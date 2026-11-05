-- Altair UI is one self-contained factory; its return value is at the end.
-- Navigation (search by symbol):
-- Clock / motionService                  Runtime foundations
-- propertyNames / Molto                 Embedded interface and icon data
-- bindDock / bindRayfieldBridge          Desktop layout and integrations
-- RayfieldOdometer / RayfieldStatistic / RayfieldColorPicker  Licensed controls
-- buildRuler / bindTheme / styleHome      Altair controls and appearance
-- bindCapsules / buildDiscovery          Media, activities and script browser
-- bindings                              Internal helper contract and factory

-- Shared visual vocabulary. These are authored defaults; Theme still owns
-- user tint/lightness, and the existing motion controllers own transitions.
local Design={
 Surface=Color3.fromRGB(16,16,16),Raised=Color3.fromRGB(28,28,28),Well=Color3.fromRGB(38,38,38),
 Ink=Color3.fromRGB(246,246,246),Muted=Color3.fromRGB(164,164,164),Edge=Color3.fromRGB(166,166,166),
 Font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium),
 Heading=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold),
}
function Design.corner(object,radius)
 local corner=object:FindFirstChildOfClass("UICorner")or Instance.new("UICorner")
 corner.CornerRadius=typeof(radius)=="UDim"and radius or UDim.new(0,radius or 12);corner.Parent=object
 return corner
end
function Design.edge(object,alpha)
 local edge=object:FindFirstChildOfClass("UIStroke")or Instance.new("UIStroke")
 edge.Color=Design.Edge;edge.Thickness=.6;edge.Transparency=alpha or .88;edge:SetAttribute("AltairDesignStrokeAlpha",edge.Transparency)
 edge.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;edge.BorderStrokePosition=Enum.BorderStrokePosition.Inner;edge.Parent=object
 return edge
end
function Design.divider(parent,name,position,size)
 local line=parent:FindFirstChild(name)or Instance.new("Frame");line.Name=name
 line.BorderSizePixel=0;line.BackgroundColor3=Design.Edge;line.BackgroundTransparency=.87
 line.Position=position;line.Size=size;line.ZIndex=parent.ZIndex+1;line.Active=false;line.Interactable=false
 line:SetAttribute("AltairDesignRole","divider");line.Parent=parent;return line
end
function Design.text(object,heading)
 if object:GetAttribute("AltairIcon")then return end
 object.FontFace=heading and Design.Heading or Design.Font;object.TextStrokeTransparency=1
end
function Design.control(object,alpha)
 object.BorderSizePixel=0;object.BackgroundColor3=Design.Well;object.BackgroundTransparency=alpha or .28
 object:SetAttribute("AltairMaterialRestAlpha",object.BackgroundTransparency)
 object:SetAttribute("AltairDesignRole","control");Design.corner(object,9);Design.edge(object,.91)
end
-- Only authored material backgrounds participate in the user's opacity setting.
-- Content groups, artwork, shadows and transparent text/icon hitboxes keep
-- their independent animation channels.
function Design.isMaterial(object)
 if not object:IsA("GuiObject")or object:GetAttribute("AltairInsetMaterial")or object:GetAttribute("AltairArtworkForeground")then return false end
 local role=object:GetAttribute("AltairDesignRole")
 if role~="surface"and role~="inset"and role~="control"and not object:GetAttribute("AltairSurface")and not object:GetAttribute("AltairInsetSurface")and not object:GetAttribute("AltairHomeSurface")then return false end
 local rest=object:GetAttribute("AltairMaterialRestAlpha")or object:GetAttribute("AltairDesignRestAlpha")
 return object.BackgroundTransparency<.999 or type(rest)=="number"and rest<.999 or object:GetAttribute("AltairSolidMaterial")==true
end
function Design.isSolid(object)
 if object:GetAttribute("AltairSolidMaterial")==true then return true end
 local root=object:FindFirstAncestorOfClass("ScreenGui")
 return root~=nil and root:GetAttribute("AltairSolidSurfaces")==true
end
-- The authored finish is calibrated at the default 90% opacity. Interpolate
-- from that finish to either endpoint, so 0% and 100% have literal meanings.
function Design.opacityAlpha(authored,transparency)
 authored=math.clamp(tonumber(authored)or .1,0,1)
 transparency=math.clamp(tonumber(transparency)or .1,0,1)
 if transparency<=0 then return 0 elseif transparency>=1 then return 1 end
 if transparency<.1 then return authored*transparency/.1 end
 return authored+(1-authored)*(transparency-.1)/.9
end
function Design.surfaceAlpha(object,transparency)
 local authored=object:GetAttribute("AltairDesignFixedTransparency")
 if type(authored)~="number"then authored=.1+(object:GetAttribute("AltairDesignTransparencyOffset")or 0)end
 return Design.opacityAlpha(authored,transparency)
end
function Design.materialAlpha(object,alpha)
 if alpha>=.99 or not Design.isMaterial(object)then return alpha end
 if object:GetAttribute("AltairMaterialRestAlpha")==nil then object:SetAttribute("AltairMaterialRestAlpha",alpha)end
 local root=object:FindFirstAncestorOfClass("ScreenGui")
 local preference=root and root:GetAttribute("AltairPanelTransparency")
 if type(preference)~="number"then return Design.isSolid(object)and 0 or alpha end
 if preference<=0 then return 0 elseif preference>=1 then return 1 end
 if object:GetAttribute("AltairDesignFixedTransparency")~=nil or object:GetAttribute("AltairDesignTransparencyOffset")~=nil then return Design.surfaceAlpha(object,preference)end
 return Design.opacityAlpha(alpha,preference)
end
-- Theme keeps undimmed palette targets; one root owner composes only Color3
-- outputs. Gradient ramps are not dimmed again through their multipliers.
Design.idleColorOwners=setmetatable({},{__mode="k"})
function Design.idleColor(root,object,property,color)
 local owner=Design.idleColorOwners[root]
 return owner and typeof(color)=="Color3"and owner:ComposeColor(object,property,color)or color
end
function Design.idleBase(root,object,property,color)
 local owner=Design.idleColorOwners[root]
 return owner and typeof(color)=="Color3"and owner:BaseColor(object,property,color)or color
end
function Design.bindIdleColors(root,owner)
 assert(type(owner)=="table"and type(owner.ComposeColor)=="function"and type(owner.BaseColor)=="function","Invalid idle color owner")
 Design.idleColorOwners[root]=owner
 return function()if Design.idleColorOwners[root]==owner then Design.idleColorOwners[root]=nil end end
end
Design.opacityOwners=setmetatable({},{__mode="k"})
Design.opacityTargets=setmetatable({},{__mode="k"})
function Design.freezeMaterial(object)
 local old=Design.opacityOwners[object];Design.opacityOwners[object]=nil;Design.opacityTargets[object]=nil
 if old then
  if type(old)=="table"and old.CancelProperty then old:CancelProperty("BackgroundTransparency")else old:Cancel()end
 end
end

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
local motionStats={requested=0,created=0,reused=0,skipped=0,nativeCreated=0}
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
 if not object:IsA("GuiObject")and not object:IsA("UIComponent")then return false end
 local visual=object
 while visual and not visual:IsA("GuiObject")and not visual:IsA("ScreenGui")do visual=visual.Parent end
 if not visual then return false end
 local screen=visual and(visual:IsA("ScreenGui")and visual or visual:FindFirstAncestorOfClass("ScreenGui"))
 if screen and not screen.Enabled then return true end
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
-- Native tracks stay independent: changing hover Size must not cancel the
-- Position track of the same transition. Single-property motions keep the
-- engine's direct fast path; aggregates only coordinate completion events.
local function propertyMotion(native,object,info,goal)
 local count=0;for _ in pairs(goal)do count+=1 end
 if count<=1 then motionStats.nativeCreated+=1;return native:Create(object,info,goal)end
 local done=Instance.new("BindableEvent")
 local group={PlaybackState=Enum.PlaybackState.Begin,Completed=done.Event}
 local tracks={};local remaining=count;local cancelled=false;local finished=false
 local function finish()
  if finished or remaining>0 then return end;finished=true
  group.PlaybackState=cancelled and Enum.PlaybackState.Cancelled or Enum.PlaybackState.Completed
  done:Fire(group.PlaybackState);task.defer(function()done:Destroy()end)
 end
 local function retire(track,state)
  if track.done then return end;track.done=true;remaining-=1
  if state==Enum.PlaybackState.Cancelled then cancelled=true end
  if track.connection then track.connection:Disconnect();track.connection=nil end
  finish()
 end
 for key,value in pairs(goal)do
  local track={};tracks[key]=track;motionStats.nativeCreated+=1
  track.tween=native:Create(object,info,{[key]=value})
  track.connection=track.tween.Completed:Connect(function(state)retire(track,state)end)
 end
 function group:Play()
  if finished or self.PlaybackState==Enum.PlaybackState.Playing then return end
  self.PlaybackState=Enum.PlaybackState.Playing
  for _,track in pairs(tracks)do if not track.done then track.tween:Play()end end
 end
 function group:CancelProperty(key)
  local track=tracks[key];if not track or track.done then return end
  track.tween:Cancel();retire(track,Enum.PlaybackState.Cancelled)
 end
 function group:Cancel()
  if finished then return end
  for key in pairs(tracks)do self:CancelProperty(key)end
 end
 function group:Pause()
  if finished or self.PlaybackState~=Enum.PlaybackState.Playing then return end
  for _,track in pairs(tracks)do if not track.done then track.tween:Pause()end end
  self.PlaybackState=Enum.PlaybackState.Paused
 end
 function group:Destroy()
  self:Cancel();for _,track in pairs(tracks)do track.tween:Destroy()end
 end
 return group
end
local function motionService(reduced,preserveTiming)
 local native=game:GetService("TweenService")
 local owners=setmetatable({}, {__mode="k"});local targets=setmetatable({}, {__mode="k"})
 return {Freeze=function(_,object,properties)
  local current=owners[object];if not current then return 0 end
  if type(properties)=="string"then properties={properties}end
  local cancelled={};local count=0
  for key,value in pairs(properties or current)do
   local property=type(key)=="number"and value or key;local old=current[property]
   if old then
    if type(old)=="table"and old.CancelProperty then old:CancelProperty(property)
    elseif not cancelled[old]then cancelled[old]=true;old:Cancel()end
    current[property]=nil;if targets[object]then targets[object][property]=nil end;count+=1
   end
  end
  return count
 end,Create=function(_,object,info,goal,options)
  motionStats.requested+=1
  -- Captured visual snapshots already contain the resolved transparency.
  -- Keep ownership, cancellation and closing concealment in this same path.
  local resolvedTransparency=type(options)=="table"and options.ResolvedTransparency==true
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
  if not resolvedTransparency and object:GetAttribute("AltairSurfaceOutline")and goal.Transparency and goal.Transparency<.99 and not transient then goal=table.clone(goal);goal.Transparency=object:GetAttribute("AltairDesignStrokeAlpha")or .86 end
  if not resolvedTransparency and object:GetAttribute("AltairGlowCap")and goal.ImageTransparency then goal=table.clone(goal);goal.ImageTransparency=1-(1-goal.ImageTransparency)*object:GetAttribute("AltairGlowCap")end
  if object:GetAttribute("AltairSharedSwitch") and goal.BackgroundTransparency~=nil then goal=table.clone(goal);goal.BackgroundTransparency=1 end
  if not resolvedTransparency and not closing and goal.BackgroundTransparency~=nil and goal.BackgroundTransparency<.99 and Design.isMaterial(object)then
   goal=table.clone(goal);goal.BackgroundTransparency=Design.materialAlpha(object,goal.BackgroundTransparency)
  end
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
    for property in pairs(goal)do local old=current[property];if old then if type(old)=="table"and old.CancelProperty then old:CancelProperty(property)elseif not cancelled[old]then cancelled[old]=true;old:Cancel()end end;current[property]=nil;target[property]=nil end
    motionStats.skipped+=1
    return completedMotion(hidden and function()if object.Parent then for property,value in pairs(goal)do object[property]=value end end end or nil)
   end
  end
  local cancelled={}
  for property in pairs(goal)do local old=current[property];if old then if type(old)=="table"and old.CancelProperty then old:CancelProperty(property)elseif not cancelled[old]then cancelled[old]=true;old:Cancel()end end end
  local visual=object:IsA("GuiObject") or object:IsA("UIStroke") or object:IsA("UIScale") or object:IsA("UIGradient")
  if visual and not preserveTiming and info.Time>0 and info.RepeatCount==0 and not info.Reverses then
   local layout=goal.Position or goal.Size or goal.Scale or goal.CanvasPosition
   local duration=layout and math.clamp(info.Time,.1,.38) or math.min(info.Time,.22)
   if closing and not layout then duration=math.min(duration,.06) end
   if reduced and reduced() then duration=math.min(duration,.08) end
   local expressive=info.EasingStyle==Enum.EasingStyle.Back or info.EasingStyle==Enum.EasingStyle.Elastic or info.EasingStyle==Enum.EasingStyle.Bounce
   info=TweenInfo.new(duration,layout and(expressive and info.EasingStyle or Enum.EasingStyle.Quint)or Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,false,info.DelayTime)
  end
  if preserveTiming and info.Time>0 then
   local time=closing and math.min(info.Time,.06)or root and root:GetAttribute("AltairReduceMotion")and math.min(info.Time,.08)or info.Time
   if time~=info.Time then info=TweenInfo.new(time,info.EasingStyle,info.EasingDirection,info.RepeatCount,info.Reverses,info.DelayTime)end
  end
  motionStats.created+=1
  local animation=propertyMotion(native,object,info,goal)
  if goal.BackgroundTransparency~=nil then
   Design.opacityOwners[object]=animation;Design.opacityTargets[object]=goal.BackgroundTransparency
   animation.Completed:Once(function()if Design.opacityOwners[object]==animation then Design.opacityOwners[object]=nil;Design.opacityTargets[object]=nil end end)
  end
  for property,value in pairs(goal) do current[property]=animation;target[property]=value end
  animation.Completed:Once(function() for property in pairs(goal) do if current[property]==animation then current[property]=nil;target[property]=nil end end end)
  return animation
 end}
end

-- NOTIFICATIONS BEGIN
local buildNotifications=(function()
-- Compact activity cards share Altair's inset material and content-sized stack.
return function(context)
	local root=context.Root
	local tweenService=motionService(function() return root:GetAttribute("AltairReduceMotion")==true end)
	local textService = game:GetService("TextService")
	local controller = {alive = true, active = {}, pending = {}, nextId = 0}
	local builtHost=root:FindFirstChild("NotificationCapsules")
	local template=builtHost and builtHost:FindFirstChild("CardTemplate")
	if context.RequireBuiltUI then assert(template,"Build.lua is missing the notification card template") end
	local font,titleFont=Design.Font,Design.Heading
	local function logicalWidth()return 300 end
	local function typefaces()return font,titleFont end
	local function boundedText(value,limit)
		value=tostring(value)
		if #value>limit then value=value:sub(1,limit);while #value>0 and utf8.len(value)==nil do value=value:sub(1,-2)end end
		return value
	end
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
		local left=icon and 58 or 18
		local right=28
		local available = width - left - right
		local titleHeight,descriptionHeight
		if measured and measured.width==width then titleHeight,descriptionHeight=measured.title,measured.body
		else
			titleHeight=math.max(17,textService:GetTextSize(title,14,Enum.Font.GothamMedium,Vector2.new(available,1000)).Y)
			descriptionHeight=description~="" and math.max(16,textService:GetTextSize(description,13,Enum.Font.Gotham,Vector2.new(available,1000)).Y) or 0
		end
		titleHeight=math.min(titleHeight,34);descriptionHeight=math.min(descriptionHeight,112)
		return descriptionHeight==0 and math.max(48,29+titleHeight) or 34+titleHeight+descriptionHeight, left, titleHeight, descriptionHeight
	end
	function controller:Layout(instant)
        if #self.active==0 then return end
		if not self.alive or #self.active==0 then return end
		local viewport,origin=root.AbsoluteSize,root.AbsolutePosition
		local factor=root:GetAttribute("AltairDisplayScale") or 1
		local width=math.min(logicalWidth()*factor,math.max(160,viewport.X-40))
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
			local expanded
   for _,child in ipairs(capsules:GetChildren())do if child:GetAttribute('AltairActiveCapsule')then expanded=child;break end end
			add(expanded or capsules:FindFirstChild('Compact'))
		end
  add(root:FindFirstChild('CapsuleActivities'))
		local toasts=root:FindFirstChild('Toasts')
		if toasts and toasts.Visible then for _,v in toasts:GetChildren() do if v.Name~='Template' then add(v) end end end
		local total=0
		for _,record in ipairs(self.active) do
			local height,left,titleHeight,descriptionHeight,right=dimensions(record.title,record.description,record.icon,width/factor,record.measured)
			right=right or 28
			local scale=record.group:FindFirstChild("AltairDisplayScale") or Instance.new("UIScale");scale.Name="AltairDisplayScale";scale.Scale=factor;scale.Parent=record.group
			record.height=height*factor;record.group.Size=UDim2.fromOffset(width/factor,height)
			record.titleLabel.Position,record.titleLabel.Size=UDim2.fromOffset(left,12),UDim2.new(1,-left-right,0,titleHeight)
			record.body.Position,record.body.Size=UDim2.fromOffset(left,20+titleHeight),UDim2.new(1,-left-right,0,descriptionHeight)
			local icon=record.iconLabel;local well=record.iconWell
			if icon then icon.Position=UDim2.new(0,30,.5,0);if well then well.Position=icon.Position end end
			record.body.Visible=descriptionHeight>0
			local rule=record.group:FindFirstChild("ContentRule");if rule then rule.Visible=descriptionHeight>0;rule.Position=UDim2.fromOffset(left,16+titleHeight);rule.Size=UDim2.new(1,-left-18,0,1)end
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
		group:SetAttribute("AltairDesignRole","notification");Design.corner(group,14)
        -- CanvasGroup gradients tint the composited text too. Material belongs on its own layer.
        local background=Instance.new("Frame");background.Name="CardBackground";background.Size=UDim2.fromScale(1,1);background.BackgroundColor3=Design.Surface;local alpha=root:GetAttribute("AltairPanelTransparency")or .1;background.BackgroundTransparency=Design.opacityAlpha(.14,alpha);background.BorderSizePixel=0;background.ZIndex=350;background:SetAttribute("AltairSurface",true);background:SetAttribute("AltairDesignTransparencyOffset",.04);background.Parent=group
        local round=group:FindFirstChildOfClass("UICorner");if round then round:Clone().Parent=background end
        local gradient=group:FindFirstChildOfClass("UIGradient");if gradient then gradient.Parent=background end
        local outline=group:FindFirstChildOfClass("UIStroke");if outline then outline.Parent=background end
        Design.corner(background,14);Design.edge(background,.88)
        if gradient then gradient.Rotation=110;gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(224,224,224)) end
        group.BackgroundTransparency=1;group:SetAttribute("AltairNotificationCard",true)
		item.group,item.generation,item.connections=group,0,{};item.fresh=true
		item.titleLabel=group:FindFirstChild("Title") or label(group,"Title",item.title,14,Color3.new(1,1,1))
		item.titleLabel.TextColor3=Color3.new(1,1,1);item.titleLabel.Text=item.title;item.titleLabel.FontFace=titleFont
		item.body=group:FindFirstChild("Description") or label(group,"Description",item.description,13,Color3.new(1,1,1));item.body.TextColor3=Color3.new(1,1,1)
		item.body.Text=item.description;item.body.FontFace=font;item.body.TextTransparency=.24
		for _,entry in ipairs({{item.titleLabel,titleFont},{item.body,font}})do
			local object,face=entry[1],entry[2]
			if not object:GetAttribute("AltairStyleBase_FontFaceFamily")then object:SetAttribute("AltairStyleBase_FontFaceFamily",face.Family);object:SetAttribute("AltairStyleBase_FontFaceWeight",face.Weight.Name);object:SetAttribute("AltairStyleBase_FontFaceStyle",face.Style.Name)end
		end
		local rule=Design.divider(group,"ContentRule",UDim2.new(),UDim2.new());rule.ZIndex=351;rule.BackgroundTransparency=.93
		local icon=group:FindFirstChild("Icon")
		if not icon then
			icon=Instance.new("ImageLabel");icon.Name="Icon";icon.BackgroundTransparency=1
			icon.Size,icon.Position,icon.AnchorPoint=UDim2.fromOffset(20,20),UDim2.new(0,30,.5,0),Vector2.new(.5,.5)
			icon.ImageColor3,icon.ZIndex,icon.Parent=Color3.new(1,1,1),351,group
		end
		local friend,staff=group:FindFirstChild("FriendIcon"),group:FindFirstChild("StaffIcon")
		if friend then friend.Visible=false end
		if staff then staff.Visible=false end
		icon.Visible=item.icon~=nil;icon.Image=item.icon or "";icon.Size=UDim2.fromOffset(20,20);icon.Position=UDim2.new(0,30,.5,0);icon.AnchorPoint=Vector2.new(.5,.5)
		local well=Instance.new("Frame");well.Name="IconWell";well.Size=UDim2.fromOffset(32,32);well.AnchorPoint=Vector2.new(.5,.5);well.Position=icon.Position;well.BackgroundColor3=Design.Well;well.BackgroundTransparency=.22;well.BorderSizePixel=0;well.ZIndex=350;well.Visible=icon.Visible;well.Parent=group;Design.corner(well,10)
		item.iconLabel,item.iconWell=icon,well
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
		local factor=root:GetAttribute("AltairDisplayScale")or 1
		local width=math.min(logicalWidth()*factor,math.max(160,root.AbsoluteSize.X-40))/factor
		local used=0
		for _,record in ipairs(controller.active) do used+=record.height+8 end
		while #controller.pending>0 and #controller.active<5 do
			local item=controller.pending[1]
			if not item.ready then break end
			local height=dimensions(item.title,item.description,item.icon,width,item.measured)*factor
			if #controller.active>0 and used+height>root.AbsoluteSize.Y-48 then break end
			spawnRecord(table.remove(controller.pending,1));used+=height+8
		end
	end
	local function measure(item)
		item.measureGeneration=(item.measureGeneration or 0)+1;local generation=item.measureGeneration
		task.spawn(function()
			local factor=root:GetAttribute("AltairDisplayScale")or 1;local width=math.min(logicalWidth()*factor,math.max(160,root.AbsoluteSize.X-40))/factor
			local bodyFace,headingFace=typefaces();local left=item.icon and 58 or 18;local right=28
			local params=Instance.new("GetTextBoundsParams");params.Width=math.max(1,width-left-right);params.RichText=false
			local ok,measured=pcall(function()
				params.Font=headingFace;params.Size=14;params.Text=item.title
				local titleHeight=math.max(17,math.ceil(textService:GetTextBoundsAsync(params).Y))
				params.Font=bodyFace;params.Size=13;params.Text=item.description
				return{width=width,title=titleHeight,body=item.description~=""and math.max(16,math.ceil(textService:GetTextBoundsAsync(params).Y))or 0}
			end);params:Destroy()
			if not controller.alive or item.closing or generation~=item.measureGeneration then return end
			if ok then item.measured=measured end;item.ready=true
			if item.group then controller:Layout()end;pump()
		end)
	end
	local function removePending(item)
		local pending=table.find(controller.pending,item)
		if pending then
			item.closing=true;item.measureGeneration=(item.measureGeneration or 0)+1
			table.remove(controller.pending,pending)
			return true
		end
		return false
	end
	local function dismissItem(item)
		if not controller.alive then return end
		if removePending(item) then pump()
		elseif item.group then controller:Dismiss(item) end
	end
	function controller:Notify(title, description, icon, options)
		if not self.alive then return nil end
		options = type(options) == "table" and options or {}
		title, description = boundedText(title or "Altair",160), boundedText(description or "",1200)
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
						dismissItem(record)
					end}
				end
			end end
		end
		self.nextId += 1
		local item = {id=self.nextId,title=title,description=description,icon=icon,key=key,
			duration=duration}
		local evicted=#self.pending>=24 and removePending(self.pending[1])
		self.pending[#self.pending+1] = item
		measure(item)
		if evicted then pump()end
		return {Dismiss=function()
			dismissItem(item)
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
	connect(root:GetAttributeChangedSignal("AltairPanelTransparency"),function()
        local alpha=root:GetAttribute("AltairPanelTransparency")or .1
        local target=Design.opacityAlpha(.14,alpha)
		for _,record in ipairs(controller.active)do
			local background=record.group and record.group:FindFirstChild("CardBackground")
			if background and not record.closing then tween(background,.18,{BackgroundTransparency=target})end
		end
	end)
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
 if object:GetAttribute("AltairPreserveSourceIcon")==true then return end
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
   scale.Name="AltairDisplayScale"
   scale.Scale=factor*(tonumber(panel:GetAttribute("AltairDialogDensity"))or 1)
   if panel:GetAttribute("ReferenceScriptSearch")then panel:SetAttribute("AltairSurfaceScale",factor)end
   scale.Parent=panel
  end
 end
 return factor
end

-- A single SmartBar shell reflows without rotating its text or button icons.


local function bindDock(root)
 local bar,drag=root.SmartBar,root.Drag
 local back=bar.Back;local buttons=back.Buttons;local clock=back.Time;local clockRule=clock:FindFirstChild("ClockDivider")
 local layout=buttons:FindFirstChildOfClass("UIListLayout")
 local motion=motionService();local animations={};local view={alive=true,NavigationGeometryOwnership=1,mode=nil,vertical=false,generation=0};local sizeLimit
 local base={backPosition=back.Position,backSize=back.Size,backAnchor=back.AnchorPoint,
  buttonsPosition=buttons.Position,buttonsSize=buttons.Size,buttonsAnchor=buttons.AnchorPoint,
  timePosition=clock.Position,timeSize=clock.Size,timeAnchor=clock.AnchorPoint,timeAlign=clock.TextXAlignment,
  ampmPosition=clock.AMPM.Position,ampmSize=clock.AMPM.Size,ampmAnchor=clock.AMPM.AnchorPoint,ampmAlign=clock.AMPM.TextXAlignment}
 local dockProfile={width=300,height=60,cell=34,
   backAnchor=base.backAnchor,backPosition=base.backPosition,backSize=base.backSize,
   buttonsAnchor=base.buttonsAnchor,buttonsPosition=base.buttonsPosition,buttonsSize=base.buttonsSize,
   timeAnchor=base.timeAnchor,timePosition=base.timePosition,timeSize=base.timeSize,timeAlign=base.timeAlign,
   ampmAnchor=base.ampmAnchor,ampmPosition=base.ampmPosition,ampmSize=base.ampmSize,ampmAlign=base.ampmAlign,
 }
 local function profile()return dockProfile end
 local horizontal={};local names={"Home","Character","Scripts","Playerlist","Settings"}
 local tileNames={};for _,name in ipairs(names)do tileNames[name]=true end
 local function mirrorPosition(position,size,pivot)
  local shift=2*pivot.X-1
  return UDim2.new(1-position.X.Scale+size.X.Scale*shift,-position.X.Offset+size.X.Offset*shift,position.Y.Scale,position.Y.Offset)
 end
 local function pixel(p,size)return Vector2.new(p.X.Scale*size.X+p.X.Offset,p.Y.Scale*size.Y+p.Y.Offset)end
 -- Moving offsets are integer-valued in the engine. Scale coordinates retain
 -- the fractional phase at every UI scale, including interrupted transitions.
 local function units(point,parentSize)
  return UDim2.new(parentSize.X>0 and point.X/parentSize.X or 0,parentSize.X>0 and 0 or point.X,parentSize.Y>0 and point.Y/parentSize.Y or 0,parentSize.Y>0 and 0 or point.Y)
 end
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
 local items={};for i,o in ipairs(buttons:GetChildren())do if o:IsA("GuiObject")then
  if tileNames[o.Name]then items[#items+1]={object=o,index=i}
  elseif o.Name=="Placeholder"then o.Visible=false;o.Active=false;o.Interactable=false end
 end end
 table.sort(items,function(a,b)return a.object.LayoutOrder==b.object.LayoutOrder and a.index<b.index or a.object.LayoutOrder<b.object.LayoutOrder end)
 local canonicalSize=Vector2.new(300,60)
 local canonicalBackSize=pixel(base.backSize,canonicalSize)
 local canonicalButtonsSize=pixel(base.buttonsSize,canonicalBackSize)
 local canonicalButtonsTop=pixel(base.buttonsPosition,canonicalBackSize)-canonicalButtonsSize*base.buttonsAnchor
 local total=0;local padding=layout and(layout.Padding.Scale*canonicalButtonsSize.X+layout.Padding.Offset)or 5
 for _,item in ipairs(items)do total+=item.object.Size.X.Offset end;total+=math.max(0,#items-1)*padding
 local cursor=(canonicalButtonsSize.X-total)/2
 for _,item in ipairs(items)do local o=item.object;horizontal[o]=canonicalButtonsTop+Vector2.new(cursor+o.Size.X.Offset*o.AnchorPoint.X,canonicalButtonsSize.Y*.5);cursor+=o.Size.X.Offset+padding end
 local scales={};for _,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then local scale=o:FindFirstChildOfClass("UIScale")or Instance.new("UIScale");scale.Name="DockTransitionScale";scale.Parent=o;scales[o]=scale end end
 -- Dock is the only tile pose owner in both orientations. The authored layout
 -- supplies canonical order/padding, then stays detached until root destruction.
 if layout then layout.Parent=nil end
 local function stopPose()
  local tween,connection,progress=view.progressTween,view.progressConnection,view.progress
  view.progressTween=nil;view.progressConnection=nil;view.progress=nil
  if connection then connection:Disconnect()end
  if tween then tween:Cancel()end
  if progress then progress:Destroy()end
 end
 function view:BarSize()local p=profile();return self.vertical and UDim2.fromOffset(p.height,p.width)or UDim2.fromOffset(p.width,p.height)end
 function view:ButtonSize(closed)local size=profile().cell-(closed and 4 or 0);return UDim2.fromOffset(size,size)end
 function view:DragSize(length,thickness)return self.vertical and UDim2.fromOffset(thickness,length)or UDim2.fromOffset(length,thickness)end
 function view:SetNavigationState(name,shown)
  if not self.alive then return end
  shown=shown==true;name=shown and tileNames[name]and name or nil
  local initial=self.shown==nil
  if not initial and self.shown==shown and self.selected==name then
   -- A preference change must settle an in-flight pose even when its target
   -- selection and visibility have not changed.
   if root:GetAttribute("AltairReduceMotion")and self.progressTween then self:Apply(self.mode or "bottom",false,true,true)end
   return
  end
  self.shown=shown;self.selected=name
  self:Apply(self.mode or "bottom",not initial,true,true)
 end
 function view:Mirror(mirrored,animate,force)
  if self.vertical then return end
  if self.mirrored==mirrored and not force then return end
  self.mirrored=mirrored
  -- Main resolves orientation before the horizontal clock side. Reuse the
  -- current rendered geometry when that second decision arrives mid-morph.
  if not force then self:Apply(self.mode or "bottom",animate,true);return end
  local p=profile()
  anchor(back,p.backAnchor);anchor(buttons,Vector2.new(.5,.5));anchor(clock,p.timeAnchor);anchor(clock.AMPM,p.ampmAnchor)
  clock.TextXAlignment=p.timeAlign;clock.AMPM.TextXAlignment=p.ampmAlign
  -- Main retains the material fades, including an interrupted bar close.
  if clockRule then clockRule.Visible=true end
  set(back,{Position=mirrored and mirrorPosition(p.backPosition,p.backSize,p.backAnchor)or p.backPosition,Size=p.backSize},animate)
  set(buttons,{Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1,1)},animate)
  set(clock,{Position=mirrored and mirrorPosition(p.timePosition,p.timeSize,p.timeAnchor)or p.timePosition,Size=p.timeSize},animate)
  set(clock.AMPM,{Position=p.ampmPosition,Size=p.ampmSize},animate)
  if clockRule then set(clockRule,{Position=UDim2.new(mirrored and 0 or 1,mirrored and -3 or 2,0,1),Size=UDim2.fromOffset(1,p.height==72 and 32 or 26)},animate)end
 end
 function view:Apply(mode,animate,retarget,tilesOnly)
  if not self.alive then return end
  local p=dockProfile
  if self.mode==mode and not retarget then return end
  local vertical=mode=="left"or mode=="right";local changed=self.vertical~=vertical;local initial=self.mode==nil
  local reduced=root:GetAttribute("AltairReduceMotion")==true
  animate=animate==true and not reduced
  local orientationActive=changed or self.morphActive==true
  local updateHandle=changed or initial or reduced and orientationActive
  self.mode=mode;root:SetAttribute("AltairDock",mode);root:SetAttribute("AltairDockButtonSize",p.cell)
  if not changed and not initial and not retarget then return end
  self.generation+=1;local generation=self.generation
  stopPose()
  if updateHandle or reduced then for _,t in pairs(animations)do t:Cancel()end;table.clear(animations)end
  local factor=root:GetAttribute("AltairDisplayScale")or 1
  local rendered={}
  for _,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then rendered[o]=(o.AbsolutePosition+o.AbsoluteSize*o.AnchorPoint-bar.AbsolutePosition)/factor end end
  self.vertical=vertical;bar:SetAttribute("AltairVertical",vertical);drag:SetAttribute("AltairVertical",vertical)
  local startSize=bar.AbsoluteSize.X>0 and bar.AbsoluteSize/factor or pixel(bar.Size,root.AbsoluteSize)
  local targetSize=vertical and Vector2.new(p.height,p.width)or Vector2.new(p.width,p.height)
  local starts,targets={},{ }
  local targetBackSize=pixel(p.backSize,targetSize)
  local targetBackAnchor=pixel(self.mirrored and mirrorPosition(p.backPosition,p.backSize,p.backAnchor)or p.backPosition,targetSize)
  local targetBackTop=targetBackAnchor-targetBackSize*p.backAnchor
  for o,point in pairs(rendered)do starts[o]=point end
  local startBackSize=back.AbsoluteSize/factor
  local startBackCenter=(back.AbsolutePosition+back.AbsoluteSize/2-bar.AbsolutePosition)/factor
  local startClock=(clock.AbsolutePosition+clock.AbsoluteSize*.5-bar.AbsolutePosition)/factor
  local startTimeSize=clock.AbsoluteSize.X>0 and clock.AbsoluteSize/factor or pixel(clock.Size,startBackSize)
  local startAMPM=pixel(clock.AMPM.Position,startTimeSize)-pixel(clock.AMPM.Size,startTimeSize)*clock.AMPM.AnchorPoint;local startAMPMSize=pixel(clock.AMPM.Size,startTimeSize)
  local startScales={};for o,value in pairs(scales)do startScales[o]=value.Scale end
  local startCells,targetCells={},{};local totalExtra=0
  local restCell=p.cell-(self.shown==false and 4 or 0)
  for _,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then
   startCells[o]=pixel(o.Size,buttons.AbsoluteSize/factor)
   local cell=restCell+(self.shown and self.selected==name and 4 or 0)
   targetCells[o]=Vector2.new(cell,cell);totalExtra+=cell-p.cell
  end end
  local ruleStart=clockRule and clockRule.Position;local ruleSize=clockRule and clockRule.Size
  local ruleTarget=vertical and UDim2.fromOffset(10,35)or UDim2.new(self.mirrored and 0 or 1,self.mirrored and -3 or 2,0,1)
  local ruleTargetSize=vertical and UDim2.fromOffset(34,1)or UDim2.fromOffset(1,26)
  local horizontalTargets={}
  local precedingExtra=0
  for i,name in ipairs(names)do local o=buttons:FindFirstChild(name);if o then
   -- Pack changes around the strip centre. An open selected tile adds four
   -- pixels: its centre stays put and each side gives it two pixels of room.
   local extra=targetCells[o].X-p.cell
   local shift=precedingExtra+extra*.5-totalExtra*.5;precedingExtra+=extra
   horizontalTargets[o]=(horizontal[o]or Vector2.new(27+(i-1)*39,25))+Vector2.new(shift,0)
   targets[o]=vertical and Vector2.new(30,100+(i-1)*40+shift)or targetBackTop+horizontalTargets[o]
  end end
  local endBackSize=vertical and Vector2.new(50,214)or targetBackSize
  local endBackCenter=vertical and Vector2.new(30,180)or targetBackTop+targetBackSize/2
  local targetClock=vertical and Vector2.new(30,28)or targetBackTop+pixel(self.mirrored and mirrorPosition(p.timePosition,p.timeSize,p.timeAnchor)or p.timePosition,targetBackSize)
  local targetTimeSize=vertical and Vector2.new(54,19)or pixel(p.timeSize,targetBackSize)
  if not vertical then targetClock+=targetTimeSize*(Vector2.new(.5,.5)-p.timeAnchor)end
  local targetAMPM=vertical and Vector2.new(7,19)or pixel(p.ampmPosition,targetTimeSize)
  local targetAMPMSize=vertical and Vector2.new(40,11)or pixel(p.ampmSize,targetTimeSize)
  if not vertical then targetAMPM-=targetAMPMSize*p.ampmAnchor end
  anchor(back,Vector2.new(.5,.5));anchor(buttons,Vector2.new(.5,.5));anchor(clock,Vector2.new(.5,.5));anchor(clock.AMPM,Vector2.zero)
  buttons.Position=UDim2.fromScale(.5,.5);buttons.Size=UDim2.fromScale(1,1)
  -- Main uses this flag for drag-release settling. Tile feedback must not
  -- masquerade as a shell orientation change.
  self.morphActive=orientationActive
  local function ease(t)t=math.clamp(t,0,1);return t*t*t*(t*(t*6-15)+10)end
  local function draw(t)
   local fan=ease(t)
   local size=startSize:Lerp(targetSize,fan)
   self.currentSize=size
   if orientationActive then bar.Size=units(size,root:IsDescendantOf(game)and root.AbsoluteSize or Vector2.zero)end
   if sizeLimit then sizeLimit.MinSize=size;sizeLimit.MaxSize=size end
   local points,cells={},{}
   for o,target in pairs(targets)do
    local point=starts[o]:Lerp(target,fan)
    points[o]=point;cells[o]=startCells[o]:Lerp(targetCells[o],fan)
   end
   -- Upright square icons need a little more room on a diagonal than their
   -- centre-line spacing. Bound the shared scale by actual pairwise spacing.
   local cap=1;local seen={}
   for o,point in pairs(points)do
    for _,other in ipairs(seen)do
     local delta=point-points[other];local combined=(cells[o]+cells[other])*.5
     cap=math.min(cap,math.max((math.abs(delta.X)-1)/math.max(1,combined.X),(math.abs(delta.Y)-1)/math.max(1,combined.Y)))
    end
    seen[#seen+1]=o
   end
   for o,value in pairs(scales)do value.Scale=math.min(math.max(.05,cap),startScales[o]+(1-startScales[o])*fan)end
   local rawSize=startBackSize:Lerp(endBackSize,fan);local rawCenter=startBackCenter:Lerp(endBackCenter,fan)
   local left=math.max(5,rawCenter.X-rawSize.X/2);local right=math.min(size.X-5,rawCenter.X+rawSize.X/2)
   local top=math.max(5,rawCenter.Y-rawSize.Y/2);local bottom=math.min(size.Y-5,rawCenter.Y+rawSize.Y/2)
   local backTop=Vector2.new(left,top);local backSize=Vector2.new(math.max(1,right-left),math.max(1,bottom-top));local backCenter=backTop+backSize/2
   back.Position=units(backCenter,size);back.Size=units(backSize,size)
   for o,point in pairs(points)do local pointInBack=point-backTop;o.Position=units(pointInBack,backSize);o.Size=units(cells[o],backSize)end
   local cp=startClock:Lerp(targetClock,fan)-backTop
   clock.Position=units(cp,backSize)
   local ts=startTimeSize:Lerp(targetTimeSize,fan);clock.Size=units(ts,backSize)
   local ap=startAMPM:Lerp(targetAMPM,fan);local az=startAMPMSize:Lerp(targetAMPMSize,fan);clock.AMPM.Position=units(ap,ts);clock.AMPM.Size=units(az,ts)
   if clockRule then clockRule.Position=ruleStart:Lerp(ruleTarget,fan);clockRule.Size=ruleSize:Lerp(ruleTargetSize,fan)end
  end
  local function complete()
   if generation~=self.generation then return end
   draw(1);self.morphActive=false
   -- Endpoints are authored integer logical dimensions. Keep them in offsets:
   -- a settled bar must not inherit a previous viewport's normalization ratio.
   bar.Size=UDim2.fromOffset(targetSize.X,targetSize.Y)
   if sizeLimit then sizeLimit:Destroy();sizeLimit=nil end
   if not vertical then
    self:Mirror(self.mirrored==true,false,true)
    for o,position in pairs(horizontalTargets)do if o.Parent then o.Position=UDim2.fromOffset(position.X,position.Y)end end
   end
   for o,cell in pairs(targetCells)do if o.Parent then o.Size=UDim2.fromOffset(cell.X,cell.Y)end end
  end
  if animate then
   -- A parent may resize before AbsoluteSize observers are dispatched. The
   -- active-only constraint retains fractional logical dimensions independently
   -- of that parent normalization, then releases the authored endpoint.
   if orientationActive then
    if not sizeLimit then sizeLimit=Instance.new("UISizeConstraint");sizeLimit.Name="DockMotionBounds"end
    sizeLimit.MinSize=startSize;sizeLimit.MaxSize=startSize;sizeLimit.Parent=bar
   end
   local progress=Instance.new("NumberValue");self.progress=progress
   local connection=progress.Changed:Connect(draw);self.progressConnection=connection
   self.progressTween=motion:Create(progress,TweenInfo.new(tilesOnly and .24 or .46,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=1})
   self.progressTween.Completed:Once(function(state)
    connection:Disconnect();if self.progressConnection==connection then self.progressConnection=nil end
    if self.progress==progress then self.progress=nil;self.progressTween=nil;progress:Destroy()end
    if state==Enum.PlaybackState.Completed and self.alive then complete()end
   end)
   self.progressTween:Play()
  else complete()end
  if updateHandle then
   set(drag,{Size=self:DragSize(150,20)},animate)
   local line=drag:FindFirstChild("Drag")
   if line then
   local oldVertical=line.Size.Y.Offset>line.Size.X.Offset
   local angle=(oldVertical and 90 or 0)+line.Rotation
   local length=math.max(line.Size.X.Offset,line.Size.Y.Offset)
   line.Size=self:DragSize(length,2)
   line.Rotation=animate and angle-(vertical and 90 or 0)or 0
   set(line,{Size=self:DragSize(100,2)},animate)
   if animate then local rotation=motion:Create(line,TweenInfo.new(.36,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Rotation=0});animations.HandleRotation=rotation;rotation:Play()end
   end
  end
 end
 root.Destroying:Connect(function()view.alive=false;view.generation+=1;stopPose();for _,t in pairs(animations)do t:Cancel()end;if sizeLimit then sizeLimit:Destroy();sizeLimit=nil end;if layout then layout:Destroy()end end)
 return view
end

local function bindRayfieldBridge(context)
 local root,capsules=context.Root,context.Capsules
 local env=getgenv and getgenv()or _G
 local bridge={alive=true,records=setmetatable({}, {__mode="k"}),libraries=setmetatable({}, {__mode="k"})}
 local native=game:GetService("TweenService")
 -- Exact Rayfield Gen2 1.2.3 defaults. Upstream themes/default.luau,
 -- Copyright (c) 2026 Corridon Capital, MPL-2.0; THIRD_PARTY_NOTICES.md.
 local function rgb(r,g,b)return Color3.fromRGB(r,g,b)end
 local function gradient(a,b,c)
  if c then return ColorSequence.new({ColorSequenceKeypoint.new(0,a),ColorSequenceKeypoint.new(.9999,b),ColorSequenceKeypoint.new(1,c)})end
  return ColorSequence.new(a,b)
 end
 local defaults={
  CornerRoundness=UDim.new(0,20),WindowColor=gradient(rgb(10,10,10),rgb(25,25,25),rgb(35,35,35)),ShadowColor=rgb(20,20,20),
  ElementStroke=rgb(35,35,35),ElementGradient=gradient(rgb(30,30,30),rgb(35,35,35),rgb(35,35,35)),ElementStrokeGradient=gradient(rgb(48,48,48),rgb(58,58,58),rgb(48,48,48)),
  TabColor=rgb(255,255,255),TabBackground=gradient(rgb(50,50,50),rgb(35,35,35)),TabStroke=gradient(rgb(95,95,95),rgb(50,50,50)),
  SliderBackground=rgb(47,47,47),SliderBackgroundHover=rgb(60,60,60),SliderProgress=gradient(rgb(0,170,127),rgb(0,134,98)),SliderStroke=rgb(255,255,255),ActionColor=rgb(255,255,255),
  TitleFont=Font.new("rbxassetid://12187365364",Enum.FontWeight.SemiBold),Font=Font.new("rbxassetid://12187365364",Enum.FontWeight.Medium),ContentColor=rgb(255,255,255),
  LiveAnimation=false,DarkToggleOverlay=true,ElementTransparency=0,ElementStrokeTransparency=0,ElementStrokeHoverTransparency=0,ElementStrokeHover=rgb(50,50,50),ElementCornerRadius=UDim.new(0,12),ElementTextHoverColor=rgb(255,255,255),TitlingColor=rgb(255,255,255),DropdownHighlight=rgb(255,255,255),
  AccentColor=rgb(23,153,110),AccentStroke=rgb(32,201,144),AccentGlow=.4,StatBackground=rgb(25,25,25),SliderHandle=rgb(255,255,255),PillCornerRadius=UDim.new(1,0),
  ToggleTrack=rgb(0,0,0),ToggleTrackTransparency=.9,ToggleKnobOff=rgb(255,255,255),ToggleKnobOffTransparency=.8,FieldBackground=rgb(255,255,255),FieldTransparency=.9,FieldGlow=rgb(255,255,255),PlaceholderColor=rgb(178,178,178),SurfaceStroke=rgb(255,255,255),
  NeutralButton=rgb(38,38,38),NeutralButtonHover=rgb(54,54,54),NeutralButtonStroke=rgb(255,255,255),ErrorColor=rgb(185,50,50),ErrorStrokeColor=rgb(240,75,75),
 }
 bridge.DefaultTheme=table.freeze(table.clone(defaults));bridge.themingEnabled=true
 local function equal(a,b)
  if typeof(a)~=typeof(b)then return false end
  if typeof(a)=="ColorSequence"then
   local x,y=a.Keypoints,b.Keypoints;if #x~=#y then return false end
   for i,p in ipairs(x)do if p.Time~=y[i].Time or p.Value~=y[i].Value then return false end end
   return true
  elseif typeof(a)=="Font"then return a.Family==b.Family and a.Weight==b.Weight and a.Style==b.Style end
  return a==b
 end
 local function same(a,b)
  if type(a)~="table"or type(b)~="table"then return false end
  for key,value in pairs(a)do if not equal(value,b[key])then return false end end
  for key in pairs(b)do if a[key]==nil then return false end end
  return true
 end
 local function isDefault(theme)
  if type(theme)~="table"then return false end
  for key,value in pairs(defaults)do
   local current=theme[key]
   if key=="Font"or key=="TitleFont"then
    if typeof(current)~="Font"or current.Weight~=value.Weight or current.Style~=Enum.FontStyle.Normal or(current.Family~=value.Family and current.Family~="rbxasset://fonts/families/BuilderSans.json")then return false end
   elseif not equal(current,value)then return false end
  end
  for key in pairs(theme)do if defaults[key]==nil then return false end end
  return true
 end
 local function stopThemeMotion(record)
  if record.themeConnection then record.themeConnection:Disconnect();record.themeConnection=nil end
  local progress=record.themeProgress;record.themeProgress=nil
  for _,animation in ipairs(record.themeAnimations or {})do animation:Cancel()end
  record.themeAnimations={}
  if progress then progress:Destroy()end
 end
 local function sample(sequence,time)
  local keys=sequence.Keypoints
  for i=2,#keys do local a,b=keys[i-1],keys[i];if time<=b.Time then return a.Value:Lerp(b.Value,(time-a.Time)/math.max(1e-7,b.Time-a.Time))end end
  return keys[#keys].Value
 end
 local function applyWindowTheme(record,target,animate)
  local window=record.window;if not window.main.Parent or window.unloaded then return false end
  stopThemeMotion(record)
  -- Hide/Show owns the collapsed shell's corner morph. A theme update must
  -- change its future expanded radius without touching the visible pill.
  local hiddenCorner=window.hidden and window.windowCorner
  local hiddenRadius=hiddenCorner and hiddenCorner.CornerRadius
  local themeProperties=window.themeProperties
  local hiddenBinding=hiddenCorner and themeProperties[hiddenCorner]
  local originalTheme=window.theme;local themeBefore=table.clone(originalTheme)
  local previous={}
  for object,properties in pairs(themeProperties)do if typeof(object)=="Instance"and object.Parent and object~=hiddenCorner then
   for property,binding in pairs(properties)do local ok,value=pcall(function()return object[property]end);if ok then previous[#previous+1]={object=object,property=property,binding=binding,from=value}end end
  end end
  if hiddenBinding then themeProperties[hiddenCorner]=nil end
  local ok=pcall(record.changeTheme,window,target)
  if hiddenBinding then themeProperties[hiddenCorner]=hiddenBinding end
  if hiddenCorner and hiddenCorner.Parent and hiddenCorner.CornerRadius~=hiddenRadius then hiddenCorner.CornerRadius=hiddenRadius end
  if not ok then
   -- An unsupported upstream binding can throw after changing some surfaces.
   -- Roll back this attempt, including any native tweens it already started.
   window.theme=originalTheme
   for key in pairs(originalTheme)do if themeBefore[key]==nil then originalTheme[key]=nil end end
   for key,value in pairs(themeBefore)do originalTheme[key]=value end
   for _,entry in ipairs(previous)do if entry.object.Parent then pcall(function()
    local kind=typeof(entry.from)
    if kind=="Color3"or kind=="number"or kind=="UDim"or kind=="UDim2"or kind=="Vector2"then
     local cancelled=native:Create(entry.object,TweenInfo.new(0),{[entry.property]=entry.from});cancelled:Play();cancelled:Cancel()
    end
    entry.object[entry.property]=entry.from
   end)end end
   return false
  end
  record.themeApplied=table.clone(window.theme)
  local duration=root:GetAttribute("AltairReduceMotion")and .08 or .28
  animate=animate~=false and not window.hidden
  local sequences={}
  for _,entry in ipairs(previous)do
   local got,goal=pcall(function()local b=entry.binding;return type(b)=="table"and b[2](window.theme[b[1]])or window.theme[b]end)
   if got and goal~=nil and entry.object.Parent then
    local kind=typeof(goal)
    if kind=="ColorSequence"and typeof(entry.from)==kind then
     if animate and not equal(entry.from,goal)then
      local times,seen={},{}
      for _,sequence in ipairs({entry.from,goal})do for _,point in ipairs(sequence.Keypoints)do if not seen[point.Time]then seen[point.Time]=true;times[#times+1]=point.Time end end end
      table.sort(times);entry.points={};entry.target=goal
      for _,time in ipairs(times)do entry.points[#entry.points+1]={time,sample(entry.from,time),sample(goal,time)}end
      entry.object[entry.property]=entry.from;sequences[#sequences+1]=entry
     else entry.object[entry.property]=goal end
    elseif kind=="Color3"or kind=="number"or kind=="UDim"or kind=="UDim2"or kind=="Vector2"then
     local animation=native:Create(entry.object,TweenInfo.new(animate and duration or 0,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{[entry.property]=goal})
     if animate then entry.object[entry.property]=entry.from;record.themeAnimations[#record.themeAnimations+1]=animation;animation:Play()
     else animation:Play();animation:Cancel();entry.object[entry.property]=goal end
    end
   end
  end
  if #sequences>0 then
   local progress=Instance.new("NumberValue");record.themeProgress=progress
   record.themeConnection=progress.Changed:Connect(function(alpha)
    for _,entry in ipairs(sequences)do if entry.object.Parent then local points={};for _,point in ipairs(entry.points)do points[#points+1]=ColorSequenceKeypoint.new(point[1],point[2]:Lerp(point[3],alpha))end;entry.object[entry.property]=ColorSequence.new(points)end end
   end)
   local animation=native:Create(progress,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Value=1});record.themeAnimations[#record.themeAnimations+1]=animation
   animation.Completed:Once(function(status)if record.themeProgress==progress then
    if status==Enum.PlaybackState.Completed then for _,entry in ipairs(sequences)do if entry.object.Parent then entry.object[entry.property]=entry.target end end end
    if record.themeConnection then record.themeConnection:Disconnect();record.themeConnection=nil end;record.themeProgress=nil;progress:Destroy()
   end end);animation:Play()
  end
  return true
 end
 local function restoredTheme(record)
  local current=table.clone(record.window.theme)
  for key,value in pairs(record.themeOriginal)do if not record.themeApplied or equal(current[key],record.themeApplied[key])then current[key]=value end end
  return current
 end
 local function stopAutomaticTheme(record,restore,animate)
  if restore and record.themeApplied and type(record.window.theme)=="table"then
   if not applyWindowTheme(record,restoredTheme(record),animate)then stopThemeMotion(record)end
  else stopThemeMotion(record)end
  record.themeApplied=nil;record.themeActive=false
 end
 local function checkAutomaticTheme(record)
  if not bridge.alive or record.destroyed or record.window.__AltairRayfieldBridgeOwner~=record or not record.themeOriginal or record.themeOptOut or record.window.unloaded or not record.window.main.Parent then return false end
  if type(record.window.theme)~="table"then stopThemeMotion(record);record.themeApplied=nil;record.themeActive=false;record.themeOptOut=true;return false end
  if not same(record.window.theme,record.themeApplied or record.themeOriginal)then
   stopAutomaticTheme(record,true,true);record.themeOptOut=true;record.window.screenGui:SetAttribute("AltairRayfieldTheme","Custom");return false
  end
  return true
 end
 local function palette(record)
  local config=context.Theme or {};local bar=root:FindFirstChild("SmartBar");local settings=root:FindFirstChild("Settings")
  local function color(object,property,fallback)
   if not object then return fallback end
   local target=object:GetAttribute("AltairTheme_"..property)
   if target~=nil then return target end
   if not root:GetAttribute("AltairThemeEnabled")then return object:GetAttribute("AltairThemeDefault_"..property)or object[property]end
   return object[property]
  end
  local background=color(settings,"BackgroundColor3",color(bar,"BackgroundColor3",rgb(12,13,17)))
  local light=.2126*background.R+.7152*background.G+.0722*background.B>.55
  local ink=light and rgb(22,24,29)or rgb(245,247,250);local shade=light and Color3.new(0,0,0)or Color3.new(1,1,1)
  local accent=config.active and config.color or rgb(216,146,65)
  local back=bar and bar:FindFirstChild("Back");local buttons=back and back:FindFirstChild("Buttons");local scripts=buttons and buttons:FindFirstChild("Scripts");local fill=scripts and scripts:FindFirstChildOfClass("UIGradient")
  if fill then local sequence=color(fill,"Color",fill.Color);accent=sample(sequence,.5)end
  local edge=background:Lerp(shade,light and .2 or .24);local raised=background:Lerp(shade,light and .04 or .08)
  local target=table.clone(record.themeOriginal)
  target.WindowColor=gradient(background:Lerp(light and Color3.new(1,1,1)or Color3.new(0,0,0),.14),background,background:Lerp(shade,.04))
  target.ShadowColor=Color3.new(0,0,0);target.ElementGradient=gradient(raised,raised:Lerp(accent,.035),raised:Lerp(shade,.035));target.ElementStroke=edge;target.ElementStrokeGradient=gradient(edge,edge:Lerp(accent,.12),edge)
  target.TabBackground=gradient(raised:Lerp(shade,.04),raised);target.TabStroke=gradient(edge,edge:Lerp(accent,.08));target.TabColor=ink
  target.SliderBackground=raised;target.SliderBackgroundHover=raised:Lerp(shade,.08);target.SliderProgress=gradient(accent:Lerp(background,.12),accent);target.SliderStroke=ink;target.SliderHandle=ink
  target.ActionColor=ink;target.ContentColor=ink;target.TitlingColor=ink;target.ElementTextHoverColor=ink;target.DropdownHighlight=ink
  target.ElementStrokeHover=edge:Lerp(accent,.35);target.ElementStrokeTransparency=.7;target.ElementStrokeHoverTransparency=.35;target.ElementTransparency=.04
  target.AccentColor=accent;target.AccentStroke=accent:Lerp(shade,.25);target.StatBackground=raised;target.ToggleTrack=ink;target.ToggleKnobOff=ink;target.FieldBackground=ink;target.FieldGlow=ink;target.PlaceholderColor=ink:Lerp(background,.35);target.SurfaceStroke=ink
  target.NeutralButton=raised;target.NeutralButtonHover=raised:Lerp(shade,.08);target.NeutralButtonStroke=edge;target.DarkToggleOverlay=not light
  if config.style=="Roblox"then target.CornerRoundness=UDim.new(0,12);target.ElementCornerRadius=UDim.new(0,8);target.Font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium);target.TitleFont=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold)end
  for key,value in pairs(record.fontOverrides or {})do target[key]=value end
  return target
 end
 function bridge:RefreshThemes()
  if not self.alive then return end
  local enabled=self.themingEnabled and capsules:IsEnabled()
  for _,record in pairs(self.records)do if checkAutomaticTheme(record)then
   if enabled then local target=palette(record);if not record.themeApplied or not same(target,record.themeApplied)then record.themeActive=applyWindowTheme(record,target,true);if not record.themeActive then record.themeOptOut=true end end;record.window.screenGui:SetAttribute("AltairRayfieldTheme",record.themeActive and "Altair"or"Unsupported")
   else stopAutomaticTheme(record,true,true);record.window.screenGui:SetAttribute("AltairRayfieldTheme","Default")end
  end end
 end
 function bridge:SetThemingEnabled(enabled)self.themingEnabled=enabled~=false;self:RefreshThemes()end
 local function wrapAutomaticTheme(record)
  local window=record.window
  if type(window.ChangeTheme)~="function"or type(window.themeProperties)~="table"or not isDefault(window.theme)then window.screenGui:SetAttribute("AltairRayfieldTheme","CustomOrUnsupported");return end
  record.changeTheme=window.ChangeTheme;record.themeOriginal=table.clone(window.theme)
  record.changeThemeWrapper=function(self,...)
   if not bridge.alive or record.destroyed or record.themeOptOut then return record.changeTheme(self,...)end
   local overrides=select(1,...)
   local fontsOnly=type(overrides)=="table"and next(overrides)~=nil
   if fontsOnly then for key,value in pairs(overrides)do
    if(key~="Font"and key~="TitleFont")or typeof(value)~="Font"then fontsOnly=false;break end
   end end
   if fontsOnly then
    if not checkAutomaticTheme(record)then return record.changeTheme(self,...)end
    -- Gen2 asynchronously resolves its brand fonts with a partial ChangeTheme.
    -- Font-only calls (whatever their source) do not choose a new palette.
    stopThemeMotion(record)
    local values=table.pack(record.changeTheme(self,...))
    record.fontOverrides=record.fontOverrides or {}
    for key in pairs(overrides)do
     local value=self.theme[key]
     record.fontOverrides[key]=value;record.themeOriginal[key]=value
     if record.themeApplied then record.themeApplied[key]=value end
    end
    return table.unpack(values,1,values.n)
   end
   -- A developer's explicit choice always wins, including a partial theme.
   local restored=restoredTheme(record);stopThemeMotion(record)
   for key,value in pairs(restored)do self.theme[key]=value end
   record.themeApplied=nil;record.themeActive=false;record.themeOptOut=true;self.screenGui:SetAttribute("AltairRayfieldTheme","Custom")
   return record.changeTheme(self,...)
  end
  window.ChangeTheme=record.changeThemeWrapper
 end
 local function notify(original,self,data,...)
  if bridge.alive and root.Parent and type(data)=="table" and not data.Actions and not data.Callback then
   local ok,result=pcall(context.Notify,data.Title or data.title or "Rayfield",data.Content or data.content or data.Description,data.Image or data.Icon or data.icon,{Duration=data.Duration or data.duration})
   if ok then return result end
  end
  return original(self,data,...)
 end
 function bridge:WrapWindow(window)
  if not self.alive or type(window)~="table" or self.records[window]then return window end
  if type(window.Hide)~="function" or type(window.Show)~="function" or not window.main or not window.screenGui then return window end
  local record={window=window,hide=window.Hide,show=window.Show,rect=window._collapsedRect,notify=window.Notify,generation=0}
  self.records[window]=record
  window.__AltairRayfieldBridgeOwner=record
  wrapAutomaticTheme(record)
  local name=window.showName or (window.title and window.title.Text)or "Rayfield"
  local handle=capsules:RegisterExternal({Title=name,Icon=window.collapsedIcon and window.collapsedIcon.Image or window.showIcon,Restore=function()window:Show()end})
  record.handle=handle
  if record.notify then record.notifyWrapper=function(self,data,...)if record.destroyed then return record.notify(self,data,...)end;return notify(record.notify,self,data,...)end;window.Notify=record.notifyWrapper end
  record.rectWrapper=function(self,...)
   if not record.destroyed and bridge.alive and capsules:IsEnabled() and self.hidden and handle.group.Visible then
    local p,visualSize=handle:Rect();local s=visualSize;local localScale=self.main:FindFirstChildOfClass("UIScale");if localScale then s/=math.max(.01,localScale.Scale)end;local parent=self.main.Parent
    local origin=parent:IsA("GuiObject")and parent.AbsolutePosition or self.screenGui.AbsolutePosition
    local a=self.main.AnchorPoint
    return UDim2.fromOffset(p.X-origin.X+visualSize.X*a.X,p.Y-origin.Y+visualSize.Y*a.Y),UDim2.fromOffset(s.X,s.Y)
   end
   return record.rect(self,...)
  end
  if record.rect then window._collapsedRect=record.rectWrapper end
  local function rememberFace()
   record.face=record.face or {}
   for _,face in ipairs({window.collapsedIcon,window.collapsedTitle and window.collapsedTitle.Parent})do
    if face and record.face[face]==nil then record.face[face]=face.Visible end
   end
  end
  record.setEnabled=function(enabled)
   record.generation+=1;local generation=record.generation
   record.pending=false;rememberFace()
   if window.unloaded or not window.main.Parent then return end
   for face,visible in pairs(record.face)do if face.Parent then face.Visible=not enabled and visible or false end end
   if not window.hidden then handle:Hide();return end
   if not window.hasShownOnce and not window._collapsedShown then handle:Hide();return end
   if enabled then
    handle:Show(true)
    motionService():Create(window.main,TweenInfo.new(.18),{BackgroundTransparency=1}):Play()
    task.delay(.2,function()if bridge.alive and generation==record.generation and window.hidden and not window.unloaded then window.main.Visible=false end end)
   else
    handle:Hide();window.main.Visible=true
    local position,size
    if record.rect then position,size=record.rect(window)end
    local goal={BackgroundTransparency=record.background or 0}
    if position and size then goal.Position=position;goal.Size=size end
    motionService():Create(window.main,TweenInfo.new(.28,Enum.EasingStyle.Quint),goal):Play()
    for _,face in ipairs({window.collapsedIcon,window.collapsedTitle,window.collapsedSubtitle})do
     if face then
      local property=face:IsA("ImageLabel")and "ImageTransparency"or "TextTransparency"
      face[property]=1
      motionService():Create(face,TweenInfo.new(.22),{[property]=face==window.collapsedSubtitle and .5 or 0}):Play()
     end
    end
   end
  end
  record.hideWrapper=function(self,...)
   if record.destroyed then return record.hide(self,...)end
   checkAutomaticTheme(record)
   if not bridge.alive then return record.hide(self,...)end
   if not capsules:IsEnabled()then record.setEnabled(false);return record.hide(self,...)end
   if record.pending then return end
   if self.animating or self.hidden then return record.hide(self,...)end
   record.generation+=1;local generation=record.generation
   record.pending=true;record.background=self.main.BackgroundTransparency
   record.face=record.face or {}
   for _,face in ipairs({self.collapsedIcon,self.collapsedTitle and self.collapsedTitle.Parent})do if face then if record.face[face]==nil then record.face[face]=face.Visible end;face.Visible=false end end
   handle:Show(false)
   -- Let the capsule layout settle before Rayfield measures the morph destination.
   game:GetService("RunService").Heartbeat:Wait()
   record.pending=false
   if not bridge.alive or generation~=record.generation or self.unloaded or not self.main.Parent then handle:Hide();return end
   if self.animating or self.hidden then handle:Hide();return end
   local result=table.pack(pcall(record.hide,self,...))
   if not result[1]then
    handle:Hide();for face,visible in pairs(record.face)do if face.Parent then face.Visible=visible end end
    error(result[2],0)
   end
   motionService():Create(self.main,TweenInfo.new(.28,Enum.EasingStyle.Quint),{BackgroundTransparency=1}):Play()
   task.delay(.37,function()
    if generation~=record.generation or not bridge.alive or self.unloaded or not self.main.Parent then return end
    if self.hidden then
     self.main.Visible=false;handle:Show(true)
     if capsules.docked and capsules.presentationTarget==0 and capsules.PulseDrag then capsules:PulseDrag()end
    else handle:Hide()end
   end)
   return table.unpack(result,2,result.n)
  end
  record.showWrapper=function(self,...)
   if record.destroyed then return record.show(self,...)end
   checkAutomaticTheme(record)
   if bridge.alive and not capsules:IsEnabled()then record.setEnabled(false);return record.show(self,...)end
   if bridge.alive then
    if self.animating then return record.show(self,...)end
    if not self.hidden then return record.show(self,...)end
    record.generation+=1
    self.main.Visible=true;motionService():Create(self.main,TweenInfo.new(.22,Enum.EasingStyle.Quint),{BackgroundTransparency=record.background or 0}):Play();handle:Hide()
   end
   return record.show(self,...)
  end
  window.Hide=record.hideWrapper;window.Show=record.showWrapper
  record.connection=window.screenGui.Destroying:Connect(function()
   record.destroyed=true;stopThemeMotion(record)
   record.restoreToken=nil
   if window.__AltairRayfieldBridgeOwner==record then window.__AltairRayfieldBridgeOwner=nil end
   if window.Hide==record.hideWrapper then window.Hide=record.hide end
   if window.Show==record.showWrapper then window.Show=record.show end
   if window._collapsedRect==record.rectWrapper then window._collapsedRect=record.rect end
   if window.Notify==record.notifyWrapper then window.Notify=record.notify end
   if window.ChangeTheme==record.changeThemeWrapper then window.ChangeTheme=record.changeTheme end
   handle:Destroy();bridge.records[window]=nil
  end)
  record.background=window.main.BackgroundTransparency
  if window.hidden then record.setEnabled(capsules:IsEnabled())end
  self:RefreshThemes()
  return window
 end
 function bridge:WrapLibrary(library)
  if type(library)~="table" or self.libraries[library]then return library end
  if library.main and library.screenGui then return self:WrapWindow(library)end
  if type(library.CreateWindow)~="function" then return library end
  local record={create=library.CreateWindow,notify=library.Notify};self.libraries[library]=record
  record.wrapper=function(self,...)
   local values=table.pack(record.create(self,...));if bridge.alive then bridge:WrapWindow(values[1])end
   return table.unpack(values,1,values.n)
  end
  library.CreateWindow=record.wrapper
  if record.notify then record.notifyWrapper=function(self,data,...)return notify(record.notify,self,data,...)end;library.Notify=record.notifyWrapper end
  return library
 end
 -- One shared compiler hook, with an inactive pass-through after Altair unloads.
 local hook=env.__AltairRayfieldLoader
 if not hook then
  hook={};env.__AltairRayfieldLoader=hook
  local original=loadstring
  local function compile(source,...)
   local fn,err=original(source,...)
   if not fn or type(source)~="string" or not source:find("CreateWindow",1,true)or not source:lower():find("rayfield",1,true)then return fn,err end
   return function(...)
    local values=table.pack(fn(...));local active=hook.active
    if active and active.alive then active:WrapLibrary(values[1])end
    return table.unpack(values,1,values.n)
   end,err
  end
  if type(hookfunction)=="function"then
   local ok,result=pcall(hookfunction,loadstring,compile)
   if ok then original=result;hook.installed=true end
  end
  if not hook.installed then env.loadstring=compile;hook.installed=true end
 end
 hook.active=bridge
 for _,key in ipairs({"Rayfield","RayfieldLibrary","ADS_RayfieldWindow"})do if type(env[key])=="table"then bridge:WrapLibrary(env[key])end end
 -- Existing and obfuscated Gen2 windows can be recognised through their restore control.
 -- Inspect only that control's closures; never scan the entire executor heap.
 local observed=setmetatable({}, {__mode="k"});bridge.discoveryConnections={}
 local function discover(object)
  if not bridge.alive or object.Name~="CollapsedInteract"or not object:IsA("GuiButton")or observed[object]then return end
  local main=object.Parent;if not main or not main:FindFirstChild("CollapsedIcon")then return end
  observed[object]=true
  local inspect=getupvalues or(debug and debug.getupvalues)
  if type(getconnections)~="function"or type(inspect)~="function"then return end
  local function attempt()
   if not bridge.alive or not object.Parent then return end
   local ok,connections=pcall(getconnections,object.InputBegan);if not ok then return end
   for _,connection in ipairs(connections)do
    local got,values=pcall(function()return inspect(connection.Function)end)
    if got and type(values)=="table"then for _,value in pairs(values)do
     if type(value)=="table"and rawget(value,"main")==main and rawget(value,"screenGui")then bridge:WrapWindow(value);return end
    end end
   end
  end
  task.delay(.1,attempt);task.delay(.6,attempt)
 end
 local parents={game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")}
 if type(gethui)=="function"then local ok,parent=pcall(gethui);if ok and parent~=parents[1]then table.insert(parents,parent)end end
 for _,parent in ipairs(parents)do
  table.insert(bridge.discoveryConnections,parent.DescendantAdded:Connect(discover))
  task.defer(function()for _,object in ipairs(parent:GetDescendants())do discover(object)end end)
 end
 bridge.enabledConnection=capsules:ObserveEnabled(function(enabled)
  for _,record in pairs(bridge.records)do record.setEnabled(enabled)end
  bridge:RefreshThemes()
 end)
 local theme=context.Theme
 if theme and type(theme.Apply)=="function"then
  bridge.themeOwner=theme;bridge.themeApply=theme.Apply
  bridge.themeApplyWrapper=function(self,...)
   local values=table.pack(bridge.themeApply(self,...));if bridge.alive then bridge:RefreshThemes()end;return table.unpack(values,1,values.n)
  end
  theme.Apply=bridge.themeApplyWrapper
 end
 local function restoreNativeWindow(record)
  local window=record.window;local token={};record.restoreToken=token
  local delays={.1,.2,.4,.8}
  local function finish()
   if record.restoreToken==token then record.restoreToken=nil end
   if window.__AltairRayfieldBridgeOwner==record then window.__AltairRayfieldBridgeOwner=nil end
  end
  local function attempt(index)
   if record.restoreToken~=token then return end
   if window.__AltairRayfieldBridgeOwner~=record or record.destroyed or window.unloaded
    or not window.main or not window.main.Parent or not window.screenGui.Parent
    or window.Hide~=record.hide or window.Show~=record.show then finish();return end
   if window.animating then
    local delay=delays[index]
    if delay then task.delay(delay,function()attempt(index+1)end)else finish()end
    return
   end
   -- Native Hide owns its in-flight geometry. Wait for it to settle, then use
   -- native Show rather than changing animating, Position or Size ourselves.
   window.main.Visible=true
   if record.background then window.main.BackgroundTransparency=record.background end
   for face,visible in pairs(record.face or {})do if face.Parent then face.Visible=visible end end
   if window.hidden then pcall(record.show,window)end
   finish()
  end
  attempt(1)
 end
 function bridge:Destroy()
  if not self.alive then return end;self.alive=false;for _,connection in ipairs(self.discoveryConnections)do connection:Disconnect()end;if hook.active==self then hook.active=nil end
  if self.enabledConnection then self.enabledConnection:Disconnect()end
  if self.themeOwner and self.themeOwner.Apply==self.themeApplyWrapper then self.themeOwner.Apply=self.themeApply end
  for window,record in pairs(self.records)do
   local ownsWindow=window.__AltairRayfieldBridgeOwner==record
   local restoreVisibility=ownsWindow and window.Hide==record.hideWrapper and window.Show==record.showWrapper
   if ownsWindow and record.themeOriginal and window.ChangeTheme==record.changeThemeWrapper then stopAutomaticTheme(record,true,false)else stopThemeMotion(record)end
   record.generation+=1
   if record.connection then record.connection:Disconnect()end
   if ownsWindow then
    if window.Hide==record.hideWrapper then window.Hide=record.hide end
    if window.Show==record.showWrapper then window.Show=record.show end
    if window._collapsedRect==record.rectWrapper then window._collapsedRect=record.rect end
    if window.Notify==record.notifyWrapper then window.Notify=record.notify end
    if window.ChangeTheme==record.changeThemeWrapper then window.ChangeTheme=record.changeTheme end
    if window.screenGui.Parent then window.screenGui:SetAttribute("AltairRayfieldTheme",nil)end
   end
   record.handle:Destroy()
   if restoreVisibility then restoreNativeWindow(record)
   elseif ownsWindow then window.__AltairRayfieldBridgeOwner=nil end
  end
  for library,record in pairs(self.libraries)do
   if library.CreateWindow==record.wrapper then library.CreateWindow=record.create end
   if library.Notify==record.notifyWrapper then library.Notify=record.notify end
  end
 end
 return bridge
end

local function bindHomeIsolation(root,scopes)
 local native=game:GetService("TweenService");local run=game:GetService("RunService")
 local controller={opened=false,generation=0,records={},connections={},customScopes=scopes~=nil,alive=true}
 local playerGui=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
 local properties={Frame={"BackgroundTransparency"},ScrollingFrame={"BackgroundTransparency","ScrollBarImageTransparency"},TextLabel={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},TextButton={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},TextBox={"BackgroundTransparency","TextTransparency","TextStrokeTransparency"},ImageLabel={"BackgroundTransparency","ImageTransparency"},ImageButton={"BackgroundTransparency","ImageTransparency"},UIStroke={"Transparency"},CanvasGroup={"GroupTransparency"}}
 local function budget(generation,opened)
  if not controller.alive or controller.generation~=generation or controller.opened~=opened then return false end
  if os.clock()-(controller.workAt or 0)>.001 then run.Heartbeat:Wait();controller.workAt=os.clock()end
  return controller.alive and controller.generation==generation and controller.opened==opened
 end
 local function cancel(record)
  for animation in pairs(record.animations)do animation:Cancel()end;table.clear(record.animations);table.clear(record.motion)
 end
 local function tween(record,object,goals,duration)
  if not object.Parent then return end
  local byProperty=record.motion[object]or{};record.motion[object]=byProperty;local changed={}
  for property,value in pairs(goals)do
   local old=byProperty[property];if old then old:Cancel();byProperty[property]=nil end
   if object[property]~=value then changed[property]=value end
  end
  if not next(changed)then return end
  local animation=native:Create(object,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),changed)
  for property in pairs(changed)do byProperty[property]=animation end;record.animations[animation]=true
  animation.Completed:Once(function()
   record.animations[animation]=nil
   for property in pairs(changed)do if byProperty[property]==animation then byProperty[property]=nil end end
  end);animation:Play()
 end
 local function setEnabled(screen,record,value)
  record.writing=true;screen.Enabled=value;record.writing=false
 end
 local function excluded(screen)
  if not screen:IsA("ScreenGui")then return true end
  local name=screen.Name:lower()
  return screen==root or screen:IsAncestorOf(root)or screen:GetAttribute("AltairUIRevision")or name=="robloxgui"or name:find("chat",1,true)~=nil
 end
 local function hideScreen(screen)
  if not controller.alive or not controller.opened then return end
  if excluded(screen)or not screen.Enabled and not controller.records[screen]then return end
  local record=controller.records[screen]
  if record and record.generation==controller.generation and(record.phase=="hiding"or record.phase=="hidden")then return end
  if not record then
   record={enabled=screen.Enabled,visuals={},roots={},rootIndex={},motion=setmetatable({},{__mode="k"}),animations={}};controller.records[screen]=record
   record.enabledConnection=screen:GetPropertyChangedSignal("Enabled"):Connect(function()
    if record.writing then return end;record.enabled=screen.Enabled
    if controller.opened and record.hidden and screen.Enabled then setEnabled(screen,record,false)end
   end)
  end
  cancel(record);record.hidden=false
  local generation=controller.generation;record.generation=generation;record.phase="hiding"
  local viewport=root.AbsoluteSize
  task.spawn(function()
   local function fade(object,visible)
    if not budget(generation,true)then return end
    if object:IsA("GuiObject")then visible=visible and object.Visible end
    if not visible then return end
    local keys=properties[object.ClassName]
    if keys then
     local values=record.visuals[object]
     if not values then values={};for _,key in ipairs(keys)do values[key]=object[key]end;record.visuals[object]=values end
     local goals={};for key in pairs(values)do goals[key]=1 end;tween(record,object,goals,.32)
    end
    if object:IsA("CanvasGroup")then return end
    for _,child in ipairs(object:GetChildren())do fade(child,visible)end
   end
   for _,object in ipairs(screen:GetChildren())do
    if not budget(generation,true)then return end
    if object:IsA("GuiObject")and object.Visible then
     local state=record.rootIndex[object]
     if not state then
      state={object=object,position=object.Position};record.rootIndex[object]=state;record.roots[#record.roots+1]=state
      local center=object.AbsolutePosition-root.AbsolutePosition+object.AbsoluteSize/2
      local relative=Vector2.new(center.X/math.max(1,viewport.X),center.Y/math.max(1,viewport.Y))
      if relative.X>.32 and relative.X<.68 and relative.Y>.32 and relative.Y<.68 then
       local scale=object:FindFirstChildOfClass("UIScale");state.created=not scale or scale:GetAttribute("AltairHomeOwnedScale")==true
       if not scale then scale=Instance.new("UIScale");scale.Name="AltairHomeIsolationScale";scale:SetAttribute("AltairHomeOwnedScale",true);scale.Parent=object end
       state.scale=scale;state.value=scale.Scale;state.hiddenScale=scale.Scale*1.48
      else
       local distances={center.X,viewport.X-center.X,center.Y,viewport.Y-center.Y};local side=1
       for index=2,4 do if distances[index]<distances[side]then side=index end end
       local size=object.AbsoluteSize
       local dx=side==1 and-center.X-size.X/2-24 or side==2 and viewport.X-center.X+size.X/2+24 or 0
       local dy=side==3 and-center.Y-size.Y/2-24 or side==4 and viewport.Y-center.Y+size.Y/2+24 or 0
       local factor=1;local ancestor=object.Parent
       while ancestor and ancestor~=screen do local scale=ancestor:FindFirstChildOfClass("UIScale");if scale then factor*=scale.Scale end;ancestor=ancestor.Parent end
       state.hiddenPosition=state.position+UDim2.fromOffset(dx/math.max(.01,factor),dy/math.max(.01,factor))
      end
     end
     if state.scale and state.scale.Parent then tween(record,state.scale,{Scale=state.hiddenScale},.3)
     elseif state.hiddenPosition then tween(record,object,{Position=state.hiddenPosition},.3)end
     fade(object,true)
    end
   end
   task.delay(.34,function()if controller.alive and controller.opened and controller.generation==generation and screen.Parent then record.hidden=true;record.phase="hidden";setEnabled(screen,record,false)end end)
  end)
 end
 local function restoreCore()
  if not controller.coreState then return end
  local starter=game:GetService("StarterGui")
  for kind,value in pairs(controller.coreState)do pcall(starter.SetCoreGuiEnabled,starter,kind,value)end
  pcall(starter.SetCore,starter,"TopbarEnabled",controller.topbarState);controller.coreState=nil
 end
 local function release(screen,record)
  if record.enabledConnection then record.enabledConnection:Disconnect()end
  for _,state in ipairs(record.roots)do if state.created and state.scale and state.scale.Parent then state.scale:Destroy()end end
  if controller.records[screen]==record then controller.records[screen]=nil end
 end
 function controller:SetOpened(opened)
  if not self.alive then return end
  self.generation+=1;self.opened=opened;self.workAt=os.clock();local generation=self.generation
  if opened then
   if not self.customScopes and not self.coreState then
    local starter=game:GetService("StarterGui");self.coreState={}
    for _,kind in ipairs(Enum.CoreGuiType:GetEnumItems())do if kind~=Enum.CoreGuiType.All then local ok,value=pcall(starter.GetCoreGuiEnabled,starter,kind);if ok then self.coreState[kind]=value end end end
    local ok,value=pcall(starter.GetCore,starter,"TopbarEnabled");self.topbarState=not ok or value~=false
    for kind in pairs(self.coreState)do if kind~=Enum.CoreGuiType.Chat then pcall(starter.SetCoreGuiEnabled,starter,kind,false)end end
   end
   for _,parent in ipairs(scopes)do for _,screen in ipairs(parent:GetChildren())do hideScreen(screen)end end
  else
   restoreCore()
   for screen,record in pairs(self.records)do
    cancel(record);record.hidden=false;record.generation=generation;record.phase="restoring"
    if screen.Parent then setEnabled(screen,record,record.enabled)else release(screen,record)end
   end
   task.spawn(function()
    for screen,record in pairs(self.records)do
     if not budget(generation,false)then return end
     if screen.Parent then
      for object,values in pairs(record.visuals)do if not budget(generation,false)then return end;tween(record,object,values,.24)end
      for _,state in ipairs(record.roots)do
       if not budget(generation,false)then return end
       tween(record,state.object,{Position=state.position},.24)
       if state.scale and state.scale.Parent then tween(record,state.scale,{Scale=state.value},.24)end
      end
     end
    end
    task.delay(.25,function()
     if not controller.alive or controller.opened or controller.generation~=generation then return end
     for screen,record in pairs(controller.records)do release(screen,record)end
    end)
   end)
  end
 end
 if not scopes then scopes={playerGui};if type(gethui)=="function"then local ok,parent=pcall(gethui);if ok and parent~=playerGui then scopes[#scopes+1]=parent end end end
 local observed=setmetatable({},{__mode="k"})
 local function watchScreen(screen)
  if excluded(screen)or observed[screen]then return end
  observed[screen]=screen:GetPropertyChangedSignal("Enabled"):Connect(function()
   if controller.opened and screen.Enabled and not controller.records[screen]then task.defer(hideScreen,screen)end
  end)
 end
 for _,parent in ipairs(scopes)do
  for _,screen in ipairs(parent:GetChildren())do watchScreen(screen)end
  controller.connections[#controller.connections+1]=parent.ChildAdded:Connect(function(screen)watchScreen(screen);if controller.opened then task.defer(hideScreen,screen)end end)
 end
 function controller:Destroy()
  if not self.alive then return end;self.alive=false;self.generation+=1;self.opened=false;restoreCore()
  for _,connection in ipairs(self.connections)do connection:Disconnect()end
  for _,connection in pairs(observed)do connection:Disconnect()end
  for screen,record in pairs(self.records)do
   cancel(record)
   if screen.Parent then
    setEnabled(screen,record,record.enabled)
    for object,values in pairs(record.visuals)do if object.Parent then for property,value in pairs(values)do object[property]=value end end end
    for _,state in ipairs(record.roots)do if state.object.Parent then state.object.Position=state.position end;if state.scale and state.scale.Parent then state.scale.Scale=state.value end end
   end
   release(screen,record)
  end
 end
 return controller
end

local function bindDragContrast(root)
 local line=root.Drag.Drag;local motion=motionService();local controller={elapsed=0,goal=nil}
 local stroke=Instance.new("UIStroke");stroke.Name="AdaptiveContrast";stroke.Color=Color3.fromRGB(14,14,16);stroke.Thickness=.35;stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inner;stroke.Transparency=1;stroke:SetAttribute("AltairContrastOutline",true);stroke.Parent=line
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.IgnoreWater=false
 local function luminance(color)return .2126*color.R+.7152*color.G+.0722*color.B end
 function controller:Update(value)
  self.elapsed=0;value=math.clamp(value,0,1);self.luminance=value
  local strength=math.clamp((value-.58)/.32,0,1);local target=1-strength*.86;local outlineColor=Color3.new(1,1,1):Lerp(Color3.fromRGB(14,15,18),strength)
  if self.goal and math.abs(self.goal-target)<.025 then return end;self.goal=target
  if self.animation then self.animation:Cancel()end
  self.animation=motion:Create(stroke,TweenInfo.new(.24,Enum.EasingStyle.Quint),{Transparency=target,Thickness=.35+strength*.15,Color=outlineColor});self.animation:Play()
 end
 function controller:Sample()
  local camera=workspace.CurrentCamera;if not camera then return .3 end
  local player=game:GetService("Players").LocalPlayer;local exclude={camera};if player and player.Character then exclude[#exclude+1]=player.Character end;params.FilterDescendantsInstances=exclude
  local lighting=game:GetService("Lighting");local center=line.AbsolutePosition+line.AbsoluteSize/2
  local angle=(line.AbsoluteSize.Y>line.AbsoluteSize.X and math.pi/2 or 0)+math.rad(line.Rotation)
  local axis=Vector2.new(math.cos(angle),math.sin(angle))*18
  local ambient=(luminance(lighting.Ambient)+luminance(lighting.OutdoorAmbient))*.5
  local day=math.clamp((math.cos((lighting.ClockTime-12)*math.pi/12)+.2)/1.2,0,1)
  local total=0;local peak=0
  for _,offset in ipairs({-axis,Vector2.zero,axis})do
   local point=center+offset;local ray=camera:ViewportPointToRay(point.X,point.Y)
   local result=workspace:Raycast(ray.Origin,ray.Direction*2048,params);local value=.15+.7*day
   if result then
    local hit=result.Instance;local color
    if hit:IsA("BasePart")then color=hit.Color elseif hit:IsA("Terrain")then color=result.Material==Enum.Material.Water and workspace.Terrain.WaterColor or workspace.Terrain:GetMaterialColor(result.Material)end
    if color then value=luminance(color)*math.clamp(.35+lighting.Brightness*.18+ambient*.5,.35,1.4)end
   end
   value=math.clamp(value,0,1);total+=value;peak=math.max(peak,value)
  end
  -- Preserve contrast over bright patches on mixed backgrounds.
  return math.max(total/3,peak*.9)
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
    params:Destroy()
    return if ok then bounds else Vector2.new(size * 0.6, size)
end

-- Digit advances are the same for every odometer of a given font+size, but
-- GetTextBoundsAsync yields, so measure the ten digits once per (font, size) and
-- cache. Later odometers reuse the result and never touch TextService again.
local metricsCache = {}
local metricsCacheCount = 0
local function metricsKey(font, size)
    -- Style is part of the key: italic and normal measure differently
    return tostring(font.Family)
        .. "|"
        .. tostring(font.Weight)
        .. "|"
        .. tostring(font.Style)
        .. "|"
        .. tostring(size)
end
local function digitMetrics(font, size, valid)
    local key = metricsKey(font, size)
    local cached = metricsCache[key]
    if cached then
        return cached
    end

    local advance, maxWidth = {}, 0
    for d = 0, 9 do
        if valid and not valid() then return nil end
        local w = math.ceil(measure(font, size, tostring(d)).X) + 2
        advance[d] = w
        if w > maxWidth then
            maxWidth = w
        end
    end
    cached = { advance = advance, maxWidth = maxWidth }
    if metricsCacheCount >= 64 then table.clear(metricsCache);metricsCacheCount = 0 end
    metricsCache[key] = cached
    metricsCacheCount += 1
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
        alive = true,
        metricGeneration = 0,
        metricConnections = {},
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
    local measuredFont = window.theme.Font
    self.metricConnections[#self.metricConnections + 1] = container.Destroying:Connect(function()
        self.alive = false;self.metricGeneration += 1
        for _,connection in ipairs(self.metricConnections) do connection:Disconnect() end
        table.clear(self.metricConnections)
        for _,slot in pairs(self.slots) do
            if slot.reel then
                if slot.reel.stripTween then slot.reel.stripTween:Cancel();slot.reel.stripTween = nil end
                if slot.reel.sizeTween then slot.reel.sizeTween:Cancel();slot.reel.sizeTween = nil end
            end
        end
    end)

    local metrics = digitMetrics(measuredFont, self.textSize, function()return self.alive end)
    if not self.alive or not metrics then return self end
    self.advance = metrics.advance
    self.maxWidth = metrics.maxWidth
    self.metricsKey = metricsKey(measuredFont, self.textSize)

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

-- The owning window can replace the rendered glyph face after construction.
-- Re-measure only on that event, retaining the vertical reel's exact phase.
function odometer:_applyMetrics(metrics)
    local oldAdvance = self.advance
    self.advance, self.maxWidth = metrics.advance, metrics.maxWidth
    for _,slot in pairs(self.slots) do
        local reel = slot.reel
        if reel and reel.cell.Parent then
            local rolling = reel.stripTween ~= nil
            local phase = 1
            if rolling and reel.startIndex and reel.targetIndex and reel.startIndex ~= reel.targetIndex then
                phase = math.clamp((-reel.strip.Position.Y.Offset / self.height - reel.startIndex) / (reel.targetIndex - reel.startIndex), 0, 1)
            elseif rolling and oldAdvance[reel.fromDigit or reel.target] ~= oldAdvance[reel.target] then
                local from = oldAdvance[reel.fromDigit or reel.target]
                phase = math.clamp((reel.cell.Size.X.Offset - from) / (oldAdvance[reel.target] - from), 0, 1)
            end
            if reel.sizeTween then reel.sizeTween:Cancel();reel.sizeTween = nil end
            local from = self.advance[reel.fromDigit or reel.target]
            local target = self.advance[reel.target]
            reel.cell.Size = UDim2.fromOffset(from + (target - from) * phase, self.height)
            reel.strip.Size = UDim2.fromOffset(self.maxWidth, self.height)
            for _,glyph in ipairs(reel.strip:GetChildren()) do
                if glyph:IsA("TextLabel") then glyph.Size = UDim2.fromOffset(self.maxWidth, self.height) end
            end
            if rolling then
                local remaining = math.max(.01, self.duration - (os.clock() - (reel.startedAt or os.clock())))
                reel.sizeTween = variables.tweenService:Create(reel.cell, TweenInfo.new(remaining, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.fromOffset(target, self.height)})
                reel.sizeTween:Play()
            end
        end
    end
end

function odometer:_watchFont(label)
    if self.metricProbe then return end
    self.metricProbe = label
    local function changed()
        if not self.alive or not label.Parent then return end
        local key = metricsKey(label.FontFace, label.TextSize)
        if key == self.metricsKey and not self.metricPending then return end
        self.metricGeneration += 1
        self.metricFace, self.metricSize = label.FontFace, label.TextSize
        if self.metricPending then return end
        self.metricPending = true
        task.defer(function()
            while self.alive and label.Parent do
                local generation, font, size = self.metricGeneration, self.metricFace, self.metricSize
                local metrics = digitMetrics(font, size, function()return self.alive end)
                if not self.alive or not label.Parent then break end
                if generation == self.metricGeneration then
                    self.metricsKey = metricsKey(font, size)
                    self:_applyMetrics(metrics)
                    break
                end
            end
            self.metricPending = false
        end)
    end
    self.metricConnections[#self.metricConnections + 1] = label:GetPropertyChangedSignal("FontFace"):Connect(changed)
    changed()
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
        local glyph = self.window:Create("TextLabel", {
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
        self:_watchFont(glyph)
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
    reel.fromDigit, reel.startIndex, reel.targetIndex, reel.startedAt = a, startIndex, targetIndex, os.clock()

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
    if not self.alive then return end
    text = tostring(text)

    -- skip the reconcile when unchanged; snap() runs every drag frame
    if text == self._lastText then
        if not animate then
            for _,slot in pairs(self.slots) do
                local reel = slot.reel
                if reel and (reel.stripTween or reel.sizeTween) then self:_reelSnap(reel, reel.target) end
            end
        end
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
    if not self.alive then return end
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
    NumberSequenceKeypoint.new(0, 0.98),
    NumberSequenceKeypoint.new(1, 0.86),
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

-- Both card layouts share the same material and accent edge. Keep these
-- defaults in one place without changing their layout-specific descendants.
function Statistic:_accentGradient(parent, color)
    return self.window:Create("UIGradient", {
        Rotation = 2,
        Offset = Vector2.new(0, 0.5),
        Color = color,
        Transparency = accentTransparency,
        Parent = parent,
    })
end

function Statistic:_buildShell(properties)
    local window = self.window
    properties.Name = self.name
    properties.BorderSizePixel = 0
    properties.ZIndex = 5
    properties.BackgroundTransparency = 1
    properties.Parent = self.tab.tabPage
    self.main = window:Create("Frame", properties,
        { BackgroundColor3 = "StatBackground", BackgroundTransparency = "ElementTransparency" })
    self.main:SetAttribute("AltairDesignRole", "inset")
    window:Create("UICorner", {
        Parent = self.main,
    }, { CornerRadius = "ElementCornerRadius" })
    self.stroke = window:Create("UIStroke", {
        Transparency = 1,
        Color = Design.Edge,
        Thickness = 0.6,
        Parent = self.main,
    }, { Transparency = "ElementStrokeTransparency" })
    self.strokeGradient = self:_accentGradient(self.stroke, accents.neutral.stroke)
end

-- full 90px card: title, value bottom-left, % change bottom-right
function Statistic:_buildFull()
    local window = self.window
    self:_buildShell({ Size = UDim2.new(1, -20, 0, 90) })
    self.signal = window:Create("Frame", {
        Name = "DirectionSignal", Position = UDim2.fromOffset(0, 17),
        Size = UDim2.fromOffset(3, 56), BorderSizePixel = 0,
        BackgroundColor3 = glowColor(accents.neutral), BackgroundTransparency = 1,
        ZIndex = 6, Parent = self.main,
    })
    self.signal:SetAttribute("AltairDesignRole", "accent")
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.signal })

    self.titleContainer = window:Create("Frame", {
        Size = UDim2.new(1, -40, 0, 32),
        Position = UDim2.fromOffset(18, 12),
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
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        LayoutOrder = 1,
        ZIndex = 10,

        TextTransparency = 1, -- In = 0

        Parent = self.titleContainer,
    }, { TextColor3 = "ContentColor", FontFace = "TitleFont" })

    self.mainGradient = self:_accentGradient(self.gradientContainer, accents.neutral.fill)

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
        Position = UDim2.new(0, 18, 1, -16),
        Size = UDim2.fromOffset(200, 24),
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
        textSize = 24,
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

    self:_buildShell({
        Size = if inRow then UDim2.fromOffset(0, compactHeight) else UDim2.new(1, -20, 0, compactHeight),
        AutomaticSize = if inRow then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
        ClipsDescendants = true,
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

    self.mainGradient = self:_accentGradient(self.card, accents.neutral.fill)

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
    if self.signal then variables.tweenService:Create(self.signal, accentTweenInfo, { BackgroundColor3 = glowColor(accent) }):Play() end
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
        w:_reveal(self.signal, { BackgroundTransparency = 0.12 }, animate)
        w:_reveal(self.gradientContainer, { BackgroundTransparency = 0 }, animate)
        w:_reveal(self.glow, { Transparency = 0.82 }, animate)
        self.valueOdo:reveal(0, animate)
        self.changeOdo:reveal(0, animate)
    else
        w:_hideCommon(self, animate)
        w:_reveal(self.signal, { BackgroundTransparency = 1 }, animate)
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
 local font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local window={theme={Font=font,TitleFont=Font.new(font.Family,Enum.FontWeight.SemiBold),ContentColor=Design.Ink,StatBackground=Design.Raised,ElementTransparency=.12,ElementStrokeTransparency=.9,ElementCornerRadius=UDim.new(0,12)}}
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
  self:_reveal(card.main,{BackgroundTransparency=.12},animate);self:_reveal(card.stroke,{Transparency=.9},animate);self:_reveal(card.title,{TextTransparency=0},animate)
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

local function parseAlphaPercent(text)
    if type(text) ~= "string" then return nil end
    local value = text:match("^%s*(.-)%s*$")
    value = value:gsub("%%%s*$", ""):match("^%s*(.-)%s*$")
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) == math.huge then return nil end
    return clamp01(number / 100)
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
function ColorPicker:_buildAxis(x, width, color, gradientProperties)
    local window = self.window
    local bar = window:Create("Frame", {
        Position = UDim2.fromOffset(x, contentY),
        Size = UDim2.fromOffset(width, mapSize.Y),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = 2,
        BackgroundTransparency = 1,
        Parent = self.main,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })
    gradientProperties.Parent = bar
    local gradient = window:Create("UIGradient", gradientProperties)
    local handle = window:Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(width + 6, 6),
        BackgroundColor3 = Color3.fromRGB(243, 246, 252),
        BorderSizePixel = 0,
        ZIndex = 4,
        BackgroundTransparency = 1,
        Parent = bar,
    })
    window:Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = handle })
    local stroke = window:Create("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 0.6,
        Transparency = 1,
        Parent = handle,
    })
    -- Both thin axes retain the same padded mouse/touch target.
    local interact = window:Create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 16, 1, 8),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Text = "",
        TextTransparency = 1,
        AutoButtonColor = false,
        ZIndex = 6,
        Parent = bar,
    })
    return bar, handle, stroke, interact, gradient
end

function ColorPicker:_buildTextField(size, value, placeholder, padding)
    local window = self.window
    local box = window:Create("Frame", {
        Position = UDim2.new(0, rightX, 0, contentY + 90),
        Size = size,
        BackgroundColor3 = Design.Well,
        BorderSizePixel = 0,
        ZIndex = 2,
        BackgroundTransparency = 1,
        Parent = self.main,
    })
    box:SetAttribute("AltairDesignRole", "control")
    window:Create("UICorner", { CornerRadius = UDim.new(0, 9), Parent = box })
    local stroke = window:Create("UIStroke", {
        Color = Design.Edge,
        Thickness = 0.6,
        Transparency = 1,
        Parent = box,
    })
    local input = window:Create("TextBox", {
        Text = value,
        PlaceholderText = placeholder,
        Size = UDim2.new(1, -padding, 1, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
        ClearTextOnFocus = false,
        ZIndex = 3,
        TextTransparency = 1,
        Parent = box,
    }, { TextColor3 = "ContentColor", FontFace = "Font", PlaceholderColor3 = "PlaceholderColor" })
    return box, stroke, input
end

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

    -- Hue and alpha retain their own gradients, state fields and hit targets.
    self.hueBar, self.hueHandle, self.hueHandleStroke, self.hueInteract = self:_buildAxis(
        hueX, hueWidth, Color3.fromRGB(255, 255, 255), { Color = hueSequence, Rotation = 90 })
    self.alphaBar, self.alphaHandle, self.alphaHandleStroke, self.alphaInteract, self.alphaGradient = self:_buildAxis(
        alphaX, alphaWidth, self.value, {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
            }),
        })

    self.hexBox, self.hexBoxStroke, self.hexInput = self:_buildTextField(
        UDim2.new(1, -(rightX + 20), 0, 30), "#" .. self.value:ToHex():upper(), locale.t("Smart Input"), 14)
    self.alphaBox, self.alphaBoxStroke, self.alphaInput = self:_buildTextField(
        UDim2.fromOffset(alphaFieldWidth, 30), tostring(math.round(self.alpha * 100)) .. "%", "100%", 10)

    self.window:ConnectFor(self, self.mapInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("sat", input.UserInputType == Enum.UserInputType.MouseButton1,input)
        end
    end)

    self.window:ConnectFor(self, self.hueInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("hue", input.UserInputType == Enum.UserInputType.MouseButton1,input)
        end
    end)

    self.window:ConnectFor(self, self.alphaInteract.InputBegan, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            self:_beginDrag("alpha", input.UserInputType == Enum.UserInputType.MouseButton1,input)
        end
    end)

    self.window:ConnectFor(self, variables.userInputService.InputEnded, function(input)
        if
            ((self._dragIsMouse and input.UserInputType == Enum.UserInputType.MouseButton1)
             or(not self._dragIsMouse and input.UserInputType == Enum.UserInputType.Touch and(self._touchInput==nil or self._touchInput==input)))
            and self._drag
        then
            self:_endDrag()
        end
    end)

    -- commit the field on enter/click-away, parsing whatever format they typed. anything
    -- unrecognised just snaps back to the current colour.
    self.window:ConnectFor(self, self.hexInput.Focused, function() self:_beginFieldEdit("hex") end)
    self.window:ConnectFor(self, self.hexInput.FocusLost, function() self:_commitField("hex") end)

    -- Keep the sign and reject malformed input instead of stripping it into a
    -- different positive value. A completed edit belongs to one open/close cycle.
    self.window:ConnectFor(self, self.alphaInput.Focused, function() self:_beginFieldEdit("alpha") end)
    self.window:ConnectFor(self, self.alphaInput.FocusLost, function() self:_commitField("alpha") end)
end

function ColorPicker:_restoreFieldText(kind)
    if kind == "alpha" then self.alphaInput.Text = tostring(math.round(self.alpha * 100)) .. "%"
    else self.hexInput.Text = "#" .. self.value:ToHex():upper() end
end

function ColorPicker:_beginFieldEdit(kind)
    local field = kind == "alpha" and self.alphaInput or self.hexInput
    if not self._isOpen or not self.window:_interactive() then
        self:_restoreFieldText(kind)
        if field:IsFocused() then field:ReleaseFocus() end
        return
    end
    self._fieldEdits = self._fieldEdits or {}
    self._fieldEdits[kind] = self._pickerGeneration or 0
end

function ColorPicker:_commitField(kind, closing)
    local field = kind == "alpha" and self.alphaInput or self.hexInput
    if not closing and field:IsFocused() then return false end -- an older queued loss must not commit a new edit
    local generation = self._fieldEdits and self._fieldEdits[kind]
    if self._fieldEdits then self._fieldEdits[kind] = nil end
    if generation == nil or not self.window:_interactive()
        or (generation ~= self._pickerGeneration and generation ~= self._closingFocusGeneration) then
        self:_restoreFieldText(kind)
        return false
    end
    if kind == "alpha" then
        local alpha = parseAlphaPercent(self.alphaInput.Text)
        if alpha ~= nil then self:SetAlpha(alpha); return true end
    else
        local color = parseColor(self.hexInput.Text)
        if color then self:Set(color); return true end
    end
    self:_restoreFieldText(kind)
    return false
end

-- start following the mouse for the given region ("sat" or "hue"). Mirrors the slider: one
-- RenderStepped loop that self-terminates if the window unloads mid-drag. For a mouse drag
-- it also bails the moment the button is up, so a dropped InputEnded cant leave it running.
function ColorPicker:_beginDrag(region, isMouse, sourceInput)
    -- the interacts stay visible through the close fade, so a click landing in that window
    -- would drag a picker thats already shut
    if not self._isOpen or not self.window:_interactive() then
        return
    end
    self._drag = region
    self._dragIsMouse = isMouse
    self._touchInput=not isMouse and sourceInput or nil
    self:_setHeld(region)
    self:_pump()

    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    self._dragConnection = variables.runService.RenderStepped:Connect(function()
        local mouseReleased = self._dragIsMouse
            and not variables.userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        local inactive=not self.window:_interactive()
        if self.window.unloaded or not self._drag or mouseReleased or inactive then
            if self._drag and(mouseReleased or inactive)then
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
    local wasDragging=self._drag~=nil
    self._drag = nil
    self._touchInput=nil
    self:_setHeld(nil)
    if self._dragConnection then
        self._dragConnection:Disconnect()
        self._dragConnection = nil
    end

    if wasDragging then self.window:_siaUsed(self, "set");self.window:_persist(self)end
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
    local mouse = self._touchInput and Vector2.new(self._touchInput.Position.X,self._touchInput.Position.Y)or variables.userInputService:GetMouseLocation()
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
    if self._isOpen or not self.window:_interactive()then
        return
    end
    self._pickerGeneration = (self._pickerGeneration or 0) + 1
    self._closingFocusGeneration = nil
    self._isOpen = true
    self:_setControlsVisible(true) -- back into input before they fade in
    if self.hexInput:IsFocused() then self:_beginFieldEdit("hex") end
    if self.alphaInput:IsFocused() then self:_beginFieldEdit("alpha") end

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
    self._closingFocusGeneration = self._pickerGeneration or 0
    self._pickerGeneration = (self._pickerGeneration or 0) + 1
    local generation = self._pickerGeneration
    self._isOpen = false
    self:_setControlsInteractive(false) -- stop new input without cutting off the visual fade
    if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end

    if self._outsideClickConn then
        self.window:Disconnect(self._outsideClickConn)
        self._outsideClickConn = nil
    end

    -- a drag in progress shouldnt keep running once the picker is gone
    if self._drag then
        self:_endDrag()
    end
    if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end
    if self._fieldEdits and self._fieldEdits.hex == self._closingFocusGeneration then
        self:_commitField("hex", true)
        if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end
    end
    if self.hexInput:IsFocused() then self.hexInput:ReleaseFocus() end
    if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end
    if self._fieldEdits and self._fieldEdits.alpha == self._closingFocusGeneration then
        self:_commitField("alpha", true)
        if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end
    end
    if self.alphaInput:IsFocused() then self.alphaInput:ReleaseFocus() end
    if self._pickerGeneration ~= generation or self._isOpen or self.window.unloaded then return end
    self._closingFocusGeneration = nil

    self:_applyPickerVisibility(false, true)
    self:_renderInvisible(true)
    variables.tweenService
        :Create(self.preview, openInfo, { Position = previewClosedPos, Size = previewClosedSize })
        :Play()
    variables.tweenService:Create(self.main, openInfo, { Size = UDim2.new(1, -20, 0, headerHeight) }):Play()

    -- once the controls have faded, drop them out of input so a transparent field below the
    -- collapsed header cant grab the cursor
    task.delay(fadeInfo.Time, function()
        if not self._isOpen and self._pickerGeneration == generation and not self.window.unloaded and self.main.Parent then
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
        [self.hexBox] = { BackgroundTransparency = if open then 0.1 else 1 },
        [self.hexBoxStroke] = { Transparency = if open then 0.85 else 1 },
        [self.hexInput] = { TextTransparency = if open then 0.4 else 1 },
        [self.alphaBox] = { BackgroundTransparency = if open then 0.1 else 1 },
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
function ColorPicker:_setControlsInteractive(interactive)
    local generation = self._pickerGeneration
    for _, target in { self.mapInteract, self.hueInteract, self.alphaInteract, self.hexInput, self.alphaInput } do
        for _, property in { "Active", "Interactable", "Selectable" } do
            if self._pickerGeneration ~= generation then return end
            target[property] = interactive
        end
    end
    if self._pickerGeneration ~= generation then return end
    self.hexInput.TextEditable = interactive
    if self._pickerGeneration ~= generation then return end
    self.alphaInput.TextEditable = interactive
end

function ColorPicker:_setControlsVisible(visible)
    local generation = self._pickerGeneration
    self:_setControlsInteractive(visible and self._isOpen)
    for _, frame in { self.map, self.hueBar, self.alphaBar, self.hexBox, self.alphaBox } do
        if self._pickerGeneration ~= generation then return end
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
local function stopContentSlide(object)
 local animation=contentSlides[object]
 if animation then contentSlides[object]=nil;animation:Cancel()end
end
local function slideContent(object,rest,direction,distance)
 stopContentSlide(object)
 local root=object:FindFirstAncestorOfClass("ScreenGui")
 if root and root:GetAttribute("AltairReduceMotion")==true then object.Position=rest;return end
 local progress=Instance.new("NumberValue");local native=game:GetService("TweenService")
 object.Position=rest+UDim2.fromOffset(direction*distance,0)
 local connection=progress.Changed:Connect(function(value)
  local bounded=math.min(1,value)+math.max(0,value-1)*.18
  if object.Parent then object.Position=rest+UDim2.fromOffset(direction*distance*(1-bounded),0)end
 end)
 local animation=native:Create(progress,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Value=1});contentSlides[object]=animation
 local destroyed,reduced
 animation.Completed:Once(function(state)
  connection:Disconnect();if destroyed then destroyed:Disconnect()end;if reduced then reduced:Disconnect()end;progress:Destroy()
  if contentSlides[object]==animation then contentSlides[object]=nil;if state==Enum.PlaybackState.Completed and object.Parent then object.Position=rest end end
 end)
 destroyed=object.Destroying:Connect(function()if contentSlides[object]==animation then stopContentSlide(object)end end)
 if root then reduced=root:GetAttributeChangedSignal("AltairReduceMotion"):Connect(function()
  if root:GetAttribute("AltairReduceMotion")==true and contentSlides[object]==animation then stopContentSlide(object);if object.Parent then object.Position=rest end end
 end)end
 animation:Play()
end
local function slideHeading(panel,direction)
 for _,name in ipairs({"Icon","Title","Subtitle","HeaderIcon","ContentTitle","ContentSubtitle"})do
  local object=panel:FindFirstChild(name)
  if object and object:IsA("GuiObject")then
   local rest=object:GetAttribute("AltairHeadingRest")or object.Position;object:SetAttribute("AltairHeadingRest",rest);slideContent(object,rest,direction,18)
  end
 end
end

local function controlMotionTime(object,duration)
 local screen=object:IsA("ScreenGui")and object or object:FindFirstAncestorOfClass("ScreenGui")
 return screen and screen:GetAttribute("AltairReduceMotion")==true and math.min(duration,.08)or duration
end
local resetAnimations=setmetatable({}, {__mode="k"})
local resetRestAngles=setmetatable({}, {__mode="k"})
local function bounceReset(icon)
 local old=resetAnimations[icon];resetAnimations[icon]=nil;if old then old:Cancel()end
 local rest=resetRestAngles[icon];if rest==nil then rest=icon.Rotation;resetRestAngles[icon]=rest end
 local reduced=controlMotionTime(icon,.7)<.7
 local tween=game:GetService("TweenService"):Create(icon,TweenInfo.new(reduced and 0 or .7,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Rotation=reduced and rest or rest-360})
 resetAnimations[icon]=tween
 tween.Completed:Once(function()
  if resetAnimations[icon]~=tween then return end
  resetAnimations[icon]=nil;if icon.Parent then icon.Rotation=rest end
 end)
 tween:Play();return tween
end

local buildRuler
local function buildColorPicker(template,parent,setting,changed,commit,resetTheme)
 local window=rayfieldWindow(parent);local connections={};local root=parent:FindFirstAncestorOfClass("ScreenGui")
 window.screenGui=root;window.hasShownOnce=true
 window.theme.ElementStroke=Design.Edge;window.theme.ElementStrokeHover=Design.Edge:Lerp(Design.Ink,.2);window.theme.ElementStrokeHoverTransparency=.78;window.theme.ElementTextHoverColor=Design.Ink
 local create=window.Create
 function window:Create(class,properties,themes)local o=create(self,class,properties,themes);if class=="ImageLabel"and properties.Image=="__AltairPalette"then applyIcon(o,"palette")end;return o end
 function window:Connect(signal,fn)local c=signal:Connect(fn);connections[#connections+1]=c;return c end
 function window:ConnectFor(_,signal,fn)return self:Connect(signal,fn)end
 function window:Disconnect(c)if c then c:Disconnect()end end
 local pages=parent.Parent and parent.Parent:FindFirstChildOfClass("UIPageLayout")
 function window:_interactive()
  if self.unloaded or not parent.Parent or root.Settings:GetAttribute("AltairClosing")or(pages and pages.CurrentPage and pages.CurrentPage~=parent)then return false end
  local object=parent;while object do
   if object:IsA("GuiObject")and(not object.Visible or object:IsA("CanvasGroup")and object.GroupTransparency>.999)then return false end
   if object:IsA("ScreenGui")then return object.Enabled end;object=object.Parent
  end
  return false
 end
 function window:_registerControl()end;function window:_siaUsed()end
 function window:_persist()commit()end
 function window:_runGuarded(_,callback,...)callback(...)end
 function window:StyleElementBody(main)
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=main
  main.BackgroundColor3=Design.Raised;main:SetAttribute("AltairSurface",true);main:SetAttribute("AltairDesignRole","inset")
  local gradient=Instance.new("UIGradient");gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(233,233,236));gradient.Rotation=90;gradient.Parent=main
  local stroke=Instance.new("UIStroke");stroke.Color=self.theme.ElementStroke;stroke.Thickness=.6;stroke.Transparency=.9;stroke.Parent=main;return stroke
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
 local function syncVisibility()
  local painted=true;local object=parent
  while object do
   if object:IsA("GuiObject")and(not object.Visible or object:IsA("CanvasGroup")and object.GroupTransparency>.999)then painted=false;break end
   if object:IsA("ScreenGui")then painted=object.Enabled;break end;object=object.Parent
  end
  picker:_setShown(window:_interactive(),painted)
 end
 local ancestor=parent
 while ancestor do
  if ancestor:IsA("GuiObject")then window:Connect(ancestor:GetPropertyChangedSignal("Visible"),syncVisibility)
  elseif ancestor:IsA("ScreenGui")then window:Connect(ancestor:GetPropertyChangedSignal("Enabled"),syncVisibility)end
  ancestor=ancestor.Parent
 end
 if pages then window:Connect(pages:GetPropertyChangedSignal("CurrentPage"),syncVisibility)end
 window:Connect(root.Settings:GetAttributeChangedSignal("AltairClosing"),syncVisibility)
 window:Connect(game:GetService("UserInputService").WindowFocusReleased,function()if picker._drag then picker:_endDrag()end end)
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

-- Signal controls share one input/physics model; only active motion owns a render loop.
buildRuler=function(parent,options)
 options=options or {}
 local input=game:GetService("UserInputService")
 local run=game:GetService("RunService")
 local native=game:GetService("TweenService")
 local actions=game:GetService("ContextActionService")
 local controller={value=0,alive=true,dragging=false,hovered=false,suspended=false,HasMoved=false,InputStage="idle"}
 local connections={};local renderConnection;local valueTween;local zoomTween
 local scale=options.Scale or 600/908
 local low,high=0,100;local step,tickStep,majorEvery=1,1,5
 local precisionZoom=options.PrecisionZoom or 5
 local poolLimit=math.clamp(math.floor(options.PoolLimit or 128),8,128)
 local amber=options.Color or Color3.fromRGB(240,158,30)
 local future=options.FutureColor or Color3.fromRGB(76,52,17)
 local white=Color3.fromRGB(243,246,252)
 local markerColor=options.MarkerColor or Color3.fromRGB(180,126,42)
 local altairSkin=options.Skin=="Altair"
 local trackSkin=options.Skin=="Track"
 local paletteTransition
 local axis=options.Orientation=="Vertical"and "Vertical"or "Horizontal"
 local state={position=Instance.new("NumberValue"),zoom=Instance.new("NumberValue")}
 state.zoom.Value=1
 local root=Instance.new("Frame");root.Name=options.Name or "Ruler";root.Visible=false;root.BackgroundTransparency=1;root.BorderSizePixel=0
 root.Position=options.Position or UDim2.new();root.Size=options.Size or UDim2.new(1,0,0,104*scale);root.ZIndex=options.ZIndex or parent.ZIndex+1
 root:SetAttribute("AltairRuler",true);root:SetAttribute("AltairThemeIgnore",true);root.Parent=parent
 root:SetAttribute("AltairControlDesign",trackSkin and "Track"or "Signal")
 local wheelAction="AltairRulerWheel-"..game:GetService("HttpService"):GenerateGUID(false)
 local wheelBound=false
 local viewport=Instance.new("Frame");viewport.Name="TapeViewport";viewport.BackgroundTransparency=1;viewport.BorderSizePixel=0;viewport.ClipsDescendants=true;viewport.Size=UDim2.fromScale(1,1);viewport.ZIndex=root.ZIndex;viewport.Parent=root
 local marker=Instance.new("ImageLabel");marker.Name="Selection";marker.BackgroundTransparency=1;marker.ImageColor3=markerColor;marker.ZIndex=root.ZIndex+2;marker.Size=UDim2.fromOffset(40*scale,40*scale);marker.AnchorPoint=Vector2.new(.5,.5);applyIcon(marker,"chevron-up");marker.Parent=root
 local trackVisual,trackHover,trackFeedbackActive=nil,0,false
 if trackSkin then
  viewport.Visible=false;marker.Visible=false
  root:SetAttribute("AltairRulerSkin","Track")
  local function shape(name,owner,color,z)
   local object=Instance.new("Frame");object.Name=name;object.BackgroundColor3=color;object.BorderSizePixel=0;object.ZIndex=z;object.Parent=owner
   local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(1,0);rounding.Parent=object
   return object
  end
  local rail=shape("TrackRail",root,future,root.ZIndex)
  rail.AnchorPoint=Vector2.new(.5,.5);rail.BackgroundTransparency=.14
  rail:SetAttribute("AltairDesignRole","inset")
  local rim=Instance.new("UIStroke");rim.Name="RailRim";rim.Thickness=.6;rim.Transparency=.88;rim.Color=amber;rim.Parent=rail
  local fill=shape("TrackFill",rail,Color3.new(1,1,1),root.ZIndex+1);fill.ClipsDescendants=true
  local gradient=Instance.new("UIGradient");gradient.Name="TrackGradient";gradient.Parent=fill
  local halo=shape("TrackHalo",root,amber,root.ZIndex+1);halo.AnchorPoint=Vector2.new(.5,.5);halo.BackgroundTransparency=1
  local handle=shape("TrackHandle",root,amber,root.ZIndex+2);handle.AnchorPoint=Vector2.new(.5,.5)
  local edge=Instance.new("UIStroke");edge.Name="HandleRim";edge.Thickness=.6;edge.Transparency=.5;edge.Color=white;edge.Parent=handle
  trackVisual={Rail=rail,Fill=fill,Gradient=gradient,Handle=handle,Halo=halo,Rim=rim,HandleRim=edge}
  controller.Track=trackVisual
 end
 local focus,signalBand,precisionBadge
 if not trackSkin and axis=="Horizontal"then
  signalBand=Instance.new("Frame");signalBand.Name="SignalBand";signalBand.AnchorPoint=Vector2.new(.5,.5);signalBand.BackgroundColor3=Design.Raised;signalBand.BackgroundTransparency=1;signalBand.BorderSizePixel=0;signalBand.ZIndex=root.ZIndex-1;signalBand.Parent=root
  signalBand:SetAttribute("AltairDesignRole","inset")
  local round=Instance.new("UICorner");round.CornerRadius=UDim.new(0,8*scale);round.Parent=signalBand
  local rim=Instance.new("UIStroke");rim.Name="SignalRim";rim.Color=Design.Edge;rim.Transparency=1;rim.Thickness=.6;rim.Parent=signalBand
  local falloff=Instance.new("UIGradient");falloff.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.12,.12),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(.88,.12),NumberSequenceKeypoint.new(1,1)});falloff.Parent=signalBand
  focus=Instance.new("Frame");focus.Name="FocusRail";focus.AnchorPoint=Vector2.new(.5,.5);focus.BackgroundColor3=amber;focus.BackgroundTransparency=1;focus.BorderSizePixel=0;focus.ZIndex=root.ZIndex;focus.Parent=root
  local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(0,8*scale);rounding.Parent=focus
  local edge=Instance.new("UIStroke");edge.Name="FocusRim";edge.Color=amber;edge.Transparency=1;edge.Thickness=.6;edge.Parent=focus
  marker.Image="";marker.BackgroundTransparency=.08;marker.BackgroundColor3=amber
  local cap=Instance.new("UICorner");cap.CornerRadius=UDim.new(1,0);cap.Parent=marker
  precisionBadge=Instance.new("TextLabel");precisionBadge.Name="PrecisionMode";precisionBadge.BackgroundTransparency=1;precisionBadge.AnchorPoint=Vector2.new(.5,1);precisionBadge.Text=options.PrecisionLabel or "PRECISION";precisionBadge.TextSize=12*scale;precisionBadge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium);precisionBadge.TextColor3=Design.Muted;precisionBadge.TextTransparency=1;precisionBadge.ZIndex=root.ZIndex+1;precisionBadge.Parent=root
 end
 local hit=Instance.new("TextButton");hit.Name="Input";hit.Text="";hit.BackgroundTransparency=1;hit.BorderSizePixel=0;hit.AutoButtonColor=false;hit.Selectable=true;hit.Size=UDim2.fromScale(1,1);hit.ZIndex=root.ZIndex+3;hit:SetAttribute("NoHover",true);hit:SetAttribute("ReferenceRulerControl",true);hit.Parent=root
 local tapeValue=state.position;tapeValue.Name="TapeValue";tapeValue.Parent=root
 local zoomValue=state.zoom;zoomValue.Name="Zoom";zoomValue.Parent=root
 controller.Root,controller.Input,controller.Selection=root,hit,marker
 controller.VisualValue,controller.Zoom=tapeValue,zoomValue
 local layers={{step=1,flashes={},pulses={},slots={}},{step=1/precisionZoom,flashes={},pulses={},slots={}}}
 local font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold)
 local lastVisual,flashUntil,pointerAxis=nil,0,nil
 local lastRenderAt
 local dirty=false;local interactionChanged=false;local destroying=false
 local coast,advanceCoast;local pendingCommit=false
 local motionGeneration=0
 local physicsUpdating=false
 local function track(signal,callback)local c=signal:Connect(callback);connections[#connections+1]=c;return c end
 local function coordinateScale()
  local result=1;local object=root
  while object and not object:IsA("ScreenGui")do
   for _,child in ipairs(object:GetChildren())do if child:IsA("UIScale")then result*=child.Scale;break end end
   object=object.Parent
  end
  return math.max(.001,result)
 end
 local function visible()
  if not controller.alive or not root.Parent then return false end
  local object=root
  while object do
   if object:IsA("GuiObject")and not object.Visible then return false end
   if object:IsA("ScreenGui")then return object.Enabled end
   object=object.Parent
  end
  return true
 end
 local function allowed()
  return visible()and not controller.suspended and(not options.CanInteract or options.CanInteract())
 end
 local function unbindWheel()
  if wheelBound then wheelBound=false;actions:UnbindAction(wheelAction)end
 end
 local function syncWheel()
  if not controller.hovered or not allowed()then unbindWheel();return end
  if wheelBound then return end
  wheelBound=true
  actions:BindActionAtPriority(wheelAction,function()
   return controller.hovered and allowed()and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
  end,false,Enum.ContextActionPriority.High.Value+1,Enum.UserInputType.MouseWheel)
 end
 local function bounded(value)
  value=tonumber(value);if not value or value~=value or math.abs(value)==math.huge then return low end
  return math.clamp(value,low,high)
 end
 local function rounded(value,quantum)
  value=bounded(value);quantum=math.max(1e-7,quantum)
  local origin=tonumber(options.SnapOrigin);if not origin or origin~=origin or math.abs(origin)==math.huge then origin=low end
  local result=origin+math.floor((value-origin)/quantum+.5)*quantum
  return math.clamp(math.floor(result*1e6+.5)/1e6,low,high)
 end
 local function text(value)
  if options.FormatTick then return options.FormatTick(value)end
  return tostring(math.floor(value*1e5+.5)/1e5)
 end
 local function slot(layer,index)
  local item=layer.slots[index];if item then return item end
  local line=Instance.new("Frame");line.Name="Tick";line.Visible=false;line.BorderSizePixel=0;line.BackgroundColor3=amber;line.AnchorPoint=Vector2.new(.5,0);line.ZIndex=root.ZIndex;line.Parent=viewport
  local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(1,0);rounding.Parent=line
  local label=Instance.new("TextLabel");label.Name="Number";label.Visible=false;label.Text="";label.BackgroundTransparency=1;label.FontFace=font;label.TextSize=22*scale;label.TextColor3=amber;label.TextXAlignment=Enum.TextXAlignment.Center;label.TextYAlignment=Enum.TextYAlignment.Center;label.ZIndex=root.ZIndex;label.Parent=viewport
  item={line=line,label=label};layer.slots[index]=item;return item
 end
 local function renderTrack(width,height,value,blend,now,elapsed)
  local pulse=0
  for _,layer in ipairs(layers)do
   for index,entry in pairs(layer.pulses)do
    local age=now-entry.time
    if entry.generation==motionGeneration and age<entry.life then pulse=math.max(pulse,(1-age/entry.life)^2)
    else layer.pulses[index]=nil end
   end
  end
  local hoverTarget=controller.dragging and 1 or(controller.hovered and .65 or 0)
  trackHover+=(hoverTarget-trackHover)*(1-math.exp(-22*math.max(elapsed,1/240)))
  trackFeedbackActive=math.abs(hoverTarget-trackHover)>.001
  if not trackFeedbackActive then trackHover=hoverTarget end
  local inset=math.min(width*.25,math.max(16,24*scale))
  local railWidth=math.max(1,width-inset*2);local ratio=math.clamp((value-low)/math.max(1e-7,high-low),0,1)
  local centerY=height*.5;local railHeight=math.max(5,7*scale)+blend*.5
  local handleSize=math.max(13,21*scale)+trackHover*2+blend+2*pulse
  local haloSize=math.min(inset*2,height,handleSize+12+4*trackHover+4*pulse)
  local x=inset+railWidth*ratio
  local accent=amber;local light=math.clamp(.13*trackHover+.7*pulse,0,1)
  trackVisual.Rail.Position=UDim2.fromOffset(width*.5,centerY);trackVisual.Rail.Size=UDim2.fromOffset(railWidth,railHeight)
  trackVisual.Rail.BackgroundColor3=Design.Well:Lerp(future,.12);trackVisual.Rim.Color=accent
  trackVisual.Rim.Transparency=.92-.08*trackHover-.06*blend
  trackVisual.Fill.Position=UDim2.new();trackVisual.Fill.Size=UDim2.fromScale(ratio,1)
  trackVisual.Gradient.Color=ColorSequence.new(accent:Lerp(Design.Surface,.28),accent:Lerp(white,.12+.36*pulse))
  trackVisual.Handle.Position=UDim2.fromScale(x/width,.5);trackVisual.Handle.Size=UDim2.fromOffset(handleSize,handleSize)
  trackVisual.Handle.BackgroundColor3=white:Lerp(accent,.16*(1-light));trackVisual.HandleRim.Color=accent:Lerp(white,.68)
  trackVisual.HandleRim.Transparency=.55-.16*trackHover-.18*pulse
  trackVisual.Halo.Position=UDim2.fromScale(x/width,.5);trackVisual.Halo.Size=UDim2.fromOffset(haloSize,haloSize)
  trackVisual.Halo.BackgroundColor3=accent;trackVisual.Halo.BackgroundTransparency=1-math.clamp(.07*trackHover+.07*blend+.14*pulse,0,.28)
 end
 local function render()
  if not controller.alive or controller.suspended or not visible()then return end
  local factor=coordinateScale();local width=root.AbsoluteSize.X/factor;local height=root.AbsoluteSize.Y/factor
  if width<=0 or height<=0 then return end
  local length=axis=="Vertical"and height or width
  local center=length*.5;local spacing=16.5*scale
  local now=os.clock();local value=tapeValue.Value;local zoom=zoomValue.Value
  if paletteTransition then
   local p=math.clamp((now-paletteTransition.at)/(paletteTransition.duration or .22),0,1);local eased=1-(1-p)^2
   amber=paletteTransition.accent:Lerp(paletteTransition.toAccent,eased)
   future=paletteTransition.future:Lerp(paletteTransition.toFuture,eased)
   markerColor=paletteTransition.marker:Lerp(paletteTransition.toMarker,eased)
   if p>=1 then paletteTransition=nil end
  end
  marker.ImageColor3=markerColor
  if focus then
   local landing,bounce=0,0
   for _,layer in ipairs(layers)do
    for index,entry in pairs(layer.pulses)do
     local age=now-entry.time
     if entry.generation==motionGeneration and age<entry.life then
      local pulse=(1-age/entry.life)^2
      landing=math.max(landing,pulse)
      bounce=math.max(bounce,math.sin(math.min(1,age/.22)*math.pi)*pulse)
     else layer.pulses[index]=nil end
    end
   end
   signalBand.Position=UDim2.fromScale(.5,.47);signalBand.Size=UDim2.new(1,-12*scale,0,30*scale)
   focus.Position=UDim2.fromScale(.5,.47);focus.Size=UDim2.fromOffset(30*scale,30*scale)
   focus.BackgroundColor3=amber;focus.FocusRim.Color=amber;marker.BackgroundColor3=amber:Lerp(white,landing)
   local capWidth=math.max(12,20*scale)*(1+.24*bounce);local capHeight=math.max(3,6*scale)*(1+.3*bounce)
   marker.Size=UDim2.fromScale(capWidth/width,capHeight/height);marker.Position=UDim2.fromScale(.5,.47-.9*scale*bounce/height)
   precisionBadge.Position=UDim2.new(.5,0,1,0);precisionBadge.Size=UDim2.fromOffset(90*scale,16*scale)
  end
  local elapsed=math.min(.1,lastRenderAt and now-lastRenderAt or 0)
  local blend=math.clamp((zoom-1)/math.max(.001,precisionZoom-1),0,1)
  if precisionBadge then precisionBadge.TextTransparency=1-blend*.8 end
  if trackSkin then
   renderTrack(width,height,value,blend,now,elapsed)
   lastVisual=value;lastRenderAt=now;dirty=false;return
  end
  local fineReveal=math.clamp((blend-.5)*2,0,1)
  local changing=lastVisual and math.abs(lastVisual-value)>1e-6
  if changing then flashUntil=now+.42 end
  if axis=="Horizontal"then
   marker.Rotation=0;if not focus then marker.Position=UDim2.new(.5,0,0,84*scale)end
  else
   marker.Rotation=90;marker.Position=UDim2.new(0,width-8*scale,.5,0)
  end
  for layerIndex,layer in ipairs(layers)do
   local layerOpacity=layerIndex==1 and 1 or fineReveal
   if layerOpacity<.001 then
    for _,item in ipairs(layer.slots)do item.line.Visible=false;item.label.Visible=false end
   else
    local interval=tickStep*layer.step
    local pixelStep=spacing*zoom*layer.step
    local count=math.min(poolLimit,math.ceil(length/math.max(1,pixelStep))+6)
    local first=math.floor(value/interval)-math.floor(count/2)
    for i=1,count do
     local item=slot(layer,i);local index=first+i-1;local number=index*interval
     local point=center+(number-value)/tickStep*spacing*zoom
     if axis=="Vertical"and not options.Reverse then point=length-point end
     local fineMajor=layerIndex==2 and index%precisionZoom==0
     local inRange=not fineMajor and number>=low-1e-5 and number<=high+1e-5 and point>=-20*scale and point<=length+20*scale
     if inRange then
      if changing and((lastVisual<value and number>lastVisual and number<=value)or(lastVisual>value and number<lastVisual and number>=value))then
       local crossing=math.clamp((number-lastVisual)/(value-lastVisual),0,1)
       layer.flashes[index]=now-elapsed*(1-crossing)
      end
      local crossed=layer.flashes[index];local age=crossed and now-crossed or math.huge
      local tail=math.exp(-.42/.12);local flash=age<.42 and math.max(0,(math.exp(-age/.12)-tail)/(1-tail))or 0
      local pulsed=layer.pulses[index];local pulseAge=pulsed and now-pulsed.time or math.huge
      local lifetime=pulsed and pulsed.life or .25
      local pulse=pulsed and pulsed.generation==motionGeneration and pulseAge<lifetime and(1-pulseAge/lifetime)^2 or 0
      local hover=options.HoverLighting and pointerAxis and controller.hovered and not controller.dragging and math.exp(-((point-pointerAxis)/(spacing*1.2))^2)*.25 or 0
      local light=math.clamp(math.max(flash,pulse,hover),0,1)
      local distance=math.abs(point-center)/math.max(1,center)
      local fade=math.clamp(1-distance^2,0,1)
      local opacity=fade*layerOpacity
      local base=options.ColorAt and options.ColorAt(number)or(number<=value+1e-5 and amber or future)
      local color=base:Lerp(white,light)
      item.line.Visible=true;item.line.BackgroundColor3=color;item.line.BackgroundTransparency=1-opacity
      if axis=="Horizontal"then
       local small=layerIndex==2
       local milestone=not small and index%majorEvery==0
       local markHeight=small and 7 or(milestone and 6 or 14)
       local markWidth=small and 2 or(milestone and 6 or 3)
       item.line.Position=UDim2.new(point/width,0,.47,-markHeight*.5*scale);item.line.Size=UDim2.fromOffset((markWidth+2*pulse)*scale,markHeight*scale)
      else
       item.line.AnchorPoint=Vector2.new(0,.5);item.line.Position=UDim2.new(0,20*scale,point/height,0);item.line.Size=UDim2.fromOffset(math.max(8*scale,width-40*scale),3*scale)
      end
      local labelOpacity=axis~="Horizontal"and options.ShowNumbers~=false and layerIndex==1 and(index%majorEvery==0 and 1 or fineReveal)or 0
      item.label.Visible=labelOpacity>.001
      if labelOpacity>.001 then
       item.label.Text=text(number);item.label.TextSize=(altairSkin and 19 or 22)*scale;item.label.TextColor3=altairSkin and Color3.fromRGB(222,226,236):Lerp(amber,number<=value and .24 or .08)or base;item.label.TextTransparency=1-opacity*labelOpacity*(altairSkin and(number<=value and 1 or .66)or 1)
       if axis=="Horizontal"then item.label.AnchorPoint=Vector2.new(.5,0);item.label.Position=UDim2.new(point/width,0,0,-3*scale);item.label.Size=UDim2.fromOffset(72*scale,28*scale)
       else item.label.AnchorPoint=Vector2.new(.5,.5);item.label.Position=UDim2.fromScale(.5,point/height);item.label.Size=UDim2.fromOffset(width,20*scale)end
      end
     else item.line.Visible=false;item.label.Visible=false end
    end
    for i=count+1,#layer.slots do layer.slots[i].line.Visible=false;layer.slots[i].label.Visible=false end
    if now>(layer.cleanupAt or 0)then
     layer.cleanupAt=now+.5
     for _,values in ipairs({layer.flashes,layer.pulses})do for index,at in pairs(values)do local time=type(at)=="table"and at.time or at;if now-time>1 then values[index]=nil end end end
    end
   end
  end
  lastVisual=value;lastRenderAt=now;dirty=false
 end
 local function disconnectRender()if renderConnection then renderConnection:Disconnect();renderConnection=nil end end
 local function wake()
  if controller.suspended or not controller.alive or renderConnection then return end
  renderConnection=run.RenderStepped:Connect(function(dt)
   if not visible()or controller.suspended then disconnectRender();return end
   if advanceCoast then advanceCoast(dt)end
   render()
   if not controller.dragging and not coast and not valueTween and not zoomTween and not paletteTransition and not trackFeedbackActive and os.clock()>flashUntil and not dirty then disconnectRender()end
  end)
 end
 local function cancelValueTween()if valueTween then local old=valueTween;valueTween=nil;old:Cancel()end end
 local function cancelZoomTween()if zoomTween then local old=zoomTween;zoomTween=nil;old:Cancel()end end
 local function moveValue(nextValue,animate,duration,easing)
  cancelValueTween()
  if animate and math.abs(tapeValue.Value-nextValue)>1e-6 then
   local tween=native:Create(tapeValue,TweenInfo.new(controlMotionTime(root,duration or options.MotionDuration or .12),easing or Enum.EasingStyle.Exponential,Enum.EasingDirection.Out),{Value=nextValue});valueTween=tween
   tween.Completed:Once(function()if valueTween==tween then valueTween=nil end end);tween:Play();wake()
  else tapeValue.Value=nextValue;lastVisual=nextValue;dirty=true;render()end
 end
 function controller:Set(nextValue,animate,preserveEffects)
  if not self.alive then return end
  local target=bounded(nextValue)
  if physicsUpdating and self.value==target then return end
  if animate==true and not self.suspended and self.value==target and(valueTween or math.abs(tapeValue.Value-target)<1e-6)then return end
  coast=nil;pendingCommit=false;if not preserveEffects then motionGeneration+=1 end
  if not self.dragging then self.InputStage="idle"end
  self.suspended=false;self.value=target;root:SetAttribute("Value",self.value)
  moveValue(self.value,animate==true);syncWheel()
 end
 function controller:GetValue()return self.value end
 function controller:RefreshVisual()dirty=true;if renderConnection then wake()else render()end end
 function controller:SetPrecision(enabled,animate)
  if not self.alive then return end
  self.precision=enabled==true;cancelZoomTween()
  local target=self.precision and precisionZoom or 1
  if animate~=false and math.abs(zoomValue.Value-target)>.001 then
   local tween=native:Create(zoomValue,TweenInfo.new(controlMotionTime(root,options.ZoomDuration or .24),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=target});zoomTween=tween
   tween.Completed:Once(function()if zoomTween==tween then zoomTween=nil end end);tween:Play();wake()
  else zoomValue.Value=target;dirty=true;render()end
 end
 local function changed(nextValue)
  if nextValue==controller.value then return end
  controller:Set(nextValue,true);dirty=true;interactionChanged=true
  if options.OnChanged then
   local ok,problem=pcall(options.OnChanged,nextValue);if not ok then warn("Altair ruler change: "..tostring(problem))end
  end
 end
 local function physicsValue(value)
  if value==controller.value then return end
  controller.value=value;root:SetAttribute("Value",value)
  if options.OnChanged then
   physicsUpdating=true
   local ok,problem=pcall(options.OnChanged,value)
   physicsUpdating=false;if not ok then warn("Altair ruler change: "..tostring(problem))end
  end
 end
 local function commitValue(value)
  pendingCommit=false
  if options.OnCommit then
   local ok,problem=pcall(options.OnCommit,value)
   if not ok then warn("Altair ruler commit: "..tostring(problem))end
  end
 end
 function controller:Pulse(lifetime)
  if not self.alive or self.suspended then return end
  local now=os.clock();lifetime=lifetime or .25
  for _,layer in ipairs(layers)do local interval=tickStep*layer.step;layer.pulses[math.floor(tapeValue.Value/interval+.5)]={time=now,life=lifetime,generation=motionGeneration}end
  flashUntil=math.max(flashUntil,now+lifetime);wake()
 end
 function controller:LandingPulse(generation)
  if not self.alive or self.suspended then return end
  generation=generation or motionGeneration
  if generation~=motionGeneration then return end
  self:Pulse(.25)
  task.delay(.27,function()
   if controller.alive and not controller.suspended and not controller.dragging and not coast and generation==motionGeneration then controller:Pulse(.8)end
  end)
 end
 function controller:IsCoasting()return coast~=nil end
 function controller:Fling(velocity,commit)
  if not self.alive or self.suspended then return end
  cancelValueTween();coast=nil;motionGeneration+=1
  velocity=math.clamp(tonumber(velocity)or 0,-(high-low)*4,(high-low)*4)
  if math.abs(velocity)<.01 then return end
  -- Release starts at the rendered phase, preserving continuity even when
  -- the rounded readout and the following tape are temporarily apart.
  pendingCommit=commit~=false
  coast={position=bounded(tapeValue.Value),velocity=velocity,direction=math.sign(velocity),age=0,commit=pendingCommit}
  self.InputStage="coast"
  wake()
 end
 local function landed(value,commit,generation)
  if generation~=motionGeneration or not controller.alive or controller.suspended then return end
  controller.InputStage="idle"
  if commit then commitValue(value)end
  if options.OnLanded then task.spawn(options.OnLanded,value)end
 end
 local function settle(position,commit)
  local ending=coast;coast=nil;local target=rounded(position,step);local generation=motionGeneration
  pendingCommit=commit==true
  if ending and ending.direction>0 then target=math.max(controller.value,target)
  elseif ending and ending.direction<0 then target=math.min(controller.value,target)end
  controller.InputStage="snap";physicsValue(target);controller:LandingPulse(generation)
  moveValue(target,true,options.SettleDuration or .27,Enum.EasingStyle.Quart)
  local settling=valueTween
  if settling then settling.Completed:Once(function(status)if status==Enum.PlaybackState.Completed then landed(target,commit,generation)end end)
  else landed(target,commit,generation)end
 end
 advanceCoast=function(dt)
  if not coast then return end
  local current=coast;local friction=math.max(.001,options.Friction or 4.2);dt=math.min(dt,.05)
  local decay=math.exp(-friction*dt)
  local nextPosition=bounded(current.position+current.velocity/friction*(1-decay))
  current.age+=dt;current.velocity*=decay
  if nextPosition==low or nextPosition==high then current.velocity=0 end
  current.position=nextPosition
  tapeValue.Value=tapeValue.Value+(nextPosition-tapeValue.Value)*(1-math.exp(-60*dt))
  local nextReadout=rounded(nextPosition,step)
  if current.direction>0 then nextReadout=math.max(controller.value,nextReadout)
  elseif current.direction<0 then nextReadout=math.min(controller.value,nextReadout)end
  physicsValue(nextReadout)
  if math.abs(current.velocity)<(options.StopVelocity or .4)or current.age>2 then settle(nextPosition,current.commit)end
 end
 local dragStart,dragValue,dragPixelsPerUnit,dragThreshold,activeTouch,lastDragAt,lastDragValue,lastMotionAt,dragVelocity,pressPrecision,dragMoved
 local function finish(immediate,commit)
  local wasDragging=controller.dragging
  local releaseVelocity=dragVelocity or 0
  local fresh=lastMotionAt and os.clock()-lastMotionAt<.1
  if lastMotionAt then releaseVelocity*=math.exp(-math.max(0,os.clock()-lastMotionAt)*12)end
  local tapped=wasDragging and not dragMoved and not immediate and commit~=false
  controller.dragging=false;controller.InputStage="idle";activeTouch=nil;dragStart=nil;dragValue=nil;dragPixelsPerUnit=nil;dragThreshold=nil
  if tapped then controller:SetPrecision(not pressPrecision,true);moveValue(controller.value,true);if pendingCommit then commitValue(controller.value)end
  else controller:SetPrecision(false,not immediate)end
  local thrown=commit~=false and not immediate and wasDragging and interactionChanged and fresh and(not pressPrecision or options.FineFling==true)and math.abs(releaseVelocity)>(options.FlickThreshold or 3)
  if thrown then controller:Fling(releaseVelocity,true)
  elseif commit~=false and wasDragging and interactionChanged and not pressPrecision then settle(controller.value,true)
  elseif commit~=false and wasDragging and interactionChanged then moveValue(controller.value,true);commitValue(controller.value)end
  interactionChanged=false
  if immediate then
   coast=nil;pendingCommit=false;motionGeneration+=1;controller.InputStage="idle";controller.hovered=false;pointerAxis=nil;unbindWheel();cancelValueTween();cancelZoomTween();controller.suspended=true;disconnectRender()
   for _,layer in ipairs(layers)do table.clear(layer.flashes);table.clear(layer.pulses)end
  else wake()end
 end
 function controller:IsDragging()return self.dragging end
 function controller:Cancel(immediate)coast=nil;pendingCommit=false;motionGeneration+=1;unbindWheel();finish(immediate==true,false)end
 function controller:SetRange(minimum,maximum,quantum,interval)
  low=tonumber(minimum)or 0;high=tonumber(maximum)or low+1;if high<=low then high=low+1 end
  step=math.max(1e-7,tonumber(quantum)or 1);tickStep=math.max(1e-7,tonumber(interval)or step)
  self:Set(bounded(self.value),false)
 end
 function controller:Configure(config)
  config=config or {};local previousVisual=tapeValue.Value;self:Cancel(true)
  if config.MajorEvery then majorEvery=math.max(1,math.floor(config.MajorEvery))end
  if config.Scale then scale=config.Scale end
  if config.PrecisionStep then options.PrecisionStep=config.PrecisionStep end
  local nextAccent=config.Color or amber;local nextFuture=config.FutureColor or future;local nextMarker=config.MarkerColor or markerColor
  if config.Animate==true and(nextAccent~=amber or nextFuture~=future or nextMarker~=markerColor)then
   paletteTransition={at=os.clock(),duration=controlMotionTime(root,.22),accent=amber,future=future,marker=markerColor,toAccent=nextAccent,toFuture=nextFuture,toMarker=nextMarker}
  else paletteTransition=nil;amber=nextAccent;future=nextFuture;markerColor=nextMarker;marker.ImageColor3=markerColor end
  if config.FormatTick then options.FormatTick=config.FormatTick end
  local range=config.Range or {low,high}
  low=tonumber(range[1])or 0;high=tonumber(range[2])or low+1;if high<=low then high=low+1 end
  step=math.max(1e-7,tonumber(config.Step)or step);tickStep=math.max(1e-7,tonumber(config.TickStep)or tickStep)
  local target=bounded(config.Value==nil and self.value or config.Value)
  if config.Animate==true then
   self.suspended=false;self.value=target;root:SetAttribute("Value",target);tapeValue.Value=previousVisual;lastVisual=previousVisual
   moveValue(target,true,options.RetargetDuration or .30,Enum.EasingStyle.Quart);syncWheel();wake()
  else self:Set(target,false)end
 end
 local function pointer(event)
  local point=event and event.Position or input:GetMouseLocation()
  return axis=="Vertical"and point.Y or point.X
 end
 local function dragPointer(event)
  if not controller.dragging or not allowed()then return end
  local distance=pointer(event)-dragStart
  if not dragMoved and math.abs(distance)<dragThreshold then return end
  dragMoved=true;controller.HasMoved=true;controller.InputStage=pressPrecision and "fine-drag"or"coarse-drag"
  -- A normal track follows the hand; a ruler moves its tape in the opposite
  -- direction. Freeze sensitivity for this gesture, including UI Size drags
  -- that resize their own ancestors while the pointer is still held down.
  local direction=(trackSkin and 1 or -1)*(options.Reverse and -1 or 1)
  local nextValue=bounded(dragValue+distance/dragPixelsPerUnit*direction)
  local now=os.clock();local elapsed=now-(lastDragAt or now)
  if elapsed>1e-4 and lastDragValue then
   local velocity=(nextValue-lastDragValue)/elapsed
   dragVelocity=(dragVelocity or 0)+(velocity-(dragVelocity or 0))*(1-math.exp(-elapsed*24))
   if math.abs(nextValue-lastDragValue)>1e-5 then lastMotionAt=now end
  end
  lastDragAt=now;lastDragValue=nextValue
  -- Keep the visible phase continuous even between rounded readout values.
  -- The callback's same-value Set echo is suppressed by physicsValue, so it
  -- cannot restart a following tween for every pointer sample.
  if math.abs(nextValue-tapeValue.Value)>1e-7 then interactionChanged=true end
  cancelValueTween();tapeValue.Value=nextValue;dirty=true
  physicsValue(rounded(nextValue,pressPrecision and(options.PrecisionStep or step/(precisionZoom*2))or step));wake()
 end
 track(hit.InputBegan,function(event)
  if not allowed()then return end
  if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
   if controller.dragging then return end
   coast=nil;motionGeneration+=1;cancelValueTween()
   controller.dragging=true;controller.HasMoved=false;controller.InputStage="pending";dirty=false;interactionChanged=false;activeTouch=event.UserInputType==Enum.UserInputType.Touch and event or nil;dragStart=pointer(event);dragValue=bounded(tapeValue.Value)
   pressPrecision=controller.precision==true;dragMoved=false
   local gestureScale=coordinateScale()
   if trackSkin then
    local railWidth=trackVisual.Rail.AbsoluteSize.X
    if railWidth<=0 then
     local width=root.AbsoluteSize.X/gestureScale
     local inset=math.min(width*.25,math.max(16,24*scale))
     railWidth=math.max(1,(width-inset*2)*gestureScale)
    end
    dragPixelsPerUnit=railWidth/math.max(1e-7,high-low)
   else dragPixelsPerUnit=16.5*scale*gestureScale/tickStep end
   dragPixelsPerUnit*=pressPrecision and precisionZoom or 1
   dragThreshold=(options.DragThreshold or 4)*scale*gestureScale
   lastDragAt=os.clock();lastDragValue=dragValue;lastMotionAt=nil;dragVelocity=0
   wake()
  elseif event.KeyCode==Enum.KeyCode.Left or event.KeyCode==Enum.KeyCode.Right or event.KeyCode==Enum.KeyCode.Up or event.KeyCode==Enum.KeyCode.Down then
   local direction=(event.KeyCode==Enum.KeyCode.Right or event.KeyCode==Enum.KeyCode.Up)and 1 or -1
   if options.Reverse and axis=="Vertical"then direction=-direction end
   local quantum=controller.precision and(options.PrecisionStep or step/(precisionZoom*2))or step
   changed(rounded(controller.value+quantum*direction,quantum));commitValue(controller.value)
  elseif event.KeyCode==Enum.KeyCode.Home or event.KeyCode==Enum.KeyCode.End then
   local target=event.KeyCode==Enum.KeyCode.Home and low or high
   -- Explicit boundary input owns the final value even while the rounded
   -- readout still matches it during an outgoing coast or retarget tween.
   if target==controller.value then
    coast=nil;pendingCommit=false;motionGeneration+=1;controller.InputStage="idle";moveValue(target,true)
   else changed(target)end
   commitValue(controller.value)
  end
 end)
 track(input.InputChanged,function(event)
  if controller.dragging and((activeTouch and event==activeTouch)or(not activeTouch and event.UserInputType==Enum.UserInputType.MouseMovement))then dragPointer(event)
  elseif controller.hovered and not controller.dragging and event.UserInputType==Enum.UserInputType.MouseWheel and allowed()then
   if controller.precision then
    local quantum=options.PrecisionStep or step/(precisionZoom*2)
    changed(rounded(controller.value+event.Position.Z*quantum*(options.Reverse and -1 or 1),quantum))
    commitValue(controller.value)
   else
    local velocity=(coast and coast.velocity or 0)+event.Position.Z*step*(options.WheelImpulse or 16)*(options.Reverse and -1 or 1)
    controller:Fling(velocity,true)
   end
  end
 end)
 track(input.InputEnded,function(event)
  if controller.dragging and((activeTouch and event==activeTouch)or(not activeTouch and event.UserInputType==Enum.UserInputType.MouseButton1))then dragPointer(event);finish(false)end
 end)
 track(input.WindowFocusReleased,function()controller.hovered=false;controller:Cancel(true)end)
 track(hit.MouseEnter,function()controller.hovered=true;dirty=true;syncWheel();wake()end)
 track(hit.MouseLeave,function()controller.hovered=false;unbindWheel();pointerAxis=nil;dirty=true;flashUntil=os.clock()+.16;wake()end)
 track(hit.MouseMoved,function(x,y)
  local factor=coordinateScale();pointerAxis=axis=="Vertical"and(y-root.AbsolutePosition.Y)/factor or(x-root.AbsolutePosition.X)/factor
  if allowed()then controller.hovered=true end
  if controller.hovered then dirty=true;syncWheel();wake()end
 end)
 track(root:GetPropertyChangedSignal("AbsoluteSize"),function()dirty=true;if not controller.suspended then render()end end)
 local function visibilityChanged()
  if not visible()then unbindWheel();finish(true,false)
  elseif not controller.suspended then
   -- A same-value Configure may run before its collapsed host is revealed.
   -- Retry after it becomes visible, including one frame for pending layout.
   dirty=true;render();syncWheel();wake()
  end
 end
 local ancestor=root
 while ancestor do
  if ancestor:IsA("GuiObject")then track(ancestor:GetPropertyChangedSignal("Visible"),visibilityChanged)
  elseif ancestor:IsA("ScreenGui")then track(ancestor:GetPropertyChangedSignal("Enabled"),visibilityChanged)end
  ancestor=ancestor.Parent
 end
 function controller:Destroy()
  if not self.alive then return end
  finish(true,false);self.alive=false;cancelValueTween();cancelZoomTween();disconnectRender()
  for _,connection in ipairs(connections)do connection:Disconnect()end;table.clear(connections)
  if root.Parent and not destroying then destroying=true;root:Destroy()end
 end
 track(root.Destroying,function()destroying=true;if controller.alive then controller:Destroy()end end)
 -- Mounting is normally hidden. Populate the bounded pools in short chunks so
 -- the first precision gesture never creates its tick/text instances mid-frame.
 local budgetAt=os.clock()
 if not trackSkin then
  for _,layer in ipairs(layers)do
   for index=1,poolLimit do
    if not controller.alive or not root.Parent then return controller end
    slot(layer,index)
    if os.clock()-budgetAt>=.0015 then run.Heartbeat:Wait();budgetAt=os.clock()end
   end
  end
 end
 root.Visible=true
 local range=options.Range or {0,100};controller:SetRange(range[1],range[2],options.Step,options.TickStep)
 majorEvery=math.max(1,math.floor(options.MajorEvery or 5));controller:Set(options.Value==nil and low or options.Value,false)
 return controller
end


-- A compact settings header expands into the shared ruler on demand.
local function buildSlider(template,parent,setting,onChange,onCommit)
 local row=template:Clone();row.Name=setting.name;row.Parent=parent;row.Visible=true;row.Title.Text=setting.name
 row:SetAttribute("AltairExpandableSlider",true);row:SetAttribute("Expanded",false);row.ClipsDescendants=true
 local old=row:FindFirstChild("Interact");if old then old:Destroy()end
 local license=row:FindFirstChild("LicenseDisplay");if license then license.Visible=false end
 local corner=row:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=UDim.new(0,12)end
 row.BackgroundColor3=Design.Raised;row.BackgroundTransparency=.12;row:SetAttribute("AltairDesignRole","inset")
 row.Title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold);row.Title.TextColor3=Color3.fromRGB(243,246,252)
 row.Description.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium);row.Description.TextColor3=Design.Muted;row.Description:SetAttribute("AltairDesignRole","muted")
 local rim=row:FindFirstChildOfClass("UIStroke");if rim then rim.Color=Design.Edge;rim.Thickness=.6;rim.Transparency=.9 end
 local native=game:GetService("TweenService");local input=game:GetService("UserInputService")
 local connections={};local animations=setmetatable({},{__mode="k"})
 local controller={alive=true,Expanded=false,creating=false,dirty=false,version=0}
 setting._sliderController=controller
 local screen=parent:FindFirstAncestorOfClass("ScreenGui");local settings=screen and screen:FindFirstChild("Settings")
 local pages=parent.Parent and parent.Parent:FindFirstChildOfClass("UIPageLayout")
 local low,high=setting.values[1],setting.values[2];local step=setting.step or 1
 local accents={
  uisize=Color3.fromRGB(96,165,250),themetint=Color3.fromRGB(203,141,247),
  themelightness=Color3.fromRGB(248,194,85),panelopacity=Color3.fromRGB(64,204,187),
  oledidledim=Color3.fromRGB(239,125,153),oledidledelay=Color3.fromRGB(168,146,235),
  notificationduration=Color3.fromRGB(96,211,144),capsulerevealtime=Color3.fromRGB(246,162,91),
 }
 local baseAccent=accents[setting.id]or Color3.fromRGB(103,161,235)
 local accent,futureAccent,markerAccent
 local function styleAccents()
  accent=baseAccent
  futureAccent=accent:Lerp(Color3.fromRGB(8,10,14),.78)
  markerAccent=accent:Lerp(Color3.fromRGB(10,12,16),.28)
 end
 styleAccents()
 local baseHeight=60;local rulerHeight=52
 local function make(class,name,properties,container)
  local object=Instance.new(class);object.Name=name
  if object:IsA("GuiObject")then object.BackgroundTransparency=1;object.BorderSizePixel=0;object.ZIndex=row.Title.ZIndex end
  for key,value in pairs(properties or {})do object[key]=value end;object.Parent=container or row;return object
 end
 local function connect(signal,callback)local c=signal:Connect(callback);connections[#connections+1]=c;return c end
 local function stop(object,goal)
  local running=animations[object];if not running then return end
  for property in pairs(goal)do local tween=running[property];if tween then tween:Cancel();running[property]=nil end end
 end
 local function animate(object,duration,goal,style)
  stop(object,goal)
  local running=animations[object]or {};animations[object]=running
  local tween=native:Create(object,TweenInfo.new(controlMotionTime(row,duration),style or Enum.EasingStyle.Quart,Enum.EasingDirection.Out),goal)
  for property in pairs(goal)do running[property]=tween end
  tween.Completed:Once(function()for property in pairs(goal)do if running[property]==tween then running[property]=nil end end end);tween:Play()
 end
 local function visible()
  if not controller.alive or not row.Parent or(settings and settings:GetAttribute("AltairClosing"))then return false end
  if pages and pages.CurrentPage and pages.CurrentPage~=parent then return false end
  local object=row
  while object do
   if object:IsA("GuiObject")and not object.Visible then return false end
   if object:IsA("ScreenGui")then return object.Enabled end
   object=object.Parent
  end
  return false
 end
 local function painted()
  if pages and pages.CurrentPage and pages.CurrentPage~=parent then return false end
  local object=row;while object do
   if object:IsA("GuiObject")and(not object.Visible or object:IsA("CanvasGroup")and object.GroupTransparency>.999)then return false end
   if object:IsA("ScreenGui")then return object.Enabled end;object=object.Parent
  end
  return false
 end
 local function formatted(number)
  number=math.round(number*10)/10
  return(number%1==0 and tostring(math.floor(number))or string.format("%.1f",number))..(setting.suffix or "%")
 end
 local value=make("TextLabel","Value",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-43,0,12),Size=UDim2.fromOffset(95,22),TextSize=14,TextColor3=row.Title.TextColor3,FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold),TextXAlignment=Enum.TextXAlignment.Right})
 local arrow=make("ImageLabel","ExpandArrow",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-17,0,23),Size=UDim2.fromOffset(16,16),ImageColor3=row.Title.TextColor3,ImageTransparency=.3});applyIcon(arrow,"chevron-down")
 local header=make("TextButton","Expand",{Text="",AutoButtonColor=false,Selectable=true,Size=UDim2.new(1,0,0,baseHeight),ZIndex=row.Title.ZIndex+2})
 local content=make("CanvasGroup","RulerContent",{Position=UDim2.fromOffset(18,baseHeight+4),Size=UDim2.new(1,-36,0,44),GroupTransparency=1,Visible=false})
 row.Title.Position=UDim2.fromOffset(18,12);row.Title.Size=UDim2.new(1,-165,0,22)
 row.Description.Text=setting.description or "";row.Description.Visible=row.Description.Text~="";row.Description.TextWrapped=true
 row.Description.Position=UDim2.fromOffset(18,36);row.Description.Size=UDim2.new(1,-36,0,48);row.Description.TextTransparency=.25
 local function readout()
  value.Text=formatted(tonumber(setting.current)or low);value:SetAttribute("DisplayedValue",value.Text)
 end
 local function commit(committedValue)
  if not controller.alive or not controller.dirty then return end
  if committedValue~=nil and math.abs(committedValue-(tonumber(setting.current)or low))>1e-6 then return end
  controller.dirty=false;if onCommit then onCommit()end
 end
 local layout
 local interactionReset=false
 local function settleInteraction()
  -- Closing/group fades keep their own concealment. Settle a cancelled hover
  -- only after this row is eligible again, using the authored material alpha.
  if not interactionReset or not visible()then return end
  interactionReset=false
  Design.freezeMaterial(row)
  row.BackgroundTransparency=Design.materialAlpha(row,.12)
  if rim and rim.Parent then rim.Transparency=.9 end
  arrow.ImageTransparency=.3
 end
 function controller:Cancel(immediate,save)
  if self.Ruler then self.Ruler:Cancel(true)end
  if immediate then
   for _,running in pairs(animations)do for _,tween in pairs(running)do tween:Cancel()end end;table.clear(animations)
   interactionReset=true;settleInteraction()
   if layout and not painted()then layout(false)end
  end
  if save~=false then commit()end
 end
 layout=function(animated)
  if not controller.alive then return end
  local textHeight=row.Description.Visible and math.max(14,row.Description.TextBounds.Y)or 0
  baseHeight=row.Description.Visible and math.max(60,36+textHeight+12)or 52
  header.Size=UDim2.new(1,0,0,baseHeight);row.Description.Size=UDim2.new(1,-36,0,textHeight+2)
  content.Position=UDim2.fromOffset(18,baseHeight+4)
  local goals={{row,{Size=UDim2.new(1,-16,0,baseHeight+(controller.Expanded and rulerHeight or 0))}},{arrow,{Rotation=controller.Expanded and 180 or 0}}}
  if controller.Expanded and controller.Ruler then content.Visible=true end
  goals[#goals+1]={content,{GroupTransparency=controller.Expanded and controller.Ruler and 0 or 1}}
  for _,target in ipairs(goals)do
   if animated then animate(target[1],.24,target[2])
   else stop(target[1],target[2]);for property,nextValue in pairs(target[2])do target[1][property]=nextValue end end
  end
  if not controller.Expanded then
   local version=controller.version
   if not animated then content.Visible=false
   else task.delay(.25,function()if controller.alive and controller.version==version and not controller.Expanded then content.Visible=false end end)end
  end
 end
 local function configure(animated)
  if not controller.Ruler then return end
  if not controller.Expanded or not visible()then controller.Ruler:Cancel(true);return end
   styleAccents()
  controller.Ruler:Configure({Range=setting.values,Value=setting.current,Step=step,TickStep=setting.tickStep or step,PrecisionStep=.1,MajorEvery=setting.majorEvery or 5,Scale=582/908,Animate=animated==true,Skin="Track",Color=accent,FutureColor=futureAccent,MarkerColor=markerAccent})
 end
 local function ensureRuler()
  if controller.Ruler or controller.creating or not controller.alive or not controller.Expanded then return end
  controller.creating=true
   styleAccents()
  local ruler=buildRuler(content,{Name="SettingsRuler",Range=setting.values,Value=setting.current,Step=step,TickStep=setting.tickStep or step,PrecisionStep=.1,MajorEvery=setting.majorEvery or 5,Scale=582/908,Size=UDim2.fromScale(1,1),Skin="Track",Color=accent,FutureColor=futureAccent,MarkerColor=markerAccent,
   CanInteract=function()return controller.alive and controller.Expanded and not controller.creating and visible()end,
   OnChanged=function(nextValue)
    if not controller.alive or not controller.Expanded or not visible()then return end
    nextValue=math.clamp(math.round(nextValue*10)/10,low,high)
    if nextValue==setting.current then return end
    setting.current=nextValue;controller.dirty=true;readout();if onChange then onChange(nextValue)end
   end,
   OnCommit=commit,
  })
  controller.creating=false
  if not controller.alive then ruler:Destroy();return end
  controller.Ruler=ruler;configure(false)
 end
 function controller:SetExpanded(expanded,animated)
  if not self.alive then return end
  self.version+=1;self.Expanded=expanded==true;row:SetAttribute("Expanded",self.Expanded)
  if not self.Expanded then self:Cancel(false,true)end
  -- Track construction has no tick pools or waits. Mount it before reserving
  -- expansion space, so the first opening never reveals an empty control area.
  if self.Expanded then if self.Ruler then configure(false)else ensureRuler()end end
  layout(animated~=false)
 end
 function controller:Refresh(animated)
  if not self.alive then return end
  settleInteraction();readout();configure(animated);layout(animated)
 end
 function controller:Destroy()
  if not self.alive then return end
  self:Cancel(true,false);self.alive=false;self.version+=1
  for _,c in ipairs(connections)do c:Disconnect()end;table.clear(connections)
  if self.Ruler then self.Ruler:Destroy()end
  if setting._sliderController==self then setting._sliderController=nil end
 end
 connect(header.Activated,function()if visible()then controller:SetExpanded(not controller.Expanded,true)end end)
 connect(header.MouseEnter,function()if visible()then interactionReset=false;if row:FindFirstChild("UIStroke")then animate(row.UIStroke,.18,{Transparency=.8})end;animate(row,.18,{BackgroundTransparency=.06});animate(arrow,.18,{ImageTransparency=0})end end)
 connect(header.MouseLeave,function()if controller.alive then if visible()then interactionReset=false end;if row:FindFirstChild("UIStroke")then animate(row.UIStroke,.18,{Transparency=.9})end;animate(row,.18,{BackgroundTransparency=.12});animate(arrow,.18,{ImageTransparency=.3})end end)
 connect(row.Description:GetPropertyChangedSignal("TextBounds"),function()layout(false)end)
 connect(row:GetAttributeChangedSignal("AltairRefreshValue"),function()
  -- An external update owns both the value and its persistence. Discard the
  -- interrupted gesture's pending commit before retargeting the same tape.
  controller:Cancel(false,false);controller.dirty=false;controller:Refresh(true)
 end)
 connect(input.WindowFocusReleased,function()controller:Cancel(false,true)end)
 local ancestor=row
 while ancestor do
  if ancestor:IsA("GuiObject")then connect(ancestor:GetPropertyChangedSignal("Visible"),function()if not visible()then controller:Cancel(true,true)else controller:Refresh(false)end end)
  elseif ancestor:IsA("ScreenGui")then connect(ancestor:GetPropertyChangedSignal("Enabled"),function()if not visible()then controller:Cancel(true,true)else controller:Refresh(false)end end)end
  ancestor=ancestor.Parent
 end
 if pages then connect(pages:GetPropertyChangedSignal("CurrentPage"),function()if not visible()then controller:Cancel(true,true)else controller:Refresh(false)end end)end
 if settings then connect(settings:GetAttributeChangedSignal("AltairClosing"),function()if settings:GetAttribute("AltairClosing")then controller:Cancel(true,true)elseif visible()then controller:Refresh(painted())end end)end
 connect(row.Destroying,function()controller:Destroy()end)
 readout();layout(false);return row
end

-- Character parameters share one ruler; the four model slots remain the source of truth.
local function buildDaylightDial(parent,options)
 options=options or {};local input=options.Input or game:GetService("UserInputService");local native=game:GetService("TweenService")
 local controller={alive=true,value=0,dragging=false};local connections={};local held,motion,dragOrigin,dragValue;local revision,reconciling=0,false
 local root=Instance.new("CanvasGroup");root.Name=options.Name or "DaylightDial";root.BackgroundTransparency=1;root.Size=options.Size or UDim2.new(1,0,0,126);root.Position=options.Position or UDim2.new();root.ZIndex=parent.ZIndex+1;root:SetAttribute("AltairThemeIgnore",true);root:SetAttribute("AltairDaylightDial",true);root.Parent=parent
 local function make(class,name,properties)
  local object=Instance.new(class);object.Name=name;if object:IsA("GuiObject")then object.BackgroundTransparency=1;object.BorderSizePixel=0;object.ZIndex=root.ZIndex+1 end
  for key,value in pairs(properties or{})do object[key]=value end;object.Parent=root;return object
 end
 local function connect(signal,callback)local c=signal:Connect(callback);connections[#connections+1]=c;return c end
 local gold,night=Color3.fromRGB(238,183,86),Color3.fromRGB(144,162,213);local segments={}
 for index=0,47 do
  local object=make("Frame","Arc"..index,{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Design.Edge})
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(1,0);corner.Parent=object
  local fade=Instance.new("UIGradient");fade.Transparency=NumberSequence.new(.1,0);fade.Parent=object;segments[index+1]=object
 end
 local marker=make("Frame","Marker",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(10,10),BackgroundColor3=gold,BackgroundTransparency=0})
 local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(1,0);rounding.Parent=marker
 local rim=Instance.new("UIStroke");rim.Color=Design.Ink;rim.Thickness=.6;rim.Transparency=.5;rim.Parent=marker
 local time=make("TextLabel","Time",{AnchorPoint=Vector2.new(.5,1),Size=UDim2.fromOffset(92,23),Text="12:00",TextSize=19,TextColor3=Design.Ink,FontFace=Design.Heading})
 local hint=make("TextLabel","Hint",{AnchorPoint=Vector2.new(.5,0),Size=UDim2.fromOffset(220,14),Text="Drag the arc beneath the marker",TextSize=10,TextColor3=Design.Muted,FontFace=Design.Font})
 local moon=make("ImageLabel","Moon",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(14,14),ImageColor3=night});applyIcon(moon,"moon")
 local sun=make("ImageLabel","Sun",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(14,14),ImageColor3=gold});applyIcon(sun,"sun")
 local dusk=make("ImageLabel","Dusk",{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(14,14),ImageColor3=night});applyIcon(dusk,"moon")
 local hit=make("TextButton","Input",{Text="",AutoButtonColor=false,Selectable=true,Size=UDim2.fromScale(1,1),ZIndex=root.ZIndex+3})
 local reset=make("ImageButton","Reset",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-4,0,4),Size=UDim2.fromOffset(28,28),AutoButtonColor=false,ImageColor3=Design.Muted,ZIndex=root.ZIndex+4});applyIcon(reset,"rotate-ccw")
 local visual=Instance.new("NumberValue");visual.Name="Hour";visual.Parent=root
 local function render()
  if not controller.alive then return end
  local width,height=root.AbsoluteSize.X,root.AbsoluteSize.Y;if width<=0 or height<=0 then return end
  local radius=math.min(width*.31,height*.74);local base=height*.83;local center=width*.5;local ratio=visual.Value/24
  for index,object in ipairs(segments)do
   local hour=(index-1)*.5;local distance=(hour-visual.Value+12)%24-12;local angle=distance*math.pi/12
   local edge=math.clamp((6-math.abs(distance))/.8,0,1);object.Visible=edge>0
   object.Position=UDim2.fromScale((center+math.sin(angle)*radius)/width,(base-math.cos(angle)*radius)/height)
   object.Size=UDim2.fromOffset(2,index%4==1 and 10 or 6);object.Rotation=-math.deg(angle)
   object.BackgroundColor3=night:Lerp(gold,math.max(0,math.sin((hour-6)*math.pi/12)))
   object.BackgroundTransparency=1-edge*(index%4==1 and .9 or .56)
  end
  marker.Position=UDim2.fromScale(.5,(base-radius)/height);marker.BackgroundColor3=night:Lerp(gold,math.max(0,math.sin((visual.Value-6)*math.pi/12)))
  local minute=math.floor(controller.value*60+.5)%1440;time.Text=string.format("%02d:%02d",math.floor(minute/60),minute%60)
  local ink=options.InkSource and options.InkSource.TextColor3 or Design.Ink
  time.TextColor3=ink;hint.TextColor3=ink:Lerp(Design.Muted,.65);rim.Color=ink
  time.Position=UDim2.fromScale(.5,.72);hint.Position=UDim2.fromScale(.5,.79)
  local iconGap=height*.15;moon.Position=UDim2.fromScale((center-radius-iconGap)/width,base/height);dusk.Position=UDim2.fromScale((center+radius+iconGap)/width,base/height);sun.Position=UDim2.fromScale(.5,.35)
  reset.ImageColor3=ink:Lerp(Design.Muted,.45)
 end
 local function allowed()
  if not controller.alive or not root.Parent or(options.CanInteract and not options.CanInteract())then return false end
  local object=root;while object do if object:IsA("GuiObject")and not object.Visible then return false elseif object:IsA("ScreenGui")then return object.Enabled end;object=object.Parent end;return false
 end
 function controller:Set(value,animated)
  if not self.alive or type(value)~="number"or value~=value or math.abs(value)==math.huge then return end
  revision+=1
  self.value=math.clamp(math.floor(value*60+.5)/60,0,24);if motion then motion:Cancel();motion=nil end
  if animated then motion=native:Create(visual,TweenInfo.new(controlMotionTime(root,.2),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=self.value});motion:Play()else visual.Value=self.value end;render()
 end
 function controller:GetValue()return self.value end
 function controller:IsDragging()return self.dragging end
 local function reconcileCurrent(version)
  if reconciling or revision~=version or not controller.alive or controller.dragging or not root.Parent or type(options.GetValue)~="function"then return end
  reconciling=true;local ok,value=pcall(options.GetValue);reconciling=false
  if not ok or revision~=version or not controller.alive or controller.dragging or not root.Parent or type(value)~="number"or value~=value or math.abs(value)==math.huge then return end
  value=math.clamp(value,0,24)
  -- Midnight endpoints are equivalent: keep an explicitly selected 24 intact.
  if math.abs(((value-controller.value+12)%24)-12)>=.001 then controller:Set(value,false)end
 end
 function controller:Cancel(skipReconcile)
  local wasDragging=self.dragging;revision+=1;held=nil;dragOrigin=nil;dragValue=nil;self.dragging=false;if motion then motion:Cancel();motion=nil end
  if wasDragging and not skipReconcile then reconcileCurrent(revision)end
 end
 local function change(value,commit)
  local previous=controller.value;controller:Set(value,false)
  if controller.value~=previous and options.OnChanged then options.OnChanged(controller.value)end
  if commit and options.OnCommit then options.OnCommit(controller.value)end
 end
 local function position(event)
  local point=event and event.Position or input:GetMouseLocation();local screen=root:FindFirstAncestorOfClass("ScreenGui")
  return Vector2.new(point.X,point.Y)+(screen and screen.AbsolutePosition or Vector2.zero)-root.AbsolutePosition
 end
 local function move(event)
  if not controller.dragging or not allowed()then controller:Cancel();return end
  local width,height=root.AbsoluteSize.X,root.AbsoluteSize.Y;if width<=0 or height<=0 or not dragOrigin then return end
  local radius=math.min(width*.31,height*.74);local p=position(event)
  change(dragValue+(dragOrigin.X-p.X)*12/math.max(1,math.pi*radius),false)
 end
 connect(hit.InputBegan,function(event)
  if not allowed()then return end
  if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then controller:Cancel();held=event;dragOrigin=position(event);dragValue=controller.value;controller.dragging=true
  elseif event.UserInputType==Enum.UserInputType.Keyboard then
   local code=event.KeyCode
   if code==Enum.KeyCode.Left or code==Enum.KeyCode.Down then change(controller.value-1/60,true)
   elseif code==Enum.KeyCode.Right or code==Enum.KeyCode.Up then change(controller.value+1/60,true)
   elseif code==Enum.KeyCode.Home then change(0,true)elseif code==Enum.KeyCode.End then change(24,true)end
  end
 end)
 connect(reset.Activated,function()
  if not allowed()then return end
  controller:Cancel();local value=options.OnReset and options.OnReset()
  if type(value)=="number"then controller:Set(value,true)end
  bounceReset(reset)
 end)
 connect(input.InputChanged,function(event)if held and(event==held or held.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseMovement)then move(event)end end)
 connect(input.InputEnded,function(event)if held and(event==held or held.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseButton1)then
  if not allowed()then controller:Cancel();return end
  local active=held;move(event)
  if held~=active or not controller.dragging then return end
  if not allowed()then controller:Cancel();return end
  local value=controller.value;controller:Cancel(true);local version=revision
  if options.OnCommit then options.OnCommit(value)end
  reconcileCurrent(version)
 end end)
 connect(input.WindowFocusReleased,function()controller:Cancel()end)
 connect(root:GetPropertyChangedSignal("AbsoluteSize"),render);connect(visual.Changed,function()if not controller.dragging then render()end end)
 if options.InkSource then connect(options.InkSource:GetPropertyChangedSignal("TextColor3"),render)end
 local ancestor=root
 while ancestor do
  if ancestor:IsA("GuiObject")then connect(ancestor:GetPropertyChangedSignal("Visible"),function()if not allowed()then controller:Cancel()else render()end end)
  elseif ancestor:IsA("ScreenGui")then connect(ancestor:GetPropertyChangedSignal("Enabled"),function()if not allowed()then controller:Cancel()else render()end end)end
  ancestor=ancestor.Parent
 end
 function controller:Destroy()if not self.alive then return end;self.alive=false;self:Cancel();for _,c in ipairs(connections)do c:Disconnect()end;table.clear(connections);if root.Parent then root:Destroy()end end
 connect(root.Destroying,function()controller:Destroy()end)
 controller.Root,controller.Input,controller.Marker,controller.Readout,controller.VisualValue=root,hit,marker,time,visual
 controller:Set(options.Value or 12,false);return controller
end

local function buildCharacterRuler(root,models,onValue,canInteract,onResize)
 local panel=root.Character;local body=panel.Interactions
 panel.Size=UDim2.fromOffset(582,304);body.Size=UDim2.new(1,0,1,-50)
 local native=game:GetService("TweenService");local connections={};local animations=setmetatable({},{__mode="k"})
 local service={alive=true,Selected=nil,SelectedModel=nil,Expanded=false,value=models[1].value or models[1].default,version=0}
 local outsidePress;local outsideGeneration=0
 local sourceScale=582/908;local font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local white=Design.Ink;local muted=Design.Muted
 local neutral=Design.Surface
 local function chipNeutral()return neutral end
 local function contentPosition(horizontal,vertical)
  return UDim2.fromOffset(-142+(horizontal or 0),236+(vertical or 0))
 end
 local function accentFor(index)
  if index==nil and service.Selected==nil and typeof(service.AccentColor)=="Color3"then return service.AccentColor end
  local model=models[index or service.Selected or 1]
  return model and typeof(model.color)=="Color3"and model.color or Color3.fromRGB(44,153,93)
 end
 local function chipColor(index,selected,hovered)
  return neutral:Lerp(accentFor(index),selected and .42 or hovered and .18 or .06)
 end
 local function futureColor(accent)return neutral:Lerp(accent,.28)end
 local function chipInk(selected,hovered)return selected and white or hovered and Color3.fromRGB(220,222,227)or muted end
 local function make(class,parent,name,properties)
  local o=Instance.new(class);o.Name=name
  if o:IsA("GuiObject")then o.BackgroundTransparency=1;o.BorderSizePixel=0;o.ZIndex=body.ZIndex+3 end
  for key,value in pairs(properties or {})do o[key]=value end;o.Parent=parent;return o
 end
 local function connect(signal,callback)local c=signal:Connect(callback);connections[#connections+1]=c;return c end
 local function animate(object,time,goal,style)
  if animations[object]then animations[object]:Cancel()end
  local t=native:Create(object,TweenInfo.new(controlMotionTime(root,time),style or Enum.EasingStyle.Exponential,Enum.EasingDirection.Out),goal);animations[object]=t
  t.Completed:Once(function()if animations[object]==t then animations[object]=nil end end);t:Play();return t
 end
 local function allowed()
  return service.alive and panel.Visible and not panel:GetAttribute("AltairClosing")and(not canInteract or canInteract())
 end
 local function claimInteraction()outsidePress=nil;outsideGeneration+=1 end
 local function claimPress(event)
  if allowed()and(event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)then claimInteraction()end
 end
 local deck=make("Frame",body,"RulerDeck",{Position=UDim2.fromOffset(158,24),Size=UDim2.fromOffset(408,68)})
 deck:SetAttribute("AltairThemeIgnore",true);service.Root=deck
 local content=make("CanvasGroup",deck,"RulerContent",{Position=contentPosition(),Size=UDim2.fromOffset(550,86),GroupTransparency=1,Visible=false})
 local sectionTitle=make("TextLabel",content,"SelectedProperty",{Position=UDim2.fromOffset(0,4),Size=UDim2.fromOffset(240,18),Text="Tuning",TextSize=11,FontFace=Design.Font,TextColor3=muted,TextXAlignment=Enum.TextXAlignment.Left})
 local expansion=Instance.new("NumberValue");expansion.Name="Expansion";expansion.Value=0;expansion.Parent=deck
 local contentReveal=Instance.new("NumberValue");contentReveal.Name="ContentReveal";contentReveal.Value=1;contentReveal.Parent=deck
 local contentShift=Instance.new("NumberValue");contentShift.Name="ContentShift";contentShift.Parent=deck
 service.Content=content;service.Expansion=expansion
 local chips={};local names={"Speed","Jump","Flight","FOV"}
 for index,name in ipairs(names)do
  local chip=make("TextButton",deck,"Parameter"..index,{Text=name,FontFace=font,TextSize=12,TextColor3=muted,TextXAlignment=Enum.TextXAlignment.Left,AutoButtonColor=false,BackgroundTransparency=.08,BackgroundColor3=chipColor(index,false,false),Position=UDim2.fromOffset(((index-1)%3)*140,math.floor((index-1)/3)*38),Size=UDim2.fromOffset(128,30),Selectable=true})
  local padding=Instance.new("UIPadding");padding.PaddingLeft=UDim.new(0,12);padding.Parent=chip
  chip:SetAttribute("AltairDesignRole","control")
  local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(0,8);rounding.Parent=chip;chips[index]=chip
  local gradient=Instance.new("UIGradient");gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(233,233,236));gradient.Rotation=90;gradient.Parent=chip
  local rim=Instance.new("UIStroke");rim.Name="ChipRim";rim.Thickness=.6;rim.Color=accentFor(index);rim.Transparency=.91;rim.Parent=chip
  chip:SetAttribute("AltairBaseColor",accentFor(index))
  connect(chip.MouseButton1Click,function()if allowed()then service:Select(index,true)end end)
  connect(chip.InputBegan,claimPress)
  connect(chip.MouseEnter,function()if allowed()and service.Selected~=index then animate(chip,.16,{BackgroundColor3=chipColor(index,false,true),TextColor3=chipInk(false,true)})end end)
  connect(chip.MouseLeave,function()if service.alive and service.Selected~=index then animate(chip,.2,{BackgroundColor3=chipColor(index,false,false),TextColor3=chipInk(false,false)})end end)
 end
 service.Chips=chips
 local daylightButton=body.Grid:FindFirstChild("Time of Day")
 if daylightButton then
  daylightButton.Parent=deck;daylightButton.Position=UDim2.fromOffset(140,38);daylightButton.Size=UDim2.fromOffset(268,30)
  local hit=daylightButton:FindFirstChild("Interact");if hit then hit.Size=UDim2.fromScale(1,1)end
  local icon=daylightButton:FindFirstChild("Icon");if icon then icon.Position=UDim2.fromOffset(10,7);icon.Size=UDim2.fromOffset(16,16)end
  local title=daylightButton:FindFirstChild("Title");if title then title.Position=UDim2.fromOffset(34,0);title.Size=UDim2.new(1,-42,1,0);title.TextSize=12 end
  connect(daylightButton.InputBegan,claimPress);if hit then connect(hit.InputBegan,claimPress)end
  service.DaylightButton=daylightButton
 end
 local numberSize=33*sourceScale;local unitSize=20*sourceScale
 local valueHost=make("TextLabel",content,"ValueReadout",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-54,0,17),Size=UDim2.fromOffset(100,30),Text="",Font=Enum.Font.BuilderSansBold,TextSize=numberSize,TextColor3=white,TextXAlignment=Enum.TextXAlignment.Right})
 local unit=make("TextLabel",content,"Unit",{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,0,0,17),Size=UDim2.fromOffset(50,25),Text="",Font=Enum.Font.SourceSansSemibold,TextSize=unitSize,TextColor3=muted,TextXAlignment=Enum.TextXAlignment.Right})
 service.Readout=valueHost;service.Unit=unit
 local reset,resetGlyph;local resetAlpha=.45
 local widthsCache={};local widthsCacheCount=0;local textService=game:GetService("TextService")
 local function textWidth(label,size,typeface)
  if label==""then return 0 end
  local key=tostring(typeface)..":"..tostring(size)..":"..label;local width=widthsCache[key]
  if not width then
   width=textService:GetTextSize(label,size,typeface,Vector2.new(10000,100)).X
   if widthsCacheCount>=256 then table.clear(widthsCache);widthsCacheCount=0 end
   widthsCache[key]=width;widthsCacheCount+=1
  end
  return width
 end
 local function formatted(value)
  local n=math.round(value*10)/10
  return n%1==0 and tostring(math.floor(n))or string.format("%.1f",n)
 end
 local function units()
  return service.Selected==1 and"studs/s"or service.Selected==3 and"×"or service.Selected==4 and"°"or ""
 end
 local function readout(value,animated)
  local label=formatted(value);local suffix=units();service.value=value
  -- The recording replaces digits on one baseline. Width changes reposition the
  -- reset immediately; only its enabled/disabled emphasis crossfades afterward.
  local numberWidth=textWidth(label,numberSize,Enum.Font.BuilderSansBold)
  local unitWidth=textWidth(suffix,unitSize,Enum.Font.SourceSansSemibold)
  local inset=unitWidth+(unitWidth>0 and 8*sourceScale or 0)
  valueHost.Text=label;valueHost:SetAttribute("DisplayedValue",label)
  valueHost.Position=UDim2.new(1,-inset,0,17);valueHost.Size=UDim2.fromOffset(numberWidth+1,30)
  unit.Text=suffix;unit.Visible=suffix~="";unit.TextTransparency=0;unit.Size=UDim2.fromOffset(unitWidth+1,25)
  unit.AnchorPoint=Vector2.new(1,suffix=="°"and 0 or .5);unit.Position=UDim2.new(1,0,0,suffix=="°"and 1 or 17)
  local target=math.abs(value-models[service.Selected].default)>1e-6 and 0 or .45
  if reset then
   reset.Position=UDim2.new(1,-16-inset-numberWidth-24*sourceScale-reset.Size.X.Offset/2,0,277)
   if target~=resetAlpha or not animated then
    if animations[resetGlyph]then animations[resetGlyph]:Cancel()end
    resetAlpha=target
    if animated then animate(resetGlyph,.2,{ImageTransparency=1-(1-target)*expansion.Value},Enum.EasingStyle.Quad)else resetGlyph.ImageTransparency=1-(1-target)*expansion.Value end
   end
  else resetAlpha=target end
 end
 service.Ruler=buildRuler(content,{Name="SharedRuler",Skin="Altair",Range=models[1].values,Value=service.value,Step=1,TickStep=1,PrecisionStep=.1,MajorEvery=5,Color=accentFor(1),FutureColor=futureColor(accentFor(1)),MarkerColor=accentFor(1),Scale=sourceScale,Position=UDim2.fromOffset(0,34),Size=UDim2.new(1,0,0,52),CanInteract=function()return service.Expanded and not service.DaylightMode and service.SelectedModel~=nil and allowed()end,
  OnChanged=function(value)
   if not service.Expanded or not allowed()then return end
   local model=models[service.Selected];if not model then return end;readout(value,true);if onValue then onValue(model,value)end
  end,
  OnCommit=function()local model=models[service.Selected];if model then model.active=false end end,
 })
 -- Preserve the reset action and value alignment inside the shared parameter deck.
 reset=body.Reset;resetGlyph=reset:FindFirstChild("ResetGlyph")
 if not resetGlyph then
  resetGlyph=make("ImageLabel",reset,"ResetGlyph",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(26*sourceScale,26*sourceScale),Image=reset.Image,ImageRectOffset=reset.ImageRectOffset,ImageRectSize=reset.ImageRectSize,ScaleType=reset.ScaleType,ImageColor3=Color3.fromRGB(190,190,190),ImageTransparency=.15})
 end
 reset.Image="";reset.AnchorPoint=Vector2.new(.5,.5);reset.Position=UDim2.new(1,-121,0,277);reset.Size=UDim2.fromOffset(53*sourceScale,53*sourceScale);reset.AutoButtonColor=false
 reset.BackgroundColor3=neutral:Lerp(accentFor(1),.12);reset.BackgroundTransparency=0;reset:SetAttribute("AltairThemeIgnore",true)
 local resetCorner=reset:FindFirstChildOfClass("UICorner")or Instance.new("UICorner");resetCorner.CornerRadius=UDim.new(0,9);resetCorner.Parent=reset
 local resetEdge=reset:FindFirstChild("RulerResetOutline")or Instance.new("UIStroke");resetEdge.Name="RulerResetOutline";resetEdge.Color=accentFor(1);resetEdge.Thickness=sourceScale;resetEdge.Transparency=1;resetEdge.Parent=reset
 service.Reset=reset;service.ResetGlyph=resetGlyph
 connect(reset.InputBegan,claimPress)
 connect(reset.MouseEnter,function()if service.Expanded and allowed()then animate(reset,.16,{BackgroundColor3=chipNeutral():Lerp(accentFor(),.25)});animate(resetGlyph,.16,{ImageTransparency=1-expansion.Value});animate(resetEdge,.16,{Transparency=1-.16*expansion.Value})end end)
 connect(reset.MouseLeave,function()if allowed()then animate(reset,.2,{BackgroundColor3=chipNeutral():Lerp(accentFor(),.12)});animate(resetGlyph,.2,{ImageTransparency=1-(1-resetAlpha)*expansion.Value});animate(resetEdge,.2,{Transparency=1})end end)
 local function renderExpansion()
  local progress=math.clamp(expansion.Value,0,1)
  content.GroupTransparency=1-progress*math.clamp(contentReveal.Value,0,1);content.Visible=service.Expanded or progress>0
  content.Position=contentPosition(contentShift.Value,(1-progress)*8)
  reset.Visible=service.ContentMode~="daylight"and(service.Expanded or progress>0);reset.BackgroundTransparency=1-progress
  resetGlyph.ImageTransparency=1-(1-resetAlpha)*progress
 end
 connect(expansion.Changed,renderExpansion)
 connect(contentReveal.Changed,renderExpansion);connect(contentShift.Changed,renderExpansion)
 local function settleContentMotion()
  for _,value in ipairs({contentReveal,contentShift})do if animations[value]then animations[value]:Cancel();animations[value]=nil end end
  contentReveal.Value=1;contentShift.Value=0;renderExpansion()
 end
 body.Sliders.Visible=false;body.PropertiesTitle.Visible=false;body.HeaderDivider.Visible=false;body.PropertiesDivider.Visible=false;body.ActionsDivider.Visible=false
 body.Toggles.Position=UDim2.fromOffset(16,24);body.Toggles.Size=UDim2.fromOffset(126,200)
 local modesLayout=body.Toggles:FindFirstChildOfClass("UIListLayout");if modesLayout then modesLayout.FillDirection=Enum.FillDirection.Vertical;modesLayout.Padding=UDim.new(0,8)end
 local function heading(name,text,x,y,width)local label=make("TextLabel",body,name,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,14),FontFace=Design.Font,TextSize=10,TextColor3=muted,TextXAlignment=Enum.TextXAlignment.Left});return label end
 local modesTitle=heading("ModesTitle","MODES",16,4,126);local tuningTitle=heading("TuningTitle","TUNING",158,4,408)
 for _,row in ipairs(body.Toggles:GetChildren())do if row:IsA("GuiObject")then
  row.Size=UDim2.fromOffset(126,44)
  local icon=row:FindFirstChild("Icon");if icon then icon.Position=UDim2.fromOffset(10,12);icon.Size=UDim2.fromOffset(20,20)end
  local title=row:FindFirstChild("Title");if title then title.Position=UDim2.fromOffset(39,7);title.Size=UDim2.fromOffset(80,16);title.TextSize=11 end
  local subtitle=row:FindFirstChild("Subtitle");if subtitle then subtitle.Position=UDim2.fromOffset(39,24);subtitle.Size=UDim2.fromOffset(80,12);subtitle.TextSize=9 end
  local hit=row:FindFirstChild("Interact");if hit then hit.Size=UDim2.fromScale(1,1)end
 end end
 body.ActionsTitle.Text="SESSION";body.ActionsTitle.Position=UDim2.fromOffset(158,108);body.ActionsTitle.Size=UDim2.fromOffset(408,14);body.ActionsTitle.TextSize=10
 body.Grid.Position=UDim2.fromOffset(158,130);body.Grid.Size=UDim2.fromOffset(408,80)
 local grid=body.Grid:FindFirstChildOfClass("UIGridLayout");if grid then grid.CellSize=UDim2.fromOffset(96,36);grid.CellPadding=UDim2.fromOffset(8,8);grid.FillDirectionMaxCells=4 end
 local function sessionButton(row,width,height)
  width,height=width or 96,height or 36
  row.Size=UDim2.fromOffset(width,height);local hit=row:FindFirstChild("Interact");if hit then hit.Size=UDim2.fromScale(1,1)end
  local icon=row:FindFirstChild("Icon");if icon then icon.Position=UDim2.fromOffset(9,(height-14)/2);icon.Size=UDim2.fromOffset(14,14)end
  local title=row:FindFirstChild("Title");if title then title.Position=UDim2.fromOffset(29,0);title.Size=UDim2.new(1,-34,1,0);title.TextSize=10;title.TextTruncate=Enum.TextTruncate.AtEnd end
 end
 for _,row in ipairs(body.Grid:GetChildren())do if row:IsA("GuiObject")then sessionButton(row)end end
 for index,name in ipairs({"Rejoin","Serverhop"})do
  local button=body[name];local position=UDim2.fromOffset(158+(index-1)*208,216)
  button.Position=position;sessionButton(button,200,26)
  for _,attribute in ipairs({"AltairHoverRestPosition","AltairDeckRest","AltairContentRestPosition"})do if button:GetAttribute(attribute)~=nil then button:SetAttribute(attribute,position)end end
 end
 function service:GetSize()return UDim2.fromOffset(582,self.Expanded and(self.ContentMode=="daylight"and 448 or 408)or 304)end
 local function layout(animated)
  local expanded=service.Expanded
  local targets={
   {panel,{Size=service:GetSize()}},
   {content,{Size=UDim2.fromOffset(550,service.ContentMode=="daylight"and 138 or 86)}},
   {expansion,{Value=expanded and 1 or 0}},
  }
  panel:SetAttribute("AltairRulerExpanded",expanded);deck:SetAttribute("Expanded",expanded)
  if expanded then content.Visible=true;reset.Visible=service.ContentMode~="daylight"end
  for _,target in ipairs(targets)do
   if animated then animate(target[1],.24,target[2],Enum.EasingStyle.Quart)
   else if animations[target[1]]then animations[target[1]]:Cancel()end;for property,value in pairs(target[2])do target[1][property]=value end end
  end
  renderExpansion()
  if onResize then onResize(service:GetSize())end
 end
 function service:Refresh(animated)
  if not self.alive then return end
  sectionTitle.FontFace=font
  for _,chip in ipairs(chips)do chip.FontFace=font end
  local accent=accentFor();self.AccentColor=accent
  local ink=accent;local mutedInk=muted
  if animated then animate(valueHost,.2,{TextColor3=ink},Enum.EasingStyle.Quad);animate(unit,.2,{TextColor3=mutedInk});animate(sectionTitle,.2,{TextColor3=mutedInk});animate(resetGlyph,.2,{ImageColor3=Color3.fromRGB(190,190,190)})
  else valueHost.TextColor3=ink;unit.TextColor3=mutedInk;sectionTitle.TextColor3=mutedInk;resetGlyph.ImageColor3=Color3.fromRGB(190,190,190)end
  reset:SetAttribute("AltairAccentColor",accent)
  if animated then animate(reset,.2,{BackgroundColor3=chipNeutral():Lerp(accent,.12)},Enum.EasingStyle.Quad);animate(resetEdge,.2,{Color=accent},Enum.EasingStyle.Quad)
  else reset.BackgroundColor3=chipNeutral():Lerp(accent,.12);resetEdge.Color=accent;resetEdge.Transparency=1 end
  local model=models[self.Selected];self.SelectedModel=model
  local daylightVisible=self.ContentMode=="daylight"
  valueHost.Visible=not daylightVisible;unit.Visible=not daylightVisible;self.Ruler.Root.Visible=not daylightVisible
  if self.Daylight then self.Daylight.Root.Visible=daylightVisible end
  sectionTitle.Text=daylightVisible and "TIME OF DAY"or(self.Selected and names[self.Selected]or "TUNING")
  sectionTitle.Visible=not daylightVisible
  if model and not self.DaylightMode then
   self.Ruler:Configure({Range=model.values,Value=model.value or model.default,Step=1,TickStep=1,PrecisionStep=.1,MajorEvery=5,Color=accent,FutureColor=futureColor(accent),MarkerColor=accent,Scale=sourceScale,Animate=animated==true})
   readout(model.value or model.default,animated)
  else self.Ruler:Cancel(true)end
  for index,chip in ipairs(chips)do local goal={BackgroundColor3=chipColor(index,index==self.Selected,false),TextColor3=chipInk(index==self.Selected,false)}
   local rim=chip:FindFirstChild("ChipRim");if rim then if animated then animate(rim,.2,{Transparency=index==self.Selected and .72 or .91,Color=accentFor(index)},Enum.EasingStyle.Quad)else rim.Transparency=index==self.Selected and .72 or .91;rim.Color=accentFor(index)end end
   if animated then animate(chip,.2,goal,Enum.EasingStyle.Quad)else if animations[chip]then animations[chip]:Cancel()end;for key,value in pairs(goal)do chip[key]=value end end
  end
  layout(animated)
  if self.DaylightMode and self.Daylight then self.Daylight:Set(self.DaylightOptions.GetValue(),animated==true)end
 end
 function service:Set(model,value,animated)
  if not self.alive or model~=models[self.Selected]then return end
  -- A model callback can echo the ruler's own value. Keep its current follow tween.
  if allowed()and(not self.Ruler:IsDragging()or math.abs(self.Ruler:GetValue()-value)>1e-6)then self.Ruler:Set(value,animated==true)end
  readout(value,animated)
 end
 function service:Select(index,animated)
  if not self.alive or not models[index]then return end
  claimInteraction()
  if self.Expanded and self.ContentMode=="daylight"and animated~=false then self:SwitchContent("signal",index);return end
  if self.Expanded and self.Selected==index and not self.PendingMode then self:Collapse(animated);return end
  if self.Expanded and self.ContentMode=="signal"then
   self.version+=1;self.PendingMode=nil;self.Ruler:Cancel(true)
   for _,model in ipairs(models)do model.active=false end
   settleContentMotion()
   self.Selected=index;self.SelectedModel=models[index];self.DaylightMode=false
   self:Refresh(animated);return
  end
  self:Cancel();self.version+=1;self.ContentMode="signal";self.DaylightMode=false;self.Selected=index;self.SelectedModel=models[index];self.Expanded=true;self:Refresh(animated)
 end
 function service:KeepExpanded()
  if not self.alive or not self.SelectedModel or self.DaylightMode then return false end
  claimInteraction();self.version+=1;self.PendingMode=nil;self.ContentMode="signal";self.Expanded=true
  settleContentMotion()
  self:Refresh(true);return true
 end
 function service:Collapse(animated)
  if not self.alive or not self.Expanded then return end
  self:Cancel();self.Selected=nil;self.SelectedModel=nil;self.DaylightMode=false;self.Expanded=false;self:Refresh(animated)
 end
 function service:Cancel()
  if not self.alive then return end
  outsidePress=nil
  self.version+=1;self.Ruler:Cancel(true)
  self.PendingMode=nil
  if self.Daylight then self.Daylight:Cancel()end
  for _,model in ipairs(models)do model.active=false end
  for _,t in pairs(animations)do t:Cancel()end;table.clear(animations);settleContentMotion()
 end
 function service:Destroy()
  if not self.alive then return end
  self:Cancel();self.alive=false
  for _,c in ipairs(connections)do c:Disconnect()end;table.clear(connections)
  self.Ruler:Destroy();if self.Daylight then self.Daylight:Destroy()end;if modesTitle.Parent then modesTitle:Destroy()end;if tuningTitle.Parent then tuningTitle:Destroy()end;if deck.Parent then deck:Destroy()end
 end
 connect(panel:GetPropertyChangedSignal("Visible"),function()if not panel.Visible then service:Cancel()end end)
 connect(panel:GetAttributeChangedSignal("AltairClosing"),function()if panel:GetAttribute("AltairClosing")then service:Cancel()end end)
 local input=game:GetService("UserInputService")
 local function inside(object,point)
  local position=object.AbsolutePosition;local size=object.AbsoluteSize
  return point.X>=position.X and point.X<=position.X+size.X and point.Y>=position.Y and point.Y<=position.Y+size.Y
 end
 local function collapseOutside(version,intent,afterRelease)
  local function collapse()
   if service.alive and service.version==version and outsideGeneration==intent and service.Expanded and allowed()and not service.Ruler:IsDragging()and not(service.Daylight and service.Daylight:IsDragging())then service:Collapse(true)end
  end
  -- Let GUI activation claim the latest intent before an outside release folds
  -- the editor; reset and parameter clicks must never race this deferred close.
  if afterRelease then task.delay(0,collapse)else task.defer(collapse)end
 end
 connect(input.InputBegan,function(event)
  if not service.Expanded or not allowed()or service.Ruler:IsDragging()or(service.Daylight and service.Daylight:IsDragging())then return end
  if event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch then return end
  local point=Vector2.new(event.Position.X,event.Position.Y)+root.AbsolutePosition
  if inside(deck,point)or inside(content,point)or reset.Visible and inside(reset,point)then return end
  local version=service.version
  outsidePress={input=event,version=version,intent=outsideGeneration}
 end)
 connect(input.InputEnded,function(event)
  if not service.alive or not outsidePress then return end
  local press=outsidePress;local active=press.input
  if event==active or(active.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseButton1)then
   outsidePress=nil;collapseOutside(press.version,press.intent,true)
  end
 end)
 connect(input.WindowFocusReleased,function()outsidePress=nil end)
 connect(root.Destroying,function()service:Destroy()end)
 function service:AttachDaylight(options)
  if self.Daylight then self.Daylight:Destroy()end;self.DaylightOptions=options
  self.Daylight=buildDaylightDial(content,{Name="Daylight",Value=options.GetValue(),GetValue=options.GetValue,InkSource=panel.Title,Position=UDim2.fromOffset(0,4),Size=UDim2.new(1,0,0,126),CanInteract=function()return self.Expanded and self.DaylightMode and not self.PendingMode and allowed()end,OnChanged=options.OnChanged,OnCommit=options.OnCommit,OnReset=options.OnReset})
  self.Daylight.Root.Visible=false;return self.Daylight
 end
 function service:SelectDaylight(animated)
  if not self.alive or not self.Daylight then return end
  if self.PendingMode=="daylight"then self:Collapse(animated);return end
  if self.Expanded and self.DaylightMode then self:Collapse(animated);return end
  if self.Expanded and animated~=false then self:SwitchContent("daylight");return end
  self:Cancel();self.ContentMode="daylight";self.DaylightMode=true;self.Selected=nil;self.SelectedModel=nil;self.Expanded=true;self:Refresh(animated)
 end
 function service:SwitchContent(mode,index)
  self:Cancel();self.PendingMode=mode;local version=self.version
  animate(contentReveal,.08,{Value=0},Enum.EasingStyle.Quad);animate(contentShift,.08,{Value=-8},Enum.EasingStyle.Quad)
  task.delay(.085,function()
   if not self.alive or self.version~=version or self.PendingMode~=mode then return end
   if not allowed()then self.PendingMode=nil;settleContentMotion();return end
   self.PendingMode=nil;self.ContentMode=mode;self.DaylightMode=mode=="daylight";self.Selected=index;self.SelectedModel=index and models[index]or nil;self.Expanded=true;self:Refresh(true)
   contentReveal.Value=0;contentShift.Value=8
   animate(contentReveal,.18,{Value=1},Enum.EasingStyle.Quart);animate(contentShift,.18,{Value=0},Enum.EasingStyle.Quart)
  end)
 end
 service:Refresh(false);return service
end

-- Experimental section badge and normal Altair color controls.
local experimentalBadge
local function bindTheme(root)
 local records=setmetatable({}, {__mode="k"});local controller={active=false,rainbow=false,color=Color3.fromRGB(91,141,239),strength=.25,lightness=0};local changedConnection
 local rainbowItems=setmetatable({}, {__mode="k"})
 local applying=false;local contrastCache={};local native=game:GetService("TweenService")
 local function skip(object)
  if object:GetAttribute("AltairContrastOutline")then return true end
  local p=object
  while p and p~=root do
   if p:GetAttribute("AltairThemeIgnore")then return true end
   if p:GetAttribute("AltairThemeEditor")then
    if object:IsA("TextLabel")or object:IsA("TextBox")or object:IsA("TextButton")or object:GetAttribute("AltairIcon")then return false end
    return object~=p and not((object:IsA("UIStroke")or object:IsA("UIGradient"))and object.Parent==p)
   end
   p=p.Parent
  end
  return false
 end
 local function role(object,property)
  if object:GetAttribute("AltairDesignRole")=="divider"and property=="BackgroundColor3"then return "stroke"end
  if object:GetAttribute("AltairDesignRole")=="indicator"and property=="BackgroundColor3"then return "stroke"end
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
  local toast=object;while toast and toast~=root do if toast.Name=="Toasts"then return base end;toast=toast.Parent end
  local foreground=role(object,property)
  if foreground=="text"or foreground=="icon"then
   local ancestor=object;while ancestor and ancestor~=root do if ancestor.Name=="GameDetection"then return Color3.new(1,1,1)end;ancestor=ancestor.Parent end
  end
  kind=role(object,property)
  if kind=="text"or kind=="icon"then
   local lightBackground=false;local surface=object
   while surface and surface~=root do
    local material=surface;local reference=surface:FindFirstChild("AltairContrastMaterial")
    if reference and reference:IsA("ObjectValue")and reference.Value then material=reference.Value
    elseif surface:GetAttribute("AltairNotificationCard")then material=surface:FindFirstChild("CardBackground")or surface
    elseif surface:IsA("GuiObject")and surface.BackgroundTransparency>=.7 then material=surface:FindFirstChild("Backdrop")or surface end
    if material:IsA("GuiObject")and(material~=surface or material.BackgroundTransparency<.7)then
     if contrastCache[material]~=nil then lightBackground=contrastCache[material];break end
     local record=records[material];local saved=record and record.BackgroundColor3
     local color=desired(saved and saved.base or material.BackgroundColor3,"background",material,"BackgroundColor3")
     local gradient=material:FindFirstChildOfClass("UIGradient")
     if gradient then
      local gr=records[gradient];local gs=gr and gr.Color
      local sequence=desired(gs and gs.base or gradient.Color,"gradient",gradient,"Color")
      local points=sequence.Keypoints;local multiplier=points[1].Value:Lerp(points[#points].Value,.5)
      color=Color3.new(color.R*multiplier.R,color.G*multiplier.G,color.B*multiplier.B)
     end
     local function linear(c)return c<=.04045 and c/12.92 or((c+.055)/1.055)^2.4 end
     lightBackground=.2126*linear(color.R)+.7152*linear(color.G)+.0722*linear(color.B)>.179
     contrastCache[material]=lightBackground;break
    end
    surface=surface.Parent
   end
   local p=object;local notification=false;local artwork=false
   while p and p~=root do
    if p.Name=="NotificationCapsules"then notification=true end
    if p:GetAttribute("AltairArtworkForeground")then artwork=true end
    p=p.Parent
   end
   if artwork then return base end
   if notification then
    return lightBackground and Color3.new(0,0,0)or Color3.new(1,1,1)
   end
   if lightBackground then local brightness=.2126*base.R+.7152*base.G+.0722*base.B;return brightness>.8 and Color3.fromRGB(22,22,22)or Color3.fromRGB(65,65,65)end
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
  if kind=="multiplier"and object:GetAttribute("AltairSurface")and not controller.active then
   return base:Lerp(Color3.fromRGB(235,238,244),controller.lightness^2*.95)
  end
  return mapped(base,kind)
 end
 local function register(object)
  if records[object]or skip(object)then return end
  local props={}
  if object:IsA("Frame")or object:IsA("CanvasGroup")or object:IsA("GuiObject")and object.BackgroundTransparency<.99 then props.BackgroundColor3=object:GetAttribute("AltairDesignRole")=="indicator"and"stroke"or"background"end
  if object:IsA("UIStroke")then props.Color="stroke"end
  if object:IsA("UIGradient")then props.Color="gradient"end
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then props.TextColor3="text"end
  if (object:IsA("ImageLabel")or object:IsA("ImageButton"))and(object:GetAttribute("AltairIcon")or object.Name:find("Icon")or object.Name=="Shadow"or object.Name=="SoftShadow"or object.Name=="Glow")then props.ImageColor3="stroke"end
  local record={};records[object]=record
  for property,kind in pairs(props)do
   local base=Design.idleBase(root,object,property,object[property]);local saved=object:GetAttribute("AltairThemeDefault_"..property);local previous=object:GetAttribute("AltairTheme_"..property)
   if saved and previous and base==previous then base=saved end
   object:SetAttribute("AltairThemeDefault_"..property,base)
   local item={base=base,kind=kind};record[property]=item
   local category=role(object,property)
   if category~="contentGradient"and category~="strokeMultiplier"and(property=="Color"or property=="BackgroundColor3"or property=="ImageColor3"and object:GetAttribute("AltairIcon"))then
    local saturation,value=0,0
    if typeof(base)=="ColorSequence"then for _,point in ipairs(base.Keypoints)do local _,sat,level=point.Value:ToHSV();saturation=math.max(saturation,sat);value=math.max(value,level)end
    elseif typeof(base)=="Color3"then local _,sat,level=base:ToHSV();saturation,value=sat,level end
    local semantic=object.Name:lower():find("status")or object.Name:lower():find("health")
    if saturation>.12 and not semantic then
     item.rainbowManaged=true
     rainbowItems[object]={property=property,item=item,gradient=typeof(base)=="ColorSequence",stroke=object:IsA("UIStroke")or category=="strokeGradient",value=value}
    end
   end
   item.connection=object:GetPropertyChangedSignal(property):Connect(function()
    local bar=root:FindFirstChild("SmartBar");local handle=root:FindFirstChild("Drag");local pulse=root:GetAttribute("AltairThemePulse")and((bar and(object==bar or object:IsDescendantOf(bar)))or(handle and(object==handle or object:IsDescendantOf(handle))))
    if applying or pulse or(root:GetAttribute("AltairThemeRainbow")and((bar and(object==bar or object:IsDescendantOf(bar)))or(handle and(object==handle or object:IsDescendantOf(handle)))))or not(controller.enabled or controller.transitioning or(controller.rainbowActive and item.rainbowManaged))or not object.Parent or skip(object)then return end
    if item.display and(kind~="text"or item.target~=item.base)then
     local color=Design.idleColor(root,object,property,item.display)
     if object[property]~=color then applying=true;object[property]=color;applying=false end
    end
   end)
  end
 end
 function controller:Rainbow(hue)
  if hue==nil then
   if self.rainbowActive then self.rainbowActive=false;self:Apply()end
   return
  end
  self.rainbowActive=true
  local sequences={};local light=self.lightness>.65
  applying=true
  for object,entry in pairs(rainbowItems)do
   local visual=object:IsA("UIGradient")and object.Parent or object
   if object.Parent and not opacityOffscreen(visual)then
    local value=entry.stroke and .85 or math.clamp(math.floor(entry.value*20+.5)/20,.15,.65)
    local saturation=entry.stroke and .65 or .58
    if light and not entry.stroke then value=.92;saturation=.18 end
    local result
    if entry.gradient then
     local key=tostring(value)..":"..tostring(saturation)
     result=sequences[key]
     if not result then
      result=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHSV((hue-.04)%1,saturation,light and value or value*.78)),ColorSequenceKeypoint.new(.5,Color3.fromHSV(hue%1,saturation,value)),ColorSequenceKeypoint.new(1,Color3.fromHSV((hue+.05)%1,saturation*.85,light and value or value*.68))})
      sequences[key]=result
     end
    else result=Color3.fromHSV(hue%1,saturation,value)end
    entry.item.display=result
    local color=Design.idleColor(root,object,entry.property,result)
    if object[entry.property]~=color then object[entry.property]=color end
   end
  end
  applying=false
 end
 local function sequenceAt(points,time)
  for index=2,#points do local a,b=points[index-1],points[index]
   if time<=b.Time then return a.Value:Lerp(b.Value,(time-a.Time)/math.max(.000001,b.Time-a.Time))end
  end
  return points[#points].Value
 end
 local function sequenceStops(from,target)
  local a,b=from.Keypoints,target.Keypoints;local times,seen={},{}
  for _,points in ipairs({a,b})do for _,point in ipairs(points)do if not seen[point.Time]then seen[point.Time]=true;times[#times+1]=point.Time end end end
  table.sort(times);local stops={}
  for _,time in ipairs(times)do stops[#stops+1]={time=time,from=sequenceAt(a,time),target=sequenceAt(b,time)}end
  -- Native sequences allow twenty points. Only disparate maximum-size external
  -- ramps need reduction; authored Altair ramps retain their exact union.
  while #stops>20 do
   local chosen,smallest=2,math.huge
   for index=2,#stops-1 do local left,point,right=stops[index-1],stops[index],stops[index+1];local t=(point.time-left.time)/(right.time-left.time)
    local function error(value,estimate)return(value.R-estimate.R)^2+(value.G-estimate.G)^2+(value.B-estimate.B)^2 end
    local loss=math.max(error(point.from,left.from:Lerp(right.from,t)),error(point.target,left.target:Lerp(right.target,t)))
    if loss<smallest then chosen,smallest=index,loss end
   end
   table.remove(stops,chosen)
  end
  return stops
 end
 function controller:Apply(config)
  if config then
   local signature={color=config.color or Color3.fromRGB(91,141,239),custom=config.custom==true,strength=math.clamp(config.strength or .25,0,1),lightness=math.clamp(config.lightness or 0,0,1)}
   local previous=self.requestedConfig
   if previous and previous.color==signature.color and previous.custom==signature.custom and previous.strength==signature.strength and previous.lightness==signature.lightness then return end
   self.requestedConfig=signature
  end
  self.requestGeneration=(self.requestGeneration or 0)+1
  local requestGeneration=self.requestGeneration
  self.applyGeneration=(self.applyGeneration or 0)+1;local generation=self.applyGeneration
  if self.animation then self.animation:Cancel();self.animation=nil end
  table.clear(contrastCache)
  if config then self.color=config.color or Color3.fromRGB(91,141,239);self.active=config.custom==true;self.strength=math.clamp(config.strength or .25,0,1);self.lightness=math.clamp(config.lightness or 0,0,1);self.active=config.custom==true and self.strength>0 end
  self.color=self.color or Color3.fromRGB(91,141,239);self.lightness=self.lightness or 0;self.strength=self.strength or .25
  if requestGeneration~=self.requestGeneration or self.destroyed then return end
  self.enabled=self.active or self.lightness>0
  root:SetAttribute("AltairThemeEnabled",self.enabled)
  local transitions={}
  local budget=os.clock();local visited=0
  for object,record in pairs(records)do if object.Parent and not skip(object)then for property,item in pairs(record)do
   item.target=desired(item.base,item.kind,object,property);object:SetAttribute("AltairTheme_"..property,self.enabled and item.target or nil)
   local current=Design.idleBase(root,object,property,object[property])
   if current~=item.target then
    if opacityOffscreen(object)then applying=true;item.display=item.target;object[property]=Design.idleColor(root,object,property,item.target);applying=false
    else
     local entry={object=object,property=property,item=item,from=current,to=item.target}
     if typeof(entry.from)=="ColorSequence"then entry.stops=sequenceStops(entry.from,entry.to)end
     transitions[#transitions+1]=entry
    end
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
     local points={};for _,stop in ipairs(entry.stops)do points[#points+1]=ColorSequenceKeypoint.new(stop.time,stop.from:Lerp(stop.target,alpha))end
     value=ColorSequence.new(points)
    else value=entry.from:Lerp(entry.to,alpha)end
    entry.item.display=value;entry.object[entry.property]=Design.idleColor(root,entry.object,entry.property,value)
   end end
   applying=false
  end)
  self.animation=native:Create(progress,TweenInfo.new(root:GetAttribute("AltairReduceMotion")and .05 or .34,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Value=1})
  local animation=self.animation
  animation.Completed:Once(function(state)
   connection:Disconnect();progress:Destroy()
   if state==Enum.PlaybackState.Completed and self.animation==animation then
    self.transitioning=false;applying=true
    for _,entry in ipairs(transitions)do if entry.object.Parent then entry.item.display=entry.to;entry.object[entry.property]=Design.idleColor(root,entry.object,entry.property,entry.to)end end
    applying=false
   end
  end);animation:Play()
 end
 local at=os.clock()
 for index,object in ipairs(root:GetDescendants())do
  register(object)
  if index%24==0 and os.clock()-at>.0015 then game:GetService("RunService").Heartbeat:Wait();at=os.clock()end
 end
 local pending=false;local additions={}
 local c=root.DescendantAdded:Connect(function(object)
  additions[#additions+1]=object
  if pending then return end;pending=true;controller.pending=true
  task.defer(function()
   local index=1;local workAt=os.clock();table.clear(contrastCache)
   while index<=#additions and root.Parent and not controller.destroyed do
    local object=additions[index];index+=1
    if object.Parent then
     register(object);local record=records[object]
     applying=true
     if record and not skip(object)then for property,item in pairs(record)do
      local value=desired(item.base,item.kind,object,property);item.target=value;item.display=value
      object:SetAttribute("AltairTheme_"..property,controller.enabled and value or nil)
      local color=Design.idleColor(root,object,property,value)
      if object[property]~=color then object[property]=color end
     end end
     applying=false
    end
    if os.clock()-workAt>.0015 then game:GetService("RunService").Heartbeat:Wait();workAt=os.clock()end
   end
   table.clear(additions);pending=false;controller.pending=false
  end)
 end)
 function controller:Attach(screen)
  for _,object in ipairs(screen:GetDescendants())do register(object)end
 end
 function controller:WhenReady()
  while self.pending and root.Parent and not self.destroyed do game:GetService("RunService").Heartbeat:Wait()end
 end
 root.Destroying:Connect(function()controller.destroyed=true;c:Disconnect();if controller.animation then controller.animation:Cancel()end;for _,record in pairs(records)do for _,item in pairs(record)do item.connection:Disconnect()end end end)
 return controller
end

-- Shared surface material: a single translucent layer, continuous outline.
local function styleSurface(panel)
 local root=panel:FindFirstAncestorOfClass("ScreenGui")
 panel:SetAttribute("AltairSurface",true);panel:SetAttribute("AltairDesignRole","surface")
 if panel:GetAttribute("AltairDesignTransparencyOffset")==nil then panel:SetAttribute("AltairDesignTransparencyOffset",.03)end
 panel.BackgroundColor3=root and root:GetAttribute("AltairOLED")and Color3.new(0,0,0)or Design.Surface;panel.BorderSizePixel=0
 Design.corner(panel,18)
 local border=Design.edge(panel,.86);border.Name=panel.Name=="SharedPanelSurface"and"Outline"or"UIStroke";border.Enabled=true;border:SetAttribute("AltairSurfaceOutline",true)
 local gradient=panel:FindFirstChildOfClass("UIGradient")or Instance.new("UIGradient")
 gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.new(1,1,1)),ColorSequenceKeypoint.new(.55,Color3.fromRGB(244,244,244)),ColorSequenceKeypoint.new(1,Color3.fromRGB(224,224,224))});gradient.Rotation=110;gradient.Offset=Vector2.zero;gradient.Parent=panel
 return panel
end
local function styleHome(content)
 -- A bounded workspace: navigation, a calm session overview and focused directories.
 content:SetAttribute("AltairHomeRedesign",true)
 content.BackgroundTransparency=1
 local view={states={}};local motion=motionService()
 local font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local bold=Font.new(font.Family,Enum.FontWeight.SemiBold)
 local ink=Design.Ink;local mutedInk=Design.Muted
 local function role(object,name)object:SetAttribute("AltairDesignRole",name);object:SetAttribute("AltairDesignManaged",true)end
 local function make(class,name,parent,props)
  local o=Instance.new(class);o.Name=name
  if o:IsA("GuiObject")then o.BorderSizePixel=0;o.BackgroundTransparency=1;o.ZIndex=24 end
  for k,v in pairs(props or {})do o[k]=v end;o.Parent=parent;return o
 end
 local function rect(o,x,y,w,h)o.AnchorPoint=Vector2.zero;o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h)end
 local function corner(o,r)make("UICorner","UICorner",o,{CornerRadius=UDim.new(0,r)})end
 local function text(parent,name,value,x,y,w,h,size,muted)
  local label=make("TextLabel",name,parent,{Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),FontFace=muted and font or bold,TextSize=size or 14,TextColor3=muted and mutedInk or ink,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd});role(label,muted and"muted"or"ink");return label
 end
 local function button(parent,name,value,x,y,w,h)
  local o=make("TextButton",name,parent,{Text="",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),AutoButtonColor=false,BackgroundColor3=Design.Well,BackgroundTransparency=.24});corner(o,9);role(o,"control")
  make("UIStroke","Outline",o,{Color=Design.Edge,Transparency=.9,Thickness=.6,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
  text(o,"Title",value,14,0,w-28,h,13)
  local motion=motionService();local scale=make("UIScale","HoverScale",o,{Scale=1})
  o.MouseEnter:Connect(function()motion:Create(o,TweenInfo.new(.18),{BackgroundTransparency=.05}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1.025}):Play()end)
  o.MouseLeave:Connect(function()motion:Create(o,TweenInfo.new(.2),{BackgroundTransparency=o:GetAttribute("AltairHomeFade_BackgroundTransparency")or .24}):Play();motion:Create(scale,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Scale=1}):Play()end)
  o.MouseButton1Down:Connect(function()motion:Create(scale,TweenInfo.new(.08,Enum.EasingStyle.Quad),{Scale=.975}):Play()end)
  o.MouseButton1Up:Connect(function()motion:Create(scale,TweenInfo.new(.24,Enum.EasingStyle.Back),{Scale=1}):Play()end)
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
  local material=panel
  if panel:IsA("CanvasGroup")then material=make("Frame","Backdrop",panel,{Size=UDim2.fromScale(1,1),ZIndex=panel.ZIndex-1})end
  styleSurface(material);material:SetAttribute("AltairHomeSurface",true)
  material:SetAttribute("AltairHomeGlass",true);material:SetAttribute("AltairDesignTransparencyOffset",.08);role(material,"surface");material.BackgroundColor3=Design.Surface;material.BackgroundTransparency=Design.opacityAlpha(.18,root and root:GetAttribute("AltairPanelTransparency")or .1)
 end
 local function divider(parent,name,x,y,w)
  local line=make("Frame",name,parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,1),BackgroundColor3=Design.Edge,BackgroundTransparency=.9});role(line,"divider");return line
 end
 local oldSidebar=content.Sidebar;local oldPages=content.Pages
 local sidebar=make("Frame","NewSidebar",content);rect(sidebar,0,0,1104,66)
 local pages=make("Frame","NewPages",content);rect(pages,0,84,1104,540);pages.ClipsDescendants=true
 text(content,"HomeHeading","Your space.",22,24,226,32,25)
 text(content,"WorkspaceLabel","ALTAIR",24,9,180,13,9,true)
 local sub=text(content,"HomeSubheading","",0,48,120,16,10,true);sub.Visible=false
 for i,name in ipairs({"Home","Games","Friends"})do
  local nav=button(sidebar,name,({Home="Home",Friends="Friends",Games="Library"})[name],282+(i-1)*140,14,128,40)
  accent(nav,({Home="Home",Games="Scripts",Friends="Playerlist"})[name])
  nav.BackgroundTransparency=1;nav.Title.Position=UDim2.fromOffset(44,0);nav.Title.Size=UDim2.fromOffset(78,42)
  local icon=make("ImageLabel","Icon",nav,{Position=UDim2.fromOffset(14,12),Size=UDim2.fromOffset(18,18)})
  applyIcon(icon,({Home="house",Friends="users",Games="gamepad-2"})[name])
 end
 local profile=make("Frame","Profile",sidebar);rect(profile,824,12,170,44)
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
 make("ObjectValue","AltairContrastMaterial",content,{Value=header})
 divider(header,"NavigationDivider",260,18,1).Size=UDim2.fromOffset(1,32)
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
 local hero=section(home,"NowPlaying",0,0,680,306)
 surface(hero)
 hero.ClipsDescendants=true
 local artViewport=make("CanvasGroup","ArtworkViewport",hero,{Position=UDim2.fromScale(0,0),Size=UDim2.fromScale(1,1),ClipsDescendants=true});corner(artViewport,18);artViewport:SetAttribute("AltairThemeIgnore",true)
 local art=make("ImageLabel","Artwork",artViewport,{Size=UDim2.fromScale(1,1),ScaleType=Enum.ScaleType.Crop,ImageTransparency=.08,ZIndex=24})
 local nextArt=art:Clone();nextArt.Name="NextArtwork";nextArt.ImageTransparency=1;nextArt.Parent=artViewport
 local shade=make("Frame","Readability",artViewport,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0,ZIndex=25});shade:SetAttribute("AltairThemeIgnore",true)
 make("UIGradient","ReadabilityGradient",shade,{Rotation=28,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.04),NumberSequenceKeypoint.new(.48,.15),NumberSequenceKeypoint.new(1,.58)})})
 hero:SetAttribute("AltairArtworkForeground",true)
 for _,o in ipairs(hero:GetChildren())do if o:IsA("GuiObject")and o~=art and o~=nextArt and o~=shade then o.ZIndex=26 end end
 content.Parent.Dim.ZIndex=2;content.ZIndex=20;sidebar.ZIndex=40
 text(hero,"Eyebrow","NOW PLAYING",24,23,330,16,10,true).ZIndex=26
 local gameIcon=make("ImageLabel","GameIcon",hero,{Position=UDim2.fromOffset(24,66),Size=UDim2.fromOffset(40,40)});corner(gameIcon,10)
 gameIcon.ZIndex=26
 local gameName=text(hero,"GameName","Loading experience…",78,62,288,74,27)
 gameName.ZIndex=26;gameName.TextWrapped=true;gameName.TextYAlignment=Enum.TextYAlignment.Top;gameName.TextTruncate=Enum.TextTruncate.None
 text(hero,"Creator","",24,165,340,20,13,true).ZIndex=26
 text(hero,"SessionPills","",24,196,340,20,12,true).ZIndex=26
 divider(hero,"SessionDivider",24,222,338)
 local resume=button(home,"Resume","Resume game",24,244,168,40)
 resume:SetAttribute("AltairArtworkForeground",true)
 accent(resume,"Home");resume.BackgroundTransparency=.15
 local library=button(home,"BrowseLibrary","Explore library",204,244,158,40);accent(library,"Scripts");library:SetAttribute("AltairArtworkForeground",true)
 local playing=transplant(oldHome.NowPlaying,hero,"FriendsPlaying",24,136,340,22)
 if playing then playing.BackgroundTransparency=1;for _,o in ipairs(playing:GetChildren())do if o:IsA("GuiObject")then o.Visible=o.Name=="Summary"or o.Name=="ViewFriends" end end;rect(playing.Summary,0,0,340,22);playing.Summary.TextSize=10;rect(playing.ViewFriends,0,0,340,22)end
 -- Keep the existing session model available to tick(), without dashboard cards.
 local status=section(home,"SessionStatus",0,0,1,1);status.Visible=false
 for _,name in ipairs({"Time","Date","Status","Game"})do text(status,name,"",0,0,1,1,11)end
 local server=section(home,"Server",700,0,404,306,"Session overview")
 surface(server);rect(server.Title,24,22,356,24)
 text(server,"PlayerCount","",24,65,160,46,38)
 text(server,"CapacityLabel","PLAYERS IN THIS SERVER",24,114,356,16,9,true)
 divider(server,"SessionDivider",24,145,356)
 for i,name in ipairs({"Ping","Uptime","Region"})do
  local metric=section(server,name,24,158+(i-1)*42,356,34)
  text(metric,"Label",({Ping="Latency",Uptime="Session time",Region="Region"})[name],0,0,124,30,12,true)
  local value=text(metric,"Value","—",132,0,224,30,13);value.TextXAlignment=Enum.TextXAlignment.Right
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
 local recent=listSection(oldHome.RecentlyPlayed,"RecentlyPlayed",0,326,1104,210,"Continue exploring","View all")
 recent.Title.TextSize=17;accent(recent.ViewAll,"Scripts")
 surface(recent);rect(recent.Title,24,16,800,22);rect(recent.ViewAll,994,12,86,28)
 divider(recent,"ShelfDivider",24,49,1056)
 -- Keep the full 140px cards above the native bottom track, not over it.
 local shelf=recent.List;rect(shelf,24,62,1056,144);shelf.AutomaticCanvasSize=Enum.AutomaticSize.X;shelf.ScrollingDirection=Enum.ScrollingDirection.X
 shelf.HorizontalScrollBarInset=Enum.ScrollBarInset.Always
 local layout=shelf:FindFirstChildOfClass("UIListLayout");if layout then layout.FillDirection=Enum.FillDirection.Horizontal;layout.Padding=UDim.new(0,18)end
 shelf.Template:Destroy()
 local tile=make("Frame","Template",shelf,{Size=UDim2.fromOffset(166,140),Visible=false,BackgroundColor3=Design.Raised,BackgroundTransparency=.2});corner(tile,12);role(tile,"inset")
 local tileArt=make("ImageLabel","Icon",tile,{Position=UDim2.fromOffset(6,6),Size=UDim2.fromOffset(154,80),ScaleType=Enum.ScaleType.Crop});corner(tileArt,8)
 text(tile,"Title","",10,94,146,20,13)
 text(tile,"LastPlayed","",10,118,146,14,10,true)
 make("TextButton","Interact",tile,{Text="",Size=UDim2.fromScale(1,1),ZIndex=30})
 local friends=listSection(oldHome.Friends,"Friends",0,0,1,1,"Friends","View all");friends.Visible=false
 local activity=listSection(oldHome.RecentActivity,"RecentActivity",0,0,1,1,"Activity");activity.Visible=false
 -- Compact, responsive card directories replace the previous list/table views.
 local function directoryViewport(list)
  local factor=1;local ancestor=list
  while ancestor and ancestor~=root do local scale=ancestor:FindFirstChildOfClass("UIScale");if scale then factor*=scale.Scale end;ancestor=ancestor.Parent end
  factor=math.max(.001,factor)
  return list.AbsoluteWindowSize/factor,factor
 end
 local function tileFlow(list,kind)
  local old=list:FindFirstChildOfClass("UIListLayout");if old then old:Destroy()end
  local queued=false;local last=0;local rowMotion=setmetatable({},{__mode="k"})
  local observed=setmetatable({},{__mode="k"})
  local queue
  local function arrange()
   if not list.Parent then return end
   local viewport,factor=directoryViewport(list);local width=viewport.X
   if width<1 then return end
   local cols=math.max(1,math.floor((width+12)/(kind=="Games"and 320 or 300)))
   local cell=(width-12*(cols-1))/cols;local height=kind=="Games"and 148 or 124
   local rows={}
   for _,o in ipairs(list:GetChildren())do if o:IsA("GuiObject")and o:GetAttribute("RuntimeEntry")then
    if not observed[o]then
     observed[o]=true;o:GetPropertyChangedSignal("Visible"):Connect(function()if queue then queue()end end);o:GetPropertyChangedSignal("LayoutOrder"):Connect(function()if queue then queue()end end)
    end
    if o.Visible then rows[#rows+1]=o end
   end end
   table.sort(rows,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
   for i,row in ipairs(rows)do
    local position=UDim2.fromOffset(((i-1)%cols)*(cell+12),math.floor((i-1)/cols)*(height+12))
    local size=UDim2.fromOffset(cell,height)
    local visible=position.Y.Offset>=list.CanvasPosition.Y/factor-height and position.Y.Offset<=list.CanvasPosition.Y/factor+viewport.Y+height
    if row:GetAttribute("AltairTilePlaced")and visible then
     if row.Position~=position or row.Size~=size then
      local movement=motion:Create(row,TweenInfo.new(.2,Enum.EasingStyle.Quint),{Position=position,Size=size});rowMotion[row]=movement
      movement.Completed:Once(function()if rowMotion[row]==movement then rowMotion[row]=nil end end);movement:Play()
     end
    else
     local movement=rowMotion[row];if movement then movement:Cancel();rowMotion[row]=nil end
     row.Position=position;row.Size=size;row:SetAttribute("AltairTilePlaced",true)
    end
   end
   local canvasHeight=math.max(0,math.ceil(#rows/cols)*(height+12)-12)
   list.CanvasSize=UDim2.fromOffset(0,canvasHeight);list:SetAttribute("AltairColumns",cols)
  end
  queue=function()
   if queued then return end;queued=true
   task.delay(math.max(0,.04-(os.clock()-last)),function()queued=false;last=os.clock();arrange()end)
  end
  list:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue);list.ChildAdded:Connect(queue)
  list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(queue)
  list.ChildRemoved:Connect(function(row)local movement=rowMotion[row];if movement then movement:Cancel();rowMotion[row]=nil end;observed[row]=nil;queue()end)
  list:GetPropertyChangedSignal("CanvasPosition"):Connect(queue);queue()
 end
 for _,name in ipairs({"Friends","Games"})do
  local old=oldPages[name]
  local page=make("CanvasGroup",name,pages,{Size=UDim2.fromOffset(1104,536),Visible=false});page:SetAttribute("AltairHomePageGroup",true)
  local browser=section(page,"Browser",0,0,1104,536,name=="Friends"and"Friends"or"Library");surface(browser)
  rect(browser.Title,20,18,450,28);browser.Title.TextSize=23
  text(browser,"Subtitle",name=="Friends"and"Find your people. Pick up where they are."or"Saved experiences and recent places, together.",20,51,650,20,12,true).Size=UDim2.new(1,-360,0,20)
  divider(browser,"BrowserDivider",20,78,1064).Size=UDim2.new(1,-40,0,1)
  local search=transplant(old.Browser,browser,"SearchBox",0,0,300,36)
  search.Position=UDim2.new(1,-320,0,20);search.Size=UDim2.fromOffset(300,36);search.BackgroundColor3=Design.Well;search.BackgroundTransparency=.22;search.TextSize=13;search.FontFace=font;role(search,"control")
  local filters=transplant(old.Browser,browser,"Filters",20,88,650,30)
  local index=0;for _,chip in ipairs(filters:GetChildren())do if chip:IsA("GuiButton")then rect(chip,index*112,0,102,30);chip.BackgroundColor3=Design.Well;chip.BackgroundTransparency=.35;role(chip,"control");local t=chip:FindFirstChild("Title");if t then t.TextSize=12;t.FontFace=font end;index+=1 end end
  local list=transplant(old.Browser,browser,"List",20,132,1064,384)
  list.Size=UDim2.new(1,-40,1,-152);list.BackgroundTransparency=1;list.ClipsDescendants=true;list.AutomaticCanvasSize=Enum.AutomaticSize.None;list.ScrollBarThickness=2
  list.VerticalScrollBarInset=Enum.ScrollBarInset.Always
  local padding=list:FindFirstChildOfClass("UIPadding");if padding then padding:Destroy()end
  local oldTemplate=list:FindFirstChild("Template");if oldTemplate then oldTemplate:Destroy()end
  local card=make("Frame","Template",list,{Size=UDim2.fromOffset(340,name=="Games"and 148 or 124),Visible=false,BackgroundColor3=Design.Raised,BackgroundTransparency=.16});corner(card,12);role(card,"inset")
  local outline=make("UIStroke","UIStroke",card,{Color=Design.Edge,Transparency=.9,Thickness=.6})
  make("TextButton","Interact",card,{Text="",Size=UDim2.fromScale(1,1),ZIndex=25})
  if name=="Games"then
   local cover=make("ImageLabel","Icon",card,{Position=UDim2.fromOffset(10,10),Size=UDim2.fromOffset(96,96),ScaleType=Enum.ScaleType.Crop});corner(cover,9);cover:SetAttribute("AltairThemeIgnore",true)
   local title=text(card,"Title","",120,13,206,42,15);title.Size=UDim2.new(1,-132,0,42);title.TextWrapped=true;title.TextYAlignment=Enum.TextYAlignment.Top
   text(card,"Creator","",120,61,206,16,10,true).Size=UDim2.new(1,-132,0,16)
   local played=text(card,"LastPlayed","",120,84,206,14,10,true);played.Size=UDim2.new(1,-132,0,14);played.ZIndex=26
   local play=button(card,"Play","Play",12,112,94,26);accent(play,"Playerlist");play.ZIndex=27
   local favorite=button(card,"Favorite","Save",0,112,84,26);favorite.AnchorPoint=Vector2.new(1,0);favorite.Position=UDim2.new(1,-12,0,112);favorite.ZIndex=27
  else
   card:SetAttribute("AltairFriendTile",true)
   local avatar=make("ImageLabel","Avatar",card,{Position=UDim2.fromOffset(12,14),Size=UDim2.fromOffset(44,44)});corner(avatar,14)
   text(card,"DisplayName","",68,14,120,22,15).Size=UDim2.new(1,-80,0,22)
   text(card,"Username","",68,40,120,16,10,true).Size=UDim2.new(1,-80,0,16)
   local statusDot=make("Frame","StatusDot",card,{Position=UDim2.fromOffset(12,74),Size=UDim2.fromOffset(6,6),BackgroundColor3=Color3.fromRGB(144,154,168),BackgroundTransparency=0});corner(statusDot,3);statusDot:SetAttribute("AltairThemeIgnore",true)
   text(card,"Status","",24,68,116,18,11,true)
   text(card,"Location","",150,69,170,16,10,true).Size=UDim2.new(1,-162,0,16)
   local gameBadge=make("ImageLabel","GameIcon",card,{Visible=false,Position=UDim2.fromOffset(44,46),Size=UDim2.fromOffset(16,16),ZIndex=26});corner(gameBadge,4)
   local join=button(card,"Join","Join",12,94,92,24);accent(join,"Playerlist");join.ZIndex=27
   local more=button(card,"More","Profile",0,94,82,24);more.AnchorPoint=Vector2.new(1,0);more.Position=UDim2.new(1,-12,0,94);more.ZIndex=27
  end
  local states=transplant(old.Browser,browser,"States",20,132,1064,384);states.Size=UDim2.new(1,-40,1,-152)
  tileFlow(list,name)
  local detailsSurface=make("CanvasGroup","DetailsSurface",page,{Position=UDim2.fromOffset(752,0),Size=UDim2.fromOffset(376,536),Visible=false,GroupTransparency=1});surface(detailsSurface)
  text(detailsSurface,"SelectionHeading",name=="Games"and"EXPERIENCE"or"FRIEND",22,22,222,16,10,true)
  divider(detailsSurface,"SelectionDivider",22,51,332)
  local details=make("CanvasGroup","Details",page,{Position=UDim2.fromOffset(774,22),Size=UDim2.fromOffset(332,492),Visible=false,GroupTransparency=1})
  make("ObjectValue","AltairContrastMaterial",details,{Value=detailsSurface.Backdrop})
  local close=button(detailsSurface,"CloseSelection","Back",278,14,78,28)
  local state={page=page,browser=browser,surface=detailsSurface,details=details,generation=0,internal=false};view.states[name]=state
  function view:SetSelection(key,selected,animate)
   local st=self.states[key];if not st then return end;st.generation+=1;local generation=st.generation
   st.details:SetAttribute("AltairDetailVersion",(st.details:GetAttribute("AltairDetailVersion")or 0)+1)
   st.internal=true;st.surface.Visible=true;st.details.Visible=true;st.internal=false
   for _,group in ipairs({st.surface,st.details})do group:SetAttribute("AltairHomeFade_GroupTransparency",selected and 0 or 1);group:SetAttribute("AltairHomePageFade_GroupTransparency",selected and 0 or 1)end
   local duration=animate==false and 0 or .3
   motion:Create(st.browser,TweenInfo.new(duration,Enum.EasingStyle.Quint),{Size=UDim2.fromOffset(selected and 704 or 1104,536)}):Play()
   motion:Create(st.surface,TweenInfo.new(duration,Enum.EasingStyle.Quart),{Position=UDim2.fromOffset(selected and 728 or 752,0),GroupTransparency=selected and 0 or 1}):Play()
   motion:Create(st.details,TweenInfo.new(duration,Enum.EasingStyle.Quart),{Position=UDim2.fromOffset(selected and 750 or 774,22),GroupTransparency=selected and 0 or 1}):Play()
   if not selected then task.delay(duration,function()if st.generation==generation and st.page.Parent then st.internal=true;st.surface.Visible=false;st.details.Visible=false;st.internal=false end end)end
  end
  if name=="Games"then
   local image=make("ImageLabel","Artwork",details,{Position=UDim2.fromOffset(0,36),Size=UDim2.fromOffset(332,166),ScaleType=Enum.ScaleType.Crop});corner(image,12)
   text(details,"Title","",0,220,332,44,22).TextWrapped=true
   text(details,"Creator","",0,270,332,18,12,true)
   button(details,"Play","Play experience",0,310,212,40);button(details,"Favorite","Save",224,310,108,40)
   text(details,"DescriptionTitle","ABOUT THIS EXPERIENCE",0,374,332,18,10,true)
   local desc=text(details,"Description","",0,404,332,86,12,true);desc.TextWrapped=true;desc.TextYAlignment=Enum.TextYAlignment.Top;desc.TextTruncate=Enum.TextTruncate.AtEnd
  else
   local avatar=make("ImageLabel","Avatar",details,{Position=UDim2.fromOffset(0,40),Size=UDim2.fromOffset(64,64)});corner(avatar,32)
   text(details,"DisplayName","",78,42,254,30,21)
   text(details,"Username","",78,78,254,18,12,true)
   local activity=section(details,"Activity",0,144,332,112);activity.BackgroundColor3=Design.Raised;activity.BackgroundTransparency=.2;corner(activity,12);role(activity,"inset")
   local icon=make("ImageLabel","GameIcon",activity,{Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(36,36)});corner(icon,9)
   text(activity,"Status","",60,10,260,16,10,true);text(activity,"GameName","",60,29,260,22,14)
   button(activity,"Join","Join experience",12,64,308,36)
   text(details,"Availability","",0,270,332,18,11,true)
   text(details,"AboutTitle","ABOUT",0,306,332,18,10,true)
   local about=text(details,"About","",0,338,332,86,12,true);about.TextWrapped=true;about.TextYAlignment=Enum.TextYAlignment.Top;about.TextTruncate=Enum.TextTruncate.AtEnd
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
 local shell=Instance.new("Frame");shell.Name="SharedPanelSurface";shell.Visible=false;shell.BorderSizePixel=0;shell.BackgroundColor3=Design.Surface;shell.BackgroundTransparency=.08;shell:SetAttribute("AltairDesignRole","surface");shell:SetAttribute("AltairDesignManaged",true);shell:SetAttribute("AltairDesignTransparencyOffset",.03);shell.Parent=root
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,18);corner.Parent=shell
 local stroke=Instance.new("UIStroke");stroke.Name="Outline";stroke.Color=Design.Edge;stroke.Transparency=.86;stroke.Thickness=.6;stroke.BorderStrokePosition=Enum.BorderStrokePosition.Inner;stroke.Parent=shell
 local gradient=Instance.new("UIGradient");gradient.Name="Material";gradient.Rotation=110;gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(224,224,224));gradient.Parent=shell
 local scale=Instance.new("UIScale");scale.Name="AltairDisplayScale";scale.Parent=shell
end
-- A rounded Gaussian atlas has fully transparent borders: its nine-slice never
-- exposes a rectangular edge. Embedded so no uploaded Roblox asset is required.
local softShadowPNG="iVBORw0KGgoAAAANSUhEUgAAAKAAAACgCAYAAACLz2ctAAAZ9klEQVR42u2de2yUZfbHxduuN0RAC5VbWUopVBC5tSwgWkCKVLDQjQioVQKVKFQxNDEFwVSJuLgEwyUBDVZWwkWRSDRglLACCZEILAQDXgKCUcDIRQgXhfk9z/I58eT9zUynZTrvO9OH5PvvPOec98O5Pe9MrwqFQlc5OfklFwQnB6CTA9DJyQHo5AB0cnIAOjkAnZwcgE4OQCcnB6CTA9DJyQHo5AB0cnIAOjkAnZwcgHFWgwTLxbyeAtgg4HIAOuAckA7AxEN3dYLlYExBAIMIWl2A6QBMIuiiPexrAqIrAdIBGEDwYoXt2gi6ro4U6bxYoUw5EFMdvGiweeG4PsGqDs5oMKYMiKkCXyzQhQPtL0p/TbD02eHAjAXGpIcw1cHzQqdBu0HpRnRTgiTnaRs0mJFgTDkQkxW+cOBVB52GTUC4Gd2CGirdGmfpz5bz5HwNpgYyFhirA9EB6AN4kaC7WYEmYDQyug01Rk3qSPL5cl4jD6C3KCAjwZhSIKYCfJHA80KnYRPImhrdbnQHSjNqVsdKU+fdjg1NFJgCZTgYI4GYtBAmG3yxgqcznUCngRPQmhulG7VALY1aodZxlnxuS3VeOjYImBpIgVFnxpqCGHgIgw6fN+vpchsNvFtVpmtKthHg7lSgtTHKMGpr1M4oE7VXyrpC6c+Sz2/HmRnYIGDeqYC8A9slM94aA4i6LEfLhg7AGsAXKetFA6+JynQCnQAnsAlc2UadjHKM7jLqbNSljtSZM3I4M1tBKlAKkAKjZMYm1YBY02zoAKwFfDrrSY8XDrxmlLeWlL+2ZB77sDsCgIXhbqN7jLob9TTqZZRrlGfUO87K47N7cVZ3zr4bW3KwLQtb22J7S3xpFgFE6RHDZcPAQ5hs8HmznvR44cCzmeRvZJeOZB77sLsZ9QCGvxv1NbrX6D6j+40GGA1Eg+Ik+bwBnHEfZ/bFhlxs6oaNd2Fze3xoEwFE6REjZcPAQxhk+HS/p3s9nfWkx0tT4GVQzrIoc13IND3JRPah9zfKB44CoweNCo2GGT1sVIRGxEnyeQ9zRiFnFmBDPjb1xcae2NwFH7LwKUOBmKZ6RJ0NdW8YqS8MDIRBhi9cyfVmvTvok1qQJQS8HDJJd7JLH7LOQB76UKPhwPEPo1FGo43GGj1u9IRRSZz1BJ89lrNGcfYIbBmKbQOxtQ+2d8eXHAViG3xuTgzCZcNIJTlQECYDfLrkSq8nWU+Gi7aUK8l43em5+pFdBvOAbQYqNnoUECwY44wmGE00esZoktFkozKj5+KkMj5zEmdM5Mxx2DAWm4qxcSg25+NDHj5JRmyPzzKsSDaU3lCX5EBDmAzweUuu9HqS9TKZJjvTQ+Uq8GxGechoJBnnMaOnjEoBwYLxglG50YtGFUbTjWYYzYyzZvDZFZxVztll2FKKbY9h60hsL1Ag5uJjZ3zOVNlQesNwJTmwECYbfFJyW6qsZ0tTV6bLPjT5BfRaxZS7EjLOs0bP8/ArgKLSaJbRbKM5Rv8ymms0L86ay2fP4axZnD0DW8qx7VlsLcH2YnwpwLc++NoV3yUbtlQlOWkg9BPAcNNuOPh0v5dO2bGTYQeV9XrTxD9Agz+Sh/ek0dOUv6k86Jd5+P8EivlGi4wWG71ttNSoyujdOKuKz36bsxZx9lxsmYVtFdg6GdufxJeR+PYAvvZW2bADMWlFjHRfGA7C6qbjlAQwXPbzrlqqg681TXg2/VAPMoItUUOYNEeRPUopb+WUvleMXicbLTRaYvSO0b+NVhitNlpjtNboI6N1cdZHfPYazlrB2e9gy0Jsex1bp2N7Gb6U4FsRvubjew9ikU1sWscAYbgVjS9ZMEilV0+7UnYFvjsJbCb7sbspQ/1YYxRSqmwzP55mfyoP8VXK3nwyj81Ey43eB4iPjdYbfWa00WiT0RdGm+OsL/jsjZy1nrPXYstybFuMrXOwfTq+TMK3sfhaiO/9iMXdxCaTWN2pIJRyfGOYFY2vpdjv0utdMutpt7En82UyAXalGe/PpGhXGI+QIex0OYUyVqnAe8tomdEqHvgnQGCB2GK0zWi70Q6jXUb/NdpttCdO2s1n7uKM7Zy5BRs+w6a12LgMmwXESnyago8l+DycGPQnJl2JUaYnEzb2TMd/jbEfTAkAY4Xvhhjhy2NPVkA5Gs06YxIlayZN/puUtmWUPFsGN/DAtwLBTgD52mi/0bdG3xsdMDoYZx3gs7/lrK85eye2bMW2Ddi6GtuX4MtsfCvH13H4XkQs7iM2sUB4Q1AgDErplb6vIbus25noWtHXdPTAN4QF7hjKUhmrDZsp3qDBryKb2N7rU6P/kHV28OD3GX0HHIeNfjI6YnTU6JjRL3HWMT77CGcd5uzvsGUPtm3D1k+xfRW+LMK3Snwtw/cxxGKIB8KOxK4Vsbyd2DaM0g8mvBQHqfTK0NGUnVZLJrts+ptcD3xjWVfY1cU0psh5ZIz3jD6kz9rEQ7WZZi8ZyD74H4HBwnHc6KTRKaPT6EycJZ97irOOc/YRbDmIbXuxdRu2r8eX9/BtHr5Ow/cJxEJDmEvMsolhS2LaVA0lgSjFfk29kfq+Jmz1W7Db6sCE14s+p0DBV0pPZJv01+iX7JpjJSXsc8raDgXeD2Qfge4UcJw1Omd03uiC0e91pAuccY4zz2CDwPgTNgqIO/Dhc3xaiY/z8Xk6MShVEBYQq17ErgOxbEFsm0TpBxM+FfuZ/bylt7GaeNuwYO3MmqEfzXYRJWcCgX+J3mgBZep9mnmbOb6k+f+G7CLgnSQTnQUGC8YfRheNLinF+5/+7Iuc+Ts2nMWmkwrEg9i+G1824dv7+LoA318iFhOITRGx6kfsOhPLNmoyblyLUpxUAEbKftWVXun7Mtnyd2PXNYiJbzR9z/P875/N/swuej+gXNmVx1dkkO8pb7b/OsFDPkcm0tD59U/DeAHbTmPrMWz/Hl++wrf1+Pouvs8mFs8Tm9HEahCx60YsM1U/GGsprvMs6Hf2i1R6s2mke7NwLWTtMI7mexolaAEPYg3T4xb6p31kkJ+NfjX6jSwj4PkJXTQYBcSz2PwrPhzEp534uAGf3yUGrxGTMmL0CDHLJ4ZdiWmkUuxbFkwUgNGyn0y96Z7SK33fEBavJawfXqQJn08p+oAHspU9m11xHGLiPEGfdT7A4EUC8Ty2n8CXQ/i2C1834HsVsZhFbCYRq2JiJ/2gLsXpaiquSRZMCgBrk/1k6m3HDktK7wP0NGNZwJazhphHM/4+JWkLD+Yb1hvHaO4l610MJd+/iyobnsKnw/i4C5/XE4OlxKSSGE0kZkXEUEpxJ2IsU7HvWTBR2e+aGLJfBi9cdmGNcD9lZBS9zRQWsW+wjlhJU76Z0rSfB/SLgu/3JMl60bLh7wrCX/BxPz5vJgYrickbxGgKMRtFDO8npl2IcUYMWfCaRGTBoGW/HF687Mc6YaQqvRU03IvYia1jMvyK/uiQynznkqjkxlqSz6lMeAifvyIG64jJImJUoUrxSGLZj9jmBCkLJhLA6nq/LJaneTTPw5joSrmMr+RKqorF7OesJ/bSpB9VmS9V4PNCKJnwKD7vJQafE5MqYlRJzEqJ4TBimkeMs2LoBVMCQO/w4d37pakbj06e7FfMu3BlrBnmUGZW0ftsZUf2PZPiiRQpu7GU4xP4/D0x2EpMVhGjOcSsjBgWe7JgJ3VDkhZmL5iwYcSv8qv3fq2ZzqT3y+dV9NG8kFnOa0nzuZz/iLKzg4b8R9YVZ2jaUxE+DeEFfP0V378hFpuIzTJi9Sqxe5pYPkRspRdsT+z1XjDhZdjP8iu3Hm25OL+HaW2w6v0mq+z3Fm+IfMo9qZTeY+zMzifptFub6fg8Ph9TpXgbsVlNrCQLTla94GBifA8xb6tuR3wpw36UXz18yK2H/SJ2Ty7ShzK9TaCPeUVlv3W8KbKT+9KfVOn9I1R//v2hSvFPxGInsVmnsuArxHACMR1KjHsSc7kd0cNIQstwogCMVH718GE39vY7sfZrifabYc8yzdlX1BfT32xQ2e8H1hKn60HpjVSKTxODH1QW3ECsFhO7CmL5GLEdSKz1MBJrGQ4sgLWZfnX5tUvSvmr4eIq7zZdZsNrpbq3q/ST7nVQrl/r2T1YzJ1UWlF5wLTGbRwyfJ6YyjPQl5roM+zINJxLAcNOv7P56cGVkS8SjrA/KuV6yF+7LWbjaaW8PfU99zX6RsuBBYrOVWC0ndrOIZSmxHUqse3h2gt5pOCUArK7/k3tfmX6Hc4X0DKXjn6wV7HWT/d7Edhawdvo7Xg97v0i94HFiso8YfUbMlhDDCmI6lhjLNCz3w9X1gUkHYLTbj3D9n/2FKPv60AgmNru/sl/Ytt+ZfUeVX9to21fYj7CQrS+Tb3UT8Sli8h0xkjL8DjGcQUxLiPEgYh6uD6zuViSpAWzkufvNZiUg/Z/9sR77OtELbPPtJGe/O/sxl++6/J5J4aVzTZfTZzxleAsx+zcxrCSm44ix9IH38Az03XCjVATQu/+T9/7k9uPe0OWfK5P1i/R/9m5zBVt+O+F9zWW8K7/hy/BhYrSNmK0ghtIHyjrmQWIutyLynqB3H5gUANZmAd1CDSCy/ytkY29fJbLvtc1mlbBa9X/7PdPvRcff/2Kgp+H9qg9cTQxnE9OJxLhQ7QNlEGnhx0LazwlYFtD2ZUn7utAwzwBiN/n2d1Tsm78b1fpF93+XHH//i4HuA2Uds5HYvU0s9SAyjJj3UgtpXyZhPwDUNyAyAQ9gSfp46PJrRPYKyf6S1FI1gNiXMO3l+9F6vn6Jto45Sox2qUFkKbGcTmwfJ9YD1CSsb0RSBsDrwgDoXcHYS/E8tvP27d0nuLuUCdguU+0Fu/1dFfvTFge4/zztBpD/N4icJjYHiNUXxK5KTcKTiXERMc8L/fligl7FeAG8LhUA1DvA1grA3gpAWcHMZIv/Lneb9s3f3WEmYPfv8j/vJLybmK0jhvOIqaxiitSVnH4zxrsLrDcA6h3gcxEA3OMAjBnAPREAfM6zC6zXAGY5AAMDYJYD0AHoAHQAOgAdgA5AB6AD0AHoAHQAOgAdgA5AB6AD0AHoAHQAOgAdgA5AB6AD0AHoAHQAOgAdgA5AB6AD0AHoAHQAun8OwJB7ITXZAaz3b0S7V/LjC6B7JT/kvpSUqH/uS0kh97VMvwF0X8sMuS+m+wmg+2J6yP00h1//6v1Pc7gfJ/L3X73/cSL382z+DyDu59lC7gcq/Sq/7gcqQ+4neoNQft1P9Ibcj5T7tX5xP1Iecn+mwY/s5/5MQy0HEfeHauKb/er9H6pxf6rLn97P/amuK1xIuz9WWPvJ1/2xwhoA6P5ca3xLr/tzrVdYht0frK790tn9weo4T8PpnmEkj/+pw/ifW0ofY7f5bzLd2T9Pb/9M/ZeqFB9lISv94KUUg0/6vlP4KqX3S2LxIbF5k1hNJXajiWU+sdXDR7pf068fAIa7FZFhRO8EdRaUXnAS09xs7jbfo9m2ZecrFrCH6IlOqdXMpRSC7xy+HcPXffi+iVi8R2xmE6tJqvfT2U/v/vTwkfDyWxcARirD3hdUw2XBjNCf3xOxfYp9XaiQ6W280ZTQ5bd636DMrGThupkJcD+X8b+oTJjs5ViX3VP4dhhfd+L7J8RiCbGZSazGE7tCYim9X5bn7jdc9rtOPbc6gy9RANY0C3ZiSWqntQdCl9/etVdIE2mqK1mwLuW6aT2X77toyA+rTHiWpj0Zp+OL2H5WZb7D+LgLn9cTg6XEpJIYTSRmRcSwDzHtFKTsV1cAxjKMROsF5X64F1dGQ2iipRS/yPXSfHqeD1i+buXB7KdEHaVZP8PaIllKspTc89h+Al8O4dsufN2A71XEYhaxkdJbTOz6E0u5920TQ/a7NhHZL5EAxpIF7TQm7wnaV4S6srHPp4w8Err8OpGd7KYZvWa0IHT5SzdreCBbKE37aNJ/Zl3xm8qGQQVRwJOs9xu2/4wv+/BtC76uwfcFxGIasRlHrAqJXW9imR36872/tCBkv0QBGEsW1HtBuR3JUaXYvj40nIluPHeb02m4F/IgPqAkbaY538ua4kfK1wmurs4pEC/6DOMlbBDwzmHjCWz+ER/24tNmfPwAnxcSg+nEZDwxGk7MpPTmqFsPvferSfZLKgBrkgX1XlBuR3Qp7sEEN5ieZgxXS7bRfokHsIBS9D5N+SbWE7vpmQ5yZfULl/enyTLnafI1jJfqCEr92QLd79hwFptOYuNP2PwNPnyJT5/gYxU+zyYGU4jJGGI0mJj18JReufXw7v18yX6JBLC6iThSKe7A5Cb9oF0njKDBLiXw0ylB82nGV7KW+JxeaQcZ5Fsu7QXE4zT3ZwDgHDBcAIy60AXOOMeZZ7DhuALvB2zdi+1b8WUdvi3F19fwfQqxGEtsClTf14UYRiq9sU6+SQlgLFkwUilupm5Islme5nKRPkRBOIHSM40mfB7riPdYzK4nc2yjfxIQD1LejigYTwLDaXQmzpLPPcVZAt0RbDmowNuJzZvw4UN8WoKPs/D5eWIg8A0hRrnELFvdeDSrQelNSPZLNICxlmKZiqUfbMfFeVc2+RrCMfQ9ZUyAlezCFlGmVnE/+ilvimwjq+yhqf+OB3+Y7HOEifMYcMRTx/jsI5x1mLO/w5Y92LYNWz/F9lX4sgjfKvG1DN/HeODLI1YdiZ30fTL11rT0JjWANcmCeiqWfjCdC/NMdlgawgL6ndFMfpPYgc2kN3qTjLGMN0TWMT1uoqxtJ9PYB/81K45vafoPAEc8dYDP/pazvubsndiyFds2YOtqbF+CL7PxrRxfx+F7EbHQ8HUiZq2JofR9eur1PfslCsCaluJYIMylzxnMxPcIu6+J9EQVZIo59Etv8TBtNllLM/8ZD3wLWWc7Gcju2f5L878nTtrNZ+7ijO2cuQUbPsOmtdi4DJvn40MlPk3BxxJ8Hk4M+hOTWOC7MSjw+QVgtFKs+0EZSmQyFgg70t/0YtIbxM6rmF5oPBliKk36qwrExZSz5UyT9oF/TJ9lIdgIEF+w8oinvuCzN3LWes5eiy3LsW2xAu9VfJiKT+PxsRifBxGDXsSko4JPJl4ZOnTf53vpTTSA1U3F4fpBGUqaeDJhO5rrLqwZ+rBwHUI5GkWGKKVPKuch2reDX6eJX0hps19btN+dXUHJWwMQH1EG46mP+Ow1nLWCs9/BloXY9jq2Tsf2MnwpwbcifM3H9x7EIpvY6MzXRA0dkfq+a/yCL9EARivF+pWt6iBsxWTXgR1XN7b9/bn3LOQNkNG8C/c0bwVPpYy9zBRpv644l2yziMzzNmuOKha98VQVn/02Zy3i7LnYMgvbKrB1MrY/iS8j8e0BfO2N752Jxd+ITXXwXR8Gvqv9gM9vAKP1g14IdU/YnLVCWxasOfQ+vcgI99OUD6NUjSZ72HXFs6wuynnQM+ivZtHk27L3L6CYF2fN5bPncNYszp6BLeXY9iy2lmB7Mb4U4FsffO2K7+2JRUtio3u+cPAFovT6BWA8ILydnVYLtvuZlB/Jhrn0Rfk8tIfIHrZ82W+GPUVJe4by9gIP/0VAmA4UM+OsGXx2BWeVc3YZtpRi22PYOhLbC/ClH75J1svG9zbEohmxSRr4/AKwNhDq6fg2FqppNNqtVDbsRD/UnZWEgGgnRfuNsIfJKI/SzJewzpjAdPkMzf5kwHguTirjMydxxkTOHIcNY7GpGBuHYrOAl4dPXfBRsl4rYpBGTG7zTLuBhs9PAGsKoV7RNPT0hc1VNmzHC5c5TIXdyRp92JMNJKMMZYVhF7j/IOOMBoTHQ5d/RbQkznqCzx7LWaM4ewS2DMW2gdjaB9u740sOvrVTWa+5p99r6Fm1BBo+vwGMBULviiZcSZZsmE4flKFAlIxov4bYk8a9L018PmsM+9AfpMEfRgYqQiPiJPm8hzmjkDMLsCEfm/piY09slown4GXgY7rKeuFKrnfVEkj4ggBgdRBGujEJlw2lNxQQ2zAZtmc/dheZpBurC5td/s5Dv5esY5v8AWShgcARD8nnDeCM+zizLzbkYlM3bLwLm9vjQxsFnvR64bJepBuOQMIXFABrCqEuyTob3hYBxNb0S5lkko6Us8487Hsocz2ZLnPpuXrHWXl8di/O6s7Zd2NLDrZlYWtbbA8H3m2erBet5AYWviABWBMII2XDcCCm0SfJsNKGB9uO7JLFNNkJAO4Chi51pM6ckcOZ2djQHpvaYqMMF83xIRx4kbJe0sAXNACjQRiuL7ze0xuGA1F6xDvIIAJjSwVkhoIyE7VXyrpC6c+SzxfYMhRwLRV0zbBZerxo4HmznrffCyx8QQQwHISxZMNIIEqPKFmxqcqMAmQ6E2ULBWYryl881UqBJuelK+Ak0zVV2U56vOrAizXrNQja8w4igNVBWBMQb/JkxUYqM2og70ACZl0qTZ2ngWusoNPZ7qZagJcU8AUZwJpCGA3EcDA25CFrKAVMgbMu1FiBpmG71ZPpNHTRwEtq+IIOYDxAjAajAClQCpgNPYDGS/qzb1Gw3azsiQRdyoGXTABGgjASiLHAqIEUKDWYda0bPbDdoOyKBbpYwGuQDM82WQC8UhDDwShA/sUDZqKkz74+CnQpCV6yAhgNQi+I0WDUQIYDMxHynn9tjNBdXU0MrnIABg9EL4yRoIwEZ7wU6bxwtl2dyuClAoCxgBgJxmhQ+qFoNjZIRfBSCcCawFgdkEFQg1SHLpUBrAmIfoNZGxtT7lmlKoBXCmOQlNLPpz4AmGxA1qvnUR8BDAqYLuYOQCcHoJMD0MnJAejkAHRycgA6OQCdnByATg5AJycHoJMD0MnJAejkAHRycgA6OQCdnByATimh/wOEclCZ9VOuVAAAAABJRU5ErkJggg=="
local dragHaloPNG="iVBORw0KGgoAAAANSUhEUgAAAQAAAABACAYAAAD1Xam+AAAEQElEQVR42u3dy0sVYRzGcTO146W8pxlmFygkyQwpEhISo7ILRIuEWmhEdBFbVKvcBAoV2cLa1UqIFkFXhJZBizaBRAWBCzcFQlLQIkiK0zPwDAwHj9vmnPkuPv+Az+995p1xzjsF6XS6AEAy8UcAKAAAFAAACgAABQCAAgBAAQCgAABQAAAoAAAUAAAKAAAFAIACAEABAKAAAFAAuWIZ8hKzTQGwyEE5JLUAFgu+MIvlyCvZck50GSR14S+2yIuseAklyAlLZRjmvFg5JK4Ikrb4CzMWfLioV1hKSq0si3LEWrbcwlxTkbxLIqUQLYPElEASF3500YcLvUJWyiqplCqplpqIWuSUaHbVzrTSGa905mExRMsgUUWQpMVf5JBTkUVf6eGok9XSKE2yVpplnbVErEesRbMK82t2pk3OeLUzr/YMhGWQ8owUJaUEkrL4iyNX/ApfDYKrRIMHIxiWTbJZWqVNtkm7bJcO2YGc0uHs2p1lm7Pd7KxbnH2DZ6HKsxHuCIqTUAL5XACZi7/M278ah97sQWj1kHTKbumWvdIr++WAHJQ+OZThMGIhM5c+Z3bAGfY6025n3OnMWz0DzZ6JGs9I2RIlQAHk8OKv8zZwg8MPrhJd0uOhOSYn5JQMyBk5K+fkvFyIuIhYiWZz3pmddYYDzvSEM+5z5l2egVbPRJNnJDElkI8FkHnPHy7+Wge80dvBnR6CI9Ivp2VIrsg1uS5jckNuyW0ZlzuItXFndcvZjTnLa852yFn3O/sez0KbZ6PJsxKWwGLPBCiAHLn6p3xfV+2HP0HLb5Vdsk+Oy6BckhEPzITcl0l5JI/liTyT5/JCXiKWXjijZ87ssTOcdKYTznjEmQ96BvZ5JrZ6Rho9MxWeobzdBeRrAYRX/1I3eb3v87b4/q/HW8HgSnBZRuWuByUYnFfyWt7KO5mW9/JBPtonxEqYywdnNe3s3jrLV8520lmPOvvTnoUez8YWz0q9Z6c0sgugAHKgAMLt/wq/GFLlBzzrvc3r8j3gSRn29vCePJQpeePh+Syz8kXm5JvMy3f7gVgJc5l3VnPObtZZTjvbKWd9z9kPexb6PBttnpUGz065Zym8DaAAcuD+vzhSAMFWbo3v74Inv3vkqLd/V+WmPJCnvlIEgzIjXz1MP+WX/JYF+WN/ESthLgvO6pezm3eWM872tbN+4OyvehaOejbaPStrPDvlWR4GUgAUACgACoBbAHALQAHwEBA8BKQA+Dcg+DcgBcCLQOBFIAqAV4HBq8AUAD8GAj8GogD4OTD4OTAF8J9KgANBOBCEA0E4EowjwdIcCcaRYBwKyqGgaQ4F5VDQBBQAx4JzLDjHgvNhED4MkubDIHwYhE+D8Wkw8GkwCoByYJGDAgAoAAAUAAAKAAAFAIACAEABAKAAAFAAACgAABQAAAoAAAUAgAIAQAEAoAAAUAAA4uQffH5/SVxnODsAAAAASUVORK5CYII="
local smallShadowPNG="iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAADvklEQVR42u2asUsjQRSHPS9qTEzUKCoGRTiLEEx1FoYDi2AlIhZ2ARHE6rAUrFIJVqkDVhZWgsWBtWAnCIH8AakEG7lG0ojG3G/hWwiLQd3EqJe38DWTmffm/d6bmd3NdtVqta5OpssEMAFMABPABDABTAATwARoD99eyX8lgDe47hdoqxjtCtwN7jsEGuD+/pwYX0aA54J2gusRvaIPgh7c9l76BhqI8WkF8GbcDdwNul+ExYCIikEPUX4L09cVo16IllfEe2S9PnAnsyEREUNiRIyJCTEp4jBJ2xh9hhgTwkYjIT6FAN7ge8heiKzGxDiBzohZkRBJMQdJ2mbpE2dMDBshbPa0WoT3CD5IKQ8TxBSBOYH+FGmxKDJiCTK0pekzx5gpbAxjM9hqEVodfD+lO0IWf4iUWCDIFbEusmJTbMEmbev0yTAmhY04NiP4aJkIzQrgDd4p11Ey55T0PMGsiQ3xW+yKnNgXB7BP2y59NhiTwUYCm6P4eE6Etgrgql5f9hEmOM2adsp5mczuEGBeHIpjcSJO4YS2Q/rkGJPFRhqb0/iIeJaD7ypoNvsBNqcBSnSKif4Sq5T3HkEdiT/iXFyKoihBkbZz+hwxZg8bq9hM4mMEn33MobudAtSXfi879DDrNEG2nAlvk8kCWb4g2LK4EbfiL9zSVqbPBWMK2NjGZhofcXyGmIPvpdBs9oOsyXE2q3lKdouJOyV9Jq4Izgm0Iu7Fo6jCI20V+pQZc4aNHDaX8fEDn1HmEGiXAPVr381+jLJMsWllKd0CATjlfS3uxIN4qjW+nuhzx5giNgrYzOIjhc+YpwrevBc0u/YjZGKWY2uNzStPCV8RSIVMv/aqMuYaG6fY3MHHAj7HmYPvvcCvAO6xN8R6nCMzG5TrEeu4TDbfEny9CHfYuMBmDh8ZfMaZg3ssvqsA3vIPsxvPcPe2whmeZycvsZ4fav6vB2yUsJnHxwo+Z5hD2O8y8Lv7u0ffGKWY5i5ul03rnMxVXljzL11P2Chj8xAf6/icZQ7ukfjm06CZ9R/lCS7BfXyWEj3mTL9hZ2/2usfWJbZz+FrE9wRz8bUPNHP8DfIYm2RNbnJLe8Lufcvx1uz1iK0itvfxlcH3JHMJfoQA7ga4xDl9wI5d4gan2gIBqtgqYfsAX0t1G6EJ8FECdOwS6OhNsKOPwY6+Eer4W2F7GLLHYXshYq/E7KWovRa3P0bsrzH7c9T+HrcPJOwTGftIyj6Tsw8l7VNZ+1jaBDABTAATwAQwAUwAE+Ar8w/lS/oANrvHMwAAAABJRU5ErkJggg=="
local assetEnvironment=type(getgenv)=="function"and getgenv()or nil
local softShadowAssets=assetEnvironment and assetEnvironment.AltairVisualAssetsV1 or {}
if assetEnvironment then assetEnvironment.AltairVisualAssetsV1=softShadowAssets end
local function resolveSoftShadowAsset(kind)
 local drag=kind==true or kind=="drag"
 local key=drag and "DragHalo-1" or kind=="small" and "SmallShadow-1" or "FeatheredShadow-1"
 if softShadowAssets[key] then return softShadowAssets[key] end
 local data=drag and dragHaloPNG or kind=="small" and smallShadowPNG or softShadowPNG
 local register=getcustomasset or getsynasset
 if type(writefile)~="function" or type(register)~="function" then return nil end
 local ok,result=pcall(function()
  local path="Altair/UI/Assets/"..key..".png"
  if type(isfile)=="function"and isfile(path)then return register(path)end
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
experimentalBadge=function(parent)
 local badge=Instance.new("TextLabel");badge.Name="Experimental";badge.Position=UDim2.new(1,-112,0,2);badge.Size=UDim2.fromOffset(112,23);badge.Text="EXPERIMENTAL";badge.TextSize=9;badge.Font=Enum.Font.GothamBold;badge.TextColor3=Color3.fromRGB(242,243,247);badge.BackgroundColor3=Color3.fromRGB(73,57,102);badge.BackgroundTransparency=.2;badge.BorderSizePixel=0;badge.ZIndex=parent.ZIndex+2;badge:SetAttribute("AltairThemeIgnore",true);badge.Parent=parent
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,7);corner.Parent=badge
 local shadow=Instance.new("ImageLabel");shadow.Name="ExperimentalShadow";shadow.BackgroundTransparency=1;shadow.AnchorPoint=Vector2.new(.5,.5);shadow.Position=UDim2.new(1,-56,0,15);shadow.Size=UDim2.fromOffset(148,59);shadow.Image=resolveSoftShadowAsset("small")or "";shadow.ScaleType=Enum.ScaleType.Slice;shadow.SliceCenter=Rect.new(31,31,33,33);shadow.SliceScale=.7;shadow.ImageColor3=Color3.fromRGB(112,84,158);shadow.ImageTransparency=.88;shadow.ZIndex=parent.ZIndex+1;shadow:SetAttribute("AltairThemeIgnore",true);shadow.Parent=parent
 return badge
end
local function buildExperimentalSection(parent,title,description)
 local section=Instance.new("Frame");section.Name=title.."Section";section.Size=UDim2.new(1,-16,0,90);section.BackgroundTransparency=1;section:SetAttribute("AltairExperimentalSection",true);section:SetAttribute("AltairThemeEditor",true);section.Parent=parent
 local label=Instance.new("TextLabel");label.Name="Title";label.BackgroundTransparency=1;label.Position=UDim2.fromOffset(2,12);label.Size=UDim2.new(1,-122,0,25);label.Font=Enum.Font.GothamBold;label.TextSize=18;label.TextColor3=Color3.fromRGB(242,243,247);label.TextXAlignment=Enum.TextXAlignment.Left;label.Text=title;label.Parent=section
 local subtitle=label:Clone();subtitle.Name="Description";subtitle.Position=UDim2.fromOffset(2,43);subtitle.Size=UDim2.new(1,-4,0,40);subtitle.Text=description or "Experimental feature. Bugs are to be expected.";subtitle.TextSize=12;subtitle.Font=Enum.Font.Gotham;subtitle.TextColor3=Color3.fromRGB(177,181,194);subtitle.TextWrapped=true;subtitle.TextYAlignment=Enum.TextYAlignment.Top;subtitle.Parent=section
 experimentalBadge(section)
 return section
end
-- Local preference discovery: bounded recycled rows, no polling or value indexing.
local function buildSettingsSearch(context)
 local panel=context.Panel;local native=game:GetService("TweenService");local inputService=game:GetService("UserInputService")
 local function duration(time)
  local root=panel:FindFirstAncestorOfClass("ScreenGui")
  return root and root:GetAttribute("AltairReduceMotion")==true and math.min(time,.08)or time
 end
 local service={alive=true,Active=false,query="",matches={},entries=context.Entries or{},version=0,navigation=0,selected=1,rows={}}
 local connections={};local animations=setmetatable({},{__mode="k"});local layoutAnimations=setmetatable({},{__mode="k"});local highlight,navigationPage
 local z=panel.ZIndex+12;local font=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local function make(class,parent,name,props)
  local o=Instance.new(class);o.Name=name;if o:IsA("GuiObject")then o.BackgroundTransparency=1;o.BorderSizePixel=0;o.ZIndex=z end
  for k,v in pairs(props or{})do o[k]=v end;o.Parent=parent;return o
 end
 local function round(parent,radius)make("UICorner",parent,"UICorner",{CornerRadius=UDim.new(0,radius)})end
 local function connect(signal,fn)local c=signal:Connect(fn);connections[#connections+1]=c;return c end
 local function animate(object,time,goal)
  local old=animations[object];if old then old:Cancel()end
  local tween=native:Create(object,TweenInfo.new(duration(time),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),goal);animations[object]=tween
  tween.Completed:Once(function()if animations[object]==tween then animations[object]=nil end end);tween:Play();return tween
 end
 local group=make("CanvasGroup",panel,"SettingsSearch",{Size=UDim2.fromScale(1,1),GroupTransparency=0});group:SetAttribute("AltairFadeGroup",true);group:SetAttribute("AltairThemeIgnore",true)
 service.Root=group
 local field=make("Frame",group,"Field",{Position=UDim2.fromOffset(18,62),Size=UDim2.fromOffset(148,32),BackgroundTransparency=.25});round(field,10)
 local edge=make("UIStroke",field,"Outline",{Thickness=.65,Transparency=.85,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 local icon=make("ImageLabel",field,"Icon",{Position=UDim2.fromOffset(9,9),Size=UDim2.fromOffset(14,14)});applyIcon(icon,"search")
 local box=make("TextBox",field,"Input",{Position=UDim2.fromOffset(30,0),Size=UDim2.new(1,-56,1,0),Text="",PlaceholderText="Find a setting",ClearTextOnFocus=false,MultiLine=false,TextSize=11,FontFace=font,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
 local clear=make("ImageButton",field,"Clear",{Position=UDim2.new(1,-25,0,7),Size=UDim2.fromOffset(18,18),ImageTransparency=1,AutoButtonColor=false,Visible=false});applyIcon(clear,"x")
 local results=make("CanvasGroup",group,"Results",{Position=UDim2.fromOffset(184,76),Size=UDim2.new(1,-198,1,-92),Visible=false,GroupTransparency=1,ClipsDescendants=true})
 local scroll=make("ScrollingFrame",results,"List",{Size=UDim2.fromScale(1,1),CanvasSize=UDim2.new(),ScrollBarThickness=3,ScrollBarImageTransparency=.4,ScrollingDirection=Enum.ScrollingDirection.Y,AutomaticCanvasSize=Enum.AutomaticSize.None})
 local empty=make("TextLabel",results,"Empty",{Position=UDim2.fromOffset(18,24),Size=UDim2.new(1,-36,0,80),Text="No settings found.\nTry a shorter name or another keyword.",TextSize=14,FontFace=font,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,Visible=false})
 service.Input=box;service.Results=results;service.Scroll=scroll
 function service:Layout(animated)
  local goals={
   [field]={Position=UDim2.fromOffset(18,62),Size=UDim2.fromOffset(148,32)},
   [results]={Position=UDim2.fromOffset(184,76),Size=UDim2.new(1,-198,1,-92)},
  }
  for object,target in pairs(goals)do
   local old=layoutAnimations[object];if old then old:Cancel()end
   if animated and panel.Visible then local animation=native:Create(object,TweenInfo.new(duration(.28),Enum.EasingStyle.Quart,Enum.EasingDirection.Out),target);layoutAnimations[object]=animation;animation:Play()
   else for property,value in pairs(target)do object[property]=value end end
  end
 end
 local function allowed()return service.alive and panel.Parent and panel.Visible and not panel:GetAttribute("AltairClosing")end
 local function factor()
  local n=1;local object=scroll
  while object and not object:IsA("ScreenGui")do local scale=object:FindFirstChildOfClass("UIScale");if scale then n*=scale.Scale end;object=object.Parent end
  return math.max(.001,n)
 end
 local ink,muted,surface
 local function paint(object,property,value)if object[property]~=value then object[property]=value end end
 local function palette()
  ink=panel.ContentTitle.TextColor3;local dark=ink.R+ink.G+ink.B>1.5
  local material=panel.BackgroundColor3;local gradient=panel:FindFirstChildOfClass("UIGradient")
  if gradient then local color=gradient.Color.Keypoints[#gradient.Color.Keypoints].Value;material=Color3.new(material.R*color.R,material.G*color.G,material.B*color.B)end
  local hue,saturation,brightness=material:ToHSV();surface=Color3.fromHSV(hue,saturation*.8,dark and math.clamp(brightness+.035,.08,.23)or math.clamp(brightness-.04,.78,.95));muted=ink:Lerp(surface,.36)
  paint(field,"BackgroundColor3",surface);paint(edge,"Color",ink);paint(icon,"ImageColor3",muted);paint(box,"TextColor3",ink);paint(box,"PlaceholderColor3",muted);paint(clear,"ImageColor3",muted);paint(empty,"TextColor3",muted);paint(scroll,"ScrollBarImageColor3",muted)
  for _,slot in ipairs(service.rows)do paint(slot.row,"BackgroundColor3",surface);paint(slot.title,"TextColor3",ink);paint(slot.category,"TextColor3",muted);paint(slot.icon,"ImageColor3",muted);paint(slot.outline,"Color",ink)end
 end
 local stride=66
 local function renderRows(animated,selectionMotion)
  local first=math.max(1,math.floor(scroll.CanvasPosition.Y/factor()/stride)+1)
  local count=math.min(14,math.max(4,math.ceil(scroll.AbsoluteSize.Y/factor()/stride)+2))
  for index=1,count do
   local slot=service.rows[index]
   if not slot then
    local row=make("TextButton",scroll,"Match"..index,{Text="",AutoButtonColor=false,Size=UDim2.new(1,-10,0,58),BackgroundTransparency=.52,Selectable=true});round(row,11)
    local outline=make("UIStroke",row,"Outline",{Thickness=.6,Transparency=.92,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
    local title=make("TextLabel",row,"Title",{Position=UDim2.fromOffset(13,8),Size=UDim2.new(1,-44,0,21),TextSize=14,FontFace=font,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
    local category=make("TextLabel",row,"Category",{Position=UDim2.fromOffset(13,32),Size=UDim2.new(1,-44,0,16),TextSize=11,FontFace=font,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
    local arrow=make("ImageLabel",row,"Arrow",{Position=UDim2.new(1,-29,0,21),Size=UDim2.fromOffset(15,15)});applyIcon(arrow,"arrow-up-right")
    slot={row=row,title=title,category=category,icon=arrow,outline=outline};service.rows[index]=slot
    connect(row.Activated,function()if allowed()and service.Active and slot.entry then service:Navigate(slot.entry)end end)
    connect(row.MouseEnter,function()if allowed()and service.Active then animate(row,.15,{BackgroundTransparency=.22});animate(outline,.15,{Transparency=.65})end end)
    connect(row.MouseLeave,function()if service.alive then animate(row,.18,{BackgroundTransparency=.52});animate(outline,.18,{Transparency=.92})end end)
   end
   local number=first+index-1;local entry=service.matches[number];local replaced=slot.entry~=entry;slot.entry=entry;slot.row.Visible=entry~=nil
   if entry then
    slot.row.Position=UDim2.fromOffset(0,(number-1)*stride);slot.title.Text=entry.name
    slot.category.Text=entry.category.name
    local selected=number==service.selected;local alpha=selected and .3 or .52
    if selectionMotion then animate(slot.row,.12,{BackgroundTransparency=alpha})
    elseif replaced or slot.selected~=selected then local old=animations[slot.row];if old then old:Cancel();animations[slot.row]=nil end;slot.row.BackgroundTransparency=alpha end
    slot.selected=selected
    if animated then slot.title.TextTransparency=1;slot.category.TextTransparency=1;animate(slot.title,.18,{TextTransparency=0});animate(slot.category,.18,{TextTransparency=0})end
   end
  end
  for index=count+1,#service.rows do service.rows[index].row.Visible=false;service.rows[index].entry=nil end
  palette()
 end
 local function words(query)local t={};for value in query:lower():gmatch("%S+")do t[#t+1]=value end;return t end
 local function search(query)
  local tokens=words(query);local found={}
  for order,entry in ipairs(service.entries)do if not entry.setting.hidden and not entry.category.hidden and entry.object and entry.object.Parent then
   local score=0;local matches=true
   for _,token in ipairs(tokens)do
    if not entry.haystack:find(token,1,true)then matches=false;break end
    score+=entry.name:lower():find(token,1,true)and 50 or 5
   end
   if matches then if entry.name:lower()==query:lower()then score+=1000 elseif entry.name:lower():sub(1,#query)==query:lower()then score+=200 end;found[#found+1]={entry=entry,score=score,order=order}end
  end end
  table.sort(found,function(a,b)return a.score==b.score and a.order<b.order or a.score>b.score end)
  local entries={};for i,value in ipairs(found)do entries[i]=value.entry end;return entries
 end
 function service:SetEntries(entries)
  self.entries=entries or{}
  for _,entry in ipairs(self.entries)do
   local keywords=entry.keywords or entry.setting.keywords or"";if type(keywords)=="table"then keywords=table.concat(keywords," ")end
   entry.haystack=(entry.name.." "..entry.category.name.." "..tostring(entry.setting.id or"").." "..tostring(entry.setting.description or"").." "..keywords):lower()
  end
  if self.Active then self:SetQuery(self.query)end
 end
 function service:SetQuery(query)
  if not self.alive then return end
  local wasActive=self.Active
  query=tostring(query or"")
  if #query>128 then query=query:sub(1,128);while #query>0 and utf8.len(query)==nil do query=query:sub(1,-2)end end
  self.version+=1;self:CancelNavigation();local version=self.version
  local scrolling=animations[scroll];if scrolling then scrolling:Cancel();animations[scroll]=nil end
  self.query=query:match("^%s*(.-)%s*$");self.Active=self.query~="";self.selected=1
  if box.Text~=query then self.suppress=true;box.Text=query;self.suppress=false end
  if highlight then highlight:Destroy();highlight=nil end
  if self.Active then clear.Visible=true end;animate(clear,.12,{ImageTransparency=self.Active and .1 or 1})
  if self.Active then
   self.matches=search(self.query);self.renderPending=true;results.Interactable=false;scroll.CanvasPosition=Vector2.zero;scroll.CanvasSize=UDim2.fromOffset(0,#self.matches*stride)
   local function mount()
    if not self.alive or self.version~=version or not self.Active then return end
    self.renderPending=false;empty.Visible=#self.matches==0;results.Visible=true;renderRows(false);results.Interactable=true;animate(results,.18,{GroupTransparency=0})
   end
   if wasActive then animate(results,.07,{GroupTransparency=1});task.delay(.075,mount)else mount()end
  else
   self.renderPending=false;self.matches={};results.Interactable=false;animate(results,.12,{GroupTransparency=1})
   task.delay(.13,function()if self.alive and self.version==version and not self.Active then results.Visible=false;clear.Visible=false end end)
  end
  if context.OnSearch and not self.silent then context.OnSearch(self.Active,#self.matches,self.query)end
 end
 function service:Clear(release)
  self:SetQuery("");if release~=false and box:IsFocused()then box:ReleaseFocus()end
 end
 function service:CancelNavigation()
  self.navigation+=1
  if navigationPage then local animation=animations[navigationPage];if animation then animation:Cancel();animations[navigationPage]=nil end;navigationPage=nil end
  if highlight then highlight:Destroy();highlight=nil end
 end
 local function destinationVisible(entry)
  if context.IsSelected and not context.IsSelected(entry)then return false end
  local row=entry.object;local page=row and row.Parent
  if not page or entry.setting.hidden or entry.category.hidden then return false end
  local layout=page.Parent and page.Parent:FindFirstChildOfClass("UIPageLayout")
  if layout and layout.CurrentPage~=page then return false end
  local object=row
  while object do
   if object:IsA("GuiObject")and not object.Visible then return false end
   if object:IsA("ScreenGui")and not object.Enabled then return false end
   object=object.Parent
  end
  return true
 end
 function service:Navigate(entry)
  if not allowed()or not entry or not entry.object or not entry.object.Parent or entry.setting.hidden or entry.category.hidden then return false end
  local destination=entry.object.Parent
  self:Clear(true);self.navigation+=1;local generation=self.navigation
  if context.Navigate then context.Navigate(entry)end
  task.delay(.27,function()
   if not allowed()or generation~=self.navigation or entry.object.Parent~=destination or not destinationVisible(entry)then return end
   local row,page=entry.object,entry.object.Parent
   if page:IsA("ScrollingFrame")then
    local scale=1;local ancestor=page;while ancestor and not ancestor:IsA("ScreenGui")do local s=ancestor:FindFirstChildOfClass("UIScale");if s then scale*=s.Scale end;ancestor=ancestor.Parent end
    -- CanvasPosition and AbsoluteCanvasSize use rendered pixels, including
    -- UIScale. Only the authored 12px inset needs scale conversion.
    local target=page.CanvasPosition.Y+row.AbsolutePosition.Y-page.AbsolutePosition.Y-12*scale
    local maximum=math.max(0,page.AbsoluteCanvasSize.Y-page.AbsoluteWindowSize.Y)
    navigationPage=page;animate(page,.3,{CanvasPosition=Vector2.new(0,math.clamp(target,0,maximum))})
   end
   if highlight then highlight:Destroy()end
   highlight=make("Frame",row,"SearchHighlight",{Size=UDim2.fromScale(1,1),BackgroundColor3=entry.category.color or Color3.fromRGB(120,160,230),BackgroundTransparency=1,ZIndex=row.ZIndex+8});highlight:SetAttribute("AltairThemeIgnore",true);round(highlight,10)
   local rim=make("UIStroke",highlight,"Outline",{Color=entry.category.color or ink,Thickness=1,Transparency=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
   local current=highlight;animate(highlight,.16,{BackgroundTransparency=.9});animate(rim,.16,{Transparency=.25})
   task.delay(.65,function()if current.Parent then animate(current,.45,{BackgroundTransparency=1});animate(rim,.45,{Transparency=1})end end)
   task.delay(1.15,function()if current.Parent then current:Destroy()end;if highlight==current then highlight=nil end end)
  end)
  return true
 end
 function service:Open()
  if not self.alive then return end;group.Visible=true;self.silent=true;self:Clear(false);self.silent=false;animate(group,.18,{GroupTransparency=0});palette()
 end
 function service:Close()
  self.navigation+=1;self:Clear(true);animate(group,.1,{GroupTransparency=1})
 end
 function service:Destroy()
  if not self.alive then return end;self.alive=false;self.version+=1;self.navigation+=1
  for _,c in ipairs(connections)do c:Disconnect()end;for _,t in pairs(animations)do t:Cancel()end;for _,t in pairs(layoutAnimations)do t:Cancel()end
  if highlight then highlight:Destroy();highlight=nil end;if group.Parent then group:Destroy()end
 end
 connect(box:GetPropertyChangedSignal("Text"),function()if not service.suppress and allowed()then service:SetQuery(box.Text)end end)
 connect(box.Focused,function()animate(edge,.15,{Transparency=.5})end);connect(box.FocusLost,function(enter)animate(edge,.18,{Transparency=.85});if enter and service.Active then service:Navigate(service.matches[service.selected])end end)
 connect(box.InputBegan,function(event)
  if event.KeyCode==Enum.KeyCode.Escape then service:Clear(true)
  elseif service.Active and(event.KeyCode==Enum.KeyCode.Down or event.KeyCode==Enum.KeyCode.Up)then
   service.selected=math.clamp(service.selected+(event.KeyCode==Enum.KeyCode.Down and 1 or -1),1,math.max(1,#service.matches))
   if not service.renderPending then
    animate(scroll,.16,{CanvasPosition=Vector2.new(0,math.max(0,(service.selected-2)*stride*factor()))});renderRows(false,true)
   end
  end
 end)
 connect(clear.Activated,function()service:Clear(true)end)
 connect(scroll:GetPropertyChangedSignal("CanvasPosition"),function()if service.Active and not service.renderPending then renderRows(false)end end)
 connect(scroll:GetPropertyChangedSignal("AbsoluteSize"),function()if service.Active and not service.renderPending then renderRows(false)end end)
 connect(panel.ContentTitle:GetPropertyChangedSignal("TextColor3"),palette)
 connect(panel:GetPropertyChangedSignal("BackgroundColor3"),palette)
 local surfaceGradient=panel:FindFirstChildOfClass("UIGradient");if surfaceGradient then connect(surfaceGradient:GetPropertyChangedSignal("Color"),palette)end
 connect(panel:GetAttributeChangedSignal("AltairClosing"),function()if panel:GetAttribute("AltairClosing")then service:Close()end end)
 connect(panel:GetPropertyChangedSignal("Visible"),function()if not panel.Visible then service:Close()end end)
 connect(panel.Destroying,function()service:Destroy()end)
 panel.SettingTypes.Position=UDim2.fromOffset(14,104);panel.SettingTypes.Size=UDim2.new(0,158,1,-120)
 service:Layout(false);service:SetEntries(service.entries);palette();return service
end
local function loadingMask(progress)
 local points={}
 for index=0,12 do
  local x=index/12;local front=.22+.56*progress
  local head=math.exp(-((x-front)/.075)^2)
  local trail=x<=front and .25 or 0
  points[#points+1]=NumberSequenceKeypoint.new(x,1-math.max(trail,head))
 end
 return NumberSequence.new(points)
end
local function bindSoftShadows(root)
 local asset=resolveSoftShadowAsset();local dragAsset=resolveSoftShadowAsset(true);local smallAsset=resolveSoftShadowAsset("small");
 if asset and not softShadowAssets.preloaded then local preload={asset};if dragAsset then preload[#preload+1]=dragAsset end;if smallAsset then preload[#preload+1]=smallAsset end;local ok=pcall(function()game:GetService("ContentProvider"):PreloadAsync(preload)end);softShadowAssets.preloaded=ok end
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
   local authored=image.Parent.Size;local minimum=math.min(authored.X.Offset,authored.Y.Offset)
   local small=smallAsset and minimum>0 and minimum<48
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
  local capsule=source:IsDescendantOf(root.TopCapsules)or source.Parent.Name=="CapsuleActivities"
  local authoredSize=source.Size
  local minimum=math.min(authoredSize.X.Offset,authoredSize.Y.Offset)
  local small=not handle and source.Parent~=root and not source:GetAttribute("AltairSurface")and smallAsset and minimum>0 and minimum<48
  if small then padding=math.min(padding,24)end
  local key=legacy or source
  if records[key]then return end
  records[key]=true;count+=1;local localConnections={};local ancestorConnections={};local shadow
  if asset then
   shadow=Instance.new("ImageLabel");shadow.Name="SoftShadow";shadow:SetAttribute("AltairFeatheredShadow",true);shadow:SetAttribute("AltairShadowFor",source.Name);shadow:SetAttribute("AltairCapsuleShadow",capsule);if source:GetAttribute("ReferenceScriptSearch")then shadow:SetAttribute("AltairThemeIgnore",true)end
   atlas(shadow,small);if handle and dragAsset then shadow.Image=dragAsset;shadow.SliceCenter=Rect.new(64,0,192,64)end
   shadow.AnchorPoint=Vector2.new(.5,.5);shadow.ImageColor3=color;shadow.ImageTransparency=1;shadow.Parent=root
  else
   local ok,value=pcall(Instance.new,"UIShadow");if not ok then return end
   shadow=value;shadow.Name="SoftShadow";shadow.BlurRadius=UDim.new(0,padding/3);shadow.Color=color;shadow.ZIndex=-1;shadow.Parent=source
  end
  local rippleMask
  if handle and asset then
   rippleMask=Instance.new("UIGradient");rippleMask.Name="CapsuleRippleMask";rippleMask:SetAttribute("AltairThemeIgnore",true);rippleMask.Parent=shadow
  end
  local function update()
   if not source.Parent or not shadow.Parent then return end
   if not root.Enabled then if asset then shadow.ImageTransparency=1 else shadow.Transparency=1 end;return end
   local opacity=legacy and (legacy.Visible and math.min(source.Name=="SmartBar"and root:GetAttribute("AltairThemePulse")and .2 or .08,(1-legacy.ImageTransparency)*.45)or 0)or(1-material.BackgroundTransparency)*strength;local current=material
   if handle then
    local loading=root:GetAttribute("AltairLoadingProgress")
    local progress=root:GetAttribute("AltairCapsuleRippleProgress")or 1
    local pulse=progress>0 and progress<1 and math.sin(progress*math.pi)or 0
    local baseline=opacity;opacity=math.max(opacity,pulse*.38)
    if loading~=nil then
     opacity=math.max(opacity,math.clamp((1-material.BackgroundTransparency)*1.58,0,1))
     if rippleMask then rippleMask.Transparency=loadingMask(loading)end
    elseif rippleMask then
     if pulse>.001 then
      local minimum=opacity>0 and math.clamp(baseline/opacity,0,1)or 1
      local points={};local left,right=.5-.65*progress,.5+.65*progress
      for index=0,8 do
       local x=index/8;local front=math.min(1,math.exp(-((x-left)/.08)^2)+math.exp(-((x-right)/.08)^2))
       points[#points+1]=NumberSequenceKeypoint.new(x,1-(minimum+(1-minimum)*front))
      end
      rippleMask.Transparency=NumberSequence.new(points)
     else rippleMask.Transparency=NumberSequence.new(0)end
    end
   end
   while current and current~=root do
    if current:IsA("GuiObject") and not current.Visible then opacity=0;break end
    if current:IsA("CanvasGroup")then opacity*=1-current.GroupTransparency end
    current=current.Parent
   end
   if opacity<.0001 then if asset then shadow.ImageTransparency=1 else shadow.Transparency=1 end;return end
   if asset then
    local position=source.AbsolutePosition-root.AbsolutePosition;local size=source.AbsoluteSize
    local factor=1;local parent=source
    while parent and parent~=root do local component=parent:FindFirstChildOfClass("UIScale");if component then factor*=component.Scale end;parent=parent.Parent end
    shadow.Position=UDim2.fromOffset(position.X+size.X/2,position.Y+size.Y/2);shadow.Size=UDim2.fromOffset(size.X+padding*2*factor,size.Y+padding*2*factor)
    if handle and dragAsset then local vertical=size.Y>size.X;shadow.Rotation=(vertical and 90 or 0)+source.Rotation;shadow.Size=UDim2.fromOffset((vertical and size.Y or size.X)+128*factor,64*factor);shadow.SliceScale=factor else shadow.SliceScale=padding/(small and 24 or 48)*factor end
    shadow.ZIndex=legacy and legacy.ZIndex or math.max(0,source.ZIndex-1);shadow.ImageTransparency=1-opacity
    shadow.ImageColor3=legacy and legacy.ImageColor3 or handle and source.BackgroundColor3 or color
   else shadow.Transparency=1-opacity end
  end
  local queued=false
  local function queueUpdate()if queued then return end;queued=true;task.defer(function()queued=false;update()end)end
  connect(localConnections,root:GetPropertyChangedSignal("Enabled"),queueUpdate)
  if handle then connect(localConnections,root:GetAttributeChangedSignal("AltairCapsuleRippleProgress"),queueUpdate);connect(localConnections,root:GetAttributeChangedSignal("AltairLoadingProgress"),queueUpdate)end
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
  for _,property in ipairs({"AbsolutePosition","AbsoluteSize","Rotation","ZIndex","BackgroundTransparency"})do connect(localConnections,source:GetPropertyChangedSignal(property),capsule and update or queueUpdate)end
  if material~=source then connect(localConnections,material:GetPropertyChangedSignal("BackgroundTransparency"),update)end
  connect(localConnections,source.AncestryChanged,ancestors)
  connect(localConnections,source.Destroying,function()
   for _,c in ipairs(localConnections)do c:Disconnect()end;for _,c in ipairs(ancestorConnections)do c:Disconnect()end
   if shadow.Parent then shadow:Destroy()end
  end)
  connect(localConnections,root.Destroying,function()for _,c in ipairs(localConnections)do c:Disconnect()end;for _,c in ipairs(ancestorConnections)do c:Disconnect()end end)
  ancestors()
 end
 local primary={Character=true,Scripts=true,Playerlist=true,Settings=true,ScriptSearch=true,CustomScriptPrompt=true,GameDetection=true,ModeratorDetectionPrompt=true,Disconnected=true,SecurityPrompt=true,SharedPanelSurface=true}
 local function inspect(object)
  if not object.Parent or object:GetAttribute("AltairFeatheredShadow")then return end
  if (object:IsA("ImageLabel") or object:IsA("ImageButton")) and (object.Name=="Shadow" or object.Name=="Glow")then replaceLegacy(object)
  elseif object:IsA("GuiObject")then
   if object.Parent==root and object:GetAttribute("ReferenceScriptSearch")then addSurface(object,.05,Color3.fromRGB(160,166,180),48,object:FindFirstChild("Backdrop"))
   elseif object.Parent==root and primary[object.Name]and not object:FindFirstChild("Shadow")then addSurface(object,.05,Color3.fromRGB(160,166,180),48,object:FindFirstChild("Backdrop")or object)
   elseif object.Name=="Content"and object.Parent.Name=="Home"and not object:GetAttribute("AltairHomeRedesign")then addSurface(object,.05,Color3.fromRGB(160,166,180),48)
   elseif object==root.Drag.Drag then addSurface(object,.2,object.BackgroundColor3,30)
   elseif object.Name=="Surface" and object.Parent.Name=="TopCapsules"then return
   elseif object.Name~="CapsuleReturnSlot"and(object.Parent.Name=="CapsuleActivities"or(object.Parent.Name=="Pills"and object.Parent.Parent.Name=="Compact"))then
    local restore=object:FindFirstChild("Restore")
    local visual=object:FindFirstChild("Visual")or(restore and restore:FindFirstChild("Visual"))
    addSurface(object,.055,Color3.fromRGB(100,106,121),24,(visual and visual:FindFirstChild("Back"))or object:FindFirstChild("Back"))
   elseif object.Name:match("^Notification_%d+$")then
    local restore=object:FindFirstChild("Restore")
    local visual=object:FindFirstChild("Visual")or(restore and restore:FindFirstChild("Visual"))
    addSurface(object,.07,Color3.fromRGB(75,81,96),24,object:FindFirstChild("CardBackground")or(visual and visual:FindFirstChild("Back")))
   end
  end
 end
 local workAt=os.clock()
 for _,object in ipairs(root:GetDescendants())do
  inspect(object)
  if os.clock()-workAt>.0015 then game:GetService("RunService").Heartbeat:Wait();workAt=os.clock()end
 end
 connect(connections,root.DescendantAdded,function(object)task.defer(function()if root.Parent then inspect(object)end end)end)
 connect(connections,root.Destroying,function()for _,c in ipairs(connections)do c:Disconnect()end end)
 return {mode=asset and "feathered-image" or "native",Count=function()return count end}
end

local function styleSettings(root)
 local panel=root.Settings;local types=panel.SettingTypes
 local medium=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local semibold=Font.new(medium.Family,Enum.FontWeight.SemiBold)
 local function role(object,name)object:SetAttribute("AltairDesignRole",name);object:SetAttribute("AltairDesignManaged",true)end
 panel:SetAttribute("AltairDesignTransparencyOffset",.03);role(panel,"surface")
 if not types:IsA("ScrollingFrame")then
  local scroller=Instance.new("ScrollingFrame");scroller.Name="SettingTypes";scroller.BackgroundTransparency=1;scroller.BorderSizePixel=0;scroller.ZIndex=types.ZIndex;scroller.Visible=types.Visible
  scroller.ScrollingDirection=Enum.ScrollingDirection.Y;scroller.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroller.CanvasSize=UDim2.new();scroller.ScrollBarThickness=2;scroller.ScrollBarImageTransparency=.5
  for _,child in ipairs(types:GetChildren())do child.Parent=scroller end
  types:Destroy();scroller.Parent=panel;types=scroller
 end
 local template=types.Template
	-- Reserve the search field before navigation captures this sidebar's rest layout.
	types.Position=UDim2.fromOffset(14,104);types.Size=UDim2.new(0,158,1,-120);types.ClipsDescendants=true
	local padding=Instance.new("UIPadding");padding.PaddingLeft=UDim.new(0,4);padding.PaddingTop=UDim.new(0,3);padding.PaddingBottom=UDim.new(0,8);padding.Parent=types
	local grid=types.UIGridLayout
	grid.CellSize=UDim2.new(1,-8,0,37);grid.CellPadding=UDim2.fromOffset(0,6)
	grid.HorizontalAlignment=Enum.HorizontalAlignment.Center
	grid.FillDirectionMaxCells=1;grid.SortOrder=Enum.SortOrder.LayoutOrder
	template.UICorner.CornerRadius=UDim.new(0,9)
	template.Title.Position=UDim2.fromOffset(38,8.5);template.Title.Size=UDim2.new(1,-43,0,20)
	template.Title.TextXAlignment=Enum.TextXAlignment.Left;template.Title.TextYAlignment=Enum.TextYAlignment.Center
	template.Title.TextSize=13;template.Title.FontFace=medium;template.Title.TextColor3=Design.Ink;role(template.Title,"ink")
	template.Shadow.Visible=false;template.UIStroke.Thickness=.6;template.UIStroke.Transparency=.9;template.UIStroke.Color=Design.Edge;role(template,"control")
	local description=Instance.new("TextLabel")
	description.Name="Description";description.BackgroundTransparency=1;description.Position=UDim2.fromOffset(47,35)
	description.Size=UDim2.new(1,-59,0,15);description.TextSize=10;description.FontFace=medium
	description.TextColor3=Design.Muted;description.TextXAlignment=Enum.TextXAlignment.Left
	description.TextTruncate=Enum.TextTruncate.AtEnd;description.Text="";description.ZIndex=template.Title.ZIndex;description.Parent=template
 local icon=Instance.new("ImageLabel");icon.Name="CategoryIcon";icon.BackgroundTransparency=1;icon.Position=UDim2.fromOffset(11,9.5);icon.Size=UDim2.fromOffset(18,18);icon.ImageColor3=Design.Ink;icon.ZIndex=template.Title.ZIndex;icon.Parent=template;role(icon,"ink")
 local header=icon:Clone();header.Name="HeaderIcon";header.Position=UDim2.fromOffset(18,15);header.Parent=panel;applyIcon(header,"settings-2")
 panel.Title.AnchorPoint=Vector2.zero;panel.Title.Position=UDim2.fromOffset(50,12);panel.Title.TextXAlignment=Enum.TextXAlignment.Left;panel.Subtitle.Visible=false;panel.Title.TextSize=16;panel.Title.FontFace=semibold;panel.Title.Size=UDim2.fromOffset(122,22);panel.Subtitle.TextSize=11;panel.Subtitle.FontFace=medium;panel.Subtitle.Size=UDim2.fromOffset(122,18);panel.ClipsDescendants=true;role(panel.Title,"ink")
 description.Visible=false
 panel.SettingLists.ClipsDescendants=true
 local pages=panel.SettingLists.UIPageLayout;pages.Animated=true;pages.TweenTime=.24;pages.EasingStyle=Enum.EasingStyle.Quint;pages.EasingDirection=Enum.EasingDirection.Out;pages.Padding=UDim.new(0,14);pages.ScrollWheelInputEnabled=false;pages.TouchInputEnabled=false
 panel.SettingLists.Position=UDim2.fromOffset(184,76);panel.SettingLists.Size=UDim2.new(1,-198,1,-92)
 local divider=Instance.new("Frame");divider.Name="SidebarDivider";divider.Position=UDim2.fromOffset(179,22);divider.Size=UDim2.new(0,1,1,-44);divider.BorderSizePixel=0;divider.BackgroundColor3=Design.Edge;divider.BackgroundTransparency=.9;divider.ZIndex=panel.Title.ZIndex;divider.Parent=panel;role(divider,"divider")
 local title=panel.Title:Clone();title.Name="ContentTitle";title.AnchorPoint=Vector2.zero;title.TextXAlignment=Enum.TextXAlignment.Left;title.Position=UDim2.fromOffset(200,17);title.Size=UDim2.new(1,-224,0,27);title.TextSize=22;title.Text="General";title.Parent=panel
 local subtitle=panel.Subtitle:Clone();subtitle.Name="ContentSubtitle";subtitle.AnchorPoint=Vector2.zero;subtitle.Visible=true;subtitle.TextXAlignment=Enum.TextXAlignment.Left;subtitle.Position=UDim2.fromOffset(200,47);subtitle.Size=UDim2.new(1,-224,0,17);subtitle.TextColor3=Design.Muted;subtitle.TextTruncate=Enum.TextTruncate.AtEnd;subtitle.Parent=panel;role(subtitle,"muted")
 local line=Instance.new("Frame");line.Name="ContentDivider";line.BorderSizePixel=0;line.Position=UDim2.fromOffset(200,69);line.Size=UDim2.new(1,-218,0,1);line.BackgroundColor3=Design.Edge;line.BackgroundTransparency=.9;line.ZIndex=panel.Title.ZIndex;line.Parent=panel;role(line,"divider")
 for _,row in ipairs(panel.SettingLists.Template:GetChildren())do if row:IsA("Frame")and row.Name:find("Template",1,true)then
  row.BackgroundColor3=Design.Raised;row.BackgroundTransparency=.12;role(row,"inset")
  local rounding=row:FindFirstChildOfClass("UICorner");if rounding then rounding.CornerRadius=UDim.new(0,12)end
  local outline=row:FindFirstChildOfClass("UIStroke");if outline then
   outline.Color=Design.Edge;outline.Thickness=.6;outline.Transparency=.9
   -- These are freshly authored templates. Rebase inherited clone metadata
   -- before Theme captures it, so returning from a style restores this rim.
   outline:SetAttribute("AltairThemeDefault_Color",Design.Edge)
   outline:SetAttribute("AltairTheme_Color",Design.Edge)
   outline:SetAttribute("AltairStyleBase_Color",Design.Edge)
  end
  for _,name in ipairs({"Title","Description","LicenseDisplay","Note"})do local text=row:FindFirstChild(name);if text and text:IsA("TextLabel")then text.FontFace=name=="Title"and semibold or medium;text.TextSize=name=="Title"and 13 or name=="Description"and 11 or 9;text.TextColor3=name=="Title"and Design.Ink or Design.Muted;role(text,name=="Title"and"ink"or"muted")end end
 end end
end

local function bindSettingsLayout(context)
 local service={alive=true,active=false,mode="Altair"}
 function service:IsLiteral()return false end
 function service:IsOverview()return false end
 function service:GetRestSize()return UDim2.fromOffset(740,430)end
 function service:Open()return false end
 function service:Back()return false end
 function service:HoverCategory()return false end
 function service:Search()return false end
 local defaultPositions={Title=UDim2.fromOffset(50,12),Subtitle=UDim2.fromOffset(50,35),ContentTitle=UDim2.fromOffset(200,17),ContentSubtitle=UDim2.fromOffset(200,47),SettingLists=UDim2.fromOffset(184,76)}
 function service:GetPosition(name)return defaultPositions[name]end
 function service:SelectCategory()return false end
 function service:Apply(animated)
  if not self.alive then return end
  if context.Search and context.Search.Layout then context.Search:Layout(animated)end
  if context.OnRestSize then context.OnRestSize(self:GetRestSize())end
 end
 function service:Destroy()self.alive=false end
 service:Apply(false);return service
end

-- One dialog vocabulary, with the original action/data nodes kept intact.
-- Runtime owns only the group opacity and pose, never individual text alphas.
local dialogFeedbackBound=setmetatable({},{__mode="k"})
local function dialogFeedback(panel)
 local motion=motionService()
 local function bind(button)
  if not button:IsA("GuiButton")or dialogFeedbackBound[button]then return end
  dialogFeedbackBound[button]=true
  local scale=button:FindFirstChild("DialogFeedback")or Instance.new("UIScale");scale.Name="DialogFeedback";scale.Parent=button
  local rest=button.BackgroundTransparency;local rim=button:FindFirstChildOfClass("UIStroke")
  local imageRest=button:IsA("ImageButton")and button.ImageTransparency
  local function release()
   if not button.Parent then return end
   motion:Create(button,TweenInfo.new(.2,Enum.EasingStyle.Quart),{BackgroundTransparency=rest}):Play()
   if rim then motion:Create(rim,TweenInfo.new(.2),{Transparency=.86}):Play()end
   if imageRest then motion:Create(button,TweenInfo.new(.2,Enum.EasingStyle.Quart),{ImageTransparency=imageRest,Rotation=0}):Play()end
   motion:Create(scale,TweenInfo.new(.23,Enum.EasingStyle.Back),{Scale=1}):Play()
  end
  button.MouseEnter:Connect(function()
   motion:Create(button,TweenInfo.new(.16,Enum.EasingStyle.Quart),{BackgroundTransparency=rest<.99 and math.max(0,rest-.16)or rest}):Play()
   if rim then motion:Create(rim,TweenInfo.new(.16),{Transparency=.65}):Play()end
   if imageRest then motion:Create(button,TweenInfo.new(.16),{ImageTransparency=0,Rotation=button.Name=="Close"and 90 or 0}):Play()end
  end)
  button.MouseLeave:Connect(release)
  button.MouseButton1Down:Connect(function()motion:Create(scale,TweenInfo.new(.09,Enum.EasingStyle.Quad),{Scale=.97}):Play()end)
  button.MouseButton1Up:Connect(function()motion:Create(scale,TweenInfo.new(.23,Enum.EasingStyle.Back),{Scale=1}):Play()end)
 end
 bind(panel);for _,object in ipairs(panel:GetDescendants())do bind(object)end
end
local function dialogAccent(panel,color)
 if typeof(color)~="Color3"then return end
 panel:SetAttribute("AltairDialogAccent",color)
 local badge=panel:FindFirstChild("HeaderBadge");local icon=badge and badge:FindFirstChild("Icon")
 if icon then motionService():Create(icon,TweenInfo.new(.18,Enum.EasingStyle.Quart),{ImageColor3=color}):Play()end
end
local function styleDialogs(root)
 local motion=motionService()
 local ink=Design.Ink;local muted=Design.Muted
 local graphite=Design.Surface;local raised=Design.Raised;local well=Design.Well
 local medium=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local semibold=Font.new(medium.Family,Enum.FontWeight.SemiBold)
 local function make(class,name,parent,props)
  local object=Instance.new(class);object.Name=name
  if object:IsA("GuiObject")then object.BackgroundTransparency=1;object.BorderSizePixel=0;object.ZIndex=parent.ZIndex+1 end
  for key,value in pairs(props or{})do object[key]=value end;object.Parent=parent;return object
 end
 local function rect(object,x,y,w,h)object.AnchorPoint=Vector2.zero;object.Position=UDim2.fromOffset(x,y);object.Size=UDim2.fromOffset(w,h)end
 local function rounded(object,radius)local c=object:FindFirstChildOfClass("UICorner")or Instance.new("UICorner");c.CornerRadius=UDim.new(0,radius);c.Parent=object end
 local function role(object,name)object:SetAttribute("AltairDesignRole",name);object:SetAttribute("AltairDesignManaged",true)end
 local function label(object,size,bold,color)
  object.FontFace=bold and semibold or medium;object.TextSize=size;object.TextColor3=color or ink;object.TextTransparency=0;object.TextStrokeTransparency=1
  object.BackgroundTransparency=1;object.TextXAlignment=Enum.TextXAlignment.Left;object.TextYAlignment=Enum.TextYAlignment.Center;object.TextTruncate=Enum.TextTruncate.AtEnd
  if object.Parent and object.Parent:IsA("GuiObject")then object.ZIndex=math.max(object.ZIndex,object.Parent.ZIndex+1)end
  role(object,color==muted and "muted"or"ink")
 end
 local function plate(parent,name,x,y,w,h)
  local object=make("Frame",name,parent,{BackgroundColor3=well,BackgroundTransparency=.5});rect(object,x,y,w,h);rounded(object,12);role(object,"inset")
  local outline=make("UIStroke","Outline",object,{Color=Design.Edge,Thickness=.6,Transparency=.9,ApplyStrokeMode=Enum.ApplyStrokeMode.Border});outline.BorderStrokePosition=Enum.BorderStrokePosition.Inner
  return object
 end
 local function control(object,primary)
  object.BorderSizePixel=0;object.BackgroundColor3=raised;object.BackgroundTransparency=primary and .08 or .28
  rounded(object,9)
  for _,child in ipairs(object:GetChildren())do if child:IsA("UIGradient")then child:Destroy()end end
  local rim=object:FindFirstChildOfClass("UIStroke")or make("UIStroke","UIStroke",object);rim.Color=Design.Edge;rim.Thickness=.6;rim.Transparency=.86;rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.BorderStrokePosition=Enum.BorderStrokePosition.Inner
  if object:IsA("TextButton")then local alpha=object.BackgroundTransparency;label(object,13,true);object.TextXAlignment=Enum.TextXAlignment.Center;object.BackgroundTransparency=alpha end
  role(object,"control");object:SetAttribute("AltairDesignRestAlpha",object.BackgroundTransparency)
  if object:IsA("GuiButton")then
   object.AutoButtonColor=false
   dialogFeedback(object)
  end
 end
 local function shell(name,width,height,iconName,status,accent)
  local old=root[name];local panel=Instance.new("CanvasGroup")
  for _,key in ipairs({"Name","AnchorPoint","Position","ZIndex","Visible","Active","Rotation"})do panel[key]=old[key]end
  for key,value in pairs(old:GetAttributes())do panel:SetAttribute(key,value)end
  if name=="SecurityPrompt"or name=="Disconnected"or name=="ModeratorDetectionPrompt"then
   panel.Position=UDim2.new(panel.Position.X.Scale,panel.Position.X.Offset,.43,0);panel:SetAttribute("AltairDialogDensity",.84)
  elseif name=="CustomScriptPrompt"then panel:SetAttribute("AltairDialogDensity",.92)end
  panel.Size=UDim2.fromOffset(width,height);panel.BackgroundColor3=graphite;panel.BackgroundTransparency=1;panel.BorderSizePixel=0;panel.GroupTransparency=0;panel.ClipsDescendants=false
  for _,child in ipairs(old:GetChildren())do child.Parent=panel end;old:Destroy();panel.Parent=root
  panel:SetAttribute("AltairDialogManaged",true);panel:SetAttribute("AltairDialogSize",panel.Size);panel:SetAttribute("AltairDialogPosition",panel.Position);panel:SetAttribute("AltairDialogOpacity",.07);panel:SetAttribute("AltairDialogAccent",accent);panel:SetAttribute("AltairDesignTransparencyOffset",.02);role(panel,"surface")
  rounded(panel,18)
  local gradient=panel:FindFirstChildOfClass("UIGradient")or Instance.new("UIGradient");gradient.Name="UIGradient";gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(224,224,224));gradient.Transparency=NumberSequence.new(0);gradient.Rotation=110;gradient.Offset=Vector2.zero;gradient.Parent=panel
  local outline=panel:FindFirstChildOfClass("UIStroke")or make("UIStroke","UIStroke",panel);outline.Color=Design.Edge;outline.Thickness=.6;outline.Transparency=.86;outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;outline.BorderStrokePosition=Enum.BorderStrokePosition.Inner
  local backdrop=make("Frame","Backdrop",panel,{Size=UDim2.fromScale(1,1),BackgroundColor3=graphite,BackgroundTransparency=.07,ZIndex=panel.ZIndex});rounded(backdrop,18);role(backdrop,"surface");backdrop:SetAttribute("AltairSurface",true);backdrop:SetAttribute("AltairDesignTransparencyOffset",.02)
  gradient.Parent=backdrop;outline.Parent=backdrop;panel:SetAttribute("AltairSurface",nil)
  for _,legacy in ipairs({"CircleGradient","TitleGradient","Shadow","Stroke"})do local object=panel:FindFirstChild(legacy);if object then object:Destroy()end end
  local badge=plate(panel,"HeaderBadge",24,22,38,38)
  local icon=make("ImageLabel","Icon",badge,{Position=UDim2.fromOffset(9,9),Size=UDim2.fromOffset(20,20),ImageColor3=accent});applyIcon(icon,iconName);role(icon,"accent")
  local eyebrow=make("TextLabel","Status",panel,{Text=status,Position=UDim2.fromOffset(76,9),Size=UDim2.new(1,-126,0,13)});label(eyebrow,9,true,muted)
  local title=panel:FindFirstChild("Title");if title then rect(title,76,24,width-126,28);label(title,20,true)end
  local divider=make("Frame","HeaderDivider",panel,{Position=UDim2.fromOffset(24,72),Size=UDim2.new(1,-48,0,1),BackgroundColor3=Design.Edge,BackgroundTransparency=.9});role(divider,"divider")
  panel:GetAttributeChangedSignal("AltairDialogAccent"):Connect(function()local color=panel:GetAttribute("AltairDialogAccent");if typeof(color)=="Color3"then motion:Create(icon,TweenInfo.new(.18),{ImageColor3=color}):Play()end end)
  return panel
 end
 local function closeButton(button,width)
  rect(button,width-45,21,24,24);button.AnchorPoint=Vector2.zero;button.BackgroundTransparency=1;button.ImageTransparency=.3;button.ImageColor3=ink;button.AutoButtonColor=false;applyIcon(button,"x");role(button,"ink")
  dialogFeedback(button)
 end
 do
  local panel=shell("SecurityPrompt",520,270,"shield-check","SECURITY REVIEW",Color3.fromRGB(231,166,80))
  rect(panel.Subtitle,24,83,472,34);label(panel.Subtitle,13,false,muted);panel.Subtitle.TextWrapped=true;panel.Subtitle.TextTruncate=Enum.TextTruncate.None
  plate(panel,"LinkWell",24,126,472,58)
  rect(panel.FoundLink,38,138,444,34);label(panel.FoundLink,12,false);panel.FoundLink.TextWrapped=true
  rect(panel.Buttons,24,206,472,40);panel.Buttons.BackgroundTransparency=1
  local layout=panel.Buttons:FindFirstChildOfClass("UIListLayout");layout.FillDirection=Enum.FillDirection.Horizontal;layout.Padding=UDim.new(0,8);layout.HorizontalAlignment=Enum.HorizontalAlignment.Left;layout.VerticalAlignment=Enum.VerticalAlignment.Center
  -- UDim offsets truncate to integers. Round the inset outward so the final
  -- action cannot extend beyond the row after applying the user's UI scale.
  panel.Buttons.Template.Size=UDim2.new(1/3,-6,1,0);control(panel.Buttons.Template)
 end
 do
  local panel=shell("Disconnected",470,222,"wifi-off","SESSION RECOVERY",Color3.fromRGB(231,166,80))
  rect(panel.Content,24,84,422,54);label(panel.Content,13,false,muted);panel.Content.TextWrapped=true;panel.Content.TextTruncate=Enum.TextTruncate.None;panel.Content.TextYAlignment=Enum.TextYAlignment.Top
  rect(panel.Action,314,158,132,40);control(panel.Action,true)
  local dismiss=panel:FindFirstChild("Dismiss")or make("TextButton","Dismiss",panel,{Text="Dismiss"});rect(dismiss,192,158,110,40);control(dismiss)
 end
 do
  local panel=shell("CustomScriptPrompt",340,308,"file-plus-2","YOUR LIBRARY",Color3.fromRGB(100,184,164));panel.Title.Text="Import a script"
  panel.Backdrop.BackgroundTransparency=.02;panel.Backdrop:SetAttribute("AltairDesignTransparencyOffset",-.03);panel:SetAttribute("AltairDesignTransparencyOffset",-.03);panel:SetAttribute("AltairDialogOpacity",.02)
  rect(panel.HeaderBadge,18,15,30,30);rect(panel.HeaderBadge.Icon,7,7,16,16)
  rect(panel.Status,60,11,226,12);rect(panel.Title,60,25,226,24);panel.Title.TextSize=18
  panel.HeaderDivider.Position=UDim2.fromOffset(18,58);panel.HeaderDivider.Size=UDim2.new(1,-36,0,1)
  closeButton(panel.Close,340)
  rect(panel.Subtitle,18,68,304,27);label(panel.Subtitle,12,false,muted);panel.Subtitle.Text="Add a local file or raw script link to your library.";panel.Subtitle.TextWrapped=true
  for _,spec in ipairs({{"IDBox","IDTextBox","EXPERIENCE ID",104,40},{"DescBox","DescTextBox","DESCRIPTION",200,52},{"ScriptBox","ScriptTextBox","SOURCE URL OR LUA FILE",152,40}})do
   local field=panel[spec[1]];field.Visible=true;rect(field,18,spec[4],304,spec[5]);field.BackgroundColor3=well;field.BackgroundTransparency=.24;rounded(field,9);role(field,"inset")
   local rim=field:FindFirstChildOfClass("UIStroke")or make("UIStroke","Outline",field);rim.Color=Design.Edge;rim.Thickness=.6;rim.Transparency=.9
   local heading=make("TextLabel","FieldLabel",field,{Text=spec[3],Position=UDim2.fromOffset(12,5),Size=UDim2.new(1,-24,0,12)});label(heading,8,true,muted)
   local box=field[spec[2]];box.Visible=true;rect(box,12,20,280,spec[5]-23);label(box,12,false);box.ClearTextOnFocus=false;box.TextYAlignment=Enum.TextYAlignment.Top;box.TextTruncate=Enum.TextTruncate.None;box.PlaceholderColor3=muted
   if spec[1]=="DescBox"then box.MultiLine=true;box.TextWrapped=true end
   box.Focused:Connect(function()motion:Create(rim,TweenInfo.new(.16),{Transparency=.48}):Play()end);box.FocusLost:Connect(function()motion:Create(rim,TweenInfo.new(.2),{Transparency=.9}):Play()end)
  end
  rect(panel.Submit,216,266,106,28);control(panel.Submit,true);panel.Submit.Text="Save script"
  local foot=make("TextLabel","FooterNote",panel,{Text="Stored locally in your Altair library",Position=UDim2.fromOffset(18,266),Size=UDim2.fromOffset(184,28)});label(foot,10,false,muted);foot.TextWrapped=true
 end
 do
  local panel=shell("ModeratorDetectionPrompt",470,292,"shield-alert","SERVER NOTICE",Color3.fromRGB(230,153,99));closeButton(panel.Close,470)
  rect(panel.Subtitle,24,82,422,25);label(panel.Subtitle,13,false,muted)
  plate(panel,"PlayerWell",24,116,422,84)
  rect(panel.Avatar,40,131,54,54);panel.Avatar.ImageTransparency=0;panel.Avatar.BackgroundTransparency=.7;rounded(panel.Avatar,16)
  rect(panel.DisplayName,110,130,310,26);label(panel.DisplayName,18,true)
  rect(panel.Rank,110,161,310,18);label(panel.Rank,12,false,muted)
  rect(panel.Serverhop,24,226,250,40);control(panel.Serverhop,true)
  rect(panel.ServersAvailableFade,24,204,422,16);label(panel.ServersAvailableFade,10,false,muted)
  rect(panel.Leave,286,226,160,40);panel.Leave.BackgroundTransparency=1
  rect(panel.Leave.Leave,0,0,160,40);control(panel.Leave.Leave);panel.Leave.Leave.Text="Leave game"
 end
 do
  local panel=shell("GameDetection",460,164,"sparkles","EXPERIENCE SCRIPT",Color3.fromRGB(124,186,203))
  panel.Position=UDim2.new(panel.Position.X.Scale,panel.Position.X.Offset,math.min(panel.Position.Y.Scale,.19),panel.Position.Y.Offset)
  panel:SetAttribute("AltairDialogPosition",panel.Position)
  panel.HeaderBadge.Visible=false;panel.HeaderDivider.Visible=false;panel.Status.Visible=false
  panel:SetAttribute("AltairArtworkForeground",true)
  local viewport=panel:FindFirstChild("ArtworkViewport")
  if viewport then
   rect(viewport,0,0,460,164);viewport.Size=UDim2.fromScale(1,1);rounded(viewport,20);viewport.ClipsDescendants=true;viewport.BackgroundTransparency=1
   viewport:SetAttribute("AltairThemeIgnore",true)
   for _,image in ipairs(viewport:GetChildren())do if image:IsA("ImageLabel")then
    image.AnchorPoint=Vector2.zero;image.Position=UDim2.fromScale(0,0);image.Size=UDim2.fromScale(1,1);image.BackgroundTransparency=1;image.ImageColor3=Color3.new(1,1,1);image.ScaleType=Enum.ScaleType.Crop;image:SetAttribute("AltairThemeIgnore",true)
   end end
  end
  local shade=panel:FindFirstChild("ArtworkShade")or make("Frame","ArtworkShade",panel,{})
  shade.AnchorPoint=Vector2.zero;shade.Position=UDim2.new();shade.Size=UDim2.fromScale(1,1);shade.BackgroundColor3=Color3.new(0,0,0);shade.BackgroundTransparency=.2;shade.ZIndex=panel.ZIndex+1;rounded(shade,20);shade:SetAttribute("AltairThemeIgnore",true)
  local shadeRamp=shade:FindFirstChildOfClass("UIGradient")or make("UIGradient","UIGradient",shade,{})
  shadeRamp.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,.6)});shadeRamp.Rotation=0
  local layer=panel.Layer;layer.Position=UDim2.new();layer.Size=UDim2.fromScale(1,1);layer.BackgroundTransparency=1
  rect(panel.ScriptTitle,24,27,390,25);label(panel.ScriptTitle,17,true,Color3.new(1,1,1))
  rect(layer.ScriptSubtitle,24,59,348,48);label(layer.ScriptSubtitle,12,false,Color3.fromRGB(220,223,230));layer.ScriptSubtitle.TextWrapped=true;layer.ScriptSubtitle.TextTruncate=Enum.TextTruncate.None;layer.ScriptSubtitle.TextYAlignment=Enum.TextYAlignment.Top
  local run=layer.Run;control(run,true);run.AnchorPoint=Vector2.new(1,1);run.Position=UDim2.new(1,-18,1,-16);run.Size=UDim2.fromOffset(96,34);run.Text="Run";run.BackgroundColor3=Color3.fromRGB(45,68,110);run.BackgroundTransparency=.08
  closeButton(layer.Close,460)
  local warning=panel.Warning;warning.Visible=false;warning.BackgroundTransparency=1
  for _,child in ipairs(warning:GetChildren())do if child:IsA("GuiObject")then child.Visible=false end end
 end
 -- Reused containers retain their legacy ZIndex. In Sibling mode a low
 -- container places its entire subtree behind the new Backdrop, regardless
 -- of a text leaf's own ZIndex. Give every content branch its own clear layer.
 for _,name in ipairs({"SecurityPrompt","Disconnected","CustomScriptPrompt","ModeratorDetectionPrompt","GameDetection"})do
  local panel=root[name];panel.Backdrop.ZIndex=panel.ZIndex
  local function layer(object,depth)
   if object:IsA("GuiObject")then object.ZIndex=panel.ZIndex+depth;depth+=1 end
   for _,child in ipairs(object:GetChildren())do layer(child,depth)end
  end
  for _,child in ipairs(panel:GetChildren())do if child~=panel.Backdrop then layer(child,1)end end
  if name=="GameDetection"then
   local viewport=panel:FindFirstChild("ArtworkViewport");if viewport then viewport.ZIndex=panel.ZIndex+1 end
   local shade=panel:FindFirstChild("ArtworkShade");if shade then shade.ZIndex=panel.ZIndex+2 end
   layer(panel.ScriptTitle,3);layer(panel.Layer,3)
  end
 end
end

local function capsulePlacement(context,controller,root,host,scale,compact,surface)
 local input=game:GetService("UserInputService")
 local playerGui=game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
 local state={amount=1,target=1,velocity=0,boxes={},probeAt=0,queries=0,lastNotice=-math.huge}
 local function setting(name,default)
  local value=context.GetSetting and context.GetSetting(name,default)
  return value==nil and default or value
 end
 local function overlap(a,b)
  return a[1]<b[3]+8 and a[3]>b[1]-8 and a[2]<b[4]+8 and a[4]>b[2]-8
 end
 local function box(object)
  if not object.Parent or not object:IsA("GuiObject")or not object.Visible then return end
  local p,s=object.AbsolutePosition-root.AbsolutePosition,object.AbsoluteSize
  if s.X<4 or s.Y<4 then return end
  return {p.X,p.Y,p.X+s.X,p.Y+s.Y}
 end
 local function gameBox(object)
  if not playerGui or not object:IsDescendantOf(playerGui)or object:IsDescendantOf(root)then return end
  local visual=object.BackgroundTransparency<.94
  if object:IsA("ImageLabel")or object:IsA("ImageButton")then visual=visual or(object.Image~=""and object.ImageTransparency<.94)end
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then visual=visual or(object.Text~=""and object.TextTransparency<.94)end
  if not visual then return end
  local b=box(object);if not b then return end
  local parent=object
  while parent and parent~=playerGui do
   if parent:IsA("GuiObject")then
    if not parent.Visible or parent:IsA("CanvasGroup")and parent.GroupTransparency>.94 then return end
    if parent~=object and parent.ClipsDescendants then
     local clip=box(parent);if not clip then return end
     b={math.max(b[1],clip[1]),math.max(b[2],clip[2]),math.min(b[3],clip[3]),math.min(b[4],clip[4])}
    end
   elseif parent:IsA("ScreenGui")and not parent.Enabled then return end
   parent=parent.Parent
  end
  if b[3]-b[1]<3 or b[4]-b[2]<3 then return end
  if (b[3]-b[1])*(b[4]-b[2])>root.AbsoluteSize.X*root.AbsoluteSize.Y*.45 then return end
  return b
 end
 local function probe(rect,now)
  if now<state.probeAt or not playerGui then return end
  state.probeAt=now+.4
  local started=os.clock();local seen={}
  for _,record in ipairs(state.boxes)do seen[record.object]=record end
  -- Nine native hit tests at most, under a shared sub-millisecond work budget.
  for x=0,2 do for y=0,2 do
   if os.clock()-started<.0008 then
    local px=rect[1]+(rect[3]-rect[1])*x/2+root.AbsolutePosition.X
    local py=rect[2]+(rect[4]-rect[2])*y/2+root.AbsolutePosition.Y
    local ok,objects=pcall(playerGui.GetGuiObjectsAtPosition,playerGui,math.floor(px),math.floor(py));state.queries+=1
    if ok then for _,object in ipairs(objects)do
     if #state.boxes<64 and not seen[object]and gameBox(object)then
      local record={object=object,seen=now};seen[object]=record;table.insert(state.boxes,record)
     elseif seen[object]then seen[object].seen=now end
    end end
   end
  end end
 end
 function state:Reveal()
  if not controller:IsEnabled()then return end
  controller.revealUntil=os.clock()+math.clamp(tonumber(setting("Capsule Reveal Duration",4))or 4,1,15)
  controller.layoutAt=0
 end
 function state:HoverBar(inside)
  self.hoverGeneration=(self.hoverGeneration or 0)+1
  self.hovering=inside;self.hoverReady=false
  if not inside then return end
  local generation=self.hoverGeneration
  task.delay(.65,function()
   if not controller.alive or generation~=self.hoverGeneration or not self.hovering or not controller.docked then return end
   local drag=context.GetDragState and context.GetDragState()
   if drag and not drag.dragging then self.hoverReady=true;self:Reveal()
   elseif drag and drag.dragging then self.hoverWaitingDrag=true end
  end)
 end
 function state:Retract()
  controller.revealUntil=0
  if controller.picker then controller:EndTimerEntry(false)end
  controller:Open(nil);controller.layoutAt=0
 end
 local function notify(status,now)
  if state.status~=status then state.status=status;state.statusAt=now end
  if state.notified==status or now-(state.statusAt or now)<.35 or now-state.lastNotice<6 then return end
  state.notified=status;state.lastNotice=now
  if context.Notify then
   local message=status=="bar"and "Capsules are tucked into the drag bar. Hover the bar to reveal them."
    or status=="moved"and "Capsules moved down to clear the occupied top-centre space."
    or "Capsules returned to the top of the screen."
   context.Notify("Capsule position",message,nil,{Duration=4})
  end
 end
 function state:Layout(width,height,factor,obstacles)
  local now=os.clock();local viewport=root.AbsoluteSize
  local mode=setting("Capsule Position","Dynamic")
  if self.mode~=mode then
   self.mode=mode;self.committedDocked=nil;self.freeY=nil;self.returnSince=nil;self.returnRect=nil
   self.queryRect=nil;self.probeCandidate=false
  end
  local offset=Vector2.zero
  local left,right=offset.X+12,offset.X+viewport.X-12
  local top=offset.Y+8
  local bottom=offset.Y+viewport.Y-12
  local centerX=offset.X+viewport.X/2
  local drag=context.GetDragState and context.GetDragState()
  local mouse=input:GetMouseLocation()
  local visual=controller:GetVisualObject()
  local held=visual and box(visual)
  local inset=root.IgnoreGuiInset and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
  mouse-=inset
  -- The placement owner survives opening, capture, and the closing morph.
  local active=controller.view~=nil or controller.presentation~=nil or controller.picker or controller.dragging or self.hovering and self.hoverReady
  if self.target>0 and host.Visible and held and mouse.X>=held[1]-18 and mouse.X<=held[3]+18
   and mouse.Y>=held[2]-18 and mouse.Y<=held[4]+18 then active=true end
  local captured=active or controller.dropPresentation~=nil or drag and drag.dragging
  local own={}
  for _,object in ipairs(obstacles)do local b=box(object);if b then table.insert(own,b)end end
  local desired={centerX-width/2,top,centerX+width/2,top+height}
  local boxes=mode=="Dynamic"and table.clone(own)or{}
  if mode=="Dynamic"and controller:IsEnabled()then
   if now>=self.probeAt then
    -- Alternate the desired and selected footprint within the existing budget.
    probe((self.probeCandidate and self.queryRect)or desired,now)
    self.probeCandidate=not self.probeCandidate
   end
   for i=#self.boxes,1,-1 do
    local record=self.boxes[i];local b=gameBox(record.object)
    if not b or now-record.seen>2 then table.remove(self.boxes,i)else table.insert(boxes,b)end
   end
  end
  local function rectAt(y)return{desired[1],y,desired[3],y+height}end
  local function clear(rect)
   if rect[1]<left or rect[3]>right or rect[2]<top or rect[4]>bottom then return false end
   for _,b in ipairs(boxes)do if overlap(rect,b)then return false end end
   return true
  end
  local function findFree(limit)
   local y=top
   for _=1,#boxes+1 do
    local candidate=rectAt(y)
    if y>top+limit or candidate[1]<left or candidate[3]>right or candidate[4]>bottom then return end
    local nextY=y
    for _,b in ipairs(boxes)do if overlap(candidate,b)then nextY=math.max(nextY,b[4]+8)end end
    if nextY==y then return candidate end
    y=nextY
   end
  end
  local function settled(candidate)
   if not candidate or captured then self.returnSince=nil;self.returnRect=nil;return false end
   local previous=self.returnRect;local changed=not previous
   if previous then for i=1,4 do if math.abs(previous[i]-candidate[i])>2 then changed=true;break end end end
   if changed then self.returnSince=now;self.returnRect=candidate end
   return now-(self.returnSince or now)>=.8
  end
  local chosen=desired
  local docked=mode=="Drag Bar Only"
  if mode=="Dynamic"then
   -- Provisional, unmeasured native-UI parameters; keep every candidate on screen.
   local maxDrop=math.min(240*factor,viewport.Y*.30,math.max(0,bottom-top-height))
   chosen=findFree(maxDrop)
   if self.committedDocked then
    local returning=findFree(math.max(0,maxDrop-24*factor))
    docked=not settled(returning)
    if not docked then chosen=returning end
   else
    local committed=self.freeY and rectAt(self.freeY)
    if committed and self.freeY<=top+maxDrop and clear(committed)then
     if captured or not chosen or chosen[2]>=self.freeY then
      chosen=committed;self.returnSince=nil;self.returnRect=nil
     elseif not settled(chosen)then chosen=committed end
    else
     self.returnSince=nil;self.returnRect=nil
    end
    docked=not chosen
   end
  else
   self.returnSince=nil;self.returnRect=nil
  end
  self.queryRect=chosen or desired
  if docked and not drag then docked=false end
  self.committedDocked=docked
  if not docked and chosen then self.freeY=chosen[2]end
  controller.docked=docked
  if self.hoverWaitingDrag and self.hovering and drag and not drag.dragging then self.hoverWaitingDrag=false;self:HoverBar(true)end
  if drag and drag.dragging then self:Retract()end
  local hidden=false
  if docked then
   if active and self.target>0 then self:Reveal()end
   hidden=not active and now>(controller.revealUntil or 0)or drag.dragging
   local center=drag.center
   -- The compact row owns its anchor. Opening a view must not move that anchor.
   local anchorWidth=(controller.compactWidth or 250)*factor
   local anchorHeight=(controller.compactHeight or 32)*factor
   if hidden then controller.targetX=center.X;controller.targetY=center.Y
   elseif drag.dock=="left"or drag.dock=="right"then
    local side=drag.dock=="left"and 1 or -1
    controller.targetX=math.clamp(center.X+side*(drag.size.X/2+12+anchorWidth/2),left+anchorWidth/2,math.max(left+anchorWidth/2,right-anchorWidth/2))
    controller.targetY=math.clamp(center.Y-anchorHeight/2,12,math.max(12,bottom-anchorHeight))
   else
    controller.targetX=math.clamp(center.X,left+anchorWidth/2,math.max(left+anchorWidth/2,right-anchorWidth/2))
    controller.targetY=math.clamp(center.Y<viewport.Y/2 and center.Y+drag.size.Y/2+12 or center.Y-drag.size.Y/2-anchorHeight-12,12,math.max(12,bottom-anchorHeight))
   end
   self.drag=drag
  else
   chosen=chosen or desired;controller.targetX=(chosen[1]+chosen[3])/2;controller.targetY=chosen[2]
  end
  local target=controller:IsEnabled()and not hidden and 1 or 0
  if self.target~=target and docked and controller.AnimateDrop then controller:AnimateDrop(target==0)end
  self.target=target
  if self.target==0 and controller.view then self:Retract()end
  local status=docked and "bar"or chosen and(math.abs(chosen[1]-desired[1])>2 or math.abs(chosen[2]-top)>2)and "moved"or "top"
  if not self.status then self.status=status;self.statusAt=now;self.notified=status=="top"and status or nil end
  if controller:IsEnabled()then notify(status,now)end
  controller.placementStatus=status;controller.presentationTarget=self.target
 end
 -- Offset components are integer-valued in native UDim. Preserve the live
 -- fractional pose so a trailing spring can converge rather than losing its
 -- subpixel movement on every frame.
 local function placeHost(point)
  local viewport=root.AbsoluteSize
  host.Position=UDim2.fromScale(point.X/math.max(1,viewport.X),point.Y/math.max(1,viewport.Y))
 end
 function state:Step(dt,factor)
  local presentation=controller.dropPresentation
  if presentation and controller.dropProgress==presentation.progress then
   local t=presentation.progress.Value
   local amount=presentation.amount+((presentation.merging and 0 or 1)-presentation.amount)*t
   self.amount=amount;self.velocity=0
   scale.Scale=factor*math.max(.025,amount)
   if not controller.presentation then compact.GroupTransparency=0 end
   local start,control,destination=presentation.start,presentation.control,presentation.destination
   local position=start*(1-t)^2+control*(2*(1-t)*t)+destination*t*t
   placeHost(position);host.Visible=amount>.001
   if presentation.merging and not presentation.impacted then
    local object=controller:GetVisualObject()
    local visualCenter=position+Vector2.new(0,object.AbsoluteSize.Y/2)
    if (visualCenter-destination).Magnitude<=8 or t>=.96 then presentation.impacted=true;controller:PulseDrag()end
   end
   return
  end
  local previous=self.amount
  local omega=root:GetAttribute("AltairReduceMotion")and 65 or 24
  local step=math.min(dt,.1);local decay=math.exp(-omega*step)
  local delta=self.amount-self.target;local j=self.velocity+omega*delta
  self.amount=self.target+(delta+j*step)*decay;self.velocity=(self.velocity-omega*j*step)*decay
  if math.abs(self.amount-self.target)<.001 then self.amount=self.target;self.velocity=0 end
  scale.Scale=factor*math.max(.025,self.amount)
  -- Drop/reveal is a physical scale transition, not an independent fade layer.
  if not controller.presentation then compact.GroupTransparency=0 end
  host.Visible=self.amount>0
  local current=host.Position;local destination=Vector2.new(controller.targetX or root.AbsoluteSize.X/2,controller.targetY or 12)
  local origin=Vector2.new(current.X.Scale*root.AbsoluteSize.X+current.X.Offset,current.Y.Scale*root.AbsoluteSize.Y+current.Y.Offset)
  local nextPosition=origin:Lerp(destination,1-math.exp(-20*step))
  if(nextPosition-destination).Magnitude<.01 then nextPosition=destination end
  placeHost(nextPosition)
 end
 return state
end

-- CAPSULES BEGIN: layout, Molto icons, and bindings are authored here.
local function bindCapsules(context)
	local root, Clock = context.Root, context.Clock
	local runService, input = game:GetService("RunService"), game:GetService("UserInputService")
	local tweenService, http = motionService(function() return root:GetAttribute("AltairReduceMotion")==true end), game:GetService("HttpService")
	local lighting = game:GetService("Lighting")
	local white, gray, amber, green = Design.Ink, Design.Muted, Color3.fromRGB(255,177,29), Color3.fromRGB(55,224,92)
	local normal = Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
	local medium = Font.new(normal.Family, Enum.FontWeight.SemiBold)
	local controller = {alive=true, clock=Clock and Clock.new() or nil, view=nil, media={connected=false,title="Spotify",artist=""},
		mediaAt=os.clock(), nextPoll=0, failures=0, connections={}, tweens=setmetatable({}, {__mode="k"}),
		lastErrorAt=-math.huge, commandBusy=false, requestBusy=false, picker=false, layoutAt=0}
	local clock = controller.clock
 controller.enabledObservers={}
 function controller:IsEnabled()return not context.GetSetting or context.GetSetting("Capsules Enabled",true)~=false end
 function controller:ObserveEnabled(callback)
  local observer={Connected=true};self.enabledObservers[observer]=callback
  function observer:Disconnect()self.Connected=false;controller.enabledObservers[self]=nil end
  return observer
 end
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
		local existing=parent and (parent:FindFirstChild(properties.Name or class)or(parent.Name=="center"and parent:FindFirstChild("MediaShelf")and parent.MediaShelf:FindFirstChild(properties.Name or class)))
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
			BackgroundColor3=color or Design.Surface,BackgroundTransparency=color and 0 or 1,BorderSizePixel=0})
		if radius then corner(object,radius) end
		return object
	end
	local function label(parent,name,text,x,y,w,h,size,color)
		local object=make("TextLabel",parent,{Name=name,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			TextSize=size or 12,TextColor3=color or white,FontFace=normal,BackgroundTransparency=1,RichText=false,
			TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Left})
		if color==gray then object:SetAttribute("AltairDesignRole","muted")end
		return object
	end
	local function button(parent,name,text,x,y,w,h,color,action)
		local object=make("TextButton",parent,{Name=name,Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
			FontFace=medium,TextSize=12,TextColor3=white,BackgroundColor3=color or Design.Raised,
			BackgroundTransparency=color and .08 or 1,BorderSizePixel=0,AutoButtonColor=false})
		corner(object,math.min(9,h/2))
		object:SetAttribute("AltairDesignRole","control")
		local feedback=make("UIScale",object,{Name="ButtonFeedback",Scale=1})
		local function feedbackFree()return not object:GetAttribute("AltairActiveCapsule")and not object:GetAttribute("AltairNeighbourTransform")end
		connect(object.MouseButton1Down,function()
			if feedbackFree()and not object:GetAttribute("NoHover")then tweenService:Create(feedback,TweenInfo.new(.07),{Scale=.88}):Play()end
		end)
		connect(object.MouseButton1Up,function()
			if feedbackFree()and not object:GetAttribute("NoHover")then tweenService:Create(feedback,TweenInfo.new(.24,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()end
		end)
		connect(object.Activated,action)
		if not color then object.BackgroundColor3=Color3.new(1,1,1) end
		connect(object.MouseEnter,function()
			if not color and not object:GetAttribute("NoHover") then tweenService:Create(object,TweenInfo.new(.12),{BackgroundTransparency=.92}):Play() end
		end)
		connect(object.MouseLeave,function()
			if feedbackFree()then tweenService:Create(feedback,TweenInfo.new(.18),{Scale=1}):Play()end
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
		if controller.artworkURL==url then
   if not url or artworkCache[url]or controller.artworkBusy or os.clock()<(controller.artworkRetryAt or 0)then return end
  else
   controller.artworkURL=url;controller.artworkGeneration=(controller.artworkGeneration or 0)+1
   controller.artworkFailures=0;controller.artworkRetryAt=0
  end
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
			if controller.alive and generation==controller.artworkGeneration then
    if ok and asset then controller.artworkFailures=0;controller.artworkRetryAt=0;showArtwork(asset)
    else controller.artworkFailures=(controller.artworkFailures or 0)+1;controller.artworkRetryAt=os.clock()+math.min(30,2^math.min(5,controller.artworkFailures))end
   end
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
	local barColor=smartBar and smartBar.BackgroundColor3 or Design.Surface
	local baseColor=barColor
	local controlColor=smartBar and smartBar.Back.BackgroundColor3:Lerp(baseColor,.35) or Design.Raised
	local surface=frame(host,"Surface",0,0,300,24,baseColor,18)
	surface:SetAttribute("AltairDesignRole","surface")
	surface.BackgroundTransparency=Design.materialAlpha(surface,.08)
	surface.AnchorPoint,surface.Position,surface.Visible,surface.ClipsDescendants=Vector2.new(.5,0),UDim2.fromScale(.5,0),false,true
	-- Share the SmartBar's charcoal finish and fine border across both capsule states.
	local sourceStroke=smartBar and smartBar:FindFirstChildOfClass("UIStroke")
	local outline=surface:FindFirstChild("CapsuleOutline") or (sourceStroke and sourceStroke:Clone()) or Instance.new("UIStroke")
	outline:SetAttribute("AltairSurfaceOutline",nil);outline:SetAttribute("AltairInsetOutline",nil)
 outline.Name="CapsuleOutline";outline.Color=Design.Edge;outline.Transparency=.9;outline.Thickness=.6
	outline.Enabled=true;outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;outline.Parent=surface
	local inner=frame(surface,"Back",5,5,0,0,smartBar and smartBar.Back.BackgroundColor3 or Color3.fromRGB(50,50,50),7)
	inner:SetAttribute("AltairInsetSurface",true)
	inner.Size=UDim2.new(1,-10,1,-10);inner.BackgroundTransparency=Design.materialAlpha(inner,.1)
	local innerStroke=make("UIStroke",inner,{Name="InnerOutline",Color=white,Thickness=.7,Transparency=.94,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
	local accentOutlines={outline,innerStroke}
	local function barTile(object,sourceName)
		local source=smartBar and smartBar.Back.Buttons:FindFirstChild(sourceName)
		local gradient=source and source:FindFirstChildOfClass("UIGradient")
		object.BackgroundColor3=Color3.new(1,1,1)
		local tile=make("UIGradient",object,{Name="TileGradient",Rotation=32,
			Color=gradient and gradient.Color or ColorSequence.new(controlColor,barColor)})
        tile:SetAttribute("AltairThemeIgnore",true);tile:SetAttribute("AltairAlbumDriven",false)
        if gradient then
         tile.Color=gradient.Color
         local connection=connect(gradient:GetPropertyChangedSignal("Color"),function()if tile.Parent and not tile:GetAttribute("AltairAlbumDriven")then tile.Color=gradient.Color end end)
         if connection then object.Destroying:Once(function()connection:Disconnect()end)end
        end
	end
	local views,pills={},{}
	local function view(name,w,h)
		local v=make("CanvasGroup",name=="duration"and views.center or surface,{Name=name,Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,GroupTransparency=1,Visible=false})
		views[name]=v;return v
	end
	local center=view("center",300,180)
	local music=view("music",248,132)
	local timer=view("timer",224,100)
	local watch=view("watch",224,130)
	local duration=view("duration",300,166)
	local morphChevron=icon(surface,"MorphChevron","chevron-down",0,0,12,white)
	morphChevron.AnchorPoint=Vector2.new(.5,.5);morphChevron.Position=UDim2.fromScale(.5,.5);morphChevron.ImageTransparency=1
	local sizes={}
	local pillNames={center="ControlCenter",music="Music",timer="Timer",watch="Stopwatch",duration="Timer"}
 local pillOrders={ControlCenter=1,Music=2,Timer=3,Stopwatch=4}
	for name,group in pairs(views) do sizes[name]=Vector2.new(group.Size.X.Offset,group.Size.Y.Offset) end
	local templateSurface=surface
 local syncCompactBounds
 controller.Views=views;controller.TemplateSurface=templateSurface
 local function capsuleRect(object)
  if not object or not object.Parent then return end
  local factor=math.max(.001,scale.Scale)
  local position=(object.AbsolutePosition-host.AbsolutePosition)/factor
  local size=object.AbsoluteSize/factor
  return{x=position.X+size.X*.5,y=position.Y,width=math.max(1,size.X),height=math.max(1,size.Y)}
 end
 local function mixRect(a,b,alpha)
  return{x=a.x+(b.x-a.x)*alpha,y=a.y+(b.y-a.y)*alpha,width=a.width+(b.width-a.width)*alpha,height=a.height+(b.height-a.height)*alpha}
 end
 local function ownOpacity(object)
  local saved={}
  for _,child in ipairs({object,table.unpack(object:GetDescendants())})do
   local properties=child:IsA("UIStroke")and{"Transparency"}or(child:IsA("TextLabel")or child:IsA("TextButton")or child:IsA("TextBox"))and{"BackgroundTransparency","TextTransparency","TextStrokeTransparency"}or(child:IsA("ImageLabel")or child:IsA("ImageButton"))and{"BackgroundTransparency","ImageTransparency"}or child:IsA("GuiObject")and{"BackgroundTransparency"}
   if properties then for _,property in ipairs(properties)do saved[#saved+1]={child,property,child[property]}end end
  end
  return saved
 end
 local function restoreOpacity(saved)
  -- ownOpacity captures rendered values, including the current material finish.
  for _,entry in ipairs(saved or{})do if entry[1].Parent then entry[1][entry[2]]=entry[3]end end
 end
 local function facePart(object)
  if not object then return end
  return{object=object,position=object.Position,size=object.Size,anchor=object.AnchorPoint,visible=object.Visible,textSize=(object:IsA("TextLabel")or object:IsA("TextButton"))and object.TextSize or nil,opacity=ownOpacity(object)}
 end
 local function restoreFace(part)
  if not part or not part.object.Parent then return end
  local object=part.object;object.Position=part.position;object.Size=part.size;object.AnchorPoint=part.anchor
  if object.Name~="Artwork"and object.Name~="Note"then object.Visible=part.visible end
  if part.textSize then object.TextSize=part.textSize end
  restoreOpacity(part.opacity)
 end
 local function tintSequence(a,b,alpha)
  local first,last=a.Keypoints[1].Value,a.Keypoints[#a.Keypoints].Value
  return ColorSequence.new(first:Lerp(b.Keypoints[1].Value,alpha),last:Lerp(b.Keypoints[#b.Keypoints].Value,alpha))
 end
 local function sourceMaterial(object)
  local visual=object and(object:FindFirstChild("Visual")or object)
  local back=visual and visual:FindFirstChild("Back")
  local gradient=back and back:FindFirstChildOfClass("UIGradient")
  return visual,back,gradient
 end
 local capsuleButtonNames={ControlCenter="Settings",Music="Playerlist",Timer="Scripts",Stopwatch="Character"}
 local function compactGradient(object,fallback)
  local _,_,gradient=sourceMaterial(object)
  if object==pills.music and gradient and gradient:GetAttribute("AltairAlbumDriven")and controller.albumColors then return ColorSequence.new(controller.albumColors[1],controller.albumColors[2])end
  local name=object and capsuleButtonNames[object.Name];local button=name and smartBar and smartBar.Back.Buttons:FindFirstChild(name)
  local source=button and button:FindFirstChildOfClass("UIGradient")
  return source and source.Color or fallback or(gradient and gradient.Color)or ColorSequence.new(baseColor)
 end
 local neighbourScales=setmetatable({}, {__mode="k"})
 controller.neighbourScales=neighbourScales
 local function effectiveCapsuleScale(object,name)
  local value=object:FindFirstChildOfClass("UIScale")
  if not value then value=Instance.new("UIScale");value.Name=name or"ButtonFeedback";value.Scale=1;value.Parent=object end
  for _,child in ipairs(object:GetChildren())do
   if child:IsA("UIScale")and child~=value and(child.Name=="CapsuleShellScale"or child.Name=="CapsuleNeighbourScale"or child.Name=="InteractionScale")then child:Destroy()end
  end
  return value
 end
 local function shellGeometry(object,rect,fit)
  local width,height=math.max(1,host.Size.X.Offset),math.max(1,host.Size.Y.Offset)
  object.Position=UDim2.fromScale(rect.x/width,rect.y/height)
  object.Size=UDim2.fromScale(math.max(1,rect.width)/math.max(.001,fit)/width,math.max(1,rect.height)/math.max(.001,fit)/height)
 end
 local function neighbourScale(object)
  local record=neighbourScales[object]
  if record and record.scale.Parent then
   if not record.owned then tweenService:Create(record.scale,TweenInfo.new(0),{Scale=record.scale.Scale}):Play();record.owned=true end
   return record.scale
  end
  local value=effectiveCapsuleScale(object,"CapsuleNeighbourScale")
  tweenService:Create(value,TweenInfo.new(0),{Scale=value.Scale}):Play()
  neighbourScales[object]={scale=value,owned=true};return value
 end
 connect(strip.ChildAdded,function(object)if object:IsA("GuiObject")and controller.presentation then controller.presentation.dirty=true end end)
 local function expandedTarget(p)
  local width,height=p.expandedSize.X,p.expandedSize.Y
  local factor=math.max(.001,controller.baseScale or scale.Scale)
  local origin=host.AbsolutePosition-root.AbsolutePosition;local viewport=root.AbsoluteSize
  local minX,maxX=(8-origin.X)/factor+width*.5,(viewport.X-8-origin.X)/factor-width*.5
  local minY,maxY=(8-origin.Y)/factor,(viewport.Y-8-origin.Y)/factor-height
  local viewportMinY,viewportMaxY=minY,maxY
  local desiredX,desiredY=host.Size.X.Offset*.5,p.anchorY or p.collapsedRect.y
  local drag=controller.docked and context.GetDragState and context.GetDragState()
  if drag then
   if drag.dock=="top"then minY=math.max(minY,(drag.center.Y+drag.size.Y/2+12-origin.Y)/factor)
   elseif drag.dock=="bottom"then maxY=math.min(maxY,(drag.center.Y-drag.size.Y/2-12-origin.Y)/factor-height)
   elseif drag.dock=="left"then local boundary=(drag.center.X+drag.size.X/2+12-origin.X)/factor+width*.5;if boundary<=maxX then minX=math.max(minX,boundary)end
   elseif drag.dock=="right"then local boundary=(drag.center.X-drag.size.X/2-12-origin.X)/factor-width*.5;if boundary>=minX then maxX=math.min(maxX,boundary)end end
  end
  if minY>maxY then minY,maxY=viewportMinY,viewportMaxY end
  return{x=math.clamp(desiredX,minX,math.max(minX,maxX)),y=math.clamp(desiredY,minY,math.max(minY,maxY)),width=width,height=height}
 end
 function controller:GetVisualObject()
  local p=self.presentation
  return p and p.shell and p.shell.Parent and p.shell or compact
 end
 function controller:GetPresentationRect()
  local p=self.presentation
  return p and p.rect or capsuleRect(compact)
 end
 function controller:GetPresentationSourceBounds()
  local p=self.presentation
  local object=p and(p.returnSource and p.returnSource~=p.source and p.returnSource or p.slot)
  local rect=capsuleRect(object or compact);if not rect then return end
  local factor=math.max(.001,scale.Scale);local origin=host.AbsolutePosition-root.AbsolutePosition
  return{origin.X+(rect.x-rect.width*.5)*factor,origin.Y+rect.y*factor,origin.X+(rect.x+rect.width*.5)*factor,origin.Y+(rect.y+rect.height)*factor}
 end
 function controller:SetSurfaceOpacity(alpha)
  self.surfaceOpacity=math.clamp(tonumber(alpha)or .1,0,1)
  if self.presentation then self.presentation.dirty=true end
 end
 function controller:GetViewSize(name)return sizes[name]end
 function controller:SetViewSize(name,size,duration)
  assert(sizes[name]and typeof(size)=="Vector2"and size.X>0 and size.Y>0,"Unknown capsule view size")
  sizes[name]=size;views[name].Size=UDim2.fromOffset(size.X,size.Y)
  local p=self.presentation
  if p and p.view==name then
   p.expandedSize=size;p.resize={from=table.clone(p.expandedRect),phase=0,velocity=0,duration=duration or .22};p.dirty=true
  end
  self.layoutAt=0
 end
 local function restorePresentation(p)
  if not p then return end
  local observerSet={}
  for _,connection in ipairs(p.materialObservers or{})do connection:Disconnect();observerSet[connection]=true end
  for index=#controller.connections,1,-1 do if observerSet[controller.connections[index]]then table.remove(controller.connections,index)end end
  for object,record in pairs(neighbourScales)do record.owned=false;if record.scale.Parent then record.scale.Scale=1;object:SetAttribute("AltairNeighbourTransform",nil)end end
  for _,group in pairs(views)do
   if not group:GetAttribute("AltairInlineView")then group.Visible=false;group.GroupTransparency=1;group.Parent=templateSurface end
  end
  for _,part in pairs(p.face)do restoreFace(part)end
  if p.visual and p.visual~=p.source then p.visual.Position=UDim2.new();p.visual.Size=UDim2.fromScale(1,1);p.visual.GroupTransparency=0 end
  p.shellScale.Scale=1
  p.source.AnchorPoint=p.original.anchor;p.source.Position=p.original.position;p.source.Size=p.slot.Parent and p.slot.Size or p.original.size
  p.source.BackgroundColor3=p.original.color;p.source.BackgroundTransparency=Design.materialAlpha(p.source,p.original.transparency);p.source.ClipsDescendants=p.original.clips
  p.source.UICorner.CornerRadius=p.original.corner;p.source:SetAttribute("NoHover",p.original.noHover);p.source:SetAttribute("AltairActiveCapsule",nil)
  if p.back then p.back.Position=p.original.backPosition;p.back.Size=p.original.backSize;p.back.BackgroundColor3=p.original.backColor;p.back.BackgroundTransparency=Design.materialAlpha(p.back,p.original.backTransparency);if p.back:FindFirstChildOfClass("UICorner")then p.back.UICorner.CornerRadius=p.original.backCorner end end
  if p.gradient then p.gradient.Color=p.original.gradient end
  if p.edge then p.edge.Position=p.original.edgePosition;p.edge.Size=p.original.edgeSize;if p.edge:FindFirstChildOfClass("UICorner")then p.edge.UICorner.CornerRadius=p.original.edgeCorner end end
  if p.source.Name=="Music"and p.face.Title then p.face.Title.object.Size=UDim2.fromOffset(math.max(1,p.source.Size.X.Offset-35),24)end
  p.source.Parent=p.original.parent and p.original.parent.Parent and p.original.parent or strip
  if p.source==pills.music then p.source.Visible=controller.musicShown else p.source.Visible=p.original.visible end
  if p.source==pills.timer and not clock.timer or p.source==pills.watch and not clock.watch.active then p.source.Visible=false end
  if p.destinationOpacity then restoreOpacity(p.destinationOpacity);if p.returnSource and p.returnSource:FindFirstChild("Chevron")then p.returnSource.Chevron.ImageTransparency=0 end end
  morphChevron.Parent=templateSurface;morphChevron.ImageTransparency=1;morphChevron.Position=UDim2.fromScale(.5,.5)
  if p.slot.Parent then p.slot:Destroy()end
  compact.Visible=true;compact.GroupTransparency=0;compact.Interactable=true;templateSurface.Visible=false
  controller.presentation=nil;controller.activityMorphSource=nil;controller.activityClosePosition=nil;controller.layoutAt=0
  syncCompactBounds()
 end
 local function startPresentation(source,name)
  local rect=capsuleRect(source);if not rect then return end
  local visual,back,gradient=sourceMaterial(source)
  local slot=Instance.new("Frame");slot.Name="CapsuleReturnSlot";slot.BackgroundTransparency=1;slot.BorderSizePixel=0;slot.Size=source.Size;slot.LayoutOrder=source.LayoutOrder;slot.Visible=true;slot.Parent=source.Parent
  local fit=rect.width/math.max(1,source.Size.X.Offset)
  local p={source=source,shell=source,slot=slot,view=name,phase=0,targetPhase=1,velocity=0,rect=table.clone(rect),collapsedRect=table.clone(rect),anchorY=rect.y,expandedSize=sizes[name],generation=controller.transition,face={},startFit=fit,dirty=true,visual=visual,back=back,gradient=gradient}
  p.expandedRect=expandedTarget(p)
  p.original={parent=source.Parent,position=source.Position,size=source.Size,anchor=source.AnchorPoint,color=source.BackgroundColor3,transparency=source:GetAttribute("AltairMaterialRestAlpha")or source:GetAttribute("AltairSolidRestAlpha")or source.BackgroundTransparency,clips=source.ClipsDescendants,corner=source.UICorner.CornerRadius,noHover=source:GetAttribute("NoHover"),visible=source.Visible}
  if back then p.original.backPosition=back.Position;p.original.backSize=back.Size;p.original.backColor=back.BackgroundColor3;p.original.backTransparency=back:GetAttribute("AltairMaterialRestAlpha")or back:GetAttribute("AltairSolidRestAlpha")or back.BackgroundTransparency;p.original.backCorner=back.UICorner.CornerRadius end
  p.edge=visual and visual:FindFirstChild("Edge")
  if p.edge then p.original.edgePosition=p.edge.Position;p.original.edgeSize=p.edge.Size;p.original.edgeCorner=p.edge:FindFirstChildOfClass("UICorner")and p.edge.UICorner.CornerRadius end
  p.original.gradient=gradient and gradient.Color
  p.materialObservers={}
  local function observe(object,property)
   if not object then return end
   local connection=connect(object:GetPropertyChangedSignal(property),function()if controller.presentation==p then p.dirty=true end end)
   if connection then p.materialObservers[#p.materialObservers+1]=connection end
  end
  if smartBar then
   observe(smartBar,"BackgroundColor3");observe(smartBar.Back,"BackgroundColor3")
   for _,button in ipairs(smartBar.Back.Buttons:GetChildren())do if button:IsA("GuiObject")then observe(button:FindFirstChildOfClass("UIGradient"),"Color")end end
  end
  for _,key in ipairs({"Value","Chevron","ClockIcon","Title","Artwork","Note"})do local part=visual and visual:FindFirstChild(key);if part then p.face[key]=facePart(part)end end
  local origin=source.AbsolutePosition-root.AbsolutePosition;local size=source.AbsoluteSize
  controller.hoverSourceBounds={origin.X,origin.Y,origin.X+size.X,origin.Y+size.Y}
  source.Parent=host;source.Visible=true;source.AnchorPoint=Vector2.new(.5,0);source.ClipsDescendants=true;source:SetAttribute("NoHover",true);source:SetAttribute("AltairActiveCapsule",true)
  local shellScale=effectiveCapsuleScale(source,"ButtonFeedback");p.shellScale=shellScale
  local cancelledFeedback=tweenService:Create(shellScale,TweenInfo.new(0),{Scale=fit})
  cancelledFeedback:Play();cancelledFeedback:Cancel();shellScale.Scale=fit
  shellGeometry(source,rect,fit)
  tweenService:Create(source,TweenInfo.new(0),{Position=source.Position,Size=source.Size}):Play()
  if visual and visual~=source then tweenService:Create(visual,TweenInfo.new(0),{Position=UDim2.new(),Size=UDim2.fromScale(1,1),GroupTransparency=0}):Play()end
  controller.presentation=p;controller.origin={x=rect.x,y=rect.y,width=rect.width,source=source}
  compact.Visible=true;compact.Interactable=false;templateSurface.Visible=false
  return p
 end
	function controller:Open(name)
		assert(name==nil or sizes[name],"Unknown capsule view")
  if name=="duration"and views.duration:GetAttribute("AltairInlineView")then
   if not self.picker and self.BeginTimerEntry then self:BeginTimerEntry();return end
   name="center"
  end
		if self.picker and name~="center"and name~="duration"then
   if name==nil then self:EndTimerEntry(false,true)else return end
  end
		if name and not self:IsEnabled()then return end
		if name==self.view then return end
  local previous=self.view;local p=self.presentation
  self.transition=(self.transition or 0)+1;self.view=name
  self.hoverGraceUntil=name and os.clock()+.85 or nil;self.hoverReachedSurface=false
  if previous=="music"and not name then self.musicHoldUntil=os.clock()+.65 end
  if self.cancelDrag then self.cancelDrag()end
  if not name then
   if not p then return end
   p.targetPhase=0;p.generation=self.transition;p.dirty=true
   local destination=self.origin and self.origin.source
   if destination and destination.Parent and destination~=p.source then
    p.returnSource=destination;p.destinationOpacity=ownOpacity(destination);p.destinationBackground=destination.BackgroundTransparency
    morphChevron.Parent=p.shell;morphChevron.Visible=true
   end
   return
  end
  if not p then
   local source=self.docked and self.activityIndicators and(name=="timer"and self.activityIndicators[1]or name=="watch"and self.activityIndicators[2])or pills[name]or pills.center
   p=startPresentation(source,name);if not p then self.view=nil;return end
  else
   p.targetPhase=1;p.generation=self.transition;p.dirty=true
   if p.destinationOpacity then restoreOpacity(p.destinationOpacity);p.destinationOpacity=nil;p.returnSource=nil;morphChevron.Parent=templateSurface;morphChevron.ImageTransparency=1 end
   if p.view~=name or p.expandedSize~=sizes[name]then p.previousView=p.view~=name and p.view or nil;p.pageAt=os.clock();p.resize={from=table.clone(p.expandedRect),phase=0,velocity=0,duration=.24}end
   p.view=name;p.expandedSize=sizes[name]
  end
  for key,group in pairs(views)do
   if not group:GetAttribute("AltairInlineView")then
    if key==name or key==p.previousView then group.Parent=p.shell;group.Visible=true
    else group.Visible=false;group.GroupTransparency=1;group.Parent=templateSurface end
   end
  end
  self.layoutAt=0
	end

	local function pill(name,text,width,color,action)
		local p=button(strip,name,text,0,0,width,24,barColor,function(event)
			if controller.presentation and controller.presentation.source.Name==name and controller.view then return end
			if event and event.UserInputType==Enum.UserInputType.Touch then action() end
		end)
		connect(p.MouseEnter,function()
			if controller.presentation and controller.presentation.source==p and controller.view then controller.hoverSession=true;controller.hoverLeftAt=nil;return end
			local position=p.AbsolutePosition-root.AbsolutePosition;local size=p.AbsoluteSize
			controller.hoverSourceBounds={position.X,position.Y,position.X+size.X,position.Y+size.Y}
			controller.hoverSource=p
			controller.hoverSession=true;controller.hoverLeftAt=nil;action()
		end)
		local visual=p
		if name=="Music" then
			p.BackgroundTransparency=1;p.ClipsDescendants=true;p.UICorner.CornerRadius=UDim.new(0,8)
			visual=make("CanvasGroup",p,{Name="Visual",Size=UDim2.fromOffset(width,24),BackgroundColor3=barColor,
				BackgroundTransparency=.08,BorderSizePixel=0,GroupTransparency=1})
			corner(visual,8)
			visual:SetAttribute("AltairDesignRole","surface")
			visual.BackgroundTransparency=Design.materialAlpha(visual,.08)
		else p.BackgroundTransparency=Design.materialAlpha(p,.08)end
		local back=frame(visual,"Back",2,2,0,0,controlColor,7);back.Size=UDim2.new(1,-4,1,-4)
		barTile(back,({ControlCenter="Settings",Music="Playerlist",Timer="Scripts",Stopwatch="Character"})[name])
		back:SetAttribute("AltairInsetSurface",true)
		back.BackgroundTransparency=Design.materialAlpha(back,.18)
		local edge=frame(visual,"Edge",1,1,0,0,nil,8);edge.Size=UDim2.new(1,-2,1,-2)
		accentOutlines[#accentOutlines+1]=make("UIStroke",edge,{Name="PillOutline",Color=Design.Edge,Thickness=.6,
			Transparency=.9,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
		if name~="Music" then
			p.Text=""
			local value=label(visual,"Value",text,0,0,width,24,8,white)
			value.TextXAlignment=Enum.TextXAlignment.Center;value.FontFace=medium
		end
		p.LayoutOrder=pillOrders[name]or #strip:GetChildren();p.TextSize=8;p.TextColor3=color or white
		p.UICorner.CornerRadius=UDim.new(0,6)
		return p,visual
	end
	local menuPill=pill("ControlCenter","",24,white,function() controller:Open("center") end)
 menuPill.UICorner.CornerRadius=UDim.new(0,6)
	icon(menuPill,"Chevron","chevron-down",6,6,12,white)
	local musicPill,musicVisual=pill("Music","",62,white,function() controller:Open("music") end)
	musicPill.Visible=false
	local timerPill=pill("Timer","    05:00",50,amber,function() controller:Open("timer") end)
	local watchPill=pill("Stopwatch","    00:00",50,green,function() controller:Open("watch") end)
	for _,p in {timerPill,watchPill} do icon(p,"ClockIcon","timer",5,6,12,white) end
	pills.center,pills.music,pills.timer,pills.watch=menuPill,musicPill,timerPill,watchPill
	artwork(musicVisual,3,3,18,9,7,7,10)
	local compactTitle=label(musicVisual,"Title","Spotify",27,0,60,24,8,white);compactTitle.FontFace=medium
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
        controller.freeMusicWidth=width
        if controller.iconOnly then width=24 end
		local presentation=controller.presentation
		if presentation and presentation.source==musicPill then
			local changed=controller.musicWidth~=width
			controller.musicShown=active;controller.musicWidth=width
			if presentation.slot.Parent then presentation.slot.Size=UDim2.fromOffset(width,24)end
			compactTitle.Size=UDim2.fromOffset(math.max(1,width-35),24)
			if changed then presentation.dirty=true;syncCompactBounds()end
			return
		end
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
			compactTitle.Size=UDim2.fromOffset(width-35,24)
		end
	end
	timerPill.Visible,watchPill.Visible=false,false
	syncCompactBounds=function()
		if root.AbsoluteSize.X<=0 then return end
		local factor=math.max(.0001,scale.Scale*compactFit.Scale)
		local width=math.max(24,pillLayout.AbsoluteContentSize.X/factor)
        local height=controller.iconOnly and math.max(24,pillLayout.AbsoluteContentSize.Y/factor)or 24
		local fit=math.min(1,(root.AbsoluteSize.X-24)/math.max(1,(width+8)*scale.Scale))
		set(compactFit,"Scale",math.max(.05,fit))
		set(strip,"Size",UDim2.fromOffset(width,height))
		set(compact,"Size",UDim2.fromOffset(width+8,height+8))
		set(compact,"Position",UDim2.new(.5,0,0,-4*compactFit.Scale))
		controller.compactWidth=(width+8)*compactFit.Scale
        controller.compactHeight=(height+8)*compactFit.Scale
		if controller.presentation then controller.presentation.dirty=true end
	end
 controller.externalHandles={}
 function controller:RegisterExternal(options)
  self.externalSerial=(self.externalSerial or 0)+1
  local group=Instance.new("CanvasGroup");group.Name="ExternalCapsule"..self.externalSerial;group.BackgroundTransparency=1
  group.Size=UDim2.fromOffset(0,24);group.GroupTransparency=1;group.Visible=false;group.ClipsDescendants=true;group.LayoutOrder=100+self.externalSerial;group.ZIndex=291;group.Parent=strip
  local button=musicPill:Clone();button.Name="Restore";button.Position=UDim2.fromOffset(0,0);button.Size=UDim2.fromScale(1,1);button.Visible=true;button.Parent=group
  -- The real music pill may currently own an expanded page. External capsules
  -- clone only its compact face, never its mounted controls or animation scale.
  for _,child in ipairs(button:GetChildren())do if views[child.Name]or child.Name=="CapsuleShellScale"or child.Name=="CapsuleNeighbourScale"then child:Destroy()end end
  button:SetAttribute("AltairActiveCapsule",nil);button:SetAttribute("NoHover",nil);button.BackgroundTransparency=1;button.UICorner.CornerRadius=UDim.new(0,6)
  local visual=button.Visual;visual.Size=UDim2.fromScale(1,1);visual.GroupTransparency=0
  visual.Position=UDim2.new();visual.BackgroundTransparency=.08;visual.UICorner.CornerRadius=UDim.new(0,8)
  visual.Back.Position=UDim2.fromOffset(2,2);visual.Back.Size=UDim2.new(1,-4,1,-4);visual.Back.BackgroundTransparency=.18;visual.Back.UICorner.CornerRadius=UDim.new(0,7)
  visual.Edge.Position=UDim2.fromOffset(1,1);visual.Edge.Size=UDim2.new(1,-2,1,-2);visual.Edge.UICorner.CornerRadius=UDim.new(0,8)
  visual.Artwork.BackgroundTransparency=0;visual.Artwork.Cover.ImageTransparency=0
  local variants={"Scripts","Character","Playerlist","Home","Settings"}
  barTile(visual.Back,variants[(self.externalSerial-1)%#variants+1])
  local title=visual.Title;title.Text=tostring(options.Title or "Rayfield");title.TextSize=compactTitle.TextSize;title.TextTransparency=0;title.TextStrokeTransparency=1;title.TextTruncate=Enum.TextTruncate.None;title.Size=UDim2.new(1,-35,1,0)
  local cover=visual.Artwork.Cover;cover.Image=type(options.Icon)=="string"and options.Icon:match("^rbx")and options.Icon or "";cover.Visible=cover.Image~=""
  local note=visual:FindFirstChild("Note");if note then note.Visible=false end
  if not cover.Visible then applyIcon(cover,"square-terminal");cover.Visible=true;visual.Artwork.Visible=true end
  local outline=visual.Edge:FindFirstChildOfClass("UIStroke");if outline then table.insert(accentOutlines,outline)end
  local press=effectiveCapsuleScale(button,"ButtonFeedback");press.Scale=1
  local handle={group=group,generation=0,width=math.clamp(#title.Text*4+35,62,220),connections={}}
  local function animate(object,duration,goals,style)tweenService:Create(object,TweenInfo.new(duration,style or Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goals):Play()end
  function handle:TargetWidth()return controller.iconOnly and 24 or self.width end
  function handle:SetIconOnly(enabled)
   animate(title,.18,{TextTransparency=enabled and 1 or 0})
   if self.shown then animate(group,.24,{Size=UDim2.fromOffset(self:TargetWidth(),24)})end
  end
  controller.externalHandles[handle]=true
  function handle:Show(reveal)
   self.generation+=1;self.shown=true;group.Visible=true
   animate(group,.3,{Size=UDim2.fromOffset(self:TargetWidth(),24),GroupTransparency=reveal and 0 or .12})
   syncCompactBounds()
  end
  function handle:Hide()
   self.generation+=1;self.shown=false;local generation=self.generation
   animate(group,.24,{Size=UDim2.fromOffset(0,24),GroupTransparency=1})
   task.delay(.25,function()if group.Parent and self.generation==generation then group.Visible=false;syncCompactBounds()end end)
  end
  function handle:Rect()
   if controller.docked and controller.presentationTarget==0 and controller.placement and controller.placement.drag then
    local center=controller.placement.drag.center+root.AbsolutePosition
    return center-Vector2.new(7,2),Vector2.new(14,4)
   end
   local factor=scale.Scale*compactFit.Scale;local delta=(self:TargetWidth()-group.Size.X.Offset)*factor
   return group.AbsolutePosition-Vector2.new(delta/2,0),Vector2.new(self:TargetWidth(),24)*factor
  end
  function handle:Destroy()controller.externalHandles[self]=nil;for _,connection in ipairs(self.connections)do connection:Disconnect()end;group:Destroy();syncCompactBounds()end
  local function listen(signal,callback)table.insert(handle.connections,signal:Connect(callback))end
  listen(button.MouseEnter,function()if controller.view then return end;animate(press,.18,{Scale=1.025});if outline then animate(outline,.18,{Transparency=.68})end end)
  listen(button.MouseLeave,function()animate(press,.3,{Scale=1},Enum.EasingStyle.Back);if outline then animate(outline,.2,{Transparency=.88})end end)
  listen(button.MouseButton1Down,function()animate(press,.1,{Scale=.94})end)
  listen(button.Activated,function()if controller.view then return end;animate(press,.35,{Scale=1},Enum.EasingStyle.Back);if controller.alive and options.Restore then options.Restore()end end)
  task.spawn(function()
   local params=Instance.new("GetTextBoundsParams");params.Font=title.FontFace;params.Size=title.TextSize;params.Text=title.Text;params.Width=1000
   local ok,bounds=pcall(game:GetService("TextService").GetTextBoundsAsync,game:GetService("TextService"),params);params:Destroy()
   if ok and group.Parent then handle.width=math.clamp(math.ceil(bounds.X)+(cover.Visible and 35 or 16),62,240);if group.Visible then animate(group,.2,{Size=UDim2.fromOffset(handle:TargetWidth(),24)})end end
  end)
  handle:SetIconOnly(controller.iconOnly==true)
  return handle
 end

	connect(pillLayout:GetPropertyChangedSignal("AbsoluteContentSize"),syncCompactBounds)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"),syncCompactBounds)
	local function notifyError(message)
		if os.clock()-controller.lastErrorAt<4 then return end
		controller.lastErrorAt=os.clock();context.Notify("Spotify",message,nil)
	end
	function controller:ShowSetup()
		context.Notify("Spotify setup","1. Run Companion/StartSpotify.cmd and keep the companion running. 2. Play something in Spotify desktop. 3. Choose Connect Spotify. Volt pairs automatically; no developer app is needed. These steps also appear in Settings > Experimental > Spotify. Other-device playback is optional under Spotify - Advanced.",nil,{Duration=12})
	end
	local function bridgeRequest(method,path,body)
		if context.MediaAdapter then return context.MediaAdapter(method,path,body) end
		if type(context.Request)~="function" then error({status="unsupported_executor",message="This executor has no HTTP request function. Spotify needs an executor with local HTTP support."},0) end
		local key=tostring(get("Spotify Bridge Key","")):match("^%s*(.-)%s*$")
		if #key<32 then error({status="pairing_required",message="Run the companion, then choose Connect Spotify to import pairing. Outside Volt, enter its local key in Spotify - Advanced."},0) end
		local port=math.clamp(math.floor(tonumber(get("Spotify Bridge Port",43827)) or 43827),1024,65535)
		local response=context.Request({Url="http://127.0.0.1:"..port.."/v1/"..path,Method=method,Timeout=method=="GET" and 3 or 15,
			Headers={Authorization="Bearer "..key,["Content-Type"]="application/json"},Body=body and http:JSONEncode(body) or nil})
		assert(type(response)=="table","The Spotify companion did not respond")
		local status=tonumber(response.StatusCode or response.Status) or 0
		if status==401 or status==403 then error({status="pairing_required",message="Companion pairing was rejected. Choose Connect Spotify to reload pairing; check the Bridge Key and Port if using manual setup."},0) end
		local ok,data=pcall(http.JSONDecode,http,response.Body or "")
		assert(ok and type(data)=="table","The companion returned an invalid response")
		assert(status>=200 and status<300,data.error or "Spotify companion request failed")
		return data
	end
	controller.commands={};controller.mediaGeneration=0
	function controller:Enqueue(path,body,previous)
		if not self.alive then return false end
		if path=="control"and body.action=="seek"and self.navigationPending then return false end
		if path~="control" then
			table.clear(self.commands)
			self.navigationPending=nil
			self.accountGeneration=(self.accountGeneration or 0)+1
		elseif body.action=="seek" or body.action=="volume" then
			for i=#self.commands,1,-1 do
				local job=self.commands[i]
				if job.path=="control" and job.body.action==body.action then table.remove(self.commands,i) end
			end
		end
		if #self.commands>=8 then notifyError("Playback controls are busy. Try again in a moment.");return false end
		local navigation
		if path=="control"and(body.action=="next"or body.action=="previous")then
			-- A seek made against the outgoing track must never follow navigation
			-- into another track, including one that was already waiting to send.
			for i=#self.commands,1,-1 do local job=self.commands[i];if job.path=="control"and job.body.action=="seek"then table.remove(self.commands,i)end end
			navigation={identity=self.mediaIdentity};self.navigationPending=navigation
			if self.cancelSeek then self.cancelSeek("navigation")end
		end
		self.mediaGeneration+=1
		self.commands[#self.commands+1]={path=path,body=body,previous=previous,generation=self.mediaGeneration,navigation=navigation}
		if self.commandBusy then return true end
		self.commandBusy=true
		task.defer(function()
			while self.alive and #self.commands>0 do
				local job=table.remove(self.commands,1)
				local ok,result=pcall(bridgeRequest,"POST",job.path,job.body)
				if not self.alive then return end
				if ok then
					if job.navigation and self.navigationPending==job.navigation then
						job.navigation.completedAt=os.clock();job.navigation.expiresAt=os.clock()+5;self.nextPoll=0
					end
					if job.path=="unlink" then
						self:SetMedia({connected=false,linked=false,title="Spotify"})
						context.Notify("Spotify","Unlinked. Saved account tokens were removed. Use Connect Spotify to connect again.",nil)
					elseif job.path=="link" then context.Notify("Spotify",result.linked and "Saved Spotify connection restored. It will reconnect automatically."or"Approve Spotify in your browser once. The connection will be saved.",nil) end
				else
					if job.navigation and self.navigationPending==job.navigation then self.navigationPending=nil end
					if job.previous and job.generation==self.mediaGeneration then self:SetMedia(job.previous) end
					notifyError(type(result)=="table" and result.message or tostring(result))
				end
			end
			self.commandBusy=false;self.nextPoll=0
		end)
		return true
	end
    local function spotifyStatus(m)
     if not get("Spotify Connection",false) then return "Updates paused","Turn on Spotify Connection to resume updates. Your saved link is unchanged." end
     if m.status=="pairing_required" or m.status=="unsupported_executor" then return "Spotify setup needed",m.message or "Run the companion and choose Connect Spotify. Manual pairing is under Spotify - Advanced." end
     if m.reauth_required or m.status=="authorization_required" then return "Spotify approval needed","Choose Connect Spotify to approve again in your browser." end
     if m.status=="waiting_for_spotify" then return "Waiting for Spotify",m.message or "Open Spotify desktop and play something. Your saved link is retained." end
     if m.status=="unlinked" then return "Connect Spotify","Run Companion/StartSpotify.cmd, play something in Spotify desktop, then choose Connect Spotify." end
     if m.available==false or m.status=="reconnecting" then return "Reconnecting Spotify",m.message or "Waiting for the companion. Keep it running; Altair will retry automatically." end
     if m.web_reauth_required and m.connected then return "Desktop playback ready","Desktop playback is available. Web API playback needs browser approval; choose Connect Spotify with your Client ID to restore it." end
     if m.connected then return m.playing and "Spotify connected" or "Spotify paused",m.message or "Your saved connection is ready. Resume playback in Spotify when you want to listen." end
     if m.linked then return "Spotify linked",m.message or "Your link is saved. Open Spotify and play something." end
     return "Connect Spotify","Run Companion/StartSpotify.cmd, play something in Spotify desktop, then choose Connect Spotify."
    end
    function controller:ShowSpotifyStatus()
     local title,message=spotifyStatus(self.media)
     context.Notify(title,message,nil)
    end
	function controller:LinkSpotify()
        if context.EnableSpotify then context.EnableSpotify()end
        self.nextPoll=0
		return self:Enqueue("link",{clientId=tostring(get("Spotify Client ID","")):match("^%s*(.-)%s*$")})
	end
 -- One modal owner: account decisions stay separate from their presentation.
 local unlinkPrompt=(function()
  local width,height=380,224
  local overlay=make("TextButton",root,{Name="SpotifyUnlinkConfirmation",Text="",AutoButtonColor=false,
   Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,Active=true,ZIndex=650})
  local scrim=frame(overlay,"Scrim",0,0,0,0,Color3.new())
  scrim.Size=UDim2.fromScale(1,1);scrim.BackgroundTransparency=1;scrim.ZIndex=650;scrim.Active=false
  scrim:SetAttribute("AltairThemeIgnore",true)
  local card=make("CanvasGroup",overlay,{Name="Card",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
   Size=UDim2.fromOffset(width,height),BackgroundTransparency=1,GroupTransparency=1,BorderSizePixel=0,Active=true,ZIndex=651})
  card:SetAttribute("AltairDesignManaged",true);card:SetAttribute("AltairDesignTransparencyOffset",.02)
  corner(card,18)
  local scale=make("UIScale",card,{Name="PresentationScale",Scale=1})
  local backdrop=frame(card,"Backdrop",0,0,width,height,Design.Surface,18)
  backdrop.BackgroundTransparency=.07;backdrop.ZIndex=651;backdrop:SetAttribute("AltairSurface",true)
  backdrop:SetAttribute("AltairDesignRole","surface");backdrop:SetAttribute("AltairDesignManaged",true)
  make("UIStroke",backdrop,{Name="UIStroke",Color=Design.Edge,Transparency=.88,Thickness=.6,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,BorderStrokePosition=Enum.BorderStrokePosition.Inner})
  local badge=frame(card,"LinkBadge",20,18,32,32,Design.Well,9)
  badge.BackgroundTransparency=.1;badge:SetAttribute("AltairDesignRole","inset")
  icon(badge,"Icon","link-2",8,8,16,Design.Muted)
  label(card,"Eyebrow","SPOTIFY",62,16,296,13,9,Design.Muted)
  local title=label(card,"Title","Disconnect Spotify?",62,31,296,24,18,Design.Ink);title.FontFace=medium
  local rule=frame(card,"BodyRule",20,66,340,1,Design.Edge)
  rule.BackgroundTransparency=.92;rule:SetAttribute("AltairDesignRole","divider")
  local body=label(card,"Description","",20,82,340,60,13,Design.Muted)
  body.TextWrapped=true;body.TextTruncate=Enum.TextTruncate.None;body.TextYAlignment=Enum.TextYAlignment.Top
  local state={version=0,open=false,alive=true,tweens={}}
  local prompt={};local controls={}
  local function cancelTweens()
   for animation in pairs(state.tweens)do animation:Cancel()end;table.clear(state.tweens)
  end
  local function animate(object,time,goal,style)
   local animation=tweenService:Create(object,TweenInfo.new(time,style or Enum.EasingStyle.Quart,Enum.EasingDirection.Out),goal)
   state.tweens[animation]=true
   animation.Completed:Once(function()state.tweens[animation]=nil end)
   animation:Play();return animation
  end
  local function fittedScale()
   local size=root.AbsoluteSize
   return math.max(.25,math.min(root:GetAttribute("AltairPreferredScale")or root:GetAttribute("AltairDisplayScale")or 1,
    (math.max(1,size.X)-32)/width,(math.max(1,size.Y)-32)/height))
  end
  local function opacity()
   return Design.opacityAlpha(.12,root:GetAttribute("AltairPanelTransparency")or .1)
  end
  local function present(open)
   state.version+=1;state.open=open;cancelTweens()
   local version=state.version;local base=fittedScale();local cold=not overlay.Visible
   if open then
    if cold then scrim.BackgroundTransparency=1;card.GroupTransparency=1;scale.Scale=base*.965 end
    backdrop.BackgroundTransparency=opacity();overlay.Visible=true;card.Interactable=true
    for _,control in ipairs(controls)do
     animate(control.object,.14,{BackgroundTransparency=.08});animate(control.rim,.14,{Transparency=.9});animate(control.scale,.18,{Scale=1})
    end
    animate(scrim,.18,{BackgroundTransparency=.58});animate(card,.2,{GroupTransparency=0})
    animate(scale,.24,{Scale=base},Enum.EasingStyle.Back)
   else
    card.Interactable=false
    animate(scrim,.18,{BackgroundTransparency=1});animate(card,.18,{GroupTransparency=1})
    animate(scale,.21,{Scale=base*.975})
    task.delay(.22,function()if state.alive and state.version==version then overlay.Visible=false end end)
   end
   return version,cold
  end
  function prompt:Resolve(confirmed)
   local action=controller.pendingDisconnect
   if not action or not controller.alive or not state.alive then return false end
   controller.pendingDisconnect=nil;present(false)
   if confirmed then action()end
   return true
  end
  local function control(name,text,x,w,color,action)
   local object=make("TextButton",card,{Name=name,Text=text,Position=UDim2.fromOffset(x,166),Size=UDim2.fromOffset(w,38),
    BackgroundColor3=color,BackgroundTransparency=.08,BorderSizePixel=0,AutoButtonColor=false,TextSize=13,FontFace=medium,TextColor3=Design.Ink,ZIndex=652})
   corner(object,9);object:SetAttribute("AltairDesignRole","control")
   local rim=make("UIStroke",object,{Name="UIStroke",Color=Design.Edge,Transparency=.9,Thickness=.6,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
   local feedback=make("UIScale",object,{Name="ButtonFeedback",Scale=1})
   controls[#controls+1]={object=object,rim=rim,scale=feedback}
   connect(object.Activated,action)
   connect(object.MouseEnter,function()if not state.open then return end;animate(object,.14,{BackgroundTransparency=0});animate(rim,.14,{Transparency=.65})end)
   connect(object.MouseLeave,function()animate(object,.18,{BackgroundTransparency=.08});animate(rim,.18,{Transparency=.9});animate(feedback,.2,{Scale=1})end)
   connect(object.MouseButton1Down,function()if state.open then animate(feedback,.09,{Scale=.97})end end)
   connect(object.MouseButton1Up,function()animate(feedback,.23,{Scale=1},Enum.EasingStyle.Back)end)
   return object
  end
  control("Cancel","Cancel",20,164,Design.Raised,function()prompt:Resolve(false)end)
  local confirm=control("Confirm","Disconnect",192,168,Color3.fromRGB(118,42,48),function()prompt:Resolve(true)end)
  for _,object in ipairs(card:GetDescendants())do if object:IsA("GuiObject")and object~=backdrop then object.ZIndex=652 end end
  local function copy(pauseOnly,version,cold)
   local heading=pauseOnly and "Pause Spotify connection?"or"Disconnect Spotify?"
   local description=pauseOnly and "Stop Spotify updates in Altair? Your saved account link will remain available when you turn it back on."
    or"Remove this computer's saved Spotify link? Desktop playback can be connected again; Web API playback will need browser approval."
   local caption=pauseOnly and "Pause connection"or"Disconnect"
   local function apply()
    title.Text=heading;body.Text=description;confirm.Text=caption
    animate(title,.12,{TextTransparency=0});animate(body,.12,{TextTransparency=0});animate(confirm,.12,{TextTransparency=0})
   end
   if not cold and(title.Text~=heading or body.Text~=description or confirm.Text~=caption)then
    animate(title,.07,{TextTransparency=1});animate(body,.07,{TextTransparency=1});animate(confirm,.07,{TextTransparency=1})
    task.delay(.075,function()if state.alive and state.open and state.version==version then apply()end end)
   else apply()end
  end
  function prompt:Show(action,pauseOnly)
   if not state.alive or not controller.alive or type(action)~="function"then return false end
   controller.pendingDisconnect=action
   local version,cold=present(true);copy(pauseOnly,version,cold)
   return true
  end
  function prompt:Destroy()
   if not state.alive then return end
   state.alive=false;state.version+=1;controller.pendingDisconnect=nil;cancelTweens();overlay:Destroy()
  end
  connect(overlay.Activated,function()prompt:Resolve(false)end)
  connect(input.InputBegan,function(event)if event.KeyCode==Enum.KeyCode.Escape then prompt:Resolve(false)end end)
  connect(root:GetPropertyChangedSignal("AbsoluteSize"),function()if state.open then animate(scale,.18,{Scale=fittedScale()})end end)
  connect(root:GetAttributeChangedSignal("AltairPreferredScale"),function()if state.open then animate(scale,.18,{Scale=fittedScale()})end end)
  connect(root:GetAttributeChangedSignal("AltairPanelTransparency"),function()if state.open then animate(backdrop,.18,{BackgroundTransparency=opacity()})end end)
  return prompt
 end)()
 function controller:ResolveSpotifyDisconnect(confirmed)return unlinkPrompt:Resolve(confirmed==true)end
 function controller:ConfirmSpotifyDisconnect(action,pauseOnly)return unlinkPrompt:Show(action,pauseOnly)end

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
		if action=="seek"and self.navigationPending then notifyError("The track is changing. Seeking will be available after playback updates.");return false end
		if action=="seek" or action=="volume" then
			if type(value)~="number" or value~=value or math.abs(value)==math.huge then return false end
			if action=="seek" and (self.media.duration or 0)<=0 then return false end
			value=math.clamp(value,0,action=="seek" and self.media.duration or 1)
		end
		local previous=table.clone(self.media)
		previous.progress=math.min(previous.duration or 0,(previous.progress or 0)+(previous.playing and os.clock()-self.mediaAt or 0))
		if not self:Enqueue("control",{action=action,value=value},previous) then return false end
        self.fastPollUntil=os.clock()+2.5
        if action=="next"or action=="previous"then self.trackDirection=action=="next"and 1 or -1;if self.AnimateTrack then self:AnimateTrack(self.trackDirection,false)end end
		local optimistic=table.clone(previous)
		if action=="seek" then optimistic.progress=value
		elseif action=="volume" then optimistic.volume=value
		elseif action=="toggle" then optimistic.playing=not optimistic.playing end
		self:SetMedia(optimistic)
		return true
	end
	function controller:SetMedia(state,freshObservation)
		if type(state)~="table" then return end
        if state.linked and state.available==false then
         local merged=table.clone(self.media or{})
         if freshObservation==true then
          -- Preserve cached track details during an outage, but not the old
          -- observation's playback, permission or error state. Missing fields
          -- in a fresh snapshot clear those values instead of reviving them.
          for _,key in ipairs({"connected","linked","available","playing","source","status","message",
           "reauth_required","web_reauth_required","stale","retry_after","web_retry_after","controls"})do merged[key]=nil end
         end
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
  local identifier=state.trackId or state.track_id or state.uri
  local identity=identifier~=nil and tostring(identifier)~=""and tostring(identifier)or(state.title.."\n"..state.artist.."\n"..math.floor(state.duration))
  local navigation=self.navigationPending
  if navigation and navigation.completedAt and freshObservation==true and state.available~=false then
   if identity~=navigation.identity or os.clock()>=navigation.expiresAt then self.navigationPending=nil
   else self.nextPoll=math.min(self.nextPoll,os.clock()+.15)end
  end
  if identity~=self.mediaIdentity then
   self.trackRevision=(self.trackRevision or 0)+1
   if self.cancelSeek then self.cancelSeek("track")end
   self.seekPreview=nil;self.mediaIdentity=identity
  end
		local trackChanged=self.media.title~=state.title and self.media.title~="Spotify"
        self.media,self.mediaAt=state,os.clock()
        if trackChanged and self.AnimateTrack then self:AnimateTrack(self.trackDirection or 1,true)end
        if self.ApplyPalette then self:ApplyPalette(state.palette)end
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
 local mediaSliders={}
 controller.rulerSliders={};controller.linearSliders={}
 local function refreshSliderInteraction()
  local busy=controller.pickerDrag~=nil
  for _,state in ipairs(mediaSliders)do if state.IsDragging()then busy=true;break end end
  controller.dragging=busy
 end
	controller.cancelDrag=function() for _,cancel in ipairs(dragCancels) do cancel() end;controller.seekPreview=nil end
	local function slider(parent,name,x,y,w,h,color,callback)
  local seeking=name=="Seek";local owner=parent==music and "music"or "center"
  local bar=frame(parent,name,x,y,w,h,Color3.fromRGB(43,43,44),h/2);bar.ClipsDescendants=true
  local fill=frame(bar,"Fill",0,0,0,h);fill.ClipsDescendants=true
  frame(fill,"Color",0,0,w,h,color,h/2)
  local hit=button(bar,"Input","",0,0,w,h,nil,function()end);hit:SetAttribute("NoHover",true)
  local level
  if not seeking then
   level=label(bar,"Level","0%",5,8,w-10,14,8,white);level.Size=UDim2.new(1,-10,0,14);level.TextXAlignment=Enum.TextXAlignment.Center;level.FontFace=medium;level.ZIndex=bar.ZIndex+2
   level.BackgroundColor3=Design.Surface;level.BackgroundTransparency=.18;corner(level,4)
   level:SetAttribute("AltairDesignRole","control");level:SetAttribute("AltairDesignManaged",true);level:SetAttribute("AltairThemeIgnore",true)
  end
   local dragging,lastPosition=false,nil
   local visibilityConnections={}
  local state={bar=bar,fill=fill,Input=hit,value=0,maximum=seeking and 1 or 100,seek=seeking,owner=owner}
  state.IsDragging=function()return dragging~=false end
  local function shown()
    if not controller.alive or controller.view~=owner or not bar.Parent
     or(seeking and(not controller.media.connected or(controller.media.duration or 0)<=0 or controller.navigationPending))then return false end
    local object=bar
    while object do
     if object:IsA("GuiObject")and not object.Visible then return false
     elseif object:IsA("ScreenGui")then return object.Enabled end
     object=object.Parent
    end
    return false
  end
  function state:Set(ratio,animate,total)
   self.value=math.clamp(tonumber(ratio)or 0,0,1)
   self.maximum=seeking and math.max(1,tonumber(total)or controller.media.duration or 1)or 100
   if level then set(level,"Text",tostring(math.floor(self.value*100+.5)).."%")end
   local size=bar:GetAttribute("AltairVertical")and UDim2.fromScale(1,self.value)or UDim2.fromScale(self.value,1)
   if animate then tween(fill,.12,{Size=size})else fill.Size=size end
  end
  function state:Cancel()
   dragging=false;self.session=nil
    for _,connection in ipairs(visibilityConnections)do connection:Disconnect()end;table.clear(visibilityConnections)
   if seeking then controller.seekPreview=nil end
   refreshSliderInteraction()
  end
  local function ratio(position)
   if bar:GetAttribute("AltairVertical")then return math.clamp(1-(position.Y+root.AbsolutePosition.Y-bar.AbsolutePosition.Y)/math.max(1,bar.AbsoluteSize.Y),0,1)end
   return math.clamp((position.X+root.AbsolutePosition.X-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1)
  end
  local function move(position,finished)
   if not shown()or not state.session or(seeking and state.session.revision~=(controller.trackRevision or 0))then state:Cancel();return end
   lastPosition=position;state:Set(ratio(position),false);callback(state.value,finished)
  end
  dragCancels[#dragCancels+1]=function()state:Cancel()end
  mediaSliders[#mediaSliders+1]=state;controller.linearSliders[#controller.linearSliders+1]=state
  connect(hit.InputBegan,function(event)
   if dragging or not shown()then return end
   if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
    dragging=event;state.session={revision=controller.trackRevision or 0};refreshSliderInteraction()
     local ancestor=bar
     while ancestor do
      local property=ancestor:IsA("GuiObject")and"Visible"or ancestor:IsA("ScreenGui")and"Enabled"
      if property then visibilityConnections[#visibilityConnections+1]=ancestor:GetPropertyChangedSignal(property):Connect(function()if not shown()then state:Cancel()end end)end
      ancestor=ancestor.Parent
     end
    move(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation(),false)
   end
  end)
  connect(input.InputChanged,function(event)
   if dragging and(event==dragging or(dragging.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseMovement))then
    move(event.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation(),false)
   end
  end)
  connect(input.InputEnded,function(event)
   if dragging and(event==dragging or(dragging.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseButton1))then
    local position=dragging.UserInputType==Enum.UserInputType.Touch and event.Position or input:GetMouseLocation()
     dragging=false;move(position or lastPosition,true);state:Cancel()
   end
  end)
  connect(input.WindowFocusReleased,function()state:Cancel()end)
  return state
	end
 controller.cancelSeek=function(reason)for _,state in ipairs(mediaSliders)do if state.seek then state:Cancel(reason)end end end
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
            connect(parent.MouseButton1Down,function()tween(glyph,.08,{Position=UDim2.new(.5,kind=="next"and 3 or -3,.5,0)})end)
            connect(parent.MouseButton1Up,function()tween(glyph,.24,{Position=UDim2.fromScale(.5,.5)},Enum.EasingStyle.Back)end)
            connect(parent.MouseLeave,function()tween(glyph,.2,{Position=UDim2.fromScale(.5,.5)})end)
		else play.Visible=kind=="play";pause.Visible=kind=="pause" end
        local playScale=make("UIScale",play,{Name="GlyphScale",Scale=1})
        local pauseScale=make("UIScale",pause,{Name="GlyphScale",Scale=1})
        play.AnchorPoint=Vector2.new(.5,.5);play.Position=UDim2.fromScale(.5,.5)
        pause.AnchorPoint=Vector2.new(.5,.5);pause.Position=UDim2.fromScale(.5,.5)
        local last=kind=="pause";local generation=0
		return function(playing)
         playing=playing==true;if last==playing then return end;last=playing;generation+=1;local current=generation
         local incoming,outgoing=playing and pause or play,playing and play or pause
         local incomingScale,outgoingScale=playing and pauseScale or playScale,playing and playScale or pauseScale
         incoming.Visible=true;outgoing.Visible=true;incomingScale.Scale=.4;incoming.Rotation=playing and -22 or 22;incoming.ImageTransparency=.5
         tween(incomingScale,.24,{Scale=1},Enum.EasingStyle.Back)
         tween(incoming,.2,{Rotation=0,ImageTransparency=0})
         tween(outgoingScale,.16,{Scale=.25});tween(outgoing,.16,{Rotation=playing and 22 or -22,ImageTransparency=1})
         task.delay(.2,function()if controller.alive and current==generation then outgoing.Visible=false end end)
        end
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
		-- Keep the reference track thin while preserving a forgiving hit target.
		seek.bar.ClipsDescendants=false
		seek.Input.Size=UDim2.new(1,0,0,16);seek.Input.Position=UDim2.fromOffset(0,-6)
		local elapsed=label(group,"Elapsed","0:00",11,54,65,12,9,gray)
		local duration=label(group,"Duration","--:--",w-76,54,65,12,9,gray);duration.TextXAlignment=Enum.TextXAlignment.Right
		playbackGlyph(previous,"previous",white);playbackGlyph(nextButton,"next",white)
		playerViews[#playerViews+1]={group=group,title=title,artist=artist,play=play,renderPlay=playbackGlyph(play,"play",white),seek=seek,elapsed=elapsed,duration=duration}
	end
    controller.trackRest=setmetatable({}, {__mode="k"})
 function controller:AnimateTrack(direction,arriving)
  self.trackAnimationVersion=(self.trackAnimationVersion or 0)+1;local version=self.trackAnimationVersion
  for _,player in ipairs(playerViews)do
   for _,object in ipairs({player.title,player.artist})do
    local rest=self.trackRest[object]or object.Position;self.trackRest[object]=rest
    if arriving then
     object.Position=rest+UDim2.fromOffset(direction*18,0)
     tween(object,.3,{Position=rest},Enum.EasingStyle.Quart)
    else
     tween(object,.1,{Position=rest+UDim2.fromOffset(-direction*5,0)})
     task.delay(.11,function()if self.alive and object.Parent and self.trackAnimationVersion==version then tween(object,.3,{Position=rest},Enum.EasingStyle.Back)end end)
    end
   end
  end
 end
	local originalBrightness=lighting.Brightness
	local brightnessChanged=false;local ownedBrightness
	local brightness=slider(center,"Brightness",11,71,136,22,white,function(value)
		brightnessChanged=true;lighting.Brightness=value*3;ownedBrightness=lighting.Brightness
	end)
	icon(center,"BrightnessIcon","sun",20,77,12,Color3.fromRGB(194,148,35))
	brightness:Set(math.clamp(originalBrightness/3,0,1),false)
	local volume=slider(center,"SpotifyVolume",153,71,136,22,white,function(value,finished)
		if finished then controller:Control("volume",value) end
	end)
	local speaker=icon(center,"VolumeIcon","volume-2",163,77,12,gray)
	local mute=icon(center,"VolumeMute","volume-x",163,77,12,gray)
	local timerSummary,timerCancel
	-- Timer setup extends the current control centre; it never opens a second shell.
	duration:SetAttribute("AltairInlineView",true)
	duration.Parent=center;duration.Position=UDim2.fromOffset(0,180);duration.Size=UDim2.fromOffset(300,64)
	duration.Visible=false;duration.GroupTransparency=1
	controller.timerDraft=300
	local timerEntry=make("TextBox",duration,{Name="Duration",Text="05:00",ClearTextOnFocus=false,
		Position=UDim2.fromOffset(11,32),Size=UDim2.fromOffset(278,30),BackgroundTransparency=1,
		TextColor3=amber,TextSize=24,FontFace=medium,TextXAlignment=Enum.TextXAlignment.Center,Visible=false})
	local divider=frame(duration,"Divider",11,0,278,1,white);divider.BackgroundTransparency=.94
	local draftReadout=label(duration,"DraftReadout","05:00",222,5,67,17,13,amber);draftReadout.TextXAlignment=Enum.TextXAlignment.Center;draftReadout.FontFace=medium
	local durationControl,startTimer
	local function syncDraft()
		if input:GetFocusedTextBox()~=timerEntry then timerEntry.Text=Clock.Format(controller.timerDraft,false,true) end
  draftReadout.Text=Clock.Format(controller.timerDraft,false,true)
  if startTimer then startTimer.Text="Start "..(controller.timerDraft%60==0 and tostring(controller.timerDraft/60).."min"or Clock.Format(controller.timerDraft,false,true))end
  if durationControl and not durationControl.IsDragging()then durationControl:Sync(false)end
	end
	function controller:SetTimerDraft(seconds)
		if type(seconds)~="number" or seconds~=seconds then return end
		self.timerDraft=math.clamp(math.floor(seconds+.5),1,86400);syncDraft()
	end
	local pickerRuler=frame(duration,"Ruler",11,5,202,43);pickerRuler.ClipsDescendants=false
	local rulerInput=button(pickerRuler,"Input","",0,0,202,43,nil,function()end);rulerInput:SetAttribute("NoHover",true);rulerInput.Visible=false;rulerInput.Active=false;rulerInput.Interactable=false
	local durationHint=label(duration,"Hint","Drag minutes · tap for seconds",11,49,202,12,9,gray);durationHint.TextXAlignment=Enum.TextXAlignment.Center
 if not context.BuildOnly then
  durationControl={bar=pickerRuler,held=false}
  durationControl.IsDragging=function()local r=durationControl.ruler;return durationControl.held or r and(r:IsDragging()or r:IsCoasting()or r.InputStage=="snap")or false end
  function durationControl:Cancel()
   self.held=false;controller.pickerDrag=nil
   if self.ruler then self.ruler:Cancel(true)end;refreshSliderInteraction()
  end
  function durationControl:Sync(animated)
   if not self.ruler then return end
   local value=controller.timerDraft
   if self.ruler.suspended or math.abs(self.ruler:GetValue()-value)>1e-5 then self.ruler:Set(value,animated==true)end
  end
  function durationControl:ApplyStyle(animated)
   if not self.ruler then return end
   local precision=self.ruler.precision
   self.ruler:Configure({Range={1,86400},Value=controller.timerDraft,Step=60,TickStep=60,PrecisionStep=1,PrecisionZoom=60,PrecisionLabel="",SnapOrigin=0,
    Color=Color3.fromRGB(240,158,30),FutureColor=Color3.fromRGB(76,52,17),MarkerColor=Color3.fromRGB(180,126,42),Animate=animated==true})
   if controller.picker and controller.view=="center"then self.ruler:SetPrecision(precision,false)else self.ruler:Cancel(true)end
  end
  local function allowed()return controller.alive and controller.picker and controller.view=="center"and duration.Visible end
  local function capture()
   controller.dragging=true
  end
  durationControl.ruler=buildRuler(pickerRuler,{Name="RulerControl",Skin="Altair",Range={1,86400},Value=300,Step=60,TickStep=60,PrecisionStep=1,PrecisionZoom=60,PrecisionLabel="",SnapOrigin=0,Scale=.4,PoolLimit=96,Size=UDim2.fromScale(1,1),CanInteract=allowed,
   OnChanged=function(value)
    if not allowed()then return end
    controller:SetTimerDraft(value);refreshSliderInteraction()
   end,
   OnCommit=function()
    durationControl.held=false;syncDraft();refreshSliderInteraction()
   end,
  })
  connect(durationControl.ruler.Zoom.Changed,function(zoom)
   durationHint.Text=zoom>1.01 and"Drag seconds · tap for minutes"or"Drag minutes · tap for seconds"
  end)
  durationControl:ApplyStyle(false)
  connect(durationControl.ruler.Input.InputBegan,function(event)
   if allowed()and(event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)then durationControl.held=event;capture()end
  end)
  connect(input.InputEnded,function(event)local held=durationControl.held;if held and(held==event or(held.UserInputType==Enum.UserInputType.MouseButton1 and event.UserInputType==Enum.UserInputType.MouseButton1))then durationControl.held=false;refreshSliderInteraction()end end)
  connect(input.WindowFocusReleased,function()durationControl:Cancel()end)
  dragCancels[#dragCancels+1]=function()durationControl:Cancel()end
  mediaSliders[#mediaSliders+1]=durationControl;controller.rulerSliders[#controller.rulerSliders+1]=durationControl;controller.timerRuler=durationControl
 end
	function controller:EndTimerEntry(start,closingShell)
  self.timerEntryGeneration=(self.timerEntryGeneration or 0)+1;local generation=self.timerEntryGeneration
  if durationControl then durationControl:Cancel()end
		self.picker=false;self.pickerDrag=nil;refreshSliderInteraction()
		if input:GetFocusedTextBox()==timerEntry then timerEntry:ReleaseFocus() end
		if start then clock:StartTimer(self.timerDraft) end
		self.hoverLeftAt=nil
  if closingShell then sizes.center=Vector2.new(300,180)end
  tween(duration,.10,{GroupTransparency=1})
  task.delay(.12,function()
   if not self.alive or generation~=self.timerEntryGeneration or self.picker then return end
   duration.Visible=false;if not closingShell then self:SetViewSize("center",Vector2.new(300,180),.28)end
  end)
	end
	function controller:BeginTimerEntry()
  self.timerEntryGeneration=(self.timerEntryGeneration or 0)+1
		self.picker=true;self.hoverLeftAt=nil
		self:SetTimerDraft(clock.timer and clock:Remaining() or self.timerDraft)
		self:Open("center");self:SetViewSize("center",Vector2.new(300,244),.30)
  duration.Visible=true;duration.GroupTransparency=1;tween(duration,.16,{GroupTransparency=0})
  if durationControl then durationControl:Sync(false)end
	end
	startTimer=button(duration,"Start","Start 5min",222,26,67,27,amber,function() controller:EndTimerEntry(true) end)
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
	local timerTile=button(center,"TimerTile","",11,102,136,33,controlColor,function()
		if controller.picker then controller:EndTimerEntry(false)elseif clock.timer then controller:Open("timer") else controller:BeginTimerEntry() end
	end)
	label(timerTile,"Label","Timer",10,3,90,12,9,gray)
	timerSummary=label(timerTile,"Value","Set",10,15,90,15,12,white);timerSummary.FontFace=medium
	timerCancel=button(timerTile,"Cancel","",110,7,20,20,Color3.fromRGB(40,40,41),function()if controller.picker then controller:EndTimerEntry(false)else clock:CancelTimer()end end)
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
		accentOutlines[#accentOutlines+1]=make("UIStroke",tile,{Name="InsetOutline",Color=Design.Edge,Thickness=.6,
			Transparency=.92,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
	end
	local timerTitle=label(timer,"Title","Timer",11,8,100,12,9,gray)
	local timerTime=label(timer,"Time","05:00",11,22,120,21,18,amber);timerTime.FontFace=medium
	local function canToggleTimer()
		local current=clock.timer
		return current~=nil and not current.finished and clock:Remaining()>0
	end
	local timerPause=button(timer,"Pause","Ⅱ",153,11,22,22,Color3.fromRGB(65,45,7),function()if canToggleTimer()then clock:ToggleTimer()end end)
	timerPause.TextColor3=amber;timerPause.TextSize=15
	timerPause.Active=false;timerPause.Interactable=false;timerPause.Selectable=false;timerPause.Visible=false
	local renderTimerPause=playbackGlyph(timerPause,"pause",amber)
 local function closeStoppedActivity()
  local factor=math.max(.01,scale.Scale);local source=menuPill
  controller.origin={x=(source.AbsolutePosition.X+source.AbsoluteSize.X/2-host.AbsolutePosition.X)/factor,y=(source.AbsolutePosition.Y-host.AbsolutePosition.Y)/factor,width=24,source=source}
  controller:Open(nil)
 end
	local timerClose=button(timer,"Cancel","",179,11,22,22,Color3.fromRGB(35,35,36),function() clock:CancelTimer();closeStoppedActivity() end)
	icon(timerClose,"Close","x",6,6,10,white)
	local ruler=frame(timer,"Ruler",11,51,186,10);ruler.ClipsDescendants=true
	local rulerStrip=frame(ruler,"Ticks",0,0,230,10)
	for index=0,60 do
  local tick=frame(rulerStrip,"Tick"..index,index*3.7,index%5==0 and 2 or 3,2,index%5==0 and 6 or 4,amber,1)
  tick:SetAttribute("AltairDesignRole","indicator")
 end
	label(watch,"Title","Stopwatch",11,8,100,12,9,gray)
	local watchTime=label(watch,"Time","00:00",11,22,100,21,18,green);watchTime.FontFace=medium
	local fraction=label(watch,"Fraction",".00",68,27,40,14,11,green)
	local lapButton=button(watch,"Lap","Lap",130,11,43,22,Color3.fromRGB(42,42,43),function()
		if clock.watch.started then clock:Lap() else clock:ResetWatch();closeStoppedActivity() end
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
  lapRows[index].bar:SetAttribute("AltairDesignRole","indicator")
		lapRows[index].value.TextXAlignment=Enum.TextXAlignment.Right
	end
    if context.BuildOnly then
     music.Artwork.Position=UDim2.fromOffset(12,12);music.Artwork.Size=UDim2.fromOffset(60,60)
     music.Note.Position=UDim2.fromOffset(33,33);music.Note.Size=UDim2.fromOffset(18,18)
     music.Title.Position=UDim2.fromOffset(84,16);music.Title.Size=UDim2.fromOffset(152,26);music.Title.TextSize=12
     music.Artist.Position=UDim2.fromOffset(84,43);music.Artist.Size=UDim2.fromOffset(152,26);music.Artist.TextWrapped=true
     for index,name in ipairs({"Previous","PlayPause","Next"})do music[name].Position=UDim2.fromOffset(96+(index-1)*52,76)end
     music.Seek.Position=UDim2.fromOffset(12,104);music.Seek.Size=UDim2.fromOffset(224,4)
     music.Elapsed.Position=UDim2.fromOffset(12,112);music.Duration.Position=UDim2.fromOffset(171,112)
     timer.Time.Position=UDim2.fromOffset(12,30);timer.Time.Size=UDim2.fromOffset(130,32);timer.Time.TextSize=24
     timer.Pause.Position=UDim2.fromOffset(155,30);timer.Cancel.Position=UDim2.fromOffset(190,30)
     timer.Ruler.Position=UDim2.fromOffset(12,79);timer.Ruler.Size=UDim2.fromOffset(200,10)
     watch.Time.Position=UDim2.fromOffset(12,30);watch.Time.Size=UDim2.fromOffset(120,32);watch.Time.TextSize=24
     watch.Fraction.Position=UDim2.fromOffset(80,42)
     watch.Lap.Position=UDim2.fromOffset(132,32);watch.Pause.Position=UDim2.fromOffset(188,32)
     watch.Empty.Position=UDim2.fromOffset(12,83)
     for index=1,3 do watch["Lap"..index].Position=UDim2.fromOffset(12,82+(index-1)*13)end
    end
    -- Control Centre-inspired asymmetric grid: a media tile and two tall faders.
 local mediaShelf=frame(center,"MediaShelf",10,10,180,118,controlColor,12)
 mediaShelf.BackgroundTransparency=.1
 if context.BuildOnly then
  for _,name in ipairs({"Artwork","Note","Title","Artist","Previous","PlayPause","Next","Seek","Elapsed","Duration"})do
   local object=center:FindFirstChild(name)
   if object then object.Parent=mediaShelf end
  end
  mediaShelf.Artwork.Position=UDim2.fromOffset(12,10);mediaShelf.Artwork.Size=UDim2.fromOffset(32,32)
  mediaShelf.Note.Position=UDim2.fromOffset(21,19)
  mediaShelf.Title.Position=UDim2.fromOffset(12,49);mediaShelf.Title.Size=UDim2.fromOffset(156,14)
  mediaShelf.Artist.Position=UDim2.fromOffset(12,65);mediaShelf.Artist.Size=UDim2.fromOffset(156,12)
  for index,name in ipairs({"Previous","PlayPause","Next"})do mediaShelf[name].Position=UDim2.fromOffset(27+(index-1)*54,89)end
  mediaShelf.Seek.Position=UDim2.fromOffset(12,82);mediaShelf.Seek.Size=UDim2.fromOffset(156,3)
  mediaShelf.Elapsed.Visible=false;mediaShelf.Duration.Visible=false
  for index,name in ipairs({"Brightness","SpotifyVolume"})do
   local bar=center[name];local fill=bar.Fill
   bar.Position=UDim2.fromOffset(200+(index-1)*46,10);bar.Size=UDim2.fromOffset(38,118)
   bar.UICorner.CornerRadius=UDim.new(0,12);bar:SetAttribute("AltairVertical",true)
   fill.AnchorPoint=Vector2.new(0,1);fill.Position=UDim2.fromScale(0,1)
   fill.Size=UDim2.fromScale(1,index==1 and math.clamp(originalBrightness/3,0,1)or 0)
   fill.Color.AnchorPoint=Vector2.new(0,1);fill.Color.Position=UDim2.fromScale(0,1);fill.Color.Size=UDim2.fromOffset(38,118)
   fill.Color.UICorner.CornerRadius=UDim.new(0,12);bar.Input.Size=UDim2.fromScale(1,1)
  end
  center.BrightnessIcon.Position=UDim2.fromOffset(213,105)
  center.VolumeIcon.Position=UDim2.fromOffset(259,105);center.VolumeMute.Position=center.VolumeIcon.Position
  for _,name in ipairs({"TimerTile","WatchTile"})do center[name].Position+=UDim2.fromOffset(0,34)end
 end
 inner:SetAttribute("AltairInsetMaterial",true);inner.BackgroundTransparency=1
 innerStroke:SetAttribute("AltairInsetOutline",true);innerStroke.Transparency=1

 for index,tile in ipairs({timerTile,watchTile})do
  tile:SetAttribute("AltairInsetSurface",true)
  tile:SetAttribute("AltairDesignRole","inset")
  tile.BackgroundColor3=tile:GetAttribute("AltairTheme_BackgroundColor3")or controlColor
  tile.BackgroundTransparency=.1;tile.TileGradient.Enabled=false
  tile.UICorner.CornerRadius=UDim.new(0,9);tile.Size=UDim2.fromOffset(136,36)
  tile.Label.Position=UDim2.fromOffset(38,4);tile.Value.Position=UDim2.fromOffset(38,17)
  local badge=frame(tile,"UtilityAccent",6,6,24,24,white,7)
  barTile(badge,index==1 and "Scripts"or "Character")
  icon(badge,"UtilitySymbol",index==1 and "timer"or "play",5,5,14,white)
 end
 local utilityDivider=frame(center,"UtilityDivider",11,132,278,1,Design.Edge);utilityDivider.BackgroundTransparency=.92;utilityDivider:SetAttribute("AltairDesignRole","divider")
 -- Dark album-derived materials stay legible independently of interface lightness.
 mediaShelf:SetAttribute("AltairThemeIgnore",true);music:SetAttribute("AltairThemeIgnore",true)
 mediaShelf.BackgroundColor3=white
 local albumBackdrop=frame(music,"AlbumBackdrop",0,0,248,132,white,18);albumBackdrop.ZIndex=music.ZIndex-1;albumBackdrop.BackgroundTransparency=.1
 local albumGradient=make("UIGradient",albumBackdrop,{Name="AlbumGradient",Rotation=18,Color=ColorSequence.new(Design.Surface,Design.Raised)})
 local shelfGradient=make("UIGradient",mediaShelf,{Name="AlbumGradient",Rotation=0,Color=albumGradient.Color})
 controller.albumColors={Design.Surface,Design.Raised}
 controller.albumTargets=table.clone(controller.albumColors)
 function controller:ApplyPalette(palette)
  local valid=type(palette)=="table"and type(palette[1])=="table"and type(palette[2])=="table"
  local colors={}
  if valid then for index=1,2 do
   local rgb=palette[index]
   for channel=1,3 do if type(rgb[channel])~="number"or rgb[channel]~=rgb[channel]or rgb[channel]<0 or rgb[channel]>255 then valid=false;break end end
   if not valid then break end
   local h,s,v=Color3.fromRGB(rgb[1],rgb[2],rgb[3]):ToHSV()
   colors[index]=Color3.fromHSV(h,s*.72,math.clamp(v*(index==1 and .11 or .4),index==1 and .035 or .09,.4))
  end end
  self.albumTargets=valid and colors or {Design.Surface,Design.Raised}
  musicVisual.Back.TileGradient:SetAttribute("AltairAlbumDriven",valid)
  if not valid and smartBar then musicVisual.Back.TileGradient.Color=smartBar.Back.Buttons.Playerlist.UIGradient.Color end
 end
 function controller:StepAlbum(dt)
  local alpha=1-math.exp(-10*math.min(dt,.1));local changed=false
  for index=1,2 do
   local current,target=self.albumColors[index],self.albumTargets[index]
   if math.abs(current.R-target.R)+math.abs(current.G-target.G)+math.abs(current.B-target.B)>.001 then self.albumColors[index]=current:Lerp(target,alpha);changed=true end
  end
  if changed then
   local first,second=self.albumColors[1],self.albumColors[2]
   local gradient=ColorSequence.new(first,second)
   albumGradient.Color=gradient;shelfGradient.Color=gradient
   if musicVisual.Back.TileGradient:GetAttribute("AltairAlbumDriven")then musicVisual.Back.TileGradient.Color=gradient end
   local p=self.presentation;if p and p.source==musicPill then p.original.gradient=gradient;p.dirty=true end
  end
 end
  controller.placement=capsulePlacement(context,controller,root,host,scale,compact,surface)
 local placement=controller.placement
 local dragHandle=root:FindFirstChild("Drag")
 if dragHandle and dragHandle:FindFirstChild("Interact")then
  connect(dragHandle.Interact.MouseEnter,function()if controller.docked then placement:HoverBar(true)end end)
  connect(dragHandle.Interact.MouseLeave,function()placement:HoverBar(false)end)
 end
 function controller:Reveal()placement:Reveal()end
 function controller:Retract()placement:Retract()end
 -- One bounded animation owns the drop and the centre-out handle ripple.
 local dragVisual=dragHandle and dragHandle:FindFirstChild("Drag")
 local ripple=dragVisual and make("Frame",dragVisual,{Name="CapsuleRipple",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ClipsDescendants=true,ZIndex=dragVisual.ZIndex+2})
 local wave=ripple and make("Frame",ripple,{Name="Wave",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(0,1),BackgroundColor3=white,BackgroundTransparency=1,BorderSizePixel=0,ZIndex=ripple.ZIndex})
 if wave then
  wave:SetAttribute("AltairThemeIgnore",true);corner(wave,8)
  make("UIGradient",wave,{Name="Wavefront",Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.12,0),NumberSequenceKeypoint.new(.5,1),NumberSequenceKeypoint.new(.88,0),NumberSequenceKeypoint.new(1,1)})})
 end
 local reaction=dragVisual and make("UIScale",dragVisual,{Name="CapsuleReaction",Scale=1})
 local rippleProgress=make("NumberValue",root,{Name="CapsuleRippleProgress",Value=1})
 connect(rippleProgress.Changed,function(value)root:SetAttribute("AltairCapsuleRippleProgress",value)end)
 function controller:ReactDrag(preparing)
  if not reaction or root:GetAttribute("AltairReduceMotion")then return end
  self.reactionGeneration=(self.reactionGeneration or 0)+1;local generation=self.reactionGeneration
  tween(reaction,preparing and .18 or .1,{Scale=preparing and .98 or 1.065},Enum.EasingStyle.Back)
  if not preparing then task.delay(.22,function()if self.alive and self.reactionGeneration==generation then tween(reaction,.36,{Scale=1},Enum.EasingStyle.Back)end end)end
 end
 function controller:PulseDrag()
  if not wave or not wave.Parent then return end
  if self.waveTween then self.waveTween:Cancel()end
  if self.rippleTween then self.rippleTween:Cancel()end
  local vertical=dragVisual.AbsoluteSize.Y>dragVisual.AbsoluteSize.X
  wave.Wavefront.Rotation=vertical and 90 or 0
  wave.Size=vertical and UDim2.fromScale(1,0)or UDim2.fromScale(0,1)
  wave.BackgroundTransparency=.08
  local duration=root:GetAttribute("AltairReduceMotion")and .2 or 1
  self.waveTween=tween(wave,duration,{Size=vertical and UDim2.fromScale(1,1.35)or UDim2.fromScale(1.35,1),BackgroundTransparency=1},Enum.EasingStyle.Sine)
  rippleProgress.Value=0;self.rippleTween=tween(rippleProgress,duration,{Value=1},Enum.EasingStyle.Sine)
  self:ReactDrag(false)
 end
 function controller:AnimateDrop(merging)
  if not context.GetDragState then return end
  if self.dropTween then self.dropTween:Cancel()end
  if self.dropProgress then self.dropProgress:Destroy();self.dropProgress=nil end
  local dragState=context.GetDragState();if not dragState then return end
  local p=host.Position;local start=Vector2.new(p.X.Scale*root.AbsoluteSize.X+p.X.Offset,p.Y.Scale*root.AbsoluteSize.Y+p.Y.Offset)
  local destination=Vector2.new(self.targetX or dragState.center.X,self.targetY or dragState.center.Y)
  local amount=placement.amount
  if not merging and amount<.001 then start=dragState.center end
  local direction=destination-start;local distance=direction.Magnitude
  local normal=distance>.01 and Vector2.new(-direction.Y,direction.X)/distance or Vector2.zero
  local progress=Instance.new("NumberValue");progress.Value=0;self.dropProgress=progress
  self.dropPresentation={start=start,destination=destination,control=start:Lerp(destination,.55)+normal*math.min(18,distance*.035),amount=amount,merging=merging,progress=progress}
  if merging then self:ReactDrag(true)else self:PulseDrag()end
  local duration=root:GetAttribute("AltairReduceMotion")and .12 or (merging and .4 or .18)
  local animation=tweenService:Create(progress,TweenInfo.new(duration,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=1});self.dropTween=animation
  animation.Completed:Once(function(status)
   if self.dropProgress~=progress then return end
   local presentation=self.dropPresentation
   if status==Enum.PlaybackState.Completed and merging and presentation and not presentation.impacted and self.alive then self:PulseDrag()end
   progress:Destroy();self.dropProgress=nil;self.dropTween=nil;self.dropPresentation=nil
  end)
  animation:Play()
 end
 -- Active timekeeping remains independently visible while other capsules merge.
 local activityShelf=make("CanvasGroup",root,{Name="CapsuleActivities",BackgroundTransparency=1,GroupTransparency=1,Visible=false,Size=UDim2.fromOffset(105,24),AnchorPoint=Vector2.new(.5,0),ZIndex=292})
 local activityScale=make("UIScale",activityShelf,{Name="ActivityScale",Scale=1})
 local activityLayout=make("UIListLayout",activityShelf,{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
 local indicators={}
 controller.activityIndicators=indicators
 for index,spec in ipairs({{"Timer",timerPill,"timer","Scripts"},{"Stopwatch",watchPill,"watch","Character"}})do
  local indicator=activityShelf:FindFirstChild(spec[1])
  if context.BuildOnly then indicator=spec[2]:Clone();indicator.Name=spec[1];indicator.Parent=activityShelf end
  assert(indicator,"Missing persistent activity indicator")
  indicator.LayoutOrder=index;indicator.Size=UDim2.fromOffset(58,24)
  indicator.Value.Size=UDim2.fromOffset(58,24);indicator.Value.TextTransparency=0
  barTile(indicator.Back,spec[4]);indicators[index]=indicator
  connect(indicator.MouseEnter,function()placement:Reveal();controller.hoverSession=true;controller:Open(spec[3])end)
  connect(indicator.Activated,function()placement:Reveal();controller:Open(spec[3])end)
  connect(indicator.MouseButton1Down,function()if not indicator:GetAttribute("AltairActiveCapsule")and not indicator:GetAttribute("AltairNeighbourTransform")then tween(indicator.ButtonFeedback,.08,{Scale=.9})end end)
  connect(indicator.MouseButton1Up,function()if not indicator:GetAttribute("AltairActiveCapsule")and not indicator:GetAttribute("AltairNeighbourTransform")then tween(indicator.ButtonFeedback,.24,{Scale=1},Enum.EasingStyle.Back)end end)
 end
 function controller:StepActivities(dt)
  local timerActive=clock.timer~=nil
  local watchActive=clock.watch.active
  self.activityChipAlpha=self.activityChipAlpha or {0,0}
  self.activityPainted=self.activityPainted or{}
  self.activitySelectedLast=self.activitySelectedLast or{}
  local live={timerActive,watchActive};local fading=false
  for index,indicator in ipairs(indicators)do
   local alpha=self.activityChipAlpha[index];local previousAlpha=alpha;alpha+=((live[index]and 1 or 0)-alpha)*(1-math.exp(-18*math.min(dt,.1)))
   if math.abs(alpha-(live[index]and 1 or 0))<.002 then alpha=live[index]and 1 or 0 end
   self.activityChipAlpha[index]=alpha;fading=fading or alpha>0
   if not indicator:GetAttribute("ActivityOpacityReady")then
    local values={};for _,object in ipairs(indicator:GetDescendants())do
     local property=object:IsA("TextLabel")and "TextTransparency"or(object:IsA("ImageLabel")and "ImageTransparency"or(object:IsA("UIStroke")and "Transparency"or(object:IsA("Frame")and "BackgroundTransparency"or nil)))
     if property then values[#values+1]={object,property,object[property]}end
    end;indicator:SetAttribute("ActivityOpacityReady",true);self.activityFadeProperties=self.activityFadeProperties or {};self.activityFadeProperties[index]=values
   end
   local selected=self.presentation and self.presentation.source==indicator
   if not selected and(alpha~=previousAlpha or self.activitySelectedLast[index]or not self.activityPainted[index])then
    for _,entry in ipairs(self.activityFadeProperties[index])do if entry[1].Parent then set(entry[1],entry[2],1-(1-entry[3])*alpha)end end
    set(indicator,"BackgroundTransparency",1-.92*alpha)
    set(indicator,"Visible",alpha>0)
    if not live[index]or alpha<1 or previousAlpha<1 then indicator.ButtonFeedback.Scale=.85+.15*alpha end
    self.activityPainted[index]=true
   end
   self.activitySelectedLast[index]=selected==true
  end
  local wanted=self:IsEnabled()and self.docked and self.view==nil and(timerActive or watchActive or fading)
  if not wanted and(self.activityAlpha or 0)==0 then self.activityVisible=false;return end
  self.activityAlpha=(self.activityAlpha or 0)+((wanted and 1 or 0)-(self.activityAlpha or 0))*(1-math.exp(-18*math.min(dt,.1)))
  if math.abs(self.activityAlpha-(wanted and 1 or 0))<.001 then self.activityAlpha=wanted and 1 or 0 end
  set(activityShelf,"Visible",self.activityAlpha>0);set(activityShelf,"GroupTransparency",1-self.activityAlpha)
  self.activityVisible=activityShelf.Visible
  if not activityShelf.Visible then return end
  if timerActive then set(indicators[1].Value,"Text","    "..Clock.Format(clock:Remaining(),false,true))end
  if watchActive then set(indicators[2].Value,"Text","    "..Clock.Format(clock:Elapsed()))end
  local count=(self.activityChipAlpha[1]>0 and 1 or 0)+(self.activityChipAlpha[2]>0 and 1 or 0)
  local dragState=context.GetDragState and context.GetDragState();if not dragState then return end
  local vertical=dragState.dock=="left"or dragState.dock=="right"
  set(activityLayout,"FillDirection",vertical and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal)
  local width=vertical and 58 or count*58+math.max(0,count-1)*5
  local height=vertical and count*24+math.max(0,count-1)*5 or 24
  set(activityShelf,"Size",UDim2.fromOffset(width,height))
  local factor=self.baseScale or 1;set(activityScale,"Scale",factor*(.85+.15*self.activityAlpha))
  width*=factor;height*=factor
  local center=dragState.center;local viewport=root.AbsoluteSize;local x,y
  if vertical then
   x=center.X+(dragState.dock=="left"and 1 or -1)*(dragState.size.X/2+12+width/2);y=center.Y-height/2
  else x=center.X;y=center.Y<viewport.Y/2 and center.Y+dragState.size.Y/2+12 or center.Y-dragState.size.Y/2-height-12 end
  if host.Visible and placement.amount>.03 then
   local origin=compact.AbsolutePosition-root.AbsolutePosition;local size=compact.AbsoluteSize
   if vertical then x=origin.X+size.X/2;y=origin.Y+size.Y+8
   else x=origin.X+size.X+8+width/2;y=origin.Y+(size.Y-height)/2 end
  end
  x=math.clamp(x,width/2+8,math.max(width/2+8,viewport.X-width/2-8));y=math.clamp(y,8,math.max(8,viewport.Y-height-8))
  local current=activityShelf.Position;local position=Vector2.new(current.X.Offset,current.Y.Offset)
  if not self.activityInitialized then position=Vector2.new(x,y+6);self.activityInitialized=true end
  local goal=Vector2.new(x,y)
  position=(position-goal).Magnitude<.01 and goal or position:Lerp(goal,1-math.exp(-22*math.min(dt,.1)))
  set(activityShelf,"Position",UDim2.fromOffset(position.X,position.Y))
  self.activityPosition=activityShelf.Position
 end

 function controller:GetDockObstacle()
  if not self.docked then return nil end
  if self.activityVisible and(placement.amount<.03 or not host.Visible)then
   local p,z=activityShelf.AbsolutePosition,activityShelf.AbsoluteSize;return {p.X,p.Y,p.X+z.X,p.Y+z.Y}
  end
  if placement.amount<.03 or not host.Visible then return nil end
  local object=self:GetVisualObject()
  local p,z=object.AbsolutePosition,object.AbsoluteSize
  local bounds={p.X,p.Y,p.X+z.X,p.Y+z.Y}
  if self.activityVisible then local a,b=activityShelf.AbsolutePosition,activityShelf.AbsoluteSize;bounds={math.min(bounds[1],a.X),math.min(bounds[2],a.Y),math.max(bounds[3],a.X+b.X),math.max(bounds[4],a.Y+b.Y)}end
  return bounds
 end
	local obstacles={}
	for _,name in ipairs({"SmartBar","Drag","Character","Scripts","Playerlist","Settings","ScriptSearch","CustomScriptPrompt","ModeratorDetectionPrompt"}) do
		local object=root:FindFirstChild(name);if object then obstacles[#obstacles+1]=object end
	end
	local function intersects(x,width,left,right) return x<right and x+width>left end
 local function freeCompactSize(factor)
  -- Use logical horizontal targets, independent of the current side-dock pose.
  local width,count=24,1
  local function include(value)width+=value;count+=1 end
  if controller.musicShown then include(controller.freeMusicWidth or 62)end
  if clock and clock.timer then include(50)end
  if clock and clock.watch.active then include(50)end
  for handle in pairs(controller.externalHandles)do if handle.shown then include(handle.width)end end
  width+=math.max(0,count-1)*5+8
  local fit=math.max(.05,math.min(1,(root.AbsoluteSize.X-24)/math.max(1,width*factor)))
  return width*factor*fit,32*factor*fit
 end
	function controller:Layout()
		local viewport=root.AbsoluteSize
		local requested=tonumber(get("Capsule Scale",1.25)) or 1.25
		-- Migrate the previous oversized default, including already saved settings.
		if requested==3 then requested=1.25 end
		local factor=math.clamp(requested,.65,2)
		factor=math.min(factor*(root:GetAttribute("AltairDisplayScale") or displayScale(viewport)),math.max(.45,(viewport.X-24)/300))
		factor=math.min(factor,math.max(.3,(viewport.Y-24)/244))
		if not self.placement then scale.Scale=factor end
        local dock=context.GetDragState and context.GetDragState()
        local iconOnly=dock and(dock.dock=="left"or dock.dock=="right")and(self.docked or get("Capsule Position","Dynamic")=="Drag Bar Only")or false
        if self.iconOnly~=iconOnly then
         self.iconOnly=iconOnly
         pillLayout.FillDirection=iconOnly and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
         for handle in pairs(self.externalHandles)do handle:SetIconOnly(iconOnly)end
         tween(compactTitle,.18,{TextTransparency=iconOnly and 1 or 0})
         for _,pill in ipairs({timerPill,watchPill})do
          local p=self.presentation;local target=p and p.source==pill and p.slot or pill
          tween(target,.22,{Size=UDim2.fromOffset(iconOnly and 24 or 50,24)})
          tween(pill.Value,.18,{TextTransparency=iconOnly and 1 or 0})
         end
         syncCompactBounds()
        end
  local width,height=freeCompactSize(factor)
  local expanded=self.presentation and self.presentation.expandedSize or self.view and sizes[self.view]
  if expanded then width=math.max(width,expanded.X*factor);height=math.max(height,expanded.Y*factor)end
				local top=12*factor
		local x,y=viewport.X/2-width/2,top
		local candidates={}
		for _,object in ipairs(obstacles) do if object.Visible then candidates[#candidates+1]=object end end
		local toasts=root:FindFirstChild("Toasts")
		if toasts then for _,object in ipairs(toasts:GetChildren()) do
			if object:IsA("GuiObject") and object.Visible and object.Name~="Template" then candidates[#candidates+1]=object end
		end end
		if context.Notifications then for _,object in ipairs(context.Notifications:GetObstacles()) do candidates[#candidates+1]=object end end
		placement:Layout(width,height,factor,candidates)
  if self.presentation then self.presentation.dirty=true end
  self.baseScale=factor
  local enabled=self:IsEnabled()
  if self.lastEnabled~=enabled then
   self.lastEnabled=enabled
   for observer,callback in pairs(self.enabledObservers)do if observer.Connected then callback(enabled)end end
  end
	end
	local function inside(object,position)
		local p,s=object.AbsolutePosition,object.AbsoluteSize
		local x,y=position.X+root.AbsolutePosition.X,position.Y+root.AbsolutePosition.Y
		-- Keep edge controls usable without changing the visible capsule dimensions.
		local margin=math.max(18,24*scale.Scale)
		return x>=p.X-margin and x<=p.X+s.X+margin
			and y>=p.Y-margin and y<=p.Y+s.Y+margin
	end
 -- Transfer hover ownership only after the expanded shell is under the pointer.
 -- A hoisted pill initially sits under the mouse; that is not a completed transfer.
 function controller:HoverContains(pointer)
  local visual=self:GetVisualObject()
  local onSurface=visual and visual.Visible and inside(visual,pointer)or false
  local source=self:GetPresentationSourceBounds()or self.hoverSourceBounds
  local margin=math.max(18,24*scale.Scale)
  local function within(bounds)
   return bounds and pointer.X>=bounds[1]-margin and pointer.X<=bounds[3]+margin
    and pointer.Y>=bounds[2]-margin and pointer.Y<=bounds[4]+margin or false
  end
  -- Neighbour reflow can move the reserved slot away from the activation edge.
  -- Keep that original hit area alive until the pointer transfers to the panel.
  local onSource=within(source)or(not self.hoverReachedSurface and within(self.hoverSourceBounds))
  local p=self.presentation
  if onSurface and p and p.phase>.88 and not onSource then self.hoverReachedSurface=true end
  local crossing=false
  if source and visual and visual.Parent and not self.hoverReachedSurface then
   local a=Vector2.new((source[1]+source[3])*.5,(source[2]+source[4])*.5)
   local position=visual.AbsolutePosition-root.AbsolutePosition;local size=visual.AbsoluteSize
   local b=Vector2.new(math.clamp(a.X,position.X,position.X+size.X),math.clamp(a.Y,position.Y,position.Y+size.Y))
   local line=b-a;local lengthSquared=line:Dot(line)
   local nearest=a+line*(lengthSquared>.01 and math.clamp((pointer-a):Dot(line)/lengthSquared,0,1)or 0)
   crossing=(pointer-nearest).Magnitude<=margin+8
  end
  return onSurface or onSource or crossing or(compact.Visible and inside(compact,pointer))
 end
	connect(input.InputBegan,function(event)
		if controller.picker and event.KeyCode==Enum.KeyCode.Escape then controller:EndTimerEntry(false);return end
		if controller.view and not controller.picker and not input:GetFocusedTextBox() and (event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)
			and not controller:HoverContains(Vector2.new(event.Position.X,event.Position.Y))then controller:Open(nil) end
	end)
	local renderAccumulator=0
 local function capsuleSpring(value,velocity,target,omega,zeta,dt)
  local delta=value-target;local frequency=omega*math.sqrt(math.max(.0001,1-zeta*zeta))
  local decay=math.exp(-zeta*omega*dt);local cosine,sine=math.cos(frequency*dt),math.sin(frequency*dt)
  return target+decay*(delta*cosine+(velocity+zeta*omega*delta)/frequency*sine),decay*(velocity*cosine-(zeta*omega*velocity+omega*omega*delta)/frequency*sine)
 end
 local function fadeFace(part,alpha)
  if not part or not part.object.Parent then return end
  for _,entry in ipairs(part.opacity)do
   if entry[1].Parent then local goal=1-(1-entry[3])*alpha;if entry[1][entry[2]]~=goal then entry[1][entry[2]]=goal end end
  end
 end
 connect(runService.RenderStepped,function(dt)
  local p=controller.presentation;if not p or not p.shell.Parent then return end
  if not p.dirty and p.phase==p.targetPhase and not p.resize and not p.previousView then return end
  local step=math.min(dt,.05)
  local opening=p.targetPhase==1
  local omega=opening and(controller.OpenOmega or 17.8)or(controller.CloseOmega or 19)
  local zeta=opening and .87 or .98
  p.phase,p.velocity=capsuleSpring(p.phase,p.velocity,p.targetPhase,omega,zeta,step)
  if math.abs(p.phase-p.targetPhase)<.0005 and math.abs(p.velocity)<.02 then p.phase=p.targetPhase;p.velocity=0 end
  local alpha=math.clamp(p.phase,0,1)
  local target=capsuleRect(p.returnSource and p.returnSource~=p.source and p.returnSource or p.slot)
  if target then p.collapsedRect=target end
  local desired=p.targetPhase==0 and p.expandedRect or expandedTarget(p)
  if not p.resize and p.phase==1 and(math.abs(desired.x-p.expandedRect.x)>.1 or math.abs(desired.y-p.expandedRect.y)>.1)then p.resize={from=table.clone(p.expandedRect),phase=0,velocity=0,duration=.22}end
  if p.resize then
   local resize=p.resize;local resizeOmega=17.8*.30/math.max(.12,resize.duration)
   local shrinking=desired.width*desired.height<resize.from.width*resize.from.height
   resize.phase,resize.velocity=capsuleSpring(resize.phase,resize.velocity,1,resizeOmega,shrinking and .98 or .87,step)
   if math.abs(resize.phase-1)<.0005 and math.abs(resize.velocity)<.02 then resize.phase=1;resize.velocity=0 end
   p.expandedRect=mixRect(resize.from,desired,resize.phase)
   if resize.phase==1 then p.resize=nil end
  else p.expandedRect=desired end
  p.rect=mixRect(p.collapsedRect,p.expandedRect,p.phase)
  local rect=p.rect
  local destinationObject=p.returnSource and p.returnSource~=p.source and p.returnSource or p.slot
  local collapsedFit=destinationObject and p.collapsedRect.width/math.max(1,destinationObject.Size.X.Offset)or p.startFit
  local fit=collapsedFit+(1-collapsedFit)*alpha
  p.shellScale.Scale=fit
  shellGeometry(p.shell,rect,fit)
  local destination=p.returnSource or p.source
  local destinationVisual,destinationBack,destinationGradient=sourceMaterial(destination)
  local liveBase=smartBar and smartBar.BackgroundColor3 or baseColor
  local liveControl=smartBar and smartBar.Back.BackgroundColor3:Lerp(liveBase,.35)or controlColor
  p.original.color=liveBase;p.original.gradient=compactGradient(p.source,p.original.gradient)
  if p.back then p.original.backColor=p.back.BackgroundColor3 end
  local baseTransparency=destination~=p.source and p.destinationBackground or p.original.transparency
  p.shell.BackgroundColor3=(destination~=p.source and destination.BackgroundColor3 or p.original.color):Lerp(liveBase,alpha)
  local collapsedAlpha=Design.materialAlpha(destination,baseTransparency)
  p.shell.BackgroundTransparency=collapsedAlpha+((controller.surfaceOpacity or .1)-collapsedAlpha)*alpha
  local expandedRadius=18
  p.shell.UICorner.CornerRadius=UDim.new(p.original.corner.Scale*(1-alpha),p.original.corner.Offset+(expandedRadius-p.original.corner.Offset)*alpha)
  if p.visual and p.visual~=p.source then
   p.visual.Position=UDim2.new();p.visual.Size=UDim2.fromScale(1,1);p.visual.GroupTransparency=0
  end
  if p.back then
   p.back.Position=p.original.backPosition:Lerp(UDim2.fromOffset(5,5),alpha);p.back.Size=p.original.backSize:Lerp(UDim2.new(1,-10,1,-10),alpha)
   p.back.BackgroundTransparency=Design.materialAlpha(p.back,p.original.backTransparency)
   p.back.UICorner.CornerRadius=UDim.new(0,p.original.backCorner.Offset+(13-p.original.backCorner.Offset)*alpha)
  end
  if p.edge then
   p.edge.Position=p.original.edgePosition:Lerp(UDim2.fromOffset(1,1),alpha);p.edge.Size=p.original.edgeSize
   if p.original.edgeCorner then p.edge.UICorner.CornerRadius=UDim.new(0,p.original.edgeCorner.Offset+(17-p.original.edgeCorner.Offset)*alpha)end
  end
  if p.gradient then
   local compactColor=destination~=p.source and compactGradient(destination,p.original.gradient)or p.original.gradient
   local expandedColor=p.view=="music"and compactColor or ColorSequence.new(liveBase,liveControl)
   p.gradient.Color=tintSequence(compactColor,expandedColor,alpha)
  end
  local faceTarget=opening and 1-math.clamp(alpha/.4,0,1)or math.clamp((.55-alpha)/.32,0,1)
  local contentTarget=opening and math.clamp((alpha-.25)/.6,0,1)or math.clamp((alpha-.75)/.25,0,1)
  local neighbourTarget=opening and 1-math.clamp(alpha/.65,0,1)or math.clamp((.55-alpha)/.32,0,1)
  local smoothing=1-math.exp(-90*step)
  p.faceAlpha=(p.faceAlpha==nil and 1 or p.faceAlpha)+(faceTarget-(p.faceAlpha==nil and 1 or p.faceAlpha))*smoothing
  p.contentAlpha=(p.contentAlpha or 0)+(contentTarget-(p.contentAlpha or 0))*smoothing
  p.neighbourAlpha=(p.neighbourAlpha==nil and 1 or p.neighbourAlpha)+(neighbourTarget-(p.neighbourAlpha==nil and 1 or p.neighbourAlpha))*smoothing
  if p.phase==p.targetPhase then p.faceAlpha=faceTarget;p.contentAlpha=contentTarget;p.neighbourAlpha=neighbourTarget end
  for _,part in pairs(p.face)do fadeFace(part,p.returnSource and p.returnSource~=p.source and 0 or p.faceAlpha)end
  compact.Visible=true;compact.GroupTransparency=1-p.neighbourAlpha;compact.Interactable=not opening and p.neighbourAlpha>.5
  p.neighbourScale=.88+.12*(1-alpha)
  for _,object in ipairs(strip:GetChildren())do
   if object:IsA("GuiObject")and object~=p.slot and object.Name~="CapsuleReturnSlot"then
    object:SetAttribute("AltairNeighbourTransform",true)
    local value=neighbourScale(object);if value.Scale~=p.neighbourScale then value.Scale=p.neighbourScale end
   end
  end
  if p.destinationOpacity then
   for _,entry in ipairs(p.destinationOpacity)do if entry[1].Parent and(entry[1]==p.returnSource or entry[1]:IsDescendantOf(p.returnSource))then entry[1][entry[2]]=1 end end
   morphChevron.Position=UDim2.fromScale(.5,.5);morphChevron.Size=UDim2.fromOffset(12,12);morphChevron.ImageTransparency=1-p.faceAlpha
  end
  local pageBlend=p.previousView and math.clamp((os.clock()-p.pageAt)/.16,0,1)or 1
  for key,group in pairs(views)do
   if not group:GetAttribute("AltairInlineView")then
    if key==p.view then group.GroupTransparency=1-p.contentAlpha*pageBlend
    elseif key==p.previousView then
     group.GroupTransparency=1-p.contentAlpha*(1-pageBlend)
     if pageBlend==1 then group.Visible=false;group.Parent=templateSurface end
    end
   end
  end
  if pageBlend==1 then p.previousView=nil end
  p.dirty=false
  if p.targetPhase==0 and p.phase==0 then restorePresentation(p)end
 end)

	connect(runService.Heartbeat,function(dt)
		if context.Alive and not context.Alive() then return end
		if clock:Tick() then
			controller.flashIconUntil=os.clock()+3
            context.Notify("Timer finished","Your countdown has ended.",nil,{Duration=8})
			if controller.view~="timer" then controller:Open("timer") end
		end
		local now=os.clock()
        controller:StepAlbum(dt)
		if controller.hoverSession and controller.view and not controller.dragging and not input:GetFocusedTextBox() then
			local pointer=input:GetMouseLocation()
			local inset=root.IgnoreGuiInset and Vector2.zero or game:GetService("GuiService"):GetGuiInset()
			pointer-=inset
			local hovering=controller:HoverContains(pointer)
			local dragState=context.GetDragState and context.GetDragState()
            local overDrag=dragState and math.abs(pointer.X-dragState.center.X)<=dragState.size.X/2+8 and math.abs(pointer.Y-dragState.center.Y)<=dragState.size.Y/2+8
            if overDrag and now>(controller.hoverGraceUntil or 0)then
             if controller.picker then controller:EndTimerEntry(false)end
             controller.hoverSession=false;controller:Open(nil)
            elseif hovering or controller.picker
				or now<(controller.hoverGraceUntil or 0) then
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
        placement:Step(dt,controller.baseScale or 1.25)
        controller:StepActivities(dt)
		if get("Spotify Connection",false) and now>=controller.nextPoll and not controller.requestBusy and not controller.commandBusy then
			controller.requestBusy=true;controller.nextPoll=now+1.5
			task.spawn(function()
				local generation=controller.mediaGeneration
				local ok,state=pcall(bridgeRequest,"GET","state")
				if not controller.alive then return end
				controller.requestBusy=false
				if generation~=controller.mediaGeneration or not get("Spotify Connection",false) then return end
				if ok then controller.failures=0;controller:SetMedia(state,true);controller.nextPoll=math.max(controller.nextPoll,os.clock()+math.min(30,tonumber(state.retry_after)or 0))
				else
					controller.failures+=1
					controller.nextPoll=os.clock()+math.min(30,2^math.min(5,controller.failures))
                    local cached=table.clone(controller.media)
                    cached.progress=progress();cached.linked=cached.linked or cached.connected
                    cached.available=false;cached.stale=true;cached.playing=false
                    cached.status=type(state)=="table" and state.status or "reconnecting"
                    cached.message=type(state)=="table" and state.message or "Companion unavailable. Keep it running; Altair will reconnect automatically without removing your saved link."
                    controller:SetMedia(cached)
				end
			end)
		elseif not get("Spotify Connection",false) and not context.MediaAdapter and controller.media.connected then
			controller:SetMedia({connected=false,title="Spotify"})
		end
		renderAccumulator+=dt
		if renderAccumulator<(controller.view and 1/60 or .1) or not host.Visible and not controller.activityVisible then return end
		local renderDt=renderAccumulator;renderAccumulator=0
		do
			local rainbow=get("Rainbow Mode",false)==true
			local accent=rainbow and ((context.GetRainbowColor and context.GetRainbowColor()) or Color3.fromHSV((os.clock()/8)%1,.65,.8)) or white
			for _,stroke in ipairs(accentOutlines) do if stroke.Parent then set(stroke,"Color",rainbow and accent or stroke:GetAttribute("AltairTheme_Color")or white)end end
		end
        local contextIcon="chevron-down"
        if now<(controller.flashIconUntil or 0)then contextIcon="check"
        elseif clock.timer then contextIcon=clock.timer.finished and "check"or clock.timer.started and "timer"or "pause"
        elseif clock.watch.active then contextIcon="clock"
        elseif controller.media.playing then contextIcon="music-2"
        elseif controller.media.connected and(controller.view=="music"or now<(controller.musicHoldUntil or 0))then contextIcon="pause"
        else for handle in pairs(controller.externalHandles)do if handle.shown then contextIcon="square-terminal";break end end end
        if contextIcon~=controller.contextIcon then
         controller.contextIcon=contextIcon;controller.iconGeneration=(controller.iconGeneration or 0)+1
         local generation=controller.iconGeneration
         local activeMenu=controller.presentation and controller.presentation.source==menuPill
         if not activeMenu then tween(menuPill.Chevron,.08,{ImageTransparency=1})end
         task.delay(.09,function()
          if controller.alive and generation==controller.iconGeneration then
           applyIcon(menuPill.Chevron,contextIcon);applyIcon(morphChevron,contextIcon)
           if not(controller.presentation and controller.presentation.source==menuPill)then tween(menuPill.Chevron,.14,{ImageTransparency=0})end
          end
         end)
        end
		local remaining,elapsed=clock:Remaining(),clock:Elapsed()
		local timerFinished=clock.timer~=nil and(clock.timer.finished or remaining<=0)
		local timerControllable=clock.timer~=nil and not timerFinished
		set(timerPause,"Active",timerControllable);set(timerPause,"Interactable",timerControllable)
		set(timerPause,"Selectable",timerControllable);set(timerPause,"Visible",timerControllable)
  local activeSource=controller.presentation and controller.presentation.source
		if activeSource~=timerPill then set(timerPill,"Visible",clock.timer~=nil and not controller.docked)end
  if activeSource~=watchPill then set(watchPill,"Visible",clock.watch.active and not controller.docked)end
		local musicActive=controller.media.connected and controller.media.playing and (controller.media.duration or 0)>0
		local retainMusic=controller.view=="music"or now<(controller.musicHoldUntil or 0)
		-- Retain the title during exit so the whole pill fades as a single visual.
		if musicActive then set(compactTitle,"Text",controller.media.title) end
		if controller.view=="music"and not controller.media.connected and not controller.media.linked then controller:Open(nil)end
		local pillWidth=math.max(60,(controller.titleWidth or 0)+35)
		animateMusic(musicActive==true or retainMusic,pillWidth)
		set(timerPill.Value,"Text","    "..Clock.Format(remaining,false,true));set(watchPill.Value,"Text","    "..Clock.Format(elapsed))
		if controller.picker then
   if durationControl and not durationControl.IsDragging()then durationControl:Sync(false)end
		end
  if controller.view=="timer" then
			set(timerTitle,"Text",timerFinished and "Timer finished"or "Timer")
			set(timerTime,"Text",Clock.Format(remaining,false,true))
			if timerControllable then renderTimerPause(clock.timer.started~=nil)end
			set(timerTime,"TextTransparency",clock.timer and not timerFinished and not clock.timer.started and .25 or 0)
			rulerStrip.Position=UDim2.fromOffset(-(((clock.timer and clock.timer.duration or 0)-remaining)*18.5%18.5),0)
		elseif controller.view=="watch" then
			set(watchTime,"Text",Clock.Format(elapsed));set(fraction,"Text",string.format(".%02d",math.floor((elapsed%1)*100)))
   local textScale=scale.Scale
   local timeWidth=watchTime.TextBounds.X/math.max(.01,textScale)
   fraction.Position=UDim2.fromOffset(timeWidth+12,42)
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
				local statusTitle,statusMessage=spotifyStatus(m)
				local playbackReady=m.connected and m.available~=false and get("Spotify Connection",false) and not m.reauth_required and m.status~="authorization_required" and m.status~="waiting_for_spotify"
				set(player.title,"Text",playbackReady and m.title or statusTitle)
				set(player.artist,"Text",playbackReady and m.artist or statusMessage)
				player.renderPlay(playbackReady and m.playing)
				set(player.elapsed,"Text",Clock.Format(progress()):gsub("^0([0-9]):","%1:"))
				set(player.duration,"Text",(m.duration or 0)>0 and Clock.Format(m.duration):gsub("^0([0-9]):","%1:") or "--:--")
				if player.group.Visible and player.group.GroupTransparency<.99 and not player.seek.IsDragging()then player.seek:Set((m.duration or 0)>0 and progress()/m.duration or 0,false,m.duration)end
			end
			set(timerSummary,"Text",controller.picker and "Cancel"or timerFinished and "Finished"or clock.timer and Clock.Format(remaining,false,true) or "Set")
			set(timerSummary,"TextColor3",clock.timer and amber or white);set(timerCancel,"Visible",clock.timer~=nil or controller.picker)
			set(watchSummary,"TextColor3",clock.watch.active and green or white);set(watchCancel,"Visible",clock.watch.active)
			set(watchSummary,"Text",clock.watch.active and Clock.Format(elapsed,true) or "Start")
			if center.Visible then
    if not volume.IsDragging()then volume:Set(math.clamp(tonumber(m.volume)or 0,0,1),false)end
    if not brightness.IsDragging()then brightness:Set(math.clamp(lighting.Brightness/3,0,1),false)end
   end
			set(mute,"Visible",(tonumber(m.volume) or 0)<=.001);set(speaker,"Visible",not mute.Visible)
            local dark=Color3.fromRGB(24,26,31)
            local volumeColor=(tonumber(m.volume)or 0)>.18 and dark or white
            set(speaker,"ImageColor3",volumeColor);set(mute,"ImageColor3",volumeColor)
            local brightnessRatio=brightness.bar:GetAttribute("AltairVertical")and brightness.fill.Size.Y.Scale or brightness.fill.Size.X.Scale
            set(center.BrightnessIcon,"ImageColor3",brightnessRatio>.18 and dark or white)
		end
	end)
	function controller:Destroy()
		if not self.alive then return end
		if context.Session and(self.media.connected or self.media.linked)then
			context.Session.media=table.clone(self.media);context.Session.media.progress=progress();context.Session.mediaAt=os.clock()
		end
		unlinkPrompt:Destroy()
		self.alive=false
        if self.dropTween then self.dropTween:Cancel()end
        if self.dropProgress then self.dropProgress:Destroy()end
        activityShelf:Destroy();if ripple then ripple:Destroy()end
        for observer in pairs(self.enabledObservers)do observer:Disconnect()end
		self.cancelDrag();table.clear(self.commands)
  for _,state in ipairs(mediaSliders)do if state.ruler then state.ruler:Destroy()end end
		for _,connection in ipairs(self.connections) do connection:Disconnect() end
		for _,animation in pairs(self.tweens) do animation:Cancel() end
		if brightnessChanged and lighting.Brightness==ownedBrightness then lighting.Brightness=originalBrightness end
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
  if (right-left)*(bottom-top)>viewport.X*viewport.Y*.45 then return nil end
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

local function buildChoice(template,parent,setting,changed)
 local motion=motionService()
 local row=template:Clone();row.Name=setting.name;row.Visible=true;row.Size=UDim2.new(1,-16,0,126)
 row.Title.Text=setting.name;row.Title.TextTransparency=0
 row.Description.Text=setting.description or "";row.Description.Visible=true
 row.Description.TextTransparency=.3;row.Description.TextWrapped=true
 row.Description.Position=UDim2.fromOffset(18,39);row.Description.Size=UDim2.new(1,-36,0,32)
 row.BackgroundColor3=Design.Raised;row.BackgroundTransparency=.12;row:SetAttribute("AltairDesignRole","inset")
 row.UIStroke.Color=Design.Edge;row.UIStroke.Thickness=.6;row.UIStroke.Transparency=.9
 local rowCorner=row:FindFirstChildOfClass("UICorner");if rowCorner then rowCorner.CornerRadius=UDim.new(0,12)end
 row.Title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold);row.Title.TextColor3=Color3.fromRGB(243,246,252)
 row.Description.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium);row.Description.TextColor3=Design.Muted;row.Description:SetAttribute("AltairDesignRole","muted")
 if row:FindFirstChild("Interact")then row.Interact:Destroy()end
 if row:FindFirstChild("LicenseDisplay")then row.LicenseDisplay.Visible=false end
 local items={}
 local function update()
  for value,item in pairs(items)do
   local selected=setting.current==value
   motion:Create(item.button,TweenInfo.new(.22,Enum.EasingStyle.Quint),{BackgroundTransparency=selected and .06 or .48}):Play()
   motion:Create(item.stroke,TweenInfo.new(.22),{Transparency=selected and .72 or .94}):Play()
  end
 end
 for index,value in ipairs(setting.values)do
  local button=Instance.new("TextButton");button.Name=value;button.Text=value;button.AutoButtonColor=false
  button.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium);button.TextSize=11;button.TextColor3=Color3.fromRGB(243,246,252)
  button.BackgroundColor3=Design.Well;button.BorderSizePixel=0;button:SetAttribute("AltairDesignRole","control")
  local fraction=(index-1)/#setting.values;local reserved=36+(#setting.values-1)*8
  button.Size=UDim2.new(1/#setting.values,-reserved/#setting.values,0,32);button.Position=UDim2.new(fraction,18+(index-1)*8-fraction*reserved,0,82)
  button.ZIndex=row.Title.ZIndex;button.Parent=row
  local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,8);corner.Parent=button
  local stroke=Instance.new("UIStroke");stroke.Color=Design.Edge;stroke.Thickness=.6;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=button
  local scale=Instance.new("UIScale");scale.Parent=button
  items[value]={button=button,stroke=stroke}
  button.MouseEnter:Connect(function()motion:Create(scale,TweenInfo.new(.18),{Scale=1.012}):Play();motion:Create(stroke,TweenInfo.new(.18),{Transparency=.65}):Play()end)
  button.MouseLeave:Connect(function()motion:Create(scale,TweenInfo.new(.25,Enum.EasingStyle.Back),{Scale=1}):Play();update()end)
  button.MouseButton1Down:Connect(function()motion:Create(scale,TweenInfo.new(.1),{Scale=.975}):Play()end)
  button.Activated:Connect(function()
   motion:Create(scale,TweenInfo.new(.28,Enum.EasingStyle.Back),{Scale=1}):Play()
   if setting.current~=value then setting.current=value;update();changed(value)end
  end)
 end
 row.Parent=parent;update();return row
end

local function loadingCloud()
 if softShadowAssets.cloud then return softShadowAssets.cloud end
 if type(writefile)~="function"or type(getcustomasset)~="function"then return nil end
 local path="Altair/CloudzLoading.png"
 local ok,result=pcall(function()
  if type(isfile)~="function"or not isfile(path)then
   if type(makefolder)=="function"then pcall(makefolder,"Altair")end
   local hex="89504e470d0a1a0a0000000d4948445200000200000002000806000000f478d4fa00001000494441547801ecdd0d7ae338ceaee1f2d9d837bdb2a95e59f7ac2c074859d54eda4efc23520479d725966459228107b4f092929dfff7c33f04104000010410588e0001b05cc8398c0002082080c08f1f04805e800002082080c0820408800583ce650410400081b509a4f704405250104000010410588c0001b058c0b98b00020820b03a815ffe1300bf38f81f010410400081a50810004b859bb30820800002ab13d8fc27003612d60820800002082c4480005828d85c4500010410589dc03ffe1300ffb0b0850002082080c0320408806542cd510410400081d5095cfa4f005cd2b08d0002082080c0220408804502cd4d0410400081d5097cf49f00f8c8c32b041040000104962040002c11664e2280000208ac4ee0b3ff04c067225e238000020820b0000102608120731101041040607502fff69f00f837137b104000010410989e0001307d88398800020820b03a816bfe1300d7a8d8870002082080c0e4040880c903cc3d0410400081d5095cf79f00b8cec55e041040000104a62640004c1d5ece2180000208ac4ee096ff04c02d32f62380000208203031010260e2e0720d01041040607502b7fd27006eb3f10e020820800002d3122000a60d2dc710400001045627f095ff04c05774bc870002082080c0a40408804903cb2d0410400081d5097ced3f01f0351fef2280000208203025010260cab0720a01041040607502dff94f007c47c8fb0820800002084c4880009830a85c4200010410589dc0f7fe1300df337204020820800002d3112000a60b298710400001045627708fff04c03d941c830002082080c064040880c902ca1d0410400081d509dce73f01701f27472180000208203015010260aa70720601041040607502f7fa4f00dc4bca710820800002084c4480009828985c4100010410589dc0fdfe1300f7b37224020820800002d3102000a609254710400001045627f088ff04c023b41c8b0002082080c0240408804902c90d0410400081d5093ce63f01f0182f4723800002082030050102608a307202010410406075028ffa4f003c4accf10820800002084c4080009820885c4000010410589dc0e3fe13008f337306020820800002e5091000e543c8010410400081d5093ce33f01f00c35e7208000020820509c0001503c80cc4700010410589dc073fe1300cf717316020820800002a5091000a5c3c7780410400081d5093ceb3f01f02c39e7218000020820509800015038784c4700010410589dc0f3fe1300cfb37326020820800002650910006543c7700410400081d509bce23f01f00a3de722800002082050940001503470cc4600010410589dc06bfe1300aff173360208208000022509100025c3c6680410400081d509bcea3f01f02a41e7238000020820509000015030684c4600010410589dc0ebfe1300af335403020820800002e5081000e542c6600410400081d509ece13f01b0074575208000020820508c0001502c60cc4500010410589dc03efe1300fb70540b020820800002a5081000a5c2c5580410400081d509ece53f01b01749f5208000020820508800015028584c4500010410589dc07efe1300fbb15413020820800002650810006542c5500410400081d509ece93f01b0274d7521800002082050840001502450cc4400010410589dc0befe1300fbf2541b0208208000022508100025c2c4480410400081d509eced3f01b03751f5218000020820508000015020484c4400010410589dc0fefe1300fb335523020820800002c3132000860f110311400001045627d0c27f02a00555752280000208203038010260f000316f1c026f6f6ffff954fe1baf3f97bf625f96cffb3f9c3b8e572c410081f109b4b1900068c355ad450944f2de127526f04ce45962f7db5bb8f4d7a7f2335e7f2eff897d593eefff70ee7b851fffcb76b2cd2c797e546341000104da112000dab155f3e00422ff6ec93e936f96cb249f093c1371961e9e643bd96696775bc2be5ca720c892eff7b0431b082030188156e61000adc8aa773802915033e16732cdc47a99ec33b96619cde6b429054196779bc3875cd287ff8e662c7b1040a0160102a056bc58fb2081c89699f4df93679c9ad3f0994c33b1c6cbb24bfaf0337cdb961404d57d2a1b0c8623d09640bbda0980766cd57c0081c88899f0b35c26fdd993630a82777fc37f62e0807ea749042a1220002a468dcdff221089ef3de9c71b39cacf327bd20f57af2e9fc5805b055731d989400d022dad24005ad2557753025bd28ff5763f7fd5a47f8b738a81ed560121708b92fd082c4a80005834f095dd8e847f39da97f4ef0b2621701f274721301081b6a610006df9aa7d2702e7a49ff7b78df65f63fa5b080453b302afb1743602a5091000a5c337bff191a42e47fb39a53dbfd37d3c4c962906525411027d986b05818708b43e9800684d58fd4f1388e49f8969e507fa9e66f7c0899b1008dc6fc9fb81531d8a00029509100095a337a9ed918972549a53fd999c26f57248b77e06fb5c088121c3c3a8b508b4f7960068cf580b771288cc23f1dfc9aaf16129048880c690558fc0d1040880a323a0fd1f91f8b7fbfc46fce3f4871401119a3742609c98b06421023d5c25007a50d6c64d02916132c1b8cf7f93d0e16ffc8c18e592713adc18062080c07e040880fd58aae90102915172d4ef3eff03cc0e3e3485001170701034bf0a813e7e12007d386be5824024ff1cf167b9d86bb30081140111be3742a040b09888c077040880ef08797f37029139b651bf5fefdb8dea2115fd8c58e6039be278087e8dce4ea0977f04402fd28bb79309231018f5078449967c6033ff02a1d9804902ca8df5081000ebc5bcabc791f873d49f893f1346d7b635d685c0fb6c4097963482c01204fa394900f463bd5c4b99fcc3e94cfea68a03c4c40b11307170b9362f010260ded81eea5924ff9c1acee47fa81d1aef4620454084fd8dd8eb865c433312e8e91301d093f6226d4516c8c46fca7f91787f72d373019f807889c0a8040880512353d0ae48fc79bfff2d4c370a0c080b2f391b9033400b23e03a02cf10e87b0e01d097f7b4ad65f20fe772e41f2b0b023f88009d0081c10910008307a88279927f85281d62638a00a2f010f41aad48a0b7cd04406fe293b517c9ffbfe1928b7c40b05c2590b785f48fab68ec44e0580204c0b1fc4bb77e4efe1ef62b1dc52ec613015d306ba43681fed61300fd994fd1a2e43f45187b3a4104f4a4ad2d04ee204000dc01c9211f0948fe1f797875370122e06e540e5c8dc011fe120047502fdca6e45f387863984e048c11075620f08300d009ee2620f9df8dca815f132002bee6e3dde5081ce33001700cf772ad46f2cf1ff7f1c05fb9c80d6b3011306c6818b60a0102609548bfe0e739f9fb2ad70b0c9d7a95001170158b9dab1138ca5f02e028f245da95fc8b04aaae994440ddd8b1bc380102a078003b989f3ff4d3a1194d2c4c2045807eb6700758dbf5e3bc27008e633f7ccb31facf8b72defb1fde56069627903f1bacaf950f23072a1120002a45aba3ade7e4efa1bf8ecc35f523ff943011a0232c45e04867098023e90fdab6e43f6860d6302b679dd6f09497081c4c800038380083366fe43f68601630cbf3000b04998b1b8163d704c0b1fc876b3d46ffbeee375c549633289f073013b05cd839dc9b0001d09bf8c0ed45f2cf8bae7bb003c76821d35204e88b0b057c45578ff69900383a0283b47f4efea6fe0789c72066fc1d766c25fbc6b5f2471c736fb9767eeedbda88aa3e2c29483fecf0020104f6234000ecc7b27a4d7921aeee03fbef27b025dd5c67ec7f27f1d33ffffe88cdadfc19dbd7cadfb1ffde72edfcdcb7b51155fd5ac28db4e7cf10a666010286654602c7fb44001c1f83c32d888bac91d6e15168664026f82cbf93fcaf147bda926eae3309ff4ee2cd2c79a0e2d3e934943d0f98ee5004ca102000ca84aa8da191fc738495c9a14d036aed4920137d968c6726f6c8a3a75c67f99de47b1aa42d0410b84e6084bd04c0085138d606a3ff63f9bfd27a26fb2c99e04ff12fd759de93fd2b153b170104e6274000cc1fe39b1ec6e83f937fce00dc3cc61bc311784ff8615526faade4bed8654100811a04c6b0920018230e47599153c547b5adddfb086472cf07e232d9c720ff94ebf7fbe3f79dee28041040e03a0102e03a97e9f79e47ffd3fb59d4c1cba42fe1170d22b311b8456094fd04c02891e868c739f91bfd77647e475399f4b364c2cf62947f0734872080c0f3040880e7d9553ed37dff71a27799f4df13ff38a6b1040104f627304e8d04c038b1e862c979f44f0074a17db3912de99fe29fa47f1393371040a0250102a025dd31eb36f57f5c5cb6c42fe91f17032d23702881911a2700468a46635bcea3ffc6ada8fe0a0189ff0a14bb1040e0580204c0b1fc7bb76ef4df97f8cf98e2cfc588bf2f77ad21302881b1cc2200c68a47336b8cfe9ba1fd5cf136dacfc4ffe7e737bd46000104462140008c1289f67618fd77601c59df68bf3d672d205092c068461300a345a4813d46ff0da07eac32bfb31fb9ff64c4ff918b5708203030010260e0e0306d7802db747ffe54eff0c6321001048e24305edb04c07831d9d5a218fde777fe4dffef4af5c7efc47f3a9d72fb877f0820804035020440b5883d6eefff3d7e8a33be2090f7f8b348fc5f40f21602087c2430e22b0260c4a8ec6b93d1ff3e3cb7fbfc12ff3e3cd5820002071320000e0e40cbe663faffbf2deb5fa8ee1cf1bbcf7f0e78f4abffdc28ff8dfd9fcbd563cf555921b0088131dd2400c68ccb5e5619fdbf467299517f24eecb449d49fcafd89725561f9740fad78d92fded73b97aecc71adf5f655b59b2edade4f32bd1940501045a1020005a501da0ceb8a4ba78be16872947fdd92fa26482cd64bb95b7407599a8338967ffc9126f7559b2ad2cd9f656d2be30f77dc9ed2c697b963cb68b611a41e05502a39e4f008c1a99d7edf2f0df730ca719f547dadc46f59938b36c893e136c26d0ad3c47aaef599bad697b96777fc2c75ca72070bbab6f3cb436010102608220de70212f9237deb2fb0681fcedfeb2f7fa231966c2cf649849714bf639b2df92e70db74bef4edfb2afff0cff7349df9341967cafb4738c9f81c0b83e1000e3c6e669cbe22ae8c2f738bd9cf22ff74b7e19eb2899f4b6849fc970e5f8a7efc920cb3b97e09362c00cc1e39f09674c4e80009833c0a6ffef8f6ba929ff486639cacff29edcc2cd6d841f9b961b04520c6c3304c4c00d4876b7213072ad04c0c8d179deb6bce03d7ff63a679698f2bf4cfa119a4cf85972a41b2f2d0f12c8cf0631f0203487cf4980009833aebcfa9e4026ffa1a7fccf893f93fd5624fdefe3fac811c4c023b41cfb0481b14f2100c68ecfc3d645d270aff36b6af94b7e43dfefcf1846d9eee94bfa5fc773af773731e016c15e44d5333c010260f8103d6ca084711b59deefcfe49f22e0f65107bc1309fff2be7e26a303acd0641048f6bf6f11c46b0b024f1318fd440260f4083d6e1f01709dd97bf2bffed6717bb7c41f16e434bfd8058881164260a06030657f0204c0fe4c0fab3193c9618d8fddf070c93f631525937e16897fecfef35b0844ccdc621b3b56035937be2904c0f8317ac4425ffffb37ad7cd86f981ff78904f23ed51f664afc01a1d8b2dd1e20028a058eb9d7091000d7b9d83b07814cfe433ce92ff1cfd1a1ce5efc9e1138bfb642e03043890900001000494441545f042aec20002a44e97e1b738472ffd1731f3952f2cfd17e1653fd73f5394260ae782ee70d01b05cc897707888e41fa3fefc4a597e9d4fe29fbbdba510c85f66746b60ee383fe05d8d4309801a71fad6ca4c36df1eb4c6018727ff88c5769fdf8ccc1a7d2ebd4c9197428008481a4a09020440893031f24e022324ff4c00a6fbef0cd88487a508080df896fd6042f7b8740f812ac7100045221557941c556e25a7963f947063f5d1e6a1c9ff1c9f4cfcabc721baa22508fc8c3e41040408cbb8040880816213178c2dc1e7fdc4adc4eeb7bc8f9cc9652b99643e97813ce96e4a7ecfffb0a7fd234079a1cfd8e4347077e735382c819fd13772c9fe31ac910cdb9b409dfa08808362155785cfc9fe32c96722d9ca411696693693ff21dff33fc730137f8ab132c018da9d400a0122a03b760d7e478000f88ed08eef9f134626fe4c1a5b91e85f637cc8c83f629917f48c61c6ef350f9cbd02811401d95f56f075691f2b394f00348e56248af7841febfcf06f45d2d887fb217fd8276299c9dfa87f9f18ae544b5e0ba2fbbc65ff59c96fbe0e4a8000681498f894e787fd32e14bfafbb2ce87febaff55bf886bc654f2df3796abd5f633fa11113065d46b394500ec18aff850bf27fd586ff7f325fd1df95e5495c9bfebd47fc4f43db66183980604cbcb0488809711aae0550204c0ab04e3fc8be490a343092298345c0e49fee18fd80604cbae0488805d711e5f59350b0880172226f1bf00efc9534fa753ef917f4ed566f27fd262a721f025811401fad79788bcd98a0001f024d948fe5b6230e27f92e113a775bdf77e8e71d7369f60e294fa04f2f65274b737d792d2b1ac673c01f060cce2539abfc0f716a7490c01a1e3d275ea3fe31cbe897140b07423903ffe450474c3ad2102e0ce3e100921557a4ed5490a7732dbf130c97f4798aa1a9a00113074786e1b57f11d02e08ea845f237dd7f07a756879c3adef73fc79ac86b154cf5de438008b88792635e2640007c8130928151ff177c3abdd52d1947bc53e8756baf133fcdd4244004948a5b4d6309801b713b27839cf2774fee06a30ebbbb4dfd9fe32df97708aa26ee264004dc8dca81cf102000ae50930cae40396057afa97ff13e20b89abc9740ce4add7bace30e2250b55902e053e42219e4a8df48f01397035e768941c43b2fb05dda3a80a126eb13d86e43d6f78407c3112000ce218944b07dd04cf99f991cb8ea32f51f3197fc0f0cb2a6ef26b05d9bee3ec1813d09d46d8b0088d84522c8a49f23ff5cc71ecb91047a4dfd878f46fe01c15282001150224cb58c5c5e005c24ff5a919bd7da2e4939e29e826f5e8a3c9b91408a809cb59ad1b7b23e55367c690110492047fc12c1383db8e7d47fc67e1ccf5982c07d04f26f07e8bbf7b172d4370496150091fc53494bfedf74909e6ff798fa3fc7bdcb2c434f76da5a8a80ebd630e1ae6dc89202401218b2d3364fca11f71c39356f6748ba8c9a8a40f4652260aa881ee3cc7202203e3892c0317dedcb567b8cfec30017cd8060998280e701060863751396130011304920200cb6341f9587f0cb5b3e83b9cd1c045e2290cf03e8d72f215cfbe4a504402401c97fc0fede7af41f71cf8b64739131205a26cd4f204540ce6aceefe9701ed637681901704e023e28e3f5d91e89b9471be39165d12a0452e0aee22b3f7724b0840038277f4960c78eb357559d46ff7b99ab1e04462490cf0318dc748ecc0ccd4d2f0024ffa1bb69535126f643c79e71fb12707b735f9e4bd436bd008828364d3251bfe54902ad47ff6196d80704cb1a0442f01201dd423d4743530b80f840b837366e3f6d9a9cc57edcc0b3ac1901b7029aa19db3e26905c03901344d327376893e5eb51cfd8b7d9f186a654802063d1dc2324b13d30a800890e41f10065d5ac7a675fd83626516023f7216e0bf3820700f812905c07904788fff8e39804087d1ff015e6912816108f86d80a6a198a7f2e904c039f91b018edb475bc7a675fde392651902ff10300bf00f0b5b37084c2700c24f0920208cba18fd8f1a19764d46206f05f86d8006419da9caa904c079f43f537c66f3a5b5386b5dff6cf1e0cfdc04cc02cc1ddf97bd9b4a00040d092020acb8107f2b469dcfdf10300bf00da0c7df9eeb8c69048004307ec76c39fd1fde137f01c182c0270266013e01f1f21f02d308807049020808032fcde243fc0d1c75a61d4dc02cc08e1198adaa29048004307eb734fa1f3f462c9c968059806943fb9a6353088040d06c7419755b5e27d02c3ec4dfebc151c3f404cc02ec12e2f92a292f002480f93ae5831e3513170fdae170044626601660e4e81c645b790110dc24808030f2d26afa9ff81b39ea6c1b8c805980170332e3e9a505800450a24bb614682deb2e019791083c40c02cc003b05638b4b4005821407cbc4e80f8bbcec55e04be20e09701bf80f3f55b73be5b5d0018010ede2f5b4dff0fee36f31018924008672260c8c81c63545901101dd974d6317de691565b0ab496753fe2a36311a844c075f38968cd7a4a5901306b40f8f53d01e2ef7b468e40e006010f03de00b3e2eeca02c00870f01edb70fa5fec078f3df386266016e0a1f0cc7b704901600458a2433649d2625f22f68c1c9b80e700c68e4f37eb4a0a806e7434840002084c482084341170675c673eacaa006832ba9c39d0bd7d33fddf9bb8f610788880db000fe19af3e0720280722dd111ff6e6165c4de45ab055875ae48c00cc05d519ffba0720220c2f17f512c6313682200c676997508d42210829a08a815b2ddadad28007687a0c2dd09fc6ff71a7f55e8d6cf2f0efe47600f0266d4bea138fbdb150580243078af3c9d4ebbcf00c468c5c56af0b833af1c013300e542b6afc11505c0be04d4b63701026d6fa2ea43a0118110d644c04db6f3bf514a00e8acf377c82f3c242cbe80e32d049e246066ed4970339c564a0004700f000684c197ddefff137e83479c7995099801b811bd15765713002bc4a4a28f79cf3fcb1f2deeff0710c22f205810684180c06e41b5469dd50400b53a46bf7a4ff6614a26fcc8f9a75c67c9fdb17bf745dc7747aa42047e1320b07fa3d836d6585713006b44653c2f33b167c9247f8a7fb9fe3bd6b9af87b504400fcada589580cfd7a291af260074d47e1d3593fb1fd15c26fbade4bed8d56f313dd98fb5969625e0bafa29f4abbcac26005689cb117e6672cf27ed33d9c7e0fe94eb9ea3fc5b3e9b9ebc45c67e0476224068ef04b258350440b180353037137f26fb2c7f9e1afc884f039b55890002083422b04eb565040085ba7ba7bc4cfcb9bd7b033b5598b3123b55a51a0410b841c0ef01dc0033f3ee320260e62074f42d137d8ef463a07fca75beeed8bca610400081b109ac641d01b046b433d167c2cf92db25bc8e591fa392129162e404043c083841101f758100789458ade333d967d2cf92dbb5ac672d0208742310829b08f8d10df7100d1100438461772332d967d2cf92dbbb37d0a94217a44ea035834010f08d9b80b0d24200cc15ed4cf699f4b3e47675ef0880ea11647f2502cb7fde2a056b0f5b09803d288e51c7cfd3e9344be21f83282b1040008189091000f5839b23fd4cfc7fd677e51f0fdc8ffc87852d043a11587c06a013e5819a2923004e7ea0e673b7d9127f26ffdcfefc7ef5d7ee47568f20fb11406068026504c0d014fb1b67babf3f732d22303d819567dea60fee150709802b5006de95bfcd1f9321a7a9a6fb07e6cd34041040605a0204409dd0be8ffaeb98fbb2a5ee47be8c5005083c4c60d15b6f0f739ae2846a0260c67bddf774a4bccfbfdaa89f00b8a7673806817d09f8dcedcb73e8daaa0980a16136302e054f26ff5c37a85e950820800002ab12a82600564a84ef53fea789befd900f185d94ffc6f665f92b5eff2eab7e20f98dc0c104fe73f9398cedcbcfe8b69dc7bc97836dd5fc8b04aa0980ffbde86f95d333f9979cf28f0bc6fb8521d679b1d8127abc7c7b0bf87f5d94fc33bf9725a71e2f4b1c6a41008103085c7e0e2f3fa3dbf6efcff1fb07fbd77ff959cfcf7c963cff00b39f6d72ddf3aa098015229553fe65927f7cf6b7849f1780df178608545e2cf24290255e5a1040606202f939cfcf7c96bc16c4a5e12dd72908fc55cf41035f4a00cc341d7ea53f6c5ff11bfa36c7dbdbdbad849f17802c575cb30b0104162490d7839fe1f7cfb86ee432a42008fb965d4a09807394864e90671b1f5de594ff1f8f9ed4f3f8f8f466e2bf1ce1e7873b4b4f33b48500027509e4f5e25210981d3838961505c0c1c8766f3e93ff9053fe5bd28ff576ff3e3fc0bb03502102082c49e083183886c0daad56140033cd000c99fc23e1a732df46fb92fedad708de23d083c087db043d1ad4c68f1f1505c02cdf04182af947d27f9fe28f758ef653994bfcae100820d09b405e773631d0fce1c1dece8dd65e390130c98380c324ff48f8ef893f3a668ef8f3c3179b16041040e070028440e310941300671e956f030c91fc25fe734fb2420081d109341202a3bbdddebeaa0260c887e6ee08577ed5ef70db23f9e7d49a11ff1d01730802080c438010d83914250540d1db0099fc0ffdaa5f24fe6dba3feff1efdc95548700020874219042201f547ee99665174b076fa4a4003833ad741be0d0e47f91f88dfacf9dc70a01044a13c841ccfb0f0b95f6e260e32b0b80c3a7d2ef8cddd1c9df74ff9d8172180208942390b30131c679cbebdc03c63b3409541600697f85728850894f84e9fe0abd838d0820b007819f71cd23021e245956009c9f0318fd36403ef1dfddc6f820e4bd31d3fd0f7e181c8e0002a509a408c8db0279fdfbd2116ffe22505600fc32ffc721a3eb73dbdfad32f977b72f927faae04cfedfd9e77d04104060360299fc5304e4757036df76f7a7b40018781620effb774dfe91f84df9effef150210208142590b301374440518f1a985d5a009c79744db4e736bf5c8530e9fa75bf4cfe61508efa53fdc6a605010410589e408a80bc2e2e0fe21680f20220926df77becb7609ef7e7d753ce9bed5791fc53e5eae4ed516b010104ea11c899d1b84cbefd1e1cd573a19dc5e505c0194dd7a47b6ef3daaaeb7dffe8d599fc47f1fd1a0ffb104000811108e4730144c0a748cc220046f80b8192ffa7cee525020820301081bfdedede72d0349049c79a32850038df063874241c36747b16c1c8ffd80f8dd61140a02c819fe7eb675907f6347c0a0190407a26e06cef53e9263ece9db75b7b9ffcf412010410284be06c38117006318d0038fb734462ec36f52ff99fa36c85000208bc468008087e530980f32c40d76f059cdb0c946d17c9bf2d5fb52380c0ec04fee5dff222602a01700e6fb77bf1d15e971907c93f485b10400081fd09a40858f6db01d309801891e70c4096fdbbcaa71aa3ade66243f2ff04dd4b041040e009025f9cb2ec5704a71300e720374fccd14ef3d1bfe41f942d082080407b024b8a802905408ccc7306a06582eef5e05f4b1fda7fa4b4800002080c41e02e2396fb8d80290540863a4440ce02a410c8977b97e63f3c14a37f3fefbb77d4d487000208dc26903f1bbc9408985600648c4304e41fe5d95b04e4e87fef3ad3dcdf25927f76c2651f4cf90dc206020820b0038107aa58eaa1c0a905c039e8391370de7c7d15a262d7fa3e5b744efea6fe3f83f11a010410e8436099e701a6170091b073b4be5742ddab9eafba718f36be6adf7b082080c0440424f87d3300001000494441549e722567619f3ab1d249d30b800c4688801cb5a710c8974f97733d4f9fffdd8931fa77dfff3b48de47000104da1358e27980250440f69548deaf3e0fd074641ec93f15a7fbfe192c05010410d889c00bd54cff3cc03202203bc15904e4e6c325cecd598487cf7be084a602e3013b1c8a00020820f08b400ecc7e6d4df8ff5202e01cbf9c09386fdebd6a9a9ccfa3ffbb8d712002082080c03d045e3e66ea5b01cb098018c9e7b300cf8880977bd2b50acec9bfa9c0b8d6ae7d0820800002771198f656c0720220c3fda008f83b8e6f39fd2ff96750140410406067023b5637e5ad80250540768a48ea3913704ff2cde3f294ddcb79f4bf7bbd2a4400010410d89540de0a98ee21ed650540768d100139b2ff52049c8fc9c35b942fdb6ed1a03a114000813508eceee574b3004b0b80ec1ee7047feb99806609dae83fe92b082080401902d3cd022c2f00b2eb8508c8fbfca7d8fe30dd1ffb7386207637599a898b26d6aa140104102844a091a953cd02100017bd24127ece046c89795b5f1cb1cfa6d1ff3e1cd582000208742630d52c0001f0a9f78408c8517fb3e47f6eae75fde766ac10400081150934f5799a590002e04a3f491190e5ca5b2fef32fa7f19a10a1040008123094c330b4000f4ef4646fffd996b1101041622d0c1d529660108800e3d656bc2e87f23618d000208942630c52c0001d0b70f1afdf7e5ad350410588e403787cbcf0210009dfa8ad17f27d09a41000104fa1028ffcb8004409f8ea21504104000810e047a361103bbd2228000e8d75b4cfff763ad25041040a00781d2b70108800e5d245462e94ed2019126104000811d0874afa2f4c3800440f7fea2410410400001048e274000f48981e9ff3e9cb58200020b1338c8f5b233bc0440e31e63fabf3160d523800002c71228fb202001706cc7d13a02082080c02e048eab24067a25450001d0becf98fe6fcf580b082080c091044ade0620008eec32da4600010410d885804a1e2740003cceecee33625aa8a42abcdb410722800002082481925f07240032740a020820804061024c7f860001f00cb5fbcf71ffff7e568e440001042a132837e34b0054ee6e6c4700010410f801c173040880e7b87d7bd6dbdb5bc9af857ceb98031040000104ae112877cd2700ae85719f7dffb74f356a4100010410b84d609c77aa0dfc088071fa0e4b104000010410e84680006887badc74503b146a46000104da1018acd65233bf04c060bd873908208000026509941af81100edfa59a98ed00e839a114000815604d4fb0a0102e0157a37ceadf620c80d37ec4600010410788c40a9811f01f058701d8d0002082030080166bc468000788d9fb3114000010410284980002819364623800002ab13e0ffab04088057095e3fbfd45741aebb602f02082080c0a3042a3d0346003c1a5dc723800002081c4e8001af1320005e67a806041040000104ca112000ca858cc1082080c0ea04f8bf070102600f8aea400001041040a0180102a058c0988b000208ac4e80fffb102000f6e1a8160410400001044a1120004a858bb1082080c0ea04f8bf170102602f92ea410001041040a0100102a04db0fed7a65ab5228000026b1318ddfbd3e9f4f7e8366ef611001b096b041040000104162240002c146cae22800002b509b07e4f0204c09e34d5850002082080401102044091403113010410589d00fff7254000eccbf3bdb64a0f81bc1bec3f04104000813d08947900309d250092429b52aa23b441a056041040602f0225ea2975dd27004af42946228000020820b02f0102605f9e97b59552829786db46000104462350c49e52bf014300b4eb55a53a423b0c6a46000104d62050edf92f02608d7ec94b041040a03001a6b7204000b4a01a7556538261b20501041040e07902e56efb1200cf07fb9e33cb75887b9c720c020820d0934091b6ca5def0980223d8b99082080000208ec498000d893e6bfebfaf3dfbbec4100010410b89f408d23e3b66fb9eb3d01d0b06f4587283725d41087aa11400081590994bcd61300edbb63c98ed11e8b1610400081ef091439a2e4759e0068dfbb4a768cf658b4800002084c43a0e4efbe1000edfb5fc98ed11e8b1610400081ef08d478bfeaed5e02a071ffaada311a63513d020820300b819f551d2100fa44ce6d803e9cb58200021311e04a5b0204405bbe5bede5be1eb2196e8d00020820709b40ccf296bdbe1300b7e3badb3bd141720620cb6e75aa08010410989b4009efca4eff275d022029f42904401fce5a4100010410b88300017007a49d0ef16d809d40aa060104e62750c1c398dd2d3bfd9f7c0980a4d0a14447c919802c1d5ad30402082080406302a5a7ff930d019014fa95d26ab11f262d2180c0da04c6f73e0675e5afe70440c77e161d266700b2746c555308208000023b13283ffa4f1e044052e85bcaabc6beb8b4860002ab1118dddf18cc4d711d27003af7b4e83866003a33d71c020820b023812946ffc98300480afdcb341da83f3a2d2280c0dc0478d78b0001d08bf4453b310b30c5f4d1854b36114000811508fc9ce9fa4d001cd765cd021cc75ecb082030280166f5234000f463fda1a59954e407c7bc40000104e62430d5e83f4344002485e3ca1fc735ad65041040603402e3da33e3a08d0038b0bf4587ca6f046439d00a4d23800002087c4360ca5bb604c03751eff0b607023b40d60402088c4f60540b63b036e5759a0038b8c745c7ca198029d5e5c168358f000208ec4160daeb3301b047f778b18e1001a92e5308bc5893d311400081aa0486b47bba07ff2e29130097348edd4e1170ac055a4700010410f84de03c38fbfd7ab60d026090884647cb198069a79a06c1cc0c04101894c080664d7f3d260006ea75210272162085c040563105010410588ec0d453ff5b3409808dc438eb1401e358c312041040a03981a11af8fb3c181bcaa816c610002da8be506774bc9c01987eeae905444e450001045a125866104600b4ec464fd61d22203b2011f0243fa72180402d0203599b53ff39081bc8a476a61000edd8be54f359042cd3115f82e564041040e0750299fc73f0f57a4d456a2000c60ed4529d71ec50b00e0104da1018a2d665eefb5fd226002e690cb61db3003903e00f060d1617e62080c0540432f92f799d250006efc744c0e001621e0208bc44e0e093974dfec99d00480a8397b308f050e0e071621e0208d42210d7d62547fe5b9408808dc4e0ebe8a8f93c001130789c988700028f1038f4d8a5937f92270092429142041409143311406074027fc4f5349fb11addcea6f611004df1ee5f79745a3301fb63552302081c40e0a02625ff337802e00ca2d28a08a8142db62280c0200472c42ff95f048300b8805169f32c0296bf875529666c4500814b025db7df9ff68feb668a80ae0d8fdc1801307274beb1eddc9989806f38791b01049626f09efc972670c37902e006982abb5304443985bd946d40b02080400d029daccc9ff73548ba019b00b801a6daee1001d9c97d4db05ae0d88b0002ad0864f2cf87a65bd55fbe5e02a07c08ff71204440767622e01f24b610406048024d8dcad9d07cd82faf874d1baa5e3901503d829fec4f1110c52d814f5cbc4400812508e4a83f937f8a80251c7ec54902e0157a039f1b22c02d8181e3c334045626d0c8f74cfe46fd0fc025001e8055edd01001f961c85b02d470b5e0b1170104ee2590d7b71cf5e7f5eede731c170408808030f39222208ad9809983cc37044a11d8cdd82df167f2cfeddd2a5ea522026091488708f8334a3e1b9033028b78cd4d04109894404ef74bfc2f069700781160b5d34304e4341911502d70ec456012022fba9123fd4cfc791d7bb12aa713000bf681140151cc062c187b2e235094c096f833f9e7765137c6329b00182b1e5dad091170795bc087aa2b7d8d21b02281877dceeb5226fd2cb9fd70054eb84d8000b8cd669977ce42607b50d0ed816522cf5104862590c93e937e96dc1ed6d0ca86110095a3b7b3ed672190f7d6520464d9b905d52180c0ca04bef13d137d964cfa5972fb9b53bcfd0a0102e0157a939ebb0981586fcf09100393c69a5b080c4020137d26fcade4eb01cc9adf040260fe18bfe46188807c4e20cb26067c385f22ea64045625f0c1efbc8e64c28f4bcc29d7f9fac3015eb4274000b4673c4d0ba7d32985c01fa7f8174ee5ac4096d8b4208000025f12c8049fe5fdfa1197905ce7eb2f4ff2665b0204405bbed3d61e1fe014035962f3b4cd0e1004d3469c63083c4420937b964cf4a7f8f7c7b9e4be872a72703b0204403bb64bd51c1fee14035962f3948220bf5590254541161ffca57a04671720909fe9ade467fdbd9c7efdcbc49f25df5f00454d1709809a711bdeeab806fc7d2e290ab2e4c52076fd5ac281f78bc5a7750a05e5c70f0c3018a10f5cfb8c5e7e8e737b2bdbe7fd46c2ffe1df800408800183b2824921037e5f302eb6532828a71306188cd007ae7d4625f8892ed004c044c1e40a020820302201368d49800018332eac420001041040a0290102a0295e9523800002ab13e0ffa80408805123c32e0410400001041a1220001ac25535020820b03a01fe8f4b80001837362c430001041040a0190102a0195a1523800002ab13e0ffc804088091a3c3360410400001041a1120001a81552d020820b03a01fe8f4d8000183b3eac430001041040a0090102a009569522800002ab13e0ffe8040880d123c43e0410400001041a1020001a405525020820b03a01fe8f4f8000183f462c44000104104060770204c0ee485588000208ac4e80ff1508100015a2c44604104000010476264000ec0c5475082080c0ea04f85f83000150234eac44000104104060570204c0ae385586000208ac4e80ff550810005522c54e04104000010476244000ec085355082080c0ea04f85f8700015027562c45000104104060370204c06e285584000208ac4e80ff9508100095a2c55604104000010476224000ec045235082080c0ea04f85f8b0001502b5eac45000104104060170204c02e185582000208ac4e80ffd5081000d522c65e04104000010476204000ec005115082080c0ea04f85f8f0001502f662c460001041040e0650204c0cb085580000208ac4e80ff1509100015a3c6660410400001045e244000bc08d0e9082080c0ea04f85f93000150336eac460001041040e0250204c04bf89c8c000208ac4e80ff550910005523c76e0410400001045e204000bc00cfa9082080c0ea04f85f9700015037762c470001041040e0690204c0d3e89c88000208ac4e80ff9509100095a3c7760410400001049e2440003c09ce69082080c0ea04f85f9b0001503b7eac470001041040e0290204c053d89c84000208ac4e80ffd5091000d523c87e0410400001049e2040003c01cd29082080c0ea04f85f9f0001503f863c400001041040e0610204c0c3c89c80000208ac4e80ff331020006688221f10400001041078900001f020308723800002ab13e0ff1c04088039e2c80b0410400001041e2240003c84cbc1082080c0ea04f83f0b0102609648f203010410400081070810000fc07228020820b03a01fecf4380009827963c410001041040e06e0204c0dda81c88000208ac4e80ff33112000668a265f104000010410b89300017027288721800002ab13e0ff5c040880b9e2c91b041040000104ee224000dc85c941082080c0ea04f83f1b010260b688f20701041040f38ab057000002934944415400813b08100077407208020820b03a01fecf478000982fa63c420001041040e05b0204c0b7881c80000208ac4e80ff33122000668c2a9f104000010410f8860001f00d206f23800002ab13e0ff9c04088039e3ca2b041040000104be2440007c89c79b082080c0ea04f83f2b010260d6c8f20b0104104000812f0810005fc0f116020820b03a01fecf4b80009837b63c430001041040e0260102e0261a6f20800002ab13e0ffcc04088099a3cb370410400001046e1020006e80b11b010410589d00ffe7264000cc1d5fde2180000208207095000170158b9d082080c0ea04f83f3b010260f608f30f0104104000812b0408802b50ec420001045627c0fff9091000f3c79887082080000208fc8b0001f02f247620800002ab13e0ff0a04088015a2cc470410400001043e1120003e01f112010410589d00ffd7204000ac11675e228000020820f0810001f0018717082080c0ea04f8bf0a0102609548f3130104104000810b0204c0050c9b082080c0ea04f8bf0e0102609d58f314010410400081df040880df286c20800002ab13e0ff4a04088095a2cd57041040000104ce04088033082b041040607502fc5f8b0001b056bc798b0002082080c03b0102e01d83ff10400081d509f07f350204c06a11e72f020820800002418000080816041040607502fc5f8f0001b05ecc798c0002082080c00f02402740000104962700c08a04088015a3ce670410400081e5091000cb7701001040607502fc5f930001b066dc798d00020820b038010260f10ec07d0410589d00ff57254000ac1a797e23800002082c4d8000583afc9c470081d509f07f5d0204c0bab1e73902082080c0c20408808583cf750410589d00ff57264000ac1c7dbe23800002082c4b80005836f41c470081d509f07f6d02ff1f0000ffff30ebcadd00000006494441540300fecc7bb53fae82e00000000049454e44ae426082"
   writefile(path,(hex:gsub("..",function(pair)return string.char(tonumber(pair,16))end)))
  end
  return getcustomasset(path)
 end)
 if ok then softShadowAssets.cloud=result end
 return ok and result or nil
end
-- No idle RenderStepped work: guide animation only exists during a drag.
local function snapDotAsset()
 if softShadowAssets.dashes2 then return softShadowAssets.dashes2 end
 if type(writefile)~="function"or type(getcustomasset)~="function"then return nil end
 local ok,asset=pcall(function()
  local path="Altair/SnapDashes2.png";if type(makefolder)=="function"then pcall(makefolder,"Altair")end
  if type(isfile)~="function"or not isfile(path)then local hex="89504e470d0a1a0a0000000d4948445200000008000000080806000000c40fbe8b0000001749444154789c63f88f1d30c03088180c0af062ca1500001c59d8287339161b0000000049454e44ae426082";writefile(path,(hex:gsub("..",function(pair)return string.char(tonumber(pair,16))end)))end
  return getcustomasset(path)
 end);if ok then softShadowAssets.dashes2=asset end;return ok and asset or nil
end
local function buildSnapGuides(root)
 local motion=motionService();local service={lines={},keys={},generations={X=0,Y=0}};local dotAsset=snapDotAsset()
 for _,axis in ipairs({'X','Y'})do
  local line=Instance.new('CanvasGroup');line.Name='SnapGuide'..axis;line.BackgroundTransparency=1;line.GroupTransparency=1;line.BorderSizePixel=0;line.ZIndex=0;line:SetAttribute('AltairThemeIgnore',true);line.Parent=root
  if dotAsset then
   local dots=Instance.new('ImageLabel');dots.Name='Dots';dots.BackgroundTransparency=1;dots.Size=UDim2.fromScale(1,1);dots.Image=dotAsset;dots.ScaleType=Enum.ScaleType.Tile;dots.TileSize=UDim2.fromOffset(8,8);dots.ImageColor3=Color3.fromRGB(210,220,235);dots.ZIndex=0;dots.Parent=line
  else
   for index=0,32 do local dot=Instance.new('Frame');dot.Name='Dot';dot.BorderSizePixel=0;dot.Size=UDim2.fromOffset(2,2);dot.BackgroundColor3=Color3.fromRGB(210,220,235);dot.ZIndex=0;dot.Parent=line end
  end
  local gradient=Instance.new('UIGradient');gradient.Rotation=axis=='X'and 90 or 0;gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.18,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(.82,1),NumberSequenceKeypoint.new(1,1)});gradient.Parent=line
  service.lines[axis]=line
 end
 function service:Update(point,x,y,enabled)
  local fresh=false;local size=root.AbsoluteSize;local origin=root.AbsolutePosition
  for _,axis in ipairs({'X','Y'})do
   local value;if enabled then if axis=='X'then value=x else value=y end end;local line=self.lines[axis]
   if self.keys[axis]~=value then self.generations[axis]+=1 end
   if value then
    local localPoint=point-origin;local coordinate=value-(axis=='X'and origin.X or origin.Y)
    line.Position=axis=='X'and UDim2.fromOffset(coordinate,0)or UDim2.fromOffset(0,coordinate)
    line.Size=axis=='X'and UDim2.new(0,1,1,0)or UDim2.new(1,0,0,1)
    if not dotAsset then
     for index,dot in ipairs(line:GetChildren())do if dot:IsA('Frame')then
      local distance=(index-17)*8;dot.Position=axis=='X'and UDim2.fromOffset(0,localPoint.Y+distance)or UDim2.fromOffset(localPoint.X+distance,0)
     end end
    end
    local gradient=line.UIGradient;gradient.Offset=axis=='X'and Vector2.new(0,localPoint.Y/math.max(1,size.Y)-.5)or Vector2.new(localPoint.X/math.max(1,size.X)-.5,0)
    if self.keys[axis]~=value then motion:Create(line,TweenInfo.new(.16),{GroupTransparency=.5}):Play();fresh=true end
   elseif self.keys[axis]then motion:Create(line,TweenInfo.new(.65),{GroupTransparency=1}):Play()end
   self.keys[axis]=value
  end
  return fresh
 end
 function service:Pulse()
  for axis,value in pairs(self.keys)do if value then
   self.generations[axis]+=1;local generation=self.generations[axis]
   local line=self.lines[axis];motion:Create(line,TweenInfo.new(.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{GroupTransparency=.18}):Play()
   task.delay(.5,function()if line.Parent and self.keys[axis]==value and self.generations[axis]==generation then motion:Create(line,TweenInfo.new(.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{GroupTransparency=.5}):Play()end end)
  end end
 end
 function service:Clear()self:Update(Vector2.zero,nil,nil,false)end
 return service
end
local function buildLoading(root,parent,cloudAsset,position,onScreen)
 local screen=Instance.new('ScreenGui');screen.Name='AltairLoading';screen.IgnoreGuiInset=true;screen.DisplayOrder=root.DisplayOrder+1;screen.ResetOnSpawn=false;pcall(function()screen.ScreenInsets=Enum.ScreenInsets.None end)
 if onScreen then onScreen(screen)end
 screen.Parent=parent
 local group=Instance.new('CanvasGroup');group.Name='Sequence';group.BackgroundTransparency=1;group.AnchorPoint=Vector2.new(.5,.5);group.Position=UDim2.fromScale(.5,.65);group.Size=UDim2.fromOffset(240,130);group.Parent=screen
 local scale=Instance.new('UIScale');scale.Parent=group
 local cloud=Instance.new('ImageLabel');cloud.Name='Cloudz';cloud.BackgroundTransparency=1;cloud.Size=UDim2.fromOffset(68,54);cloud.Position=UDim2.fromOffset(86,0);cloudAsset=cloudAsset or loadingCloud();cloud.Image=cloudAsset or '';cloud.ScaleType=Enum.ScaleType.Fit;cloud.Parent=group
 if not cloudAsset then applyIcon(cloud,'cloud')end
 local text=Instance.new('TextLabel');text.Name='Stage';text.BackgroundTransparency=1;text.Size=UDim2.fromOffset(240,24);text.Position=UDim2.fromOffset(0,68);text.Text='Building interface';text.TextSize=12;text.TextColor3=Color3.fromRGB(243,246,252);text.FontFace=Font.new('rbxasset://fonts/families/BuilderSans.json',Enum.FontWeight.Medium);text.Parent=group
 local track=Instance.new('Frame');track.Name='LoadingBar';track.Size=UDim2.fromOffset(160,4);track.Position=UDim2.fromOffset(40,108);track.BackgroundColor3=Color3.new(1,1,1);track.BackgroundTransparency=.84;track.BorderSizePixel=0;track.ClipsDescendants=true;track.Parent=group
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(1,0);corner.Parent=track
 local fill=track:Clone();fill:ClearAllChildren();fill.Name='Progress';fill.Position=UDim2.fromOffset(0,0);fill.Size=UDim2.fromScale(0,1);fill.BackgroundTransparency=.12;fill.Parent=track;corner:Clone().Parent=fill
 local glow=Instance.new('UIGradient');glow.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(.8,.05),NumberSequenceKeypoint.new(1,0)});glow.Parent=fill
 local shadow=Instance.new('ImageLabel');shadow.Name='LoadingShadow';shadow.BackgroundTransparency=1;shadow.AnchorPoint=Vector2.new(.5,.5);shadow.Image=resolveSoftShadowAsset(true)or '';shadow.ScaleType=Enum.ScaleType.Slice;shadow.SliceCenter=Rect.new(64,0,192,64);shadow.Size=UDim2.fromOffset(288,64);shadow.ImageColor3=Color3.new(1,1,1);shadow.ImageTransparency=.62;shadow.ZIndex=0;shadow.Parent=group
 local mask=Instance.new('UIGradient');mask.Parent=shadow
 local loadingProgress=Instance.new('NumberValue');loadingProgress.Name='LoadingProgressValue';loadingProgress.Parent=screen
 loadingProgress.Changed:Connect(function(value)root:SetAttribute('AltairLoadingProgress',value);mask.Transparency=loadingMask(value)end)
 root:SetAttribute('AltairLoadingProgress',0);mask.Transparency=loadingMask(0)
 local motion=motionService(function()return root:GetAttribute('AltairReduceMotion')==true end);local service={Screen=screen,progress=0}
 screen.Destroying:Once(function()
  service.exiting=true;service.stageGeneration=(service.stageGeneration or 0)+1
  local exit=service.exitTween;service.exitTween=nil
  if exit then exit:Cancel()end
 end)
 function service:Anchor(point,animated)
  local viewport=screen.AbsoluteSize;if viewport.X<=0 then viewport=workspace.CurrentCamera.ViewportSize end
  local upper=point.Y<viewport.Y/2;local x=math.clamp(point.X,120,math.max(120,viewport.X-120))
  local destination=UDim2.fromOffset(x,point.Y+(upper and 45 or -45))
  if animated then motion:Create(group,TweenInfo.new(.2,Enum.EasingStyle.Quint),{Position=destination}):Play()else group.Position=destination end
  track.Position=UDim2.fromOffset(40+point.X-x,upper and 18 or 108)
  shadow.Position=UDim2.fromOffset(120+point.X-x,upper and 20 or 110)
  cloud.Position=UDim2.fromOffset(86,upper and 64 or 0)
  self.textRest=UDim2.fromOffset(0,upper and 37 or 68);text.Position=self.textRest
 end
 local viewport=screen.AbsoluteSize;if viewport.X<=0 then viewport=workspace.CurrentCamera.ViewportSize end
 local x=type(position)=='table'and tonumber(position.x)or .5;local y=type(position)=='table'and tonumber(position.y)or nil
 service:Anchor(Vector2.new(math.clamp(x or .5,0,1)*viewport.X,y and math.clamp(y,0,1)*viewport.Y or viewport.Y-38),false)
 function service:Stage(value,label)
  if self.exiting or not screen.Parent then return end
  self.progress=math.max(self.progress,math.clamp(value,0,1))
  self.stageGeneration=(self.stageGeneration or 0)+1;local generation=self.stageGeneration
  motion:Create(text,TweenInfo.new(.07),{TextTransparency=1,Position=self.textRest-UDim2.fromOffset(0,3)}):Play()
  task.delay(.075,function()
   if not screen.Parent or self.stageGeneration~=generation then return end
   text.Text=label;text.Position=self.textRest+UDim2.fromOffset(0,4)
   motion:Create(text,TweenInfo.new(.15,Enum.EasingStyle.Quint),{TextTransparency=0,Position=self.textRest}):Play()
  end)
  motion:Create(fill,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Size=UDim2.fromScale(self.progress,1)}):Play()
  motion:Create(loadingProgress,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Value=self.progress}):Play()
  game:GetService('RunService').Heartbeat:Wait() -- Render this milestone before the next initialization batch.
 end
 function service:Finish(drag,hideBar)
  if self.finishing or self.exiting or not screen.Parent then return end
  self.finishing=true
  local real=drag and drag:FindFirstChild('Drag')
  if real then
   drag.Visible=true;real.Visible=true
   local vertical=real.AbsoluteSize.Y>real.AbsoluteSize.X
   real.Size=vertical and UDim2.fromOffset(2,160)or UDim2.fromOffset(160,2)
   local origin=screen.AbsolutePosition;local center=real.AbsolutePosition+real.AbsoluteSize/2-origin
   track.Visible=false;shadow.Visible=false
   local completedFill=Instance.new('Frame');completedFill.Name='LoadingProgress';completedFill.BorderSizePixel=0;completedFill.BackgroundColor3=Color3.new(1,1,1);completedFill.BackgroundTransparency=.12;completedFill.Size=real.AbsoluteSize.Y>real.AbsoluteSize.X and UDim2.fromScale(1,self.progress)or UDim2.fromScale(self.progress,1);completedFill.ZIndex=real.ZIndex+1;completedFill.Parent=real;corner:Clone().Parent=completedFill
   local halo=Instance.new('UIStroke');halo.Name='LoadingGlow';halo.Color=Color3.new(1,1,1);halo.Thickness=3;halo.Transparency=1;halo.Parent=completedFill
   motion:Create(completedFill,TweenInfo.new(.22,Enum.EasingStyle.Quint),{Size=UDim2.fromScale(1,1)}):Play()
   motion:Create(halo,TweenInfo.new(.2),{Transparency=.65}):Play()
   self.completedFill=completedFill
  end
  self:Stage(1,'Ready');task.wait(root:GetAttribute('AltairReduceMotion')and .17 or .24)
  if not screen.Parent then return end
  if self.completedFill then
   local completedFill=self.completedFill;motion:Create(completedFill,TweenInfo.new(.24),{BackgroundTransparency=1}):Play()
   motion:Create(completedFill.LoadingGlow,TweenInfo.new(.24),{Transparency=1}):Play()
   task.delay(.26,function()completedFill:Destroy()end)
  end
  self.exiting=true;self.stageGeneration=(self.stageGeneration or 0)+1
  motion:Freeze(text,{'TextTransparency','Position'})
  local exit=motion:Create(group,TweenInfo.new(.24),{GroupTransparency=1})
  self.exitTween=exit
  exit.Completed:Once(function(state)
   if self.exitTween~=exit then return end
   self.exitTween=nil
   if(state==Enum.PlaybackState.Completed or state==Enum.PlaybackState.Cancelled)and screen.Parent then screen:Destroy()end
  end)
  exit:Play()
  if real and hideBar then
   motion:Create(real,TweenInfo.new(.24),{BackgroundTransparency=1}):Play()
   task.wait(.24);if drag.Parent then drag.Visible=false end
  end
  root:SetAttribute('AltairLoadingProgress',nil)
 end
 return service
end

-- Altair discovery keeps query, provider, detail and confirmation ownership
-- separate from its compact material and animation layout.
local function buildDiscovery(context)
 local root=context.Root
 local service
 local function featuredHeight()return 538 end
 local native=game:GetService("TweenService")
 local ratio=600/908
 local function u(n)return n*ratio end
 local function browseTop()return 150 end
 local function browserPose(x)return UDim2.fromOffset(u(x or 24),u(browseTop()))end
 local function detailPoseAt(x)return UDim2.fromOffset(u(x or 24),u(76))end
 local function selectedHeight()return 508 end
 -- Authored material bytes are shared with Altair; the theme controller owns
 -- light/dark adaptation instead of a second colored overlay.
 local function srgb(r,g,b)
  if r==18 and g==21 and b==28 then return Design.Surface end
  if r==29 and g==33 and b==43 then return Design.Raised end
  if r==38 and g==43 and b==55 then return Design.Well end
  if r==157 and g==169 and b==189 then return Design.Muted end
  if r==160 and g==176 and b==200 then return Design.Edge end
  if r==243 and g==246 and b==252 then return Design.Ink end
  return Color3.fromRGB(r,g,b)
 end

 local function rect(o,x,y,w,h)o.Position=UDim2.fromOffset(u(x),u(y));o.Size=UDim2.fromOffset(u(w),u(h))end
 local function corner(o,r)local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,u(r));c.Parent=o end
 local function make(class,parent,name,x,y,w,h)
  local o=Instance.new(class);o.Name=name;o.BorderSizePixel=0;o.BackgroundTransparency=1;o.ZIndex=3
  rect(o,x,y,w,h);o.Parent=parent;return o
 end
 local regular=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
 local semibold=Font.new(regular.Family,Enum.FontWeight.SemiBold)
 local function text(parent,name,value,x,y,w,h,size,color,bold)
  local o=make("TextLabel",parent,name,x,y,w,h);o.Text=value;o.TextSize=u(size);o.TextColor3=color or srgb(230,230,230);o.FontFace=bold and semibold or regular
  o.TextXAlignment=Enum.TextXAlignment.Left;o.TextTruncate=Enum.TextTruncate.AtEnd;o:SetAttribute("AltairDesignRole",bold and"ink"or"muted");o:SetAttribute("AltairDesignManaged",true);return o
 end
 -- Browser, result and detail states share the same original Altair material.
 local function syncSurface(panel)
  local source=root.Scripts;local backdrop=panel.Backdrop
  backdrop.BackgroundColor3=source.BackgroundColor3
  backdrop.BackgroundTransparency=Design.surfaceAlpha(backdrop,root:GetAttribute("AltairPanelTransparency")or .1)
  local from=source:FindFirstChildOfClass("UIGradient");local to=backdrop.Material
  if from then
   for _,key in ipairs({"Color","Rotation","Offset","Enabled"})do to[key]=from[key]end
   to.Transparency=NumberSequence.new(0)
  else to.Color=ColorSequence.new(Color3.new(1,1,1));to.Transparency=NumberSequence.new(0)end
  local outline=source:FindFirstChildOfClass("UIStroke")
  if outline then
   panel.Outline.Color=outline.Color;panel.Outline.Thickness=.6;panel.Outline.Transparency=.86
   local fromEdge=outline:FindFirstChildOfClass("UIGradient");local toEdge=panel.Outline:FindFirstChildOfClass("UIGradient")
   if fromEdge then
    if not toEdge then toEdge=Instance.new("UIGradient");toEdge.Parent=panel.Outline end
    for _,key in ipairs({"Color","Transparency","Rotation","Offset","Enabled"})do toEdge[key]=fromEdge[key]end
   elseif toEdge then toEdge:Destroy()end
  end
 end
 if context.BuildOnly then
  local previous=root.ScriptSearch;local position=previous.Position;previous:Destroy()
  local panel=make("CanvasGroup",root,"ScriptSearch",0,0,908,530);panel.Position=position;panel.AnchorPoint=Vector2.new(.5,.5);panel.ZIndex=260;panel.Visible=false;panel.ClipsDescendants=true
  panel.BackgroundTransparency=1;panel:SetAttribute("ReferenceScriptSearch",true);panel:SetAttribute("AltairDesignRole","surface");panel:SetAttribute("AltairDesignManaged",true);panel:SetAttribute("AltairDesignFixedTransparency",.02);corner(panel,27)
  local backdrop=make("Frame",panel,"Backdrop",0,0,908,530);backdrop.Size=UDim2.fromScale(1,1);backdrop.ZIndex=0;backdrop.BackgroundColor3=Design.Surface;backdrop.BackgroundTransparency=.02;backdrop:SetAttribute("AltairDesignRole","surface");backdrop:SetAttribute("AltairSurface",true);backdrop:SetAttribute("AltairDesignFixedTransparency",.02);corner(backdrop,27)
  local material=Instance.new("UIGradient");material.Name="Material";material.Rotation=105;material.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(224,224,224));material.Parent=backdrop
  local border=Instance.new("UIStroke");border.Name="Outline";border.Color=Design.Edge;border.Thickness=.6;border.Transparency=.9;border.BorderStrokePosition=Enum.BorderStrokePosition.Inner;border.Parent=panel
  local header=make("CanvasGroup",panel,"Header",24,20,860,118)
  local back=make("TextButton",header,"Back",0,0,44,36);back.Text="";back.AutoButtonColor=false;back.BackgroundColor3=Design.Well;back.BackgroundTransparency=.24;back:SetAttribute("ReferenceSearchControl",true);corner(back,10)
  local arrow=make("ImageLabel",back,"Icon",12,8,20,20);applyIcon(arrow,"arrow-left");arrow.ImageColor3=Design.Muted
  text(header,"Label","Discover",58,0,420,36,27,Design.Ink,true)
  local count=text(header,"Count","3 sources",644,4,174,28,16,Design.Muted);count.AnchorPoint=Vector2.new(1,0);count.Position=UDim2.new(1,0,0,u(4));count.TextXAlignment=Enum.TextXAlignment.Right
  local spinner=make("Frame",header,"Spinner",833,7,22,22);spinner.Visible=false;corner(spinner,22)
  local arc=Instance.new("UIStroke");arc.Color=Design.Muted;arc.Thickness=u(3);arc.Parent=spinner
  local mask=Instance.new("UIGradient");mask.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.499,1),NumberSequenceKeypoint.new(.501,0),NumberSequenceKeypoint.new(1,0)});mask.Parent=arc
  for _,y in ipairs({0,22})do local cap=make("Frame",spinner,"ArcCap",11,y,3,3);cap.AnchorPoint=Vector2.new(.5,.5);cap.BackgroundColor3=Design.Muted;cap.BackgroundTransparency=1;corner(cap,2)end
  local field=make("Frame",header,"SearchWell",0,54,860,56);field.BackgroundColor3=Design.Well;field.BackgroundTransparency=.3;field:SetAttribute("AltairDesignRole","control");corner(field,12)
  local edge=Instance.new("UIStroke");edge.Color=Design.Edge;edge.Thickness=.6;edge.Transparency=.9;edge.Parent=field
  local icon=make("ImageLabel",header,"Icon",17,70,23,23);applyIcon(icon,"search");icon.ImageColor3=Design.Muted
  local box=make("TextBox",header,"SearchBox",54,54,788,56);box.Text="";box.PlaceholderText="Search scripts, games or tools";box.FontFace=regular;box.TextSize=u(22);box.TextColor3=Design.Ink;box.PlaceholderColor3=Design.Muted;box.TextXAlignment=Enum.TextXAlignment.Left;box.ClearTextOnFocus=false;box.MultiLine=false;box:SetAttribute("AltairDesignRole","ink")
  local browser=make("CanvasGroup",panel,"Browser",24,150,860,356);browser.ClipsDescendants=true
  local pinned=make("Frame",browser,"Pinned",0,0,860,0);pinned.Visible=false
  local pinLayout=Instance.new("UIListLayout");pinLayout.SortOrder=Enum.SortOrder.LayoutOrder;pinLayout.Parent=pinned
  local scroll=make("ScrollingFrame",browser,"Scroll",0,0,860,356);scroll.Size=UDim2.fromScale(1,1);scroll.CanvasSize=UDim2.new();scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.ScrollBarThickness=u(3);scroll.ScrollBarImageColor3=Design.Muted;scroll.ScrollBarImageTransparency=.6;scroll.ScrollingDirection=Enum.ScrollingDirection.Y
  local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,u(8));layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Parent=scroll
  local padding=Instance.new("UIPadding");padding.PaddingRight=UDim.new(0,u(5));padding.PaddingBottom=UDim.new(0,u(8));padding.Parent=scroll
  -- This gradient masks opacity on the entire CanvasGroup; coloring it would
  -- multiply every result, artwork and heading by the material's dark tint.
  local falloff=Instance.new("UIGradient");falloff.Name="EdgeFade";falloff:SetAttribute("AltairThemeIgnore",true);falloff.Rotation=90;falloff.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(.96,0),NumberSequenceKeypoint.new(1,1)});falloff.Parent=browser
  local detail=make("CanvasGroup",panel,"Detail",24,76,860,430);detail.Visible=false;detail.Interactable=false
  local art=make("ImageLabel",detail,"Artwork",0,0,300,220);art.ScaleType=Enum.ScaleType.Crop;art.BackgroundColor3=Design.Raised;art.BackgroundTransparency=.12;corner(art,16)
  local title=text(detail,"Title","",324,0,536,72,30,Design.Ink,true);title.TextWrapped=true;title.TextYAlignment=Enum.TextYAlignment.Top
  local creator=text(detail,"Creator","",324,82,536,40,18,Design.Muted);creator.TextWrapped=true;creator.TextYAlignment=Enum.TextYAlignment.Top
  text(detail,"Metrics","",324,130,536,26,18,Design.Muted)
  make("Frame",detail,"Tags",324,171,536,30)
  local descriptionWell=make("Frame",detail,"DescriptionWell",0,240,860,100);descriptionWell.BackgroundColor3=Design.Raised;descriptionWell.BackgroundTransparency=.2;descriptionWell:SetAttribute("AltairDesignRole","inset");corner(descriptionWell,14)
  local descriptionScroll=make("ScrollingFrame",descriptionWell,"Scroll",14,12,832,76);descriptionScroll.CanvasSize=UDim2.new();descriptionScroll.AutomaticCanvasSize=Enum.AutomaticSize.None;descriptionScroll.ScrollBarThickness=u(2);descriptionScroll.ScrollBarImageColor3=Design.Muted;descriptionScroll.ScrollBarImageTransparency=.6;descriptionScroll.ScrollingDirection=Enum.ScrollingDirection.Y
  local desc=text(descriptionScroll,"Description","",0,0,820,24,20,Design.Muted);desc.Size=UDim2.new(1,-u(8),0,u(24));desc.TextWrapped=true;desc.TextYAlignment=Enum.TextYAlignment.Top;desc.TextTruncate=Enum.TextTruncate.None
  local cancel=make("TextButton",detail,"Cancel",488,356,116,52);cancel.Text="Back";cancel.TextColor3=Design.Muted;cancel.TextSize=u(21);cancel.FontFace=semibold;cancel.AutoButtonColor=false;cancel:SetAttribute("ReferenceIndependentOpacity",true);corner(cancel,10)
  local background=make("Frame",detail,"RunBackground",620,356,240,52);background.BackgroundColor3=Color3.new(1,1,1);background.BackgroundTransparency=1;background:SetAttribute("ReferenceIndependentOpacity",true);background:SetAttribute("AltairDesignRole","control");corner(background,10)
  local run=make("TextButton",detail,"Run",620,356,240,52);run.ZIndex=4;run.Text="Run script →";run.TextColor3=Design.Ink;run.TextSize=u(23);run.FontFace=semibold;run.AutoButtonColor=false;run:SetAttribute("ReferenceIndependentOpacity",true);run:SetAttribute("AltairDesignRole","ink");corner(run,10)
  local runMaterial=Instance.new("ObjectValue");runMaterial.Name="AltairContrastMaterial";runMaterial.Value=background;runMaterial.Parent=run
  local fill=Instance.new("UIGradient");fill.Rotation=28;fill.Color=ColorSequence.new(srgb(32,73,88),srgb(45,105,113));fill.Parent=background
  local rim=Instance.new("UIStroke");rim.Color=Design.Edge;rim.Thickness=.6;rim.Transparency=.9;rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.BorderStrokePosition=Enum.BorderStrokePosition.Inner;rim.Parent=background
  local highlight=Instance.new("UIGradient");highlight.Name="Highlight";highlight.Rotation=90;highlight.Transparency=NumberSequence.new(1,0);highlight.Parent=rim
  local glow=make("ImageLabel",detail,"RunGlow",608,350,264,70);glow.ZIndex=2;glow.Image=resolveSoftShadowAsset("small")or"";glow.ScaleType=Enum.ScaleType.Slice;glow.SliceCenter=Rect.new(31,31,33,33);glow.SliceScale=u(.4);glow.ImageColor3=Design.Ink;glow.ImageTransparency=1
  local hover=Instance.new("NumberValue");hover.Name="HoverProgress";hover.Parent=run
  local reveal=Instance.new("NumberValue");reveal.Name="RevealProgress";reveal.Parent=run
  local hint=make("ImageLabel",panel,"ScrollHint",0,0,20,12);hint.AnchorPoint=Vector2.new(.5,1);hint.Position=UDim2.new(.5,0,1,-u(7));hint.ImageTransparency=1;hint.ImageColor3=Design.Muted;hint.Visible=false;hint.ZIndex=10;applyIcon(hint,"chevron-down")
  local credit=text(panel,"Attribution","RoScripts · ScriptBlox · RobloxScripts",24,0,760,15,12,Design.Muted);credit.Position=UDim2.new(0,u(24),1,-u(14));credit.Visible=false
  syncSurface(panel);panel.UICorner.CornerRadius=root.Scripts.UICorner.CornerRadius;backdrop.UICorner.CornerRadius=panel.UICorner.CornerRadius
  return
 end
 local panel=root.ScriptSearch;local header=panel.Header;local input=header.SearchBox;local browser=panel.Browser;local scroll=browser.Scroll;local pinned=browser.Pinned;local detail=panel.Detail
 local description=detail.DescriptionWell.Scroll.Description
 service={items={},page="closed",version=0,detailVersion=0,animations=setmetatable({},{__mode="k"}),height=538}
 local surfaceConnections={}
 local function watch(object,property,callback)surfaceConnections[#surfaceConnections+1]=object:GetPropertyChangedSignal(property):Connect(callback)end
 local descriptionMeasure,descriptionWidth=0,0
 local function descriptionScale()
  local factor=1;local owner=description
  while owner and owner~=root do local scale=owner:FindFirstChildOfClass("UIScale");if scale then factor*=scale.Scale end;owner=owner.Parent end
  return math.max(.001,factor)
 end
 local function measureDescription()
  descriptionMeasure+=1;local generation=descriptionMeasure
  task.defer(function()
   if not root.Parent or not description.Parent or generation~=descriptionMeasure then return end
   local width=description.AbsoluteSize.X/descriptionScale();if width<=0 then return end
   descriptionWidth=width
   local params=Instance.new("GetTextBoundsParams");params.Font=description.FontFace;params.Size=description.TextSize;params.Width=width;params.Text=description.Text;params.RichText=false
   local ok,bounds=pcall(function()return game:GetService("TextService"):GetTextBoundsAsync(params)end);params:Destroy()
   if not ok or not root.Parent or not description.Parent or generation~=descriptionMeasure then return end
   local height=math.max(1,math.ceil(bounds.Y+2));description.Size=UDim2.new(1,-u(8),0,height);detail.DescriptionWell.Scroll.CanvasSize=UDim2.fromOffset(0,height+1)
  end)
 end
 watch(description,"Text",measureDescription);watch(description,"TextSize",measureDescription);watch(description,"FontFace",measureDescription)
 watch(description,"AbsoluteSize",function()if math.abs(description.AbsoluteSize.X/descriptionScale()-descriptionWidth)>.5 then measureDescription()end end)
 task.defer(measureDescription)
 local function refreshSurface()syncSurface(panel)end
 watch(root.Scripts,"BackgroundColor3",refreshSurface)
 local sourceGradient=root.Scripts:FindFirstChildOfClass("UIGradient")
 if sourceGradient then for _,key in ipairs({"Color","Transparency","Rotation","Offset","Enabled"})do watch(sourceGradient,key,refreshSurface)end end
 local sourceOutline=root.Scripts:FindFirstChildOfClass("UIStroke")
 if sourceOutline then
  for _,key in ipairs({"Color","Thickness"})do watch(sourceOutline,key,refreshSurface)end
  local edge=sourceOutline:FindFirstChildOfClass("UIGradient")
  if edge then for _,key in ipairs({"Color","Transparency","Rotation","Offset","Enabled"})do watch(edge,key,refreshSurface)end end
 end
 surfaceConnections[#surfaceConnections+1]=root:GetAttributeChangedSignal("AltairPanelTransparency"):Connect(refreshSurface)
 watch(panel.UICorner,"CornerRadius",function()panel.Backdrop.UICorner.CornerRadius=panel.UICorner.CornerRadius end)
 local white=Design.Ink;local gray=Design.Muted
 local function setOpacity(group,alpha)group.GroupTransparency=alpha end
 local function stopAnimation(object)
  local old=service.animations[object];if old then old:Cancel();service.animations[object]=nil end
 end
 local function animate(object,time,goal,style,direction)
  stopAnimation(object)
  if root:GetAttribute("AltairReduceMotion")==true then time=math.min(time,.08)end
  local animation=native:Create(object,TweenInfo.new(time,style or Enum.EasingStyle.Exponential,direction or Enum.EasingDirection.Out),goal)
  service.animations[object]=animation;animation.Completed:Once(function()if service.animations[object]==animation then service.animations[object]=nil end end);animation:Play();return animation
 end
 local function selectedArtworkSize()return 300,220 end
 watch(root.Scripts.UICorner,"CornerRadius",function()
  if service.page~="closed"then stopAnimation(panel.UICorner);panel.UICorner.CornerRadius=root.Scripts.UICorner.CornerRadius end
 end)
 local function themeInk(object,property,fallback)return object:GetAttribute("AltairTheme_"..property)or fallback end
 local function renderRun()
  local hover=detail.Run.HoverProgress.Value;local reveal=detail.Run.RevealProgress.Value
  detail.Run.TextTransparency=1-reveal;detail.Run.TextStrokeTransparency=1;detail.Run.BackgroundTransparency=1
  detail.RunBackground.BackgroundTransparency=1-reveal
  detail.Run.TextColor3=themeInk(detail.Run,"TextColor3",white)
  local gradient=detail.RunBackground.UIGradient;local themed=gradient:GetAttribute("AltairTheme_Color")
  if typeof(themed)=="ColorSequence"then
   local points={};for _,point in ipairs(themed.Keypoints)do points[#points+1]=ColorSequenceKeypoint.new(point.Time,point.Value:Lerp(Color3.new(1,1,1),hover*.04))end;gradient.Color=ColorSequence.new(points)
  else gradient.Color=ColorSequence.new(srgb(32,73,88):Lerp(srgb(38,86,101),hover),srgb(45,105,113):Lerp(srgb(53,120,127),hover))end
  detail.RunBackground.UIStroke.Transparency=1-reveal*(.10+.13*hover)
  detail.RunBackground.UIStroke.Highlight.Rotation=90+180*hover
  detail.RunGlow.ImageTransparency=1-reveal*(.02+.04*hover)
 end
 watch(detail.Run.HoverProgress,"Value",renderRun);watch(detail.Run.RevealProgress,"Value",renderRun);renderRun()
 local function later(delay,callback)local version=service.version;task.delay(delay,function()if root.Parent and version==service.version then callback()end end)end
 local function boundedQuery(value)
  -- Match Main's transport limit before starting a loading presentation.
  local query=tostring(value or "")
  if #query>160 then query=query:sub(1,160)end
  while #query>0 and utf8.len(query)==nil do query=query:sub(1,-2)end
  return query
 end
 local function invalidate()service.version+=1;service.runToken=nil;service.busy=false;if context.Invalidate then context.Invalidate()end end
 local function clear(parent)for _,o in ipairs(parent:GetChildren())do if o:IsA("GuiObject")then o:Destroy()end end end
 local function views(n)n=tonumber(n)or 0;return n>=1e6 and string.format("%.1fM",n/1e6):gsub("%.0M","M")or n>=1000 and string.format("%.0fK",n/1000)or tostring(n)end
 local function age(value)
  local ok,date=pcall(DateTime.fromIsoDate,tostring(value or ""));if not ok or not date then return ""end
  local days=math.max(0,math.floor((os.time()-date.UnixTimestamp)/86400));return days<1 and "today"or days<7 and(days.."d ago")or days<30 and(math.floor(days/7).."w ago")or(math.floor(days/30).."mo ago")
 end
 local function gameName(result)local value=type(result.game)=="table"and result.game.name;return type(value)=="string"and value~=""and value or "Universal"end
 local function providerSite(result)
  local provider=tostring(result.provider or "Unknown source")
  return({RoScripts="RoScripts.io",ScriptBlox="ScriptBlox.com"})[provider]or provider
 end
 local function artwork(parent,name,result,x,y,w,h,r)
  local box=make("Frame",parent,name,x,y,w,h);box.BackgroundColor3=Design.Well;box.BackgroundTransparency=.18;box:SetAttribute("AltairDesignRole","inset");corner(box,r or 12)
  local image=make("ImageLabel",box,"Image",0,0,w,h);image.ImageTransparency=.999;image.ScaleType=Enum.ScaleType.Crop;corner(image,r or 12)
  local placeholder=make("ImageLabel",box,"Placeholder",0,0,48,48);placeholder.AnchorPoint=Vector2.new(.5,.5);placeholder.Position=UDim2.fromScale(.5,.5);local ok,asset=pcall(Molto.GetAsset,"scroll-fill","phosphor");if ok and asset then placeholder.Image=asset.Url;placeholder.ImageRectSize=asset.ImageRectSize;placeholder.ImageRectOffset=asset.ImageRectOffset;placeholder.ScaleType=Enum.ScaleType.Fit else applyIcon(placeholder,"scroll")end;placeholder.ImageColor3=srgb(200,200,200)
  local info=type(result.game)=="table"and result.game or {};local id=tonumber(info.placeId or info.gameId)
  task.spawn(function()
   local asset
   if context.Image then local ok,value=pcall(context.Image,result,function()return root.Parent~=nil and box.Parent~=nil end);if ok then asset=value end end
   if not box.Parent then return end
   if asset then image.Image=asset elseif id then image.Image="rbxthumb://type=GameThumbnail&id="..id.."&w=768&h=432"end
  end)
  local revealed=false
  local function reveal()if not revealed and image.Parent and image.IsLoaded and image.Image~=""then revealed=true;animate(placeholder,.12,{ImageTransparency=1});image.ImageTransparency=1;animate(image,.18,{ImageTransparency=0})end end
  image:GetPropertyChangedSignal("IsLoaded"):Connect(reveal)
  local warming=false
  local function warm()
   if warming or not image.Parent or image.Image==""then return end
   warming=true
   task.spawn(function()
    while (service.assetLoads or 0)>=3 do if not image.Parent or not root.Parent then return end;task.wait(.03)end
    if not image.Parent or not root.Parent then return end
    service.assetLoads=(service.assetLoads or 0)+1
    pcall(function()game:GetService("ContentProvider"):PreloadAsync({image.Image})end)
    service.assetLoads-=1;warming=false
    if image.Parent then reveal()end
   end)
  end
  image:GetPropertyChangedSignal("Image"):Connect(warm);task.defer(function()reveal();warm()end)
  return box
 end
 local function feedback(button,target,idle,hover)
  local rest=target.Position
  button.MouseEnter:Connect(function()if panel.Visible and service.page~="closed"then animate(target,.16,{BackgroundTransparency=hover});animate(button,.16,{BackgroundTransparency=1})end end)
  button.MouseLeave:Connect(function()if service.page=="closed"then return end;animate(target,.2,{BackgroundTransparency=idle})end)
  button.MouseButton1Down:Connect(function()if service.page=="closed"then return end;animate(target,.08,{BackgroundTransparency=math.max(0,hover-.15)})end)
  button.MouseButton1Up:Connect(function()if service.page=="closed"then return end;animate(target,.18,{BackgroundTransparency=hover})end)
 end
 local function click(parent,name,callback)
  local button=Instance.new("TextButton");button.Name=name;button.Text="";button.BackgroundTransparency=1;button.BorderSizePixel=0;button.AutoButtonColor=false;button.Size=UDim2.fromScale(1,1);button.ZIndex=8;button:SetAttribute("ReferenceSearchControl",true);button.Parent=parent
  button.MouseButton1Click:Connect(callback);return button
 end
 local function heading(value,order,height,parent)
  local label=text(parent or scroll,"Section",value,6,0,840,height or 32,20,gray,true);label.LayoutOrder=order;return label
 end
 local function placeholderGradient(object)
  local gradient=Instance.new("UIGradient");gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.new(.75,.75,.75));gradient.Parent=object
 end
 local function tag(parent,value,x,y)
  local width=({Verified=84,Key=50,Mobile=74})[value]or math.max(50,#value*10+22);local o=text(parent,"Tag",value,x,y,width,30,17,Design.Ink,true);o.TextXAlignment=Enum.TextXAlignment.Center;o.BackgroundColor3=value=="Verified"and srgb(31,69,62)or Design.Well;o.BackgroundTransparency=.18;o:SetAttribute("AltairDesignRole","control");corner(o,8);return width+8
 end
 local function tags(parent,result,x,y)
  if result.verified then x+=tag(parent,"Verified",x,y)end
  if result.key then x+=tag(parent,"Key",x,y)end
  if result.mobile then x+=tag(parent,"Mobile",x,y)end
 end
 function service:Resize(height,time)
  local bottomInset=browseTop()+24
  local fraction=math.clamp(1-28/math.max(29,height-bottomInset),.05,.99);browser.EdgeFade.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(fraction,0),NumberSequenceKeypoint.new(1,1)})
  local size=UDim2.fromOffset(600,u(height))
  self.height=height;local position=context.Position(size)
  animate(panel,time or .48,{Size=size,Position=position})
  browser.Size=UDim2.new(1,-u(48),1,-u(bottomInset))
 end
 function service:ConfigureResults(fixed)
  pinned.Visible=false;scroll.Position=UDim2.fromOffset(0,0);scroll.Size=UDim2.fromScale(1,1)
 end
 function service:Controls(alpha,time)
  animate(detail.Cancel,time,{TextTransparency=alpha})
  animate(detail.Run.RevealProgress,time,{Value=1-alpha})
 end
 function service:Spinner(enabled)
  local reduced=root:GetAttribute("AltairReduceMotion")==true;local wasEnabled=self.spinnerEnabled
  self.spinnerEnabled=not not enabled
  if enabled and wasEnabled and self.spinReduced==reduced and(reduced or self.spin)then header.Spinner.Visible=true;return end
  self.spinReduced=reduced
  self.spinVersion=(self.spinVersion or 0)+1;local version=self.spinVersion
  local stroke=header.Spinner.UIStroke
  if self.spin then self.spin:Cancel();self.spin=nil end
  if enabled then
   header.Spinner.Visible=true;stroke.Transparency=1;header.Spinner.Rotation=0
   for _,cap in ipairs(header.Spinner:GetChildren())do if cap:IsA("Frame")then animate(cap,.1,{BackgroundTransparency=0},Enum.EasingStyle.Sine)end end
   animate(stroke,.1,{Transparency=0},Enum.EasingStyle.Sine);animate(header.Count,.1,{TextTransparency=1},Enum.EasingStyle.Sine)
   if not reduced then self.spin=native:Create(header.Spinner,TweenInfo.new(.8,Enum.EasingStyle.Linear,Enum.EasingDirection.Out,-1),{Rotation=360});self.spin:Play()end
   task.delay(.1,function()if root.Parent and self.spinVersion==version then header.Count.Visible=false end end)
  else
   for _,cap in ipairs(header.Spinner:GetChildren())do if cap:IsA("Frame")then animate(cap,.1,{BackgroundTransparency=1},Enum.EasingStyle.Sine)end end
   header.Count.Visible=true;animate(header.Count,.1,{TextTransparency=0},Enum.EasingStyle.Sine);animate(stroke,.1,{Transparency=1},Enum.EasingStyle.Sine)
   task.delay(.1,function()if root.Parent and self.spinVersion==version then header.Spinner.Visible=false end end)
  end
 end

 surfaceConnections[#surfaceConnections+1]=root:GetAttributeChangedSignal("AltairReduceMotion"):Connect(function()
  if root.Parent and service.spinnerEnabled then service:Spinner(true)end
 end)

 function service:Transition(page,height,render)
  self.version+=1;local version=self.version;self.page=page
  self:Resize(height)
  local empty=true;for _,object in ipairs(scroll:GetChildren())do if object:IsA("GuiObject")then empty=false;break end end
  animate(browser,.13,{GroupTransparency=1})
  later(empty and .02 or .13,function()
   clear(scroll);clear(pinned);scroll.CanvasPosition=Vector2.zero;browser.Visible=true;setOpacity(browser,1);render()
   animate(browser,.19,{GroupTransparency=0,Position=browserPose()})
  end)
  return version
 end
 local function suggestionNames(query,games,results)
  local names={tostring(query or "")};local seen={[names[1]:lower()]=true}
  for _,items in ipairs({games or {},results or {}})do for _,item in ipairs(items)do
   local name=tostring(type(item)=="table"and(item.name or item.title)or item):gsub("%b[]",""):match("^%s*(.-)%s*$")
   if name~=""and not seen[name:lower()]and #names<4 then names[#names+1]=name;seen[name:lower()]=true end
  end end
  return names
 end
 function service:PreviewTransition(query,games,results,loading,render)
  local retained=self.suggestionRows and self.suggestionRows[1]and self.suggestionRows[1].Parent==scroll
   and(self.page=="suggestions"or self.page=="loading")
  local height=loading and(retained and self.height or 530)or(#suggestionNames(query,games,results)*48+450)
  if not retained then
   return self:Transition(loading and "loading"or"suggestions",height,function()
    self:ConfigureResults(false);self:Suggestions(query,games or {},results);render()
   end)
  end
  self.version+=1;self.page=loading and "loading"or"suggestions";self:Resize(height)
  if not loading then self:Suggestions(query,games or {},results)end
  local outgoing={}
  for _,object in ipairs(scroll:GetChildren())do if object:IsA("GuiObject")and object:GetAttribute("SearchPreviewResult")then
   outgoing[#outgoing+1]=object;animate(object,.1,{GroupTransparency=1})
  end end
  later(#outgoing>0 and .1 or 0,function()
   for _,object in ipairs(outgoing)do object:Destroy()end
   render()
   for _,object in ipairs(scroll:GetChildren())do if object:IsA("CanvasGroup")and object:GetAttribute("SearchPreviewResult")then
    object.GroupTransparency=1;animate(object,.16,{GroupTransparency=0})
   end end
  end)
 end
 function service:Skeleton(preview,query,games)
  self:Spinner(true)
  if preview and self.page=="loading"and self.loadingQuery==query then return end
  self.loadingQuery=query;self.loadingPreview=preview
  local function render()
   if not preview then self:ConfigureResults(false);heading("Finding scripts",0)end
   local count=preview and 2 or 4
   for i=1,count do
    local row=make("CanvasGroup",scroll,"Skeleton"..i,0,0,860,92);row.LayoutOrder=i+1;row:SetAttribute("SearchPreviewResult",preview==true)
    local art=make("Frame",row,"Artwork",10,12,96,68);art.BackgroundTransparency=.16;art.BackgroundColor3=Design.Well;corner(art,9)
    local first=make("Frame",row,"Title",124,14,370,18);first.BackgroundColor3=Design.Well;first.BackgroundTransparency=.25;corner(first,6)
    local second=make("Frame",row,"Metadata",124,48,570,14);second.BackgroundColor3=Design.Raised;second.BackgroundTransparency=.15;corner(second,5)
    placeholderGradient(art);placeholderGradient(first);placeholderGradient(second)
   end
  end
  if preview then self:PreviewTransition(query,games or self.lastGames,nil,true,render)else self:Transition("loading",630,render)end
 end
 function service:Suggestions(query,games,results)
  local names=suggestionNames(query,games,results)
  if not(self.suggestionRows and self.suggestionRows[1]and self.suggestionRows[1].Parent==scroll)then self.suggestionRows={};self.suggestionDivider=nil end
  for i,name in ipairs(names)do
   local row=self.suggestionRows[i]
   if not row then
    row=make("Frame",scroll,"Suggestion",0,0,860,40);row.LayoutOrder=i-10;row.BackgroundColor3=Design.Well;corner(row,9);self.suggestionRows[i]=row
    local icon=make("ImageLabel",row,"Icon",10,11,18,18);applyIcon(icon,"search");icon.ImageColor3=gray
    text(row,"Title",name,44,0,794,40,20,Design.Muted)
    local button=click(row,"Choose",function()self:Commit(row:GetAttribute("Query"))end);feedback(button,row,1,.45)
   end
   row.Title.Text=name;row:SetAttribute("Query",name);row.Visible=true
  end
  for i=#names+1,#self.suggestionRows do self.suggestionRows[i].Visible=false end
  if not(self.suggestionDivider and self.suggestionDivider.Parent==scroll)then
   local divider=make("Frame",scroll,"Divider",6,0,848,13);divider.LayoutOrder=-1;local line=make("Frame",divider,"Line",0,12,848,1);line.BackgroundColor3=Design.Edge;line.BackgroundTransparency=.9;self.suggestionDivider=divider
   heading("Suggested scripts",0,32)
  end
 end
 local function providerAccent(result)
  return({RoScripts=Color3.fromRGB(100,184,164),ScriptBlox=Color3.fromRGB(231,166,80),["RobloxScripts.com"]=Color3.fromRGB(210,139,116)})[result.provider]or Design.Muted
 end
 function service:Row(result,index)
  local row=make(self.preview and"CanvasGroup"or"Frame",scroll,"Result"..index,0,0,860,92);row.LayoutOrder=index;row:SetAttribute("SearchPreviewResult",self.preview==true)
  row.BackgroundColor3=Design.Raised;row.BackgroundTransparency=1;corner(row,10)
  artwork(row,"Artwork",result,10,12,96,68,9)
  local total=(result.verified and 92 or 0)+(result.key and 58 or 0)+(result.mobile and 82 or 0)
  text(row,"Title",result.title,124,8,720-total,28,23,white,true)
  if total>0 then tags(row,result,848-total,7)end
  local dot=make("Frame",row,"SourceMark",124,46,5,5);dot.BackgroundColor3=providerAccent(result);dot.BackgroundTransparency=0;corner(dot,3)
  text(row,"Metadata",providerSite(result),138,38,330,20,17,gray)
  local updated=age(result.updatedAt);local metrics=text(row,"Metrics",views(result.views).." views"..(updated~=""and(" · "..updated)or""),482,38,362,20,17,gray);metrics.TextXAlignment=Enum.TextXAlignment.Right
  text(row,"Context",gameName(result),124,65,720,18,17,gray)
  local divider=make("Frame",row,"Divider",124,91,720,1);divider.BackgroundColor3=Design.Edge;divider.BackgroundTransparency=.93;divider:SetAttribute("AltairDesignRole","divider")
  local button=click(row,"Choose",function()self:Select(result)end);feedback(button,row,1,.55)
 end
 function service:Results(results,preview,query,games)
  self.items=results;self.preview=preview;panel.ScrollHint.Visible=false;self.hintDismissed=false;self.lastQuery=query;self.lastGames=games
  self.loadingQuery=nil;local height=preview and(#suggestionNames(query,games,results)*48+450)or 724
  self:Spinner(false);header.Count.Text=preview and ""or(#results.." results")
  local function render()
   self:ConfigureResults(false)
   if not preview then heading("Search results",0,32)end
   for i,result in ipairs(results)do
    if i>(preview and 2 or 20)then break end
    self:Row(result,i)
   end
   if #results==0 then
    if preview then
     local empty=make("CanvasGroup",scroll,"EmptyResults",0,0,860,54);empty.LayoutOrder=1;empty:SetAttribute("SearchPreviewResult",true)
     text(empty,"Title","No matching scripts. Try another name.",6,0,840,42,21,gray)
    else heading("No scripts found",1)end
   end
   if not preview and #results>5 then panel.ScrollHint.Visible=true;panel.ScrollHint.ImageTransparency=1;later(.25,function()if self.page=="results"and not self.hintDismissed then animate(panel.ScrollHint,.18,{ImageTransparency=0})end end)end
  end
  if preview then self:PreviewTransition(query,games,results,false,render)else self:Transition("results",height,render)end
 end
 local function featuredDeck()
  local deck=service.featuredDeck
  return deck and deck.heading.Parent==scroll and deck.shelf.Parent==scroll and deck or nil
 end
 local function featuredKey(result)
  local info=type(result.game)=="table"and result.game or {}
  local image=result.image or result.thumbnailUrl or result.thumbnail or info.imageUrl or info.image or info.iconUrl or ""
  if type(image)=="table"then image=image.url or ""end
  return tostring(result.title).."\0"..providerSite(result).."\0"..tostring(result.views).."\0"..tostring(result.key).."\0"..tostring(image)
 end
 local fillFeatured
 local function mountFeatured()
  local deck={heading=heading("Popular scripts",0,32),cards={}}
  deck.shelf=make("Frame",scroll,"Featured",0,0,860,312);deck.shelf.LayoutOrder=1;service.featuredDeck=deck
  for i=1,4 do
   local width,height=424,150
   local card=make("CanvasGroup",deck.shelf,"Card"..i,((i-1)%2)*436,math.floor((i-1)/2)*162,width,height);card.GroupTransparency=1;card.BackgroundColor3=Design.Raised;card.BackgroundTransparency=.12;card:SetAttribute("AltairDesignRole","inset");corner(card,14)
   local outline=Instance.new("UIStroke");outline.Name="Outline";outline.Color=Design.Edge;outline.Thickness=.6;outline.Transparency=.9;outline.BorderStrokePosition=Enum.BorderStrokePosition.Inner;outline.Parent=card
   local skeleton=make("CanvasGroup",card,"Skeleton",0,0,width,height)
   local placeholders={{12,14,96,112,9},{124,20,272,18,6},{124,91,234,13,5},{124,119,180,12,5}}
   for _,r in ipairs(placeholders)do
    local bar=make("Frame",skeleton,"Placeholder",r[1],r[2],r[3],r[4]);bar.BackgroundColor3=Design.Well;bar.BackgroundTransparency=.15;corner(bar,r[5]);placeholderGradient(bar)
   end
   local content=make("CanvasGroup",card,"Content",0,0,width,height);content.GroupTransparency=1
   local slot={root=card,skeleton=skeleton,content=content,revision=0};deck.cards[i]=slot
   slot.button=click(card,"Choose",function()if service.page=="featured"and slot.result then service:Select(slot.result)end end);slot.button.Interactable=false
   slot.button.MouseEnter:Connect(function()if service.page=="featured"then animate(card,.16,{BackgroundTransparency=.02});animate(outline,.16,{Transparency=.65})end end)
   slot.button.MouseLeave:Connect(function()if service.page=="featured"then animate(card,.2,{BackgroundTransparency=.12});animate(outline,.2,{Transparency=.9})end end)
   later((i-1)*.045,function()if card.Parent then animate(card,.16,{GroupTransparency=0})end end)
  end
  deck.empty=make("CanvasGroup",deck.shelf,"EmptyState",0,0,860,312);deck.empty.Visible=false;deck.empty.GroupTransparency=1
  local empty=text(deck.empty,"Title","Nothing to feature right now",20,80,820,36,24,white,true);empty.TextXAlignment=Enum.TextXAlignment.Center
  local help=text(deck.empty,"Description","Search for an experience or script above.",20,126,820,30,20,gray);help.TextXAlignment=Enum.TextXAlignment.Center
  local pending=service.pendingFeatured
  if pending and pending.version==service.version then service.pendingFeatured=nil;fillFeatured(pending.items)end
 end
 fillFeatured=function(results)
  local deck=featuredDeck();if not deck then return false end
  local returning=service.page=="detail";service.page="featured";service.items=results;service.preview=nil;service.pendingFeatured=nil
  for i,slot in ipairs(deck.cards)do
   local result=results[i];slot.revision+=1;local revision=slot.revision
   if result then
    local key=featuredKey(result);local previous=slot.result;slot.result=result;slot.button.Interactable=true;slot.root.Visible=true
    animate(slot.root,.16,{GroupTransparency=0})
    if key~=slot.key then
     local function render()
      if slot.revision~=revision or not slot.content.Parent then return end
      stopAnimation(slot.content);setOpacity(slot.content,1);clear(slot.content);slot.key=key
       slot.artwork=artwork(slot.content,"Artwork",result,12,14,96,112,9)
       local title=text(slot.content,"Title",result.title,124,14,284,56,22,white,true);title.TextWrapped=true;title.TextYAlignment=Enum.TextYAlignment.Top
       local line=make("Frame",slot.content,"Divider",124,78,284,1);line.BackgroundColor3=Design.Edge;line.BackgroundTransparency=.9;line:SetAttribute("AltairDesignRole","divider")
       local mark=make("Frame",slot.content,"SourceMark",124,95,5,5);mark.BackgroundTransparency=0;mark.BackgroundColor3=providerAccent(result);corner(mark,3)
       text(slot.content,"Metadata",providerSite(result),138,88,270,20,17,gray)
       text(slot.content,"Metrics",(result.key and"Key required · "or"")..views(result.views).." views",124,116,284,18,16,gray)
      animate(slot.skeleton,.14,{GroupTransparency=1})
      later((i-1)*.035,function()if slot.revision==revision and slot.content.Parent then animate(slot.content,.18,{GroupTransparency=0})end end)
     end
     if previous then animate(slot.content,.1,{GroupTransparency=1});later(.1,render)else render()end
    else animate(slot.skeleton,.14,{GroupTransparency=1});animate(slot.content,.18,{GroupTransparency=0})end
   else
    slot.result=nil;slot.key=nil;slot.button.Interactable=false
    animate(slot.root,.14,{GroupTransparency=1})
    later(.15,function()if slot.revision==revision and not slot.result and slot.root.Parent then slot.root.Visible=false end end)
   end
  end
  if #results==0 then deck.empty.Visible=true;animate(deck.empty,.18,{GroupTransparency=0})
  else animate(deck.empty,.14,{GroupTransparency=1});later(.15,function()if deck.empty.Parent and #service.items>0 then deck.empty.Visible=false end end)end
  if returning then animate(browser,.19,{GroupTransparency=0,Position=browserPose()})end
  return true
 end
 function service:Idle(results)
  if self.page=="closed"then return end
  results=results or {};panel.ScrollHint.Visible=false;self:Spinner(false)
  if self.height~=featuredHeight()then self:Resize(featuredHeight(),.36)end
  if fillFeatured(results)then return end
  if self.page~="featured-loading"then self:IdleLoading()end
  self.pendingFeatured={version=self.version,items=results}
 end
 function service:IdleLoading()
  self:Spinner(false);header.Count.Text="3 sources";panel.ScrollHint.Visible=false
  local deck=featuredDeck()
  if deck then
   self.page="featured-loading";self:ConfigureResults(false)
   browser.Visible=true;animate(browser,.19,{GroupTransparency=0,Position=browserPose()})
   if self.height~=featuredHeight()then self:Resize(featuredHeight(),.36)end
   for _,slot in ipairs(deck.cards)do if slot.root.Visible then animate(slot.root,.16,{GroupTransparency=0})end end
   return
  end
  self.featuredDeck=nil;self.pendingFeatured=nil
  self:Transition("featured-loading",featuredHeight(),function()self:ConfigureResults(false);mountFeatured()end)
 end
 function service:Select(result)
  if self.page=="closed"or self.page=="detail"then return end
  invalidate();self.detailVersion+=1;self.controlsReady=false;detail.Interactable=false;detail.Cancel.Interactable=false;detail.Run.Interactable=false;self:Spinner(false);self.previous={items=self.items,preview=self.preview,query=self.lastQuery,games=self.lastGames,page=self.page};self.selected=result;self.page="detail";panel.ScrollHint.Visible=false;local version=self.version
  input:ReleaseFocus();input.TextEditable=false
  animate(header,.1,{GroupTransparency=1});animate(browser,.18,{GroupTransparency=1,Position=browserPose(8)})
  later(.11,function()if self.page=="detail"then
    header.Label.Text="Script details";header.Count.Text=providerSite(result);header.SearchBox.Visible=false;header.SearchWell.Visible=false;header.Icon.Visible=false
   animate(header,.16,{GroupTransparency=0})
  end end)
  detail.Title.Text=result.title;detail.Creator.Text="Source: "..providerSite(result).." · "..gameName(result).." · by "..tostring(type(result.owner)=="table"and result.owner.username or "Unknown")
  detail.Metrics.Text=views(result.views).." views"..(age(result.updatedAt)~=""and(" · updated "..age(result.updatedAt))or "")
  stopAnimation(description);description.TextTransparency=0;description.Text=tostring(result.description or result.features or(context.Detail and"Loading script details…"or"No description provided."));detail.DescriptionWell.Scroll.CanvasPosition=Vector2.zero
   clear(detail.Artwork);detail.Artwork.Image="";detail.Artwork.BackgroundTransparency=1;local artWidth,artHeight=selectedArtworkSize();artwork(detail.Artwork,"SelectedArtwork",result,0,0,artWidth,artHeight,16)
  clear(detail.Tags);tags(detail.Tags,result,0,0)
  stopAnimation(detail.Cancel);stopAnimation(detail.Run.HoverProgress);stopAnimation(detail.Run.RevealProgress)
  detail.Cancel.TextTransparency=1;detail.Cancel.TextColor3=themeInk(detail.Cancel,"TextColor3",gray);detail.Run.HoverProgress.Value=0;detail.Run.RevealProgress.Value=0
  later(.25,function()if self.page=="detail"then self.controlsReady=true;detail.Interactable=true;detail.Cancel.Interactable=true;detail.Run.Interactable=true end end)
  later(.1,function()animate(detail.Cancel,.15,{TextTransparency=0});animate(detail.Run.RevealProgress,.15,{Value=1})end)
  detail.Run.Text="Run script →";detail.Visible=true;detail.Position=detailPoseAt(44);setOpacity(detail,1);animate(detail,.24,{GroupTransparency=0,Position=detailPoseAt()},Enum.EasingStyle.Quart);self:Resize(selectedHeight(),.32)
  later(.19,function()if self.page=="detail"then browser.Visible=false end end)
  if context.Detail then task.spawn(function()
   local ok,info=pcall(context.Detail,result)
   if root.Parent and self.version==version and self.selected==result then
    local nextText
    if ok and info then result.features=info.features or info.description;nextText=tostring(result.features or "No description provided.")
    elseif not result.description and not result.features then nextText="Description unavailable."end
    if nextText and description.Text~=nextText then
     animate(description,.08,{TextTransparency=1})
     later(.085,function()if self.page=="detail"and self.selected==result then description.Text=nextText;animate(description,.15,{TextTransparency=0})end end)
    end
   end
  end)end
 end
 function service:Back()
  if not self.previous then return end;invalidate();self.detailVersion+=1;local detailVersion=self.detailVersion;self.controlsReady=false;detail.Interactable=false;detail.Cancel.Interactable=false;detail.Run.Interactable=false;self.selected=nil;header.Visible=true;browser.Visible=true
  animate(header,.08,{GroupTransparency=1});animate(detail,.16,{GroupTransparency=1,Position=detailPoseAt(44)});self:Controls(1,.12)
  local previous=self.previous;self.previous=nil
  if previous.page=="featured"then self:Idle(previous.items)else self:Results(previous.items,previous.preview,previous.query,previous.games)end
  later(.09,function()header.Label.Text="Discover";header.SearchBox.Visible=true;header.SearchWell.Visible=true;header.Icon.Visible=true;input.TextEditable=true;animate(header,.16,{GroupTransparency=0})end)
  task.delay(.2,function()if root.Parent and detail.Parent and self.detailVersion==detailVersion and self.page~="detail"then detail.Visible=false end end)
 end
 function service:Commit(query)
  query=boundedQuery(query or input.Text)
  invalidate();self.suppress=true;input.Text=query;self.suppress=false;input:ReleaseFocus()
  query=query:match("^%s*(.-)%s*$")
  if query==""then self:IdleLoading();if self.LoadIdle then self.LoadIdle()end;return end
  if self.Query then self.Query(query,false)end
 end
 function service:Stop()
  invalidate();self.detailVersion+=1;detail.Interactable=false;self.spinnerEnabled=false;self.spinVersion=(self.spinVersion or 0)+1;self.life=(self.life or 0)+1;if self.spin then self.spin:Cancel();self.spin=nil end
  for _,animation in pairs(self.animations)do animation:Cancel()end;table.clear(self.animations)
  if self.activeCarry then self.activeCarry:Destroy();self.activeCarry=nil end
 end
 function service:Carry(face,entering,duration)
  if self.activeCarry then self.activeCarry:Destroy();self.activeCarry=nil end
  if not face then return end
  local carry=Instance.new("CanvasGroup");carry.Name="ButtonMorph";carry.BackgroundTransparency=1;carry.Size=UDim2.fromScale(1,1);carry.ZIndex=20;carry.GroupTransparency=entering and 0 or 1;carry.Parent=panel;self.activeCarry=carry
  face.AnchorPoint=Vector2.zero;face.Position=UDim2.fromScale(0,0);face.Size=UDim2.fromScale(1,1);face.Parent=carry
  for _,object in ipairs(face:GetDescendants())do if object:IsA("GuiButton")then object.Interactable=false;object.Active=false end end
  animate(carry,duration,{GroupTransparency=entering and 1 or 0})
  task.delay(duration+.04,function()if carry.Parent then carry:Destroy()end;if self.activeCarry==carry then self.activeCarry=nil end end)
 end
 function service:Open(position,size,onReady,face)
  self:Stop();self.page="featured-loading";self.selected=nil;self.previous=nil
  panel.Visible=true;panel.Interactable=true;input.TextEditable=true;panel.Position=position;panel.Size=size;panel.BackgroundTransparency=1;panel.GroupTransparency=0;syncSurface(panel)
  self.featuredDeck=nil;self.pendingFeatured=nil;clear(scroll)
  header.Visible=true;setOpacity(header,1);browser.Visible=true;setOpacity(browser,1);detail.Visible=false
  self.suppress=true;input.Text="";self.suppress=false;header.Count.Text="3 sources";header.Label.Text="Discover";header.SearchBox.Visible=true;header.SearchWell.Visible=true;header.Icon.Visible=true;header.Back.Icon.ImageColor3=themeInk(header.Back.Icon,"ImageColor3",gray);browser.Position=browserPose()
  self:IdleLoading();animate(header,.2,{GroupTransparency=0})
  local rounding=face and face:FindFirstChildOfClass("UICorner")
  panel.UICorner.CornerRadius=rounding and rounding.CornerRadius or UDim.new(0,u(16));animate(panel.UICorner,.48,{CornerRadius=root.Scripts.UICorner.CornerRadius})
  self:Carry(face,true,.18)
  local life=self.life;task.delay(.48,function()if root.Parent and self.life==life and self.page~="closed"and onReady then onReady()end end)
 end
 function service:Close(position,size,onClosed,face,duration)
  self:Stop();panel.ScrollHint.Visible=false;self.page="closed";self.controlsReady=false;panel.Interactable=false;input.TextEditable=false;detail.Cancel.Interactable=false;detail.Run.Interactable=false;self:Spinner(false);input:ReleaseFocus()
  animate(header,.12,{GroupTransparency=1});animate(browser,.12,{GroupTransparency=1});animate(detail,.12,{GroupTransparency=1});self:Controls(1,.12)
  local time=duration or .48
  local rounding=face and face:FindFirstChildOfClass("UICorner")
  animate(panel.UICorner,time,{CornerRadius=rounding and rounding.CornerRadius or UDim.new(0,u(16))})
  animate(panel,time,{Position=position,Size=size})
  self:Carry(face,false,time)
  later(time+.01,function()panel.Visible=false;if onClosed then onClosed()end end)
 end
 scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()if scroll.CanvasPosition.Y>2 and not service.hintDismissed then service.hintDismissed=true;animate(panel.ScrollHint,.15,{ImageTransparency=1})end end)
 input:GetPropertyChangedSignal("Text"):Connect(function()
  if service.suppress or service.page=="closed"then return end
  local text=boundedQuery(input.Text)
  if input.Text~=text then service.suppress=true;input.Text=text;service.suppress=false end
  invalidate();local query=text:match("^%s*(.-)%s*$")
  if query==""then service:IdleLoading();if service.LoadIdle then service.LoadIdle()end;return end
  service:Skeleton(true,query);local version=service.version
  task.delay(.24,function()if service.version==version and root.Parent and service.Query then service.Query(query,true)end end)
 end)
 input.Focused:Connect(function()if service.page~="closed"and service.page~="detail"then animate(header.SearchWell,.16,{BackgroundTransparency=.12});animate(header.SearchWell.UIStroke,.16,{Transparency=.65})end end)
 input.FocusLost:Connect(function(enter)
  if service.page~="closed"then animate(header.SearchWell,.18,{BackgroundTransparency=.3});animate(header.SearchWell.UIStroke,.18,{Transparency=.9})
  else header.SearchWell.BackgroundTransparency=.3;header.SearchWell.UIStroke.Transparency=.9 end
  if enter and service.page~="closed"and service.page~="detail"and input.Text~=""then service:Commit(input.Text)end
 end)
 header.Back.MouseButton1Click:Connect(function()if service.page=="detail"then service:Back()elseif service.page~="closed"and context.Back then context.Back()end end)
 header.Back.MouseEnter:Connect(function()if service.page~="closed"then animate(header.Back.Icon,.15,{ImageColor3=themeInk(header.Label,"TextColor3",white)})end end)
 header.Back.MouseLeave:Connect(function()if service.page~="closed"then animate(header.Back.Icon,.18,{ImageColor3=themeInk(header.Back.Icon,"ImageColor3",gray)})end end)
 detail.Cancel.MouseButton1Click:Connect(function()if service.page=="detail"and service.controlsReady then service:Back()end end)
 detail.Run.MouseButton1Click:Connect(function()
  if service.busy or not service.selected or service.page~="detail"or not service.controlsReady then return end
  local version=service.version;local result=service.selected;local token={};service.runToken=token;service.busy=true;detail.Run.Text="Loading…"
  task.spawn(function()local ok,problem=pcall(context.Execute,result)
   if service.runToken==token then service.busy=false;service.runToken=nil end;if root.Parent and service.version==version then detail.Run.Text="Run script →";if not ok or problem then if context.Error then context.Error(tostring(ok and problem or problem))end end end
  end)
 end)
 detail.Run.MouseEnter:Connect(function()if service.page=="detail"and service.controlsReady then animate(detail.Run.HoverProgress,.2,{Value=1},Enum.EasingStyle.Sine)end end)
 detail.Run.MouseLeave:Connect(function()if service.page=="detail"and service.controlsReady then animate(detail.Run.HoverProgress,.2,{Value=0},Enum.EasingStyle.Sine)end end)
 detail.Cancel.MouseEnter:Connect(function()if service.page=="detail"and service.controlsReady then animate(detail.Cancel,.2,{TextColor3=themeInk(detail.Title,"TextColor3",white)},Enum.EasingStyle.Sine)end end)
 detail.Cancel.MouseLeave:Connect(function()if service.page=="detail"and service.controlsReady then animate(detail.Cancel,.2,{TextColor3=themeInk(detail.Cancel,"TextColor3",gray)},Enum.EasingStyle.Sine)end end)
 root.Destroying:Connect(function()service:Stop();for _,connection in ipairs(surfaceConnections)do connection:Disconnect()end end)
 return service
end

-- Built-in alternatives to small standalone utility scripts. No global hooks.
local function buildNativeUtilities(context)
 local run=game:GetService('RunService');local input=context.Input or game:GetService('UserInputService')
 local actions=context.Actions or game:GetService('ContextActionService');local light=context.Lighting or game:GetService('Lighting')
 local service={alive=true,entries={},order={},connections={},fullbright=false,freecamera=false,cameraGeneration=0,starting=false}
 local key='AltairNativeCamera-'..game:GetService('HttpService'):GenerateGUID(false)
 local mouseState,view,velocity,pitch,yaw,position;local cameraState;local controls
 local function alive()return service.alive and(not context.IsAlive or context.IsAlive())end
 local function notice(title,body)if alive()and context.Notify then context.Notify(title,body)end end
 local function camera()return context.GetCamera and context.GetCamera()or workspace.CurrentCamera end
 local function releaseMouse()
  local previous=mouseState;mouseState=nil
  if previous then pcall(function()if input.MouseBehavior==Enum.MouseBehavior.LockCurrentPosition then input.MouseBehavior=previous end end)end
 end
 local function releaseBindings()
  if context.UnbindRender then pcall(context.UnbindRender,key)else pcall(run.UnbindFromRenderStep,run,key)end
  pcall(actions.UnbindAction,actions,key)
 end
 local function restoreCamera()
  releaseMouse();velocity=Vector3.zero
  local generation=service.cameraGeneration
  local state=cameraState
  if state and state.camera then
   local c=state.camera;local read,kind=pcall(function()return c.CameraType end)
   if read then
    if kind~=Enum.CameraType.Scriptable then
     if cameraState==state then cameraState=nil end
    else
     -- Free camera owns pose/type, never FOV or the game's current subject.
     -- Keep failed restoration pending for an explicit retry; do not claim
     -- success or release the snapshot after a transient property error.
     local pose=pcall(function()c.CFrame=state.cframe end)
     local focus=pcall(function()c.Focus=state.focus end)
     if pose and focus then
      local restored=pcall(function()c.CameraType=state.kind end)
      if restored and cameraState==state then cameraState=nil end
     end
    end
   end
  end
  if controls then
   local owned=controls;local restored,result=pcall(owned.Enable,owned)
   if restored and result~=false and controls==owned and service.cameraGeneration==generation then controls=nil end
  end
  return cameraState==nil and controls==nil
 end
 function service:SetFreeCamera(enabled)
  enabled=enabled==true
  if not enabled then
   self.cameraGeneration+=1;self.starting=false;self.freecamera=false
   releaseBindings()
   if not restoreCamera()then return false,'Camera or controls restoration is still pending'end
   return true
  end
  if not alive()then return false,'Altair is unloaded'end
  if self.freecamera then return true end
  if self.starting then return false,'Free Camera is already starting'end
  if(cameraState or controls)and not restoreCamera()then return false,'Previous camera or controls restoration is still pending'end
  if not alive()then return false,'Altair is unloaded'end
  self.cameraGeneration+=1;local generation=self.cameraGeneration;self.starting=true
  local function current()return alive()and self.cameraGeneration==generation end
  local function fail(problem)
   if self.cameraGeneration==generation then
    self.starting=false;self.freecamera=false;releaseBindings()
    if not restoreCamera()then problem=tostring(problem)..' (camera or controls restoration is still pending)'end
   end
   return false,problem
  end
  if context.CanCamera then
   local checked,allowed=pcall(context.CanCamera)
   if not current()then return fail('Free Camera activation was cancelled')end
   if not checked then return fail('Camera availability check failed')end
   if not allowed then return fail('Close Home or stop spectating first')end
  end
  local available,initialCamera=pcall(camera)
  if not current()then return fail('Free Camera activation was cancelled')end
  if not available or not initialCamera then return fail('Camera is unavailable')end
  -- PlayerModule require may yield. Resolve it before taking camera ownership,
  -- then verify the same live activation still owns the continuation.
  local value
  if context.GetControls then local ok,result=pcall(context.GetControls);if ok then value=result end end
  if not current()then return fail('Free Camera activation was cancelled')end
  if context.CanCamera then
   local checked,allowed=pcall(context.CanCamera)
   if not current()then return fail('Free Camera activation was cancelled')end
   if not checked then return fail('Camera availability check failed')end
   if not allowed then return fail('Close Home or stop spectating first')end
  end
  local found,c=pcall(camera)
  if not current()then return fail('Free Camera activation was cancelled')end
  if not found or not c then return fail('Camera is unavailable')end
  local activated,problem=pcall(function()
   cameraState={camera=c,cframe=c.CFrame,focus=c.Focus,kind=c.CameraType}
   view=c;position=c.CFrame.Position;pitch,yaw=c.CFrame:ToOrientation();velocity=Vector3.zero;c.CameraType=Enum.CameraType.Scriptable
  -- Use the normal control module when available; otherwise the scoped action
  -- sink still prevents keyboard movement. Never replace the module or globals.
  if value and type(value.Disable)=="function"and type(value.Enable)=="function"and value.controlsEnabled~=false then
   controls=value
   local disabled,disableProblem=pcall(value.Disable,value)
   if not disabled or disableProblem==false then error('Controls could not be disabled: '..tostring(disableProblem),0)end
  end
  if not current()then return false end
  self.freecamera=true
  actions:BindActionAtPriority(key,function()
   if not current()or not self.freecamera then return Enum.ContextActionResult.Pass end
   local focused=input:GetFocusedTextBox()
   return(current()and self.freecamera and not focused)and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
  end,false,Enum.ContextActionPriority.High.Value+10,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.KeyCode.Q,Enum.KeyCode.E,Enum.KeyCode.Space)
  local function step(dt)if current()and self.freecamera then self:Step(dt,generation)end end
  if context.BindRender then context.BindRender(key,step)
  else run:BindToRenderStep(key,Enum.RenderPriority.Camera.Value+1,step)end
  return current()
  end)
  if not activated then return fail('Free Camera is unavailable: '..tostring(problem))end
  if not problem then return fail('Free Camera activation was cancelled')end
  self.starting=false
  return true
 end
 function service:Step(dt,generation)
  generation=generation or self.cameraGeneration
  if self.cameraGeneration~=generation then return end
  local live=alive()
  if self.cameraGeneration~=generation then return end
  if not live then self:SetFreeCamera(false);return end
  if not self.freecamera then return end
  local found,current=pcall(camera)
  if self.cameraGeneration~=generation or not self.freecamera then return end
  local checked,allowed=true,true
  if context.CanCamera then checked,allowed=pcall(context.CanCamera)end
  live=alive()
  if self.cameraGeneration~=generation or not self.freecamera then return end
  if not live or not found or current~=view or not checked or not allowed then self:SetFreeCamera(false);return end
  if view.CameraType~=Enum.CameraType.Scriptable then self:SetFreeCamera(false);return end
  dt=math.clamp(tonumber(dt)or 0,0,.05)
  local direction=Vector3.zero
  if not input:GetFocusedTextBox()then
   local function down(code)return input:IsKeyDown(code)and 1 or 0 end
   direction=Vector3.new(down(Enum.KeyCode.D)-down(Enum.KeyCode.A),down(Enum.KeyCode.E)-down(Enum.KeyCode.Q),down(Enum.KeyCode.S)-down(Enum.KeyCode.W))
  end
  local rotation=CFrame.fromOrientation(pitch,yaw,0)
  local speed=(input:IsKeyDown(Enum.KeyCode.LeftShift)or input:IsKeyDown(Enum.KeyCode.RightShift))and 64 or 24
  local wanted=direction.Magnitude>0 and rotation:VectorToWorldSpace(direction.Unit)*speed or Vector3.zero
  live=alive()
  if self.cameraGeneration~=generation or not self.freecamera then return end
  if not live then self:SetFreeCamera(false);return end
  velocity=velocity:Lerp(wanted,1-math.exp(-12*dt));position+=velocity*dt
  view.CFrame=CFrame.new(position)*rotation;view.Focus=view.CFrame*CFrame.new(0,0,-24)
 end
 local bright={Brightness=2,Ambient=Color3.fromRGB(178,178,178),OutdoorAmbient=Color3.fromRGB(178,178,178),GlobalShadows=false,ClockTime=14}
 local function restoreLighting()
  local state=service.lightingState
  for property,original in pairs(state or {})do
   local read,current=pcall(function()return light[property]end)
   if read then
    if current~=bright[property]then state[property]=nil
    else local restored=pcall(function()light[property]=original end);if restored then state[property]=nil end end
   end
  end
  if not state or next(state)==nil then service.lightingState=nil;return true end
  return false
 end
 function service:SetFullbright(enabled)
  if enabled and not alive()then return false,'Altair is unloaded'end
  enabled=enabled==true;if self.fullbright==enabled and(enabled or not self.lightingState)then return true end
  if enabled then
   if self.lightingState and not restoreLighting()then return false,'Previous lighting changes could not be restored on this client'end
   self.lightingState={}
   local applied,problem=pcall(function()
    for property,target in pairs(bright)do local original=light[property]
     if original~=target then self.lightingState[property]=original;light[property]=target end
    end
   end)
   if not applied then self.fullbright=false;restoreLighting();return false,'Fullbright is unavailable: '..tostring(problem)end
  else
   self.fullbright=false
   if not restoreLighting()then return false,'Some lighting settings could not be restored on this client'end
  end
  self.fullbright=enabled;return true
 end
 function service:Register(entry)
  if not alive()then return false,'Altair is unloaded'end
  assert(type(entry)=='table'and type(entry.id)=='string'and type(entry.run)=='function','Invalid native utility')
  if not self.entries[entry.id]then self.order[#self.order+1]=entry.id end;self.entries[entry.id]=entry
 end
 function service:List()
  local list={};for _,id in ipairs(self.order)do local item=self.entries[id];list[#list+1]={id=id,name=item.name,description=item.description,icon=item.icon,toggle=item.active~=nil,active=item.active and item.active()or false}end;return list
 end
 function service:Run(id,...)
  if not alive()then return false,'Altair is unloaded'end
  local entry=self.entries[tostring(id)];if not entry then return false,'Unknown built-in tool'end
  local args=table.pack(...);local ok,value,detail=pcall(function()return entry.run(table.unpack(args,1,args.n))end)
  if not alive()then return false,'Altair is unloaded'end
  if not ok then return false,tostring(value)end
  if value==false then return false,detail end
  return true,value
 end
 service:Register({id='freecamera',name='Free Camera',description='WASD moves, Q/E changes height, hold right mouse to look. Shift moves faster.',icon='video',active=function()return service.freecamera end,run=function()local ok,problem=service:SetFreeCamera(not service.freecamera);if ok then notice('Free Camera',service.freecamera and 'Enabled · WASD / Q / E · right mouse to look · Shift to speed up.'or 'Disabled · camera restored.')end;return ok,problem end})
 service:Register({id='fullbright',name='Fullbright',description='Brighten dark environments. Toggle off to restore the lighting you changed.',icon='sun',active=function()return service.fullbright end,run=function()local ok,problem=service:SetFullbright(not service.fullbright);if ok then notice('Fullbright',service.fullbright and 'Enabled' or 'Disabled · lighting restored.')end;return ok,problem end})
 local function track(signal,callback)service.connections[#service.connections+1]=signal:Connect(callback)end
 track(input.InputBegan,function(event,processed)
  if alive()and service.freecamera and not processed and not input:GetFocusedTextBox()and event.UserInputType==Enum.UserInputType.MouseButton2 then
   if not mouseState or input.MouseBehavior~=Enum.MouseBehavior.LockCurrentPosition then mouseState=input.MouseBehavior end
   input.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
  end
 end)
 track(input.InputChanged,function(event)
  if alive()and service.freecamera and mouseState and event.UserInputType==Enum.UserInputType.MouseMovement then yaw-=event.Delta.X*.003;pitch=math.clamp(pitch-event.Delta.Y*.003,-math.pi*.49,math.pi*.49)end
 end)
 track(input.InputEnded,function(event)if event.UserInputType==Enum.UserInputType.MouseButton2 then releaseMouse()end end)
 track(input.WindowFocusReleased,function()releaseMouse();velocity=Vector3.zero end)
 function service:Destroy()
  if not self.alive then
   if cameraState or controls then pcall(restoreCamera)end
   if self.lightingState then pcall(self.SetFullbright,self,false)end
   return
  end
  self.alive=false
  -- Repeated explicit destruction retries retained restoration failures. Each
  -- subsystem still gets cleanup if another injected callback throws.
  pcall(self.SetFreeCamera,self,false);pcall(self.SetFullbright,self,false)
  for _,connection in ipairs(self.connections)do pcall(connection.Disconnect,connection)end;table.clear(self.connections);table.clear(self.entries);table.clear(self.order)
 end
 if context.Root then track(context.Root.Destroying,function()service:Destroy()end)end
 return service
end

-- Public badges expose service health without an account credential.
-- These checks monitor downloads, not individual players or gameplay.
local sentivelComponents={
 {key="runtime",name="Runtime download",id="27805597-862c-4cd3-8241-3a5a3df8dacb"},
 {key="interface",name="Interface download",id="cf422960-49ee-4274-858b-94255472425a"},
}
local function sentivelSnapshot(saved,wall,interval)
 wall=wall or os.time();interval=math.clamp(tonumber(interval)or 300,300,3600)
 local function finite(value)return type(value)=="number"and value==value and math.abs(value)<math.huge end
 if type(saved)~="table"or saved.version~=2 or saved.clock~="unix"or not finite(saved.savedAt)or saved.savedAt<0 then return nil end
 local clockValid=saved.savedAt<=wall
 local function stamp(value)return clockValid and finite(value)and value>=0 and value<=wall and value or nil end
 local result={version=2,clock="unix",savedAt=wall,checkedAt=stamp(saved.checkedAt),components={}}
 local valid={operational=true,degraded=true,outage=true,maintenance=true,unknown=true}
 local notices={}
 for _,component in ipairs(sentivelComponents)do
  local record=type(saved.components)=="table"and saved.components[component.key]
  if type(record)=="table"then
   local status=valid[record.status]and record.status or nil
   local checkedAt=status and stamp(record.checkedAt)or nil
   local item={status=status,checkedAt=checkedAt,stale=record.stale==true or checkedAt==nil}
   if saved.problemAnnounced==true and(record.noticeStatus=="degraded"or record.noticeStatus=="outage")then
    item.noticeStatus=record.noticeStatus;notices[#notices+1]=component.key..":"..record.noticeStatus
   end
   result.components[component.key]=item
  end
 end
 if saved.problemAnnounced==true then
  result.problemAnnounced=true
  if #notices>0 then result.noticeKey=table.concat(notices,"|")end
 end
 -- No raw runtime clock, worker handle or unbounded future deadline survives.
 -- A clock rollback leaves health unknown and adds at most one poll interval.
 if not clockValid then result.nextCheckAt=wall+interval
 else
  local nextCheck=finite(saved.nextCheckAt)and saved.nextCheckAt>=0 and saved.nextCheckAt or(result.checkedAt and result.checkedAt+interval)
  if nextCheck then result.nextCheckAt=wall+math.clamp(nextCheck-wall,0,interval)end
 end
 return result
end
local function bindSentivel(context)
 local page="https://www.sentivel.com/status/altair-cloudz"
 local components=sentivelComponents
 local statuses={operational="operational",degraded="degraded",["degraded performance"]="degraded",["partial outage"]="outage",["major outage"]="outage",outage="outage",down="outage",maintenance="maintenance",["under maintenance"]="maintenance",["no data"]="unknown",["warming up"]="unknown",unknown="unknown",idle="unknown"}
 local now=context.Now or os.time
 local wallNow=context.WallNow or os.time
 local schedule=context.Schedule or task.delay
 local cancel=context.Cancel or task.cancel
 local interval=math.clamp(tonumber(context.Interval)or 300,300,3600)
 local session=context.Session or{}
 local cache={components={}}
 local wall,timestamp=wallNow(),now()
 local restored=sentivelSnapshot(session.sentivel,wall,interval)
 if restored then
  local function relative(value)return value and timestamp-(wall-value)or nil end
  cache.checkedAt=relative(restored.checkedAt)
  cache.nextCheckAt=relative(restored.nextCheckAt)
  cache.problemAnnounced=restored.problemAnnounced;cache.noticeKey=restored.noticeKey
  for key,record in pairs(restored.components)do
   cache.components[key]={status=record.status,checkedAt=relative(record.checkedAt),stale=record.stale,noticeStatus=record.noticeStatus}
  end
 end
 local service={alive=true,busy=false,PageUrl=page,generation=0}
 local pending
 local function alive()return service.alive and(not context.Alive or context.Alive())end
 function service:ExportCache()
  local timestamp,wall=now(),wallNow()
  local function stamp(value)
   if type(value)=="number"and value==value and math.abs(value)<math.huge and value<=timestamp then return wall-(timestamp-value)end
  end
  local saved={version=2,clock="unix",savedAt=wall,checkedAt=stamp(cache.checkedAt),components={},problemAnnounced=cache.problemAnnounced}
  if type(cache.nextCheckAt)=="number"then saved.nextCheckAt=wall+math.clamp(cache.nextCheckAt-timestamp,0,interval)end
  for _,component in ipairs(components)do
   local record=cache.components[component.key]
   if record then saved.components[component.key]={status=record.status,checkedAt=stamp(record.checkedAt),stale=record.stale,noticeStatus=record.noticeStatus}end
  end
  return sentivelSnapshot(saved,wall,interval)
 end
 local function persist()
  session.sentivel=service:ExportCache()
  if context.SaveCache then pcall(context.SaveCache,session.sentivel)end
 end
 session.sentivel=service:ExportCache()
 local function parse(body)
  if type(body)~="string"or #body>32768 or not body:match("^%s*<svg[%s>]")then return end
  local label=body:match('aria%-label%s*=%s*"([^"]+)"')or body:match("aria%-label%s*=%s*'([^']+)'")or body:match("<title[^>]*>(.-)</title>")
  if not label then return end
  local value=label:match(":%s*([^:]+)$")
  if not value then return end
  value=value:lower():gsub("[_%-]"," "):gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
  return statuses[value]
 end
 local function read(component)
  local url=page.."/badge.svg?component="..component.id
  local ok,response=pcall(function()
   if context.Request then return context.Request({Url=url,Method="GET",Headers={Accept="image/svg+xml"},Timeout=8})end
   return game:HttpGet(url)
  end)
  if not ok then return end
  if type(response)=="table"then
   local status=tonumber(response.StatusCode or response.status_code or response.Status)
   if status~=200 then return end
   response=response.Body or response.body
  end
  return parse(response)
 end
 function service:GetStatus()
  local timestamp=now();local result={provider="Sentivel",url=page,status="operational",checkedAt=cache.checkedAt,nextCheckAt=cache.nextCheckAt,components={}}
  local severity={operational=0,maintenance=1,unknown=2,degraded=3,outage=4};local highest=0
  for _,component in ipairs(components)do
   local record=cache.components[component.key]or{}
   local stale=record.stale==true or not record.checkedAt or timestamp<record.checkedAt or timestamp-record.checkedAt>interval*2
   local status=stale and"unknown"or record.status or"unknown"
   result.components[#result.components+1]={key=component.key,name=component.name,status=status,lastKnownStatus=record.status,checkedAt=record.checkedAt,stale=stale}
   if(severity[status]or 2)>highest then highest=severity[status]or 2;result.status=status end
  end
  return result
 end
 local poll
 local function queue(delay)
  if not alive()then return end
  pending=schedule(math.max(0,delay),function()pending=nil;poll()end)
 end
 poll=function()
  if not alive()or service.busy then return end
  local timestamp=now()
  if cache.nextCheckAt and timestamp<cache.nextCheckAt then queue(cache.nextCheckAt-timestamp);return end
  service.busy=true;service.generation+=1;local generation=service.generation
  cache.nextCheckAt=timestamp+interval
  persist() -- Reserve the portable deadline before the first yielding request.
  local results={};local healthy=true
  for _,component in ipairs(components)do
   if not alive()or generation~=service.generation then return end
   local status=read(component)
   if not alive()or generation~=service.generation then return end
   results[component.key]=status or false
   if status~="operational"then healthy=false end
  end
  local problems,names={},{};local newProblem=false
  for _,component in ipairs(components)do
   local status=results[component.key]
   local record=cache.components[component.key]or{}
   if status then record.status=status;record.checkedAt=timestamp;record.stale=false
   else record.stale=true end
   if status=="degraded"or status=="outage"then
    if record.noticeStatus~=status then newProblem=true;record.noticeStatus=status end
    problems[#problems+1]=component.key..":"..status;names[#names+1]=component.name
   elseif status=="operational"then record.noticeStatus=nil end
   cache.components[component.key]=record
  end
  cache.checkedAt=timestamp
  local problem=#problems>0 and table.concat(problems,"|")or nil
  local title,message
  if problem and newProblem then
   cache.noticeKey=problem;cache.problemAnnounced=true
   title="Altair service issue";message=table.concat(names," and ")..(#names==1 and" is"or" are").." reporting a service issue. Your open controls may continue to work. Check Altair status for updates."
  elseif healthy and cache.problemAnnounced then
   cache.noticeKey=nil;cache.problemAnnounced=nil
   title="Altair services recovered";message="Runtime and interface downloads are operational again."
  end
  persist() -- Persist notice ownership before a rerun can announce it again.
  if not alive()or generation~=service.generation then return end
  if title and context.Notify then pcall(context.Notify,title,message,nil,{Duration=7})end
  service.busy=false
  queue(math.max(0,cache.nextCheckAt-now()))
 end
 function service:Refresh()
  if not alive()or self.busy then return false end
  if pending then pcall(cancel,pending);pending=nil end
  queue(0);return true
 end
 function service:Destroy()
  if not self.alive then return end
  self.alive=false;self.generation+=1;self.busy=false
  if pending then pcall(cancel,pending);pending=nil end
 end
 queue(math.max(0,(cache.nextCheckAt or 0)-now()))
 return service
end


-- Palette-linked exterior rails. Dock owns the complete tile selection pose.
-- Owns new visuals and clipping; never dock or panel geometry.
local function bindNavigationAccents(context)
 local root=context.Root;local bar=root.SmartBar;local buttons=bar.Back.Buttons
 local dock=context.Dock
 assert(type(dock)=="table"and dock.NavigationGeometryOwnership==1 and type(dock.SetNavigationState)=="function","Matching Dock navigation geometry contract 1 is required")
 -- Exterior rails need the button-list padding; the dock still owns every pose.
 local buttonsClips=buttons.ClipsDescendants;buttons.ClipsDescendants=false
 local service={alive=true};local connections,visuals,entries,categories,sectionRules={},{},{},{},{}
 local motion=motionService(nil,true);local running={};local pending=false
 local names={"Home","Character","Scripts","Playerlist","Settings"}
 local function connect(signal,callback)
  local connection=signal:Connect(callback);connections[#connections+1]=connection;return connection
 end
 local function animate(object,duration,goal,easing)
  local animation=motion:Create(object,TweenInfo.new(duration,easing or Enum.EasingStyle.Quart,Enum.EasingDirection.Out),goal)
  running[animation]=true;animation.Completed:Once(function()running[animation]=nil end);animation:Play();return animation
 end
 local function rule(parent,name,position,size,vertical)
  local line=Instance.new("Frame");line.Name=name;line.AnchorPoint=Vector2.new(.5,.5)
  line.Position=position;line.Size=size;line.BorderSizePixel=0;line.BackgroundColor3=Color3.new(1,1,1);line.BackgroundTransparency=1
  line.Active=false;line.Interactable=false;line.ZIndex=parent.ZIndex+2;line:SetAttribute("AltairThemeIgnore",true)
  local rounding=Instance.new("UICorner");rounding.CornerRadius=UDim.new(1,0);rounding.Parent=line
  local gradient=Instance.new("UIGradient");gradient.Name="Palette";gradient.Rotation=vertical and 90 or 0
  gradient.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.18,.08),NumberSequenceKeypoint.new(.82,.08),NumberSequenceKeypoint.new(1,1)});gradient.Parent=line
  line.Parent=parent;visuals[#visuals+1]=line
  return {line=line,gradient=gradient}
 end
 local function bindPalette(record,source,category)
  if record.source==source then return end
  for _,connection in ipairs(record.paletteConnections or{})do connection:Disconnect()end
  record.source=source;record.paletteConnections={}
  if not source then return end
  local stroke=category and source:FindFirstChildOfClass("UIStroke")
  local ramp=stroke and stroke:FindFirstChildOfClass("UIGradient")or source:FindFirstChildOfClass("UIGradient")
  local multiplier=stroke and stroke.Color or source.BackgroundColor3
  local function paint()
   if not service.alive or not source.Parent then return end
   multiplier=stroke and stroke.Color or source.BackgroundColor3
   local points={};local sequence=ramp and ramp.Color or ColorSequence.new(multiplier)
   for _,point in ipairs(sequence.Keypoints)do
    local color=ramp and Color3.new(point.Value.R*multiplier.R,point.Value.G*multiplier.G,point.Value.B*multiplier.B)or point.Value
    local hue,saturation,value=color:ToHSV()
    -- Read the existing palette, lifting only its luminance for a one-pixel rule.
    color=Color3.fromHSV(hue,saturation,math.max(value,.62))
    points[#points+1]=ColorSequenceKeypoint.new(point.Time,color)
   end
   local result=ColorSequence.new(points)
   for _,visual in ipairs(record.rules)do if visual.line.Parent then visual.gradient.Color=result end end
  end
  record.paletteConnections[#record.paletteConnections+1]=source:GetPropertyChangedSignal("BackgroundColor3"):Connect(paint)
  if stroke then record.paletteConnections[#record.paletteConnections+1]=stroke:GetPropertyChangedSignal("Color"):Connect(paint)end
  if ramp then record.paletteConnections[#record.paletteConnections+1]=ramp:GetPropertyChangedSignal("Color"):Connect(paint)end
  paint()
 end
 local function panelLive(panel)
  return panel and panel.Parent and panel.Visible and not panel:GetAttribute("AltairClosing")and not panel:GetAttribute("AltairDeckSource")
 end
 local function selectedName()
  if not root.Enabled or not bar.Visible or bar:GetAttribute("AltairClosing")then return nil end
  if context.IsBarOpen and not context.IsBarOpen()then return nil end
  if context.IsHomeOpen and context.IsHomeOpen()then return "Home"end
  if root.ScriptSearch.Visible then return "Scripts"end
  for _,name in ipairs({"Character","Scripts","Playerlist","Settings"})do if panelLive(root:FindFirstChild(name))then return name end end
 end
 local function selectButton(entry,selected,shown)
  local state=not shown and"hidden"or selected and"selected"or entry.hovered and"hovered"or"idle"
  if entry.state==state then return end
  entry.state=state;local reduced=root:GetAttribute("AltairReduceMotion")==true
  local width=selected and .74 or entry.hovered and .62 or .50
  local alpha=not shown and 1 or selected and .08 or entry.hovered and .32 or .60
  for _,visual in ipairs(entry.rules)do
   local goal={BackgroundTransparency=alpha}
   if reduced then visual.line.Size=UDim2.new(width,0,0,1.2)else goal.Size=UDim2.new(width,0,0,1.2)end
   animate(visual.line,reduced and .12 or selected and .28 or .22,goal,selected and Enum.EasingStyle.Back or Enum.EasingStyle.Quart)
  end
 end
 local function watchPanel(panel,queue)
  if not panel then return end
  connect(panel:GetPropertyChangedSignal("Visible"),queue)
  for _,attribute in ipairs({"AltairClosing","AltairDeckSource"})do connect(panel:GetAttributeChangedSignal(attribute),queue)end
 end
 local function refresh()
  if not service.alive then return end
  local selected=selectedName();local shown=root.Enabled and bar.Visible and not bar:GetAttribute("AltairClosing")and(not context.IsBarOpen or context.IsBarOpen())
  dock:SetNavigationState(selected,shown)
  for name,entry in pairs(entries)do selectButton(entry,name==selected,shown)end
  for _,record in ipairs(sectionRules)do
   local live=panelLive(record.panel);local state=live and"shown"or"hidden"
   if record.state~=state then
    record.state=state
    animate(record.reveal,.20,{Value=live and 1 or 0})
   end
  end
  local settings=root.Settings;local heading=settings:FindFirstChild("ContentTitle")
  local categoryName=heading and heading.Text;local settingsLive=panelLive(settings)
  for name,record in pairs(categories)do
   local active=settingsLive and name==categoryName;local alpha=not settingsLive and 1 or active and .12 or .77
   if record.alpha~=alpha then
    record.alpha=alpha;animate(record.reveal,.22,{Value=1-alpha})
    animate(record.rules[1].line,.22,{Size=UDim2.new(0,1.2,active and .68 or .38,0)})
   end
  end
 end
 local function queue()
  if pending or not service.alive then return end;pending=true
  task.defer(function()pending=false;if service.alive then refresh()end end)
 end
 for _,name in ipairs(names)do
  local button=buttons:FindFirstChild(name);local icon=button and button:FindFirstChild("Icon")
  if button and icon then
   -- Entire strokes sit beyond the tile edges, never at their inset ends.
   -- Keep them children so the list layout cannot turn them into extra cells.
   local clips=button.ClipsDescendants;button.ClipsDescendants=false
   local top=rule(button,"PanelAccentTop",UDim2.new(.5,0,0,-3.5),UDim2.new(.50,0,0,1.2))
   local bottom=rule(button,"PanelAccentBottom",UDim2.new(.5,0,1,3.5),UDim2.new(.50,0,0,1.2))
   local entry={button=button,clips=clips,rules={top,bottom}}
   entries[name]=entry;bindPalette(entry,button)
   connect(button.MouseEnter,function()entry.hovered=true;queue()end)
   connect(button.MouseLeave,function()entry.hovered=false;queue()end)
  end
  watchPanel(root:FindFirstChild(name),queue)
 end
 watchPanel(root.ScriptSearch,queue)
 connect(root:GetPropertyChangedSignal("Enabled"),queue)
 connect(bar:GetPropertyChangedSignal("Visible"),queue)
 connect(bar:GetAttributeChangedSignal("AltairClosing"),function()for _,entry in pairs(entries)do entry.hovered=false end;queue()end)
 connect(root:GetAttributeChangedSignal("AltairReduceMotion"),function()for _,entry in pairs(entries)do entry.state=nil end;queue()end)
 local function section(panel,heading,source)
  if not heading then return end
  local visual=rule(heading,"SectionAccent",UDim2.new(0,-6,.5,0),UDim2.new(0,1.2,.72,0),true)
  local reveal=Instance.new("NumberValue");reveal.Name="Reveal";reveal.Parent=visual.line
  local record={panel=panel,rules={visual},reveal=reveal};sectionRules[#sectionRules+1]=record;bindPalette(record,source)
  local function paint()if service.alive and visual.line.Parent then visual.line.BackgroundTransparency=1-.57*math.clamp(reveal.Value,0,1)*(1-heading.TextTransparency)end end
  connect(reveal.Changed,paint);connect(heading:GetPropertyChangedSignal("TextTransparency"),paint);paint()
 end
 section(root.Character,root.Character.Interactions:FindFirstChild("PropertiesTitle"),buttons.Character)
 section(root.Character,root.Character.Interactions:FindFirstChild("ActionsTitle"),buttons.Scripts)
 section(root.Playerlist,root.Playerlist:FindFirstChild("Title"),buttons.Playerlist)
 local types=root.Settings.SettingTypes
 local function category(object)
  if not object:IsA("GuiObject")or object.Name=="Template"or categories[object.Name]then return end
  local visual=rule(object,"CategoryAccent",UDim2.new(0,3,.5,0),UDim2.new(0,1.2,.38,0),true)
  local reveal=Instance.new("NumberValue");reveal.Name="Reveal";reveal.Parent=visual.line
  local title=object:FindFirstChild("Title")
  local record={rules={visual},reveal=reveal};categories[object.Name]=record;bindPalette(record,object,true)
  local function paint()if service.alive and visual.line.Parent then visual.line.BackgroundTransparency=1-math.clamp(reveal.Value,0,1)*(title and 1-title.TextTransparency or 1)end end
  connect(reveal.Changed,paint);if title then connect(title:GetPropertyChangedSignal("TextTransparency"),paint)end;paint();queue()
 end
 for _,object in ipairs(types:GetChildren())do category(object)end
 connect(types.ChildAdded,function(object)task.defer(function()if service.alive and object.Parent==types then category(object)end end)end)
 local heading=root.Settings:FindFirstChild("ContentTitle")
 if heading then connect(heading:GetPropertyChangedSignal("Text"),queue)end
 function service:Destroy()
  if not self.alive then return end;self.alive=false
  for _,connection in ipairs(connections)do connection:Disconnect()end
  for animation in pairs(running)do animation:Cancel()end
  for _,records in ipairs({entries,categories,sectionRules})do for _,record in pairs(records)do
   for _,connection in ipairs(record.paletteConnections or{})do connection:Disconnect()end
   if record.button and record.button.Parent then
    if record.button.ClipsDescendants==false then record.button.ClipsDescendants=record.clips end
   end
  end end
  if buttons.Parent and buttons.ClipsDescendants==false then buttons.ClipsDescendants=buttonsClips end
  for _,object in ipairs(visuals)do object:Destroy()end
 end
 connect(root.Destroying,function()service:Destroy()end)
 refresh();return service
end

-- A bounded, event-driven material registry; no render loop or per-object
-- property listeners are needed for opaque surfaces or late-created cards.
local function bindSurfaceOpacity(root,motion)
 local controller={alive=true,solid=nil,alpha=nil,ready=false,count=0}
 local records=setmetatable({},{__mode="k"})
 local queued=setmetatable({},{__mode="k"});local queue={};local head,tail=1,0;local worker
 local function closing(object)
  local parent=object
  while parent and parent~=root do
   if parent:GetAttribute("AltairClosing")or parent:GetAttribute("AltairDialogClosing")or parent:GetAttribute("AltairSharedSwitch")then return true end
   parent=parent.Parent
  end
  return false
 end
 local function paint(object,record)
  object:SetAttribute("AltairSolidMaterial",controller.solid and true or nil)
  object:SetAttribute("AltairSolidRestAlpha",record.alpha)
  local target=Design.opacityTargets[object]
  -- Alpha=1 can mean either a fade owned by a panel, or the user's 0% finish.
  -- Only the latter may be restored here; never resurrect a closing surface.
  if closing(object)or(object.BackgroundTransparency>=.99 and object.BackgroundTransparency~=record.last and not(target and target<.99))then return end
  Design.freezeMaterial(object)
  if motion and motion.Freeze then motion:Freeze(object,"BackgroundTransparency")end
  local alpha=Design.opacityAlpha(record.alpha,controller.alpha)
  if object:GetAttribute("AltairDesignFixedTransparency")~=nil or object:GetAttribute("AltairDesignTransparencyOffset")~=nil then alpha=Design.surfaceAlpha(object,controller.alpha)end
  record.last=alpha;object.BackgroundTransparency=alpha
 end
 function controller:Resolve(object)
  if not self.alive or not object.Parent or not object:IsDescendantOf(root)or not Design.isMaterial(object)then return nil end
  -- Resolve from authored registry metadata, never a hidden/current rendered alpha.
  local transparency=root:GetAttribute("AltairPanelTransparency")
  if type(transparency)~="number"then transparency=self.alpha end
  if object:GetAttribute("AltairDesignFixedTransparency")~=nil or object:GetAttribute("AltairDesignTransparencyOffset")~=nil then
   return Design.surfaceAlpha(object,transparency)
  end
  local record=records[object]
  local authored=record and record.alpha or object:GetAttribute("AltairMaterialRestAlpha")or object:GetAttribute("AltairSolidRestAlpha")or object:GetAttribute("AltairDesignRestAlpha")
  if type(authored)~="number"then return nil end
  return Design.opacityAlpha(authored,transparency)
 end
 local function register(object)
  if not object.Parent or not object:IsDescendantOf(root)or not Design.isMaterial(object)then return end
  local record=records[object]
  if not record then
   local authored=object:GetAttribute("AltairMaterialRestAlpha")or object:GetAttribute("AltairSolidRestAlpha")or object:GetAttribute("AltairDesignRestAlpha")
   if type(authored)~="number"then
    authored=object:GetAttribute("AltairDesignFixedTransparency")
    if type(authored)~="number"and object:GetAttribute("AltairDesignTransparencyOffset")~=nil then authored=.1+object:GetAttribute("AltairDesignTransparencyOffset")end
   end
   record={alpha=type(authored)=="number"and authored or object.BackgroundTransparency}
   object:SetAttribute("AltairMaterialRestAlpha",record.alpha)
   records[object]=record;controller.count+=1
  end
  -- Merely discovering a surface must not reset an active fade or hover.
  if controller.alpha~=.1 or object:GetAttribute("AltairSolidMaterial")then paint(object,record)end
 end
 local function startWorker()
  if worker or not controller.alive then return end
  worker=task.defer(function()
   while controller.alive and head<=tail do
    local deadline=os.clock()+.002
    repeat
     local object=queue[head];queue[head]=nil;head+=1
     if object then queued[object]=nil;register(object)end
    until head>tail or os.clock()>=deadline
    if head<=tail then task.wait()end
   end
   table.clear(queue);head,tail=1,0;worker=nil;controller.ready=controller.alive
  end)
 end
 local function enqueue(object)
  if not controller.alive or queued[object]then return end
  queued[object]=true;tail+=1;queue[tail]=object;controller.ready=false;startWorker()
 end
 function controller:Set(transparency)
  if type(transparency)=="boolean"then transparency=transparency and 0 or .1 end
  transparency=math.clamp(tonumber(transparency)or .1,0,1)
  if not self.alive or self.alpha==transparency then return false end
  self.alpha=transparency;self.solid=transparency<=0
  root:SetAttribute("AltairSolidSurfaces",self.solid)
  for object,record in pairs(records)do if object.Parent then paint(object,record)end end
  return true
 end
 function controller:Destroy()
  if not self.alive then return end
  self.alive=false
  if worker then pcall(task.cancel,worker);worker=nil end
  for _,connection in ipairs(self.connections)do connection:Disconnect()end
  root:SetAttribute("AltairSolidSurfaces",false)
  for object,record in pairs(records)do if object.Parent then
   object:SetAttribute("AltairSolidMaterial",nil)
   object:SetAttribute("AltairSolidRestAlpha",nil)
   object:SetAttribute("AltairMaterialRestAlpha",nil)
   if object.BackgroundTransparency==record.last and not closing(object)then object.BackgroundTransparency=record.alpha end
  end end
  table.clear(records);table.clear(queue);table.clear(queued)
 end
 controller.connections={root.DescendantAdded:Connect(enqueue),root:GetAttributeChangedSignal("AltairPanelTransparency"):Connect(function()controller:Set(root:GetAttribute("AltairPanelTransparency"))end)}
 controller:Set(root:GetAttribute("AltairPanelTransparency")or .1)
 for _,object in ipairs(root:GetDescendants())do enqueue(object)end
 controller.connections[#controller.connections+1]=root.Destroying:Connect(function()controller:Destroy()end)
 return controller
end

local bindings={NavigationAccents=bindNavigationAccents,MaterialAlpha=Design.materialAlpha,OpacityAlpha=Design.opacityAlpha,SurfaceOpacity=bindSurfaceOpacity,DialogAccent=dialogAccent,DialogFeedback=dialogFeedback,Sentivel=bindSentivel,SentivelSnapshot=sentivelSnapshot,NativeUtilities=buildNativeUtilities,Ruler=buildRuler,CharacterRuler=buildCharacterRuler,Discovery=buildDiscovery,ExperimentalSection=buildExperimentalSection,SnapGuides=buildSnapGuides,Loading=buildLoading,Choice=buildChoice,UIAvoidance=bindUIAvoidance,SlideContent=slideContent,StopSlide=stopContentSlide,SlideHeading=slideHeading,BounceReset=bounceReset,HomeIsolation=bindHomeIsolation,RayfieldBridge=bindRayfieldBridge,DragContrast=bindDragContrast,Dock=bindDock,Capsules=bindCapsules,Clock=Clock,Notifications=buildNotifications,ApplyIcon=applyIcon,RefreshIcon=refreshIcon,Motion=motionService,Resize=resizeInterface,DisplayScale=displayScale,Slider=buildSlider,Stats=buildStats,SoftShadows=bindSoftShadows,Surface=styleSurface,HomeSurface=styleHome,ColorPicker=buildColorPicker,Theme=bindTheme,HomeContainer=function(root)local content=Instance.new("Frame");content.Name="Content";content.BackgroundTransparency=1;content.Parent=root.Home;return content end}
-- Shared chrome is authored once, before theme capture and runtime cloning.
-- Feature controllers retain their geometry, data and animation ownership.
local function styleWorkbenchPanels(root)
 local function material(object,alpha)
  object.BackgroundColor3=Design.Raised;object.BackgroundTransparency=alpha or .18;object.BorderSizePixel=0
  object:SetAttribute("AltairDesignRestAlpha",object.BackgroundTransparency)
  object:SetAttribute("AltairDesignRole","inset");Design.corner(object,12);Design.edge(object,.9)
  local gradient=object:FindFirstChildOfClass("UIGradient")
  if gradient then gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(224,224,224));gradient.Rotation=105 end
 end
 local function typeStyle(object)
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then
   if not object:GetAttribute("AltairIcon")then Design.text(object,object.Name=="Title"or object.Name=="DisplayName") end
  end
 end
 for _,object in ipairs(root:GetDescendants())do if not object:IsDescendantOf(root.Scripts)and not object:IsDescendantOf(root.Toasts)then typeStyle(object)end end
 local function header(panel,subtitle)
  panel:SetAttribute("AltairDesignManaged",true)
  panel.Title.FontFace=Design.Heading;panel.Title.TextColor3=Design.Ink;panel.Title.TextSize=18
  panel.Icon.ImageColor3=Design.Ink
  if panel:FindFirstChild("Subtitle")then panel.Subtitle.Text=subtitle;panel.Subtitle.TextColor3=Design.Muted;panel.Subtitle.FontFace=Design.Font end
  local line=Design.divider(panel,"AltairHeaderDivider",UDim2.fromOffset(16,49),UDim2.new(1,-32,0,1));line.BackgroundTransparency=.9
 end
 header(root.Character,"Movement, camera and session controls")
 header(root.Playerlist,"People and actions in this server")
 local function action(object)
  if not object:IsA("GuiObject")then return end
  material(object,.2);Design.corner(object,9)
  local title=object:FindFirstChild("Title");if title then title.TextColor3=Design.Ink;title.TextSize=12;title.FontFace=Design.Font end
  local icon=object:FindFirstChild("Icon");if icon and(icon:IsA("ImageLabel")or icon:IsA("ImageButton"))then icon.ImageColor3=Design.Muted end
 end
 local character=root.Character.Interactions
 for _,object in ipairs(character.Grid:GetChildren())do if object:IsA("GuiObject")then action(object)end end
 action(character.Rejoin);action(character.Serverhop)
 local toggle=character.Toggles.Template;material(toggle,.15)
 for _,name in ipairs({"ActionsDivider","PropertiesDivider","HeaderDivider"})do
  local line=character:FindFirstChild(name);if line then line.BackgroundColor3=Design.Edge;line.BackgroundTransparency=.9;line:SetAttribute("AltairDesignRole","divider")end
 end
 local list=root.Playerlist.Interactions
 material(list.SearchFrame,.2);Design.corner(list.SearchFrame,9)
 list.SearchFrame.SearchBox.TextColor3=Design.Ink;list.SearchFrame.SearchBox.PlaceholderColor3=Design.Muted
 list.SearchFrame.SearchBox.Size=UDim2.new(1,-46,1,0)
 for _,object in ipairs({list.List.Template,list.SelectedPlayer})do
  material(object,.18);object:SetAttribute("AltairPlayerMaterial",true)
  local avatar=object:FindFirstChild("Avatar");if avatar then Design.corner(avatar,8)end
 end
 for _,object in ipairs(list.SelectedActions:GetChildren())do if object:IsA("GuiObject")and object.Name~="Title"then action(object)end end
 for _,object in ipairs(root.Playerlist:GetDescendants())do
  if object:IsA("TextLabel")or object:IsA("TextButton")then object.TextColor3=(object.Name=="Role"or object.Name=="Username"or object.Name=="NoActions")and Design.Muted or Design.Ink end
  if object:IsA("Frame")and(object.Name:find("Divider")or object.Name=="Stroke"or object.Name=="Stroke2")then object.BackgroundColor3=Design.Edge;object.BackgroundTransparency=.91;object:SetAttribute("AltairDesignRole","divider")end
 end
 Design.divider(list.SelectedPlayer,"ProfileDivider",UDim2.fromOffset(14,147),UDim2.new(1,-28,0,1))
 local bar=root.SmartBar
 bar:SetAttribute("AltairDesignTransparencyOffset",0);bar.BackgroundColor3=Design.Surface
 bar.Back.BackgroundColor3=Color3.fromRGB(48,48,50);bar.Back.BackgroundTransparency=.45;Design.edge(bar.Back,.96);bar.Back.UIStroke.Thickness=.45;Design.corner(bar.Back,UDim.new(.5,0))
 bar.Back.Time.TextColor3=Design.Ink;bar.Back.Time.AMPM.TextColor3=Design.Muted
 bar.Back.Time.FontFace=Design.Font;bar.Back.Time.AMPM.FontFace=Design.Heading
 -- Clock separator belongs to the clock, so dock mirroring cannot leave it behind.
 local rule=Design.divider(bar.Back.Time,"ClockDivider",UDim2.new(1,2,0,1),UDim2.fromOffset(1,26));rule.BackgroundTransparency=.9
 for _,object in ipairs(bar.Back.Buttons:GetChildren())do if object:IsA("Frame")and object.Name~="Placeholder"then
  Design.corner(object,10);Design.edge(object,.94);object.Icon.Size=UDim2.fromOffset(22,22)
 end end
 local legacy=root:FindFirstChild("Notifications")
 if legacy then
  local template=legacy:FindFirstChild("Template");if template then material(template,.12);for _,o in ipairs(template:GetDescendants())do typeStyle(o)end end
 end
 local starlight=root:FindFirstChild("Starlight")
 if starlight then
  styleSurface(starlight);starlight:SetAttribute("AltairDesignManaged",true)
  starlight.CommandBox.Position=UDim2.fromOffset(42,0);starlight.CommandBox.AnchorPoint=Vector2.zero;starlight.CommandBox.Size=UDim2.new(1,-140,1,0);starlight.CommandBox.TextSize=14;starlight.CommandBox.TextColor3=Design.Ink
  starlight.AutoComplete.Position=starlight.CommandBox.Position;starlight.AutoComplete.Size=starlight.CommandBox.Size;starlight.AutoComplete.AnchorPoint=Vector2.zero;starlight.AutoComplete.TextColor3=Design.Muted
  local icon=Instance.new("ImageLabel");icon.Name="CommandIcon";icon.BackgroundTransparency=1;icon.Size=UDim2.fromOffset(18,18);icon.Position=UDim2.new(0,14,.5,-9);icon.ImageColor3=Design.Muted;icon.Parent=starlight;applyIcon(icon,"square-terminal")
  for _,object in ipairs(starlight.RayfieldView:GetDescendants())do if object:IsA("Frame")and object.BackgroundTransparency<.99 then material(object,.18)end end
 end
 local status=root:FindFirstChild("Status");if status then
  status.Title.FontFace=Design.Font;status.Title.TextColor3=Design.Ink
  status.Line.BackgroundColor3=Design.Edge;status.Line.Size=UDim2.new(1,0,0,1);status.Line.BackgroundTransparency=.9;status.Line:SetAttribute("AltairDesignRole","divider")
 end
end
bindings.DaylightDial=buildDaylightDial
bindings.SettingsSearch=buildSettingsSearch
bindings.SettingsLayout=bindSettingsLayout
-- Contract 1: the factory honors IsCurrent/OnRoot and Loading honors onScreen.
bindings.StartupOwnership=1
-- Contract 1: native utility actions and yielding camera startup honor IsAlive.
bindings.NativeUtilitiesOwnership=1
-- Contract 1: raw theme targets and final idle-dim Color3 outputs stay separate.
bindings.IdleColorOwnership=1
bindings.NavigationGeometryOwnership=1
bindings.IdleColor=Design.idleColor
bindings.IdleBase=Design.idleBase
bindings.BindIdleColors=Design.bindIdleColors
return function(options)
	if options and options.BindingsOnly then return bindings end
	local objects = table.create(#nodes)
 local buildAt=os.clock()
 local function current()if options and options.IsCurrent then assert(options.IsCurrent(),"Altair UI startup superseded")end end
 local function budget()current();if os.clock()-buildAt>.002 then game:GetService("RunService").Heartbeat:Wait();current();buildAt=os.clock()end end
	local ok, result = pcall(function()
		for index, node in ipairs(nodes) do
   budget()
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
			if index==1 and options and options.OnRoot then options.OnRoot(object)end
		end
		-- CanvasGroup composition uses sibling stacking, including standalone builds.
		objects[1].ZIndexBehavior=Enum.ZIndexBehavior.Sibling
		-- Link children only after configuration; never mount into the live DataModel here.
		for index = 2, #nodes do
   budget()
			objects[index].Parent = objects[nodes[index][1]]
		end
		for _,object in ipairs(objects) do refreshIcon(object) end
        -- Character: a quick-control strip above two balanced work areas.
        do
         local panel=objects[1].Character;local body=panel.Interactions
         panel.Size=UDim2.fromOffset(582,354);panel.Subtitle.Text="Movement, camera and session controls"
         body.Size=UDim2.new(1,0,1,-50)
         body.Toggles.Position=UDim2.fromOffset(16,8);body.Toggles.Size=UDim2.new(1,-32,0,64)
         local list=body.Toggles:FindFirstChildOfClass("UIListLayout");list.FillDirection=Enum.FillDirection.Horizontal;list.Padding=UDim.new(0,8)
         local toggle=body.Toggles.Template;toggle.Size=UDim2.fromOffset(131,64)
         toggle.Icon.Position=UDim2.fromOffset(12,19);toggle.Icon.Size=UDim2.fromOffset(24,24)
         toggle.Title.Position=UDim2.fromOffset(45,14);toggle.Title.Size=UDim2.fromOffset(80,17)
         toggle.Subtitle.Position=UDim2.fromOffset(45,35);toggle.Subtitle.Size=UDim2.fromOffset(80,14)
         body.PropertiesTitle.Text="Movement & camera";body.PropertiesTitle.Position=UDim2.fromOffset(20,88);body.PropertiesTitle.Size=UDim2.fromOffset(240,18)
         body.ActionsTitle.Text="Player & session";body.ActionsTitle.Position=UDim2.fromOffset(316,88);body.ActionsTitle.Size=UDim2.fromOffset(240,18)
         body.Reset.Position=UDim2.fromOffset(274,89)
         body.Sliders.Position=UDim2.fromOffset(20,116);body.Sliders.Size=UDim2.fromOffset(264,174)
         local row=body.Sliders.Template;row.Size=UDim2.fromOffset(264,36)
         row.Track.Size=UDim2.fromOffset(210,7);row.Value.Position=UDim2.fromOffset(220,2)
         row.Information.Size=UDim2.fromOffset(210,16)
         body.Rejoin.Position=UDim2.fromOffset(316,116);body.Serverhop.Position=UDim2.fromOffset(441,116)
         for _,button in ipairs({body.Rejoin,body.Serverhop})do button.Size=UDim2.fromOffset(121,35);button.Interact.Size=UDim2.fromScale(1,1);button.Title.Size=UDim2.new(1,-34,1,0)end
         body.Grid.Position=UDim2.fromOffset(316,159);body.Grid.Size=UDim2.fromOffset(246,132)
         local grid=body.Grid:FindFirstChildOfClass("UIGridLayout");if grid then grid.CellSize=UDim2.fromOffset(121,36);grid.CellPadding=UDim2.fromOffset(4,8)end
         body.Grid.Template.Size=UDim2.fromOffset(121,36);body.Grid.Template.Interact.Size=UDim2.fromScale(1,1);body.Grid.Template.Title.Size=UDim2.new(1,-34,1,0)
         body.ActionsDivider.Position=UDim2.fromOffset(300,88);body.ActionsDivider.Size=UDim2.fromOffset(1,202)
         body.PropertiesDivider.Visible=false;body.HeaderDivider.Visible=false
        end
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
  for name,id in pairs({Home="house",Character="person-standing",Scripts="square-terminal",Playerlist="users-round",Settings="settings"})do applyIcon(objects[1].SmartBar.Back.Buttons[name].Icon,id)end
  local bar=objects[1].SmartBar;bar.UICorner.CornerRadius=UDim.new(1,0);bar.Back:SetAttribute("AltairInsetMaterial",nil);bar.Back.BackgroundColor3=Color3.fromRGB(48,48,50);bar.Back:SetAttribute("AltairInsetSurface",true);bar.Back.BackgroundTransparency=.45;bar.Back.UIStroke:SetAttribute("AltairInsetOutline",nil);bar.Back.UIStroke.Transparency=.96;bar.Back.UIStroke.Thickness=.45;bar.Back.UICorner.CornerRadius=UDim.new(.5,0);bar.UIStroke.Thickness=.65
  bar.Back.AnchorPoint=Vector2.new(1,.5);bar.Back.Position=UDim2.new(1,-8,.5,0);bar.Back.Size=UDim2.new(1,-76,1,-12)
  bar.Back.Buttons.AnchorPoint=Vector2.zero;bar.Back.Buttons.Position=UDim2.fromOffset(8,7);bar.Back.Buttons.Size=UDim2.new(1,-16,1,-14)
  local clock=bar.Back.Time;clock.AnchorPoint=Vector2.new(0,.5);clock.Position=UDim2.new(0,-58,.5,-3);clock.Size=UDim2.fromOffset(48,20);clock.TextSize=14;clock.TextXAlignment=Enum.TextXAlignment.Center
  clock.AMPM.AnchorPoint=Vector2.new(.5,0);clock.AMPM.Position=UDim2.new(.5,0,1,-2);clock.AMPM.Size=UDim2.new(1,0,0,10);clock.AMPM.TextSize=8;clock.AMPM.TextXAlignment=Enum.TextXAlignment.Center
  for _,button in ipairs(bar.Back.Buttons:GetChildren())do if button:IsA("GuiObject")then local corner=button:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=UDim.new(0,7)end;local stroke=button:FindFirstChildOfClass("UIStroke");if stroke then stroke.Thickness=.6;stroke.Transparency=.82 end end end
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
        styleDialogs(objects[1])
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

        styleWorkbenchPanels(objects[1])
        buildDiscovery({Root=objects[1],BuildOnly=true})
 objects[1]:SetAttribute("AltairUIRevision",52)
		bindCapsules({Root=objects[1],BuildOnly=true})
		current()
		return objects[1]
	end)
	if not ok then
		for _, object in ipairs(objects) do object:Destroy() end
		error("Altair UI | Construction failed: " .. tostring(result), 2)
	end
	return result, bindings
end
