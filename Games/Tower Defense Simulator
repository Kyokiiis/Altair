--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!
]]
-- [[ CONFIGURATION ]]
_G.AutoStrat = false
_G.AutoSkip = false
_G.AutoSnowballs = false

-- Always start this UI in a passive/manual state. This also neutralizes most
-- automation loops left behind by an older execution in the same Roblox session.
local ADS_BOOTSTRAP_ENV = getgenv()

-- Altair integration. Altair.lua is intentionally not modified by this script.
-- The API is resolved dynamically so Altair can be executed before or after this file.
local ALTAIR_INFO_COLOR = Color3.fromRGB(110, 180, 255)
local ALTAIR_SUCCESS_COLOR = Color3.fromRGB(90, 210, 125)
local ALTAIR_WARNING_COLOR = Color3.fromRGB(255, 190, 80)
local ALTAIR_ERROR_COLOR = Color3.fromRGB(235, 80, 80)

local function GetAltairAPI()
    local env = getgenv()
    local api = env and env.Altair
    return type(api) == "table" and api or nil
end

local function AltairBlink(count, color)
    local api = GetAltairAPI()
    if api and type(api.BlinkSmartBar) == "function" then
        return pcall(api.BlinkSmartBar, count or 1, color)
    end
    return false
end

local function AltairToast(content, color, skipBlink)
    local api = GetAltairAPI()
    if api and type(api.Toast) == "function" then
        return pcall(api.Toast, tostring(content or ""), color, nil, skipBlink == true)
    end
    print("[ADS] " .. tostring(content or ""))
    return false
end

-- Hard game gate: only allow this script to initialize inside Tower Defense Simulator.
-- We read the current PlaceId for diagnostics, but validate the universe so the script
-- continues to work in both the TDS lobby and TDS match places.
local TDS_MAIN_PLACE_ID = 3260590327
local TDS_UNIVERSE_ID = 1176784616
local CURRENT_PLACE_ID = game.PlaceId
local CURRENT_UNIVERSE_ID = game.GameId

if CURRENT_UNIVERSE_ID ~= TDS_UNIVERSE_ID then
    AltairToast(
        ("TDS script aborted - this experience is not Tower Defense Simulator."),
        ALTAIR_ERROR_COLOR,
        false
    )
    return
end

local function AltairQueueNotification(title, description, image)
    local api = GetAltairAPI()
    local queue = api and (api.QueueNotification or api.Notify)
    if type(queue) == "function" then
        return pcall(queue, tostring(title or "ADS"), tostring(description or ""), tonumber(image))
    end
    print(("[ADS] %s: %s"):format(tostring(title or "Notification"), tostring(description or "")))
    return false
end

local function AltairNotify(props)
    props = props or {}

    local title = tostring(props.Title or props.Name or "ADS")
    local description = tostring(props.Desc or props.Content or props.Description or "")
    local kind = tostring(props.Type or "normal"):lower()
    local duration = tonumber(props.Time or props.Duration) or 3
    local image = tonumber(props.Image or props.Icon)

    if kind == "error" then
        AltairBlink(2, ALTAIR_ERROR_COLOR)
        AltairToast((title ~= "ADS" and (title .. ": ") or "") .. description, ALTAIR_ERROR_COLOR, true)
        AltairQueueNotification(title, description, image or 4370336704)
        return
    elseif kind == "warning" or kind == "warn" then
        AltairBlink(1, ALTAIR_WARNING_COLOR)
        AltairToast((title ~= "ADS" and (title .. ": ") or "") .. description, ALTAIR_WARNING_COLOR, true)
        AltairQueueNotification(title, description, image or 4370305588)
        return
    end

    local looksSuccessful = kind == "success"
        or description:lower():find("success", 1, true) ~= nil
        or description:lower():find("saved", 1, true) ~= nil
        or description:lower():find("loaded", 1, true) ~= nil

    local toastColor = looksSuccessful and ALTAIR_SUCCESS_COLOR or ALTAIR_INFO_COLOR
    local toastText = (title ~= "ADS" and (title .. ": ") or "") .. description

    -- Short status messages fit Altair's toast surface. Longer explanations use
    -- the queued notification surface so the full description remains readable.
    if duration <= 5 and #description <= 110 then
        AltairToast(toastText, toastColor, false)
    else
        AltairQueueNotification(title, description, image or 4400695581)
    end
end

local function AltairWarn(message, title)
    local description = tostring(message or "Unknown warning")
    AltairBlink(2, ALTAIR_WARNING_COLOR)
    AltairToast(description, ALTAIR_WARNING_COLOR, true)
    AltairQueueNotification(title or "Warning", description, 4370305588)
end
local ADS_MANUAL_START_KEYS = {
    "AutoSkip", "AutoOpenCrates", "AutoReady", "AutoChain", "AutoGatling",
    "Gatlify", "SupportCaravan", "AutoDJ", "AutoNecro",
    "AutoRejoin", "AutoRestart", "TimeScaleEnabled", "SellFarms",
    "AutoMercenary", "AutoMilitary", "Frost", "Fallen", "Easy",
    "AutoPickups", "ClaimRewards", "AutoProgressionLoader",
    "AutoProgressionEnabled", "AutoMedic", "AutoTrials"
}
for _, key in ipairs(ADS_MANUAL_START_KEYS) do
    ADS_BOOTSTRAP_ENV[key] = false
end

if ADS_BOOTSTRAP_ENV.ADS_StopEmbeddedStrategy then
    pcall(ADS_BOOTSTRAP_ENV.ADS_StopEmbeddedStrategy)
end
if ADS_BOOTSTRAP_ENV.ADS_RayfieldWindow and ADS_BOOTSTRAP_ENV.ADS_RayfieldWindow.Unload then
    pcall(function() ADS_BOOTSTRAP_ENV.ADS_RayfieldWindow:Unload() end)
    ADS_BOOTSTRAP_ENV.ADS_RayfieldWindow = nil
end
if isfile and delfile and isfile("ADS_EmbeddedStrategyArmed.flag") then
    pcall(delfile, "ADS_EmbeddedStrategyArmed.flag")
end

-- [[ WEBHOOK SETTINGS ]]
_G.SendWebhook = false -- Set to true to enable notifications
_G.Webhook = "YOUR-WEBHOOK-URL-HERE" 

-- [[ INITIALIZE LIBRARY ]]
local TDS = (function()
local Globals = getgenv()

-- Never return a stale TDSTable here. Re-executing the script must rebuild the
-- current Rayfield UI instead of silently reusing an older library instance.
if shared.TDSTable then
    shared.TDSTable = nil
    shared["TDS_Table"] = nil
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local Window
local function SmartTeleportToLobby()
    local lobbyId = 3260590327
    pcall(function()
        local platform = UserInputService:GetPlatform()
        local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
        
        if not IsMobile and Globals.PrivateCode and Globals.PrivateCode ~= "" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = lobbyId, 
                linkCode = Globals.PrivateCode
            })
        else
            TeleportService:Teleport(lobbyId)
        end
    end)

    task.spawn(function()
        task.wait(10)
        if Window then
            AltairNotify({
                Title = "Teleport Failed",
                Desc = "It looks like you're stuck! If you are using Delta, please ensure that 'Verify Teleports' is disabled in your settings.",
                Time = 9999,
                Type = "error"
            })
            task.wait(5)
            AltairNotify({
                Title = "Fixing Delta Teleport Issues",
                Desc = "1. Disconnect from the game\n" ..
                       "2. Completely empty your 'autoexecute' folder\n" ..
                       "3. Reopen Roblox and join the game\n" ..
                       "4. Go to Delta settings and disable 'Verify Teleports'\n" ..
                       "5. Disconnect and rejoin to confirm 'Verify Teleports' remains OFF\n" ..
                       "6. Once verified, restore your files to 'autoexecute' and rejoin",
                Time = 9999,
                Type = "normal"
            })
        end
    end)
end

local function Reconnect()
    local initialCode = GuiService:GetErrorCode()
    
    if initialCode and initialCode ~= Enum.ConnectionError.OK then
        task.wait(5)
        
        if GuiService:GetErrorCode() == initialCode then
            pcall(function()
                TeleportService:TeleportReconnect()
            end)
        end
    end
end

local function AntiStuck()
    task.spawn(function()
        local secondsStuck = 0

        while true do 
            task.wait(1)
            
            local attrLoading = LocalPlayer:GetAttribute("Loading") == true
            local attrTeleporting = LocalPlayer:GetAttribute("Teleporting") == true
            
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            local loadScreen = pg and pg:FindFirstChild("LoadingScreen")
            local loadContent = loadScreen and loadScreen:FindFirstChild("content")
            local isLoadVisible = loadContent and loadContent.Visible == true
            
            local countScreen = pg and pg:FindFirstChild("PlayerCountdown")
            local countFrame = countScreen and countScreen:FindFirstChild("Frame")
            local isCountVisible = countFrame and countFrame.Visible == true

            if attrLoading or attrTeleporting or isLoadVisible or isCountVisible then
                secondsStuck = secondsStuck + 1
                if secondsStuck >= 60 then
                    pcall(SmartTeleportToLobby)
                    secondsStuck = 0 
                end
            else
                secondsStuck = 0 
            end
        end
    end)
end

-- Recovery helpers are intentionally manual/passive in this merged build.
-- They used to start immediately and could teleport/reconnect without a UI action.
local ADS_AUTOMATIC_RECOVERY = false
if ADS_AUTOMATIC_RECOVERY then
    AntiStuck()
    task.spawn(Reconnect)
    GuiService.ErrorMessageChanged:Connect(Reconnect)
end

if not game:IsLoaded() then game.Loaded:Wait() end

local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local mouse = LocalPlayer:GetMouse()
local RemoteFunc = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local FileName = "ADS_Config.json"
local Logger
local StartBackToLobby
local platform = UserInputService:GetPlatform()
local IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)

task.spawn(function()
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

task.spawn(function()
    pcall(function()
        RemoteFunc:InvokeServer("Settings", "Update", "Show Nametags", false)
    end)
end)

local function IdentifyGameState()
    local players = game:GetService("Players")
    local TempPlayer = players.LocalPlayer or players.PlayerAdded:Wait()
    local TempGui = TempPlayer:WaitForChild("PlayerGui")

    while true do
        if TempGui:FindFirstChild("ReactLobbyHud") then
            return "LOBBY"
        elseif TempGui:FindFirstChild("ReactUniversalHotbar") then
            return "GAME"
        end
        task.wait(1)
    end
end

local GameState = IdentifyGameState()

local function StartAntiAfk()
    task.spawn(function()
        local LobbyTimer = 0
        while GameState == "LOBBY" do 
            task.wait(1)
            LobbyTimer = LobbyTimer + 1
            if LobbyTimer >= 600 then
                SmartTeleportToLobby()
                break 
            end
        end
    end)
end

if ADS_AUTOMATIC_RECOVERY then
    StartAntiAfk()
end

local SendRequest = request or http_request or httprequest
    or GetDevice and GetDevice().request

if not SendRequest then 
    AltairWarn("No HTTP request function is available.", "HTTP Error") 
    return 
end

local BackToLobbyRunning = false
local AutoPickupsRunning = false
local AutoSkipRunning = false
local AutoClaimRewards = false
local AntiLagRunning = false
local AutoChainRunning = false
local AutoDjRunning = false
local AutoNecroRunning = false
local TimeScaleRunning = false
local TimeScaleNoTicketsWarned = false
local AutoMercenaryBaseRunning = false
local AutoMilitaryBaseRunning = false
local SellFarmsRunning = false
local AutoGatlingRunning = false
local GatlingExecuted = false
local GatlifyRunning = false
local GatlifyExecuted = false
local IsCurrentlyLoading = false
local LastLoadTime = 0
local IsEquippingLoadout = false

local MaxPathDistance = 300 -- default
local MilMarker = nil
local MercMarker = nil

local CurrentEquippedTowers = {"None"}

local StackEnabled = false
local SelectedTower = nil
local StackSphere = nil

local AutoMedicRunning = false
local _AutoTrialsRunning = false

local AllModifiers = {
    "HiddenEnemies", "Glass", "ExplodingEnemies", "Limitation", 
    "Committed", "HealthyEnemies", "Fog", "FlyingEnemies", 
    "Broke", "SpeedyEnemies", "Quarantine", "JailedTowers", "Inflation"
}

local DefaultSettings = {
    PathVisuals = false,
    MilitaryPath = false,
    MercenaryPath = false,
    AutoSkip = false,
    AutoOpenCrates = false,
    SelectedCrate = "All",
    AutoReady = false,
    AutoChain = false,
    AutoGatling = false,
    Gatlify = false,
    SupportCaravan = false,
    AutoDJ = false,
    DJCustomSongID = "",
    AutoNecro = false,
    AutoRejoin = false,
    AutoRestart = false,
    PrivateCode = "",
    TimeScaleEnabled = false,
    TimeScaleValue = 2,
    SellFarms = false,
    AutoMercenary = false,
    AutoMilitary = false,
    Frost = false,
    Fallen = false,
    Easy = false,
    AntiLag = false,
    Disable3DRendering = false,
    AutoPickups = false,
    ClaimRewards = false,
    SendWebhook = false,
    NoRecoil = false,
    SellFarmsWave = 1,
    Snapper = false,
    WebhookURL = "",
    PickupMethod = "Pathfinding",
    StreamerMode = false,
    HideUsername = false,
    BuffOverlay = false,
    StreamerName = "",
    tagName = "None",
    Modifiers = {},
    AutoProgressionMode = "None",
    AutoProgressionLoader = false,
    AutoProgressionEnabled = false,
    ProgressionWebhookURL = "",
    SendProgressionWebhook = false,
    AutoProgressionStatus = "Status: waiting... | Mode: None",
    AutoMedic = false,
    AutoTrials = false
}

local TowerSnapper = {
    Enabled = Globals.Snapper ~= nil and Globals.Snapper or true,
    MaxRadius = 16,
    CoarseStep = 0.35,
    FineStep = 0.08,
    SpacingOffset = 0.04,
    LastInput = nil,
    LastSnapped = nil,
    LastHit = nil,
    LastValid = false,
    TowerCount = 0
}

local BuffOverlay = {
    Enabled = true,
    AuraVisuals = {},
    PulseClock = 0,
    BasePreviewRange = nil,
    CurrentExpandedRange = nil,
    SupportDefinitions = {
        ["DJ Booth"] = {
            Tag = "DJ",
            Color = Color3.fromRGB(255, 43, 79),
            GlowColor = Color3.fromRGB(255, 90, 120),
            FallbackRanges = { [0] = 12, [1] = 15, [2] = 15, [3] = 15, [4] = 16.5, [5] = 18 }
        },
        ["Commander"] = {
            Tag = "CMD",
            Color = Color3.fromRGB(0, 210, 255),
            GlowColor = Color3.fromRGB(120, 235, 255),
            FallbackRanges = { [0] = 10, [1] = 10, [2] = 13, [3] = 15, [4] = 17 }
        },
        ["Medic"] = {
            Tag = "MED",
            Color = Color3.fromRGB(0, 255, 163),
            GlowColor = Color3.fromRGB(120, 255, 210),
            FallbackRanges = { [0] = 12, [1] = 12, [2] = 14, [3] = 15, [4] = 18, [5] = 20 }
        }
    }
}

local TimeScaleValues = {0.5, 1, 1.5, 2}

local function NormalizeTimeScaleValue(val)
    val = tonumber(val)
    if not val then
        return nil
    end
    for _, v in ipairs(TimeScaleValues) do
        if v == val then
            return v
        end
    end
    return nil
end

local function CoerceTimeScaleValue(val, fallback)
    return NormalizeTimeScaleValue(val) or fallback
end

local function GetTimescaleFrame()
    local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
    local frame = hotbar and hotbar:FindFirstChild("Frame")
    return frame and frame:FindFirstChild("timescale")
end

local StartTimeScale
local ApplyTimeScaleOnce

-- // icon item ids ill add more soon arghh
local ItemNames = {
    ["17447507910"] = "Timescale Ticket(s)",
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["18443277591"] = "High Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
    ["110415073436604"] = "Holy Hand Grenade(s)",
    ["17429533728"] = "Frag Grenade(s)",
    ["17437703262"] = "Molotov(s)",
    ["139414922355803"] = "Present Clusters(s)"
}

local executed_actions = {}

-- // tower management core
TDS = {
    PlacedTowers = {},
    ActiveStrat = true,
    IsEquippingLoadout = false,
    LoadoutPending = false,
    MatchmakingMap = {
        ["PizzaParty"] = "halloween",
        ["Badlands"] = "badlands",
        ["PollutedWasteland"] = "polluted",
        ["DuckyEasy"] = "ducky2025",
        ["DuckyHard"] = "ducky2025"
    }
}
TDS["placed_towers"] = TDS.PlacedTowers
TDS["active_strat"] = TDS.ActiveStrat
TDS["matchmaking_map"] = TDS.MatchmakingMap

local UpgradeHistory = {}

-- // shared for addons
shared.TDSTable = TDS
shared["TDS_Table"] = TDS

function TDS:ResetAllStates()
    table.clear(self.PlacedTowers)
    table.clear(UpgradeHistory)
    table.clear(executed_actions)
    if Logger and Logger.Clear then
        pcall(function()
            Logger:Clear()
            Logger:Log("Restarting strategy...")
        end)
    end
end

function TDS:RunStrategy()
    if Globals.activeStrategyThread then
        pcall(task.cancel, Globals.activeStrategyThread)
        Globals.activeStrategyThread = nil
    end

    Globals.activeStrategyThread = task.spawn(function()
        Globals.tdsReplaying = true
        pcall(function()
            loadstring(readfile("ADS_LastStrat.lua"))()
        end)
        Globals.tdsReplaying = false
        Globals.activeStrategyThread = nil
    end)
end

-- // load & save
local function SaveSettings()
    local DataToSave = {}
    for key, _ in pairs(DefaultSettings) do
        DataToSave[key] = Globals[key]
    end
    writefile(FileName, HttpService:JSONEncode(DataToSave))
end

local function LoadSettings()
    local data = {}
    if isfile(FileName) then
        pcall(function()
            data = HttpService:JSONDecode(readfile(FileName))
        end)
    end

    for key, DefaultVal in pairs(DefaultSettings) do
        if Globals[key] == nil then
            if data[key] ~= nil then
                Globals[key] = data[key]
            else
                Globals[key] = DefaultVal
            end
        end
    end
    
    SaveSettings()
end

local function SetSetting(name, value)
    if DefaultSettings[name] ~= nil then
        if name == "TimeScaleValue" then
            value = CoerceTimeScaleValue(value, Globals.TimeScaleValue or 2)
        end
        Globals[name] = value
        SaveSettings()
    end
end

local function Apply3dRendering()
    if Globals.Disable3DRendering then
        game:GetService("RunService"):Set3dRenderingEnabled(false)
    else
        RunService:Set3dRenderingEnabled(true)
    end
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = PlayerGui and PlayerGui:FindFirstChild("ADS_BlackScreen")
    if Globals.Disable3DRendering then
        if PlayerGui and not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "ADS_BlackScreen"
            gui.IgnoreGuiInset = true
            gui.ResetOnSpawn = false
            gui.DisplayOrder = -1000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = PlayerGui
            local frame = Instance.new("Frame")
            frame.Name = "Cover"
            frame.BackgroundColor3 = Color3.new(0, 0, 0)
            frame.BorderSizePixel = 0
            frame.Size = UDim2.fromScale(1, 1)
            frame.ZIndex = 0
            frame.Parent = gui
        end
        gui.Enabled = true
    else
        if gui then
            gui.Enabled = false
        end
    end
end

LoadSettings()

-- Saved preferences may contain automation toggles from an older session. Keep
-- non-automation preferences, but require every automation feature to be enabled
-- manually after this execution starts. Do not write these forced-off values back
-- to disk until the user actually changes a setting.
for _, key in ipairs(ADS_MANUAL_START_KEYS) do
    Globals[key] = false
end

Globals.TimeScaleValue = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)
Apply3dRendering()

local isTagChangerRunning = false
local tagChangerConn = nil
local tagChangerTag = nil
local tagChangerOrig = nil

local function collectTagOptions()
    local list = {}
    local seen = {}
    local function addFolder(folder)
        if not folder then
            return
        end
        for _, child in ipairs(folder:GetChildren()) do
            local childName = child.Name
            if childName and not seen[childName] then
                seen[childName] = true
                list[#list + 1] = childName
            end
        end
    end
    local content = ReplicatedStorage:FindFirstChild("Content")
    if content then
        local nametag = content:FindFirstChild("Nametag")
        if nametag then
            addFolder(nametag:FindFirstChild("Basic"))
            addFolder(nametag:FindFirstChild("Exclusive"))
        end
    end
    table.sort(list)
    table.insert(list, 1, "None")
    return list
end

local function stopTagChanger()
    if tagChangerConn then
        tagChangerConn:Disconnect()
        tagChangerConn = nil
    end
    if tagChangerTag and tagChangerTag.Parent and tagChangerOrig ~= nil then
        pcall(function()
            tagChangerTag.Value = tagChangerOrig
        end)
    end
    tagChangerTag = nil
    tagChangerOrig = nil
end

local function startTagChanger()
    if isTagChangerRunning then
        return
    end
    isTagChangerRunning = true
    task.spawn(function()
        while Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" do
            local tag = LocalPlayer:FindFirstChild("Tag")
            if tag then
                if tagChangerTag ~= tag then
                    if tagChangerConn then
                        tagChangerConn:Disconnect()
                        tagChangerConn = nil
                    end
                    tagChangerTag = tag
                    if tagChangerOrig == nil then
                        tagChangerOrig = tag.Value
                    end
                end
                if tag.Value ~= Globals.tagName then
                    tag.Value = Globals.tagName
                end
                if not tagChangerConn then
                    tagChangerConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
                        if Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" then
                            if tag.Value ~= Globals.tagName then
                                tag.Value = Globals.tagName
                            end
                        end
                    end)
                end
            end
            task.wait(0.5)
        end
        isTagChangerRunning = false
    end)
end

if Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" then
    startTagChanger()
end

local OriginalDisplayName = LocalPlayer.DisplayName
local OriginalUserName = LocalPlayer.Name

local SpoofTextCache = setmetatable({}, {__mode = "k"})
local PrivacyRunning = false
local LastSpoofName = nil
local PrivacyConns = {}
local PrivacyTextNodes = setmetatable({}, {__mode = "k"})
local StreamerTag = nil
local StreamerTagOrig = nil
local StreamerTagConn = nil

local function AddPrivacyConn(conn)
    if conn then
        PrivacyConns[#PrivacyConns + 1] = conn
    end
end

local function ClearPrivacyConns()
    for _, c in ipairs(PrivacyConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    PrivacyConns = {}
    for inst in pairs(PrivacyTextNodes) do
        PrivacyTextNodes[inst] = nil
    end
end

local function MakeSpoofName()
    return "BelowNatural"
end

local function EnsureSpoofName()
    local nm = Globals.StreamerName
    if not nm or nm == "" then
        nm = MakeSpoofName()
        SetSetting("StreamerName", nm)
    end
    return nm
end

local function IsTagChangerActive()
    return Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None"
end

local function SetLocalDisplayName(nm)
    if not nm or nm == "" then
        return
    end
    pcall(function()
        LocalPlayer.DisplayName = nm
    end)
end

local function ReplacePlain(str, old, new)
    if not str or str == "" or not old or old == "" or old == new then
        return str, false
    end
    local start = 1
    local out = {}
    local changed = false
    while true do
        local i, j = string.find(str, old, start, true)
        if not i then
            out[#out + 1] = string.sub(str, start)
            break
        end
        changed = true
        out[#out + 1] = string.sub(str, start, i - 1)
        out[#out + 1] = new
        start = j + 1
    end
    if changed then
        return table.concat(out), true
    end
    return str, false
end

local function ApplySpoofToInstance(inst, OldA, OldB, NewName)
    if not inst then
        return
    end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        local txt = inst.Text
        if type(txt) == "string" and txt ~= "" then
            local HasA = OldA and OldA ~= "" and string.find(txt, OldA, 1, true)
            local HasB = OldB and OldB ~= "" and string.find(txt, OldB, 1, true)
            if not HasA and not HasB then
                return
            end
            local t = txt
            local changed = false
            local ch
            if OldA and OldA ~= "" then
                t, ch = ReplacePlain(t, OldA, NewName)
                if ch then changed = true end
            end
            if OldB and OldB ~= "" then
                t, ch = ReplacePlain(t, OldB, NewName)
                if ch then changed = true end
            end
            if changed then
                if SpoofTextCache[inst] == nil then
                    SpoofTextCache[inst] = txt
                end
                inst.Text = t
            end
        end
    end
end

local function RestoreSpoofText()
    for inst, txt in pairs(SpoofTextCache) do
        if inst and inst.Parent then
            pcall(function()
                inst.Text = txt
            end)
        end
        SpoofTextCache[inst] = nil
    end
end

local function GetPrivacyName()
    if Globals.StreamerMode then
        return EnsureSpoofName()
    end
    if Globals.HideUsername then
        return "████████"
    end
    return nil
end

local function AddPrivacyNode(inst)
    if not (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
        return
    end
    PrivacyTextNodes[inst] = true
    local nm = GetPrivacyName()
    if nm then
        ApplySpoofToInstance(inst, OriginalDisplayName, OriginalUserName, nm)
    end
end

local function HookPrivacyRoot(root)
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        AddPrivacyNode(inst)
    end
    AddPrivacyConn(root.DescendantAdded:Connect(function(inst)
        if GetPrivacyName() then
            AddPrivacyNode(inst)
        end
    end))
end

local function SweepPrivacyText(nm)
    for inst in pairs(PrivacyTextNodes) do
        if inst and inst.Parent then
            ApplySpoofToInstance(inst, OriginalDisplayName, OriginalUserName, nm)
        else
            PrivacyTextNodes[inst] = nil
        end
    end
end

local function ApplyStreamerTag()
    if IsTagChangerActive() then
        if StreamerTagConn then
            StreamerTagConn:Disconnect()
            StreamerTagConn = nil
        end
        StreamerTag = nil
        StreamerTagOrig = nil
        return
    end
    local nm = EnsureSpoofName()
    local tag = LocalPlayer:FindFirstChild("Tag")
    if not tag then
        return
    end
    if StreamerTag and StreamerTag ~= tag then
        if StreamerTagConn then
            StreamerTagConn:Disconnect()
            StreamerTagConn = nil
        end
    end
    if StreamerTag ~= tag then
        StreamerTag = tag
        StreamerTagOrig = tag.Value
    end
    if tag.Value ~= nm then
        tag.Value = nm
    end
    if StreamerTagConn then
        StreamerTagConn:Disconnect()
        StreamerTagConn = nil
    end
    StreamerTagConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
        if not Globals.StreamerMode then
            return
        end
        if IsTagChangerActive() then
            return
        end
        local nm2 = EnsureSpoofName()
        if tag.Value ~= nm2 then
            tag.Value = nm2
        end
    end)
end

local function RestoreStreamerTag()
    if StreamerTagConn then
        StreamerTagConn:Disconnect()
        StreamerTagConn = nil
    end
    if IsTagChangerActive() then
        StreamerTag = nil
        StreamerTagOrig = nil
        return
    end
    if StreamerTag and StreamerTag.Parent and StreamerTagOrig ~= nil then
        pcall(function()
            StreamerTag.Value = StreamerTagOrig
        end)
    end
    StreamerTag = nil
    StreamerTagOrig = nil
end

local function ApplyPrivacyOnce()
    local nm = GetPrivacyName()
    if not nm then
        return
    end
    if LastSpoofName and LastSpoofName ~= nm then
        RestoreSpoofText()
    end
    if Globals.StreamerMode then
        ApplyStreamerTag()
    else
        RestoreStreamerTag()
    end
    SetLocalDisplayName(nm)
    SweepPrivacyText(nm)
    LastSpoofName = nm
end

local function StopPrivacyMode()
    ClearPrivacyConns()
    RestoreSpoofText()
    LastSpoofName = nil
    RestoreStreamerTag()
    SetLocalDisplayName(OriginalDisplayName)
    PrivacyRunning = false
end

local function StartPrivacyMode()
    if PrivacyRunning then
        return
    end
    PrivacyRunning = true
    ClearPrivacyConns()
    ApplyPrivacyOnce()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        HookPrivacyRoot(pg)
    end
    local CoreGui = game:GetService("CoreGui")
    if CoreGui then
        HookPrivacyRoot(CoreGui)
    end
    local TagsRoot = workspace:FindFirstChild("Nametags")
    if TagsRoot then
        HookPrivacyRoot(TagsRoot)
    end
    local ch = LocalPlayer.Character
    if ch then
        HookPrivacyRoot(ch)
    end
    AddPrivacyConn(LocalPlayer.CharacterAdded:Connect(function(NewChar)
        if GetPrivacyName() then
            HookPrivacyRoot(NewChar)
            ApplyPrivacyOnce()
        end
    end))
    AddPrivacyConn(workspace.ChildAdded:Connect(function(inst)
        if GetPrivacyName() and inst.Name == "Nametags" then
            HookPrivacyRoot(inst)
            ApplyPrivacyOnce()
        end
    end))
    local function step()
        if not GetPrivacyName() then
            StopPrivacyMode()
            return
        end
        ApplyPrivacyOnce()
        task.delay(0.5, step)
    end
    task.defer(step)
end

local function UpdatePrivacyState()
    if GetPrivacyName() then
        if not PrivacyRunning then
            StartPrivacyMode()
        else
            ApplyPrivacyOnce()
        end
    else
        if PrivacyRunning then
            StopPrivacyMode()
        end
    end
end

UpdatePrivacyState()

-- // for calculating path
local function FindPath()
    local MapFolder = workspace:FindFirstChild("Map")
    if not MapFolder then return nil end
    local PathsFolder = MapFolder:FindFirstChild("Paths")
    if not PathsFolder then return nil end
    local PathFolder = PathsFolder:GetChildren()[1]
    if not PathFolder then return nil end

    local PathNodes = {}
    for _, node in ipairs(PathFolder:GetChildren()) do
        if node:IsA("BasePart") then
            table.insert(PathNodes, node)
        end
    end

    table.sort(PathNodes, function(a, b)
        local NumA = tonumber(a.Name:match("%d+"))
        local NumB = tonumber(b.Name:match("%d+"))
        if NumA and NumB then return NumA < NumB end
        return a.Name < b.Name
    end)

    return PathNodes
end

local function TotalLength(PathNodes)
    local TotalLength = 0
    for i = 1, #PathNodes - 1 do
        TotalLength = TotalLength + (PathNodes[i + 1].Position - PathNodes[i].Position).Magnitude
    end
    return TotalLength
end

local MercenarySlider
local MilitarySlider
local MaxLenght

local function CalcLength()
    local map = workspace:FindFirstChild("Map")

    if GameState == "GAME" and map then
        local PathNodes = FindPath()

        if PathNodes and #PathNodes > 0 then
            MaxPathDistance = TotalLength(PathNodes)

            if MercenarySlider then
                MercenarySlider:SetMax(MaxPathDistance) 
            end

            if MilitarySlider then
                MilitarySlider:SetMax(MaxPathDistance)
            end

            if MaxLenght then
                MaxLenght = MaxPathDistance
            end
            return true
        end
    end
    return false
end

local function GetPointAtDistance(PathNodes, distance)
    if not PathNodes or #PathNodes < 2 then return nil end

    local CurrentDist = 0
    for i = 1, #PathNodes - 1 do
        local StartPos = PathNodes[i].Position
        local EndPos = PathNodes[i+1].Position
        local SegmentLen = (EndPos - StartPos).Magnitude

        if CurrentDist + SegmentLen >= distance then
            local remaining = distance - CurrentDist
            local direction = (EndPos - StartPos).Unit
            return StartPos + (direction * remaining)
        end
        CurrentDist = CurrentDist + SegmentLen
    end
    return PathNodes[#PathNodes].Position
end

local function UpdatePathVisuals()
    if not Globals.PathVisuals then
        if MilMarker then 
            MilMarker:Destroy() 
            MilMarker = nil 
        end
        if MercMarker then 
            MercMarker:Destroy() 
            MercMarker = nil 
        end
        return
    end

    local PathNodes = FindPath()
    if not PathNodes then return end

    if not MilMarker then
        MilMarker = Instance.new("Part")
        MilMarker.Name = "MilVisual"
        MilMarker.Shape = Enum.PartType.Cylinder
        MilMarker.Size = Vector3.new(0.3, 3, 3)
        MilMarker.Color = Color3.fromRGB(0, 255, 0)
        MilMarker.Material = Enum.Material.Plastic
        MilMarker.Anchored = true
        MilMarker.CanCollide = false
        MilMarker.Orientation = Vector3.new(0, 0, 90)
        MilMarker.Parent = workspace
    end

    if not MercMarker then
        MercMarker = MilMarker:Clone()
        MercMarker.Name = "MercVisual"
        MercMarker.Color = Color3.fromRGB(255, 0, 0)
        MercMarker.Parent = workspace
    end

    local MilPos = GetPointAtDistance(PathNodes, Globals.MilitaryPath or 0)
    local MercPos = GetPointAtDistance(PathNodes, Globals.MercenaryPath or 0)

    if MilPos then
        MilMarker.Position = MilPos + Vector3.new(0, 0.2, 0)
        MilMarker.Transparency = 0.7
    end
    if MercPos then
        MercMarker.Position = MercPos + Vector3.new(0, 0.2, 0)
        MercMarker.Transparency = 0.7
    end
end

local function MissionsUIFix()
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                local MissionsScrollingFrame = game:GetService("Players").LocalPlayer.PlayerGui.ReactLobbyQuests.quests.missions.scrollingFrame
                local MissionsListLayout = MissionsScrollingFrame.listLayout
                local MissionFrame = MissionsScrollingFrame["1"]
                if MissionFrame.AbsoluteSize.Y > 0 then
                    local UIScaleRatio = MissionFrame.AbsoluteSize.Y / MissionFrame.Size.Y.Offset
                    local CurrentCanvasSize = MissionsScrollingFrame.CanvasSize
                    local CanvasHeight = (MissionsListLayout.AbsoluteContentSize.Y / UIScaleRatio) + 25
                    MissionsScrollingFrame.CanvasSize = UDim2.new(CurrentCanvasSize.X.Scale, CurrentCanvasSize.X.Offset, CurrentCanvasSize.Y.Scale, CanvasHeight)
                end
            end)
        end
    end)
end

local function GetEquippedTowers()
    local towers = {}
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")

    if StateReplicators then
        for _, folder in ipairs(StateReplicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                local equipped = folder:GetAttribute("EquippedTowers")
                if type(equipped) == "string" then
                    local CleanedJson = equipped:match("%[.*%]") 
                    local success, TowerTable = pcall(function()
                        return HttpService:JSONDecode(CleanedJson)
                    end)

                    if success and type(TowerTable) == "table" then
                        for i = 1, 5 do
                            if TowerTable[i] then
                                table.insert(towers, TowerTable[i])
                            end
                        end
                    end
                end
            end
        end
    end
    return #towers > 0 and towers or {"None"}
end

CurrentEquippedTowers = GetEquippedTowers()

local CrateList = {
    "All", "Basic", "Premium", "Deluxe", "Golden", "Bunny", "Halloween 2019", 
    "Party", "Toy", "Valentines", "Xmas 2019", "Spooky", "Pumpkin", "Frost", 
    "Lovely", "Cold Front", "Ducky", "Vigilante", "Pirate", "Phantom", 
    "Halloween", "Jolly", "Lunar", "Lovestruck", "UglyCrate", "Coin Crate", 
    "Banned", "Christmas 2025", "Showtime", "Valentines 2026", "Shamrock",
    "Low Grade", "Mid Grade", "High Grade"
}

local AutoOpenRunning = false

local function StartAutoOpenCrates()
    if AutoOpenRunning or not Globals.AutoOpenCrates then return end
    AutoOpenRunning = true

    for _, crateName in ipairs(CrateList) do
        if crateName == "All" then continue end

        task.spawn(function()
            while Globals.AutoOpenCrates do
                if Globals.SelectedCrate == "All" or Globals.SelectedCrate == crateName then
                    local success, res = pcall(function()
                        return RemoteFunc:InvokeServer("Inventory", "Open", "Crate", crateName)
                    end)

                    if success and type(res) == "table" then
                        task.wait(0.1) 
                    else
                        task.wait(5)
                    end
                else
                    task.wait(1)
                end
            end
        end)
    end

    task.spawn(function()
        repeat task.wait(1) until not Globals.AutoOpenCrates
        AutoOpenRunning = false
    end)
end

-- // voting & map selection
local function RunVoteSkip()
    while true do
        local success = pcall(function()
            RemoteFunc:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.1)
    end
end

AutoReadyRunning = false

local function StartAutoReady()
    if AutoReadyRunning or not Globals.AutoReady or GameState ~= "GAME" then return end
    AutoReadyRunning = true

    task.spawn(function()
        local voteReplicator = ReplicatedStorage:WaitForChild("StateReplicators"):WaitForChild("VoteReplicator")
        
        repeat task.wait(0.1) until voteReplicator:GetAttribute("Enabled") == true and voteReplicator:GetAttribute("Title") == "Ready?"
        
        RunVoteSkip()
        
        repeat task.wait(0.1) until voteReplicator:GetAttribute("Enabled") == false
        
        AutoReadyRunning = false
    end)
end

local EasyModeRunning = false

local function StartEasyMode()
    if EasyModeRunning or not Globals.Easy then return end

    EasyModeRunning = true

    task.spawn(function()
        local content = nil

        while Globals.Easy and content == nil do
            local success, res = pcall(function() 
                return game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Easy.lua") 
            end)

            if success and type(res) == "string" then
                content = res
            else
                task.wait(1)
            end
        end

        if content then
            while not (TDS and TDS.Loadout) do 
                task.wait(0.5) 
            end

            local func = loadstring(content)

            if func then
                pcall(func)

                AltairNotify({Title = "ADS", Desc = "Running...", Time = 3})
            end
        end

        repeat task.wait(2) until not Globals.Easy or (GameState == "GAME" and not game:IsLoaded())

        EasyModeRunning = false
    end)
end

local function AutoSetDJSong(tower)
    task.spawn(function()
        local replicator = tower:WaitForChild("TowerReplicator", 10)
        if not replicator then return end
        if replicator:GetAttribute("Name") ~= "DJ Booth" then return end
        if replicator:GetAttribute("OwnerId") ~= LocalPlayer.UserId then return end
        
        local songIdNum = tonumber(Globals.DJCustomSongID)
        if not songIdNum then return end
        
        pcall(function()
            RemoteFunc:InvokeServer(
                "Troops",
                "Execute",
                {
                    Data = { songIdNum },
                    Name = "Music",
                    Tower = tower
                }
            )
        end)
    end)
end

task.spawn(function()
    local Towers = workspace:WaitForChild("Towers", 10)
    if not Towers then return end
    Towers.ChildAdded:Connect(AutoSetDJSong)
    for _, tower in ipairs(Towers:GetChildren()) do
        AutoSetDJSong(tower)
    end
end)

local function InvalidateSnapCache()
    TowerSnapper.LastInput = nil
    TowerSnapper.LastSnapped = nil
    TowerSnapper.LastHit = nil
    TowerSnapper.LastValid = false
end
task.spawn(function()
    local TowersFolder = workspace:WaitForChild("Towers", 30)
    if TowersFolder then
        TowersFolder.ChildAdded:Connect(InvalidateSnapCache)
        TowersFolder.ChildRemoved:Connect(InvalidateSnapCache)
    end
end)

local function GetTwoCircleTangents(PosA, RadiusA, PosB, RadiusB, RadiusNew)
    local CenterDist = (Vector3.new(PosB.X, 0, PosB.Z) - Vector3.new(PosA.X, 0, PosA.Z)).Magnitude
    local DistA = RadiusA + RadiusNew + TowerSnapper.SpacingOffset
    local DistB = RadiusB + RadiusNew + TowerSnapper.SpacingOffset
    if CenterDist > (DistA + DistB) or CenterDist < math.abs(DistA - DistB) or CenterDist == 0 then
        return nil
    end
    local SideA = (DistA^2 - DistB^2 + CenterDist^2) / (2 * CenterDist)
    local HeightSq = DistA^2 - SideA^2
    if HeightSq < 0 then return nil end
    local Height = math.sqrt(HeightSq)
    local DirX = (PosB.X - PosA.X) / CenterDist
    local DirZ = (PosB.Z - PosA.Z) / CenterDist
    local MidX = PosA.X + (DirX * SideA)
    local MidZ = PosA.Z + (DirZ * SideA)
    local NormX = -DirZ
    local NormZ = DirX
    local Pocket1 = Vector3.new(MidX + (NormX * Height), PosA.Y, MidZ + (NormZ * Height))
    local Pocket2 = Vector3.new(MidX - (NormX * Height), PosA.Y, MidZ - (NormZ * Height))
    return Pocket1, Pocket2
end

local function FindHoneycombCandidates(TowerName, TargetPos)
    local TowersFolder = workspace:FindFirstChild("Towers")
    if not TowersFolder then return {} end
    local Asset = require(ReplicatedStorage.Shared.Modules.Asset)
    local SharedConstants = require(ReplicatedStorage.Shared.Modules.SharedGameConstants)
    local TowerAsset = Asset("Troops", TowerName)
    local DefaultBoundary = SharedConstants.DEFAULT_BOUNDARY_SIZE or 1.5
    local NewRadius = (TowerAsset and TowerAsset.Properties and TowerAsset.Properties.BoundarySize) or DefaultBoundary
    local NearbyTowers = {}

    for _, TowerInstance in ipairs(TowersFolder:GetChildren()) do
        local Replicator = TowerInstance:FindFirstChild("TowerReplicator")
        if Replicator then
            local OtherName = Replicator:GetAttribute("Name") or TowerInstance.Name
            local OtherAsset = Asset("Troops", OtherName)
            local OtherRadius = (OtherAsset and OtherAsset.Properties and OtherAsset.Properties.BoundarySize) or DefaultBoundary
            local TowerPos = TowerInstance:GetPivot().Position
            local Dist = (Vector3.new(TowerPos.X, 0, TowerPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
            if Dist <= (OtherRadius + NewRadius + 12) then
                table.insert(NearbyTowers, {
                    Position = TowerPos,
                    Radius = OtherRadius,
                    Distance = Dist
                })
            end
        end
    end

    if #NearbyTowers == 0 then return {} end
    table.sort(NearbyTowers, function(A, B) return A.Distance < B.Distance end)

    local Candidates = {}

    if #NearbyTowers >= 2 then
        for FirstIdx = 1, math.min(#NearbyTowers - 1, 3) do
            for SecondIdx = FirstIdx + 1, math.min(#NearbyTowers, 4) do
                local TowerA = NearbyTowers[FirstIdx]
                local TowerB = NearbyTowers[SecondIdx]
                local P1, P2 = GetTwoCircleTangents(TowerA.Position, TowerA.Radius, TowerB.Position, TowerB.Radius, NewRadius)
                if P1 then table.insert(Candidates, P1) end
                if P2 then table.insert(Candidates, P2) end
            end
        end
    end

    for Index = 1, math.min(#NearbyTowers, 3) do
        local Tower = NearbyTowers[Index]
        local Dir = (Vector3.new(TargetPos.X, 0, TargetPos.Z) - Vector3.new(Tower.Position.X, 0, Tower.Position.Z))
        local TangentDist = Tower.Radius + NewRadius + TowerSnapper.SpacingOffset

        if Dir.Magnitude > 0.01 then
            table.insert(Candidates, Tower.Position + (Dir.Unit * TangentDist))
        end

        for AngleIdx = 0, 15 do
            local Angle = (math.pi * 2 / 16) * AngleIdx
            table.insert(Candidates, Tower.Position + Vector3.new(math.cos(Angle) * TangentDist, 0, math.sin(Angle) * TangentDist))
        end
    end

    return Candidates
end

local function FindNearestValidPlacement(CheckCollisionsOriginal, TowerName, TargetPos, Team, MaxRadius)
    local CurrentTowerCount = #workspace.Towers:GetChildren()
    if CurrentTowerCount ~= TowerSnapper.TowerCount then
        TowerSnapper.TowerCount = CurrentTowerCount
        InvalidateSnapCache()
    end

    local IsValidDirect, DirectHit = CheckCollisionsOriginal(TowerName, TargetPos, Team)
    if IsValidDirect then
        TowerSnapper.LastInput = TargetPos
        TowerSnapper.LastSnapped = TargetPos
        TowerSnapper.LastHit = DirectHit
        TowerSnapper.LastValid = true
        return TargetPos, DirectHit, false
    end

    if TowerSnapper.LastInput and (TargetPos - TowerSnapper.LastInput).Magnitude < 0.02 then
        if TowerSnapper.LastValid and TowerSnapper.LastSnapped then
            return TowerSnapper.LastSnapped, TowerSnapper.LastHit, true
        end
    end

    local BestPos = nil
    local BestDist = math.huge
    local BestHit = nil

    local HoneycombCandidates = FindHoneycombCandidates(TowerName, TargetPos)
    for _, CandPos in ipairs(HoneycombCandidates) do
        local IsCandValid, CandHit = CheckCollisionsOriginal(TowerName, CandPos, Team)
        if IsCandValid and CandHit then
            local ActualPos = (typeof(CandHit) == "RaycastResult") and CandHit.Position or CandPos
            local CandDist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
            if CandDist < BestDist then
                BestDist = CandDist
                BestPos = ActualPos
                BestHit = CandHit
            end
        end
    end

    MaxRadius = MaxRadius or TowerSnapper.MaxRadius
    local CoarseStep = TowerSnapper.CoarseStep
    local BestCoarseDist = math.huge
    local BestAngle = 0
    local BestRadius = 0

    for Radius = CoarseStep, MaxRadius, CoarseStep do
        if Radius >= BestDist then
            break
        end

        local Count = math.max(12, math.floor(2 * math.pi * Radius / CoarseStep))
        local AngleStep = (2 * math.pi) / Count
        local FoundInRing = false

        for Index = 0, Count - 1 do
            local Theta = Index * AngleStep
            local TestPos = TargetPos + Vector3.new(math.cos(Theta) * Radius, 0, math.sin(Theta) * Radius)
            local Valid, Res = CheckCollisionsOriginal(TowerName, TestPos, Team)
            if Valid and Res then
                local ActualPos = (typeof(Res) == "RaycastResult") and Res.Position or TestPos
                local Dist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
                if Dist < BestCoarseDist then
                    BestCoarseDist = Dist
                    BestAngle = Theta
                    BestRadius = Radius
                    FoundInRing = true
                end
            end
        end

        if FoundInRing and BestCoarseDist <= Radius + (CoarseStep * 0.5) then
            break
        end
    end

    if BestCoarseDist < BestDist then
        local FineBestPos = nil
        local FineBestDist = math.huge
        local FineBestRes = nil
        local RadiusMin = math.max(0.04, BestRadius - CoarseStep)
        local RadiusMax = BestRadius + (CoarseStep * 0.5)
        local RadiusStep = TowerSnapper.FineStep
        local AngleSpan = math.atan2(CoarseStep, BestRadius) * 1.6

        for Radius = RadiusMin, RadiusMax, RadiusStep do
            local AngleSteps = math.max(6, math.floor(Radius * AngleSpan / RadiusStep))
            for Index = -AngleSteps, AngleSteps do
                local Theta = BestAngle + (Index * (AngleSpan / AngleSteps))
                local TestPos = TargetPos + Vector3.new(math.cos(Theta) * Radius, 0, math.sin(Theta) * Radius)
                local Valid, Res = CheckCollisionsOriginal(TowerName, TestPos, Team)
                if Valid and Res then
                    local ActualPos = (typeof(Res) == "RaycastResult") and Res.Position or TestPos
                    local Dist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
                    if Dist < FineBestDist then
                        FineBestDist = Dist
                        FineBestPos = ActualPos
                        FineBestRes = Res
                    end
                end
            end
            if FineBestPos and FineBestDist <= Radius + 0.04 then
                break
            end
        end

        if FineBestPos and FineBestDist < BestDist then
            BestDist = FineBestDist
            BestPos = FineBestPos
            BestHit = FineBestRes
        end
    end

    local FinalPos = BestPos or TargetPos
    local FinalRes = BestHit or DirectHit
    local IsSnapped = (BestPos ~= nil)

    TowerSnapper.LastInput = TargetPos
    TowerSnapper.LastSnapped = FinalPos
    TowerSnapper.LastHit = FinalRes
    TowerSnapper.LastValid = IsSnapped

    return FinalPos, FinalRes, IsSnapped
end

local function HookPlacementSystem()
    local Success, Err = pcall(function()
        local NewPlacementController = require(ReplicatedStorage.Client.Controllers.Game.NewPlacementController)
        local SharedGameFunctions = require(ReplicatedStorage.Shared.Modules.SharedGameFunctions)
        local Scheduler = require(ReplicatedStorage.Shared.Modules.Scheduler)
        local OrigCheckTowerCollisions = SharedGameFunctions.CheckTowerCollisions
        local ProxyShared = setmetatable({}, {
            __index = function(_, Key)
                if Key == "CheckTowerCollisions" then
                    return function(TowerName, Pos, Team, ...)
                        if not TowerSnapper.Enabled then
                            return OrigCheckTowerCollisions(TowerName, Pos, Team, ...)
                        end
                        local SnappedPos, HitRes, IsSnapped = FindNearestValidPlacement(
                            OrigCheckTowerCollisions,
                            TowerName,
                            Pos,
                            Team
                        )
                        if IsSnapped and HitRes then
                            return true, HitRes
                        end
                        return OrigCheckTowerCollisions(TowerName, Pos, Team, ...)
                    end
                end
                return SharedGameFunctions[Key]
            end,
            __newindex = function(_, Key, Val)
                SharedGameFunctions[Key] = Val
            end
        })
        if getupvalues and setupvalue then
            local Upvals = getupvalues(NewPlacementController.Start)
            for Idx, Val in pairs(Upvals) do
                if Val == SharedGameFunctions then
                    setupvalue(NewPlacementController.Start, Idx, ProxyShared)
                    break
                end
            end
        end
        if NewPlacementController.Place and NewPlacementController.Place.Connect then
            NewPlacementController.Place:Connect(function()
                InvalidateSnapCache()
            end)
        end
        local OrigAdd = Scheduler.add
        Scheduler.add = function(Name, Signal, Callback)
            if Name == "TowerPlacement" and type(Callback) == "function" then
                local WrappedCallback = function(Dt)
                    if not TowerSnapper.Enabled then
                        return Callback(Dt)
                    end
                    local Upvals = getupvalues(Callback)
                    local Mouse = Upvals[1]
                    local RaycastParams = Upvals[2]
                    local SharedGame = Upvals[3]
                    local TowerData = Upvals[4]
                    local Team = Upvals[5]
                    local UpgradesStore = Upvals[7]
                    local Model = Upvals[8]
                    local SpringPos = Upvals[11]
                    local RotLerp = Upvals[12]
                    local TargetRot = Upvals[13]
                    local AnimController = Upvals[14]
                    local TowerClass = Upvals[15]
                    local EnumModule = Upvals[16]
                    local SpringNormal = Upvals[17]
                    local QuaternionModule = Upvals[18]
                    local Ray = workspace:Raycast(Mouse.UnitRay.Origin, Mouse.UnitRay.Direction * 1000, RaycastParams)
                    if Ray then
                        local IsValid, HitRes = SharedGame.CheckTowerCollisions(TowerData.Name, Ray.Position, Team)
                        if Upvals[6] ~= IsValid then
                            setupvalue(Callback, 6, IsValid)
                            UpgradesStore.updateValid(Model, IsValid)
                        end
                        local FinalTargetPos = Ray.Position
                        local FinalTargetNormal = Ray.Normal
                        if IsValid and HitRes then
                            local HitPos = (typeof(HitRes) == "RaycastResult") and HitRes.Position or HitRes
                            setupvalue(Callback, 9, HitPos)
                            FinalTargetPos = HitPos
                            if typeof(HitRes) == "RaycastResult" and HitRes.Normal then
                                FinalTargetNormal = HitRes.Normal
                            end
                        end
                        if Upvals[10] then
                            setupvalue(Callback, 10, false)
                            SpringPos.init(FinalTargetPos, Vector3.new(0, 0, 0))
                        else
                            SpringPos.t = FinalTargetPos
                        end
                        local DtAlpha = math.min(Dt * 10, 1)
                        RotLerp = math.lerp(RotLerp, TargetRot, DtAlpha)
                        setupvalue(Callback, 12, RotLerp)
                        local ModelCF = CFrame.new(SpringPos.p) * CFrame.Angles(0, math.rad(RotLerp), 0)
                        if AnimController and TowerClass ~= EnumModule.TowerType.Flying and SpringNormal and QuaternionModule then
                            SpringNormal.t = ModelCF.Position
                            local Tilt = QuaternionModule(FinalTargetNormal, FinalTargetNormal + (-0.01 * SpringNormal.v)) + SpringNormal.p
                            ModelCF = ModelCF * (Tilt - Tilt.Position)
                        end
                        Model:PivotTo(CFrame.new(ModelCF.X, FinalTargetPos.Y, ModelCF.Z) * CFrame.Angles(ModelCF:toEulerAnglesXYZ()))
                    end
                end
                return OrigAdd(Name, Signal, WrappedCallback)
            end
            return OrigAdd(Name, Signal, Callback)
        end
    end)
end

local function GetDJRangeBuffPercent(UpgradeLevel, TrackName)
    TrackName = TrackName or "Purple"
    if TrackName == "Purple" then
        local PurpleTable = { [0] = 12.5, [1] = 12.5, [2] = 15, [3] = 17.5, [4] = 22.5, [5] = 25 }
        return PurpleTable[UpgradeLevel] or 12.5
    elseif TrackName == "Green" or TrackName == "Red" then
        if UpgradeLevel >= 5 then
            return 10
        end
    end
    return 0
end

local function ClearBuffVisuals()
    for _, VisualRecord in pairs(BuffOverlay.AuraVisuals) do
        if VisualRecord.OutlinePart and VisualRecord.OutlinePart.Parent then
            VisualRecord.OutlinePart:Destroy()
        end
    end
    table.clear(BuffOverlay.AuraVisuals)

    if BuffOverlay.BasePreviewRange then
        pcall(function()
            local UpgradesStore = require(ReplicatedStorage.Client.Interfaces.Stores.Game.UpgradesStore)
            UpgradesStore.updateZone({ range = BuffOverlay.BasePreviewRange })
        end)
        BuffOverlay.BasePreviewRange = nil
        BuffOverlay.CurrentExpandedRange = nil
    end
end

local function UpdateBuffOverlay(CursorPosition, DeltaTime)
    if not BuffOverlay.Enabled or not CursorPosition then
        ClearBuffVisuals()
        return
    end

    local TowersFolder = workspace:FindFirstChild("Towers")
    if not TowersFolder then
        ClearBuffVisuals()
        return
    end

    BuffOverlay.PulseClock = BuffOverlay.PulseClock + (DeltaTime or 0.016)
    local PulseAlpha = (math.sin(BuffOverlay.PulseClock * 4) + 1) * 0.5

    local FoundSupports = {}
    local ActiveDJBuffPercent = 0

    for _, TowerInstance in ipairs(TowersFolder:GetChildren()) do
        local Replicator = TowerInstance:FindFirstChild("TowerReplicator")
        if Replicator then
            local TowerName = Replicator:GetAttribute("Name")
            local Definition = BuffOverlay.SupportDefinitions[TowerName]
            if Definition then
                local UpgradeLevel = Replicator:GetAttribute("Upgrade") or 0
                
                local BaseRange = Replicator:GetAttribute("Range")
                if not BaseRange or BaseRange <= 0 then
                    BaseRange = Definition.FallbackRanges[UpgradeLevel] or Definition.FallbackRanges[0] or 12
                end

                local RangeBuff = Replicator:GetAttribute("RangeBuff") or 0
                local ActualRadius = BaseRange * (1 + (RangeBuff / 100))
                local TowerPosition = TowerInstance:GetPivot().Position

                table.insert(FoundSupports, {
                    Name = TowerName,
                    Tag = Definition.Tag,
                    Definition = Definition,
                    Instance = TowerInstance,
                    Position = TowerPosition,
                    Radius = ActualRadius,
                    Replicator = Replicator,
                    Upgrade = UpgradeLevel
                })
            end
        end
    end

    if #FoundSupports == 0 then
        ClearBuffVisuals()
        return
    end

    for _, SupportData in ipairs(FoundSupports) do
        local FlatDistance = (Vector3.new(SupportData.Position.X, 0, SupportData.Position.Z) - Vector3.new(CursorPosition.X, 0, CursorPosition.Z)).Magnitude
        local InRange = (FlatDistance <= SupportData.Radius)

        if InRange and SupportData.Tag == "DJ" then
            local TrackName = SupportData.Replicator:GetAttribute("Track") or "Purple"
            local BuffPercent = GetDJRangeBuffPercent(SupportData.Upgrade, TrackName)
            if BuffPercent > ActiveDJBuffPercent then
                ActiveDJBuffPercent = BuffPercent
            end
        end

        local VisualRecord = BuffOverlay.AuraVisuals[SupportData.Instance]
        if not VisualRecord then
            local OutlinePart = Instance.new("Part")
            OutlinePart.Name = "AuraOutline_" .. SupportData.Tag
            OutlinePart.Anchored = true
            OutlinePart.CanCollide = false
            OutlinePart.CanTouch = false
            OutlinePart.CanQuery = false
            OutlinePart.Transparency = 1
            OutlinePart.Material = Enum.Material.Plastic
            OutlinePart.Parent = workspace

            local Adornment = Instance.new("CylinderHandleAdornment")
            Adornment.Name = "RingAdornment"
            Adornment.Adornee = OutlinePart
            Adornment.AlwaysOnTop = false
            Adornment.ZIndex = 1
            Adornment.CFrame = CFrame.Angles(math.rad(90), 0, 0)
            Adornment.Parent = OutlinePart

            VisualRecord = {
                OutlinePart = OutlinePart,
                Adornment = Adornment
            }
            BuffOverlay.AuraVisuals[SupportData.Instance] = VisualRecord
        end

        local FloorY = SupportData.Position.Y + 0.08
        VisualRecord.OutlinePart.Position = Vector3.new(SupportData.Position.X, FloorY, SupportData.Position.Z)
        VisualRecord.OutlinePart.Size = Vector3.new(0.2, 0.2, 0.2)

        local Radius = SupportData.Radius
        local Thickness = 0.18
        VisualRecord.Adornment.Radius = Radius
        VisualRecord.Adornment.InnerRadius = Radius - Thickness
        VisualRecord.Adornment.Height = 0.05
        VisualRecord.Adornment.Color3 = InRange and SupportData.Definition.GlowColor or SupportData.Definition.Color
        VisualRecord.Adornment.Transparency = InRange and (0.15 - (PulseAlpha * 0.1)) or 0.55
    end

    for SupportInstance, VisualRecord in pairs(BuffOverlay.AuraVisuals) do
        if not SupportInstance or not SupportInstance.Parent then
            if VisualRecord.OutlinePart then VisualRecord.OutlinePart:Destroy() end
            BuffOverlay.AuraVisuals[SupportInstance] = nil
        end
    end

    pcall(function()
        local UpgradesStore = require(ReplicatedStorage.Client.Interfaces.Stores.Game.UpgradesStore)
        local State = UpgradesStore.getState()
        local CurrentStoreRange = State.range or 0

        if CurrentStoreRange > 0 then
            if not BuffOverlay.BasePreviewRange or (CurrentStoreRange ~= BuffOverlay.CurrentExpandedRange and CurrentStoreRange ~= BuffOverlay.BasePreviewRange) then
                BuffOverlay.BasePreviewRange = CurrentStoreRange
            end

            local TargetRange = BuffOverlay.BasePreviewRange
            if ActiveDJBuffPercent > 0 and TargetRange then
                TargetRange = math.round(BuffOverlay.BasePreviewRange * (1 + (ActiveDJBuffPercent / 100)))
            end

            if TargetRange and TargetRange ~= CurrentStoreRange then
                BuffOverlay.CurrentExpandedRange = TargetRange
                UpgradesStore.updateZone({ range = TargetRange })
            end
        end
    end)
end

RunService.RenderStepped:Connect(function(DeltaTime)
    if GameState ~= "GAME" then
        ClearBuffVisuals()
        return
    end

    local NewPlacementController = require(ReplicatedStorage.Client.Controllers.Game.NewPlacementController)
    if not NewPlacementController.Active or not BuffOverlay.Enabled then
        ClearBuffVisuals()
        return
    end

    local TargetPosition = TowerSnapper and TowerSnapper.LastSnapped
    if not TargetPosition then
        local Mouse = LocalPlayer:GetMouse()
        TargetPosition = Mouse.Hit and Mouse.Hit.Position
    end
    
    if TargetPosition then
        UpdateBuffOverlay(TargetPosition, DeltaTime)
    else
        ClearBuffVisuals()
    end
end)

if GameState == "GAME" then
    HookPlacementSystem()
end

-- // ui - Rayfield Gen2 compatibility layer
pcall(CalcLength) -- seed dynamic path ranges before creating Rayfield sliders

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local function NormalizeRayfieldIcon(icon)
    if type(icon) == "number" then
        return icon
    end

    if type(icon) == "string" then
        local numeric = tonumber(icon)
        if numeric then
            return numeric
        end

        if icon:match("^rbxassetid://") or icon:match("^rbxthumb://") or icon:match("^rbxasset://") then
            return icon
        end
    end

    return nil
end

local RayWindow = Rayfield:CreateWindow({
    name = "CORE",
    subtitle = "your #1 hub",
    sidebarLayout = true,
    theme = "default",
    icon = 116265951007418,
    showName = "CORE",
})
ADS_BOOTSTRAP_ENV.ADS_RayfieldWindow = RayWindow

local function RoundingToIncrement(rounding)
    rounding = tonumber(rounding) or 0
    if rounding <= 0 then
        return 1
    end
    return 10 ^ (-rounding)
end

local function WrapTextHandle(handle)
    local wrapped = { _handle = handle }

    function wrapped:SetTitle(text)
        if self._handle and self._handle.SetTitle then
            self._handle:SetTitle(tostring(text or ""))
        end
    end

    function wrapped:SetValue(text)
        if self._handle and self._handle.Set then
            self._handle:Set(tostring(text or ""))
        end
    end

    return wrapped
end

local function WrapStatHandle(handle)
    local wrapped = { _handle = handle }

    function wrapped:Set(value)
        if self._handle and self._handle.Set then
            self._handle:Set(tonumber(value) or 0)
        end
    end

    function wrapped:SetValue(value)
        self:Set(value)
    end

    function wrapped:Get()
        if self._handle and self._handle.Get then
            return self._handle:Get()
        end
        return nil
    end

    return wrapped
end

local function WrapSliderHandle(handle, minimum, maximum)
    local wrapped = {
        _handle = handle,
        _min = tonumber(minimum) or 0,
        _max = tonumber(maximum) or 100,
    }

    local function TryApplyRange(self)
        if self._handle and self._handle.SetRange then
            self._handle:SetRange(self._min, self._max)
        end
    end

    function wrapped:SetMin(value)
        self._min = tonumber(value) or self._min
        TryApplyRange(self)
    end

    function wrapped:SetMax(value)
        self._max = tonumber(value) or self._max
        TryApplyRange(self)
    end

    function wrapped:SetValue(value)
        if self._handle and self._handle.Set then
            self._handle:Set(tonumber(value) or self._min, true)
        end
    end

    function wrapped:Set(value, skipCallback)
        if self._handle and self._handle.Set then
            self._handle:Set(value, skipCallback)
        end
    end

    return wrapped
end

local function WrapProgressHandle(handle, minimum, maximum)
    local wrapped = {
        _handle = handle,
        _min = tonumber(minimum) or 0,
        _max = tonumber(maximum) or 100,
    }

    local function ApplyRange(self)
        if self._handle and self._handle.SetRange then
            self._handle:SetRange(self._min, self._max)
        end
    end

    function wrapped:SetMin(value)
        self._min = tonumber(value) or self._min
        ApplyRange(self)
    end

    function wrapped:SetMax(value)
        self._max = tonumber(value) or self._max
        ApplyRange(self)
    end

    function wrapped:SetValue(value)
        if self._handle and self._handle.Set then
            self._handle:Set(tonumber(value) or self._min)
        end
    end

    function wrapped:Set(value)
        if self._handle and self._handle.Set then
            self._handle:Set(value)
        end
    end

    return wrapped
end

local function CreateTabAdapter(nativeTab)
    local Tab = { _tab = nativeTab }

    function Tab:Section(props)
        props = props or {}
        return self._tab:CreateSection({
            name = props.Title or props.Name or "Section",
            icon = NormalizeRayfieldIcon(props.Icon),
        })
    end

    function Tab:Toggle(props)
        props = props or {}
        local value = props.Value
        if value == nil then value = false end

        return self._tab:CreateToggle({
            name = props.Title or props.Name or "Toggle",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            value = value,
            forgetState = true,
            callback = props.Callback or function() end,
        })
    end

    function Tab:Slider(props)
        props = props or {}
        local minimum = tonumber(props.Min) or 0
        local maximum = tonumber(props.Max) or 100
        if maximum <= minimum then maximum = minimum + 1 end

        local value = tonumber(props.Value)
        if value == nil then value = minimum end
        value = math.clamp(value, minimum, maximum)

        local handle = self._tab:CreateSlider({
            name = props.Title or props.Name or "Slider",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            range = { minimum, maximum },
            increment = RoundingToIncrement(props.Rounding),
            value = value,
            suffix = props.Suffix,
            forgetState = true,
            callback = props.Callback or function() end,
        })

        return WrapSliderHandle(handle, minimum, maximum)
    end

    function Tab:Stat(props)
        props = props or {}
        local value = tonumber(props.Value)
        if value == nil then value = 0 end

        local handle = self._tab:CreateStat({
            name = props.Title or props.Name or "Statistic",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            value = value,
            numberEasing = props.NumberEasing ~= false,
            changeMode = props.ChangeMode or "absolute",
            changeBaseline = props.ChangeBaseline or "previous",
            prefix = props.Prefix or "",
            suffix = props.Suffix or "",
            compact = props.Compact ~= false,
            display = props.Display or "value",
        })

        return WrapStatHandle(handle)
    end

    function Tab:StatRow(items)
        items = items or {}
        local group = self._tab:CreateGroup({ direction = "row" })
        local stats = {}

        for _, props in ipairs(items) do
            props = props or {}
            local value = tonumber(props.Value)
            if value == nil then value = 0 end

            local handle = group:CreateStat({
                name = props.Title or props.Name or "Statistic",
                icon = NormalizeRayfieldIcon(props.Icon),
                value = value,
                numberEasing = props.NumberEasing ~= false,
                changeMode = props.ChangeMode or "absolute",
                changeBaseline = props.ChangeBaseline or "previous",
                prefix = props.Prefix or "",
                suffix = props.Suffix or "",
                compact = true,
                display = props.Display or "value",
            })

            stats[#stats + 1] = WrapStatHandle(handle)
        end

        return stats
    end

    function Tab:Progress(props)
        props = props or {}
        local minimum = tonumber(props.Min) or 0
        local maximum = tonumber(props.Max) or 100
        if maximum <= minimum then maximum = minimum + 1 end

        local value = tonumber(props.Value)
        if value == nil then value = minimum end
        value = math.clamp(value, minimum, maximum)

        local handle = self._tab:CreateProgress({
            name = props.Title or props.Name or "Progress",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            range = { minimum, maximum },
            value = value,
        })

        return WrapProgressHandle(handle, minimum, maximum)
    end

    function Tab:Dropdown(props)
        props = props or {}
        local options = table.clone(props.List or props.Options or {})
        local multi = props.Multi == true or props.MultiSelect == true
        local value = props.Value

        if multi and type(value) ~= "table" then
            value = value ~= nil and { tostring(value) } or {}
        elseif not multi and type(value) == "table" then
            value = value[1]
        end

        local handle = self._tab:CreateDropdown({
            name = props.Title or props.Name or "Dropdown",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            options = options,
            value = value,
            multiSelect = multi,
            placeholder = props.Placeholder or "None",
            forgetState = true,
            callback = props.Callback or function() end,
        })

        local wrapped = {
            _handle = handle,
            _options = options,
        }

        function wrapped:Clear()
            table.clear(self._options)
            if self._handle and self._handle.Refresh then
                self._handle:Refresh({})
            end
        end

        function wrapped:Add(option)
            option = tostring(option)
            table.insert(self._options, option)
            if self._handle and self._handle.Add then
                self._handle:Add(option)
            elseif self._handle and self._handle.Refresh then
                self._handle:Refresh(self._options)
            end
        end

        function wrapped:Set(value, skipCallback)
            if self._handle and self._handle.Set then
                self._handle:Set(value, skipCallback)
            end
        end

        return wrapped
    end

    function Tab:Textbox(props)
        props = props or {}
        local value = props.Value
        if value == nil then value = "" end

        return self._tab:CreateInput({
            name = props.Title or props.Name or "Input",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            value = tostring(value),
            placeholder = props.Placeholder,
            numeric = props.Numeric == true,
            clearOnFocus = props.ClearTextOnFocus == true,
            forgetState = true,
            callback = props.Callback or function() end,
        })
    end

    function Tab:Button(props)
        props = props or {}
        return self._tab:CreateButton({
            name = props.Title or props.Name or "Button",
            description = props.Desc or props.Description,
            icon = NormalizeRayfieldIcon(props.Icon),
            callback = props.Callback or function() end,
        })
    end

    function Tab:Label(props)
        props = props or {}
        local body = props.Desc or props.Description
        if body == "" then body = nil end

        local handle = self._tab:CreateText({
            name = props.Title or props.Name or "",
            text = body,
            icon = NormalizeRayfieldIcon(props.Icon),
        })

        return WrapTextHandle(handle)
    end

    function Tab:CreateLogger(props)
        props = props or {}
        local height = 120
        if typeof(props.Size) == "UDim2" then
            height = math.max(48, props.Size.Y.Offset)
        elseif tonumber(props.Height) then
            height = math.max(48, tonumber(props.Height))
        end

        local console = self._tab:CreateConsole({
            name = props.Title or props.Name or "Console",
            description = props.Desc or props.Description,
            height = height,
            follow = true,
            maxLines = props.MaxLines or 300,
        })

        local wrapped = { _handle = console }

        function wrapped:Log(message)
            if self._handle and self._handle.Append then
                self._handle:Append(tostring(message or ""))
            end
        end

        function wrapped:Clear()
            if self._handle and self._handle.Clear then
                self._handle:Clear()
            end
        end

        function wrapped:Set(text)
            if self._handle and self._handle.Set then
                self._handle:Set(tostring(text or ""))
            end
        end

        return wrapped
    end

    return Tab
end

Window = {}

function Window:Tab(props)
    props = props or {}
    local nativeTab = RayWindow:CreateTab({
        name = props.Title or props.Name or "Tab",
        icon = NormalizeRayfieldIcon(props.Icon),
    })
    return CreateTabAdapter(nativeTab)
end

function Window:Line()
    -- Rayfield Gen2's sidebar already visually separates tabs; no extra rail line is required.
end

local function PopupStyleForButton(button)
    if not button then return "neutral" end
    local color = button.Color
    if typeof(color) == "Color3" then
        if color.R > color.G * 1.2 and color.R > color.B * 1.2 then
            return "danger"
        end
    end
    return "primary"
end

function Window:Dialog(props)
    props = props or {}
    local options = {}

    if props.Button1 then
        table.insert(options, {
            text = props.Button1.Title or "Confirm",
            style = PopupStyleForButton(props.Button1),
            callback = props.Button1.Callback,
        })
    end

    if props.Button2 then
        table.insert(options, {
            text = props.Button2.Title or "Cancel",
            style = PopupStyleForButton(props.Button2),
            callback = props.Button2.Callback,
        })
    end

    return RayWindow:Popup({
        title = props.Title or "Confirm",
        content = props.Desc or props.Content or "",
        options = options,
        dismissable = true,
    })
end

-- Preserve the old LeftControl visibility key used by CORE.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.LeftControl then
        RayWindow:ToggleHide()
    end
end)

task.spawn(function()
    local retries = 0
    while retries < 10 do
        local success, inGroup = pcall(LocalPlayer.IsInGroup, LocalPlayer, 4914494)
        if success then
            if not inGroup then
                AltairNotify({
                    Title = "Warning",
                    Desc = "Please consider joining the Paradoxum Group. Otherwise, strategies may not work for you.",
                    Time = 25,
                    Type = "error"
                })
            end
            break
        end
        retries += 1
        task.wait(1)
    end
end)

local Automation = Window:Tab({Title = "Automation", Icon = "bot"}) do
    
    Automation:Section({Title = "Strategy Control"})

    Automation:Button({
        Title = "Start Embedded Strategy",
        Desc = "Starts the bundled strategy manually. Loading the script by itself will no longer queue a match.",
        Callback = function()
            local runner = getgenv().ADS_StartEmbeddedStrategy
            if type(runner) == "function" then
                runner()
            else
                AltairNotify({
                    Title = "Strategy",
                    Desc = "The embedded strategy is not ready yet.",
                    Time = 4,
                    Type = "error"
                })
            end
        end
    })

    Automation:Button({
        Title = "Stop Embedded Strategy",
        Desc = "Stops the currently running bundled strategy and clears its resume state.",
        Callback = function()
            local stopper = getgenv().ADS_StopEmbeddedStrategy
            if type(stopper) == "function" then
                stopper()
            end
        end
    })

    Automation:Section({Title = "Match Progression"})
    
    Automation:Toggle({
        Title = "Auto Rejoin",
        Desc = "Turn this ON if you are running a WIN strat",
        Value = Globals.AutoRejoin,
        Callback = function(v)
            SetSetting("AutoRejoin", v)
            if isfile("ADS_LastStrat.lua") then
                pcall(delfile, "ADS_LastStrat.lua")
            end
            if v and GameState == "GAME" then
                if #executed_actions > 0 then
                    local content = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", content)
                end
                if not BackToLobbyRunning then
                    StartBackToLobby()
                end
            end
        end
    })

    Automation:Toggle({
        Title = "Auto Restart",
        Desc = "Turn this ON if you are running a LOSE strat",
        Value = Globals.AutoRestart,
        Callback = function(v)
            SetSetting("AutoRestart", v)
            if isfile("ADS_LastStrat.lua") then
                pcall(delfile, "ADS_LastStrat.lua")
            end
            if v and GameState == "GAME" then
                if #executed_actions > 0 then
                    local content = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", content)
                end
                if not BackToLobbyRunning then
                    StartBackToLobby()
                end
            end
        end
    })

    if not IsMobile then
        Automation:Textbox({
            Title = "Private Server Code",
            Desc = "Paste your Private Server Code here to always join your private server",
            Placeholder = "Example: 16055572089259659857100802598629",
            Value = Globals.PrivateCode or "",
            ClearTextOnFocus = false,
            Callback = function(text)
                local validated = text

                if text ~= "" and not text:match("^%d+$") then
                    validated = ""
                end

                Globals.PrivateCode = validated
                
                SetSetting("PrivateCode", validated)
            end
        })
    end

    Automation:Toggle({
    Title = "Auto Ready Up",
    Desc = "Automatically readies up when starting a match",
    Value = Globals.AutoReady,
    Callback = function(v)
        Globals.AutoReady = v
        SetSetting("AutoReady", v)
        if v then StartAutoReady() end
    end
    }) 

    Automation:Toggle({
        Title = "Auto Skip Waves",
        Desc = "Skips all Waves",
        Value = Globals.AutoSkip,
        Callback = function(v)
            SetSetting("AutoSkip", v)
        end
    })

    Automation:Dropdown({
        Title = "Modifiers:",
        Desc = "Selected modifiers must already be unlocked via trials!",
        List = AllModifiers,
        Value = Globals.Modifiers,
        Multi = true,
        Callback = function(choice)
            SetSetting("Modifiers", choice)
        end
    })

    Automation:Section({Title = "Auto-Abilities"})
    
    Automation:Toggle({
        Title = "Auto Chain",
        Desc = "Chains Commander Ability",
        Value = Globals.AutoChain,
        Callback = function(v)
            SetSetting("AutoChain", v)
        end
    })

     Automation:Toggle({
        Title = "Auto Medic",
        Desc = "Chains Medic Ability",
        Value = Globals.AutoMedic,
        Callback = function(v)
            SetSetting("AutoMedic", v)
        end
    })

    Automation:Toggle({
        Title = "Support Caravan",
        Desc = "Uses Commander Support Caravan",
        Value = Globals.SupportCaravan,
        Callback = function(v)
            SetSetting("SupportCaravan", v)
        end
    })

    Automation:Toggle({
        Title = "Auto DJ Booth",
        Desc = "Uses DJ Booth Ability",
        Value = Globals.AutoDJ,
        Callback = function(v)
            SetSetting("AutoDJ", v)
        end
    })

    Automation:Textbox({
        Title = "DJ Custom Music",
        Desc = "Custom audio ID for your DJ Booth (Requires Gamepass)",
        Placeholder = "Audio ID",
        Value = Globals.DJCustomSongID or "",
        ClearTextOnFocus = false,
        Callback = function(value)
            SetSetting("DJCustomSongID", value or "")
            if not tonumber(value) then return end
            task.spawn(function()
                local TowersFolder = workspace:FindFirstChild("Towers")
                if not TowersFolder then return end
                for _, tower in ipairs(TowersFolder:GetChildren()) do
                    AutoSetDJSong(tower)
                end
            end)
        end
    })

    Automation:Toggle({
        Title = "Auto Necro",
        Desc = "Uses Necromancer Ability",
        Value = Globals.AutoNecro,
        Callback = function(v)
            SetSetting("AutoNecro", v)
        end
    })

    Automation:Section({Title = "Unit Spawners"})
    
    Automation:Toggle({
        Title = "Enable Path Distance Marker",
        Desc = "Red = Mercenary Base, Green = Military Baset",
        Value = Globals.PathVisuals,
        Callback = function(v)
            SetSetting("PathVisuals", v)
        end
    })

    Automation:Toggle({
        Title = "Auto Mercenary Base",
        Desc = "Uses Air-Drop Ability",
        Value = Globals.AutoMercenary,
        Callback = function(v)
            SetSetting("AutoMercenary", v)
        end
    })

    MercenarySlider = Automation:Slider({
        Title = "Path Distance",
        Min = 0,
        Max = MaxPathDistance,
        Rounding = 0,
        Value = Globals.MercenaryPath,
        Callback = function(val)
            SetSetting("MercenaryPath", val)
        end
    })

    Automation:Toggle({
        Title = "Auto Military Base",
        Desc = "Uses Airstrike Ability",
        Value = Globals.AutoMilitary,
        Callback = function(v)
            SetSetting("AutoMilitary", v)
        end
    })

    MilitarySlider = Automation:Slider({
        Title = "Path Distance",
        Min = 0,
        Max = MaxPathDistance,
        Rounding = 0,
        Value = Globals.MilitaryPath,
        Callback = function(val)
            SetSetting("MilitaryPath", val)
        end
    })

    task.spawn(function()
        while true do
            local success = CalcLength()
            if success then break end 
            task.wait(3)
        end
    end)

    Automation:Section({Title = "Inventory Management"})

    Automation:Toggle({
    Title = "Auto Open Crates",
    Desc = "Periodically attempts to open selected crates.",
    Value = Globals.AutoOpenCrates or false,
    Callback = function(v)
        Globals.AutoOpenCrates = v
        SetSetting("AutoOpenCrates", v)
        if v then StartAutoOpenCrates() end
    end
    })

    Automation:Dropdown({
    Title = "Target Crate:",
    List = CrateList,
    Value = Globals.SelectedCrate or "All",
    Callback = function(choice)
        Globals.SelectedCrate = choice
        SetSetting("SelectedCrate", choice)
    end
    })

    Automation:Section({Title = "Economy & Farming"})
    
    Automation:Toggle({
        Title = "Sell Farms",
        Desc = "Sells all your farms on the specified wave",
        Value = Globals.SellFarms,
        Callback = function(v)
            SetSetting("SellFarms", v)
        end
    })

    Automation:Textbox({
        Title = "Wave:",
        Desc = "Wave to sell farms",
        Placeholder = "40",
        Value = tostring(Globals.SellFarmsWave),
        ClearTextOnFocus = false,
        Callback = function(text)
            local number = tonumber(text)
            if number then
                SetSetting("SellFarmsWave", number)
            else
                AltairNotify({
                    Title = "ADS",
                    Desc = "Invalid number entered!",
                    Time = 3,
                    Type = "error"
                })
            end
        end
    })

    Automation:Section({Title = "Utilities"})
    
    Automation:Toggle({
        Title = "Auto Gatling",
        Desc = "Loads external Auto Gatling (credits to DeadSignalFound on GitHub)",
        Value = Globals.AutoGatling,
        Callback = function(v)
            SetSetting("AutoGatling", v)
        end
    })

    Automation:Toggle({
        Title = "Gatlify",
        Desc = "External Gatling utility with additional stability and features.",
        Value = Globals.Gatlify,
        Callback = function(v)
            SetSetting("Gatlify", v)
        end
    })

    Automation:Toggle({
        Title = "Auto Collect Pickups",
        Desc = "Collects Logbooks + Event currency",
        Value = Globals.AutoPickups,
        Callback = function(v)
            SetSetting("AutoPickups", v)
        end
    })

    Automation:Dropdown({
        Title = "Pickup Method",
        Desc = "",
        List = {"Pathfinding", "Instant"},
        Value = Globals.PickupMethod or "Pathfinding",
        Callback = function(choice)
            local selected = type(choice) == "table" and choice[1] or choice
            if not selected or selected == "" then
                selected = "Pathfinding"
            end
            SetSetting("PickupMethod", selected)
        end
    })

    Automation:Toggle({
        Title = "Claim Rewards",
        Desc = "Claims your playtime and uses spin tickets in Lobby",
        Value = Globals.ClaimRewards,
        Callback = function(v)
            SetSetting("ClaimRewards", v)
        end
    })
end

Window:Line()

local Interactive = Window:Tab({Title = "Interactive", Icon = "mouse-pointer-click"}) do
    
    Interactive:Section({Title = "Tower Controls"})
        
    Interactive:Toggle({
        Title = "Tower Snapper",
        Desc = "Automatically snaps and honeycomb-packs towers into the nearest valid position when hovering invalid spots",
        Value = Globals.Snapper ~= nil and Globals.Snapper or true,
        Callback = function(Value)
            TowerSnapper.Enabled = Value
            SetSetting("Snapper", Value)
            InvalidateSnapCache()
        end
    })

    Interactive:Toggle({
        Title = "Buff Indicator Overlay",
        Desc = "Shows active DJ/Commander/Medic range auras and in-range badges while placing",
        Value = Globals.BuffOverlay ~= nil and Globals.BuffOverlay or true,
        Callback = function(Value)
            BuffOverlay.Enabled = Value
            SetSetting("BuffOverlay", Value)
            if not Value then
                ClearBuffVisuals()
            end
        end
    })

    local TowerDropdown = Interactive:Dropdown({
        Title = "Tower:",
        List = CurrentEquippedTowers,
        Value = CurrentEquippedTowers[1],
        Callback = function(choice)
            SelectedTower = choice
        end
    })

    local function RefreshDropdown()
        local NewTowers = GetEquippedTowers()
        if table.concat(NewTowers, ",") ~= table.concat(CurrentEquippedTowers, ",") then
            TowerDropdown:Clear() 

            for _, TowerName in ipairs(NewTowers) do
                TowerDropdown:Add(TowerName)
            end

            CurrentEquippedTowers = NewTowers
        end
    end

    task.spawn(function()
        while task.wait(2) do
            RefreshDropdown()
        end
    end)

    Interactive:Toggle({
        Title = "Stack Tower",
        Desc = "Enables Stacking placement",
        Value = false,
        Callback = function(v)
            StackEnabled = v
            Globals.StackEnabled = v

            if StackEnabled then
                AltairNotify({
                    Title = "ADS",
                    Desc = "Make sure not to equip the tower, only select it and then place where you want to!",
                    Time = 5,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Open Inventory",
        Desc = "Place initial towers, then click this to swap loadout before readying up (bypasses 5-tower limit).\nNote: Does not work on low sUNC executors like Solara/Xeno",
        Callback = function()
            pcall(function()
                require(game:GetService("ReplicatedStorage").Client.Interfaces.LegacyInterface.Controllers.ViewController):setView("Inventory")
            end)
        end
    })

    Interactive:Button({
        Title = "Upgrade Selected",
        Desc = "",
        Callback = function()
            if SelectedTower then
                for _, v in pairs(workspace.Towers:GetChildren()) do
                    if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == SelectedTower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                        RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
                    end
                end
                AltairNotify({
                    Title = "ADS",
                    Desc = "Attempted to upgrade all the selected towers!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Sell Selected",
        Desc = "",
        Callback = function()
            if SelectedTower then
                for _, v in pairs(workspace.Towers:GetChildren()) do
                    if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == SelectedTower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                        RemoteFunc:InvokeServer("Troops", "Sell", {Troop = v})
                    end
                end
                AltairNotify({
                    Title = "ADS",
                    Desc = "Attempted to sell all the selected towers!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Upgrade All",
        Desc = "",
        Callback = function()
            for _, v in pairs(workspace.Towers:GetChildren()) do
                if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
                    RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
                end
            end
            AltairNotify({
                Title = "ADS",
                Desc = "Attempted to upgrade all the towers!",
                Time = 3,
                Type = "normal"
            })
        end
    })

    Interactive:Button({
        Title = "Sell All",
        Desc = "",
        Callback = function()
            Window:Dialog({
                Title = "Do you want to sell all the towers?",
                Button1 = {
                    Title = "Confirm",
                    Color = Color3.fromRGB(226, 39, 6),
                    Callback = function()
                        for _, v in pairs(workspace.Towers:GetChildren()) do
                            if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
                                RemoteFunc:InvokeServer("Troops", "Sell", {Troop = v})
                            end
                        end

                        AltairNotify({
                            Title = "ADS",
                            Desc = "Attempted to sell all the towers!",
                            Time = 3,
                            Type = "normal"
                        })
                    end
                },
                Button2 = {
                    Title = "Cancel",
                    Color = Color3.fromRGB(0, 188, 0)
                }
            })
        end
    })

    Interactive:Section({Title = "TimeScale Management"})
    
    Interactive:Toggle({
        Title = "Enable TimeScale",
        Desc = "Unlocks and sets game speed using tickets",
        Value = Globals.TimeScaleEnabled,
        Callback = function(v)
            SetSetting("TimeScaleEnabled", v)
            if v then
                StartTimeScale()
            end
        end
    })

    Interactive:Dropdown({
        Title = "TimeScale Speed",
        Desc = "Choose: 0.5, 1, 1.5, 2",
        List = {"0.5", "1", "1.5", "2"},
        Value = tostring(Globals.TimeScaleValue or 2),
        Callback = function(choice)
            local selected = type(choice) == "table" and choice[1] or choice
            local value = CoerceTimeScaleValue(selected, Globals.TimeScaleValue or 2)
            SetSetting("TimeScaleValue", value)
            if Globals.TimeScaleEnabled then
                ApplyTimeScaleOnce()
            end
        end
    })

    Interactive:Section({Title = "Player Statistics"})
    
    local PlayerStats = Interactive:StatRow({
        {Title = "Coins", Value = 0},
        {Title = "Gems", Value = 0},
        {Title = "Timescale Tickets", Value = 0},
        {Title = "Level", Value = 0},
        {Title = "Wins", Value = 0},
        {Title = "Losses", Value = 0},
        {Title = "Experience", Value = 0, Suffix = " XP"},
    })
    local CoinsStat = PlayerStats[1]
    local GemsStat = PlayerStats[2]
    local TicketsStat = PlayerStats[3]
    local LevelStat = PlayerStats[4]
    local WinsStat = PlayerStats[5]
    local LossesStat = PlayerStats[6]
    local ExperienceStat = PlayerStats[7]
    local ExpSlider = Interactive:Progress({
        Title = "EXP",
        Desc = "",
        Min = 0,
        Max = 100,
        Rounding = 0,
        Value = 0,
        Callback = function()
        end
    })

    local function ParseNumber(val)
        if type(val) == "number" then
            return val
        end
        if type(val) == "string" then
            local cleaned = string.gsub(val, ",", "")
            local n = tonumber(cleaned)
            if n then
                return n
            end
        end
        if type(val) == "table" and val.get then
            local ok, v = pcall(function()
                return val:get()
            end)
            if ok then
                return ParseNumber(v)
            end
        end
        return nil
    end

    local function ReadValue(obj)
        if not obj then
            return nil
        end
        local ok, v = pcall(function()
            return obj.Value
        end)
        if ok then
            return ParseNumber(v)
        end
        return nil
    end

    local function GetStatNumber(name)
        local obj = LocalPlayer:FindFirstChild(name)
        local v = ReadValue(obj)
        if v ~= nil then
            return v
        end
        local attr = LocalPlayer:GetAttribute(name)
        v = ParseNumber(attr)
        if v ~= nil then
            return v
        end
        return nil
    end

    local function PickExpMax()
        local ExpObj = LocalPlayer:FindFirstChild("Experience")
        local AttrMax = ExpObj and ParseNumber(ExpObj:GetAttribute("Max"))
        local AttrNeed = ExpObj and ParseNumber(ExpObj:GetAttribute("Required"))
        local AttrNext = ExpObj and ParseNumber(ExpObj:GetAttribute("Next"))
        return AttrMax
            or AttrNeed
            or AttrNext
            or GetStatNumber("ExperienceMax")
            or GetStatNumber("ExperienceNeeded")
            or GetStatNumber("ExperienceRequired")
            or GetStatNumber("ExperienceToNextLevel")
            or GetStatNumber("ExperienceToLevel")
            or GetStatNumber("NextLevelExp")
            or GetStatNumber("ExpToNextLevel")
            or GetStatNumber("ExpNeeded")
            or GetStatNumber("ExpRequired")
            or GetStatNumber("MaxExp")
            or GetStatNumber("MaxExperience")
            or 100
    end

    local GcExpCache = { t = nil, last = 0 }
    local function GetGcExp()
        if not getgc then
            return nil
        end
        local t = GcExpCache.t
        if t then
            local exp = ParseNumber(rawget(t, "exp") or rawget(t, "Exp") or rawget(t, "experience") or rawget(t, "Experience"))
            local MaxExp = ParseNumber(rawget(t, "maxExp") or rawget(t, "MaxExp") or rawget(t, "maxEXP") or rawget(t, "MaxEXP") or rawget(t, "maxExperience") or rawget(t, "MaxExperience"))
            local lvl = ParseNumber(rawget(t, "level") or rawget(t, "Level") or rawget(t, "lvl") or rawget(t, "Lvl"))
            if exp and MaxExp then
                return exp, MaxExp, lvl
            end
        end
        local now = os.clock()
        if now - GcExpCache.last < 3 then
            return nil
        end
        GcExpCache.last = now
        local plvl = GetStatNumber("Level")
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" then
                local exp = ParseNumber(rawget(obj, "exp") or rawget(obj, "Exp") or rawget(obj, "experience") or rawget(obj, "Experience"))
                local MaxExp = ParseNumber(rawget(obj, "maxExp") or rawget(obj, "MaxExp") or rawget(obj, "maxEXP") or rawget(obj, "MaxEXP") or rawget(obj, "maxExperience") or rawget(obj, "MaxExperience"))
                if exp and MaxExp then
                    local lvl = ParseNumber(rawget(obj, "level") or rawget(obj, "Level") or rawget(obj, "lvl") or rawget(obj, "Lvl"))
                    if not plvl or not lvl or lvl == plvl then
                        GcExpCache.t = obj
                        return exp, MaxExp, lvl
                    end
                end
            end
        end
        return nil
    end

    local function UpdateStats()
        local coins = GetStatNumber("Coins") or 0
        local gems = GetStatNumber("Gems") or 0
        local tickets = GetStatNumber("TimescaleTickets") or 0
        local lvl = GetStatNumber("Level") or 0
        local wins = GetStatNumber("Triumphs") or 0
        local loses = GetStatNumber("Loses") or 0
        local exp = GetStatNumber("Experience") or 0
        local MaxExp = PickExpMax()
        local GcExp, GcMax, GcLvl = GetGcExp()
        if GcExp and GcMax then
            exp = GcExp
            MaxExp = GcMax
            if GcLvl then
                lvl = GcLvl
            end
        end
        if MaxExp < 1 then
            MaxExp = 1
        end
        if exp > MaxExp then
            MaxExp = exp
        end
        if CoinsStat then CoinsStat:Set(coins) end
        if GemsStat then GemsStat:Set(gems) end
        if TicketsStat then TicketsStat:Set(tickets) end
        if LevelStat then LevelStat:Set(lvl) end
        if WinsStat then WinsStat:Set(wins) end
        if LossesStat then LossesStat:Set(loses) end
        if ExperienceStat then ExperienceStat:Set(exp) end
        if ExpSlider then
            ExpSlider:SetMin(0)
            ExpSlider:SetMax(MaxExp)
            ExpSlider:SetValue(exp)
        end
    end

    local StatsQueued = false
    local function QueueStatsUpdate()
        if StatsQueued then
            return
        end
        StatsQueued = true
        task.delay(0.2, function()
            StatsQueued = false
            UpdateStats()
        end)
    end

    local function HookStatObj(obj)
        if not obj then
            return
        end
        if obj.Changed then
            obj.Changed:Connect(QueueStatsUpdate)
        end
        obj:GetAttributeChangedSignal("Max"):Connect(QueueStatsUpdate)
        obj:GetAttributeChangedSignal("Required"):Connect(QueueStatsUpdate)
        obj:GetAttributeChangedSignal("Next"):Connect(QueueStatsUpdate)
    end

    local StatNames = {"Coins", "Gems", "TimescaleTickets", "Level", "Triumphs", "Loses", "Experience"}
    local ExpAttrNames = {
        "ExperienceMax",
        "ExperienceNeeded",
        "ExperienceRequired",
        "ExperienceToNextLevel",
        "ExperienceToLevel",
        "NextLevelExp",
        "ExpToNextLevel",
        "ExpNeeded",
        "ExpRequired",
        "MaxExp",
        "MaxExperience"
    }

    for _, name in ipairs(StatNames) do
        HookStatObj(LocalPlayer:FindFirstChild(name))
        LocalPlayer:GetAttributeChangedSignal(name):Connect(QueueStatsUpdate)
    end

    for _, name in ipairs(ExpAttrNames) do
        LocalPlayer:GetAttributeChangedSignal(name):Connect(QueueStatsUpdate)
    end

    LocalPlayer.ChildAdded:Connect(function(child)
        if table.find(StatNames, child.Name) then
            HookStatObj(child)
            QueueStatsUpdate()
        end
    end)

    LocalPlayer.ChildRemoved:Connect(function(child)
        if table.find(StatNames, child.Name) then
            QueueStatsUpdate()
        end
    end)

    QueueStatsUpdate()
end

Window:Line()

local Configuration = Window:Tab({Title = "Configuration", Icon = "sliders-horizontal"}) do
    Configuration:Section({Title = "Performance Optimization"})
    
    Configuration:Toggle({
        Title = "Enable Anti-Lag",
        Desc = "Boosts your FPS",
        Value = Globals.AntiLag,
        Callback = function(v)
            SetSetting("AntiLag", v)
        end
    })

    Configuration:Toggle({
        Title = "Disable 3d rendering",
        Desc = "Turns off 3d rendering",
        Value = Globals.Disable3DRendering,
        Callback = function(v)
            SetSetting("Disable3DRendering", v)
            Apply3dRendering()
        end
    })

    Configuration:Section({Title = "Custom Nametags"})
    
    local tagOptions = collectTagOptions()
    local tagValue = Globals.tagName or "None"
    if not table.find(tagOptions, tagValue) then
        tagValue = "None"
    end
    Configuration:Dropdown({
        Title = "Tag Changer",
        Desc = "",
        List = tagOptions,
        Value = tagValue,
        Callback = function(choice)
            local selected = choice
            if type(choice) == "table" then
                selected = choice[1]
            end
            if not selected or selected == "" then
                selected = "None"
            end
            SetSetting("tagName", selected)
            if selected == "None" then
                stopTagChanger()
            else
                startTagChanger()
            end
        end
    })

    Configuration:Section({Title = "Config Management"})
    
    Configuration:Button({
        Title = "Save Settings",
        Callback = function()
            AltairNotify({
                    Title = "ADS",
                    Desc = "Settings Saved!",
                    Time = 3,
                    Type = "normal"
                })
            SaveSettings()
        end
    })

    Configuration:Button({
        Title = "Load Settings",
        Callback = function()
            AltairNotify({
                    Title = "ADS",
                    Desc = "Settings Loaded!",
                    Time = 3,
                    Type = "normal"
                })
            LoadSettings()
        end
    })

    Configuration:Section({Title = "Experimental Features"})
    
    local StickerSpam = false

    Configuration:Toggle({
        Title = "Sticker Spam",
        Desc = "This will drop everyones FPS to like 5 (you will not be able to see this unless you have an alt)",
        Value = false,
        Callback = function(v)
            StickerSpam = v

            if StickerSpam then
                task.spawn(function()
                    while StickerSpam do
                        for i = 1, 9999 do
                            if not StickerSpam then break end

                            local args = {"Flex"}
                            game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Sticker"):WaitForChild("URE:Show"):FireServer(unpack(args))
                        end
                        task.wait()
                    end
                end)
            end
        end
    })

    Configuration:Button({
        Title = "Unlock Admin+ (Sandbox)",
        Desc = "Keep in mind that some features such as selecting maps, spawning in enemies and changing tower stats will not work!",
        Callback = function()
            if GameState == "GAME" then
                local args = {
                    game.Players.LocalPlayer.UserId,
                    true
                }

                game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Sandbox"):WaitForChild("RE:SetAdmin"):FireServer(unpack(args))

                AltairNotify({
                    Title = "ADS",
                    Desc = "Successfully unlocked Admin+ Mode!",
                    Time = 3,
                    Type = "normal"
                })
            else
                AltairNotify({
                    Title = "ADS",
                    Desc = "You must be in Sandbox mode for this to work!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })
end

Window:Line()


local Progression = Window:Tab({Title = "Progression", Icon = "settings"}) do
    Progression:Toggle({
        Title = "Auto Progression By Rya (Better version)",
        Desc = "Loads Ryas Auto Progress (Discord ID: 1088319992115757087)",
        Value = Globals.AutoProgressionLoader or false,
        Callback = function(v)
            SetSetting("AutoProgressionLoader", v)

            if v then
                loadstring(game:HttpGet("https://raw.githubusercontent.com/Ceepizz/rya/refs/heads/main/progloader.lua"))()

                repeat
                    task.wait()
                until game:GetService("CoreGui"):FindFirstChild("Progress")

                local aetherGui = game:GetService("CoreGui"):FindFirstChild("Aether")
                if aetherGui then
                    aetherGui:Destroy()
                end
            end
        end
    })

    Progression:Button({
        Title = "Copy Auto Progression Script (Paste this into auto exec folder)",
        Desc = "Copies Rya's Auto Progression loader",
        Callback = function()
            setclipboard([[loadstring(game:HttpGet("https://raw.githubusercontent.com/Ceepizz/rya/refs/heads/main/AutoProgress.lua"))()]])
        end
    })
    
    Progression:Section({Title = "Account Statistics"})

    -- Native Rayfield Gen2 account stats. These bypass the Altair compatibility
    -- adapter entirely and are created directly on a Rayfield row group.
    local AccountStatsRow = Progression._tab:CreateGroup({ direction = "row" })

    local function ReadProgressionStat(name, fallback)
        local obj = LocalPlayer:FindFirstChild(name)
        if obj then
            local ok, value = pcall(function() return obj.Value end)
            if ok and tonumber(value) then
                return tonumber(value)
            end
        end
        local attr = LocalPlayer:GetAttribute(name)
        return tonumber(attr) or fallback or 0
    end

    local ProgressionCoinsStat = AccountStatsRow:CreateStat({
        name = "Coins",
        value = ReadProgressionStat("Coins", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionGemsStat = AccountStatsRow:CreateStat({
        name = "Gems",
        value = ReadProgressionStat("Gems", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionTicketsStat = AccountStatsRow:CreateStat({
        name = "Timescale Tickets",
        value = ReadProgressionStat("TimescaleTickets", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionLevelStat = AccountStatsRow:CreateStat({
        name = "Level",
        value = ReadProgressionStat("Level", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionWinsStat = AccountStatsRow:CreateStat({
        name = "Wins",
        value = ReadProgressionStat("Triumphs", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionLossesStat = AccountStatsRow:CreateStat({
        name = "Losses",
        value = ReadProgressionStat("Loses", 0),
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionExperienceStat = AccountStatsRow:CreateStat({
        name = "Experience",
        value = ReadProgressionStat("Experience", 0),
        suffix = " XP",
        numberEasing = true,
        changeMode = "absolute",
        changeBaseline = "previous",
        compact = true,
    })

    local ProgressionStatHandles = {
        Coins = ProgressionCoinsStat,
        Gems = ProgressionGemsStat,
        TimescaleTickets = ProgressionTicketsStat,
        Level = ProgressionLevelStat,
        Triumphs = ProgressionWinsStat,
        Loses = ProgressionLossesStat,
        Experience = ProgressionExperienceStat,
    }

    local function RefreshProgressionStat(name)
        local handle = ProgressionStatHandles[name]
        if handle then
            handle:Set(ReadProgressionStat(name, 0))
        end
    end

    for statName in pairs(ProgressionStatHandles) do
        local name = statName
        local statObject = LocalPlayer:FindFirstChild(name)
        if statObject and statObject.Changed then
            statObject.Changed:Connect(function()
                RefreshProgressionStat(name)
            end)
        end
        LocalPlayer:GetAttributeChangedSignal(name):Connect(function()
            RefreshProgressionStat(name)
        end)
    end

    LocalPlayer.ChildAdded:Connect(function(child)
        if ProgressionStatHandles[child.Name] then
            if child.Changed then
                child.Changed:Connect(function()
                    RefreshProgressionStat(child.Name)
                end)
            end
            RefreshProgressionStat(child.Name)
        end
    end)

    Progression:Section({Title = "Private Server"})
    if not IsMobile then
        Progression:Textbox({
            Title = "Private Server Code",
            Desc = "Paste your Private Server Code here to always join your private server",
            Placeholder = "Example: 16055572089259659857100802598629",
            Value = Globals.PrivateCode or "",
            ClearTextOnFocus = false,
            Callback = function(text)
                local validated = text

                if text ~= "" and not text:match("^%d+$") then
                    validated = ""
                end

                Globals.PrivateCode = validated
                
                SetSetting("PrivateCode", validated)
            end
        })
    end

    Progression:Section({Title = "Webhook"})
    Progression:Toggle({
        Title = "Send Webhook",
        Desc = "",
        Value = Globals.SendProgressionWebhook,
        Callback = function(v)
            SetSetting("SendProgressionWebhook", v)
        end
    })

    Progression:Button({
        Title = "Test Webhook",
        Callback = function()
            if not Globals.ProgressionWebhookURL or Globals.ProgressionWebhookURL == "" then
                AltairNotify({Title = "Error", Desc = "Webhook URL is empty!", Time = 3, Type = "error"})
                return
            end

            local success, response = pcall(function()
                return SendRequest({
                    Url = Globals.ProgressionWebhookURL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = game:GetService("HttpService"):JSONEncode({["content"] = "Webhook Test"})
                })
            end)

            if success and response.StatusCode >= 200 and response.StatusCode < 300 then
                AltairNotify({
                    Title = "ADS",
                    Desc = "Webhook sent successfully and is working!",
                    Time = 3,
                    Type = "normal"
                })
            else
                AltairNotify({
                    Title = "Error",
                    Desc = "Invalid Webhook, Discord returned an error.",
                    Time = 5,
                    Type = "error"
                })
            end
        end
    })

    Progression:Textbox({
        Title = "Webhook URL:",
        Desc = "",
        Placeholder = "https://discord.com/api/webhooks/...",
        Value = Globals.ProgressionWebhookURL,
        ClearTextOnFocus = true,
        Callback = function(value)
            SetSetting("ProgressionWebhookURL", value) 

            if value ~= "" and value:find("https://discord.com/api/webhooks/") then
                AltairNotify({
                    Title = "ADS",
                    Desc = "Webhook is successfully set!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })
end

Window:Line()

Logger = Window:Tab({Title = "Logger", Icon = "terminal"}); do
    Logger = Logger:CreateLogger({
        Title = "STRATEGY LOGGER:",
        Size = UDim2.new(0, 330, 0, 300)
    })
end

Window:Line()

local RecorderInit = loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Sources/Recorder.lua"))()
RecorderInit({
    Window = Window,
    ReplicatedStorage = ReplicatedStorage,
    LocalPlayer = LocalPlayer,
    HttpService = HttpService,
    GameState = GameState,
    workspace = workspace
})

Window:Line()

local Settings = Window:Tab({Title = "Settings", Icon = "settings"}) do
    Settings:Section({Title = "Settings"})
    Settings:Button({
        Title = "Save Settings",
        Callback = function()
            AltairNotify({
                    Title = "ADS",
                    Desc = "Settings Saved!",
                    Time = 3,
                    Type = "normal"
                })
            SaveSettings()
        end
    })

    Settings:Button({
        Title = "Load Settings",
        Callback = function()
            AltairNotify({
                    Title = "ADS",
                    Desc = "Settings Loaded!",
                    Time = 3,
                    Type = "normal"
                })
            LoadSettings()
        end
    })

    Settings:Section({Title = "Privacy"})
    Settings:Toggle({
        Title = "Hide Username",
        Desc = "",
        Value = Globals.HideUsername,
        Callback = function(v)
            SetSetting("HideUsername", v)

            if v then
                UpdatePrivacyState()
            end
        end
    })

    Settings:Textbox({
        Title = "Streamer Name",
        Desc = "",
        Placeholder = "Spoof Name",
        Value = Globals.StreamerName or "",
        ClearTextOnFocus = false,
        Callback = function(value)
            SetSetting("StreamerName", value or "")
            UpdatePrivacyState()
        end
    })

    Settings:Toggle({
        Title = "Streamer Mode",
        Desc = "",
        Value = Globals.StreamerMode,
        Callback = function(v)
            SetSetting("StreamerMode", v)
            UpdatePrivacyState()
        end
    })

    Settings:Section({Title = "Tags"})
    local tagOptions = collectTagOptions()
    local tagValue = Globals.tagName or "None"
    if not table.find(tagOptions, tagValue) then
        tagValue = "None"
    end
    Settings:Dropdown({
        Title = "Tag Changer",
        Desc = "",
        List = tagOptions,
        Value = tagValue,
        Callback = function(choice)
            local selected = choice
            if type(choice) == "table" then
                selected = choice[1]
            end
            if not selected or selected == "" then
                selected = "None"
            end
            SetSetting("tagName", selected)
            if selected == "None" then
                stopTagChanger()
            else
                startTagChanger()
            end
        end
    })

    Settings:Section({Title = "Webhook"})
    Settings:Toggle({
        Title = "Send Webhook",
        Desc = "",
        Value = Globals.SendWebhook,
        Callback = function(v)
            SetSetting("SendWebhook", v)
        end
    })

    Settings:Button({
        Title = "Test Webhook",
        Callback = function()
            if not Globals.WebhookURL or Globals.WebhookURL == "" then
                AltairNotify({Title = "Error", Desc = "Webhook URL is empty!", Time = 3, Type = "error"})
                return
            end

            local success, response = pcall(function()
                return SendRequest({
                    Url = Globals.WebhookURL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = game:GetService("HttpService"):JSONEncode({["content"] = "Webhook Test"})
                })
            end)

            if success and response.StatusCode >= 200 and response.StatusCode < 300 then
                AltairNotify({
                    Title = "ADS",
                    Desc = "Webhook sent successfully and is working!",
                    Time = 3,
                    Type = "normal"
                })
            else
                AltairNotify({
                    Title = "Error",
                    Desc = "Invalid Webhook, Discord returned an error.",
                    Time = 5,
                    Type = "error"
                })
            end
        end
    })

    Settings:Textbox({
        Title = "Webhook URL:",
        Desc = "",
        Placeholder = "https://discord.com/api/webhooks/...",
        Value = Globals.WebhookURL,
        ClearTextOnFocus = true,
        Callback = function(value)
            SetSetting("WebhookURL", value) 

            if value ~= "" and value:find("https://discord.com/api/webhooks/") then
                AltairNotify({
                    Title = "ADS",
                    Desc = "Webhook is successfully set!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })
end

RunService.RenderStepped:Connect(function()
    if StackEnabled then
        if not StackSphere then
            StackSphere = Instance.new("Part")
            StackSphere.Shape = Enum.PartType.Ball
            StackSphere.Size = Vector3.new(1.5, 1.5, 1.5)
            StackSphere.Color = Color3.fromRGB(0, 255, 0)
            StackSphere.Transparency = 0.5
            StackSphere.Anchored = true
            StackSphere.CanCollide = false
            StackSphere.Material = Enum.Material.Neon
            StackSphere.Parent = workspace
            mouse.TargetFilter = StackSphere
        end
        local hit = mouse.Hit
        if hit then StackSphere.Position = hit.Position end
    elseif StackSphere then
        StackSphere:Destroy()
        StackSphere = nil
    end

    UpdatePathVisuals()
end)

mouse.Button1Down:Connect(function()
    if StackEnabled and StackSphere and SelectedTower then
        local pos = StackSphere.Position
        local newpos = Vector3.new(pos.X, pos.Y + 25, pos.Z)
        RemoteFunc:InvokeServer("Troops", "Place", {Rotation = CFrame.new(), Position = newpos}, SelectedTower)
    end
end)

-- // currency tracking
local StartCoins, CurrentTotalCoins, StartGems, CurrentTotalGems = 0, 0, 0, 0
if GameState == "GAME" then
    pcall(function()
        repeat task.wait(1) until LocalPlayer:FindFirstChild("Coins")
        StartCoins = LocalPlayer.Coins.Value
        CurrentTotalCoins = StartCoins
        StartGems = LocalPlayer.Gems.Value
        CurrentTotalGems = StartGems
    end)
end

-- // check if remote returned valid
local function CheckResOk(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end

    local success, IsModel = pcall(function()
        return data and data:IsA("Model")
    end)

    if success and IsModel then return true end
    if type(data) == "userdata" then return true end

    return false
end

-- // scrap ui for match data
local function GetAllRewards()
    local results = {
        Coins = 0, 
        Gems = 0, 
        XP = 0, 
        Wave = 0,
        Level = 0,
        Time = "00:00",
        Status = "UNKNOWN",
        Others = {} 
    }

    local UiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    local MainFrame = UiRoot and UiRoot:FindFirstChild("Frame")
    local GameOver = MainFrame and MainFrame:FindFirstChild("gameOver")
    local RewardsScreen = GameOver and GameOver:FindFirstChild("RewardsScreen")

    local GameStats = RewardsScreen and RewardsScreen:FindFirstChild("gameStats")
    local StatsList = GameStats and GameStats:FindFirstChild("stats")

    if StatsList then
        for _, frame in ipairs(StatsList:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            local refLabel = l2 and l2:FindFirstChild("refLabel")
            if l1 and refLabel and l1.Text:find("Time Completed:") then
                results.Time = refLabel.Text
                break
            end
        end
    end

    local TopBanner = RewardsScreen and RewardsScreen:FindFirstChild("RewardBanner")
    if TopBanner and TopBanner:FindFirstChild("textLabel") then
        local txt = TopBanner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    local LevelValue = LocalPlayer.Level
    if LevelValue then
        results.Level = LevelValue.Value or 0
    end

    local label = PlayerGui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
    local WaveNum = label.Text:match("^(%d+)")

    if WaveNum then
        results.Wave = tonumber(WaveNum) or 0
    end

    local SectionRewards = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    if SectionRewards then
        for _, item in ipairs(SectionRewards:GetChildren()) do
            if tonumber(item.Name) then 
                local IconId = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then IconId = img.Image:match("%d+") or "0" end

                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0

                        if text:find("Coins") then
                            results.Coins = amt
                        elseif text:find("Gems") then
                            results.Gems = amt
                        elseif text:find("XP") then
                            results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[IconId] or "Unknown Item (" .. IconId .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end

    return results
end

-- // rejoining
local function RejoinMatch()
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res

    if Globals.PrivateCode and Globals.PrivateCode ~= "" and not IsMobile then
        Logger:Log("Private server code detected. Returning to private lobby...")
        SmartTeleportToLobby()
        task.wait(9e9)
        return
    end

    repeat
        local StateFolder = ReplicatedStorage:FindFirstChild("State")
        local CurrentMode = StateFolder and StateFolder.Difficulty.Value
        if not CurrentMode or CurrentMode == "" then
            CurrentMode = TDS.SavedDifficulty
        end

        if CurrentMode and CurrentMode ~= "" then
            local ok, result = pcall(function()
                local payload
                local EventMode = StateFolder:FindFirstChild("Mode") and StateFolder.Mode.Value

                if CurrentMode == "PizzaParty" then
                    payload = {
                        mode = "halloween",
                        count = 1
                    }
                elseif tostring(EventMode or ""):lower() == "hardcore" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "hardcore",
                        count = 1
                    }
                elseif CurrentMode == "PollutedWasteland" then
                    payload = {
                        mode = "polluted",
                        count = 1
                    }
                elseif CurrentMode == "Badlands" then
                    payload = {
                        mode = "badlands",
                        count = 1
                    }
                elseif EventMode == "DuckEvent" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "ducky2025",
                        count = 1
                    }
                elseif CurrentMode == "Trial" then
                    payload = {
                        mode = "Trials",
                        count = 1
                    }
                else
                    payload = {
                        difficulty = CurrentMode,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
                res = result
            else
                task.wait(0.5) 
            end
        else
            task.wait(1)
        end
    until success

    return res
end

local function HandlePostMatch(skipRejoin)
    local UiRoot
    repeat
        task.wait(1)

        local root = PlayerGui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local RewardsScreen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        UiRoot = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    until UiRoot

    if not UiRoot then 
        if not skipRejoin then
            RejoinMatch() 
        end
        return
    end
    if not Globals.AutoRejoin and not Globals.AutoRestart then return end

    if not Globals.SendWebhook then
        if not skipRejoin then
            RejoinMatch()
        end
        return
    end

    task.wait(1)

    local match = GetAllRewards()

    CurrentTotalCoins += match.Coins
    CurrentTotalGems += match.Gems

    local BonusString = ""
    if #match.Others > 0 then
        for _, res in ipairs(match.Others) do
            BonusString = BonusString .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n"
        end
    else
        BonusString = "_No bonus rewards found._"
    end

    local PostData = {
        username = "TDS AutoStrat",
        embeds = {{
            title = (match.Status == "WIN" and "🏆 TRIUMPH" or "💀 DEFEAT"),
            color = (match.Status == "WIN" and 0x2ecc71 or 0xe74c3c),
            description =
                "### 📋 Match Overview\n" ..
                "> **Status:** `" .. match.Status .. "`\n" ..
                "> **Time:** `" .. match.Time .. "`\n" ..
                "> **Current Level:** `" .. match.Level .. "`\n" ..
                "> **Wave:** `" .. match.Wave .. "`\n",

            fields = {
                {
                    name = "✨ Rewards",
                    value = "```ansi\n" ..
                            "[2;33mCoins:[0m +" .. match.Coins .. "\n" ..
                            "[2;34mGems: [0m +" .. match.Gems .. "\n" ..
                            "[2;32mXP:   [0m +" .. match.XP .. "```",
                    inline = false
                },
                {
                    name = "🎁 Bonus Items",
                    value = BonusString,
                    inline = true
                },
                {
                    name = "📊 Session Totals",
                    value = "```py\n# Total Amount\nCoins: " .. CurrentTotalCoins .. "\nGems:  " .. CurrentTotalGems .. "```",
                    inline = true
                }
            },
            footer = { text = "Logged for " .. LocalPlayer.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        SendRequest({
            Url = Globals.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(PostData)
        })
    end)

    task.wait(1.5)

    if not skipRejoin then
        RejoinMatch()
    end

    task.wait(9e9)
end

local function MatchReadyUp()
    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators")
    local voteReplicator = stateReplicators:WaitForChild("VoteReplicator")
    local gameStateReplicator = stateReplicators:WaitForChild("GameStateReplicator")

    if gameStateReplicator:GetAttribute("GameStarted") == true then
        return
    end
    
    local voteTitle = voteReplicator:GetAttribute("Title")
    if voteTitle == "Ready?" and voteReplicator:GetAttribute("Enabled") == true then
        RunVoteSkip()
        return
    end

    local yieldSignal = Instance.new("BindableEvent")
    local voteConnection
    local gameStartedConnection

    voteConnection = voteReplicator.AttributeChanged:Connect(function(attributeName)
        if attributeName == "Enabled" and voteReplicator:GetAttribute("Enabled") == true then
            if voteReplicator:GetAttribute("Title") == "Ready?" then
                RunVoteSkip()
                yieldSignal:Fire()
            end
        elseif attributeName == "Title" and voteReplicator:GetAttribute("Title") ~= "Ready?" then
            yieldSignal:Fire()
        elseif attributeName == "VoteCount" or attributeName == "MaxVotes" then
            local currentVotes = voteReplicator:GetAttribute("VoteCount")
            local maxVotesRequired = voteReplicator:GetAttribute("MaxVotes")
            if currentVotes and maxVotesRequired and maxVotesRequired > 0 and currentVotes >= maxVotesRequired then
                yieldSignal:Fire()
            end
        end
    end)

    gameStartedConnection = gameStateReplicator:GetAttributeChangedSignal("GameStarted"):Connect(function()
        if gameStateReplicator:GetAttribute("GameStarted") == true then
            yieldSignal:Fire()
        end
    end)

    yieldSignal.Event:Wait()

    if voteConnection then
        voteConnection:Disconnect()
    end
    if gameStartedConnection then
        gameStartedConnection:Disconnect()
    end
    yieldSignal:Destroy()
end

local function CastMapVote(MapId, PosVec)
    local TargetMap = MapId or "Simplicity"
    local TargetPos = PosVec or Vector3.new(0,0,0)
    RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
    Logger:Log("Cast map vote: " .. TargetMap)
end

local function LobbyReadyUp()
    pcall(function()
        RemoteEvent:FireServer("LobbyVoting", "Ready")
        Logger:Log("Lobby ready up sent")
    end)
end

local function SelectMapOverride(MapId, ...)
    local args = {...}

    if args[#args] == "vip" then
        RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
    end

    task.wait(3)
    CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
    task.wait(1)
    LobbyReadyUp()
end

local function CastModifierVote(ModsTable)
    local BulkModifiers = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
    local ModRep = ReplicatedStorage:WaitForChild("StateReplicators"):FindFirstChild("ModifierReplicator")

    local Available = {}
    if ModRep then
        local raw = ModRep:GetAttribute("Available")
        if type(raw) == "string" then
            local clean = raw:match("{.+}")
            if clean then
                pcall(function()
                    Available = HttpService:JSONDecode(clean)
                end)
            end
        end
    end

    local SelectedMods = {}
    local missingMods = {}

    if ModsTable then
        for k, v in pairs(ModsTable) do
            local modName = type(k) == "string" and k or v
            
            if type(modName) == "string" then
                if Available[modName] == true then
                    SelectedMods[modName] = true
                else
                    table.insert(missingMods, modName)
                end
            end
        end
    end

    if #missingMods > 0 then
        AltairNotify({
            Title = "ADS",
            Desc = "Locked (Skipped) modifiers: " .. table.concat(missingMods, ", "),
            Time = 50,
            Type = "error"
        })
    end

    if next(SelectedMods) then
        pcall(function()
            BulkModifiers:InvokeServer(SelectedMods)
            Logger:Log("Successfully casted modifier votes.")
        end)
    end
end

local function IsMapAvailable(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    local hasVoted = false

    repeat
        local IntermissionFrame = PlayerGui:WaitForChild("ReactGameIntermission"):WaitForChild("Frame")
        local VetoValue = IntermissionFrame.buttons.veto.value
        local VetoText = VetoValue.Text
        
        if VetoText ~= "" then
            if not VetoText:find("Veto") then
                return false 
            end

            local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
            local current, total = tonumber(currentStr), tonumber(totalStr)

            if not hasVoted and total and total > 0 and current == 0 then
                RemoteEvent:FireServer("LobbyVoting", "Veto")
                hasVoted = true
            end
        end

        local found = false
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and t.Text == name then
                    found = true
                    break
                end
            end
        end

        task.wait(1)

        local TotalPlayer = #Players:GetChildren()
        local isFull = VetoText == "Veto ("..TotalPlayer.."/"..TotalPlayer..")"

    until found or isFull

    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    return false
end

-- // timescale logic
local function SetGameTimescale(TargetVal)
    if GameState ~= "GAME" then 
        return 
    end

    local SpeedList = {0, 0.5, 1, 1.5, 2}

    local TargetIdx
    for i, v in ipairs(SpeedList) do
        if v == TargetVal then
            TargetIdx = i
            break
        end
    end
    if not TargetIdx then return end

    local SpeedLabel = game.Players.LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Speed

    local CurrentVal = tonumber(SpeedLabel.Text:match("x([%d%.]+)"))
    if not CurrentVal then return end

    local CurrentIdx
    for i, v in ipairs(SpeedList) do
        if v == CurrentVal then
            CurrentIdx = i
            break
        end
    end
    if not CurrentIdx then return end

    local diff = TargetIdx - CurrentIdx
    if diff < 0 then
        diff = #SpeedList + diff
    end

    for _ = 1, diff do
        ReplicatedStorage.RemoteFunction:InvokeServer(
            "TicketsManager",
            "CycleTimeScale"
        )
        task.wait(0.5)
    end
end

local function UnlockSpeedTickets()
    if GameState ~= "GAME" then 
        return 
    end

    if LocalPlayer.TimescaleTickets.Value >= 1 then
        local TimescaleButton = LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale
        local LockIcon = TimescaleButton:FindFirstChild("Lock")
        if LockIcon and LockIcon.Visible then
            ReplicatedStorage.RemoteFunction:InvokeServer('TicketsManager', 'UnlockTimeScale')
            Logger:Log("Unlocked timescale tickets")
        end
    else
        Logger:Log("No timescale tickets left")
    end
end

ApplyTimeScaleOnce = function()
    if not Globals.TimeScaleEnabled or GameState ~= "GAME" then
        return
    end

    local frame = GetTimescaleFrame()
    if not frame or not frame.Visible then
        return
    end

    local desired = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)
    if not desired then
        return
    end

    local lock = frame:FindFirstChild("Lock")
    if lock and lock.Visible then
        if LocalPlayer.TimescaleTickets.Value < 1 then
            if not TimeScaleNoTicketsWarned then
                Logger:Log("No timescale tickets left")
                TimeScaleNoTicketsWarned = true
            end
            return
        end
        UnlockSpeedTickets()
        task.wait(0.4)
    else
        TimeScaleNoTicketsWarned = false
    end

    SetGameTimescale(desired)
end

StartTimeScale = function()
    if TimeScaleRunning or not Globals.TimeScaleEnabled then
        return
    end
    TimeScaleRunning = true

    task.spawn(function()
        while Globals.TimeScaleEnabled do
            ApplyTimeScaleOnce()
            task.wait(3)
        end
        TimeScaleNoTicketsWarned = false
        TimeScaleRunning = false
    end)
end

-- // ingame control
local function TriggerRestart()
    local UiRoot = PlayerGui:WaitForChild("ReactGameNewRewards")
    local FoundSection = false

    repeat
        task.wait(0.3)
        local f = UiRoot:FindFirstChild("Frame")
        local g = f and f:FindFirstChild("gameOver")
        local s = g and g:FindFirstChild("RewardsScreen")
        if s and s:FindFirstChild("RewardsSection") then
            FoundSection = true
        end
    until FoundSection

    task.wait(3)
    RunVoteSkip()
end

local function GetCurrentWave()
    local label

    repeat
        task.wait(0.5)
        label = PlayerGui:FindFirstChild("ReactGameTopGameDisplay", true) 
            and PlayerGui.ReactGameTopGameDisplay.Frame.wave.container:FindFirstChild("value")
    until label ~= nil

    local text = label.Text
    local WaveNum = text:match("(%d+)")

    return tonumber(WaveNum) or 0
end

local function DoPlaceTower(TName, TPos, ...)
    local args = {...}
    Logger:Log("Placing tower: " .. TName)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = TPos
            }, TName, unpack(args))
        end)

        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoUpgradeTower(TObj, PathId)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = TObj,
                Path = PathId
            })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoSellTower(TObj)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TObj })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoSetOption(TObj, OptName, OptVal, ReqWave)
    if ReqWave then
        repeat task.wait(0.3) until GetCurrentWave() >= ReqWave
    end

    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Option", "Set", {
                Troop = TObj,
                Name = OptName,
                Value = OptVal
            })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoActivateAbility(TObj, AbName, AbData, IsLooping)
    if type(AbData) == "boolean" then
        IsLooping = AbData
        AbData = nil
    end

    AbData = type(AbData) == "table" and AbData or nil

    local positions
    if AbData and type(AbData.towerPosition) == "table" then
        positions = AbData.towerPosition
    end

    local CloneIdx = AbData and AbData.towerToClone
    local TargetIdx = AbData and AbData.towerTarget

    local function attempt()
        while true do
            local ok, res = pcall(function()
                local data

                if AbData then
                    data = table.clone(AbData)

                    if positions and #positions > 0 then
                        data.towerPosition = positions[math.random(#positions)]
                    end

                    if type(CloneIdx) == "number" then
                        data.towerToClone = TDS.PlacedTowers[CloneIdx]
                    end

                    if type(TargetIdx) == "number" then
                        data.towerTarget = TDS.PlacedTowers[TargetIdx]
                    end
                end

                return RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    {
                        Troop = TObj,
                        Name = AbName,
                        Data = data
                    }
                )
            end)

            if ok and CheckResOk(res) then
                return true
            end

            task.wait(0.25)
        end
    end

    if IsLooping then
        local active = true
        task.spawn(function()
            while active do
                attempt()
                task.wait(1)
            end
        end)
        return function() active = false end
    end

    return attempt()
end

-- // public api
-- lobby
function TDS:Mode(difficulty, code)
    self.SavedDifficulty = difficulty
    local targetCode = ""

    if IsMobile then
        if (code and code ~= "") or (Globals.PrivateCode and Globals.PrivateCode ~= "") then
            AltairNotify({
                Title = "Warning",
                Desc = "Private server codes are not supported on mobile devices.",
                Time = 25,
                Type = "error"
            })
        end
    else
        if code and code ~= "" then
            targetCode = code
        elseif Globals.PrivateCode then
            targetCode = Globals.PrivateCode
        end
    end

    self.PrivateCode = tostring(targetCode)

    if GameState ~= "LOBBY" then 
        return false 
    end

    if targetCode ~= "" and not MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
        local ServerType = game:GetService('RobloxReplicatedStorage').GetServerType:InvokeServer()
        
        if ServerType ~= "VIPServer" then
            game:GetService("ExperienceService"):LaunchExperience({
                placeId = game.PlaceId, 
                linkCode = tostring(targetCode)
            })
            return true
        end
    end

    if difficulty == "Trial" then
        local success = pcall(function()
            RemoteFunc:InvokeServer(
                "Multiplayer",
                "v2:start",
                {
                    count = 1,
                    mode = "Trials"
                }
            )
        end)
        
        return success
    end

    local LobbyHud = PlayerGui:WaitForChild("ReactLobbyHud", 30)
    local frame = LobbyHud and LobbyHud:WaitForChild("Frame", 30)
    local MatchMaking = frame and frame:WaitForChild("matchmaking", 30)

    if MatchMaking then
        local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
        local success = false
        repeat
            local ok, result = pcall(function()
                local mode = TDS.MatchmakingMap[difficulty]
                local payload

                if difficulty == "Hardcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Easy",
                        count = 1
                    }
                elseif difficulty == "Voidcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Hard",
                        count = 1
                    }
                elseif mode then
                    payload = {
                        mode = mode,
                        count = 1
                    }
                    if difficulty:match("Ducky") then
                        payload.difficulty = difficulty:gsub("Ducky", "")
                    end
                else
                    payload = {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
            else
                task.wait(0.5) 
            end
        until success
    end

    return true
end

function TDS:Loadout(...)
    if GameState ~= "GAME" then
        return
    end

    while IsCurrentlyLoading do
        task.wait(0.2)
    end

    IsCurrentlyLoading = true
    IsEquippingLoadout = true
    self.IsEquippingLoadout = true

    local towers = {...}
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")

    local success = pcall(function()
        local CurrentlyEquipped = {}

        if StateReplicators then
            for _, folder in ipairs(StateReplicators:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                    local EquippedAttr = folder:GetAttribute("EquippedTowers")
                    if type(EquippedAttr) == "string" then
                        local CleanedJson = EquippedAttr:match("%[.*%]") 
                        local DecodeSuccess, decoded = pcall(function()
                            return HttpService:JSONDecode(CleanedJson)
                        end)

                        if DecodeSuccess and type(decoded) == "table" then
                            CurrentlyEquipped = decoded
                        end
                    end
                end
            end
        end

        for _, CurrentTower in ipairs(CurrentlyEquipped) do
            if CurrentTower ~= "None" then
                local UnequipDone = false
                repeat
                    local ok = pcall(function()
                        remote:FireServer("Inventory", "Unequip", "Tower", CurrentTower)
                        task.wait(0.3)
                    end)
                    if ok then UnequipDone = true else task.wait(0.2) end
                until UnequipDone
            end
        end

        task.wait(0.5)

        for _, TowerName in ipairs(towers) do
            if TowerName and TowerName ~= "" then
                local EquipSuccess = false
                repeat
                    local ok = pcall(function()
                        remote:FireServer("Inventory", "Equip", "Tower", TowerName)
                        Logger:Log("Equipped tower: " .. TowerName)
                        task.wait(0.3)
                    end)
                    if ok then EquipSuccess = true else task.wait(0.2) end
                until EquipSuccess
            end
        end

        task.wait(0.5)
    end)

    IsCurrentlyLoading = false
    IsEquippingLoadout = false
    self.IsEquippingLoadout = false
    self.LoadoutPending = false
    LastLoadTime = os.clock()

    return success
end

-- ingame
function TDS:VoteSkip(StartWave, EndWave)
    task.spawn(function()
        local CurrentWave = GetCurrentWave()
        
        self.LastVoteSkipTarget = self.LastVoteSkipTarget or 0
        
        if not StartWave then
            if self.LastVoteSkipTarget < CurrentWave then
                self.LastVoteSkipTarget = CurrentWave
            else
                self.LastVoteSkipTarget = self.LastVoteSkipTarget + 1
            end
            StartWave = self.LastVoteSkipTarget
            EndWave = StartWave
        else
            EndWave = EndWave or StartWave
            self.LastVoteSkipTarget = EndWave
        end

        for wave = StartWave, EndWave do
            while GetCurrentWave() < wave do
                task.wait(1)
            end

            local TargetNextWave = wave + 1
            
            while GetCurrentWave() < TargetNextWave do
                local VoteUi = PlayerGui:FindFirstChild("ReactOverridesVote")
                local VoteButton = VoteUi 
                    and VoteUi:FindFirstChild("Frame") 
                    and VoteUi.Frame:FindFirstChild("votes") 
                    and VoteUi.Frame.votes:FindFirstChild("vote", true)

                if VoteButton and VoteButton.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    pcall(function()
                        RemoteFunc:InvokeServer("Voting", "Skip")
                    end)
                end
                
                task.wait(0.5)
            end
            
            Logger:Log("Successfully skipped wave " .. wave)
        end
    end)
end

function TDS:GameInfo(name, list)
    if GameState ~= "GAME" then return false end

    local VoteGui = PlayerGui:WaitForChild("ReactGameIntermission", 30)
    if not (VoteGui and VoteGui.Enabled and VoteGui:WaitForChild("Frame", 5)) then return end

    local modifiers = (list and next(list)) and list or Globals.Modifiers

    CastModifierVote(modifiers)

    local stateReplicators = game:GetService("ReplicatedStorage"):WaitForChild("StateReplicators", 5)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) or (gameStateReplicator and gameStateReplicator:GetAttribute("IsPrivateServer") == true) then
        SelectMapOverride(name, "vip")
        Logger:Log("Selected map: " .. name)
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true 
    elseif IsMapAvailable(name) then
        SelectMapOverride(name)
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true
    else
        Logger:Log("Map '" .. name .. "' not available, rejoining...")
        RejoinMatch()
        repeat task.wait(9999) until false
    end
end

function TDS:UnlockTimeScale()
    UnlockSpeedTickets()
end

function TDS:TimeScale(val)
    SetGameTimescale(val)
end

function TDS:StartGame()
    LobbyReadyUp()
end

function TDS:Ready()
    if GameState ~= "GAME" then
        return false 
    end
    MatchReadyUp()
    return true
end

function TDS:GetWave()
    return GetCurrentWave()
end

function TDS:WaitForWave(targetWave)
    if GameState ~= "GAME" then return false end
    while self:GetWave() < targetWave do
        task.wait(0.5)
    end
    return true
end

function TDS:RestartGame()
    TriggerRestart()
end

function TDS:Place(TName, px, py, pz, ...)
    local args = {...}

    -- Ignore the legacy trailing stack sentinel and use ordinary placement.
    if args[#args] == "stack" or args[#args] == true then
        table.remove(args, #args)
    end

    if GameState ~= "GAME" then
        return false 
    end

    local existing = {}
    for _, child in ipairs(workspace.Towers:GetChildren()) do
        for _, SubChild in ipairs(child:GetChildren()) do
            if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                existing[child] = true
                break
            end
        end
    end

    DoPlaceTower(TName, Vector3.new(px, py, pz), unpack(args))

    local NewT
    repeat
        for _, child in ipairs(workspace.Towers:GetChildren()) do
            if not existing[child] then
                for _, SubChild in ipairs(child:GetChildren()) do
                    if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                        NewT = child
                        break
                    end
                end
            end
            if NewT then break end
        end
        task.wait(0.05)
    until NewT

    table.insert(self.PlacedTowers, NewT)
    return #self.PlacedTowers
end

function TDS:Upgrade(idx, PId)
    local t = self.PlacedTowers[idx]
    if t then
        DoUpgradeTower(t, PId or 1)
        Logger:Log("Upgrading tower index: " .. idx)
        UpgradeHistory[idx] = (UpgradeHistory[idx] or 0) + 1
    end
end

function TDS:SetTarget(idx, TargetType, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end

    local t = self.PlacedTowers[idx]
    if not t then return end

    pcall(function()
        RemoteFunc:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = TargetType
        })
        Logger:Log("Set target for tower index " .. idx .. " to " .. TargetType)
    end)
end

function TDS:Sell(idx, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end
    local t = self.PlacedTowers[idx]
    if t and DoSellTower(t) then
        return true
    end
    return false
end

function TDS:SellAll(ReqWave)
    task.spawn(function()
        if ReqWave then
            repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
        end

        local TowersCopy = {unpack(self.PlacedTowers)}
        for idx, t in ipairs(TowersCopy) do
            if DoSellTower(t) then
                for i, OrigT in ipairs(self.PlacedTowers) do
                    if OrigT == t then
                        table.remove(self.PlacedTowers, i)
                        break
                    end
                end
            end
        end

        return true
    end)
end

function TDS:Ability(idx, name, data, loop)
    local t = self.PlacedTowers[idx]
    if not t then return false end
    Logger:Log("Activating ability '" .. name .. "' for tower index: " .. idx)
    return DoActivateAbility(t, name, data, loop)
end

function TDS:AutoChain(...)
    local TowerIndices = {...}
    if #TowerIndices == 0 then return end

    local running = true

    task.spawn(function()
        local i = 1
        while running do
            local idx = TowerIndices[i]
            local tower = TDS.PlacedTowers[idx]

            if tower then
                DoActivateAbility(tower, "Call Of Arms")
            end

            local hotbar = PlayerGui.ReactUniversalHotbar.Frame
            local timescale = hotbar:FindFirstChild("timescale")

            if timescale then
                if timescale:FindFirstChild("Lock") then
                    task.wait(10.5)
                else
                    task.wait(5.5)
                end
            else
                task.wait(10.5)
            end

            i += 1
            if i > #TowerIndices then
                i = 1
            end
        end
    end)

    return function()
        running = false
    end
end

function TDS:SetOption(idx, name, val, ReqWave)
    local t = self.PlacedTowers[idx]
    if t then
        Logger:Log("Setting option '" .. name .. "' for tower index: " .. idx)
        return DoSetOption(t, name, val, ReqWave)
    end
    return false
end

function TDS:MedicSelect(idx, val)
    local t = self.PlacedTowers[idx]
    local target = self.PlacedTowers[val]
    if t and target then
        Logger:Log("Medic: " .. idx .. " -> " .. val)
        RemoteFunc:InvokeServer("Troops", "TowerServerEvent", "ToggleSelectedTower", t, target)
        return true
    end
    return false
end

local MedicChainAPI

function TDS:MedicChain(...)
    if not MedicChainAPI then
        local loaded = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/Ceepizz/rya/refs/heads/main/api"
        ))()

        if type(loaded) == "table"
            and type(loaded.MedicChain) == "function" then

            MedicChainAPI = loaded.MedicChain

        elseif type(loaded) == "function" then
            MedicChainAPI = loaded

        else
            AltairWarn("MedicChain failed to load its API.", "MedicChain")
            return false
        end
    end

    return MedicChainAPI(self, ...)
end

local function strategyRecordingSetup()
    local originalMethods = {}
    local recordableMethods = {
        "Mode", "Place", "Upgrade", "SetTarget", "Sell", "SellAll", "Ability", "SetOption", "MedicSelect", "MedicChain", "Ready", "VoteSkip", "WaitForWave", "UnlockTimeScale", "TimeScale"
    }

    for _, methodName in ipairs(recordableMethods) do
        originalMethods[methodName] = TDS[methodName]
        TDS[methodName] = function(self, ...)
            if not Globals.tdsReplaying and GameState == "GAME" then
                local argumentsList = {...}
                local stringifiedArguments = {}
                for _, argumentValue in ipairs(argumentsList) do
                    local argumentType = type(argumentValue)
                    if argumentType == "string" then
                        table.insert(stringifiedArguments, string.format("%q", argumentValue))
                    elseif argumentType == "number" or argumentType == "boolean" then
                        table.insert(stringifiedArguments, tostring(argumentValue))
                    elseif argumentType == "table" then
                        local parts = {}
                        for key, val in pairs(argumentValue) do
                            local keyType = type(key)
                            local formattedKey
                            if keyType == "string" then
                                formattedKey = string.format("[%q]", key)
                            elseif keyType == "number" then
                                formattedKey = string.format("[%d]", key)
                            else
                                formattedKey = string.format("[%s]", tostring(key))
                            end
                            local formattedValue = type(val) == "string" and string.format("%q", val) or tostring(val)
                            table.insert(parts, formattedKey .. " = " .. formattedValue)
                        end
                        table.insert(stringifiedArguments, "{" .. table.concat(parts, ", ") .. "}")
                    else
                        table.insert(stringifiedArguments, "nil")
                    end
                end
                
                if methodName == "Mode" then
                    executed_actions = {}
                else
                    local actionString = string.format("TDS:%s(%s)", methodName, table.concat(stringifiedArguments, ", "))
                    table.insert(executed_actions, actionString)
                    
                    local strategyFileContent = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    strategyFileContent = strategyFileContent .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", strategyFileContent)
                end
            end
            
            return originalMethods[methodName](self, ...)
        end
    end
end

strategyRecordingSetup()

if GameState == "LOBBY" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
    pcall(delfile, "ADS_LastStrat.lua")
end

-- Do not replay a saved strategy merely because the library was executed.
-- Strategy execution is now armed explicitly through the UI/manual runner.

-- // misc utility
local function IsVoidCharm(obj)
    return math.abs(obj.Position.Y) > 999999
end

local function GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function StartAutoGatling()
    if AutoGatlingRunning or not Globals.AutoGatling then return end
    AutoGatlingRunning = true
    task.spawn(function()
        while Globals.AutoGatling do
            if GameState == "GAME" then
                if not GatlingExecuted then
                    GatlingExecuted = true 
                    task.spawn(function()
                        pcall(function()
                            loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"))()
                        end)
                    end)
                end
            else
                GatlingExecuted = false 
            end
            task.wait(1)
        end
        AutoGatlingRunning = false
    end)
end

local function StartGatlify()
    if GatlifyRunning or not Globals.Gatlify then return end
    GatlifyRunning = true
    task.spawn(function()
        while Globals.Gatlify do
            if GameState == "GAME" then
                if not GatlifyExecuted then
                    repeat task.wait(0.5) until not IsCurrentlyLoading and not IsEquippingLoadout and not (TDS and TDS.LoadoutPending) and (os.clock() - LastLoadTime >= 5)
                    if not Globals.Gatlify then break end
                    if not GatlifyExecuted then
                        IsCurrentlyLoading = true
                        GatlifyExecuted = true 
                        pcall(function()
                            loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"))()
                        end)
                        IsCurrentlyLoading = false
                        LastLoadTime = os.clock()
                    end
                end
            else
                GatlifyExecuted = false 
            end
            task.wait(1)
        end
        GatlifyRunning = false
    end)
end

local function StartAutoPickups()
    if AutoPickupsRunning or not Globals.AutoPickups then return end
    AutoPickupsRunning = true

    task.spawn(function()
        while Globals.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = GetRoot()

            if folder and hrp then
                local char = hrp.Parent
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                local function MoveToPos(TargetPos)
                    if not humanoid then
                        return false
                    end
                    local function MoveDirect(pos)
                        humanoid:MoveTo(pos)
                        local StartT = os.clock()
                        while os.clock() - StartT < 2 do
                            if not Globals.AutoPickups then
                                return false
                            end
                            if (hrp.Position - pos).Magnitude < 4 then
                                return true
                            end
                            task.wait(0.1)
                        end
                        return (hrp.Position - pos).Magnitude < 4
                    end
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2,
                        AgentHeight = 6,
                        AgentCanJump = true,
                        AgentJumpHeight = 7,
                        AgentMaxSlope = 45
                    })
                    local ok = pcall(function()
                        path:ComputeAsync(hrp.Position, TargetPos)
                    end)
                    if ok and path.Status == Enum.PathStatus.Success then
                        local waypoints = path:GetWaypoints()
                        local BlockedConn = nil
                        BlockedConn = path.Blocked:Connect(function()
                            if BlockedConn then
                                BlockedConn:Disconnect()
                            end
                            if Globals.AutoPickups then
                                task.spawn(function()
                                    MoveToPos(TargetPos)
                                end)
                            end
                        end)
                        for _, wp in ipairs(waypoints) do
                            if not Globals.AutoPickups then
                                if BlockedConn then
                                    BlockedConn:Disconnect()
                                end
                                return false
                            end
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                humanoid.Jump = true
                            end
                            if not MoveDirect(wp.Position) then
                                if BlockedConn then
                                    BlockedConn:Disconnect()
                                end
                                return false
                            end
                        end
                        if BlockedConn then
                            BlockedConn:Disconnect()
                        end
                        return true
                    end
                    return MoveDirect(TargetPos)
                end

                for _, item in ipairs(folder:GetChildren()) do
                    if not Globals.AutoPickups then break end

                    if item:IsA("MeshPart") and (item.Name == "Bunz" or item.Name == "Lorebook" or item.Name == "SnowCharm") then
                        if not IsVoidCharm(item) then
                            if Globals.PickupMethod == "Instant" then
                                hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                                task.wait(0.2)
                                task.wait(0.3)
                            else
                                local TargetPos = item.Position + Vector3.new(0, 3, 0)
                                MoveToPos(TargetPos)
                                task.wait(0.2)
                                task.wait(0.3)
                            end
                        end
                    end
                end
            end

            task.wait(1)
        end

        AutoPickupsRunning = false
    end)
end

local function StartAutoSkip()
    if AutoSkipRunning or not Globals.AutoSkip then return end
    AutoSkipRunning = true

    task.spawn(function()
        while Globals.AutoSkip do
            local SkipVisible =
                PlayerGui:FindFirstChild("ReactOverridesVote")
                and PlayerGui.ReactOverridesVote:FindFirstChild("Frame")
                and PlayerGui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and PlayerGui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if SkipVisible and SkipVisible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                RunVoteSkip()
            end

            task.wait(0.1)
        end

        AutoSkipRunning = false
    end)
end

local function StartClaimRewards()
    if AutoClaimRewards or not Globals.ClaimRewards or GameState ~= "LOBBY" then 
        return 
    end

    AutoClaimRewards = true

    local player = game:GetService("Players").LocalPlayer
    local network = game:GetService("ReplicatedStorage"):WaitForChild("Network")

    local SpinTickets = player:WaitForChild("SpinTickets", 15)

    if SpinTickets and SpinTickets.Value > 0 then
        local TicketCount = SpinTickets.Value

        local DailySpin = network:WaitForChild("DailySpin", 5)
        local RedeemRemote = DailySpin and DailySpin:WaitForChild("RF:RedeemSpin", 5)

        if RedeemRemote then
            for i = 1, TicketCount do
                RedeemRemote:InvokeServer()
                task.wait(0.5)
            end
        end
    end

    for i = 1, 6 do
        local args = { i }
        network:WaitForChild("PlaytimeRewards"):WaitForChild("RF:ClaimReward"):InvokeServer(unpack(args))
        task.wait(0.5)
    end

    game:GetService("ReplicatedStorage").Network.DailySpin["RF:RedeemReward"]:InvokeServer()
    AutoClaimRewards = false
end

function StartBackToLobby()
    if GameState ~= "GAME" then return end
    if BackToLobbyRunning then return end
    BackToLobbyRunning = true

    task.spawn(function()
        local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 30)
        local gameStateReplicator = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 30)
        local voteReplicator = stateReplicators and stateReplicators:WaitForChild("VoteReplicator", 30)
        
        if not gameStateReplicator or not voteReplicator then
            while true do
                pcall(HandlePostMatch)
                task.wait(1)
            end
            return
        end

        while Globals.AutoRejoin or Globals.AutoRestart do
            local isGameOver = gameStateReplicator:GetAttribute("GameOver") == true
            if isGameOver then
                local health = gameStateReplicator:GetAttribute("Health") or 0
                if health > 0 then
                    if Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                else
                    if Globals.AutoRestart then
                        task.spawn(pcall, HandlePostMatch, true)
                        local lastVoteTime = 0
                        while Globals.AutoRestart do
                            local title = voteReplicator:GetAttribute("Title")
                            local enabled = voteReplicator:GetAttribute("Enabled")
                            
                            if enabled == true and title == "Restart?" then
                                if os.clock() - lastVoteTime > 3 then
                                    pcall(function()
                                        RemoteFunc:InvokeServer("Voting", "Skip")
                                    end)
                                    lastVoteTime = os.clock()
                                end
                            end
                            
                            if title == "Ready?" or gameStateReplicator:GetAttribute("GameOver") == false then
                                break
                            end
                            task.wait(0.5)
                        end
                        
                        if not Globals.AutoRestart then break end
                        
                        if isfile("ADS_LastStrat.lua") then
                            task.spawn(function()
                                repeat
                                    task.wait(0.1)
                                    local towersFolder = workspace:FindFirstChild("Towers")
                                until (towersFolder and #towersFolder:GetChildren() == 0) or not Globals.AutoRestart
                                
                                if not Globals.AutoRestart then return end
                                TDS:ResetAllStates()
                                TDS:RunStrategy()
                            end)
                        end
                        
                        repeat task.wait(1) until gameStateReplicator:GetAttribute("GameOver") == false or not Globals.AutoRestart
                    elseif Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                end
            end
            task.wait(1)
        end
        BackToLobbyRunning = false
    end)
end

local function StartAntiLag()
    if AntiLagRunning then return end
    AntiLagRunning = true

    local settings = settings().Rendering
    settings.QualityLevel = Enum.QualityLevel.Level01

    task.spawn(function()
        while Globals.AntiLag do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local ClientUnits = workspace:FindFirstChild("ClientUnits")

            if TowersFolder then
                for _, tower in ipairs(TowersFolder:GetChildren()) do
                    local anims = tower:FindFirstChild("Animations")
                    local weapon = tower:FindFirstChild("Weapon")
                    local projectiles = tower:FindFirstChild("Projectiles")

                    if anims then anims:Destroy() end
                    if projectiles then projectiles:Destroy() end
                    if weapon then weapon:Destroy() end
                end
            end
            if ClientUnits then
                for _, unit in ipairs(ClientUnits:GetChildren()) do
                    unit:Destroy()
                end
            end
            
            task.wait(0.5)
        end
        AntiLagRunning = false
    end)
end

local function StartAutoChain()
    if AutoChainRunning or not Globals.AutoChain then return end
    AutoChainRunning = true

    task.spawn(function()
        local idx = 1

        while Globals.AutoChain do
            local commander = {}
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                        commander[#commander + 1] = towers.Parent
                    end
                end
            end

            if #commander >= 3 then
                if idx > #commander then idx = 1 end

                local CurrentCommander = commander[idx]
                local replicator = CurrentCommander:FindFirstChild("TowerReplicator")
                local UpgradeLevel = replicator and replicator:GetAttribute("Upgrade") or 0

                if UpgradeLevel >= 4 and Globals.SupportCaravan then
                    RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentCommander, Name = "Support Caravan", Data = {} }
                    )
                    task.wait(0.1) 
                end

                local response = RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = CurrentCommander, Name = "Call Of Arms", Data = {} }
                )

                if response then
                    idx += 1

                    local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
                    local TimescaleFrame = hotbar and hotbar.Frame:FindFirstChild("timescale")

                    if TimescaleFrame and TimescaleFrame.Visible then
                        if TimescaleFrame:FindFirstChild("Lock") then
                            task.wait(10.3)
                        else
                            task.wait(5.25)
                        end
                    else
                        task.wait(10.3)
                    end
                else
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end

        AutoChainRunning = false
    end)
end

local function StartAutoDjBooth()
    if AutoDjRunning or not Globals.AutoDJ then return end
    AutoDjRunning = true

    task.spawn(function()
        while Globals.AutoDJ do
            local DJ = nil
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "DJ Booth"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = towers.Parent
                    end
                end
            end

            if DJ then
                RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} }
                )
            end

            task.wait(1)
        end

        AutoDjRunning = false
    end)
end

local function StartAutoNecro()
    if AutoNecroRunning or not Globals.AutoNecro then return end
    AutoNecroRunning = true

    local lastActivation = 0
    local ownerId = game.Players.LocalPlayer.UserId

    local function getNecros(towersFolder)
        local list = {}
        if not towersFolder then
            return list
        end
        for _, rep in ipairs(towersFolder:GetDescendants()) do
            if rep:IsA("Folder") and rep.Name == "TowerReplicator"
            and rep:GetAttribute("Name") == "Necromancer"
            and rep:GetAttribute("OwnerId") == ownerId then
                list[#list + 1] = rep.Parent
            end
        end
        return list
    end

    local function pickMaxGraves(rep, graveStore, up)
        local maxGraves = rep and rep:GetAttribute("Max_Graves")
        if graveStore then
            local gMax = graveStore:GetAttribute("Max_Graves")
            if type(gMax) == "number" and gMax > 0 then
                maxGraves = gMax
            end
        end
        if not maxGraves or maxGraves < 2 then
            if up >= 4 then
                maxGraves = 9
            elseif up >= 2 then
                maxGraves = 6
            else
                maxGraves = 3
            end
        end
        return maxGraves
    end

    local function countGraves(graveStore)
        if not graveStore then
            return 0
        end
        local cnt = 0
        for k, v in pairs(graveStore:GetAttributes()) do
            if type(k) == "string" and #k > 20 then
                local isDestroy = false
                if type(v) == "table" then
                    for _, elem in pairs(v) do
                        if tostring(elem) == "Destroy" then
                            isDestroy = true
                            break
                        end
                    end
                elseif tostring(v):find("Destroy") then
                    isDestroy = true
                end
                if isDestroy then
                    graveStore:SetAttribute(k, nil)
                else
                    cnt += 1
                end
            end
        end
        return cnt
    end

    local function cleanAllGraves(list)
        for _, necro in ipairs(list) do
            local rep = necro and necro:FindFirstChild("TowerReplicator")
            local store = rep and rep:FindFirstChild("GraveStone")
            if store then
                countGraves(store)
            end
        end
    end

    task.spawn(function()
        local idx = 1

        while Globals.AutoNecro do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local necromancer = getNecros(TowersFolder)
            cleanAllGraves(necromancer)

            if #necromancer >= 1 then
                if idx > #necromancer then idx = 1 end
                local CurrentNecromancer = necromancer[idx]
                local replicator = CurrentNecromancer:FindFirstChild("TowerReplicator")

                local up = replicator and (replicator:GetAttribute("Upgrade") or 0) or 0
                local graveStore = replicator and replicator:FindFirstChild("GraveStone")
                local maxGraves = pickMaxGraves(replicator, graveStore, up)
                local graveCount = countGraves(graveStore)
                local debounce = (replicator and replicator:GetAttribute("AbilityDebounce")) or 5
                local now = os.clock()

                if maxGraves and graveCount >= maxGraves and (now - lastActivation >= debounce) then
                    local response = RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentNecromancer, Name = "Raise The Dead", Data = {} }
                    )

                    if response then 
                        lastActivation = now
                        idx += 1
                        task.wait(1)
                    else
                        task.wait(0.5)
                    end
                else
                    task.wait(0.1)
                end
            else
                task.wait(1)
            end
        end

        AutoNecroRunning = false
    end)
end

local function StartAutoMercenary()
    if not Globals.AutoMercenary and not Globals.AutoMilitary then return end

    if AutoMercenaryBaseRunning then return end
    AutoMercenaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMercenary do
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Mercenary Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 5 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Air-Drop", 
                                Data = {
                                    pathName = 1, 
                                    directionCFrame = CFrame.new(), 
                                    dist = Globals.MercenaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMercenary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMercenaryBaseRunning = false
    end)
end

local function StartAutoMilitary()
    if not Globals.AutoMilitary then return end

    if AutoMilitaryBaseRunning then return end
    AutoMilitaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMilitary do
            local TowersFolder = workspace:FindFirstChild("Towers")
            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Military Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 4 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Airstrike", 
                                Data = {
                                    pathName = 1, 
                                    pointToEnd = CFrame.new(), 
                                    dist = Globals.MilitaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMilitary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMilitaryBaseRunning = false
    end)
end

local function StartSellFarm()
    if SellFarmsRunning or not Globals.SellFarms or GameState ~= "GAME" then return end
    SellFarmsRunning = true

    task.spawn(function()
        while Globals.SellFarms do
            local CurrentWave = GetCurrentWave()
            if Globals.SellFarmsWave and CurrentWave < Globals.SellFarmsWave then
                task.wait(1)
                continue
            end

            local TowersFolder = workspace:FindFirstChild("Towers")
            if TowersFolder then
                for _, replicator in ipairs(TowersFolder:GetDescendants()) do
                    if replicator:IsA("Folder") and replicator.Name == "TowerReplicator" then
                        local IsFarm = replicator:GetAttribute("Name") == "Farm"
                        local IsMine = replicator:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId

                        if IsFarm and IsMine then
                            local TowerModel = replicator.Parent
                            RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TowerModel })

                            task.wait(0.2)
                        end
                    end
                end
            end

            task.wait(1)
        end
        SellFarmsRunning = false
    end)
end

local AutoMedicModule = nil

local function StartMedicChain()
    if Globals.AutoMedic then
        if AutoMedicModule and AutoMedicModule.State and AutoMedicModule.State.Running then 
            return 
        end
        if not AutoMedicModule then
            local success, loadedLib = pcall(function()
                local url = "https://raw.githubusercontent.com/AmonguszzZ/ModdedAether/refs/heads/main/AutoAbilities/AutoMedicNew.lua"
                return loadstring(game:HttpGet(url))()
            end)
            if success and loadedLib then
                AutoMedicModule = loadedLib
            end
        end
        if AutoMedicModule then
            AutoMedicModule.Chaining()
        end
    else
        if AutoMedicModule and AutoMedicModule.State then
            AutoMedicModule.State.Running = false
        end
    end
end

task.spawn(function()
    task.wait(2)
    while true do
        if Globals.AutoPickups and not AutoPickupsRunning then
            StartAutoPickups()
        end

        if Globals.AutoSkip and not AutoSkipRunning then
            StartAutoSkip()
        end

        if Globals.TimeScaleEnabled and not TimeScaleRunning then
            StartTimeScale()
        end

        if Globals.AutoChain and not AutoChainRunning then
            StartAutoChain()
        end

        if Globals.AutoDJ and not AutoDjRunning then
            StartAutoDjBooth()
        end

        if Globals.AutoNecro and not AutoNecroRunning then
            StartAutoNecro()
        end

        if Globals.AutoMercenary and not AutoMercenaryBaseRunning then
            StartAutoMercenary()
        end

        if Globals.AutoMilitary and not AutoMilitaryBaseRunning then
            StartAutoMilitary()
        end

        if Globals.SellFarms and not SellFarmsRunning then
            StartSellFarm()
        end

        if Globals.AntiLag and not AntiLagRunning then
            StartAntiLag()
        end

        if (Globals.AutoRejoin or Globals.AutoRestart) and not BackToLobbyRunning then
            StartBackToLobby()
        end

        if Globals.AutoGatling and not AutoGatlingRunning then
            StartAutoGatling()
        end

        if Globals.Gatlify and not GatlifyRunning then
            StartGatlify()
        end

        if Globals.AutoOpenCrates and not AutoOpenRunning then
            StartAutoOpenCrates()
        end

        if Globals.AutoReady and not AutoReadyRunning then
            StartAutoReady()
        end

        if Globals.Easy and not EasyModeRunning then
            StartEasyMode()
        end

         if Globals.AutoMedic and not AutoMedicRunning then
            StartMedicChain()
        end

        task.wait(1)
    end
end)

if Globals.ClaimRewards and not AutoClaimRewards then
    StartClaimRewards()
end

MissionsUIFix()

return TDS
end)()

-- [[ EMBEDDED STRATEGY - MANUAL START ]]
local ADS_EMBEDDED_THREAD_KEY = "ADS_EmbeddedStrategyThread"

local function IsEmbeddedStrategyInGame()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player and player:FindFirstChild("PlayerGui")
    return playerGui and playerGui:FindFirstChild("ReactUniversalHotbar") ~= nil
end

local function StartEmbeddedStrategy()
    local env = getgenv()
    local running = env[ADS_EMBEDDED_THREAD_KEY]
    if running then
        return false
    end

    local thread
    thread = task.defer(function()
        local ok, err = pcall(function()
        TDS:Loadout("Scout", "Accelerator", "Mercenary Base", "Hacker", "Warlock")
        TDS:Mode("Frost")
        TDS:GameInfo("Simplicity", {})

        TDS:Place("Scout", -15.24, 1.00, -8.97) -- 1
        TDS:Place("Scout", -16.65, 1.00, -11.65) -- 2
        TDS:Place("Scout", -19.71, 1.00, -12.34) -- 3
        TDS:Place("Scout", -20.00, 1.00, -15.33) -- 4
        TDS:Place("Scout", -16.83, 1.00, -14.83) -- 5
        TDS:Place("Scout", -13.68, 1.00, -14.99) -- 6
        TDS:Place("Scout", -13.62, 1.00, -11.84) -- 7
        TDS:Upgrade(1)
        TDS:Upgrade(1)
        TDS:Upgrade(2)
        TDS:Upgrade(2)
        TDS:Upgrade(3)
        TDS:Upgrade(3)
        TDS:Upgrade(4)
        TDS:Upgrade(4)
        TDS:Upgrade(5)
        TDS:Upgrade(5)
        TDS:Upgrade(6)
        TDS:Upgrade(6)
        TDS:Upgrade(7)
        TDS:Upgrade(7)
        TDS:Place("Hacker", -12.12, 1.00, -9.13) -- 8
        TDS:Place("Hacker", -12.58, 1.00, 3.03) -- 9
        TDS:Upgrade(8)
        TDS:Upgrade(8)
        TDS:Upgrade(9)
        TDS:Upgrade(9)
        TDS:Place("Scout", -15.64, 1.00, 3.26) -- 10
        TDS:Upgrade(10)
        TDS:Upgrade(10)
        TDS:Place("Scout", -18.69, 1.00, 3.23) -- 11
        TDS:Upgrade(11)
        TDS:Upgrade(11)
        TDS:Place("Scout", -18.74, 1.00, 6.30) -- 12
        TDS:Upgrade(12)
        TDS:Upgrade(12)
        TDS:Place("Scout", -15.68, 1.00, 6.29) -- 13
        TDS:Upgrade(13)
        TDS:Upgrade(13)
        TDS:Place("Scout", -12.62, 1.00, 6.13) -- 14
        TDS:Upgrade(14)
        TDS:Upgrade(14)
        TDS:Place("Scout", -9.46, 1.00, 3.14) -- 15
        TDS:Upgrade(15)
        TDS:Upgrade(15)
        TDS:Place("Scout", -9.52, 1.00, 6.32) -- 16
        TDS:Upgrade(16)
        TDS:Upgrade(16)
        TDS:Place("Scout", -9.02, 1.00, -9.11) -- 17
        TDS:Upgrade(17)
        TDS:Upgrade(17)
        TDS:Place("Scout", -21.71, 1.00, 3.27) -- 18
        TDS:Upgrade(18)
        TDS:Upgrade(18)
        TDS:Upgrade(1)
        TDS:Upgrade(2)
        TDS:Upgrade(3)
        TDS:Upgrade(4)
        TDS:Upgrade(5)
        TDS:Upgrade(6)
        TDS:Upgrade(7)
        TDS:Upgrade(10)
        TDS:Upgrade(11)
        TDS:Upgrade(12)
        TDS:Upgrade(13)
        TDS:Upgrade(14)
        TDS:Upgrade(15)
        TDS:Upgrade(16)
        TDS:Upgrade(17)
        TDS:Upgrade(18)
        TDS:Place("Mercenary Base", 25.39, 1.00, 12.63) -- 19
        TDS:Upgrade(19)
        TDS:Upgrade(19)
        TDS:Upgrade(19)
        TDS:Place("Mercenary Base", 20.68, 1.00, 12.67) -- 20
        TDS:Upgrade(20)
        TDS:Upgrade(20)
        TDS:Upgrade(20)
        TDS:Place("Mercenary Base", 25.79, 1.00, 18.40) -- 21
        TDS:Upgrade(21)
        TDS:Upgrade(21)
        TDS:Upgrade(21)
        TDS:Upgrade(1)
        TDS:Upgrade(2)
        TDS:Upgrade(3)
        TDS:Upgrade(4)
        TDS:Upgrade(5)
        TDS:Upgrade(6)
        TDS:Upgrade(7)
        TDS:Upgrade(10)
        TDS:Upgrade(11)
        TDS:Upgrade(12)
        TDS:Upgrade(13)
        TDS:Upgrade(14)
        TDS:Upgrade(15)
        TDS:Upgrade(16)
        TDS:Upgrade(17)
        TDS:Upgrade(18)
        TDS:Upgrade(19)
        TDS:Upgrade(19)
        TDS:Upgrade(19)
        TDS:Ability(19, "Air-Drop", {pathName = 1, directionCFrame = CFrame.new(), dist = 150}, true)
        TDS:SetOption(19, "Unit 3", "Field Medic")
        TDS:Upgrade(20)
        TDS:Upgrade(20)
        TDS:Upgrade(20)
        TDS:Ability(20, "Air-Drop", {pathName = 1, directionCFrame = CFrame.new(), dist = 150}, true)
        TDS:Upgrade(21)
        TDS:Upgrade(21)
        TDS:Upgrade(21)
        TDS:Ability(21, "Air-Drop", {pathName = 1, directionCFrame = CFrame.new(), dist = 150}, true)
        TDS:Place("Warlock", -12.1382923, 2.35000086, -3.52993631) -- 22
        TDS:Upgrade(22)
        TDS:Upgrade(22)
        TDS:Upgrade(22)
        TDS:Place("Warlock", -9.12535381, 2.35000086, -3.75096846) -- 23
        TDS:Upgrade(23)
        TDS:Upgrade(23)
        TDS:Upgrade(23)
        TDS:Place("Warlock", -12.5959377, 2.35000038, -0.488339424) -- 24
        TDS:Upgrade(24)
        TDS:Upgrade(24)
        TDS:Upgrade(24)
        TDS:Place("Warlock", -9.51527023, 2.34998322, -0.76658535) -- 25
        TDS:Upgrade(25)
        TDS:Upgrade(25)
        TDS:Upgrade(25)
        TDS:Upgrade(22)
        TDS:Upgrade(22)
        TDS:Upgrade(23)
        TDS:Upgrade(23)
        TDS:Upgrade(24)
        TDS:Upgrade(24)
        TDS:Upgrade(25)
        TDS:Upgrade(25)
        TDS:Place("Accelerator", -6.10374212, 2.34998798, -3.54938531) -- 26
        TDS:Upgrade(26)
        TDS:Upgrade(26)
        TDS:Upgrade(26)
        TDS:Place("Accelerator", -2.93865132, 2.3499918, -3.34146309) -- 27
        TDS:Upgrade(27)
        TDS:Upgrade(27)
        TDS:Upgrade(27)
        TDS:Place("Accelerator", 0.183600187, 2.34998322, -3.29001379) -- 28
        TDS:Upgrade(28)
        TDS:Upgrade(28)
        TDS:Upgrade(28)
        TDS:Place("Accelerator", -2.4514637, 2.34998322, 2.40833759) -- 29
        TDS:Upgrade(29)
        TDS:Upgrade(29)
        TDS:Upgrade(29)
        TDS:Place("Accelerator", 0.104843616, 2.34998322, 4.04229164) -- 30
        TDS:Upgrade(30)
        TDS:Upgrade(30)
        TDS:Upgrade(30)
        TDS:Place("Accelerator", -5.86860037, 2.34999704, -8.9741745, 1, 0, 0, 0, 1, 0, 0, 0, 1) -- 31
        TDS:Upgrade(31)
        TDS:Upgrade(31)
        TDS:Upgrade(31)
        TDS:Place("Accelerator", -2.77454877, 2.35000157, -9.04821396, 1, 0, 0, 0, 1, 0, 0, 0, 1) -- 32
        TDS:Upgrade(32)
        TDS:Upgrade(32)
        TDS:Upgrade(32)
        TDS:Place("Accelerator", 0.199033976, 2.34998322, -9.67147255, 1, 0, 0, 0, 1, 0, 0, 0, 1) -- 33
        TDS:Upgrade(33)
        TDS:Upgrade(33)
        TDS:Upgrade(33)
        TDS:Upgrade(26)
        TDS:Upgrade(26)
        TDS:Upgrade(27)
        TDS:Upgrade(27)
        TDS:Upgrade(28)
        TDS:Upgrade(28)
        TDS:Upgrade(29)
        TDS:Upgrade(29)
        TDS:Upgrade(30)
        TDS:Upgrade(30)
        TDS:Upgrade(31)
        TDS:Upgrade(31)
        TDS:Upgrade(32)
        TDS:Upgrade(32)
        TDS:Upgrade(33)
        TDS:Upgrade(33)
        TDS:Upgrade(8)
        TDS:Upgrade(8)
        TDS:Upgrade(8, 2)
        TDS:Upgrade(9)
        TDS:Upgrade(9)
        TDS:Upgrade(9, 2)
        TDS:Ability(8, "Hologram Tower", {
            towerToClone = 19,
            towerPosition = {
                Vector3.new(14.1853657, 3.46938539, 13.4541798),
                Vector3.new(15.6933384, 3.46938467, 18.3442345),
            }
        }, true)
        TDS:Ability(9, "Hologram Tower", {
            towerToClone = 20,
            towerPosition = {
                Vector3.new(20.7010803, 3.46938467, 18.3634109),
                Vector3.new(19.6996384, 3.46937752, 4.1759696),
            }
        }, true)
        TDS:SetOption(19, "Unit 1", "Riot Guard", 40)
        TDS:SetOption(19, "Unit 2", "Riot Guard", 40)
        TDS:SetOption(19, "Unit 3", "Riot Guard", 40)
        TDS:SetOption(20, "Unit 1", "Riot Guard", 40)
        TDS:SetOption(20, "Unit 2", "Riot Guard", 40)
        TDS:SetOption(20, "Unit 3", "Riot Guard", 40)
        TDS:SetOption(21, "Unit 1", "Riot Guard", 40)
        TDS:SetOption(21, "Unit 2", "Riot Guard", 40)
        TDS:SetOption(21, "Unit 3", "Riot Guard", 40)
        end)

        env[ADS_EMBEDDED_THREAD_KEY] = nil

        if not ok then
            AltairWarn("Embedded strategy error: " .. tostring(err), "Strategy Error")
        end
    end)

    env[ADS_EMBEDDED_THREAD_KEY] = thread
    return true
end

local function StopEmbeddedStrategy()
    local env = getgenv()
    local thread = env[ADS_EMBEDDED_THREAD_KEY]
    if thread then
        pcall(task.cancel, thread)
        env[ADS_EMBEDDED_THREAD_KEY] = nil
    end
end

getgenv().ADS_StartEmbeddedStrategy = StartEmbeddedStrategy
getgenv().ADS_StopEmbeddedStrategy = StopEmbeddedStrategy

-- No automatic strategy continuation. The embedded strategy only runs after
-- the user explicitly presses the Start Embedded Strategy button in this execution.
