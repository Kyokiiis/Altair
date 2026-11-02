-- CLOCK MODEL BEGIN
local Clock=(function()
-- Monotonic timer/stopwatch model. No rendering, yields, or Roblox dependencies.
local Clock = {}
Clock.__index = Clock

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Clock.new(now)
	return setmetatable({now = now or os.clock, timer = nil,
		watch = {elapsed = 0, started = nil, laps = {}, splitAt = 0, active = false}, revision = 0}, Clock)
end

function Clock:StartTimer(seconds)
	assert(finite(seconds) and seconds >= 1 and seconds <= 86400, "Timer must be between 1 second and 24 hours")
	self.timer = {remaining = seconds, started = self.now(), duration = seconds, finished = false}
	self.revision += 1
end

function Clock:Remaining()
	local timer = self.timer
	if not timer then return 0 end
	return math.max(0, timer.remaining - (timer.started and math.max(0, self.now() - timer.started) or 0))
end

function Clock:ToggleTimer()
	local timer = self.timer
	if not timer or timer.finished then return end
	if timer.started then timer.remaining = self:Remaining(); timer.started = nil
	else timer.started = self.now() end
	self.revision += 1
end

function Clock:CancelTimer()
	self.timer = nil
	self.revision += 1
end

function Clock:Elapsed()
	local watch = self.watch
	return watch.elapsed + (watch.started and math.max(0, self.now() - watch.started) or 0)
end

function Clock:ToggleWatch()
	local watch = self.watch
	watch.active = true
	if watch.started then watch.elapsed = self:Elapsed(); watch.started = nil
	else watch.started = self.now() end
	self.revision += 1
end

function Clock:Lap()
	local watch = self.watch
	if not watch.started then return false end
	local elapsed = self:Elapsed()
	watch.laps[#watch.laps + 1] = {number = (watch.lapCount or 0) + 1, seconds = elapsed - watch.splitAt}
	watch.lapCount = (watch.lapCount or 0) + 1
	watch.splitAt = elapsed
	if #watch.laps > 30 then table.remove(watch.laps, 1) end
	self.revision += 1
	return true
end

function Clock:ResetWatch()
	self.watch = {elapsed = 0, started = nil, laps = {}, splitAt = 0, active = false, lapCount = 0}
	self.revision += 1
end

function Clock:Tick()
	local timer = self.timer
	if timer and not timer.finished and self:Remaining() <= 0 then
		timer.remaining, timer.started, timer.finished = 0, nil, true
		self.revision += 1
		return true -- Edge-triggered: exactly one completion per timer.
	end
	return false
end

function Clock.Format(seconds, hundredths, roundUp)
	seconds = finite(seconds) and math.max(0, seconds) or 0
	local whole = roundUp and math.ceil(seconds) or math.floor(seconds)
	local hours, minutes, remainder = math.floor(whole / 3600), math.floor(whole / 60) % 60, whole % 60
	local result = hours > 0 and string.format("%d:%02d:%02d", hours, minutes, remainder)
		or string.format("%02d:%02d", math.floor(whole / 60), remainder)
	if hundredths then result ..= string.format(".%02d", math.min(99,math.floor((seconds % 1) * 100 + 0.000001))) end
	return result
end

return Clock

end)()
-- CLOCK MODEL END

-- One interruptible owner per animated property across all UI surfaces.
local motionStats={requested=0,created=0,reused=0,skipped=0}
-- A completed animation needs no engine Tween/Instance when nothing can change.
local function completedMotion(apply)
 local listeners={};local signal={};local animation={PlaybackState=Enum.PlaybackState.Begin,Completed=signal}
 function signal:Connect(fn)local c={Connected=true};function c:Disconnect()self.Connected=false end;listeners[#listeners+1]={fn,c};return c end
 signal.Once=signal.Connect
 local function finish(state)
  animation.PlaybackState=state
  for _,entry in ipairs(listeners)do if entry[2].Connected then entry[2].Connected=false;task.defer(entry[1],state)end end
  table.clear(listeners)
 end
 function animation:Play()if self.PlaybackState~=Enum.PlaybackState.Begin then return end;if apply then apply();apply=nil end;finish(Enum.PlaybackState.Completed)end
 function animation:Cancel()if self.PlaybackState==Enum.PlaybackState.Begin then finish(Enum.PlaybackState.Cancelled)end end
 animation.Destroy=animation.Cancel;animation.Pause=animation.Cancel
 return animation
end
local function opacityOffscreen(object)
 if not object:IsA("GuiObject")and not object:IsA("UIStroke")then return false end
 local visual=object:IsA("GuiObject")and object or object.Parent
 local parent=visual
 while parent and not parent:IsA("ScreenGui")do
  if parent:IsA("GuiObject")then
   if not parent.Visible then return true end
   if parent~=visual and parent:IsA("CanvasGroup")and parent.GroupTransparency>.999 then return true end
   if parent~=visual and parent:IsA("ScrollingFrame")then
    local p,z=visual.AbsolutePosition,visual.AbsoluteSize;local q,w=parent.AbsolutePosition,parent.AbsoluteSize
    if p.Y+z.Y<=q.Y or p.Y>=q.Y+w.Y or p.X+z.X<=q.X or p.X>=q.X+w.X then return true end
   end
  end
  parent=parent.Parent
 end
 return false
end
local function motionService(reduced,preserveTiming)
 local native=game:GetService("TweenService")
 local owners=setmetatable({}, {__mode="k"});local targets=setmetatable({}, {__mode="k"})
 return {Create=function(_,object,info,goal)
  motionStats.requested+=1
  local root=object:FindFirstAncestorOfClass("ScreenGui")
  local bar=root and root:FindFirstChild("SmartBar");local handle=root and root:FindFirstChild("Drag")
  local transient=root and root:GetAttribute("AltairThemePulse")and((bar and(object==bar or object:IsDescendantOf(bar)))or(handle and(object==handle or object:IsDescendantOf(handle))))
  local closing=not object:GetAttribute("AltairMorphVisual") and object.Parent
  while closing and not closing:GetAttribute("AltairClosing") do closing=closing.Parent end
  if closing then
   goal=table.clone(goal)
   for key,value in pairs(goal) do if type(value)=="number" and key:find("Transparency",1,true) then goal[key]=1 end end
  end
  if object:GetAttribute("AltairInsetMaterial") and goal.BackgroundTransparency~=nil then goal=table.clone(goal);goal.BackgroundTransparency=1 end
  if object:GetAttribute("AltairInsetOutline")and goal.Transparency~=nil then goal=table.clone(goal);goal.Transparency=1 end
  if object:GetAttribute("AltairSurfaceOutline")and goal.Transparency and goal.Transparency<.99 and not transient then goal=table.clone(goal);goal.Transparency=.65 end
  if object:GetAttribute("AltairGlowCap")and goal.ImageTransparency then goal=table.clone(goal);goal.ImageTransparency=1-(1-goal.ImageTransparency)*object:GetAttribute("AltairGlowCap")end
  if object:GetAttribute("AltairSharedSwitch") and goal.BackgroundTransparency~=nil then goal=table.clone(goal);goal.BackgroundTransparency=1 end
  if object:IsA("UIStroke") and object.Parent and object.Parent:GetAttribute("AltairSharedSwitch") and goal.Transparency~=nil then
   object.Parent:SetAttribute("AltairSharedStroke",goal.Transparency);goal=table.clone(goal);goal.Transparency=1
  end
  if root and root:GetAttribute("AltairThemeEnabled")and not root:GetAttribute("AltairThemeRainbow")and not transient then
   for key,value in pairs(goal)do local target=object:GetAttribute("AltairTheme_"..key);if target and(typeof(value)=="Color3"or typeof(value)=="ColorSequence")then goal=table.clone(goal);goal[key]=target end end
  end
  if closing then
   local onlyOpacity=true;for property in pairs(goal)do if not property:find("Transparency",1,true)then onlyOpacity=false;break end end
   local parent=object.Parent
   while onlyOpacity and parent and parent~=closing do
    if parent:GetAttribute("AltairFadeGroup")then motionStats.skipped+=1;return completedMotion()end
    parent=parent.Parent
   end
  end
  local current=owners[object] or {};owners[object]=current
  local target=targets[object]or{};targets[object]=target
  local simple=info.RepeatCount==0 and not info.Reverses and info.DelayTime==0
  if simple then
   local same,unchanged,opacity=true,true,true;local existing
   for property,value in pairs(goal)do
    local old=current[property]
    if not old or target[property]~=value or old.PlaybackState~=Enum.PlaybackState.Playing or(existing and old~=existing)then same=false end
    existing=existing or old
    if object[property]~=value then unchanged=false end
    if not property:find("Transparency",1,true)then opacity=false end
   end
   if same and existing then motionStats.reused+=1;return existing end
   local shared=object.Parent
   while shared and not shared:IsA("ScreenGui")and not shared:GetAttribute("AltairSharedSwitch")do shared=shared.Parent end
   local slide=opacity and shared and shared:GetAttribute("AltairSharedSwitch")and object~=shared and object.Parent~=shared
   local hidden=opacity and not unchanged and(opacityOffscreen(object)or slide)
   if unchanged or hidden then
    local cancelled={}
    for property in pairs(goal)do local old=current[property];if old and not cancelled[old]then cancelled[old]=true;old:Cancel()end;current[property]=nil;target[property]=nil end
    motionStats.skipped+=1
    return completedMotion(hidden and function()if object.Parent then for property,value in pairs(goal)do object[property]=value end end end or nil)
   end
  end
  local cancelled={}
  for property in pairs(goal) do local old=current[property];if old and not cancelled[old] then cancelled[old]=true;old:Cancel() end end
  local visual=object:IsA("GuiObject") or object:IsA("UIStroke") or object:IsA("UIScale") or object:IsA("UIGradient")
  if visual and not preserveTiming and info.Time>0 and info.RepeatCount==0 and not info.Reverses then
   local layout=goal.Position or goal.Size or goal.Scale or goal.CanvasPosition
   local duration=layout and math.clamp(info.Time,.1,.38) or math.min(info.Time,.22)
   if closing and not layout then duration=math.min(duration,.06) end
   if reduced and reduced() then duration=math.min(duration,.08) end
   info=TweenInfo.new(duration,layout and Enum.EasingStyle.Quint or Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,false,info.DelayTime)
  end
  if preserveTiming and info.Time>0 then
   local time=closing and math.min(info.Time,.06)or root and root:GetAttribute("AltairReduceMotion")and math.min(info.Time,.08)or info.Time
   if time~=info.Time then info=TweenInfo.new(time,info.EasingStyle,info.EasingDirection,info.RepeatCount,info.Reverses,info.DelayTime)end
  end
  motionStats.created+=1
  local animation=native:Create(object,info,goal)
  for property,value in pairs(goal) do current[property]=animation;target[property]=value end
  animation.Completed:Once(function() for property in pairs(goal) do if current[property]==animation then current[property]=nil;target[property]=nil end end end)
  return animation
 end}
end

-- NOTIFICATIONS BEGIN
local buildNotifications=(function()
-- Reference: 300px black capsules; 20px corners, 8px stack spacing, content-sized height.
return function(context)
	local root=context.Root
	local tweenService=motionService(function() return root:GetAttribute("AltairReduceMotion")==true end)
	local textService = game:GetService("TextService")
	local controller = {alive = true, active = {}, pending = {}, nextId = 0}
	local builtHost=root:FindFirstChild("NotificationCapsules")
	local template=builtHost and builtHost:FindFirstChild("CardTemplate")
	if context.RequireBuiltUI then assert(template,"Build.lua is missing the notification card template") end
	local font = template and template.Description.FontFace or Font.new("rbxasset://fonts/families/GothamSSm.json")
	local titleFont=template and template.Title.FontFace or Font.new(font.Family,Enum.FontWeight.Medium)
	local host = builtHost or Instance.new("Frame")
	host.Name, host.BackgroundTransparency, host.Size, host.ZIndex = "NotificationCapsules", 1, UDim2.fromScale(1, 1), 350
	host.Parent = root
	local connections, tweens = {}, setmetatable({}, {__mode = "k"})
	local function connect(signal, fn)
		local connection = signal:Connect(fn); connections[#connections+1] = connection; return connection
	end
	local function tween(object, time, properties)
		-- The shared service owns each property independently.
		local animation = tweenService:Create(object, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), properties)
		tweens[object] = animation
		animation.Completed:Once(function() if tweens[object]==animation then tweens[object]=nil end end)
		animation:Play()
	end
	local function label(parent, name, text, size, color)
		local object = Instance.new("TextLabel")
		object.Name, object.Text, object.TextSize, object.TextColor3 = name, text, size, color
		object.FontFace, object.BackgroundTransparency, object.TextXAlignment = font, 1, Enum.TextXAlignment.Left
		object.TextYAlignment, object.RichText, object.TextWrapped = Enum.TextYAlignment.Top, false, true
		object.ZIndex=351; object.TextTruncate=Enum.TextTruncate.AtEnd
		object.Parent = parent; return object
	end
	local function dimensions(title, description, icon, width, measured)
		local left = icon and 58 or 20
		local available = width - left - 20
		local titleHeight,descriptionHeight
		if measured and measured.width==width then titleHeight,descriptionHeight=measured.title,measured.body
		else
			titleHeight=math.max(17,textService:GetTextSize(title,14,Enum.Font.GothamMedium,Vector2.new(available,1000)).Y)
			descriptionHeight=description~="" and math.max(16,textService:GetTextSize(description,13,Enum.Font.Gotham,Vector2.new(available,1000)).Y) or 0
		end
		titleHeight=math.min(titleHeight,34);descriptionHeight=math.min(descriptionHeight,112)
		return descriptionHeight==0 and math.max(44,27+titleHeight) or 28+titleHeight+descriptionHeight+3, left, titleHeight, descriptionHeight
	end
	function controller:Layout(instant)
        if #self.active==0 then return end
		if not self.alive or #self.active==0 then return end
		local viewport,origin=root.AbsoluteSize,root.AbsolutePosition
		local factor=root:GetAttribute("AltairDisplayScale") or 1
		local width=math.min(300*factor,math.max(160,viewport.X-40))
		local x=math.max(20,viewport.X-width-24)
		local obstacles={}
		local function add(object)
			if object and object:IsA('GuiObject') and object.Visible then
				local p,s=object.AbsolutePosition-origin,object.AbsoluteSize
				if s.X>0 and s.Y>0 then obstacles[#obstacles+1]={x=p.X,y=p.Y,w=s.X,h=s.Y} end
			end
		end
		local bar=root:FindFirstChild('SmartBar')
		if not (bar and bar.Visible) then bar=root:FindFirstChild('Drag') end
  -- Notifications keep their normal corner; only real overlaps trigger avoidance.
  local topDock=false
		for _,name in {'SmartBar','Drag','Character','Scripts','Playerlist','Settings','Home','ScriptSearch','CustomScriptPrompt','ModeratorDetectionPrompt'} do add(root:FindFirstChild(name)) end
		local capsules=root:FindFirstChild('TopCapsules')
		if capsules and capsules.Visible then
			local expanded=capsules:FindFirstChild('Surface')
			add(expanded and expanded.Visible and expanded or capsules:FindFirstChild('Compact'))
		end
		local toasts=root:FindFirstChild('Toasts')
		if toasts and toasts.Visible then for _,v in toasts:GetChildren() do if v.Name~='Template' then add(v) end end end
		local total=0
		for _,record in ipairs(self.active) do
			local height,left,titleHeight,descriptionHeight=dimensions(record.title,record.description,record.icon,width/factor,record.measured)
			local scale=record.group:FindFirstChild("AltairDisplayScale") or Instance.new("UIScale");scale.Name="AltairDisplayScale";scale.Scale=factor;scale.Parent=record.group
			record.height=height*factor;record.group.Size=UDim2.fromOffset(width/factor,height)
			record.titleLabel.Position,record.titleLabel.Size=UDim2.fromOffset(left,14),UDim2.new(1,-left-20,0,titleHeight)
			record.body.Position,record.body.Size=UDim2.fromOffset(left,17+titleHeight),UDim2.new(1,-left-20,0,descriptionHeight)
			record.body.Visible=descriptionHeight>0
			total+=height*factor+8
		end
		total-=8
		local y=viewport.Y-24-total
		local preferred=y
		for _=1,#obstacles+1 do
			local nextY=y
			for _,box in ipairs(obstacles) do
				if x<box.x+box.w+8 and x+width>box.x-8 and y<box.y+box.h+8 and y+total>box.y-8 then
					nextY=topDock and math.max(nextY,box.y+box.h+8) or math.min(nextY,box.y-total-8)
				end
			end
			if nextY==y then break end
			if nextY<24 or nextY+total>viewport.Y-24 then
				-- On small screens, keep the complete stack readable over large panels.
				-- Still reserve space for the SmartBar when it shares this column.
				y=preferred
				if bar and bar.Visible then
					local p,s=bar.AbsolutePosition-origin,bar.AbsoluteSize
					if x<p.X+s.X+8 and x+width>p.X-8 then
						y=topDock and math.max(y,p.Y+s.Y+8) or math.min(y,p.Y-total-8)
					end
				end
				break
			end
			y=nextY
		end
		y=math.clamp(y,16,math.max(16,viewport.Y-total-16))
		for _,record in ipairs(self.active) do
			local goal=UDim2.fromOffset(x,y)
			if record.fresh then record.group.Position=goal+UDim2.fromOffset(width+32,0);record.fresh=false end
			if instant then record.group.Position=goal
			elseif not record.goal or math.abs(record.goal.X.Offset-x)>.5 or math.abs(record.goal.Y.Offset-y)>.5 then
				tween(record.group,.28,{Position=goal})
			end
			record.goal=goal;y+=record.height+8
		end
	end
	local pump
	function controller:Dismiss(record)
		if not self.alive or record.closing then return end
		record.closing = true; record.generation += 1
		if record.fade then record.fade:Cancel() end
		local index = table.find(self.active, record)
		if index then table.remove(self.active, index) end
		for _, connection in ipairs(record.connections) do connection:Disconnect() end
		tween(record.group, 0.28, {Position = record.group.Position + UDim2.fromOffset(36,0), GroupTransparency = 1})
		task.delay(0.3, function() if record.group.Parent then record.group:Destroy() end end)
		self:Layout(); pump()
	end
	local function expiry(record, delay)
		record.generation += 1
		local generation = record.generation
		record.deadline = os.clock() + delay
		task.delay(delay, function()
			if controller.alive and not record.closing and generation == record.generation and not record.hovered then
				controller:Dismiss(record)
			end
		end)
	end
	local function spawnRecord(item)
		local group = template and template:Clone() or Instance.new("CanvasGroup")
		group.Visible=true;group.BackgroundTransparency=root:GetAttribute("AltairPanelTransparency") or .12
		group.Name="Notification_"..item.id
		if not template then group.BackgroundColor3,group.BorderSizePixel=Color3.fromRGB(17,17,17),0 end
		group.Size, group.GroupTransparency, group.ZIndex = UDim2.fromOffset(300, 64), 1, 350
		if not template then
			local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,20);corner.Parent=group
			local gradient=Instance.new("UIGradient");gradient.Rotation=90
			gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(115,115,115));gradient.Parent=group
		end
        -- CanvasGroup gradients tint the composited text too. Material belongs on its own layer.
        local background=Instance.new("Frame");background.Name="CardBackground";background.Size=UDim2.fromScale(1,1);background.BackgroundColor3=group:GetAttribute("AltairThemeDefault_BackgroundColor3")or Color3.fromRGB(17,17,17);background.BackgroundTransparency=root:GetAttribute("AltairPanelTransparency")or .12;background.BorderSizePixel=0;background.ZIndex=350;background:SetAttribute("AltairSurface",true);background.Parent=group
        local round=group:FindFirstChildOfClass("UICorner");if round then round:Clone().Parent=background end
        local gradient=group:FindFirstChildOfClass("UIGradient");if gradient then gradient.Parent=background end
        local outline=group:FindFirstChildOfClass("UIStroke");if outline then outline.Parent=background end
        group.BackgroundTransparency=1;group:SetAttribute("AltairNotificationCard",true)
		item.group,item.generation,item.connections=group,0,{};item.fresh=true
		item.titleLabel=group:FindFirstChild("Title") or label(group,"Title",item.title,14,Color3.new(1,1,1))
		item.titleLabel.TextColor3=Color3.new(1,1,1);item.titleLabel.Text=item.title;item.titleLabel.FontFace=titleFont
		item.body=group:FindFirstChild("Description") or label(group,"Description",item.description,13,Color3.new(1,1,1));item.body.TextColor3=Color3.new(1,1,1)
		item.body.Text=item.description
		local icon=group:FindFirstChild("Icon")
		if not icon then
			icon=Instance.new("ImageLabel");icon.Name="Icon";icon.BackgroundTransparency=1
			icon.Size,icon.Position,icon.AnchorPoint=UDim2.fromOffset(22,22),UDim2.new(0,20,.5,0),Vector2.new(0,.5)
			icon.ImageColor3,icon.ZIndex,icon.Parent=Color3.new(1,1,1),351,group
		end
		local friend,staff=group:FindFirstChild("FriendIcon"),group:FindFirstChild("StaffIcon")
		local friendIcon=friend and item.icon and item.icon:find("4370335364",1,true)~=nil
		local staffIcon=staff and item.icon and item.icon:find("3944670656",1,true)~=nil
		if friend then friend.Visible=friendIcon==true end
		if staff then staff.Visible=staffIcon==true end
		icon.Visible=item.icon~=nil and not friendIcon and not staffIcon;icon.Image=item.icon or ""
		local button=group:FindFirstChild("Dismiss")
		if not button then
			button=Instance.new("TextButton");button.Name="Dismiss";button.Text="";button.BackgroundTransparency=1
			button.AutoButtonColor=false;button.Size=UDim2.fromScale(1,1);button.ZIndex=354;button.Parent=group
		end
		group.Position, group.Parent = UDim2.new(1,60,1,-100), host
		controller.active[#controller.active+1] = item
		controller:Layout()
		-- Opacity has its own tween so a stack reflow cannot cancel the fade.
		item.fade = tweenService:Create(group, TweenInfo.new(0.28), {GroupTransparency=0}); item.fade:Play()
		item.connections[1] = button.Activated:Connect(function() controller:Dismiss(item) end)
		item.connections[2] = button.MouseEnter:Connect(function()
			item.hovered, item.remaining = true, math.max(0.5, item.deadline - os.clock()); item.generation += 1
		end)
		item.connections[3] = button.MouseLeave:Connect(function() item.hovered = false; expiry(item, item.remaining or 2) end)
		expiry(item, item.duration)
	end
	pump = function()
		if not controller.alive then return end
		local used=0
		for _,record in ipairs(controller.active) do used+=record.height+8 end
		while #controller.pending>0 and #controller.active<5 do
			local item=controller.pending[1]
			if not item.ready then break end
			local height=dimensions(item.title,item.description,item.icon,math.min(300,math.max(160,root.AbsoluteSize.X-40)),item.measured)
			if #controller.active>0 and used+height>root.AbsoluteSize.Y-48 then break end
			spawnRecord(table.remove(controller.pending,1));used+=height+8
		end
	end
	function controller:Notify(title, description, icon, options)
		if not self.alive then return nil end
		options = type(options) == "table" and options or {}
		title, description = tostring(title or "Altair"):sub(1,160), tostring(description or ""):sub(1,1200)
		if icon ~= nil and icon ~= false and icon ~= "" then
			icon = tonumber(icon) and ("rbxassetid://" .. tostring(icon)) or tostring(icon)
		else icon = nil end
		local duration=math.clamp(tonumber(options.Duration) or tonumber(root:GetAttribute("AltairNotificationDuration")) or (2.5+#description*0.045),2.5,12)
		local key=type(options.Key)=="string" and options.Key:sub(1,80) or nil
		if key then
			for _,list in {self.active,self.pending} do for _,record in ipairs(list) do
				if record.key==key and record.title==title and record.description==description and record.icon==icon then
					record.duration=duration
					if record.group then
						if record.hovered then record.remaining=duration else expiry(record,duration) end
					end
					return {Dismiss=function()
						local pending=table.find(self.pending,record)
						if pending then table.remove(self.pending,pending) elseif record.group then self:Dismiss(record) end
					end}
				end
			end end
		end
		self.nextId += 1
		local item = {id=self.nextId,title=title,description=description,icon=icon,key=key,
			duration=duration}
		if #self.pending >= 24 then table.remove(self.pending,1) end
		self.pending[#self.pending+1] = item
		task.spawn(function()
			-- Measure the actual FontFace once, outside layout/render loops.
			local width=math.min(300,math.max(160,root.AbsoluteSize.X-40))
			local params=Instance.new("GetTextBoundsParams")
			params.Width=width-(icon and 58 or 20)-20;params.RichText=false
			local ok,measured=pcall(function()
				params.Font=titleFont;params.Size=14;params.Text=title
				local titleHeight=math.max(17,math.ceil(textService:GetTextBoundsAsync(params).Y))
				params.Font=font;params.Size=13;params.Text=description
				return {width=width,title=titleHeight,body=description~="" and math.max(16,math.ceil(textService:GetTextBoundsAsync(params).Y)) or 0}
			end)
			params:Destroy()
			if not self.alive then return end
			if ok then item.measured=measured end
			item.ready=true;pump()
		end)
		return {Dismiss=function()
			local pending = table.find(self.pending,item)
			if pending then table.remove(self.pending,pending) elseif item.group then self:Dismiss(item) end
		end}
	end
	function controller:GetObstacles()
		local objects = {}
		for _, item in ipairs(self.active) do objects[#objects+1] = item.group end
		return objects
	end
	function controller:Destroy()
		if not self.alive then return end
		self.alive = false
		for _, connection in ipairs(connections) do connection:Disconnect() end
		for _, item in ipairs(self.active) do
			item.generation += 1
			if item.fade then item.fade:Cancel() end
			for _, connection in ipairs(item.connections) do connection:Disconnect() end
		end
		for _, animation in pairs(tweens) do animation:Cancel() end
		table.clear(self.active); table.clear(self.pending); host:Destroy()
	end
	local layoutElapsed=0
	connect(game:GetService("RunService").Heartbeat,function(dt)
		layoutElapsed+=dt
		if layoutElapsed>=.1 then layoutElapsed=0;controller:Layout() end
	end)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), function() controller:Layout(); pump() end)
	connect(root.Destroying, function() controller:Destroy() end)
	return controller
end

end)()
-- NOTIFICATIONS END

--!nocheck
-- Altair UI, captured in Studio from the current interface on 2026-10-23.
-- Returns a factory: local root = require(UI.Build)().
-- Keeps every authored child, including hidden templates and preview rows.
-- Immutable values/property sets are shared; every call returns fresh Instances.
-- The root stays disabled and unparented until the caller owns and mounts it.

local classes = {"Frame","ImageButton","ImageLabel","ScreenGui","ScrollingFrame","TextBox","TextButton","TextLabel","UIAspectRatioConstraint","UICorner","UIGradient","UIGridLayout","UIListLayout","UIPadding","UIPageLayout","UIStroke"}

-- Shared Roblox values (not Instances).
local v = {
100,Enum.ScreenInsets.DeviceSafeInsets,false,Vector2.new(0.5,1),Color3.new(0.117647059,0.117647059,0.117647059),0.100000001,Color3.new(0.105882362,0.164705887,0.207843155),0,UDim2.new(0.5,0,1,-92),UDim2.new(0,582,0,303),150,UDim.new(0,14),Font.new("rbxassetid://12187365364",Enum.FontWeight.ExtraBold,Enum.FontStyle.Normal),"Character",Color3.new(0.941176474,0.941176474,0.941176474),16,true,Enum.TextXAlignment.Left,Color3.new(1,1,1),1,UDim2.new(0,47,0,11),UDim2.new(0,328,0,21),157,UDim2.new(0,0,0,50),UDim2.new(0,582,0,253),152,Font.new("rbxassetid://12187365364",Enum.FontWeight.Bold,Enum.FontStyle.Normal),"Player Properties",Color3.new(0.678431392,0.678431392,0.698039234),12,UDim2.new(0,399,0,8),UDim2.new(0,169,0,17),"Player Actions",UDim2.new(0,170,0,8),UDim2.new(0,203,0,17),"rbxassetid://4400696294",0.699999988,UDim2.new(1,-25,0,10),UDim2.new(0,15,0,15),Color3.new(0.196078435,0.196078435,0.196078435),UDim2.new(0,275,0,30),UDim2.new(0,98,0,35),Font.new("rbxasset://fonts/families/SourceSansPro.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal),"",Color3.new(0,0,0),11,158,Font.new("rbxassetid://12187365364",Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),"Serverhop",UDim2.new(0,34,0,0),UDim2.new(0,62,0,35),0.910000026,"rbxassetid://92188766517878",UDim2.new(0,10,0,9),UDim2.new(0,16,0,16),UDim2.new(0,170,0,30),"Rejoin","rbxassetid://138133190015277",UDim2.new(0,399,0,30),UDim2.new(0,163,0,203),UDim.new(0,5),Enum.HorizontalAlignment.Center,Enum.SortOrder.LayoutOrder,Color3.new(0.172549024,0.600000024,0.36470589),UDim2.new(0,163,0,36),1.04999995,UDim.new(0,7),UDim2.new(0,0,0,22),UDim2.new(0,68,0,7),154,UDim.new(0,4),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.533333,0.12549,1)),ColorSequenceKeypoint.new(1,Color3.new(0.054902,0.819608,0.92549))}),Vector2.new(0.5,0.5),Color3.new(0.125490203,0.819607854,0.921568632),UDim2.new(1,0,0.5,0),UDim2.new(0,12,0,12),155,UDim.new(0,16),UDim2.new(0.5,0,0.5,0),UDim2.new(0,5,0,5),156,"rbxassetid://8119252523",0.419999987,UDim2.new(0,34,0,34),"Property",UDim2.new(0,112,0,16),"rbxassetid://3602733521",Color3.new(0.0784313753,0.0784313753,0.0784313753),0.600000024,UDim2.new(0.999999642,0,1.00000012,0),149,UDim2.new(0,0,0,16),UDim2.new(0,111,0,19),UDim2.new(0,111,0,7),153,Font.new("rbxasset://fonts/families/GothamSSm.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal),"16",Color3.new(0.917647064,0.941176474,1),UDim2.new(0,121,0,2),UDim2.new(0,41,0,29),UDim2.new(0,170,0,72),UDim2.new(0,203,0,161),UDim2.new(0,7,0,7),5,0.5,UDim.new(0,6),"rbxassetid://9134761478","Action",Color3.new(0.490196079,0.490196079,0.490196079),UDim2.new(0,582,0,2),200,Color3.new(0.549019635,0.549019635,0.580392182),0.349999994,UDim2.new(0,157,0,10),UDim2.new(0,1,0,224),UDim2.new(0,385,0,10),UDim2.new(0,17,0,9),UDim2.new(0,126,0,225),Color3.new(0.168627456,0.188235298,0.235294119),0.119999997,UDim2.new(0,126,0,51),"rbxassetid://9134787693",UDim2.new(0,12,0,13),UDim2.new(0,25,0,25),Color3.new(0.352941185,0.392156869,0.486274511),0.319999993,"Toggle",UDim2.new(0,48,0,10),UDim2.new(0,77,0,16),10,UDim2.new(0,48,0,26),UDim2.new(0,77,0,14),"rbxassetid://91388274398195",Color3.new(0.470588237,0.294117659,0.941176474),0.150000006,Rect.new(10,10,118,118),UDim2.new(1,105,1,105),151,"rbxassetid://9080470458",UDim2.new(0,21,0,21),Enum.ApplyStrokeMode.Border,0.649999976,ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,Color3.new(0.803922,0.803922,0.803922))}),90,"Quick controls for your player",UDim2.new(0,47,0,31),UDim2.new(0,328,0,13),Color3.new(0.0941176489,0.0941176489,0.0941176489),UDim2.new(0.5,-40,1,0),45,UDim2.new(0,11,0,11),UDim2.new(0.5,0,1,-110),UDim2.new(0,580,0,220),UDim.new(0.0199999996,0),Enum.VerticalAlignment.Bottom,UDim2.new(0.5,0,0.959090889,0),UDim2.new(1,0,-0.0636363626,32),"Toast",20,0.300000012,UDim2.new(1,0,0,16),105,UDim2.new(0.5,0,0.325021535,0),UDim2.new(0,391,0,97),UDim.new(0,13),"You've been banned, would you like to leave this game?",15,Enum.TextYAlignment.Top,UDim2.new(0.0629999861,0,0.370000005,0),UDim2.new(0,235,0,52),Vector2.new(1,1),Color3.new(0.392156899,0.392156899,0.392156899),UDim2.new(1,-10,1,-10),UDim2.new(0,88,0,36),UDim.new(1,0),"Removal Detection",14,UDim2.new(0.0632659867,0,0.187546402,0),UDim2.new(0,210,0,17),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.239216,0.490196,0.890196))}),Vector2.new(0,0.649999976),80,UDim2.new(0.5,0,0.499690175,0),UDim2.new(0,580,0,529),Font.new("rbxassetid://12187365364",Enum.FontWeight.Medium,Enum.FontStyle.Normal),Color3.new(0.588235319,0.588235319,0.588235319),"Search for scripts",UDim2.new(0.523000002,0,0.0540000014,0),UDim2.new(0,512,0,16),"rbxassetid://3605509925",Enum.ScaleType.Fit,UDim2.new(0.0537931025,0,0.0560637638,0),Enum.AutomaticSize.Y,UDim2.new(0,0,0,0),2,UDim2.new(0,0,0.0967807025,0),UDim2.new(0,580,0,461),UDim.new(0,8),Color3.new(0.0980392173,0.0980392173,0.0980392173),-100,UDim2.new(0.0425862297,0,0,0),Color3.new(0.392156869,0.392156869,0.392156869),0.800000012,UDim2.new(0.0250000004,0,0,0),UDim2.new(0,555,0,171),"Script Example",UDim2.new(0.0378378369,0,0.267053783,0),UDim2.new(0,259,0,17),Font.new("rbxassetid://12187365364",Enum.FontWeight.Regular,Enum.FontStyle.Normal),"desc",UDim2.new(0.0379999392,0,0.364912242,0),UDim2.new(0,363,0,83),"uploaded by unknown",UDim2.new(0.0378378369,0,0.855087519,0),UDim2.new(0,405,0,13),UDim2.new(0.284369379,0,0.0409356728,0),UDim2.new(0,386,0,30),Enum.FillDirection.Horizontal,Enum.HorizontalAlignment.Right,Enum.VerticalAlignment.Center,Color3.new(0,0.552941203,0.82745105),UDim2.new(0.268588066,0,0,0),UDim2.new(0,140,1,0),"Verified Creator",UDim2.new(0.800000012,0,0,15),3,UDim2.new(0.499999642,0,0.5,0),Color3.new(0,0.545098066,0.400000006),UDim2.new(0.666662991,0,0,0),UDim2.new(0,145,1,0),"Positive Reviews",Color3.new(0.690196097,0.152941182,0.152941182),UDim2.new(0,83,1,0),"Patched","Run",UDim2.new(0.912351847,0,0.845373333,0),UDim2.new(0,74,0,36),"No Scripts Found",UDim2.new(0.5,0,0.482986778,0),UDim2.new(0,195,0,17),"Try searching with a different query",UDim2.new(0.5,0,0.515109658,0),UDim2.new(0,355,0,15),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.239216,0.454902,0.776471))}),Vector2.new(0,0.600000024),UDim2.new(0,310,0,315),"Import Script",UDim2.new(0.0596665889,0,0.0683826283,0),UDim2.new(0,197,0,17),"rbxassetid://3926305904",Vector2.new(924,724),Vector2.new(36,36),Vector2.new(1,0),UDim2.new(1,-15,0,15),UDim2.new(0,18,0,18),"Import your own script and loadstring for Sirius to use.",Color3.new(0.784313738,0.784313738,0.784313738),UDim2.new(0.0596666671,0,0.123177171,0),UDim2.new(0,232,0,29),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.266667,0.529412,0.705882))}),Vector2.new(0,-0.400000006),-80,UDim2.new(0.0570151061,0,0.304418743,0),UDim2.new(0,232,0,30),Color3.new(0.699999988,0.699999988,0.699999988),"PlaceId",13,UDim2.new(0.0488160215,0,0,0),UDim2.new(0,205,0,30),UDim.new(0,9),UDim2.new(0.0570151061,0,0.41870448,0),UDim2.new(0,232,0,67),"Description",UDim2.new(0.0488160215,0,0.127073377,0),UDim2.new(0,209,0,55),UDim2.new(0.0570151061,0,0.650450468,0),"Raw Code Link","Submit",0.0500000007,UDim2.new(0.675346494,0,0.864385486,0),UDim2.new(0,90,0,33),UDim2.new(0,613,0,384),"Detections",UDim2.new(0.0909999982,0,0.057,0),UDim2.new(0,239,0,20),205,UDim2.new(0,0,0.223958418,0),UDim2.new(0,613,0,287),UDim2.new(0,10,0,10),UDim2.new(0,180,0,100),UDim2.new(0,100,0,100),UDim.new(0,12),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.117647,0.117647,0.117647)),ColorSequenceKeypoint.new(1,Color3.new(0,0.494118,0.72549))}),Vector2.new(0,0.400000006),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0392157,0.0392157,0.0392157)),ColorSequenceKeypoint.new(1,Color3.new(0,0.494118,0.72549))}),"GENERAL",0.200000003,Enum.TextXAlignment.Right,UDim2.new(0.183333337,0,0.74000001,0),UDim2.new(0,133,0,17),210,"rbxassetid://3523728077",UDim2.new(0.50036484,0,0.489581287,0),UDim2.new(0,205,0,179),207,UDim2.new(1,0,1,0),215,"The basic and essential settings that you can quickly modify to tweak your experience",UDim2.new(0.0450000353,0,0.111999989,0),UDim2.new(0,282,0,30),Vector2.new(564,244),UDim2.new(0.0410000011,0,0.0520000011,0),UDim2.new(0,0,0.224000007,0),Enum.EasingStyle.Exponential,Enum.FillDirection.Vertical,0.899999976,UDim2.new(0.0473083183,0,0,0),UDim2.new(0,558,0,40),"Switch",UDim2.new(0,18,0,12),UDim2.new(0,333,0,16),Vector2.new(1,0.5),Color3.new(0.196078449,0.196078449,0.196078449),UDim2.new(1,-12,0.5,0),UDim2.new(0,43,0,21),UDim.new(0,15),Vector2.new(0,0.5),Color3.new(0.921568632,0.921568632,0.921568632),0.75,UDim2.new(1,-40,0.5,0),UDim2.new(0,17,0,17),1.20000005,UDim2.new(0.815322578,0,0.5,0),UDim2.new(0.369354695,0,1,0),"Button",UDim2.new(0,18,0,30),UDim2.new(0,333,0,57),"PRO FEATURE",UDim2.new(0,18,0,13),UDim2.new(0,333,0,12),Color3.new(0.137254909,0.137254909,0.137254909),"Input",UDim2.new(1,-7,0,20),UDim2.new(0,120,0,30),Color3.new(0.764705956,0.764705956,0.764705956),"Dynamic Input",Color3.new(0.490196109,0.490196109,0.490196109),UDim2.new(0.026442308,0,-0.013325341,0),UDim2.new(0,0,0.204999968,0),UDim2.new(0,405,0,143),UDim2.new(0.392473131,0,0,0),UDim2.new(0.970000029,0,0,38),Color3.new(0.215686277,0.215686277,0.215686277),"Option",UDim2.new(0.408736676,0,0.5,0),UDim2.new(0,297,0,14),"Dropdown Option 1",Vector2.new(0.5,0),UDim2.new(0,443,0,12),UDim2.new(0,151,0,16),Vector2.new(564,284),9,UDim2.new(0,535,0,20),UDim2.new(0,32,0,28),UDim2.new(0,203,0,21),UDim2.new(0,406,0,43),"Dropdown",UDim2.new(0.044861339,0,0.501742184,0),"tap to interact",UDim2.new(1,-20,0.5,0),UDim2.new(0,139,0,15),UDim2.new(0,18,0,43),1000,ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0588235,0.0588235,0.0588235)),ColorSequenceKeypoint.new(1,Color3.new(0.705882,0,0))}),UDim2.new(0.5,0,0.300000012,0),UDim2.new(0,641,0,45),UDim.new(0,11),UDim2.new(0.334716022,0,0.499999672,0),UDim2.new(0.608632267,0,0.431177437,0),"tap <b>Enter</b>",UDim2.new(0.899999976,0,0.5,0),UDim2.new(0.134144336,0,0.379494786,0),6,"start typing",UDim2.new(0.334716022,0,0.50000006,0),UDim2.new(0.608610988,0,0.431247383,0),UDim2.new(0.5,0,0,55),UDim2.new(1,0,0,50),"Aimbot",UDim2.new(0,20,0.5,0),UDim2.new(0,552,0,15),Color3.new(0.254901975,0.254901975,0.254901975),UDim2.new(1,2,1,2),Color3.new(0.168627456,0.411764711,0.623529434),UDim2.new(0.800000012,0,0.5,0),UDim2.new(0,222,0,30),Color3.new(0.188235298,0.466666669,0.694117665),UDim2.new(0.800968468,0,1,0),Color3.new(0.24313727,0.619607866,0.905882418),"750 studs",0.400000006,UDim2.new(0.453598171,0,0.5,0),UDim2.new(0,168,0,15),"Slider",UDim2.new(0,371,0,15),UDim2.new(1,-15,0,14),UDim2.new(0,468,0,15),UDim2.new(0,34,0,30),"Keybind","Q","button",UDim2.new(0.883000016,0,0.5,0),UDim2.new(0,108,0,15),Color3.new(0.129411772,0.129411772,0.129411772),0.819999993,UDim2.new(1.11060238,0,1.92164946,0),UDim2.new(1,-28,1,-28),UDim2.new(0.5,0,0,20),UDim2.new(0,350,0,60),"Unknown Status",UDim2.new(0.5,0,0,0),UDim2.new(0.5,0,0,22),UDim2.new(1,0,0,2),UDim2.new(0.5,0,0,200),UDim2.new(0,473,0,154),"rbxassetid://9319332188",Enum.ScaleType.Crop,UDim2.new(0,70,0,32),0.850000024,"The most popular FPS shooter from the development team at ROLVe. Execute the script to get an unfair advantage.",Color3.new(0.941176534,0.941176534,0.941176534),UDim2.new(0,23,0.561999977,0),UDim2.new(0,274,0,44),"Arsenal",UDim2.new(0,23,0.351999998,0),UDim2.new(0,274,0,21),UDim2.new(0.000999987125,0,1.05466092,0),UDim2.new(0,459,0,91),"This game was updated after our most recent patch. The script may be detected or not work correctly.",UDim2.new(0.0468213484,0,0.427032977,0),UDim2.new(0,366,0,29),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.784314,0.172549,0.172549))}),Vector2.new(0,-1),250,"Possible Detection",UDim2.new(0.0469280556,0,0.24620676,0),UDim2.new(0,365,0,17),Color3.new(0.0941176564,0.0941176564,0.0941176564),UDim2.new(0.933217704,70,1.26182342,60),UDim2.new(1.10434783,0,1.71428573,0),UDim2.new(0.5,0,0,80),UDim2.new(0,576,0,181),"Text",UDim2.new(0.5,0,0.5,6),UDim2.new(0,524,0,32),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.764706,0.305882,0.0941176))}),UDim2.new(0.0428699926,0,0.100063853,0),UDim2.new(0,389,0,17),UDim2.new(0.0430000015,0,0.200000003,0),UDim2.new(0,389,0,28),UDim2.new(0.254999995,0,0.75,0),UDim2.new(0,415,0,36),UDim2.new(0.177156672,0,0,0),UDim2.new(0,341,0,36),UDim2.new(0.5,0,1,-12),UDim2.new(0,300,0,60),UDim.new(0,40),UDim2.new(0.601999998,0,0.910000026,0),UDim2.new(0,210,0,50),UDim.new(0,20),1.5,160,UDim2.new(0.324999988,0,0.5,0),"rbxassetid://9080449299",Rect.new(0.5,0,0.5,0),UDim2.new(0,24,0,24),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.462745,0.321569,0.639216)),ColorSequenceKeypoint.new(1,Color3.new(0.388235,0.47451,0.713726))}),50,ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.380392,0.262745,0.521569)),ColorSequenceKeypoint.new(1,Color3.new(0.317647,0.388235,0.584314))}),UDim2.new(0.409999996,0,0.5,0),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.180392,0.192157,0.572549)),ColorSequenceKeypoint.new(1,Color3.new(0.0627451,0.603922,0.603922))}),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.235294,0.25098,0.745098)),ColorSequenceKeypoint.new(1,Color3.new(0.0745098,0.741176,0.741176))}),UDim2.new(0.498333335,0,0.5,0),"rbxassetid://9080478424",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.764706,0.0588235,0.270588)),ColorSequenceKeypoint.new(1,Color3.new(0.776471,0.529412,0.184314))}),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.619608,0.0588235,0.266667)),ColorSequenceKeypoint.new(1,Color3.new(0.705882,0.490196,0.164706))}),4,UDim2.new(0.584444463,0,0.5,0),"rbxassetid://9080475789",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0470588,0.701961,0.45098)),ColorSequenceKeypoint.new(1,Color3.new(0.172549,0.380392,0.145098))}),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0431373,0.65098,0.419608)),ColorSequenceKeypoint.new(1,Color3.new(0.129412,0.298039,0.113725))}),UDim2.new(0.670000017,0,0.5,0),"rbxassetid://3605022185",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.282353,0.301961,0.317647)),ColorSequenceKeypoint.new(1,Color3.new(0.14902,0.164706,0.168627))}),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.317647,0.341176,0.356863)),ColorSequenceKeypoint.new(1,Color3.new(0.172549,0.192157,0.196078))}),1000000,UDim2.new(0.639498413,0,0.5,0),UDim2.new(0.0125391847,0,0,0),-10,UDim2.new(0,0,0.5,0),Font.new("rbxasset://fonts/families/GothamSSm.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal),"12:31",UDim2.new(-0.190476194,0,0.433000028,0),UDim2.new(0,67,0,19),Font.new("rbxasset://fonts/families/GothamSSm.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal),"PM",UDim2.new(0.25,0,0.899999976,0),UDim2.new(0,34,0,11),UDim2.new(0.49888888,0,0.153588861,0),UDim2.new(0.935555577,70,0.692822278,60),"rbxassetid://111379846641013",UDim2.new(1.159464,40,1.96641541,70),Color3.new(0.0588235334,0.0588235334,0.0588235334),UDim2.new(0.5,0,0.200000003,0),UDim2.new(0,300,0,220),"An administrator for this game has joined your session.",UDim2.new(0.166000158,0,0.642585635,0),UDim2.new(0,200,0,30),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0,0,0)),ColorSequenceKeypoint.new(1,Color3.new(0.705882,0,0))}),"Moderator Detection",UDim2.new(0.166000158,0,0.0427272432,0),UDim2.new(0,200,0,16),"rbxassetid://9333366626",UDim2.new(0.427250177,0,0.250706077,0),UDim2.new(0,42,0,42),"Eline",UDim2.new(0.166000158,0,0.458543539,0),UDim2.new(0.648333311,0,0.332727343,0),UDim2.new(0,110,0,36),"Servers Available",UDim2.new(0.680333257,0,0.173568934,0),UDim2.new(0,92,0,28),"[A] Administrator",UDim2.new(0.166000158,0,0.532659829,0),UDim2.new(0,200,0,14),UDim2.new(1.01999998,-15,-0.0272727273,15),UDim2.new(0.166000158,0,0.809090912,0),"Leave",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,0.262745,0.27451)),ColorSequenceKeypoint.new(1,Color3.new(0.54902,0.54902,0.54902))}),-90,NumberSequence.new({NumberSequenceKeypoint.new(0,0.7,0),NumberSequenceKeypoint.new(1,0.7,0)}),Color3.new(1,0.262745112,0.274509817),UDim2.new(0.5,0,1.08608997,0),UDim2.new(1.10000002,70,1.00963831,60),99,Color3.new(0.121568628,0.121568628,0.121568628),UDim2.new(0,0,0.170000002,0),UDim2.new(1,0,0,1),UDim2.new(0.496125072,0,0.0821039379,0),UDim2.new(0,200,0,36),Color3.new(0.121568635,0.121568635,0.121568635),UDim2.new(0,581,0,303),"Players",Color3.new(0.960784316,0.960784316,0.972549021),18,UDim2.new(0,47,0,10),UDim2.new(0,330,0,22),UDim2.new(0,343,0,92),UDim2.new(0,226,0,197),0.0799999982,UDim2.new(0,221,0,34),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.482353,0.278431,1)),ColorSequenceKeypoint.new(0.45,Color3.new(0.121569,0.2,0.356863)),ColorSequenceKeypoint.new(1,Color3.new(0.54902,0.670588,1))}),"In Server",Color3.new(0.725490212,0.772549033,0.850980401),UDim2.new(0,63,0,18),UDim2.new(0,150,0,13),"rbxassetid://4370336704",UDim2.new(0.155000001,0,0.400000006,0),UDim2.new(0,22,0,22),"No Actions Available",UDim2.new(1,-30,0.5,0),UDim2.new(0,132,0,13),"vayeco",Color3.new(0.937254906,0.949019611,0.97647059),UDim2.new(0,63,0,3),UDim2.new(0,150,0,14),UDim2.new(0,180,0,40),UDim2.new(0,38,0,38),159,"rbxassetid://3944668821",Color3.new(0.235294119,0.235294119,0.235294119),UDim2.new(0.388888896,0,0.0250000004,0),"rbxassetid://4335479121",UDim2.new(0.788888872,0,0.0250000004,0),"rbxassetid://9134770786",UDim2.new(0.411111116,0,0.0250000004,0),"rbxassetid://9134780101","rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150",UDim2.new(0,7,0,3),UDim2.new(0,28,0,28),UDim.new(0,100),Color3.new(0.313725501,0.313725501,0.313725501),UDim2.new(0.0709980428,0,0.498167306,0),UDim2.new(0.640771389,70,3.35655832,60),Color3.new(0.188235298,0.858823538,0.454901963),UDim2.new(0,46,0,20),UDim2.new(0,9,0,9),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.211765,0.121569,0.435294)),ColorSequenceKeypoint.new(0.45,Color3.new(0.121569,0.2,0.356863)),ColorSequenceKeypoint.new(1,Color3.new(0.109804,0.133333,0.2))}),UDim2.new(0,343,0,57),UDim2.new(0,226,0,28),"Search players...",UDim2.new(0,31,0,0),UDim2.new(0,189,0,28),"rbxassetid://10734943674",UDim2.new(0,7,0,4),UDim2.new(0,19,0,19),"Teams",UDim2.new(0.180000007,0,0.189999998,0),UDim2.new(0,180,0,17),"24 players in your session",UDim2.new(0.5,0,0.970000029,0),UDim2.new(0,541,0,17),0.0399999991,UDim2.new(0,12,0,57),UDim2.new(0,172,0,232),Color3.new(0.921568632,0.921568632,0.941176474),UDim2.new(0,45,0,14),UDim2.new(0,82,0,82),"Noclip",Color3.new(0.945098042,0.949019611,0.968627453),UDim2.new(0,10,0,107),UDim2.new(0,152,0,21),"@Noclip",Color3.new(0.678431392,0.737254918,0.835294127),UDim2.new(0,10,0,131),UDim2.new(0,152,0,15),UDim2.new(0,17,0,153),UDim2.new(0,138,0,20),Color3.new(0.615686297,0.412549019,0.934117675),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.45098,0.160784,0.905882)),ColorSequenceKeypoint.new(1,Color3.new(0.0431373,0.454902,0.682353))}),"Friend",UDim2.new(0,95,0,20),"rbxassetid://10747373426",UDim2.new(0,8,0,1),UDim2.new(0,17,0,177),Color3.new(0.368627459,0.832549036,0.626666665),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0980392,0.760784,0.466667)),ColorSequenceKeypoint.new(1,Color3.new(0.0588235,0.419608,0.356863))}),"In  Server",UDim2.new(0,9,0,4),UDim2.new(0,13,0,13),UDim2.new(0,17,0,201),Color3.new(0.461960793,0.483921587,0.549803913),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.231373,0.262745,0.356863)),ColorSequenceKeypoint.new(1,Color3.new(0.12549,0.141176,0.231373))}),"Premium","rbxassetid://10734966248",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.517647,0.145098,0.933333)),ColorSequenceKeypoint.new(1,Color3.new(0,0.721569,0.980392))}),Color3.new(0.188235298,0.898039222,0.388235301),UDim2.new(0,112,0,80),UDim2.new(0,100,0,68),UDim2.new(0,37,0,37),UDim2.new(0,197,0,57),UDim2.new(0,133,0,232),Color3.new(0.650980413,0.725490212,0.843137264),UDim2.new(0,133,0,19),0.0299999993,UDim2.new(0,0,0,30),UDim2.new(0,133,0,40),"rbxassetid://10723346959",UDim2.new(0,10,0,7),"Spectate",Color3.new(0.933333337,0.945098042,0.97647059),UDim2.new(0,43,0,0),UDim2.new(0,87,0,40),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.215686,0.215686,0.215686)),ColorSequenceKeypoint.new(1,Color3.new(0.137255,0.137255,0.137255))}),UDim2.new(0,0,0,78),"rbxassetid://10734943902","Goto",UDim2.new(0,0,0,126),"Track",UDim2.new(0,0,0,174),"rbxassetid://10709811834","View Profile",UDim2.new(0,17,0,12),UDim2.new(0,23,0,23),UDim2.new(0.500002086,0,0.5,0),UDim2.new(2.5,0,2.5,0),Color3.new(0.56078434,0.596078455,0.662745118),0.620000005,Color3.new(0.490196079,0.490196079,0.53725493),UDim2.new(0,12,0,49),UDim2.new(0,557,0,1),UDim2.new(0,336,0,57),UDim2.new(0,1,0,232),"Browse and interact with players in this server",Color3.new(0.662745118,0.709803939,0.80392158),UDim2.new(0,47,0,32),UDim2.new(0,380,0,14),UDim2.new(0.5,38,1,0),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.803922,0.803922,0.803922)),ColorSequenceKeypoint.new(1,Color3.new(0.803922,0.803922,0.803922))}),UDim2.new(1,-20,1,-20),UDim2.new(0,300,0,800),0.449999988,UDim2.new(-0.519999981,0,0.653750002,0),UDim2.new(1,0,0,170),"rbxassetid://77891951053543",Color3.new(0.819607913,0.819607913,0.819607913),UDim2.new(0,25,0.5,0),UDim2.new(0.5,0,0.600000024,0),UDim2.new(0.100000001,60,0.100000001,60),"If you're seeing this, this script may not be on the latest Rayfield version. The developer needs to use the sirius.menu/rayfield loadstring to use the latest features and fixes. \n\nVisit sirius.menu/discord for help.",UDim2.new(1,-80,1,-40),"Notification Error",UDim2.new(0,70,0,15),UDim2.new(1,-80,0,16),UDim2.new(1,-18,1,-18),UDim2.new(0.5,0,1,0),UDim2.new(0.935555577,70,0.949999988,60),UDim2.new(0.5,-520,0.5,-270),UDim2.new(0,1040,0,38),UDim.new(0.0700000003,0),Color3.new(0.745098054,0.745098054,0.768627465),1.39999998,Color3.new(0.254901975,0.254901975,0.274509817),UDim2.new(0,92,0,32),25,UDim.new(0.25,0),"rbxassetid://7733960981",Color3.new(0.749019623,0.784313738,0.827450991),UDim2.new(0,10,0,8),23,"Home",Color3.new(0.917647064,0.917647064,0.933333337),UDim2.new(0,33,0,0),UDim2.new(0,59,0,32),UDim2.new(0,100,0,0),"rbxassetid://7743876054","Friends",UDim2.new(0,200,0,0),"rbxassetid://7733734848","Recent",UDim2.new(0,240,0,150),22,"rbxthumb://type=AvatarHeadShot&id=263152704&w=150&h=150",UDim2.new(0,16,0,18),UDim2.new(0,62,0,62),UDim.new(0.5,0),"Skyss",UDim2.new(0,91,0,22),UDim2.new(0,130,0,25),"@notskyss_",UDim2.new(0,91,0,51),UDim2.new(0,130,0,20),Color3.new(0.639215708,0.639215708,0.670588255),0.519999981,ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.14902,0.14902,0.160784)),ColorSequenceKeypoint.new(1,Color3.new(0.0862745,0.0862745,0.0941176))}),65,"â  In Game",Color3.new(0.254901975,0.87843138,0.529411793),UDim2.new(0,91,0,77),"FRIENDS             ACCOUNT",Color3.new(0.592156887,0.592156887,0.635294139),UDim2.new(0,16,0,100),UDim2.new(0,212,0,14),"42                       Roblox",UDim2.new(0,16,0,117),UDim2.new(0,212,0,17),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0588235,0.0588235,0.0588235)),ColorSequenceKeypoint.new(1,Color3.new(0.196078,0.196078,0.196078))}),UDim2.new(0,1040,0,440),UDim2.new(0,254,0,0),UDim2.new(0,492,0,440),"rbxassetid://116444221868620",UDim2.new(0,14,0,14),UDim2.new(0,464,0,192),Color3.new(0.0313725509,0.0313725509,0.0392156877),UDim.new(0.0450000018,0),NumberSequence.new({NumberSequenceKeypoint.new(0,0.4,0),NumberSequenceKeypoint.new(0.5,0.8,0),NumberSequenceKeypoint.new(1,0.04,0)}),"rbxthumb://type=GameIcon&id=1176784616&w=150&h=150",UDim2.new(0,16,0,221),UDim.new(0,10),"Now Playing",UDim2.new(0.23918575,0,0.0837438405,0),UDim2.new(0.508905828,0,0.049261082,0),"Tower Defense Simulator",UDim2.new(0,91,0,222),UDim2.new(0,384,0,28),"By Paradoxum Games",UDim2.new(0,91,0,251),UDim2.new(0,384,0,20),UDim2.new(0,16,0,310),UDim2.new(0,459,0,34),"3 friends playing",UDim2.new(0,95,0,4),UDim2.new(0,230,0,19),"rbxassetid://7733717755",UDim2.new(0,438,0,6),Enum.AutomaticSize.X,Color3.new(0.717647076,0.788235307,0.874509811),Enum.ScrollingDirection.X,UDim2.new(0,86,0,29),UDim.new(0,3),UDim.new(0,2),"rbxthumb://type=AvatarHeadShot&id=156&w=150&h=150",UDim2.new(0,459,0,29),"â In Game        12 / 30 Players        94 ms",Color3.new(0.266666681,0.858823538,0.568627477),UDim2.new(0,91,0,278),UDim2.new(0,384,0,22),Color3.new(0.666666687,0.666666687,0.694117665),UDim2.new(0,14,0,302),UDim2.new(0,464,0,2),UDim2.new(0,14,0,343),UDim2.new(0.67964071,0,0.170912951,0),UDim2.new(0.271856278,0,0.109341823,0),"10:43 PM",Color3.new(0.980392158,0.984313726,1),UDim2.new(0.0594713651,0,0.242718443,0),UDim2.new(0.528634369,0,0.281553388,0),"Wed, Aug 26, 2026",UDim2.new(0.0594713651,0,0.601941764,0),UDim2.new(0.612334788,0,0.194174752,0),"In Game â",Color3.new(0.356862754,0.90196079,0.53725493),UDim2.new(0.680616736,0,0.281553388,0),UDim2.new(0.277533054,0,0.184466019,0),"Roblox",UDim2.new(0.744493365,0,0.563106775,0),UDim2.new(0.198237881,0,0.194174752,0),UDim2.new(0,760,0,0),UDim2.new(0,280,0,198),UDim2.new(0,17,0,18),"Server Info",UDim2.new(0,45,0,15),UDim2.new(0,180,0,25),"15 / 30",UDim2.new(0.762114525,0,0.120567374,0),UDim2.new(0.198237881,0,0.0815602839,0),UDim2.new(0,17,0,53),UDim2.new(0,246,0,41),UDim2.new(0,0,0,40),UDim2.new(0,246,0,1),"rbxassetid://7733954760",UDim2.new(0.0125000002,0,0.223880604,0),UDim2.new(0.0724999979,0,0.432835817,0),"Server Region",UDim2.new(0,0,0,7),UDim2.new(0,125,0,22),"Unknown",UDim2.new(0,128,0,7),UDim2.new(0,118,0,22),UDim2.new(0,17,0,139),"rbxassetid://8997387546","Latency","94 ms",UDim2.new(0,17,0,96),"Server Age","1h 24m",UDim2.new(0,0,0,162),UDim2.new(0,240,0,278),UDim2.new(0,16,0,14),UDim2.new(0,165,0,24),UDim2.new(0,206,0,18),0.550000012,Enum.ScrollingDirection.Y,UDim2.new(0,12,0,48),UDim2.new(0,216,0,217),UDim2.new(0,212,0,61),Color3.new(0.337254912,0.36470589,0.407843143),UDim2.new(0,2,0,5),UDim2.new(0,46,0,46),UDim2.new(0,60,0,4),UDim2.new(0,138,0,19),Color3.new(0.286274523,0.874509811,0.478431374),UDim2.new(0,39,0,42),"In Game",UDim2.new(0,60,0,25),UDim2.new(0,138,0,17),Color3.new(0.600000024,0.600000024,0.647058845),UDim2.new(0,60,0,44),UDim2.new(0,147,0,15),"reylix",Color3.new(0.333333343,0.788235307,0.929411769),"m1zu","Online","Available to play","kairo",Color3.new(0.529411793,0.529411793,0.568627477),"Offline","Last seen recently",UDim2.new(0,270,0,349),UDim2.new(0,460,0,78),Color3.new(0.654901981,0.654901981,0.694117665),"Recently Played",UDim2.new(0,350,0,17),UDim2.new(0,440,0,0),UDim2.new(0,0,0,24),UDim2.new(0,460,0,54),UDim2.new(0,145,0,50),"rbxasset://textures/loading/robloxTilt.png",Color3.new(0.0941176489,0.113725491,0.141176477),UDim2.new(0,0,0,1),UDim2.new(0,43,0,43),UDim.new(0.129999995,0),"Game",Enum.TextTruncate.AtEnd,UDim2.new(0,51,0,2),UDim2.new(0,92,0,22),"Yesterday",UDim2.new(0,51,0,25),UDim2.new(0,92,0,17),"Tower Defense","rbxthumb://type=GameIcon&id=994732206&w=150&h=150","Blox Fruits","rbxthumb://type=GameIcon&id=5039447380&w=150&h=150","Gunfight Arena",ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(1,Color3.new(0.72549,0.72549,0.745098))}),UDim2.new(0,760,0,212),UDim2.new(0,280,0,228),"Recent Activity",UDim2.new(0,17,0,15),UDim2.new(0,245,0,24),UDim2.new(0,14,0,50),UDim2.new(0,252,0,165),UDim2.new(0,248,0,47),Color3.new(0.235294119,0.188235298,0.345098048),"Activity",UDim2.new(0,49,0,1),UDim2.new(0,190,0,19),"Session activity",UDim2.new(0,49,0,23),UDim2.new(0,190,0,17),"Joined experience","Tower Defense Simulator Â· Now","Friend came online","reylix Â· 9m ago","Previous session","Blox Fruits Â· Yesterday",Color3.new(0.937254906,0.937254906,0.949019611),UDim2.new(0,18,0,17),UDim2.new(0,220,0,27),24,"People you play with",Color3.new(0.650980413,0.650980413,0.686274529),UDim2.new(0,18,0,48),UDim2.new(0,456,0,18),"Search friends...",Color3.new(0.184313729,0.184313729,0.200000003),UDim2.new(0,276,0,17),UDim2.new(0,198,0,30),UDim.new(0,18),UDim2.new(0,18,0,78),UDim2.new(0,456,0,30),Color3.new(0.274509817,0.274509817,0.305882365),UDim2.new(0,106,0,30),"All",26,Color3.new(0.196078435,0.196078435,0.215686277),UDim2.new(0,114,0,0),UDim2.new(0,228,0,0),UDim2.new(0,342,0,0),Color3.new(0.592156887,0.592156887,0.627451003),UDim2.new(0,16,0,121),UDim2.new(0,460,0,303),0.180000007,UDim2.new(1,-8,0,64),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.184314,0.184314,0.203922)),ColorSequenceKeypoint.new(1,Color3.new(0.133333,0.133333,0.14902))}),NumberSequence.new({NumberSequenceKeypoint.new(0,0.22,0),NumberSequenceKeypoint.new(1,0.22,0)}),0.860000014,Color3.new(0.282352954,0.345098048,0.411764711),UDim2.new(0,10,0,12),UDim2.new(0,40,0,40),Color3.new(0.262745112,0.874509811,0.505882382),UDim2.new(0,40,0,42),"DisplayName",UDim2.new(0,61,0,13),UDim2.new(0,115,0,19),"@username",UDim2.new(0,61,0,34),UDim2.new(0,115,0,17),UDim2.new(0,184,0,18),Color3.new(0.243137255,0.854901969,0.494117647),UDim2.new(0,221,0,13),UDim2.new(0,124,0,19),UDim2.new(0,124,0,17),UDim2.new(0,349,0,64),Color3.new(0.145098045,0.301960796,0.23137255),UDim2.new(0,56,0,30),"Join",Color3.new(0.513725519,0.949019611,0.68235296),UDim2.new(0,412,0,17),UDim2.new(0,29,0,30),"â¢â¢â¢",Color3.new(0.545098066,0.635294139,0.68235296),0.25,"@reylix","@m1zu","View","@kairo","rbxthumb://type=AvatarHeadShot&id=2&w=150&h=150","Pixley","@Pixley","rbxthumb://type=AvatarHeadShot&id=3&w=150&h=150","Captide","@Captide","rbxthumb://type=AvatarHeadShot&id=4&w=150&h=150","shlexr","@shlexr",UDim2.new(0,18,0,121),UDim2.new(0,456,0,303),"Loading...",UDim2.new(0,12,0,110),UDim2.new(0,432,0,54),"Nothing here yet.","Unable to load. Try again.",UDim2.new(0,280,0,440),UDim2.new(0,96,0,19),UDim2.new(0,88,0,88),UDim.new(0,88),UDim2.new(0,18,0,118),UDim2.new(0,244,0,25),UDim2.new(0,18,0,145),UDim2.new(0,244,0,19),UDim2.new(0,16,0,182),UDim2.new(0,248,0,91),"Playing",UDim2.new(0,62,0,10),UDim2.new(0,174,0,17),UDim2.new(0,62,0,29),UDim2.new(0,174,0,22),UDim2.new(0,10,0,61),UDim2.new(0,228,0,23),"About",UDim2.new(0,18,0,290),UDim2.new(0,244,0,20),"Good games, better friends.",UDim2.new(0,18,0,316),UDim2.new(0,244,0,35),"In game Â· Join available",UDim2.new(0,18,0,357),UDim2.new(0,16,0,392),UDim2.new(0,157,0,32),UDim2.new(0,181,0,392),UDim2.new(0,83,0,32),"More","Friends playing","Games","Your favorites and recent adventures","Search games...","Favorites",UDim2.new(1,-8,0,88),UDim2.new(0,11,0,13),"Game title",UDim2.new(0,87,0,12),UDim2.new(0,270,0,22),"By creator",UDim2.new(0,87,0,36),UDim2.new(0,270,0,18),"Last played unavailable",UDim2.new(0,87,0,59),UDim2.new(0,263,0,17),UDim2.new(0,361,0,88),UDim2.new(0,367,0,12),UDim2.new(0,72,0,31),"Play",UDim2.new(0,403,0,51),UDim2.new(0,36,0,26),"â","Paradoxum Games","Played today","Gamer Robot Inc","Played yesterday","Gunfight Studio","Played 2 days ago","Saved to favorites",UDim2.new(0,252,0,141),19,UDim2.new(0,18,0,170),UDim2.new(0,244,0,46),UDim2.new(0,18,0,220),"About this experience",UDim2.new(0,18,0,267),"Team up with friends, build your defenses, and take on waves of enemies.",UDim2.new(0,18,0,295),UDim2.new(0,244,0,65),UDim2.new(0,16,0,373),UDim2.new(0,157,0,42),UDim2.new(0,181,0,373),UDim2.new(0,83,0,42),"Favorite",Color3.new(0.392156869,0.392156869,0.427450985),UDim2.new(0,18,0,253),UDim2.new(0,244,0,1),"Continue playing",UDim2.new(0,185,0,22),UDim2.new(0,208,0,18),UDim2.new(0,12,0,50),UDim2.new(0,216,0,210),UDim2.new(1,-6,0,60),UDim2.new(0,4,0,6),UDim2.new(0,48,0,48),UDim2.new(0,63,0,12),UDim2.new(0,137,0,20),UDim2.new(0,63,0,34),UDim2.new(0,137,0,16),UDim2.new(0,208,0,60),UDim2.new(0,581,0,234),Color3.new(0.607843161,0.635294139,0.698039234),UDim2.new(0,16,0,10),101,"Scripting",Color3.new(0.937254906,0.941176474,0.956862748),UDim2.new(0,50,0,10),UDim2.new(0,380,0,26),102,UDim2.new(0,10,0,44),UDim2.new(0,244,0,100),103,ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.121569,0.188235,0.305882)),ColorSequenceKeypoint.new(1,Color3.new(0.113725,0.133333,0.172549))}),Color3.new(0.443137258,0.650980413,1),UDim2.new(0,11,0,14),104,Color3.new(0.666666687,0.827450991,1),UDim2.new(0,17,0,20),UDim2.new(0,35,0,35),"ScriptSearch",UDim2.new(0,70,0,17),UDim2.new(0,152,0,23),"Instant access to a catalogue\nof community scripts",Color3.new(0.772549033,0.788235307,0.835294127),UDim2.new(0,70,0,43),UDim2.new(0,157,0,49),"âº",UDim2.new(0,225,0,39),UDim2.new(0,12,0,23),107,UDim2.new(0,262,0,44),UDim2.new(0,309,0,100),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.309804,0.223529,0.0980392)),ColorSequenceKeypoint.new(1,Color3.new(0.141176,0.137255,0.121569))}),Color3.new(1,0.760784328,0.290196091),"rbxassetid://10723367380",Color3.new(1,0.772549033,0.31764707),"Script Found",UDim2.new(0,217,0,23),"Tap to reprompt the\ngame detection",UDim2.new(0,222,0,49),UDim2.new(0,290,0,39),UDim2.new(0,10,0,152),UDim2.new(0,207,0,72),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.388235,0.145098,0.176471)),ColorSequenceKeypoint.new(1,Color3.new(0.164706,0.121569,0.137255))}),Color3.new(0.980392158,0.388235301,0.43921569),"rbxassetid://10723404337",Color3.new(1,0.43921569,0.490196079),UDim2.new(0,32,0,32),"Universal Scripts",UDim2.new(0,63,0,25),UDim2.new(0,131,0,24),UDim2.new(0,63,0,37),UDim2.new(0,130,0,31),UDim2.new(0,188,0,25),UDim2.new(0,225,0,152),UDim2.new(0,201,0,72),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0705882,0.301961,0.247059)),ColorSequenceKeypoint.new(1,Color3.new(0.0980392,0.164706,0.164706))}),Color3.new(0.349019617,0.898039222,0.698039234),"rbxassetid://10734924532",Color3.new(0.666666687,1,0.870588243),"Custom Scripts",UDim2.new(0,63,0,14),UDim2.new(0,122,0,23),"Add your own scripts\nto Altair",UDim2.new(0,124,0,31),UDim2.new(0,182,0,25),UDim2.new(0,434,0,152),UDim2.new(0,137,0,72),ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(0.0627451,0.25098,0.290196)),ColorSequenceKeypoint.new(1,Color3.new(0.0862745,0.160784,0.184314))}),Color3.new(0.152941182,0.882352948,0.937254906),"rbxassetid://10709782497",Color3.new(0.270588249,0.894117653,0.964705884),"V4",UDim2.new(0,58,0,23),"Vape V4",UDim2.new(0,60,0,31),UDim2.new(0,118,0,25),UDim2.new(0.5,0,0.5,20),UDim2.new(1,-30,1,-55),Color3.new(0.149019614,0.149019614,0.149019614),UDim2.new(1,0,0.0942408368,40),"Template",UDim2.new(0,15,0.379000008,0),UDim2.new(0,310,0,16),UDim2.new(1,-6,1,-6),"Short Description, very brief",UDim2.new(0,15,0.653999984,0),UDim2.new(0,310,0,14),Color3.new(0.0901960805,0.0980392173,0.121568628),UDim2.new(0.5,0,1,-85),UDim2.new(0,150,0,20),UDim2.new(0,100,0,4),}

-- Property sets contain only values that differ from Instance.new defaults.
local propertyNames = {"DisplayOrder","ResetOnSpawn","ScreenInsets","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderSizePixel","Position","Size","Visible","ZIndex","BottomLeftRadius","BottomRightRadius","TopLeftRadius","TopRightRadius","FontFace","Text","TextColor3","TextSize","TextWrapped","TextXAlignment","Image","ImageColor3","ImageTransparency","TextTransparency","Color","Transparency","HorizontalAlignment","Padding","SortOrder","Thickness","ClearTextOnFocus","CellPadding","CellSize","FillDirectionMaxCells","SliceCenter","LayoutOrder","ApplyStrokeMode","Rotation","ClipsDescendants","VerticalAlignment","TextScaled","TextStrokeTransparency","TextYAlignment","Offset","PlaceholderColor3","PlaceholderText","ScaleType","Active","AutomaticCanvasSize","CanvasSize","ScrollBarImageColor3","ScrollBarThickness","FillDirection","ImageRectOffset","ImageRectSize","Animated","EasingStyle","ScrollBarImageTransparency","RichText","Enabled","ScrollingDirection","PaddingBottom","PaddingLeft","PaddingRight","PaddingTop","TextTruncate","AutoButtonColor"}
local propertySets = {{1,1,2,3,3,2},{4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,3,12,11},{13,12,14,12,15,12,16,12},{5,19,6,20,7,7,8,8,17,13,9,21,10,22,18,14,19,15,20,16,21,17,22,18,12,23},{5,19,6,20,7,7,8,8,9,24,10,25,12,26},{5,19,6,20,7,7,8,8,17,27,9,31,10,32,18,28,19,29,20,30,21,17,22,18,12,23},{5,19,6,20,7,7,8,8,17,27,9,34,10,35,18,33,19,29,20,30,21,17,22,18,12,23},{5,19,6,20,7,7,8,8,23,36,24,15,25,37,9,38,10,39,12,26},{5,40,6,6,7,7,8,8,9,41,10,42,12,26},{},{5,19,6,20,7,7,8,8,17,43,10,42,18,44,19,45,20,46,26,20,12,47},{5,19,6,20,7,7,8,8,17,48,9,50,10,51,18,49,19,15,20,46,21,17,22,18,12,23},{27,19,28,52},{6,20,23,53,9,54,10,55,12,23},{5,40,6,6,7,7,8,8,9,56,10,42,12,26},{5,19,6,20,7,7,8,8,17,48,9,50,10,51,18,57,19,15,20,46,21,17,22,18,12,23},{6,20,23,58,9,54,10,55,12,23},{5,19,6,20,7,7,9,59,10,60,12,26},{29,62,30,61,31,63},{5,64,6,20,7,7,8,8,10,65,11,3,12,26},{27,64,32,66,28,20},{13,67,14,67,15,67,16,67},{5,19,7,7,8,8,9,68,10,69,12,70},{13,71,14,71,15,71,16,71},{27,72},{4,73,5,74,8,8,9,75,10,76,12,77},{13,78,14,78,15,78,16,78},{4,73,5,19,8,8,9,79,10,80,12,81},{4,73,6,20,23,82,24,74,25,83,9,79,10,84,12,70},{5,19,6,20,7,7,8,8,17,48,10,86,18,85,19,15,20,46,21,17,22,18,12,23},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,89,9,79,10,90,11,3,12,91},{13,61,14,61,15,61,16,61},{5,19,6,20,7,7,17,43,9,92,10,93,18,44,19,45,20,46,12,47},{5,40,8,8,9,68,10,94,12,95},{5,40,33,3,17,96,9,99,10,100,18,97,19,98,20,46,12,23},{5,19,6,20,7,7,9,101,10,102,12,26},{34,103,35,42,36,104,31,63},{5,40,6,6,7,7,8,8,10,42,11,3,12,26},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,105,9,79,10,90,11,3,12,91},{13,106,14,106,15,106,16,106},{5,19,6,20,7,7,8,8,23,107,24,15,9,54,10,55,12,23},{6,20,17,96,9,50,10,51,18,108,19,15,20,46,22,18,12,23},{5,109,6,37,8,8,10,110,12,111},{5,112,6,113,8,8,9,114,10,115,12,23},{5,112,6,113,8,8,9,116,10,115,12,23},{6,20,9,117,10,118,12,26},{30,67,31,63},{5,119,6,120,7,7,8,8,10,121,11,3,12,26},{5,19,6,20,7,7,8,8,17,43,10,121,18,44,19,45,20,46,26,20,12,47},{5,19,6,20,7,7,8,8,23,122,24,15,9,123,10,124,12,23},{27,125,28,126},{6,20,17,96,9,128,10,129,18,127,19,15,20,46,22,18,12,23},{6,20,17,96,9,131,10,132,18,127,19,29,20,130,22,18,12,23},{4,73,6,20,23,133,24,134,25,135,9,79,10,137,37,136,12,138},{6,20,7,7,8,8,23,139,38,20,9,55,10,140,12,23},{39,141,27,19,28,142},{27,143,40,144},{6,20,17,96,9,146,10,147,18,145,19,29,20,130,22,18,12,23},{4,73,5,148,8,8,9,149,40,150,10,151,12,91},{4,4,5,19,6,20,7,7,8,8,41,17,9,152,10,153,12,1},{30,154,31,63,42,155},{4,73,5,19,6,20,7,7,8,8,9,156,10,157,11,3,12,1},{4,73,5,19,6,20,7,7,8,8,17,27,9,79,10,161,18,158,19,15,43,17,20,159,44,160,21,17,12,162},{4,73,5,19,7,7,8,8,9,163,10,164,11,3,12,130},{13,165,14,165,15,165,16,165},{5,19,6,20,7,7,8,8,17,48,9,169,10,170,18,166,19,15,20,167,26,160,21,17,22,18,45,168,12,130},{4,171,5,172,6,37,7,7,8,8,17,48,9,173,10,174,18,57,19,15,20,16,21,17,12,130},{13,175,14,175,15,175,16,175},{5,19,6,20,7,7,8,8,17,27,9,178,10,179,18,176,19,15,43,17,20,177,21,17,22,18,12,130},{27,180,46,181,40,182},{4,73,5,5,6,160,7,7,8,8,9,183,10,184,11,3},{4,73,5,19,6,20,7,7,8,8,33,3,17,185,47,186,48,187,9,188,10,189,18,44,19,186,43,17,20,177,21,17,22,18},{4,73,5,19,6,20,7,7,8,8,23,190,24,186,9,192,49,191,10,140},{50,17,51,193,5,19,6,20,7,7,8,8,52,194,9,196,53,172,54,195,10,197},{29,62,30,198,31,63},{5,199,7,7,8,8,38,200,9,201},{5,199,7,7,8,8,38,1,9,201},{5,202,6,203,7,7,8,8,9,204,10,205},{5,19,6,20,7,7,8,8,17,27,9,207,10,208,18,206,19,15,43,17,20,177,21,17,22,18},{5,19,6,20,7,7,8,8,17,209,9,211,10,212,18,210,19,15,20,177,26,160,21,17,22,18,45,168},{5,19,6,20,7,7,8,8,17,209,9,214,10,215,18,213,19,15,43,17,20,177,26,37,21,17,22,18},{5,19,6,20,7,7,8,8,9,216,10,217},{55,218,29,219,30,71,31,63,42,220},{5,221,7,7,8,8,38,130,9,222,10,223},{4,73,5,19,6,20,7,7,8,8,17,185,9,79,10,225,18,224,19,15,43,17,20,177,21,17,12,226},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,37,9,227,10,90},{5,228,7,7,8,8,38,130,9,229,10,230},{4,73,5,19,6,20,7,7,8,8,17,185,9,79,10,225,18,231,19,15,43,17,20,177,21,17,12,226},{5,232,7,7,8,8,38,130,9,222,10,233},{4,73,5,19,6,20,7,7,8,8,17,185,9,79,10,225,18,234,19,15,43,17,20,177,21,17,12,226},{4,73,5,202,6,203,7,7,8,8,17,48,9,236,10,237,18,235,19,15,20,16,21,17,12,130},{4,73,5,19,6,20,7,7,8,8,17,27,9,239,10,240,18,238,19,186,43,17,20,177,26,20,21,17},{4,73,5,19,6,20,7,7,8,8,17,48,9,242,10,243,18,241,19,186,43,17,20,177,26,20,21,17},{27,244,46,245,40,182},{4,73,5,19,7,7,9,79,10,246,11,3},{5,19,6,20,7,7,17,27,9,248,10,249,18,247,19,15,43,17,20,177,21,17,22,18},{4,253,6,20,7,7,8,8,23,250,56,251,57,252,25,89,9,254,10,255,12,195},{5,19,6,20,7,7,17,48,9,258,10,259,18,256,19,257,43,17,20,177,21,17,22,18},{27,260,46,261,40,262},{5,172,6,37,7,7,9,263,10,264},{5,19,6,20,7,7,33,3,17,185,47,265,48,266,9,268,10,269,18,44,19,15,20,267,22,18},{13,270,14,270,15,270,16,270},{5,172,6,37,7,7,9,271,10,272},{5,19,6,20,7,7,33,3,17,185,47,265,48,273,9,274,10,275,18,44,19,15,20,267,21,17,22,18,45,168},{5,172,6,37,7,7,9,276,10,264},{5,19,6,20,7,7,33,3,17,185,47,265,48,277,9,268,10,269,18,44,19,15,20,267,22,18},{5,202,6,37,7,7,17,48,9,280,10,281,18,278,19,15,20,16,26,279,21,17},{4,73,5,5,6,160,7,7,9,79,10,282,11,3,12,111},{5,19,6,20,7,7,17,27,9,284,10,285,18,283,19,15,43,17,20,177,21,17,22,18,12,286},{5,19,6,20,7,7,9,287,10,288,12,286},{34,289,35,290,36,226,29,62,31,63},{5,19,7,7,8,8,10,291,11,3,12,286},{13,292,14,292,15,292,16,292},{27,19},{27,293,46,294,40,182},{27,295,46,181,40,182},{5,19,6,20,7,7,8,8,17,13,9,299,10,300,18,296,19,15,43,17,20,177,26,297,21,17,22,298,12,301},{4,73,5,19,6,20,7,7,8,8,23,302,25,37,9,303,10,304,12,305},{4,73,5,19,6,20,7,7,8,8,17,43,9,79,10,306,18,44,19,45,20,177,12,307},{5,19,6,20,7,7,17,185,9,309,10,310,18,308,19,257,20,177,21,17,22,18,12,286},{6,20,7,7,23,250,56,311,57,252,9,312,10,124,12,286},{5,19,6,20,7,7,41,17,9,313,10,288,12,286},{58,3,59,314,55,315,29,62,31,63,42,220},{50,17,51,193,5,19,6,20,7,7,8,8,52,194,54,195,10,306,12,286},{5,186,6,316,7,7,8,8,9,317,10,318,12,286},{5,19,6,20,7,7,8,8,17,48,9,320,10,321,18,319,19,15,43,17,20,177,21,17,22,18,12,286},{27,202,28,89},{4,322,5,323,6,20,7,7,8,8,9,324,10,325,12,286},{13,326,14,326,15,326,16,326},{27,172,28,105},{4,327,5,328,6,329,7,7,8,8,9,330,10,331,12,286},{27,19,32,332,28,37},{4,73,5,19,6,20,7,7,8,8,17,43,9,333,10,334,18,44,19,45,20,177,26,20,12,301},{5,19,6,20,7,7,8,8,17,185,9,336,10,337,18,335,19,15,20,177,26,160,21,17,22,18,45,168,11,3,12,286},{5,19,6,20,7,7,8,8,17,48,9,339,10,340,18,338,19,15,43,17,20,177,26,89,21,17,22,18,45,168,11,3,12,286},{29,62,30,106,31,63},{5,341,6,20,7,7,8,8,38,200,9,317,12,286},{5,19,6,20,7,7,8,8,17,48,9,320,10,321,18,342,19,15,43,17,20,177,21,17,22,18,12,286},{4,322,5,323,6,20,7,7,8,8,9,343,10,344,12,286},{4,73,5,19,6,20,7,7,8,8,33,3,17,48,47,345,48,346,9,79,10,254,18,44,19,15,43,17,20,177,26,135,21,17,12,301},{27,347,28,203},{5,186,6,316,7,7,8,8,9,348,10,318,12,286},{50,17,51,193,5,19,6,20,7,7,8,8,9,349,53,15,60,37,54,195,10,350,11,3,12,286},{5,5,7,7,8,8,9,351,10,352,12,286},{27,353},{4,73,5,19,6,20,7,7,8,8,17,96,9,355,10,356,18,354,19,15,43,17,20,177,21,17,22,18,12,286},{5,19,6,20,7,7,8,8,17,43,10,306,18,44,19,45,20,20,12,301},{5,5,7,7,8,8,38,200,9,351,12,286},{4,358,5,19,6,20,7,7,8,8,17,185,9,359,10,360,18,357,19,15,43,17,20,177,26,105,21,17,22,298,12,286},{4,73,6,20,7,7,8,8,23,250,24,15,56,361,57,252,25,105,38,362,9,363,10,364,12,286},{4,73,5,19,6,20,7,7,8,8,17,43,9,365,10,366,18,44,19,45,20,177,26,20,12,301},{5,19,6,20,7,7,8,8,17,48,9,320,10,321,18,367,19,15,43,17,20,177,21,17,22,18,12,286},{5,186,6,316,7,7,8,8,9,368,10,318,12,286},{4,322,5,19,6,20,7,7,8,8,17,185,9,370,10,371,18,369,19,15,43,17,20,177,26,89,21,17,22,298,12,286},{4,73,5,19,6,20,7,7,8,8,17,43,9,79,10,306,18,44,19,45,20,177,26,20,12,301},{5,19,6,20,7,7,8,8,17,48,9,320,10,321,18,335,19,15,43,17,20,177,21,17,22,18,12,286},{5,19,6,20,7,7,8,8,17,185,9,372,10,337,18,335,19,15,20,177,26,160,21,17,22,18,45,168,11,3,12,286},{5,341,6,20,7,7,8,8,38,373,9,317,12,286},{27,374,46,181,40,182},{4,73,5,199,6,113,7,7,9,375,10,376,11,3},{13,377,14,377,15,377,16,377},{4,73,5,19,6,20,7,7,8,8,17,185,9,378,10,379,18,44,19,19,43,17,20,177,26,160,21,17,22,18,12,104},{4,73,5,19,6,20,7,7,8,8,17,185,9,381,61,17,10,382,18,380,19,19,43,17,20,177,26,20,21,17,22,298,12,383},{4,73,5,19,6,20,7,7,8,8,17,48,47,19,48,384,9,385,10,386,18,44,19,19,43,17,20,177,26,105,21,17,22,18,12,104},{4,358,5,19,6,20,7,7,9,387,10,388,11,3},{5,341,7,7,8,8,10,306,11,3},{4,327,5,19,6,20,7,7,8,8,17,96,9,390,10,391,18,389,19,15,43,17,20,177,21,17,22,18},{4,73,5,19,6,20,7,7,8,8,17,43,9,333,10,334,18,44,19,45,20,177,26,20,12,104},{4,322,5,5,7,7,8,8,9,370,10,325},{27,392},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,89,9,79,10,393,12,226},{4,327,5,202,7,7,8,8,9,330,10,331},{27,109,32,332},{4,73,5,394,6,203,7,7,8,8,9,395,10,396},{27,397,32,332,28,297},{5,394,7,7,8,8,10,398},{27,399,32,332,28,297},{4,73,5,19,6,20,7,7,8,8,17,96,9,402,10,403,18,400,19,15,43,17,20,177,26,401,21,17,22,18,12,104},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,37,9,79,10,90,12,226},{5,19,6,20,7,7,8,8,17,43,10,306,18,44,19,45,20,177,12,130},{4,327,5,19,6,20,7,7,8,8,17,96,9,390,10,405,18,404,19,15,43,17,20,177,21,17,22,18},{4,322,5,5,7,7,8,8,9,370,10,344},{4,73,5,19,6,20,7,7,8,8,33,3,17,96,47,265,48,346,9,79,10,406,18,44,19,15,20,177},{4,327,5,19,6,20,7,7,8,8,17,96,9,390,10,407,18,389,19,15,43,17,20,177,21,17,22,18},{4,322,5,5,7,7,8,8,9,370,10,408},{4,73,5,19,6,20,7,7,8,8,33,3,17,96,47,265,48,409,9,79,10,406,18,410,19,15,20,177},{4,73,5,19,6,20,7,7,8,8,17,96,9,412,10,413,18,411,19,15,43,17,20,177,26,316,21,17,22,298},{4,73,5,19,6,20,7,7,8,8,17,43,9,79,10,306,18,44,19,45,20,177,26,20,12,104},{4,73,5,19,6,20,7,7,8,8,23,302,24,414,25,415,9,79,10,416,12,8},{4,73,5,19,6,20,7,7,8,8,9,79,10,417},{4,358,5,45,6,20,7,45,8,8,9,418,10,419,11,3},{4,358,5,19,6,20,7,7,8,8,17,48,9,421,10,161,18,420,19,19,20,16,26,89,21,17,12,11},{4,358,5,19,6,316,7,45,8,8,9,422,10,423},{4,73,5,45,7,7,8,8,9,424,10,425,11,3},{4,73,5,19,6,20,7,7,8,8,23,426,25,105,9,79,49,427,10,306},{5,19,6,20,7,7,10,306},{4,171,5,45,6,105,7,7,8,8,17,48,9,173,10,428,18,235,19,15,20,16,21,17,12,130},{39,141,27,19,32,332,28,429},{4,327,5,19,6,20,7,7,8,8,17,48,9,432,10,433,18,430,19,431,20,177,26,160,21,17,22,18,12,130},{4,327,5,19,6,20,7,7,8,8,17,27,9,435,10,436,18,434,19,15,43,17,20,177,21,17,22,18,12,130},{5,19,7,7,9,437,10,438,11,3},{5,19,6,20,7,7,17,48,9,440,10,441,18,439,19,15,43,17,20,177,26,160,21,17,22,18},{27,442,46,443,40,444},{5,19,6,20,7,7,17,27,9,446,10,447,18,445,19,15,43,17,20,177,21,17,22,18},{4,73,5,19,6,20,7,7,8,8,23,302,24,448,25,37,9,79,10,449,12,8},{4,73,5,19,6,20,7,7,8,8,23,302,24,448,25,37,9,79,10,450,12,8},{4,358,5,19,7,7,9,451,10,452,11,3},{4,73,5,202,6,20,7,7,17,48,9,454,10,455,18,453,19,19,20,16,26,297,21,17},{27,456,46,181,40,182},{5,19,6,20,7,7,17,27,9,457,10,458,18,453,19,15,43,17,20,177,21,17,22,18},{5,19,6,20,7,7,17,48,9,459,10,460,18,453,19,19,43,17,20,177,26,160,21,17,22,18},{5,19,6,20,7,45,8,8,9,461,10,462},{5,202,6,37,7,7,17,185,9,463,10,464,18,453,19,15,20,167,26,279},{55,218,29,219,30,61,31,63,42,220},{4,4,5,5,6,6,7,7,8,8,9,465,10,466,12,11},{13,467,14,467,15,467,16,467},{39,141,27,19,28,429},{4,4,5,40,6,6,7,7,8,8,9,468,10,469,12,11},{13,470,14,470,15,470,16,470},{27,19,32,471,28,203},{4,73,5,19,6,20,8,8,41,17,9,79,10,306,12,472},{4,73,5,19,7,7,8,8,38,20,9,473,10,84,12,472},{4,73,6,20,7,7,8,8,23,474,24,15,38,20,9,79,10,476,37,475,12,472},{27,19,32,332},{27,477,40,478},{27,479,40,478},{4,73,5,19,6,20,7,7,8,8,17,43,9,79,10,306,18,44,19,45,20,177,26,20,12,111},{4,73,5,19,7,7,8,8,38,195,9,480,10,84,12,472},{4,73,6,20,7,7,8,8,23,139,24,15,38,20,9,79,10,476,12,472},{27,481,40,478},{27,482,40,478},{4,73,5,19,7,7,8,8,38,226,9,483,10,84,12,472},{4,73,6,20,7,7,8,8,23,484,24,15,38,20,9,79,10,476,12,472},{27,485,40,478},{27,486,40,478},{4,73,5,19,7,7,8,8,38,487,9,488,10,84,12,472},{4,73,6,20,7,7,8,8,23,489,24,15,38,20,9,79,10,476,12,472},{27,490,40,478},{27,491,40,478},{55,218,29,62,30,61,31,63,42,220},{4,73,5,19,7,7,8,8,38,104,9,492,10,84,12,472},{4,73,6,20,7,7,8,8,23,493,24,15,38,20,9,79,10,476,12,472},{27,494,40,478},{27,495,40,478},{5,19,6,20,7,7,8,8,38,496,9,497,10,498,11,3,12,95},{5,19,6,20,7,7,8,8,38,499,9,500,10,498,11,3,12,95},{4,73,5,19,6,20,7,7,8,8,17,501,9,503,10,504,18,502,19,15,20,159,21,17,12,11},{5,19,6,20,7,7,17,505,9,507,10,508,18,506,19,19,20,130,12,11},{4,73,5,19,6,20,7,7,8,8,23,82,25,20,9,509,10,510,12,91},{4,73,5,19,6,20,7,7,8,8,23,511,25,316,9,79,10,512},{4,73,5,513,6,279,7,7,41,17,9,514,10,515,11,3},{5,19,6,20,7,7,17,209,9,517,10,518,18,516,19,257,20,177,21,17,12,1},{27,519,62,3,46,181,40,182},{5,19,6,20,7,7,17,27,9,521,10,522,18,520,19,15,43,17,20,177,21,17,12,1},{5,202,6,37,7,7,23,523,9,524,10,525,12,1},{27,323,32,195},{5,19,6,20,7,7,17,27,9,527,10,522,18,526,19,257,43,17,20,177,21,17,12,1},{5,172,6,37,7,7,17,185,9,528,10,529,18,49,19,15,20,167,26,279,11,3,12,1},{5,19,6,20,7,7,17,209,9,531,10,532,18,530,19,15,43,17,20,177,26,105,21,17,11,3,12,1},{5,19,6,20,7,7,17,185,9,534,10,535,18,533,19,186,43,17,20,267,21,17,12,1},{4,253,6,20,7,7,8,8,23,250,56,251,57,252,25,89,9,536,10,255,12,1},{5,40,6,401,7,45,8,8,9,537,10,518},{5,202,6,20,7,7,17,185,10,306,18,538,19,15,20,167,26,279,12,1},{27,539,40,540,28,541},{4,73,5,19,6,20,7,7,8,8,23,82,24,542,25,37,9,543,10,544,12,545},{5,546,7,45,8,8,9,547,10,548},{4,73,5,19,6,20,7,7,8,8,23,82,25,203,9,549,10,550,12,545},{27,551},{4,4,5,5,6,6,7,7,8,8,9,9,10,552,11,3,12,11},{5,19,6,20,7,7,8,8,17,96,9,556,10,557,18,553,19,554,43,17,20,555,21,17,22,18,12,138},{5,19,6,20,7,7,8,8,10,306,12,138},{50,17,51,193,5,19,6,20,7,7,8,8,52,194,9,558,53,431,60,20,54,195,10,559,12,26},{5,19,6,560,7,7,8,8,41,17,38,20,10,561,12,95},{27,19,28,120},{27,562,40,478},{5,19,6,20,7,7,8,8,17,185,9,565,10,566,18,563,19,564,20,130,21,17,22,18,12,70},{4,73,5,19,6,20,7,7,8,8,23,567,9,568,10,569,11,3,12,70},{4,322,5,19,6,20,7,7,8,8,17,185,9,571,10,572,18,570,19,19,43,17,20,177,26,105,21,17,11,3,12,70},{5,19,6,20,7,7,8,8,17,27,9,575,10,576,18,573,19,574,43,17,20,46,21,17,22,18,12,70},{4,73,5,19,6,20,7,7,8,8,41,17,9,395,10,577,11,3,12,70},{5,40,7,7,8,8,10,578,12,77},{4,73,5,19,6,20,7,7,8,8,23,87,24,88,25,37,9,79,10,90,12,70},{4,73,5,19,6,20,7,7,8,8,17,43,9,79,10,306,19,45,20,177,26,20,12,579},{4,73,5,19,6,20,7,7,8,8,23,580,24,202,9,79,49,191,10,476,12,81},{27,581,32,332},{5,40,7,7,8,8,9,582,10,578,12,77},{4,73,5,19,6,20,7,7,8,8,23,583,24,202,9,79,49,191,10,476,12,81},{5,19,7,7,8,8,38,130,12,77},{5,40,7,7,8,8,9,584,10,578,12,77},{4,73,5,19,6,20,7,7,8,8,23,585,24,202,9,79,49,191,10,476,12,81},{5,40,7,7,8,8,9,586,10,578,12,77},{4,73,5,19,6,20,7,7,8,8,23,587,24,202,9,79,49,191,10,476,12,81},{5,323,6,20,7,7,8,8,23,588,9,589,10,590,12,70},{13,591,14,591,15,591,16,591},{27,592,32,332},{5,19,6,20,7,7,17,43,10,306,18,44,19,45,20,177,12,23},{4,73,5,19,6,20,7,7,8,8,23,82,24,542,25,37,9,593,10,594,11,3,12,70},{5,595,8,8,9,596,10,597,12,77},{27,598,40,478},{5,19,6,20,7,7,8,8,38,496,12,95},{5,19,6,20,7,7,8,8,38,499,12,95},{5,353,6,6,7,7,8,8,9,599,10,600,12,26},{27,186,28,89},{5,19,6,20,7,7,8,8,33,3,17,48,47,186,48,601,9,602,10,603,18,44,19,15,20,46,21,17,22,18,12,95},{5,19,6,20,7,7,8,8,23,604,24,186,9,605,49,191,10,606,12,95},{4,73,5,19,6,20,7,7,8,8,17,13,9,608,10,609,18,607,19,431,20,16,21,17,22,18,11,3,12,26},{4,73,5,19,6,20,7,7,8,8,17,209,9,611,10,612,18,610,19,431,20,177,26,105,21,17,11,3,12,26},{5,19,6,613,9,614,10,615,12,26},{6,20,23,588,24,616,9,617,10,618,12,70},{6,20,17,96,9,621,10,622,18,619,19,620,20,16,12,77},{6,20,17,96,9,625,10,626,18,623,19,624,20,46,12,77},{5,19,6,6,9,627,10,628,12,95},{27,629,28,113},{27,630},{6,20,17,96,9,50,10,632,18,631,19,620,20,130,22,18,12,77},{6,20,23,633,9,634,10,331,12,70},{5,19,6,6,9,635,10,628,12,95},{27,636,28,113},{27,637},{6,20,17,96,9,50,10,632,18,638,19,620,20,130,22,18,12,77},{6,20,23,82,9,639,10,640,12,70},{5,19,6,6,9,641,10,628,12,95},{27,642,28,113},{27,643},{6,20,17,96,9,50,10,632,18,644,19,620,20,130,22,18,12,77},{6,20,23,645,9,634,10,331,12,70},{5,19,8,8,9,617,10,618,12,95},{27,646},{5,647,8,8,9,648,10,640,12,77},{6,20,23,82,24,647,25,89,9,649,10,650,12,70},{6,20,9,651,10,652,12,26},{6,20,17,96,10,654,18,33,19,653,20,30,22,18,12,95},{5,19,6,655,9,656,10,657,12,95},{27,19,28,89},{6,20,23,658,24,616,9,659,10,124,12,70},{6,20,17,96,9,662,10,663,18,660,19,661,20,30,22,18,12,70},{6,20,10,306,18,44,12,111},{27,664,40,144},{5,19,6,655,9,665,10,657,12,95},{6,20,23,666,24,616,9,659,10,124,12,70},{6,20,17,96,9,662,10,663,18,667,19,661,20,30,22,18,12,70},{6,20,10,306,18,44,12,23},{5,19,6,655,9,668,10,657,12,95},{6,20,23,633,24,616,9,659,10,124,12,70},{6,20,17,96,9,662,10,663,18,669,19,661,20,30,22,18,12,70},{5,19,6,655,9,670,10,657,12,95},{6,20,23,671,24,616,9,659,10,124,12,70},{6,20,17,96,9,662,10,663,18,672,19,661,20,30,22,18,12,70},{6,20,7,7,8,8,23,489,24,15,38,20,9,673,10,674,12,138},{4,73,5,19,6,20,7,7,8,8,23,82,24,15,25,37,9,675,10,676,12,26},{39,141,27,677,28,678},{5,679,6,329,7,45,8,8,9,680,10,681,12,138},{5,679,6,89,7,45,8,8,9,682,10,683,12,138},{6,20,17,501,9,686,10,687,18,684,19,685,20,130,22,18,12,138},{4,73,5,5,6,6,8,8,9,688,40,150,10,151,12,138},{27,689,40,144},{4,171,5,19,6,20,7,45,8,8,9,690,10,691},{5,88,6,692,7,45,8,8,41,17,9,693,10,694,11,3,12,1},{4,327,5,696,6,20,7,45,8,8,23,695,9,697,10,476,12,162},{4,73,5,19,6,20,7,7,8,8,23,82,25,142,9,698,10,699,12,1},{4,73,5,19,6,20,7,45,8,8,17,43,9,79,10,306,18,44,19,45,20,177,26,20,12,1},{27,19,28,203},{5,19,6,20,7,7,8,8,17,185,9,428,10,701,18,700,19,19,20,167,26,113,21,17,22,18,45,168,12,162},{5,19,6,20,7,7,8,8,17,48,9,703,10,704,18,702,19,19,20,16,21,17,22,18,12,162},{4,73,5,19,6,20,7,45,8,8,9,79,10,705,12,1},{4,73,5,19,6,20,7,7,8,8,23,82,25,142,9,706,10,707,12,1},{29,62,30,198,31,63,42,155},{4,73,6,20,9,79,10,306,11,3},{5,45,6,105,8,8,10,306},{5,19,6,20,8,8,9,708,10,709,12,159},{13,710,14,710,15,710,16,710},{27,711,32,712,28,20},{5,713,6,20,8,8,10,714,18,44,12,715},{13,716,14,716,15,716,16,716},{5,19,6,20,8,8,23,717,24,718,9,719,49,191,10,55,12,720},{5,19,6,20,8,8,17,505,9,723,10,724,18,721,19,722,20,30,21,17,22,18,12,720},{5,19,6,135,8,8,9,725,10,714,18,44,12,715},{5,19,6,20,8,8,23,726,24,718,9,719,49,191,10,55,12,720},{5,19,6,20,8,8,17,501,9,723,10,724,18,727,19,722,20,30,21,17,22,18,12,720},{5,19,6,20,8,8,9,728,10,714,18,44,12,715},{5,19,6,20,8,8,23,729,24,718,9,719,49,191,10,55,12,720},{5,19,6,20,8,8,17,501,9,723,10,724,18,730,19,722,20,30,21,17,22,18,12,720},{5,19,6,560,8,8,9,24,10,731,12,732},{5,19,6,20,8,8,23,733,9,734,49,191,10,735,12,720},{13,736,14,736,15,736,16,736},{5,19,6,20,8,8,17,505,9,738,10,739,18,737,19,722,20,732,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,741,10,742,18,740,19,722,20,30,21,17,22,18,12,720},{5,19,6,20,8,8,10,731,18,44,12,715},{27,743,32,195,28,744},{27,745,40,746},{6,20,17,96,9,749,10,742,18,747,19,748,20,30,22,18,12,720},{6,20,17,96,9,752,10,753,18,750,19,751,20,46,22,18,12,720},{6,20,17,96,9,755,10,756,18,754,19,722,20,167,22,18,12,720},{27,757,46,181,40,182},{4,73,5,19,6,20,8,8,9,79,10,758,12,159},{5,19,6,20,8,8,10,758,12,159},{5,19,6,560,8,8,41,17,9,759,10,760,12,159},{5,19,6,20,8,8,23,761,9,762,49,427,10,763,12,720},{27,711,32,712,28,89},{5,764,6,6,8,8,10,306,11,3,12,159},{13,765,14,765,15,765,16,765},{40,144,28,766},{5,19,6,20,8,8,23,767,9,768,49,191,10,735,12,720},{13,769,14,769,15,769,16,769},{5,19,6,20,8,8,17,501,9,771,10,772,18,770,19,718,20,30,21,17,22,18,11,3,12,720},{5,19,6,20,8,8,17,505,9,774,10,775,18,773,19,722,20,159,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,777,10,778,18,776,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,9,779,10,780,12,159},{5,19,6,20,8,8,17,501,9,782,10,783,18,781,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,23,784,24,718,9,785,49,191,10,762,12,720},{51,786,6,20,8,8,52,194,53,787,60,142,54,8,63,788,10,789,12,159},{55,218,30,790,31,63},{64,61,65,791,66,71,67,791},{6,20,10,124,11,3,12,159},{5,19,6,20,8,8,23,588,49,191,10,306,12,720},{6,20,10,306,18,44,12,715},{6,20,38,20,10,124,12,159},{5,19,6,20,8,8,23,733,49,191,10,306,12,720},{6,20,38,195,10,124,12,159},{6,20,38,226,10,124,12,159},{5,19,6,20,8,8,23,792,49,191,10,306,12,720},{6,20,10,793,18,44,12,715},{27,745,46,181,40,746},{6,20,17,96,9,796,10,797,18,794,19,795,20,30,22,18,12,720},{5,798,6,316,8,8,9,799,10,800,12,1},{5,798,6,316,8,8,9,801,10,800,12,1},{5,19,6,135,8,8,9,802,10,803,11,3,12,159},{27,711,32,195,28,89},{5,19,6,20,8,8,17,505,9,806,10,807,18,804,19,805,20,30,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,809,10,810,18,808,19,718,20,30,21,17,22,18,12,720},{5,19,6,20,8,8,17,505,9,813,10,814,18,811,19,812,20,30,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,816,10,817,18,815,19,718,20,30,21,17,22,18,12,720},{5,19,6,560,8,8,9,818,10,819,12,159},{5,19,6,20,8,8,23,53,24,718,9,820,49,191,10,606,12,720},{5,19,6,20,8,8,17,505,9,822,10,823,18,821,19,722,20,16,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,825,10,826,18,824,19,718,20,30,21,17,22,18,11,3,12,720},{5,19,6,20,8,8,9,827,10,828,12,159},{5,798,6,316,8,8,9,829,10,830,12,159},{5,19,6,20,8,8,23,831,24,718,9,832,49,191,10,833,11,3,12,720},{5,19,6,20,8,8,17,501,9,835,10,836,18,834,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,838,10,839,18,837,19,722,20,267,21,17,22,298,12,720},{5,19,6,20,8,8,9,840,10,828,12,159},{5,19,6,20,8,8,23,841,24,718,9,832,49,191,10,833,11,3,12,720},{5,19,6,20,8,8,17,501,9,835,10,836,18,842,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,838,10,839,18,843,19,722,20,267,21,17,22,298,12,720},{5,19,6,20,8,8,9,844,10,828,12,159},{5,19,6,20,8,8,23,729,24,718,9,832,49,191,10,833,11,3,12,720},{5,19,6,20,8,8,17,501,9,835,10,836,18,845,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,838,10,839,18,846,19,722,20,267,21,17,22,298,12,720},{5,19,6,560,8,8,9,847,10,848,12,159},{5,19,6,20,8,8,17,505,9,849,10,850,18,727,19,722,20,16,21,17,22,18,12,720},{5,19,6,20,8,8,23,784,9,851,10,55,12,715},{51,193,5,19,6,20,8,8,52,194,9,854,60,852,54,195,63,853,10,855,12,159},{64,270,65,71,66,198,67,71},{5,19,6,20,8,8,10,856,11,3,12,159},{5,857,6,113,8,8,23,588,9,858,49,191,10,859,12,720},{27,711,28,142},{5,19,6,20,8,8,17,505,9,860,10,861,18,631,19,722,20,167,21,17,22,18,12,720},{5,862,8,8,9,863,10,597,12,159},{5,19,6,20,8,8,17,501,9,865,10,866,18,864,19,722,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,10,856,18,44,12,715},{6,20,17,96,9,868,10,869,18,773,19,867,20,46,22,18,12,720},{30,270,31,63},{5,19,6,20,8,8,38,20,10,856,12,159},{5,857,6,113,8,8,23,733,9,858,49,191,10,859,12,720},{5,19,6,20,8,8,17,505,9,860,10,861,18,870,19,722,20,167,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,865,10,866,18,864,19,871,20,267,21,17,22,18,12,720},{5,19,6,20,8,8,38,195,10,856,12,159},{5,19,6,20,8,8,17,505,9,860,10,861,18,872,19,722,20,167,21,17,22,18,12,720},{5,19,6,20,8,8,17,501,9,865,10,866,18,873,19,871,20,267,21,17,22,18,12,720},{6,20,17,96,9,868,10,869,18,874,19,867,20,46,22,18,12,720},{5,19,6,20,8,8,38,226,10,856,12,159},{5,857,6,113,8,8,23,792,9,858,49,191,10,859,12,720},{5,19,6,20,8,8,17,505,9,860,10,861,18,875,19,722,20,167,21,17,22,18,12,720},{5,876,8,8,9,863,10,597,12,159},{5,19,6,20,8,8,17,501,9,865,10,866,18,877,19,876,20,267,21,17,22,18,12,720},{6,20,17,96,9,868,10,869,18,878,19,867,20,46,22,18,12,720},{5,5,6,20,8,8,9,879,10,880,12,159},{27,881,32,195,28,20},{5,19,6,20,8,8,17,505,10,883,18,882,19,722,20,16,21,17,22,18,12,720},{5,19,6,20,8,8,23,784,9,884,10,762,12,715},{51,786,5,19,6,20,8,8,52,194,9,885,60,852,54,195,63,788,10,886,12,159},{5,19,6,20,8,8,10,887,11,3,12,159},{5,889,6,6,8,8,23,888,9,890,49,427,10,891,12,720},{13,892,14,892,15,892,16,892},{5,19,6,20,8,8,17,505,9,895,10,896,18,893,19,722,20,30,68,894,22,18,12,720},{5,19,6,20,8,8,17,501,9,898,10,899,18,897,19,722,20,46,21,17,22,18,12,720},{5,19,6,20,8,8,10,887,18,44,12,715},{55,218,30,769,31,63},{5,19,6,20,8,8,38,20,10,887,12,159},{5,889,6,6,8,8,23,767,9,890,49,427,10,891,12,720},{5,19,6,20,8,8,17,505,9,895,10,896,18,900,19,722,20,30,68,894,22,18,12,720},{5,19,6,20,8,8,38,195,10,887,12,159},{5,889,6,6,8,8,23,901,9,890,49,427,10,891,12,720},{5,19,6,20,8,8,17,505,9,895,10,896,18,902,19,722,20,30,68,894,22,18,12,720},{5,19,6,20,8,8,38,226,10,887,12,159},{5,889,6,6,8,8,23,903,9,890,49,427,10,891,12,720},{5,19,6,20,8,8,17,505,9,895,10,896,18,904,19,722,20,30,68,894,22,18,12,720},{27,905,46,181,40,746},{5,19,6,560,9,906,10,907,12,159},{6,20,17,96,9,909,10,910,18,908,19,722,20,16,22,18,12,720},{51,193,6,20,8,8,52,194,9,911,54,195,10,912,12,159},{30,198,31,63},{6,20,10,913,11,3,12,159},{5,914,23,729,10,84,12,720},{6,20,17,96,9,916,10,917,18,915,19,722,20,267,22,18,12,720},{6,20,17,96,9,919,10,920,18,918,19,722,20,46,22,18,12,720},{6,20,38,20,10,913,12,159},{6,20,17,96,9,916,10,917,18,921,19,722,20,267,22,18,12,720},{6,20,17,96,9,919,10,920,18,922,19,722,20,46,22,18,12,720},{6,20,38,195,10,913,12,159},{6,20,17,96,9,916,10,917,18,923,19,722,20,267,22,18,12,720},{6,20,17,96,9,919,10,920,18,924,19,722,20,46,22,18,12,720},{6,20,38,226,10,913,12,159},{6,20,17,96,9,916,10,917,18,925,19,722,20,267,22,18,12,720},{6,20,17,96,9,919,10,920,18,926,19,722,20,46,22,18,12,720},{5,19,6,20,8,8,10,306,11,3,12,159},{5,19,6,560,8,8,9,759,10,760,12,159},{5,19,6,20,8,8,17,96,9,928,10,929,18,727,19,927,20,732,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,933,10,934,18,931,19,932,20,30,68,894,22,18,12,930},{5,936,6,135,8,8,33,3,17,501,47,932,48,935,9,937,10,938,18,44,19,927,20,30,22,18,12,930},{65,939,66,292},{5,19,6,20,8,8,9,940,10,941,12,159},{5,942,6,135,8,8,10,943,18,44,12,715},{5,19,6,20,8,8,17,96,10,943,18,944,19,927,20,30,68,894,12,945},{5,946,6,135,8,8,9,947,10,943,18,44,12,715},{5,19,6,20,8,8,17,96,10,943,18,864,19,927,20,30,68,894,12,945},{5,946,6,135,8,8,9,948,10,943,18,44,12,715},{5,19,6,20,8,8,17,96,10,943,18,873,19,927,20,30,68,894,12,945},{5,946,6,135,8,8,9,949,10,943,18,44,12,715},{5,19,6,20,8,8,17,96,10,943,18,877,19,927,20,30,68,894,12,945},{51,193,5,19,6,20,8,8,52,194,9,951,53,950,60,692,54,226,63,853,10,952,12,159},{64,198,65,791,66,61,67,790},{5,19,6,953,8,8,10,954,11,3,12,159},{27,955,40,746,28,956},{27,743,28,957},{5,958,6,692,8,8,23,733,9,959,49,191,10,960,12,720},{5,961,8,8,9,962,10,289,12,715},{5,19,6,20,8,8,17,96,9,964,10,965,18,963,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,966,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,23,767,9,969,49,191,10,590,12,720},{5,19,6,20,8,8,17,96,9,971,10,972,18,864,19,970,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,561,10,973,18,773,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,10,974,18,44,12,715},{5,975,6,135,8,8,9,883,10,976,18,44,12,715},{5,19,6,20,8,8,17,96,10,976,18,977,19,978,20,30,68,894,12,945},{5,946,6,135,8,8,9,979,10,980,18,44,12,715},{5,19,6,20,8,8,17,96,10,980,18,981,19,927,20,30,68,894,12,945},{5,19,6,953,8,8,38,20,10,954,12,159},{27,982,28,983},{5,970,8,8,9,962,10,289,12,715},{5,19,6,20,8,8,17,96,9,964,10,965,18,870,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,984,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,195,10,954,12,159},{5,958,6,692,8,8,23,588,9,959,49,191,10,960,12,720},{5,19,6,20,8,8,17,96,9,964,10,965,18,872,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,985,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,23,767,9,969,49,191,10,590,11,3,12,720},{5,19,6,20,8,8,17,96,9,971,10,972,18,873,19,970,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,561,10,973,18,874,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,10,976,18,986,19,978,20,30,68,894,12,945},{5,19,6,953,8,8,38,226,10,954,12,159},{5,958,6,692,8,8,23,792,25,692,9,959,49,191,10,960,12,720},{5,932,8,8,9,962,10,289,12,715},{5,19,6,20,8,8,17,96,9,964,10,965,18,875,19,927,20,177,26,401,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,987,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,971,10,972,18,877,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,561,10,973,18,878,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,487,10,954,12,159},{5,958,6,692,8,8,23,988,9,959,49,191,10,960,12,720},{5,19,6,20,8,8,17,96,9,964,10,965,18,989,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,990,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,23,901,9,969,49,191,10,590,12,720},{5,19,6,20,8,8,17,96,9,561,10,973,18,902,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,104,10,954,12,159},{5,958,6,692,8,8,23,991,9,959,49,191,10,960,12,720},{5,19,6,20,8,8,17,96,9,964,10,965,18,992,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,993,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,383,10,954,12,159},{5,958,6,692,8,8,23,994,25,692,9,959,49,191,10,960,12,720},{5,19,6,20,8,8,17,96,9,964,10,965,18,995,19,927,20,177,26,401,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,967,10,968,18,996,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,9,997,10,998,11,3,12,159},{5,19,6,20,8,8,17,96,9,1000,10,1001,18,999,19,932,20,177,68,894,21,17,11,3,12,930},{5,19,6,20,8,8,17,96,9,1000,10,1001,18,1002,19,932,20,177,68,894,21,17,11,3,12,930},{5,19,6,20,8,8,17,96,9,1000,10,1001,18,1003,19,932,20,177,68,894,21,17,11,3,12,930},{5,19,6,560,8,8,9,818,10,1004,12,159},{5,958,6,692,8,8,23,733,9,1005,49,191,10,1006,12,720},{13,1007,14,1007,15,1007,16,1007},{5,19,6,20,8,8,17,96,9,1008,10,1009,18,870,19,927,20,159,68,894,12,930},{5,19,6,20,8,8,17,96,9,1010,10,1011,18,984,19,932,20,30,68,894,12,930},{5,19,6,953,8,8,9,1012,10,1013,12,159},{5,19,6,20,8,8,23,767,9,959,49,191,10,525,12,720},{5,19,6,20,8,8,17,96,9,1015,10,1016,18,1014,19,970,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1017,10,1018,18,773,19,927,20,30,68,894,21,17,22,18,12,930},{5,975,6,135,8,8,9,1019,10,1020,18,44,12,715},{5,19,6,20,8,8,17,96,10,1020,18,977,19,978,20,30,68,894,12,945},{5,19,6,20,8,8,17,96,9,1022,10,1023,18,1021,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1025,10,1026,18,1024,19,932,20,30,68,894,21,17,22,18,45,168,12,930},{5,19,6,20,8,8,17,96,9,1028,10,1009,18,1027,19,932,20,46,68,894,21,17,22,18,12,930},{5,946,6,135,8,8,9,1029,10,1030,18,44,12,715},{5,19,6,20,8,8,17,96,10,1030,18,672,19,927,20,30,68,894,12,945},{5,946,6,135,8,8,9,1031,10,1032,18,44,12,715},{5,19,6,20,8,8,17,96,10,1032,18,1033,19,927,20,30,68,894,12,945},{5,19,6,20,8,8,17,505,9,849,10,850,18,1034,19,722,20,16,21,17,22,18,12,720},{5,19,6,20,8,8,17,96,9,928,10,929,18,1035,19,927,20,732,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,933,10,934,18,1036,19,932,20,30,68,894,22,18,12,930},{5,936,6,135,8,8,33,3,17,501,47,932,48,1037,9,937,10,938,18,44,19,927,20,30,22,18,12,930},{5,19,6,20,8,8,17,96,10,943,18,1038,19,927,20,30,68,894,12,945},{5,19,6,20,8,8,17,96,10,943,18,730,19,927,20,30,68,894,12,945},{5,19,6,953,8,8,10,1039,11,3,12,159},{5,19,6,20,8,8,23,767,9,1040,49,191,10,735,12,720},{5,19,6,20,8,8,17,96,9,1042,10,1043,18,1041,19,927,20,167,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1045,10,1046,18,1044,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1048,10,1049,18,1047,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,10,1050,18,44,12,715},{5,975,6,135,8,8,9,1051,10,1052,18,44,12,715},{5,19,6,20,8,8,17,96,10,1052,18,1053,19,978,20,30,68,894,12,945},{5,946,6,135,8,8,9,1054,10,1055,18,44,12,715},{5,19,6,20,8,8,17,96,10,1055,18,1056,19,927,20,30,68,894,12,945},{5,19,6,953,8,8,38,20,10,1039,12,159},{5,19,6,20,8,8,17,96,9,1042,10,1043,18,773,19,927,20,167,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1045,10,1046,18,1057,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1048,10,1049,18,1058,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,195,10,1039,12,159},{5,19,6,20,8,8,23,901,9,1040,49,191,10,735,12,720},{5,19,6,20,8,8,17,96,9,1042,10,1043,18,902,19,927,20,167,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1045,10,1046,18,1059,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1048,10,1049,18,1060,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,226,10,1039,12,159},{5,19,6,20,8,8,23,903,9,1040,49,191,10,735,12,720},{5,19,6,20,8,8,17,96,9,1042,10,1043,18,904,19,927,20,167,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1045,10,1046,18,1061,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1048,10,1049,18,1062,19,932,20,46,68,894,22,18,12,930},{5,19,6,953,8,8,38,487,10,1039,12,159},{5,19,6,20,8,8,17,96,9,1048,10,1049,18,1063,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,23,761,9,762,49,427,10,1064,12,720},{5,19,6,20,8,8,17,96,9,1066,10,1067,18,773,19,927,20,1065,68,894,21,17,22,18,45,168,12,930},{5,19,6,20,8,8,17,96,9,1068,10,1023,18,1057,19,932,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1070,10,1023,18,1069,19,927,20,177,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1072,10,1073,18,1071,19,932,20,30,68,894,21,17,22,18,45,168,12,930},{5,975,6,135,8,8,9,1074,10,1075,18,44,12,715},{5,19,6,20,8,8,17,96,10,1075,18,1053,19,978,20,30,68,894,12,945},{5,946,6,135,8,8,9,1076,10,1077,18,44,12,715},{5,19,6,20,8,8,17,96,10,1077,18,1078,19,927,20,30,68,894,12,945},{5,1079,6,142,8,8,9,1080,10,1081,12,720},{5,19,6,20,8,8,17,96,9,55,10,1083,18,1082,19,927,20,16,68,894,22,18,12,930},{5,19,6,20,8,8,23,784,9,1084,10,55,12,715},{51,193,5,19,6,20,8,8,52,194,9,1085,60,852,54,226,63,853,10,1086,12,159},{5,19,6,20,8,8,10,1087,11,3,12,159},{5,889,6,6,8,8,23,888,9,1088,49,427,10,1089,12,720},{5,19,6,20,8,8,17,96,9,1090,10,1091,18,893,19,927,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,17,96,9,1092,10,1093,18,897,19,932,20,46,68,894,22,18,12,930},{5,19,6,20,8,8,10,1094,18,44,12,715},{5,19,6,20,8,8,38,20,10,1087,12,159},{5,889,6,6,8,8,23,767,9,1088,49,427,10,1089,12,720},{5,19,6,20,8,8,17,96,9,1090,10,1091,18,900,19,927,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,38,195,10,1087,12,159},{5,889,6,6,8,8,23,901,9,1088,49,427,10,1089,12,720},{5,19,6,20,8,8,17,96,9,1090,10,1091,18,902,19,927,20,30,68,894,22,18,12,930},{5,19,6,20,8,8,38,226,10,1087,12,159},{5,889,6,6,8,8,23,903,9,1088,49,427,10,1089,12,720},{5,19,6,20,8,8,17,96,9,1090,10,1091,18,904,19,927,20,30,68,894,22,18,12,930},{4,4,5,5,6,6,8,8,9,9,10,1095,11,3,12,1},{39,141,27,1096,28,89},{6,20,23,484,9,1097,10,124,12,1098},{6,20,17,96,9,1101,10,1102,18,1099,19,1100,20,1065,21,17,22,18,45,168,12,1098},{6,20,10,306,12,1098},{6,20,10,306,12,1103},{5,19,6,560,8,8,9,1104,10,1105,12,1106},{27,1107,40,159},{27,1108,28,142},{5,1108,6,89,8,8,9,1109,10,1089,12,1110},{69,3,6,20,23,604,24,1111,9,1112,10,1113,12,1110},{6,20,17,96,9,1115,10,1116,18,1114,19,1100,20,16,68,894,22,18,45,168,12,1110},{6,20,17,501,9,1119,10,1120,18,1117,19,1118,20,30,21,17,22,18,45,168,12,1110},{6,20,17,501,9,1122,10,1123,18,1121,19,1100,20,732,21,17,22,18,45,168,12,1110},{6,20,10,306,18,44,12,1124},{5,19,6,560,8,8,9,1125,10,1126,12,1106},{27,1127,40,159},{27,1128,28,142},{5,1128,6,89,8,8,9,1109,10,1089,12,1110},{69,3,6,20,23,1129,24,1130,9,1112,10,1113,12,1110},{6,20,17,96,9,1115,10,1132,18,1131,19,1100,20,16,68,894,22,18,45,168,12,1110},{6,20,17,501,9,1119,10,1134,18,1133,19,1118,20,30,21,17,22,18,45,168,12,1110},{6,20,17,501,9,1135,10,1123,18,1121,19,1100,20,732,21,17,22,18,45,168,12,1110},{5,19,6,560,8,8,9,1136,10,1137,12,1106},{27,1138,40,159},{27,1139,28,142},{5,1139,6,89,8,8,9,1040,10,891,12,1110},{69,3,6,20,23,1140,24,1141,9,734,10,1142,12,1110},{6,20,17,96,9,1144,10,1145,18,1143,19,1100,20,267,68,894,22,18,45,168,12,1110},{6,20,17,501,9,1146,10,1147,18,44,19,1118,20,30,21,17,22,18,45,168,11,3,12,1110},{6,20,17,501,9,1148,10,1123,18,1121,19,1100,20,732,21,17,22,18,45,168,12,1110},{5,19,6,560,8,8,9,1149,10,1150,12,1106},{27,1151,40,159},{27,1152,28,142},{5,1152,6,89,8,8,9,1040,10,891,12,1110},{69,3,6,20,23,1153,24,1154,9,734,10,1142,12,1110},{6,20,17,96,9,1156,10,1157,18,1155,19,1100,20,267,68,894,22,18,45,168,12,1110},{6,20,17,501,9,1146,10,1159,18,1158,19,1118,20,30,21,17,22,18,45,168,12,1110},{6,20,17,501,9,1160,10,1123,18,1121,19,1100,20,732,21,17,22,18,45,168,12,1110},{5,19,6,560,8,8,9,1161,10,1162,12,1106},{27,1163,40,159},{27,1164,28,142},{5,1164,6,89,8,8,9,1040,10,891,12,1110},{69,3,6,20,23,1165,24,1166,9,734,10,1142,12,1110},{6,20,17,96,9,1156,10,1168,18,1167,19,1100,20,267,68,894,22,18,45,168,12,1110},{6,20,17,501,9,1146,10,1170,18,1169,19,1118,20,30,21,17,22,18,45,168,12,1110},{6,20,17,501,9,1171,10,1123,18,1121,19,1100,20,732,21,17,22,18,45,168,12,1110},{5,19,6,20,7,45,8,8,38,20,10,306,11,3,12,1103},{50,17,4,73,51,193,5,19,6,20,7,45,8,8,52,194,9,1172,60,37,54,226,10,1173,12,1106},{5,1174,7,45,8,8,10,1175,12,1110},{4,327,5,19,6,20,7,45,8,8,17,48,9,1177,10,1178,18,1176,19,19,43,17,20,177,21,17,22,18,12,162},{4,171,5,40,7,7,8,8,17,48,9,1179,10,428,18,235,19,15,20,16,21,17,12,162},{4,327,5,19,6,20,7,45,8,8,17,185,9,1181,10,1182,18,1180,19,19,43,17,20,177,26,105,21,17,22,18,12,162},{30,61,31,63},{4,73,5,1183,8,8,9,706,40,150,10,762,12,1098},{4,73,5,19,6,20,7,45,8,8,9,1184,10,1185},{5,19,6,20,7,45,8,8,17,209,10,306,18,44,19,45,20,177,26,20},{4,73,5,19,6,160,7,45,8,8,9,79,10,1186},{4,4,6,20,7,7,23,250,56,361,57,252,38,362,9,1184,10,364,11,3,12,11}}

local attributeSets = {
{["DesignHeight"]=303,["DesignWidth"]=582,["TemplateNote"]="Clone hidden Template; remove IsPreview instances before populating. Grid and Sliders retain legacy child names. Toggles is the new quick-action template container."},{["Purpose"]="Gaussian rounded halo with fully transparent padding; no sliced texture edges"},{["TargetButton"]="SmartBar.Buttons.Character"},{["IsTemplate"]=true},{["SelectedUserId"]=0},{["RequiresSelection"]=true},{["DesignHeight"]=490,["DesignNotes"]="Studio dashboard mockup. Remove IsPreview rows before scripted population. Existing Friends, RecentlyPlayed, FriendsPlaying template paths retained. RecentActivity.List.Template added; live controller requires adaptation to compact layout.",["DesignWidth"]=1040,["LayoutNote"]="Home and Dim must remain full-screen. Centered content lives in Pages and Sidebar. Design content size 1040x440; preserve templates when wiring.",["PreviewData"]=true},{["TargetPage"]="Home"},{["TargetPage"]="Friends"},{["TargetPage"]="Games"},{["PlaceId"]=3260590327,["UniverseId"]=1176784616},{["FriendCount"]=12,["TemplateUsage"]="Clone List.Template; set Visible=true, IsTemplate=false, UserId, DisplayName, Username and LayoutOrder; set Avatar.Image; parent to List. Remove IsPreview entries when populating. Update Summary.Text and FriendCount separately."},{["DisplayName"]="",["IsTemplate"]=true,["UserId"]=0,["Username"]=""},{["DisplayName"]="",["IsPreview"]=true,["IsTemplate"]=true,["UserId"]=0,["Username"]=""},{["IsTemplate"]=true,["UserId"]=0},{["IsPreview"]=true,["IsTemplate"]=true,["UserId"]=0},{["IsTemplate"]=true,["PlaceId"]=0,["UniverseId"]=0},{["IsPreview"]=true,["IsTemplate"]=true,["PlaceId"]=0,["UniverseId"]=0},{["IsPreview"]=true},{["SelectedFilter"]="All"},{["Filter"]="All"},{["Filter"]="InGame"},{["Filter"]="Online"},{["Filter"]="Offline"},{["CanJoin"]=false,["IsTemplate"]=true,["JobId"]="",["PlaceId"]=0,["Presence"]="Unknown",["UniverseId"]=0,["UserId"]=0},{["CanJoin"]=false,["IsPreview"]=true,["IsTemplate"]=true,["JobId"]="",["PlaceId"]=0,["Presence"]="Unknown",["UniverseId"]=0,["UserId"]=0},{["SelectedFilter"]="Favorites"},{["DataSource"]="Favorites"},{["DataSource"]="TrackedHistory"},{["CanPlay"]=false,["IsFavorite"]=false,["IsTemplate"]=true,["LastPlayedAt"]=0,["PlaceId"]=0,["UniverseId"]=0},{["CanPlay"]=false,["IsFavorite"]=false,["IsPreview"]=true,["IsTemplate"]=true,["LastPlayedAt"]=0,["PlaceId"]=0,["UniverseId"]=0},{["SelectedPlaceId"]=0,["SelectedUniverseId"]=0},}

-- {parent index, class index, name, property set, optional attribute set}
local nodes = {
{0,4,"Altair",1},{1,1,"Character",2,1},{2,10,"UICorner",3},{2,8,"Title",4},{2,1,"Interactions",5},{5,8,"PropertiesTitle",6},{5,8,"ActionsTitle",7},{5,2,"Reset",8},{5,1,"Serverhop",9},{9,10,"UICorner",10},{9,7,"Interact",11},{9,8,"Title",12},{9,16,"UIStroke",13},{9,3,"Icon",14},{5,1,"Rejoin",15},{15,10,"UICorner",10},{15,7,"Interact",11},{15,8,"Title",16},{15,16,"UIStroke",13},{15,3,"Icon",17},{5,1,"Sliders",18},{21,13,"UIListLayout",19},{21,1,"Template",20},{23,16,"UIStroke",21},{23,10,"UICorner",22},{23,1,"Progress",23},{26,10,"UICorner",24},{26,11,"UIGradient",25},{26,1,"Knob",26},{29,10,"UICorner",27},{29,1,"Center",28},{31,10,"UICorner",10},{29,3,"Glow",29},{23,8,"Information",30},{23,3,"Shadow",31},{35,10,"UICorner",32},{23,7,"Interact",33},{23,1,"Track",34},{38,10,"UICorner",24},{23,6,"Value",35},{40,10,"UICorner",10},{5,1,"Grid",36},{42,12,"UIGridLayout",37},{42,1,"Template",38},{44,10,"UICorner",10},{44,3,"Shadow",39},{46,10,"UICorner",40},{44,7,"Interact",11},{44,3,"Icon",41},{44,16,"UIStroke",13},{44,8,"Title",42},{5,1,"HeaderDivider",43},{5,1,"ActionsDivider",44},{5,1,"PropertiesDivider",45},{5,1,"Toggles",46},{55,13,"UIListLayout",47},{55,1,"Template",48},{57,10,"UICorner",10},{57,3,"Shadow",39},{59,10,"UICorner",40},{57,7,"Interact",49},{57,3,"Icon",50},{57,16,"UIStroke",51},{57,8,"Title",52},{57,8,"Subtitle",53},{57,3,"Glow",54,2},{2,2,"Icon",55},{2,16,"UIStroke",56},{2,11,"UIGradient",57},{2,8,"Subtitle",58},{2,1,"Pointer",59,3},{1,1,"Toasts",60},{72,13,"UIListLayout",61},{72,1,"Template",62},{74,8,"Title",63},{1,1,"Disconnected",64},{76,10,"UICorner",65},{76,8,"Content",66},{76,7,"Action",67},{79,10,"UICorner",68},{76,8,"Title",69},{76,11,"UIGradient",70},{1,1,"ScriptSearch",71},{83,10,"UICorner",3},{83,6,"SearchBox",72},{83,3,"Icon",73},{83,5,"List",74},{87,13,"UIListLayout",75},{87,1,"Placeholder",76},{87,1,"Placeholder",77},{87,1,"Template",78},{91,10,"UICorner",10},{91,8,"ScriptName",79},{91,8,"ScriptDescription",80},{91,8,"ScriptAuthor",81},{91,1,"Tags",82},{96,13,"UIListLayout",83},{96,1,"Verified",84},{98,10,"UICorner",68},{98,8,"Title",85},{98,3,"Shadow",86},{101,10,"UICorner",40},{96,1,"Review",87},{103,10,"UICorner",68},{103,8,"Title",88},{103,3,"Shadow",86},{106,10,"UICorner",40},{96,1,"Patched",89},{108,10,"UICorner",68},{108,8,"Title",90},{108,3,"Shadow",86},{111,10,"UICorner",40},{91,7,"Execute",91},{113,10,"UICorner",68},{83,8,"NoScriptsTitle",92},{83,8,"NoScriptsDesc",93},{83,11,"UIGradient",94},{83,16,"UIStroke",56},{1,1,"CustomScriptPrompt",95},{119,10,"UICorner",65},{119,8,"Title",96},{119,2,"Close",97},{119,8,"Subtitle",98},{119,11,"UIGradient",99},{119,1,"IDBox",100},{125,6,"IDTextBox",101},{125,10,"UICorner",102},{119,1,"DescBox",103},{128,6,"DescTextBox",104},{128,10,"UICorner",102},{119,1,"ScriptBox",105},{131,10,"UICorner",102},{131,6,"ScriptTextBox",106},{119,7,"Submit",107},{134,10,"UICorner",68},{1,1,"Settings",108},{136,10,"UICorner",3},{136,8,"Title",109},{136,1,"SettingTypes",110},{139,12,"UIGridLayout",111},{139,1,"Template",112},{141,10,"UICorner",113},{141,16,"UIStroke",114},{143,11,"UIGradient",115},{141,11,"UIGradient",116},{141,8,"Title",117},{141,3,"Shadow",118},{147,11,"UIGradient",115},{141,7,"Interact",119},{136,8,"Subtitle",120},{136,2,"Back",121},{136,1,"SettingLists",122},{152,15,"UIPageLayout",123},{152,5,"Template",124},{154,1,"SwitchTemplate",125},{155,10,"UICorner",40},{155,8,"Title",126},{155,16,"UIStroke",127},{155,1,"Switch",128},{159,10,"UICorner",129},{159,16,"UIStroke",130},{159,1,"Indicator",131},{162,10,"UICorner",68},{162,16,"UIStroke",132},{155,7,"Interact",133},{155,8,"Description",134},{155,8,"LicenseDisplay",135},{154,13,"UIListLayout",136},{154,1,"Placeholder",137},{154,1,"InputTemplate",125},{170,10,"UICorner",40},{170,16,"UIStroke",127},{170,8,"Title",138},{170,1,"InputFrame",139},{174,6,"InputBox",140},{174,10,"UICorner",32},{174,16,"UIStroke",141},{170,8,"Description",134},{170,8,"LicenseDisplay",135},{154,1,"DropdownTemplate",142},{180,10,"UICorner",24},{180,5,"List",143},{182,1,"Template",144},{183,10,"UICorner",32},{183,16,"UIStroke",145},{183,8,"Title",146},{183,7,"Interact",147},{182,13,"UIListLayout",19},{182,1,"Placeholder",148},{180,8,"Selected",149},{180,2,"Toggle",150},{180,7,"Interact",151},{180,16,"UIStroke",127},{180,8,"Title",152},{154,1,"ButtonTemplate",153},{195,10,"UICorner",40},{195,16,"UIStroke",127},{195,8,"Note",154},{195,7,"Interact",155},{195,8,"Title",156},{195,8,"Description",157},{195,8,"LicenseDisplay",135},{154,1,"Placeholder",158},{136,11,"UIGradient",159},{136,16,"UIStroke",56},{1,1,"Starlight",160},{206,10,"UICorner",161},{206,8,"AutoComplete",162},{206,8,"CompleteNote",163},{206,6,"CommandBox",164},{206,1,"RayfieldView",165},{211,1,"Toggle",166},{212,8,"Title",167},{212,7,"Interact",168},{212,1,"Switch",169},{215,10,"UICorner",129},{215,16,"UIStroke",170},{215,3,"Shadow",171},{218,10,"UICorner",129},{215,1,"Indicator",172},{220,10,"UICorner",68},{220,16,"UIStroke",173},{212,10,"UICorner",161},{211,1,"Slider",166},{224,1,"Main",174},{225,16,"UIStroke",175},{225,10,"UICorner",40},{225,1,"Progress",176},{228,10,"UICorner",40},{228,16,"UIStroke",177},{225,8,"Information",178},{225,3,"Shadow",179},{232,10,"UICorner",40},{225,7,"Interact",180},{224,8,"Title",181},{224,10,"UICorner",161},{211,1,"Input",166},{237,10,"UICorner",161},{237,1,"InputFrame",182},{239,6,"InputBox",183},{239,16,"UIStroke",170},{239,10,"UICorner",32},{237,8,"Title",184},{211,1,"Keybind",166},{244,10,"UICorner",161},{244,1,"KeybindFrame",185},{246,6,"KeybindBox",186},{246,16,"UIStroke",170},{246,10,"UICorner",32},{244,8,"Title",184},{211,1,"Button",166},{251,10,"UICorner",161},{251,8,"ElementIndicator",187},{251,7,"Interact",188},{251,8,"Title",184},{206,3,"Shadow",189},{206,1,"BlurModule",190},{1,1,"Status",191},{258,8,"Title",192},{258,1,"Line",193},{1,1,"GameDetection",194},{261,10,"UICorner",65},{261,3,"Thumbnail",195},{263,10,"UICorner",65},{261,1,"Layer",196},{265,7,"Run",197},{266,10,"UICorner",68},{266,16,"UIStroke",198},{265,8,"ScriptSubtitle",199},{265,2,"Close",97},{261,8,"ScriptTitle",200},{261,1,"Warning",201},{272,8,"Subtitle",202},{272,11,"UIGradient",203},{272,8,"Title",204},{272,10,"UICorner",113},{272,3,"Shadow",205},{261,3,"Shadow",206},{1,1,"SecurityPrompt",207},{279,8,"FoundLink",208},{279,11,"UIGradient",209},{279,8,"Title",210},{279,10,"UICorner",65},{279,8,"Subtitle",211},{279,1,"Buttons",212},{285,7,"Template",213},{286,10,"UICorner",68},{285,13,"UIListLayout",214},{1,1,"SmartBar",215},{289,10,"UICorner",216},{289,16,"UIStroke",217},{289,1,"Back",218},{292,10,"UICorner",219},{292,16,"UIStroke",220},{292,1,"Buttons",221},{295,1,"Home",222},{296,10,"UICorner",22},{296,2,"Icon",223},{296,16,"UIStroke",224},{299,11,"UIGradient",225},{296,11,"UIGradient",226},{296,7,"Interact",227},{295,1,"Character",228},{303,10,"UICorner",22},{303,2,"Icon",229},{303,7,"Interact",227},{303,11,"UIGradient",230},{303,16,"UIStroke",224},{308,11,"UIGradient",231},{295,1,"Scripts",232},{310,10,"UICorner",22},{310,2,"Icon",233},{310,16,"UIStroke",224},{313,11,"UIGradient",234},{310,7,"Interact",227},{310,11,"UIGradient",235},{295,1,"Playerlist",236},{317,10,"UICorner",22},{317,2,"Icon",237},{317,16,"UIStroke",224},{320,11,"UIGradient",238},{317,7,"Interact",227},{317,11,"UIGradient",239},{295,13,"UIListLayout",240},{295,1,"Settings",241},{325,10,"UICorner",22},{325,2,"Icon",242},{325,7,"Interact",227},{325,11,"UIGradient",243},{325,16,"UIStroke",224},{330,11,"UIGradient",244},{295,1,"Placeholder",245},{295,1,"Placeholder",246},{292,8,"Time",247},{334,8,"AMPM",248},{289,3,"CircleGradient",249},{289,3,"Shadow",250},{1,1,"ModeratorDetectionPrompt",251},{338,8,"Subtitle",252},{338,11,"UIGradient",253},{338,8,"Title",254},{338,10,"UICorner",129},{338,3,"Avatar",255},{343,10,"UICorner",68},{343,16,"UIStroke",256},{338,8,"DisplayName",257},{338,7,"Serverhop",258},{347,10,"UICorner",68},{338,8,"ServersAvailableFade",259},{338,8,"Rank",260},{338,2,"Close",261},{338,1,"Leave",262},{352,10,"UICorner",68},{352,7,"Leave",263},{354,10,"UICorner",68},{352,16,"UIStroke",114},{356,11,"UIGradient",264},{338,3,"CircleGradient",265},{338,1,"Stroke",266},{338,3,"TitleGradient",267},{338,16,"UIStroke",268},{1,1,"Playerlist",269},{362,10,"UICorner",3},{362,8,"Title",270},{362,1,"Interactions",271},{365,5,"List",272},{366,1,"Template",273,4},{367,10,"UICorner",10},{367,16,"UIStroke",274},{369,11,"UIGradient",275},{367,8,"Role",276},{367,3,"Icon",277},{372,10,"UICorner",68},{367,8,"NoActions",278},{367,7,"DisplayName",279},{367,1,"PlayerInteractions",280},{376,1,"Kill",281},{377,10,"UICorner",10},{377,3,"Shadow",282},{379,10,"UICorner",22},{377,7,"Interact",283},{377,3,"Icon",284},{377,16,"UIStroke",285},{376,13,"UIListLayout",214},{376,1,"Teleport",286},{385,10,"UICorner",10},{385,3,"Shadow",282},{387,10,"UICorner",22},{385,7,"Interact",283},{385,3,"Icon",287},{385,16,"UIStroke",285},{376,1,"Placeholder",288},{376,1,"Spectate",289},{393,10,"UICorner",10},{393,3,"Shadow",282},{395,10,"UICorner",22},{393,7,"Interact",283},{393,3,"Icon",290},{393,16,"UIStroke",285},{376,1,"Locate",291},{400,10,"UICorner",10},{400,3,"Shadow",282},{402,10,"UICorner",22},{400,7,"Interact",283},{400,3,"Icon",292},{400,16,"UIStroke",285},{367,3,"Avatar",293},{407,10,"UICorner",294},{407,16,"UIStroke",295},{367,7,"Interact",296},{367,3,"CircleGradient",297},{367,1,"StatusDot",298},{412,10,"UICorner",294},{367,11,"UIGradient",299},{366,13,"UIListLayout",19},{366,1,"Placeholder",300},{366,1,"Placeholder",301},{366,1,"Template",273,4},{418,10,"UICorner",10},{418,16,"UIStroke",274},{420,11,"UIGradient",275},{418,8,"Role",276},{418,3,"Icon",277},{423,10,"UICorner",68},{418,8,"NoActions",278},{418,7,"DisplayName",279},{418,1,"PlayerInteractions",280},{427,1,"Kill",281},{428,10,"UICorner",10},{428,3,"Shadow",282},{430,10,"UICorner",22},{428,7,"Interact",283},{428,3,"Icon",284},{428,16,"UIStroke",285},{427,13,"UIListLayout",214},{427,1,"Teleport",286},{436,10,"UICorner",10},{436,3,"Shadow",282},{438,10,"UICorner",22},{436,7,"Interact",283},{436,3,"Icon",287},{436,16,"UIStroke",285},{427,1,"Placeholder",288},{427,1,"Spectate",289},{444,10,"UICorner",10},{444,3,"Shadow",282},{446,10,"UICorner",22},{444,7,"Interact",283},{444,3,"Icon",290},{444,16,"UIStroke",285},{427,1,"Locate",291},{451,10,"UICorner",10},{451,3,"Shadow",282},{453,10,"UICorner",22},{451,7,"Interact",283},{451,3,"Icon",292},{451,16,"UIStroke",285},{418,3,"Avatar",293},{458,10,"UICorner",294},{458,16,"UIStroke",295},{418,7,"Interact",296},{418,3,"CircleGradient",297},{418,1,"StatusDot",298},{463,10,"UICorner",294},{418,11,"UIGradient",299},{366,1,"Template",273,4},{466,10,"UICorner",10},{466,16,"UIStroke",274},{468,11,"UIGradient",275},{466,8,"Role",276},{466,3,"Icon",277},{471,10,"UICorner",68},{466,8,"NoActions",278},{466,7,"DisplayName",279},{466,1,"PlayerInteractions",280},{475,1,"Kill",281},{476,10,"UICorner",10},{476,3,"Shadow",282},{478,10,"UICorner",22},{476,7,"Interact",283},{476,3,"Icon",284},{476,16,"UIStroke",285},{475,13,"UIListLayout",214},{475,1,"Teleport",286},{484,10,"UICorner",10},{484,3,"Shadow",282},{486,10,"UICorner",22},{484,7,"Interact",283},{484,3,"Icon",287},{484,16,"UIStroke",285},{475,1,"Placeholder",288},{475,1,"Spectate",289},{492,10,"UICorner",10},{492,3,"Shadow",282},{494,10,"UICorner",22},{492,7,"Interact",283},{492,3,"Icon",290},{492,16,"UIStroke",285},{475,1,"Locate",291},{499,10,"UICorner",10},{499,3,"Shadow",282},{501,10,"UICorner",22},{499,7,"Interact",283},{499,3,"Icon",292},{499,16,"UIStroke",285},{466,3,"Avatar",293},{506,10,"UICorner",294},{506,16,"UIStroke",295},{466,7,"Interact",296},{466,3,"CircleGradient",297},{466,1,"StatusDot",298},{511,10,"UICorner",294},{466,11,"UIGradient",299},{366,1,"Template",273,4},{514,10,"UICorner",10},{514,16,"UIStroke",274},{516,11,"UIGradient",275},{514,8,"Role",276},{514,3,"Icon",277},{519,10,"UICorner",68},{514,8,"NoActions",278},{514,7,"DisplayName",279},{514,1,"PlayerInteractions",280},{523,1,"Kill",281},{524,10,"UICorner",10},{524,3,"Shadow",282},{526,10,"UICorner",22},{524,7,"Interact",283},{524,3,"Icon",284},{524,16,"UIStroke",285},{523,13,"UIListLayout",214},{523,1,"Teleport",286},{532,10,"UICorner",10},{532,3,"Shadow",282},{534,10,"UICorner",22},{532,7,"Interact",283},{532,3,"Icon",287},{532,16,"UIStroke",285},{523,1,"Placeholder",288},{523,1,"Spectate",289},{540,10,"UICorner",10},{540,3,"Shadow",282},{542,10,"UICorner",22},{540,7,"Interact",283},{540,3,"Icon",290},{540,16,"UIStroke",285},{523,1,"Locate",291},{547,10,"UICorner",10},{547,3,"Shadow",282},{549,10,"UICorner",22},{547,7,"Interact",283},{547,3,"Icon",292},{547,16,"UIStroke",285},{514,3,"Avatar",293},{554,10,"UICorner",294},{554,16,"UIStroke",295},{514,7,"Interact",296},{514,3,"CircleGradient",297},{514,1,"StatusDot",298},{559,10,"UICorner",294},{514,11,"UIGradient",299},{366,1,"Template",273,4},{562,10,"UICorner",10},{562,16,"UIStroke",274},{564,11,"UIGradient",275},{562,8,"Role",276},{562,3,"Icon",277},{567,10,"UICorner",68},{562,8,"NoActions",278},{562,7,"DisplayName",279},{562,1,"PlayerInteractions",280},{571,1,"Kill",281},{572,10,"UICorner",10},{572,3,"Shadow",282},{574,10,"UICorner",22},{572,7,"Interact",283},{572,3,"Icon",284},{572,16,"UIStroke",285},{571,13,"UIListLayout",214},{571,1,"Teleport",286},{580,10,"UICorner",10},{580,3,"Shadow",282},{582,10,"UICorner",22},{580,7,"Interact",283},{580,3,"Icon",287},{580,16,"UIStroke",285},{571,1,"Placeholder",288},{571,1,"Spectate",289},{588,10,"UICorner",10},{588,3,"Shadow",282},{590,10,"UICorner",22},{588,7,"Interact",283},{588,3,"Icon",290},{588,16,"UIStroke",285},{571,1,"Locate",291},{595,10,"UICorner",10},{595,3,"Shadow",282},{597,10,"UICorner",22},{595,7,"Interact",283},{595,3,"Icon",292},{595,16,"UIStroke",285},{562,3,"Avatar",293},{602,10,"UICorner",294},{602,16,"UIStroke",295},{562,7,"Interact",296},{562,3,"CircleGradient",297},{562,1,"StatusDot",298},{607,10,"UICorner",294},{562,11,"UIGradient",299},{366,1,"Template",273,4},{610,10,"UICorner",10},{610,16,"UIStroke",274},{612,11,"UIGradient",275},{610,8,"Role",276},{610,3,"Icon",277},{615,10,"UICorner",68},{610,8,"NoActions",278},{610,7,"DisplayName",279},{610,1,"PlayerInteractions",280},{619,1,"Kill",281},{620,10,"UICorner",10},{620,3,"Shadow",282},{622,10,"UICorner",22},{620,7,"Interact",283},{620,3,"Icon",284},{620,16,"UIStroke",285},{619,13,"UIListLayout",214},{619,1,"Teleport",286},{628,10,"UICorner",10},{628,3,"Shadow",282},{630,10,"UICorner",22},{628,7,"Interact",283},{628,3,"Icon",287},{628,16,"UIStroke",285},{619,1,"Placeholder",288},{619,1,"Spectate",289},{636,10,"UICorner",10},{636,3,"Shadow",282},{638,10,"UICorner",22},{636,7,"Interact",283},{636,3,"Icon",290},{636,16,"UIStroke",285},{619,1,"Locate",291},{643,10,"UICorner",10},{643,3,"Shadow",282},{645,10,"UICorner",22},{643,7,"Interact",283},{643,3,"Icon",292},{643,16,"UIStroke",285},{610,3,"Avatar",293},{650,10,"UICorner",294},{650,16,"UIStroke",295},{610,7,"Interact",296},{610,3,"CircleGradient",297},{610,1,"StatusDot",298},{655,10,"UICorner",294},{610,11,"UIGradient",299},{365,1,"SearchFrame",302},{658,10,"UICorner",40},{658,16,"UIStroke",303},{658,6,"SearchBox",304},{658,3,"Icon",305},{365,8,"Title",306},{365,8,"Value",307},{365,1,"SelectedPlayer",308,5},{665,10,"UICorner",102},{665,16,"UIStroke",274},{667,11,"UIGradient",275},{665,11,"UIGradient",299},{665,3,"Avatar",309},{670,10,"UICorner",294},{665,8,"DisplayName",310},{665,8,"Username",311},{665,1,"Friend",312},{674,10,"UICorner",102},{674,16,"UIStroke",313},{674,11,"UIGradient",314},{674,8,"Title",315},{674,3,"Icon",316},{665,1,"InServer",317},{680,10,"UICorner",102},{680,16,"UIStroke",318},{680,11,"UIGradient",319},{680,8,"Title",320},{680,3,"Icon",321},{665,1,"Premium",322},{686,10,"UICorner",102},{686,16,"UIStroke",323},{686,11,"UIGradient",324},{686,8,"Title",325},{686,3,"Icon",326},{665,1,"AvatarBackdrop",327},{692,10,"UICorner",294},{692,11,"UIGradient",328},{665,1,"OnlineDot",329},{695,10,"UICorner",294},{665,3,"StatusGlow",330},{365,1,"SelectedActions",331,6},{698,8,"Title",332},{698,1,"Spectate",333},{700,10,"UICorner",102},{700,16,"UIStroke",334},{700,3,"Icon",335},{700,8,"Title",336},{700,7,"Interact",337},{700,11,"UIGradient",338},{698,1,"Teleport",339},{707,10,"UICorner",102},{707,16,"UIStroke",334},{707,3,"Icon",340},{707,8,"Title",341},{707,7,"Interact",342},{707,11,"UIGradient",338},{698,1,"Bring",343},{714,10,"UICorner",102},{714,16,"UIStroke",334},{714,11,"UIGradient",338},{714,3,"Icon",344},{714,8,"Title",345},{714,7,"Interact",342},{698,1,"ViewProfile",346},{721,10,"UICorner",102},{721,16,"UIStroke",334},{721,3,"Icon",347},{721,8,"Title",348},{721,7,"Interact",342},{721,11,"UIGradient",338},{362,2,"Icon",349},{728,3,"CircleGradient",350},{362,16,"UIStroke",351},{362,1,"Stroke",352},{362,1,"Stroke2",353},{362,8,"Subtitle",354},{362,1,"Pointer",355},{734,11,"UIGradient",356},{362,11,"UIGradient",57},{1,1,"Notifications",357},{737,1,"Template",358},{738,10,"UICorner",219},{738,3,"Icon",359},{740,3,"CircleGradient",360},{738,7,"Interact",361},{738,16,"UIStroke",362},{738,8,"Description",363},{738,8,"Title",364},{738,1,"BlurFrame",365},{738,3,"CircleGradient",366},{737,13,"UIListLayout",367},{1,1,"Home",368,7},{749,1,"Dim",369},{749,1,"Sidebar",370},{751,10,"UICorner",371},{751,16,"UIStroke",372},{751,7,"Home",373,8},{754,10,"UICorner",374},{754,3,"Icon",375},{754,8,"Title",376},{751,7,"Friends",377,9},{758,10,"UICorner",374},{758,3,"Icon",378},{758,8,"Title",379},{751,7,"Games",380,10},{762,10,"UICorner",374},{762,3,"Icon",381},{762,8,"Title",382},{751,1,"Profile",383},{766,3,"Avatar",384},{767,10,"UICorner",385},{766,8,"DisplayName",386},{766,8,"Status",387},{766,7,"Interact",388},{766,10,"UICorner",27},{766,16,"UIStroke",389},{766,11,"UIGradient",390},{766,8,"Membership",391},{766,8,"Stats",392},{766,8,"StatValues",393},{751,11,"UIGradient",394},{749,1,"Pages",395},{779,1,"Home",396},{780,1,"NowPlaying",397,11},{781,10,"UICorner",27},{781,3,"Artwork",398},{783,10,"UICorner",161},{783,16,"UIStroke",399},{781,1,"Readability",400},{786,10,"UICorner",401},{786,11,"UIGradient",402},{781,3,"GameIcon",403},{789,10,"UICorner",404},{781,8,"Eyebrow",405},{781,8,"GameName",406},{781,8,"Creator",407},{781,1,"FriendsPlaying",408,12},{794,8,"Summary",409},{794,3,"Chevron",410},{794,5,"List",411},{797,13,"UIListLayout",412},{797,14,"UIPadding",413},{797,1,"Template",414,13},{800,3,"Avatar",415},{801,10,"UICorner",385},{801,9,"UIAspectRatioConstraint",10},{800,7,"Interact",416},{797,1,"Preview_1",417,14},{805,3,"Avatar",418},{806,10,"UICorner",385},{806,9,"UIAspectRatioConstraint",10},{805,7,"Interact",416},{797,1,"Preview_2",419,14},{810,3,"Avatar",415},{811,10,"UICorner",385},{811,9,"UIAspectRatioConstraint",10},{810,7,"Interact",416},{797,1,"Preview_3",420,14},{815,3,"Avatar",421},{816,10,"UICorner",385},{816,9,"UIAspectRatioConstraint",10},{815,7,"Interact",416},{794,7,"ViewFriends",422},{781,11,"UIGradient",423},{781,16,"UIStroke",389},{781,8,"SessionPills",424},{781,1,"Divider",425},{781,1,"Divider",426},{780,1,"SessionStatus",427},{826,10,"UICorner",371},{826,16,"UIStroke",428},{826,8,"Time",429},{826,8,"Date",430},{826,8,"Status",431},{826,8,"Game",432},{826,11,"UIGradient",394},{780,1,"Server",433},{834,10,"UICorner",27},{834,16,"UIStroke",389},{834,3,"Icon",434},{834,8,"Title",435},{834,8,"PlayerCount",436},{834,1,"Region",437},{840,1,"Divider",438},{840,3,"Icon",439},{840,8,"Label",440},{840,8,"Value",441},{834,1,"Ping",442},{845,1,"Divider",438},{845,3,"Icon",443},{845,8,"Label",444},{845,8,"Value",445},{834,1,"Uptime",446},{850,1,"Divider",438},{850,3,"Icon",447},{850,8,"Label",448},{850,8,"Value",449},{834,11,"UIGradient",423},{780,1,"Friends",450},{856,10,"UICorner",27},{856,16,"UIStroke",389},{856,8,"Title",451},{856,2,"ViewAll",452},{856,5,"List",453},{861,14,"UIPadding",454},{861,1,"Template",455,15},{863,3,"Avatar",456},{864,10,"UICorner",385},{864,16,"UIStroke",457},{863,8,"DisplayName",458},{863,1,"StatusDot",459},{868,10,"UICorner",385},{863,8,"Status",460},{863,7,"Interact",461},{863,8,"Location",462},{861,13,"UIListLayout",463},{861,1,"Preview_1",464,16},{874,3,"Avatar",465},{875,10,"UICorner",385},{875,16,"UIStroke",457},{874,8,"DisplayName",466},{874,1,"StatusDot",459},{879,10,"UICorner",385},{874,8,"Status",467},{874,7,"Interact",461},{874,8,"Location",462},{861,1,"Preview_2",468,16},{884,3,"Avatar",456},{885,10,"UICorner",385},{885,16,"UIStroke",457},{884,8,"DisplayName",469},{884,1,"StatusDot",459},{889,10,"UICorner",385},{884,8,"Status",470},{884,7,"Interact",461},{884,8,"Location",471},{861,1,"Preview_3",472,16},{894,3,"Avatar",473},{895,10,"UICorner",385},{895,16,"UIStroke",457},{894,8,"DisplayName",474},{894,1,"StatusDot",475},{899,10,"UICorner",385},{894,8,"Status",476},{894,7,"Interact",461},{894,8,"Location",477},{856,11,"UIGradient",423},{780,1,"RecentlyPlayed",478},{905,10,"UICorner",129},{905,16,"UIStroke",479},{905,8,"Title",480},{905,2,"ViewAll",481},{905,5,"List",482},{910,14,"UIPadding",454},{910,1,"Template",483,17},{912,3,"Icon",484},{913,10,"UICorner",485},{912,8,"Title",486},{912,8,"LastPlayed",487},{912,7,"Interact",488},{910,13,"UIListLayout",489},{910,1,"Preview_1",490,18},{919,3,"Icon",491},{920,10,"UICorner",485},{919,8,"Title",492},{919,8,"LastPlayed",487},{919,7,"Interact",488},{910,1,"Preview_2",493,18},{925,3,"Icon",494},{926,10,"UICorner",485},{925,8,"Title",495},{925,8,"LastPlayed",487},{925,7,"Interact",488},{910,1,"Preview_3",496,18},{931,3,"Icon",497},{932,10,"UICorner",485},{931,8,"Title",498},{931,8,"LastPlayed",487},{931,7,"Interact",488},{905,11,"UIGradient",499},{780,1,"RecentActivity",500},{938,10,"UICorner",27},{938,16,"UIStroke",389},{938,11,"UIGradient",390},{938,8,"Title",501},{938,5,"List",502},{943,13,"UIListLayout",503},{943,1,"Template",504},{945,3,"Icon",505},{946,10,"UICorner",404},{945,8,"Title",506},{945,8,"Description",507},{943,1,"Preview_1",508,19},{950,3,"Icon",505},{951,10,"UICorner",404},{950,8,"Title",509},{950,8,"Description",510},{943,1,"Preview_2",511,19},{955,3,"Icon",505},{956,10,"UICorner",404},{955,8,"Title",512},{955,8,"Description",513},{943,1,"Preview_3",514,19},{960,3,"Icon",505},{961,10,"UICorner",404},{960,8,"Title",515},{960,8,"Description",516},{779,1,"Friends",517,20},{965,1,"Browser",518},{966,10,"UICorner",27},{966,16,"UIStroke",389},{966,8,"Title",519},{966,8,"Subtitle",520},{966,6,"SearchBox",521},{971,10,"UICorner",404},{971,14,"UIPadding",522},{966,1,"Filters",523},{974,7,"All",524,21},{975,10,"UICorner",404},{975,8,"Title",525},{974,7,"InGame",526,22},{978,10,"UICorner",404},{978,8,"Title",527},{974,7,"Online",528,23},{981,10,"UICorner",404},{981,8,"Title",529},{974,7,"Offline",530,24},{984,10,"UICorner",404},{984,8,"Title",531},{966,5,"List",532},{987,13,"UIListLayout",503},{987,14,"UIPadding",533},{987,1,"Template",534,25},{990,10,"UICorner",404},{990,11,"UIGradient",535},{990,16,"UIStroke",536},{990,3,"Avatar",537},{994,10,"UICorner",216},{990,1,"StatusDot",538},{996,10,"UICorner",385},{990,8,"DisplayName",539},{990,8,"Username",540},{990,3,"GameIcon",541},{1000,10,"UICorner",40},{990,8,"Status",542},{990,8,"Location",543},{990,7,"Interact",544},{990,7,"Join",545},{1005,10,"UICorner",404},{1005,8,"Title",546},{990,7,"More",547},{1008,10,"UICorner",404},{1008,8,"Title",548},{987,1,"Preview_1",549,26},{1011,10,"UICorner",404},{1011,11,"UIGradient",535},{1011,16,"UIStroke",550},{1011,3,"Avatar",537},{1015,10,"UICorner",216},{1011,1,"StatusDot",551},{1017,10,"UICorner",385},{1011,8,"DisplayName",552},{1011,8,"Username",553},{1011,3,"GameIcon",541},{1021,10,"UICorner",40},{1011,8,"Status",542},{1011,8,"Location",543},{1011,7,"Interact",544},{1011,7,"Join",545},{1026,10,"UICorner",404},{1026,8,"Title",546},{1011,7,"More",547},{1029,10,"UICorner",404},{1029,8,"Title",548},{987,1,"Preview_2",554,26},{1032,10,"UICorner",404},{1032,11,"UIGradient",535},{1032,16,"UIStroke",536},{1032,3,"Avatar",555},{1036,10,"UICorner",216},{1032,1,"StatusDot",551},{1038,10,"UICorner",385},{1032,8,"DisplayName",556},{1032,8,"Username",557},{1032,3,"GameIcon",558},{1042,10,"UICorner",40},{1032,8,"Status",559},{1032,8,"Location",560},{1032,7,"Interact",544},{1032,7,"Join",545},{1047,10,"UICorner",404},{1047,8,"Title",561},{1032,7,"More",547},{1050,10,"UICorner",404},{1050,8,"Title",548},{987,1,"Preview_3",562,26},{1053,10,"UICorner",404},{1053,11,"UIGradient",535},{1053,16,"UIStroke",536},{1053,3,"Avatar",563},{1057,10,"UICorner",216},{1053,1,"StatusDot",564},{1059,10,"UICorner",385},{1053,8,"DisplayName",565},{1053,8,"Username",566},{1053,3,"GameIcon",558},{1063,10,"UICorner",40},{1053,8,"Status",567},{1053,8,"Location",568},{1053,7,"Interact",544},{1053,7,"Join",545},{1068,10,"UICorner",404},{1068,8,"Title",561},{1053,7,"More",547},{1071,10,"UICorner",404},{1071,8,"Title",548},{987,1,"Preview_4",569,26},{1074,10,"UICorner",404},{1074,11,"UIGradient",535},{1074,16,"UIStroke",536},{1074,3,"Avatar",570},{1078,10,"UICorner",216},{1074,1,"StatusDot",551},{1080,10,"UICorner",385},{1074,8,"DisplayName",571},{1074,8,"Username",572},{1074,3,"GameIcon",573},{1084,10,"UICorner",40},{1074,8,"Status",542},{1074,8,"Location",574},{1074,7,"Interact",544},{1074,7,"Join",545},{1089,10,"UICorner",404},{1089,8,"Title",546},{1074,7,"More",547},{1092,10,"UICorner",404},{1092,8,"Title",548},{987,1,"Preview_5",575,26},{1095,10,"UICorner",404},{1095,11,"UIGradient",535},{1095,16,"UIStroke",536},{1095,3,"Avatar",576},{1099,10,"UICorner",216},{1095,1,"StatusDot",551},{1101,10,"UICorner",385},{1095,8,"DisplayName",577},{1095,8,"Username",578},{1095,3,"GameIcon",558},{1105,10,"UICorner",40},{1095,8,"Status",559},{1095,8,"Location",560},{1095,7,"Interact",544},{1095,7,"Join",545},{1110,10,"UICorner",404},{1110,8,"Title",561},{1095,7,"More",547},{1113,10,"UICorner",404},{1113,8,"Title",548},{987,1,"Preview_6",579,26},{1116,10,"UICorner",404},{1116,11,"UIGradient",535},{1116,16,"UIStroke",536},{1116,3,"Avatar",580},{1120,10,"UICorner",216},{1116,1,"StatusDot",564},{1122,10,"UICorner",385},{1116,8,"DisplayName",581},{1116,8,"Username",582},{1116,3,"GameIcon",558},{1126,10,"UICorner",40},{1116,8,"Status",567},{1116,8,"Location",568},{1116,7,"Interact",544},{1116,7,"Join",545},{1131,10,"UICorner",404},{1131,8,"Title",561},{1116,7,"More",547},{1134,10,"UICorner",404},{1134,8,"Title",548},{966,1,"States",583},{1137,8,"Loading",584},{1137,8,"Empty",585},{1137,8,"Error",586},{966,11,"UIGradient",423},{965,1,"Details",587,5},{1142,10,"UICorner",27},{1142,16,"UIStroke",389},{1142,3,"Avatar",588},{1145,10,"UICorner",589},{1142,8,"DisplayName",590},{1142,8,"Username",591},{1142,1,"Activity",592},{1149,10,"UICorner",404},{1149,11,"UIGradient",535},{1149,16,"UIStroke",536},{1149,3,"GameIcon",593},{1153,10,"UICorner",10},{1149,8,"Status",594},{1149,8,"GameName",595},{1149,7,"Join",596},{1157,10,"UICorner",404},{1157,8,"Title",597},{1142,8,"AboutTitle",598},{1142,8,"About",599},{1142,8,"Availability",600},{1142,7,"ViewProfile",601},{1163,10,"UICorner",404},{1163,8,"Title",602},{1142,7,"More",603},{1166,10,"UICorner",404},{1166,8,"Title",604},{1142,11,"UIGradient",423},{965,1,"InThisSession",450},{1170,10,"UICorner",27},{1170,16,"UIStroke",389},{1170,8,"Title",605},{1170,2,"ViewAll",452},{1170,5,"List",453},{1175,14,"UIPadding",454},{1175,1,"Template",455,15},{1177,3,"Avatar",456},{1178,10,"UICorner",385},{1178,16,"UIStroke",457},{1177,8,"DisplayName",458},{1177,1,"StatusDot",459},{1182,10,"UICorner",385},{1177,8,"Status",460},{1177,7,"Interact",461},{1177,8,"Location",462},{1175,13,"UIListLayout",463},{1175,1,"Preview_1",464,16},{1188,3,"Avatar",465},{1189,10,"UICorner",385},{1189,16,"UIStroke",457},{1188,8,"DisplayName",466},{1188,1,"StatusDot",459},{1193,10,"UICorner",385},{1188,8,"Status",467},{1188,7,"Interact",461},{1188,8,"Location",462},{1175,1,"Preview_2",468,16},{1198,3,"Avatar",456},{1199,10,"UICorner",385},{1199,16,"UIStroke",457},{1198,8,"DisplayName",469},{1198,1,"StatusDot",459},{1203,10,"UICorner",385},{1198,8,"Status",470},{1198,7,"Interact",461},{1198,8,"Location",471},{1175,1,"Preview_3",472,16},{1208,3,"Avatar",473},{1209,10,"UICorner",385},{1209,16,"UIStroke",457},{1208,8,"DisplayName",474},{1208,1,"StatusDot",475},{1213,10,"UICorner",385},{1208,8,"Status",476},{1208,7,"Interact",461},{1208,8,"Location",477},{1170,11,"UIGradient",423},{779,1,"Games",517,27},{1219,1,"Browser",518},{1220,10,"UICorner",27},{1220,16,"UIStroke",389},{1220,8,"Title",606},{1220,8,"Subtitle",607},{1220,6,"SearchBox",608},{1225,10,"UICorner",404},{1225,14,"UIPadding",522},{1220,1,"Filters",523},{1228,7,"Favorites",526,28},{1229,10,"UICorner",404},{1229,8,"Title",609},{1228,7,"Recent",524,29},{1232,10,"UICorner",404},{1232,8,"Title",610},{1220,5,"List",532},{1235,13,"UIListLayout",503},{1235,14,"UIPadding",533},{1235,1,"Template",611,30},{1238,10,"UICorner",404},{1238,11,"UIGradient",535},{1238,16,"UIStroke",536},{1238,3,"Icon",612},{1242,10,"UICorner",404},{1238,8,"Title",613},{1238,8,"Creator",614},{1238,8,"LastPlayed",615},{1238,7,"Interact",616},{1238,7,"Play",617},{1248,10,"UICorner",404},{1248,8,"Title",618},{1238,7,"Favorite",619},{1251,10,"UICorner",404},{1251,8,"Title",620},{1235,1,"Preview_1",621,31},{1254,10,"UICorner",404},{1254,11,"UIGradient",535},{1254,16,"UIStroke",550},{1254,3,"Icon",612},{1258,10,"UICorner",404},{1254,8,"Title",622},{1254,8,"Creator",623},{1254,8,"LastPlayed",624},{1254,7,"Interact",616},{1254,7,"Play",617},{1264,10,"UICorner",404},{1264,8,"Title",618},{1254,7,"Favorite",619},{1267,10,"UICorner",404},{1267,8,"Title",620},{1235,1,"Preview_2",625,31},{1270,10,"UICorner",404},{1270,11,"UIGradient",535},{1270,16,"UIStroke",536},{1270,3,"Icon",626},{1274,10,"UICorner",404},{1270,8,"Title",627},{1270,8,"Creator",628},{1270,8,"LastPlayed",629},{1270,7,"Interact",616},{1270,7,"Play",617},{1280,10,"UICorner",404},{1280,8,"Title",618},{1270,7,"Favorite",619},{1283,10,"UICorner",404},{1283,8,"Title",620},{1235,1,"Preview_3",630,31},{1286,10,"UICorner",404},{1286,11,"UIGradient",535},{1286,16,"UIStroke",536},{1286,3,"Icon",631},{1290,10,"UICorner",404},{1286,8,"Title",632},{1286,8,"Creator",633},{1286,8,"LastPlayed",634},{1286,7,"Interact",616},{1286,7,"Play",617},{1296,10,"UICorner",404},{1296,8,"Title",618},{1286,7,"Favorite",619},{1299,10,"UICorner",404},{1299,8,"Title",620},{1235,1,"Preview_4",635,31},{1302,10,"UICorner",404},{1302,11,"UIGradient",535},{1302,16,"UIStroke",536},{1302,3,"Icon",612},{1306,10,"UICorner",404},{1302,8,"Title",622},{1302,8,"Creator",623},{1302,8,"LastPlayed",636},{1302,7,"Interact",616},{1302,7,"Play",617},{1312,10,"UICorner",404},{1312,8,"Title",618},{1302,7,"Favorite",619},{1315,10,"UICorner",404},{1315,8,"Title",620},{1220,1,"States",583},{1318,8,"Loading",584},{1318,8,"Empty",585},{1318,8,"Error",586},{1220,11,"UIGradient",423},{1219,1,"Details",587,32},{1323,10,"UICorner",27},{1323,16,"UIStroke",389},{1323,3,"Artwork",637},{1326,10,"UICorner",161},{1323,8,"Title",638},{1323,8,"Creator",639},{1323,8,"DescriptionTitle",640},{1323,8,"Description",641},{1323,7,"Play",642},{1332,10,"UICorner",404},{1332,8,"Title",643},{1323,7,"Favorite",644},{1335,10,"UICorner",404},{1335,8,"Title",645},{1323,11,"UIGradient",423},{1323,1,"Divider",646},{1219,1,"ContinuePlaying",450},{1340,10,"UICorner",27},{1340,16,"UIStroke",389},{1340,8,"Title",647},{1340,2,"ViewAll",648},{1340,5,"List",649},{1345,14,"UIPadding",454},{1345,1,"Template",650,17},{1347,3,"Icon",651},{1348,10,"UICorner",102},{1347,8,"Title",652},{1347,8,"LastPlayed",653},{1347,7,"Interact",654},{1345,13,"UIListLayout",463},{1345,1,"Preview_1",655,18},{1354,3,"Icon",656},{1355,10,"UICorner",102},{1354,8,"Title",657},{1354,8,"LastPlayed",653},{1354,7,"Interact",654},{1345,1,"Preview_2",658,18},{1360,3,"Icon",659},{1361,10,"UICorner",102},{1360,8,"Title",660},{1360,8,"LastPlayed",653},{1360,7,"Interact",654},{1345,1,"Preview_3",661,18},{1366,3,"Icon",662},{1367,10,"UICorner",102},{1366,8,"Title",663},{1366,8,"LastPlayed",653},{1366,7,"Interact",654},{1340,11,"UIGradient",423},{1,1,"Scripts",664},{1373,10,"UICorner",3},{1373,16,"UIStroke",665},{1373,2,"Icon",666},{1373,8,"Title",667},{1373,1,"Interactions",668},{1378,1,"Selection",669},{1379,1,"Library",670},{1380,10,"UICorner",102},{1380,11,"UIGradient",671},{1380,16,"UIStroke",672},{1380,1,"IconBadge",673},{1384,10,"UICorner",10},{1380,2,"Icon",674},{1380,8,"Title",675},{1380,8,"Subtitle",676},{1380,8,"Chevron",677},{1380,7,"Interact",678},{1379,1,"Reprompt",679},{1391,10,"UICorner",102},{1391,11,"UIGradient",680},{1391,16,"UIStroke",681},{1391,1,"IconBadge",682},{1395,10,"UICorner",10},{1391,2,"Icon",683},{1391,8,"Title",684},{1391,8,"Subtitle",685},{1391,8,"Chevron",686},{1391,7,"Interact",678},{1379,1,"UniversalScripts",687},{1402,10,"UICorner",102},{1402,11,"UIGradient",688},{1402,16,"UIStroke",689},{1402,1,"IconBadge",690},{1406,10,"UICorner",10},{1402,2,"Icon",691},{1402,8,"Title",692},{1402,8,"Subtitle",693},{1402,8,"Chevron",694},{1402,7,"Interact",678},{1379,1,"CustomScripts",695},{1413,10,"UICorner",102},{1413,11,"UIGradient",696},{1413,16,"UIStroke",697},{1413,1,"IconBadge",698},{1417,10,"UICorner",10},{1413,2,"Icon",699},{1413,8,"Title",700},{1413,8,"Subtitle",701},{1413,8,"Chevron",702},{1413,7,"Interact",678},{1379,1,"V4",703},{1424,10,"UICorner",102},{1424,11,"UIGradient",704},{1424,16,"UIStroke",705},{1424,1,"IconBadge",706},{1428,10,"UICorner",10},{1424,2,"Icon",707},{1424,8,"Title",708},{1424,8,"Subtitle",709},{1424,8,"Chevron",710},{1424,7,"Interact",678},{1378,1,"Universal",711},{1435,5,"List",712},{1436,1,"Template",713},{1437,10,"UICorner",404},{1437,8,"Title",714},{1437,7,"Run",715},{1440,10,"UICorner",404},{1437,8,"Subtitle",716},{1436,13,"UIListLayout",717},{1373,1,"Pointer",718},{1373,11,"UIGradient",57},{1,1,"Drag",719},{1446,10,"UICorner",219},{1446,7,"Interact",720},{1446,1,"Drag",721},{1449,10,"UICorner",219},{1,2,"Toggle",722},}

-- Molto registry, vendored from https://molto.pages.dev/source.lua (2026-11-01).
-- Sprite artwork and provider metadata are cached by Molto; no custom icon drawing.
local Molto=(function()
local Registry = {}

--// Helpers \\--
local function Check(...)
	for index = 1, select("#", ...) do
		if typeof((select(index, ...))) ~= "function" then return false end
	end
	return true
end

local AssetManager = {}
do
	local BASE_PATH = "molto-icons"

	AssetManager.Supported = Check(isfile, isfolder, makefolder, readfile, writefile, getcustomasset)
	AssetManager.CanDelete = AssetManager.Supported and Check(listfiles, delfolder)

	function AssetManager.Path(relative: string?): string
		return if relative then `{BASE_PATH}/{relative}` else BASE_PATH
	end

	function AssetManager.EnsureFolder(relative: string?)
		local current = ""
		for _, part in string.split(AssetManager.Path(relative), "/") do
			current = if current == "" then part else `{current}/{part}`
			if not isfolder(current) then
				makefolder(current)
			end
		end
	end

	function AssetManager.IsFile(relative: string): boolean
		local success, result = pcall(isfile, AssetManager.Path(relative))
		return success and result == true
	end

	function AssetManager.Read(relative: string): string?
		return if AssetManager.IsFile(relative) then readfile(AssetManager.Path(relative)) else nil
	end

	function AssetManager.Write(relative: string, data: string)
		writefile(AssetManager.Path(relative), data)
	end

	function AssetManager.Download(relative: string, url: string, validate: ((string) -> boolean)?)
		if AssetManager.IsFile(relative) then return end

		local data = game:HttpGet(url)
		assert(not validate or validate(data), `Invalid download for {relative}`)
		AssetManager.Write(relative, data)
	end

	function AssetManager.ListNames(): { string }
		local names = {}
		for _, entry in listfiles(BASE_PATH) do
			local name = entry:gsub("\\", "/"):gsub("/$", ""):match("([^/]+)$")
			if name then
				table.insert(names, name)
			end
		end
		return names
	end

	function AssetManager.GetAsset(relative: string): string
		return getcustomasset(AssetManager.Path(relative))
	end
end

--// Constants \\--
local ASSET_BASE_URL = "https://molto.pages.dev/"
local DEFAULT_PROVIDER = "lucide"
local PROVIDERS = {lucide={Hash="11d446c12405c3dcce9fcea63ca304378f0d002569c5be7431c2e946a896dd2c",FontSources={"3023058e0624db67b242be8259ad1c8bfd0baa25d2bc265496ab3f6e0cf6cbb2","d24060429c26965c0563eef73818ee939817e32cea5a8d60a3ce7f909b0f2572"},Font=true,Name="Lucide",SourceHash="0673c282baccf4ddd27b6aa413923e9004db064b696b5afb0a7e3952dbd22431",Sheets=2,License="ISC",Count=2095,FontParts=2},tabler={Hash="de0041ef23f9edba3c95e9f20f46d1a3c839d6f610a83bdcf44abd7229542e98",FontSources={"8195e5c93fd7bbd4d9d15fe17e9b26efe44cf0a33ea7eea07694dbd8037c7a0b","23456f6370d7fc077370c06c85d802c4768f21bfe70bb5b91f6a4dfea07aa8be","83da31ec40d824567641f78f70d30a1ad17c7bbb166139fc3a765ffcd2d09ef5","4c99944f07a6b2ecb43bbbda5b13550e0361a7ea38383135cc30893f9d27b0e8","8ce861237f45de04305a899db3cd95e292e6b097a4f7fa1d1fd7849701d30776"},Font=true,Name="Tabler",SourceHash="5b51978591ea66f6688a93bd24e3da217e722fc4b467d2027d0ed6ebcefca7ac",Sheets=4,License="MIT",Count=6305,FontParts=5},heroicons={Hash="da3ef30e5bda1a0cf6586a6de9789a12537d550aec9598eccc85b4326be76615",FontSources={"da02a3a8e3f2b01840e735d0025f9c898a597fa3f22802b8cf61fba7ca4dd065","1a0ce866418752177d2393a48aede97f27ba5c52239eab5e3b7a9b0de15e6c44"},Font=true,Count=1288,SourceHash="6439652a852d969b2916cffd09efb0ab9a6f2127b7b7692b7b0e48315b4b8029",Sheets=1,License="MIT",Name="Heroicons",FontParts=2},solar={Hash="01d27f4a6f5ef2740f7080fb66f89fdaca0682cff34776dd71342aed31c4788b",FontSources={"0fbc79d272ced0ecc7e9b4357c8d89c5fc58681d491c9af67cb7c16aa98db15d","c60573fba17a7a8493d8385cd2f63f5c6c2509b780a93ae358d42fdc4d724c42","9b645fa22ab9a6f9ff56f7bba9fcde3d6a9b85d09ccbd71a95e31914c636a51d","95f3976e92db9a2478efcc5629b8aec2693e33b17276ce8aa068055a1f33a08b","e12f62e3ef20c62d3a7735e915199dbc3baffbdb958c09ab24bfb1d04177ec2d","414dd9aa75fbfc2005138857544df5febe4a55e5b670d2303f2034f27e701426"},Font=true,Count=8859,SourceHash="bc5184a9d553589aad59d3375558bd13e4af5bb176dea7c89a164eabf9ee28c7",Sheets=6,License="CC BY 4.0",Name="Solar",FontParts=6},material={Hash="993be4ca36fcb877522411e30786f8fe60cfeef65173a101598a645d16767af7",FontSources={"4425cbbe00b48122e9526f66347f67b5b12e6d7f8ff320165e3f324f4c194866","c7f31caaeda57199e15b94e6a03f5b7cfc365c0fe7bd4b594d4318331df15979","874ea19f7ff611beac8077cc98bbadda90a52b374b7d3c3dc12017687cf94555","e8d6e6babc6a12e7a0d703e5df813b1f3a965359af60e3a8b3673b3289b08f77","7e80c00e76d77336e4ea67d5332d4c1e21c3e79cd48771373c04a877e2a47c79","e2bb326dab6eae516f3491c16ac606c97a50b91e40797cf24c83bc9289a0d490","8ea19612bbf24de04ee358b146c3af61ede6f1db11fd25536d73022a602631ca","472eb72acf8b80a5ee2998c01afa09d8ac5b4ad7cb8f82efd6a00aa4660d35e1","86792e6a3acd6c5aa294e30fe9f90665fa0d137d85b96091fee8ea2c1490214b","6e3b6507c9895272fe2dd1f073135bcc838e603a7afaeb2ec8332841e6a581ff","087bb1f361a113f7e3ec3118ce6f29d20b9ac5545b708c185469550fa64ac0b5","ed40ff0d0763f205a17f95fa83bec8d0a1f92aef4119f992b95a94d9050a8b26","ec71dd27d9ea3a6fd4ff488a80396328adf2c2d8f396413ce1139160defb4dfc","41e3b748421a606578891a7ecb98317777e35f7b6853e6c5e1fc7fa2fa86ed8b","c754424a1b589b740315af67f52d6f6aa1b348de97a98c8e5ccb28734b747db2","4bc3e346d9d5b1c458c5af99ba7788bbad15f15b81d551b4eba94bcb290861a7","02bf85a05bab64c5be4cf63f8ae414677027f1328fa1d74ae97ebb21163195a3"},Font=true,Name="Material Symbols",SourceHash="23bd4f231d978101790ad3bcd3e3b2eb9718b214f012b30fe1639dab1043d2b9",Sheets=11,License="Apache 2.0",Count=16475,FontParts=17},fluent={Hash="1d72f6702e4bbbf7d7b728f29f2b1d3f7f462b9aeebc112e07d1114ec7e28c9c",FontSources={"21e91032f8e038d016f28f07777f63d6acfb3cfd9a211a058a4473a24bdd060a","1d599093d1ce85121c282c4454290c7e863931e6673a33619a40d916f76ff8b0","8ae582404698799f654cf5a8aea1e609cd37a7600ca0e50519ed97254e02118d","954a0c5bd84593dbda577b5923d7fe86d21c25e41dd91e484c67bcc947fa1640","65a2b5ebc82089e9fc844bd54b03eb41a0c29b004c11900b4642f203ee0bd375","d3a65ae7af734d04cd01551bdaa66330df361b2999098072e9b4ff89c7c1a21d","425c8e47320bbc9b5916c1a645161bd982bfe1802d75d0b4c5a513c817194ef4","0b3b52b1e78ee3abbbf56bf8008b6247759e06a2b4aa843e00706bbc72b9b6d0","72f047c4e16688c5e167bb2fadf6dd95e6243fdb42017a6f65befef455987e4e","459b54e519f643aac8b4febc20ebce816f51299ea8b59ed881efdda46f97b8cf","e7c714f383b1811cb98ca9a4bfbe56587b66a01a34f16ebe31de50df891193d8","2ddf3f8f91a16e12931ade6fb05cc8e43a94866b11c6a9e18d0f65ea588ecd51","30361480085c950d0527fdebb2aa5e1aa90fe2f7343cbeeefd6047276a7b3ab0","8e0dd7a0d33cea2f1be2cbd59c69ed448edadc73e51dc939f50b0f6c84e7851f","e9b9536d31780948ef6e23cc12dea33c0f8b9dcecbaa5eb7239be46e7d7ed80e","fb65b8f1a477e93dceac67dd94cf4c0913b7f7971e91dcfd1ad739cb5a1cfcfc","bf3a54cc315d9dc1d7ddfec645176b01f3db35ddfdf3235d14a6ca7412e44e95","aa3975d48720a3e94e6e538465043f25fd5d54beeeb185a0712a1b1bd87806dc","22137120ac5aca616b37183abdc5a79664b22bb643b4be04a84f0a61e3c8653c","8a933e73735d254c8c86da88197db4ec8424ff32831b3c54a62bd21c8b7dc549","7755a8ed4934ec2d3897eb3457c3b751693ac111ca0d2a0d05474dd361ad7865","d87e8a1715675f01ad8046be1a87ea872c3f2f2bbe913cbaa64924cbee90e46d","f708be381ac72be1f5264588bfe45c1eb15cb167d5d0c9a3af64a42a1ae4bb6c","e1cbf6386abf84c7e3fe3506b5453d92792d31511578b91680bcef6ef772bb57","ba930236f8c2e606bee57ece25e83cbe1e9a49136e9e1fad0871c22d2ca60c47"},Font=true,Name="Fluent UI",SourceHash="aefd29a983af7e178aa22261a9dc424bd5dbfa19680d2dc163a46f34997796de",Sheets=13,License="MIT",Count=20334,FontParts=25},phosphor={Hash="3a5e9b8ed33e68efb30de3f96814cb55320b7d7579fa375e29cf2f9fcea4d371",FontSources={"e8c24227843917e3fc9290d8bf203705de7f4a59485d07f9401cea9d4fc3d1c9","616bc7cf12efd96cffe2ea91298d2a928e6e0a508a233ec887c97cbc9c4395bb","53f51b226944327ba01306717fe829cec5d638f4d1179b4f121af355330399d7","a4d996e7818c0514d1d1f5f068b33de5667c7c735b88414276686b29128cc829","a2c1f74720b1a04cb699b54cb3938fc81643bb7d036147753ea130ea70019bb4","32b4ec07d36dee3d04585246dbb3c82f3c178a1229cc6179827ca15fe3922776","e5c39571e65797199d631dd71df13f9ac935c784eb7f3c2abd8f3d0f58c2ff75"},Font=true,Count=9161,SourceHash="841b552595d27509a630dadd2bc5a04fc0b30e724e3b42f6f2807ef7628fd415",Sheets=6,License="MIT",Name="Phosphor",FontParts=7}}

local MAX_ALIAS_DEPTH = 8
local PRELOAD_WORKERS = 6

--// Providers \\--
type ProviderState = {
	Id: string,
	Icons: { string },
	Aliases: { [string]: string },
	Rects: { { any } },
	NoFont: { [string]: boolean },
	Index: { [string]: number },
	SheetUrls: { [number]: string },
	Folder: string,
	FontParts: number?,
	FontName: string,
	Fonts: { [number]: Font | false },
}

local loadedProviders: { [string]: ProviderState } = {}
local currentProvider = DEFAULT_PROVIDER

-- Keeps only the newest build of a provider on disk
local function PruneCache(id: string, currentFolder: string)
	if not AssetManager.CanDelete then return end

	for _, name in AssetManager.ListNames() do
		local hash = if name:sub(1, #id + 1) == `{id}-` then name:sub(#id + 2) else nil
		if hash and name ~= currentFolder and hash:match("^" .. string.rep("%x", 64) .. "$") then
			pcall(delfolder, AssetManager.Path(name))
		end
	end
end

local function LoadProvider(id: string): ProviderState
	local loaded = loadedProviders[id]
	if loaded then return loaded end

	local meta = PROVIDERS[id]
	assert(meta, `Unknown icon provider "{id}"`)

	local folder = `{id}-{meta.Hash}`
	local dataFile = `{folder}/data.lua`
	local dataUrl = `{ASSET_BASE_URL}providers/{id}.lua`

	local useCustomSprites = false
	local source: string? = nil

	if AssetManager.Supported then
		useCustomSprites = pcall(function()
			AssetManager.EnsureFolder(folder)
			for sheet = 1, meta.Sheets do
				AssetManager.Download(`{folder}/{sheet}.png`, `{ASSET_BASE_URL}spritesheets/{id}/{sheet}.png`, function(data)
					return data:sub(1, 8) == "\137PNG\r\n\26\n" -- PNG header
				end)
			end
			AssetManager.GetAsset(`{folder}/1.png`)
		end)

		pcall(function()
			AssetManager.EnsureFolder(folder)
			AssetManager.Download(dataFile, dataUrl, function(data)
				return data:sub(1, 6) == "return"
			end)
			source = AssetManager.Read(dataFile)
		end)

		if useCustomSprites then
			pcall(PruneCache, id, folder)
		end
	end

	local data = loadstring(source or game:HttpGet(dataUrl))()

	local sheetUrls = {}
	for sheet, fallback in data.Sheets do
		sheetUrls[sheet] = if useCustomSprites then AssetManager.GetAsset(`{folder}/{sheet}.png`) else fallback
	end

	local index = {}
	for position, name in data.Icons do
		index[name] = position
	end

	-- Icons with see-through layers cannot be drawn by a one color font, so they only exist as sprites
	local noFont = {}
	for _, name in data.NoFont or {} do
		noFont[name] = true
	end

	local state: ProviderState = {
		Id = id,
		Icons = data.Icons,
		Aliases = data.Aliases,
		Rects = data.Rects,
		NoFont = noFont,
		Index = index,
		SheetUrls = sheetUrls,
		Folder = folder,
		FontParts = if meta.Font then meta.FontParts else nil,
		FontName = meta.Name,
		Fonts = {},
	}

	loadedProviders[id] = state
	return state
end

-- Must match FontPartOf in scripts/build.luau
local function FontPartOf(name: string, parts: number): number
	local hash = 7
	for index = 1, #name do
		hash = (hash * 131 + string.byte(name, index)) % 2147483629
	end
	return hash % parts + 1
end

-- Roblox does not shape a ligature whose text starts with a digit, so the font stores those icons with a letter prefix.
-- Must match LigatureOf in scripts/build.luau
local function LigatureOf(name: string): string
	return if name:match("^%d") then `x-{name}` else name
end

-- Big sets are split into several fonts, so a font is downloaded when its first icon is looked up
local function GetFontFace(state: ProviderState, part: number): Font?
	local cached = state.Fonts[part]
	if cached ~= nil then return cached or nil end

	local face: Font? = nil
	if AssetManager.Supported then
		pcall(function()
			local ttfFile = `{state.Folder}/font-{part}.ttf`
			local familyFile = `{state.Folder}/font-{part}.json`

			AssetManager.EnsureFolder(state.Folder)
			AssetManager.Download(ttfFile, `{ASSET_BASE_URL}fonts/{state.Id}/{state.Id}-{part}.ttf`, function(data)
				return data:sub(1, 4) == "\0\1\0\0" -- TrueType header
			end)
			AssetManager.Write(familyFile, game:GetService("HttpService"):JSONEncode({
				name = `{state.FontName} {part}`,
				loadStrategy = "sameFamilyOnly",
				faces = {
					{ name = "Regular", weight = 400, style = "normal", assetId = AssetManager.GetAsset(ttfFile) },
				},
			}))

			face = Font.new(AssetManager.GetAsset(familyFile))
		end)
	end

	state.Fonts[part] = face or false
	return face
end

--// API \--
Registry.Providers = {}
for id in PROVIDERS do
	table.insert(Registry.Providers, id)
end
table.sort(Registry.Providers)

function Registry.GetProviderInfo(id: string?)
	local meta = PROVIDERS[id or currentProvider]
	if not meta then return nil end

	return { Id = id or currentProvider, Name = meta.Name, License = meta.License, Count = meta.Count }
end

function Registry.GetProvider(): string
	return currentProvider
end

function Registry.SetProvider(id: string)
	assert(PROVIDERS[id], `Unknown icon provider "{id}"`)

	LoadProvider(id)
	currentProvider = id
end

function Registry.GetIcons(provider: string?): { string }
	return LoadProvider(provider or currentProvider).Icons
end

function Registry.HasIcon(name: string, provider: string?): boolean
	return Registry.GetAsset(name, provider) ~= nil
end

local function Resolve(state: ProviderState, name: string): string
	local resolved = name
	for _ = 1, MAX_ALIAS_DEPTH do
		local target = state.Aliases[resolved]
		if not target then break end
		resolved = target
	end
	return resolved
end

-- Downloads everything up front so GetAsset never yields. Without names it fetches every font part of the provider.
-- Returns the number of font parts that are ready
function Registry.PreloadAsync(names: { string }?, provider: string?): number
	local state = LoadProvider(provider or currentProvider)
	if not state.FontParts then return 0 end

	local seen: { [number]: boolean } = {}
	local queue: { number } = {}
	local function Add(part: number)
		if not seen[part] then
			seen[part] = true
			table.insert(queue, part)
		end
	end

	if names then
		for _, name in names do
			local resolved = Resolve(state, name)
			if state.Index[resolved] and not state.NoFont[resolved] then
				Add(FontPartOf(resolved, state.FontParts))
			end
		end
	else
		for part = 1, state.FontParts do
			Add(part)
		end
	end

	local ready = 0
	local function Work()
		while true do
			local part = table.remove(queue)
			if not part then return end
			if GetFontFace(state, part) then
				ready += 1
			end
		end
	end

	-- Several parts download at once, the rest of the queue is picked up as workers finish
	local workers = math.min(PRELOAD_WORKERS, #queue)
	if typeof(task) ~= "table" or workers <= 1 then
		Work()
		return ready
	end

	local running = workers
	for _ = 1, workers do
		task.spawn(function()
			pcall(Work)
			running -= 1
		end)
	end
	while running > 0 do
		task.wait()
	end
	return ready
end

function Registry.GetAsset(name: string, provider: string?)
	local state = LoadProvider(provider or currentProvider)

	local resolved = Resolve(state, name)

	local position = state.Index[resolved]
	if not position then
		return nil
	end

	local rect = state.Rects[position]
	local fontPart = if state.FontParts and not state.NoFont[resolved] then FontPartOf(resolved, state.FontParts) else nil
	local fontFace = nil -- Altair uses Molto sprite assets exclusively.

	return {
		IconName = name,
		Provider = state.Id,
		Url = state.SheetUrls[rect[1]],
		ImageRectSize = Vector2.new(rect[2][1], rect[2][2]),
		ImageRectOffset = Vector2.new(rect[3][1], rect[3][2]),

		-- Only present when the provider font loaded. The font shapes Text into one icon through a ligature
		FontFace = fontFace,
		FontPart = fontPart,
		Text = if fontFace then LigatureOf(resolved) else nil,
	}
end

function Registry.SetIcon(iconInstance: TextLabel | ImageLabel, name: string, provider: string?)
	assert(typeof(iconInstance) == "Instance" and (iconInstance:IsA("TextLabel") or iconInstance:IsA("ImageLabel")), "iconInstance must be a TextLabel or ImageLabel")

	local asset = Registry.GetAsset(name, provider)
	assert(asset, `Icon "{name}" not found in provider "{provider}"`)

	if iconInstance:IsA("TextLabel") then
		assert(asset.FontFace, "Environment does not support font icons. Try using an ImageLabel instead.")

		iconInstance.Text = asset.Text
		iconInstance.FontFace = asset.FontFace
	else
		iconInstance.Image = asset.Url
		iconInstance.ImageRectSize = asset.ImageRectSize
		iconInstance.ImageRectOffset = asset.ImageRectOffset
	end
end

return Registry


end)()
local iconAssets={}
local iconSheets={}
local function applyIcon(object,name)
 local asset=iconAssets[name]
 if asset==nil then
  local ok,value=pcall(Molto.GetAsset,name,"lucide")
  asset=ok and value or false;iconAssets[name]=asset
 end
 if not asset then return false end
 iconSheets[asset.Url]=true
 object.Image=asset.Url;object.ImageRectSize=asset.ImageRectSize;object.ImageRectOffset=asset.ImageRectOffset
 object.ScaleType=Enum.ScaleType.Fit;object:SetAttribute("AltairIcon",name)
 return true
end
-- Official Phosphor Fill artwork; one embedded atlas, no runtime icon downloads.
local filledSmartBarPNG="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"
local filledSmartBarAsset
local function applyFilledSmartBar(root)
 local register=getcustomasset or getsynasset
 if not filledSmartBarAsset and type(register)=="function"and type(writefile)=="function"then
  local ok,result=pcall(function()
   local data=filledSmartBarPNG;local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local lookup={};for i=1,#alphabet do lookup[alphabet:byte(i)]=i-1 end
   local bytes={};for i=1,#data,4 do local a,b,c,d=data:byte(i,i+3);local n=(lookup[a]or 0)*262144+(lookup[b]or 0)*4096+(lookup[c]or 0)*64+(lookup[d]or 0);bytes[#bytes+1]=string.char(math.floor(n/65536)%256);if c~=61 then bytes[#bytes+1]=string.char(math.floor(n/256)%256)end;if d~=61 then bytes[#bytes+1]=string.char(n%256)end end
   if makefolder then for _,path in ipairs({"Altair","Altair/UI","Altair/UI/Assets"})do pcall(makefolder,path)end end
   local path="Altair/UI/Assets/SmartBar-Filled-1.png";if not isfile or not isfile(path)then writefile(path,table.concat(bytes))end;return register(path)
  end)
  if ok then filledSmartBarAsset=result;iconSheets[result]=true end
 end
 if not filledSmartBarAsset then return end
 for index,name in ipairs({"Home","Character","Scripts","Playerlist","Settings"})do
  local icon=root.SmartBar.Back.Buttons[name]:FindFirstChild("Icon")
  if icon and name~="Character"then icon.Image=filledSmartBarAsset;icon.ImageRectSize=Vector2.new(96,96);icon.ImageRectOffset=Vector2.new((index-1)*96,0);icon.ScaleType=Enum.ScaleType.Fit;icon:SetAttribute("AltairIcon","phosphor-filled-"..name);icon:SetAttribute("AltairFilledIcon",true)end
 end
end

local legacyIcons={
 ["4400696294"]="rotate-ccw",["92188766517878"]="shuffle",["138133190015277"]="log-in",
 ["9134761478"]="toggle-left",["14385986465"]="toggle-right",["9134787693"]="toggle-left",
 ["9134755504"]="plane",["14385992605"]="plane",["9134762943"]="rotate-ccw",
 ["9134765994"]="shield-check",["14386216487"]="shield",["9134785384"]="wind",["14386226155"]="wind",
 ["9134780101"]="scan-eye",["14386232387"]="scan-eye",["9134778004"]="moon",["10137794784"]="sun",
 ["9134774810"]="volume-x",["14386246782"]="volume-2",["14386256326"]="eye-off",["9134770786"]="eye",
 ["9080470458"]="person-standing",["3605509925"]="search",["9080449299"]="house",
 ["9080478424"]="code-xml",["9080475789"]="users-round",["3605022185"]="settings-2",
 ["4370336704"]="user-round",["3944668821"]="crosshair",["4335479121"]="navigation",
 ["10734943674"]="search",["10747373426"]="user-round-check",["10734966248"]="crown",
 ["10723346959"]="eye",["10734943902"]="navigation",["10709811834"]="contact-round",
 ["77891951053543"]="bell",["7733960981"]="house",["7743876054"]="users-round",
 ["7733734848"]="gamepad-2",["7733717755"]="chevron-right",["7733954760"]="globe",
 ["8997387546"]="activity",["10723367380"]="refresh-cw",["10723404337"]="library",
 ["10734924532"]="file-code-2",["10709782497"]="sparkles",["4370335364"]="user-round-plus",
 ["3944670656"]="shield-check"
}
local function refreshIcon(object)
 if not (object:IsA("ImageLabel") or object:IsA("ImageButton")) then return end
 local id=object.Image:match("^rbxassetid://(%d+)$")
 local name=id and legacyIcons[id]
 if id=="3926305904" then name=object.Name=="Back" and "arrow-left" or object.Name=="Toggle" and "chevron-down" or "x" end
 if name then applyIcon(object,name)
 elseif object:GetAttribute("AltairIcon") and not iconSheets[object.Image] then
  object.ImageRectSize=Vector2.zero;object.ImageRectOffset=Vector2.zero;object:SetAttribute("AltairIcon",nil)
 end
end

-- Scale independent top-level surfaces without scaling screen coordinates.
local function displayScale(viewport)
 return math.clamp(math.min(viewport.X/1600,viewport.Y/900),.8,2)
end
local function resizeInterface(root)
 local viewport=root.AbsoluteSize
 if viewport.X<=0 or viewport.Y<=0 then return end
 local chosen=tonumber(root:GetAttribute("AltairPreferredScale"))
 local factor=chosen and math.clamp(chosen,.65,2.5) or displayScale(viewport);root:SetAttribute("AltairDisplayScale",factor)
 for _,name in ipairs({"SmartBar","Drag","Character","Scripts","Playerlist","Settings","ScriptSearch","CustomScriptPrompt","GameDetection","ModeratorDetectionPrompt","Disconnected","SecurityPrompt","Toasts"}) do
  local panel=root:FindFirstChild(name)
  if panel and panel:IsA("GuiObject") then
   local scale=panel:FindFirstChild("AltairDisplayScale") or Instance.new("UIScale")
   scale.Name="AltairDisplayScale";scale.Scale=factor;scale.Parent=panel
  end
 end
 return factor
end

-- A single SmartBar shell reflows without rotating its text or button icons.
local function bindDock(root)
 local bar,drag=root.SmartBar,root.Drag
 local back=bar.Back;local buttons=back.Buttons;local clock=back.Time
 local layout=buttons:FindFirstChildOfClass("UIListLayout")
 local motion=motionService();local animations={};local view={mode=nil,vertical=false,generation=0}
 local base={backPosition=back.Position,backSize=back.Size,backAnchor=back.AnchorPoint,
  buttonsPosition=buttons.Position,buttonsSize=buttons.Size,buttonsAnchor=buttons.AnchorPoint,
  timePosition=clock.Position,timeSize=clock.Size,timeAnchor=clock.AnchorPoint,timeAlign=clock.TextXAlignment,
  ampmPosition=clock.AMPM.Position,ampmSize=clock.AMPM.Size,ampmAnchor=clock.AMPM.AnchorPoint,ampmAlign=clock.AMPM.TextXAlignment}
 local horizontal={};local names={"Home","Character","Scripts","Playerlist","Settings"}
 local function mirror(p)return UDim2.new(1-p.X.Scale,-p.X.Offset,p.Y.Scale,p.Y.Offset)end
 local function pixel(p,size)return Vector2.new(p.X.Scale*size.X+p.X.Offset,p.Y.Scale*size.Y+p.Y.Offset)end
 local function anchor(object,nextAnchor)
  local delta=nextAnchor-object.AnchorPoint
  object.Position+=UDim2.new(object.Size.X.Scale*delta.X,object.Size.X.Offset*delta.X,object.Size.Y.Scale*delta.Y,object.Size.Y.Offset*delta.Y)
  object.AnchorPoint=nextAnchor
 end
 local function set(object,goal,animate)
  local old=animations[object];if old then old:Cancel()end
  if animate then local t=motion:Create(object,TweenInfo.new(.32,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goal);animations[object]=t;t:Play()
  else for key,value in pairs(goal)do object[key]=value end end
 end
 -- Exact native layout fallback for a saved side dock before its first render.
 local items={};for i,o in ipairs(buttons:GetChildren())do if o:IsA("GuiObject")then items[#items+1]={object=o,index=i}end end
 table.sort(items,function(a,b)return a.object.LayoutOrder==b.object.LayoutOrder and a.index<b.index or a.object.LayoutOrder<b.object.LayoutOrder end)
 local total=0;local padding=layout and layout.Padding.Offset or 5
 for _,item in ipairs(items)do total+=item.object.Size.X.Offset end;total+=math.max(0,#items-1)*padding
 local cursor=(base.backSize.X.Offset-total)/2
 for _,item in ipairs(items)do local o=item.object;horizontal[o]=Vector2.new(cursor+o.Size.X.Offset*o.AnchorPoint.X,base.backSize.Y.Offset/2);cursor+=o.Size.X.Offset+padding end
 local scales={};for _,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then local scale=Instance.new("UIScale");scale.Name="DockTransitionScale";scale.Parent=o;scales[o]=scale end end
 function view:BarSize()return self.vertical and UDim2.fromOffset(60,300)or UDim2.fromOffset(300,60)end
 function view:DragSize(length,thickness)return self.vertical and UDim2.fromOffset(thickness,length)or UDim2.fromOffset(length,thickness)end
 function view:Mirror(mirrored,animate,force)
  if self.vertical then return end
  if self.mirrored==mirrored and not force then return end
  self.mirrored=mirrored;if self.morphActive then return end
  anchor(back,base.backAnchor);anchor(buttons,base.buttonsAnchor);anchor(clock,base.timeAnchor);anchor(clock.AMPM,base.ampmAnchor)
  clock.TextXAlignment=base.timeAlign;clock.AMPM.TextXAlignment=base.ampmAlign
  set(back,{Position=mirrored and mirror(base.backPosition)or base.backPosition,Size=base.backSize},animate)
  set(buttons,{Position=mirrored and mirror(base.buttonsPosition)or base.buttonsPosition,Size=base.buttonsSize},animate)
  set(clock,{Position=mirrored and mirror(base.timePosition)or base.timePosition,Size=base.timeSize},animate)
  set(clock.AMPM,{Position=base.ampmPosition,Size=base.ampmSize},animate)
 end
 function view:Apply(mode,animate)
  if self.mode==mode then return end
  local vertical=mode=="left"or mode=="right";local changed=self.vertical~=vertical;local initial=self.mode==nil
  self.mode=mode;root:SetAttribute("AltairDock",mode)
  if not changed and not initial then return end
  self.generation+=1;local generation=self.generation
  if self.progressTween then self.progressTween:Cancel()end
  if self.progressConnection then self.progressConnection:Disconnect();self.progressConnection=nil end
  if self.progress then self.progress:Destroy();self.progress=nil end
  for _,t in pairs(animations)do t:Cancel()end;table.clear(animations)
  local factor=root:GetAttribute("AltairDisplayScale")or 1
  if vertical and not self.vertical and layout and layout.Parent then
   for _,button in ipairs(buttons:GetChildren())do if button:IsA("GuiObject")and button.AbsoluteSize.X>0 then
    horizontal[button]=(button.AbsolutePosition-buttons.AbsolutePosition+button.AbsoluteSize*button.AnchorPoint)/factor
   end end
  end
  local rendered={}
  for _,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then rendered[o]=(o.AbsolutePosition+o.AbsoluteSize*o.AnchorPoint-bar.AbsolutePosition)/factor end end
  if layout then layout.Parent=nil end
  self.vertical=vertical;bar:SetAttribute("AltairVertical",vertical);drag:SetAttribute("AltairVertical",vertical)
  if initial and not vertical then if layout then layout.Parent=buttons end;return end
  local startSize=Vector2.new(bar.Size.X.Offset,bar.Size.Y.Offset)
  local targetSize=vertical and Vector2.new(60,300)or Vector2.new(300,60)
  local starts,targets={},{ }
  local targetBackSize=Vector2.new(base.backSize.X.Offset,base.backSize.Y.Offset)
  local targetBackAnchor=pixel(self.mirrored and mirror(base.backPosition)or base.backPosition,targetSize)
  local targetBackTop=targetBackAnchor-targetBackSize*base.backAnchor
  for o,point in pairs(rendered)do starts[o]=point end
  local startBackSize=back.AbsoluteSize/factor
  local startBackCenter=(back.AbsolutePosition+back.AbsoluteSize/2-bar.AbsolutePosition)/factor
  local startClock=(clock.AbsolutePosition+clock.AbsoluteSize*clock.AnchorPoint-bar.AbsolutePosition)/factor
  local startTimeSize=Vector2.new(clock.Size.X.Offset,clock.Size.Y.Offset)
  local startAMPM=pixel(clock.AMPM.Position,startTimeSize);local startAMPMSize=Vector2.new(clock.AMPM.Size.X.Offset,clock.AMPM.Size.Y.Offset)
  for i,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then targets[o]=vertical and Vector2.new(30,100+(i-1)*40)or targetBackTop+(horizontal[o]or Vector2.new(27+(i-1)*39,25))end end
  local endBackSize=vertical and Vector2.new(50,214)or targetBackSize
  local endBackCenter=vertical and Vector2.new(30,180)or targetBackTop+targetBackSize/2
  local targetClock=vertical and Vector2.new(30,28)or targetBackTop+pixel(self.mirrored and mirror(base.timePosition)or base.timePosition,targetBackSize)
  local targetTimeSize=vertical and Vector2.new(54,19)or Vector2.new(base.timeSize.X.Offset,base.timeSize.Y.Offset)
  local targetAMPM=vertical and Vector2.new(7,19)or pixel(base.ampmPosition,targetTimeSize)
  local targetAMPMSize=vertical and Vector2.new(40,11)or Vector2.new(base.ampmSize.X.Offset,base.ampmSize.Y.Offset)
  anchor(back,Vector2.new(.5,.5));anchor(buttons,Vector2.new(.5,.5));anchor(clock,Vector2.new(.5,.5));anchor(clock.AMPM,Vector2.zero)
  buttons.Position=UDim2.fromScale(.5,.5);buttons.Size=UDim2.fromScale(1,1)
  self.morphActive=true
  local function ease(t)t=math.clamp(t,0,1);return 1-(1-t)^3 end
  local function draw(t)
   local shrink=ease(t/.8);local expand=ease(math.max(0,t-.06)/.94)
   local size=Vector2.new(startSize.X+(targetSize.X-startSize.X)*(vertical and shrink or expand),startSize.Y+(targetSize.Y-startSize.Y)*(vertical and expand or shrink))
   bar.Size=UDim2.fromOffset(size.X,size.Y)
   local points={};local lo=Vector2.new(math.huge,math.huge);local hi=Vector2.new(-math.huge,-math.huge)
   local fan=ease(t/.9)
   for o,target in pairs(targets)do
    local source=starts[o];local from=Vector2.new(source.X/math.max(1,startSize.X),source.Y/math.max(1,startSize.Y));local to=Vector2.new(target.X/targetSize.X,target.Y/targetSize.Y)
    local normalized=from:Lerp(to,fan);local point=Vector2.new(math.clamp(normalized.X*size.X,24,math.max(24,size.X-24)),math.clamp(normalized.Y*size.Y,24,math.max(24,size.Y-24)))
    points[o]=point;lo=Vector2.new(math.min(lo.X,point.X),math.min(lo.Y,point.Y));hi=Vector2.new(math.max(hi.X,point.X),math.max(hi.Y,point.Y))
    scales[o].Scale=1-.14*math.sin(math.pi*t)
   end
   local fromSize=Vector2.new(startBackSize.X/math.max(1,startSize.X),startBackSize.Y/math.max(1,startSize.Y))
   local toSize=Vector2.new(endBackSize.X/targetSize.X,endBackSize.Y/targetSize.Y)
   local fromCenter=Vector2.new(startBackCenter.X/math.max(1,startSize.X),startBackCenter.Y/math.max(1,startSize.Y))
   local toCenter=Vector2.new(endBackCenter.X/targetSize.X,endBackCenter.Y/targetSize.Y)
   local proportion=fromSize:Lerp(toSize,fan);local center=fromCenter:Lerp(toCenter,fan)
   local rawSize=Vector2.new(proportion.X*size.X,proportion.Y*size.Y);local rawCenter=Vector2.new(center.X*size.X,center.Y*size.Y)
   local left=math.max(5,rawCenter.X-rawSize.X/2);local right=math.min(size.X-5,rawCenter.X+rawSize.X/2)
   local top=math.max(5,rawCenter.Y-rawSize.Y/2);local bottom=math.min(size.Y-5,rawCenter.Y+rawSize.Y/2)
   local backTop=Vector2.new(left,top);local backSize=Vector2.new(math.max(1,right-left),math.max(1,bottom-top));local backCenter=backTop+backSize/2
   back.Position=UDim2.fromOffset(backCenter.X,backCenter.Y);back.Size=UDim2.fromOffset(backSize.X,backSize.Y)
   for o,point in pairs(points)do local p=point-backTop;o.Position=UDim2.fromOffset(p.X,p.Y)end
   local normalized=Vector2.new(startClock.X/math.max(1,startSize.X),startClock.Y/math.max(1,startSize.Y)):Lerp(Vector2.new(targetClock.X/targetSize.X,targetClock.Y/targetSize.Y),fan)
   local cp=Vector2.new(normalized.X*size.X,normalized.Y*size.Y)-backTop
   clock.Position=UDim2.fromOffset(cp.X,cp.Y)
   local ts=startTimeSize:Lerp(targetTimeSize,fan);clock.Size=UDim2.fromOffset(ts.X,ts.Y)
   local ap=startAMPM:Lerp(targetAMPM,fan);local az=startAMPMSize:Lerp(targetAMPMSize,fan);clock.AMPM.Position=UDim2.fromOffset(ap.X,ap.Y);clock.AMPM.Size=UDim2.fromOffset(az.X,az.Y)
  end
  local function complete()
   if generation~=self.generation then return end
   draw(1);self.morphActive=false
   if not vertical then
    self:Mirror(self.mirrored==true,false,true)
    for o,position in pairs(horizontal)do if o.Parent then o.Position=UDim2.fromOffset(position.X,position.Y)end end
    if layout then layout.Parent=buttons end
   end
  end
  if animate and not root:GetAttribute("AltairReduceMotion")then
   local progress=Instance.new("NumberValue");self.progress=progress
   local connection=progress.Changed:Connect(draw);self.progressConnection=connection
   self.progressTween=motion:Create(progress,TweenInfo.new(.46,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=1})
   self.progressTween.Completed:Once(function(state)connection:Disconnect();if self.progressConnection==connection then self.progressConnection=nil end;if state==Enum.PlaybackState.Completed then complete()end;if self.progress==progress then self.progress=nil end;progress:Destroy()end)
   self.progressTween:Play()
  else complete()end
  set(drag,{Size=self:DragSize(150,20)},animate)
  local line=drag:FindFirstChild("Drag")
  if line then
   local oldVertical=line.Size.Y.Offset>line.Size.X.Offset
   local angle=(oldVertical and 90 or 0)+line.Rotation
   local length=math.max(line.Size.X.Offset,line.Size.Y.Offset)
   line.Size=self:DragSize(length,4)
   line.Rotation=animate and angle-(vertical and 90 or 0)or 0
   set(line,{Size=self:DragSize(100,4)},animate)
   if animate then local rotation=motion:Create(line,TweenInfo.new(.36,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Rotation=0});animations.HandleRotation=rotation;rotation:Play()end
  end
 end
 root.Destroying:Connect(function()for _,t in pairs(animations)do t:Cancel()end;if view.progressTween then view.progressTween:Cancel()end;if view.progressConnection then view.progressConnection:Disconnect()end;if view.progress then view.progress:Destroy()end;if layout and not layout.Parent then layout:Destroy()end end)
 return view
end

local function bindDragContrast(root)
 local line=root.Drag.Drag;local motion=motionService();local controller={elapsed=0,goal=nil}
 local stroke=Instance.new("UIStroke");stroke.Name="AdaptiveContrast";stroke.Color=Color3.fromRGB(14,15,18);stroke.Thickness=1;stroke.Transparency=.86;stroke:SetAttribute("AltairContrastOutline",true);stroke.Parent=line
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.IgnoreWater=false
 local function luminance(color)return .2126*color.R+.7152*color.G+.0722*color.B end
 function controller:Update(value)
  self.elapsed=0;value=math.clamp(value,0,1);self.luminance=value
  local strength=math.clamp((value-.42)/.35,0,1);local target=.86-strength*.62
  if self.goal and math.abs(self.goal-target)<.025 then return end;self.goal=target
  if self.animation then self.animation:Cancel()end
  self.animation=motion:Create(stroke,TweenInfo.new(.24,Enum.EasingStyle.Quint),{Transparency=target});self.animation:Play()
 end
 function controller:Sample()
  local camera=workspace.CurrentCamera;if not camera then return .3 end
  local player=game:GetService("Players").LocalPlayer;local exclude={camera};if player and player.Character then exclude[#exclude+1]=player.Character end;params.FilterDescendantsInstances=exclude
  local lighting=game:GetService("Lighting");local center=line.AbsolutePosition+line.AbsoluteSize/2
  local angle=(line.AbsoluteSize.Y>line.AbsoluteSize.X and math.pi/2 or 0)+math.rad(line.Rotation)
  local axis=Vector2.new(math.cos(angle),math.sin(angle))*18
  local ambient=(luminance(lighting.Ambient)+luminance(lighting.OutdoorAmbient))*.5
  local day=math.clamp((math.cos((lighting.ClockTime-12)*math.pi/12)+.2)/1.2,0,1)
  local total=0
  for _,offset in ipairs({-axis,Vector2.zero,axis})do
   local point=center+offset;local ray=camera:ViewportPointToRay(point.X,point.Y)
   local result=workspace:Raycast(ray.Origin,ray.Direction*2048,params);local value=.15+.7*day
   if result then
    local hit=result.Instance;local color
    if hit:IsA("BasePart")then color=hit.Color elseif hit:IsA("Terrain")then color=result.Material==Enum.Material.Water and workspace.Terrain.WaterColor or workspace.Terrain:GetMaterialColor(result.Material)end
    if color then value=luminance(color)*math.clamp(.35+lighting.Brightness*.18+ambient*.5,.35,1.4)end
   end
   total+=math.clamp(value,0,1)
  end
  return total/3
 end
 local connection=game:GetService("RunService").Heartbeat:Connect(function(dt)
  controller.elapsed+=dt
  if controller.elapsed<.35 or not root.Enabled or not root.Drag.Visible then return end
  controller.elapsed=0;local ok,value=pcall(controller.Sample,controller);if ok then controller:Update(value)end
 end)
 root.Destroying:Connect(function()connection:Disconnect();if controller.animation then controller.animation:Cancel()end end)
 return controller
end

-- Rayfield Gen2 adaptations. Copyright (c) 2026 Corridon Capital.
-- MPL-2.0: see THIRD_PARTY_NOTICES.md.
-- Upstream: https://github.com/SiriusSoftwareLtd/rayfield-gen2
local RayfieldOdometer=(function()
--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Odometer readout: a number as a row of per-digit reels. Each digit is a clipped
-- cell holding a strip of glyphs; changing it tweens the strip so the new digit
-- rolls up from the bottom and the old one leaves the top. Non-digit characters
-- (separators, %, prefix/suffix) are static cells.
--
-- Cells are variable width (each digit's natural advance) so it reads like normal
-- text, not a monospaced counter, and the width tweens with the roll. Reconciles
-- from the right so decimals/suffixes stay put as digits grow on the left. Cells are
-- pooled and reused (hidden, never destroyed) so window:Create owns their cleanup.

local variables={textService=game:GetService("TextService"),tweenService=game:GetService("TweenService")}
local TextService = variables.textService

local odometer = {}
odometer.__index = odometer

-- Two stacked copies of 0-9. A reel on digit d rests at strip Y = -d*H. Rolling up
-- moves to higher indices; rolling down first jumps to the second copy (same glyph)
-- so it can travel down without running past index 0.
local stripLength = 20

local function measure(font, size, text)
    local params = Instance.new("GetTextBoundsParams")
    params.Text = text
    params.Font = font
    params.Size = size
    params.Width = math.huge
    local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
    return if ok then bounds else Vector2.new(size * 0.6, size)
end

-- Digit advances are the same for every odometer of a given font+size, but
-- GetTextBoundsAsync yields, so measure the ten digits once per (font, size) and
-- cache. Later odometers reuse the result and never touch TextService again.
local metricsCache = {}
local function digitMetrics(font, size)
    -- Style is part of the key: italic and normal measure differently
    local key = tostring(font.Family)
        .. "|"
        .. tostring(font.Weight)
        .. "|"
        .. tostring(font.Style)
        .. "|"
        .. tostring(size)
    local cached = metricsCache[key]
    if cached then
        return cached
    end

    local advance, maxWidth = {}, 0
    for d = 0, 9 do
        local w = math.ceil(measure(font, size, tostring(d)).X)
        advance[d] = w
        if w > maxWidth then
            maxWidth = w
        end
    end
    cached = { advance = advance, maxWidth = maxWidth }
    metricsCache[key] = cached
    return cached
end

-- window   : owning Window (for :Create, theming + cleanup)
-- container: Frame the row lives in; the odometer lays its cells out inside it
-- opts     : { textSize, alignment (Enum.HorizontalAlignment), transparency, duration }
function odometer.new(window, container, opts)
    opts = opts or {}
    local self = setmetatable({
        window = window,
        container = container,
        textSize = opts.textSize or 16,
        transparency = opts.transparency or 1, -- current base text transparency
        duration = opts.duration or 0.55,
        slots = {}, -- [indexFromRight] = { reel = reelData?, static = label? }
        length = 0, -- how many slots are currently shown
    }, odometer)

    self.roll = TweenInfo.new(self.duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    -- Cells sit above the container so the digits never get hidden by it under Global
    -- ZIndexBehavior, wherever the container itself is stacked (floored at the old default).
    self.zIndex = math.max(container.ZIndex + 1, 6)

    -- Height tracks the text size (not the taller text-bounds height) so the readout
    -- keeps a plain-label footprint; neighbour digits sit one cell away, outside the clip.
    self.height = math.ceil(self.textSize)

    -- Natural advance per digit (includes side bearings), plus the widest: the
    -- scrolling strip uses the widest so no glyph clips mid-roll, while each clip
    -- cell uses its own digit's advance.
    local metrics = digitMetrics(window.theme.Font, self.textSize)
    self.advance = metrics.advance
    self.maxWidth = metrics.maxWidth

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = opts.alignment or Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 0),

        Parent = container,
    })

    return self
end

-- Lazily build (or fetch) the reel for a slot: a clipped cell + a fixed-width
-- strip of 20 themed digit labels, centred so the visible glyph sits in the
-- middle of the (variable-width) cell.
function odometer:_reel(index)
    local slot = self.slots[index]
    if slot.reel then
        return slot.reel
    end

    local cell = self.window:Create("Frame", {
        Name = "Reel",
        Size = UDim2.fromOffset(self.maxWidth, self.height),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = self.zIndex,

        Parent = self.container,
    })

    local strip = self.window:Create("Frame", {
        Size = UDim2.fromOffset(self.maxWidth, self.height),
        AnchorPoint = Vector2.new(0.5, 0), -- centred horizontally in the cell
        Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = self.zIndex,

        Parent = cell,
    })

    for i = 0, stripLength - 1 do
        self.window:Create("TextLabel", {
            Text = tostring(i % 10),
            Position = UDim2.fromOffset(0, i * self.height),
            Size = UDim2.fromOffset(self.maxWidth, self.height),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = self.textSize,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTransparency = self.transparency,
            ZIndex = self.zIndex,

            Parent = strip,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })
    end

    local reel = { cell = cell, strip = strip, digit = 0, target = 0, stripTween = nil, sizeTween = nil }
    slot.reel = reel
    return reel
end

-- Fetch/build the static (separator/letter) label for a slot. Statics hug their
-- own glyph width so separators/suffixes space naturally.
function odometer:_static(index)
    local slot = self.slots[index]
    if slot.static then
        return slot.static
    end

    local label = self.window:Create("TextLabel", {
        Name = "Static",
        Size = UDim2.fromOffset(0, self.height),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = self.textSize,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = self.transparency,
        ZIndex = self.zIndex,

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    slot.static = label
    return label
end

local function stopReel(reel)
    if reel.stripTween then
        reel.stripTween:Cancel()
        reel.stripTween = nil
    end
    if reel.sizeTween then
        reel.sizeTween:Cancel()
        reel.sizeTween = nil
    end
end

function odometer:_reelSnap(reel, digit)
    stopReel(reel)
    reel.cell.Size = UDim2.fromOffset(self.advance[digit], self.height)
    reel.strip.Position = UDim2.new(0.5, 0, 0, -digit * self.height)
    reel.digit = digit
    reel.target = digit
end

function odometer:_reelRoll(reel, digit, up)
    -- Finalise any in-flight roll so we start from a clean resting digit.
    if reel.stripTween or reel.sizeTween then
        self:_reelSnap(reel, reel.target)
    end

    local a = reel.digit
    if a == digit then
        return
    end

    local startIndex, targetIndex
    if up then
        startIndex = a
        targetIndex = a + (digit - a) % 10 -- 1..9 above, glyph at target = digit
    else
        startIndex = a + 10 -- jump to 2nd copy (same glyph) to travel downward
        targetIndex = startIndex - (a - digit) % 10
    end

    reel.strip.Position = UDim2.new(0.5, 0, 0, -startIndex * self.height)
    reel.target = digit

    -- Roll the strip vertically and reflow the cell to the new digit's width together.
    local stripTween = variables.tweenService:Create(reel.strip, self.roll, {
        Position = UDim2.new(0.5, 0, 0, -targetIndex * self.height),
    })
    local sizeTween = variables.tweenService:Create(reel.cell, self.roll, {
        Size = UDim2.fromOffset(self.advance[digit], self.height),
    })
    reel.stripTween = stripTween
    reel.sizeTween = sizeTween
    stripTween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and reel.stripTween == stripTween then
            self:_reelSnap(reel, digit)
        end
    end)
    stripTween:Play()
    sizeTween:Play()
    reel.digit = digit
end

-- Show a slot as a digit; hide its static twin. A cell coming back from hidden
-- (the number grew past this column earlier, e.g. 100 -> 99 -> 100) snaps rather
-- than rolling from whatever stale digit it last held.
function odometer:_putDigit(index, digit, up, animate)
    local reel = self:_reel(index)
    local wasHidden = not reel.cell.Visible
    reel.cell.Visible = true
    reel.cell.LayoutOrder = -index
    if self.slots[index].static then
        self.slots[index].static.Visible = false
    end
    if animate and not wasHidden then
        self:_reelRoll(reel, digit, up)
    else
        self:_reelSnap(reel, digit)
    end
end

-- Show a slot as a static char; hide its reel twin.
function odometer:_putStatic(index, char)
    local label = self:_static(index)
    if not label.Visible then
        -- reveal only fades visible statics, so a hidden cell may carry a stale level
        label.TextTransparency = self.transparency
    end
    label.Text = char
    label.Visible = true
    label.LayoutOrder = -index
    if self.slots[index].reel then
        self.slots[index].reel.cell.Visible = false
    end
end

function odometer:_hide(index)
    local slot = self.slots[index]
    if not slot then
        return
    end
    if slot.reel then
        slot.reel.cell.Visible = false
    end
    if slot.static then
        slot.static.Visible = false
    end
end

-- Core: render `text`, animating digit changes when `animate` and rolling in the
-- direction implied by `up` (value increased vs decreased).
function odometer:_render(text, animate, up)
    text = tostring(text)

    -- skip the reconcile when unchanged; snap() runs every drag frame
    if text == self._lastText then
        return
    end
    self._lastText = text

    -- Split into whole UTF-8 characters, not bytes: a suffix like "°" is two
    -- bytes and string.sub would tear it into invalid halves (rendered as tofu).
    local chars = {}
    for _, code in utf8.codes(text) do
        table.insert(chars, utf8.char(code))
    end

    local n = #chars
    for i = 0, math.max(n, self.length) - 1 do
        self.slots[i] = self.slots[i] or {}
        if i < n then
            local char = chars[n - i] -- reconcile from the right
            if char:match("%d") then
                self:_putDigit(i, tonumber(char), up, animate)
            else
                self:_putStatic(i, char)
            end
        else
            self:_hide(i)
        end
    end
    self.length = n
end

-- Roll to `text` (digits animate, direction from `up`).
function odometer:to(text, up)
    self:_render(text, true, up)
end

-- Set `text` instantly (no roll).
function odometer:snap(text)
    self:_render(text, false, true)
end

-- Fade every current label toward `target` transparency, and remember it so
-- lazily-created cells come in at the same level. Mirrors Window:_reveal.
function odometer:reveal(target, animate, info)
    self.transparency = target
    for _, slot in self.slots do
        if slot.static and slot.static.Visible then
            self.window:_reveal(slot.static, { TextTransparency = target }, animate, info)
        end
        if slot.reel then
            for _, lbl in slot.reel.strip:GetChildren() do
                if lbl:IsA("TextLabel") then
                    self.window:_reveal(lbl, { TextTransparency = target }, animate, info)
                end
            end
        end
    end
end

return odometer

end)()
local RayfieldStatistic=(function()
--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local Statistic = {}
Statistic.__index = Statistic
Statistic.__type = "Statistic"

-- Altair adapter: rendering, locale passthrough, and lifecycle belong to Build.lua.
local variables={tweenService=game:GetService("TweenService")}
local odometer=RayfieldOdometer
local functions={textWidth=function(_,size,text) return #text*size*.6 end}
local moveable=function() end
local locale={t=function(text)return text end,resolve=function(text)return text end}
local log={warn=warn}
local constants={statAccents={
 positive={fill=ColorSequence.new(Color3.fromRGB(0,170,127),Color3.fromRGB(0,134,98)),stroke=ColorSequence.new(Color3.fromRGB(0,213,156),Color3.fromRGB(0,189,135))},
 negative={fill=ColorSequence.new(Color3.fromRGB(172,47,47),Color3.fromRGB(135,37,37)),stroke=ColorSequence.new(Color3.fromRGB(255,75,75),Color3.fromRGB(244,67,67))},
 neutral={fill=ColorSequence.new(Color3.fromRGB(0,170,127),Color3.fromRGB(0,134,98)),stroke=ColorSequence.new(Color3.fromRGB(0,213,156),Color3.fromRGB(0,189,135))}}}

-- Accent gradients per direction (fill drives the card + glow, stroke is the brighter edge)
local accents = constants.statAccents

local accentTransparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.85),
    NumberSequenceKeypoint.new(1, 0),
})

local compactHeight = 41

local accentTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Exponential)

-- UIShadow glows take one colour, so the halo uses the brightest stop of the direction's fill.
local function glowColor(accent)
    return accent.fill.Keypoints[1].Value
end

local function formatPct(pct)
    if pct > 0 then
        return string.format("+%.1f%%", pct)
    elseif pct < 0 then
        return string.format("%.1f%%", pct)
    else
        return "0%"
    end
end

local function formatValue(value)
    if typeof(value) ~= "number" then
        return tostring(value)
    end
    -- round (matching formatChange) and format without exponent notation so huge
    -- values don't render as "1e+20"
    local rounded = math.round(math.abs(value))
    local s = string.format("%.0f", rounded)
    local result = s:reverse():gsub("%d%d%d", "%0,"):reverse()
    if result:sub(1, 1) == "," then
        result = result:sub(2)
    end
    -- no "-0": a negative that rounds to zero shows plain 0
    return if value < 0 and rounded ~= 0 then "-" .. result else result
end

local function formatChange(delta)
    -- sign follows the rounded value, so a delta that rounds to zero shows plain 0
    local rounded = math.round(delta)
    if rounded > 0 then
        return "+" .. formatValue(rounded)
    elseif rounded < 0 then
        return formatValue(rounded)
    else
        return "0"
    end
end

function Statistic.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Statistic",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,

        value = if (properties.value or properties.Value) ~= nil then (properties.value or properties.Value) else 0,
        -- did we start with a real value, or is the displayed number just a placeholder?
        -- the first Set on a placeholder establishes the baseline instead of showing a change
        _hasValue = (properties.value or properties.Value) ~= nil,

        numberEasing = if (properties.numberEasing ~= nil)
            then properties.numberEasing
            elseif properties.NumberEasing ~= nil then properties.NumberEasing
            else true,

        changeMode = properties.changeMode or properties.ChangeMode or "percentage", -- "percentage" | "absolute"
        changeBaseline = properties.changeBaseline or properties.ChangeBaseline or "previous",

        prefix = properties.prefix or properties.Prefix or "",
        suffix = properties.suffix or properties.Suffix or "",

        -- 41px single-readout card. config opt-in, forced on in a row. only room for
        -- one number, so `display` picks value or % change.
        compact = properties.compact or properties.Compact or tab.compact or false,
        display = (properties.display or properties.Display or "value"), -- "value" | "change"

        _initialValue = if (properties.value or properties.Value) ~= nil
            then (properties.value or properties.Value)
            else nil,
        _lastChange = 0,
    }, Statistic)

    if self.compact then
        self:_buildCompact()
    else
        self:_buildFull()
    end

    if self.description then
        if self.compact then
            log.warn(`Rayfield: a compact stat has no room for a description, ignoring it on '{self.name}'.`)
        else
            self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
        end
    end

    return self
end

-- full 90px card: title, value bottom-left, % change bottom-right
function Statistic:_buildFull()
    local window = self.window

    self.main = window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 90),
        BorderSizePixel = 0,
        Name = self.name,
        ZIndex = 5,

        BackgroundTransparency = 1,

        Parent = self.tab.tabPage,
    }, { BackgroundColor3 = "StatBackground", BackgroundTransparency = "ElementTransparency" })

    window:Create("UICorner", {
        Parent = self.main,
    }, { CornerRadius = "ElementCornerRadius" })

    self.stroke = window:Create("UIStroke", {
        Transparency = 1, -- Animation In = 0
        Color = Color3.fromRGB(255, 255, 255),

        Parent = self.main,
    }, { Transparency = "ElementStrokeTransparency" })

    self.strokeGradient = window:Create("UIGradient", {
        Rotation = 2,
        Offset = Vector2.new(0, 0.5),
        Color = accents.neutral.stroke,
        Transparency = accentTransparency,

        Parent = self.stroke,
    })

    self.titleContainer = window:Create("Frame", {
        Size = UDim2.new(1, -40, 0, 32),
        Position = UDim2.fromOffset(20, 15),
        BorderSizePixel = 0,
        LayoutOrder = -1,
        BackgroundTransparency = 1,
        ZIndex = 5,

        Parent = self.main,
    })

    self.gradientContainer = window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromOffset(0, 0),
        BorderSizePixel = 0,
        BackgroundTransparency = 1, -- In 0
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        ZIndex = 5,

        Parent = self.main,
    })

    -- Soft accent halo behind the card. UIShadow (no image) is our glow standard; its colour
    -- follows the stat direction and it reveals from hidden to 0.7 like the rest of the card.
    self.glow = window:CreateGlow(self.main, glowColor(accents.neutral), 13, 1)

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),

        Size = UDim2.fromOffset(300, 19),
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 19,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,
        ZIndex = 10,

        TextTransparency = 1, -- In = 0

        Parent = self.titleContainer,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    self.mainGradient = window:Create("UIGradient", {
        Rotation = 2,
        Offset = Vector2.new(0, 0.5),
        Color = accents.neutral.fill,
        Transparency = accentTransparency,

        Parent = self.gradientContainer,
    })

    window:Create("UICorner", {
        Parent = self.gradientContainer,
    }, { CornerRadius = "ElementCornerRadius" })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(32, 32),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 10,

            ImageTransparency = 1, -- In = 0

            Parent = self.titleContainer,
        }, { ImageColor3 = "ContentColor" })
    end

    self.containerLayout = window:Create("UIListLayout", {
        Padding = UDim.new(0, 8),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.titleContainer,
    })

    -- Value (bottom-left) + change (bottom-right) odometer readouts.
    self.valueHost = window:Create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 20, 1, -15),
        Size = UDim2.fromOffset(200, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,

        Parent = self.main,
    })

    self.changeHost = window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -15),
        Size = UDim2.fromOffset(200, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,

        Parent = self.main,
    })

    self.valueOdo = odometer.new(window, self.valueHost, {
        textSize = 20,
        alignment = Enum.HorizontalAlignment.Left,
        transparency = 1, -- revealed to 0 on show
    })
    self.valueOdo:snap(self:_formatValue(self.value))

    self.changeOdo = odometer.new(window, self.changeHost, {
        textSize = 15,
        alignment = Enum.HorizontalAlignment.Right,
        transparency = 1,
    })
    self.changeOdo:snap(self:_formatChange(0))

    self._accentGradients = { self.strokeGradient, self.mainGradient }
end

-- compact 41px card: icon+title left, one readout right. accent gradient sits on
-- the card (the flexed child), not a separate overlay
function Statistic:_buildCompact()
    local window = self.window

    -- in a row it's content-sized and flexes; standalone it's full-width, no flex item
    local inRow = self.tab.compact or false

    self.main = window:Create("Frame", {
        Name = self.name,
        Size = if inRow then UDim2.fromOffset(0, compactHeight) else UDim2.new(1, -20, 0, compactHeight),
        AutomaticSize = if inRow then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
        ClipsDescendants = true,
        BorderSizePixel = 0,
        ZIndex = 5,

        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundColor3 = "StatBackground", BackgroundTransparency = "ElementTransparency" })

    window:Create("UICorner", {
        Parent = self.main,
    }, { CornerRadius = "ElementCornerRadius" })

    self.stroke = window:Create("UIStroke", {
        Transparency = 1, -- In = ElementStrokeTransparency
        Color = Color3.fromRGB(255, 255, 255),

        Parent = self.main,
    }, { Transparency = "ElementStrokeTransparency" })

    self.strokeGradient = window:Create("UIGradient", {
        Rotation = 2,
        Offset = Vector2.new(0, 0.5),
        Color = accents.neutral.stroke,
        Transparency = accentTransparency,

        Parent = self.stroke,
    })

    if inRow then
        window:Create("UIFlexItem", {
            FlexMode = Enum.UIFlexMode.Fill,
            Parent = self.main,
        })
    end

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,

        Parent = self.main,
    })

    -- accent surface + content: white base + accent gradient, title left, readout right
    self.card = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, compactHeight),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 5,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })

    window:Create("UICorner", {
        Parent = self.card,
    }, { CornerRadius = "ElementCornerRadius" })

    self.mainGradient = window:Create("UIGradient", {
        Rotation = 2,
        Offset = Vector2.new(0, 0.5),
        Color = accents.neutral.fill,
        Transparency = accentTransparency,

        Parent = self.card,
    })

    window:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 15),
        PaddingRight = UDim.new(0, 15),

        Parent = self.card,
    })

    window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
        Padding = UDim.new(0, 10),

        Parent = self.card,
    })

    -- icon + title (left)
    self.titleContainer = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        ZIndex = 6,

        Parent = self.card,
    })

    -- title gives up room to the readout when tight
    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.titleContainer,
    })

    window:Create("UIListLayout", {
        Padding = UDim.new(0, 6),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.titleContainer,
    })

    if self.icon then
        self.iconLabel = window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(20, 20), -- smaller than the full 32
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            LayoutOrder = 0,
            ZIndex = 6,

            ImageTransparency = 1, -- In = 0

            Parent = self.titleContainer,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = 1,
        ZIndex = 6,

        TextTransparency = 1, -- In = 0

        Parent = self.titleContainer,
    }, { TextColor3 = "ContentColor", FontFace = "Font" }) -- Medium, like the other row elements

    -- grows to its text, shrinks + ellipsizes when tight
    window:Create("UIFlexItem", {
        FlexMode = Enum.UIFlexMode.Shrink,
        Parent = self.title,
    })

    -- single readout (right)
    self.readoutHost = window:Create("Frame", {
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 1,
        ZIndex = 6,

        Parent = self.card,
    })

    self.readoutOdo = odometer.new(window, self.readoutHost, {
        textSize = 17,
        alignment = Enum.HorizontalAlignment.Right,
        transparency = 1,
    })
    self.readoutOdo:snap(self.display == "change" and self:_formatChange(0) or self:_formatValue(self.value))

    self._accentGradients = { self.strokeGradient, self.mainGradient }
end

function Statistic:_setAccent(key, direction)
    local accent = accents[key]
    self.strokeGradient.Color = accent.stroke
    self.mainGradient.Color = accent.fill
    if self.glow then
        self.glow.Color = glowColor(accent)
    end

    -- Subtle rotation + offset shift to give the gradient a bit of life
    local rotation = if direction == 1 then 14 elseif direction == -1 then -10 else 2
    local offset = if direction == 1
        then Vector2.new(0.04, 0.5)
        elseif direction == -1 then Vector2.new(-0.04, 0.5)
        else Vector2.new(0, 0.5)
    for _, gradient in self._accentGradients do
        variables.tweenService:Create(gradient, accentTweenInfo, { Rotation = rotation, Offset = offset }):Play()
    end
end

function Statistic:_formatValue(value)
    return self.prefix .. formatValue(value) .. self.suffix
end

function Statistic:_formatChange(delta)
    if self.changeMode == "absolute" then
        return formatChange(delta)
    else
        return formatPct(delta)
    end
end

-- Put a value on a readout: rolls when number easing is on and there's a previous number to
-- roll from, snaps otherwise. Both card shapes and ResetBaseline go through here.
function Statistic:_showValue(odo, value, previousValue, hasNoHistory)
    if self.numberEasing and not hasNoHistory then
        odo:to(self:_formatValue(value), value >= previousValue)
    else
        odo:snap(self:_formatValue(value))
    end
end

-- full: roll value + change independently
function Statistic:_updateFullReadouts(value, previousValue, targetChange, noChange, infinityText, hasNoHistory)
    self:_showValue(self.valueOdo, value, previousValue, hasNoHistory)

    if infinityText then
        self.changeOdo:snap(infinityText)
        self._lastChange = 0
    elseif self.numberEasing and not noChange then
        self.changeOdo:to(self:_formatChange(targetChange), targetChange >= self._lastChange)
        self._lastChange = targetChange
    else
        self.changeOdo:snap(self:_formatChange(targetChange or 0))
        self._lastChange = targetChange or 0
    end
end

-- compact: roll the one readout
function Statistic:_updateCompactReadout(value, previousValue, targetChange, noChange, infinityText, hasNoHistory)
    if self.display == "change" then
        if infinityText then
            self.readoutOdo:snap(infinityText)
            self._lastChange = 0
        elseif self.numberEasing and not noChange then
            self.readoutOdo:to(self:_formatChange(targetChange), targetChange >= self._lastChange)
            self._lastChange = targetChange
        else
            self.readoutOdo:snap(self:_formatChange(targetChange or 0))
            self._lastChange = targetChange or 0
        end
    else -- "value"
        self:_showValue(self.readoutOdo, value, previousValue, hasNoHistory)
    end
end

function Statistic:Set(value)
    assert(typeof(value) == "number", "Statistic:Set() - value must be a number, got " .. typeof(value))

    local previousValue = self.value
    local hasNoHistory = not self._hasValue
    self.value = value
    self._hasValue = true

    if hasNoHistory then
        self._initialValue = value
    end

    local refValue = if self.changeBaseline == "initial" then self._initialValue else previousValue
    local noChange = hasNoHistory or refValue == value

    -- Determine target change, accent, and direction
    local targetChange, infinityText, accentKey, direction
    if noChange then
        targetChange = 0
        accentKey = "neutral"
        direction = 0
    elseif refValue == 0 then
        local sign = if value > 0 then "+" else "-"
        local suffix = if self.changeMode == "percentage" then "∞%" else "∞"
        infinityText = sign .. suffix
        accentKey = if value > 0 then "positive" else "negative"
        direction = if value > 0 then 1 else -1
    elseif self.changeMode == "percentage" then
        targetChange = ((value - refValue) / math.abs(refValue)) * 100
        direction = if targetChange > 0 then 1 elseif targetChange < 0 then -1 else 0
        accentKey = if direction == 1 then "positive" elseif direction == -1 then "negative" else "neutral"
    else
        targetChange = value - refValue
        direction = if targetChange > 0 then 1 elseif targetChange < 0 then -1 else 0
        accentKey = if direction == 1 then "positive" elseif direction == -1 then "negative" else "neutral"
    end

    self:_setAccent(accentKey, direction)

    if self.compact then
        self:_updateCompactReadout(value, previousValue, targetChange, noChange, infinityText, hasNoHistory)
    else
        self:_updateFullReadouts(value, previousValue, targetChange, noChange, infinityText, hasNoHistory)
    end
end

function Statistic:ResetBaseline(newBaseline)
    local previousValue = self.value
    local hasNoHistory = not self._hasValue
    local baseline = if typeof(newBaseline) == "number" then newBaseline else self.value
    self._initialValue = baseline
    self.value = baseline
    self._hasValue = true
    self._lastChange = 0

    -- change readout drops back to 0; the value readout follows the new baseline
    if self.compact then
        if self.display == "change" then
            self.readoutOdo:snap(self:_formatChange(0))
        else
            self:_showValue(self.readoutOdo, baseline, previousValue, hasNoHistory)
        end
    else
        self.changeOdo:snap(self:_formatChange(0))
        self:_showValue(self.valueOdo, baseline, previousValue, hasNoHistory)
    end

    self:_setAccent("neutral", 0)
end

function Statistic:_setShown(shown, animate)
    local w = self.window

    if self.compact then
        w:_reveal(
            self.main,
            { BackgroundTransparency = if shown then (self.window.theme.ElementTransparency or 0) else 1 },
            animate
        )
        w:_reveal(
            self.stroke,
            { Transparency = if shown then self.window.theme.ElementStrokeTransparency else 1 },
            animate
        )
        w:_reveal(self.card, { BackgroundTransparency = if shown then 0 else 1 }, animate)
        w:_reveal(self.title, { TextTransparency = if shown then 0 else 1 }, animate)
        if self.iconLabel then
            w:_reveal(self.iconLabel, { ImageTransparency = if shown then 0 else 1 }, animate)
        end
        self.readoutOdo:reveal(if shown then 0 else 1, animate)
        return
    end

    if shown then
        w:_revealCommon(self, animate)
        w:_reveal(self.gradientContainer, { BackgroundTransparency = 0 }, animate)
        w:_reveal(self.glow, { Transparency = 0.82 }, animate)
        self.valueOdo:reveal(0, animate)
        self.changeOdo:reveal(0, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.gradientContainer, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.glow, { Transparency = 1 }, animate)
        self.valueOdo:reveal(1, animate)
        self.changeOdo:reveal(1, animate)
    end
end

-- Room the compact card needs: padding + icon (and gap) if shown + title text + the gap
-- to the readout + the readout number itself. Lets a horizontal group wrap sensibly.
function Statistic:_minWidth()
    local w = 30 + 10 -- 15+15 card padding, 10 gap between title and readout
    if self.icon then
        w += 26 -- 20 icon + 6 gap
    end
    -- measure what actually renders: the title shows the translated string
    w += functions.textWidth(self.window.theme.Font, 16, locale.resolve(self.name))
    local readout = if self.display == "change" then self:_formatChange(0) else self:_formatValue(self.value)
    w += functions.textWidth(self.window.theme.Font, 17, readout)
    return w
end

moveable(Statistic)

return Statistic

end)()
local function rayfieldWindow(parent)
 local root=parent:FindFirstAncestorOfClass("ScreenGui")
 local service=motionService(function()return root and root:GetAttribute("AltairReduceMotion")==true end)
 local font=Font.new("rbxasset://fonts/families/GothamSSm.json")
 local window={theme={Font=font,TitleFont=font,ContentColor=Color3.fromRGB(245,245,247),StatBackground=Color3.fromRGB(19,21,24),ElementTransparency=.08,ElementStrokeTransparency=.65,ElementCornerRadius=UDim.new(0,12)}}
 function window:Create(class,properties,themes)
  local object=Instance.new(class)
  for key,value in pairs(properties)do object[key]=value end
  for key,name in pairs(themes or {})do if self.theme[name]~=nil then object[key]=self.theme[name] end end
  object:SetAttribute("AltairRayfieldVisual",true)
  if object:IsA("GuiObject")then object.ZIndex=((root and root:FindFirstChild("Settings") and root.Settings.ZIndex) or parent.ZIndex)+2+(properties.ZIndex or 1) end
  return object
 end
 function window:CreateGlow()return nil end
 function window:_reveal(object,goal,animate,info)
  if not object then return end
  if animate then service:Create(object,info or TweenInfo.new(.18),goal):Play() else for key,value in pairs(goal)do object[key]=value end end
 end
 function window:_revealCommon(card,animate)
  self:_reveal(card.main,{BackgroundTransparency=.08},animate);self:_reveal(card.stroke,{Transparency=.65},animate);self:_reveal(card.title,{TextTransparency=0},animate)
 end
 function window:_hideCommon(card,animate)
  self:_reveal(card.main,{BackgroundTransparency=1},animate);self:_reveal(card.stroke,{Transparency=1},animate);self:_reveal(card.title,{TextTransparency=1},animate)
 end
 return window
end
local RayfieldColorPicker=(function()
--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__type = "ColorPicker"

local variables={tweenService=motionService(function()return false end,true),userInputService=game:GetService("UserInputService"),guiService=game:GetService("GuiService"),runService=game:GetService("RunService")}
local functions={deriveFlagFromName=function(name)return name end}
local constants={icons={colorpicker="__AltairPalette"}}
local locale={t=function(value)return value end};local hapticEngine={click=function()end}
local moveable=function()end;local lockable=function()end
-- Full hue wheel top (red) to bottom (back to red) for the vertical hue bar.
local hueSequence = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
})

-- Layout. The card is one frame that grows from a header row into the full picker; every
-- offset below is measured from the card's own top-left, no inner padding frame.
local headerHeight = 41
local contentY = 52 -- picker controls start just under the header
local mapSize = Vector2.new(150, 120)
local hueX = 184 -- map left (20) + 150 + 14 gap
local hueWidth = 10
-- big gap so the two handles (which overhang their bars by ~6px each, more when held) never touch
local alphaX = 214 -- hue right (194) + 20 gap
local alphaWidth = 10
local rightX = 240 -- alpha right (224) + 16 gap: left edge of the wide preview/field column
local alphaFieldWidth = 62 -- the alpha % input, sits right of the hex field
local fieldGap = 8
-- below this element width the preview + fields cant sit beside the map/bars without getting
-- too narrow, so they reflow to a full-width row under the map (see _applyLayout)
local narrowWidth = 400

-- Per-mode geometry for the bits that move between layouts. map + hue + alpha stay top-left in
-- both. "open" rects are where the preview morphs to and where the hex + alpha fields sit;
-- "height" is the card's open height. The preview morphs between its closed pill and this rect.
local layoutSpec = {
    wide = {
        height = 190,
        previewPos = UDim2.new(1, -20, 0, contentY + 39),
        previewSize = UDim2.new(1, -(rightX + 20), 0, 78),
        hexPos = UDim2.new(0, rightX, 0, contentY + 90),
        hexSize = UDim2.new(1, -(rightX + 20 + alphaFieldWidth + fieldGap), 0, 30),
        alphaFieldPos = UDim2.new(1, -(20 + alphaFieldWidth), 0, contentY + 90),
        alphaFieldSize = UDim2.new(0, alphaFieldWidth, 0, 30),
    },
    narrow = {
        height = 296,
        previewPos = UDim2.new(1, -20, 0, contentY + mapSize.Y + 40),
        previewSize = UDim2.new(1, -40, 0, 56),
        hexPos = UDim2.new(0, 20, 0, contentY + mapSize.Y + 78),
        hexSize = UDim2.new(1, -(40 + alphaFieldWidth + fieldGap), 0, 30),
        alphaFieldPos = UDim2.new(1, -(20 + alphaFieldWidth), 0, contentY + mapSize.Y + 78),
        alphaFieldSize = UDim2.new(0, alphaFieldWidth, 0, 30),
    },
}

-- The preview is a single frame that morphs between the closed header pill and the mode's open
-- rect. AnchorPoint stays (1, 0.5) so only pos/size tween.
local previewClosedPos = UDim2.new(1, -16, 0, headerHeight / 2)
local previewClosedSize = UDim2.fromOffset(40, 22)

local openInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local followInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- short enough to track the mouse tightly, long enough that the cursor glides instead of
-- snapping. this is the "animated" feel a hard snap lost.
local dragInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local heldInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function clamp01(n)
    return math.clamp(n, 0, 1)
end

local function clampByte(n)
    return math.clamp(math.round(n), 0, 255)
end

-- named colours accepted by the smart field
local namedColors = {
    black = Color3.fromRGB(0, 0, 0),
    white = Color3.fromRGB(255, 255, 255),
    red = Color3.fromRGB(255, 0, 0),
    green = Color3.fromRGB(0, 255, 0),
    blue = Color3.fromRGB(0, 0, 255),
    yellow = Color3.fromRGB(255, 255, 0),
    cyan = Color3.fromRGB(0, 255, 255),
    magenta = Color3.fromRGB(255, 0, 255),
    orange = Color3.fromRGB(255, 165, 0),
    purple = Color3.fromRGB(128, 0, 128),
    pink = Color3.fromRGB(255, 105, 180),
    brown = Color3.fromRGB(139, 69, 19),
    gray = Color3.fromRGB(128, 128, 128),
    grey = Color3.fromRGB(128, 128, 128),
}

-- hsl -> Color3 (h/s/l all 0..1). hsv has a built-in, hsl doesnt.
local function hslToColor(h, s, l)
    if s <= 0 then
        return Color3.new(l, l, l)
    end
    local function hue2(p, q, t)
        t = t % 1
        if t < 1 / 6 then
            return p + (q - p) * 6 * t
        elseif t < 1 / 2 then
            return q
        elseif t < 2 / 3 then
            return p + (q - p) * (2 / 3 - t) * 6
        end
        return p
    end
    local q = if l < 0.5 then l * (1 + s) else l + s - l * s
    local p = 2 * l - q
    return Color3.new(hue2(p, q, h + 1 / 3), hue2(p, q, h), hue2(p, q, h - 1 / 3))
end

-- pull every number (ints or floats) out of a string, in order
local function numbersIn(s)
    local out = {}
    for n in s:gmatch("[%d%.]+") do
        table.insert(out, tonumber(n))
    end
    return out
end

-- Smart, forgiving colour parse. Handles hex (#fff, ffffff, 0xffffff), rgb (rgb(...),
-- "255,0,0", "255 0 0"), hsv/hsb, hsl, plain 0..1 float triplets, and named colours.
-- Returns a Color3 or nil.
local function parseColor(input)
    if typeof(input) ~= "string" then
        return nil
    end
    local s = (input:lower():match("^%s*(.-)%s*$")) or ""
    if s == "" then
        return nil
    end

    if namedColors[s] then
        return namedColors[s]
    end

    local model = s:match("^(%a+)")
    local nums = numbersIn(s)

    if (model == "hsv" or model == "hsb") and #nums >= 3 then
        local h = (nums[1] % 360) / 360
        local sat = if nums[2] > 1 then nums[2] / 100 else nums[2]
        local v = if nums[3] > 1 then nums[3] / 100 else nums[3]
        return Color3.fromHSV(h, clamp01(sat), clamp01(v))
    end

    if model == "hsl" and #nums >= 3 then
        local h = (nums[1] % 360) / 360
        local sat = if nums[2] > 1 then nums[2] / 100 else nums[2]
        local l = if nums[3] > 1 then nums[3] / 100 else nums[3]
        return hslToColor(h, clamp01(sat), clamp01(l))
    end

    if (model == "rgb" or model == "rgba") and #nums >= 3 then
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    -- hex: with or without # / 0x, 3 or 6 digits
    local hex = s:match("^#?(%x%x%x%x%x%x)$") or s:match("^#?(%x%x%x)$") or s:match("^0x(%x%x%x%x%x%x)$")
    if hex then
        local ok, color = pcall(Color3.fromHex, hex)
        if ok then
            return color
        end
    end

    -- bare triplet, no model word: 0..1 floats read as raw channels, otherwise 0..255
    if #nums >= 3 and not model then
        if nums[1] <= 1 and nums[2] <= 1 and nums[3] <= 1 then
            return Color3.new(clamp01(nums[1]), clamp01(nums[2]), clamp01(nums[3]))
        end
        return Color3.fromRGB(clampByte(nums[1]), clampByte(nums[2]), clampByte(nums[3]))
    end

    return nil
end

-- accept a Color3, or anything parseColor understands, or fall back to the given default
local function coerceColor(value, fallback)
    if typeof(value) == "Color3" then
        return value
    end
    if typeof(value) == "string" then
        return parseColor(value) or fallback
    end
    return fallback
end

function ColorPicker.new(tab, properties)
    properties = if typeof(properties) == "table" then properties else {}

    local self = setmetatable({
        tab = assert(tab, "Missing argument #1 (Tab expected)"),
        window = tab.window,
        name = properties.name or properties.Name or "Color Picker",
        icon = properties.icon or properties.Icon,
        description = properties.description or properties.Description,
        forgetState = properties.forgetState or properties.ForgetState or tab.forgetState,

        callback = properties.callback or properties.Callback or function() end,

        _isOpen = false,
    }, ColorPicker)

    self.value = coerceColor(
        properties.color or properties.Color or properties.value or properties.Value or properties.default,
        Color3.fromRGB(255, 255, 255)
    )

    -- hue is kept alongside sat/val so dragging into a grey (where hue is undefined) doesnt
    -- lose the colour you were on, same as the classic pickers
    self.hue, self.sat, self.val = self.value:ToHSV()

    -- alpha (0..1). the callback gets it as a second arg; opacity of the preview + alpha slider
    local a = properties.alpha or properties.Alpha
    self.alpha = if type(a) == "number" then clamp01(a) else 1

    self.flag = properties.flag
        or properties.Flag
        or (not self.forgetState and functions.deriveFlagFromName(self.name) or nil)
    self.window:_registerControl(self)

    -- One card that grows from the header row into the full picker. No clip: the controls
    -- below the header just sit fully transparent while collapsed, so nothing shows through.
    self.main = self.window:Create("Frame", {
        Size = UDim2.new(1, -20, 0, headerHeight),
        BorderSizePixel = 0,
        Name = self.name,
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 1, -- In = ElementTransparency

        Parent = self.tab.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })

    self.stroke = self.window:StyleElementBody(self.main)
    self.hoverOverlay = self.window:CreateHoverOverlay(self.main)

    self:_buildHeader()
    self:_buildPicker()

    self.window:ConnectFor(self, self.interact.MouseButton1Click, function()
        hapticEngine.click()
        if self._isOpen then
            self:_close()
        else
            self:_open()
        end
    end)

    -- Hover: brighten stroke + title + overlay, but not while open (the picker's the focus then)
    self.window:ConnectFor(self, self.main.MouseEnter, function()
        if self._isOpen or not self.window:_interactive() then
            return
        end
        local theme = self.window.theme
        variables.tweenService
            :Create(self.stroke, fadeInfo, {
                Transparency = theme.ElementStrokeHoverTransparency,
                Color = theme.ElementStrokeHover,
            })
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ElementTextHoverColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 0.97 }):Play()
    end)

    self.window:ConnectFor(self, self.main.MouseLeave, function()
        local theme = self.window.theme
        variables.tweenService
            :Create(
                self.stroke,
                fadeInfo,
                { Transparency = theme.ElementStrokeTransparency, Color = theme.ElementStroke }
            )
            :Play()
        variables.tweenService:Create(self.title, fadeInfo, { TextColor3 = theme.ContentColor }):Play()
        variables.tweenService:Create(self.hoverOverlay, fadeInfo, { BackgroundTransparency = 1 }):Play()
    end)

    if self.description then
        self.descriptor = require(script.Parent.descriptor).new(self.tab, { description = self.description })
    end

    -- establish the picker's hidden state once, from the single visibility list
    self:_applyPickerVisibility(false, false)
    self:_setControlsVisible(false) -- and keep the collapsed controls out of input entirely

    -- pick wide/narrow from the real width and keep it in sync as that width changes (the
    -- column resolves a frame after we build, and the window can be resized). Ignore the
    -- transient widths swept while the window animates/hides, same as the slider.
    self.window:ConnectFor(self, self.main:GetPropertyChangedSignal("AbsoluteSize"), function()
        -- hasShownOnce: the initial layout pass happens while the window is still hidden,
        -- and blocking it would freeze the width-0 layout mode (same fix as the slider)
        if self.window.animating or (self.window.hidden and self.window.hasShownOnce) then
            return
        end
        self:_applyLayout()
    end)
    self:_applyLayout()

    self:_render("instant")

    return self
end

-- Header row: icon + title on the left, the morphing colour preview on the right.
function ColorPicker:_buildHeader()
    self.container = self.window:Create("Frame", {
        Size = UDim2.new(0, 170, 0, 16),
        Position = UDim2.new(0, 20, 0, headerHeight / 2),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = self.main,
    })

    self.window:Create("UIListLayout", {
        Padding = UDim.new(0, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.container,
    })

    if self.icon then
        self.iconLabel = self.window:Create("ImageLabel", {
            Image = self.icon,
            Size = UDim2.fromOffset(16, 16),
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 5,

            ImageTransparency = 1, -- In = 0

            Parent = self.container,
        }, { ImageColor3 = "ContentColor" })
    end

    self.title = self.window:Create("TextLabel", {
        Text = locale.t(self.name),
        Size = UDim2.fromOffset(150, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BorderSizePixel = 0,
        BackgroundTransparency = 1,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
        ZIndex = 5,

        TextTransparency = 1, -- In = 0

        Parent = self.container,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- The colour preview. Starts as the header pill; on open it morphs (pos + size) into the
    -- big swatch. No stroke - it reads as pure colour.
    self.preview = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = previewClosedPos,
        Size = previewClosedSize,
        BackgroundColor3 = self.value,
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- In = 0

        Parent = self.main,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = self.preview,
    })

    -- Soft glow behind the preview, tinted to the colour. Its transparency tracks alpha
    -- (0.6 solid -> 1 fully clear). One shadow follows the preview through the mini<->full morph.
    self.previewShadow = self.window:CreateGlow(self.preview, self.value, 20, 1)

    -- Shown centred on the (open) preview once alpha reaches 0, since the swatch is fully clear
    -- then: an icon + "Invisible" so it doesnt just look empty.
    self.invisibleGroup = self.window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        Parent = self.preview,
    })

    self.window:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,

        Parent = self.invisibleGroup,
    })

    self.invisibleIcon = self.window:Create("ImageLabel", {
        Image = constants.icons.colorpicker,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,

        ImageTransparency = 1, -- fades in near alpha 0

        Parent = self.invisibleGroup,
    }, { ImageColor3 = "ContentColor" })

    self.invisibleText = self.window:Create("TextLabel", {
        Text = locale.t("Invisible"),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        LayoutOrder = 1,
        ZIndex = 5,

        TextTransparency = 1, -- fades in near alpha 0

        Parent = self.invisibleGroup,
    }, { TextColor3 = "ContentColor", FontFace = "Font" })

    -- Covers only the header, so drags on the map/hue below dont toggle the card.
    self.interact = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, headerHeight),
        Position = UDim2.fromScale(0, 0),
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,
        AutoButtonColor = false,
        ZIndex = 10,

        Parent = self.main,
    })
end

-- Sat/val field, built from gradients (no image asset): a hue-tinted Frame with a white
-- left->right saturation gradient and a black top->bottom value gradient layered on top. Each
-- layer rounds its own corners so nothing needs clipping (which would clip the cursor).
function ColorPicker:_buildMap()
    self.map = self.window:Create("Frame", {
        Position = UDim2.fromOffset(20, contentY),
        Size = UDim2.fromOffset(mapSize.X, mapSize.Y),
        BackgroundColor3 = Color3.fromHSV(self.hue, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.main,
    })

    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.map })

    self.mapStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- Open = 0.9

        Parent = self.map,
    })

    -- saturation: white on the left, fading to the bare hue on the right
    self.satOverlay = self.window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 3,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.map,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.satOverlay })
    self.window:Create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = self.satOverlay,
    })

    -- value: transparent at the top, fading to black at the bottom
    self.valOverlay = self.window:Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 4,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.map,
    })
    self.window:Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.valOverlay })
    self.window:Create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = self.valOverlay,
    })
end

-- The picker guts: sat/val map, hue bar and an editable hex field, all sitting under the
-- header. They're fully transparent while collapsed and fade in on open.
function ColorPicker:_buildPicker()
    self:_buildMap()

    self.satCursor = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 6,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.map,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.satCursor,
    })

    self.satCursorStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,
        Transparency = 1, -- Open = 0 (solid white)

        Parent = self.satCursor,
    })

    self.mapInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        TextTransparency = 1,
        AutoButtonColor = false,
        ZIndex = 7,

        Parent = self.map,
    })

    -- Hue bar: vertical spectrum with a round handle tracking self.hue.
    self.hueBar = self.window:Create("Frame", {
        Position = UDim2.fromOffset(hueX, contentY),
        Size = UDim2.fromOffset(hueWidth, mapSize.Y),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.main,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.hueBar,
    })

    self.window:Create("UIGradient", {
        Color = hueSequence,
        Rotation = 90,

        Parent = self.hueBar,
    })

    self.hueHandle = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(hueWidth + 8, 8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 4,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.hueBar,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.hueHandle,
    })

    self.hueHandleStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,
        Transparency = 1, -- Open = 0 (solid white)

        Parent = self.hueHandle,
    })

    self.hueInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        -- pad the hit area sideways so the thin bar is easy to grab
        Size = UDim2.new(1, 16, 1, 8),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Text = "",
        TextTransparency = 1,
        AutoButtonColor = false,
        ZIndex = 6,

        Parent = self.hueBar,
    })

    -- Alpha bar: the colour fading top(opaque)->bottom(transparent). The bar's own transparency
    -- gradient does the fade (0 at top -> 1 at bottom), so the card shows through as it clears.
    -- The round handle tracks self.alpha.
    self.alphaBar = self.window:Create("Frame", {
        Position = UDim2.fromOffset(alphaX, contentY),
        Size = UDim2.fromOffset(alphaWidth, mapSize.Y),
        BackgroundColor3 = self.value,
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0 (then the gradient fades it down its length)

        Parent = self.main,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.alphaBar,
    })

    self.alphaGradient = self.window:Create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = self.alphaBar,
    })

    self.alphaHandle = self.window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(alphaWidth + 8, 8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 4,

        BackgroundTransparency = 1, -- Open = 0

        Parent = self.alphaBar,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(1, 0),
        Parent = self.alphaHandle,
    })

    self.alphaHandleStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,
        Transparency = 1, -- Open = 0 (solid white)

        Parent = self.alphaHandle,
    })

    self.alphaInteract = self.window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 16, 1, 8),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Text = "",
        TextTransparency = 1,
        AutoButtonColor = false,
        ZIndex = 6,

        Parent = self.alphaBar,
    })

    -- Hex field under the big preview.
    self.hexBox = self.window:Create("Frame", {
        Position = UDim2.new(0, rightX, 0, contentY + 90),
        Size = UDim2.new(1, -(rightX + 20), 0, 30),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.9

        Parent = self.main,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = self.hexBox,
    })

    self.hexBoxStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- Open = 0.85

        Parent = self.hexBox,
    })

    self.hexInput = self.window:Create("TextBox", {
        Text = "#" .. self.value:ToHex():upper(),
        PlaceholderText = locale.t("Smart Input"),
        Size = UDim2.new(1, -14, 1, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false,
        ZIndex = 3,

        TextTransparency = 1, -- Open = 0.4

        Parent = self.hexBox,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    -- Alpha % field, sits right of the hex field. Same styling as hexBox.
    self.alphaBox = self.window:Create("Frame", {
        Position = UDim2.new(0, rightX, 0, contentY + 90),
        Size = UDim2.fromOffset(alphaFieldWidth, 30),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        ZIndex = 2,

        BackgroundTransparency = 1, -- Open = 0.9

        Parent = self.main,
    })

    self.window:Create("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = self.alphaBox,
    })

    self.alphaBoxStroke = self.window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 1, -- Open = 0.85

        Parent = self.alphaBox,
    })

    self.alphaInput = self.window:Create("TextBox", {
        Text = tostring(math.round(self.alpha * 100)) .. "%",
        PlaceholderText = "100%",
        Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false,
        ZIndex = 3,

        TextTransparency = 1, -- Open = 0.4

        Parent = self.alphaBox,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })

    self.window:ConnectFor(self, self.mapInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("sat", input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    self.window:ConnectFor(self, self.hueInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("hue", input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    self.window:ConnectFor(self, self.alphaInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("alpha", input.UserInputType == Enum.UserInputType.MouseButton1)
        end
    end)

    self.window:ConnectFor(self, variables.userInputService.InputEnded, function(input)
        if
            (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
            and self._drag
        then
            self:_endDrag()
        end
    end)

    -- commit the field on enter/click-away, parsing whatever format they typed. anything
    -- unrecognised just snaps back to the current colour.
    self.window:ConnectFor(self, self.hexInput.FocusLost, function()
        local color = parseColor(self.hexInput.Text)
        if color then
            self:Set(color)
        else
            self.hexInput.Text = "#" .. self.value:ToHex():upper()
        end
    end)

    -- alpha field: take the first number as a percent, clamp 0..100, else snap back
    self.window:ConnectFor(self, self.alphaInput.FocusLost, function()
        local n = tonumber((self.alphaInput.Text:gsub("[^%d%.]", "")))
        if n then
            self:SetAlpha(clamp01(n / 100))
        else
            self.alphaInput.Text = tostring(math.round(self.alpha * 100)) .. "%"
        end
    end)
end

-- start following the mouse for the given region ("sat" or "hue"). Mirrors the slider: one
-- RenderStepped loop that self-terminates if the window unloads mid-drag. For a mouse drag
-- it also bails the moment the button is up, so a dropped InputEnded cant leave it running.
function ColorPicker:_beginDrag(region, isMouse)
    -- the interacts stay visible through the close fade, so a click landing in that window
    -- would drag a picker thats already shut
    if not self._isOpen then
        return
    end
    self._drag = region
    self._dragIsMouse = isMouse
    self:_setHeld(region)
    self:_pump()

    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    self._dragConnection = variables.runService.RenderStepped:Connect(function()
        local mouseReleased = self._dragIsMouse
            and not variables.userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if self.window.unloaded or not self._drag or mouseReleased then
            if mouseReleased then
                self:_endDrag()
                return
            end
            if self._dragConnection then
                self._dragConnection:Disconnect()
                self._dragConnection = nil
            end
            return
        end
        self:_pump()
    end)
end

function ColorPicker:_endDrag()
    self._drag = nil
    self:_setHeld(nil)
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    self.window:_siaUsed(self, "set")
    self.window:_persist(self)
end

-- grow only the grabbed control a touch while dragging, so it reads as a press (same idea as
-- the slider handle swelling when held). region is "sat"/"hue"/"alpha" while held, nil on release.
function ColorPicker:_setHeld(region)
    local satSize = if region == "sat" then UDim2.fromOffset(16, 16) else UDim2.fromOffset(12, 12)
    local hueSize = if region == "hue" then UDim2.fromOffset(hueWidth + 12, 10) else UDim2.fromOffset(hueWidth + 8, 8)
    local alphaSize = if region == "alpha"
        then UDim2.fromOffset(alphaWidth + 12, 10)
        else UDim2.fromOffset(alphaWidth + 8, 8)
    variables.tweenService:Create(self.satCursor, heldInfo, { Size = satSize }):Play()
    variables.tweenService:Create(self.hueHandle, heldInfo, { Size = hueSize }):Play()
    variables.tweenService:Create(self.alphaHandle, heldInfo, { Size = alphaSize }):Play()
end

-- Mouse in AbsolutePosition space. GetMouseLocation() sits one gui-inset below where
-- AbsolutePosition measures from (verified in play: GetGuiObjectsAtPosition lines up with
-- AbsolutePosition, and GetMouseLocation is +inset.Y off it), so subtract the inset. Only Y
-- matters here since the inset is vertical, but subtract both to be safe.
function ColorPicker:_mouseLocation()
    local mouse = variables.userInputService:GetMouseLocation()
    local screenGui = self.window.screenGui
    if screenGui and screenGui.IgnoreGuiInset then
        return mouse - variables.guiService:GetGuiInset()
    end
    return mouse
end

-- read the mouse for the active region, update the stored channels and repaint
function ColorPicker:_pump()
    -- the branches below mutate these in place
    local prevHue, prevSat, prevVal, prevAlpha = self.hue, self.sat, self.val, self.alpha

    if self._drag == "sat" then
        local size = self.map.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end
        local mouse = self:_mouseLocation()
        self.sat = clamp01((mouse.X - self.map.AbsolutePosition.X) / size.X)
        self.val = 1 - clamp01((mouse.Y - self.map.AbsolutePosition.Y) / size.Y)
    elseif self._drag == "hue" then
        local height = self.hueBar.AbsoluteSize.Y
        if height <= 0 then
            return
        end
        local mouse = self:_mouseLocation()
        self.hue = clamp01((mouse.Y - self.hueBar.AbsolutePosition.Y) / height)
    elseif self._drag == "alpha" then
        local height = self.alphaBar.AbsoluteSize.Y
        if height <= 0 then
            return
        end
        local mouse = self:_mouseLocation()
        -- top of the bar is fully opaque (alpha 1), bottom is clear (alpha 0)
        self.alpha = 1 - clamp01((mouse.Y - self.alphaBar.AbsolutePosition.Y) / height)
    else
        return
    end

    -- held but stationary: nothing moved, so dont re-render and hammer the callback every frame.
    -- compare the channels, not the colour they make: at val 0 (or sat 0) every hue is the same
    -- black, so a colour check would freeze the handles for the whole drag.
    if self.hue == prevHue and self.sat == prevSat and self.val == prevVal and self.alpha == prevAlpha then
        return
    end

    self.value = Color3.fromHSV(self.hue, self.sat, self.val)
    self:_render("drag")
    self:_fireCallback()
end

-- paint every surface from the current hue/sat/val/alpha.
-- mode "instant": everything snaps (initial build / Set while collapsed).
-- mode "drag":    map tint + cursors glide on a short tween so they track the mouse smoothly.
-- mode "animate": everything eases on the slower tween (a discrete Set while the picker's open).
-- Cursors/handles are tinted to the colour under them; the preview shows the colour at its alpha.
function ColorPicker:_render(mode)
    local mapHue = Color3.fromHSV(self.hue, 1, 1)
    local satPos = UDim2.new(self.sat, 0, 1 - self.val, 0)
    local huePos = UDim2.new(0.5, 0, self.hue, 0)
    local alphaPos = UDim2.new(0.5, 0, 1 - self.alpha, 0)
    local previewT = 1 - self.alpha -- preview opacity tracks alpha
    local shadowT = 1 - 0.4 * self.alpha -- 0.6 (solid) at full alpha -> 1 (gone) at zero alpha

    if mode == "instant" then
        self.map.BackgroundColor3 = mapHue
        self.satCursor.Position, self.satCursor.BackgroundColor3 = satPos, self.value
        self.hueHandle.Position, self.hueHandle.BackgroundColor3 = huePos, mapHue
        self.alphaBar.BackgroundColor3 = self.value
        self.alphaHandle.Position, self.alphaHandle.BackgroundColor3 = alphaPos, self.value
        self.preview.BackgroundColor3 = self.value
        self.previewShadow.Color = self.value
        if not self.window.hidden then
            self.preview.BackgroundTransparency = previewT
            self.previewShadow.Transparency = shadowT
        end
    else
        local moveInfo = if mode == "drag" then dragInfo else followInfo
        variables.tweenService:Create(self.map, moveInfo, { BackgroundColor3 = mapHue }):Play()
        variables.tweenService
            :Create(self.satCursor, moveInfo, { Position = satPos, BackgroundColor3 = self.value })
            :Play()
        variables.tweenService:Create(self.hueHandle, moveInfo, { Position = huePos, BackgroundColor3 = mapHue }):Play()
        variables.tweenService
            :Create(self.alphaHandle, moveInfo, { Position = alphaPos, BackgroundColor3 = self.value })
            :Play()
        -- the preview + its glow morph colour and opacity together on the softer follow tween
        variables.tweenService:Create(self.alphaBar, followInfo, { BackgroundColor3 = self.value }):Play()
        local previewGoal = { BackgroundColor3 = self.value }
        local shadowGoal = { Color = self.value }
        if not self.window.hidden then
            previewGoal.BackgroundTransparency = previewT
            shadowGoal.Transparency = shadowT
        end
        variables.tweenService:Create(self.preview, followInfo, previewGoal):Play()
        variables.tweenService:Create(self.previewShadow, followInfo, shadowGoal):Play()
    end

    -- dont fight the user while they're typing in a field
    if not self.hexInput:IsFocused() then
        self.hexInput.Text = "#" .. self.value:ToHex():upper()
    end
    if not self.alphaInput:IsFocused() then
        self.alphaInput.Text = tostring(math.round(self.alpha * 100)) .. "%"
    end

    self:_renderInvisible(mode ~= "instant")
end

-- Fade the "Invisible" overlay in as alpha nears 0 (only on the open preview - it wouldnt fit
-- the header pill). Fully in at alpha 0, gone by ~12% alpha.
function ColorPicker:_renderInvisible(animate)
    local inv = 0
    if self._isOpen and not self.window.hidden then
        inv = clamp01((0.12 - self.alpha) / 0.12)
    end
    local t = 1 - inv
    if animate then
        variables.tweenService:Create(self.invisibleIcon, fadeInfo, { ImageTransparency = t }):Play()
        variables.tweenService:Create(self.invisibleText, fadeInfo, { TextTransparency = t }):Play()
    else
        self.invisibleIcon.ImageTransparency = t
        self.invisibleText.TextTransparency = t
    end
end

function ColorPicker:_fireCallback()
    self.window:_runGuarded(self, self.callback, self.value, self.alpha)
end

function ColorPicker:_open()
    if self._isOpen then
        return
    end
    self._isOpen = true
    self:_setControlsVisible(true) -- back into input before they fade in

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
    end
    self._outsideClickConn = self.window:Connect(variables.userInputService.InputBegan, function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end
        local pos = input.Position
        local mainPos = self.main.AbsolutePosition
        local mainSize = self.main.AbsoluteSize
        if
            pos.X < mainPos.X
            or pos.X > mainPos.X + mainSize.X
            or pos.Y < mainPos.Y
            or pos.Y > mainPos.Y + mainSize.Y
        then
            self:_close()
        end
    end)

    variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
    -- the header pill morphs out into the big swatch as the card grows
    variables.tweenService
        :Create(self.preview, openInfo, { Position = self._previewOpenPos, Size = self._previewOpenSize })
        :Play()
    self:_applyPickerVisibility(true, true)
    self:_renderInvisible(true)
end

function ColorPicker:_close()
    if not self._isOpen then
        return
    end
    self._isOpen = false

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end

    -- a drag in progress shouldnt keep running once the picker is gone
    if self._drag then
        self:_endDrag()
    end
    if self.hexInput:IsFocused() then
        self.hexInput:ReleaseFocus()
    end
    if self.alphaInput:IsFocused() then
        self.alphaInput:ReleaseFocus()
    end

    self:_applyPickerVisibility(false, true)
    self:_renderInvisible(true)
    variables.tweenService
        :Create(self.preview, openInfo, { Position = previewClosedPos, Size = previewClosedSize })
        :Play()
    variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, headerHeight) }):Play()

    -- once the controls have faded, drop them out of input so a transparent field below the
    -- collapsed header cant grab the cursor
    task.delay(fadeInfo.Time, function()
        if not self._isOpen then
            self:_setControlsVisible(false)
        end
    end)
end

-- One source of truth for the picker controls' shown/hidden transparencies. Used both to hide
-- them instantly at build and to fade them on open/close, so every control is listed in exactly
-- one place - adding one cant re-introduce the bleed-through we'd get from a stray opaque fill
-- (there's no clip). The card height + preview morph animate separately.
function ColorPicker:_applyPickerVisibility(open, animate)
    local set = {
        [self.map] = { BackgroundTransparency = if open then 0 else 1 },
        [self.satOverlay] = { BackgroundTransparency = if open then 0 else 1 },
        [self.valOverlay] = { BackgroundTransparency = if open then 0 else 1 },
        [self.mapStroke] = { Transparency = if open then 0.9 else 1 },
        [self.satCursor] = { BackgroundTransparency = if open then 0 else 1 },
        [self.satCursorStroke] = { Transparency = if open then 0 else 1 },
        [self.hueBar] = { BackgroundTransparency = if open then 0 else 1 },
        [self.hueHandle] = { BackgroundTransparency = if open then 0 else 1 },
        [self.hueHandleStroke] = { Transparency = if open then 0 else 1 },
        [self.alphaBar] = { BackgroundTransparency = if open then 0 else 1 },
        [self.alphaHandle] = { BackgroundTransparency = if open then 0 else 1 },
        [self.alphaHandleStroke] = { Transparency = if open then 0 else 1 },
        [self.hexBox] = { BackgroundTransparency = if open then 0.9 else 1 },
        [self.hexBoxStroke] = { Transparency = if open then 0.85 else 1 },
        [self.hexInput] = { TextTransparency = if open then 0.4 else 1 },
        [self.alphaBox] = { BackgroundTransparency = if open then 0.9 else 1 },
        [self.alphaBoxStroke] = { Transparency = if open then 0.85 else 1 },
        [self.alphaInput] = { TextTransparency = if open then 0.4 else 1 },
    }

    for instance, props in set do
        if animate then
            variables.tweenService:Create(instance, fadeInfo, props):Play()
        else
            for prop, value in props do
                instance[prop] = value
            end
        end
    end
end

-- The picker controls sit below the header even while collapsed (the card doesnt clip), so a
-- transparent TextBox or button down there would still catch the cursor and clicks. Toggling the
-- top control frames off drops the whole cluster out of input when closed. The preview pill is
-- separate, so it stays.
function ColorPicker:_setControlsVisible(visible)
    for _, frame in { self.map, self.hueBar, self.alphaBar, self.hexBox, self.alphaBox } do
        frame.Visible = visible
    end
end

-- Pick side-by-side (wide) vs stacked (narrow) from the real width and apply the mode's
-- geometry. map + hue stay top-left in both; only the preview's open rect, the hex field and
-- the open height change. Re-tweens live if the mode flips while open.
function ColorPicker:_applyLayout()
    local width = self.main.AbsoluteSize.X
    local mode = if width > 0 and width < narrowWidth then "narrow" else "wide"
    if mode == self._layoutMode then
        return
    end
    self._layoutMode = mode

    local l = layoutSpec[mode]
    self._openHeight = l.height
    self._previewOpenPos = l.previewPos
    self._previewOpenSize = l.previewSize
    self.hexBox.Position = l.hexPos
    self.hexBox.Size = l.hexSize
    self.alphaBox.Position = l.alphaFieldPos
    self.alphaBox.Size = l.alphaFieldSize

    if self._isOpen then
        variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, self._openHeight) }):Play()
        variables.tweenService
            :Create(self.preview, openInfo, { Position = self._previewOpenPos, Size = self._previewOpenSize })
            :Play()
    end
end

function ColorPicker:Set(color, skipCallback)
    self.value = coerceColor(color, self.value)
    self.hue, self.sat, self.val = self.value:ToHSV()
    -- ease the cursors only when the picker is open, otherwise theres nothing on screen to move
    self:_render(if self._isOpen then "animate" else "instant")

    if not skipCallback then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

function ColorPicker:SetAlpha(alpha, skipCallback)
    self.alpha = clamp01(if type(alpha) == "number" then alpha else self.alpha)
    self:_render(if self._isOpen then "animate" else "instant")

    if not skipCallback then
        self:_fireCallback()
        self.window:_persist(self)
    end
end

-- Persistence: RRGGBB plus an alpha byte (AA) so alpha round-trips.
function ColorPicker:_serialize()
    return self.value:ToHex() .. string.format("%02x", math.clamp(math.round((self.alpha or 1) * 255), 0, 255))
end

-- Restore colour + alpha from that hex. Old 6-char configs (no alpha byte) still load. Alpha is
-- set silently first so the Set fires the callback just once, with the final colour and alpha.
function ColorPicker:_deserialize(raw)
    local hex = tostring(raw)
    local alpha = nil
    if #hex >= 8 then
        alpha = (tonumber(hex:sub(7, 8), 16) or 255) / 255
        hex = hex:sub(1, 6)
    end

    -- resolve the colour before applying anything: fromHex throws on a malformed string, and
    -- an alpha set first would stick while the colour fell back to the default
    local ok, color = pcall(Color3.fromHex, hex)
    if not ok then
        return
    end
    if alpha then
        self:SetAlpha(alpha, true)
    end
    self:Set(color)
end

function ColorPicker:_setShown(shown, animate)
    local w = self.window
    if shown then
        w:_revealCommon(self, animate)
        -- the preview shows the colour at its alpha, so its opacity tracks alpha even in the header
        w:_reveal(self.preview, { BackgroundTransparency = 1 - self.alpha }, animate)
        w:_reveal(self.previewShadow, { Transparency = 1 - 0.4 * self.alpha }, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.preview, { BackgroundTransparency = 1 }, animate)
        w:_reveal(self.previewShadow, { Transparency = 1 }, animate)
        -- if the window hides while we're open, collapse so we dont reopen mid-air
        if self._isOpen then
            self:_close()
        end
    end
end

moveable(ColorPicker)
lockable(ColorPicker)

return ColorPicker

end)()
local contentSlides=setmetatable({}, {__mode="k"})
local function slideContent(object,rest,direction,distance)
 local previous=contentSlides[object];if previous then previous:Cancel()end
 local progress=Instance.new("NumberValue");local native=game:GetService("TweenService")
 object.Position=rest+UDim2.fromOffset(direction*distance,0)
 local connection=progress.Changed:Connect(function(value)
  local bounded=math.min(1,value)+math.max(0,value-1)*.18
  if object.Parent then object.Position=rest+UDim2.fromOffset(direction*distance*(1-bounded),0)end
 end)
 local animation=native:Create(progress,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Value=1});contentSlides[object]=animation
 animation.Completed:Once(function(state)connection:Disconnect();progress:Destroy();if state==Enum.PlaybackState.Completed and object.Parent then object.Position=rest end;if contentSlides[object]==animation then contentSlides[object]=nil end end);animation:Play()
end
local function slideHeading(panel,direction)
 for _,name in ipairs({"Icon","Title","Subtitle","HeaderIcon","ContentTitle","ContentSubtitle"})do
  local object=panel:FindFirstChild(name)
  if object and object:IsA("GuiObject")then
   local rest=object:GetAttribute("AltairHeadingRest")or object.Position;object:SetAttribute("AltairHeadingRest",rest);slideContent(object,rest,direction,18)
  end
 end
end

local resetAnimations=setmetatable({}, {__mode="k"})
local function bounceReset(icon)
 local old=resetAnimations[icon];if old then old:Cancel()end
 local tween=game:GetService("TweenService"):Create(icon,TweenInfo.new(.7,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Rotation=icon.Rotation-360})
 resetAnimations[icon]=tween;tween:Play();return tween
end

local function buildColorPicker(template,parent,setting,changed,commit,resetTheme)
 local window=rayfieldWindow(parent);local connections={};local root=parent:FindFirstAncestorOfClass("ScreenGui")
 window.screenGui=root;window.hasShownOnce=true
 window.theme.ElementStroke=Color3.fromRGB(90,95,108);window.theme.ElementStrokeHover=Color3.fromRGB(165,175,195);window.theme.ElementStrokeHoverTransparency=.4;window.theme.ElementTextHoverColor=Color3.new(1,1,1)
 local create=window.Create
 function window:Create(class,properties,themes)local o=create(self,class,properties,themes);if class=="ImageLabel"and properties.Image=="__AltairPalette"then applyIcon(o,"palette")end;return o end
 function window:Connect(signal,fn)local c=signal:Connect(fn);connections[#connections+1]=c;return c end
 function window:ConnectFor(_,signal,fn)return self:Connect(signal,fn)end
 function window:Disconnect(c)if c then c:Disconnect()end end
 function window:_interactive()return parent.Parent~=nil and not root.Settings:GetAttribute("AltairClosing")end
 function window:_registerControl()end;function window:_siaUsed()end
 function window:_persist()commit()end
 function window:_runGuarded(_,callback,...)callback(...)end
 function window:StyleElementBody(main)
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=main
  main.BackgroundColor3=Color3.fromRGB(20,22,27);main:SetAttribute("AltairSurface",true)
  local gradient=Instance.new("UIGradient");gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(225,228,235));gradient.Rotation=90;gradient.Parent=main
  local stroke=Instance.new("UIStroke");stroke.Color=self.theme.ElementStroke;stroke.Transparency=.65;stroke.Parent=main;return stroke
 end
 function window:CreateHoverOverlay(main)local o=Instance.new("Frame");o.Size=UDim2.fromScale(1,1);o.BackgroundColor3=Color3.new(1,1,1);o.BackgroundTransparency=1;o.BorderSizePixel=0;o.Parent=main;return o end
 function window:CreateGlow(parent,color,_,alpha)
  local ok,o=pcall(Instance.new,"UIShadow");if not ok then o=Instance.new("UIStroke");o.Thickness=1 end
  o.Color=color;o.Transparency=alpha;o.Parent=parent;return o
 end
 local picker=RayfieldColorPicker.new({window=window,tabPage=parent},{name=setting.name,color=setting.current,alpha=setting.alpha or .25,forgetState=true,callback=changed})
 picker.title.Name="Title";picker.interact.Name="Interact"
 picker.main:SetAttribute("AltairThemeEditor",true);picker.main:SetAttribute("AltairRayfieldVisual",true)
 picker.main.Name=setting.name;picker.main.Size=UDim2.new(1,-16,0,41)
 local reset=Instance.new("ImageButton");reset.Name="ResetTheme";reset.AnchorPoint=Vector2.new(1,.5);reset.Position=UDim2.new(1,-64,0,20.5);reset.Size=UDim2.fromOffset(20,20);reset.BackgroundTransparency=1;reset.ImageColor3=Color3.fromRGB(220,225,236);reset.ZIndex=picker.interact.ZIndex+3;reset.Parent=picker.main;applyIcon(reset,"rotate-ccw")
 local resetMotion=motionService(function()return root:GetAttribute("AltairReduceMotion")==true end,true)
 local resetMove,resetSpin,resetScaleTween
 local resetScale=Instance.new("UIScale");resetScale.Parent=reset
 local function resetPosition(animate)
  if resetMove then resetMove:Cancel()end
  local target=UDim2.new(1,picker._isOpen and -16 or -64,0,20.5)
  if animate then resetMove=resetMotion:Create(reset,TweenInfo.new(.5,Enum.EasingStyle.Exponential,Enum.EasingDirection.Out),{Position=target});resetMove:Play()else reset.Position=target end
 end
 local open,close=picker._open,picker._close
 function picker:_open()open(self);resetPosition(true)end
 function picker:_close()close(self);resetPosition(true)end
 window:Connect(reset.Activated,function()
  if not window:_interactive()then return end
  if resetSpin then resetSpin:Cancel()end
  if resetScaleTween then resetScaleTween:Cancel()end
  resetSpin=bounceReset(reset)
  resetScaleTween=resetMotion:Create(resetScale,TweenInfo.new(.09),{Scale=.9});resetScaleTween:Play()
  task.delay(.09,function()if reset.Parent then resetScaleTween=resetMotion:Create(resetScale,TweenInfo.new(.38,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1});resetScaleTween:Play()end end)
  if resetTheme then resetTheme()end
 end)
 window:Connect(reset.MouseEnter,function()window:_reveal(reset,{ImageTransparency=0},true)end)
 window:Connect(reset.MouseLeave,function()window:_reveal(reset,{ImageTransparency=.25},true)end)
 local shown=picker._setShown
 function picker:_setShown(value,animate)shown(self,value,animate);window:_reveal(reset,{ImageTransparency=value and .25 or 1},animate)end
 picker:_setShown(true,false)
 picker.main.Destroying:Connect(function()if resetMove then resetMove:Cancel()end;if resetSpin then resetSpin:Cancel()end;if resetScaleTween then resetScaleTween:Cancel()end;window.unloaded=true;picker:_endDrag();for _,c in ipairs(connections)do c:Disconnect()end end)
 return picker.main,picker
end

local function buildStats(template,parent)
 local row=template:Clone();row.Name="Session Performance";row.Visible=true;row.Parent=parent
 row.Title.Visible=false;row.Description.Visible=false;row.BackgroundTransparency=1;row.UIStroke.Enabled=false
 local interact=row:FindFirstChild("Interact");if interact then interact:Destroy() end
 local window=rayfieldWindow(row)
 local fps=RayfieldStatistic.new({window=window,tabPage=row},{name="Client FPS",suffix=" FPS"})
 local ping=RayfieldStatistic.new({window=window,tabPage=row},{name="Server Ping",suffix=" ms"})
 fps.main.Size=UDim2.new(1,0,0,90);fps.main.Position=UDim2.fromOffset(0,0)
 ping.main.Size=UDim2.new(1,0,0,90);ping.main.Position=UDim2.fromOffset(0,98)
 local accent=ping._setAccent
 function ping:_setAccent(key,direction) return accent(self,key=="positive" and "negative" or key=="negative" and "positive" or key,-direction) end
 fps:_setShown(true,true);ping:_setShown(true,true)
 return row,{fps=fps,ping=ping}
end

-- Pointer/touch/keyboard slider; commits once when an interaction finishes.
local function buildSlider(template,parent,setting,onChange,onCommit)
 local row=template:Clone();row.Name=setting.name;row.Parent=parent;row.Visible=true;row.Title.Text=setting.name
 local old=row:FindFirstChild("Interact");if old then old:Destroy() end
 local function make(class,name,properties,container)
  local object=Instance.new(class);object.Name=name
  for key,value in pairs(properties) do object[key]=value end
  object.Parent=container or row;return object
 end
 local value=make("TextLabel","Value",{BackgroundTransparency=1,Position=UDim2.new(1,-110,0,12),Size=UDim2.fromOffset(92,22),TextSize=14,TextColor3=Color3.fromRGB(235,238,245),FontFace=row.Title.FontFace,TextXAlignment=Enum.TextXAlignment.Right,ZIndex=row.Title.ZIndex})
 local track=make("Frame","Track",{Position=UDim2.new(0,20,1,-24),Size=UDim2.new(1,-40,0,14),BackgroundColor3=Color3.fromRGB(68,72,82),BorderSizePixel=0,ZIndex=row.Title.ZIndex})
 local fill=make("Frame","Fill",{Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.fromRGB(110,158,255),BorderSizePixel=0,ZIndex=track.ZIndex+1},track)
 local thumb=make("Frame","Thumb",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(1,0,.5,0),Size=UDim2.fromOffset(35,20),BackgroundColor3=Color3.fromRGB(245,247,255),BorderSizePixel=0,ZIndex=track.ZIndex+2},fill)
 for _,v in ipairs({track,fill,thumb}) do local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=v end
 local hit=make("TextButton","SliderInput",{Text="",BackgroundTransparency=1,Position=UDim2.new(0,12,1,-42),Size=UDim2.new(1,-24,0,40),AutoButtonColor=false,Selectable=true,ZIndex=track.ZIndex+3})
 local input=game:GetService("UserInputService");local connections={};local dragging=false;local touch=nil;local dragLeft,dragWidth
 local low,high=setting.values[1],setting.values[2];local motion=motionService()
 local window=rayfieldWindow(row)
 value.Text="";local readout=Instance.new("Frame");readout.Name="RollingValue";readout.BackgroundTransparency=1;readout.Size=UDim2.fromScale(1,1);readout.ZIndex=value.ZIndex+1;readout.Parent=value
 local odo=RayfieldOdometer.new(window,readout,{textSize=14,alignment=Enum.HorizontalAlignment.Right,transparency=0,duration=.3})
 local edge=Instance.new("UIStroke");edge.Color=Color3.new(1,1,1);edge.Transparency=1;edge.Parent=thumb
 connections[#connections+1]=hit.MouseEnter:Connect(function()motion:Create(track,TweenInfo.new(.25),{BackgroundColor3=Color3.fromRGB(90,96,110)}):Play()end)
 connections[#connections+1]=hit.MouseLeave:Connect(function()motion:Create(track,TweenInfo.new(.25),{BackgroundColor3=Color3.fromRGB(68,72,82)}):Play()end)
 local function draw(animate)
  local ratio=(setting.current-low)/(high-low)
  local text=tostring(math.floor(setting.current+.5))..(setting.suffix or "%")
  value:SetAttribute("DisplayedValue",text)
  if animate then
   motion:Create(fill,TweenInfo.new(.3,Enum.EasingStyle.Quint),{Size=UDim2.fromScale(ratio,1)}):Play()
   if dragging then odo:snap(text) else odo:to(text,true) end
  else fill.Size=UDim2.fromScale(ratio,1);odo:snap(text) end
 end
 local function setValue(nextValue)
  nextValue=math.clamp(math.floor(nextValue+.5),low,high)
  if nextValue~=setting.current then setting.current=nextValue;draw(true);onChange(nextValue) end
 end
 local function pointer(x)
  local left,width=dragLeft or track.AbsolutePosition.X,dragWidth or track.AbsoluteSize.X
  if width>0 then setValue(low+math.clamp((x-left)/width,0,1)*(high-low)) end
 end
 local function finish()
  if not dragging then return end;dragging=false;touch=nil;dragLeft=nil;dragWidth=nil
  motion:Create(thumb,TweenInfo.new(.3),{Size=UDim2.fromOffset(35,20),BackgroundTransparency=0}):Play();motion:Create(edge,TweenInfo.new(.3),{Transparency=1}):Play();onCommit()
 end
 connections[#connections+1]=hit.InputBegan:Connect(function(event)
  if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
   dragLeft,dragWidth=track.AbsolutePosition.X,track.AbsoluteSize.X
   dragging=true;touch=event.UserInputType==Enum.UserInputType.Touch and event or nil
   motion:Create(thumb,TweenInfo.new(.3),{Size=UDim2.fromOffset(41,22),BackgroundTransparency=.7}):Play();motion:Create(edge,TweenInfo.new(.3),{Transparency=.6}):Play();pointer(event.Position.X)
  elseif event.KeyCode==Enum.KeyCode.Left or event.KeyCode==Enum.KeyCode.Right then setValue(setting.current+(event.KeyCode==Enum.KeyCode.Right and (setting.step or 5) or -(setting.step or 5)));onCommit() end
 end)
 connections[#connections+1]=input.InputChanged:Connect(function(event)
  if dragging and ((touch and event==touch) or (not touch and event.UserInputType==Enum.UserInputType.MouseMovement)) then pointer(event.Position.X) end
 end)
 connections[#connections+1]=input.InputEnded:Connect(function(event)
  if dragging and (event==touch or event.UserInputType==Enum.UserInputType.MouseButton1) then finish() end
 end)
 connections[#connections+1]=input.WindowFocusReleased:Connect(finish)
 row.Destroying:Connect(function() for _,connection in ipairs(connections) do connection:Disconnect() end end)
 connections[#connections+1]=row:GetAttributeChangedSignal("AltairRefreshValue"):Connect(function()draw(true)end)
 draw();return row
end

-- Native, resolution-independent previews: the cards remain crisp at every UI size.
local function buildStyleGallery(parent,setting,changed)
 local root=parent:FindFirstAncestorOfClass("ScreenGui")
 local z=root.Settings.ZIndex+4
 local motion=motionService();local connections={};local cards={};local controller={}
 local function make(class,name,owner,props)
  local object=Instance.new(class);object.Name=name
  if object:IsA("GuiObject")then object.BorderSizePixel=0;object.BackgroundTransparency=1;object.ZIndex=z end
  for key,value in pairs(props or {})do object[key]=value end
  object.Parent=owner;return object
 end
 local function corner(owner,radius)return make("UICorner","UICorner",owner,{CornerRadius=UDim.new(0,radius)})end
 local function text(name,owner,value,position,size,fontSize,bold)
  return make("TextLabel",name,owner,{Text=value,Position=position,Size=size,TextSize=fontSize,TextColor3=Color3.fromRGB(242,243,247),FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular),TextXAlignment=Enum.TextXAlignment.Left})
 end
 local function connect(signal,callback)table.insert(connections,signal:Connect(callback))end
 local frame=make("Frame",setting.name,parent,{Size=UDim2.new(1,-16,0,248)})
 frame:SetAttribute("AltairThemeEditor",true);frame:SetAttribute("AltairStyleGallery",true)
 text("Title",frame,"Styles",UDim2.fromOffset(2,0),UDim2.new(1,-110,0,24),18,true)
 text("Description",frame,"A different interface. Your colours stay yours.",UDim2.fromOffset(2,25),UDim2.new(1,0,0,20),12,false).TextColor3=Color3.fromRGB(177,181,194)
 local badge=text("Experimental",frame,"EXPERIMENTAL",UDim2.new(1,-103,0,2),UDim2.fromOffset(103,23),10,true)
 badge.TextXAlignment=Enum.TextXAlignment.Center;badge.BackgroundColor3=Color3.fromRGB(73,57,102);badge.BackgroundTransparency=.2;corner(badge,7)
 for index,id in ipairs({"Altair","Roblox"})do
  local card=make("TextButton",id,frame,{Text="",AutoButtonColor=false,Position=UDim2.new((index-1)*.5,(index-1)*6,0,52),Size=UDim2.new(.5,-6,0,144),BackgroundColor3=Color3.fromRGB(29,31,38),BackgroundTransparency=.14})
  corner(card,12)
  local stroke=make("UIStroke","Selection",card,{Color=Color3.fromRGB(82,88,106),Thickness=1,Transparency=.5})
  local scale=make("UIScale","HoverScale",card,{Scale=1})
  local preview=make("Frame","SmartBarPreview",card,{Position=UDim2.fromOffset(8,8),Size=UDim2.new(1,-16,0,72),ClipsDescendants=true,BackgroundColor3=Color3.fromRGB(12,14,20),BackgroundTransparency=.15})
  corner(preview,8)
  local handle=make("Frame","Handle",preview,{Position=UDim2.new(.5,-24,0,10),Size=UDim2.fromOffset(48,2),BackgroundColor3=Color3.fromRGB(185,188,200),BackgroundTransparency=.3});corner(handle,2)
  local bar=make("Frame","SmartBar",preview,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.58),Size=UDim2.new(1,-16,0,39),BackgroundColor3=id=="Roblox"and Color3.fromRGB(22,24,29)or Color3.fromRGB(17,18,22),BackgroundTransparency=.12});corner(bar,20)
  make("UIStroke","Outline",bar,{Color=Color3.fromRGB(100,105,121),Transparency=.65,Thickness=1})
  local clock=text("Clock",bar,"12:03",UDim2.fromOffset(8,9),UDim2.fromOffset(31,20),10,false)
  clock.Position=UDim2.fromOffset(8,5);text("AMPM",bar,"AM",UDim2.fromOffset(8,23),UDim2.fromOffset(31,8),6,false).TextXAlignment=Enum.TextXAlignment.Center
  local inset=make("Frame","Inset",bar,{Position=UDim2.fromOffset(43,4),Size=UDim2.new(1,-47,1,-8),BackgroundColor3=Color3.fromRGB(48,50,58),BackgroundTransparency=.4});corner(inset,16)
  local colors={Color3.fromRGB(105,77,173),Color3.fromRGB(21,141,173),Color3.fromRGB(180,94,36),Color3.fromRGB(21,154,102),Color3.fromRGB(86,91,104)}
  for n,iconId in ipairs({"house","person-standing","square-terminal","users-round","settings"})do
   local button=make("Frame","Button"..n,inset,{Position=UDim2.new((n-1)/5,2,0,2),Size=UDim2.new(.2,-4,1,-4),BackgroundColor3=id=="Roblox"and Color3.fromRGB(39,41,48)or colors[n],BackgroundTransparency=id=="Roblox"and .7 or .05});corner(button,7)
   if id=="Altair"then make("UIGradient","Gradient",button,{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(138,144,165)),Rotation=50})end
   local icon=make("ImageLabel","Icon",button,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(16,16)});applyIcon(icon,iconId)
  end
  text("Name",card,id,UDim2.fromOffset(12,89),UDim2.new(1,-46,0,22),16,true)
  local subtitle=text("Summary",card,id=="Roblox"and"Builder Sans · quiet surfaces"or"Colourful · glass surfaces",UDim2.fromOffset(12,114),UDim2.new(1,-24,0,18),11,false);subtitle.TextColor3=Color3.fromRGB(172,178,194)
  local selected=make("ImageLabel","Selected",card,{Position=UDim2.new(1,-31,0,91),Size=UDim2.fromOffset(18,18),ImageColor3=Color3.fromRGB(115,161,255),ImageTransparency=1});applyIcon(selected,"circle-check")
  cards[id]={card=card,stroke=stroke,scale=scale,selected=selected}
  connect(card.MouseEnter,function()motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.02}):Play();motion:Create(card,TweenInfo.new(.16),{BackgroundTransparency=0}):Play()end)
  connect(card.MouseLeave,function()motion:Create(scale,TweenInfo.new(.24,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play();motion:Create(card,TweenInfo.new(.16),{BackgroundTransparency=.14}):Play()end)
  connect(card.Activated,function()
   motion:Create(scale,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=.98}):Play()
   task.delay(.12,function()if card.Parent then motion:Create(scale,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end end)
   controller:Set(id)
  end)
 end
 local reset=make("TextButton","ResetStyle",frame,{Text="Reset style",TextSize=13,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium),TextColor3=Color3.fromRGB(235,238,245),AutoButtonColor=false,Position=UDim2.fromOffset(0,208),Size=UDim2.fromOffset(125,32),BackgroundColor3=Color3.fromRGB(42,45,55),BackgroundTransparency=.2});corner(reset,8)
 local resetIcon=make("ImageLabel","Icon",reset,{Position=UDim2.fromOffset(10,8),Size=UDim2.fromOffset(16,16)});applyIcon(resetIcon,"rotate-ccw")
 reset.Text="      Reset style"
 connect(reset.MouseEnter,function()motion:Create(reset,TweenInfo.new(.16),{BackgroundTransparency=0}):Play()end)
 connect(reset.MouseLeave,function()motion:Create(reset,TweenInfo.new(.16),{BackgroundTransparency=.2}):Play()end)
 connect(reset.Activated,function()bounceReset(resetIcon);controller:Set("Altair")end)
 text("AppliesTo",frame,"Applies across Altair",UDim2.fromOffset(137,213),UDim2.new(1,-137,0,22),11,false).TextColor3=Color3.fromRGB(156,163,181)
 function controller:Set(id,silent)
  if id~="Roblox"then id="Altair"end
  local previous=setting.current;setting.current=id
  for name,card in pairs(cards)do
   local active=name==id
   motion:Create(card.stroke,TweenInfo.new(.2),{Color=active and Color3.fromRGB(112,156,255)or Color3.fromRGB(82,88,106),Transparency=active and .05 or .5,Thickness=active and 1.5 or 1}):Play()
   motion:Create(card.selected,TweenInfo.new(.16),{ImageTransparency=active and 0 or 1}):Play()
  end
  if not silent and previous~=id then changed(id)end
 end
 controller:Set(setting.current,true)
 frame.Destroying:Connect(function()for _,connection in ipairs(connections)do connection:Disconnect()end end)
 return frame,controller
end

local function bindTheme(root)
 local records=setmetatable({}, {__mode="k"});local controller={active=false,rainbow=false,color=Color3.fromRGB(91,141,239),strength=.25,lightness=0};local changedConnection
 local applying=false;local contrastCache={};local native=game:GetService("TweenService");local styleRecords=setmetatable({}, {__mode="k"})
 local function skip(object)
  if object:GetAttribute("AltairContrastOutline")then return true end
  local p=object
  while p and p~=root do
   if p:GetAttribute("AltairThemeIgnore")then return true end
   if p:GetAttribute("AltairThemeEditor")then
    if not p:GetAttribute("AltairStyleGallery")and(object:IsA("TextLabel")or object:IsA("TextBox")or object:IsA("TextButton")or object:GetAttribute("AltairIcon"))then return false end
    return object~=p and not((object:IsA("UIStroke")or object:IsA("UIGradient"))and object.Parent==p)
   end
   p=p.Parent
  end
  return false
 end
 local function role(object,property)
  if property=="TextColor3"then return "text"end
  if property=="ImageColor3"then return (object.Name=="Shadow"or object.Name=="SoftShadow"or object.Name=="Glow")and"stroke"or"icon"end
  if object:IsA("UIStroke")then return object:FindFirstChildOfClass("UIGradient")and"strokeMultiplier"or"stroke"end
  local owner=object:IsA("UIGradient")and object.Parent or object
  if object:IsA("UIGradient")then
   if owner:IsA("TextLabel")or owner:IsA("TextBox")or owner:IsA("TextButton")and owner.Text~=""and owner.BackgroundTransparency>.95 or owner:GetAttribute("AltairIcon")then return "contentGradient"end
   if owner:IsA("UIStroke")then return "strokeGradient"end
   return "gradient"
  end
  -- White is a gradient multiplier, not another colored layer.
  if owner:GetAttribute("AltairInsetSurface")then return "inset"end
  if owner:FindFirstChildOfClass("UIGradient")then return "multiplier"end
  return "background"
 end
 local function mapped(base,kind,time,variation)
  local strength=controller.active and controller.strength or 0;local light=controller.lightness or 0
  if kind=="contentGradient"then return Color3.new(1,1,1)end
  if kind=="strokeMultiplier"then return controller.active and Color3.new(1,1,1)or base end
  if kind=="text"or kind=="icon"then
   if light>.72 then local brightness=.2126*base.R+.7152*base.G+.0722*base.B;return brightness>.8 and Color3.fromRGB(22,24,29)or Color3.fromRGB(65,69,78)end
   return base
  end
  if kind=="multiplier"then return controller.active and Color3.new(1,1,1)or base:Lerp(Color3.fromRGB(235,238,244),light*.25)end
  local hue,sat,value=controller.color:ToHSV();local t=time or .5
  local offset=(variation or 0)*math.min(1,sat*2);local hueSample=Color3.fromHSV(hue,sat,1)
  local luminance=.2126*hueSample.R+.7152*hueSample.G+.0722*hueSample.B
  local balance=math.clamp(math.sqrt(.35/math.max(.08,luminance)),.7,1.35)
  local target
  if kind=="inset"then
   target=Color3.fromHSV(hue,math.min(.55,sat),.23+.1*strength)
  elseif kind=="background"then
   target=Color3.fromHSV(hue,math.min(.8,sat),.045+.12*strength)
  elseif kind=="surfaceGradient"then
   target=Color3.fromHSV((hue-.018+t*.045)%1,math.min(.8,sat),.12+.12*t)
  elseif kind=="gradient"then
   target=Color3.fromHSV((hue+offset-.025+t*.095)%1,math.min(.94,sat)*(.55+.45*strength),math.min(.62,(.19+.25*t+.10*strength)*math.max(.5,value)*balance))
   if controller.active then return target:Lerp(Color3.fromRGB(235,238,244),light*.78)end
  else
   target=Color3.fromHSV((hue-.015+t*.065)%1,math.min(.7,sat),.36+.18*t)
  end
  if controller.active and(kind=="background"or kind=="surfaceGradient")then local grey=(base.R+base.G+base.B)/3;base=Color3.new(grey,grey,grey)end
  if controller.active and(kind=="stroke"or kind=="strokeGradient")then
   target=Color3.fromHSV((hue+(variation or 0)+(time or .5)*.035)%1,math.min(.65,sat),.50+.14*(time or .5))
   return target:Lerp(Color3.fromRGB(55,59,68),light*.7)
  end
  local result=base:Lerp(target,strength)
  return result:Lerp(Color3.fromRGB(235,238,244),(kind=="surfaceGradient"or kind=="background")and light^2*.92 or light*.75)
 end
 local function desired(base,kind,object,property)
  kind=role(object,property)
  if controller.style=="Roblox"then
   if typeof(base)=="ColorSequence"then
    if kind=="contentGradient"or kind=="strokeGradient"then base=ColorSequence.new(Color3.new(1,1,1))
    elseif object.Parent:GetAttribute("AltairSurface")then base=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(232,234,239))
    elseif object.Parent.Parent==root then base=ColorSequence.new(Color3.fromRGB(27,29,35),Color3.fromRGB(22,24,30))
    else base=ColorSequence.new(Color3.fromRGB(47,49,58),Color3.fromRGB(34,36,43))end
   elseif kind=="multiplier"then base=object:GetAttribute("AltairSurface")and Color3.fromRGB(25,27,33)or Color3.new(1,1,1)
   elseif kind=="background"then base=Color3.fromRGB(25,27,33)
   elseif kind=="inset"then base=Color3.fromRGB(43,45,53)
   elseif kind=="strokeMultiplier"then base=Color3.fromRGB(100,103,115)
   elseif kind=="stroke"then
    base=(object.Name=="Shadow"or object.Name=="SoftShadow"or object.Name=="Glow")and Color3.new(0,0,0)or Color3.fromRGB(100,103,115)
   end
  end
  if kind=="text"or kind=="icon"then
   local lightBackground=false;local surface=object
   while surface and surface~=root do
    if surface:GetAttribute("AltairNotificationCard")then surface=surface:FindFirstChild("CardBackground")or surface end
    if surface:IsA("GuiObject")and surface.BackgroundTransparency<.7 then
     if contrastCache[surface]~=nil then lightBackground=contrastCache[surface];break end
     local record=records[surface];local saved=record and record.BackgroundColor3
     local color=desired(saved and saved.base or surface.BackgroundColor3,"background",surface,"BackgroundColor3")
     local gradient=surface:FindFirstChildOfClass("UIGradient")
     if gradient then
      local gr=records[gradient];local gs=gr and gr.Color
      local sequence=desired(gs and gs.base or gradient.Color,"gradient",gradient,"Color")
      local points=sequence.Keypoints;local multiplier=points[1].Value:Lerp(points[#points].Value,.5)
      color=Color3.new(color.R*multiplier.R,color.G*multiplier.G,color.B*multiplier.B)
     end
     local function linear(c)return c<=.04045 and c/12.92 or((c+.055)/1.055)^2.4 end
     lightBackground=.2126*linear(color.R)+.7152*linear(color.G)+.0722*linear(color.B)>.179
     contrastCache[surface]=lightBackground;break
    end
    surface=surface.Parent
   end
   local p=object;local notification=false;local artwork=false
   while p and p~=root do
    if p.Name=="NotificationCapsules"then notification=true end
    if p.Name=="CustomScriptPrompt"or p.Name=="GameDetection"then artwork=true end
    p=p.Parent
   end
   if artwork then return base end
   if notification then
    return lightBackground and Color3.new(0,0,0)or Color3.new(1,1,1)
   end
   if lightBackground then local brightness=.2126*base.R+.7152*base.G+.0722*base.B;return brightness>.8 and Color3.fromRGB(22,24,29)or Color3.fromRGB(65,69,78)end
   return base
  end
  if typeof(base)=="ColorSequence"then
   if kind=="contentGradient"then return ColorSequence.new(Color3.new(1,1,1))end
   if not controller.active and controller.lightness==0 then return base end
   local owner=object.Parent
   local hash=0;local identity=owner.Name..(owner.Parent and owner.Parent.Name or "");for i=1,#identity do hash=(hash*31+identity:byte(i))%997 end
   local variation=(hash/996-.5)*.075
   if owner:GetAttribute("AltairSurface")then kind="surfaceGradient"end
   local points={};local list=base.Keypoints
   if #list==2 then list={ColorSequenceKeypoint.new(0,list[1].Value),ColorSequenceKeypoint.new(.5,list[1].Value:Lerp(list[2].Value,.5)),ColorSequenceKeypoint.new(1,list[2].Value)}end
   for _,point in ipairs(list)do
    local baseColor=point.Value
    if kind=="surfaceGradient"and controller.active then local body=owner:GetAttribute("AltairThemeDefault_BackgroundColor3")or Color3.fromRGB(10,11,14);baseColor=Color3.new(body.R*baseColor.R,body.G*baseColor.G,body.B*baseColor.B)end
    points[#points+1]=ColorSequenceKeypoint.new(point.Time,mapped(baseColor,kind,point.Time,variation))
   end
   return ColorSequence.new(points)
  end
  if controller.style=="Roblox"and kind=="multiplier"and object:GetAttribute("AltairSurface")and not controller.active then
   return Color3.fromRGB(25,27,33):Lerp(Color3.fromRGB(235,238,244),controller.lightness^2*.95)
  end
  return mapped(base,kind)
 end
 local function styleObject(object)
  if skip(object)or object:IsA("TextLabel")and object:GetAttribute("AltairIcon")then return end
  local original=styleRecords[object]
  if not original then
   if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then original={font=object.FontFace}
   elseif object:IsA("UICorner")then original={radius=object.CornerRadius}
   else return end
   styleRecords[object]=original
  end
  if original.font then
   object.FontFace=controller.style=="Roblox"and Font.new("rbxasset://fonts/families/BuilderSans.json",original.font.Weight,original.font.Style)or original.font
  elseif original.radius then
   local radius=original.radius
   if controller.style=="Roblox"and radius.Scale==0 and radius.Offset<25 then radius=UDim.new(0,object.Parent and object.Parent:GetAttribute("AltairSurface")and 12 or 8)end
   if object.CornerRadius~=radius then
    if opacityOffscreen(object)then object.CornerRadius=radius
    else native:Create(object,TweenInfo.new(.2,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{CornerRadius=radius}):Play()end
   end
  end
 end
 local smartIcons={}
 local function styleIcons()
  local bar=root:FindFirstChild("SmartBar");local back=bar and bar:FindFirstChild("Back");local buttons=back and back:FindFirstChild("Buttons")
  if not buttons then return end
  local icons={Home="house",Character="person-standing",Scripts="square-terminal",Playerlist="users-round",Settings="settings"}
  for name,id in pairs(icons)do
   local button=buttons:FindFirstChild(name);local icon=button and button:FindFirstChild("Icon")
   if icon then
    if not smartIcons[icon]then smartIcons[icon]={image=icon.Image,size=icon.ImageRectSize,offset=icon.ImageRectOffset,id=icon:GetAttribute("AltairIcon"),filled=icon:GetAttribute("AltairFilledIcon")}end
    if controller.style=="Roblox"then applyIcon(icon,id);icon:SetAttribute("AltairFilledIcon",nil)
    else local original=smartIcons[icon];icon.Image=original.image;icon.ImageRectSize=original.size;icon.ImageRectOffset=original.offset;icon:SetAttribute("AltairIcon",original.id);icon:SetAttribute("AltairFilledIcon",original.filled)end
   end
  end
 end
 local function register(object)
  styleObject(object)
  if records[object]or skip(object)then return end
  local props={}
  if object:IsA("Frame")or object:IsA("CanvasGroup")or object:IsA("GuiObject")and object.BackgroundTransparency<.99 then props.BackgroundColor3="background"end
  if object:IsA("UIStroke")then props.Color="stroke"end
  if object:IsA("UIGradient")then props.Color="gradient"end
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then props.TextColor3="text"end
  if (object:IsA("ImageLabel")or object:IsA("ImageButton"))and(object:GetAttribute("AltairIcon")or object.Name:find("Icon")or object.Name=="Shadow"or object.Name=="SoftShadow"or object.Name=="Glow")then props.ImageColor3="stroke"end
  local record={};records[object]=record
  for property,kind in pairs(props)do
   local base=object[property];local saved=object:GetAttribute("AltairThemeDefault_"..property);local previous=object:GetAttribute("AltairTheme_"..property)
   if saved and previous and base==previous then base=saved end
   object:SetAttribute("AltairThemeDefault_"..property,base)
   local item={base=base,kind=kind};record[property]=item
   item.connection=object:GetPropertyChangedSignal(property):Connect(function()
    local bar=root:FindFirstChild("SmartBar");local handle=root:FindFirstChild("Drag");local pulse=root:GetAttribute("AltairThemePulse")and((bar and(object==bar or object:IsDescendantOf(bar)))or(handle and(object==handle or object:IsDescendantOf(handle))))
    if applying or pulse or root:GetAttribute("AltairThemeRainbow")or not(controller.enabled or controller.transitioning)or not object.Parent or skip(object)then return end
    if item.display and(kind~="text"or item.target~=item.base)and object[property]~=item.display then applying=true;object[property]=item.display;applying=false end
   end)
  end
 end
 function controller:Apply(config)
  table.clear(contrastCache)
  local nextStyle=config and config.style or self.style or "Altair"
  if nextStyle~="Roblox"then nextStyle="Altair"end
  if self.style~=nextStyle then
   self.style=nextStyle;root:SetAttribute("AltairInterfaceStyle",nextStyle)
   styleIcons()
   for object in pairs(styleRecords)do if object.Parent then styleObject(object)end end
  end
  if config then self.color=config.color or Color3.fromRGB(91,141,239);self.active=config.custom==true;self.strength=math.clamp(config.strength or .25,0,1);self.lightness=math.clamp(config.lightness or 0,0,1);self.active=config.custom==true and self.strength>0 end
  self.color=self.color or Color3.fromRGB(91,141,239);self.lightness=self.lightness or 0;self.strength=self.strength or .25
  self.enabled=self.active or self.lightness>0 or self.style=="Roblox"
  root:SetAttribute("AltairThemeEnabled",self.enabled)
  if self.animation then self.animation:Cancel()end
  local transitions={}
  self.applyGeneration=(self.applyGeneration or 0)+1;local generation=self.applyGeneration
  local budget=os.clock();local visited=0
  for object,record in pairs(records)do if object.Parent and not skip(object)then for property,item in pairs(record)do
   item.target=desired(item.base,item.kind,object,property);object:SetAttribute("AltairTheme_"..property,self.enabled and item.target or nil)
   if object[property]~=item.target then
    if opacityOffscreen(object)then applying=true;object[property]=item.target;item.display=item.target;applying=false
    else transitions[#transitions+1]={object=object,property=property,item=item,from=object[property]}end
   else item.display=item.target end
  end end
   visited+=1
   if visited%64==0 and os.clock()-budget>.0015 then
    game:GetService("RunService").Heartbeat:Wait()
    if generation~=self.applyGeneration or self.destroyed then return end;budget=os.clock()
   end
  end
  if #transitions==0 then self.transitioning=false;return end
  local progress=Instance.new("NumberValue");self.transitioning=true
  local connection=progress.Changed:Connect(function(alpha)
   applying=true
   for _,entry in ipairs(transitions)do if entry.object.Parent then
    local value
    if typeof(entry.from)=="ColorSequence"then
     local a,b=entry.from.Keypoints,entry.item.target.Keypoints
     value=ColorSequence.new({ColorSequenceKeypoint.new(0,a[1].Value:Lerp(b[1].Value,alpha)),ColorSequenceKeypoint.new(.5,a[math.ceil(#a/2)].Value:Lerp(b[math.ceil(#b/2)].Value,alpha)),ColorSequenceKeypoint.new(1,a[#a].Value:Lerp(b[#b].Value,alpha))})
    else value=entry.from:Lerp(entry.item.target,alpha)end
    entry.item.display=value;entry.object[entry.property]=value
   end end
   applying=false
  end)
  self.animation=native:Create(progress,TweenInfo.new(root:GetAttribute("AltairReduceMotion")and .05 or .18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Value=1})
  local animation=self.animation
  animation.Completed:Once(function(state)
   connection:Disconnect();progress:Destroy()
   if state==Enum.PlaybackState.Completed and self.animation==animation then
    self.transitioning=false;applying=true
    for _,entry in ipairs(transitions)do if entry.object.Parent then entry.item.display=entry.item.target;entry.object[entry.property]=entry.item.target end end
    applying=false
   end
  end);animation:Play()
 end
 for _,object in ipairs(root:GetDescendants())do register(object)end
 local pending=false;local additions={}
 local c=root.DescendantAdded:Connect(function(object)
  additions[#additions+1]=object
  if pending then return end;pending=true
  task.defer(function()
   pending=false;if not root.Parent then table.clear(additions);return end
   local batch=additions;additions={}
   for _,object in ipairs(batch)do if object.Parent then register(object)end end
   applying=true;table.clear(contrastCache)
   for _,object in ipairs(batch)do local record=records[object]
    if object.Parent and record and not skip(object)then for property,item in pairs(record)do
     local value=desired(item.base,item.kind,object,property);item.target=value;item.display=value
     object:SetAttribute("AltairTheme_"..property,controller.enabled and value or nil)
     if object[property]~=value then object[property]=value end
    end end
   end
   applying=false
  end)
 end)
 root.Destroying:Connect(function()controller.destroyed=true;c:Disconnect();if controller.animation then controller.animation:Cancel()end;for _,record in pairs(records)do for _,item in pairs(record)do item.connection:Disconnect()end end end)
 return controller
end

-- Shared surface material: a single translucent layer, continuous outline.
local function styleSurface(panel)
 local root=panel:FindFirstAncestorOfClass("ScreenGui")
 panel:SetAttribute("AltairSurface",true);panel.BackgroundColor3=root and root:GetAttribute("AltairOLED")and Color3.new(0,0,0)or Color3.fromRGB(10,11,14);panel.BorderSizePixel=0
 local corner=panel:FindFirstChildOfClass("UICorner")or Instance.new("UICorner");corner.CornerRadius=UDim.new(0,18);corner.Parent=panel
 local border=panel:FindFirstChildOfClass("UIStroke")or Instance.new("UIStroke");border.Name=panel.Name=="SharedPanelSurface"and"Outline"or"UIStroke";border.Color=Color3.fromRGB(160,166,180);border.Thickness=1;border.BorderStrokePosition=Enum.BorderStrokePosition.Inner;border.Transparency=.65;border.Enabled=true;border:SetAttribute("AltairSurfaceOutline",true);border.Parent=panel
 local gradient=panel:FindFirstChildOfClass("UIGradient")or Instance.new("UIGradient");gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(230,232,238));gradient.Rotation=90;gradient.Offset=Vector2.zero;gradient.Parent=panel
 return panel
end
local function styleHome(content)
 -- Console-style Home: top navigation, grouped surfaces and a recent-game shelf.
 content:SetAttribute("AltairHomeRedesign",true)
 content.BackgroundTransparency=1
 local view={states={}};local motion=motionService()
 local font=Font.new(Font.fromEnum(Enum.Font.Roboto).Family,Enum.FontWeight.Medium)
 local bold=Font.new(font.Family,Enum.FontWeight.Bold)
 local function make(class,name,parent,props)
  local o=Instance.new(class);o.Name=name
  if o:IsA("GuiObject")then o.BorderSizePixel=0;o.BackgroundTransparency=1;o.ZIndex=24 end
  for k,v in pairs(props or {})do o[k]=v end;o.Parent=parent;return o
 end
 local function rect(o,x,y,w,h)o.AnchorPoint=Vector2.zero;o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h)end
 local function corner(o,r)make("UICorner","UICorner",o,{CornerRadius=UDim.new(0,r)})end
 local function text(parent,name,value,x,y,w,h,size,muted)
  return make("TextLabel",name,parent,{Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),FontFace=bold,TextSize=size or 14,TextColor3=muted and Color3.fromRGB(167,173,185)or Color3.fromRGB(242,244,249),TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
 end
 local function button(parent,name,value,x,y,w,h)
  local o=make("TextButton",name,parent,{Text="",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(35,39,49),BackgroundTransparency=.35});corner(o,10)
  text(o,"Title",value,14,0,w-28,h,13)
  local motion=motionService();local scale=make("UIScale","HoverScale",o,{Scale=1})
  o.MouseEnter:Connect(function()motion:Create(o,TweenInfo.new(.18),{BackgroundTransparency=.05}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1.025}):Play()end)
  o.MouseLeave:Connect(function()motion:Create(o,TweenInfo.new(.2),{BackgroundTransparency=o:GetAttribute("AltairHomeFade_BackgroundTransparency")or .35}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1}):Play()end)
  return o
 end
 local root=content:FindFirstAncestorOfClass("ScreenGui")
 local function accent(button,name)
  local source=root and root.SmartBar.Back.Buttons:FindFirstChild(name)
  if not source then return end
  button:SetAttribute("AltairHomeAccent",name)
  button.BackgroundColor3=source:GetAttribute("AltairThemeDefault_BackgroundColor3")or source.BackgroundColor3
  local original=source:FindFirstChildOfClass("UIGradient")
  if original then
   local gradient=make("UIGradient","Accent",button,{Color=original:GetAttribute("AltairThemeDefault_Color")or original.Color,Rotation=original.Rotation,Offset=Vector2.zero})
  end
 end
 local function surface(panel)
  styleSurface(panel);panel:SetAttribute("AltairHomeSurface",true)
  panel:SetAttribute("AltairHomeGlass",true);panel.BackgroundTransparency=math.min(.5,(root and root:GetAttribute("AltairPanelTransparency")or .1)+.12)
 end
 local oldSidebar=content.Sidebar;local oldPages=content.Pages
 local sidebar=make("Frame","NewSidebar",content);rect(sidebar,0,0,1104,66)
 local pages=make("Frame","NewPages",content);rect(pages,0,84,1104,536)
 text(content,"HomeHeading","altair",22,15,120,36,25)
 local sub=text(content,"HomeSubheading","",0,48,120,16,10,true);sub.Visible=false
 for i,name in ipairs({"Home","Games","Friends"})do
  local nav=button(sidebar,name,({Home="Home",Friends="Friends",Games="Library"})[name],150+(i-1)*138,10,126,42)
  accent(nav,({Home="Home",Games="Scripts",Friends="Playerlist"})[name])
  nav.BackgroundTransparency=1;nav.Title.Position=UDim2.fromOffset(44,0);nav.Title.Size=UDim2.fromOffset(78,42)
  local icon=make("ImageLabel","Icon",nav,{Position=UDim2.fromOffset(14,12),Size=UDim2.fromOffset(18,18)})
  applyIcon(icon,({Home="house",Friends="users",Games="gamepad-2"})[name])
 end
 local profile=make("Frame","Profile",sidebar);rect(profile,866,12,148,44)
 local avatar=make("ImageLabel","Avatar",profile,{Position=UDim2.fromOffset(0,6),Size=UDim2.fromOffset(32,32)});corner(avatar,16)
 text(profile,"DisplayName","You",43,5,113,20,12)
 text(profile,"Status","In game",43,26,113,16,10,true)
 make("TextButton","Interact",profile,{Text="",Size=UDim2.fromScale(1,1),ZIndex=26})
 local clock=text(content,"HeaderTime","",1012,22,70,24,13,true);clock.TextXAlignment=Enum.TextXAlignment.Right
 local function section(parent,name,x,y,w,h,title)
  local o=make("Frame",name,parent);rect(o,x,y,w,h)
  if title then text(o,"Title",title,0,0,w-100,24,17)end
  return o
 end
 local header=section(content,"NavigationSurface",0,0,1104,68);header.ZIndex=19;surface(header)
 local function freshTemplate(list)
  local old=list:FindFirstChild("Template");if not old then return end
  local row=old:Clone();old:Destroy()
  local objects={row};for _,o in ipairs(row:GetDescendants())do objects[#objects+1]=o end
  for _,o in ipairs(objects)do for name in pairs(o:GetAttributes())do if name:find("^AltairTheme")then o:SetAttribute(name,nil)end end end
  row.Parent=list;return row
 end
 local function transplant(old,parent,name,x,y,w,h)
  local o=old:FindFirstChild(name);if not o then return end
  o.Parent=parent;rect(o,x,y,w,h);return o
 end
 local home=make("CanvasGroup","Home",pages,{Size=UDim2.fromOffset(1104,540)});home:SetAttribute("AltairHomePageGroup",true)
 local oldHome=oldPages.Home
 local hero=section(home,"NowPlaying",0,0,712,300)
 surface(hero)
 hero.ClipsDescendants=true
 local art=make("ImageLabel","Artwork",hero,{Size=UDim2.fromScale(1,1),ScaleType=Enum.ScaleType.Crop,ImageTransparency=.08,ZIndex=24});corner(art,18)
 local nextArt=art:Clone();nextArt.Name="NextArtwork";nextArt.ImageTransparency=1;nextArt.Parent=hero
 local shade=make("Frame","Readability",hero,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0,ZIndex=25});corner(shade,18);shade:SetAttribute("AltairThemeIgnore",true)
 make("UIGradient","ReadabilityGradient",shade,{Rotation=90,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.65),NumberSequenceKeypoint.new(.48,.3),NumberSequenceKeypoint.new(1,.04)})})
 for _,o in ipairs(hero:GetChildren())do if o:IsA("GuiObject")and o~=art and o~=nextArt and o~=shade then o.ZIndex=26 end end
 content.Parent.Dim.ZIndex=2;content.ZIndex=20;sidebar.ZIndex=40
 text(hero,"Eyebrow","CURRENT EXPERIENCE",24,22,500,20,11,true).ZIndex=26
 local gameIcon=make("ImageLabel","GameIcon",hero,{Position=UDim2.fromOffset(24,104),Size=UDim2.fromOffset(48,48)});corner(gameIcon,12)
 gameIcon.ZIndex=26
 local gameName=text(hero,"GameName","Loading experience…",88,100,598,62,25)
 gameName.ZIndex=26;gameName.TextWrapped=true;gameName.TextYAlignment=Enum.TextYAlignment.Top;gameName.TextTruncate=Enum.TextTruncate.None
 text(hero,"Creator","",24,178,654,20,13,true).ZIndex=26
 text(hero,"SessionPills","",24,208,654,20,12,true).ZIndex=26
 local resume=button(home,"Resume","Resume game",24,246,216,46)
 accent(resume,"Home");resume.BackgroundTransparency=.15
 local library=button(home,"BrowseLibrary","Explore library",254,246,178,46);accent(library,"Scripts")
 local playing=transplant(oldHome.NowPlaying,hero,"FriendsPlaying",430,18,250,28)
 if playing then playing.BackgroundTransparency=1;for _,o in ipairs(playing:GetChildren())do if o:IsA("GuiObject")then o.Visible=o.Name=="Summary"or o.Name=="ViewFriends" end end;rect(playing.Summary,0,0,250,28);playing.Summary.TextSize=10;rect(playing.ViewFriends,0,0,250,28)end
 -- Keep the existing session model available to tick(), without dashboard cards.
 local status=section(home,"SessionStatus",0,0,1,1);status.Visible=false
 for _,name in ipairs({"Time","Date","Status","Game"})do text(status,name,"",0,0,1,1,11)end
 local server=section(home,"Server",736,0,368,300,"Your session")
 surface(server);rect(server.Title,24,22,280,24)
 text(server,"PlayerCount","",24,64,322,46,34)
 text(server,"CapacityLabel","PLAYERS IN THIS SERVER",24,110,322,16,10,true)
 for i,name in ipairs({"Ping","Uptime","Region"})do
  local metric=section(server,name,24,150+(i-1)*42,322,34)
  text(metric,"Label",({Ping="Latency",Uptime="Session time",Region="Region"})[name],0,0,124,30,12,true)
  local value=text(metric,"Value","—",132,0,190,30,13);value.TextXAlignment=Enum.TextXAlignment.Right
 end
 text(content,"HomeFooter","",22,628,1060,18,11,true)
 local function listSection(old,name,x,y,w,h,title,view)
  local o=section(home,name,x,y,w,h,title)
  if view then local b=button(o,"ViewAll",view,w-86,0,86,28);b.Title.TextSize=11 end
  local list=transplant(old,o,"List",0,40,w,h-40)
  if list then
   list.BackgroundTransparency=1;list.ClipsDescendants=true
   if list:IsA("ScrollingFrame")then list.ScrollBarThickness=2;list.ScrollBarImageTransparency=.65;list.AutomaticCanvasSize=Enum.AutomaticSize.Y;list.CanvasSize=UDim2.new()end
   local pad=list:FindFirstChildOfClass("UIPadding");if pad then pad.PaddingLeft=UDim.new();pad.PaddingRight=UDim.new();pad.PaddingTop=UDim.new();pad.PaddingBottom=UDim.new()end
   local layout=list:FindFirstChildOfClass("UIListLayout");if layout then layout.Padding=UDim.new(0,10)end
   local template=freshTemplate(list)
   if template then
    template.Size=UDim2.new(1,-4,0,52);template.BackgroundTransparency=1
    for _,d in ipairs(template:GetChildren())do if d:IsA("UIStroke")or d:IsA("UIGradient")then d:Destroy()end end
    local image=template:FindFirstChild("Avatar")or template:FindFirstChild("Icon");if image then rect(image,0,4,42,42)end
    for _,pair in ipairs({{"Title",56,5,w-66,22},{"DisplayName",56,5,w-66,22},{"LastPlayed",56,29,w-66,17},{"Status",56,29,w-66,17},{"Description",56,29,w-66,17},{"Location",56,29,w-66,17}})do
     local t=template:FindFirstChild(pair[1]);if t then rect(t,pair[2],pair[3],pair[4],pair[5]);t.TextSize=pair[3]==5 and 14 or 11;t.TextTruncate=Enum.TextTruncate.AtEnd end
    end
   end
  end
  return o
 end
 local recent=listSection(oldHome.RecentlyPlayed,"RecentlyPlayed",0,320,1104,216,"Jump back in","View all")
 recent.Title.TextSize=17;accent(recent.ViewAll,"Scripts")
 surface(recent);rect(recent.Title,24,16,800,22);rect(recent.ViewAll,994,12,86,28)
 local shelf=recent.List;rect(shelf,24,54,1056,154);shelf.AutomaticCanvasSize=Enum.AutomaticSize.X;shelf.ScrollingDirection=Enum.ScrollingDirection.X
 local layout=shelf:FindFirstChildOfClass("UIListLayout");if layout then layout.FillDirection=Enum.FillDirection.Horizontal;layout.Padding=UDim.new(0,18)end
 shelf.Template:Destroy()
 local tile=make("Frame","Template",shelf,{Size=UDim2.fromOffset(166,150),Visible=false})
 local tileArt=make("ImageLabel","Icon",tile,{Size=UDim2.fromOffset(166,104),ScaleType=Enum.ScaleType.Crop});corner(tileArt,12)
 text(tile,"Title","",0,112,166,20,13)
 text(tile,"LastPlayed","",0,134,166,14,10,true)
 make("TextButton","Interact",tile,{Text="",Size=UDim2.fromScale(1,1),ZIndex=30})
 local friends=listSection(oldHome.Friends,"Friends",0,0,1,1,"Friends","View all");friends.Visible=false
 local activity=listSection(oldHome.RecentActivity,"RecentActivity",0,0,1,1,"Activity");activity.Visible=false
 -- Compact, responsive card directories replace the previous list/table views.
 local function tileFlow(list,kind)
  local old=list:FindFirstChildOfClass("UIListLayout");if old then old:Destroy()end
  local queued=false;local last=0
  local function arrange()
   if not list.Parent then return end
   local factor=root:GetAttribute("AltairDisplayScale")or 1;local width=list.AbsoluteSize.X/factor
   if width<1 then return end
   local cols=math.max(1,math.floor((width+12)/(kind=="Games"and 184 or 216)))
   local cell=(width-12*(cols-1))/cols;local height=kind=="Games"and 184 or 144
   local rows={};for _,o in ipairs(list:GetChildren())do if o:IsA("GuiObject")and o:GetAttribute("RuntimeEntry")then rows[#rows+1]=o end end
   table.sort(rows,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
   for i,row in ipairs(rows)do
    local position=UDim2.fromOffset(((i-1)%cols)*(cell+12),math.floor((i-1)/cols)*(height+12))
    local size=UDim2.fromOffset(cell,height)
    local visible=position.Y.Offset>=list.CanvasPosition.Y/factor-height and position.Y.Offset<=(list.CanvasPosition.Y+list.AbsoluteSize.Y)/factor+height
    if row:GetAttribute("AltairTilePlaced")and visible then
     if row.Position~=position or row.Size~=size then motion:Create(row,TweenInfo.new(.2,Enum.EasingStyle.Quint),{Position=position,Size=size}):Play()end
    else row.Position=position;row.Size=size;row:SetAttribute("AltairTilePlaced",true)end
   end
   list.CanvasSize=UDim2.fromOffset(0,math.ceil(#rows/cols)*(height+12));list:SetAttribute("AltairColumns",cols)
  end
  local function queue()
   if queued then return end;queued=true
   task.delay(math.max(0,.04-(os.clock()-last)),function()queued=false;last=os.clock();arrange()end)
  end
  list:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue);list.ChildAdded:Connect(queue);list.ChildRemoved:Connect(queue)
  list:GetPropertyChangedSignal("CanvasPosition"):Connect(queue);queue()
 end
 for _,name in ipairs({"Friends","Games"})do
  local old=oldPages[name]
  local page=make("CanvasGroup",name,pages,{Size=UDim2.fromOffset(1104,536),Visible=false});page:SetAttribute("AltairHomePageGroup",true)
  local browser=section(page,"Browser",0,0,1104,536,name=="Friends"and"Friends"or"Library");surface(browser)
  rect(browser.Title,20,18,450,28);browser.Title.TextSize=23
  text(browser,"Subtitle",name=="Friends"and"Your people, wherever they are playing."or"Your next session starts here.",20,51,650,20,12,true).Size=UDim2.new(1,-360,0,20)
  local search=transplant(old.Browser,browser,"SearchBox",0,0,300,36)
  search.Position=UDim2.new(1,-320,0,20);search.Size=UDim2.fromOffset(300,36);search.BackgroundColor3=Color3.fromRGB(42,42,46);search.BackgroundTransparency=.42;search.TextSize=13
  local filters=transplant(old.Browser,browser,"Filters",20,88,650,30)
  local index=0;for _,chip in ipairs(filters:GetChildren())do if chip:IsA("GuiButton")then rect(chip,index*130,0,120,30);chip.BackgroundColor3=Color3.fromRGB(48,48,53);local t=chip:FindFirstChild("Title");if t then t.TextSize=12 end;index+=1 end end
  local list=transplant(old.Browser,browser,"List",20,132,1064,384)
  list.Size=UDim2.new(1,-40,1,-152);list.BackgroundTransparency=1;list.ClipsDescendants=true;list.AutomaticCanvasSize=Enum.AutomaticSize.None;list.ScrollBarThickness=2
  local padding=list:FindFirstChildOfClass("UIPadding");if padding then padding:Destroy()end
  local oldTemplate=list:FindFirstChild("Template");if oldTemplate then oldTemplate:Destroy()end
  local card=make("Frame","Template",list,{Size=UDim2.fromOffset(200,name=="Games"and 184 or 144),Visible=false,BackgroundColor3=Color3.fromRGB(30,30,34),BackgroundTransparency=.38});corner(card,12)
  local outline=make("UIStroke","UIStroke",card,{Color=Color3.fromRGB(148,152,164),Transparency=.86,Thickness=1})
  make("TextButton","Interact",card,{Text="",Size=UDim2.fromScale(1,1),ZIndex=25})
  if name=="Games"then
   local cover=make("ImageLabel","Icon",card,{Position=UDim2.fromOffset(8,8),Size=UDim2.new(1,-16,0,92),ScaleType=Enum.ScaleType.Crop});corner(cover,9)
   text(card,"Title","",12,107,176,20,14).Size=UDim2.new(1,-24,0,20)
   text(card,"Creator","",12,128,176,16,10,true).Size=UDim2.new(1,-24,0,16)
   local played=text(card,"LastPlayed","",12,80,160,14,10);played.ZIndex=26
   local play=button(card,"Play","Play",12,150,78,24);accent(play,"Playerlist");play.ZIndex=27
   local favorite=button(card,"Favorite","Save",0,150,78,24);favorite.AnchorPoint=Vector2.new(1,0);favorite.Position=UDim2.new(1,-12,0,150);favorite.ZIndex=27
  else
   card:SetAttribute("AltairFriendTile",true)
   local avatar=make("ImageLabel","Avatar",card,{Position=UDim2.fromOffset(12,14),Size=UDim2.fromOffset(44,44)});corner(avatar,22)
   text(card,"DisplayName","",68,14,120,22,14).Size=UDim2.new(1,-80,0,22)
   text(card,"Username","",68,38,120,16,10,true).Size=UDim2.new(1,-80,0,16)
   local statusDot=make("Frame","StatusDot",card,{Position=UDim2.fromOffset(12,72),Size=UDim2.fromOffset(6,6),BackgroundColor3=Color3.fromRGB(144,154,168),BackgroundTransparency=0});corner(statusDot,3);statusDot:SetAttribute("AltairThemeIgnore",true)
   text(card,"Status","",24,66,160,18,11,true).Size=UDim2.new(1,-38,0,18)
   text(card,"Location","",12,87,170,16,10,true).Size=UDim2.new(1,-24,0,16)
   local gameBadge=make("ImageLabel","GameIcon",card,{Visible=false,Position=UDim2.fromOffset(44,46),Size=UDim2.fromOffset(16,16),ZIndex=26});corner(gameBadge,4)
   local join=button(card,"Join","Join",12,110,90,24);accent(join,"Playerlist");join.ZIndex=27
   local more=button(card,"More","Profile",0,110,78,24);more.AnchorPoint=Vector2.new(1,0);more.Position=UDim2.new(1,-12,0,110);more.ZIndex=27
  end
  local states=transplant(old.Browser,browser,"States",20,132,1064,384);states.Size=UDim2.new(1,-40,1,-152)
  tileFlow(list,name)
  local detailsSurface=make("CanvasGroup","DetailsSurface",page,{Position=UDim2.fromOffset(728,0),Size=UDim2.fromOffset(376,536),Visible=false,GroupTransparency=1});surface(detailsSurface)
  local details=make("CanvasGroup","Details",page,{Position=UDim2.fromOffset(750,22),Size=UDim2.fromOffset(332,492),Visible=false,GroupTransparency=1})
  local close=button(detailsSurface,"CloseSelection","Back",278,14,78,28)
  local state={page=page,browser=browser,surface=detailsSurface,details=details,generation=0,internal=false};view.states[name]=state
  function view:SetSelection(key,selected,animate)
   local st=self.states[key];if not st then return end;st.generation+=1;local generation=st.generation
   st.internal=true;st.surface.Visible=true;st.details.Visible=true;st.internal=false
   for _,group in ipairs({st.surface,st.details})do group:SetAttribute("AltairHomeFade_GroupTransparency",selected and 0 or 1);group:SetAttribute("AltairHomePageFade_GroupTransparency",selected and 0 or 1)end
   local duration=animate==false and 0 or .3
   motion:Create(st.browser,TweenInfo.new(duration,Enum.EasingStyle.Quint),{Size=UDim2.fromOffset(selected and 704 or 1104,536)}):Play()
   motion:Create(st.surface,TweenInfo.new(duration),{GroupTransparency=selected and 0 or 1}):Play()
   motion:Create(st.details,TweenInfo.new(duration),{GroupTransparency=selected and 0 or 1}):Play()
   if not selected then task.delay(duration,function()if st.generation==generation and st.page.Parent then st.internal=true;st.surface.Visible=false;st.details.Visible=false;st.internal=false end end)end
  end
  if name=="Games"then
   local image=make("ImageLabel","Artwork",details,{Position=UDim2.fromOffset(0,36),Size=UDim2.fromOffset(332,166),ScaleType=Enum.ScaleType.Crop});corner(image,12)
   text(details,"Title","",0,220,332,44,22).TextWrapped=true
   text(details,"Creator","",0,270,332,18,12,true)
   button(details,"Play","Play experience",0,310,212,40);button(details,"Favorite","Save",224,310,108,40)
   text(details,"DescriptionTitle","ABOUT THIS EXPERIENCE",0,374,332,18,10,true)
   local desc=text(details,"Description","",0,404,332,86,12,true);desc.TextWrapped=true;desc.TextYAlignment=Enum.TextYAlignment.Top;desc.TextTruncate=Enum.TextTruncate.None
  else
   local avatar=make("ImageLabel","Avatar",details,{Position=UDim2.fromOffset(0,40),Size=UDim2.fromOffset(64,64)});corner(avatar,32)
   text(details,"DisplayName","",78,42,254,30,21)
   text(details,"Username","",78,78,254,18,12,true)
   local activity=section(details,"Activity",0,144,332,112)
   local icon=make("ImageLabel","GameIcon",activity,{Size=UDim2.fromOffset(42,42)});corner(icon,10)
   text(activity,"Status","",56,0,276,18,11,true);text(activity,"GameName","",56,22,276,22,14)
   button(activity,"Join","Join experience",0,62,332,38)
   text(details,"Availability","",0,270,332,18,11,true)
   text(details,"AboutTitle","ABOUT",0,306,332,18,10,true)
   local about=text(details,"About","",0,338,332,86,12,true);about.TextWrapped=true;about.TextYAlignment=Enum.TextYAlignment.Top;about.TextTruncate=Enum.TextTruncate.None
   button(details,"ViewProfile","View profile",0,452,218,38);button(details,"More","More",230,452,102,38)
  end
 end
 -- Runtime rows are created by the data controller; animate each new interaction.
 local motion=motionService()
 for _,list in ipairs(pages:GetDescendants())do if list:IsA("ScrollingFrame")and list:FindFirstChild("Template")then
  list.ChildAdded:Connect(function(row)
   if not row:IsA("GuiObject")or not row:GetAttribute("RuntimeEntry")then return end
   local hit=row:FindFirstChild("Interact")
   local scale=make("UIScale","HomeEntryMotion",row,{Scale=.985})
   motion:Create(scale,TweenInfo.new(.26,Enum.EasingStyle.Quint),{Scale=1}):Play()
   if hit and hit:IsA("GuiButton")then
    local rest=row.BackgroundTransparency
    hit.MouseEnter:Connect(function()motion:Create(row,TweenInfo.new(.18),{BackgroundTransparency=math.min(rest,.82)}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1.006}):Play()end)
    hit.MouseLeave:Connect(function()motion:Create(row,TweenInfo.new(.2),{BackgroundTransparency=rest}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1}):Play()end)
   end
  end)
 end end
 function view:SwapDetails(panel,update)
  local version=(panel:GetAttribute("AltairDetailVersion")or 0)+1;panel:SetAttribute("AltairDetailVersion",version)
  motion:Create(panel,TweenInfo.new(.08),{GroupTransparency=1}):Play()
  task.delay(.08,function()if panel.Parent and panel:GetAttribute("AltairDetailVersion")==version then update();motion:Create(panel,TweenInfo.new(.18),{GroupTransparency=0}):Play()end end)
 end
 -- Artwork changes use two rounded surfaces, with no full-screen wallpaper.
 local artworkGeneration=0
 function view:SetArtwork(images)
  artworkGeneration+=1;local generation=artworkGeneration
  self.images=images;self.artworkIndex=1
  if images[1]then art.Image=images[1]end
  task.spawn(function()
   while content.Parent and generation==artworkGeneration do
    task.wait(5)
    if not content.Parent or generation~=artworkGeneration then break end
    if #images>1 and content.Parent.Visible and not content.Parent:GetAttribute("AltairClosing")and home.Visible then
     self.artworkIndex=self.artworkIndex%#images+1;nextArt.Image=images[self.artworkIndex]
     local loaded=true;local ok=pcall(function()game:GetService("ContentProvider"):PreloadAsync({nextArt.Image},function(_,status)if status~=Enum.AssetFetchStatus.Success then loaded=false end end)end)
     if generation~=artworkGeneration then break end
     if ok and loaded then
      local reduced=root:GetAttribute("AltairReduceMotion");nextArt.Position=UDim2.fromScale(reduced and 0 or .12,0);nextArt.ImageTransparency=1
      motion:Create(nextArt,TweenInfo.new(.38,Enum.EasingStyle.Quint),{Position=UDim2.fromScale(0,0),ImageTransparency=.08}):Play()
      motion:Create(art,TweenInfo.new(.38,Enum.EasingStyle.Quint),{Position=UDim2.fromScale(reduced and 0 or -.08,0),ImageTransparency=1}):Play()
      task.wait(.4);if generation~=artworkGeneration then break end
      art.Image=nextArt.Image;art.Position=UDim2.fromScale(0,0);art.ImageTransparency=content.Parent:GetAttribute("AltairClosing")and 1 or .08;nextArt.ImageTransparency=1
     end
    end
   end
  end)
 end
 content.Destroying:Connect(function()artworkGeneration+=1 end)
 oldSidebar:Destroy();oldPages:Destroy();sidebar.Name="Sidebar";pages.Name="Pages"
 return view
end

local function createSharedSurface(root)
 local shell=Instance.new("Frame");shell.Name="SharedPanelSurface";shell.Visible=false;shell.BorderSizePixel=0;shell.BackgroundColor3=Color3.fromRGB(25,26,29);shell.BackgroundTransparency=.1;shell.Parent=root
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,18);corner.Parent=shell
 local stroke=Instance.new("UIStroke");stroke.Name="Outline";stroke.Color=Color3.fromRGB(160,166,180);stroke.Transparency=.65;stroke.Parent=shell
 local gradient=Instance.new("UIGradient");gradient.Name="Material";gradient.Parent=shell
 local scale=Instance.new("UIScale");scale.Name="AltairDisplayScale";scale.Parent=shell
end
-- A rounded Gaussian atlas has fully transparent borders: its nine-slice never
-- exposes a rectangular edge. Embedded so no uploaded Roblox asset is required.
local softShadowPNG="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"
local dragHaloPNG="iVBORw0KGgoAAAANSUhEUgAAAQAAAABACAYAAAD1Xam+AAAEQElEQVR42u3dy0sVYRzGcTO146W8pxlmFygkyQwpEhISo7ILRIuEWmhEdBFbVKvcBAoV2cLa1UqIFkFXhJZBizaBRAWBCzcFQlLQIkiK0zPwDAwHj9vmnPkuPv+Az+995p1xzjsF6XS6AEAy8UcAKAAAFAAACgAABQCAAgBAAQCgAABQAAAoAAAUAAAKAAAFAIACAEABAKAAAFAAuWIZ8hKzTQGwyEE5JLUAFgu+MIvlyCvZck50GSR14S+2yIuseAklyAlLZRjmvFg5JK4Ikrb4CzMWfLioV1hKSq0si3LEWrbcwlxTkbxLIqUQLYPElEASF3500YcLvUJWyiqplCqplpqIWuSUaHbVzrTSGa905mExRMsgUUWQpMVf5JBTkUVf6eGok9XSKE2yVpplnbVErEesRbMK82t2pk3OeLUzr/YMhGWQ8owUJaUEkrL4iyNX/ApfDYKrRIMHIxiWTbJZWqVNtkm7bJcO2YGc0uHs2p1lm7Pd7KxbnH2DZ6HKsxHuCIqTUAL5XACZi7/M278ah97sQWj1kHTKbumWvdIr++WAHJQ+OZThMGIhM5c+Z3bAGfY6025n3OnMWz0DzZ6JGs9I2RIlQAHk8OKv8zZwg8MPrhJd0uOhOSYn5JQMyBk5K+fkvFyIuIhYiWZz3pmddYYDzvSEM+5z5l2egVbPRJNnJDElkI8FkHnPHy7+Wge80dvBnR6CI9Ivp2VIrsg1uS5jckNuyW0ZlzuItXFndcvZjTnLa852yFn3O/sez0KbZ6PJsxKWwGLPBCiAHLn6p3xfV+2HP0HLb5Vdsk+Oy6BckhEPzITcl0l5JI/liTyT5/JCXiKWXjijZ87ssTOcdKYTznjEmQ96BvZ5JrZ6Rho9MxWeobzdBeRrAYRX/1I3eb3v87b4/q/HW8HgSnBZRuWuByUYnFfyWt7KO5mW9/JBPtonxEqYywdnNe3s3jrLV8520lmPOvvTnoUez8YWz0q9Z6c0sgugAHKgAMLt/wq/GFLlBzzrvc3r8j3gSRn29vCePJQpeePh+Syz8kXm5JvMy3f7gVgJc5l3VnPObtZZTjvbKWd9z9kPexb6PBttnpUGz065Zym8DaAAcuD+vzhSAMFWbo3v74Inv3vkqLd/V+WmPJCnvlIEgzIjXz1MP+WX/JYF+WN/ESthLgvO6pezm3eWM872tbN+4OyvehaOejbaPStrPDvlWR4GUgAUACgACoBbAHALQAHwEBA8BKQA+Dcg+DcgBcCLQOBFIAqAV4HBq8AUAD8GAj8GogD4OTD4OTAF8J9KgANBOBCEA0E4EowjwdIcCcaRYBwKyqGgaQ4F5VDQBBQAx4JzLDjHgvNhED4MkubDIHwYhE+D8Wkw8GkwCoByYJGDAgAoAAAUAAAKAAAFAIACAEABAKAAAFAAACgAABQAAAoAAAUAgAIAQAEAoAAAUAAA4uQffH5/SVxnODsAAAAASUVORK5CYII="
local smallShadowPNG="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAADvklEQVR42u2asUsjQRSHPS9qTEzUKCoGRTiLEEx1FoYDi2AlIhZ2ARHE6rAUrFIJVqkDVhZWgsWBtWAnCIH8AakEG7lG0ojG3G/hWwiLQd3EqJe38DWTmffm/d6bmd3NdtVqta5OpssEMAFMABPABDABTAATwARoD99eyX8lgDe47hdoqxjtCtwN7jsEGuD+/pwYX0aA54J2gusRvaIPgh7c9l76BhqI8WkF8GbcDdwNul+ExYCIikEPUX4L09cVo16IllfEe2S9PnAnsyEREUNiRIyJCTEp4jBJ2xh9hhgTwkYjIT6FAN7ge8heiKzGxDiBzohZkRBJMQdJ2mbpE2dMDBshbPa0WoT3CD5IKQ8TxBSBOYH+FGmxKDJiCTK0pekzx5gpbAxjM9hqEVodfD+lO0IWf4iUWCDIFbEusmJTbMEmbev0yTAmhY04NiP4aJkIzQrgDd4p11Ey55T0PMGsiQ3xW+yKnNgXB7BP2y59NhiTwUYCm6P4eE6Etgrgql5f9hEmOM2adsp5mczuEGBeHIpjcSJO4YS2Q/rkGJPFRhqb0/iIeJaD7ypoNvsBNqcBSnSKif4Sq5T3HkEdiT/iXFyKoihBkbZz+hwxZg8bq9hM4mMEn33MobudAtSXfi879DDrNEG2nAlvk8kCWb4g2LK4EbfiL9zSVqbPBWMK2NjGZhofcXyGmIPvpdBs9oOsyXE2q3lKdouJOyV9Jq4Izgm0Iu7Fo6jCI20V+pQZc4aNHDaX8fEDn1HmEGiXAPVr381+jLJMsWllKd0CATjlfS3uxIN4qjW+nuhzx5giNgrYzOIjhc+YpwrevBc0u/YjZGKWY2uNzStPCV8RSIVMv/aqMuYaG6fY3MHHAj7HmYPvvcCvAO6xN8R6nCMzG5TrEeu4TDbfEny9CHfYuMBmDh8ZfMaZg3ssvqsA3vIPsxvPcPe2whmeZycvsZ4fav6vB2yUsJnHxwo+Z5hD2O8y8Lv7u0ffGKWY5i5ul03rnMxVXljzL11P2Chj8xAf6/icZQ7ukfjm06CZ9R/lCS7BfXyWEj3mTL9hZ2/2usfWJbZz+FrE9wRz8bUPNHP8DfIYm2RNbnJLe8Lufcvx1uz1iK0itvfxlcH3JHMJfoQA7ga4xDl9wI5d4gan2gIBqtgqYfsAX0t1G6EJ8FECdOwS6OhNsKOPwY6+Eer4W2F7GLLHYXshYq/E7KWovRa3P0bsrzH7c9T+HrcPJOwTGftIyj6Tsw8l7VNZ+1jaBDABTAATwAQwAUwAE+Ar8w/lS/oANrvHMwAAAABJRU5ErkJggg=="
local softShadowAssets={}
local function resolveSoftShadowAsset(kind)
 local drag=kind==true or kind=="drag"
 local key=drag and "DragHalo-1" or kind=="small" and "SmallShadow-1" or "FeatheredShadow-1"
 if softShadowAssets[key] then return softShadowAssets[key] end
 local data=drag and dragHaloPNG or kind=="small" and smallShadowPNG or softShadowPNG
 local register=getcustomasset or getsynasset
 if type(writefile)~="function" or type(register)~="function" then return nil end
 local ok,result=pcall(function()
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local lookup={}
  for i=1,#alphabet do lookup[alphabet:byte(i)]=i-1 end
  local bytes={}
  for i=1,#data,4 do
   local a,b,c,d=data:byte(i,i+3);local n=(lookup[a] or 0)*262144+(lookup[b] or 0)*4096+(lookup[c] or 0)*64+(lookup[d] or 0)
   bytes[#bytes+1]=string.char(math.floor(n/65536)%256)
   if c~=61 then bytes[#bytes+1]=string.char(math.floor(n/256)%256)end
   if d~=61 then bytes[#bytes+1]=string.char(n%256)end
  end
  if type(makefolder)=="function" then for _,path in ipairs({"Altair","Altair/UI","Altair/UI/Assets"})do pcall(makefolder,path)end end
  local path="Altair/UI/Assets/"..key..".png"
  if type(isfile)~="function" or not isfile(path)then writefile(path,table.concat(bytes))end
  return register(path)
 end)
 if ok then softShadowAssets[key]=result end
 return softShadowAssets[key]
end
local function bindSoftShadows(root)
 local asset=resolveSoftShadowAsset();local dragAsset=resolveSoftShadowAsset(true);local smallAsset=resolveSoftShadowAsset("small");
 if asset then local preload={asset};if dragAsset then preload[#preload+1]=dragAsset end;if smallAsset then preload[#preload+1]=smallAsset end;pcall(function()game:GetService("ContentProvider"):PreloadAsync(preload)end)end
 local connections={};local records=setmetatable({}, {__mode="k"});local count=0
 local function connect(list,signal,callback)local c=signal:Connect(callback);list[#list+1]=c;return c end
 local function atlas(image,small)
  image.Image=small and smallAsset or asset;image.ScaleType=Enum.ScaleType.Slice;image.SliceCenter=small and Rect.new(31,31,33,33) or Rect.new(72,72,88,88);image.SliceScale=1
  image.ImageRectOffset=Vector2.zero;image.ImageRectSize=Vector2.zero;image.BackgroundTransparency=1
 end
 local addSurface
 local function replaceLegacy(image)
  if records[image]then return end
  if asset and image.Parent.Parent==root then
   image:SetAttribute("AltairFeatheredShadow",true)
   addSurface(image.Parent,.05,image.ImageColor3,48,nil,image);image.Image="";return
  end
  records[image]=true;count+=1
  if asset then
   local small=smallAsset and math.min(image.Parent.AbsoluteSize.X,image.Parent.AbsoluteSize.Y)<48*(root:GetAttribute("AltairDisplayScale") or 1)
   local spread=small and 48 or 96;atlas(image,small);image.AnchorPoint=Vector2.new(.5,.5);image.Position=UDim2.fromScale(.5,.5);image.Size=UDim2.new(1,spread,1,spread)
   image:SetAttribute("AltairFeatheredShadow",true)
   if image.Parent.Name=="Knob"then
    image.Size=UDim2.new(1,24,1,24);image.SliceScale=.5;image:SetAttribute("AltairGlowCap",.1);image.ImageTransparency=math.max(.9,image.ImageTransparency)
    image.Parent.BackgroundColor3=Color3.fromRGB(226,235,247)
    local center=image.Parent:FindFirstChild("Center");if center then center.BackgroundColor3=Color3.fromRGB(226,235,247)end
   else image:SetAttribute("AltairGlowCap",.18);image.ImageTransparency=math.max(.82,image.ImageTransparency)end
  else
   local ok,shadow=pcall(Instance.new,"UIShadow");if not ok then return end
   shadow.Name="SoftShadow";shadow.BlurRadius=UDim.new(0,18);shadow.ZIndex=-1;shadow.Parent=image.Parent
   image.Image=""
   local function update()shadow.Color=image.ImageColor3;shadow.Transparency=image.Visible and image.ImageTransparency or 1 end
   connect(connections,image:GetPropertyChangedSignal("ImageTransparency"),update);connect(connections,image:GetPropertyChangedSignal("ImageColor3"),update);connect(connections,image:GetPropertyChangedSignal("Visible"),update);update()
  end
 end
 addSurface=function(source,strength,color,padding,material,legacy)
  material=material or source
  local handle=source==root.Drag.Drag
  local small=not handle and source.Parent~=root and not source:GetAttribute("AltairSurface")and smallAsset and math.min(source.AbsoluteSize.X,source.AbsoluteSize.Y)<48*(root:GetAttribute("AltairDisplayScale") or 1)
  if small then padding=math.min(padding,24)end
  local key=legacy or source
  if records[key]then return end
  records[key]=true;count+=1;local localConnections={};local ancestorConnections={};local shadow
  if asset then
   shadow=Instance.new("ImageLabel");shadow.Name="SoftShadow";shadow:SetAttribute("AltairFeatheredShadow",true);shadow:SetAttribute("AltairShadowFor",source.Name)
   atlas(shadow,small);if handle and dragAsset then shadow.Image=dragAsset;shadow.SliceCenter=Rect.new(64,0,192,64)end
   shadow.AnchorPoint=Vector2.new(.5,.5);shadow.ImageColor3=color;shadow.ImageTransparency=1;shadow.Parent=root
  else
   local ok,value=pcall(Instance.new,"UIShadow");if not ok then return end
   shadow=value;shadow.Name="SoftShadow";shadow.BlurRadius=UDim.new(0,padding/3);shadow.Color=color;shadow.ZIndex=-1;shadow.Parent=source
  end
  local function update()
   if not source.Parent or not shadow.Parent then return end
   local opacity=legacy and (legacy.Visible and math.min(source.Name=="SmartBar"and root:GetAttribute("AltairThemePulse")and .2 or .08,(1-legacy.ImageTransparency)*.45)or 0)or(1-material.BackgroundTransparency)*strength;local current=material
   while current and current~=root do
    if current:IsA("GuiObject") and not current.Visible then opacity=0;break end
    if current:IsA("CanvasGroup")then opacity*=1-current.GroupTransparency end
    current=current.Parent
   end
   if asset then
    local position=source.AbsolutePosition-root.AbsolutePosition;local size=source.AbsoluteSize
    local factor=1;local parent=source
    while parent and parent~=root do for _,child in ipairs(parent:GetChildren())do if child:IsA("UIScale")then factor*=child.Scale end end;parent=parent.Parent end
    shadow.Position=UDim2.fromOffset(position.X+size.X/2,position.Y+size.Y/2);shadow.Size=UDim2.fromOffset(size.X+padding*2*factor,size.Y+padding*2*factor)
    if handle and dragAsset then local vertical=size.Y>size.X;shadow.Rotation=(vertical and 90 or 0)+source.Rotation;shadow.Size=UDim2.fromOffset((vertical and size.Y or size.X)+128*factor,64*factor);shadow.SliceScale=factor else shadow.SliceScale=padding/(small and 24 or 48)*factor end
    shadow.ZIndex=legacy and legacy.ZIndex or math.max(0,source.ZIndex-1);shadow.ImageTransparency=1-opacity
    shadow.ImageColor3=legacy and legacy.ImageColor3 or handle and source.BackgroundColor3 or color
   else shadow.Transparency=1-opacity end
  end
  local queued=false
  local function queueUpdate()if queued then return end;queued=true;task.defer(function()queued=false;update()end)end
  local function ancestors()
   for _,c in ipairs(ancestorConnections)do c:Disconnect()end;table.clear(ancestorConnections)
   local current=material
   while current and current~=root do
    if current:IsA("GuiObject")then connect(ancestorConnections,current:GetPropertyChangedSignal("Visible"),update)end
    if current:IsA("CanvasGroup")then connect(ancestorConnections,current:GetPropertyChangedSignal("GroupTransparency"),update)end
    current=current.Parent
   end
   queueUpdate()
  end
  if legacy then
   for _,property in ipairs({"ImageTransparency","ImageColor3","Visible","ZIndex"})do connect(localConnections,legacy:GetPropertyChangedSignal(property),update)end
   local gradient=legacy:FindFirstChildOfClass("UIGradient")
   if gradient then local copy=gradient:Clone();copy.Parent=shadow;for _,property in ipairs({"Color","Transparency","Rotation","Offset","Enabled"})do connect(localConnections,gradient:GetPropertyChangedSignal(property),function()copy[property]=gradient[property]end)end end
  end
  if handle then connect(localConnections,source:GetPropertyChangedSignal("BackgroundColor3"),update)end
  for _,property in ipairs({"AbsolutePosition","AbsoluteSize","Rotation","ZIndex","BackgroundTransparency"})do connect(localConnections,source:GetPropertyChangedSignal(property),queueUpdate)end
  if material~=source then connect(localConnections,material:GetPropertyChangedSignal("BackgroundTransparency"),update)end
  connect(localConnections,source.AncestryChanged,ancestors)
  connect(localConnections,source.Destroying,function()
   for _,c in ipairs(localConnections)do c:Disconnect()end;for _,c in ipairs(ancestorConnections)do c:Disconnect()end
   if shadow.Parent then shadow:Destroy()end
  end)
  connect(connections,root.Destroying,function()for _,c in ipairs(localConnections)do c:Disconnect()end;for _,c in ipairs(ancestorConnections)do c:Disconnect()end end)
  ancestors()
 end
 local primary={Character=true,Scripts=true,Playerlist=true,Settings=true,ScriptSearch=true,CustomScriptPrompt=true,GameDetection=true,ModeratorDetectionPrompt=true,Disconnected=true,SecurityPrompt=true,SharedPanelSurface=true}
 local function inspect(object)
  if not object.Parent or object:GetAttribute("AltairFeatheredShadow")then return end
  if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and (object.Name=="Shadow" or object.Name=="Glow")then replaceLegacy(object)
  elseif object:IsA("GuiObject")then
   if object.Parent==root and primary[object.Name]and not object:FindFirstChild("Shadow")then addSurface(object,.05,Color3.fromRGB(160,166,180),48)
   elseif object.Name=="Content"and object.Parent.Name=="Home"and not object:GetAttribute("AltairHomeRedesign")then addSurface(object,.05,Color3.fromRGB(160,166,180),48)
   elseif object==root.Drag.Drag then addSurface(object,.5,object.BackgroundColor3,30)
   elseif object.Name=="Surface" and object.Parent.Name=="TopCapsules"then addSurface(object,.04,Color3.fromRGB(160,166,180),48)
   elseif object.Name:match("^Notification_%d+$") or (object.Parent.Name=="Pills" and object.Parent.Parent.Name=="Compact")then local visual=object:FindFirstChild("Visual");addSurface(object,.03,Color3.fromRGB(160,166,180),24,object:FindFirstChild("CardBackground")or(visual and visual:FindFirstChild("Back")))end
  end
 end
 for _,object in ipairs(root:GetDescendants())do inspect(object)end
 connect(connections,root.DescendantAdded,function(object)task.defer(function()if root.Parent then inspect(object)end end)end)
 connect(connections,root.Destroying,function()for _,c in ipairs(connections)do c:Disconnect()end end)
 return {mode=asset and "feathered-image" or "native",Count=function()return count end}
end

local function styleSettings(root)
 local panel=root.Settings;local types=panel.SettingTypes
 if not types:IsA("ScrollingFrame")then
  local scroller=Instance.new("ScrollingFrame");scroller.Name="SettingTypes";scroller.BackgroundTransparency=1;scroller.BorderSizePixel=0;scroller.ZIndex=types.ZIndex;scroller.Visible=types.Visible
  scroller.ScrollingDirection=Enum.ScrollingDirection.Y;scroller.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroller.CanvasSize=UDim2.new();scroller.ScrollBarThickness=2;scroller.ScrollBarImageTransparency=.5
  for _,child in ipairs(types:GetChildren())do child.Parent=scroller end
  types:Destroy();scroller.Parent=panel;types=scroller
 end
 local template=types.Template
	types.Position=UDim2.fromOffset(14,68);types.Size=UDim2.new(0,158,1,-84);types.ClipsDescendants=true
	local padding=Instance.new("UIPadding");padding.PaddingLeft=UDim.new(0,4);padding.PaddingTop=UDim.new(0,3);padding.PaddingBottom=UDim.new(0,8);padding.Parent=types
	local grid=types.UIGridLayout
	grid.CellSize=UDim2.new(1,-8,0,40);grid.CellPadding=UDim2.fromOffset(0,6)
	grid.HorizontalAlignment=Enum.HorizontalAlignment.Center
	grid.FillDirectionMaxCells=1;grid.SortOrder=Enum.SortOrder.LayoutOrder
	template.UICorner.CornerRadius=UDim.new(0,11)
	template.Title.Position=UDim2.fromOffset(38,10);template.Title.Size=UDim2.new(1,-43,0,20)
	template.Title.TextXAlignment=Enum.TextXAlignment.Left;template.Title.TextYAlignment=Enum.TextYAlignment.Center
	template.Title.TextSize=11;template.Title.FontFace=Font.new(Font.fromEnum(Enum.Font.Roboto).Family,Enum.FontWeight.Medium)
	template.Shadow.Visible=false;template.UIStroke.Thickness=1;template.UIStroke.Transparency=.4
	local description=Instance.new("TextLabel")
	description.Name="Description";description.BackgroundTransparency=1;description.Position=UDim2.fromOffset(47,35)
	description.Size=UDim2.new(1,-59,0,15);description.TextSize=10;description.FontFace=Font.fromEnum(Enum.Font.Roboto)
	description.TextColor3=Color3.fromRGB(210,210,218);description.TextXAlignment=Enum.TextXAlignment.Left
	description.TextTruncate=Enum.TextTruncate.AtEnd;description.Text="";description.ZIndex=template.Title.ZIndex;description.Parent=template
 local icon=Instance.new("ImageLabel");icon.Name="CategoryIcon";icon.BackgroundTransparency=1;icon.Position=UDim2.fromOffset(11,12);icon.Size=UDim2.fromOffset(16,16);icon.ImageColor3=Color3.fromRGB(235,239,250);icon.ZIndex=template.Title.ZIndex;icon.Parent=template
 local header=icon:Clone();header.Name="HeaderIcon";header.Position=UDim2.fromOffset(18,15);header.Parent=panel;applyIcon(header,"settings-2")
 panel.Title.AnchorPoint=Vector2.zero;panel.Title.TextXAlignment=Enum.TextXAlignment.Left;panel.Subtitle.Visible=false;panel.Title.TextSize=16;panel.Title.Size=UDim2.fromOffset(122,22);panel.Subtitle.TextSize=11;panel.Subtitle.Size=UDim2.fromOffset(122,18);panel.ClipsDescendants=true
 description.Visible=false
 panel.SettingLists.ClipsDescendants=true
 local pages=panel.SettingLists.UIPageLayout;pages.Animated=true;pages.TweenTime=.24;pages.EasingStyle=Enum.EasingStyle.Quint;pages.EasingDirection=Enum.EasingDirection.Out;pages.Padding=UDim.new(0,14);pages.ScrollWheelInputEnabled=false;pages.TouchInputEnabled=false
 panel.SettingLists.Position=UDim2.fromOffset(184,76);panel.SettingLists.Size=UDim2.new(1,-198,1,-92)
 local divider=Instance.new("Frame");divider.Name="SidebarDivider";divider.Position=UDim2.fromOffset(178,62);divider.Size=UDim2.new(0,1,1,-78);divider.BorderSizePixel=0;divider.BackgroundColor3=Color3.fromRGB(100,110,130);divider.BackgroundTransparency=.65;divider.ZIndex=panel.Title.ZIndex;divider.Parent=panel
 local title=panel.Title:Clone();title.Name="ContentTitle";title.AnchorPoint=Vector2.zero;title.TextXAlignment=Enum.TextXAlignment.Left;title.Position=UDim2.fromOffset(198,20);title.Size=UDim2.new(1,-220,0,24);title.Text="General";title.Parent=panel
 local subtitle=panel.Subtitle:Clone();subtitle.Name="ContentSubtitle";subtitle.AnchorPoint=Vector2.zero;subtitle.Visible=true;subtitle.TextXAlignment=Enum.TextXAlignment.Left;subtitle.Position=UDim2.fromOffset(198,46);subtitle.Size=UDim2.new(1,-220,0,18);subtitle.TextTruncate=Enum.TextTruncate.AtEnd;subtitle.Parent=panel


end

-- CAPSULES BEGIN: layout, Molto icons, and bindings are authored here.
local function bindCapsules(context)
	local root, Clock = context.Root, context.Clock
	local runService, input = game:GetService("RunService"), game:GetService("UserInputService")
	local tweenService, http = motionService(function() return root:GetAttribute("AltairReduceMotion")==true end), game:GetService("HttpService")
	local lighting = game:GetService("Lighting")
	local white, gray, amber, green = Color3.fromRGB(249,249,250), Color3.fromRGB(145,145,149), Color3.fromRGB(255,177,29), Color3.fromRGB(55,224,92)
	local normal = Font.fromEnum(Enum.Font.Roboto)
	local medium = Font.new(normal.Family, Enum.FontWeight.Bold)
	local controller = {alive=true, clock=Clock and Clock.new() or nil, view=nil, media={connected=false,title="Spotify",artist=""},
		mediaAt=os.clock(), nextPoll=0, failures=0, connections={}, tweens=setmetatable({}, {__mode="k"}),
		lastErrorAt=-math.huge, commandBusy=false, requestBusy=false, picker=false, layoutAt=0}
	local clock = controller.clock
	local function get(name, fallback)
		local value=context.GetSetting and context.GetSetting(name,fallback)
		if value==nil then return fallback end
		return value
	end
	local function connect(signal, fn)
		if context.BuildOnly then return nil end
		local connection = signal:Connect(function(...) if controller.alive then fn(...) end end)
		controller.connections[#controller.connections+1] = connection; return connection
	end
	local function make(class, parent, properties)
		local existing=parent and parent:FindFirstChild(properties.Name or class)
		if context.RequireBuiltUI then
			assert(existing and existing.ClassName==class,"Build.lua is missing capsule object: "..(properties.Name or class))
			return existing
		end
		local object = Instance.new(class)
		if object:IsA("GuiObject") then object.ZIndex=291 end
		for key,value in pairs(properties) do object[key]=value end
		object.Parent=parent; return object
	end
	local function corner(parent, radius) make("UICorner",parent,{CornerRadius=UDim.new(0,radius)}) end
	local function frame(parent,name,x,y,w,h,color,radius)
		local object=make("Frame",parent,{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			BackgroundColor3=color or Color3.fromRGB(28,28,29),BackgroundTransparency=color and 0 or 1,BorderSizePixel=0})
		if radius then corner(object,radius) end
		return object
	end
	local function label(parent,name,text,x,y,w,h,size,color)
		return make("TextLabel",parent,{Name=name,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			TextSize=size or 12,TextColor3=color or white,FontFace=normal,BackgroundTransparency=1,RichText=false,
			TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left})
	end
	local function button(parent,name,text,x,y,w,h,color,action)
		local object=make("TextButton",parent,{Name=name,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			FontFace=medium,TextSize=12,TextColor3=white,BackgroundColor3=color or Color3.fromRGB(28,28,29),
			BackgroundTransparency=color and 0 or 1,BorderSizePixel=0,AutoButtonColor=false})
		corner(object,math.min(12,h/2))
		connect(object.Activated,action)
		if not color then object.BackgroundColor3=Color3.new(1,1,1) end
		connect(object.MouseEnter,function()
			if not color and not object:GetAttribute("NoHover") then tweenService:Create(object,TweenInfo.new(.12),{BackgroundTransparency=.92}):Play() end
		end)
		connect(object.MouseLeave,function()
			if not color and not object:GetAttribute("NoHover") then tweenService:Create(object,TweenInfo.new(.12),{BackgroundTransparency=1}):Play() end
		end)
		return object
	end
	local function set(object,property,value) if object[property]~=value then object[property]=value end end
	local function tween(object,time,properties,style,direction)
		-- Keep opacity and geometry independent during interrupted motion.
		local animation=tweenService:Create(object,TweenInfo.new(time,style or Enum.EasingStyle.Quint,direction or Enum.EasingDirection.Out),properties)
		controller.tweens[object]=animation
		animation.Completed:Once(function() if controller.tweens[object]==animation then controller.tweens[object]=nil end end)
		animation:Play();return animation
	end
	-- Molto sprite rectangles preserve the provider artwork.
	local function icon(parent,name,kind,x,y,size,color)
		local object=make("ImageLabel",parent,{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(size,size),
			BackgroundTransparency=1,ImageColor3=color or white,
			ScaleType=Enum.ScaleType.Fit,ZIndex=parent.ZIndex+1})
		applyIcon(object,kind);return object
	end

	local artworkTargets={}
	local function artwork(parent,x,y,size,radius,noteX,noteY,noteSize)
		local tile=frame(parent,"Artwork",x,y,size,size,Color3.fromRGB(34,34,35),radius)
		local cover=make("ImageLabel",tile,{Name="Cover",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
			Image="",Visible=false,ScaleType=Enum.ScaleType.Crop,ZIndex=tile.ZIndex+1})
		corner(cover,radius)
		local note=icon(parent,"Note","eighth-note",noteX,noteY,noteSize,gray)
		artworkTargets[#artworkTargets+1]={cover=cover,note=note}
	end
	local function showArtwork(asset)
		for _,target in ipairs(artworkTargets) do
			target.cover.Image=asset or "";target.cover.Visible=asset~=nil;target.note.Visible=asset==nil
		end
	end
	local artworkCache,artworkSlots={},{}
	local artworkSlot=0
	local function updateArtwork(url)
		url=type(url)=="string"and(url:match("^https://i%.scdn%.co/image/[a-zA-Z0-9]+$")or url:match("^altair%-desktop:[a-f0-9]+$"))and url or nil
		if controller.artworkURL==url then return end
		controller.artworkURL=url;controller.artworkGeneration=(controller.artworkGeneration or 0)+1
		local generation=controller.artworkGeneration
		showArtwork(url and artworkCache[url] or nil)
		if not url or artworkCache[url] then return end
		if controller.artworkBusy then controller.artworkPending=true;return end
		local register=getcustomasset or getsynasset
		if type(register)~="function" or type(writefile)~="function" or type(context.Request)~="function" then return end
		controller.artworkBusy=true
		task.spawn(function()
			local ok,asset=pcall(function()
				-- Public artwork request carries no account token or companion bridge key.
				local requestURL,headers=url,nil
                local desktop=url:match("^altair%-desktop:([a-f0-9]+)$")
                if desktop then
                 assert(#desktop==64,"Invalid cover identifier")
                 local port=math.clamp(math.floor(tonumber(get("Spotify Bridge Port",43827))or 43827),1024,65535)
                 requestURL="http://127.0.0.1:"..port.."/v1/artwork/"..desktop
                 headers={Authorization="Bearer "..tostring(get("Spotify Bridge Key",""))}
                end
                local response=context.Request({Url=requestURL,Headers=headers,Method="GET",Timeout=8})
				local status=tonumber(response.StatusCode or response.Status) or 0
				local bytes=response.Body
				assert(status==200 and type(bytes)=="string" and #bytes>8 and #bytes<=1048576,"Artwork unavailable")
				assert(bytes:sub(1,2)==string.char(255,216) or bytes:sub(1,8)==string.char(137).."PNG\r\n"..string.char(26).."\n","Invalid artwork image")
				if not controller.alive or generation~=controller.artworkGeneration then return nil end
				if type(makefolder)=="function" then pcall(makefolder,"Altair");pcall(makefolder,"Altair/UI");pcall(makefolder,"Altair/UI/Artwork") end
				artworkSlot=artworkSlot%4+1
				local previous=artworkSlots[artworkSlot];if previous then artworkCache[previous]=nil end
				local file="Altair/UI/Artwork/cover-"..artworkSlot..".jpg"
				writefile(file,bytes);local result=register(file)
				artworkCache[url]=result;artworkSlots[artworkSlot]=url
				return result
			end)
			controller.artworkBusy=false
			if controller.alive and generation==controller.artworkGeneration and ok and asset then showArtwork(asset) end
			if controller.alive and controller.artworkPending then
				controller.artworkPending=false;local pending=controller.artworkURL;controller.artworkURL=nil;updateArtwork(pending)
			end
		end)
	end
	local host=frame(root,"TopCapsules",0,12,300,180)
	host.AnchorPoint,host.Position,host.ZIndex=Vector2.new(0.5,0),UDim2.new(0.5,0,0,12),290
	local scale=make("UIScale",host,{Scale=1.25})
	local compact=make("CanvasGroup",host,{Name="Compact",Size=UDim2.fromOffset(300,32),BackgroundTransparency=1})
	compact.AnchorPoint=Vector2.new(.5,0);compact.Position=UDim2.new(.5,0,0,-4)
	local compactFit=make("UIScale",compact,{Name="FitScale",Scale=1})
	local strip=make("Frame",compact,{Name="Pills",AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(.5,0,0,4),
		Size=UDim2.fromOffset(250,24),BackgroundTransparency=1})
	local pillLayout=make("UIListLayout",strip,{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,
		VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
	local smartBar=root:FindFirstChild("SmartBar")
	local barColor=smartBar and smartBar.BackgroundColor3 or Color3.fromRGB(30,30,30)
	local baseColor=barColor
	local controlColor=smartBar and smartBar.Back.BackgroundColor3:Lerp(baseColor,.35) or Color3.fromRGB(40,40,41)
	local surface=frame(host,"Surface",0,0,300,24,baseColor,12)
	surface.BackgroundTransparency=.08
	surface.AnchorPoint,surface.Position,surface.Visible,surface.ClipsDescendants=Vector2.new(.5,0),UDim2.fromScale(.5,0),false,true
	-- Share the SmartBar's charcoal finish and fine border across both capsule states.
	local sourceStroke=smartBar and smartBar:FindFirstChildOfClass("UIStroke")
	local outline=surface:FindFirstChild("CapsuleOutline") or (sourceStroke and sourceStroke:Clone()) or Instance.new("UIStroke")
	outline:SetAttribute("AltairSurfaceOutline",nil);outline:SetAttribute("AltairInsetOutline",nil)
 outline.Name="CapsuleOutline";outline.Color=white;outline.Transparency=.45;outline.Thickness=1
	outline.Enabled=true;outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;outline.Parent=surface
	local inner=frame(surface,"Back",5,5,0,0,smartBar and smartBar.Back.BackgroundColor3 or Color3.fromRGB(50,50,50),16)
	inner.Size=UDim2.new(1,-10,1,-10);inner.BackgroundTransparency=.1
	local innerStroke=make("UIStroke",inner,{Name="InnerOutline",Color=white,Thickness=1,Transparency=.65,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
	local accentOutlines={outline,innerStroke}
	local function barTile(object,sourceName)
		local source=smartBar and smartBar.Back.Buttons:FindFirstChild(sourceName)
		local gradient=source and source:FindFirstChildOfClass("UIGradient")
		object.BackgroundColor3=Color3.new(1,1,1)
		make("UIGradient",object,{Name="TileGradient",Rotation=90,
			Color=gradient and gradient.Color or ColorSequence.new(controlColor,barColor)})
	end
	-- The collapsing shell takes on the source pill's material before handoff.
	local morphMaterial=frame(surface,"MorphMaterial",2,2,0,0,Color3.new(1,1,1),12)
	morphMaterial.Size=UDim2.new(1,-4,1,-4);morphMaterial.BackgroundTransparency=1
	local morphGradient=make("UIGradient",morphMaterial,{Name="MaterialGradient",Rotation=90,Color=ColorSequence.new(baseColor)})
	local function syncMorphMaterial(source)
		local visual=source and (source:FindFirstChild("Visual") or source)
		local back=visual and visual:FindFirstChild("Back")
		local gradient=back and back:FindFirstChildOfClass("UIGradient")
		morphMaterial.BackgroundColor3=back and back.BackgroundColor3 or baseColor
		morphGradient.Color=gradient and gradient.Color or ColorSequence.new(baseColor)
		morphGradient.Rotation=gradient and gradient.Rotation or 90
	end
	local views,pills={},{}
	local function view(name,w,h)
		local v=make("CanvasGroup",surface,{Name=name,Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,GroupTransparency=1,Visible=false})
		views[name]=v;return v
	end
	local center=view("center",300,146)
	local music=view("music",220,82)
	local timer=view("timer",208,68)
	local watch=view("watch",208,94)
	local duration=view("duration",300,166)
	local morphChevron=icon(surface,"MorphChevron","chevron-down",0,0,12,white)
	morphChevron.AnchorPoint=Vector2.new(.5,.5);morphChevron.Position=UDim2.fromScale(.5,.5);morphChevron.ImageTransparency=1
	local sizes={}
	local pillNames={center="ControlCenter",music="Music",timer="Timer",watch="Stopwatch",duration="Timer"}
	for name,group in pairs(views) do sizes[name]=Vector2.new(group.Size.X.Offset,group.Size.Y.Offset) end
	function controller:Open(name)
		assert(name==nil or sizes[name],"Unknown capsule view")
		if self.picker and name~="duration" then return end
		if name==self.view then return end
        if self.restoreMusicCarry then self.restoreMusicCarry();self.restoreMusicCarry=nil end
        if self.restoreReturningMusic then self.restoreReturningMusic();self.restoreReturningMusic=nil end
        if self.musicCarry then self.musicCarry:Destroy();self.musicCarry=nil end
        if self.circleCarry then self.circleCarry:Destroy();self.circleCarry=nil end
        local liveMusic=views.music
        if liveMusic:FindFirstChild("Title") then liveMusic.Title.Visible=true end
        if liveMusic:FindFirstChild("Artwork") then liveMusic.Artwork.Visible=true end
		local previous=self.view
		self.view=name;self.transition=(self.transition or 0)+1
		local transition=self.transition
		self.finishMorph=nil
		if self.cancelDrag then self.cancelDrag() end
		for key,group in pairs(views) do
			if key~=name then
				tween(group,.12,{GroupTransparency=1})
				task.delay(.12,function() if self.alive and self.view~=key then group.Visible=false end end)
			end
		end
		if not name then
			compact.Visible=false;compact.GroupTransparency=1
			local origin=self.origin or {x=150,width=24}
			syncMorphMaterial(origin.source)
            if previous=="music" and origin.source and origin.source.Name=="Music" then
             local carry=Instance.new("Frame");carry.Name="ClosingMusicContent";carry.BackgroundTransparency=1;carry.Size=UDim2.fromScale(1,1);carry.ZIndex=surface.ZIndex+5;carry.Parent=surface;self.musicCarry=carry
             local sourceVisual=origin.source:FindFirstChild("Visual");local records={}
             for _,key in ipairs({"Title","Artwork"}) do
              local original=views.music:FindFirstChild(key);local actual=sourceVisual and sourceVisual:FindFirstChild(key)
              if original and actual then
               local record={object=actual,parent=actual.Parent,position=actual.Position,size=actual.Size,z={}}
               for _,v in ipairs({actual,table.unpack(actual:GetDescendants())})do if v:IsA("GuiObject")then record.z[v]=v.ZIndex;v.ZIndex=carry.ZIndex+1 end end
               if key=="Title"then record.textSize=actual.TextSize;actual.TextSize=original.TextSize end
               records[#records+1]=record;actual.Parent=carry;actual.Position=original.Position;actual.Size=original.Size;original.Visible=false
               if key=="Title"then tween(actual,.38,{Position=UDim2.fromOffset(27,0),Size=record.size,TextSize=record.textSize})
               else tween(actual,.38,{Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(18,18)}) end
              end
             end
             self.restoreMusicCarry=function()
              for _,record in ipairs(records)do
               local actual=record.object;actual.Parent=record.parent;actual.Position=record.position;actual.Size=record.size
               if record.textSize then actual.TextSize=record.textSize end
               for object,z in pairs(record.z)do if object.Parent then object.ZIndex=z end end
              end
             end
             local circle=strip.ControlCenter:Clone();circle.Name="ReturningCircle";circle.AnchorPoint=Vector2.new(.5,0);circle.ZIndex=surface.ZIndex+4;circle.Parent=host;circle.Position=UDim2.fromOffset(surface.Position.X.Offset-surface.Size.X.Offset/2-17,0);self.circleCarry=circle
             for _,object in ipairs({circle,table.unpack(circle:GetDescendants())}) do
              local goal={}
              if object:IsA("GuiObject") then goal.BackgroundTransparency=object.BackgroundTransparency;object.BackgroundTransparency=1;object.ZIndex=circle.ZIndex end
              if object:IsA("ImageLabel") then goal.ImageTransparency=object.ImageTransparency;object.ImageTransparency=1 end
              if object:IsA("UIStroke") then goal.Transparency=object.Transparency;object.Transparency=1 end
              if next(goal) then tween(object,.12,goal) end
             end
            end


            if previous=="center" and strip:FindFirstChild("Music") and strip.Music.Visible then
             local actual=strip.Music;local saved={parent=strip,position=actual.Position,anchor=actual.AnchorPoint}
             local slot=Instance.new("Frame");slot.Name="MusicReturnSlot";slot.Size=actual.Size;slot.LayoutOrder=actual.LayoutOrder;slot.BackgroundTransparency=1;slot.Parent=strip
             actual.Visual.GroupTransparency=1;actual.Parent=host;actual.AnchorPoint=Vector2.new(.5,0);self.returningMusic=actual
             tween(actual.Visual,.12,{GroupTransparency=0})
             self.restoreReturningMusic=function()
              actual.Parent=saved.parent;actual.AnchorPoint=saved.anchor;actual.Position=saved.position;slot:Destroy();self.returningMusic=nil
             end
            end
			tween(morphMaterial,.14,{BackgroundTransparency=origin.source and .18 or 1})
			-- Remove the inner material before the outer shell reaches its circle.
			tween(inner,.06,{BackgroundTransparency=1})
			tween(innerStroke,.1,{Transparency=1})
			tween(morphChevron,.24,{ImageTransparency=origin.width<=26 and 0 or 1})
			self.morphTarget={x=origin.x,width=origin.width,height=24}
			tween(surface,.2,{BackgroundTransparency=.08})
			tween(outline,.38,{Transparency=.45})
			self.finishMorph=function()
				if self.alive and transition==self.transition then
					compact.Visible=true;compact.GroupTransparency=1
                    if self.restoreMusicCarry then self.restoreMusicCarry();self.restoreMusicCarry=nil end
                    if self.restoreReturningMusic then self.restoreReturningMusic();self.restoreReturningMusic=nil end
                    compact.GroupTransparency=0;surface.Visible=false
                    if self.musicCarry then self.musicCarry:Destroy();self.musicCarry=nil end
                    if self.circleCarry then self.circleCarry:Destroy();self.circleCarry=nil end
				end
			end
		else
			if not previous or name=="center" then
				local source=strip:FindFirstChild(pillNames[name] or "ControlCenter")
				local factor=math.max(.01,scale.Scale)
				local x=source and ((source.AbsolutePosition.X+source.AbsoluteSize.X/2-host.AbsolutePosition.X)/factor) or 150
				local width=source and source.AbsoluteSize.X/factor or 24
				self.origin={x=x,width=width,source=source}
				if not previous then syncMorphMaterial(source);morphMaterial.BackgroundTransparency=source and .18 or 1 end
				if not surface.Visible then surface.Size=UDim2.fromOffset(width,24);surface.Position=UDim2.fromOffset(x,0);self.morphState=nil end
				surface.BackgroundTransparency=0
			end
			compact.Visible=true
            tween(compact,.1,{GroupTransparency=1})
            task.delay(.12,function() if self.alive and transition==self.transition and self.view~=nil then compact.Visible=false end end)
			tween(morphMaterial,.12,{BackgroundTransparency=1})
			tween(inner,.24,{Position=UDim2.fromOffset(5,5),Size=UDim2.new(1,-10,1,-10),BackgroundTransparency=.1})
			tween(innerStroke,.36,{Transparency=.65})
			if not previous then morphChevron.ImageTransparency=self.origin.width<=26 and 0 or 1 end
			tween(morphChevron,.16,{ImageTransparency=1})
			local size=sizes[name]
			surface.Visible=true;views[name].Visible=true;views[name].GroupTransparency=1
			self.morphTarget={x=host.Size.X.Offset*.5,width=size.X,height=size.Y}
			tween(surface,.24,{BackgroundTransparency=.08})
			tween(outline,.28,{Transparency=.45})
			task.delay(.06,function()
				if self.alive and transition==self.transition then tween(views[name],.22,{GroupTransparency=0}) end
			end)
		end
		self.layoutAt=0
	end
	local function pill(name,text,width,color,action)
		local p=button(strip,name,text,0,0,width,24,barColor,function(event)
			if event and event.UserInputType==Enum.UserInputType.Touch then action() end
		end)
		connect(p.MouseEnter,function()
			controller.hoverSession=true;controller.hoverLeftAt=nil;action()
		end)
		local visual=p
		if name=="Music" then
			p.BackgroundTransparency=1;p.ClipsDescendants=true;p.UICorner.CornerRadius=UDim.new(0,8)
			visual=make("CanvasGroup",p,{Name="Visual",Size=UDim2.fromOffset(width,24),BackgroundColor3=barColor,
				BackgroundTransparency=.08,BorderSizePixel=0,GroupTransparency=1})
			corner(visual,8)
		else p.BackgroundTransparency=.08 end
		local back=frame(visual,"Back",2,2,0,0,controlColor,7);back.Size=UDim2.new(1,-4,1,-4)
		barTile(back,({ControlCenter="Settings",Music="Home",Timer="Scripts",Stopwatch="Playerlist"})[name])
		back.BackgroundTransparency=.18
		local edge=frame(visual,"Edge",1,1,0,0,nil,8);edge.Size=UDim2.new(1,-2,1,-2)
		accentOutlines[#accentOutlines+1]=make("UIStroke",edge,{Name="PillOutline",Color=white,Thickness=1,
			Transparency=.45,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
		if name~="Music" then
			p.Text=""
			local value=label(visual,"Value",text,0,0,width,24,8,white)
			value.TextXAlignment=Enum.TextXAlignment.Center;value.FontFace=medium
		end
		p.LayoutOrder=#strip:GetChildren();p.TextSize=8;p.TextColor3=color or white
		return p,visual
	end
	local menuPill=pill("ControlCenter","",24,white,function() controller:Open("center") end)
	icon(menuPill,"Chevron","chevron-down",6,6,12,white)
	local musicPill,musicVisual=pill("Music","",62,white,function() controller:Open("music") end)
	musicPill.Visible=false
	local timerPill=pill("Timer","    05:00",50,amber,function() controller:Open("timer") end)
	local watchPill=pill("Stopwatch","    00:00",50,green,function() controller:Open("watch") end)
	for _,p in {timerPill,watchPill} do icon(p,"ClockIcon","timer",5,6,12,white) end
	pills.center,pills.music,pills.timer,pills.watch=menuPill,musicPill,timerPill,watchPill
	artwork(musicVisual,3,3,18,9,7,7,10)
	local compactTitle=label(musicVisual,"Title","Spotify",27,0,60,24,7,white);compactTitle.FontFace=medium
	compactTitle.TextTruncate=Enum.TextTruncate.None
	local function renderedTitleWidth()
		if compactTitle.Text==controller.measuredTitle and compactTitle.TextBounds.X>0 then
			return math.ceil(compactTitle.TextBounds.X/math.max(.01,scale.Scale*compactFit.Scale))
		end
	end
	connect(compactTitle:GetPropertyChangedSignal("TextBounds"),function()
		controller.titleWidth=controller.titleWidth or renderedTitleWidth()
	end)
	local function measureCompactTitle(title)
		if controller.measuredTitle==title then return end
		controller.measuredTitle=title;controller.titleMeasurement=(controller.titleMeasurement or 0)+1
		local generation=controller.titleMeasurement
		task.spawn(function()
			local params=Instance.new("GetTextBoundsParams")
			params.Text=title;params.Font=compactTitle.FontFace;params.Size=compactTitle.TextSize;params.Width=100000
			local ok,bounds=pcall(function() return game:GetService("TextService"):GetTextBoundsAsync(params) end)
			params:Destroy()
			if controller.alive and generation==controller.titleMeasurement then
				controller.titleWidth=(ok and math.ceil(bounds.X) or renderedTitleWidth() or game:GetService("TextService"):GetTextSize(title,7,Enum.Font.Roboto,Vector2.new(100000,24)).X)
			end
		end)
	end
	controller.musicShown=false;controller.musicTransition=0
	musicPill.Size=UDim2.fromOffset(0,24)
	local function animateMusic(active,width)
		if active~=controller.musicShown then
			controller.musicShown=active;controller.musicTransition+=1
			local generation=controller.musicTransition
			local wasVisible=musicPill.Visible
			musicPill.Visible=true
			if active then
				if not wasVisible then
					musicVisual.Position=UDim2.fromOffset(0,-10);musicVisual.GroupTransparency=1
					musicPill.Size=UDim2.fromOffset(0,24)
				end
				controller.musicWidth=width
				tween(musicVisual,.28,{Position=UDim2.fromOffset(0,0),GroupTransparency=0},Enum.EasingStyle.Quad)
				tween(musicPill,.4,{Size=UDim2.fromOffset(width,24)},Enum.EasingStyle.Quart)
			else
				tween(musicVisual,.32,{Position=UDim2.fromOffset(0,-10),GroupTransparency=1},Enum.EasingStyle.Quad,Enum.EasingDirection.In)
				tween(musicPill,.4,{Size=UDim2.fromOffset(0,24)},Enum.EasingStyle.Quart,Enum.EasingDirection.InOut)
				task.delay(.42,function()
					if controller.alive and generation==controller.musicTransition and not controller.musicShown then musicPill.Visible=false end
				end)
			end
		elseif active and controller.musicWidth~=width then
			controller.musicWidth=width;tween(musicPill,.2,{Size=UDim2.fromOffset(width,24)})
		end
		if active then
			musicVisual.Size=UDim2.fromOffset(width,24)
			if not controller.musicCarry then compactTitle.Size=UDim2.fromOffset(width-35,24) end
		end
	end
	timerPill.Visible,watchPill.Visible=false,false
	local function syncCompactBounds()
		if root.AbsoluteSize.X<=0 then return end
		local factor=math.max(.01,scale.Scale*compactFit.Scale)
		local width=math.max(24,pillLayout.AbsoluteContentSize.X/factor)
		local fit=math.min(1,(root.AbsoluteSize.X-24)/math.max(1,(width+8)*scale.Scale))
		set(compactFit,"Scale",math.max(.05,fit))
		set(strip,"Size",UDim2.fromOffset(width,24))
		set(compact,"Size",UDim2.fromOffset(width+8,32))
		set(compact,"Position",UDim2.new(.5,0,0,-4*compactFit.Scale))
		controller.compactWidth=(width+8)*compactFit.Scale
	end
	connect(pillLayout:GetPropertyChangedSignal("AbsoluteContentSize"),syncCompactBounds)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"),syncCompactBounds)
	local function notifyError(message)
		if os.clock()-controller.lastErrorAt<4 then return end
		controller.lastErrorAt=os.clock();context.Notify("Spotify",message,nil)
	end
	function controller:ShowSetup()
		context.Notify("Spotify setup","Run Companion/StartSpotify.cmd once, open Spotify desktop and play something, then choose Connect Spotify. Volt pairs automatically and saves the connection. No developer app is needed for local desktop playback. For other devices use your public Spotify Client ID and approve in the browser. Unlink asks before removing the saved connection.",nil,{Duration=12})
	end
	local function bridgeRequest(method,path,body)
		if context.MediaAdapter then return context.MediaAdapter(method,path,body) end
		assert(type(context.Request)=="function","This executor has no HTTP request function")
		local key=tostring(get("Spotify Bridge Key","")):match("^%s*(.-)%s*$")
		assert(#key>=32,"Paste the companion key into Spotify Bridge Key in Settings")
		local port=math.clamp(math.floor(tonumber(get("Spotify Bridge Port",43827)) or 43827),1024,65535)
		local response=context.Request({Url="http://127.0.0.1:"..port.."/v1/"..path,Method=method,Timeout=method=="GET" and 3 or 15,
			Headers={Authorization="Bearer "..key,["Content-Type"]="application/json"},Body=body and http:JSONEncode(body) or nil})
		assert(type(response)=="table","The Spotify companion did not respond")
		local status=tonumber(response.StatusCode or response.Status) or 0
		local ok,data=pcall(http.JSONDecode,http,response.Body or "")
		assert(ok and type(data)=="table","The companion returned an invalid response")
		assert(status>=200 and status<300,data.error or "Spotify companion request failed")
		return data
	end
	controller.commands={};controller.mediaGeneration=0
	function controller:Enqueue(path,body,previous)
		if not self.alive then return false end
		if path~="control" then
			table.clear(self.commands)
			self.accountGeneration=(self.accountGeneration or 0)+1
		elseif body.action=="seek" or body.action=="volume" then
			for i=#self.commands,1,-1 do
				local job=self.commands[i]
				if job.path=="control" and job.body.action==body.action then table.remove(self.commands,i) end
			end
		end
		if #self.commands>=8 then notifyError("Playback controls are busy. Try again in a moment.");return false end
		self.mediaGeneration+=1
		self.commands[#self.commands+1]={path=path,body=body,previous=previous,generation=self.mediaGeneration}
		if self.commandBusy then return true end
		self.commandBusy=true
		task.defer(function()
			while self.alive and #self.commands>0 do
				local job=table.remove(self.commands,1)
				local ok,result=pcall(bridgeRequest,"POST",job.path,job.body)
				if not self.alive then return end
				if ok then
					if job.path=="unlink" then
						self:SetMedia({connected=false,linked=false,title="Spotify"})
						context.Notify("Spotify","Unlinked. Saved account tokens were removed. Use Link Spotify to connect again.",nil)
					elseif job.path=="link" then context.Notify("Spotify",result.linked and "Saved Spotify connection restored. It will reconnect automatically."or"Approve Spotify in your browser once. The connection will be saved.",nil) end
				else
					if job.previous and job.generation==self.mediaGeneration then self:SetMedia(job.previous) end
					notifyError(tostring(result))
				end
			end
			self.commandBusy=false;self.nextPoll=0
		end)
		return true
	end
    function controller:ShowSpotifyStatus()
     local m=self.media
     local message=m.reauth_required and "Spotify requires browser approval again. Choose Connect Spotify."
      or m.linked and(m.available==false and "Account saved and linked. Updates are retrying automatically; no relink is needed. "..tostring(m.message or "")or"Account saved and connected. Altair reruns do not remove this link.")
      or "Run the companion once, then choose Connect Spotify."
     context.Notify("Spotify connection",message,nil)
    end
	function controller:LinkSpotify()
        if context.EnableSpotify then context.EnableSpotify()end
        self.nextPoll=0
		return self:Enqueue("link",{clientId=tostring(get("Spotify Client ID","")):match("^%s*(.-)%s*$")})
	end
	local unlinkDialog=make("TextButton",root,{Name="SpotifyUnlinkConfirmation",Text="",AutoButtonColor=false,
		Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=.35,Visible=false,ZIndex=650})
	local unlinkCard=frame(unlinkDialog,"Card",0,0,380,184,Color3.fromRGB(20,20,22),18)
	unlinkCard.AnchorPoint=Vector2.new(.5,.5);unlinkCard.Position=UDim2.fromScale(.5,.5);unlinkCard.Size=UDim2.new(1,-32,0,184);unlinkCard.Active=true
	make("UISizeConstraint",unlinkCard,{Name="Bounds",MaxSize=Vector2.new(380,184)})
	make("UIStroke",unlinkCard,{Color=white,Transparency=.65,Thickness=1})
	local unlinkTitle=label(unlinkCard,"Title","Disconnect Spotify?",22,20,336,24,18,white)
	local unlinkBody=label(unlinkCard,"Description","",22,56,336,54,13,gray)
	unlinkBody.TextWrapped=true;unlinkBody.TextTruncate=Enum.TextTruncate.None;unlinkBody.Size=UDim2.new(1,-44,0,54)
	local function closeUnlink(confirmed)
		local pending=controller.pendingDisconnect
		if not pending or not controller.alive then return false end
		controller.pendingDisconnect=nil;unlinkDialog.Visible=false
		if confirmed then pending() end
		return true
	end
	local cancel=button(unlinkCard,"Cancel","Cancel",22,128,158,36,Color3.fromRGB(40,40,43),function() closeUnlink(false) end)
	local confirm=button(unlinkCard,"Confirm","Disconnect",190,128,168,36,Color3.fromRGB(118,42,48),function() closeUnlink(true) end)
	cancel.Size=UDim2.new(.5,-27,0,36);confirm.Position=UDim2.new(.5,5,0,128);confirm.Size=UDim2.new(.5,-27,0,36)
	unlinkCard.ZIndex=651
	for _,object in ipairs(unlinkCard:GetDescendants()) do if object:IsA("GuiObject") then object.ZIndex=652 end end
	connect(unlinkDialog.Activated,function() closeUnlink(false) end)
	connect(input.InputBegan,function(event) if event.KeyCode==Enum.KeyCode.Escape then closeUnlink(false) end end)
	function controller:ResolveSpotifyDisconnect(confirmed) return closeUnlink(confirmed==true) end
	function controller:ConfirmSpotifyDisconnect(action,pauseOnly)
		if not self.alive then return false end
		if self.pendingDisconnect then return true end
		self.pendingDisconnect=action;unlinkDialog.Visible=true
		unlinkTitle.Text=pauseOnly and "Pause Spotify connection?" or "Disconnect Spotify?"
		unlinkBody.Text=pauseOnly and "Stop Spotify updates in Altair? Your saved account link will remain available when you turn it back on."
			or "Remove this computer's saved Spotify link? You will need to approve Spotify again to reconnect."
		confirm.Text=pauseOnly and "Pause connection" or "Disconnect"
		return true
	end
	function controller:UnlinkSpotify()
		return self:ConfirmSpotifyDisconnect(function() self:Enqueue("unlink",{}) end,false)
	end
	function controller:Control(action,value)
        if self.media.available==false and self.media.linked then notifyError(self.media.reauth_required and "Spotify needs approval again. Choose Connect Spotify."or"Spotify is retrying automatically. Your account is still linked.");return false end
		if not self.media.connected then
			if self.media.message then notifyError(self.media.message) else self:ShowSetup() end
			return false
		end
		if self.media.controls and self.media.controls[action]==false then notifyError("Spotify does not currently support that control.");return false end
		if action=="seek" or action=="volume" then
			if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
			if action=="seek" and (self.media.duration or 0)<=0 then return false end
			value=math.clamp(value,0,action=="seek" and self.media.duration or 1)
		end
		local previous=table.clone(self.media)
		previous.progress=math.min(previous.duration or 0,(previous.progress or 0)+(previous.playing and os.clock()-self.mediaAt or 0))
		if not self:Enqueue("control",{action=action,value=value},previous) then return false end
		local optimistic=table.clone(previous)
		if action=="seek" then optimistic.progress=value
		elseif action=="volume" then optimistic.volume=value
		elseif action=="toggle" then optimistic.playing=not optimistic.playing end
		self:SetMedia(optimistic)
		return true
	end
	function controller:SetMedia(state)
		if type(state)~="table" then return end
        if state.linked and state.available==false then
         local merged=table.clone(self.media or{})
         for key,value in pairs(state)do merged[key]=value end
         state=merged
        else state=table.clone(state)end
		local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
		state.duration=finite(state.duration) and math.clamp(state.duration,0,86400) or 0
		state.progress=finite(state.progress) and math.clamp(state.progress,0,state.duration) or 0
		state.title=tostring(state.title or "Spotify"):sub(1,300)
		state.artist=tostring(state.artist or ""):sub(1,300)
        state.connected=state.connected==true;state.playing=state.playing==true
        if state.linked==nil then state.linked=state.connected or(self.media and self.media.linked)or false end
		self.media,self.mediaAt=state,os.clock()
		if context.Session and(state.connected or state.linked~=nil)then
			context.Session.media=table.clone(state);context.Session.mediaAt=self.mediaAt
		end
		measureCompactTitle(state.title)
		updateArtwork(state.connected and state.artwork or nil)
	end
	local function progress()
		if controller.seekPreview then return controller.seekPreview end
		local m=controller.media
		return math.clamp(m.progress or 0,0,m.duration or 0)+(m.playing and math.min(os.clock()-controller.mediaAt,math.max(0,(m.duration or 0)-(m.progress or 0))) or 0)
	end
	local dragCancels={}
	controller.cancelDrag=function() for _,cancel in ipairs(dragCancels) do cancel() end;controller.seekPreview=nil end
	local function slider(parent,name,x,y,w,h,color,callback)
		local bar=frame(parent,name,x,y,w,h,Color3.fromRGB(43,43,44),h/2);bar.ClipsDescendants=true
		local fill=frame(bar,"Fill",0,0,0,h);fill.ClipsDescendants=true
		frame(fill,"Color",0,0,w,h,color,h/2)
		local hit=button(bar,"Input","",0,0,w,h,nil,function() end)
		hit:SetAttribute("NoHover",true)
		local dragging,lastPosition=false,nil
		local state={bar=bar,fill=fill,value=0}
		local function ratio(position) return math.clamp((position.X-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1) end
		local function move(position,finished)
			lastPosition=position;state.value=ratio(position)
			fill.Size=UDim2.new(state.value,0,1,0);callback(state.value,finished)
		end
		local function cancel() dragging=false;controller.dragging=false end
		dragCancels[#dragCancels+1]=cancel
		connect(hit.InputBegan,function(event)
			if dragging then return end
			if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
				controller.dragging=true;dragging=event
				move(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation(),false)
			end
		end)
		connect(input.InputChanged,function(event)
			if dragging and (event==dragging or (dragging.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseMovement)) then
				move(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation(),false)
			end
		end)
		connect(input.InputEnded,function(event)
			if dragging and (event==dragging or (dragging.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseButton1)) then
				local position=dragging.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation()
				dragging=false;controller.dragging=false;move(position or lastPosition,true)
			end
		end)
		connect(input.WindowFocusReleased,function() cancel();controller.seekPreview=nil end)
		state.IsDragging=function() return dragging~=false end
		return state
	end
	local function playbackGlyph(parent,kind,color)
		parent.Text=""
		local glyph=frame(parent,"Glyph",0,0,16,16)
		glyph.ZIndex=parent.ZIndex+1
		glyph.AnchorPoint=Vector2.new(.5,.5);glyph.Position=UDim2.fromScale(.5,.5)
		local play=icon(glyph,"Play","play",0,0,16,color)
		local pause=icon(glyph,"Pause","pause",0,0,16,color)
		if kind=="next" or kind=="previous" then
			play.Visible=false;pause.Visible=false
			icon(glyph,"Skip",kind=="previous" and "skip-back" or "skip-forward",1,1,14,color)
		else play.Visible=kind=="play";pause.Visible=kind=="pause" end
		return function(playing) play.Visible=not playing;pause.Visible=playing end
	end
	local playerViews={}
	for _,spec in ipairs({{center,300,true},{music,220,false}}) do
		local group,w,expanded=spec[1],spec[2],spec[3]
		artwork(group,11,11,29,7,19,19,13)
		local title=label(group,"Title","Connect Spotify",48,13,w-132,13,11,white);title.FontFace=medium
		local artist=label(group,"Artist","Open Settings for setup",48,27,w-132,12,10,gray)
		local previous=button(group,"Previous","◂◂",w-67,17,18,20,nil,function() controller:Control("previous") end);previous.TextSize=10
		local play=button(group,"PlayPause","▶",w-47,15,20,23,nil,function() controller:Control("toggle") end);play.TextSize=17
		local nextButton=button(group,"Next","▸▸",w-25,17,18,20,nil,function() controller:Control("next") end);nextButton.TextSize=10
		local seek=slider(group,"Seek",11,47,w-22,4,white,function(value,finished)
			local seconds=value*(controller.media.duration or 0)
			if finished then controller:Control("seek",seconds);controller.seekPreview=nil else controller.seekPreview=seconds end
		end)
		-- A larger invisible hit target retains the thin reference progress bar.
		seek.bar.ClipsDescendants=false
		local seekInput=seek.bar.Input;seekInput.Size=UDim2.new(1,0,0,16);seekInput.Position=UDim2.fromOffset(0,-6)
		local elapsed=label(group,"Elapsed","0:00",11,54,65,12,9,gray)
		local duration=label(group,"Duration","--:--",w-76,54,65,12,9,gray);duration.TextXAlignment=Enum.TextXAlignment.Right
		playbackGlyph(previous,"previous",white);playbackGlyph(nextButton,"next",white)
		playerViews[#playerViews+1]={title=title,artist=artist,play=play,renderPlay=playbackGlyph(play,"play",white),seek=seek,elapsed=elapsed,duration=duration}
	end
	local originalBrightness=lighting.Brightness
	local brightnessChanged=false
	local brightness=slider(center,"Brightness",11,71,136,22,white,function(value)
		brightnessChanged=true;lighting.Brightness=value*3
	end)
	icon(center,"BrightnessIcon","sun",20,77,12,Color3.fromRGB(194,148,35))
	brightness.fill.Size=UDim2.fromScale(math.clamp(originalBrightness/3,0,1),1)
	local volume=slider(center,"SpotifyVolume",153,71,136,22,white,function(value,finished)
		if finished then controller:Control("volume",value) end
	end)
	local speaker=icon(center,"VolumeIcon","volume-2",163,77,12,gray)
	local mute=icon(center,"VolumeMute","volume-x",163,77,12,gray)
	local timerSummary,timerCancel
	controller.timerDraft=300;controller.timerUnit=60;controller.rulerTarget=5;controller.rulerDisplay=5
	local timerEntry=make("TextBox",duration,{Name="Duration",Text="05:00",ClearTextOnFocus=false,
		Position=UDim2.fromOffset(11,32),Size=UDim2.fromOffset(278,30),BackgroundTransparency=1,
		TextColor3=amber,TextSize=24,FontFace=medium,TextXAlignment=Enum.TextXAlignment.Center})
	label(duration,"Title","Set timer",12,9,135,16,11,white)
	local minutesButton,secondsButton
	local function syncDraft()
		if input:GetFocusedTextBox()~=timerEntry then timerEntry.Text=Clock.Format(controller.timerDraft,false,true) end
		controller.rulerTarget=controller.timerUnit==60 and math.floor(controller.timerDraft/60) or controller.timerDraft%60
	end
	function controller:SetTimerDraft(seconds)
		if type(seconds)~="number" or seconds~=seconds then return end
		self.timerDraft=math.clamp(math.floor(seconds+.5),1,86400);syncDraft()
	end
	local function selectUnit(unit)
		controller.timerUnit=unit;syncDraft();controller.rulerDisplay=controller.rulerTarget
		for _,spec in {{minutesButton,60},{secondsButton,1}} do
			local selected=unit==spec[2]
			tween(spec[1],.16,{BackgroundColor3=selected and white or Color3.fromRGB(32,32,33),TextColor3=selected and Color3.fromRGB(20,20,20) or gray})
		end
	end
	minutesButton=button(duration,"Minutes","Min",196,8,42,19,white,function() selectUnit(60) end)
	secondsButton=button(duration,"Seconds","Sec",244,8,42,19,Color3.fromRGB(32,32,33),function() selectUnit(1) end)
	minutesButton.TextColor3=Color3.fromRGB(20,20,20);minutesButton.TextSize=9;secondsButton.TextSize=9
	local pickerRuler=frame(duration,"Ruler",11,76,278,35);pickerRuler.ClipsDescendants=true
	local rulerInput=button(pickerRuler,"Input","",0,0,278,35,nil,function() end);rulerInput:SetAttribute("NoHover",true)
	rulerInput.ZIndex=295
	local pickerTicks={}
	for i=1,61 do
		local tick=frame(pickerRuler,"Tick"..i,0,0,1,9,amber)
		local caption=label(pickerRuler,"Label"..i,"",0,16,26,12,8,gray);caption.TextXAlignment=Enum.TextXAlignment.Center
		pickerTicks[i]={tick=tick,label=caption}
	end
	icon(duration,"Selection","chevron-down",145,64,10,amber)
	label(duration,"Hint","Drag the ruler or scroll to adjust",11,109,278,12,8,gray).TextXAlignment=Enum.TextXAlignment.Center
	function controller:EndTimerEntry(start)
		self.picker=false;self.dragging=false;self.pickerDrag=nil
		if input:GetFocusedTextBox()==timerEntry then timerEntry:ReleaseFocus() end
		if start then clock:StartTimer(self.timerDraft) end
		self.hoverLeftAt=nil;self:Open("center")
	end
	function controller:BeginTimerEntry()
		self.picker=true;self.hoverLeftAt=nil
		self:SetTimerDraft(clock.timer and clock:Remaining() or self.timerDraft)
		self:Open("duration")
	end
	button(duration,"Cancel","Cancel",11,128,136,27,Color3.fromRGB(32,32,33),function() controller:EndTimerEntry(false) end).TextSize=10
	local startTimer=button(duration,"Start","Start timer",153,128,136,27,amber,function() controller:EndTimerEntry(true) end)
	startTimer.TextSize=10;startTimer.TextColor3=Color3.fromRGB(25,20,10)
	connect(timerEntry.FocusLost,function(enter)
		if not controller.picker then return end
		local hours,minutes,seconds=timerEntry.Text:match("^%s*(%d+):(%d%d?):(%d%d?)%s*$")
		local total
		if hours then
			if tonumber(minutes)<60 and tonumber(seconds)<60 then total=tonumber(hours)*3600+tonumber(minutes)*60+tonumber(seconds) end
		else
			minutes,seconds=timerEntry.Text:match("^%s*(%d+):(%d%d?)%s*$")
			total=minutes and tonumber(seconds)<60 and tonumber(minutes)*60+tonumber(seconds) or (not minutes and tonumber(timerEntry.Text) or nil)
		end
		if total and total>=1 and total<=86400 then
			controller:SetTimerDraft(total)
			if enter then controller:EndTimerEntry(true) end
		else
			timerEntry.Text=Clock.Format(controller.timerDraft,false,true)
			context.Notify("Timer","Enter minutes:seconds, from 00:01 to 1440:00.")
		end
	end)
	local function changeRuler(position)
		local drag=controller.pickerDrag;if not drag then return end
		local value=drag.value-(position.X-drag.x)/(7*math.max(.01,scale.Scale))
		value=math.clamp(value,0,controller.timerUnit==60 and 1440 or 59)
		local rounded=math.floor(value+.5)
		local total=controller.timerUnit==60 and rounded*60+drag.remainder or drag.minutes*60+rounded
		controller:SetTimerDraft(total);controller.rulerTarget=value
	end
	connect(rulerInput.InputBegan,function(event)
		if event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch then return end
		local position=event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation()
		controller.pickerDrag={input=event,x=position.X,value=controller.rulerTarget,remainder=controller.timerDraft%60,minutes=math.floor(controller.timerDraft/60)}
		controller.dragging=true
	end)
	connect(input.InputChanged,function(event)
		local drag=controller.pickerDrag
		if drag and (event==drag.input or event.UserInputType==Enum.UserInputType.MouseMovement) then
			changeRuler(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation())
		end
	end)
	connect(input.InputEnded,function(event)
		local drag=controller.pickerDrag
		if drag and (event==drag.input or event.UserInputType==Enum.UserInputType.MouseButton1) then
			changeRuler(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation())
			controller.pickerDrag=nil;controller.dragging=false;syncDraft()
		end
	end)
	connect(rulerInput.InputChanged,function(event)
		if event.UserInputType==Enum.UserInputType.MouseWheel then controller:SetTimerDraft(controller.timerDraft+event.Position.Z*controller.timerUnit) end
	end)
	connect(input.WindowFocusReleased,function() controller.pickerDrag=nil;controller.dragging=false;syncDraft() end)
	local timerTile=button(center,"TimerTile","",11,102,136,33,controlColor,function()
		if clock.timer then controller:Open("timer") else controller:BeginTimerEntry() end
	end)
	label(timerTile,"Label","Timer",10,3,90,12,9,gray)
	timerSummary=label(timerTile,"Value","Set",10,15,90,15,12,white);timerSummary.FontFace=medium
	timerCancel=button(timerTile,"Cancel","",110,7,20,20,Color3.fromRGB(40,40,41),function() clock:CancelTimer() end)
	icon(timerCancel,"Close","x",5,5,10,white);timerCancel.Visible=false

	local watchTile=button(center,"WatchTile","",153,102,136,33,controlColor,function()
		if not clock.watch.active then clock:ToggleWatch() else controller:Open("watch") end
	end)
	label(watchTile,"Label","Stopwatch",10,3,90,12,9,gray)
	local watchSummary=label(watchTile,"Value","Start",10,15,90,15,12,white);watchSummary.FontFace=medium
	local watchCancel=button(watchTile,"Cancel","×",110,7,20,20,Color3.fromRGB(40,40,41),function() clock:ResetWatch() end)
	watchCancel.Text="";icon(watchCancel,"Close","x",5,5,10,white)
	watchCancel.Visible=false
	for _,tile in {timerTile,watchTile} do
		barTile(tile,tile==timerTile and "Scripts" or "Playerlist")
		tile.Label.TextColor3=white:Lerp(gray,.15)
		accentOutlines[#accentOutlines+1]=make("UIStroke",tile,{Name="InsetOutline",Color=white,Thickness=1,
			Transparency=.55,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
	end
	label(timer,"Title","Timer",11,8,100,12,9,gray)
	local timerTime=label(timer,"Time","05:00",11,22,120,21,18,amber);timerTime.FontFace=medium
	local timerPause=button(timer,"Pause","Ⅱ",153,11,22,22,Color3.fromRGB(65,45,7),function() clock:ToggleTimer() end)
	timerPause.TextColor3=amber;timerPause.TextSize=15
	local renderTimerPause=playbackGlyph(timerPause,"pause",amber)
	local timerClose=button(timer,"Cancel","",179,11,22,22,Color3.fromRGB(35,35,36),function() clock:CancelTimer();controller:Open(nil) end)
	icon(timerClose,"Close","x",6,6,10,white)
	local ruler=frame(timer,"Ruler",11,51,186,10);ruler.ClipsDescendants=true
	local rulerStrip=frame(ruler,"Ticks",0,0,230,10)
	for index=0,60 do frame(rulerStrip,"Tick"..index,index*3.7, index%5==0 and 0 or 2,1,index%5==0 and 9 or 6,amber) end
	label(watch,"Title","Stopwatch",11,8,100,12,9,gray)
	local watchTime=label(watch,"Time","00:00",11,22,100,21,18,green);watchTime.FontFace=medium
	local fraction=label(watch,"Fraction",".00",68,27,40,14,11,green)
	local lapButton=button(watch,"Lap","Lap",130,11,43,22,Color3.fromRGB(42,42,43),function()
		if clock.watch.started then clock:Lap() else clock:ResetWatch();controller:Open(nil) end
	end);lapButton.TextSize=10
	local watchPause=button(watch,"Pause","Ⅱ",179,11,22,22,Color3.fromRGB(11,67,25),function() clock:ToggleWatch() end)
	watchPause.TextColor3=green;watchPause.TextSize=15
	local renderWatchPause=playbackGlyph(watchPause,"pause",green)
	local lapEmpty=label(watch,"Empty","Laps show here. Tap Lap to split.",11,50,186,18,9,gray)
	local lapRows={}
	for index=1,3 do
		local row=frame(watch,"Lap"..index,11,49+(index-1)*13,186,12)
		lapRows[index]={root=row,title=label(row,"Label","",0,0,35,12,9,gray),bar=frame(row,"Bar",39,4,0,4,green,2),
			value=label(row,"Value","",135,0,51,12,9,white)}
		lapRows[index].value.TextXAlignment=Enum.TextXAlignment.Right
	end
	local obstacles={}
	for _,name in ipairs({"SmartBar","Drag","Character","Scripts","Playerlist","Settings","ScriptSearch","CustomScriptPrompt","ModeratorDetectionPrompt"}) do
		local object=root:FindFirstChild(name);if object then obstacles[#obstacles+1]=object end
	end
	local function intersects(x,width,left,right) return x<right and x+width>left end
	function controller:Layout()
		local viewport=root.AbsoluteSize
		local requested=tonumber(get("Capsule Scale",1.25)) or 1.25
		-- Migrate the previous oversized default, including already saved settings.
		if requested==3 then requested=1.25 end
		local factor=math.clamp(requested,.65,2)
		factor=math.min(factor*(root:GetAttribute("AltairDisplayScale") or displayScale(viewport)),math.max(.45,(viewport.X-24)/300))
		factor=math.min(factor,math.max(.3,(viewport.Y-24)/180))
		scale.Scale=factor
		local width=(self.view and sizes[self.view].X or self.compactWidth or 250)*factor
		local height=(self.view and sizes[self.view].Y or 24)*factor
				local top=12*factor
		local x,y=viewport.X/2-width/2,top
		local candidates={}
		for _,object in ipairs(obstacles) do if object.Visible then candidates[#candidates+1]=object end end
		local toasts=root:FindFirstChild("Toasts")
		if toasts then for _,object in ipairs(toasts:GetChildren()) do
			if object:IsA("GuiObject") and object.Visible and object.Name~="Template" then candidates[#candidates+1]=object end
		end end
		if context.Notifications then for _,object in ipairs(context.Notifications:GetObstacles()) do candidates[#candidates+1]=object end end
		local origin=root.AbsolutePosition
		-- Resolve overlapping top obstacles without changing to a bottom anchor/dock.
		for _=1,#candidates+1 do
			local nextY=y
			for _,object in ipairs(candidates) do
				local p,s=object.AbsolutePosition-origin,object.AbsoluteSize
				if s.Y>0 and p.Y<viewport.Y*.5 and s.Y<viewport.Y*.8 and intersects(x,width,p.X,p.X+s.X)
					and y<p.Y+s.Y+8 and y+height>p.Y-8 then nextY=math.max(nextY,p.Y+s.Y+8) end
			end
			if nextY==y then break end;y=nextY
		end
		y=math.clamp(y,top,math.max(top,viewport.Y-height-top))
		self.targetY=y
		set(host,"Visible",get("Capsules Enabled",true)==true)
	end
	local function inside(object,position)
		local p,s=object.AbsolutePosition,object.AbsoluteSize
		-- Keep edge controls usable without changing the visible capsule dimensions.
		local margin=math.max(18,24*scale.Scale)
		return position.X>=p.X-margin and position.X<=p.X+s.X+margin
			and position.Y>=p.Y-margin and position.Y<=p.Y+s.Y+margin
	end
	connect(surface.MouseEnter,function() controller.hoverSession=true;controller.hoverLeftAt=nil end)
	connect(input.InputBegan,function(event)
		if controller.picker and event.KeyCode==Enum.KeyCode.Escape then controller:EndTimerEntry(false);return end
		if controller.view and not controller.picker and not input:GetFocusedTextBox() and (event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)
			and not inside(surface,event.Position) and not inside(compact,event.Position) then controller:Open(nil) end
	end)
	local renderAccumulator=0
	connect(runService.RenderStepped,function(dt)
		local target=controller.morphTarget;if not target then return end
		local state=controller.morphState
		if not state then
			state={x=surface.Position.X.Offset+surface.Position.X.Scale*host.Size.X.Offset,width=surface.Size.X.Offset,height=surface.Size.Y.Offset,vx=0,vwidth=0,vheight=0}
			controller.morphState=state
		end
		local omega=root:GetAttribute("AltairReduceMotion")==true and 100 or 30
		local step=math.min(dt,.1);local decay=math.exp(-omega*step);local settled=true
		for _,key in ipairs({"x","width","height"}) do
			local velocity="v"..key;local delta=state[key]-target[key]
			local j=state[velocity]+omega*delta
			state[key]=target[key]+(delta+j*step)*decay
			state[velocity]=(state[velocity]-omega*j*step)*decay
			if math.abs(state[key]-target[key])>.12 then settled=false end
		end
		if settled then
			for _,key in ipairs({"x","width","height"}) do state[key]=target[key];state["v"..key]=0 end
		end
		surface.Size=UDim2.fromOffset(math.max(1,state.width),math.max(1,state.height));surface.Position=UDim2.fromOffset(state.x,0)
        if controller.circleCarry then controller.circleCarry.Position=UDim2.fromOffset(state.x-state.width/2-17,0) end
        if controller.returningMusic then controller.returningMusic.Position=UDim2.fromOffset(state.x+state.width/2+5+controller.returningMusic.Size.X.Offset/2,0) end
        if settled then controller.morphTarget=nil;if controller.finishMorph then local finish=controller.finishMorph;controller.finishMorph=nil;finish()end end
	end)
	connect(runService.Heartbeat,function(dt)
		if context.Alive and not context.Alive() then return end
		if clock:Tick() then
			context.Notify("Timer finished","Your countdown has ended.",nil,{Duration=8})
			if controller.view~="timer" then controller:Open("timer") end
		end
		local now=os.clock()
		if controller.hoverSession and controller.view and not controller.picker and not controller.dragging and not input:GetFocusedTextBox() then
			local pointer=input:GetMouseLocation()
			local inset=root.IgnoreGuiInset and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
			pointer-=inset
			if inside(surface,pointer) or (compact.Visible and inside(compact,pointer)) then
				controller.hoverLeftAt=nil
			else
				controller.hoverLeftAt=controller.hoverLeftAt or now
				if now-controller.hoverLeftAt>.5 then controller.hoverSession=false;controller:Open(nil) end
			end
		end
		if now>=controller.layoutAt then controller.layoutAt=now+.1;controller:Layout() end
        local oled=get("OLED Appearance",false)
        if controller.lastOLED~=oled or controller.lastThemeEnabled~=root:GetAttribute("AltairThemeEnabled")then
         controller.lastOLED=oled;controller.lastThemeEnabled=root:GetAttribute("AltairThemeEnabled")
         for _,entry in ipairs({{surface,baseColor,Color3.fromRGB(4,4,6)},{inner,controlColor,Color3.fromRGB(9,9,12)},{menuPill,barColor,Color3.fromRGB(4,4,6)},{menuPill.Back,barColor,Color3.fromRGB(9,9,12)}})do
          local object=entry[1];local color=object:GetAttribute("AltairTheme_BackgroundColor3")or(oled and entry[3]or entry[2]);if object.BackgroundColor3~=color then object.BackgroundColor3=color end
         end
        end
		local y=host.Position.Y.Offset
		if controller.targetY and math.abs(y-controller.targetY)>.1 then
			host.Position=UDim2.new(.5,0,0,y+(controller.targetY-y)*(1-math.exp(-18*dt)))
		end
		if get("Spotify Connection",false) and now>=controller.nextPoll and not controller.requestBusy and not controller.commandBusy then
			controller.requestBusy=true;controller.nextPoll=now+1.5
			task.spawn(function()
				local generation=controller.mediaGeneration
				local ok,state=pcall(bridgeRequest,"GET","state")
				if not controller.alive then return end
				controller.requestBusy=false
				if generation~=controller.mediaGeneration or not get("Spotify Connection",false) then return end
				if ok then controller.failures=0;controller:SetMedia(state);controller.nextPoll=math.max(controller.nextPoll,os.clock()+math.min(30,tonumber(state.retry_after)or 0))
				else
					controller.failures+=1
					controller.nextPoll=os.clock()+math.min(30,2^math.min(5,controller.failures))
                    local cached=table.clone(controller.media)
                    cached.progress=progress();cached.linked=cached.linked or cached.connected
                    cached.available=false;cached.stale=true;cached.status="reconnecting";cached.message="Companion unavailable; reconnecting automatically. Your saved account is retained."
                    controller:SetMedia(cached)
				end
			end)
		elseif not get("Spotify Connection",false) and not context.MediaAdapter and controller.media.connected then
			controller:SetMedia({connected=false,title="Spotify"})
		end
		renderAccumulator+=dt
		if renderAccumulator<(controller.view and 1/60 or .1) or not host.Visible then return end
		local renderDt=renderAccumulator;renderAccumulator=0
		do
			local rainbow=get("Rainbow Mode",false)==true
			local accent=rainbow and ((context.GetRainbowColor and context.GetRainbowColor()) or Color3.fromHSV((os.clock()/8)%1,.65,.8)) or white
			for _,stroke in ipairs(accentOutlines) do set(stroke,"Color",accent) end
		end
		local remaining,elapsed=clock:Remaining(),clock:Elapsed()
		set(timerPill,"Visible",clock.timer~=nil);set(watchPill,"Visible",clock.watch.active)
		local musicActive=controller.media.connected and controller.media.playing and (controller.media.duration or 0)>0
		-- Retain the title during exit so the whole pill fades as a single visual.
		if musicActive then set(compactTitle,"Text",controller.media.title) end
		if controller.view=="music" and not musicActive then controller:Open(nil) end
		local pillWidth=math.max(60,(controller.titleWidth or 0)+35)
		animateMusic(musicActive==true,pillWidth)
		set(timerPill.Value,"Text","    "..Clock.Format(remaining,false,true));set(watchPill.Value,"Text","    "..Clock.Format(elapsed))
		if controller.view=="duration" then
			controller.rulerDisplay+=(controller.rulerTarget-controller.rulerDisplay)*(1-math.exp(-22*renderDt))
			local base=math.floor(controller.rulerDisplay)
			for index,row in ipairs(pickerTicks) do
				local value=base+index-31
				local x=139+(value-controller.rulerDisplay)*7
				local valid=value>=0 and value<=(controller.timerUnit==60 and 1440 or 59)
				local fade=math.clamp(math.abs(x-139)/139,0,1)^2
				row.tick.Visible=valid;row.label.Visible=valid and value%5==0
				row.tick.Position=UDim2.fromOffset(x,value%5==0 and 0 or 4)
				row.tick.Size=UDim2.fromOffset(1,value%5==0 and 13 or 7)
				row.tick.BackgroundTransparency=.15+.8*fade
				row.label.Position=UDim2.fromOffset(x-13,17);row.label.Text=tostring(value);row.label.TextTransparency=fade
			end
		elseif controller.view=="timer" then
			set(timerTime,"Text",Clock.Format(remaining,false,true))
			renderTimerPause(clock.timer~=nil and clock.timer.started~=nil)
			set(timerTime,"TextTransparency",clock.timer and not clock.timer.started and .25 or 0)
			rulerStrip.Position=UDim2.fromOffset(-(((clock.timer and clock.timer.duration or 0)-remaining)*18.5%18.5),0)
		elseif controller.view=="watch" then
			set(watchTime,"Text",Clock.Format(elapsed));set(fraction,"Text",string.format(".%02d",math.floor((elapsed%1)*100)))
			fraction.Position=UDim2.fromOffset(watchTime.TextBounds.X/math.max(.01,scale.Scale)+12,27)
			renderWatchPause(clock.watch.started~=nil);set(lapButton,"Text",clock.watch.started and "Lap" or "Reset")
			local laps=clock.watch.laps;lapEmpty.Visible=#laps==0
			local maximum=math.max(.01,elapsed-clock.watch.splitAt)
			for _,lap in ipairs(laps) do maximum=math.max(maximum,lap.seconds) end
			for index,row in ipairs(lapRows) do
				row.root.Visible=#laps>0
				local lap=index==1 and {number=(clock.watch.lapCount or 0)+1,seconds=elapsed-clock.watch.splitAt} or laps[#laps-index+2]
				if lap and row.root.Visible then
					set(row.title,"Text","Lap "..lap.number);set(row.value,"Text",Clock.Format(lap.seconds,true))
					local target=math.clamp(lap.seconds/maximum,0,1)*92
					row.bar.Size=UDim2.fromOffset(row.bar.Size.X.Offset+(target-row.bar.Size.X.Offset)*(1-math.exp(-18*renderDt)),4)
				else row.root.Visible=false end
			end
		elseif controller.view=="music" or controller.view=="center" then
			local m=controller.media
			for _,player in ipairs(playerViews) do
				set(player.title,"Text",m.connected and m.title or "Connect Spotify")
				set(player.artist,"Text",m.connected and m.artist or "Settings → Capsules & Spotify")
				player.renderPlay(m.playing)
				set(player.elapsed,"Text",Clock.Format(progress()):gsub("^0([0-9]):","%1:"))
				set(player.duration,"Text",(m.duration or 0)>0 and Clock.Format(m.duration):gsub("^0([0-9]):","%1:") or "--:--")
				if not player.seek.IsDragging() then player.seek.fill.Size=UDim2.fromScale((m.duration or 0)>0 and progress()/m.duration or 0,1) end
			end
			set(timerSummary,"Text",clock.timer and Clock.Format(remaining,false,true) or "Set")
			set(timerSummary,"TextColor3",clock.timer and amber or white);set(timerCancel,"Visible",clock.timer~=nil or controller.picker)
			set(watchSummary,"TextColor3",clock.watch.active and green or white);set(watchCancel,"Visible",clock.watch.active)
			set(watchSummary,"Text",clock.watch.active and Clock.Format(elapsed,true) or "Start")
			if not volume.IsDragging() then volume.fill.Size=UDim2.fromScale(math.clamp(tonumber(m.volume) or 0,0,1),1) end
			set(mute,"Visible",(tonumber(m.volume) or 0)<=.001);set(speaker,"Visible",not mute.Visible)
		end
	end)
	function controller:Destroy()
		if not self.alive then return end
		if context.Session and(self.media.connected or self.media.linked)then
			context.Session.media=table.clone(self.media);context.Session.media.progress=progress();context.Session.mediaAt=os.clock()
		end
		self.pendingDisconnect=nil;unlinkDialog:Destroy()
		self.alive=false
		self.cancelDrag();table.clear(self.commands)
		for _,connection in ipairs(self.connections) do connection:Disconnect() end
		for _,animation in pairs(self.tweens) do animation:Cancel() end
		if brightnessChanged then lighting.Brightness=originalBrightness end
		host:Destroy();table.clear(self.connections)
	end
	connect(root.Destroying,function() controller:Destroy() end)
	if context.BuildOnly then
		-- Notification appearance is also authored in Build.lua; the renderer clones this card.
		local notificationHost=frame(root,"NotificationCapsules",0,0,0,0)
		notificationHost.Size=UDim2.fromScale(1,1);notificationHost.ZIndex=350
		local card=make("CanvasGroup",notificationHost,{Name="CardTemplate",BackgroundColor3=Color3.fromRGB(17,17,17),
			BorderSizePixel=0,Size=UDim2.fromOffset(300,64),Visible=false,GroupTransparency=1,ZIndex=350})
		corner(card,20)
		make("UIGradient",card,{Rotation=90,Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(115,115,115))})
		local title=label(card,"Title","Title",58,14,222,17,14,white);title.FontFace=medium
		local body=label(card,"Description","Description",58,34,222,16,13,Color3.fromRGB(174,174,178))
		for _,text in {title,body} do text.TextWrapped=true;text.TextYAlignment=Enum.TextYAlignment.Top end
		make("ImageLabel",card,{Name="Icon",BackgroundTransparency=1,Size=UDim2.fromOffset(22,22),
			Position=UDim2.new(0,20,.5,0),AnchorPoint=Vector2.new(0,.5),ImageColor3=white})
		for _,spec in {{"FriendIcon","user"},{"StaffIcon","settings"}} do
			local vector=icon(card,spec[1],spec[2],20,0,22,white)
			vector.AnchorPoint=Vector2.new(0,.5);vector.Position=UDim2.new(0,20,.5,0);vector.Visible=false
		end
		make("TextButton",card,{Name="Dismiss",Text="",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,AutoButtonColor=false,ZIndex=354})
		for _,object in card:GetDescendants() do if object:IsA("GuiObject") and object.Name~="Dismiss" then object.ZIndex=351 end end
		root:SetAttribute("AltairCapsuleSchema",2)
	end
	if not context.BuildOnly then
		if context.Session and context.Session.media and get("Spotify Connection",false) then
			local cached=table.clone(context.Session.media)
			if cached.playing then cached.progress=math.min(cached.duration or 0,(cached.progress or 0)+math.max(0,os.clock()-(context.Session.mediaAt or os.clock()))) end
			controller:SetMedia(cached)
		end
		controller:Layout()
	end
	return controller
end

-- CAPSULES END

-- Game HUD avoidance is queried only while dragging. Roblox supplies the hit index;
-- no descendant walks, per-widget signals, or idle polling are required.
local function bindUIAvoidance(root, enabled)
 local playerGui=game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
 local service={records={},lastQuery=-math.huge,Queries=0,Hits=0,Blocks=0,QuerySeconds=0}
 local function bounds(object)
  if not object.Parent or not object:IsDescendantOf(playerGui) or object:IsDescendantOf(root) then return nil end
  local p,s=object.AbsolutePosition,object.AbsoluteSize
  if s.X<12 or s.Y<8 then return nil end
  local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
  if s.X*s.Y>viewport.X*viewport.Y*.45 then return nil end
  local visual=object.BackgroundTransparency<.95
  if object:IsA("ImageLabel")or object:IsA("ImageButton")then visual=visual or(object.Image~=""and object.ImageTransparency<.95)end
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then visual=visual or(object.Text~=""and object.TextTransparency<.95)end
  if not visual then return nil end
  local left,top,right,bottom=p.X,p.Y,p.X+s.X,p.Y+s.Y
  local parent=object
  while parent and parent~=playerGui do
   if parent:IsA("GuiObject")then
    if not parent.Visible then return nil end
    if parent:IsA("CanvasGroup")and parent.GroupTransparency>.95 then return nil end
    if parent~=object and parent.ClipsDescendants then
     local q,z=parent.AbsolutePosition,parent.AbsoluteSize
     left,top=math.max(left,q.X),math.max(top,q.Y)
     right,bottom=math.min(right,q.X+z.X),math.min(bottom,q.Y+z.Y)
    end
   elseif parent:IsA("ScreenGui")and not parent.Enabled then return nil end
   parent=parent.Parent
  end
  if right-left<4 or bottom-top<4 then return nil end
  return {left,top,right,bottom,object=object}
 end
 local function inside(p,r)return p.X>r[1]+.01 and p.X<r[3]-.01 and p.Y>r[2]+.01 and p.Y<r[4]-.01 end
 -- Swept point against expanded rectangles: prevents tunnelling and permits sliding.
 local function sweep(origin,target,rectangles)
  local position,remaining=origin,target-origin
  for _=1,4 do
   local earliest,normal=1,nil
   for _,r in ipairs(rectangles)do
    if not inside(position,r)then -- Existing overlaps can be dragged out without teleporting.
     local enter,exit=-math.huge,math.huge
     local axis
     for dimension=1,2 do
      local start=dimension==1 and position.X or position.Y
      local delta=dimension==1 and remaining.X or remaining.Y
      local lo,hi=r[dimension],r[dimension+2]
      if math.abs(delta)<1e-7 then
       if start<=lo or start>=hi then enter=math.huge;break end
      else
       local a,b=(lo-start)/delta,(hi-start)/delta
       if a>b then a,b=b,a end
       if a>enter then enter=a;axis=dimension end
       exit=math.min(exit,b)
      end
     end
     if enter>=0 and enter<earliest and enter<=exit and exit>=0 then earliest,normal=enter,axis end
    end
   end
   if not normal then return position+remaining end
   position+=remaining*math.max(0,earliest-1e-5)
   remaining*=1-earliest
   remaining=normal==1 and Vector2.new(0,remaining.Y)or Vector2.new(remaining.X,0)
   if remaining.Magnitude<.001 then break end
  end
  return position
 end
 service.Sweep=sweep
 function service:Resolve(origin,target,extents)
  if not enabled()then return target end
  if not playerGui or not playerGui.Parent then playerGui=game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")end
  if not playerGui then return target end
  local now=os.clock()
  if now-self.lastQuery>=.08 and(not self.probes or self.probeIndex>#self.probes)then
   self.lastQuery=now
   local padding=math.min(160,48+(target-origin).Magnitude*3)
   local left,right=math.min(origin.X,target.X)+extents[1]-padding,math.max(origin.X,target.X)+extents[3]+padding
   local top,bottom=math.min(origin.Y,target.Y)+extents[2]-padding,math.max(origin.Y,target.Y)+extents[4]+padding
   local columns=math.clamp(math.ceil((right-left)/55),2,6)
   local rows=math.clamp(math.ceil((bottom-top)/55),2,3)
   self.probes={target,Vector2.new(target.X+extents[1],target.Y+extents[2]),Vector2.new(target.X+extents[3],target.Y+extents[2]),Vector2.new(target.X+extents[1],target.Y+extents[4]),Vector2.new(target.X+extents[3],target.Y+extents[4])}
   for x=0,columns do for y=0,rows do table.insert(self.probes,Vector2.new(left+(right-left)*x/columns,top+(bottom-top)*y/rows))end end
   self.probeIndex=1
  end
  -- Spread native hit tests across frames instead of creating a periodic frame spike.
  if self.probes and self.probeIndex<=#self.probes then
   local started=os.clock()
   for _=1,4 do
    local point=self.probes[self.probeIndex]
    if not point then break end
    self.probeIndex+=1
    local ok,objects=pcall(playerGui.GetGuiObjectsAtPosition,playerGui,math.floor(point.X),math.floor(point.Y))
    self.Queries+=1
    if ok then for _,object in ipairs(objects)do
     if bounds(object)then
      local found=false
      for i=#self.records,1,-1 do
       local record=self.records[i]
       if object==record.object or object:IsDescendantOf(record.object)then record.seen=now;found=true;break
       elseif record.object:IsDescendantOf(object)then table.remove(self.records,i)end
      end
      if not found and #self.records<80 then table.insert(self.records,{object=object,seen=now});self.Hits+=1 end
     end
    end end
    if os.clock()-started>=.00075 then break end
   end
   self.QuerySeconds+=os.clock()-started
  end
  local rectangles={}
  for i=#self.records,1,-1 do
   local record=self.records[i]
   local r=bounds(record.object)
   if not r or now-record.seen>2 then table.remove(self.records,i)
   else table.insert(rectangles,{r[1]-6-extents[3],r[2]-6-extents[4],r[3]+6-extents[1],r[4]+6-extents[2]})end
  end
  local resolved=sweep(origin,target,rectangles)
  if (resolved-target).Magnitude>.01 then self.Blocks+=1 end
  return resolved
 end
 return service
end

local bindings={StyleGallery=buildStyleGallery,UIAvoidance=bindUIAvoidance,SlideContent=slideContent,SlideHeading=slideHeading,BounceReset=bounceReset,HomeContainer=function(root)local content=Instance.new("CanvasGroup");content.Name="Content";content.BackgroundTransparency=1;content:SetAttribute("AltairHomeGroup",true);content.Parent=root.Home;return content end,Performance=motionStats,DragContrast=bindDragContrast,Dock=bindDock,Capsules=bindCapsules,Clock=Clock,Notifications=buildNotifications,ApplyIcon=applyIcon,RefreshIcon=refreshIcon,Motion=motionService,Resize=resizeInterface,DisplayScale=displayScale,Slider=buildSlider,Stats=buildStats,SoftShadows=bindSoftShadows,Surface=styleSurface,HomeSurface=styleHome,ColorPicker=buildColorPicker,Theme=bindTheme}
return function(options)
	if options and options.BindingsOnly then return bindings end
	local objects = table.create(#nodes)
	local ok, result = pcall(function()
		for index, node in ipairs(nodes) do
			local class=classes[node[2]]
			local object = Instance.new(class)
			objects[index] = object -- Register before assigning properties so failure cleans up.
			object.Name = node[3]
			if index == 1 then object.Enabled = false end
			local props=propertySets[node[4]]
			for j=1,#props,2 do
				local property,propertyValue=propertyNames[props[j]],v[props[j+1]]
				-- The loader enables the root only after runtime initialization.
				if index ~= 1 or property ~= "Enabled" then
					object[property] = propertyValue
				end
			end
			if node[5] then
				for attribute, attributeValue in pairs(attributeSets[node[5]]) do
					object:SetAttribute(attribute, attributeValue)
				end
			end
		end
		-- Link children only after configuration; never mount into the live DataModel here.
		for index = 2, #nodes do
			objects[index].Parent = objects[nodes[index][1]]
		end
		for _,object in ipairs(objects) do refreshIcon(object) end
		createSharedSurface(objects[1])
		styleSettings(objects[1])
		for _,name in ipairs({"Character","Scripts","Playerlist","Settings","ScriptSearch","CustomScriptPrompt"}) do
			local panel=objects[1]:FindFirstChild(name)
			if panel then
				local rounding=panel:FindFirstChildOfClass("UICorner");if rounding then rounding.CornerRadius=UDim.new(0,18) end
				local border=panel:FindFirstChildOfClass("UIStroke");if border then border.Color=Color3.fromRGB(160,166,180);border.Thickness=1 end
			end
		end

  for _,name in ipairs({"Character","Scripts","Playerlist","Settings","ScriptSearch","SmartBar","SharedPanelSurface","CustomScriptPrompt","GameDetection","ModeratorDetectionPrompt","Disconnected","SecurityPrompt"})do styleSurface(objects[1][name])end
  for _,label in ipairs(objects[1].Scripts:GetDescendants())do
   if label:IsA("TextLabel")and label.Name=="Chevron"then
    label.Text="";local icon=Instance.new("ImageLabel");icon.Name="ChevronIcon";icon.BackgroundTransparency=1;icon.AnchorPoint=Vector2.new(.5,.5);icon.Position=UDim2.fromScale(.5,.5);icon.Size=UDim2.fromOffset(16,16);icon.ImageTransparency=.15;icon.ZIndex=label.ZIndex+1;icon.Parent=label;applyIcon(icon,"chevron-right")
   end
  end
  applyFilledSmartBar(objects[1])
  local bar=objects[1].SmartBar;bar.UICorner.CornerRadius=UDim.new(1,0);bar.Back:SetAttribute("AltairInsetMaterial",nil);bar.Back.BackgroundColor3=Color3.fromRGB(48,48,50);bar.Back:SetAttribute("AltairInsetSurface",true);bar.Back.BackgroundTransparency=.45;bar.Back.UIStroke:SetAttribute("AltairInsetOutline",nil);bar.Back.UIStroke.Transparency=.9;bar.Back.UICorner.CornerRadius=UDim.new(.5,0);bar.UIStroke.Thickness=.65
  bar.Back.AnchorPoint=Vector2.new(1,.5);bar.Back.Position=UDim2.new(1,-8,.5,0);bar.Back.Size=UDim2.new(1,-76,1,-12)
  bar.Back.Buttons.AnchorPoint=Vector2.zero;bar.Back.Buttons.Position=UDim2.fromOffset(8,7);bar.Back.Buttons.Size=UDim2.new(1,-16,1,-14)
  local clock=bar.Back.Time;clock.AnchorPoint=Vector2.new(0,.5);clock.Position=UDim2.new(0,-58,.5,-3);clock.Size=UDim2.fromOffset(48,20);clock.TextSize=14;clock.TextXAlignment=Enum.TextXAlignment.Center
  clock.AMPM.AnchorPoint=Vector2.new(.5,0);clock.AMPM.Position=UDim2.new(.5,0,1,-2);clock.AMPM.Size=UDim2.new(1,0,0,10);clock.AMPM.TextSize=8;clock.AMPM.TextXAlignment=Enum.TextXAlignment.Center
  for _,button in ipairs(bar.Back.Buttons:GetChildren())do if button:IsA("GuiObject")then local corner=button:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=UDim.new(0,9)end;local stroke=button:FindFirstChildOfClass("UIStroke");if stroke then stroke.Thickness=.6;stroke.Transparency=.82 end end end
		do
			local prompt=objects[1].GameDetection
			-- Preserve the original authored prompt position and anchor.
			prompt.Size=UDim2.fromOffset(460,164);prompt.BackgroundColor3=Color3.fromRGB(12,13,16);prompt.BackgroundTransparency=.04
			prompt.ClipsDescendants=true
			local rounding=prompt:FindFirstChildOfClass("UICorner");if rounding then rounding.CornerRadius=UDim.new(0,20) end
			local border=prompt:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			border.Color=Color3.fromRGB(160,165,180);border.Transparency=.75;border.Thickness=1;border.Parent=prompt
			local image=prompt:FindFirstChild("Thumbnail")
			if image then
				image.AnchorPoint=Vector2.zero;image.Position=UDim2.fromScale(0,0);image.Size=UDim2.fromScale(1,1);image.BackgroundTransparency=1;image.ImageTransparency=0;image.ScaleType=Enum.ScaleType.Crop
				-- Round the composited viewport, not each moving image. CanvasGroup
				-- clips its children to its UICorner throughout the slide.
				local c=image:FindFirstChildOfClass("UICorner");if c then c:Destroy() end
				local viewport=Instance.new("CanvasGroup");viewport.Name="ArtworkViewport";viewport.BackgroundTransparency=1;viewport.Size=UDim2.fromScale(1,1);viewport.ClipsDescendants=true;viewport.ZIndex=image.ZIndex;viewport.Parent=prompt
				local mask=Instance.new("UICorner");mask.CornerRadius=UDim.new(0,20);mask.Parent=viewport
				image.Parent=viewport
				local nextImage=image:Clone();nextImage.Name="NextThumbnail";nextImage.ImageTransparency=1;nextImage.Parent=viewport
				local shade=Instance.new("Frame");shade.Name="ArtworkShade";shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=.2;shade.BorderSizePixel=0;shade.ZIndex=image.ZIndex+1;shade.Parent=prompt
				local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,20);corner.Parent=shade
				local gradient=Instance.new("UIGradient");gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,.6)});gradient.Parent=shade
			end
			local layer=prompt:FindFirstChild("Layer");if layer then layer.BackgroundTransparency=1;layer.Position=UDim2.fromOffset(0,0);layer.Size=UDim2.fromScale(1,1);if layer:IsA("ImageLabel") then layer.ImageTransparency=1 end end
			local title=prompt.ScriptTitle;title.AnchorPoint=Vector2.zero;title.Position=UDim2.fromOffset(24,27);title.Size=UDim2.new(1,-70,0,25);title.TextSize=17;title.TextXAlignment=Enum.TextXAlignment.Left
			local description=layer and layer:FindFirstChild("ScriptSubtitle")
			if description then description.AnchorPoint=Vector2.zero;description.Position=UDim2.fromOffset(24,59);description.Size=UDim2.new(1,-112,0,48);description.TextWrapped=true;description.TextSize=12;description.TextYAlignment=Enum.TextYAlignment.Top;description.TextColor3=Color3.fromRGB(220,223,230) end
			local run=prompt:FindFirstChild("Run",true)
			if run and run:IsA("GuiObject") then run.AnchorPoint=Vector2.new(1,1);run.Position=UDim2.new(1,-18,1,-16);run.Size=UDim2.fromOffset(96,34);run.BackgroundColor3=Color3.fromRGB(45,68,110);run.BackgroundTransparency=.08 end
			for _,item in ipairs(prompt:GetDescendants()) do
				if item:IsA("GuiObject") and item.Name~="Thumbnail" and item.Name~="NextThumbnail" and item.Name~="ArtworkViewport" and item.Name~="ArtworkShade" then item.ZIndex=math.max(item.ZIndex,(image and image.ZIndex or 1)+2) end
			end
		end
        -- Group opacity changes keep work proportional to visible surfaces, not row count.
        local function fadeGroup(old,attribute)
         local group=Instance.new("CanvasGroup")
         for _,property in ipairs({"Name","AnchorPoint","Position","Size","SizeConstraint","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderSizePixel","LayoutOrder","ZIndex","Visible","Active","Rotation"})do group[property]=old[property]end
         for key,value in pairs(old:GetAttributes())do group:SetAttribute(key,value)end
         group.GroupTransparency=0;group.BackgroundTransparency=1;group:SetAttribute(attribute,true)
         local parent=old.Parent
         for _,child in ipairs(old:GetChildren())do child.Parent=group end
         old:Destroy();group.Parent=parent;return group
        end
        fadeGroup(objects[1].Playerlist.Interactions,"AltairFadeGroup")
        fadeGroup(objects[1].Character.Interactions,"AltairFadeGroup")
        fadeGroup(objects[1].Scripts.Interactions,"AltairFadeGroup")
        fadeGroup(objects[1].Settings.SettingLists,"AltairFadeGroup")

		objects[1]:SetAttribute("AltairUIRevision",22)
		bindCapsules({Root=objects[1],BuildOnly=true})
		return objects[1]
	end)
	if not ok then
		for _, object in ipairs(objects) do object:Destroy() end
		error("Altair UI | Construction failed: " .. tostring(result), 2)
	end
	return result, bindings
end
