-- Run against an initialized Altair API in a Roblox client.
return function(api)
	assert(api and api.GetUI and api.OpenPanel,"Initialize Altair first")
	local panel=api.GetUI().Playerlist
	local subtitle=assert(panel:FindFirstChild("Subtitle"),"Player-list subtitle missing")
	local checks=0
	local function expect(condition,message) checks+=1;assert(condition,message) end
	api.OpenSmartBar();task.wait(.7)
	if panel.Visible then api.ClosePanel("Playerlist");task.wait(.6) end
	for pass=1,2 do
		task.defer(api.OpenPanel,"Playerlist");task.wait(.08)
		expect(subtitle.TextTransparency>.98,"Subtitle flashed before panel entrance on pass "..pass)
		task.wait(.7)
		expect(panel.Visible and subtitle.TextTransparency<.4,"Subtitle did not fade in on pass "..pass)
		task.defer(api.ClosePanel,"Playerlist");task.wait(.25)
		expect(subtitle.TextTransparency>.99,"Subtitle remained visible while closing on pass "..pass)
		task.wait(.5)
		expect(not panel.Visible,"Player list did not finish closing")
	end
	local root=api.GetUI()
	for _,delay in ipairs({.12,.46,.52}) do
		api.OpenSmartBar();task.wait(.7)
		task.defer(api.OpenPanel,"Playerlist");task.wait(delay)
		api.CloseSmartBar()
		if type(getconnections)=="function" then
			for _,signal in ipairs({root.Drag.Interact.MouseEnter,root.Drag.Interact.MouseLeave}) do
				for _,connection in ipairs(getconnections(signal)) do
					if type(connection.Function)=="function" then task.defer(connection.Function) end
				end
			end
		end
		task.wait(.35)
		expect(panel.Subtitle.TextTransparency>.99,"Interrupted entrance revived subtitle")
		local strokes=0
		for _,row in ipairs(panel.Interactions.List:GetChildren()) do
			if row:GetAttribute("AltairRuntimePlayer")==true then
				for _,object in ipairs(row:GetDescendants()) do
					if object:IsA("UIStroke") and object.Enabled and object.Transparency<.98 then strokes+=1 end
				end
			end
		end
		expect(strokes==0,"Interrupted entrance revived player outlines")
		task.wait(.45)
		expect(not panel.Visible and not root.SmartBar.Visible,"Combined close did not finish")
		local line=root.Drag:FindFirstChild("Drag") or root.Drag
		local bar=root.SmartBar
		local upper=bar.AbsolutePosition.Y+bar.AbsoluteSize.Y/2<root.AbsolutePosition.Y+root.AbsoluteSize.Y/2
		local actual=upper and line.AbsolutePosition.Y or line.AbsolutePosition.Y+line.AbsoluteSize.Y
		local target=upper and bar.AbsolutePosition.Y or bar.AbsolutePosition.Y+bar.AbsoluteSize.Y
		expect(math.abs(actual-target)<2,"Hover resizing stopped drag-bar docking")
	end
	return {passed=true,checks=checks}
end
