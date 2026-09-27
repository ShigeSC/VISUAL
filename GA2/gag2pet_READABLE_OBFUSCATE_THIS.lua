-- ScoopHub V2.2 - Remote Auto Buy Pet module
-- Readable build: obfuscate this file by itself before uploading as gag2pet.lua.
local Module = { Version = "ScoopHub-V2.2-AutoBuyPet-Remote-1" }

function Module.Init(Bridge)
    if type(Bridge) ~= "table" then error("[ScoopHub AutoBuy] Bridge required") end

    local T = Bridge.T
    local TrackConnection = Bridge.TrackConnection
    local ScoopHubRunAlive = Bridge.RunAlive
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local SG = Bridge.SG
    local GP = Bridge.GP
    local Auto = Bridge.Auto
    local Scale = Bridge.Scale
    local getScoopHubQueueOnTeleport = Bridge.GetQueueOnTeleport
    local queueScoopHubAfterTeleport = Bridge.QueueAfterTeleport

    local AccentThemePresets = Bridge.AccentThemePresets
    local GetAccentPreset = Bridge.GetAccentPreset
    local ActiveAccentPreset = Bridge.ActiveAccentPreset
    local AccentSelectedBg = Bridge.AccentSelectedBg
    local AccentButtonBg = Bridge.AccentButtonBg
    local AccentButtonBgHover = Bridge.AccentButtonBgHover
    local AccentSoftStroke = Bridge.AccentSoftStroke
    local AccentSoftStrokeAlt = Bridge.AccentSoftStrokeAlt
    local CurrentAppliedAccentTheme = Bridge.CurrentAppliedAccentTheme or "Red"
    local currentRequestedThemeName = Bridge.CurrentRequestedThemeName
    local prepareThemedInstance = Bridge.PrepareThemedInstance
    local applyDynamicThemeToInstance = Bridge.ApplyDynamicThemeToInstance

    if type(T) ~= "table" or not SG or not Auto or not Scale then
        error("[ScoopHub AutoBuy] GUI bridge incomplete")
    end
    if type(TrackConnection) ~= "function" or type(ScoopHubRunAlive) ~= "function" then
        error("[ScoopHub AutoBuy] runtime bridge incomplete")
    end

local function __ScoopHubInitAutoBuyPet()

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

if _G.ScoopHubAutoBuyPetIdleConnection then
    pcall(function()
        _G.ScoopHubAutoBuyPetIdleConnection:Disconnect()
    end)
end

_G.ScoopHubAutoBuyPetIdleToken = (_G.ScoopHubAutoBuyPetIdleToken or 0) + 1

do
local antiIdleToken = _G.ScoopHubAutoBuyPetIdleToken
local VirtualInputManager = game:GetService("VirtualInputManager")

local function antiIdleJump()
    local sentInput = pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.08)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    if not sentInput then
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then humanoid.Jump = true end
    end
end

_G.ScoopHubAutoBuyPetIdleConnection = TrackConnection(LocalPlayer.Idled:Connect(antiIdleJump))

task.spawn(function()
    while ScoopHubRunAlive() and _G.ScoopHubAutoBuyPetIdleToken == antiIdleToken do
        task.wait(180)
        if _G.ScoopHubAutoBuyPetIdleToken == antiIdleToken then antiIdleJump() end
    end
end)
end

local isKRNL = type(getScoopHubQueueOnTeleport()) == "function"

local function setupAutoRejoinQueue()
    local success = queueScoopHubAfterTeleport()

    if success then
        _G.__ScoopHubSilentLog("[AutoBuyPet] queue_on_teleport registered successfully")
    else
        warn("[AutoBuyPet] queue_on_teleport is unavailable or failed")
    end

    return success
end

do
local function setupTeleportHandler()

    TrackConnection(LocalPlayer.OnTeleport:Connect(function(teleportState)
        if teleportState == Enum.TeleportState.Started then
            _G.__ScoopHubSilentLog("[AutoBuyPet] Teleport started - saving state...")

            if saveSettings then
                pcall(saveSettings)
            end
        elseif teleportState == Enum.TeleportState.Failed then
            _G.__ScoopHubSilentLog("[AutoBuyPet] Teleport failed - will retry...")
            task.wait(3)
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
        end
    end))
end

pcall(setupTeleportHandler)
end

local function enableKRNLQueue()
    if isKRNL then
        setupAutoRejoinQueue()
    end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local Networking = require(ReplicatedStorage.SharedModules.Networking)
local ShovelNet = Networking.Shovel

local Theme, Config
Theme = {
    Bg = Color3.fromRGB(9, 5, 8),
    Panel = Color3.fromRGB(22, 10, 14),
    PanelLine = Color3.fromRGB(154, 44, 53),
    Red = Color3.fromRGB(231, 47, 59),
    RedDark = Color3.fromRGB(145, 28, 39),
    Text = Color3.fromRGB(255, 111, 120),
    TextDim = Color3.fromRGB(190, 73, 84),
    Success = Color3.fromRGB(99, 215, 163),
    White = Color3.fromRGB(246, 244, 252),
    TabBg = Color3.fromRGB(35, 16, 22),
    InputBg = Color3.fromRGB(49, 41, 49),
    InputText = Color3.fromRGB(238, 240, 249),
    Avatar = Color3.fromRGB(124, 106, 115),
    ObsidianTop = Color3.fromRGB(39, 11, 17),
    ObsidianMid = Color3.fromRGB(8, 5, 8),
    ObsidianLow = Color3.fromRGB(34, 8, 11),
    Surface = Color3.fromRGB(22, 10, 14),
    Surface2 = Color3.fromRGB(37, 17, 23),
    Surface3 = Color3.fromRGB(52, 31, 37),
    Stroke = Color3.fromRGB(179, 52, 63),
    Muted = Color3.fromRGB(199, 170, 176),
    Glow = Color3.fromRGB(211, 64, 75),
    Font = Enum.Font.GothamBold,
    FontBody = Enum.Font.Gotham,
}

Config = {
    Discord = "discord.gg/WxgqUa9Qz",
    DiscordIcon = "rbxassetid://94434236999817",
    Logo = "rbxassetid://90541504618217",
    LogoColor = Color3.fromRGB(255, 255, 255),
    Title = "AUTO BUY PET",
    Version = "V1.9",
    SubTitle = "by ScoopHub",
    HubNameColor = Color3.fromRGB(242, 92, 101),
    SubTitleColor = Color3.fromRGB(166, 174, 187),
}

local function colorKey(color)
    return string.format("%d,%d,%d", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

GetAccentPreset = function(themeName)
    return AccentThemePresets[themeName] or AccentThemePresets.Red
end

local function applyAccentPaletteTables(preset)
    T.Line = preset.Line
    T.Red = preset.Red
    T.RedDark = preset.RedDark
    T.Text = preset.Text
    T.Dim = preset.Dim
    T.Stroke = preset.Stroke
    T.UserActiveBg = preset.UserActiveBg
    T.UserActiveBgAlt = preset.UserActiveBgAlt
    T.UserAccentButton = preset.UserAccentButton
    T.UserAccentButtonHover = preset.UserAccentButtonHover
    T.UserSoftStroke = preset.UserSoftStroke
    T.UserSoftStrokeAlt = preset.UserSoftStrokeAlt

    if type(Theme) == "table" then
        Theme.PanelLine = preset.Line
        Theme.Red = preset.Red
        Theme.RedDark = preset.RedDark
        Theme.Text = preset.Text
        Theme.TextDim = preset.Dim
        Theme.Stroke = preset.Stroke
        Theme.Glow = preset.Red
        Theme.UserActiveBg = preset.UserActiveBg
        Theme.UserActiveBgAlt = preset.UserActiveBgAlt
        Theme.UserAccentButton = preset.UserAccentButton
        Theme.UserAccentButtonHover = preset.UserAccentButtonHover
        Theme.UserSoftStroke = preset.UserSoftStroke
        Theme.UserSoftStrokeAlt = preset.UserSoftStrokeAlt
    end

    if type(Config) == "table" then
        Config.HubNameColor = preset.HubNameColor
    end
end

ActiveAccentPreset = function()
    return GetAccentPreset("Red")
end

AccentSelectedBg = function()
    return ActiveAccentPreset().UserActiveBgAlt
end

AccentButtonBg = function()
    return ActiveAccentPreset().UserAccentButton
end

AccentButtonBgHover = function()
    return ActiveAccentPreset().UserAccentButtonHover
end

AccentSoftStroke = function()
    return ActiveAccentPreset().UserSoftStroke
end

AccentSoftStrokeAlt = function()
    return ActiveAccentPreset().UserSoftStrokeAlt
end

CurrentAppliedAccentTheme = "Red"
applyAccentPaletteTables(GetAccentPreset("Red"))
_G.ScoopHubApplyAccentTheme = nil

if SG and SG.DescendantAdded then
    SG.DescendantAdded:Connect(function(instance)
        task.defer(function()
            if not (instance and instance.Parent) then return end
            local selectedTheme = currentRequestedThemeName()
            pcall(function()
                applyDynamicThemeToInstance(instance, selectedTheme, "Red")
            end)
        end)
    end)
end

local function New(className, props, parent)
    local inst = Instance.new(className)
    props = props or {}
    prepareThemedInstance(inst, props)
    for prop, value in pairs(props) do
        inst[prop] = value
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function GetGuiParent()
    local ok, gethui_ok = pcall(function() return gethui and gethui() end)
    if ok and gethui_ok then
        return gethui_ok
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function MakeDraggable(handle, frame)
    local dragging, dragStart, startPos = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

local function SafeTween(Object, Info, Properties)
    if not Object then return nil end
    Properties = Properties or {}
    prepareThemedInstance(Object, Properties)
    local Success, Tween = pcall(function()
        return TweenService:Create(Object, Info, Properties)
    end)
    if Success and Tween then
        local Played = pcall(function() Tween:Play() end)
        if Played then return Tween end
    end
    return nil
end

local petProtectEnabled = false
local targetPetNames = {}
local targetDisplayText = "Select pets..."
local maxPetPrice = 50000000
local petWalkSpeed = 32
local petPunchRadius = 16
local fastCFrameMove = false

local buyBigPetsPriority = false
local buyHugePetsPriority = false
local petProtectThread = nil
local petsBought = 0
totalSpent = 0
serverHops = 0
serverHopInProgress = false
pendingPetDelivery = false
pendingPetDeliveryName = ""
pendingPetDeliveryCount = 0
local autoRejoin = false
local customJobIds = {}
local customJobIndex = 1
local petHistory = {}
targetPresets = {}
activityFeed = {}
dailyDate = os.date("%Y-%m-%d")
dailyPetsBought = 0
local cleanupEnabled = false
local autoSellEnabled = false
local webhookEnabled = false
local webhookUrl = ""
sellWebhookEnabled = false
sellWebhookUrl = ""

local GLOBAL_WEBHOOK_URL = "https://discord.com/api/webhooks/1531370747170259145/CcWzZasAXVgedW4TOP-3AXXT7WUryve7loGpr2zUGFCIU7h22zSroSPBLbAM2v9SceZe"

local PRIVATE_WEBHOOK_URL = "https://discord.com/api/webhooks/1537116981348802670/Cp6Ej5csTO0688_IRyKsoBBiehLUwwdibrCOL5x-r-sjzTGrJT5tB45nUedP71x3NQBM"
function censorGlobalPlayerName(name)
    local text = tostring(name or "Player")
    return text:sub(1, math.min(3, #text)) .. "******"
end

webhookPetAlerts = true
webhookSellAlerts = true
webhookDisconnectAlerts = true
sellBatchInterval = 15
webhookUrlsVisible = false
lastWebhookStatus = "No webhook sent yet"
local lastDisconnectWebhookAt = 0
local sessionStartedAt = os.time()
autoBuyRuntimeSeconds = 0
autoBuyRuntimeStartedAt = nil
local lastAutoSaveAt = 0

local resumePetProtectOnLoad = false
local playerStats = {}
local currentPlayerKey = tostring(LocalPlayer.UserId)

local PET_RARITY_OVERRIDES = {
    Frog = "Common",
    Bunny = "Common",
    Owl = "Uncommon",
    Dog = "Uncommon",
    Deer = "Rare",
    Turtle = "Rare",
    Hedgehog = "Rare",
    Turkey = "Rare",
    Robin = "Legendary",
    Bee = "Legendary",
    Butterfly = "Legendary",
    Squirrel = "Legendary",
    Swan = "Legendary",
    Jackalope = "Legendary",
    Monkey = "Mythic",
    JandelMonkey = "Mythic",
    GoldenDragonfly = "Mythic",
    Unicorn = "Mythic",
    Bear = "Mythic",
    BaldEagle = "Mythic",
    Firefly = "Mythic",
    Fox = "Mythic",
    Wolf = "Mythic",
    Scarecrow = "Mythic",
    Raccoon = "Super",
    BlackDragon = "Super",
    IceSerpent = "Super",
    ShadowDragon = "Super",
    RedPanda = "Super",
    Kitsune = "Secret",
}

local RARITY_RANK = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Legendary = 4,
    Mythic = 5,
    Super = 6,
    Secret = 7,
    Unknown = 0,
}

local function storeCurrentPlayerStats()
    playerStats[currentPlayerKey] = {
        username = LocalPlayer.Name,
        petsBought = petsBought,
        spent = totalSpent,
        serverHops = serverHops,
        runtimeSeconds = autoBuyRuntimeSeconds + ((petProtectEnabled and autoBuyRuntimeStartedAt)
            and math.max(0, os.time() - autoBuyRuntimeStartedAt) or 0),
        history = petHistory,
        dailyDate = dailyDate,
        dailyPetsBought = dailyPetsBought,
    }
end

local function resetAccountStats()

    petsBought = 0
    totalSpent = 0
    serverHops = 0
    autoBuyRuntimeSeconds = 0
    autoBuyRuntimeStartedAt = nil
    petHistory = {}
    dailyDate = os.date("%Y-%m-%d")
    dailyPetsBought = 0
end

local AllPets = {
    "Frog", "Bunny", "Owl", "Dog", "Deer", "Turtle", "Hedgehog", "Turkey",
    "Robin", "Bee", "Butterfly", "Squirrel", "Swan", "Jackalope",
    "Monkey", "JandelMonkey", "GoldenDragonfly", "Unicorn", "Bear", "BaldEagle",
    "Firefly", "Fox", "Wolf", "Scarecrow", "Raccoon", "BlackDragon", "IceSerpent",
    "ShadowDragon", "RedPanda", "Kitsune"
}

local selectedPets = {}
for _, name in ipairs(targetPetNames) do
    selectedPets[name] = true
end
local selectedSellPets = {}

local function formatList(items)
    if type(items) ~= "table" or #items == 0 then return "None" end
    if #items <= 2 then return table.concat(items, ", ") end
    return items[1] .. ", " .. items[2] .. " +" .. (#items - 2) .. " more"
end

local function Notify(title, content, duration)
    duration = duration or 3
    local notifGui = New("ScreenGui", { Name = "PetNotif", ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, GetGuiParent())
    local frame = New("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Position = UDim2.new(1, 350, 1, -30),
        Size = UDim2.new(0, 280, 0, 60),
    }, notifGui)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
    New("UIStroke", { Color = Theme.Red, Thickness = 1, Transparency = 0.5 }, frame)
    New("TextLabel", {
        Text = title,
        Font = Theme.Font,
        TextSize = 14,
        TextColor3 = Theme.White,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -24, 0, 18),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    New("TextLabel", {
        Text = content,
        Font = Theme.FontBody,
        TextSize = 12,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 28),
        Size = UDim2.new(1, -24, 0, 24),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }, frame)

    SafeTween(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
        Position = UDim2.new(1, -30, 1, -30)
    })
    task.delay(duration, function()
        if notifGui.Parent then
            SafeTween(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back), {
                Position = UDim2.new(1, 350, 1, -30)
            })
            task.delay(0.5, function()
                if notifGui.Parent then notifGui:Destroy() end
            end)
        end
    end)
end

function addActivity(message)
    table.insert(activityFeed, 1, os.date("%H:%M") .. "  " .. tostring(message))
    while #activityFeed > 5 do
        table.remove(activityFeed)
    end
    if ActivityLabel then
        ActivityLabel.Text = "ACTIVITY  ●  " .. (activityFeed[1] or "Waiting for activity")
    end
    if ActivityList then
        rebuildActivityFeed()
    end
end

local function formatWebhookElapsed()
    local elapsed = autoBuyRuntimeSeconds
    if petProtectEnabled and autoBuyRuntimeStartedAt then
        elapsed = elapsed + math.max(0, os.time() - autoBuyRuntimeStartedAt)
    end
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local seconds = elapsed % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds)
    end
    return string.format("%d:%02d", minutes, seconds)
end

local function formatWebhookNumber(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    return text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local WEBHOOK_RARITY_COLORS = {
    Common = 5763719,
    Uncommon = 5793266,
    Rare = 3447003,
    Legendary = 16766720,
    Mythic = 10181046,
    Super = 15158332,
    Secret = 11184810,
}
local WEBHOOK_PET_PAGE_NAMES = {
    GoldenDragonfly = "Golden Dragonfly",
    BlackDragon = "Black Dragon",
    IceSerpent = "Ice Serpent",
    ShadowDragon = "Shadow Dragon",
    JandelMonkey = "Jandel Monkey",
    RedPanda = "Red Panda",
}

local function stripPetSizePrefix(petName)
    local name = tostring(petName or "")
    name = name:gsub("^Huge%s+", "")
    name = name:gsub("^Big%s+", "")
    return name
end

local webhookPetImageCache = {}

local function getWebhookPetImage(petName)
    if webhookPetImageCache[petName] then
        return webhookPetImageCache[petName]
    end

    local basePetName = stripPetSizePrefix(petName)
    local pageName = WEBHOOK_PET_PAGE_NAMES[basePetName] or basePetName
    local imageUrl = nil

    pcall(function()
        local apiUrl = "https://growagarden2.fandom.com/api.php?action=query&format=json&prop=pageimages&piprop=thumbnail&pithumbsize=256&titles="
            .. HttpService:UrlEncode(pageName)
        local pageData = HttpService:JSONDecode(game:HttpGet(apiUrl))
        local pages = pageData and pageData.query and pageData.query.pages
        local pageKey = pages and next(pages)
        local page = pageKey and pages[pageKey]
        imageUrl = page and page.thumbnail and page.thumbnail.source
    end)

    imageUrl = imageUrl or ("https://growagarden2.fandom.com/wiki/Special:FilePath/"
        .. HttpService:UrlEncode(pageName .. ".png"))
    webhookPetImageCache[petName] = imageUrl
    return imageUrl
end

local function sendWebhook(title, description, color, fields, thumbnailUrl, destinationUrl, bypassMainToggle)
    local targetUrl = destinationUrl or webhookUrl
    if (not bypassMainToggle and not webhookEnabled) or targetUrl == "" then return false end

    local requestFn = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
    if type(requestFn) ~= "function" then
        warn("[AutoBuyPet] Webhook request function is unavailable in this executor.")
        lastWebhookStatus = "Last webhook failed: request unavailable"
        return false
    end

    local embed = {
        title = title,
        description = description,
        color = color or 15158203,

        footer = { text = "AUTO BUY PET V1.9  ●  discord.gg/WxgqUa9Qz" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    if fields then embed.fields = fields end
    if thumbnailUrl then embed.thumbnail = { url = thumbnailUrl } end

    local body = HttpService:JSONEncode({
        username = "ScoopHub | AUTO BUY PET V1.9",
        embeds = { embed },
    })

    local requestOk, response = pcall(function()
        return requestFn({
            Url = targetUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)
    local statusCode = requestOk and type(response) == "table" and (response.StatusCode or response.Status)
    if not requestOk or (statusCode and (tonumber(statusCode) or 0) >= 300) then
        task.wait(0.8)
        requestOk, response = pcall(function()
            return requestFn({
                Url = targetUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        statusCode = requestOk and type(response) == "table" and (response.StatusCode or response.Status)
        if not requestOk then
            lastWebhookStatus = "Last webhook failed: " .. tostring(response)
            if WebhookStatusLabel then
                WebhookStatusLabel.Text = lastWebhookStatus
                WebhookStatusLabel.TextColor3 = Theme.Text
            end
            return false, tostring(response)
        end
        if statusCode and (tonumber(statusCode) or 0) >= 300 then
            lastWebhookStatus = "Last webhook failed: HTTP " .. tostring(statusCode)
            if WebhookStatusLabel then
                WebhookStatusLabel.Text = lastWebhookStatus
                WebhookStatusLabel.TextColor3 = Theme.Text
            end
            return false, "Discord returned HTTP " .. tostring(statusCode)
        end
    end
    lastWebhookStatus = "Last sent: " .. tostring(title)
    if WebhookStatusLabel then
        WebhookStatusLabel.Text = lastWebhookStatus
        WebhookStatusLabel.TextColor3 = Theme.Success
    end
    return true
end

pcall(function()
    TrackConnection(GuiService.ErrorMessageChanged:Connect(function(message)
        local lowerMessage = string.lower(tostring(message or ""))
        if webhookDisconnectAlerts and (lowerMessage:find("error code: 279", 1, true) or lowerMessage:find("failed to connect", 1, true))
            and tick() - lastDisconnectWebhookAt > 20 then
            lastDisconnectWebhookAt = tick()
            sendWebhook(
                "CONNECTION LOST",
                "Roblox reported a connection failure (**Error 279**).",
                15158332,
                {
                    { name = "TOTAL PETS", value = tostring(petsBought), inline = true },
                }
            )
        end
    end))
end)

local function setCleanupEnabled(enabled)
    cleanupEnabled = enabled == true

    local core = type(_G.ScoopHubEnsureVisualFeaturesCore) == "function"
        and _G.ScoopHubEnsureVisualFeaturesCore()
        or nil

    if type(core) ~= "table" or type(core.SetLowGraphics) ~= "function" then
        if cleanupEnabled then
            cleanupEnabled = false
            warn("[ScoopHub] Remote Low Graphics module is unavailable.")
        end
        return false
    end

    local ok, result = pcall(core.SetLowGraphics, cleanupEnabled)
    if not ok or result == false then
        if cleanupEnabled then
            cleanupEnabled = false
        end
        warn("[ScoopHub] Low Graphics remote call failed: " .. tostring(result))
        return false
    end

    return true
end

local PetAutoSellRuntime = {}

do

local lastPetSellAt = 0
local petSellBusy = false

local PET_AUTO_SELL_SAFETY_SECONDS = 2
local PetSellEventPending = false
local PetSellDrainRunning = false
local PetSellWakeSerial = 0
local PetSellSourceSignature = nil
local PetSellSourceConnections = {}
local PetSellToolConnections = setmetatable({}, { __mode = "k" })

local queuePetAutoSell
local refreshPetAutoSellSources

local function classifySellPetSizeFromInstance(instance)
    if not instance then
        return nil
    end

    local attributes = instance:GetAttributes()

    for _, attributeName in ipairs({
        "Size", "SizeType", "PetSize", "PetSizeType",
        "Variant", "VariantType", "SpecialType",
    }) do
        local value = attributes[attributeName]
        if type(value) == "string" then
            local lowered = string.lower(value)

            if string.find(lowered, "huge", 1, true)
                or string.find(lowered, "giant", 1, true) then
                return "Huge"
            end

            if string.find(lowered, "big", 1, true) then
                return "Big"
            end
        end
    end

    if attributes.IsHuge == true or attributes.Huge == true then
        return "Huge"
    end
    if attributes.IsBig == true or attributes.Big == true then
        return "Big"
    end

    for _, attributeName in ipairs({
        "SizeMultiplier", "ScaleMultiplier", "PetScale",
    }) do
        local rawValue = attributes[attributeName]
        local value = tonumber(rawValue)

        if value then
            if value >= 1.5 then
                return "Huge"
            elseif value > 1.1 then
                return "Big"
            end
        end
    end

    local loweredName = string.lower(tostring(instance.Name or ""))
    if string.find(loweredName, "huge", 1, true)
        or string.find(loweredName, "giant", 1, true) then
        return "Huge"
    end
    if string.find(loweredName, "big", 1, true) then
        return "Big"
    end

    for _, attributeName in ipairs({
        "Size", "SizeType", "PetSize", "PetSizeType",
        "Variant", "VariantType", "SpecialType",
    }) do
        local value = attributes[attributeName]
        if type(value) == "string" then
            local lowered = string.lower(value)

            if lowered == "normal"
                or lowered == "regular"
                or lowered == "default"
                or lowered == "standard" then
                return "Normal"
            end
        end
    end

    local hasHugeFlag = attributes.IsHuge ~= nil or attributes.Huge ~= nil
    local hasBigFlag = attributes.IsBig ~= nil or attributes.Big ~= nil
    if (hasHugeFlag or hasBigFlag)
        and attributes.IsHuge ~= true
        and attributes.Huge ~= true
        and attributes.IsBig ~= true
        and attributes.Big ~= true then
        return "Normal"
    end

    for _, attributeName in ipairs({
        "SizeMultiplier", "ScaleMultiplier", "PetScale",
    }) do
        local rawValue = attributes[attributeName]
        local value = tonumber(rawValue)

        if value and value <= 1.1 then
            return "Normal"
        end
    end

    if loweredName == "normal"
        or string.find(loweredName, "normal ", 1, true)
        or string.find(loweredName, " normal", 1, true) then
        return "Normal"
    end

    return nil
end

local function getBackpackPetSellSizeTier(tool)
    local foundNormal = false
    local foundBig = false

    local function consider(instance)
        local tier = classifySellPetSizeFromInstance(instance)

        if tier == "Huge" then
            return "Huge"
        elseif tier == "Big" then
            foundBig = true
        elseif tier == "Normal" then
            foundNormal = true
        end

        return nil
    end

    if consider(tool) == "Huge" then
        return "Huge"
    end

    for _, descendant in ipairs(tool:GetDescendants()) do
        if consider(descendant) == "Huge" then
            return "Huge"
        end
    end

    if foundBig then
        return "Big"
    end
    if foundNormal then
        return "Normal"
    end

    return "Unknown"
end

local function disconnectPetSellToolWatcher(tool)
    local connections = PetSellToolConnections[tool]
    if not connections then
        return
    end

    for index = #connections, 1, -1 do
        pcall(function()
            connections[index]:Disconnect()
        end)
    end

    PetSellToolConnections[tool] = nil
end

local function watchPetSellTool(tool)
    if not tool or not tool:IsA("Tool") or PetSellToolConnections[tool] then
        return
    end

    local connections = {}
    PetSellToolConnections[tool] = connections

    local function changed()
        if autoSellEnabled and queuePetAutoSell then
            queuePetAutoSell("pet_metadata_changed")
        end
    end

    connections[#connections + 1] = tool.AttributeChanged:Connect(changed)
    connections[#connections + 1] = tool.DescendantAdded:Connect(changed)
    connections[#connections + 1] = tool.DescendantRemoving:Connect(changed)
end

local function disconnectPetAutoSellSources()
    PetSellWakeSerial += 1
    PetSellEventPending = false

    for index = #PetSellSourceConnections, 1, -1 do
        pcall(function()
            PetSellSourceConnections[index]:Disconnect()
        end)
        PetSellSourceConnections[index] = nil
    end

    for tool in pairs(PetSellToolConnections) do
        disconnectPetSellToolWatcher(tool)
    end

    PetSellSourceSignature = nil
end

RegisterScoopHubCleanup(function()
    disconnectPetAutoSellSources()
end)

local function getPetSellIntervalRemaining()
    if lastPetSellAt <= 0 then
        return 0
    end

    return math.max(
        0,
        sellBatchInterval - (tick() - lastPetSellAt)
    )
end

local function sellSelectedBackpackPets()
    if petSellBusy or not autoSellEnabled then
        return 0
    end

    local remaining = getPetSellIntervalRemaining()
    if remaining > 0 then
        return 0, remaining
    end

    petSellBusy = true

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local attempted = 0
    local soldByName = {}
    local sellCandidates = {}

    if backpack and Networking.NPCS and Networking.NPCS.SellPet then
        for _, tool in ipairs(backpack:GetChildren()) do
            if autoSellEnabled
                and tool:IsA("Tool")
                and selectedSellPets[tool.Name] then

                local petId = tool:GetAttribute("PetId")
                local isFavorite =
                    tool:GetAttribute("Favorite") == true
                    or tool:GetAttribute("IsFavorite") == true

                if not isFavorite
                    and type(petId) == "string"
                    and petId ~= "" then

                    local sizeTier = getBackpackPetSellSizeTier(tool)

                    if sizeTier == "Normal" then
                        sellCandidates[tool.Name] =
                            sellCandidates[tool.Name] or {}

                        table.insert(
                            sellCandidates[tool.Name],
                            tool
                        )
                    end
                end
            end
        end

        local hasCandidates = next(sellCandidates) ~= nil
        if hasCandidates then

            lastPetSellAt = tick()
        end

        for petName, tools in pairs(sellCandidates) do
            for index = 1, #tools do
                local tool = tools[index]
                local petId = tool:GetAttribute("PetId")

                if autoSellEnabled
                    and type(petId) == "string"
                    and petId ~= ""
                    and getBackpackPetSellSizeTier(tool) == "Normal" then

                    local ok, err = pcall(function()
                        Networking.NPCS.SellPet:Fire(petId)
                    end)

                    if ok then
                        attempted += 1
                        soldByName[petName] =
                            (soldByName[petName] or 0) + 1
                    else
                        warn(
                            "[AutoBuyPet] Could not sell "
                            .. petName
                            .. ": "
                            .. tostring(err)
                        )
                    end

                    task.wait(0.12)
                end
            end
        end
    end

    if attempted > 0 then
        _G.__ScoopHubSilentLog(
            "[AutoBuyPet] Sent sell request for "
            .. attempted
            .. " Normal selected pet(s)."
        )

        addActivity(
            "Sold "
            .. attempted
            .. " Normal pet(s)"
        )

        local soldLines = {}
        for petName, amount in pairs(soldByName) do
            table.insert(
                soldLines,
                petName .. " x" .. amount
            )
        end
        table.sort(soldLines)

        if webhookSellAlerts
            and sellWebhookEnabled
            and sellWebhookUrl ~= "" then

            sendWebhook(
                "PETS SOLD",
                "Selected Normal Backpack pets were sold. Big, Huge, Favorite, and unknown-size pets are protected.",
                15105570,
                {
                    {
                        name = "SOLD",
                        value = table.concat(soldLines, "\n"),
                        inline = false,
                    },
                    {
                        name = "TOTAL SOLD",
                        value = tostring(attempted),
                        inline = true,
                    },
                    {
                        name = "SESSION PETS",
                        value = formatWebhookNumber(petsBought),
                        inline = true,
                    },
                },
                nil,
                sellWebhookUrl,
                true
            )
        end
    end

    petSellBusy = false
    return attempted
end

queuePetAutoSell = function(_reason)
    if not ScoopHubRunAlive()
        or not ScreenGui.Parent
        or not autoSellEnabled then
        return
    end

    PetSellEventPending = true

    if PetSellDrainRunning then
        return
    end

    PetSellDrainRunning = true

    task.defer(function()
        while ScoopHubRunAlive()
            and ScreenGui.Parent
            and autoSellEnabled
            and PetSellEventPending do

            PetSellEventPending = false

            local remaining = getPetSellIntervalRemaining()
            if remaining > 0 then

                PetSellWakeSerial += 1
                local wakeSerial = PetSellWakeSerial

                PetSellDrainRunning = false

                task.delay(remaining, function()
                    if wakeSerial ~= PetSellWakeSerial
                        or not ScoopHubRunAlive()
                        or not autoSellEnabled then
                        return
                    end

                    queuePetAutoSell("batch_ready")
                end)

                return
            end

            local ok = pcall(sellSelectedBackpackPets)
            if not ok then
                petSellBusy = false
            end
        end

        PetSellDrainRunning = false
    end)
end

refreshPetAutoSellSources = function(force)
    if not autoSellEnabled or not ScoopHubRunAlive() then
        disconnectPetAutoSellSources()
        return
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local signature = tostring(backpack)

    if not force and signature == PetSellSourceSignature then

        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") then
                    watchPetSellTool(tool)
                end
            end
        end
        return
    end

    disconnectPetAutoSellSources()
    PetSellSourceSignature = signature

    if not backpack then
        return
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            watchPetSellTool(tool)
        end
    end

    PetSellSourceConnections[#PetSellSourceConnections + 1] =
        backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                watchPetSellTool(child)
            end

            if queuePetAutoSell then
                queuePetAutoSell("backpack_added")
            end
        end)

    PetSellSourceConnections[#PetSellSourceConnections + 1] =
        backpack.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then
                disconnectPetSellToolWatcher(child)
            end

            if queuePetAutoSell then
                queuePetAutoSell("backpack_removed")
            end
        end)
end

local function startPetAutoSellScheduler()
    if not autoSellEnabled then
        return
    end

    refreshPetAutoSellSources(true)
    queuePetAutoSell("enabled")
end

local function stopPetAutoSellScheduler()
    PetSellWakeSerial += 1
    PetSellEventPending = false
    disconnectPetAutoSellSources()
end

    PetAutoSellRuntime.Queue = queuePetAutoSell
    PetAutoSellRuntime.Refresh = refreshPetAutoSellSources
    PetAutoSellRuntime.Start = startPetAutoSellScheduler
    PetAutoSellRuntime.Stop = stopPetAutoSellScheduler

    PetAutoSellRuntime.BumpWake = function()
        PetSellWakeSerial += 1
    end

    PetAutoSellRuntime.HasSources = function()
        return PetSellSourceSignature ~= nil
            or #PetSellSourceConnections > 0
    end

    PetAutoSellRuntime.SafetySeconds = PET_AUTO_SELL_SAFETY_SECONDS
end

local CONFIG_FOLDER = "AutoBuyPet"

local CONFIG_FILE = CONFIG_FOLDER .. "/settings_" .. tostring(LocalPlayer.UserId) .. ".json"
local LEGACY_CONFIG_FILE = CONFIG_FOLDER .. "/settings.json"

function saveSettings()
    if not (writefile and isfolder and makefolder) then return end

    storeCurrentPlayerStats()

    pcall(function()
        if not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
    end)

    local data = {
        selectedPets = {},
        selectedSellPets = {},
        maxPetPrice = maxPetPrice,
        petWalkSpeed = petWalkSpeed,
        petPunchRadius = petPunchRadius,
        fastCFrameMove = fastCFrameMove,
        buyBigPetsPriority = buyBigPetsPriority,
        buyHugePetsPriority = buyHugePetsPriority,
        autoRejoin = autoRejoin,
        cleanupEnabled = cleanupEnabled,
        autoSellEnabled = autoSellEnabled,
        webhookEnabled = webhookEnabled,
        webhookUrl = webhookUrl,
        sellWebhookEnabled = sellWebhookEnabled,
        sellWebhookUrl = sellWebhookUrl,
        webhookPetAlerts = webhookPetAlerts,
        webhookSellAlerts = webhookSellAlerts,
        webhookDisconnectAlerts = webhookDisconnectAlerts,
        sellBatchInterval = sellBatchInterval,
        customJobIds = customJobIds,
        customJobIndex = customJobIndex,
        petProtectEnabled = petProtectEnabled,
        playerStats = playerStats,
        targetPresets = targetPresets,
        dailyDate = dailyDate,
        dailyPetsBought = dailyPetsBought,
    }

    for name, isOn in pairs(selectedPets) do
        if isOn then
            table.insert(data.selectedPets, name)
        end
    end
    for name, isOn in pairs(selectedSellPets) do
        if isOn then
            table.insert(data.selectedSellPets, name)
        end
    end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if ok then
        pcall(writefile, CONFIG_FILE, encoded)
    end
end

local function loadSettings()
    if not (readfile and isfile) then return end

    local exists = false
    local sourceFile = CONFIG_FILE
    pcall(function()
        exists = isfile(CONFIG_FILE)
    end)

    if not exists then
        pcall(function()
            exists = isfile(LEGACY_CONFIG_FILE)
            if exists then sourceFile = LEGACY_CONFIG_FILE end
        end)
    end
    if not exists then return end

    local rawSettings = nil
    local success, data = pcall(function()
        rawSettings = readfile(sourceFile)
        return HttpService:JSONDecode(rawSettings)
    end)
    if not success or type(data) ~= "table" then return end

    if sourceFile == LEGACY_CONFIG_FILE and rawSettings then
        pcall(function()
            if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
            writefile(CONFIG_FILE, rawSettings)
        end)
    end

    local currentPetLookup = {}
    for _, petName in ipairs(AllPets) do
        currentPetLookup[petName] = true
    end

    table.clear(selectedPets)
    if type(data.selectedPets) == "table" then
        for _, name in ipairs(data.selectedPets) do
            if currentPetLookup[name] then
                selectedPets[name] = true
            end
        end
    end
    maxPetPrice = tonumber(data.maxPetPrice) or 50000000
    petWalkSpeed = tonumber(data.petWalkSpeed) or 32
    petPunchRadius = tonumber(data.petPunchRadius) or 16
    fastCFrameMove = data.fastCFrameMove == true
    buyBigPetsPriority = data.buyBigPetsPriority == true
    buyHugePetsPriority = data.buyHugePetsPriority == true
    autoRejoin = data.autoRejoin == true

    cleanupEnabled = false

    autoSellEnabled = data.autoSellEnabled == true
    webhookEnabled = data.webhookEnabled == true
    webhookUrl = type(data.webhookUrl) == "string" and data.webhookUrl or ""
    sellWebhookEnabled = data.sellWebhookEnabled == true
    sellWebhookUrl = type(data.sellWebhookUrl) == "string" and data.sellWebhookUrl or ""
    webhookPetAlerts = data.webhookPetAlerts ~= false
    webhookSellAlerts = data.webhookSellAlerts ~= false
    webhookDisconnectAlerts = data.webhookDisconnectAlerts ~= false
    sellBatchInterval = math.clamp(tonumber(data.sellBatchInterval) or 15, 10, 30)
    if type(data.customJobIds) == "table" then
        customJobIds = data.customJobIds
    end
    table.clear(selectedSellPets)
    if type(data.selectedSellPets) == "table" then
        for _, name in ipairs(data.selectedSellPets) do
            if currentPetLookup[name] then
                selectedSellPets[name] = true
            end
        end
    end
    customJobIndex = math.max(1, tonumber(data.customJobIndex) or 1)
    resumePetProtectOnLoad = data.petProtectEnabled == true
    if type(data.playerStats) == "table" then
        playerStats = data.playerStats
    end
    if type(data.targetPresets) == "table" then
        targetPresets = data.targetPresets
    end
    resetAccountStats()
    local savedStats = playerStats[currentPlayerKey]
    if type(savedStats) == "table" then
        petsBought = tonumber(savedStats.petsBought) or 0
        totalSpent = tonumber(savedStats.spent) or 0
        serverHops = tonumber(savedStats.serverHops) or 0
        autoBuyRuntimeSeconds = math.max(0, tonumber(savedStats.runtimeSeconds) or 0)
        if type(savedStats.history) == "table" then
            petHistory = savedStats.history
        end
        if savedStats.dailyDate == os.date("%Y-%m-%d") then
            dailyDate = savedStats.dailyDate
            dailyPetsBought = math.max(0, tonumber(savedStats.dailyPetsBought) or 0)
        end
    end

    petProtectEnabled = resumePetProtectOnLoad
end

local GuiParent = GP
local ScreenGui = SG
local Body = Auto

for _, child in ipairs(Body:GetChildren()) do
    if child:GetAttribute("ScoopHubAutoBuyEmbedded") == true then
        child:Destroy()
    end
end

local RawNew = New
New = function(className, props, parent)
    local inst = RawNew(className, props, parent)
    if parent == Body then
        inst:SetAttribute("ScoopHubAutoBuyEmbedded", true)
    end
    return inst
end

local function CreatePanel(parent, name, position, size, titleText)
    local Panel = New("Frame", {
        Name = name,
        Position = position,
        Size = size,
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, parent)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, Panel)
    New("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(43, 17, 24)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 8, 12)),
        }),
        Rotation = 20,
    }, Panel)
    New("UIStroke", { Color = Theme.PanelLine, Thickness = 1.1, Transparency = 0.42 }, Panel)
    New("TextLabel", {
        Text = titleText,
        Font = Theme.Font,
        TextSize = 11,
        TextColor3 = Theme.Text,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 6),
        Size = UDim2.new(1, -20, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, Panel)
    return Panel
end

local TabBar = New("Frame", {
    Name = "TabBar",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 8),
    Size = UDim2.new(1, -24, 0, 28),
}, Body)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, TabBar)
New("UIStroke", { Color = Theme.PanelLine, Thickness = 1, Transparency = 0.42 }, TabBar)

local TabUnderline = New("Frame", {
    Name = "TabUnderline",
    BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 1, -2),
    Size = UDim2.new(1 / 4, 0, 0, 2),
    ZIndex = 2,
}, TabBar)

local AutoBuyPage = New("Frame", {
    Name = "AutoBuyPage",
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 1, -48),
}, Body)

local SettingsPage = New("ScrollingFrame", {
    Name = "SettingsPage",
    BackgroundTransparency = 1,
    Visible = false,
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 1, -48),
    CanvasSize = UDim2.new(0, 0, 0, 656),
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Red,
    BorderSizePixel = 0,
}, Body)

local HistoryPage = New("Frame", {
    Name = "HistoryPage",
    BackgroundTransparency = 1,
    Visible = false,
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 1, -48),
}, Body)

local WebhookPage = New("ScrollingFrame", {
    Name = "WebhookPage",
    BackgroundTransparency = 1,
    Visible = false,
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(1, 0, 1, -48),
    CanvasSize = UDim2.new(0, 0, 0, 420),
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Red,
    BorderSizePixel = 0,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, Body)

local updateHistoryUI
local AutoBuyHistoryBuilt = false
local AutoBuyHistoryDirty = true
local AutoBuyHistorySignature = nil
local TabButtons = {}
local function CreateTabButton(name, order)
    local button = New("TextButton", {
        Name = name .. "Tab",
        Text = name,
        Font = Theme.Font,
        TextSize = 11,
        TextColor3 = Theme.TextDim,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new((order - 1) / 4, 0, 0, 0),
        Size = UDim2.new(1 / 4, 0, 1, 0),
    }, TabBar)
    TabButtons[name] = button
    return button
end

local AutoBuyTab = CreateTabButton("DASHBOARD", 1)
local SettingsTab = CreateTabButton("CONFIGS", 2)
local HistoryTab = CreateTabButton("HISTORY", 3)
local WebhookTab = CreateTabButton("WEBHOOK", 4)

local function setActiveTab(tabName)
    AutoBuyPage.Visible = tabName == "DASHBOARD"
    SettingsPage.Visible = tabName == "CONFIGS"
    HistoryPage.Visible = tabName == "HISTORY"
    WebhookPage.Visible = tabName == "WEBHOOK"
    for name, button in pairs(TabButtons) do
        local active = name == tabName
        button.TextColor3 = active and Theme.Red or Theme.TextDim
        button.Font = active and Theme.Font or Theme.FontBody
        button.BackgroundTransparency = 1
    end
    local tabOrder = tabName == "DASHBOARD" and 0
        or (tabName == "CONFIGS" and 1 or (tabName == "HISTORY" and 2 or 3))
    SafeTween(TabUnderline, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(tabOrder / 4, 0, 1, -2),
    })
    if tabName ~= "CONFIGS" then
        local dropdown = Body:FindFirstChild("PetDropdown")
        if dropdown then dropdown.Visible = false end
        local importModal = Body:FindFirstChild("BackupImportModal")
        if importModal then importModal.Visible = false end
        local presetsModal = Body:FindFirstChild("PresetModal")
        if presetsModal then presetsModal.Visible = false end
    end
    if tabName == "HISTORY" and updateHistoryUI then

        updateHistoryUI(true)
    end
end

AutoBuyTab.Activated:Connect(function() setActiveTab("DASHBOARD") end)
SettingsTab.Activated:Connect(function() setActiveTab("CONFIGS") end)
HistoryTab.Activated:Connect(function() setActiveTab("HISTORY") end)
WebhookTab.Activated:Connect(function() setActiveTab("WEBHOOK") end)
setActiveTab("DASHBOARD")

local PetsPanel = CreatePanel(SettingsPage, "PetsPanel", UDim2.new(0, 12, 0, 12), UDim2.new(0, 240, 0, 200), "BUY TARGET PETS")

local SelectPetsButton = New("TextButton", {
    Name = "SelectPetsButton",
    Text = "Select pets...",
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.InputText,
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.new(0, 10, 0, 30),
    Size = UDim2.new(1, -20, 0, 28),
}, PetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SelectPetsButton)
New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, SelectPetsButton)

local RefreshPetsButton = New("TextButton", {
    Name = "RefreshPetsButton",
    Text = "",
    Font = Theme.Font,
    TextSize = 16,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,

    Position = UDim2.new(1, -34, 0, 3),
    Size = UDim2.new(0, 24, 0, 22),
}, PetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, RefreshPetsButton)
New("UIStroke", { Color = Theme.Red, Thickness = 1 }, RefreshPetsButton)

New("ImageLabel", {
    Name = "RefreshIcon",
    Image = "rbxassetid://122032243989747",
    ImageColor3 = Theme.White,
    ScaleType = Enum.ScaleType.Fit,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, 14, 0, 14),
}, RefreshPetsButton)

local SelectedCountLabel = New("TextLabel", {
    Name = "SelectedCountLabel",
    Text = "1 pet selected",
    Font = Theme.FontBody,
    TextSize = 12,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 10, 0, 66),
    Size = UDim2.new(1, -20, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
}, PetsPanel)

local SelectAllPetsButton = New("TextButton", {
    Name = "SelectAllPetsButton",
    Text = "SELECT ALL",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 10, 0, 92),
    Size = UDim2.new(0.5, -14, 0, 24),
}, PetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SelectAllPetsButton)
SelectAllPetsButton.Visible = false

local RemoveAllPetsButton = New("TextButton", {
    Name = "RemoveAllPetsButton",
    Text = "REMOVE ALL",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 4, 0, 92),
    Size = UDim2.new(0.5, -14, 0, 24),
}, PetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, RemoveAllPetsButton)
RemoveAllPetsButton.Visible = false

ManageTargetsButton = New("TextButton", {
    Text = "MANAGE TARGETS", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
    Position = UDim2.new(0, 10, 0, 92), Size = UDim2.new(1, -20, 0, 24),
}, PetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ManageTargetsButton)

New("TextLabel", {
    Name = "SizePriorityTitle",
    Text = "SIZE PRIORITY",
    Font = Theme.Font,
    TextSize = 9,
    TextColor3 = Theme.Red,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 10, 0, 122),
    Size = UDim2.new(1, -20, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, PetsPanel)

local function createSizePriorityRow(name, title, subtitle, yPosition)
    New("TextLabel", {
        Name = name .. "Label",
        Text = title,
        Font = Theme.Font,
        TextSize = 10,
        TextColor3 = Theme.White,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, yPosition),
        Size = UDim2.new(1, -76, 0, 13),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, PetsPanel)
    New("TextLabel", {
        Name = name .. "Hint",
        Text = subtitle,
        Font = Theme.FontBody,
        TextSize = 9,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, yPosition + 12),
        Size = UDim2.new(1, -76, 0, 12),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, PetsPanel)
    local toggle = New("TextButton", {
        Name = name .. "Toggle",
        Text = "",
        BackgroundColor3 = Theme.RedDark,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -58, 0, yPosition + 3),
        Size = UDim2.new(0, 48, 0, 22),
    }, PetsPanel)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, toggle)
    local knob = New("Frame", {
        Name = name .. "Knob",
        BackgroundColor3 = Theme.White,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 16, 0, 16),
    }, toggle)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
    return toggle, knob
end

local BigPetsPriorityToggle, BigPetsPriorityKnob = createSizePriorityRow(
    "BigPetsPriority", "BUY BIG PETS", "Prioritize Big pets when they spawn", 140
)
local HugePetsPriorityToggle, HugePetsPriorityKnob = createSizePriorityRow(
    "HugePetsPriority", "BUY HUGE PETS", "Highest priority when they spawn", 166
)
local rebuildTargetList

local function updatePetSizePriorityUI()
    BigPetsPriorityToggle.BackgroundColor3 = buyBigPetsPriority and Theme.Success or Theme.RedDark
    HugePetsPriorityToggle.BackgroundColor3 = buyHugePetsPriority and Theme.Success or Theme.RedDark
    SafeTween(BigPetsPriorityKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = buyBigPetsPriority and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
    SafeTween(HugePetsPriorityKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = buyHugePetsPriority and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
end

BigPetsPriorityToggle.Activated:Connect(function()
    buyBigPetsPriority = not buyBigPetsPriority
    updatePetSizePriorityUI()
    rebuildTargetList()
end)

HugePetsPriorityToggle.Activated:Connect(function()
    buyHugePetsPriority = not buyHugePetsPriority
    updatePetSizePriorityUI()
    rebuildTargetList()
end)

local RejoinPanel = CreatePanel(
    SettingsPage,
    "RejoinPanel",
    UDim2.new(0, 264, 0, 148),
    UDim2.new(1, -276, 0, 64),
    "SERVER HOP"
)

local RejoinToggle = New("TextButton", {
    Name = "RejoinToggle",
    Text = "SERVER HOP: OFF",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 10, 0, 28),
    Size = UDim2.new(1, -20, 0, 28),
}, RejoinPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, RejoinToggle)

local function updateRejoinUI()
    if autoRejoin then
        RejoinToggle.Text = "AUTO HOP: ON"
        RejoinToggle.BackgroundColor3 = Theme.Success
    else
        RejoinToggle.Text = "AUTO HOP: OFF"
        RejoinToggle.BackgroundColor3 = Theme.RedDark
    end
end

RejoinToggle.Activated:Connect(function()
    autoRejoin = not autoRejoin
    updateRejoinUI()
    saveSettings()

    if autoRejoin then
        Notify("Auto Server Hop", "Will hop after 12s with no selected target pets.", 2)
    else
        Notify("Auto Server Hop", "Disabled", 2)
    end
end)

local SellPetsPanel = CreatePanel(SettingsPage, "SellPetsPanel", UDim2.new(0, 264, 0, 12), UDim2.new(1, -276, 0, 126), "SELL TARGET PETS")

local SelectSellPetsButton = New("TextButton", {
    Name = "SelectSellPetsButton",
    Text = "Select pets...",
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.InputText,
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Position = UDim2.new(0, 10, 0, 30),
    Size = UDim2.new(1, -20, 0, 28),
}, SellPetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SelectSellPetsButton)
New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, SelectSellPetsButton)

local SellSelectedCountLabel = New("TextLabel", {
    Name = "SellSelectedCountLabel",
    Text = "0 pets selected for sell",
    Font = Theme.FontBody,
    TextSize = 12,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 10, 0, 66),
    Size = UDim2.new(1, -132, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SellPetsPanel)

local SelectAllSellPetsButton = New("TextButton", {
    Name = "SelectAllSellPetsButton",
    Text = "SELECT ALL",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 10, 0, 90),
    Size = UDim2.new(0.5, -14, 0, 24),
}, SellPetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SelectAllSellPetsButton)
SelectAllSellPetsButton.Visible = false

local RemoveAllSellPetsButton = New("TextButton", {
    Name = "RemoveAllSellPetsButton",
    Text = "REMOVE ALL",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 4, 0, 90),
    Size = UDim2.new(0.5, -14, 0, 24),
}, SellPetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, RemoveAllSellPetsButton)
RemoveAllSellPetsButton.Visible = false

ManageSellButton = New("TextButton", {
    Text = "MANAGE", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
    Position = UDim2.new(1, -112, 0, 62), Size = UDim2.new(0, 102, 0, 24),
}, SellPetsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ManageSellButton)

local SellToggle = New("TextButton", {
    Name = "SellToggle",
    Text = "",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -58, 0, 90),
    Size = UDim2.new(0, 48, 0, 24),
}, SellPetsPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, SellToggle)
SellToggleKnob = New("Frame", {
    BackgroundColor3 = Theme.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.new(0, 18, 0, 18),
}, SellToggle)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, SellToggleKnob)

New("TextLabel", {
    Text = "AUTO SELL", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 94), Size = UDim2.new(1, -80, 0, 16),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SellPetsPanel)

local PetDropdown = New("Frame", {
    Name = "PetDropdown",
    BackgroundColor3 = Theme.Surface2,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
    ZIndex = 50,
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(0, 220, 0, 240),
}, Body)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, PetDropdown)
New("UIStroke", { Color = Theme.Red, Thickness = 1.5 }, PetDropdown)

local PetSearchBox = New("TextBox", {
    Name = "PetSearchBox",
    PlaceholderText = "Search pets...",
    Text = "",
    Font = Theme.FontBody,
    TextSize = 13,
    TextColor3 = Theme.White,
    PlaceholderColor3 = Color3.fromRGB(160, 160, 165),
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Position = UDim2.new(0, 4, 0, 4),
    Size = UDim2.new(1, -8, 0, 26),
    ZIndex = 51,
}, PetDropdown)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PetSearchBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, PetSearchBox)

local PetDropdownScroll = New("ScrollingFrame", {
    Name = "PetDropdownScroll",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 4, 0, 34),
    Size = UDim2.new(1, -8, 1, -38),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Red,
    ZIndex = 51,
}, PetDropdown)
New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, PetDropdownScroll)
local petDropdownMode = "buy"
local LastPetDropdownSignature = nil
local rebuildSellList
local updateSellUI
local TargetLabel

rebuildTargetList = function()
    targetPetNames = {}
    for name, isOn in pairs(selectedPets) do
        if isOn then
            table.insert(targetPetNames, name)
        end
    end
    table.sort(targetPetNames)

    local displayTargets = table.clone(targetPetNames)
    if buyBigPetsPriority then table.insert(displayTargets, "BIG PETS") end
    if buyHugePetsPriority then table.insert(displayTargets, "HUGE PETS") end
    targetDisplayText = #displayTargets > 0 and formatList(displayTargets) or "Select pets..."

    local count = #targetPetNames
    if count == 0 then
        SelectPetsButton.Text = "Select pets..."
        SelectedCountLabel.Text = "0 pets selected"
    elseif count == 1 then
        SelectPetsButton.Text = targetPetNames[1]
        SelectedCountLabel.Text = "1 pet selected"
    else
        SelectPetsButton.Text = formatList(targetPetNames)
        SelectedCountLabel.Text = count .. " pets selected"
    end
    if TargetLabel then
        TargetLabel.Text = "TARGETS  ●  " .. targetDisplayText
    end
    saveSettings()
end

SelectAllPetsButton.Activated:Connect(function()
    for _, petName in ipairs(AllPets) do
        selectedPets[petName] = true
    end
    rebuildTargetList()
    PetDropdown.Visible = false
end)

RemoveAllPetsButton.Activated:Connect(function()
    table.clear(selectedPets)
    rebuildTargetList()
    PetDropdown.Visible = false
end)

SelectAllSellPetsButton.Activated:Connect(function()
    for _, petName in ipairs(AllPets) do
        selectedSellPets[petName] = true
    end
    rebuildSellList()
    PetDropdown.Visible = false
end)

RemoveAllSellPetsButton.Activated:Connect(function()
    table.clear(selectedSellPets)
    rebuildSellList()
    PetDropdown.Visible = false
end)

SellToggle.Activated:Connect(function()
    if not autoSellEnabled and next(selectedSellPets) == nil then
        Notify("Sell Pet", "Select at least one pet first.", 2)
        return
    end

    autoSellEnabled = not autoSellEnabled

    if autoSellEnabled then
        PetAutoSellRuntime.Start()
    else
        PetAutoSellRuntime.Stop()
    end

    updateSellUI()
    saveSettings()

    Notify(
        "Sell Pet",
        autoSellEnabled
            and "Enabled: Normal selected pets only. Big, Huge, Favorite, and unknown-size pets are protected."
            or "Disabled.",
        3
    )
end)

local function UpdatePetDropdownPosition(button)
    local success = pcall(function()

        local scaleValue = math.max(tonumber(Scale.Scale) or 1, 0.01)
        local basePos = Body.AbsolutePosition
        local baseSize = Body.AbsoluteSize
        button = button or SelectPetsButton
        local btnPos = button.AbsolutePosition
        local btnSize = button.AbsoluteSize

        local pageWidth = baseSize.X / scaleValue
        local buttonX = (btnPos.X - basePos.X) / scaleValue
        local buttonTop = (btnPos.Y - basePos.Y) / scaleValue
        local buttonHeight = btnSize.Y / scaleValue
        local buttonWidth = btnSize.X / scaleValue
        local margin = 4

        local x = math.clamp(
            buttonX,
            margin,
            math.max(margin, pageWidth - buttonWidth - margin)
        )
        local y = buttonTop + buttonHeight + margin

        PetDropdown.Position = UDim2.fromOffset(x, y)
        PetDropdown.Size = UDim2.new(0, buttonWidth, 0, PetDropdown.Size.Y.Offset)
    end)
    if not success then
        PetDropdown.Position = UDim2.new(0, 22, 0, 78)
    end
end

local function BuildPetDropdown(filterText, force)

    local query = string.lower(tostring(filterText or ""))
    local activeSelections = petDropdownMode == "sell" and selectedSellPets or selectedPets
    local signatureParts = { petDropdownMode, query }
    for _, petName in ipairs(AllPets) do
        if activeSelections[petName] then
            signatureParts[#signatureParts + 1] = petName
        end
    end
    local signature = table.concat(signatureParts, "|")

    if not force and LastPetDropdownSignature == signature then
        return
    end
    LastPetDropdownSignature = signature

    for _, child in ipairs(PetDropdownScroll:GetChildren()) do

        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    local filtered = {}
    for _, name in ipairs(AllPets) do
        if query == "" or string.find(string.lower(name), query, 1, true) then
            table.insert(filtered, name)
        end
    end

    local bulkActions = New("Frame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0, ZIndex = 52,
    }, PetDropdownScroll)
    local selectAll = New("TextButton", {
        Text = "SELECT ALL", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.White,
        BackgroundColor3 = Theme.RedDark, BorderSizePixel = 0,
        Size = UDim2.new(0.5, -3, 1, 0), ZIndex = 53,
        AutoButtonColor = false,
    }, bulkActions)
    New("UICorner", { CornerRadius = UDim.new(0, 4) }, selectAll)

    local clearAll = New("TextButton", {
        Text = "CLEAR ALL", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.White,
        BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
        Position = UDim2.new(0.5, 3, 0, 0), Size = UDim2.new(0.5, -3, 1, 0),
        ZIndex = 53, AutoButtonColor = false,
    }, bulkActions)
    New("UICorner", { CornerRadius = UDim.new(0, 4) }, clearAll)

    selectAll.Activated:Connect(function()
        for _, petName in ipairs(AllPets) do
            activeSelections[petName] = true
        end
        if petDropdownMode == "sell" then rebuildSellList() else rebuildTargetList() end
        BuildPetDropdown(PetSearchBox.Text)
    end)

    clearAll.Activated:Connect(function()
        table.clear(activeSelections)
        if petDropdownMode == "sell" then rebuildSellList() else rebuildTargetList() end
        BuildPetDropdown(PetSearchBox.Text)
    end)

    if #filtered == 0 then
        New("TextLabel", {
            Text = "No matches",
            Font = Theme.FontBody,
            TextSize = 14,
            TextColor3 = Theme.TextDim,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 30),
            LayoutOrder = 1,
        }, PetDropdownScroll)
        PetDropdownScroll.CanvasSize = UDim2.new(0, 0, 0, 62)
        return
    end

    for i, petName in ipairs(filtered) do
        local isSelected = activeSelections[petName] == true
        local row = New("TextButton", {
            Name = "PetOption",
            Text = "",
            Font = Theme.Font,
            TextSize = 14,
            BackgroundColor3 = isSelected and AccentSelectedBg() or Theme.Surface2,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            LayoutOrder = i + 1,
            ZIndex = 52,
            AutoButtonColor = false,
        }, PetDropdownScroll)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, row)

        local check = New("TextLabel", {
            Text = isSelected and "\u{2713}" or "",
            Font = Theme.Font,
            TextSize = 14,
            TextColor3 = Theme.Success,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(0, 18, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 53,
        }, row)

        New("TextLabel", {
            Text = petName,
            Font = Theme.Font,
            TextSize = 14,
            TextColor3 = Theme.White,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 28, 0, 0),
            Size = UDim2.new(1, -36, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 53,
        }, row)

        row.MouseEnter:Connect(function()
            if not activeSelections[petName] then
                row.BackgroundColor3 = Theme.RedDark
            end
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundColor3 = activeSelections[petName] and AccentSelectedBg() or Theme.Surface2
        end)

        row.Activated:Connect(function()
            activeSelections[petName] = not activeSelections[petName]
            check.Text = activeSelections[petName] and "\u{2713}" or ""
            row.BackgroundColor3 = activeSelections[petName] and AccentSelectedBg() or Theme.Surface2
            if petDropdownMode == "sell" then
                rebuildSellList()
            else
                rebuildTargetList()
            end
        end)
    end

    PetDropdownScroll.CanvasSize = UDim2.new(0, 0, 0, (#filtered * 32) + 30)
end

local function RefreshOpenPetDropdownTheme()
    if PetDropdown and PetDropdown.Visible then
        BuildPetDropdown(PetSearchBox and PetSearchBox.Text or "", true)
    end
end
_G.__ScoopHubRefreshOpenPetDropdownTheme = RefreshOpenPetDropdownTheme

local function ClosePetDropdown()
    PetDropdown.Visible = false
end

SelectPetsButton.Activated:Connect(function()
    petDropdownMode = "buy"
    PetDropdown.Visible = not PetDropdown.Visible
    if PetDropdown.Visible then
        UpdatePetDropdownPosition()
        PetSearchBox.Text = ""
        BuildPetDropdown("")
    end
end)

RefreshPetsButton.Activated:Connect(function()
    BuildPetDropdown(PetSearchBox.Text, true)
end)

PetSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    BuildPetDropdown(PetSearchBox.Text)
end)

TrackConnection(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    if not PetDropdown.Visible then return end
    task.defer(function()
        local mousePos = UserInputService:GetMouseLocation()
        local hitObjects = GuiService:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
        local clickedInside = false
        for _, obj in ipairs(hitObjects) do
            if obj == PetDropdown or obj:IsDescendantOf(PetDropdown)
                or obj == SelectPetsButton or obj == SelectSellPetsButton or obj == RefreshPetsButton
                or obj == ManageTargetsButton or obj == ManageSellButton then
                clickedInside = true
                break
            end
        end
        if not clickedInside then
            ClosePetDropdown()
        end
    end)
end))

SettingsPanel = CreatePanel(SettingsPage, "SettingsPanel", UDim2.new(0, 12, 0, 224), UDim2.new(1, -24, 0, 206), "BUY & MOVEMENT")

New("TextLabel", {
    Text = "Max Price",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 28),
    Size = UDim2.new(1/3, -16, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local PriceBox = New("TextBox", {
    Name = "PriceBox",
    Text = "50000000",
    PlaceholderText = "50000000",
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 46),
    Size = UDim2.new(1/3, -16, 0, 28),
    ClearTextOnFocus = false,
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PriceBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, PriceBox)

PriceBox.FocusLost:Connect(function()
    local num = tonumber(PriceBox.Text)
    if num then
        maxPetPrice = num
        saveSettings()
    else
        PriceBox.Text = tostring(maxPetPrice)
    end
end)

New("TextLabel", {
    Text = "Walk Speed (28-40)",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(1/3, 4, 0, 28),
    Size = UDim2.new(1/3, -16, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local SpeedBox = New("TextBox", {
    Name = "SpeedBox",
    Text = "32",
    PlaceholderText = "32",
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    Position = UDim2.new(1/3, 4, 0, 46),
    Size = UDim2.new(1/3, -16, 0, 28),
    ClearTextOnFocus = false,
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SpeedBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, SpeedBox)

SpeedBox.FocusLost:Connect(function()
    local num = tonumber(SpeedBox.Text)
    if num then
        petWalkSpeed = math.clamp(num, 16, 100)
        SpeedBox.Text = tostring(petWalkSpeed)
        saveSettings()
    else
        SpeedBox.Text = tostring(petWalkSpeed)
    end
end)

New("TextLabel", {
    Text = "Punch Radius",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(2/3, -4, 0, 28),
    Size = UDim2.new(1/3, -8, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local RadiusBox = New("TextBox", {
    Name = "RadiusBox",
    Text = "16",
    PlaceholderText = "16",
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    Position = UDim2.new(2/3, -4, 0, 46),
    Size = UDim2.new(1/3, -8, 0, 28),
    ClearTextOnFocus = false,
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, RadiusBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, RadiusBox)

RadiusBox.FocusLost:Connect(function()
    local num = tonumber(RadiusBox.Text)
    if num then
        petPunchRadius = math.clamp(num, 8, 40)
        RadiusBox.Text = tostring(petPunchRadius)
        saveSettings()
    else
        RadiusBox.Text = tostring(petPunchRadius)
    end
end)

SelectSellPetsButton.Activated:Connect(function()
    petDropdownMode = "sell"
    PetDropdown.Visible = not PetDropdown.Visible
    if PetDropdown.Visible then
        UpdatePetDropdownPosition(SelectSellPetsButton)
        PetSearchBox.Text = ""
        BuildPetDropdown("")
    end
end)

ManageTargetsButton.Activated:Connect(function()
    petDropdownMode = "buy"
    PetDropdown.Visible = true
    UpdatePetDropdownPosition(SelectPetsButton)
    PetSearchBox.Text = ""
    BuildPetDropdown("")
end)

ManageSellButton.Activated:Connect(function()
    petDropdownMode = "sell"
    PetDropdown.Visible = true
    UpdatePetDropdownPosition(SelectSellPetsButton)
    PetSearchBox.Text = ""
    BuildPetDropdown("")
end)

New("TextLabel", {
    Text = "Enable Cleanup",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 88),
    Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

New("TextLabel", {
    Text = "Remove plants, trees, and effects for better FPS",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 103),
    Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local CleanupToggle = New("TextButton", {
    Name = "CleanupToggle",
    Text = "",
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -62, 0, 91),
    Size = UDim2.new(0, 48, 0, 24),
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, CleanupToggle)
local CleanupKnob = New("Frame", {
    Name = "CleanupKnob",
    BackgroundColor3 = Theme.White,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0),
    Size = UDim2.new(0, 18, 0, 18),
}, CleanupToggle)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, CleanupKnob)

local function updateCleanupUI()
    CleanupToggle.BackgroundColor3 = cleanupEnabled and Theme.Success or Theme.RedDark
    SafeTween(CleanupKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = cleanupEnabled and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
end

CleanupToggle.Activated:Connect(function()
    setCleanupEnabled(not cleanupEnabled)
    updateCleanupUI()
    saveSettings()
    Notify("Cleanup", cleanupEnabled and "Cleanup enabled. Your garden stays visible with textures removed." or "Cleanup disabled. A rejoin restores removed visuals.", 2)
end)

New("TextLabel", {
    Text = "Fast CFrame Move",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 124),
    Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

New("TextLabel", {
    Text = "Instantly move beside selected WildPets",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 139),
    Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local CFrameMoveToggle = New("TextButton", {
    Name = "CFrameMoveToggle",
    Text = "",
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -62, 0, 127),
    Size = UDim2.new(0, 48, 0, 24),
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, CFrameMoveToggle)
local CFrameMoveKnob = New("Frame", {
    Name = "CFrameMoveKnob",
    BackgroundColor3 = Theme.White,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0),
    Size = UDim2.new(0, 18, 0, 18),
}, CFrameMoveToggle)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, CFrameMoveKnob)

local function updateCFrameMoveUI()
    CFrameMoveToggle.BackgroundColor3 = fastCFrameMove and Theme.Success or Theme.RedDark
    SafeTween(CFrameMoveKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = fastCFrameMove and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
end

CFrameMoveToggle.Activated:Connect(function()
    fastCFrameMove = not fastCFrameMove
    updateCFrameMoveUI()
    saveSettings()
    Notify("Movement", fastCFrameMove and "Fast CFrame movement enabled." or "Normal walking enabled.", 2)
end)

New("TextLabel", {
    Text = "SETTINGS BACKUP",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 162),
    Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, SettingsPanel)

local ExportSettingsButton = New("TextButton", {
    Name = "ExportSettingsButton",
    Text = "EXPORT",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 180),
    Size = UDim2.new(1/3, -16, 0, 22),
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ExportSettingsButton)

local ImportSettingsButton = New("TextButton", {
    Name = "ImportSettingsButton",
    Text = "IMPORT",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(1/3, 4, 0, 180),
    Size = UDim2.new(1/3, -16, 0, 22),
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ImportSettingsButton)

PresetsButton = New("TextButton", {
    Text = "PRESETS", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
    Position = UDim2.new(2/3, -4, 0, 180), Size = UDim2.new(1/3, -8, 0, 22),
}, SettingsPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PresetsButton)

local BackupImportModal = New("Frame", {
    Name = "BackupImportModal",
    Visible = false,
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 18, 0, 74),
    Size = UDim2.new(1, -36, 0, 290),
    ZIndex = 80,
}, Body)
New("UICorner", { CornerRadius = UDim.new(0, 7) }, BackupImportModal)
New("UIStroke", { Color = Theme.Red, Thickness = 1.4 }, BackupImportModal)

New("TextLabel", {
    Text = "IMPORT SETTINGS BACKUP",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.White,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 10),
    Size = UDim2.new(1, -24, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 81,
}, BackupImportModal)

New("TextLabel", {
    Text = "Paste a backup created with Export. This replaces the current saved settings.",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 32),
    Size = UDim2.new(1, -24, 0, 30),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 81,
}, BackupImportModal)

local BackupImportBox = New("TextBox", {
    Name = "BackupImportBox",
    Text = "",
    PlaceholderText = "Paste settings JSON here...",
    MultiLine = true,
    ClearTextOnFocus = false,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 68),
    Size = UDim2.new(1, -24, 0, 160),
    ZIndex = 81,
}, BackupImportModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, BackupImportBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, BackupImportBox)

local ConfirmImportButton = New("TextButton", {
    Text = "IMPORT BACKUP",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -34),
    Size = UDim2.new(0.5, -16, 0, 22),
    ZIndex = 81,
}, BackupImportModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ConfirmImportButton)

local CancelImportButton = New("TextButton", {
    Text = "CANCEL",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 4, 1, -34),
    Size = UDim2.new(0.5, -16, 0, 22),
    ZIndex = 81,
}, BackupImportModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, CancelImportButton)

PresetModal = New("Frame", {
    Name = "PresetModal", Visible = false, BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Position = UDim2.new(0, 18, 0, 74), Size = UDim2.new(1, -36, 0, 290), ZIndex = 84,
}, Body)
New("UICorner", { CornerRadius = UDim.new(0, 7) }, PresetModal)
New("UIStroke", { Color = Theme.Red, Thickness = 1.4 }, PresetModal)
New("TextLabel", {
    Text = "TARGET PRESETS", Font = Theme.Font, TextSize = 13, TextColor3 = Theme.White,
    BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -56, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 85,
}, PresetModal)
PresetCloseButton = New("TextButton", {
    Text = "X", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.White, BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0, Position = UDim2.new(1, -34, 0, 8), Size = UDim2.new(0, 22, 0, 22), ZIndex = 85,
}, PresetModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PresetCloseButton)
New("TextLabel", {
    Text = "Save the current selected target pets under a name, then load it anytime.",
    Font = Theme.FontBody, TextSize = 11, TextColor3 = Theme.Muted, BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 34), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 85,
}, PresetModal)
PresetNameBox = New("TextBox", {
    Text = "", PlaceholderText = "Preset name...", Font = Theme.FontBody, TextSize = 12,
    TextColor3 = Theme.InputText, PlaceholderColor3 = Theme.Muted, BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0, ClearTextOnFocus = false, Position = UDim2.new(0, 12, 0, 60),
    Size = UDim2.new(1, -118, 0, 26), ZIndex = 85,
}, PresetModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PresetNameBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8) }, PresetNameBox)
SavePresetButton = New("TextButton", {
    Text = "SAVE", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.White, BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0, Position = UDim2.new(1, -98, 0, 60), Size = UDim2.new(0, 86, 0, 26), ZIndex = 85,
}, PresetModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SavePresetButton)
PresetList = New("ScrollingFrame", {
    Name = "PresetList", BackgroundColor3 = Theme.Surface2, BackgroundTransparency = 0.18, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 96), Size = UDim2.new(1, -24, 1, -108), CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Red, ZIndex = 85,
}, PresetModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PresetList)
New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, PresetList)
New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.Name }, PresetList)

function rebuildPresetList()
    for _, child in ipairs(PresetList:GetChildren()) do
        if child.Name == "PresetRow" or child.Name == "EmptyPreset" then
            child:Destroy()
        end
    end
    local names = {}
    for presetName in pairs(targetPresets) do
        table.insert(names, presetName)
    end
    table.sort(names)
    if #names == 0 then
        New("TextLabel", {
            Name = "EmptyPreset", Text = "No presets saved yet.", Font = Theme.FontBody, TextSize = 11,
            TextColor3 = Theme.Muted, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30),
            TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 86,
        }, PresetList)
        return
    end
    for index, presetName in ipairs(names) do
        local savedTargets = targetPresets[presetName] or {}
        local row = New("Frame", {
            Name = "PresetRow", LayoutOrder = index, BackgroundColor3 = Theme.Surface3, BackgroundTransparency = 0.12,
            BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), ZIndex = 86,
        }, PresetList)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, row)
        New("TextLabel", {
            Text = presetName .. "  ●  " .. #savedTargets .. " pet(s)", Font = Theme.FontBody, TextSize = 11,
            TextColor3 = Theme.White, BackgroundTransparency = 1, Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -102, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 87,
        }, row)
        local loadButton = New("TextButton", {
            Text = "LOAD", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White, BackgroundColor3 = Theme.RedDark,
            BorderSizePixel = 0, Position = UDim2.new(1, -88, 0, 4), Size = UDim2.new(0, 52, 0, 22), ZIndex = 87,
        }, row)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, loadButton)
        local deleteButton = New("TextButton", {
            Text = "X", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.White, BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0, Position = UDim2.new(1, -30, 0, 4), Size = UDim2.new(0, 22, 0, 22), ZIndex = 87,
        }, row)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, deleteButton)
        loadButton.Activated:Connect(function()
            table.clear(selectedPets)
            local allowed = {}
            for _, petName in ipairs(AllPets) do
                allowed[petName] = true
            end
            for _, petName in ipairs(savedTargets) do
                if allowed[petName] then selectedPets[petName] = true end
            end
            rebuildTargetList()
            saveSettings()
            addActivity("Loaded preset " .. presetName)
            Notify("Presets", "Loaded " .. presetName, 2)
            PresetModal.Visible = false
        end)
        deleteButton.Activated:Connect(function()
            targetPresets[presetName] = nil
            saveSettings()
            rebuildPresetList()
        end)
    end
end

PresetsButton.Activated:Connect(function()
    PresetNameBox.Text = ""
    PresetModal.Visible = true
    rebuildPresetList()
end)
PresetCloseButton.Activated:Connect(function() PresetModal.Visible = false end)
SavePresetButton.Activated:Connect(function()
    local presetName = tostring(PresetNameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if presetName == "" then
        Notify("Presets", "Enter a preset name first.", 2)
        return
    end
    local savedTargets = {}
    for petName, enabled in pairs(selectedPets) do
        if enabled then table.insert(savedTargets, petName) end
    end
    table.sort(savedTargets)
    if #savedTargets == 0 then
        Notify("Presets", "Select at least one target pet first.", 2)
        return
    end
    targetPresets[presetName] = savedTargets
    saveSettings()
    rebuildPresetList()
    addActivity("Saved preset " .. presetName)
    Notify("Presets", "Saved " .. presetName, 2)
end)

JobIdPanel = CreatePanel(SettingsPage, "JobIdPanel", UDim2.new(0, 12, 0, 442), UDim2.new(1, -24, 0, 200), "SERVER HOP ROTATION")

New("TextLabel", {
    Text = "Add Job IDs to hop through them in order. Leave empty for random 1-6 player servers.",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 27),
    Size = UDim2.new(1, -24, 0, 18),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, JobIdPanel)

local JobIdInput = New("TextBox", {
    Name = "JobIdInput",
    Text = "",
    PlaceholderText = "Paste a server Job ID...",
    Font = Theme.FontBody,
    TextSize = 12,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Position = UDim2.new(0, 12, 0, 50),
    Size = UDim2.new(1, -112, 0, 28),
}, JobIdPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, JobIdInput)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, JobIdInput)

local AddJobIdButton = New("TextButton", {
    Text = "ADD ID",
    Font = Theme.Font,
    TextSize = 11,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -92, 0, 50),
    Size = UDim2.new(0, 80, 0, 28),
}, JobIdPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, AddJobIdButton)

local JobIdsLabel = New("TextLabel", {
    Name = "JobIdsLabel",
    Visible = false,
    Text = "No saved Job IDs - random hopping is active.",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 84),
    Size = UDim2.new(1, -112, 0, 42),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, JobIdPanel)

local ClearJobIdsButton = New("TextButton", {
    Text = "CLEAR ALL",
    Font = Theme.Font,
    TextSize = 10,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -92, 1, -36),
    Size = UDim2.new(0, 80, 0, 24),
}, JobIdPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ClearJobIdsButton)

local JobIdList = New("ScrollingFrame", {
    Name = "JobIdList",
    BackgroundColor3 = Theme.Surface2,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 86),
    Size = UDim2.new(1, -24, 1, -130),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.Red,
}, JobIdPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, JobIdList)
New("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 5),
    PaddingRight = UDim.new(0, 5),
}, JobIdList)
New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, JobIdList)

local JobRouteLabel = New("TextLabel", {
    Name = "JobRouteLabel",
    Text = "Random 1-6 player servers are active.",
    Font = Theme.FontBody,
    TextSize = 10,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 1, -34),
    Size = UDim2.new(1, -112, 0, 22),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, JobIdPanel)

local function updateJobIdsUI()
    if #customJobIds == 0 then
        JobIdsLabel.Text = "No saved Job IDs - random hopping is active."
        return
    end
    local lines = {}
    for index, jobId in ipairs(customJobIds) do
        local marker = index == customJobIndex and "Next: " or "      "
        table.insert(lines, marker .. index .. ". " .. tostring(jobId))
    end
    JobIdsLabel.Text = table.concat(lines, "\n")
end

local function rebuildJobIdList()
    for _, child in ipairs(JobIdList:GetChildren()) do
        if child.Name == "JobIdRow" or child.Name == "EmptyJobIds" then
            child:Destroy()
        end
    end

    if #customJobIds == 0 then
        JobRouteLabel.Text = "Random 1-6 player servers are active."
        New("TextLabel", {
            Name = "EmptyJobIds",
            Text = "No saved Job IDs. Add one above to use a custom rotation.",
            Font = Theme.FontBody,
            TextSize = 11,
            TextColor3 = Theme.Muted,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 32),
            TextXAlignment = Enum.TextXAlignment.Center,
        }, JobIdList)
        return
    end

    JobRouteLabel.Text = #customJobIds .. " saved server" .. (#customJobIds == 1 and " - rotates in order." or "s - rotates in order.")
    for index, jobId in ipairs(customJobIds) do
        local row = New("Frame", {
            Name = "JobIdRow",
            LayoutOrder = index,
            BackgroundColor3 = index == customJobIndex and Color3.fromRGB(62, 23, 31) or Theme.Surface3,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 28),
        }, JobIdList)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, row)
        New("TextLabel", {
            Text = (index == customJobIndex and "NEXT  " or "") .. tostring(jobId),
            Font = Theme.FontBody,
            TextSize = 11,
            TextColor3 = index == customJobIndex and Theme.White or Theme.Muted,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -42, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
        local removeButton = New("TextButton", {
            Text = "X",
            Font = Theme.Font,
            TextSize = 12,
            TextColor3 = Theme.Text,
            BackgroundColor3 = Theme.RedDark,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -26, 0, 3),
            Size = UDim2.new(0, 22, 0, 22),
        }, row)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, removeButton)
        removeButton.Activated:Connect(function()
            table.remove(customJobIds, index)
            customJobIndex = #customJobIds > 0 and math.clamp(customJobIndex, 1, #customJobIds) or 1
            rebuildJobIdList()
            saveSettings()
        end)
    end
end

local function addJobId()
    local jobId = tostring(JobIdInput.Text or ""):gsub("%s+", "")
    if jobId == "" then
        Notify("Server Hop", "Paste a Job ID first.", 2)
        return
    end
    for _, existingId in ipairs(customJobIds) do
        if existingId == jobId then
            Notify("Server Hop", "That Job ID is already in the rotation.", 2)
            return
        end
    end
    table.insert(customJobIds, jobId)
    JobIdInput.Text = ""
    updateJobIdsUI()
    rebuildJobIdList()
    saveSettings()
end

rebuildSellList = function()
    local names = {}
    for name, isOn in pairs(selectedSellPets) do
        if isOn then
            table.insert(names, name)
        end
    end
    table.sort(names)

    local count = #names
    if count == 0 then
        SelectSellPetsButton.Text = "Select pets..."
        SellSelectedCountLabel.Text = "0 pets selected for sell"
    elseif count == 1 then
        SelectSellPetsButton.Text = names[1]
        SellSelectedCountLabel.Text = "1 pet selected for sell"
    else
        SelectSellPetsButton.Text = formatList(names)
        SellSelectedCountLabel.Text = count .. " pets selected for sell"
    end

    saveSettings()

    if autoSellEnabled and PetAutoSellRuntime.Queue then
        PetAutoSellRuntime.Queue("selection_changed")
    end
end

updateSellUI = function()
    SellToggle.BackgroundColor3 = autoSellEnabled and Theme.Success or Theme.RedDark
    SafeTween(SellToggleKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = autoSellEnabled and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
end

AddJobIdButton.Activated:Connect(addJobId)
JobIdInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then addJobId() end
end)
ClearJobIdsButton.Activated:Connect(function()
    table.clear(customJobIds)
    customJobIndex = 1
    updateJobIdsUI()
    rebuildJobIdList()
    saveSettings()
    Notify("Server Hop", "Custom Job ID rotation cleared.", 2)
end)

local function getNextCustomJobId()
    if #customJobIds == 0 then return nil end
    customJobIndex = math.clamp(customJobIndex, 1, #customJobIds)
    for _ = 1, #customJobIds do
        local jobId = customJobIds[customJobIndex]
        customJobIndex = (customJobIndex % #customJobIds) + 1
        if jobId ~= game.JobId then
            updateJobIdsUI()
            rebuildJobIdList()
            return jobId
        end
    end
    return nil
end

DashboardProfilePanel = CreatePanel(AutoBuyPage, "DashboardProfilePanel", UDim2.new(0, 12, 0, 12), UDim2.new(1, -24, 0, 88), "PLAYER PROFILE")

DashboardAvatar = New("ImageLabel", {
    Name = "DashboardAvatar",
    Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=100&h=100",
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 29),
    Size = UDim2.new(0, 44, 0, 44),
    ScaleType = Enum.ScaleType.Crop,
}, DashboardProfilePanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, DashboardAvatar)
New("UIStroke", { Color = Theme.PanelLine, Thickness = 1, Transparency = 0.38 }, DashboardAvatar)

DashboardDisplayNameLabel = New("TextLabel", {
    Text = LocalPlayer.DisplayName,
    Font = Theme.Font,
    TextSize = 14,
    TextColor3 = Theme.White,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 66, 0, 31),
    Size = UDim2.new(0.52, -66, 0, 18),
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextXAlignment = Enum.TextXAlignment.Left,
}, DashboardProfilePanel)

New("TextLabel", {
    Text = "@" .. LocalPlayer.Name,
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 66, 0, 51),
    Size = UDim2.new(0.52, -66, 0, 16),
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextXAlignment = Enum.TextXAlignment.Left,
}, DashboardProfilePanel)

New("TextLabel", {
    Text = "USER ID",
    Font = Theme.Font,
    TextSize = 9,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0.58, 0, 0, 31),
    Size = UDim2.new(0.4, -12, 0, 12),
    TextXAlignment = Enum.TextXAlignment.Left,
}, DashboardProfilePanel)

New("TextLabel", {
    Text = tostring(LocalPlayer.UserId),
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.Text,
    BackgroundTransparency = 1,
    Position = UDim2.new(0.58, 0, 0, 43),
    Size = UDim2.new(0.4, -12, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, DashboardProfilePanel)

DashboardProfileStatusLabel = New("TextLabel", {
    Text = "AUTO BUY: STOPPED",
    Font = Theme.Font,
    TextSize = 10,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0.58, 0, 0, 59),
    Size = UDim2.new(0.4, -12, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, DashboardProfilePanel)

StatusPanel = CreatePanel(AutoBuyPage, "StatusPanel", UDim2.new(0, 12, 0, 112), UDim2.new(1, -24, 0, 236), "SESSION STATUS")

SessionNameLabel = New("TextLabel", {
    Name = "SessionNameLabel",
    Text = LocalPlayer.Name .. " ● 00:00",
    Font = Theme.FontBody,
    TextSize = 10,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 20),
    Size = UDim2.new(0.5, -16, 0, 12),
    TextXAlignment = Enum.TextXAlignment.Left,
}, StatusPanel)
SessionNameLabel.Visible = false

local LiveChip = New("Frame", {
    Name = "LiveChip",
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -98, 0, 7),
    Size = UDim2.new(0, 86, 0, 18),
}, StatusPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, LiveChip)
local LiveChipLabel = New("TextLabel", {
    Name = "LiveChipLabel",
    Text = "● STOPPED",
    Font = Theme.Font,
    TextSize = 9,
    TextColor3 = Theme.White,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Center,
}, LiveChip)

local function CreateStatusCard(name, position, labelText, valueColor)
    local isLarge = name == "ElapsedCard" or name == "SessionPetsCard"
    local card = New("Frame", {
        Name = name,
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Position = position,
        Size = UDim2.new(0.5, -16, 0, isLarge and 52 or 30),
    }, StatusPanel)
    New("UICorner", { CornerRadius = UDim.new(0, 5) }, card)
    New("UIStroke", { Color = Theme.PanelLine, Thickness = 0.8, Transparency = 0.62 }, card)
    New("TextLabel", {
        Text = labelText,
        Font = Theme.Font,
        TextSize = 9,
        TextColor3 = Theme.Muted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, isLarge and 7 or 3),
        Size = UDim2.new(1, -16, 0, isLarge and 10 or 8),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    return New("TextLabel", {
        Name = "Value",
        Text = "--",
        Font = Theme.Font,
        TextSize = isLarge and 21 or 13,
        TextColor3 = valueColor,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, isLarge and 21 or 12),
        Size = UDim2.new(1, -16, 0, isLarge and 25 or 16),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
end

ElapsedLabel = CreateStatusCard("ElapsedCard", UDim2.new(0, 12, 0, 36), "ELAPSED", Theme.White)
local BoughtLabel = CreateStatusCard("SessionPetsCard", UDim2.new(0.5, 4, 0, 36), "SESSION PETS", Theme.Success)
local ShecklesLabel = CreateStatusCard("ShecklesCard", UDim2.new(0, 12, 0, 92), "SHECKLES", Color3.fromRGB(123, 222, 151))
SpentLabel = CreateStatusCard("SpentCard", UDim2.new(0.5, 4, 0, 92), "SPENT", Color3.fromRGB(255, 166, 112))
ServerHopsLabel = CreateStatusCard("ServerHopsCard", UDim2.new(0, 12, 0, 126), "SERVER HOPS", Theme.Text)

TargetLabel = New("TextLabel", {
    Name = "TargetLabel",
    Text = "TARGETS  ●  " .. targetDisplayText,
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 160),
    Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, StatusPanel)

ActivityLabel = New("TextButton", {
    Name = "ActivityLabel",
    Text = "ACTIVITY  ●  Waiting for activity",
    Font = Theme.FontBody,
    TextSize = 10,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 116),
    Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    AutoButtonColor = false,
}, StatusPanel)
ActivityLabel.Visible = false

local ToggleButton = New("TextButton", {
    Name = "ToggleButton",
    Text = "ENABLE AUTO BUY PET",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0,
    Position = UDim2.new(0.5, 4, 1, -48),
    Size = UDim2.new(0.5, -16, 0, 34),
}, StatusPanel)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, ToggleButton)
New("UIStroke", { Color = Color3.fromRGB(255, 150, 157), Thickness = 1, Transparency = 0.55 }, ToggleButton)

ForceHopButton = New("TextButton", {
    Name = "ForceHopButton",
    Text = "FORCE HOP",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -48),
    Size = UDim2.new(0.5, -16, 0, 34),
}, StatusPanel)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, ForceHopButton)
New("UIStroke", { Color = Theme.PanelLine, Thickness = 1, Transparency = 0.45 }, ForceHopButton)

ActivityModal = New("Frame", {
    Name = "ActivityModal", Visible = false, BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Position = UDim2.new(0, 16, 0, 28), Size = UDim2.new(1, -32, 0, 184), ZIndex = 70,
}, AutoBuyPage)
New("UICorner", { CornerRadius = UDim.new(0, 7) }, ActivityModal)
New("UIStroke", { Color = Theme.Red, Thickness = 1.2 }, ActivityModal)
New("TextLabel", { Text = "RECENT ACTIVITY", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.White, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -52, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }, ActivityModal)
ActivityCloseButton = New("TextButton", { Text = "X", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.White, BackgroundColor3 = Theme.RedDark, BorderSizePixel = 0, Position = UDim2.new(1, -34, 0, 8), Size = UDim2.new(0, 22, 0, 22), ZIndex = 71 }, ActivityModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ActivityCloseButton)
ActivityList = New("ScrollingFrame", { BackgroundColor3 = Theme.Surface2, BackgroundTransparency = 0.18, BorderSizePixel = 0, Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 1, -50), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Red, ZIndex = 71 }, ActivityModal)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, ActivityList)
New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, ActivityList)
New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ActivityList)

function rebuildActivityFeed()
    for _, child in ipairs(ActivityList:GetChildren()) do
        if child.Name == "ActivityRow" or child.Name == "ActivityEmpty" then child:Destroy() end
    end
    if #activityFeed == 0 then
        New("TextLabel", { Name = "ActivityEmpty", Text = "No activity yet.", Font = Theme.FontBody, TextSize = 11, TextColor3 = Theme.Muted, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 72 }, ActivityList)
        return
    end
    for index, message in ipairs(activityFeed) do
        New("TextLabel", { Name = "ActivityRow", LayoutOrder = index, Text = message, Font = Theme.FontBody, TextSize = 11, TextColor3 = Theme.White, BackgroundColor3 = Theme.Surface3, BackgroundTransparency = 0.12, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 25), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 72 }, ActivityList)
    end
end

ActivityLabel.Activated:Connect(function()
    ActivityModal.Visible = true
    rebuildActivityFeed()
end)
ActivityCloseButton.Activated:Connect(function() ActivityModal.Visible = false end)

do
HistoryPanel = CreatePanel(HistoryPage, "HistoryPanel", UDim2.new(0, 12, 0, 12), UDim2.new(1, -24, 1, -24), "PET HISTORY")

local HistoryFooterDivider = New("Frame", {
    Name = "HistoryFooterDivider",
    BackgroundColor3 = Theme.PanelLine,
    BackgroundTransparency = 0.62,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 1, -39),
    Size = UDim2.new(1, -24, 0, 1),
}, HistoryPanel)

local HistoryTotalLabel = New("TextLabel", {
    Name = "HistoryTotalLabel",
    Text = "Total pets: 0",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.Success,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 1, -34),
    Size = UDim2.new(0.5, -12, 0, 22),
    TextXAlignment = Enum.TextXAlignment.Left,
}, HistoryPanel)

HistoryDailyLabel = New("TextLabel", {
    Name = "HistoryDailyLabel",
    Text = "Today: 0 pets",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0.5, 0, 1, -34),
    Size = UDim2.new(0.5, -12, 0, 22),
    TextXAlignment = Enum.TextXAlignment.Right,
}, HistoryPanel)

HistoryColumns = New("Frame", {
    Name = "HistoryColumns",
    BackgroundColor3 = Theme.Surface3,
    BackgroundTransparency = 0.28,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 28),
    Size = UDim2.new(1, -24, 0, 20),
}, HistoryPanel)
New("UICorner", { CornerRadius = UDim.new(0, 4) }, HistoryColumns)

local function CreateHistoryColumn(text, position, size, alignment)
    New("TextLabel", {
        Text = text,
        Font = Theme.Font,
        TextSize = 10,
        TextColor3 = Theme.TextDim,
        BackgroundTransparency = 1,
        Position = position,
        Size = size,
        TextXAlignment = alignment,
    }, HistoryColumns)
end
CreateHistoryColumn("PET NAME", UDim2.new(0, 10, 0, 0), UDim2.new(0.55, -10, 1, 0), Enum.TextXAlignment.Left)
CreateHistoryColumn("AMOUNT", UDim2.new(0.55, 0, 0, 0), UDim2.new(0.2, 0, 1, 0), Enum.TextXAlignment.Center)
CreateHistoryColumn("RARITY", UDim2.new(0.75, 0, 0, 0), UDim2.new(0.25, -10, 1, 0), Enum.TextXAlignment.Right)

local HistoryScroll = New("ScrollingFrame", {
    Name = "HistoryScroll",
    BackgroundColor3 = Theme.Surface2,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 52),
    Size = UDim2.new(1, -24, 1, -96),
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Red,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, HistoryPanel)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, HistoryScroll)
New("UIPadding", {
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6),
}, HistoryScroll)
New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, HistoryScroll)

local WIKI_PET_PAGE_NAMES = {
    GoldenDragonfly = "Golden Dragonfly",
    BlackDragon = "Black Dragon",
    IceSerpent = "Ice Serpent",
    ShadowDragon = "Shadow Dragon",
}
local petIconCache = {}
local petIconLoading = {}
local petIconFolder = CONFIG_FOLDER .. "/pet_icons"
local customAsset = getcustomasset or getsynasset

local function getInGamePetIcon(petName)
    for _, container in ipairs({ LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }) do
        if container then
            local petTool = container:FindFirstChild(petName)
            if petTool and petTool:IsA("Tool") and petTool.TextureId ~= "" then
                return petTool.TextureId
            end
        end
    end
    return nil
end

local function setPetIcon(petName, imageLabel)
    local inGameIcon = getInGamePetIcon(petName)
    if inGameIcon then
        imageLabel.Image = inGameIcon
        return
    end
    if petIconCache[petName] then
        imageLabel.Image = petIconCache[petName]
        return
    end
    if petIconLoading[petName] or type(customAsset) ~= "function" then return end
    petIconLoading[petName] = true

    task.spawn(function()
        local safeName = tostring(petName):gsub("[^%w]", "_")
        local iconFile = petIconFolder .. "/" .. safeName .. ".png"
        local iconAsset = nil

        pcall(function()
            if isfolder and makefolder and not isfolder(petIconFolder) then
                makefolder(petIconFolder)
            end
            if isfile and isfile(iconFile) then
                iconAsset = customAsset(iconFile)
                return
            end

            local pageName = WIKI_PET_PAGE_NAMES[petName] or petName
            local apiUrl = "https://growagarden2.fandom.com/api.php?action=query&format=json&prop=pageimages&piprop=thumbnail&pithumbsize=128&titles="
                .. HttpService:UrlEncode(pageName)
            local pageData = HttpService:JSONDecode(game:HttpGet(apiUrl))
            local pages = pageData and pageData.query and pageData.query.pages
            local page = pages and next(pages) and pages[next(pages)]
            local imageUrl = page and page.thumbnail and page.thumbnail.source
            if imageUrl then
                writefile(iconFile, game:HttpGet(imageUrl))
                iconAsset = customAsset(iconFile)
            end
        end)

        petIconLoading[petName] = nil
        if iconAsset then
            petIconCache[petName] = iconAsset
            if imageLabel and imageLabel.Parent then
                imageLabel.Image = iconAsset
            end
        end
    end)
end

local function getAutoBuyHistorySignature()
    local parts = {
        tostring(petsBought),
        tostring(dailyPetsBought),
        tostring(dailyDate or ""),
    }

    local keys = {}
    for petName, count in pairs(petHistory) do
        if tonumber(count) and tonumber(count) > 0 then
            keys[#keys + 1] = tostring(petName)
        end
    end
    table.sort(keys)

    for _, petName in ipairs(keys) do
        parts[#parts + 1] = petName .. "=" .. tostring(petHistory[petName])
    end

    return table.concat(parts, "|")
end

updateHistoryUI = function(force)
    if not force and (not HistoryPage or not HistoryPage.Visible) then
        AutoBuyHistoryDirty = true
        return
    end

    local signature = getAutoBuyHistorySignature()
    if AutoBuyHistoryBuilt
        and not AutoBuyHistoryDirty
        and AutoBuyHistorySignature == signature then
        return
    end

    for _, child in ipairs(HistoryScroll:GetChildren()) do
        if child.Name == "HistoryRow" or child.Name == "HistoryEmpty" then
            child:Destroy()
        end
    end

    HistoryTotalLabel.Text = "Total pets: " .. petsBought
    HistoryDailyLabel.Text = "Today: " .. dailyPetsBought .. " pets"

    local names = {}
    for petName, count in pairs(petHistory) do
        if tonumber(count) and tonumber(count) > 0 then
            table.insert(names, petName)
        end
    end
    table.sort(names, function(first, second)
        local firstBaseName = stripPetSizePrefix(first)
        local secondBaseName = stripPetSizePrefix(second)
        local firstRank = RARITY_RANK[PET_RARITY_OVERRIDES[firstBaseName] or "Unknown"] or 0
        local secondRank = RARITY_RANK[PET_RARITY_OVERRIDES[secondBaseName] or "Unknown"] or 0
        if firstRank ~= secondRank then
            return firstRank < secondRank
        end
        return first < second
    end)

    if #names == 0 then
        New("TextLabel", {
            Name = "HistoryEmpty",
            Text = "No pets secured yet.",
            Font = Theme.FontBody,
            TextSize = 13,
            TextColor3 = Theme.Muted,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 32),
            TextXAlignment = Enum.TextXAlignment.Center,
        }, HistoryScroll)
        AutoBuyHistoryBuilt = true
        AutoBuyHistoryDirty = false
        AutoBuyHistorySignature = signature
        return
    end

    for rowIndex, petName in ipairs(names) do
        local basePetName = stripPetSizePrefix(petName)
        local row = New("Frame", {
            Name = "HistoryRow",
            LayoutOrder = rowIndex,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.22,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
        }, HistoryScroll)
        New("UICorner", { CornerRadius = UDim.new(0, 5) }, row)
        local petIcon = New("ImageLabel", {
            Name = "PetIcon",
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Fit,
            Position = UDim2.new(0, 4, 0, 4),
            Size = UDim2.new(0, 22, 0, 22),
            Image = "",
        }, row)
        New("UICorner", { CornerRadius = UDim.new(0, 4) }, petIcon)
        setPetIcon(basePetName, petIcon)
        New("TextLabel", {
            Text = petName,
            Font = Theme.Font,
            TextSize = 13,
            TextColor3 = Theme.White,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 32, 0, 0),
            Size = UDim2.new(0.55, -32, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
        New("TextLabel", {
            Text = tostring(petHistory[petName]),
            Font = Theme.Font,
            TextSize = 13,
            TextColor3 = Theme.Success,
            BackgroundTransparency = 1,
            Position = UDim2.new(0.55, 0, 0, 0),
            Size = UDim2.new(0.2, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
        }, row)
        local rarity = PET_RARITY_OVERRIDES[basePetName] or "Unknown"
        New("TextLabel", {
            Text = rarity,
            Font = Theme.Font,
            TextSize = 13,
            TextColor3 = rarity == "Unknown" and Theme.Muted or Theme.Success,
            BackgroundTransparency = 1,
            Position = UDim2.new(0.75, 0, 0, 0),
            Size = UDim2.new(0.25, -10, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)
    end

    AutoBuyHistoryBuilt = true
    AutoBuyHistoryDirty = false
    AutoBuyHistorySignature = signature
end
end

do
WebhookPanel = CreatePanel(WebhookPage, "WebhookPanel", UDim2.new(0, 12, 0, 12), UDim2.new(1, -28, 0, 390), "WEBHOOK ALERTS")

New("TextLabel", {
    Text = "Main alerts stay separate from sell summaries. Choose exactly which alerts you receive.",
    Font = Theme.FontBody,
    TextSize = 12,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 28),
    Size = UDim2.new(1, -24, 0, 24),
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)

New("TextLabel", {
    Text = "Discord Webhook URL",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 58),
    Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)

local WebhookUrlBox = New("TextBox", {
    Name = "WebhookUrlBox",
    Text = "",
    PlaceholderText = "https://discord.com/api/webhooks/...",
    Font = Theme.FontBody,
    TextSize = 12,
    TextColor3 = Theme.InputText,
    PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ClearTextOnFocus = false,
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 0, 76),
    Size = UDim2.new(1, -96, 0, 28),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, WebhookUrlBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, WebhookUrlBox)

WebhookUrlShowButton = New("TextButton", {
    Text = "SHOW", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
    Position = UDim2.new(1, -76, 0, 76), Size = UDim2.new(0, 64, 0, 28),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, WebhookUrlShowButton)

New("TextLabel", {
    Text = "Sell Webhook URL", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 112), Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)
SellWebhookUrlBox = New("TextBox", {
    Name = "SellWebhookUrlBox", Text = "", PlaceholderText = "https://discord.com/api/webhooks/...",
    Font = Theme.FontBody, TextSize = 12, TextColor3 = Theme.InputText, PlaceholderColor3 = Theme.Muted,
    BackgroundColor3 = Theme.InputBg, BorderSizePixel = 0, ClipsDescendants = true, ClearTextOnFocus = false,
    TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 12, 0, 130), Size = UDim2.new(1, -96, 0, 28),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SellWebhookUrlBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, SellWebhookUrlBox)
SellWebhookUrlShowButton = New("TextButton", {
    Text = "SHOW", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.Surface3, BorderSizePixel = 0,
    Position = UDim2.new(1, -76, 0, 130), Size = UDim2.new(0, 64, 0, 28),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SellWebhookUrlShowButton)

New("TextLabel", {
    Text = "Enable Main Webhook",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 170),
    Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)
local WebhookToggle = New("TextButton", {
    Name = "WebhookToggle",
    Text = "",
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -62, 0, 167),
    Size = UDim2.new(0, 48, 0, 24),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, WebhookToggle)
local WebhookKnob = New("Frame", {
    Name = "WebhookKnob",
    BackgroundColor3 = Theme.White,
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0),
    Size = UDim2.new(0, 18, 0, 18),
}, WebhookToggle)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, WebhookKnob)

local TestWebhookButton = New("TextButton", {
    Text = "TEST MAIN",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark,
    BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 216),
    Size = UDim2.new(0.5, -16, 0, 26),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, TestWebhookButton)

New("TextLabel", {
    Text = "Enable Sell Webhook", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 256), Size = UDim2.new(1, -100, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)
SellWebhookToggle = New("TextButton", {
    Text = "", BackgroundColor3 = Theme.RedDark, BorderSizePixel = 0,
    Position = UDim2.new(1, -62, 0, 253), Size = UDim2.new(0, 48, 0, 24),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, SellWebhookToggle)
SellWebhookKnob = New("Frame", {
    BackgroundColor3 = Theme.White, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.new(0, 18, 0, 18),
}, SellWebhookToggle)
New("UICorner", { CornerRadius = UDim.new(1, 0) }, SellWebhookKnob)
TestSellWebhookButton = New("TextButton", {
    Text = "TEST SELL", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.White,
    BackgroundColor3 = Theme.RedDark, BorderSizePixel = 0,
    Position = UDim2.new(0.5, 4, 0, 216), Size = UDim2.new(0.5, -16, 0, 26),
}, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, TestSellWebhookButton)

New("TextLabel", {
    Text = "ALERTS", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.TextDim,
    BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 290), Size = UDim2.new(1, -24, 0, 12),
    TextXAlignment = Enum.TextXAlignment.Left,
}, WebhookPanel)
PetAlertButton = New("TextButton", { Text = "PET: ON", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White, BackgroundColor3 = Theme.Success, BorderSizePixel = 0, Position = UDim2.new(0, 12, 0, 306), Size = UDim2.new(1/3, -16, 0, 22) }, WebhookPanel)
SellAlertButton = New("TextButton", { Text = "SELL: ON", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White, BackgroundColor3 = Theme.Success, BorderSizePixel = 0, Position = UDim2.new(1/3, 4, 0, 306), Size = UDim2.new(1/3, -16, 0, 22) }, WebhookPanel)
DisconnectAlertButton = New("TextButton", { Text = "ERROR: ON", Font = Theme.Font, TextSize = 10, TextColor3 = Theme.White, BackgroundColor3 = Theme.Success, BorderSizePixel = 0, Position = UDim2.new(2/3, -4, 0, 306), Size = UDim2.new(1/3, -8, 0, 22) }, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, PetAlertButton)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SellAlertButton)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, DisconnectAlertButton)

New("TextLabel", { Text = "Sell batch interval (10-30 seconds)", Font = Theme.Font, TextSize = 11, TextColor3 = Theme.TextDim, BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 340), Size = UDim2.new(0.65, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left }, WebhookPanel)
SellBatchIntervalBox = New("TextBox", { Text = "15", Font = Theme.Font, TextSize = 12, TextColor3 = Theme.InputText, BackgroundColor3 = Theme.InputBg, BorderSizePixel = 0, ClearTextOnFocus = false, Position = UDim2.new(1, -82, 0, 336), Size = UDim2.new(0, 70, 0, 24), TextXAlignment = Enum.TextXAlignment.Center }, WebhookPanel)
New("UICorner", { CornerRadius = UDim.new(0, 5) }, SellBatchIntervalBox)

WebhookStatusLabel = New("TextLabel", {
    Name = "WebhookStatusLabel",
    Text = "Webhook is OFF",
    Font = Theme.FontBody,
    TextSize = 11,
    TextColor3 = Theme.Muted,
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 1, -26),
    Size = UDim2.new(1, -24, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, WebhookPanel)

function updateWebhookUI()
    WebhookUrlBox.Text = webhookUrl
    SellWebhookUrlBox.Text = sellWebhookUrl
    WebhookUrlBox.TextTransparency = webhookUrlsVisible and 0 or 1
    SellWebhookUrlBox.TextTransparency = webhookUrlsVisible and 0 or 1
    WebhookUrlShowButton.Text = webhookUrlsVisible and "HIDE" or "SHOW"
    SellWebhookUrlShowButton.Text = webhookUrlsVisible and "HIDE" or "SHOW"
    WebhookToggle.BackgroundColor3 = webhookEnabled and Theme.Success or Theme.RedDark
    SafeTween(WebhookKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = webhookEnabled and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
    SellWebhookToggle.BackgroundColor3 = sellWebhookEnabled and Theme.Success or Theme.RedDark
    SafeTween(SellWebhookKnob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = sellWebhookEnabled and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
    })
    PetAlertButton.Text = webhookPetAlerts and "PET: ON" or "PET: OFF"
    SellAlertButton.Text = webhookSellAlerts and "SELL: ON" or "SELL: OFF"
    DisconnectAlertButton.Text = webhookDisconnectAlerts and "ERROR: ON" or "ERROR: OFF"
    PetAlertButton.BackgroundColor3 = webhookPetAlerts and Theme.Success or Theme.RedDark
    SellAlertButton.BackgroundColor3 = webhookSellAlerts and Theme.Success or Theme.RedDark
    DisconnectAlertButton.BackgroundColor3 = webhookDisconnectAlerts and Theme.Success or Theme.RedDark
    SellBatchIntervalBox.Text = tostring(sellBatchInterval)
    WebhookStatusLabel.Text = lastWebhookStatus
    WebhookStatusLabel.TextColor3 = string.find(lastWebhookStatus, "failed", 1, true) and Theme.Text
        or (string.find(lastWebhookStatus, "sent", 1, true) and Theme.Success or Theme.Muted)
end

WebhookUrlBox.FocusLost:Connect(function()
    webhookUrl = tostring(WebhookUrlBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    saveSettings()
    updateWebhookUI()
end)

local webhookSaveSerial = 0
WebhookUrlBox:GetPropertyChangedSignal("Text"):Connect(function()
    webhookSaveSerial = webhookSaveSerial + 1
    local currentSerial = webhookSaveSerial
    task.delay(0.7, function()
        if currentSerial ~= webhookSaveSerial then return end
        webhookUrl = tostring(WebhookUrlBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        saveSettings()
    end)
end)

SellWebhookUrlBox.FocusLost:Connect(function()
    sellWebhookUrl = tostring(SellWebhookUrlBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    saveSettings()
    updateWebhookUI()
end)

SellWebhookUrlBox:GetPropertyChangedSignal("Text"):Connect(function()
    webhookSaveSerial = webhookSaveSerial + 1
    local currentSerial = webhookSaveSerial
    task.delay(0.7, function()
        if currentSerial ~= webhookSaveSerial then return end
        sellWebhookUrl = tostring(SellWebhookUrlBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        saveSettings()
    end)
end)

WebhookUrlShowButton.Activated:Connect(function()
    webhookUrlsVisible = not webhookUrlsVisible
    updateWebhookUI()
end)
SellWebhookUrlShowButton.Activated:Connect(function()
    webhookUrlsVisible = not webhookUrlsVisible
    updateWebhookUI()
end)

WebhookToggle.Activated:Connect(function()
    if not webhookEnabled and webhookUrl == "" then
        Notify("Webhook", "Paste your Discord webhook URL first.", 2)
        return
    end
    webhookEnabled = not webhookEnabled
    saveSettings()
    updateWebhookUI()
end)

SellWebhookToggle.Activated:Connect(function()
    if not sellWebhookEnabled and sellWebhookUrl == "" then
        Notify("Sell Webhook", "Paste your Sell Webhook URL first.", 2)
        return
    end
    sellWebhookEnabled = not sellWebhookEnabled
    saveSettings()
    updateWebhookUI()
end)

PetAlertButton.Activated:Connect(function() webhookPetAlerts = not webhookPetAlerts; saveSettings(); updateWebhookUI() end)
SellAlertButton.Activated:Connect(function() webhookSellAlerts = not webhookSellAlerts; saveSettings(); updateWebhookUI() end)
DisconnectAlertButton.Activated:Connect(function() webhookDisconnectAlerts = not webhookDisconnectAlerts; saveSettings(); updateWebhookUI() end)

SellBatchIntervalBox.FocusLost:Connect(function()
    sellBatchInterval = math.clamp(
        tonumber(SellBatchIntervalBox.Text) or sellBatchInterval,
        10,
        30
    )

    saveSettings()
    updateWebhookUI()

    if autoSellEnabled then
        PetAutoSellRuntime.BumpWake()
        PetAutoSellRuntime.Queue("interval_changed")
    end
end)

TestWebhookButton.Activated:Connect(function()
    if not webhookEnabled or webhookUrl == "" then
        Notify("Webhook", "Enable Webhook and add a URL first.", 2)
        return
    end
    local sent, reason = sendWebhook("Webhook Connected", "Test alert from AUTO BUY PET V1.9.", 5763719)
    if sent then
        Notify("Webhook", "Test alert delivered.", 2)
    else
        Notify("Webhook", "Test failed: " .. tostring(reason or "request unavailable"), 4)
    end
    updateWebhookUI()
end)

TestSellWebhookButton.Activated:Connect(function()
    if not sellWebhookEnabled or sellWebhookUrl == "" then
        Notify("Sell Webhook", "Enable Sell Webhook and add a URL first.", 2)
        return
    end
    local sent, reason = sendWebhook("Sell Webhook Connected", "Test sell-summary alert from AUTO BUY PET V1.9.", 15105570, nil, nil, sellWebhookUrl, true)
    Notify("Sell Webhook", sent and "Test alert delivered." or ("Test failed: " .. tostring(reason or "request unavailable")), sent and 2 or 4)
    updateWebhookUI()
end)
end

do
local shecklesValueObject = nil

function readNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        return tonumber(value:gsub("[^%d%-%.]", ""))
    end
    return nil
end

function formatSheckles(value)
    local suffixes = {
        { 1000000000000, "T" },
        { 1000000000, "B" },
        { 1000000, "M" },
        { 1000, "K" },
    }
    for _, unit in ipairs(suffixes) do
        if value >= unit[1] then
            local text = string.format("%.1f", value / unit[1]):gsub("%.0$", "")
            return text .. unit[2]
        end
    end
    return tostring(math.floor(value))
end

function getSheckles()

    if shecklesValueObject and shecklesValueObject.Parent then
        return readNumber(shecklesValueObject.Value)
    end

    local directAttribute = readNumber(LocalPlayer:GetAttribute("Sheckles"))
        or readNumber(LocalPlayer:GetAttribute("Scheckles"))
        or readNumber(LocalPlayer:GetAttribute("Leaves"))
    if directAttribute ~= nil then return directAttribute end

    for _, item in ipairs(LocalPlayer:GetDescendants()) do
        local name = string.lower(item.Name)

        if (name == "sheckles" or name == "scheckles" or name == "leaves") and item:IsA("ValueBase") then
            shecklesValueObject = item
            return readNumber(item.Value)
        end
    end
    return nil
end

function updateShecklesUI()
    local sheckles = getSheckles()
    ShecklesLabel.Text = sheckles and formatSheckles(sheckles) or "Not found"
end
end

function updateStatusUI()
    if petProtectEnabled then
        LiveChipLabel.Text = "● RUNNING"
        LiveChip.BackgroundColor3 = Color3.fromRGB(37, 126, 89)
        DashboardProfileStatusLabel.Text = "AUTO BUY: RUNNING"
        DashboardProfileStatusLabel.TextColor3 = Theme.Success
        ToggleButton.Text = "DISABLE AUTO BUY PET"
        ToggleButton.BackgroundColor3 = Theme.RedDark
    else
        LiveChipLabel.Text = "● STOPPED"
        LiveChip.BackgroundColor3 = Theme.RedDark
        DashboardProfileStatusLabel.Text = "AUTO BUY: STOPPED"
        DashboardProfileStatusLabel.TextColor3 = Theme.TextDim
        ToggleButton.Text = "ENABLE AUTO BUY PET"
        ToggleButton.BackgroundColor3 = Theme.Red
    end
    ElapsedLabel.Text = formatWebhookElapsed()
    BoughtLabel.Text = formatWebhookNumber(petsBought)
    SpentLabel.Text = totalSpent > 0 and "-" .. formatSheckles(totalSpent) or "0"
    ServerHopsLabel.Text = formatWebhookNumber(serverHops)
    updateShecklesUI()
    TargetLabel.Text = "TARGETS  ●  " .. targetDisplayText
end

function normalizeRarity(value)
    if type(value) ~= "string" then return nil end
    local lowered = string.lower(value)
    for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Legendary", "Mythic", "Super", "Secret" }) do
        if lowered == string.lower(rarity) then
            return rarity
        end
    end
    return nil
end

function findRarityOverride(petName)
    if type(petName) ~= "string" or petName == "" then return nil end

    local exact = PET_RARITY_OVERRIDES[petName]
    if exact then return exact end

    local normalizedName = string.lower(petName):gsub("[^%a%d]", "")
    for configuredName, rarity in pairs(PET_RARITY_OVERRIDES) do
        local normalizedConfigured = string.lower(configuredName):gsub("[^%a%d]", "")
        if normalizedName == normalizedConfigured
            or string.find(normalizedName, normalizedConfigured, 1, true) then
            return rarity
        end
    end
    return nil
end

function getWildPetSpeciesName(pet)

    local species = pet.Name:match("^WildPet_([^_]+)_WildPet_")
    return species or pet.Name
end

function getSizeTierFromInstance(instance)
    if not instance then return nil end

    for _, attributeName in ipairs({
        "Size", "SizeType", "PetSize", "PetSizeType", "Variant", "VariantType", "SpecialType",
    }) do
        local value = instance:GetAttribute(attributeName)
        if type(value) == "string" then
            local lowered = string.lower(value)
            if lowered:find("huge", 1, true) or lowered:find("giant", 1, true) then
                return "Huge"
            end
            if lowered:find("big", 1, true) then
                return "Big"
            end
        end
    end

    if instance:GetAttribute("IsHuge") == true or instance:GetAttribute("Huge") == true then
        return "Huge"
    end
    if instance:GetAttribute("IsBig") == true or instance:GetAttribute("Big") == true then
        return "Big"
    end

    for _, attributeName in ipairs({ "SizeMultiplier", "ScaleMultiplier", "PetScale" }) do
        local value = tonumber(instance:GetAttribute(attributeName))
        if value then
            if value >= 1.5 then return "Huge" end
            if value > 1.1 then return "Big" end
        end
    end

    local name = string.lower(tostring(instance.Name or ""))
    if name:find("huge", 1, true) or name:find("giant", 1, true) then
        return "Huge"
    end
    if name:find("big", 1, true) then
        return "Big"
    end
    return nil
end

function getPetSizeTier(pet, petRef, petName)
    local bestTier = nil
    local function consider(instance)
        local tier = getSizeTierFromInstance(instance)
        if tier == "Huge" then
            bestTier = "Huge"
        elseif tier == "Big" and not bestTier then
            bestTier = "Big"
        end
    end

    consider(pet)
    consider(petRef)

    return bestTier
end

function getWildPetSizeTier(pet)
    local foundBig = false
    local function consider(instance)
        local tier = getSizeTierFromInstance(instance)
        if tier == "Huge" then return "Huge" end
        if tier == "Big" then foundBig = true end
        return nil
    end

    if consider(pet) == "Huge" then return "Huge" end
    if pet then
        for _, descendant in ipairs(pet:GetDescendants()) do
            if consider(descendant) == "Huge" then return "Huge" end
        end

        local map = workspace:FindFirstChild("Map")
        local refs = map and map:FindFirstChild("WildPetRef")
        if refs then
            for _, ref in ipairs(refs:GetChildren()) do
                if ref.Name ~= "" and string.find(pet.Name, ref.Name, 1, true) then
                    if consider(ref) == "Huge" then return "Huge" end
                    break
                end
            end
        end
    end
    return foundBig and "Big" or nil
end

function getWildPetSizePriority(pet)
    local sizeTier = getWildPetSizeTier(pet)
    if sizeTier == "Huge" and buyHugePetsPriority then
        return 2, sizeTier
    end
    if sizeTier == "Big" and buyBigPetsPriority then
        return 1, sizeTier
    end
    return 0, sizeTier
end

function getPetRarity(pet)

    local candidateNames = { getWildPetSpeciesName(pet), pet.Name }
    for _, attributeName in ipairs({ "PetName", "Species", "PetSpecies" }) do
        local attributeValue = pet:GetAttribute(attributeName)
        if type(attributeValue) == "string" then
            table.insert(candidateNames, attributeValue)
        end
    end
    for _, candidateName in ipairs(candidateNames) do
        local override = findRarityOverride(candidateName)
        if override then
            return override
        end
    end

    for _, attributeName in ipairs({ "Rarity", "PetRarity", "Tier" }) do
        local rarity = normalizeRarity(pet:GetAttribute(attributeName))
        if rarity then return rarity end

        local valueObject = pet:FindFirstChild(attributeName, true)
        if valueObject and valueObject:IsA("StringValue") then
            rarity = normalizeRarity(valueObject.Value)
            if rarity then return rarity end
        end
    end

    for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Legendary", "Mythic", "Super", "Secret" }) do
        if string.find(string.lower(pet.Name), string.lower(rarity), 1, true) then
            return rarity
        end
    end

    return "Unknown"
end

Theme.FindLowPopulationServer = function()
    local candidates = {}
    local cursor = nil

    for _ = 1, 3 do
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
            .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor then
            url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
        end

        local requestOk, responseBody = pcall(function()
            return game:HttpGet(url)
        end)
        if not requestOk or type(responseBody) ~= "string" then
            break
        end

        local decodeOk, page = pcall(function()
            return HttpService:JSONDecode(responseBody)
        end)
        if not decodeOk or type(page) ~= "table" then
            break
        end

        for _, server in ipairs(page.data or {}) do
            local players = tonumber(server.playing) or 0
            if server.id ~= game.JobId and players >= 1 and players <= 6 then
                table.insert(candidates, server)
            end
        end

        if #candidates > 0 or not page.nextPageCursor then
            break
        end
        cursor = page.nextPageCursor
    end

    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(1, #candidates)]
end

function waitForPendingPetDelivery()
    local startedAt = tick()
    while pendingPetDelivery and tick() - startedAt < 20 do
        task.wait(0.1)
    end
    return not pendingPetDelivery
end

function beginServerHop(silent)
    if serverHopInProgress then
        if not silent then
            Notify("Server Hop", "A server hop is already being prepared.", 2)
        end
        return
    end

    serverHopInProgress = true
    task.spawn(function()
        if not waitForPendingPetDelivery() then
            serverHopInProgress = false
            if not silent then
                Notify("Server Hop", "Waiting for " .. (pendingPetDeliveryName ~= "" and pendingPetDeliveryName or "the bought pet") .. " to arrive in your Backpack.", 3)
            end
            return
        end

        local targetJobId = getNextCustomJobId()
        if targetJobId then
            if not silent then
                Notify("Server Hop", "Hopping to the next saved Job ID...", 2)
            end
        else
            if not silent then
                Notify("Server Hop", "Searching for a 1-6 player server...", 2)
            end
            local server = Theme.FindLowPopulationServer()
            while not server do
                if not silent then
                    Notify("Server Hop", "No 1-6 player server found. Retrying...", 3)
                end
                task.wait(0.5)
                server = Theme.FindLowPopulationServer()
            end
            targetJobId = server.id
        end

        if isKRNL then
            enableKRNLQueue()
        end
        serverHops = serverHops + 1
        if ServerHopsLabel then
            ServerHopsLabel.Text = formatWebhookNumber(serverHops)
        end
        addActivity("Server hop " .. tostring(serverHops) .. " started")
        saveSettings()
        task.wait(1.2)

        local success = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, LocalPlayer)
        end)

        if not success then

            serverHopInProgress = false
            Notify("Server Hop", "Teleport could not start. Try again.", 3)
        end

    end)
end

Theme.SetPetProtectEnabled = function(enabled)
    petProtectEnabled = enabled == true
    if petProtectEnabled and not autoBuyRuntimeStartedAt then
        autoBuyRuntimeStartedAt = os.time()
    elseif not petProtectEnabled and autoBuyRuntimeStartedAt then
        autoBuyRuntimeSeconds = autoBuyRuntimeSeconds + math.max(0, os.time() - autoBuyRuntimeStartedAt)
        autoBuyRuntimeStartedAt = nil
    end
    rebuildTargetList()
    updateStatusUI()
    saveSettings()

    if not petProtectEnabled then

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if humanoid then
            humanoid:Move(Vector3.new(0, 0, 0), false)
            if root then
                humanoid:MoveTo(root.Position)
            end
            humanoid.WalkSpeed = 16
        end
    end

    if petProtectEnabled then
        if #targetPetNames == 0 and not buyBigPetsPriority and not buyHugePetsPriority then
            Notify("Error", "Select a target pet or enable a size priority first!", 3)
            petProtectEnabled = false
            if autoBuyRuntimeStartedAt then
                autoBuyRuntimeSeconds = autoBuyRuntimeSeconds + math.max(0, os.time() - autoBuyRuntimeStartedAt)
                autoBuyRuntimeStartedAt = nil
            end
            updateStatusUI()
            saveSettings()
            return
        end

        Notify("Buy Protect", "Started - Buying and Protecting: " .. formatList(targetPetNames), 3)
        addActivity("Auto Buy Pet enabled")

        petProtectThread = task.spawn(function()
            local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local humanoid = character:WaitForChild("Humanoid")
            local hrp = character:WaitForChild("HumanoidRootPart")
            local backpack = LocalPlayer:WaitForChild("Backpack")

            local FOLLOW_DISTANCE = 1.0
            local RETURN_DISTANCE = 9
            local MIN_Y = -20
            local NO_PET_TIMEOUT = 12

            humanoid.WalkSpeed = petWalkSpeed
            humanoid.AutoRotate = true

            local runTarget = nil
            local currentTargetPet = nil
            local fastApproach = false
            local claimedWildPets = {}
            local noPetTimer = 0
            local targetSpawnConn = nil
            local targetRemovedConn = nil

            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and string.find(string.lower(tool.Name), "shovel") then
                    humanoid:EquipTool(tool)
                    break
                end
            end

            local groundReferences = {}
            local baseplateModel = workspace:FindFirstChild("Baseplate")
            if baseplateModel then
                local topLayer = baseplateModel:FindFirstChild("TopLayer")
                table.insert(groundReferences, topLayer or baseplateModel)
            end
            if workspace:FindFirstChild("Terrain") then
                table.insert(groundReferences, workspace.Terrain)
            end

            local groundRaycastParams = nil
            if #groundReferences > 0 then
                groundRaycastParams = RaycastParams.new()
                groundRaycastParams.FilterType = Enum.RaycastFilterType.Include
                groundRaycastParams.FilterDescendantsInstances = groundReferences
            end

            local function getGroundY(position)
                if not groundRaycastParams then return -math.huge end
                local result = workspace:Raycast(
                    position + Vector3.new(0, 50, 0),
                    Vector3.new(0, -2000, 0),
                    groundRaycastParams
                )
                return result and result.Position.Y or -math.huge
            end

            local GROUND_CLEARANCE = (humanoid.HipHeight or 2) + (hrp.Size.Y / 2) + 0.05

            local function cframeBeside(position, stopDistance)
                if not hrp or not position then return end

                local horizontal = Vector3.new(
                    position.X - hrp.Position.X,
                    0,
                    position.Z - hrp.Position.Z
                )
                if horizontal.Magnitude < 0.1 then return end

                local destination = position - (horizontal.Unit * (stopDistance or 3))
                local destinationGroundY = getGroundY(destination)
                if destinationGroundY > -math.huge then
                    destination = Vector3.new(
                        destination.X,
                        destinationGroundY + GROUND_CLEARANCE,
                        destination.Z
                    )
                else
                    destination = Vector3.new(destination.X, position.Y + 2.5, destination.Z)
                end

                hrp.CFrame = CFrame.lookAt(
                    destination,
                    Vector3.new(position.X, destination.Y, position.Z)
                )
            end

            local function forceRun()
                if not humanoid then return end
                if not petProtectEnabled then
                    humanoid:Move(Vector3.new(0, 0, 0), false)
                    return
                end

                humanoid.PlatformStand = false
                humanoid.Sit = false
                humanoid.AutoRotate = true
                if hrp then
                    hrp.Anchored = false
                end

                humanoid.WalkSpeed = petWalkSpeed

                if not runTarget then return end

                if fastCFrameMove then

                    cframeBeside(runTarget, 3)
                    return
                end

                humanoid:MoveTo(runTarget)
                local groundY = getGroundY(hrp.Position)
                if groundY > -math.huge then
                    local minY = groundY + GROUND_CLEARANCE
                    if hrp.Position.Y < minY then
                        hrp.CFrame = CFrame.new(hrp.Position.X, minY, hrp.Position.Z)
                            * (hrp.CFrame - hrp.CFrame.Position)
                    end
                end
            end

            local noclipParts = {}
            local noclipPartSet = setmetatable({}, { __mode = "k" })

            local function registerNoclipPart(object)
                if object and object:IsA("BasePart") and not noclipPartSet[object] then
                    noclipPartSet[object] = true
                    noclipParts[#noclipParts + 1] = object
                    object.CanCollide = false
                end
            end

            for _, object in ipairs(character:GetDescendants()) do
                registerNoclipPart(object)
            end

            local noclipDescendantConn = TrackConnection(character.DescendantAdded:Connect(function(object)
                registerNoclipPart(object)
            end))

            local function forceNoclip()

                for index = #noclipParts, 1, -1 do
                    local part = noclipParts[index]
                    if not part or not part.Parent then
                        if part then noclipPartSet[part] = nil end
                        table.remove(noclipParts, index)
                    elseif part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end

            local walkConn = TrackConnection(RunService.Heartbeat:Connect(forceRun))
            local noclipConn = TrackConnection(RunService.Stepped:Connect(forceNoclip))

            local function getTargetPart(model)
                return model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
            end

            local LIVE_PET_RECONCILE_SECONDS = 4
            local livePetCache = setmetatable({}, { __mode = "k" })
            local watchedWildPetSpawns = nil
            local lastLivePetReconcileAt = 0

            local function getWildPetSpawnsFolder()
                local map = workspace:FindFirstChild("Map")
                return map and map:FindFirstChild("WildPetSpawns")
            end

            local function buildLivePetData(pet)
                if not pet or not pet:IsA("Model") then
                    return nil
                end

                local speciesName = getWildPetSpeciesName(pet)
                local rarity = getPetRarity(pet)
                local sizeTier = getWildPetSizeTier(pet)

                return {
                    Pet = pet,
                    SpeciesName = speciesName,
                    SpeciesLower = string.lower(tostring(speciesName or "")),
                    Rarity = rarity,
                    RarityRank = RARITY_RANK[rarity] or 0,
                    SizeTier = sizeTier,
                    TargetPart = getTargetPart(pet),
                }
            end

            local function registerLivePet(pet, forceRefresh)
                if not pet or not pet:IsA("Model") then
                    return nil
                end

                local data = livePetCache[pet]

                if forceRefresh or not data then
                    data = buildLivePetData(pet)
                    if data then
                        livePetCache[pet] = data
                    end
                elseif not data.TargetPart or not data.TargetPart.Parent then

                    data.TargetPart = getTargetPart(pet)
                end

                return data
            end

            local function unregisterLivePet(pet)
                livePetCache[pet] = nil
            end

            local function buildRequestedNameList(names)
                local result = {}
                for _, name in ipairs(names or {}) do
                    local lowerName = string.lower(tostring(name or ""))
                    if lowerName ~= "" then
                        result[#result + 1] = lowerName
                    end
                end
                return result
            end

            local function getCachedSizePriority(data)
                if not data then
                    return 0
                end

                if data.SizeTier == "Huge" and buyHugePetsPriority then
                    return 2
                end
                if data.SizeTier == "Big" and buyBigPetsPriority then
                    return 1
                end
                return 0
            end

            local function cachedPetMatchesSelection(data, lowerNames)
                if not data then
                    return false, 0
                end

                local pet = data.Pet
                if not pet
                    or not pet.Parent
                    or claimedWildPets[pet] then
                    return false, 0
                end

                local sizePriority = getCachedSizePriority(data)
                if sizePriority > 0 then
                    return true, sizePriority
                end

                for _, requestedName in ipairs(lowerNames) do
                    if string.find(data.SpeciesLower, requestedName, 1, true) then
                        return true, 0
                    end
                end

                return false, 0
            end

            local function isBetterCachedPet(priority, rarityRank, distance, bestPriority, bestRarityRank, bestDistance)
                if bestPriority == nil then
                    return true
                end
                if priority ~= bestPriority then
                    return priority > bestPriority
                end
                if rarityRank ~= bestRarityRank then
                    return rarityRank > bestRarityRank
                end
                return distance < bestDistance
            end

            local function useNewPetImmediatelyIfWanted(pet)

                task.spawn(function()
                    for attempt = 1, 6 do
                        if not petProtectEnabled
                            or currentTargetPet
                            or not pet
                            or not pet.Parent then
                            return
                        end

                        local data = registerLivePet(pet, attempt > 1)
                        local lowerNames = buildRequestedNameList(targetPetNames)
                        local wanted = cachedPetMatchesSelection(data, lowerNames)

                        if wanted and data and data.TargetPart and data.TargetPart.Parent then
                            runTarget = data.TargetPart.Position
                            return
                        end

                        task.wait(0.08)
                    end
                end)
            end

            local function connectWildPetFolder(spawns)
                if watchedWildPetSpawns == spawns then
                    return
                end

                if targetSpawnConn then
                    targetSpawnConn:Disconnect()
                    targetSpawnConn = nil
                end
                if targetRemovedConn then
                    targetRemovedConn:Disconnect()
                    targetRemovedConn = nil
                end

                watchedWildPetSpawns = spawns
                table.clear(livePetCache)

                if not spawns then
                    return
                end

                for _, pet in ipairs(spawns:GetChildren()) do
                    registerLivePet(pet, true)
                end

                targetSpawnConn = TrackConnection(spawns.ChildAdded:Connect(function(pet)
                    if not pet:IsA("Model") then
                        return
                    end

                    registerLivePet(pet, true)
                    useNewPetImmediatelyIfWanted(pet)
                end))

                targetRemovedConn = TrackConnection(spawns.ChildRemoved:Connect(function(pet)
                    unregisterLivePet(pet)
                end))
            end

            local function reconcileLivePetCache(force)
                local now = os.clock()
                local spawns = getWildPetSpawnsFolder()

                if spawns ~= watchedWildPetSpawns then
                    connectWildPetFolder(spawns)
                    lastLivePetReconcileAt = now
                    return
                end

                if not force and (now - lastLivePetReconcileAt) < LIVE_PET_RECONCILE_SECONDS then
                    return
                end

                lastLivePetReconcileAt = now

                if not spawns then
                    table.clear(livePetCache)
                    return
                end

                local seen = setmetatable({}, { __mode = "k" })

                for _, pet in ipairs(spawns:GetChildren()) do
                    if pet:IsA("Model") then
                        seen[pet] = true
                        if force or not livePetCache[pet] then

                            registerLivePet(pet, true)
                        elseif not livePetCache[pet].TargetPart
                            or not livePetCache[pet].TargetPart.Parent then
                            livePetCache[pet].TargetPart = getTargetPart(pet)
                        end
                    end
                end

                for pet in pairs(livePetCache) do
                    if not seen[pet] or pet.Parent ~= spawns then
                        unregisterLivePet(pet)
                    end
                end
            end

            connectWildPetFolder(getWildPetSpawnsFolder())
            lastLivePetReconcileAt = os.clock()

            task.delay(0.6, function()
                if petProtectEnabled then
                    reconcileLivePetCache(true)
                end
            end)

            local function findWildPets(names, forceFresh)
                if not names
                    or (#names == 0 and not buyBigPetsPriority and not buyHugePetsPriority) then
                    return {}
                end

                reconcileLivePetCache(forceFresh == true)

                local lowerNames = buildRequestedNameList(names)
                local bestPet = nil
                local bestPriority = nil
                local bestRarityRank = nil
                local bestDistance = nil

                for pet, data in pairs(livePetCache) do
                    if pet and pet.Parent then
                        local matches, priority = cachedPetMatchesSelection(data, lowerNames)
                        if matches then
                            local targetPart = data.TargetPart
                            if not targetPart or not targetPart.Parent then
                                data = registerLivePet(pet, true)
                                targetPart = data and data.TargetPart or nil
                            end

                            local distance = targetPart
                                and (hrp.Position - targetPart.Position).Magnitude
                                or math.huge
                            local rarityRank = data and data.RarityRank or 0

                            if isBetterCachedPet(
                                priority,
                                rarityRank,
                                distance,
                                bestPriority,
                                bestRarityRank,
                                bestDistance
                            ) then
                                bestPet = pet
                                bestPriority = priority
                                bestRarityRank = rarityRank
                                bestDistance = distance
                            end
                        end
                    end
                end

                return bestPet and { bestPet } or {}
            end

            local function aimAtNextWildPet()
                local nextPet = findWildPets(targetPetNames)[1]
                local data = nextPet and livePetCache[nextPet] or nil
                local nextPart = data and data.TargetPart or getTargetPart(nextPet)
                runTarget = nextPart and nextPart.Position or nil
            end

            local function isInsideSafeZone(pos)
                local zones = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("SafeZones")
                if not zones then return false end
                for _, zone in ipairs(zones:GetDescendants()) do
                    if zone:IsA("BasePart") then
                        local size = zone.Size / 2
                        local rel = zone.CFrame:PointToObjectSpace(pos)
                        if math.abs(rel.X) <= size.X and math.abs(rel.Y) <= size.Y and math.abs(rel.Z) <= size.Z then
                            return true
                        end
                    end
                end
                return false
            end

            local function getPromptPrice(prompt)
                if not prompt or not prompt.ObjectText then return nil end
                local text = prompt.ObjectText:gsub("[Â¢,\s]", ""):upper()
                local num = tonumber(text:match("[%d%.]+"))
                if not num then return nil end
                if text:find("K") then num = num * 1000
                elseif text:find("M") then num = num * 1000000
                elseif text:find("B") then num = num * 1000000000 end
                return num
            end

            local function getClosestIntruder(petPos, preferredPlayer)

                if preferredPlayer and preferredPlayer ~= LocalPlayer and preferredPlayer.Character then
                    local preferredHRP = preferredPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if preferredHRP and (preferredHRP.Position - petPos).Magnitude < petPunchRadius then
                        return preferredPlayer
                    end
                end

                local closest, closestDist = nil, petPunchRadius
                for _, other in ipairs(Players:GetPlayers()) do
                    if other ~= LocalPlayer and other.Character then
                        local otherHRP = other.Character:FindFirstChild("HumanoidRootPart")
                        if otherHRP then
                            local dist = (otherHRP.Position - petPos).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                closest = other
                            end
                        end
                    end
                end
                return closest
            end

            local function getShovelTool()
                for _, tool in ipairs(backpack:GetChildren()) do
                    if tool:IsA("Tool") and string.find(string.lower(tool.Name), "shovel") then
                        return tool
                    end
                end
                for _, tool in ipairs(character:GetChildren()) do
                    if tool:IsA("Tool") and string.find(string.lower(tool.Name), "shovel") then
                        return tool
                    end
                end
                return nil
            end

            local function countOwnedPet(petName)
                local amount = 0
                for _, container in ipairs({ backpack, character }) do
                    if container then
                        for _, item in ipairs(container:GetChildren()) do
                            if item:IsA("Tool") and item.Name == petName then
                                amount = amount + 1
                            end
                        end
                    end
                end
                return amount
            end

            local function getWildPetRef(pet)
                local map = workspace:FindFirstChild("Map")
                local refs = map and map:FindFirstChild("WildPetRef")
                if not refs or not pet then
                    return nil
                end
                for _, ref in ipairs(refs:GetChildren()) do
                    if ref.Name ~= "" and string.find(pet.Name, ref.Name, 1, true) then
                        return ref
                    end
                end
                return nil
            end

            local function isWildPetOwnedByMe(ref)
                if not ref then
                    return false
                end
                return tonumber(ref:GetAttribute("OwnerUserId")) == LocalPlayer.UserId
                    or tostring(ref:GetAttribute("OwnerName") or "") == LocalPlayer.Name
            end

            local function waitForPetInBackpack(pet, petName, ownedBefore, petRef)
                pendingPetDeliveryCount = pendingPetDeliveryCount + 1
                pendingPetDelivery = true
                pendingPetDeliveryName = petName
                local arrived = false
                local result = "timeout"
                for _ = 1, 120 do
                    if not pet.Parent then
                        if countOwnedPet(petName) > ownedBefore then
                            arrived = true
                            result = "arrived"
                            break
                        end
                        if petRef and not isWildPetOwnedByMe(petRef) then
                            result = "owner_changed"
                            break
                        end
                    end
                    task.wait(0.1)
                end
                if pet.Parent and not arrived then
                    result = "still_alive"
                end
                pendingPetDeliveryCount = math.max(0, pendingPetDeliveryCount - 1)
                pendingPetDelivery = pendingPetDeliveryCount > 0
                if not pendingPetDelivery then
                    pendingPetDeliveryName = ""
                end
                return arrived, result
            end

            local function recordSecuredPet(pet, petName, purchasePrice, purchaseRequested, petRef)
                local rarity = getPetRarity(pet)
                local sizeTier = getPetSizeTier(pet, petRef, petName)
                local displayPetName = sizeTier and (sizeTier .. " " .. petName) or petName
                petsBought = petsBought + 1
                if purchasePrice > 0 then
                    totalSpent = totalSpent + purchasePrice
                end
                if dailyDate ~= os.date("%Y-%m-%d") then
                    dailyDate = os.date("%Y-%m-%d")
                    dailyPetsBought = 0
                end
                dailyPetsBought = dailyPetsBought + 1
                petHistory[displayPetName] = (tonumber(petHistory[displayPetName]) or 0) + 1
                addActivity("Secured " .. displayPetName .. " (" .. rarity .. ")")
                _G.__ScoopHubSilentLog("[AutoBuyPet] Secured", displayPetName, rarity, "Total pets:", petsBought)
                saveSettings()
                updateStatusUI()
                if updateHistoryUI then updateHistoryUI() end
                local baseWebhookPetName = WEBHOOK_PET_PAGE_NAMES[petName] or petName
                local webhookPetName = sizeTier and (sizeTier .. " " .. baseWebhookPetName) or baseWebhookPetName
                if webhookPetAlerts then
                    sendWebhook(
                        "PET SECURED",
                        "**" .. webhookPetName .. "** was secured successfully.",
                        WEBHOOK_RARITY_COLORS[rarity] or 5763719,
                        {
                            { name = "PET", value = webhookPetName, inline = true },
                            { name = "RARITY", value = rarity, inline = true },
                            { name = "TOTAL PETS", value = tostring(petsBought), inline = true },
                        },
                        getWebhookPetImage(petName)
                    )
                end
                if GLOBAL_WEBHOOK_URL ~= "" then
                    sendWebhook(
                        "PET SECURED",
                        "**" .. webhookPetName .. "** was secured successfully.",
                        WEBHOOK_RARITY_COLORS[rarity] or 5763719,
                        {
                            { name = "PLAYER", value = censorGlobalPlayerName(LocalPlayer.Name), inline = true },
                            { name = "PET", value = webhookPetName, inline = true },
                            { name = "RARITY", value = rarity, inline = true },
                        },
                        getWebhookPetImage(petName),
                        GLOBAL_WEBHOOK_URL,
                        true
                    )
                end
                if PRIVATE_WEBHOOK_URL ~= "" then
                    sendWebhook(
                        "PET SECURED",
                        "**" .. webhookPetName .. "** was secured successfully.",
                        WEBHOOK_RARITY_COLORS[rarity] or 5763719,
                        {
                            { name = "PLAYER", value = LocalPlayer.Name, inline = true },
                            { name = "PET", value = webhookPetName, inline = true },
                            { name = "RARITY", value = rarity, inline = true },
                        },
                        getWebhookPetImage(petName),
                        PRIVATE_WEBHOOK_URL,
                        true
                    )
                end
                Notify("Secured!", displayPetName .. " bought! " .. rarity, 2)
            end

            local function securePet(pet)
                local expectedPetName = getWildPetSpeciesName(pet)
                local ownedBefore = countOwnedPet(expectedPetName)
                local petRef = getWildPetRef(pet)
                local wasOwnedByMe = isWildPetOwnedByMe(petRef)
                local lastOwnerName = petRef and tostring(petRef:GetAttribute("OwnerName") or "") or ""
                local reclaimOwnerName = nil
                currentTargetPet = pet
                Notify("Target Locked", "Now Buying And Protecting: " .. expectedPetName, 2)
                noPetTimer = 0
                local refPrice = petRef and tonumber(petRef:GetAttribute("Price")) or 0
                local purchasePrice = refPrice
                local purchaseRequested = false

                while ScoopHubRunAlive() and petProtectEnabled do
                    if not pet then
                        break
                    end
                    if not pet.Parent then

                        fastApproach = false
                        runTarget = nil
                        claimedWildPets[pet] = true
                        recordSecuredPet(pet, expectedPetName, purchasePrice, purchaseRequested, petRef)
                        aimAtNextWildPet()
                        break
                    else

                    end

                    local targetPart = getTargetPart(pet)
                    if not targetPart then break end

                    if petRef then
                        local ownerName = tostring(petRef:GetAttribute("OwnerName") or "")
                        if purchaseRequested and ownerName ~= lastOwnerName and not isWildPetOwnedByMe(petRef) then
                            Notify("Ownership Changed", expectedPetName .. " changed owner. Returning to buy it again.", 2)
                            reclaimOwnerName = ownerName ~= "" and ownerName or nil
                            runTarget = targetPart.Position
                            purchaseRequested = false
                            wasOwnedByMe = false
                        elseif isWildPetOwnedByMe(petRef) then

                            reclaimOwnerName = nil
                            wasOwnedByMe = true
                        end
                        lastOwnerName = ownerName
                    end

                    if false and purchaseRequested and not wasOwnedByMe and isWildPetOwnedByMe(petRef) then
                        local arrived, result = waitForPetInBackpack(pet, expectedPetName, ownedBefore, petRef)
                        if arrived then
                            claimedWildPets[pet] = true
                            recordSecuredPet(pet, expectedPetName, purchasePrice, purchaseRequested, petRef)
                            aimAtNextWildPet()
                            break
                        elseif result == "still_alive" then

                            runTarget = targetPart.Position
                            task.wait(0.1)
                        else
                            Notify("Purchase Pending", expectedPetName .. " disappeared but did not reach your Backpack.", 3)
                            aimAtNextWildPet()
                            break
                        end
                    end

                    if purchaseRequested and petRef and wasOwnedByMe and not pet.Parent then
                        if waitForPetInBackpack(pet, expectedPetName, ownedBefore, petRef) then
                            claimedWildPets[pet] = true
                            recordSecuredPet(pet, expectedPetName, purchasePrice, purchaseRequested, petRef)
                            aimAtNextWildPet()
                        else
                            Notify("Purchase Pending", expectedPetName .. " is still being delivered to your Backpack.", 3)
                        end
                        break
                    end

                    local petPos = targetPart.Position

                    if hrp.Position.Y < MIN_Y then
                        hrp.CFrame = CFrame.new(petPos + Vector3.new(0, 5, 0))
                        task.wait(0.1)
                        continue
                    end

                    local distanceToPet = (hrp.Position - petPos).Magnitude
                    local prompt = pet:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local ownerName = petRef and tostring(petRef:GetAttribute("OwnerName") or "") or ""
                    fastApproach = ownerName == "" and distanceToPet > FOLLOW_DISTANCE

                    if reclaimOwnerName and distanceToPet <= FOLLOW_DISTANCE and prompt and prompt.Enabled then
                        if not purchaseRequested then
                            purchasePrice = refPrice > 0 and refPrice or (getPromptPrice(prompt) or 0)
                            purchaseRequested = true
                        end
                        pcall(function()
                            fireproximityprompt(prompt)
                        end)
                        task.wait(0.12)
                    end

                    local reclaimOwner = reclaimOwnerName and Players:FindFirstChild(reclaimOwnerName) or nil
                    local intruder = getClosestIntruder(petPos, reclaimOwner)

                    if intruder and intruder.Character then
                        fastApproach = false
                        local otherHRP = intruder.Character:FindFirstChild("HumanoidRootPart")
                        if otherHRP then

                            runTarget = otherHRP.Position

                            cframeBeside(otherHRP.Position, 2.5)
                            pcall(function() ShovelNet.HitPlayer:Fire(intruder.UserId) end)
                            pcall(function() ShovelNet.SwingShovel:Fire(intruder.Character) end)

                            local shovelTool = getShovelTool()
                            if shovelTool then
                                local equipped = character:FindFirstChildOfClass("Tool")
                                if equipped ~= shovelTool then
                                    humanoid:EquipTool(shovelTool)
                                end
                                pcall(function() shovelTool:Activate() end)
                            end

                            task.wait(0.06)
                            continue
                        end
                    end

                    if distanceToPet > RETURN_DISTANCE then
                        runTarget = petPos
                        task.wait(0.05)
                        continue
                    end

                    if distanceToPet <= FOLLOW_DISTANCE then
                        fastApproach = false
                    end
                    if distanceToPet > FOLLOW_DISTANCE then
                        runTarget = petPos
                    end

                    if prompt and prompt.Enabled then
                        local price = getPromptPrice(prompt)
                        if not price or price < maxPetPrice then
                            if not purchaseRequested then
                                purchasePrice = refPrice > 0 and refPrice or (price or 0)
                                purchaseRequested = true
                            end
                            fireproximityprompt(prompt)
                            task.wait(0.25)
                        end
                    end

                    task.wait(0.06)
                end
                if currentTargetPet == pet then
                    currentTargetPet = nil
                end
                fastApproach = false
            end

            while ScoopHubRunAlive() and petProtectEnabled do
                local matches = findWildPets(targetPetNames)

                if #matches == 0 then

                    runTarget = nil
                    fastApproach = false
                    humanoid:MoveTo(hrp.Position)
                    noPetTimer = noPetTimer + 1

                    if autoRejoin and noPetTimer >= NO_PET_TIMEOUT then

                        if not waitForPendingPetDelivery() then
                            noPetTimer = 0
                            task.wait(2)
                            continue
                        end

                        if #findWildPets(targetPetNames, true) > 0 then
                            noPetTimer = 0
                            continue
                        end

                        Notify(
                            "Auto Server Hop",
                            "No pets available - hopping server",
                            3
                        )
                        addActivity("No selected target pets left - auto hop")
                        noPetTimer = 0

                        beginServerHop(true)

                        break
                    end

                    task.wait(1)
                else

                    noPetTimer = 0
                    securePet(matches[1])
                end
            end

            walkConn:Disconnect()
            noclipConn:Disconnect()
            if noclipDescendantConn then
                noclipDescendantConn:Disconnect()
            end
            if targetSpawnConn then
                targetSpawnConn:Disconnect()
            end
            if targetRemovedConn then
                targetRemovedConn:Disconnect()
            end
            table.clear(livePetCache)
            humanoid.WalkSpeed = 16

            for _, part in ipairs(noclipParts) do
                if part and part.Parent and part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end)
    else
        Notify("Pet Protect", "Stopped", 3)
        addActivity("Auto Buy Pet stopped")
    end
end

ToggleButton.Activated:Connect(function()
    Theme.SetPetProtectEnabled(not petProtectEnabled)
end)

ForceHopButton.Activated:Connect(function()
    beginServerHop()
end)

ExportSettingsButton.Activated:Connect(function()
    saveSettings()
    local exported = nil
    pcall(function()
        if readfile and isfile and isfile(CONFIG_FILE) then
            exported = readfile(CONFIG_FILE)
        end
    end)
    if not exported then
        Notify("Settings Backup", "Could not read the settings file.", 3)
        return
    end

    local copy = setclipboard or toclipboard
    if type(copy) == "function" then
        local copied = pcall(copy, exported)
        if copied then
            Notify("Settings Backup", "Backup copied to clipboard.", 3)
            return
        end
    end

    BackupImportBox.Text = exported
    BackupImportModal.Visible = true
    Notify("Settings Backup", "Clipboard unavailable - copy the text manually.", 3)
end)

ImportSettingsButton.Activated:Connect(function()
    BackupImportBox.Text = ""
    BackupImportModal.Visible = true
end)

CancelImportButton.Activated:Connect(function()
    BackupImportModal.Visible = false
end)

ConfirmImportButton.Activated:Connect(function()
    local rawBackup = tostring(BackupImportBox.Text or "")
    local decodedOk, backupData = pcall(function()
        return HttpService:JSONDecode(rawBackup)
    end)
    if not decodedOk or type(backupData) ~= "table" then
        Notify("Settings Backup", "That backup text is not valid JSON.", 3)
        return
    end
    if not (writefile and isfolder and makefolder) then
        Notify("Settings Backup", "Your executor cannot save imported settings.", 3)
        return
    end

    local wrote = pcall(function()
        if not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
        writefile(CONFIG_FILE, rawBackup)
    end)
    if not wrote then
        Notify("Settings Backup", "Could not write the imported backup.", 3)
        return
    end

    local wasAutoBuyEnabled = petProtectEnabled
    loadSettings()
    local importedAutoBuyEnabled = petProtectEnabled

    PriceBox.Text = tostring(maxPetPrice)
    SpeedBox.Text = tostring(petWalkSpeed)
    RadiusBox.Text = tostring(petPunchRadius)
    rebuildTargetList()
    rebuildSellList()
    updateSellUI()
    updateRejoinUI()
    updatePetSizePriorityUI()
    updateJobIdsUI()
    rebuildJobIdList()
    updateCleanupUI()
    updateCFrameMoveUI()
    updateWebhookUI()
    if updateHistoryUI then updateHistoryUI() end
    if cleanupEnabled then setCleanupEnabled(true) end

    if wasAutoBuyEnabled ~= importedAutoBuyEnabled then
        Theme.SetPetProtectEnabled(importedAutoBuyEnabled)
    end
    BackupImportModal.Visible = false
    Notify("Settings Backup", "Backup restored successfully.", 3)
end)

loadSettings()

PriceBox.Text = tostring(maxPetPrice)
SpeedBox.Text = tostring(petWalkSpeed)
RadiusBox.Text = tostring(petPunchRadius)

rebuildTargetList()
rebuildSellList()
updateSellUI()
updateRejoinUI()
updatePetSizePriorityUI()
updateStatusUI()
updateJobIdsUI()
rebuildJobIdList()
if updateHistoryUI then updateHistoryUI() end
updateCleanupUI()
updateCFrameMoveUI()
updateWebhookUI()

do
    local core = type(_G.ScoopHubEnsureVisualFeaturesCore) == "function"
        and _G.ScoopHubEnsureVisualFeaturesCore()
        or nil
    if type(core) == "table" and type(core.SetWildPetESP) == "function" then
        pcall(core.SetWildPetESP, false)
    end
end
if cleanupEnabled then
    setCleanupEnabled(true)
end

task.spawn(function()
    while ScoopHubRunAlive() and ScreenGui.Parent do
        if autoSellEnabled then
            PetAutoSellRuntime.Refresh(false)
            PetAutoSellRuntime.Queue("safety")
            task.wait(PetAutoSellRuntime.SafetySeconds)
        else
            if PetAutoSellRuntime.HasSources() then
                PetAutoSellRuntime.Stop()
            end

            task.wait(2)
        end
    end

    PetAutoSellRuntime.Stop()
end)

if autoSellEnabled then
    PetAutoSellRuntime.Start()
end

do
    local DashboardPresentationGeneration = 0

    local function DashboardIsEffectivelyVisible()
        return Body
            and Body.Visible
            and AutoBuyPage
            and AutoBuyPage.Visible
    end

    local function RefreshDashboardPresentation()
        updateShecklesUI()

        local elapsedText = formatWebhookElapsed()
        if ElapsedLabel then
            ElapsedLabel.Text = elapsedText
        end
        if SessionNameLabel then
            SessionNameLabel.Text =
                LocalPlayer.Name .. " ● " .. elapsedText
        end
    end

    local function RestartDashboardPresentationWorker()
        DashboardPresentationGeneration += 1
        local myGeneration = DashboardPresentationGeneration

        if not DashboardIsEffectivelyVisible() then
            return
        end

        RefreshDashboardPresentation()

        task.spawn(function()
            while ScoopHubRunAlive()
                and ScreenGui.Parent
                and DashboardPresentationGeneration == myGeneration
                and DashboardIsEffectivelyVisible() do

                task.wait(0.5)

                if not ScoopHubRunAlive()
                    or not ScreenGui.Parent
                    or DashboardPresentationGeneration ~= myGeneration
                    or not DashboardIsEffectivelyVisible() then
                    break
                end

                RefreshDashboardPresentation()
            end
        end)
    end

    TrackConnection(
        Body:GetPropertyChangedSignal("Visible"):Connect(
            RestartDashboardPresentationWorker
        )
    )
    TrackConnection(
        AutoBuyPage:GetPropertyChangedSignal("Visible"):Connect(
            RestartDashboardPresentationWorker
        )
    )

    RestartDashboardPresentationWorker()
end

task.spawn(function()
    while ScoopHubRunAlive() and ScreenGui.Parent do
        if petProtectEnabled then
            local elapsedSinceSave =
                os.time() - lastAutoSaveAt

            if elapsedSinceSave >= 15 then
                lastAutoSaveAt = os.time()
                saveSettings()
                task.wait(1)
            else
                local remaining = math.max(
                    1,
                    15 - elapsedSinceSave
                )
                task.wait(remaining)
            end
        else
            task.wait(5)
        end
    end
end)

if resumePetProtectOnLoad then
    Theme.SetPetProtectEnabled(true)
end

_G.__ScoopHubSilentLog("[AutoBuyPet] Loaded: " .. tostring(isKRNL) .. " | SERVER HOPPING: " .. tostring(autoRejoin))
addActivity("Script loaded")
Notify("Loaded", "Settings restored: " .. tostring(isKRNL), 3)

_G.ScoopHubAutoBuyPetAPI = {
    SetEnabled = function(value)
        Theme.SetPetProtectEnabled(value == true)
    end,
    Toggle = function()
        Theme.SetPetProtectEnabled(not petProtectEnabled)
    end,
    ForceHop = function()
        beginServerHop()
    end,
    Save = function()
        saveSettings()
    end,
    SetCleanup = function(value)
        setCleanupEnabled(value == true)
        updateCleanupUI()
        saveSettings()
    end,
    IsCleanupEnabled = function()
        return cleanupEnabled == true
    end,
    SetWildPetESP = function(value)
        local core = type(_G.ScoopHubEnsureVisualFeaturesCore) == "function"
            and _G.ScoopHubEnsureVisualFeaturesCore()
            or nil
        if type(core) == "table" and type(core.SetWildPetESP) == "function" then
            return core.SetWildPetESP(value == true)
        end
        return false
    end,
    IsWildPetESPEnabled = function()
        local core = rawget(_G, "ScoopHubVisualFeaturesAPI")
        return type(core) == "table"
            and type(core.IsWildPetESPEnabled) == "function"
            and core.IsWildPetESPEnabled() == true
    end,
    IsEnabled = function()
        return petProtectEnabled
    end,
    OpenTab = function(tabName)
        local requested = string.upper(tostring(tabName or "DASHBOARD"))
        if requested ~= "DASHBOARD"
            and requested ~= "CONFIGS"
            and requested ~= "HISTORY"
            and requested ~= "WEBHOOK" then
            requested = "DASHBOARD"
        end
        setActiveTab(requested)
    end,
    GetStats = function()
        return {
            PetsBought = petsBought,
            Spent = totalSpent,
            ServerHops = serverHops,
            Runtime = autoBuyRuntimeSeconds + ((petProtectEnabled and autoBuyRuntimeStartedAt)
                and math.max(0, os.time() - autoBuyRuntimeStartedAt) or 0),
        }
    end,
}
end

local __autoBuyPetInitOk, __autoBuyPetInitErr = pcall(__ScoopHubInitAutoBuyPet)
if not __autoBuyPetInitOk then
    warn("[ScoopHub] Auto Buy Pet init error: " .. tostring(__autoBuyPetInitErr))
end

    return {
        GetAccentPreset = GetAccentPreset,
        ActiveAccentPreset = ActiveAccentPreset,
        AccentSelectedBg = AccentSelectedBg,
        AccentButtonBg = AccentButtonBg,
        AccentButtonBgHover = AccentButtonBgHover,
        AccentSoftStroke = AccentSoftStroke,
        AccentSoftStrokeAlt = AccentSoftStrokeAlt,
        CurrentAppliedAccentTheme = CurrentAppliedAccentTheme,
    }
end

return Module
