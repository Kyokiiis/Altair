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
            for _,collection in ipairs({sim.recons or {},sim.reconTowers or {}}) do
                for _,drone in ipairs(collection) do
                    if not drone.dead and (drone.x-site.x)^2+(drone.y-site.y)^2 < (drone.r or drone.radius or 90)^2 then covered=true break end
                end
                if covered then break end
            end
            if not covered then return site end
        end
    end
end
function Model.roundKey(sim)
    local level=sim.level or {}
    return tostring(level.map or "manhattan")..":"..tostring(level.kitMap or "")..":"..tostring(level.id or level.name or level.stars or "")
end
local function distance2(a,b) return (a.x-b.x)^2+(a.y-b.y)^2 end
-- All rescue identifiers come from map sites / roofs, never the screen layout.
function Model.rescue(city, active)
    if active.dead then return nil end
    if active.rooftop then
        local roof=city.roofs and city.roofs[active.roof]
        if not roof then return nil end
        return {tool="Rooftop",key="roof:"..tostring(active.roof),roof=active.roof,x=roof[1],y=roof[2]}
    end
    for i,site in ipairs(city.evacSites or {}) do
        if site==active.site or distance2(site,active)<16 then
            return {tool="Evac",key="boat:"..i,x=site.x,y=site.y}
        end
    end
end
function Model.newRescues() return {seen={},own={},points={},order={},cursor={}} end
function Model.observeRescues(book,sim,enabled,fullFarm,now)
    local live,activeKeys={},{}
    for _,active in ipairs(sim.evacs or {}) do
        local point=Model.rescue(sim.city,active)
        if point then
            -- Multiplayer snapshots replace table identities; expiration is stable.
            local token=point.key..":"..tostring(active.expire)
            live[token]=true
            activeKeys[point.key]=true
            if not book.seen[token] and not fullFarm and enabled[point.tool]
                and not book.own[point.key] and not book.points[point.key] then
                book.points[point.key]=point;table.insert(book.order,point.key)
            end
        end
    end
    book.seen=live
    for key,untilTime in pairs(book.own) do if now>untilTime and not activeKeys[key] then book.own[key]=nil end end
end
function Model.issuedRescue(book,city,id,x,y,now)
    local key
    if id=="Evac" then
        local closest,d
        for i,site in ipairs(city.evacSites or {}) do
            local dd=(site.x-x)^2+(site.y-y)^2
            if not d or dd<d then closest,d=i,dd end
        end
        if closest then key="boat:"..closest end
    elseif id=="Rooftop" and city.roofAt then
        local roof=city:roofAt(x,y);if roof then key="roof:"..tostring(roof) end
    end
    if key then book.own[key]=now+10 end
end
function Model.repeatRescue(book,sim,id)
    local busy={}
    for _,active in ipairs(sim.evacs or {}) do
        local point=Model.rescue(sim.city,active);if point then busy[point.key]=true end
    end
    local start=book.cursor[id] or 0
    for n=1,#book.order do
        local index=(start+n-1)%#book.order+1
        local point=book.points[book.order[index]]
        if point and point.tool==id and not busy[point.key]
            and (not point.roof or not ((sim.fires or {})[point.roof] or (sim.charred or {})[point.roof])) then
            return point,index
        end
    end
end
function Model.clusters(sim,kind,radius,includeUnrevealed)
    local cells={}
    for _,a in ipairs(sim.agents or {}) do
        local visible=kind=="Healthy" and a.kind=="Human" and not a.infected
            or kind=="Zombie" and a.kind=="Zombie" and not a.hidden
            or kind=="Infected" and a.kind=="Human" and a.infected and (includeUnrevealed or sim.time<(a.revealUntil or 0))
        if visible and not a.dead and not a.stashed then
            local key=math.floor(a.x/radius)..":"..math.floor(a.y/radius)
            local c=cells[key] or {x=0,y=0,count=0,agent=a,specials={},threat=0};cells[key]=c
            c.x+=a.x;c.y+=a.y;c.count+=1
            if kind=="Zombie" then
                local weight=Model.specialWeight(a)
                c.threat+=weight
                if a.special then c.specials[a.special]=(c.specials[a.special] or 0)+1 end
                if weight>Model.specialWeight(c.agent) then c.agent=a end
            end
        end
    end
    local list={}
    for _,c in pairs(cells) do c.x/=c.count;c.y/=c.count;table.insert(list,c) end
    table.sort(list,function(a,b) if a.count~=b.count then return a.count>b.count end;if a.x~=b.x then return a.x<b.x end;return a.y<b.y end)
    return list
end
function Model.rooftop(sim,minimum,radius)
    local busy={}
    for _,e in ipairs(sim.evacs or {}) do if e.rooftop and not e.dead then busy[e.roof]=true end end
    local nearby={}
    -- Spatial bins keep this linear in people + a small neighborhood per roof.
    for _,a in ipairs(sim.agents or {}) do
        if a.kind=="Human" and not a.dead and not a.stashed and not a.infected then
            local key=math.floor(a.x/radius)..":"..math.floor(a.y/radius)
            nearby[key]=nearby[key] or {};table.insert(nearby[key],a)
        end
    end
    local best,count
    for id,roof in ipairs(sim.city.roofs or {}) do
        if not busy[id] and not (sim.fires or {})[id] and not (sim.charred or {})[id] then
            local x,y=sim.city:nearestWalkable(roof[1],roof[2])
            if x then
                local gx,gy=math.floor(x/radius),math.floor(y/radius);local people=0
                for dx=-1,1 do for dy=-1,1 do
                    for _,a in ipairs(nearby[(gx+dx)..":"..(gy+dy)] or {}) do
                        if (a.x-x)^2+(a.y-y)^2<=radius^2 then people+=1 end
                    end
                end end
                if people>=minimum and (not count or people>count) then best={x=roof[1],y=roof[2],roof=id};count=people end
            end
        end
    end
    return best
end
function Model.hqTarget(sim,origin,excluded)
    local healthy=Model.clusters(sim,"Healthy",160)
    local best,score
    for _,cluster in ipairs(Model.clusters(sim,"Zombie",100)) do
        local a=cluster.agent
        if not excluded[a.id or a] and Model.specialWeight(a)>0 then
            local risk=cluster.threat or cluster.count
            for _,people in ipairs(healthy) do if distance2(cluster,people)<280^2 then risk+=people.count*2 end end
            for _,evac in ipairs(sim.evacs or {}) do if not evac.dead and distance2(cluster,evac)<250^2 then risk+=50 end end
            for _,tent in ipairs(sim.tents or {}) do if not tent.dead and distance2(cluster,tent)<200^2 then risk+=120 end end
            for _,depot in ipairs(sim.depots or {}) do if not depot.dead and distance2(cluster,depot)<200^2 then risk+=180 end end
            if a.special=="wrecker" then
                for _,wall in ipairs(sim.walls or {}) do
                    if not wall.dead and (wall.hp or 1)>0 and (a.x-(wall.x1+wall.x2)/2)^2+(a.y-(wall.y1+wall.y2)/2)^2<180^2 then risk+=60 break end
                end
            end
            local priority=risk/(1+math.sqrt(distance2(origin,a))/450)
            if not score or priority>score then best,score=a,priority end
        end
    end
    return best
end
function Model.specialWeight(agent)
    local kind=agent.special
    if kind=="weeper" then return agent.weeperMood=="angry" and 10 or 0 end
    if agent.kind=="Zombie" and not agent.hidden and agent.hiddenUntil then return 8 end -- publicly revealed outbreak starter
    return ({runner=3,screamer=5,bloater=7,wrecker=6,brute=3,boss=8,hive=8,necro=10,swimmer=2})[kind] or (kind and 2 or 1)
end
function Model.medicTarget(sim,origin,includeUnrevealed)
    local best,bestDistance;local zombies={}
    for _,z in ipairs(sim.agents or {}) do
        if z.kind=="Zombie" and not z.dead and (includeUnrevealed or not z.hidden) then table.insert(zombies,z) end
    end
    for _,a in ipairs(sim.agents or {}) do
        if a.kind~="Human" or a.dead or a.stashed or not a.infected or a.patientZero or a.bossSeed or a.tentHeld or (not includeUnrevealed and sim.time>=(a.revealUntil or 0)) then continue end
        local d=distance2(origin,a);if bestDistance and d>=bestDistance then continue end
        local danger=false
        for _,z in ipairs(zombies) do
            if distance2(a,z)<100^2 then danger=true break end
        end
        if not danger then best,bestDistance=a,d end
    end
    return best
end
function Model.support(sim,minimum,deployments)
    local best,score
    for _,c in ipairs(Model.clusters(sim,"Zombie",95)) do
        local a=c.agent;local weight=Model.specialWeight(a)
        if weight<=0 or (c.count<minimum and weight<3) then continue end
        local incoming=false
        for _,drop in ipairs(deployments or {}) do if drop.untilTime>sim.time and distance2(drop,c)<150^2 then incoming=true break end end
        if incoming then continue end
        local soldiers=0
        for _,unit in ipairs(sim.agents or {}) do
            if unit.kind=="Soldier" and not unit.dead and not unit.medicTeam and distance2(unit,c)<130^2 then soldiers+=1 end
        end
        if soldiers>=3 and c.threat<=soldiers*3 then continue end
        local avoid=false
        for _,w in ipairs(sim.weepers or {}) do
            if not w.dead and w.weeperMood~="angry" and distance2(w,c)<140^2 then avoid=true break end
        end
        local value=c.threat*3+c.count-soldiers*3
        for _,tent in ipairs(sim.tents or {}) do if not tent.dead and distance2(c,tent)<220^2 then value+=80 end end
        for _,depot in ipairs(sim.depots or {}) do if not depot.dead and distance2(c,depot)<220^2 then value+=100 end end
        if not avoid and (not score or value>score) then best={x=c.x,y=c.y,special=a.special,count=c.count,seed=a.hiddenUntil~=nil};score=value end
    end
    return best
end
function Model.responseTool(target,equipped)
    local choices=(target.seed or target.special=="weeper") and {"Ghosts","Hunters","Strike"} or {"Hunters","Strike","Ghosts"}
    for _,id in ipairs(choices) do if equipped[id] then return id end end
end
function Model.reportTreatment(sim,radius,visited)
    local best,score
    for _,clue in ipairs(sim.suspects or {}) do
        local age=sim.time-(clue.born or -100)
        local single=(clue.n or 0)==1 and (sim.pop.hiddenZombies or 0)==0
        if age<0 or age>3 or (clue.expire or 0)<=sim.time or ((clue.n or 0)<2 and not single) or (clue.r or 0)>radius*1.3 then continue end
        local key=tostring(clue.born)..":"..math.floor(clue.x/60)..":"..math.floor(clue.y/60)
        if visited[key] then continue end
        local value=(clue.n or 1)/(1+(clue.r or 0)/radius)
        if not score or value>score then
            best={x=clue.x,y=clue.y,count=clue.n,reportKey=key,intelKey=math.floor(clue.x/70)..":"..math.floor(clue.y/70)};score=value
        end
    end
    return best
end
function Model.sentry(sim,point,spacing)
    for _,fort in ipairs(sim.forts or {}) do if not fort.dead and distance2(point,fort)<130^2 then return nil end end
    for _,build in ipairs(sim.builds or {}) do if build.kind=="fort" and distance2(point,build)<130^2 then return nil end end
    local best,score
    for id,roof in ipairs(sim.city.roofs or {}) do
        local p={x=roof[1],y=roof[2]};local d=distance2(point,p)
        if d>150^2 or (sim.fires or {})[id] or (sim.charred or {})[id] then continue end
        local x,y=sim.city:nearestWalkable(p.x,p.y)
        if not x or (p.x-x)^2+(p.y-y)^2>(math.max(roof[3],roof[4])/2+14)^2 then continue end
        local free=true
        for _,fort in ipairs(sim.forts or {}) do if not fort.dead and distance2(p,fort)<spacing^2 then free=false break end end
        for _,build in ipairs(sim.builds or {}) do if build.kind=="fort" and distance2(p,build)<spacing^2 then free=false break end end
        if free and (not score or d<score) then best,score=p,d end
    end
    return best
end
function Model.square(city,point,half)
    if city.W<half*2 or city.H<half*2 then return nil end
    local x=math.clamp(point.x,half,city.W-half);local y=math.clamp(point.y,half,city.H-half)
    return {{x-half,y-half},{x+half,y-half},{x+half,y+half},{x-half,y+half}}
end
function Model.gateCovered(step,walls)
    local dx,dy=step.x2-step.x,step.y2-step.y;local length=math.sqrt(dx*dx+dy*dy)
    if length<.001 then return false end
    local intervals={}
    for _,wall in ipairs(walls or {}) do
        if wall.gate and not wall.dead and (wall.hp or 1)>0 then
            local function project(x,y)
                local along=((x-step.x)*dx+(y-step.y)*dy)/length
                local across=math.abs((x-step.x)*dy-(y-step.y)*dx)/length
                return along,across
            end
            local a,acrossA=project(wall.x1,wall.y1);local b,acrossB=project(wall.x2,wall.y2)
            if acrossA<3 and acrossB<3 then table.insert(intervals,{math.min(a,b),math.max(a,b)}) end
        end
    end
    table.sort(intervals,function(a,b) return a[1]<b[1] end)
    local covered=0
    for _,interval in ipairs(intervals) do
        if interval[1]>covered+2 then return false end
        covered=math.max(covered,interval[2]);if covered>=length-2 then return true end
    end
    return false
end
function Model.preservation(sim)
    if not sim.pop or not finite(sim.startPop) or sim.startPop<=0 or not finite(sim.pop.citizens) then return nil end
    return sim.pop.citizens/sim.startPop,math.floor(sim.pop.citizens-sim.startPop*0.85)
end
function Model.policy(sim,reserve)
    local p=sim.pop or {};local ratio=Model.preservation(sim) or 1
    local zombies=p.visibleZombies or p.zombies or 0;local infected=p.infected or 0
    local hard=(sim.level.stars or 1)>=4
    local crisis=zombies>=20 or infected>=40 or ratio<.95
    local alert=zombies>0 or infected>0
    return {stage=crisis and "Containment emergency" or alert and "Contain outbreaks" or "Search / evacuate",
        reserve=math.min(reserve,crisis and 0 or hard and 40 or 100),
        build=not alert and (sim.budget or 0)>=1000 and (sim.time or 0)>30,
        roof=not crisis or (sim.budget or 0)>350,zombies=zombies,infected=infected,
        minCures=hard and infected>2 and (sim.time or 0)>35 and (sim.day or 1)<=(sim.level.surviveDays or 3) and (crisis and 4 or 2) or 1}
end
-- Tracking reports are clues the game actually displays, not hidden agent data.
function Model.intel(sim,visits,coverage)
    local best,bestScore
    for _,report in ipairs(sim.suspects or {}) do
        if (report.expire or -1)<=sim.time then continue end
        local reach=math.min(report.r or 0,coverage)
        local offsets=reach>coverage*.6 and {{0,0},{-.65,0},{.65,0},{0,-.65},{0,.65}} or {{0,0}}
        for _,offset in ipairs(offsets) do
            local x,y=report.x+offset[1]*reach,report.y+offset[2]*reach
            local key=math.floor(x/70)..":"..math.floor(y/70)
            if not Model.point(x,y,sim.city) or sim.time-(visits[key] or -100)<10 then continue end
            local covered=false
            for _,collection in ipairs({sim.recons or {},sim.reconTowers or {}}) do
                for _,drone in ipairs(collection) do
                    if not drone.dead and (drone.x-x)^2+(drone.y-y)^2<(drone.r or drone.radius or coverage)^2*.64 then covered=true break end
                end
                if covered then break end
            end
            local score=(report.n or 1)*10+(report.born or 0)*.01
            if not covered and (not bestScore or score>bestScore) then best={x=x,y=y,intelKey=key};bestScore=score end
        end
    end
    return best
end
function Model.sourceIntel(sim,coverage)
    local best,priority
    for _,a in ipairs(sim.agents or {}) do
        if a.dead or a.stashed or not (a.kind=="Zombie" and a.hidden or a.kind=="Human" and (a.patientZero or a.bossSeed)) then continue end
        local covered=false
        for _,list in ipairs({sim.recons or {},sim.reconTowers or {}}) do
            for _,drone in ipairs(list) do
                if not drone.dead and distance2(a,drone)<((drone.r or drone.radius or coverage)*.8)^2 then covered=true break end
            end
            if covered then break end
        end
        local value=a.kind=="Zombie" and 100 or 1
        if not covered and (not priority or value>priority) then best={x=a.x,y=a.y};priority=value end
    end
    return best
end
function Model.treatment(sim,radius,doses,includeUnrevealed)
    local groups=Model.clusters(sim,"Infected",radius,includeUnrevealed)
    if #groups==0 then return nil end
    local bins={}
    for _,a in ipairs(sim.agents or {}) do
        if a.kind=="Human" and not a.dead and not a.stashed and not a.patientZero and not a.bossSeed
            and ((a.immuneUntil or 0)<=sim.time or (a.infected and (includeUnrevealed or (a.revealUntil or 0)>sim.time))) then
            local key=math.floor(a.x/radius)..":"..math.floor(a.y/radius)
            bins[key]=bins[key] or {};table.insert(bins[key],a)
        end
    end
    local best,bestScore
    for i=1,math.min(#groups,32) do
        local g=groups[i]
        for _,point in ipairs({g,g.agent}) do
            if point.patientZero or point.bossSeed then continue end
            local nearby={};local gx,gy=math.floor(point.x/radius),math.floor(point.y/radius)
            for dx=-1,1 do for dy=-1,1 do
                for _,a in ipairs(bins[(gx+dx)..":"..(gy+dy)] or {}) do
                    local d=distance2(point,a)
                    if d<=radius^2 then table.insert(nearby,{a=a,d=d}) end
                end
            end end
            table.sort(nearby,function(a,b)return a.d<b.d end)
            local cured,protected=0,math.min(doses,#nearby)
            for n=1,protected do
                local a=nearby[n].a
                if a.infected and (includeUnrevealed or (a.revealUntil or 0)>sim.time) then cured+=1 end
            end
            local score=cured*100+protected*.1
            if cured>0 and (not bestScore or score>bestScore) then best={x=point.x,y=point.y,count=cured};bestScore=score end
        end
    end
    return best
end
function Model.clinic(sim,pullRange)
    local groups={}
    for _,a in ipairs(sim.agents or {}) do
        if a.kind=="Human" and not a.dead and not a.stashed and (a.immuneUntil or 0)<=sim.time then
            local key=math.floor(a.x/160)..":"..math.floor(a.y/160)
            local g=groups[key] or {x=0,y=0,count=0};groups[key]=g;g.x+=a.x;g.y+=a.y;g.count+=1
        end
    end
    local best,score
    for _,g in pairs(groups) do
        if g.count<12 then continue end;g.x/=g.count;g.y/=g.count
        local x,y=sim.city:nearestWalkable(g.x,g.y);if not x then continue end
        local point={x=x,y=y};local covered=false;local danger,soldiers=0,0
        for _,tent in ipairs(sim.tents or {}) do if not tent.dead and distance2(point,tent)<(pullRange*.8)^2 then covered=true break end end
        if covered then continue end
        for _,a in ipairs(sim.agents or {}) do
            if not a.dead and distance2(a,point)<150^2 then
                if a.kind=="Zombie" and not a.hidden then danger+=Model.specialWeight(a) end
                if a.kind=="Soldier" and not a.medicTeam then soldiers+=1 end
            end
        end
        if danger>math.max(2,soldiers*3) then continue end
        local value=g.count+soldiers*3-danger*5
        for _,clue in ipairs(sim.suspects or {}) do if (clue.expire or 0)>sim.time and distance2(clue,point)<200^2 then value+=(clue.n or 1)*2 end end
        if not score or value>score then best,score=point,value end
    end
    return best
end
function Model.pickups(sim,supplies,candy,cap)
    local list={}
    for _,crate in ipairs(sim.crates or {}) do
        if not crate.dead and (crate.expire or 0)>sim.time
            and ((crate.candy and candy and sim.isNight and (sim.candyCollected or 0)<cap) or (not crate.candy and supplies)) then
            table.insert(list,crate)
        end
    end
    table.sort(list,function(a,b)if not not a.candy~=not not b.candy then return not not a.candy end;return a.expire<b.expire end)
    return list
end
function Model.loadout(config,profile,pass,noTools)
    profile=profile or {};local owned=profile.unlocks or {};local upgrades=profile.upgrades or {}
    local capacity=math.min((config.LOADOUT.SLOTS or 9)+((upgrades.toolSlot or 0)>=1 and 1 or 0)+(pass and 1 or 0),config.LOADOUT.MAX_SLOTS or 11)
    local byId={};for _,t in ipairs(config.ALL_TOOLS) do byId[t.id]=t end
    local function allowed(id)
        local t=byId[id]
        return t and not (noTools or {})[id] and not t.gamepass and (not (t.unlock or t.crate or t.candyUnlock) or owned[id]==true)
    end
    local locked=config.LOADOUT.LOCKED;local reserve=locked and allowed(locked) and 1 or 0;local kit={}
    for _,id in ipairs({"Recon","Medics","Airstrike","Evac","Tent","Hunters","Ghosts","Rooftop","Depot","Gate","Fort","Strike","Wall"}) do
        if #kit>=capacity-reserve then break end
        if allowed(id) and id~=locked then table.insert(kit,id) end
    end
    if reserve==1 then table.insert(kit,locked) end
    return kit
end
local function segmentDistance2(x,y,x1,y1,x2,y2)
    local dx,dy=x2-x1,y2-y1;local length=dx*dx+dy*dy
    local t=length>0 and math.clamp(((x-x1)*dx+(y-y1)*dy)/length,0,1) or 0
    return (x-x1-dx*t)^2+(y-y1-dy*t)^2
end
function Model.ordnance(sim,tool,maxCivilianRisk)
    local clusters=Model.clusters(sim,"Zombie",90);local best,bestScore
    local radius=tool.radius or 38;local lead=(tool.delay or 3)+(tool.flyTime or 2)*.5
    for i=1,math.min(12,#clusters) do
        local c=clusters[i]
        if c.count<6 and c.agent.special~="weeper" and c.threat<20 then continue end
        for _,angle in ipairs({0,math.pi/4,math.pi/2,math.pi*3/4}) do
            for _,length in ipairs({120,240}) do
                length=math.clamp(length,tool.minLength or 60,tool.maxLength or 340)
                local vx,vy=(c.agent.vx or 0)*lead,(c.agent.vy or 0)*lead
                local cx,cy=c.x+vx,c.y+vy;local dx,dy=math.cos(angle)*length/2,math.sin(angle)*length/2
                local plan={x=math.clamp(cx-dx,0,sim.city.W),y=math.clamp(cy-dy,0,sim.city.H),x2=math.clamp(cx+dx,0,sim.city.W),y2=math.clamp(cy+dy,0,sim.city.H)}
                if (plan.x2-plan.x)^2+(plan.y2-plan.y)^2<(tool.minLength or 60)^2 then continue end
                local risk,hits,value,unsafe=0,0,0,false
                for _,a in ipairs(sim.agents or {}) do
                    if a.dead or a.stashed then continue end
                    local d=segmentDistance2(a.x,a.y,plan.x,plan.y,plan.x2,plan.y2)
                    if a.kind=="Human" and d<radius^2 then risk+=1 end
                    if a.kind=="Soldier" and a.main and d<(radius+15)^2 then unsafe=true break end
                    if a.kind=="Zombie" and not a.hidden then
                        local future=segmentDistance2(a.x+(a.vx or 0)*lead,a.y+(a.vy or 0)*lead,plan.x,plan.y,plan.x2,plan.y2)
                        if future<radius^2 then hits+=1;value+=a.special=="weeper" and 12 or Model.specialWeight(a) end
                    end
                end
                for _,list in ipairs({sim.tents or {},sim.depots or {}}) do
                    for _,asset in ipairs(list) do if not asset.dead and segmentDistance2(asset.x,asset.y,plan.x,plan.y,plan.x2,plan.y2)<(radius+20)^2 then unsafe=true break end end
                    if unsafe then break end
                end
                local score=value*4-risk*3
                if not unsafe and score>0 and risk<=maxCivilianRisk and (hits>=6 or c.agent.special=="weeper" and value>=12) and (not bestScore or score>bestScore) then
                    best,bestScore=plan,score;plan.hits=hits;plan.risk=risk
                end
            end
        end
    end
    return best
end
-- The command-line regression suite can exercise planning without Roblox.
if not game then return Model end
if game.GameId ~= 10769802973 then warn("Last Stand | This module is for universe 10769802973."); return end
local env = getgenv()
local previous=env.LastStand
local previousOwn=previous and previous.rescues and previous.rescues.own
local previousSim=previous and previous.bound
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
    autoRepeat=false,autoHQ=false,autoSupplies=false,lastHQ=-100,controls={},rounds=0,
    autoRooftop=false,autoFort=false,autoClinic=false,autoCandy=false,autoOrdnance=false,autoStrongpoint=false,fullFarm=false,autoDefenses=false,showThreats=false,rescues=Model.newRescues(),hqJobs={},stopEpoch=0,
    reconVisits={},intelVisits={},treatedReports={},deployments={},pickupPending={},candyPicked=0,lastThreatNotice=-100,defenseAt=-100,labels={},toolCounts={}}
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
                if type(ctx.hud.onSpeed)=="function" then
                    local speedOK,speedValues=pcall(read,ctx.hud.onSpeed)
                    if speedOK and speedValues[3]==ctx.hud and type(speedValues[2])=="number" then ctx.timeScale=speedValues[2] end
                end
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
    local style=ctx.config.MAP_STYLES and ctx.config.MAP_STYLES[ctx.hud.kitMap or ctx.sim.level.kitMap or ctx.sim.level.map]
    if style and style.NO_TOOLS and style.NO_TOOLS[id] then return nil,"Tool unavailable on this map: "..id end
    local equipped=false
    for key,value in pairs(ctx.hud.loadoutIds or {}) do if value==id or key==id then equipped=true break end end
    if not equipped then return nil,"Tool is not in this match's loadout: "..id end
    for _, tool in pairs(ctx.config.ALL_TOOLS) do
        if tool.id==id then
            local profile=ctx.hud.profile
            if profile and not ctx.hud.allUnlocked and (tool.unlock or tool.crate or tool.candyUnlock) and not (profile.unlocks or {})[id] then return nil,"Tool is not unlocked: "..id end
            return tool
        end
    end
    return nil,"Unknown tool: "..id
end
local pointTools = {Evac=true,Recon=true,Medics=true,Strike=true,Hunters=true,Ghosts=true,Fort=true,Depot=true,Tent=true,ReconTower=true,Rooftop=true}
local function usable(ctx)
    if ctx.sim.over then return false,"Match ended." end
    if ctx.timeScale==0 then return false,"Game paused." end
    if ctx.hud.overlay and ctx.hud.overlay.Visible then return false,"Close the briefing/menu first." end
    if ctx.sim.__mpMirror and (not ctx.mp or not ctx.mp.game or not ctx.mp.ready or ctx.mp.sim~=ctx.sim) then return false,"Waiting for multiplayer state." end
    return true
end
local function submit(ctx, id, x, y, reserve, source)
    local ready, reason = usable(ctx); if not ready then return false,reason end
    if not pointTools[id] or not Model.point(x,y,ctx.sim.city) then return false,"Invalid point placement." end
    local tool, missing = getTool(ctx,id); if not tool then return false,missing end
    local effective = ctx.sim:effective(tool)
    if ctx.sim.budget-(effective.cost or 0) < reserve then return false,"Waiting for budget above reserve." end
    local can, why = ctx.sim:canUse(effective); if not can then return false,why end
    if os.clock()-(state.pending[id] or -100) < (state.fullFarm and (ctx.sim.__mpMirror and .75 or .25) or 3) then return false,"Waiting for the previous request." end
    local accepted, rejection = ctx.sim:useTool(tool,x,y)
    state.pending[id]=os.clock()
    if not accepted then return false,rejection or "Placement rejected." end
    if id=="Evac" or id=="Rooftop" then
        if source=="manual" then
            -- Explicit Rayfield placements and recorded plans also count as the
            -- player's choice; automatic placements must never seed repeat mode.
            local fake={x=x,y=y,rooftop=id=="Rooftop"}
            if fake.rooftop then fake.roof=ctx.sim.city:roofAt(x,y) end
            local point=Model.rescue(ctx.sim.city,fake)
            if point and not state.rescues.points[point.key] then
                state.rescues.points[point.key]=point;table.insert(state.rescues.order,point.key)
            end
        end
        Model.issuedRescue(state.rescues,ctx.sim.city,id,x,y,os.clock())
    end
    state.submitted+=1
    state.toolCounts[id]=(state.toolCounts[id] or 0)+1
    if state.fullFarm and (id=="Ghosts" or id=="Hunters" or id=="Strike") then
        table.insert(state.deployments,{x=x,y=y,untilTime=ctx.sim.time+(effective.deployDelay or 7)+3})
    end
    log(string.format("%s %s at %.0f, %.0f",ctx.sim.__mpMirror and "Sent" or "Placed",tool.name or id,x,y))
    return true
end
function state:GetContext() return context() end
function state:UseTool(id,x,y)
    local ctx,err=context(); assert(ctx,err)
    return submit(ctx,id,x,y,0,"manual")
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
    assert(pointTools[self.selected],"Choose an equipped point tool first.")
    assert(#self.queue<100,"Queue limit is 100 placements.")
    table.insert(self.queue,{tool=self.selected,x=self.marker.x,y=self.marker.y})
    log("Queued "..self.selected.." (#"..#self.queue..")")
end
function state:Stop()
    self.playing=false;self.autoEvac=false;self.autoRecon=false;self.autoMedics=false;self.autoStrike=false;self.autoRepeat=false
    self.autoHQ=false;self.autoSupplies=false;self.autoCandy=false;self.autoRooftop=false;self.autoFort=false;self.autoClinic=false;self.autoOrdnance=false;self.autoStrongpoint=false;self.fullFarm=false;self.autoDefenses=false;self.showThreats=false
    self.stopEpoch+=1;self.rescues.points={};self.rescues.order={};self.rescues.cursor={};self.hqJobs={}
    self.expectedRound=nil;self.replayAt=nil;self.strikePlan=nil;self.lastStrikeScan=nil
    for _,control in pairs(self.controls) do pcall(function() control:Set(false,true) end) end
    log("All automation stopped.")
end
function state:Destroy()
    if not self.alive then return end
    self:Stop();self.alive=false
    for _,connection in ipairs(self.connections) do connection:Disconnect() end
    if self.threatGui then self.threatGui:Destroy() end
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
                        local callback=connection.Function;local epoch=state.stopEpoch
                        -- Level loading may yield or retire the game's calling
                        -- thread. Keep it outside the automation scheduler.
                        task.defer(function()
                            if not state.alive or state.stopEpoch~=epoch then state.uiPending=false;return end
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
local flags={autoEvac="Evac",autoRooftop="Rooftop",autoRecon="Recon",autoMedics="Medics",autoStrike="Strike",autoFort="Fort",autoClinic="Tent"}
local combatTools={"Hunters","Strike","Ghosts"}
local function hasResponse(ctx,flag,id)
    if flag=="autoStrike" then for _,candidate in ipairs(combatTools) do if getTool(ctx,candidate) then return true end end;return false end
    return getTool(ctx,id)~=nil
end
function state:SetFullFarm(value)
    if not value then self:Stop();return end
    local ctx,err=context();assert(ctx,err);assert(not ctx.sim.level.tutorial,"Finish the tutorial first.")
    self.fullFarm=true;self.controls.fullFarm:Set(true,true)
    for flag,id in pairs(flags) do self.controls[flag]:Set(hasResponse(ctx,flag,id)) end
    self.controls.autoHQ:Set(true);self.controls.autoSupplies:Set(true);self.controls.autoCandy:Set(true);self.controls.showThreats:Set(true)
    self.controls.autoDefenses:Set(getTool(ctx,"Gate")~=nil and getTool(ctx,"Clear")~=nil)
    self.controls.autoStrongpoint:Set(false)
    self.controls.autoRepeat:Set(not ctx.sim.__mpMirror)
    if not ctx.sim.__mpMirror and not ctx.sim.over and ctx.hud.overlay and ctx.hud.overlay.Visible then
        for _,button in ipairs(ctx.hud.overlay:GetDescendants()) do
            if button:IsA("TextButton") and button.Text=="Begin Response" then
                self.expectedRound=roundKey(ctx.sim);self.beginDeadline=os.clock()+30;break
            end
        end
    end
    log("Full autofarm enabled: rescue, treatment, HQ, available defenses and normal solo replay.")
    notify("Full autofarm",ctx.sim.__mpMirror and "Equipped actions enabled. Co-op replay remains manual." or "Equipped actions and level repeat enabled. F10 stops everything.")
end
local function ownedSquads(ctx)
    if ctx.sim.__mpMirror then
        local info=ctx.mp.info;local admin=info and info.admins and info.admins[info.me]
        return admin and admin.squads or {}
    end
    return ctx.sim.mainSquads or {ctx.sim.mainSquad}
end
local function strongpoint(ctx)
    if state.fullFarm and state.autoStrongpoint and not ctx.sim.__mpMirror and ctx.sim.city.base
        and ctx.sim:lvl("orderBroadcast")>0 and getTool(ctx,"Clear") then return ctx.sim.city.base end
end
local function defendPoint(sim,origin)
    for _,zone in ipairs(sim.clearZones or {}) do if zone.safe then return zone end end
    local best,score
    for _,rescue in ipairs(sim.evacs or {}) do
        if not rescue.dead then
            local value=1000-math.sqrt(distance2(origin,rescue))
            if not score or value>score then best,score=rescue,value end
        end
    end
    if best then return best end
    for _,cluster in ipairs(Model.clusters(sim,"Healthy",180)) do
        local value=cluster.count/(1+math.sqrt(distance2(origin,cluster))/350)
        if not score or value>score then best,score=cluster,value end
    end
    return best or origin
end
local function updateHQ(ctx)
    local sim=ctx.sim;local now=os.clock()
    if now-state.lastHQ<(state.fullFarm and .6 or 2) then return end;state.lastHQ=now
    local assigned={}
    for _,id in ipairs(ownedSquads(ctx)) do
        if sim.__mpMirror and not ctx.mp:ownsSquad(id) then continue end
        local members=sim:squadMembers(id);if #members==0 then continue end
        local origin={x=0,y=0}
        for _,a in ipairs(members) do origin.x+=a.x/#members;origin.y+=a.y/#members end
        local job=state.hqJobs[id] or {blocked={}};state.hqJobs[id]=job
        if members[1].medicTeam then
            -- Combat medics cannot shoot. Chasing zombies keeps them moving and
            -- prevents their native nearby-carrier seeking behavior.
            local patient=Model.medicTarget(sim,origin,state.fullFarm and not sim.__mpMirror)
            if patient then
                if not job.patient or distance2(job.patient,patient)>25^2 or now-(job.at or -100)>3 then
                    sim:setSquadMode(id,"manual")
                    if sim:moveSquad(id,patient.x,patient.y) then job.patient={x=patient.x,y=patient.y};job.at=now;log("HQ "..tostring(id)..": treat revealed carriers.") end
                end
            elseif sim:squadMode(id)~="patrol" then
                sim:setSquadMode(id,"patrol");job.patient=nil;job.target=nil
                log("HQ "..tostring(id)..": medical patrol.")
            end
            continue
        end
        local base=strongpoint(ctx)
        if base and sim.objective=="clear" and not members[1].medicTeam then
            local r=base.rect;local threat=false
            for _,z in ipairs(sim.agents) do
                if z.kind=="Zombie" and not z.dead and not z.hidden and z.x>r[1]-220 and z.x<r[2]+220 and z.y>r[3]-220 and z.y<r[4]+220 then threat=true break end
            end
            if not threat then base=nil end
        end
        if base then
            local selected,best
            for i,gate in ipairs(base.gates or {}) do
                local p={x=gate.x or gate[1],y=gate.y or gate[2]};local urgency=0
                for _,z in ipairs(sim.agents) do
                    if z.kind=="Zombie" and not z.dead and not z.hidden and distance2(z,p)<240^2 then urgency+=Model.specialWeight(z) end
                end
                local value=urgency*100-math.sqrt(distance2(origin,p))*.05
                if not best or value>best then selected,best=p,value end
            end
            if selected then
                local r=base.rect;local center={x=(r[1]+r[2])/2,y=(r[3]+r[4])/2}
                local dx,dy=center.x-selected.x,center.y-selected.y;local length=math.max(1,math.sqrt(dx*dx+dy*dy))
                selected.x+=dx/length*15;selected.y+=dy/length*15
                if sim:squadMode(id)~="defend" or not job.defend or distance2(job.defend,selected)>55^2 then
                    sim:setSquadMode(id,"defend")
                    local vertices=Model.square(sim.city,selected,85)
                    if vertices and sim:setSquadArea(id,vertices) then job.defend=selected;job.target=nil;log("HQ "..tostring(id)..": protect base entrance / medical support.") end
                end
            end
            continue
        end
        local excluded=table.clone(assigned)
        for key,untilTime in pairs(job.blocked) do if now<untilTime then excluded[key]=true else job.blocked[key]=nil end end
        local current=sim:squadAttackTarget(id)
        if job.target and not current and now-(job.at or now)>6 then job.blocked[job.target]=now+20;excluded[job.target]=true end
        local target=Model.hqTarget(sim,origin,excluded)
        if not target and next(assigned) then target=Model.hqTarget(sim,origin,job.blocked) end
        if current and not current.dead and not current.hidden and Model.specialWeight(current)>0 then
            if not target or distance2(origin,target)>120^2 or distance2(origin,current)<220^2 then target=current end
        end
        local mode=sim:squadMode(id)
        if target then
            local key=target.id or target;assigned[key]=true
            if not current or current.dead or (current.id or current)~=key or mode~="attack" then
                if now-(job.at or -100)<(state.fullFarm and .8 or 3) then continue end
                sim:setSquadMode(id,"attack")
                local ok,why=sim:setSquadAttack(id,target)
                if ok then job.target=key;job.at=now;job.defend=nil;log("HQ "..tostring(id)..": attack / retarget visible zombie.")
                else job.blocked[key]=now+20;log("HQ order: "..tostring(why)) end
            end
        elseif state.fullFarm then
            -- Follow fresh public tracking clues before carriers become hordes.
            local report,bestDistance
            for _,clue in ipairs(sim.suspects or {}) do
                if (clue.expire or 0)<=sim.time then continue end
                local key=math.floor(clue.x/120)..":"..math.floor(clue.y/120)
                local d=distance2(origin,clue)
                if not assigned[key] and (not bestDistance or d<bestDistance) then report={x=clue.x,y=clue.y,key=key};bestDistance=d end
            end
            if report then
                assigned[report.key]=true
                if not job.scout or now-(job.scout.at or 0)>10 or distance2(job.scout,report)>170^2 then
                    sim:setSquadMode(id,"manual")
                    local ok=sim:moveSquad(id,report.x,report.y)
                    if ok then job.target=nil;job.scout={x=report.x,y=report.y,at=now};log("HQ "..tostring(id)..": investigate tracking report.") end
                end
            elseif mode~="patrol" then
                sim:setSquadMode(id,"patrol");job.target=nil;job.scout=nil
                log("HQ "..tostring(id)..": patrol / drone intel.")
            end
        else
            local point=defendPoint(sim,origin)
            if mode~="defend" or not job.defend or distance2(point,job.defend)>70^2 then
                local vertices=Model.square(sim.city,point,90)
                if vertices then
                    sim:setSquadMode(id,"defend")
                    local ok,why=sim:setSquadArea(id,vertices)
                    if ok then job.target=nil;job.defend={x=point.x,y=point.y};job.at=now;log("HQ "..tostring(id)..": defend rescue / civilian area.")
                    else log("HQ defense: "..tostring(why)) end
                end
            end
        end
    end
end
local function reconPoint(ctx)
    local sim=ctx.sim
    if state.fullFarm and not sim.__mpMirror then
        local tool=getTool(ctx,"Recon")
        return tool and Model.sourceIntel(sim,sim:effective(tool).radius)
    end
    if state.fullFarm and (sim.pop.infected or 0)==0 and (sim.pop.hiddenZombies or 0)==0 then return nil end
    if state.fullFarm then
        local tool=getTool(ctx,"Recon")
        local report=Model.intel(sim,state.intelVisits,tool and sim:effective(tool).radius or 175)
        if report then return report end
    end
    local report=Model.report(sim)
    if report and (not state.fullFarm or sim.time-(report.t or 0)<60) then
        local key=math.floor(report.x/70)..":"..math.floor(report.y/70)
        if not state.fullFarm or sim.time-(state.intelVisits[key] or -100)>25 then return {x=report.x,y=report.y,intelKey=key} end
    end
    if not state.fullFarm then return nil end
    if sim:lvl("tracking")>=2 or sim.time-(state.lastSweep or -100)<20 then return nil end
    local best,score
    for _,c in ipairs(Model.clusters(sim,"Healthy",150)) do
        local covered=false
        for _,r in ipairs(sim.recons or {}) do if not r.dead and distance2(c,r)<110^2 then covered=true break end end
        for _,r in ipairs(sim.reconTowers or {}) do if not r.dead and distance2(c,r)<110^2 then covered=true break end end
        local key=math.floor(c.x/150)..":"..math.floor(c.y/150)
        local age=os.clock()-(state.reconVisits[key] or -100)
        local value=age+math.min(c.count,30)*.1 -- oldest areas cannot starve behind dense crowds
        if not covered and age>25 and (not score or value>score) then best,score=c,value;best.visit=key end
    end
    return best
end
local function buildDefensePlan(ctx)
    local sim=ctx.sim;local origin
    for _,id in ipairs(ownedSquads(ctx)) do
        local members=sim:squadMembers(id)
        if members[1] then origin={x=members[1].x,y=members[1].y};break end
    end
    if not origin then return nil end
    local vertices=Model.square(sim.city,origin,70);if not vertices then return nil end
    local steps={}
    for i,a in ipairs(vertices) do
        local b=vertices[i%4+1]
        for half=0,1 do
            local x1,y1=a[1]+(b[1]-a[1])*half/2,a[2]+(b[2]-a[2])*half/2
            local x2,y2=a[1]+(b[1]-a[1])*(half+1)/2,a[2]+(b[2]-a[2])*(half+1)/2
            for _,piece in ipairs(sim.wallPieces(sim.city,x1,y1,x2,y2)) do
                if piece[5]>=10 then table.insert(steps,{tool="Gate",x=piece[1],y=piece[2],x2=piece[3],y2=piece[4]}) end
            end
        end
    end
    if #steps==0 then return nil end
    return {steps=steps,vertices=vertices,x=(vertices[1][1]+vertices[3][1])/2,y=(vertices[1][2]+vertices[3][2])/2,sent={}}
end
local function construction(ctx,step,reserveOverride)
    local sim=ctx.sim;local ready,reason=usable(ctx);if not ready then return false,reason end
    local tool,err=getTool(ctx,step.tool);if not tool then return false,err end
    local effective=sim:effective(tool);local cost=effective.cost or 0;local zone
    if step.tool=="Gate" then
        if not Model.point(step.x,step.y,sim.city) or not Model.point(step.x2,step.y2,sim.city) then return false,"Invalid gate endpoints." end
        local length=math.sqrt((step.x2-step.x)^2+(step.y2-step.y)^2)
        if length<(effective.minLength or 10) or length>(effective.maxLength or 80) then return false,"Gate length is invalid." end
        cost=sim.wallCost(effective,length,sim.streetLength(sim.city,step.x,step.y,step.x2,step.y2))
    elseif step.tool=="Clear" then
        for _,p in ipairs(step.vertices or {}) do if not Model.point(p[1],p[2],sim.city) then return false,"Invalid safe zone." end end
        zone=sim.clearPoly(effective,step.vertices);if not zone then return false,"Invalid safe-zone polygon." end
        zone.safe=true
        if (sim.income or 0)-sim:zoneUpkeep(zone)<1 then return false,"Waiting for income to support safe-zone upkeep." end
    else return false,"Unsupported construction." end
    local minimum=reserveOverride~=nil and reserveOverride or state.reserve+200
    if sim.budget-cost<minimum then return false,"Saving funds for rescue before construction." end
    local can,why=sim:canUse(effective,cost);if not can then return false,why end
    if os.clock()-(state.pending[step.tool] or -100)<3 then return false,"Waiting for previous construction request." end
    local ok,rejection
    if zone then ok,rejection=sim:useTool(tool,step.vertices,"safe")
    else ok,rejection=sim:useTool(tool,step.x,step.y,step.x2,step.y2) end
    state.pending[step.tool]=os.clock()
    if ok then state.submitted+=1;log((sim.__mpMirror and "Sent " or "Built ")..(zone and "safe zone." or "checkpoint gate.")) end
    return ok,rejection
end
local function baseOperations(ctx)
    local base=strongpoint(ctx);if not base then return false end
    local sim=ctx.sim;local r=base.rect
    state.basePlan=state.basePlan or {vertices={{r[1]+12,r[3]+12},{r[2]-12,r[3]+12},{r[2]-12,r[4]-12},{r[1]+12,r[4]-12}},gates={},sent={}}
    local plan=state.basePlan
    if not plan.recorded then
        for _,wall in ipairs(sim.walls or {}) do
            if wall.base and wall.gate then table.insert(plan.gates,{tool="Gate",x=wall.x1,y=wall.y1,x2=wall.x2,y2=wall.y2}) end
        end
        plan.recorded=true
    end
    local safe=false
    for _,zone in ipairs(sim.clearZones or {}) do if zone.safe and sim:inBase(zone.x,zone.y) then safe=true break end end
    if not safe then return construction(ctx,{tool="Clear",vertices=plan.vertices},0) end
    if not (sim.orders or {}).broadcast and sim.budget>=((ctx.config.ORDERS or {}).broadcast.COST or 100) then
        local ok=sim:setOrder("broadcast",true)
        if ok then log("Enacted safe-zone broadcast toward the existing fortified base.") end
        return ok
    end
    for _,step in ipairs(plan.gates) do
        if not Model.gateCovered(step,sim.walls) and os.clock()-(plan.sent[step] or -100)>12 then
            local ok=construction(ctx,step,0);if ok then plan.sent[step]=os.clock() end
            return ok
        end
    end
    return false
end
local function updateDefenses(ctx)
    local sim=ctx.sim
    if state.fullFarm then
        local style=ctx.config.MAP_STYLES and ctx.config.MAP_STYLES[ctx.hud.kitMap or sim.level.map]
        if (style and style.BASE) or not (state.farmPolicy and state.farmPolicy.build) then return end
    end
    if not getTool(ctx,"Gate") or not getTool(ctx,"Clear") or os.clock()-state.defenseAt<4 then return end
    state.defenseAt=os.clock()
    if not state.defensePlan then
        for _,zone in ipairs(sim.clearZones or {}) do if zone.safe then return end end
        state.defensePlan=buildDefensePlan(ctx)
    end
    local plan=state.defensePlan;if not plan then return end
    for _,step in ipairs(plan.steps) do
        if not Model.gateCovered(step,sim.walls) then
            if os.clock()-(plan.sent[step] or -100)<30 then return end
            local ok=construction(ctx,step);if ok then plan.sent[step]=os.clock() end
            return
        end
    end
    for _,zone in ipairs(sim.clearZones or {}) do if zone.safe and distance2(zone,plan)<30^2 then return end end
    for _,kind in ipairs({"Zombie","Infected"}) do
        for _,c in ipairs(Model.clusters(sim,kind,80)) do if distance2(c,plan)<160^2 then return end end
    end
    if os.clock()-(plan.zoneSent or -100)<30 then return end
    if construction(ctx,{tool="Clear",vertices=plan.vertices}) then plan.zoneSent=os.clock() end
end
local function submitOrdnance(ctx,plan,reserve)
    local ready,reason=usable(ctx);if not ready then return false,reason end
    local tool,why=getTool(ctx,"Airstrike");if not tool then return false,why end
    local sim=ctx.sim;local effective=sim:effective(tool)
    if not Model.point(plan.x,plan.y,sim.city) or not Model.point(plan.x2,plan.y2,sim.city) then return false,"Invalid strike path." end
    if sim.budget-effective.cost<reserve or not sim:canUse(effective) then return false,"Waiting for strike budget / cooldown." end
    if os.clock()-(state.pending.Airstrike or -100)<1 then return false,"Waiting for strike request." end
    local ok,rejection=sim:useTool(tool,plan.x,plan.y,plan.x2,plan.y2);state.pending.Airstrike=os.clock()
    if ok then state.submitted+=1;state.toolCounts.Airstrike=(state.toolCounts.Airstrike or 0)+1;log(string.format("%s bombing run: %d predicted zombies, %d civilians at risk.",sim.__mpMirror and "Sent" or "Called",plan.hits,plan.risk)) end
    return ok,rejection
end
local function threatLabels(ctx,reuseSnapshot)
    local clusters=state.showThreats and not ctx.sim.over and usable(ctx)
        and (reuseSnapshot and state.threats or Model.clusters(ctx.sim,"Zombie",110)) or {}
    clusters=clusters or {}
    state.threats=clusters
    state.threatClusters=#clusters
    if not state.threatGui and #clusters>0 then
        local gui=Instance.new("ScreenGui");gui.Name="AltairLastStandThreats";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=20
        gui.Parent=game.Players.LocalPlayer:WaitForChild("PlayerGui");state.threatGui=gui
        local canvas=Instance.new("Frame");canvas.Name="MapLabels";canvas.BackgroundTransparency=1;canvas.Size=UDim2.fromScale(1,1);canvas.Parent=gui;state.threatCanvas=canvas
    end
    if not state.threatGui then return end
    local world=ctx.hud.world;local offset=world.AbsolutePosition-state.threatCanvas.AbsolutePosition;local size=world.AbsoluteSize
    state.labelWorld=world;state.labelPosition=world.AbsolutePosition;state.labelSize=size
    local low,high=Vector2.new(0,0),state.threatCanvas.AbsoluteSize
    local ancestor=world
    while ancestor and ancestor:IsA("GuiObject") do
        if not ancestor.Visible then clusters={} break end
        if ancestor.ClipsDescendants then
            local p=ancestor.AbsolutePosition-state.threatCanvas.AbsolutePosition;local s=ancestor.AbsoluteSize
            low=Vector2.new(math.max(low.X,p.X),math.max(low.Y,p.Y));high=Vector2.new(math.min(high.X,p.X+s.X),math.min(high.Y,p.Y+s.Y))
        end
        ancestor=ancestor.Parent
    end
    for i=1,math.min(#clusters,40) do
        local label=state.labels[i]
        if not label then
            label=Instance.new("TextLabel");label.Name="Threat";label.AnchorPoint=Vector2.new(.5,1);label.Size=UDim2.fromOffset(158,23)
            label.BackgroundColor3=Color3.fromRGB(27,11,13);label.BackgroundTransparency=.12;label.TextColor3=Color3.fromRGB(255,145,145)
            label.Font=Enum.Font.GothamMedium;label.TextSize=11;label.ZIndex=2;label.Parent=state.threatCanvas
            local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,7);corner.Parent=label
            local stroke=Instance.new("UIStroke");stroke.Color=Color3.fromRGB(211,71,84);stroke.Transparency=.35;stroke.Parent=label
            state.labels[i]=label
        end
        local c=clusters[i];local px,py=c.x/ctx.sim.city.W*size.X,c.y/ctx.sim.city.H*size.Y
        local screenX,screenY=offset.X+px,offset.Y+py-8
        label.Visible=screenX>=low.X and screenY>=low.Y+23 and screenX<=high.X and screenY<=high.Y
        label.Position=UDim2.fromOffset(offset.X+px,offset.Y+py-8)
        local kind=c.agent.special;local spec=kind and ctx.config.SPECIALS and ctx.config.SPECIALS[kind]
        local name=spec and spec.name or kind
        label.Text=name and string.format("%d · %s%s",c.count,name,(c.specials[kind] or 0)>1 and " x"..c.specials[kind] or "") or string.format("%d zombie%s",c.count,c.count==1 and "" or "s")
        label.TextColor3=kind=="weeper" and Color3.fromRGB(216,167,255) or kind=="bloater" and Color3.fromRGB(255,187,108) or Color3.fromRGB(255,145,145)
    end
    for i=math.min(#clusters,40)+1,#state.labels do state.labels[i].Visible=false end
    if os.clock()-state.lastThreatNotice>25 then
        for _,c in ipairs(clusters) do
            for _,rescue in ipairs(ctx.sim.evacs or {}) do
                if not rescue.dead and distance2(c,rescue)<180^2 then
                    state.lastThreatNotice=os.clock();notify("Rescue under threat",string.format("%d visible zombies near an active extraction. Enabled HQ / tool responses will react.",c.count));return
                end
            end
        end
    end
end
local loaded, Rayfield = pcall(function() return assert(loadstring(game:HttpGet("https://sirius.menu/gen2")))() end)
if not loaded then state:Destroy();error("Last Stand | Rayfield failed to load: "..tostring(Rayfield)) end
local built, buildError = pcall(function()
    window=Rayfield:CreateWindow({name="Last Stand",subtitle="Altair · rescue and containment",icon="shield",sidebarLayout=true,
        configuration={autoSave=false,autoLoad=false,fileName="LastStand"}})
    state.window=window
    local overview=window:CreateTab({name="Match",icon="activity"})
    local status=overview:CreateText({name="Match status",text="Reading the active level…"})
    overview:CreateButton({name="Stop all automation",callback=function() state:Stop() end})
    local budget=overview:CreateStat({name="Budget",prefix="$",value=0,changeMode="absolute"})
    local evacuated=overview:CreateStat({name="Evacuated",value=0,changeMode="absolute"})
    local preservation=overview:CreateText({name="S-rank objective",text="Win and preserve at least 85% of the starting population. Reading current margin…"})
    local rescueStatus=overview:CreateText({name="Rescue repeat",text="Waiting for your first evacuation. Full autofarm chooses its own locations."})
    local threatStatus=overview:CreateText({name="Known threats",text="Enable zombie labels to track visible groups and their locations."})
    overview:CreateText({name="Normal game actions",text="Placements use your equipped tools and obey the game's costs, cooldowns, valid sites, and multiplayer permissions. Automation starts off. F10 stops everything."})
    local auto=window:CreateTab({name="Automation",icon="repeat"})
    state.controls.fullFarm=auto:CreateToggle({name="Full autofarm",value=false,callback=guarded(function(v) state:SetFullFarm(v) end),
        description="One switch: choose rescues, use equipped responses, direct owned HQ squads, build available gated defenses, collect supplies, and repeat the same solo level. S is an objective, not a guaranteed result."})
    local readiness=auto:CreateText({name="Equipped response plan",text="Checking this match's tools…"})
    local strategy=auto:CreateText({name="Adaptive strategy",text="Full autofarm adjusts spending and response priorities to the outbreak. Presets use owned tools; they never buy research."})
    auto:CreateButton({name="Equip Nightmare loadout & start",callback=guarded(function()
        local ctx,err=context();assert(ctx,err)
        assert(not ctx.sim.__mpMirror,"Select the co-op toolkit in the game's lobby.")
        assert(ctx.hud.overlay and ctx.hud.overlay.Visible,"Use this from the level briefing.")
        local briefing=false
        for _,b in ipairs(ctx.hud.overlay:GetDescendants()) do if b:IsA("TextButton") and b.Text=="Begin Response" then briefing=true break end end
        assert(briefing,"Return to the level briefing first.")
        local style=ctx.config.MAP_STYLES[ctx.hud.kitMap or ctx.sim.level.map] or {}
        local kit=Model.loadout(ctx.config,ctx.hud.profile,ctx.hud.toolSlotPassOwned,style.NO_TOOLS)
        local callback=ctx.hud.onLoadout;local epoch=state.stopEpoch
        task.defer(function() if state.alive and state.stopEpoch==epoch then pcall(callback,kit) end end)
        task.spawn(function()
            local deadline=os.clock()+10
            repeat
                task.wait(.2)
                if not state.alive or state.stopEpoch~=epoch then return end
                local latest=context()
                if latest and table.concat(latest.hud.loadoutIds or {},",")==table.concat(kit,",") then
                    state:SetFullFarm(true);return
                end
            until os.clock()>deadline
            notify("Loadout not confirmed","Check the game's selected tools before starting.")
        end)
    end)})
    state.controls.autoEvac=auto:CreateToggle({name="Repeat my evac points",value=false,callback=function(v) state.autoEvac=v;if v then state.rescues.seen={} end end,
        description="Outside full autofarm, waits for you to start an evac, then repeats at that exact site. Multiple sites are remembered. Costs and cooldowns still apply."})
    state.controls.autoRooftop=auto:CreateToggle({name="Repeat my rooftop extracts",value=false,callback=function(v) state.autoRooftop=v;if v then state.rescues.seen={} end end,
        description="Waits for a rooftop extract you start, then repeats on that building. Full autofarm can select healthy, accessible roofs itself. Requires Rooftop in this loadout."})
    auto:CreateButton({name="Forget repeated rescue locations",callback=function()
        state.rescues.points={};state.rescues.order={};state.rescues.cursor={};log("Rescue locations cleared; waiting for a new player-started extraction.")
    end})
    auto:CreateSlider({name="Assist budget reserve",range={0,2000},increment=25,value=250,suffix="$",callback=function(v) state.reserve=v end})
    auto:CreateText({name="Autofarm funds",text="Manual assists honor this reserve. Full autofarm uses a smaller adaptive buffer, saves treatment funds after scans, and can spend the buffer during an emergency."})
    auto:CreateSlider({name="Autofarm: minimum civilians near rescue",range={1,100},increment=1,value=12,callback=function(v) state.minEvac=v end})
    state.controls.showThreats=auto:CreateToggle({name="Label visible zombie groups",value=false,callback=function(v) state.showThreats=v end,
        description="Pooled map labels follow visible zombie groups; nearby-rescue warnings are rate limited. Hidden outbreaks need normal reconnaissance. Up to 40 labels; no per-zombie render loop."})
    state.controls.autoRecon=auto:CreateToggle({name="Recon reported outbreaks",value=false,callback=function(v) state.autoRecon=v end,
        description="Send recon to reported outbreak locations without an active nearby drone."})
    state.controls.autoMedics=auto:CreateToggle({name="Treat revealed infected",value=false,callback=function(v) state.autoMedics=v end,
        description="Use Vaccine Shell on clusters already revealed by reconnaissance."})
    state.controls.autoStrike=auto:CreateToggle({name="Reinforce visible outbreaks",value=false,callback=function(v) state.autoStrike=v end,
        description="Use equipped Monster Hunters, Strike Team, or Ghost Patrol against visible zombie clusters. Skip responses that are unavailable, unaffordable, or cooling down."})
    state.controls.autoFort=auto:CreateToggle({name="Fortify rescue / civilian areas",value=false,callback=function(v) state.autoFort=v end,
        description="When Fortification is equipped, fortify a reachable nearby roof without duplicating existing or building forts. Rescue and treatment take priority."})
    state.controls.autoClinic=auto:CreateToggle({name="Build vaccination clinics",value=false,callback=function(v) state.autoClinic=v end,
        description="Use an equipped, unlocked Vaccination Tent to immunize populated areas. Avoid overlapping clinics and unsupported hordes. Full autofarm prioritizes prevention and keeps a bounded network."})
    state.controls.autoOrdnance=auto:CreateToggle({name="Experimental: bomb concentrated threats",value=false,callback=function(v) state.autoOrdnance=v end,
        description="Use an equipped Bombing Run against predicted enemy concentrations. Reject paths near owned HQ teams, clinics and depots; limit civilian exposure. The game still controls warning time, movement and damage."})
    state.controls.autoHQ=auto:CreateToggle({name="Adaptive HQ attack / defend",value=false,callback=function(v) state.autoHQ=v end,
        description="Prioritize zombies threatening civilians and extractions. Retarget dead / unreachable enemies; defend rescues or civilian areas when clear. Only commands your living HQ teams."})
    state.controls.autoDefenses=auto:CreateToggle({name="Build / maintain a gated safe zone",value=false,callback=function(v) state.autoDefenses=v end,
        description="Requires Gate + Evac Zone. Build checkpoint barriers on streets around HQ, then create a safe zone after the gates finish and known threats are clear. Healthy civilians can pass. Keeps rescue funds and checks upkeep."})
    state.controls.autoStrongpoint=auto:CreateToggle({name="Experimental: use existing fortified bases",value=false,callback=function(v) state.autoStrongpoint=v end,
        description="Where a map already provides a base, use its defenses, create a safe zone, enact an unlocked survivor broadcast, protect entrances and rebuild gates. Full autofarm only; costs and upkeep apply."})
    state.controls.autoSupplies=auto:CreateToggle({name="Collect available supply drops",value=false,callback=function(v) state.autoSupplies=v end,
        description="Click existing, unexpired supply drops using the game's normal pickup action. Excludes candy crates."})
    state.controls.autoCandy=auto:CreateToggle({name="Collect all available candy",value=false,callback=function(v) state.autoCandy=v end,
        description="Pick up actual night-time candy drops through the normal game action. Game and server reward limits still apply. Enabled with full autofarm."})
    state.controls.autoRepeat=auto:CreateToggle({name="Repeat this level",value=false,callback=function(v) state.autoRepeat=v end,
        description="Single-player: use the normal Play Again / Retry result button, then Begin Response. Keeps the same map and difficulty. No paid restart or mid-match reset."})
    auto:CreateButton({name="Enable equipped gameplay automations",callback=guarded(function()
        local ctx,err=context();assert(ctx,err)
        assert(not ctx.sim.level.tutorial,"Finish the tutorial first.")
        for flag,id in pairs(flags) do
            state.controls[flag]:Set(hasResponse(ctx,flag,id))
        end
        state.controls.autoHQ:Set(true);state.controls.autoSupplies:Set(true)
        notify("Assists enabled","Evac / rooftop repeat waits for sites you start. Full autofarm chooses sites. Level repeat is a separate toggle; F10 stops everything.")
    end)})
    auto:CreateText({name="Match transitions",text="Repeat uses the game's ordinary result flow. Match changes outside that flow stop automation. Rewards and research caps remain controlled by the game. A disconnect or game update stops the script."})
    auto:CreateButton({name="Equip standard loadout during briefing",callback=guarded(function()
        local ctx,err=context();assert(ctx,err)
        assert(not ctx.sim.__mpMirror,"Change the co-op loadout through the game's lobby.")
        local briefing=false
        if ctx.hud.overlay and ctx.hud.overlay.Visible then
            for _,v in ipairs(ctx.hud.overlay:GetDescendants()) do
                if v:IsA("TextButton") and v.Text=="Begin Response" then briefing=true break end
            end
        end
        assert(briefing,"Return to the level briefing before changing the loadout.")
        local epoch=state.stopEpoch;local callback=ctx.hud.onLoadout;local preset=table.clone(ctx.config.LOADOUT.DEFAULT)
        -- Profile saving in the game's callback may yield. Do not suspend the
        -- Rayfield control handler or assume that saving has already completed.
        task.defer(function()
            if not state.alive or state.stopEpoch~=epoch then return end
            local ok,reason=pcall(callback,preset)
            if not ok then log("Loadout request: "..tostring(reason));notify("Loadout request failed",reason) end
        end)
        notify("Standard loadout requested","Includes Recon, Vaccine Shell, Evac Point, and Strike Team. Check the equipped response plan before beginning.")
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
        if not ctx then
            for _,label in ipairs(state.labels) do label.Visible=false end
            status:Set(err);return true
        end
        local sim=ctx.sim
        if not state.bound and previousSim==sim and previousOwn then state.rescues.own=previousOwn end
        previousOwn=nil;previousSim=nil
        if state.bound and state.bound~=sim then
            if state.autoRepeat and state.expectedRound==roundKey(sim) then
                state.playing=false;state.index=1;state.rounds+=1;log("Replay level loaded.")
            else state:Stop();log("New match detected; review settings before restarting automation.") end
            state.pending={};state.rescues=Model.newRescues();state.hqJobs={};state.reconVisits={};state.intelVisits={};state.treatedReports={};state.deployments={};state.pickupPending={};state.defensePlan=nil;state.basePlan=nil;state.strikePlan=nil;state.lastStrikeScan=nil;state.riskNotified=false;state.resultLogged=false
        end
        state.bound=sim
        state.lastContext=ctx
        state.farmPolicy=state.fullFarm and Model.policy(sim,state.reserve) or nil
        local choices,equipped={},{}
        for _,tool in pairs(ctx.config.ALL_TOOLS) do
            if getTool(ctx,tool.id) then table.insert(equipped,tool.id);if pointTools[tool.id] then table.insert(choices,tool.id) end end
        end
        table.sort(choices);table.sort(equipped)
        local signature=table.concat(equipped,",")
        if signature~=state.loadoutSignature then
            state.loadoutSignature=signature;toolPicker:Refresh(choices)
            if not table.find(choices,state.selected) then state.selected=choices[1];if state.selected then toolPicker:Set(state.selected,true) end end
            if state.fullFarm then
                for flag,id in pairs(flags) do state.controls[flag]:Set(hasResponse(ctx,flag,id)) end
                state.controls.autoDefenses:Set(getTool(ctx,"Gate")~=nil and getTool(ctx,"Clear")~=nil)
                if state.autoStrongpoint and (sim.__mpMirror or not sim.city.base or not getTool(ctx,"Clear")) then state.controls.autoStrongpoint:Set(false) end
            end
            local function yes(id) return getTool(ctx,id) and "ready" or "not equipped" end
            readiness:Set(string.format("Evac: %s · Rooftop: %s\nRecon: %s · Vaccine: %s\nGated safe zone: %s · Fort: %s\nUnavailable tools are skipped; S depends on the response and outcome.",yes("Evac"),yes("Rooftop"),yes("Recon"),yes("Medics"),getTool(ctx,"Gate") and getTool(ctx,"Clear") and "ready" or "needs Gate + Evac Zone",yes("Fort")))
        end
        Model.observeRescues(state.rescues,sim,{Evac=state.autoEvac,Rooftop=state.autoRooftop},state.fullFarm,os.clock())
        local ratio,margin=Model.preservation(sim)
        if ratio then
            preservation:Set(string.format("Population preserved: %.1f%% · S margin: %d people\nS requires a win with at least 85%% preserved. Rewards use the game's normal result flow.",ratio*100,math.max(0,margin)))
            if ratio<.85 and not state.riskNotified and state.fullFarm then state.riskNotified=true;notify("S objective at risk","Population is below the S threshold. Continuing rescue; this round cannot currently meet the S requirement.") end
        end
        local boats,roofs=0,0
        for _,p in pairs(state.rescues.points) do if p.tool=="Evac" then boats+=1 else roofs+=1 end end
        rescueStatus:Set(state.fullFarm and "Full autofarm: choosing rescue locations from this map and your equipped tools." or string.format("Your repeated sites: %d evac · %d rooftop\nEnable repeat, then start an extraction in the game. No chosen sites means no automatic placement.",boats,roofs))
        threatLabels(ctx)
        if state.showThreats then
            local lines={string.format("%d known visible groups. Hidden outbreaks still need recon.",#(state.threats or {}))}
            for i=1,math.min(3,#(state.threats or {})) do
                local c=state.threats[i];local ok,sector=pcall(sim.city.sectorName,sim.city,c.x,c.y)
                table.insert(lines,string.format("%d zombies · %s (%.0f, %.0f)",c.count,ok and tostring(sector) or "Map",c.x,c.y))
            end
            threatStatus:Set(table.concat(lines,"\n"))
        else threatStatus:Set("Enable zombie labels to track visible groups and their locations.") end
        if os.clock()-(state.lastStatRefresh or -100)>.8 then
            state.lastStatRefresh=os.clock();budget:Set(math.floor(sim.budget));evacuated:Set(sim.stats and (sim.stats.evacuated or sim.stats.safe) or sim.safe or 0)
        end
        if state.farmPolicy then strategy:Set(string.format("%s · current buffer $%d\n%s",state.farmPolicy.stage,state.farmPolicy.reserve,strongpoint(ctx) and "Gather survivors at the fortified base; protect entrances and medical services." or "Containment, rescue and medical coverage take priority over new defenses.")) end
        local phase=sim.over and "Ended" or (ctx.hud.overlay and ctx.hud.overlay.Visible and "Briefing / menu" or "Active")
        status:Set(string.format("%s · Day %d · %s\nQueue %d/%d · %d actions submitted",sim.__mpMirror and "Multiplayer" or "Single player",sim.day or 1,phase,math.min(state.index,#state.queue),#state.queue,state.submitted))
        if sim.over then
            state.playing=false
            if not state.resultLogged then
                state.resultLogged=true;local _,grade=sim:score();log("Round ended: "..tostring(sim.over).." · grade "..tostring(grade).." · RP "..tostring(sim.researchGained or 0))
            end
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
            if state.playing or state.autoEvac or state.autoRooftop or state.autoRecon or state.autoMedics or state.autoStrike or state.autoHQ or state.autoSupplies or state.autoCandy or state.autoClinic or state.autoOrdnance or state.autoRepeat or state.fullFarm or state.autoDefenses or state.autoFort then state:Stop();log("Complete the tutorial manually before enabling automation.") end
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
        if os.clock()-state.lastAttempt<(state.fullFarm and .25 or 2) then return true end
        state.lastAttempt=os.clock()
        local ready=usable(ctx);if not ready then return true end
        if state.autoHQ then updateHQ(ctx) end
        if state.autoSupplies or state.autoCandy then
            local cap=ctx.config.candyMax and ctx.config.candyMax(sim.level) or 0
            for i,crate in ipairs(Model.pickups(sim,state.autoSupplies,state.autoCandy,cap)) do
                if i>8 then break end
                local key=tostring(crate.candy)..":"..crate.x..":"..crate.y..":"..crate.expire
                if os.clock()-(state.pickupPending[key] or -100)<1 then continue end
                state.pickupPending[key]=os.clock()
                local receipt=sim:claimCrate(crate.x,crate.y)
                if receipt then
                    if receipt.candy then state.candyPicked+=1;log(sim.__mpMirror and "Sent candy pickup." or "Picked up a candy drop.")
                    else log(sim.__mpMirror and "Sent supply pickup." or "Collected a supply drop.") end
                end
            end
        end
        if state.playing then
            if state.session~=sim then state:Stop();return true end
            local step=state.queue[state.index]
            if not step then state.playing=false;log("Placement queue finished.");return true end
            local ok,reason=submit(ctx,step.tool,step.x,step.y,state.reserve,"manual")
            if ok then state.index+=1;state.waitSince=os.clock()
            elseif os.clock()-(state.waitSince or os.clock())>90 then state.playing=false;log("Queue paused: "..tostring(reason)) end
            return true
        end
        local candidate,id,repeatIndex
        local planningReserve=state.farmPolicy and state.farmPolicy.reserve or state.reserve
        local medicine=getTool(ctx,"Medics")
        local medicineCost=medicine and state.autoMedics and (sim:effective(medicine).cost or 90) or 0
        for n=#state.deployments,1,-1 do if state.deployments[n].untilTime<=sim.time then table.remove(state.deployments,n) end end
        local response,responseId,responseCost
        local equippedResponses={}
        for _,toolId in ipairs(combatTools) do equippedResponses[toolId]=getTool(ctx,toolId)~=nil end
        if state.fullFarm and state.autoStrike then
            response=Model.support(sim,2,state.deployments)
            if response then responseId=Model.responseTool(response,equippedResponses) end
            if responseId then responseCost=sim:effective(getTool(ctx,responseId)).cost end
        end
        local responseReserve=responseCost or 0
        if state.autoOrdnance and getTool(ctx,"Airstrike") and sim.budget>=(sim:effective(getTool(ctx,"Airstrike")).cost or 300) and os.clock()-(state.lastStrikeScan or -100)>1 then
            state.lastStrikeScan=os.clock();local _,margin=Model.preservation(sim)
            state.strikePlan=Model.ordnance(sim,sim:effective(getTool(ctx,"Airstrike")),math.min(30,math.max(3,math.floor((margin or 300)*.1))))
        end
        local function available(toolId)
            local tool=getTool(ctx,toolId)
            if not tool or os.clock()-(state.pending[toolId] or -100)<(state.fullFarm and (sim.__mpMirror and .75 or .25) or 3) then return false end
            local effective=sim:effective(tool)
            local reserve=planningReserve
            if state.fullFarm and toolId=="Recon" then reserve=math.max(reserve,medicineCost) end
            if state.fullFarm and (toolId=="Ghosts" or toolId=="Hunters" or toolId=="Strike") and toolId~=responseId then reserve=math.max(reserve,responseReserve) end
            return sim.budget-(effective.cost or 0)>=reserve and sim:canUse(effective)
        end
        if state.autoOrdnance and state.strikePlan and available("Airstrike") then
            if submitOrdnance(ctx,state.strikePlan,planningReserve) then state.strikePlan=nil;return true end
        end
        if state.fullFarm and not sim.__mpMirror and state.autoRecon and available("Recon") then
            candidate=Model.sourceIntel(sim,sim:effective(getTool(ctx,"Recon")).radius);id="Recon"
        end
        if not candidate and state.fullFarm and state.autoMedics and available("Medics") then
            local eff=sim:effective(medicine)
            candidate=Model.treatment(sim,eff.radius,eff.doses or 30,not sim.__mpMirror)
            if candidate and candidate.count<state.farmPolicy.minCures then candidate=nil end
            if not candidate and sim.__mpMirror then candidate=Model.reportTreatment(sim,eff.radius,state.treatedReports) end
            id="Medics"
        end
        if not candidate and response and responseId and available(responseId) then candidate=response;id=responseId end
        if not candidate and state.autoMedics and available("Medics") then
            if state.fullFarm then local effective=sim:effective(getTool(ctx,"Medics"));candidate=Model.treatment(sim,effective.radius,effective.doses or 30,not sim.__mpMirror)
            else candidate=Model.target(sim,"Infected",state.minInfected,65) end
            if state.fullFarm and candidate and candidate.count<state.farmPolicy.minCures then candidate=nil end
            id="Medics"
        end
        if not candidate and state.fullFarm and sim.__mpMirror and state.autoRecon and available("Recon") then
            candidate=Model.intel(sim,state.intelVisits,sim:effective(getTool(ctx,"Recon")).radius);id="Recon"
        end
        if not candidate and state.fullFarm and (sim.time<15 or sim.budget>=650) and sim.city.base and #(sim.depots or {})==0 and available("Depot") and sim.budget>=380 then
            local r=sim.city.base.rect;local x,y=sim.city:nearestWalkable((r[1]+r[2])/2,(r[3]+r[4])/2)
            if x and sim:inBase(x,y) then candidate={x=x,y=y};id="Depot" end
        end
        if not candidate and state.fullFarm and (#(sim.depots or {})>0 or sim.time>3) and baseOperations(ctx) then return true end
        if not candidate and state.autoClinic and available("Tent") and #(sim.tents or {})<4 then
            local cost=sim:effective(getTool(ctx,"Tent")).cost or 120
            if sim.budget>=cost+(#(sim.tents or {})==0 and planningReserve or math.max(planningReserve,medicineCost)) then
                candidate=Model.clinic(sim,sim:effective(getTool(ctx,"Tent")).pullRange or 280);id="Tent"
            end
        end
        if not candidate and state.autoEvac and available("Evac") then
            if state.fullFarm then candidate=Model.evac(sim,state.minEvac,state.dangerRadius)
            else candidate,repeatIndex=Model.repeatRescue(state.rescues,sim,"Evac") end
            id="Evac"
        end
        if not candidate and state.autoRooftop and available("Rooftop") and (not state.fullFarm or state.farmPolicy.roof) then
            if state.fullFarm then candidate=Model.rooftop(sim,state.minEvac,sim:effective(getTool(ctx,"Rooftop")).radius or 100)
            else candidate,repeatIndex=Model.repeatRescue(state.rescues,sim,"Rooftop") end
            id="Rooftop"
        end
        if not candidate and state.autoRecon and available("Recon") then candidate=reconPoint(ctx);id="Recon" end
        if not candidate and state.autoStrike and not state.fullFarm then
            for _,combat in ipairs(combatTools) do
                if available(combat) then
                    candidate=Model.target(sim,"Zombie",state.minZombies,85)
                    id=combat;if candidate then break end
                end
            end
        end
        if not candidate and state.autoFort and available("Fort") and sim.budget>=state.reserve+500 and (not state.fullFarm or state.farmPolicy.build) then
            local effective=sim:effective(getTool(ctx,"Fort"));local count=#(sim.forts or {})
            for _,build in ipairs(sim.builds or {}) do if build.kind=="fort" then count+=1 end end
            if not effective.maxCount or count<effective.maxCount then
                for _,squad in ipairs(ownedSquads(ctx)) do
                    local members=sim:squadMembers(squad)
                    if members[1] then candidate=Model.sentry(sim,defendPoint(sim,members[1]),(ctx.config.FORT or {}).MIN_SPACING or 40);id="Fort";break end
                end
            end
        end
        local placed=false
        if candidate then
            local ok,reason=submit(ctx,id,candidate.x,candidate.y,planningReserve)
            if not ok and reason~=state.lastWait then log(reason);state.lastWait=reason end
            if ok then
                placed=true
                state.lastWait=nil
                if repeatIndex then state.rescues.cursor[id]=repeatIndex end
                if id=="Recon" and candidate.visit then state.reconVisits[candidate.visit]=os.clock() end
                if id=="Recon" and candidate.intelKey then state.intelVisits[candidate.intelKey]=sim.time end
                if id=="Medics" and candidate.reportKey then state.treatedReports[candidate.reportKey]=true;state.intelVisits[candidate.intelKey]=sim.time end
                if id=="Recon" and candidate.visit then state.lastSweep=sim.time end
            end
        end
        if not placed and state.autoDefenses then updateDefenses(ctx) end
        return true
    end
    table.insert(state.connections,Input.InputBegan:Connect(function(input,processed)
        if input.KeyCode==Enum.KeyCode.F10 then state:Stop();notify("Last Stand","All automation stopped.");return end
        if processed or Input:GetFocusedTextBox() then return end
        if input.KeyCode==Enum.KeyCode.F8 then guarded(function() state:MarkAtCursor() end)()
        elseif input.KeyCode==Enum.KeyCode.F9 then guarded(function() state:Enqueue() end)() end
    end))
    -- Reposition only pooled labels while panning/zooming. Threat discovery and
    -- planning stay on the slower scheduler; there is no per-agent render loop.
    table.insert(state.connections,RunService.RenderStepped:Connect(function()
        local ctx=state.lastContext
        if not state.alive or not state.showThreats or not state.threatGui or not ctx or ctx.sim~=state.bound then return end
        local world=ctx.hud.world
        if not world or not world.Parent then
            for _,label in ipairs(state.labels) do label.Visible=false end
        elseif world~=state.labelWorld or world.AbsolutePosition~=state.labelPosition or world.AbsoluteSize~=state.labelSize then
            threatLabels(ctx,true)
        end
    end))
    state.runner=task.spawn(function()
        while state.alive and not window.unloaded do
            local updateStart=os.clock()
            local ok,keep=pcall(update)
            state.updateMs=(os.clock()-updateStart)*1000
            state.maxUpdateMs=math.max(state.maxUpdateMs or 0,state.updateMs)
            if not ok then
                state.lastError=tostring(keep)
                state:Stop();log("Update failed: "..state.lastError);notify("Last Stand paused",state.lastError);break
            end
            if not keep then break end
            task.wait(state.fullFarm and .35 or .75)
        end
        if state.alive then state:Destroy() end
    end)
end)
if not built then state:Destroy();error("Last Stand | UI failed: "..tostring(buildError)) end
notify("Last Stand ready","Automation starts off. Finish the tutorial, then configure your loadout and reserve.")
return state
