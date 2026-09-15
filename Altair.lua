
--[[

Altair

© 2026 Cloudz Softwares. 

Altair is a Smart Script based and built around Sirius

--]]

--[[

Altair Pre-Hyperion Todo List

High Priority
 - Invisible, Godmode
 - All Scripts buttons and Universal scripts
 - Chat Spam Detection
 - Custom Script Prompts
 - Player Kill, Spectate and ESP via Playerlist
 - http.request support for Altair Intelligent HTTP Interception
 - Performance Improvements to Roblox itself
 
Moderate Priority
 - Spectate Animation, like GTA serverhop, tween to high in the sky, then tween to other player's head
 - Chat Spy Tracking: Follows who they're whispering to based on original message
 - Starlight 
 - Chatlogs
 - GTA Serverhop
 - Anti-Spam (chat) formula, based on text length, caps, emojis etc.
 - Reduce any form of detection of Altair
 - Automated lowering of graphics on lower FPS, ensure no false positives
 
Potential Future Setting Options
 - Block entire domain or just the specific page in the Altair Intelligent Flow Interception. Do this on case by case, e.g blocked = {"link.com", true} - true being whether its the domain or not
 - Serverhop type (default/gta)
 - Hook Specific Functions to reduce the need for external scripts
 
--]]

if not game:IsLoaded() then
	local deadline = os.clock() + 10
	while not game:IsLoaded() and os.clock() < deadline do
		task.wait()
	end
end

-- Check License Tier
local Pro = true -- We're open sourced now!

local function optional(value)
	return typeof(value) == "function" and value or nil
end

local setFpsCap = optional(setfpscap)
local getConnectionsFor = optional(getconnections)
local hookMetamethod = optional(hookmetamethod)
local getHiddenUI = optional(gethui)
local cloneRef = optional(cloneref)
local getEnv = optional(getgenv)

local env = getEnv and getEnv() or _G
-- Finish the previous session before capturing camera/audio state for this one.
do
	local previous = env.Altair
	if type(previous) == "table" and type(previous.Unload) == "function" then
		pcall(previous.Unload)
	elseif type(previous) == "table" then
		-- One-time migration from the old name-based, one-second cleanup loop.
		pcall(function()
			local root = getHiddenUI and getHiddenUI() or game:GetService("CoreGui")
			local old = root:FindFirstChild("Altair")
			if old and old:FindFirstChild("SmartBar") and old:FindFirstChild("Drag") then
				old:Destroy()
				task.wait(1.1)
			end
		end)
	end
end

local function getService(name)
	local service = game:GetService(name)
	return cloneRef and cloneRef(service) or service
end

-- Create Variables for Roblox Services
local coreGui = getService("CoreGui")
local httpService = getService("HttpService")
local lighting = getService("Lighting")
local players = getService("Players")
local replicatedStorage = getService("ReplicatedStorage")
local runService = getService("RunService")
local guiService = getService("GuiService")
local statsService = getService("Stats")
local starterGui = getService("StarterGui")
local teleportService = getService("TeleportService")
local tweenService = getService("TweenService")
local userInputService = getService("UserInputService")
local textChatService = getService("TextChatService")
local marketplaceService = getService("MarketplaceService")
local gameSettings = UserSettings():GetService("UserGameSettings")

-- Variables
local useStudio = runService:IsStudio()
local connections = {}
local camera = workspace.CurrentCamera
local getMessage = replicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 1) and replicatedStorage.DefaultChatSystemChatEvents:WaitForChild("OnMessageDoneFiltering", 1)
local legacyChatActive = getMessage ~= nil and textChatService.ChatVersion == Enum.ChatVersion.LegacyChatService
local localPlayer = players.LocalPlayer
local notifications = {}

local promptedDisconnected = false
local smartBarOpen = false
local debounce = false
local searchingForPlayer = false
local lowerName = localPlayer.Name:lower()
local lowerDisplayName = localPlayer.DisplayName:lower()
local placeId = game.PlaceId
local jobId = game.JobId
local checkingForKey
local originalTextValues = {}
local creatorId = game.CreatorId
local noclipDefaults = {}
local movers = {}
local creatorType = game.CreatorType
local espContainer -- Created only after the UI asset successfully loads.
local locatedPlayers = {} -- per-player ESP toggles, independent from the global ESP action
local espConnections = {} -- [player] = RBXScriptConnection for CharacterAdded
local descendantAddedConn -- top-level DescendantAdded; tracked so we can disconnect on teardown
local oldVolume = gameSettings.MasterVolume
local baseFieldOfView = camera.FieldOfView -- captured once; Home restores to this rather than doing relative maths

local placeName -- resolved once at startup so the JobId copy button never yields on click

-- Runtime caches
local suppressedSounds = {}
local soundSuppressionNotificationCooldown = 0
local soundInstances = {}
local trackedSounds = {} -- [Sound] = true, replaces the linear table.find scan
local trackedText = {} -- [TextLabel|TextButton] = true
local cachedIds = {}
local activeToasts = {}
local cachedText = {}

local blinkState = {
	queue = {},
	running = false,
	color = nil,
	persistentColor = nil,
}
local spectating
local closeModPrompt

-- Configurable Core Values
local SECURITY_PROMPT_TIMEOUT = 60 -- seconds before an unanswered prompt denies by default
local altairValues = {
	altairVersion = "1.34",
	altairName = "Altair",
	releaseType = "Stable",
	altairFolder = "Altair",
	settingsFile = "settings.altair",
	customScriptsFolder = "Custom Scripts",
	scriptsFolder = "Scripts",
	customScripts = {},
	detectedScript = nil,
	detectionPromptOpen = false,
	customScriptPromptOpen = false,
	interfaceAsset = 138836088211906,

	executors = {
		"synapse x",
		"script-ware",
		"krnl",
		"scriptware",
		"comet",
		"valyse",
		"fluxus",
		"electron",
		"hydrogen",
		"wave",
		"solara",
		"xeno",
		"swift",
		"delta",
		"codex",
		"arceus x",
		"trigon",
		"vegax",
		"cryptic",
	},
	disconnectTypes = { { "ban", { "ban", "perm" } }, { "network", { "internet connection", "network" } } },
	nameGeneration = {
		adjectives = { "Cool", "Awesome", "Epic", "Ninja", "Super", "Mystic", "Swift", "Golden", "Diamond", "Silver", "Mint", "Roblox", "Amazing" },
		nouns = { "Player", "Gamer", "Master", "Legend", "Hero", "Ninja", "Wizard", "Champion", "Warrior", "Sorcerer" },
	},
	administratorRoles = { "mod", "admin", "staff", "dev", "founder", "owner", "supervis", "manager", "management", "executive", "president", "chairman", "chairwoman", "chairperson", "director" },
	transparencyProperties = {
		UIStroke = { "Transparency" },
		Frame = { "BackgroundTransparency" },
		TextButton = { "BackgroundTransparency", "TextTransparency" },
		TextLabel = { "BackgroundTransparency", "TextTransparency" },
		TextBox = { "BackgroundTransparency", "TextTransparency" },
		ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
		ImageButton = { "BackgroundTransparency", "ImageTransparency" },
		ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	},
	chatSpy = {
		enabled = true,
		visual = {
			Color = Color3.fromRGB(26, 148, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 18,
		},
	},
	chatModeration = {
		users = {},
		maxHistory = 16,
		alertCooldown = 9,
	},
	playerAnomaly = {
		users = {},
		sampleRate = 0.25,
	},
	pingProfile = {
		recentPings = {},
		adaptiveBaselinePings = {},
		pingNotificationCooldown = 0,
		maxSamples = 12, -- max num of recent pings stored
		spikeThreshold = 1.75, -- high Ping in comparison to average ping (e.g 100 avg would be high at 150)
		adaptiveBaselineSamples = 30, -- how many samples Altair takes before deciding on a fixed high ping value
		adaptiveHighPingThreshold = 120, -- default value
	},
	frameProfile = {
		frameNotificationCooldown = 0,
		fpsQueueSize = 10,
		lowFPSThreshold = 20, -- what's low fps!??!?!
		totalFPS = 0,
		fpsQueue = {},
		fpsQueueIndex = 0,
		fpsQueueCount = 0,
	},
	actions = {
		{
			name = "Noclip",
			images = { 14385986465, 9134787693 },
			color = Color3.fromRGB(0, 170, 127),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function() end,
		},
		{
			name = "Flight",
			images = { 9134755504, 14385992605 },
			color = Color3.fromRGB(170, 37, 46),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.PlatformStand = value
				end
			end,
		},
		{
			name = "Refresh",
			images = { 9134761478, 9134761478 },
			color = Color3.fromRGB(61, 179, 98),
			enabled = false,
			rotateWhileEnabled = true,
			disableAfter = 3,
			callback = function()
				task.spawn(function()
					local character = localPlayer.Character
					if character then
						local cframe = character:GetPivot()
						local humanoid = character:FindFirstChildOfClass("Humanoid")
						if humanoid then
							humanoid:ChangeState(Enum.HumanoidStateType.Dead)
						end
						character = localPlayer.CharacterAdded:Wait()
						task.defer(character.PivotTo, character, cframe)
					end
				end)
			end,
		},
		{
			name = "Respawn",
			images = { 9134762943, 9134762943 },
			color = Color3.fromRGB(49, 88, 193),
			enabled = false,
			rotateWhileEnabled = true,
			disableAfter = 2,
			callback = function()
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				end
			end,
		},
		{
			name = "Invincibility",
			images = { 9134765994, 14386216487 },
			color = Color3.fromRGB(193, 46, 90),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function() end,
		},
		{
			name = "Fling",
			images = { 9134785384, 14386226155 },
			color = Color3.fromRGB(184, 85, 61),
			enabled = false,
			rotateWhileEnabled = true,
			callback = function(value)
				local character = localPlayer.Character
				local primaryPart = character and character.PrimaryPart
				if primaryPart then
					for _, part in ipairs(character:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Massless = value
							part.CustomPhysicalProperties = PhysicalProperties.new(value and math.huge or 0.7, 0.3, 0.5)
						end
					end

					primaryPart.Anchored = true
					primaryPart.AssemblyLinearVelocity = Vector3.zero
					primaryPart.AssemblyAngularVelocity = Vector3.zero

					if movers[3] then
						movers[3].Parent = value and primaryPart or nil
					end

					task.delay(0.5, function()
						primaryPart.Anchored = false
					end)
				end
			end,
		},
		{
			name = "Extrasensory Perception",
			images = { 9134780101, 14386232387 },
			color = Color3.fromRGB(214, 182, 19),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				for _, highlight in ipairs(espContainer:GetChildren()) do
					highlight.Enabled = value or locatedPlayers[highlight.Name] == true
				end
			end,
		},
		{
			name = "Time of Day",
			images = { 9134778004, 10137794784 },
			color = Color3.fromRGB(102, 75, 190),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				tweenService:Create(lighting, TweenInfo.new(0.5), { ClockTime = value and 12 or 24 }):Play()
			end,
		},
		{
			name = "Master Vol",
			images = { 9134774810, 14386246782 },
			color = Color3.fromRGB(202, 103, 58),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				if value then
					oldVolume = gameSettings.MasterVolume
					gameSettings.MasterVolume = 0
				else
					gameSettings.MasterVolume = oldVolume
				end
			end,
		},
		{
			name = "Visibility",
			images = { 14386256326, 9134770786 },
			color = Color3.fromRGB(62, 94, 170),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function() end,
		},
	},
	sliders = {
		{
			name = "player speed",
			color = Color3.fromRGB(44, 153, 93),
			values = { 0, 300 },
			default = 16,
			value = 16,
			active = false,
			callback = function(value)
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then -- was `if character`, which let a Humanoid-less character through
					humanoid.WalkSpeed = value
				end
			end,
		},
		{
			name = "jump power",
			color = Color3.fromRGB(59, 126, 184),
			values = { 0, 350 },
			default = 50,
			value = 16,
			active = false,
			callback = function(value)
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then -- was `if character`, which let a Humanoid-less character through
					if humanoid.UseJumpPower then
						humanoid.JumpPower = value
					else
						humanoid.JumpHeight = value
					end
				end
			end,
		},
		{
			name = "flight speed",
			color = Color3.fromRGB(177, 45, 45),
			values = { 1, 25 },
			default = 3,
			value = 3,
			active = false,
			callback = function() end, -- read directly by the Heartbeat flight loop
		},
		{
			name = "field of view",
			color = Color3.fromRGB(198, 178, 75),
			values = { 45, 120 },
			default = 70,
			value = 16,
			active = false,
			callback = function(value)
				tweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), { FieldOfView = value }):Play()
			end,
		},
	},
}

local altairSettings = {
	{
		name = "General",
		description = "The general settings for Altair, from simple to unique features.",
		color = Color3.new(0.117647, 0.490196, 0.72549),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Anonymous Client",
				description = "Randomise your username in real-time in any CoreGui parented interface, including Altair. You will still appear as your actual name to others in-game. This setting can be performance intensive.",
				settingType = "Boolean",
				current = false,

				id = "anonmode",
			},
			{
				name = "Chat Spy",
				description = "Display whispers usually hidden from you in the chat box. This requires the legacy Roblox chat system; experiences on TextChatService route whispers through channels the client never receives, so Altair will tell you when it is unavailable rather than silently doing nothing.",
				settingType = "Boolean",
				current = true,

				id = "chatspy",
			},
			{
				name = "Rainbow Mode",
				description = "Enables an Rainbow function on Altair",
				settingType = "Boolean",
				current = true,

				id = "Rainbowmode",
			},
			{
				name = "Hide Bar",
				description = "This will remove the Drag Bar from the interface.",
				settingType = "Boolean",
				current = false,

				id = "hidetoggle",
			},
			{
				name = "Friend Notifications",
				settingType = "Boolean",
				current = true,

				id = "friendnotifs",
			},
			{
				name = "Load Hidden",
				settingType = "Boolean",
				current = false,

				id = "loadhidden",
			},
			{
				name = "Startup Sound Effect",
				settingType = "Boolean",
				current = true,

				id = "startupsound",
			},
			{
				name = "Anti Idle",
				description = "Remove all callbacks and events linked to the LocalPlayer Idled state. This may prompt detection from Adonis or similar anti-cheats.",
				settingType = "Boolean",
				current = true,

				id = "antiidle",
			},
			{
				name = "Client-Based Anti Kick",
				description = "Cancel any kick request involving you sent by the client. This may prompt detection from Adonis or similar anti-cheats. You will need to rejoin and re-run Altair to toggle.",
				settingType = "Boolean",
				current = false,

				id = "antikick",
			},
			{
				name = "Muffle audio while unfocused",
				settingType = "Boolean",
				current = true,

				id = "muffleunfocused",
			},
		},
	},
	{
		name = "Keybinds",
		description = "Assign keybinds to actions or change keybinds such as the one to open/close Altair.",
		color = Color3.new(0.0941176, 0.686275, 0.509804),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Toggle smartBar",
				settingType = "Key",
				current = "K",
				id = "smartbar",
			},
			{
				name = "Open ScriptSearch",
				settingType = "Key",
				current = "T",
				id = "scriptsearch",
			},
			{
				name = "NoClip",
				settingType = "Key",
				current = nil,
				id = "noclip",
				actionIndex = 1,
				callback = function()
					local noclip = altairValues.actions[1]
					noclip.enabled = not noclip.enabled
					noclip.callback(noclip.enabled)
				end,
			},
			{
				name = "Flight",
				settingType = "Key",
				current = nil,
				id = "flight",
				actionIndex = 2,
				callback = function()
					local flight = altairValues.actions[2]
					flight.enabled = not flight.enabled
					flight.callback(flight.enabled)
				end,
			},
			{
				name = "Refresh",
				settingType = "Key",
				current = nil,
				id = "refresh",
				actionIndex = 3,
				callback = function()
					local refresh = altairValues.actions[3]
					if not refresh.enabled then
						refresh.enabled = true
						refresh.callback()
					end
				end,
			},
			{
				name = "Respawn",
				settingType = "Key",
				current = nil,
				id = "respawn",
				actionIndex = 4,
				callback = function()
					local respawn = altairValues.actions[4]
					if not respawn.enabled then
						respawn.enabled = true
						respawn.callback()
					end
				end,
			},
			{
				name = "Invulnerability",
				settingType = "Key",
				current = nil,
				id = "invulnerability",
				actionIndex = 5,
				callback = function()
					local invulnerability = altairValues.actions[5]
					invulnerability.enabled = not invulnerability.enabled
					invulnerability.callback(invulnerability.enabled)
				end,
			},
			{
				name = "Fling",
				settingType = "Key",
				current = nil,
				id = "fling",
				actionIndex = 6,
				callback = function()
					local fling = altairValues.actions[6]
					fling.enabled = not fling.enabled
					fling.callback(fling.enabled)
				end,
			},
			{
				name = "ESP",
				settingType = "Key",
				current = nil,
				id = "esp",
				actionIndex = 7,
				callback = function()
					local esp = altairValues.actions[7]
					esp.enabled = not esp.enabled
					esp.callback(esp.enabled)
				end,
			},
			{
				name = "Night and Day",
				settingType = "Key",
				current = nil,
				id = "nightandday",
				actionIndex = 8,
				callback = function()
					local nightandday = altairValues.actions[8]
					nightandday.enabled = not nightandday.enabled
					nightandday.callback(nightandday.enabled)
				end,
			},
			{
				name = "Global Audio",
				settingType = "Key",
				current = nil,
				id = "globalaudio",
				actionIndex = 9,
				callback = function()
					local globalaudio = altairValues.actions[9]
					globalaudio.enabled = not globalaudio.enabled
					globalaudio.callback(globalaudio.enabled)
				end,
			},
			{
				name = "Visibility",
				settingType = "Key",
				current = nil,
				id = "visibility",
				actionIndex = 10,
				callback = function()
					local visibility = altairValues.actions[10]
					visibility.enabled = not visibility.enabled
					visibility.callback(visibility.enabled)
				end,
			},
		},
	},
	{
		name = "Performance",
		description = "Tweak and test your performance settings for Roblox in Altair.",
		color = Color3.new(1, 0.376471, 0.168627),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Artificial FPS Limit",
				description = "Altair will automatically set your FPS to this number when you are tabbed-in to Roblox.",
				settingType = "Number",
				values = { 20, 5000 },
				current = 240,

				id = "fpscap",
			},
			{
				name = "Limit FPS while unfocused",
				description = "Altair will automatically set your FPS to 60 when you tab-out or unfocus from Roblox.",
				settingType = "Boolean", -- number for the cap below!! with min and max val
				current = true,

				id = "fpsunfocused",
			},
			{
				name = "Adaptive Latency Warning",
				description = "Altair will check your average latency in the background and notify you if your current latency significantly goes above your average latency.",
				settingType = "Boolean",
				current = true,

				id = "latencynotif",
			},
			{
				name = "Adaptive Performance Warning",
				description = "Altair will check your average FPS in the background and notify you if your current FPS goes below a specific number.",
				settingType = "Boolean",
				current = true,

				id = "fpsnotif",
			},
		},
	},
	{
		name = "Detections",
		description = "Altair detects and prevents anything malicious or possibly harmful to your wellbeing.",
		color = Color3.new(0.705882, 0, 0),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Suspicious Player Detection",
				description = "Detect sustained flight, hovering and fling-like physics from other players and notify you without taking action.",
				settingType = "Boolean",
				minimumLicense = "Free",
				current = true,

				id = "suspiciousplayerdetection",
			},
			{
				name = "Movement Detection Sensitivity",
				description = "Controls how much repeated movement evidence is required before Altair reports a potentially exploiting player.",
				settingType = "Number",
				minimumLicense = "Free",
				values = { 1, 100 },
				current = 55,

				id = "movementdetectionsensitivity",
			},
			{
				name = "Chat Spam Detection",
				description = "Detect likely chat spam using message frequency, duplicate text, repeated characters, caps, emojis, punctuation and message length.",
				settingType = "Boolean",
				minimumLicense = "Free",
				current = true,

				id = "chatspamdetection",
			},
			{
				name = "Anti-Spam Sensitivity",
				description = "Controls how aggressively Altair classifies chat as spam. Higher values catch spam sooner; lower values require stronger evidence.",
				settingType = "Number",
				minimumLicense = "Free",
				values = { 1, 100 },
				current = 60,

				id = "antispamsensitivity",
			},
			{
				name = "Spatial Shield",
				description = "Suppress loud sounds played from any audio source in-game, in real-time with Spatial Shield.",
				settingType = "Boolean",
				minimumLicense = "Pro",
				current = true,

				id = "spatialshield",
			},
			{
				name = "Spatial Shield Threshold",
				description = "How loud a sound needs to be to be suppressed.",
				settingType = "Number",
				minimumLicense = "Pro",
				values = { 100, 1000 },
				current = 300,

				id = "spatialshieldthreshold",
			},
			{
				name = "Moderator Detection",
				description = "Be notified whenever Altair detects a player joins your session that could be a game moderator.",
				settingType = "Boolean",
				minimumLicense = "Pro",
				current = true,

				id = "moddetection",
			},
			{
				name = "Intelligent HTTP Interception",
				description = "Block external HTTP/HTTPS requests from being sent/recieved and ask you before allowing it to run.",
				settingType = "Boolean",
				minimumLicense = "Essential",
				current = true,

				id = "intflowintercept",
			},
			{
				name = "Intelligent Clipboard Interception",
				description = "Block your clipboard from being set and ask you before allowing it to set your clipboard.",
				settingType = "Boolean",
				minimumLicense = "Essential",
				current = true,

				id = "intflowinterceptclip",
			},
		},
	},
	{
		name = "Logging",
		description = "Send logs to your specified webhook URL of things like player joins and leaves and messages.",
		color = Color3.new(0.905882, 0.780392, 0.0666667),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Log Messages",
				description = "Log messages sent by any player to your webhook.",
				settingType = "Boolean",
				current = false,

				id = "logmsg",
			},
			{
				name = "Message Webhook URL",
				description = "Discord Webhook URL",
				settingType = "Input",
				current = "No Webhook",

				id = "logmsgurl",
			},
			{
				name = "Log PlayerAdded and PlayerRemoving",
				description = "Log whenever any player leaves or joins your session.",
				settingType = "Boolean",
				current = false,

				id = "logplrjoinleave",
			},
			{
				name = "Player Added and Removing Webhook URL",
				description = "Discord Webhook URL",
				settingType = "Input",
				current = "No Webhook",

				id = "logplrjoinleaveurl",
			},
		},
	},
	{
		name = "Developer",
		description = "Development-only tooling for diagnosing Altair and custom scripts. This category is only shown when Altair Developer Tools is installed.",
		color = Color3.fromRGB(126, 104, 220),
		minimumLicense = "Free",
		categorySettings = {
			{
				name = "Debug Mode",
				description = "Loads Altair/Developer/AltairDevTools.lua. Disable it to unload every development watcher, recorder, bridge connection, and diagnostic resource.",
				settingType = "Boolean",
				current = false,
				id = "debugmode",
			},
			{
				name = "Record Session",
				description = "Record a bounded diagnostic session. Turning this off stops the recording and exports it to Altair/Developer/Captures. This toggle is transient and never persists across Altair launches.",
				settingType = "Boolean",
				current = false,
				persistent = false,
				id = "devrecord",
			},
			{
				name = "Run Self-Test",
				description = "Run the Developer Tools integrity and capability checks. The switch automatically returns to off when the test finishes.",
				settingType = "Boolean",
				current = false,
				persistent = false,
				id = "devselftest",
			},
			{
				name = "MCP Auto-Connect",
				description = "Keep the live MCP bridge connected for this Debug Mode session. This control appears only while an MCP companion is connected.",
				settingType = "Boolean",
				current = true,
				persistent = false,
				id = "devmcpauto",
			},
			{
				name = "Stream Observation Events",
				description = "Stream recorded observation events to the MCP companion while recording. Leave this off when you only need local capture files.",
				settingType = "Boolean",
				current = false,
				id = "devstream",
			},
			{
				name = "Recording Sample Rate",
				description = "State samples per second used by the next recording. Event-driven changes are captured immediately regardless of this value.",
				settingType = "Number",
				current = 8,
				values = { 1, 30 },
				id = "devsamplehz",
			},
			{
				name = "Event Buffer Capacity",
				description = "Total retained events for the next recording. Altair reserves independent critical/state/general lanes so noisy UI cannot evict diagnostics. Larger values improve 10+ minute captures but use more memory.",
				settingType = "Number",
				current = 30000,
				values = { 1000, 100000 },
				id = "deveventcap",
			},
		},
	},
}

-- Keep one natural-looking, distinct username/display-name pair for this session.
local randomUsername, randomDisplayName = (function()
	local names = { "Alex", "Avery", "Casey", "Drew", "Ellis", "Jamie", "Jules", "Kai", "Milo", "Morgan", "Noel", "Quinn", "Reese", "Riley", "Robin", "Rowan", "Sam", "Taylor", "Theo", "Luca", "Remy", "Sage", "Nico", "Finn", "Arlo", "Jesse", "Sky", "Blair", "River", "Ash", "Rey", "Cameron" }
	local words = { "cedar", "comet", "cove", "dusk", "echo", "fern", "finch", "frost", "grove", "harbor", "haze", "iris", "ivory", "jade", "juniper", "kestrel", "lagoon", "lark", "maple", "meadow", "moss", "nova", "orbit", "otter", "pebble", "pine", "raven", "reef", "ripple", "rover", "slate", "sparrow", "spruce", "stone", "summit", "tide", "timber", "vale", "willow", "wren", "aero", "cloud", "cobalt", "coral", "drift", "ember", "falcon", "flora", "glacier", "indigo", "lunar", "marble", "ocean", "olive", "opal", "panda", "pixel", "plum", "quartz", "satin", "solar", "sora", "sprout", "velvet" }
	local modifiers = { "quiet", "little", "sleepy", "soft", "small", "late", "lost", "mellow", "cozy", "blue", "silver", "warm", "wild", "still", "slow", "bright", "hidden", "wandering", "distant", "daily", "cloudy", "lucky", "gentle", "golden" }
	local surnames = { "Reed", "Lane", "Brooks", "Hayes", "Wells", "Blake", "Gray", "Cole", "Parker", "Reid", "West", "Hart", "Miles", "Hayden", "Stone", "Vale" }
	local starts = { "ka", "lu", "mi", "no", "ra", "se", "vi", "za", "a", "el", "ne", "ri", "so", "ta", "va", "yo" }
	local endings = { "ren", "lo", "ri", "ven", "ra", "lin", "no", "va", "len", "ro", "mi", "sei", "rin", "la", "vi", "on" }
	local function pick(list) return list[math.random(#list)] end
	local function title(word) return word:sub(1, 1):upper() .. word:sub(2) end
	local used = {}
	for _, player in ipairs(players:GetPlayers()) do
		used[player.Name:lower()] = true
		used[player.DisplayName:lower()] = true
	end
	local function generate()
		local first, word, second = pick(names), pick(words), pick(words)
		local style = math.random(10)
		local username
		if style == 1 then username = first .. pick(surnames)
		elseif style == 2 then username = pick(modifiers) .. title(word)
		elseif style == 3 then username = word .. title(second)
		elseif style == 4 then username = word .. tostring(math.random(10, 999))
		elseif style == 5 then username = first .. "_" .. word
		elseif style == 6 then username = pick(starts) .. pick(endings) .. pick(endings)
		elseif style == 7 then username = "its" .. first
		elseif style == 8 then username = word .. "_" .. second
		elseif style == 9 then username = first:sub(1, 1) .. pick(surnames) .. tostring(math.random(10, 99))
		else username = pick(modifiers) .. title(word) .. tostring(math.random(2, 99)) end
		if math.random(3) ~= 1 then username = username:lower() end
		local displayStyle = math.random(6)
		local displayName
		if displayStyle == 1 then displayName = first
		elseif displayStyle == 2 then displayName = title(word)
		elseif displayStyle == 3 then displayName = title(pick(words))
		elseif displayStyle == 4 then displayName = pick(names) .. " " .. pick(surnames):sub(1, 1) .. "."
		elseif displayStyle == 5 then displayName = pick(modifiers) .. " " .. pick(words)
		else displayName = title(pick(starts) .. pick(endings)) end
		return username, displayName
	end
	local username, displayName
	repeat username, displayName = generate()
	until username:lower() ~= displayName:lower() and not used[username:lower()] and not used[displayName:lower()]
	return username, displayName
end)()

-- Initialise Altair Client Interface
local guiParent = getHiddenUI and getHiddenUI() or (useStudio and localPlayer:WaitForChild("PlayerGui")) or coreGui

local function loadInterface()
	if useStudio then
		local container = script.Parent
		return container and container:FindFirstChild(altairValues.altairName)
	end
	local objects = game:GetObjects("rbxassetid://" .. altairValues.interfaceAsset)
	local root = objects and objects[1]
	for _, object in ipairs(objects or {}) do if object ~= root then object:Destroy() end end
	return root
end

local uiResult, uiError
for attempt = 1, 3 do
	local success, result = pcall(loadInterface)
	if success and result then
		uiResult = result
		break
	end
	uiError = success and "the interface asset returned nothing" or tostring(result)
	if attempt < 3 then
		task.wait(attempt)
	end
end

if not uiResult then
	warn("Altair | Couldn't load the interface asset after 3 attempts (" .. tostring(uiError) .. "). Altair has not started.")
	return
end

-- One owner for runtime resources; identifiers are not used to find them again.
altairValues.lifecycle = { alive = true, objects = {}, globals = {}, audio = {} }
function altairValues.lifecycle:own(object)
	object.Name = httpService:GenerateGUID(false)
	self.objects[object] = true
	object.Destroying:Once(function() self.objects[object] = nil end)
	return object
end
function altairValues.lifecycle:replaceGlobal(key, value)
	self.globals[key] = { before = env[key], installed = value }
	env[key] = value
end
function altairValues.lifecycle:unload()
	if not self.alive then return end
	self.alive = false
	if self.runtimeCleanup then pcall(self.runtimeCleanup) end
	for _, connection in ipairs(connections) do pcall(connection.Disconnect, connection) end
	table.clear(connections)
	for key, replacement in pairs(self.globals) do
		if env[key] == replacement.installed then env[key] = replacement.before end
	end
	table.clear(self.globals)
	for object in pairs(self.objects) do pcall(object.Destroy, object) end
	table.clear(self.objects)
	table.clear(self.audio)
	if self.api and env.Altair == self.api then env.Altair = nil end
end

-- Bounded session activity; teleport settings stay local to this Roblox session.
altairValues.activity = { items = {}, revision = 0, key = "Altair.Activity.v1" }
do
	local activity = altairValues.activity
	local ok, saved = pcall(teleportService.GetTeleportSetting, teleportService, activity.key)
	if ok and type(saved) == "table" and saved.universe == game.GameId and type(saved.items) == "table" then
		for _, item in ipairs(saved.items) do
			if #activity.items >= 30 then break end
			if type(item) == "table" and type(item.title) == "string" and #item.title <= 160
				and type(item.description) == "string" and #item.description <= 320
				and type(item.time) == "number" and item.time <= os.time() and item.time >= 0 then
				table.insert(activity.items, {title=item.title, description=item.description, time=item.time,
					icon="rbxassetid://7733734848"})
			end
		end
		activity.previousJob = saved.job
	end
	function activity:save()
		pcall(teleportService.SetTeleportSetting, teleportService, self.key,
			{universe=game.GameId, job=game.JobId, items=self.items})
	end
	function activity:record(title, description, icon)
		if not altairValues.lifecycle.alive or type(title) ~= "string" or title == "" then return false end
		table.insert(self.items, 1, {title=title:sub(1,160), description=tostring(description or ""):sub(1,320),
			icon=type(icon) == "string" and icon or "rbxassetid://7733734848", time=os.time()})
		if #self.items > 30 then table.remove(self.items) end
		self.revision += 1
		self:save()
		return true
	end
end

local UI = altairValues.lifecycle:own(uiResult)
UI.Destroying:Once(function() altairValues.lifecycle:unload() end)
espContainer = altairValues.lifecycle:own(Instance.new("Folder"))
espContainer.Parent = guiParent
UI.Enabled = false -- Never render the asset at its authored position.
UI.Parent = guiParent

-- Volt/CoreGui: use the full physical viewport, not Roblox top-bar / safe-area insets.
-- Do this immediately so every later AbsolutePosition/AbsoluteSize read uses the
-- same coordinate space as Rayfield Gen 2.
if UI:IsA("ScreenGui") then
	UI.IgnoreGuiInset = true
	pcall(function() UI.ScreenInsets = Enum.ScreenInsets.None end)
	pcall(function() UI.ClipToDeviceSafeArea = false end)
end

UI.Enabled = false

-- Create Variables for Interface Elements
local characterPanel = UI.Character
local openHome, closeHome
local homeOpen, homeFov = false, nil
local closeSettings, closeScriptSearch
local homeChatEnabled
local characterPanelSize = characterPanel.Size
local customScriptPrompt = UI.CustomScriptPrompt
local disconnectedPrompt = UI.Disconnected
local gameDetectionPrompt = UI.GameDetection
local homeContainer = UI.Home
local moderatorDetectionPrompt = UI.ModeratorDetectionPrompt
local notificationContainer = UI.Notifications
local playerlistPanel = UI.Playerlist
altairValues.playerlistUI = altairValues.playerlistUI or {}
altairValues.playerlistUI.panelSize = playerlistPanel.Size
local playerSearch = playerlistPanel.Interactions.SearchFrame.SearchBox
local scriptSearch = UI.ScriptSearch
local scriptsPanel = UI.Scripts
local settingsPanel = UI.Settings
local smartBar = UI.SmartBar
local drag = UI.Drag
local toastsContainer = UI.Toasts

altairValues.cachedInGameUI = {}
altairValues.cachedCoreUI = {}

local indexSetClipboard = "setclipboard"

local index = (http_request and "http_request") or "request"
local rawRequest = optional(env.request) or optional(env.http_request) or optional(env.http and env.http.request) or optional(env.syn and env.syn.request) or optional(env.fluxus and env.fluxus.request) or optional(request) or optional(http_request)

-- Read legacy originals once, then keep them local rather than in shared globals.
local originalRequest = optional(type(env.altairOriginals) == "table" and env.altairOriginals.request) or rawRequest
local originalSetClipboard = optional(type(env.altairOriginals) == "table" and env.altairOriginals.setclipboard) or optional(env[indexSetClipboard])
env.altairOriginals = nil

if not legacyChatActive then
	altairValues.chatSpy.enabled = false
end

-- Call External Modules

-- httpRequest
local httpRequest = originalRequest

local function track(connection)
	if not altairValues.lifecycle.alive then connection:Disconnect(); return connection end
	table.insert(connections, connection)
	return connection
end

local function replacePlain(haystack, needleLower, replacement)
	if needleLower == "" then
		return haystack
	end

	local lowered = string.lower(haystack)
	local out, cursor = {}, 1

	while true do
		local startIndex, endIndex = string.find(lowered, needleLower, cursor, true)
		if not startIndex then
			break
		end

		table.insert(out, string.sub(haystack, cursor, startIndex - 1))
		table.insert(out, replacement)
		cursor = endIndex + 1
	end

	if cursor == 1 then
		return haystack
	end

	table.insert(out, string.sub(haystack, cursor))
	return table.concat(out)
end

local function truncateForDisplay(value, limit)
	local text = tostring(value)
	limit = limit or 24
	if #text <= limit then
		return text
	end
	return string.sub(text, 1, limit - 2) .. ".."
end

local function keyCodeFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local success, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)
	return success and keyCode or nil
end

local function applyActionVisual(action, object)
	if not (action and object) then
		return
	end

	local quickToggle = object.Parent == characterPanel.Interactions.Toggles
	object.Icon.Image = "rbxassetid://" .. action.images[action.enabled and 1 or 2]
	if quickToggle then
		object.Subtitle.Text = action.enabled and "Enabled" or "Disabled"
	end
	if not characterPanel.Visible or debounce then return end
	if quickToggle then
		tweenService:Create(object.Subtitle, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = action.enabled and 0 or 0.25 }):Play()
		tweenService:Create(object.Glow, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0.15 or 0.8 }):Play()
	end
	tweenService:Create(object, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundTransparency = action.enabled and 0.02 or (quickToggle and 0.12 or 0.1) }):Play()
	tweenService:Create(object.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Transparency = action.enabled and 0.3 or (quickToggle and 0.32 or 0.91) }):Play()
	tweenService:Create(object.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0 or 0.15 }):Play()
	tweenService:Create(object.Title, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
end

local function checkAltair()
	return altairValues.lifecycle.alive and UI.Parent
end

local function getPing()
	local success, ping = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return success and math.clamp(ping, 10, 700) or 0
end

local function checkFolder()
	if not (isfolder and makefolder) then
		return
	end

	local root = altairValues.altairFolder
	local customRoot = root .. "/" .. altairValues.customScriptsFolder
	local scriptsRoot = root .. "/" .. altairValues.scriptsFolder

	for _, path in ipairs({
		root,
		root .. "/Assets",
		root .. "/Assets/Icons",
		customRoot,
		scriptsRoot,
	}) do
		if not isfolder(path) then
			makefolder(path)
		end
	end

	if writefile and isfile and not isfile(customRoot .. "/README.txt") then
		writefile(customRoot .. "/README.txt", [[Altair Custom Scripts

The files in this folder are DETECTION DEFINITIONS. Each definition can use
either a remote Loadstring URL or a local .lua file stored in Altair/Scripts.

REMOTE SCRIPT:
{
    "ScriptTitle": "Example Script",
    "ScriptSubtitle": "Shown underneath the script title",
    "PlaceIds": [123456789],
    "Loadstring": "https://raw.githubusercontent.com/user/repo/refs/heads/main/script.lua"
}

Loadstring must contain the RAW URL only. Altair executes it as:
loadstring(game:HttpGet(url))()

LOCAL LUA FILE:
{
    "ScriptTitle": "Example Script",
    "ScriptSubtitle": "Shown underneath the script title",
    "PlaceIds": [123456789],
    "LuaFile": "Example.lua"
}

Put local runnable files here:
Altair/Scripts/Example.lua

Accepted aliases:
- ScriptTitle: Title or Name
- ScriptSubtitle: Subtitle or Description
- PlaceIds: Games or PlaceId
- Loadstring: Url or URL
- LuaFile: ScriptFile or File

If both Loadstring and LuaFile are supplied, Loadstring is used first.
]])
	end

	if writefile and isfile and not isfile(scriptsRoot .. "/README.txt") then
		writefile(scriptsRoot .. "/README.txt", [[Altair Scripts

Place runnable .lua files in this folder.

Reference them from a file in Altair/Custom Scripts with:
"LuaFile": "YourScript.lua"
]])
	end
end

local function isPanel(name)
	return name == "Character" or name == "Scripts" or name == "Playerlist"
end

local function undoAnonymousChanges()
	local masked = altairValues.anonymousMaskedText
	for element, originalText in pairs(originalTextValues) do
		if element.Parent and (not masked or element.Text == masked[element]) then
			element.Text = originalText
		end
	end
	if masked then table.clear(masked) end
end

local function isHighlightEnabledFor(playerName)
	return altairValues.actions[7].enabled or locatedPlayers[playerName] == true
end

local function createEsp(player)
	if not player or not checkAltair() then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.Adornee = player.Character
	highlight.Name = player.Name
	highlight.Enabled = isHighlightEnabledFor(player.Name)
	highlight.Parent = espContainer

	if espConnections[player] then
		espConnections[player]:Disconnect()
	end
	espConnections[player] = player.CharacterAdded:Connect(function(character)
		if not checkAltair() then
			return
		end
		task.wait()
		highlight.Adornee = character
	end)
end

local function makeDraggable(object)
	local dragging = false
	local relative = nil

	local offset = Vector2.zero
	local screenGui = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui and screenGui.IgnoreGuiInset then
		offset += guiService:GetGuiInset()
	end

	object.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			relative = object.AbsolutePosition + object.AbsoluteSize * object.AnchorPoint - userInputService:GetMouseLocation()
			dragging = true
		end
	end)

	local inputEnded = userInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			dragging = false
		end
	end)

	local renderStepped = runService.RenderStepped:Connect(function()
		if dragging then
			local position = userInputService:GetMouseLocation() + relative + offset
			object.Position = UDim2.fromOffset(position.X, position.Y)
		end
	end)

	object.Destroying:Connect(function()
		inputEnded:Disconnect()
		renderStepped:Disconnect()
	end)
end

local function actionButton(action)
	if not action then
		return nil
	end
	return characterPanel.Interactions.Toggles:FindFirstChild(action.name) or characterPanel.Interactions.Grid:FindFirstChild(action.name)
end

local function checkSetting(settingTarget, categoryTarget)
	altairValues.settingIndex = altairValues.settingIndex or {}
	local key = tostring(categoryTarget or "*") .. "\0" .. tostring(settingTarget)
	local cached = altairValues.settingIndex[key]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end

	for _, category in ipairs(altairSettings) do
		if not categoryTarget or category.name == categoryTarget then
			for _, setting in ipairs(category.categorySettings) do
				if setting.name == settingTarget then
					altairValues.settingIndex[key] = setting
					return setting
				end
			end
		end
	end

	altairValues.settingIndex[key] = false
	return nil
end

local function settingValue(settingTarget, fallback)
	local setting = checkSetting(settingTarget)
	if setting == nil or setting.current == nil then
		return fallback
	end
	return setting.current
end

local function wipeTransparency(ins, target, checkSelf, tween, duration)
	local transparencyProperties = altairValues.transparencyProperties

	local function applyTransparency(obj)
		local properties = transparencyProperties[obj.ClassName]

		if properties then
			local tweenProperties = {}

			for _, property in ipairs(properties) do
				tweenProperties[property] = target
			end

			for property, transparency in pairs(tweenProperties) do
				if tween then
					tweenService:Create(obj, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { [property] = transparency }):Play()
				else
					obj[property] = transparency
				end
			end
		end
	end

	if checkSelf then
		applyTransparency(ins)
	end

	for _, descendant in ipairs(ins:GetDescendants()) do
		applyTransparency(descendant)
	end
end

local function blurSignature(value)
	local owner = altairValues.lifecycle
	if not value then
		if owner.blur then owner.blur:Destroy(); owner.blur = nil end
	elseif owner.alive and not owner.blur then
		local blurLight = owner:own(Instance.new("DepthOfFieldEffect"))
		owner.blur = blurLight
		blurLight.Enabled = true
		blurLight.FarIntensity = 0
		blurLight.FocusDistance = 51.6
		blurLight.InFocusRadius = 50
		blurLight.NearIntensity = 0.8
		blurLight.Parent = lighting
	end
end

local function figureNotifications()
	if checkAltair() then
		local notificationsSize = 0

		if #notifications > 0 then
			blurSignature(true)
		else
			blurSignature(false)
		end

		for i = #notifications, 1, -1 do
			local notification = notifications[i]
			if notification then
				if notificationsSize == 0 then
					notificationsSize = notification.Size.Y.Offset + 2
				else
					notificationsSize += notification.Size.Y.Offset + 5
				end
				local desiredPosition = UDim2.new(0.5, 0, 0, notificationsSize)
				if notification.Position ~= desiredPosition then
					notification:TweenPosition(desiredPosition, "Out", "Quint", 0.8, true)
				end
			end
		end
	end
end

local function queueNotification(Title, Description, Image)
	task.spawn(function()
		if checkAltair() then
			local newNotification = notificationContainer.Template:Clone()
			newNotification.Parent = notificationContainer
			newNotification.Name = Title or "Unknown Title"
			newNotification.Visible = true

			newNotification.Title.Text = Title or "Unknown Title"
			newNotification.Description.Text = Description or "Unknown Description"

			-- Prepare for animation
			newNotification.AnchorPoint = Vector2.new(0.5, 1)
			newNotification.Position = UDim2.new(0.5, 0, -1, 0)
			newNotification.Size = UDim2.new(0, 320, 0, 500)
			newNotification.Description.Size = UDim2.new(0, 241, 0, 400)
			wipeTransparency(newNotification, 1, true)

			newNotification.Description.Size = UDim2.new(0, 241, 0, newNotification.Description.TextBounds.Y)
			newNotification.Size = UDim2.new(0, 100, 0, newNotification.Description.TextBounds.Y + 50)

			table.insert(notifications, newNotification)
			figureNotifications()

			local notificationSound = Instance.new("Sound")
			notificationSound.Parent = UI
			notificationSound.SoundId = "rbxassetid://255881176"
			notificationSound.Name = "notificationSound"
			notificationSound.Volume = 0.65
			notificationSound.PlayOnRemove = true
			notificationSound:Destroy()

			if tonumber(Image) then
				newNotification.Icon.Image = "rbxassetid://" .. tostring(Image)
			elseif type(Image) == "string" and Image ~= "" then
				newNotification.Icon.Image = Image
			else
				newNotification.Icon.Image = "rbxassetid://14317577326"
			end

			newNotification:TweenPosition(UDim2.new(0.5, 0, 0, newNotification.Size.Y.Offset + 2), "Out", "Quint", 0.9, true)
			task.wait(0.1)
			tweenService:Create(newNotification, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), { Size = UDim2.new(0, 320, 0, newNotification.Description.TextBounds.Y + 50) }):Play()
			task.wait(0.05)
			tweenService:Create(newNotification, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.35 }):Play()
			tweenService:Create(newNotification.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), { Transparency = 0.7 }):Play()
			task.wait(0.05)
			tweenService:Create(newNotification.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { ImageTransparency = 0 }):Play()
			task.wait(0.04)
			tweenService:Create(newNotification.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { TextTransparency = 0 }):Play()
			task.wait(0.04)
			tweenService:Create(newNotification.Description, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { TextTransparency = 0.15 }):Play()

			newNotification.Interact.MouseButton1Click:Connect(function()
				local foundNotification = table.find(notifications, newNotification)
				if foundNotification then
					table.remove(notifications, foundNotification)
				end

				tweenService
					:Create(newNotification, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1.5, 0, 0, newNotification.Position.Y.Offset) })
					:Play()

				task.wait(0.4)
				newNotification:Destroy()
				figureNotifications()
				return
			end)

			local waitTime = (#newNotification.Description.Text * 0.1) + 2
			if waitTime <= 1 then
				waitTime = 2.5
			elseif waitTime > 10 then
				waitTime = 10
			end

			task.wait(waitTime)

			local foundNotification = table.find(notifications, newNotification)
			if foundNotification then
				table.remove(notifications, foundNotification)
			end

			tweenService:Create(newNotification, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1.5, 0, 0, newNotification.Position.Y.Offset) }):Play()

			task.wait(1.2)
			newNotification:Destroy()
			figureNotifications()
		end
	end)
end

function altairValues.playerAnomaly:headshot(player)
	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150"
end

function altairValues.playerAnomaly:notify(player, kind, detail, evidence, threshold)
	local record = self.users[player.UserId]
	if not record then
		return
	end

	local now = os.clock()
	record.lastAlerts = record.lastAlerts or {}
	if now - (record.lastAlerts[kind] or 0) < 30 then
		return
	end
	record.lastAlerts[kind] = now

	local confidence = math.clamp(
		math.floor(68 + math.max(0, evidence - threshold) * 5 + (evidence / math.max(threshold, 0.01)) * 9),
		72,
		99
	)

	queueNotification(
		"Possible Exploit Detected",
		player.DisplayName
			.. " (@"
			.. player.Name
			.. ") shows "
			.. detail
			.. " ("
			.. tostring(confidence)
			.. "% confidence).",
		self:headshot(player)
	)
end

function altairValues.playerAnomaly:samplePlayer(player, now)
	if player == localPlayer then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and (
		character:FindFirstChild("HumanoidRootPart")
		or character.PrimaryPart
	)

	if not humanoid or not root or humanoid.Health <= 0 or not root:IsA("BasePart") then
		self.users[player.UserId] = nil
		return
	end

	local record = self.users[player.UserId]
	if not record then
		record = {
			lastPosition = root.Position,
			lastSample = now,
			airSince = nil,
			flyEvidence = 0,
			flingEvidence = 0,
			flyLatched = false,
			flingLatched = false,
			lastAlerts = {},
		}
		self.users[player.UserId] = record
		return
	end

	local dt = math.clamp(now - (record.lastSample or now), 0.05, 1)
	local position = root.Position
	local delta = position - (record.lastPosition or position)
	local velocity = root.AssemblyLinearVelocity
	local angular = root.AssemblyAngularVelocity
	local state = humanoid:GetState()

	record.lastPosition = position
	record.lastSample = now

	local excludedState =
		humanoid.Sit
		or humanoid.SeatPart ~= nil
		or state == Enum.HumanoidStateType.Seated
		or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Dead

	if excludedState then
		record.airSince = nil
		record.flyEvidence = math.max(0, record.flyEvidence - 2)
		record.flingEvidence = math.max(0, record.flingEvidence - 2)
		return
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if grounded then
		record.airSince = nil
	else
		record.airSince = record.airSince or now
	end

	local airTime = record.airSince and (now - record.airSince) or 0
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local verticalVelocity = velocity.Y
	local linearSpeed = velocity.Magnitude
	local angularSpeed = angular.Magnitude

	local horizontalDelta = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	local verticalDelta = math.abs(delta.Y) / dt

	local flyAdded = 0

	if not grounded and airTime >= 2.75 then
		if math.abs(verticalVelocity) <= 4.5 then
			flyAdded += 0.9
		end

		if horizontalVelocity >= 14 and math.abs(verticalVelocity) <= 11 then
			flyAdded += 0.75
		end

		if horizontalDelta >= 15 and verticalDelta <= 12 then
			flyAdded += 0.55
		end

		if root.Anchored and airTime >= 2 then
			flyAdded += 1.1
		end

		if humanoid.PlatformStand and math.abs(verticalVelocity) <= 7 then
			flyAdded += 0.45
		end
	end

	if not grounded and airTime >= 1.5 and verticalVelocity >= 70 then
		flyAdded += 0.4
	end

	if flyAdded > 0 then
		record.flyEvidence = math.min(20, record.flyEvidence + flyAdded)
	else
		record.flyEvidence = math.max(0, record.flyEvidence - 0.7)
	end

	local flingAdded = 0

	if angularSpeed >= 220 then
		flingAdded += 3.2
	elseif angularSpeed >= 110 and linearSpeed >= 55 then
		flingAdded += 2.2
	elseif angularSpeed >= 65 and linearSpeed >= 95 then
		flingAdded += 1.65
	elseif angularSpeed >= 45 and linearSpeed >= 150 then
		flingAdded += 1.2
	end

	if linearSpeed >= 240 and angularSpeed >= 35 then
		flingAdded += 0.9
	end

	if flingAdded > 0 then
		record.flingEvidence = math.min(20, record.flingEvidence + flingAdded)
	else
		record.flingEvidence = math.max(0, record.flingEvidence - 1.15)
	end

	local sensitivity = math.clamp(
		tonumber(settingValue("Movement Detection Sensitivity", 55)) or 55,
		1,
		100
	)

	local flyThreshold = math.clamp(10.2 - ((sensitivity - 50) * 0.045), 7.5, 12.4)
	local flingThreshold = math.clamp(6.8 - ((sensitivity - 50) * 0.03), 5.2, 8.4)

	if record.flyEvidence >= flyThreshold then
		if not record.flyLatched then
			record.flyLatched = true
			self:notify(
				player,
				"flight",
				"sustained flight/hover-like movement",
				record.flyEvidence,
				flyThreshold
			)
		end
	elseif record.flyEvidence <= flyThreshold * 0.28 then
		record.flyLatched = false
	end

	if record.flingEvidence >= flingThreshold then
		if not record.flingLatched then
			record.flingLatched = true
			self:notify(
				player,
				"fling",
				"fling-like rotational physics",
				record.flingEvidence,
				flingThreshold
			)
		end
	elseif record.flingEvidence <= flingThreshold * 0.22 then
		record.flingLatched = false
	end
end

function altairValues.playerAnomaly:sampleAll()
	if not settingValue("Suspicious Player Detection", true) then
		table.clear(self.users)
		return
	end

	local now = os.clock()
	for _, player in ipairs(players:GetPlayers()) do
		local ok = pcall(self.samplePlayer, self, player, now)
		if not ok then
			self.users[player.UserId] = nil
		end
	end
end

function altairValues.chatModeration:emojiCount(value)
	local count = 0
	pcall(function()
		for _, codepoint in utf8.codes(value) do
			if
				(codepoint >= 0x1F300 and codepoint <= 0x1FAFF)
				or (codepoint >= 0x2600 and codepoint <= 0x26FF)
				or (codepoint >= 0x2700 and codepoint <= 0x27BF)
				or (codepoint >= 0x1F1E6 and codepoint <= 0x1F1FF)
			then
				count += 1
			end
		end
	end)
	return count
end

function altairValues.chatModeration:observe(player, message)
	if not settingValue("Chat Spam Detection", true) or not player or player == localPlayer or type(message) ~= "string" then
		return
	end

	local cleaned = message:gsub("[\r\n\t]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	if cleaned == "" then
		return
	end

	local now = os.clock()
	local id = player.UserId
	local record = self.users[id]
	if not record then
		record = {
			history = {},
			lastAlert = 0,
			lastSeen = "",
			lastSeenAt = 0,
			lastScore = 0,
			flaggedUntil = 0,
		}
		self.users[id] = record
	end

	local lower = cleaned:lower()
	if record.lastSeen == lower and now - record.lastSeenAt < 0.18 then
		return
	end
	record.lastSeen = lower
	record.lastSeenAt = now

	local history = record.history
	for index = #history, 1, -1 do
		if now - history[index].time > 15 then
			table.remove(history, index)
		end
	end

	local score = 0
	local reasons = {}
	local function add(points, reason)
		score += points
		if reason and not table.find(reasons, reason) then
			table.insert(reasons, reason)
		end
	end

	local charCount = utf8.len(cleaned) or #cleaned
	local letters = 0
	local capitals = 0
	for char in cleaned:gmatch("%a") do
		letters += 1
		if char:match("%u") then
			capitals += 1
		end
	end

	if letters >= 8 then
		local ratio = capitals / letters
		if ratio >= 0.95 then
			add(18, "almost all caps")
		elseif ratio >= 0.8 then
			add(13, "heavy caps")
		elseif ratio >= 0.65 then
			add(8, "high caps")
		end
	end

	local emojiCount = self:emojiCount(cleaned)
	if emojiCount >= 4 and charCount > 0 then
		local ratio = emojiCount / charCount
		if ratio >= 0.55 then
			add(17, "emoji-heavy")
		elseif ratio >= 0.3 then
			add(11, "many emojis")
		elseif emojiCount >= 8 then
			add(8, "many emojis")
		end
	end

	if charCount >= 190 then
		add(11, "very long messages")
	elseif charCount >= 140 then
		add(6, "long messages")
	end

	local punctuation = select(2, cleaned:gsub("[!%?%.]", ""))
	if punctuation >= 12 then
		add(12, "excessive punctuation")
	elseif punctuation >= 7 then
		add(7, "heavy punctuation")
	end

	local links = select(2, lower:gsub("https?://", ""))
	if links >= 2 then
		add(12, "multiple links")
	elseif links == 1 and charCount < 45 then
		add(5, "link repetition risk")
	end

	local mentions = select(2, cleaned:gsub("@[%w_]+", ""))
	if mentions >= 4 then
		add(10, "mass mentions")
	elseif mentions >= 2 then
		add(5, "multiple mentions")
	end

	local longestRun = 1
	local currentRun = 1
	local previous = ""
	for index = 1, #cleaned do
		local byte = cleaned:sub(index, index)
		if byte == previous and byte ~= " " then
			currentRun += 1
			if currentRun > longestRun then
				longestRun = currentRun
			end
		else
			currentRun = 1
			previous = byte
		end
	end
	if longestRun >= 10 then
		add(18, "repeated characters")
	elseif longestRun >= 6 then
		add(11, "repeated characters")
	end

	local wordCounts = {}
	local maxWordRepeats = 0
	for word in lower:gmatch("[%w']+") do
		if #word >= 2 then
			wordCounts[word] = (wordCounts[word] or 0) + 1
			if wordCounts[word] > maxWordRepeats then
				maxWordRepeats = wordCounts[word]
			end
		end
	end
	if maxWordRepeats >= 6 then
		add(16, "repeated words")
	elseif maxWordRepeats >= 4 then
		add(10, "repeated words")
	end

	local fingerprint = lower:gsub("[%s%p_]", "")
	if fingerprint == "" then
		fingerprint = lower
	end

	local duplicates = 0
	local sixSecondCount = 1
	local twoSecondCount = 1
	for _, item in ipairs(history) do
		local age = now - item.time
		if age <= 6 then
			sixSecondCount += 1
		end
		if age <= 2 then
			twoSecondCount += 1
		end
		if age <= 15 and (item.text == lower or (#fingerprint >= 4 and item.fingerprint == fingerprint)) then
			duplicates += 1
		end
	end

	if duplicates >= 3 then
		add(45, "repeated messages")
	elseif duplicates == 2 then
		add(32, "repeated messages")
	elseif duplicates == 1 then
		add(18, "duplicate message")
	end

	if sixSecondCount >= 8 then
		add(45, "rapid messages")
	elseif sixSecondCount >= 6 then
		add(28, "rapid messages")
	elseif sixSecondCount >= 4 then
		add(12, "rapid messages")
	end

	if twoSecondCount >= 4 then
		add(22, "message burst")
	elseif twoSecondCount >= 3 then
		add(16, "message burst")
	end

	if charCount <= 3 and sixSecondCount >= 5 then
		add(10, "repeated short messages")
	end

	score = math.clamp(math.floor(score + 0.5), 0, 100)
	record.lastScore = score

	table.insert(history, {
		time = now,
		text = lower,
		fingerprint = fingerprint,
	})
	while #history > self.maxHistory do
		table.remove(history, 1)
	end

	local sensitivity = math.clamp(tonumber(settingValue("Anti-Spam Sensitivity", 60)) or 60, 1, 100)
	local threshold = math.clamp(92 - (sensitivity * 0.55), 35, 85)

	if score < threshold then
		return
	end

	record.flaggedUntil = math.max(record.flaggedUntil, now + math.clamp(5 + score * 0.12, 8, 20))

	if now - record.lastAlert < self.alertCooldown then
		return
	end
	record.lastAlert = now

	local reasonText
	if #reasons == 0 then
		reasonText = "message pattern"
	else
		local shown = {}
		for index = 1, math.min(3, #reasons) do
			table.insert(shown, reasons[index])
		end
		reasonText = table.concat(shown, ", ")
	end

	queueNotification(
		"Chat Spam Detected",
		player.DisplayName .. " (@" .. player.Name .. ") scored " .. tostring(score) .. "/100 for likely spam: " .. reasonText .. ".",
		4384400106
	)
end

-- Rainbow Mode
do
	local bar, hue, enabled = UI.SmartBar, 0, false
	local dragVisual = drag:FindFirstChild("Drag")
	local dragColor = dragVisual and (dragVisual:IsA("ImageLabel") or dragVisual:IsA("ImageButton"))
		and dragVisual.ImageColor3
		or (dragVisual and dragVisual:IsA("GuiObject") and dragVisual.BackgroundColor3)
	local toastColors = setmetatable({}, {__mode = "k"})
	local borderColors = setmetatable({}, { __mode = "k" })
	local rainbowAccumulator = 0
	local rainbowInterval = 1 / 20
	altairValues.rainbowPlayerRows = altairValues.rainbowPlayerRows or setmetatable({}, { __mode = "k" })

	local playerlistBaseFillSequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(54, 31, 111)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(31, 51, 91)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 34, 51)),
	})
	local playerlistBaseStrokeSequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(123, 71, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(31, 51, 91)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 171, 255)),
	})

	local function ensurePlayerlistGradient(root, name)
		if not root then
			return nil
		end

		local gradient = root:FindFirstChildOfClass("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = name
			gradient.Parent = root
		end
		gradient.Enabled = true
		return gradient
	end

	local function ensurePlayerlistStrokeGradient(stroke)
		if not stroke or not stroke:IsA("UIStroke") then
			return nil
		end

		stroke.Color = Color3.new(1, 1, 1)

		local gradient = stroke:FindFirstChildOfClass("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "AltairPlayerlistStrokeGradient"
			gradient.Parent = stroke
		end
		gradient.Enabled = true
		return gradient
	end

	local function applyPlayerlistBase(root)
		if not root or not root:IsA("GuiObject") then
			return
		end

		if root:IsA("Frame")
			or root:IsA("TextLabel")
			or root:IsA("TextButton")
			or root:IsA("TextBox")
		then
			root.BackgroundColor3 = Color3.new(1, 1, 1)
		elseif root:IsA("ImageLabel") or root:IsA("ImageButton") then
			root.ImageColor3 = Color3.new(1, 1, 1)
		end

		local gradient = ensurePlayerlistGradient(root, "AltairPlayerlistBackgroundGradient")
		if gradient then
			gradient.Color = playerlistBaseFillSequence
		end

		local stroke = root:FindFirstChildOfClass("UIStroke")
		if stroke then
			local strokeGradient = ensurePlayerlistStrokeGradient(stroke)
			if strokeGradient then
				strokeGradient.Color = playerlistBaseStrokeSequence
			end
		end
	end

	altairValues.registerRainbowPlayerRow = function(row)
		if not row or row:GetAttribute("AltairRuntimePlayer") ~= true then
			return
		end
		local state = {
			gradient = ensurePlayerlistGradient(row, "AltairPlayerlistBackgroundGradient"),
			stroke = row:FindFirstChildOfClass("UIStroke"),
			statusDot = row:FindFirstChild("StatusDot", true),
		}
		if state.stroke then
			state.strokeGradient = ensurePlayerlistStrokeGradient(state.stroke)
		end
		altairValues.rainbowPlayerRows[row] = state
	end

	local function applyPlayerlistRainbow(hue)
		if not playerlistPanel
			or not playerlistPanel:FindFirstChild("Interactions")
		then
			return
		end

		local fillSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, 0.58, 0.56)),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV(hue, 0.64, 0.43)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, 0.68, 0.31)),
		})

		local strokeSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, 0.64, 0.98)),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV(hue, 0.68, 0.84)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, 0.72, 0.72)),
		})

		local dotColor = Color3.fromHSV(hue, 0.62, 0.82)
		local interactions = playerlistPanel.Interactions

		for row, state in pairs(altairValues.rainbowPlayerRows) do
			if not row.Parent then
				altairValues.rainbowPlayerRows[row] = nil
			else
				if row:IsA("Frame")
					or row:IsA("TextLabel")
					or row:IsA("TextButton")
					or row:IsA("TextBox")
				then
					row.BackgroundColor3 = Color3.new(1, 1, 1)
				end
				if state.gradient then
					state.gradient.Color = fillSequence
				end
				if state.strokeGradient then
					state.strokeGradient.Color = strokeSequence
				end
				local statusDot = state.statusDot
				if statusDot and statusDot.Parent then
					if statusDot:IsA("Frame") then
						statusDot.BackgroundColor3 = dotColor
					elseif statusDot:IsA("ImageLabel") or statusDot:IsA("ImageButton") then
						statusDot.ImageColor3 = dotColor
					end
				end
			end
		end

		local profile = interactions:FindFirstChild("SelectedPlayer")
		if profile then
			if profile:IsA("Frame") then
				profile.BackgroundColor3 = Color3.new(1, 1, 1)
			end

			local profileGradient = ensurePlayerlistGradient(profile, "AltairPlayerlistBackgroundGradient")
			if profileGradient then
				profileGradient.Color = fillSequence
			end

			local profileStroke = profile:FindFirstChildOfClass("UIStroke")
			if profileStroke then
				local strokeGradient = ensurePlayerlistStrokeGradient(profileStroke)
				if strokeGradient then
					strokeGradient.Color = strokeSequence
				end
			end
		end
	end

	local function restorePlayerlistRainbow()
		if not playerlistPanel
			or not playerlistPanel:FindFirstChild("Interactions")
		then
			return
		end

		local interactions = playerlistPanel.Interactions

		for row, state in pairs(altairValues.rainbowPlayerRows) do
			if not row.Parent then
				altairValues.rainbowPlayerRows[row] = nil
			else
				applyPlayerlistBase(row)
				local statusDot = state.statusDot
				if statusDot and statusDot.Parent then
					if statusDot:IsA("Frame") then
						statusDot.BackgroundColor3 = Color3.fromRGB(49, 214, 110)
					elseif statusDot:IsA("ImageLabel") or statusDot:IsA("ImageButton") then
						statusDot.ImageColor3 = Color3.fromRGB(49, 214, 110)
					end
				end
			end
		end

		local profile = interactions:FindFirstChild("SelectedPlayer")
		if profile then
			applyPlayerlistBase(profile)
		end
	end

	altairValues.applyPlayerlistBase = applyPlayerlistBase
	altairValues.restorePlayerlistRainbow = restorePlayerlistRainbow

	local function border(object)
		if borderColors[object] then return end
		if object:IsA("UIStroke") and (object:IsDescendantOf(homeContainer) or object:IsDescendantOf(characterPanel)) then
			local original = object:GetAttribute("AltairBaseColor") or object.Color
			object:SetAttribute("AltairBaseColor", original)
			borderColors[object] = { "Color", original }
		elseif object:IsA("Frame") and object.Name:find("Divider") and (object:IsDescendantOf(homeContainer) or object:IsDescendantOf(characterPanel)) then
			local original = object:GetAttribute("AltairBaseColor") or object.BackgroundColor3
			object:SetAttribute("AltairBaseColor", original)
			borderColors[object] = { "BackgroundColor3", original }
		end
	end
	for _,object in ipairs(UI:GetDescendants()) do border(object) end
	track(UI.DescendantAdded:Connect(border))
	

	track(runService.RenderStepped:Connect(function(dt)
		if not UI.Parent or not bar:IsDescendantOf(UI) then
			return
		end

		local rainbow = settingValue("Rainbow Mode", false)
		local persistentColor = blinkState.persistentColor
		if not rainbow and not enabled and not persistentColor then
			return
		end

		rainbowAccumulator += dt
		if rainbow and rainbowAccumulator < rainbowInterval then
			return
		end
		rainbowAccumulator = 0

		hue = (os.clock() / 8) % 1
		local color = rainbow and Color3.fromHSV(hue, 0.65, 0.8) or Color3.new(1, 1, 1)

		if rainbow then
			altairValues.rainbowColor = color
			applyPlayerlistRainbow(hue)
		else
			altairValues.rainbowColor = nil
			restorePlayerlistRainbow()
		end

		for object, original in pairs(borderColors) do
			if not object:IsDescendantOf(UI) then
				borderColors[object] = nil
			else
				object[original[1]] = rainbow and color or object:GetAttribute("AltairBaseColor") or original[2]
				if object:IsA("UIStroke") then
					local gradient = object:FindFirstChildOfClass("UIGradient")
					if gradient then
						if gradient:GetAttribute("AltairBaseEnabled") == nil then
							gradient:SetAttribute("AltairBaseEnabled", gradient.Enabled)
						end
						gradient.Enabled = not rainbow and gradient:GetAttribute("AltairBaseEnabled")
					end
				end
			end
		end

		local sliderGradientColor = rainbow and ColorSequence.new(
			Color3.fromHSV((hue + 0.12) % 1, 0.8, 1),
			Color3.fromHSV(hue, 0.8, 1)
		) or nil
		local sliderSolidColor = rainbow and Color3.fromHSV(hue, 0.8, 1) or nil

		for _, slider in ipairs(altairValues.sliders) do
			local sliderObject = slider.object
			local progress = sliderObject and sliderObject:FindFirstChild("Progress")
			if progress then
				local gradient = progress:FindFirstChildOfClass("UIGradient")
				local progressKey = "AltairSliderBackgroundColor3"
				if progress:GetAttribute(progressKey) == nil then
					progress:SetAttribute(progressKey, progress.BackgroundColor3)
				end
				progress.BackgroundColor3 = rainbow
					and (gradient and Color3.new(1, 1, 1) or color)
					or progress:GetAttribute(progressKey)

				if gradient then
					local gradientKey = "AltairSliderColor"
					if gradient:GetAttribute(gradientKey) == nil then
						gradient:SetAttribute(gradientKey, gradient.Color)
					end
					gradient.Color = rainbow and sliderGradientColor or gradient:GetAttribute(gradientKey)
				end

				local knob = progress:FindFirstChild("Knob")
				if knob then
					local knobKey = "AltairSliderBackgroundColor3"
					if knob:GetAttribute(knobKey) == nil then
						knob:SetAttribute(knobKey, knob.BackgroundColor3)
					end
					knob.BackgroundColor3 = rainbow and sliderSolidColor or knob:GetAttribute(knobKey)

					local glow = knob:FindFirstChild("Glow")
					if glow then
						local glowKey = "AltairSliderImageColor3"
						if glow:GetAttribute(glowKey) == nil then
							glow:SetAttribute(glowKey, glow.ImageColor3)
						end
						glow.ImageColor3 = rainbow and sliderSolidColor or glow:GetAttribute(glowKey)
					end
				end
			end
		end

		local smartBarColor = blinkState.color or persistentColor or (rainbow and color or Color3.new(1, 1, 1))
		bar.Shadow.ImageColor3 = smartBarColor
		bar.CircleGradient.ImageColor3 = smartBarColor
		bar.UIStroke.Color = smartBarColor
		bar.Back.UIStroke.Color = smartBarColor
		if dragVisual and dragColor then
			if dragVisual:IsA("ImageLabel") or dragVisual:IsA("ImageButton") then
				dragVisual.ImageColor3 = rainbow and color or dragColor
			else
				dragVisual.BackgroundColor3 = rainbow and color or dragColor
			end
		end

		if rainbow then
			for _, toast in ipairs(activeToasts) do
				local title = toast:FindFirstChild("Title")
				if title then
					if toastColors[title] == nil then
						toastColors[title] = title.TextColor3
					end
					title.TextColor3 = color
				end
			end
		else
			for title, original in pairs(toastColors) do
				if title.Parent then
					title.TextColor3 = original
				end
			end
		end

		enabled = rainbow or persistentColor ~= nil
	end))
end

local function BlinkSmartBar(blinkCount, color)
	table.insert(blinkState.queue, {
		count = math.max(1, math.floor(tonumber(blinkCount) or 1)),
		color = typeof(color) == "Color3" and color or nil,
	})

	if blinkState.running then return end
	blinkState.running = true

	task.spawn(function()
		local activeBar, activeSaved

		local function capture(bar)
			local saved = {}

			for _, object in ipairs({
				bar.Shadow,
				bar.CircleGradient,
				bar.UIStroke,
				bar.Back.UIStroke,
			}) do
				local stroke = object:IsA("UIStroke")
				local transparencyProperty = stroke and "Transparency" or "ImageTransparency"
				local colorProperty = stroke and "Color" or "ImageColor3"

				saved[object] = {
					transparencyProperty,
					object[transparencyProperty],
					colorProperty,
					object[colorProperty],
				}
			end

			return saved
		end

		local function restore(bar, saved)
			blinkState.color = nil
			if not saved then return end

			local rainbow = settingValue("Rainbow Mode", false)

			for object, state in pairs(saved) do
				if object.Parent then
					object[state[1]] =
						object == bar.Back.UIStroke
						and math.min(state[2], 0.8)
						or state[2]

					object[state[3]] = blinkState.persistentColor or (rainbow and state[4] or Color3.new(1, 1, 1))
				end
			end
		end

		local ok, err = pcall(function()
			while #blinkState.queue > 0 do
				local request = table.remove(blinkState.queue, 1)
				local bar = UI.SmartBar

				if bar and bar.Parent then
					activeBar = bar
					activeSaved = capture(bar)

					local tweenInfo = TweenInfo.new(
						0.5,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.InOut
					)

					for _ = 1, request.count do
						blinkState.color = request.color

						for object, state in pairs(activeSaved) do
							if object.Parent then
								local transparency = math.max(0, state[2] - 0.25)
								if object == bar.Back.UIStroke then
									transparency = math.min(transparency, 0.8)
								end

								local goal = {
									[state[1]] = transparency,
								}

								if request.color then
									goal[state[3]] = request.color
								end

								tweenService:Create(object, tweenInfo, goal):Play()
							end
						end

						task.wait(0.5)

						blinkState.color = nil

						for object, state in pairs(activeSaved) do
							if object.Parent then
								local transparency =
									object == bar.Back.UIStroke
									and math.min(state[2], 0.8)
									or state[2]

								local restoreColor = blinkState.persistentColor
								if not restoreColor then
									restoreColor = settingValue("Rainbow Mode", false)
										and Color3.fromHSV((os.clock() / 8) % 1, 0.65, 0.8)
										or Color3.new(1, 1, 1)
								end
								tweenService:Create(object, tweenInfo, {
									[state[1]] = transparency,
									[state[3]] = restoreColor,
								}):Play()
							end
						end

						task.wait(0.5)
					end

					restore(bar, activeSaved)
					activeBar, activeSaved = nil, nil
				end
			end
		end)

		if activeBar and activeSaved then
			pcall(restore, activeBar, activeSaved)
		else
			blinkState.color = nil
		end

		blinkState.running = false

		if not ok then
			warn("Altair | SmartBar blink failed: " .. tostring(err))
		end
	end)
end

local function Toast(content, color, font, skipBlink)
	if not checkAltair() then return end
	content = tostring(content or "")
	local length = utf8.len(content) or #content
	local lifetime = math.clamp(4 + length / 22, 7, 16)
	local reducedMotion = false
	pcall(function() reducedMotion = guiService.ReducedMotionEnabled end)
	for _, existing in ipairs(activeToasts) do
		if existing.Parent and not existing:GetAttribute("AltairExiting")
			and existing:GetAttribute("AltairContent") == content
			and existing:GetAttribute("AltairColor") == (color or Color3.fromRGB(240, 240, 240)) then
			local count = (existing:GetAttribute("AltairCount") or 1) + 1
			existing:SetAttribute("AltairCount", count)
			existing:SetAttribute("AltairDeadline", os.clock() + lifetime)
			existing.Title.Text = content .. " (x" .. count .. ")"
			existing.Title.MaxVisibleGraphemes = -1
			return
		end
	end
	while #activeToasts >= 6 do
		local oldest = table.remove(activeToasts)
		oldest:SetAttribute("AltairExiting", true)
		oldest:Destroy()
	end
	local template = UI.Toasts.Template:Clone()
	template.Parent, template.Title.Text, template.Title.TextColor3, template.Title.Font = UI.Toasts, content, color or Color3.fromRGB(240, 240, 240), font or Enum.Font.GothamSemibold
	template.Visible, template.BackgroundTransparency, template.Title.TextTransparency, template.Title.TextStrokeTransparency, template.Title.FontFace = true, 1, 1, 0.3, Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
	template.Title.MaxVisibleGraphemes = 0

	template:SetAttribute("AltairContent", content)
	template:SetAttribute("AltairCount", 1)
	template:SetAttribute("AltairColor", color or Color3.fromRGB(240, 240, 240))
	template:SetAttribute("AltairDeadline", os.clock() + lifetime)
	table.insert(activeToasts, 1, template)

	if altairValues.smartBarLayout then altairValues.smartBarLayout:syncToasts() end

	local startupSound = Instance.new("Sound")
	startupSound.Parent, startupSound.SoundId, startupSound.Name, startupSound.Volume, startupSound.PlayOnRemove = UI, "rbxassetid://255881176", "Toast", 0.85, true
	startupSound:Destroy()

	if #activeToasts == 1 then
		tweenService:Create(UI.SmartBar.CircleGradient, TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0.7}):Play()
	end

	tweenService:Create(template.Title, TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.3,
	}):Play()

	task.spawn(function()
		if reducedMotion then template.Title.MaxVisibleGraphemes = -1; return end
		local delay = math.clamp(1.15 / math.max(length, 1), 0.012, 0.035)

		for i = 1, length do
			if not template.Parent or template:GetAttribute("AltairExiting") or template:GetAttribute("AltairCount") > 1 then return end
			template.Title.MaxVisibleGraphemes = i
			task.wait(delay)
		end

		if template.Parent then
			template.Title.MaxVisibleGraphemes = -1
		end
	end)

	if not skipBlink and not reducedMotion then
		BlinkSmartBar(1, color)
	end

	task.spawn(function()
		while template.Parent do
			local remaining = (template:GetAttribute("AltairDeadline") or 0) - os.clock()
			if remaining <= 0 then break end
			task.wait(remaining)
		end
		if not template.Parent then return end
		template:SetAttribute("AltairExiting", true)
		template.Title.MaxVisibleGraphemes = -1

		tweenService:Create(template.Title, TweenInfo.new(2.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.wait(2.1)

		for i, toast in ipairs(activeToasts) do
			if toast == template then table.remove(activeToasts, i) break end
		end

		template:Destroy()

		if #activeToasts == 0 then
			tweenService:Create(UI.SmartBar.CircleGradient, TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 1}):Play()
		end
	end)
end

altairValues.scanCustomScripts = function()
	altairValues.customScripts = {}
	altairValues.detectedScript = nil

	if not (isfolder and listfiles and readfile) then
		return nil, "filesystem unavailable"
	end

	local folder = altairValues.altairFolder .. "/" .. altairValues.customScriptsFolder
	if not isfolder(folder) then
		if not makefolder then
			return nil, "custom scripts folder unavailable"
		end
		local ok = pcall(makefolder, folder)
		if not ok then
			return nil, "could not create custom scripts folder"
		end
	end

	local ok, files = pcall(listfiles, folder)
	if not ok or type(files) ~= "table" then
		return nil, "could not list custom scripts"
	end

	table.sort(files)

	for _, file in ipairs(files) do
		local lower = string.lower(tostring(file))
		if lower:sub(-5) == ".json" or lower:sub(-7) == ".altair" then
			local readOk, raw = pcall(readfile, file)

			if readOk and type(raw) == "string" and raw ~= "" then
				local decodeOk, data = pcall(httpService.JSONDecode, httpService, raw)

				if decodeOk and type(data) == "table" then
					local title = data.ScriptTitle or data.Title or data.Name
					local subtitle = data.ScriptSubtitle or data.Subtitle or data.Description
					local sourceUrl = data.Loadstring or data.Url or data.URL
					local rawSource = data.Source
					local scriptFile = data.LuaFile or data.ScriptFile or data.File
					local ids = data.PlaceIds or data.Games or data.PlaceId
					local definitionFile = file

					local normalizedFile = tostring(file):gsub(string.char(92), "/")
					local fileName = normalizedFile:match("([^/]+)$") or normalizedFile
					local stem, extension = fileName:match("^(.-)(%.[^%.]+)$")
					if stem and tonumber(stem) and writefile and delfile then
						local readableName = type(title) == "string" and title:match("^%s*(.-)%s*$") or ""

						if readableName == "" or tonumber(readableName) then
							local firstId = type(ids) == "table" and ids[1] or ids
							local numericId = tonumber(firstId)
							if numericId then
								local infoOk, info = pcall(
									marketplaceService.GetProductInfo,
									marketplaceService,
									math.floor(numericId)
								)
								if infoOk and info and type(info.Name) == "string" and info.Name ~= "" then
									readableName = info.Name
								end
							end
						end

						readableName = tostring(readableName)
							:gsub('[<>:"/|%?%*]', "")
		:gsub(string.char(92), "")
							:gsub("^%s+", "")
							:gsub("%s+$", "")

						if readableName == "" then
							readableName = "Custom Script"
						end

						local target = folder .. "/" .. readableName .. extension
						if isfile and isfile(target) then
							local base = folder .. "/" .. readableName
							local suffix = 2
							while isfile(base .. " (" .. tostring(suffix) .. ")" .. extension) do
								suffix += 1
							end
							target = base .. " (" .. tostring(suffix) .. ")" .. extension
						end

						local writeOk = pcall(writefile, target, raw)
						if writeOk then
							pcall(delfile, file)
							definitionFile = target
						end
					end

					if type(ids) ~= "table" then
						ids = ids ~= nil and { ids } or {}
					end

					local validSource =
						(type(sourceUrl) == "string" and sourceUrl ~= "")
						or (type(rawSource) == "string" and rawSource ~= "")
						or (type(scriptFile) == "string" and scriptFile ~= "")

					if type(title) == "string"
						and title ~= ""
						and type(subtitle) == "string"
						and subtitle ~= ""
						and validSource
						and #ids > 0
					then
						local entry = {
							ScriptTitle = title,
							ScriptSubtitle = subtitle,
							PlaceIds = ids,
							Loadstring = sourceUrl,
							Source = rawSource,
							LuaFile = scriptFile,
							ScriptFile = scriptFile,
							DefinitionFile = definitionFile,
						}

						table.insert(altairValues.customScripts, entry)

						if not altairValues.detectedScript then
							for _, id in ipairs(ids) do
								if tonumber(id) == placeId then
									altairValues.detectedScript = entry
									break
								end
							end
						end
					else
						warn("Altair | Ignoring invalid custom script definition: " .. tostring(file))
					end
				else
					warn("Altair | Couldn't parse custom script definition: " .. tostring(file))
				end
			end
		end
	end

	return altairValues.detectedScript
end

altairValues.closeGameDetection = function()
	if not gameDetectionPrompt.Visible then
		altairValues.detectionPromptOpen = false
		return
	end

	altairValues.detectionPromptOpen = false

	local scale = gameDetectionPrompt:FindFirstChild("AltairDetectionScale")
	if scale then
		tweenService:Create(
			scale,
			TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Scale = 0.94 }
		):Play()
	end

	for _, object in ipairs(gameDetectionPrompt:GetDescendants()) do
		local warning = gameDetectionPrompt:FindFirstChild("Warning", true)
		if not (warning and object:IsDescendantOf(warning)) then
			local properties = altairValues.transparencyProperties[object.ClassName]
			if properties then
				for _, property in ipairs(properties) do
					pcall(function()
						tweenService:Create(
							object,
							TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
							{ [property] = 1 }
						):Play()
					end)
				end
			end
		end
	end

	task.delay(0.3, function()
		if not altairValues.detectionPromptOpen then
			gameDetectionPrompt.Visible = false
		end
	end)
end

altairValues.showGameDetection = function(scriptInfo)
	if type(scriptInfo) ~= "table" then return false end

	local layer = gameDetectionPrompt:FindFirstChild("Layer")
	if not layer then
		warn("Altair | GameDetection.Layer is missing from the interface.")
		return false
	end

	local subtitle = layer:FindFirstChild("ScriptSubtitle")
	local thumbnail = gameDetectionPrompt:FindFirstChild("Thumbnail")
	local warning = gameDetectionPrompt:FindFirstChild("Warning")

	local currentPlaceId = game.PlaceId
	local ok, info = pcall(marketplaceService.GetProductInfo, marketplaceService, currentPlaceId)
	local gameTitle = ok and info and info.Name or ("Place " .. tostring(currentPlaceId))

	placeName = gameTitle
	gameDetectionPrompt.ScriptTitle.Text = gameTitle

	if subtitle then subtitle.Text = tostring(scriptInfo.ScriptSubtitle or "") end
	if warning then warning.Visible = false end

	if thumbnail and thumbnail:IsA("ImageLabel") then
		thumbnail.Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=512&h=512"
	end

	local scale = gameDetectionPrompt:FindFirstChild("AltairDetectionScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "AltairDetectionScale"
		scale.Scale = 1
		scale.Parent = gameDetectionPrompt
	end

	for _, object in ipairs(gameDetectionPrompt:GetDescendants()) do
		if not (warning and object:IsDescendantOf(warning)) then
			local properties = altairValues.transparencyProperties[object.ClassName]
			if properties then
				for _, property in ipairs(properties) do
					pcall(function()
						local attribute = "AltairDetection_" .. property
						if object:GetAttribute(attribute) == nil then
							object:SetAttribute(attribute, object[property])
						end
						object[property] = 1
					end)
				end
			end
		end
	end

	scale.Scale = 0.92
	gameDetectionPrompt.Visible = true
	altairValues.detectionPromptOpen = true

	tweenService:Create(
		scale,
		TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	for _, object in ipairs(gameDetectionPrompt:GetDescendants()) do
		if not (warning and object:IsDescendantOf(warning)) then
			local properties = altairValues.transparencyProperties[object.ClassName]
			if properties then
				for _, property in ipairs(properties) do
					pcall(function()
						local target = object:GetAttribute("AltairDetection_" .. property)
						if target ~= nil then
							tweenService:Create(
								object,
								TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
								{ [property] = target }
							):Play()
						end
					end)
				end
			end
		end
	end

	return true
end

altairValues.runDetectedScript = function()
	local scriptInfo = altairValues.detectedScript
	if type(scriptInfo) ~= "table" then
		Toast("No custom script was detected for this experience.")
		return false
	end

	altairValues.closeGameDetection()

	local currentGameName
	do
		local infoOk, info = pcall(
			marketplaceService.GetProductInfo,
			marketplaceService,
			game.PlaceId
		)
		currentGameName = infoOk and info and info.Name or "this experience"
	end
	Toast("Loading in " .. tostring(currentGameName) .. "...")

	task.spawn(function()
		if type(scriptInfo.Loadstring) == "string" and scriptInfo.Loadstring ~= "" then
			local url = scriptInfo.Loadstring

			if not loadstring then
				Toast("This executor doesn't support loadstring.", Color3.fromRGB(255, 90, 90))
				return
			end

			if not (url:match("^https?://")) then
				Toast("The custom script Loadstring must be a raw http(s) URL.", Color3.fromRGB(255, 90, 90))
				return
			end

			local ok, err = pcall(function()
				local chunk = assert(loadstring(game:HttpGet(url)))
				altairValues.activity:record("Script started", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Custom script")
				chunk()
			end)

			if not ok then
				altairValues.activity:record("Script failed", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Load or runtime error")
				warn("Altair | Remote custom script failed: " .. tostring(err))
				Toast("The remote custom script failed to load.", Color3.fromRGB(255, 90, 90))
			end

			return
		end

		local source = scriptInfo.Source
		local scriptFile = scriptInfo.LuaFile or scriptInfo.ScriptFile

		if (type(source) ~= "string" or source == "")
			and type(scriptFile) == "string"
			and scriptFile ~= ""
			and readfile
		then
			local path = scriptFile

			local normalizedPath = path:gsub(string.char(92), "/")
			if not normalizedPath:find("/", 1, true) then
				if not normalizedPath:match("%.[^/%.]+$") then
					path ..= ".lua"
				end

				local scriptsRoot = altairValues.altairFolder .. "/" .. altairValues.scriptsFolder
				local requestedName = path
				path = scriptsRoot .. "/" .. requestedName

				if isfile and not isfile(path) and listfiles then
					local ok, files = pcall(listfiles, scriptsRoot)
					if ok and type(files) == "table" then
						local wanted = string.lower(requestedName)
						for _, candidate in ipairs(files) do
							local name = tostring(candidate):gsub(string.char(92), "/"):match("([^/]+)$")
							if name and string.lower(name) == wanted then
								path = candidate
								break
							end
						end
					end
				end
			end

			if not isfile or not isfile(path) then
				Toast(
					"Custom script file not found: " .. tostring(scriptFile),
					Color3.fromRGB(255, 90, 90)
				)
				return
			end

			local ok, result = pcall(readfile, path)
			if ok and type(result) == "string" and result ~= "" then
				source = result
			else
				Toast("Couldn't read the custom script file.", Color3.fromRGB(255, 90, 90))
				return
			end
		end

		if type(source) ~= "string" or source == "" then
			Toast("This custom script has no runnable source.", Color3.fromRGB(255, 90, 90))
			return
		end

		if not loadstring then
			Toast("This executor doesn't support loadstring.", Color3.fromRGB(255, 90, 90))
			return
		end

		local compileOk, chunk = pcall(loadstring, source)
		if not compileOk or type(chunk) ~= "function" then
			altairValues.activity:record("Script failed", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Compile error")
			Toast("The custom script couldn't be compiled.", Color3.fromRGB(255, 90, 90))
			return
		end

		altairValues.activity:record("Script started", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Custom script")
		local runOk, runError = pcall(chunk)
		if not runOk then
			altairValues.activity:record("Script failed", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Runtime error")
			warn("Altair | Custom script failed: " .. tostring(runError))
			Toast("The custom script returned an error.", Color3.fromRGB(255, 90, 90))
		end
	end)

	return true
end

altairValues.closeCustomScriptPrompt = function()
	if not customScriptPrompt.Visible then
		altairValues.customScriptPromptOpen = false
		return
	end

	altairValues.customScriptPromptOpen = false

	local scale = customScriptPrompt:FindFirstChild("AltairCustomScriptScale")
	if scale then
		tweenService:Create(
			scale,
			TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Scale = 0.95 }
		):Play()
	end

	for _, object in ipairs({ customScriptPrompt, table.unpack(customScriptPrompt:GetDescendants()) }) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			for _, property in ipairs(properties) do
				pcall(function()
					tweenService:Create(
						object,
						TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
						{ [property] = 1 }
					):Play()
				end)
			end
		end
	end

	task.delay(0.26, function()
		if not altairValues.customScriptPromptOpen then
			customScriptPrompt.Visible = false
		end
	end)
end

altairValues.openCustomScriptPrompt = function()
	local idBox = customScriptPrompt:FindFirstChild("IDTextBox", true)
	local descBox = customScriptPrompt:FindFirstChild("DescTextBox", true)
	local scriptBox = customScriptPrompt:FindFirstChild("ScriptTextBox", true)

	if not (idBox and descBox and scriptBox) then
		Toast("Custom Scripts UI is missing one or more text boxes.", Color3.fromRGB(255, 90, 90))
		return false
	end

	idBox.Text = tostring(placeId)
	descBox.Text = ""
	scriptBox.Text = ""

	local scale = customScriptPrompt:FindFirstChild("AltairCustomScriptScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "AltairCustomScriptScale"
		scale.Scale = 1
		scale.Parent = customScriptPrompt
	end

	scale.Scale = 0.94

	for _, object in ipairs({ customScriptPrompt, table.unpack(customScriptPrompt:GetDescendants()) }) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			for _, property in ipairs(properties) do
				pcall(function()
					local attribute = "AltairCustomScript_" .. property
					if object:GetAttribute(attribute) == nil then
						object:SetAttribute(attribute, object[property])
					end
					object[property] = 1
				end)
			end
		end
	end

	customScriptPrompt.Visible = true
	altairValues.customScriptPromptOpen = true

	tweenService:Create(
		scale,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	for _, object in ipairs({ customScriptPrompt, table.unpack(customScriptPrompt:GetDescendants()) }) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			for _, property in ipairs(properties) do
				pcall(function()
					local target = object:GetAttribute("AltairCustomScript_" .. property)
					if target ~= nil then
						tweenService:Create(
							object,
							TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
							{ [property] = target }
						):Play()
					end
				end)
			end
		end
	end

	return true
end

altairValues.saveCustomScriptPrompt = function()
	local idBox = customScriptPrompt:FindFirstChild("IDTextBox", true)
	local descBox = customScriptPrompt:FindFirstChild("DescTextBox", true)
	local scriptBox = customScriptPrompt:FindFirstChild("ScriptTextBox", true)

	if not (idBox and descBox and scriptBox) then
		Toast("Custom Scripts UI is missing one or more text boxes.", Color3.fromRGB(255, 90, 90))
		return false
	end

	if not (writefile and readfile and isfolder and makefolder) then
		Toast("This executor doesn't support saving custom scripts.", Color3.fromRGB(255, 90, 90))
		return false
	end

	local requestedId = tostring(idBox.Text or ""):match("^%s*(.-)%s*$")
	local targetPlaceId = tonumber(requestedId) or placeId

	if not targetPlaceId or targetPlaceId <= 0 then
		targetPlaceId = placeId
	end

	targetPlaceId = math.floor(targetPlaceId)
	idBox.Text = tostring(targetPlaceId)

	local enteredDescription = tostring(descBox.Text or ""):match("^%s*(.-)%s*$")
	local description = enteredDescription ~= "" and enteredDescription or "Custom script for this experience."

	local sourceValue = tostring(scriptBox.Text or ""):match("^%s*(.-)%s*$")
	if sourceValue == "" then
		Toast("Enter a raw script URL or Lua file name.", Color3.fromRGB(255, 90, 90))
		return false
	end

	local isRemote = sourceValue:match("^https?://") ~= nil

	local function normalizeFile(value)
		value = tostring(value or ""):match("^%s*(.-)%s*$"):gsub(string.char(92), "/")
		if value == "" then return "" end
		if not value:match("%.[^/%.]+$") then
			value ..= ".lua"
		end
		return string.lower(value)
	end

	local normalizedSource = isRemote and sourceValue or normalizeFile(sourceValue)

	local targetGameName
	do
		local infoOk, info = pcall(
			marketplaceService.GetProductInfo,
			marketplaceService,
			targetPlaceId
		)
		targetGameName = infoOk and info and info.Name or "this experience"
	end

	altairValues.scanCustomScripts()

	local existing
	for _, entry in ipairs(altairValues.customScripts) do
		local matches = false

		if isRemote then
			matches = type(entry.Loadstring) == "string"
				and entry.Loadstring:match("^%s*(.-)%s*$") == normalizedSource
		else
			local existingFile = entry.LuaFile or entry.ScriptFile
			matches = normalizeFile(existingFile) == normalizedSource
		end

		if matches then
			existing = entry
			break
		end
	end

	if existing and type(existing.DefinitionFile) == "string" then
		local readOk, raw = pcall(readfile, existing.DefinitionFile)
		local decodeOk, definition = false, nil

		if readOk and type(raw) == "string" and raw ~= "" then
			decodeOk, definition = pcall(httpService.JSONDecode, httpService, raw)
		end

		if not decodeOk or type(definition) ~= "table" then
			Toast("Couldn't update the existing custom script.", Color3.fromRGB(255, 90, 90))
			return false
		end

		local ids = definition.PlaceIds or definition.Games or definition.PlaceId
		if type(ids) ~= "table" then
			ids = ids ~= nil and { ids } or {}
		end

		local alreadySupported = false
		local mergedIds = {}

		for _, id in ipairs(ids) do
			local numericId = tonumber(id)
			if numericId then
				numericId = math.floor(numericId)
				if numericId == targetPlaceId then
					alreadySupported = true
				end
				if not table.find(mergedIds, numericId) then
					table.insert(mergedIds, numericId)
				end
			end
		end

		if not alreadySupported then
			table.insert(mergedIds, targetPlaceId)
		end

		definition.PlaceIds = mergedIds

		if enteredDescription ~= "" then
			definition.ScriptSubtitle = enteredDescription
		end

		local encodedOk, encoded = pcall(httpService.JSONEncode, httpService, definition)
		if not encodedOk then
			Toast("Couldn't rebuild the existing custom script.", Color3.fromRGB(255, 90, 90))
			return false
		end

		local writeOk, writeError = pcall(writefile, existing.DefinitionFile, encoded)
		if not writeOk then
			warn("Altair | Couldn't update custom script: " .. tostring(writeError))
			Toast("Couldn't update the existing custom script.", Color3.fromRGB(255, 90, 90))
			return false
		end

		altairValues.scanCustomScripts()
		altairValues.closeCustomScriptPrompt()

		if alreadySupported then
			Toast(
				"Updated custom script for " .. tostring(targetGameName) .. ".",
				Color3.fromRGB(80, 220, 145)
			)
		else
			Toast(
				"Added " .. tostring(targetGameName) .. " to the existing custom script.",
				Color3.fromRGB(80, 220, 145)
			)
		end

		return true
	end

	local title = targetGameName ~= "this experience" and targetGameName or "Custom Script"

	local definition = {
		ScriptTitle = title,
		ScriptSubtitle = description,
		PlaceIds = { targetPlaceId },
	}

	if isRemote then
		definition.Loadstring = sourceValue
	else
		definition.LuaFile = sourceValue
	end

	local folder = altairValues.altairFolder .. "/" .. altairValues.customScriptsFolder
	if not isfolder(folder) then
		local ok = pcall(makefolder, folder)
		if not ok then
			Toast("Couldn't create the Custom Scripts folder.", Color3.fromRGB(255, 90, 90))
			return false
		end
	end

	local encodedOk, encoded = pcall(httpService.JSONEncode, httpService, definition)
	if not encodedOk then
		Toast("Couldn't build the custom script definition.", Color3.fromRGB(255, 90, 90))
		return false
	end

	local safeTitle = tostring(title)
		:gsub('[<>:"/|%?%*]', "")
		:gsub(string.char(92), "")
		:gsub("^%s+", "")
		:gsub("%s+$", "")

	if safeTitle == "" then
		safeTitle = "Custom Script"
	end

	local filePath = folder .. "/" .. safeTitle .. ".altair"

	if isfile and isfile(filePath) then
		local base = folder .. "/" .. safeTitle
		local suffix = 2
		while isfile(base .. " (" .. tostring(suffix) .. ").altair") do
			suffix += 1
		end
		filePath = base .. " (" .. tostring(suffix) .. ").altair"
	end

	local writeOk, writeError = pcall(writefile, filePath, encoded)

	if not writeOk then
		warn("Altair | Couldn't save custom script: " .. tostring(writeError))
		Toast("Couldn't save the custom script.", Color3.fromRGB(255, 90, 90))
		return false
	end

	altairValues.scanCustomScripts()
	altairValues.closeCustomScriptPrompt()
	Toast("Imported custom script for " .. tostring(title) .. ".", Color3.fromRGB(80, 220, 145))
	return true
end

local function checkLastVersion()
	checkFolder()

	local lastVersion = isfile and isfile(altairValues.altairFolder .. "/" .. "version.altair") and readfile(altairValues.altairFolder .. "/" .. "version.altair") or nil

	if lastVersion then
		if lastVersion ~= altairValues.altairVersion then
			queueNotification("Altair has been updated", "Altair has been updated to version " .. altairValues.altairVersion .. ", check our Discord for all new features and changes.", 4400701828)
		end
	end

	if writefile then
		writefile(altairValues.altairFolder .. "/" .. "version.altair", altairValues.altairVersion)
	end
end

local function removeReverbs(timing)
	timing = timing or 0.65
	for sound, reverb in pairs(altairValues.lifecycle.audio) do
		altairValues.lifecycle.audio[sound] = nil
		if reverb.Parent then
			tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { HighGain = 0, LowGain = 0, MidGain = 0 }):Play()
			task.delay(timing + 0.03, function() if reverb.Parent then reverb:Destroy() end end)
		end
	end
end

local function createReverb(timing)
	if not altairValues.lifecycle.alive then return end
	for _, sound in ipairs(soundInstances) do
		if sound.Parent and not altairValues.lifecycle.audio[sound] then
			local reverb = altairValues.lifecycle:own(Instance.new("EqualizerSoundEffect"))
			altairValues.lifecycle.audio[sound] = reverb
			reverb.Destroying:Once(function()
				if altairValues.lifecycle.audio[sound] == reverb then altairValues.lifecycle.audio[sound] = nil end
			end)
			reverb.HighGain, reverb.LowGain, reverb.MidGain = 0, 0, 0
			reverb.Parent = sound
			if timing then
				tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { HighGain = -20, LowGain = 5, MidGain = -20 }):Play()
			end
		end
	end
end

altairValues.currentCreator = creatorType == Enum.CreatorType.Group and "group" or creatorId
altairValues.currentGroup = creatorType == Enum.CreatorType.Group and creatorId or nil

local function updateSliderPadding()
	for _, v in pairs(altairValues.sliders) do
		-- Viewport changes can land before sortActions() has built the slider objects
		if v.object then
			v.padding = {
				v.object.Track.AbsolutePosition.X,
				v.object.Track.AbsolutePosition.X + v.object.Track.AbsoluteSize.X,
			}
		end
	end
end

local function updateSlider(data, setValue, forceValue, pointerX)
	if not data.object or not data.padding then
		return
	end

	local inverse_interpolation

	if setValue then
		setValue = math.clamp(setValue, data.values[1], data.values[2])
		inverse_interpolation = (setValue - data.values[1]) / (data.values[2] - data.values[1])
	else
		-- Measure the track during the drag, including while the panel is moving.
		data.padding = { data.object.Track.AbsolutePosition.X, data.object.Track.AbsolutePosition.X + data.object.Track.AbsoluteSize.X }
		pointerX = pointerX or userInputService:GetMouseLocation().X
		local posX = math.clamp(pointerX, data.padding[1], data.padding[2])
		local span = data.padding[2] - data.padding[1]
		inverse_interpolation = span > 0 and (posX - data.padding[1]) / span or 0
	end

	-- Progress and Track are siblings; keep the fill eight pixels high and inside the track.
	local track = data.object.Track
	local progressSize = UDim2.new(track.Size.X.Scale * inverse_interpolation, track.Size.X.Offset * inverse_interpolation, track.Size.Y.Scale, track.Size.Y.Offset)
	tweenService:Create(data.object.Progress, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Size = progressSize }):Play()

	local precision = data.default % 1 ~= 0 and 10 or 1
	local value = math.floor((data.values[1] + (data.values[2] - data.values[1]) * inverse_interpolation) * precision + 0.5) / precision
	data.object.Information.Text = data.name:gsub("^%l", string.upper)
	if not data.object.Value:IsFocused() then
		data.object.Value.Text = tostring(value)
	end
	data.value = value

	-- Parenthesised: this used to read (callback and not setValue) or forceValue, so a forced
	-- update on a slider without a callback called nil.
	if data.callback and (not setValue or forceValue) then
		data.callback(value)
	end
end

local function resetSliders()
	for _, v in pairs(altairValues.sliders) do
		updateSlider(v, v.default, true)
	end
end

local function sortActions()
	characterPanel.Interactions.Toggles.Template.Visible = false
	characterPanel.Interactions.Grid.Template.Visible = false
	characterPanel.Interactions.Sliders.Template.Visible = false
	for _, container in ipairs({ characterPanel.Interactions.Toggles, characterPanel.Interactions.Grid, characterPanel.Interactions.Sliders }) do
		for _, row in ipairs(container:GetChildren()) do
			if row:IsA("GuiObject") and row.Name ~= "Template" and (row:GetAttribute("IsPreview") or row:GetAttribute("RuntimeEntry")) then
				row:Destroy()
			end
		end
	end
	characterPanel.Interactions.Reset.Position = UDim2.new(1, -25, 0, 10)
	characterPanel.Interactions.Reset.Visible = true
	local closeButton = characterPanel:FindFirstChild("Close")
	if closeButton then closeButton:Destroy() end

	local quickToggles = { Noclip = 1, Flight = 2, Visibility = 3, ["Extrasensory Perception"] = 4 }
	for index, action in ipairs(altairValues.actions) do
		local container = quickToggles[action.name] and characterPanel.Interactions.Toggles or characterPanel.Interactions.Grid
		local newAction = container.Template:Clone()
		newAction.Name = action.name
		newAction:SetAttribute("RuntimeEntry", true)
		newAction.Parent = container
		newAction.LayoutOrder = quickToggles[action.name] or index
		newAction.Title.Text = action.name == "Extrasensory Perception" and "ESP" or action.name
		if action.name == "Invulnerability" then newAction.Title.TextSize = 10 end
		if quickToggles[action.name] then
			newAction.Subtitle.Text = "Disabled"
			newAction.BackgroundColor3 = Color3.new(1, 1, 1)
			local gradient = newAction:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient", newAction)
			gradient.Color = ColorSequence.new(Color3.fromRGB(43, 48, 60):Lerp(action.color, 0.32), Color3.fromRGB(32, 35, 43))
			gradient.Rotation = 90
			newAction.UIStroke.Color = action.color
			newAction.UIStroke:SetAttribute("AltairBaseColor", action.color)
			local glowGradient = newAction.Glow:FindFirstChildOfClass("UIGradient")
			if glowGradient then
				newAction.Glow.ImageColor3 = Color3.new(1, 1, 1)
				glowGradient.Color = ColorSequence.new(action.color)
			else
				newAction.Glow.ImageColor3 = action.color
			end
		end
		newAction.Icon.Image = "rbxassetid://" .. action.images[2]
		newAction.Visible = true

		applyActionVisual(action, newAction)

		newAction.MouseEnter:Connect(function()
			if action.enabled or debounce then
				return
			end
			tweenService:Create(newAction, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.5 }):Play()
			tweenService:Create(newAction.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
			tweenService:Create(newAction.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0.5 }):Play()
			tweenService:Create(newAction.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.1 }):Play()
		end)

		newAction.MouseLeave:Connect(function()
			if debounce then
				return
			end
			applyActionVisual(action, newAction)
			tweenService:Create(newAction.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
			tweenService:Create(newAction.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.5 }):Play()
		end)

		newAction.Interact.MouseButton1Click:Connect(function()
			local success = pcall(function()
				action.enabled = not action.enabled
				action.callback(action.enabled)

				if action.enabled then
					applyActionVisual(action, newAction)

					if action.disableAfter then
						task.delay(action.disableAfter, function()
							action.enabled = false
							applyActionVisual(action, newAction)
						end)
					end

					if action.rotateWhileEnabled then
						repeat
							newAction.Icon.Rotation = 0
							tweenService:Create(newAction.Icon, TweenInfo.new(0.75, Enum.EasingStyle.Quint), { Rotation = 360 }):Play()
							task.wait(1)
						until not action.enabled
						newAction.Icon.Rotation = 0
					end
				else
					applyActionVisual(action, newAction)
					
				end
			end)

			if not success then
				queueNotification("Action Error", "This action ('" .. action.name .. "') had an error while running, please report this to the Altair team", 4370336704)
				action.enabled = false
				applyActionVisual(action, newAction)
			end
		end)
	end

	local startingHumanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
	if startingHumanoid and not startingHumanoid.UseJumpPower then
		altairValues.sliders[2].name = "jump height"
		altairValues.sliders[2].default = 7.2
		altairValues.sliders[2].value = 7.2
		altairValues.sliders[2].values = { 0, 120 }
	end

	for index, slider in ipairs(altairValues.sliders) do
		local newSlider = characterPanel.Interactions.Sliders.Template:Clone()
		newSlider.Name = slider.name .. " Slider"
		newSlider:SetAttribute("RuntimeEntry", true)
		newSlider.Parent = characterPanel.Interactions.Sliders
		newSlider.LayoutOrder = index
		-- Keep the template's neutral progress base, gradient, knob and glow colors.
		newSlider.Information.Text = slider.name
		newSlider.Visible = true

		slider.object = newSlider

		slider.padding = {
			newSlider.Track.AbsolutePosition.X,
			newSlider.Track.AbsolutePosition.X + newSlider.Track.AbsoluteSize.X,
		}

		newSlider.MouseEnter:Connect(function()
			if debounce or slider.active then
				return
			end
			tweenService:Create(newSlider, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(newSlider.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { Transparency = 1 }):Play()
			tweenService:Create(newSlider.Information, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { TextTransparency = 0 }):Play()
		end)

		newSlider.MouseLeave:Connect(function()
			if debounce or slider.active then
				return
			end
			tweenService:Create(newSlider, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(newSlider.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { Transparency = 1 }):Play()
			tweenService:Create(newSlider.Information, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { TextTransparency = 0 }):Play()
		end)

		newSlider.Interact.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
			if debounce or not checkAltair() then
				return
			end

			slider.active = true
			updateSlider(slider, nil, nil, input.Position.X)

			tweenService:Create(slider.object, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(slider.object.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { Transparency = 1 }):Play()
			tweenService:Create(slider.object.Information, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { TextTransparency = 0.05 }):Play()
		end)

		newSlider.Value.FocusLost:Connect(function()
			local value = tonumber(newSlider.Value.Text)
			if value and value == value and value > -math.huge and value < math.huge then
				local success = pcall(updateSlider, slider, value, true)
				if not success then
					queueNotification("Property Error", "Unable to update " .. slider.name .. ".", 4370336704)
				end
			end
			newSlider.Value.Text = tostring(slider.value)
		end)

		updateSlider(slider, slider.default)
	end
end

local function getAdaptiveHighPingThreshold()
	local adaptiveBaselinePings = altairValues.pingProfile.adaptiveBaselinePings

	if #adaptiveBaselinePings == 0 then
		return altairValues.pingProfile.adaptiveHighPingThreshold
	end

	table.sort(adaptiveBaselinePings)
	local median
	if #adaptiveBaselinePings % 2 == 0 then
		median = (adaptiveBaselinePings[#adaptiveBaselinePings / 2] + adaptiveBaselinePings[#adaptiveBaselinePings / 2 + 1]) / 2
	else
		median = adaptiveBaselinePings[math.ceil(#adaptiveBaselinePings / 2)]
	end

	return median * altairValues.pingProfile.spikeThreshold
end

local function checkHighPing()
	local recentPings = altairValues.pingProfile.recentPings
	local adaptiveBaselinePings = altairValues.pingProfile.adaptiveBaselinePings

	local currentPing = getPing()
	table.insert(recentPings, currentPing)

	if #recentPings > altairValues.pingProfile.maxSamples then
		table.remove(recentPings, 1)
	end

	if #adaptiveBaselinePings < altairValues.pingProfile.adaptiveBaselineSamples then
		if currentPing >= 350 then
			currentPing = 300
		end

		table.insert(adaptiveBaselinePings, currentPing)

		return false
	end

	local averagePing = 0
	for _, ping in ipairs(recentPings) do
		averagePing = averagePing + ping
	end
	averagePing = averagePing / #recentPings

	if averagePing > getAdaptiveHighPingThreshold() then
		return true
	end

	return false
end

altairValues.smartBarLayout = (function()
	local controller = {
		dragging = false,
		dragMoved = false,
		touchInput = nil,
		contentSide = nil,
		lastPointer = Vector2.zero,
		startPointer = Vector2.zero,
		lastRenderPointer = Vector2.zero,
		grabOffset = Vector2.zero,
		dragSide = 1,
		barOffsetY = 0,
		closedAtDrag = false,
		idleAccumulator = 0,
		initializing = true,
	}

	local back = smartBar.Back
	local time = back.Time
	local buttons = back.Buttons
	local dragVisual = drag:FindFirstChild("Drag")
	local baseBackPosition = back.Position
	local baseTimePosition = time.Position
	local baseButtonsPosition = buttons.Position

	local function centerOf(object)
		return object.AbsolutePosition + object.AbsoluteSize * 0.5
	end

	local function moveCenter(object, target)
		-- Preserve the rendered ScreenGui origin so the held group follows the pointer.
		local delta = target - centerOf(object)
		object.Position += UDim2.fromOffset(delta.X, delta.Y)
	end

	local function mirrorX(position)
		return UDim2.new(1 - position.X.Scale, -position.X.Offset, position.Y.Scale, position.Y.Offset)
	end

	local function screenSize()
		local size = UI:IsA("ScreenGui") and UI.AbsoluteSize or camera.ViewportSize
		return size.X > 0 and size.Y > 0 and size or camera.ViewportSize
	end

	local function screenOriginY()
		return UI:IsA("ScreenGui") and UI.AbsolutePosition.Y or 0
	end

	local function clampCenter(object, target, margin)
		local viewport = screenSize()
		local half = object.AbsoluteSize * 0.5
		margin = margin or 8
		return Vector2.new(
			math.clamp(target.X, half.X + margin, math.max(half.X + margin, viewport.X - half.X - margin)),
			math.clamp(target.Y, screenOriginY() + half.Y + margin, math.max(screenOriginY() + half.Y + margin, screenOriginY() + viewport.Y - half.Y - margin))
		)
	end

	local function pointerPosition(input)
		local position = input and input.Position or userInputService:GetMouseLocation()
		return Vector2.new(position.X, position.Y)
	end

	local function panelSize(panel)
		return panel.Name == "Character" and characterPanelSize
			or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
			or UDim2.fromOffset(581, 246)
	end

	function controller:getDock()
		return centerOf(smartBar).Y < screenSize().Y * 0.5 and "top" or "bottom"
	end

	function controller:getOpenPanel()
		if self.activePanel and self.activePanel.Parent and self.activePanel.Visible then
			return self.activePanel
		end
		for _, name in ipairs({ "Character", "Scripts", "Playerlist" }) do
			local panel = UI:FindFirstChild(name)
			if panel and panel.Visible then
				return panel
			end
		end
	end

	function controller:getPanelPosition(panel, size)
		size = size or panelSize(panel)
		local dock = self:getDock()
		local viewport = screenSize()
		local barPos, barSize = smartBar.AbsolutePosition, smartBar.AbsoluteSize
		local width, height = size.X.Offset, size.Y.Offset
		local gap, margin = 12, 8
		local x = barPos.X + barSize.X * 0.5 - width * 0.5
		local y = dock == "top"
			and barPos.Y + barSize.Y + gap
			or barPos.Y - height - gap

		x = math.clamp(x, margin, math.max(margin, viewport.X - width - margin))
		y = math.clamp(y, margin, math.max(margin, viewport.Y - height - margin))

		local anchor = panel.AnchorPoint
		local currentAnchor = panel.AbsolutePosition + panel.AbsoluteSize * anchor
		local targetAnchor = Vector2.new(x + width * anchor.X, y + height * anchor.Y)
		local delta = targetAnchor - currentAnchor
		return panel.Position + UDim2.fromOffset(delta.X, delta.Y)
	end

	function controller:syncContents(animate)
		local viewport = screenSize()
		local x = centerOf(smartBar).X
		local midpoint = viewport.X * 0.5
		local nextSide = self.contentSide

		if not nextSide then
			nextSide = x < midpoint and "left" or "right"
		elseif nextSide == "left" and x > midpoint + 24 then
			nextSide = "right"
		elseif nextSide == "right" and x < midpoint - 24 then
			nextSide = "left"
		end

		if nextSide == self.contentSide then
			return
		end
		local hadSide = self.contentSide ~= nil
		self.contentSide = nextSide

		local mirrored = nextSide == "left"
		local backTarget = mirrored and mirrorX(baseBackPosition) or baseBackPosition
		local timeTarget = mirrored and mirrorX(baseTimePosition) or baseTimePosition
		local buttonsTarget = mirrored and mirrorX(baseButtonsPosition) or baseButtonsPosition

		if animate or hadSide then
			local info = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			tweenService:Create(back, info, { Position = backTarget }):Play()
			tweenService:Create(time, info, { Position = timeTarget }):Play()
			tweenService:Create(buttons, info, { Position = buttonsTarget }):Play()
		else
			back.Position, time.Position, buttons.Position = backTarget, timeTarget, buttonsTarget
		end
	end

	local function positionAtRenderedCenter(object, target)
		local delta = target - centerOf(object)
		return object.Position + UDim2.fromOffset(delta.X, delta.Y)
	end

	local function positionPath()
		return altairValues.altairFolder .. "/position.altair"
	end

	local function finiteFraction(value)
		return type(value) == "number" and value == value and value >= 0 and value <= 1
	end

	function controller:savePosition()
		if type(writefile) ~= "function" then return end
		local viewport = screenSize()
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local center = centerOf(smartBar)
		local position = {
			version = 1,
			x = math.clamp((center.X - originX) / viewport.X, 0, 1),
			y = math.clamp((center.Y - screenOriginY()) / viewport.Y, 0, 1),
		}
		local ok, err = pcall(function()
			checkFolder()
			writefile(positionPath(), httpService:JSONEncode(position))
		end)
		if not ok then warn("Altair | Unable to save position: " .. tostring(err)) end
	end

	function controller:restoreSavedPosition()
		if type(readfile) ~= "function" then return false end
		local ok, position = pcall(function()
			if isfile and not isfile(positionPath()) then return nil end
			return httpService:JSONDecode(readfile(positionPath()))
		end)
		if not ok or type(position) ~= "table" or position.version ~= 1
			or not finiteFraction(position.x) or not finiteFraction(position.y) then
			return false
		end
		local viewport = screenSize()
		if viewport.X <= 0 or viewport.Y <= 0 then return false end
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local target = Vector2.new(originX + position.x * viewport.X, screenOriginY() + position.y * viewport.Y)
		smartBar.Size = UDim2.fromOffset(300, 60)
		-- Restore from known dimensions, without reading a stale rendered asset size.
		local x = math.clamp(target.X - originX, 158, math.max(158, viewport.X - 158))
		local y = math.clamp(target.Y - screenOriginY(), 38, math.max(38, viewport.Y - 38))
		smartBar.Position = UDim2.fromOffset(x + (smartBar.AnchorPoint.X - 0.5) * 300,
			y + (smartBar.AnchorPoint.Y - 0.5) * 60)
		altairValues.smartBarPositionInitialized = true
		return true
	end

	function controller:prepareStartup(hidden)
		smartBar.Visible = false
		drag.Visible = false
		smartBar.Size = UDim2.fromOffset(300, 60)
		if not self:restoreSavedPosition() then
			local viewport = screenSize()
			smartBar.Position = UDim2.fromOffset(viewport.X * 0.5, math.max(38, viewport.Y - 38))
			altairValues.smartBarPositionInitialized = true
		end
		-- Let Roblox resolve absolute geometry while both moving objects are invisible.
		UI.Enabled = true
		runService.RenderStepped:Wait()
		self.closedAtDrag = hidden
		self:cancelDragPositionTween()
		local target = hidden and self:getClosedDragCenter() or self:getRestDragCenter()
		drag.Position = positionAtRenderedCenter(drag, target)
		self:syncContents(false)
		self:syncToasts()
		runService.RenderStepped:Wait() -- Resolve Drag before open/close computes its first tween.
		self.initializing = false
	end

	function controller:getClosedDragCenter()
		local barCenter = centerOf(smartBar)
		local line = dragVisual and dragVisual:IsA("GuiObject") and dragVisual or drag
		local lineTop = line.AbsolutePosition.Y - centerOf(drag).Y
		local lineBottom = lineTop + line.AbsoluteSize.Y
		local upperHalf = barCenter.Y < screenOriginY() + screenSize().Y * 0.5
		local y = upperHalf and (smartBar.AbsolutePosition.Y - lineTop)
			or (smartBar.AbsolutePosition.Y + smartBar.AbsoluteSize.Y - lineBottom)
		return Vector2.new(barCenter.X, y)
	end

	function controller:restoreSmartBarAtDrag()
		smartBar.Position = positionAtRenderedCenter(smartBar, clampCenter(smartBar, centerOf(drag), 8))
	end

	function controller:cancelDragPositionTween()
		local tween = self.dragPositionTween
		self.dragPositionTween = nil
		if tween then tween:Cancel() end
	end

	function controller:tweenDragCenter(target, info, size)
		self:cancelDragPositionTween()
		local goal = { Position = positionAtRenderedCenter(drag, target) }
		if size then goal.Size = size end
		local tween = tweenService:Create(drag, info, goal)
		self.dragPositionTween = tween
		tween.Completed:Once(function()
			if self.dragPositionTween == tween then
				self.dragPositionTween = nil
				self:syncDrag()
			end
		end)
		tween:Play()
	end

	function controller:getRestDragCenter()
		local dock = self:getDock()
		local viewport = screenSize()
		local barPos, barSize = smartBar.AbsolutePosition, smartBar.AbsoluteSize
		local half = drag.AbsoluteSize * 0.5
		local gap = 4
		local line = dragVisual and dragVisual:IsA("GuiObject") and dragVisual or drag
		local lineTop = line.AbsolutePosition.Y - centerOf(drag).Y
		local lineBottom = lineTop + line.AbsoluteSize.Y
		local targetX = barPos.X + barSize.X * 0.5
		local edge = dock == "bottom" and barPos.Y or (barPos.Y + barSize.Y)

		for _, name in ipairs({ "Character", "Scripts", "Playerlist" }) do
			local panel = UI:FindFirstChild(name)
			if panel and panel.Visible then
				if dock == "bottom" then
					edge = math.min(edge, panel.AbsolutePosition.Y)
				else
					edge = math.max(edge, panel.AbsolutePosition.Y + panel.AbsoluteSize.Y)
				end
			end
		end

		local targetY = dock == "bottom"
			and edge - gap - lineBottom
			or edge + gap - lineTop

		return Vector2.new(
			math.clamp(targetX, half.X + 8, math.max(half.X + 8, viewport.X - half.X - 8)),
			math.clamp(targetY, screenOriginY() + 8 - lineTop, math.max(screenOriginY() + 8 - lineTop, screenOriginY() + viewport.Y - 8 - lineBottom))
		)
	end

	function controller:syncDrag()
		drag.Visible = not settingValue("Hide Bar")
		drag.BackgroundTransparency = 1

		if self.dragging or not smartBarOpen or self.dragPositionTween then
			return
		end

		if dragVisual then dragVisual.Rotation = 0 end
		-- Absolute coordinates include the ScreenGui origin; preserve that conversion.
		drag.Position = positionAtRenderedCenter(drag, self:getRestDragCenter())
	end

	function controller:syncToasts(dragCenter)
		if not (toastsContainer and toastsContainer.Parent and drag.Parent) then
			return
		end

		local viewport = screenSize()
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local margin, gap = 8, 8
		local topEdge, bottomEdge = screenOriginY() + margin, screenOriginY() + viewport.Y - margin
		local toastPos, toastSize = toastsContainer.AbsolutePosition, toastsContainer.AbsoluteSize
		local dragSize = drag.AbsoluteSize
		dragCenter = dragCenter or centerOf(drag)
		local above = dragCenter.Y - dragSize.Y * 0.5 - gap - toastSize.Y
		local below = dragCenter.Y + dragSize.Y * 0.5 + gap
		local bottomDock
		if self.dragging then
			bottomDock = self.dragSide > 0
		else
			bottomDock = self:getDock() == "bottom"
		end
		-- Prefer the usual side, then use the other side if it has enough room.
		if bottomDock and above < topEdge and below + toastSize.Y <= bottomEdge then
			bottomDock = false
		elseif not bottomDock and below + toastSize.Y > bottomEdge and above >= topEdge then
			bottomDock = true
		end

		local layout = toastsContainer:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.VerticalAlignment = bottomDock and Enum.VerticalAlignment.Bottom or Enum.VerticalAlignment.Top
		end
		-- Match toast text to the SmartBar's horizontal third of the screen.
		local barX = smartBarOpen and centerOf(smartBar).X or dragCenter.X
		local xRatio = (barX - originX) / math.max(viewport.X, 1)
		local alignment = xRatio < 1 / 3 and Enum.TextXAlignment.Left
			or (xRatio > 2 / 3 and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center)
		-- Include the hidden template so new toasts inherit the current alignment.
		for _, toast in ipairs(toastsContainer:GetChildren()) do
			local title = toast:FindFirstChild("Title")
			if title and title:IsA("TextLabel") and title.TextXAlignment ~= alignment then
				title.TextXAlignment = alignment
			end
		end
		local targetLeft = math.clamp(dragCenter.X - toastSize.X * 0.5,
			originX + margin, math.max(originX + margin, originX + viewport.X - toastSize.X - margin))
		local targetTop = math.clamp(bottomDock and above or below,
			topEdge, math.max(topEdge, bottomEdge - toastSize.Y))
		toastsContainer.Position += UDim2.fromOffset(targetLeft - toastPos.X, targetTop - toastPos.Y)
	end

	function controller:syncPanels(dt)
		if not self.dragging then
			return
		end

		local alpha = 1 - math.pow(1e-8, dt)
		for _, name in ipairs({ "Character", "Scripts", "Playerlist" }) do
			local panel = UI:FindFirstChild(name)
			if panel and panel.Visible then
				panel.Position = panel.Position:Lerp(self:getPanelPosition(panel, panelSize(panel)), alpha)
				if altairValues.syncPanelPointer then
					altairValues.syncPanelPointer(panel, buttons:FindFirstChild(name))
				end
			end
		end
	end

	function controller:sync(dt, animateContents)
		self:syncContents(animateContents)
		self:syncPanels(dt or 1 / 60)
		self:syncDrag()
		self:syncToasts()
	end

	local function dragLineOffsets()
		local line = dragVisual and dragVisual:IsA("GuiObject") and dragVisual or drag
		local top = line.AbsolutePosition.Y - centerOf(drag).Y
		return top, top + line.AbsoluteSize.Y
	end

	function controller:clampDragTarget(target, dt)
		local viewport = screenSize()
		local originY = screenOriginY()
		-- Evaluate the requested center BEFORE clamping, so either zone stays reachable.
		if target.Y <= originY + viewport.Y * 0.22 then
			self.dragSide = -1
		elseif target.Y >= originY + viewport.Y * 0.50 then
			self.dragSide = 1
		end

		local lineTop, lineBottom = dragLineOffsets()
		local halfBar = smartBar.AbsoluteSize.Y * 0.5
		local wantedOffset = self.dragSide < 0
			and lineTop - 4 - halfBar
			or lineBottom + 4 + halfBar
		local barOffset
		if not smartBarOpen then
			-- Keep the closed line on the outer edge while dragging the hidden bar.
			barOffset = self.dragSide < 0 and (lineTop + halfBar) or (lineBottom - halfBar)
			self.animatedDragSide = nil
		else
			if self.animatedDragSide ~= self.dragSide then
				self.animatedDragSide = self.dragSide
				self.sideOffsetStart = self.barOffsetY
				self.sideOffsetElapsed = 0
			end
			self.sideOffsetElapsed = math.min((self.sideOffsetElapsed or 0) + (dt or 1 / 60), 0.28)
			local progress = self.sideOffsetElapsed / 0.28
			local eased = progress * progress * (3 - 2 * progress)
			barOffset = self.sideOffsetStart + (wantedOffset - self.sideOffsetStart) * eased
		end
		self.barOffsetY = barOffset
		-- Bounds of the visible line and SmartBar relative to the Drag center.
		-- Above: SmartBar's top sets minY. Below: its bottom sets maxY.
		local minY = originY + 8 - math.min(lineTop, barOffset - halfBar)
		local maxY = originY + viewport.Y - 8 - math.max(lineBottom, barOffset + halfBar)
		local halfDragX = drag.AbsoluteSize.X * 0.5
		-- If the screen cannot fit the group, retain the gap and minimize overflow.
		local y = minY <= maxY and math.clamp(target.Y, minY, maxY) or (minY + maxY) * 0.5
		return Vector2.new(
			math.clamp(target.X, halfDragX + 8, math.max(halfDragX + 8, viewport.X - halfDragX - 8)),
			y
		), barOffset
	end

	function controller:moveSmartBar(dragCenter, dt, barOffset)
		altairValues.smartBarPositionInitialized = true
		local viewport = screenSize()
		local half = smartBar.AbsoluteSize * 0.5
		local middle = viewport.X * 0.5
		local x = math.abs(dragCenter.X - middle) <= 36 and middle or dragCenter.X
		self.barOffsetY = barOffset
		-- Use the same rendered-line geometry as the target clamp; no competing Y clamp.
		moveCenter(smartBar, Vector2.new(
			math.clamp(x, half.X + 8, math.max(half.X + 8, viewport.X - half.X - 8)),
			dragCenter.Y + barOffset
		))
	end

	function controller:setDragVisual(width, transparency, duration)
		if not dragVisual or not dragVisual:IsA("GuiObject") then
			return
		end
		local goal = { Size = UDim2.fromOffset(width, 4) }
		if dragVisual:IsA("ImageLabel") or dragVisual:IsA("ImageButton") then
			goal.ImageTransparency = transparency
		else
			goal.BackgroundTransparency = transparency
		end
		tweenService:Create(dragVisual, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), goal):Play()
	end

	function controller:bind(toggleSmartBar)
		local barCenter, dragCenter = centerOf(smartBar), centerOf(drag)
		smartBar.AnchorPoint = Vector2.new(0.5, 0.5)
		drag.AnchorPoint = Vector2.new(0.5, 0.5)
		moveCenter(smartBar, clampCenter(smartBar, barCenter, 8))
		moveCenter(drag, clampCenter(drag, dragCenter, 8))

		drag.Size = UDim2.fromOffset(150, 20)
		drag.BackgroundTransparency = 1
		drag.Visible = true

		if dragVisual then
			dragVisual.Visible = true
			dragVisual.AnchorPoint = Vector2.new(0.5, 0.5)
			dragVisual.Position = UDim2.fromScale(0.5, 0.5)
			dragVisual.BorderSizePixel = 0
		end

		local interact = drag.Interact
		interact.Visible = true
		interact.Active = true
		interact.BackgroundTransparency = 1
		if interact:IsA("TextButton") or interact:IsA("TextLabel") or interact:IsA("TextBox") then
			interact.TextTransparency = 1
		end
		if interact:IsA("ImageButton") or interact:IsA("ImageLabel") then
			interact.ImageTransparency = 1
		end

		self:setDragVisual(100, 0.45, 0)

		track(drag:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if not self.dragging then self:syncToasts() end
		end))

		track(drag.Interact.MouseEnter:Connect(function()
			self.dragHovered = true
			if not self.dragging then
				tweenService:Create(drag, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(165, 22),
				}):Play()
				self:setDragVisual(120, 0, 0.25)
			end
		end))

		track(drag.Interact.MouseLeave:Connect(function()
			self.dragHovered = false
			if not self.dragging then
				tweenService:Create(drag, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(150, 20),
				}):Play()
				self:setDragVisual(100, 0.45, 0.25)
			end
		end))

		track(drag.Interact.InputBegan:Connect(function(input)
			local inputType = input.UserInputType
			if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
				return
			end

			self:cancelDragPositionTween()
			self.dragging = true
			self.dragMoved = false
			self.touchInput = inputType == Enum.UserInputType.Touch and input or nil
			self.lastPointer = pointerPosition(self.touchInput and input or nil)
			self.startPointer = self.lastPointer
			self.lastRenderPointer = self.lastPointer
			self.grabOffset = centerOf(drag) - self.lastPointer
			self.dragSide = self:getDock() == "top" and -1 or 1
			self.barOffsetY = centerOf(smartBar).Y - centerOf(drag).Y
			if self.onDragBegin then self:onDragBegin() end
			self.animatedDragSide = nil
			tweenService:Create(drag, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(175, 24),
			}):Play()
			self:setDragVisual(110, 0, 0.25)
		end))

		track(userInputService.InputChanged:Connect(function(input)
			if not self.dragging then return end
			if self.touchInput then
				if input == self.touchInput then self.lastPointer = pointerPosition(input) end
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				self.lastPointer = pointerPosition(input)
			end
		end))

		local function finish(input)
			if not self.dragging then
				return
			end
			if input and self.touchInput and input ~= self.touchInput then
				return
			end

			self.dragging = false
			self.touchInput = nil
			if self.viewportFitPending then self:fitViewport() end
			tweenService:Create(drag, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(150, 20),
			}):Play()
			self:setDragVisual(100, self.dragHovered and 0 or 0.45, 0.3)
			self:sync(1 / 60, true)
			if self.dragMoved then self:savePosition() end

			if not self.dragMoved and toggleSmartBar then
				toggleSmartBar()
			end
		end

		track(userInputService.InputEnded:Connect(function(input)
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
				finish(input)
			end
		end))
		track(userInputService.WindowFocusReleased:Connect(function()
			finish()
		end))

		track(runService.RenderStepped:Connect(function(dt)
			if not UI.Parent or self.initializing then
				return
			end

			if self.dragging then
				local pointer = self.touchInput and self.lastPointer or pointerPosition()
				if (pointer - self.startPointer).Magnitude > 6 then
					self.dragMoved = true
				end

				self.lastRenderPointer = pointer

				if self.dragMoved then
					local dragCenter, barOffset = self:clampDragTarget(pointer + self.grabOffset, dt)
					moveCenter(drag, dragCenter)
					self:moveSmartBar(dragCenter, dt, barOffset)
					self:syncContents(true)
					self:syncPanels(dt)
					self:syncToasts(dragCenter)
				end
			else
				self.idleAccumulator += dt
				if self.idleAccumulator >= 1 / 30 then
					self.idleAccumulator = 0
					self:sync(dt, false)
				end
			end
		end))
	end

	function controller:fitViewport()
		if self.initializing or self.viewportFitQueued then return end
		self.viewportFitQueued = true
		task.defer(function()
			runService.RenderStepped:Wait()
			self.viewportFitQueued = false
			if not UI.Parent then return end
			if self.dragging then self.viewportFitPending = true; return end
			self.viewportFitPending = false
			local center = centerOf(smartBar)
			local target = clampCenter(smartBar, center, 8)
			if (center - target).Magnitude < 0.5 then return end
			self:cancelDragPositionTween()
			moveCenter(smartBar, target)
			runService.RenderStepped:Wait()
			if not UI.Parent or self.dragging then return end
			drag.Position = positionAtRenderedCenter(drag, smartBarOpen and self:getRestDragCenter() or self:getClosedDragCenter())
			self:syncContents(false)
			self:syncPanels(1 / 60)
			self:syncToasts()
			self.viewportReflows = (self.viewportReflows or 0) + 1
		end)
	end

	function controller:panelSize(panel)
		return panelSize(panel)
	end

	return controller
end)()

local updateBackpackLayout
do
	local entries, activePanel, refresh = {}, nil, 0

	local function visible(v)
		if not v.Parent then return false end
		while v do
			if v:IsA("GuiObject") and not v.Visible or v:IsA("ScreenGui") and not v.Enabled then return false end
			v = v.Parent
		end
		return true
	end

	local function parentHeight(v)
		local parent = v.Parent
		while parent and not parent:IsA("GuiBase2d") do parent = parent.Parent end
		return math.max(1, parent and parent.AbsoluteSize.Y or camera.ViewportSize.Y)
	end

	local function scan()
		local found = {}
		for _, root in ipairs({ coreGui, localPlayer:FindFirstChildOfClass("PlayerGui") }) do
			for _, v in ipairs(root:GetDescendants()) do
				local name = v.Name:lower()
				if v:IsA("GuiObject") and not v:IsDescendantOf(UI)
					and (name:find("backpack", 1, true) or name:find("hotbar", 1, true))
					and visible(v)
				then
					found[v] = true
				end
			end
		end

		local roots = {}
		for v in pairs(found) do
			local parent, nested = v.Parent, false
			while parent do
				if found[parent] then nested = true break end
				parent = parent.Parent
			end
			if not nested then roots[v] = true end
		end

		for v, entry in pairs(entries) do
			if not roots[v] then
				if v.Parent and entry.shift > 0 then v.Position = entry.position end
				entries[v] = nil
			end
		end

		for v in pairs(roots) do
			if not entries[v] then
				local coreBackpack = v:IsDescendantOf(coreGui) and v.Name == "Backpack" and v.Parent.Name == "RobloxGui"
				entries[v] = { position = coreBackpack and UDim2.new() or v.Position, shift = 0, core = coreBackpack }
			elseif not smartBarOpen and entries[v].shift == 0 and not entries[v].core then
				entries[v].position = v.Position
			end

			local bounds, hasHotbar
			for _, candidate in ipairs(v:GetDescendants()) do
				if candidate:IsA("GuiObject") and candidate.Name:lower():find("hotbar", 1, true) then
					hasHotbar = true
					if visible(candidate) and candidate.AbsoluteSize.Y > 0 and (not bounds or candidate.AbsoluteSize.Y < bounds.AbsoluteSize.Y) then
						bounds = candidate
					end
				end
			end
			if not hasHotbar then bounds = v end
			if bounds then
				entries[v].bounds = bounds
			else
				if entries[v].shift > 0 then v.Position = entries[v].position end
				entries[v] = nil
			end
		end
	end

	updateBackpackLayout = function(panel)
		activePanel, refresh = panel, 0
	end

	local accumulator = 0
	local connection = track(runService.RenderStepped:Connect(function(dt)
		if not UI.Parent then return end
		accumulator += dt
		if accumulator < 1 / 30 then return end
		dt, accumulator = accumulator, 0

		refresh -= dt
		if refresh <= 0 then
			scan()
			refresh = 2
		end

		local bottomDock = smartBarOpen and altairValues.smartBarLayout:getDock() == "bottom"
		local ceiling = bottomDock and smartBar.AbsolutePosition.Y or nil
		if ceiling and activePanel and activePanel.Parent and activePanel.Visible then
			ceiling = math.min(ceiling, activePanel.AbsolutePosition.Y)
		end

		local alpha = 1 - math.exp(-14 * dt)
		for v, entry in pairs(entries) do
			local bounds = entry.bounds
			if v.Parent and bounds.Parent and visible(bounds) and bounds.AbsoluteSize.Y > 0 then
				local height = parentHeight(v)
				local displacement = (entry.position.Y.Scale - v.Position.Y.Scale) * height
				local restingTop = bounds.AbsolutePosition.Y + displacement
				local target = ceiling and math.max(0, restingTop + bounds.AbsoluteSize.Y - ceiling + 20) or 0
				entry.shift += (target - entry.shift) * alpha
				if math.abs(entry.shift - target) < 0.1 then entry.shift = target end
				if ceiling or entry.shift > 0 or displacement ~= 0 then
					v.Position = entry.shift == 0 and entry.position or entry.position - UDim2.new(0, 0, entry.shift / height, 0)
				end
			end
		end
	end))

	UI.Destroying:Connect(function()
		connection:Disconnect()
		for v, entry in pairs(entries) do
			if v.Parent and entry.shift > 0 then v.Position = entry.position end
		end
	end)
end

local function getPanelButtonGeometry(panel, button)
	if not (panel and button and panel.Parent and button.Parent) then
		return nil, nil
	end

	local buttonSize = button.AbsoluteSize
	if buttonSize.X <= 0 or buttonSize.Y <= 0 then
		return button.Size, panel.Position
	end

	local anchor = panel.AnchorPoint
	local currentAnchor = panel.AbsolutePosition + Vector2.new(
		panel.AbsoluteSize.X * anchor.X,
		panel.AbsoluteSize.Y * anchor.Y
	)
	local targetAnchor = button.AbsolutePosition + Vector2.new(
		buttonSize.X * anchor.X,
		buttonSize.Y * anchor.Y
	)
	local delta = targetAnchor - currentAnchor

	return UDim2.fromOffset(buttonSize.X, buttonSize.Y),
		panel.Position + UDim2.fromOffset(delta.X, delta.Y)
end

altairValues.panelPointerConnections = altairValues.panelPointerConnections or {}

altairValues.getPanelPointer = function(panel)
	if not panel then
		return nil
	end

	local pointer = panel:FindFirstChild("Pointer")
	if not pointer and panel ~= characterPanel then
		local source = characterPanel:FindFirstChild("Pointer")
		if source then
			pointer = source:Clone()
			pointer.Name = "Pointer"
			pointer.Parent = panel
		end
	end

	if pointer and pointer:IsA("GuiObject") then
		pointer.Visible = true
		pointer.Size = UDim2.fromOffset(12, 12)
		pointer.AnchorPoint = Vector2.new(0.5, 0.5)
		pointer.Rotation = 45
		pointer.BorderSizePixel = 0
		pointer.BackgroundColor3 = panel.BackgroundColor3
		pointer.BackgroundTransparency = panel.BackgroundTransparency

		local stroke = pointer:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 1 end
		local gradient = pointer:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Enabled = false end
		local corner = pointer:FindFirstChildOfClass("UICorner")
		if corner then corner.CornerRadius = UDim.new(0, 1) end

		return pointer
	end

	return nil
end

altairValues.syncPanelPointer = function(panel, button)
	local pointer = altairValues.getPanelPointer(panel)
	if not (pointer and button and button:IsA("GuiObject")) then
		return nil
	end

	local dock = altairValues.smartBarLayout:getDock()
	local panelPos, panelSize = panel.AbsolutePosition, panel.AbsoluteSize
	local buttonCenter = button.AbsolutePosition + button.AbsoluteSize * 0.5
	local edgePadding = 18

	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Rotation = 45

	local x = math.clamp(buttonCenter.X - panelPos.X, edgePadding, math.max(edgePadding, panelSize.X - edgePadding))
	pointer.Position = UDim2.fromOffset(x, dock == "top" and 0 or panelSize.Y)

	pointer.Visible = true
	return pointer
end

altairValues.setPanelPointerVisible = function(panel, button, visible, duration)
	local pointer = altairValues.syncPanelPointer(panel, button)
	if not pointer then
		return
	end

	local goal = {}
	if pointer:IsA("ImageLabel") or pointer:IsA("ImageButton") then
		goal.ImageTransparency = visible and 0 or 1
	elseif pointer:IsA("Frame") or pointer:IsA("ScrollingFrame") then
		goal.BackgroundTransparency = visible and panel.BackgroundTransparency or 1
	else
		pcall(function()
			goal.BackgroundTransparency = visible and 0 or 1
		end)
	end

	if next(goal) then
		tweenService:Create(
			pointer,
			TweenInfo.new(duration or 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			goal
		):Play()
	end
end

altairValues.bindPanelPointer = function(panel, button)
	if not (panel and button and button:IsA("GuiObject")) then
		return
	end

	if altairValues.panelPointerConnections[panel] then
		altairValues.syncPanelPointer(panel, button)
		return
	end

	local pointer = altairValues.getPanelPointer(panel)
	if not pointer then
		return
	end

	local function sync()
		if panel.Parent and button.Parent then
			altairValues.syncPanelPointer(panel, button)
		end
	end

	altairValues.panelPointerConnections[panel] = {
		track(button:GetPropertyChangedSignal("AbsolutePosition"):Connect(sync)),
		track(button:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)),
		track(panel:GetPropertyChangedSignal("AbsolutePosition"):Connect(sync)),
		track(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)),
	}

	sync()
end

local function closePanel(panelName, openingOther)
	local button = smartBar.Back.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end

	debounce = true

	local panelSize = panel.Name == "Character" and characterPanelSize
		or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
		or UDim2.fromOffset(581, 246)

	local buttonSize, buttonPosition = getPanelButtonGeometry(panel, button)
	buttonSize = buttonSize or button.Size
	buttonPosition = buttonPosition or panel.Position

	if panel.Name == "Playerlist" and altairValues.playerlistUI.prepareClose then
		altairValues.playerlistUI:prepareClose()

		local subtitle = altairValues.playerlistUI.subtitle
		if subtitle and (
			subtitle:IsA("TextLabel")
			or subtitle:IsA("TextButton")
			or subtitle:IsA("TextBox")
		) then
			tweenService:Create(
				subtitle,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			):Play()
		end
	end

	if not openingOther then
		if panel.Name == "Character" then -- Character Panel Animation
			tweenService:Create(characterPanel.Subtitle, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(characterPanel.Interactions.PropertiesTitle, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(characterPanel.Interactions.ActionsTitle, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			for _, divider in ipairs({ characterPanel.Interactions.HeaderDivider, characterPanel.Interactions.ActionsDivider, characterPanel.Interactions.PropertiesDivider }) do
				tweenService:Create(divider, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			end

			for _, data in ipairs(altairValues.sliders) do
				local slider = data.object
				if slider then
					data.active = false
					slider.Value:ReleaseFocus()
					tweenService:Create(slider, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(slider.Progress, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(slider.Track, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(slider.Progress.Knob, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(slider.Progress.Knob.Center, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(slider.Progress.Knob.Glow, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
					tweenService:Create(slider.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
					tweenService:Create(slider.Information, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
					tweenService:Create(slider.Value, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
				end
			end

			for _, action in ipairs(altairValues.actions) do
				local actionObject = actionButton(action)
				if actionObject then
					tweenService:Create(actionObject, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					tweenService:Create(actionObject.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
					tweenService:Create(actionObject.Icon, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
					tweenService:Create(actionObject.Title, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
					if actionObject.Parent == characterPanel.Interactions.Toggles then
						tweenService:Create(actionObject.Subtitle, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
						tweenService:Create(actionObject.Glow, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
					end
				end
			end

			tweenService:Create(characterPanel.Interactions.Reset, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			for _, actionObject in ipairs({ characterPanel.Interactions.Serverhop, characterPanel.Interactions.Rejoin }) do
				tweenService:Create(actionObject, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
				tweenService:Create(actionObject.Title, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
				tweenService:Create(actionObject.Icon, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
				tweenService:Create(actionObject.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			end
		elseif panel.Name == "Scripts" then -- Scripts Panel Animation
			for _, scriptButton in ipairs(scriptsPanel.Interactions.Selection:GetChildren()) do
				if scriptButton.ClassName == "Frame" then
					tweenService:Create(scriptButton, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					if scriptButton:FindFirstChild("Icon") then
						tweenService:Create(scriptButton.Icon, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
					end
					tweenService:Create(scriptButton.Title, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
					if scriptButton:FindFirstChild("Subtitle") then
						tweenService:Create(scriptButton.Subtitle, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
					end
					tweenService:Create(scriptButton.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
				end
			end
		elseif panel.Name == "Playerlist" then -- Playerlist Panel Animation
			altairValues.playerlistUI.rowsOpening = false

			if altairValues.playerlistUI.headerDivider then
				altairValues.playerlistUI:_setVisual(altairValues.playerlistUI.headerDivider, false, 0.18)
			end

			for _, row in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
				if row:IsA("GuiObject") and row:GetAttribute("AltairRuntimePlayer") == true then
					tweenService:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					for _, playerIns in ipairs(row:GetDescendants()) do
						if playerIns:IsA("UIStroke") then
							tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
						else
							local properties = altairValues.transparencyProperties[playerIns.ClassName]
							if properties then
								local goal = {}
								for _, property in ipairs(properties) do
									goal[property] = 1
								end
								tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), goal):Play()
							end
						end
					end
				end
			end

			tweenService:Create(playerlistPanel.Interactions.SearchFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.Icon, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.SearchBox, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.List, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ScrollBarImageTransparency = 1 }):Play()
		end

		altairValues.setPanelPointerVisible(panel, button, false, 0.2)
		tweenService:Create(panel.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		tweenService:Create(panel.Title, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(panel.UIStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
		task.wait(0.03)

		tweenService:Create(panel, TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(panel, TweenInfo.new(1.1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Size = buttonSize }):Play()
		tweenService:Create(panel, TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), { Position = buttonPosition }):Play()
	end

	-- Animate interactive elements
	if openingOther then
		local offsetY = altairValues.smartBarLayout:getDock() == "top" and -45 or 45
		tweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {
			Position = panel.Position + UDim2.fromOffset(0, offsetY),
		}):Play()
		wipeTransparency(panel, 1, true, true, 0.3)
	end

	task.wait(0.5)
	panel.Size = panelSize
	panel.Visible = false
	if not openingOther and altairValues.smartBarLayout.activePanel == panel then
		altairValues.smartBarLayout.activePanel = nil
	end
	if not openingOther then updateBackpackLayout() end
	altairValues.smartBarLayout:sync(1 / 60, false)

	debounce = false
end

local function openPanel(panelName)
	if homeOpen then closeHome() end
	if settingsPanel.Visible then closeSettings() end
	if debounce then
		return
	end
	local button = smartBar.Back.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end

	debounce = true

	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Back.Buttons:FindFirstChild(otherPanel.Name) then
			if isPanel(otherPanel.Name) and otherPanel.Visible then
				task.spawn(closePanel, otherPanel.Name, true)
				task.wait()
			end
		end
	end

	local panelSize = panel.Name == "Character" and characterPanelSize
		or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
		or UDim2.fromOffset(581, 246)

	-- Playerlist reset writes its full authored panel size. Do that first, then
	-- collapse the shell exactly like Character/Scripts before the opening tween.
	if panel.Name == "Playerlist" and altairValues.playerlistUI.reset then
		altairValues.playerlistUI.rowsOpening = true
		altairValues.playerlistUI:reset(true)
	end

	local buttonSize, buttonPosition = getPanelButtonGeometry(panel, button)
	panel.Size = buttonSize or button.Size
	panel.Position = buttonPosition or panel.Position

	wipeTransparency(panel, 1, true)

	panel.Visible = true
	altairValues.smartBarLayout.activePanel = panel
	altairValues.bindPanelPointer(panel, button)
	altairValues.syncPanelPointer(panel, button)

	updateBackpackLayout(panel)

	tweenService:Create(panel, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.1 }):Play()
	tweenService:Create(panel, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), { Size = panelSize }):Play()
	tweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {
		Position = altairValues.smartBarLayout:getPanelPosition(panel, panelSize),
	}):Play()

	task.wait(0.4)

	altairValues.setPanelPointerVisible(panel, button, true, 0.45)
	tweenService:Create(panel.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	task.wait(0.05)
	tweenService:Create(panel.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(panel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.95 }):Play()
	task.wait(0.05)

	-- Animate interactive elements
	if panel.Name == "Character" then -- Character Panel Animation
		tweenService:Create(characterPanel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.7 }):Play()
		tweenService:Create(characterPanel.Subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.PropertiesTitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.ActionsTitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.HeaderDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
		tweenService:Create(characterPanel.Interactions.ActionsDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.35 }):Play()
		tweenService:Create(characterPanel.Interactions.PropertiesDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.35 }):Play()

		for _, data in ipairs(altairValues.sliders) do
			local slider = data.object
			if slider then
				slider.Progress.Size = UDim2.new(0, 0, slider.Track.Size.Y.Scale, slider.Track.Size.Y.Offset)
				updateSlider(data, data.value)
				tweenService:Create(slider.Track, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(slider.Progress, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(slider.Progress.Knob, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(slider.Progress.Knob.Center, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(slider.Progress.Knob.Glow, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0.42 }):Play()
				tweenService:Create(slider.Information, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
				tweenService:Create(slider.Value, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
			end
		end
		updateSliderPadding()

		for _, action in ipairs(altairValues.actions) do
			local actionObject = actionButton(action)
			if actionObject then
				local quickToggle = actionObject.Parent == characterPanel.Interactions.Toggles
				actionObject.Icon.Image = "rbxassetid://" .. action.images[action.enabled and 1 or 2]
				tweenService:Create(actionObject, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { BackgroundTransparency = action.enabled and 0.02 or (quickToggle and 0.12 or 0.1) }):Play()
				tweenService:Create(actionObject.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Transparency = action.enabled and 0.3 or (quickToggle and 0.32 or 0.91) }):Play()
				tweenService:Create(actionObject.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0 or 0.15 }):Play()
				tweenService:Create(actionObject.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
				if quickToggle then
					actionObject.Subtitle.Text = action.enabled and "Enabled" or "Disabled"
					tweenService:Create(actionObject.Subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = action.enabled and 0 or 0.25 }):Play()
					tweenService:Create(actionObject.Glow, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0.15 or 0.8 }):Play()
				end
			end
		end

		tweenService:Create(characterPanel.Interactions.Reset, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
		for _, actionObject in ipairs({ characterPanel.Interactions.Serverhop, characterPanel.Interactions.Rejoin }) do
			tweenService:Create(actionObject, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.1 }):Play()
			tweenService:Create(actionObject.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
			tweenService:Create(actionObject.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0.5 }):Play()
			tweenService:Create(actionObject.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.91 }):Play()
		end
	elseif panel.Name == "Scripts" then -- Scripts Panel Animation
		for _, scriptButton in ipairs(scriptsPanel.Interactions.Selection:GetChildren()) do
			if scriptButton.ClassName == "Frame" then
				tweenService:Create(scriptButton, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				if scriptButton:FindFirstChild("Icon") then
					tweenService:Create(scriptButton.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
				end
				tweenService:Create(scriptButton.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
				if scriptButton:FindFirstChild("Subtitle") then
					tweenService:Create(scriptButton.Subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
				end
				tweenService:Create(scriptButton.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.2 }):Play()
			end
		end
	elseif panel.Name == "Playerlist" then -- Playerlist Panel Animation
		-- Re-prime every visible list row here, after the shell delay, in case an
		-- asynchronous player refresh completed while the panel was expanding.
		for _, listChild in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
			if listChild:IsA("GuiObject")
				and listChild ~= altairValues.playerlistUI.template
				and (
					listChild:GetAttribute("AltairRuntimePlayer") == true
					or listChild.Name == "Placeholder"
				)
			then
				for _, visual in ipairs(listChild:GetDescendants()) do
					if visual:IsA("UIStroke") then
						visual.Enabled = true
						visual.Transparency = 1
					elseif visual.Name ~= "Interact" then
						local properties = altairValues.transparencyProperties[visual.ClassName]
						if properties then
							for _, property in ipairs(properties) do
								visual[property] = 1
							end
						end
					end
				end
			end
		end

		local subtitle = altairValues.playerlistUI.subtitle
		if subtitle and (
			subtitle:IsA("TextLabel")
			or subtitle:IsA("TextButton")
			or subtitle:IsA("TextBox")
		) then
			tweenService:Create(
				subtitle,
				TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{
					TextTransparency = altairValues.playerlistUI.subtitleTextTransparency
						or 0,
				}
			):Play()
		end
		if altairValues.playerlistUI.headerDivider then
			altairValues.playerlistUI.headerDivider.Visible = true
			altairValues.playerlistUI:_setVisual(altairValues.playerlistUI.headerDivider, true, 0.45)
		end

		for _, row in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
			if row:IsA("GuiObject") and row:GetAttribute("AltairRuntimePlayer") == true then
				local rowPlayer = players:GetPlayerByUserId(
					tonumber(row:GetAttribute("AltairPlayerUserId")) or 0
				)

				-- Refresh content first, then explicitly prime the row hidden so refreshed
				-- avatars/strokes cannot flash before the entrance tween.
				if rowPlayer then
					altairValues.playerlistUI:refreshRuntimePlayer(rowPlayer, row)
				end

				row.BackgroundTransparency = 1

				for _, playerIns in ipairs(row:GetDescendants()) do
					if playerIns:IsA("UIStroke") then
						playerIns.Enabled = true
						playerIns.Transparency = 1
					elseif playerIns.Name ~= "Interact" then
						local properties = altairValues.transparencyProperties[playerIns.ClassName]
						if properties then
							for _, property in ipairs(properties) do
								if playerIns:GetAttribute("AltairPlayerOpen_" .. property) ~= nil then
									playerIns[property] = 1
								end
							end
						end
					end
				end

				tweenService:Create(
					row,
					TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 0 }
				):Play()

				for _, playerIns in ipairs(row:GetDescendants()) do
					if playerIns:IsA("UIStroke") then
						tweenService:Create(
							playerIns,
							TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
							{ Transparency = 0.12 }
						):Play()
					elseif playerIns.Name ~= "Interact" then
						local properties = altairValues.transparencyProperties[playerIns.ClassName]
						if properties then
							local goal = {}
							for _, property in ipairs(properties) do
								local stored = playerIns:GetAttribute("AltairPlayerOpen_" .. property)
								if stored ~= nil then
									goal[property] = stored
								end
							end
							if next(goal) then
								tweenService:Create(
									playerIns,
									TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
									goal
								):Play()
							end
						end
					end
				end
			end
		end

		tweenService:Create(playerlistPanel.Interactions.SearchFrame, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
		tweenService:Create(playerlistPanel.Interactions.SearchFrame.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
		task.wait(0.01)
		tweenService:Create(playerlistPanel.Interactions.SearchFrame.SearchBox, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(playerlistPanel.Interactions.SearchFrame.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.2 }):Play()
		task.wait(0.05)
		tweenService:Create(playerlistPanel.Interactions.List, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { ScrollBarImageTransparency = 0.7 }):Play()

		task.delay(0.46, function()
			if checkAltair() and playerlistPanel.Visible then
				altairValues.playerlistUI.rowsOpening = false
				altairValues.playerlistUI:_highlightSelected()
			end
		end)
	end

	task.wait(0.45)
	debounce = false
end

altairValues.smartBarLayout.onDragBegin = function(self)
	for _, panelName in ipairs({ "Character", "Scripts", "Playerlist" }) do
		local panel = UI:FindFirstChild(panelName)
		if panel and panel.Visible then
			self.activePanel = nil
			task.spawn(closePanel, panelName, true)
			break
		end
	end
end

local function rejoin()
	altairValues.activity:record("Rejoin requested", "Current server")
	queueNotification("Rejoining Session", "We're queueing a rejoin to this session, give us a moment.", 4400696294)

	if #players:GetPlayers() <= 1 then
		task.wait()
		teleportService:Teleport(placeId, localPlayer)
	else
		teleportService:TeleportToPlaceInstance(placeId, jobId, localPlayer)
	end
end

altairValues.serverHop = (function()
	local controller = { busy = false, generation = 0, attempt = 0 }
	local historyKey = "AltairServerHop_" .. tostring(placeId)
	local historyPath = altairValues.altairFolder .. "/serverhop-" .. tostring(placeId) .. ".altair"
	local history
	pcall(function() history = teleportService:GetTeleportSetting(historyKey) end)
	if type(history) ~= "table" or history.version ~= 1 then
		pcall(function()
			if readfile and (not isfile or isfile(historyPath)) then
				history = httpService:JSONDecode(readfile(historyPath))
			end
		end)
	end
	if type(history) == "table" and history.version == 1 then
		controller.previous = history.current == jobId and history.previous or history.current
		if type(controller.previous) ~= "string" then controller.previous = nil end
	end
	-- Record arrivals, not attempted destinations, so failed hops never become history.
	history = { version = 1, current = jobId, previous = controller.previous }
	pcall(function() teleportService:SetTeleportSetting(historyKey, history) end)
	if writefile then pcall(function()
		checkFolder()
		writefile(historyPath, httpService:JSONEncode(history))
	end) end

	local function positive(value)
		return type(value) == "number" and value == value and value > 0 and value < math.huge
	end

	function controller:collect()
		local candidates, legacy, seen, cursors = {}, {}, { [jobId] = true }, {}
		if self.previous then seen[self.previous] = true end
		local cursor
		local received = false
		-- Follow the available pages with a bounded retry budget; no background scans.
		for page = 1, 20 do
			local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100"
			if cursor then url ..= "&cursor=" .. httpService:UrlEncode(cursor) end
			local response
			for retry = 1, 3 do
				local ok, data = pcall(function() return httpService:JSONDecode(game:HttpGetAsync(url)) end)
				if ok and type(data) == "table" and type(data.data) == "table" then
					response = data
					break
				end
				if retry < 3 then task.wait(0.5 * retry) end
			end
			if not response and page == 1 then
				-- Retry the original server-list request before giving up on discovery.
				local ok, data = pcall(function()
					return httpService:JSONDecode(game:HttpGetAsync("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"))
				end)
				if ok and type(data) == "table" and type(data.data) == "table" then response = data end
			end
			if not response then break end
			received = true
			for _, server in ipairs(response.data) do
				if type(server) == "table" and type(server.id) == "string" and server.id ~= ""
					and not seen[server.id] and positive(server.maxPlayers)
					and type(server.playing) == "number" and server.playing >= 0 and server.playing < server.maxPlayers then
					seen[server.id] = true
					local candidate = { id = server.id, ping = positive(server.ping) and server.ping or nil,
						fps = positive(server.fps) and server.fps or 0, playing = server.playing }
					table.insert(legacy, candidate)
					if candidate.ping then table.insert(candidates, candidate) end
				end
			end
			cursor = response.nextPageCursor
			if type(cursor) ~= "string" or cursor == "" or cursors[cursor] then break end
			cursors[cursor] = true
			if page < 20 then task.wait(0.25) end
		end
		table.sort(candidates, function(a, b)
			if a.ping ~= b.ping then return a.ping < b.ping end
			if a.fps ~= b.fps then return a.fps > b.fps end
			if a.playing ~= b.playing then return a.playing > b.playing end
			return a.id < b.id
		end)
		self.usingLegacy = #candidates == 0 and #legacy > 0
		if self.usingLegacy then
			-- Original preference: highest population among joinable eligible servers.
			table.sort(legacy, function(a, b)
				if a.playing ~= b.playing then return a.playing > b.playing end
				return a.id < b.id
			end)
			candidates = legacy
		end
		return candidates, received
	end

	function controller:tryNext(generation)
		if generation ~= self.generation or not self.busy or not checkAltair() then return end
		self.attempt += 1
		local server = self.candidates[self.attempt]
		if not server or self.attempt > 3 then
			self.busy, self.waiting, self.target = false, false, nil
			queueNotification("Teleport Failed", "The selected servers could not accept the hop. Try again in a moment.", 4370317928)
			return
		end
		self.target, self.waiting = server.id, true
		local attempt = self.attempt
		local message = self.usingLegacy and "Connection ranking is unavailable. Using the original Serverhop selection."
			or ("Joining the best available listed connection (" .. tostring(math.floor(server.ping or 0)) .. " ms reported ping).")
		queueNotification("Teleporting", message, 4335479121)
		task.wait(1)
		local ok = pcall(teleportService.TeleportToPlaceInstance, teleportService, placeId, server.id, localPlayer)
		if not ok and self.waiting and self.attempt == attempt then
			self.waiting = false
			task.defer(function() self:tryNext(generation) end)
			return
		end
		-- Do not start a second teleport merely because departure is taking time.
		task.delay(30, function()
			if self.generation == generation and self.attempt == attempt and self.waiting then
				self.busy, self.waiting, self.target = false, false, nil
			end
		end)
	end

	track(teleportService.TeleportInitFailed:Connect(function(player, _, _, failedPlace, options)
		if player ~= localPlayer or failedPlace ~= placeId or not controller.waiting then return end
		local failedId
		if options then pcall(function() failedId = options.ServerInstanceId end) end
		if failedId and failedId ~= "" and failedId ~= controller.target then return end
		controller.waiting = false
		local generation = controller.generation
		task.defer(function() controller:tryNext(generation) end)
	end))

	function controller:start()
		if self.busy then return end
		self.busy = true
		self.generation += 1
		self.attempt = 0
		queueNotification("Finding a server", "Checking available connections and excluding your current and previous server.", 4335479121)
		local ok, candidates, received = pcall(function() return self:collect() end)
		if not ok or not received or #candidates == 0 then
			self.busy = false
			queueNotification("No suitable server", (not ok or not received)
				and "Roblox's server list is unavailable. Try again shortly."
				or "No other joinable server was listed. Altair will not send you back to the current or previous server.", 4370317928)
			return
		end
		self.candidates = candidates
		self:tryNext(self.generation)
	end
	return controller
end)()

local function serverhop()
	if not altairValues.serverHop.busy then altairValues.activity:record("Server hop requested", "Searching for a server") end
	altairValues.serverHop:start()
end

local function leaveExperience()
	if pcall(function()
		game:Shutdown()
	end) then
		return
	end
	if pcall(teleportService.Teleport, teleportService, 0, localPlayer) then
		return
	end
	queueNotification("Unable to leave", "Altair couldn't close the experience from here, you'll need to leave manually.", 4370317928)
end

local function ensureFrameProperties()
	drag.Visible = false

	for _, panelName in ipairs({ "Character", "Scripts", "Playerlist" }) do
		local panel = UI:FindFirstChild(panelName)
		if panel then
			local pointer = altairValues.getPanelPointer(panel)
			if pointer then
				pointer.Visible = true
			end
		end
	end

	characterPanel.Visible = false
	customScriptPrompt.Visible = false
	disconnectedPrompt.Visible = false
	if altairValues.playerlistUI.init then
		altairValues.playerlistUI:init()
		if altairValues.playerlistUI.template then
			altairValues.playerlistUI.template.Visible = false
		end
		for _, child in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("AltairRuntimePlayer") ~= true then
				child.Visible = false
			end
		end
		altairValues.playerlistUI:reset(true)
	end
	gameDetectionPrompt.Visible = false
	homeContainer.Visible = false
	moderatorDetectionPrompt.Visible = false
	notificationContainer.Visible = true
	playerlistPanel.Visible = false
	scriptSearch.Visible = false
	scriptsPanel.Visible = false
	settingsPanel.Visible = false
	smartBar.Visible = false
	toastsContainer.Visible = true
	makeDraggable(settingsPanel)
end

moderatorDetectionPrompt.Leave.Leave.MouseButton1Click:Connect(function()
	if closeModPrompt then
		closeModPrompt()
	end
	leaveExperience()
end)

moderatorDetectionPrompt.Serverhop.MouseEnter:Connect(function()
	tweenService:Create(moderatorDetectionPrompt.ServersAvailableFade, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
end)

moderatorDetectionPrompt.Serverhop.MouseLeave:Connect(function()
	tweenService:Create(moderatorDetectionPrompt.ServersAvailableFade, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
end)

moderatorDetectionPrompt.Serverhop.MouseButton1Click:Connect(function()
	if not moderatorDetectionPrompt.Visible then
		return
	end
	task.spawn(serverhop)
	if closeModPrompt then
		closeModPrompt()
	end
end)

moderatorDetectionPrompt.Close.MouseButton1Click:Connect(function()
	if closeModPrompt then
		closeModPrompt()
	end
end)

local function promptModerator(player, role)
	if moderatorDetectionPrompt.Visible then
		return
	end

	moderatorDetectionPrompt.Size = UDim2.new(0, 283, 0, 175)
	moderatorDetectionPrompt.UIGradient.Offset = Vector2.new(0, 1)
	wipeTransparency(moderatorDetectionPrompt, 1, true)

	moderatorDetectionPrompt.DisplayName.Text = player.DisplayName
	moderatorDetectionPrompt.Rank.Text = role
	moderatorDetectionPrompt.Avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png"

	moderatorDetectionPrompt.Visible = true

	moderatorDetectionPrompt.Serverhop.Visible = true
	moderatorDetectionPrompt.ServersAvailableFade.Visible = true

	task.spawn(function()
		local serversAvailable = false
		local success, response = pcall(function()
			return httpService:JSONDecode(game:HttpGetAsync("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"))
		end)

		if success and response and response.data then
			for _, v in ipairs(response.data) do
				if type(v) == "table" and v.maxPlayers > v.playing and v.id ~= jobId then
					serversAvailable = true
					break
				end
			end
		end

		if not moderatorDetectionPrompt.Visible then
			return
		end

		moderatorDetectionPrompt.Serverhop.Visible = serversAvailable
		moderatorDetectionPrompt.ServersAvailableFade.Visible = serversAvailable
	end)

	tweenService:Create(moderatorDetectionPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 300, 0, 186) }):Play()
	tweenService:Create(moderatorDetectionPrompt.UIGradient, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.65) }):Play()
	tweenService:Create(moderatorDetectionPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Rank, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Leave, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
	task.wait(0.2)
	tweenService:Create(moderatorDetectionPrompt.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(moderatorDetectionPrompt.Leave, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	task.wait(0.3)
	tweenService:Create(moderatorDetectionPrompt.Close, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.6 }):Play()

	closeModPrompt = function()
		tweenService:Create(moderatorDetectionPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 283, 0, 175) }):Play()
		tweenService:Create(moderatorDetectionPrompt.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 1) }):Play()
		tweenService:Create(moderatorDetectionPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Rank, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Leave, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Leave, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(moderatorDetectionPrompt.Close, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		task.wait(0.5)
		moderatorDetectionPrompt.Visible = false
	end
end

local homeBlur = altairValues.lifecycle:own(Instance.new("BlurEffect"))
homeBlur.Size = 0
UI.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
homeContainer.Size=UDim2.fromScale(1,1)
homeContainer.Position=UDim2.fromScale(.5,.5)
homeContainer.AnchorPoint=Vector2.new(.5,.5)
homeContainer.BackgroundTransparency=1
homeContainer.Dim.Size=UDim2.fromScale(1,1)
homeContainer.Dim.Position=UDim2.fromOffset(0,0)
homeContainer.Dim.Visible=true
homeContainer.Dim.BackgroundTransparency=1
local homeContent=Instance.new("Frame")
homeContent.Name="Content" homeContent.Size=UDim2.fromOffset(1104,650)
homeContent.AnchorPoint=Vector2.new(.5,.5) homeContent.Position=UDim2.fromScale(.5,.5)
homeContent.BackgroundTransparency=1 homeContent.ZIndex=20 homeContent.Parent=homeContainer
homeContainer.Sidebar.Parent=homeContent homeContainer.Pages.Parent=homeContent
homeContent.Sidebar.Position=UDim2.fromOffset(32,80) homeContent.Sidebar.AnchorPoint=Vector2.zero
homeContent.Pages.Position=UDim2.fromOffset(32,130) homeContent.Pages.AnchorPoint=Vector2.zero

homeContent.Pages.ZIndex=20
homeContent.Sidebar.ZIndex=40
for _,page in ipairs(homeContent.Pages:GetChildren()) do
 page.Size=page.Size+UDim2.fromOffset(24,24)
 local padding=Instance.new("UIPadding",page)
 padding.PaddingLeft=UDim.new(0,12) padding.PaddingRight=UDim.new(0,12)
 padding.PaddingTop=UDim.new(0,12) padding.PaddingBottom=UDim.new(0,12)
end
for _,object in ipairs(homeContent:GetDescendants()) do
 if object:IsA("Frame") then object.ClipsDescendants=false
 elseif object:IsA("UIStroke") then object.Thickness=2 object.BorderStrokePosition=Enum.BorderStrokePosition.Inner end
end
local homeScale=Instance.new("UIScale",homeContent)
local function fitHome()
 local size=homeContainer.AbsoluteSize
 homeScale.Scale=math.max(.25,math.min(1,(size.X-40)/1104,(size.Y-160)/650))
end
fitHome()
track(homeContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHome))
local homeController = (function()
 local pages = homeContent:FindFirstChild('Pages')
 assert(pages and pages:FindFirstChild('Home') and pages:FindFirstChild('Friends') and pages:FindFirstChild('Games'), 'The published GUI is missing Home.Pages.Home/Friends/Games')
 local home, fp, gp = pages.Home, pages.Friends, pages.Games
 do
  local playingPanel=fp:FindFirstChild('InThisSession')
  local browser=fp:FindFirstChild('Browser')
  if playingPanel and playingPanel:IsA('GuiObject') then
   playingPanel.Visible=false
   if browser and browser:IsA('GuiObject') then
    local oldSize=browser.Size
    local rightScale=browser.Position.X.Scale+browser.Size.X.Scale
    local rightOffset=browser.Position.X.Offset+browser.Size.X.Offset
    local leftScale=playingPanel.Position.X.Scale
    local leftOffset=playingPanel.Position.X.Offset
    local newSize=UDim2.new(
     rightScale-leftScale,
     rightOffset-leftOffset,
     browser.Size.Y.Scale,
     browser.Size.Y.Offset
    )

    browser.Position=UDim2.new(leftScale,leftOffset,browser.Position.Y.Scale,browser.Position.Y.Offset)
    browser.Size=newSize

    local growScale=newSize.X.Scale-oldSize.X.Scale
    local growOffset=newSize.X.Offset-oldSize.X.Offset

    for _,name in ipairs({'List','Filters','States'}) do
     local object=browser:FindFirstChild(name)
     if object and object:IsA('GuiObject') then
      object.Size=UDim2.new(
       object.Size.X.Scale+growScale,
       object.Size.X.Offset+growOffset,
       object.Size.Y.Scale,
       object.Size.Y.Offset
      )
     end
    end

    local search=browser:FindFirstChild('SearchBox')
    if search and search:IsA('GuiObject') then
     search.Position=UDim2.new(
      search.Position.X.Scale+growScale,
      search.Position.X.Offset+growOffset,
      search.Position.Y.Scale,
      search.Position.Y.Offset
     )
    end
   end
  end
 end
 local alive, opened = true, false
 local connections, data, metadata = {}, {history={}, saved={}}, {}
 local friends, favorites, selectedFriend, selectedGame = {}, {}, nil, nil
 local friendFilter, gameFilter, activePage = 'All', 'Recent', 'Home'
 local friendBusy, favoriteBusy, friendError, favoriteError = false, false, nil, nil
 local lastFriends, lastFavorites = -math.huge, -math.huge
 local sessionStarted = os.clock()
 local renderFriends, renderGames, selectFriend, selectGame, refreshFriends, refreshFavorites, showPage, recordActivity
 local storePath = altairValues.altairFolder .. '/home-' .. tostring(localPlayer.UserId) .. '.json'
 local storageWarning = false
 local function connect(signal, fn) local c=signal:Connect(fn) table.insert(connections,c) return c end
 local function action(button, fn)
  if not button or not button:IsA('GuiButton') then return end
  connect(button.Activated,function() if alive then local ok,err=pcall(fn) if not ok then if alive then queueNotification('Home', 'Action failed: '..tostring(err), 4370336704) end end end end)
 end
 local function text(o, name, value) local v=o and o:FindFirstChild(name) if v and (v:IsA('TextLabel') or v:IsA('TextButton')) then v.Text=tostring(value or '') end end
 local function label(o, value) if o:FindFirstChild('Title') then o.Title.Text=value else o.Text=value end end
 local function head(id) return 'rbxthumb://type=AvatarHeadShot&id='..tostring(id)..'&w=150&h=150' end
 local function gameIcon(id) return tonumber(id) and tonumber(id)>0 and ('rbxthumb://type=GameIcon&id='..tostring(id)..'&w=150&h=150') or 'rbxasset://textures/loading/robloxTilt.png' end
 local function age(stamp)
  if not tonumber(stamp) or stamp<=0 then return 'Not recorded' end
  local seconds=math.max(0,os.time()-stamp)
  if seconds<60 then return 'Just now' elseif seconds<3600 then return math.floor(seconds/60)..'m ago' elseif seconds<86400 then return math.floor(seconds/3600)..'h ago' else return math.floor(seconds/86400)..'d ago' end
 end
 local function bounded(fn, seconds)
  local done, result = false, nil
  local worker=task.spawn(function() result=table.pack(pcall(fn)) done=true end)
  local deadline=os.clock()+(seconds or 15)
  repeat task.wait(.03) until done or not alive or os.clock()>=deadline
  if not alive or not done then pcall(task.cancel,worker) return nil,alive and 'Request timed out' or 'Closed' end
  if not result[1] then return nil,tostring(result[2]) end
  return result[2],nil
 end
 local function getJSON(url)
  local value, err=bounded(function()
   if not originalRequest then error('HTTP requests are unavailable') end
   local response=originalRequest({Url=url,Method='GET',Headers={Accept='application/json'}})
   assert(type(response)=='table','Invalid response')
   local status=tonumber(response.StatusCode) or 0
   assert(status>=200 and status<300, status==429 and 'Roblox rate limit; retry shortly' or ('Roblox request failed ('..status..')'))
   local decoded=httpService:JSONDecode(response.Body)
   assert(type(decoded)=='table','Invalid JSON response')
   return decoded
  end)
  return value,err
 end
 data.serverRegion=(function()
  local state={
   value=tostring(game:GetAttribute('ServerRegion') or workspace:GetAttribute('ServerRegion') or ''),
   busy=false,
   peer=nil,
   networkClient=getService('NetworkClient'),
   hiddenProperty=typeof(gethiddenproperty)=='function' and gethiddenproperty or nil,
   properties=typeof(getproperties)=='function' and getproperties or nil,
   hiddenProperties=typeof(gethiddenproperties)=='function' and gethiddenproperties or nil
  }

  local function validPublicIPv4(ip)
   if type(ip)~='string' then return nil end
   local a,b,c,d=ip:match('(%d+)%.(%d+)%.(%d+)%.(%d+)')
   a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
   if not a or not b or not c or not d or a>255 or b>255 or c>255 or d>255 then return nil end
   if a==10 or a==127 or a==0 or (a==169 and b==254) or (a==172 and b>=16 and b<=31) or (a==192 and b==168) then return nil end
   return string.format('%d.%d.%d.%d',a,b,c,d)
  end

  local function ipFromValue(value)
   local kind=typeof(value)
   if kind=='string' or kind=='number' then
    return validPublicIPv4(tostring(value))
   end
   if kind=='table' then
    for _,key in ipairs({'Value','value','Address','address','Peer','peer','Endpoint','endpoint','MachineAddress','RemoteAddress','ServerAddress'}) do
     local ip=ipFromValue(value[key])
     if ip then return ip end
    end
   end
   return nil
  end

  local function readProperty(object,name)
   local ok,value=pcall(function() return object[name] end)
   if ok then
    local ip=ipFromValue(value)
    if ip then return ip end
   end
   if state.hiddenProperty then
    local hiddenOk,hiddenValue=pcall(state.hiddenProperty,object,name)
    if hiddenOk then
     local ip=ipFromValue(hiddenValue)
     if ip then return ip end
    end
   end
   return nil
  end

  local function scanProperties(object)
   if not object then return nil end
   for _,name in ipairs({'MachineAddress','RemoteAddress','ServerAddress','PeerAddress','Address','Endpoint','Peer'}) do
    local ip=readProperty(object,name)
    if ip then return ip end
   end
   for _,provider in ipairs({state.properties,state.hiddenProperties}) do
    if provider then
     local ok,properties=pcall(provider,object)
     if ok and type(properties)=='table' then
      for key,value in pairs(properties) do
       local ip=ipFromValue(value)
       if ip then return ip end
       if type(key)=='string' then
        ip=readProperty(object,key)
        if ip then return ip end
       end
       if type(value)=='string' and value:match('^[%a_][%w_]*$') then
        ip=readProperty(object,value)
        if ip then return ip end
       end
      end
     end
    end
   end
   return nil
  end

  local function findServerIPv4()
   local ip=ipFromValue(game:GetAttribute('ServerIP')) or ipFromValue(workspace:GetAttribute('ServerIP')) or ipFromValue(state.peer)
   if ip then return ip end

   ip=scanProperties(state.networkClient)
   if ip then return ip end

   local ok,children=pcall(function() return state.networkClient:GetChildren() end)
   if ok then
    for _,object in ipairs(children) do
     if object:IsA('ClientReplicator') or object:IsA('NetworkReplicator') then
      ip=scanProperties(object)
      if ip then return ip end
     end
    end
   end

   local network=statsService:FindFirstChild('Network')
   if network then
    for _,item in ipairs(network:GetDescendants()) do
     local valueOk,value=pcall(function()
      if item.GetValueString then return item:GetValueString() end
     end)
     if valueOk then
      ip=ipFromValue(value)
      if ip then return ip end
     end
    end
   end

   return nil
  end

  local function lookupServerRegion(ip)
   local result,err=getJSON('https://ipapi.co/'..httpService:UrlEncode(ip)..'/json/')
   if not result or result.error then return nil,err or tostring(result and result.reason or 'Region lookup failed') end
   local city=tostring(result.city or '')
   local region=tostring(result.region_code or result.region or '')
   local country=tostring(result.country_code or result.country or '')
   local parts={}
   if city~='' and city~='nil' then table.insert(parts,city) end
   if region~='' and region~='nil' and region~=city then table.insert(parts,region) end
   if country~='' and country~='nil' then table.insert(parts,country) end
   if #parts==0 then return nil,'Region lookup returned no location' end
   return table.concat(parts,', '),nil
  end

  function state.refresh(force)
   local provided=game:GetAttribute('ServerRegion') or workspace:GetAttribute('ServerRegion')
   if provided and tostring(provided)~='' then
    state.value=tostring(provided)
    return
   end
   if state.busy or (state.value~='' and not force) then return end
   state.busy=true
   task.spawn(function()
    local ip=findServerIPv4()
    if not ip then
     state.busy=false
     if state.value=='' then state.value='Not available' end
     return
    end
    local region=lookupServerRegion(ip)
    state.busy=false
    if region then
     state.value=region
     homeContainer:SetAttribute('ResolvedServerIP',ip)
    elseif state.value=='' then
     state.value='Not available'
    end
   end)
  end

  return state
 end)()

 local function save()
  if not writefile or not readfile then
   if not storageWarning then storageWarning=true if alive then queueNotification('Home', 'History and saved games are session-only: filesystem access is unavailable.', 4370336704) end end
   return false
  end
  local ok,err=pcall(function()
   checkFolder()
   writefile(storePath,httpService:JSONEncode({version=1,history=data.history,saved=data.saved}))
  end)
  if not ok then if alive then queueNotification('Home', 'Could not save history: '..tostring(err), 4370336704) end end
  return ok
 end
 local function validGame(v)
  return type(v)=='table' and tonumber(v.placeId) and tonumber(v.placeId)>0 and tonumber(v.universeId) and tonumber(v.universeId)>=0
 end
 if readfile and isfile then
  local ok,decoded=pcall(function() if isfile(storePath) then return httpService:JSONDecode(readfile(storePath)) end end)
  if ok and type(decoded)=='table' then
   local seen={}
   for _,v in ipairs(type(decoded.history)=='table' and decoded.history or {}) do
    if validGame(v) and not seen[tostring(v.universeId>0 and v.universeId or v.placeId)] and #data.history<100 then
     seen[tostring(v.universeId>0 and v.universeId or v.placeId)]=true
     table.insert(data.history,{placeId=tonumber(v.placeId),universeId=tonumber(v.universeId),name=tostring(v.name or 'Experience'),creator=tostring(v.creator or ''),lastPlayed=tonumber(v.lastPlayed) or 0})
    end
   end
   for k,v in pairs(type(decoded.saved)=='table' and decoded.saved or {}) do if validGame(v) then data.saved[tostring(k)]=v end end
  elseif not ok then
   if writefile then pcall(function() writefile(storePath..'.corrupt-'..os.time(),readfile(storePath)) end) end
   if alive then queueNotification('Home', 'History file could not be read. A fresh history will be started.', 4370336704) end
  end
 end
 local function clear(list)
  list.Template.Visible=false
  for _,v in ipairs(list:GetChildren()) do if v:IsA('GuiObject') and v.Name~='Template' and (v:GetAttribute('RuntimeEntry') or v:GetAttribute('IsPreview') or v.Name:match('^Preview')) then v:Destroy() end end
 end
 local function row(list,id,order)
  local v=list.Template:Clone() v.Name='Entry_'..tostring(id) v.Visible=true v.LayoutOrder=order
  v:SetAttribute('RuntimeEntry',true) v:SetAttribute('IsTemplate',false) v:SetAttribute('IsPreview',nil)
  v.Parent=list return v
 end

 local function friendRowControls(v)
  if not v or not v:IsA('GuiObject') then return end

  local interact=v:FindFirstChild('Interact')
  if interact and interact:IsA('GuiButton') then
   interact.AnchorPoint=Vector2.zero
   interact.Position=UDim2.fromScale(0,0)
   interact.Size=UDim2.fromScale(1,1)
   interact.BackgroundTransparency=1
   interact.ZIndex=math.max(v.ZIndex,1)
  end

  local more=v:FindFirstChild('More')
  if more and more:IsA('GuiObject') then
   more.AnchorPoint=Vector2.new(1,.5)
   more.Position=UDim2.new(1,-14,.5,0)
   more.ZIndex=math.max((interact and interact.ZIndex or v.ZIndex)+2,more.ZIndex)
  end

  local join=v:FindFirstChild('Join')
  if join and join:IsA('GuiObject') then
   join.AnchorPoint=Vector2.new(1,.5)
   local moreWidth=(more and more.AbsoluteSize.X>0 and more.AbsoluteSize.X)
    or (more and more.Size.X.Offset>0 and more.Size.X.Offset)
    or 30
   join.Position=UDim2.new(1,-(14+moreWidth+8),.5,0)
   join.ZIndex=math.max((interact and interact.ZIndex or v.ZIndex)+2,join.ZIndex)
  end
 end
 local function state(browser, mode, message)
  browser.States.Visible=mode~=nil
  for _,v in ipairs(browser.States:GetChildren()) do if v:IsA('GuiObject') then
   v.Visible=v.Name==mode or (v.Name=='Retry' and mode=='Error')
   if v.Name==mode and message and v:IsA('TextLabel') then v.Text=message end
  end end
  browser.List.Visible=mode==nil
 end
 local function matches(value,query) return tostring(value or ''):lower():find(query:lower(),1,true)~=nil end
 local function profileURL(id) return 'https://www.roblox.com/users/'..tostring(id)..'/profile' end
 local function copy(value) if originalSetClipboard then originalSetClipboard(value) if alive then queueNotification('Home', 'Copied to clipboard.', 4370336704) end else if alive then queueNotification('Home', 'Clipboard is unavailable.', 4370336704) end end end
 local menu=Instance.new('Frame') menu.Name='HomeActionMenu' menu.Visible=false menu.Size=UDim2.fromOffset(280,146) menu.AnchorPoint=Vector2.new(.5,.5) menu.Position=UDim2.fromScale(.5,.5) menu.BackgroundColor3=Color3.fromRGB(27,27,30) menu.BorderSizePixel=0 menu.ZIndex=90 menu.Parent=homeContent
 Instance.new('UICorner',menu).CornerRadius=UDim.new(0,12)
 local menuButtons={}
 for i=1,3 do local b=Instance.new('TextButton') b.Name='Action'..i b.Position=UDim2.new(0,10,0,10+(i-1)*43) b.Size=UDim2.new(1,-20,0,37) b.BackgroundColor3=Color3.fromRGB(49,49,54) b.TextColor3=Color3.new(1,1,1) b.TextSize=15 b.Font=Enum.Font.Gotham b.ZIndex=91 b.Parent=menu Instance.new('UICorner',b).CornerRadius=UDim.new(0,8) menuButtons[i]=b end
 local menuActions={}
 for i,b in ipairs(menuButtons) do action(b,function() menu.Visible=false if menuActions[i] then menuActions[i]() end end) end
 local function moreFriend(f)
  if not f then return end
  menuButtons[1].Text='Copy profile link' menuButtons[2].Text='Copy username' menuButtons[3].Text='Close'
  menuActions={function() copy(profileURL(f.id)) end,function() copy(f.username) end,function() end} menu.Visible=true
 end
 local function inspect(id)
  task.spawn(function()
   local ok=pcall(function() guiService:InspectPlayerFromUserId(id) end)
   if not ok then copy(profileURL(id)) end
  end)
 end
 local function playGame(item,job)
  if not item or not tonumber(item.placeId) or item.placeId<=0 then if alive then queueNotification('Home', 'This experience is unavailable to join.', 4370336704) end return end
  if not job and (tonumber(item.placeId)==game.PlaceId or (tonumber(item.universeId) and item.universeId>0 and item.universeId==game.GameId)) then
   if not originalSetClipboard then queueNotification('Unable to copy join script','Clipboard support is unavailable.',4335479658) return end
   local joinScript=string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, %q)',game.PlaceId,game.JobId)
   local ok=pcall(originalSetClipboard,joinScript)
   queueNotification(ok and 'Copied Join Script' or 'Unable to copy join script',ok and 'Copied a join script for your current server.' or 'The clipboard operation failed.',ok and 4335479121 or 4335479658)
   return
  end
  recordActivity('Joining experience',item.name or 'Experience')
  task.spawn(function()
   local ok,err=pcall(function()
    if job and job~='' then teleportService:TeleportToPlaceInstance(item.placeId,job,localPlayer)
    else teleportService:Teleport(item.placeId,localPlayer) end
   end)
   if not ok then if alive then queueNotification('Home', 'Could not join: '..tostring(err), 4370336704) end end
  end)
 end
 local friendActivity={roster=nil,rosterAt=0,version=0,placeCache={},refreshError=nil}
 function friendActivity.showPlaying(count)
  local section=home.NowPlaying.FriendsPlaying
  section.Visible=count>0
  local divider,nearest=nil,-math.huge
  local height=home.NowPlaying.AbsoluteSize.Y
  local top=section.Position.Y.Scale*height+section.Position.Y.Offset
  for _,child in ipairs(home.NowPlaying:GetChildren()) do
   if child:IsA('GuiObject') and child.Name=='Divider' then
    local y=child.Position.Y.Scale*height+child.Position.Y.Offset
    if y<=top and y>nearest then divider,nearest=child,y end
   end
  end
  if divider then divider.Visible=count>0 end
 end
 function friendActivity.positive(value)
  local number=tonumber(value) return number and number>0 and number or 0
 end
 function friendActivity.string(value)
  return type(value)=='string' and value:match('%S') and value or ''
 end
 function friendActivity.normalize(friend,online,presence,inServer,onlineKnown)
  local positive,nonempty=friendActivity.positive,friendActivity.string
  local nativePlace=positive(online and online.PlaceId)
  local nativeType=tonumber(online and online.LocationType)
  local inStudio=online and (nativeType==3 or nativeType==6)
  local nativePlaying=nativeType==1 or nativeType==4 or (nativeType==nil and nativePlace>0)
  local webPlace=positive(presence and presence.placeId)
  local status=presence and tonumber(presence.userPresenceType)
  local f={id=tonumber(friend.Id),username=friend.Username or friend.Name or tostring(friend.Id),displayName=friend.DisplayName or friend.Username or tostring(friend.Id),checkedAt=os.clock()}

  f.placeId=nativePlace>0 and nativePlace or webPlace
  f.universeId=positive(online and online.UniverseId)
  if f.universeId==0 and (nativePlace==0 or webPlace==0 or webPlace==nativePlace) then
   f.universeId=positive(presence and presence.universeId)
  end

  f.jobId=nonempty(online and online.GameId)
  if tonumber(f.jobId) then f.jobId='' end
  if f.jobId=='' and (nativePlace==0 or nativePlace==webPlace) then
   f.jobId=nonempty(presence and presence.gameId)
  end
  if tonumber(f.jobId) then f.jobId='' end

  f.location=nonempty(online and online.LastLocation)
  if f.location=='' and (nativePlace==0 or nativePlace==webPlace) then
   f.location=nonempty(presence and presence.lastLocation)
  end

  if inServer then
   f.presence='InGame'
   f.placeId=game.PlaceId
   f.universeId=game.GameId
   f.jobId=game.JobId
   f.location=placeName or 'This experience'
   f.source='Current server'
  elseif online then
   if online.IsOnline==false then
    f.presence='Offline'
   elseif inStudio then
    f.presence='Online'
    f.location='In Studio'
   elseif nativePlaying or nativePlace>0 then
    f.presence='InGame'
   else
    f.presence='Online'
   end
   f.source='Roblox client'
  elseif presence then
   f.presence=status==2 and 'InGame' or (status==1 or status==3) and 'Online' or status==0 and 'Offline' or 'Unknown'
   f.source='Roblox presence fallback'
  elseif onlineKnown then
   f.presence='Offline'
   f.source='Roblox client'
  else
   f.presence='Unknown'
   f.source='Unavailable'
  end

  if f.presence~='InGame' then
   f.placeId=0
   f.universeId=0
   f.jobId=''
  end

  if f.location=='' then
   if f.presence=='InGame' then
    f.location=(f.placeId>0 or f.universeId>0) and 'Playing' or 'Playing · activity private'
   elseif f.presence=='Online' then
    f.location='Online'
   elseif f.presence=='Offline' then
    f.location='Offline'
   else
    f.location='Activity unavailable'
   end
  end

  f.joinable=f.presence=='InGame' and f.placeId>0 and f.jobId~=''
  f.canAttemptJoin=f.presence=='InGame'
  return f
 end
 function friendActivity.online()
  local result,err=bounded(function() return localPlayer:GetFriendsOnlineAsync(200) end,8)
  if type(result)~='table' then
   result,err=bounded(function() return localPlayer:GetFriendsOnline(200) end,8)
  end
  if type(result)~='table' then return nil,err or 'Invalid online-friends response' end
  local indexed={}
  for _,value in pairs(result) do if type(value)=='table' then
   local id=tonumber(value.VisitorId or value.UserId or value.Id)
   if id then indexed[id]=value end
  end end
  return indexed
 end
 function friendActivity.resolvePlaceInstance(userId)
  local done,result=false,nil
  local worker=task.spawn(function()
   result=table.pack(pcall(function()
    return teleportService:GetPlayerPlaceInstanceAsync(userId)
   end))
   done=true
  end)
  local deadline=os.clock()+7
  repeat task.wait(.03) until done or not alive or os.clock()>=deadline
  if not alive or not done then
   pcall(task.cancel,worker)
   return nil,nil,alive and 'Server lookup timed out' or 'Closed'
  end
  if not result[1] then return nil,nil,tostring(result[2]) end

  local placeId=tonumber(result[4]) or tonumber(result[3])
  local jobId=friendActivity.string(result[5])
  if jobId=='' and type(result[4])=='string' and result[4]:find('%-') then jobId=result[4] end
  if not placeId or placeId<=0 or jobId=='' then return nil,nil,'Roblox did not return a joinable server' end
  return placeId,jobId,nil
 end
 function friendActivity.joinButton(button,f)
  button.Visible=f.presence=='InGame'
  label(button,'Join')
  button.AutoButtonColor=f.presence=='InGame'
  button.Active=f.presence=='InGame'
 end
 function friendActivity.updateDetails(f)
  if not selectedFriend or selectedFriend.id~=f.id then return end
  local d=fp.Details
  text(d.Activity,'Status',f.presence=='InGame' and 'In Game' or f.presence)
  text(d.Activity,'GameName',f.location)
  d.Activity.GameIcon.Image=gameIcon(f.universeId)
  d.Activity.GameIcon.Visible=f.presence=='InGame' and f.universeId>0
  friendActivity.joinButton(d.Activity.Join,f)
  text(d,'Availability',f.presence=='InGame' and (f.joinable and 'Join this server' or 'Server will be resolved when you join') or f.presence=='Unknown' and 'Activity unavailable' or f.presence)
 end
 function friendActivity.updateRow(f)
  local lists={fp.Browser.List,home.Friends.List,home.NowPlaying.FriendsPlaying.List}
  if fp:FindFirstChild('InThisSession') then table.insert(lists,fp.InThisSession.List) end
  for _,list in ipairs(lists) do
   local v=list:FindFirstChild('Entry_'..f.id)
   if v then
    text(v,'Location',f.location)
    if v:FindFirstChild('GameIcon') then v.GameIcon.Image=gameIcon(f.universeId) v.GameIcon.Visible=f.presence=='InGame' and f.universeId>0 end
    v:SetAttribute('PlaceId',f.placeId) v:SetAttribute('UniverseId',f.universeId) v:SetAttribute('JobId',f.jobId)
    v:SetAttribute('ActivitySource',f.source)
    if v:FindFirstChild('Join') then friendActivity.joinButton(v.Join,f) end
    friendRowControls(v)
   end
  end
  local list=home.NowPlaying.FriendsPlaying.List
  if f.presence=='InGame' and ((f.universeId>0 and f.universeId==game.GameId) or (f.placeId>0 and f.placeId==game.PlaceId)) and not list:FindFirstChild('Entry_'..f.id) then
   local count=0 for _,entry in ipairs(list:GetChildren()) do if entry:GetAttribute('RuntimeEntry') then count+=1 end end
   local entry=row(list,f.id,count+1) entry.Avatar.Image=head(f.id)
   entry:SetAttribute('UserId',f.id) entry:SetAttribute('PlaceId',f.placeId) entry:SetAttribute('UniverseId',f.universeId) entry:SetAttribute('JobId',f.jobId)
   action(entry.Interact,function() showPage('Friends') selectFriend(f,true) end)
   text(home.NowPlaying.FriendsPlaying,'Summary',(count+1)..' friends playing this experience')
   friendActivity.showPlaying(count+1)
  end
  friendActivity.updateDetails(f)
 end
 function friendActivity.enrich(snapshot,version)
  local grouped={} local queue={}
  for _,f in ipairs(snapshot) do if f.presence=='InGame' and (f.placeId>0 or f.universeId>0) then
   local key=f.placeId>0 and f.placeId or ('universe:'..f.universeId)
   if not grouped[key] then grouped[key]={} table.insert(queue,key) end
   table.insert(grouped[key],f)
  end end
  local nextIndex=0
  for _=1,math.min(4,#queue) do task.spawn(function()
   while alive and friendActivity.version==version and friends==snapshot do
    nextIndex+=1 local key=queue[nextIndex] if not key then return end
    local placeId=grouped[key][1].placeId
    local cached=friendActivity.placeCache[key]
    if not cached or os.clock()-cached.time>300 then
     cached={time=os.clock(),universeId=grouped[key][1].universeId}
     if cached.universeId==0 then
      local universe=getJSON('https://apis.roblox.com/universes/v1/places/'..placeId..'/universe')
      cached.universeId=friendActivity.positive(universe and universe.universeId)
     end
     if cached.universeId>0 then
      local response=getJSON('https://games.roblox.com/v1/games?universeIds='..cached.universeId)
      local info=response and response.data and response.data[1]
      cached.name=info and friendActivity.string(info.name) or ''
     end
     if placeId>0 and (not cached.name or cached.name=='') then
      local info=bounded(function() return marketplaceService:GetProductInfo(placeId) end,8)
      cached.name=type(info)=='table' and friendActivity.string(info.Name) or ''
     end
     if cached.name~='' or cached.universeId>0 then friendActivity.placeCache[key]=cached end
    end
    if not alive or friendActivity.version~=version or friends~=snapshot then return end
    for _,f in ipairs(grouped[key]) do
     if cached.name and cached.name~='' then f.location=cached.name elseif f.location=='Loading game...' then f.location='Game name unavailable' end
     if cached.universeId>0 then f.universeId=cached.universeId end
     friendActivity.updateRow(f)
    end
   end
  end) end
 end
 refreshFriends=function(force)
  if not alive or friendBusy or (not force and os.clock()-lastFriends<35) then return end
  friendBusy=true
  lastFriends=os.clock()
  friendActivity.version+=1
  local version=friendActivity.version

  if #friends==0 then state(fp.Browser,'Loading','Loading friends...') end

  task.spawn(function()
   local roster=friendActivity.roster
   local rosterError

   if not roster or os.clock()-friendActivity.rosterAt>300 then
    roster,rosterError=bounded(function()
     local result={}
     local seen={}
     local page=players:GetFriendsAsync(localPlayer.UserId)
     for _=1,100 do
      for _,f in ipairs(page:GetCurrentPage()) do
       local id=tonumber(f.Id)
       if id and not seen[id] then
        seen[id]=true
        table.insert(result,f)
       end
      end
      if page.IsFinished then return result end
      page:AdvanceToNextPageAsync()
     end
     error('Too many friend pages')
    end,25)

    if type(roster)~='table' then
     local result=getJSON('https://friends.roblox.com/v1/users/'..localPlayer.UserId..'/friends')
     if result and type(result.data)=='table' then
      roster={}
      for _,f in ipairs(result.data) do
       table.insert(roster,{Id=f.id,Username=f.name,DisplayName=f.displayName})
      end
     end
    end

    if type(roster)=='table' then
     friendActivity.roster=roster
     friendActivity.rosterAt=os.clock()
    end
   end

   if not alive or friendActivity.version~=version then return end
   if type(roster)~='table' then
    friendBusy=false
    friendError=rosterError or 'Friends unavailable'
    renderFriends()
    return
   end

   local inServer={}
   for _,p in ipairs(players:GetPlayers()) do inServer[p.UserId]=true end

   local function publish(online,presence,onlineKnown)
    if not alive or friendActivity.version~=version then return end
    local snapshot={}
    for _,f in ipairs(roster) do
     local id=tonumber(f.Id)
     if id then
      table.insert(snapshot,friendActivity.normalize(
       f,
       online and online[id],
       presence and presence[id],
       inServer[id],
       onlineKnown
      ))
     end
    end

    local rank={InGame=1,Online=2,Offline=3,Unknown=4}
    table.sort(snapshot,function(a,b)
     if rank[a.presence]~=rank[b.presence] then return rank[a.presence]<rank[b.presence] end
     return a.displayName:lower()<b.displayName:lower()
    end)

    friends=snapshot
    renderFriends()
    if selectedFriend then friendActivity.updateDetails(selectedFriend) end
    return snapshot
   end

   if #friends==0 then publish(nil,nil,false) end

   local online,onlineError=friendActivity.online()
   if not alive or friendActivity.version~=version then return end

   local presence=nil
   local webError=nil

   if not online then
    presence={}
    if originalRequest then
     for startIndex=1,#roster,100 do
      if not alive or friendActivity.version~=version then break end
      local ids={}
      for index=startIndex,math.min(startIndex+99,#roster) do
       table.insert(ids,tonumber(roster[index].Id))
      end
      local result,err=bounded(function()
       local response=originalRequest({
        Url='https://presence.roblox.com/v1/presence/users',
        Method='POST',
        Headers={['Content-Type']='application/json',Accept='application/json'},
        Body=httpService:JSONEncode({userIds=ids})
       })
       assert(type(response)=='table' and tonumber(response.StatusCode)==200,'Presence HTTP '..tostring(response and response.StatusCode))
       local decoded=httpService:JSONDecode(response.Body)
       assert(type(decoded.userPresences)=='table','Invalid presence response')
       return decoded
      end,8)
      if result then
       for _,p in ipairs(result.userPresences) do
        if tonumber(p.userId) then presence[tonumber(p.userId)]=p end
       end
      else
       webError=err
       break
      end
     end
    else
     webError='HTTP request unavailable'
    end
   end

   if not alive or friendActivity.version~=version then return end

   friendBusy=false
   friendError=nil
   friendActivity.refreshError=(not online and next(presence)==nil) and (onlineError or webError or 'Activity unavailable') or nil
   homeContainer:SetAttribute('FriendActivityClientStatus',online and 'OK' or tostring(onlineError))
   homeContainer:SetAttribute('FriendActivityHttpStatus',online and 'Not needed' or (webError or 'Fallback OK'))

   local snapshot=publish(online,presence,online~=nil)
   if snapshot then friendActivity.enrich(snapshot,version) end

   if friendActivity.refreshError then
    text(fp.Browser,'Subtitle','Friend activity is unavailable; retry shortly')
   else
    text(fp.Browser,'Subtitle','People you play with')
   end
  end)
 end
 local joiningFriends={}
 local function joinFriend(f)
  if not f or joiningFriends[f.id] then return end
  joiningFriends[f.id]=true

  task.spawn(function()
   if players:GetPlayerByUserId(f.id) then
    joiningFriends[f.id]=nil
    queueNotification('Home','This friend is already in your server.',4370336704)
    return
   end

   local target=f
   local online=friendActivity.online()

   if not alive then
    joiningFriends[f.id]=nil
    return
   end

   if online and online[f.id] then
    target=friendActivity.normalize(
     {Id=f.id,Username=f.username,DisplayName=f.displayName},
     online[f.id],
     nil,
     false,
     true
    )
    for key,value in pairs(target) do f[key]=value end
    friendActivity.updateRow(f)
   end

   if target.joinable then
    joiningFriends[f.id]=nil
    playGame(target,target.jobId)
    return
   end

   local placeId,jobId,resolveError=friendActivity.resolvePlaceInstance(f.id)
   joiningFriends[f.id]=nil

   if placeId and jobId then
    f.presence='InGame'
    f.placeId=placeId
    f.jobId=jobId
    f.joinable=true
    f.canAttemptJoin=true
    f.source='Roblox server lookup'
    if f.location=='' or f.location=='Playing · activity private' then f.location='Playing' end
    friendActivity.updateRow(f)
    playGame(f,jobId)
    return
   end

   if f.presence=='InGame' or (online and online[f.id]) then
    local followUrl='https://www.roblox.com/games/start?userId='..tostring(f.id)
    if originalSetClipboard then
     local copied=pcall(originalSetClipboard,followUrl)
     queueNotification(
      'Join Friend',
      copied and 'Roblox is hiding the exact server. Copied the official follow link to your clipboard.'
       or 'Roblox is hiding the exact server and the follow link could not be copied.',
      copied and 4335479121 or 4370336704
     )
    else
     queueNotification('Join Friend','Roblox is hiding the exact server for this friend. Their join/privacy settings may prevent direct following.',4370336704)
    end
   else
    queueNotification('Join Friend','This friend is not currently in a joinable experience.'..(resolveError and (' '..tostring(resolveError)) or ''),4370336704)
   end
  end)
 end
 local function gameKey(item) return tostring(item.universeId>0 and item.universeId or item.placeId) end
 local function saved(item) return item and data.saved[gameKey(item)]~=nil end
 local function toggleSave(item)
  if not item then return end
  local key=gameKey(item)
  data.saved[key]=not saved(item) and {placeId=item.placeId,universeId=item.universeId,name=item.name,creator=item.creator,lastPlayed=item.lastPlayed} or nil
  save() renderGames() if selectedGame then selectGame(selectedGame) end
  recordActivity(saved(item) and 'Saved game' or 'Removed saved game',item.name)
 end
 local function gameDetails(item)
  local id=tonumber(item.universeId) or 0
  if id>0 and metadata[id] then return metadata[id] end
  local result=id>0 and getJSON('https://games.roblox.com/v1/games?universeIds='..id) or nil
  local info=result and result.data and result.data[1]
  local detail=table.clone(item)
  if info then detail.name=info.name detail.creator=info.creator and info.creator.name or '' detail.description=info.description or '' detail.placeId=info.rootPlaceId or item.placeId end
  if id>0 then
   local thumbnails=getJSON('https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds='..id..'&countPerUniverse=1&defaults=true&size=768x432&format=Png&isCircular=false')
   local thumb=thumbnails and thumbnails.data and thumbnails.data[1] and thumbnails.data[1].thumbnails and thumbnails.data[1].thumbnails[1]
   if thumb and thumb.targetId then detail.artwork='rbxassetid://'..tostring(thumb.targetId) end
  end
  if info then metadata[id]=detail end
  return detail
 end
 local function selectDetails(panel,list,id)
  panel:SetAttribute('RestPosition',panel:GetAttribute('RestPosition') or panel.Position)
  local position=panel:GetAttribute('RestPosition')
  panel.Position=position-UDim2.fromOffset(28,0)
  tweenService:Create(panel,TweenInfo.new(.6,Enum.EasingStyle.Quint),{Position=position}):Play()
  for _,row in ipairs(list:GetChildren()) do if row:GetAttribute('RuntimeEntry') then
   local selected=row.Name=='Entry_'..tostring(id)
   local scale=row:FindFirstChild('SelectionScale') or Instance.new('UIScale',row) scale.Name='SelectionScale'
   tweenService:Create(scale,TweenInfo.new(.45,Enum.EasingStyle.Quint),{Scale=selected and 1.02 or 1}):Play()
   if row:FindFirstChild('UIStroke') then tweenService:Create(row.UIStroke,TweenInfo.new(.35),{Transparency=selected and .25 or .86}):Play() end
  end end
 end
 selectGame=function(item,animate)
  local changed=selectedGame~=item
  selectedGame=item if not item then gp.Details.Visible=false return end
  local d=gp.Details d.Visible=true if homeOpen and (changed or animate) then selectDetails(d,gp.Browser.List,gameKey(item)) end d:SetAttribute('SelectedUniverseId',item.universeId) d:SetAttribute('SelectedPlaceId',item.placeId)
  text(d,'Title',item.name) text(d,'Creator',item.creator) text(d,'Description','Loading experience details...') d.Artwork.Image=gameIcon(item.universeId)
  label(d.Favorite,saved(item) and 'Unsave' or 'Save')
  task.spawn(function()
   local detail=gameDetails(item)
   if not alive or selectedGame~=item then return end
   text(d,'Title',detail.name) text(d,'Creator',detail.creator) text(d,'Description',detail.description or 'Description unavailable.') d.Artwork.Image=detail.artwork or gameIcon(detail.universeId)
  end)
 end
 selectFriend=function(f,animate)
  local changed=not selectedFriend or not f or selectedFriend.id~=f.id
  selectedFriend=f if not f then fp.Details.Visible=false return end
  local d=fp.Details d.Visible=true if homeOpen and (changed or animate) then selectDetails(d,fp.Browser.List,f.id) end d:SetAttribute('SelectedUserId',f.id)
  d.Avatar.Image=head(f.id) text(d,'DisplayName',f.displayName) text(d,'Username','@'..f.username)
  text(d.Activity,'Status',f.presence) text(d.Activity,'GameName',f.location or 'Location unavailable') d.Activity.GameIcon.Image=gameIcon(f.universeId)
  friendActivity.updateDetails(f)
  text(d,'About','Loading profile...')
  task.spawn(function()
   local info=getJSON('https://users.roblox.com/v1/users/'..f.id)
   if alive and selectedFriend and selectedFriend.id==f.id then text(d,'About',info and (info.description~='' and info.description or 'No bio provided.') or 'Profile description unavailable.') end
  end)
 end
 local tabVersion=0
 local PAGE_REST_X=-12
 local PAGE_REST_Y=-12
 local PAGE_TRAVEL=28
 local PAGE_REST=UDim2.fromOffset(PAGE_REST_X,PAGE_REST_Y)
 local TAB_ORDER={Home=1,Friends=2,Games=3}
 local profile=homeContent.Sidebar:FindFirstChild('Profile')
 local PROFILE_REST=profile and profile.Position
 local PROFILE_TRAVEL=28

 local function pageOffset(direction)
  return UDim2.fromOffset(PAGE_REST_X+(PAGE_TRAVEL*direction),PAGE_REST_Y)
 end

 local function pageFadeState(page,visible,duration,direction)
  local props=altairValues.transparencyProperties
  local objects={page}
  for _,object in ipairs(page:GetDescendants()) do table.insert(objects,object) end
  for _,object in ipairs(objects) do
   local list=props[object.ClassName]
   if list then
    local goal={}
    local hasGoal=false
    for _,property in ipairs(list) do
     local attr='AltairHomePageFade_'..property
     local saved=object:GetAttribute(attr)
     if saved==nil then
      local homeSaved=object:GetAttribute('AltairHomeFade_'..property)
      saved=homeSaved~=nil and homeSaved or object[property]
      object:SetAttribute(attr,saved)
     end
     goal[property]=visible and saved or 1
     hasGoal=true
    end
    if hasGoal then
     tweenService:Create(object,TweenInfo.new(duration,Enum.EasingStyle.Quint,direction),goal):Play()
    end
   end
  end
 end

 local function primePageHidden(page)
  local props=altairValues.transparencyProperties
  local objects={page}
  for _,object in ipairs(page:GetDescendants()) do table.insert(objects,object) end
  for _,object in ipairs(objects) do
   local list=props[object.ClassName]
   if list then
    for _,property in ipairs(list) do
     local attr='AltairHomePageFade_'..property
     if object:GetAttribute(attr)==nil then
      local homeSaved=object:GetAttribute('AltairHomeFade_'..property)
      object:SetAttribute(attr,homeSaved~=nil and homeSaved or object[property])
     end
     object[property]=1
    end
   end
  end
 end

 local function profileOffset(direction)
  if not PROFILE_REST then return nil end
  return UDim2.new(
   PROFILE_REST.X.Scale,
   PROFILE_REST.X.Offset+(PROFILE_TRAVEL*direction),
   PROFILE_REST.Y.Scale,
   PROFILE_REST.Y.Offset
  )
 end

 local function profileFadeState(visible,duration,easingDirection)
  if not profile then return end
  local props=altairValues.transparencyProperties
  local objects={profile}
  for _,object in ipairs(profile:GetDescendants()) do table.insert(objects,object) end

  for _,object in ipairs(objects) do
   local list=props[object.ClassName]
   if list then
    local goal={}
    local hasGoal=false
    for _,property in ipairs(list) do
     local attr='AltairProfileFade_'..property
     local saved=object:GetAttribute(attr)
     if saved==nil then
      local homeSaved=object:GetAttribute('AltairHomeFade_'..property)
      saved=homeSaved~=nil and homeSaved or object[property]
      object:SetAttribute(attr,saved)
     end
     goal[property]=visible and saved or 1
     hasGoal=true
    end
    if hasGoal then
     tweenService:Create(
      object,
      TweenInfo.new(duration,Enum.EasingStyle.Quint,easingDirection),
      goal
     ):Play()
    end
   end
  end
 end

 local function primeProfileHidden()
  if not profile then return end
  local props=altairValues.transparencyProperties
  local objects={profile}
  for _,object in ipairs(profile:GetDescendants()) do table.insert(objects,object) end

  for _,object in ipairs(objects) do
   local list=props[object.ClassName]
   if list then
    for _,property in ipairs(list) do
     local attr='AltairProfileFade_'..property
     if object:GetAttribute(attr)==nil then
      local homeSaved=object:GetAttribute('AltairHomeFade_'..property)
      object:SetAttribute(attr,homeSaved~=nil and homeSaved or object[property])
     end
     object[property]=1
    end
   end
  end
 end

 showPage=function(name)
  local targetPage=pages:FindFirstChild(name)
  if not targetPage then return end
  if activePage==name and opened and targetPage.Visible then return end

  local previousName=activePage
  local previousPage=nil
  for _,page in ipairs(pages:GetChildren()) do
   if page:IsA('GuiObject') and page.Visible and page~=targetPage then
    previousPage=page
    break
   end
  end

  local previousOrder=TAB_ORDER[previousName] or TAB_ORDER[name] or 1
  local targetOrder=TAB_ORDER[name] or previousOrder
  local direction=targetOrder>=previousOrder and 1 or -1
  local enterPosition=pageOffset(direction)
  local exitPosition=pageOffset(-direction)

  local enteringFriends=name=='Friends' and previousName~='Friends'
  local leavingFriends=previousName=='Friends' and name~='Friends'

  activePage=name tabVersion+=1 local version=tabVersion
  homeContainer:SetAttribute('ActivePage',name) menu.Visible=false

  for _,button in ipairs(homeContent.Sidebar:GetChildren()) do
   if button:IsA('GuiButton') and pages:FindFirstChild(button.Name) then
    local selected=button.Name==name
    local backgroundTransparency=selected and .15 or 1
    local textColor=selected and Color3.fromRGB(242,242,246) or Color3.fromRGB(164,164,174)
    local iconColor=selected and Color3.fromRGB(232,232,238) or Color3.fromRGB(154,154,164)
    local fontWeight=selected and Enum.FontWeight.SemiBold or Enum.FontWeight.Regular

    button.BackgroundColor3=Color3.fromRGB(62,62,68)
    button.BackgroundTransparency=backgroundTransparency
    button:SetAttribute('AltairHomeFade_BackgroundTransparency',backgroundTransparency)

    local navObjects={button}
    for _,object in ipairs(button:GetDescendants()) do
     table.insert(navObjects,object)
    end

    for _,object in ipairs(navObjects) do
     if object:IsA('TextLabel') or object:IsA('TextButton') or object:IsA('TextBox') then
      object.TextColor3=textColor
      object.FontFace=Font.new(object.FontFace.Family,fontWeight,object.FontFace.Style)
     elseif object:IsA('ImageLabel') or object:IsA('ImageButton') then
      object.ImageColor3=iconColor
     end
    end
   end
  end

  if profile then
   if enteringFriends then
    profile.Visible=true
    profileFadeState(false,.28,Enum.EasingDirection.In)
    tweenService:Create(
     profile,
     TweenInfo.new(.34,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),
     {Position=profileOffset(-direction)}
    ):Play()
    task.delay(.30,function()
     if alive and version==tabVersion and activePage=='Friends' then
      profile.Visible=false
     end
    end)
   elseif name=='Friends' then
    profile.Visible=false
   elseif not leavingFriends and PROFILE_REST then
    profile.Visible=true
    profile.Position=PROFILE_REST
   end
  end

  local function reveal()
   if not alive or version~=tabVersion then return end

   if profile and leavingFriends then
    profile.Visible=true
    primeProfileHidden()
    profile.Position=profileOffset(direction)
    profileFadeState(true,.52,Enum.EasingDirection.Out)
    tweenService:Create(
     profile,
     TweenInfo.new(.58,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),
     {Position=PROFILE_REST}
    ):Play()
   end

   for _,page in ipairs(pages:GetChildren()) do
    if page:IsA('GuiObject') then
     page.Visible=page==targetPage
    end
   end

   if opened then
    primePageHidden(targetPage)
    targetPage.Position=enterPosition
    targetPage.Visible=true
    pageFadeState(targetPage,true,.52,Enum.EasingDirection.Out)
    tweenService:Create(targetPage,TweenInfo.new(.58,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{
     Position=PAGE_REST
    }):Play()
   else
    targetPage.Position=PAGE_REST
   end
  end

  if opened and previousPage then
   pageFadeState(previousPage,false,.28,Enum.EasingDirection.In)
   tweenService:Create(previousPage,TweenInfo.new(.34,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{
    Position=exitPosition
   }):Play()
   task.delay(.30,reveal)
  else
   reveal()
  end

  if name=='Friends' then refreshFriends() elseif name=='Games' and gameFilter=='Favorites' then refreshFavorites() end
 end
 renderFriends=function()
  local browser=fp.Browser local query=browser.SearchBox.Text
  clear(browser.List) clear(home.Friends.List) clear(home.NowPlaying.FriendsPlaying.List)
  if fp:FindFirstChild('InThisSession') then clear(fp.InThisSession.List) end
  local counts={All=#friends,InGame=0,Online=0,Offline=0} local shown,playing=0,0
  for i,f in ipairs(friends) do
   if f.presence=='InGame' then counts.InGame+=1 end
   if f.presence=='Online' or f.presence=='InGame' then counts.Online+=1 end
   if f.presence=='Offline' then counts.Offline+=1 end
   local function fill(v)
    v:SetAttribute('UserId',f.id) v:SetAttribute('PlaceId',f.placeId) v:SetAttribute('UniverseId',f.universeId) v:SetAttribute('JobId',f.jobId)
    friendRowControls(v)
    v.Avatar.Image=head(f.id) text(v,'DisplayName',f.displayName) text(v,'Username','@'..f.username) text(v,'Status',f.presence=='InGame' and 'In Game' or f.presence) text(v,'Location',f.location)
    local offline=f.presence=='Offline' or f.presence=='Unknown'
    v.Avatar.ImageTransparency=offline and .45 or 0
    for _,name in ipairs({'DisplayName','Username','Status','Location'}) do local field=v:FindFirstChild(name) if field then field.TextTransparency=offline and .4 or 0 end end
    if v:FindFirstChild('Status') then v.Status.TextColor3=offline and Color3.fromRGB(145,145,154) or Color3.fromRGB(86,216,145) end
    if v:FindFirstChild('StatusDot') then v.StatusDot.BackgroundColor3=(f.presence=='InGame' or f.presence=='Online') and Color3.fromRGB(77,227,133) or Color3.fromRGB(144,154,168) end
    action(v.Interact,function() showPage('Friends') selectFriend(f,true) end)
   end
   if i<=40 then fill(row(home.Friends.List,f.id,i)) end
   if (f.universeId>0 and f.universeId==game.GameId) or (f.placeId>0 and f.placeId==game.PlaceId) then playing+=1 fill(row(home.NowPlaying.FriendsPlaying.List,f.id,playing)) if fp:FindFirstChild('InThisSession') then fill(row(fp.InThisSession.List,f.id,playing)) end end
   local included=friendFilter=='All' or f.presence==friendFilter or (friendFilter=='Online' and f.presence=='InGame')
   if included and (matches(f.displayName,query) or matches(f.username,query)) then
    shown+=1 local v=row(browser.List,f.id,shown) fill(v)
    text(v,'Location',f.location) v.GameIcon.Image=gameIcon(f.universeId) v.GameIcon.Visible=f.presence=='InGame' and f.universeId>0
    friendActivity.joinButton(v.Join,f) v:SetAttribute('ActivitySource',f.source)
    friendRowControls(v)
    action(v.Join,function() joinFriend(f) end) action(v.More,function() selectFriend(f) moreFriend(f) end)
   end
  end
  for _,button in ipairs(browser.Filters:GetChildren()) do if button:IsA('GuiButton') then label(button,(button.Name=='InGame' and 'In Game' or button.Name)..' ('..tostring(counts[button.Name] or 0)..')') button.BackgroundTransparency=button.Name==friendFilter and .15 or .65 end end
  friendActivity.showPlaying(playing)
  text(home.Friends,'Title',#friends>0 and ('Friends ('..#friends..')') or 'Friends')
  text(home.NowPlaying.FriendsPlaying,'Summary',friendError and 'Friends unavailable · click to retry' or (playing..' friends playing this experience'))
  state(browser,friendBusy and #friends==0 and 'Loading' or friendError and #friends==0 and 'Error' or shown==0 and 'Empty' or nil,friendError or (query~='' and 'No matching friends.' or 'No friends in this filter.'))
  if selectedFriend then
   local replacement=nil for _,f in ipairs(friends) do if f.id==selectedFriend.id then replacement=f break end end
   if replacement then selectedFriend=replacement else selectFriend(nil) end
  end
 end
 renderGames=function()
  local browser=gp.Browser local query=browser.SearchBox.Text local items={}
  if gameFilter=='Recent' then for _,v in ipairs(data.history) do table.insert(items,v) end
  else
   local seen={}
   for _,v in ipairs(favorites) do seen[gameKey(v)]=true table.insert(items,v) end
   for _,v in pairs(data.saved) do if not seen[gameKey(v)] then table.insert(items,v) end end
   table.sort(items,function(a,b) return tostring(a.name)<tostring(b.name) end)
  end
  clear(browser.List) clear(home.RecentlyPlayed.List)
  if gp:FindFirstChild('ContinuePlaying') then clear(gp.ContinuePlaying.List) end
  local recentLists={home.RecentlyPlayed.List}
  if gp:FindFirstChild('ContinuePlaying') then table.insert(recentLists,gp.ContinuePlaying.List) end
  for _,list in ipairs(recentLists) do
  for i,item in ipairs(data.history) do if i>30 then break end local v=row(list,gameKey(item),i) v.Icon.Image=gameIcon(item.universeId) text(v,'Title',item.name) text(v,'LastPlayed',item.universeId==game.GameId and 'Playing now' or age(item.lastPlayed)) v:SetAttribute('PlaceId',item.placeId) v:SetAttribute('UniverseId',item.universeId) action(v.Interact,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') selectGame(item,true) end) end
  end
  local shown=0
  for _,item in ipairs(items) do if matches(item.name,query) or matches(item.creator,query) then
   shown+=1 local v=row(browser.List,gameKey(item),shown) v.Icon.Image=gameIcon(item.universeId) text(v,'Title',item.name) text(v,'Creator',item.creator~='' and ('By '..item.creator) or '') text(v,'LastPlayed',gameFilter=='Recent' and age(item.lastPlayed) or saved(item) and 'Saved in Altair' or 'Roblox favorite')
   v:SetAttribute('PlaceId',item.placeId) v:SetAttribute('UniverseId',item.universeId) v:SetAttribute('LastPlayedAt',item.lastPlayed or 0) v:SetAttribute('IsFavorite',saved(item))
   label(v.Favorite,saved(item) and '★' or '☆')
   action(v.Interact,function() selectGame(item,true) end) action(v.Play,function() playGame(item) end) action(v.Favorite,function() toggleSave(item) end)
  end end
  for _,v in ipairs(browser.Filters:GetChildren()) do if v:IsA('GuiButton') then v.BackgroundTransparency=v.Name==gameFilter and .15 or .65 end end
  label(browser.Filters.Favorites,'Favorites')
  text(browser,'Subtitle',gameFilter=='Recent' and 'Experiences visited while Altair is running' or (favoriteError and 'Roblox favorites unavailable · showing saved games' or 'Roblox favorites and games saved in Altair'))
  local mode=gameFilter=='Favorites' and favoriteBusy and #items==0 and 'Loading' or gameFilter=='Favorites' and favoriteError and #items==0 and 'Error' or shown==0 and 'Empty' or nil
  state(browser,mode,mode=='Error' and favoriteError or query~='' and 'No matching games.' or gameFilter=='Recent' and 'Your visits will appear here.' or 'No favorite or saved games yet.')
 end
 refreshFavorites=function(force)
  if favoriteBusy or (not force and os.clock()-lastFavorites<120) then return end
  favoriteBusy=true lastFavorites=os.clock() renderGames()
  task.spawn(function()
   local result, cursor, seen, err = {}, nil, {}, nil
   for _=1,100 do
    local response,e=getJSON('https://games.roblox.com/v2/users/'..localPlayer.UserId..'/favorite/games?accessFilter=2&limit=50&sortOrder=Desc'..(cursor and ('&cursor='..httpService:UrlEncode(cursor)) or ''))
    if not response then err=e break end
    for _,v in ipairs(response.data or {}) do
     local id=tonumber(v.id) local place=v.rootPlace and tonumber(v.rootPlace.id)
     if id and place and not seen[id] then seen[id]=true table.insert(result,{universeId=id,placeId=place,name=v.name or 'Experience',creator=v.creator and v.creator.name or '',lastPlayed=0}) end
    end
    local nextCursor=response.nextPageCursor if not nextCursor or nextCursor=='' then break end
    if nextCursor==cursor then err='Repeated Roblox page cursor' break end cursor=nextCursor
   end
   if not alive then return end
   if not err then favorites=result end favoriteError=err favoriteBusy=false renderGames()
  end)
 end
 local function refreshCurrentGame()
  local item={placeId=game.PlaceId,universeId=game.GameId,name=placeName or 'Current experience',creator='',lastPlayed=os.time()}
  local info=bounded(function() return marketplaceService:GetProductInfo(game.PlaceId) end)
  if info then item.name=info.Name or item.name item.creator=info.Creator and info.Creator.Name or '' end
  if not alive then return end
  local key=gameKey(item)
  for i=#data.history,1,-1 do if gameKey(data.history[i])==key then table.remove(data.history,i) end end
  if item.placeId>0 then table.insert(data.history,1,item) while #data.history>100 do table.remove(data.history) end save() end
  text(home.NowPlaying,'GameName',item.name) text(home.NowPlaying,'Creator',item.creator) home.NowPlaying.GameIcon.Image=gameIcon(item.universeId) home.NowPlaying.Artwork.Image=gameIcon(item.universeId)
  home.NowPlaying:SetAttribute('PlaceId',item.placeId) home.NowPlaying:SetAttribute('UniverseId',item.universeId)
  text(home.SessionStatus,'Game',item.name) renderGames()
  local detail=gameDetails(item) if alive then home.NowPlaying.Artwork.Image=detail.artwork or gameIcon(item.universeId) end
 end
 local activity=altairValues.activity.items
 recordActivity=function(title,description,icon)
  return altairValues.activity:record(title,description,icon)
 end
 local function renderActivity()
  if not home:FindFirstChild('RecentActivity') then return end
  local list=home.RecentActivity.List clear(list)
  for index,item in ipairs(activity) do local entry=row(list,index,index) text(entry,'Title',item.title) text(entry,'Description',item.description..' · '..age(item.time)) entry.Icon.Image=item.icon end
 end
 local lastActivityRender,activityRevision=0,-1
 local function tick()
  if not alive or not opened then return end
  local now=os.clock()
  local playerCount=#players:GetPlayers()
  local ping=math.floor(getPing())
  text(home.SessionStatus,'Time',os.date('%I:%M %p'):gsub('^0','')) text(home.SessionStatus,'Date',os.date('%a, %b %d, %Y')) text(home.SessionStatus,'Status','In Game ●')
  text(home.Server,'PlayerCount',playerCount..' / '..players.MaxPlayers)
  text(home.Server.Ping,'Value',ping..' ms')
  local seconds=math.floor(now-sessionStarted) text(home.Server.Uptime,'Label','Session time') text(home.Server.Uptime,'Value',math.floor(seconds/3600)..'h '..math.floor(seconds/60)%60 ..'m')
  text(home.Server.Region,'Value',data.serverRegion.value~='' and data.serverRegion.value or 'Searching...')
  text(home.NowPlaying,'SessionPills','● In Game     '..playerCount..' / '..players.MaxPlayers..' Players     '..ping..' ms')
  if activityRevision~=altairValues.activity.revision or now-lastActivityRender>=5 then lastActivityRender=now activityRevision=altairValues.activity.revision renderActivity() end
  refreshFriends()
 end
 local controller={}

 function controller.fadeOut(duration)
  duration=duration or .28
  local props=altairValues.transparencyProperties
  for _,obj in ipairs(homeContent:GetDescendants()) do
   local list=props[obj.ClassName]
   if list then
    local goal={}
    for _,property in ipairs(list) do
     local attr='AltairHomeFade_'..property
     if obj:GetAttribute(attr)==nil then obj:SetAttribute(attr,obj[property]) end
     goal[property]=1
    end
    tweenService:Create(obj,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goal):Play()
   end
  end
 end

 function controller.fadeIn(duration)
  duration=duration or .38
  local props=altairValues.transparencyProperties
  for _,obj in ipairs(homeContent:GetDescendants()) do
   local list=props[obj.ClassName]
   if list then
    local goal={}
    local hasGoal=false
    for _,property in ipairs(list) do
     local saved=obj:GetAttribute('AltairHomeFade_'..property)
     if saved~=nil then
      goal[property]=saved
      hasGoal=true
     end
    end
    if hasGoal then
     tweenService:Create(obj,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goal):Play()
    end
   end
  end
 end

 function controller.setOpened(value) opened=value end
 function controller.destroy()
  if not alive then return end
  if closeHome then closeHome(true) end alive=false
  homeBlur:Destroy()
  for _,c in ipairs(connections) do c:Disconnect() end table.clear(connections)
  if menu.Parent then menu:Destroy() end
 end
 controller.tick=tick
 controller.recordActivity=recordActivity
 controller.selectFriend=selectFriend
 controller.selectGame=selectGame
 controller.showPage=showPage
 controller.refreshFriends=refreshFriends
 controller.refreshFavorites=refreshFavorites
 controller.debugState=function() return {opened=opened,friends=friends,history=data.history,saved=data.saved,friendBusy=friendBusy,favoriteBusy=favoriteBusy,friendError=friendError,favoriteError=favoriteError} end
 for _,v in ipairs(homeContainer:GetDescendants()) do if v:IsA('ScrollingFrame') and v:FindFirstChild('Template') then clear(v) end end
 home.NowPlaying.Artwork.Image='' home.NowPlaying.GameIcon.Image='' text(home.NowPlaying,'GameName','Loading experience...') text(home.NowPlaying,'Creator','')
 homeContent.Sidebar.Profile.Avatar.Image=head(localPlayer.UserId) text(homeContent.Sidebar.Profile,'DisplayName',localPlayer.DisplayName) text(homeContent.Sidebar.Profile,'Status','● In Game')
 profile=homeContent.Sidebar.Profile
 if profile:IsA('GuiObject') then profile.ZIndex=50 end
 for _,object in ipairs(profile:GetDescendants()) do
  if object:IsA('GuiObject') then object.ZIndex=math.max(object.ZIndex,51) end
 end
 text(profile,'Membership',localPlayer.MembershipType==Enum.MembershipType.Premium and 'Premium' or 'Roblox account')
 text(profile,'Stats','FRIENDS          ACCOUNT AGE')
 text(profile,'StatValues','—                   '..tostring(localPlayer.AccountAge)..' days')
 task.spawn(function()
  local count=getJSON('https://friends.roblox.com/v1/users/'..localPlayer.UserId..'/friends/count')
  if alive then text(profile,'StatValues',tostring(count and count.count or '—')..'                   '..tostring(localPlayer.AccountAge)..' days') end
 end)
 if altairValues.activity.previousJob~=game.JobId then
  recordActivity(altairValues.activity.previousJob and 'Arrived after teleport' or 'Joined experience',placeName or 'Current session')
 end
 renderActivity()
 selectFriend(nil) selectGame(nil)
 for _,v in ipairs(homeContent.Sidebar:GetChildren()) do if v:IsA('GuiButton') and pages:FindFirstChild(v.Name) then action(v,function() showPage(v.Name) end) end end
 action(homeContent.Sidebar.Profile.Interact,function() inspect(localPlayer.UserId) end)
 action(home.Friends.ViewAll,function() showPage('Friends') end)
 if gp:FindFirstChild('ContinuePlaying') then action(gp.ContinuePlaying.ViewAll,function() gameFilter='Recent' renderGames() end) end
 action(home.RecentlyPlayed.ViewAll,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') end)
 action(home.NowPlaying.FriendsPlaying.ViewFriends,function() friendFilter='InGame' renderFriends() showPage('Friends') refreshFriends(true) end)
 local sessionLink=Instance.new('TextButton') sessionLink.Name='CopyServerLink' sessionLink.Text='' sessionLink.BackgroundTransparency=1 sessionLink.Size=UDim2.fromOffset(26,26) sessionLink.Position=UDim2.new(1,-40,0,10) sessionLink.Text='⋯' sessionLink.TextColor3=Color3.new(1,1,1) sessionLink.ZIndex=30 sessionLink.Parent=home.Server
 action(sessionLink,function() copy('https://www.roblox.com/games/start?placeId='..game.PlaceId..'&gameInstanceId='..httpService:UrlEncode(game.JobId)) end)
 local gameLink=Instance.new('TextButton') gameLink.Name='ViewGame' gameLink.Text='' gameLink.BackgroundTransparency=1 gameLink.Position=home.NowPlaying.GameIcon.Position gameLink.Size=home.NowPlaying.GameIcon.Size gameLink.ZIndex=30 gameLink.Parent=home.NowPlaying
 action(gameLink,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') for _,item in ipairs(data.history) do if item.placeId==game.PlaceId then selectGame(item) break end end end)
 for _,v in ipairs(fp.Browser.Filters:GetChildren()) do if v:IsA('GuiButton') then action(v,function() friendFilter=v.Name fp.Browser.List.CanvasPosition=Vector2.zero renderFriends() end) end end
 for _,v in ipairs(gp.Browser.Filters:GetChildren()) do if v:IsA('GuiButton') then action(v,function() gameFilter=v.Name gp.Browser.List.CanvasPosition=Vector2.zero renderGames() if gameFilter=='Favorites' then refreshFavorites() end end) end end
 local friendSearchVersion,gameSearchVersion=0,0
 connect(fp.Browser.SearchBox:GetPropertyChangedSignal('Text'),function()
  friendSearchVersion+=1 local version=friendSearchVersion
  task.delay(.12,function() if alive and version==friendSearchVersion then renderFriends() end end)
 end)
 connect(gp.Browser.SearchBox:GetPropertyChangedSignal('Text'),function()
  gameSearchVersion+=1 local version=gameSearchVersion
  task.delay(.12,function() if alive and version==gameSearchVersion then renderGames() end end)
 end)
 action(fp.Details.Activity.Join,function() joinFriend(selectedFriend) end)
 action(fp.Details.ViewProfile,function() if selectedFriend then inspect(selectedFriend.id) end end)
 action(fp.Details.More,function() moreFriend(selectedFriend) end)
 action(gp.Details.Play,function() playGame(selectedGame) end)
 action(gp.Details.Favorite,function() toggleSave(selectedGame) end)
 for _,pair in ipairs({{fp.Browser,function() refreshFriends(true) end},{gp.Browser,function() refreshFavorites(true) end}}) do
  local retry=Instance.new('TextButton') retry.Name='Retry' retry.Text='Retry' retry.Size=UDim2.fromOffset(100,32) retry.Position=UDim2.new(.5,-50,.7,0) retry.TextColor3=Color3.new(1,1,1) retry.BackgroundColor3=Color3.fromRGB(61,78,102) retry.Visible=false retry.Parent=pair[1].States
  connect(pair[1].States.Error:GetPropertyChangedSignal('Visible'),function() retry.Visible=pair[1].States.Error.Visible end) action(retry,pair[2])
 end
 connect(userInputService.InputBegan,function(key,processed) if opened and not processed and not userInputService:GetFocusedTextBox() and key.KeyCode==Enum.KeyCode.Escape then closeHome() end end)
 connect(teleportService.TeleportInitFailed,function(p,_,message) if p==localPlayer then if alive then queueNotification('Home', 'Teleport failed: '..tostring(message), 4370336704) end end end)
 pcall(function()
  connect(data.serverRegion.networkClient.ConnectionAccepted,function(peer)
   data.serverRegion.peer=tostring(peer or '')
   data.serverRegion.value=''
   data.serverRegion.refresh(true)
  end)
 end)
 data.serverRegion.refresh(true)
 connect(UI.Destroying,controller.destroy)
 do
  local props=altairValues.transparencyProperties
  for _,obj in ipairs(homeContent:GetDescendants()) do
   local list=props[obj.ClassName]
   if list then
    for _,property in ipairs(list) do
     local attr='AltairHomeFade_'..property
     if obj:GetAttribute(attr)==nil then obj:SetAttribute(attr,obj[property]) end
    end
   end
  end
  controller.fadeOut(0)
 end
 homeContainer.Visible=false showPage('Home') renderFriends() renderGames()
 task.spawn(refreshCurrentGame)
 controller.refreshCurrentGame=refreshCurrentGame
 return controller
end)()
local function UpdateHome() homeController.tick() end

openHome = function()
 if homeOpen or not UI.Parent then return end
 homeOpen=true homeFov=homeFov or camera.FieldOfView
 homeBlur.Parent=lighting
 for _,panel in ipairs(UI:GetChildren()) do
  if panel:IsA("GuiObject") and panel.Visible and smartBar.Back.Buttons:FindFirstChild(panel.Name) and isPanel(panel.Name) then
   task.spawn(closePanel,panel.Name,true)
  end
 end
 if settingsPanel.Visible then task.spawn(closeSettings) end
 if scriptSearch.Visible then task.spawn(closeScriptSearch) end
 pcall(function() homeChatEnabled=starterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) end)
 pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat,false) end)
 pcall(function() starterGui:SetCore("ChatActive",false) end)
 homeController.setOpened(true)
 if not homeContainer.Visible then homeContent.Position=UDim2.new(.5,-45,.5,0) end
 homeContainer.Visible=true
 homeController.fadeIn(.38)
 tweenService:Create(homeContent,TweenInfo.new(.8,Enum.EasingStyle.Quint),{Position=UDim2.fromScale(.5,.5)}):Play()
 tweenService:Create(homeContainer.Dim,TweenInfo.new(.5),{BackgroundTransparency=.5}):Play()
 tweenService:Create(homeBlur,TweenInfo.new(.8,Enum.EasingStyle.Quint),{Size=26}):Play()
 tweenService:Create(camera,TweenInfo.new(.8,Enum.EasingStyle.Quint),{FieldOfView=math.max(20,homeFov-35)}):Play()
 homeController.tick()
end

closeHome = function(immediate)
 if not homeOpen and not immediate then return end
 homeOpen=false homeController.setOpened(false)
 if homeChatEnabled~=nil then pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat,homeChatEnabled) end) homeChatEnabled=nil end
 homeController.fadeOut(immediate and 0 or .28)
 local slide=tweenService:Create(homeContent,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.new(.5,-45,.5,0)})
 tweenService:Create(homeContainer.Dim,TweenInfo.new(immediate and 0 or .3),{BackgroundTransparency=1}):Play()
 tweenService:Create(homeBlur,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint),{Size=0}):Play()
 tweenService:Create(camera,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint),{FieldOfView=homeFov or camera.FieldOfView}):Play()
 slide.Completed:Once(function(state)
  if state==Enum.PlaybackState.Completed and not homeOpen then homeContainer.Visible=false homeFov=nil
   if homeBlur.Parent then homeBlur.Parent=nil end
  end
 end)
 slide:Play()
end

-- Search owns its input layer and transition state. The interface now uses
-- sibling Z ordering, so decorative siblings must stay below the text field.
altairValues.scriptSearchState = { version = 0, phase = "closed" }

function altairValues.scriptSearchState:prepareInput()
	scriptSearch.ZIndex = math.max(scriptSearch.ZIndex, homeContainer.ZIndex + 1,
		settingsPanel.ZIndex + 1, scriptsPanel.ZIndex + 1,
		characterPanel.ZIndex + 1, playerlistPanel.ZIndex + 1)
	scriptSearch.Active = true
	scriptSearch.Interactable = true
	scriptSearch.Shadow.Active = false
	scriptSearch.Shadow.ZIndex = 0
	local top = 1
	for _, child in ipairs(scriptSearch:GetChildren()) do
		if child:IsA("GuiObject") and child ~= scriptSearch.SearchBox and child ~= scriptSearch.Icon then
			top = math.max(top, child.ZIndex + 1)
		end
	end
	scriptSearch.SearchBox.ZIndex = top
	scriptSearch.Icon.ZIndex = top
	scriptSearch.Icon.Active = false
	scriptSearch.SearchBox.Visible = true
	scriptSearch.SearchBox.Active = true
	scriptSearch.SearchBox.Interactable = true
	scriptSearch.SearchBox.TextEditable = true
	scriptSearch.SearchBox.ClearTextOnFocus = false
	scriptSearch.SearchBox.MultiLine = false
	scriptSearch.List.Active = true
	scriptSearch.List.Interactable = true
	-- A visible Modal button releases first-person mouse lock. Keep this tiny,
	-- transparent button behind the content so it cannot cover search/results.
	if not self.mouseUnlock then
		local button = Instance.new("TextButton")
		button.Name = "ScriptSearchMouseUnlock"
		button.Size = UDim2.fromOffset(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.Active = false
		button.Selectable = false
		button.ZIndex = 0
		button.Parent = scriptSearch
		self.mouseUnlock = button
	end
	self.mouseUnlock.Modal = true
end

local function openScriptSearch()
	local state = altairValues.scriptSearchState
	if state.phase == "open" or state.phase == "opening" then return end
	state.version += 1
	local version = state.version
	state.phase = "opening"
	state:prepareInput()
	scriptSearch.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	scriptSearch.UIGradient.Enabled = true
	if homeOpen then closeHome() end
	debounce = true

	scriptSearch.Size = UDim2.new(0, 480, 0, 23)
	scriptSearch.Position = UDim2.new(0.5, 0, 0.5, 0)
	scriptSearch.SearchBox.Position = UDim2.new(0.509, 0, 0.5, 0)
	scriptSearch.Icon.Position = UDim2.new(0.04, 0, 0.5, 0)
	scriptSearch.SearchBox.Text = ""
	scriptSearch.UIGradient.Offset = Vector2.new(0, 2)
	scriptSearch.SearchBox.PlaceholderText = "Search ScriptBlox.com"
	scriptSearch.List.Template.Visible = false
	scriptSearch.List.Visible = false
	scriptSearch.Visible = true

	wipeTransparency(scriptSearch, 1, true)

	tweenService:Create(scriptSearch, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(scriptSearch, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 580, 0, 43) }):Play()
	tweenService:Create(scriptSearch.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.85 }):Play()
	task.wait(0.03)
	if state.version ~= version then return end
	tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	task.wait(0.02)
	if state.version ~= version then return end
	tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

	task.wait(0.3)
	if state.version ~= version or not scriptSearch.Visible then return end
	state.phase = "open"
	scriptSearch.SearchBox:CaptureFocus()
	task.wait(0.2)
	if state.version ~= version then return end
	debounce = false
end

closeScriptSearch = function()
	local state = altairValues.scriptSearchState
	if state.phase == "closing" or state.phase == "closed" then return end
	state.version += 1
	local version = state.version
	state.phase = "closing"
	state.searching = nil
	if state.mouseUnlock then state.mouseUnlock.Modal = false end
	debounce = true

	wipeTransparency(scriptSearch, 1, false)

	task.wait(0.1)
	if state.version ~= version then return end

	scriptSearch.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scriptSearch.UIGradient.Enabled = false
	tweenService:Create(scriptSearch, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 520, 0, 0) }):Play()
	scriptSearch.SearchBox:ReleaseFocus()

	task.wait(0.5)
	if state.version ~= version then return end

	for _, createdScript in ipairs(scriptSearch.List:GetChildren()) do
		if createdScript.Name ~= "Placeholder" and createdScript.Name ~= "Template" and createdScript.ClassName == "Frame" then
			createdScript:Destroy()
		end
	end

	task.wait(0.1)
	if state.version ~= version then return end
	scriptSearch.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	state.phase = "closed"
	scriptSearch.Visible = false
	scriptSearch.UIGradient.Enabled = true
	debounce = false
end

-- Search-only transport: bounded work, short-lived cache, and shared requests.
altairValues.searchTransport = { cache = {}, pending = {}, active = 0, hits = 0, bytes = 0, cooldown = 0 }
function altairValues.searchTransport:get(url, current)
	local deadline = os.clock() + 12
	if not current() then return nil, "Cancelled" end
	local cached = self.cache[url]
	if cached and cached.expires > os.clock() then
		cached.used = os.clock(); self.hits += 1
		return cached.value
	end
	if os.clock() < self.cooldown then return nil, "Search is rate limited; try again shortly." end
	if type(httpRequest) ~= "function" then return nil, "This executor does not provide HTTP requests." end
	while self.active >= 4 and not self.pending[url] do
		if not current() then return nil, "Cancelled" end
		if os.clock() >= deadline then return nil, "Search is busy; try again shortly." end
		task.wait(0.05)
	end
	if not current() then return nil, "Cancelled" end
	if os.clock() < self.cooldown then return nil, "Search is rate limited; try again shortly." end
	local job = self.pending[url]
	if not job then
		job = { done = false }
		self.pending[url] = job
		self.active += 1
		task.spawn(function()
			local ok, result = pcall(function()
				local response = httpRequest({ Url = url, Method = "GET", Timeout = 12 })
				assert(type(response) == "table", "No response received.")
				local status = tonumber(response.StatusCode or response.Status) or 200
				if status == 429 then
					local headers = type(response.Headers) == "table" and response.Headers or {}
					self.cooldown = os.clock() + math.clamp(tonumber(headers["Retry-After"] or headers["retry-after"]) or 15, 1, 60)
				end
				assert(status >= 200 and status < 300, "Search returned HTTP " .. tostring(status) .. ".")
				assert(type(response.Body) == "string" and #response.Body <= 1024 * 1024, "Search response is missing or too large.")
				local value = httpService:JSONDecode(response.Body)
				assert(type(value) == "table", "Invalid search response.")
				assert((type(value.result) == "table" and type(value.result.scripts) == "table")
					or type(value.script) == "table", "Search data is unavailable.")
				if UI.Parent then
					local old = self.cache[url]
					if old then self.bytes -= old.bytes end
					self.cache[url] = { value = value, bytes = #response.Body, used = os.clock(), expires = os.clock() + 60 }
					self.bytes += #response.Body
					while true do
						local count, oldest, stamp = 0, nil, math.huge
						for key, entry in pairs(self.cache) do
							count += 1
							if entry.used < stamp then oldest, stamp = key, entry.used end
						end
						if count <= 32 and self.bytes <= 4 * 1024 * 1024 then break end
						self.bytes -= self.cache[oldest].bytes; self.cache[oldest] = nil
					end
				end
				return value
			end)
			job.value = ok and result or nil
			job.problem = not ok and tostring(result) or nil
			job.done = true
			self.active -= 1
			self.pending[url] = nil
		end)
	end
	while not job.done do
		if not current() then return nil, "Cancelled" end
		if os.clock() >= deadline then return nil, "Search timed out; you can retry." end
		task.wait(0.05)
	end
	if not current() then return nil, "Cancelled" end
	return job.value, job.problem
end
local function createScript(result, current)
	if not current() or type(result) ~= "table" or type(result.title) ~= "string" then return end
	local newScript = UI.ScriptSearch.List.Template:Clone()
	newScript.Name = result.title
	newScript.Parent = UI.ScriptSearch.List
	newScript.Visible = true

	for _, tag in ipairs(newScript.Tags:GetChildren()) do
		if tag.ClassName == "Frame" then
			tag.Shadow.ImageTransparency = 1
			tag.BackgroundTransparency = 1
			tag.Title.TextTransparency = 1
		end
	end

	task.defer(function()
		local response = altairValues.searchTransport:get("https://scriptblox.com/api/script/" .. httpService:UrlEncode(tostring(result.slug or "")),
			function() return current() and newScript.Parent ~= nil end)
		if not current() or not newScript.Parent then return end
		if not response or type(response.script) ~= "table" then
			newScript.ScriptDescription.Text = "Details unavailable. The search result is still available."
			return
		end

		newScript.ScriptDescription.Text = tostring(response.script.features or "No description provided.")

		local likes = tonumber(response.script.likeCount) or 0
		local dislikes = tonumber(response.script.dislikeCount) or 0

		if likes ~= dislikes then
			newScript.Tags.Review.Title.Text = (likes > dislikes) and "Positive Reviews" or "Negative Reviews"
			newScript.Tags.Review.BackgroundColor3 = (likes > dislikes) and Color3.fromRGB(0, 139, 102) or Color3.fromRGB(180, 0, 0)
			newScript.Tags.Review.Size = (likes > dislikes) and UDim2.new(0, 145, 1, 0) or UDim2.new(0, 150, 1, 0)
		elseif likes > 0 then
			newScript.Tags.Review.Title.Text = "Mixed Reviews"
			newScript.Tags.Review.BackgroundColor3 = Color3.fromRGB(198, 132, 0)
			newScript.Tags.Review.Size = UDim2.new(0, 130, 1, 0)
		else
			newScript.Tags.Review.Visible = false
		end

		local owner = type(response.script.owner) == "table" and response.script.owner or {}
		newScript.ScriptAuthor.Text = "uploaded by " .. tostring(owner.username or "Unknown")
		newScript.Tags.Verified.Visible = owner.verified == true

		tweenService:Create(newScript, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.8 }):Play()
		tweenService:Create(newScript.ScriptName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(newScript.Execute, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.8 }):Play()
		tweenService:Create(newScript.Execute, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

		newScript.Tags.Visible = true

		tweenService:Create(newScript.ScriptDescription, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
		tweenService:Create(newScript.ScriptAuthor, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.7 }):Play()

		for _, tag in ipairs(newScript.Tags:GetChildren()) do
			if tag.ClassName == "Frame" then
				tweenService:Create(tag.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
				tweenService:Create(tag, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(tag.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
			end
		end
	end)

	wipeTransparency(newScript, 1, true)

	newScript.ScriptName.Text = result.title
	newScript.ScriptDescription.Text = "Loading details..."
	newScript.ScriptAuthor.Text = ""
	newScript.BackgroundTransparency = 0.8
	newScript.ScriptName.TextTransparency = 0
	newScript.Execute.BackgroundTransparency = 0.8
	newScript.Execute.TextTransparency = 0
	newScript.ScriptDescription.TextTransparency = 0.3

	newScript.Tags.Visible = false
	newScript.Tags.Patched.Visible = result.isPatched or false

	newScript.Execute.MouseButton1Click:Connect(function()
		if type(result.script) ~= "string" or #result.script == 0 then
			queueNotification("ScriptSearch", "ScriptBlox didn't return a script body for " .. result.title .. ".", 4384402990)
			return
		end

		queueNotification("ScriptSearch", "Running " .. result.title .. " via ScriptSearch", 4384403532)
		closeScriptSearch()

		local compiled, chunk, compileError = pcall(loadstring, result.script)
		if not compiled or type(chunk) ~= "function" then
			altairValues.activity:record("Script failed", result.title .. " · Compile error")
			queueNotification("ScriptSearch", "Couldn't run " .. result.title .. ": " .. tostring(compiled and compileError or chunk), 4384402990)
			return
		end

		altairValues.activity:record("Script started", result.title .. " · ScriptSearch")
		local runSuccess, runError = pcall(chunk)
		if not runSuccess then
			altairValues.activity:record("Script failed", result.title .. " · Runtime error")
			queueNotification("ScriptSearch", result.title .. " errored while running: " .. tostring(runError), 4384402990)
		end
	end)
end
local function extractDomain(link)
	local domainToReturn = link:match("([%w-_]+%.[%w-_%.]+)")
	return domainToReturn
end

local function readAllowlist()
	if not (isfile and readfile) then
		return nil
	end

	local path = altairValues.altairFolder .. "/" .. "allowedLinks.altair"
	local readSuccess, raw = pcall(function()
		return isfile(path) and readfile(path) or nil
	end)

	if not readSuccess or not raw then
		return nil
	end

	local decodeSuccess, decoded = pcall(httpService.JSONDecode, httpService, raw)
	if not decodeSuccess or type(decoded) ~= "table" then
		warn("Altair | allowedLinks.altair was unreadable and has been ignored")
		return nil
	end

	return decoded
end

local function securityDetection(title, content, link, gradient, actions)
	if not checkAltair() then
		return
	end

	local domain = extractDomain(link) or link
	checkFolder()
	local currentAllowlist = readAllowlist()
	if currentAllowlist and table.find(currentAllowlist, domain) then
		return true
	end

	local newSecurityPrompt = UI.SecurityPrompt:Clone()

	newSecurityPrompt.Parent = UI
	newSecurityPrompt.Name = link

	wipeTransparency(newSecurityPrompt, 1, true)
	newSecurityPrompt.Size = UDim2.new(0, 478, 0, 150)

	newSecurityPrompt.Title.Text = title
	newSecurityPrompt.Subtitle.Text = content
	newSecurityPrompt.FoundLink.Text = domain

	newSecurityPrompt.Visible = true
	newSecurityPrompt.UIGradient.Color = gradient

	newSecurityPrompt.Buttons.Template.Visible = false

	local function closeSecurityPrompt()
		tweenService:Create(newSecurityPrompt, TweenInfo.new(0.52, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 500, 0, 165) }):Play()
		tweenService:Create(newSecurityPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(newSecurityPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(newSecurityPrompt.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(newSecurityPrompt.FoundLink, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()

		for _, button in ipairs(newSecurityPrompt.Buttons:GetChildren()) do
			if button.Name ~= "Template" and button.ClassName == "TextButton" then
				tweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
				tweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			end
		end
		task.wait(0.55)
		newSecurityPrompt:Destroy()
	end

	local decision

	for _, action in ipairs(actions) do
		local newAction = newSecurityPrompt.Buttons.Template:Clone()
		newAction.Name = action[1]
		newAction.Text = action[1]
		newAction.Parent = newSecurityPrompt.Buttons
		newAction.Visible = true
		newAction.Size = UDim2.new(0, newAction.TextBounds.X + 50, 0, 36) -- textbounds

		newAction.MouseButton1Click:Connect(function()
			if decision ~= nil then
				return
			end -- one answer per prompt

			if action[2] then
				if action[3] and writefile then
					checkFolder()
					local allowed = currentAllowlist or {}
					table.insert(allowed, domain)
					pcall(writefile, altairValues.altairFolder .. "/" .. "allowedLinks.altair", httpService:JSONEncode(allowed))
				end
				decision = true
			else
				decision = false
			end

			closeSecurityPrompt()
		end)
	end

	tweenService:Create(newSecurityPrompt, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 576, 0, 181) }):Play()
	tweenService:Create(newSecurityPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(newSecurityPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(newSecurityPrompt.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
	task.wait(0.03)
	tweenService:Create(newSecurityPrompt.FoundLink, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()

	task.wait(0.1)

	for _, button in ipairs(newSecurityPrompt.Buttons:GetChildren()) do
		if button.Name ~= "Template" and button.ClassName == "TextButton" then
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.05 }):Play()
			task.wait(0.1)
		end
	end

	newSecurityPrompt.FoundLink.MouseEnter:Connect(function()
		newSecurityPrompt.FoundLink.Text = link
		tweenService:Create(newSecurityPrompt.FoundLink, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.4 }):Play()
	end)

	newSecurityPrompt.FoundLink.MouseLeave:Connect(function()
		newSecurityPrompt.FoundLink.Text = domain
		tweenService:Create(newSecurityPrompt.FoundLink, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()
	end)

	local deadline = os.clock() + SECURITY_PROMPT_TIMEOUT
	while decision == nil do
		if os.clock() > deadline then
			decision = false
			task.spawn(closeSecurityPrompt)
			break
		end
		if not newSecurityPrompt.Parent then
			decision = false
			break
		end
		task.wait()
	end

	return decision
end

if originalRequest then
	altairValues.lifecycle.requestWrapper = function(data)
		if type(data) ~= "table" then
			return originalRequest(data)
		end

		if not (checkAltair() and settingValue("Intelligent HTTP Interception")) then
			return originalRequest(data)
		end

		local title = "Do you trust this source?"
		local content = "Altair has prevented data from being sent off-client, would you like to allow data to be sent or retrieved from this source?"
		local url = data.Url or data.url or "Unknown Link"
		local gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.new(0.764706, 0.305882, 0.0941176)) })
		local actions = { { "Always Allow", true, true }, { "Allow just this once", true }, { "Don't Allow", false } }

		if url == "http://127.0.0.1:6463/rpc?v=1" and data.Body then
			local decodeSuccess, bodyDecoded = pcall(httpService.JSONDecode, httpService, data.Body)

			if decodeSuccess and type(bodyDecoded) == "table" and bodyDecoded.cmd == "INVITE_BROWSER" then
				title = "Would you like to join this Discord server?"
				content = "Altair has prevented your Discord client from automatically joining this Discord server, would you like to continue and join, or block it?"
				url = bodyDecoded.args and bodyDecoded.args.code and "discord.gg/" .. bodyDecoded.args.code or "Unknown Invite"
				gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.new(0.345098, 0.396078, 0.94902)) })
				actions = { { "Allow", true }, { "Don't Allow", false } }
			end
		end

		if securityDetection(title, content, url, gradient, actions) then
			return originalRequest(data)
		end

		return {
			Success = false,
			StatusCode = 403,
			StatusMessage = "Blocked by Altair",
			Headers = {},
			Body = "",
		}
	end

	altairValues.lifecycle:replaceGlobal(index, altairValues.lifecycle.requestWrapper)
	for _, alias in ipairs({ "request", "http_request" }) do
		if alias ~= index and env[alias] then
			altairValues.lifecycle:replaceGlobal(alias, altairValues.lifecycle.requestWrapper)
		end
	end
end

if originalSetClipboard then
	altairValues.lifecycle.clipboardWrapper = function(data)
		if not (checkAltair() and settingValue("Intelligent Clipboard Interception")) then
			return originalSetClipboard(data)
		end

		local title = "Would you like to copy this to your clipboard?"
		local content = "Altair has prevented a script from setting the below text to your clipboard, would you like to allow this, or prevent it from copying?"
		local url = tostring(data or "Unknown Clipboard")
		local gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.new(0.776471, 0.611765, 0.529412)) })
		local actions = { { "Allow", true }, { "Don't Allow", false } }

		if securityDetection(title, content, url, gradient, actions) then
			return originalSetClipboard(data)
		end
	end
	altairValues.lifecycle:replaceGlobal(indexSetClipboard, altairValues.lifecycle.clipboardWrapper)
end

local function searchScriptBlox(query)
	local state = altairValues.scriptSearchState
	query = tostring(query or ""):match("^%s*(.-)%s*$")
	if query == "" or #query > 160 or state.phase ~= "open" then return end
	if state.searching == query then return end
	state.requestVersion = (state.requestVersion or 0) + 1
	local requestVersion, version = state.requestVersion, state.version
	state.searching = query
	local function current()
		return UI.Parent ~= nil and scriptSearch.Visible and state.phase == "open"
			and state.version == version and state.requestVersion == requestVersion
	end
	scriptSearch.SearchBox.PlaceholderText = "Searching..."
	local response, problem = altairValues.searchTransport:get(
		"https://scriptblox.com/api/script/search?q=" .. httpService:UrlEncode(query) .. "&mode=free&max=20&page=1", current)
	if not current() then return end
	state.searching = nil
	scriptSearch.SearchBox.PlaceholderText = "Search ScriptBlox.com"
	if not response or type(response.result) ~= "table" or type(response.result.scripts) ~= "table" then
		queueNotification("ScriptSearch", problem or "Search data is unavailable. Try again.", 4384402990)
		return -- Keep the query and previous results available for retry.
	end

	tweenService:Create(scriptSearch.NoScriptsTitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	tweenService:Create(scriptSearch.NoScriptsDesc, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()

	for _, createdScript in ipairs(scriptSearch.List:GetChildren()) do
		if createdScript.Name ~= "Placeholder" and createdScript.Name ~= "Template" and createdScript.ClassName == "Frame" then
			wipeTransparency(createdScript, 1, true)
		end
	end

	scriptSearch.List.Visible = true
	task.wait(0.5)
	if not current() then return end

	scriptSearch.List.CanvasPosition = Vector2.new(0, 0)

	for _, createdScript in ipairs(scriptSearch.List:GetChildren()) do
		if createdScript.Name ~= "Placeholder" and createdScript.Name ~= "Template" and createdScript.ClassName == "Frame" then
			createdScript:Destroy()
		end
	end

	tweenService:Create(scriptSearch, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 580, 0, 529) }):Play()
	tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.054, 0, 0.056, 0) }):Play()
	tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.523, 0, 0.056, 0) }):Play()
	tweenService:Create(scriptSearch.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.6) }):Play()

	local scriptCreated = false
	for index, scriptResult in ipairs(response.result.scripts) do
		if index > 20 or not current() then break end
		if type(scriptResult) == "table" and type(scriptResult.title) == "string" and pcall(createScript, scriptResult, current) then
			scriptCreated = true
		end
	end

	if not scriptCreated then
		task.wait(0.2)
		if not current() then return end
		tweenService:Create(scriptSearch.NoScriptsTitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		task.wait(0.1)
		if not current() then return end
		tweenService:Create(scriptSearch.NoScriptsDesc, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	else
		tweenService:Create(scriptSearch.List, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ScrollBarImageTransparency = 0 }):Play()
	end
end
-- Each toggle owns its animation steps; older coroutines/callbacks cannot resume it.
local smartBarTransition = { generation = 0, tweens = {} }

function smartBarTransition:begin()
	self.generation += 1
	for _, tween in ipairs(self.tweens) do tween:Cancel() end
	table.clear(self.tweens)
	altairValues.smartBarLayout:cancelDragPositionTween()
	return self.generation
end

function smartBarTransition:create(object, info, goal)
	local tween = tweenService:Create(object, info, goal)
	table.insert(self.tweens, tween)
	return tween
end

local function openSmartBar()
	local transition = smartBarTransition:begin()
	smartBarOpen = true
	updateBackpackLayout()

	smartBar.Back.BackgroundTransparency = 1
	smartBar.Back.UIStroke.Transparency = 1
	smartBar.BackgroundTransparency = 1
	smartBar.Back.Time.TextTransparency = 1
	smartBar.Back.Time.AMPM.TextTransparency = 1
	smartBar.UIStroke.Enabled = true
	smartBar.UIStroke.Thickness = 1
	smartBar.UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	smartBar.UIStroke.Transparency = 1
	smartBar.Shadow.ImageTransparency = 1
	smartBar.Size = UDim2.fromOffset(300, 60)

	if not altairValues.smartBarPositionInitialized then
		local viewport = UI:IsA("ScreenGui") and UI.AbsoluteSize or camera.ViewportSize
		local half = smartBar.AbsoluteSize * 0.5
		smartBar.AnchorPoint = Vector2.new(0.5, 0.5)
		smartBar.Position = UDim2.fromOffset(viewport.X * 0.5, viewport.Y - half.Y - 8)
		altairValues.smartBarPositionInitialized = true
	end

	altairValues.smartBarLayout.closedAtDrag = false

	smartBar.Visible = true
	drag.Visible = not settingValue("Hide Bar")

	for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") then
			if button.Name == "Placeholder" then
				button.Visible = true
				button.BackgroundTransparency = 1
				button.Size = UDim2.fromOffset(34, 34)
				continue
			end

			local gradient = button:FindFirstChildOfClass("UIGradient")
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
			local icon = button:FindFirstChild("Icon")

			if gradient then gradient.Rotation = -120 end
			if strokeGradient then strokeGradient.Rotation = -120 end
			button.Size = UDim2.fromOffset(34, 34)
			button.BackgroundTransparency = 1
			if stroke then stroke.Transparency = 1 end
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then icon.ImageTransparency = 1 end
		end
	end

	altairValues.smartBarLayout:syncContents(false)
	altairValues.smartBarLayout:syncToasts()

	-- Drag leaves the closed SmartBar position and returns to its authored
	-- above/below resting position.
	do
		local target = altairValues.smartBarLayout:getRestDragCenter()
		altairValues.smartBarLayout:tweenDragCenter(target,
			TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end

	smartBarTransition:create(smartBar, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.1 }):Play()
	smartBarTransition:create(smartBar.Shadow, TweenInfo.new(1.2, Enum.EasingStyle.Quint), { ImageTransparency = 0.9 }):Play()
	smartBarTransition:create(smartBar.Back.Time, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	smartBarTransition:create(smartBar.Back.Time.AMPM, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	smartBarTransition:create(smartBar.UIStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Transparency = 0.85 }):Play()

	for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") and button.Name ~= "Placeholder" then
			local gradient = button:FindFirstChildOfClass("UIGradient")
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
			local icon = button:FindFirstChild("Icon")

			if stroke then smartBarTransition:create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Transparency = 0 }):Play() end
			smartBarTransition:create(button, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {
				Size = UDim2.fromOffset(34, 34),
				BackgroundTransparency = 0,
			}):Play()
			if gradient then smartBarTransition:create(gradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play() end
			if strokeGradient then smartBarTransition:create(strokeGradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play() end
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
				smartBarTransition:create(icon, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
			end
			task.wait(0.03)
			if transition ~= smartBarTransition.generation then return end
		end
	end

	smartBarTransition:create(smartBar.Back, TweenInfo.new(1, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.1 }):Play()
	smartBarTransition:create(smartBar.Back.UIStroke, TweenInfo.new(1, Enum.EasingStyle.Quint), { Transparency = 0.8 }):Play()
	altairValues.smartBarLayout:syncContents(true)
	altairValues.smartBarLayout:syncToasts()
end

local function closeSmartBar()
	local transition = smartBarTransition:begin()
	smartBarOpen = false
	updateBackpackLayout()

	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Back.Buttons:FindFirstChild(otherPanel.Name) and isPanel(otherPanel.Name) and otherPanel.Visible then
			task.spawn(closePanel, otherPanel.Name, true)
			task.wait()
			if transition ~= smartBarTransition.generation then return end
		end
	end

	smartBarTransition:create(smartBar.Back.Time, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	smartBarTransition:create(smartBar.Back.Time.AMPM, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()

	for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") and button.Name ~= "Placeholder" then
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local icon = button:FindFirstChild("Icon")
			if stroke then smartBarTransition:create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play() end
			smartBarTransition:create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
				Size = UDim2.fromOffset(30, 30),
				BackgroundTransparency = 1,
			}):Play()
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
				smartBarTransition:create(icon, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			end
		end
	end

	-- When closed, the visible Drag line rests on the outer SmartBar edge.
	drag.Visible = not settingValue("Hide Bar")
	altairValues.smartBarLayout.closedAtDrag = true

	local closeInfo = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	altairValues.smartBarLayout:tweenDragCenter(altairValues.smartBarLayout:getClosedDragCenter(),
		closeInfo, UDim2.fromOffset(150, 20))
	local shellGoal = {
		BackgroundTransparency = 1,
	}


	smartBarTransition:create(smartBar.Back.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	smartBarTransition:create(smartBar.Back, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
	smartBarTransition:create(smartBar, closeInfo, shellGoal):Play()
	smartBarTransition:create(smartBar.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	smartBarTransition:create(smartBar.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()

	task.delay(0.35, function()
		if transition == smartBarTransition.generation and not smartBarOpen and smartBar.Parent then
			smartBar.Visible = false
			smartBar.Size = UDim2.fromOffset(300, 60)
			altairValues.smartBarLayout:syncToasts()
		end
	end)
end

local function windowFocusChanged(value)
	if not checkAltair() then
		return
	end

	if value then -- Window Focused
		if setFpsCap then
			local cap = tonumber(settingValue("Artificial FPS Limit"))
			if cap then
				pcall(setFpsCap, cap)
			end
		end
		removeReverbs(0.5)
	else -- Window unfocused
		if settingValue("Muffle audio while unfocused") then
			createReverb(0.7)
		end
		if setFpsCap and settingValue("Limit FPS while unfocused") then
			pcall(setFpsCap, 30)
		end
	end
end

local function displaySystemMessage(visuals)
	if legacyChatActive then
		local success = pcall(starterGui.SetCore, starterGui, "ChatMakeSystemMessage", visuals)
		if success then
			return
		end
	end

	pcall(function()
		local channels = textChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:DisplaySystemMessage(visuals.Text)
		end
	end)
end

local function postWebhook(url, payload)
	if not originalRequest then
		return
	end
	if type(url) ~= "string" or not url:match("^https?://") then
		return
	end

	local encodeSuccess, body = pcall(httpService.JSONEncode, httpService, payload)
	if not encodeSuccess then
		return
	end

	task.spawn(function()
		pcall(originalRequest, {
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
end

local function onChatted(player, message)
	local enabled = settingValue("Chat Spy") and altairValues.chatSpy.enabled
	local chatSpyVisuals = altairValues.chatSpy.visual

	if not message or not checkAltair() then
		return
	end

	if legacyChatActive then
		altairValues.chatModeration:observe(player, message)
	end

	if enabled and player ~= localPlayer then
		local message2 = message:gsub("[\n\r]", ""):gsub("\t", " "):gsub("[ ]+", " ")
		local hidden = true

		local get = getMessage.OnClientEvent:Connect(function(packet, channel)
			local speakerPlayer = packet.FromSpeaker and players:FindFirstChild(packet.FromSpeaker)
			if
				packet.SpeakerUserId == player.UserId
				and packet.Message == message2:sub(#message2 - #packet.Message + 1)
				and (channel == "All" or (channel == "Team" and speakerPlayer and speakerPlayer.Team == localPlayer.Team))
			then
				hidden = false
			end
		end)

		task.wait(1)

		get:Disconnect()

		if hidden and enabled then
			chatSpyVisuals.Text = "Altair Spy - [" .. player.Name .. "]: " .. message2
			displaySystemMessage(chatSpyVisuals)
		end
	end

	if settingValue("Log Messages") then
		postWebhook(settingValue("Message Webhook URL"), {
			["content"] = message,
			["avatar_url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png",
			["username"] = player.DisplayName,
			["allowed_mentions"] = { parse = {} },
		})
	end
end

local function sortPlayers()
	local entries = {}
	for _, child in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute("AltairRuntimePlayer") == true then
			table.insert(entries, child)
		end
	end

	table.sort(entries, function(playerA, playerB)
		local a = tostring(playerA:GetAttribute("AltairDisplayName") or playerA.Name):lower()
		local b = tostring(playerB:GetAttribute("AltairDisplayName") or playerB.Name):lower()
		if a == b then
			return tostring(playerA:GetAttribute("AltairUsername") or ""):lower()
				< tostring(playerB:GetAttribute("AltairUsername") or ""):lower()
		end
		return a < b
	end)

	for index, frame in ipairs(entries) do
		frame.LayoutOrder = index
	end
end

local function restoreCamera()
	spectating = nil
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.CameraType = Enum.CameraType.Custom
end

local function toggleSpectate(player)
	if spectating == player then
		restoreCamera()
		Toast("Camera returned to your character.")
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		Toast(player.DisplayName .. " doesn't have a loaded character right now.")
		return false
	end

	spectating = player
	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom
	Toast("Now spectating " .. player.DisplayName .. ".")
	return true
end

local function teleportTo(player)
	local targetCharacter = player.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	local localCharacter = localPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")

	if targetRoot and localRoot then
		Toast("Teleporting to " .. player.DisplayName .. ".")
		localRoot.CFrame = CFrame.new(targetRoot.Position) * (localRoot.CFrame - localRoot.CFrame.Position)
		return true
	end

	Toast(player.DisplayName .. " cannot be teleported to right now.")
	return false
end

function altairValues.playerlistUI:_visualObjects(root)
	local objects = { root }
	for _, object in ipairs(root:GetDescendants()) do
		table.insert(objects, object)
	end
	return objects
end

function altairValues.playerlistUI:_cacheVisual(root)
	if not root then
		return
	end
	for _, object in ipairs(self:_visualObjects(root)) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			for _, property in ipairs(properties) do
				local attribute = "AltairPlayerlist_" .. property
				if object:GetAttribute(attribute) == nil then
					object:SetAttribute(attribute, object[property])
				end
			end
		end
	end
end

function altairValues.playerlistUI:_setVisual(root, visible, duration)
	if not root then
		return
	end
	self:_cacheVisual(root)
	root.Visible = true
	for _, object in ipairs(self:_visualObjects(root)) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			local goal = {}
			for _, property in ipairs(properties) do
				local stored = object:GetAttribute("AltairPlayerlist_" .. property)
				goal[property] = visible and (stored ~= nil and stored or object[property]) or 1
			end
			tweenService:Create(
				object,
				TweenInfo.new(duration or 0.42, Enum.EasingStyle.Quint, visible and Enum.EasingDirection.Out or Enum.EasingDirection.In),
				goal
			):Play()
		end
	end
end

function altairValues.playerlistUI:_primeHidden(root)
	if not root then
		return
	end
	self:_cacheVisual(root)
	for _, object in ipairs(self:_visualObjects(root)) do
		local properties = altairValues.transparencyProperties[object.ClassName]
		if properties then
			for _, property in ipairs(properties) do
				object[property] = 1
			end
		end
	end
end

function altairValues.playerlistUI:_clickTarget(object)
	if not object then
		return nil
	end
	if object:IsA("GuiButton") then
		return object
	end
	local interact = object:FindFirstChild("Interact", true)
	if interact and interact:IsA("GuiButton") then
		return interact
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant
		end
	end
	return nil
end

function altairValues.playerlistUI:_setObjectText(object, value)
	if not object then
		return
	end
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		object.Text = tostring(value)
		return
	end
	local label = object:FindFirstChild("Value", true)
		or object:FindFirstChild("Title", true)
		or object:FindFirstChildWhichIsA("TextLabel", true)
		or object:FindFirstChildWhichIsA("TextButton", true)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		label.Text = tostring(value)
	end
end

function altairValues.playerlistUI:_setActionVisual(action, active)
	if not action or not action:IsA("GuiObject") then
		return
	end

	if action:GetAttribute("AltairIdleBackground") == nil then
		action:SetAttribute("AltairIdleBackground", action.BackgroundColor3)
	end

	local icon = action:FindFirstChild("Icon", true)
	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) and icon:GetAttribute("AltairIdleImageColor") == nil then
		icon:SetAttribute("AltairIdleImageColor", icon.ImageColor3)
	end

	local stroke = action:FindFirstChildOfClass("UIStroke")
	if stroke and stroke:GetAttribute("AltairIdleStrokeColor") == nil then
		stroke:SetAttribute("AltairIdleStrokeColor", stroke.Color)
	end

	local activeColor = Color3.fromRGB(0, 152, 111)
	local idleBackground = action:GetAttribute("AltairIdleBackground") or action.BackgroundColor3
	local idleIcon = icon and icon:GetAttribute("AltairIdleImageColor")
	local idleStroke = stroke and stroke:GetAttribute("AltairIdleStrokeColor")

	tweenService:Create(
		action,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint),
		{ BackgroundColor3 = active and activeColor or idleBackground }
	):Play()

	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		tweenService:Create(
			icon,
			TweenInfo.new(0.35, Enum.EasingStyle.Quint),
			{ ImageColor3 = active and Color3.fromRGB(220, 220, 220) or (idleIcon or icon.ImageColor3) }
		):Play()
	end

	if stroke then
		tweenService:Create(
			stroke,
			TweenInfo.new(0.35, Enum.EasingStyle.Quint),
			{ Color = active and activeColor or (idleStroke or stroke.Color) }
		):Play()
	end
end

function altairValues.playerlistUI:_pulseAction(action, success)
	if not action then
		return
	end

	self:_setActionVisual(action, success == true)
	task.delay(0.5, function()
		if checkAltair() then
			self:_setActionVisual(action, false)
		end
	end)
end

function altairValues.playerlistUI:init()
	if self.initialized then
		return self.available
	end
	self.initialized = true

	local interactions = playerlistPanel:FindFirstChild("Interactions")
	self.interactions = interactions
	self.list = interactions and interactions:FindFirstChild("List")
	self.search = interactions and interactions:FindFirstChild("SearchFrame")
	self.selectedProfile = interactions and interactions:FindFirstChild("SelectedPlayer")
	self.selectedActions = interactions and interactions:FindFirstChild("SelectedActions")
	self.teamList = interactions and interactions:FindFirstChild("TeamList")

	self.available = self.list ~= nil
		and self.search ~= nil
		and self.selectedProfile ~= nil
		and self.selectedActions ~= nil

	if not self.available then
		return false
	end

	self.template = self.list:FindFirstChild("Template")
	if not self.template or not self.template:IsA("GuiObject") then
		self.available = false
		return false
	end

	self.template.Visible = false
	self.template.Size = UDim2.new(self.template.Size.X.Scale, self.template.Size.X.Offset, 0, 34)
	if altairValues.applyPlayerlistBase then altairValues.applyPlayerlistBase(self.template) end
	if altairValues.applyPlayerlistBase then altairValues.applyPlayerlistBase(self.selectedProfile) end

	for _, row in ipairs(self.list:GetChildren()) do
		if row:IsA("GuiObject") and row:GetAttribute("AltairRuntimePlayer") == true then
			if altairValues.applyPlayerlistBase then altairValues.applyPlayerlistBase(row) end
		end
	end
	for _, child in ipairs(self.list:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute("AltairRuntimePlayer") ~= true then
			if child.Name == "Placeholder" then
				child.Visible = true
				child.BackgroundTransparency = 1
			elseif child ~= self.template then
				child.Visible = false
			end
		end
	end

	self.selectedListPosition = self.list.Position
	self.selectedListSize = self.list.Size
	self.selectedSearchPosition = self.search.Position
	self.selectedSearchSize = self.search.Size

	self.profilePosition = self.selectedProfile.Position
	self.actionsPosition = self.selectedActions.Position
	self.teamPosition = self.teamList and self.teamList.Position or nil

	local listRightScale = self.selectedListPosition.X.Scale + self.selectedListSize.X.Scale
	local listRightOffset = self.selectedListPosition.X.Offset + self.selectedListSize.X.Offset
	local searchRightScale = self.selectedSearchPosition.X.Scale + self.selectedSearchSize.X.Scale
	local searchRightOffset = self.selectedSearchPosition.X.Offset + self.selectedSearchSize.X.Offset
	local expandedLeft = self.profilePosition.X

	self.listOnlyPosition = UDim2.new(
		expandedLeft.Scale,
		expandedLeft.Offset,
		self.selectedListPosition.Y.Scale,
		self.selectedListPosition.Y.Offset
	)
	self.listOnlySize = UDim2.new(
		listRightScale - expandedLeft.Scale,
		listRightOffset - expandedLeft.Offset,
		self.selectedListSize.Y.Scale,
		self.selectedListSize.Y.Offset
	)
	self.searchOnlyPosition = UDim2.new(
		expandedLeft.Scale,
		expandedLeft.Offset,
		self.selectedSearchPosition.Y.Scale,
		self.selectedSearchPosition.Y.Offset
	)
	self.searchOnlySize = UDim2.new(
		searchRightScale - expandedLeft.Scale,
		searchRightOffset - expandedLeft.Offset,
		self.selectedSearchSize.Y.Scale,
		self.selectedSearchSize.Y.Offset
	)

	self.profileHiddenPosition = self.profilePosition - UDim2.fromOffset(110, 0)
	self.actionsHiddenPosition = self.actionsPosition - UDim2.fromOffset(110, 0)
	self.teamHiddenPosition = self.teamPosition and (self.teamPosition - UDim2.fromOffset(110, 0)) or nil
	self.transitionVersion = 0

	self.subtitle = playerlistPanel:FindFirstChild("Subtitle", true)
	self.subtitleTextTransparency = nil
	if self.subtitle and (
		self.subtitle:IsA("TextLabel")
		or self.subtitle:IsA("TextButton")
		or self.subtitle:IsA("TextBox")
	) then
		self.subtitleTextTransparency = self.subtitle.TextTransparency
	end

	self.decorations = {}

	for _, object in ipairs(playerlistPanel:GetDescendants()) do
		local lowered = object.Name:lower()
		if object:IsA("Frame") and lowered:find("divider") then
			table.insert(self.decorations, object)
		end
	end

	self.headerDivider = playerlistPanel:FindFirstChild("HeaderDivider", true)
	if not self.headerDivider then
		self.headerDivider = Instance.new("Frame")
		self.headerDivider.Name = "AltairHeaderDivider"
		self.headerDivider.BorderSizePixel = 0
		self.headerDivider.BackgroundColor3 = Color3.fromRGB(84, 84, 88)
		self.headerDivider.BackgroundTransparency = 0.38
		self.headerDivider.AnchorPoint = Vector2.new(0, 0.5)
		self.headerDivider.Position = UDim2.new(0.025, 0, 0.16, 0)
		self.headerDivider.Size = UDim2.new(0.95, 0, 0, 1)
		self.headerDivider.ZIndex = math.max(playerlistPanel.ZIndex + 2, 2)
		self.headerDivider.Parent = playerlistPanel
		table.insert(self.decorations, self.headerDivider)
	end

	self.verticalDivider = self.interactions:FindFirstChild("VerticalDivider", true)
		or self.interactions:FindFirstChild("ActionsDivider", true)

	if not self.verticalDivider then
		self.verticalDivider = Instance.new("Frame")
		self.verticalDivider.Name = "AltairVerticalDivider"
		self.verticalDivider.BorderSizePixel = 0
		self.verticalDivider.BackgroundColor3 = Color3.fromRGB(84, 84, 88)
		self.verticalDivider.BackgroundTransparency = 0.38
		self.verticalDivider.AnchorPoint = Vector2.new(0.5, 0)
		self.verticalDivider.Position = UDim2.new(
			self.selectedSearchPosition.X.Scale,
			self.selectedSearchPosition.X.Offset - 12,
			self.selectedSearchPosition.Y.Scale,
			self.selectedSearchPosition.Y.Offset
		)
		self.verticalDivider.Size = UDim2.new(
			0,
			1,
			(self.selectedListPosition.Y.Scale + self.selectedListSize.Y.Scale) - self.selectedSearchPosition.Y.Scale,
			(self.selectedListPosition.Y.Offset + self.selectedListSize.Y.Offset) - self.selectedSearchPosition.Y.Offset
		)
		self.verticalDivider.ZIndex = math.max(self.interactions.ZIndex + 2, 2)
		self.verticalDivider.Parent = self.interactions
		table.insert(self.decorations, self.verticalDivider)
	end

	if self.subtitle then
		self:_cacheVisual(self.subtitle)
	end
	for _, decoration in ipairs(self.decorations) do
		self:_cacheVisual(decoration)
	end

	self:_cacheVisual(self.selectedProfile)
	self:_cacheVisual(self.selectedActions)
	if self.teamList then
		self:_cacheVisual(self.teamList)
	end

	local listZ = self.list.ZIndex
	local raisedZ = listZ + 10
	for _, root in ipairs({ self.selectedProfile, self.selectedActions, self.teamList }) do
		if root and root:IsA("GuiObject") then
			root.ZIndex = math.max(root.ZIndex, raisedZ)
		end
	end

	self.selectedProfile.Visible = false
	self.selectedActions.Visible = false
	if self.teamList then
		self.teamList.Visible = false
	end

	for _, actionName in ipairs({ "Spectate", "Teleport", "Bring", "ViewProfile" }) do
		local action = self.selectedActions:FindFirstChild(actionName)
		if action and action:IsA("GuiObject") then
			if action:GetAttribute("AltairOriginalActionSize") == nil then
				action:SetAttribute("AltairOriginalActionSize", action.Size)
			end
			local originalSize = action:GetAttribute("AltairOriginalActionSize")
			action.Size = UDim2.new(
				originalSize.X.Scale,
				originalSize.X.Offset - 10,
				originalSize.Y.Scale,
				originalSize.Y.Offset
			)
			if action:GetAttribute("AltairIdleBackground") == nil then
				action:SetAttribute("AltairIdleBackground", action.BackgroundColor3)
			end

			local actionIcon = action:FindFirstChild("Icon")
			if actionIcon and (actionIcon:IsA("ImageLabel") or actionIcon:IsA("ImageButton"))
				and actionIcon:GetAttribute("AltairIdleImageColor") == nil
			then
				actionIcon:SetAttribute("AltairIdleImageColor", actionIcon.ImageColor3)
			end

			local actionStroke = action:FindFirstChildOfClass("UIStroke")
			if actionStroke and actionStroke:GetAttribute("AltairIdleStrokeColor") == nil then
				actionStroke:SetAttribute("AltairIdleStrokeColor", actionStroke.Color)
			end
		end
	end

	local trackAction = self.selectedActions:FindFirstChild("Bring")
	if trackAction then
		local title = trackAction:FindFirstChild("Title", true)
		self:_setObjectText(title, "Track")
	end

	self.roleCache = self.roleCache or {}
	self.roleLoading = self.roleLoading or {}
	self.roleCallbacks = self.roleCallbacks or {}
	self.rowsOpening = false

	self:reset(true)
	return true
end

function altairValues.playerlistUI:_setRoleText(root, roleText)
	if not root then
		return
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") or root:IsA("TextBox") then
		root.Text = roleText
		root.Visible = true
		return
	end

	local preferred = root:FindFirstChild("Role", true)
		or root:FindFirstChild("Title", true)
		or root:FindFirstChild("Value", true)
		or root:FindFirstChild("Label", true)

	if preferred and (
		preferred:IsA("TextLabel")
		or preferred:IsA("TextButton")
		or preferred:IsA("TextBox")
	) then
		preferred.Text = roleText
		preferred.Visible = true
		return
	end

	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
			object.Text = roleText
			object.Visible = true
			return
		end
	end
end

function altairValues.playerlistUI:_applyProfileRole(player, roleText)
	if not player or self.selectedPlayer ~= player or not self.selectedProfile then
		return
	end

	local serverBadge = self.selectedProfile:FindFirstChild("InServer")
	if serverBadge and serverBadge:IsA("GuiObject") then
		serverBadge.Visible = true
		self:_setRoleText(serverBadge, roleText)
	end
end

function altairValues.playerlistUI:requestRole(player, callback)
	if not player then
		if callback then
			callback("In Server")
		end
		return
	end

	self.roleCache = self.roleCache or {}
	self.roleLoading = self.roleLoading or {}
	self.roleCallbacks = self.roleCallbacks or {}

	local userId = player.UserId
	local cached = self.roleCache[userId]
	if cached then
		if callback then
			callback(cached)
		end
		return
	end

	if callback then
		self.roleCallbacks[userId] = self.roleCallbacks[userId] or {}
		table.insert(self.roleCallbacks[userId], callback)
	end

	if self.roleLoading[userId] then
		return
	end
	self.roleLoading[userId] = true

	task.spawn(function()
		local roleText = "In Server"

		if creatorType == Enum.CreatorType.Group or altairValues.currentCreator == "group" then
			local ok, role = pcall(player.GetRoleInGroup, player, creatorId)
			if ok and type(role) == "string" and role ~= "" and role ~= "Guest" then
				roleText = role
			end
		end

		self.roleCache[userId] = roleText
		self.roleLoading[userId] = nil

		local callbacks = self.roleCallbacks[userId]
		self.roleCallbacks[userId] = nil

		if callbacks then
			for _, pendingCallback in ipairs(callbacks) do
				pcall(pendingCallback, roleText)
			end
		end
	end)
end

function altairValues.playerlistUI:_populate(player)
	if not self.available or not player then
		return
	end

	local profile = self.selectedProfile
	local avatar = profile:FindFirstChild("Avatar")
	local displayName = profile:FindFirstChild("DisplayName")
	local username = profile:FindFirstChild("Username")
	local friendBadge = profile:FindFirstChild("Friend")
	local serverBadge = profile:FindFirstChild("InServer")
	local premiumBadge = profile:FindFirstChild("Premium")
	local onlineDot = profile:FindFirstChild("OnlineDot")

	if avatar and (avatar:IsA("ImageLabel") or avatar:IsA("ImageButton")) then
		local expectedUserId = player.UserId
		local avatarBackdrop = profile:FindFirstChild("AvatarBackdrop")
		local onlineDotObject = profile:FindFirstChild("OnlineDot")

		avatar.Visible = true
		avatar.ImageTransparency = 0
		avatar.ImageColor3 = Color3.new(1, 1, 1)
		avatar.BackgroundTransparency = 1
		avatar.Image = "rbxthumb://type=AvatarHeadShot&id="
			.. tostring(expectedUserId)
			.. "&w=420&h=420"

		if avatarBackdrop and avatarBackdrop:IsA("GuiObject") then
			avatar.ZIndex = math.max(avatar.ZIndex, avatarBackdrop.ZIndex + 1)
		end
		if onlineDotObject and onlineDotObject:IsA("GuiObject") then
			onlineDotObject.ZIndex = math.max(onlineDotObject.ZIndex, avatar.ZIndex + 1)
		end

		task.spawn(function()
			local ok, image = pcall(
				players.GetUserThumbnailAsync,
				players,
				expectedUserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)

			if ok
				and image
				and self.selectedPlayer
				and self.selectedPlayer.UserId == expectedUserId
				and avatar.Parent
			then
				avatar.Image = image
				avatar.ImageTransparency = 0
			end
		end)
	end
	self:_setObjectText(displayName, player.DisplayName)
	self:_setObjectText(username, "@" .. player.Name)

	if onlineDot and onlineDot:IsA("GuiObject") then
		onlineDot.Visible = true
	end
	if serverBadge and serverBadge:IsA("GuiObject") then
		serverBadge.Visible = true
		self:_setRoleText(serverBadge, "In Server")
	end

	self:requestRole(player, function(roleText)
		if checkAltair() then
			self:_applyProfileRole(player, roleText)
		end
	end)
	if premiumBadge and premiumBadge:IsA("GuiObject") then
		premiumBadge.Visible = player.MembershipType == Enum.MembershipType.Premium
	end
	if friendBadge and friendBadge:IsA("GuiObject") then
		local ok, isFriend = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
		friendBadge.Visible = ok and isFriend or false
	end

	if self.teamList then
		local teamName = player.Team and player.Team.Name or "No Team"
		local title = self.teamList:FindFirstChild("Title")
		local value = self.teamList:FindFirstChild("Value")
		self:_setObjectText(title, "Team")
		self:_setObjectText(value, teamName)
	end

	local spectate = self.selectedActions:FindFirstChild("Spectate")
	local teleport = self.selectedActions:FindFirstChild("Teleport")
		or self.selectedActions:FindFirstChild("Goto")
	local trackAction = self.selectedActions:FindFirstChild("Track")
		or self.selectedActions:FindFirstChild("Bring")
	if spectate and spectate:IsA("GuiObject") then
		spectate.Visible = player ~= localPlayer
	end
	if teleport and teleport:IsA("GuiObject") then
		teleport.Visible = player ~= localPlayer
	end
	if trackAction and trackAction:IsA("GuiObject") then
		trackAction.Visible = player ~= localPlayer
		self:_setObjectText(trackAction:FindFirstChild("Title", true), "Track")
	end

	self:_setActionVisual(self.selectedActions:FindFirstChild("Spectate"), spectating == player)
	self:_setActionVisual(self.selectedActions:FindFirstChild("Teleport"), false)
	self:_setActionVisual(self.selectedActions:FindFirstChild("ViewProfile"), false)
	self:_setActionVisual(trackAction, locatedPlayers[player.Name] == true)
end

function altairValues.playerlistUI:_setPlayerRowHighlight(row, highlighted)
	if not row or not row.Parent or self.rowsOpening then
		return
	end

	local gradient = row:FindFirstChildOfClass("UIGradient")
	local stroke = row:FindFirstChildOfClass("UIStroke")
	local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
	local avatar = row:FindFirstChild("Avatar", true)
	if highlighted then
		if gradient then
			tweenService:Create(
				gradient,
				TweenInfo.new(1.4, Enum.EasingStyle.Quint),
				{ Rotation = 360 }
			):Play()
			tweenService:Create(
				gradient,
				TweenInfo.new(0.7, Enum.EasingStyle.Quint),
				{ Offset = Vector2.new(0, -0.5) }
			):Play()
		end

		if strokeGradient then
			tweenService:Create(
				strokeGradient,
				TweenInfo.new(1.4, Enum.EasingStyle.Quint),
				{ Rotation = 360 }
			):Play()
		end

		if stroke then
			tweenService:Create(
				stroke,
				TweenInfo.new(0.8, Enum.EasingStyle.Quint),
				{ Transparency = 1 }
			):Play()
		end

		if avatar and (avatar:IsA("ImageLabel") or avatar:IsA("ImageButton")) then
			tweenService:Create(
				avatar,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint),
				{ ImageTransparency = 0 }
			):Play()
		end
	else
		if strokeGradient then
			tweenService:Create(
				strokeGradient,
				TweenInfo.new(0.6, Enum.EasingStyle.Quint),
				{ Rotation = 50 }
			):Play()
		end

		if gradient then
			tweenService:Create(
				gradient,
				TweenInfo.new(0.9, Enum.EasingStyle.Quint),
				{ Rotation = 50 }
			):Play()
			tweenService:Create(
				gradient,
				TweenInfo.new(0.7, Enum.EasingStyle.Quint),
				{ Offset = Vector2.new(0, 0) }
			):Play()
		end

		if stroke then
			tweenService:Create(
				stroke,
				TweenInfo.new(0.6, Enum.EasingStyle.Quint),
				{ Transparency = 0.12 }
			):Play()
		end

		if avatar and (avatar:IsA("ImageLabel") or avatar:IsA("ImageButton")) then
			tweenService:Create(
				avatar,
				TweenInfo.new(0.2, Enum.EasingStyle.Quint),
				{ ImageTransparency = 0 }
			):Play()
		end
	end
end

function altairValues.playerlistUI:_highlightSelected()
	if not self.list then
		return
	end

	local selectedUserId = self.selectedPlayer and self.selectedPlayer.UserId or nil

	for _, row in ipairs(self.list:GetChildren()) do
		if row:IsA("GuiObject") and row:GetAttribute("AltairRuntimePlayer") == true then
			local rowUserId = tonumber(row:GetAttribute("AltairPlayerUserId"))
			self:_setPlayerRowHighlight(
				row,
				selectedUserId ~= nil and rowUserId == selectedUserId
			)
		end
	end

	if not settingValue("Rainbow Mode", false) and altairValues.applyPlayerlistBase then
		altairValues.applyPlayerlistBase(self.selectedProfile)
	end
end

function altairValues.playerlistUI:_setRuntimeRowMode(selected)
	for _, row in ipairs(self.list:GetChildren()) do
		if row:IsA("GuiObject") then
			if row:GetAttribute("AltairRuntimePlayer") == true then
				row.Size = selected
					and UDim2.fromOffset(221, 34)
					or UDim2.new(1, -26, 0, 34)
			elseif row.Name == "Placeholder" then
				row.Visible = true
				row.BackgroundTransparency = 1
			end
		end
	end
end

function altairValues.playerlistUI:select(player)
	if not self:init() or not player then
		return
	end

	if self.selectedPlayer == player then
		self:reset(false)
		return
	end

	local firstSelection = self.selectedPlayer == nil
	self.transitionVersion += 1
	local transitionVersion = self.transitionVersion

	self.selectedPlayer = player
	self:_setRuntimeRowMode(true)

	if altairValues.playerlistUI.panelSize then
		playerlistPanel.Size = altairValues.playerlistUI.panelSize
	end

	self:_populate(player)
	self:_highlightSelected()

	if not firstSelection then
		return
	end

	self:_primeHidden(self.selectedProfile)
	self:_primeHidden(self.selectedActions)
	if self.teamList then
		self:_primeHidden(self.teamList)
	end

	self.selectedProfile.Position = self.profileHiddenPosition
	self.selectedActions.Position = self.actionsHiddenPosition
	if self.teamList and self.teamHiddenPosition then
		self.teamList.Position = self.teamHiddenPosition
	end

	self.selectedProfile.Visible = true
	self.selectedActions.Visible = true
	if self.teamList then
		self.teamList.Visible = true
	end

	if self.verticalDivider then
		self:_primeHidden(self.verticalDivider)
		self.verticalDivider.Visible = true
		self:_setVisual(self.verticalDivider, true, 0.42)
	end

	local layoutTween = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	tweenService:Create(self.list, layoutTween, {
		Position = self.selectedListPosition,
		Size = self.selectedListSize,
	}):Play()
	tweenService:Create(self.search, layoutTween, {
		Position = self.selectedSearchPosition,
		Size = self.selectedSearchSize,
	}):Play()

	tweenService:Create(self.selectedProfile, layoutTween, {
		Position = self.profilePosition,
	}):Play()
	tweenService:Create(self.selectedActions, layoutTween, {
		Position = self.actionsPosition,
	}):Play()

	if self.teamList and self.teamPosition then
		tweenService:Create(self.teamList, layoutTween, {
			Position = self.teamPosition,
		}):Play()
	end

	self:_setVisual(self.selectedProfile, true, 0.48)
	self:_setVisual(self.selectedActions, true, 0.48)
	if self.teamList then
		self:_setVisual(self.teamList, true, 0.48)
	end

	task.delay(0.56, function()
		if self.transitionVersion ~= transitionVersion then
			return
		end
	end)
end

function altairValues.playerlistUI:reset(immediate)
	if not self:init() then
		return
	end

	self.transitionVersion += 1
	local transitionVersion = self.transitionVersion
	self.selectedPlayer = nil
	self:_setRuntimeRowMode(false)
	self:_highlightSelected()

	if altairValues.playerlistUI.panelSize then
		playerlistPanel.Size = altairValues.playerlistUI.panelSize
	end

	if immediate then
		self.list.Position = self.listOnlyPosition
		self.list.Size = self.listOnlySize
		self.search.Position = self.searchOnlyPosition
		self.search.Size = self.searchOnlySize

		self.selectedProfile.Position = self.profileHiddenPosition
		self.selectedActions.Position = self.actionsHiddenPosition
		self.selectedProfile.Visible = false
		self.selectedActions.Visible = false

		if self.teamList then
			self.teamList.Position = self.teamHiddenPosition or self.teamPosition
			self.teamList.Visible = false
		end

		if self.verticalDivider then
			self.verticalDivider.Visible = false
		end
		return
	end

	-- Keep the list on the right while the profile/actions slide out.
	self.list.Position = self.selectedListPosition
	self.list.Size = self.selectedListSize
	self.search.Position = self.selectedSearchPosition
	self.search.Size = self.selectedSearchSize

	local exitTween = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)

	if self.selectedProfile.Visible then
		tweenService:Create(self.selectedProfile, exitTween, {
			Position = self.profileHiddenPosition,
		}):Play()
		self:_setVisual(self.selectedProfile, false, 0.38)
	end

	if self.selectedActions.Visible then
		tweenService:Create(self.selectedActions, exitTween, {
			Position = self.actionsHiddenPosition,
		}):Play()
		self:_setVisual(self.selectedActions, false, 0.38)
	end

	if self.teamList and self.teamList.Visible and self.teamHiddenPosition then
		tweenService:Create(self.teamList, exitTween, {
			Position = self.teamHiddenPosition,
		}):Play()
		self:_setVisual(self.teamList, false, 0.38)
	end

	if self.verticalDivider and self.verticalDivider.Visible then
		self:_setVisual(self.verticalDivider, false, 0.3)
	end

	-- Only AFTER the left content is out do we let the list claim that space.
	task.delay(0.5, function()
		if self.transitionVersion ~= transitionVersion or self.selectedPlayer ~= nil then
			return
		end

		self.selectedProfile.Visible = false
		self.selectedActions.Visible = false
		if self.teamList then
			self.teamList.Visible = false
		end
		if self.verticalDivider then
			self.verticalDivider.Visible = false
		end

		local expandTween = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tweenService:Create(self.list, expandTween, {
			Position = self.listOnlyPosition,
			Size = self.listOnlySize,
		}):Play()
		tweenService:Create(self.search, expandTween, {
			Position = self.searchOnlyPosition,
			Size = self.searchOnlySize,
		}):Play()
	end)
end

function altairValues.playerlistUI:prepareClose()
	if not self:init() then
		return
	end

	self.transitionVersion += 1
	self.selectedPlayer = nil
	self:_setRuntimeRowMode(false)
	self:_highlightSelected()

	if altairValues.playerlistUI.panelSize then
		playerlistPanel.Size = altairValues.playerlistUI.panelSize
	end

	self.selectedProfile.Visible = false
	self.selectedActions.Visible = false
	self.selectedProfile.Position = self.profileHiddenPosition
	self.selectedActions.Position = self.actionsHiddenPosition

	if self.teamList then
		self.teamList.Visible = false
		self.teamList.Position = self.teamHiddenPosition or self.teamPosition
	end

	if self.verticalDivider then
		self.verticalDivider.Visible = false
	end

	self.list.Position = self.listOnlyPosition
	self.list.Size = self.listOnlySize
	self.search.Position = self.searchOnlyPosition
	self.search.Size = self.searchOnlySize
end

altairValues.playerlistUI:init()

-- Selected player actions.
do
	local selectedActions = playerlistPanel.Interactions.SelectedActions

	local spectateAction = selectedActions:FindFirstChild("Spectate")
	local gotoAction = selectedActions:FindFirstChild("Teleport")
		or selectedActions:FindFirstChild("Goto")
	local trackAction = selectedActions:FindFirstChild("Track")
		or selectedActions:FindFirstChild("Bring")
	local profileAction = selectedActions:FindFirstChild("ViewProfile")

	if trackAction then
		altairValues.playerlistUI:_setObjectText(trackAction:FindFirstChild("Title", true), "Track")
	end

	local function selectedPlayer()
		return altairValues.playerlistUI.selectedPlayer
	end

	local function actionInteract(action)
		if not action then
			return nil
		end
		local interact = action:FindFirstChild("Interact")
		if interact and interact:IsA("GuiButton") then
			return interact
		end
		return nil
	end

	local function setToggleVisual(action, enabled)
		if not action then
			return
		end

		local activeColor = Color3.fromRGB(0, 152, 111)
		local idleColor = action:GetAttribute("AltairIdleBackground") or action.BackgroundColor3
		local icon = action:FindFirstChild("Icon", true)
		local stroke = action:FindFirstChildOfClass("UIStroke")
		local idleIcon = icon and (icon:GetAttribute("AltairIdleImageColor") or icon.ImageColor3)
		local idleStroke = stroke and (stroke:GetAttribute("AltairIdleStrokeColor") or stroke.Color)

		tweenService:Create(
			action,
			TweenInfo.new(0.4, Enum.EasingStyle.Quint),
			{ BackgroundColor3 = enabled and activeColor or idleColor }
		):Play()

		if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
			tweenService:Create(
				icon,
				TweenInfo.new(0.4, Enum.EasingStyle.Quint),
				{ ImageColor3 = enabled and Color3.fromRGB(220, 220, 220) or idleIcon }
			):Play()
		end

		if stroke then
			tweenService:Create(
				stroke,
				TweenInfo.new(0.4, Enum.EasingStyle.Quint),
				{ Color = enabled and activeColor or idleStroke }
			):Play()
		end
	end

	local spectateInteract = actionInteract(spectateAction)
	if spectateInteract then
		spectateInteract.MouseButton1Click:Connect(function()
			local player = selectedPlayer()
			if not player then
				return
			end

			local nowSpectating = toggleSpectate(player)
			setToggleVisual(spectateAction, nowSpectating == true)
		end)
	end

	local gotoInteract = actionInteract(gotoAction)
	if gotoInteract then
		gotoInteract.MouseButton1Click:Connect(function()
			local player = selectedPlayer()
			if not player then
				return
			end

			local success = teleportTo(player)
			if success then
				setToggleVisual(gotoAction, true)
				task.delay(0.5, function()
					if checkAltair() then
						setToggleVisual(gotoAction, false)
					end
				end)
			end
		end)
	end

	local trackInteract = actionInteract(trackAction)
	if trackInteract then
		trackInteract.MouseButton1Click:Connect(function()
			local player = selectedPlayer()
			if not player then
				return
			end

			locatedPlayers[player.Name] = not locatedPlayers[player.Name] or nil
			local nowTracking = locatedPlayers[player.Name] == true

			local highlight = espContainer:FindFirstChild(player.Name)
			if not highlight then
				createEsp(player)
				highlight = espContainer:FindFirstChild(player.Name)
			end

			if highlight then
				highlight.Adornee = player.Character
				highlight.Enabled = isHighlightEnabledFor(player.Name)
			end

			setToggleVisual(trackAction, nowTracking)
			Toast((nowTracking and "Now tracking " or "Stopped tracking ") .. player.DisplayName .. ".")
		end)
	end

	local profileInteract = actionInteract(profileAction)
	if profileInteract then
		profileInteract.MouseButton1Click:Connect(function()
			local player = selectedPlayer()
			if not player then
				return
			end

			local opened = pcall(function()
				guiService:InspectPlayerFromUserId(player.UserId)
			end)

			if not opened and originalSetClipboard then
				pcall(
					originalSetClipboard,
					"https://www.roblox.com/users/" .. tostring(player.UserId) .. "/profile"
				)
				Toast("Copied " .. player.DisplayName .. "'s profile link.")
			end
		end)
	end
end

function altairValues.playerlistUI:refreshRuntimePlayer(player, row)
	if not player or not row or not row.Parent or row:GetAttribute("AltairRuntimePlayer") ~= true then
		return
	end

	local revealAllowed = not self.rowsOpening

	row.Name = player.Name
	row:SetAttribute("AltairPlayerUserId", player.UserId)
	row:SetAttribute("AltairDisplayName", player.DisplayName)
	row:SetAttribute("AltairUsername", player.Name)
	row.Size = self.selectedPlayer
		and UDim2.fromOffset(221, 34)
		or UDim2.new(1, -26, 0, 34)

	for _, object in ipairs(row:GetDescendants()) do
		if object:IsA("UIStroke") then
			object.Enabled = true
			object.Thickness = 1
		end

		if object.Name == "DisplayName"
			and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
		then
			object.Text = tostring(player.DisplayName)
			object.Visible = true
			if revealAllowed then
				object.TextTransparency = 0
			end
			object:SetAttribute("AltairPlayerOpen_TextTransparency", 0)

		elseif object.Name == "Role"
			and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
		then
			object.Text = "In Server"
			object.Visible = true
			if revealAllowed then
				object.TextTransparency = 0.35
			end
			object:SetAttribute("AltairPlayerOpen_TextTransparency", 0.35)

		elseif object.Name == "Avatar"
			and (object:IsA("ImageLabel") or object:IsA("ImageButton"))
		then
			object.Visible = true
			if revealAllowed then
				object.ImageTransparency = 0
			end
			object.ImageColor3 = Color3.new(1, 1, 1)
			object:SetAttribute("AltairPlayerOpen_ImageTransparency", 0)
			object.Image = "rbxthumb://type=AvatarHeadShot&id="
				.. tostring(player.UserId)
				.. "&w=150&h=150"

		elseif object.Name == "StatusDot" and object:IsA("GuiObject") then
			object.Visible = true
			if object:IsA("Frame") then
				object.BackgroundColor3 = Color3.fromRGB(49, 214, 110)
				if revealAllowed then
					object.BackgroundTransparency = 0
				end
				object:SetAttribute("AltairPlayerOpen_BackgroundTransparency", 0)
			elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
				object.ImageColor3 = Color3.fromRGB(49, 214, 110)
				if revealAllowed then
					object.ImageTransparency = 0
				end
				object:SetAttribute("AltairPlayerOpen_ImageTransparency", 0)
			end
		end
	end

	self:requestRole(player, function(roleText)
		if not checkAltair()
			or not player.Parent
			or not row.Parent
			or tonumber(row:GetAttribute("AltairPlayerUserId")) ~= player.UserId
		then
			return
		end

		for _, object in ipairs(row:GetDescendants()) do
			if object.Name == "Role"
				and (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox"))
			then
				object.Text = roleText
				object.Visible = true
				if not self.rowsOpening then
					object.TextTransparency = 0.35
				end
				object:SetAttribute("AltairPlayerOpen_TextTransparency", 0.35)
			end
		end

		self:_applyProfileRole(player, roleText)
	end)

	if not settingValue("Rainbow Mode", false) and altairValues.applyPlayerlistBase then
		altairValues.applyPlayerlistBase(row)
	end

	if row:GetAttribute("AltairAvatarReady") == true then
		return
	end

	task.spawn(function()
		for _ = 1, 4 do
			if not checkAltair()
				or not player.Parent
				or not row.Parent
				or tonumber(row:GetAttribute("AltairPlayerUserId")) ~= player.UserId
			then
				return
			end

			local ok, content, ready = pcall(
				players.GetUserThumbnailAsync,
				players,
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)

			if ok and content then
				for _, object in ipairs(row:GetDescendants()) do
					if object.Name == "Avatar"
						and (object:IsA("ImageLabel") or object:IsA("ImageButton"))
					then
						object.Image = content
						object.Visible = true
						if not self.rowsOpening then
							object.ImageTransparency = 0
						end
						object.ImageColor3 = Color3.new(1, 1, 1)
						object:SetAttribute("AltairPlayerOpen_ImageTransparency", 0)
					end
				end

				if ready then
					row:SetAttribute("AltairAvatarReady", true)
					return
				end
			end

			task.wait(0.5)
		end
	end)
end

altairValues.playerConnections = altairValues.playerConnections or {}

local function disconnectPlayerConnections(player)
	local list = altairValues.playerConnections[player]
	if list then
		for _, connection in ipairs(list) do
			pcall(connection.Disconnect, connection)
		end
		altairValues.playerConnections[player] = nil
	end
end

local function addPlayerConnection(player, connection)
	altairValues.playerConnections[player] = altairValues.playerConnections[player] or {}
	table.insert(altairValues.playerConnections[player], connection)
	return connection
end

local function createPlayer(player)
	if not checkAltair() then
		return
	end

	for _, existing in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if existing:IsA("GuiObject")
			and existing:GetAttribute("AltairRuntimePlayer") == true
			and tonumber(existing:GetAttribute("AltairPlayerUserId")) == player.UserId
		then
			return
		end
	end

	local template = altairValues.playerlistUI.template
	if not template or not template.Parent then
		return
	end

	local newPlayer = template:Clone()
	newPlayer.Name = player.Name
	newPlayer:SetAttribute("AltairRuntimePlayer", true)
	newPlayer:SetAttribute("AltairPlayerUserId", player.UserId)
	newPlayer:SetAttribute("AltairDisplayName", player.DisplayName)
	newPlayer:SetAttribute("AltairUsername", player.Name)
	newPlayer.Size = altairValues.playerlistUI.selectedPlayer
		and UDim2.fromOffset(221, 34)
		or UDim2.new(1, -26, 0, 34)

	newPlayer:SetAttribute("AltairPlayerOpen_BackgroundTransparency", 0)

	for _, object in ipairs(newPlayer:GetDescendants()) do
		if object:IsA("UIStroke") then
			object.Enabled = true
			object.Thickness = 1
			object:SetAttribute("AltairPlayerOpen_Transparency", 0.12)
		else
			local properties = altairValues.transparencyProperties[object.ClassName]
			if properties then
				for _, property in ipairs(properties) do
					object:SetAttribute("AltairPlayerOpen_" .. property, object[property])
				end
			end
		end
	end

	newPlayer.Parent = playerlistPanel.Interactions.List
	newPlayer.Visible = not searchingForPlayer
	if altairValues.registerRainbowPlayerRow then
		altairValues.registerRainbowPlayerRow(newPlayer)
	end
	if altairValues.applyPlayerlistBase then altairValues.applyPlayerlistBase(newPlayer) end

	if playerlistPanel.Visible and newPlayer.Visible then
		newPlayer.BackgroundTransparency = 1

		for _, object in ipairs(newPlayer:GetDescendants()) do
			if object:IsA("UIStroke") then
				object.Transparency = 1
			elseif object.Name ~= "Interact" then
				local properties = altairValues.transparencyProperties[object.ClassName]
				if properties then
					for _, property in ipairs(properties) do
						if object:GetAttribute("AltairPlayerOpen_" .. property) ~= nil then
							object[property] = 1
						end
					end
				end
			end
		end

		tweenService:Create(
			newPlayer,
			TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }
		):Play()

		for _, object in ipairs(newPlayer:GetDescendants()) do
			if object:IsA("UIStroke") then
				tweenService:Create(
					object,
					TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Transparency = 0.12 }
				):Play()
			elseif object.Name ~= "Interact" then
				local properties = altairValues.transparencyProperties[object.ClassName]
				if properties then
					local goal = {}
					for _, property in ipairs(properties) do
						local stored = object:GetAttribute("AltairPlayerOpen_" .. property)
						if stored ~= nil then
							goal[property] = stored
						end
					end
					if next(goal) then
						tweenService:Create(
							object,
							TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
							goal
						):Play()
					end
				end
			end
		end
	else
		newPlayer.BackgroundTransparency = 0
		for _, object in ipairs(newPlayer:GetDescendants()) do
			if object:IsA("UIStroke") then
				object.Transparency = 0.12
			end
		end
	end

	local oldInteractions = newPlayer:FindFirstChild("PlayerInteractions")
	if oldInteractions then
		oldInteractions.Visible = false
	end
	local noActions = newPlayer:FindFirstChild("NoActions")
	if noActions and noActions:IsA("GuiObject") then
		noActions.Visible = false
	end

	altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
	sortPlayers()

	addPlayerConnection(player, player:GetPropertyChangedSignal("DisplayName"):Connect(function()
		if checkAltair() and newPlayer.Parent then
			altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
			sortPlayers()
		end
	end))

	addPlayerConnection(player, player.CharacterAdded:Connect(function()
		task.defer(function()
			if checkAltair() and newPlayer.Parent then
				altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
			end
		end)
	end))

	task.delay(0.2, function()
		if checkAltair() and player.Parent and newPlayer.Parent then
			altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
		end
	end)

	task.delay(1, function()
		if checkAltair() and player.Parent and newPlayer.Parent then
			altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
		end
	end)

	newPlayer.MouseEnter:Connect(function()
		if not debounce and playerlistPanel.Visible then
			altairValues.playerlistUI:_setPlayerRowHighlight(newPlayer, true)
		end
	end)

	newPlayer.MouseLeave:Connect(function()
		if not debounce then
			local selected = altairValues.playerlistUI.selectedPlayer
			local keepHighlighted = selected ~= nil and selected.UserId == player.UserId
			altairValues.playerlistUI:_setPlayerRowHighlight(newPlayer, keepHighlighted)
		end
	end)

	local interact = newPlayer:FindFirstChild("Interact")
	if interact and interact:IsA("GuiButton") then
		interact.MouseButton1Click:Connect(function()
			if debounce or not playerlistPanel.Visible then
				return
			end
			altairValues.playerlistUI:select(player)
		end)
	end
end

local function removePlayer(player)
	if not checkAltair() then
		return
	end

	if altairValues.playerlistUI.roleCache then
		altairValues.playerlistUI.roleCache[player.UserId] = nil
	end
	if altairValues.playerlistUI.roleLoading then
		altairValues.playerlistUI.roleLoading[player.UserId] = nil
	end
	if altairValues.playerlistUI.roleCallbacks then
		altairValues.playerlistUI.roleCallbacks[player.UserId] = nil
	end

	if altairValues.playerlistUI.selectedPlayer == player then
		altairValues.playerlistUI:reset(false)
	end

	for _, entry in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if entry:IsA("GuiObject")
			and entry:GetAttribute("AltairRuntimePlayer") == true
			and tonumber(entry:GetAttribute("AltairPlayerUserId")) == player.UserId
		then
			entry:Destroy()
			break
		end
	end
end

local function openSettings()
	if homeOpen then closeHome() end
	for _, panelName in ipairs({ "Character", "Scripts", "Playerlist" }) do
		local panel = UI:FindFirstChild(panelName)
		if panel and panel.Visible then
			closePanel(panelName, true)
			break
		end
	end
	debounce = true

	settingsPanel.BackgroundTransparency = 1
	settingsPanel.Title.TextTransparency = 1
	settingsPanel.Subtitle.TextTransparency = 1
	settingsPanel.Back.ImageTransparency = 1

	wipeTransparency(settingsPanel.SettingTypes, 1, true)

	settingsPanel.Visible = true
	settingsPanel.UIGradient.Enabled = true
	settingsPanel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	settingsPanel.UIGradient.Color =
		ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.0470588, 0.0470588, 0.0470588)), ColorSequenceKeypoint.new(1, Color3.new(0.0470588, 0.0470588, 0.0470588)) })
	settingsPanel.UIGradient.Offset = Vector2.new(0, 1.7)
	settingsPanel.SettingTypes.Visible = true
	settingsPanel.SettingLists.Visible = false
	settingsPanel.Size = UDim2.new(0, 550, 0, 340)
	settingsPanel.Title.Position = UDim2.new(0.045, 0, 0.057, 0)

	settingsPanel.Title.Text = "Settings"
	settingsPanel.Subtitle.Text = "Adjust your preferences, set new keybinds, test out new features and more."

	tweenService:Create(settingsPanel, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 613, 0, 384) }):Play()
	tweenService:Create(settingsPanel, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(settingsPanel.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

	task.wait(0.1)

	for _, settingType in ipairs(settingsPanel.SettingTypes:GetChildren()) do
		if settingType.ClassName == "Frame" then
			local gradientRotation = math.random(78, 95)

			tweenService:Create(settingType.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType.Shadow.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType.UIStroke.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(settingType.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
			tweenService:Create(settingType.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
			tweenService:Create(settingType.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()

			task.wait(0.02)
		end
	end

	for _, settingList in ipairs(settingsPanel.SettingLists:GetChildren()) do
		if settingList.ClassName == "ScrollingFrame" then
			for _, setting in ipairs(settingList:GetChildren()) do
				if setting.ClassName == "Frame" then
					setting.Visible = true
				end
			end
		end
	end

	debounce = false
end

closeSettings = function()
	debounce = true

	for _, settingType in ipairs(settingsPanel.SettingTypes:GetChildren()) do
		if settingType.ClassName == "Frame" then
			tweenService:Create(settingType, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(settingType.Shadow, TweenInfo.new(0.05, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			tweenService:Create(settingType.UIStroke, TweenInfo.new(0.05, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(settingType.Title, TweenInfo.new(0.05, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		end
	end

	tweenService:Create(settingsPanel.Back, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
	tweenService:Create(settingsPanel.Title, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	tweenService:Create(settingsPanel.Subtitle, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()

	for _, settingList in ipairs(settingsPanel.SettingLists:GetChildren()) do
		if settingList.ClassName == "ScrollingFrame" then
			for _, setting in ipairs(settingList:GetChildren()) do
				if setting.ClassName == "Frame" then
					setting.Visible = false
				end
			end
		end
	end

	tweenService:Create(settingsPanel, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 520, 0, 0) }):Play()
	tweenService:Create(settingsPanel, TweenInfo.new(0.55, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()

	task.wait(0.55)

	settingsPanel.Visible = false
	debounce = false
end

local function settingsPath()
	return altairValues.altairFolder .. "/" .. altairValues.settingsFile
end

-- Keep a validated recovery copy; executor file APIs do not promise atomic writes.
altairValues.settingsStore = { status = "Not loaded" }
function altairValues.settingsStore:read(path)
	if type(readfile) ~= "function" then return nil end
	local ok, raw = pcall(readfile, path)
	if not ok or type(raw) ~= "string" or #raw > 256 * 1024 then return nil end
	local decoded, value = pcall(httpService.JSONDecode, httpService, raw)
	if not decoded or type(value) ~= "table" then return nil end
	return value, raw
end

function altairValues.settingsStore:load()
	local value, raw = self:read(settingsPath())
	if value then self.lastGood = raw; self.status = "Loaded"; return value end
	value, raw = self:read(settingsPath() .. ".backup")
	if value then
		self.lastGood = raw; self.recovered = true; self.status = "Recovered backup"
		warn("Altair | Recovered settings from the backup copy.")
		return value
	end
	self.status = type(writefile) == "function" and "Defaults" or "Session only"
	return nil
end

function altairValues.settingsStore:write(encoded)
	if type(writefile) ~= "function" then self.status = "Session only"; return false end
	if self.writing then self.pending = encoded; return false end
	if encoded == self.lastGood and not self.recovered then return true end
	self.writing = true
	local ok, problem = pcall(function()
		checkFolder()
		-- Never replace a good backup with unreadable primary data.
		writefile(settingsPath() .. ".backup", self.lastGood or encoded)
		if type(readfile) == "function" then
			assert(readfile(settingsPath() .. ".backup") == (self.lastGood or encoded), "Backup verification failed")
		end
		writefile(settingsPath(), encoded)
		if type(readfile) == "function" then assert(readfile(settingsPath()) == encoded, "Settings verification failed") end
	end)
	if self.pending then
		task.defer(function()
			local pending = self.pending; self.pending = nil; self.writing = false
			self:write(pending)
		end)
	else self.writing = false end
	if ok then self.lastGood = encoded; self.recovered = false; self.status = "Saved"; return true end
	self.status = "Save failed"
	if not self.warnedAt or os.clock() - self.warnedAt >= 30 then
		self.warnedAt = os.clock()
		warn("Altair | Settings could not be saved: " .. tostring(problem))
		queueNotification("Settings not saved", "Your changes still work this session, but could not be saved to disk. Altair kept its recovery copy.", 4370336704)
	end
	return false
end
local function saveSettings()
	if not writefile then
		return
	end


	local flat = {}
	for _, category in ipairs(altairSettings) do
		for _, setting in ipairs(category.categorySettings) do
			if setting.persistent ~= false and setting.current ~= nil then
				flat[setting.id] = setting.current
			end
		end
	end

	local encodeSuccess, encoded = pcall(httpService.JSONEncode, httpService, flat)
	if not encodeSuccess then
		warn("Altair | Unable to encode settings: " .. tostring(encoded))
		return
	end

	altairValues.settingsStore:write(encoded)
end

local function assembleSettings()
	do
		local stored = altairValues.settingsStore:load()
		if type(stored) == "table" then
			for _, category in ipairs(altairSettings) do
				for _, setting in ipairs(category.categorySettings) do
					if setting.persistent == false then continue end
					local value = stored[setting.id]

					if value == nil and stored[1] then
						for _, storedCategory in ipairs(stored) do
							if type(storedCategory) == "table" and type(storedCategory.categorySettings) == "table" then
								for _, storedSetting in ipairs(storedCategory.categorySettings) do
									if storedSetting.id == setting.id then
										value = storedSetting.current
										break
									end
								end
							end
						end
					end

					if value ~= nil and (setting.current == nil or typeof(value) == typeof(setting.current)) then
						setting.current = value
					end
				end
			end
		end
	end

	saveSettings() -- write back, picking up any settings added since the file was created

	local function licenseLocked(tier)
		return (tier == "Pro" and not Pro) or (tier == "Essential" and not (Pro or Essential))
	end

	local function denyLocked(setting)
		local tier = setting.minimumLicense
		if not licenseLocked(tier) then return false end
		queueNotification("This feature is locked", "You must be " .. tier .. " or higher to use " .. setting.name .. ". ", 4483345875)
		return true
	end

	local function bindInputResize(item, box)
		item.InputFrame.Size = UDim2.new(0, box.TextBounds.X + 24, 0, 30)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			tweenService:Create(item.InputFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, box.TextBounds.X + 24, 0, 30),
			}):Play()
		end)
	end

	local function makeValueInput(list, setting, placeholder)
		local item = settingsPanel.SettingLists.Template.InputTemplate:Clone()
		local box = item.InputFrame.InputBox
		item.Name, item.Parent, item.Visible = setting.name, list, true
		item.Title.Text = setting.name
		box.PlaceholderText = setting.placeholder or placeholder
		box.Text, box.TextWrapped = truncateForDisplay(setting.current), false
		bindInputResize(item, box)
		box.Focused:Connect(function() box.Text = tostring(setting.current) end)
		return item, box
	end

	settingsPanel.Back.MouseButton1Click:Connect(function()
		tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {
			ImageTransparency = 1,
			Position = UDim2.new(0.002, 0, 0.052, 0),
		}):Play()
		tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.045, 0, 0.057, 0) }):Play()
		tweenService:Create(settingsPanel.UIGradient, TweenInfo.new(1, Enum.EasingStyle.Exponential), { Offset = Vector2.new(0, 1.3) }):Play()
		settingsPanel.Title.Text = "Settings"
		settingsPanel.Subtitle.Text = "Adjust your preferences, set new keybinds, test out new features and more"
		settingsPanel.SettingTypes.Visible = true
		settingsPanel.SettingLists.Visible = false
	end)

	for _, category in altairSettings do
		if category.hidden then continue end
		local newCategory = settingsPanel.SettingTypes.Template:Clone()
		newCategory.Name = category.name
		newCategory.Title.Text = string.upper(category.name)
		newCategory.Parent = settingsPanel.SettingTypes
		newCategory.UIGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.0392157, 0.0392157, 0.0392157)), ColorSequenceKeypoint.new(1, category.color) })

		newCategory.Visible = true

		local hue, sat, val = Color3.toHSV(category.color)

		hue = math.clamp(hue + 0.01, 0, 1)
		sat = math.clamp(sat + 0.1, 0, 1)
		val = math.clamp(val + 0.2, 0, 1)

		local newColor = Color3.fromHSV(hue, sat, val)
		newCategory.UIStroke.UIGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.117647, 0.117647, 0.117647)), ColorSequenceKeypoint.new(1, newColor) })
		newCategory.Shadow.UIGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.117647, 0.117647, 0.117647)), ColorSequenceKeypoint.new(1, newColor) })

		local newList = settingsPanel.SettingLists.Template:Clone()
		newList.Name = category.name
		newList.Parent = settingsPanel.SettingLists

		newList.Visible = true

		for _, obj in ipairs(newList:GetChildren()) do
			if obj.Name ~= "Placeholder" and obj.Name ~= "UIListLayout" then
				obj:Destroy()
			end
		end

		newCategory.Interact.MouseButton1Click:Connect(function()
			if settingsPanel.SettingLists:FindFirstChild(category.name) then
				settingsPanel.UIGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.0470588, 0.0470588, 0.0470588)), ColorSequenceKeypoint.new(1, category.color) })
				settingsPanel.SettingTypes.Visible = false
				settingsPanel.SettingLists.Visible = true
				settingsPanel.SettingLists.UIPageLayout:JumpTo(settingsPanel.SettingLists[category.name])
				settingsPanel.Subtitle.Text = category.description
				settingsPanel.Back.Visible = true
				settingsPanel.Title.Text = category.name

				local gradientRotation = math.random(78, 95)
				settingsPanel.UIGradient.Rotation = gradientRotation
				tweenService:Create(settingsPanel.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { Offset = Vector2.new(0, 0.65) }):Play()
				tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
				tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.041, 0, 0.052, 0) }):Play()
				tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.091, 0, 0.057, 0) }):Play()
			else
				closeSettings()
			end
		end)

		newCategory.MouseEnter:Connect(function()
			tweenService:Create(newCategory.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
			tweenService:Create(newCategory.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.4) }):Play()
			tweenService:Create(newCategory.UIStroke.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.2) }):Play()
			tweenService:Create(newCategory.Shadow.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.2) }):Play()
		end)

		newCategory.MouseLeave:Connect(function()
			tweenService:Create(newCategory.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()
			tweenService:Create(newCategory.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.65) }):Play()
			tweenService:Create(newCategory.UIStroke.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.4) }):Play()
			tweenService:Create(newCategory.Shadow.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.4) }):Play()
		end)

		for _, setting in ipairs(category.categorySettings) do
			if not setting.hidden then
				local settingType = setting.settingType
				local minimumLicense = setting.minimumLicense
				local object

				if settingType == "Boolean" then
					local newSwitch = settingsPanel.SettingLists.Template.SwitchTemplate:Clone()
					object = newSwitch
					setting._uiObject = newSwitch
					newSwitch.Name = setting.name
					newSwitch.Parent = newList
					newSwitch.Visible = true
					newSwitch.Title.Text = setting.name

					if setting.current then
						newSwitch.Switch.Indicator.Position = UDim2.new(1, -20, 0.5, 0)
						newSwitch.Switch.Indicator.UIStroke.Color = Color3.fromRGB(220, 220, 220)
						newSwitch.Switch.Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						newSwitch.Switch.Indicator.BackgroundTransparency = 0.6
					end

					if licenseLocked(minimumLicense) then
						newSwitch.Switch.Indicator.Position = UDim2.new(1, -40, 0.5, 0)
						newSwitch.Switch.Indicator.UIStroke.Color = Color3.fromRGB(255, 255, 255)
						newSwitch.Switch.Indicator.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
						newSwitch.Switch.Indicator.BackgroundTransparency = 0.75
					end

					newSwitch.Interact.MouseButton1Click:Connect(function()
						if denyLocked(setting) then return end

						local previousValue = setting.current
						setting.current = not setting.current
						altairValues.activity:record("Setting changed", setting.name .. (setting.current and " · Enabled" or " · Disabled"))
						saveSettings()
						if type(setting.onChanged) == "function" then
							task.spawn(setting.onChanged, setting.current, previousValue)
						end

						local enabled = setting.current
						local indicator = newSwitch.Switch.Indicator
						Toast(setting.name .. (enabled and " has been enabled." or " has been disabled."))
						tweenService:Create(indicator, TweenInfo.new(enabled and 0.5 or 0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
							Position = UDim2.new(1, enabled and -20 or -40, 0.5, 0),
						}):Play()
						tweenService:Create(indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
							Size = UDim2.new(0, 12, 0, 12),
						}):Play()
						tweenService:Create(indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
							Color = enabled and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(255, 255, 255),
							Transparency = enabled and 0.5 or 0.7,
						}):Play()
						tweenService:Create(indicator, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
							BackgroundColor3 = enabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(235, 235, 235),
						}):Play()
						tweenService:Create(indicator, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
							BackgroundTransparency = enabled and 0.6 or 0.75,
						}):Play()
						task.wait(0.05)
						tweenService:Create(indicator, TweenInfo.new(enabled and 0.45 or 0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
							Size = UDim2.new(0, 17, 0, 17),
						}):Play()
					end)
				elseif settingType == "Input" then
					local newInput, box = makeValueInput(newList, setting, "input")
					object = newInput

					box.FocusLost:Connect(function()
						if denyLocked(setting) then
							box.Text = truncateForDisplay(setting.current)
							return
						end
						if box.Text ~= "" then
							setting.current = box.Text
							saveSettings()
						end
						box.Text = truncateForDisplay(setting.current)
					end)
				elseif settingType == "Number" then
					local newInput, box = makeValueInput(newList, setting, "number")
					object = newInput

					box.FocusLost:Connect(function()
						if denyLocked(setting) then
							box.Text = truncateForDisplay(setting.current)
							return
						end

						local inputValue = tonumber(box.Text)
						if inputValue then
							local oldValue = setting.current
							local nextValue = setting.values and math.clamp(inputValue, setting.values[1], setting.values[2]) or inputValue
							if nextValue ~= oldValue then
								setting.current = nextValue
								saveSettings()
								if type(setting.onChanged) == "function" then
									task.spawn(setting.onChanged, nextValue, oldValue)
								end
								Toast(setting.name .. " set to " .. tostring(nextValue), category.color)
							end
						end
						box.Text = truncateForDisplay(setting.current)
					end)
				elseif settingType == "Key" then
					local newKeybind = settingsPanel.SettingLists.Template.InputTemplate:Clone()
					object = newKeybind
					newKeybind.Name = setting.name
					newKeybind.InputFrame.InputBox.PlaceholderText = setting.placeholder or "listening.."
					newKeybind.InputFrame.InputBox.Text = setting.current or "No Keybind"
					newKeybind.Parent = newList

					newKeybind.Visible = true
					newKeybind.Title.Text = setting.name
					newKeybind.InputFrame.InputBox.TextWrapped = false
					bindInputResize(newKeybind, newKeybind.InputFrame.InputBox)

					newKeybind.InputFrame.InputBox.FocusLost:Connect(function()
						local capture = checkingForKey
						local ownsCapture = capture and capture.object == newKeybind
						if ownsCapture then
							checkingForKey = nil
						end

						if denyLocked(setting) then
							newKeybind.InputFrame.InputBox.Text = setting.current or "No Keybind"
							return
						end

						if newKeybind.InputFrame.InputBox.Text == nil or newKeybind.InputFrame.InputBox.Text == "" then
							setting.current = ownsCapture and capture.previous or setting.current
							newKeybind.InputFrame.InputBox.Text = setting.current or "No Keybind"
						end
					end)

					newKeybind.InputFrame.InputBox.Focused:Connect(function()
						checkingForKey = { data = setting, object = newKeybind, previous = setting.current }
						newKeybind.InputFrame.InputBox.Text = ""
					end)

				end

				if object then
					if setting.description then
						object.Description.Visible = true
						object.Description.TextWrapped = true
						object.Description.Size = UDim2.new(0, 333, 0, 999)
						object.Description.Text = setting.description
						object.Description.Size = UDim2.new(0, 333, 0, object.Description.TextBounds.Y + 10)
						object.Size = UDim2.new(0, 558, 0, object.Description.TextBounds.Y + 44)
					end

					if minimumLicense then
						object.LicenseDisplay.Visible = true
						object.Title.Position = UDim2.new(0, 18, 0, 26)
						object.Description.Position = UDim2.new(0, 18, 0, 43)
						object.Size = UDim2.new(0, 558, 0, object.Size.Y.Offset + 13)
						object.LicenseDisplay.Text = string.upper(minimumLicense) .. " FEATURE"
					end

					local objectTouching
					object.MouseEnter:Connect(function()
						objectTouching = true
						tweenService:Create(object.UIStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.45 }):Play()
						tweenService:Create(object, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.83 }):Play()
					end)

					object.MouseLeave:Connect(function()
						objectTouching = false
						tweenService:Create(object.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.6 }):Play()
						tweenService:Create(object, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.9 }):Play()
					end)

					if object:FindFirstChild("Interact") then
						object.Interact.MouseButton1Click:Connect(function()
							tweenService:Create(object.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
							tweenService:Create(object, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.8 }):Play()
							task.wait(0.1)
							if objectTouching then
								tweenService:Create(object.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.45 }):Play()
								tweenService:Create(object, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.83 }):Play()
							else
								tweenService:Create(object.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.6 }):Play()
								tweenService:Create(object, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.9 }):Play()
							end
						end)
					end
				end
			end
		end
	end
end

local function initialiseAntiKick()
	if not settingValue("Client-Based Anti Kick") then
		return
	end
	if not (hookMetamethod and optional(getnamecallmethod)) then
		return
	end

	if env.altairAntiKickInstalled then
		return
	end
	env.altairAntiKickInstalled = true

	local hookSuccess, hookError = pcall(function()
		local originalIndex
		local originalNamecall

		originalIndex = hookMetamethod(game, "__index", function(self, method)
			if self == localPlayer and type(method) == "string" and method:lower() == "kick" and settingValue("Client-Based Anti Kick") and checkAltair() then
				queueNotification("Kick Prevented", "Altair has prevented you from being kicked by the client.", 4400699701)
				return error("Expected ':' not '.' calling member function Kick", 2)
			end
			return originalIndex(self, method)
		end)

		originalNamecall = hookMetamethod(game, "__namecall", function(self, ...)
			if self == localPlayer and getnamecallmethod():lower() == "kick" and settingValue("Client-Based Anti Kick") and checkAltair() then
				queueNotification("Kick Prevented", "Altair has prevented you from being kicked by the client.", 4400699701)
				return
			end
			return originalNamecall(self, ...)
		end)
	end)

	if not hookSuccess then
		env.altairAntiKickInstalled = nil
		warn("Altair | Anti Kick could not be installed on this executor: " .. tostring(hookError))
	end
end

local developerTools = (function()
	local candidates = {
		altairValues.altairFolder .. "/Developer/AltairDevTools.lua",
		altairValues.altairFolder .. "/AltairDevTools.lua",
		"AltairDevTools.lua",
	}
	local activeService
	local generation = 0
	local observers = env.__ALTAIR_DEBUG_OBSERVERS
	if type(observers) ~= "table" then
		observers = setmetatable({}, { __mode = "k" })
		env.__ALTAIR_DEBUG_OBSERVERS = observers
	end

	local controller = {}
	local stateSink
	local configProvider

	function controller:IsAvailable()
		if type(env.__ALTAIR_DEVTOOLS_SOURCE) == "string" and env.__ALTAIR_DEVTOOLS_SOURCE ~= "" then
			return type(loadstring) == "function"
		end
		if type(isfile) ~= "function" or type(loadfile) ~= "function" then return false end
		for _, path in ipairs(candidates) do
			local ok, exists = pcall(isfile, path)
			if ok and exists then return true end
		end
		return false
	end

	function controller:PublishDebugState(enabled, details)
		for callback in pairs(observers) do
			task.defer(function()
				local ok, err = pcall(callback, enabled == true, details)
				if not ok then warn("Altair | Debug observer failed: " .. tostring(err)) end
			end)
		end
	end

	function controller:Observe(callback)
		if type(callback) ~= "function" then return nil end
		observers[callback] = true
		local connection = { Connected = true }
		function connection:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			observers[callback] = nil
		end
		task.defer(function()
			if connection.Connected then
				pcall(callback, settingValue("Debug Mode", false) == true and activeService ~= nil, { reason = "subscribe" })
			end
		end)
		return connection
	end

	function controller:SetStateSink(callback)
		stateSink = type(callback) == "function" and callback or nil
	end

	function controller:SetConfigProvider(callback)
		configProvider = type(callback) == "function" and callback or nil
	end

	local function compilePackage()
		if type(env.__ALTAIR_DEVTOOLS_SOURCE) == "string" and env.__ALTAIR_DEVTOOLS_SOURCE ~= "" then
			if type(loadstring) ~= "function" then
				return nil, "Volt loadstring is unavailable for the developer source override", "getgenv().__ALTAIR_DEVTOOLS_SOURCE"
			end
			local chunk, compileError = loadstring(env.__ALTAIR_DEVTOOLS_SOURCE, "@AltairDevTools")
			return chunk, compileError, "getgenv().__ALTAIR_DEVTOOLS_SOURCE"
		end

		if type(isfile) ~= "function" or type(loadfile) ~= "function" then
			return nil, "Volt isfile/loadfile APIs are unavailable", nil
		end

		for _, path in ipairs(candidates) do
			local okExists, exists = pcall(isfile, path)
			if okExists and exists then
				local okLoad, chunk, compileError = pcall(loadfile, path)
				if not okLoad then
					return nil, tostring(chunk), path
				end
				if type(chunk) ~= "function" then
					return nil, tostring(compileError or "Volt loadfile returned no compiled chunk"), path
				end
				return chunk, nil, path
			end
		end

		return nil, "Altair/Developer/AltairDevTools.lua was not found", nil
	end

	function controller:Stop(reason)
		local service = activeService
			or env.__ALTAIR_DEVTOOLS_SERVICE
			or (type(env.Altair) == "table" and env.Altair.Dev)

		activeService = nil
		if type(service) == "table" and type(service.Destroy) == "function" then
			pcall(service.Destroy, service, reason or "debug-disabled")
		end

		if type(env.Altair) == "table" and env.Altair.Dev == service then
			env.Altair.Dev = nil
		end
		if env.__ALTAIR_DEVTOOLS_SERVICE == service then
			env.__ALTAIR_DEVTOOLS_SERVICE = nil
		end
	end

	function controller:Start(expectedGeneration)
		if activeService and type(activeService.GetStatus) == "function" then
			return true
		end

		local chunk, compileError, sourceName = compilePackage()
		if not chunk then
			local title = sourceName and "Developer Tools failed to compile" or "Developer Tools unavailable"
			local suffix = sourceName and "" or ". Place AltairDevTools.lua in Altair/Developer and try again."
			queueNotification(title, tostring(compileError) .. suffix, 4483345875)
			return false, compileError
		end

		local okChunk, bootstrap = pcall(chunk)
		if not okChunk then
			queueNotification("Developer Tools failed to load", tostring(bootstrap), 4483345875)
			return false, bootstrap
		end
		if type(bootstrap) ~= "function" then
			queueNotification("Developer Tools invalid", "AltairDevTools.lua did not return a bootstrap function.", 4483345875)
			return false, "invalid developer tools package"
		end

		local initialConfig
		if configProvider then
			local okConfig, value = pcall(configProvider)
			if okConfig and type(value) == "table" then initialConfig = value end
		end

		local okStart, service = pcall(bootstrap, {
			Altair = env.Altair,
			RootFolder = altairValues.altairFolder,
			Version = altairValues.altairVersion,
			Source = sourceName,
			Config = initialConfig,
			StateChanged = stateSink,
		})
		if not okStart or type(service) ~= "table" then
			queueNotification("Developer Tools failed to start", tostring(service), 4483345875)
			return false, service
		end

		if expectedGeneration ~= generation or settingValue("Debug Mode", false) ~= true then
			if type(service.Destroy) == "function" then
				pcall(service.Destroy, service, "stale-startup")
			end
			return false, "developer tools startup was superseded"
		end

		activeService = service
		return true, service
	end

	function controller:Sync(enabled)
		if enabled == nil then
			enabled = settingValue("Debug Mode", false) == true
		end

		generation += 1
		local currentGeneration = generation

		if enabled then
			self:Stop("replaced")
			local ok, serviceOrError = self:Start(currentGeneration)
			self:PublishDebugState(ok == true, { reason = ok and "enabled" or "start-failed", detail = serviceOrError })
			return ok, serviceOrError
		end

		self:Stop("debug-disabled")
		self:PublishDebugState(false, { reason = "disabled" })
		return true
	end

	return controller
end)()

local altairAPI = {}
altairValues.lifecycle.api = altairAPI
altairAPI.Unload = function() altairValues.lifecycle:unload() end
altairAPI.Destroy = altairAPI.Unload

altairAPI.Toast = Toast
altairAPI.QueueNotification = queueNotification
altairAPI.Notify = queueNotification
altairAPI.BlinkSmartBar = BlinkSmartBar
altairAPI.SupportsColoredSmartBarBlink = true
altairAPI.SupportsQueuedSmartBarBlink = true
altairAPI.ToastSupportsSkipBlink = true
altairAPI.SetSmartBarPersistentColor = function(color)
	blinkState.persistentColor = typeof(color) == "Color3" and color or nil
	local activeColor = blinkState.color or blinkState.persistentColor
	if not activeColor then
		if settingValue("Rainbow Mode", false) then
			activeColor = Color3.fromHSV((os.clock() / 8) % 1, 0.65, 0.8)
		else
			activeColor = Color3.new(1, 1, 1)
		end
	end
	for _, object in ipairs({ UI.SmartBar.Shadow, UI.SmartBar.CircleGradient, UI.SmartBar.UIStroke, UI.SmartBar.Back.UIStroke }) do
		if object and object.Parent then
			if object:IsA("UIStroke") then object.Color = activeColor else object.ImageColor3 = activeColor end
		end
	end
end

altairAPI.OpenSmartBar = openSmartBar
altairAPI.CloseSmartBar = closeSmartBar
altairAPI.OpenPanel = openPanel
altairAPI.ClosePanel = closePanel
altairAPI.OpenScriptSearch = openScriptSearch
altairAPI.SearchScripts = searchScriptBlox

altairAPI.Rejoin = rejoin
altairAPI.ServerHop = serverhop
altairAPI.LeaveExperience = leaveExperience
altairAPI.TeleportToPlayer = teleportTo
altairAPI.ToggleSpectate = toggleSpectate
altairAPI.CreateESP = createEsp

altairAPI.GetRuntimeHealth = function()
	local network = altairValues.searchTransport
	return {
		searchRequests = network.active, searchCacheHits = network.hits, searchCacheBytes = network.bytes,
		searchCooldown = math.max(0, network.cooldown - os.clock()),
		settings = altairValues.settingsStore.status, activeToasts = #activeToasts,
		viewportRecoveries = altairValues.smartBarLayout.viewportReflows or 0,
	}
end

altairAPI.GetPing = getPing
altairAPI.GetSetting = settingValue
-- Name-based integrations can recognize the local player without comparing only
-- the anonymized label. A preserved source wins over alias guesses.
altairAPI.IsLocalPlayerName = function(value, textObject)
	local function normalize(name)
		if type(name) ~= "string" then return nil end
		return name:match("^%s*(.-)%s*$"):gsub("^@", ""):lower()
	end
	local function actualMatch(name)
		return name == localPlayer.Name:lower() or name == localPlayer.DisplayName:lower()
	end
	if typeof(textObject) == "Instance" and originalTextValues[textObject]
		and altairValues.anonymousMaskedText
		and textObject.Text == altairValues.anonymousMaskedText[textObject] then
		return actualMatch(normalize(originalTextValues[textObject]))
	end
	local name = normalize(value)
	if not name or name == "" then return false end
	if actualMatch(name) then return true end
	if not settingValue("Anonymous Client") then return false end
	for _, player in ipairs(players:GetPlayers()) do
		if player ~= localPlayer and (name == player.Name:lower() or name == player.DisplayName:lower()) then
			return false
		end
	end
	return name == randomUsername:lower() or name == randomDisplayName:lower()
end
altairAPI.SaveSettings = saveSettings
altairAPI.UpdateHome = UpdateHome
altairAPI.IsLoaded = checkAltair

altairAPI.GetUI = function()
	return UI
end

altairAPI.GetSmartBar = function()
	return smartBar
end

altairAPI.GetDetectedScript = function()
	return altairValues.detectedScript
end
altairAPI.ScanCustomScripts = altairValues.scanCustomScripts
altairAPI.OpenCustomScriptImporter = altairValues.openCustomScriptPrompt
altairAPI.SaveCustomScriptImporter = altairValues.saveCustomScriptPrompt
altairAPI.RepromptCustomScript = function()
	local detected = altairValues.detectedScript or altairValues.scanCustomScripts()
	if detected then
		return altairValues.showGameDetection(detected)
	end
	Toast("No custom script was detected for this experience.")
	return false
end

altairAPI.DebugContractVersion = 2

altairAPI.DebugEnabled = function()
	local dev = type(env.Altair) == "table" and env.Altair.Dev or nil
	return settingValue("Debug Mode", false) == true
		and type(dev) == "table"
		and dev._destroyed ~= true
end

altairAPI.GetDebugClient = function(name, provider, metadata)
	if not altairAPI.DebugEnabled() then return nil end
	local dev = env.Altair.Dev
	if type(dev.CreateClient) ~= "function" then return nil end
	local ok, client = pcall(dev.CreateClient, dev, name, provider, metadata)
	return ok and client or nil
end

altairAPI.OnDebugChanged = function(callback)
	return developerTools:Observe(callback)
end

altairAPI.RecordActivity = function(title, description)
	return altairValues.activity:record(title, description)
end
altairAPI.Version = altairValues.altairVersion
env.Altair = altairAPI

altairValues.continuation = { quiet = false, key = "Altair.Session.v1" }
do
	local session = altairValues.continuation
	local ok, marker = pcall(teleportService.GetTeleportSetting, teleportService, session.key)
	local recent = ok and type(marker) == "table" and marker.universe == game.GameId
		and type(marker.at) == "number" and os.time() - marker.at >= 0 and os.time() - marker.at < 600
	if recent then
		session.quiet = marker.arrivedJob == jobId or (type(marker.fromJob) == "string" and marker.fromJob ~= jobId)
		if session.quiet and type(marker.open) == "boolean" then session.open = marker.open end
	end
	local function mark(arriving)
		pcall(teleportService.SetTeleportSetting, teleportService, session.key, {
			universe = game.GameId, fromJob = jobId, arrivedJob = arriving and jobId or "",
			at = os.time(), open = smartBarOpen,
		})
	end
	session.mark = mark
	mark(true)
	local teleportPending = false
	local function teleportFailed()
		if teleportPending then altairValues.activity:record("Teleport failed", "Still in the current server") end
		teleportPending = false
		mark(true)
	end
	track(localPlayer.OnTeleport:Connect(function(teleportState)
		if teleportState == Enum.TeleportState.Failed then teleportFailed(); return end
		if teleportState == Enum.TeleportState.Started or teleportState == Enum.TeleportState.InProgress then
			if not teleportPending then
				teleportPending = true
				altairValues.activity:record("Teleport started", "Leaving the current server")
			end
			altairValues.activity:save()
			altairValues.smartBarLayout:savePosition()
			mark(false)
		end
	end))
	track(teleportService.TeleportInitFailed:Connect(function(player)
		if player == localPlayer then teleportFailed() end
	end))
end

local function start()
	if altairValues.releaseType == "Experimental" then -- Make this more secure.
		if not Pro then
			localPlayer:Kick("This is an experimental release, you must be Pro to run this. ")
			return
		end
	end
	windowFocusChanged(true)

	local developerAvailable = developerTools:IsAvailable()
	local developerCategory
	for _, category in ipairs(altairSettings) do
		if category.name == "Developer" then
			developerCategory = category
			category.hidden = not developerAvailable
			break
		end
	end

	assembleSettings()

	local function syncDeveloperBoolean(name, value)
		local setting = checkSetting(name, "Developer")
		if not setting then return end
		setting.current = value == true
		local switch = setting._uiObject
		local indicator = switch and switch:FindFirstChild("Switch") and switch.Switch:FindFirstChild("Indicator")
		if not indicator then return end
		if setting.current then
			indicator.Position = UDim2.new(1, -20, 0.5, 0)
			indicator.UIStroke.Color = Color3.fromRGB(220, 220, 220)
			indicator.UIStroke.Transparency = 0.5
			indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			indicator.BackgroundTransparency = 0.6
		else
			indicator.Position = UDim2.new(1, -40, 0.5, 0)
			indicator.UIStroke.Color = Color3.fromRGB(255, 255, 255)
			indicator.UIStroke.Transparency = 0.7
			indicator.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
			indicator.BackgroundTransparency = 0.75
		end
	end

	local function setDeveloperSettingVisible(name, visible)
		local setting = checkSetting(name, "Developer")
		if not setting then return end
		setting.runtimeHidden = not visible
		local object = setting._uiObject
		if object then object.Visible = visible == true end
	end

	local function syncMcpControls(connected)
		setDeveloperSettingVisible("MCP Auto-Connect", connected)
		setDeveloperSettingVisible("Stream Observation Events", connected)
	end

	syncMcpControls(false)

	local legacyCapacity = checkSetting("Event Buffer Capacity", "Developer")
	if legacyCapacity and tonumber(legacyCapacity.current) == 5000 then
		legacyCapacity.current = 30000
		saveSettings()
	end

	developerTools:SetConfigProvider(function()
		return {
			Bridge = { AutoConnect = settingValue("MCP Auto-Connect", true) == true },
			Recorder = {
				StreamEvents = settingValue("Stream Observation Events", false) == true,
				SampleHz = settingValue("Recording Sample Rate", 8),
				EventCapacity = settingValue("Event Buffer Capacity", 30000),
			},
		}
	end)

	developerTools:SetStateSink(function(state, value, details)
		if state == "recording" then
			syncDeveloperBoolean("Record Session", value == true)
		elseif state == "bridge" then
			syncMcpControls(value == true)
		end
	end)

	local debugSetting = checkSetting("Debug Mode", "Developer")
	local recordSetting = checkSetting("Record Session", "Developer")
	local selfTestSetting = checkSetting("Run Self-Test", "Developer")
	local mcpSetting = checkSetting("MCP Auto-Connect", "Developer")
	local streamSetting = checkSetting("Stream Observation Events", "Developer")
	local sampleSetting = checkSetting("Recording Sample Rate", "Developer")
	local capacitySetting = checkSetting("Event Buffer Capacity", "Developer")

	local function configureDeveloperTools(patch)
		local dev = type(env.Altair) == "table" and env.Altair.Dev or nil
		if type(dev) == "table" and type(dev.Configure) == "function" then
			local ok, err = pcall(dev.Configure, dev, patch)
			if not ok then warn("Altair | Developer Tools configuration failed: " .. tostring(err)) end
		end
	end

	if debugSetting then
		debugSetting.onChanged = function()
			local enabled = developerAvailable and settingValue("Debug Mode", false) == true
			altairAPI.SetSmartBarPersistentColor(enabled and Color3.fromRGB(126, 104, 220) or nil)
			if enabled then
				syncDeveloperBoolean("MCP Auto-Connect", true)
			else
				syncDeveloperBoolean("Record Session", false)
				syncMcpControls(false)
			end
			developerTools:Sync(enabled)
		end
	end

	if recordSetting then
		recordSetting.onChanged = function(enabled)
			local dev = type(env.Altair) == "table" and env.Altair.Dev or nil
			if enabled then
				if not settingValue("Debug Mode", false) or type(dev) ~= "table" or type(dev.StartCapture) ~= "function" then
					syncDeveloperBoolean("Record Session", false)
					Toast("Enable Debug Mode before starting a recording.", Color3.fromRGB(126, 104, 220))
					return
				end
				local ok, err = pcall(dev.StartCapture, dev)
				if not ok then
					syncDeveloperBoolean("Record Session", false)
					queueNotification("Recording failed", tostring(err), 4483345875)
				end
			elseif type(dev) == "table" and type(dev.FinishCapture) == "function" then
				local ok, result = pcall(dev.FinishCapture, dev)
				if not ok then queueNotification("Recording export failed", tostring(result), 4483345875) end
			end
		end
	end

	if selfTestSetting then
		selfTestSetting.onChanged = function(enabled)
			if not enabled then return end
			local dev = type(env.Altair) == "table" and env.Altair.Dev or nil
			if type(dev) == "table" and type(dev.SelfTest) == "function" then
				local ok, result = pcall(dev.SelfTest, dev)
				local passed = ok and type(result) == "table" and result.ok == true
				Toast(passed and "Developer Tools self-test passed." or "Developer Tools self-test failed.", Color3.fromRGB(126, 104, 220))
			else
				Toast("Enable Debug Mode before running the self-test.", Color3.fromRGB(126, 104, 220))
			end
			syncDeveloperBoolean("Run Self-Test", false)
		end
	end

	if mcpSetting then
		mcpSetting.onChanged = function(value)
			configureDeveloperTools({ Bridge = { AutoConnect = value == true } })
		end
	end
	if streamSetting then
		streamSetting.onChanged = function(value)
			configureDeveloperTools({ Recorder = { StreamEvents = value == true } })
		end
	end
	if sampleSetting then
		sampleSetting.onChanged = function(value)
			configureDeveloperTools({ Recorder = { SampleHz = value } })
		end
	end
	if capacitySetting then
		capacitySetting.onChanged = function(value)
			configureDeveloperTools({ Recorder = { EventCapacity = value } })
		end
	end

	local debugEnabled = developerAvailable and settingValue("Debug Mode", false) == true
	altairAPI.SetSmartBarPersistentColor(debugEnabled and Color3.fromRGB(126, 104, 220) or nil)
	developerTools:Sync(debugEnabled)

	ensureFrameProperties()
	sortActions()

	initialiseAntiKick()
	checkLastVersion()

	smartBar.Back.Time.Text = os.date("%I:%M"):gsub("^0", "")
    smartBar.Back.Time.AMPM.Text = os.date("%p")

	local startupHidden = settingValue("Load Hidden")
	if altairValues.continuation.open ~= nil then startupHidden = not altairValues.continuation.open end
	altairValues.smartBarLayout:prepareStartup(startupHidden)

	if not startupHidden then
		if not altairValues.continuation.quiet and settingValue("Startup Sound Effect") then
			local startupSound = Instance.new("Sound")
			startupSound.Parent = UI
			startupSound.SoundId = "rbxassetid://5515669992"
			startupSound.Name = "startupSound"
			startupSound.Volume = 0.85
			startupSound.PlayOnRemove = true
			startupSound:Destroy()
		end

		openSmartBar()
	else
		closeSmartBar()
	end
	altairValues.continuation.mark(true)

	-- Resume Rivals if this executor lacks a teleport queue; the module deduplicates both paths.
	task.spawn(function()
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
	end)

	task.spawn(function()
		task.wait(0.65)
		local detected = altairValues.scanCustomScripts()
		if detected and not altairValues.continuation.quiet then
			altairValues.showGameDetection(detected)
		end
	end)

	if not altairValues.continuation.quiet and settingValue("Chat Spy") and not legacyChatActive then
		task.delay(6, function()
			queueNotification(
				"Chat Spy unavailable",
				"This experience uses Roblox's current chat system, which routes whispers through channels your client never receives. Chat Spy only works on the legacy chat system.",
				4370336704
			)
		end)
	end

	task.spawn(function()
		local infoSuccess, info = pcall(marketplaceService.GetProductInfo, marketplaceService, placeId)
		placeName = (infoSuccess and info and info.Name) or "this experience"
	end)
end

-- Altair Events

-- Drag can be clicked to toggle the SmartBar, or dragged to reposition it.
altairValues.smartBarLayout:bind(function()
	if smartBarOpen then closeSmartBar() else openSmartBar() end
end)
track(UI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() altairValues.smartBarLayout:fitViewport() end))
track(UI:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() altairValues.smartBarLayout:fitViewport() end))



local startSuccess, startError = pcall(start)
if not startSuccess then
	warn("Altair | Startup error: " .. tostring(startError))
	altairValues.lifecycle:unload()
	return
end

do
	local closeButton = customScriptPrompt:FindFirstChild("Close", true)
	local submitButton = customScriptPrompt:FindFirstChild("Submit", true)

	if closeButton and closeButton:IsA("GuiButton") then
		track(closeButton.MouseButton1Click:Connect(function()
			altairValues.closeCustomScriptPrompt()
		end))
	end

	if submitButton and submitButton:IsA("GuiButton") then
		track(submitButton.MouseButton1Click:Connect(function()
			altairValues.saveCustomScriptPrompt()
		end))
	end
end

do
	local layer = gameDetectionPrompt:FindFirstChild("Layer")

	if layer then
		local runButton = layer:FindFirstChild("Run")
		local closeButton = layer:FindFirstChild("Close")

		if runButton and runButton:IsA("GuiButton") then
			track(runButton.MouseButton1Click:Connect(function()
				altairValues.runDetectedScript()
			end))
		end

		if closeButton and closeButton:IsA("GuiButton") then
			track(closeButton.MouseButton1Click:Connect(function()
				altairValues.closeGameDetection()
			end))
		end
	end
end

characterPanel.Interactions.Reset.MouseButton1Click:Connect(function()
	resetSliders()

	characterPanel.Interactions.Reset.Rotation = 360
	Toast("Successfully reset all character panel sliders")
	tweenService:Create(characterPanel.Interactions.Reset, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
end)

characterPanel.Interactions.Reset.MouseEnter:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Reset, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
end)
characterPanel.Interactions.Reset.MouseLeave:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Reset, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
end)

playerSearch:GetPropertyChangedSignal("Text"):Connect(function()
	local query = string.lower(playerSearch.Text)

	for _, player in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if player:IsA("GuiObject") and player:GetAttribute("AltairRuntimePlayer") == true then
			local displayName = player:FindFirstChild("DisplayName", true)
			local displayText = displayName and string.lower(displayName.Text) or ""
			local username = string.lower(tostring(player:GetAttribute("AltairUsername") or ""))
			player.Visible =
				string.find(username, query, 1, true) ~= nil
				or string.find(displayText, query, 1, true) ~= nil
		end
	end

	if #playerSearch.Text == 0 then
		searchingForPlayer = false
		for _, player in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
			if player:IsA("GuiObject") and player:GetAttribute("AltairRuntimePlayer") == true then
				player.Visible = true
			end
		end
	else
		searchingForPlayer = true
	end
end)

characterPanel.Interactions.Serverhop.MouseEnter:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.1 }):Play()
end)

characterPanel.Interactions.Serverhop.MouseLeave:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Serverhop, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	tweenService:Create(characterPanel.Interactions.Serverhop.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.5 }):Play()
end)

characterPanel.Interactions.Rejoin.MouseEnter:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Rejoin, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.1 }):Play()
end)

characterPanel.Interactions.Rejoin.MouseLeave:Connect(function()
	if debounce then
		return
	end
	tweenService:Create(characterPanel.Interactions.Rejoin, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.5 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	tweenService:Create(characterPanel.Interactions.Rejoin.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.5 }):Play()
end)

characterPanel.Interactions.Rejoin.Interact.MouseButton1Click:Connect(rejoin)
characterPanel.Interactions.Serverhop.Interact.MouseButton1Click:Connect(serverhop)

for _, button in ipairs(scriptsPanel.Interactions.Selection:GetChildren()) do
	local origsize = button.Size

	button.MouseEnter:Connect(function()
		if not debounce then
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, button.Size.X.Offset - 5, 0, button.Size.Y.Offset - 3) }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(button.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		if not debounce then
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = origsize }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
			tweenService:Create(button.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		end
	end)

	button.Interact.MouseButton1Click:Connect(function()
		tweenService:Create(button, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = UDim2.new(0, origsize.X.Offset - 9, 0, origsize.Y.Offset - 6) }):Play()
		task.wait(0.1)
		tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = origsize }):Play()

		if button.Name == "Library" then
			if not scriptSearch.Visible and not debounce then
				openScriptSearch()
			end
		elseif button.Name == "CustomScripts" then
			altairValues.openCustomScriptPrompt()
		elseif button.Name == "Reprompt" then
			local detected = altairValues.detectedScript or altairValues.scanCustomScripts()
			if detected then
				altairValues.showGameDetection(detected)
			else
				Toast("No custom script was detected for this experience.")
			end
		end
	end)
end

smartBar.Back.Buttons.Home.Interact.MouseButton1Click:Connect(function()
	if debounce then
		return
	end
	if homeOpen then
		closeHome()
	else
		openHome()
	end
end)

smartBar.Back.Buttons.Settings.Interact.MouseButton1Click:Connect(function()
	if settingsPanel.Visible then
		closeSettings()
	else
		openSettings()
	end
end)

for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
 if button:IsA("GuiObject") and button.Name ~= "Placeholder" and button.Name~="Home" and button:FindFirstChild("Interact") then
  track(button.Interact.MouseButton1Click:Connect(function()
   if homeOpen then closeHome() end
  end))
 end
	if button:IsA("GuiObject") and button.Name ~= "Placeholder" and UI:FindFirstChild(button.Name) and button:FindFirstChild("Interact") then
		button.Interact.MouseButton1Click:Connect(function()
			if isPanel(button.Name) then
				if not debounce and UI:FindFirstChild(button.Name).Visible then
					task.spawn(closePanel, button.Name)
				else
					task.spawn(openPanel, button.Name)
				end
			end

			tweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 28, 0, 28) }):Play()
			tweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.6 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 0.6 }):Play()
			task.wait(0.15)
			tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = UDim2.fromOffset(34, 34) }):Play()
			tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { ImageTransparency = 0.02 }):Play()
		end)

		button.MouseEnter:Connect(function()
			tweenService:Create(button.UIGradient, TweenInfo.new(1.4, Enum.EasingStyle.Quint), { Rotation = 360 }):Play()
			tweenService:Create(button.UIStroke.UIGradient, TweenInfo.new(1.4, Enum.EasingStyle.Quint), { Rotation = 360 }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, -0.5) }):Play()
		end)

		button.MouseLeave:Connect(function()
			tweenService:Create(button.UIStroke.UIGradient, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(0.9, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 0.05 }):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0) }):Play()
		end)
	end
end

track(userInputService.InputBegan:Connect(function(input, processed)
	if not checkAltair() then
		return
	end

	if checkingForKey then
		local inputType = input.UserInputType.Name
		if inputType ~= "Keyboard" and string.find(inputType, "Gamepad", 1, true) ~= 1 then
			return
		end

		local keyCode = input.KeyCode
		local keyName = keyCode and keyCode.Name
		if keyName and keyName ~= "Unknown" then
			local capture = checkingForKey
			if keyName == "Backspace" or keyName == "Delete" then
				capture.object.InputFrame.InputBox.Text = "No Keybind"
				capture.data.current = nil
			else
				capture.object.InputFrame.InputBox.Text = keyName
				capture.data.current = keyName
			end
			checkingForKey = nil
			capture.object.InputFrame.InputBox:ReleaseFocus()
			saveSettings()
		end

		return
	end

	if scriptSearch.Visible and input.KeyCode == Enum.KeyCode.Escape then
		closeScriptSearch()
		return
	end

	if processed then
		return
	end

	local inputTypeName = input.UserInputType.Name
	if inputTypeName ~= "Keyboard" and string.find(inputTypeName, "Gamepad", 1, true) ~= 1 then
		return
	end

	for _, category in ipairs(altairSettings) do
		for _, setting in ipairs(category.categorySettings) do
			if setting.settingType == "Key" and setting.callback and input.KeyCode == keyCodeFromName(setting.current) then
				task.spawn(setting.callback)

				local action = setting.actionIndex and altairValues.actions[setting.actionIndex]
				local object = actionButton(action)

				if action and object then
					applyActionVisual(action, object)

					if action.enabled and action.disableAfter then
						task.delay(action.disableAfter, function()
							action.enabled = false
							applyActionVisual(action, object)
						end)
					end

					if action.enabled and action.rotateWhileEnabled then
						task.spawn(function()
							repeat
								object.Icon.Rotation = 0
								tweenService:Create(object.Icon, TweenInfo.new(0.75, Enum.EasingStyle.Quint), { Rotation = 360 }):Play()
								task.wait(1)
							until not action.enabled or not checkAltair()
							object.Icon.Rotation = 0
						end)
					end
				end
			end
		end
	end

	if input.KeyCode == keyCodeFromName(settingValue("Open ScriptSearch")) and not debounce then
		if scriptSearch.Visible then
			closeScriptSearch()
		else
			openScriptSearch()
		end
	end

	if input.KeyCode == keyCodeFromName(settingValue("Toggle smartBar")) and not debounce then
		if smartBarOpen then
			closeSmartBar()
		else
			openSmartBar()
		end
	end
end))

track(userInputService.InputEnded:Connect(function(input)
	if not checkAltair() then
		return
	end

	-- Touch releases end a drag too; MouseButton1 alone left sliders stuck active on mobile
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		for _, slider in pairs(altairValues.sliders) do
			slider.active = false

			if characterPanel.Visible and not debounce and slider.object and checkAltair() then
				tweenService:Create(slider.object, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 }):Play()
				tweenService:Create(slider.object.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { Transparency = 1 }):Play()
				tweenService:Create(slider.object.Information, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), { TextTransparency = 0 }):Play()
			end
		end
	end
end))

track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	task.wait(0.5)
	updateSliderPadding()
end))

scriptSearch.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if #scriptSearch.SearchBox.Text > 0 then
		tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(255, 255, 255) }):Play()
		tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	else
		tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(150, 150, 150) }):Play()
		tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextColor3 = Color3.fromRGB(150, 150, 150) }):Play()
	end
end)

scriptSearch.SearchBox.FocusLost:Connect(function(enterPressed)
	-- ReleaseFocus during close must not start another close coroutine.
	if altairValues.scriptSearchState.phase ~= "open" or not scriptSearch.Visible then return end
	tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(150, 150, 150) }):Play()
	tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextColor3 = Color3.fromRGB(150, 150, 150) }):Play()

	if #scriptSearch.SearchBox.Text > 0 then
		if enterPressed then
			pcall(searchScriptBlox, scriptSearch.SearchBox.Text)
		end
	else
		closeScriptSearch()
	end
end)

scriptSearch.SearchBox.Focused:Connect(function()
	if #scriptSearch.SearchBox.Text > 0 then
		tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(255, 255, 255) }):Play()
		tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	end
end)

track(userInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	for _, slider in pairs(altairValues.sliders) do
		if slider.active then
			updateSlider(slider, nil, nil, input.Position.X)
		end
	end
end))

track(userInputService.WindowFocusReleased:Connect(function()
	windowFocusChanged(false)
end))
track(userInputService.WindowFocused:Connect(function()
	windowFocusChanged(true)
end))

if not legacyChatActive then
	track(textChatService.MessageReceived:Connect(function(chatMessage)
		if not checkAltair() or not chatMessage or not chatMessage.TextSource then
			return
		end

		local player = players:GetPlayerByUserId(chatMessage.TextSource.UserId)
		if player then
			altairValues.chatModeration:observe(player, chatMessage.Text)
		end
	end))
end

for _, player in ipairs(players:GetPlayers()) do
	createPlayer(player)
	createEsp(player)
	addPlayerConnection(player, player.Chatted:Connect(function(message)
		onChatted(player, message)
	end))
end

track(localPlayer.CharacterAdded:Connect(function()
	altairValues.activity:record("Character spawned", "Your character was added to the world")
end))

track(players.PlayerAdded:Connect(function(player)
	altairValues.activity:record("Player joined", player.DisplayName)
	if not checkAltair() then
		return
	end

	createPlayer(player)
	createEsp(player)

	addPlayerConnection(player, player.Chatted:Connect(function(message)
		onChatted(player, message)
	end))

	if settingValue("Log PlayerAdded and PlayerRemoving") then
		postWebhook(settingValue("Player Added and Removing Webhook URL"), {
			["content"] = player.DisplayName .. " (@" .. player.Name .. ") joined the server.",
			["avatar_url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png",
			["username"] = player.DisplayName,
			["allowed_mentions"] = { parse = {} },
		})
	end

	if settingValue("Moderator Detection") and altairValues.currentCreator == "group" then
		task.spawn(function()
			local roleSuccess, roleFound = pcall(player.GetRoleInGroup, player, creatorId)
			if not roleSuccess or type(roleFound) ~= "string" then
				return
			end

			for _, role in ipairs(altairValues.administratorRoles) do
				if string.find(string.lower(roleFound), role, 1, true) then
					promptModerator(player, roleFound)
					queueNotification("Administrator Joined", roleFound .. " " .. player.DisplayName .. " has joined your session", 3944670656)
					break -- a role matching two keywords used to fire two prompts and two toasts
				end
			end
		end)
	end

	if settingValue("Friend Notifications") then
		local friendSuccess, isFriend = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
		if friendSuccess and isFriend then
			queueNotification("Friend Joined", "Your friend " .. player.DisplayName .. " has joined your server.", 4370335364)
		end
	end
end))

track(players.PlayerRemoving:Connect(function(player)
	altairValues.activity:record("Player left", player.DisplayName)
	disconnectPlayerConnections(player)
	altairValues.chatModeration.users[player.UserId] = nil
	altairValues.playerAnomaly.users[player.UserId] = nil

	if settingValue("Log PlayerAdded and PlayerRemoving") then
		postWebhook(settingValue("Player Added and Removing Webhook URL"), {
			["content"] = player.DisplayName .. " (@" .. player.Name .. ") left the server.",
			["avatar_url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png",
			["username"] = player.DisplayName,
			["allowed_mentions"] = { parse = {} },
		})
	end

	if spectating == player then
		restoreCamera()
	end

	removePlayer(player)
	locatedPlayers[player.Name] = nil

	if espConnections[player] then
		espConnections[player]:Disconnect()
		espConnections[player] = nil
	end

	local highlight = espContainer:FindFirstChild(player.Name)
	if highlight then
		highlight:Destroy()
	end
end))

task.spawn(function()
	while checkAltair() do
		if settingValue("Suspicious Player Detection", true) then
			altairValues.playerAnomaly:sampleAll()
			task.wait(altairValues.playerAnomaly.sampleRate)
		else
			table.clear(altairValues.playerAnomaly.users)
			task.wait(1)
		end
	end
end)

track(runService.RenderStepped:Connect(function(frame)
	if not checkAltair()
		or not Pro
		or not settingValue("Adaptive Performance Warning", false)
	then
		return
	end

	local profile = altairValues.frameProfile
	local fps = math.round(1 / math.max(frame, 1 / 1000))
	local nextIndex = (profile.fpsQueueIndex % profile.fpsQueueSize) + 1
	local oldValue = profile.fpsQueue[nextIndex]

	if oldValue ~= nil then
		profile.totalFPS -= oldValue
	else
		profile.fpsQueueCount += 1
	end

	profile.fpsQueue[nextIndex] = fps
	profile.fpsQueueIndex = nextIndex
	profile.totalFPS += fps
end))

local function runtime()
	if not checkAltair() then return end
	local characterParts = {}
	local characterPartConnections = {}

	local function clearCharacterPartTracking()
		for _, connection in ipairs(characterPartConnections) do
			connection:Disconnect()
		end
		table.clear(characterPartConnections)
		table.clear(characterParts)
		table.clear(noclipDefaults)
	end

	local function trackCharacterParts(character)
		clearCharacterPartTracking()
		if not character then
			return
		end

		local function add(part)
			if part:IsA("BasePart") then
				characterParts[part] = true
				if noclipDefaults[part] == nil then
					noclipDefaults[part] = part.CanCollide
				end
			end
		end

		for _, descendant in ipairs(character:GetDescendants()) do
			add(descendant)
		end

		table.insert(characterPartConnections, character.DescendantAdded:Connect(add))
		table.insert(
			characterPartConnections,
			character.DescendantRemoving:Connect(function(part)
				characterParts[part] = nil
				noclipDefaults[part] = nil
			end)
		)
	end

	local function spatialShieldWanted()
		return Pro and settingValue("Spatial Shield") == true
	end

	local function anonymousWanted()
		return settingValue("Anonymous Client") == true
	end

	local function registerSound(instance)
		local suppression = suppressedSounds[instance.SoundId]
		if suppression then
			instance.Volume = (suppression == "S" and 0.5) or (suppression == "S2" and 0.1) or 0
			return
		end

		if not spatialShieldWanted() then
			return
		end
		if trackedSounds[instance] then
			return
		end

		if not cachedIds[instance.SoundId] then
			cachedIds[instance.SoundId] = true
			trackedSounds[instance] = true
			table.insert(soundInstances, instance)
		end
	end

	local function anonymousReplacement(raw, objectName)
		local lowered = raw:lower()
		local result, cursor = {}, 1
		while cursor <= #raw do
			local us, ue = string.find(lowered, lowerName, cursor, true)
			local ds, de = string.find(lowered, lowerDisplayName, cursor, true)
			if lowerName == "" then us, ue = nil, nil end
			if lowerDisplayName == "" then ds, de = nil, nil end
			if not us and not ds then break end
			local useUsername = us and (not ds or us < ds or (us == ds and ue > de))
			if us and ds and us == ds and ue == de then
				local field = (objectName or ""):lower()
				useUsername = field == "username" or field == "user" or (us > 1 and raw:sub(us - 1, us - 1) == "@")
			end
			local startIndex, endIndex = useUsername and us or ds, useUsername and ue or de
			table.insert(result, raw:sub(cursor, startIndex - 1))
			table.insert(result, useUsername and randomUsername or randomDisplayName)
			cursor = endIndex + 1
		end
		table.insert(result, raw:sub(cursor))
		return table.concat(result)
	end

	local function maskAnonymousText(text)
		if not text.Parent then return end
		altairValues.anonymousMaskedText = altairValues.anonymousMaskedText or {}
		local raw = text.Text
		local lastMasked = altairValues.anonymousMaskedText[text]
		if raw == lastMasked then return end
		local lowerText = string.lower(raw)
		if string.find(lowerText, lowerName, 1, true) or string.find(lowerText, lowerDisplayName, 1, true) then
			originalTextValues[text] = raw
			local masked = anonymousReplacement(raw, text.Name)
			altairValues.anonymousMaskedText[text] = masked
			text.Text = masked
		else
			originalTextValues[text] = nil
			altairValues.anonymousMaskedText[text] = nil
		end
	end

	local function registerText(instance)
		if not anonymousWanted() then
			return
		end
		if trackedText[instance] then
			return
		end

		trackedText[instance] = true
		table.insert(cachedText, instance)
		if instance:IsDescendantOf(UI) then
			-- HiddenUI is outside the normal DataModel sweep. Mask Altair text immediately,
			-- including names rewritten by the Home/profile/player-list renderers.
			maskAnonymousText(instance)
			local connection = track(instance:GetPropertyChangedSignal("Text"):Connect(function()
				if anonymousWanted() then maskAnonymousText(instance) end
			end))
			track(instance.Destroying:Once(function() connection:Disconnect() end))
		end
	end

	local function registerDescendant(instance)
		if instance:IsA("Sound") then
			registerSound(instance)
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			registerText(instance)
		end
	end

	local descendantSweepPending = false
	local descendantRemovingConn
	local function refreshDescendantTracking()
		if descendantSweepPending then
			return
		end
		descendantSweepPending = true

		task.spawn(function()
			local descendants = game:GetDescendants()
			for _, instance in ipairs(UI:GetDescendants()) do
				if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
					table.insert(descendants, instance)
				end
			end
			for index, instance in ipairs(descendants) do
				if not checkAltair() then break end
				registerDescendant(instance)
				if index % 400 == 0 then
					task.wait()
				end
			end
			table.clear(descendants)
			descendantSweepPending = false
		end)
	end

	local function teardown()
		if altairValues.runtimeCleaned then return end
		altairValues.runtimeCleaned = true
		developerTools:Stop("altair-teardown")
		homeController.destroy()
		if espContainer then
			espContainer:Destroy()
		end

		if descendantAddedConn then
			descendantAddedConn:Disconnect()
			descendantAddedConn = nil
		end
		if descendantRemovingConn then
			descendantRemovingConn:Disconnect()
			descendantRemovingConn = nil
		end

		for player, conn in pairs(espConnections) do
			conn:Disconnect()
			espConnections[player] = nil
		end

		for player in pairs(altairValues.playerConnections or {}) do
			disconnectPlayerConnections(player)
		end

		for _, connection in ipairs(connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(connections)

		pcall(function()
			for part in pairs(characterParts) do
				if part.Parent then
					local default = noclipDefaults[part]
					part.CanCollide = if default == nil then true else default
				end
			end
		end)

		clearCharacterPartTracking()
		undoAnonymousChanges()
		table.clear(originalTextValues)

		pcall(restoreCamera)
		pcall(removeReverbs, 0.1)
		pcall(blurSignature, false)

		-- Put back everything Altair changed globally
		if setFpsCap then
			pcall(setFpsCap, 240)
		end
		pcall(function()
			gameSettings.MasterVolume = oldVolume
		end)
		pcall(function()
			camera.FieldOfView = baseFieldOfView
		end)

		for _, coreUI in ipairs(altairValues.cachedCoreUI or {}) do
			pcall(starterGui.SetCoreGuiEnabled, starterGui, Enum.CoreGuiType[coreUI], true)
		end

		for _, cachedUI in ipairs(altairValues.cachedInGameUI or {}) do
			pcall(function()
				if cachedUI.Parent then
					cachedUI.Enabled = true
				end
			end)
		end
	end

	altairValues.lifecycle.runtimeCleanup = teardown
	trackCharacterParts(localPlayer.Character)
	track(localPlayer.CharacterAdded:Connect(trackCharacterParts))
	track(localPlayer.CharacterRemoving:Connect(clearCharacterPartTracking))

	local noclipWasActive = false

	track(runService.Stepped:Connect(function()
		if not checkAltair() then
			return
		end

		local noclipActive = altairValues.actions[1].enabled or altairValues.actions[6].enabled

		if not noclipActive and not noclipWasActive then
			return
		end

		for part in pairs(characterParts) do
			if part.Parent then
				if noclipActive then
					part.CanCollide = false
				else
					local default = noclipDefaults[part]
					part.CanCollide = if default == nil then true else default
				end
			end
		end

		noclipWasActive = noclipActive
	end))

	track(runService.Heartbeat:Connect(function(dt)
		if not checkAltair() then
			return
		end

		local flightActive = altairValues.actions[2].enabled
		local flingActive = altairValues.actions[6].enabled
		if not flightActive and not flingActive then
			for _, mover in ipairs(movers) do
				if mover and mover.Parent then
					mover.Parent = nil
				end
			end
			return
		end

		local character = localPlayer.Character
		local primaryPart = character and character.PrimaryPart
		if not primaryPart then
			return
		end

		local bodyVelocity, bodyGyro, bodyAngularVelocity = unpack(movers)
		if not bodyVelocity or not bodyGyro or not bodyAngularVelocity then
			bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.one * 9e9

			bodyGyro = Instance.new("BodyGyro")
			bodyGyro.MaxTorque = Vector3.one * 9e9
			bodyGyro.P = 9e4

			bodyAngularVelocity = Instance.new("BodyAngularVelocity")
			bodyAngularVelocity.AngularVelocity = Vector3.yAxis * 9e9
			bodyAngularVelocity.MaxTorque = Vector3.yAxis * 9e9
			bodyAngularVelocity.P = 9e9

			movers = { bodyVelocity, bodyGyro, bodyAngularVelocity }
		end

		bodyAngularVelocity.Parent = flingActive and primaryPart or nil

		if flightActive then
			local camCFrame = camera.CFrame
			local velocity = Vector3.zero
			local rotation = camCFrame.Rotation

			if userInputService:IsKeyDown(Enum.KeyCode.W) then
				velocity += camCFrame.LookVector
				rotation *= CFrame.Angles(math.rad(-40), 0, 0)
			end
			if userInputService:IsKeyDown(Enum.KeyCode.S) then
				velocity -= camCFrame.LookVector
				rotation *= CFrame.Angles(math.rad(40), 0, 0)
			end
			if userInputService:IsKeyDown(Enum.KeyCode.D) then
				velocity += camCFrame.RightVector
				rotation *= CFrame.Angles(0, 0, math.rad(-40))
			end
			if userInputService:IsKeyDown(Enum.KeyCode.A) then
				velocity -= camCFrame.RightVector
				rotation *= CFrame.Angles(0, 0, math.rad(40))
			end
			if userInputService:IsKeyDown(Enum.KeyCode.Space) then
				velocity += Vector3.yAxis
			end
			if userInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
				velocity -= Vector3.yAxis
			end

			local alpha = 1 - math.exp(-12 * dt)
			local targetVelocity = velocity * altairValues.sliders[3].value * 45
			bodyVelocity.Velocity = bodyVelocity.Velocity:Lerp(targetVelocity, alpha)
			bodyVelocity.Parent = primaryPart

			if not flingActive then
				bodyGyro.CFrame = bodyGyro.CFrame:Lerp(rotation, alpha)
				bodyGyro.Parent = primaryPart
			else
				bodyGyro.Parent = nil
			end
		else
			bodyVelocity.Parent = nil
			bodyGyro.Parent = nil
		end
	end))

	-- Anonymous Client throttle/transition state
	altairValues.anonymousMaskedText = altairValues.anonymousMaskedText or {}
	local anonymousAccumulator = 0
	local spatialAccumulator = 0
	local anonymousWasEnabled = false
	local ANONYMOUS_INTERVAL = 0.25
	local SPATIAL_INTERVAL = 0.1

	track(runService.Heartbeat:Connect(function(dt)
		if not checkAltair() then
			return
		end
		spatialAccumulator += dt
		if Pro and spatialAccumulator >= SPATIAL_INTERVAL then
			spatialAccumulator %= SPATIAL_INTERVAL
			if settingValue("Spatial Shield") and tonumber(settingValue("Spatial Shield Threshold")) then
				local threshold = tonumber(settingValue("Spatial Shield Threshold"))
				for i = #soundInstances, 1, -1 do
					local sound = soundInstances[i]
					if not sound then
						table.remove(soundInstances, i)
					elseif gameSettings.MasterVolume * sound.PlaybackLoudness * sound.Volume >= threshold then
						if sound.Volume > 0.55 then
							suppressedSounds[sound.SoundId] = "S"
							sound.Volume = 0.5
						elseif sound.Volume > 0.2 and sound.Volume < 0.55 then
							suppressedSounds[sound.SoundId] = "S2"
							sound.Volume = 0.1
						elseif sound.Volume < 0.2 then
							suppressedSounds[sound.SoundId] = "Mute"
							sound.Volume = 0
						end
						if soundSuppressionNotificationCooldown == 0 then
							queueNotification("Spatial Shield", "A high-volume audio is being played (" .. sound.Name .. ") and it has been suppressed.", 4483362458)
							soundSuppressionNotificationCooldown = 15
						end
						table.remove(soundInstances, i)
					end
				end
			end

			if soundSuppressionNotificationCooldown > 0 then
				soundSuppressionNotificationCooldown -= 1
			end
		end

		local anonymousEnabled = settingValue("Anonymous Client")
		anonymousAccumulator += dt

		if anonymousEnabled then
			if anonymousAccumulator >= ANONYMOUS_INTERVAL then
				anonymousAccumulator %= ANONYMOUS_INTERVAL

				for i = #cachedText, 1, -1 do
					local text = cachedText[i]
					if not text or not text.Parent then
						trackedText[text] = nil
						altairValues.anonymousMaskedText[text] = nil
						originalTextValues[text] = nil
						table.remove(cachedText, i)
					else
						maskAnonymousText(text)
					end
				end
			end
		elseif anonymousWasEnabled then
			anonymousAccumulator = 0
			undoAnonymousChanges()
			table.clear(originalTextValues)
		end

		anonymousWasEnabled = anonymousEnabled
	end))

	local function descendantTrackingWanted()
		return spatialShieldWanted() or anonymousWanted() or next(suppressedSounds) ~= nil
	end

	local function updateDescendantWatcher()
		local wanted = descendantTrackingWanted()
		if wanted and not descendantAddedConn then
			descendantAddedConn = game.DescendantAdded:Connect(function(instance)
				if checkAltair() then
					registerDescendant(instance)
				end
			end)
		elseif not wanted and descendantAddedConn then
			descendantAddedConn:Disconnect()
			descendantAddedConn = nil
		end

		if wanted and not descendantRemovingConn then
			descendantRemovingConn = game.DescendantRemoving:Connect(function(instance)
				trackedSounds[instance] = nil
				trackedText[instance] = nil
				altairValues.anonymousMaskedText[instance] = nil
				originalTextValues[instance] = nil
			end)
		elseif not wanted and descendantRemovingConn then
			descendantRemovingConn:Disconnect()
			descendantRemovingConn = nil
		end
	end

	track(UI.DescendantAdded:Connect(function(instance)
		if checkAltair() and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
			registerText(instance)
		end
	end))

	if descendantTrackingWanted() then
		refreshDescendantTracking()
	end
	updateDescendantWatcher()

	local lastAnonymousWanted = anonymousWanted()
	local lastSpatialWanted = spatialShieldWanted()
	local lastAntiIdle = nil

	while task.wait(1) do
		if not checkAltair() then
			altairValues.lifecycle:unload()
			break
		end

		local tickSuccess, tickError = pcall(function()
			smartBar.Back.Time.Text = os.date("%I:%M"):gsub("^0", "")
			smartBar.Back.Time.AMPM.Text = os.date("%p")
			UpdateHome()

			local anonymousNow, spatialNow = anonymousWanted(), spatialShieldWanted()
			if (anonymousNow and not lastAnonymousWanted) or (spatialNow and not lastSpatialWanted) then
				refreshDescendantTracking()
			end
			lastAnonymousWanted, lastSpatialWanted = anonymousNow, spatialNow
			updateDescendantWatcher()

			if getConnectionsFor then
				local antiIdle = settingValue("Anti Idle")
				if antiIdle ~= lastAntiIdle then
					lastAntiIdle = antiIdle
					pcall(function()
						for _, connection in getConnectionsFor(localPlayer.Idled) do
							if antiIdle then
								connection:Disable()
							else
								connection:Enable()
							end
						end
					end)
				end
			end

			local dragVisible = not settingValue("Hide Bar")
			if drag.Visible ~= dragVisible then
				drag.Visible = dragVisible
			end

			local promptGui = coreGui:FindFirstChild("RobloxPromptGui")
			local promptOverlay = promptGui and promptGui:FindFirstChild("promptOverlay")
			local disconnectedRobloxUI = promptOverlay and promptOverlay:FindFirstChild("ErrorPrompt")

			if disconnectedRobloxUI and not promptedDisconnected then
				local messageArea = disconnectedRobloxUI:FindFirstChild("MessageArea")
				local errorFrame = messageArea and messageArea:FindFirstChild("ErrorFrame")
				local errorMessage = errorFrame and errorFrame:FindFirstChild("ErrorMessage")
				local reasonPrompt = errorMessage and errorMessage.Text or ""

				promptedDisconnected = true
				disconnectedPrompt.Parent = promptGui

				local disconnectType
				local foundString

				for _, preDisconnectType in ipairs(altairValues.disconnectTypes) do
					for _, typeString in pairs(preDisconnectType[2]) do
						if string.find(reasonPrompt, typeString) then
							disconnectType = preDisconnectType[1]
							foundString = true
							break
						end
					end
				end

				if not foundString then
					disconnectType = "kick"
				end

				wipeTransparency(disconnectedPrompt, 1, true)
				disconnectedPrompt.Visible = true

				if disconnectType == "ban" then
					disconnectedPrompt.Content.Text = "You've been banned, would you like to leave this server?"
					disconnectedPrompt.Action.Text = "Leave"
					disconnectedPrompt.Action.Size = UDim2.new(0, 77, 0, 36) -- use textbounds

					disconnectedPrompt.UIGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
						ColorSequenceKeypoint.new(1, Color3.new(0.819608, 0.164706, 0.164706)),
					})
				elseif disconnectType == "kick" then
					disconnectedPrompt.Content.Text = "You've been kicked, would you like to serverhop?"
					disconnectedPrompt.Action.Text = "Serverhop"
					disconnectedPrompt.Action.Size = UDim2.new(0, 114, 0, 36)

					disconnectedPrompt.UIGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
						ColorSequenceKeypoint.new(1, Color3.new(0.0862745, 0.596078, 0.835294)),
					})
				elseif disconnectType == "network" then
					disconnectedPrompt.Content.Text = "You've lost connection, would you like to rejoin?"
					disconnectedPrompt.Action.Text = "Rejoin"
					disconnectedPrompt.Action.Size = UDim2.new(0, 82, 0, 36)

					disconnectedPrompt.UIGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
						ColorSequenceKeypoint.new(1, Color3.new(0.862745, 0.501961, 0.0862745)),
					})
				end

				tweenService:Create(disconnectedPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				tweenService:Create(disconnectedPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
				tweenService:Create(disconnectedPrompt.Content, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
				tweenService:Create(disconnectedPrompt.Action, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.7 }):Play()
				tweenService:Create(disconnectedPrompt.Action, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

				disconnectedPrompt.Action.MouseButton1Click:Connect(function()
					if disconnectType == "ban" then
						leaveExperience()
					elseif disconnectType == "kick" then
						task.spawn(serverhop)
					elseif disconnectType == "network" then
						rejoin()
					end
				end)
			end

			if Pro then
				-- all Pro checks here!

				-- Two-Way Adaptive Latency Checks
				if settingValue("Adaptive Latency Warning") and checkHighPing() then
					if altairValues.pingProfile.pingNotificationCooldown <= 0 then
						queueNotification(
							"High Latency Warning",
							"We've noticed your latency has reached a higher value than usual, you may find that you are lagging or your actions are delayed in-game. Consider checking for any background downloads on your machine.",
							4370305588
						)
						altairValues.pingProfile.pingNotificationCooldown = 120
					end
				end

				if altairValues.pingProfile.pingNotificationCooldown > 0 then
					altairValues.pingProfile.pingNotificationCooldown -= 1
				end

				-- Adaptive frame time checks
				if altairValues.frameProfile.frameNotificationCooldown <= 0 then
					if altairValues.frameProfile.fpsQueueCount > 0 then
						local avgFPS = altairValues.frameProfile.totalFPS / altairValues.frameProfile.fpsQueueCount

						if avgFPS < altairValues.frameProfile.lowFPSThreshold then
							if settingValue("Adaptive Performance Warning") then
								queueNotification(
									"Degraded Performance",
									"We've noticed your client's frames per second have decreased. Consider checking for any background tasks or programs on your machine.",
									4384400106
								)
								altairValues.frameProfile.frameNotificationCooldown = 120
							end
						end
					end
				end

				if altairValues.frameProfile.frameNotificationCooldown > 0 then
					altairValues.frameProfile.frameNotificationCooldown -= 1
				end
			end
		end) -- end of the per-tick pcall

		if not tickSuccess then
			warn("Altair | Error in the update loop (recovering): " .. tostring(tickError))
		end
	end
end

(function()
	if developerTools:IsAvailable() and type(isfile) == "function" and type(readfile) == "function" then
		local okExists, exists = pcall(isfile, settingsPath())
		if okExists and exists then
			local okRead, stored = pcall(function()
				return httpService:JSONDecode(readfile(settingsPath()))
			end)
			if okRead and type(stored) == "table" and stored.debugmode == true then
				altairAPI.SetSmartBarPersistentColor(Color3.fromRGB(126, 104, 220))
			end
		end
	end
end)()

if not altairValues.continuation.quiet then
	BlinkSmartBar(2)
	task.wait(2)
	Toast("Welcome back. Nice to see you, "..lowerDisplayName)
end
--[[]]

runtime()