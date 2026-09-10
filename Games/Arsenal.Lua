--[[

	Arsenal is a free-for-all gun game with a weapon ladder. This script adds ESP,
	aim assist, triggerbot, recoil control and hitbox expansion. It also tracks
	session stats and shows the current target's weapon and level.

	Altair integration: if Altair is present, Arsenal will use its toast and
	notification system instead of printing to the console.

]]
	
--------------------------------------------------------------------------------
-- experience check
--------------------------------------------------------------------------------

if game.PlaceId ~= 286090429 then
	local api = getgenv().Altair

	if type(api) == "table" and type(api.Toast) == "function" then
		pcall(
			api.Toast,
			"Arsenal script aborted - this experience is not Arsenal.",
			Color3.fromRGB(255, 75, 75)
		)
	else
		warn("Arsenal | Wrong experience - expected PlaceId 286090429.")
	end

	return
end


local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams              = game:GetService("Teams")
-- NOT `game:GetService("CoreGui")`. On Volt the script runs on a thread without
-- the Plugin capability and that call THROWS ("The current thread cannot access
-- 'CoreGui'") instead of returning nil - at the top of the file it took the whole
-- script down before a single line of it ran.
local CoreGui
do
	local ok, svc = pcall(game.GetService, game, "CoreGui")
	CoreGui = ok and svc or nil
end

local plr    = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ENV = getgenv()
local GEN = (ENV.__ARSENAL or 0) + 1
ENV.__ARSENAL = GEN

--------------------------------------------------------------------------------
-- Altair integration
--------------------------------------------------------------------------------

local function altairCall(name, ...)
	local api = ENV.Altair
	local fn = type(api) == "table" and api[name]
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function altairToast(text, color)
	local api = ENV.Altair
	if type(api) ~= "table" or type(api.Toast) ~= "function" then
		print(text)
		return false
	end

	-- New Altair API: let Arsenal explicitly perform ONE SmartBar blink using
	-- the exact same colour as the toast. Toast is told not to launch its own
	-- blink, preventing the old double-tween/frozen-SmartBar problem.
	if api.SupportsColoredSmartBarBlink
		and api.ToastSupportsSkipBlink
		and type(api.BlinkSmartBar) == "function"
	then
		local shown = pcall(api.Toast, text, color, nil, true)
		if shown then
			pcall(api.BlinkSmartBar, 1, color)
			return true
		end
		return false
	end

	-- Backwards compatibility with an older Altair build.
	return pcall(api.Toast, text, color)
end

local function altairNotify(title, description, image)
	if altairCall("QueueNotification", title, description, image) then return true end
	return altairToast(title .. " - " .. description)
end

local RESULT_WIN_COLOR = Color3.fromRGB(255, 205, 55)
local RESULT_LOSS_COLOR = Color3.fromRGB(255, 75, 75)

--------------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------------

local CONFIG = {
	-- ESP ----------------------------------------------------------------------
	box        = true,
	boxFilled  = false,
	name       = true,
	health     = true,
	hpText     = true,
	weapon     = true,     -- derived from Status.Level, see the header
	level      = true,     -- the gun-game level itself
	kills      = false,    -- kills / streak in the info line
	distance   = true,
	tracer     = false,
	headDot    = true,
	skeleton   = false,
	chams      = false,
	teamESP    = false,
	visCheck   = true,
	offScreen  = true,     -- arrow at the screen edge for enemies behind you
	maxDist    = 1500,
	textSize   = 14,
	textFont   = "System",
	textOutline = true,
	textShrink = false,

	colCham    = Color3.fromRGB(255, 72, 88),
	colChamOwn = false,
	colFov     = Color3.fromRGB(255, 255, 255),
	colLeader  = Color3.fromRGB(255, 200, 70),
	markLeader = true,     -- the player closest to the last level gets his own colour

	chamStyle  = "Fill",
	chamRainbow = false,
	chamByHealth = false,

	-- who counts as a target ---------------------------------------------------
	-- Arsenal's standard mode is a free-for-all, so "everybody" is the honest
	-- default. Auto reads the mode name out of the HUD and only switches to a
	-- team check when the mode actually says so.
	teamMode   = "Auto",   -- Auto | Everyone (FFA) | Team check

	-- aim assist ---------------------------------------------------------------
	-- Core camera movement follows the simple CFrame:Lerp aim from Arsenal.Lua.
	-- FOV, sticky targeting and the existing Arsenal target filters stay intact.
	aim        = false,
	aimPart    = "Head",   -- Head | Torso | Hitbox | Nearest
	aimPick    = "Crosshair", -- Crosshair | Closest | Lowest HP | Lowest level
	aimSticky  = true,
	aimVisible = true,
	aimMaxDist = 1500,
	aimOnlyGun = true,
	aimAir     = "Always", -- Always | Only grounded | Only airborne

	aimFov     = 120,
	aimSmooth  = 15,      -- CFrame:Lerp alpha as a percentage; 15 = source's 0.15

	aimKillMs  = 250,
	aimCircle  = true,

	-- aim behavior -------------------------------------------------------------
	aimRandomPart = true,  -- when on, Aim at is ignored for the acquired target
	aimHeadChance = 50,    -- remaining chance uses torso/root
	aimDistancePart = false, -- <=5m torso, then guaranteed headshot out to aimHeadRangeM
	aimHeadRangeM = 50,    -- 5-50 metres; farther targets fall back to random/manual targeting
	aimPauseUI    = true,  -- pauses aim + triggerbot while Arsenal is visible
	panicKey      = "F1",

	-- trigger ------------------------------------------------------------------
	-- Enabled means armed; there is no separate activation key anymore.
	trig       = false,
	trigMode   = "Click",  -- Click | Hold
	trigHoldMs = 120,
	trigDelayMin = 40,
	trigDelayMax = 110,
	trigRefireMs = 90,
	trigHitPct = 100,
	trigHeadOnly = false,
	trigMaxDist = 1500,
	trigFov    = 0,
	trigOnlyGun = true,
	trigBurst  = 0,

	-- recoil -------------------------------------------------------------------
	rcs        = false,
	rcsPitch   = 70,
	rcsYaw     = 70,
	rcsAfter   = 1,
	rcsMaxDeg  = 4,

	-- hitbox -------------------------------------------------------------------
	hb         = false,
	hbSize     = 8,
	hbPart     = "Hitbox", -- Hitbox | HeadHB | Head | Hitbox + HeadHB
	hbTrans    = 100,      -- % transparency; 100 = fully invisible
	hbEnemy    = true,     -- enemies only
	hbEvery    = 0.5,      -- seconds between refreshes
}

-- There is no master switch on this panel and there deliberately is not one:
-- every drawing has its own row, so a second switch above them could only ever
-- mean "the row you just moved does nothing", which is what it was reported as.
-- The render pass still wants a cheap way out when the whole list is off, and
-- this is it - the flags themselves rather than a flag about the flags.
local DRAWINGS = {
	"box",
	"boxFilled",
	"name",
	"health",
	"hpText",
	"level",
	"weapon",
	"distance",
	"kills",
	"headDot",
	"skeleton",
	"tracer",
	"offScreen",
	"teamESP",
	"markLeader",
	"chams",
}

local function anyDrawing()
	for _, key in ipairs(DRAWINGS) do
		if CONFIG[key] then return true end
	end
	return false
end


local STATE = {
	note      = "",
	targets   = 0,
	target    = "-",
	weapon    = "-",
	level     = 0,
	shots     = 0,
	trigHits  = 0,
	trigOn    = false,
	sensY     = 0, sensP = 0, calibN = 0,
	kickY     = 0, kickP = 0, kickPeak = 0,
	underCross = "-",
	lastKey   = "-",
	clickHow  = "-",   -- which executor call actually delivers a shot, see pullTrigger
	touch     = false, -- this client has no mouse and no keyboard
	mode      = "-",
	sub       = "-",
	scoreR    = 0, scoreB = 0,
	aliveN    = 0,
	leader    = "-",
	lastWinner = "-",
	nextWep   = "-",
	ffa       = true,

	-- Script-session stats; these start at zero every time Arsenal is executed.
	sessionKills = 0,
	sessionDeaths = 0,
	sessionHeadshots = 0,
	sessionWins = 0,
	engaged   = false,     -- the aim actually moved the camera this frame
	waitMs    = 0,         -- reaction delay still to run on the current target
	breaking  = false,
	hbCount   = 0,
	panelOpen = false,
}

local COLOUR = {
	hpGood   = Color3.fromRGB(90, 220, 120),
	hpBad    = Color3.fromRGB(230, 80, 60),
	text     = Color3.fromRGB(235, 235, 240),
	black    = Color3.fromRGB(0, 0, 0),
	fov      = Color3.fromRGB(255, 255, 255),
}

local function note(text)
	STATE.note = tostring(text)
end

local function dimmed(colour)
	local h, s, v = Color3.toHSV(colour)
	return Color3.fromHSV(h, s * 0.9, v * 0.55)
end

--------------------------------------------------------------------------------
-- game state
--------------------------------------------------------------------------------

-- Everything about another player that this script needs is in Player.Status and
-- Player.ScoreFolder, both of which replicate in full. Read through one helper so
-- a missing child during a respawn is a fallback rather than an error.
local function pv(p, folder, child, fallback)
	local f = p:FindFirstChild(folder)
	if not f then return fallback end
	local v = f:FindFirstChild(child)
	if not v then return fallback end
	local ok, value = pcall(function() return v.Value end)
	if not ok then return fallback end
	return value
end

local function statusTeam(p)
	return tostring(pv(p, "Status", "Team", ""))
end

local SESSION_SCORE_FIELDS = {
	sessionKills = "Kills",
	sessionDeaths = "Deaths",
	sessionHeadshots = "Headshots",
}

local lastSessionScore = {}

local function updateSessionScore()
	for stateKey, scoreName in pairs(SESSION_SCORE_FIELDS) do
		local current = tonumber(pv(plr, "ScoreFolder", scoreName, nil))
		local previous = lastSessionScore[stateKey]

		if current ~= nil then
			if previous ~= nil and current > previous then
				STATE[stateKey] += current - previous
			end

			-- A lower value means Arsenal reset/replaced the score counter.
			-- Rebase here so the next kill/death/headshot still counts correctly.
			lastSessionScore[stateKey] = current
		end
	end
end

local function dominantTeamColour(kind)
	for _, team in ipairs(Teams:GetTeams()) do
		local c = team.TeamColor.Color
		if kind == "red" and c.R > c.G * 1.15 and c.R > c.B * 1.15 then
			return c
		elseif kind == "blue" and c.B > c.R * 1.15 and c.B > c.G * 1.15 then
			return c
		end
	end
end

local function playerTeamColour(p)
	local code = statusTeam(p):upper()

	-- Arsenal reports these replicated team codes even in modes where Player.Team
	-- can disagree. Resolve them to the actual Team service colour when possible.
	if code == "TRC" then
		return dominantTeamColour("red") or BrickColor.new("Bright red").Color
	elseif code == "TBC" then
		return Color3.fromRGB(65, 145, 255)
	end

	-- For any other game/team code, use the player's actual Roblox TeamColor.
	local ok, colour = pcall(function()
		return p.TeamColor.Color
	end)
	if ok and colour then return colour end

	return Color3.fromRGB(210, 210, 215)
end

local function levelOf(p)
	return tonumber(pv(p, "Status", "Level", 0)) or 0
end

-- The gun-game ladder. ReplicatedStorage.Levels holds one StringValue per level,
-- named "1".."32", and the value is the weapon that level hands out. In the
-- default mode that makes an enemy's weapon exactly knowable from a number that
-- replicates, which is the one thing EquippedWep refuses to tell anybody.
-- NOT cached, and that is deliberate. The first build cached level -> weapon
-- once, and then the server changed the mode from "Automatics" to "Legacy
-- Competitive" and REWROTE the whole folder underneath it: level 1 was M4A1
-- before the switch and SCAR-L after it, while the panel still printed M4A1.
-- The ladder is per mode, so it is read fresh every time - a FindFirstChild on
-- a 32 entry folder is a hash lookup and costs nothing at ten players a frame.
local LevelsFolder = ReplicatedStorage:FindFirstChild("Levels")

local function weaponForLevel(lvl)
	if lvl <= 0 then return "" end
	if not LevelsFolder or not LevelsFolder.Parent then
		LevelsFolder = ReplicatedStorage:FindFirstChild("Levels")
	end
	local v = LevelsFolder and LevelsFolder:FindFirstChild(tostring(lvl))
	return (v and tostring(v.Value)) or ""
end

local MAXLEVEL = 0
if LevelsFolder then
	for _, c in ipairs(LevelsFolder:GetChildren()) do
		local n = tonumber(c.Name)
		if n and n > MAXLEVEL then MAXLEVEL = n end
	end
end

-- A dead body is cleaned up in this game, but a character can also exist for a
-- second before the Humanoid is ready, so both halves are checked - and
-- Status.Alive is checked on top because a player sitting in the lobby menu
-- still has a character parented at y = -403.
local function alive(p)
	local char = p.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	if pv(p, "Status", "Alive", true) == false then return nil end
	return char, hum, root
end

-- Free-for-all is the default mode, and in a free-for-all a team check would
-- simply hide half the enemies. Auto only turns the check on when the HUD says
-- the mode is a team one.
local Gui = plr:WaitForChild("PlayerGui")

local function hudText(path, fallback)
	local node = Gui:FindFirstChild("GUI")
	if not node then return fallback end
	for _, step in ipairs(path) do
		node = node:FindFirstChild(step)
		if not node then return fallback end
	end
	local ok, value = pcall(function() return node.Text end)
	if not ok or value == nil then return fallback end
	return tostring(value)
end

-- Auto is a NAME LIST, not a measurement, and it is worth being honest about
-- why. Everything that could have been measured turned out not to separate the
-- two cases: `Player.Status.Team` reads TRC/TBC for every deployed player in a
-- gun game as well as in a round mode, `ReplicatedStorage.NoTeam` was false in
-- both, and `Player.FriendlyFire` was false in both. So the mode caption in the
-- HUD is what is left, and the dropdown next to it exists precisely because a
-- name list will eventually meet a mode nobody wrote down.
local TEAM_MODE_WORDS = {
	"team", "tdm", "competitive", "capture", "flag", "domination",
	"king", "control", "payload", "escort", "siege",
}

local function ffaNow()
	if CONFIG.teamMode == "Everyone (FFA)" then return true end
	if CONFIG.teamMode == "Team check" then return false end
	local mode = string.lower(STATE.mode or "")
	for _, word in ipairs(TEAM_MODE_WORDS) do
		if mode:find(word, 1, true) then return false end
	end
	return true
end

local function isEnemy(p)
	if p == plr then return false end
	if STATE.ffa then return true end
	local mine, theirs = statusTeam(plr), statusTeam(p)
	if mine == "" or theirs == "" then return true end
	return mine ~= theirs
end

--------------------------------------------------------------------------------
-- line of sight
--------------------------------------------------------------------------------
--
-- The filter is "everything a BULLET would not stop on", which is not the same
-- as "everything you cannot see", and on this map that distinction is worth 72
-- parts. Two families of them, both found by measurement:
--
--  * `Map.Clips` - the movement clip brushes, collision group Clips, fully
--    transparent, CanQuery true. Solid to a player, invisible, and bullets pass
--    straight through. The same trap as Counter Blox.
--  * `Map.Ignore` - a folder whose NAME says ignore but whose contents are
--    mixed: 256 opaque collidable parts (real geometry, must stay) sitting next
--    to 37 `Floors`, 8 literally named `RAYCAST`, 4 `MainSt` and 2 `Glass`,
--    every one of them transparency 1, CanCollide FALSE and CanQuery TRUE.
--    Dropping the whole folder would make real walls transparent to the wall
--    check; keeping it whole made an enemy at 49 m read as blocked by
--    `Map.Ignore.Floors.RAYCAST`. Measured on Standard.
--
-- So the rule is a PROPERTY test rather than a name list: a part that is fully
-- transparent AND not collidable is neither visible nor solid, so nothing a
-- bullet can stop on - whatever it happens to be called. The scan is 8.4 ms
-- over 12257 descendants, so it runs on a timer in its own thread, never per
-- frame.

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local trigParams = RaycastParams.new()
trigParams.FilterType = Enum.RaycastFilterType.Exclude
trigParams.IgnoreWater = true

-- Every part in the map that is invisible AND not collidable. Rebuilt on a
-- timer and whenever the Map model itself is replaced, which is what a map
-- change looks like from here.
local ghosts = {}
local ghostMap = nil

local function scanGhosts()
	local map = workspace:FindFirstChild("Map")
	if not map then ghosts = {} ghostMap = nil return 0 end
	local list = {}
	for _, c in ipairs(map:GetDescendants()) do
		if c:IsA("BasePart") and c.Transparency >= 1 and not c.CanCollide then
			table.insert(list, c)
		end
	end
	ghosts = list
	ghostMap = map
	return #list
end

local function ignoreList()
	local list = {}
	for _, name in ipairs({ "Ray_Ignore", "Debris", "Sounds", "Destructable" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(list, f) end
	end
	local map = workspace:FindFirstChild("Map")
	if map then
		local clips = map:FindFirstChild("Clips")
		if clips then table.insert(list, clips) end
	end
	for _, part in ipairs(ghosts) do
		if part.Parent then table.insert(list, part) end
	end
	-- The third-person weapon models. Every part in them is CanQuery false
	-- already, so this is belt and braces, but it costs one table insert.
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name:sub(1, 6) == "HWRAP_" then table.insert(list, c) end
	end
	return list
end

local function refreshFilter()
	local base = ignoreList()

	local espList = {}
	for _, v in ipairs(base) do table.insert(espList, v) end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(espList, p.Character) end
	end
	rayParams.FilterDescendantsInstances = espList

	-- The trigger's ray must NOT exclude the other characters: the enemy's body
	-- is exactly what it is looking for.
	local trigList = {}
	for _, v in ipairs(base) do table.insert(trigList, v) end
	if plr.Character then table.insert(trigList, plr.Character) end
	trigParams.FilterDescendantsInstances = trigList
end

local function visible(worldPos)
	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, worldPos - origin, rayParams)
	return hit == nil
end

STATE.ghosts = 0
task.spawn(function()
	while ENV.__ARSENAL == GEN do
		local ok, err = pcall(function()
			local map = workspace:FindFirstChild("Map")
			if map ~= ghostMap then
				STATE.ghosts = scanGhosts()
				refreshFilter()
				note("map scan: " .. STATE.ghosts .. " see-through parts filtered")
			end
		end)
		if not ok then note("ghosts: " .. tostring(err)) end
		task.wait(3)
	end
end)

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local FONTS = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local FONTLIST = { "System", "UI", "Plex", "Monospace" }

local function fontId()
	local id = FONTS[CONFIG.textFont]
	if id == nil then return 1 end
	if Drawing.Fonts then
		local named = Drawing.Fonts[CONFIG.textFont]
		if named ~= nil then return named end
	end
	return id
end

local drawn = {}
local pool  = {}

if _G.__ARSENAL_POOL then
	for _, obj in ipairs(_G.__ARSENAL_POOL) do pcall(function() obj:Remove() end) end
end
_G.__ARSENAL_POOL = pool

local function make(kind, props)
	local obj = Drawing.new(kind)
	obj.Visible = false
	for k, v in pairs(props or {}) do obj[k] = v end
	table.insert(pool, obj)
	return obj
end

local BONES = {
	{ "Head", "UpperTorso" },
	{ "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" },
	{ "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
	{ "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" },
	{ "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" },
	{ "RightLowerLeg", "RightFoot" },
}

local function objectsFor(p)
	local set = drawn[p]
	if set then return set end
	set = {
		outline  = make("Square", { Thickness = 3, Filled = false, ZIndex = 1,
			Color = COLOUR.black, Transparency = 0.6 }),
		box      = make("Square", { Thickness = 1, Filled = false, ZIndex = 2 }),
		fill     = make("Square", { Filled = true, ZIndex = 0, Transparency = 0.18 }),
		hpBg     = make("Square", { Filled = true, ZIndex = 1, Color = COLOUR.black,
			Transparency = 0.6 }),
		hp       = make("Square", { Filled = true, ZIndex = 2 }),
		name     = make("Text", { Size = 13, Center = true, Outline = true,
			Font = 1, Color = COLOUR.text, ZIndex = 3 }),
		info     = make("Text", { Size = 12, Center = true, Outline = true,
			Font = 1, Color = COLOUR.text, ZIndex = 3 }),
		tracer   = make("Line", { Thickness = 1, ZIndex = 1 }),
		head     = make("Circle", { Thickness = 1, Filled = false, NumSides = 14,
			ZIndex = 3 }),
		arrow    = make("Triangle", { Thickness = 1, Filled = true, ZIndex = 2,
			Transparency = 0.75 }),
		bones    = {},
	}
	for i = 1, #BONES do
		set.bones[i] = make("Line", { Thickness = 1, ZIndex = 2 })
	end
	drawn[p] = set
	return set
end

local function hideSet(set)
	set.outline.Visible = false
	set.box.Visible     = false
	set.fill.Visible    = false
	set.hpBg.Visible    = false
	set.hp.Visible      = false
	set.name.Visible    = false
	set.info.Visible    = false
	set.tracer.Visible  = false
	set.head.Visible    = false
	set.arrow.Visible   = false
	for _, line in ipairs(set.bones) do line.Visible = false end
end

local function hideAll()
	for _, set in pairs(drawn) do hideSet(set) end
end

--------------------------------------------------------------------------------
-- chams
--------------------------------------------------------------------------------

-- gethui() can throw rather than return nil, and CoreGui is nil on an executor
-- that refuses it (Volt) - so PlayerGui is the last resort, where a Highlight
-- renders exactly the same.
local hlRoot
pcall(function() hlRoot = gethui and gethui() end)
hlRoot = hlRoot or CoreGui or plr:WaitForChild("PlayerGui", 10)
local chamsFolder = hlRoot:FindFirstChild("SeluxArsenalChams")
if chamsFolder then pcall(function() chamsFolder:Destroy() end) end
chamsFolder = Instance.new("Folder")
chamsFolder.Name = "SeluxArsenalChams"
chamsFolder.Parent = hlRoot

local highlights = {}

local CHAM_STYLES = {
	["Fill"]         = { fill = 0.35, out = 0,    depth = "AlwaysOnTop" },
	["Solid"]        = { fill = 0,    out = 0,    depth = "AlwaysOnTop" },
	["Outline"]      = { fill = 1,    out = 0,    depth = "AlwaysOnTop" },
	["Glow"]         = { fill = 0.78, out = 0.15, depth = "AlwaysOnTop", boost = 1.6 },
	["Ghost"]        = { fill = 0.6,  out = 0.4,  depth = "AlwaysOnTop", boost = 0.55 },
	["Wall only"]    = { fill = 0.35, out = 0,    depth = "Occluded" },
	["Wall outline"] = { fill = 1,    out = 0,    depth = "Occluded" },
}
local CHAM_LIST = { "Fill", "Solid", "Outline", "Glow", "Ghost",
	"Wall only", "Wall outline" }

local function chamFor(p)
	local hl = highlights[p]
	if hl and hl.Parent then return hl end
	hl = Instance.new("Highlight")
	hl.FillTransparency = 0.35
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = chamsFolder
	highlights[p] = hl
	return hl
end

local function chamColour(base, hum)
	if CONFIG.chamRainbow then
		return Color3.fromHSV((os.clock() * 0.25) % 1, 0.85, 1)
	end
	if CONFIG.chamByHealth and hum then
		local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		return COLOUR.hpBad:Lerp(COLOUR.hpGood, frac)
	end
	if CONFIG.colChamOwn then return CONFIG.colCham end
	return base
end

local function applyCham(hl, base, hum)
	local style = CHAM_STYLES[CONFIG.chamStyle] or CHAM_STYLES["Fill"]
	local col = chamColour(base, hum)
	if style.boost then
		local h, s, v = Color3.toHSV(col)
		col = Color3.fromHSV(h, math.clamp(s * (style.boost > 1 and 0.75 or 1), 0, 1),
			math.clamp(v * style.boost, 0, 1))
	end
	hl.FillTransparency = style.fill
	hl.OutlineTransparency = style.out
	hl.DepthMode = Enum.HighlightDepthMode[style.depth]
	hl.FillColor = col
	hl.OutlineColor = col
	hl.Enabled = true
end

local function clearChams()
	for _, hl in pairs(highlights) do
		if hl and hl.Parent then hl.Adornee = nil hl.Enabled = false end
	end
end

--------------------------------------------------------------------------------
-- the render pass
--------------------------------------------------------------------------------

local fovCircle = make("Circle", { Thickness = 1, NumSides = 48, Filled = false,
	Color = COLOUR.fov, Transparency = 0.5, ZIndex = 1 })
local trigCircle = make("Circle", { Thickness = 1, NumSides = 32, Filled = false,
	Color = Color3.fromRGB(255, 210, 90), Transparency = 0.45, ZIndex = 1 })

local function centre()
	local vp = camera.ViewportSize
	return Vector2.new(vp.X / 2, vp.Y / 2)
end

local filterAt = 0
local aimFovNow = CONFIG.aimFov      -- filled in by aimNumbers(), drawn here

local function renderPass()
	if ENV.__ARSENAL ~= GEN then return end

	local mid = centre()
	fovCircle.Visible = CONFIG.aim and CONFIG.aimCircle
	if fovCircle.Visible then
		fovCircle.Position = mid
		fovCircle.Radius = aimFovNow
		fovCircle.Color = CONFIG.colFov
	end
	trigCircle.Visible = CONFIG.trig and CONFIG.trigFov > 0
	if trigCircle.Visible then
		trigCircle.Position = mid
		trigCircle.Radius = CONFIG.trigFov
	end

	if not anyDrawing() then
		hideAll()
		clearChams()
		STATE.targets = 0
		return
	end

	local now = os.clock()
	if now - filterAt > 1 then
		filterAt = now
		refreshFilter()
	end

	local vp = camera.ViewportSize
	local camPos = camera.CFrame.Position
	local count = 0

	-- Who is closest to the last level. In a gun game that is the only piece of
	-- information that decides the match, and the HUD only shows it as a small
	-- number in a corner.
	local leaderName, leaderLvl = nil, -1
	if CONFIG.markLeader then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= plr then
				local lvl = levelOf(p)
				if lvl > leaderLvl then leaderName, leaderLvl = p.Name, lvl end
			end
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local set = objectsFor(p)
		local char, hum, root = alive(p)
		local enemy = isEnemy(p)
		local wanted = char and p ~= plr and (enemy or CONFIG.teamESP)

		if not wanted then
			hideSet(set)
			local hl = highlights[p]
			if hl then hl.Enabled = false hl.Adornee = nil end
		else
			local dist = (camPos - root.Position).Magnitude
			if dist > CONFIG.maxDist then
				hideSet(set)
				local hl = highlights[p]
				if hl then hl.Enabled = false hl.Adornee = nil end
			else
				local head = char:FindFirstChild("HeadHB") or char:FindFirstChild("Head")
				local seen = true
				if CONFIG.visCheck then
					seen = visible((head or root).Position)
				end

				local base = playerTeamColour(p)
				local isLeader = CONFIG.markLeader and leaderName == p.Name and leaderLvl > 0
				local col = seen and base or dimmed(base)

				-- Never Model:GetBoundingBox() - see the genre file. The projected
				-- distance between the top of the head and the lower foot IS the
				-- on-screen height, so it scales with range for free.
				local headPart = char:FindFirstChild("Head")
				local lf, rf = char:FindFirstChild("LeftFoot"), char:FindFirstChild("RightFoot")

				local topPos = headPart
					and (headPart.Position + Vector3.new(0, headPart.Size.Y / 2 + 0.35, 0))
					or (root.Position + Vector3.new(0, 3, 0))

				local botPos
				local low = lf
				if lf and rf then low = (lf.Position.Y <= rf.Position.Y) and lf or rf
				elseif rf then low = rf end
				if low then
					botPos = low.Position - Vector3.new(0, low.Size.Y / 2, 0)
				else
					botPos = root.Position - Vector3.new(0, 3, 0)
				end

				local sTop = camera:WorldToViewportPoint(topPos)
				local sBot = camera:WorldToViewportPoint(botPos)

				local behind = sTop.Z <= 0 or sBot.Z <= 0
				local h = math.max(math.abs(sBot.Y - sTop.Y), 4)
				local w = h * 0.52
				local cx = (sTop.X + sBot.X) / 2
				local minX, minY = cx - w / 2, math.min(sTop.Y, sBot.Y)
				local maxX, maxY = minX + w, minY + h

				local onScreen = not behind
					and maxX > 0 and minX < vp.X and maxY > 0 and minY < vp.Y

				if not onScreen then
					hideSet(set)
					-- An off-screen enemy still gets an edge marker if that is on -
					-- in a free-for-all the shot that kills you almost always comes
					-- from a direction you are not looking at.
					if CONFIG.offScreen and not (dist > CONFIG.maxDist) then
						local rel = camera.CFrame:PointToObjectSpace(root.Position)
						local ang = math.atan2(rel.X, -rel.Z)
						if behind then ang = math.atan2(rel.X, math.abs(rel.Z)) end
						local r = math.min(vp.X, vp.Y) * 0.34
						local px = mid.X + math.sin(ang) * r
						local py = mid.Y - math.cos(ang) * r * 0.35
						local dir = Vector2.new(px - mid.X, py - mid.Y)
						if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
						dir = dir.Unit
						local side = Vector2.new(-dir.Y, dir.X)
						set.arrow.Visible = true
						set.arrow.PointA = Vector2.new(px, py) + dir * 9
						set.arrow.PointB = Vector2.new(px, py) - dir * 6 + side * 6
						set.arrow.PointC = Vector2.new(px, py) - dir * 6 - side * 6
						set.arrow.Color = col
					end
					local hl = highlights[p]
					if hl and not CONFIG.chams then hl.Enabled = false end
				else
					count = count + 1
					local pos = Vector2.new(minX, minY)
					local siz = Vector2.new(w, h)

					set.box.Visible = CONFIG.box
					set.outline.Visible = CONFIG.box
					if CONFIG.box then
						set.box.Position = pos      set.box.Size = siz
						set.box.Color = col
						set.outline.Position = pos  set.outline.Size = siz
					end

					set.fill.Visible = CONFIG.box and CONFIG.boxFilled
					if set.fill.Visible then
						set.fill.Position = pos  set.fill.Size = siz
						set.fill.Color = col
					end

					set.hpBg.Visible = CONFIG.health
					set.hp.Visible   = CONFIG.health
					if CONFIG.health then
						local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						set.hpBg.Position = Vector2.new(minX - 6, minY)
						set.hpBg.Size     = Vector2.new(3, h)
						set.hp.Position   = Vector2.new(minX - 6, minY + h * (1 - frac))
						set.hp.Size       = Vector2.new(3, h * frac)
						set.hp.Color      = COLOUR.hpBad:Lerp(COLOUR.hpGood, frac)
					end

					local ts = CONFIG.textSize
					if CONFIG.textShrink then
						ts = math.clamp(h * 0.22, math.max(12, CONFIG.textSize - 2),
							CONFIG.textSize)
					end
					ts = math.floor(ts + 0.5)
					local face = fontId()

					set.name.Visible = CONFIG.name
					if CONFIG.name then
						set.name.Size = ts
						set.name.Font = face
						set.name.Outline = CONFIG.textOutline
						set.name.Position = Vector2.new(minX + w / 2, minY - (ts + 3))
						set.name.Text = p.Name .. (isLeader and " ★" or "")
						set.name.Color = col
					end

					local bits = {}
					local lvl = levelOf(p)
					if CONFIG.level and lvl > 0 then
						table.insert(bits, "L" .. tostring(lvl))
					end
					if CONFIG.weapon then
						local wep = weaponForLevel(lvl)
						if wep ~= "" then table.insert(bits, wep) end
					end
					if CONFIG.distance then
						table.insert(bits, string.format("%dm", math.floor(dist)))
					end
					if CONFIG.hpText then
						table.insert(bits, string.format("%d", math.floor(hum.Health)))
					end
					if CONFIG.kills then
						local k = tonumber(pv(p, "ScoreFolder", "Kills", 0)) or 0
						local s = tonumber(pv(p, "ScoreFolder", "Streak", 0)) or 0
						table.insert(bits, string.format("%d/%d", k, s))
					end
					set.info.Visible = #bits > 0
					if set.info.Visible then
						set.info.Size = math.max(12, ts - 1)
						set.info.Font = face
						set.info.Outline = CONFIG.textOutline
						set.info.Position = Vector2.new(minX + w / 2, maxY + 2)
						set.info.Text = table.concat(bits, "  ")
						set.info.Color = col
					end

					set.tracer.Visible = CONFIG.tracer
					if CONFIG.tracer then
						set.tracer.From = Vector2.new(vp.X / 2, vp.Y)
						set.tracer.To   = Vector2.new(minX + w / 2, maxY)
						set.tracer.Color = col
					end

					set.head.Visible = CONFIG.headDot and head ~= nil
					if set.head.Visible then
						local sp = camera:WorldToViewportPoint(head.Position)
						set.head.Position = Vector2.new(sp.X, sp.Y)
						set.head.Radius = math.max(1.5, h * 0.075)
						set.head.Color = col
					end
					set.arrow.Visible = false

					if CONFIG.skeleton then
						for i, bone in ipairs(BONES) do
							local a = char:FindFirstChild(bone[1])
							local b = char:FindFirstChild(bone[2])
							local line = set.bones[i]
							if a and b then
								local pa = camera:WorldToViewportPoint(a.Position)
								local pb = camera:WorldToViewportPoint(b.Position)
								if pa.Z > 0 and pb.Z > 0 then
									line.Visible = true
									line.From = Vector2.new(pa.X, pa.Y)
									line.To   = Vector2.new(pb.X, pb.Y)
									line.Color = col
								else
									line.Visible = false
								end
							else
								line.Visible = false
							end
						end
					else
						for _, line in ipairs(set.bones) do line.Visible = false end
					end

					if CONFIG.chams then
						local hl = chamFor(p)
						hl.Adornee = char
						applyCham(hl, base, hum)
					else
						local hl = highlights[p]
						if hl then hl.Enabled = false hl.Adornee = nil end
					end
				end
			end
		end
	end

	STATE.targets = count
end

--------------------------------------------------------------------------------
-- key binding
--------------------------------------------------------------------------------

local function keyDisplay(name)
	local n = tostring(name)
	local side = n:match("^MouseButton(%d)$")
	if side then return "MOUSE " .. side end
	return string.upper(n)
end

-- Indexing a Roblox Enum with a name it does not have THROWS instead of
-- returning nil, so both lookups are wrapped and the answer is cached.
local keyCache = {}

local function resolveKey(name)
	local hit = keyCache[name]
	if hit ~= nil then return hit end
	local entry = false
	if name:sub(1, 11) == "MouseButton" then
		local ok, value = pcall(function() return Enum.UserInputType[name] end)
		if ok and value then entry = { mouse = value } end
	else
		local ok, value = pcall(function() return Enum.KeyCode[name] end)
		if ok and value then entry = { key = value } end
	end
	keyCache[name] = entry
	return entry
end

local function keyHeld(name)
	if not name or name == "" then return false end
	local spec = resolveKey(name)
	if not spec then return false end
	if spec.mouse then return UserInputService:IsMouseButtonPressed(spec.mouse) end
	return UserInputService:IsKeyDown(spec.key)
end

local capturing = nil
local armedGuard = false

local function arm(fn)
	capturing = fn
	armedGuard = true
	task.spawn(function()
		while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
			task.wait()
		end
		task.wait(0.06)
		armedGuard = false
	end)
end

local function capture(name)
	local fn = capturing
	if not fn then return end
	capturing = nil
	armedGuard = false
	STATE.lastKey = tostring(name)
	fn(name)
end

UserInputService.InputBegan:Connect(function(input, typing)
	if ENV.__ARSENAL ~= GEN then return end
	if capturing and not armedGuard
		and input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Escape then capture(nil) return end
		if input.KeyCode == Enum.KeyCode.Unknown then return end
		capture(input.KeyCode.Name)
		return
	end
	-- The panic key. One press and every input-touching feature is off - the
	-- ESP stays, because a drawing has never had to be panicked away.
	if typing or capturing then return end
	if input.UserInputType == Enum.UserInputType.Keyboard
		and CONFIG.panicKey ~= "" then
		local spec = resolveKey(CONFIG.panicKey)
		if spec and spec.key and input.KeyCode == spec.key then
			CONFIG.aim, CONFIG.trig, CONFIG.rcs = false, false, false
			note("PANIC - aim, trigger and recoil off")
			altairNotify("Arsenal safety", "Panic enabled - aim, trigger and recoil are off.")
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if ENV.__ARSENAL ~= GEN or not capturing or armedGuard then return end
	local name = input.UserInputType.Name
	if name:sub(1, 11) ~= "MouseButton" then return end
	capture(name)
end)

--------------------------------------------------------------------------------
-- a client with no mouse and no keyboard
--------------------------------------------------------------------------------
--
-- Everything above this point is a mouse or a keyboard, and a phone has neither.
-- The same four breaks measured in counterblox.lua are all present here, and each
-- is fatal on its own:
--
--   * `keyHeld` ends in IsMouseButtonPressed / IsKeyDown, which are false forever
--     on a client with MouseEnabled and KeyboardEnabled both off. Aim and trigger
--     no longer depend on activation keys; the panic key remains keyboard-only.
--   * `firing()` read MouseButton1, so "While firing", the shot counter and the
--     recoil pass were dead too.
--   * the key recorder takes Keyboard on InputBegan and MouseButton on InputEnded
--     and nothing else, so a phone could not bind its way out of it.
--   * Roblox does NOT synthesise MouseMovement on a touch client - a camera drag
--     arrives as UserInputType.Touch - so the sensitivity calibration never got a
--     sample and rcsPass returned at its `sensYaw == 0` guard every frame.
--
-- Everything below is ADDITIVE: every mouse path is untouched, so a desktop
-- behaves exactly as before.
local TOUCH = false
pcall(function()
	TOUCH = UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
		and not UserInputService.KeyboardEnabled
end)
-- Test hook, like _G.__SEL_VIEWPORT in the panel template: a desktop cannot be
-- given a phone's input, and a branch that cannot be run on the machine it was
-- written on is a branch that ships unverified. Never set in normal use.
if _G.__ARSENAL_FORCE_TOUCH then TOUCH = true end
STATE.touch = TOUCH

-- Counting fingers with +1/-1 drifts the moment one InputEnded is missed (a finger
-- leaving over the Roblox top bar does that) and a count stuck at 1 would leave
-- "Screen held" permanently on. The set is keyed by the InputObject and re-checked
-- on read, so a stale entry removes itself.
local touches = setmetatable({}, { __mode = "k" })

local function screenHeld()
	local n = 0
	for input in pairs(touches) do
		local ok, state = pcall(function() return input.UserInputState end)
		if ok and state ~= Enum.UserInputState.End
			and state ~= Enum.UserInputState.Cancel then
			n = n + 1
		else
			touches[input] = nil
		end
	end
	return n > 0
end

UserInputService.InputBegan:Connect(function(input)
	if ENV.__ARSENAL ~= GEN then return end
	if input.UserInputType == Enum.UserInputType.Touch then touches[input] = true end
end)

UserInputService.InputEnded:Connect(function(input)
	if ENV.__ARSENAL ~= GEN then return end
	if input.UserInputType == Enum.UserInputType.Touch then touches[input] = nil end
end)

-- Set by pullTrigger. It is the only thing a touch client can know for certain
-- about shooting, and the shot counter and the recoil pass need exactly that.
local lastShotAt = -1e9

local function firing()
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return true
	end
	-- A raw screen touch is deliberately NOT firing: on a touch client the camera
	-- is dragged with a finger, so "a finger is down" is true almost continuously
	-- and would both mis-count every spray and starve the sensitivity calibration,
	-- which only samples while NOT firing.
	if TOUCH and os.clock() - lastShotAt < 0.35 then return true end
	return false
end

-- Can this device produce that binding at all? A key it cannot press leaves the
-- feature off forever with nothing on screen to say why, which is what a phone
-- got. An unreachable hotkey therefore falls back to holding the screen, so an old
-- saved config comes back working instead of dead.
local function reachable(name)
	if not name or name == "" then return false end
	local spec = resolveKey(name)
	if not spec then return false end
	local ok, enabled = pcall(function()
		if spec.mouse then return UserInputService.MouseEnabled end
		return UserInputService.KeyboardEnabled
	end)
	return ok and enabled and true or false
end

local function hotkeyHeld(name)
	if TOUCH and not reachable(name) then return screenHeld() end
	return keyHeld(name)
end

--------------------------------------------------------------------------------
-- the weapon in hand
--------------------------------------------------------------------------------
--
-- Arsenal keeps no Tool on the character, so the local weapon comes from the
-- same ladder the ESP uses for everybody else: Status.Level -> Levels[level] ->
-- ReplicatedStorage.Weapons[name]. The stat block is the whole thing: DMG,
-- FireRate, Ammo, StoredAmmo, Auto, Range, MaxSpread, Bullets, Falloff,
-- RecoilControl, ReloadTime and Speed%.
--
-- "Is this thing a gun" comes from CONTENT: a Weapons folder entry with an Ammo
-- above one and a FireRate shoots. The 173 entries in ReplicatedStorage.Melees
-- have a `Type` of Knife and no Ammo at all, so they answer no without a single
-- name being matched.

local WeaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
local MeleesFolder  = ReplicatedStorage:FindFirstChild("Melees")

local weaponCache = {}

local function weaponInfo()
	local name = weaponForLevel(levelOf(plr))
	if name == "" then return nil, "" end
	local cached = weaponCache[name]
	if cached ~= nil then return cached or nil, name end

	local folder = WeaponsFolder and WeaponsFolder:FindFirstChild(name)
	if not folder then
		if MeleesFolder and MeleesFolder:FindFirstChild(name) then
			local melee = { name = name, gun = false, melee = true, rate = 0.5,
				dmg = 0, ammo = 0, auto = false, range = 0, spread = 0,
				bullets = 1, reload = 0, stored = 0, speed = 0, falloff = 0,
				recoil = 0 }
			weaponCache[name] = melee
			return melee, name
		end
		weaponCache[name] = false
		return nil, name
	end

	local function num(child, fallback)
		local v = folder:FindFirstChild(child)
		return (v and tonumber(v.Value)) or fallback
	end
	local autoValue = folder:FindFirstChild("Auto")
	local info = {
		name    = name,
		dmg     = num("DMG", 0),
		rate    = num("FireRate", 0.1),
		ammo    = num("Ammo", 0),
		stored  = num("StoredAmmo", 0),
		spread  = num("MaxSpread", 0),
		bullets = num("Bullets", 1),
		range   = num("Range", 0),
		falloff = num("Falloff", 0),
		recoil  = num("RecoilControl", 0),
		reload  = num("ReloadTime", 0),
		speed   = num("Speed%", 0),
		auto    = autoValue ~= nil and autoValue.Value == true,
		melee   = false,
	}
	info.gun = info.ammo > 1 and info.rate > 0
	weaponCache[name] = info
	return info, name
end

local HEADPARTS = { Head = true, HeadHB = true, FakeHead = true }

local function gunGate(needGun)
	if not needGun then return true end
	local info = weaponInfo()
	return info ~= nil and info.gun
end

-- Arsenal has no scope BoolValue on the character, but it does have a very
-- Arsenal-shaped condition instead: half the kills in this game are taken in
-- mid-air, so the gate here is grounded/airborne rather than scoped.
local function airGate(mode)
	if mode == "Always" then return true end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return true end
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if mode == "Only grounded" then return grounded end
	return not grounded
end


--------------------------------------------------------------------------------
-- aim assist
--------------------------------------------------------------------------------

local lastKillAt = 0
local stickyTarget = nil
local randomPartFor = nil
local randomPartMode = nil
local currentAimMode = nil

local function clearRandomPart()
	randomPartFor, randomPartMode = nil, nil
end

local function aimActive()
	if not CONFIG.aim then return false end
	if CONFIG.aimPauseUI and STATE.panelOpen then return false end
	return true
end

local function aimNumbers()
	aimFovNow = CONFIG.aimFov
	return CONFIG.aimFov, math.clamp(CONFIG.aimSmooth / 100, 0.01, 1)
end

local function targetPart(char, mode)
	mode = mode or CONFIG.aimPart

	if mode == "Torso" then
		return char:FindFirstChild("UpperTorso")
			or char:FindFirstChild("HumanoidRootPart")
			or char:FindFirstChild("LowerTorso")
	end

	if mode == "Hitbox" then
		return char:FindFirstChild("Hitbox")
			or char:FindFirstChild("UpperTorso")
			or char:FindFirstChild("HumanoidRootPart")
	end

	if mode == "Nearest" then
		local mid = centre()
		local best, bestD

		for _, name in ipairs({ "HeadHB", "Head", "UpperTorso", "Hitbox", "HumanoidRootPart" }) do
			local part = char:FindFirstChild(name)
			if part then
				local sp = camera:WorldToViewportPoint(part.Position)
				if sp.Z > 0 then
					local d = (Vector2.new(sp.X, sp.Y) - mid).Magnitude
					if not bestD or d < bestD then
						best, bestD = part, d
					end
				end
			end
		end

		return best
	end

	return char:FindFirstChild("HeadHB")
		or char:FindFirstChild("Head")
		or char:FindFirstChild("HumanoidRootPart")
end

local function rollAimPart()
	return math.random(1, 100) <= CONFIG.aimHeadChance and "Head" or "Torso"
end

local STUD_TO_M = 0.28
local CLOSE_TORSO_M = 5

local function targetDistanceM(root)
	return root and (camera.CFrame.Position - root.Position).Magnitude * STUD_TO_M or math.huge
end

local function targetModeFor(player, newTarget, root)
	-- Roll once for every newly acquired player even if distance targeting is
	-- currently overriding it. If they later leave the distance zone, their
	-- original random roll is still waiting underneath.
	if CONFIG.aimRandomPart and (newTarget or randomPartFor ~= player or not randomPartMode) then
		randomPartFor = player
		randomPartMode = rollAimPart()
	end

	-- Distance targeting has highest priority.
	-- <= 5m: torso/root so somebody directly in your face is not an auto-headshot.
	-- > 5m through the chosen range: guaranteed head.
	-- Beyond the chosen range: fall back to the per-target randomizer/manual Aim at.
	if CONFIG.aimDistancePart then
		local metres = targetDistanceM(root)
		if metres <= CLOSE_TORSO_M then
			return "Torso"
		elseif metres <= CONFIG.aimHeadRangeM then
			return "Head"
		end
	end

	if CONFIG.aimRandomPart then
		return randomPartMode
	end

	clearRandomPart()
	return CONFIG.aimPart
end

local function candidatePart(char)
	-- Body randomisation should not change WHICH player wins the target-selection
	-- contest. Root is used only for candidate scoring; the actual aimed-at part
	-- is chosen after the player is acquired.
	if CONFIG.aimRandomPart then
		return char:FindFirstChild("HumanoidRootPart")
			or char:FindFirstChild("UpperTorso")
			or char:FindFirstChild("Head")
	end
	return targetPart(char, CONFIG.aimPart)
end

local function pickTarget()
	local fov = select(1, aimNumbers())
	local mid = centre()
	local camPos = camera.CFrame.Position
	local best, bestScore

	for _, p in ipairs(Players:GetPlayers()) do
		if isEnemy(p) then
			local char, hum, root = alive(p)
			if char then
				local part = candidatePart(char)
				if part and (camPos - root.Position).Magnitude <= CONFIG.aimMaxDist then
					local sp = camera:WorldToViewportPoint(part.Position)
					if sp.Z > 0 then
						local px = (Vector2.new(sp.X, sp.Y) - mid).Magnitude
						if px <= fov and ((not CONFIG.aimVisible) or visible(part.Position)) then
							local score
							if CONFIG.aimPick == "Closest" then
								score = (camPos - root.Position).Magnitude
							elseif CONFIG.aimPick == "Lowest HP" then
								score = hum.Health
							elseif CONFIG.aimPick == "Lowest level" then
								score = levelOf(p)
							else
								score = px
							end

							if not bestScore or score < bestScore then
								best = { player = p, char = char, px = px }
								bestScore = score
							end
						end
					end
				end
			end
		end
	end

	return best
end

local aimWroteCamera = false

local function aimPass(dt)
	if ENV.__ARSENAL ~= GEN then return end

	aimWroteCamera = false
	STATE.engaged = false
	STATE.waitMs = 0
	STATE.breaking = false

	if not aimActive() or not gunGate(CONFIG.aimOnlyGun) or not airGate(CONFIG.aimAir) then
		STATE.target = "-"
		stickyTarget = nil
		currentAimMode = nil
		clearRandomPart()
		return
	end

	if os.clock() * 1000 - lastKillAt < CONFIG.aimKillMs then
		STATE.target = "-"
		return
	end

	local fov, alpha = aimNumbers()
	local pick

	-- Sticky targeting keeps both the player AND the already-rolled body region.
	if CONFIG.aimSticky and stickyTarget then
		local char, _, root = alive(stickyTarget)
		if char and root and (camera.CFrame.Position - root.Position).Magnitude <= CONFIG.aimMaxDist then
			local mode = targetModeFor(stickyTarget, false, root)
			local part = targetPart(char, mode)

			if part then
				local sp = camera:WorldToViewportPoint(part.Position)
				local px = (Vector2.new(sp.X, sp.Y) - centre()).Magnitude
				if sp.Z > 0
					and px <= fov * 1.35
					and ((not CONFIG.aimVisible) or visible(part.Position)) then
					pick = { player = stickyTarget, char = char, part = part, px = px }
				end
			end
		end
	end

	if not pick then
		local candidate = pickTarget()
		if candidate then
			local isNew = candidate.player ~= stickyTarget
			local _, _, root = alive(candidate.player)
			local mode = targetModeFor(candidate.player, isNew, root)
			local part = targetPart(candidate.char, mode)

			if part then
				local sp = camera:WorldToViewportPoint(part.Position)
				local px = (Vector2.new(sp.X, sp.Y) - centre()).Magnitude
				if sp.Z > 0
					and px <= fov * 1.35
					and ((not CONFIG.aimVisible) or visible(part.Position)) then
					pick = {
						player = candidate.player,
						char = candidate.char,
						part = part,
						px = px,
					}
				end
			end
		end
	end

	if not pick or not pick.part or not pick.part.Parent then
		STATE.target = "-"
		stickyTarget = nil
		currentAimMode = nil
		clearRandomPart()
		return
	end

	stickyTarget = pick.player
	STATE.target = pick.player.Name
	local _, _, currentRoot = alive(pick.player)
	currentAimMode = targetModeFor(pick.player, false, currentRoot)
	pick.part = targetPart(pick.char, currentAimMode) or pick.part

	local cf = camera.CFrame
	local targetCFrame = CFrame.lookAt(cf.Position, pick.part.Position)
	camera.CFrame = cf:Lerp(targetCFrame, alpha)

	aimWroteCamera = true
	STATE.engaged = true
end

--------------------------------------------------------------------------------
-- recoil control, measured rather than assumed
--------------------------------------------------------------------------------
--
-- Identical method to counterblox and for the same reason: the weapon folder
-- carries a RecoilControl number but nothing says what one unit of it is worth
-- on this camera. So the client measures its own effective sensitivity while
-- the player is NOT firing, and while firing treats whatever camera movement is
-- left after subtracting sensitivity x mouse delta as the recoil. Both numbers
-- are shown live in the panel so this can be checked rather than believed - and
-- if the kick reads near zero while spraying, Arsenal does not move the camera
-- on recoil at all and no camera-side compensation can work.

local mouseDX, mouseDY = 0, 0
UserInputService.InputChanged:Connect(function(input)
	if ENV.__ARSENAL ~= GEN then return end
	local kind = input.UserInputType
	-- A touch client never sends MouseMovement; the camera drag arrives as Touch.
	-- Without this branch sensYaw stayed 0 on a phone and rcsPass returned at its
	-- `sensYaw == 0 and sp == 0` guard on every single frame.
	if kind == Enum.UserInputType.MouseMovement
		or (TOUCH and kind == Enum.UserInputType.Touch) then
		mouseDX = mouseDX + input.Delta.X
		mouseDY = mouseDY + input.Delta.Y
	end
end)

local lastYaw, lastPitch = nil, nil
local sensYaw, sensPitch = 0, 0
local sprayAt = 0

local function rcsPass(dt)
	if ENV.__ARSENAL ~= GEN then return end
	local cf = camera.CFrame
	local pitch, yaw = cf:ToOrientation()
	local mx, my = mouseDX, mouseDY
	mouseDX, mouseDY = 0, 0

	if lastYaw == nil then lastYaw, lastPitch = yaw, pitch return end

	local dYaw = angleDelta(lastYaw, yaw)
	local dPitch = pitch - lastPitch
	lastYaw, lastPitch = yaw, pitch

	local shooting = firing()

	if not shooting and not aimWroteCamera then
		if math.abs(mx) > 2 then
			local s = -dYaw / mx
			sensYaw = sensYaw == 0 and s or (sensYaw * 0.9 + s * 0.1)
			STATE.calibN = STATE.calibN + 1
		end
		if math.abs(my) > 2 then
			local s = -dPitch / my
			sensPitch = sensPitch == 0 and s or (sensPitch * 0.9 + s * 0.1)
		end
	end
	STATE.sensY = sensYaw
	STATE.sensP = sensPitch

	if not shooting then
		STATE.kickY, STATE.kickP = 0, 0
		return
	end

	-- Vertical sensitivity is measured far less often than horizontal, so an
	-- unmeasured pitch falls back to the yaw one rather than to zero. With zero
	-- the residual is the player's whole vertical movement and the correction
	-- fights the user instead of the recoil.
	local sp = sensPitch
	if sp == 0 then sp = sensYaw end

	local resYaw   = dYaw   - (-sensYaw * mx)
	local resPitch = dPitch - (-sp      * my)
	STATE.kickY = math.deg(resYaw)
	STATE.kickP = math.deg(resPitch)
	if math.abs(STATE.kickP) > math.abs(STATE.kickPeak) then
		STATE.kickPeak = STATE.kickP
	end

	if not CONFIG.rcs or aimWroteCamera then return end
	if sensYaw == 0 and sp == 0 then return end
	if STATE.shots < CONFIG.rcsAfter then return end

	local cap = math.rad(CONFIG.rcsMaxDeg)
	local corrYaw   = math.clamp(-resYaw   * (CONFIG.rcsYaw   / 100), -cap, cap)
	local corrPitch = math.clamp(-resPitch * (CONFIG.rcsPitch / 100), -cap, cap)
	if math.abs(corrYaw) < 1e-5 and math.abs(corrPitch) < 1e-5 then return end

	camera.CFrame = CFrame.new(cf.Position)
		* CFrame.fromOrientation(pitch + corrPitch, yaw + corrYaw, 0)
	lastPitch, lastYaw = pitch + corrPitch, yaw + corrYaw
end

--------------------------------------------------------------------------------
-- shot counting
--------------------------------------------------------------------------------
--
-- Same problem as Counter Blox: nothing on the client holds a live ammo count
-- that this script can read, so the shot number is counted from the trigger
-- being down and the weapon's own FireRate, and reset after a 0.35s gap.

local nextShotAt = 0

local function shotClock()
	local now = os.clock()
	-- On a touch client there is no held button to run the clock off, so the count
	-- is incremented by pullTrigger itself - the one place that knows a shot really
	-- happened. Here only the spray reset is left.
	if TOUCH then
		if now - sprayAt > 0.35 then STATE.shots = 0 end
		return
	end
	if not firing() then
		if now - sprayAt > 0.35 then STATE.shots = 0 end
		return
	end
	local info = weaponInfo()
	local rate = (info and info.rate) or 0.1
	if now >= nextShotAt then
		STATE.shots = STATE.shots + 1
		sprayAt = now
		nextShotAt = now + rate
		if info and not info.auto then
			nextShotAt = now + math.max(rate, 0.22)
		end
	end
end


--------------------------------------------------------------------------------
-- trigger
--------------------------------------------------------------------------------

local execEnv = (type(getgenv) == "function" and getgenv()) or _G
local click = execEnv.mouse1click
local press = execEnv.mouse1press
local release = execEnv.mouse1release
local mouse = plr:GetMouse()

local VIM = nil
pcall(function()
	local service = game:GetService("VirtualInputManager")
	if service and type(service.SendMouseButtonEvent) == "function" then
		VIM = service
	end
end)

local function tryInput(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function vimButton(down)
	if not VIM then return false end
	local vp = camera.ViewportSize
	return pcall(function()
		VIM:SendMouseButtonEvent(
			math.floor(vp.X / 2),
			math.floor(vp.Y / 2),
			0,
			down,
			game,
			0
		)
	end)
end

STATE.clickHow = type(click) == "function" and "mouse1click"
	or ((type(press) == "function" and type(release) == "function") and "mouse1press")
	or (VIM and "VirtualInputManager")
	or "none"

local function pullTrigger()
	local hold = CONFIG.trigMode == "Hold"
	local fired = false

	-- Hold mode prefers a real press/release pair.
	if hold and type(press) == "function" and type(release) == "function" then
		if tryInput(press) then
			task.wait(CONFIG.trigHoldMs / 1000)
			fired = tryInput(release)
			if fired then STATE.clickHow = "mouse1press" end
		end
	end

	-- Click mode uses Volt's mouse1click first.
	if not fired and not hold and type(click) == "function" then
		fired = tryInput(click)
		if fired then STATE.clickHow = "mouse1click" end
	end

	-- If mouse1click exists but fails at runtime, fall back instead of killing
	-- this trigger pass.
	if not fired and type(press) == "function" and type(release) == "function" then
		if tryInput(press) then
			task.wait(hold and (CONFIG.trigHoldMs / 1000) or 0.02)
			fired = tryInput(release)
			if fired then STATE.clickHow = "mouse1press" end
		end
	end

	if not fired and VIM then
		if vimButton(true) then
			task.wait(hold and (CONFIG.trigHoldMs / 1000) or 0.02)
			fired = vimButton(false)
			if fired then STATE.clickHow = "VirtualInputManager" end
		end
	end

	if not fired then
		STATE.clickHow = "none"
		return false
	end

	lastShotAt = os.clock()
	if TOUCH then
		STATE.shots = STATE.shots + 1
		sprayAt = lastShotAt
	end
	return true
end

local function enemyFromPart(part)
	if not part then return nil end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then return nil end

	local p = Players:GetPlayerFromCharacter(model)
	if not p or not isEnemy(p) or not alive(p) then return nil end
	if CONFIG.trigHeadOnly and not HEADPARTS[part.Name] then return nil end

	return p, part
end

local function underCrosshair()
	-- Roblox's client mouse target is a useful first path in Arsenal because the
	-- cursor is normally locked to the game's crosshair.
	if CONFIG.trigFov <= 0 then
		local ok, part = pcall(function() return mouse.Target end)
		if ok and part then
			local p, hitPart = enemyFromPart(part)
			if p then return p, hitPart end
		end
	end

	local vp = camera.ViewportSize
	local mid = Vector2.new(vp.X / 2, vp.Y / 2)
	local offsets = { Vector2.new(0, 0) }

	if CONFIG.trigFov > 0 then
		local r = CONFIG.trigFov
		for i = 0, 7 do
			local a = math.rad(i * 45)
			table.insert(offsets, Vector2.new(math.cos(a) * r, math.sin(a) * r))
		end
	end

	for _, off in ipairs(offsets) do
		local ray = camera:ViewportPointToRay(mid.X + off.X, mid.Y + off.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * CONFIG.trigMaxDist, trigParams)

		if hit and hit.Instance then
			local p, hitPart = enemyFromPart(hit.Instance)
			if p then return p, hitPart end
		end
	end

	return nil
end

local function triggerGunGate()
	if not CONFIG.trigOnlyGun then return true end

	local info = weaponInfo()
	-- Replication can briefly leave the weapon unknown. Unknown should not make
	-- an otherwise-valid trigger permanently dead; a positively identified melee
	-- still blocks it.
	if not info then return true end
	return info.gun == true
end

local trigShots = 0

local function trigActive()
	if not CONFIG.trig then return false end
	if CONFIG.aimPauseUI and STATE.panelOpen then return false end
	return true
end

task.spawn(function()
	local nextAt = 0

	while ENV.__ARSENAL == GEN do
		local ok, err = pcall(function()
			local seen = underCrosshair()
			STATE.underCross = seen and seen.Name or "-"

			if not trigActive() then
				trigShots = 0
				STATE.trigOn = false
				return
			end

			STATE.trigOn = true

			if not triggerGunGate() then return end
			if CONFIG.trigBurst > 0 and trigShots >= CONFIG.trigBurst then return end

			local now = os.clock() * 1000
			if now < nextAt or not seen then return end

			if math.random(1, 100) > CONFIG.trigHitPct then
				nextAt = now + CONFIG.trigRefireMs
				return
			end

			local lo = math.min(CONFIG.trigDelayMin, CONFIG.trigDelayMax)
			local hi = math.max(CONFIG.trigDelayMin, CONFIG.trigDelayMax)
			if hi > 0 then
				task.wait(math.random(lo, hi) / 1000)
			end

			-- Re-check after reaction delay so a target that left the crosshair
			-- does not receive a stale synthetic click.
			if not underCrosshair() then return end

			if pullTrigger() then
				trigShots = trigShots + 1
				STATE.trigHits = STATE.trigHits + 1
				nextAt = os.clock() * 1000 + CONFIG.trigRefireMs
			else
				nextAt = os.clock() * 1000 + 100
			end
		end)

		if not ok then note("trigger: " .. tostring(err)) end
		task.wait(0.01)
	end
end)

-- A kill pauses the aim. Staying glued to a corpse and then flicking off it is
-- the single most obvious thing an aim assist does.
task.spawn(function()
	local seen = {}
	while ENV.__ARSENAL == GEN do
		pcall(function()
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local was = seen[p]
				local now = hum and hum.Health or 0
				if was and was > 0 and now <= 0 and p == stickyTarget then
					lastKillAt = os.clock() * 1000
					stickyTarget = nil
					clearRandomPart()
				end
				seen[p] = now
			end
		end)
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------------
-- hitbox
--------------------------------------------------------------------------------
--
-- Arsenal gives every character a dedicated `Hitbox` part, 4.5 x 4 x 4 studs,
-- fully transparent and CanQuery true, sitting on the torso. Resizing it on this
-- client is the classic Arsenal hitbox expander.
--
-- What this session could NOT measure is whether the SERVER grades a hit against
-- the client's copy of that part - the account was in the lobby throughout, so
-- no shot was ever fired. The feature therefore ships off, says so in its own
-- readout, and restores every part it touched the moment it is switched off or
-- the player leaves. Do not present it as verified until a before/after kill
-- confirms it.

local HB_PARTS = {
	["Hitbox"] = { "Hitbox" },
	["HeadHB"] = { "HeadHB" },
	["Head"]   = { "Head", "HeadHB" },
	["Hitbox + HeadHB"] = { "Hitbox", "HeadHB" },
}
local HB_LIST = { "Hitbox", "HeadHB", "Head", "Hitbox + HeadHB" }

-- The original size and transparency of everything ever touched, keyed by the
-- part itself so a respawned character simply never matches an old entry.
local hbSaved = _G.__ARSENAL_HBSAVED or {}
_G.__ARSENAL_HBSAVED = hbSaved

local function hbRestoreAll()
	for part, old in pairs(hbSaved) do
		pcall(function()
			if part and part.Parent then
				part.Size = old.size
				part.Transparency = old.trans
				part.CanCollide = old.collide
			end
		end)
		hbSaved[part] = nil
	end
	STATE.hbCount = 0
end

local function hbApply()
	local names = HB_PARTS[CONFIG.hbPart] or HB_PARTS["Hitbox"]
	local count = 0
	local size = CONFIG.hbSize
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local want = p ~= plr and char ~= nil
			and ((not CONFIG.hbEnemy) or isEnemy(p))
		if want then
			for _, n in ipairs(names) do
				local part = char:FindFirstChild(n)
				if part and part:IsA("BasePart") then
					if not hbSaved[part] then
						hbSaved[part] = { size = part.Size, trans = part.Transparency,
							collide = part.CanCollide }
					end
					-- CanCollide is forced OFF: an eight stud collidable box on
					-- every enemy turns the map into an obstacle course and is
					-- also the most visible thing this could possibly do.
					part.CanCollide = false
					part.Size = Vector3.new(size, size, size)
					part.Transparency = CONFIG.hbTrans / 100
					count = count + 1
				end
			end
		end
	end
	STATE.hbCount = count
end

task.spawn(function()
	local was = false
	while ENV.__ARSENAL == GEN do
		local ok, err = pcall(function()
			if CONFIG.hb then
				hbApply()
				was = true
			elseif was then
				hbRestoreAll()
				was = false
			end
		end)
		if not ok then note("hitbox: " .. tostring(err)) end
		task.wait(math.max(0.1, CONFIG.hbEvery))
	end
	pcall(hbRestoreAll)
end)

Players.PlayerRemoving:Connect(function(p)
	local set = drawn[p]
	if set then hideSet(set) end
	local hl = highlights[p]
	if hl then pcall(function() hl:Destroy() end) highlights[p] = nil end
end)

--------------------------------------------------------------------------------
-- the frame bindings
--------------------------------------------------------------------------------

for _, name in ipairs({ "SeluxArsenalAim", "SeluxArsenalESP" }) do
	pcall(function() RunService:UnbindFromRenderStep(name) end)
end

RunService:BindToRenderStep("SeluxArsenalAim", Enum.RenderPriority.Camera.Value + 1,
	function(dt)
		if ENV.__ARSENAL ~= GEN then
			pcall(function() RunService:UnbindFromRenderStep("SeluxArsenalAim") end)
			return
		end
		local ok, err = pcall(function()
			shotClock()
			aimPass(dt)
			rcsPass(dt)
		end)
		if not ok then note("aim: " .. tostring(err)) end
	end)

RunService:BindToRenderStep("SeluxArsenalESP", Enum.RenderPriority.Camera.Value + 2,
	function()
		if ENV.__ARSENAL ~= GEN then
			pcall(function() RunService:UnbindFromRenderStep("SeluxArsenalESP") end)
			hideAll()
			return
		end
		local ok, err = pcall(renderPass)
		if not ok then note("esp: " .. tostring(err)) end
	end)

--------------------------------------------------------------------------------
-- panel
--------------------------------------------------------------------------------

-- Arsenal Gen2 destroys a WINDOW with :Unload().
-- Store the previous window in Volt's persistent getgenv() so a new execution
-- can actually reach and unload it.
if ENV.__ARSENAL_RAY_WINDOW then
	pcall(function()
		if not ENV.__ARSENAL_RAY_WINDOW.unloaded then
			ENV.__ARSENAL_RAY_WINDOW:Unload()
		end
	end)
	ENV.__ARSENAL_RAY_WINDOW = nil
end

-- Compatibility cleanup for an older build that stored the wrapper instead.
if ENV.__ARSENAL_WIN then
	pcall(function()
		local old = ENV.__ARSENAL_WIN
		if old.ray and type(old.ray.Unload) == "function" then
			old.ray:Unload()
		elseif type(old.Destroy) == "function" then
			old:Destroy()
		end
	end)
	ENV.__ARSENAL_WIN = nil
end

local Arsenal = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- Arsenal Gen2 compatibility layer. The rest of the script keeps using the
-- same page/card calls so no gameplay code has to change for the UI swap.
local UI = {
	icon = {
		eye = "eye",
		target = "crosshair",
		wave = "activity",
		bolt = "zap",
		chart = "chart-line",
		shield = "shield",
		list = "list",
	},
	theme = {
		good = true,
		warn = true,
		band = true,
		bad = true,
	},
}

function UI.t(text)
	return text
end

function UI.sweep()
	-- Arsenal Gen2 windows are unloaded through the wrapper below.
end

function UI.config()
	-- Arsenal Gen2 owns UI state persistence through its configuration object.
end

local function rayFlag(pageName, cardName, elementName)
	return ("arsenal_%s_%s_%s"):format(pageName, cardName, elementName)
		:lower()
		:gsub("[^%w_]+", "_")
		:gsub("_+", "_")
end

local function enumFromKey(name)
	if typeof(name) == "EnumItem" then return name end
	if type(name) ~= "string" then return name end

	local spec = resolveKey(name)
	if spec then return spec.key or spec.mouse end
	return name
end

function UI.Window(options)
	local ray = Arsenal:CreateWindow({
		name = (options.title or "") .. (options.accentTitle or ""),
		subtitle = options.subtitle or "",
    	icon = 138354947487999,
		sidebarLayout = true,
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "arsenal",
			customFolder = "Arsenal",
		},
	})

	local wrapper = {
		ray = ray,
		root = { Visible = true },
		pages = {},
		stats = {},
		note = "Ready",
		status = "",
		statusText = nil,
		toggleConnection = nil,
	}

	local function updateStatus()
		local page = wrapper.pages.MATCH
		if not page then return end

		if not wrapper.statusText then
			page.tab:CreateSection({ name = "SESSION" })
			wrapper.statusText = page.tab:CreateText({
				name = "Live",
				text = "",
			})
		end

		local parts = {}
		for i = 1, 3 do
			local stat = wrapper.stats[i]
			if stat then
				table.insert(parts, tostring(stat.label or "") .. " " .. tostring(stat.value or ""))
			end
		end

		local line = table.concat(parts, "   •   ")
		local body = line
		if wrapper.status ~= "" then body = body .. "\n" .. wrapper.status end
		if wrapper.note ~= "" then body = body .. "\n" .. wrapper.note end
		wrapper.statusText:Set(body)
	end

	function wrapper:Page(name, icon)
		local tab = ray:CreateTab({
			name = name,
			icon = icon,
		})

		local page = {
			name = name,
			tab = tab,
			window = self,
		}
		self.pages[name] = page

		function page:Divider(text)
			return self.tab:CreateDivider({
				text = text or "",
			})
		end

		function page:Stat(options)
			return self.tab:CreateStat(options)
		end

		function page:Row()
			return self.tab:CreateGroup({
				direction = "row",
			})
		end

		function page:Readout(lines)
			local console = self.tab:CreateConsole({
				text = "",
				height = math.clamp((lines or 6) * 17 + 24, 100, 260),
				follow = false,
				maxLines = math.max(lines or 6, 20),
			})

			local readout = {}

			function readout:set(value)
				console:Set(type(value) == "table" and table.concat(value, "\n") or tostring(value or ""))
			end

			return readout
		end

		function page:Card(cardName)
			self.tab:CreateSection({ name = cardName })

			local card = {
				name = cardName,
				page = self,
				tab = self.tab,
			}

			function card:Accent()
				return self
			end

			function card:Toggle(name, value, callback, description)
				return self.tab:CreateToggle({
					name = name,
					description = description,
					flag = rayFlag(self.page.name, self.name, name),
					value = value and true or false,
					callback = callback,
				})
			end

			function card:Dropdown(name, options, value, callback, description)
				return self.tab:CreateDropdown({
					name = name,
					description = description,
					flag = rayFlag(self.page.name, self.name, name),
					options = options,
					value = value,
					callback = callback,
				})
			end

			function card:Slider(name, min, max, value, callback, description)
				return self.tab:CreateSlider({
					name = name,
					description = description,
					flag = rayFlag(self.page.name, self.name, name),
					range = { min, max },
					increment = 1,
					value = value,
					callback = function(v)
						callback(v)
					end,
				})
			end

			function card:Colour(name, value, callback, description)
				return self.tab:CreateColorPicker({
					name = name,
					description = description,
					flag = rayFlag(self.page.name, self.name, name),
					color = value,
					callback = function(color)
						callback(color)
					end,
				})
			end

			function card:Button(name, callback)
				return self.tab:CreateButton({
					name = name,
					callback = callback,
				})
			end

			function card:Label(text)
				return self.tab:CreateText({
					text = text,
				})
			end

			function card:Keybind(name, value, onChanged, description)
				return self.tab:CreateKeybind({
					name = name,
					description = description,
					flag = rayFlag(self.page.name, self.name, name),
					value = enumFromKey(value),
					callback = function() end,
					onChanged = function(key)
						if typeof(key) == "EnumItem" then
							onChanged(key.Name)
						else
							onChanged(tostring(key))
						end
					end,
				})
			end

			function card:Readout(lines)
				return self.page:Readout(lines)
			end

			return card
		end

		return page
	end

	function wrapper:Tag(text, color)
		return ray:CreateTag({
			text = text,
			color = color,
		})
	end

	function wrapper:SetStat(index, value, label)
		self.stats[index] = { value = value, label = label }
		updateStatus()
	end

	function wrapper:SetNote(value)
		self.note = tostring(value or "")
		updateStatus()
	end

	function wrapper:SetStatus(value)
		self.status = tostring(value or "")
		updateStatus()
	end

	function wrapper:Home()
		pcall(function() ray:Navigate("ESP") end)
	end

	function wrapper:Refresh()
		-- Existing callbacks write CONFIG directly. Arsenal already reflects
		-- user changes immediately; preset values take effect in gameplay at once.
	end

	function wrapper:Destroy()
		if self.toggleConnection then
			self.toggleConnection:Disconnect()
			self.toggleConnection = nil
		end

		pcall(function()
			if not ray.unloaded then
				ray:Unload()
			end
		end)

		if ENV.__ARSENAL_WIN == self then
			ENV.__ARSENAL_WIN = nil
		end
		if ENV.__ARSENAL_RAY_WINDOW == ray then
			ENV.__ARSENAL_RAY_WINDOW = nil
		end
	end

	wrapper.toggleConnection = UserInputService.InputBegan:Connect(function(input, typing)
		if typing or ENV.__ARSENAL ~= GEN then return end
		if input.KeyCode == Enum.KeyCode.RightShift then
			wrapper.root.Visible = not wrapper.root.Visible
			if wrapper.root.Visible then
				ray:Show()
			else
				ray:Hide()
			end
		end
	end)

	return wrapper
end

UI.config("arsenal", CONFIG)

local win = UI.Window({
	name = "Arsenal",
	title = "Ars",
	accentTitle = "enal",
	subtitle = "Cloudz Softworks",
	badge = "◎",
	width = 940,
	height = 590,
})
ENV.__ARSENAL_WIN = win
ENV.__ARSENAL_RAY_WINDOW = win.ray

local ACCENT_GREEN = Color3.fromRGB(25, 145, 105)
local MODE_BLUE = Color3.fromRGB(65, 145, 255)

-- Curated bright colors stay readable on Arsenal's dark tag/toast surfaces.
-- A mode gets one random color when it becomes active; its tag and announcement
-- share that exact Color3.
local MODE_COLORS = {
	Color3.fromRGB(255, 90, 105),
	Color3.fromRGB(255, 165, 70),
	Color3.fromRGB(255, 210, 65),
	Color3.fromRGB(80, 220, 145),
	Color3.fromRGB(45, 205, 190),
	Color3.fromRGB(75, 165, 255),
	Color3.fromRGB(120, 125, 255),
	Color3.fromRGB(185, 105, 255),
	Color3.fromRGB(245, 100, 210),
}

local function randomModeColor(previous)
	if #MODE_COLORS == 1 then return MODE_COLORS[1] end

	local color
	repeat
		color = MODE_COLORS[math.random(1, #MODE_COLORS)]
	until color ~= previous

	return color
end

local gameModeColor = randomModeColor()
local gameModeTag = win:Tag("Loading mode...", gameModeColor)
local modeTag = win:Tag("FFA", MODE_BLUE)
local lastGameMode, lastModeTag


-- Every caption below is written in ENGLISH on purpose: UI.t() looks a string up
-- by exactly the characters the script passed and tools/i18n/*.tsv is keyed in
-- English, so a German literal here is a key that is in no dictionary and the
-- language flags in the header would appear to do nothing.

--------------------------------------------------------------------------------
-- ESP page
--------------------------------------------------------------------------------

local espPage = win:Page("ESP", UI.icon.eye)

local drawCard = espPage:Card("DRAWING", 1):Accent()
drawCard:Toggle("Box", CONFIG.box, function(v) CONFIG.box = v end,
	"projected head to feet, follows crouching and range", UI.theme.good)
drawCard:Toggle("Filled box", CONFIG.boxFilled, function(v) CONFIG.boxFilled = v end)
drawCard:Toggle("Name", CONFIG.name, function(v) CONFIG.name = v end)
drawCard:Toggle("Health bar", CONFIG.health, function(v) CONFIG.health = v end,
	"left of the box, green to red")
drawCard:Toggle("Health number", CONFIG.hpText, function(v) CONFIG.hpText = v end)
drawCard:Toggle("Level", CONFIG.level, function(v) CONFIG.level = v end,
	"the gun game level - this is what decides the match", UI.theme.good)
drawCard:Toggle("Weapon", CONFIG.weapon, function(v) CONFIG.weapon = v end,
	"read from the level ladder; EquippedWep never replicates", UI.theme.good)
drawCard:Toggle("Distance", CONFIG.distance, function(v) CONFIG.distance = v end)
drawCard:Toggle("Kills / streak", CONFIG.kills, function(v) CONFIG.kills = v end)
drawCard:Toggle("Head dot", CONFIG.headDot, function(v) CONFIG.headDot = v end,
	"sits on HeadHB, the part a headshot is graded against")
drawCard:Toggle("Skeleton", CONFIG.skeleton, function(v) CONFIG.skeleton = v end)
drawCard:Toggle("Tracer", CONFIG.tracer, function(v) CONFIG.tracer = v end)
drawCard:Toggle("Off screen arrows", CONFIG.offScreen, function(v)
	CONFIG.offScreen = v
end, "a marker at the screen edge for enemies behind you", UI.theme.good)

local modeCard = espPage:Card("RANGE & TEXT", 2)
modeCard:Dropdown("Targets", { "Auto", "Everyone (FFA)", "Team check" },
	CONFIG.teamMode, function(v) CONFIG.teamMode = v end)
modeCard:Toggle("Wall check", CONFIG.visCheck, function(v) CONFIG.visCheck = v end,
	"behind a wall is drawn at 55% brightness instead of full", UI.theme.good)
modeCard:Toggle("Draw team mates", CONFIG.teamESP, function(v) CONFIG.teamESP = v end)
modeCard:Toggle("Mark the leader", CONFIG.markLeader, function(v)
	CONFIG.markLeader = v
end, "adds a star to whoever is closest to the last level without changing team colour")
modeCard:Slider("Max distance", 100, 3000, CONFIG.maxDist, function(v)
	CONFIG.maxDist = v
end, "studs; nothing is drawn beyond this")
modeCard:Slider("Text size", 12, 26, CONFIG.textSize, function(v) CONFIG.textSize = v end,
	"whole pixels; below 12 every Drawing face turns to mush")
modeCard:Dropdown("Font", FONTLIST, CONFIG.textFont, function(v) CONFIG.textFont = v end)
modeCard:Toggle("Text outline", CONFIG.textOutline, function(v)
	CONFIG.textOutline = v
end)
modeCard:Toggle("Shrink with distance", CONFIG.textShrink, function(v)
	CONFIG.textShrink = v
end)

local colCard = espPage:Card("COLOURS", 1)
colCard:Label("Player ESP follows each player's actual team colour.")
colCard:Colour("FOV circle", CONFIG.colFov, function(c) CONFIG.colFov = c end)

local chamCard = espPage:Card("CHAMS", 2)
chamCard:Toggle("Chams", CONFIG.chams, function(v)
	CONFIG.chams = v
	if not v then clearChams() end
end, "Highlight through walls; lives in CoreGui, not in the game tree", UI.theme.warn)
chamCard:Dropdown("Style", CHAM_LIST, CONFIG.chamStyle, function(v) CONFIG.chamStyle = v end)
chamCard:Toggle("Rainbow", CONFIG.chamRainbow, function(v) CONFIG.chamRainbow = v end)
chamCard:Toggle("Colour by health", CONFIG.chamByHealth, function(v)
	CONFIG.chamByHealth = v
end)
chamCard:Toggle("Own cham colour", CONFIG.colChamOwn, function(v) CONFIG.colChamOwn = v end)
chamCard:Colour("Cham colour", CONFIG.colCham, function(c) CONFIG.colCham = c end)

--------------------------------------------------------------------------------
-- AIM page
--------------------------------------------------------------------------------

local aimPage = win:Page("AIM", UI.icon.target)

local function bindButton(card, caption, get, set)
	if TOUCH then
		card:Label(caption .. ": no keyboard on this device")
		return
	end
	card:Keybind(caption, get(), set)
end

-- Activation ---------------------------------------------------------

local aimActivation = aimPage:Card("ACTIVATION", 1):Accent()

aimActivation:Toggle("Aim enabled", CONFIG.aim, function(v)
	CONFIG.aim = v
	note(v and "aim on" or "aim off")
end, "moves the camera toward the selected enemy", UI.theme.warn)

aimActivation:Toggle("Pause aim + triggerbot while Arsenal is open", CONFIG.aimPauseUI, function(v)
	if CONFIG.aimPauseUI == v then return end

	CONFIG.aimPauseUI = v
	altairToast(v and "Aim + triggerbot paused." or "Aim + triggerbot resumed.")
end, "pauses both features while the Arsenal UI is visible", UI.theme.good)

-- Target selection ---------------------------------------------------

local aimSelection = aimPage:Card("TARGET SELECTION", 2)

aimSelection:Dropdown(
	"Pick target by",
	{ "Crosshair", "Closest", "Lowest HP", "Lowest level" },
	CONFIG.aimPick,
	function(v) CONFIG.aimPick = v end
)

aimSelection:Toggle("Sticky target", CONFIG.aimSticky, function(v)
	CONFIG.aimSticky = v
	stickyTarget = nil
	clearRandomPart()
end, "keeps the same enemy until the target becomes invalid", UI.theme.good)

aimSelection:Toggle("Visible only", CONFIG.aimVisible, function(v)
	CONFIG.aimVisible = v
end, "never aims at an enemy behind a wall", UI.theme.good)

aimSelection:Toggle("Firearms only", CONFIG.aimOnlyGun, function(v)
	CONFIG.aimOnlyGun = v
end)

aimSelection:Dropdown(
	"Ground condition",
	{ "Always", "Only grounded", "Only airborne" },
	CONFIG.aimAir,
	function(v) CONFIG.aimAir = v end
)

aimSelection:Slider("Max distance", 50, 3000, CONFIG.aimMaxDist, function(v)
	CONFIG.aimMaxDist = v
end)

-- Body targeting -----------------------------------------------------

local aimBody = aimPage:Card("BODY TARGETING", 2)

aimBody:Toggle("Distance-based headshots", CONFIG.aimDistancePart, function(v)
	CONFIG.aimDistancePart = v
end)

aimBody:Slider("Guaranteed headshot range (m)", 5, 50, CONFIG.aimHeadRangeM, function(v)
	CONFIG.aimHeadRangeM = v
end, "0-5m uses torso; 5m to the selected range uses head.. farther targets fall back to random/manual targeting")

aimBody:Toggle("Randomize head / torso", CONFIG.aimRandomPart, function(v)
	CONFIG.aimRandomPart = v
	stickyTarget = nil
	clearRandomPart()
end, "rolls once for each newly acquired player", UI.theme.good)

aimBody:Slider("Headshot chance %", 0, 100, CONFIG.aimHeadChance, function(v)
	CONFIG.aimHeadChance = v
end, "remaining chance uses UpperTorso / HumanoidRootPart")

aimBody:Dropdown(
	"Aim at",
	{ "Head", "Torso", "Hitbox", "Nearest" },
	CONFIG.aimPart,
	function(v)
		CONFIG.aimPart = v
		if not CONFIG.aimRandomPart then
			stickyTarget = nil
			clearRandomPart()
		end
	end,
	"manual fallback when distance targeting and randomization are not deciding"
)

-- Aim movement / visuals --------------------------------------------

local aimMovement = aimPage:Card("AIMING", 1)

aimMovement:Toggle("Draw FOV", CONFIG.aimCircle, function(v)
	CONFIG.aimCircle = v
end)
aimMovement:Slider("Circle FOV", 5, 600, CONFIG.aimFov, function(v)
	CONFIG.aimFov = v
end, "only enemies inside this circle are acquired")

aimMovement:Slider("Smoothness", 5, 100, CONFIG.aimSmooth, function(v)
	CONFIG.aimSmooth = v
end, "CFrame:Lerp strength; 15 equals 0.15")

aimMovement:Slider("Delay after kill (ms)", 0, 1000, CONFIG.aimKillMs, function(v)
	CONFIG.aimKillMs = v
end, "briefly releases a dead target before acquiring another")

-- Safety / status ----------------------------------------------------

local aimSafety = aimPage:Card("SAFETY", 1)
bindButton(aimSafety, "PANIC KEY", function() return CONFIG.panicKey end, function(v)
	CONFIG.panicKey = v
end)
aimSafety:Label("Panic disables aim, triggerbot and recoil control.")

local aimOut = aimPage:Card("STATUS", 2):Readout(6)

--------------------------------------------------------------------------------
-- TRIGGER page
--------------------------------------------------------------------------------

local trigPage = win:Page("TRIGGER", UI.icon.bolt)
local trigControls = {}

local TRIGGER_PRESETS = {
	Instant = {
		delayMin = 0,
		delayMax = 0,
		refire = 20,
		hitPct = 100,
	},
	Fast = {
		delayMin = 15,
		delayMax = 45,
		refire = 60,
		hitPct = 100,
	},
	Natural = {
		delayMin = 40,
		delayMax = 110,
		refire = 90,
		hitPct = 98,
	},
}

local function setControl(control, value)
	if control and type(control.Set) == "function" then
		pcall(function() control:Set(value) end)
	end
end

local function applyTriggerPreset(name)
	local preset = TRIGGER_PRESETS[name]
	if not preset then return end

	CONFIG.trigDelayMin = preset.delayMin
	CONFIG.trigDelayMax = preset.delayMax
	CONFIG.trigRefireMs = preset.refire
	CONFIG.trigHitPct = preset.hitPct

	setControl(trigControls.delayMin, preset.delayMin)
	setControl(trigControls.delayMax, preset.delayMax)
	setControl(trigControls.refire, preset.refire)
	setControl(trigControls.hitPct, preset.hitPct)

	note("trigger preset: " .. name)
end

-- Activation ---------------------------------------------------------

local trigActivation = trigPage:Card("ACTIVATION", 1):Accent()

trigActivation:Toggle("Trigger enabled", CONFIG.trig, function(v)
	CONFIG.trig = v
	note(v and "trigger on" or "trigger off")
end, "fires when an enemy is under the crosshair", UI.theme.warn)

trigActivation:Dropdown("Fire mode", { "Click", "Hold" }, CONFIG.trigMode, function(v)
	CONFIG.trigMode = v
end)

trigActivation:Slider("Hold time (ms)", 20, 600, CONFIG.trigHoldMs, function(v)
	CONFIG.trigHoldMs = v
end, "used only in Hold mode")

if STATE.clickHow == "none" then
	trigActivation:Label("This executor exposes no supported mouse click method.")
end

-- Presets ------------------------------------------------------------

local trigPresets = trigPage:Card("PRESETS", 1)
trigPresets:Button("INSTANT", function() applyTriggerPreset("Instant") end)
trigPresets:Button("FAST", function() applyTriggerPreset("Fast") end)
trigPresets:Button("NATURAL", function() applyTriggerPreset("Natural") end)

-- Targeting ----------------------------------------------------------

local trigTargeting = trigPage:Card("TARGETING", 2)

trigTargeting:Toggle("Head only", CONFIG.trigHeadOnly, function(v)
	CONFIG.trigHeadOnly = v
end, "fires only when the ray lands on Head, HeadHB or FakeHead")

trigTargeting:Toggle("Firearms only", CONFIG.trigOnlyGun, function(v)
	CONFIG.trigOnlyGun = v
end)

trigTargeting:Slider("FOV (pixels)", 0, 60, CONFIG.trigFov, function(v)
	CONFIG.trigFov = v
end, "0 uses the exact centre ray; higher values add a small target window")

trigTargeting:Slider("Max distance", 50, 3000, CONFIG.trigMaxDist, function(v)
	CONFIG.trigMaxDist = v
end)

-- Timing -------------------------------------------------------------

local trigTiming = trigPage:Card("TIMING", 2)

trigControls.delayMin = trigTiming:Slider(
	"Reaction min (ms)", 0, 500, CONFIG.trigDelayMin,
	function(v) CONFIG.trigDelayMin = v end,
	"random delay between the minimum and maximum"
)

trigControls.delayMax = trigTiming:Slider(
	"Reaction max (ms)", 0, 500, CONFIG.trigDelayMax,
	function(v) CONFIG.trigDelayMax = v end
)

trigControls.refire = trigTiming:Slider(
	"Refire lockout (ms)", 20, 1000, CONFIG.trigRefireMs,
	function(v) CONFIG.trigRefireMs = v end
)

trigControls.hitPct = trigTiming:Slider(
	"Hit chance %", 1, 100, CONFIG.trigHitPct,
	function(v) CONFIG.trigHitPct = v end
)

trigTiming:Slider("Shots per hold", 0, 30, CONFIG.trigBurst, function(v)
	CONFIG.trigBurst = v
end, "0 = unlimited")

local trigOut = trigPage:Card("STATUS", 1):Readout(5)

--------------------------------------------------------------------------------
-- RECOIL page
--------------------------------------------------------------------------------

local rcsPage = win:Page("RECOIL", UI.icon.chart)

local rcsCard = rcsPage:Card("RECOIL CONTROL", 1):Accent()
rcsCard:Toggle("RCS enabled", CONFIG.rcs, function(v)
	CONFIG.rcs = v
	note(v and "rcs on" or "rcs off")
end, "measures itself against your own mouse - no calibration step", UI.theme.warn)
rcsCard:Slider("Pitch %", 0, 100, CONFIG.rcsPitch, function(v) CONFIG.rcsPitch = v end,
	"share of the measured vertical kick that is taken back out")
rcsCard:Slider("Yaw %", 0, 100, CONFIG.rcsYaw, function(v) CONFIG.rcsYaw = v end)
rcsCard:Slider("Start at shot", 1, 10, CONFIG.rcsAfter, function(v) CONFIG.rcsAfter = v end,
	"the first bullet has no recoil, so there is nothing to cancel")
rcsCard:Slider("Max correction (deg)", 1, 15, CONFIG.rcsMaxDeg, function(v)
	CONFIG.rcsMaxDeg = v
end, "hard per-frame cap so the correction cannot oscillate")

local rcsOut = rcsPage:Card("MEASUREMENT", 2):Readout(6)
local wpnOut = rcsPage:Card("WEAPON", 2):Readout(8)

--------------------------------------------------------------------------------
-- HITBOX page
--------------------------------------------------------------------------------

local hbPage = win:Page("HITBOX", UI.icon.shield)

local hbCard = hbPage:Card("HITBOX EXPANDER", 1):Accent()
hbCard:Toggle("Hitbox expander", CONFIG.hb, function(v)
	CONFIG.hb = v
	if not v then hbRestoreAll() end
	note(v and "hitbox expander on - UNVERIFIED, see the readout"
		or "hitbox expander off, sizes restored")
end, "resizes the enemy's own Hitbox part on THIS client", UI.theme.bad)
hbCard:Slider("Size (studs)", 4, 30, CONFIG.hbSize, function(v) CONFIG.hbSize = v end,
	"the part is 4.5 x 4 x 4 by default, so 4 changes nothing")
hbCard:Dropdown("Which part", HB_LIST, CONFIG.hbPart, function(v)
	hbRestoreAll()
	CONFIG.hbPart = v
end)
hbCard:Slider("Transparency %", 0, 100, CONFIG.hbTrans, function(v) CONFIG.hbTrans = v end,
	"below 100 draws the box - useful to see what is actually being changed")
hbCard:Toggle("Enemies only", CONFIG.hbEnemy, function(v)
	hbRestoreAll()
	CONFIG.hbEnemy = v
end)
hbCard:Button("RESTORE EVERY PART NOW", function()
	hbRestoreAll()
	note("all hitbox parts restored")
end, UI.theme.band)

local hbOut = hbPage:Card("WHAT THIS IS", 2):Readout(9)

--------------------------------------------------------------------------------
-- MATCH page
--------------------------------------------------------------------------------

local matchPage = win:Page("MATCH", UI.icon.list)

matchPage:Divider("SESSION")

-- Main session stats use the full Gen2 card style like the stats showcase.
local killsStat = matchPage:Stat({
	name = "Kills",
	description = "Kills since Arsenal was loaded",
	value = 0,
	changeMode = "absolute",
})

local winsStat = matchPage:Stat({
	name = "Wins",
	description = "Wins since Arsenal was loaded",
	value = 0,
	changeMode = "absolute",
})

-- Secondary stats stay compact so the page does not turn into four huge cards.
local secondaryStats = matchPage:Row()

local deathsStat = secondaryStats:CreateStat({
	name = "Deaths",
	value = 0,
	compact = true,
	changeMode = "absolute",
})

local headshotsStat = secondaryStats:CreateStat({
	name = "Headshots",
	value = 0,
	compact = true,
	changeMode = "absolute",
})

matchPage:Divider("ROUND")
local roundOut = matchPage:Readout(5)

matchPage:Divider("PLAYERS")
local listOut = matchPage:Readout(13)

--------------------------------------------------------------------------------
-- the panel refresh
--------------------------------------------------------------------------------

task.spawn(function()
	while ENV.__ARSENAL == GEN do
		local ok, err = pcall(function()
			STATE.mode   = hudText({ "Timer", "GM" }, "-")
			STATE.sub    = hudText({ "Timer", "Sub" }, "-")
			STATE.scoreR = tonumber(hudText({ "Timer", "R" }, "0")) or 0
			STATE.scoreB = tonumber(hudText({ "Timer", "B" }, "0")) or 0
			STATE.nextWep = hudText({ "Timer", "NW" }, "-")
			STATE.aliveN = tonumber(hudText({ "PlayersAlive", "Num" }, "0")) or 0
			STATE.ffa    = ffaNow()

			updateSessionScore()

			pcall(function()
				killsStat:Set(STATE.sessionKills)
				deathsStat:Set(STATE.sessionDeaths)
				headshotsStat:Set(STATE.sessionHeadshots)
				winsStat:Set(STATE.sessionWins)
			end)

			local currentMode = tostring(STATE.mode or ""):match("^%s*(.-)%s*$")
			if currentMode ~= "" and currentMode ~= "-" and currentMode ~= lastGameMode then
				local previousMode = lastGameMode
				lastGameMode = currentMode
				gameModeColor = randomModeColor(gameModeColor)

				pcall(function()
					gameModeTag:SetText(currentMode)
					gameModeTag:SetColor(gameModeColor)
				end)

				-- Initial discovery only seeds the tag. Actual mode changes use
				-- the same randomly selected color for both tag and Altair toast.
				if previousMode then
					altairToast("Next mode: " .. currentMode, gameModeColor)
				end
			end

			local modeText = STATE.ffa and "FFA" or "TEAM"
			if modeText ~= lastModeTag then
				lastModeTag = modeText
				pcall(function()
					modeTag:SetText(modeText)
					modeTag:SetColor(STATE.ffa and MODE_BLUE or ACCENT_GREEN)
				end)
			end

			local ws = ReplicatedStorage:FindFirstChild("WinnerScore")
			STATE.leader = (ws and tostring(ws.Value)) or "-"

			STATE.level = levelOf(plr)

			-- The whole lobby, sorted by level: in a gun game that IS the
			-- scoreboard, and the HUD only shows the top few.
			local rows = {}
			local camPos = camera.CFrame.Position
			local topLvl = -1
			for _, p in ipairs(Players:GetPlayers()) do
				local lvl = levelOf(p)
				if lvl > topLvl then topLvl = lvl end
			end
			for _, p in ipairs(Players:GetPlayers()) do
				local char, hum, root = alive(p)
				local lvl = levelOf(p)
				local dist = root and math.floor((camPos - root.Position).Magnitude) or nil
				local kills = tonumber(pv(p, "ScoreFolder", "Kills", 0)) or 0
				local streak = tonumber(pv(p, "ScoreFolder", "Streak", 0)) or 0
				table.insert(rows, {
					lvl = lvl,
					me = p == plr,
					line = string.format(" %-2d %-15s %-4s %-9s %-5s %d/%d%s",
						lvl,
						p.Name:sub(1, 15),
						char and (math.floor(hum.Health) .. "") or "DEAD",
						weaponForLevel(lvl):sub(1, 9),
						dist and (dist .. "m") or "-",
						kills, streak,
						(lvl == topLvl and lvl > 0) and "  <<" or ""),
				})
			end
			table.sort(rows, function(a, b)
				if a.lvl ~= b.lvl then return a.lvl > b.lvl end
				return a.line < b.line
			end)

			local lines = { " LV NAME            HP   WEAPON    DIST  K/S" }
			for i = 1, math.min(#rows, 12) do table.insert(lines, rows[i].line) end
			pcall(function() listOut:set(lines) end)

			pcall(function()
				roundOut:set({
					string.format("  %s   %s", STATE.mode, STATE.sub),
					string.format("  score  R %d : %d B      %d alive",
						STATE.scoreR, STATE.scoreB, STATE.aliveN),
					string.format("  leader %s   targets %s   drawn %d   ghosts %d",
						STATE.leader, STATE.ffa and "everyone (FFA)" or "enemy team",
						STATE.targets, STATE.ghosts or 0),
					"  last winner  " .. tostring(STATE.lastWinner),
					"  " .. tostring(STATE.note),
				})
			end)

			local info, wname = weaponInfo()
			STATE.weapon = wname ~= "" and wname or "-"

			pcall(function()
				local fov, alpha = aimNumbers()
				aimOut:set({
					"  target   " .. tostring(STATE.target)
						.. "   shot " .. tostring(STATE.shots),
					"  state    " .. (STATE.engaged and "tracking" or "idle"),
					"  active   " .. (CONFIG.aim and "enabled" or "off")
						.. (STATE.panelOpen and CONFIG.aimPauseUI and "   PAUSED BY UI" or ""),
					"  body     " .. (currentAimMode
						or (CONFIG.aimRandomPart and (randomPartMode or "waiting for target") or CONFIG.aimPart))
						.. (CONFIG.aimDistancePart and ("   distance <= " .. CONFIG.aimHeadRangeM .. "m") or "")
						.. (CONFIG.aimRandomPart and ("   random head " .. CONFIG.aimHeadChance .. "%") or ""),
					string.format("  now      FOV %dpx   lerp %.2f", fov, alpha),
					"  weapon   L" .. tostring(STATE.level) .. "  " .. STATE.weapon
						.. (info and (info.gun and "  (firearm)"
							or (info.melee and "  (melee)" or "  (no shots)")) or ""),
				})
			end)


			pcall(function()
				trigOut:set({
					"  state    " .. (CONFIG.trig
						and (STATE.trigOn and "armed" or "waiting for target")
						or "off"),
					"  crosshair " .. tostring(STATE.underCross),
					-- Named because a trigger that never fires looks identical to one
					-- that is never armed, and on a phone it was always the former.
					"  click    " .. tostring(STATE.clickHow),
					string.format("  shots    %d   reaction %d-%dms",
						STATE.trigHits, CONFIG.trigDelayMin, CONFIG.trigDelayMax),
					"  window   " .. (CONFIG.trigFov > 0
						and (CONFIG.trigFov .. "px ring") or "centre ray only")
						.. (CONFIG.trigHeadOnly and "   head only" or ""),
				})
			end)

			pcall(function()
				rcsOut:set({
					"  MEASUREMENT",
					string.format("  sens H   %.5f   V %.5f", STATE.sensY, STATE.sensP),
					string.format("  samples  %d", STATE.calibN),
					string.format("  kick H   %.2f deg", STATE.kickY),
					string.format("  kick V   %.2f deg   peak %.2f",
						STATE.kickP, STATE.kickPeak),
					"  " .. (CONFIG.rcs
						and ((STATE.calibN > 0) and "active"
							or (TOUCH and "waiting for camera movement"
								or "waiting for mouse movement"))
						or "off"),
				})
			end)

			pcall(function()
				if not info then
					wpnOut:set({ "  WEAPON", "  " .. STATE.weapon,
						"  no entry in ReplicatedStorage.Weapons",
						"  (the level ladder names it, the folder does not carry it)" })
				elseif info.melee then
					wpnOut:set({ "  WEAPON", "  " .. info.name .. "   melee",
						"  no ammo, no fire rate - the gun gates treat it as no weapon" })
				else
					wpnOut:set({
						"  WEAPON",
						"  " .. info.name .. (info.auto and "   full auto" or "   semi auto"),
						string.format("  damage   %d   x%d per shot", info.dmg, info.bullets),
						string.format("  rate     %.3fs   magazine %d (+%d)",
							info.rate, info.ammo, info.stored),
						string.format("  spread   max %d   falloff %.2f",
							info.spread, info.falloff),
						string.format("  range    %d   reload %.2fs", info.range, info.reload),
						string.format("  recoil   %.2f   speed %+d%%",
							info.recoil, info.speed),
					})
				end
			end)

			pcall(function()
				hbOut:set({
					"  WHAT THIS IS",
					"  Arsenal gives every character a Hitbox part,",
					"  4.5 x 4 x 4 studs, invisible, CanQuery true.",
					"  This resizes THAT part on your client only.",
					"",
					"  UNVERIFIED: whether the server grades a hit",
					"  against your copy was never measured here.",
					string.format("  parts changed right now: %d", STATE.hbCount),
					"  everything is restored when this is turned off.",
				})
			end)

			pcall(function()
				win:SetStat(1, "L" .. tostring(STATE.level), "level")
				win:SetStat(2, tostring(STATE.targets), "drawn")
				win:SetStat(3, tostring(STATE.aliveN), "alive")
				-- The strip title used to be the master switch's caption. With the
				-- switch gone it carries what the script is actually doing.
				win:SetNote(STATE.note ~= "" and STATE.note or "Ready")
				win:SetStatus(string.format("%s   %s   next: %s",
					STATE.mode, STATE.weapon, STATE.nextWep))
			end)
		end)
		if not ok then note("ui: " .. tostring(err)) end
		task.wait(0.4)
	end
end)

--------------------------------------------------------------------------------
-- Match result toast
--------------------------------------------------------------------------------

do
	local winnerGui = plr.PlayerGui.GUI.Winner
	local lastName, lastToast = nil, 0

	local function getWinnerText(obj)
		if not obj then return end

		local ok, value = pcall(function()
			return obj.Text
		end)
		if not ok or type(value) ~= "string" then return end

		value = value:match("^%s*(.-)%s*$")
		if value ~= "" and value ~= "Nobody" then
			return value
		end
	end

	local function checkWinner(frame)
		task.wait(0.2)

		-- Persistent winner frame first.
		local name = getWinnerText(frame:FindFirstChild("PlayerName", true))

		-- Temporary podium clone fallback.
		if not name then
			local win1 = frame:FindFirstChild("Win1", true)
			name = getWinnerText(win1 and win1:FindFirstChild("Username", true))
		end

		if not name then return end
		if name == lastName and os.clock() - lastToast < 5 then return end

		lastName = name
		lastToast = os.clock()
		STATE.lastWinner = name

		local normalized = name:gsub("^@", ""):lower()
		local won = normalized == plr.Name:lower() or name:lower() == plr.DisplayName:lower()

		if won then
			STATE.sessionWins += 1
			altairToast("Congrats - you won the round!", RESULT_WIN_COLOR)
		else
			altairToast("Better luck next time - " .. name .. " won.", RESULT_LOSS_COLOR)
		end
	end

	winnerGui.ChildAdded:Connect(function(child)
		task.spawn(checkWinner, child)
	end)
end

--------------------------------------------------------------------------------
-- Arsenal visibility / safety pause
--------------------------------------------------------------------------------

task.spawn(function()
	local previousVisible

	while ENV.__ARSENAL == GEN do
		local visible

		pcall(function()
			if win and win.ray and type(win.ray.IsVisible) == "function" then
				visible = win.ray:IsVisible()
			elseif type(Arsenal.IsVisible) == "function" then
				visible = Arsenal:IsVisible()
			end
		end)

		if type(visible) ~= "boolean" then
			visible = win and win.root and win.root.Visible == true or false
		end

		STATE.panelOpen = visible

		if previousVisible ~= nil
			and visible ~= previousVisible
			and CONFIG.aimPauseUI
			and (CONFIG.aim or CONFIG.trig)
		then
			if visible then
				altairToast("Aim + triggerbot paused.")
			else
				altairToast("Aim + triggerbot resumed.")
			end
		end

		previousVisible = visible
		task.wait(0.1)
	end
end)

-- The camera reference is replaced on every respawn, so a cached one silently
-- stops updating after the first death - which looks exactly like "the ESP broke
-- when I died".
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then camera = workspace.CurrentCamera end
end)

pcall(function() win:Home() end)
win:Refresh()

--------------------------------------------------------------------------------

ENV.__ARSENAL_DBG = {
	CONFIG = CONFIG, STATE = STATE,
	alive = alive, isEnemy = isEnemy, visible = visible, pickTarget = pickTarget,
	renderPass = renderPass, aimPass = aimPass, rcsPass = rcsPass,
	shotClock = shotClock, aimNumbers = aimNumbers, targetPart = targetPart,
	underCrosshair = underCrosshair, pullTrigger = pullTrigger,
	weaponInfo = weaponInfo, weaponForLevel = weaponForLevel, levelOf = levelOf,
	statusTeam = statusTeam, gunGate = gunGate, airGate = airGate,
	keyHeld = keyHeld, approach = approach, angleDelta = angleDelta,
	firing = firing, hudText = hudText, ffaNow = ffaNow,
	hbApply = hbApply, hbRestoreAll = hbRestoreAll, hbSaved = hbSaved,
	refreshFilter = refreshFilter, scanGhosts = scanGhosts,
	updateSessionScore = updateSessionScore,
	sessionStats = { kills = killsStat, deaths = deathsStat, headshots = headshotsStat, wins = winsStat },
	drawn = drawn, highlights = highlights, hideAll = hideAll,
	clearChams = clearChams, note = note, pv = pv,
	TOUCH = TOUCH, screenHeld = screenHeld, reachable = reachable,
	hotkeyHeld = hotkeyHeld, aimActive = aimActive, trigActive = trigActive,
}

if TOUCH then
	note("touch client detected")
	altairNotify("Arsenal", "Touch client detected.")
elseif STATE.clickHow == "none" then
	note("this executor cannot click - triggerbot is unavailable")
	altairNotify("Arsenal", "No supported click method was found - triggerbot is unavailable.")
end

altairToast("Arsenal loaded.", Color3.fromRGB(32, 195, 140))

print("[arsenal] gen " .. GEN .. " ready - RightShift for the panel"
	.. (TOUCH and "  (touch client, click: " .. STATE.clickHow .. ")" or ""))
