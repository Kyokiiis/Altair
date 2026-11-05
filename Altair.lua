
--[[

Altair

© 2026 Cloudz Softwares. 

Altair is a Smart Script based and built around Sirius

--]]

-- Runtime map (search by symbol):
-- altairSettings                      Configuration and saved setting IDs
-- loadInterface / lifecycle           UI loading, ownership and cleanup
-- smartBarLayout / sharedPanel        Docking, navigation and panel motion
-- homeController / playerlistUI       Home and server-player views
-- scriptSearchState / searchTransport Script discovery and request caching
-- settingsStore / assembleSettings    Persistence and settings presentation
-- altairAPI / start / runtime         Public integrations and runtime wiring

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
-- Claim startup before the first deliberate yield, including game readiness.
local startupClaim={schema=1,alive=true,roots={},previous=env.__AltairStartupClaim}
env.__AltairStartupClaim=startupClaim
local function ownsStartup()
	return startupClaim.alive and env.__AltairStartupClaim==startupClaim
end
local function requireStartup()
	assert(ownsStartup(),"Altair startup superseded")
end
function startupClaim:Cancel()
	self.alive=false
	if self.cleaned or self.cleaning then return end
	self.cleaning=true
	if self.lifecycle then pcall(self.lifecycle.unload,self.lifecycle)end
	for root in pairs(self.roots)do pcall(root.Destroy,root)end
	table.clear(self.roots)
	self.cleaning=false
	self.cleaned=not self.predecessorCleanup
	if env.__AltairStartupClaim==self then env.__AltairStartupClaim=nil end
end
local function observeStartupRoot(root)
	if not ownsStartup()then
		if typeof(root)=="Instance"and not root.Parent then pcall(root.Destroy,root)end
		requireStartup()
	end
	if typeof(root)=="Instance"and not root.Parent and not startupClaim.roots[root]then
		startupClaim.roots[root]=true
		root.Destroying:Once(function()startupClaim.roots[root]=nil end)
	end
end
local function initialise()
startupClaim.predecessorCleanup=true
local predecessor=startupClaim.previous
if type(predecessor)=="table"and predecessor.schema==1 and type(predecessor.Cancel)=="function"then
	predecessor:Cancel()
	-- Cleanup may itself yield. A third run must await that whole predecessor
	-- chain before capturing baselines or mounting its own runtime.
	while type(predecessor)=="table"and predecessor.schema==1 do
		while not predecessor.cleaned do requireStartup();task.wait()end
		predecessor=predecessor.previous
	end
end
requireStartup()
-- Finish the previous session before capturing camera/audio state for this one.
do
	local previous = env.Altair
	if type(previous) == "table" and type(previous.Unload) == "function" then
		pcall(previous.Unload)
	end
	requireStartup()
	-- Also remove orphaned roots left by an interrupted or older session.
	-- Destroying a current root invokes its runtime teardown before replacement.
	local containers={}
	pcall(function() containers[#containers+1]=getHiddenUI and getHiddenUI() or game:GetService("CoreGui") end)
	pcall(function() containers[#containers+1]=game:GetService("CoreGui") end)
	pcall(function() containers[#containers+1]=game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui") end)
	for _,container in ipairs(containers) do
		for _,old in ipairs(container:GetChildren()) do
			requireStartup()
			if old:IsA("ScreenGui") and (old.Name=="Altair" or old.Name=="AltairCapsuleQA" or old:GetAttribute("AltairCapsuleSchema")==2)
				and (old:FindFirstChild("SmartBar") or old:FindFirstChild("TopCapsules")) then
				old:Destroy()
			end
		end
	end
end
startupClaim.predecessorCleanup=false
startupClaim.previous=nil
requireStartup()
if not game:IsLoaded() then
	local deadline=os.clock()+10
	while not game:IsLoaded()and os.clock()<deadline do task.wait();requireStartup()end
end
requireStartup()

local function getService(name)
	local service = game:GetService(name)
	return cloneRef and cloneRef(service) or service
end

-- Roblox services
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

-- Runtime state
local useStudio = runService:IsStudio()
local connections = {}
local camera = workspace.CurrentCamera
if not camera then
	local deadline = os.clock() + 10
	repeat
		task.wait()
		requireStartup()
		camera = workspace.CurrentCamera
	until camera or os.clock() >= deadline
	if not camera then
		warn("Altair | No current camera is available; Altair has not started.")
		return
	end
end
local getMessage = replicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 1) and replicatedStorage.DefaultChatSystemChatEvents:WaitForChild("OnMessageDoneFiltering", 1)
requireStartup()
local legacyChatActive = getMessage ~= nil and textChatService.ChatVersion == Enum.ChatVersion.LegacyChatService
local localPlayer = players.LocalPlayer

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
local espContainer -- Created only after the Lua interface successfully builds.
local locatedPlayers = {} -- per-player ESP toggles, independent from the global ESP action
local espConnections = {} -- [player] = RBXScriptConnection for CharacterAdded
local descendantAddedConn -- top-level DescendantAdded; tracked so we can disconnect on teardown
local oldVolume = 1
local daylightClock={baseline=lighting.ClockTime,editing=false,owned=nil}
-- Ordinary Studio LocalScripts cannot read this executor-only setting.
if useStudio then
	gameSettings = nil
else
	local readable = pcall(function() oldVolume = gameSettings.MasterVolume end)
	if not readable then gameSettings = nil end
end
local baseFieldOfView = camera.FieldOfView -- Updated when Roblox replaces the camera.
local fovMotionRoot
local function fovMotionDuration(duration)
 return fovMotionRoot and fovMotionRoot:GetAttribute("AltairReduceMotion")==true and math.min(duration,.08)or duration
end

local placeName -- resolved once at startup so the JobId copy button never yields on click

-- Runtime caches
local suppressedSounds = {}
local spatialSoundVolumes = {} -- [Sound] = { baseline = number, applied = number }
local soundSuppressionNotificationCooldown = 0
local soundInstances = {}
local trackedSounds = {} -- [Sound] = true, replaces the linear table.find scan
local trackedText = {} -- [TextLabel|TextButton] = true
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

-- Configuration and character property models
local SECURITY_PROMPT_TIMEOUT = 60 -- seconds before an unanswered prompt denies by default
local altairValues
altairValues = {
	altairVersion = "1.4",
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
	interfaceSource = "https://raw.githubusercontent.com/Kyokiiis/Altair/refs/heads/main/UI/Build.lua",
 dockGap = 12,

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
			control = "Daylight",
			images = { 9134778004, 10137794784 },
			color = Color3.fromRGB(102, 75, 190),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				if type(value)=="number"then
					if not daylightClock.editing then daylightClock.baseline=lighting.ClockTime end
					daylightClock.editing=true;daylightClock.owned=math.clamp(value,0,24)
					lighting.ClockTime=daylightClock.owned;return
				end
				local ruler=altairValues.characterRuler
				if ruler then
					local panel=ruler.Root:FindFirstAncestor("Character")
					local api=(getgenv and getgenv()or _G).Altair
					if panel and not panel.Visible and api and api.OpenPanel then api.OpenPanel("Character")end
					ruler:SelectDaylight(true)
				end
			end,
			reset = function()
				local value=daylightClock.baseline
				daylightClock.editing=false;daylightClock.owned=value;lighting.ClockTime=value
				return value
			end,
		},
		{
			name = "Master Vol",
			images = { 9134774810, 14386246782 },
			color = Color3.fromRGB(202, 103, 58),
			enabled = false,
			rotateWhileEnabled = false,
			callback = function(value)
				if not gameSettings then return end
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
			values = { 0, 500 },
			default = 16,
			value = 16,
			active = false,
			callback = function(value)
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = value
				end
			end,
		},
		{
			name = "jump power",
			color = Color3.fromRGB(59, 126, 184),
			values = { 0, 500 },
			default = 50,
			value = 16,
			active = false,
			callback = function(value)
				local character = localPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
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
			values = { 1, 50 },
			default = 3,
			value = 3,
			active = false,
			callback = function() end, -- read directly by the Heartbeat flight loop
		},
		{
			name = "field of view",
			color = Color3.fromRGB(198, 178, 75),
			values = { 1, 120 },
			default = 70,
			value = 16,
			active = false,
			callback = function(value)
				local state=altairValues.cameraState
				if state and state.closingCamera==camera then
					local target=camera
					state:CancelClose()
					state.owned[target]=nil;state.pendingRestore[target]=nil
				end
				tweenService:Create(camera, TweenInfo.new(fovMotionDuration(0.6), Enum.EasingStyle.Exponential), { FieldOfView = value }):Play()
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
			{name="UI Size",settingType="Slider",current=110,id="uisize",values={65,250},description="Drag to choose a fixed UI size. Your choice stays the same across resolutions."},
			{name="Theme Color",settingType="ColorPicker",current="5B8DEF",id="themecolor",description="Choose a color; the second bar controls how strongly it tints Altair."},
            {name="Theme Tint",settingType="Slider",current=25,id="themetint",values={0,100},description="Subtle accents at low values, full color at 100%."},
            {name="Theme Lightness",settingType="Slider",current=0,id="themelightness",values={0,100},description="Lift the theme from dark surfaces toward a light appearance."},
            {name="Custom Theme",settingType="Boolean",current=false,id="customtheme",hidden=true},
            {name="Panel Opacity",settingType="Slider",current=90,id="panelopacity",values={0,100},description="Choose how solid Altair's surfaces look. 0% is transparent; 100% is solid."},
            {name="OLED Idle Dim",settingType="Slider",current=0,id="oledidledim",values={0,65},description="Dim only Altair after inactivity. Zero disables it; input or a notification restores brightness."},
            {name="Idle Dim Delay",settingType="Slider",current=45,id="oledidledelay",values={15,180},suffix=" s",description="How long Altair waits before idle dimming."},
            {name="Notification Duration",settingType="Slider",current=5,id="notificationduration",values={3,12},step=1,suffix=" s",description="Default time on screen. Important notifications can request their own duration."},
            {name="Reduce Motion",settingType="Boolean",current=false,id="reducemotion",description="Use brief fades and minimal movement throughout Altair."},
			{name="OLED Appearance",settingType="Boolean",current=false,id="oledappearance",description="Use true-black panel surfaces with restrained highlights."},
			{name="Server Region Lookup",settingType="Boolean",current=false,id="serverregionlookup",onChangedSync=true,description="Off uses a region supplied by the experience. On sends the game-server IP to ipapi.co, which also sees your connection IP.",onChanged=function(enabled)
				if altairValues.serverRegion then altairValues.serverRegion.policyChanged(enabled) end
			end},
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
				name = "Snap Visual Effects",
                description = "Pulse the Smartbar and show alignment guides when dragging onto a snap line.",
                settingType = "Boolean", current = true, id = "snapvisuals",
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
				description = "Temporarily disable active idle callbacks and restore them when turned off or Altair closes. This may prompt detection from Adonis or similar anti-cheats.",
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
					altairValues.actions[8].callback()
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
            {name="Session Performance",settingType="Stat",persistent=false,description="Live client frame rate and reported server latency."},
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
		description = "Audio protection, moderator notices and permission reviews. Player and chat signals are under Experimental.",
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
				allowEmpty = true,
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
				allowEmpty = true,
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
 {name="Experimental",description="Early features: player signals, chat checks, HUD avoidance, capsules and Spotify. Bugs are to be expected.",color=Color3.fromRGB(157,119,231),minimumLicense="Free",categorySettings={
  {section="Movement Detection",sectionDescription="Local observations of unusual movement. Game abilities, vehicles, lag and knockback can produce similar signals; no action is taken against players.",name="Suspicious Player Detection",settingType="Boolean",current=true,id="suspiciousplayerdetection",onChangedSync=true,description="Watch player movement and notify when repeated evidence exceeds the selected sensitivity.",onChanged=function()
   if not altairValues.lifecycle or not altairValues.lifecycle.alive then return end
   if altairValues.playerAnomaly.Clear then altairValues.playerAnomaly:Clear(false)end
  end},
  {name="Flight Detection",settingType="Boolean",current=true,id="detectflight",description="Look for sustained hovering or controlled airborne movement, excluding ordinary jumps, falls, seats, swimming and climbing."},
  {name="Speed Detection",settingType="Boolean",current=true,id="detectspeed",description="Look for sustained ground speed above the observed movement allowance, accounting for moving platforms and short bursts."},
  {name="Fling Detection",settingType="Boolean",current=true,id="detectfling",description="Look for repeated extreme spinning and fling-like physics. A single collision is not enough."},
  {name="Teleport Detection",settingType="Boolean",current=false,id="detectteleport",description="Look for repeated large position jumps. Leave off in games with frequent portals, dashes or scripted teleports."},
  {name="Jump Detection",settingType="Boolean",current=false,id="detectjump",description="Look for repeated large upward impulses without landing. Leave off in games with double jumps or launch abilities."},
  {name="Movement Detection Sensitivity",settingType="Slider",current=55,values={1,100},step=1,id="movementdetectionsensitivity",description="Higher values need less sustained evidence. Lower values are more conservative."},
  {section="Chat Detection",sectionDescription="Experimental local checks for repeated messages and sustained chat floods. Only messages this client receives can be considered.",name="Chat Spam Detection",settingType="Boolean",current=true,id="chatspamdetection",onChangedSync=true,description="Combine message bursts, duplicates, repeated links and repeated-character patterns. One loud message alone does not trigger an alert.",onChanged=function()
   if not altairValues.lifecycle or not altairValues.lifecycle.alive then return end
   if altairValues.chatModeration.Clear then altairValues.chatModeration:Clear(false)end
  end},
  {name="Anti-Spam Sensitivity",settingType="Slider",current=60,values={1,100},step=1,id="antispamsensitivity",description="Higher values identify repeated spam patterns sooner. Normal short replies and isolated capitalized messages need additional evidence."},
  {section="Detection Feedback",sectionDescription="Control notification detail and try the same observation rules on your own character. Self-test does not change your movement or send messages.",name="Detection Details",settingType="Boolean",current=true,id="detectiondetails",description="Include observed reasons and measurements in detection notifications."},
  {name="Detection Cooldown",settingType="Slider",current=45,values={10,180},step=1,suffix=" s",id="detectioncooldown",description="Minimum time between accepted alerts for the same player and signal."},
  {name="Detection Self Test",settingType="Boolean",current=false,persistent=false,id="detectionselftest",description="Include your own movement and received chat in the detectors for this run. Your alerts are labeled as self-tests.",onChanged=function()
   altairValues.playerAnomaly.users[localPlayer.UserId]=nil;altairValues.chatModeration.users[localPlayer.UserId]=nil
  end},
  {name="Detection Status",settingType="Action",description="Show active checks, observed players and accepted alert counts.",action=function()if altairValues.showDetectionStatus then altairValues.showDetectionStatus()end end},
  {name="Clear Detection History",settingType="Action",description="Clear accumulated movement and chat evidence without changing which checks are enabled.",action=function()
   if altairValues.playerAnomaly.Clear then altairValues.playerAnomaly:Clear(true)end
   if altairValues.chatModeration.Clear then altairValues.chatModeration:Clear(true)end
   if altairValues.showDetectionStatus then altairValues.showDetectionStatus(true)end
  end},
  {section="Game UI Avoidance",sectionDescription="Keep Altair outside game HUD elements. This experimental feature may miss fast-changing interfaces.",name="Avoid Game UI",settingType="Boolean",current=false,id="avoidgameui",description="Keep the dragged Smartbar and handle outside visible game HUD elements, sliding along their edges."},

			{section="Capsules",sectionDescription="Top controls, timers and stopwatch. Bugs may occur while these features are experimental.",name="Capsules Enabled", settingType="Boolean", current=true, id="capsulesenabled"},
			{name="Capsule Scale", settingType="Number", current=1.25, values={0.65,2}, id="capsulescale"},
            {name="Capsule Position",settingType="Choice",current="Dynamic",values={"Dynamic","Fixed","Drag Bar Only"},id="capsuleposition",description="Dynamic avoids game HUDs. Fixed stays at the top. Drag Bar Only reveals on hover."},
            {name="Capsule Reveal Duration",settingType="Slider",current=4,values={1,15},step=1,suffix=" s",id="capsulerevealtime",description="Time to reach a revealed capsule. Hovering or using its panel keeps it open."},
            {section="Spotify",sectionDescription="Windows desktop: run Companion/StartSpotify.cmd, play something in Spotify, then connect. Volt pairs automatically; no developer app is needed.",name="Connect Spotify",settingType="Action",description="Connect desktop playback or restore your saved link. Optional Web API settings are below.",action=function()if altairValues.capsules then altairValues.capsules:LinkSpotify()end end},
            {name="Spotify Status",settingType="Action",description="Check playback, companion availability, and whether any action is needed.",action=function()if altairValues.capsules then altairValues.capsules:ShowSpotifyStatus()end end},
            {name="Spotify Setup",settingType="Action",description="1. Run Companion/StartSpotify.cmd. 2. Open Spotify desktop and play something. 3. Choose Connect Spotify. Keep the companion running. Volt pairs automatically.",action=function()if altairValues.capsules then altairValues.capsules:ShowSetup()end end},
            {name="Spotify Connection",settingType="Boolean",current=false,id="spotifyenabled",confirmDisable=true,description="Keep Spotify updates enabled. Pausing updates preserves your saved link; turning this back on resumes automatic recovery."},
            {name="Unlink Spotify",settingType="Action",description="Ask before removing this computer's saved Spotify link.",action=function()if altairValues.capsules then altairValues.capsules:UnlinkSpotify()end end},
            {section="Spotify - Advanced (optional)",sectionDescription="Skip these for Spotify desktop with Volt. Use a Client ID for Web API playback on other devices, or manual bridge settings for other executors.",name="Spotify Client ID",settingType="Input",current="",id="spotifyclientid",allowEmpty=true,description="Optional public Client ID for Web API approval. Clearing this field keeps any saved Web API account linked; it does not switch playback modes. Redirect: http://127.0.0.1:43827/callback (use your Bridge Port). Never enter a client secret."},
            {name="Spotify Client ID Override",settingType="Boolean",current=false,id="spotifyclientidmanual",hidden=true},
            {name="Spotify Bridge Key",settingType="Input",current="",id="spotifybridgekey",description="Manual pairing only: paste the companion's local key. Volt imports it automatically. Account tokens stay in the companion."},
            {name="Spotify Bridge Port",settingType="Number",current=43827,values={1024,65535},id="spotifyport",description="Keep 43827 unless you changed the companion port. The Spotify redirect must use the same port."},
 }},
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

-- Interface loading and resource lifetime
local guiParent = getHiddenUI and getHiddenUI() or (useStudio and localPlayer:WaitForChild("PlayerGui")) or coreGui
requireStartup()

function altairValues.loadUIModule(name)
	requireStartup()
	assert(({Build=true})[name], "Unknown Altair UI module")
	if useStudio then
		local container = script and script.Parent
		local folder = (script and script:FindFirstChild("UI")) or (container and container:FindFirstChild("UI"))
		local module = folder and folder:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), "Import UI/" .. name .. ".lua beside the Altair LocalScript")
		local result=require(module);requireStartup();return result
	end
	local source
	local read = optional(readfile)
	if read and not altairValues.remoteInterface then
		local ok, contents = pcall(read, altairValues.altairFolder .. "/UI/" .. name .. ".lua")
		if ok and type(contents)=="string" and contents:match("%S") then source=contents end
	end
	requireStartup()
	if not source then source=game:HttpGet(altairValues.interfaceSource:gsub("Build%.lua$",name..".lua").."?uiRevision=52") end
	requireStartup()
	assert(type(source)=="string" and source:match("%S"), "Empty Altair UI module: "..name)
	local compile=optional(loadstring)
	assert(compile,"This executor does not support loadstring")
 -- Keep compilation across reruns, never evaluated module state or UI instances.
 -- Exact bytes and environment identity matter even when the UI revision matches.
 local cache=env.__AltairUICompiledChunks
 if type(cache)~="table"then cache={};env.__AltairUICompiledChunks=cache end
 local inspectEnvironment=optional(getfenv)
 local function environmentOf(fn)
  if not inspectEnvironment then return nil end
  local ok,value=pcall(inspectEnvironment,fn)
  return ok and type(value)=="table"and value or nil
 end
 local environment=environmentOf(altairValues.loadUIModule)
 local entry=cache[name];local chunk
 if type(entry)=="table"and entry.source==source and entry.compiler==compile
  and environment~=nil and entry.environment==environment and optional(entry.chunk)
  and environmentOf(entry.chunk)==environment then
  chunk=entry.chunk
 else
  cache[name]=nil
  local compileError;chunk,compileError=compile(source,"@Altair/UI/"..name..".lua")
  assert(chunk,"Couldn't compile "..name..": "..tostring(compileError))
  if environment~=nil and environmentOf(chunk)==environment then
   entry={source=source,compiler=compile,environment=environment,chunk=chunk};cache[name]=entry
  else entry=nil end
 end
 requireStartup()
 local success,result=pcall(chunk)
 requireStartup()
 if not success then if cache[name]==entry then cache[name]=nil end;error(result,0)end
 if type(result)~="function"and cache[name]==entry then cache[name]=nil end
 return result
end

local function loadInterface()
	-- One contract drives local validation and the remote fallback. Loading,
	-- compilation, factory and contract failures all take that same route.
	local function validate(root,bindings)
		assert(typeof(root) == "Instance" and root:IsA("ScreenGui"), "The UI builder must return a ScreenGui")
		assert(root.Parent==nil,"The UI builder must return an unmounted ScreenGui")
		assert(type(bindings)=="table", "The UI builder must return a bindings table")
		assert(bindings.StartupOwnership==1,"Update UI/Build.lua: startup root and loading ownership contract 1 is required")
		assert(bindings.NativeUtilitiesOwnership==1,"Update UI/Build.lua: native utility ownership contract 1 is required")
		assert(bindings.IdleColorOwnership==1,"Update UI/Build.lua: idle color ownership contract 1 is required")
		assert(bindings.NavigationGeometryOwnership==1,"Update UI/Build.lua: dock navigation geometry contract 1 is required")
		assert(root:GetAttribute("AltairUIRevision")==52 and root:FindFirstChild("SpotifyUnlinkConfirmation"),"Update UI/Build.lua: matching UI revision 52 is required")
		assert(type(bindings)=="table" and type(bindings.Capsules)=="function" and type(bindings.SoftShadows)=="function" and type(bindings.Dock)=="function" and type(bindings.DragContrast)=="function" and root:FindFirstChild("SharedPanelSurface"), "Update UI/Build.lua: current UI bindings are missing")
		assert(type(bindings.SurfaceOpacity)=="function" and type(bindings.NavigationAccents)=="function" and type(bindings.Motion)=="function", "Update UI/Build.lua: current material/navigation bindings are missing")
		assert(root:FindFirstChild("TopCapsules") and root:FindFirstChild("NotificationCapsules"), "Update UI/Build.lua: capsule templates are missing")
		for _, name in ipairs({ "Character", "CustomScriptPrompt", "Disconnected", "GameDetection", "Home",
			"ModeratorDetectionPrompt", "Notifications", "Playerlist", "ScriptSearch", "Scripts", "Settings",
			"SmartBar", "Drag", "Toasts", "Starlight", "SecurityPrompt" }) do
			assert(root:FindFirstChild(name), "The UI builder is missing " .. name)
		end
		assert(root.SmartBar.Back:FindFirstChild("Time") and root.SmartBar.Back:FindFirstChild("Buttons"), "The SmartBar hierarchy is incomplete")
		assert(root.Drag:FindFirstChild("Interact"), "The drag handle has no input button")
		assert(type(bindings.Ruler)=="function" and type(bindings.CharacterRuler)=="function","Update UI/Build.lua: the ruler controls are missing")
		assert(type(bindings.Discovery)=="function" and root.ScriptSearch:IsA("CanvasGroup") and root.ScriptSearch:FindFirstChild("Header") and root.ScriptSearch:FindFirstChild("Browser"),"Update UI/Build.lua: the Script Search renderer is missing")
		for _,name in ipairs({"Loading","Theme","Notifications","HomeIsolation","HomeSurface","HomeContainer",
			"NativeUtilities","SettingsSearch","SettingsLayout","Slider","Choice","ColorPicker","Stats",
			"Resize","Surface","SlideContent","StopSlide","SlideHeading","BounceReset","SnapGuides",
			"ApplyIcon","RefreshIcon","DisplayScale","UIAvoidance","RayfieldBridge","Sentivel","SentivelSnapshot","MaterialAlpha","OpacityAlpha","ExperimentalSection","IdleColor","IdleBase","BindIdleColors"})do
			assert(type(bindings[name])=="function","Update UI/Build.lua: missing "..name.." binding")
		end
		local motion=bindings.Motion(function() return root:GetAttribute("AltairReduceMotion")==true end)
		assert(type(motion)=="table" and type(motion.Create)=="function", "The UI builder returned an invalid motion service")
		return motion
	end
	local function candidate(remote)
		altairValues.remoteInterface=remote
		local root,bindings,motion
		local attemptRoots={}
		local function observeAttemptRoot(object)
			observeStartupRoot(object)
			if typeof(object)=="Instance"and startupClaim.roots[object]then attemptRoots[object]=true end
		end
		local ok,problem=pcall(function()
			local build=altairValues.loadUIModule("Build")
			requireStartup()
			assert(type(build)=="function","UI/Build.lua must return a UI factory function")
			root,bindings=build({IsCurrent=ownsStartup,OnRoot=observeAttemptRoot})
			observeAttemptRoot(root);requireStartup()
			motion=validate(root,bindings)
			requireStartup()
		end)
		if not ok then
			-- A factory can expose its root and then throw before returning it.
			for object in pairs(attemptRoots)do
				if startupClaim.roots[object]then pcall(object.Destroy,object)end
			end
			if typeof(root)=="Instance"and not attemptRoots[root]and not root.Parent then pcall(root.Destroy,root)end
			requireStartup()
			return nil,tostring(problem)
		end
		return root,bindings,motion
	end
	local remote=altairValues.remoteInterface==true
	local root,bindings,motion=candidate(remote)
	if not root and not useStudio and not remote then root,bindings,motion=candidate(true)end
	assert(root,bindings or "The UI builder returned nothing")
	requireStartup()
	altairValues.interfaceBindings = bindings
	tweenService=motion
	return root
end

local uiResult, uiError
for attempt = 1, 3 do
	requireStartup()
	local success, result = pcall(loadInterface)
	requireStartup()
	if success and result then
		uiResult = result
		break
	end
	uiError = success and "the UI builder returned nothing" or tostring(result)
	if attempt < 3 then
		task.wait(attempt)
		requireStartup()
	end
end

if not uiResult then
	warn("Altair | Couldn't build the Lua interface after 3 attempts (" .. tostring(uiError) .. "). Altair has not started.")
	return
end

-- One owner for runtime resources; identifiers are not used to find them again.
altairValues.lifecycle = { alive = true, objects = {}, globals = {}, audio = {} }
startupClaim.lifecycle=altairValues.lifecycle
function altairValues.lifecycle:isCurrent()
	return self.alive and ownsStartup()
end
function altairValues.lifecycle:own(object)
	if not self:isCurrent()then pcall(object.Destroy,object);requireStartup();error("Altair is unloaded",0)end
	object.Name = httpService:GenerateGUID(false)
	self.objects[object] = true
	object.Destroying:Once(function() self.objects[object] = nil end)
	return object
end
function altairValues.lifecycle:replaceGlobal(key, value)
	assert(self:isCurrent(),"Altair lifecycle no longer owns global replacements")
	self.globals[key] = { before = env[key], installed = value }
	env[key] = value
end
function altairValues.lifecycle:unload()
	if not self.alive or self.unloading then return end
	self.unloading=true
	local inheritedCleanup=startupClaim.cleaning
	startupClaim.cleaning=true;startupClaim.alive=false
	if self.snapshot then pcall(self.snapshot) end
	self.alive = false
	local sentivel=self.sentivel;self.sentivel=nil
	if sentivel then pcall(sentivel.Destroy,sentivel)end
	if self.scriptLaunches then
		for key, token in pairs(self.scriptLaunches) do
			if env.AltairScriptRuns and env.AltairScriptRuns[key] == token then
				env.AltairScriptRuns[key] = nil
			end
		end
		table.clear(self.scriptLaunches)
	end
	if altairValues.cameraState then pcall(altairValues.cameraState.RestoreAll, altairValues.cameraState) end
	if altairValues.serverHop then pcall(altairValues.serverHop.cancel, altairValues.serverHop, true) end
	if altairValues.nativeTools then pcall(altairValues.nativeTools.Destroy, altairValues.nativeTools) end
	if altairValues.smartBarLayout then pcall(altairValues.smartBarLayout.cancelToastPositionTween, altairValues.smartBarLayout) end
	if self.developerCleanup then pcall(self.developerCleanup)end
	if self.muffleCleanup then pcall(self.muffleCleanup) end
	if self.runtimeCleanup then pcall(self.runtimeCleanup) end
 if altairValues.antiIdle then pcall(altairValues.antiIdle.Destroy,altairValues.antiIdle)end
 if altairValues.homeFovBinding then pcall(runService.UnbindFromRenderStep,runService,altairValues.homeFovBinding)end
 if altairValues.rayfieldBridge then pcall(altairValues.rayfieldBridge.Destroy,altairValues.rayfieldBridge)end
 if altairValues.homeIsolation then pcall(altairValues.homeIsolation.Destroy,altairValues.homeIsolation)end
 if altairValues.surfaceOpacity then pcall(altairValues.surfaceOpacity.Destroy,altairValues.surfaceOpacity)end
	for _, connection in ipairs(connections) do pcall(connection.Disconnect, connection) end
	table.clear(connections)
	for key, replacement in pairs(self.globals) do
		pcall(function()if env[key] == replacement.installed then env[key] = replacement.before end end)
	end
	table.clear(self.globals)
	for object in pairs(self.objects) do pcall(object.Destroy, object) end
	table.clear(self.objects)
	for root in pairs(startupClaim.roots)do pcall(root.Destroy,root)end
	table.clear(startupClaim.roots)
	table.clear(self.audio)
	pcall(function()if self.api and env.Altair == self.api then env.Altair = nil end end)
	self.unloading=false
	if not inheritedCleanup then
		startupClaim.cleaning=false;startupClaim.cleaned=true
		if env.__AltairStartupClaim==startupClaim then env.__AltairStartupClaim=nil end
	end
end

-- A new place/server continues the experience; a new universe starts a new session.
altairValues.sessionMemory = { key="Altair.Context.v1", startedAt=os.time(), hops=0 }
do
	local context = altairValues.sessionMemory
	local ok, saved = pcall(teleportService.GetTeleportSetting, teleportService, context.key)
	local now = os.time()
	local function stamp(value) return type(value)=="number" and value==value and value>=0 and value<=now end
	local sameIdentity = ok and type(saved)=="table" and saved.version==1 and saved.universe==game.GameId
		and saved.user==localPlayer.UserId and type(saved.job)=="string" and saved.job~=""
	local same = sameIdentity and stamp(saved.at) and (saved.job==game.JobId or now-saved.at<600)
	if same then
		context.resumed = true
		context.startedAt = stamp(saved.startedAt) and saved.startedAt or now
		local hops=tonumber(saved.hops) or 0
		context.hops = (hops==hops and math.floor(math.clamp(hops,0,10000)) or 0) + (saved.job~=game.JobId and 1 or 0)
		context.position = type(saved.position)=="table" and saved.position or nil
		context.home = type(saved.home)=="table" and saved.home or nil
		context.open = type(saved.open)=="boolean" and saved.open or nil
		if saved.open==false then context.open=false end
		if type(saved.username)=="string" and #saved.username>=3 and #saved.username<=20
			and saved.username:match("^[%w_]+$") and type(saved.displayName)=="string"
			and #saved.displayName>0 and #saved.displayName<=64 then
			randomUsername, randomDisplayName = saved.username, saved.displayName
		end
	end
	-- A same-job clock rollback must not erase the public poll reservation.
	-- Keep the general UI/session context rejected; sanitize only service health.
	local statusContext=same or(sameIdentity and saved.job==game.JobId and type(saved.at)=="number"
		and saved.at==saved.at and math.abs(saved.at)<math.huge and saved.at>now)
	if statusContext and type(altairValues.interfaceBindings.SentivelSnapshot)=="function" then
		context.sentivel=altairValues.interfaceBindings.SentivelSnapshot(saved.sentivel)
	end
	function context:save()
		if not altairValues.lifecycle.alive then return end
		if self.captureHome then self.home=self.captureHome() end
		pcall(teleportService.SetTeleportSetting, teleportService, self.key, {
			version=1, universe=game.GameId, user=localPlayer.UserId, job=game.JobId, at=os.time(),
			startedAt=self.startedAt, hops=self.hops, position=self.position, home=self.home,
			open=smartBarOpen, username=randomUsername, displayName=randomDisplayName,
			sentivel=self.sentivel,
		})
		self.lastSave=os.clock()
	end
	altairValues.lifecycle.snapshot=function() context:save() end
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
fovMotionRoot = UI
UI.Destroying:Once(function() altairValues.lifecycle:unload() end)
espContainer = altairValues.lifecycle:own(Instance.new("Folder"))
requireStartup()
espContainer.Parent = guiParent
UI.Enabled = false -- Never render the interface at its authored position.
requireStartup()
UI.Parent = guiParent
altairValues.loadingPosition=altairValues.sessionMemory.position
if not altairValues.loadingPosition and type(readfile)=="function"then
 local ok,value=pcall(function()return httpService:JSONDecode(readfile(altairValues.altairFolder.."/position.altair"))end)
 if ok and type(value)=="table"then altairValues.loadingPosition=value end
end
requireStartup()
altairValues.loading=altairValues.interfaceBindings.Loading(UI,guiParent,nil,altairValues.loadingPosition,function(screen)altairValues.lifecycle:own(screen)end)
requireStartup()
if not altairValues.lifecycle.objects[altairValues.loading.Screen]then altairValues.lifecycle:own(altairValues.loading.Screen)end
altairValues.loading:Stage(.2,"Preparing interface")
altairValues.theme=altairValues.interfaceBindings.Theme(UI)
requireStartup()
altairValues.theme:Attach(altairValues.loading.Screen)

-- Volt/CoreGui: use the full physical viewport, not Roblox top-bar / safe-area insets.
-- Do this immediately so every later AbsolutePosition/AbsoluteSize read uses the
-- same coordinate space as Rayfield Gen 2.
if UI:IsA("ScreenGui") then
	UI.IgnoreGuiInset = true
	pcall(function() UI.ScreenInsets = Enum.ScreenInsets.None end)
	pcall(function() UI.ClipToDeviceSafeArea = false end)
end

UI.Enabled = false

-- Interface references
local characterPanel = UI.Character
local openHome, closeHome
local homeOpen, homeFov = false, nil
local closeSettings, closeScriptSearch, openSettings
local homeChatEnabled
local characterPanelSize = characterPanel.Size
local customScriptPrompt = UI.CustomScriptPrompt
local disconnectedPrompt = UI.Disconnected
-- The recovery prompt can move into RobloxPromptGui; keep it owned on reload.
altairValues.lifecycle.objects[disconnectedPrompt]=true
disconnectedPrompt.Destroying:Once(function()altairValues.lifecycle.objects[disconnectedPrompt]=nil end)
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
altairValues.surfaceOpacity=altairValues.interfaceBindings.SurfaceOpacity(UI,tweenService)

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

-- Shared UI and preference helpers
local httpRequest = originalRequest

local function track(connection)
	if not altairValues.lifecycle:isCurrent()then connection:Disconnect(); return connection end
	table.insert(connections, connection)
	return connection
end

-- Camera ownership can change while every Altair panel is closed. Keep the
-- previous camera only for layout measurements during a temporary nil gap;
-- camera actions below require the current live instance returned here.
local cameraState = {
	available = true,
	closeVersion = 0,
	baselines = setmetatable({ [camera] = baseFieldOfView }, { __mode = "k" }),
	owned = setmetatable({}, { __mode = "k" }),
	pendingRestore = setmetatable({}, { __mode = "k" }),
}
altairValues.cameraState = cameraState
function cameraState:CancelClose()
	self.closeVersion += 1
	local animation = altairValues.homeCameraTween
	altairValues.homeCameraTween = nil
	self.closingCamera = nil
	if animation then animation:Cancel() end
end
function cameraState:Restore(target)
	if not target or not self.owned[target] then return true end
	if self.closingCamera == target then self:CancelClose() end
	local ok = pcall(function() target.FieldOfView = self.baselines[target] end)
	if ok then
		self.owned[target] = nil
		self.pendingRestore[target] = nil
	else
		self.pendingRestore[target] = true
	end
	return ok
end
function cameraState:Own(target)
	if self.pendingRestore[target] and not self:Restore(target) then return nil end
	if not self.owned[target] then
		self.baselines[target] = target.FieldOfView
		self.owned[target] = true
	end
	return self.baselines[target]
end
function cameraState:RestoreAll()
	self:CancelClose()
	for target in pairs(self.owned) do self:Restore(target) end
end
local function syncCamera()
	local current = workspace.CurrentCamera
	-- Cleanup may ask for the live camera after the lifecycle is marked dead;
	-- only explicit Restore/RestoreAll calls may change FOV at that point.
	if not altairValues.lifecycle.alive then return current end
	if not current then
		if cameraState.available then cameraState:Restore(camera) end
		cameraState.available = false
		return nil
	end
	if current ~= camera or not cameraState.available then
		if current ~= camera then cameraState:Restore(camera) end
		-- A nil gap can return the same instance. Finish any pending restore
		-- before treating it as available or capturing a new ownership baseline.
		if cameraState.pendingRestore[current] and not cameraState:Restore(current) then return nil end
		camera = current
		cameraState.available = true
		if not cameraState.owned[current] then cameraState.baselines[current] = current.FieldOfView end
		baseFieldOfView = cameraState.baselines[current]
		if homeOpen then
			homeFov = cameraState:Own(current)
			if not homeFov then return nil end
			altairValues.homeTargetFov = math.max(20, homeFov - 35)
			if altairValues.homeFovTarget then
				-- Supersede any zoom tween targeting the previous camera's baseline.
				tweenService:Create(altairValues.homeFovTarget, TweenInfo.new(0), { Value = altairValues.homeTargetFov }):Play()
				altairValues.homeFovTarget.Value = altairValues.homeTargetFov
			end
		else
			homeFov = nil
		end
		if spectating then
			local character = spectating.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				current.CameraSubject = humanoid
				current.CameraType = Enum.CameraType.Custom
			end
		end
	end
	return current
end
track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if altairValues.lifecycle.alive then syncCamera() end
end))
syncCamera()

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
	if action.control=="Daylight"then altairValues.interfaceBindings.ApplyIcon(object.Icon,"sun")else object.Icon.Image = "rbxassetid://" .. action.images[action.enabled and 1 or 2]end
	if quickToggle then
		object.Subtitle.Text = action.enabled and "Enabled" or "Disabled"
	end
	if not characterPanel.Visible or debounce then return end
	if quickToggle then
		tweenService:Create(object.Subtitle, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = action.enabled and 0 or 0.25 }):Play()
		tweenService:Create(object.Glow, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0.15 or 0.8 }):Play()
	end
	tweenService:Create(object, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { BackgroundTransparency = action.enabled and 0.02 or (quickToggle and 0.12 or 0.1) }):Play()
	tweenService:Create(object.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Transparency = action.enabled and .55 or .9 }):Play()
	tweenService:Create(object.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = action.enabled and 0 or 0.15 }):Play()
	tweenService:Create(object.Title, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
end

local function checkAltair()
	return altairValues.lifecycle:isCurrent() and UI.Parent
end

-- Preserve ownership of callbacks changed by Anti Idle. Other scripts may
-- intentionally disable their own callbacks; Altair must not enable those.
function altairValues.newAntiIdleController(getCallbacks)
 local controller={alive=true,enabled=false,owned={}}
 local function enabled(connection)
  local ok,value=pcall(function()return connection.Enabled end)
  if ok and type(value)=="boolean"then return value end
  return nil -- Unknown state cannot safely be changed and later restored.
 end
 function controller:Restore()
  self.enabled=false
  for connection in pairs(self.owned)do pcall(function()connection:Enable()end)end
  table.clear(self.owned)
 end
 function controller:Set(value)
  value=value==true
  if not self.alive or self.enabled==value then return false end
  self.enabled=value
  if not value then self:Restore();return true end
  local ok,callbacks=pcall(getCallbacks)
  if not ok or type(callbacks)~="table"then return false end
  for _,connection in pairs(callbacks)do
   if enabled(connection)==true then
    local changed=pcall(function()connection:Disable()end)
    if changed then self.owned[connection]=true end
   end
  end
  return true
 end
 function controller:Destroy()
  if not self.alive then return end
  self.alive=false;self:Restore()
 end
 return controller
end
altairValues.antiIdle=altairValues.newAntiIdleController(function()
 return getConnectionsFor and getConnectionsFor(localPlayer.Idled)or{}
end)

local function getPing()
	local success, ping = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return success and math.clamp(ping, 10, 700) or 0
end

local function checkFolder(owns)
	local function current()return not owns or owns()end
	if not current()then return false end
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
		if not current()then return false end
		local exists=isfolder(path)
		if not current()then return false end
		if not exists then
			makefolder(path)
			if not current()then return false end
		end
	end

	local function missing(path)
		if not current()then return false end
		local exists=isfile(path)
		return current()and not exists
	end
	if writefile and isfile and missing(customRoot .. "/README.txt") then
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
		if not current()then return false end
	end

	if writefile and isfile and missing(scriptsRoot .. "/README.txt") then
		writefile(scriptsRoot .. "/README.txt", [[Altair Scripts

Place runnable .lua files in this folder.

Reference them from a file in Altair/Custom Scripts with:
"LuaFile": "YourScript.lua"
]])
		if not current()then return false end
	end
	return current()
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
		if not checkAltair()or not highlight.Parent then return end
		highlight.Adornee = character
	end)
end

local function actionButton(action)
	if not action then
		return nil
	end
	return characterPanel.Interactions.Toggles:FindFirstChild(action.name) or characterPanel.Interactions.Grid:FindFirstChild(action.name) or characterPanel.Interactions:FindFirstChild(action.name,true)
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

            if tween then
             tweenService:Create(obj,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),tweenProperties):Play()
            else
             for property,value in pairs(tweenProperties)do if obj[property]~=value then obj[property]=value end end
            end
		end
	end

	if checkSelf then
		applyTransparency(ins)
	end

 local function visit(parent)
  for _,child in ipairs(parent:GetChildren())do
   if child:GetAttribute("AltairFadeGroup")then
    if tween then tweenService:Create(child,TweenInfo.new(duration,Enum.EasingStyle.Quint),{GroupTransparency=target}):Play()else child.GroupTransparency=target end
   else applyTransparency(child);visit(child)end
  end
 end
 visit(ins)
end

function altairValues.captureFadeState(root)
 local snapshot=setmetatable({}, {__mode="k"})
 local function visit(parent)
  for _,object in ipairs(parent:GetChildren())do
   local group=object:GetAttribute("AltairFadeGroup")
   local properties=group and{"GroupTransparency"}or altairValues.transparencyProperties[object.ClassName]
   if properties then local saved={};snapshot[object]=saved;for _,key in ipairs(properties)do saved[key]=object[key]end end
   if not group then visit(object)end
  end
 end
 visit(root);return snapshot
end

-- Keep authored surface hierarchy while applying the user's opacity preference.
function altairValues.surfaceTransparency(surface,base)
 base=tonumber(base)or UI:GetAttribute("AltairPanelTransparency")or .1
 base=math.clamp(base,0,1)
 if base<=0 then return 0 elseif base>=1 then return 1 end
 local authored=surface:GetAttribute("AltairDesignFixedTransparency")
 if type(authored)~="number"then authored=.1+(surface:GetAttribute("AltairDesignTransparencyOffset")or 0)end
 authored=math.clamp(authored,0,1)
 return base<.1 and authored*base/.1 or authored+(1-authored)*(base-.1)/.9
end

-- Dialog templates own their layout/material; this owner only moves and fades them.
altairValues.dialogMotion=(function()
 local states=setmetatable({},{__mode="k"})
 local controller={}
 local function stateFor(panel)
  local state=states[panel]
  if not state then state={version=0};states[panel]=state end
  return state
 end
 local function material(panel)
  return panel:FindFirstChild("Backdrop")or panel
 end
 local function refreshElementMaterials(state)
  if not state.targets then return end
  local transparency=UI:GetAttribute("AltairPanelTransparency")
  if state.targetTransparency==transparency then return end
  local registry=altairValues.surfaceOpacity
  if not registry or not registry.Resolve then return end
  for item,properties in pairs(state.targets)do
   if item.Parent and properties.BackgroundTransparency~=nil then
    local alpha=registry:Resolve(item)
    if type(alpha)=="number"then properties.BackgroundTransparency=alpha end
   end
  end
  state.targetTransparency=transparency
 end
 local function shifted(panel,position,pixels)
  local parent=panel.Parent
  local height=parent and parent.AbsoluteSize.Y or UI.AbsoluteSize.Y
  return position+UDim2.fromScale(0,pixels/math.max(1,height))
 end
 function controller:IsOpen(panel)
  return panel.Parent~=nil and panel.Visible and not panel:GetAttribute("AltairDialogClosing")
 end
 function controller:Owns(panel,version)
  local state=states[panel]
  return state~=nil and state.version==version and self:IsOpen(panel)
 end
 function controller:Open(panel,nativePrompt)
  assert(panel:IsA("CanvasGroup"),"Update UI/Build.lua: dialog groups are missing")
  local feedback=altairValues.interfaceBindings.DialogFeedback
  if feedback then feedback(panel)end
  local state=stateFor(panel)
  if state.opened and self:IsOpen(panel)then return state.version end
  local cold=not panel.Visible
  state.version+=1;state.opened=true;state.dialog=true
  state.rest=panel:GetAttribute("AltairDialogPosition")or state.rest or panel.Position
  local size=panel:GetAttribute("AltairDialogSize")or panel.Size
  if panel==disconnectedPrompt then
   state.baseRest=state.baseRest or state.rest
   state.rest=state.baseRest
   local parent=panel.Parent
   if typeof(nativePrompt)=="Instance"and nativePrompt:IsA("GuiObject")and nativePrompt.Visible and parent and parent:IsA("ScreenGui")and nativePrompt:IsDescendantOf(parent)then
    local viewport=parent.AbsoluteSize
    local nativeSize=nativePrompt.AbsoluteSize
    local height=panel.AbsoluteSize.Y
    if height<=0 then
     local scale=panel:FindFirstChildOfClass("UIScale")
     height=(size.Y.Scale*viewport.Y+size.Y.Offset)*(scale and scale.Scale or 1)
    end
    if viewport.X>0 and viewport.Y>0 and nativeSize.X>0 and nativeSize.Y>0 and height>0 then
     local y=state.baseRest.Y.Scale*viewport.Y+state.baseRest.Y.Offset
     local top=y-panel.AnchorPoint.Y*height
     local nativeTop=nativePrompt.AbsolutePosition.Y-parent.AbsolutePosition.Y
     -- Reserve 12px clearance plus the existing 14px downward entrance travel.
     local shift=math.min(math.max(0,top+height-nativeTop+26),math.max(0,top-12))
     state.rest=UDim2.new(state.baseRest.X.Scale,state.baseRest.X.Offset,state.baseRest.Y.Scale,state.baseRest.Y.Offset-shift)
    end
   end
   panel:SetAttribute("AltairDialogPosition",state.rest)
  end
  panel:SetAttribute("AltairDialogClosing",false)
  panel.Interactable=true
  local surface=material(panel)
  if surface~=panel then panel.BackgroundTransparency=1 end
  if cold then
   panel.Size=size;panel.Position=shifted(panel,state.rest,14)
   panel.GroupTransparency=1;surface.BackgroundTransparency=altairValues.surfaceTransparency(panel)
  else tweenService:Create(surface,TweenInfo.new(.18),{BackgroundTransparency=altairValues.surfaceTransparency(panel)}):Play()end
  panel.Visible=true
  tweenService:Create(panel,TweenInfo.new(.3,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=state.rest,Size=size}):Play()
  tweenService:Create(panel,TweenInfo.new(.18,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{GroupTransparency=0}):Play()
  return state.version
 end
 function controller:Close(panel,onHidden)
  if not panel.Parent then return end
  local state=stateFor(panel);state.version+=1;state.opened=false
  local version=state.version
  if not panel.Visible then if onHidden then onHidden()end;return end
  state.rest=panel:GetAttribute("AltairDialogPosition")or state.rest or panel.Position
  panel:SetAttribute("AltairDialogClosing",true);panel.Interactable=false
  for _,object in ipairs(panel:GetDescendants())do if object:IsA("TextBox")and object:IsFocused()then object:ReleaseFocus()end end
  tweenService:Create(panel,TweenInfo.new(.2,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=shifted(panel,state.rest,10)}):Play()
  tweenService:Create(panel,TweenInfo.new(.16,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{GroupTransparency=1}):Play()
  task.delay(.21,function()
   if panel.Parent and state.version==version then
    panel.Visible=false;panel.Position=state.rest
    panel:SetAttribute("AltairDialogClosing",false)
    if onHidden then onHidden()end
   end
  end)
 end
 function controller:Element(object,visible)
  local state=stateFor(object);state.elementVersion=(state.elementVersion or 0)+1
  local version=state.elementVersion
  if not state.targets then
   state.targets=altairValues.captureFadeState(object)
   local properties=altairValues.transparencyProperties[object.ClassName]
   if properties then local saved={};for _,key in ipairs(properties)do saved[key]=object[key]end;state.targets[object]=saved end
  end
  refreshElementMaterials(state)
  if visible and not object.Visible then
   for item,properties in pairs(state.targets)do if item.Parent then for key in pairs(properties)do item[key]=1 end end end
  end
  object.Interactable=visible
  if visible then object.Visible=true end
  for item,properties in pairs(state.targets)do if item.Parent then
   local goal={};for key,value in pairs(properties)do goal[key]=visible and value or 1 end
   tweenService:Create(item,TweenInfo.new(.14),goal,{ResolvedTransparency=true}):Play()
  end end
  if not visible then task.delay(.15,function()if object.Parent and state.elementVersion==version then object.Visible=false end end)end
 end
 function controller:RefreshOpacity()
  for panel,state in pairs(states)do
   refreshElementMaterials(state)
   if state.dialog and self:IsOpen(panel)then
    tweenService:Create(material(panel),TweenInfo.new(.18),{BackgroundTransparency=altairValues.surfaceTransparency(panel)}):Play()
   end
  end
 end
 function controller:Accent(panel,color)
  if typeof(color)~="Color3"then return end
  local refresh=altairValues.interfaceBindings.DialogAccent
  if refresh then refresh(panel,color)else panel:SetAttribute("AltairDialogAccent",color)end
 end
 return controller
end)()

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

notificationContainer.Visible = false
altairValues.notificationController = altairValues.interfaceBindings.Notifications({Root=UI,RequireBuiltUI=true})
local function notification(Title, Description, Image, options)
 altairValues.lastUIActivity=os.clock()
 if type(Title)=="table" then
  local data=Title;Title=data.Title or data.title or "Altair";Description=data.Description or data.Content or data.description
  Image=data.Icon or data.Image;options={Duration=data.Duration,Key=data.Key}
 end
	return altairValues.notificationController:Notify(Title, Description, Image, options)
end

function altairValues.showDetectionStatus(cleared)
 local movement=altairValues.playerAnomaly.Summary and altairValues.playerAnomaly:Summary()or{}
 local chat=altairValues.chatModeration.Summary and altairValues.chatModeration:Summary()or{}
 local sampling=movement.sampling or{}
 local checks={}
 if settingValue("Suspicious Player Detection",true)then
  for _,name in ipairs({"Flight","Speed","Fling","Teleport","Jump"})do
   if settingValue(name.." Detection",name~="Teleport"and name~="Jump")then checks[#checks+1]=name end
  end
 end
 local lines={}
 -- Keep timing limits first: notification bodies are height-bounded.
 if #checks==0 then
  lines[#lines+1]="Sampling paused; no current rechecks."
 elseif(sampling.count or 0)==0 then
  lines[#lines+1]=movement.checks and movement.checks.teleport and"Teleport timing unknown: no recent player rechecks yet."or"Sampling: no recent player rechecks yet."
 elseif movement.checks and movement.checks.teleport and sampling.teleportTiming=="unavailable"then
  lines[#lines+1]=string.format("Teleport configured but timing unavailable: all %d retained recent rechecks exceeded 1.2s.",sampling.count)
 elseif movement.checks and movement.checks.teleport and(sampling.overTeleportLimit or 0)>0 then
  lines[#lines+1]=string.format("Teleport timing limited: %d/%d recent rechecks exceeded 1.2s.",sampling.overTeleportLimit,sampling.count)
 else
  lines[#lines+1]=string.format("Sampling: %d recent rechecks, %.2f-%.2fs.",sampling.count,sampling.minimum,sampling.maximum)
 end
 lines[#lines+1]="Movement"..(movement.selfTest and" (self-test on)"or"")..": "..(#checks>0 and table.concat(checks,", ")or"Paused")
 if cleared then lines[#lines+1]="Accumulated movement and chat evidence was cleared."end
 lines[#lines+1]=string.format("Observed: %d players · %d movement samples · %d accepted movement alerts",movement.tracked or 0,movement.samples or 0,movement.alerts or 0)
 lines[#lines+1]=string.format("Chat: %s · %d observed senders · %d accepted chat alerts",settingValue("Chat Spam Detection",true)and"On"or"Paused",chat.tracked or 0,chat.alerts or 0)
 lines[#lines+1]="Self-test: "..(settingValue("Detection Self Test",false)and"On for this run"or"Off")
 notification("Experimental detections",table.concat(lines,"\n"),nil,{Key="detection-status",Duration=9})
end

-- Experimental movement observations. These are client-visible signals, not
-- proof of cheating: game abilities, replication and knockback can look alike.
function altairValues.playerAnomaly:headshot(player)
 return "rbxthumb://type=AvatarHeadShot&id="..tostring(player.UserId).."&w=150&h=150"
end

function altairValues.playerAnomaly:HasEnabledChecks()
 return settingValue("Suspicious Player Detection",true)and(
  settingValue("Flight Detection",true)or settingValue("Speed Detection",true)
  or settingValue("Fling Detection",true)or settingValue("Teleport Detection",false)
  or settingValue("Jump Detection",false))
end

function altairValues.playerAnomaly:Clear(resetStats)
 table.clear(self.users);self.cursor=1
 self.revisitIntervals=nil;self.revisitIndex=1
 if resetStats then self.samples=0;self.alerts=0;self.lastAlert=nil end
end

function altairValues.playerAnomaly:Summary()
 local tracked=0;for _ in pairs(self.users)do tracked+=1 end
 local sampling={count=0,withinTeleportLimit=0,overTeleportLimit=0,window=30,capacity=64}
 if self:HasEnabledChecks()then
  local now=os.clock()
  for _,interval in ipairs(self.revisitIntervals or{})do
   if now-interval.at>=0 and now-interval.at<=sampling.window then
    sampling.count+=1
    sampling.minimum=sampling.minimum and math.min(sampling.minimum,interval.dt)or interval.dt
    sampling.maximum=sampling.maximum and math.max(sampling.maximum,interval.dt)or interval.dt
    if interval.dt<=1.2 then sampling.withinTeleportLimit+=1 else sampling.overTeleportLimit+=1 end
   end
  end
 end
 -- Timing snapshot only: retained rechecks are not player coverage or eligibility.
 sampling.teleportTiming=sampling.count==0 and"unknown"or sampling.withinTeleportLimit==0 and"unavailable"
  or sampling.overTeleportLimit>0 and"limited"or"within-limit"
 return {tracked=tracked,samples=self.samples or 0,alerts=self.alerts or 0,lastAlert=self.lastAlert,
  sampling=sampling,
  selfTest=settingValue("Detection Self Test",false),checks={
   flight=settingValue("Flight Detection",true),speed=settingValue("Speed Detection",true),
   fling=settingValue("Fling Detection",true),teleport=settingValue("Teleport Detection",false),
   jump=settingValue("Jump Detection",false)}}
end

function altairValues.playerAnomaly:notify(player,kind,detail,evidence,threshold,metrics)
 if not checkAltair()then return false end
 local record=self.users[player.UserId]
 if not record or not self:HasEnabledChecks()then return false end
 local now=os.clock();local cooldown=math.clamp(tonumber(settingValue("Detection Cooldown",45))or 45,10,300)
 local previous=record.lastAlerts[kind]
 if previous and now-previous<cooldown then return false end
 -- Bound cross-player bursts as well as per-player alerts; retry rejected
 -- signals on later samples instead of permanently latching an unseen alert.
 if self.lastNotification and now-self.lastNotification<2 then return false end
 local titles={flight="Flight / hover signal",speed="Unusual speed",fling="Unusual spinning physics",teleport="Repeated position jumps",jump="Repeated airborne lift"}
 local selfTest=player==localPlayer
 local text=(selfTest and"Your character"or player.DisplayName.." (@"..player.Name..")").." shows "..detail.."."
 if settingValue("Detection Details",true)and metrics and metrics~=""then text..=" "..metrics end
 text..=selfTest and" Self-test observation only."or" Observed locally."
 local accepted=notification((selfTest and"Self-test · "or"")..(titles[kind]or"Movement signal"),text,self:headshot(player),{Key="movement-"..tostring(player.UserId).."-"..kind,Duration=7})
 if accepted==nil or accepted==false then return false end
 if not checkAltair()or self.users[player.UserId]~=record or not self:HasEnabledChecks()then return false end
 record.lastAlerts[kind]=now;self.lastNotification=now;self.alerts=(self.alerts or 0)+1
 self.lastAlert={userId=player.UserId,name=player.Name,kind=kind,time=now,evidence=evidence,threshold=threshold,selfTest=selfTest}
 return true
end

function altairValues.playerAnomaly:signal(player,record,kind,value,threshold,enabled,detail,metrics)
 local signal=record.signals[kind]
 if not signal then signal={value=0,latched=false};record.signals[kind]=signal end
 if not enabled then signal.value=0;signal.latched=false;return end
 signal.value=math.clamp(value,0,20)
 if signal.value<=threshold*.25 then signal.latched=false end
 if signal.value>=threshold and not signal.latched and self:notify(player,kind,detail,signal.value,threshold,metrics)and type(record.signals)=="table"and record.signals[kind]==signal then signal.latched=true end
end

function altairValues.playerAnomaly:samplePlayer(player,now)
 if player==localPlayer and not settingValue("Detection Self Test",false)then self.users[player.UserId]=nil;return end
 local character=player.Character
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 local part=character and(character:FindFirstChild("HumanoidRootPart")or character.PrimaryPart)
 if not humanoid or not part or not part:IsA("BasePart")or humanoid.Health<=0 then self.users[player.UserId]=nil;return end
 local record=self.users[player.UserId]
 if not record or record.character~=character or record.part~=part then
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={character};params.IgnoreWater=true
  record={character=character,part=part,lastPosition=part.Position,lastVelocity=part.AssemblyLinearVelocity,lastSample=now,
   born=now,graceUntil=now+4,signals={},lastAlerts={},teleports={},jumps={},params=params,baseWalkSpeed=humanoid.WalkSpeed,groundVelocity=Vector3.zero}
  self.users[player.UserId]=record;return
 end
 local dt=now-record.lastSample
 if dt<=0 then return end
 local evidenceDt=math.min(dt,.75)
 local position,velocity,angular=part.Position,part.AssemblyLinearVelocity,part.AssemblyAngularVelocity
 local delta=position-record.lastPosition;local oldVelocity=record.lastVelocity
 record.lastPosition=position;record.lastSample=now;record.lastVelocity=velocity
 self.samples=(self.samples or 0)+1
 -- Reuse 64 timing slots in the existing sampler; no player identifiers.
 local intervals=self.revisitIntervals
 if not intervals then intervals={};self.revisitIntervals=intervals end
 local intervalIndex=self.revisitIndex or 1
 local interval=intervals[intervalIndex]or{};interval.dt=dt;interval.at=now
 intervals[intervalIndex]=interval;self.revisitIndex=intervalIndex%64+1
 local sensitivity=math.clamp(tonumber(settingValue("Movement Detection Sensitivity",55))or 55,1,100)
 local factor=1.45-sensitivity*.0055
 local thresholds={flight=5.5*factor,speed=4*factor,fling=2.2*factor,teleport=1.7*factor,jump=1.7*factor}
 local enabled={flight=settingValue("Flight Detection",true),speed=settingValue("Speed Detection",true),fling=settingValue("Fling Detection",true),teleport=settingValue("Teleport Detection",false),jump=settingValue("Jump Detection",false)}
 local function prior(kind)local value=record.signals[kind];return value and value.value or 0 end
 local function decay(rate)
  for kind,threshold in pairs(thresholds)do
   local signal=record.signals[kind]
   if signal then
    signal.value=enabled[kind]and math.max(0,signal.value-dt*rate)or 0
    if signal.value<=threshold*.25 then signal.latched=false end
   end
  end
 end
 local state=humanoid:GetState()
 local excluded=humanoid.Sit or humanoid.SeatPart~=nil or part.Anchored
  or state==Enum.HumanoidStateType.Seated or state==Enum.HumanoidStateType.Swimming
  or state==Enum.HumanoidStateType.Climbing or state==Enum.HumanoidStateType.Dead
 if excluded or dt>8 or now-record.born<4 or character:FindFirstChildOfClass("ForceField")then
  record.airSince=nil;record.groundSince=nil;record.spinSince=nil;record.groundVelocity=Vector3.zero
  table.clear(record.teleports);table.clear(record.jumps);decay(4);return
 end
 if now<record.graceUntil then record.airSince=nil;record.groundSince=nil;record.spinSince=nil;decay(4);return end
 local physics=state==Enum.HumanoidStateType.Ragdoll or state==Enum.HumanoidStateType.FallingDown or state==Enum.HumanoidStateType.GettingUp
 local grounded=humanoid.FloorMaterial~=Enum.Material.Air
 local groundVelocity=Vector3.zero
 if enabled.flight or enabled.speed or enabled.jump then
  local foot=math.clamp(tonumber(humanoid.HipHeight)or 2,0,12)+part.Size.Y*.5
  local hit=workspace:Raycast(position,Vector3.new(0,-math.max(8,foot+3),0),record.params)
  if hit and hit.Distance<=foot+1.6 then
   grounded=true
   if hit.Instance:IsA("BasePart")then groundVelocity=hit.Instance:GetVelocityAtPosition(position)end
  end
 end
 local relativeVelocity=velocity-groundVelocity
 local travel=delta/dt-(record.groundVelocity+groundVelocity)*.5
 record.groundVelocity=groundVelocity
 local horizontal=Vector3.new(relativeVelocity.X,0,relativeVelocity.Z).Magnitude
 local measured=Vector3.new(travel.X,0,travel.Z).Magnitude
 local angularSpeed=angular.Magnitude;local linearSpeed=velocity.Magnitude
 if grounded then record.airSince=nil;record.groundSince=record.groundSince or now
 else record.airSince=record.airSince or now;record.groundSince=nil end
 local airTime=record.airSince and now-record.airSince or 0
 local gravity=math.max(1,workspace.Gravity)
 local jumpVelocity=humanoid.UseJumpPower and humanoid.JumpPower or math.sqrt(math.max(0,2*gravity*humanoid.JumpHeight))
 local normalAirTime=2*jumpVelocity/gravity
 local flightDelay=math.max(3,normalAirTime*2.5)
 local acceleration=(velocity.Y-oldVelocity.Y)/dt
 -- Ordinary jumps, low gravity, elevators, conveyors, respawns and short
 -- knockback bursts do not accumulate a flight/speed signal by themselves.
 local flightRate=0
 if enabled.flight and not grounded and not physics and airTime>flightDelay then
  local steadyHeight=math.abs(relativeVelocity.Y)<5 and math.abs(travel.Y)<8
  local steadyRise=relativeVelocity.Y>12 and relativeVelocity.Y<math.max(120,jumpVelocity*2)and math.abs(acceleration)<gravity*.18
  if steadyHeight then flightRate=horizontal>12 and 1.8 or 1.35 elseif steadyRise then flightRate=1.1 end
 end
 local expected=math.max(8,humanoid.WalkSpeed)
 if player==localPlayer then expected=math.max(8,record.baseWalkSpeed)end
 local speedLimit=math.max(42,expected*1.8+8)
 local speedRate=0
 if enabled.speed and grounded and not physics and not humanoid.PlatformStand and now-(record.groundSince or now)>.65 then
  if measured>speedLimit and(horizontal>speedLimit*.65 or measured>speedLimit*1.5)then speedRate=measured>speedLimit*2 and 2.2 or 1.15 end
 end
 local extremeSpin=angularSpeed>180 or angularSpeed>90 and linearSpeed>65
 if extremeSpin then record.spinSince=record.spinSince or now else record.spinSince=nil end
 local spinTime=record.spinSince and now-record.spinSince or 0
 local flingRate=enabled.fling and not physics and extremeSpin and spinTime>.65 and(angularSpeed>260 and 2.8 or 1.9)or 0
 local function recent(events,window)
  while events[1]and now-events[1]>window do table.remove(events,1)end
  while #events>4 do table.remove(events,1)end
  return #events
 end
 local positionCorrection=dt<=1.2 and delta.Magnitude>math.max(90,expected*dt*5)
  and delta.Magnitude/dt>math.max(300,linearSpeed*3+80)and(not record.lastTeleport or now-record.lastTeleport>.45)
 if positionCorrection then
  if enabled.teleport then record.teleports[#record.teleports+1]=now end;record.lastTeleport=now
  -- Do not interpret a teleport/replication correction as a speed or jump burst.
  record.airSince=nil;record.groundSince=nil;record.graceUntil=now+.65;flightRate=0;speedRate=0
 end
 if enabled.jump and not positionCorrection and not grounded and not physics and not humanoid.PlatformStand and airTime>.55
  and oldVelocity.Y< -6 and velocity.Y>math.max(25,jumpVelocity*.7)
  and(not record.lastJump or now-record.lastJump>1.2)then record.jumps[#record.jumps+1]=now;record.lastJump=now end
 local teleports=recent(record.teleports,12);local jumps=recent(record.jumps,12)
 if not enabled.teleport then table.clear(record.teleports);teleports=0 end
 if not enabled.jump then table.clear(record.jumps);jumps=0 end
 self:signal(player,record,"flight",flightRate>0 and prior("flight")+flightRate*evidenceDt or math.max(0,prior("flight")-dt*1.5),thresholds.flight,enabled.flight,"sustained flight/hover-like movement",string.format("Airborne %.1fs; vertical %.0f studs/s.",airTime,relativeVelocity.Y))
 self:signal(player,record,"speed",speedRate>0 and prior("speed")+speedRate*evidenceDt or math.max(0,prior("speed")-dt*1.8),thresholds.speed,enabled.speed,"sustained movement above the observed walking allowance",string.format("Ground-relative %.0f studs/s; allowance %.0f.",measured,speedLimit))
 self:signal(player,record,"fling",flingRate>0 and prior("fling")+flingRate*evidenceDt or math.max(0,prior("fling")-dt*2),thresholds.fling,enabled.fling,"persistent high-spin physics",string.format("Rotation %.0f rad/s; movement %.0f studs/s.",angularSpeed,linearSpeed))
 self:signal(player,record,"teleport",teleports,thresholds.teleport,enabled.teleport,"repeated position discontinuities",string.format("%d large corrections in 12s.",teleports))
 self:signal(player,record,"jump",jumps,thresholds.jump,enabled.jump,"repeated upward impulses while already airborne",string.format("%d airborne lifts in 12s.",jumps))
end

function altairValues.playerAnomaly:sampleAll()
 if not self:HasEnabledChecks()then self:Clear();return end
 local now=os.clock()
 if self.lastTick and now-self.lastTick>1.25 then self:Clear()end
 self.lastTick=now
 local roster=players:GetPlayers();local count=#roster
 if count==0 then self.cursor=1;return end
 local index=math.clamp(self.cursor or 1,1,count);local deadline=os.clock()+.002
 -- One existing worker samples a bounded round-robin slice. There is no
 -- per-player task, per-frame detector or unbounded character scan.
 for _=1,math.min(count,20)do
  local player=roster[index]
  local ok=pcall(self.samplePlayer,self,player,os.clock())
  if not ok then self.users[player.UserId]=nil end
  index=index%count+1
  if os.clock()>=deadline then break end
 end
 self.cursor=index
end

-- Passive chat observations: bounded pattern metadata, never message transcripts.
do
 local maxBytes,maxCharacters,historyWindow=4096,512,18
 local function emoji(code)
  return(code>=0x1F300 and code<=0x1FAFF)or(code>=0x2600 and code<=0x27BF)or(code>=0x1F1E6 and code<=0x1F1FF)
 end
 local function patternKey(value)
  local a,b=5381,2166136261
  for index=1,#value do local byte=string.byte(value,index);a=(a*33+byte)%4294967296;b=(b*65599+byte)%4294967296 end
  return tostring(a)..":"..tostring(b)..":"..tostring(#value)
 end
 local function messageShape(value)
  if type(value)~="string"or #value==0 or #value>maxBytes then return nil end
  local chars={};local count,letters,capitals,emojis,symbols,longest,run,previous=0,0,0,0,0,0,0,nil
  local ok=pcall(function()
   for _,original in utf8.codes(value)do
    count+=1;if count>maxCharacters then return end
    local code=original
    if code>=0xFF01 and code<=0xFF5E then code-=0xFEE0 end
    local invisible=(code>=0x200B and code<=0x200F)or(code>=0x202A and code<=0x202E)or(code>=0x2060 and code<=0x206F)or code==0xFEFF
    if invisible or code<32 and code~=9 and code~=10 and code~=13 then continue end
    local space=code==9 or code==10 or code==13 or code==32 or code==0xA0 or(code>=0x2000 and code<=0x200A)or code==0x2028 or code==0x2029 or code==0x202F or code==0x205F or code==0x3000
    if space then code=32 end
    local upper=(code>=65 and code<=90)or(code>=0xC0 and code<=0xD6)or(code>=0xD8 and code<=0xDE)or(code>=0x391 and code<=0x3AB and code~=0x3A2)or(code>=0x400 and code<=0x42F)
    local lower=(code>=97 and code<=122)or(code>=0xDF and code<=0xF6)or(code>=0xF8 and code<=0xFF)or(code>=0x3B1 and code<=0x3CB)or(code>=0x430 and code<=0x45F)
    if upper or lower then letters+=1;if upper then capitals+=1 end end
    if emoji(code)then emojis+=1 end
    if(code>=33 and code<=47)or(code>=58 and code<=64)or(code>=91 and code<=96)or(code>=123 and code<=126)or(code>=0x2010 and code<=0x205E)or(code>=0x3001 and code<=0x303F)then symbols+=1 end
    if upper then code+=(code>=0x400 and code<=0x40F)and 80 or 32 end
    if code==previous and code~=32 then run+=1 else run=1;previous=code end
    longest=math.max(longest,run);chars[#chars+1]=utf8.char(code)
   end
  end)
  if not ok or count>maxCharacters then return nil end
  local cleaned=table.concat(chars):gsub(" +"," "):match("^ *(.-) *$")or""
  if cleaned==""then return nil end
  local fingerprint=cleaned:gsub("[%s%p_]","")
  if #fingerprint==0 then fingerprint=cleaned end
  local links={};local linkCount=0
  for token in cleaned:gmatch("%S+")do
   if token:match("^https?://")or token:match("^www%.")then
    linkCount+=1
    if #links<4 then links[#links+1]=token:gsub("^https?://",""):gsub("[%.%,%!%?%;%:]+$","")end
   end
  end
  table.sort(links)
  local words,totalWords,maxWord={},0,0
  for word in cleaned:gmatch("[%w']+")do if #word>=2 then totalWords+=1;words[word]=(words[word]or 0)+1;maxWord=math.max(maxWord,words[word])end end
  return {key=patternKey(cleaned),rawKey=patternKey(value),fingerprint=patternKey(fingerprint),fingerprintLength=#fingerprint,
   characters=count,letters=letters,capitals=capitals,emojis=emojis,symbols=symbols,longest=longest,
   links=linkCount,linkKey=#links>0 and patternKey(table.concat(links,"|"))or nil,words=totalWords,maxWord=maxWord}
 end
 function altairValues.chatModeration:emojiCount(value)
  local shape=messageShape(value);return shape and shape.emojis or 0
 end
 function altairValues.chatModeration:Clear(resetStats)
  -- Sender evidence and delivery deduplication never cross a toggle boundary.
  -- Aggregate run counters reset only through an explicit Clear History action.
  table.clear(self.users)
  if resetStats==true then self.observed=0;self.alertCount=0;self.lastAlertAt=nil end
 end
 function altairValues.chatModeration:Summary()
  local count,flagged=0,0;local now=os.clock()
  for _,record in pairs(self.users)do count+=1;if(record.flaggedUntil or 0)>now then flagged+=1 end end
  return {tracked=count,flagged=flagged,observed=self.observed or 0,alerts=self.alertCount or 0,lastAlertAt=self.lastAlertAt}
 end
 function altairValues.chatModeration:observe(player,message,event)
  if not checkAltair()then return false end
  if not settingValue("Chat Spam Detection",true)then
   if next(self.users)then self:Clear(false)end
   return false
  end
  if not player or type(player.UserId)~="number"or(player==localPlayer and not settingValue("Detection Self Test",false))then return false end
  local shape=messageShape(message);if not shape then return false end
  local now=os.clock();local record=self.users[player.UserId]
  if not record then record={history={},deliveries={},deliveryIds={},lastAlert=-math.huge,evidence=0,hits={},lastScore=0,flaggedUntil=0};self.users[player.UserId]=record end
  local source=type(event)=="table"and(event.source=="legacy"or event.source=="modern")and event.source or"unknown"
  local deliveryId=type(event)=="table"and type(event.id)=="string"and #event.id>0 and #event.id<=128 and event.id or nil
  for id,seen in pairs(record.deliveryIds)do if now-seen>20 then record.deliveryIds[id]=nil end end
  if deliveryId and record.deliveryIds[deliveryId]then return false end
  if deliveryId then
   local size=0;local oldest,oldestAt
   for id,seen in pairs(record.deliveryIds)do size+=1;if not oldestAt or seen<oldestAt then oldest,oldestAt=id,seen end end
   if size>=24 then record.deliveryIds[oldest]=nil end
   record.deliveryIds[deliveryId]=now
  end
  local paired=false
  for index=#record.deliveries,1,-1 do
   local item=record.deliveries[index]
   if now-item.time>.15 then table.remove(record.deliveries,index)
   elseif not paired and source~="unknown"and item.source~="unknown"and item.source~=source and not item.paired and item.key==shape.rawKey then item.paired=true;paired=true end
  end
  if paired then return false end
  record.deliveries[#record.deliveries+1]={time=now,source=source,key=shape.rawKey,paired=false}
  while #record.deliveries>12 do table.remove(record.deliveries,1)end
  self.observed=(self.observed or 0)+1
  local elapsed=record.lastMessage and now-record.lastMessage or historyWindow
  record.lastMessage=now
  record.evidence=math.max(0,record.evidence-elapsed*6)
  if elapsed>=8 then record.latched=false;table.clear(record.hits)end
  local history=record.history
  for index=#history,1,-1 do if now-history[index].time>historyWindow then table.remove(history,index)end end
  for index=#record.hits,1,-1 do if now-record.hits[index]>8 then table.remove(record.hits,index)end end
  local score,contextScore=0,0;local reasons,seenReasons={},{}
  local function add(points,reason,contextual)
   score+=points;if contextual then contextScore+=points end
   if reason and not seenReasons[reason]then seenReasons[reason]=true;reasons[#reasons+1]=reason end
  end
  if shape.letters>=12 and shape.capitals/shape.letters>=.85 then add(12,"repeated capitals")end
  if shape.longest>=14 then add(20,"character flooding")elseif shape.longest>=8 then add(12,"repeated characters")end
  if shape.characters>=18 and shape.symbols/math.max(1,shape.characters)>=.55 then add(18,"symbol flooding")end
  if shape.emojis>=8 and shape.emojis/math.max(1,shape.characters)>=.4 then add(16,"emoji flooding")end
  if shape.maxWord>=6 and shape.maxWord/math.max(1,shape.words)>=.45 then add(15,"repeated words")end
  if shape.links>=3 then add(14,"multiple links")end
  -- Long messages alone are ordinary conversation; only combine with repetition.
  score=math.min(score,32)
  local duplicates,repeatLinks,countSix,countTwo=0,0,1,1
  for _,item in ipairs(history)do
   local age=now-item.time
   if age<=6 then countSix+=1 end;if age<=2 then countTwo+=1 end
   if item.key==shape.key or(shape.fingerprintLength>=4 and item.fingerprint==shape.fingerprint)then duplicates+=1 end
   if shape.linkKey and item.linkKey==shape.linkKey then repeatLinks+=1 end
  end
  if duplicates>=3 then add(45,"repeated messages",true)elseif duplicates==2 then add(32,"repeated messages",true)elseif duplicates==1 then add(16,"duplicate messages",true)end
  if repeatLinks>=2 then add(28,"repeated links",true)elseif repeatLinks==1 then add(12,"repeated links",true)end
  if countSix>=7 then add(38,"rapid messages",true)elseif countSix>=5 then add(21,"rapid messages",true)elseif countSix>=4 then add(10,"rapid messages",true)end
  if countTwo>=4 then add(26,"message bursts",true)elseif countTwo>=3 then add(14,"message bursts",true)end
  if shape.characters<=3 and countSix>=5 then add(8,"short-message flooding",true)end
  score=math.clamp(math.floor(score+.5),0,100);record.lastScore=score
  history[#history+1]={time=now,key=shape.key,fingerprint=shape.fingerprint,linkKey=shape.linkKey}
  while #history>math.clamp(self.maxHistory or 16,8,24)do table.remove(history,1)end
  local sensitivity=math.clamp(tonumber(settingValue("Anti-Spam Sensitivity",60))or 60,1,100)
  local threshold=math.clamp(98-sensitivity*.5,45,90)
  record.evidence=math.min(100,record.evidence+score*.34)
  if contextScore>=14 and score>=threshold*.6 then
   record.hits[#record.hits+1]=now
   while #record.hits>12 do table.remove(record.hits,1)end
  end
  if record.evidence<threshold*.24 then record.latched=false end
  local sustained=#history>=3 and #record.hits>=2 and contextScore>=14 and score>=threshold*.8 and record.evidence>=threshold*.62
  if not sustained then return false end
  record.flaggedUntil=math.max(record.flaggedUntil,now+math.clamp(6+score*.1,10,16))
  local cooldown=math.clamp(tonumber(settingValue("Detection Cooldown",45))or 45,10,300)
  if record.latched or now-record.lastAlert<cooldown then return false end
  local identity=tostring(player.DisplayName).." (@"..tostring(player.Name)..")"
  local detail=identity.." is showing a sustained pattern of possible chat spam."
  if settingValue("Detection Details",true)then
   local shown={};for index=1,math.min(3,#reasons)do shown[#shown+1]=reasons[index]end
   detail..=" Evidence "..tostring(score).."/100 · "..table.concat(shown,", ").."."
  end
  if player==localPlayer then detail..=" Self-test observation."end
  local accepted=notification("Possible Chat Spam",detail,4384400106,{Key="chat-pattern-"..tostring(player.UserId),Duration=6})
  if not accepted or not checkAltair()or self.users[player.UserId]~=record then return false end
  record.lastAlert=now;record.latched=true;self.lastAlertAt=now;self.alertCount=(self.alertCount or 0)+1
  return true
 end
end

-- Theme animation and Smartbar feedback
do
	local function colorOutput(object,property,color)return altairValues.interfaceBindings.IdleColor(UI,object,property,color)end
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
		ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 35, 37)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 30, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 26, 28)),
	})
	local playerlistBaseStrokeSequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 176, 200)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(127, 144, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 176, 200)),
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

		stroke.Color = colorOutput(stroke,"Color",Color3.new(1, 1, 1))

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
			root.BackgroundColor3 = colorOutput(root,"BackgroundColor3",Color3.new(1, 1, 1))
		elseif root:IsA("ImageLabel") or root:IsA("ImageButton") then
			root.ImageColor3 = colorOutput(root,"ImageColor3",Color3.new(1, 1, 1))
		end

		local gradient = ensurePlayerlistGradient(root, "AltairPlayerlistBackgroundGradient")
		if gradient then
			gradient.Color = playerlistBaseFillSequence
		end

		local stroke = root:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness,stroke.Transparency=.6,.9
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
					row.BackgroundColor3 = colorOutput(row,"BackgroundColor3",Color3.new(1, 1, 1))
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
						statusDot.BackgroundColor3 = colorOutput(statusDot,"BackgroundColor3",dotColor)
					elseif statusDot:IsA("ImageLabel") or statusDot:IsA("ImageButton") then
						statusDot.ImageColor3 = colorOutput(statusDot,"ImageColor3",dotColor)
					end
				end
			end
		end

		local profile = interactions:FindFirstChild("SelectedPlayer")
		if profile then
			if profile:IsA("Frame") then
				profile.BackgroundColor3 = colorOutput(profile,"BackgroundColor3",Color3.new(1, 1, 1))
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
						statusDot.BackgroundColor3 = colorOutput(statusDot,"BackgroundColor3",Color3.fromRGB(49, 214, 110))
					elseif statusDot:IsA("ImageLabel") or statusDot:IsA("ImageButton") then
						statusDot.ImageColor3 = colorOutput(statusDot,"ImageColor3",Color3.fromRGB(49, 214, 110))
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
		UI:SetAttribute("AltairThemeRainbow",rainbow)

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
				object[original[1]] = colorOutput(object,original[1],rainbow and color or object:GetAttribute("AltairBaseColor") or original[2])
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


		local smartBarColor = blinkState.color or persistentColor or (rainbow and color or (bar.UIStroke:GetAttribute("AltairTheme_Color")or Color3.fromRGB(160,166,180)))
		bar.Shadow.ImageColor3 = colorOutput(bar.Shadow,"ImageColor3",smartBarColor)
		bar.CircleGradient.ImageColor3 = colorOutput(bar.CircleGradient,"ImageColor3",smartBarColor)
		bar.UIStroke.Color = colorOutput(bar.UIStroke,"Color",smartBarColor)
		bar.Back.UIStroke.Color = colorOutput(bar.Back.UIStroke,"Color",smartBarColor)
		if dragVisual and dragColor then
			if dragVisual:IsA("ImageLabel") or dragVisual:IsA("ImageButton") then
				dragVisual.ImageColor3 = colorOutput(dragVisual,"ImageColor3",blinkState.color or rainbow and color or dragColor)
			else
				dragVisual.BackgroundColor3 = colorOutput(dragVisual,"BackgroundColor3",blinkState.color or rainbow and color or dragColor)
			end
		end

		if rainbow then
			for _, toast in ipairs(activeToasts) do
				local title = toast:FindFirstChild("Title")
				if title then
					if toastColors[title] == nil then
						toastColors[title] = altairValues.interfaceBindings.IdleBase(UI,title,"TextColor3",title.TextColor3)
					end
					title.TextColor3 = colorOutput(title,"TextColor3",color)
				end
			end
		else
			for title, original in pairs(toastColors) do
				if title.Parent then
					title.TextColor3 = colorOutput(title,"TextColor3",original)
				end
			end
		end

  if altairValues.theme then altairValues.theme:Rainbow(rainbow and hue or nil)end
		enabled = rainbow or persistentColor ~= nil
	end))
end

local function BlinkSmartBar(blinkCount, color, onPulse)
	if not checkAltair() then return end
	local count = tonumber(blinkCount) or 1
	if count ~= count or count == math.huge or count == -math.huge then count = 1 end
	-- Feedback is bounded even when external callers repeatedly enqueue it.
	local accepted = #blinkState.queue < 16
	if accepted then
		table.insert(blinkState.queue, {
			count = math.clamp(math.floor(count), 1, 8),
			onPulse = onPulse,
			color = typeof(color) == "Color3" and color or nil,
		})
	end
	if blinkState.running then
		if not accepted then return false end
		return
	end
	blinkState.running = true
	task.spawn(function()
		local feedback, outline, backFeedback, backOutline, shadow, sourceShadow
		local dragFeedback, dragVisual, shadowColorProperty, shadowTransparencyProperty
		local outlineAnimation, backAnimation, shadowAnimation, dragAnimation, activeBar, activeBack
		local visualConnections = {}
		local function alive()
			return checkAltair() and activeBar and activeBar:IsDescendantOf(UI)
				and feedback and feedback.Parent == activeBar and outline and outline.Parent == feedback
				and activeBack and activeBack.Parent == activeBar
				and backFeedback and backFeedback.Parent == activeBack and backOutline and backOutline.Parent == backFeedback
				and (not sourceShadow or sourceShadow.Parent) and (not shadow or shadow.Parent)
				and (not dragVisual or dragVisual.Parent) and (not dragFeedback or dragFeedback.Parent)
		end
		local function stopAnimations()
			if outlineAnimation then outlineAnimation:Cancel(); outlineAnimation = nil end
			if backAnimation then backAnimation:Cancel(); backAnimation = nil end
			if shadowAnimation then shadowAnimation:Cancel(); shadowAnimation = nil end
			if dragAnimation then dragAnimation:Cancel(); dragAnimation = nil end
		end
		local function animate(duration, outlineGoal, backGoal, shadowGoal, dragGoal)
			stopAnimations()
			local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			outlineAnimation = tweenService:Create(outline, info, outlineGoal)
			outlineAnimation:Play()
			backAnimation = tweenService:Create(backOutline, info, backGoal)
			backAnimation:Play()
			if shadow and shadowGoal then
				shadowAnimation = tweenService:Create(shadow, info, shadowGoal)
				shadowAnimation:Play()
			end
			if dragFeedback and dragGoal then
				dragAnimation = tweenService:Create(dragFeedback, info, dragGoal)
				dragAnimation:Play()
			end
		end
		local ok, err = pcall(function()
			local bar = UI:FindFirstChild("SmartBar")
			local back = bar and bar:FindFirstChild("Back")
			if not checkAltair() or not bar or not back then return end
			for _, object in ipairs(UI:GetChildren()) do
				if object:IsA("ImageLabel") and object.Name == "SoftShadow"
					and object:GetAttribute("AltairShadowFor") == "SmartBar" then
					sourceShadow = object
					break
				end
			end
			if not sourceShadow then
				local nativeShadow = bar:FindFirstChild("SoftShadow")
				if nativeShadow and nativeShadow:IsA("UIShadow") then sourceShadow = nativeShadow end
			end
			activeBar = bar
			activeBack = back
			feedback = Instance.new("Frame")
			feedback.Name = "SmartBarFeedback"
			feedback.BackgroundTransparency = 1
			feedback.BorderSizePixel = 0
			feedback.Size = UDim2.fromScale(1, 1)
			feedback.Active = false
			feedback.Interactable = false
			feedback.ZIndex = bar.ZIndex + 5
			feedback:SetAttribute("AltairThemeIgnore", true)
			local corner = bar:FindFirstChildOfClass("UICorner")
			if corner then corner:Clone().Parent = feedback end
			outline = Instance.new("UIStroke")
			outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			outline.Thickness = 1
			outline.Transparency = 1
			outline.Parent = feedback
			feedback.Parent = bar
			backFeedback = Instance.new("Frame")
			backFeedback.Name = "SmartBarBackFeedback"
			backFeedback.BackgroundTransparency = 1
			backFeedback.BorderSizePixel = 0
			backFeedback.Size = UDim2.fromScale(1, 1)
			backFeedback.Active = false
			backFeedback.Interactable = false
			backFeedback.ZIndex = back.ZIndex + 5
			backFeedback:SetAttribute("AltairThemeIgnore", true)
			local backCorner = back:FindFirstChildOfClass("UICorner")
			if backCorner then backCorner:Clone().Parent = backFeedback end
			local baseBackOutline = back:FindFirstChildOfClass("UIStroke")
			local backRestThickness = baseBackOutline and baseBackOutline.Thickness or .45
			backOutline = Instance.new("UIStroke")
			backOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			backOutline.Thickness = backRestThickness
			backOutline.Transparency = 1
			backOutline.Parent = backFeedback
			backFeedback.Parent = back
			local drag = UI:FindFirstChild("Drag")
			dragVisual = drag and drag:FindFirstChild("Drag")
			if dragVisual and dragVisual:IsA("GuiObject") then
				dragFeedback = Instance.new("Frame")
				dragFeedback.Name = "SmartBarFeedbackDrag"
				dragFeedback.BackgroundTransparency = 1
				dragFeedback.BorderSizePixel = 0
				dragFeedback.Active = false
				dragFeedback.Interactable = false
				dragFeedback:SetAttribute("AltairThemeIgnore", true)
				local dragCorner = dragVisual:FindFirstChildOfClass("UICorner")
				if dragCorner then dragCorner:Clone().Parent = dragFeedback end
				for _, property in ipairs({"Position", "Size", "AnchorPoint", "Rotation", "ZIndex", "Visible"}) do
					local key = property
					dragFeedback[key] = dragVisual[key]
					visualConnections[#visualConnections + 1] = dragVisual:GetPropertyChangedSignal(key):Connect(function()
						if dragFeedback and dragFeedback.Parent and dragVisual.Parent then dragFeedback[key] = dragVisual[key] end
					end)
				end
				dragFeedback.ZIndex = dragVisual.ZIndex + 5
				dragFeedback.Parent = dragVisual.Parent
			end
			if sourceShadow then
				-- Clone the active renderer under its existing parent. Blink owns only
				-- this clone's tint/alpha; the base renderer remains theme-owned.
				shadow = sourceShadow:Clone()
				shadow.Name = "SmartBarFeedbackShadow"
				shadow:SetAttribute("AltairThemeIgnore", true)
				if shadow:IsA("ImageLabel") then
					shadowColorProperty = "ImageColor3"
					shadowTransparencyProperty = "ImageTransparency"
					shadow.ImageTransparency = 1
					shadow.Active = false
					shadow.Interactable = false
					local function syncRenderedShadowVisibility()
						if shadow and sourceShadow.Parent then
							shadow.Visible = sourceShadow.Visible and bar.Visible and bar:GetAttribute("AltairClosing") ~= true
						end
					end
					for _, property in ipairs({"Position", "Size", "Rotation", "SliceScale", "ZIndex"}) do
						local key = property
						visualConnections[#visualConnections + 1] = sourceShadow:GetPropertyChangedSignal(key):Connect(function()
							if shadow and shadow.Parent and sourceShadow.Parent then shadow[key] = sourceShadow[key] end
						end)
					end
					syncRenderedShadowVisibility()
					for _, signal in ipairs({
						sourceShadow:GetPropertyChangedSignal("Visible"),
						bar:GetPropertyChangedSignal("Visible"),
						bar:GetAttributeChangedSignal("AltairClosing"),
					}) do
						visualConnections[#visualConnections + 1] = signal:Connect(syncRenderedShadowVisibility)
					end
				else
					shadowColorProperty = "Color"
					shadowTransparencyProperty = "Transparency"
					shadow.Transparency = 1
				end
				shadow.Parent = sourceShadow.Parent
			end
			while checkAltair() and #blinkState.queue > 0 do
				local request = table.remove(blinkState.queue, 1)
				for _ = 1, request.count do
					if not alive() then return end
					if type(request.onPulse) == "function" then pcall(request.onPulse) end
					if not alive() then return end
					local reduced = UI:GetAttribute("AltairReduceMotion") == true
					pcall(function() reduced = reduced or guiService.ReducedMotionEnabled == true end)
					-- Reduced motion still delivers the callback, without a flash.
					if reduced then
						-- Callbacks can enqueue more work; always yield under this
						-- profile too, rather than consuming a reentrant queue inline.
						task.wait()
					else
						local stroke = bar:FindFirstChildOfClass("UIStroke")
						local raw = request.color or blinkState.persistentColor
							or (settingValue("Rainbow Mode", false) and Color3.fromHSV((os.clock() / 8) % 1, .65, .8))
							or (stroke and altairValues.interfaceBindings.IdleBase(UI, stroke, "Color", stroke.Color))
							or Color3.fromRGB(160, 166, 180)
						local pulseColor = altairValues.interfaceBindings.IdleColor(UI, outline, "Color", raw)
						outline.Color = pulseColor
						backOutline.Color = pulseColor
						if dragFeedback then dragFeedback.BackgroundColor3 = pulseColor end
						local shadowPeak, shadowRest
						if shadow then
							shadow[shadowColorProperty] = pulseColor
							shadowPeak = {[shadowTransparencyProperty] = .90}
							shadowRest = {[shadowTransparencyProperty] = 1}
						end
						animate(.155,
							{Transparency = .90, Thickness = 1.35},
							{Transparency = .90, Thickness = backRestThickness + .45},
							shadowPeak,
							dragFeedback and {BackgroundTransparency = .90} or nil)
						task.wait(.155)
						if not alive() then return end
						animate(.375,
							{Transparency = 1, Thickness = 1},
							{Transparency = 1, Thickness = backRestThickness},
							shadowRest,
							dragFeedback and {BackgroundTransparency = 1} or nil)
						task.wait(.375)
					end
				end
			end
		end)
		-- Release the queue before native cancellation/destruction signals: any
		-- reentrant request can start its own worker instead of being stranded.
		blinkState.running = false
		-- One failed native cleanup must not permanently lock the request queue.
		pcall(stopAnimations)
		for _, connection in ipairs(visualConnections) do connection:Disconnect() end
		if shadow then pcall(function() shadow:Destroy() end) end
		if dragFeedback then pcall(function() dragFeedback:Destroy() end) end
		if backFeedback then pcall(function() backFeedback:Destroy() end) end
		if feedback then pcall(function() feedback:Destroy() end) end
		if not checkAltair() then table.clear(blinkState.queue) end
		-- No global Theme:Apply or base material/alpha restoration: this pulse
		-- never changed those properties, so unrelated panels cannot flash.
		if not ok then warn("Altair | SmartBar feedback failed: " .. tostring(err)) end
	end)
	if not accepted then return false end
end

local function Toast(content, color, font, skipBlink)
	if not checkAltair() then return end
	content = tostring(content or "")
	local length = utf8.len(content) or #content
	local lifetime = math.clamp(4 + length / 22, 7, 16)
	local reducedMotion = UI:GetAttribute("AltairReduceMotion")==true
	pcall(function() reducedMotion = reducedMotion or guiService.ReducedMotionEnabled==true end)
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

-- Keep executor-facing names ASCII: some Windows executors cannot enumerate
-- a directory containing Unicode filenames. Display titles remain unchanged.
altairValues.customScriptFileStem = function(title)
	local stem = tostring(title or ""):gsub("[^%w %-%_%.%(%)]+", "")
		:gsub("^%s+", ""):gsub("[%s%.]+$", "")
	if stem == "" then stem = "Custom Script" end
	local base = (stem:match("^([^%.]+)") or stem):upper()
	if base == "CON" or base == "PRN" or base == "AUX" or base == "NUL"
		or base:match("^COM[1-9]$") or base:match("^LPT[1-9]$") then
		stem = "Custom " .. stem
	end
	return stem
end

altairValues.scanCustomScripts = function()
	if not checkAltair()then return nil,"Altair is unloaded"end
	altairValues.customScripts = {}
	altairValues.detectedScript = nil

	if not (isfolder and listfiles and readfile) then
		return nil, "filesystem unavailable"
	end

	local folder = altairValues.altairFolder .. "/" .. altairValues.customScriptsFolder
	local folderExists=isfolder(folder)
	if not checkAltair()then return nil,"Altair is unloaded"end
	if not folderExists then
		if not makefolder then
			return nil, "custom scripts folder unavailable"
		end
		local ok = pcall(makefolder, folder)
		if not checkAltair()then return nil,"Altair is unloaded"end
		if not ok then
			return nil, "could not create custom scripts folder"
		end
	end

	local ok, files = pcall(listfiles, folder)
	if not checkAltair()then return nil,"Altair is unloaded"end
	if not ok or type(files) ~= "table" then
		local detail = "Could not list Altair/Custom Scripts. Rename any emoji or non-ASCII filenames in that folder, then use Reprompt."
		warn("Altair | " .. detail .. " " .. tostring(files))
		notification("Custom scripts unavailable", detail, nil, {Key="custom-script-scan", Duration=10})
		return nil, "could not list custom scripts: " .. tostring(files)
	end

	table.sort(files)

	for _, file in ipairs(files) do
		if not checkAltair()then return nil,"Altair is unloaded"end
		local lower = string.lower(tostring(file))
		if lower:sub(-5) == ".json" or lower:sub(-7) == ".altair" then
			local readOk, raw = pcall(readfile, file)
			if not checkAltair()then return nil,"Altair is unloaded"end

			if readOk and type(raw) == "string" and raw ~= "" then
				local decodeOk, data = pcall(httpService.JSONDecode, httpService, raw)
				if not checkAltair()then return nil,"Altair is unloaded"end

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
								if not checkAltair()then return nil,"Altair is unloaded"end
								if infoOk and info and type(info.Name) == "string" and info.Name ~= "" then
									readableName = info.Name
								end
							end
						end

						readableName = altairValues.customScriptFileStem(readableName)

						local target = folder .. "/" .. readableName .. extension
						local targetExists=isfile and isfile(target)
						if not checkAltair()then return nil,"Altair is unloaded"end
						if targetExists then
							local base = folder .. "/" .. readableName
							local suffix = 2
							while true do
								if not checkAltair()then return nil,"Altair is unloaded"end
								local exists=isfile(base .. " (" .. tostring(suffix) .. ")" .. extension)
								if not checkAltair()then return nil,"Altair is unloaded"end
								if not exists then break end
								suffix += 1
							end
							target = base .. " (" .. tostring(suffix) .. ")" .. extension
						end

						local writeOk = pcall(writefile, target, raw)
						if not checkAltair()then return nil,"Altair is unloaded"end
						if writeOk then
							pcall(delfile, file)
							if not checkAltair()then return nil,"Altair is unloaded"end
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
 altairValues.promptArtworkGeneration=(altairValues.promptArtworkGeneration or 0)+1
 altairValues.detectionLoadVersion=(altairValues.detectionLoadVersion or 0)+1
 altairValues.detectionPromptOpen=false
 altairValues.dialogMotion:Close(gameDetectionPrompt)
end

env.AltairScriptRuns=type(env.AltairScriptRuns)=="table" and env.AltairScriptRuns or {}
function altairValues.scriptRunKey(info)
	return tostring(game.GameId)..":"..tostring(game.PlaceId)..":"..game.JobId..":"..tostring(info.Loadstring or info.LuaFile or info.ScriptFile or info.DefinitionFile or info.ScriptTitle or info.Source)
end
function altairValues.knownScriptHandle(info)
	local title=tostring(info.ScriptTitle or ""):lower()
	return title:find("arsenal",1,true) and env.__ARSENAL_RAY_WINDOW
		or title:find("last stand",1,true) and env.LastStand
		or (title:find("tower defense",1,true) or title=="tds") and env.ADS_RayfieldWindow
end
function altairValues.markScriptRunning(info)
	local handle=altairValues.knownScriptHandle(info)
	env.AltairScriptRuns[altairValues.scriptRunKey(info)]=handle and setmetatable({handle=handle},{__mode="v"}) or true
end
function altairValues.scriptAlreadyRunning(info)
	local status=env.AltairScriptRuns[altairValues.scriptRunKey(info)]
	if type(status)=="table" and status.state=="loading" then return type(status.owner)=="table" and status.owner.alive==true end
	local live=altairValues.knownScriptHandle(info) or (type(status)=="table" and status.handle)
	if type(live)=="table" then return live.unloaded~=true and live.alive~=false and not (live.window and live.window.unloaded) end
	return status==true or status=="loading"
end
altairValues.showGameDetection = function(scriptInfo)
	if type(scriptInfo) ~= "table" then return false end
	if altairValues.scriptAlreadyRunning(scriptInfo) then
		altairValues.closeGameDetection()
		local status=env.AltairScriptRuns[altairValues.scriptRunKey(scriptInfo)]
		local loading=status=="loading" or (type(status)=="table" and status.state=="loading")
		notification(loading and "Script is starting" or "Script already running",tostring(scriptInfo.ScriptTitle or "Game script")..(loading and " is already starting. Its launch prompt was skipped." or " was already run. Its launch prompt was skipped."),nil,{Key="script-already-running",Duration=5})
		return false
	end

	local layer = gameDetectionPrompt:FindFirstChild("Layer")
	if not layer then
		warn("Altair | GameDetection.Layer is missing from the interface.")
		return false
	end

	local subtitle = layer:FindFirstChild("ScriptSubtitle")
	local thumbnail = gameDetectionPrompt:FindFirstChild("Thumbnail",true)
	local warning = gameDetectionPrompt:FindFirstChild("Warning")

 altairValues.detectionLoadVersion=(altairValues.detectionLoadVersion or 0)+1
 local loadVersion=altairValues.detectionLoadVersion
	local currentPlaceId=game.PlaceId
	local ok,info=pcall(marketplaceService.GetProductInfo,marketplaceService,currentPlaceId)
 if not checkAltair()or loadVersion~=altairValues.detectionLoadVersion then return false end
	local gameTitle = ok and info and info.Name or ("Place " .. tostring(currentPlaceId))

	placeName = gameTitle
	gameDetectionPrompt.ScriptTitle.Text = gameTitle

	if subtitle then subtitle.Text = tostring(scriptInfo.ScriptSubtitle or "") end
	if warning then warning.Visible = false end

	if thumbnail and thumbnail:IsA("ImageLabel") then
		thumbnail.Image = "rbxthumb://type=GameThumbnail&id=" .. tostring(game.PlaceId) .. "&w=768&h=432"
	end

 altairValues.detectionPromptOpen=true
 altairValues.dialogMotion:Open(gameDetectionPrompt)

	altairValues.promptArtworkGeneration=(altairValues.promptArtworkGeneration or 0)+1
	local generation=altairValues.promptArtworkGeneration
	local nextImage=gameDetectionPrompt:FindFirstChild("NextThumbnail",true)
	if thumbnail and nextImage then
		nextImage.ImageTransparency=1;nextImage.Position=UDim2.fromScale(1,0);thumbnail.Position=UDim2.fromScale(0,0)
		task.spawn(function()
			local function active() return checkAltair() and altairValues.detectionPromptOpen and generation==altairValues.promptArtworkGeneration end
			local images={thumbnail.Image}
			local success,response=pcall(function() return httpRequest({Url="https://games.roblox.com/v2/games/"..game.GameId.."/media",Method="GET",Timeout=8}) end)
			if success and response and tonumber(response.StatusCode)==200 then
				local decoded,data=pcall(httpService.JSONDecode,httpService,response.Body)
				if decoded and type(data)=="table" then
					local seen={}
					for _,media in ipairs(data.data or {}) do
						if media.assetType=="Image" and media.approved~=false and tonumber(media.imageId) and not seen[media.imageId] then seen[media.imageId]=true;images[#images+1]="rbxassetid://"..media.imageId end
						if #images>=9 then break end
					end
				end
			end
			if #images<2 or not active() then return end
			local index=1
			while active() do
				task.wait(5)
				if not active() then break end
				index=index%#images+1;nextImage.Image=images[index]
				local loaded=true
				local preloaded=pcall(function() game:GetService("ContentProvider"):PreloadAsync({images[index]},function(_,status) if status~=Enum.AssetFetchStatus.Success then loaded=false end end) end)
				if not active() then break end
				if preloaded and loaded then
					nextImage.Position=UDim2.fromScale(1,0);nextImage.ImageTransparency=.15
					local reduced=UI:GetAttribute("AltairReduceMotion")==true
					if reduced then nextImage.Position=UDim2.fromScale(0,0) end
					tweenService:Create(nextImage,TweenInfo.new(.38,Enum.EasingStyle.Quint),{ImageTransparency=0,Position=UDim2.fromScale(0,0)}):Play()
					if not reduced then tweenService:Create(thumbnail,TweenInfo.new(.38,Enum.EasingStyle.Quint),{Position=UDim2.fromScale(-.18,0)}):Play() end
					task.wait(.4)
					if not active() then break end
					thumbnail.Image=nextImage.Image;thumbnail.Position=UDim2.fromScale(0,0);nextImage.ImageTransparency=1;nextImage.Position=UDim2.fromScale(1,0)
				end
			end
		end)
	end
	return true
end

altairValues.runDetectedScript = function()
	if not checkAltair() then return false end
	local scriptInfo = altairValues.detectedScript
	if type(scriptInfo) ~= "table" then
		Toast("No custom script was detected for this experience.")
		return false
	end
	scriptInfo=table.clone(scriptInfo)
	if altairValues.scriptAlreadyRunning(scriptInfo) then altairValues.showGameDetection(scriptInfo);return false end

	-- Reserve before metadata, disk, or HTTP work can yield. Each launch owns
	-- its own token, so a late completion cannot clear or mark a newer launch.
	local runKey=altairValues.scriptRunKey(scriptInfo)
	local token={state="loading",owner=altairValues.lifecycle}
	local launches=altairValues.lifecycle.scriptLaunches
	if not launches then launches={};altairValues.lifecycle.scriptLaunches=launches end
	launches[runKey]=token
	env.AltairScriptRuns[runKey]=token
	local function ownsLaunch()
		return checkAltair() and env.AltairScriptRuns[runKey]==token
	end
	local function releaseLaunch()
		if env.AltairScriptRuns[runKey]==token then env.AltairScriptRuns[runKey]=nil end
		if launches[runKey]==token then launches[runKey]=nil end
	end
	task.spawn(function()
		local currentGameName
		local function launch()
		if not ownsLaunch() then return end
		altairValues.closeGameDetection()
		local infoOk, info = pcall(marketplaceService.GetProductInfo,marketplaceService,game.PlaceId)
		if not ownsLaunch() then return end
		currentGameName = infoOk and info and info.Name or "this experience"
		Toast("Loading in " .. tostring(currentGameName) .. "...")
		if not ownsLaunch() then return end
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
				local source = game:HttpGet(url)
				if not ownsLaunch() then return end
				local chunk = assert(loadstring(source))
				if not ownsLaunch() then return end
				altairValues.activity:record("Script started", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Custom script")
				if not ownsLaunch() then return end
				local result=chunk()
				if result~=false and ownsLaunch() then altairValues.markScriptRunning(scriptInfo) end
			end)

			if not ok and ownsLaunch() then
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
					if not ownsLaunch() then return end
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

			local exists=isfile and isfile(path)
			if not ownsLaunch() then return end
			if not exists then
				Toast(
					"Custom script file not found: " .. tostring(scriptFile),
					Color3.fromRGB(255, 90, 90)
				)
				return
			end

			local ok, result = pcall(readfile, path)
			if not ownsLaunch() then return end
			if ok and type(result) == "string" and result ~= "" then
				source = result
			else
				Toast("Couldn't read the custom script file.", Color3.fromRGB(255, 90, 90))
				return
			end
		end

		if not ownsLaunch() then return end
		if type(source) ~= "string" or source == "" then
			Toast("This custom script has no runnable source.", Color3.fromRGB(255, 90, 90))
			return
		end

		if not loadstring then
			Toast("This executor doesn't support loadstring.", Color3.fromRGB(255, 90, 90))
			return
		end

		local compileOk, chunk = pcall(loadstring, source)
		if not ownsLaunch() then return end
		if not compileOk or type(chunk) ~= "function" then
			altairValues.activity:record("Script failed", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Compile error")
			Toast("The custom script couldn't be compiled.", Color3.fromRGB(255, 90, 90))
			return
		end

		altairValues.activity:record("Script started", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Custom script")
		if not ownsLaunch() then return end
		local runOk, runError = pcall(chunk)
		if runOk and runError~=false and ownsLaunch() then altairValues.markScriptRunning(scriptInfo) end
		if not runOk and ownsLaunch() then
			altairValues.activity:record("Script failed", tostring(scriptInfo.ScriptTitle or currentGameName) .. " · Runtime error")
			warn("Altair | Custom script failed: " .. tostring(runError))
			Toast("The custom script returned an error.", Color3.fromRGB(255, 90, 90))
		end
		end
		local launched,problem=pcall(launch)
		local reportProblem=ownsLaunch()
		releaseLaunch()
		if not launched and reportProblem then warn("Altair | Custom script launch failed: "..tostring(problem));notification("Script failed","The script could not start. You can try it again.",nil) end
	end)

	return true
end

altairValues.closeCustomScriptPrompt = function()
	if not checkAltair()then return false end
 altairValues.customScriptPromptOpen=false
 altairValues.dialogMotion:Close(customScriptPrompt)
end

altairValues.openCustomScriptPrompt = function()
 if not checkAltair()then return false,"Altair is unloaded"end
 local idBox=customScriptPrompt:FindFirstChild("IDTextBox",true)
 local descBox=customScriptPrompt:FindFirstChild("DescTextBox",true)
 local scriptBox=customScriptPrompt:FindFirstChild("ScriptTextBox",true)
 if not(idBox and descBox and scriptBox)then
  Toast("Custom Scripts UI is missing one or more text boxes.",Color3.fromRGB(255,90,90))
  return false
 end
 if not customScriptPrompt.Visible then
  idBox.Text=tostring(placeId);descBox.Text="";scriptBox.Text=""
 end
 altairValues.customScriptPromptOpen=true
 altairValues.dialogMotion:Open(customScriptPrompt)
 if not checkAltair()then return false,"Altair is unloaded"end
 return true
end

altairValues.saveCustomScriptPrompt = function()
	if not checkAltair()then return false,"Altair is unloaded"end
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
		if not checkAltair()then return false,"Altair is unloaded"end
		targetGameName = infoOk and info and info.Name or "this experience"
	end

	altairValues.scanCustomScripts()
	if not checkAltair()then return false,"Altair is unloaded"end

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
		if not checkAltair()then return false,"Altair is unloaded"end
		local decodeOk, definition = false, nil

		if readOk and type(raw) == "string" and raw ~= "" then
			decodeOk, definition = pcall(httpService.JSONDecode, httpService, raw)
			if not checkAltair()then return false,"Altair is unloaded"end
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
		if not checkAltair()then return false,"Altair is unloaded"end
		if not encodedOk then
			Toast("Couldn't rebuild the existing custom script.", Color3.fromRGB(255, 90, 90))
			return false
		end

		local writeOk, writeError = pcall(writefile, existing.DefinitionFile, encoded)
		if not checkAltair()then return false,"Altair is unloaded"end
		if not writeOk then
			warn("Altair | Couldn't update custom script: " .. tostring(writeError))
			Toast("Couldn't update the existing custom script.", Color3.fromRGB(255, 90, 90))
			return false
		end

		altairValues.scanCustomScripts()
		if not checkAltair()then return false,"Altair is unloaded"end
		altairValues.closeCustomScriptPrompt()
		if not checkAltair()then return false,"Altair is unloaded"end

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
	local folderExists=isfolder(folder)
	if not checkAltair()then return false,"Altair is unloaded"end
	if not folderExists then
		local ok = pcall(makefolder, folder)
		if not checkAltair()then return false,"Altair is unloaded"end
		if not ok then
			Toast("Couldn't create the Custom Scripts folder.", Color3.fromRGB(255, 90, 90))
			return false
		end
	end

	local encodedOk, encoded = pcall(httpService.JSONEncode, httpService, definition)
	if not checkAltair()then return false,"Altair is unloaded"end
	if not encodedOk then
		Toast("Couldn't build the custom script definition.", Color3.fromRGB(255, 90, 90))
		return false
	end

	local safeTitle = altairValues.customScriptFileStem(title)

	local filePath = folder .. "/" .. safeTitle .. ".altair"

	local pathExists=isfile and isfile(filePath)
	if not checkAltair()then return false,"Altair is unloaded"end
	if pathExists then
		local base = folder .. "/" .. safeTitle
		local suffix = 2
		while true do
			if not checkAltair()then return false,"Altair is unloaded"end
			local exists=isfile(base .. " (" .. tostring(suffix) .. ").altair")
			if not checkAltair()then return false,"Altair is unloaded"end
			if not exists then break end
			suffix += 1
		end
		filePath = base .. " (" .. tostring(suffix) .. ").altair"
	end

	local writeOk, writeError = pcall(writefile, filePath, encoded)
	if not checkAltair()then return false,"Altair is unloaded"end

	if not writeOk then
		warn("Altair | Couldn't save custom script: " .. tostring(writeError))
		Toast("Couldn't save the custom script.", Color3.fromRGB(255, 90, 90))
		return false
	end

	altairValues.scanCustomScripts()
	if not checkAltair()then return false,"Altair is unloaded"end
	altairValues.closeCustomScriptPrompt()
	if not checkAltair()then return false,"Altair is unloaded"end
	Toast("Imported custom script for " .. tostring(title) .. ".", Color3.fromRGB(80, 220, 145))
	return true
end

local function checkLastVersion()
	checkFolder()

	local lastVersion = isfile and isfile(altairValues.altairFolder .. "/" .. "version.altair") and readfile(altairValues.altairFolder .. "/" .. "version.altair") or nil

	if lastVersion then
		if lastVersion ~= altairValues.altairVersion then
			notification("Altair has been updated", "Altair has been updated to version " .. altairValues.altairVersion .. ", check our Discord for all new features and changes.", 4400701828)
		end
	end

	if writefile then
		writefile(altairValues.altairFolder .. "/" .. "version.altair", altairValues.altairVersion)
	end
end

-- Unfocused audio owns its sweep/watchers independently from Spatial Shield.
local removeReverbs, createReverb
do
local muffleAudio = { active = false, focused = true, generation = 0, tweens = {}, applied = {} }
altairValues.muffleAudio = muffleAudio
local function cancelMuffleTween(reverb)
	local tween = muffleAudio.tweens[reverb]
	muffleAudio.tweens[reverb] = nil
	if tween then tween:Cancel() end
end
local function destroyMuffleEffect(sound, reverb)
	if altairValues.lifecycle.audio[sound] == reverb then altairValues.lifecycle.audio[sound] = nil end
	cancelMuffleTween(reverb)
	muffleAudio.applied[reverb] = nil
	reverb:Destroy()
end
removeReverbs = function(timing)
	timing = timing or 0.65
	muffleAudio.active = false
	muffleAudio.generation += 1
	local generation = muffleAudio.generation
	for _, key in ipairs({ "added", "removing" }) do
		if muffleAudio[key] then muffleAudio[key]:Disconnect(); muffleAudio[key] = nil end
	end
	for sound, reverb in pairs(altairValues.lifecycle.audio) do
		cancelMuffleTween(reverb)
		if not altairValues.lifecycle.alive or timing <= 0 or not reverb.Parent then
			destroyMuffleEffect(sound, reverb)
		else
			local tween = tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), { HighGain = 0, LowGain = 0, MidGain = 0 })
			muffleAudio.tweens[reverb] = tween
			tween:Play()
			-- Keep ownership during fade-out so a focus reversal reuses this effect.
			task.delay(timing + 0.03, function()
				if generation == muffleAudio.generation and not muffleAudio.active
					and altairValues.lifecycle.audio[sound] == reverb then
					destroyMuffleEffect(sound, reverb)
				end
			end)
		end
	end
end
local function applyMuffle(sound, timing, generation)
	if not muffleAudio.active or muffleAudio.focused or generation ~= muffleAudio.generation
		or not checkAltair() or not settingValue("Muffle audio while unfocused")
		or not sound:IsA("Sound") or not sound:IsDescendantOf(game) then return end
	local reverb = altairValues.lifecycle.audio[sound]
	if reverb and reverb.Parent ~= sound then destroyMuffleEffect(sound, reverb); reverb = nil end
	if not reverb then
		reverb = altairValues.lifecycle:own(Instance.new("EqualizerSoundEffect"))
		altairValues.lifecycle.audio[sound] = reverb
		reverb.Destroying:Once(function()
			if altairValues.lifecycle.audio[sound] == reverb then altairValues.lifecycle.audio[sound] = nil end
			cancelMuffleTween(reverb)
			muffleAudio.applied[reverb] = nil
		end)
		reverb.HighGain, reverb.LowGain, reverb.MidGain = 0, 0, 0
		reverb.Parent = sound
	end
	if muffleAudio.applied[reverb] == generation then return end
	muffleAudio.applied[reverb] = generation
	cancelMuffleTween(reverb)
	local target = { HighGain = -20, LowGain = 5, MidGain = -20 }
	if timing and timing > 0 then
		local tween = tweenService:Create(reverb, TweenInfo.new(timing, Enum.EasingStyle.Exponential), target)
		muffleAudio.tweens[reverb] = tween
		tween:Play()
	else
		for key, value in pairs(target) do reverb[key] = value end
	end
end
createReverb = function(timing)
	if not checkAltair() or muffleAudio.focused or not settingValue("Muffle audio while unfocused") then return end
	muffleAudio.active = true
	muffleAudio.generation += 1
	muffleAudio.timing = timing
	local generation = muffleAudio.generation
	if not muffleAudio.added then
		muffleAudio.added = game.DescendantAdded:Connect(function(sound)
			applyMuffle(sound, muffleAudio.timing, muffleAudio.generation)
		end)
		muffleAudio.removing = game.DescendantRemoving:Connect(function(sound)
			local reverb = altairValues.lifecycle.audio[sound]
			if reverb then destroyMuffleEffect(sound, reverb) end
		end)
	end
	for sound, reverb in pairs(altairValues.lifecycle.audio) do
		if sound:IsDescendantOf(game) then applyMuffle(sound, timing, generation)
		else destroyMuffleEffect(sound, reverb) end
	end
	task.spawn(function()
		local descendants = game:GetDescendants()
		for index, sound in ipairs(descendants) do
			if not muffleAudio.active or generation ~= muffleAudio.generation or not checkAltair() then break end
			applyMuffle(sound, timing, generation)
			if index % 400 == 0 then task.wait() end
		end
	end)
end
do
	local setting = checkSetting("Muffle audio while unfocused")
	local previousChanged = setting and setting.onChanged
	local handler = function(...)
		if not checkAltair() then return end
		if not muffleAudio.focused and settingValue("Muffle audio while unfocused") then createReverb(0.2)
		else removeReverbs(0.2) end
		if type(previousChanged) == "function" then previousChanged(...) end
	end
	if setting then setting.onChanged = handler end
	altairValues.lifecycle.muffleCleanup = function()
		removeReverbs(0)
		if setting and setting.onChanged == handler then setting.onChanged = previousChanged end
	end
end
end

altairValues.currentCreator = creatorType == Enum.CreatorType.Group and "group" or creatorId
altairValues.currentGroup = creatorType == Enum.CreatorType.Group and creatorId or nil

-- Property models retain their existing names; CharacterRuler owns the visuals.
local function updateSlider(model, value, applyCallback)
 local ruler=altairValues.characterRuler
 if not ruler or type(value)~="number"or value~=value or math.abs(value)==math.huge then return end
 value=math.clamp(math.round(value*10)/10,model.values[1],model.values[2])
 model.value=value
 ruler:Set(model,value,true)
 if model.callback and applyCallback then model.callback(value)end
end

local function resetSliders()
	for _, v in pairs(altairValues.sliders) do
		updateSlider(v, v.default, true)
	end
end

-- Character actions and the shared property ruler
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
	characterPanel.Interactions.Reset.Position = UDim2.fromOffset(274, 89)
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
			if action.control=="Daylight"then action.callback();return end
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
				notification("Action Error", "This action ('" .. action.name .. "') had an error while running, please report this to the Altair team", 4370336704)
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
		altairValues.sliders[2].values = { 0, 200 }
	end

 if altairValues.characterRuler then altairValues.characterRuler:Destroy();altairValues.characterRuler=nil end
 for _,model in ipairs(altairValues.sliders)do model.active=false;model.value=model.default end
 altairValues.characterRuler=altairValues.interfaceBindings.CharacterRuler(UI,altairValues.sliders,function(model,value)
  local ok,problem=pcall(updateSlider,model,value,true)
  if not ok then notification("Property Error","Unable to update "..model.name..".",4370336704);warn(problem)end
 end,function()return checkAltair()and characterPanel.Visible and not characterPanel:GetAttribute("AltairClosing")and not debounce end,function(size)
  characterPanelSize=size
  if characterPanel.Visible and not characterPanel:GetAttribute("AltairClosing")and altairValues.smartBarLayout then
   game:GetService("TweenService"):Create(characterPanel,TweenInfo.new(.24,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=altairValues.smartBarLayout:getPanelPosition(characterPanel,size)}):Play()
  end
 end)
 altairValues.characterRuler:AttachDaylight({GetValue=function()return lighting.ClockTime end,OnChanged=function(value)altairValues.actions[8].callback(value)end,OnReset=function()
  local value=altairValues.actions[8].reset();Toast("Time of day reset",Color3.fromRGB(238,183,86));return value
 end})
 if not altairValues.daylightClockConnection then
  altairValues.daylightClockConnection=track(lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
   local value=lighting.ClockTime
   if daylightClock.owned and math.abs(((value-daylightClock.owned+12)%24)-12)<.001 then return end
   daylightClock.baseline=value;daylightClock.owned=nil
   local ruler=altairValues.characterRuler
   if ruler and ruler.Daylight and ruler.DaylightMode and not ruler.Daylight:IsDragging()then ruler.Daylight:Set(value,true)end
  end))
 end
 characterPanelSize=characterPanel.Size
 local function bindJump(humanoid)
  if altairValues.jumpModeConnection then altairValues.jumpModeConnection:Disconnect()end
  local function refreshJump()
   if not checkAltair()or not humanoid.Parent then return end
   local model=altairValues.sliders[2];local power=humanoid.UseJumpPower
   model.name=power and "jump power"or"jump height";model.default=power and 50 or 7.2;model.values={0,power and 500 or 200}
   model.value=math.clamp(power and humanoid.JumpPower or humanoid.JumpHeight,model.values[1],model.values[2])
   if altairValues.characterRuler then altairValues.characterRuler:Cancel();altairValues.characterRuler:Refresh(false)end
  end
  refreshJump();altairValues.jumpModeConnection=track(humanoid:GetPropertyChangedSignal("UseJumpPower"):Connect(refreshJump))
 end
 if startingHumanoid then bindJump(startingHumanoid)end
 if not altairValues.jumpCharacterConnection then altairValues.jumpCharacterConnection=track(localPlayer.CharacterAdded:Connect(function(character)
  task.spawn(function()local humanoid=character:WaitForChild("Humanoid",5);if humanoid and character==localPlayer.Character and checkAltair()then bindJump(humanoid)end end)
 end))end
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

altairValues.loading:Stage(.4,"Preparing interactions")
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

 altairValues.uiAvoidance=altairValues.interfaceBindings.UIAvoidance(UI,function()return settingValue("Avoid Game UI",false)end)
 local dockView=altairValues.interfaceBindings.Dock(UI)
 assert(type(dockView)=="table"and dockView.NavigationGeometryOwnership==1 and type(dockView.SetNavigationState)=="function","Update UI/Build.lua: matching Dock navigation geometry contract 1 is required")
 altairValues.navigationAccents=altairValues.interfaceBindings.NavigationAccents({Root=UI,Dock=dockView,IsBarOpen=function()return smartBarOpen end,IsHomeOpen=function()return homeOpen end})
 altairValues.dragContrast=altairValues.interfaceBindings.DragContrast(UI)
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
		local position=object.Position
		local viewport=UI.AbsoluteSize
		object.Position=UDim2.new(position.X.Scale+(position.X.Offset+delta.X)/math.max(1,viewport.X),0,position.Y.Scale+(position.Y.Offset+delta.Y)/math.max(1,viewport.Y),0)
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
		return panel.Name == "Settings" and (altairValues.settingsLayout and altairValues.settingsLayout:GetRestSize()or UDim2.fromOffset(740,430))
            or panel.Name == "Character" and characterPanelSize
			or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
			or UDim2.fromOffset(581, 246)
	end
 function controller:getPanelSize(panel)return panelSize(panel)end

 function controller:isVertical()return self.dock=="left"or self.dock=="right"end
 function controller:getBarSize()return dockView:BarSize()end
 function controller:getButtonSize(closed)return dockView:ButtonSize(closed)end
 function controller:getDragSize(length,thickness)return self:isVertical()and UDim2.fromOffset(thickness,length)or UDim2.fromOffset(length,thickness)end
 function controller:getDock()
  if self:isVertical()then return self.dock end
  return centerOf(smartBar).Y<screenOriginY()+screenSize().Y*.5 and"top"or"bottom"
 end
 function controller:setDock(mode,animate)
  if mode~="left"and mode~="right"and mode~="top"and mode~="bottom"then return end
  self.dock=mode;dockView:Apply(mode,animate==true)
 end
 function controller:detectDock(target)
  local viewport=screenSize();local originX=UI.AbsolutePosition.X
  local factor=UI:GetAttribute("AltairDisplayScale")or 1
  local enter=math.clamp(viewport.X*.075,80*factor,120*factor)
  local x=target.X-originX;local mode
  if self.dock=="left"and x<enter+90*factor then mode="left"
  elseif self.dock=="right"and x>viewport.X-enter-90*factor then mode="right"
  elseif x<enter then mode="left"
  elseif x>viewport.X-enter then mode="right"
  else mode=target.Y<screenOriginY()+viewport.Y*.5 and"top"or"bottom"end
  self:setDock(mode,true);return mode
 end

	function controller:getOpenPanel()
		if self.activePanel and self.activePanel.Parent and self.activePanel.Visible then
			return self.activePanel
		end
		for _, name in ipairs({ "Character", "Scripts", "Playerlist", "Settings", "ScriptSearch" }) do
			local panel = UI:FindFirstChild(name)
			if panel and panel.Visible then
				return panel
			end
		end
	end

	function controller:getGap()return altairValues.dockGap*(UI:GetAttribute("AltairDisplayScale") or 1)end

	function controller:getPanelPosition(panel, size)
		size = size or panelSize(panel)
		local dock = self:getDock()
		local viewport = screenSize()
		local barPos, barSize = smartBar.AbsolutePosition, smartBar.AbsoluteSize
		local origin=UI.AbsolutePosition
		local factor=panel:GetAttribute("AltairSurfaceScale") or UI:GetAttribute("AltairDisplayScale") or 1
		local width, height = size.X.Offset*factor, size.Y.Offset*factor
		local gap, margin = self:getGap(), 12
		local x = barPos.X + barSize.X * 0.5 - width * 0.5
		local y = dock == "top"
			and barPos.Y + barSize.Y + gap
			or barPos.Y - height - gap
  if dock=="left"or dock=="right"then
   x=dock=="left"and barPos.X+barSize.X+gap or barPos.X-width-gap
   y=barPos.Y+barSize.Y*.5-height*.5
  end

		x = math.clamp(x, origin.X+margin, math.max(origin.X+margin, origin.X+viewport.X-width-margin))
		y = math.clamp(y, origin.Y+margin, math.max(origin.Y+margin, origin.Y+viewport.Y-height-margin))

		local anchor = panel.AnchorPoint
		local currentAnchor = panel.AbsolutePosition + panel.AbsoluteSize * anchor
		local targetAnchor = Vector2.new(x + width * anchor.X, y + height * anchor.Y)
		local delta = targetAnchor - currentAnchor
		local position=panel.Position
		return UDim2.new(position.X.Scale+(position.X.Offset+delta.X)/math.max(1,viewport.X),0,position.Y.Scale+(position.Y.Offset+delta.Y)/math.max(1,viewport.Y),0)
	end

 function controller:syncContents(animate)
  dockView:Apply(self:getDock(),animate==true or self.dragging)
  if self:isVertical()then return end
  local x=centerOf(smartBar).X;local midpoint=screenSize().X*.5;local nextSide=self.contentSide
  if not nextSide then nextSide=x<midpoint and"left"or"right"
  elseif nextSide=="left"and x>midpoint+24 then nextSide="right"
  elseif nextSide=="right"and x<midpoint-24 then nextSide="left"end
  local changed=nextSide~=self.contentSide;self.contentSide=nextSide
  dockView:Mirror(nextSide=="left",animate==true or changed and not self.initializing)
 end

	local function positionAtRenderedCenter(object, target)
		local delta = target - centerOf(object)
		local position=object.Position
		local viewport=UI.AbsoluteSize
		return UDim2.new(position.X.Scale+(position.X.Offset+delta.X)/math.max(1,viewport.X),0,position.Y.Scale+(position.Y.Offset+delta.Y)/math.max(1,viewport.Y),0)
	end

	local function positionPath()
		return altairValues.altairFolder .. "/position.altair"
	end

	local function finiteFraction(value)
		return type(value) == "number" and value == value and value >= 0 and value <= 1
	end

	function controller:savePosition()
		local viewport = screenSize()
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local center = centerOf(smartBar)
		local position = {
			version = 2,dock=self:getDock(),
			x = math.clamp((center.X - originX) / viewport.X, 0, 1),
			y = math.clamp((center.Y - screenOriginY()) / viewport.Y, 0, 1),
		}
		altairValues.sessionMemory.position = position
		altairValues.sessionMemory:save()
		if type(writefile) ~= "function" then return end
		local ok, err = pcall(function()
			checkFolder()
			writefile(positionPath(), httpService:JSONEncode(position))
		end)
		if not ok then warn("Altair | Unable to save position: " .. tostring(err)) end
	end

	function controller:restoreSavedPosition()
		local ok, position = pcall(function()
			local remembered = altairValues.sessionMemory and altairValues.sessionMemory.position
			if type(remembered)=="table" and (remembered.version==1 or remembered.version==2)and finiteFraction(remembered.x) and finiteFraction(remembered.y) then return remembered end
			if type(readfile) ~= "function" then return nil end
			if isfile and not isfile(positionPath()) then return nil end
			return httpService:JSONDecode(readfile(positionPath()))
		end)
		if not ok or type(position) ~= "table" or (position.version ~= 1 and position.version ~= 2)
			or not finiteFraction(position.x) or not finiteFraction(position.y) then
			return false
		end
		local viewport = screenSize()
		if viewport.X <= 0 or viewport.Y <= 0 then return false end
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local target = Vector2.new(originX + position.x * viewport.X, screenOriginY() + position.y * viewport.Y)
  if position.dock=="left"or position.dock=="right"then self:setDock(position.dock,false)end
  smartBar.Size=self:getBarSize()
  -- Restore from known dimensions, without reading a stale rendered asset size.
  local factor=UI:GetAttribute("AltairDisplayScale")or 1;local size=self:getBarSize()
  local hw,hh=size.X.Offset*factor/2,size.Y.Offset*factor/2
  local x=math.clamp(target.X-originX,hw+8,math.max(hw+8,viewport.X-hw-8))
  local y=math.clamp(target.Y-screenOriginY(),hh+8,math.max(hh+8,viewport.Y-hh-8))
  smartBar.Position=UDim2.fromScale((x+(smartBar.AnchorPoint.X-.5)*size.X.Offset)/viewport.X,(y+(smartBar.AnchorPoint.Y-.5)*size.Y.Offset)/viewport.Y)

		altairValues.smartBarPositionInitialized = true
		return true
	end

	function controller:prepareStartup(hidden)
  self.loading=true
		smartBar.Visible = false
		drag.Visible = false
		smartBar.Size = self:getBarSize()
		if not self:restoreSavedPosition() then
			local viewport = screenSize()
   local bottom=38
			smartBar.Position=UDim2.fromScale(.5,math.max(bottom,viewport.Y-bottom)/math.max(1,viewport.Y))
			altairValues.smartBarPositionInitialized = true
		end
  self:syncContents(false)
  drag.Size=self:getDragSize(150,20)
  if dragVisual then dragVisual.Size=self:getDragSize(100,3)end
		-- Let Roblox resolve absolute geometry while both moving objects are invisible.
		UI.Enabled = true
		runService.RenderStepped:Wait()
		self.closedAtDrag = hidden
		self:cancelDragPositionTween()
		local target = centerOf(smartBar)
		drag.Position = positionAtRenderedCenter(drag, target)
		self:syncContents(false)
		self:syncToasts()
		runService.RenderStepped:Wait() -- Resolve Drag before open/close computes its first tween.
		self.initializing = false
	end

	function controller:getClosedDragCenter()
		if self.exitAnchor then return self.exitAnchor end
  local barCenter = centerOf(smartBar)
  if self:isVertical()then
   local line=dragVisual or drag;local half=line.AbsoluteSize.X/2
   return Vector2.new(self.dock=="left"and smartBar.AbsolutePosition.X+half or smartBar.AbsolutePosition.X+smartBar.AbsoluteSize.X-half,barCenter.Y)
  end
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
		-- Hover may resize Drag while it travels. It must not cancel Position.
		if size then tweenService:Create(drag,info,{Size=size}):Play() end
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
  if self:isVertical()then
   local line=dragVisual or drag;local halfLine=line.AbsoluteSize.X/2
   local edge=dock=="left"and barPos.X+barSize.X or barPos.X
   for _,name in ipairs({"Character","Scripts","Playerlist","Settings","ScriptSearch"})do
    local panel=UI:FindFirstChild(name)
    if panel and panel.Visible then edge=dock=="left"and math.max(edge,panel.AbsolutePosition.X+panel.AbsoluteSize.X)or math.min(edge,panel.AbsolutePosition.X)end
   end
   local x=dock=="left"and edge+self:getGap()+halfLine or edge-self:getGap()-halfLine
   local origin=UI.AbsolutePosition
   return Vector2.new(math.clamp(x,origin.X+8+halfLine,math.max(origin.X+8+halfLine,origin.X+viewport.X-8-halfLine)),math.clamp(barPos.Y+barSize.Y/2,origin.Y+drag.AbsoluteSize.Y/2+8,math.max(origin.Y+drag.AbsoluteSize.Y/2+8,origin.Y+viewport.Y-drag.AbsoluteSize.Y/2-8)))
  end
  local half = drag.AbsoluteSize * 0.5
		local gap = self:getGap()
		local line = dragVisual and dragVisual:IsA("GuiObject") and dragVisual or drag
		local lineTop = line.AbsolutePosition.Y - centerOf(drag).Y
		local lineBottom = lineTop + line.AbsoluteSize.Y
		local targetX = barPos.X + barSize.X * 0.5
		local edge = dock == "bottom" and barPos.Y or (barPos.Y + barSize.Y)

		for _, name in ipairs({ "Character", "Scripts", "Playerlist", "Settings", "ScriptSearch" }) do
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

	function controller:syncDrag(dt)
  if self.loading then return end
  local wasVisible=drag.Visible
		drag.Visible = not settingValue("Hide Bar")
  if drag.Visible and not wasVisible then drag.Drag.Visible=true;self:setDragVisual(100,self.dragHovered and .4 or .76,.18)end
		drag.BackgroundTransparency = 1

		if self.dragging then return end
  if self.dragPositionTween then
   local state=self.dragPositionTween.PlaybackState
   if state==Enum.PlaybackState.Completed or state==Enum.PlaybackState.Cancelled then self.dragPositionTween=nil else return end
  end

		-- Absolute coordinates include the ScreenGui origin; preserve that conversion.
		local target=smartBarOpen and self:getRestDragCenter() or self:getClosedDragCenter()
		local current=centerOf(drag)
        if (target-current).Magnitude<.05 then return end
        local alpha=1-math.exp(-32*math.min(dt or 1/60,.1))
        drag.Position=positionAtRenderedCenter(drag,current:Lerp(target,alpha))
	end

	function controller:cancelToastPositionTween()
		local animation = self.toastPositionTween
		self.toastPositionTween = nil
		if animation then animation:Cancel() end
	end

	function controller:syncToasts(dragCenter)
		if not checkAltair() or not (toastsContainer and toastsContainer.Parent and drag.Parent) then
			self:cancelToastPositionTween()
			return
		end

		local viewport = screenSize()
		local originX = UI:IsA("ScreenGui") and UI.AbsolutePosition.X or 0
		local margin, gap = 8, self:getGap()
		local topEdge, bottomEdge = screenOriginY() + margin, screenOriginY() + viewport.Y - margin
		local toastPos, toastSize = toastsContainer.AbsolutePosition, toastsContainer.AbsoluteSize
		local dragSize = drag.AbsoluteSize
		dragCenter = dragCenter or centerOf(drag)
  local capsules=altairValues.capsules
  local reserved=capsules and capsules.GetDockObstacle and capsules:GetDockObstacle()
  if self:isVertical()then
   self.toastCapsuleTarget=nil
   local targetLeft=originX+(viewport.X-toastSize.X)/2
   local targetTop=bottomEdge-toastSize.Y-20
   -- Side-docked toasts keep their bottom-centre anchor, but must share the
   -- same docked-capsule clearance policy as horizontally docked toasts.
   if reserved and targetLeft < reserved[3]+gap and targetLeft+toastSize.X > reserved[1]-gap
    and targetTop < reserved[4]+gap and targetTop+toastSize.Y > reserved[2]-gap then
    local clearAbove=reserved[2]-gap-toastSize.Y
    local clearBelow=reserved[4]+gap
    if clearAbove>=topEdge then targetTop=clearAbove
    elseif clearBelow+toastSize.Y<=bottomEdge then targetTop=clearBelow
    else targetTop=math.min(clearBelow,bottomEdge-toastSize.Y)end
   end
   local target=Vector2.new(targetLeft,targetTop)
   if not self.toastSidebarTarget or(self.toastSidebarTarget-target).Magnitude>.5 then
    self:cancelToastPositionTween()
    self.toastSidebarTarget=target
    local animation=tweenService:Create(toastsContainer,TweenInfo.new(.2,Enum.EasingStyle.Sine),{Position=toastsContainer.Position+UDim2.fromOffset(target.X-toastPos.X,target.Y-toastPos.Y)})
    self.toastPositionTween=animation
    animation.Completed:Once(function()if self.toastPositionTween==animation then self.toastPositionTween=nil end end)
    animation:Play()
   end
   local layout=toastsContainer:FindFirstChildOfClass("UIListLayout");if layout then layout.VerticalAlignment=Enum.VerticalAlignment.Bottom end
   for _,toast in ipairs(toastsContainer:GetChildren())do local title=toast:FindFirstChild("Title");if title and title:IsA("TextLabel")then title.TextXAlignment=Enum.TextXAlignment.Center end end
   return
  end
  self:cancelToastPositionTween()
  self.toastSidebarTarget=nil

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
        -- Capsules reserve clearance only; the Smartbar remains the toast anchor.
        if reserved and targetLeft < reserved[3]+gap and targetLeft+toastSize.X > reserved[1]-gap
            and targetTop < reserved[4]+gap and targetTop+toastSize.Y > reserved[2]-gap then
            local clearAbove=reserved[2]-gap-toastSize.Y
            local clearBelow=reserved[4]+gap
            if bottomDock and clearAbove>=topEdge then targetTop=clearAbove
            elseif not bottomDock and clearBelow+toastSize.Y<=bottomEdge then targetTop=clearBelow
            elseif clearAbove>=topEdge then targetTop=clearAbove
            else targetTop=math.min(clearBelow,bottomEdge-toastSize.Y) end
        end
		toastsContainer.Position += UDim2.fromOffset(targetLeft - toastPos.X, targetTop - toastPos.Y)
	end

	function controller:syncPanels(dt)
		if not self.dragging then
			return
		end

		local alpha = 1 - math.pow(1e-8, dt)
		for _, name in ipairs({ "Character", "Scripts", "Playerlist", "Settings" }) do
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
		self:syncDrag(dt)
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
  self:detectDock(target)
  if self:isVertical()then
   local factor=UI:GetAttribute("AltairDisplayScale")or 1;local size=self:getBarSize()
   local half=Vector2.new(size.X.Offset,size.Y.Offset)*factor/2
   local line=dragVisual or drag;local halfLine=line.AbsoluteSize.X/2
   local offset=Vector2.new((self.dock=="left"and -1 or 1)*(half.X+self:getGap()+halfLine),0)
   local originX=UI.AbsolutePosition.X
   local minX=originX+8-math.min(-halfLine,offset.X-half.X)
   local maxX=originX+viewport.X-8-math.max(halfLine,offset.X+half.X)
   local y=math.clamp(target.Y,originY+8+half.Y,math.max(originY+8+half.Y,originY+viewport.Y-8-half.Y))
   self.barOffsetY=0;self.animatedDragSide=nil
   return Vector2.new(math.clamp(target.X,minX,math.max(minX,maxX)),y),offset
  end
  -- Evaluate the requested center BEFORE clamping, so either zone stays reachable.
		if target.Y <= originY + viewport.Y * 0.22 then
			self.dragSide = -1
		elseif target.Y >= originY + viewport.Y * 0.50 then
			self.dragSide = 1
		end

		local lineTop, lineBottom = dragLineOffsets()
		local halfBar = smartBar.AbsoluteSize.Y * 0.5
		local wantedOffset = self.dragSide < 0
			and lineTop - self:getGap() - halfBar
			or lineBottom + self:getGap() + halfBar
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

 function controller:applySnapping(point,offset)
  if not self.snapGuides then self.snapGuides=altairValues.interfaceBindings.SnapGuides(UI)end
  local viewport=screenSize();local origin=UI.AbsolutePosition
  local factor=UI:GetAttribute("AltairDisplayScale")or 1;local barSize=self:getBarSize()
  local half=Vector2.new(barSize.X.Offset,barSize.Y.Offset)*factor/2
  local delta=typeof(offset)=="Vector2"and offset or Vector2.new(0,offset)
  local function axis(value,length,start,previous,halfSize,barDelta)
   local best,distance=nil,math.huge
   for _,ratio in ipairs({.25,.5,.75})do
    local candidate=start+length*ratio
    local threshold=previous==candidate and 22 or 12
    local d=math.abs(value-candidate)
    if d<threshold and d<distance and candidate+barDelta-halfSize>=start+8 and candidate+barDelta+halfSize<=start+length-8 then best=candidate;distance=d end
   end
   return best
  end
  local barPoint=point+delta
  local x=axis(barPoint.X,viewport.X,origin.X,self.snapX,half.X,0)
  local y=axis(barPoint.Y,viewport.Y,origin.Y,self.snapY,half.Y,0)
  self.snapX,self.snapY=x,y
  local target=Vector2.new(x or barPoint.X,y or barPoint.Y)
  return target-delta
 end
 function controller:publishSnapping(point,offset)
  if not checkAltair()or not self.dragging or not self.snapGuides then return end
  local guides=self.snapGuides
  local delta=typeof(offset)=="Vector2"and offset or Vector2.new(0,offset)
  -- Only publish accepted axes, after collision resolution has rejected any
  -- displaced coordinate. Ordinary smoothing lag is not a snap rejection.
  if guides:Update(point+delta,self.snapX,self.snapY,settingValue("Snap Visual Effects",true))and os.clock()-(self.snapBlinkAt or 0)>.3 then
   self.snapBlinkAt=os.clock()
   local session=self.dragSession
   BlinkSmartBar(1,nil,function()
    if checkAltair()and self.dragging and self.dragSession==session and self.snapGuides==guides then guides:Pulse()end
   end)
  end
 end
 -- A fast release can precede the dock morph. Its endpoint is based on the
 -- authored dock footprint; rendered bounds only constrain the journey there.
 function controller:releaseDockTarget(point)
  local viewport,origin=screenSize(),UI.AbsolutePosition
  local factor=UI:GetAttribute("AltairDisplayScale")or 1
  local dimensions=self:getBarSize();local half=Vector2.new(dimensions.X.Offset,dimensions.Y.Offset)*factor*.5
  local edge=factor;local offset
  if self:isVertical()then offset=Vector2.new((self.dock=="left"and -1 or 1)*(half.X+self:getGap()+edge),0)
  else offset=Vector2.new(0,(self.dragSide<0 and -1 or 1)*(half.Y+self:getGap()+edge))end
  local lineHalf=self:isVertical()and Vector2.new(edge,50*factor)or Vector2.new(50*factor,edge)
  local lower=Vector2.new(math.min(-lineHalf.X,offset.X-half.X),math.min(-lineHalf.Y,offset.Y-half.Y))
  local upper=Vector2.new(math.max(lineHalf.X,offset.X+half.X),math.max(lineHalf.Y,offset.Y+half.Y))
  local minimum=origin+Vector2.new(8,8)-lower;local maximum=origin+viewport-Vector2.new(8,8)-upper
  local anchor=Vector2.new(math.clamp(point.X,minimum.X,math.max(minimum.X,maximum.X)),math.clamp(point.Y,minimum.Y,math.max(minimum.Y,maximum.Y)))
  return anchor+offset,anchor
 end
	function controller:moveSmartBar(dragCenter, dt, barOffset)
		altairValues.smartBarPositionInitialized = true
		local viewport = screenSize()
		local half = smartBar.AbsoluteSize * 0.5
		local middle = viewport.X * 0.5
		local x = dragCenter.X
  if typeof(barOffset)=="Vector2"then
   local target=clampCenter(smartBar,dragCenter+barOffset,8)
   self.mainDragTarget=target;self.lastDragTarget=dragCenter;self.barOffsetY=0
   local response=UI:GetAttribute("AltairReduceMotion")and 1 or 1-1e-7^math.min(dt or 1/60,.1)
   moveCenter(smartBar,centerOf(smartBar):Lerp(target,response));return
  end
		self.barOffsetY = barOffset
		-- Use the same rendered-line geometry as the target clamp; no competing Y clamp.
  local target=Vector2.new(math.clamp(x,half.X+8,math.max(half.X+8,viewport.X-half.X-8)),dragCenter.Y+barOffset)
  self.mainDragTarget=target;self.lastDragTarget=dragCenter
  local response=UI:GetAttribute("AltairReduceMotion")and 1 or 1-1e-7^math.min(dt or 1/60,.1)
  moveCenter(smartBar,centerOf(smartBar):Lerp(target,response))
	end

	function controller:setDragVisual(width, transparency, duration)
		if not dragVisual or not dragVisual:IsA("GuiObject") then
			return
		end
		self.dragVisualTransparency=transparency
		local goal = { Size = self:getDragSize(width,3) }
		if dragVisual:IsA("ImageLabel") or dragVisual:IsA("ImageButton") then
			goal.ImageTransparency = transparency
		else
			goal.BackgroundTransparency = transparency
		end
  if duration==0 then for key,value in pairs(goal)do dragVisual[key]=value end;return end
		tweenService:Create(dragVisual, TweenInfo.new(duration or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), goal):Play()
	end

	function controller:bind(toggleSmartBar)
		track(UI.Destroying:Connect(function()self:cancelToastPositionTween()end))
		local barCenter, dragCenter = centerOf(smartBar), centerOf(drag)
		smartBar.AnchorPoint = Vector2.new(0.5, 0.5)
		drag.AnchorPoint = Vector2.new(0.5, 0.5)
		moveCenter(smartBar, clampCenter(smartBar, barCenter, 8))
		moveCenter(drag, clampCenter(drag, dragCenter, 8))

		drag.Size = self:getDragSize(150,20)
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

		self:setDragVisual(100, .76, 0)

		track(drag:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if not self.dragging then self:syncToasts() end
		end))

		track(drag.Interact.MouseEnter:Connect(function()
			self.dragHovered = true
			if not self.dragging then
				tweenService:Create(drag, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = self:getDragSize(165,22),
				}):Play()
				self:setDragVisual(120, .4, .25)
			end
		end))

		track(drag.Interact.MouseLeave:Connect(function()
			self.dragHovered = false
			if not self.dragging then
				tweenService:Create(drag, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = self:getDragSize(150,20),
				}):Play()
				self:setDragVisual(100, .76, .25)
			end
		end))

		track(drag.Interact.InputBegan:Connect(function(input)
			local inputType = input.UserInputType
			if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
				return
			end
			if self.dragging then return end

			self:cancelDragPositionTween()
			self.releaseMotion=nil
			self.dragging = true
			self.dragMoved = false
   self.dragSession=(self.dragSession or 0)+1;self.mainDragTarget=nil;self.lastDragTarget=nil
   self.openedForDrag=not smartBarOpen
   self.dragReadyAt=self.openedForDrag and os.clock()+.16 or 0
   if self.openedForDrag and self.openForDrag then task.spawn(self.openForDrag)end
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
				Size = self:getDragSize(175,24),
			}):Play()
			self:setDragVisual(110, .3, 0.25)
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
            self.snapX=nil;self.snapY=nil;if self.snapGuides then self.snapGuides:Clear()end
			self.touchInput = nil
			if self.viewportFitPending then self:fitViewport() end
			tweenService:Create(drag, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = self:getDragSize(150,20),
			}):Play()
			self:setDragVisual(100, self.dragHovered and .4 or .76, 0.3)
			self:sync(1 / 60, true)
			if self.dragMoved and self.mainDragTarget then
    local session=self.dragSession
    if dockView.morphActive and not settingValue("Avoid Game UI",false)then
     self.mainDragTarget,self.lastDragTarget=self:releaseDockTarget((self.lastPointer or pointerPosition())+self.grabOffset)
     self.releaseMotion={target=self.mainDragTarget,session=session}
    else
     tweenService:Create(smartBar,TweenInfo.new(.22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=positionAtRenderedCenter(smartBar,self.mainDragTarget)}):Play()
     self:tweenDragCenter(self.lastDragTarget,TweenInfo.new(.22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out))
     task.delay(.24,function()if UI.Parent and not self.dragging and self.dragSession==session then self:savePosition()end end)
    end
   elseif self.dragMoved and not self.openedForDrag then self:savePosition()end

			if not self.dragMoved and not self.openedForDrag and toggleSmartBar then
				toggleSmartBar()
			end
		end

		track(userInputService.InputEnded:Connect(function(input)
			local inputType = input.UserInputType
			if self.touchInput and input==self.touchInput or not self.touchInput and inputType==Enum.UserInputType.MouseButton1 then
				finish(input)
			end
		end))
		track(userInputService.WindowFocusReleased:Connect(function()
			finish()
		end))

		track(runService.RenderStepped:Connect(function(dt)
			if not UI.Parent or self.initializing or self.loading then
				return
			end

			if self.dragging then
				local pointer = self.touchInput and self.lastPointer or pointerPosition()
				if (pointer - self.startPointer).Magnitude > 6 then
					self.dragMoved = true
				end

				self.lastRenderPointer = pointer

				if self.dragMoved and os.clock()>=(self.dragReadyAt or 0)then
     self:cancelDragPositionTween()
					local dragCenter, barOffset = self:clampDragTarget(pointer + self.grabOffset, dt)
     dragCenter=self:applySnapping(dragCenter,barOffset)
     local rendered=centerOf(drag)
     local nextCenter=rendered:Lerp(dragCenter,1-1e-60^math.min(dt,.1))
     if settingValue("Avoid Game UI",false)then
      local offset=typeof(barOffset)=="Vector2"and barOffset or Vector2.new(0,barOffset)
      local actual=centerOf(smartBar)-rendered
      local dimensions=self:getBarSize();local factor=UI:GetAttribute("AltairDisplayScale")or 1
      -- The finite dock morph can grow after a quick release. Reserve both
      -- its current dimensions and authored endpoint in the existing sweep.
      local currentSize=smartBar.AbsoluteSize
      local half=Vector2.new(math.max(currentSize.X,dimensions.X.Offset*factor),math.max(currentSize.Y,dimensions.Y.Offset*factor))*.5
      local handle=(dragVisual or drag).AbsoluteSize*.5
      local extents={math.min(-handle.X,offset.X-half.X,actual.X-half.X),math.min(-handle.Y,offset.Y-half.Y,actual.Y-half.Y),math.max(handle.X,offset.X+half.X,actual.X+half.X),math.max(handle.Y,offset.Y+half.Y,actual.Y+half.Y)}
      local proposed=nextCenter
      nextCenter=altairValues.uiAvoidance:Resolve(rendered,nextCenter,extents)
      dragCenter=nextCenter -- Both rendered surfaces follow the collision-constrained position.
      if self.snapX and math.abs(nextCenter.X-proposed.X)>1.5 then self.snapX=nil end
      if self.snapY and math.abs(nextCenter.Y-proposed.Y)>1.5 then self.snapY=nil end
     end
     self:publishSnapping(dragCenter,barOffset)
     moveCenter(drag,nextCenter)
					self:moveSmartBar(dragCenter, dt, barOffset)
					self:syncContents(true)
					self:syncPanels(dt)
					self:syncToasts(dragCenter)
				end
            else
             local release=self.releaseMotion
             if release then
              if release.session~=self.dragSession then self.releaseMotion=nil
              else
               local target=clampCenter(smartBar,release.target,8)
               moveCenter(smartBar,centerOf(smartBar):Lerp(target,1-1e-24^math.min(dt,.1)))
               if not dockView.morphActive and(centerOf(smartBar)-release.target).Magnitude<.15 then
                moveCenter(smartBar,release.target);self.releaseMotion=nil;self:savePosition()
               end
              end
             end
             -- Visual following stays at display refresh; only housekeeping is throttled.
             self:syncDrag(dt)
             self.idleAccumulator+=dt
             if self.idleAccumulator>=.1 then self.idleAccumulator=0;self:syncContents(false);self:syncToasts()end
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
 local entries,refresh={},0
 local function visible(object)
  while object do
   if object:IsA("GuiObject") and not object.Visible or object:IsA("ScreenGui") and not object.Enabled then return false end
   object=object.Parent
  end
  return true
 end
 local function hotbarName(name)
  name=name:lower();return name:find("hotbar",1,true) or name:find("backpack",1,true) or name:find("quickbar",1,true) or name:find("toolbar",1,true)
 end
 local function parentHeight(object)
  local parent=object.Parent;while parent and not parent:IsA("GuiBase2d")do parent=parent.Parent end
  return math.max(1,parent and parent.AbsoluteSize.Y or camera.ViewportSize.Y)
 end
 local function restore(object,entry)
  if object.Parent and math.abs(entry.shift)>.01 then object.Position=entry.position end
 end
 local candidates=setmetatable({}, {__mode="k"})
 local function consider(object)
  if object:IsA("GuiObject")and not object:IsDescendantOf(UI)and hotbarName(object.Name)then candidates[object]=true;refresh=0 end
 end
 for _,root in ipairs({coreGui,localPlayer:FindFirstChildOfClass("PlayerGui")})do if root then
  for _,branch in ipairs(root:GetChildren())do if branch~=UI then consider(branch);for _,object in ipairs(branch:GetDescendants())do consider(object)end end end
  track(root.DescendantAdded:Connect(consider))
  track(root.DescendantRemoving:Connect(function(object)if candidates[object]then candidates[object]=nil;refresh=0 end end))
 end end
 local function scan()
  local found={}
  for object in pairs(candidates)do if object.Parent and visible(object)then found[object]=true end end
  local roots={}
  for object in pairs(found)do
   local parent,nested=object.Parent,false
   while parent do if found[parent]then nested=true;break end;parent=parent.Parent end
   if not nested then roots[object]=true end
  end
  for object,entry in pairs(entries)do if not roots[object]then restore(object,entry);entries[object]=nil end end
  for object in pairs(roots)do
   local bounds,best
   for candidate in pairs(candidates)do
    if not candidate:IsDescendantOf(object)then continue end
    local name=candidate.Name:lower()
    if candidate:IsA("GuiObject") and not candidate:IsA("TextLabel") and visible(candidate) and (name:find("hotbar",1,true)or name:find("quickbar",1,true)or name:find("toolbar",1,true)) and candidate.AbsoluteSize.X>0 and candidate.AbsoluteSize.Y>0 and candidate.AbsoluteSize.Y<camera.ViewportSize.Y*.4 then
     local score=candidate.AbsoluteSize.X*candidate.AbsoluteSize.Y
     if name=="hotbar"or name=="quickbar"or name=="toolbar"then score+=10000000 end
     if not best or score>best then bounds,best=candidate,score end
    end
   end
   if not bounds and object.AbsoluteSize.Y<camera.ViewportSize.Y*.4 then bounds=object end
   if bounds then
    if not entries[object]then entries[object]={position=object.Position,shift=0,applied=object.Position}end
    entries[object].bounds=bounds
   elseif entries[object]then restore(object,entries[object]);entries[object]=nil end
  end
 end
 updateBackpackLayout=function()refresh=0 end
 local accumulator=0
 local connection=track(runService.RenderStepped:Connect(function(dt)
  if not UI.Parent then return end
  accumulator+=dt;dt,accumulator=accumulator,0
  refresh-=dt;if refresh<=0 then scan();refresh=2 end
  if next(entries)==nil then return end
  local layout=altairValues.smartBarLayout;local side=layout:isVertical();local bottom=side and smartBar.AbsolutePosition.Y+smartBar.AbsoluteSize.Y/2>UI.AbsolutePosition.Y+UI.AbsoluteSize.Y/2 or not side and layout:getDock()=="bottom";local gap=layout:getGap();local obstacles={}
  local line=drag:FindFirstChild("Drag")
  if line and visible(line)then obstacles[#obstacles+1]=line end
  if smartBarOpen or smartBar.Back.BackgroundTransparency<.99 then obstacles[#obstacles+1]=smartBar end
  for _,name in ipairs({"Character","Scripts","Playerlist","Settings","SharedPanelSurface"})do
   local panel=UI:FindFirstChild(name);if panel and panel.Visible and panel.BackgroundTransparency<.99 then obstacles[#obstacles+1]=panel end
  end
  local alpha=1-math.exp(-32*dt)
  for object,entry in pairs(entries)do
   local bounds=entry.bounds
   if object.Parent and bounds.Parent and visible(bounds) and bounds.AbsoluteSize.Y>0 then
    -- Respect a game moving its own container instead of retaining a stale baseline.
    local height=parentHeight(object)
    if object.Position~=entry.applied and object.Position~=entry.position then entry.position=object.Position;entry.shift=0 end
    local displacement=(entry.position.Y.Scale-object.Position.Y.Scale)*height
    local restingTop=bounds.AbsolutePosition.Y+displacement;local left=bounds.AbsolutePosition.X;local right=left+bounds.AbsoluteSize.X;local edge
    for _,obstacle in ipairs(obstacles)do
     local position,size=obstacle.AbsolutePosition,obstacle.AbsoluteSize
     if right>position.X-gap and left<position.X+size.X+gap and(not side or restingTop<position.Y+size.Y+gap and restingTop+bounds.AbsoluteSize.Y>position.Y-gap)then
      local boundary=bottom and position.Y or position.Y+size.Y
      edge=edge and (bottom and math.min(edge,boundary)or math.max(edge,boundary))or boundary
     end
    end
    local target=0
    if edge then target=bottom and math.max(0,restingTop+bounds.AbsoluteSize.Y-edge+gap)or math.min(0,restingTop-edge-gap)end
    entry.shift+=(target-entry.shift)*alpha
    if math.abs(target-entry.shift)<.1 then entry.shift=target end
    local position=entry.position-UDim2.new(0,0,entry.shift/parentHeight(object),0)
    if object.Position~=position then object.Position=position end;entry.applied=position
   end
  end
 end))
 UI.Destroying:Connect(function()connection:Disconnect();for object,entry in pairs(entries)do restore(object,entry)end end)
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

	local factor=UI:GetAttribute("AltairDisplayScale") or 1
	return UDim2.fromOffset(buttonSize.X/factor, buttonSize.Y/factor),
		panel.Position + UDim2.fromOffset(delta.X, delta.Y)
end

altairValues.panelPointerConnections = altairValues.panelPointerConnections or {}
altairValues.panelPointerViews=setmetatable({}, {__mode="k"})
altairValues.panelPointerShown=setmetatable({}, {__mode="k"})

altairValues.getPanelPointer = function(panel)
 if panel then local authored=panel:FindFirstChild("Pointer");if authored then authored.Visible=false end end
 local cached=altairValues.panelPointerViews[panel];if cached and cached.Parent then return cached end
 local shared=altairValues.sharedPanelPointer;if shared and shared.Parent then altairValues.panelPointerViews[panel]=shared;return shared end
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

  local overlay=pointer:Clone();pointer.Visible=false
  overlay.Name=panel.Name.."PanelPointer";overlay.Visible=false;overlay:SetAttribute("AltairThemeIgnore",true);overlay.Parent=UI
  overlay.ZIndex=panel.ZIndex-1;overlay.BackgroundTransparency=1
  altairValues.sharedPanelPointer=overlay
  altairValues.panelPointerViews[panel]=overlay
  return overlay
	end

	return nil
end

altairValues.syncPanelPointer = function(panel, button)
	local pointer = altairValues.getPanelPointer(panel)
 if altairValues.panelPointerOwner~=panel then return pointer end
	if not (pointer and button and button:IsA("GuiObject")) then
		return nil
	end

 local position,size=panel.AbsolutePosition,panel.AbsoluteSize
 local center=button.AbsolutePosition+button.AbsoluteSize*.5
 local half=size*.5;local delta=center-(position+half)
 local margin=18;local destination
 if math.abs(delta.X)/math.max(1,half.X)>math.abs(delta.Y)/math.max(1,half.Y)then
  destination=Vector2.new(delta.X<0 and position.X or position.X+size.X,math.clamp(center.Y,position.Y+margin,math.max(position.Y+margin,position.Y+size.Y-margin)))
 else
  destination=Vector2.new(math.clamp(center.X,position.X+margin,math.max(position.X+margin,position.X+size.X-margin)),delta.Y<0 and position.Y or position.Y+size.Y)
 end
 local factor=UI:GetAttribute("AltairDisplayScale")or 1
 pointer.Size=UDim2.fromOffset(12*factor,12*factor);pointer.Rotation=45;pointer.AnchorPoint=Vector2.new(.5,.5)
 pointer.ZIndex=math.min(panel.ZIndex,UI.SharedPanelSurface.Visible and UI.SharedPanelSurface.ZIndex or panel.ZIndex)-1
 local material=UI.SharedPanelSurface.Visible and UI.SharedPanelSurface or panel
 local color=material.BackgroundColor3;local gradient=material:FindFirstChildOfClass("UIGradient")
 if gradient then local points=gradient.Color.Keypoints;local tint=points[1].Value:Lerp(points[#points].Value,.5);color=Color3.new(color.R*tint.R,color.G*tint.G,color.B*tint.B)end
 pointer.BackgroundColor3=color
 local origin=UI.AbsolutePosition
 if not pointer:GetAttribute("AltairPointerInitialized")then pointer.Position=UDim2.fromOffset(center.X-origin.X,center.Y-origin.Y);pointer:SetAttribute("AltairPointerInitialized",true)end
 tweenService:Create(pointer,TweenInfo.new(.28,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(destination.X-origin.X,destination.Y-origin.Y)}):Play()

	return pointer
end

altairValues.setPanelPointerVisible = function(panel, button, visible, duration)
 if not visible and altairValues.panelPointerOwner~=panel then return end
 if visible then altairValues.panelPointerOwner=panel end
 altairValues.panelPointerShown[panel]=visible==true
	local pointer = altairValues.syncPanelPointer(panel, button)
	if not pointer then
		return
	end

 pointer.Visible=panel.Visible
	local goal = {}
	if pointer:IsA("ImageLabel") or pointer:IsA("ImageButton") then
		goal.ImageTransparency = visible and 0 or 1
	elseif pointer:IsA("Frame") or pointer:IsA("ScrollingFrame") then
		goal.BackgroundTransparency = visible and altairValues.surfaceTransparency(panel)or 1
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

 track(panel:GetPropertyChangedSignal("Visible"):Connect(function()if altairValues.panelPointerOwner==panel and altairValues.sharedPanelPointer then altairValues.sharedPanelPointer.Visible=panel.Visible end end))
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
        track(panel:GetPropertyChangedSignal("BackgroundColor3"):Connect(sync)),
	}

	local gradient=panel:FindFirstChildOfClass("UIGradient");if gradient then table.insert(altairValues.panelPointerConnections[panel],track(gradient:GetPropertyChangedSignal("Color"):Connect(sync)))end
	sync()
end

altairValues.panelTextOpacity=setmetatable({}, {__mode="k"})
function altairValues.fadePanelText(panel,visible)
 if panel.Name=="Playerlist"and panel.Interactions:GetAttribute("AltairFadeGroup")then return end
	for _,text in ipairs(panel:GetDescendants()) do
		if text:IsA("TextLabel") or text:IsA("TextButton") or text:IsA("TextBox") then
			if altairValues.characterRuler and text:IsDescendantOf(altairValues.characterRuler.Root)then continue end
			if text:FindFirstAncestor("RulerContent")then continue end
			if visible and panel.Name=="Playerlist" and text.Parent==panel and text.Name=="Subtitle" then
				altairValues.panelTextOpacity[text]=nil;continue -- Its dedicated entrance starts with the header.
			end
			local saved=altairValues.panelTextOpacity[text]
			if not visible then
				if not saved then saved={text.TextTransparency,text.TextStrokeTransparency};altairValues.panelTextOpacity[text]=saved end
				tweenService:Create(text,TweenInfo.new(.12,Enum.EasingStyle.Quint),{TextTransparency=1,TextStrokeTransparency=1}):Play()
			elseif saved then
				tweenService:Create(text,TweenInfo.new(.18,Enum.EasingStyle.Quint),{TextTransparency=saved[1],TextStrokeTransparency=saved[2]}):Play()
				altairValues.panelTextOpacity[text]=nil
			end
		end
	end
end
altairValues.panelLayers=setmetatable({}, {__mode="k"})
function altairValues.panelBehindBar(panel,closing)
 if closing then
  if altairValues.panelLayers[panel] then return end
  local saved=setmetatable({}, {__mode="k"});altairValues.panelLayers[panel]=saved
  if UI.ZIndexBehavior==Enum.ZIndexBehavior.Sibling then saved[panel]=panel.ZIndex;panel.ZIndex=math.min(panel.ZIndex,smartBar.ZIndex-1);return end
  local ceiling=smartBar.ZIndex-1
  for _,object in ipairs(smartBar:GetDescendants()) do if object:IsA("GuiObject") then ceiling=math.min(ceiling,object.ZIndex-1) end end
  for _,object in ipairs({panel,table.unpack(panel:GetDescendants())}) do
   if object:IsA("GuiObject") then saved[object]=object.ZIndex;object.ZIndex=math.min(object.ZIndex,ceiling) end
  end
 else
  local saved=altairValues.panelLayers[panel]
  if saved then for object,z in pairs(saved) do if object.Parent then object.ZIndex=z end end end
  altairValues.panelLayers[panel]=nil
 end
end
-- One visual shell is retained while the existing panel content changes.
altairValues.sharedPanel=(function()
 local controller={generation=0,fadingDecks=setmetatable({},{__mode="k"})};local shell=UI.SharedPanelSurface
 local names={"Character","Scripts","Playerlist","Settings"}
 local primary={};for _,name in ipairs(names)do primary[#primary+1]=UI:FindFirstChild(name)end
 -- Save authored child coordinates before any entrance can shift them. Sampling
 -- a moving child during the next switch would make that offset its new rest.
 for _,panel in ipairs(primary)do for _,object in ipairs(panel:GetChildren())do
  if object:IsA("GuiObject")then
   object:SetAttribute("AltairDeckRest",object.Position)
   if object.Name=="Interactions"or object.Name=="SettingLists"then object:SetAttribute("AltairContentRestPosition",object.Position)end
   if object.Name=="Icon"or object.Name=="Title"or object.Name=="Subtitle"or object.Name=="HeaderIcon"or object.Name=="ContentTitle"or object.Name=="ContentSubtitle"then object:SetAttribute("AltairHeadingRest",object.Position)end
  end
 end end
 UI.Destroying:Connect(function()
  controller.generation+=1;controller.pending=false
  controller:stopDeck(nil);controller.deckProgress=nil
  if controller.materialTween then controller.materialTween:Cancel()end
  for _,panel in ipairs(primary)do panel:SetAttribute("AltairClosing",true);panel:SetAttribute("AltairMotionVersion",(panel:GetAttribute("AltairMotionVersion") or 0)+1)end
 end)
 local function point(value,viewport)
  return Vector2.new(value.X.Scale*viewport.X+value.X.Offset,value.Y.Scale*viewport.Y+value.Y.Offset)
 end
 local function fractional(value,viewport)
  return UDim2.fromScale(value.X/math.max(1,viewport.X),value.Y/math.max(1,viewport.Y))
 end
 function controller:stopDeck(keep,fading)
  if self.deckConnection then self.deckConnection:Disconnect();self.deckConnection=nil end
  if self.deckTween then self.deckTween:Cancel();self.deckTween=nil end
  self.deckCarry=nil;self.deckStride=nil
  local records=self.deckRecords;self.deckRecords=nil
  if records then for _,record in ipairs(records)do
   local panel=record.panel
   if panel.Parent then
    panel:SetAttribute("AltairDeckSource",nil);panel:SetAttribute("AltairDeckActive",nil)
    if fading then
     -- Cancellation must retain the last clipped frame until its content fades.
     -- A new prepare() revokes this record, so interrupted reopening owns it.
     self.fadingDecks[panel]=record;panel:SetAttribute("AltairSharedSwitch",false)
     if panel~=keep then
      panel:SetAttribute("AltairClosing",true)
      panel:SetAttribute("AltairMotionVersion",(panel:GetAttribute("AltairMotionVersion")or 0)+1)
      wipeTransparency(panel,1,false,true,.06)
     end
     task.delay(.08,function()
      if self.fadingDecks[panel]~=record then return end
      self.fadingDecks[panel]=nil
      if panel.Parent and panel:GetAttribute("AltairClosing")and not panel:GetAttribute("AltairDeckActive")then
       for _,item in ipairs(record.objects)do if item.object.Parent then item.object.Position=item.rest end end
       if panel~=keep then panel.Visible=false end
      end
     end)
    else
     for _,item in ipairs(record.objects)do if item.object.Parent then item.object.Position=item.rest end end
     if panel~=keep then panel.Visible=false;panel:SetAttribute("AltairSharedSwitch",false)end
    end
   end
  end end
 end
 function controller:scrollDeck(target,size)
  local from=self.deckStart or self.sourceIndex or self.targetIndex
  local to=self.targetIndex;local duration=.26+.045*math.abs(to-from)
  local reduced=UI:GetAttribute("AltairReduceMotion")==true
  if reduced then from=to end -- Keep the target clip stationary; its normal entrance still fades.
  local lo,hi=math.floor(math.min(from,to)),math.ceil(math.max(from,to))
  local records={};local factor=UI:GetAttribute("AltairDisplayScale")or 1
  local viewport=UI.AbsoluteSize;local shellStart=point(shell.Position,viewport);local shellStartSize=point(shell.Size,viewport)
  local stride=math.max(size.X.Offset,shellStartSize.X);local carry=not reduced and self.deckCarry or nil;self.deckCarry=nil
  self.deckStride=stride;self.deckRecords=records
  self.deckDuration=duration -- Retain the original sampler lifetime instead of racing the reduced shell.
  local native=game:GetService("TweenService")
  for index,name in ipairs(names)do if index<lo or index>hi then
   local hidden=UI[name];hidden.Visible=false;hidden:SetAttribute("AltairDeckSource",nil);hidden:SetAttribute("AltairDeckActive",nil);hidden:SetAttribute("AltairSharedSwitch",false)
  end end
  for index=math.max(1,lo),math.min(#names,hi)do
   local panel=UI[names[index]];altairValues.panelBehindBar(panel,false)
   local previous=carry and carry[panel]
   local anchor=Vector2.new(panel.AnchorPoint.X,panel.AnchorPoint.Y)
   local record={panel=panel,index=index,objects={},previous=previous}
   if previous then record.parentCorrection=previous.position-shellStart-shellStartSize*factor*anchor end
   records[#records+1]=record
   panel:SetAttribute("AltairSharedSwitch",true);panel:SetAttribute("AltairDeckActive",true);panel:SetAttribute("AltairDeckSource",panel~=target)
   panel.ClipsDescendants=true;panel.Visible=true;panel.BackgroundTransparency=1
   native:Create(panel,TweenInfo.new(0),{Position=panel.Position,Size=panel.Size,BackgroundTransparency=1}):Play()
   local border=panel:FindFirstChildOfClass("UIStroke");if border then border.Transparency=1 end
   shell.ZIndex=math.min(shell.ZIndex,panel.ZIndex-1)
   for _,object in ipairs(panel:GetChildren())do
    if object:IsA("GuiObject")and object.Name~="Shadow"and object.Name~="Pointer"and object.Name~="AltairMorphIcon"then
     if altairValues.interfaceBindings.StopSlide then altairValues.interfaceBindings.StopSlide(object)end
     local rest=object:GetAttribute("AltairContentRestPosition")or object:GetAttribute("AltairHeadingRest")or object:GetAttribute("AltairDeckRest")or object.Position
     local item={object=object,rest=rest}
     if previous and previous.objects[object]then
      item.correction=previous.objects[object]-point(rest,previous.size)-Vector2.new((index-from)*stride,0)
     end
     object:SetAttribute("AltairDeckRest",rest);record.objects[#record.objects+1]=item
     if object:IsA("CanvasGroup")then native:Create(object,TweenInfo.new(0),{GroupTransparency=0}):Play()end
     if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then object.TextTransparency=object.Name:find("Subtitle")and .2 or 0 end
     if object:IsA("ImageLabel")or object:IsA("ImageButton")then object.ImageTransparency=0 end
    end
   end
  end
  local generation=self.generation;local progress=Instance.new("NumberValue")
  local function draw(value)
   local bounded=math.clamp(value,0,1)+(value<0 and value*.15 or value>1 and(value-1)*.15 or 0)
   local index=from+(to-from)*bounded;self.deckProgress=index
   local dimensions=UI.AbsoluteSize;local shellPosition=point(shell.Position,dimensions);local shellSize=point(shell.Size,dimensions)
   for _,record in ipairs(records)do local panel=record.panel
    local logical=record.previous and record.previous.size:Lerp(shellSize,bounded)or shellSize
    local anchor=Vector2.new(panel.AnchorPoint.X,panel.AnchorPoint.Y)
    local position=shellPosition+shellSize*factor*anchor
    if record.parentCorrection then position+=record.parentCorrection*(1-bounded)end
    panel.Size=fractional(logical,dimensions);panel.Position=fractional(position,dimensions)
    for _,item in ipairs(record.objects)do if item.object.Parent then
     local position=point(item.rest,logical)+Vector2.new((record.index-index)*stride,0)
     if item.correction then position+=item.correction*(1-bounded)end
     item.object.Position=fractional(position,logical)
    end end
   end
  end
  draw(0)
  -- Sample the shell and deck together. A separate Changed callback could leave
  -- the clipped content one native tween step behind its shell on interruption.
  local connection=runService.RenderStepped:Connect(function()draw(progress.Value)end);self.deckConnection=connection
  local animation=native:Create(progress,TweenInfo.new(self.deckDuration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Value=1});self.deckTween=animation
  animation.Completed:Once(function(state)
   connection:Disconnect();if self.deckConnection==connection then self.deckConnection=nil end;progress:Destroy()
   if state==Enum.PlaybackState.Completed and generation==self.generation then
    draw(1);self.deckTween=nil;self.deckProgress=nil;self:stopDeck(target)
   end
  end);animation:Play()
 end
 function controller:cancel(panel)
  if self.target~=panel and not(self.pending and self.source==panel)then return end
  self.pending=false;self.generation+=1;self:stopDeck(panel,self.deckRecords~=nil);self.deckProgress=nil;shell.Visible=false;panel:SetAttribute("AltairSharedSwitch",false)
  panel.BackgroundTransparency=altairValues.surfaceTransparency(panel)
  self.target=nil
 end
 function controller:prepare(name)
  local target=UI:FindFirstChild(name);local source
  if self.materialTween then self.materialTween:Cancel();self.materialTween=nil end
  local resuming=target and self.fadingDecks[target]
  if target then self.fadingDecks[target]=nil;target:SetAttribute("AltairResumingDeck",nil)end
  if self.target and self.target.Name~=name and self.target.Visible and not self.target:GetAttribute("AltairClosing")then source=self.target end
  if not source then for _,other in ipairs(names)do local candidate=UI:FindFirstChild(other);if other~=name and candidate and candidate.Visible and not candidate:GetAttribute("AltairClosing")then source=candidate;break end end end
  self.freshEntry=source==nil
  if not source then
   if resuming and target.Visible and target:GetAttribute("AltairClosing")then
    target:SetAttribute("AltairResumingDeck",true)
    for _,item in ipairs(resuming.objects)do if item.object.Parent then
     tweenService:Create(item.object,TweenInfo.new(.18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=item.rest}):Play()
    end end
   end
   self.generation+=1;self:stopDeck(nil);self.deckProgress=nil;self.deckStart=nil;self.target=nil;shell.Visible=false;return false
  end
  self.deckStart=self.deckProgress
  -- Preserve the rendered clip rectangles and child transforms before stopDeck
  -- restores their authored layout. Retargeting must not change a visible frame.
  local carry
  if self.deckRecords then
   carry={};local viewport=UI.AbsoluteSize
   for _,record in ipairs(self.deckRecords)do local panel=record.panel
    if panel.Parent then
     local previous={position=point(panel.Position,viewport),size=point(panel.Size,viewport),objects={}}
     for _,item in ipairs(record.objects)do if item.object.Parent then previous.objects[item.object]=point(item.object.Position,previous.size)end end
     carry[panel]=previous
    end
   end
  end
  self:stopDeck(source);self.deckCarry=carry
  self.generation+=1;local generation=self.generation;self.pending=true;self.source=source
  local factor=UI:GetAttribute("AltairDisplayScale") or 1
  if not shell.Visible then
   local origin=source.AbsolutePosition-UI.AbsolutePosition
   shell.Position=UDim2.fromOffset(origin.X,origin.Y);shell.Size=UDim2.fromOffset(source.AbsoluteSize.X/factor,source.AbsoluteSize.Y/factor)
   shell.BackgroundColor3=source.BackgroundColor3;shell.BackgroundTransparency=source.BackgroundTransparency;shell.ZIndex=source.ZIndex
   local gradient=source:FindFirstChildOfClass("UIGradient");shell.Material.Enabled=gradient~=nil
   if gradient then shell.Material.Color=gradient.Color;shell.Material.Rotation=gradient.Rotation;shell.Material.Offset=gradient.Offset end
   local corner=source:FindFirstChildOfClass("UICorner");if corner then shell.UICorner.CornerRadius=corner.CornerRadius end
   local stroke=source:FindFirstChildOfClass("UIStroke");if stroke then shell.Outline.Color=stroke.Color;shell.Outline.Transparency=stroke.Transparency end
  end
  shell.AltairDisplayScale.Scale=factor;shell.Visible=true
  if source then
   source:SetAttribute("AltairMotionVersion",(source:GetAttribute("AltairMotionVersion")or 0)+1)
   source:SetAttribute("AltairDeckSource",true);source.BackgroundTransparency=1
   local stroke=source:FindFirstChildOfClass("UIStroke");if stroke then stroke.Transparency=1 end
  end
  if generation~=self.generation then return "cancelled"end
  self.pending=false
  if not smartBarOpen then shell.Visible=false;self.target=nil;return "cancelled"end
  for _,other in ipairs(names)do local panel=UI:FindFirstChild(other);if panel and panel~=source then panel.Visible=false;panel:SetAttribute("AltairSharedSwitch",false)end end
  altairValues.panelBehindBar(target,false)
  shell.ZIndex=math.min(shell.ZIndex,target.ZIndex-1)
  local direction=1;for i,n in ipairs(names)do if source and n==source.Name then self.sourceIndex=i end;if n==name then self.targetIndex=i end end
  if(self.targetIndex or 1)<(self.sourceIndex or 1)then direction=-1 end
  target:SetAttribute("AltairSlideDirection",direction)
  target:SetAttribute("AltairSharedSwitch",true);target:SetAttribute("AltairClosing",true)
  target.Size=shell.Size
  local physical=Vector2.new(shell.Size.X.Offset,shell.Size.Y.Offset)*factor
  target.Position=UDim2.fromOffset(shell.Position.X.Offset+physical.X*target.AnchorPoint.X,shell.Position.Y.Offset+physical.Y*target.AnchorPoint.Y)
  target.BackgroundTransparency=1;target.Visible=true;self.target=target
  local corner=target:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=shell.UICorner.CornerRadius end
  return true
 end
 function controller:animate(panel,size)
  if self.target~=panel or not panel:GetAttribute("AltairSharedSwitch") then return end
  local generation=self.generation;local factor=UI:GetAttribute("AltairDisplayScale") or 1
  local goal=altairValues.smartBarLayout:getPanelPosition(panel,size)
  local viewport=UI.AbsoluteSize
  local position=fractional(point(goal,viewport)-Vector2.new(size.X.Offset*factor*panel.AnchorPoint.X,size.Y.Offset*factor*panel.AnchorPoint.Y),viewport)
  tweenService:Create(shell,TweenInfo.new(.31,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=size,Position=position,BackgroundColor3=panel.BackgroundColor3}):Play()
  shell.BackgroundTransparency=altairValues.surfaceTransparency(panel)
  local targetGradient=panel:FindFirstChildOfClass("UIGradient")
  if targetGradient then
   shell.Material.Enabled=true
   if self.materialTween then self.materialTween:Cancel()end
   local from,to=shell.Material.Color.Keypoints,targetGradient.Color.Keypoints
   local progress=Instance.new("NumberValue");local connection=progress.Changed:Connect(function(alpha)
    if generation~=self.generation then return end
    shell.Material.Color=ColorSequence.new(from[1].Value:Lerp(to[1].Value,alpha),from[#from].Value:Lerp(to[#to].Value,alpha))
   end)
   self.materialTween=tweenService:Create(progress,TweenInfo.new(.38,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Value=1})
   self.materialTween.Completed:Once(function()connection:Disconnect();progress:Destroy()end);self.materialTween:Play()
   tweenService:Create(shell.Material,TweenInfo.new(.38),{Rotation=targetGradient.Rotation,Offset=targetGradient.Offset}):Play()
  end
  local stroke=panel:FindFirstChildOfClass("UIStroke");if stroke then panel:SetAttribute("AltairSharedStroke",stroke.Transparency);stroke.Transparency=1 end
  self:scrollDeck(panel,size)
  task.delay(math.max(.42,(self.deckDuration or .34)+.04),function()
   if generation~=self.generation or not panel.Parent or panel:GetAttribute("AltairClosing") then return end
   panel:SetAttribute("AltairSharedSwitch",false);panel.BackgroundTransparency=altairValues.surfaceTransparency(panel)
   if stroke then stroke.Transparency=panel:GetAttribute("AltairSharedStroke") or .65 end
   shell.Visible=false;self.target=nil
  end)
 end
 return controller
end)()

altairValues.panelCornerMemory=setmetatable({}, {__mode="k"})
function altairValues.openPanelCorners(panel,button,interrupted)
 local corner=panel:FindFirstChildOfClass("UICorner");local origin=button:FindFirstChildOfClass("UICorner")
 if not corner then return end
 local rest=altairValues.panelCornerMemory[panel]or corner:GetAttribute("AltairStyleBase_CornerRadius")or corner.CornerRadius;altairValues.panelCornerMemory[panel]=rest
 if not interrupted and origin then corner.CornerRadius=origin.CornerRadius end
 tweenService:Create(corner,TweenInfo.new(.38),{CornerRadius=rest}):Play()
end
function altairValues.morphPanelToIcon(panel,button,size,position,version)
 altairValues.panelBehindBar(panel,true)
 local corner=panel:FindFirstChildOfClass("UICorner");local origin=button:FindFirstChildOfClass("UICorner")
 if corner and origin then
  altairValues.panelCornerMemory[panel]=altairValues.panelCornerMemory[panel]or corner:GetAttribute("AltairStyleBase_CornerRadius")or corner.CornerRadius
  tweenService:Create(corner,TweenInfo.new(.38),{CornerRadius=origin.CornerRadius}):Play()
 end
 local glyph=panel:FindFirstChild("AltairMorphIcon")
 if not glyph and button:FindFirstChild("Icon") then
  glyph=button.Icon:Clone();glyph.Name="AltairMorphIcon";glyph:SetAttribute("AltairMorphVisual",true)
  glyph.AnchorPoint=Vector2.new(.5,.5);glyph.Position=UDim2.fromScale(.5,.5)
  glyph.Size=button.Icon.Size;glyph.ZIndex=panel.ZIndex+20;glyph.Parent=panel
 end
 if glyph then glyph.Visible=false end
 -- Keep opacity separate: replacing its tween must never cancel the shell's
 -- Size/Position tween halfway through the trip to the SmartBar button.
 panel.BackgroundTransparency=math.min(.15,button.BackgroundTransparency)
 tweenService:Create(panel,TweenInfo.new(.38),{Size=size,Position=position}):Play()
 -- Keep the shell visible through the contraction, fading before it reaches the icon.
 tweenService:Create(panel,TweenInfo.new(.14),{BackgroundTransparency=1}):Play()


end

local function closePanel(panelName, openingOther)
 if not checkAltair()then return end
 local closing=UI:FindFirstChild(panelName);if closing then altairValues.sharedPanel:cancel(closing) end
	local button = smartBar.Back.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end
	if smartBarOpen and panel.Visible then altairValues.smartBarLayout:cancelDragPositionTween()end

	debounce = true
	panel:SetAttribute("AltairClosing",true)
	if panel.Name=="Character"and altairValues.characterRuler then altairValues.characterRuler:Cancel()end
	altairValues.setPanelPointerVisible(panel, button, false, .18)
    altairValues.panelBehindBar(panel,true)
	local motionVersion=(panel:GetAttribute("AltairMotionVersion") or 0)+1
	panel:SetAttribute("AltairMotionVersion",motionVersion)
	wipeTransparency(panel,1,false,true,.06)

	local panelSize = panel.Name == "Character" and characterPanelSize
		or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
		or UDim2.fromOffset(581, 246)

	local buttonSize, buttonPosition = getPanelButtonGeometry(panel, button)
	buttonSize = buttonSize or button.Size
	buttonPosition = buttonPosition or panel.Position

	if panel.Name == "Playerlist" and altairValues.playerlistUI.prepareClose then
		altairValues.playerlistUI.transitionVersion=(altairValues.playerlistUI.transitionVersion or 0)+1
		altairValues.playerlistUI.rowsOpening=false

		local subtitle = altairValues.playerlistUI.subtitle
		if subtitle and (
			subtitle:IsA("TextLabel")
			or subtitle:IsA("TextButton")
			or subtitle:IsA("TextBox")
		) then
			tweenService:Create(
				subtitle,
				TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
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
        elseif panel.Name=="Playerlist"then
         altairValues.playerlistUI.rowsOpening=false

		end

		altairValues.setPanelPointerVisible(panel, button, false, 0.2)
		tweenService:Create(panel.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
		tweenService:Create(panel.Title, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		tweenService:Create(panel.UIStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
		task.wait(0.08)
		if not checkAltair()or panel:GetAttribute("AltairMotionVersion")~=motionVersion then return end

		altairValues.morphPanelToIcon(panel,button,buttonSize,buttonPosition,motionVersion)
	end

	-- Animate interactive elements
	if openingOther then
  local exit=altairValues.smartBarExitVector or Vector2.new(0,altairValues.smartBarExitDirection or 0)
  local offset=Vector2.new(exit.X*(panel.AbsoluteSize.X+96),exit.Y*(panel.AbsoluteSize.Y+96))
		tweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
			Position = panel.Position + UDim2.fromOffset(offset.X,offset.Y),
		}):Play()
		wipeTransparency(panel, 1, true, true, 0.3)
        if panel:IsA("CanvasGroup") then tweenService:Create(panel,TweenInfo.new(.16),{GroupTransparency=1}):Play() end
	end

	task.wait(0.5)
	if not checkAltair()or panel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
	panel.Size = panelSize
	panel.Visible = false
	local glyph=panel:FindFirstChild("AltairMorphIcon");if glyph then glyph.Visible=false end
	if panel.Name=="Playerlist" and altairValues.playerlistUI.prepareClose then altairValues.playerlistUI:prepareClose() end
	if not openingOther and altairValues.smartBarLayout.activePanel == panel then
		altairValues.smartBarLayout.activePanel = nil
	end
	if not openingOther then updateBackpackLayout() end
	altairValues.smartBarLayout:sync(1 / 60, false)

	debounce = false
end

function altairValues.nextPanelRequest(name)
 if not checkAltair()then return end
 if name~="Settings"and altairValues.resetSettingsFeedback then altairValues.resetSettingsFeedback()end
 altairValues.panelRequestVersion=(altairValues.panelRequestVersion or 0)+1
 altairValues.panelRequestedName=name
 return altairValues.panelRequestVersion
end
function altairValues.ownsPanelRequest(version)
 return checkAltair()and version==altairValues.panelRequestVersion
end

local function openPanel(panelName,requestVersion)
 if not smartBarOpen or(panelName~="Settings"and not isPanel(panelName))then return end
 requestVersion=type(requestVersion)=="number"and requestVersion or altairValues.nextPanelRequest(panelName)
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 if panelName=="Settings"then return openSettings(requestVersion)end
 if scriptSearch.Visible and closeScriptSearch then
  if panelName=="Scripts"then closeScriptSearch(false)else closeScriptSearch(false,function()if altairValues.ownsPanelRequest(requestVersion)then openPanel(panelName,requestVersion)end end)end
  return
 end
 local shared=altairValues.sharedPanel:prepare(panelName);if shared=="cancelled" then return end
 local opening=UI:FindFirstChild(panelName);if opening then altairValues.panelBehindBar(opening,false) end
	if homeOpen then closeHome() end
	if settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing")and not settingsPanel:GetAttribute("AltairDeckSource")then closeSettings() end
	if not altairValues.ownsPanelRequest(requestVersion)then return end
	-- Navigation is owned by requestVersion. A global interaction debounce must
	-- not leave a prepared destination visible without completing its entrance.
	local button = smartBar.Back.Buttons:FindFirstChild(panelName)
	local panel = UI:FindFirstChild(panelName)

	if not isPanel(panelName) then
		return
	end
	if not (panel and button) then
		return
	end
	altairValues.smartBarLayout:cancelDragPositionTween()
	local glyph=panel:FindFirstChild("AltairMorphIcon");if glyph then glyph.Visible=false end
	local interrupted=panel.Visible and panel:GetAttribute("AltairClosing")
	local continuing=interrupted and not shared
	local resumeSize=interrupted and panel.Size
	local resumePosition=interrupted and panel.Position
	local resumeAlpha=interrupted and panel.BackgroundTransparency
	local resumeStroke=continuing and panel.UIStroke.Transparency

	debounce = true

	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Back.Buttons:FindFirstChild(otherPanel.Name) then
			if otherPanel.Name~=panelName and isPanel(otherPanel.Name) and otherPanel.Visible and not otherPanel:GetAttribute("AltairClosing")and not otherPanel:GetAttribute("AltairDeckSource")then
				task.spawn(closePanel, otherPanel.Name, true)
				task.wait()
			end
		end
	end
	if not altairValues.ownsPanelRequest(requestVersion)then return end
	if not smartBarOpen then debounce=false;return end
	local motionVersion=(panel:GetAttribute("AltairMotionVersion") or 0)+1
	panel:SetAttribute("AltairMotionVersion",motionVersion)

	local panelSize = panel.Name == "Character" and characterPanelSize
		or (panel.Name == "Playerlist" and (altairValues.playerlistUI.panelSize or playerlistPanel.Size))
		or UDim2.fromOffset(581, 246)

	-- Playerlist reset writes its full authored panel size. Do that first, then
	-- collapse the shell exactly like Character/Scripts before the opening tween.
	if panel.Name == "Playerlist" and altairValues.playerlistUI.reset then
		altairValues.playerlistUI.rowsOpening = true
		if not continuing then altairValues.playerlistUI:reset(true)end
	end

	local buttonSize, buttonPosition = getPanelButtonGeometry(panel, button)
	panel.Size = resumeSize or buttonSize or button.Size
	panel.Position = resumePosition or buttonPosition or panel.Position

    local content=panel:FindFirstChild("Interactions")
    if content and not panel:GetAttribute("AltairResumingDeck")and content:GetAttribute("AltairContentRestPosition")then content.Position=content:GetAttribute("AltairContentRestPosition")end
	if panel.Name=="Scripts"and altairValues.nativeCatalog then altairValues.nativeCatalog:Reset()end
	if continuing then
		panel:SetAttribute("AltairClosing",false)
		if tweenService.Freeze then
			for object,properties in pairs(altairValues.captureFadeState(panel))do if object.Parent then tweenService:Freeze(object,properties)end end
			if panel:IsA("CanvasGroup")then tweenService:Freeze(panel,{GroupTransparency=panel.GroupTransparency})end
		end
	else wipeTransparency(panel, 1, true)end

	altairValues.interfaceBindings.Surface(panel)
	if resumeAlpha then panel.BackgroundTransparency=resumeAlpha end
	if resumeStroke then panel.UIStroke.Transparency=resumeStroke end
 panel.Visible = true
    if panel:IsA("CanvasGroup") then if not continuing then panel.GroupTransparency=1 end;tweenService:Create(panel,TweenInfo.new(.18),{GroupTransparency=0}):Play() end
	panel:SetAttribute("AltairClosing",false)
	altairValues.openPanelCorners(panel,button,interrupted)
	task.delay(.12,function()
		if altairValues.ownsPanelRequest(requestVersion)and panel.Parent and panel.Visible and panel:GetAttribute("AltairMotionVersion")==motionVersion and not panel:GetAttribute("AltairClosing") then altairValues.fadePanelText(panel,true) end
	end)
	altairValues.smartBarLayout.activePanel = panel
	altairValues.bindPanelPointer(panel, button)
	altairValues.syncPanelPointer(panel, button)

	updateBackpackLayout(panel)

	tweenService:Create(panel, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { BackgroundTransparency = altairValues.surfaceTransparency(panel) }):Play()
	if not shared then
		tweenService:Create(panel, TweenInfo.new(.38, Enum.EasingStyle.Quint), {
			Size=panelSize,Position=altairValues.smartBarLayout:getPanelPosition(panel,panelSize),
		}):Play()
	end

	altairValues.sharedPanel:animate(panel,panelSize)
	task.wait(0.12)

	if not altairValues.ownsPanelRequest(requestVersion)or panel:GetAttribute("AltairMotionVersion")~=motionVersion or panel:GetAttribute("AltairClosing") then return end
    if panel:GetAttribute("AltairSharedSwitch")and not panel:GetAttribute("AltairDeckActive")then altairValues.interfaceBindings.SlideHeading(panel,panel:GetAttribute("AltairSlideDirection")or 1)end
	altairValues.setPanelPointerVisible(panel, button, true, 0.45)
	tweenService:Create(panel.Icon, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
	task.wait(0.025)
	if not altairValues.ownsPanelRequest(requestVersion)or panel:GetAttribute("AltairMotionVersion")~=motionVersion or panel:GetAttribute("AltairClosing") then return end
	tweenService:Create(panel.Title, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(panel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = 0.95 }):Play()
	task.wait(0.025)
	if not altairValues.ownsPanelRequest(requestVersion)or panel:GetAttribute("AltairMotionVersion")~=motionVersion or panel:GetAttribute("AltairClosing") then return end

	-- Animate interactive elements
	if panel.Name == "Character" then -- Character Panel Animation
		tweenService:Create(characterPanel.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = .86 }):Play()
		if altairValues.characterRuler then altairValues.characterRuler:Refresh(false)end
		tweenService:Create(characterPanel.Subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.PropertiesTitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.ActionsTitle, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		tweenService:Create(characterPanel.Interactions.HeaderDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = .9 }):Play()
		tweenService:Create(characterPanel.Interactions.ActionsDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = .9 }):Play()
		tweenService:Create(characterPanel.Interactions.PropertiesDivider, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { BackgroundTransparency = .9 }):Play()


		for _, action in ipairs(altairValues.actions) do
			local actionObject = actionButton(action)
			if actionObject then
				local quickToggle = actionObject.Parent == characterPanel.Interactions.Toggles
				if action.control=="Daylight"then altairValues.interfaceBindings.ApplyIcon(actionObject.Icon,"sun")else actionObject.Icon.Image = "rbxassetid://" .. action.images[action.enabled and 1 or 2]end
				tweenService:Create(actionObject, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { BackgroundTransparency = action.enabled and 0.02 or (quickToggle and 0.12 or 0.1) }):Play()
				tweenService:Create(actionObject.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Transparency = action.enabled and .55 or .9 }):Play()
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
					tweenService:Create(scriptButton.UIStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quint), { Transparency = .2 }):Play()
			end
		end
    elseif panel.Name=="Playerlist"then
     local content=playerlistPanel.Interactions
     if panel:GetAttribute("AltairSharedSwitch")then content.GroupTransparency=0 else tweenService:Create(content,TweenInfo.new(.18),{GroupTransparency=0}):Play()end
     altairValues.playerlistUI.rowsOpening=false
     local subtitle=altairValues.playerlistUI.subtitle
     if subtitle then tweenService:Create(subtitle,TweenInfo.new(.18),{TextTransparency=altairValues.playerlistUI.subtitleTextTransparency or .3}):Play()end
     if altairValues.playerlistUI.headerDivider then altairValues.playerlistUI:_setVisual(altairValues.playerlistUI.headerDivider,true,.18)end
    end

    if panel.Name=="Character"or panel.Name=="Scripts"or panel.Name=="Playerlist"then
     local content=panel.Interactions
     if panel:GetAttribute("AltairDeckActive")then content.GroupTransparency=0
     elseif panel:GetAttribute("AltairSharedSwitch")then
      local rest=content:GetAttribute("AltairContentRestPosition")or content.Position;content:SetAttribute("AltairContentRestPosition",rest)
      panel.ClipsDescendants=true;content.GroupTransparency=0
      altairValues.interfaceBindings.SlideContent(content,rest,panel:GetAttribute("AltairSlideDirection")or 1,panelSize.X.Offset+24)
     else tweenService:Create(content,TweenInfo.new(.28),{GroupTransparency=0}):Play()end
    end
	task.wait(0.22)
	if not altairValues.ownsPanelRequest(requestVersion)or panel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
	debounce = false
end

altairValues.smartBarLayout.onDragBegin = function(self)
 altairValues.nextPanelRequest(nil)
 if scriptSearch.Visible and closeScriptSearch then
  local session=self.dragSession
  self.activePanel=nil
  -- Finish the button return before the dock moves underneath its source card.
  self.dragReadyAt=math.max(self.dragReadyAt or 0,os.clock()+.5)
  closeScriptSearch(false,function()
   if not UI.Parent then return end
   closePanel("Scripts",true)
   if self.dragSession==session then self.dragReadyAt=0 end
  end)
  return
 end
 if settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing")then self.activePanel=nil;task.spawn(closeSettings)end
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
	if not checkAltair()then return false end
	altairValues.activity:record("Rejoin requested", "Current server")
	if not checkAltair()then return false end
	notification("Rejoining Session", "We're queueing a rejoin to this session, give us a moment.", 4400696294)
	local solo=#players:GetPlayers()<=1
	if solo then task.wait()end
	if not checkAltair()then return false end
	if solo then
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

	-- Population is the primary criterion; connection quality breaks ties.
	function controller.rank(a,b)
		if a.playing~=b.playing then return a.playing>b.playing end
		local ap,bp=a.ping or math.huge,b.ping or math.huge
		if ap~=bp then return ap<bp end
		if a.fps~=b.fps then return a.fps>b.fps end
		return a.id<b.id
	end

	function controller:collect(generation)
		local candidates, seen, cursors = {}, { [jobId] = true }, {}
		if self.previous then seen[self.previous] = true end
		local cursor
		local received = false
		-- Follow the available pages with a bounded retry budget; no background scans.
		for page = 1, 20 do
			if not checkAltair() or generation and (generation~=self.generation or not self.busy) then return {},false end
			local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100"
			if cursor then url ..= "&cursor=" .. httpService:UrlEncode(cursor) end
			local response
			for retry = 1, 3 do
				if not checkAltair() or generation and (generation~=self.generation or not self.busy) then return {},false end
				local ok, data = pcall(function() return httpService:JSONDecode(game:HttpGetAsync(url)) end)
				if not checkAltair() or generation and (generation~=self.generation or not self.busy) then return {},false end
				if ok and type(data) == "table" and type(data.data) == "table" then
					response = data
					break
				end
				if retry < 3 then task.wait(0.5 * retry) end
			end
			if not response and page == 1 then
				-- Retry the original server-list request before giving up on discovery.
				local ok, data = pcall(function()
					return httpService:JSONDecode(game:HttpGetAsync("https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"))
				end)
				if not checkAltair() or generation and (generation~=self.generation or not self.busy) then return {},false end
				if ok and type(data) == "table" and type(data.data) == "table" then response = data end
			end
			if not response then break end
			received = true
			for _, server in ipairs(response.data) do
				if type(server) == "table" and type(server.id) == "string" and server.id ~= ""
					and not seen[server.id] and positive(server.maxPlayers)
					and type(server.playing) == "number" and server.playing > 0 and server.playing < server.maxPlayers then
					seen[server.id] = true
					local candidate = { id = server.id, ping = positive(server.ping) and server.ping or nil,
						fps = positive(server.fps) and server.fps or 0, playing = server.playing, capacity=server.maxPlayers }
					table.insert(candidates,candidate)
				end
			end
			cursor = response.nextPageCursor
			if type(cursor) ~= "string" or cursor == "" or cursors[cursor] then break end
			cursors[cursor] = true
			if page < 20 then task.wait(0.25) end
		end
		table.sort(candidates,self.rank)
		return candidates, received
	end

	function controller:cancel(silent)
		local wasBusy=self.busy
		self.generation+=1
		self.busy,self.waiting,self.target=false,false,nil
		self.lastTeleportAt=os.clock()
		if wasBusy and not silent then notification("Server hop cancelled","You can try again whenever you're ready.",4370317928)end
	end
	function controller:finish(title,message)
		self:cancel(true)
		notification(title,message,4370317928)
	end
	function controller:isTeleportError(message)
		local text=string.lower(tostring(message))
		return text:find("server is full",1,true)~=nil or text:find("game is full",1,true)~=nil
			or text:find("experience is full",1,true)~=nil
			or text:find("teleport",1,true)~=nil or text:find("error code: 772",1,true)~=nil
			or (self.busy or (self.lastTeleportAt and os.clock()-self.lastTeleportAt<45))
				and (text:find("error code: 773",1,true)~=nil or text:find("error code: 771",1,true)~=nil)
	end

	function controller:tryNext(generation)
		if generation ~= self.generation or not self.busy or not checkAltair() then return end
		self.attempt += 1
		local server = self.candidates[self.attempt]
		if not server or self.attempt > 12 then
			self:finish("Server hop unavailable", "The listed servers couldn't accept the hop. You can retry or keep playing here.")
			return
		end
		self.target, self.waiting = server.id, true
		local attempt = self.attempt
		local message="Joining a populated server ("..tostring(server.playing).."/"..tostring(server.capacity).." players"
			..(server.ping and ", "..tostring(math.floor(server.ping)).." ms reported ping" or "")..")."
		notification("Teleporting", message, 4335479121)
		task.wait(1)
		if generation~=self.generation or not self.busy or self.attempt~=attempt or not checkAltair() then return end
		self.lastTeleportAt=os.clock()
		local ok = pcall(teleportService.TeleportToPlaceInstance, teleportService, placeId, server.id, localPlayer)
		if generation~=self.generation or not self.busy or self.attempt~=attempt or not checkAltair() then return end
		if not ok and self.generation==generation and self.waiting and self.attempt == attempt then
			self.waiting = false
			task.defer(function() self:tryNext(generation) end)
			return
		end
		-- Do not start a second teleport merely because departure is taking time.
		task.delay(30, function()
			if checkAltair() and self.generation == generation and self.attempt == attempt and self.waiting then
				self:finish("Server hop timed out","Roblox didn't finish the transfer. You can retry; Altair has stopped this attempt.")
			end
		end)
	end

	track(teleportService.TeleportInitFailed:Connect(function(player, _, _, failedPlace, options)
		if not checkAltair() or player ~= localPlayer or failedPlace ~= placeId or not controller.waiting then return end
		local failedId
		if options then pcall(function() failedId = options.ServerInstanceId end) end
		if failedId and failedId ~= "" and failedId ~= controller.target then return end
		controller.waiting = false
		local generation = controller.generation
		task.defer(function() controller:tryNext(generation) end)
	end))

	function controller:start()
		if not checkAltair() then return end
		if self.busy then self:cancel();return end
		self.busy = true
		self.generation += 1
		local generation=self.generation
		self.attempt = 0
		notification("Finding a server", "Finding populated joinable servers. Select Serverhop again to cancel.", 4335479121)
		local ok, candidates, received = pcall(function() return self:collect(generation) end)
		if generation~=self.generation or not self.busy or not checkAltair() then return end
		if not ok or not received or #candidates == 0 then
			self.busy = false
			notification("No suitable server", (not ok or not received)
				and "Roblox's server list is unavailable. Try again shortly."
				or "No other populated, joinable server was listed. Altair will not send you to an empty, current, or previous server.", 4370317928)
			return
		end
		self.candidates = candidates
		self:tryNext(generation)
	end
	return controller
end)()

altairValues.classifyDisconnect=function(reason)
	local text=string.lower(tostring(reason))
	if altairValues.serverHop:isTeleportError(text)then return "teleport"end
	if text:find("banned",1,true)or text:find("permanently",1,true)then return "ban"end
	if text:find("kicked",1,true)or text:find("error code: 267",1,true)then return "kick"end
	if text:find("connection",1,true)or text:find("network",1,true)or text:find("error code: 277",1,true)then return "network"end
	return "unknown"
end

-- Preserve Roblox's own error controls; this recovery card is always dismissible.
do
 local dismiss=disconnectedPrompt:FindFirstChild("Dismiss")
 assert(dismiss and dismiss:IsA("GuiButton"),"Update UI/Build.lua: recovery dismiss control is missing")
 track(dismiss.Activated:Connect(function()
  altairValues.serverHop:cancel(true)
  altairValues.dialogMotion:Close(disconnectedPrompt)
 end))
end

local function serverhop()
	if not checkAltair()then return false end
	if not altairValues.serverHop.busy then altairValues.activity:record("Server hop requested", "Searching for a server") end
	altairValues.serverHop:start()
end

local function leaveExperience()
	if not checkAltair()then return false end
	if pcall(function()
		game:Shutdown()
	end) then
		return
	end
	if not checkAltair()then return false end
	if pcall(teleportService.Teleport, teleportService, 0, localPlayer) then
		return
	end
	if not checkAltair()then return false end
	notification("Unable to leave", "Altair couldn't close the experience from here, you'll need to leave manually.", 4370317928)
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
	settingsPanel.Draggable=false -- Panels move only through the SmartBar handle.
end

moderatorDetectionPrompt.Leave.Leave.MouseButton1Click:Connect(function()
	if closeModPrompt then
		closeModPrompt()
	end
	leaveExperience()
end)

moderatorDetectionPrompt.Serverhop.MouseEnter:Connect(function()
 if not altairValues.dialogMotion:IsOpen(moderatorDetectionPrompt)or not moderatorDetectionPrompt.Serverhop.Interactable then return end
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

local function promptModerator(player,role)
 if altairValues.dialogMotion:IsOpen(moderatorDetectionPrompt)then return end
 moderatorDetectionPrompt.DisplayName.Text=player.DisplayName
 moderatorDetectionPrompt.Rank.Text=role
 moderatorDetectionPrompt.Avatar.Image="https://www.roblox.com/headshot-thumbnail/image?userId="..player.UserId.."&width=420&height=420&format=png"
 altairValues.dialogMotion:Element(moderatorDetectionPrompt.Serverhop,true)
 altairValues.dialogMotion:Element(moderatorDetectionPrompt.ServersAvailableFade,true)
 closeModPrompt=function()altairValues.dialogMotion:Close(moderatorDetectionPrompt)end
 local version=altairValues.dialogMotion:Open(moderatorDetectionPrompt)
 task.spawn(function()
  local serversAvailable=false
  local success,response=pcall(function()
   return httpService:JSONDecode(game:HttpGetAsync("https://games.roblox.com/v1/games/"..placeId.."/servers/Public?sortOrder=Asc&limit=100"))
  end)
  if success and response and response.data then
   for _,server in ipairs(response.data)do
    if type(server)=="table"and server.maxPlayers>server.playing and server.id~=jobId then serversAvailable=true;break end
   end
  end
  if not altairValues.dialogMotion:Owns(moderatorDetectionPrompt,version)then return end
  altairValues.dialogMotion:Element(moderatorDetectionPrompt.Serverhop,serversAvailable)
  altairValues.dialogMotion:Element(moderatorDetectionPrompt.ServersAvailableFade,serversAvailable)
 end)
end

altairValues.homeIsolation=altairValues.interfaceBindings.HomeIsolation(UI)
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
local homeContent=altairValues.interfaceBindings.HomeContainer(UI)
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
altairValues.homeView=altairValues.interfaceBindings.HomeSurface(homeContent)
-- Reuse the page groups for Home visibility; the small navigation group keeps
-- header controls together without adding a full-screen offscreen texture.
do
 local old=homeContent.Sidebar
 if not old:IsA("CanvasGroup")then
  local group=Instance.new("CanvasGroup")
  for _,property in ipairs({"Name","Position","Size","AnchorPoint","ZIndex","Visible","BackgroundTransparency","BackgroundColor3","BorderSizePixel"})do group[property]=old[property]end
  for key,value in pairs(old:GetAttributes())do group:SetAttribute(key,value)end
  for _,child in ipairs(old:GetChildren())do child.Parent=group end
  old:Destroy();group.Parent=homeContent
 end
end
local homeScale=Instance.new("UIScale",homeContent)
local function fitHome()
 local size=homeContainer.AbsoluteSize
 local authored=homeContent.Size;local width=math.max(1,authored.X.Offset);local height=math.max(1,authored.Y.Offset)
 homeScale.Scale=math.max(.25,math.min((UI:GetAttribute("AltairPreferredScale") or altairValues.interfaceBindings.DisplayScale(size)),(size.X-40)/width,(size.Y-160)/height))
end
fitHome()
track(homeContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHome))
track(homeContent:GetPropertyChangedSignal("Size"):Connect(fitHome))
local homeController = (function()
 local pages = homeContent:FindFirstChild('Pages')
 assert(pages and pages:FindFirstChild('Home') and pages:FindFirstChild('Friends') and pages:FindFirstChild('Games'), 'The published GUI is missing Home.Pages.Home/Friends/Games')
 local home, fp, gp = pages.Home, pages.Friends, pages.Games
 do
  local playingPanel=fp:FindFirstChild('InThisSession')
  local browser=fp:FindFirstChild('Browser')
  if playingPanel and playingPanel:IsA('GuiObject') and not homeContent:GetAttribute('AltairHomeRedesign') then
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
 local homeOpacity=1
 local pageOpacity,pageOpacityTweens=setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"})
 local nativeHomeTween=game:GetService("TweenService")
 local connections, data, metadata = {}, {history={}, saved={}}, {}
 local friends, favorites, selectedFriend, selectedGame = {}, {}, nil, nil
 local friendSelectionVersion,friendProfileVersion,friendAbout=0,0,'Loading profile...'
 local friendFilter, gameFilter, activePage = 'All', 'Recent', 'Home'
 local friendBusy, favoriteBusy, friendError, favoriteError = false, false, nil, nil
 local lastFriends, lastFavorites = -math.huge, -math.huge
 local sessionStarted = altairValues.sessionMemory.startedAt
 local renderFriends, renderGames, selectFriend, selectGame, refreshFriends, refreshFavorites, showPage, recordActivity
 local friendPaint={generation=0,pools=setmetatable({},{__mode="k"})}
 local storePath = altairValues.altairFolder .. '/home-' .. tostring(localPlayer.UserId) .. '.json'
 local model={}
 function model.id(value)
  local n=tonumber(value)
  return n and n==n and n>0 and n<9007199254740992 and n%1==0 and n or 0
 end
 function model.key(item)
  local id=model.id(item.universeId)
  return id>0 and ('u:'..id) or ('p:'..model.id(item.placeId))
 end
 function model.normalize(value)
  if type(value)~='table' then return nil end
  local place,universe,root=model.id(value.placeId),model.id(value.universeId),model.id(value.rootPlaceId)
  if place==0 and root==0 then return nil end
  local stamp=tonumber(value.lastPlayed) or 0
  return {placeId=root>0 and root or place,universeId=universe,rootPlaceId=root,
   lastPlaceId=model.id(value.lastPlaceId)>0 and model.id(value.lastPlaceId) or place,
   name=tostring(value.name or 'Experience'):sub(1,200),creator=tostring(value.creator or ''):sub(1,160),
   lastPlayed=stamp==stamp and math.clamp(stamp,0,os.time()) or 0}
 end
 function model.decode(value)
  if type(value)~='table' or type(value.history)~='table' or type(value.saved)~='table' then return nil end
  local result,seen={history={},saved={}},{ }
  for _,raw in ipairs(value.history) do
   local item=model.normalize(raw)
   if item and not seen[model.key(item)] and #result.history<100 then
    seen[model.key(item)]=true table.insert(result.history,item)
   end
  end
  for _,raw in pairs(value.saved) do
   local item=model.normalize(raw)
    if item then
    local key=model.key(item)
     if not result.saved[key] then result.saved[key]=item end
   end
  end
  return result
 end
 function model.apply(item,info)
  if type(info)~='table' or model.id(info.id)~=model.id(item.universeId) or model.id(info.rootPlaceId)==0 then return false end
  item.rootPlaceId=model.id(info.rootPlaceId) item.placeId=item.rootPlaceId
  if type(info.name)=='string' and info.name~='' then item.name=info.name:sub(1,200) end
  item.creator=type(info.creator)=='table' and tostring(info.creator.name or ''):sub(1,160) or item.creator
  return true
 end
 local function connect(signal, fn) local c=signal:Connect(fn) table.insert(connections,c) return c end
 local function action(button, fn)
  if not button or not button:IsA('GuiButton') then return end
  connect(button.Activated,function() if alive then local ok,err=pcall(fn) if not ok then if alive then notification('Home', 'Action failed: '..tostring(err), 4370336704) end end end end)
 end
 local function text(o, name, value) local v=o and o:FindFirstChild(name) if v and (v:IsA('TextLabel') or v:IsA('TextButton')) then local nextText=tostring(value or '');if v.Text~=nextText then v.Text=nextText end end end
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
 local homeNetwork={active=0,pending={},cooldowns={},hits=0}
 altairValues.homeNetwork=homeNetwork
 local function getJSON(url,canRun)
  local function active()return alive and(not canRun or canRun())end
  if not active()then return nil,'Closed' end
  local host=url:match('^https?://([^/]+)') or ''
  local deadline=os.clock()+15
  if (homeNetwork.cooldowns[host] or 0)>os.clock() then return nil,'Service rate limit; retry shortly' end
  -- An owned request must not join an earlier policy generation's response.
  local requestKey=canRun or url
  local pending=homeNetwork.pending[requestKey]
  if pending then homeNetwork.hits+=1 end
  while not pending and homeNetwork.active>=4 and active()and os.clock()<deadline do
   task.wait(.03) pending=homeNetwork.pending[requestKey]
  end
  if not active()then return nil,'Closed' end
  if os.clock()>=deadline then return nil,'Requests are busy; retry shortly' end
  if not pending then
   if (homeNetwork.cooldowns[host] or 0)>os.clock() then return nil,'Service rate limit; retry shortly' end
   pending={done=false} homeNetwork.pending[requestKey]=pending homeNetwork.active+=1
   task.spawn(function()
    local ok,result=pcall(function()
     assert(active(),'Closed')
     assert(type(originalRequest)=='function','HTTP requests are unavailable')
    -- Match the bounded transport option already used by Script Search. The
    -- caller deadline alone cannot stop a provider that ignores this option.
    local response=originalRequest({Url=url,Method='GET',Timeout=12,Headers={Accept='application/json'}})
     assert(active(),'Closed')
     assert(type(response)=='table','Invalid response')
     local status=tonumber(response.StatusCode) or 0
     if status==429 then
      local retry=15
      for key,value in pairs(type(response.Headers)=='table' and response.Headers or {}) do
       if tostring(key):lower()=='retry-after' then retry=math.clamp(tonumber(value) or 15,1,120) end
      end
      homeNetwork.cooldowns[host]=os.clock()+retry
     end
     assert(status>=200 and status<300,status==429 and 'Service rate limit; retry shortly' or ('Request failed ('..status..')'))
     assert(type(response.Body)=='string' and #response.Body<=2097152,'Response is missing or too large')
     local decoded=httpService:JSONDecode(response.Body)
     assert(type(decoded)=='table','Invalid JSON response')
     return decoded
    end)
    pending.value=ok and result or nil pending.error=not ok and tostring(result) or nil pending.done=true
    homeNetwork.pending[requestKey]=nil homeNetwork.active-=1
   end)
  end
  while not pending.done and active()and os.clock()<deadline do task.wait(.03) end
  if not active()then return nil,'Closed' end
  if not pending.done then return nil,'Request timed out' end
  return pending.value,pending.error
 end

 data.serverRegion=(function()
  local function providedRegion()
   for _,source in ipairs({game,workspace})do
    local region=source:GetAttribute('ServerRegion')
    if type(region)=='string'and region~=''then return region end
   end
   return nil
  end
  local state={
   value=providedRegion()or'Not available',
   busy=false,
   generation=0,
   enabled=false,
   peer=nil,
   networkClient=getService('NetworkClient'),
   hiddenProperty=typeof(gethiddenproperty)=='function' and gethiddenproperty or nil,
   properties=typeof(getproperties)=='function' and getproperties or nil,
   hiddenProperties=typeof(gethiddenproperties)=='function' and gethiddenproperties or nil
  }

  local function validPublicIPv4(ip)
   if type(ip)~='string'or #ip>15 then return nil end
   local a,b,c,d=ip:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
   a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
   if not a or not b or not c or not d or a>255 or b>255 or c>255 or d>255 then return nil end
   local canonical=string.format('%d.%d.%d.%d',a,b,c,d)
   if ip~=canonical then return nil end -- No substring, endpoint, or octal-looking interpretation.
   -- A conservative game-server lookup allow path, not an IANA reachability
   -- oracle. Never disclose private, shared, test, multicast or reserved IPs.
   if a==0 or a==10 or a==127 or a>=224 or(a==100 and b>=64 and b<=127)
    or(a==169 and b==254)or(a==172 and b>=16 and b<=31)or(a==192 and b==168)
    or(a==192 and b==0 and((c==0 and d~=9 and d~=10)or c==2))or(a==192 and b==88 and c==99)
    or(a==198 and(b==18 or b==19))or(a==198 and b==51 and c==100)
    or(a==203 and b==0 and c==113)then return nil end
   return canonical
  end

  local function ipFromValue(value)
   local kind=typeof(value)
   if kind=='string' or kind=='number' then
    local text=tostring(value)
    local ip=validPublicIPv4(text)
    if ip then return ip end
    -- Explicit endpoint fields may include a decimal port. Do not recover an
    -- IP from arbitrary prose, URLs, paths or an ambiguous authority string.
    local address,port=text:match('^(%d+%.%d+%.%d+%.%d+):(%d+)$')
    local number=tonumber(port)
    if not number or number<1 or number>65535 or tostring(number)~=port then return nil end
    return validPublicIPv4(address)
   end
   if kind=='table' then
    for _,key in ipairs({'Value','value','Address','address','Peer','peer','Endpoint','endpoint','MachineAddress','RemoteAddress','ServerAddress'}) do
     local ip=ipFromValue(value[key])
     if ip then return ip end
    end
   end
   return nil
  end

  local function readProperty(object,name,canRun)
   if not canRun()then return nil end
   local ok,value=pcall(function() return object[name] end)
   if not canRun()then return nil end
   if ok then
    local ip=ipFromValue(value)
    if ip then return ip end
   end
   if state.hiddenProperty then
    local hiddenOk,hiddenValue=pcall(state.hiddenProperty,object,name)
    if not canRun()then return nil end
    if hiddenOk then
     local ip=ipFromValue(hiddenValue)
     if ip then return ip end
    end
   end
   return nil
  end

  local function scanProperties(object,canRun)
   if not object or not canRun()then return nil end
   for _,name in ipairs({'MachineAddress','RemoteAddress','ServerAddress','PeerAddress','Address','Endpoint','Peer'}) do
    if not canRun()then return nil end
    local ip=readProperty(object,name,canRun)
    if ip then return ip end
   end
   for _,provider in ipairs({state.properties,state.hiddenProperties}) do
    if not canRun()then return nil end
    if provider then
     local ok,properties=pcall(provider,object)
     if not canRun()then return nil end
     if ok and type(properties)=='table' then
      for key,value in pairs(properties) do
       if not canRun()then return nil end
       local ip=ipFromValue(value)
       if ip then return ip end
       if type(key)=='string' then
        ip=readProperty(object,key,canRun)
        if ip then return ip end
       end
       if type(value)=='string' and value:match('^[%a_][%w_]*$') then
        ip=readProperty(object,value,canRun)
        if ip then return ip end
       end
      end
     end
    end
   end
   return nil
  end

  local function findServerIPv4(canRun)
   if not canRun()then return nil end
   local ip=ipFromValue(game:GetAttribute('ServerIP')) or ipFromValue(workspace:GetAttribute('ServerIP')) or ipFromValue(state.peer)
   if ip then return ip end

   ip=scanProperties(state.networkClient,canRun)
   if ip then return ip end

   if not canRun()then return nil end
   local ok,children=pcall(function() return state.networkClient:GetChildren() end)
   if not canRun()then return nil end
   if ok then
    for _,object in ipairs(children) do
     if not canRun()then return nil end
     if object:IsA('ClientReplicator') or object:IsA('NetworkReplicator') then
      ip=scanProperties(object,canRun)
      if ip then return ip end
     end
    end
   end

   local network=statsService:FindFirstChild('Network')
   if not canRun()then return nil end
   if network then
    for _,item in ipairs(network:GetDescendants()) do
     if not canRun()then return nil end
     local valueOk,value=pcall(function()
      if item.GetValueString then return item:GetValueString() end
     end)
     if not canRun()then return nil end
     if valueOk then
      ip=ipFromValue(value)
      if ip then return ip end
     end
    end
   end

   return nil
  end

  local function lookupServerRegion(ip,canRun)
   if not canRun()then return nil,'Closed' end
   local result,err=getJSON('https://ipapi.co/'..httpService:UrlEncode(ip)..'/json/',canRun)
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

  local function paint(value)
   state.value=value
   text(home.Server.Region,'Value',value~=''and value or'Searching...')
  end
  local function invalidate()
   state.generation+=1;state.busy=false;state.peer=nil
   homeContainer:SetAttribute('ResolvedServerIP',nil)
  end
  function state.policyChanged(enabled)
   if not alive or not altairValues.lifecycle.alive then return end
   -- Run synchronously when the option changes: even OFF -> ON must retire
   -- every request started by the previous enabled generation.
   invalidate();state.enabled=enabled==true
   paint(providedRegion()or(state.enabled and''or'Not available'))
   if state.enabled then state.refresh(true)end
  end
  function state.refresh(force)
   if not alive or not altairValues.lifecycle.alive then return end
   local enabled=settingValue('Server Region Lookup',false)==true
   if enabled~=state.enabled then state.policyChanged(enabled);return end
   local provided=providedRegion()
   if provided then
    if state.busy then invalidate()end
    state.peer=nil;homeContainer:SetAttribute('ResolvedServerIP',nil)
    paint(provided);return
   end
   if not enabled then
    state.peer=nil;homeContainer:SetAttribute('ResolvedServerIP',nil)
    paint('Not available');return
   end
   if state.busy or(state.value~=''and not force)then return end
   state.generation+=1;local generation=state.generation
   state.busy=true;paint('')
   local function current()
    return alive and altairValues.lifecycle.alive and state.enabled
     and settingValue('Server Region Lookup',false)==true and state.generation==generation
   end
   task.spawn(function()
    if not current()then return end
    local ip=findServerIPv4(current)
    if not current()then return end
    if not ip then state.busy=false;paint('Not available');return end
    local region=lookupServerRegion(ip,current)
    if not current()then return end
    state.busy=false;paint(region or'Not available')
    if region then homeContainer:SetAttribute('ResolvedServerIP',ip)end
   end)
  end
  function state.connectionAccepted(peer)
   if not alive then return end
   invalidate();state.enabled=settingValue('Server Region Lookup',false)==true
   local provided=providedRegion()
   paint(provided or(state.enabled and''or'Not available'))
   if state.enabled and not provided then state.peer=tostring(peer or'')end
   state.refresh(true)
  end
  function state.cancel()
   invalidate();state.value='Not available'
  end

  altairValues.serverRegion=state
  return state
 end)()

 local homeStore={status='Session only',key='Altair.Home.v2.'..tostring(localPlayer.UserId)}
 altairValues.homeStore=homeStore
 function homeStore:read(path)
  if type(readfile)~='function' then return nil end
  local ok,raw=pcall(readfile,path)
  if not ok or type(raw)~='string' or #raw>1048576 then return nil end
  local decoded,value=pcall(httpService.JSONDecode,httpService,raw)
  if decoded and model.decode(value) then return value,raw end
 end
 function homeStore:load()
  local value,raw=self:read(storePath)
  if not value then value,raw=self:read(storePath..'.backup') self.recovered=value~=nil end
  self.lastGood=raw
  local ok,memory=pcall(teleportService.GetTeleportSetting,teleportService,self.key)
  if ok and type(memory)=='string' and #memory<=1048576 then
   local parsed,snapshot=pcall(httpService.JSONDecode,httpService,memory)
   if parsed and model.decode(snapshot) and (not value or (tonumber(snapshot.savedAt) or 0)>=(tonumber(value.savedAt) or 0)) then value=snapshot end
  end
  self.status=self.recovered and 'Recovered backup' or value and 'Loaded' or 'New history'
  return value and model.decode(value)
 end
 function homeStore:write(encoded)
  if not alive then return false end
  pcall(teleportService.SetTeleportSetting,teleportService,self.key,encoded)
  if type(writefile)~='function' or type(readfile)~='function' then self.status='Session only' return false end
  if self.writing then self.pending=encoded return false end
  self.writing=true
  local ok,err=pcall(function()
   checkFolder()
   local backup=self.lastGood or encoded
   writefile(storePath..'.backup',backup)
   assert(readfile(storePath..'.backup')==backup,'Backup verification failed')
   writefile(storePath,encoded)
   assert(readfile(storePath)==encoded,'History verification failed')
  end)
  if self.pending then
   task.defer(function() local pending=self.pending self.pending=nil self.writing=false self:write(pending) end)
  else self.writing=false end
  if ok then self.lastGood=encoded self.status='Saved' self.recovered=false return true end
  self.status='Save failed; session copy retained'
  if not self.warnedAt or os.clock()-self.warnedAt>=30 then
   self.warnedAt=os.clock()
   if alive then notification('Home','History could not be saved to disk. Its session copy and recovery backup are retained.',4370336704) end
  end
  return false
 end
 local function save()
  local ok,encoded=pcall(httpService.JSONEncode,httpService,{version=2,savedAt=os.time(),history=data.history,saved=data.saved})
  if not ok or #encoded>1048576 then return false end
  return homeStore:write(encoded)
 end
 do
  local loaded=homeStore:load()
  if loaded then data.history=loaded.history data.saved=loaded.saved end
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
 local function revealHomeRow(entry,animated)
  local objects={entry};for _,object in ipairs(entry:GetDescendants())do objects[#objects+1]=object end
  for _,object in ipairs(objects)do
   local properties=altairValues.transparencyProperties[object.ClassName]
   if properties then
    local goal={}
    for _,property in ipairs(properties)do
     local target=object:GetAttribute('AltairHomeFade_'..property)
     if target==nil then target=object[property];object:SetAttribute('AltairHomeFade_'..property,target)end
     if animated and target~=1 then object[property]=1;goal[property]=target elseif object[property]~=target then object[property]=target end
    end
    if next(goal)then tweenService:Create(object,TweenInfo.new(.18,Enum.EasingStyle.Quint),goal):Play()end
   end
  end
  entry.Visible=true
 end

 local function friendRowControls(v)
  if not v or not v:IsA('GuiObject') then return end
  if v:GetAttribute('AltairFriendTile')then
   local hit=v:FindFirstChild('Interact');if hit then hit.Size=UDim2.fromScale(1,1);hit.ZIndex=25 end
   if v:FindFirstChild('Join')then v.Join.AnchorPoint=Vector2.zero;v.Join.Position=UDim2.fromOffset(12,94);v.Join.Size=UDim2.fromOffset(90,24);v.Join.ZIndex=27 end
   if v:FindFirstChild('More')then v.More.AnchorPoint=Vector2.new(1,0);v.More.Position=UDim2.new(1,-12,0,94);v.More.Size=UDim2.fromOffset(78,24);v.More.ZIndex=27 end
   return
  end

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
 local function copy(value)
  if not alive or not checkAltair()then return end
  if originalSetClipboard then
   originalSetClipboard(value)
   if alive and checkAltair()then notification('Home', 'Copied to clipboard.', 4370336704)end
  else notification('Home', 'Clipboard is unavailable.', 4370336704)end
 end
 local menu=Instance.new("CanvasGroup")
 menu.Name="HomeActionMenu";menu.Visible=false;menu.Size=UDim2.fromOffset(280,146)
 menu.AnchorPoint=Vector2.new(.5,.5);menu.Position=UDim2.fromScale(.5,.5)
 menu.BackgroundTransparency=1;menu.BorderSizePixel=0;menu.ZIndex=90;menu.Parent=homeContent
 menu:SetAttribute("AltairDesignRole","surface");menu:SetAttribute("AltairDesignManaged",true)
 menu:SetAttribute("AltairDesignTransparencyOffset",.04)
 menu:SetAttribute("AltairDialogManaged",true);menu:SetAttribute("AltairDialogSize",menu.Size);menu:SetAttribute("AltairDialogPosition",menu.Position)
 Instance.new("UICorner",menu).CornerRadius=UDim.new(0,16)
 local backdrop=Instance.new("Frame");backdrop.Name="Backdrop";backdrop.Size=UDim2.fromScale(1,1)
 backdrop.BackgroundColor3=Color3.fromRGB(14,14,16);backdrop.BackgroundTransparency=.14;backdrop.BorderSizePixel=0;backdrop.ZIndex=90;backdrop.Parent=menu
 backdrop:SetAttribute("AltairDesignRole","surface");backdrop:SetAttribute("AltairDesignManaged",true)
 Instance.new("UICorner",backdrop).CornerRadius=UDim.new(0,16)
 local edge=Instance.new("UIStroke");edge.Color=Color3.fromRGB(148,157,176);edge.Thickness=.6;edge.Transparency=.9
 edge.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;edge.BorderStrokePosition=Enum.BorderStrokePosition.Inner;edge.Parent=backdrop
 local menuButtons={}
 for index=1,3 do
  local button=Instance.new("TextButton");button.Name="Action"..index
  button.Position=UDim2.fromOffset(10,10+(index-1)*43);button.Size=UDim2.new(1,-20,0,37)
  button.BackgroundColor3=Color3.fromRGB(28,28,30);button.BackgroundTransparency=.12
  button.BorderSizePixel=0;button.AutoButtonColor=false
  button.TextColor3=Color3.fromRGB(242,244,249);button.TextSize=14
  button.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium)
  button.ZIndex=91;button.Parent=menu
  button:SetAttribute("AltairDesignRole","control");button:SetAttribute("AltairDesignManaged",true)
  Instance.new("UICorner",button).CornerRadius=UDim.new(0,10)
  local feedback=Instance.new("UIScale");feedback.Name="DialogFeedback";feedback.Parent=button
  menuButtons[index]=button
 end
 local menuActions={}
 for i,b in ipairs(menuButtons)do action(b,function()altairValues.dialogMotion:Close(menu);if menuActions[i]then menuActions[i]()end end)end
 local function moreFriend(f)
  if not f then return end
  menuButtons[1].Text='Copy profile link' menuButtons[2].Text='Copy username' menuButtons[3].Text='Close'
  menuActions={function() copy(profileURL(f.id)) end,function() copy(f.username) end,function() end};altairValues.dialogMotion:Open(menu)
 end
 local function inspect(id)
  task.spawn(function()
   if not alive or not checkAltair()then return end
   local ok=pcall(function() guiService:InspectPlayerFromUserId(id) end)
   if not ok then copy(profileURL(id)) end
  end)
 end
 local resolveRoot
 local joining=false
 local function playGame(item,job,ownsRequest)
  local function current()return alive and checkAltair()and(not ownsRequest or ownsRequest())end
  if not current()then return end
  if not item or not tonumber(item.placeId) or item.placeId<=0 then notification('Home', 'This experience is unavailable to join.', 4370336704) return end
   local instanceJoin=type(job)=='string'and job~=''
  if joining then return end
  joining=true
  task.spawn(function()
   if not current()then joining=false return end
    local target,resolveError
    if instanceJoin then target=model.id(item.placeId)else target,resolveError=resolveRoot(item)end
   if not current()then joining=false return end
    if model.id(target)==0 then joining=false notification('Home',resolveError or 'The experience start place could not be verified. No teleport was attempted.',4370336704) return end
    if not instanceJoin and target==game.PlaceId then
     joining=false
     if not originalSetClipboard then notification('Unable to copy join script','Clipboard support is unavailable.',4335479658) return end
     local joinScript=string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, %q)',game.PlaceId,game.JobId)
     local ok=pcall(originalSetClipboard,joinScript)
     if not current()then return end
     notification(ok and 'Copied Join Script' or 'Unable to copy join script',ok and 'Copied a join script for your current server.' or 'The clipboard operation failed.',ok and 4335479121 or 4335479658)
     return
    end
   recordActivity('Joining experience',item.name or 'Experience')
   if not current()then joining=false return end
   local ok,err=pcall(function()
     if instanceJoin then teleportService:TeleportToPlaceInstance(target,job,localPlayer)
    else teleportService:Teleport(target,localPlayer) end
   end)
   joining=false
   if not ok and current()then notification('Home','Could not join: '..tostring(err),4370336704) end
  end)
 end
 local friendActivity={roster=nil,rosterAt=0,version=0,placeCache={},refreshError=nil,byId={}}
 function friendActivity.current(f,version)
  return alive and checkAltair()and type(f)=='table'and friendActivity.byId[f.id]==f
   and(version==nil or(f.activityVersion or 0)==version)
 end
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
   -- The online list is bounded/cached; omission is not proof of being offline.
   f.presence='Unknown'
   f.source='Roblox client (not confirmed)'
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

  -- Presence samples (including cached job IDs) are hints, not a confirmed
  -- destination. Only this action's native server lookup marks it joinable.
  f.joinable=false
  f.canAttemptJoin=f.presence=='InGame'
  return f
 end
 function friendActivity.online(ownsRequest)
  local function current()return alive and checkAltair()and(not ownsRequest or ownsRequest())end
  if not current()then return nil,'Closed'end
  local result,err=bounded(function() return localPlayer:GetFriendsOnlineAsync(200) end,8)
  if not current()then return nil,'Closed'end
  if type(result)~='table' then
   result,err=bounded(function() return localPlayer:GetFriendsOnline(200) end,8)
   if not current()then return nil,'Closed'end
  end
  if type(result)~='table' then return nil,err or 'Invalid online-friends response' end
  local indexed={}
  for _,value in pairs(result) do if type(value)=='table' then
   local id=tonumber(value.VisitorId or value.UserId or value.Id)
   if id then indexed[id]=value end
  end end
  return indexed
 end
 function friendActivity.resolvePlaceInstance(userId,ownsRequest)
  local function current()return alive and checkAltair()and(not ownsRequest or ownsRequest())end
  if not current()then return nil,nil,'Closed'end
  local done,result=false,nil
  local worker=task.spawn(function()
   if not current()then done=true return end
   result=table.pack(pcall(function()
    return teleportService:GetPlayerPlaceInstanceAsync(userId)
   end))
   done=true
  end)
  local deadline=os.clock()+7
  repeat task.wait(.03) until done or not current()or os.clock()>=deadline
  if not current()or not done then
   pcall(task.cancel,worker)
   return nil,nil,current()and 'Server lookup timed out' or 'Closed'
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
  if not friendActivity.current(f)or selectedFriend~=f then return end
  local d=fp.Details
  text(d.Activity,'Status',f.presence=='InGame' and 'In Game' or f.presence)
  text(d.Activity,'GameName',f.location)
  d.Activity.GameIcon.Image=gameIcon(f.universeId)
  d.Activity.GameIcon.Visible=f.presence=='InGame' and f.universeId>0
  friendActivity.joinButton(d.Activity.Join,f)
  text(d,'Availability',f.presence=='InGame' and (f.joinable and 'Join this server' or 'Server will be resolved when you join') or f.presence=='Unknown' and 'Activity unavailable' or f.presence)
 end
 function friendActivity.updateRow(f)
  if not friendActivity.current(f)then return end
  local lists={fp.Browser.List,home.Friends.List,home.NowPlaying.FriendsPlaying.List}
  if fp:FindFirstChild('InThisSession') then table.insert(lists,fp.InThisSession.List) end
  for _,list in ipairs(lists) do
   local v=list:FindFirstChild('Entry_'..f.id)
   if v then
    -- Data, comparison key and visuals belong to the same exact friend sample.
    -- Updating activity must not reveal a row excluded by the active filter.
    friendPaint.fill(friendPaint.ensure(list,f,v.LayoutOrder),f,true)
   end
  end
  local list=home.NowPlaying.FriendsPlaying.List
  if f.presence=='InGame' and ((f.universeId>0 and f.universeId==game.GameId) or (f.placeId>0 and f.placeId==game.PlaceId)) and not list:FindFirstChild('Entry_'..f.id) and friendPaint.visible and friendPaint.visible(list)then
   local count=0 for _,entry in ipairs(list:GetChildren()) do if entry:GetAttribute('RuntimeEntry')and entry.Visible then count+=1 end end
   local entry
   if friendPaint.ensure then entry=friendPaint.ensure(list,f,count+1);friendPaint.fill(entry,f)
   else entry=row(list,f.id,count+1);entry.Avatar.Image=head(f.id);action(entry.Interact,function()showPage('Friends');selectFriend(f,true)end)end
   entry:SetAttribute('UserId',f.id) entry:SetAttribute('PlaceId',f.placeId) entry:SetAttribute('UniverseId',f.universeId) entry:SetAttribute('JobId',f.jobId)
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
   table.insert(grouped[key],{value=f,version=f.activityVersion or 0,placeId=f.placeId,universeId=f.universeId})
  end end
  local nextIndex=0
  for _=1,math.min(4,#queue) do task.spawn(function()
   while alive and checkAltair()and friendActivity.version==version and friends==snapshot do
    local function current()return alive and checkAltair()and friendActivity.version==version and friends==snapshot end
    nextIndex+=1 local key=queue[nextIndex] if not key then return end
    local placeId=grouped[key][1].placeId
    local cached=friendActivity.placeCache[key]
    if not cached or os.clock()-cached.time>300 then
     cached={time=os.clock(),universeId=grouped[key][1].universeId}
     if cached.universeId==0 then
      local universe=getJSON('https://apis.roblox.com/universes/v1/places/'..placeId..'/universe')
      if not current()then return end
      cached.universeId=friendActivity.positive(universe and universe.universeId)
     end
     if cached.universeId>0 then
      local response=getJSON('https://games.roblox.com/v1/games?universeIds='..cached.universeId)
      if not current()then return end
      local info=response and response.data and response.data[1]
      cached.name=info and friendActivity.string(info.name) or ''
     end
     if placeId>0 and (not cached.name or cached.name=='') then
      local info=bounded(function() return marketplaceService:GetProductInfo(placeId) end,8)
      if not current()then return end
      cached.name=type(info)=='table' and friendActivity.string(info.Name) or ''
     end
     if cached.name~='' or cached.universeId>0 then friendActivity.placeCache[key]=cached end
    end
    if not alive or not checkAltair()or friendActivity.version~=version or friends~=snapshot then return end
    for _,entry in ipairs(grouped[key]) do
     local f=entry.value
     if friendActivity.current(f,entry.version)then
      if cached.name and cached.name~='' then f.location=cached.name elseif f.location=='Loading game...' then f.location='Game name unavailable' end
      if cached.universeId>0 then f.universeId=cached.universeId end
      friendActivity.updateRow(f)
     end
    end
   end
  end) end
 end
 refreshFriends=function(force)
  if not alive or not checkAltair()or friendBusy or (not force and os.clock()-lastFriends<35) then return end
  friendBusy=true
  lastFriends=os.clock()
  friendActivity.version+=1
  local version=friendActivity.version
  local function current()return alive and checkAltair()and friendActivity.version==version end

  if #friends==0 then state(fp.Browser,'Loading','Loading friends...') end

  task.defer(function()
   if not alive or not checkAltair()then return end
   local roster=friendActivity.roster
   local rosterError

   if not roster or os.clock()-friendActivity.rosterAt>300 then
    roster,rosterError=bounded(function()
     local result={}
     local seen={}
     local page=players:GetFriendsAsync(localPlayer.UserId)
     for _=1,100 do
      if not current()then error('Closed')end
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
    if not current()then return end

    if type(roster)~='table' then
     local result=getJSON('https://friends.roblox.com/v1/users/'..localPlayer.UserId..'/friends')
     if not current()then return end
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

   if not alive or not checkAltair()or friendActivity.version~=version then return end
   if type(roster)~='table' then
    friendBusy=false
    friendError=rosterError or 'Friends unavailable'
    renderFriends()
    return
   end

   local inServer={}
   for _,p in ipairs(players:GetPlayers()) do inServer[p.UserId]=true end

   local function publish(online,presence,onlineKnown)
    if not alive or not checkAltair()or friendActivity.version~=version then return end
    local snapshot,indexed={},{}
    for _,f in ipairs(roster) do
     local id=tonumber(f.Id)
     if id then
      local value=friendActivity.normalize(
       f,
       online and online[id],
       presence and presence[id],
       inServer[id],
       onlineKnown
      )
      table.insert(snapshot,value);indexed[id]=value
     end
    end

    local rank={InGame=1,Online=2,Offline=3,Unknown=4}
    table.sort(snapshot,function(a,b)
     if rank[a.presence]~=rank[b.presence] then return rank[a.presence]<rank[b.presence] end
     return a.displayName:lower()<b.displayName:lower()
    end)

    friends=snapshot
    friendActivity.byId=indexed
    for _,pool in pairs(friendPaint.pools)do for id,slot in pairs(pool)do
     local value=indexed[id]
     if slot.data~=value then slot.data=value;slot.key=nil end
    end end
    if selectedFriend then selectFriend(indexed[selectedFriend.id],false,true)end
    renderFriends()
    return snapshot
   end

   if #friends==0 then publish(nil,nil,false) end

   local online,onlineError=friendActivity.online()
   if not alive or not checkAltair()or friendActivity.version~=version then return end

   local presence=nil
   local webError=nil

   if not online then
    presence={}
    if originalRequest then
     for startIndex=1,#roster,100 do
      if not alive or not checkAltair()or friendActivity.version~=version then break end
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

   if not alive or not checkAltair()or friendActivity.version~=version then return end

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
  if not alive or not checkAltair()or not f or joining then return end
  f=friendActivity.byId[f.id]
  if not f or joiningFriends[f.id] then return end
  local activityVersion=f.activityVersion or 0
  local function current()return friendActivity.current(f,activityVersion)end
  joiningFriends[f.id]=true

  task.spawn(function()
   if not current()then joiningFriends[f.id]=nil return end
   if players:GetPlayerByUserId(f.id) then
    joiningFriends[f.id]=nil
    notification('Home','This friend is already in your server.',4370336704)
    return
   end

   local target=f
   local online=friendActivity.online(current)

   if not current()then
    joiningFriends[f.id]=nil
    return
   end

   if online then
    target=friendActivity.normalize(
     {Id=f.id,Username=f.username,DisplayName=f.displayName},
     online[f.id],
     nil,
     false,
     true
    )
    activityVersion+=1;f.activityVersion=activityVersion
    for key,value in pairs(target) do f[key]=value end
    target=f
    friendActivity.updateRow(f)
    renderFriends()
   end

   if target.presence=='Offline'then
    joiningFriends[f.id]=nil
    notification('Join Friend','This friend is not currently in a joinable experience.',4370336704)
    return
   end

   -- Client presence can be cached. Only the explicit server lookup may
   -- supply the destination for this Join action, never a cached job ID.
   f.jobId='';f.joinable=false
   activityVersion+=1;f.activityVersion=activityVersion
   friendActivity.updateRow(f)
   local placeId,jobId,resolveError=friendActivity.resolvePlaceInstance(f.id,current)
   joiningFriends[f.id]=nil
   if not current()then return end

   if placeId and jobId then
    activityVersion+=1;f.activityVersion=activityVersion
    if f.placeId~=placeId then f.universeId=0;f.location='Playing'end
    f.presence='InGame'
    f.placeId=placeId
    f.jobId=jobId
    f.joinable=true
    f.canAttemptJoin=true
    f.source='Roblox server lookup'
    if f.location=='' or f.location=='Playing · activity private' then f.location='Playing' end
    friendActivity.updateRow(f)
    renderFriends()
    playGame(f,jobId,current)
    return
   end

   if f.presence=='InGame' or (online and online[f.id]) then
    local followUrl='https://www.roblox.com/games/start?userId='..tostring(f.id)
    if originalSetClipboard then
     if not current()then return end
     local copied=pcall(originalSetClipboard,followUrl)
     if not current()then return end
     notification(
      'Join Friend',
      copied and 'The exact server could not be confirmed. Copied the official follow link; Roblox may still refuse the join.'
       or 'The exact server could not be confirmed and the follow link could not be copied.',
      copied and 4335479121 or 4370336704
     )
    else
     notification('Join Friend','The exact server could not be confirmed. Their join/privacy settings may prevent direct following.',4370336704)
    end
   else
    notification('Join Friend','This friend\'s activity or joinable server could not be confirmed.'..(resolveError and (' '..tostring(resolveError)) or ''),4370336704)
   end
  end)
 end
 local gameKey=model.key
 local function saved(item) return item and data.saved[gameKey(item)]~=nil end
 local function toggleSave(item)
  if not item then return end
  local key=gameKey(item)
   if not saved(item) then
     -- The limit applies to new saves. Keep valid legacy overflow on load
     -- and allow existing saves to be removed without evicting other games.
    local count=0
    for _ in pairs(data.saved) do
     count+=1
     if count>=100 then
       notification('Library full','New saves are limited to 100 games. Unsave games until your Library is below that limit before saving another.',4370336704)
      return
     end
    end
   end
  data.saved[key]=not saved(item) and model.normalize(item) or nil
  save() renderGames() if selectedGame then selectGame(selectedGame) end
  recordActivity(saved(item) and 'Saved game' or 'Removed saved game',item.name)
 end
 local function gameDetails(item)
   local id=model.id(item.universeId)
   if id>0 and metadata[id] then return metadata[id],true end
  local result=id>0 and getJSON('https://games.roblox.com/v1/games?universeIds='..id) or nil
  local info=result and result.data and result.data[1]
  local detail=table.clone(item)
  if model.apply(detail,info) then detail.description=info.description or '' else info=nil end
  local thumbnailPlace=model.id(detail.rootPlaceId)>0 and detail.rootPlaceId or detail.placeId
  if model.id(thumbnailPlace)>0 then detail.artwork='rbxthumb://type=GameThumbnail&id='..tostring(thumbnailPlace)..'&w=768&h=432'end
  if info then metadata[id]=detail end
   return detail,info~=nil
 end
 local function repairGame(item,detail)
  if not detail or model.id(detail.rootPlaceId)==0 then return false end
  local changed=item.rootPlaceId~=detail.rootPlaceId or item.name~=detail.name or item.creator~=detail.creator
  item.placeId=detail.rootPlaceId item.rootPlaceId=detail.rootPlaceId item.name=detail.name item.creator=detail.creator
  local stored=data.saved[gameKey(item)]
  if stored then stored.placeId=item.placeId stored.rootPlaceId=item.rootPlaceId stored.name=item.name stored.creator=item.creator end
  return changed
 end
 resolveRoot=function(item)
   if model.id(item.universeId)==0 then return nil,'This saved experience has no universe ID, so its start place could not be verified. No teleport was attempted.'end
   local detail,verified=gameDetails(item)
  if not alive then return nil end
   if not verified then return nil,'The experience start place could not be verified from Roblox. No teleport was attempted.'end
  if repairGame(item,detail) then save() renderGames() end
  return model.id(item.rootPlaceId)>0 and item.rootPlaceId or nil
 end
 local function selectDetails(panel,list,id)
  for _,row in ipairs(list:GetChildren()) do if row:GetAttribute('RuntimeEntry') then
   local selected=row.Name=='Entry_'..tostring(id)
   local scale=row:FindFirstChild('HomeEntryMotion')or row:FindFirstChild('SelectionScale')or Instance.new('UIScale',row);if scale.Name~='HomeEntryMotion'then scale.Name='SelectionScale'end
   tweenService:Create(scale,TweenInfo.new(.45,Enum.EasingStyle.Quint),{Scale=selected and 1.02 or 1}):Play()
   if row:FindFirstChild('UIStroke') then tweenService:Create(row.UIStroke,TweenInfo.new(.35),{Transparency=selected and .25 or .86}):Play() end
  end end
 end
 selectGame=function(item,animate)
  local changed=selectedGame~=item
  selectedGame=item if not item then altairValues.homeView:SetSelection('Games',false,homeOpen);return end
  local d=gp.Details local wasVisible=d.Visible and d.GroupTransparency<.5;altairValues.homeView:SetSelection('Games',true,homeOpen) if homeOpen and (changed or animate) then selectDetails(d,gp.Browser.List,gameKey(item)) end d:SetAttribute('SelectedUniverseId',item.universeId) d:SetAttribute('SelectedPlaceId',item.placeId)
  local resolvedDetail
  local function paint()
   local value=resolvedDetail or item
   text(d,'Title',value.name) text(d,'Creator',value.creator) text(d,'Description',resolvedDetail and (resolvedDetail.description or 'Description unavailable.')or'Loading experience details...') d.Artwork.Image=resolvedDetail and resolvedDetail.artwork or 'rbxthumb://type=GameThumbnail&id='..tostring(item.rootPlaceId or item.placeId)..'&w=768&h=432'
   label(d.Favorite,saved(item) and 'Unsave' or 'Save')
  end
  if wasVisible and changed and homeOpen then altairValues.homeView:SwapDetails(d,function()if selectedGame==item then paint()end end)else paint()end
  task.spawn(function()
   local detail=gameDetails(item)
   if not alive or selectedGame~=item then return end
   resolvedDetail=detail
   if repairGame(item,detail) then save() renderGames() end
   d:SetAttribute('SelectedPlaceId',item.placeId)
   text(d,'Title',detail.name) text(d,'Creator',detail.creator) text(d,'Description',detail.description or 'Description unavailable.') d.Artwork.Image=detail.artwork or gameIcon(detail.universeId)
  end)
 end
 selectFriend=function(f,animate,rebase)
  if not alive or not checkAltair()then return end
  if f then f=friendActivity.byId[f.id];if not f then return end end
  local changed=not selectedFriend or not f or selectedFriend.id~=f.id
  friendSelectionVersion+=1;local selectionVersion=friendSelectionVersion
  selectedFriend=f
  if changed then friendAbout='Loading profile...'end
  if not f then friendProfileVersion+=1;altairValues.homeView:SetSelection('Friends',false,homeOpen);return end
  local d=fp.Details local wasVisible=d.Visible and d.GroupTransparency<.5;altairValues.homeView:SetSelection('Friends',true,homeOpen) if homeOpen and (changed or animate) then selectDetails(d,fp.Browser.List,f.id) end d:SetAttribute('SelectedUserId',f.id)
  local function current()return friendActivity.current(f)and selectedFriend==f and friendSelectionVersion==selectionVersion end
  local function paint()
   if not current()then return end
   d.Avatar.Image=head(f.id) text(d,'DisplayName',f.displayName) text(d,'Username','@'..f.username)
   text(d.Activity,'Status',f.presence) text(d.Activity,'GameName',f.location or 'Location unavailable') d.Activity.GameIcon.Image=gameIcon(f.universeId)
   friendActivity.updateDetails(f);text(d,'About',friendAbout)
  end
  if wasVisible and changed and homeOpen then altairValues.homeView:SwapDetails(d,paint)else paint()end
  if not rebase then
   friendProfileVersion+=1;local profileVersion=friendProfileVersion;local id=f.id
   task.spawn(function()
    local info=getJSON('https://users.roblox.com/v1/users/'..id)
    -- A profile belongs to the user ID, not a particular activity snapshot.
    -- Rebase activity without adding requests or letting an older selection win.
    if profileVersion==friendProfileVersion and friendActivity.current(selectedFriend)and selectedFriend.id==id then
     friendAbout=info and(info.description~=''and info.description or'No bio provided.')or'Profile description unavailable.'
     text(d,'About',friendAbout)
    end
   end)
  end
 end
 local tabVersion=0
 local PAGE_REST_X=0
 local PAGE_REST_Y=0
 local PAGE_TRAVEL=28
 local PAGE_REST=UDim2.fromOffset(PAGE_REST_X,PAGE_REST_Y)
 local TAB_ORDER={Home=1,Games=2,Friends=3}
 local profile=homeContent.Sidebar:FindFirstChild('Profile')

 local function pageOffset(direction)
  return UDim2.fromOffset(PAGE_REST_X+(PAGE_TRAVEL*direction),PAGE_REST_Y)
 end

 local function paintPageOpacity(page)
  local phase=pageOpacity[page]
  if page.Parent then page.GroupTransparency=1-(1-homeOpacity)*(1-(phase and phase.Value or 0))end
 end
 local function pagePhase(page)
  local phase=pageOpacity[page]
  if phase then return phase end
  phase=Instance.new("NumberValue");phase.Name="PageVisibility";phase.Value=page.GroupTransparency;phase.Parent=page;pageOpacity[page]=phase
  connect(phase.Changed,function()paintPageOpacity(page)end)
  return phase
 end
 local function stopPageOpacity(page)
  local tween=pageOpacityTweens[page];if tween then tween:Cancel();pageOpacityTweens[page]=nil end
 end
 local function setPageOpacity(page,target,duration,direction)
  local phase=pagePhase(page);stopPageOpacity(page)
  if not duration or duration<=0 then phase.Value=target;paintPageOpacity(page);return end
  local time=UI:GetAttribute("AltairReduceMotion")and math.min(duration,.08)or math.min(duration,.22)
  local tween=nativeHomeTween:Create(phase,TweenInfo.new(time,Enum.EasingStyle.Quint,direction or Enum.EasingDirection.Out),{Value=target});pageOpacityTweens[page]=tween
  tween.Completed:Once(function()if pageOpacityTweens[page]==tween then pageOpacityTweens[page]=nil end end);tween:Play()
 end

 local function pageFadeState(page,visible,duration,direction)
  setPageOpacity(page,visible and 0 or 1,duration,direction)
 end

 local pagePositionTweens=setmetatable({},{__mode="k"})
 local function stopPageMotion(page)
  stopPageOpacity(page)
  local movement=pagePositionTweens[page];if movement then movement:Cancel();pagePositionTweens[page]=nil end
 end
 local function movePage(page,position,duration,complete)
  local old=pagePositionTweens[page];if old then old:Cancel()end
  local movement=nativeHomeTween:Create(page,TweenInfo.new(duration,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=position})
  pagePositionTweens[page]=movement
  movement.Completed:Once(function(state)
   if pagePositionTweens[page]~=movement then return end
   pagePositionTweens[page]=nil
   if state==Enum.PlaybackState.Completed and complete then complete()end
  end)
  movement:Play()
 end
 showPage=function(name)
  local targetPage=pages:FindFirstChild(name)
  if not targetPage or not targetPage:IsA("CanvasGroup")then return end
  if activePage==name and opened and targetPage.Visible then return end
  local previousName=activePage;local previousPage=pages:FindFirstChild(previousName)
  if previousPage==targetPage or not previousPage or not previousPage.Visible then previousPage=nil end
  local direction=(TAB_ORDER[name]or 1)>=(TAB_ORDER[previousName]or 1)and 1 or -1
  activePage=name;tabVersion+=1;local version=tabVersion
  homeContainer:SetAttribute('ActivePage',name);menu.Visible=false
  for _,page in ipairs({home,fp,gp})do
   stopPageMotion(page)
   if page~=targetPage and page~=previousPage then page.Visible=false;page.Position=PAGE_REST;setPageOpacity(page,1,0)end
  end
  for _,button in ipairs(homeContent.Sidebar:GetChildren())do
   if button:IsA('GuiButton')and pages:FindFirstChild(button.Name)then
    local selected=button.Name==name;local alpha=selected and .15 or 1
    tweenService:Create(button,TweenInfo.new(.2,Enum.EasingStyle.Quint),{BackgroundTransparency=alpha}):Play()
    button:SetAttribute('AltairHomeFade_BackgroundTransparency',alpha)
    for _,object in ipairs(button:GetDescendants())do
     if object:IsA('TextLabel')or object:IsA('TextButton')or object:IsA('TextBox')then object.FontFace=Font.new(object.FontFace.Family,selected and Enum.FontWeight.SemiBold or Enum.FontWeight.Regular,object.FontFace.Style)end
    end
   end
  end
  if not opened then
   for _,page in ipairs({home,fp,gp})do page.Visible=page==targetPage;page.Position=PAGE_REST;setPageOpacity(page,page==targetPage and 0 or 1,0)end
  else
   local alreadyVisible=targetPage.Visible
   if not alreadyVisible then targetPage.Position=pageOffset(direction);setPageOpacity(targetPage,1,0)end
   targetPage.Visible=true
   local duration=UI:GetAttribute("AltairReduceMotion")and .08 or .26
   pageFadeState(targetPage,true,duration,Enum.EasingDirection.Out)
   movePage(targetPage,PAGE_REST,duration)
   if previousPage then
    pageFadeState(previousPage,false,duration*.8,Enum.EasingDirection.Out)
    movePage(previousPage,pageOffset(-direction),duration,function()
     if alive and version==tabVersion and activePage~=previousPage.Name then previousPage.Visible=false;previousPage.Position=PAGE_REST;setPageOpacity(previousPage,1,0)end
    end)
   end
  end
  if name=='Friends'then renderFriends();refreshFriends()elseif name=='Games'then renderGames();if gameFilter=='Favorites'then refreshFavorites()end end
 end
 local function friendListVisible(list)
  if not opened then return false end
  local object=list
  while object and object~=homeContent do if object:IsA('GuiObject')and not object.Visible then return false end;object=object.Parent end
  return object==homeContent
 end
 friendPaint.visible=friendListVisible
 function friendPaint.ensure(list,f,order)
  local pool=friendPaint.pools[list];if not pool then pool={};friendPaint.pools[list]=pool end
  local slot=pool[f.id]
  if not slot or not slot.row.Parent then
   local entry=list:FindFirstChild('Entry_'..f.id)
   local fresh=entry==nil
   if fresh then entry=list.Template:Clone();entry.Name='Entry_'..f.id;entry.Visible=false;entry:SetAttribute('RuntimeEntry',true);entry:SetAttribute('IsTemplate',false);entry:SetAttribute('IsPreview',nil);entry.Parent=list end
   slot={row=entry,fresh=fresh};pool[f.id]=slot;friendRowControls(entry)
   action(entry:FindFirstChild('Interact'),function()local target=slot.data;if target then showPage('Friends');selectFriend(target,true)end end)
   action(entry:FindFirstChild('Join'),function()if slot.data then joinFriend(slot.data)end end)
   action(entry:FindFirstChild('More'),function()if slot.data then selectFriend(slot.data);moreFriend(slot.data)end end)
  end
  slot.data=f;slot.row.LayoutOrder=order;return slot.row
 end
 function friendPaint.fill(entry,f,preserveVisibility)
  if not friendActivity.current(f)then return end
  local pool=friendPaint.pools[entry.Parent];local slot=pool and pool[f.id];if not slot then return end
  if slot.row~=entry or slot.data~=f then return end
  local key=f.displayName..'\0'..f.username..'\0'..f.presence..'\0'..tostring(f.location)..'\0'..tostring(f.placeId)..'\0'..tostring(f.universeId)..'\0'..tostring(f.jobId)..'\0'..tostring(f.source)
  local fresh=slot.fresh
  if slot.key~=key then
   slot.key=key
   for name,value in pairs({UserId=f.id,PlaceId=f.placeId,UniverseId=f.universeId,JobId=f.jobId,ActivitySource=f.source})do if entry:GetAttribute(name)~=value then entry:SetAttribute(name,value)end end
   local avatar=head(f.id);if entry.Avatar.Image~=avatar then entry.Avatar.Image=avatar end
   text(entry,'DisplayName',f.displayName);text(entry,'Username','@'..f.username);text(entry,'Status',f.presence=='InGame'and'In Game'or f.presence);text(entry,'Location',f.location)
   local offline=f.presence=='Offline'or f.presence=='Unknown'
   local function opacity(object,property,target)
    local attr='AltairHomeFade_'..property;local previous=object:GetAttribute(attr);object:SetAttribute(attr,target)
    if fresh then object[property]=target elseif previous~=target then tweenService:Create(object,TweenInfo.new(.18,Enum.EasingStyle.Quint),{[property]=target}):Play()end
   end
   opacity(entry.Avatar,'ImageTransparency',offline and .45 or 0)
   for _,name in ipairs({'DisplayName','Username','Status','Location'})do local field=entry:FindFirstChild(name);if field then opacity(field,'TextTransparency',offline and .4 or 0)end end
   local status=entry:FindFirstChild('Status');if status then status.TextColor3=offline and Color3.fromRGB(145,145,154)or Color3.fromRGB(86,216,145)end
   local dot=entry:FindFirstChild('StatusDot');if dot then dot.BackgroundColor3=not offline and Color3.fromRGB(77,227,133)or Color3.fromRGB(144,154,168)end
   local gameImage=entry:FindFirstChild('GameIcon');if gameImage then local image=gameIcon(f.universeId);if gameImage.Image~=image then gameImage.Image=image end;gameImage.Visible=f.presence=='InGame'and f.universeId>0 end
   local join=entry:FindFirstChild('Join');if join then friendActivity.joinButton(join,f)end
  end
  if preserveVisibility then return end
  if fresh or not entry.Visible then revealHomeRow(entry,opened);slot.fresh=false else entry.Visible=true end
 end
 renderFriends=function()
  friendPaint.generation+=1;local generation=friendPaint.generation;local snapshot=friends;local filter=friendFilter;local query=fp.Browser.SearchBox.Text
  task.defer(function()
   if not alive or not checkAltair()or generation~=friendPaint.generation then return end
   local browser=fp.Browser;local counts={All=#snapshot,InGame=0,Online=0,Offline=0};local playing=0;local budget=os.clock()
   local function valid()return alive and checkAltair()and generation==friendPaint.generation end
   local function yieldBudget()
    if os.clock()-budget>.001 then runService.Heartbeat:Wait();budget=os.clock()end
    return valid()
   end
   for _,f in ipairs(snapshot)do
    if f.presence=='InGame'then counts.InGame+=1 end
    if f.presence=='Online'or f.presence=='InGame'then counts.Online+=1 end
    if f.presence=='Offline'then counts.Offline+=1 end
    if(f.universeId>0 and f.universeId==game.GameId)or(f.placeId>0 and f.placeId==game.PlaceId)then playing+=1 end
    if not yieldBudget()then return end
   end
   friendActivity.showPlaying(playing)
   local eligible,seen={},{}
   local lists={browser.List,home.Friends.List,home.NowPlaying.FriendsPlaying.List};if fp:FindFirstChild('InThisSession')then lists[#lists+1]=fp.InThisSession.List end
   for _,list in ipairs(lists)do eligible[list]=friendListVisible(list);seen[list]={}end
   local shown,playingOrder=0,0
   local function paint(list,f,order)
    if not eligible[list]then return end
    seen[list][f.id]=true;friendPaint.fill(friendPaint.ensure(list,f,order),f)
   end
   for index,f in ipairs(snapshot)do
    if not valid()then return end
    if index<=40 then paint(home.Friends.List,f,index)end
    if(f.universeId>0 and f.universeId==game.GameId)or(f.placeId>0 and f.placeId==game.PlaceId)then
     playingOrder+=1;paint(home.NowPlaying.FriendsPlaying.List,f,playingOrder);if fp:FindFirstChild('InThisSession')then paint(fp.InThisSession.List,f,playingOrder)end
    end
    local included=filter=='All'or f.presence==filter or(filter=='Online'and f.presence=='InGame')
    if included and(matches(f.displayName,query)or matches(f.username,query))then shown+=1;paint(browser.List,f,shown)end
    if not yieldBudget()then return end
   end
   for list,ids in pairs(seen)do if eligible[list]then
    for id,slot in pairs(friendPaint.pools[list]or{})do if not ids[id]and slot.row.Parent then slot.row.Visible=false end;if not yieldBudget()then return end end
   end end
   if not valid()then return end
   for _,button in ipairs(browser.Filters:GetChildren())do if button:IsA('GuiButton')then label(button,(button.Name=='InGame'and'In Game'or button.Name)..' ('..tostring(counts[button.Name]or 0)..')');button.BackgroundTransparency=button.Name==filter and .15 or .65 end end
   text(home.Friends,'Title',#snapshot>0 and('Friends ('..#snapshot..')')or'Friends')
   text(home.NowPlaying.FriendsPlaying,'Summary',friendError and'Friends unavailable · click to retry'or(playing..' friends playing this experience'))
   state(browser,friendBusy and #snapshot==0 and'Loading'or friendError and #snapshot==0 and'Error'or shown==0 and'Empty'or nil,friendError or(query~=''and'No matching friends.'or'No friends in this filter.'))
  end)
 end
 connect(fp:GetPropertyChangedSignal('Visible'),function()if fp.Visible and opened then renderFriends()end end)
 connect(home:GetPropertyChangedSignal('Visible'),function()if home.Visible and opened then renderFriends()end end)

 -- These three game lists belong to this Home controller. Engine ancestry
 -- does not retain their Luau references; weak keys can lose live row pools.
 local gameRows={}
 local function gameRow(list,item,order,directory)
  local pool=gameRows[list];if not pool then pool={};gameRows[list]=pool end
  local key=gameKey(item);local slot=pool[key]
  if not slot or slot.row.Parent~=list then
   local entry=row(list,key,order);slot={row=entry};pool[key]=slot
   action(entry.Interact,function()
    local current=slot.item;if not current then return end
    if directory then selectGame(current,true)else
     if gameFilter~='Recent'then gameFilter='Recent';renderGames()end
     showPage('Games');selectGame(current,true)
    end
   end)
   if directory then
    action(entry.Play,function()if slot.item then playGame(slot.item)end end)
    action(entry.Favorite,function()if slot.item then toggleSave(slot.item)end end)
   end
  end
  slot.item=item;local entry=slot.row;entry.LayoutOrder=order
  local image=gameIcon(item.universeId);if entry.Icon.Image~=image then entry.Icon.Image=image end
  text(entry,'Title',item.name)
  text(entry,'LastPlayed',directory and(gameFilter=='Recent'and age(item.lastPlayed)or saved(item)and'Saved in Altair'or'Roblox favorite')or(item.universeId==game.GameId and'Playing now'or age(item.lastPlayed)))
  if directory then text(entry,'Creator',item.creator~=''and('By '..item.creator)or'');label(entry.Favorite,saved(item)and'Saved'or'Save')end
  entry:SetAttribute('PlaceId',item.placeId);entry:SetAttribute('UniverseId',item.universeId);entry:SetAttribute('LastPlayedAt',item.lastPlayed or 0);entry:SetAttribute('IsFavorite',saved(item));entry.Visible=true
  return key
 end
 local function hideUnusedGames(list,seen)
  local pool=gameRows[list]or{}
  local owned={}
  for key,slot in pairs(pool)do
   local entry=slot.row
   if entry.Parent==list then
    owned[entry]=true
    if not seen[key]then entry.Visible=false end
   end
  end
  for _,entry in ipairs(list:GetChildren())do
   if entry:IsA('GuiObject')and entry:GetAttribute('RuntimeEntry')==true and not owned[entry]then entry:Destroy()end
  end
 end
 renderGames=function()
  local browser=gp.Browser;local query=browser.SearchBox.Text;local items={}
  if gameFilter=='Recent'then for _,v in ipairs(data.history)do items[#items+1]=v end
  else
   local seen={};for _,v in ipairs(favorites)do seen[gameKey(v)]=true;items[#items+1]=v end
   for _,v in pairs(data.saved)do if not seen[gameKey(v)]then items[#items+1]=v end end
   table.sort(items,function(a,b)return tostring(a.name)<tostring(b.name)end)
  end
  local recentLists={home.RecentlyPlayed.List};if gp:FindFirstChild('ContinuePlaying')then recentLists[#recentLists+1]=gp.ContinuePlaying.List end
  for _,list in ipairs(recentLists)do
   local seen={};for i,item in ipairs(data.history)do if i>30 then break end;seen[gameRow(list,item,i,false)]=true end;hideUnusedGames(list,seen)
  end
  local shown=0;local seen={}
  for _,item in ipairs(items)do if matches(item.name,query)or matches(item.creator,query)then shown+=1;seen[gameRow(browser.List,item,shown,true)]=true end end
  hideUnusedGames(browser.List,seen)
  for _,v in ipairs(browser.Filters:GetChildren())do if v:IsA('GuiButton')then v.BackgroundTransparency=v.Name==gameFilter and .15 or .65 end end
  label(browser.Filters.Favorites,'Favorites')
  text(browser,'Subtitle',gameFilter=='Recent'and'Experiences visited while Altair is running'or(favoriteError and'Roblox favorites unavailable · showing saved games'or'Roblox favorites and games saved in Altair'))
  local mode=gameFilter=='Favorites'and favoriteBusy and #items==0 and'Loading'or gameFilter=='Favorites'and favoriteError and #items==0 and'Error'or shown==0 and'Empty'or nil
  state(browser,mode,mode=='Error'and favoriteError or query~=''and'No matching games.'or gameFilter=='Recent'and'Your visits will appear here.'or'No favorite or saved games yet.')
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
     if id and place and not seen[id] then seen[id]=true table.insert(result,{universeId=id,placeId=place,rootPlaceId=place,name=v.name or 'Experience',creator=v.creator and v.creator.name or '',lastPlayed=0}) end
    end
    local nextCursor=response.nextPageCursor if not nextCursor or nextCursor=='' then break end
    if nextCursor==cursor then err='Repeated Roblox page cursor' break end cursor=nextCursor
   end
   if not alive then return end
   if not err then favorites=result end favoriteError=err favoriteBusy=false renderGames()
  end)
 end
 local function refreshCurrentGame()
  local previous
  for _,v in ipairs(data.history) do if v.universeId==game.GameId then previous=v break end end
  local item=previous and table.clone(previous) or {placeId=game.PlaceId,universeId=game.GameId,name=placeName or 'Current experience',creator=''}
  item.lastPlaceId=game.PlaceId item.lastPlayed=os.time()
  -- Only universe metadata can establish a launch place; a match title cannot replace it.
  local detail=gameDetails(item)
  if not alive then return end
  repairGame(item,detail)
  local key=gameKey(item)
  for i=#data.history,1,-1 do if gameKey(data.history[i])==key then table.remove(data.history,i) end end
  if item.placeId>0 then table.insert(data.history,1,item) while #data.history>100 do table.remove(data.history) end save() end
  text(home.NowPlaying,'GameName',item.name) text(home.NowPlaying,'Creator',item.creator) home.NowPlaying.GameIcon.Image=gameIcon(item.universeId) home.NowPlaying.ArtworkViewport.Artwork.Image=detail.artwork or gameIcon(item.universeId)
  home.NowPlaying:SetAttribute('PlaceId',game.PlaceId) home.NowPlaying:SetAttribute('UniverseId',item.universeId)
  text(home.SessionStatus,'Game',item.name) renderGames()
  local images={detail.artwork or ('rbxthumb://type=GameThumbnail&id='..game.PlaceId..'&w=768&h=432')}
  if altairValues.homeView then altairValues.homeView:SetArtwork(images)end
  task.spawn(function()
   local media=getJSON('https://games.roblox.com/v2/games/'..tostring(game.GameId)..'/media')
   if not alive then return end
   local seen={};for _,m in ipairs(media and media.data or {})do if m.assetType=='Image'and m.approved~=false and tonumber(m.imageId)and not seen[m.imageId]then seen[m.imageId]=true;images[#images+1]='rbxassetid://'..m.imageId end;if #images>=8 then break end end
   if altairValues.homeView then altairValues.homeView:SetArtwork(images)end
  end)

 end
 local activity=altairValues.activity.items
 recordActivity=function(title,description,icon)
  return altairValues.activity:record(title,description,icon)
 end
 local activityPaint={generation=0,rows={}}
 local function renderActivity()
  activityPaint.generation+=1;local generation=activityPaint.generation
  local panel=home:FindFirstChild('RecentActivity');if not panel or not panel.Visible then return end
  task.defer(function()
   local list=panel.List;local budget=os.clock()
   for index,item in ipairs(activity)do
    if not alive or generation~=activityPaint.generation or not panel.Visible then return end
    local entry=activityPaint.rows[index]
    local fresh=not entry or not entry.Parent
    if fresh then entry=list.Template:Clone();entry.Name='Entry_'..index;entry.Visible=false;entry.LayoutOrder=index;entry:SetAttribute('RuntimeEntry',true);entry.Parent=list;activityPaint.rows[index]=entry end
    text(entry,'Title',item.title);text(entry,'Description',item.description..' · '..age(item.time));if entry.Icon.Image~=item.icon then entry.Icon.Image=item.icon end
    if fresh then revealHomeRow(entry,opened)else entry.Visible=true end
    if os.clock()-budget>.001 then runService.Heartbeat:Wait();budget=os.clock()end
   end
   for index=#activity+1,#activityPaint.rows do local entry=activityPaint.rows[index];if entry.Parent then entry.Visible=false end end
  end)
 end
 if home:FindFirstChild('RecentActivity')then connect(home.RecentActivity:GetPropertyChangedSignal('Visible'),function()renderActivity()end)end
 local lastActivityRender,activityRevision=0,-1
 local function tick()
  if not alive or not opened then return end
  data.serverRegion.refresh(false)
  local now=os.clock()
  local playerCount=#players:GetPlayers()
  local ping=math.floor(getPing())
  text(homeContent,'HeaderTime',os.date('%I:%M'):gsub('^0',''))
  text(homeContent,'HomeFooter',tostring(playerCount)..(playerCount==1 and ' player' or ' players')..'  ·  '..ping..' ms  ·  Altair')
  text(home.SessionStatus,'Time',os.date('%I:%M %p'):gsub('^0','')) text(home.SessionStatus,'Date',os.date('%a, %b %d, %Y')) text(home.SessionStatus,'Status','In Game ●')
  text(home.Server,'PlayerCount',playerCount..' / '..players.MaxPlayers)
  text(home.Server.Ping,'Value',ping..' ms')
  local seconds=math.max(0,os.time()-sessionStarted) text(home.Server.Uptime,'Label','Session time') text(home.Server.Uptime,'Value',math.floor(seconds/3600)..'h '..math.floor(seconds/60)%60 ..'m')
  text(home.Server.Region,'Value',data.serverRegion.value~='' and data.serverRegion.value or 'Searching...')
  text(home.NowPlaying,'SessionPills','● In Game     '..playerCount..' / '..players.MaxPlayers..' Players     '..ping..' ms')
  if activityRevision~=altairValues.activity.revision or now-lastActivityRender>=5 then lastActivityRender=now activityRevision=altairValues.activity.revision renderActivity() end
  refreshFriends()
 end
 local controller={}

 local homeFadeGeneration=0
 local homeFadeTargets,homeFadeRecords,homeFadeTweens={},setmetatable({},{__mode="k"}),{}
 local homeFadeHidden,homeFadeDead=true,0
 local homeVisibility=Instance.new("NumberValue");homeVisibility.Name="HomeVisibility";homeVisibility.Value=1;homeVisibility.Parent=homeContent
 local homeVisibilityTween
 local function paintHomeVisibility()
  homeOpacity=homeVisibility.Value
  homeContent.Sidebar.GroupTransparency=homeOpacity
  for _,page in ipairs({home,fp,gp})do pagePhase(page);paintPageOpacity(page)end
 end
 connect(homeVisibility.Changed,paintHomeVisibility)
 local function groupedHomeObject(object)
  local current=object
  while current and current~=homeContent do
   if current==homeContent.Sidebar or current:GetAttribute("AltairHomePageGroup")or current:GetAttribute("AltairDialogManaged")then return true end
   current=current.Parent
  end
  return false
 end
 local function cacheHomeFade(object)
  if homeFadeRecords[object]or not object:IsDescendantOf(homeContent)or groupedHomeObject(object)then return end
  local properties=altairValues.transparencyProperties[object.ClassName];if not properties then return end
  local record={object=object,properties=properties,index=#homeFadeTargets+1};homeFadeRecords[object]=record;homeFadeTargets[record.index]=record
  for _,property in ipairs(properties)do local attr="AltairHomeFade_"..property;if object:GetAttribute(attr)==nil then object:SetAttribute(attr,object[property])end end
  if homeFadeHidden then for _,property in ipairs(properties)do if object[property]~=1 then object[property]=1;record.touched=true end end end
 end
 local function homeFadeVisible(object)
  local current=object
  while current and current~=homeContent do if current:IsA("GuiObject")and not current.Visible then return false end;current=current.Parent end
  return current==homeContent
 end
 connect(homeContent.DescendantAdded,function(object)task.defer(function()if alive and object.Parent then cacheHomeFade(object)end end)end)
 connect(homeContent.DescendantRemoving,function(object)
  local record=homeFadeRecords[object];if not record then return end
  if record.tween then record.tween:Cancel();homeFadeTweens[record.tween]=nil end
  record.dead=true;homeFadeDead+=1;homeFadeRecords[object]=nil
 end)
 local function fadeHome(hidden,duration)
  homeFadeGeneration+=1;local generation=homeFadeGeneration
  homeFadeHidden=hidden
  if homeVisibilityTween then homeVisibilityTween:Cancel();homeVisibilityTween=nil end
  if duration==0 then homeVisibility.Value=hidden and 1 or 0;paintHomeVisibility()
  else
   local time=UI:GetAttribute("AltairReduceMotion")and math.min(duration,.08)or duration
   homeVisibilityTween=nativeHomeTween:Create(homeVisibility,TweenInfo.new(time,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Value=hidden and 1 or 0});homeVisibilityTween:Play()
  end
  for animation,record in pairs(homeFadeTweens)do animation:Cancel();record.tween=nil end;table.clear(homeFadeTweens)
  if homeFadeDead>0 then local live={};for _,record in ipairs(homeFadeTargets)do if not record.dead and record.object.Parent then live[#live+1]=record;record.index=#live end end;homeFadeTargets=live;homeFadeDead=0 end
  local function apply()
   local deadline=os.clock()+.001
   for _,record in ipairs(homeFadeTargets)do
    if not alive or generation~=homeFadeGeneration then return end
    local obj=record.object;local visible=obj.Parent and homeFadeVisible(obj)
    if not record.dead and obj.Parent and(visible or not hidden and record.touched or duration==0)then
     local goals={}
     for _,property in ipairs(record.properties)do
      local attr="AltairHomeFade_"..property
      local goal=hidden and 1 or obj:GetAttribute(attr)
      if goal~=nil and obj[property]~=goal then goals[property]=goal end
     end
     record.touched=hidden
     if next(goals)then
      if duration==0 or not visible then for property,value in pairs(goals)do obj[property]=value end
      else
       local time=UI:GetAttribute("AltairReduceMotion")and math.min(duration,.08)or duration
       local animation=nativeHomeTween:Create(obj,TweenInfo.new(time,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goals);record.tween=animation;homeFadeTweens[animation]=record
       animation.Completed:Once(function()homeFadeTweens[animation]=nil;if record.tween==animation then record.tween=nil end end);animation:Play()
      end
     end
    end
    if duration>0 and os.clock()>deadline then runService.Heartbeat:Wait();deadline=os.clock()+.001 end
   end
  end
  if duration==0 then apply()else task.spawn(apply)end
 end
 function controller.fadeOut(duration)fadeHome(true,duration or .28)end
 function controller.fadeIn(duration)fadeHome(false,duration or .38)end

 function controller.setOpened(value)
  opened=value;tabVersion+=1
  for _,page in ipairs({home,fp,gp})do stopPageMotion(page)end
  if value then
   local current=pages:FindFirstChild(activePage)or home
   for _,page in ipairs({home,fp,gp})do page.Visible=page==current;page.Position=PAGE_REST;setPageOpacity(page,page==current and 0 or 1,0)end
   renderFriends();renderGames();renderActivity()
  else
   if menu.Visible then altairValues.dialogMotion:Close(menu)end
   -- Leave rendered rows intact while the containing page fades as one surface.
   friendPaint.generation+=1;activityPaint.generation+=1
  end
 end
 function controller.destroy()
  if not alive then return end
  if closeHome then closeHome(true) end alive=false
  data.serverRegion.cancel()
  if homeVisibilityTween then homeVisibilityTween:Cancel()end
  for _,page in ipairs({home,fp,gp})do stopPageMotion(page)end
  for tween in pairs(homeFadeTweens)do tween:Cancel()end
  homeBlur:Destroy()
  for _,c in ipairs(connections) do c:Disconnect() end table.clear(connections)
  table.clear(gameRows)
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
 home.NowPlaying.ArtworkViewport.Artwork.Image='' home.NowPlaying.GameIcon.Image='' text(home.NowPlaying,'GameName','Loading experience...') text(home.NowPlaying,'Creator','')
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
 action(gp.DetailsSurface.CloseSelection,function()selectGame(nil)end)
 action(fp.DetailsSurface.CloseSelection,function()selectFriend(nil)end)
 action(home.Friends.ViewAll,function() showPage('Friends') end)
 action(home.Resume,function()closeHome()end)
 action(home.BrowseLibrary,function()showPage('Games')end)
 action(home.RecentlyPlayed.ViewAll,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') end)
 action(home.NowPlaying.FriendsPlaying.ViewFriends,function() friendFilter='InGame' renderFriends() showPage('Friends') refreshFriends(true) end)
 local sessionLink=Instance.new('TextButton') sessionLink.Name='CopyServerLink' sessionLink.Text='' sessionLink.BackgroundTransparency=1 sessionLink.Size=UDim2.fromOffset(26,26) sessionLink.Position=UDim2.new(1,-40,0,10) sessionLink.Text='⋯' sessionLink.TextColor3=Color3.new(1,1,1) sessionLink.ZIndex=30 sessionLink.Parent=home.Server
 action(sessionLink,function() copy('https://www.roblox.com/games/start?placeId='..game.PlaceId..'&gameInstanceId='..httpService:UrlEncode(game.JobId)) end)
 local gameLink=Instance.new('TextButton') gameLink.Name='ViewGame' gameLink.Text='' gameLink.BackgroundTransparency=1 gameLink.Position=home.NowPlaying.GameIcon.Position gameLink.Size=home.NowPlaying.GameIcon.Size gameLink.ZIndex=30 gameLink.Parent=home.NowPlaying
 action(gameLink,function() if gameFilter~='Recent' then gameFilter='Recent' renderGames() end showPage('Games') for _,item in ipairs(data.history) do if item.universeId==game.GameId then selectGame(item) break end end end)
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
 connect(teleportService.TeleportInitFailed,function(p,_,message) if p==localPlayer then if alive then notification('Home', 'Teleport failed: '..tostring(message), 4370336704) end end end)
 pcall(function()
  connect(data.serverRegion.networkClient.ConnectionAccepted,function(peer)
   data.serverRegion.connectionAccepted(peer)
  end)
 end)
 connect(game:GetAttributeChangedSignal('ServerRegion'),function()data.serverRegion.refresh(true)end)
 connect(workspace:GetAttributeChangedSignal('ServerRegion'),function()data.serverRegion.refresh(true)end)
 data.serverRegion.refresh(true)
 connect(UI.Destroying,controller.destroy)
 do
  local budget=os.clock()
  for _,obj in ipairs(homeContent:GetDescendants()) do
   cacheHomeFade(obj)
   if os.clock()-budget>.001 then runService.Heartbeat:Wait();budget=os.clock()end
  end
  controller.fadeOut(0)
 end
 local remembered=altairValues.sessionMemory.home or {}
 if ({All=true,InGame=true,Online=true,Offline=true})[remembered.friendFilter] then friendFilter=remembered.friendFilter end
 if ({Recent=true,Favorites=true})[remembered.gameFilter] then gameFilter=remembered.gameFilter end
 altairValues.sessionMemory.captureHome=function() return {page=activePage,friendFilter=friendFilter,gameFilter=gameFilter} end
 homeContainer.Visible=false showPage(pages:FindFirstChild(tostring(remembered.page)) and remembered.page or 'Home') renderFriends() renderGames()
 task.spawn(refreshCurrentGame)
 controller.refreshCurrentGame=refreshCurrentGame
 return controller
end)()
-- Prepare Home assets and the native blur pass during initialization, not on first interaction.
task.spawn(function()
 pcall(function()game:GetService("ContentProvider"):PreloadAsync({homeContent})end)
 if not checkAltair()or homeOpen or env.__AltairHomeBlurWarmed then return end
 env.__AltairHomeBlurWarmed=true
 homeBlur.Enabled=true;homeBlur.Size=1;homeBlur.Parent=lighting
 runService.RenderStepped:Wait();runService.RenderStepped:Wait()
 if checkAltair()and not homeOpen then homeBlur.Size=0;homeBlur.Parent=nil end
end)
local function UpdateHome() homeController.tick() end
altairValues.homeFovTarget=Instance.new("NumberValue")
altairValues.homeFovTarget.Value=camera.FieldOfView
altairValues.lifecycle:own(altairValues.homeFovTarget)
local function applyHomeFov(force)
 if not altairValues.lifecycle.alive then return end
 local closingCamera=cameraState.closingCamera
 local closeVersion=cameraState.closeVersion
 local restore=altairValues.homeCameraTween
 if not homeOpen and not(closingCamera and restore and cameraState.owned[closingCamera])then return end
 local activeCamera=syncCamera()
 if not activeCamera or not cameraState.owned[activeCamera]then return end
 if not homeOpen and(activeCamera~=closingCamera or cameraState.closingCamera~=closingCamera or cameraState.closeVersion~=closeVersion or altairValues.homeCameraTween~=restore)then return end
 local target=altairValues.homeFovTarget.Value
 if force==true or math.abs(activeCamera.FieldOfView-target)>.01 then activeCamera.FieldOfView=target end
end
altairValues.homeFovBinding="AltairHomeFov-"..httpService:GenerateGUID(false)
runService:BindToRenderStep(altairValues.homeFovBinding,Enum.RenderPriority.Last.Value+1,applyHomeFov)
track(altairValues.homeFovTarget.Changed:Connect(applyHomeFov))

openHome = function(requestVersion)
 if not altairValues.lifecycle.alive then return end
 requestVersion=type(requestVersion)=="number"and requestVersion or altairValues.nextPanelRequest("Home")
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 if scriptSearch.Visible then closeScriptSearch(true,function()if altairValues.ownsPanelRequest(requestVersion)then openHome(requestVersion)end end);return end
 if homeOpen or not UI.Parent then return end
 local activeCamera=syncCamera()
 if not activeCamera then return end
 cameraState:CancelClose()
 homeContainer:SetAttribute("AltairClosing",false)
 homeFov=cameraState:Own(activeCamera)
 if not homeFov then return end
 altairValues.homeFovTarget.Value=activeCamera.FieldOfView
 homeOpen=true
 homeBlur.Enabled=true;homeBlur.Parent=lighting
 altairValues.homeIsolation:SetOpened(true)
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 for _,panel in ipairs(UI:GetChildren()) do
  if panel:IsA("GuiObject") and panel.Visible and smartBar.Back.Buttons:FindFirstChild(panel.Name) and isPanel(panel.Name) then
   task.spawn(closePanel,panel.Name,true)
  end
 end
 if settingsPanel.Visible then task.spawn(closeSettings) end
 if scriptSearch.Visible then task.spawn(closeScriptSearch,true) end
 homeController.setOpened(true)
 if not homeContainer.Visible then homeContent.Position=UDim2.new(.5,-45,.5,0) end
 homeContainer.Visible=true
 homeController.fadeIn(.38)
 tweenService:Create(homeContent,TweenInfo.new(.8,Enum.EasingStyle.Quint),{Position=UDim2.fromScale(.5,.5)}):Play()
 tweenService:Create(homeContainer.Dim,TweenInfo.new(.5),{BackgroundTransparency=.5}):Play()
 -- Home has no enclosing box; the full-screen scrim provides contrast.

 -- Retarget the live blur so a close/reopen reversal keeps its current frame.
 tweenService:Create(homeBlur,TweenInfo.new(.8,Enum.EasingStyle.Quint),{Size=20}):Play()
 altairValues.homeTargetFov=math.max(20,homeFov-35)
 tweenService:Create(altairValues.homeFovTarget,TweenInfo.new(fovMotionDuration(.8),Enum.EasingStyle.Quint),{Value=math.max(20,homeFov-35)}):Play()
 homeController.tick()
end

closeHome = function(immediate)
 if not altairValues.lifecycle.alive then return end
 if not homeOpen and not immediate then return end
 local activeCamera=syncCamera()
 homeContainer:SetAttribute("AltairClosing",true)
 homeOpen=false homeController.setOpened(false)
 altairValues.homeIsolation:SetOpened(false)
 tweenService:Create(homeContent,TweenInfo.new(immediate and 0 or .18),{BackgroundTransparency=1}):Play()
 homeController.fadeOut(immediate and 0 or .28)
 local slide=tweenService:Create(homeContent,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.new(.5,-45,.5,0)})
 tweenService:Create(homeContainer.Dim,TweenInfo.new(immediate and 0 or .3),{BackgroundTransparency=1}):Play()
 tweenService:Create(homeBlur,TweenInfo.new(immediate and 0 or .8,Enum.EasingStyle.Quint),{Size=0}):Play()
 cameraState:CancelClose()
 if activeCamera and cameraState.owned[activeCamera] then
  local closeVersion=cameraState.closeVersion
  altairValues.homeFovTarget.Value=activeCamera.FieldOfView
  local restore=tweenService:Create(altairValues.homeFovTarget,TweenInfo.new(immediate and 0 or fovMotionDuration(.8),Enum.EasingStyle.Quint),{Value=cameraState.baselines[activeCamera]})
  altairValues.homeCameraTween=restore
  cameraState.closingCamera=activeCamera
  restore.Completed:Once(function(state)
   if not altairValues.lifecycle.alive or homeOpen or altairValues.homeCameraTween~=restore or cameraState.closingCamera~=activeCamera or cameraState.closeVersion~=closeVersion then return end
   if state==Enum.PlaybackState.Completed then
    -- Commit the final sample before releasing the closing owner, even if
    -- Changed delivery or the next render callback has not run yet.
    local restored=pcall(applyHomeFov,true)
    if not altairValues.lifecycle.alive or homeOpen or altairValues.homeCameraTween~=restore or cameraState.closingCamera~=activeCamera or cameraState.closeVersion~=closeVersion then return end
    if restored then
     cameraState.owned[activeCamera]=nil;cameraState.pendingRestore[activeCamera]=nil
    else
     cameraState.pendingRestore[activeCamera]=true
    end
   end
   altairValues.homeCameraTween=nil;cameraState.closingCamera=nil
  end)
  restore:Play()
 end
 slide.Completed:Once(function(state)
  if not altairValues.lifecycle.alive then return end
  if state==Enum.PlaybackState.Completed and not homeOpen then homeContainer.Visible=false homeFov=nil
   if homeBlur.Parent then homeBlur.Parent=nil end
  end
 end)
 slide:Play()
end

-- Script Search owns one navigation generation for every pending operation.
altairValues.scriptSearchState={version=0,nav=0,phase="closed"}
function altairValues.scriptSearchState:stopSourceFade()
 for _,animation in ipairs(self.sourceFadeTweens or {})do animation:Cancel()end
 self.sourceFadeTweens={}
end
function altairValues.scriptSearchState:fadeSource(version)
 self:stopSourceFade()
 local function fade(object,properties)
  local animation=tweenService:Create(object,TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),properties)
  self.sourceFadeTweens[#self.sourceFadeTweens+1]=animation;animation:Play()
 end
 fade(scriptsPanel,{BackgroundTransparency=1})
 for object,properties in pairs(self.source.fade)do if object.Parent then
  local goal={};for property in pairs(properties)do goal[property]=1 end;fade(object,goal)
 end end
 task.delay(.14,function()if self.version==version and UI.Parent then scriptsPanel.Visible=false;self:stopSourceFade()end end)
end
function altairValues.scriptSearchState:geometry(object)
 local scale=scriptSearch:GetAttribute("AltairSurfaceScale")or UI:GetAttribute("AltairDisplayScale")or 1
 local point=object.AbsolutePosition-UI.AbsolutePosition
 return UDim2.fromOffset(point.X+object.AbsoluteSize.X/2,point.Y+object.AbsoluteSize.Y/2),UDim2.fromOffset(object.AbsoluteSize.X/scale,object.AbsoluteSize.Y/scale)
end
local function openScriptSearch()
 if not checkAltair()then return end
 local state=altairValues.scriptSearchState
 local native=altairValues.nativeCatalog
 if native and(native.opened or native.closing)then
  local version=state.version
  native:Close(true,function()
   if checkAltair()and smartBarOpen and not homeOpen and not(settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing")and not settingsPanel:GetAttribute("AltairDeckSource"))and altairValues.smartBarLayout.activePanel==scriptsPanel and not scriptsPanel:GetAttribute("AltairClosing")and state.version==version then
    scriptsPanel.Interactions.Selection.GroupTransparency=0
    openScriptSearch()
   end
  end)
  return
 end
 if state.phase=="open"or state.phase=="opening"then return end
 state.version+=1;state.nav+=1;local version=state.version;state.phase="opening";state.afterClose=nil
 state:stopSourceFade()
 if not checkAltair()then state.phase="closed";return end
 if homeOpen then closeHome()end
 local dock=altairValues.smartBarLayout
 local expectedNavigation=altairValues.sharedPanel.generation
 if not scriptsPanel.Visible or scriptsPanel:GetAttribute("AltairClosing")then
  -- Reserve this request before openPanel yields. A later navigation owns the
  -- shared panel generation, so this older request must not reopen Search.
  expectedNavigation+=1
  openPanel("Scripts")
 end
 if not checkAltair()or state.version~=version or state.phase~="opening"then return end
 if not checkAltair()or not smartBarOpen or homeOpen or not scriptsPanel.Visible or scriptsPanel:GetAttribute("AltairClosing")
  or altairValues.sharedPanel.generation~=expectedNavigation
  or(dock.activePanel and dock.activePanel~=scriptsPanel)
  or(altairValues.sharedPanel.target and altairValues.sharedPanel.target~=scriptsPanel)then
  state.phase="closed";state.nav+=1;return
 end
 local source=scriptsPanel.Interactions.Selection.Library
 altairValues.sharedPanel:cancel(scriptsPanel)
 local canonicalSize=dock:getPanelSize(scriptsPanel)
 local canonicalPosition=dock:getPanelPosition(scriptsPanel,canonicalSize)
 -- A quick library activation can arrive before the source entrance finishes.
 -- Retain its true rest geometry and stop that older entrance from moving the
 -- source underneath the button morph or writing after it has been restored.
 tweenService:Create(scriptsPanel,TweenInfo.new(0),{Size=canonicalSize,Position=canonicalPosition}):Play()
 state.source={size=canonicalSize,position=canonicalPosition,background=scriptsPanel.BackgroundTransparency,fade=altairValues.captureFadeState(scriptsPanel)}
 local position,size=state:geometry(source)
 altairValues.setPanelPointerVisible(scriptsPanel,smartBar.Back.Buttons.Scripts,false,.12)
 scriptsPanel.Interactable=false
 altairValues.panelBehindBar(scriptSearch,false)
 altairValues.discovery:Open(position,size,function()if state.version==version and UI.Parent then state.phase="open"end end,source:Clone())
 state:fadeSource(version)
 if state.mouseUnlock then state.mouseUnlock.Modal=true end
 if altairValues.discovery.LoadIdle then task.spawn(altairValues.discovery.LoadIdle)end
end
closeScriptSearch=function(dismiss,continuation,returnDuration)
 if not checkAltair()then return end
 local state=altairValues.scriptSearchState
 if state.phase=="closed"then if continuation then task.spawn(continuation)end;return end
 if state.phase=="closing"then state.afterClose=continuation;state.dismiss=dismiss;return end
 state.version+=1;state.nav+=1;local version=state.version;state.phase="closing";state.searching=nil;state.dismiss=dismiss;state.afterClose=continuation
 state:stopSourceFade()
 if state.mouseUnlock then state.mouseUnlock.Modal=false end
 local source=state.source
 scriptsPanel:SetAttribute("AltairClosing",false);scriptsPanel:SetAttribute("AltairMotionVersion",(scriptsPanel:GetAttribute("AltairMotionVersion")or 0)+1)
 altairValues.panelBehindBar(scriptsPanel,false)
 if source then
  scriptsPanel.Size=source.size;scriptsPanel.Position=source.position;scriptsPanel.BackgroundTransparency=source.background
  for object,properties in pairs(source.fade)do if object.Parent then for key,value in pairs(properties)do object[key]=value end end end
 end
 scriptsPanel.Visible=true;scriptsPanel.Interactable=false
 altairValues.setPanelPointerVisible(scriptsPanel,smartBar.Back.Buttons.Scripts,true,.14)
 local button=scriptsPanel.Interactions.Selection.Library
 local position,size=state:geometry(button)
 altairValues.discovery:Close(position,size,function()
  if state.version~=version or not checkAltair()then return end
  state.phase="closed";scriptsPanel.Interactable=true;local nextAction=state.afterClose;state.afterClose=nil
  if nextAction then task.spawn(nextAction)elseif state.dismiss then task.spawn(closePanel,"Scripts",true)end
 end,button:Clone(),returnDuration or .2)
end
-- Palette is owned by the builder theme bindings; preserve the integration hook.
altairValues.scriptSearchColours=function()end
-- Search-only transport: bounded work, short-lived cache, and shared requests.
altairValues.searchTransport = { cache = {}, pending = {}, active = 0, hits = 0, bytes = 0, cooldown = 0 }
function altairValues.searchTransport:get(url, current)
	local deadline = os.clock() + 12
 local host=url:match("^https?://([^/]+)")or url
 self.cooldowns=self.cooldowns or {}
	if not current() then return nil, "Cancelled" end
	local cached = self.cache[url]
	if cached and cached.expires > os.clock() then
		cached.used = os.clock(); self.hits += 1
		return cached.value
	end
	if os.clock() < (self.cooldowns[host]or 0) then return nil, "Search is rate limited; try again shortly." end
	if type(httpRequest) ~= "function" then return nil, "This executor does not provide HTTP requests." end
	while self.active >= 4 and not self.pending[url] do
		if not current() then return nil, "Cancelled" end
		if os.clock() >= deadline then return nil, "Search is busy; try again shortly." end
		task.wait(0.05)
	end
	if not current() then return nil, "Cancelled" end
	if os.clock() < (self.cooldowns[host]or 0) then return nil, "Search is rate limited; try again shortly." end
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
					local retryAfter
					for key,value in pairs(headers)do
						if type(key)=="string"and key:lower()=="retry-after"then retryAfter=tonumber(value);break end
					end
					self.cooldowns[host] = os.clock() + math.clamp(retryAfter or 15, 1, 60)
                     self.cooldown=math.max(self.cooldown,self.cooldowns[host])
				end
				assert(status >= 200 and status < 300, "Search returned HTTP " .. tostring(status) .. ".")
				assert(type(response.Body) == "string" and #response.Body <= 1024 * 1024, "Search response is missing or too large.")
				local value = httpService:JSONDecode(response.Body)
				assert(type(value) == "table", "Invalid search response.")
                if type(value.data)=="table"and url:find("https://robloxscripts.com/api/v1/",1,true)==1 then
                 local scripts={}
                 for _,entry in ipairs(value.data)do if type(entry)=="table"and entry.accessType~="paid"then
                  entry.owner=type(entry.author)=="table"and entry.author or {};entry.verified=entry.owner.verified==true
                  if type(entry.features)=="table"then entry.features=table.concat(entry.features," · ")end
                  scripts[#scripts+1]=entry
                 end end
                 value.result={scripts=scripts}
                end
				assert((type(value.result) == "table" and type(value.result.scripts) == "table")
					or(type(value.result)=="table"and type(value.result.games)=="table")or type(value.script) == "table", "Search data is unavailable.")
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
-- Only result-supplied HTTPS images are downloaded; bounded concurrency and cache.
altairValues.searchImages={active=0,cache={},pending={}}
function altairValues.searchImages:get(result,current)
 local info=type(result.game)=="table"and result.game or {}
 local url=result.image or result.thumbnailUrl or result.thumbnail or info.imageUrl or info.image or info.iconUrl
 if type(url)=="table"then url=url.url end
 if type(url)~="string"or url==""then return nil end
 if url:sub(1,1)=="/"then url=(result.provider=="ScriptBlox"and "https://scriptblox.com"or result.provider=="RobloxScripts.com"and "https://robloxscripts.com"or "https://roscripts.io")..url end
 local host=url:match("^https://([^/:]+)")
 if not host or not host:find("%.")or host:match("^[%d%.]+$")or host:lower():match("%.local$")or #url>2048 then return nil end
 if type(writefile)~="function"or type(isfile)~="function"or type(makefolder)~="function"or type(isfolder)~="function"or type(getcustomasset)~="function"then return nil end
 local cached=self.cache[url];if cached and(cached.asset or os.clock()<(cached.retryAt or 0))then cached.used=os.clock();return cached.asset end
 local job=self.pending[url]
 if not job then
  job={done=false};self.pending[url]=job
  task.spawn(function()
   while self.active>=3 do if not UI.Parent then job.done=true;self.pending[url]=nil;return end;task.wait(.05)end
   self.active+=1
   local ok,asset=pcall(function()
    local hash=5381;for i=1,#url do hash=(hash*33+url:byte(i))%4294967296 end
    local folder=altairValues.altairFolder.."/Image Cache";if not isfolder(folder)then makefolder(folder)end
    local path=folder.."/search-"..string.format("%08x",hash)..".png"
    if not isfile(path)then
     local response=httpRequest({Url=url,Method="GET",Timeout=10})
     assert(type(response)=="table"and tonumber(response.StatusCode or response.Status)==200,"image unavailable")
     local body=response.Body;assert(type(body)=="string"and #body>12 and #body<=2*1024*1024,"invalid image")
     local valid=body:sub(1,8)=="\137PNG\13\10\26\10"or body:sub(1,3)=="\255\216\255"or(body:sub(1,4)=="RIFF"and body:sub(9,12)=="WEBP")
     assert(valid,"unsupported image");writefile(path,body)
    end
    return getcustomasset(path)
   end)
   self.active-=1;job.asset=ok and asset or nil;job.done=true;self.pending[url]=nil
   self.cache[url]={asset=job.asset,used=os.clock(),retryAt=os.clock()+30}
   local count=0;for _ in pairs(self.cache)do count+=1 end
   if count>64 then local oldest,time=nil,math.huge;for key,item in pairs(self.cache)do if item.used<time then oldest,time=key,item.used end end;if oldest then self.cache[oldest]=nil end end
  end)
 end
 local deadline=os.clock()+12
 while not job.done do if not current()or os.clock()>deadline then return nil end;task.wait(.05)end
 return current()and job.asset or nil
end
altairValues.discovery=altairValues.interfaceBindings.Discovery({
 Root=UI,
 Back=function()closeScriptSearch(false,nil,.42)end,
 Invalidate=function()altairValues.scriptSearchState.nav+=1 end,
 Position=function(size)return altairValues.smartBarLayout:getPanelPosition(scriptSearch,size)end,
 Error=function(problem)if checkAltair()then notification("Script Search",problem,4384402990)end end,
 Detail=function(result)
  if not checkAltair()then return end
  if result.provider=="RoScripts"or result.provider=="RobloxScripts.com"then return result end
  local state=altairValues.scriptSearchState;local version,nav=state.version,state.nav
  local function current()return checkAltair()and scriptSearch.Visible and state.version==version and state.nav==nav end
  local response=altairValues.searchTransport:get("https://scriptblox.com/api/script/"..httpService:UrlEncode(tostring(result.slug or "")),current)
  if not current()then return end
  if response and type(response.script)=="table"then result.script=response.script.script;return response.script end
 end,
 Image=function(result,current)return altairValues.searchImages:get(result,function()return checkAltair()and current()end)end,
 Execute=function(result)
  local state=altairValues.scriptSearchState;local version,nav=state.version,state.nav
  local function current()return checkAltair()and scriptSearch.Visible and state.version==version and state.nav==nav and altairValues.discovery.selected==result end
  if not current()then return end
  if result.provider=="RoScripts"then
   if type(result.loadstring)=="string"and result.loadstring:match("^https://script%.roscripts%.io/[%w_-]+$")then result.script="loadstring(game:HttpGet("..string.format("%q",result.loadstring).."))()"end
  elseif result.provider=="ScriptBlox"and(type(result.script)~="string"or result.script=="")then
   local response=altairValues.searchTransport:get("https://scriptblox.com/api/script/"..httpService:UrlEncode(tostring(result.slug or "")),current)
   if not current()then return end
   result.script=response and type(response.script)=="table"and response.script.script or nil
  end
  if not current()then return end
  if type(result.script)~="string"or result.script==""then return "The provider did not return runnable source."end
  local ok,chunk,problem=pcall(loadstring,result.script)
  if not current()then return end
  if not ok or type(chunk)~="function"then return tostring(problem or chunk)end
  Toast("Running script · "..tostring(result.title or "Untitled script"))
  if not current()then return end
  closeScriptSearch(true)
  if not checkAltair()then return end
  altairValues.activity:record("Script started",result.title.." · Script Search")
  if not checkAltair()then return end
  local success,err=pcall(chunk);if checkAltair()and not success then notification("Script Search",tostring(err),4384402990)end
 end,
})
do
 local button=Instance.new("TextButton");button.Name="ScriptSearchMouseUnlock";button.Text="";button.BackgroundTransparency=1;button.Size=UDim2.fromOffset(1,1);button.ZIndex=0;button.Active=false;button.Parent=scriptSearch
 altairValues.scriptSearchState.mouseUnlock=button
end

local function extractDomain(link)
	if type(link) ~= "string" or link:find("[%z\1-\32\127]") or link:find("\\", 1, true) then return nil end
	local scheme, authority = link:match("^([%a][%w+%.%-]*)://([^/?#]*)")
	local remember = scheme ~= nil and (scheme:lower() == "http" or scheme:lower() == "https")
	if scheme and not remember then return nil end
	if not authority then
		-- Scheme-less values are used for invite/clipboard display, never HTTP trust.
		authority = link:match("^([^/?#]+)")
		remember = false
	end
	if not authority or authority == "" or authority:find("%", 1, true) then return nil end
	local userinfo = authority:match(".*()@")
	if userinfo then authority = authority:sub(userinfo + 1); remember = false end
	local function ipv4(value)
		local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
		if not a then return false end
		for _, octet in ipairs({a, b, c, d}) do
			if #octet > 3 or (#octet > 1 and octet:sub(1, 1) == "0") or tonumber(octet) > 255 then return false end
		end
		return true
	end
	local host, suffix
	if authority:sub(1, 1) == "[" then
		local close = authority:find("]", 2, true)
		if not close then return nil end
		host, suffix = authority:sub(1, close):lower(), authority:sub(close + 1)
		local address = host:sub(2, -2)
		if address == "" or address:find("[^%x:%.]") or address:find(":::", 1, true) then return nil end
		if (address:sub(1, 1) == ":" and address:sub(1, 2) ~= "::")
			or (address:sub(-1) == ":" and address:sub(-2) ~= "::") then return nil end
		local compressed = address:find("::", 1, true)
		if compressed and address:find("::", compressed + 2, true) then return nil end
		if not compressed and (address:sub(1, 1) == ":" or address:sub(-1) == ":") then return nil end
		local groups = 0
		for part in address:gmatch("[^:]+") do
			if part:find(".", 1, true) then
				if not ipv4(part) or address:sub(-#part) ~= part then return nil end
				groups += 2
			else
				if #part > 4 then return nil end
				groups += 1
			end
		end
		if (compressed and groups >= 8) or (not compressed and groups ~= 8) then return nil end
	else
		host, suffix = authority:match("^([^:]+)(:.*)$")
		if not host then host, suffix = authority, "" end
		host = host:lower():gsub("%.$", "")
		if host == "" or #host > 253 or host:sub(1, 1) == "." or host:sub(-1) == "."
			or host:find("[^a-z0-9%.%-]") or host:find("..", 1, true) then return nil end
		for label in host:gmatch("[^.]+") do
			if #label > 63 or label:sub(1, 1) == "-" or label:sub(-1) == "-" then return nil end
		end
		-- URL stacks disagree about abbreviated/hex/octal numeric host spellings.
		if host:match("^[%d%.]+$") then
			if not ipv4(host) then return nil end
		elseif host:match("^[^.]+$") and host:match("^0x%x+$") then return nil
		elseif host:match("%.%d+$") or host:match("%.0x%x+$") then return nil end
	end
	if suffix ~= "" then
		local port = suffix:match("^:(%d+)$")
		if not port or #port > 5 or tonumber(port) < 1 or tonumber(port) > 65535 then return nil end
	end
	-- Preserve existing host-wide permissions across paths, schemes, and ports.
	return host, remember and host or nil
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

local allowlistWriting = false
local function rememberAllowedDomain(domain)
	while allowlistWriting do
		if not checkAltair() then return false end
		task.wait()
	end
	if not checkAltair() then return false end
	allowlistWriting = true
	local ok = pcall(function()
		checkFolder()
		local allowed = readAllowlist() or {}
		if not table.find(allowed, domain) then table.insert(allowed, domain) end
		if checkAltair() then
			writefile(altairValues.altairFolder .. "/allowedLinks.altair", httpService:JSONEncode(allowed))
		end
	end)
	allowlistWriting = false
	return ok
end

local function securityDetection(title, content, link, gradient, actions, operation)
	if not checkAltair() then
		return
	end

	local domain, allowedDomain = extractDomain(link)
	domain = domain or link
	if operation ~= "request" then allowedDomain = nil end
	checkFolder()
	if not checkAltair() then return false end
	local currentAllowlist = allowedDomain and readAllowlist() or nil
	if not checkAltair() then return false end
	if currentAllowlist and table.find(currentAllowlist, allowedDomain) then
		return true
	end
	if not allowedDomain then
		local oneTimeActions = {}
		for _, action in ipairs(actions) do if not action[3] then table.insert(oneTimeActions, action) end end
		actions = oneTimeActions
	end

	local newSecurityPrompt = UI.SecurityPrompt:Clone()

	newSecurityPrompt.Name = "SecurityReview-" .. httpService:GenerateGUID(false)
	newSecurityPrompt.Parent = UI

 newSecurityPrompt.Title.Text=title
 newSecurityPrompt.Subtitle.Text=content
 newSecurityPrompt.FoundLink.Text=domain
 altairValues.dialogMotion:Accent(newSecurityPrompt,gradient.Keypoints[#gradient.Keypoints].Value)
 newSecurityPrompt.Buttons.Template.Visible=false
 local function closeSecurityPrompt()
  altairValues.dialogMotion:Close(newSecurityPrompt,function()newSecurityPrompt:Destroy()end)
 end

	local decision

	for _, action in ipairs(actions) do
		local newAction = newSecurityPrompt.Buttons.Template:Clone()
		newAction.Name = action[1]
		newAction.Text = action[1]
		newAction.Parent = newSecurityPrompt.Buttons
		newAction.Visible = true
  local layout=newSecurityPrompt.Buttons:FindFirstChildOfClass("UIListLayout")
  local gap=layout and layout.Padding.Offset or 8
  newAction.Size=UDim2.new(1/#actions,-math.ceil(gap*(#actions-1)/#actions),1,0)

		newAction.MouseButton1Click:Connect(function()
			if decision ~= nil then
				return
			end -- one answer per prompt

			if not checkAltair() then
				decision = false
				closeSecurityPrompt()
				return
			end
			decision = action[2] == true
			if action[2] then
				if action[3] and allowedDomain and writefile then
					rememberAllowedDomain(allowedDomain)
				end
			end

			closeSecurityPrompt()
		end)
	end

 altairValues.dialogMotion:Open(newSecurityPrompt)

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
		if not checkAltair() then
			decision = false
			task.spawn(closeSecurityPrompt)
			break
		end
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

	return checkAltair() and decision or false
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
		local operation = "request"

		if url == "http://127.0.0.1:6463/rpc?v=1" and data.Body then
			local decodeSuccess, bodyDecoded = pcall(httpService.JSONDecode, httpService, data.Body)

			if decodeSuccess and type(bodyDecoded) == "table" and bodyDecoded.cmd == "INVITE_BROWSER" then
				operation = "discord-invite"
				title = "Would you like to join this Discord server?"
				content = "Altair has prevented your Discord client from automatically joining this Discord server, would you like to continue and join, or block it?"
				url = bodyDecoded.args and bodyDecoded.args.code and "discord.gg/" .. bodyDecoded.args.code or "Unknown Invite"
				gradient = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.new(0.345098, 0.396078, 0.94902)) })
				actions = { { "Allow", true }, { "Don't Allow", false } }
			end
		end

		if securityDetection(title, content, url, gradient, actions, operation) then
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

		if securityDetection(title, content, url, gradient, actions, "clipboard") then
			return originalSetClipboard(data)
		end
	end
	altairValues.lifecycle:replaceGlobal(indexSetClipboard, altairValues.lifecycle.clipboardWrapper)
end

local function searchScripts(query,preview)
 if not checkAltair()then return end
 local state=altairValues.scriptSearchState
 query=tostring(query or ""):match("^%s*(.-)%s*$")
 if query==""or #query>160 or utf8.len(query)==nil or not scriptSearch.Visible or state.phase=="closing"or state.phase=="closed"then return end
 local function providerPrefix(value,byteLimit)
  if #value<=byteLimit then return value end
  return value:sub(1,utf8.offset(value,0,byteLimit+1)-1)
 end
 state.nav+=1;local nav,version=state.nav,state.version;state.searching=query
 local function current()return checkAltair()and scriptSearch.Visible and state.version==version and state.nav==nav end
 local started=os.clock();altairValues.discovery:Skeleton(preview,query)
 local providers={
  {name="RoScripts",url="https://api.roscripts.io/v1/scripts/search?q="..httpService:UrlEncode(query).."&max=10&mode=free"},
  {name="ScriptBlox",url="https://scriptblox.com/api/script/search?q="..httpService:UrlEncode(query).."&mode=free&max=10&page=1"},
  {name="RobloxScripts.com",url="https://robloxscripts.com/api/v1/scripts?q="..httpService:UrlEncode(providerPrefix(query,100)).."&limit=10"},
 }
 local remaining=#providers+(preview and 1 or 0);local games={};local failures={}
 if preview then task.spawn(function()
  local ok,response=pcall(altairValues.searchTransport.get,altairValues.searchTransport,"https://api.roscripts.io/v1/suggest?q="..httpService:UrlEncode(query),current)
  if ok and response and type(response.result)=="table"then
   for _,group in ipairs({response.result.games or {},response.result.scripts or {}})do for _,item in ipairs(group)do if type(item)=="table"then games[#games+1]=item end end end
  end
  remaining-=1
 end)end
 for _,provider in ipairs(providers)do task.spawn(function()
  local ok,response=pcall(altairValues.searchTransport.get,altairValues.searchTransport,provider.url,current)
  if ok and response and type(response.result)=="table"and type(response.result.scripts)=="table"then provider.results=response.result.scripts
  else failures[#failures+1]=provider.name;provider.results={}end
  remaining-=1
 end)end
 while remaining>0 do if not current()then return end;task.wait(.03)end
 local minimum=preview and .2 or 11/60
 if os.clock()-started<minimum then task.wait(minimum-(os.clock()-started))end
 if not current()then return end;state.searching=nil
 local results={};local seen={}
 for index=1,10 do for _,provider in ipairs(providers)do
  local result=provider.results[index]
  if type(result)=="table"and type(result.title)=="string"and result.title:match("%S")then
   -- Keep UTF-8 title bytes; ASCII-only %W collapses unrelated names.
   local key=result.title:lower():gsub("[%s%p_]","")
   if key==""then key=result.title:lower():match("^%s*(.-)%s*$")end
   if not seen[key]and #results<20 then seen[key]=true;result.provider=provider.name;results[#results+1]=result end
  end
 end end
 altairValues.discovery:Results(results,preview,query,games)
 if #failures==#providers then notification("Script Search","Search providers are unavailable. Try again shortly.",4384402990)end
end
altairValues.discovery.Query=function(query,preview)task.spawn(searchScripts,query,preview)end
altairValues.discovery.LoadIdle=function()
 local state=altairValues.scriptSearchState;local version,nav=state.version,state.nav;local started=os.clock()
 local function current()return checkAltair()and scriptSearch.Visible and state.version==version and state.nav==nav end
 local function namedScripts(response)
  local scripts=type(response)=="table"and type(response.result)=="table"and response.result.scripts
  local results={}
  if type(scripts)=="table"then
   for _,item in ipairs(scripts)do
    if type(item)=="table"and type(item.title)=="string"and item.title:match("%S")then results[#results+1]=item end
   end
  end
  return results
 end
 local response=altairValues.searchTransport:get("https://api.roscripts.io/v1/scripts?universal=1&mode=free&max=4&sortBy=views",current)
 if os.clock()-started<.42 then task.wait(.42-(os.clock()-started))end
 if not current()then return end
 local results=namedScripts(response)
 local provider="RoScripts"
 if #results==0 and current()then
  provider="ScriptBlox";local fallback=altairValues.searchTransport:get("https://scriptblox.com/api/script/fetch?mode=free&max=4&sortBy=views&universal=1",current)
  results=namedScripts(fallback)
 end
 if not current()then return end
 for _,result in ipairs(results)do result.provider=provider end
 altairValues.discovery:Idle(results)
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
	if not checkAltair()then return end
	if smartBarOpen and smartBar.Visible and not smartBar:GetAttribute("AltairClosing")then return end
	local cold=not smartBar.Visible
	local transition = smartBarTransition:begin()
	smartBarOpen = true
	smartBar:SetAttribute("AltairClosing",false)
	altairValues.smartBarExitDirection=nil;altairValues.smartBarExitVector=nil
	local layout=altairValues.smartBarLayout
	if layout.exitPosition then
		if smartBar.Visible then smartBarTransition:create(smartBar,TweenInfo.new(.34,Enum.EasingStyle.Quint),{Position=layout.exitPosition}):Play()
		else smartBar.Position=layout.exitPosition end
	end
	layout.exitPosition=nil;layout.exitAnchor=nil
	updateBackpackLayout()

	if cold then
	 smartBar.Back.BackgroundTransparency = 1
	 smartBar.Back.UIStroke.Transparency = 1
	 smartBar.BackgroundTransparency = 1
	 smartBar.Back.Time.TextTransparency = 1
	 smartBar.Back.Time.AMPM.TextTransparency = 1
	 if smartBar.Back.Time:FindFirstChild("ClockDivider")then smartBar.Back.Time.ClockDivider.BackgroundTransparency=1 end
	 smartBar.UIStroke.Transparency = 1
	 smartBar.Shadow.ImageTransparency = 1
	 smartBar.Size = altairValues.smartBarLayout:getBarSize()
	end
	smartBar.UIStroke.Enabled = true
	smartBar.UIStroke.Thickness = .65
	smartBar.UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

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

	if cold then for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") then
			if button.Name == "Placeholder" then
				button.Visible = false
				button.BackgroundTransparency = 1
				continue
			end

			local gradient = button:FindFirstChildOfClass("UIGradient")
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
			local icon = button:FindFirstChild("Icon")

			if gradient then gradient.Rotation = -120 end
			if strokeGradient then strokeGradient.Rotation = -120 end
			button.BackgroundTransparency = 1
			if stroke then stroke.Transparency = 1 end
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then icon.ImageTransparency = 1 end
		end
	end end

	altairValues.smartBarLayout:syncContents(not cold)
	altairValues.smartBarLayout:syncToasts()

	-- Drag leaves the closed SmartBar position and returns to its authored
	-- above/below resting position.
	do
		local target = altairValues.smartBarLayout:getRestDragCenter()
		altairValues.smartBarLayout:tweenDragCenter(target,
			TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end

	smartBarTransition:create(smartBar, TweenInfo.new(.8, Enum.EasingStyle.Quint), { BackgroundTransparency = altairValues.surfaceTransparency(smartBar) }):Play()
	smartBarTransition:create(smartBar.Shadow, TweenInfo.new(1.2, Enum.EasingStyle.Quint), { ImageTransparency = .9 }):Play()
	smartBarTransition:create(smartBar.Back.Time, TweenInfo.new(.8, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	smartBarTransition:create(smartBar.Back.Time.AMPM, TweenInfo.new(.8, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	if smartBar.Back.Time:FindFirstChild("ClockDivider")then smartBarTransition:create(smartBar.Back.Time.ClockDivider,TweenInfo.new(.3),{BackgroundTransparency=.9}):Play()end
	smartBarTransition:create(smartBar.UIStroke, TweenInfo.new(.8, Enum.EasingStyle.Quint), { Transparency = 0.85 }):Play()

	for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") and button.Name ~= "Placeholder" then
			local gradient = button:FindFirstChildOfClass("UIGradient")
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
			local icon = button:FindFirstChild("Icon")

			if stroke then smartBarTransition:create(stroke, TweenInfo.new(.8, Enum.EasingStyle.Quint), { Transparency = .94 }):Play() end
			smartBarTransition:create(button, TweenInfo.new(.8, Enum.EasingStyle.Quint), {
				BackgroundTransparency = 0,
			}):Play()
			if gradient then smartBarTransition:create(gradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play() end
			if strokeGradient then smartBarTransition:create(strokeGradient, TweenInfo.new(1, Enum.EasingStyle.Quint), { Rotation = 50 }):Play() end
			if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
				smartBarTransition:create(icon, TweenInfo.new(.8, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
			end
			task.wait(.03)
			if not checkAltair()or transition ~= smartBarTransition.generation then return end
		end
	end

	smartBarTransition:create(smartBar.Back, TweenInfo.new(1, Enum.EasingStyle.Quint), { BackgroundTransparency = .45 }):Play()
	smartBarTransition:create(smartBar.Back.UIStroke, TweenInfo.new(1, Enum.EasingStyle.Quint), { Transparency = .96 }):Play()
	altairValues.smartBarLayout:syncContents(true)
	altairValues.smartBarLayout:syncToasts()
end

local function closeSmartBar(requestVersion)
 requestVersion=type(requestVersion)=="number"and requestVersion or altairValues.nextPanelRequest(nil)
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 if scriptSearch.Visible then closeScriptSearch(true,function()if altairValues.ownsPanelRequest(requestVersion)then closeSmartBar(requestVersion)end end);return end
	local transition = smartBarTransition:begin()
	local layout=altairValues.smartBarLayout
	layout.exitPosition=layout.exitPosition or smartBar.Position
	layout.exitAnchor=layout.exitAnchor or layout:getClosedDragCenter()
	local position=smartBar.AbsolutePosition.Y-UI.AbsolutePosition.Y
	local viewport=UI.AbsoluteSize.Y
	altairValues.smartBarExitDirection=position<120 and -1 or position+smartBar.AbsoluteSize.Y>viewport-120 and 1 or 0
 local dock=layout:getDock()
 altairValues.smartBarExitVector=dock=="left"and Vector2.new(-1,0)or dock=="right"and Vector2.new(1,0)or Vector2.new(0,altairValues.smartBarExitDirection)

	smartBarOpen = false
	smartBar:SetAttribute("AltairClosing",true)
	for _,button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		local icon=button:FindFirstChild("Icon")
		if icon then
			local rest=icon:GetAttribute("AltairHoverRestPosition")
			if rest then tweenService:Create(icon,TweenInfo.new(.18),{Position=rest}):Play() end
			local feedback=icon:FindFirstChild("PressFeedback")
			if feedback then tweenService:Create(feedback,TweenInfo.new(.18),{Scale=1}):Play() end
		end
	end
	updateBackpackLayout()

	if settingsPanel.Visible then task.spawn(closeSettings,true) end
	for _, otherPanel in ipairs(UI:GetChildren()) do
		if smartBar.Back.Buttons:FindFirstChild(otherPanel.Name) and isPanel(otherPanel.Name) and otherPanel.Visible then
			task.spawn(closePanel, otherPanel.Name, true)
			task.wait()
			if not checkAltair()or transition ~= smartBarTransition.generation then return end
		end
	end

	smartBarTransition:create(smartBar.Back.Time, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	smartBarTransition:create(smartBar.Back.Time.AMPM, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	if smartBar.Back.Time:FindFirstChild("ClockDivider")then smartBarTransition:create(smartBar.Back.Time.ClockDivider,TweenInfo.new(.2),{BackgroundTransparency=1}):Play()end

	for _, button in ipairs(smartBar.Back.Buttons:GetChildren()) do
		if button:IsA("GuiObject") and button.Name ~= "Placeholder" then
			local stroke = button:FindFirstChildOfClass("UIStroke")
			local icon = button:FindFirstChild("Icon")
			if stroke then smartBarTransition:create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play() end
			smartBarTransition:create(button, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
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
		closeInfo, layout:getDragSize(150,20))
	local shellGoal = {
		BackgroundTransparency = 1,
	}
 local exit=altairValues.smartBarExitVector or Vector2.zero
 if exit.Magnitude>0 then shellGoal.Position=layout.exitPosition+UDim2.fromOffset(exit.X*96,exit.Y*96)end


	smartBarTransition:create(smartBar.Back.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	smartBarTransition:create(smartBar.Back, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
	smartBarTransition:create(smartBar, closeInfo, shellGoal):Play()
	smartBarTransition:create(smartBar.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
	smartBarTransition:create(smartBar.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()

	task.delay(0.35, function()
		if checkAltair()and transition == smartBarTransition.generation and not smartBarOpen and smartBar.Parent then
			smartBar.Visible = false
			if layout.exitPosition then smartBar.Position=layout.exitPosition;layout.exitPosition=nil end
			smartBar.Size = altairValues.smartBarLayout:getBarSize()
			altairValues.smartBarLayout:syncToasts()
		end
	end)
end

local function windowFocusChanged(value)
	if not checkAltair() then
		return
	end
	altairValues.muffleAudio.focused = value

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
		altairValues.chatModeration:observe(player, message, {source="legacy"})
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
	local wasSpectating = spectating ~= nil
	spectating = nil
	if not wasSpectating then return end
	local activeCamera = syncCamera()
	if not activeCamera then return end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		activeCamera.CameraSubject = humanoid
	end
	activeCamera.CameraType = Enum.CameraType.Custom
end

local function toggleSpectate(player)
	if not checkAltair()then return false end
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

	local activeCamera = syncCamera()
	if not activeCamera then
		Toast("The camera is not available right now.")
		return false
	end
	spectating = player
	activeCamera.CameraSubject = humanoid
	activeCamera.CameraType = Enum.CameraType.Custom
	Toast("Now spectating " .. player.DisplayName .. ".")
	return true
end

local function teleportTo(player)
	if not checkAltair()then return false end
	local targetCharacter = player.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	local localCharacter = localPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")

	if targetRoot and localRoot then
		Toast("Teleporting to " .. player.DisplayName .. ".")
		if not checkAltair()then return false end
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
	if visible and playerlistPanel:GetAttribute("AltairClosing") then return end
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
	if not action or not action:IsA("GuiObject")then
		return
	end
	self.actionPulseVersions=self.actionPulseVersions or setmetatable({},{__mode="k"})
	local versions=self.actionPulseVersions
	local version=(versions[action]or 0)+1;versions[action]=version
	self:_setActionVisual(action, success == true)
	task.delay(0.5, function()
		if versions[action]~=version then return end
		versions[action]=nil
		if checkAltair()and action.Parent then
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

	self.subtitle = playerlistPanel:FindFirstChild("Subtitle") or playerlistPanel:FindFirstChild("Subtitle", true)
	self.subtitleTextTransparency = nil
	if self.subtitle and (
		self.subtitle:IsA("TextLabel")
		or self.subtitle:IsA("TextButton")
		or self.subtitle:IsA("TextBox")
	) then
		self.subtitleTextTransparency = math.min(self.subtitle.TextTransparency,.3)
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
		self.headerDivider.BackgroundTransparency = .9
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
		self.verticalDivider.BackgroundTransparency = .9
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

	local transitionVersion = self.transitionVersion
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
		friendBadge.Visible = false
		task.spawn(function()
			local ok, isFriend = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
			if self.selectedPlayer ~= player or self.transitionVersion ~= transitionVersion or not profile.Parent then
				return
			end
			friendBadge.Visible = ok and isFriend or false
		end)
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
 if row:GetAttribute("AltairHighlightState")==highlighted then return end
 row:SetAttribute("AltairHighlightState",highlighted)
	if not row or not row.Parent or self.rowsOpening or playerlistPanel:GetAttribute("AltairClosing") or not playerlistPanel.Visible then
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
				{ Transparency = .9 }
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
     and UDim2.fromOffset(221,34)
     or UDim2.new(1,-26,0,34)
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

	if altairValues.playerlistUI.panelSize and not playerlistPanel:GetAttribute("AltairClosing") then
		playerlistPanel.Size = altairValues.playerlistUI.panelSize
	end

	self:_populate(player)
	-- Friendship lookup may yield. A later selection or close owns both the
	-- detail data and its entrance animation when that lookup resumes.
	if self.transitionVersion ~= transitionVersion or self.selectedPlayer ~= player or not playerlistPanel.Parent then
		return
	end
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

	if altairValues.playerlistUI.panelSize and not playerlistPanel:GetAttribute("AltairClosing") then
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

	if altairValues.playerlistUI.panelSize and not playerlistPanel:GetAttribute("AltairClosing") then
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
track(playerlistPanel.DescendantAdded:Connect(function(object)
	if not playerlistPanel:GetAttribute("AltairClosing") then return end
	task.defer(function()
		if not object.Parent or not playerlistPanel:GetAttribute("AltairClosing") then return end
		if object:IsA("UIStroke") then object.Transparency=1
		elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then object.TextTransparency=1;object.TextStrokeTransparency=1
		elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then object.ImageTransparency=1 end
	end)
end))

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
				altairValues.playerlistUI:_pulseAction(gotoAction,true)
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

function altairValues.playerlistUI:filterRuntimePlayer(row, query)
	if not row or not row.Parent or row:GetAttribute("AltairRuntimePlayer") ~= true then
		return
	end
	query = query or string.lower(playerSearch.Text)
	local displayName = string.lower(tostring(row:GetAttribute("AltairDisplayName") or ""))
	local username = string.lower(tostring(row:GetAttribute("AltairUsername") or ""))
	row.Visible = string.find(username, query, 1, true) ~= nil or string.find(displayName, query, 1, true) ~= nil
end

function altairValues.playerlistUI:refreshRuntimePlayer(player, row)
	if not player or not row or not row.Parent or row:GetAttribute("AltairRuntimePlayer") ~= true then
		return
	end

	local revealAllowed=playerlistPanel.Interactions:GetAttribute("AltairFadeGroup")or(not self.rowsOpening and not playerlistPanel:GetAttribute("AltairClosing")and playerlistPanel.Visible)

	row.Name = player.Name
	row:SetAttribute("AltairPlayerUserId", player.UserId)
	row:SetAttribute("AltairDisplayName", player.DisplayName)
	row:SetAttribute("AltairUsername", player.Name)
	self:filterRuntimePlayer(row)
 row.Size = self.selectedPlayer
  and UDim2.fromOffset(221,34)
  or UDim2.new(1,-26,0,34)

	for _, object in ipairs(row:GetDescendants()) do
		if object:IsA("UIStroke") then
			object.Enabled = true
			object.Thickness = .6
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
				if playerlistPanel.Interactions:GetAttribute("AltairFadeGroup")or(not self.rowsOpening and not playerlistPanel:GetAttribute("AltairClosing")and playerlistPanel.Visible)then
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
						if playerlistPanel.Interactions:GetAttribute("AltairFadeGroup")or(not self.rowsOpening and not playerlistPanel:GetAttribute("AltairClosing")and playerlistPanel.Visible)then
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

	newPlayer:SetAttribute("AltairPlayerOpen_BackgroundTransparency", .18)

	for _, object in ipairs(newPlayer:GetDescendants()) do
		if object:IsA("UIStroke") then
			object.Enabled = true
			object.Thickness = .6
			object:SetAttribute("AltairPlayerOpen_Transparency", .9)
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
	altairValues.playerlistUI:filterRuntimePlayer(newPlayer)
	if altairValues.registerRainbowPlayerRow then
		altairValues.registerRainbowPlayerRow(newPlayer)
	end
	if altairValues.applyPlayerlistBase then altairValues.applyPlayerlistBase(newPlayer) end

	if playerlistPanel.Visible and newPlayer.Visible and not playerlistPanel.Interactions:GetAttribute("AltairFadeGroup")then
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
			{ BackgroundTransparency = .18 }
		):Play()

		for _, object in ipairs(newPlayer:GetDescendants()) do
			if object:IsA("UIStroke") then
				tweenService:Create(
					object,
					TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Transparency = .9 }
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
		newPlayer.BackgroundTransparency = .18
		for _, object in ipairs(newPlayer:GetDescendants()) do
			if object:IsA("UIStroke") then
				object.Transparency = .9
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

	addPlayerConnection(player, player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if checkAltair() and newPlayer.Parent then
				altairValues.playerlistUI:refreshRuntimePlayer(player, newPlayer)
			end
			if not checkAltair() or spectating ~= player or player.Character ~= character then return end
			local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			-- The target may respawn again, spectating may stop, or Altair may
			-- unload while waiting for the new character's Humanoid.
			if not checkAltair() or spectating ~= player or player.Character ~= character
				or not humanoid or not humanoid:IsA("Humanoid") then return end
			local activeCamera = syncCamera()
			if not activeCamera then return end
			activeCamera.CameraSubject = humanoid
			activeCamera.CameraType = Enum.CameraType.Custom
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
 if playerlistPanel.Interactions:GetAttribute("AltairFadeGroup")and not(playerlistPanel.Visible and newPlayer.Visible)then
  newPlayer.BackgroundTransparency=0
  for _,object in ipairs(newPlayer:GetDescendants())do
   local properties=altairValues.transparencyProperties[object.ClassName]
   if properties then for _,property in ipairs(properties)do local value=object:GetAttribute("AltairPlayerOpen_"..property);if value~=nil then object[property]=value end end end
  end
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

function altairValues.settingsPosition(name,fallback)
 local layout=altairValues.settingsLayout;return layout and layout:GetPosition(name)or fallback
end

openSettings=function(requestVersion)
 if not smartBarOpen then return end
 requestVersion=type(requestVersion)=="number"and requestVersion or altairValues.nextPanelRequest("Settings")
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 if homeOpen then closeHome()end
 if not altairValues.ownsPanelRequest(requestVersion)then return end
 if scriptSearch.Visible then closeScriptSearch(false,function()if altairValues.ownsPanelRequest(requestVersion)then openSettings(requestVersion)end end);return end
 local shared=altairValues.sharedPanel:prepare("Settings");if shared=="cancelled" then return end
 local continuing=not shared and settingsPanel.Visible and settingsPanel:GetAttribute("AltairClosing")
 local resumeSize,resumePosition=settingsPanel.Size,settingsPanel.Position
 local resumeAlpha=settingsPanel.BackgroundTransparency
 altairValues.smartBarLayout:cancelDragPositionTween()
 local sharedSize,sharedPosition=settingsPanel.Size,settingsPanel.Position
 altairValues.panelBehindBar(settingsPanel,false)
 settingsPanel:SetAttribute("AltairClosing",false)
 if continuing and tweenService.Freeze then
  tweenService:Freeze(settingsPanel,{"Size","Position","BackgroundTransparency"})
  if settingsPanel:IsA("CanvasGroup")then tweenService:Freeze(settingsPanel,"GroupTransparency")end
 end
 settingsPanel:SetAttribute("AltairMotionVersion",(settingsPanel:GetAttribute("AltairMotionVersion") or 0)+1)
 local motionVersion=settingsPanel:GetAttribute("AltairMotionVersion")
 if not continuing then settingsPanel:SetAttribute("AltairSettingsRevealPending",true)end
 local glyph=settingsPanel:FindFirstChild("AltairMorphIcon");if glyph then glyph.Visible=false end
 altairValues.settingsRestPosition=altairValues.smartBarLayout:getPanelPosition(settingsPanel,(altairValues.settingsLayout and altairValues.settingsLayout:GetRestSize()or UDim2.fromOffset(740,430)))
 if not continuing then settingsPanel.SettingLists.Visible=false end
 if altairValues.settingsFadeSnapshot then
  for object,properties in pairs(altairValues.settingsFadeSnapshot)do if object.Parent then
   if continuing then
    if tweenService.Freeze then tweenService:Freeze(object,properties)end
    tweenService:Create(object,TweenInfo.new(.18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),properties,{ResolvedTransparency=true}):Play()
   else for key,value in pairs(properties)do if object[key]~=value then object[key]=value end end end
  end end
  altairValues.settingsFadeSnapshot=nil
 end
 if not continuing and settingsPanel.SettingLists:IsA("CanvasGroup")then settingsPanel.SettingLists.GroupTransparency=1 end
	local stroke=settingsPanel:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Enabled=true;if not continuing then stroke.Transparency=.6 end end
	if homeOpen then closeHome() end
	for _, panelName in ipairs({ "Character", "Scripts", "Playerlist" }) do
		local panel = UI:FindFirstChild(panelName)
		if panel and panel.Visible and not panel:GetAttribute("AltairDeckSource")then
			closePanel(panelName, true)
			break
		end
	end
	if not altairValues.ownsPanelRequest(requestVersion)or settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion or settingsPanel:GetAttribute("AltairClosing")then return end
	debounce = true

 if not continuing then
  settingsPanel.BackgroundTransparency=1
  settingsPanel.Title.TextTransparency=1
  settingsPanel.Subtitle.TextTransparency=1
  settingsPanel.Back.ImageTransparency=1
  wipeTransparency(settingsPanel.SettingTypes,1,true)
  for _,name in ipairs({"NavigationWell","ContentWell","ContentDivider"})do local layer=settingsPanel:FindFirstChild(name);if layer then layer.BackgroundTransparency=1 end end
 end

	settingsPanel.Visible = true
 for _,name in ipairs({"NavigationWell","ContentWell","ContentDivider"})do local layer=settingsPanel:FindFirstChild(name);if layer then tweenService:Create(layer,TweenInfo.new(.26),{BackgroundTransparency=layer:GetAttribute("AltairDesignRestAlpha")or .9}):Play()end end
 if not continuing and altairValues.settingsSearch then altairValues.settingsSearch:Open()end
 if settingsPanel:IsA("CanvasGroup")then if not continuing then settingsPanel.GroupTransparency=1 end;tweenService:Create(settingsPanel,TweenInfo.new(.18),{GroupTransparency=0}):Play()end
 altairValues.bindPanelPointer(settingsPanel,smartBar.Back.Buttons.Settings)
 altairValues.setPanelPointerVisible(settingsPanel,smartBar.Back.Buttons.Settings,true,.18)
 if not continuing then
  settingsPanel.UIGradient.Enabled=true
  settingsPanel.BackgroundColor3=Color3.fromRGB(25,26,29)
  settingsPanel.UIGradient.Color=ColorSequence.new(Color3.new(.0470588,.0470588,.0470588))
  settingsPanel.UIGradient.Offset=Vector2.new(0,1.7)
 end
 if not continuing then altairValues.interfaceBindings.Surface(settingsPanel)end
 if continuing then settingsPanel.BackgroundTransparency=resumeAlpha end
 local divider=settingsPanel:FindFirstChild("SidebarDivider");if divider then tweenService:Create(divider,TweenInfo.new(.18),{BackgroundTransparency=.9}):Play()end
	settingsPanel.SettingTypes.Visible=true
 if not continuing then settingsPanel.SettingLists.Visible=false end
	local originSize,originPosition=getPanelButtonGeometry(settingsPanel,smartBar.Back.Buttons.Settings)
	settingsPanel.Size=continuing and resumeSize or shared and sharedSize or originSize
 settingsPanel.Position=continuing and resumePosition or shared and sharedPosition or originPosition
	altairValues.openPanelCorners(settingsPanel,smartBar.Back.Buttons.Settings,shared or continuing)
 if not settingsPanel:GetAttribute("AltairResumingDeck")then
  settingsPanel.Title.Position=altairValues.settingsPosition("Title",UDim2.fromOffset(50,12))
  settingsPanel.Subtitle.Position=altairValues.settingsPosition("Subtitle",UDim2.fromOffset(50,35))
 end
 if not continuing then
  for _,category in ipairs(altairSettings)do if category.name=="General"then settingsPanel.ContentTitle.Text=category.name;settingsPanel.ContentSubtitle.Text=category.description;break end end
  settingsPanel.ContentTitle.TextTransparency=1;settingsPanel.ContentSubtitle.TextTransparency=1
 end
 settingsPanel.HeaderIcon.Visible=true;if not continuing then settingsPanel.HeaderIcon.ImageTransparency=1 end
 tweenService:Create(settingsPanel.HeaderIcon,TweenInfo.new(.18),{ImageTransparency=0}):Play()

 if not continuing then
  settingsPanel.Title.Text="Preferences"
  settingsPanel.Subtitle.Text="Make Altair your own."
 end

 if altairValues.settingsLayout and altairValues.settingsLayout:IsLiteral()then altairValues.settingsLayout:Open(false)end
	if not shared then tweenService:Create(settingsPanel, TweenInfo.new(.38), { Size = (altairValues.settingsLayout and altairValues.settingsLayout:GetRestSize()or UDim2.fromOffset(740,430)),Position=altairValues.settingsRestPosition }):Play()end
 altairValues.sharedPanel:animate(settingsPanel,(altairValues.settingsLayout and altairValues.settingsLayout:GetRestSize()or UDim2.fromOffset(740,430)))
	tweenService:Create(settingsPanel, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = altairValues.surfaceTransparency(settingsPanel) }):Play()
	tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
	tweenService:Create(settingsPanel.Subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()

	task.wait(0.1)
	if not altairValues.ownsPanelRequest(requestVersion)or settingsPanel:GetAttribute("AltairClosing") or settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion then return end

	for _, settingType in ipairs(settingsPanel.SettingTypes:GetChildren()) do
		if settingType.ClassName == "Frame" then
			local gradientRotation = math.random(78, 95)

			tweenService:Create(settingType.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType.Shadow.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType.UIStroke.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Rotation = gradientRotation }):Play()
			tweenService:Create(settingType, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(settingType.Shadow, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			tweenService:Create(settingType.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0.4 }):Play()
			tweenService:Create(settingType.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()
			tweenService:Create(settingType.Description, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
            if settingType:FindFirstChild("CategoryIcon") then tweenService:Create(settingType.CategoryIcon,TweenInfo.new(.18),{ImageTransparency=0}):Play() end

			task.wait(0.02)
		if not altairValues.ownsPanelRequest(requestVersion)or settingsPanel:GetAttribute("AltairClosing") or settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
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

 if altairValues.settingsLayout and altairValues.settingsLayout:IsLiteral()then altairValues.settingsLayout:Open(true)
 elseif not continuing and altairValues.settingsSelectors and altairValues.settingsSelectors.General then altairValues.settingsSelectors.General()end
	debounce = false
end

closeSettings = function(combined)
 altairValues.settingsPageVersion=(altairValues.settingsPageVersion or 0)+1
 if altairValues.resetSettingsFeedback then altairValues.resetSettingsFeedback()end
 if smartBarOpen and settingsPanel.Visible then altairValues.smartBarLayout:cancelDragPositionTween()end
 altairValues.setPanelPointerVisible(settingsPanel,smartBar.Back.Buttons.Settings,false,.12)
 altairValues.sharedPanel:cancel(settingsPanel)
 if altairValues.themePicker then altairValues.themePicker:_setShown(false,true)end
 settingsPanel:SetAttribute("AltairClosing",true)
 altairValues.panelBehindBar(settingsPanel,true)
 settingsPanel:SetAttribute("AltairMotionVersion",(settingsPanel:GetAttribute("AltairMotionVersion") or 0)+1)
 local motionVersion=settingsPanel:GetAttribute("AltairMotionVersion")
 altairValues.settingsFadeSnapshot=altairValues.captureFadeState(settingsPanel)
 wipeTransparency(settingsPanel,1,false,true,.16)

	local stroke=settingsPanel:FindFirstChildOfClass("UIStroke")
	if stroke then
		tweenService:Create(stroke,TweenInfo.new(.18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Transparency=1}):Play()
	end
	debounce = true

	for _, settingType in ipairs(settingsPanel.SettingTypes:GetChildren()) do
		if settingType.ClassName == "Frame" then
			tweenService:Create(settingType, TweenInfo.new(.16, Enum.EasingStyle.Quint), { BackgroundTransparency = 1 }):Play()
			tweenService:Create(settingType.Shadow, TweenInfo.new(.16, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
			tweenService:Create(settingType.UIStroke, TweenInfo.new(.16, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(settingType.Title, TweenInfo.new(.16, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
			tweenService:Create(settingType.Description, TweenInfo.new(.16, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
		end
	end

	tweenService:Create(settingsPanel.Back, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { ImageTransparency = 1 }):Play()
	tweenService:Create(settingsPanel.Title, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()
	tweenService:Create(settingsPanel.Subtitle, TweenInfo.new(0.1, Enum.EasingStyle.Quint), { TextTransparency = 1 }):Play()

	for _, settingList in ipairs(settingsPanel.SettingLists:GetChildren()) do
		if settingList.ClassName == "ScrollingFrame" then
			for _, setting in ipairs(settingList:GetChildren()) do
				if setting.ClassName == "Frame" then
					-- Descendants fade as one content phase before the shell morph.
				end
			end
		end
	end

	task.wait(.08)
 if settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
 local size,position=getPanelButtonGeometry(settingsPanel,smartBar.Back.Buttons.Settings)
 if combined then
  local exit=altairValues.smartBarExitVector or Vector2.new(0,altairValues.smartBarExitDirection or 0)
  tweenService:Create(settingsPanel,TweenInfo.new(.3),{Position=settingsPanel.Position+UDim2.fromOffset(exit.X*(settingsPanel.AbsoluteSize.X+96),exit.Y*(settingsPanel.AbsoluteSize.Y+96)),BackgroundTransparency=1}):Play()
 else
  altairValues.morphPanelToIcon(settingsPanel,smartBar.Back.Buttons.Settings,size,position,motionVersion)
 end

	task.wait(.4)
 if settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
	settingsPanel.Visible = false
 settingsPanel.Position=altairValues.settingsRestPosition or settingsPanel.Position
 local glyph=settingsPanel:FindFirstChild("AltairMorphIcon");if glyph then glyph.Visible=false end
	if stroke then stroke.Enabled=false end
	debounce = false
end

local function settingsPath()
	return altairValues.altairFolder .. "/" .. altairValues.settingsFile
end
-- UI lifetimes are shorter than the Spotify link. Keep only configuration and
-- playback metadata here; account tokens remain in the companion.
altairValues.spotifySession = type(env.AltairSpotifySession)=="table" and env.AltairSpotifySession or {}
env.AltairSpotifySession = altairValues.spotifySession

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
	if not checkAltair()then return false end
	if type(writefile) ~= "function" then self.status = "Session only"; return false end
	if self.writing then self.pending = encoded; return false end
	if encoded == self.lastGood and not self.recovered then return true end
	self.writing = true
	local ok, problem = pcall(function()
		local function current()assert(checkAltair(),"Altair is unloaded")end
		current()
		assert(checkFolder(checkAltair)~=false,"Altair is unloaded")
		current()
		-- Never replace a good backup with unreadable primary data.
		writefile(settingsPath() .. ".backup", self.lastGood or encoded)
		current()
		if type(readfile) == "function" then
			local backup=readfile(settingsPath() .. ".backup")
			current()
			assert(backup == (self.lastGood or encoded), "Backup verification failed")
		end
		current()
		writefile(settingsPath(), encoded)
		current()
		if type(readfile) == "function" then
			local saved=readfile(settingsPath())
			current()
			assert(saved == encoded, "Settings verification failed")
		end
	end)
	if not checkAltair()then self.pending=nil;self.writing=false;return false end
	if self.pending then
		task.defer(function()
			if not checkAltair()then self.pending=nil;self.writing=false;return end
			local pending = self.pending; self.pending = nil; self.writing = false
			self:write(pending)
		end)
	else self.writing = false end
	if ok then self.lastGood = encoded; self.recovered = false; self.status = "Saved"; return true end
	self.status = "Save failed"
	if not self.warnedAt or os.clock() - self.warnedAt >= 30 then
		self.warnedAt = os.clock()
		warn("Altair | Settings could not be saved: " .. tostring(problem))
		notification("Settings not saved", "Your changes still work this session, but could not be saved to disk. Altair kept its recovery copy.", 4370336704)
	end
	return false
end
local function saveSettings(notifyUser)
	if not checkAltair()then return false end
	local flat = {}
	for _, category in ipairs(altairSettings) do
		for _, setting in ipairs(category.categorySettings) do
			if setting.persistent ~= false then
				if setting.settingType == "Key" and setting.current == nil then
					-- An absent key means "use the default"; false means explicitly unbound.
					flat[setting.id] = false
				elseif setting.current ~= nil then
					flat[setting.id] = setting.current
				end
			end
		end
	end
	local spotify={}
	for _,id in ipairs({"spotifyenabled","spotifyclientid","spotifyclientidmanual","spotifybridgekey","spotifyport"}) do spotify[id]=flat[id] end
	altairValues.spotifySession.settings=spotify
	if not writefile then
		if notifyUser then notification("Settings updated","",nil,{Key="settings-update",Duration=3}) end
		return false
	end

	local encodeSuccess, encoded = pcall(httpService.JSONEncode, httpService, flat)
	if not checkAltair()then return false end
	if not encodeSuccess then
		warn("Altair | Unable to encode settings: " .. tostring(encoded))
		return
	end

	local saved=altairValues.settingsStore:write(encoded)
	if not checkAltair()then return false end
	if saved and notifyUser then notification("Settings saved","",nil,{Key="settings-update",Duration=3}) end
	return saved
end

function altairValues.importSpotifyConnection()
 if type(readfile)~="function"then return false end
 local ok,data=pcall(function()return httpService:JSONDecode(readfile(altairValues.altairFolder.."/Spotify.connection.json"))end)
 if not ok or type(data)~="table"or data.version~=1 or type(data.bridgeKey)~="string"or #data.bridgeKey<32 or #data.bridgeKey>256 or type(data.port)~="number"or data.port<1024 or data.port>65535 or data.port%1~=0 then return false end
 for _,entry in ipairs({{"Spotify Bridge Key",data.bridgeKey},{"Spotify Bridge Port",data.port},{"Spotify Client ID",data.clientId}})do
  local setting=checkSetting(entry[1]);local override=checkSetting("Spotify Client ID Override")
  if setting and entry[2]~=nil and(entry[1]~="Spotify Client ID"or(type(entry[2])=="string"and setting.current=="" and not(override and override.current)))then setting.current=entry[2]end
 end
 return true
end
function altairValues.enableSpotifyConnection()
 altairValues.importSpotifyConnection()
 local setting=checkSetting("Spotify Connection");setting.current=true
 local row=setting._uiObject
 if row and row.Parent then tweenService:Create(row.Switch.Indicator,TweenInfo.new(.25),{Position=UDim2.new(1,-20,.5,0),BackgroundTransparency=.6}):Play()end
 saveSettings(false)
end

local function restoreSettings()
	if altairValues.settingsStore.restored then return end
	local spotifyConnectionRestored=false
	do
		local stored = altairValues.settingsStore:load() or altairValues.spotifySession.settings
		if type(stored) == "table" then
			for _, category in ipairs(altairSettings) do
				for _, setting in ipairs(category.categorySettings) do
					if setting.persistent == false then continue end
					local value = stored[setting.id]

					if value == nil and stored[1] then
						for _, storedCategory in ipairs(stored) do
							if type(storedCategory) == "table" and type(storedCategory.categorySettings) == "table" then
								for _, storedSetting in ipairs(storedCategory.categorySettings) do
									if type(storedSetting) == "table" and storedSetting.id == setting.id then
										value = storedSetting.current
										break
									end
								end
							end
						end
					end

					if setting.settingType == "Key" then
						if value == false then
							setting.current = nil
						elseif type(value) == "string" then
							setting.current = value
						end
					elseif value ~= nil and (setting.current == nil or typeof(value) == typeof(setting.current)) then
						if setting.settingType=="Number"then
							if type(value)~="number"or value~=value or math.abs(value)==math.huge then continue end
							-- Keep the legacy scale=3 marker for Layout's existing 1.25 migration.
							if setting.values and not(setting.id=="capsulescale"and value==3)then value=math.clamp(value,setting.values[1],setting.values[2])end
						end
						setting.current = value
						if setting.id=="spotifyenabled"then spotifyConnectionRestored=true end
					end
				end
			end
		end
	end
    local paired=altairValues.importSpotifyConnection()
    if paired and not spotifyConnectionRestored then
     checkSetting("Spotify Connection").current=true
    end
	altairValues.settingsStore.restored=true
	if altairValues.serverRegion then altairValues.serverRegion.refresh(true) end
end

-- Preference pages and input bindings
local function assembleSettings()
 local buildAt=os.clock()
 local feedbackRows=setmetatable({},{__mode="k"})
 altairValues.resetSettingsFeedback=function()for row,reset in pairs(feedbackRows)do if row.Parent then reset()else feedbackRows[row]=nil end end end
 local searchEntries={}
 local searchKeywords={
  uisize="zoom scaling resolution display",
  themetint="accent colour color strength saturation",
  themelightness="bright light dark appearance",
  panelopacity="transparent transparency glass",
  rainbow="rainbow rgb animated colours colors",
  avoidgameui="hud collision overlap avoid interface",
  capsuleposition="dock island top dynamic hidden drag bar",
  capsulerevealtime="capsule hover hide timeout",
  spotifyenabled="music media playback connection reconnect",
  spotifyclientid="music spotify oauth app setup",
  spotifybridgekey="music companion pairing",
  notificationduration="notification toast timeout duration",
  oledidledim="oled burn in screen dim idle",
  oledidledelay="oled idle timeout dim",
  suspiciousplayerdetection="player movement unusual signals experimental",
  detectflight="hover flying levitation airborne",
  detectspeed="running sprint fast movement platform",
  detectfling="spinning angular velocity physics fling",
  detectteleport="position jumps teleport dash portals",
  detectjump="air jump double jumping upward impulse",
  chatspamdetection="chat messages flood repeats links emoji",
  detectionselftest="test own character local player myself chat movement",
  detectioncooldown="signal notifications rate delay cooldown",
 }
 local categoryPresentation={
  Experimental={icon="flask-conical",description="Early features and integrations"},
  General={icon="sliders-horizontal",description="Appearance and everyday preferences"},
  Keybinds={icon="keyboard",description="Shortcuts for actions and controls"},
  Performance={icon="gauge",description="Performance and rendering options"},
  Detections={icon="shield-check",description="Audio, permissions and moderator notices"},
  Logging={icon="scroll-text",description="Activity and notification logs"},
  Developer={icon="terminal",description="Diagnostics and development tools"},
 }

	restoreSettings()

	saveSettings() -- write back quietly, picking up settings added since the file was created

	local function licenseLocked(tier)
		return (tier == "Pro" and not Pro) or (tier == "Essential" and not (Pro or Essential))
	end

	local function denyLocked(setting)
		local tier = setting.minimumLicense
		if not licenseLocked(tier) then return false end
		notification("This feature is locked", "You must be " .. tier .. " or higher to use " .. setting.name .. ". ", 4483345875)
		return true
	end

	local function bindInputResize(item, box)
        item.InputFrame.ClipsDescendants=true
        local corner=item.InputFrame:FindFirstChildOfClass("UICorner");if corner then corner.CornerRadius=UDim.new(1,0) end
		item.InputFrame.Size = UDim2.new(0, math.clamp(box.TextBounds.X/(UI:GetAttribute("AltairDisplayScale") or 1)+24,54,220), 0, 30)
  local pending=false
  local function resize()
   if pending then return end;pending=true
   task.defer(function()
    pending=false;if not item.Parent or not box.Parent then return end
    local width=math.clamp(math.ceil(box.TextBounds.X/(UI:GetAttribute("AltairDisplayScale")or 1))+28,54,220)
    tweenService:Create(item.InputFrame,TweenInfo.new(.18,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(width,30)}):Play()
   end)
  end
  box:GetPropertyChangedSignal("Text"):Connect(resize)
  box:GetPropertyChangedSignal("TextBounds"):Connect(resize)
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
  if altairValues.settingsLayout and altairValues.settingsLayout:Back(true)then return end
		tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {
			ImageTransparency = 1,
			Position = UDim2.new(0.002, 0, 0.052, 0),
		}):Play()
		tweenService:Create(settingsPanel.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = altairValues.settingsPosition("Title",UDim2.fromOffset(50,12)) }):Play()
		tweenService:Create(settingsPanel.UIGradient, TweenInfo.new(1, Enum.EasingStyle.Exponential), { Offset = Vector2.new(0, 1.3) }):Play()
		settingsPanel.Title.Text = "Preferences"
		settingsPanel.Subtitle.Text = "Make Altair your own."
        settingsPanel.HeaderIcon.Visible=true;settingsPanel.HeaderIcon.ImageTransparency=0
		settingsPanel.SettingTypes.Visible = true
		settingsPanel.SettingLists.Visible = false
	end)

	for _, category in altairSettings do
		if category.hidden then continue end
		local newCategory = settingsPanel.SettingTypes.Template:Clone()
		newCategory.Name = category.name
		newCategory.Title.Text = category.name
        local presentation=categoryPresentation[category.name]
        altairValues.interfaceBindings.ApplyIcon(newCategory.CategoryIcon,presentation and presentation.icon or "settings-2")
        newCategory.Description.Text=presentation and presentation.description or category.description
        newCategory.Description.Visible=false
		newCategory.LayoutOrder = #settingsPanel.SettingTypes:GetChildren()
		newCategory.Parent = settingsPanel.SettingTypes
		newCategory.BackgroundColor3 = Color3.new(1,1,1)
		newCategory.UIGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(16,16,19):Lerp(category.color,.22)),ColorSequenceKeypoint.new(.55,Color3.fromRGB(16,16,19):Lerp(category.color,.36)),ColorSequenceKeypoint.new(1,Color3.fromRGB(16,16,19):Lerp(category.color,.56))})
		newCategory.UIGradient.Offset=Vector2.new(0,.1)

		newCategory.Visible = true

		local hue, sat, val = Color3.toHSV(category.color)

		hue = math.clamp(hue + 0.01, 0, 1)
		sat = math.clamp(sat + 0.1, 0, 1)
		val = math.clamp(val + 0.2, 0, 1)

		local newColor = Color3.fromHSV(hue, sat, val)
		newCategory.UIStroke.UIGradient.Color = ColorSequence.new(category.color:Lerp(Color3.fromRGB(30,30,34),.45),newColor)
		newCategory.Shadow.UIGradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(0.117647, 0.117647, 0.117647)), ColorSequenceKeypoint.new(1, newColor) })

		local newList = settingsPanel.SettingLists.Template:Clone()
		newList.Name = category.name
		newList.Parent = settingsPanel.SettingLists

		newList.Visible = true;newList.Size=UDim2.fromScale(1,1)
        newList.ScrollingDirection=Enum.ScrollingDirection.Y;newList.AutomaticCanvasSize=Enum.AutomaticSize.Y;newList.CanvasSize=UDim2.new();newList.ScrollBarThickness=3
        local spacer=newList:FindFirstChild("Placeholder");if spacer and spacer:IsA("GuiObject") then spacer.Size=UDim2.new(1,-16,spacer.Size.Y.Scale,spacer.Size.Y.Offset) end

		for _, obj in ipairs(newList:GetChildren()) do
			if obj.Name ~= "Placeholder" and obj.Name ~= "UIListLayout" then
				obj:Destroy()
			end
		end

		local function selectCategory(preserveSearchNavigation)
            if settingsPanel:GetAttribute("AltairClosing") then return end
            if altairValues.resetSettingsFeedback then altairValues.resetSettingsFeedback()end
            if altairValues.settingsSearch then
             if altairValues.settingsSearch.Active then altairValues.settingsSearch:Clear(true)
             elseif preserveSearchNavigation~=true then altairValues.settingsSearch:CancelNavigation()end
            end
            altairValues.settingsActiveCategory=category
            if altairValues.settingsLayout then altairValues.settingsLayout:SelectCategory(newCategory,true)end
			if settingsPanel.SettingLists:FindFirstChild(category.name) then
				settingsPanel.UIGradient.Color = settingsPanel.UIGradient:GetAttribute("AltairTheme_Color")or ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(230,232,238))
				settingsPanel.SettingTypes.Visible = true
                settingsPanel.HeaderIcon.Visible=true
				settingsPanel.SettingLists.Visible = true
                local content=settingsPanel.SettingLists
                if settingsPanel:GetAttribute("AltairSettingsRevealPending")then
                 settingsPanel:SetAttribute("AltairSettingsRevealPending",false)
                 local rest=content:GetAttribute("AltairContentRestPosition")or content.Position;content:SetAttribute("AltairContentRestPosition",rest)
                 if content:IsA("CanvasGroup")then content.GroupTransparency=1 end
                 if not settingsPanel:GetAttribute("AltairDeckActive")then altairValues.interfaceBindings.SlideContent(content,rest,1,24)end
                end
                if content:IsA("CanvasGroup")then tweenService:Create(content,TweenInfo.new(.26),{GroupTransparency=0}):Play()end
				settingsPanel.SettingLists.UIPageLayout:JumpTo(settingsPanel.SettingLists[category.name])
                local page=settingsPanel.SettingLists[category.name]
                for _,row in ipairs(page:GetChildren()) do
                 if row:IsA("Frame") and not row:GetAttribute("AltairThemeEditor")then
                  row.ZIndex=settingsPanel.ZIndex+2
                  local inset=row:GetAttribute("AltairDesignRole")=="inset"
                  local rowAlpha=row:GetAttribute("AltairSourceRowRestAlpha")or(inset and(row:GetAttribute("AltairTheme_BackgroundTransparency")or .12)or .9)
                  tweenService:Create(row,TweenInfo.new(.18),{BackgroundTransparency=rowAlpha}):Play()
                  for _,object in ipairs(row:GetDescendants()) do
                   if object:FindFirstAncestor("RulerContent")then continue end
                   if object:IsA("GuiObject") and not object:GetAttribute("AltairRayfieldVisual") then object.ZIndex=settingsPanel.ZIndex+(object.Name=="Indicator" and 5 or object:IsA("GuiButton") and 6 or 4) end
                   if object.Name=="Note" then object.Visible=object:GetAttribute("AltairSourceRestVisible")==true end
                   if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                    tweenService:Create(object,TweenInfo.new(.18),{TextTransparency=object:GetAttribute("AltairSourceRestAlpha")or(object.Name=="Description" and .25 or 0)}):Play()
                   elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                    tweenService:Create(object,TweenInfo.new(.18),{ImageTransparency=.05}):Play()
                   elseif object:IsA("UIStroke") then
                    tweenService:Create(object,TweenInfo.new(.18),{Transparency=object:GetAttribute("AltairSourceRestAlpha")or(inset and .9 or .6)}):Play()
                   elseif object:IsA("Frame") and object.Name=="Indicator" then
                    local model=checkSetting(row.Name)
                    tweenService:Create(object,TweenInfo.new(.18),{BackgroundTransparency=row:GetAttribute("AltairSourceSettingsRow")and(model and model.current and .6 or .75)or .6}):Play()
                   elseif object:IsA("Frame") and object.Name=="Switch" then
                    tweenService:Create(object,TweenInfo.new(.18),{BackgroundTransparency=object:GetAttribute("AltairSourceRestAlpha")or .45}):Play()
                   end
                  end
                 end
                end
				if altairValues.themePicker then altairValues.themePicker:_setShown(category.name=="General",true)end
				settingsPanel.Subtitle.Text = "Personalize Altair."
				settingsPanel.Back.Visible = false
				altairValues.settingsPageVersion=(altairValues.settingsPageVersion or 0)+1
                local version=altairValues.settingsPageVersion
                local motionVersion=settingsPanel:GetAttribute("AltairMotionVersion")
                local title,subtitle=settingsPanel.ContentTitle,settingsPanel.ContentSubtitle
                local function revealHeading()
                 if not UI.Parent or not settingsPanel.Visible or version~=altairValues.settingsPageVersion or settingsPanel:GetAttribute("AltairClosing")or settingsPanel:GetAttribute("AltairMotionVersion")~=motionVersion then return end
                 title.Text=category.name;subtitle.Text=category.description
                 tweenService:Create(title,TweenInfo.new(.18),{TextTransparency=0}):Play()
                 tweenService:Create(subtitle,TweenInfo.new(.18),{TextTransparency=.2}):Play()
                end
                if title.TextTransparency>.98 and subtitle.TextTransparency>.98 then revealHeading()
                elseif title.Text~=category.name or subtitle.Text~=category.description then
                 tweenService:Create(title,TweenInfo.new(.1),{TextTransparency=1}):Play()
                 tweenService:Create(subtitle,TweenInfo.new(.1),{TextTransparency=1}):Play()
                 task.delay(.11,revealHeading)
                else
                 -- Returning to the still-assigned heading revokes the prior
                 -- page's pending fade, even before that page changed its text.
                 revealHeading()
                end

				local gradientRotation = math.random(78, 95)
				settingsPanel.UIGradient.Rotation = gradientRotation
				tweenService:Create(settingsPanel.UIGradient, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), { Offset = Vector2.new(0, 0.65) }):Play()
				tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
				tweenService:Create(settingsPanel.Back, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = UDim2.new(0.041, 0, 0.052, 0) }):Play()
				settingsPanel.Title.Position=altairValues.settingsPosition("Title",UDim2.fromOffset(50,12))
    if altairValues.settingsLayout and altairValues.settingsLayout:IsLiteral()then altairValues.settingsLayout:SelectCategory(newCategory,true)end
			else
				closeSettings()
			end
		end
        altairValues.settingsSelectors=altairValues.settingsSelectors or {}
        altairValues.settingsSelectors[category.name]=selectCategory
        newCategory.Interact.MouseButton1Click:Connect(selectCategory)

		newCategory.MouseEnter:Connect(function()
   if altairValues.settingsLayout and altairValues.settingsLayout:HoverCategory(newCategory,true)then return end
			tweenService:Create(newCategory.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
			tweenService:Create(newCategory.UIGradient, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0) }):Play()
			tweenService:Create(newCategory.UIStroke.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.2) }):Play()
			tweenService:Create(newCategory.Shadow.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.2) }):Play()
		end)

		newCategory.MouseLeave:Connect(function()
   if altairValues.settingsLayout and altairValues.settingsLayout:HoverCategory(newCategory,false)then return end
			tweenService:Create(newCategory.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.2 }):Play()
			tweenService:Create(newCategory.UIGradient, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.1) }):Play()
			tweenService:Create(newCategory.UIStroke.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.4) }):Play()
			tweenService:Create(newCategory.Shadow.UIGradient, TweenInfo.new(0.7, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, 0.4) }):Play()
		end)

		local rowOrder=0
		for _, setting in ipairs(category.categorySettings) do
            if os.clock()-buildAt>.002 then runService.Heartbeat:Wait();buildAt=os.clock()end
			if not setting.hidden then
				if setting.section then rowOrder+=1;local section=altairValues.interfaceBindings.ExperimentalSection(newList,setting.section,setting.sectionDescription);section.LayoutOrder=rowOrder end
                local settingType = setting.settingType
				local minimumLicense = setting.minimumLicense
				local object

				if settingType == "Action" then
					object = settingsPanel.SettingLists.Template.ButtonTemplate:Clone()
					object.Name, object.Parent, object.Visible = setting.name, newList, true
					object.Title.Text = setting.name
					object.Interact.Activated:Connect(function()
						if type(setting.action)=="function" then setting.action() end
					end)
                elseif settingType=="Choice"then
                    object=altairValues.interfaceBindings.Choice(settingsPanel.SettingLists.Template.ButtonTemplate,newList,setting,function()saveSettings(true)end)
				elseif settingType == "ColorPicker"then
                    setting.alpha=settingValue("Theme Tint",25)/100
                    local picker
                    object,picker=altairValues.interfaceBindings.ColorPicker(settingsPanel.SettingLists.Template.ButtonTemplate,newList,setting,function(color,alpha)
                     setting.current=color:ToHex():upper()
                     for _,category in ipairs(altairSettings)do for _,entry in ipairs(category.categorySettings)do if entry.id=="customtheme"then entry.current=true elseif entry.id=="themetint"then entry.current=math.floor(alpha*100+.5)end end end
                     if altairValues.applyAppearance then altairValues.applyAppearance()end
                    end,function()saveSettings(true)end,function()if altairValues.resetTheme then altairValues.resetTheme()end end)
                    altairValues.themePicker=picker
                elseif settingType == "Stat" then
                    object,altairValues.performanceStats=altairValues.interfaceBindings.Stats(settingsPanel.SettingLists.Template.ButtonTemplate,newList)
                elseif settingType == "Slider" then
                    object=altairValues.interfaceBindings.Slider(settingsPanel.SettingLists.Template.ButtonTemplate,newList,setting,function(value)
                     if setting.id=="uisize" then UI:SetAttribute("AltairPreferredScale",value/100)
                     altairValues.interfaceBindings.Resize(UI)
                     fitHome()
                     if altairValues.capsules then altairValues.capsules:Layout() end
                     if altairValues.notificationController then altairValues.notificationController:Layout(true) end
                     altairValues.smartBarLayout:fitViewport()
                     end
                     if setting.id=="themetint"and altairValues.themePicker then altairValues.themePicker:SetAlpha(value/100,true)end
                     if setting.id=="themetint"then for _,category in ipairs(altairSettings)do for _,entry in ipairs(category.categorySettings)do if entry.id=="customtheme"then entry.current=true end end end end
                     if setting.id=="notificationduration"then UI:SetAttribute("AltairNotificationDuration",value)end
                     if(setting.id=="themetint"or setting.id=="themelightness"or setting.id=="panelopacity")and altairValues.applyAppearance then altairValues.applyAppearance()end
                    end,function() saveSettings(true) end)
                elseif settingType == "Boolean" then
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
						if not checkAltair()then return end
						if denyLocked(setting) then return end
						local function applyChange()
						if not checkAltair()then return end
						local previousValue = setting.current
						setting.current = not setting.current
						if setting.onChangedSync and type(setting.onChanged)=="function"then
							local changed,problem=pcall(setting.onChanged,setting.current,previousValue)
							if not changed then warn("Altair | Setting change handler failed: "..tostring(problem))end
						end
						altairValues.activity:record("Setting changed", setting.name .. (setting.current and " · Enabled" or " · Disabled"))
						saveSettings(true)
						if not setting.onChangedSync and type(setting.onChanged) == "function" then
							task.spawn(setting.onChanged, setting.current, previousValue)
						end

						local enabled = setting.current
						local indicator = newSwitch.Switch.Indicator
						-- saveSettings emits the compact notification confirmation.
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
						end
						if setting.current and setting.confirmDisable and altairValues.capsules then
							altairValues.capsules:ConfirmSpotifyDisconnect(applyChange,true)
						else applyChange() end
					end)
				elseif settingType == "Input" then
					local newInput, box = makeValueInput(newList, setting, "input")
					object = newInput

					box.FocusLost:Connect(function()
						if denyLocked(setting) then
							box.Text = truncateForDisplay(setting.current)
							return
						end
						if (box.Text ~= "" or setting.allowEmpty == true) and box.Text~=tostring(setting.current) then
							if setting.id=="spotifyclientid" then checkSetting("Spotify Client ID Override").current=true end
							setting.current = box.Text
							saveSettings(true)
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
						if inputValue and inputValue==inputValue then
							local oldValue = setting.current
							local nextValue = setting.values and math.clamp(inputValue, setting.values[1], setting.values[2]) or inputValue
							if nextValue ~= oldValue then
								setting.current = nextValue
								saveSettings(true)
								if type(setting.onChanged) == "function" then
									task.spawn(setting.onChanged, nextValue, oldValue)
								end
								-- Confirmation uses the notification stack, not a SmartBar toast.
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
                    rowOrder+=1;object.LayoutOrder=rowOrder;setting._uiObject=object
                    local keywords=setting.keywords or"";if type(keywords)=="table"then keywords=table.concat(keywords," ")end
                    searchEntries[#searchEntries+1]={name=setting.name,setting=setting,category=category,object=object,keywords=category.description.." "..keywords.." "..(searchKeywords[setting.id]or"")}
                end
                if object and settingType~="ColorPicker"and settingType~="Choice"and not object:GetAttribute("AltairExpandableSlider")then
                    object.Size=UDim2.new(1,-16,0,object.Size.Y.Offset)
					if setting.description then
						object.Description.Visible = true
						object.Description.TextWrapped = true
						object.Description.Size = UDim2.new(0, 333, 0, 999)
						object.Description.Text = setting.description
						object.Description.Size = UDim2.new(0, 333, 0, object.Description.TextBounds.Y + 10)
						object.Size = UDim2.new(1,-16,0,object.Description.TextBounds.Y+44)
					end

					if settingType=="Stat" then object.Size=UDim2.new(1,-16,0,188);object.Title.Visible=false;object.Description.Visible=false end
                    if settingType=="Slider" then object.Size=UDim2.new(1,-16,0,math.max(112,object.Description.TextBounds.Y+82)) end
					if minimumLicense and string.lower(minimumLicense)~="free" then
						object.LicenseDisplay.Visible = true
						object.Title.Position = UDim2.new(0, 18, 0, 26)
						object.Description.Position = UDim2.new(0, 18, 0, 43)
						object.Size = UDim2.new(1,-16,0,object.Size.Y.Offset+13)
						object.LicenseDisplay.Text = string.upper(minimumLicense) .. " FEATURE"
					end

                    object.Size=UDim2.new(1,-16,0,object.Size.Y.Offset)
                    if object:FindFirstChildOfClass("UICorner") then object:FindFirstChildOfClass("UICorner").CornerRadius=UDim.new(0,10) end
					local objectTouching=false
					object:SetAttribute("AltairSettingsHover",false);object:SetAttribute("AltairSettingsFeedbackBound",true)
					local feedbackVersion=0
					local restAlpha=object:GetAttribute("AltairDesignRestAlpha")or(object:GetAttribute("AltairDesignRole")=="inset"and .12 or .9)
					local restStroke=object:GetAttribute("AltairDesignRole")=="inset"and .9 or .6
					local function feedback(hovered,pressed)
						if not object.Parent then return end
						local active=hovered and settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing")
						local restAlpha=object:GetAttribute("AltairSourceRowRestAlpha")or restAlpha
						local restStroke=object:GetAttribute("AltairSourceRowRestStroke")or restStroke
						local alpha=math.clamp(restAlpha-(pressed and .11 or active and .07 or 0),0,1)
						tweenService:Create(object,TweenInfo.new(.16),{BackgroundTransparency=alpha}):Play()
						tweenService:Create(object.UIStroke,TweenInfo.new(.16),{Transparency=active and math.max(.5,restStroke-.2)or restStroke}):Play()
					end
					feedbackRows[object]=function()feedbackVersion+=1;objectTouching=false;object:SetAttribute("AltairSettingsHover",false);feedback(false)end
					object.MouseEnter:Connect(function()
						objectTouching=true;object:SetAttribute("AltairSettingsHover",true);feedback(true)
					end)

					object.MouseLeave:Connect(function()
						objectTouching=false;object:SetAttribute("AltairSettingsHover",false);feedback(false)
					end)

					if object:FindFirstChild("Interact") then
						object.Interact.MouseButton1Click:Connect(function()
							feedbackVersion+=1;local version=feedbackVersion;feedback(objectTouching,true)
							task.delay(.1,function()if feedbackVersion==version then feedback(objectTouching)end end)
						end)
					end
				end
			end
		end
	end
 if altairValues.settingsLayout then altairValues.settingsLayout:Destroy();altairValues.settingsLayout=nil end
 if altairValues.settingsSearch then altairValues.settingsSearch:Destroy()end
 altairValues.settingsSearch=altairValues.interfaceBindings.SettingsSearch({Panel=settingsPanel,Entries=searchEntries,
  OnSearch=function(active,count)
   if altairValues.settingsLayout and altairValues.settingsLayout:Search(active,count)then return end
   if not settingsPanel.Visible or settingsPanel:GetAttribute("AltairClosing")then return end
   altairValues.settingsPageVersion=(altairValues.settingsPageVersion or 0)+1;local version=altairValues.settingsPageVersion
   local motionVersion=settingsPanel:GetAttribute("AltairMotionVersion")
   local category=altairValues.settingsActiveCategory or altairSettings[1]
   local title=active and"Search preferences"or category.name
   local subtitle=active and(count==1 and"1 matching setting"or(count.." matching settings"))or category.description
   local heading,description=settingsPanel.ContentTitle,settingsPanel.ContentSubtitle
   tweenService:Create(heading,TweenInfo.new(.08),{TextTransparency=1}):Play();tweenService:Create(description,TweenInfo.new(.08),{TextTransparency=1}):Play()
   task.delay(.09,function()if UI.Parent and settingsPanel.Visible and altairValues.settingsPageVersion==version and settingsPanel:GetAttribute("AltairMotionVersion")==motionVersion and not settingsPanel:GetAttribute("AltairClosing")then
    heading.Text=title;description.Text=subtitle;tweenService:Create(heading,TweenInfo.new(.16),{TextTransparency=0}):Play();tweenService:Create(description,TweenInfo.new(.16),{TextTransparency=.2}):Play()
   end end)
   if active then
    tweenService:Create(settingsPanel.SettingLists,TweenInfo.new(.1),{GroupTransparency=1}):Play()
    task.delay(.11,function()if UI.Parent and settingsPanel.Visible and altairValues.settingsPageVersion==version and settingsPanel:GetAttribute("AltairMotionVersion")==motionVersion and not settingsPanel:GetAttribute("AltairClosing")and altairValues.settingsSearch and altairValues.settingsSearch.Active then settingsPanel.SettingLists.Visible=false end end)
   else
    settingsPanel.SettingLists.Visible=true;tweenService:Create(settingsPanel.SettingLists,TweenInfo.new(.18),{GroupTransparency=0}):Play()
   end
  end,
  Navigate=function(entry)local selectCategory=altairValues.settingsSelectors[entry.category.name];if selectCategory then selectCategory(true)end end,
  IsSelected=function(entry)return altairValues.settingsActiveCategory==entry.category end,
 })
 altairValues.settingsLayout=altairValues.interfaceBindings.SettingsLayout({Panel=settingsPanel,Search=altairValues.settingsSearch,Motion=tweenService,
  Category=function(name)for _,category in ipairs(altairSettings)do if category.name==name then return category end end end,
  Setting=function(row)return checkSetting(row.Name)end,
  OnRestSize=function(size)
   if not settingsPanel.Visible or settingsPanel:GetAttribute("AltairClosing")or settingsPanel:GetAttribute("AltairDeckActive")then return end
   local position=altairValues.smartBarLayout:getPanelPosition(settingsPanel,size)
   altairValues.settingsRestPosition=position
   tweenService:Create(settingsPanel,TweenInfo.new(.34,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=size,Position=position}):Play()
   altairValues.sharedPanel:animate(settingsPanel,size)
  end})
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
				notification("Kick Prevented", "Altair has prevented you from being kicked by the client.", 4400699701)
				return error("Expected ':' not '.' calling member function Kick", 2)
			end
			return originalIndex(self, method)
		end)

		originalNamecall = hookMetamethod(game, "__namecall", function(self, ...)
			if self == localPlayer and getnamecallmethod():lower() == "kick" and settingValue("Client-Based Anti Kick") and checkAltair() then
				notification("Kick Prevented", "Altair has prevented you from being kicked by the client.", 4400699701)
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
	local candidates = {altairValues.altairFolder .. "/Developer/AltairDevTools.lua"}

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
		if type(isfile) ~= "function" or type(loadfile) ~= "function" then return false end
		for _, path in ipairs(candidates) do
			local ok, exists = pcall(isfile, path)
			if ok and exists then return true end
		end
		return false
	end

	function controller:PublishDebugState(enabled, details, expectedGeneration)
		local publication=expectedGeneration or generation
		if not checkAltair()or publication~=generation then return end
		for callback in pairs(observers) do
			task.defer(function()
				if not checkAltair()or publication~=generation or not observers[callback]then return end
				local ok, err = pcall(callback, enabled == true, details)
				if not ok then warn("Altair | Debug observer failed: " .. tostring(err)) end
			end)
		end
	end

	function controller:Observe(callback)
		if type(callback) ~= "function"or not checkAltair()then return nil end
		local subscription=generation
		observers[callback] = true
		local connection = { Connected = true }
		function connection:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			observers[callback] = nil
		end
		task.defer(function()
			if connection.Connected and checkAltair()and subscription==generation then
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
		generation+=1 -- Revoke any bootstrap and deferred publication first.
		local service=activeService
		activeService = nil
		if not service then return end
		if type(service) == "table" and type(service.Destroy) == "function" then
			pcall(service.Destroy, service, reason or "debug-disabled")
		end

		local api=altairValues.lifecycle.api
		if type(api)=="table"and api.Dev==service then
			api.Dev = nil
		end
		if env.__ALTAIR_DEVTOOLS_SERVICE == service then
			env.__ALTAIR_DEVTOOLS_SERVICE = nil
		end
	end

	function controller:Start(expectedGeneration)
		local function current()
			return checkAltair()and expectedGeneration==generation and settingValue("Debug Mode",false)==true
		end
		if not current()then return false,"developer tools startup was superseded"end
		if activeService and type(activeService.GetStatus) == "function" then
			return true,activeService
		end

		local chunk, compileError, sourceName = compilePackage()
		if not current()then return false,"developer tools startup was superseded"end
		if not chunk then
			local title = sourceName and "Developer Tools failed to compile" or "Developer Tools unavailable"
			local suffix = sourceName and "" or ". Place AltairDevTools.lua in Altair/Developer and try again."
			notification(title, tostring(compileError) .. suffix, 4483345875)
			return false, compileError
		end

		local okChunk, bootstrap = pcall(chunk)
		if not current()then return false,"developer tools startup was superseded"end
		if not okChunk then
			notification("Developer Tools failed to load", tostring(bootstrap), 4483345875)
			return false, bootstrap
		end
		if type(bootstrap) ~= "function" then
			notification("Developer Tools invalid", "AltairDevTools.lua did not return a bootstrap function.", 4483345875)
			return false, "invalid developer tools package"
		end

		local initialConfig
		if configProvider then
			local okConfig, value = pcall(configProvider)
			if okConfig and type(value) == "table" then initialConfig = value end
		end
		if not current()then return false,"developer tools startup was superseded"end

		local okStart, service = pcall(bootstrap, {
			Altair = altairValues.lifecycle.api,
			RootFolder = altairValues.altairFolder,
			Version = altairValues.altairVersion,
			Source = sourceName,
			Config = initialConfig,
			StateChanged = function(...)
				if current()and stateSink then return stateSink(...)end
			end,
		})
		if not current()then
			-- An opaque bootstrap may return a shared/foreign singleton. Its
			-- pre-return side effects are not proof that this run owns it.
			return false,"developer tools startup was superseded"
		end
		if not okStart or type(service) ~= "table" then
			notification("Developer Tools failed to start", tostring(service), 4483345875)
			return false, service
		end

		activeService = service
		return true, service
	end

	function controller:Sync(enabled)
		if not checkAltair()then return false,"Altair is unloaded"end
		if enabled == nil then
			enabled = settingValue("Debug Mode", false) == true
		end

		if enabled then
			self:Stop("replaced")
			if not checkAltair()then return false,"Altair is unloaded"end
			local currentGeneration=generation
			local ok, serviceOrError = self:Start(currentGeneration)
			if not checkAltair()or generation~=currentGeneration then return false,"developer tools startup was superseded"end
			self:PublishDebugState(ok == true, { reason = ok and "enabled" or "start-failed", detail = serviceOrError },currentGeneration)
			return ok, serviceOrError
		end

		self:Stop("debug-disabled")
		if not checkAltair()then return false,"Altair is unloaded"end
		self:PublishDebugState(false, { reason = "disabled" })
		return true
	end

	-- start() can yield in the bootstrap before runtime() installs its cleanup.
	altairValues.lifecycle.developerCleanup=function()controller:Stop("altair-teardown")end
	return controller
end)()

local altairAPI = {}
altairValues.lifecycle.api = altairAPI
altairAPI.Unload = function() altairValues.lifecycle:unload() end
altairAPI.Destroy = altairAPI.Unload

-- Captured public action functions remain bound to this lifecycle. Read-only
-- accessors and idempotent Unload keep their existing contracts.
function altairValues.publicAction(callback)
	return function(...)
		if not checkAltair()then return end
		return callback(...)
	end
end

altairAPI.Toast = Toast
altairAPI.notification = altairValues.publicAction(notification)
altairAPI.Notification = altairAPI.notification
altairAPI.QueueNotification = altairAPI.notification
altairAPI.Notify = altairAPI.notification
restoreSettings() -- Restore connection configuration before the first media poll.
altairValues.softShadows=altairValues.interfaceBindings.SoftShadows(UI)
UI:SetAttribute("AltairPreferredScale",settingValue("UI Size",110)/100)
altairValues.interfaceBindings.Resize(UI)
fitHome()
track(UI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
 altairValues.interfaceBindings.Resize(UI)
 if altairValues.notificationController then altairValues.notificationController:Layout(true) end
 task.defer(function()
  if not UI.Parent then return end
  for _,name in ipairs({"Character","Scripts","Playerlist","Settings"}) do
   local panel=UI:FindFirstChild(name)
   if panel and panel.Visible and not panel:GetAttribute("AltairClosing") then panel.Position=altairValues.smartBarLayout:getPanelPosition(panel) end
  end
 end)
end))
UI:SetAttribute("AltairReduceMotion",settingValue("Reduce Motion",false))
do
 local bound=setmetatable({}, {__mode="k"})
 local function bindIcon(object)
  if bound[object] or not (object:IsA("ImageLabel") or object:IsA("ImageButton")) then return end
  bound[object]=true
  altairValues.interfaceBindings.RefreshIcon(object)
  track(object:GetPropertyChangedSignal("Image"):Connect(function() altairValues.interfaceBindings.RefreshIcon(object) end))
 end
 for _,object in ipairs(UI:GetDescendants()) do bindIcon(object) end
 track(UI.DescendantAdded:Connect(bindIcon))
 local buttons=setmetatable({}, {__mode="k"})
 local function bindButton(button)
  if button:IsDescendantOf(scriptSearch)then return end
  if buttons[button] or not button:IsA("GuiButton") or button.Name=="Input" or button.Name=="Interact" then return end
  if button.BackgroundTransparency==1 and not button:IsA("ImageButton") then return end
  if button:FindFirstChildOfClass("UIScale") then return end
  buttons[button]=true
  local scale=Instance.new("UIScale");scale.Name="AltairFeedback";scale.Parent=button
  local hovered,pressed=false,false
  local function update()
   local inactive=button:IsDescendantOf(smartBar)and not smartBarOpen
   local factor=(inactive or UI:GetAttribute("AltairReduceMotion")) and 1 or pressed and .97 or hovered and 1.015 or 1
   tweenService:Create(scale,TweenInfo.new(pressed and .09 or .18),{Scale=factor}):Play()
  end
  if button:IsDescendantOf(smartBar)then
   track(smartBar:GetAttributeChangedSignal("AltairClosing"):Connect(function()
    if smartBar:GetAttribute("AltairClosing")then hovered=false;pressed=false;update()end
   end))
  end
  track(button.MouseEnter:Connect(function() hovered=true;update() end))
  track(button.MouseLeave:Connect(function() hovered=false;pressed=false;update() end))
  track(button.MouseButton1Down:Connect(function() pressed=true;update() end))
  track(button.MouseButton1Up:Connect(function() pressed=false;update() end))
 end
 for _,object in ipairs(UI:GetDescendants()) do bindButton(object) end
 track(UI.DescendantAdded:Connect(bindButton))
end

do
	local originals=setmetatable({}, {__mode="k"});local elapsed=0
 local homeSurfaces={}
 local homeRoot=UI:FindFirstChild("Home")
 if homeRoot then for _,panel in ipairs(homeRoot:GetDescendants())do if panel:GetAttribute("AltairHomeSurface")then homeSurfaces[#homeSurfaces+1]=panel end end end
	track(runService.Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.25 then return end;elapsed=0
		UI:SetAttribute("AltairReduceMotion",settingValue("Reduce Motion",false))
		local oled=settingValue("OLED Appearance",false)
  UI:SetAttribute("AltairOLED",oled)
		for _,name in ipairs({"SmartBar","Settings","Character","Scripts","Playerlist","Home"}) do
			local panel=UI:FindFirstChild(name)
   if name=="Home" and panel then panel=panel:FindFirstChild("Content")or panel end
			if panel and panel:IsA("GuiObject") then
				if not originals[panel] then originals[panel]=altairValues.interfaceBindings.IdleBase(UI,panel,"BackgroundColor3",panel.BackgroundColor3)end
				local color=oled and not UI:GetAttribute("AltairThemeEnabled")and Color3.new(0,0,0)or panel:GetAttribute("AltairTheme_BackgroundColor3")or panel:GetAttribute("AltairThemeDefault_BackgroundColor3")or originals[panel]
				panel.BackgroundColor3=altairValues.interfaceBindings.IdleColor(UI,panel,"BackgroundColor3",color)
			end
        end
        for _,panel in ipairs(homeSurfaces)do if panel.Parent then
         local color=oled and not UI:GetAttribute("AltairThemeEnabled")and Color3.new(0,0,0)or panel:GetAttribute("AltairTheme_BackgroundColor3")or panel:GetAttribute("AltairThemeDefault_BackgroundColor3")or Color3.fromRGB(10,11,14)
         panel.BackgroundColor3=altairValues.interfaceBindings.IdleColor(UI,panel,"BackgroundColor3",color)
        end end
    end))
end
function altairValues.applyAppearance()
 altairValues.appearanceGeneration=(altairValues.appearanceGeneration or 0)+1
 local generation=altairValues.appearanceGeneration
 local alpha=1-math.clamp(tonumber(settingValue("Panel Opacity",90))or 90,0,100)/100
 UI:SetAttribute("AltairPanelTransparency",alpha)
 if altairValues.surfaceOpacity then altairValues.surfaceOpacity:Set(alpha)end
 local ok,color=pcall(Color3.fromHex,settingValue("Theme Color","5B8DEF"))
 if altairValues.theme then altairValues.theme:Apply({color=ok and color or Color3.fromRGB(91,141,239),custom=settingValue("Custom Theme",false),strength=settingValue("Theme Tint",25)/100,lightness=settingValue("Theme Lightness",0)/100})end
 if generation~=altairValues.appearanceGeneration then return end
 if altairValues.scriptSearchColours then altairValues.scriptSearchColours(scriptSearch.Header.SearchBox:IsFocused())end
 UI:SetAttribute("AltairNotificationDuration",settingValue("Notification Duration",5))
 for _,name in ipairs({"SmartBar","Character","Scripts","Playerlist","Settings"})do
  local panel=UI:FindFirstChild(name)
  if panel and panel.Visible and not panel:GetAttribute("AltairClosing")then panel.BackgroundTransparency=altairValues.surfaceTransparency(panel,alpha)end
 end
 local home=UI:FindFirstChild("Home");local content=home and home:FindFirstChild("Content")
 if content then for _,panel in ipairs(content:GetDescendants())do if panel:GetAttribute("AltairHomeSurface")then
  local homeAlpha=altairValues.surfaceTransparency(panel,alpha)
  panel:SetAttribute("AltairHomeFade_BackgroundTransparency",homeAlpha);panel:SetAttribute("AltairHomePageFade_BackgroundTransparency",homeAlpha)
  if homeOpen then panel.BackgroundTransparency=homeAlpha end
 end end end
 altairValues.dialogMotion:RefreshOpacity()
 local capsules=altairValues.capsules
 if capsules and capsules.SetSurfaceOpacity then capsules:SetSurfaceOpacity(alpha)end
end
altairValues.resetTheme=function()
 for _,category in ipairs(altairSettings)do for _,setting in ipairs(category.categorySettings)do
  if setting.id=="themecolor"then setting.current="5B8DEF"elseif setting.id=="themetint"then setting.current=25 elseif setting.id=="themelightness"then setting.current=0 elseif setting.id=="customtheme"then setting.current=false end
 end end
 local picker=altairValues.themePicker;if picker then picker:Set(Color3.fromHex("5B8DEF"),true);picker:SetAlpha(.25,true)end
 local page=settingsPanel.SettingLists:FindFirstChild("General")
 if page then for _,name in ipairs({"Theme Tint","Theme Lightness"})do local row=page:FindFirstChild(name);if row then row:SetAttribute("AltairRefreshValue",(row:GetAttribute("AltairRefreshValue")or 0)+1)end end end
 altairValues.applyAppearance();saveSettings(true)
end
altairValues.applyAppearance()
do
 local elapsed,frames=0,0
 track(runService.RenderStepped:Connect(function(dt)
  elapsed+=dt;frames+=1;if elapsed<1 then return end
  local fps=math.floor(frames/elapsed+.5);frames=0;elapsed=0
  local cards=altairValues.performanceStats
  if cards and settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing") then
   cards.fps:Set(fps);cards.ping:Set(getPing())
   cards.fps:_setShown(true,true);cards.ping:_setShown(true,true)
  end
 end))
end
-- Optional OLED idle dimming affects Altair only, never the game or monitor.
do
 local dimmer={alive=true,armed=false,ready=false,alpha=0,paintedAlpha=0,dirty=false,entries={},lookup={},generation=0,connections={}}
 altairValues.idleDimmer=dimmer
 local elapsed=0;local black=Color3.new(0,0,0);local startWorker
 local function disconnect()
  for _,connection in ipairs(dimmer.connections)do connection:Disconnect()end;table.clear(dimmer.connections)
 end
 local function stopWorker()
  dimmer.generation+=1;local worker=dimmer.worker;dimmer.worker=nil
  if worker and worker~=coroutine.running()then pcall(task.cancel,worker)end
  dimmer.queue=nil;dimmer.queued=nil;dimmer.queueAt=1;dimmer.paintPending=false
 end
 local function clear()
  table.clear(dimmer.entries);table.clear(dimmer.lookup);dimmer.ready=false;dimmer.paintedAlpha=0;dimmer.dirty=false
 end
 local function paint(record,alpha,restore)
  local object=record.object
  if alpha>0 then dimmer.dirty=true end
  for key,state in pairs(record.properties)do
   local current=object[key]
   if current~=state.last then state.base=current end
   local color=alpha==0 and state.base or state.base:Lerp(black,alpha)
   if not restore or current==state.last then state.last=color;if current~=color then object[key]=color end end
  end
 end
 local function remember(object,silent)
  if dimmer.lookup[object]then return end
  local gui=object:IsA("GuiObject");local stroke=object:IsA("UIStroke")
  if not gui and not stroke then return end
  local record={object=object,properties={}}
  local function property(key)local color=object[key];record.properties[key]={base=color,last=color}end
  if gui then property("BackgroundColor3")end
  if object:IsA("TextLabel")or object:IsA("TextButton")or object:IsA("TextBox")then property("TextColor3")end
  if object:IsA("ImageLabel")or object:IsA("ImageButton")then property("ImageColor3")end
  if stroke then property("Color")end
  dimmer.lookup[object]=record;dimmer.entries[#dimmer.entries+1]=record
  if not silent and dimmer.ready and dimmer.alpha>0 then paint(record,dimmer.alpha)end
 end
 function dimmer:BaseColor(object,key,color)
  local record=self.lookup[object];local state=record and record.properties[key]
  return state and color==state.last and state.base or color
 end
 function dimmer:ComposeColor(object,key,color)
  if not self.alive or self.alpha==0 and not self.armed and #self.entries==0 or not object.Parent or not object:IsDescendantOf(UI)then return color end
  remember(object,true)
  local record=self.lookup[object];local state=record and record.properties[key]
  if not state then return color end
  state.base=color;state.last=self.alpha==0 and color or color:Lerp(black,self.alpha)
  if self.alpha>0 then self.dirty=true end
  return state.last
 end
 local releaseColors=altairValues.interfaceBindings.BindIdleColors(UI,dimmer)
 local function enqueue(object)
  if not dimmer.alive or not dimmer.armed then return end
  if not dimmer.queue then dimmer.queue={};dimmer.queued={};dimmer.queueAt=1 end
  if dimmer.queued[object]then return end
  dimmer.queued[object]=true;dimmer.queue[#dimmer.queue+1]=object;startWorker()
 end
 startWorker=function()
  if dimmer.worker or not dimmer.alive then return end
  local generation=dimmer.generation
  dimmer.worker=task.defer(function()
   local budgetAt=os.clock()
   local function budget()
    if os.clock()-budgetAt<.002 then return true end
    runService.Heartbeat:Wait();budgetAt=os.clock()
    return dimmer.alive and generation==dimmer.generation and UI.Parent~=nil
   end
   while dimmer.alive and generation==dimmer.generation and UI.Parent do
    if dimmer.queue and dimmer.queueAt<=#dimmer.queue then
     local object=dimmer.queue[dimmer.queueAt];dimmer.queueAt+=1
     if object==UI or object.Parent and object:IsDescendantOf(UI)then
      remember(object)
      for _,child in ipairs(object:GetChildren())do enqueue(child)end
     end
     if not budget()then return end
    elseif dimmer.queue then
     dimmer.queue=nil;dimmer.queued=nil;dimmer.ready=true;dimmer.paintPending=true
    elseif dimmer.paintPending then
     dimmer.paintPending=false;local alpha=dimmer.alpha;local dead=false
     for index=1,#dimmer.entries do
      local record=dimmer.entries[index]
      if record then
       if record.object.Parent and record.object:IsDescendantOf(UI)then paint(record,alpha)
       else paint(record,0,true);dimmer.lookup[record.object]=nil;dimmer.entries[index]=false;dead=true end
      end
      if not budget()then return end
     end
     if dead then local entries={};for _,record in ipairs(dimmer.entries)do if record then entries[#entries+1]=record end end;dimmer.entries=entries end
     dimmer.paintedAlpha=alpha
     if alpha==0 then dimmer.dirty=false end
     if not dimmer.armed and alpha==0 then clear()end
    else break end
   end
   if generation==dimmer.generation then dimmer.worker=nil end
  end)
 end
 local function wake()
  if not dimmer.alive then return end
  altairValues.lastUIActivity=os.clock()
 end
 local function arm()
  stopWorker();dimmer.armed=true;dimmer.ready=false;wake()
  dimmer.connections={UI.DescendantAdded:Connect(enqueue),userInputService.InputBegan:Connect(wake),userInputService.InputChanged:Connect(wake),userInputService.WindowFocused:Connect(wake)}
  enqueue(UI)
 end
 function dimmer:Destroy()
  if not self.alive then return end
  self.alive=false;self.armed=false;disconnect();stopWorker()
  releaseColors()
  for _,record in ipairs(self.entries)do if record then paint(record,0,true)end end
  self.alpha=0;clear()
 end
 -- This owner-bound signal remains alive until destruction even when the main
 -- lifecycle has already disconnected its general runtime connections.
 UI.Destroying:Once(function()dimmer:Destroy()end)
 track(runService.Heartbeat:Connect(function(dt)
  if not dimmer.alive then return end
  elapsed+=dt;if elapsed<.1 then return end;local step=elapsed;elapsed=0
  local amount=math.clamp(tonumber(settingValue("OLED Idle Dim",0)) or 0,0,65)/100
  if amount>0 and not dimmer.armed then arm()
  elseif amount==0 and dimmer.armed then
   dimmer.armed=false;disconnect();stopWorker()
   if dimmer.alpha==0 and dimmer.paintedAlpha==0 and not dimmer.dirty then clear();return end
  end
  if not dimmer.armed and #dimmer.entries==0 then return end
  local target=dimmer.armed and dimmer.ready and os.clock()-(altairValues.lastUIActivity or 0)>settingValue("Idle Dim Delay",45)and amount or 0
  dimmer.alpha=dimmer.alpha+(target-dimmer.alpha)*(1-math.exp(-8*step));if math.abs(dimmer.alpha-target)<.001 then dimmer.alpha=target end
  if dimmer.alpha==0 and dimmer.paintedAlpha==0 and not dimmer.dirty and not dimmer.worker then return end
  dimmer.paintPending=true;startWorker()
 end))
end
altairValues.capsules = altairValues.interfaceBindings.Capsules({Root=UI, RequireBuiltUI=true, Clock=altairValues.interfaceBindings.Clock,
	Session=altairValues.spotifySession,
	GetSetting=settingValue, Request=originalRequest, Notify=notification, Alive=checkAltair, EnableSpotify=altairValues.enableSpotifyConnection,
	GetRainbowColor=function() return altairValues.rainbowColor end,
	Notifications=altairValues.notificationController,
 GetDragState=function()
  return {center=drag.AbsolutePosition-UI.AbsolutePosition+drag.AbsoluteSize/2,size=drag.AbsoluteSize,
   dock=altairValues.smartBarLayout:getDock(),dragging=altairValues.smartBarLayout.dragging==true}
 end})
altairAPI.Capsules = altairValues.capsules
altairValues.rayfieldBridge=altairValues.interfaceBindings.RayfieldBridge({Root=UI,Capsules=altairValues.capsules,Notify=notification,Theme=altairValues.theme})
local sentivel=altairValues.interfaceBindings.Sentivel({Root=UI,Notify=notification,Alive=checkAltair,Session=altairValues.sessionMemory,Request=originalRequest,
 SaveCache=function()altairValues.sessionMemory:save()end})
altairValues.sentivel=sentivel
altairValues.lifecycle.sentivel=sentivel
track(UI.Destroying:Connect(function()sentivel:Destroy()end))
altairAPI.GetServiceStatus=function()return altairValues.sentivel:GetStatus()end
altairAPI.ConnectRayfield=altairValues.publicAction(function(library)return altairValues.rayfieldBridge:WrapLibrary(library)end)
altairAPI.BlinkSmartBar = altairValues.publicAction(BlinkSmartBar)
altairAPI.SupportsColoredSmartBarBlink = true
altairAPI.SupportsQueuedSmartBarBlink = true
altairAPI.ToastSupportsSkipBlink = true
altairAPI.SetSmartBarPersistentColor = altairValues.publicAction(function(color)
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
end)

altairAPI.OpenSmartBar = altairValues.publicAction(openSmartBar)
altairAPI.CloseSmartBar = altairValues.publicAction(closeSmartBar)
altairAPI.OpenHome = altairValues.publicAction(openHome)
altairAPI.CloseHome = altairValues.publicAction(closeHome)
altairAPI.OpenPanel = altairValues.publicAction(openPanel)
altairAPI.ClosePanel = altairValues.publicAction(closePanel)
altairAPI.OpenScriptSearch = altairValues.publicAction(openScriptSearch)
altairAPI.SearchScripts = altairValues.publicAction(searchScripts)
altairAPI.CloseScriptSearch = altairValues.publicAction(closeScriptSearch)

altairAPI.Rejoin = rejoin
altairAPI.ServerHop = serverhop
altairAPI.CancelServerHop = altairValues.publicAction(function()altairValues.serverHop:cancel()end)
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
		homeStorage = altairValues.homeStore.status, homeRequests = altairValues.homeNetwork.active,
		homeSharedRequests = altairValues.homeNetwork.hits,
		sessionSeconds = math.max(0,os.time()-altairValues.sessionMemory.startedAt),
		sessionHops = altairValues.sessionMemory.hops, resumedSession = altairValues.sessionMemory.resumed == true,
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
altairAPI.UpdateHome = altairValues.publicAction(UpdateHome)
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
altairAPI.IsScriptRunning=function(info) return type(info)=="table" and altairValues.scriptAlreadyRunning(info) or false end
altairAPI.RegisterScriptRunning=function(info)
	if not checkAltair()then return false end
	assert(type(info)=="table","Provide the custom script definition")
	altairValues.markScriptRunning(info)
end
altairAPI.UnregisterScriptRunning=function(info)
	if not checkAltair()then return false end
	if type(info)~="table" then return false end
	env.AltairScriptRuns[altairValues.scriptRunKey(info)]=nil;return true
end
-- One native utility registry replaces duplicate remote utility loaders.
altairValues.nativeTools=altairValues.interfaceBindings.NativeUtilities({Root=UI,Notify=notification,IsAlive=checkAltair,
 CanCamera=function()return not homeOpen and not spectating end,
 GetControls=function()
  local module=localPlayer:FindFirstChild('PlayerScripts');module=module and module:FindFirstChild('PlayerModule')
  if module and module:IsA('ModuleScript')then return require(module):GetControls()end
 end,
})
altairValues.nativeTools:Register({id='rejoin',name='Rejoin',description='Reconnect to this experience using Altair recovery.',icon='log-in',run=rejoin})
altairValues.nativeTools:Register({id='serverhop',name='Find a server',description='Join a populated server with retry and cancellation.',icon='shuffle',run=serverhop})
altairValues.nativeTools:Register({id='copylink',name='Copy game link',description='Copy the current experience link.',icon='link',run=function()
 if not originalSetClipboard then return false,'Clipboard is unavailable in this executor'end
 originalSetClipboard('https://www.roblox.com/games/'..tostring(game.PlaceId));Toast('Experience link copied.');return true
end})
altairValues.nativeTools:Register({id='copyserver',name='Copy join script',description='Copy a join script for this exact server.',icon='copy',run=function()
 if not originalSetClipboard then return false,'Clipboard is unavailable in this executor'end
 originalSetClipboard(string.format('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, %q, game:GetService("Players").LocalPlayer)',game.PlaceId,game.JobId));Toast('Server join script copied.');return true
end})
altairAPI.ListNativeTools=function()return altairValues.nativeTools:List()end
altairAPI.RunNativeTool=function(id,...)return altairValues.nativeTools:Run(id,...)end
altairValues.nativeCatalog=(function()
 local body=scriptsPanel.Interactions;local selection=body.Selection
 local contentColor=scriptsPanel.Title:GetAttribute('AltairThemeDefault_TextColor3')or scriptsPanel.Title.TextColor3
 selection.UniversalScripts.Title.Text='Built-in tools'
 selection.UniversalScripts.Subtitle.Text='Native utilities · no extra scripts'
 if not selection:IsA('CanvasGroup')then
  local previous=selection;selection=Instance.new('CanvasGroup');selection.Name='Selection'
  for _,property in ipairs({'Size','Position','AnchorPoint','Visible','ZIndex','LayoutOrder','BackgroundColor3','BackgroundTransparency','BorderSizePixel'})do selection[property]=previous[property]end
  for _,child in ipairs(previous:GetChildren())do child.Parent=selection end
  previous:Destroy();selection.Parent=body
 end
 local rest=selection.Position+UDim2.fromOffset(10,42)
 local group=Instance.new('CanvasGroup');group.Name='NativeTools';group.BackgroundTransparency=1;group.Position=rest;group.Size=selection.Size-UDim2.fromOffset(20,52);group.Visible=false;group.GroupTransparency=1;group.Parent=body
 local list=Instance.new('Frame');list.Name='List';list.BackgroundTransparency=1;list.Size=UDim2.new(1,0,1,-30);list.Position=UDim2.fromOffset(0,30);list.Parent=group
 local back=Instance.new('TextButton');back.Name='Back';back.Text='‹  Scripts';back.FontFace=scriptsPanel.Title.FontFace;back.TextSize=14;back.TextXAlignment=Enum.TextXAlignment.Left;back.TextColor3=contentColor;back.BackgroundTransparency=1;back.AutoButtonColor=false;back.Size=UDim2.fromOffset(110,26);back.Parent=group
 local status=back:Clone();status.Name='ServiceStatus';status.AnchorPoint=Vector2.new(1,0);status.Position=UDim2.fromScale(1,0);status.Size=UDim2.fromOffset(210,26);status.TextSize=11;status.TextXAlignment=Enum.TextXAlignment.Right;status.TextTransparency=.25;status.Parent=group
 local service={opened=false,version=0,rows={}}
 local function restoreOpacity(object,properties)
  local animation=tweenService:Create(object,TweenInfo.new(0),properties);animation:Play();animation:Cancel()
  for property,value in pairs(properties)do
   if property=='BackgroundTransparency'and value<.99 then value=altairValues.interfaceBindings.MaterialAlpha(object,value)end
   object[property]=value
  end
 end
 local function paint(restore)
  if restore then restoreOpacity(back,{TextTransparency=.25});restoreOpacity(status,{TextTransparency=.25})end
  local health=altairValues.sentivel:GetStatus();status.Text='Services · '..(({operational='Online',unknown='Checking',outage='Outage',degraded='Degraded',maintenance='Maintenance'})[health.status]or 'Checking')
  local items=altairValues.nativeTools:List()
  for index,item in ipairs(items)do local row=service.rows[index];if row then
   if restore then
    restoreOpacity(row,{BackgroundTransparency=.16});restoreOpacity(row.Title,{TextTransparency=0});restoreOpacity(row.Description,{TextTransparency=.35});restoreOpacity(row.Icon,{ImageTransparency=0})
    local edge=row:FindFirstChildOfClass('UIStroke');if edge then restoreOpacity(edge,{Transparency=.8})end
   end
   row.State.Text=item.toggle and(item.active and 'ON' or 'OFF')or '›'
   if restore then restoreOpacity(row.State,{TextTransparency=item.active and 0 or .35})else row.State.TextTransparency=item.active and 0 or .35 end
   row:SetAttribute('NativeToolId',item.id)
  end end
 end
 local function animate(object,time,goal)return tweenService:Create(object,TweenInfo.new(time,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),goal):Play()end
 for index,item in ipairs(altairValues.nativeTools:List())do
  local row=Instance.new('TextButton');row.Name=item.id;row.Text='';row.AutoButtonColor=false;row.BackgroundColor3=Color3.fromRGB(25,28,34);row.BackgroundTransparency=altairValues.interfaceBindings.OpacityAlpha(.16,UI:GetAttribute('AltairPanelTransparency'));row.BorderSizePixel=0;row:SetAttribute('AltairDesignRole','control');row:SetAttribute('AltairMaterialRestAlpha',.16)
  row:SetAttribute('AltairDesignRole','control');row:SetAttribute('AltairDesignRestAlpha',.16)
  row.Size=UDim2.new(.5,-5,1/3,-5);row.Position=UDim2.new((index-1)%2*.5,(index-1)%2*5,math.floor((index-1)/2)/3,0);row.Parent=list;service.rows[index]=row
  local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,10);corner.Parent=row
  local edge=Instance.new('UIStroke');edge.Color=Color3.fromRGB(155,165,186);edge.Thickness=.65;edge.Transparency=.8;edge.Parent=row
  local source=selection:FindFirstChild(({'Reprompt','Library','CustomScripts','UniversalScripts','V4','CustomScripts'})[index])
  local gradient=Instance.new('UIGradient');gradient.Rotation=28;gradient.Color=source and(source.UIGradient:GetAttribute('AltairThemeDefault_Color')or source.UIGradient.Color)or ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(165,174,193));gradient.Parent=row
  if source then row.BackgroundColor3=Color3.new(1,1,1);edge.Color=source.UIStroke:GetAttribute('AltairThemeDefault_Color')or source.UIStroke.Color end
  local icon=Instance.new('ImageLabel');icon.Name='Icon';icon.BackgroundTransparency=1;icon.Position=UDim2.fromOffset(11,11);icon.Size=UDim2.fromOffset(22,22);icon.ImageColor3=contentColor;icon.Parent=row;altairValues.interfaceBindings.ApplyIcon(icon,item.icon)
  local title=Instance.new('TextLabel');title.Name='Title';title.BackgroundTransparency=1;title.Position=UDim2.fromOffset(42,8);title.Size=UDim2.new(1,-77,0,19);title.Text=item.name;title.TextXAlignment=Enum.TextXAlignment.Left;title.TextSize=14;title.FontFace=scriptsPanel.Title.FontFace;title.TextColor3=contentColor;title.Parent=row
  local subtitle=title:Clone();subtitle.Name='Description';subtitle.Position=UDim2.fromOffset(42,25);subtitle.Size=UDim2.new(1,-54,1,-27);subtitle.Text=item.description;subtitle.TextSize=10;subtitle.TextTransparency=.35;subtitle.TextYAlignment=Enum.TextYAlignment.Top;subtitle.TextWrapped=true;subtitle.TextTruncate=Enum.TextTruncate.None;subtitle.LineHeight=1;subtitle.Parent=row
  local state=title:Clone();state.Name='State';state.AnchorPoint=Vector2.new(1,0);state.Position=UDim2.new(1,-9,0,10);state.Size=UDim2.fromOffset(26,18);state.TextSize=11;state.TextXAlignment=Enum.TextXAlignment.Right;state.Parent=row
  row:SetAttribute('NativeToolId',item.id)
  row.MouseEnter:Connect(function()if service.opened then animate(edge,.14,{Transparency=.4});animate(row,.14,{BackgroundTransparency=.04})end end)
  row.MouseLeave:Connect(function()animate(edge,.2,{Transparency=.8});animate(row,.2,{BackgroundTransparency=.16})end)
  row.Activated:Connect(function()
   if not service.opened or scriptsPanel:GetAttribute('AltairClosing')then return end
   animate(row,.08,{BackgroundTransparency=.28})
   local ok,problem=altairValues.nativeTools:Run(item.id);if not ok then notification('Built-in tools',problem or 'This tool is unavailable.')end
   paint();animate(row,.2,{BackgroundTransparency=.16})
  end)
 end
 function service:Open()
  if self.opened or scriptsPanel:GetAttribute('AltairClosing')then return end
  self.opened=true;self.closing=false;self.pendingReturn=nil;self.version+=1;local version=self.version;paint(true)
  if group.Visible then selection.Visible=false;animate(group,.22,{GroupTransparency=0,Position=rest});return end
  animate(selection,.12,{GroupTransparency=1})
  task.delay(.12,function()if self.version~=version or not self.opened then return end
   paint(true);selection.Visible=false;group.Position=rest+UDim2.fromOffset(18,0);group.Visible=true;group.GroupTransparency=1
   animate(group,.22,{GroupTransparency=0,Position=rest})
  end)
 end
 function service:Close(immediate,onClosed)
  self.pendingReturn=onClosed
  if self.closing then return end
  if not self.opened then if onClosed then task.defer(onClosed)end;return end
  self.opened=false;self.closing=true;self.version+=1;local version=self.version
  animate(group,immediate and .08 or .16,{GroupTransparency=1,Position=rest+UDim2.fromOffset(18,0)})
  task.delay(immediate and .09 or .17,function()
   if self.version~=version then return end
   self.closing=false;group.Visible=false;selection.Visible=true;selection.GroupTransparency=1;animate(selection,.16,{GroupTransparency=0})
   local continuation=self.pendingReturn;self.pendingReturn=nil;if continuation then continuation()end
  end)
 end
 function service:Reset()
  -- A panel entrance always returns to its script choices. Revoke pending
  -- catalogue callbacks before they can hide a newly opened Selection group.
  self.version+=1;self.opened=false;self.closing=false;self.pendingReturn=nil
  if tweenService.Freeze then
   tweenService:Freeze(group,{GroupTransparency=group.GroupTransparency,Position=group.Position})
   tweenService:Freeze(selection,{GroupTransparency=selection.GroupTransparency})
  end
  group.Visible=false;group.GroupTransparency=1;group.Position=rest
  selection.Visible=true;selection.GroupTransparency=0
 end
 back.Activated:Connect(function()service:Close(false)end)
 status.Activated:Connect(function()
  if not service.opened then return end;altairValues.sentivel:Refresh()
  local health=altairValues.sentivel:GetStatus();local lines={}
  for _,component in ipairs(health.components)do lines[#lines+1]=component.name..' · '..component.status end
  notification('Altair service status',table.concat(lines,'\n'));paint()
 end)
 status.MouseEnter:Connect(function()animate(status,.15,{TextTransparency=0})end);status.MouseLeave:Connect(function()animate(status,.18,{TextTransparency=.25})end)
 back.MouseEnter:Connect(function()animate(back,.15,{TextTransparency=0})end);back.MouseLeave:Connect(function()animate(back,.18,{TextTransparency=.25})end)
 track(scriptsPanel:GetAttributeChangedSignal('AltairClosing'):Connect(function()
  if scriptsPanel:GetAttribute('AltairClosing')then
   service.version+=1;service.opened=false;service.closing=false;service.pendingReturn=nil
   -- Keep the rendered content until the parent group has finished fading.
   -- Reset() restores the choices underneath the next entrance.
  end
 end))
 return service
end)()
track(UI.Destroying:Connect(function()altairValues.nativeTools:Destroy()end))

altairAPI.ScanCustomScripts = altairValues.scanCustomScripts
altairAPI.OpenCustomScriptImporter = altairValues.openCustomScriptPrompt
altairAPI.SaveCustomScriptImporter = altairValues.saveCustomScriptPrompt
altairAPI.RepromptCustomScript = function()
	if not checkAltair()then return false end
	local detected = altairValues.detectedScript or altairValues.scanCustomScripts()
	if not checkAltair()then return false end
	if detected then
		return altairValues.showGameDetection(detected)
	end
	Toast("No custom script was detected for this experience.")
	return false
end

altairAPI.DebugContractVersion = 2

altairAPI.DebugEnabled = function()
	if not checkAltair()then return false end
	local dev = altairAPI.Dev
	return settingValue("Debug Mode", false) == true
		and type(dev) == "table"
		and dev._destroyed ~= true
end

altairAPI.GetDebugClient = function(name, provider, metadata)
	if not altairAPI.DebugEnabled() then return nil end
	local dev = altairAPI.Dev
	if type(dev.CreateClient) ~= "function" then return nil end
	local ok, client = pcall(dev.CreateClient, dev, name, provider, metadata)
	if not checkAltair()or altairAPI.Dev~=dev or not altairAPI.DebugEnabled()then return nil end
	return ok and client or nil
end

altairAPI.OnDebugChanged = function(callback)
	return developerTools:Observe(callback)
end

altairAPI.RecordActivity = function(title, description)
	if not checkAltair()then return false end
	return altairValues.activity:record(title, description)
end
altairAPI.Version = altairValues.altairVersion
requireStartup()
env.Altair = altairAPI

altairValues.continuation = { quiet = false, key = "Altair.Session.v1" }
do
	local session = altairValues.continuation
	local ok, marker = pcall(teleportService.GetTeleportSetting, teleportService, session.key)
	local recent = ok and type(marker) == "table" and marker.universe == game.GameId
		and type(marker.at) == "number" and os.time() - marker.at >= 0
		and (marker.arrivedJob == jobId or os.time() - marker.at < 600)
	if recent then
		session.quiet = marker.arrivedJob == jobId or (type(marker.fromJob) == "string" and marker.fromJob ~= jobId)
		if session.quiet and type(marker.open) == "boolean" then session.open = marker.open end
	end
	if altairValues.sessionMemory.resumed then
		session.quiet=true
		if altairValues.sessionMemory.open~=nil then session.open=altairValues.sessionMemory.open end
	end
	local function mark(arriving)
		altairValues.sessionMemory:save()
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

	altairValues.loading:Stage(.65,"Building settings")
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
					notification("Recording failed", tostring(err), 4483345875)
				end
			elseif type(dev) == "table" and type(dev.FinishCapture) == "function" then
				local ok, result = pcall(dev.FinishCapture, dev)
				if not ok then notification("Recording export failed", tostring(result), 4483345875) end
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

	local hideBarSetting=checkSetting("Hide Bar")
    if hideBarSetting then hideBarSetting.onChanged=function(hidden)
     if not hidden then drag.Visible=true;drag.Drag.Visible=true;altairValues.smartBarLayout:setDragVisual(100,.76,.18)end
     altairValues.smartBarLayout:syncDrag()
    end end
    local debugEnabled = developerAvailable and settingValue("Debug Mode", false) == true
	altairAPI.SetSmartBarPersistentColor(debugEnabled and Color3.fromRGB(126, 104, 220) or nil)
	developerTools:Sync(debugEnabled)

	ensureFrameProperties()
	sortActions()

	altairValues.loading:Stage(.85,"Restoring preferences")
	initialiseAntiKick()
	checkLastVersion()

	smartBar.Back.Time.Text = os.date("%I:%M"):gsub("^0", "")
    smartBar.Back.Time.AMPM.Text = os.date("%p")

	local startupHidden = settingValue("Load Hidden")
	if altairValues.continuation.open ~= nil then startupHidden = not altairValues.continuation.open end
	altairValues.theme:WhenReady()
	altairValues.smartBarLayout:prepareStartup(startupHidden)
    altairValues.loading:Finish(drag,settingValue("Hide Bar",false))
    altairValues.smartBarLayout:setDragVisual(100,.76,.32)

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
	altairValues.smartBarLayout.loading=false
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
		if detected and checkAltair() then
			altairValues.showGameDetection(detected)
		end
	end)

	if not altairValues.continuation.quiet and settingValue("Chat Spy") and not legacyChatActive then
		task.delay(6, function()
			notification(
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

-- Runtime input and player events

-- Drag can be clicked to toggle the SmartBar, or dragged to reposition it.
altairValues.smartBarLayout.openForDrag=openSmartBar
altairValues.smartBarLayout:bind(function()
	if smartBarOpen then closeSmartBar() else openSmartBar() end
end)
track(UI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() altairValues.smartBarLayout:fitViewport() end))
track(UI:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() altairValues.smartBarLayout:fitViewport() end))



requireStartup()
local startSuccess, startError = pcall(start)
requireStartup()
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

do
	local reset=characterPanel.Interactions.Reset
	local glyph=reset:FindFirstChild("ResetGlyph")or reset
	local native=game:GetService("TweenService")
	local function resetAccent()
		local ruler=altairValues.characterRuler
		return ruler and ruler.AccentColor or altairValues.sliders[1].color
	end
	local scale=Instance.new("UIScale");scale.Name="ResetHoldScale";scale.Parent=reset
	local rim=Instance.new("UIStroke");rim.Name="ResetHoldProgress";rim.Color=resetAccent();rim.Thickness=1;rim.Transparency=1;rim.Parent=reset
	local controller={pressed=false,held=false,generation=0,suppressActivation=false,tweens={}}
	altairValues.characterReset=controller
	local function allowed()
		local ruler=altairValues.characterRuler
		return altairValues.lifecycle.alive and UI.Parent and checkAltair()and characterPanel.Visible and not characterPanel:GetAttribute("AltairClosing")and not debounce and reset.Visible and ruler and ruler.Expanded and ruler.SelectedModel~=nil
	end
	local function animate(object,duration,goal,style)
		if controller.tweens[object]then controller.tweens[object]:Cancel()end
		local tween=native:Create(object,TweenInfo.new(duration,style or Enum.EasingStyle.Quad,Enum.EasingDirection.Out),goal)
		controller.tweens[object]=tween
		tween.Completed:Once(function()if controller.tweens[object]==tween then controller.tweens[object]=nil end end)
		tween:Play()
	end
	local function feedback(immediate)
		for _,tween in pairs(controller.tweens)do tween:Cancel()end;table.clear(controller.tweens)
		if immediate or not reset.Parent then
			scale.Scale=1;rim.Transparency=1;rim.Thickness=1;glyph.ImageColor3=Color3.fromRGB(190,190,190)
		else
			animate(scale,.24,{Scale=1},Enum.EasingStyle.Back)
			animate(rim,.18,{Transparency=1,Thickness=1})
			animate(glyph,.18,{ImageColor3=Color3.fromRGB(190,190,190)})
		end
	end
	function controller:Cancel(immediate,suppress)
		if suppress and self.pressed then self.suppressActivation=true end
		self.generation+=1;self.pressed=false;self.held=false;self.input=nil
		feedback(immediate)
	end
	local function resetFeedback(message,color)
		altairValues.interfaceBindings.BounceReset(reset)
		Toast(message,color or resetAccent())
	end
	function controller:ResetSelected()
		if not allowed()then return false end
		local ruler=altairValues.characterRuler
		local model=ruler and ruler.SelectedModel or altairValues.sliders[1]
		if not model then return false end
		if ruler then ruler:KeepExpanded()end
		if ruler then ruler.Ruler:Cancel(true)end
		updateSlider(model,model.default,true)
		resetFeedback((model.name:gsub("^%l",string.upper)).." reset")
		return true
	end
	function controller:ResetAll()
		if not allowed()then return false end
		local color=resetAccent()
		if altairValues.characterRuler then altairValues.characterRuler:KeepExpanded();altairValues.characterRuler.Ruler:Cancel(true)end
		resetSliders()
		resetFeedback("All character sliders reset",color)
		return true
	end
	track(reset.InputBegan:Connect(function(input)
		local kind=input.UserInputType
		if(kind~=Enum.UserInputType.MouseButton1 and kind~=Enum.UserInputType.Touch)or controller.pressed or not allowed()then return end
		controller:Cancel(true);controller.suppressActivation=false;controller.pressed=true;controller.input=input
		local generation=controller.generation
		rim.Color=resetAccent()
		animate(scale,.65,{Scale=1.08});animate(rim,.65,{Transparency=.12,Thickness=1.5});animate(glyph,.65,{ImageColor3=resetAccent()})
		task.delay(.65,function()
			if controller.generation~=generation or not controller.pressed or not allowed()then return end
			controller.held=true;controller.suppressActivation=true
			if controller:ResetAll()then feedback(false)end
		end)
	end))
	track(reset.Activated:Connect(function()
		if controller.suppressActivation then controller.suppressActivation=false;return end
		controller:ResetSelected()
	end))
	track(userInputService.InputEnded:Connect(function(input)
		if not controller.pressed then return end
		local active=controller.input
		if input==active or(active and active.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1)then controller:Cancel(false)end
	end))
	track(userInputService.InputChanged:Connect(function(input)
		if not controller.pressed or input~=controller.input or input.UserInputType~=Enum.UserInputType.Touch then return end
		local point=input.Position;local position=reset.AbsolutePosition;local size=reset.AbsoluteSize
		if point.X<position.X or point.X>position.X+size.X or point.Y<position.Y or point.Y>position.Y+size.Y then controller:Cancel(false,true)end
	end))
	track(reset.MouseLeave:Connect(function()if controller.pressed then controller:Cancel(false,true)end end))
	track(userInputService.WindowFocusReleased:Connect(function()controller:Cancel(false,true)end))
	track(characterPanel:GetPropertyChangedSignal("Visible"):Connect(function()if not characterPanel.Visible then controller:Cancel(true,true)end end))
	track(characterPanel:GetAttributeChangedSignal("AltairClosing"):Connect(function()if characterPanel:GetAttribute("AltairClosing")then controller:Cancel(true,true)end end))
	track(characterPanel:GetAttributeChangedSignal("AltairRulerExpanded"):Connect(function()if not characterPanel:GetAttribute("AltairRulerExpanded")then controller:Cancel(true,true)end end))
	track(UI.Destroying:Connect(function()controller:Cancel(true,true)end))
end

playerSearch:GetPropertyChangedSignal("Text"):Connect(function()
	local query = string.lower(playerSearch.Text)
	searchingForPlayer = query ~= ""

	for _, player in ipairs(playerlistPanel.Interactions.List:GetChildren()) do
		if player:IsA("GuiObject") and player:GetAttribute("AltairRuntimePlayer") == true then
			altairValues.playerlistUI:filterRuntimePlayer(player, query)
		end
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
	local function restSize()return button:GetAttribute("AltairScriptRestSize")or origsize end

	button.MouseEnter:Connect(function()
		if not debounce then
			local size=restSize()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = size-UDim2.fromOffset(5,3) }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 1 }):Play()
			tweenService:Create(button.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0.1 }):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		if not debounce then
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Size = restSize() }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Transparency = 0 }):Play()
			tweenService:Create(button.Title, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
		end
	end)

	button.Interact.MouseButton1Click:Connect(function()
		tweenService:Create(button, TweenInfo.new(0.4, Enum.EasingStyle.Quint), { Size = restSize()-UDim2.fromOffset(9,6) }):Play()
		task.wait(0.1)
		tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Size = restSize() }):Play()

		if button.Name == "Library" then
			if not scriptSearch.Visible and not debounce then
				openScriptSearch()
			end
		elseif button.Name == "UniversalScripts" then
			altairValues.nativeCatalog:Open()
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
	if homeOpen then
		closeHome()
	else
		openHome()
	end
end)

smartBar.Back.Buttons.Settings.Interact.MouseButton1Click:Connect(function()
	if settingsPanel.Visible and not settingsPanel:GetAttribute("AltairClosing")and not settingsPanel:GetAttribute("AltairDeckSource")then
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
			if not smartBarOpen then return end
			if isPanel(button.Name) then
				if UI:FindFirstChild(button.Name).Visible and not UI:FindFirstChild(button.Name):GetAttribute("AltairClosing")and not UI:FindFirstChild(button.Name):GetAttribute("AltairDeckSource")then
					task.spawn(closePanel, button.Name)
				else
					task.spawn(openPanel, button.Name)
				end
			end

			local pressScale=button.Icon:FindFirstChild("PressFeedback") or Instance.new("UIScale");pressScale.Name="PressFeedback";pressScale.Parent=button.Icon
            tweenService:Create(pressScale,TweenInfo.new(.1),{Scale=.88}):Play()
			tweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundTransparency = 0.6 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 0.6 }):Play()
			task.wait(0.15)
			if not smartBarOpen then return end
			tweenService:Create(pressScale,TweenInfo.new(.18),{Scale=1}):Play()
			tweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { BackgroundTransparency = 0 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { ImageTransparency = 0.02 }):Play()
		end)

		local iconRestPosition=button.Icon.Position
		button.Icon:SetAttribute("AltairHoverRestPosition",iconRestPosition)
		button.MouseEnter:Connect(function()
   if not smartBarOpen then return end
   local rest=button.Icon:GetAttribute("AltairHoverRestPosition")or iconRestPosition
   tweenService:Create(button.Icon,TweenInfo.new(.18),{Position=rest+UDim2.fromOffset(0,UI:GetAttribute("AltairReduceMotion")and 0 or -1)}):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(.2, Enum.EasingStyle.Quint), { Rotation = 75 }):Play()
			tweenService:Create(button.UIStroke.UIGradient, TweenInfo.new(.2, Enum.EasingStyle.Quint), { Rotation = 75 }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(.18, Enum.EasingStyle.Quint), { Transparency = .65 }):Play()
			tweenService:Create(button.Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { ImageTransparency = 0 }):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(.2, Enum.EasingStyle.Quint), { Offset = Vector2.new(0, -.08) }):Play()
		end)

		button.MouseLeave:Connect(function()
   if not smartBarOpen then return end
   local rest=button.Icon:GetAttribute("AltairHoverRestPosition")or iconRestPosition
   tweenService:Create(button.Icon,TweenInfo.new(.2),{Position=rest}):Play()
			tweenService:Create(button.UIStroke.UIGradient, TweenInfo.new(.22, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
			tweenService:Create(button.UIGradient, TweenInfo.new(.22, Enum.EasingStyle.Quint), { Rotation = 50 }):Play()
			tweenService:Create(button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quint), { Transparency = .82 }):Play()
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
			saveSettings(true)
		end

		return
	end

	if scriptSearch.Visible and input.KeyCode == Enum.KeyCode.Escape then
		closeScriptSearch()
		return
	end

	if processed or userInputService:GetFocusedTextBox() then
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
			altairValues.chatModeration:observe(player, chatMessage.Text, {source="modern",id=chatMessage.MessageId})
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
					notification("Staff in your server", "An administrator from this experience's group has just joined. They can see what you do in game. (" .. roleFound .. ")", 3944670656)
					break -- a role matching two keywords used to fire two prompts and two toasts
				end
			end
		end)
	end

	if settingValue("Friend Notifications") then
		local friendSuccess, isFriend = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
		if friendSuccess and isFriend then
			notification("Friend joined", player.DisplayName .. " has joined your server.", 4370335364)
		end
	end
end))

track(players.PlayerRemoving:Connect(function(player)
	if not altairValues.lifecycle.alive then return end
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
		if altairValues.playerAnomaly:HasEnabledChecks() then
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

	local function restoreNoclipPart(part)
		local ownership = noclipDefaults[part]
		noclipDefaults[part] = nil
		if not ownership then return end
		pcall(function()
			-- Only undo a value Altair actually wrote, and preserve a later
			-- observable game change instead of restoring a load-time snapshot.
			if part.CanCollide == ownership.applied then part.CanCollide = ownership.baseline end
		end)
	end

	local function clearCharacterPartTracking()
		for _, connection in ipairs(characterPartConnections) do
			connection:Disconnect()
		end
		table.clear(characterPartConnections)
		for part in pairs(noclipDefaults) do restoreNoclipPart(part) end
		table.clear(characterParts)
		table.clear(noclipDefaults)
	end

	local function trackCharacterParts(character)
		clearCharacterPartTracking()
		if not checkAltair() or not character then
			return
		end

		local function add(part)
			if checkAltair() and part:IsA("BasePart") then
				characterParts[part] = true
			end
		end

		for _, descendant in ipairs(character:GetDescendants()) do
			add(descendant)
		end

		table.insert(characterPartConnections, character.DescendantAdded:Connect(add))
		table.insert(
			characterPartConnections,
			character.DescendantRemoving:Connect(function(part)
				restoreNoclipPart(part)
				characterParts[part] = nil
			end)
		)
	end

	local function spatialShieldWanted()
		return checkAltair() and Pro and settingValue("Spatial Shield") == true
	end

	local function anonymousWanted()
		return settingValue("Anonymous Client") == true
	end

	local function restoreSpatialSound(sound)
		local ownership = spatialSoundVolumes[sound]
		spatialSoundVolumes[sound] = nil
		if not ownership then return end
		pcall(function()
			-- Restore only our last write; leave a later game/user volume intact.
			if sound.Volume == ownership.applied then sound.Volume = ownership.baseline end
		end)
	end

	local function clearSpatialShield()
		for sound in pairs(spatialSoundVolumes) do restoreSpatialSound(sound) end
		table.clear(suppressedSounds)
		table.clear(soundInstances)
		table.clear(trackedSounds)
		soundSuppressionNotificationCooldown = 0
	end
	local spatialSetting = checkSetting("Spatial Shield")
	local previousSpatialChanged = spatialSetting and spatialSetting.onChanged
	local spatialChangedHandler

	local function unregisterSound(sound)
		if not trackedSounds[sound] and not spatialSoundVolumes[sound] then return end
		restoreSpatialSound(sound)
		trackedSounds[sound] = nil
		for index = #soundInstances, 1, -1 do
			if soundInstances[index] == sound then table.remove(soundInstances, index) end
		end
	end

	local function suppressSound(sound, limit)
		if not spatialShieldWanted() then return false end
		local volume = sound.Volume
		local target = math.min(volume, limit)
		if target == volume then return false end -- Never amplify a quieter instance.
		local ownership = spatialSoundVolumes[sound]
		if not ownership or volume ~= ownership.applied then
			-- A game/user change supersedes the earlier baseline before we write again.
			ownership = { baseline = volume }
			spatialSoundVolumes[sound] = ownership
		end
		ownership.applied = target
		sound.Volume = target
		return true
	end

	local function registerSound(instance)
		if not spatialShieldWanted() or not instance:IsDescendantOf(game) then
			return
		end
		if trackedSounds[instance] then
			return
		end

		-- Track each instance: several sounds may share an ID and different volumes.
		trackedSounds[instance] = true
		table.insert(soundInstances, instance)
		local suppression = suppressedSounds[instance.SoundId]
		if suppression ~= nil then suppressSound(instance, suppression) end
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
		clearSpatialShield()
		if spatialSetting and spatialSetting.onChanged == spatialChangedHandler then
			spatialSetting.onChanged = previousSpatialChanged
		end
		-- Stop character forces before disconnecting their update callbacks.
		for _, index in {2,6} do
			local action=altairValues.actions[index]
			if action.enabled then action.enabled=false;pcall(action.callback,false) end
		end
		for _, mover in ipairs(movers) do pcall(mover.Destroy,mover) end
		table.clear(movers)
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
		if gameSettings then
			pcall(function() gameSettings.MasterVolume = oldVolume end)
		end
		pcall(function()
			cameraState:RestoreAll()
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
					if part.CanCollide ~= false then
						if not noclipDefaults[part] then
							noclipDefaults[part] = { baseline = part.CanCollide, applied = false }
						end
						part.CanCollide = false
					end
				else
					restoreNoclipPart(part)
				end
			end
		end

		noclipWasActive = noclipActive
	end))

	track(runService.Heartbeat:Connect(function()
		if not checkAltair() then
			return
		end

		local flightActive = altairValues.actions[2].enabled
		local flingActive = altairValues.actions[6].enabled

		local character = localPlayer.Character
		local primaryPart = character and character.PrimaryPart
		if not primaryPart then
			return
		end

		local bodyVelocity, bodyGyro, bodyAngularVelocity = unpack(movers)
		-- Sirius recreates cached forces when a respawn destroys the old instances.
		if bodyVelocity and not pcall(function() bodyVelocity.Parent=bodyVelocity.Parent end) then
			table.clear(movers)
			bodyVelocity,bodyGyro,bodyAngularVelocity=nil,nil,nil
		end
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

		local activeCamera = flightActive and syncCamera() or nil
		if flightActive and activeCamera then
			local camCFrame = activeCamera.CFrame
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

			local targetVelocity = velocity * altairValues.sliders[3].value * 45
			tweenService:Create(bodyVelocity,TweenInfo.new(.5),{Velocity=targetVelocity}):Play()
			bodyVelocity.Parent = primaryPart

			if not flingActive then
				tweenService:Create(bodyGyro,TweenInfo.new(.5),{CFrame=rotation}):Play()
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
		if not spatialShieldWanted() then
			if next(spatialSoundVolumes) or next(suppressedSounds) or #soundInstances > 0 then clearSpatialShield() end
			spatialAccumulator = 0
		elseif spatialAccumulator >= SPATIAL_INTERVAL then
			spatialAccumulator %= SPATIAL_INTERVAL
			if settingValue("Spatial Shield") and tonumber(settingValue("Spatial Shield Threshold")) then
				local threshold = tonumber(settingValue("Spatial Shield Threshold"))
				for i = #soundInstances, 1, -1 do
					local sound = soundInstances[i]
					if not sound or not sound:IsDescendantOf(game) then
						if sound then restoreSpatialSound(sound); trackedSounds[sound] = nil end
						table.remove(soundInstances, i)
					elseif (gameSettings and gameSettings.MasterVolume or oldVolume) * sound.PlaybackLoudness * sound.Volume >= threshold then
						local limit = sound.Volume >= 0.55 and 0.5 or sound.Volume >= 0.2 and 0.1 or 0
						suppressedSounds[sound.SoundId] = limit
						local changed = suppressSound(sound, limit)
						if changed and soundSuppressionNotificationCooldown == 0 then
							notification("Spatial Shield", "A high-volume audio is being played (" .. sound.Name .. ") and it has been suppressed.", 4483362458)
							soundSuppressionNotificationCooldown = 15
						end
						-- Keep monitoring: playback and game-controlled volume can change.
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
		return spatialShieldWanted() or anonymousWanted()
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
				unregisterSound(instance)
				trackedText[instance] = nil
				altairValues.anonymousMaskedText[instance] = nil
				originalTextValues[instance] = nil
			end)
		elseif not wanted and descendantRemovingConn then
			descendantRemovingConn:Disconnect()
			descendantRemovingConn = nil
		end
	end

	if spatialSetting then
		spatialChangedHandler = function(...)
			if checkAltair() then
				if not spatialShieldWanted() then clearSpatialShield() end
				updateDescendantWatcher()
				if spatialShieldWanted() then refreshDescendantTracking() end
			end
			if type(previousSpatialChanged) == "function" then previousSpatialChanged(...) end
		end
		spatialSetting.onChanged = spatialChangedHandler
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
			if os.clock()-(altairValues.sessionMemory.lastSave or 0)>=60 then altairValues.sessionMemory:save() end
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
					altairValues.antiIdle:Set(antiIdle)
				end
			end

			local dragVisible = not settingValue("Hide Bar")
			if drag.Visible ~= dragVisible then
				drag.Visible = dragVisible
			end

			local promptGui = not useStudio and game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
			local promptOverlay = promptGui and promptGui:FindFirstChild("promptOverlay")
			local disconnectedRobloxUI = promptOverlay and promptOverlay:FindFirstChild("ErrorPrompt")

			local messageArea=disconnectedRobloxUI and disconnectedRobloxUI:FindFirstChild("MessageArea")
			local errorFrame=messageArea and messageArea:FindFirstChild("ErrorFrame")
			local errorMessage=errorFrame and errorFrame:FindFirstChild("ErrorMessage")
			local reasonPrompt=errorMessage and errorMessage.Text or ""
			local errorVisible=disconnectedRobloxUI and disconnectedRobloxUI.Visible
			if not errorVisible then promptedDisconnected=false end
			local disconnectType=altairValues.classifyDisconnect(reasonPrompt)
			if errorVisible and reasonPrompt~="" and not promptedDisconnected and disconnectType~="teleport" then
				promptedDisconnected=true
				disconnectedPrompt.Parent=promptGui
				if altairValues.disconnectAction then altairValues.disconnectAction:Disconnect()end


				if disconnectType == "ban" then
					disconnectedPrompt.Content.Text = "You've been banned, would you like to leave this server?"
					disconnectedPrompt.Action.Text = "Leave"


					altairValues.dialogMotion:Accent(disconnectedPrompt,Color3.new(0.819608, 0.164706, 0.164706))
				elseif disconnectType == "kick" then
					disconnectedPrompt.Content.Text = "You've been kicked, would you like to serverhop?"
					disconnectedPrompt.Action.Text = "Serverhop"


					altairValues.dialogMotion:Accent(disconnectedPrompt,Color3.new(0.0862745, 0.596078, 0.835294))
				elseif disconnectType == "network" then
					disconnectedPrompt.Content.Text = "You've lost connection, would you like to rejoin?"
					disconnectedPrompt.Action.Text = "Rejoin"


					altairValues.dialogMotion:Accent(disconnectedPrompt,Color3.new(0.862745, 0.501961, 0.0862745))
				end

				if disconnectType=="unknown"then
					disconnectedPrompt.Content.Text="Roblox reported a connection error. You can retry or dismiss this message."
					disconnectedPrompt.Action.Text="Rejoin"
				end
    altairValues.dialogMotion:Open(disconnectedPrompt,disconnectedRobloxUI)

				altairValues.disconnectAction=track(disconnectedPrompt.Action.MouseButton1Click:Connect(function()
					if disconnectType == "ban" then
						leaveExperience()
					elseif disconnectType == "kick" then
						task.spawn(serverhop)
					else
						rejoin()
					end
				end))
			end

			if Pro then
				-- all Pro checks here!

				-- Two-Way Adaptive Latency Checks
				if settingValue("Adaptive Latency Warning") and checkHighPing() then
					if altairValues.pingProfile.pingNotificationCooldown <= 0 then
						notification(
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
								notification(
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

-- Physics must start independently of optional developer checks and welcome UI.
task.spawn(runtime);


if not altairValues.continuation.quiet then
	BlinkSmartBar(2)
	task.wait(2)
	requireStartup()
	Toast("Welcome back. Nice to see you, "..lowerDisplayName)
end
requireStartup()
startupClaim.ready=true
end

local startupSuccess,startupError=pcall(initialise)
startupClaim.predecessorCleanup=false
if not startupSuccess then
	local report=ownsStartup()
	startupClaim:Cancel()
	if report then warn("Altair | Startup error: "..tostring(startupError))end
elseif not startupClaim.ready then startupClaim:Cancel()end
