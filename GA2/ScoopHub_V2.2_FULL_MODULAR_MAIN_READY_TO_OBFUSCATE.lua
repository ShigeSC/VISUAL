--// ScoopHub V2.2 - Compact Unified GUI

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local LP = Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")

-- ScoopHub console mode: routine print/debug output is intentionally hidden.
-- Warnings/errors remain visible so real failures can still be diagnosed.
_G.__ScoopHubSilentLog = function(...) end

-- =========================================================
-- SCOOPHUB RE-EXECUTION CLEANUP / RUN GENERATION
--
-- A server teleport creates a new Roblox client DataModel, so the old server's
-- connections do not carry into the new server. This cleanup primarily protects
-- same-server manual re-execution / loader re-execution and long test sessions.
-- =========================================================
do
    local previousCleanup = rawget(_G, "ScoopHubCleanup")
    if type(previousCleanup) == "function" then
        pcall(previousCleanup, "reexecute")
    end
end

local SCOOPHUB_RUN_ID =
    tostring(os.clock()) .. ":" .. tostring(math.random(100000, 999999))

_G.ScoopHubRunId = SCOOPHUB_RUN_ID

local ScoopHubTrackedConnections = {}
local ScoopHubCleanupCallbacks = {}
local ScoopHubCleanupComplete = false

local function ScoopHubRunAlive()
    return _G.ScoopHubRunId == SCOOPHUB_RUN_ID and not ScoopHubCleanupComplete
end

local function TrackConnection(connection)
    if connection then
        ScoopHubTrackedConnections[#ScoopHubTrackedConnections + 1] = connection
    end
    return connection
end

local function RegisterScoopHubCleanup(callback)
    if type(callback) == "function" then
        ScoopHubCleanupCallbacks[#ScoopHubCleanupCallbacks + 1] = callback
    end
    return callback
end

local function CleanupScoopHub(reason)
    if ScoopHubCleanupComplete then
        return
    end
    ScoopHubCleanupComplete = true

    -- Disconnect service/workspace/inventory listeners first so the old run
    -- cannot react while its remaining workers are winding down.
    for index = #ScoopHubTrackedConnections, 1, -1 do
        local connection = ScoopHubTrackedConnections[index]
        pcall(function()
            connection:Disconnect()
        end)
        ScoopHubTrackedConnections[index] = nil
    end

    for index = #ScoopHubCleanupCallbacks, 1, -1 do
        pcall(ScoopHubCleanupCallbacks[index], reason)
        ScoopHubCleanupCallbacks[index] = nil
    end

    if _G.ScoopHubRunId == SCOOPHUB_RUN_ID then
        _G.ScoopHubRunId = nil
    end
end

_G.ScoopHubCleanup = CleanupScoopHub


-- =========================================================
-- SCOOPHUB AUTO-EXEC AFTER TELEPORT / SERVER HOP
-- Uses the same loader as the known-working Auto Buy Pet script.
-- queue_on_teleport is checked first, with common executor fallbacks.
-- =========================================================
local SCOOPHUB_AUTO_EXEC_URL =
    "https://raw.githubusercontent.com/yupie1558-beep/gag2/refs/heads/main/scoophubloader.lua"

local function getScoopHubQueueOnTeleport()
    if type(queue_on_teleport) == "function" then
        return queue_on_teleport
    end

    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        return syn.queue_on_teleport
    end

    if type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
        return fluxus.queue_on_teleport
    end

    return nil
end

local function queueScoopHubAfterTeleport()
    local queueFn = getScoopHubQueueOnTeleport()
    if type(queueFn) ~= "function" then
        warn("[ScoopHub] queue_on_teleport is unavailable in this executor.")
        return false
    end

    local queuedCode = [[
        repeat task.wait() until game:IsLoaded()
        task.wait(2)

        local ok, err = pcall(function()
            local source = game:HttpGet("]] .. SCOOPHUB_AUTO_EXEC_URL .. [[")
            local runner = loadstring(source)

            if type(runner) ~= "function" then
                error("loadstring did not return a function")
            end

            runner()
        end)

        if not ok then
            warn("[ScoopHub] Auto-execute after teleport failed: " .. tostring(err))
        end
    ]]

    local ok, err = pcall(function()
        queueFn(queuedCode)
    end)

    if ok then
        _G.__ScoopHubSilentLog("[ScoopHub] Script queued for automatic execution after teleport.")
        return true
    end

    warn("[ScoopHub] Failed to queue script after teleport: " .. tostring(err))
    return false
end

_G.ScoopHubQueueAfterTeleport = queueScoopHubAfterTeleport

local function parent()
    local ok, h = pcall(function() return gethui and gethui() end)
    return ok and h or LP:WaitForChild("PlayerGui")
end

local GP = parent()
if GP:FindFirstChild("ScoopHubV12") then GP.ScoopHubV12:Destroy() end

--==================================================
-- THEME - SAME AS POLISHED MAIL GUI
--==================================================

local T = {
    Bg=Color3.fromRGB(9,5,8), Panel=Color3.fromRGB(22,10,14),
    Line=Color3.fromRGB(154,44,53), Red=Color3.fromRGB(231,47,59),
    RedDark=Color3.fromRGB(145,28,39), Text=Color3.fromRGB(255,111,120),
    Dim=Color3.fromRGB(190,73,84), White=Color3.fromRGB(246,244,252),
    Muted=Color3.fromRGB(199,170,176), Success=Color3.fromRGB(99,215,163),
    Input=Color3.fromRGB(49,41,49), Surface2=Color3.fromRGB(37,17,23),
    Surface3=Color3.fromRGB(52,31,37), Stroke=Color3.fromRGB(179,52,63),
    Top=Color3.fromRGB(39,11,17), Mid=Color3.fromRGB(8,5,8),
    Low=Color3.fromRGB(34,8,11), Tab=Color3.fromRGB(35,16,22),
    Font=Enum.Font.GothamBold, Body=Enum.Font.Gotham
}

local GetAccentPreset
local ActiveAccentPreset, AccentSelectedBg, AccentButtonBg, AccentButtonBgHover, AccentSoftStroke, AccentSoftStrokeAlt
local CurrentAppliedAccentTheme = "Red"

local AccentThemePresets = {
    Red = {
        Name = "Red",
        Line = Color3.fromRGB(154, 44, 53),
        Red = Color3.fromRGB(231, 47, 59),
        RedDark = Color3.fromRGB(145, 28, 39),
        Text = Color3.fromRGB(255, 111, 120),
        Dim = Color3.fromRGB(190, 73, 84),
        Stroke = Color3.fromRGB(179, 52, 63),
        HubNameColor = Color3.fromRGB(242, 92, 101),
        UserActiveBg = Color3.fromRGB(59, 20, 25),
        UserActiveBgAlt = Color3.fromRGB(55, 22, 30),
        UserAccentButton = Color3.fromRGB(50, 14, 18),
        UserAccentButtonHover = Color3.fromRGB(74, 18, 24),
        UserSoftStroke = Color3.fromRGB(92, 67, 72),
        UserSoftStrokeAlt = Color3.fromRGB(83, 70, 74),
    },
    Dark = {
        Name = "Dark",
        Line = Color3.fromRGB(102, 102, 112),
        Red = Color3.fromRGB(155, 155, 165),
        RedDark = Color3.fromRGB(88, 88, 98),
        Text = Color3.fromRGB(225, 225, 235),
        Dim = Color3.fromRGB(163, 163, 173),
        Stroke = Color3.fromRGB(124, 124, 134),
        HubNameColor = Color3.fromRGB(195, 195, 205),
        UserActiveBg = Color3.fromRGB(52, 52, 58),
        UserActiveBgAlt = Color3.fromRGB(46, 46, 52),
        UserAccentButton = Color3.fromRGB(56, 56, 62),
        UserAccentButtonHover = Color3.fromRGB(74, 74, 82),
        UserSoftStroke = Color3.fromRGB(108, 108, 118),
        UserSoftStrokeAlt = Color3.fromRGB(96, 96, 106),
    },
    Purple = {
        Name = "Purple",
        Line = Color3.fromRGB(128, 72, 189),
        Red = Color3.fromRGB(174, 88, 255),
        RedDark = Color3.fromRGB(108, 54, 163),
        Text = Color3.fromRGB(224, 176, 255),
        Dim = Color3.fromRGB(182, 126, 228),
        Stroke = Color3.fromRGB(150, 92, 220),
        HubNameColor = Color3.fromRGB(200, 124, 255),
        UserActiveBg = Color3.fromRGB(54, 21, 77),
        UserActiveBgAlt = Color3.fromRGB(48, 20, 70),
        UserAccentButton = Color3.fromRGB(57, 20, 84),
        UserAccentButtonHover = Color3.fromRGB(79, 29, 113),
        UserSoftStroke = Color3.fromRGB(118, 89, 151),
        UserSoftStrokeAlt = Color3.fromRGB(108, 84, 142),
    },
    Ocean = {
        Name = "Ocean",
        Line = Color3.fromRGB(61, 108, 178),
        Red = Color3.fromRGB(70, 151, 255),
        RedDark = Color3.fromRGB(40, 96, 181),
        Text = Color3.fromRGB(168, 214, 255),
        Dim = Color3.fromRGB(118, 170, 224),
        Stroke = Color3.fromRGB(86, 134, 214),
        HubNameColor = Color3.fromRGB(106, 184, 255),
        UserActiveBg = Color3.fromRGB(19, 37, 62),
        UserActiveBgAlt = Color3.fromRGB(17, 33, 56),
        UserAccentButton = Color3.fromRGB(18, 42, 73),
        UserAccentButtonHover = Color3.fromRGB(24, 59, 98),
        UserSoftStroke = Color3.fromRGB(79, 107, 140),
        UserSoftStrokeAlt = Color3.fromRGB(73, 102, 136),
    },
}

local THEME_ORIG_PREFIX = "__ScoopHubThemeOrig_"
local THEME_APPLIED_PREFIX = "__ScoopHubThemeApplied_"
local THEME_SEQ_PREFIX = "__ScoopHubThemeSeq_"
local THEME_SEQ_APPLIED_PREFIX = "__ScoopHubThemeSeqApplied_"
local THEME_IGNORE_ATTRIBUTE = "__ScoopHubThemeIgnore"

local function themeColorToString(color)
    return string.format("%d,%d,%d",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function themeStringToColor(value)
    if type(value) ~= "string" then return nil end
    local r, g, b = value:match("^(%d+),(%d+),(%d+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

local function hueDistance(a, b)
    local d = math.abs(a - b)
    return math.min(d, 1 - d)
end

-- Anything in the red / ruby / burgundy / pink-red family is theme-owned.
-- This intentionally catches the dark red dropdown/card fills too, not only
-- exact T.Red values.
local function isRedFamilyColor(color)
    if typeof(color) ~= "Color3" then return false end
    local h, s, v = color:ToHSV()
    if v <= 0.025 or s < 0.10 then return false end
    return h <= 0.10 or h >= 0.82
end

local function isPresetFamilyColor(color, presetName)
    local preset = AccentThemePresets[presetName]
    if not preset or presetName == "Red" or presetName == "Dark" then return false end
    local h, s, v = color:ToHSV()
    local targetH, targetS = preset.Red:ToHSV()
    if v <= 0.025 or s < 0.08 or targetS < 0.08 then return false end
    return hueDistance(h, targetH) <= 0.075
end

local function recoverOriginalRedColor(color, oldThemeName)
    if isRedFamilyColor(color) then
        return color
    end

    if isPresetFamilyColor(color, oldThemeName) then
        local h, s, v = color:ToHSV()
        local _, targetS = AccentThemePresets[oldThemeName].Red:ToHSV()
        local _, baseRedS = AccentThemePresets.Red.Red:ToHSV()
        local ratio = targetS > 0.001 and (targetS / math.max(baseRedS, 0.001)) or 1
        local originalS = math.clamp(s / math.max(ratio, 0.05), 0, 1)
        return Color3.fromHSV(0, originalS, v)
    end

    return nil
end

local function transformOriginalThemeColor(original, themeName)
    if typeof(original) ~= "Color3" then return original end
    local preset = AccentThemePresets[themeName] or AccentThemePresets.Red
    if preset.Name == "Red" then
        return original
    end

    local _, sourceS, sourceV = original:ToHSV()
    local targetH, targetS = preset.Red:ToHSV()
    local _, baseRedS = AccentThemePresets.Red.Red:ToHSV()

    -- Keep the original brightness so deep burgundy panels stay dark and
    -- light red labels stay light. Only the hue/saturation family changes.
    local saturationScale = targetS / math.max(baseRedS, 0.001)
    local newS = math.clamp(sourceS * saturationScale, 0, 1)
    if preset.Name == "Dark" then
        newS = math.min(newS, 0.075)
    end
    return Color3.fromHSV(targetH, newS, sourceV)
end

local function serializeColorSequence(sequence)
    local parts = {}
    for _, kp in ipairs(sequence.Keypoints) do
        local c = kp.Value
        parts[#parts + 1] = string.format("%.6f,%d,%d,%d",
            kp.Time,
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5)
        )
    end
    return table.concat(parts, ";")
end

local function deserializeColorSequence(value)
    if type(value) ~= "string" or value == "" then return nil end
    local points = {}
    for part in value:gmatch("[^;]+") do
        local t, r, g, b = part:match("^([%d%.%-]+),(%d+),(%d+),(%d+)$")
        t, r, g, b = tonumber(t), tonumber(r), tonumber(g), tonumber(b)
        if t and r and g and b then
            points[#points + 1] = ColorSequenceKeypoint.new(
                math.clamp(t, 0, 1),
                Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
            )
        end
    end
    if #points >= 2 then
        return ColorSequence.new(points)
    end
    return nil
end

local function transformColorSequence(sequence, themeName)
    local points = {}
    for _, kp in ipairs(sequence.Keypoints) do
        local original = kp.Value
        points[#points + 1] = ColorSequenceKeypoint.new(
            kp.Time,
            isRedFamilyColor(original) and transformOriginalThemeColor(original, themeName) or original
        )
    end
    return ColorSequence.new(points)
end

local function currentRequestedThemeName()
    -- Theme switching was removed from the User page. ScoopHub now stays on
    -- its original red palette, while the existing color plumbing remains in
    -- place so older controls/helpers do not need to be refactored.
    return "Red"
end

local function themePropertyValue(instance, propertyName, rawValue, themeName, oldThemeName)
    if typeof(rawValue) == "Color3" then
        local originalAttribute = THEME_ORIG_PREFIX .. propertyName
        local appliedAttribute = THEME_APPLIED_PREFIX .. propertyName
        local storedOriginal = themeStringToColor(instance:GetAttribute(originalAttribute))
        local lastApplied = themeStringToColor(instance:GetAttribute(appliedAttribute))

        -- IMPORTANT: GUI controls change state after they are created (active tab,
        -- hover, selected row, disabled row, etc.). The old full-theme guard kept
        -- the FIRST red shade it saw forever, so 0.35s later it restored that old
        -- shade and made buttons/tabs appear to "go back". Detect a real property
        -- change and update/clear the tracked source color instead.
        if storedOriginal and lastApplied and themeColorToString(rawValue) ~= themeColorToString(lastApplied) then
            local changedOriginal = recoverOriginalRedColor(rawValue, oldThemeName or themeName or "Red")
            if changedOriginal then
                storedOriginal = changedOriginal
                pcall(function()
                    instance:SetAttribute(originalAttribute, themeColorToString(storedOriginal))
                end)
            else
                -- The control moved to a neutral/non-theme state. Stop owning this
                -- property until it becomes red/theme-colored again.
                pcall(function()
                    instance:SetAttribute(originalAttribute, nil)
                    instance:SetAttribute(appliedAttribute, nil)
                end)
                return rawValue, false
            end
        elseif not storedOriginal then
            storedOriginal = recoverOriginalRedColor(rawValue, oldThemeName or themeName or "Red")
            if not storedOriginal then
                return rawValue, false
            end
            pcall(function()
                instance:SetAttribute(originalAttribute, themeColorToString(storedOriginal))
            end)
        end

        local transformed = transformOriginalThemeColor(storedOriginal, themeName)
        pcall(function()
            instance:SetAttribute(appliedAttribute, themeColorToString(transformed))
        end)
        return transformed, true

    elseif typeof(rawValue) == "ColorSequence" then
        local originalAttribute = THEME_SEQ_PREFIX .. propertyName
        local appliedAttribute = THEME_SEQ_APPLIED_PREFIX .. propertyName
        local originalSequence = deserializeColorSequence(instance:GetAttribute(originalAttribute))
        local lastAppliedSequence = deserializeColorSequence(instance:GetAttribute(appliedAttribute))
        local rawSerialized = serializeColorSequence(rawValue)
        local lastSerialized = lastAppliedSequence and serializeColorSequence(lastAppliedSequence) or nil

        if originalSequence and lastSerialized and rawSerialized ~= lastSerialized then
            -- A callback changed this gradient after our previous pass. Treat the
            -- new gradient as the source only if it still contains a theme-owned
            -- color; otherwise release it as a neutral gradient.
            local hasThemeColor = false
            for _, kp in ipairs(rawValue.Keypoints) do
                if recoverOriginalRedColor(kp.Value, oldThemeName or themeName or "Red") then
                    hasThemeColor = true
                    break
                end
            end
            if hasThemeColor then
                local sourcePoints = {}
                for _, kp in ipairs(rawValue.Keypoints) do
                    local recovered = recoverOriginalRedColor(kp.Value, oldThemeName or themeName or "Red")
                    sourcePoints[#sourcePoints + 1] = ColorSequenceKeypoint.new(kp.Time, recovered or kp.Value)
                end
                originalSequence = ColorSequence.new(sourcePoints)
                pcall(function()
                    instance:SetAttribute(originalAttribute, serializeColorSequence(originalSequence))
                end)
            else
                pcall(function()
                    instance:SetAttribute(originalAttribute, nil)
                    instance:SetAttribute(appliedAttribute, nil)
                end)
                return rawValue, false
            end
        elseif not originalSequence then
            local sourcePoints = {}
            local hasThemeColor = false
            for _, kp in ipairs(rawValue.Keypoints) do
                local recovered = recoverOriginalRedColor(kp.Value, oldThemeName or themeName or "Red")
                if recovered then hasThemeColor = true end
                sourcePoints[#sourcePoints + 1] = ColorSequenceKeypoint.new(kp.Time, recovered or kp.Value)
            end
            if not hasThemeColor then
                return rawValue, false
            end
            originalSequence = ColorSequence.new(sourcePoints)
            pcall(function()
                instance:SetAttribute(originalAttribute, serializeColorSequence(originalSequence))
            end)
        end

        local transformed = transformColorSequence(originalSequence, themeName)
        pcall(function()
            instance:SetAttribute(appliedAttribute, serializeColorSequence(transformed))
        end)
        return transformed, true
    end
    return rawValue, false
end

local THEME_COLOR_PROPERTIES = {
    "BackgroundColor3",
    "TextColor3",
    "ImageColor3",
    "ScrollBarImageColor3",
    "PlaceholderColor3",
    "TextStrokeColor3",
    "BorderColor3",
    "Color",
}

local function applyDynamicThemeToInstance(instance, themeName, oldThemeName)
    if not instance then return end
    if instance:GetAttribute(THEME_IGNORE_ATTRIBUTE) == true then return end
    for _, propertyName in ipairs(THEME_COLOR_PROPERTIES) do
        local ok, value = pcall(function() return instance[propertyName] end)
        if ok and (typeof(value) == "Color3" or typeof(value) == "ColorSequence") then
            local transformed, changed = themePropertyValue(instance, propertyName, value, themeName, oldThemeName)
            if changed then
                pcall(function() instance[propertyName] = transformed end)
            end
        end
    end
end

local function applyDynamicThemeToTree(root, themeName, oldThemeName)
    if not root then return end
    applyDynamicThemeToInstance(root, themeName, oldThemeName)
    for _, instance in ipairs(root:GetDescendants()) do
        applyDynamicThemeToInstance(instance, themeName, oldThemeName)
    end
end

local function prepareThemedInstance(instance, props)
    local themeName = currentRequestedThemeName()
    for propertyName, rawValue in pairs(props or {}) do
        if typeof(rawValue) == "Color3" or typeof(rawValue) == "ColorSequence" then
            local transformed, changed = themePropertyValue(instance, propertyName, rawValue, themeName, "Red")
            if changed then
                props[propertyName] = transformed
            end
        end
    end
end

local W,H = 690,445
local HEADER,SIDE,GAP = 38,132,8

local function N(c,p,par)
    local x=Instance.new(c)
    p = p or {}
    prepareThemedInstance(x, p)
    for k,v in pairs(p) do x[k]=v end
    x.Parent=par
    return x
end

local function C(x,r) N("UICorner",{CornerRadius=UDim.new(0,r or 6)},x) return x end
local function S(x,col,tr,th) N("UIStroke",{Color=col or T.Line,Transparency=tr or 0,Thickness=th or 1},x) return x end
local function tw(x,p,t)
    p = p or {}
    prepareThemedInstance(x, p)
    TS:Create(x,TweenInfo.new(t or .14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),p):Play()
end

local function label(par,text,pos,size,ts,col,font,align)
    return N("TextLabel",{
        BackgroundTransparency=1,Text=text,Position=pos,Size=size,
        TextColor3=col or T.White,Font=font or T.Body,TextSize=ts or 10,
        TextXAlignment=align or Enum.TextXAlignment.Left
    },par)
end

local function gradient(x,a,b,rot)
    N("UIGradient",{Color=ColorSequence.new(a,b),Rotation=rot or 20},x)
end

local function panel(par,pos,size,title)
    local f=C(N("Frame",{Position=pos,Size=size,BackgroundColor3=T.Panel,
        BackgroundTransparency=.12,BorderSizePixel=0,ClipsDescendants=true},par),7)

    gradient(f,Color3.fromRGB(43,17,24),Color3.fromRGB(18,8,12))
    S(f,T.Line,.22,1.1)

    if title then
        label(f,title,UDim2.new(0,9,0,5),UDim2.new(1,-18,0,14),10,T.Text,T.Font)
    end
    return f
end

local function button(par,text,pos,size,col)
    local b=C(N("TextButton",{Text=text,Position=pos,Size=size,BackgroundColor3=col or T.Red,
        TextColor3=T.White,Font=T.Font,TextSize=10,BorderSizePixel=0,AutoButtonColor=false},par),5)
    return b
end

--==================================================
-- ROOT
--==================================================

--==================================================
-- NEW SCOOPHUB GUI LIBRARY SHELL
--==================================================
local SCOOPHUB_GUI_LIBRARY_URL = "https://raw.githubusercontent.com/rhiannamilagros-png/WW/refs/heads/main/scopsgui.lua"

local guiSourceOk, guiSource = pcall(function()
    return game:HttpGet(SCOOPHUB_GUI_LIBRARY_URL)
end)

if not guiSourceOk or type(guiSource) ~= "string" or guiSource == "" then
    error("[ScoopHub] Failed to download scopsgui.lua: " .. tostring(guiSource))
end

if type(loadstring) ~= "function" then
    error("[ScoopHub] This executor does not support loadstring.")
end

local guiChunk, guiCompileError = loadstring(guiSource)
if type(guiChunk) ~= "function" then
    error("[ScoopHub] scopsgui.lua compile error: " .. tostring(guiCompileError))
end

local guiLibraryOk, Library = pcall(guiChunk)
if not guiLibraryOk or type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
    error("[ScoopHub] scopsgui.lua failed to initialize: " .. tostring(Library))
end

if type(Library.Theme) == "table" then
    T = Library.Theme
end

local function ShutdownScoopHubFeatureApis()
    if _G.ScoopHubAutoBuyPetAPI then
        pcall(function() _G.ScoopHubAutoBuyPetAPI.SetEnabled(false) end)
        pcall(function() _G.ScoopHubAutoBuyPetAPI.Save() end)
    end
    if _G.ScoopHubMailAPI then
        pcall(function() _G.ScoopHubMailAPI.Shutdown() end)
    end
    if _G.ScoopHubInventoryAPI then
        pcall(function() _G.ScoopHubInventoryAPI.Stop() end)
    end
    if _G.ScoopHubShopAPI then
        pcall(function() _G.ScoopHubShopAPI.Stop() end)
    end
end

local Window = Library:CreateWindow({
    GuiName = "ScoopHubV12",
    BrandPrimary = "SCOOPHUB",
    BrandAccent = "PREMIUM",
    Version = "V2.2",
    Byline = "By Scoop",
    Discord = "discord.gg/WxgqUa9Qz",
    Logo = "rbxassetid://97406911955707",
    OnClose = function()
        ShutdownScoopHubFeatureApis()
        CleanupScoopHub("close")
    end,
})

if type(Window) ~= "table"
    or not Window.ScreenGui
    or not Window.Holder
    or not Window.Main
    or not Window.Header
    or not Window.Body
    or not Window.Side
then
    error("[ScoopHub] scopsgui.lua returned an incompatible window API.")
end

local SG = Window.ScreenGui
local Holder = Window.Holder
local Main = Window.Main
local Header = Window.Header
local Body = Window.Body
local Side = Window.Side
local stars = Window.Stars or Main:FindFirstChild("ScoopHubDecorativeStars")
local Scale = Holder:FindFirstChildOfClass("UIScale")

if not Scale then
    Scale = N("UIScale", {Scale=1}, Holder)
end

--==================================================
-- SCOOPHUB COMPACT PERFORMANCE HUD
-- Small always-visible HUD using the same ScoopHub accent/theme system.
-- Default placement is below the in-game chat/message panel at the top-left,
-- with a slightly larger size for better readability. It still remains visible
-- while the main window is minimized because it is parented directly to the ScreenGui.
--==================================================
do
    local RunService = game:GetService("RunService")
    local StatsService = game:GetService("Stats")

    local Hud = C(N("Frame",{
        Name="ScoopHubPerformanceHud",
        AnchorPoint=Vector2.new(0,0),
        Position=UDim2.new(0,14,0,348),
        Size=UDim2.fromOffset(248,34),
        BackgroundColor3=T.Panel,
        BackgroundTransparency=.08,
        BorderSizePixel=0,
        Active=true,
        ZIndex=900
    },SG),6)
    local HudScale=N("UIScale",{Scale=1},Hud)
    S(Hud,T.Line,.42,1)

    -- Match the main ScoopHub responsive scaling rules. Desktop keeps the normal
    -- GUI scale, while phones/tablets use the same extra 80% mobile reduction.
    local HUD_IS_MOBILE = UIS.TouchEnabled and (not UIS.KeyboardEnabled or not UIS.MouseEnabled)
    local HUD_MOBILE_SCALE = 0.80

    local function resizePerformanceHud()
        local camera=workspace.CurrentCamera
        if not camera then return end

        local viewport=camera.ViewportSize
        local baseScale=math.min((viewport.X-24)/W,(viewport.Y-24)/H)
        if HUD_IS_MOBILE then
            HudScale.Scale=math.clamp(baseScale*HUD_MOBILE_SCALE,.45,HUD_MOBILE_SCALE)
        else
            HudScale.Scale=math.clamp(baseScale,.55,1)
        end
    end

    resizePerformanceHud()
    TrackConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(resizePerformanceHud))
    task.defer(function()
        if workspace.CurrentCamera then
            TrackConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resizePerformanceHud))
        end
    end)
    N("UIGradient",{
        Color=ColorSequence.new({
            ColorSequenceKeypoint.new(0,Color3.fromRGB(38,15,21)),
            ColorSequenceKeypoint.new(1,Color3.fromRGB(15,8,11))
        }),
        Rotation=8
    },Hud)

    -- Thin ScoopHub accent strip, matching the main red/theme accent.
    C(N("Frame",{
        Name="Accent",
        Position=UDim2.new(0,4,0,4),
        Size=UDim2.new(0,4,1,-8),
        BackgroundColor3=T.Red,
        BorderSizePixel=0,
        ZIndex=902
    },Hud),2)

    local HubLabel=label(
        Hud,
        "ScoopHub",
        UDim2.new(0,17,0,0),
        UDim2.new(0,86,1,0),
        12,
        T.Text,
        T.Font
    )
    HubLabel.ZIndex=902

    local Divider1=N("Frame",{
        Position=UDim2.new(0,103,.5,-8),
        Size=UDim2.fromOffset(1,16),
        BackgroundColor3=T.Line,
        BackgroundTransparency=.30,
        BorderSizePixel=0,
        ZIndex=902
    },Hud)

    local FpsLabel=label(
        Hud,
        "-- fps",
        UDim2.new(0,112,0,0),
        UDim2.new(0,58,1,0),
        12,
        T.White,
        T.Body,
        Enum.TextXAlignment.Center
    )
    FpsLabel.ZIndex=902

    local Divider2=N("Frame",{
        Position=UDim2.new(0,179,.5,-8),
        Size=UDim2.fromOffset(1,14),
        BackgroundColor3=T.Line,
        BackgroundTransparency=.30,
        BorderSizePixel=0,
        ZIndex=902
    },Hud)

    local PingLabel=label(
        Hud,
        "-- ms",
        UDim2.new(0,188,0,0),
        UDim2.new(1,-194,1,0),
        12,
        T.Muted,
        T.Body,
        Enum.TextXAlignment.Center
    )
    PingLabel.ZIndex=902

    local function readPingMs()
        local value=nil
        pcall(function()
            local network=StatsService:FindFirstChild("Network")
            local serverStats=network and network:FindFirstChild("ServerStatsItem")
            local pingItem=serverStats and serverStats:FindFirstChild("Data Ping")
            if pingItem then
                local ok,result=pcall(function() return pingItem:GetValue() end)
                if ok then value=tonumber(result) end
                if not value then
                    local okString,resultString=pcall(function() return pingItem:GetValueString() end)
                    if okString then
                        value=tonumber(tostring(resultString):match("[%d%.]+"))
                    end
                end
            end
        end)
        return value and math.max(0,math.floor(value+.5)) or nil
    end

    local frames=0
    local elapsed=0
    TrackConnection(RunService.RenderStepped:Connect(function(dt)
        frames+=1
        elapsed+=dt
        if elapsed<0.50 then return end

        local fps=elapsed>0 and math.floor((frames/elapsed)+.5) or 0
        local ping=readPingMs()
        FpsLabel.Text=tostring(math.max(0,fps)).." fps"
        PingLabel.Text=ping and (tostring(ping).." ms") or "-- ms"

        frames=0
        elapsed=0
    end))

    -- Independent lightweight drag so the HUD can be placed anywhere without
    -- affecting the main ScoopHub window/launcher positions.
    local dragging=false
    local dragInput=nil
    local dragStart=nil
    local startPos=nil

    TrackConnection(Hud.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
            or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            dragInput=input.UserInputType==Enum.UserInputType.Touch and input or nil
            dragStart=input.Position
            startPos=Hud.Position
        end
    end))

    TrackConnection(UIS.InputEnded:Connect(function(input)
        local mouseEnded=input.UserInputType==Enum.UserInputType.MouseButton1 and dragInput==nil
        local touchEnded=input.UserInputType==Enum.UserInputType.Touch and input==dragInput
        if mouseEnded or touchEnded then
            dragging=false
            dragInput=nil
        end
    end))

    TrackConnection(UIS.InputChanged:Connect(function(input)
        if not dragging or not dragStart or not startPos then return end
        local movingMouse=input.UserInputType==Enum.UserInputType.MouseMovement and dragInput==nil
        local movingTouch=input.UserInputType==Enum.UserInputType.Touch and input==dragInput
        if not movingMouse and not movingTouch then return end

        local camera=workspace.CurrentCamera
        if not camera then return end

        local delta=input.Position-dragStart
        local viewport=camera.ViewportSize
        local width,height=248,34
        local baseX=viewport.X*startPos.X.Scale+startPos.X.Offset+delta.X
        local baseY=viewport.Y*startPos.Y.Scale+startPos.Y.Offset+delta.Y

        Hud.Position=UDim2.fromOffset(
            math.clamp(baseX,4,math.max(4,viewport.X-width-4)),
            math.clamp(baseY,height+4,math.max(height+4,viewport.Y-4))
        )
    end))
end

RegisterScoopHubCleanup(function(reason)
    -- Let scopsgui.lua release its own input/drag/minimize/search connections.
    if reason ~= "server_hop" then
        if Window and type(Window.Destroy) == "function" and not Window.Closed then
            pcall(function() Window:Destroy() end)
        elseif SG and SG.Parent then
            SG:Destroy()
        end
    end
end)

-- Holder / Scale / Main / stars now come from scopsgui.lua.
-- Low Graphics cleanup below still operates on the library's Stars frame.

local function disableDecorativeStars()
    if decorativeStarsDisabled then
        return
    end

    decorativeStarsDisabled = true

    -- Main background stars: 80 Frames + their UICorners.
    if stars and stars.Parent then
        stars.Visible = false
        for _, child in ipairs(stars:GetChildren()) do
            pcall(function()
                child:Destroy()
            end)
        end
    end

    -- Mail panel stars may already exist if Low Graphics was enabled after
    -- Mail initialized. This is a one-time cleanup scan, not a recurring loop.
    if SG and SG.Parent then
        for _, instance in ipairs(SG:GetDescendants()) do
            if instance.Name == "PanelStar" then
                pcall(function()
                    instance:Destroy()
                end)
            end
        end
    end
end

--==================================================
-- REMOTE VISUAL FEATURES BRIDGE
-- Upload ScoopHub_VisualFeatures_REMOTE.lua to GitHub, then replace the URL below.
-- Keeping this loader in the protected main file moves the heavy ESP / cleanup
-- implementations out of the MoonVeil input while preserving the same GUI APIs.
--==================================================
do
    local VISUAL_FEATURES_URL =
        "https://raw.githubusercontent.com/ShigeSC/VISUAL/refs/heads/main/gag2.lua"
    local moduleCache = nil
    local coreCache = nil

    _G.ScoopHubGetVisualFeaturesModule = function()
        if type(moduleCache) == "table" then
            return moduleCache
        end

        local url = tostring(
            rawget(_G, "ScoopHubVisualFeaturesURL")
            or VISUAL_FEATURES_URL
        )

        if url == "" or string.find(url, "PASTE_RAW_GITHUB_URL_HERE", 1, true) then
            warn("[ScoopHub] Visual features URL has not been configured yet.")
            return nil
        end

        local ok, result = pcall(function()
            local source = game:HttpGet(url)
            local chunk, compileError = loadstring(source)
            if type(chunk) ~= "function" then
                error("Visual features compile error: " .. tostring(compileError))
            end
            return chunk()
        end)

        if not ok or type(result) ~= "table" then
            warn("[ScoopHub] Failed to load remote visual features: " .. tostring(result))
            return nil
        end

        moduleCache = result
        return moduleCache
    end

    _G.ScoopHubEnsureVisualFeaturesCore = function()
        if type(coreCache) == "table" then
            return coreCache
        end

        local module = _G.ScoopHubGetVisualFeaturesModule()
        if type(module) ~= "table" or type(module.CreateCore) ~= "function" then
            return nil
        end

        local ok, result = pcall(module.CreateCore, {
            LP = LP,
            SG = SG,
            RunAlive = ScoopHubRunAlive,
            TrackConnection = TrackConnection,
            RegisterCleanup = RegisterScoopHubCleanup,
            DisableDecorativeStars = disableDecorativeStars,
            GetWildPetSpeciesName = function(pet)
                if type(getWildPetSpeciesName) == "function" then
                    return getWildPetSpeciesName(pet)
                end
                return pet and tostring(pet.Name or "Pet") or "Pet"
            end,
            GetWildPetSizeTier = function(pet)
                if type(getWildPetSizeTier) == "function" then
                    return getWildPetSizeTier(pet)
                end
                return nil
            end,
            GetPetRarity = function(pet)
                if type(getPetRarity) == "function" then
                    return getPetRarity(pet)
                end
                return "Unknown"
            end,
        })

        if not ok or type(result) ~= "table" then
            warn("[ScoopHub] Visual feature core failed to initialize: " .. tostring(result))
            return nil
        end

        coreCache = result
        _G.ScoopHubVisualFeaturesAPI = coreCache
        return coreCache
    end

    RegisterScoopHubCleanup(function()
        if type(coreCache) == "table" and type(coreCache.Destroy) == "function" then
            pcall(coreCache.Destroy)
        end
        coreCache = nil
        moduleCache = nil
        _G.ScoopHubVisualFeaturesAPI = nil
    end)
end

--==================================================
-- NEW LIBRARY TABS / PAGE BRIDGE
--==================================================
-- Existing game systems keep drawing into these Page frames.

local UserTab = Window:AddTab({Name="User",Icon="rbxassetid://17132521951",Order=10})
local AutomationTab = Window:AddTab({Name="Automation",Icon="rbxassetid://15332132816",Order=20})
local GardenTab = Window:AddTab({Name="Garden",Icon="rbxassetid://11330204834",Order=30})
local ShopTab = Window:AddTab({Name="Shop",Icon="rbxassetid://11385395241",Order=40})
local MailTab = Window:AddTab({Name="Mail",Icon="rbxassetid://16149098638",Order=50})
local AutoBuyPetTab = Window:AddTab({Name="Auto Buy Pet",Icon="rbxassetid://13001190533",Order=60})
local InventoryTab = Window:AddTab({Name="Inventory",Icon="rbxassetid://96943151264418",Order=70})
local ConfigTab = Window:AddTab({Name="Config",Icon="rbxassetid://98211971158539",Order=80})
local MiscTab = Window:AddTab({Name="Misc",Icon="rbxassetid://16717281575",Order=90})

local User = UserTab.Page
local Automation = AutomationTab.Page
local Garden = GardenTab.Page
local Shop = ShopTab.Page
local Mail = MailTab.Page
local Auto = AutoBuyPetTab.Page
local Inventory = InventoryTab.Page
local Configs = ConfigTab.Page
local Misc = MiscTab.Page

local Pages = {
    User = User,
    Automation = Automation,
    Garden = Garden,
    Shop = Shop,
    Mail = Mail,
    ["Auto Buy Pet"] = Auto,
    Inventory = Inventory,
    Config = Configs,
    Misc = Misc,
}

local NavData = {}
local active = "User"

local function open(name)
    if not Pages[name] then return end
    active = name
    if Window and type(Window.SelectTab) == "function" then
        Window:SelectTab(name)
    end
end

--==================================================
-- WORLD-SPECIFIC SHOP / PET CATALOG
-- Garden Valley and Fall Harvest intentionally use separate catalogs.
-- Kept in _G so the isolated Auto Buy Pet / Shop modules can share it
-- without adding long-lived root locals to this already-large Luau chunk.
--==================================================
do
    local GARDEN_VALLEY_PLACE_ID = 97598239454123
    local FALL_HARVEST_PLACE_ID = 126987765280963
    local FALL_HARVEST_ALT_PLACE_ID = 129343810645058

    local GardenValley = {
        Key = "GardenValley",
        Name = "Garden Valley",
        Supported = true,
        HasAuction = true,
        ReturnToGardenAfterSeedBuy = false,

        Seeds = {
            "Acorn", "Apple", "Bamboo", "Banana", "Blueberry", "Cactus", "Carrot", "Cherry",
            "Coconut", "Corn", "Dragon Fruit", "Dragon's Breath", "Fire Fern", "Grape",
            "Green Bean", "Hypno Bloom", "Mango", "Moon Bloom", "Mushroom", "Padding",
            "Pineapple", "Poison Apple", "Pomegranate", "Pudding", "Rocket Pop", "Star Fruit",
            "Strawberry", "Sun Bloom", "Sunflower", "Tomato", "Tulip", "Venom Spitter", "Venus Fly Trap",
        },

        Gears = {
            "Common Watering Can", "Common Sprinkler", "Sign", "Megaphone",
            "Uncommon Sprinkler", "Rare Sprinkler", "Legendary Sprinkler", "Super Sprinkler",
            "Trowel", "Speed Mushroom", "Jump Mushroom", "Gnome", "Shrink Mushroom",
            "Supersize Mushroom", "Wheelbarrow", "Strawberry Sniper", "Invisibility Mushroom",
            "Teleporter", "Legendary Pet Teleporter", "Mythic Pet Teleporter", "Super Pet Teleporter",
            "Super Watering Can", "Basic Pot", "Flashbang", "Player Magnet",
        },

        Crates = {
            "Arch Crate", "Bear Trap Crate", "Bench Crate", "Boombox Crate",
            "Bridge Crate", "Conveyor Crate", "Fence Crate", "Fourth Of July Crate",
            "Ladder Crate", "Light Crate", "Owner Door Crate", "Picture Frame Crate",
            "Roleplay Crate", "Seesaw Crate", "Sign Crate", "Spring Crate",
            "Teleporter Pad Crate", "Weather Machine Crate", "Wood Wall Crate",
        },

        -- Explicit Garden Valley pet catalog from the working reference.
        -- Runtime discovery can add newly replicated Garden pets, but Fall pets
        -- are never used as a static fallback here.
        StaticPets = {
            "Bunny", "Frog", "Owl", "Deer", "Turtle", "Bee", "Butterfly", "Robin",
            "BaldEagle", "Bear", "Firefly", "GoldenDragonfly", "Monkey", "Unicorn",
            "BlackDragon", "IceSerpent", "Raccoon", "Dog", "Dragonfly", "Fox",
            "Hedgehog", "ShadowDragon", "Squirrel", "Swan", "Turkey", "Wolf",
        },

        AuctionEggs = {
            "Common Egg", "Uncommon Egg", "Rare Egg", "Legendary Egg",
            "Mythic Egg", "Super Egg", "Secret Egg",
        },

        AuctionSeedPacks = {
            "Common Seed Pack", "Ghost Pepper Pack", "Legendary Seed Pack", "Moon Bloom",
            "Mythic Seed Pack", "Rare Seed Pack", "Secret Seed Pack", "Super Seed Pack",
            "Uncommon Seed Pack",
        },
    }

    local FallHarvest = {
        Key = "FallHarvestWorld",
        Name = "Fall Harvest World",
        Supported = true,
        HasAuction = false,
        ReturnToGardenAfterSeedBuy = true,

        Seeds = {
            "Maple Carrot", "Maple Strawberry", "Maple Blueberry", "Maple Tulip", "Maple Tomato", "Maple Apple",
            "Maple Bamboo", "Maple Corn", "Maple Cactus", "Maple Pineapple", "Maple Mushroom", "Maple Green Bean",
            "Maple Banana", "Maple Grape", "Maple Coconut", "Maple Mango", "Maple Dragon Fruit", "Atlantic Giant Pumpkin",
            "Maple Acorn", "Maple Cherry", "Maple Sunflower", "Maple Venus Fly Trap", "Maple Pomegranate", "Maple Poison Apple",
            "Maple Venom Spitter", "Conifer Cone", "Amber Cranberry",
        },

        Gears = {
            "Bull Horn", "Harp", "Legendary Magic Mail", "Megaphone", "Rare Magic Mail", "Sign",
            "Super Magic Mail", "Super Syrup Sprinkler", "Super Syrup Watering Can", "Syrup Sprinkler",
            "Syrup Watering Can", "Trowel", "Wheelbarrow", "Wind Staff",
        },

        Crates = {
            "Rake Crate", "Lantern Crate", "Fall Structure Crate", "Fall Cosmetic Crate", "Cobblestone Crate",
        },

        -- Deliberately empty: Fall pet names are discovered from the CURRENT
        -- Fall world instead of guessing Garden Valley names into the picker.
        StaticPets = {},
        AuctionEggs = {},
        AuctionSeedPacks = {},
    }

    local Unsupported = {
        Key = "Unsupported",
        Name = "Unsupported World",
        Supported = false,
        HasAuction = false,
        ReturnToGardenAfterSeedBuy = false,
        Seeds = {}, Gears = {}, Crates = {}, StaticPets = {},
        AuctionEggs = {}, AuctionSeedPacks = {},
    }

    local Current = ({
        [GARDEN_VALLEY_PLACE_ID] = GardenValley,
        [FALL_HARVEST_PLACE_ID] = FallHarvest,
        [FALL_HARVEST_ALT_PLACE_ID] = FallHarvest,
    })[game.PlaceId] or Unsupported

    local function cloneList(source)
        local result = {}
        for _, value in ipairs(source or {}) do
            result[#result + 1] = value
        end
        return result
    end

    local function cleanRuntimePetName(value)
        local text = tostring(value or "")
        text = text:gsub("^WildPet[_%s%-]*", "")
        text = text:gsub("[_%-]%d+$", "")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")

        -- Ignore UUID-like model names unless a real PetName/DisplayName
        -- attribute supplied the value.
        if #text >= 24 and text:match("^[%x%-]+$") then
            return ""
        end
        return text
    end

    local function getPetNames()
        local result, seen = {}, {}

        local function add(value, trusted)
            local text = tostring(value or "")
            if not trusted then
                text = cleanRuntimePetName(text)
            else
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
            end
            if text ~= "" and not seen[text] then
                seen[text] = true
                result[#result + 1] = text
            end
        end

        -- Runtime discovery is world-local because Workspace belongs to the
        -- current PlaceId. This is especially important in Fall Harvest where
        -- no Garden static fallback is allowed.
        local map = workspace:FindFirstChild("Map")
        local spawns = map and map:FindFirstChild("WildPetSpawns")
        if spawns then
            for _, object in ipairs(spawns:GetDescendants()) do
                if object:IsA("Model") then
                    local explicitName = object:GetAttribute("PetName")
                        or object:GetAttribute("WildPetName")
                        or object:GetAttribute("DisplayName")
                    if explicitName ~= nil then
                        add(explicitName, true)
                    elseif object:FindFirstChildWhichIsA("ProximityPrompt", true) then
                        add(object.Name, false)
                    end
                end
            end

            for _, object in ipairs(spawns:GetChildren()) do
                if object:IsA("Model") then
                    local explicitName = object:GetAttribute("PetName")
                        or object:GetAttribute("WildPetName")
                        or object:GetAttribute("DisplayName")
                    add(explicitName or object.Name, explicitName ~= nil)
                end
            end
        end

        for _, petName in ipairs(Current.StaticPets or {}) do
            add(petName, true)
        end

        table.sort(result, function(a, b)
            return string.lower(a) < string.lower(b)
        end)
        return result
    end

    local function filterAllowed(values, allowed)
        local allowedLookup = {}
        for _, name in ipairs(allowed or {}) do
            allowedLookup[tostring(name)] = true
        end

        local result, seen = {}, {}
        for _, name in ipairs(values or {}) do
            name = tostring(name)
            if allowedLookup[name] and not seen[name] then
                seen[name] = true
                result[#result + 1] = name
            end
        end
        return result
    end

    -- Shared catalog helpers used by Automation, Shop, Mail, and Auto Buy Pet.
    -- They all resolve from the CURRENT PlaceId so Fall Harvest never shows
    -- Garden Valley-only items and Garden Valley never shows Fall-only items.
    local function normalizeCatalogName(value)
        local text = tostring(value or "")
        text = text:gsub("%s*%[%d+%.?%d*%s*[Kk][Gg]%]%s*$", "")
        text = text:gsub("%s*[Ss]eed%s*$", "")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        return string.lower(text):gsub("[^%w]", "")
    end

    local function getMailAllowedLookup()
        local lookup = {}
        local function addList(list)
            for _, name in ipairs(list or {}) do
                local key = normalizeCatalogName(name)
                if key ~= "" then lookup[key] = true end
            end
        end

        addList(Current.Seeds)
        addList(Current.Gears)
        addList(Current.Crates)
        addList(Current.AuctionEggs)
        addList(Current.AuctionSeedPacks)
        addList(getPetNames())
        return lookup
    end

    local function getFruitAllowedLookup()
        local lookup = {}
        for _, seedName in ipairs(Current.Seeds or {}) do
            local key = normalizeCatalogName(seedName)
            if key ~= "" then
                lookup[key] = true
                -- Fall Harvest fruit runtime names often omit the "Maple"
                -- prefix even though the seed/tool is named "Maple X".
                if Current.Key == "FallHarvestWorld" then
                    local baseKey = key:gsub("^maple", "")
                    if baseKey ~= "" then lookup[baseKey] = true end
                end
            end
        end
        return lookup
    end

    local function getWorldSprinklers()
        local result = {}
        for _, gearName in ipairs(Current.Gears or {}) do
            if string.find(string.lower(tostring(gearName)), "sprinkler", 1, true) then
                result[#result + 1] = gearName
            end
        end
        return result
    end

    _G.ScoopHubWorldData = {
        GardenValleyPlaceId = GARDEN_VALLEY_PLACE_ID,
        FallHarvestPlaceId = FALL_HARVEST_PLACE_ID,
        FallHarvestAltPlaceId = FALL_HARVEST_ALT_PLACE_ID,
        Current = Current,
        GetPetNames = getPetNames,
        FilterAllowed = filterAllowed,
        CloneList = cloneList,
        NormalizeCatalogName = normalizeCatalogName,
        GetMailAllowedLookup = getMailAllowedLookup,
        GetFruitAllowedLookup = getFruitAllowedLookup,
        GetWorldSprinklers = getWorldSprinklers,
    }
end

--==================================================
-- USER PAGE - ACCOUNT / SESSION DASHBOARD
--==================================================
local function __ScoopHubInitUser()
    local Page = User
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local Workspace = game:GetService("Workspace")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    Page.ClipsDescendants = false

    local Prefs = _G.ScoopHubUserPrefs or {}
    -- Preferences start OFF on a fresh/re-executed script.
    -- Auto Rejoin / Low Graphics are restored only by the named Config loader.
    -- Theme selection was removed; the original ScoopHub red palette is fixed.
    Prefs.Notifications = false
    Prefs.Tooltips = false
    Prefs.Theme = "Red"
    _G.ScoopHubUserPrefs = Prefs
    _G.__ScoopHubRefreshUserThemeRows = nil

    -- Real session timer. Roblox time() advances continuously from client/game
    -- start and is independent of the User page. DistributedGameTime is kept as
    -- an additional source because it may already contain a larger elapsed value.
    -- The returned value is monotonic, so the display can never jump backwards or
    -- remain permanently at 00:00:00 because one source is unavailable.
    local initialTimeValue = math.max(0, tonumber(time()) or 0)
    local initialDistributedValue = math.max(0, tonumber(Workspace.DistributedGameTime) or 0)
    local sessionTimerFloor = math.max(initialTimeValue, initialDistributedValue)
    local sessionStartedAt = os.time() - math.floor(sessionTimerFloor)
    local lastPlaySeconds = sessionTimerFloor

    local function getLivePlaySeconds()
        local clientElapsed = math.max(0, tonumber(time()) or 0)
        local distributed = math.max(0, tonumber(Workspace.DistributedGameTime) or 0)

        -- V20: no hidden-page timer loop is needed to keep the local fallback
        -- advancing. sessionStartedAt is already anchored to the session floor,
        -- so wall-clock elapsed catches up instantly whenever User is shown.
        local wallElapsed = math.max(0, os.time() - sessionStartedAt)

        local elapsed = math.max(
            clientElapsed,
            distributed,
            wallElapsed,
            lastPlaySeconds
        )

        lastPlaySeconds = elapsed
        return elapsed
    end

    local accent = T.Red
    local accentDark = T.RedDark

    local function card(pos, size, title)
        local f = C(N("Frame", {
            Position = pos,
            Size = size,
            BackgroundColor3 = Color3.fromRGB(12, 12, 14),
            BackgroundTransparency = .08,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, Page), 7)
        local stroke = S(f, T.Red, .38, 1)
        local titleLabel = label(
            f,
            title,
            UDim2.new(0, 12, 0, 8),
            UDim2.new(1, -24, 0, 18),
            11,
            accent,
            T.Font
        )
        return f, stroke, titleLabel
    end

    local function hoverButton(parent, textValue, pos, size, red)
        local b = C(N("TextButton", {
            Text = textValue,
            Position = pos,
            Size = size,
            BackgroundColor3 = red and AccentButtonBg() or Color3.fromRGB(24, 22, 25),
            BackgroundTransparency = .08,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            TextColor3 = red and accent or T.White,
            Font = T.Font,
            TextSize = 10,
        }, parent), 5)
        S(b, red and accent or AccentSoftStroke(), red and .32 or .58, 1)
        b.MouseEnter:Connect(function()
            tw(b, {
                BackgroundColor3 = red and AccentButtonBgHover() or Color3.fromRGB(36, 31, 35)
            }, .1)
        end)
        b.MouseLeave:Connect(function()
            tw(b, {
                BackgroundColor3 = red and AccentButtonBg() or Color3.fromRGB(24, 22, 25)
            }, .1)
        end)
        return b
    end

    local function row(parent, titleText, valueText, y)
        label(parent, titleText, UDim2.new(0, 12, 0, y), UDim2.new(.42, -6, 0, 17), 10, T.Muted, T.Body)
        local v = label(parent, valueText, UDim2.new(.42, 0, 0, y), UDim2.new(.58, -12, 0, 17), 10, T.White, T.Body, Enum.TextXAlignment.Right)
        N("Frame", {
            Position = UDim2.new(0, 12, 0, y + 22),
            Size = UDim2.new(1, -24, 0, 1),
            BackgroundColor3 = Color3.fromRGB(68, 55, 59),
            BackgroundTransparency = .65,
            BorderSizePixel = 0,
        }, parent)
        return v
    end

    local function formatDuration(total)
        total = math.max(0, math.floor(tonumber(total) or 0))
        local h = math.floor(total / 3600)
        local m = math.floor((total % 3600) / 60)
        local s = total % 60
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    -- WORLD TELEPORTS ------------------------------------------------------
    -- Prefer the game's own Event Worlds button so its normal world-transfer
    -- flow runs first. TeleportService is used only as a fallback.
    local GARDEN_VALLEY_PLACE_ID = 97598239454123
    local FALL_HARVEST_PLACE_ID = 126987765280963
    local FALL_HARVEST_ALT_PLACE_ID = 129343810645058

    local function isCurrentWorld(placeId)
        if placeId == FALL_HARVEST_PLACE_ID then
            return game.PlaceId == FALL_HARVEST_PLACE_ID or game.PlaceId == FALL_HARVEST_ALT_PLACE_ID
        end
        return game.PlaceId == placeId
    end

    local function triggerEventWorldTeleport(worldName)
        local playerGui = LP:FindFirstChildOfClass("PlayerGui")
        local eventWorldsGui = playerGui and playerGui:FindFirstChild("EventWorldsTeleporter")
        local frame = eventWorldsGui and eventWorldsGui:FindFirstChild("Frame")
        local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
        if not scrollingFrame then return false end

        for _, worldFrame in ipairs(scrollingFrame:GetChildren()) do
            local mainFrame = worldFrame:FindFirstChild("Main_Frame") or worldFrame:FindFirstChild("Main_Frame", true)
            local nameLabel = mainFrame and mainFrame:FindFirstChild("Name", true)
            local teleportButton = mainFrame and mainFrame:FindFirstChild("TeleportButton", true)

            if nameLabel and teleportButton and nameLabel:IsA("TextLabel")
                and teleportButton:IsA("TextButton")
                and tostring(nameLabel.Text or ""):gsub("<[^>]->", "") == worldName then

                if type(firesignal) == "function" then
                    local ok = pcall(function()
                        firesignal(teleportButton.Activated)
                    end)
                    if ok then return true end
                end

                local center = teleportButton.AbsolutePosition + (teleportButton.AbsoluteSize / 2)
                local ok = pcall(function()
                    VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    task.wait(0.05)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                end)
                if ok then return true end
            end
        end

        return false
    end

    local function teleportToWorld(worldName, placeId, button)
        if isCurrentWorld(placeId) then
            local oldText = button.Text
            button.Text = "CURRENT WORLD"
            task.delay(1.1, function()
                if button.Parent then button.Text = oldText end
            end)
            return
        end

        local oldText = button.Text
        button.Text = "TELEPORTING..."

        task.spawn(function()
            -- Queue first because triggerEventWorldTeleport may teleport from
            -- the server side without giving this script another chance.
            queueScoopHubAfterTeleport()

            local started = triggerEventWorldTeleport(worldName)
            if not started then
                started = pcall(function()
                    TeleportService:Teleport(placeId, LP)
                end)
            end

            if not started then
                button.Text = "FAILED"
                task.wait(1.1)
            else
                task.wait(1.0)
            end

            if button.Parent then button.Text = oldText end
        end)
    end

    -- Header ---------------------------------------------------------------
    N("ImageLabel", {
        Image = "rbxassetid://17132521951",
        ImageColor3 = accent,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 3, 0, 4),
        Size = UDim2.fromOffset(31, 31),
    }, Page)

    local UserTitle = label(Page, "USER", UDim2.new(0, 41, 0, 4), UDim2.new(1, -45, 0, 20), 16, T.White, T.Font)
    label(Page, "Manage your account, preferences and session.", UDim2.new(0, 41, 0, 24), UDim2.new(1, -45, 0, 16), 10, T.Muted, T.Body)

    -- Player Info ----------------------------------------------------------
    local PlayerCard = card(UDim2.new(0, 0, 0, 49), UDim2.new(.5, -5, 0, 159), "PLAYER INFO")

    local AvatarTile = C(N("Frame", {
        Position = UDim2.new(0, 12, 0, 31),
        Size = UDim2.fromOffset(92, 72),
        BackgroundColor3 = Color3.fromRGB(26, 25, 28),
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, PlayerCard), 6)
    S(AvatarTile, Color3.fromRGB(85, 66, 72), .62, 1)

    N("ImageLabel", {
        Image = "rbxthumb://type=AvatarBust&id=" .. tostring(LP.UserId) .. "&w=180&h=180",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ScaleType = Enum.ScaleType.Fit,
    }, AvatarTile)

    label(PlayerCard, "Username", UDim2.new(0, 114, 0, 30), UDim2.new(1, -124, 0, 13), 9, T.Muted, T.Body)
    label(PlayerCard, tostring(LP.Name), UDim2.new(0, 114, 0, 43), UDim2.new(1, -124, 0, 15), 10, T.White, T.Font)
    label(PlayerCard, "User ID", UDim2.new(0, 114, 0, 60), UDim2.new(1, -124, 0, 13), 9, T.Muted, T.Body)
    label(PlayerCard, tostring(LP.UserId), UDim2.new(0, 114, 0, 73), UDim2.new(1, -124, 0, 15), 10, T.White, T.Font)
    label(PlayerCard, "Display Name", UDim2.new(0, 114, 0, 90), UDim2.new(1, -124, 0, 13), 9, T.Muted, T.Body)
    label(PlayerCard, tostring(LP.DisplayName), UDim2.new(0, 114, 0, 103), UDim2.new(1, -124, 0, 15), 10, T.White, T.Font)

    local CopyIdButton = hoverButton(PlayerCard, "COPY USER ID", UDim2.new(0, 12, 1, -30), UDim2.new(.5, -18, 0, 22), false)
    local RejoinButton = hoverButton(PlayerCard, "REJOIN", UDim2.new(.5, 6, 1, -30), UDim2.new(.5, -18, 0, 22), false)
    RejoinButton.TextColor3 = T.White
    local RejoinStroke = RejoinButton:FindFirstChildOfClass("UIStroke")
    if RejoinStroke then RejoinStroke:Destroy() end

    CopyIdButton.Activated:Connect(function()
        local copied = false
        if type(setclipboard) == "function" then
            copied = pcall(setclipboard, tostring(LP.UserId))
        elseif type(toclipboard) == "function" then
            copied = pcall(toclipboard, tostring(LP.UserId))
        end
        CopyIdButton.Text = copied and "COPIED" or tostring(LP.UserId)
        task.delay(1.15, function()
            if CopyIdButton.Parent then CopyIdButton.Text = "COPY USER ID" end
        end)
    end)

    RejoinButton.Activated:Connect(function()
        queueScoopHubAfterTeleport()
        pcall(function()
            if game.JobId and game.JobId ~= "" then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
            else
                TeleportService:Teleport(game.PlaceId, LP)
            end
        end)
    end)

    -- Session Info ---------------------------------------------------------
    local SessionCard = card(UDim2.new(.5, 5, 0, 49), UDim2.new(.5, -5, 0, 159), "SESSION INFO")
    local PlayTimeValue = row(SessionCard, "Play Time", "00:00:00", 31)
    row(SessionCard, "Join Time", os.date("%m/%d/%Y %I:%M:%S %p", sessionStartedAt), 55)
    row(SessionCard, "Place ID", tostring(game.PlaceId), 79)
    row(SessionCard, "Job ID", tostring(game.JobId or "-"), 103)

    -- Compact world buttons live in Session Info so the User page layout stays
    -- unchanged. Server Hop is kept beside them instead of creating another card.
    -- Leave a real gap between all three buttons. The old .34/.34/.32 split
    -- made FALL HARVEST and GARDEN VALLEY touch at common UI scales.
    local FallWorldButton = hoverButton(SessionCard, "FALL HARVEST", UDim2.new(0, 12, 1, -30), UDim2.new(.31, -8, 0, 22), false)
    local GardenWorldButton = hoverButton(SessionCard, "GARDEN VALLEY", UDim2.new(.31, 8, 1, -30), UDim2.new(.38, -8, 0, 22), false)
    local ServerHopButton = hoverButton(SessionCard, "SERVER HOP", UDim2.new(.69, 4, 1, -30), UDim2.new(.31, -16, 0, 22), false)
    FallWorldButton.TextSize = 9
    GardenWorldButton.TextSize = 9
    ServerHopButton.TextSize = 9

    if isCurrentWorld(FALL_HARVEST_PLACE_ID) then
        FallWorldButton.TextColor3 = accent
    elseif isCurrentWorld(GARDEN_VALLEY_PLACE_ID) then
        GardenWorldButton.TextColor3 = accent
    end

    FallWorldButton.Activated:Connect(function()
        teleportToWorld("Fall Harvest World", FALL_HARVEST_PLACE_ID, FallWorldButton)
    end)

    GardenWorldButton.Activated:Connect(function()
        teleportToWorld("Garden Valley", GARDEN_VALLEY_PLACE_ID, GardenWorldButton)
    end)

    ServerHopButton.Activated:Connect(function()
        if _G.ScoopHubAutoBuyPetAPI and _G.ScoopHubAutoBuyPetAPI.ForceHop then
            pcall(_G.ScoopHubAutoBuyPetAPI.ForceHop)
            return
        end

        task.spawn(function()
            ServerHopButton.Text = "SEARCHING..."
            local ok, body = pcall(function()
                return game:HttpGet("https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100")
            end)
            if ok then
                local decodedOk, payload = pcall(function() return HttpService:JSONDecode(body) end)
                if decodedOk and payload and type(payload.data) == "table" then
                    local choices = {}
                    for _, server in ipairs(payload.data) do
                        local playing = tonumber(server.playing) or 0
                        local maxPlayers = tonumber(server.maxPlayers) or 0
                        if server.id and server.id ~= game.JobId and playing < maxPlayers then
                            table.insert(choices, server)
                        end
                    end
                    table.sort(choices, function(a, b)
                        return (tonumber(a.playing) or 0) < (tonumber(b.playing) or 0)
                    end)
                    if choices[1] then
                        queueScoopHubAfterTeleport()
                        pcall(function()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, choices[1].id, LP)
                        end)
                    end
                end
            end
            task.wait(.8)
            if ServerHopButton.Parent then ServerHopButton.Text = "SERVER HOP" end
        end)
    end)

    -- Preferences ----------------------------------------------------------
    local PrefCard = card(UDim2.new(0, 0, 0, 217), UDim2.new(.5, -5, 1, -217), "PREFERENCES")

    local preferenceControls = {}
    local function preferenceToggle(titleText, description, y, initial, callback)
        label(PrefCard, titleText, UDim2.new(0, 12, 0, y), UDim2.new(1, -75, 0, 15), 10, T.White, T.Font)
        label(PrefCard, description, UDim2.new(0, 12, 0, y + 14), UDim2.new(1, -75, 0, 14), 8, T.Muted, T.Body)

        local b = C(N("TextButton", {
            Text = "",
            Position = UDim2.new(1, -58, 0, y + 3),
            Size = UDim2.fromOffset(43, 21),
            BackgroundColor3 = initial and accentDark or Color3.fromRGB(47, 43, 47),
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, PrefCard), 20)
        S(b, initial and accent or Color3.fromRGB(93, 77, 82), .48, 1)

        local knob = C(N("Frame", {
            AnchorPoint = Vector2.new(0, .5),
            Position = initial and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundColor3 = T.White,
            BorderSizePixel = 0,
        }, b), 20)

        local control = { Value = initial == true }
        function control:Set(value, fire)
            value = value == true
            if self.Value == value and fire ~= true then return end
            self.Value = value
            tw(b, { BackgroundColor3 = value and accentDark or Color3.fromRGB(47, 43, 47) }, .12)
            tw(knob, { Position = value and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0) }, .12)
            if fire and callback then callback(value) end
        end
        b.Activated:Connect(function() control:Set(not control.Value, true) end)
        table.insert(preferenceControls, control)
        return control
    end

    local miscSettings = nil
    if _G.ScoopHubMiscAPI and _G.ScoopHubMiscAPI.GetSettings then
        pcall(function() miscSettings = _G.ScoopHubMiscAPI.GetSettings() end)
    end
    miscSettings = type(miscSettings) == "table" and miscSettings or {}

    local AutoRejoinPreference = preferenceToggle(
        "Auto Rejoin",
        "Automatically rejoin after a disconnect.",
        31,
        miscSettings.AutoRejoin == true,
        function(value)
            if _G.ScoopHubMiscAPI and _G.ScoopHubMiscAPI.SetAutoRejoin then
                pcall(_G.ScoopHubMiscAPI.SetAutoRejoin, value)
            end
        end
    )

    local LowGraphicsPreference = preferenceToggle(
        "Low Graphics Mode",
        "Reduce world effects and decorative UI for better FPS.",
        66,
        miscSettings.Cleanup == true,
        function(value)
            if _G.ScoopHubMiscAPI and _G.ScoopHubMiscAPI.SetCleanup then
                pcall(_G.ScoopHubMiscAPI.SetCleanup, value)
            end
        end
    )

    preferenceToggle(
        "UI Notifications",
        "Keep ScoopHub notification preference enabled.",
        101,
        Prefs.Notifications == true,
        function(value) Prefs.Notifications = value end
    )

    preferenceToggle(
        "Show Tooltips",
        "Show helper descriptions where supported.",
        136,
        Prefs.Tooltips == true,
        function(value) Prefs.Tooltips = value end
    )

    -- Weather -------------------------------------------------------------
    -- Replaces the old Theme card. The compact card shows only the NEXT moon;
    -- VIEW ALL WEATHER opens a medium table with the next 10. Both surfaces
    -- share one tiny cached API response, so opening the popup never creates a
    -- second HTTP request.
    do
        local WEATHER_API_URL = "https://api.gag2.gg/api/live/weather"
        local WEATHER_REFRESH_SECONDS = 30
        local weatherRunning = true
        local weatherEvents = {}
        local weatherLastFetchUnix = nil
        local weatherLastError = nil

        local WeatherCard = card(
            UDim2.new(.5, 5, 0, 217),
            UDim2.new(.5, -5, 1, -217),
            "WEATHER"
        )

        label(
            WeatherCard,
            "EVENT",
            UDim2.new(0, 12, 0, 38),
            UDim2.new(0, 112, 0, 13),
            9,
            T.Muted,
            T.Font
        )
        label(
            WeatherCard,
            "TIME",
            UDim2.new(0, 130, 0, 38),
            UDim2.new(0, 68, 0, 13),
            9,
            T.Muted,
            T.Font,
            Enum.TextXAlignment.Center
        )
        label(
            WeatherCard,
            "LEFT",
            UDim2.new(0, 200, 0, 38),
            UDim2.new(1, -212, 0, 13),
            9,
            T.Muted,
            T.Font,
            Enum.TextXAlignment.Right
        )

        local CompactRow = C(N("Frame", {
            Position = UDim2.new(0, 12, 0, 56),
            Size = UDim2.new(1, -24, 0, 36),
            BackgroundColor3 = Color3.fromRGB(24, 22, 25),
            BackgroundTransparency = .18,
            BorderSizePixel = 0,
        }, WeatherCard), 5)
        S(CompactRow, AccentSoftStrokeAlt(), .67, 1)

        local CompactEvent = label(
            CompactRow,
            "Loading...",
            UDim2.new(0, 8, 0, 0),
            UDim2.new(0, 110, 1, 0),
            11,
            T.White,
            T.Font
        )
        CompactEvent.TextTruncate = Enum.TextTruncate.AtEnd
        CompactEvent.TextYAlignment = Enum.TextYAlignment.Center

        local CompactTime = label(
            CompactRow,
            "--:--",
            UDim2.new(0, 118, 0, 0),
            UDim2.new(0, 72, 1, 0),
            11,
            T.White,
            T.Body,
            Enum.TextXAlignment.Center
        )
        CompactTime.TextYAlignment = Enum.TextYAlignment.Center

        local CompactLeft = label(
            CompactRow,
            "--",
            UDim2.new(0, 190, 0, 0),
            UDim2.new(1, -198, 1, 0),
            11,
            T.White,
            T.Body,
            Enum.TextXAlignment.Right
        )
        CompactLeft.TextYAlignment = Enum.TextYAlignment.Center

        local ViewAllWeatherButton = C(N("TextButton", {
            Text = "VIEW ALL WEATHER",
            Position = UDim2.new(0, 12, 0, 105),
            Size = UDim2.new(1, -24, 0, 31),
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 10,
            TextStrokeTransparency = 1,
        }, WeatherCard), 5)
        local ViewAllWeatherStroke = S(ViewAllWeatherButton, T.Red, .42, 1)
        ViewAllWeatherButton.MouseEnter:Connect(function()
            tw(ViewAllWeatherButton, {BackgroundColor3 = T.Red, TextColor3 = T.White}, .12)
            if ViewAllWeatherStroke then
                tw(ViewAllWeatherStroke, {Transparency = .05, Thickness = 1.5}, .12)
            end
        end)
        ViewAllWeatherButton.MouseLeave:Connect(function()
            tw(ViewAllWeatherButton, {BackgroundColor3 = T.RedDark, TextColor3 = T.White}, .14)
            if ViewAllWeatherStroke then
                tw(ViewAllWeatherStroke, {Transparency = .42, Thickness = 1}, .14)
            end
        end)

        local CompactStatus = label(
            WeatherCard,
            "Connecting to live weather...",
            UDim2.new(0, 12, 0, 149),
            UDim2.new(1, -24, 0, 14),
            8,
            T.Muted,
            T.Body
        )
        CompactStatus.TextTruncate = Enum.TextTruncate.AtEnd

        -- Medium popup: large enough for all 10 rows, but still clearly smaller
        -- than the main ScoopHub window.
        local WeatherPopup = C(N("Frame", {
            Name = "ScoopHubWeatherPopup",
            AnchorPoint = Vector2.new(.5, .5),
            Position = UDim2.fromScale(.5, .5),
            Size = UDim2.fromOffset(540, 400),
            BackgroundColor3 = T.Bg,
            BackgroundTransparency = .02,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = false,
            Active = true,
            ZIndex = 700,
        }, Holder), 8)
        S(WeatherPopup, T.Stroke, .45, 1.1)
        N("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 15, 21)),
                ColorSequenceKeypoint.new(.55, Color3.fromRGB(17, 8, 11)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 9, 13)),
            }),
            Rotation = 12,
        }, WeatherPopup)

        local PopupHeader = N("Frame", {
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundColor3 = Color3.fromRGB(31, 12, 17),
            BackgroundTransparency = .08,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 701,
        }, WeatherPopup)

        local PopupTitle = label(
            PopupHeader,
            "WEATHER",
            UDim2.new(0, 14, 0, 7),
            UDim2.new(1, -58, 0, 19),
            14,
            T.Text,
            T.Font
        )
        PopupTitle.ZIndex = 702

        local PopupSubTitle = label(
            PopupHeader,
            "Next 10 upcoming moons",
            UDim2.new(0, 14, 0, 27),
            UDim2.new(1, -58, 0, 14),
            10,
            T.Muted,
            T.Body
        )
        PopupSubTitle.ZIndex = 702

        local PopupClose = C(N("TextButton", {
            Text = "×",
            Position = UDim2.new(1, -40, 0, 10),
            Size = UDim2.fromOffset(30, 28),
            BackgroundColor3 = Color3.fromRGB(40, 20, 25),
            BackgroundTransparency = .16,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            TextColor3 = T.Muted,
            Font = T.Font,
            TextSize = 17,
            ZIndex = 703,
        }, PopupHeader), 5)
        S(PopupClose, AccentSoftStrokeAlt(), .64, 1)

        local function popupHeader(textValue, x, width, alignment)
            local item = label(
                WeatherPopup,
                textValue,
                UDim2.new(0, x, 0, 58),
                UDim2.new(0, width, 0, 17),
                10,
                T.Muted,
                T.Font,
                alignment or Enum.TextXAlignment.Left
            )
            item.ZIndex = 702
            return item
        end

        popupHeader("#", 16, 26, Enum.TextXAlignment.Center)
        popupHeader("EVENT", 52, 194)
        popupHeader("TIME", 258, 102, Enum.TextXAlignment.Center)
        popupHeader("COUNTDOWN", 374, 150, Enum.TextXAlignment.Right)

        local PopupRows = {}
        for index = 1, 10 do
            local y = 80 + (index - 1) * 29
            local rowFrame = C(N("Frame", {
                Position = UDim2.new(0, 12, 0, y),
                Size = UDim2.new(1, -24, 0, 27),
                BackgroundColor3 = index % 2 == 1
                    and Color3.fromRGB(28, 18, 22)
                    or Color3.fromRGB(23, 16, 19),
                BackgroundTransparency = .20,
                BorderSizePixel = 0,
                ZIndex = 701,
            }, WeatherPopup), 4)

            local numberLabel = label(
                rowFrame,
                tostring(index),
                UDim2.new(0, 2, 0, 0),
                UDim2.new(0, 28, 1, 0),
                10,
                T.Muted,
                T.Body,
                Enum.TextXAlignment.Center
            )
            numberLabel.ZIndex = 702
            numberLabel.TextYAlignment = Enum.TextYAlignment.Center

            local eventLabel = label(
                rowFrame,
                "--",
                UDim2.new(0, 40, 0, 0),
                UDim2.new(0, 190, 1, 0),
                12,
                T.White,
                T.Font
            )
            eventLabel.ZIndex = 702
            eventLabel.TextYAlignment = Enum.TextYAlignment.Center
            eventLabel.TextTruncate = Enum.TextTruncate.AtEnd

            local timeLabel = label(
                rowFrame,
                "--:--",
                UDim2.new(0, 238, 0, 0),
                UDim2.new(0, 110, 1, 0),
                12,
                T.White,
                T.Body,
                Enum.TextXAlignment.Center
            )
            timeLabel.ZIndex = 702
            timeLabel.TextYAlignment = Enum.TextYAlignment.Center

            local countdownLabel = label(
                rowFrame,
                "--",
                UDim2.new(0, 360, 0, 0),
                UDim2.new(1, -370, 1, 0),
                12,
                T.White,
                T.Body,
                Enum.TextXAlignment.Right
            )
            countdownLabel.ZIndex = 702
            countdownLabel.TextYAlignment = Enum.TextYAlignment.Center

            PopupRows[index] = {
                Frame = rowFrame,
                Event = eventLabel,
                Time = timeLabel,
                Countdown = countdownLabel,
            }
        end

        local PopupStatus = label(
            WeatherPopup,
            "Live schedule • updates every 30s",
            UDim2.new(0, 14, 1, -28),
            UDim2.new(1, -28, 0, 16),
            9,
            T.Muted,
            T.Body
        )
        PopupStatus.ZIndex = 702

        local function nowUnix()
            local ok, value = pcall(function()
                return Workspace:GetServerTimeNow()
            end)
            if ok and tonumber(value) then
                return tonumber(value)
            end
            return os.time()
        end

        local function formatClock(boundary)
            boundary = tonumber(boundary)
            if not boundary then return "--:--" end

            local ok, value = pcall(function()
                return DateTime
                    .fromUnixTimestamp(math.floor(boundary))
                    :FormatLocalTime("LT", "en-us")
            end)

            if ok and type(value) == "string" and value ~= "" then
                return value
            end

            return os.date("%I:%M %p", math.floor(boundary)):gsub("^0", "")
        end

        local function formatCountdown(boundary, currentTime)
            local remaining = math.max(0, math.floor((tonumber(boundary) or 0) - currentTime))
            if remaining <= 0 then return "NOW" end

            local hours = math.floor(remaining / 3600)
            local minutes = math.floor((remaining % 3600) / 60)
            local seconds = remaining % 60

            if hours > 0 then
                return string.format("%dh %02dm", hours, minutes)
            elseif minutes > 0 then
                return string.format("%dm %02ds", minutes, seconds)
            end
            return string.format("%ds", seconds)
        end

        local function eventColor(name)
            local lowerName = string.lower(tostring(name or ""))
            if string.find(lowerName, "blood", 1, true) then
                return Color3.fromRGB(255, 95, 107)
            elseif string.find(lowerName, "gold", 1, true) then
                return Color3.fromRGB(245, 198, 86)
            elseif string.find(lowerName, "rainbow", 1, true) then
                return Color3.fromRGB(225, 137, 255)
            elseif string.find(lowerName, "mega", 1, true) then
                return Color3.fromRGB(242, 226, 191)
            end
            return T.White
        end

        local function futureEvents(currentTime, limit)
            local result = {}
            for _, entry in ipairs(weatherEvents) do
                if tonumber(entry.Boundary) and entry.Boundary > currentTime then
                    result[#result + 1] = entry
                    if #result >= limit then break end
                end
            end
            return result
        end

        local function refreshWeatherPresentation()
            if not (WeatherCard and WeatherCard.Parent) then return end

            local currentTime = nowUnix()
            local entries = futureEvents(currentTime, 10)
            local first = entries[1]

            if first then
                CompactEvent.Text = first.Name
                CompactEvent.TextColor3 = eventColor(first.Name)
                CompactTime.Text = formatClock(first.Boundary)
                CompactLeft.Text = formatCountdown(first.Boundary, currentTime)
            elseif weatherLastError and #weatherEvents == 0 then
                CompactEvent.Text = "Unavailable"
                CompactEvent.TextColor3 = T.Muted
                CompactTime.Text = "--:--"
                CompactLeft.Text = "--"
            else
                CompactEvent.Text = "No upcoming moon"
                CompactEvent.TextColor3 = T.Muted
                CompactTime.Text = "--:--"
                CompactLeft.Text = "--"
            end

            if weatherLastFetchUnix then
                CompactStatus.Text = weatherLastError
                    and "Using last schedule • reconnecting..."
                    or "Live schedule • updates every 30s"
            else
                CompactStatus.Text = weatherLastError
                    and "Weather API unavailable • retrying..."
                    or "Connecting to live weather..."
            end

            for index = 1, 10 do
                local row = PopupRows[index]
                local entry = entries[index]

                if entry then
                    row.Frame.Visible = true
                    row.Event.Text = entry.Name
                    row.Event.TextColor3 = eventColor(entry.Name)
                    row.Time.Text = formatClock(entry.Boundary)
                    row.Countdown.Text = formatCountdown(entry.Boundary, currentTime)
                else
                    row.Frame.Visible = true
                    row.Event.Text = "--"
                    row.Event.TextColor3 = T.Muted
                    row.Time.Text = "--:--"
                    row.Countdown.Text = "--"
                end
            end

            PopupStatus.Text = weatherLastError
                and "Live API reconnecting • showing last successful schedule"
                or "Live schedule • updates every 30s"
        end

        local function fetchUrl(url)
            if type(request) == "function" then
                local response = request({
                    Url = url,
                    Method = "GET",
                    Headers = {
                        ["Accept"] = "application/json",
                        ["Origin"] = "https://www.gag2.gg",
                        ["Referer"] = "https://www.gag2.gg/stock/weather",
                    },
                })
                local status = tonumber(response and (response.StatusCode or response.Status)) or 0
                if status >= 200 and status < 300 and type(response.Body) == "string" then
                    return response.Body
                end
                error("HTTP " .. tostring(status))
            end

            if type(http_request) == "function" then
                local response = http_request({
                    Url = url,
                    Method = "GET",
                    Headers = { ["Accept"] = "application/json" },
                })
                local status = tonumber(response and (response.StatusCode or response.Status)) or 0
                if status >= 200 and status < 300 and type(response.Body) == "string" then
                    return response.Body
                end
                error("HTTP " .. tostring(status))
            end

            if type(syn) == "table" and type(syn.request) == "function" then
                local response = syn.request({
                    Url = url,
                    Method = "GET",
                    Headers = { ["Accept"] = "application/json" },
                })
                local status = tonumber(response and (response.StatusCode or response.Status)) or 0
                if status >= 200 and status < 300 and type(response.Body) == "string" then
                    return response.Body
                end
                error("HTTP " .. tostring(status))
            end

            return game:HttpGet(url)
        end

        local function fetchWeatherSchedule()
            local ok, result = pcall(function()
                local body = fetchUrl(WEATHER_API_URL)
                local payload = HttpService:JSONDecode(body)
                local upcoming = payload
                    and payload.weather
                    and payload.weather.upcomingMoons

                if type(upcoming) ~= "table" then
                    error("upcomingMoons missing")
                end

                local parsed = {}
                for _, entry in ipairs(upcoming) do
                    local name = tostring(entry.name or "")
                    local boundary = tonumber(entry.boundary)
                    if name ~= "" and boundary then
                        parsed[#parsed + 1] = {
                            Name = name,
                            Boundary = boundary,
                        }
                    end
                end

                table.sort(parsed, function(a, b)
                    return a.Boundary < b.Boundary
                end)

                if #parsed == 0 then
                    error("empty upcomingMoons")
                end

                return parsed
            end)

            if ok and type(result) == "table" then
                weatherEvents = result
                weatherLastFetchUnix = nowUnix()
                weatherLastError = nil
            else
                weatherLastError = tostring(result)
            end

            refreshWeatherPresentation()
        end

        ViewAllWeatherButton.Activated:Connect(function()
            WeatherPopup.Visible = true
            refreshWeatherPresentation()
        end)

        PopupClose.Activated:Connect(function()
            WeatherPopup.Visible = false
        end)

        -- Lightweight drag for the popup. Delta is converted back through the
        -- main ScoopHub UIScale so mouse/touch movement stays correct on mobile.
        do
            local dragging = false
            local dragInput = nil
            local dragStart = nil
            local startPosition = nil

            TrackConnection(PopupHeader.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
                    dragStart = input.Position
                    startPosition = WeatherPopup.Position
                end
            end))

            TrackConnection(UIS.InputEnded:Connect(function(input)
                local mouseEnded = input.UserInputType == Enum.UserInputType.MouseButton1 and dragInput == nil
                local touchEnded = input.UserInputType == Enum.UserInputType.Touch and input == dragInput
                if mouseEnded or touchEnded then
                    dragging = false
                    dragInput = nil
                end
            end))

            TrackConnection(UIS.InputChanged:Connect(function(input)
                if not dragging or not dragStart or not startPosition then return end
                local movingMouse = input.UserInputType == Enum.UserInputType.MouseMovement and dragInput == nil
                local movingTouch = input.UserInputType == Enum.UserInputType.Touch and input == dragInput
                if not movingMouse and not movingTouch then return end

                local guiScale = (Scale and tonumber(Scale.Scale)) or 1
                if guiScale <= 0 then guiScale = 1 end
                local delta = (input.Position - dragStart) / guiScale

                WeatherPopup.Position = UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset + delta.X,
                    startPosition.Y.Scale,
                    startPosition.Y.Offset + delta.Y
                )
            end))
        end

        RegisterScoopHubCleanup(function()
            weatherRunning = false
            if WeatherPopup and WeatherPopup.Parent then
                WeatherPopup:Destroy()
            end
        end)

        -- One HTTP worker (~1-2 KB every 30 seconds). API failures never block
        -- ScoopHub and never clear the last successful schedule.
        task.spawn(function()
            while weatherRunning and ScoopHubRunAlive() do
                fetchWeatherSchedule()
                local waited = 0
                while weatherRunning and ScoopHubRunAlive() and waited < WEATHER_REFRESH_SECONDS do
                    task.wait(1)
                    waited += 1
                end
            end
        end)

        -- Countdown math is local only. Skip the UI work while both surfaces are
        -- hidden, but keep the API cache fresh in the background.
        task.spawn(function()
            while weatherRunning and ScoopHubRunAlive() do
                if Page.Visible or WeatherPopup.Visible then
                    refreshWeatherPresentation()
                end
                task.wait(1)
            end
        end)
    end

    -- V20 PERFORMANCE:
    -- User presentation is now visibility-driven. Hidden User no longer keeps
    -- two separate 2-second polling workers alive. When User becomes visible,
    -- one worker refreshes Play Time + mirrored Misc preferences immediately,
    -- then at 0.5s only for as long as this page remains visible.
    do
        local UserPresentationGeneration = 0

        local function RefreshUserPresentation()
            local ok, elapsed = pcall(getLivePlaySeconds)
            if ok then
                PlayTimeValue.Text = formatDuration(elapsed)
            else
                PlayTimeValue.Text = formatDuration(lastPlaySeconds)
            end

            if _G.ScoopHubMiscAPI and _G.ScoopHubMiscAPI.GetSettings then
                local settingsOk, current = pcall(_G.ScoopHubMiscAPI.GetSettings)
                if settingsOk and type(current) == "table" then
                    pcall(function()
                        AutoRejoinPreference:Set(
                            current.AutoRejoin == true,
                            false
                        )
                    end)
                    pcall(function()
                        LowGraphicsPreference:Set(
                            current.Cleanup == true,
                            false
                        )
                    end)
                end
            end
        end

        local function RestartUserPresentationWorker()
            UserPresentationGeneration += 1
            local myGeneration = UserPresentationGeneration

            if not Page.Visible then
                return
            end

            RefreshUserPresentation()

            task.spawn(function()
                while ScoopHubRunAlive()
                    and SG.Parent
                    and Page.Parent
                    and Page.Visible
                    and UserPresentationGeneration == myGeneration do

                    task.wait(0.5)

                    if not ScoopHubRunAlive()
                        or not SG.Parent
                        or not Page.Parent
                        or not Page.Visible
                        or UserPresentationGeneration ~= myGeneration then
                        break
                    end

                    RefreshUserPresentation()
                end
            end)
        end

        TrackConnection(
            Page:GetPropertyChangedSignal("Visible"):Connect(
                RestartUserPresentationWorker
            )
        )

        RestartUserPresentationWorker()
    end

    _G.__ScoopHubSilentLog("[ScoopHub] User dashboard initialized.")
end

--============================================================
-- REMOTE AUTO BUY PET
-- Tab position is NOT changed. The main shell still creates AUTO BUY PET at
-- Order=60; this module only fills that existing page and exports its API.
--============================================================
do
    local url = tostring(
        rawget(_G, "ScoopHubRemoteAutoBuyPetURL")
        or "https://raw.githubusercontent.com/ShigeSC/VISUAL/refs/heads/main/gag2pet.lua"
    )

    local ok, result = pcall(function()
        local source = game:HttpGet(url)
        if type(source) ~= "string" or source == "" then error("empty gag2pet.lua response") end
        local chunk, compileError = loadstring(source)
        if type(chunk) ~= "function" then error("gag2pet.lua compile error: " .. tostring(compileError)) end
        local module = chunk()
        if type(module) ~= "table" or type(module.Init) ~= "function" then
            error("gag2pet.lua returned an incompatible module")
        end

        local helpers = module.Init({
            T = T,
            TrackConnection = TrackConnection,
            RunAlive = ScoopHubRunAlive,
            RegisterCleanup = RegisterScoopHubCleanup,
            SG = SG,
            GP = GP,
            Auto = Auto,
            Scale = Scale,
            GetQueueOnTeleport = getScoopHubQueueOnTeleport,
            QueueAfterTeleport = queueScoopHubAfterTeleport,
            AccentThemePresets = AccentThemePresets,
            GetAccentPreset = GetAccentPreset,
            ActiveAccentPreset = ActiveAccentPreset,
            AccentSelectedBg = AccentSelectedBg,
            AccentButtonBg = AccentButtonBg,
            AccentButtonBgHover = AccentButtonBgHover,
            AccentSoftStroke = AccentSoftStroke,
            AccentSoftStrokeAlt = AccentSoftStrokeAlt,
            CurrentAppliedAccentTheme = CurrentAppliedAccentTheme,
            CurrentRequestedThemeName = currentRequestedThemeName,
            PrepareThemedInstance = prepareThemedInstance,
            ApplyDynamicThemeToInstance = applyDynamicThemeToInstance,
        })

        if type(helpers) == "table" then
            GetAccentPreset = helpers.GetAccentPreset or GetAccentPreset
            ActiveAccentPreset = helpers.ActiveAccentPreset or ActiveAccentPreset
            AccentSelectedBg = helpers.AccentSelectedBg or AccentSelectedBg
            AccentButtonBg = helpers.AccentButtonBg or AccentButtonBg
            AccentButtonBgHover = helpers.AccentButtonBgHover or AccentButtonBgHover
            AccentSoftStroke = helpers.AccentSoftStroke or AccentSoftStroke
            AccentSoftStrokeAlt = helpers.AccentSoftStrokeAlt or AccentSoftStrokeAlt
            CurrentAppliedAccentTheme = helpers.CurrentAppliedAccentTheme or CurrentAppliedAccentTheme
        end

        _G.ScoopHubRemoteAutoBuyPetModule = module
        return true
    end)

    -- Theme helpers are also used by User/Automation/remote pages. Keep safe
    -- red-palette fallbacks if the Auto Buy module cannot be downloaded.
    if type(GetAccentPreset) ~= "function" then
        GetAccentPreset = function(themeName)
            return AccentThemePresets[themeName] or AccentThemePresets.Red
        end
    end
    if type(ActiveAccentPreset) ~= "function" then
        ActiveAccentPreset = function() return GetAccentPreset("Red") end
    end
    if type(AccentSelectedBg) ~= "function" then
        AccentSelectedBg = function() return ActiveAccentPreset().UserActiveBgAlt end
    end
    if type(AccentButtonBg) ~= "function" then
        AccentButtonBg = function() return ActiveAccentPreset().UserAccentButton end
    end
    if type(AccentButtonBgHover) ~= "function" then
        AccentButtonBgHover = function() return ActiveAccentPreset().UserAccentButtonHover end
    end
    if type(AccentSoftStroke) ~= "function" then
        AccentSoftStroke = function() return ActiveAccentPreset().UserSoftStroke end
    end
    if type(AccentSoftStrokeAlt) ~= "function" then
        AccentSoftStrokeAlt = function() return ActiveAccentPreset().UserSoftStrokeAlt end
    end

    if not ok then
        warn("[ScoopHub] Remote Auto Buy Pet failed: " .. tostring(result))
    end

    RegisterScoopHubCleanup(function()
        _G.ScoopHubRemoteAutoBuyPetModule = nil
    end)
end

--============================================================
-- REMOTE MAIL
-- MAIL remains Order=50 in the sidebar. Only its implementation moved out.
--============================================================
do
    local url = tostring(
        rawget(_G, "ScoopHubRemoteMailURL")
        or "https://raw.githubusercontent.com/ShigeSC/VISUAL/refs/heads/main/gag2mail.lua"
    )

    local ok, result = pcall(function()
        local source = game:HttpGet(url)
        if type(source) ~= "string" or source == "" then error("empty gag2mail.lua response") end
        local chunk, compileError = loadstring(source)
        if type(chunk) ~= "function" then error("gag2mail.lua compile error: " .. tostring(compileError)) end
        local module = chunk()
        if type(module) ~= "table" or type(module.Init) ~= "function" then
            error("gag2mail.lua returned an incompatible module")
        end
        module.Init({
            TrackConnection = TrackConnection,
            RunAlive = ScoopHubRunAlive,
            PrepareThemedInstance = prepareThemedInstance,
            GP = GP,
            Mail = Mail,
            SG = SG,
        })
        _G.ScoopHubRemoteMailModule = module
        return true
    end)

    if not ok then
        warn("[ScoopHub] Remote Mail failed: " .. tostring(result))
    end

    RegisterScoopHubCleanup(function()
        _G.ScoopHubRemoteMailModule = nil
    end)
end

--============================================================
-- REMOTE AUTOMATION
-- AUTOMATION remains Order=20 in the sidebar. Only its implementation moved.
--============================================================
do
    local url = tostring(
        rawget(_G, "ScoopHubRemoteAutomationURL")
        or "https://raw.githubusercontent.com/ShigeSC/VISUAL/refs/heads/main/gag2auto.lua"
    )

    local ok, result = pcall(function()
        local source = game:HttpGet(url)
        if type(source) ~= "string" or source == "" then error("empty gag2auto.lua response") end
        local chunk, compileError = loadstring(source)
        if type(chunk) ~= "function" then error("gag2auto.lua compile error: " .. tostring(compileError)) end
        local module = chunk()
        if type(module) ~= "table" or type(module.Init) ~= "function" then
            error("gag2auto.lua returned an incompatible module")
        end
        module.Init({
            T = T,
            N = N,
            C = C,
            S = S,
            Tween = tw,
            Label = label,
            Button = button,
            Panel = panel,
            Automation = Automation,
            SG = SG,
            Scale = Scale,
            Players = Players,
            UIS = UIS,
            TrackConnection = TrackConnection,
            RegisterCleanup = RegisterScoopHubCleanup,
            RunAlive = ScoopHubRunAlive,
            AccentSelectedBg = AccentSelectedBg,
        })
        _G.ScoopHubRemoteAutomationModule = module
        return true
    end)

    if not ok then
        warn("[ScoopHub] Remote Automation failed: " .. tostring(result))
    end

    RegisterScoopHubCleanup(function()
        _G.ScoopHubRemoteAutomationModule = nil
    end)
end

--==================================================
-- REMOTE GARDEN / SHOP / INVENTORY PAGES
-- The sidebar tabs stay in the original positions. Each module only fills the
-- already-created page, which also keeps each MoonVeil input well under 200k.
--==================================================
do
    local function loadPageModule(fileName, overrideKey, bridge)
        local base = "https://raw.githubusercontent.com/ShigeSC/VISUAL/refs/heads/main/"
        local url = tostring(rawget(_G, overrideKey) or (base .. fileName))
        local ok, result = pcall(function()
            local source = game:HttpGet(url)
            if type(source) ~= "string" or source == "" then error("empty " .. fileName .. " response") end
            local chunk, compileError = loadstring(source)
            if type(chunk) ~= "function" then error(fileName .. " compile error: " .. tostring(compileError)) end
            local module = chunk()
            if type(module) ~= "table" or type(module.Init) ~= "function" then
                error(fileName .. " returned an incompatible module")
            end
            module.Init(bridge)
            return module
        end)
        if not ok then
            warn("[ScoopHub] Remote " .. fileName .. " failed: " .. tostring(result))
            return nil
        end
        return result
    end

    _G.ScoopHubRemoteGardenModule = loadPageModule(
        "gag2garden.lua",
        "ScoopHubRemoteGardenURL",
        {
            Pages = Pages,
            LP = LP,
            T = T,
            N = N,
            C = C,
            S = S,
            Tween = tw,
            Label = label,
            Gradient = gradient,
            TrackConnection = TrackConnection,
            RegisterCleanup = RegisterScoopHubCleanup,
            RunAlive = ScoopHubRunAlive,
        }
    )

    _G.ScoopHubRemoteShopModule = loadPageModule(
        "gag2shop.lua",
        "ScoopHubRemoteShopURL",
        {
            Shop = Shop,
            SG = SG,
            Scale = Scale,
            UIS = UIS,
            T = T,
            N = N,
            C = C,
            S = S,
            Tween = tw,
            Label = label,
            Panel = panel,
            TrackConnection = TrackConnection,
            RegisterCleanup = RegisterScoopHubCleanup,
            RunAlive = ScoopHubRunAlive,
            AccentSelectedBg = AccentSelectedBg,
        }
    )

    _G.ScoopHubRemoteInventoryModule = loadPageModule(
        "gag2inventory.lua",
        "ScoopHubRemoteInventoryURL",
        {
            Inventory = Inventory,
            LP = LP,
            T = T,
            N = N,
            C = C,
            S = S,
            Tween = tw,
            Label = label,
            Gradient = gradient,
            Panel = panel,
            TrackConnection = TrackConnection,
            RegisterCleanup = RegisterScoopHubCleanup,
            Notify = function(title, content)
                warn("[ScoopHub] " .. tostring(title or "Notice") .. ": " .. tostring(content or ""))
            end,
        }
    )

    RegisterScoopHubCleanup(function()
        _G.ScoopHubRemoteGardenModule = nil
        _G.ScoopHubRemoteShopModule = nil
        _G.ScoopHubRemoteInventoryModule = nil
    end)
end

--==================================================
-- MISC PAGE
--==================================================
local function __ScoopHubInitMisc()
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local RunService = game:GetService("RunService")
    local GuiService = game:GetService("GuiService")
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local State = _G.ScoopHubMiscState or {
        AutoRejoin = false,
        WalkSpeed = 16,
        JumpPower = 50,
        NoClip = false,
        InfiniteJump = false,
        FPS = "60",
        RemoveOtherGardens = false,
        BackpackValueESP = false,
        GardenESPEnabled = false,
        GardenESPFruitAll = false,
        GardenESPFruits = {},
        GardenESPMutationAll = true,
        GardenESPMutations = {},
    }
    _G.ScoopHubMiscState = State

    -- Preference toggles begin OFF each execution. Named Config auto-load runs
    -- after User/Misc initialization and may explicitly restore AutoRejoin.
    State.AutoRejoin = false
    State.BackpackValueESP = false
    State.GardenESPEnabled = false
    State.GardenESPFruitAll = false
    State.GardenESPFruits = {}
    State.GardenESPMutationAll = true
    State.GardenESPMutations = {}

    State.WalkSpeed = tonumber(State.WalkSpeed) or 16
    State.JumpPower = tonumber(State.JumpPower) or 50
    State.FPS = tostring(State.FPS or "60")

    local Page = Misc
    Page.ClipsDescendants = false

    local Title = label(
        Page,
        "MISC OPTIONS",
        UDim2.new(0, 4, 0, 1),
        UDim2.new(1, -8, 0, 20),
        11,
        T.Text,
        T.Font
    )

    local Divider = N("Frame", {
        Position = UDim2.new(0, 4, 0, 22),
        Size = UDim2.new(1, -8, 0, 1),
        BackgroundColor3 = T.Red,
        BackgroundTransparency = .5,
        BorderSizePixel = 0,
    }, Page)

    -- Misc keeps 65px cards and scrolling, but the layout is now styled more
    -- like Config: cleaner outer margins, a reserved scrollbar gutter, and a
    -- padded content area so the cards do not feel cramped against the page.
    local CARD_H = 65
    local ROW_GAP = 4
    local START_Y = 0
    local MISC_ROWS = 7
    local GARDEN_ESP_CARD_H = 170
    local CONTENT_H =
        ((MISC_ROWS - 1) * CARD_H)
        + ((MISC_ROWS - 1) * ROW_GAP)
        + GARDEN_ESP_CARD_H

    local MiscScroll = N("ScrollingFrame", {
        Name = "MiscScroll",
        Position = UDim2.new(0, 0, 0, 28),
        Size = UDim2.new(1, 0, 1, -28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, CONTENT_H + 8),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Red,
        ScrollBarImageTransparency = .18,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        VerticalScrollBarInset = Enum.ScrollBarInset.Always,
        ClipsDescendants = true,
        ZIndex = 1,
    }, Page)

    local MiscContent = N("Frame", {
        Name = "MiscContent",
        -- 1px inset keeps the card UIStroke inside the ScrollingFrame clip.
        -- Without this, the left/top half of the 1px stroke is clipped at x/y=0.
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -10, 0, CONTENT_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
    }, MiscScroll)

    local function card(col, row, titleText, description)
        local xScale = col == 1 and 0 or .5
        local xOffset = col == 1 and 0 or 3
        local widthOffset = -3
        local y = START_Y + ((row - 1) * (CARD_H + ROW_GAP))

        local f = C(N("Frame", {
            Position = UDim2.new(xScale, xOffset, 0, y),
            Size = UDim2.new(.5, widthOffset, 0, CARD_H),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = .06,
            BorderSizePixel = 0,
            ClipsDescendants = false,
            ZIndex = 2,
        }, MiscContent), 7)
        S(f, T.Line, .48, 1)

        N("Frame", {
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(0, 32, 0, 2),
            BackgroundColor3 = T.Red,
            BackgroundTransparency = .18,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, f)

        label(
            f,
            titleText,
            UDim2.new(0, 10, 0, 8),
            UDim2.new(1, -20, 0, 18),
            11,
            T.White,
            T.Font
        )

        if description and description ~= "" then
            local desc = label(
                f,
                description,
                UDim2.new(0, 10, 0, 25),
                UDim2.new(1, -20, 0, 26),
                9,
                T.Muted,
                T.Body
            )
            desc.TextWrapped = true
            desc.TextYAlignment = Enum.TextYAlignment.Top
        end

        return f
    end

    local function makeToggle(parent, initial, onChanged)
        local value = initial == true

        local b = C(N("TextButton", {
            Text = "",
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, .5),
            Position = UDim2.new(1, -9, .5, 6),
            Size = UDim2.fromOffset(43, 22),
            BackgroundColor3 = value and T.Red or T.Surface3,
            BorderSizePixel = 0,
            ZIndex = 5,
        }, parent), 11)

        local knob = C(N("Frame", {
            AnchorPoint = Vector2.new(0, .5),
            Position = value and UDim2.new(1, -20, .5, 0) or UDim2.new(0, 3, .5, 0),
            Size = UDim2.fromOffset(17, 17),
            BackgroundColor3 = T.White,
            BorderSizePixel = 0,
            ZIndex = 6,
        }, b), 9)

        local control = {}

        function control:Set(newValue, fireCallback)
            value = newValue == true
            b.BackgroundColor3 = value and T.Red or T.Surface3
            tw(knob, {
                Position = value and UDim2.new(1, -20, .5, 0) or UDim2.new(0, 3, .5, 0),
            }, .12)

            if fireCallback ~= false and onChanged then
                onChanged(value)
            end
        end

        function control:Get()
            return value
        end

        b.Activated:Connect(function()
            control:Set(not value, true)
        end)

        return control
    end

    local function makeValueBox(parent, textValue, onCommit)
        local box = C(N("TextBox", {
            Text = tostring(textValue),
            ClearTextOnFocus = false,
            Font = T.Font,
            TextSize = 10,
            TextColor3 = T.White,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = T.Input,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 9, 0, 34),
            Size = UDim2.new(1, -18, 0, 20),
            ZIndex = 4,
        }, parent), 5)
        N("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)
        S(box, T.Line, .72, 1)

        box.FocusLost:Connect(function()
            if onCommit then
                onCommit(box)
            end
        end)

        return box
    end

    local function makeAction(parent, textValue, callback)
        local b = C(N("TextButton", {
            Text = textValue,
            AutoButtonColor = false,
            Font = T.Font,
            TextSize = 10,
            TextColor3 = T.White,
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 9, 0, 34),
            Size = UDim2.new(1, -18, 0, 20),
            ZIndex = 4,
        }, parent), 5)
        S(b, T.Red, .45, 1)

        b.MouseEnter:Connect(function()
            tw(b, { BackgroundColor3 = T.Red }, .1)
        end)
        b.MouseLeave:Connect(function()
            tw(b, { BackgroundColor3 = T.RedDark }, .1)
        end)
        b.Activated:Connect(callback)
        return b
    end

    local function getHumanoid()
        local character = LP.Character
        return character and character:FindFirstChildOfClass("Humanoid")
    end

    local function applyMovement()
        local humanoid = getHumanoid()
        if not humanoid then return end

        pcall(function()
            humanoid.WalkSpeed = State.WalkSpeed
        end)

        pcall(function()
            humanoid.UseJumpPower = true
            humanoid.JumpPower = State.JumpPower
        end)
    end

    TrackConnection(LP.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if humanoid then
            task.wait(.15)
            applyMovement()
        end
    end))

    -- AUTO REJOIN -----------------------------------------------------------
    local reconnectBusy = false
    local AutoRejoinCard = card(1, 1, "AUTO REJOIN", "Rejoin this server if disconnected.")
    local AutoRejoinToggle = makeToggle(AutoRejoinCard, State.AutoRejoin, function(enabled)
        State.AutoRejoin = enabled
    end)

    TrackConnection(GuiService.ErrorMessageChanged:Connect(function(message)
        if not State.AutoRejoin or reconnectBusy then return end
        if tostring(message or "") == "" then return end

        reconnectBusy = true
        task.delay(2, function()
            queueScoopHubAfterTeleport()
            pcall(function()
                if game.JobId and game.JobId ~= "" then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
                else
                    TeleportService:Teleport(game.PlaceId, LP)
                end
            end)
            task.delay(5, function()
                reconnectBusy = false
            end)
        end)
    end))

    -- WALK SPEED ------------------------------------------------------------
    local WalkCard = card(2, 1, "WALK SPEED", "Player movement speed.")
    local WalkBox = makeValueBox(WalkCard, State.WalkSpeed, function(box)
        local value = tonumber(box.Text)
        if not value then
            box.Text = tostring(State.WalkSpeed)
            return
        end
        State.WalkSpeed = math.clamp(value, 0, 500)
        box.Text = tostring(State.WalkSpeed)
        applyMovement()
    end)

    -- JUMP POWER ------------------------------------------------------------
    local JumpCard = card(1, 2, "JUMP POWER", "Player jump power.")
    local JumpBox = makeValueBox(JumpCard, State.JumpPower, function(box)
        local value = tonumber(box.Text)
        if not value then
            box.Text = tostring(State.JumpPower)
            return
        end
        State.JumpPower = math.clamp(value, 0, 500)
        box.Text = tostring(State.JumpPower)
        applyMovement()
    end)

    -- NO CLIP ---------------------------------------------------------------
    -- Plant-only noclip for the local player's own garden.
    -- Target: Workspace > Gardens > <owned Plot#> > Plants
    -- We disable collision on the plant parts themselves instead of disabling
    -- collision on the character, so the player still collides with the ground
    -- and the rest of the map normally.
    local collisionCache = setmetatable({}, { __mode = "k" })
    local plantDescendantConnection
    local watchedPlantsFolder

    -- V15: the No Clip safety watchdog exists ONLY while No Clip is enabled.
    -- Generation invalidation cleanly stops an older worker without leaving
    -- an idle 0.75-second loop running in the background.
    local noClipWatchdogGeneration = 0
    local noClipWatchdogRunning = false

    local NoClipCard = card(2, 2, "NO CLIP", "Walk through plants in your garden.")
    local NoClipToggle

    local function getOwnPlot()
        local gardens = workspace:FindFirstChild("Gardens")
        if not gardens then
            return nil
        end

        -- Plots are named dynamically (Plot1, Plot2, Plot3, ...).
        -- Detect the local player's plot from the Owner / OwnerUserId attributes.
        for _, plot in ipairs(gardens:GetChildren()) do
            local owner = plot:GetAttribute("Owner")
            local ownerUserId = plot:GetAttribute("OwnerUserId")

            if tostring(owner or "") == LP.Name
                or tonumber(ownerUserId) == LP.UserId then
                return plot
            end
        end

        return nil
    end

    local function getOwnPlantsFolder()
        local ownPlot = getOwnPlot()
        if not ownPlot then
            return nil
        end

        return ownPlot:FindFirstChild("Plants")
    end

    local function setPlantNoclipClimbing(enabled)
        local humanoid = getHumanoid()
        if not humanoid then
            return
        end

        -- enabled=true means plant noclip is active, so disable Roblox's
        -- climbing state to stop the character from walking/jumping up trees.
        pcall(function()
            humanoid:SetStateEnabled(
                Enum.HumanoidStateType.Climbing,
                not enabled
            )
        end)

        if enabled and humanoid:GetState() == Enum.HumanoidStateType.Climbing then
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
    end

    local function setPlantPartNoClip(part)
        if not part or not part:IsA("BasePart") then
            return
        end

        if collisionCache[part] == nil then
            collisionCache[part] = part.CanCollide
        end

        part.CanCollide = false
    end

    local function applyPlantNoClip()
        local plantsFolder = getOwnPlantsFolder()
        if not plantsFolder then
            return
        end

        for _, item in ipairs(plantsFolder:GetDescendants()) do
            if item:IsA("BasePart") then
                setPlantPartNoClip(item)
            end
        end
    end

    local function stopWatchingPlants()
        if plantDescendantConnection then
            plantDescendantConnection:Disconnect()
            plantDescendantConnection = nil
        end
        watchedPlantsFolder = nil
    end

    local function watchPlantsFolder()
        local plantsFolder = getOwnPlantsFolder()
        if plantsFolder == watchedPlantsFolder and plantDescendantConnection then
            return
        end

        stopWatchingPlants()
        watchedPlantsFolder = plantsFolder

        if plantsFolder then
            plantDescendantConnection = TrackConnection(plantsFolder.DescendantAdded:Connect(function(item)
                if State.NoClip and item:IsA("BasePart") then
                    task.defer(function()
                        if State.NoClip and item.Parent then
                            setPlantPartNoClip(item)
                        end
                    end)
                end
            end))
        end
    end

    local function restoreCollisions()
        stopWatchingPlants()

        for part, oldValue in pairs(collisionCache) do
            if part and part.Parent and part:IsA("BasePart") then
                pcall(function()
                    part.CanCollide = oldValue
                end)
            end
        end

        table.clear(collisionCache)
    end

    local function stopNoClipWatchdog()
        noClipWatchdogGeneration += 1
        noClipWatchdogRunning = false
    end

    local function startNoClipWatchdog()
        if noClipWatchdogRunning
            or not State.NoClip
            or not ScoopHubRunAlive()
            or not SG.Parent then
            return
        end

        noClipWatchdogGeneration += 1
        local myGeneration = noClipWatchdogGeneration
        noClipWatchdogRunning = true

        task.spawn(function()
            -- DescendantAdded handles normal newly-created plant parts
            -- immediately. This watchdog is only the slow safety/repair path
            -- while No Clip is actually ON.
            while ScoopHubRunAlive()
                and SG.Parent
                and State.NoClip
                and myGeneration == noClipWatchdogGeneration do

                watchPlantsFolder()
                applyPlantNoClip()
                setPlantNoclipClimbing(true)

                task.wait(0.75)
            end

            if myGeneration == noClipWatchdogGeneration then
                noClipWatchdogRunning = false
            end
        end)
    end

    NoClipToggle = makeToggle(NoClipCard, State.NoClip, function(enabled)
        State.NoClip = enabled == true

        if State.NoClip then
            -- Apply immediately; do not wait for the watchdog's first cycle.
            watchPlantsFolder()
            applyPlantNoClip()
            setPlantNoclipClimbing(true)
            startNoClipWatchdog()
        else
            -- V15: OFF means zero recurring NoClip work.
            stopNoClipWatchdog()
            restoreCollisions()
            setPlantNoclipClimbing(false)
        end
    end)

    -- PERFORMANCE HISTORY:
    -- Older versions used RunService.Stepped and scanned every frame.
    -- V14 reduced that to a permanent 0.75s safety loop.
    -- V15 keeps the same 0.75s repair behavior ONLY while No Clip is enabled.

    -- Re-apply the humanoid setting after respawn while the toggle is on.
    TrackConnection(LP.CharacterAdded:Connect(function(character)
        if not State.NoClip then
            return
        end

        local humanoid = character:WaitForChild("Humanoid", 10)
        if humanoid then
            task.wait(.15)
            setPlantNoclipClimbing(true)
            watchPlantsFolder()
            applyPlantNoClip()
            startNoClipWatchdog()
        end
    end))

    -- State can persist if this UI is reloaded in the same session.
    if State.NoClip then
        task.defer(function()
            watchPlantsFolder()
            applyPlantNoClip()
            setPlantNoclipClimbing(true)
            startNoClipWatchdog()
        end)
    end

    RegisterScoopHubCleanup(function()
        stopNoClipWatchdog()
        restoreCollisions()
        setPlantNoclipClimbing(false)
    end)

    -- INFINITE JUMP ---------------------------------------------------------
    local InfiniteCard = card(1, 3, "INFINITE JUMP", "Jump again while already in the air.")
    local InfiniteToggle = makeToggle(InfiniteCard, State.InfiniteJump, function(enabled)
        State.InfiniteJump = enabled
    end)

    TrackConnection(UIS.JumpRequest:Connect(function()
        if not State.InfiniteJump then return end
        local humanoid = getHumanoid()
        if humanoid and humanoid.Health > 0 then
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end))

    -- SERVER HOP ------------------------------------------------------------
    local ServerCard = card(2, 3, "SERVER HOPPER", "Teleport to another public server.")
    local serverHopBusy = false
    local ServerButton

    local function serverHop()
        if serverHopBusy then return end
        serverHopBusy = true
        ServerButton.Text = "SEARCHING..."

        task.spawn(function()
            local ok, result = pcall(function()
                local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
                    .. "/servers/Public?sortOrder=Asc&limit=100"
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            local choices = {}
            if ok and type(result) == "table" and type(result.data) == "table" then
                for _, server in ipairs(result.data) do
                    if server.id
                        and server.id ~= game.JobId
                        and tonumber(server.playing)
                        and tonumber(server.maxPlayers)
                        and server.playing < server.maxPlayers then
                        table.insert(choices, server.id)
                    end
                end
            end

            if #choices > 0 then
                local target = choices[math.random(1, #choices)]
                queueScoopHubAfterTeleport()
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, target, LP)
                end)
            else
                ServerButton.Text = "NO SERVER FOUND"
                task.wait(1.2)
                ServerButton.Text = "SERVER HOP"
                serverHopBusy = false
            end
        end)
    end

    ServerButton = makeAction(ServerCard, "SERVER HOP", serverHop)

    -- SET FPS ---------------------------------------------------------------
    local FPSCard = card(1, 4, "SET FPS", "Choose your target frame rate.")
    local FPSButton = C(N("TextButton", {
        Text = State.FPS,
        AutoButtonColor = false,
        Font = T.Font,
        TextSize = 10,
        TextColor3 = T.White,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = T.Input,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 9, 0, 36),
        Size = UDim2.new(1, -18, 0, 22),
        ZIndex = 15,
    }, FPSCard), 5)
    N("UIPadding", { PaddingLeft = UDim.new(0, 8) }, FPSButton)
    S(FPSButton, T.Line, .72, 1)

    local Chevron = label(
        FPSButton,
        "▼",
        UDim2.new(1, -20, 0, 0),
        UDim2.fromOffset(14, 22),
        8,
        T.Muted,
        T.Font,
        Enum.TextXAlignment.Center
    )
    Chevron.ZIndex = 16

    local FPSOptions = { "10", "15", "30", "60", "120", "inf" }
    local FPSDropdown = C(N("Frame", {
        Visible = false,
        BackgroundColor3 = T.Surface2,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(120, (#FPSOptions * 24) + 6),
        ZIndex = 100,
    }, Page), 6)
    S(FPSDropdown, T.Red, .15, 1)

    local FPSList = N("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.new(1, -6, 1, -6),
        ZIndex = 101,
    }, FPSDropdown)
    N("UIListLayout", { Padding = UDim.new(0, 0) }, FPSList)

    local function applyFPS(value)
        State.FPS = tostring(value)
        FPSButton.Text = State.FPS

        local cap = State.FPS == "inf" and 9999 or tonumber(State.FPS)
        local setter = setfpscap
        if type(setter) == "function" and cap then
            -- Reset the executor's previous FPS cap first.
            -- This fixes the common case where 15 FPS applies correctly,
            -- but changing upward to 30/60/120 stays stuck at the old cap.
            --
            -- setfpscap(0) is the normal "uncap/reset" path on supported
            -- executors. 9999 is used as a fallback/high reset as well.
            pcall(setter, 0)
            pcall(setter, 9999)

            -- Give the executor one scheduler step to release the old limiter,
            -- then apply the user's actual selected value.
            task.wait()

            if State.FPS == "inf" then
                pcall(setter, 9999)
            else
                pcall(setter, cap)
            end
        end
    end

    for _, option in ipairs(FPSOptions) do
        local row = N("TextButton", {
            Text = option,
            AutoButtonColor = false,
            Font = T.Body,
            TextSize = 10,
            TextColor3 = T.White,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 24),
            ZIndex = 102,
        }, FPSList)
        N("UIPadding", { PaddingLeft = UDim.new(0, 8) }, row)

        row.MouseEnter:Connect(function()
            row.BackgroundColor3 = T.RedDark
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundColor3 = T.Surface2
        end)
        row.Activated:Connect(function()
            FPSDropdown.Visible = false
            applyFPS(option)
        end)
    end

    local function positionFPSDropdown()
        local pagePos = Page.AbsolutePosition
        local buttonPos = FPSButton.AbsolutePosition
        local buttonSize = FPSButton.AbsoluteSize
        local dropdownHeight = FPSDropdown.AbsoluteSize.Y
        local pageBottom = pagePos.Y + Page.AbsoluteSize.Y

        local x = buttonPos.X - pagePos.X
        local belowY = buttonPos.Y - pagePos.Y + buttonSize.Y + 3
        local aboveY = buttonPos.Y - pagePos.Y - dropdownHeight - 3
        local y = ((pagePos.Y + belowY + dropdownHeight) <= pageBottom) and belowY or aboveY

        FPSDropdown.Position = UDim2.fromOffset(x, math.max(0, y))
        FPSDropdown.Size = UDim2.fromOffset(math.max(120, buttonSize.X), (#FPSOptions * 24) + 6)
    end

    FPSButton.Activated:Connect(function()
        FPSDropdown.Visible = not FPSDropdown.Visible
        if FPSDropdown.Visible then
            positionFPSDropdown()
        end
    end)

    -- REJOIN ----------------------------------------------------------------
    local RejoinCard = card(2, 4, "REJOIN SERVER", "Reconnect to the current server.")
    makeAction(RejoinCard, "REJOIN", function()
        queueScoopHubAfterTeleport()
        pcall(function()
            if game.JobId and game.JobId ~= "" then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
            else
                TeleportService:Teleport(game.PlaceId, LP)
            end
        end)
    end)

    -- REMOTE VISUAL / ESP FEATURES -------------------------------------------
    -- Low Graphics, Remove Other Gardens, Backpack Value ESP, Wild Pet ESP,
    -- and Garden ESP are mounted by one remote module. The returned controls
    -- keep the same Get/Set API used by Config and the rest of ScoopHub.
    local RemoteVisuals
    do
        local module = type(_G.ScoopHubGetVisualFeaturesModule) == "function"
            and _G.ScoopHubGetVisualFeaturesModule()
            or nil

        if type(module) == "table" and type(module.MountMisc) == "function" then
            local ok, result = pcall(module.MountMisc, {
                LP = LP,
                State = State,
                Page = Page,
                SG = SG,
                Scale = Scale,
                UIS = UIS,
                T = T,
                Card = card,
                MakeToggle = makeToggle,
                Label = label,
                N = N,
                C = C,
                S = S,
                Tween = tw,
                TrackConnection = TrackConnection,
                RegisterCleanup = RegisterScoopHubCleanup,
                RunAlive = ScoopHubRunAlive,
                GardenEspCardHeight = GARDEN_ESP_CARD_H,
            })

            if ok and type(result) == "table" then
                RemoteVisuals = result
            else
                warn("[ScoopHub] Remote Misc visual features failed: " .. tostring(result))
            end
        end
    end

    local function fallbackToggle()
        local value = false
        return {
            Set = function(_, newValue) value = newValue == true end,
            Get = function() return value end,
        }
    end

    local CleanupToggle = RemoteVisuals and RemoteVisuals.CleanupToggle or fallbackToggle()
    local RemoveGardenToggle = RemoteVisuals and RemoteVisuals.RemoveGardenToggle or fallbackToggle()
    local WildPetEspToggle = RemoteVisuals and RemoteVisuals.WildPetEspToggle or fallbackToggle()
    local BackpackValueToggle = RemoteVisuals and RemoteVisuals.BackpackValueToggle or fallbackToggle()
    local GardenESPFeature = RemoteVisuals and RemoteVisuals.GardenESPFeature or {
        GetSettings = function()
            return {
                Enabled = false,
                FruitAll = false,
                Fruits = {},
                MutationAll = true,
                Mutations = {},
            }
        end,
        ApplySettings = function() return false end,
        SetEnabled = function() end,
        IsEnabled = function() return false end,
        Stop = function() end,
    }

    -- Click outside the FPS dropdown to close it.
    TrackConnection(UIS.InputBegan:Connect(function(input)
        if not FPSDropdown.Visible then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local point = input.Position
        local function inside(gui)
            local p = gui.AbsolutePosition
            local s = gui.AbsoluteSize
            return point.X >= p.X and point.X <= p.X + s.X
                and point.Y >= p.Y and point.Y <= p.Y + s.Y
        end

        if not inside(FPSDropdown) and not inside(FPSButton) then
            FPSDropdown.Visible = false
        end
    end))

    Page:GetPropertyChangedSignal("Visible"):Connect(function()
        if not Page.Visible then
            FPSDropdown.Visible = false
        end
    end)

    applyMovement()
    applyFPS(State.FPS)

    _G.ScoopHubMiscAPI = {
        GetSettings = function()
            local cleanup = CleanupToggle:Get() == true
            return {
                AutoRejoin = State.AutoRejoin == true,
                WalkSpeed = State.WalkSpeed,
                JumpPower = State.JumpPower,
                NoClip = State.NoClip == true,
                InfiniteJump = State.InfiniteJump == true,
                FPS = tostring(State.FPS),
                Cleanup = cleanup,
                RemoveOtherGardens = State.RemoveOtherGardens == true,
                WildPetESP = WildPetEspToggle:Get() == true,
                BackpackValueESP = BackpackValueToggle:Get() == true,
                GardenESP = GardenESPFeature.GetSettings(),
            }
        end,
        ApplySettings = function(data)
            if type(data) ~= "table" then
                return false
            end

            State.WalkSpeed = math.clamp(tonumber(data.WalkSpeed) or 16, 0, 500)
            State.JumpPower = math.clamp(tonumber(data.JumpPower) or 50, 0, 500)
            WalkBox.Text = tostring(State.WalkSpeed)
            JumpBox.Text = tostring(State.JumpPower)
            applyMovement()

            AutoRejoinToggle:Set(data.AutoRejoin == true, true)
            NoClipToggle:Set(data.NoClip == true, true)
            InfiniteToggle:Set(data.InfiniteJump == true, true)
            CleanupToggle:Set(data.Cleanup == true, true)
            RemoveGardenToggle:Set(data.RemoveOtherGardens == true, true)
            WildPetEspToggle:Set(data.WildPetESP == true, true)
            BackpackValueToggle:Set(data.BackpackValueESP == true, true)
            GardenESPFeature.ApplySettings(data.GardenESP)

            local fpsValue = tostring(data.FPS or "60"):lower()
            local validFPS = false
            for _, option in ipairs(FPSOptions) do
                if fpsValue == option then
                    validFPS = true
                    break
                end
            end
            applyFPS(validFPS and fpsValue or "60")
            return true
        end,
        SetAutoRejoin = function(value)
            AutoRejoinToggle:Set(value == true, true)
        end,
        IsAutoRejoinEnabled = function()
            return State.AutoRejoin == true
        end,
        SetCleanup = function(value)
            CleanupToggle:Set(value == true, true)
        end,
        SetRemoveOtherGardens = function(value)
            RemoveGardenToggle:Set(value == true, true)
        end,
        SetBackpackValueESP = function(value)
            BackpackValueToggle:Set(value == true, true)
        end,
        IsBackpackValueESPEnabled = function()
            return BackpackValueToggle:Get() == true
        end,
        SetGardenESP = function(value)
            GardenESPFeature.SetEnabled(value == true)
        end,
        IsGardenESPEnabled = function()
            return GardenESPFeature.IsEnabled()
        end,
        SetFPS = function(value)
            local normalized = tostring(value):lower()
            for _, option in ipairs(FPSOptions) do
                if normalized == option then
                    applyFPS(option)
                    return true
                end
            end
            return false
        end,
    }

    _G.__ScoopHubSilentLog("[ScoopHub] Misc page initialized.")
end

__ScoopHubInitMisc()
local __userInitOk, __userInitErr = pcall(__ScoopHubInitUser)
if not __userInitOk then
    warn("[ScoopHub] User dashboard init error: " .. tostring(__userInitErr))
end

--==================================================
-- CONFIG PAGE
--==================================================
local function __ScoopHubInitConfig()
    local HttpService = game:GetService("HttpService")
    local Page = Configs
    Page.ClipsDescendants = false

    local CONFIG_DIR = "ScoopHub/Configs"
    local META_FILE = CONFIG_DIR .. "/meta_" .. tostring(LP.UserId) .. ".json"
    local currentConfig = ""
    -- Only LOAD CONFIG makes a config active for future rejoin/re-execution.
    -- currentConfig is the chooser/UI selection; activeConfig is what auto-loads.
    local activeConfig = ""
    local knownConfigs = {}
    local autoSave = false
    local lastAutoSaveJSON = nil
    local configBusy = false

    local function ensureFolder()
        if not (isfolder and makefolder) then return false end
        pcall(function()
            if not isfolder("ScoopHub") then makefolder("ScoopHub") end
            if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        end)
        return true
    end

    local function trim(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- Keep config filenames human-readable. Only characters that are unsafe
    -- in normal filenames are replaced, so a config named "My Farm" saves as
    -- ScoopHub/Configs/My Farm.json instead of a hexadecimal filename.
    local function safeFileName(name)
        local value = trim(name)
        value = value:gsub("[%z\1-\31<>:\"/\\|%?%*]", "_")
        value = value:gsub("[%.%s]+$", "")
        if value == "" then value = "Config" end
        return value
    end

    -- Legacy path support for configs saved by the older hex-filename build.
    local function legacyNameKey(name)
        local out = {}
        name = trim(name)
        for i = 1, #name do
            out[#out + 1] = string.format("%02X", string.byte(name, i))
        end
        return table.concat(out)
    end

    local function configPath(name)
        return CONFIG_DIR .. "/" .. safeFileName(name) .. ".json"
    end

    local function legacyConfigPath(name)
        return CONFIG_DIR .. "/config_" .. tostring(LP.UserId) .. "_" .. legacyNameKey(name) .. ".json"
    end

    local function existingConfigPath(name)
        local newPath = configPath(name)
        if isfile then
            local exists = false
            pcall(function() exists = isfile(newPath) end)
            if exists then return newPath end

            local oldPath = legacyConfigPath(name)
            pcall(function() exists = isfile(oldPath) end)
            if exists then return oldPath end
        end
        return newPath
    end

    local function safeClone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = safeClone(v) end
        return out
    end

    local function captureConfig(name)
        local data = {
            Version = 3,
            ConfigName = trim(name or currentConfig),
            UserId = LP.UserId,
            SavedAt = os.time(),
            Automation = {},
            Shop = {},
            Misc = {},
        }

        if _G.ScoopHubAutomationAPI and _G.ScoopHubAutomationAPI.GetSettings then
            local ok, value = pcall(_G.ScoopHubAutomationAPI.GetSettings)
            if ok and type(value) == "table" then data.Automation = safeClone(value) end
        end

        if _G.ScoopHubShopAPI and _G.ScoopHubShopAPI.GetSettings then
            local ok, value = pcall(_G.ScoopHubShopAPI.GetSettings)
            if ok and type(value) == "table" then data.Shop = safeClone(value) end
        end

        if _G.ScoopHubMiscAPI and _G.ScoopHubMiscAPI.GetSettings then
            local ok, value = pcall(_G.ScoopHubMiscAPI.GetSettings)
            if ok and type(value) == "table" then data.Misc = safeClone(value) end
        end

        return data
    end

    local function applyConfig(data)
        if type(data) ~= "table" then return false end

        if type(data.Automation) == "table"
            and _G.ScoopHubAutomationAPI
            and _G.ScoopHubAutomationAPI.ApplySettings then
            pcall(_G.ScoopHubAutomationAPI.ApplySettings, data.Automation)
        end

        if type(data.Shop) == "table"
            and _G.ScoopHubShopAPI
            and _G.ScoopHubShopAPI.ApplySettings then
            pcall(_G.ScoopHubShopAPI.ApplySettings, data.Shop)
        end

        if type(data.Misc) == "table"
            and _G.ScoopHubMiscAPI
            and _G.ScoopHubMiscAPI.ApplySettings then
            pcall(_G.ScoopHubMiscAPI.ApplySettings, data.Misc)
        end

        return true
    end

    local function writeJSON(path, data)
        if not (writefile and ensureFolder()) then return false, "writefile unavailable" end
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not ok then return false, "JSON encode failed" end
        local wrote = pcall(writefile, path, encoded)
        return wrote, wrote and encoded or "write failed"
    end

    local function readJSON(path)
        if not (readfile and isfile) then return nil, "readfile unavailable" end
        local exists = false
        pcall(function() exists = isfile(path) end)
        if not exists then return nil, "config not found" end
        local ok, raw = pcall(readfile, path)
        if not ok or type(raw) ~= "string" or raw == "" then return nil, "read failed" end
        local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not decodedOk or type(data) ~= "table" then return nil, "invalid JSON" end
        return data, raw
    end

    local function addKnown(name)
        name = trim(name)
        if name == "" then return end
        for _, existing in ipairs(knownConfigs) do
            if string.lower(existing) == string.lower(name) then return end
        end
        table.insert(knownConfigs, name)
        table.sort(knownConfigs, function(a, b) return string.lower(a) < string.lower(b) end)
    end

    local function removeKnown(name)
        for i = #knownConfigs, 1, -1 do
            if string.lower(knownConfigs[i]) == string.lower(name) then
                table.remove(knownConfigs, i)
            end
        end
    end

    local function loadMeta()
        local meta = readJSON(META_FILE)
        if type(meta) == "table" then
            -- ActiveConfig is deliberately separate from CurrentConfig.
            -- This prevents merely saving/choosing a config from making it
            -- auto-load after a rejoin. Only LOAD CONFIG writes ActiveConfig.
            activeConfig = trim(meta.ActiveConfig)
            currentConfig = activeConfig ~= "" and activeConfig or trim(meta.CurrentConfig)
            autoSave = meta.AutoSave == true
            if type(meta.KnownConfigs) == "table" then
                for _, name in ipairs(meta.KnownConfigs) do addKnown(name) end
            end
        end
    end

    local function saveMeta()
        writeJSON(META_FILE, {
            CurrentConfig = currentConfig,
            ActiveConfig = activeConfig,
            AutoSave = autoSave,
            KnownConfigs = knownConfigs,
        })
    end

    loadMeta()

    local title = label(Page, "CONFIG", UDim2.new(0, 4, 0, 1), UDim2.new(1, -8, 0, 20), 12, T.Text, T.Font)
    N("Frame", {
        Position = UDim2.new(0, 4, 0, 22), Size = UDim2.new(1, -8, 0, 1),
        BackgroundColor3 = T.Red, BackgroundTransparency = .5, BorderSizePixel = 0,
    }, Page)

    local function configPanel(pos, size, heading)
        local f = C(N("Frame", {
            Position = pos, Size = size, BackgroundColor3 = T.Surface2,
            BackgroundTransparency = .06, BorderSizePixel = 0, ClipsDescendants = false,
        }, Page), 7)
        S(f, T.Line, .48, 1)

        -- V26: thin accent rail gives Config cards hierarchy without filling
        -- every action with bright red.
        N("Frame", {
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(0, 32, 0, 2),
            BackgroundColor3 = T.Red,
            BackgroundTransparency = .18,
            BorderSizePixel = 0,
        }, f)

        if heading and heading ~= "" then
            label(f, heading, UDim2.new(0, 10, 0, 8), UDim2.new(1, -20, 0, 18), 11, T.White, T.Font)
        end
        return f
    end

    local ManagerPanel = configPanel(UDim2.new(0, 0, 0, 28), UDim2.new(.56, -3, 0, 192), "CONFIG MANAGER")
    local TransferPanel = configPanel(UDim2.new(.56, 3, 0, 28), UDim2.new(.44, -3, 0, 192), "BACKUP & TRANSFER")
    local AutoSavePanel = configPanel(UDim2.new(0, 0, 0, 226), UDim2.new(1, 0, 0, 58), "AUTO SAVE")
    local ResetPanel = configPanel(UDim2.new(0, 0, 0, 290), UDim2.new(1, 0, 0, 52), "CONFIG SETTINGS")
    local InfoPanel = configPanel(UDim2.new(0, 0, 0, 348), UDim2.new(1, 0, 0, 42), "")

    local ActiveBadge = C(N("Frame", {
        BackgroundColor3 = activeConfig ~= "" and T.Success or T.Surface3,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -86, 0, 7),
        Size = UDim2.fromOffset(76, 17),
    }, ManagerPanel), 999)
    S(ActiveBadge, activeConfig ~= "" and T.Success or T.Line, .5, 1)
    local ActiveBadgeText = label(
        ActiveBadge,
        activeConfig ~= "" and "ACTIVE" or "NO ACTIVE",
        UDim2.new(0, 0, 0, 0),
        UDim2.new(1, 0, 1, 0),
        8,
        T.White,
        T.Font,
        Enum.TextXAlignment.Center
    )

    local StatusStrip = C(N("Frame", {
        BackgroundColor3 = T.Surface3,
        BackgroundTransparency = .18,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 0, 166),
        Size = UDim2.new(1, -20, 0, 18),
    }, ManagerPanel), 4)
    S(StatusStrip, T.Line, .72, 1)
    local Status = label(StatusStrip, "Ready", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 1, 0), 9, T.Muted, T.Body)

    local function setStatus(message, success)
        Status.Text = tostring(message)
        Status.TextColor3 = success == false and T.Text or (success == true and T.Success or T.Muted)

        local isActive = trim(activeConfig) ~= ""
        ActiveBadge.BackgroundColor3 = isActive and T.Success or T.Surface3
        ActiveBadgeText.Text = isActive and "ACTIVE" or "NO ACTIVE"
    end

    local NameBox = C(N("TextBox", {
        Name = "ConfigNameBox", Text = currentConfig, PlaceholderText = "Type config name...",
        Font = T.Body, TextSize = 11, TextColor3 = T.White, PlaceholderColor3 = T.Muted,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        BackgroundColor3 = T.Input, BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 0, 33), Size = UDim2.new(1, -20, 0, 29), ZIndex = 12,
    }, ManagerPanel), 5)
    N("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, NameBox)
    S(NameBox, T.Line, .65, 1)

    local ConfigButton = C(N("TextButton", {
        Text = "",
        Font = T.Font, TextSize = 11, TextColor3 = T.White, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundColor3 = T.Input, BorderSizePixel = 0, AutoButtonColor = false,
        ClipsDescendants = true,
        Position = UDim2.new(0, 10, 0, 67), Size = UDim2.new(1, -20, 0, 29), ZIndex = 12,
    }, ManagerPanel), 5)
    S(ConfigButton, T.Line, .65, 1)

    -- V36: use the exact same INNER LAYOUT as every Shop filter button.
    -- No UIPadding is attached to ConfigButton, because padding changes the
    -- coordinate area used by its children and was what kept pushing the
    -- chevron inward even when its Position looked identical to Shop.
    local ConfigButtonText = N("TextLabel", {
        Name = "ConfigButtonText",
        Text = currentConfig ~= "" and currentConfig or "Choose config...",
        Font = T.Body,
        TextSize = 12,
        TextColor3 = T.White,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0, 0),
        Size = UDim2.new(1, -28, 1, 0),
        ZIndex = 13,
    }, ConfigButton)

    local function setConfigButtonDisplay(value)
        ConfigButtonText.Text = tostring(value or "")
    end

    -- Exact Shop-filter chevron coordinates/size.
    local ConfigChevron = N("Frame", {
        Name = "ConfigChevron",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -20, 0.5, -5),
        Size = UDim2.fromOffset(14, 10),
        Rotation = 0,
        ZIndex = 13,
    }, ConfigButton)

    N("Frame", {
        Name = "ChevronLeft",
        BackgroundColor3 = T.Muted,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.new(.5, -2, .5, 0),
        Size = UDim2.fromOffset(7, 2),
        Rotation = 45,
        ZIndex = 14,
    }, ConfigChevron)

    N("Frame", {
        Name = "ChevronRight",
        BackgroundColor3 = T.Muted,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.new(.5, 2, .5, 0),
        Size = UDim2.fromOffset(7, 2),
        Rotation = -45,
        ZIndex = 14,
    }, ConfigChevron)

    local function setConfigChevron(open)
        -- V40: same smooth open/close chevron animation as Automation/Shop.
        tw(ConfigChevron, {
            Rotation = open and 180 or 0,
        }, .14)
    end

    -- Floating dropdown so the config chooser does not collide with the cards below.
    local ConfigDropdown = C(N("Frame", {
        Name = "ConfigDropdown", Visible = false, BackgroundColor3 = T.Surface2,
        BorderSizePixel = 0, ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(100, 108), ZIndex = 150,
    }, Page), 5)
    S(ConfigDropdown, T.Red, .2, 1)

    local ConfigSearch = C(N("TextBox", {
        Name = "ConfigSearch", Text = "", PlaceholderText = "Search configs...",
        Font = T.Body, TextSize = 11, TextColor3 = T.White, PlaceholderColor3 = T.Muted,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        BackgroundColor3 = T.Input, BorderSizePixel = 0,
        Position = UDim2.new(0, 4, 0, 4), Size = UDim2.new(1, -8, 0, 24), ZIndex = 151,
    }, ConfigDropdown), 4)
    N("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, ConfigSearch)
    S(ConfigSearch, T.Line, .72, 1)

    local ConfigScroll = N("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(4, 31), Size = UDim2.new(1, -8, 1, -35),
        CanvasSize = UDim2.new(0, 0, 0, 0), ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Red, ZIndex = 151,
    }, ConfigDropdown)
    local ConfigList = N("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, ConfigScroll)

    local dropdownRowHeight = 28
    local dropdownMaxRows = 5
    local function updateDropdownGeometry(rowCount)
        local visibleRows = math.clamp(tonumber(rowCount) or 0, 1, dropdownMaxRows)
        local pagePos = Page.AbsolutePosition
        local pageSize = Page.AbsoluteSize
        local btnPos = ConfigButton.AbsolutePosition
        local btnSize = ConfigButton.AbsoluteSize
        local width = btnSize.X
        local height = 35 + (visibleRows * dropdownRowHeight) + 4
        local x = btnPos.X - pagePos.X
        local belowY = btnPos.Y - pagePos.Y + btnSize.Y + 4
        local aboveY = btnPos.Y - pagePos.Y - height - 4
        local y = belowY
        if belowY + height > pageSize.Y and aboveY >= 0 then
            y = aboveY
        end
        ConfigDropdown.Position = UDim2.fromOffset(x, y)
        ConfigDropdown.Size = UDim2.fromOffset(width, height)
    end

    local function selectConfig(name)
        name = trim(name)
        currentConfig = name
        -- The name box is only for typing a NEW config name.
        -- Picking an existing config should not copy its name into this field.
        NameBox.Text = ""
        setConfigButtonDisplay(name ~= "" and name or "Choose config...")
        ConfigDropdown.Visible = false
        setConfigChevron(false)
        ConfigSearch.Text = ""
        saveMeta()

        if name == "" then
            setStatus("No config selected", nil)
            return
        end

        local exists = false
        if isfile then
            local path = existingConfigPath(name)
            pcall(function() exists = isfile(path) end)
        end
        setStatus(exists and ("Selected: " .. name) or ("New config: " .. name), nil)
    end

    local function scanConfigs()
        local discovered = {}
        local function add(name)
            name = trim(name)
            if name == "" then return end
            local key = string.lower(name)
            if discovered[key] then return end
            discovered[key] = name
        end

        -- A real refresh reflects the JSON files that currently exist.
        -- It also migrates old hexadecimal filenames to readable names.
        local listedFiles = false
        if listfiles and ensureFolder() then
            local ok, paths = pcall(listfiles, CONFIG_DIR)
            if ok and type(paths) == "table" then
                listedFiles = true
                local legacyPrefix = "config_" .. tostring(LP.UserId) .. "_"

                for _, path in ipairs(paths) do
                    local pathString = tostring(path)
                    local fileName = pathString:match("([^/\\]+)$") or pathString
                    local lowerFile = string.lower(fileName)

                    local isJSON = lowerFile:sub(-5) == ".json"
                    local isMeta = lowerFile:sub(1, 5) == "meta_"
                    local isExport = lowerFile:sub(1, 7) == "export_"
                    local isImport = lowerFile == "import.json"

                    if isJSON and not isMeta and not isExport and not isImport then
                        local data = readJSON(pathString)
                        if type(data) == "table" and trim(data.ConfigName) ~= "" then
                            local displayName = trim(data.ConfigName)
                            add(displayName)

                            -- Convert the previous config_<userid>_<hex>.json file
                            -- to <actual config name>.json so the folder is readable.
                            if fileName:sub(1, #legacyPrefix) == legacyPrefix then
                                local readablePath = configPath(displayName)
                                local readableExists = false
                                if isfile then
                                    pcall(function() readableExists = isfile(readablePath) end)
                                end

                                if not readableExists and writefile then
                                    local readOk, raw = pcall(readfile, pathString)
                                    if readOk and type(raw) == "string" and raw ~= "" then
                                        pcall(writefile, readablePath, raw)
                                        readableExists = true
                                    end
                                end

                                if readableExists and delfile then
                                    pcall(delfile, pathString)
                                end
                            end
                        end
                    end
                end
            end
        end

        if not listedFiles then
            for _, name in ipairs(knownConfigs) do
                add(name)
            end
        end

        knownConfigs = {}
        for _, name in pairs(discovered) do
            table.insert(knownConfigs, name)
        end
        table.sort(knownConfigs, function(a, b)
            return string.lower(a) < string.lower(b)
        end)
        saveMeta()
        return #knownConfigs
    end

    local function rebuildConfigList(filterText)
        for _, child in ipairs(ConfigScroll:GetChildren()) do
            if child ~= ConfigList then child:Destroy() end
        end

        local filtered = {}
        local query = string.lower(trim(filterText or ""))
        for _, name in ipairs(knownConfigs) do
            local lowerName = string.lower(name)
            if query == "" or string.find(lowerName, query, 1, true) then
                table.insert(filtered, name)
            end
        end

        if #filtered == 0 then
            local emptyText = (#knownConfigs == 0 and query == "") and "No saved configs" or "No matches"
            local empty = label(ConfigScroll, emptyText, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 26), 10, T.Muted, T.Body)
            empty.LayoutOrder = 1
            empty.ZIndex = 152
            ConfigScroll.CanvasSize = UDim2.new(0, 0, 0, 28)
            updateDropdownGeometry(1)
            return
        end

        for i, name in ipairs(filtered) do
            local isSelected = currentConfig ~= "" and string.lower(currentConfig) == string.lower(name)
            local row = C(N("TextButton", {
                Text = "", BackgroundColor3 = isSelected and T.RedDark or T.Surface2,
                BorderSizePixel = 0, AutoButtonColor = false,
                Size = UDim2.new(1, -2, 0, 26), LayoutOrder = i, ZIndex = 152,
            }, ConfigScroll), 4)

            local txt = label(row, name, UDim2.new(0, 8, 0, 0), UDim2.new(1, -30, 1, 0), 11, T.White, T.Body)
            txt.ZIndex = 153
            if isSelected then
                local check = label(row, "\u{2713}", UDim2.new(1, -18, 0, 0), UDim2.fromOffset(12, 26), 12, T.White, T.Font)
                check.ZIndex = 153
            end

            row.MouseEnter:Connect(function()
                if not (currentConfig ~= "" and string.lower(currentConfig) == string.lower(name)) then
                    row.BackgroundColor3 = T.RedDark
                end
            end)
            row.MouseLeave:Connect(function()
                row.BackgroundColor3 = (currentConfig ~= "" and string.lower(currentConfig) == string.lower(name)) and T.RedDark or T.Surface2
            end)
            row.Activated:Connect(function() selectConfig(name) end)
        end
        ConfigScroll.CanvasSize = UDim2.new(0, 0, 0, #filtered * dropdownRowHeight)
        updateDropdownGeometry(#filtered)
    end

    ConfigSearch:GetPropertyChangedSignal("Text"):Connect(function()
        if ConfigDropdown.Visible then
            rebuildConfigList(ConfigSearch.Text)
        end
    end)

    ConfigButton.Activated:Connect(function()
        ConfigDropdown.Visible = not ConfigDropdown.Visible
        setConfigChevron(ConfigDropdown.Visible)
        if ConfigDropdown.Visible then
            ConfigSearch.Text = ""
            rebuildConfigList("")
        end
    end)

    -- V30 CONFIG BRIGHT HOVER GLOW:
    -- Match the Rejoin-style hover shown by the user: the whole button lights
    -- up to the bright accent color while a soft red halo and outline appear.
    -- MouseLeave smoothly restores the shared dark-red base color.
    local function applyConfigButtonGlow(button, accentColor, baseStrokeTransparency)
        accentColor = accentColor or T.Red
        baseStrokeTransparency = tonumber(baseStrokeTransparency) or .48

        local normalBackground = button.BackgroundColor3
        local parent = button.Parent
        local glow = N("ImageLabel", {
            Name = "ConfigHoverGlow",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Image = "rbxassetid://6015897843",
            ImageColor3 = accentColor,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(49, 49, 450, 450),
            AnchorPoint = button.AnchorPoint,
            Position = UDim2.new(
                button.Position.X.Scale,
                button.Position.X.Offset - 8,
                button.Position.Y.Scale,
                button.Position.Y.Offset - 8
            ),
            Size = UDim2.new(
                button.Size.X.Scale,
                button.Size.X.Offset + 16,
                button.Size.Y.Scale,
                button.Size.Y.Offset + 16
            ),
            ZIndex = math.max(1, button.ZIndex - 1),
        }, parent)

        local stroke = N("UIStroke", {
            Color = accentColor,
            Transparency = baseStrokeTransparency,
            Thickness = 1,
        }, button)

        button.MouseEnter:Connect(function()
            -- Bright filled button + restrained outer halo, like the Rejoin
            -- reference instead of only an outline glow.
            tw(button, {
                BackgroundColor3 = accentColor,
                TextColor3 = T.White,
            }, .12)
            tw(glow, {ImageTransparency = .44}, .12)
            tw(stroke, {Transparency = .05, Thickness = 1.5}, .12)
        end)

        button.MouseLeave:Connect(function()
            tw(button, {
                BackgroundColor3 = normalBackground,
                TextColor3 = T.White,
            }, .14)
            tw(glow, {ImageTransparency = 1}, .16)
            tw(stroke, {
                Transparency = baseStrokeTransparency,
                Thickness = 1,
            }, .14)
        end)

        return stroke, glow
    end

    local function miniButton(textValue, xScale, xOffset, y, widthScale, widthOffset, color, strokeColor)
        local normal = color or T.Surface3
        local accent = strokeColor or T.Line
        local b = C(N("TextButton", {
            Text = textValue, Font = T.Font, TextSize = 10, TextColor3 = T.White,
            BackgroundColor3 = normal, BorderSizePixel = 0, AutoButtonColor = false,
            Position = UDim2.new(xScale, xOffset, 0, y), Size = UDim2.new(widthScale, widthOffset, 0, 27), ZIndex = 10,
        }, ManagerPanel), 5)
        applyConfigButtonGlow(b, accent, .42)
        return b
    end

    -- V29: unified Config action color. Every action uses the same dark-red
    -- base and the same red hover glow so the grid reads as one button family.
    local SaveButton = miniButton("SAVE CONFIG", 0, 10, 103, .5, -13, T.RedDark, T.Red)
    local LoadButton = miniButton("LOAD CONFIG", .5, 3, 103, .5, -13, T.RedDark, T.Red)
    local RefreshButton = miniButton("REFRESH", 0, 10, 136, .5, -13, T.RedDark, T.Red)
    local DeleteButton = miniButton("DELETE", .5, 3, 136, .5, -13, T.RedDark, T.Red)

    local function requestedName()
        local typed = trim(NameBox.Text)
        if typed ~= "" then return typed end
        return trim(currentConfig)
    end

    SaveButton.Activated:Connect(function()
        if configBusy then return end
        local name = requestedName()
        if name == "" then
            setStatus("Type a config name first", false)
            return
        end

        configBusy = true
        currentConfig = name
        local data = captureConfig(name)
        local ok, encoded = writeJSON(configPath(name), data)
        if ok then
            -- Remove the old hexadecimal copy if this config came from an older build.
            if delfile and isfile then
                local oldPath = legacyConfigPath(name)
                local oldExists = false
                pcall(function() oldExists = isfile(oldPath) end)
                if oldExists then pcall(delfile, oldPath) end
            end
            addKnown(name)
            NameBox.Text = ""
            setConfigButtonDisplay(name)
            lastAutoSaveJSON = type(encoded) == "string" and encoded or nil
            saveMeta()
            rebuildConfigList("")
            setStatus("Saved: " .. name .. (activeConfig == name and " \u{2022} Active" or ""), true)
        else
            setStatus("Save failed", false)
        end
        configBusy = false
    end)

    LoadButton.Activated:Connect(function()
        if configBusy then return end
        local name = requestedName()
        if name == "" then
            setStatus("Choose a config first", false)
            return
        end

        configBusy = true
        local data, raw = readJSON(existingConfigPath(name))
        if type(data) == "table" then
            currentConfig = trim(data.ConfigName) ~= "" and trim(data.ConfigName) or name
            activeConfig = currentConfig
            applyConfig(data)
            addKnown(currentConfig)
            NameBox.Text = ""
            setConfigButtonDisplay(currentConfig)
            lastAutoSaveJSON = type(raw) == "string" and raw or nil
            saveMeta()
            setStatus("Loaded & active: " .. currentConfig, true)
        else
            setStatus("Config not found: " .. name, false)
        end
        configBusy = false
    end)

    RefreshButton.Activated:Connect(function()
        -- Refresh means start from a clean chooser state: rescan files, clear
        -- the selected config, and clear the new-config name box.
        local count = scanConfigs()

        currentConfig = ""
        activeConfig = ""
        NameBox.Text = ""
        setConfigButtonDisplay("Choose config...")
        lastAutoSaveJSON = nil

        ConfigDropdown.Visible = false
        setConfigChevron(false)
        ConfigSearch.Text = ""
        rebuildConfigList("")
        saveMeta()

        setStatus("Config list refreshed (" .. tostring(count or #knownConfigs) .. " found) \u{2022} Active config cleared", true)
    end)

    DeleteButton.Activated:Connect(function()
        local name = requestedName()
        if name == "" then
            setStatus("Choose a config first", false)
            return
        end
        if not delfile then
            setStatus("Delete unsupported", false)
            return
        end

        local path = existingConfigPath(name)
        local exists = false
        if isfile then pcall(function() exists = isfile(path) end) end
        if not exists then
            removeKnown(name)
            saveMeta()
            rebuildConfigList("")
            setStatus("Config not found", false)
            return
        end

        local ok = pcall(delfile, path)
        if ok then
            removeKnown(name)
            if string.lower(currentConfig) == string.lower(name) then
                currentConfig = ""
                NameBox.Text = ""
                setConfigButtonDisplay("Choose config...")
                lastAutoSaveJSON = nil
            end
            if string.lower(activeConfig) == string.lower(name) then
                activeConfig = ""
            end
            saveMeta()
            rebuildConfigList("")
            setStatus("Deleted: " .. name, true)
        else
            setStatus("Delete failed", false)
        end
    end)

    label(
        TransferPanel,
        "Move configs between sessions or devices",
        UDim2.new(0, 10, 0, 31),
        UDim2.new(1, -20, 0, 18),
        9,
        T.Muted,
        T.Body
    )

    local function actionButton(parent, textValue, xScale, xOffset, y, widthScale, widthOffset, color)
        local normal = color or T.Surface3
        local b = C(N("TextButton", {
            Text = textValue, Font = T.Font, TextSize = 10, TextColor3 = T.White,
            BackgroundColor3 = normal, BorderSizePixel = 0, AutoButtonColor = false,
            Position = UDim2.new(xScale, xOffset, 0, y), Size = UDim2.new(widthScale, widthOffset, 0, 38), ZIndex = 8,
        }, parent), 5)
        applyConfigButtonGlow(b, T.Red, .42)
        return b
    end

    local ExportButton = actionButton(TransferPanel, "EXPORT JSON", 0, 10, 57, .5, -13, T.RedDark)
    local ImportButton = actionButton(TransferPanel, "IMPORT JSON", .5, 3, 57, .5, -13, T.RedDark)

    local TransferInfo = C(N("Frame", {
        BackgroundColor3 = T.Input,
        BackgroundTransparency = .25,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 10, 0, 104),
        Size = UDim2.new(1, -20, 0, 70),
    }, TransferPanel), 5)
    S(TransferInfo, T.Line, .72, 1)
    local TransferNote = label(
        TransferInfo,
        "EXPORT copies the selected config as JSON.\nIMPORT reads clipboard JSON or ScoopHub/Configs/import.json.",
        UDim2.new(0, 9, 0, 8),
        UDim2.new(1, -18, 1, -16),
        9,
        T.Muted,
        T.Body
    )
    TransferNote.TextWrapped = true

    ExportButton.Activated:Connect(function()
        local name = requestedName()
        if name == "" then setStatus("Choose a config first", false) return end
        local data = readJSON(existingConfigPath(name))
        if type(data) ~= "table" then
            data = captureConfig(name)
        end
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
        if not ok then setStatus("Export encode failed", false) return end
        ensureFolder()
        local exportPath = CONFIG_DIR .. "/export_" .. safeFileName(name) .. ".json"
        if writefile then pcall(writefile, exportPath, encoded) end
        if setclipboard then pcall(setclipboard, encoded) end
        setStatus("Exported: " .. name, true)
    end)

    ImportButton.Activated:Connect(function()
        local raw = nil
        if getclipboard then
            local ok, value = pcall(getclipboard)
            if ok and type(value) == "string" and value ~= "" then raw = value end
        end
        if not raw and readfile and isfile then
            local importPath = CONFIG_DIR .. "/import.json"
            local exists = false
            pcall(function() exists = isfile(importPath) end)
            if exists then pcall(function() raw = readfile(importPath) end) end
        end
        if type(raw) ~= "string" or raw == "" then
            setStatus("Copy config JSON first", false)
            return
        end
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(data) ~= "table" then
            setStatus("Invalid config JSON", false)
            return
        end

        local name = trim(data.ConfigName)
        if name == "" then name = requestedName() end
        if name == "" then
            setStatus("Type a name for imported config", false)
            return
        end
        data.ConfigName = name
        local wrote = writeJSON(configPath(name), data)
        if wrote then
            addKnown(name)
            currentConfig = name
            NameBox.Text = ""
            setConfigButtonDisplay(name)
            applyConfig(data)
            saveMeta()
            rebuildConfigList("")
            setStatus("Imported: " .. name, true)
        else
            setStatus("Import save failed", false)
        end
    end)

    label(AutoSavePanel, "Automatically save changes to the selected config", UDim2.new(0, 10, 0, 27), UDim2.new(1, -100, 0, 16), 10, T.White, T.Body)
    label(AutoSavePanel, "Only writes when the config JSON actually changes", UDim2.new(0, 10, 0, 42), UDim2.new(1, -100, 0, 12), 8, T.Muted, T.Body)
    local AutoToggle = C(N("TextButton", {
        Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, .5),
        Position = UDim2.new(1, -12, .5, 7), Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = autoSave and T.Red or T.Surface3, BorderSizePixel = 0,
    }, AutoSavePanel), 12)
    local AutoKnob = C(N("Frame", {
        AnchorPoint = Vector2.new(0, .5), Position = autoSave and UDim2.new(1, -21, .5, 0) or UDim2.new(0, 3, .5, 0),
        Size = UDim2.fromOffset(18, 18), BackgroundColor3 = T.White, BorderSizePixel = 0,
    }, AutoToggle), 9)
    local function setAutoSave(value)
        autoSave = value == true
        AutoToggle.BackgroundColor3 = autoSave and T.Red or T.Surface3
        tw(AutoKnob, {Position = autoSave and UDim2.new(1, -21, .5, 0) or UDim2.new(0, 3, .5, 0)}, .12)
        saveMeta()
        if autoSave and currentConfig == "" then
            setStatus("Select/save a config for Auto Save", false)
        elseif autoSave then
            setStatus("Auto Save ON", true)
        else
            setStatus("Auto Save OFF", nil)
        end
    end
    AutoToggle.Activated:Connect(function() setAutoSave(not autoSave) end)

    label(ResetPanel, "Restore Automation + Misc settings to their defaults", UDim2.new(0, 10, 0, 27), UDim2.new(.62, -10, 0, 18), 9, T.Muted, T.Body)
    local ResetButton = C(N("TextButton", {
        Text = "RESET TO DEFAULTS", Font = T.Font, TextSize = 10, TextColor3 = T.White,
        BackgroundColor3 = T.RedDark, BorderSizePixel = 0, AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 15), Size = UDim2.new(.34, 0, 0, 29),
    }, ResetPanel), 5)
    applyConfigButtonGlow(ResetButton, T.Red, .42)
    ResetButton.Activated:Connect(function()
        applyConfig({
            Automation = {
                PlantNames = {}, HarvestNames = {}, SellNames = {},
                PlantEnabled = false, HarvestEnabled = false, SellEnabled = false,
                TrowelEnabled = false, TrowelPlantName = "All Plants", TrowelRarity = "Any",
                TrowelDelay = 1, TrowelPosition = nil,
                PotEnabled = false, PotPlantNames = { "All Plants" }, MergeEnabled = false,
                PlantDelay = 0.18, HarvestMaxKg = 100, SellMaxKg = 3,
                HarvestRarities = {}, HarvestMutations = {}, SellRarities = {}, SellMutations = {},
                HarvestDirection = "Below", SellDirection = "Below",
            },
            Misc = {
                AutoRejoin = false, WalkSpeed = 16, JumpPower = 50,
                NoClip = false, InfiniteJump = false, FPS = "60",
                Cleanup = false, RemoveOtherGardens = false, BackpackValueESP = false,
                GardenESP = {
                    Enabled = false, FruitAll = false, Fruits = {},
                    MutationAll = true, Mutations = {},
                },
            },
        })
        setStatus("Defaults restored", true)
    end)

    local InfoBadge = C(N("Frame", {
        BackgroundColor3 = T.RedDark,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, .5, -8),
        Size = UDim2.fromOffset(34, 16),
    }, InfoPanel), 999)
    local InfoBadgeText = label(InfoBadge, "INFO", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), 7, T.White, T.Font, Enum.TextXAlignment.Center)
    local info = label(InfoPanel,
        "LOAD stays active across rejoin/re-execution. REFRESH rescans files and clears the active config.",
        UDim2.new(0, 50, 0, 5), UDim2.new(1, -58, 0, 32), 9, T.Muted, T.Body)
    info.TextWrapped = true

    Page:GetPropertyChangedSignal("Visible"):Connect(function()
        if not Page.Visible then ConfigDropdown.Visible = false setConfigChevron(false) end
    end)

    Page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if ConfigDropdown.Visible then
            updateDropdownGeometry(math.max(1, math.floor(ConfigScroll.CanvasSize.Y.Offset / dropdownRowHeight)))
        end
    end)

    TrackConnection(UIS.InputBegan:Connect(function(input)
        if not ConfigDropdown.Visible then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local point = input.Position
        local function inside(gui)
            local p = gui.AbsolutePosition local s = gui.AbsoluteSize
            return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
        end
        if not inside(ConfigDropdown) and not inside(ConfigButton) then ConfigDropdown.Visible = false setConfigChevron(false) end
    end))

    task.spawn(function()
        while ScoopHubRunAlive() and SG.Parent do
            -- Config capture/JSON encoding is comparatively expensive. Five seconds
            -- keeps autosave responsive without creating a periodic two-second hitch.
            task.wait(5)
            if autoSave and not configBusy and trim(currentConfig) ~= "" then
                local data = captureConfig(currentConfig)
                local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
                if ok and encoded ~= lastAutoSaveJSON then
                    configBusy = true
                    local wrote = false
                    if writefile and ensureFolder() then wrote = pcall(writefile, configPath(currentConfig), encoded) end
                    if wrote then
                        lastAutoSaveJSON = encoded
                        addKnown(currentConfig)
                        saveMeta()
                    end
                    configBusy = false
                end
            end
        end
    end)

    scanConfigs()
    rebuildConfigList("")

    -- Persist the last explicitly LOADED config across server rejoin/script
    -- execution. Refresh clears activeConfig, so after a refresh this block
    -- intentionally applies nothing on the next execution.
    if activeConfig ~= "" then
        local data, raw = readJSON(existingConfigPath(activeConfig))
        if type(data) == "table" then
            currentConfig = trim(data.ConfigName) ~= "" and trim(data.ConfigName) or activeConfig
            activeConfig = currentConfig
            applyConfig(data)
            addKnown(currentConfig)
            NameBox.Text = ""
            setConfigButtonDisplay(currentConfig)
            lastAutoSaveJSON = type(raw) == "string" and raw or nil
            saveMeta()
            rebuildConfigList("")
            setStatus("Auto-loaded active config: " .. currentConfig, true)
        else
            -- Do not keep retrying a missing/broken active config forever.
            activeConfig = ""
            currentConfig = ""
            NameBox.Text = ""
            setConfigButtonDisplay("Choose config...")
            lastAutoSaveJSON = nil
            saveMeta()
            setStatus("Active config missing \u{2022} choose/load a config", false)
        end
    else
        -- A non-active CurrentConfig from an older build is only a UI choice;
        -- it must not be applied automatically.
        currentConfig = ""
        NameBox.Text = ""
        setConfigButtonDisplay("Choose config...")
        lastAutoSaveJSON = nil
        saveMeta()
        setStatus(#knownConfigs > 0 and "Choose a saved config" or "Type a config name", nil)
    end

    _G.__ScoopHubSilentLog("[ScoopHub] Named Config manager initialized.")
end

__ScoopHubInitConfig()

--==================================================
-- PLACEHOLDERS
--==================================================

for name,p in pairs(Pages) do
    if name~="Auto Buy Pet"
        and name~="Mail"
        and name~="User"
        and name~="Automation"
        and name~="Garden"
        and name~="Shop"
        and name~="Inventory"
        and name~="Config"
        and name~="Misc"
    then
        local f=panel(
            p,
            UDim2.fromScale(0,0),
            UDim2.fromScale(1,1)
        )

        label(
            f,
            string.upper(name),
            UDim2.new(0,0,.5,-16),
            UDim2.new(1,0,0,20),
            14,
            T.Text,
            T.Font,
            Enum.TextXAlignment.Center
        )
    end
end

local originalOpen = open
open = function(name)
    originalOpen(name)

    -- Auto Buy Pet always returns to its own dashboard.  The surrounding
    -- User, Automation, and Config pages stay completely separate.
    if name == "Auto Buy Pet" and _G.ScoopHubAutoBuyPetAPI then
        _G.ScoopHubAutoBuyPetAPI.OpenTab("DASHBOARD")
    end

    if name == "Shop" and _G.ScoopHubShopAPI and _G.ScoopHubShopAPI.Refresh then
        pcall(_G.ScoopHubShopAPI.Refresh)
    end
end
--==================================================
-- WINDOW CONTROLS
--==================================================
-- Close/minimize/restore/drag/Discord behavior is owned by scopsgui.lua.
-- Feature shutdown is wired through Window.OnClose above.

--==================================================
-- NEW LIBRARY SEARCH REGISTRATION
--==================================================
do
    local seen = {}

    local function cleanSearchText(value)
        local result = tostring(value or "")
        result = result:gsub("<[^>]->", "")
        result = result:gsub("^%s+", ""):gsub("%s+$", "")
        result = result:gsub("%s+", " ")
        return result
    end

    local function useful(value)
        value = cleanSearchText(value)
        if #value < 3 or #value > 90 then return false end
        local lower = string.lower(value)
        if lower == "on" or lower == "off" or lower == "ready"
            or lower == "enabled" or lower == "disabled"
            or lower == "search" or lower == "refresh"
            or lower == "none"
        then
            return false
        end
        if lower:match("^%d+$") then return false end
        return true
    end

    for pageName, pageObject in pairs(Pages) do
        local tab = Window.Tabs and Window.Tabs[pageName]
        if tab then
            tab.SearchItems = tab.SearchItems or {}

            tab.SearchItems[#tab.SearchItems + 1] = {
                Title = pageName,
                Target = pageObject,
            }

            for _, instance in ipairs(pageObject:GetDescendants()) do
                if instance:IsA("TextLabel")
                    or instance:IsA("TextButton")
                    or instance:IsA("TextBox")
                then
                    local value = cleanSearchText(instance.Text)
                    local key = string.lower(pageName .. "\31" .. value)

                    if useful(value) and not seen[key] then
                        seen[key] = true
                        tab.SearchItems[#tab.SearchItems + 1] = {
                            Title = value,
                            Target = instance,
                        }
                    end
                end
            end
        end
    end
end

--==================================================
-- API
--==================================================

local API={}

function API:SetStat(k,v) end
function API:SetTargets(v) end
function API:SetAutoBuyEnabled(v) if _G.ScoopHubAutoBuyPetAPI then _G.ScoopHubAutoBuyPetAPI.SetEnabled(v) end end
function API:ForceAutoBuyHop() if _G.ScoopHubAutoBuyPetAPI then _G.ScoopHubAutoBuyPetAPI.ForceHop() end end
function API:OpenPage(v) open(v) end
function API:SetSelectedMailItem(v) end
function API:OpenMailTab(v) if _G.ScoopHubMailAPI then _G.ScoopHubMailAPI.OpenTab(v) end end
function API:RefreshMail() if _G.ScoopHubMailAPI then _G.ScoopHubMailAPI.Refresh() end end

(typeof(getgenv)=="function" and getgenv() or _G).ScoopHubUI=API

open("User")
print("[ScoopHub] PREMIUM V2.2")

--