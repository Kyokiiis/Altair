-- Studio client test. Uses a simulated media adapter; never links a real account.
return function()
	local root=Instance.new("ScreenGui")
	root.Name="AltairCapsuleValidation";root.IgnoreGuiInset=true
	root.Parent=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local notifications,controller
	local ok,result=pcall(function()
		local settings={['Capsules Enabled']=true,['Spotify Connection']=true,['Spotify Client ID']=string.rep('a',32)}
		local linked,commands=false,{}
		notifications=require(script.Parent.Notifications)({Root=root})
		controller=require(script.Parent.Capsules)({Root=root,Clock=require(script.Parent.Clock),
			GetSetting=function(name,fallback) local v=settings[name];if v==nil then return fallback end;return v end,
			Notify=function(...) return notifications:Notify(...) end,Notifications=notifications,
			MediaAdapter=function(method,path,body)
				commands[#commands+1]=path
				if path=='link' then assert(body.clientId==string.rep('a',32));linked=true;return {ok=true}
				elseif path=='unlink' then linked=false;return {ok=true}
				elseif path=='control' then assert(body.action=='toggle');return {ok=true} end
				return {connected=linked,linked=linked,title='Simulated test track',artist='Validation only',duration=100,progress=5,playing=true}
			end})
		settings['Capsules Enabled']=false;controller:Layout();assert(not root.TopCapsules.Visible)
		settings['Capsules Enabled']=true;controller:Layout();assert(root.TopCapsules.Visible)
		controller:LinkSpotify();task.wait(.15);controller.nextPoll=0;task.wait(.25)
		assert(linked and controller.media.connected,'Simulated link failed')
		controller:Open('music');task.wait(.1)
		assert(root.TopCapsules.Surface.music.Title.Text=='Simulated test track','Music did not render')
		local surface=root.TopCapsules.Surface
		assert(surface.BackgroundTransparency<.1 and math.abs(surface.CapsuleOutline.Transparency-.85)<.00001,'Expanded SmartBar finish changed')
		settings['Rainbow Mode']=true;task.wait(.1)
		assert(surface.CapsuleOutline.Color~=Color3.fromRGB(249,249,250),'Rainbow did not tint the expanded outline')
		settings['Rainbow Mode']=false;task.wait(.1)
		assert(surface.CapsuleOutline.Color==Color3.fromRGB(249,249,250),'Disabling rainbow did not restore the outline')
		assert(controller:Control('toggle'));task.wait(.1)
		assert(table.find(commands,'control'),'Playback command was not sent')
		controller:UnlinkSpotify();task.wait(.1)
		assert(not linked and not controller.media.connected,'Unlink retained account state')
		controller:LinkSpotify();task.wait(.1);assert(linked,'Relink failed')
		controller:Open(nil)
		local bar=Instance.new('Frame')
		bar.Name='SmartBar';bar.Size=UDim2.fromOffset(300,50);bar.AnchorPoint=Vector2.new(.5,0)
		bar.Position=UDim2.fromScale(.5,0);bar.Parent=root
		-- A second controller discovers the test obstacle during construction.
		controller:Destroy()
		controller=require(script.Parent.Capsules)({Root=root,Clock=require(script.Parent.Clock),Notifications=notifications,
			Notify=function(...) return notifications:Notify(...) end})
		task.wait(.2);controller:Layout();assert(controller.targetY>=58,'Capsules failed top avoidance')
		local single=notifications:Notify('Settings saved','',nil,{Duration=3})
		task.wait(.3)
		local found
		for _,group in ipairs(root.NotificationCapsules:GetChildren()) do
			if group:IsA('CanvasGroup') and group.Title.Text=='Settings saved' then
				found=true;assert(group.Size.Y.Offset==44,'Single-line notification height changed')
			end
		end
		assert(found,'Notification did not render');single.Dismiss()
		return {passed=true,checks=12,accountLinked=false}
	end)
	if controller then controller:Destroy() end
	if notifications then notifications:Destroy() end
	root:Destroy()
	if not ok then error(result,0) end
	return result
end
