--!nocheck
-- Studio regression check: require(UI.Validate)(require(UI.Build), originalScreenGui).
-- The reference is read only. Every test-created instance is destroyed before returning.
local properties = {
	Frame = {"Active","AnchorPoint","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClipsDescendants","Draggable","Interactable","LayoutOrder","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","Position","RootLocalizationTable","Rotation","Selectable","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","Style","Visible","ZIndex"},
	ImageButton = {"Active","AnchorPoint","AutoButtonColor","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClipsDescendants","Draggable","HoverHapticEffect","HoverImage","Image","ImageColor3","ImageRectOffset","ImageRectSize","ImageTransparency","Interactable","LayoutOrder","Modal","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","Position","PressHapticEffect","PressedImage","ResampleMode","RootLocalizationTable","Rotation","ScaleType","Selectable","Selected","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","SliceCenter","SliceScale","Style","TileSize","Visible","ZIndex"},
	ImageLabel = {"Active","AnchorPoint","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClipsDescendants","Draggable","Image","ImageColor3","ImageRectOffset","ImageRectSize","ImageTransparency","Interactable","LayoutOrder","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","Position","ResampleMode","RootLocalizationTable","Rotation","ScaleType","Selectable","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","SliceCenter","SliceScale","TileSize","Visible","ZIndex"},
	ScreenGui = {"AutoLocalize","ClipToDeviceSafeArea","DisplayOrder","Enabled","ResetOnSpawn","RootLocalizationTable","SafeAreaCompatibility","ScreenInsets","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","ZIndexBehavior"},
	ScrollingFrame = {"Active","AnchorPoint","AutoLocalize","AutomaticCanvasSize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","BottomImage","CanvasPosition","CanvasSize","ClipsDescendants","Draggable","ElasticBehavior","HorizontalScrollBarInset","Interactable","LayoutOrder","MidImage","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","Position","RootLocalizationTable","Rotation","ScrollBarImageColor3","ScrollBarImageTransparency","ScrollBarThickness","ScrollingDirection","ScrollingEnabled","Selectable","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","TopImage","VerticalScrollBarInset","VerticalScrollBarPosition","Visible","ZIndex"},
	TextBox = {"Active","AnchorPoint","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClearTextOnFocus","ClipsDescendants","Draggable","FontFace","Interactable","LayoutOrder","LineHeight","MaxVisibleGraphemes","MultiLine","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","OpenTypeFeatures","PlaceholderColor3","PlaceholderText","Position","RichText","RootLocalizationTable","Rotation","Selectable","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","ShowNativeInput","Size","SizeConstraint","Text","TextColor3","TextDirection","TextEditable","TextScaled","TextSize","TextStrokeColor3","TextStrokeTransparency","TextTransparency","TextTruncate","TextWrapped","TextXAlignment","TextYAlignment","Visible","ZIndex"},
	TextButton = {"Active","AnchorPoint","AutoButtonColor","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClipsDescendants","Draggable","FontFace","HoverHapticEffect","Interactable","LayoutOrder","LineHeight","MaxVisibleGraphemes","Modal","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","OpenTypeFeatures","Position","PressHapticEffect","RichText","RootLocalizationTable","Rotation","Selectable","Selected","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","Style","Text","TextColor3","TextDirection","TextScaled","TextSize","TextStrokeColor3","TextStrokeTransparency","TextTransparency","TextTruncate","TextWrapped","TextXAlignment","TextYAlignment","Visible","ZIndex"},
	TextLabel = {"Active","AnchorPoint","AutoLocalize","AutomaticSize","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderMode","BorderSizePixel","ClipsDescendants","Draggable","FontFace","Interactable","LayoutOrder","LineHeight","MaxVisibleGraphemes","NextSelectionDown","NextSelectionLeft","NextSelectionRight","NextSelectionUp","OpenTypeFeatures","Position","RichText","RootLocalizationTable","Rotation","Selectable","SelectionBehaviorDown","SelectionBehaviorLeft","SelectionBehaviorRight","SelectionBehaviorUp","SelectionGroup","SelectionImageObject","SelectionOrder","Size","SizeConstraint","Text","TextColor3","TextDirection","TextScaled","TextSize","TextStrokeColor3","TextStrokeTransparency","TextTransparency","TextTruncate","TextWrapped","TextXAlignment","TextYAlignment","Visible","ZIndex"},
	UIAspectRatioConstraint = {"AspectRatio","AspectType","DominantAxis"},
	UICorner = {"BottomLeftRadius","BottomRightRadius","TopLeftRadius","TopRightRadius"},
	UIGradient = {"Color","Enabled","Offset","Rotation","Scale","TileMode","Transparency","Type"},
	UIGridLayout = {"CellPadding","CellSize","FillDirection","FillDirectionMaxCells","HorizontalAlignment","SortOrder","StartCorner","VerticalAlignment"},
	UIListLayout = {"FillDirection","HorizontalAlignment","HorizontalFlex","ItemLineAlignment","Padding","SortOrder","VerticalAlignment","VerticalFlex","Wraps"},
	UIPadding = {"PaddingBottom","PaddingLeft","PaddingRight","PaddingTop"},
	UIPageLayout = {"Animated","Circular","EasingDirection","EasingStyle","FillDirection","GamepadInputEnabled","HorizontalAlignment","Padding","ScrollWheelInputEnabled","SortOrder","TouchInputEnabled","TweenTime","VerticalAlignment"},
	UIStroke = {"ApplyStrokeMode","BorderOffset","BorderStrokePosition","Color","Enabled","LineJoinMode","StrokeSizingMode","Thickness","Transparency","ZIndex"},
}

local function equal(a, b)
	if typeof(a) ~= typeof(b) then return false end
	local kind = typeof(a)
	if kind == "number" then return math.abs(a - b) <= 0.00001 * math.max(1, math.abs(a), math.abs(b)) end
	if kind == "Color3" then return equal(a.R,b.R) and equal(a.G,b.G) and equal(a.B,b.B) end
	if kind == "Vector2" then return equal(a.X,b.X) and equal(a.Y,b.Y) end
	if kind == "UDim" then return equal(a.Scale,b.Scale) and a.Offset == b.Offset end
	if kind == "UDim2" then return equal(a.X,b.X) and equal(a.Y,b.Y) end
	if kind == "Rect" then return equal(a.Min,b.Min) and equal(a.Max,b.Max) end
	if kind == "Font" then return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style end
	if kind == "NumberSequence" or kind == "ColorSequence" then
		local x,y = a.Keypoints,b.Keypoints
		if #x ~= #y then return false end
		for index,point in ipairs(x) do
			if not equal(point.Time,y[index].Time) or not equal(point.Value,y[index].Value) then return false end
			if kind == "NumberSequence" and not equal(point.Envelope,y[index].Envelope) then return false end
		end
		return true
	end
	return a == b
end

return function(build, reference)
	assert(type(build) == "function", "Expected the UI builder factory")
	assert(reference and reference:IsA("ScreenGui"), "Expected the original Studio ScreenGui")
	local created = {}
	local ok, report = pcall(function()
		local started = os.clock()
		local actual = build()
		created[#created+1] = actual
		local firstBuildMs = (os.clock() - started) * 1000
		assert(actual.Parent == nil and actual.Enabled == false, "Builder must return an unmounted, disabled root")
		local failures, objectCount, propertyCount, attributeCount = {},0,0,0
		local function fail(message)
			if #failures < 100 then failures[#failures+1] = message end
		end
		local function compare(expected, result, path)
			objectCount += 1
			if expected.ClassName ~= result.ClassName or expected.Name ~= result.Name then
				fail(path .. ": name/class mismatch")
				return
			end
			for _,property in ipairs(properties[expected.ClassName]) do
				if not (expected == reference and property == "Enabled") then
					propertyCount += 1
					if not equal(expected[property],result[property]) then
						fail(path .. "." .. property .. ": " .. tostring(expected[property]) .. " ~= " .. tostring(result[property]))
					end
				end
			end
			local attributes = expected:GetAttributes()
			for name,v in pairs(attributes) do
				attributeCount += 1
				if not equal(v,result:GetAttribute(name)) then fail(path .. " attribute " .. name) end
			end
			for name in pairs(result:GetAttributes()) do
				if attributes[name] == nil and not (expected==reference and name=="AltairCapsuleSchema") then fail(path .. " extra attribute " .. name) end
			end
			local children, resultChildren = expected:GetChildren(), result:GetChildren()
			if expected==reference and not expected:FindFirstChild("TopCapsules") then
				local originalChildren={}
				for _,child in ipairs(resultChildren) do
					if child.Name~="TopCapsules" and child.Name~="NotificationCapsules" then originalChildren[#originalChildren+1]=child end
				end
				resultChildren=originalChildren
			end
			if #children ~= #resultChildren then fail(path .. ": child count mismatch") end
			for index,child in ipairs(children) do
				if resultChildren[index] then compare(child,resultChildren[index],path .. "." .. child.Name .. "[" .. index .. "]") end
			end
		end
		compare(reference,actual,reference.Name)
		-- Two independent builds must not share Instances or mutable attributes.
		local second = build()
		created[#created+1] = second
		assert(second ~= actual and second:GetChildren()[1] ~= actual:GetChildren()[1], "Builder reused Instances")
		actual:SetAttribute("__ValidationIsolation", true)
		assert(second:GetAttribute("__ValidationIsolation") == nil, "Builder shared mutable state")
		local timings = {}
		for index = 1,5 do
			local begin = os.clock()
			local sample = build()
			timings[index] = (os.clock() - begin) * 1000
			sample:Destroy()
		end
		table.sort(timings)
		return {passed=#failures==0, objects=objectCount, properties=propertyCount, attributes=attributeCount,
			firstBuildMs=firstBuildMs, medianBuildMs=timings[3], failures=failures}
	end)
	for _,root in ipairs(created) do root:Destroy() end
	if not ok then error(report,2) end
	return report
end
