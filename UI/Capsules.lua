-- Top capsules: one clock model, one throttled render loop, one in-flight bridge request.
-- Reference geometry is in logical pixels (the supplied recordings show a magnified UI).
return function(context)
	local root, Clock = context.Root, context.Clock
	local runService, input = game:GetService("RunService"), game:GetService("UserInputService")
	local tweenService, http = game:GetService("TweenService"), game:GetService("HttpService")
	local lighting = game:GetService("Lighting")
	local white, gray, amber, green = Color3.fromRGB(249,249,250), Color3.fromRGB(145,145,149), Color3.fromRGB(255,177,29), Color3.fromRGB(55,224,92)
	local normal = Font.new("rbxasset://fonts/families/GothamSSm.json")
	local medium = Font.new(normal.Family, Enum.FontWeight.Medium)
	local controller = {alive=true, clock=Clock.new(), view=nil, media={connected=false,title="Spotify",artist=""},
		mediaAt=os.clock(), nextPoll=0, failures=0, connections={}, tweens=setmetatable({}, {__mode="k"}),
		lastErrorAt=-math.huge, commandBusy=false, requestBusy=false, picker=false, layoutAt=0}
	local clock = controller.clock
	local function get(name, fallback)
		local value=context.GetSetting and context.GetSetting(name,fallback)
		if value==nil then return fallback end
		return value
	end
	local function connect(signal, fn)
		local connection = signal:Connect(function(...) if controller.alive then fn(...) end end)
		controller.connections[#controller.connections+1] = connection; return connection
	end
	local function make(class, parent, properties)
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
		connect(object.MouseEnter,function() object.TextTransparency=0.12 end)
		connect(object.MouseLeave,function() object.TextTransparency=0 end)
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
	local host=frame(root,"TopCapsules",0,12,300,180)
	host.AnchorPoint,host.Position,host.ZIndex=Vector2.new(0.5,0),UDim2.new(0.5,0,0,12),290
	local scale=make("UIScale",host,{Scale=1})
	local compact=frame(host,"Compact",0,0,300,24)
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
	local outline=sourceStroke and sourceStroke:Clone() or Instance.new("UIStroke")
	outline.Name="CapsuleOutline";outline.Color=white;outline.Transparency=.85;outline.Thickness=1
	outline.Enabled=true;outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;outline.Parent=surface
	local views={}
	local function view(name,w,h)
		local v=make("CanvasGroup",surface,{Name=name,Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,GroupTransparency=1,Visible=false})
		views[name]=v;return v
	end
	local center=view("center",300,146)
	local music=view("music",220,82)
	local timer=view("timer",208,68)
	local watch=view("watch",208,94)
	local sizes={center=Vector2.new(300,146),music=Vector2.new(220,82),timer=Vector2.new(208,68),watch=Vector2.new(208,94)}
	function controller:Open(name)
		if name==self.view then name=nil end
		self.view=name;self.transition=(self.transition or 0)+1
		local transition=self.transition
		compact.Visible=name==nil
		for key,group in pairs(views) do
			if key~=name then group.Visible=false;group.GroupTransparency=1 end
		end
		if not name then
			tween(surface,.25,{Size=UDim2.fromOffset(100,24)})
			task.delay(.26,function() if self.alive and transition==self.transition then surface.Visible=false end end)
		else
			local size=sizes[name]
			surface.Visible=true;views[name].Visible=true;views[name].GroupTransparency=1
			tween(surface,.42,{Size=UDim2.fromOffset(size.X,size.Y+(name=="center" and self.picker and 52 or 0))})
			tween(views[name],.25,{GroupTransparency=0})
		end
		self.layoutAt=0
	end
	local function pill(name,text,width,color,action)
		local p=button(strip,name,text,0,0,width,24,Color3.fromRGB(10,10,11),action)
		p.LayoutOrder=#strip:GetChildren();p.TextSize=10;p.TextColor3=color or white
		return p
	end
	local menuPill=pill("ControlCenter","",24,white,function() controller:Open("center") end)
	frame(menuPill,"ChevronLeft",7,11,6,1,white).Rotation=45
	frame(menuPill,"ChevronRight",11,11,6,1,white).Rotation=-45
	local musicPill=pill("Music","♫  Spotify",84,white,function() controller:Open("music") end)
	local timerPill=pill("Timer","    05:00",58,amber,function() controller:Open("timer") end)
	local watchPill=pill("Stopwatch","    00:00",58,green,function() controller:Open("watch") end)
	for _,spec in ipairs({{timerPill,amber},{watchPill,green}}) do
		local icon=frame(spec[1],"ClockIcon",7,8,8,8)
		corner(icon,4);make("UIStroke",icon,{Color=spec[2],Thickness=1})
		frame(icon,"MinuteHand",4,1,1,3,spec[2]);frame(icon,"HourHand",4,4,2,1,spec[2])
	end
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
		local response=context.Request({Url="http://127.0.0.1:"..port.."/v1/"..path,Method=method,Timeout=3,
			Headers={Authorization="Bearer "..key,["Content-Type"]="application/json"},Body=body and http:JSONEncode(body) or nil})
		assert(type(response)=="table","The Spotify companion did not respond")
		local status=tonumber(response.StatusCode or response.Status) or 0
		local ok,data=pcall(http.JSONDecode,http,response.Body or "")
		assert(ok and type(data)=="table","The companion returned an invalid response")
		assert(status>=200 and status<300,data.error or "Spotify companion request failed")
		return data
	end
	local function accountAction(path,body)
		if controller.commandBusy then return end
		controller.commandBusy=true
		controller.accountGeneration=(controller.accountGeneration or 0)+1
		task.spawn(function()
			local ok,result=pcall(bridgeRequest,"POST",path,body)
			if not controller.alive then return end
			controller.commandBusy=false;controller.nextPoll=0
			if ok then
				if path=="unlink" then controller:SetMedia({connected=false,linked=false,title="Spotify"}) end
				context.Notify("Spotify",path=="unlink" and "Unlinked. Saved account tokens were removed. Use Link Spotify to connect again." or "Finish linking in your browser. Keep the companion running.",nil)
			else notifyError(tostring(result)) end
		end)
	end
	function controller:LinkSpotify()
		accountAction("link",{clientId=tostring(get("Spotify Client ID","")):match("^%s*(.-)%s*$")})
	end
	function controller:UnlinkSpotify() accountAction("unlink",{}) end
	function controller:Control(action,value)
		if not self.media.connected then self:ShowSetup();return false end
		if self.commandBusy then return false end
		if self.media.controls and self.media.controls[action]==false then notifyError("Spotify does not currently support that control.");return false end
		self.commandBusy=true
		task.spawn(function()
			local ok,err=pcall(bridgeRequest,"POST","control",{action=action,value=value})
			if not self.alive then return end
			self.commandBusy=false;self.nextPoll=0
			if not ok then notifyError(tostring(err)) end
		end)
		return true
	end
	function controller:SetMedia(state)
		if type(state)~="table" then return end
		local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
		state.duration=finite(state.duration) and math.clamp(state.duration,0,86400) or 0
		state.progress=finite(state.progress) and math.clamp(state.progress,0,state.duration) or 0
		state.title=tostring(state.title or "Spotify"):sub(1,300)
		state.artist=tostring(state.artist or ""):sub(1,300)
		state.connected=state.connected==true;state.playing=state.playing==true
		self.media,self.mediaAt=state,os.clock()
	end
	local function progress()
		local m=controller.media
		return math.clamp(m.progress or 0,0,m.duration or 0)+(m.playing and math.min(os.clock()-controller.mediaAt,math.max(0,(m.duration or 0)-(m.progress or 0))) or 0)
	end
	local function slider(parent,name,x,y,w,h,color,callback)
		local bar=frame(parent,name,x,y,w,h,Color3.fromRGB(43,43,44),h/2);bar.ClipsDescendants=true
		local fill=frame(bar,"Fill",0,0,0,h,color,h/2)
		local hit=button(bar,"Input","",0,0,w,h,nil,function() end)
		local dragging=false
		local function ratio(position) return math.clamp((position.X-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1) end
		local function move(position,finished)
			local value=ratio(position);fill.Size=UDim2.new(value,0,1,0);callback(value,finished)
		end
		connect(hit.InputBegan,function(event)
			if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then dragging=event;move(event.Position,false) end
		end)
		connect(input.InputChanged,function(event)
			if dragging and (event==dragging or event.UserInputType==Enum.UserInputType.MouseMovement) then move(event.Position,false) end
		end)
		connect(input.InputEnded,function(event)
			if dragging and (event==dragging or event.UserInputType==Enum.UserInputType.MouseButton1) then move(event.Position,true);dragging=false end
		end)
		return {bar=bar,fill=fill,IsDragging=function() return dragging~=false end}
	end
	local playerViews={}
	for _,spec in ipairs({{center,300,true},{music,220,false}}) do
		local group,w,expanded=spec[1],spec[2],spec[3]
		frame(group,"Artwork",11,11,29,29,Color3.fromRGB(34,34,35),7)
		local note=label(group,"Note","♪",11,11,29,29,16,gray);note.TextXAlignment=Enum.TextXAlignment.Center
		local title=label(group,"Title","Connect Spotify",48,13,w-132,13,11,white);title.FontFace=medium
		local artist=label(group,"Artist","Open Settings for setup",48,27,w-132,12,10,gray)
		local previous=button(group,"Previous","◂◂",w-67,17,18,20,nil,function() controller:Control("previous") end);previous.TextSize=10
		local play=button(group,"PlayPause","▶",w-47,15,20,23,nil,function() controller:Control("toggle") end);play.TextSize=17
		local nextButton=button(group,"Next","▸▸",w-25,17,18,20,nil,function() controller:Control("next") end);nextButton.TextSize=10
		local seek=slider(group,"Seek",11,47,w-22,4,white,function(value,finished)
			if finished then controller:Control("seek",value*(controller.media.duration or 0)) end
		end)
		-- A larger invisible hit target retains the thin reference progress bar.
		seek.bar.ClipsDescendants=false
		local seekInput=seek.bar.Input;seekInput.Size=UDim2.new(1,0,0,16);seekInput.Position=UDim2.fromOffset(0,-6)
		local elapsed=label(group,"Elapsed","0:00",11,54,65,12,9,gray)
		local duration=label(group,"Duration","--:--",w-76,54,65,12,9,gray);duration.TextXAlignment=Enum.TextXAlignment.Right
		playerViews[#playerViews+1]={title=title,artist=artist,play=play,seek=seek,elapsed=elapsed,duration=duration}
	end
	local originalBrightness=lighting.Brightness
	local brightnessChanged=false
	local brightness=slider(center,"Brightness",11,71,136,22,white,function(value)
		brightnessChanged=true;lighting.Brightness=value*3
	end)
	label(center,"BrightnessIcon","☀",19,72,22,20,15,Color3.fromRGB(194,148,35))
	brightness.fill.Size=UDim2.fromScale(math.clamp(originalBrightness/3,0,1),1)
	local volume=slider(center,"SpotifyVolume",153,71,136,22,white,function(value,finished)
		if finished then controller:Control("volume",value) end
	end)
	label(center,"VolumeIcon","♫",162,72,20,20,14,gray)
	local timerTile=button(center,"TimerTile","",11,102,136,33,Color3.fromRGB(28,28,29),function()
		if clock.timer then controller:Open("timer") else
			controller.picker=not controller.picker
			tween(surface,.35,{Size=UDim2.fromOffset(300,controller.picker and 198 or 146)})
		end
	end)
	label(timerTile,"Label","Timer",10,3,116,12,9,gray)
	local timerSummary=label(timerTile,"Value","Set",10,15,116,15,12,white);timerSummary.FontFace=medium
	local watchTile=button(center,"WatchTile","",153,102,136,33,Color3.fromRGB(28,28,29),function()
		if not clock.watch.active then clock:ToggleWatch();controller:Open(nil) else controller:Open("watch") end
	end)
	label(watchTile,"Label","Stopwatch",10,3,116,12,9,gray)
	local watchSummary=label(watchTile,"Value","Start",10,15,116,15,12,white);watchSummary.FontFace=medium
	local picker=frame(center,"TimerPicker",11,146,278,44)
	center.Size=UDim2.fromOffset(300,198)
	local timerInput=make("TextBox",picker,{Name="Duration",Text="05:00",PlaceholderText="mm:ss",ClearTextOnFocus=false,
		Position=UDim2.fromOffset(0,4),Size=UDim2.fromOffset(70,30),BackgroundColor3=Color3.fromRGB(28,28,29),
		TextColor3=amber,TextSize=13,FontFace=medium,BorderSizePixel=0})
	corner(timerInput,10)
	for index,minutes in ipairs({5,15,30}) do
		button(picker,"Preset"..minutes,minutes.."m",75+(index-1)*40,4,35,30,Color3.fromRGB(28,28,29),function() timerInput.Text=string.format("%02d:00",minutes) end)
	end
	button(picker,"StartTimer","Start",200,4,78,30,Color3.fromRGB(65,45,7),function()
		local minutes,seconds=timerInput.Text:match("^(%d+):(%d%d?)$")
		local duration=minutes and (tonumber(minutes)*60+tonumber(seconds)) or tonumber(timerInput.Text)
		if not duration or duration<1 or duration>86400 or (seconds and tonumber(seconds)>59) then
			context.Notify("Timer","Enter minutes:seconds, from 00:01 to 1440:00.");return
		end
		clock:StartTimer(duration);controller.picker=false;controller:Open(nil)
	end)
	label(timer,"Title","Timer",11,8,100,12,9,gray)
	local timerTime=label(timer,"Time","05:00",11,22,120,21,18,amber);timerTime.FontFace=medium
	local timerPause=button(timer,"Pause","Ⅱ",153,11,22,22,Color3.fromRGB(65,45,7),function() clock:ToggleTimer() end)
	timerPause.TextColor3=amber;timerPause.TextSize=15
	button(timer,"Cancel","×",179,11,22,22,Color3.fromRGB(35,35,36),function() clock:CancelTimer();controller:Open(nil) end).TextSize=17
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
		local factor=math.clamp(tonumber(get("Capsule Scale",1)) or 1,.65,2)
		factor=math.min(factor,math.max(.45,(viewport.X-24)/300))
		scale.Scale=factor
		local width=(self.view and sizes[self.view].X or 250)*factor
		local height=(self.view and sizes[self.view].Y or 24)*factor
		if self.view=="center" and self.picker then height=198*factor end
		local x,y=viewport.X/2-width/2,12
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
		y=math.clamp(y,12,math.max(12,viewport.Y-height-12))
		self.targetY=y
		set(host,"Visible",get("Capsules Enabled",true)==true)
	end
	local function inside(object,position)
		local p,s=object.AbsolutePosition,object.AbsoluteSize
		return position.X>=p.X and position.X<=p.X+s.X and position.Y>=p.Y and position.Y<=p.Y+s.Y
	end
	connect(input.InputBegan,function(event)
		if controller.view and (event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch)
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
		if now>=controller.layoutAt then controller.layoutAt=now+.1;controller:Layout() end
		local y=host.Position.Y.Offset
		if controller.targetY and math.abs(y-controller.targetY)>.1 then
			host.Position=UDim2.new(.5,0,0,y+(controller.targetY-y)*(1-math.exp(-18*dt)))
		end
		if get("Spotify Connection",false) and now>=controller.nextPoll and not controller.requestBusy then
			controller.requestBusy=true;controller.nextPoll=now+1.5
			task.spawn(function()
				local generation=controller.accountGeneration
				local ok,state=pcall(bridgeRequest,"GET","state")
				if not controller.alive then return end
				controller.requestBusy=false
				if generation~=controller.accountGeneration or not get("Spotify Connection",false) then return end
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
		if renderAccumulator<.04 or not host.Visible then return end
		renderAccumulator=0
		if surface.Visible then
			local rainbow=get("Rainbow Mode",false)==true
			local accent=rainbow and ((context.GetRainbowColor and context.GetRainbowColor()) or Color3.fromHSV((os.clock()/8)%1,.65,.8)) or white
			set(outline,"Color",accent)
		end
		local remaining,elapsed=clock:Remaining(),clock:Elapsed()
		set(timerPill,"Visible",clock.timer~=nil);set(watchPill,"Visible",clock.watch.active)
		set(musicPill,"Text","♫  "..(controller.media.connected and controller.media.title or "Spotify"))
		set(timerPill,"Text","    "..Clock.Format(remaining,false,true));set(watchPill,"Text","    "..Clock.Format(elapsed))
		if controller.view=="timer" then
			set(timerTime,"Text",Clock.Format(remaining,false,true))
			set(timerPause,"Text",clock.timer and clock.timer.started and "Ⅱ" or "▶")
			set(timerTime,"TextTransparency",clock.timer and not clock.timer.started and .25 or 0)
			rulerStrip.Position=UDim2.fromOffset(-((remaining%1)*3.7),0)
		elseif controller.view=="watch" then
			set(watchTime,"Text",Clock.Format(elapsed));set(fraction,"Text",string.format(".%02d",math.floor((elapsed%1)*100)))
			fraction.Position=UDim2.fromOffset(watchTime.TextBounds.X+12,27)
			set(watchPause,"Text",clock.watch.started and "Ⅱ" or "▶");set(lapButton,"Text",clock.watch.started and "Lap" or "Reset")
			local laps=clock.watch.laps;lapEmpty.Visible=#laps==0
			local maximum=math.max(.01,elapsed-clock.watch.splitAt)
			for _,lap in ipairs(laps) do maximum=math.max(maximum,lap.seconds) end
			for index,row in ipairs(lapRows) do
				row.root.Visible=#laps>0
				local lap=index==1 and {number=(clock.watch.lapCount or 0)+1,seconds=elapsed-clock.watch.splitAt} or laps[#laps-index+2]
				if lap and row.root.Visible then
					set(row.title,"Text","Lap "..lap.number);set(row.value,"Text",Clock.Format(lap.seconds,true))
					row.bar.Size=UDim2.fromOffset(math.clamp(lap.seconds/maximum,0,1)*92,4)
				else row.root.Visible=false end
			end
		elseif controller.view=="music" or controller.view=="center" then
			local m=controller.media
			for _,player in ipairs(playerViews) do
				set(player.title,"Text",m.connected and m.title or "Connect Spotify")
				set(player.artist,"Text",m.connected and m.artist or "Settings → Capsules & Spotify")
				set(player.play,"Text",m.playing and "Ⅱ" or "▶")
				set(player.elapsed,"Text",Clock.Format(progress()):gsub("^0([0-9]):","%1:"))
				set(player.duration,"Text",(m.duration or 0)>0 and Clock.Format(m.duration):gsub("^0([0-9]):","%1:") or "--:--")
				if not player.seek.IsDragging() then player.seek.fill.Size=UDim2.fromScale((m.duration or 0)>0 and progress()/m.duration or 0,1) end
			end
			set(timerSummary,"Text",clock.timer and Clock.Format(remaining,false,true) or "Set")
			set(watchSummary,"Text",clock.watch.active and Clock.Format(elapsed) or "Start")
			if not volume.IsDragging() then volume.fill.Size=UDim2.fromScale(math.clamp(tonumber(m.volume) or 0,0,1),1) end
		end
	end)
	function controller:Destroy()
		if not self.alive then return end
		self.alive=false
		for _,connection in ipairs(self.connections) do connection:Disconnect() end
		for _,animation in pairs(self.tweens) do animation:Cancel() end
		if brightnessChanged then lighting.Brightness=originalBrightness end
		host:Destroy();table.clear(self.connections)
	end
	connect(root.Destroying,function() controller:Destroy() end)
	controller:Layout()
	return controller
end
