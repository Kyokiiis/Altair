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

-- NOTIFICATIONS BEGIN
local buildNotifications=(function()
-- Reference: 300px black capsules; 20px corners, 8px stack spacing, content-sized height.
return function(context)
	local root, tweenService = context.Root, game:GetService("TweenService")
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
		local old = tweens[object]; if old then old:Cancel() end
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
		local titleHeight = math.max(17, textService:GetTextSize(title, 14, Enum.Font.GothamMedium, Vector2.new(available, 1000)).Y)
		local descriptionHeight = description ~= "" and math.max(16,
			textService:GetTextSize(description, 13, Enum.Font.Gotham, Vector2.new(available, 1000)).Y) or 0
		if measured and measured.width==width then titleHeight,descriptionHeight=measured.title,measured.body end
		titleHeight=math.min(titleHeight,34);descriptionHeight=math.min(descriptionHeight,112)
		return descriptionHeight==0 and math.max(44,27+titleHeight) or 28+titleHeight+descriptionHeight+3, left, titleHeight, descriptionHeight
	end
	function controller:Layout(instant)
		if not self.alive then return end
		local viewport = root.AbsoluteSize
		local width = math.min(300, math.max(160, viewport.X - 40))
		local bottom = viewport.Y - 24
		for index = #self.active, 1, -1 do
			local record = self.active[index]
			local height, left, titleHeight, descriptionHeight = dimensions(record.title, record.description, record.icon, width,record.measured)
			record.height = height
			record.group.Size = UDim2.fromOffset(width, height)
			record.titleLabel.Position, record.titleLabel.Size = UDim2.fromOffset(left, 14), UDim2.new(1, -left-20, 0, titleHeight)
			record.body.Position, record.body.Size = UDim2.fromOffset(left, 17+titleHeight), UDim2.new(1, -left-20, 0, descriptionHeight)
			record.body.Visible = descriptionHeight > 0
			local goal = UDim2.fromOffset(math.max(20, viewport.X - width - 24), bottom - height)
			if instant then record.group.Position = goal else tween(record.group, 0.42, {Position = goal}) end
			bottom -= height + 8
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
		tween(record.group, 0.28, {Position = record.group.Position + UDim2.fromOffset(60, 0), GroupTransparency = 1})
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
		group.Visible=true
		group.Name="Notification_"..item.id
		if not template then group.BackgroundColor3,group.BorderSizePixel=Color3.fromRGB(17,17,17),0 end
		group.Size, group.GroupTransparency, group.ZIndex = UDim2.fromOffset(300, 64), 1, 350
		if not template then
			local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,20);corner.Parent=group
			local gradient=Instance.new("UIGradient");gradient.Rotation=90
			gradient.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(115,115,115));gradient.Parent=group
		end
		item.group,item.generation,item.connections=group,0,{}
		item.titleLabel=group:FindFirstChild("Title") or label(group,"Title",item.title,14,Color3.fromRGB(250,250,250))
		item.titleLabel.Text=item.title;item.titleLabel.FontFace=titleFont
		item.body=group:FindFirstChild("Description") or label(group,"Description",item.description,13,Color3.fromRGB(174,174,178))
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
		self.nextId += 1
		local item = {id=self.nextId,title=title,description=description,icon=icon,
			duration=math.clamp(tonumber(options.Duration) or (2.5+#description*0.045),2.5,12)}
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

-- Official Lucide artwork. PNGs are rasterized from the unchanged SVG paths in UI/Development/Lucide.
-- Embedded bytes keep first-run icons independent of HTTP and public Roblox assets.
local lucidePNGs={
	["chevron-down"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAA+0lEQVR42u3Y2w3DIBAFUZdCCe7clJQOoIObn0SKFcCvJV6UOQXgO7LlD6YJAAAAAAAAAACgSkGLkpIWhQHPV1DSW9Jsfv68Ot8+QVGfjBNW8yUp2gesH2Ca8DVfSvYBWeqTUJgvPXp/QmYJxfldPqFQeAeXEyrzc5//0GydUJ0/T33YJvx8vm3CLfPtEm6bb5Nw6/zrCbfPv5bgYv75BDfzzyW4mn88wd38Ywku5+9PcDt/X4Lr+dsJ7ue3E4aY30wYY34jYZT5uxP8zt+V4Hv+ZoL/+c2EMeZXE8aZX0wYa/5XwnjzX1dhUVlZsc91PAAAAAAAAAAA+FdPDxjr4SxRlCQAAAAASUVORK5CYII=",
	["eighth-note"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAChklEQVR42u2bwZGbQBBFv1wOgAxMBiaDJQNtBksGDmHJYJUBZLCEIEcg+eYbOALh297+Hqx1lWGAAYSm29X/RpWAfuLPwHT3ACaT6Q7iN55Ikic+6Qs+uQb/oRMTTeFHnfBJ8sJMD0BOtwpGOgCOHJIOK3FMGqzEKUm3Eqcl20r0kWQr0VdSrdQLNGOrykrdKAEmPCuyUh8AYMRSjZVcAACgxkpDAGqsNAygxEpjACqsNAUwYaVEAcColUoVACNWuqgBGLKSIgCnlUpVAD0rtYzVAQCMWbJly9In/N32AJ0b3viOn7SnzAzAAAzAAAzAAAzAAAzAAAzAAAzAAAzAAMLoM1Y10mCPFECEBMAZLYAK33dn8dyMWbAerK7ULD6yauKStQAjPnuVrp8ZCQRgxot39f3CTBiA538/orDWKUjNADcIPyDAYO+bDoD+YLyq4YHpn2IoE6Y8sBEIwMg58zTuhgBmYxBy7FMNtwIwYiUIgPGSAvRQ6ToEQLmsfu5+CiEA6p73I8+R0wgAYNLvelszd4UfwM2ss5utAaYXNGnnuJp1/QriVmTqAL50jmdZCO3WALutWwWs1WA1wK/ue3nmsv9f/b4/QNfzswDQfeX9DD8LPa769dv9AboT4X7W9ff3nla3/pQI0Qfa+xyovT/m6jWfIbcbA8feMC68rl30BnwFSFnQFItyGDEgZ0n5OrqkfHWckYdMabXOFK5zZyqfnGnfNmg7/WBapeYLH/6mVR74MpizzgCZmzr9lCO8RnZbTKkEZNQFliGUgvYlLTBSDlka2fPimnkyQOImc7/nkAveaMuY5UgKt+HhXm/d3coya4pHABG+AvhxLbMeFZRZTab/Ru/wdwisOMtWrQAAAABJRU5ErkJggg==",
	["pause"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAABJ0lEQVR42u3bwRGCMBCF4YfjXe0kJdCBdgKdiR1QAp0QK1jPMqJshmWc4X/n5JFv4uTkSoQQQvacaulCS7qqVtJ5ZkHWoF6PatimxxlrbFlGa7bo8R7/bp7co3u8x2/Nmzayx3v8ZP6MlqJ6pjn8FNwK1OcPu9bqcQPqoourw3q8z6iNsw/et+TqEtPjB9hkQ1W2bq0e/0/ozwMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADE5/hzxVMnffl//+yuqB73DZQNpA1hPW5AX/ThPqxH/jGs7B6fyh/HsFbp2d8gnCRZ5/psF91Tdgt54aW3W/SoaBz3plrp/TF8e/AG9eoWjOOu0kMIIYRI0gti5EF6F7huogAAAABJRU5ErkJggg==",
	["play"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACiElEQVR42u2b3XHCMBCEL5kU4BJcgkugg9ABdEA6gA6gA9wBdGCnAugAOrA72DzEzBDbyLKtn1VG++yHW8n6dJLuRKKioqKiorSFBFsUqAAAFQpskYQU/BF9OiINIfxlM+79Yp8J7DGkG1a84a+hpwIZY/iZ8ufprgi2nwkFxqnChin8FFN0w4LFwKETXI1lw6Wr0sSJAq8oW2Fdn8PCF2qlCf947RhYd7a3AzVeOwGlvZwqafHajkWxU98p8aprQAQJdsoV4Qev+gYa6J7J8DrOgIgIFlR4HW+ADK/TDBDhdaoBGrzOMUCB17kGRES84tWEARGkyD3h1YwBj3g1Z6A5nLrGq1kDHvBq2kCzItzh1YYBp3i1ZcAZXm0acIJXuwY08ZpQG9DAa/V7D0JsQAOve3IDGnhd0xsYwGs1aXdwbUCJ1yIQAwq8poEYaPDanYddQAZEkHV2iLL9zbsQ6+0qB/JUYvzrRFAzoCN2A+1U7jsoA8hkMKH+IA5/ISdp56FlOBvZKdiNDAm2L16mz2Ekc7cXyVxNn8whUz6qr9kPNOqCkh33kXKjrMeoZxztnRzqL8qxPxMf6l/i8qE78bWKApePH+eL+2rxphz7nPhqcQCXQEl8uTuIy/tE3jt64NgMlK/tiB84NHCZivA+8tnGpT0DjnBp8aHbDS4tlRq4w6WFYg+3uDRcbuMel0YLnnzg0ljJmS9cGin684lLA2WXfnE5s/DVPy5nlB5z4FLbwOVP8TcPLkeU31f4FBHBigqXhhsg7jQNED0/0ZD84FKZktUjws8JO8q027BKyjasF0uZDZcaB5OaGpdaGX7eu2TzIJpBn7o0ymYuapRBjHxUVFRU1D/WD9GyiR/sEGpBAAAAAElFTkSuQmCC",
	["settings"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAE/UlEQVR42u1c23XbOBC9zMn/soNlKjC3AtEViB2IHUQdiB1ErsDswHQFgisQU4G4FQip4O6Hdc7KBEA8CFlUovkUIWCAGWDuXAwJ3OUuf7Ykl+mWGZYokCIH0EFC4DXpb2RNWHBHnexY3IL6zxyT53krn3JPm+yZ3rL6c56CwfO1u2GO6q/pI9X83OfoNYFjLDf6EmkGJVSFnvCIb/iGRzwpz1KU87LAcPtK5h+e55Sz3geKi6zte2RO6ucuyimTzOezB4aqvGlbvVn+dcUJDDek0LYSln9dzYEyxTm0qrFS2kU4Sr86qbhAASBHB6BLXj/6P9TzpNN2o/564GPy4VcukQMoIACI5C3G6j4rIerIZy5P4WulCWBG3M9eE9BW73bg0jBSPiW6/mCIGGGCxolc5EeQqzHnIWi40bxLYwMXOXjbgbkntvlfCku2FiZHrykwDVx9B5QZ6EbkwcOR+BI4SO3Uex3Y+4t7Uh7k++5GZhG4F4rwzKplxYIVO23HkrXfScGUtYJP30WcRmo1z3dhcfXDzJlxfTaNniI8u2JFcWYLwTUziydkCNhklemkiodmp+py/qdm6DxXxVntQJvGjkaHRmquihQbi3Z2MJe0ISAEC5TIkCED0KNHjxZvifSmblvvxI1iWuLHbIRcfHbYhON5nPD3uioy/Nv4HLjKNm7946QzERifWtRAmjogQXcb0Av+OUEz7YK4HN2aCGidQnxmTqu+2yGgBVujiNzZeZwXxZCN1K6eJ7VrZjxBuI2LXZlp7Smdtz9LH1Jci57IjjULpkxZsDaAwMyLqPehYQyYfe0EPkhyq1hVZ6XGg6ivfQOIdidoHc5xrbR21TjFBO93SP5KB7W2HnuldJpmFY7XrUZXHKgbPR467/4s6o9yo0mjXE1kVvQ6EuwTqTy19/eUNFPI3eGAD0qLv52IXdPTv5QWD+4L4hYTLMy/H2Ebu794d2RXky+eVxe/lBb/el1bDJ/+VFr88rsGsU2gslLkQy50nLsZPpVWEr6aMAFWWFnUVX9Zmr2WKZbe/a1iRoFbCmTa5LD/FCihox03vupvJ4K5waWEIVu+FJgzUODCC07vueGCKVMuuDEkPJkbM+IJpw3poRxJaOroCY2cUCCiVaezpJSdt/qdJaXsw1PKo99gI2moWaRDj+qiHIPqHuzqG+pRxtR3o1W6AFpFcSDhQUN1051n0KPwJ7amUYv27VxfmlqcTu42RuWb+OTuV0SWpEfFNQqUyJDiAcBPSPRoIfzp9RAIISawMfG1KW0WUNGo9IOzF5bKil5/v0s++zXr9zNkc+COq2DFV9yd0Vh7fo9wzWqAUi9cccGVAZQd/e5dAKbcGAj5/WmkF3c4GafU4OD+dgCLwGKSIvR21lWc0g5uAntvfQzcc27lNr2Xk3pBs88oeJIhNVuB5WGjvR4uXcpjv5T4/KK/7YT6UmZsFGeSbN4BBlNWGlc7eKy/ZHUquywNI2UR3iNjgQJAhh6ASMQgigqFY/4n6bTxdq/QkuWg8HVkpEu+veHkRJcpPY7ATicSr9ZrCx1N+xoDXseh11sngjePenXxu7wAcX8F5aReN16Poqllaec1gUpL8C6YM+dCS+xWmNmLcJGZuXnY4HZeRRwhxRmcWV3BjSJTi/OcwnzVd6re2gK38FEAYSisL3BDn2UoUSA9lR5LCLQ381mGu9zlpuQ/annII2SGwpwAAAAASUVORK5CYII=",
	["skip-back"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACgElEQVR42u2b0XGCQBCG10zekxJIB5RAB7GDpAPtQEqwA+xAOpAOklQQO4AO/jyYyeiBwMHt3pLZ/81BzvvwU7jbOyKLxWKxWCwWy1WQ4IgaNY5IxD/7GTucUAMAapyww7N/9y+nX5pIRC9cga4UXhAob04uxbq/u7pwbmpk4xu6baYW6XyGbwwlH9uYE5Ff3Li8KwToFactUqoKYJQ48P5FygB4iHObRAXAgDifWBMRYY2mdWwfHWBAnAbbq/em+HSOV1EBBsU5uLcsvCsCGBQn60T27Q8PgI84M/sTHsBfHFUAU8RRAzBdHAUA88SJDjBXnKgAIcSJBhBKnEgA4cSJABBWHGGA8OKIAnCIIwbAJY4IAKc4AgBYc4rDDoAdrzjMAK1xUnBxWAGQ3pUnmDi8ACd+cRgB2qNUDnE4AfYd1z4jtgz159G7RXd+8ouyVUPR8uB9xpPzeh+z+0Sr9lfmvGHVf5xeVmfW+euB/jzQwuMP8OW8zpYG4Bq/GVV2UARQtf6VTsgUOTXxRlYs5kZGhOpOBWuzFIC0o3JyycciHuYGHqcL9Y/TRETIe8uhG/UARMjuihRUJt5Bfdk7qC9UD+r/voczr0wSE1s5p0xSU4tsMklO7rLIJDu9ziCTfIEjsExxSkwBZYpV5AsmU8wyaxCZYhe6Z8sUf6nBTJl0LPaYIZOe5TYTZVICMFUmNQuepsqkasmZv0xI8aEOYJRMb0REeO2oBOV6Fr6WC174Okom3UuPR8rkVoJSncvvy7DL72+vSCO0AeIcbgNErC0ofTL5lBGRXDXUCG8COnRC+JZwkaBEgwZllG1YOapfjAYVtlzT9haLxWKxWCz/IT9UB40uDmzDngAAAABJRU5ErkJggg==",
	["skip-forward"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACZ0lEQVR42u2b3ZWCMBBGx63AEiiBEuxg7WDtYLcD6cDtQDuQDmAr0A60g6SDb198QJCfmMwkOWe+Z0Ny4XoIzECk0Wg0Go1GoxkJ1tijgQEAGDTYYy2+hgJnGBicUbgu/ohhDI6OB/JdvunMvXxmbDsDhxB7MYD6aeZ66bAD5nLDRgTg+TSaZYN2WJYzv0z9KZcMKSfkEZfpHYAGbmGVyRkABd4Jm0zuAL+DxVlsH/+Mq7xM7gBtb8S1e27xAysrkz/AbnB7O0nK5A7Qz4vlYCMnkzfA6O+EZGIDkJKJEUBGJmYAfpkEAHhlEgHglEkMgEsmUQAOmYQBwssUASCsTJEAwskUDSCUTFEBQsgUHcBXpgQAFsm0SRxggUz75AFmZdolDzAjk0GZAcCkTHUmABMyFZkAPGQaXocqIwAilLj3pmtd1/NBEbO6UuV9jCFx7wcr1mtQ0G16vrn1RL0CIRIboL+F+MsKACUdMr4C2FBD/aJtG6Ok896N7JjxjQzfI1W4Oo/N3GVkM2eT38yNipPHdnpUnJFdUGqPlJeJxdukHylnxAHqpB/qZ8S5J/1aZVacKu1Xix7ixH+56ylO7Nfr3uLELHAEESdWiSmYOHGKfAHFkS+zBhZHttDNII5kqwGLOFLNHmziSLTbsIrD3/DELA5vy5mAOCEBLt0nVSlxwrZdGnwSEeFLThz5xtc6mcbXFxLN5Z5U6zERyslyqIg4nnuzxe33dZLt90REqOKK01nJsw3WrwQnJo73JygTpVCLk/BHQLYzd+H+bqFC+ziERYsqymdYNSysxD9Oo9FoNBqNJq/8Azwcu2dhSMdKAAAAAElFTkSuQmCC",
	["sun"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAADo0lEQVR42u1c65miMBQNUwHbASXQAZQwHYwdrB1IB2MH2AFMBdKBbAW4FRArOPNj0RFIQp4Qv839N0rgnOE+ch+RkCBBgjgSJKjQo0eF5DXh97hL/4IUUONZ6tcj0I8I9K6eEzkjgMmDHD3p7dVdRSAQCAQC/wcBZOvGUiTI7N3sMASjC1KFVXQUyKjCyhSXYdXBBvziOZ7KU9DdSiAdxfDCQkQdbwlkKSB5egdUVgEn8DGN5+rwc8CAQg0KilofPoDc1JigT0HxWSz4MHYeaNehwIHf2rgxdU+BA59aeQqHwsUqgYsz+AIK1t4Bw1VIw5eKxFFLcnKbfRw7DMU3kketbSOjlv0D39dRJ35uQqF2VgJwA3+gcHeqNWLhdQeccR5M84IzzvgtgoX4QaF1Bv8BLucrDxKU6MCTDqVwbe4Y/AK1+LFvFcsBMfFPsGOGIrb02PkG/wBVOfgDPkYJHSk9USVN+ABQ+gC/gIkU25suW6443p0iUuQ44sq5cret9vdM8DsO2SvTI8V+qY8gRj/FWx/UiJlunhZXnRykjZoETurwGQUXADhuQ6Cb6X4saTlTW+i2gJ/q+xOG70q3N+Cr0urpO9gT8+Lu0Neduzl2n3dacFJLcKZXv3P7zLJ4Rn3d+aLZEjQmFbRZGt+Y4iFMDy1IIGcmnBhZ0EUXT/TT1xVWGWj0y24bdWm9LJ43yY5xtLqXkMTzQ6ARLph/+3eqs2oqNPngj8QTxd+O6vnzKtkWRiyF5/EGoitJyRej/nYjXySNlr38u5KCLF5tjGfxf7g32Q7MfNiehK2EOoXZlkx6M9eZbEPsNbqnhpcQuSS9JInRNsRpQlNq1TC2SWg4KWUlTCkrryoTiJm+usMH8+oPZtmXblre4pZVOnwie5RVMnxya9a7UNhykNzLyokQP4q7ehROHvUJNBSpIMS3BgeVBk+9a3AMqiT3HoptHWcmGj9DghO3Dv2vZi1am1kcNFsYBqsW2qx7NGiGpmyLBg32C23WSmewzWSipLJ678r5PBJjICZxllvYp+BgGMzSYNubZA3hzKjSUIfmFpOzzWkhN8Ng6wy2OR0GW2OwzfEwmOvBNmbaSJ2NXVLr6SbDP1CFwVfFc2RMCrnd0WMV+BrnyOYU7G6U6SrD39TypvtBQWkYTP8c2dNgm72cQTRmJqV6UHYeeTgIR8IhoEAgEAgEXpnATfDXSxBoiHzXl/j5owAa58h8o6B4jixIkCDq8g3S8DtFND2NFAAAAABJRU5ErkJggg==",
	["timer"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAD20lEQVR42u1b3ZGjMAwWO/e+vgo2HSwdhA6WDsJVEDoIJVwHoYOwFYSrIKSC0AFOBbqHy24mIH5sSw43g94yQ2zJ1r8+Ayy00EJMhCs8YINj1OABV/Nkf5z5uxDzEwELNKGCa9+ATYAGlMHnOvjJs+8LPOco2A6OT4BS8GtPRqwnW4Ceqx8qJgihsZgl+wsttNBCC/2XFHAviGsIQQFABAAKQgCoQN+SBw1V8Geu5YzCDe4nFTR73KCaF+tbPKIpHXE7CzFwZ1CJdW9j91zmN3hBV7rg5jnMRwzM34WIfLO/R27a+zTaI0rQ0caojeMAhrCHcPCTMxRffj+oAPAeF2J4H/xnBb+CSlrzm8FaKxk+RVSYDNZtjag1YDLAfGa0UjYgRCJ3+r3Mm2svKsx6RZC4BQx7lMehRMdVTz+vwZDf85zIrVLnlVNy3RNzmkE6To0xy9oxaQ9H6bBV810zhlgLhjbSeGveK0ZFisBjzETOo9mNDDAkFOkk5ftjkPBzsUhMIM4/BSEiPNLFdcmMf7Zym6WRszIiLmRuptVwN8YfAmJnVoYrIqgpzivNmON5MeHO7VW2E321m/Mk0pELcettb1TaKxDr+ZPZVD3J7hSPA9UCySDpEjp3kNgN+SK+wRyGcCTGsFdIJ40AI8vJL1dQ6Tn93njeufuGJwNSftgnrS8yV6H28udAsypP1F++BxrOI9xMEKC9aeGLfXI35S6A9sg+S2JVuubm5ro/YIGlPFaik7L5Of1+Ad5av2vDlX87sd9W2FfzE2yRcxQxrONc93cXQLuVoe4CtIvslRMEzZT9sLV7ZW4DbZ03LWRSuDqY7mQnLuaFghpC+IQrXOETQjm//wP6e/XrVjAvjUWw715MzoRfJjuyOU12rVTowytfH86JDF86zVLM2pQ0JoWd8CRI26lQO6WNvSlQPD2VfzEAp669CbBmqca52yoO7Uxb68OKsc1n384s7d1o3okFqfgFpDzFbF+bT/jpAtHcdWtnEvp4EBXgwG53xOzK54CjXkZM5B00IkO+bhFayY1ZL+xj1osgZgJzUgTOQTfFfi7Z5vqnSFxQA6oBVnLHx4oEZWydV96S61bsMZ+cpCOiy8NCXBF+XwgJMAR4QtxZAZ52XgFPI5AzQwzuIN43kQX96cF3qptR0N9m8M2rNj19G9hlPgqe/IJdXm+wy9dv2OUYYDPxMTlQpFN1p9Ijmp0MbW6UA/gGf9dszFfewd/fXsldiNpfu8Ycgzv+MDQDmMMTlNTCrEtM5/aSJsF80nPcfAwi/txnWNHDM6x3ADg/PMMqYaGFFmKkvytMplsF/+rnAAAAAElFTkSuQmCC",
	["user"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACqklEQVR42u1abXXjMBDchMCZQc3gzKBmkDBoIJRBwqBhYDOoIaQMWgROEUSHYO5H+/ruFKnRyl5JaXb++T3J2rFXX7NDpFAoFIpbxkLipWhoRS0RVdQQ0SsZIhroZfFa/PdAjQ4jfBjRoS43+ApbhGCLqsTwNzghFCdsSgt/Cy62JaVOhxh0haRSZPgA0JUQ/g5TsMs/dd04Yo8WzceugBZ7HD0tN3mz/+QMfuMhe3SuSFVZ6TP4A0KFoaA0Qu0Ipr/Yq3f0yrM7O0Lpg/qd/4V9HgLjWe5XgTPHngtjjvCb+PXEsXY1+SfwkdXb/gePsXEsoxm01vPA6m23XqcnQLMSoPQE7qxnVgqRsZ5/Jb9SAtaLFmn7z59CmRBP4N3el5nX/v/xlp6AnfO840B1YU5kSKG1YGsRAvZCuGL1Xkktq7dzlHAcB8bgw9w45Rgy3xw4nE3jsEt6dzbhB6JSLjRdlIaR50LjuVI+f3ulfC5KmUAF45RwH5ytH5yyr8kqb3lllRFPuP+SVe7x5NWsc8oqP0DY8uoMYeiJyhB34yj0BdUJIhJpR1RagcMEB2+KK3B8plLYf9gVWWL62p17rw79oVnX11FmbWlNRBX9JqK3zzLr4QrKrAqFQqGgG/ILWb4gLnL6iC74grhI6yMK9gWx/StJDnksXxAX8j4ioW+fxkcU7QsqxUeUKHwpH9FE+ST3jTnEFxQh0KfyEfF8QREfR9pHxPUFRXwgSR9RnC9oFn2vzuoLYo8zCI0T6wuKSCQJH9GUYt4Ma12T2Rc0uXD4OL3I11LKghzbR7QU9gWJv30p7Avigu0jWqTy9Uj5iG7YL6QElIASUAJKIIjAn2+eJMAcb8n0ZR3ECcw9Hup/KvBGXoIVGA81BhgYDGkU5NTjKRQKheKa8ReddoJLiFWApAAAAABJRU5ErkJggg==",
	["volume-2"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAADUUlEQVR42u1b0ZGbMBBdMvmPOggdhA5MCS7BHcQdmA7iVGBSQZwKTAfmKjCpQLiCl4/c+XxCQhIsIGb0vu4YjXgPrVar3TVRREREREREREQEC3DABQBwww+kayOf4YpnSBzWRV+ii+O66QNAtm76QLlu+sB13fQBDJxXYIMDNovTHyYAGW5vKzjhLnKhP0QAxIP+fwliTvotg4CtMsVlTvoZg4CiM+9pNvpEDAJ2mrl3M9FnESC6hgggn4U+hwAi5Jo3SBZ/ZKPPI4AIe81bxm9m5Db6XAKIUA40I2Q44OLi4XX0+QQQoR4QmOA7/NCqlskoQKDx9Eb4PZY+pwCi7qmCm+/G8aTPK0C7Ewp3tQPo+whAihMkJE5mB4lU406F6wHeh9r0UlcBHxyyNKcANLy2+oGVB/2i57u6CijdfLzmXNbf8pwcZ40ziv6EibMA9X175zWQNM52LdvOVYCrbev2wZP5flrsNvpL+V+QwTCThl6UR7sQViD1WIOjw4k8twCtj985u/g0BAGpe6zT8UT58nuAkoZ+Ko8y4wX+rI4MQAARFXRXnpgC5qaz5UMQkLRUOwowYtkVIKpMpmEZl4cioB07wdICVBP66ij0y8MM392fYp/JUDfqMw8ESbfxpnmXXgFauwmpm/av6SxWHryEKqAxjBOmPbG0ALF2E8otXsk0rgpCAAR9sxxYga9A0TEhk4DUegAGEU7XzjfoIEKJ7hXyaHSiwuqtArhSts5XyjqEPdD9/mViCu02lutNEGmVdlha5fPjr/t7hKcLnl69dEM1/UlqhhVQ3keF8furV/279v1eqcUDe2qx6kktSrfUol9y98qQ3G2fzCel0cndTFvcNEMypNdLtGhR9tD38FX+BQ4ZVIGDiAjn8RImLjE19vrsSENiLfLdBrQcIEOBykOGnKzMenWPldwL3a1NAtuBeJqkX8Lgq+QsrQYVEU+3RK8ElmaPrXtVlF0CS7uNnLDdxiZhBQ1P/RImaTkrp+ma00vgb/qriKbqW2wnartsPtSmBdGCEgbOW9taGmaTMDiMyLFn9TwDJdQUenY6qSnvlOrsqUIKrYe9XfEPIHokrOUnKIrneItdClobULyKaPruuREREREREREREVz4B9zju6y1QN8pAAAAAElFTkSuQmCC",
	["volume-x"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACa0lEQVR42u2b73HCMAzFBRMwQkbICIzQTcoGYYRuABskG5QNkk5ilwVev3AtEMt/CIelnt4n7gjk/RLHlmSFyGQymUwmk8n0FKHDCABwOKDRZr69mP9Tp8u+w1wH3fYBYKvbPnDUbR8YddsHoNy+aIAc+4IBGPteCQBrv1UBwNsnUgAQs68AIG5fPEDKvnAAbFP2BQCgRYfPnBk+ZL86AN5Rpjv7lQHQL7VfFQC75fYrAszX0Efsvx5g/fvpreh3X7RdTbKmyFPB1d9H/qfoDqBBDweHPl7FyDgua+KcMGCfOFUBAJqrs7rwkJwtn445/7PGbhHAcHMogzBb/Qc5APd3PYAQCF6cHIBZ+nOPEIy9vNQhNENgQkdBQ6gJ3INfBDbylfMQE6HlENKBuwgAFuGMc5H9egAsQpn9mgCZCHH7dQEyEFL2awMkENL26wMQoQ0+uMA5Zn9N/0UChhAfDzvxQyhZ6XaiH+KsQr0TO43m7TMkESqGEi47lHDiQonIPkMbi1TlhNOxQj2H0MhOaPxNQuNlJzQuWSoOIQjOiX0wqfdacmLPllV8zhDKSSpG9OjiC8rDObGPFrZ8OicuKS12TywtDvDwGJKlxdRx2BfVpkfuetUsr/siBCejvL5kg8OJ2uBgF5ZChNqbfLulA0nCNusepwIMJ2qbNbnRnYwQ5bcaJBA0NHtEEXS028SK4koanlgEPS1nXF1fUdNfGEFV22XGaiG98dWrBshB0ND8HUOYXtet8qBWE23pm/16ItLxBoFX/AJEBOFIpOktmim/q0gmwgYfFwiPo7rXsK4wNmQymUwmk8mkQz9L4pdh9wXOvwAAAABJRU5ErkJggg==",
	["x"]="iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAABjElEQVR42u2a0W3DMAwFg06iEbx5PFI3EOEFXn9aoEZlW7ZJ6rl4N4ByhwSBRPD1EkIIIYQQQgghxAEoeKOi4o3ywPNRUPFDxeR+/rQ63z8BM37jnLDSB4DZP2D9Aa4Jf/SB6h9gQExCQx/4jP4JuSU09UN+QqXxHdxO2NC3mP+hyTthU396xeCbkK7vmzBE3y9hmL5PwlD9+wnD9e8lUOhfT6DRv5ZApX8+gU7/XAKlfn8CrX5fArX+cQK9/n7CI/R3EhYsj9DfSXiKfncCr35XArf+YQK//nfC0tRfIvQ/NPPtu/OEzVQz9fkTDvW5E7r0eRM29NtXicp4E9q4svkPJFP1Y2aqqfr0CX33fdqE/ucKZcK51xZdwvnHIlXCtbcuTcL1pzpFwr1Jw/CE+4OSoQk+c55hCX5jqiEJvlO29AT/IWFqwmpfyG1QsplQcpY9zGXZw3KWPWrUmKqZkLAvZK4LT5a9L2TuK2eWuS9kIUt/Fr0vVDDDYJjD1i5DzxdCCCGEEEIIIf4XX83XPbAq1sRyAAAAAElFTkSuQmCC",
}
local lucideAssets={}
local function lucideAsset(name)
 if lucideAssets[name] then return lucideAssets[name] end
 local register=getcustomasset or getsynasset
 if type(register)~="function" or type(writefile)~="function" then return "" end
 local ok,asset=pcall(function()
  if type(makefolder)=="function" then pcall(makefolder,"Altair");pcall(makefolder,"Altair/UI");pcall(makefolder,"Altair/UI/Icons") end
  local file="Altair/UI/Icons/lucide-v1-"..name..".png"
  if not (type(isfile)=="function" and isfile(file)) then
   local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
   local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
   local source=assert(lucidePNGs[name],"Unknown Lucide icon: "..name)
   local bytes,acc,bits={},0,0
   for i=1,#source do
    local digit=digits[source:sub(i,i)]
    if digit then
     acc=acc*64+digit;bits+=6
     if bits>=8 then bits-=8;bytes[#bytes+1]=string.char(math.floor(acc/2^bits)%256);acc=acc%2^bits end
    end
   end
   writefile(file,table.concat(bytes))
  end
  return register(file)
 end)
 if ok and type(asset)=="string" then lucideAssets[name]=asset;return asset end
 return ""
end

local function styleSettings(root)
	local panel=root.Settings;local types=panel.SettingTypes;local template=types.Template
	types.Position=UDim2.fromOffset(24,86);types.Size=UDim2.new(1,-48,1,-108);types.ClipsDescendants=false
	local grid=types.UIGridLayout
	grid.CellSize=UDim2.new(.5,-9,0,58);grid.CellPadding=UDim2.fromOffset(10,10)
	grid.HorizontalAlignment=Enum.HorizontalAlignment.Center
	grid.FillDirectionMaxCells=2;grid.SortOrder=Enum.SortOrder.LayoutOrder
	template.UICorner.CornerRadius=UDim.new(0,11)
	template.Title.Position=UDim2.fromOffset(14,9);template.Title.Size=UDim2.new(1,-28,0,20)
	template.Title.TextXAlignment=Enum.TextXAlignment.Left;template.Title.TextYAlignment=Enum.TextYAlignment.Center
	template.Title.TextSize=13;template.Title.FontFace=Font.new(Font.fromEnum(Enum.Font.Roboto).Family,Enum.FontWeight.Medium)
	template.Shadow.Visible=false;template.UIStroke.Thickness=1;template.UIStroke.Transparency=.4
	local description=Instance.new("TextLabel")
	description.Name="Description";description.BackgroundTransparency=1;description.Position=UDim2.fromOffset(14,31)
	description.Size=UDim2.new(1,-28,0,15);description.TextSize=10;description.FontFace=Font.fromEnum(Enum.Font.Roboto)
	description.TextColor3=Color3.fromRGB(210,210,218);description.TextXAlignment=Enum.TextXAlignment.Left
	description.TextTruncate=Enum.TextTruncate.AtEnd;description.Text="";description.ZIndex=template.Title.ZIndex;description.Parent=template
end

-- CAPSULES BEGIN: layout, Lucide vectors, and bindings are authored here.
local function bindCapsules(context)
	local root, Clock = context.Root, context.Clock
	local runService, input = game:GetService("RunService"), game:GetService("UserInputService")
	local tweenService, http = game:GetService("TweenService"), game:GetService("HttpService")
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
	local function tween(object,time,properties)
		local old=controller.tweens[object];if old then old:Cancel() end
		local animation=tweenService:Create(object,TweenInfo.new(time,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),properties)
		controller.tweens[object]=animation
		animation.Completed:Once(function() if controller.tweens[object]==animation then controller.tweens[object]=nil end end)
		animation:Play();return animation
	end
	-- ImageLabels use Lucide's real artwork; no drawn geometry or Unicode substitutes.
	local function icon(parent,name,kind,x,y,size,color)
		return make("ImageLabel",parent,{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(size,size),
			BackgroundTransparency=1,Image=lucideAsset(kind),ImageColor3=color or white,
			ScaleType=Enum.ScaleType.Fit,ZIndex=parent.ZIndex+1})
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
		url=type(url)=="string" and url:match("^https://i%.scdn%.co/image/[a-zA-Z0-9]+$") and url or nil
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
				local response=context.Request({Url=url,Method="GET",Timeout=8})
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
	local compact=make("CanvasGroup",host,{Name="Compact",Size=UDim2.fromOffset(300,24),BackgroundTransparency=1})
	local strip=make("Frame",compact,{Name="Pills",AnchorPoint=Vector2.new(0.5,0),Position=UDim2.fromScale(.5,0),
		Size=UDim2.fromOffset(250,24),BackgroundTransparency=1})
	make("UIListLayout",strip,{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Center,
		VerticalAlignment=Enum.VerticalAlignment.Center,Padding=UDim.new(0,5),SortOrder=Enum.SortOrder.LayoutOrder})
	local smartBar=root:FindFirstChild("SmartBar")
	local baseColor=smartBar and smartBar.BackgroundColor3:Lerp(Color3.new(0,0,0),.4) or Color3.fromRGB(18,18,18)
	local surface=frame(host,"Surface",0,0,300,24,baseColor,20)
	surface.BackgroundTransparency=.04
	surface.AnchorPoint,surface.Position,surface.Visible,surface.ClipsDescendants=Vector2.new(.5,0),UDim2.fromScale(.5,0),false,true
	-- Match the SmartBar finish on expanded surfaces; compact pills retain their styling.
	local sourceStroke=smartBar and smartBar:FindFirstChildOfClass("UIStroke")
	local outline=surface:FindFirstChild("CapsuleOutline") or (sourceStroke and sourceStroke:Clone()) or Instance.new("UIStroke")
	outline.Name="CapsuleOutline";outline.Color=white;outline.Transparency=.85;outline.Thickness=1
	outline.Enabled=true;outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;outline.Parent=surface
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
	local sizes={}
	for name,group in pairs(views) do sizes[name]=Vector2.new(group.Size.X.Offset,group.Size.Y.Offset) end
	function controller:Open(name)
		assert(name==nil or sizes[name],"Unknown capsule view")
		if self.picker and name~="duration" then return end
		if name==self.view then return end
		local previous=self.view
		self.view=name;self.transition=(self.transition or 0)+1
		local transition=self.transition
		if self.cancelDrag then self.cancelDrag() end
		for key,group in pairs(views) do
			if key~=name then
				tween(group,.12,{GroupTransparency=1})
				task.delay(.12,function() if self.alive and self.view~=key then group.Visible=false end end)
			end
		end
		if not name then
			compact.Visible=true;compact.GroupTransparency=1
			tween(compact,.24,{GroupTransparency=0})
			local origin=self.origin or {x=150,width=60}
			tween(surface,.3,{Size=UDim2.fromOffset(origin.width,24),Position=UDim2.fromOffset(origin.x,0),BackgroundTransparency=1})
			tween(outline,.2,{Transparency=1})
			task.delay(.3,function() if self.alive and transition==self.transition then surface.Visible=false end end)
		else
			if not previous then
				local source=pills[name]
				local factor=math.max(.01,scale.Scale)
				local x=source and ((source.AbsolutePosition.X+source.AbsoluteSize.X/2-host.AbsolutePosition.X)/factor) or 150
				local width=source and source.Size.X.Offset or 60
				self.origin={x=x,width=width}
				surface.Size=UDim2.fromOffset(width,24);surface.Position=UDim2.fromOffset(x,0)
				surface.BackgroundTransparency=0
			end
			tween(compact,.18,{GroupTransparency=1})
			task.delay(.18,function() if self.alive and transition==self.transition then compact.Visible=false end end)
			local size=sizes[name]
			surface.Visible=true;views[name].Visible=true;views[name].GroupTransparency=1
			tween(surface,.36,{Size=UDim2.fromOffset(size.X,size.Y),Position=UDim2.fromScale(.5,0),BackgroundTransparency=.04})
			tween(outline,.28,{Transparency=.85})
			tween(views[name],.24,{GroupTransparency=0})
		end
		self.layoutAt=0
	end
	local function pill(name,text,width,color,action)
		local p=button(strip,name,text,0,0,width,24,Color3.fromRGB(10,10,11),function(event)
			-- Touch has no hover; tapping opens the same animated surface.
			if event and event.UserInputType==Enum.UserInputType.Touch then action() end
		end)
		connect(p.MouseEnter,function()
			controller.hoverSession=true;controller.hoverLeftAt=nil;action()
		end)
		p.LayoutOrder=#strip:GetChildren();p.TextSize=8;p.TextColor3=color or white
		return p
	end
	local menuPill=pill("ControlCenter","",24,white,function() controller:Open("center") end)
	icon(menuPill,"Chevron","chevron-down",6,6,12,white)
	local musicPill=pill("Music","",62,white,function() controller:Open("music") end)
	musicPill.Visible=false
	local timerPill=pill("Timer","    05:00",50,amber,function() controller:Open("timer") end)
	local watchPill=pill("Stopwatch","    00:00",50,green,function() controller:Open("watch") end)
	for _,spec in ipairs({{timerPill,amber},{watchPill,green}}) do icon(spec[1],"ClockIcon","timer",5,6,12,spec[2]) end
	pills.center,pills.music,pills.timer,pills.watch=menuPill,musicPill,timerPill,watchPill
	artwork(musicPill,2,3,18,9,6,7,10)
	local compactTitle=label(musicPill,"Title","Spotify",24,0,60,24,7,white);compactTitle.FontFace=medium
	timerPill.Visible,watchPill.Visible=false,false
	local function notifyError(message)
		if os.clock()-controller.lastErrorAt<4 then return end
		controller.lastErrorAt=os.clock();context.Notify("Spotify",message,nil)
	end
	function controller:ShowSetup()
		context.Notify("Spotify setup", "Run Companion/StartSpotify.cmd. Create a Spotify developer app with redirect http://127.0.0.1:"..tostring(get("Spotify Bridge Port",43827)).."/callback. In Settings enter its Client ID and the companion's bridge key, enable Spotify Connection, then click Link Spotify. Approve in your browser. Unlink Spotify removes this device's account tokens. See Companion/README.md for app access requirements.",nil,{Duration=12})
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
					elseif job.path=="link" then context.Notify("Spotify","Finish linking in your browser. Keep the companion running.",nil) end
				else
					if job.previous and job.generation==self.mediaGeneration then self:SetMedia(job.previous) end
					notifyError(tostring(result))
				end
			end
			self.commandBusy=false;self.nextPoll=0
		end)
		return true
	end
	function controller:LinkSpotify()
		return self:Enqueue("link",{clientId=tostring(get("Spotify Client ID","")):match("^%s*(.-)%s*$")})
	end
	function controller:UnlinkSpotify() return self:Enqueue("unlink",{}) end
	function controller:Control(action,value)
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
		state=table.clone(state)
		local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
		state.duration=finite(state.duration) and math.clamp(state.duration,0,86400) or 0
		state.progress=finite(state.progress) and math.clamp(state.progress,0,state.duration) or 0
		state.title=tostring(state.title or "Spotify"):sub(1,300)
		state.artist=tostring(state.artist or ""):sub(1,300)
		state.connected=state.connected==true;state.playing=state.playing==true
		self.media,self.mediaAt=state,os.clock()
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
	local timerTile=button(center,"TimerTile","",11,102,136,33,Color3.fromRGB(28,28,29),function()
		if clock.timer then controller:Open("timer") else controller:BeginTimerEntry() end
	end)
	label(timerTile,"Label","Timer",10,3,90,12,9,gray)
	timerSummary=label(timerTile,"Value","Set",10,15,90,15,12,white);timerSummary.FontFace=medium
	timerCancel=button(timerTile,"Cancel","",110,7,20,20,Color3.fromRGB(40,40,41),function() clock:CancelTimer() end)
	icon(timerCancel,"Close","x",5,5,10,white);timerCancel.Visible=false

	local watchTile=button(center,"WatchTile","",153,102,136,33,Color3.fromRGB(28,28,29),function()
		if not clock.watch.active then clock:ToggleWatch() else controller:Open("watch") end
	end)
	label(watchTile,"Label","Stopwatch",10,3,90,12,9,gray)
	local watchSummary=label(watchTile,"Value","Start",10,15,90,15,12,white);watchSummary.FontFace=medium
	local watchCancel=button(watchTile,"Cancel","×",110,7,20,20,Color3.fromRGB(40,40,41),function() clock:ResetWatch() end)
	watchCancel.Text="";icon(watchCancel,"Close","x",5,5,10,white)
	watchCancel.Visible=false
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
		factor=math.min(factor*math.clamp(viewport.X/1280,.8,1),math.max(.45,(viewport.X-24)/300))
		scale.Scale=factor
		local width=(self.view and sizes[self.view].X or 250)*factor
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
				if ok then controller.failures=0;controller:SetMedia(state)
				else
					controller.failures+=1
					controller.nextPoll=os.clock()+math.min(30,2^math.min(5,controller.failures))
					controller:SetMedia({connected=false,title="Spotify",message=tostring(state)})
				end
			end)
		elseif not get("Spotify Connection",false) and not context.MediaAdapter and controller.media.connected then
			controller:SetMedia({connected=false,title="Spotify"})
		end
		renderAccumulator+=dt
		if renderAccumulator<(controller.view and 1/60 or .1) or not host.Visible then return end
		local renderDt=renderAccumulator;renderAccumulator=0
		if surface.Visible then
			local rainbow=get("Rainbow Mode",false)==true
			local accent=rainbow and ((context.GetRainbowColor and context.GetRainbowColor()) or Color3.fromHSV((os.clock()/8)%1,.65,.8)) or white
			set(outline,"Color",accent)
		end
		local remaining,elapsed=clock:Remaining(),clock:Elapsed()
		set(timerPill,"Visible",clock.timer~=nil);set(watchPill,"Visible",clock.watch.active)
		local musicActive=controller.media.connected and controller.media.playing and (controller.media.duration or 0)>0
		set(musicPill,"Visible",musicActive==true)
		set(compactTitle,"Text",musicActive and controller.media.title or "")
		if controller.view=="music" and not musicActive then controller:Open(nil) end
		local pillWidth=math.clamp(compactTitle.TextBounds.X/math.max(.01,scale.Scale)+33,60,110)
		set(musicPill,"Size",UDim2.fromOffset(pillWidth,24));compactTitle.Size=UDim2.fromOffset(pillWidth-30,24)
		set(timerPill,"Text","    "..Clock.Format(remaining,false,true));set(watchPill,"Text","    "..Clock.Format(elapsed))
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
	if not context.BuildOnly then controller:Layout() end
	return controller
end

-- CAPSULES END

local bindings={Capsules=bindCapsules,Clock=Clock,Notifications=buildNotifications}
return function(options)
	if options and options.BindingsOnly then return bindings end
	local objects = table.create(#nodes)
	local ok, result = pcall(function()
		for index, node in ipairs(nodes) do
			local object = Instance.new(classes[node[2]])
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
		styleSettings(objects[1])
		objects[1]:SetAttribute("AltairUIRevision",4)
		bindCapsules({Root=objects[1],BuildOnly=true})
		return objects[1]
	end)
	if not ok then
		for _, object in ipairs(objects) do object:Destroy() end
		error("Altair UI | Construction failed: " .. tostring(result), 2)
	end
	return result, bindings
end
