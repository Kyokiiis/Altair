
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

-- Ensure the game is loaded.
--
-- game.Loaded fires exactly once, so waiting on it after it has already fired blocks
-- forever. IsLoaded() guards that, but the two disagree on auto-execute: the signal has
-- gone while IsLoaded() still reads false, and Altair stops here with no error, nothing on
-- screen and no way for the user to tell it ever ran. Polling the flag instead cannot miss
-- an edge, and the deadline means a client that never reports loaded costs a few seconds
-- rather than the whole launch.
if not game:IsLoaded() then
	local deadline = os.clock() + 10
	while not game:IsLoaded() and os.clock() < deadline do
		task.wait()
	end
end

-- Check License Tier
local Pro = true -- We're open sourced now!

-- Executor Feature Detection
-- Optional globals vary wildly between executors, so every one is resolved through a
-- typeof() check up front. Anything missing stays nil and every call site guards on it,
-- which stops a single absent function from aborting startup for the whole script.
local function optional(value)
	return typeof(value) == "function" and value or nil
end

local setFpsCap = optional(setfpscap)
local getExecutorName = optional(identifyexecutor)
local getCustomAsset = optional(getcustomasset)
local getConnectionsFor = optional(getconnections)
local hookMetamethod = optional(hookmetamethod)
local getHiddenUI = optional(gethui)
local cloneRef = optional(cloneref)
local getEnv = optional(getgenv)

-- The executor's shared environment. Falls back to _G so the caches and re-run sentinels
-- still have somewhere to live on executors that don't expose getgenv.
local env = getEnv and getEnv() or _G

-- Prefer the executor's own service clones where available; a cloneref'd handle isn't
-- reachable from the game's own scripts, which is what the "reduce detection" TODO wants.
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
-- Roblox retired the legacy chat system; anything built on DefaultChatSystemChatEvents only
-- works in experiences still opted into it. Checked once here rather than at each call site.
local legacyChatActive = getMessage ~= nil and textChatService.ChatVersion == Enum.ChatVersion.LegacyChatService
local localPlayer = players.LocalPlayer
local notifications = {}

local promptedDisconnected = false
local smartBarOpen = false
local debounce = false
local searchingForPlayer = false
local musicQueue = {}
local playGeneration = 0 -- bumped to invalidate parked Ended:Wait coroutines in playNext
local currentAudio
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
local espContainer = Instance.new("Folder", getHiddenUI and getHiddenUI() or coreGui)
espContainer.Name = "AltairESP"
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
}
local spectating
local closeModPrompt

-- Configurable Core Values
local SECURITY_PROMPT_TIMEOUT = 60 -- seconds before an unanswered prompt denies by default
local altairValues = {
	altairVersion = "1.28",
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
	interfaceAsset = 106482431665693,


	-- The per-experience game scripts, the neon module and the sense ESP library were all
	-- removed: their URLs pointed at a branch that no longer exists and at the retired
	-- shlexware org, so every fetch 404'd. Experience Sync went with them.
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
	buttonPositions = { Character = UDim2.new(0.5, -30, 1, -29), Scripts = UDim2.new(0.5, -10, 1, -29), Playerlist = UDim2.new(0.5, 20, 1, -29) },
	chatSpy = {
		enabled = true,
		visual = {
			Color = Color3.fromRGB(26, 148, 255),
			Font = Enum.Font.SourceSansBold,
			TextSize = 18,
		},
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
				name = "Hide Toggle Button",
				description = "This will remove the option to open the smartBar with the toggle button.",
				settingType = "Boolean",
				current = false,

				id = "hidetoggle",
			},
			{
				name = "Now Playing Notifications",
				description = "When active, Altair will notify you when the next song in your Music queue plays.",
				settingType = "Boolean",
				current = true,

				id = "nowplaying",
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
}

-- Generate random username
local randomAdjective = altairValues.nameGeneration.adjectives[math.random(1, #altairValues.nameGeneration.adjectives)]
local randomNoun = altairValues.nameGeneration.nouns[math.random(1, #altairValues.nameGeneration.nouns)]
local randomNumber = math.random(100, 3999) -- You can customize the range
local randomUsername = randomAdjective .. randomNoun .. randomNumber

-- Initialise Altair Client Interface
local guiParent = getHiddenUI and getHiddenUI() or (useStudio and localPlayer:WaitForChild("PlayerGui")) or coreGui
local altair = guiParent:FindFirstChild("Altair")
if altair then
	altair:Destroy()
end

-- In Studio there's no GetObjects, so the interface is expected to sit next to this script.
local function loadInterface()
	if useStudio then
		local container = script.Parent
		return container and container:FindFirstChild(altairValues.altairName)
	end
	-- Indexing [1] directly threw its own error when the fetch came back empty, which
	-- then read as "GetObjects is broken" rather than "the asset didn't arrive".
	local objects = game:GetObjects("rbxassetid://" .. altairValues.interfaceAsset)
	return objects and objects[1]
end

-- GetObjects has two distinct failure modes and they used to share one silent exit: it can
-- throw, or it can succeed and hand back an empty table because the asset did not come down
-- for this client. The second is transient and worth retrying; neither is worth ending the
-- script over without telling anyone.
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

-- The old message named only the pcall's error value, so the empty-asset case printed
-- "nil" and said nothing about what had gone wrong. Both causes are spelled out now, and
-- the line says Altair is stopping -- the previous wording read as a warning about a
-- missing extra rather than the end of the launch.
if not uiResult then
	warn("Altair | Couldn't load the interface asset after 3 attempts (" .. tostring(uiError) .. "). Altair has not started.")
	return
end

local UI = uiResult
UI.Name = altairValues.altairName
UI.Parent = guiParent
UI.Enabled = false

-- Create Variables for Interface Elements
local characterPanel = UI.Character
local openHome, closeHome
local homeOpen, homeFov = false, nil
local closeSettings, closeScriptSearch
local homeChatEnabled
local characterPanelSize = characterPanel.Size
local customScriptPrompt = UI.CustomScriptPrompt
local securityPrompt = UI.SecurityPrompt
local disconnectedPrompt = UI.Disconnected
local gameDetectionPrompt = UI.GameDetection
local homeContainer = UI.Home
local moderatorDetectionPrompt = UI.ModeratorDetectionPrompt
local musicPanel = UI.Music
local notificationContainer = UI.Notifications
local playerlistPanel = UI.Playerlist
local playerSearch = playerlistPanel.Interactions.SearchFrame.SearchBox
local scriptSearch = UI.ScriptSearch
local scriptsPanel = UI.Scripts
local settingsPanel = UI.Settings
local smartBar = UI.SmartBar
local toggle = UI.Toggle
local toastsContainer = UI.Toasts

-- Interface Caching
-- Reset per run: carrying a previous session's list over means closing Home re-enables
-- interfaces the current experience never had open.
env.cachedInGameUI = {}
env.cachedCoreUI = {}

-- Malicious Behavior Prevention
--
-- Both interception hooks replace a global, so a second execution would otherwise wrap
-- Altair' own wrapper and show one prompt per run. The pristine functions are stashed under
-- a sentinel on first run and re-read on every run after that, so re-executing is idempotent.
local indexSetClipboard = "setclipboard"

-- Widened to match Rayfield: several executors only expose their request function under a
-- namespace, and the old two-entry check left originalRequest nil on those.
local index = (http_request and "http_request") or "request"
local rawRequest = optional(env.request) or optional(env.http_request) or optional(env.http and env.http.request) or optional(env.syn and env.syn.request) or optional(env.fluxus and env.fluxus.request) or optional(request) or optional(http_request)

if env.altairOriginals == nil then
	env.altairOriginals = {
		request = rawRequest,
		setclipboard = env[indexSetClipboard],
	}
end

if not optional(env.altairOriginals.request) then env.altairOriginals.request = rawRequest end
local originalRequest = optional(env.altairOriginals.request)
local originalSetClipboard = env.altairOriginals.setclipboard

if not legacyChatActive then
	altairValues.chatSpy.enabled = false
end

-- Call External Modules

-- httpRequest
local httpRequest = originalRequest

-- Altair Functions
-- Loads and executes a function hosted on a remote URL, cancelling the request if the URL
-- takes too long to respond. Ported from Rayfield so a slow CDN can't stall startup.
local function loadWithTimeout(url, timeout)
	assert(type(url) == "string", "Expected string, got " .. type(url))
	timeout = timeout or 5
	local requestCompleted = false
	local success, result = false, nil

	local requestThread = task.spawn(function()
		local fetchSuccess, fetchResult = pcall(game.HttpGet, game, url)
		-- A "successful" request can still come back empty
		if not fetchSuccess or #fetchResult == 0 then
			if fetchSuccess and #fetchResult == 0 then
				fetchResult = "Empty response"
			end
			success, result = false, fetchResult
			requestCompleted = true
			return
		end

		local execSuccess, execResult = pcall(function()
			return loadstring(fetchResult)()
		end)
		success, result = execSuccess, execResult
		requestCompleted = true
	end)

	local timeoutThread = task.delay(timeout, function()
		if not requestCompleted then
			warn("Altair | Request for " .. url .. " timed out after " .. tostring(timeout) .. " seconds")
			task.cancel(requestThread)
			result = "Request timed out"
			requestCompleted = true
		end
	end)

	while not requestCompleted do
		task.wait()
	end

	if coroutine.status(timeoutThread) ~= "dead" then
		task.cancel(timeoutThread)
	end

	if not success then
		warn("Altair | Failed to process " .. tostring(url) .. ": " .. tostring(result))
		return nil
	end

	return result
end

-- Every connection Altair opens is registered here so teardown can close all of them at once.
local function track(connection)
	table.insert(connections, connection)
	return connection
end

-- Case-insensitive literal replace. string.gsub treats its needle as a Lua pattern, so names
-- containing -, ., ( or % broke or errored; this walks plain-text matches instead.
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

-- Shortens a value for display only. The stored value is never overwritten with the result.
local function truncateForDisplay(value, limit)
	local text = tostring(value)
	limit = limit or 24
	if #text <= limit then
		return text
	end
	return string.sub(text, 1, limit - 2) .. ".."
end

-- Enum.KeyCode[name] throws on an unknown or nil name. A cleared keybind stores nil, so the two
-- unguarded lookups at the bottom of InputBegan used to throw on *every* keypress, taking out
-- all keybinds, the smartBar toggle and ScriptSearch with them.
local function keyCodeFromName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local success, keyCode = pcall(function()
		return Enum.KeyCode[name]
	end)
	return success and keyCode or nil
end

-- Shared by Character action buttons and keybinds so both paths animate identically.
local function applyActionVisual(action, object)
	if not (action and object) then
		return
	end

	local quickToggle = object.Parent == characterPanel.Interactions.Toggles
	object.Icon.Image = "rbxassetid://" .. action.images[action.enabled and 1 or 2]
	if quickToggle then
		object.Subtitle.Text = action.enabled and "Enabled" or "Disabled"
	end
	-- Delayed action resets and keybinds must not reverse a panel fade.
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
	return UI.Parent
end

local function getPing()
	local success, ping = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return success and math.clamp(ping, 10, 700) or 0
end

-- Parents are created before their children; the old ordering made Assets/Icons first, which
-- failed on executors that don't create intermediate directories and then skipped Assets
-- entirely on the ones that do.
local function checkFolder()
	if not (isfolder and makefolder) then
		return
	end

	local root = altairValues.altairFolder
	local customRoot = root .. "/" .. altairValues.customScriptsFolder
	local scriptsRoot = root .. "/" .. altairValues.scriptsFolder

	for _, path in ipairs({
		root,
		root .. "/Music",
		root .. "/Assets",
		root .. "/Assets/Icons",
		customRoot,
		scriptsRoot,
	}) do
		if not isfolder(path) then
			makefolder(path)
		end
	end

	if writefile and isfile and not isfile(root .. "/Music/readme.txt") then
		writefile(root .. "/Music/readme.txt", "Hey there! Place your MP3 or other audio files in this folder, and have the ability to play them through the Altair Music UI!")
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
	return not table.find({ "Home", "Music", "Settings" }, name)
end

local function storeOriginalText(element)
	if originalTextValues[element] == nil then
		originalTextValues[element] = element.Text
	end
end

local function undoAnonymousChanges()
	for element, originalText in pairs(originalTextValues) do
		element.Text = originalText
	end
end

local function isHighlightEnabledFor(playerName)
	return altairValues.actions[7].enabled or locatedPlayers[playerName] == true
end

local function createEsp(player)
	if player == localPlayer or not checkAltair() then
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

-- Looks up the Character button for an action. The old checkAction matched the *setting* name against
-- the *action* name and always returned a table even on a miss, so callers' `if action then`
-- guard never fired. Two names never matched ('NoClip' vs 'Noclip', 'ESP' vs 'Extrasensory
-- Perception'), which meant those keybinds threw on every press.
local function actionButton(action)
	if not action then
		return nil
	end
	return characterPanel.Interactions.Toggles:FindFirstChild(action.name) or characterPanel.Interactions.Grid:FindFirstChild(action.name)
end

-- The category-scoped form used to `return` after examining the first category regardless of
-- whether it matched, so scoped lookups only worked when the target happened to be first.
local function checkSetting(settingTarget, categoryTarget)
	for _, category in ipairs(altairSettings) do
		if not categoryTarget or category.name == categoryTarget then
			for _, setting in ipairs(category.categorySettings) do
				if setting.name == settingTarget then
					return setting
				end
			end
		end
	end

	return nil
end

-- Every checkSetting caller immediately reads .current, so a typo'd or removed name used to
-- throw at the call site. Callers get a stable default instead.
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
		-- ClassName / GetDescendants; the lowercase aliases are deprecated legacy spellings
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
	if not value then
		if lighting:FindFirstChild("AltairBlur") then
			lighting:FindFirstChild("AltairBlur"):Destroy()
		end
	else
		if not lighting:FindFirstChild("AltairBlur") then
			local blurLight = Instance.new("DepthOfFieldEffect", lighting)
			blurLight.Name = "AltairBlur"
			blurLight.Enabled = true
			blurLight.FarIntensity = 0
			blurLight.FocusDistance = 51.6
			blurLight.InFocusRadius = 50
			blurLight.NearIntensity = 0.8
		end
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
			--newNotification.Time.Text = "now"

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

			if not tonumber(Image) then
				newNotification.Icon.Image = "rbxassetid://14317577326"
			else
				newNotification.Icon.Image = "rbxassetid://" .. tostring(Image)
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
			--tweenService:Create(newNotification.Time, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { TextTransparency = 0.5 }):Play()

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


-- Rainbow Mode
do
	local bar, hue, enabled = UI.SmartBar, 0, false
	local toggleColor = toggle.ImageColor3
	local toastColors = setmetatable({}, {__mode = "k"})
	local borderColors = {}
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
		if not UI.Parent or not bar:IsDescendantOf(UI) then return end
		local rainbow = settingValue("Rainbow Mode", false)
		if rainbow or enabled then
			hue = (os.clock() / 8) % 1
			local color = rainbow and Color3.fromHSV(hue, 0.65, 0.8) or Color3.new(1,1,1)

			
			for _, root in ipairs({homeContainer, characterPanel}) do
                for _, object in ipairs(root:GetDescendants()) do
                    border(object)
                    local original = borderColors[object]
                    if original then
                        object[original[1]] = rainbow and color or object:GetAttribute("AltairBaseColor") or original[2]
                        if object:IsA("UIStroke") then
                            local gradient=object:FindFirstChildOfClass("UIGradient")
                            if gradient then
                                if gradient:GetAttribute("AltairBaseEnabled")==nil then gradient:SetAttribute("AltairBaseEnabled",gradient.Enabled) end
                                gradient.Enabled=not rainbow and gradient:GetAttribute("AltairBaseEnabled")
                            end
                        end
                    end
                end
            end
            for object in pairs(borderColors) do
                if not object:IsDescendantOf(UI) then borderColors[object] = nil end
            end
            -- Tint the existing slider fill, knob and soft glow; keep animation transparency intact.
            for _,slider in ipairs(characterPanel.Interactions.Sliders:GetChildren()) do
                local progress=slider:FindFirstChild("Progress")
                if progress then
                    local function tint(object,property,value)
                        local key="AltairSlider"..property
                        if object:GetAttribute(key)==nil then object:SetAttribute(key,object[property]) end
                        object[property]=rainbow and value or object:GetAttribute(key)
                    end
                    local gradient=progress:FindFirstChildOfClass("UIGradient")
                    tint(progress,"BackgroundColor3",gradient and Color3.new(1,1,1) or color)
                    if gradient then
                        tint(gradient,"Color",ColorSequence.new(Color3.fromHSV((hue+.12)%1,.8,1),Color3.fromHSV(hue,.8,1)))
                    end
                    local knob=progress:FindFirstChild("Knob")
                    if knob then
                        tint(knob,"BackgroundColor3",Color3.fromHSV(hue,.8,1))
                        local glow=knob:FindFirstChild("Glow")
                        if glow then tint(glow,"ImageColor3",Color3.fromHSV(hue,.8,1)) end
                    end
                end
            end
			local smartBarColor = blinkState.color or (rainbow and color or Color3.new(1, 1, 1))
			bar.Shadow.ImageColor3 = smartBarColor
			bar.CircleGradient.ImageColor3 = smartBarColor
			bar.UIStroke.Color = smartBarColor
			bar.Back.UIStroke.Color = smartBarColor
			toggle.ImageColor3 = rainbow and color or toggleColor

			if rainbow then
				for _, toast in ipairs(activeToasts) do
					local title = toast:FindFirstChild("Title")
					if title then
						if toastColors[title] == nil then toastColors[title] = title.TextColor3 end
						title.TextColor3 = color
					end
				end
			else
				for title, original in pairs(toastColors) do
					if title.Parent then title.TextColor3 = original end
				end
			end
		end
		enabled = rainbow
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

					-- SmartBar's normal non-rainbow colour is white. If Rainbow Mode
					-- was disabled while this blink was running, do not restore the
					-- rainbow colour captured at blink start.
					object[state[3]] = rainbow and state[4] or Color3.new(1, 1, 1)
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
						-- Flash in.
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

						-- Flash out.
						blinkState.color = nil

						for object, state in pairs(activeSaved) do
							if object.Parent then
								local transparency =
									object == bar.Back.UIStroke
									and math.min(state[2], 0.8)
									or state[2]

								tweenService:Create(object, tweenInfo, {
									[state[1]] = transparency,
									[state[3]] = state[4],
								}):Play()
							end
						end

						task.wait(0.5)
					end

					-- Hard restore after every queued request.
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
	local template = UI.Toasts.Template:Clone()
	template.Parent, template.Title.Text, template.Title.TextColor3, template.Title.Font = UI.Toasts, content, color or Color3.fromRGB(240, 240, 240), font or Enum.Font.GothamSemibold
	template.Visible, template.BackgroundTransparency, template.Title.TextTransparency, template.Title.TextStrokeTransparency, template.Title.FontFace = true, 1, 1, 0.3, Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
	template.Title.MaxVisibleGraphemes = 0

	table.insert(activeToasts, 1, template)

	local startupSound = Instance.new("Sound")
	startupSound.Parent, startupSound.SoundId, startupSound.Name, startupSound.Volume, startupSound.PlayOnRemove = UI, "rbxassetid://255881176", "Toast", 0.85, true
	startupSound:Destroy()

	if #activeToasts == 1 then
		tweenService:Create(UI.SmartBar.CircleGradient, TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0.7}):Play()
	end

	-- Keep the existing fade/position entrance, with a typewriter reveal layered
	-- on top. MaxVisibleGraphemes leaves the full Text intact, so sizing/layout
	-- does not jump around while the message is being typed.
	tweenService:Create(template.Title, TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0.01 * (#activeToasts - 1), 0), TextTransparency = 0, TextStrokeTransparency = 0.3}):Play()

	task.spawn(function()
		local length = utf8.len(content) or #content
		local delay = math.clamp(1.15 / math.max(length, 1), 0.012, 0.035)

		for i = 1, length do
			if not template.Parent or template:GetAttribute("AltairExiting") then return end
			template.Title.MaxVisibleGraphemes = i
			task.wait(delay)
		end

		if template.Parent then
			template.Title.MaxVisibleGraphemes = -1
		end
	end)

	if not skipBlink then
		BlinkSmartBar(1, color)
	end

	task.spawn(function()
		task.wait(7)
		if not template.Parent then return end
		template:SetAttribute("AltairExiting", true)
		template.Title.MaxVisibleGraphemes = -1

		-- Slightly slower than the old 1.5s exit so the toast eases upward and
		-- fades away instead of disappearing as abruptly.
		tweenService:Create(template.Title, TweenInfo.new(2.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, -0.5, 0), TextTransparency = 1, TextStrokeTransparency = 1}):Play()
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

--------------------------------------------------------------------------------
-- Custom script detection
--------------------------------------------------------------------------------

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

					-- Migrate legacy files named with PlaceIds, such as
					-- 286090429.altair, to a readable game-name filename.
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

	-- ScriptTitle is NOT inside Layer. Its actual path in the Altair asset is:
	-- GameDetection.ScriptTitle.Text
	--
	-- Resolve the CURRENT PlaceId every time the prompt opens so this can never
	-- reuse a stale title from another experience/session.
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

	-- Preserve the asset's authored transparency values once. The prompt then
	-- fades to those exact values rather than flattening every element to zero.
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

			-- Custom-script URLs are intentionally executed using the normal
			-- executor pattern:
			--
			-- loadstring(game:HttpGet(url))()
			--
			-- Some executors are more reliable with the colon-form HttpGet call
			-- than invoking game.HttpGet as an unbound function through pcall.
			if not loadstring then
				Toast("This executor doesn't support loadstring.", Color3.fromRGB(255, 90, 90))
				return
			end

			if not (url:match("^https?://")) then
				Toast("The custom script Loadstring must be a raw http(s) URL.", Color3.fromRGB(255, 90, 90))
				return
			end

			local ok, err = pcall(function()
				loadstring(game:HttpGet(url))()
			end)

			if not ok then
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

			-- A simple filename is resolved from Altair/Scripts.
			-- If NO extension is supplied, .lua is the default.
			-- If an extension is explicitly supplied (.Lua, .txt, .luau, etc.),
			-- preserve it exactly instead of appending another extension.
			local normalizedPath = path:gsub(string.char(92), "/")
			if not normalizedPath:find("/", 1, true) then
				if not normalizedPath:match("%.[^/%.]+$") then
					path ..= ".lua"
				end

				local scriptsRoot = altairValues.altairFolder .. "/" .. altairValues.scriptsFolder
				local requestedName = path
				path = scriptsRoot .. "/" .. requestedName

				-- Some executor filesystems are case-sensitive. Resolve the filename
				-- case-insensitively so Arsenal.lua, Arsenal.Lua and ARSENAL.LUA all
				-- refer to the same file when one exists.
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
			Toast("The custom script couldn't be compiled.", Color3.fromRGB(255, 90, 90))
			return
		end

		local runOk, runError = pcall(chunk)
		if not runOk then
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

	-- Fade out without destroying the prompt's authored transparency values.
	-- In particular, the TextBoxes are intentionally transparent in the asset;
	-- forcing every BackgroundTransparency to 0 caused the white rectangles.
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

	-- The current PlaceId is prefilled every time the prompt opens.
	-- The user can edit it normally; Submit falls back to the current PlaceId
	-- when this is left blank or contains no valid number.
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

	-- Cache every authored transparency once, then start hidden.
	-- Restoring to those cached values keeps transparent TextBoxes transparent
	-- instead of turning them into solid white GuiObjects.
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

	-- Normalize only for matching. The value saved by the user is otherwise left
	-- alone, so explicitly supplied extensions and paths are preserved.
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

	-- Refresh the definitions before checking for an existing source. A custom
	-- script is identified by its remote URL OR local Lua file, not by PlaceId.
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

		-- Canonicalize the supported-place list while leaving the original source
		-- field intact. This means a manually-created Url/File alias still works.
		definition.PlaceIds = mergedIds

		-- Only replace an existing description when the user actually typed one.
		-- Leaving the box blank keeps the existing description for multi-game hubs.
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

	-- No matching source exists yet, so create a new custom-script definition.
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

	-- If another unrelated definition already has this game name, keep both
	-- human-readable instead of falling back to a numeric PlaceId filename.
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

	for _, sound in ipairs(soundInstances) do
		if sound:FindFirstChild("AltairAudioProfile") then
			local reverb = sound:FindFirstChild("AltairAudioProfile")
			tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { HighGain = 0 }):Play()
			tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { LowGain = 0 }):Play()
			tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { MidGain = 0 }):Play()

			task.delay(timing + 0.03, reverb.Destroy, reverb)
		end
	end
end

-- Iterative rather than recursive: the old version called itself once per track, and because
-- that call wasn't in tail position the stack grew for the whole length of the queue.
local function playNext()
	playGeneration += 1
	local thisGen = playGeneration

	while true do
		if #musicQueue == 0 then
			if currentAudio then
				currentAudio.Playing = false
				currentAudio.SoundId = ""
			end
			musicPanel.Playing.Text = "Not Playing"
			return
		end

		if not currentAudio then
			local newAudio = Instance.new("Sound")
			newAudio.Parent = UI
			newAudio.Name = "Audio"
			currentAudio = newAudio
		end

		local entry = musicQueue[1]
		local assetSuccess, asset = pcall(getCustomAsset, altairValues.altairFolder .. "/Music/" .. entry.sound)

		if musicPanel.Queue.List:FindFirstChild(tostring(entry.instanceName)) then
			musicPanel.Queue.List:FindFirstChild(tostring(entry.instanceName)):Destroy()
		end

		if not assetSuccess or not asset then
			-- Unreadable file: drop it and move on instead of stalling the whole queue
			queueNotification("Unable to play file", entry.sound .. " could not be loaded and has been skipped.", 4370341699)
			table.remove(musicQueue, 1)
			continue
		end

		if settingValue("Now Playing Notifications") then
			queueNotification("Now Playing", entry.sound, 4400695581)
		end

		currentAudio.SoundId = asset
		musicPanel.Playing.Text = entry.sound
		currentAudio:Play()
		musicPanel.Menu.TogglePlaying.ImageRectOffset = currentAudio.Playing and Vector2.new(804, 124) or Vector2.new(764, 244)
		currentAudio.Ended:Wait()

		if thisGen ~= playGeneration then
			return
		end -- superseded by Next/skip; let the active call do the table.remove

		table.remove(musicQueue, 1)
	end
end

local function addToQueue(file)
	if not (getCustomAsset and isfile) then
		return
	end
	if not file or file == "" then
		return
	end
	checkFolder()
	if not isfile(altairValues.altairFolder .. "/Music/" .. file) then
		queueNotification("Unable to locate file", "Please ensure that your audio file is in the Altair/Music folder and that you are including the file extension (e.g mp3 or ogg).", 4370341699)
		return
	end
	musicPanel.AddBox.Input.Text = ""

	local newAudio = musicPanel.Queue.List.Template:Clone()
	newAudio.Parent = musicPanel.Queue.List
	newAudio.Size = UDim2.new(0, 254, 0, 40)
	newAudio.Close.ImageTransparency = 1
	newAudio.Name = file
	-- Measured against the filename, not the cloned template's placeholder text, which is what
	-- the old check read - so truncation fired off a constant instead of the actual length.
	if string.len(file) > 26 then
		newAudio.FileName.Text = string.sub(file, 1, 24) .. ".."
	else
		newAudio.FileName.Text = file
	end
	newAudio.Visible = true
	newAudio.Duration.Text = ""

	table.insert(musicQueue, { sound = file, instanceName = newAudio.Name })

	local lengthSuccess, lengthAsset = pcall(getCustomAsset, altairValues.altairFolder .. "/Music/" .. file)
	if lengthSuccess and lengthAsset then
		local getLength = Instance.new("Sound")
		getLength.Parent = workspace
		getLength.SoundId = lengthAsset
		getLength.Volume = 0
		getLength:Play()
		task.wait(0.05)
		if newAudio.Parent then
			newAudio.Duration.Text = tostring(math.round(getLength.TimeLength)) .. "s"
		end
		getLength:Stop()
		getLength:Destroy()
	end

	newAudio.MouseEnter:Connect(function()
		tweenService:Create(newAudio, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { BackgroundColor3 = Color3.fromRGB(100, 100, 100) }):Play()
		tweenService:Create(newAudio.Close, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { ImageTransparency = 0 }):Play()
		tweenService:Create(newAudio.Duration, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { TextTransparency = 1 }):Play()
	end)

	newAudio.MouseLeave:Connect(function()
		tweenService:Create(newAudio.Close, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { ImageTransparency = 1 }):Play()
		tweenService:Create(newAudio, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { BackgroundColor3 = Color3.fromRGB(0, 0, 0) }):Play()
		tweenService:Create(newAudio.Duration, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), { TextTransparency = 0.7 }):Play()
	end)

	newAudio.Close.MouseButton1Click:Connect(function()
		-- The old version looped over every field of each queue entry. `sound` and `instanceName`
		-- hold the same filename, so each match fired twice and removed two entries - silently
		-- dropping the following track. One indexed pass, matched on one field, with a break.
		local removedIndex
		for i = 1, #musicQueue do
			if musicQueue[i].instanceName == newAudio.Name then
				removedIndex = i
				break
			end
		end

		if not removedIndex then
			newAudio:Destroy()
			return
		end

		local wasPlaying = removedIndex == 1 and currentAudio ~= nil and currentAudio.Playing

		table.remove(musicQueue, removedIndex)
		newAudio:Destroy()

		-- Only restart playback when the track we removed is the one currently playing
		if wasPlaying then
			task.spawn(playNext)
		end
	end)

	if #musicQueue == 1 then
		playNext()
	end
end

local function openMusic()
	if homeOpen then closeHome() end
	debounce = true
	musicPanel.Visible = true
	musicPanel.Queue.List.Template.Visible = false

	debounce = false
end

local function closeMusic()
	debounce = true
	musicPanel.Visible = false

	debounce = false
end

local function createReverb(timing)
	for _, sound in ipairs(soundInstances) do
		if not sound:FindFirstChild("AltairAudioProfile") then
			local reverb = Instance.new("EqualizerSoundEffect")

			reverb.Name = "AltairAudioProfile"
			reverb.Parent = sound

			reverb.Enabled = false

			reverb.HighGain = 0
			reverb.LowGain = 0
			reverb.MidGain = 0
			reverb.Enabled = true

			if timing then
				tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { HighGain = -20 }):Play()
				tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { LowGain = 5 }):Play()
				tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { MidGain = -20 }):Play()
			end
		end
	end
end

-- Experience Sync (the per-experience game scripts) was removed: altairValues.rawTree pointed
-- at a branch of this repo that no longer exists, so every fetch 404'd. The creator identity it
-- populated is now resolved directly, because Moderator Detection reads it and previously never
-- saw it set - Experience Sync was disabled, so the detection could never fire.
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
			-- White base avoids multiplying the gradient by the action color twice.
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

	-- The character can exist without a Humanoid mid-spawn; indexing straight through used to
	-- throw here, which aborted start() and left the whole interface half-built.
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

local function checkTools()
	task.wait(0.03)
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local character = localPlayer.Character

	-- Used to fall off the end returning nil when a backpack existed but held no tools
	return (backpack and backpack:FindFirstChildOfClass("Tool") ~= nil) or (character and character:FindFirstChildOfClass("Tool") ~= nil) or false
end

-- One owner for backpack and toast positions; all offsets come from rendered bounds.
local updateBackpackLayout
do
	local entries, activePanel, refresh, toastOffset = {}, nil, 0, 30
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
		for _, root in ipairs({coreGui, localPlayer:FindFirstChildOfClass("PlayerGui")}) do
			for _, v in ipairs(root:GetDescendants()) do
				local name = v.Name:lower()
				if v:IsA("GuiObject") and not v:IsDescendantOf(UI) and (name:find("backpack", 1, true) or name:find("hotbar", 1, true)) and visible(v) then found[v] = true end
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
				entries[v] = {position = coreBackpack and UDim2.new(0,0,0,0) or v.Position, shift = 0, core = coreBackpack}
			elseif not smartBarOpen and entries[v].shift == 0 and not entries[v].core then
				entries[v].position = v.Position
			end
			-- Move the outer container once, but measure its hotbar rather than a full-screen wrapper.
			local bounds, hasHotbar = nil, false
			for _, candidate in ipairs(v:GetDescendants()) do
				if candidate:IsA("GuiObject") and candidate.Name:lower():find("hotbar", 1, true) then
					hasHotbar = true
					if visible(candidate) and candidate.AbsoluteSize.Y > 0 and (not bounds or candidate.AbsoluteSize.Y < bounds.AbsoluteSize.Y) then bounds = candidate end
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
	local connection = track(runService.RenderStepped:Connect(function(dt)
		if not UI.Parent then return end
		refresh -= dt
		if refresh <= 0 then scan() refresh = 0.5 end
		local ceiling = smartBarOpen and smartBar.AbsolutePosition.Y or nil
		if smartBarOpen and activePanel and activePanel.Parent and activePanel.Visible then ceiling = math.min(ceiling, activePanel.AbsolutePosition.Y) end
		for _, panel in ipairs({musicPanel, settingsPanel, scriptSearch}) do
			if panel.Parent and visible(panel) then ceiling = math.min(ceiling or math.huge, panel.AbsolutePosition.Y) end
		end
		local hotbarTop, alpha = nil, 1 - math.exp(-14 * dt)
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
					v.Position = entry.shift == 0 and entry.position or entry.position - UDim2.new(0,0,entry.shift / height,0)
				end
				hotbarTop = math.min(hotbarTop or math.huge, restingTop - entry.shift)
			end
		end
		-- Live toast clones have different positions from the hidden template.
		-- Keep the lowest active text above Altair's toggle button; let exiting text animate freely.
		local measured
		for _, toast in ipairs(activeToasts) do
			local title = toast.Parent and not toast:GetAttribute("AltairExiting") and toast:FindFirstChild("Title")
			if title and title:IsA("TextLabel") and title.Visible and title.AbsoluteSize.Y > 0 then
				local textHeight = math.min(title.AbsoluteSize.Y, math.max(title.TextBounds.Y, title.TextSize))
				local extra = title.TextYAlignment == Enum.TextYAlignment.Top and textHeight or title.TextYAlignment == Enum.TextYAlignment.Bottom and title.AbsoluteSize.Y or (title.AbsoluteSize.Y + textHeight) / 2
				local bottom = title.AbsolutePosition.Y - toastsContainer.AbsolutePosition.Y + extra
				measured = math.max(measured or -math.huge, bottom)
			end
		end
		if measured then toastOffset = measured end

		local toggleVisible = toggle.Parent and visible(toggle) and toggle.AbsoluteSize.Y > 0
		local boundary = toggleVisible and toggle.AbsolutePosition.Y or hotbarTop or ceiling
		local targetTop = boundary and boundary - 14 - toastOffset or UI.AbsolutePosition.Y + UI.AbsoluteSize.Y - 28
		targetTop = math.max(UI.AbsolutePosition.Y + 8, targetTop)
		local delta = targetTop - toastsContainer.AbsolutePosition.Y
		-- Track the toggle exactly while it animates; ease only when the toggle is unavailable.
		toastsContainer.Position += UDim2.new(0,0,delta * ((toggleVisible or hotbarTop) and 1 or alpha) / parentHeight(toastsContainer),0)
	end))
	UI.Destroying:Connect(function()
		connection:Disconnect()
		for v, entry in pairs(entries) do if v.Parent and entry.shift > 0 then v.Position = entry.position end end
	end)
end

local function closePanel(panelName, openingOther)
	local button = smartBar.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	-- Guards run before debounce is claimed. Bailing out after setting it left the flag stuck
	-- true, which locks every panel, Home, Settings, Music and ScriptSearch for the session.
	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end

	debounce = true

	local panelSize = panel.Name == "Character" and characterPanelSize or UDim2.fromOffset(581, 246)

	if not openingOther then
		if panel.Name == "Character" then -- Character Panel Animation
			tweenService:Create(characterPanel.Subtitle, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(characterPanel.Pointer, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
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
			for _, playerIns in ipairs(playerlistPanel.Interactions.List:GetDescendants()) do
				if playerIns.ClassName == "Frame" then
					tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
				elseif playerIns.ClassName == "TextLabel" or playerIns.ClassName == "TextButton" then
					tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
				elseif playerIns.ClassName == "ImageLabel" or playerIns.ClassName == "ImageButton" then
					tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
					if playerIns.Name == "Avatar" then
						tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
					end
				elseif playerIns.ClassName == "UIStroke" then
					tweenService:Create(playerIns, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
				end
			end

			tweenService:Create(playerlistPanel.Interactions.SearchFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.Icon, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.SearchBox, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.SearchFrame.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(playerlistPanel.Interactions.List, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ScrollBarImageTransparency = 1 }):Play()
		end

		tweenService:Create(panel.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		tweenService:Create(panel.Title, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(panel.UIStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
		tweenService:Create(panel.Shadow, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		task.wait(0.03)

		tweenService:Create(panel, TweenInfo.new(0.75, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(panel, TweenInfo.new(1.1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), { Size = button.Size }):Play()
		tweenService:Create(panel, TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), { Position = altairValues.buttonPositions[panelName] }):Play()
		tweenService:Create(toggle, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 1, -70) }):Play()
	end

	-- Animate interactive elements
	if openingOther then
		tweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 350, 1, -90) }):Play()
		wipeTransparency(panel, 1, true, true, 0.3)
	end

	task.wait(0.5)
	panel.Size = panelSize
	panel.Visible = false
	if not openingOther then updateBackpackLayout() end

	debounce = false
end

local function openPanel(panelName)
	if homeOpen then closeHome() end
	if debounce then
		return
	end
	local button = smartBar.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	-- Same as closePanel: never claim the debounce before the guards have passed
	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end

	debounce = true

	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Buttons:FindFirstChild(otherPanel.Name) then
			if isPanel(otherPanel.Name) and otherPanel.Visible then
				task.spawn(closePanel, otherPanel.Name, true)
				task.wait()
			end
		end
	end

	local panelSize = panel.Name == "Character" and characterPanelSize or UDim2.fromOffset(581, 246)

	panel.Size = button.Size
	panel.Position = altairValues.buttonPositions[panelName]

	wipeTransparency(panel, 1, true)

	panel.Visible = true

	updateBackpackLayout(panel)
	tweenService:Create(toggle, TweenInfo.new(0.65, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -(panelSize.Y.Offset + 91)) }):Play()

	tweenService:Create(panel, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
	tweenService:Create(panel, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), { Size = panelSize }):Play()
	tweenService:Create(panel, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -90) }):Play()
	task.wait(0.1)
	tweenService:Create(panel.Shadow, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
	tweenService:Create(panel.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	task.wait(0.05)
	tweenService:Create(panel.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(panel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.95 }):Play()
	task.wait(0.05)

	-- Animate interactive elements
	if panel.Name == "Character" then -- Character Panel Animation
		tweenService:Create(characterPanel.Shadow, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0.55 }):Play()
		tweenService:Create(characterPanel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.7 }):Play()
		tweenService:Create(characterPanel.Subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Pointer, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
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
		for _, playerIns in ipairs(playerlistPanel.Interactions.List:GetDescendants()) do
			if playerIns.Name ~= "Interact" and playerIns.Name ~= "Role" then
				if playerIns.ClassName == "Frame" then
					tweenService:Create(playerIns, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
				elseif playerIns.ClassName == "TextLabel" or playerIns.ClassName == "TextButton" then
					tweenService:Create(playerIns, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
				elseif playerIns.ClassName == "ImageLabel" or playerIns.ClassName == "ImageButton" then
					tweenService:Create(playerIns, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
					if playerIns.Name == "Avatar" then
						tweenService:Create(playerIns, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
					end
				elseif playerIns.ClassName == "UIStroke" then
					tweenService:Create(playerIns, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
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
	end

	task.wait(0.45)
	debounce = false
end

local function rejoin()
	queueNotification("Rejoining Session", "We're queueing a rejoin to this session, give us a moment.", 4400696294)

	if #players:GetPlayers() <= 1 then
		task.wait()
		teleportService:Teleport(placeId, localPlayer)
	else
		teleportService:TeleportToPlaceInstance(placeId, jobId, localPlayer)
	end
end

local function serverhop()
	local highestPlayers = 0
	local target

	-- A rate-limited or offline games API used to throw straight out of the click handler
	local success, response = pcall(function()
		return httpService:JSONDecode(game:HttpGetAsync("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"))
	end)

	if not success or not response or not response.data then
		return queueNotification("Unable to find servers", "Altair couldn't reach the Roblox server list, this is usually rate limiting. Try again in a moment.", 4370317928)
	end

	for _, v in ipairs(response.data) do
		if type(v) == "table" and v.maxPlayers > v.playing and v.id ~= jobId then
			if v.playing > highestPlayers then
				highestPlayers = v.playing
				target = v.id
			end
		end
	end

	if not target then
		return queueNotification("No Servers Found", "We couldn't find another server, this may be the only server.", 4370317928)
	end

	queueNotification("Teleporting", "We're now moving you to the new session, this may take a few seconds.", 4335479121)
	task.wait(0.3)

	local hopped = pcall(teleportService.TeleportToPlaceInstance, teleportService, placeId, target)
	if not hopped then
		queueNotification("Teleport Failed", "Roblox refused the teleport to that server. Try again in a moment.", 4370317928)
	end
end

-- game:Shutdown() is a server method; client availability depends entirely on the executor and
-- it was being called bare from two user-facing buttons. Fall back to the home page.
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
	UI.Enabled = true
	characterPanel.Visible = false
	customScriptPrompt.Visible = false
	disconnectedPrompt.Visible = false
	playerlistPanel.Interactions.List.Template.Visible = false
	gameDetectionPrompt.Visible = false
	homeContainer.Visible = false
	moderatorDetectionPrompt.Visible = false
	musicPanel.Visible = false
	notificationContainer.Visible = true
	playerlistPanel.Visible = false
	scriptSearch.Visible = false
	scriptsPanel.Visible = false
	settingsPanel.Visible = false
	smartBar.Visible = false
	musicPanel.Playing.Text = "Not Playing"
	-- Music needs getcustomasset to load local files at all
	if not getCustomAsset then
		smartBar.Buttons.Music.Visible = false
	end
	toastsContainer.Visible = true
	makeDraggable(settingsPanel)
	makeDraggable(musicPanel)
end

-- Connected once at load. These used to be wired up inside promptModerator, so after N
-- detections a single click on Leave fired N times.

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

	-- Assume a hop is possible and correct it once the server list lands. Blocking the prompt
	-- on an unguarded HTTP call meant a rate-limited response threw and left it half-drawn.
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
-- Home: layout setup, data, then the editable open/close tweens.

local homeBlur = Instance.new("BlurEffect")
homeBlur.Name, homeBlur.Size, homeBlur.Parent = "AltairHomeBlur", 0, lighting
-- Group fades leave every template's original transparency intact.
local function canvasGroup(frame)
 if frame:IsA("CanvasGroup") then return frame end
 local group=Instance.new("CanvasGroup")
 for _,property in ipairs({"Name","Size","Position","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderSizePixel","Visible","ZIndex","LayoutOrder"}) do group[property]=frame[property] end
 for name,value in pairs(frame:GetAttributes()) do group:SetAttribute(name,value) end
 for _,child in ipairs(frame:GetChildren()) do child.Parent=group end
 -- A UIGradient on CanvasGroup tints its entire rendered contents.
 -- Keep the authored gradient on a separate background, behind the content.
 local gradient=group:FindFirstChildOfClass("UIGradient")
 if gradient then
  local background=Instance.new("Frame")
  background.Name="CardBackground" background.Size=UDim2.fromScale(1,1)
  background.BackgroundColor3=group.BackgroundColor3 background.BackgroundTransparency=group.BackgroundTransparency
  background.BorderSizePixel=0 background.ZIndex=0
  local corner=group:FindFirstChildOfClass("UICorner") if corner then corner:Clone().Parent=background end
  gradient.Parent=background background.Parent=group group.BackgroundTransparency=1
 end
 group.Parent=frame.Parent frame:Destroy()
 return group
end
UI.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
homeContainer.Size=UDim2.fromScale(1,1)
homeContainer.Position=UDim2.fromScale(.5,.5)
homeContainer.AnchorPoint=Vector2.new(.5,.5)
homeContainer.BackgroundTransparency=1
homeContainer.Dim.Size=UDim2.fromScale(1,1)
homeContainer.Dim.Position=UDim2.fromOffset(0,0)
homeContainer.Dim.Visible=true
homeContainer.Dim.BackgroundTransparency=1
local homeContent=Instance.new("CanvasGroup")
homeContent.Name="Content" homeContent.Size=UDim2.fromOffset(1104,650)
homeContent.AnchorPoint=Vector2.new(.5,.5) homeContent.Position=UDim2.fromScale(.5,.5)
homeContent.BackgroundTransparency=1 homeContent.GroupTransparency=1 homeContent.ZIndex=20 homeContent.Parent=homeContainer
homeContainer.Sidebar.Parent=homeContent homeContainer.Pages.Parent=homeContent
homeContent.Sidebar.Position=UDim2.fromOffset(32,80) homeContent.Sidebar.AnchorPoint=Vector2.zero
homeContent.Pages.Position=UDim2.fromOffset(32,130) homeContent.Pages.AnchorPoint=Vector2.zero
for _,page in ipairs(homeContent.Pages:GetChildren()) do
 if page:IsA("Frame") then page=canvasGroup(page) end
 page.Size=page.Size+UDim2.fromOffset(24,24)
 local padding=Instance.new("UIPadding",page)
 padding.PaddingLeft=UDim.new(0,12) padding.PaddingRight=UDim.new(0,12)
 padding.PaddingTop=UDim.new(0,12) padding.PaddingBottom=UDim.new(0,12)
 if page:FindFirstChild("Details") then canvasGroup(page.Details) end
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
   -- Preserve the unreadable file before the first write; do not discard it silently.
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
 -- Volt's request is ordinary HTTP; it is not a signed-in Roblox presence session.
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
 function friendActivity.normalize(friend,online,presence,inServer)
  local positive,nonempty=friendActivity.positive,friendActivity.string
  local nativePlace=positive(online and online.PlaceId)
  -- Legacy native LocationType is a different enum from web userPresenceType.
  local nativeType=tonumber(online and online.LocationType)
  local inStudio=online and (nativeType==3 or nativeType==6)
  local nativePlaying=nativeType==1 or nativeType==4 or (nativeType==nil and nativePlace>0)
  local webPlace=positive(presence and presence.placeId)
  local status=presence and tonumber(presence.userPresenceType)
  local f={id=tonumber(friend.Id),username=friend.Username or friend.Name or tostring(friend.Id),displayName=friend.DisplayName or friend.Username or tostring(friend.Id),checkedAt=os.clock()}
  f.placeId=nativePlace>0 and nativePlace or webPlace
  f.universeId=positive(online and online.UniverseId)
  if f.universeId==0 and (nativePlace==0 or webPlace==0 or webPlace==nativePlace) then f.universeId=positive(presence and presence.universeId) end
  f.jobId=nonempty(online and online.GameId)
  if tonumber(f.jobId) then f.jobId='' end -- A numeric legacy GameId is not a server instance ID.
  if f.jobId=='' and (nativePlace==0 or nativePlace==webPlace) then f.jobId=nonempty(presence and presence.gameId) end
  if tonumber(f.jobId) then f.jobId='' end
  f.location=nonempty(online and online.LastLocation)
  if f.location=='' and (nativePlace==0 or nativePlace==webPlace) then f.location=nonempty(presence and presence.lastLocation) end
  if inServer then
   f.presence='InGame' f.placeId=game.PlaceId f.universeId=game.GameId f.jobId=game.JobId f.location=placeName or 'This experience' f.source='Current server'
  elseif online and online.IsOnline~=false then
   f.presence=not inStudio and (nativePlaying or nativeType==nil and status==2) and 'InGame' or 'Online' f.source='Roblox client'
  else
   f.presence=status==2 and 'InGame' or (status==1 or status==3) and 'Online' or status==0 and 'Offline' or 'Unknown'
   f.source=presence and 'Roblox presence' or 'Unavailable'
  end
  if f.presence~='InGame' then f.placeId=0 f.universeId=0 f.jobId='' end
  if inStudio then f.location='In Studio' end
  if f.location=='' then f.location=f.presence=='InGame' and ((f.placeId>0 or f.universeId>0) and 'Loading game...' or 'Game activity unavailable') or status==3 and 'In Studio' or f.presence=='Unknown' and 'Activity unavailable' or f.presence end
  if f.presence=='Online' and not inStudio then f.location='Online' end
  f.joinable=f.presence=='InGame' and f.placeId>0 and f.jobId~=''
  return f
 end
 function friendActivity.online()
  local result,err=bounded(function() return localPlayer:GetFriendsOnlineAsync(200) end,8)
  if type(result)~='table' then
   -- Compatibility fallback for executor/client builds exposing the older method.
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
 function friendActivity.joinButton(button,f)
  button.Visible=f.presence=='InGame'
  label(button,f.joinable and 'Join' or 'Unavailable')
  button.AutoButtonColor=f.joinable==true
 end
 function friendActivity.updateDetails(f)
  if not selectedFriend or selectedFriend.id~=f.id then return end
  local d=fp.Details
  text(d.Activity,'Status',f.presence=='InGame' and 'In Game' or f.presence)
  text(d.Activity,'GameName',f.location)
  d.Activity.GameIcon.Image=gameIcon(f.universeId)
  d.Activity.GameIcon.Visible=f.presence=='InGame' and f.universeId>0
  friendActivity.joinButton(d.Activity.Join,f)
  text(d,'Availability',f.presence=='InGame' and (f.joinable and 'Join this server' or 'No joinable server returned') or f.presence=='Unknown' and 'Activity unavailable' or f.presence)
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
   end
  end
  -- A universe resolved from a sub-place can newly match the current experience.
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
  -- Resolve a place once, with at most four outstanding metadata lookups.
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
  friendBusy=true lastFriends=os.clock() friendActivity.version+=1 local version=friendActivity.version
  if #friends==0 then state(fp.Browser,'Loading','Loading friends...') end
  task.spawn(function()
   local roster=friendActivity.roster local rosterError
   if not roster or os.clock()-friendActivity.rosterAt>300 then
    roster,rosterError=bounded(function()
     local result={} local seen={} local page=players:GetFriendsAsync(localPlayer.UserId)
     for _=1,100 do
      for _,f in ipairs(page:GetCurrentPage()) do local id=tonumber(f.Id) if id and not seen[id] then seen[id]=true table.insert(result,f) end end
      if page.IsFinished then return result end page:AdvanceToNextPageAsync()
     end
     error('Too many friend pages')
    end,25)
    if type(roster)~='table' then
     local result=getJSON('https://friends.roblox.com/v1/users/'..localPlayer.UserId..'/friends')
     if result and type(result.data)=='table' then roster={} for _,f in ipairs(result.data) do table.insert(roster,{Id=f.id,Username=f.name,DisplayName=f.displayName}) end end
    end
    if type(roster)=='table' then friendActivity.roster=roster friendActivity.rosterAt=os.clock() end
   end
   if not alive or friendActivity.version~=version then return end
   if type(roster)~='table' then friendBusy=false friendError=rosterError or 'Friends unavailable' renderFriends() return end
   local inServer={} for _,p in ipairs(players:GetPlayers()) do inServer[p.UserId]=true end
   local function publish(online,presence)
    if not alive or friendActivity.version~=version then return end
    local snapshot={}
    for _,f in ipairs(roster) do if tonumber(f.Id) then table.insert(snapshot,friendActivity.normalize(f,online and online[tonumber(f.Id)],presence and presence[tonumber(f.Id)],inServer[tonumber(f.Id)])) end end
    local rank={InGame=1,Online=2,Offline=3,Unknown=4}
    table.sort(snapshot,function(a,b) if rank[a.presence]~=rank[b.presence] then return rank[a.presence]<rank[b.presence] end return a.displayName:lower()<b.displayName:lower() end)
    friends=snapshot renderFriends()
    if selectedFriend then friendActivity.updateDetails(selectedFriend) end
    return snapshot
   end
   if #friends==0 then publish(nil,nil) end
   local presence={} local webDone=false local webError
   task.spawn(function()
    if originalRequest then for start=1,#roster,100 do
     if not alive or friendActivity.version~=version then break end
     local ids={} for index=start,math.min(start+99,#roster) do table.insert(ids,tonumber(roster[index].Id)) end
     local result,err=bounded(function()
      local response=originalRequest({Url='https://presence.roblox.com/v1/presence/users',Method='POST',Headers={['Content-Type']='application/json',Accept='application/json'},Body=httpService:JSONEncode({userIds=ids})})
      assert(type(response)=='table' and tonumber(response.StatusCode)==200,'Presence HTTP '..tostring(response and response.StatusCode))
      local decoded=httpService:JSONDecode(response.Body) assert(type(decoded.userPresences)=='table','Invalid presence response') return decoded
     end,8)
     if result then for _,p in ipairs(result.userPresences) do if tonumber(p.userId) then presence[tonumber(p.userId)]=p end end else webError=err break end
    end else webError='Volt HTTP request unavailable' end
    webDone=true
   end)
   local online,onlineError=friendActivity.online()
   if not alive or friendActivity.version~=version then return end
   -- Render the signed-in client's activity immediately; anonymous HTTP never delays it.
   local snapshot=publish(online,presence)
   friendActivity.enrich(snapshot,version)
   local deadline=os.clock()+9
   while not webDone and alive and os.clock()<deadline do task.wait(.05) end
   if not alive or friendActivity.version~=version then return end
   friendBusy=false friendError=nil
   friendActivity.refreshError=onlineError and (webError or not webDone) and 'Activity unavailable; retry shortly' or nil
   homeContainer:SetAttribute('FriendActivityClientStatus',online and 'OK' or tostring(onlineError))
   homeContainer:SetAttribute('FriendActivityHttpStatus',webDone and (webError or 'OK') or 'Timed out')
   snapshot=publish(online,presence)
   if friendActivity.refreshError then text(fp.Browser,'Subtitle',friendActivity.refreshError) else text(fp.Browser,'Subtitle','People you play with') end
   friendActivity.enrich(snapshot,version)
  end)
 end
 local joiningFriends={}
 local function joinFriend(f)
  if not f or joiningFriends[f.id] then return end
  joiningFriends[f.id]=true
  task.spawn(function()
   local online=friendActivity.online()
   if not alive then joiningFriends[f.id]=nil return end
   local sameServer=players:GetPlayerByUserId(f.id)~=nil
   local target=f
   if sameServer or (online and online[f.id]) then
    target=friendActivity.normalize({Id=f.id,Username=f.username,DisplayName=f.displayName},online and online[f.id],nil,sameServer)
   elseif online and f.source=='Roblox client' then
    target={joinable=false}
   elseif os.clock()-(f.checkedAt or 0)>45 then target={joinable=false} end
   joiningFriends[f.id]=nil
   if sameServer then queueNotification('Home','This friend is already in your server.',4370336704) return end
   if not target.joinable then queueNotification('Home','Roblox is not sharing a joinable server for this friend. Their activity or join visibility may be restricted.',4370336704) return end
   playGame(target,target.jobId)
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
  panel.GroupTransparency=1 panel.Position=position-UDim2.fromOffset(28,0)
  tweenService:Create(panel,TweenInfo.new(.6,Enum.EasingStyle.Quint),{GroupTransparency=0,Position=position}):Play()
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
 showPage=function(name)
  if not pages:FindFirstChild(name) then return end
  if activePage==name and opened and pages[name].Visible then return end
  activePage=name tabVersion+=1 local version=tabVersion
  homeContainer:SetAttribute('ActivePage',name) menu.Visible=false
  for _,button in ipairs(homeContent.Sidebar:GetChildren()) do if button:IsA('GuiButton') then
   button.BackgroundColor3=Color3.fromRGB(62,62,68)
   button.BackgroundTransparency=button.Name==name and .15 or 1
  end end
  local function reveal()
   if not alive or version~=tabVersion then return end
   for _,page in ipairs(pages:GetChildren()) do if page:IsA('CanvasGroup') then page.Visible=page.Name==name end end
   local page=pages[name] page.Position=UDim2.fromOffset(-40,-12) page.GroupTransparency=1
   tweenService:Create(page,TweenInfo.new(opened and .65 or 0,Enum.EasingStyle.Quint),{Position=UDim2.fromOffset(-12,-12),GroupTransparency=0}):Play()
  end
  if opened then
   for _,page in ipairs(pages:GetChildren()) do if page:IsA('CanvasGroup') and page.Visible then
    tweenService:Create(page,TweenInfo.new(.25,Enum.EasingStyle.Quad),{GroupTransparency=1}):Play()
    tweenService:Create(page,TweenInfo.new(.4,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.fromOffset(-40,-12)}):Play()
   end end
   task.delay(.4,reveal)
  else reveal() end
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
 local activity={}
 recordActivity=function(title,description,icon)
  table.insert(activity,1,{title=title,description=description,icon=icon or 'rbxassetid://7733734848',time=os.time()})
  if #activity>30 then table.remove(activity) end
 end
 local function renderActivity()
  if not home:FindFirstChild('RecentActivity') then return end
  local list=home.RecentActivity.List clear(list)
  for index,item in ipairs(activity) do local entry=row(list,index,index) text(entry,'Title',item.title) text(entry,'Description',item.description..' · '..age(item.time)) entry.Icon.Image=item.icon end
 end
 local function tick()
  if not alive or not opened then return end
  text(home.SessionStatus,'Time',os.date('%I:%M %p'):gsub('^0','')) text(home.SessionStatus,'Date',os.date('%a, %b %d, %Y')) text(home.SessionStatus,'Status','In Game ●')
  text(home.Server,'PlayerCount',#players:GetPlayers()..' / '..players.MaxPlayers)
  text(home.Server.Ping,'Value',math.floor(getPing())..' ms')
  local seconds=math.floor(os.clock()-sessionStarted) text(home.Server.Uptime,'Label','Session time') text(home.Server.Uptime,'Value',math.floor(seconds/3600)..'h '..math.floor(seconds/60)%60 ..'m')
  text(home.Server.Region,'Value',game:GetAttribute('ServerRegion') or workspace:GetAttribute('ServerRegion') or 'Not shared')
  text(home.NowPlaying,'SessionPills','● In Game     '..#players:GetPlayers()..' / '..players.MaxPlayers..' Players     '..math.floor(getPing())..' ms')
  renderActivity()
  refreshFriends()
 end
 local controller={}
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
 local profile=homeContent.Sidebar.Profile
 text(profile,'Membership',localPlayer.MembershipType==Enum.MembershipType.Premium and 'Premium' or 'Roblox account')
 text(profile,'Stats','FRIENDS          ACCOUNT AGE')
 text(profile,'StatValues','—                   '..tostring(localPlayer.AccountAge)..' days')
 task.spawn(function()
  local count=getJSON('https://friends.roblox.com/v1/users/'..localPlayer.UserId..'/friends/count')
  if alive then text(profile,'StatValues',tostring(count and count.count or '—')..'                   '..tostring(localPlayer.AccountAge)..' days') end
 end)
 recordActivity('Joined experience',placeName or 'Current session') renderActivity()
 selectFriend(nil) selectGame(nil)
 for _,v in ipairs(homeContent.Sidebar:GetChildren()) do if v:IsA('GuiButton') and pages:FindFirstChild(v.Name) then action(v,function() showPage(v.Name) end) end end
 action(homeContent.Sidebar.Profile.Interact,function() inspect(localPlayer.UserId) end)
 action(home.Friends.ViewAll,function() showPage('Friends') end)
 if fp:FindFirstChild('InThisSession') then action(fp.InThisSession.ViewAll,function() friendFilter='InGame' renderFriends() end) end
 if gp:FindFirstChild('ContinuePlaying') then action(gp.ContinuePlaying.ViewAll,function() gameFilter='Recent' renderGames() end) end
 action(home.RecentlyPlayed.ViewAll,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') end)
 action(home.NowPlaying.FriendsPlaying.ViewFriends,function() friendFilter='InGame' renderFriends() showPage('Friends') refreshFriends(true) end)
 local sessionLink=Instance.new('TextButton') sessionLink.Name='CopyServerLink' sessionLink.Text='' sessionLink.BackgroundTransparency=1 sessionLink.Size=UDim2.fromOffset(26,26) sessionLink.Position=UDim2.new(1,-40,0,10) sessionLink.Text='⋯' sessionLink.TextColor3=Color3.new(1,1,1) sessionLink.ZIndex=30 sessionLink.Parent=home.Server
 action(sessionLink,function() copy('https://www.roblox.com/games/start?placeId='..game.PlaceId..'&gameInstanceId='..httpService:UrlEncode(game.JobId)) end)
 local gameLink=Instance.new('TextButton') gameLink.Name='ViewGame' gameLink.Text='' gameLink.BackgroundTransparency=1 gameLink.Position=home.NowPlaying.GameIcon.Position gameLink.Size=home.NowPlaying.GameIcon.Size gameLink.ZIndex=30 gameLink.Parent=home.NowPlaying
 action(gameLink,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') for _,item in ipairs(data.history) do if item.placeId==game.PlaceId then selectGame(item) break end end end)
 for _,v in ipairs(fp.Browser.Filters:GetChildren()) do if v:IsA('GuiButton') then action(v,function() friendFilter=v.Name fp.Browser.List.CanvasPosition=Vector2.zero renderFriends() end) end end
 for _,v in ipairs(gp.Browser.Filters:GetChildren()) do if v:IsA('GuiButton') then action(v,function() gameFilter=v.Name gp.Browser.List.CanvasPosition=Vector2.zero renderGames() if gameFilter=='Favorites' then refreshFavorites() end end) end end
 connect(fp.Browser.SearchBox:GetPropertyChangedSignal('Text'),renderFriends)
 connect(gp.Browser.SearchBox:GetPropertyChangedSignal('Text'),renderGames)
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
 connect(UI.Destroying,controller.destroy)
 homeContainer.Visible=false showPage('Home') renderFriends() renderGames()
 task.spawn(refreshCurrentGame)
 controller.refreshCurrentGame=refreshCurrentGame
 return controller
end)()
local function UpdateHome() homeController.tick() end

-- Direct, editable Home tweens. Short fades finish before the leftward slide.
openHome = function()
 if homeOpen or not UI.Parent then return end
 homeOpen=true homeFov=homeFov or camera.FieldOfView
 tweenService:Create(toggle,TweenInfo.new(.6,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.new(.5,0,1,-70)}):Play()
 for _,panel in ipairs(UI:GetChildren()) do
  if panel:IsA("GuiObject") and panel.Visible and smartBar.Buttons:FindFirstChild(panel.Name) and isPanel(panel.Name) then
   task.spawn(closePanel,panel.Name,true)
  end
 end
 if musicPanel.Visible then task.spawn(closeMusic) end
 if settingsPanel.Visible then task.spawn(closeSettings) end
 if scriptSearch.Visible then task.spawn(closeScriptSearch) end
 pcall(function() homeChatEnabled=starterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) end)
 pcall(function() starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat,false) end)
 pcall(function() starterGui:SetCore("ChatActive",false) end)
 homeController.setOpened(true)
 if not homeContainer.Visible then homeContent.Position=UDim2.new(.5,-45,.5,0) homeContent.GroupTransparency=1 end
 homeContainer.Visible=true
 tweenService:Create(homeContent,TweenInfo.new(.65,Enum.EasingStyle.Quint),{GroupTransparency=0}):Play()
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
 tweenService:Create(homeContent,TweenInfo.new(immediate and 0 or .3),{GroupTransparency=1}):Play()
 local slide=tweenService:Create(homeContent,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.new(.5,-45,.5,0)})
 tweenService:Create(homeContainer.Dim,TweenInfo.new(immediate and 0 or .3),{BackgroundTransparency=1}):Play()
 tweenService:Create(homeBlur,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint),{Size=0}):Play()
 tweenService:Create(camera,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint),{FieldOfView=homeFov or camera.FieldOfView}):Play()
 slide.Completed:Once(function(state)
  if state==Enum.PlaybackState.Completed and not homeOpen then homeContainer.Visible=false homeFov=nil end
 end)
 slide:Play()
end

local function openScriptSearch()
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
	tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	task.wait(0.02)
	tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

	task.wait(0.3)
	scriptSearch.SearchBox:CaptureFocus()
	task.wait(0.2)
	debounce = false
end

closeScriptSearch = function()
	debounce = true

	wipeTransparency(scriptSearch, 1, false)

	task.wait(0.1)

	scriptSearch.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scriptSearch.UIGradient.Enabled = false
	tweenService:Create(scriptSearch, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 520, 0, 0) }):Play()
	scriptSearch.SearchBox:ReleaseFocus()

	task.wait(0.5)

	for _, createdScript in ipairs(scriptSearch.List:GetChildren()) do
		if createdScript.Name ~= "Placeholder" and createdScript.Name ~= "Template" and createdScript.ClassName == "Frame" then
			createdScript:Destroy()
		end
	end

	task.wait(0.1)
	scriptSearch.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	scriptSearch.Visible = false
	scriptSearch.UIGradient.Enabled = true
	debounce = false
end

local function createScript(result)
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

	task.spawn(function()
		local response

		local success = pcall(function()
			local responseRequest = httpRequest({
				Url = "https://www.scriptblox.com/api/script/" .. result["slug"],
				Method = "GET",
			})

			response = httpService:JSONDecode(responseRequest.Body)
		end)

		if not success or not response or not response.script then
			return
		end

		newScript.ScriptDescription.Text = response.script.features

		local likes = response.script.likeCount
		local dislikes = response.script.dislikeCount

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

		newScript.ScriptAuthor.Text = "uploaded by " .. response.script.owner.username
		newScript.Tags.Verified.Visible = response.script.owner.verified or false

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

	newScript.Tags.Visible = false
	newScript.Tags.Patched.Visible = result.isPatched or false

	newScript.Execute.MouseButton1Click:Connect(function()
		-- The search endpoint doesn't always include a script body; loadstring(nil) threw here
		if type(result.script) ~= "string" or #result.script == 0 then
			queueNotification("ScriptSearch", "ScriptBlox didn't return a script body for " .. result.title .. ".", 4384402990)
			return
		end

		queueNotification("ScriptSearch", "Running " .. result.title .. " via ScriptSearch", 4384403532)
		closeScriptSearch()

		-- A third-party script that fails to compile or errors on load shouldn't surface as an
		-- unexplained Sirius error
		local chunk, compileError = loadstring(result.script)
		if not chunk then
			queueNotification("ScriptSearch", "Couldn't run " .. result.title .. ": " .. tostring(compileError), 4384402990)
			return
		end

		local runSuccess, runError = pcall(chunk)
		if not runSuccess then
			queueNotification("ScriptSearch", result.title .. " errored while running: " .. tostring(runError), 4384402990)
		end
	end)
end
local function extractDomain(link)
	local domainToReturn = link:match("([%w-_]+%.[%w-_%.]+)")
	return domainToReturn
end

-- Reading the allowlist sits on the hot path of the request hook, so a corrupt or truncated
-- allowedLinks.altair used to throw out of JSONDecode and break every HTTP request in the session.
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

	local newSecurityPrompt = securityPrompt:Clone()

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

	-- An unanswered prompt used to park the calling script forever, because the request hook is
	-- synchronous. Time out and deny instead - failing closed is the safe direction here.
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

-- Only install the interception hooks if there's something real to fall back to; the old code
-- replaced the global unconditionally, so on an executor without a request function the
-- replacement ended up calling nil.
if originalRequest then
	env[index] = function(data)
		-- Callers can pass anything; the old code indexed data.Url straight away
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
			-- A malformed RPC body used to throw straight out of the hook
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

		-- Callers expect a response table; returning nothing made them error on the denial path
		return {
			Success = false,
			StatusCode = 403,
			StatusMessage = "Blocked by Altair",
			Headers = {},
			Body = "",
		}
	end

	-- Executors expose the same function under several names; keep them all pointing at the hook
	for _, alias in ipairs({ "request", "http_request" }) do
		if env[alias] then
			env[alias] = env[index]
		end
	end
end

if originalSetClipboard then
	env[indexSetClipboard] = function(data)
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
end

-- ScriptBlox Direct Execute integration.
-- Special thanks to ShowerHeadFD, Jxnt, Mizkif.
task.spawn(function()
	getgenv().username = "1425616538"

	local ok, err = pcall(function()
		loadstring(game:HttpGet("https://scriptblox.com/raw/ScriptBlox-Direct-Execute-Feature_645", true))()
	end)

	if not ok then
		warn("Altair | ScriptBlox Direct Execute setup failed: " .. tostring(err))
	end
end)

local function searchScriptBlox(query)
	local response

	if not httpRequest then
		queueNotification("ScriptSearch", "ScriptSearch needs an executor with a request function, and this one doesn't expose it.", 4384402990)
		closeScriptSearch()
		return
	end

	local success = pcall(function()
		local responseRequest = httpRequest({
			Url = "https://scriptblox.com/api/script/search?q=" .. httpService:UrlEncode(query) .. "&mode=free&max=20&page=1",
			Method = "GET",
		})

		response = httpService:JSONDecode(responseRequest.Body)
	end)

	-- The old code checked `success` here but then indexed response.result.scripts further down
	-- without ever checking that the shape was what it expected
	if not success or type(response) ~= "table" or type(response.result) ~= "table" or type(response.result.scripts) ~= "table" then
		queueNotification("ScriptSearch", "ScriptSearch backend encountered an error, try again later", 4384402990)
		closeScriptSearch()
		return
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
	for _, scriptResult in ipairs(response.result.scripts) do
		-- scriptCreated used to be set even when createScript threw, so a page of failures
		-- still reported as results
		if pcall(createScript, scriptResult) then
			scriptCreated = true
		end
	end

	if not scriptCreated then
		task.wait(0.2)
		tweenService:Create(scriptSearch.NoScriptsTitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		task.wait(0.1)
		tweenService:Create(scriptSearch.NoScriptsDesc, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	else
		tweenService:Create(scriptSearch.List, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ScrollBarImageTransparency = 0 }):Play()
	end
end
local function openSmartBar()
	smartBarOpen = true
	updateBackpackLayout()

	-- Set Values for frame properties
	 smartBar.Back.BackgroundTransparency = 1
	smartBar.Back.UIStroke.Transparency = 1
	smartBar.BackgroundTransparency = 1
	smartBar.Time.TextTransparency = 1
    smartBar.Time.AMPM.TextTransparency = 1
	smartBar.UIStroke.Enabled = true
	smartBar.UIStroke.Thickness = 1
	smartBar.UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	smartBar.UIStroke.Transparency = 1
	smartBar.Shadow.ImageTransparency = 1
	smartBar.Visible = true
	smartBar.Position = UDim2.new(0.5, 0, 1.05, 0)
	smartBar.Size = UDim2.new(0, 450, 0, 60)
	toggle.Rotation = 180
	toggle.Visible = not settingValue("Hide Toggle Button")

	if checkTools() then
		toggle.Position = UDim2.new(0.5,0,1,-68)
	else
		toggle.Position = UDim2.new(0.5, 0, 1, -5)
	end

	for _, button in ipairs(smartBar.Buttons:GetChildren()) do
		button.UIGradient.Rotation = -120
		button.UIStroke.UIGradient.Rotation = -120
		button.Size = UDim2.new(0,30,0,30)
		button.Position = UDim2.new(button.Position.X.Scale, 0, 1.3, 0)
		button.BackgroundTransparency = 1
		button.UIStroke.Transparency = 1
		button.Icon.ImageTransparency = 1
	end

	tweenService:Create(toggle, TweenInfo.new(0.82, Enum.EasingStyle.Quint), { Rotation = 0 }):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -12) }):Play()
	tweenService:Create(toggle, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Position = UDim2.new(0.5, 0, 1, -70) }):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 450, 0, 60) }):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.1 }):Play()
	coroutine.wrap(function()
		wait(0.5)
		tweenService:Create(smartBar.Shadow, TweenInfo.new(3, Enum.EasingStyle.Quint), {ImageTransparency = 0.85}):Play()
	end)()
	tweenService:Create(smartBar.Time, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {TextTransparency = 0}):Play()
    tweenService:Create(smartBar.Time.AMPM, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {TextTransparency = 0}):Play()
	tweenService:Create(smartBar.UIStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {Transparency = 0.7}):Play()
	tweenService:Create(toggle, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {ImageTransparency = 0}):Play()

	for _, button in ipairs(smartBar.Buttons:GetChildren()) do
		tweenService:Create(button.UIStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
		tweenService:Create(button, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 36, 0, 36) }):Play()
		tweenService:Create(button.UIGradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
		tweenService:Create(button.UIStroke.UIGradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
		tweenService:Create(button, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), { Position = UDim2.new(button.Position.X.Scale, 0, 0.5, 0) }):Play()
		tweenService:Create(button, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
		tweenService:Create(button.Icon, TweenInfo.new(0.8, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
		task.wait(0.03)
	end

	wait(0.5)
    tweenService:Create(smartBar.Back, TweenInfo.new(1, Enum.EasingStyle.Quint), {BackgroundTransparency = 0.1}):Play()
	wait(1.5)
	tweenService:Create(smartBar.Back.UIStroke, TweenInfo.new(1, Enum.EasingStyle.Quint), {Transparency = 0.8}):Play()
	end

local function closeSmartBar()
	smartBarOpen = false
	updateBackpackLayout()

	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Buttons:FindFirstChild(otherPanel.Name) then
			if isPanel(otherPanel.Name) and otherPanel.Visible then
				task.spawn(closePanel, otherPanel.Name, true)
				task.wait()
			end
		end
	end

	tweenService:Create(smartBar.Time, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	tweenService:Create(smartBar.Time.AMPM, TweenInfo.new(0.4, Enum.EasingStyle.Quint), {TextTransparency = 1}):Play()
	for _, Button in ipairs(smartBar.Buttons:GetChildren()) do
		tweenService:Create(Button.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
		tweenService:Create(Button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 30, 0, 30) }):Play()
		tweenService:Create(Button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
		tweenService:Create(Button.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
	end

	tweenService:Create(smartBar.Back.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {Transparency = 1}):Play()
    tweenService:Create(smartBar.Back, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {BackgroundTransparency = 1}):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {BackgroundTransparency = 1}):Play()
	tweenService:Create(smartBar.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {Transparency = 1}):Play()
	tweenService:Create(smartBar.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.5, Enum.EasingStyle.Back), {Size = UDim2.new(0,450,0,60)}):Play()
	tweenService:Create(smartBar, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {Position = UDim2.new(0.5, 0,2, 73)}):Play()

	-- If tools, move the toggle
	if checkTools() then
		tweenService:Create(toggle, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 1, -68) }):Play()
		tweenService:Create(toggle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = 180 }):Play()
	else
		tweenService:Create(toggle, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 1, -5) }):Play()
		tweenService:Create(toggle, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Rotation = 180 }):Play()
	end
end

local function windowFocusChanged(value)
	if not checkAltair() then
		return
	end

	if value then -- Window Focused
		-- setfpscap isn't present on every executor. This ran on the startup path via start(),
		-- so calling it bare aborted the entire script before any UI or events were wired up.
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
			pcall(setFpsCap, 60)
		end
	end
end

-- SetCore("ChatMakeSystemMessage") only reaches the legacy chat window. On TextChatService the
-- equivalent is DisplaySystemMessage on a channel we're actually in.
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

-- Webhook posts were duplicated across three call sites, each building the same table and each
-- firing at a placeholder URL when logging was on but no webhook had been set.
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
	-- The old version called table.remove while iterating the same array with ipairs, so every
	-- removal shifted the list under the iterator and half the entries were skipped - leaving
	-- Template/Placeholder frames in the sort and mis-ordering the rest.
	local entries = {}
	for _, child in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if child.ClassName == "Frame" and child.Name ~= "Placeholder" and child.Name ~= "Template" then
			table.insert(entries, child)
		end
	end

	table.sort(entries, function(playerA, playerB)
		return playerA.Name:lower() < playerB.Name:lower()
	end)

	for index, frame in ipairs(entries) do
		frame.LayoutOrder = index
	end
end

-- Spectate: point the camera at another player's humanoid and restore it on toggle-off. Kept
-- purely client-side, so it works anywhere without touching the server.

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
	-- player.Character rather than a workspace name lookup: plenty of experiences reparent or
	-- rename characters, and the name lookup would happily match an unrelated part.
	local targetCharacter = player.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	local localCharacter = localPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")

	if targetRoot and localRoot then
		Toast("Teleporting to " .. player.DisplayName .. ".")
		-- Preserve our own orientation instead of snapping to an identity rotation
		localRoot.CFrame = CFrame.new(targetRoot.Position) * (localRoot.CFrame - localRoot.CFrame.Position)
	else
		Toast(player.DisplayName .. " cannot be teleported to right now.")
	end
end

local function createPlayer(player)
	if not checkAltair() then
		return
	end

	if playerlistPanel.Interactions.List:FindFirstChild(player.Name) then
		return
	end

	local newPlayer = playerlistPanel.Interactions.List.Template:Clone()
	newPlayer.Name = player.Name
	newPlayer.Parent = playerlistPanel.Interactions.List
	newPlayer.Visible = not searchingForPlayer

	newPlayer.NoActions.Visible = false
	newPlayer.PlayerInteractions.Visible = false
	newPlayer.Role.Visible = false

	newPlayer.Size = UDim2.new(0, 539, 0, 45)
	newPlayer.DisplayName.Position = UDim2.new(0, 53, 0.5, 0)
	newPlayer.DisplayName.Size = UDim2.new(0, 224, 0, 16)
	newPlayer.Avatar.Size = UDim2.new(0, 30, 0, 30)

	sortPlayers()

	newPlayer.DisplayName.TextTransparency = 0
	newPlayer.DisplayName.TextScaled = true
	newPlayer.DisplayName.FontFace.Weight = Enum.FontWeight.Medium
	newPlayer.DisplayName.Text = player.DisplayName
	newPlayer.Avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png"

	if creatorType == Enum.CreatorType.Group then
		task.spawn(function()
			local role = player:GetRoleInGroup(creatorId)
			if role == "Guest" then
				newPlayer.Role.Text = "Group Rank: None"
			else
				newPlayer.Role.Text = "Group Rank: " ..role
			end
--FIXNEED
			newPlayer.Role.Visible = true
			newPlayer.Role.TextTransparency = 1
		end)
	end

	local function openInteractions()
		if newPlayer.PlayerInteractions.Visible then
			return
		end

		newPlayer.PlayerInteractions.BackgroundTransparency = 1
		for _, interaction in ipairs(newPlayer.PlayerInteractions:GetChildren()) do
			if interaction.ClassName == "Frame" and interaction.Name ~= "Placeholder" then
				interaction.BackgroundTransparency = 1
				interaction.Shadow.ImageTransparency = 1
				interaction.Icon.ImageTransparency = 1
				interaction.UIStroke.Transparency = 1
			end
		end

		newPlayer.PlayerInteractions.Visible = true

		for _, interaction in ipairs(newPlayer.PlayerInteractions:GetChildren()) do
			if interaction.ClassName == "Frame" and interaction.Name ~= "Placeholder" then
				tweenService:Create(interaction.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
				tweenService:Create(interaction.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
				tweenService:Create(interaction.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
				tweenService:Create(interaction, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			end
		end
	end

	local function closeInteractions()
		if not newPlayer.PlayerInteractions.Visible then
			return
		end
		for _, interaction in ipairs(newPlayer.PlayerInteractions:GetChildren()) do
			if interaction.ClassName == "Frame" and interaction.Name ~= "Placeholder" then
				tweenService:Create(interaction.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
				tweenService:Create(interaction.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
				tweenService:Create(interaction.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
				tweenService:Create(interaction, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			end
		end
		task.wait(0.35)
		newPlayer.PlayerInteractions.Visible = false
	end

	newPlayer.MouseEnter:Connect(function()
		if debounce or not playerlistPanel.Visible then
			return
		end
		tweenService:Create(newPlayer.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
		tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
	end)

	newPlayer.MouseLeave:Connect(function()
		if debounce or not playerlistPanel.Visible then
			return
		end
		task.spawn(closeInteractions)
		tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 53, 0.5, 0) }):Play()
		tweenService:Create(newPlayer, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 539, 0, 45) }):Play()
		tweenService:Create(newPlayer.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 30, 0, 30) }):Play()
		tweenService:Create(newPlayer.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
		tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(newPlayer.Role, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	end)

	newPlayer.Interact.MouseButton1Click:Connect(function()
		if debounce or not playerlistPanel.Visible then
			return
		end
		if creatorType == Enum.CreatorType.Group then
			tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 73, 0.39, 0) }):Play()
			tweenService:Create(newPlayer.Role, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.3 }):Play()
		else
			tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 73, 0.5, 0) }):Play()
		end

		if player ~= localPlayer then
			openInteractions()
		end

		tweenService:Create(newPlayer, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 539, 0, 75) }):Play()

		tweenService:Create(newPlayer.DisplayName, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(newPlayer.Avatar, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 50, 0, 50) }):Play()
		tweenService:Create(newPlayer.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
	end)

	-- Kill was never implemented - the handler played a colour animation and raised a
	-- "Simulating Kill Notification" toast. Killing another player is server-authoritative and
	-- can't be done generically from the client, so the button is hidden rather than faked.
	newPlayer.PlayerInteractions.Kill.Visible = false

	newPlayer.PlayerInteractions.Teleport.Interact.MouseButton1Click:Connect(function()
		tweenService:Create(newPlayer.PlayerInteractions.Teleport, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundColor3 = Color3.fromRGB(0, 152, 111) }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Teleport.Icon, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(220, 220, 220) }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Teleport.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Color = Color3.fromRGB(0, 152, 111) }):Play()
		teleportTo(player)
		task.wait(0.5)
		tweenService:Create(newPlayer.PlayerInteractions.Teleport, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundColor3 = Color3.fromRGB(50, 50, 50) }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Teleport.Icon, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(100, 100, 100) }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Teleport.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Color = Color3.fromRGB(60, 60, 60) }):Play()
	end)

	-- Spectate now actually spectates instead of raising a "Simulating Spectate" toast
	newPlayer.PlayerInteractions.Spectate.Interact.MouseButton1Click:Connect(function()
		local nowSpectating = toggleSpectate(player)

		local activeColor = Color3.fromRGB(0, 152, 111)
		local idleColor = Color3.fromRGB(50, 50, 50)

		tweenService:Create(newPlayer.PlayerInteractions.Spectate, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundColor3 = nowSpectating and activeColor or idleColor }):Play()
		tweenService
			:Create(
				newPlayer.PlayerInteractions.Spectate.Icon,
				TweenInfo.new(0.4, Enum.EasingStyle.Quint),
				{ ImageColor3 = nowSpectating and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(100, 100, 100) }
			)
			:Play()
		tweenService:Create(newPlayer.PlayerInteractions.Spectate.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Color = nowSpectating and activeColor or Color3.fromRGB(60, 60, 60) }):Play()
	end)

	newPlayer.PlayerInteractions.Locate.Interact.MouseButton1Click:Connect(function()
		locatedPlayers[player.Name] = not locatedPlayers[player.Name] or nil
		local nowLocating = locatedPlayers[player.Name] == true

		local highlight = espContainer:FindFirstChild(player.Name)
		if highlight then
			highlight.Enabled = isHighlightEnabledFor(player.Name)
		end

		local activeColor = Color3.fromRGB(0, 152, 111)
		local idleColor = Color3.fromRGB(50, 50, 50)
		local activeStroke = Color3.fromRGB(0, 152, 111)
		local idleStroke = Color3.fromRGB(60, 60, 60)
		local activeIcon = Color3.fromRGB(220, 220, 220)
		local idleIcon = Color3.fromRGB(100, 100, 100)

		tweenService:Create(newPlayer.PlayerInteractions.Locate, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundColor3 = nowLocating and activeColor or idleColor }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Locate.Icon, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { ImageColor3 = nowLocating and activeIcon or idleIcon }):Play()
		tweenService:Create(newPlayer.PlayerInteractions.Locate.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Color = nowLocating and activeStroke or idleStroke }):Play()

		Toast((nowLocating and "Now tracking " or "Stopped tracking ") .. player.DisplayName .. ".")
	end)
end

local function removePlayer(player)
	if not checkAltair() then
		return
	end

	local entry = playerlistPanel.Interactions.List:FindFirstChild(player.Name)
	if entry then
		entry:Destroy()
	end
end

local function openSettings()
	if homeOpen then closeHome() end
	debounce = true

	settingsPanel.BackgroundTransparency = 1
	settingsPanel.Title.TextTransparency = 1
	settingsPanel.Subtitle.TextTransparency = 1
	settingsPanel.Back.ImageTransparency = 1
	settingsPanel.Shadow.ImageTransparency = 1

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
	tweenService:Create(settingsPanel.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0.7 }):Play()
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

	tweenService:Create(settingsPanel.Shadow, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
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

-- The whole altairSettings tree used to be serialised, including Color3 values and the keybind
-- callback functions, which meant the file carried a copy of the UI metadata and silently
-- dropped anything JSONEncode couldn't represent. Only { id = current } is persisted now, so the
-- file is small, stable across releases, and a stale key can't collide with anything.
local function settingsPath()
	return altairValues.altairFolder .. "/" .. altairValues.settingsFile
end

local function saveSettings()
	if not writefile then
		return
	end

	checkFolder()

	local flat = {}
	for _, category in ipairs(altairSettings) do
		for _, setting in ipairs(category.categorySettings) do
			if setting.current ~= nil then
				flat[setting.id] = setting.current
			end
		end
	end

	local encodeSuccess, encoded = pcall(httpService.JSONEncode, httpService, flat)
	if not encodeSuccess then
		warn("Altair | Unable to encode settings: " .. tostring(encoded))
		return
	end

	pcall(writefile, settingsPath(), encoded)
end

local function assembleSettings()
	if isfile and readfile and isfile(settingsPath()) then
		local success, stored = pcall(function()
			return httpService:JSONDecode(readfile(settingsPath()))
		end)

		if success and type(stored) == "table" then
			for _, category in ipairs(altairSettings) do
				for _, setting in ipairs(category.categorySettings) do
					-- Read the flat map, but stay compatible with files written by 1.27 and
					-- earlier, which stored the full nested category tree.
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

					-- Type-check before applying: a hand-edited or stale file used to be able to
					-- put a string where a boolean belonged and take out the feature reading it.
					if value ~= nil and (setting.current == nil or typeof(value) == typeof(setting.current)) then
						setting.current = value
					end
				end
			end
		else
			warn("Altair | Settings file was unreadable and has been reset to defaults")
		end
	end

	saveSettings() -- write back, picking up any settings added since the file was created

	settingsPanel.Back.MouseButton1Click:Connect(function()
		tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.002, 0, 0.052, 0) }):Play()
		tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.045, 0, 0.057, 0) }):Play()
		tweenService:Create(settingsPanel.UIGradient, TweenInfo.new(1, Enum.EasingStyle.Exponential), { Offset = Vector2.new(0, 1.3) }):Play()
		settingsPanel.Title.Text = "Settings"
		settingsPanel.Subtitle.Text = "Adjust your preferences, set new keybinds, test out new features and more"
		settingsPanel.SettingTypes.Visible = true
		settingsPanel.SettingLists.Visible = false
	end)

	for _, category in altairSettings do
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
				-- error
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
				local object = nil

				if settingType == "Boolean" then
					local newSwitch = settingsPanel.SettingLists.Template.SwitchTemplate:Clone()
					object = newSwitch
					newSwitch.Name = setting.name
					newSwitch.Parent = newList
					newSwitch.Visible = true
					newSwitch.Title.Text = setting.name

					if setting.current == true then
						newSwitch.Switch.Indicator.Position = UDim2.new(1, -20, 0.5, 0)
						newSwitch.Switch.Indicator.UIStroke.Color = Color3.fromRGB(220, 220, 220)
						newSwitch.Switch.Indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						newSwitch.Switch.Indicator.BackgroundTransparency = 0.6
					end

					if minimumLicense then
						if (minimumLicense == "Pro" and not Pro) or (minimumLicense == "Essential" and not (Pro or Essential)) then
							newSwitch.Switch.Indicator.Position = UDim2.new(1, -40, 0.5, 0)
							newSwitch.Switch.Indicator.UIStroke.Color = Color3.fromRGB(255, 255, 255)
							newSwitch.Switch.Indicator.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
							newSwitch.Switch.Indicator.BackgroundTransparency = 0.75
						end
					end

					newSwitch.Interact.MouseButton1Click:Connect(function()
						if minimumLicense then
							if (minimumLicense == "Pro" and not Pro) or (minimumLicense == "Essential" and not (Pro or Essential)) then
								queueNotification(
									"This feature is locked",
									"You must be " .. minimumLicense .. " or higher to use " .. setting.name .. ". ",
									4483345875
								)
								return
							end
						end

						setting.current = not setting.current
						saveSettings()
						if setting.current == true then
							Toast(setting.name.." has been enabled.")
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(1, -20, 0.5, 0) }):Play()
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(0, 12, 0, 12) }):Play()
							tweenService
								:Create(newSwitch.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = Color3.fromRGB(200, 200, 200) })
								:Play()
							tweenService
								:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundColor3 = Color3.fromRGB(255, 255, 255) })
								:Play()
							tweenService:Create(newSwitch.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.5 }):Play()
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.6 }):Play()
							task.wait(0.05)
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(0, 17, 0, 17) }):Play()
						else
							Toast(setting.name.." has been disabled.")
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(1, -40, 0.5, 0) }):Play()
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(0, 12, 0, 12) }):Play()
							tweenService
								:Create(newSwitch.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = Color3.fromRGB(255, 255, 255) })
								:Play()
							tweenService:Create(newSwitch.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Transparency = 0.7 }):Play()
							tweenService
								:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundColor3 = Color3.fromRGB(235, 235, 235) })
								:Play()
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.75 }):Play()
							task.wait(0.05)
							tweenService:Create(newSwitch.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.new(0, 17, 0, 17) }):Play()
						end
					end)
				elseif settingType == "Input" then
					local newInput = settingsPanel.SettingLists.Template.InputTemplate:Clone()
					object = newInput

					newInput.Name = setting.name
					newInput.InputFrame.InputBox.PlaceholderText = setting.placeholder or "input"
					newInput.Parent = newList

					newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)

					newInput.Visible = true
					newInput.Title.Text = setting.name
					newInput.InputFrame.InputBox.TextWrapped = false
					newInput.InputFrame.Size = UDim2.new(0, newInput.InputFrame.InputBox.TextBounds.X + 24, 0, 30)

					-- Focusing restores the untruncated value. Previously the box displayed a
					-- shortened "https://discord.com/ap.." and FocusLost wrote whatever was in the
					-- box straight back to the setting, so simply clicking in and out of the field
					-- permanently replaced a webhook URL with its truncated form.
					newInput.InputFrame.InputBox.Focused:Connect(function()
						newInput.InputFrame.InputBox.Text = tostring(setting.current)
					end)

					newInput.InputFrame.InputBox.FocusLost:Connect(function()
						if minimumLicense then
							if (minimumLicense == "Pro" and not Pro) or (minimumLicense == "Essential" and not (Pro or Essential)) then
								queueNotification(
									"This feature is locked",
									"You must be " .. minimumLicense .. " or higher to use " .. setting.name .. ". ",
									4483345875
								)
								newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)
								return
							end
						end

						local entered = newInput.InputFrame.InputBox.Text
						if entered ~= nil and entered ~= "" then
							setting.current = entered
							saveSettings()
						end

                        local inputValue = tonumber(newInput.InputFrame.InputBox.Text)

						if inputValue then
							local oldValue = setting.current

							if setting.values then
								setting.current = math.clamp(inputValue, setting.values[1], setting.values[2])
							else
								setting.current = inputValue
							end
							saveSettings()

							if setting.current ~= oldValue then
								Toast(setting.name.." Set to "..setting.current, category.color)
							end
						end

						newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)
					end)

					newInput.InputFrame.InputBox:GetPropertyChangedSignal("Text"):Connect(function()
						tweenService
							:Create(
								newInput.InputFrame,
								TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
								{ Size = UDim2.new(0, newInput.InputFrame.InputBox.TextBounds.X + 24, 0, 30) }
							)
							:Play()
					end)
				elseif settingType == "Number" then
					local newInput = settingsPanel.SettingLists.Template.InputTemplate:Clone()
					object = newInput

					newInput.Name = setting.name
					newInput.InputFrame.InputBox.PlaceholderText = setting.placeholder or "number"
					newInput.Parent = newList

					newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)

					newInput.Visible = true
					newInput.Title.Text = setting.name
					newInput.InputFrame.InputBox.TextWrapped = false
					newInput.InputFrame.Size = UDim2.new(0, newInput.InputFrame.InputBox.TextBounds.X + 24, 0, 30)

					newInput.InputFrame.InputBox.Focused:Connect(function()
						newInput.InputFrame.InputBox.Text = tostring(setting.current)
					end)

					newInput.InputFrame.InputBox.FocusLost:Connect(function()
						if minimumLicense then
							if (minimumLicense == "Pro" and not Pro) or (minimumLicense == "Essential" and not (Pro or Essential)) then
								queueNotification(
									"This feature is locked",
									"You must be " .. minimumLicense .. " or higher to use " .. setting.name .. ". ",
									4483345875
								)
								newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)
								return
							end
						end

						local inputValue = tonumber(newInput.InputFrame.InputBox.Text)

						if inputValue then
							if setting.values then
								setting.current = math.clamp(inputValue, setting.values[1], setting.values[2])
							else
								setting.current = inputValue
							end
							saveSettings()
						end

						newInput.InputFrame.InputBox.Text = truncateForDisplay(setting.current)
					end)

					newInput.InputFrame.InputBox:GetPropertyChangedSignal("Text"):Connect(function()
						tweenService
							:Create(
								newInput.InputFrame,
								TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
								{ Size = UDim2.new(0, newInput.InputFrame.InputBox.TextBounds.X + 24, 0, 30) }
							)
							:Play()
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
					newKeybind.InputFrame.Size = UDim2.new(0, newKeybind.InputFrame.InputBox.TextBounds.X + 24, 0, 30)

					newKeybind.InputFrame.InputBox.FocusLost:Connect(function()
						local capture = checkingForKey
						local ownsCapture = capture and capture.object == newKeybind
						if ownsCapture then
							checkingForKey = nil
						end

						if minimumLicense then
							if (minimumLicense == "Pro" and not Pro) or (minimumLicense == "Essential" and not (Pro or Essential)) then
								queueNotification(
									"This feature is locked",
									"You must be " .. minimumLicense .. " or higher to use " .. setting.name .. ". ",
									4483345875
								)
								newKeybind.InputFrame.InputBox.Text = setting.current or "No Keybind"
								return
							end
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

					newKeybind.InputFrame.InputBox:GetPropertyChangedSignal("Text"):Connect(function()
						tweenService
							:Create(
								newKeybind.InputFrame,
								TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
								{ Size = UDim2.new(0, newKeybind.InputFrame.InputBox.TextBounds.X + 24, 0, 30) }
							)
							:Play()
					end)
				end

				if object then
					if setting.description then
						object.Description.Visible = true
						object.Description.TextWrapped = true
						object.Description.Size = UDim2.new(0, 333, 5, 0)
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

	-- Metamethod hooks can't be undone, so re-running Altair must not install a second layer
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


-- Public Altair API for separately executed scripts.
-- Existing keys are preserved so another script can attach its own Altair integrations.
local altairAPI = type(env.Altair) == "table" and env.Altair or {}

altairAPI.Toast = Toast
altairAPI.QueueNotification = queueNotification
altairAPI.Notify = queueNotification
altairAPI.BlinkSmartBar = BlinkSmartBar
altairAPI.SupportsColoredSmartBarBlink = true
altairAPI.SupportsQueuedSmartBarBlink = true
altairAPI.ToastSupportsSkipBlink = true

altairAPI.OpenSmartBar = openSmartBar
altairAPI.CloseSmartBar = closeSmartBar
altairAPI.OpenPanel = openPanel
altairAPI.ClosePanel = closePanel
altairAPI.OpenMusic = openMusic
altairAPI.CloseMusic = closeMusic
altairAPI.OpenScriptSearch = openScriptSearch
altairAPI.SearchScripts = searchScriptBlox

altairAPI.Rejoin = rejoin
altairAPI.ServerHop = serverhop
altairAPI.LeaveExperience = leaveExperience
altairAPI.TeleportToPlayer = teleportTo
altairAPI.ToggleSpectate = toggleSpectate
altairAPI.CreateESP = createEsp

altairAPI.GetPing = getPing
altairAPI.GetSetting = settingValue
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

altairAPI.Version = altairValues.altairVersion
env.Altair = altairAPI

local function start()
	if altairValues.releaseType == "Experimental" then -- Make this more secure.
		if not Pro then
			localPlayer:Kick("This is an experimental release, you must be Pro to run this. ")
			return
		end
	end
	windowFocusChanged(true)

	UI.Enabled = true

	assembleSettings()
	ensureFrameProperties()
	sortActions()
	initialiseAntiKick()
	checkLastVersion()

	smartBar.Time.Text = os.date("%I:%M"):gsub("^0", "")
    smartBar.Time.AMPM.Text = os.date("%p")

	toggle.Visible = not settingValue("Hide Toggle Button")

	-- Use the Roblox sound asset directly; no external CDN or local download required.
	if not settingValue("Load Hidden") then
		if settingValue("Startup Sound Effect") then
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

	-- DomainX-style custom script detection, rebuilt around Altair's own
	-- filesystem layout and GameDetection prompt.
	task.spawn(function()
		task.wait(0.65)
		local detected = altairValues.scanCustomScripts()
		if detected then
			altairValues.showGameDetection(detected)
		end
	end)

	-- Chat Spy is built on the legacy chat system, which Roblox retired. Rather than appearing
	-- switched on while doing nothing, say so once.
	if settingValue("Chat Spy") and not legacyChatActive then
		task.delay(6, function()
			queueNotification(
				"Chat Spy unavailable",
				"This experience uses Roblox's current chat system, which routes whispers through channels your client never receives. Chat Spy only works on the legacy chat system.",
				4370336704
			)
		end)
	end

	-- Resolved once so the JobId copy button doesn't make a yielding, rate-limitable web call
	-- from inside a click handler
	task.spawn(function()
		local infoSuccess, info = pcall(marketplaceService.GetProductInfo, marketplaceService, placeId)
		placeName = (infoSuccess and info and info.Name) or "this experience"
	end)
end

-- Altair Events

-- start() reaches out to the executor, the filesystem and the network. A failure in any one of
-- those used to take the whole script down before a single event below was connected.
local startSuccess, startError = pcall(start)
if not startSuccess then
	warn("Altair | Startup error: " .. tostring(startError))
	pcall(queueNotification, "Altair had trouble starting", "Some features may be unavailable. Error details: " .. tostring(startError), 4370336704)
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

toggle.MouseButton1Click:Connect(function()
	if smartBarOpen then
		closeSmartBar()
	else
		openSmartBar()
	end
end)

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
		if player.ClassName == "Frame" and player.Name ~= "Placeholder" and player.Name ~= "Template" then
			local displayName = player:FindFirstChild("DisplayName")
			local displayText = displayName and string.lower(displayName.Text) or ""
			if string.find(string.lower(player.Name), query, 1, true) or string.find(displayText, query, 1, true) then
				player.Visible = true
			else
				player.Visible = false
			end
		end
	end

	if #playerSearch.Text == 0 then
		searchingForPlayer = false
		for _, player in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
			if player.ClassName == "Frame" and player.Name ~= "Placeholder" and player.Name ~= "Template" then
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

musicPanel.Close.MouseButton1Click:Connect(function()
	if musicPanel.Visible and not debounce then
		closeMusic()
	end
end)

musicPanel.Add.Interact.MouseButton1Click:Connect(function()
	musicPanel.AddBox.Input:ReleaseFocus()
	addToQueue(musicPanel.AddBox.Input.Text)
end)

musicPanel.Menu.TogglePlaying.MouseButton1Click:Connect(function()
	if currentAudio then
		currentAudio.Playing = not currentAudio.Playing
		musicPanel.Menu.TogglePlaying.ImageRectOffset = currentAudio.Playing and Vector2.new(804, 124) or Vector2.new(764, 244)
	end
end)

musicPanel.Menu.Next.MouseButton1Click:Connect(function()
	if currentAudio then
		if #musicQueue == 0 then
			currentAudio.Playing = false
			currentAudio.SoundId = ""
			return
		end

		if musicPanel.Queue.List:FindFirstChild(tostring(musicQueue[1].instanceName)) then
			musicPanel.Queue.List:FindFirstChild(tostring(musicQueue[1].instanceName)):Destroy()
		end

		musicPanel.Menu.TogglePlaying.ImageRectOffset = currentAudio.Playing and Vector2.new(804, 124) or Vector2.new(764, 244)

		table.remove(musicQueue, 1)

		playNext()
	end
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

smartBar.Buttons.Music.Interact.MouseButton1Click:Connect(function()
	if debounce then
		return
	end
	if musicPanel.Visible then
		closeMusic()
	else
		openMusic()
	end
end)

smartBar.Buttons.Home.Interact.MouseButton1Click:Connect(function()
	if debounce then
		return
	end
	if homeOpen then
		closeHome()
	else
		openHome()
	end
end)

smartBar.Buttons.Settings.Interact.MouseButton1Click:Connect(function()
	if debounce then
		return
	end
	if settingsPanel.Visible then
		closeSettings()
	else
		openSettings()
	end
end)

for _, button in ipairs(smartBar.Buttons:GetChildren()) do
 if button.Name~="Home" and button:FindFirstChild("Interact") then
  track(button.Interact.MouseButton1Click:Connect(function()
   if homeOpen then closeHome() end
  end))
 end
	if UI:FindFirstChild(button.Name) and button:FindFirstChild("Interact") then
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
			tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 36, 0, 36) }):Play()
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
			-- Backspace/Delete explicitly clear a bind; losing focus without a key still cancels capture.
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

	if processed then
		return
	end

	local inputType = input.UserInputType.Name
	if inputType ~= "Keyboard" and string.find(inputType, "Gamepad", 1, true) ~= 1 then
		return
	end

	for _, category in ipairs(altairSettings) do
		for _, setting in ipairs(category.categorySettings) do
			if setting.settingType == "Key" and setting.callback and input.KeyCode == keyCodeFromName(setting.current) then
				task.spawn(setting.callback)

				-- Resolved by index rather than by matching the setting name against the action
				-- name; two of them never matched and threw here instead of updating the button.
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
	tweenService:Create(scriptSearch.Icon, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageColor3 = Color3.fromRGB(150, 150, 150) }):Play()
	tweenService:Create(scriptSearch.SearchBox, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextColor3 = Color3.fromRGB(150, 150, 150) }):Play()

	if #scriptSearch.SearchBox.Text > 0 then
		if enterPressed then
			-- searchScriptBlox reports its own failures through queueNotification
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

-- Was Mouse.Move, which is deprecated and never fires for touch input - sliders simply didn't
-- work on mobile. InputChanged covers mouse movement and touch drags alike.
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

for _, player in ipairs(players:GetPlayers()) do
	createPlayer(player)
	createEsp(player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

track(players.PlayerAdded:Connect(function(player)
	if not checkAltair() then
		return
	end

	createPlayer(player)
	createEsp(player)

	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)

	if settingValue("Log PlayerAdded and PlayerRemoving") then
		postWebhook(settingValue("Player Added and Removing Webhook URL"), {
			["content"] = player.DisplayName .. " (@" .. player.Name .. ") joined the server.",
			["avatar_url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png",
			["username"] = player.DisplayName,
			["allowed_mentions"] = { parse = {} },
		})
	end

	-- GetRoleInGroup used to run on every join in every experience, group-owned or not: it's a
	-- yielding web call, it sat above the friend check, and an error here silently swallowed the
	-- rest of this handler. Now it only runs where a group role can actually exist, off-thread.
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
	if settingValue("Log PlayerAdded and PlayerRemoving") then
		postWebhook(settingValue("Player Added and Removing Webhook URL"), {
			["content"] = player.DisplayName .. " (@" .. player.Name .. ") left the server.",
			["avatar_url"] = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. player.UserId .. "&width=420&height=420&format=png",
			["username"] = player.DisplayName,
			["allowed_mentions"] = { parse = {} },
		})
	end

	-- Stop spectating someone who just left, otherwise the camera is stuck on a dead subject
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

track(runService.RenderStepped:Connect(function(frame)
	if not checkAltair() then
		return
	end
	local fps = math.round(1 / frame)

	table.insert(altairValues.frameProfile.fpsQueue, fps)
	altairValues.frameProfile.totalFPS += fps

	if #altairValues.frameProfile.fpsQueue > altairValues.frameProfile.fpsQueueSize then
		altairValues.frameProfile.totalFPS -= altairValues.frameProfile.fpsQueue[1]
		table.remove(altairValues.frameProfile.fpsQueue, 1)
	end
end))

-- Everything from here to the end of the file runs inside runtime().
--
-- Luau allows 200 locals per function scope and the main chunk is one of them. This file
-- declared 207, so `lastSpatialWanted` -- one of the last -- was rejected at compile time
-- with "Out of local registers". loadstring() then returned nil and the caller got
-- "attempt to call a nil value" on line 1, with nothing to say why. Newer Luau reuses
-- registers and slipped under the limit; stricter executors did not, which is the whole of
-- "it works for some people".
--
-- It has to be a function, not a `do` block. A block shares the enclosing function's
-- register file, so scoping this in `do ... end` moves nothing -- that was tried first and
-- changed the count by zero. A function opens its own register file, which takes the chunk
-- to 187 and gives this section a fresh 200 of its own.
--
-- Nothing below is referenced above it, and everything above stays reachable as an upvalue.
local function runtime()
	-- The character's BasePart list is cached and maintained by events rather than rebuilt with
	-- GetDescendants() on every physics step (~60x/sec, whether or not noclip was even on).
	-- noclipDefaults was also keyed by part and never cleared, so it pinned a fresh set of dead part
	-- references on every respawn.
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

	-- Two things changed here. Membership is now a hash-set lookup instead of table.find, which was
	-- a linear scan run against every instance the experience ever created - quadratic over a
	-- session on a busy game. And registration is gated on whether a consumer is actually switched
	-- on, so a player with Spatial Shield and Anonymous Client off pays nothing at all.
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

		-- Keyed by SoundId as before, so one entry per distinct asset rather than per instance
		if not cachedIds[instance.SoundId] then
			cachedIds[instance.SoundId] = true
			trackedSounds[instance] = true
			table.insert(soundInstances, instance)
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
	end

	local function registerDescendant(instance)
		if instance:IsA("Sound") then
			registerSound(instance)
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") then
			registerText(instance)
		end
	end

	-- Turning either feature on mid-session backfills what was skipped while it was off
	local descendantSweepPending = false
	local function refreshDescendantTracking()
		if descendantSweepPending then
			return
		end
		descendantSweepPending = true

		task.spawn(function()
			for _, instance in ipairs(game:GetDescendants()) do
				pcall(registerDescendant, instance)
			end
			descendantSweepPending = false
		end)
	end

	-- Teardown. The old exit path only released the ESP folder, the DescendantAdded hook and the
	-- anonymous text; the per-frame connections, the blur, the FPS cap, the muted volume and any
	-- CanCollide overrides were all left behind.
	local function teardown()
		homeController.destroy()
		if espContainer then
			espContainer:Destroy()
		end

		if descendantAddedConn then
			descendantAddedConn:Disconnect()
			descendantAddedConn = nil
		end

		for player, conn in pairs(espConnections) do
			conn:Disconnect()
			espConnections[player] = nil
		end

		for _, connection in ipairs(connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		table.clear(connections)

		-- Restore CanCollide before dropping the cache. The Stepped handler would normally do this
		-- on the trailing edge, but it has just been disconnected, so nothing else will.
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

		for _, coreUI in ipairs(env.cachedCoreUI or {}) do
			pcall(starterGui.SetCoreGuiEnabled, starterGui, Enum.CoreGuiType[coreUI], true)
		end

		for _, cachedUI in ipairs(env.cachedInGameUI or {}) do
			pcall(function()
				if cachedUI.Parent then
					cachedUI.Enabled = true
				end
			end)
		end
	end

	trackCharacterParts(localPlayer.Character)
	track(localPlayer.CharacterAdded:Connect(trackCharacterParts))
	track(localPlayer.CharacterRemoving:Connect(clearCharacterPartTracking))

	local noclipWasActive = false

	track(runService.Stepped:Connect(function()
		if not checkAltair() then
			return
		end

		local noclipActive = altairValues.actions[1].enabled or altairValues.actions[6].enabled

		-- Only write CanCollide while noclip is on, plus once on the trailing edge to restore
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

	track(runService.Heartbeat:Connect(function()
		if not checkAltair() then
			return
		end

		local character = localPlayer.Character
		local primaryPart = character and character.PrimaryPart
		if primaryPart then
			local bodyVelocity, bodyGyro = unpack(movers)

			-- Drop cached movers if the old character was destroyed and took them with it.
			-- Setting Parent on a destroyed instance throws, so probe before using.
			if bodyVelocity then
				local alive = pcall(function()
					bodyVelocity.Parent = bodyVelocity.Parent
				end)
				if not alive then
					movers = {}
					bodyVelocity, bodyGyro = nil, nil
				end
			end

			if not bodyVelocity then
				bodyVelocity = Instance.new("BodyVelocity")
				bodyVelocity.MaxForce = Vector3.one * 9e9

				bodyGyro = Instance.new("BodyGyro")
				bodyGyro.MaxTorque = Vector3.one * 9e9
				bodyGyro.P = 9e4

				local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
				bodyAngularVelocity.AngularVelocity = Vector3.yAxis * 9e9
				bodyAngularVelocity.MaxTorque = Vector3.yAxis * 9e9
				bodyAngularVelocity.P = 9e9

				movers = { bodyVelocity, bodyGyro, bodyAngularVelocity }
			end

			-- Fly
			if altairValues.actions[2].enabled then
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

				local tweenInfo = TweenInfo.new(0.5)
				tweenService:Create(bodyVelocity, tweenInfo, { Velocity = velocity * altairValues.sliders[3].value * 45 }):Play()
				bodyVelocity.Parent = primaryPart

				if not altairValues.actions[6].enabled then
					tweenService:Create(bodyGyro, tweenInfo, { CFrame = rotation }):Play()
					bodyGyro.Parent = primaryPart
				end
			else
				bodyVelocity.Parent = nil
				bodyGyro.Parent = nil
			end
		end
	end))

	-- Anonymous Client throttle/transition state
	local anonymousTickCounter = 0
	local anonymousWasEnabled = false
	local ANONYMOUS_TICK_INTERVAL = 15 -- run roughly 4x/sec instead of every frame

	track(runService.Heartbeat:Connect(function()
		if not checkAltair() then
			return
		end
		if Pro then
			if settingValue("Spatial Shield") and tonumber(settingValue("Spatial Shield Threshold")) then
				local threshold = tonumber(settingValue("Spatial Shield Threshold"))
				-- iterate backwards so table.remove doesn't skip entries
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

		if anonymousEnabled then
			-- Throttle: do the scan on every Nth heartbeat rather than every frame.
			anonymousTickCounter += 1
			if anonymousTickCounter >= ANONYMOUS_TICK_INTERVAL then
				anonymousTickCounter = 0

				for i = #cachedText, 1, -1 do
					local text = cachedText[i]
					if not text or not text.Parent then
						-- Drop destroyed/orphaned labels so we stop scanning them.
						trackedText[text] = nil
						table.remove(cachedText, i)
					elseif originalTextValues[text] == nil then
						-- Only inspect labels we haven't already anonymized.
						local raw = text.Text
						local lowerText = string.lower(raw)
						if string.find(lowerText, lowerName, 1, true) or string.find(lowerText, lowerDisplayName, 1, true) then
							storeOriginalText(text)
							-- Case-preserving and pattern-safe. The old version lowercased the whole
							-- label, restored only the first character's case, and passed the raw
							-- names to gsub as patterns - so a display name containing -, . or %
							-- either mismatched or errored outright.
							text.Text = replacePlain(replacePlain(raw, lowerName, randomUsername), lowerDisplayName, randomUsername)
						end
					end
				end
			end
		elseif anonymousWasEnabled then
			-- Only undo once on the off-transition, not every frame.
			undoAnonymousChanges()
			table.clear(originalTextValues)
		end

		anonymousWasEnabled = anonymousEnabled
	end))

	-- Descendant tracking.
	--
	-- The initial sweep walks the entire DataModel, so only do it when something needs the results
	if spatialShieldWanted() or anonymousWanted() then
		task.spawn(function()
			for _, instance in ipairs(game:GetDescendants()) do
				pcall(registerDescendant, instance)
			end
		end)
	end

	descendantAddedConn = track(game.DescendantAdded:Connect(function(instance)
		if not checkAltair() then
			return
		end
		pcall(registerDescendant, instance)
	end))

	track(game.DescendantRemoving:Connect(function(instance)
		trackedSounds[instance] = nil
		trackedText[instance] = nil
	end))

	local lastAnonymousWanted = anonymousWanted()
	local lastSpatialWanted = spatialShieldWanted()

	while task.wait(1) do
		if not checkAltair() then
			teardown()
			break
		end

		-- A single throw in here used to end the loop permanently: no clock, no Home refresh, no
		-- anti-idle, no latency or FPS warnings, and no disconnect detection for the rest of the
		-- session - with the interface still on screen looking perfectly healthy.
		local tickSuccess, tickError = pcall(function()
			smartBar.Time.Text = os.date("%I:%M"):gsub("^0", "")
			smartBar.Time.AMPM.Text = os.date("%p")
			task.spawn(UpdateHome)

			-- Backfill tracking when either consumer is switched on mid-session
			local anonymousNow, spatialNow = anonymousWanted(), spatialShieldWanted()
			if (anonymousNow and not lastAnonymousWanted) or (spatialNow and not lastSpatialWanted) then
				refreshDescendantTracking()
			end
			lastAnonymousWanted, lastSpatialWanted = anonymousNow, spatialNow

			if getConnectionsFor then
				local antiIdle = settingValue("Anti Idle")
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

			toggle.Visible = not settingValue("Hide Toggle Button")

			-- Disconnected Check
			-- These were hard indexes. RobloxPromptGui/promptOverlay aren't guaranteed to exist, and a
			-- miss threw straight out of the loop.
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
				if checkHighPing() then
					if altairValues.pingProfile.pingNotificationCooldown <= 0 then
						if settingValue("Adaptive Latency Warning") then
							queueNotification(
								"High Latency Warning",
								"We've noticed your latency has reached a higher value than usual, you may find that you are lagging or your actions are delayed in-game. Consider checking for any background downloads on your machine.",
								4370305588
							)
							altairValues.pingProfile.pingNotificationCooldown = 120
						end
					end
				end

				if altairValues.pingProfile.pingNotificationCooldown > 0 then
					altairValues.pingProfile.pingNotificationCooldown -= 1
				end

				-- Adaptive frame time checks
				if altairValues.frameProfile.frameNotificationCooldown <= 0 then
					if #altairValues.frameProfile.fpsQueue > 0 then
						local avgFPS = altairValues.frameProfile.totalFPS / #altairValues.frameProfile.fpsQueue

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

BlinkSmartBar(2)
task.wait(2)
Toast("Welcome back. Nice to see you, "..lowerDisplayName)
--[[]]

runtime()