-- Studio client tests use simulated media and never authorize an account.
return function()
	local root,bindings=require(script.Parent.Parent.Parent.Build)()
	root.Name="AltairCapsuleValidation";root.Enabled=true
	root.Parent=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	for _,child in root:GetChildren() do
		if child:IsA("GuiObject") and child.Name~="TopCapsules" and child.Name~="NotificationCapsules" then child.Visible=false end
	end
	local notifications,controller
	local checks=0
	local function expect(condition,message) checks+=1;assert(condition,message) end
	local ok,result=pcall(function()
		local settings={['Capsules Enabled']=true,['Spotify Connection']=true,['Spotify Client ID']=string.rep('a',32)}
		local linked=false
		local media={connected=false,title='Simulated test track',artist='Validation only',duration=100,progress=5,playing=true,volume=.8}
		local commands={};local session={}
		notifications=bindings.Notifications({Root=root,RequireBuiltUI=true})
		controller=bindings.Capsules({Root=root,RequireBuiltUI=true,Clock=bindings.Clock,Session=session,
			GetSetting=function(name,fallback) local value=settings[name];if value==nil then return fallback end;return value end,
			Notify=function(...) return notifications:Notify(...) end,Notifications=notifications,
			MediaAdapter=function(_,path,body)
				if path=='link' then expect(body.clientId==string.rep('a',32),'Client ID was not passed');linked=true;media.connected=true
				elseif path=='unlink' then linked=false;media.connected=false
				elseif path=='control' then
					task.wait(.04);commands[#commands+1]=body
					if body.action=='toggle' then media.playing=not media.playing
					elseif body.action=='seek' then media.progress=body.value
					elseif body.action=='volume' then media.volume=body.value end
				else return table.clone(media) end
				return {ok=true}
			end})
		expect(root:GetAttribute('AltairCapsuleSchema')==2,'UI was not constructed by Build.lua')
		expect(root.TopCapsules.Compact.Pills.Music.Visual.Note:IsA('ImageLabel'),'Music fallback is not a Lucide image asset')
		expect(root.TopCapsules.Surface.center.Next.Glyph.Skip:IsA('ImageLabel'),'Playback icon is not a Lucide image asset')
		settings['Capsule Scale']=3;controller:Layout()
		expect(root.TopCapsules.UIScale.Scale<=1.25,'Saved oversized default was not migrated')
		settings['Capsule Scale']=nil
		settings['Capsules Enabled']=false;controller:Layout();expect(not root.TopCapsules.Visible,'Capsules could not be hidden')
		settings['Capsules Enabled']=true;controller:Layout();expect(root.TopCapsules.Visible,'Capsules could not be shown')
		controller:LinkSpotify();task.wait(.15);controller.nextPoll=0;task.wait(.25)
		expect(linked and controller.media.connected,'Link did not refresh playback')
		local originalTitle=media.title
		media.title='The Other Side of Paradise (Live at Alexandra Palace - Extended Version)'
		controller:SetMedia(media);task.wait(.6)
		local musicPill=root.TopCapsules.Compact.Pills.Music
		local title=musicPill.Visual.Title
		expect(musicPill.Size.X.Offset>110,'Song title retained the old width cap')
		expect(title.TextBounds.X<=title.AbsoluteSize.X+1,'Full song title was clipped')
		local expandedWidth=musicPill.Size.X.Offset
		media.title=originalTitle;controller:SetMedia(media);task.wait(.6)
		expect(musicPill.Size.X.Offset<expandedWidth,'Shorter song title did not shrink the pill')
		controller:Open('music');task.wait(.45)
		controller:Open('music');expect(controller.view=='music','Repeated hover unexpectedly collapsed the panel')
		controller:BeginTimerEntry();controller:SetTimerDraft(90)
		controller:Open(nil);expect(controller.picker and controller.view=='duration','Entry collapsed while editing')
		controller:EndTimerEntry(true);expect(controller.clock.timer.duration==90,'Picker did not start the draft duration')
		controller.clock:CancelTimer()
		media.playing=false;controller:SetMedia(media);task.wait(.12)
		expect(root.TopCapsules.Compact.Pills.Music.Visible,'Spotify disappeared before exit animation')
		task.wait(.45)
		expect(not root.TopCapsules.Compact.Pills.Music.Visible,'Idle Spotify pill remained visible')
		media.playing=true;controller:SetMedia(media);task.wait(.15)
		expect(root.TopCapsules.Compact.Pills.Music.Visible,'Playing Spotify pill did not return')
		media.playing=false;controller:SetMedia(media);task.wait(.12)
		media.playing=true;controller:SetMedia(media);task.wait(.65)
		expect(root.TopCapsules.Compact.Pills.Music.Visible,'Interrupted exit hid resumed playback')
		expect(root.TopCapsules.Compact.Pills.Music.Visual.GroupTransparency==0,'Resumed pill retained exit fade')
		controller:Open('music');task.wait(.45)
		local surface=root.TopCapsules.Surface
		expect(surface.music.Title.Text=='Simulated test track','Music did not render')
		expect(surface.BackgroundTransparency<.1 and math.abs(surface.CapsuleOutline.Transparency-.45)<.00001,'Expanded finish changed')
		settings['Rainbow Mode']=true;task.wait(.1)
		expect(surface.CapsuleOutline.Color~=Color3.fromRGB(249,249,250),'Rainbow did not color the outline')
		settings['Rainbow Mode']=false;task.wait(.1)
		expect(surface.CapsuleOutline.Color==Color3.fromRGB(249,249,250),'Rainbow did not restore the neutral outline')
		expect(controller:Control('toggle'),'Toggle was rejected')
		expect(controller:Control('seek',80),'Seek was dropped behind an in-flight command')
		expect(controller:Control('seek',90),'Latest seek was dropped')
		expect(controller:Control('volume',.4),'Volume was dropped behind seek')
		task.wait(.3)
		expect(#commands==3 and commands[2].action=='seek' and commands[2].value==90,'Seeks were not serialized and coalesced')
		expect(media.volume==.4 and media.progress==90,'Commands did not update playback')
		controller:UnlinkSpotify();task.wait(.1)
		expect(linked and root.SpotifyUnlinkConfirmation.Visible,'Unlink bypassed confirmation')
		controller:ResolveSpotifyDisconnect(false);expect(linked,'Cancel unlinked the account')
		controller:UnlinkSpotify();controller:ResolveSpotifyDisconnect(true);task.wait(.1)
		expect(not linked and not controller.media.connected,'Unlink retained account state')
		expect(session.media.linked==false,'Unlink left a linked rerun snapshot')
		controller:LinkSpotify();task.wait(.1);expect(linked,'Relink failed')
		controller:Open(nil)
		local bar=root.SmartBar
		bar.Size=UDim2.fromOffset(300,50);bar.AnchorPoint=Vector2.new(.5,0);bar.Position=UDim2.fromScale(.5,0);bar.Visible=true
		task.wait(.2);controller:Layout();expect(controller.targetY>=58,'Capsules did not avoid the top bar')
		local single=notifications:Notify('Settings saved','',nil,{Duration=3});task.wait(.3)
		local found
		for _,group in root.NotificationCapsules:GetChildren() do
			if group:IsA('CanvasGroup') and group.Name~='CardTemplate' and group.Title.Text=='Settings saved' then
				found=true;expect(group.Size.Y.Offset==44,'Single-line notification height changed')
			end
		end
		expect(found,'Notification did not render');single.Dismiss()
		for _,record in ipairs(table.clone(notifications.active)) do notifications:Dismiss(record) end
		table.clear(notifications.pending);task.wait(.25)
		notifications:Notify('Settings saved','',nil,{Key='settings-update',Duration=3})
		notifications:Notify('Settings saved','',nil,{Key='settings-update',Duration=3})
		task.wait(.35)
		expect(#notifications.active==1,'Repeated settings confirmations did not coalesce')
		expect(notifications.active[1].height==44,'Compact settings confirmation changed height')
		notifications:Notify('Friend joined','jenson has joined your server.',4370335364,{Duration=5})
		notifications:Notify('Staff in your server',"An administrator from this experience's group has just joined. They can see what you do in game.",3944670656,{Duration=5})
		bar.AnchorPoint=Vector2.zero;bar.Size=UDim2.fromOffset(300,50);bar.Position=UDim2.new(1,-324,1,-74)
		task.wait(.6)
		expect(#notifications.active==3,'Reference notification stack did not render')
		expect(notifications.active[3].height>notifications.active[2].height,'Multiline notification did not grow with its content')
		local last=notifications.active[3].group
		expect(last.AbsolutePosition.Y+last.AbsoluteSize.Y<=bar.AbsolutePosition.Y-6,'Notifications covered the bottom SmartBar')
		bar.Position=UDim2.new(1,-324,0,24);task.wait(.6)
		expect(notifications.active[1].group.AbsolutePosition.Y>=bar.AbsolutePosition.Y+bar.AbsoluteSize.Y+6,'Notifications did not follow the bar to the top')
		local cachedTitle=controller.media.title
		controller:UnlinkSpotify();controller:Destroy()
		expect(linked,'UI teardown unlinked Spotify')
		expect(not controller:ResolveSpotifyDisconnect(true),'Destroyed UI accepted a pending confirmation')
		expect(not controller.alive and #controller.connections==0,'Capsule connections leaked on unload')
		local nextRoot,nextBindings=require(script.Parent.Parent.Parent.Build)()
		local nextController
		local resumed,problem=pcall(function()
			nextController=nextBindings.Capsules({Root=nextRoot,RequireBuiltUI=true,Clock=nextBindings.Clock,Session=session,
				GetSetting=function(name,fallback)if name=='Spotify Connection'then return true end;return fallback end,Notify=function()end,MediaAdapter=function()return table.clone(media)end})
			expect(nextController.media.connected and nextController.media.title==cachedTitle,'Rerun lost the saved playback snapshot')
			local paused=false
			nextController:ConfirmSpotifyDisconnect(function()paused=true end,true)
			nextController:ResolveSpotifyDisconnect(false);expect(not paused,'Cancel paused the connection')
			nextController:ConfirmSpotifyDisconnect(function()paused=true end,true)
			nextController:ResolveSpotifyDisconnect(true);expect(paused,'Confirmed pause was not applied')
			nextController:Destroy();nextRoot:Destroy()
			nextRoot,nextBindings=require(script.Parent.Parent.Parent.Build)()
			nextController=nextBindings.Capsules({Root=nextRoot,RequireBuiltUI=true,Clock=nextBindings.Clock,Session=session,
				GetSetting=function(_,fallback)return fallback end,Notify=function()end,MediaAdapter=function()return table.clone(media)end})
			expect(not nextController.media.connected,'Rerun ignored an explicitly paused connection')
		end)
		if nextController then nextController:Destroy() end;nextRoot:Destroy()
		if not resumed then error(problem,0) end
		return {passed=true,checks=checks,accountLinked=false}
	end)
	if controller then controller:Destroy() end
	if notifications then notifications:Destroy() end
	root:Destroy()
	if not ok then error(result,0) end
	return result
end
