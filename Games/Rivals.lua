-- Altair Rivals 1.2.0 | Run this complete file.
-- The readable source below is passed to itself to resume across match teleports.
local source = [======[
-- Altair Rivals | Rayfield Gen2
-- Original implementation. Research and validation: Rivals_RESEARCH.md.
-- RIVALS: universe 6035872082, root place 17625359962.
-- Runtime assumptions are exposed in Diagnostics; no third-party gameplay loader.

if not game:IsLoaded() then game.Loaded:Wait() end

if game.GameId ~= 6035872082 and game.PlaceId ~= 17625359962 then
	warn("Altair Rivals | This module is for RIVALS.")
	return
end

local moduleSource, queuedResume = ...
if not game:IsLoaded() then game.Loaded:Wait() end
local env = type(getgenv) == "function" and getgenv() or _G
local Teleport = game:GetService("TeleportService")
local resumeKey = "Altair.Rivals.v1"
local resumeOK, resume = pcall(Teleport.GetTeleportSetting, Teleport, resumeKey)
local continuing = resumeOK and type(resume) == "table" and resume.active == true
	and resume.universe == game.GameId and type(resume.fromJob) == "string" and resume.fromJob ~= game.JobId
	and type(resume.at) == "number" and os.time() - resume.at >= 0 and os.time() - resume.at < 600
if queuedResume and not continuing then return end
local previous = env.AltairRivals
-- Claim the destination before the UI download can yield. Autoexecute and queued
-- continuation may arrive in either order; both must share the same instance.
if continuing and type(previous) == "table" and previous.JobId == game.JobId then return previous end
if type(previous) == "table" and type(previous.Unload) == "function" then
	pcall(previous.Unload)
end
if continuing then pcall(Teleport.SetTeleportSetting, Teleport, resumeKey, resume) end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local cfg = {
	aim = false, aimMode = "Hold", aimKey = Enum.UserInputType.MouseButton2,
	method = "Mouse", part = "Head", priority = "Crosshair", sticky = true,
	fov = 140, smooth = 30, turnRate = 240, distance = 1000,
	visible = true, teams = true, sameArena = true, unassigned = false,
	pauseMenu = true, killDelay = 200, lead = 0,
	trigger = false, triggerMode = "Click", reaction = 80, refire = 120, hold = 100,
	headOnly = false, triggerDistance = 600, triggerWithAimKey = false,
	esp = false, boxes = true, names = true, health = true, ranges = true,
	chams = false, throughWalls = true, espDistance = 1500, espRate = 30,
	espTeam = false, arrows = true, circle = true, crosshair = false,
	enemyColor = Color3.fromRGB(231, 124, 137), targetColor = Color3.fromRGB(115, 200, 255),
	allyColor = Color3.fromRGB(128, 213, 173), fill = 80,
	theme = "cobalt", panicKey = Enum.KeyCode.F1,
	antiKatana = false, tracers = false, weaponLabels = false, pauseRound = true,
	speed = false, speedPercent = 135, infiniteJump = false, noclip = false,
	silent = false, silentChance = 100,
}
local state = {
	alive = true, ready = false, focused = true, connections = {}, overlays = {},
	window = nil, target = nil, pending = nil, release = nil, releaseAt = 0,
	nextShot = 0, killUntil = 0, inputCount = 0, frames = 0, elapsed = 0,
	fps = 0, status = "Starting", teamStatus = "Waiting", weapon = "Unavailable",
	ammo = nil, item = nil, lastError = "None", errors = 0, lastErrorAt = 0,
	residual = Vector2.zero, lastCamera = camera, lastHealth = nil,
}
state.collisions = {}
state.aimPath = "idle"
state.weaponSource = "Unavailable"
local controls = {}
local api = { JobId = game.JobId }
env.AltairRivals = api

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(state.connections, connection)
	return connection
end

local function notify(message)
	local altair = env.Altair
	if type(altair) == "table" and type(altair.Toast) == "function" then
		local ok = pcall(altair.Toast, message)
		if ok then return end
	end
	if state.window and not state.window.unloaded then
		pcall(function() state.window:Notify({ title = "Rivals", content = message, duration = 5 }) end)
	else
		warn("Altair Rivals | " .. message)
	end
end

local function releaseTrigger()
	local release = state.release
	state.release = nil
	state.releaseAt = 0
	if release then pcall(release) end
end

local function cancelCombat()
	state.target = nil
	state.pending = nil
	state.lastHealth = nil
	state.residual = Vector2.zero
	releaseTrigger()
end

function api.Unload()
	if not state.alive then return end
	state.alive = false
	if state.restoreSilent then state.restoreSilent() end
	if env.AltairRivals == api then pcall(Teleport.SetTeleportSetting, Teleport, resumeKey, false) end
	if state.restoreMovement then state.restoreMovement() end
	if state.debugClient then pcall(state.debugClient.Detach, state.debugClient, "rivals-unloaded") end
	cancelCombat()
	RunService:UnbindFromRenderStep("AltairRivals")
	for _, connection in ipairs(state.connections) do connection:Disconnect() end
	table.clear(state.connections)
	if state.gui then state.gui:Destroy() end
	if state.highlights then state.highlights:Destroy() end
	if state.window and not state.window.unloaded then pcall(function() state.window:Unload() end) end
	if env.AltairRivals == api then env.AltairRivals = nil end
end

local function reportError(message)
	state.lastError = tostring(message)
	state.errors += 1
	if state.restoreMovement then state.restoreMovement() end
	cancelCombat()
	if os.clock() - state.lastErrorAt > 5 then
		state.lastErrorAt = os.clock()
		warn("Altair Rivals | " .. state.lastError)
	end
end

-- Only the requested, official UI library is downloaded and executed.
local loaded, library = pcall(function()
	local source = game:HttpGet("https://sirius.menu/gen2")
	local chunk, err = loadstring(source)
	assert(chunk, err)
	return chunk()
end)
if not state.alive or env.AltairRivals ~= api then return end
if not loaded or type(library) ~= "table" then
	notify("Rayfield Gen2 could not load: " .. tostring(library))
	api.Unload()
	return
end

local function create(class, properties, parent)
	local object = Instance.new(class)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

-- Native GUI primitives keep overlays usable without the Drawing extension.
local function buildOverlayRoot()
	local gui = create("ScreenGui", {
		Name = "AltairRivalsOverlay", IgnoreGuiInset = true, ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20,
	}, nil)
	state.gui = gui
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
	local parent
	local hidden = env.gethui or env.get_hidden_gui or gethui
	if type(hidden) == "function" then
		local ok, result = pcall(hidden)
		if ok then parent = result end
	end
	if not parent then
		local ok, result = pcall(game.GetService, game, "CoreGui")
		if ok then parent = result end
	end
	local ok = parent and pcall(function() gui.Parent = parent end)
	if not ok then gui.Parent = localPlayer:WaitForChild("PlayerGui", 10) end
	assert(gui.Parent, "No accessible GUI parent")
	state.highlights = create("Folder", { Name = "AltairRivalsHighlights" }, gui)
	state.circle = create("Frame", { Name = "AimRadius", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(.5, .5), Visible = false }, gui)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, state.circle)
	state.circleStroke = create("UIStroke", { Thickness = 1, Transparency = .35 }, state.circle)
	state.crosshair = create("TextLabel", { BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(20, 20),
		Text = "+", TextSize = 22, Font = Enum.Font.Code, Visible = false }, gui)
end

-- Pure response function: the setting is the time to remove half the error.
local function smoothingAlpha(milliseconds, dt)
	return 1 - 2 ^ (-math.max(dt, 0) / (math.max(milliseconds, 1) / 1000))
end

local function teamId(player)
	local value = player:GetAttribute("TeamID")
	if (type(value) == "string" and value ~= "") or type(value) == "number" then return value end
	return nil
end

local function relation(player)
	local mine, theirs = teamId(localPlayer), teamId(player)
	if mine ~= nil and theirs ~= nil then
		return mine == theirs and "Ally" or "Enemy"
	end
	if localPlayer.Team and player.Team and not localPlayer.Neutral and not player.Neutral then
		return localPlayer.Team == player.Team and "Ally" or "Enemy"
	end
	return "Unknown"
end

-- The round capture has EnvironmentID on Character; Player is a fallback.
local function environmentId(player)
	local character = player.Character
	local value = character and character:GetAttribute("EnvironmentID")
	if value ~= nil then return value end
	return player:GetAttribute("EnvironmentID")
end

local function sharesArena(player)
	if not cfg.sameArena then return true end
	local mine = environmentId(localPlayer)
	local theirs = environmentId(player)
	-- The attribute is a compatibility hint, not a claimed stable game API.
	if mine ~= nil or theirs ~= nil then return mine ~= nil and mine == theirs end
	return true
end

local function characterOf(player)
	local character = player.Character
	if not character or not character.Parent then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return character, humanoid, root
end

-- Resolve only the captured, bounded ViewModels hierarchy, never the whole world.
function state.weaponFor(player)
	local models = workspace:FindFirstChild("ViewModels")
	if not models then return nil end
	local folder = player == localPlayer and models:FindFirstChild("FirstPerson") or models
	if not folder then return nil end
	local prefix = player.Name .. " - "
	local found
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name:sub(1, #prefix) == prefix then
			local tail = model.Name:sub(#prefix + 1)
			local name = tail:match("^(.-) %- ") or tail
			if found and found ~= name then return nil end -- ambiguous equipment transition
			found = name
		end
	end
	return found
end

function state.mainFrame()
	local gui = localPlayer:FindFirstChild("PlayerGui")
	local main = gui and gui:FindFirstChild("MainGui")
	return main and main:FindFirstChild("MainFrame")
end

function state.follow(root, ...)
	for _, name in ipairs({ ... }) do root = root and root:FindFirstChild(name) end
	return root
end

function state.shown(object)
	if not object then return false end
	local node = object
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") then return node.Enabled end
		node = node.Parent
	end
	return false
end

function state.roundPause()
	local main = state.mainFrame()
	if not main then return nil end
	if state.shown(state.follow(main, "BottomStack", "Spectate")) then return "Spectating" end
	local duel = state.follow(main, "DuelInterfaces", "DuelInterface")
	if state.shown(state.follow(duel, "FinalResults")) then return "Match results" end
	if state.shown(state.follow(duel, "Top", "RoundResult")) then return "Round results" end
	return nil
end

function state.readHotbar()
	local fighter = state.follow(state.mainFrame(), "FighterInterfaces", localPlayer.Name)
	local hotbar = state.follow(fighter, "BottomRight", "Container", "Hotbar", "Container")
	local names, ammo = {}, nil
	if hotbar then
		for _, slot in ipairs(hotbar:GetChildren()) do
			if slot:IsA("GuiObject") and slot:FindFirstChild("Ammo") then
				table.insert(names, slot.Name)
				if slot.Name == state.weapon then
					local title = state.follow(slot, "Ammo", "Title")
					if title and title:IsA("TextLabel") then ammo = tonumber(title.Text:gsub("<[^>]+>", ""):match("^%s*(%d+)")) end
				end
			end
		end
	end
	table.sort(names)
	state.hotbar = names
	return ammo
end

local function allowed(player, forEsp)
	if player == localPlayer or player.Parent ~= Players or not sharesArena(player) then return false end
	if not forEsp and cfg.antiKatana then
		local weapon = state.weaponFor(player)
		if weapon and weapon:lower():find("katana", 1, true) then return false end
	end
	local side = relation(player)
	if side == "Unknown" and not cfg.unassigned then return false end
	if cfg.teams and side == "Ally" and not (forEsp and cfg.espTeam) then return false end
	return true
end

local HEAD = { "HitboxHead", "PhysicalHitboxHead", "Head" }
local BODY = { "HitboxBody", "PhysicalHitboxBody", "UpperTorso", "Torso", "HumanoidRootPart" }
local function firstPart(character, names)
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part end
	end
	return nil
end

local function aimPart(character)
	if cfg.part == "Torso" then return firstPart(character, BODY) end
	local head = firstPart(character, HEAD)
	if cfg.part == "Head" then return head or firstPart(character, BODY) end
	local body = firstPart(character, BODY)
	if not head then return body end
	if not body then return head end
	local centre = camera.ViewportSize / 2
	local a = camera:WorldToViewportPoint(head.Position)
	local b = camera:WorldToViewportPoint(body.Position)
	return (Vector2.new(a.X, a.Y) - centre).Magnitude < (Vector2.new(b.X, b.Y) - centre).Magnitude and head or body
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local function raycast(direction)
	local exclude = { camera }
	-- The capture places first-person weapon geometry here, not under Camera.
	local viewModels = workspace:FindFirstChild("ViewModels")
	local firstPerson = viewModels and viewModels:FindFirstChild("FirstPerson")
	if firstPerson then table.insert(exclude, firstPerson) end
	if localPlayer.Character then table.insert(exclude, localPlayer.Character) end
	rayParams.FilterDescendantsInstances = exclude
	return workspace:Raycast(camera.CFrame.Position, direction, rayParams)
end

local function clearSight(character, position)
	local hit = raycast(position - camera.CFrame.Position)
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

local function candidate(player, radius)
	if not allowed(player, false) then return nil end
	local character, humanoid, root = characterOf(player)
	if not character or character:FindFirstChildOfClass("ForceField") then return nil end
	local part = aimPart(character)
	if not part then return nil end
	local distance = (root.Position - camera.CFrame.Position).Magnitude
	if distance > cfg.distance then return nil end
	local point, onScreen = camera:WorldToViewportPoint(part.Position)
	local pixels = (Vector2.new(point.X, point.Y) - camera.ViewportSize / 2).Magnitude
	if not onScreen or point.Z <= 0 or pixels > radius then return nil end
	if cfg.visible and not clearSight(character, part.Position) then return nil end
	return { player = player, character = character, humanoid = humanoid, part = part,
		root = root, pixels = pixels, distance = distance }
end

local function acquire()
	if cfg.sticky and state.target then
		local retained = candidate(state.target.player, cfg.fov * 1.2)
		if retained then return retained end
	end
	local best, bestScore
	for _, player in ipairs(Players:GetPlayers()) do
		local pick = candidate(player, cfg.fov)
		if pick then
			local score = cfg.priority == "Closest" and pick.distance
				or cfg.priority == "Lowest health" and pick.humanoid.Health or pick.pixels
			if bestScore == nil or score < bestScore then best, bestScore = pick, score end
		end
	end
	return best
end

local function keyHeld(key)
	if typeof(key) ~= "EnumItem" then return false end
	if key.EnumType == Enum.UserInputType then return Input:IsMouseButtonPressed(key) end
	if key == Enum.KeyCode.Unknown then return false end
	return Input:IsKeyDown(key)
end

local function pauseReason()
	if not state.ready then return "Starting" end
	if state.teleporting then return "Teleporting" end
	if not state.focused then return "Window unfocused" end
	if Input:GetFocusedTextBox() then return "Typing" end
	local window = state.window
	if window and window.hasShownOnce == false then return "Starting" end
	if window and window._recordingKeybind then return "Recording key" end
	if cfg.pauseMenu and window and not window.hidden and not window.minimised then return "Menu open" end
	if cfg.pauseRound then
		local round = state.roundPause()
		if round then return round end
	end
	if not camera or not characterOf(localPlayer) then return "Waiting for character" end
	return nil
end

local moveMouse = env.mousemoverel or mousemoverel
local pressMouse = env.mouse1press or mouse1press
local releaseMouse = env.mouse1release or mouse1release
local clickMouse = env.mouse1click or mouse1click
local hasPair = type(pressMouse) == "function" and type(releaseMouse) == "function"
local hasClick = type(clickMouse) == "function"

function state.restoreMovement()
	for part, original in pairs(state.collisions) do
		pcall(function() if part.Parent and part.CanCollide == false then part.CanCollide = original end end)
	end
	table.clear(state.collisions)
end

function state.movementStep()
	if not state.alive or pauseReason() then state.restoreMovement(); return end
	local character, humanoid, root = characterOf(localPlayer)
	if not character then state.restoreMovement(); return end
	if cfg.noclip then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				if state.collisions[part] == nil then state.collisions[part] = part.CanCollide end
				part.CanCollide = false
			end
		end
	else state.restoreMovement() end
	if cfg.speed and humanoid.MoveDirection.Magnitude > 0 then
		local velocity = humanoid.MoveDirection * (humanoid.WalkSpeed * cfg.speedPercent / 100)
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, root.AssemblyLinearVelocity.Y, velocity.Z)
	end
end

local function steer(pick, dt)
	if type(moveMouse) ~= "function" then state.aimPath = "Mouse input unavailable"; return end
	local position = pick.part.Position + pick.root.AssemblyLinearVelocity * (cfg.lead / 1000)
	local delta = position - camera.CFrame.Position
	if delta.Magnitude < .001 then return end
	-- 1..100 maps to a 5..40ms half-life, with the same response at different FPS.
	local halfLife = 5 + (math.clamp(cfg.smooth, 1, 100) - 1) * 35 / 99
	local alpha = smoothingAlpha(halfLife, math.min(dt, .05))
	local angle = math.acos(math.clamp(camera.CFrame.LookVector:Dot(delta.Unit), -1, 1))
	if angle > .0001 then alpha = math.min(alpha, math.rad(cfg.turnRate) * math.min(dt, .05) / angle) end
	state.aimPath = "Mouse"
	local screen, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen or screen.Z <= 0 then state.residual = Vector2.zero; return end
	local movement = (Vector2.new(screen.X, screen.Y) - camera.ViewportSize / 2) * alpha + state.residual
	local x, y = math.round(movement.X), math.round(movement.Y)
	state.residual = movement - Vector2.new(x, y)
	if x ~= 0 or y ~= 0 then moveMouse(x, y) end
end

-- The supplied Rivals script redirects argument three of Utility.Raycast.
-- Keep that interception separate from mouse steering, and own only our wrapper.
function state.restoreSilent()
	if state.utility and state.silentWrapper then
		pcall(function()
			if state.utility.Raycast == state.silentWrapper then state.utility.Raycast = state.originalRaycast end
		end)
	end
	state.utility, state.silentWrapper, state.originalRaycast = nil, nil, nil
	state.silentStatus = "Disabled"
end

function state.installSilent()
	if state.utility and state.utility.Raycast == state.silentWrapper then return true end
	local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("Utility")
	if not module or not module:IsA("ModuleScript") then return false, "Modules.Utility is unavailable here." end
	local ok, utility = pcall(require, module)
	if not ok or type(utility) ~= "table" or type(utility.Raycast) ~= "function" then
		return false, "Utility.Raycast could not be loaded."
	end
	if not state.alive or env.AltairRivals ~= api or not cfg.silent then return false, "Cancelled" end
	if state.utility == utility and utility.Raycast == state.silentWrapper then return true end
	local original = utility.Raycast
	local wrapper
	wrapper = function(...)
		local args = table.pack(...)
		if state.alive and env.AltairRivals == api and cfg.silent and state.silentWrapper == wrapper
			and args.n >= 3 and typeof(args[2]) == "Vector3" and typeof(args[3]) == "Vector3" then
			local success, replacement = pcall(function()
				if pauseReason() or os.clock() < state.killUntil or math.random(1, 100) > cfg.silentChance then return nil end
				local pick = acquire()
				if pick then return pick.part.Position + pick.root.AssemblyLinearVelocity * (cfg.lead / 1000) end
			end)
			if success and replacement then args[3] = replacement end
		end
		return original(table.unpack(args, 1, args.n))
	end
	local installed, err = pcall(function() utility.Raycast = wrapper end)
	if not installed then return false, tostring(err) end
	state.utility, state.originalRaycast, state.silentWrapper = utility, original, wrapper
	state.silentStatus = "Utility.Raycast installed"
	return true
end

-- Trigger uses the centre ray, independently of the aim target/FOV circle.
local function crosshairTarget()
	local hit = raycast(camera.CFrame.LookVector * cfg.triggerDistance)
	if not hit then return nil end
	local node = hit.Instance
	local owner
	while node and node ~= workspace do
		if node:IsA("Model") then
			owner = Players:GetPlayerFromCharacter(node)
			if owner then break end
		end
		node = node.Parent
	end
	if not owner or not allowed(owner, false) then return nil end
	local character = characterOf(owner)
	if not character or character:FindFirstChildOfClass("ForceField") then return nil end
	if cfg.headOnly and not table.find(HEAD, hit.Instance.Name) then return nil end
	return owner
end

local function triggerStep(now)
	if not cfg.trigger or (cfg.triggerWithAimKey and not keyHeld(cfg.aimKey)) then
		state.pending = nil
		releaseTrigger()
		return
	end
	local target = crosshairTarget()
	if state.release then
		if now >= state.releaseAt or not target or target ~= state.heldTarget then releaseTrigger() end
		return
	end
	if not target then state.pending = nil; return end
	if now < state.nextShot then return end
	if not state.pending or state.pending.player ~= target then
		state.pending = { player = target, at = now + cfg.reaction / 1000 }
	end
	if now < state.pending.at then return end
	state.pending = nil
	local ok = false
	if hasPair then
		-- Register the release before pressing, so an input error cannot strand it.
		state.release = releaseMouse
		ok = pcall(pressMouse)
		if ok then
			state.heldTarget = target
			state.releaseAt = now + (cfg.triggerMode == "Hold" and cfg.hold / 1000 or .025)
		else releaseTrigger() end
	elseif hasClick and cfg.triggerMode == "Click" then ok = pcall(clickMouse) end
	state.nextShot = now + cfg.refire / 1000
	if ok then state.inputCount += 1 else state.lastError = "Mouse input failed or unsupported" end
end

local function overlayFor(player)
	local entry = state.overlays[player]
	if entry then return entry end
	local root = create("Frame", { Name = "Player_" .. player.UserId, BackgroundTransparency = 1,
		Visible = false, BorderSizePixel = 0 }, state.gui)
	local stroke = create("UIStroke", { Thickness = 1.2 }, root)
	local label = create("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextSize = 12, TextStrokeTransparency = .3, AnchorPoint = Vector2.new(.5, 1),
		Position = UDim2.fromScale(.5, 0), Size = UDim2.new(1, 160, 0, 48), Text = "" }, root)
	local healthBack = create("Frame", { BackgroundColor3 = Color3.fromRGB(20, 23, 30),
		BorderSizePixel = 0, Position = UDim2.fromOffset(-6, 0), Size = UDim2.new(0, 3, 1, 0) }, root)
	local health = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1) }, healthBack)
	local arrow = create("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(.5, .5), Text = "▲", TextSize = 21, Font = Enum.Font.GothamBold,
		Visible = false, TextStrokeTransparency = .3 }, state.gui)
	local tracer = create("Frame", { BackgroundTransparency = .25, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(.5, .5), Visible = false }, state.gui)
	local highlight = create("Highlight", { Enabled = false, OutlineTransparency = .2 }, state.highlights)
	entry = { root = root, stroke = stroke, label = label, healthBack = healthBack,
		health = health, arrow = arrow, highlight = highlight, tracer = tracer }
	state.overlays[player] = entry
	return entry
end

local function hideOverlays()
	for _, entry in pairs(state.overlays) do
		entry.root.Visible = false; entry.arrow.Visible = false; entry.highlight.Enabled = false; entry.tracer.Visible = false
	end
end

local function projectedBox(character)
	local cf, size = character:GetBoundingBox()
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				local screen = camera:WorldToViewportPoint(cf:PointToWorldSpace(size * Vector3.new(x, y, z) / 2))
				if screen.Z <= .1 then return nil end
				minX, minY = math.min(minX, screen.X), math.min(minY, screen.Y)
				maxX, maxY = math.max(maxX, screen.X), math.max(maxY, screen.Y)
			end
		end
	end
	return minX, minY, maxX - minX, maxY - minY
end

local function espStep()
	hideOverlays()
	if not cfg.esp or not camera then return end
	local vp = camera.ViewportSize
	for _, player in ipairs(Players:GetPlayers()) do
		if not allowed(player, true) then continue end
		local character, humanoid, root = characterOf(player)
		if not character then continue end
		local distance = (root.Position - camera.CFrame.Position).Magnitude
		if distance > cfg.espDistance then continue end
		if not cfg.throughWalls and not clearSight(character, root.Position) then continue end
		local entry = overlayFor(player)
		local color = state.target and state.target.player == player and cfg.targetColor
			or relation(player) == "Ally" and cfg.allyColor or cfg.enemyColor
		entry.highlight.Adornee = character
		entry.highlight.Enabled = cfg.chams
		entry.highlight.FillColor = color
		entry.highlight.OutlineColor = color
		entry.highlight.FillTransparency = cfg.fill / 100
		entry.highlight.DepthMode = cfg.throughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		local screen, onScreen = camera:WorldToViewportPoint(root.Position)
		if onScreen and screen.Z > 0 then
			local x, y, w, h = projectedBox(character)
			if x then
				if cfg.tracers then
					local from, to = Vector2.new(vp.X / 2, vp.Y), Vector2.new(x + w / 2, y + h)
					local delta, midpoint = to - from, (to + from) / 2
					entry.tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
					entry.tracer.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
					entry.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
					entry.tracer.BackgroundColor3 = color
					entry.tracer.Visible = true
				end
				entry.root.Visible = true
				entry.root.Position = UDim2.fromOffset(x, y)
				entry.root.Size = UDim2.fromOffset(w, h)
				entry.stroke.Enabled = cfg.boxes
				entry.stroke.Color = color
				local lines = {}
				if cfg.names then table.insert(lines, player.DisplayName) end
				if cfg.weaponLabels then
					local weapon = state.weaponFor(player)
					if weapon then table.insert(lines, weapon) end
				end
				if cfg.ranges then table.insert(lines, math.floor(distance) .. " studs") end
				entry.label.Text = table.concat(lines, "\n")
				entry.label.TextColor3 = color
				entry.healthBack.Visible = cfg.health
				local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
				entry.health.Size = UDim2.fromScale(1, fraction)
				entry.health.BackgroundColor3 = Color3.fromRGB(240, 91, 105):Lerp(Color3.fromRGB(115, 221, 155), fraction)
			end
		elseif cfg.arrows then
			local localPoint = camera.CFrame:PointToObjectSpace(root.Position)
			local direction = Vector2.new(localPoint.X, -localPoint.Y)
			if localPoint.Z > 0 then direction = Vector2.new(direction.X, math.abs(direction.Y) + 1) end
			if direction.Magnitude < .01 then direction = Vector2.new(0, 1) end
			direction = direction.Unit
			local bounds = Vector2.new(math.max(1, vp.X / 2 - 32), math.max(1, vp.Y / 2 - 32))
			local scale = math.min(bounds.X / math.max(math.abs(direction.X), .001), bounds.Y / math.max(math.abs(direction.Y), .001))
			local position = vp / 2 + direction * scale
			entry.arrow.Position = UDim2.fromOffset(position.X, position.Y)
			entry.arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
			entry.arrow.TextColor3 = color
			entry.arrow.Visible = true
		end
	end
end

local function set(key, value)
	if key == "method" then value = "Mouse"
	elseif key == "aim" and value and type(moveMouse) ~= "function" then
		value = false
		notify("Mouse aim requires mousemoverel on this executor.")
	elseif key == "trigger" and value and not hasPair and not hasClick then
		value = false
		notify("Trigger requires supported mouse input functions.")
	elseif key == "triggerMode" and value == "Hold" and not hasPair then
		value = "Click"
		notify("Hold requires mouse press/release; using Click.")
	end
	cfg[key] = value
	if key == "silent" then
		if value then
			local ok, err = state.installSilent()
			if not ok then cfg.silent = false; value = false; state.silentStatus = err; notify("Silent aim: " .. tostring(err)) end
		else state.restoreSilent() end
	end
	if key == "aim" or key == "trigger" or key == "aimMode" or key == "method" or key == "part"
		or key == "teams" or key == "sameArena" or key == "unassigned" or key == "pauseMenu" or key == "pauseRound" or key == "antiKatana" then cancelCombat() end
	if controls[key] then controls[key]:Set(value, true) end
	if key == "esp" and not value then hideOverlays() end
	if key == "noclip" and not value then state.restoreMovement() end
end

function api.Panic()
	set("aim", false); set("silent", false); set("trigger", false); set("esp", false)
	set("speed", false); set("infiniteJump", false); set("noclip", false)
	cancelCombat(); hideOverlays()
	notify("Aim, silent aim, trigger, ESP and movement disabled.")
end

function api.Snapshot()
	return { version = "1.2.0", placeId = game.PlaceId, status = state.status,
		fps = state.fps, teamStatus = state.teamStatus, weapon = state.weapon, ammo = state.ammo,
		aimPath = state.aimPath, silentStatus = state.silentStatus or "Disabled", teleport = state.teleportStatus, continued = continuing, weaponSource = state.weaponSource, hotbar = state.hotbar or {},
		localEnvironment = environmentId(localPlayer) ~= nil and "Available" or "Unavailable",
		features = { aim = cfg.aim, silent = cfg.silent, trigger = cfg.trigger, esp = cfg.esp, noclip = cfg.noclip, speed = cfg.speed },
		targetUserId = state.target and state.target.player.UserId or nil,
		triggerActions = state.inputCount, lastError = state.lastError, errors = state.errors,
		capabilities = { mouseMove = type(moveMouse) == "function", mousePair = hasPair, mouseClick = hasClick } }
end

local function toggle(tab, key, name, description)
	controls[key] = tab:CreateToggle({ name = name, description = description, flag = "rivals_" .. key,
		value = cfg[key], callback = function(value) set(key, value) end })
	return controls[key]
end
local function slider(tab, key, name, low, high, description)
	controls[key] = tab:CreateSlider({ name = name, description = description, flag = "rivals_" .. (key == "smooth" and "smooth_v2" or key),
		range = { low, high }, increment = 1, value = cfg[key], callback = function(value) cfg[key] = value end })
end
local function dropdown(tab, key, name, options, description)
	controls[key] = tab:CreateDropdown({ name = name, description = description, flag = "rivals_" .. key,
		options = options, value = cfg[key], callback = function(value) set(key, value) end })
end
local function keybind(tab, key, name, description, callback)
	controls[key] = tab:CreateKeybind({ name = name, description = description, flag = "rivals_" .. key,
		value = cfg[key], callback = callback or function() end,
		onChanged = function(value) cfg[key] = value; cancelCombat() end })
end

local function buildUI()
	local window = library:CreateWindow({ name = "Rivals", subtitle = "Altair", showName = "Rivals",
		sidebarLayout = true, theme = cfg.theme, profile = "Match tools",
		configuration = { autoSave = true, autoLoad = not (continuing and type(resume.values) == "table"), fileName = "rivals", customFolder = "Altair/Rivals" } })
	state.window = window
	if continuing and window.settings then window.settings.welcomeToast = false end
	local home = window:CreateTab({ name = "Overview", icon = 138354947487999 })
	local aim = window:CreateTab({ name = "Aim", icon = 10734966248 })
	local trigger = window:CreateTab({ name = "Trigger", icon = 10709791437 })
	local visuals = window:CreateTab({ name = "Visuals", icon = 10723346959 })
	local movement = window:CreateTab({ name = "Movement", icon = 10734966248 })
	local settings = window:CreateTab({ name = "Controls", icon = 10734950309 })
	local diagnostic = window:CreateTab({ name = "Diagnostics", icon = 10723415903 })
	home:CreateText({ name = "Your match, at a glance", text = "Hold right mouse to aim after enabling Aim. Hide this menu to resume combat features. Every setting saves automatically." })
	local stats = home:CreateGroup({ direction = "row" })
	state.fpsStat = stats:CreateStat({ name = "FPS", value = 0, compact = true })
	state.playersStat = stats:CreateStat({ name = "Players", value = 0, compact = true })
	state.actionsStat = stats:CreateStat({ name = "Trigger actions", value = 0, compact = true })
	state.statusText = home:CreateText({ name = "Status", text = "Starting" })
	local quick = home:CreateGroup({ direction = "row" })
	quick:CreateButton({ name = "Disable all", callback = api.Panic })
	quick:CreateButton({ name = "Hide menu", callback = function() window:Hide() end })
	home:CreateText({ name = "Match detection", text = "TeamID determines sides where available. Unassigned players are excluded by default. Diagnostics shows what this server exposes." })

	aim:CreateSection({ name = "Activation" })
	toggle(aim, "aim", "Aim enabled", "Steers toward an eligible opponent while your activation condition is met.")
	dropdown(aim, "aimMode", "Activation", { "Hold", "Always" }, "Hold requires the aim key. Always runs whenever enabled and unpaused; suitable for touch devices.")
	keybind(aim, "aimKey", "Aim key", "Hold this key or mouse button when Activation is Hold.")
	aim:CreateText({ name = "Mouse steering", text = "Aim moves the mouse through the game controller. Response depends on your in-game sensitivity. Camera steering has been removed." })
	toggle(aim, "antiKatana", "Skip Katana holders", "Excludes opponents with a recognised Katana viewmodel from aim and trigger. It does not detect whether they are blocking.")
	aim:CreateSection({ name = "Movement" })
	slider(aim, "smooth", "Smoothness", 1, 100, "Higher = smoother; lower = quicker. The full range removes half the error in 5 to 40ms, so values above 30 remain responsive. Start at 30.")
	slider(aim, "turnRate", "Turn limit (degrees/sec)", 30, 720, "Limits large mouse corrections using an approximate angular speed. Higher allows faster turns; sensitivity also affects the result.")
	slider(aim, "lead", "Motion lead (ms)", 0, 200, "Adds this much target movement to the aim point. 0 is direct aim. This is manual motion lead, not automatic ballistic prediction.")
	slider(aim, "killDelay", "Delay after target death (ms)", 0, 1000, "Waits this long before acquiring a new opponent when the tracked target dies.")
	aim:CreateSection({ name = "Target selection" })
	dropdown(aim, "part", "Body region", { "Head", "Torso", "Nearest" }, "Head/torso prefer Rivals hitbox parts. Nearest chooses whichever region is closer to the crosshair.")
	dropdown(aim, "priority", "Prioritize", { "Crosshair", "Closest", "Lowest health" }, "Chooses the closest screen position, shortest world distance, or lowest health among eligible targets.")
	toggle(aim, "sticky", "Keep target", "Retains the current eligible target out to 120% of FOV; new targets must be inside the drawn circle.")
	slider(aim, "fov", "Aim radius (pixels)", 20, 600, "Maximum distance from screen centre for acquiring an opponent. Higher values cover more of the screen.")
	slider(aim, "distance", "Maximum aim distance (studs)", 50, 3000, "Opponents farther away than this are excluded.")
	toggle(aim, "visible", "Visible targets only", "Requires a clear ray to the selected body region before steering.")

	aim:CreateSection({ name = "Silent aim" })
	toggle(aim, "silent", "Silent aim enabled", "Redirects Utility.Raycast toward an eligible target without moving the view. Uses the target rules below Mouse steering and pauses with combat. Requires this game's Utility module.")
	slider(aim, "silentChance", "Redirect chance (%)", 1, 100, "Chance to redirect each eligible ray. This is not a guaranteed hit rate; 100 redirects every eligible call.")

	trigger:CreateSection({ name = "Firing" })
	toggle(trigger, "trigger", "Trigger enabled", "Fires when the centre ray hits an eligible opponent; independent of the aim FOV.")
	dropdown(trigger, "triggerMode", "Fire mode", { "Click", "Hold" }, "Click briefly presses fire. Hold keeps it pressed up to Hold time, releasing early if the target leaves or combat pauses.")
	slider(trigger, "reaction", "Reaction delay (ms)", 0, 500, "The same opponent must stay under the crosshair for this long. Higher values respond more slowly.")
	slider(trigger, "refire", "Refire interval (ms)", 30, 1000, "Minimum time between trigger actions. Actual weapon fire rate may be slower.")
	slider(trigger, "hold", "Hold time (ms)", 20, 600, "Maximum time fire stays down in Hold mode; an automatic weapon can fire several bullets.")
	toggle(trigger, "headOnly", "Head hits only", "Only fires when the ray hits a recognised head part or Rivals head hitbox.")
	toggle(trigger, "triggerWithAimKey", "Require aim key", "Trigger runs only while your aim key is physically held, regardless of Aim activation mode.")
	slider(trigger, "triggerDistance", "Maximum trigger distance (studs)", 50, 3000, "Length of the centre ray used to find an opponent.")
	trigger:CreateText({ name = "Input support", text = hasPair and "Mouse press/release available: Click and Hold supported."
		or hasClick and "Mouse click available. Hold mode requires mouse press/release support."
		or "No supported mouse input functions detected. Trigger is unavailable on this executor." })

	visuals:CreateSection({ name = "Player overlay" })
	toggle(visuals, "esp", "Player ESP", "Shows selected overlays for eligible players; uses Roblox GUI primitives.")
	toggle(visuals, "boxes", "Bounding boxes", "Draws a projected box around each character model.")
	toggle(visuals, "tracers", "ESP tracers", "Draws a line from the bottom centre to each visible player box.")
	toggle(visuals, "weaponLabels", "Weapon labels", "Shows the weapon name from available player viewmodels.")
	toggle(visuals, "names", "Player names", "Shows the player's display name above the box.")
	toggle(visuals, "health", "Health bars", "Shows current health as a red-to-green bar beside the box.")
	toggle(visuals, "ranges", "Distance labels", "Shows camera-to-player distance in studs.")
	toggle(visuals, "arrows", "Offscreen arrows", "Points toward eligible players outside the viewport.")
	toggle(visuals, "chams", "Body highlights", "Adds a coloured fill and outline to player bodies.")
	toggle(visuals, "throughWalls", "Show through walls", "Allows overlays and highlights through obstacles. Turn off to require visibility.")
	toggle(visuals, "espTeam", "Include teammates", "Includes teammates in ESP while keeping them excluded from aim and trigger when Team check is enabled.")
	slider(visuals, "fill", "Highlight transparency (%)", 0, 100, "0 is solid; 100 hides the fill while keeping its outline.")
	slider(visuals, "espDistance", "ESP distance (studs)", 50, 3000, "Maximum distance for all player overlays.")
	slider(visuals, "espRate", "ESP refresh rate (Hz)", 10, 60, "Higher updates overlays more often and uses more CPU. Aim still updates every frame.")
	visuals:CreateSection({ name = "Crosshair and colour" })
	toggle(visuals, "circle", "Aim radius circle", "Shows the acquisition radius while Aim is enabled and unpaused.")
	toggle(visuals, "crosshair", "Centre crosshair", "Adds a small cross at the physical viewport centre.")
	for _, spec in ipairs({ { "enemyColor", "Enemy colour" }, { "targetColor", "Current target colour" }, { "allyColor", "Teammate colour" } }) do
		local key = spec[1]
		controls[key] = visuals:CreateColorPicker({ name = spec[2], description = "Applies to this player's boxes, labels, arrows and highlights.",
			flag = "rivals_" .. key, color = cfg[key], callback = function(color) cfg[key] = color end })
	end

	movement:CreateSection({ name = "Character movement" })
	toggle(movement, "speed", "Speed boost", "Scales horizontal movement while walking. Preserves vertical velocity and pauses with the menu, results or spectator view.")
	slider(movement, "speedPercent", "Movement speed (%)", 100, 250, "100 uses your current WalkSpeed; 135 requests 1.35 times that horizontal speed. Server corrections can still apply.")
	toggle(movement, "infiniteJump", "Air jump", "Allows another jump request while airborne. Supports the keyboard and Roblox's touch jump button.")
	toggle(movement, "noclip", "Noclip", "Temporarily disables your character's collisions. Restores saved values when paused, disabled, respawned or unloaded.")
	movement:CreateText({ name = "Panic", text = "Your panic key also disables all movement changes." })
	settings:CreateSection({ name = "Shared target rules" })
	toggle(settings, "teams", "Team check", "Excludes your Rivals TeamID, with non-neutral Roblox teams as a fallback. Applies to aim, trigger and ESP.")
	toggle(settings, "sameArena", "Same environment only", "When EnvironmentID is available, excludes players in other environments. Has no effect when both IDs are absent.")
	toggle(settings, "unassigned", "Include unassigned players", "Includes players whose side cannot be determined. Useful for testing; can include lobby players.")
	toggle(settings, "pauseMenu", "Pause combat while menu is open", "Pauses aim and trigger while this window is expanded. Hiding or minimising it resumes enabled features.")
	toggle(settings, "pauseRound", "Pause during results and spectating", "Pauses combat and movement when the captured Rivals result or spectator interfaces are visible.")
	keybind(settings, "panicKey", "Panic key", "Immediately disables aim, trigger, ESP and movement, and releases synthetic fire input.")
	settings:CreateSection({ name = "Appearance and session" })
	controls.theme = settings:CreateDropdown({ name = "Theme", description = "Uses Rayfield Gen2's built-in animated themes.", flag = "rivals_theme",
		options = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }, value = cfg.theme,
		callback = function(value) cfg.theme = value; window:ChangeTheme(value) end })
	settings:CreateButton({ name = "Save settings now", description = "Writes the current configuration to Altair/Rivals.",
		callback = function() notify(window:Save() and "Rivals settings saved." or "Settings could not be saved.") end })
	settings:CreateButton({ name = "Unload Rivals", description = "Restores character collisions and removes this window, overlays, callbacks and synthetic held input.", callback = api.Unload })
	diagnostic:CreateText({ name = "Compatibility", text = "TeamID, character EnvironmentID, viewmodels and the fighter HUD provide match information. Missing weapon data does not disable aim. Altair Debug Mode adds a Rivals provider to recordings." })
	state.diagnostics = diagnostic:CreateConsole({ text = "Starting", height = 250, maxLines = 30, follow = false })
	diagnostic:CreateButton({ name = "Copy diagnostics", description = "Copies a compact status snapshot for troubleshooting.", callback = function()
		local copy = env.setclipboard or setclipboard
		if type(copy) ~= "function" then notify("Clipboard is unavailable."); return end
		local ok, err = pcall(function() copy(game:GetService("HttpService"):JSONEncode(api.Snapshot())) end)
		notify(ok and "Diagnostics copied." or "Copy failed: " .. tostring(err))
	end })
	if window.screenGui then connect(window.screenGui.Destroying, api.Unload) end
	if type(moveMouse) ~= "function" then controls.aim:Lock("Mouse movement is unavailable on this executor.") end
	if not hasPair and not hasClick then controls.trigger:Lock("Mouse input is unavailable on this executor.") end
end

local ok, err = pcall(function() buildOverlayRoot(); buildUI() end)
if not ok then reportError(err); notify("Rivals could not initialize: " .. tostring(err)); api.Unload(); return end

-- Teleport values are kept client-side by Roblox for this experience only.
-- Carry the exact running source; no repository URL, filesystem path or second
-- autoexecute entry is required, and successive hops do not nest source strings.
state.resumeCode = [====[
-- Runs either from the executor's teleport queue or Altair's existing autoexecute.
if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 6035872082 then return end
local service = game:GetService("TeleportService")
local ok, marker = pcall(service.GetTeleportSetting, service, "Altair.Rivals.v1")
if not ok or type(marker) ~= "table" or marker.active ~= true or marker.universe ~= game.GameId
	or type(marker.fromJob) ~= "string" or marker.fromJob == game.JobId
	or type(marker.at) ~= "number" or os.time() - marker.at < 0 or os.time() - marker.at > 600
	or type(marker.source) ~= "string" then return end
local chunk, err = loadstring(marker.source, "Altair Rivals (continued)")
if chunk then return chunk(marker.source, true) end
warn("Altair Rivals | Could not continue after teleport: " .. tostring(err))
]====]
state.queueTeleport = env.queue_on_teleport or env.queueonteleport or queue_on_teleport or queueonteleport
	or (type(syn) == "table" and syn.queue_on_teleport)
	or (type(fluxus) == "table" and fluxus.queue_on_teleport)
state.teleportStatus = type(state.queueTeleport) == "function" and "Queue available" or "Altair autoexecute fallback"

function state.packSettings()
	local values = {}
	for key, value in pairs(cfg) do
		if typeof(value) == "EnumItem" then values[key] = { kind = "enum", family = tostring(value.EnumType), name = value.Name }
		elseif typeof(value) == "Color3" then values[key] = { kind = "color", r = value.R, g = value.G, b = value.B }
		elseif type(value) == "number" or type(value) == "string" or type(value) == "boolean" then values[key] = value end
	end
	return values
end

if continuing and type(resume.values) == "table" then
	for key, value in pairs(resume.values) do
		if cfg[key] ~= nil and key ~= "method" then
			local ok, decoded = pcall(function()
				if type(value) ~= "table" then return value end
				if value.kind == "color" then return Color3.new(value.r, value.g, value.b) end
				if value.kind == "enum" and (value.family == "Enum.KeyCode" or value.family == "Enum.UserInputType") then
					return Enum[value.family:sub(6)][value.name]
				end
			end)
			if ok and typeof(decoded) == typeof(cfg[key]) then set(key, decoded) end
		end
	end
	if state.window.ChangeTheme then state.window:ChangeTheme(cfg.theme) end
	-- Saved collapsed windows resume without flashing the expanded menu. Gen2's
	-- initial reveal must finish before its public Hide/ToggleMinimise methods run.
	if resume.hidden or resume.minimised then
		local window = state.window
		if window.screenGui then window.screenGui.Enabled = false end
		task.spawn(function()
			while state.alive and (not window.hasShownOnce or window.animating) do task.wait(.05) end
			if not state.alive then return end
			if resume.hidden then window:Hide() else window:ToggleMinimise() end
			while state.alive and window.animating do task.wait(.05) end
			if state.alive and window.screenGui then window.screenGui.Enabled = true end
		end)
	end
end

connect(localPlayer.OnTeleport, function(teleportState)
	if teleportState == Enum.TeleportState.Failed then
		state.teleporting = false
		state.teleportQueued = false
		pcall(Teleport.SetTeleportSetting, Teleport, resumeKey, false)
		return
	end
	if teleportState ~= Enum.TeleportState.Started and teleportState ~= Enum.TeleportState.InProgress then return end
	if not state.alive then return end
	state.teleporting = true
	cancelCombat()
	state.restoreMovement()
	local ok, err = pcall(function()
		assert(type(moduleSource) == "string", "Run the complete Rivals.lua artifact to enable continuation.")
		Teleport:SetTeleportSetting(resumeKey, {
			active = true, universe = game.GameId, fromJob = game.JobId, at = os.time(), source = moduleSource,
			values = state.packSettings(), hidden = state.window.hidden == true, minimised = state.window.minimised == true,
		})
		if type(state.queueTeleport) == "function" and not state.teleportQueued then
			state.queueTeleport(state.resumeCode)
			state.teleportQueued = true
		end
	end)
	state.teleportStatus = ok and (state.teleportQueued and "Queued" or "Waiting for Altair autoexecute") or tostring(err)
	if not ok then warn("Altair Rivals | Teleport continuation: " .. tostring(err)) end
end)
connect(Teleport.TeleportInitFailed, function(player)
	if player ~= localPlayer then return end
	state.teleporting = false
	state.teleportQueued = false
	pcall(Teleport.SetTeleportSetting, Teleport, resumeKey, false)
end)

connect(Input.WindowFocusReleased, function() state.focused = false; cancelCombat() end)
connect(Input.WindowFocused, function() state.focused = true end)
connect(Input.InputBegan, function(input)
	if state.ready and not state.window._recordingKeybind and not Input:GetFocusedTextBox()
		and (input.KeyCode == cfg.panicKey or input.UserInputType == cfg.panicKey) then api.Panic() end
end)
connect(localPlayer.CharacterRemoving, function() cancelCombat(); state.restoreMovement() end)
connect(RunService.PreSimulation, function()
	local ok, err = pcall(state.movementStep)
	if not ok then reportError(err) end
end)
connect(Input.JumpRequest, function()
	if not cfg.infiniteJump or pauseReason() or os.clock() < (state.nextJump or 0) then return end
	local _, humanoid = characterOf(localPlayer)
	if humanoid then
		state.nextJump = os.clock() + .2
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)
connect(localPlayer:GetAttributeChangedSignal("TeamID"), cancelCombat)
connect(localPlayer:GetAttributeChangedSignal("EnvironmentID"), cancelCombat)
connect(Players.PlayerRemoving, function(player)
	local entry = state.overlays[player]
	if entry then entry.root:Destroy(); entry.arrow:Destroy(); entry.highlight:Destroy(); entry.tracer:Destroy(); state.overlays[player] = nil end
	if state.target and state.target.player == player then cancelCombat() end
end)

-- The recorded match exposes equipment through ViewModels and the fighter HUD.
-- Reading it does not require running the game's controller modules.
task.spawn(function()
	while state.alive do
		pcall(function()
			state.weapon = state.weaponFor(localPlayer) or "Unavailable"
			state.weaponSource = state.weapon ~= "Unavailable" and "ViewModels" or "Unavailable"
			state.ammo = state.readHotbar()
		end)
		task.wait(.25)
	end
end)

state.ready = true
local espElapsed, statusElapsed = 0, 0
RunService:BindToRenderStep("AltairRivals", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not state.alive then return end
	if state.window.unloaded then api.Unload(); return end
	local success, problem = pcall(function()
		camera = workspace.CurrentCamera
		if camera ~= state.lastCamera then state.lastCamera = camera; cancelCombat() end
		state.frames += 1; state.elapsed += dt
		espElapsed += dt; statusElapsed += dt
		local now = os.clock()
		local reason = pauseReason()
		if reason then cancelCombat(); state.aimPath = "paused"; state.status = reason
		else
			state.status = "Ready"
			local aimActive = cfg.aim and (cfg.aimMode == "Always" or keyHeld(cfg.aimKey))
			if aimActive then
				if state.target and state.target.humanoid.Health <= 0 then
					state.killUntil = now + cfg.killDelay / 1000; state.target = nil
				end
				if now >= state.killUntil then
					local pick = acquire()
					if not pick then state.aimPath = "No eligible target" end
					if not pick or not state.target or pick.player ~= state.target.player then state.residual = Vector2.zero end
					state.target = pick
					if pick then steer(pick, dt); state.status = "Tracking opponent" else state.status = "No eligible target" end
				else state.status = "Delay after target death" end
			else state.target = nil; state.aimPath = cfg.aim and "Waiting for aim key" or "Disabled"; state.residual = Vector2.zero end
			triggerStep(now)
		end
		if camera then
			local centre = camera.ViewportSize / 2
			state.circle.Visible = cfg.circle and (cfg.aim or cfg.silent) and reason == nil
			state.circle.Position = UDim2.fromOffset(centre.X, centre.Y)
			state.circle.Size = UDim2.fromOffset(cfg.fov * 2, cfg.fov * 2)
			state.circleStroke.Color = cfg.targetColor
			state.crosshair.Visible = cfg.crosshair and reason == nil
			state.crosshair.Position = UDim2.fromOffset(centre.X, centre.Y)
			state.crosshair.TextColor3 = cfg.targetColor
		end
		if espElapsed >= 1 / cfg.espRate then espElapsed = 0; espStep() end
		if statusElapsed >= .5 then
			statusElapsed = 0
			pcall(function()
				local altair = env.Altair
				local enabled = type(altair) == "table" and type(altair.DebugEnabled) == "function" and altair.DebugEnabled()
				if not enabled then
					if state.debugClient then state.debugClient:Detach("debug-disabled"); state.debugClient = nil end
				elseif type(altair.GetDebugClient) == "function" and (not state.debugClient or not state.debugClient:IsActive()) then
					state.debugClient = altair.GetDebugClient("Rivals", { Description = "Rivals combat, input and weapon state.",
						Sample = function() return api.Snapshot() end, Snapshot = function() return api.Snapshot() end },
						{ script = "Rivals", version = "1.2.0", placeId = game.PlaceId })
				end
			end)
			state.fps = math.floor(state.frames / math.max(state.elapsed, .001) + .5)
			state.frames, state.elapsed = 0, 0
			state.teamStatus = teamId(localPlayer) ~= nil and "Rivals TeamID available" or "Rivals TeamID unavailable"
			state.fpsStat:Set(state.fps); state.playersStat:Set(#Players:GetPlayers()); state.actionsStat:Set(state.inputCount)
			state.statusText:Set(state.status .. "\n" .. state.teamStatus .. "\nWeapon: " .. state.weapon)
			state.diagnostics:Set(table.concat({ "Status: " .. state.status, "Teams: " .. state.teamStatus,
				"EnvironmentID: " .. (environmentId(localPlayer) ~= nil and "Available" or "Unavailable"),
				"Aim path: " .. state.aimPath, "Silent aim: " .. (state.silentStatus or "Disabled"),
				"Teleport: " .. state.teleportStatus, "Weapon source: " .. state.weaponSource,
				"Hotbar: " .. table.concat(state.hotbar or {}, ", "), "Weapon: " .. state.weapon, "Ammo: " .. tostring(state.ammo or "Unknown"),
				"Mouse move: " .. tostring(type(moveMouse) == "function"), "Mouse press/release: " .. tostring(hasPair),
				"Trigger actions (not confirmed hits): " .. state.inputCount, "Errors: " .. state.errors,
				"Last error: " .. state.lastError }, "\n"))
		end
	end)
	if not success then reportError(problem) end
end)

if not continuing then notify("Rivals ready. Enable the features you want, then hide the menu. F1 disables aim, silent aim, trigger, ESP and movement.") end
return api
]======]
local chunk, err = loadstring(source, "Altair Rivals")
assert(chunk, err)
return chunk(source)
