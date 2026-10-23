-- Reference: 300px black capsules; 20px corners, 8px stack spacing, content-sized height.
return function(context)
	local root, tweenService = context.Root, game:GetService("TweenService")
	local textService = game:GetService("TextService")
	local controller = {alive = true, active = {}, pending = {}, nextId = 0}
	local font = Font.new("rbxasset://fonts/families/GothamSSm.json")
	local host = Instance.new("Frame")
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
		local group = Instance.new("CanvasGroup")
		group.Name, group.BackgroundColor3, group.BorderSizePixel = "Notification_" .. item.id, Color3.fromRGB(17,17,17), 0
		group.Size, group.GroupTransparency, group.ZIndex = UDim2.fromOffset(300, 64), 1, 350
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,20); corner.Parent = group
		local gradient = Instance.new("UIGradient")
		gradient.Rotation, gradient.Color = 90, ColorSequence.new(Color3.new(1,1,1), Color3.fromRGB(115,115,115)); gradient.Parent = group
		item.group, item.generation, item.connections = group, 0, {}
		item.titleLabel = label(group, "Title", item.title, 14, Color3.fromRGB(250,250,250))
		item.titleLabel.FontFace = Font.new(font.Family, Enum.FontWeight.Medium)
		item.body = label(group, "Description", item.description, 13, Color3.fromRGB(174,174,178))
		if item.icon then
			local icon = Instance.new("ImageLabel")
			icon.Name, icon.BackgroundTransparency, icon.Image = "Icon", 1, item.icon
			icon.Size, icon.Position, icon.AnchorPoint = UDim2.fromOffset(22,22), UDim2.new(0,20,0.5,0), Vector2.new(0,0.5)
			icon.ZIndex=351
			icon.ImageColor3, icon.Parent = Color3.new(1,1,1), group
		end
		local button = Instance.new("TextButton")
		button.Name, button.Text, button.BackgroundTransparency, button.AutoButtonColor = "Dismiss", "", 1, false
		button.Size, button.ZIndex, button.Parent = UDim2.fromScale(1,1), 354, group
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
				params.Font=Font.new(font.Family,Enum.FontWeight.Medium);params.Size=14;params.Text=title
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
