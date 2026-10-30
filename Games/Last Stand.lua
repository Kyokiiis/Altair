-- Last Stand: normal-action automation. Uses the game's own canUse/useTool
-- methods, including the multiplayer mirror's permission/encoding path.
-- Economy/profile values, cooldowns and ownership checks are never overwritten.
local Model = {}
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function Model.point(x, y, city)
    return finite(x) and finite(y) and x >= 0 and y >= 0 and x <= city.W and y <= city.H
end
function Model.evac(sim, minimum, dangerRadius)
    local best, bestScore
    for _, site in ipairs(sim.city.evacSites or {}) do
        local occupied, people, danger = false, 0, 0
        for _, active in ipairs(sim.evacs or {}) do
            if active.site == site or (active.x-site.x)^2+(active.y-site.y)^2 < 16 then occupied = true break end
        end
        if not occupied then
            for _, agent in ipairs(sim.agents) do
                if not agent.dead and not agent.stashed then
                    local d = (agent.x-site.x)^2 + (agent.y-site.y)^2
                    if agent.kind == "Human" and not agent.infected and d < 240^2 then people += 1 end
                    if agent.kind == "Zombie" and not agent.hidden and d < dangerRadius^2 then danger += 1 end
                end
            end
            local score = people - danger * 10
            if people >= minimum and danger == 0 and (not bestScore or score > bestScore) then best, bestScore = site, score end
        end
    end
    return best
end
function Model.target(sim, kind, minimum, radius)
    local cells = {}
    for _, a in ipairs(sim.agents) do
        local visible = kind == "Zombie" and a.kind == "Zombie" and not a.hidden
            or kind == "Infected" and a.kind == "Human" and a.infected and sim.time < (a.revealUntil or 0)
        if not a.dead and not a.stashed and visible then
            local key = math.floor(a.x/radius)..":"..math.floor(a.y/radius)
            local cell = cells[key] or {x=0,y=0,count=0}
            cells[key] = cell; cell.x += a.x; cell.y += a.y; cell.count += 1
        end
    end
    local best
    for _, c in pairs(cells) do if c.count >= minimum and (not best or c.count > best.count) then best = c end end
    if best then return {x=best.x/best.count,y=best.y/best.count,count=best.count} end
end
function Model.step(value, city)
    if type(value) ~= "table" or type(value.tool) ~= "string" or not Model.point(value.x,value.y,city) then return nil end
    return {tool=value.tool,x=value.x,y=value.y}
end
function Model.report(sim)
    for _, site in ipairs(sim.sites or {}) do
        if site.reported then
            local covered = false
            for _, drone in ipairs(sim.recons or {}) do
                if (drone.x-site.x)^2+(drone.y-site.y)^2 < 90^2 then covered=true break end
            end
            if not covered then return site end
        end
    end
end
function Model.roundKey(sim)
    local level=sim.level or {}
    return tostring(level.map or "manhattan")..":"..tostring(level.id or level.name or level.stars or "")
end
-- The command-line regression suite can exercise planning without Roblox.
if not game then return Model end
if game.GameId ~= 10769802973 then warn("Last Stand | This module is for universe 10769802973."); return end
local env = getgenv()
if env.LastStand and env.LastStand.Destroy then env.LastStand:Destroy() end
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Http = game:GetService("HttpService")
local read = getupvalues or (debug and debug.getupvalues)
assert(type(read)=="function" and type(getconnections)=="function", "Last Stand requires Volt's connection inspection support.")
local state = {alive=true,callbacks={},lastScan=-100,queue={},index=1,playing=false,connections={},history={},
    autoEvac=false,autoRecon=false,autoMedics=false,autoStrike=false,reserve=250,minEvac=12,dangerRadius=90,
    minInfected=3,minZombies=6,lastAttempt=-100,pending={},selected="Evac",marker=nil,session=nil,submitted=0,
    autoRepeat=false,autoHQ=false,autoSupplies=false,lastHQ=-100,controls={},rounds=0}
env.LastStand = state
local window, logView
local function log(message)
    local line = os.date("%H:%M:%S").."  "..tostring(message)
    table.insert(state.history,line); if #state.history > 100 then table.remove(state.history,1) end
    if logView then pcall(logView.Append,logView,line) end
end
local function notify(title, text)
    local api = env.Altair
    if type(api)=="table" and type(api.QueueNotification)=="function" then
        local ok = pcall(api.QueueNotification,title,tostring(text)); if ok then return end
    end
    if window and not window.unloaded then pcall(window.Notify,window,{title=title,content=tostring(text),duration=4}) end
end
local function isSim(v)
    return type(v)=="table" and type(rawget(v,"agents"))=="table" and type(rawget(v,"toolCd"))=="table" and type(rawget(v,"budget"))=="number"
end
local function scan()
    state.callbacks = {}; state.lastScan = os.clock()
    for _, connection in ipairs(getconnections(RunService.RenderStepped)) do
        local fn = connection.Function
        if type(fn)=="function" then
            local ok, values = pcall(read,fn)
            if ok then for _, value in pairs(values) do if isSim(value) then table.insert(state.callbacks,fn);break end end end
        end
    end
end
local function context()
    -- Volt may expose a snapshot of a callback's upvalue bindings. Refresh the
    -- callback handles too, so a replay cannot keep acting on the previous sim.
    if os.clock()-state.lastScan>2 then scan() end
    local result
    for _, fn in ipairs(state.callbacks) do
        local ok, values = pcall(read,fn)
        if ok then
            local ctx = {}
            for _, value in pairs(values) do
                if isSim(value) then ctx.sim=value
                elseif type(value)=="table" then
                    if type(rawget(value,"ALL_TOOLS"))=="table" then ctx.config=value end
                    if typeof(rawget(value,"world"))=="Instance" and type(rawget(value,"onTool"))=="function" then ctx.hud=value end
                    if type(rawget(value,"ctx"))=="table" and typeof(rawget(value,"remotes"))=="Instance" then ctx.mp=value end
                end
            end
            if ctx.sim and ctx.hud and ctx.config then
                if result and result.sim~=ctx.sim then return nil,"Multiple active simulations; reload the game module." end
                result=ctx
            end
        end
    end
    if not result then
        if os.clock()-state.lastScan>3 then scan() end
        return nil,"Start a level first."
    end
    return result
end
local function getTool(ctx, id)
    local equipped=false
    for key,value in pairs(ctx.hud.loadoutIds or {}) do if value==id or key==id then equipped=true break end end
    if not equipped then return nil,"Tool is not in this match's loadout: "..id end
    for _, tool in pairs(ctx.config.ALL_TOOLS) do if tool.id==id then return tool end end
    return nil,"Unknown tool: "..id
end
local pointTools = {Evac=true,Recon=true,Medics=true,Strike=true,Fort=true,Depot=true,ReconTower=true,Rooftop=true}
local function usable(ctx)
    if ctx.sim.over then return false,"Match ended." end
    if ctx.hud.overlay and ctx.hud.overlay.Visible then return false,"Close the briefing/menu first." end
    if ctx.sim.__mpMirror and (not ctx.mp or not ctx.mp.game or not ctx.mp.ready or ctx.mp.sim~=ctx.sim) then return false,"Waiting for multiplayer state." end
    return true
end
local function submit(ctx, id, x, y, reserve)
    local ready, reason = usable(ctx); if not ready then return false,reason end
    if not pointTools[id] or not Model.point(x,y,ctx.sim.city) then return false,"Invalid point placement." end
    local tool, missing = getTool(ctx,id); if not tool then return false,missing end
    local effective = ctx.sim:effective(tool)
    if ctx.sim.budget-(effective.cost or 0) < reserve then return false,"Waiting for budget above reserve." end
    local can, why = ctx.sim:canUse(effective); if not can then return false,why end
    if os.clock()-(state.pending[id] or -100) < 3 then return false,"Waiting for the previous request." end
    local accepted, rejection = ctx.sim:useTool(tool,x,y)
    state.pending[id]=os.clock()
    if not accepted then return false,rejection or "Placement rejected." end
    state.submitted+=1
    log(string.format("%s %s at %.0f, %.0f",ctx.sim.__mpMirror and "Sent" or "Placed",tool.name or id,x,y))
    return true
end
function state:GetContext() return context() end
function state:UseTool(id,x,y)
    local ctx,err=context(); assert(ctx,err)
    return submit(ctx,id,x,y,0)
end
function state:MarkAtCursor()
    local ctx,err=context(); assert(ctx,err)
    local mouse=Input:GetMouseLocation()-GuiService:GetGuiInset()
    local world=ctx.hud.world
    local delta=mouse-world.AbsolutePosition
    local x=delta.X/world.AbsoluteSize.X*ctx.sim.city.W
    local y=delta.Y/world.AbsoluteSize.Y*ctx.sim.city.H
    assert(Model.point(x,y,ctx.sim.city),"Move the pointer over the city, then press F8.")
    self.marker={x=x,y=y}; log(string.format("Marked %.0f, %.0f",x,y));return self.marker
end
function state:Enqueue()
    assert(self.marker,"Mark a map position with F8 first.")
    assert(#self.queue<100,"Queue limit is 100 placements.")
    table.insert(self.queue,{tool=self.selected,x=self.marker.x,y=self.marker.y})
    log("Queued "..self.selected.." (#"..#self.queue..")")
end
function state:Stop()
    self.playing=false;self.autoEvac=false;self.autoRecon=false;self.autoMedics=false;self.autoStrike=false;self.autoRepeat=false
    self.autoHQ=false;self.autoSupplies=false
    self.expectedRound=nil;self.replayAt=nil
    for _,control in pairs(self.controls) do pcall(function() control:Set(false,true) end) end
    log("All automation stopped.")
end
function state:Destroy()
    if not self.alive then return end
    self:Stop();self.alive=false
    for _,connection in ipairs(self.connections) do connection:Disconnect() end
    if window and not window.unloaded then window:Unload() end
    if env.LastStand==self then env.LastStand=nil end
end
local function guarded(fn)
    return function(...)
        local ok,result=pcall(fn,...)
        if not ok then log(result);notify("Last Stand",result) end
    end
end
local function pressGameButton(ctx, wanted)
    if state.uiPending then return false end
    if not ctx.hud.overlay or not ctx.hud.overlay.Visible then return false end
    for _,button in ipairs(ctx.hud.overlay:GetDescendants()) do
        if button:IsA("TextButton") and wanted[button.Text] then
            local visible=button.Visible;local parent=button.Parent
            while parent and parent:IsA("GuiObject") do visible=visible and parent.Visible;parent=parent.Parent end
            if visible then
                for _,connection in ipairs(getconnections(button.MouseButton1Click)) do
                    if type(connection.Function)=="function" then
                        state.uiPending=true
                        local callback=connection.Function
                        -- Level loading may yield or retire the game's calling
                        -- thread. Keep it outside the automation scheduler.
                        task.defer(function()
                            if not state.alive then state.uiPending=false;return end
                            local ok,err=pcall(callback)
                            state.uiPending=false
                            if not ok then state.lastError=tostring(err);log("Game menu action failed: "..state.lastError);state:Stop() end
                        end)
                        return true
                    end
                end
            end
        end
    end
    return false
end
local function roundKey(sim)
    return Model.roundKey(sim)
end
local loaded, Rayfield = pcall(function() return assert(loadstring(game:HttpGet("https://sirius.menu/gen2")))() end)
if not loaded then state:Destroy();error("Last Stand | Rayfield failed to load: "..tostring(Rayfield)) end
local built, buildError = pcall(function()
    window=Rayfield:CreateWindow({name="Last Stand",subtitle="Altair · deployment and evacuation",icon="shield",sidebarLayout=true,
        configuration={autoSave=false,autoLoad=false,fileName="LastStand"}})
    state.window=window
    local overview=window:CreateTab({name="Match",icon="activity"})
    local status=overview:CreateText({name="Match status",text="Reading the active level…"})
    local budget=overview:CreateStat({name="Budget",prefix="$",value=0,changeMode="absolute"})
    local evacuated=overview:CreateStat({name="Evacuated",value=0,changeMode="absolute"})
    overview:CreateText({name="Normal game actions",text="Placements use your equipped tools and obey the game's costs, cooldowns, valid sites, and multiplayer permissions. Automation starts off. F10 stops everything."})
    overview:CreateButton({name="Stop all automation",callback=function() state:Stop() end})
    local auto=window:CreateTab({name="Automation",icon="repeat"})
    state.controls.autoEvac=auto:CreateToggle({name="Automatic evacuation",value=false,callback=function(v) state.autoEvac=v end,
        description="Rotate between free green evac sites with nearby civilians. Avoid visible zombies and active evac boats."})
    auto:CreateSlider({name="Keep budget reserve",range={0,2000},increment=25,value=250,suffix="$",callback=function(v) state.reserve=v end})
    auto:CreateSlider({name="Minimum civilians near evac",range={1,100},increment=1,value=12,callback=function(v) state.minEvac=v end})
    state.controls.autoRecon=auto:CreateToggle({name="Recon reported outbreaks",value=false,callback=function(v) state.autoRecon=v end,
        description="Send recon to reported outbreak locations without an active nearby drone."})
    state.controls.autoMedics=auto:CreateToggle({name="Treat revealed infected",value=false,callback=function(v) state.autoMedics=v end,
        description="Use Vaccine Shell on clusters already revealed by reconnaissance."})
    state.controls.autoStrike=auto:CreateToggle({name="Reinforce visible outbreaks",value=false,callback=function(v) state.autoStrike=v end,
        description="Deploy Strike Team near visible zombie clusters when the loadout, budget, and cooldown allow it."})
    state.controls.autoHQ=auto:CreateToggle({name="Send owned HQ teams to visible threats",value=false,callback=function(v) state.autoHQ=v end,
        description="Move your existing squads toward revealed threats. Uses normal squad orders; co-op ownership checks are preserved."})
    state.controls.autoSupplies=auto:CreateToggle({name="Collect available supply drops",value=false,callback=function(v) state.autoSupplies=v end,
        description="Click existing, unexpired supply drops using the game's normal pickup action. Excludes candy crates."})
    state.controls.autoRepeat=auto:CreateToggle({name="Repeat this level",value=false,callback=function(v) state.autoRepeat=v end,
        description="Single-player: use the normal Play Again / Retry result button, then Begin Response. Keeps the same map and difficulty. No paid restart or mid-match reset."})
    auto:CreateButton({name="Enable equipped gameplay automations",callback=guarded(function()
        local ctx,err=context();assert(ctx,err)
        assert(not ctx.sim.level.tutorial,"Finish the tutorial first.")
        for flag,id in pairs({autoEvac="Evac",autoRecon="Recon",autoMedics="Medics",autoStrike="Strike"}) do
            state.controls[flag]:Set(getTool(ctx,id)~=nil)
        end
        state.controls.autoHQ:Set(true);state.controls.autoSupplies:Set(true)
        notify("Gameplay automation enabled","Only equipped tools are enabled. Level repeat is a separate toggle; F10 stops everything.")
    end)})
    auto:CreateText({name="Match transitions",text="Repeat uses the game's ordinary result flow. Match changes outside that flow stop automation. Rewards and research caps remain controlled by the game. A disconnect or game update stops the script."})
    auto:CreateButton({name="Equip standard loadout during briefing",callback=guarded(function()
        local ctx,err=context();assert(ctx,err)
        assert(not ctx.sim.__mpMirror,"Change the co-op loadout through the game's lobby.")
        local briefing=false
        if ctx.hud.overlay.Visible then
            for _,v in ipairs(ctx.hud.overlay:GetDescendants()) do
                if v:IsA("TextButton") and v.Text=="Begin Response" then briefing=true break end
            end
        end
        assert(briefing,"Return to the level briefing before changing the loadout.")
        ctx.hud.onLoadout(table.clone(ctx.config.LOADOUT.DEFAULT))
        if type(ctx.hud.pickerRefresh)=="function" then ctx.hud.pickerRefresh() end
        notify("Standard loadout equipped","Includes Recon, Vaccine Shell, Evac Point, and Strike Team. Begin Response when ready.")
    end)})
    local deploy=window:CreateTab({name="Placements",icon="map-pin"})
    local toolPicker=deploy:CreateDropdown({name="Equipped point tool",options={"Evac"},value="Evac",callback=function(v) state.selected=v end})
    deploy:CreateText({name="Record a placement",text="Hover over a location on the map and press F8 to mark it. F9 adds the selected tool at that point to the queue. Only equipped tools can be used."})
    deploy:CreateButton({name="Add marked placement",callback=guarded(function() state:Enqueue() end)})
    deploy:CreateButton({name="Deploy selected at marker",callback=guarded(function()
        assert(state.marker,"Mark a map point with F8 first.")
        local ok,err=state:UseTool(state.selected,state.marker.x,state.marker.y);assert(ok,err)
    end)})
    deploy:CreateButton({name="Run / resume placement queue",callback=guarded(function()
        assert(#state.queue>0 and state.index<=#state.queue,"Add new placements first.")
        local ctx,err=context();assert(ctx,err);state.session=ctx.sim;state.playing=true;state.waitSince=os.clock()
    end)})
    deploy:CreateButton({name="Clear queue",callback=function() state.playing=false;state.queue={};state.index=1;log("Queue cleared.") end})
    deploy:CreateButton({name="Save placement plan",callback=guarded(function()
        assert(writefile and makefolder and isfolder,"Filesystem unavailable.")
        if not isfolder("Altair") then makefolder("Altair") end
        if not isfolder("Altair/LastStand") then makefolder("Altair/LastStand") end
        local ctx,err=context();assert(ctx,err)
        writefile("Altair/LastStand/plan.json",Http:JSONEncode({version=1,map=ctx.sim.level.map,steps=state.queue}))
        notify("Plan saved","Altair/LastStand/plan.json")
    end)})
    deploy:CreateButton({name="Load placement plan",callback=guarded(function()
        assert(readfile,"Filesystem unavailable.")
        local plan=Http:JSONDecode(readfile("Altair/LastStand/plan.json"));local ctx,err=context();assert(ctx,err)
        assert(type(plan)=="table" and plan.version==1 and plan.map==ctx.sim.level.map,"Plan is for another map or version.")
        assert(type(plan.steps)=="table" and #plan.steps<=100,"Invalid plan.")
        local steps={};for _,v in ipairs(plan.steps) do local step=Model.step(v,ctx.sim.city);assert(step and pointTools[step.tool],"Invalid placement in plan.");table.insert(steps,step) end
        state.playing=false;state.queue=steps;state.index=1;log("Loaded "..#steps.." placements.")
    end)})
    local debugTab=window:CreateTab({name="Log",icon="list"})
    logView=debugTab:CreateConsole({name="Action log",height=240,maxLines=100,follow=true})
    debugTab:CreateButton({name="Refresh game binding",callback=guarded(function() scan();local ctx,err=context();assert(ctx,err);notify("Bound",ctx.sim.__mpMirror and "Multiplayer server mirror" or "Single-player gameplay simulation") end)})
    debugTab:CreateButton({name="Copy action log",callback=guarded(function() assert(setclipboard,"Clipboard unavailable.");setclipboard(table.concat(state.history,"\n")) end)})
    debugTab:CreateButton({name="Unload Last Stand",callback=function() state:Destroy() end})
    local function update()
        if not state.alive or window.unloaded then return false end
        state.lastTick=os.clock()
        local ctx,err=context()
        if not ctx then status:Set(err);return true end
        local sim=ctx.sim
        if state.bound and state.bound~=sim then
            if state.autoRepeat and state.expectedRound==roundKey(sim) then
                state.playing=false;state.index=1;state.rounds+=1;log("Replay level loaded.")
            else state:Stop();log("New match detected; review settings before restarting automation.") end
            state.pending={}
        end
        state.bound=sim
        local choices={}
        for _,tool in pairs(ctx.config.ALL_TOOLS) do if pointTools[tool.id] and getTool(ctx,tool.id) then table.insert(choices,tool.id) end end
        table.sort(choices)
        local signature=table.concat(choices,",")
        if signature~=state.loadoutSignature then
            state.loadoutSignature=signature;toolPicker:Refresh(choices)
            if not table.find(choices,state.selected) then state.selected=choices[1];if state.selected then toolPicker:Set(state.selected,true) end end
        end
        budget:Set(math.floor(sim.budget));evacuated:Set(sim.stats and (sim.stats.evacuated or sim.stats.safe) or sim.safe or 0)
        status:Set(string.format("%s · Day %d · %s\nQueue %d/%d · %d actions submitted",sim.__mpMirror and "Multiplayer" or "Single player",sim.day or 1,sim.over and "Ended" or "Active",math.min(state.index,#state.queue),#state.queue,state.submitted))
        if sim.over then
            state.playing=false
            if state.autoRepeat and not sim.__mpMirror and not sim.level.tutorial then
                state.replayAt=state.replayAt or os.clock()+5
                if os.clock()>=state.replayAt then
                    state.expectedRound=roundKey(sim)
                    if pressGameButton(ctx,{["Play Again"]=true,Retry=true}) then
                        state.replayAt=nil;state.beginDeadline=os.clock()+30;log("Requested normal level replay.")
                    end
                end
            end
            return true
        end
        if sim.level and sim.level.tutorial then
            if state.playing or state.autoEvac or state.autoRecon or state.autoMedics or state.autoStrike or state.autoHQ or state.autoSupplies or state.autoRepeat then state:Stop();log("Complete the tutorial manually before enabling automation.") end
            return true
        end
        if state.autoRepeat and state.expectedRound then
            if roundKey(sim)~=state.expectedRound then
                log("Replay changed context: "..tostring(state.expectedRound).." -> "..roundKey(sim))
                state:Stop();return true
            end
            if pressGameButton(ctx,{["Begin Response"]=true}) then
                state.expectedRound=nil;state.beginDeadline=nil;log("Response begun; automation resumed.")
            elseif state.beginDeadline and os.clock()>state.beginDeadline then
                state:Stop();log("Replay timed out. Start the next response manually.")
            end
        end
        if os.clock()-state.lastAttempt<2 then return true end
        state.lastAttempt=os.clock()
        local ready=usable(ctx);if not ready then return true end
        if state.autoHQ and os.clock()-state.lastHQ>=8 then
            state.lastHQ=os.clock()
            local threat=Model.target(sim,"Zombie",1,85) or Model.target(sim,"Infected",1,65)
            if threat then
                local squads={sim.mainSquad}
                if sim.__mpMirror then
                    local admin=ctx.mp.info and ctx.mp.info.admins[ctx.mp.info.me]
                    squads=admin and admin.squads or {}
                end
                for _,id in ipairs(squads) do
                    if not sim.__mpMirror or ctx.mp:ownsSquad(id) then
                        local ok,reason=sim:moveSquad(id,threat.x,threat.y)
                        if ok then log((sim.__mpMirror and "Sent" or "Ordered").." HQ squad "..tostring(id))
                        elseif reason~=state.lastHQReason then log(reason);state.lastHQReason=reason end
                    end
                end
            end
        end
        if state.autoSupplies then
            for _,crate in ipairs(sim.crates or {}) do
                if not crate.candy and not crate.dead and sim.time<(crate.expire or 0) then
                    if sim:claimCrate(crate.x,crate.y) then log(sim.__mpMirror and "Sent supply pickup." or "Collected a supply drop.") end
                    break
                end
            end
        end
        if state.playing then
            if state.session~=sim then state:Stop();return true end
            local step=state.queue[state.index]
            if not step then state.playing=false;log("Placement queue finished.");return true end
            local ok,reason=submit(ctx,step.tool,step.x,step.y,state.reserve)
            if ok then state.index+=1;state.waitSince=os.clock()
            elseif os.clock()-(state.waitSince or os.clock())>90 then state.playing=false;log("Queue paused: "..tostring(reason)) end
            return true
        end
        local candidate,id
        local function available(toolId)
            local tool=getTool(ctx,toolId)
            if not tool or os.clock()-(state.pending[toolId] or -100)<3 then return false end
            local effective=sim:effective(tool)
            return sim.budget-(effective.cost or 0)>=state.reserve and sim:canUse(effective)
        end
        if state.autoMedics and available("Medics") then candidate=Model.target(sim,"Infected",state.minInfected,65);id="Medics" end
        if not candidate and state.autoEvac and available("Evac") then candidate=Model.evac(sim,state.minEvac,state.dangerRadius);id="Evac" end
        if not candidate and state.autoRecon and available("Recon") then candidate=Model.report(sim);id="Recon" end
        if not candidate and state.autoStrike and available("Strike") then candidate=Model.target(sim,"Zombie",state.minZombies,85);id="Strike" end
        if candidate then
            local ok,reason=submit(ctx,id,candidate.x,candidate.y,state.reserve)
            if not ok and reason~=state.lastWait then log(reason);state.lastWait=reason end
            if ok then state.lastWait=nil end
        end
        return true
    end
    table.insert(state.connections,Input.InputBegan:Connect(function(input,processed)
        if input.KeyCode==Enum.KeyCode.F10 then state:Stop();notify("Last Stand","All automation stopped.");return end
        if processed or Input:GetFocusedTextBox() then return end
        if input.KeyCode==Enum.KeyCode.F8 then guarded(function() state:MarkAtCursor() end)()
        elseif input.KeyCode==Enum.KeyCode.F9 then guarded(function() state:Enqueue() end)() end
    end))
    state.runner=task.spawn(function()
        while state.alive and not window.unloaded do
            local ok,keep=pcall(update)
            if not ok then
                state.lastError=tostring(keep)
                state:Stop();log("Update failed: "..state.lastError);notify("Last Stand paused",state.lastError);break
            end
            if not keep then break end
            task.wait(0.75)
        end
        if state.alive then state:Destroy() end
    end)
end)
if not built then state:Destroy();error("Last Stand | UI failed: "..tostring(buildError)) end
notify("Last Stand ready","Automation starts off. Finish the tutorial, then configure your loadout and reserve.")
return state
