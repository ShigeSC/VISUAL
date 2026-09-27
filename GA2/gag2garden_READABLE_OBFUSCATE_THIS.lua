-- ScoopHub V2.2 remote page module
-- Readable build: obfuscate this file by itself before uploading.
local Module = {}

function Module.Init(Bridge)
    if type(Bridge) ~= "table" then error("[ScoopHub Pages] Bridge required") end
    local Pages = Bridge.Pages
    local LP = Bridge.LP or game:GetService("Players").LocalPlayer
    local T = Bridge.T
    local N = Bridge.N
    local C = Bridge.C
    local S = Bridge.S
    local tw = Bridge.Tween
    local label = Bridge.Label
    local gradient = Bridge.Gradient
    local TrackConnection = Bridge.TrackConnection
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local ScoopHubRunAlive = Bridge.RunAlive

    if type(Pages) ~= "table" or type(T) ~= "table" then error("[ScoopHub Garden] GUI bridge incomplete") end

--==================================================
-- GARDEN PAGE - GROWING VALUES
-- Integrated from the user's standalone Growing Values tool.
--
-- V43 integration goals:
--   * Native ScoopHub page size/theme (no second 720x520 window)
--   * Sidebar position: Automation -> Garden -> Shop
--   * Filters: OVERALL / READY / GROWING
--   * Search + cached rows + manual Harvest button
--   * Full garden scan only while the Garden page is visible
--   * Hidden page performs no garden scan
--==================================================
(function()
    local Garden = Pages["Garden"]
    if not Garden then
        return
    end

    local RS = game:GetService("ReplicatedStorage")
    local WS = game:GetService("Workspace")
    local P = LP

    local WarningColor = Color3.fromRGB(255, 199, 74)

    local G = {}
    local State = {
        Running = true,
        Refreshing = false,
        RefreshRequested = false,

        SearchText = "",
        CurrentTab = "Overall",

        -- V54 Garden sort / advanced filters.
        SortMode = "Default",
        FilterMulti = true,
        FilterSingle = true,
        FilterMinKG = 0,
        FilterMinValue = 0,
        FilterMutation = "",
        AdvancedUI = {},

        ModuleCache = {},
        ResolveCache = {},
        MultiCache = {},
        MutationCache = {},
        ForeverCache = {},
        GrowRateCache = {},
        SyncCache = {},
        SellNorm = {},
        SingleHarvest = {},

        -- V47 virtualization:
        -- LatestItems/VisibleItems can hold hundreds of lightweight data records,
        -- while RowPool holds only enough physical GUI cards for the viewport.
        RowPool = {},
        VisibleItems = {},
        LatestItems = {},
        PendingHarvest = {},
        VirtualRenderQueued = false,

        -- Manual Garden-tab harvest feedback only.
        ManualHarvestMessage = nil,
        ManualHarvestMessageUntil = 0,
    }

    RegisterScoopHubCleanup(function()
        State.Running = false
    end)

    local function setText(obj, value)
        value = tostring(value or "")
        if obj and obj.Text ~= value then
            obj.Text = value
        end
    end

    local function setColor(obj, color)
        if obj and obj.TextColor3 ~= color then
            obj.TextColor3 = color
        end
    end

    local function need(parent, name, timeout)
        local obj = parent and parent:WaitForChild(name, timeout or 10)
        if not obj then
            error("Missing " .. tostring(name))
        end
        return obj
    end

    local moduleOK, moduleError = pcall(function()
        local SM = need(RS, "SharedModules", 10)

        G.Sell = require(need(SM, "SellValueData", 10))
        G.MutationData = require(need(SM, "MutationData", 10))
        G.SeedData = require(need(SM, "SeedData", 10))
        G.FruitIdentity = require(need(SM, "FruitIdentity", 10))
        G.FruitGrowRate = require(need(SM, "FruitGrowRate", 10))
        G.Networking = require(need(SM, "Networking", 10))
        G.PlantBehaviorRules = require(need(SM, "PlantBehaviorRules", 10))

        local Controllers = need(
            need(P, "PlayerScripts", 10),
            "Controllers",
            10
        )

        G.GardenSync = require(
            need(Controllers, "GardenSyncController", 10)
        )

        local Gen = need(RS, "PlantGenerationModules", 10)
        G.FruitModules = need(Gen, "Fruits", 10)
        G.PlantModules = need(Gen, "Plants", 10)
    end)

    -- ==============================================================
    -- PAGE UI
    -- ==============================================================

    label(
        Garden,
        "GARDEN",
        UDim2.new(0, 4, 0, 2),
        UDim2.new(0.5, -4, 0, 16),
        12,
        T.Text,
        T.Font
    )

    local HeaderStatus = label(
        Garden,
        "READY",
        UDim2.new(0.5, 0, 0, 2),
        UDim2.new(0.5, -5, 0, 16),
        10,
        T.Success,
        T.Font,
        Enum.TextXAlignment.Right
    )

    local TabHolder = C(N("Frame", {
        Position = UDim2.new(0, 3, 0, 22),
        Size = UDim2.new(1, -6, 0, 30),
        BackgroundColor3 = T.Panel,
        BackgroundTransparency = .10,
        BorderSizePixel = 0,
    }, Garden), 6)
    S(TabHolder, T.Line, .30, 1)

    local GardenTabButtons = {}

    local function createGardenTabButton(textValue, index)
        local buttonWidth = 1 / 3

        local b = C(N("TextButton", {
            Name = "Garden" .. textValue .. "Tab",
            Text = textValue,
            Position = UDim2.new((index - 1) * buttonWidth, 3, 0, 3),
            Size = UDim2.new(buttonWidth, -6, 1, -6),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextColor3 = T.Muted,
            Font = T.Font,
            TextSize = 10,
            AutoButtonColor = false,
        }, TabHolder), 5)

        GardenTabButtons[textValue] = b
        return b
    end

    local OverallTab = createGardenTabButton("OVERALL", 1)
    local ReadyTab = createGardenTabButton("READY", 2)
    local GrowingTab = createGardenTabButton("GROWING", 3)

    local Info = label(
        Garden,
        "Open Garden tab to scan...",
        UDim2.new(0, 5, 0, 57),
        UDim2.new(1, -10, 0, 14),
        9,
        T.Muted,
        T.Body
    )

    local Search = C(N("TextBox", {
        Name = "GardenSearch",
        Position = UDim2.new(0, 4, 0, 75),
        Size = UDim2.new(.56, -6, 0, 30),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Search fruit, plant or mutation...",
        PlaceholderColor3 = T.White,
        TextColor3 = T.White,
        TextStrokeTransparency = 1,
        Font = T.Body,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    }, Garden), 6)
    N("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, Search)

    -- V50: self-contained Mail-History-style focus border.
    -- IMPORTANT: do not call Mail's AddFocusBorder() here because that helper
    -- is local to __ScoopHubInitMail() and is not visible in the Garden scope.
    local GardenSearchStroke = N("UIStroke", {
        Color = T.Red,
        Thickness = 1.15,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, Search)

    TrackConnection(
        Search.Focused:Connect(function()
            tw(GardenSearchStroke, {Transparency = 0}, .12)
        end)
    )

    TrackConnection(
        Search.FocusLost:Connect(function()
            tw(GardenSearchStroke, {Transparency = 1}, .12)
        end)
    )

    -- ==============================================================
    -- V54 SORT + ADVANCED FILTER CONTROLS
    -- ==============================================================

    State.AdvancedUI.SortButton = C(N("TextButton", {
        Name = "GardenSortButton",
        Position = UDim2.new(.56, 2, 0, 75),
        Size = UDim2.new(.21, -4, 0, 30),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "SORT: DEFAULT",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 9,
        AutoButtonColor = false,
        ZIndex = 30,
    }, Garden), 6)
    S(State.AdvancedUI.SortButton, T.Line, .62, 1)

    State.AdvancedUI.FilterButton = C(N("TextButton", {
        Name = "GardenFilterButton",
        Position = UDim2.new(.77, 2, 0, 75),
        Size = UDim2.new(.23, -6, 0, 30),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "FILTERS",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 9,
        AutoButtonColor = false,
        ZIndex = 30,
    }, Garden), 6)
    S(State.AdvancedUI.FilterButton, T.Line, .62, 1)

    State.AdvancedUI.SortPanel = C(N("Frame", {
        Name = "GardenSortPanel",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -4, 0, 108),
        Size = UDim2.fromOffset(174, 150),
        BackgroundColor3 = T.Panel,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 300,
    }, Garden), 7)
    S(State.AdvancedUI.SortPanel, T.Line, .18, 1)

    State.AdvancedUI.FilterPanel = C(N("Frame", {
        Name = "GardenAdvancedFilterPanel",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -4, 0, 108),
        Size = UDim2.fromOffset(264, 204),
        BackgroundColor3 = T.Panel,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 300,
    }, Garden), 7)
    S(State.AdvancedUI.FilterPanel, T.Line, .18, 1)

    local function gardenPopupLabel(parent, textValue, position, size, textSize)
        local obj = label(
            parent,
            textValue,
            position,
            size,
            textSize or 9,
            T.Muted,
            T.Font
        )
        obj.ZIndex = 302
        return obj
    end

    gardenPopupLabel(
        State.AdvancedUI.FilterPanel,
        "ADVANCED FILTERS",
        UDim2.fromOffset(9, 6),
        UDim2.new(1, -18, 0, 18),
        10
    )

    gardenPopupLabel(
        State.AdvancedUI.FilterPanel,
        "HARVEST TYPE",
        UDim2.fromOffset(9, 28),
        UDim2.new(1, -18, 0, 14),
        8
    )

    State.AdvancedUI.MultiToggle = C(N("TextButton", {
        Name = "GardenMultiFilter",
        Position = UDim2.fromOffset(9, 44),
        Size = UDim2.new(.5, -13, 0, 25),
        BackgroundColor3 = T.RedDark,
        BorderSizePixel = 0,
        Text = "MULTI  ON",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 9,
        AutoButtonColor = false,
        ZIndex = 302,
    }, State.AdvancedUI.FilterPanel), 5)

    State.AdvancedUI.SingleToggle = C(N("TextButton", {
        Name = "GardenSingleFilter",
        Position = UDim2.new(.5, 4, 0, 44),
        Size = UDim2.new(.5, -13, 0, 25),
        BackgroundColor3 = T.RedDark,
        BorderSizePixel = 0,
        Text = "SINGLE  ON",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 9,
        AutoButtonColor = false,
        ZIndex = 302,
    }, State.AdvancedUI.FilterPanel), 5)

    gardenPopupLabel(
        State.AdvancedUI.FilterPanel,
        "MIN KG",
        UDim2.fromOffset(9, 74),
        UDim2.new(.5, -13, 0, 14),
        8
    )

    gardenPopupLabel(
        State.AdvancedUI.FilterPanel,
        "MIN VALUE",
        UDim2.new(.5, 4, 0, 74),
        UDim2.new(.5, -13, 0, 14),
        8
    )

    local function gardenFilterBox(name, position, size, placeholder)
        local box = C(N("TextBox", {
            Name = name,
            Position = position,
            Size = size,
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = T.Muted,
            TextColor3 = T.White,
            TextStrokeTransparency = 1,
            Font = T.Body,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            ZIndex = 302,
        }, State.AdvancedUI.FilterPanel), 5)

        N("UIPadding", {
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, box)

        local stroke = N("UIStroke", {
            Color = T.Red,
            Thickness = 1.05,
            Transparency = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, box)
        stroke.ZIndex = 303

        TrackConnection(box.Focused:Connect(function()
            tw(stroke, {Transparency = 0}, .10)
        end))

        TrackConnection(box.FocusLost:Connect(function()
            tw(stroke, {Transparency = 1}, .10)
        end))

        return box
    end

    State.AdvancedUI.MinKGBox = gardenFilterBox(
        "GardenMinKG",
        UDim2.fromOffset(9, 89),
        UDim2.new(.5, -13, 0, 25),
        "0"
    )

    State.AdvancedUI.MinValueBox = gardenFilterBox(
        "GardenMinValue",
        UDim2.new(.5, 4, 0, 89),
        UDim2.new(.5, -13, 0, 25),
        "0 / 1m / 500k"
    )

    gardenPopupLabel(
        State.AdvancedUI.FilterPanel,
        "MUTATION",
        UDim2.fromOffset(9, 119),
        UDim2.new(1, -18, 0, 14),
        8
    )

    State.AdvancedUI.MutationBox = gardenFilterBox(
        "GardenMutationFilter",
        UDim2.fromOffset(9, 134),
        UDim2.new(1, -18, 0, 25),
        "All mutations"
    )

    State.AdvancedUI.ResetFilters = C(N("TextButton", {
        Name = "GardenResetFilters",
        Position = UDim2.fromOffset(9, 169),
        Size = UDim2.new(1, -18, 0, 25),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "RESET FILTERS",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 9,
        AutoButtonColor = false,
        ZIndex = 302,
    }, State.AdvancedUI.FilterPanel), 5)
    S(State.AdvancedUI.ResetFilters, T.Line, .58, 1)

    local ListPanel = C(N("Frame", {
        Position = UDim2.new(0, 4, 0, 111),
        Size = UDim2.new(1, -8, 1, -115),
        BackgroundColor3 = T.Panel,
        BackgroundTransparency = .12,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, Garden), 6)
    gradient(
        ListPanel,
        Color3.fromRGB(43, 17, 24),
        Color3.fromRGB(18, 8, 12)
    )
    S(ListPanel, T.Line, .28, 1)

    local Scroll = N("ScrollingFrame", {
        Name = "GardenGrowingValuesList",
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Red,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ClipsDescendants = true,
    }, ListPanel)

    -- V47: fixed-height virtual list geometry. No UIListLayout is used because
    -- only the visible rows physically exist; their Y positions represent the
    -- full filtered list.
    local VIRTUAL_ROW_HEIGHT = 70
    local VIRTUAL_ROW_GAP = 4
    local VIRTUAL_ROW_STRIDE = VIRTUAL_ROW_HEIGHT + VIRTUAL_ROW_GAP
    local VIRTUAL_MIN_ROWS = 8
    local VIRTUAL_MAX_ROWS = 18
    local VIRTUAL_BUFFER_ROWS = 3

    local function updateGardenTabs()
        for name, buttonObject in pairs(GardenTabButtons) do
            local selected =
                (name == "OVERALL" and State.CurrentTab == "Overall")
                or (name == "READY" and State.CurrentTab == "Ready")
                or (name == "GROWING" and State.CurrentTab == "Growing")

            tw(buttonObject, {
                BackgroundTransparency = selected and .12 or 1,
                BackgroundColor3 = selected and T.RedDark or T.Surface2,
                TextColor3 = selected and T.White or T.Muted,
            }, .12)
        end
    end

    -- If modules are unavailable, keep the new tab alive but clearly explain
    -- that the world/game build does not expose the required garden modules.
    if not moduleOK then
        setText(Info, "Garden values unavailable: " .. tostring(moduleError))
        setColor(Info, T.Text)
        setText(HeaderStatus, "UNAVAILABLE")
        setColor(HeaderStatus, T.Text)
        updateGardenTabs()
        return
    end

    -- ==============================================================
    -- DATA HELPERS
    -- ==============================================================

    local function norm(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    for key in pairs(G.Sell) do
        State.SellNorm[norm(key)] = key
    end

    for _, value in pairs(G.SeedData) do
        if type(value) == "table" and value.SeedName then
            State.SingleHarvest[value.SeedName] =
                value.IsSingleHarvest == true
        end
    end

    local function getPlot()
        local gardens = WS:FindFirstChild("Gardens")
        if not gardens then
            return nil
        end

        local plotId = P:GetAttribute("PlotId")

        if plotId then
            local plot = gardens:FindFirstChild("Plot" .. tostring(plotId))
            if plot then
                return plot
            end
        end

        for _, plot in ipairs(gardens:GetChildren()) do
            if plot:GetAttribute("OwnerUserId") == P.UserId
                or plot:GetAttribute("Owner") == P.Name then
                return plot
            end
        end

        return nil
    end

    local function resolveFruit(seed)
        if not seed then
            return nil
        end

        if State.ResolveCache[seed] ~= nil then
            return State.ResolveCache[seed]
        end

        local ok, value = pcall(function()
            return G.FruitIdentity.ResolveFruitName(seed)
        end)

        value = ok and value or seed
        State.ResolveCache[seed] = value

        return value
    end

    local function isMulti(seed)
        if State.MultiCache[seed] ~= nil then
            return State.MultiCache[seed], resolveFruit(seed)
        end

        local name = resolveFruit(seed)
        local value =
            name ~= nil
            and G.FruitModules:FindFirstChild(name) ~= nil
            or false

        State.MultiCache[seed] = value
        return value, name
    end

    local function getModuleData(folder, name)
        if not name then
            return nil
        end

        local key = folder:GetFullName() .. "|" .. tostring(name)

        if State.ModuleCache[key] ~= nil then
            return State.ModuleCache[key] or nil
        end

        local module = folder:FindFirstChild(name)

        if not module then
            local wanted = norm(name)

            for _, candidate in ipairs(folder:GetChildren()) do
                if candidate:IsA("ModuleScript")
                    and norm(candidate.Name) == wanted then
                    module = candidate
                    break
                end
            end
        end

        if not module or not module:IsA("ModuleScript") then
            State.ModuleCache[key] = false
            return nil
        end

        local ok, data = pcall(require, module)

        if not ok or type(data) ~= "table" then
            State.ModuleCache[key] = false
            return nil
        end

        State.ModuleCache[key] = data
        return data
    end

    local function baseWeight(folder, name)
        local data = getModuleData(folder, name)

        return data
            and data.GrowData
            and tonumber(data.GrowData.BaseWeight)
            or nil
    end

    local function mutationMulti(name)
        if not name or name == "" then
            return 1
        end

        if State.MutationCache[name] ~= nil then
            return State.MutationCache[name]
        end

        local ok, value = pcall(function()
            return G.MutationData.ReturnPriceMultiplier(name)
        end)

        value = ok and tonumber(value) or 1
        State.MutationCache[name] = value

        return value
    end

    local function growsForever(name)
        if not name then
            return false
        end

        if State.ForeverCache[name] ~= nil then
            return State.ForeverCache[name]
        end

        local ok, value = pcall(function()
            return G.PlantBehaviorRules.GrowsForever(name)
        end)

        value = ok and value == true
        State.ForeverCache[name] = value

        return value
    end

    local function getFruitGrowRate(name)
        if not name then
            return .025
        end

        if State.GrowRateCache[name] ~= nil then
            return State.GrowRateCache[name]
        end

        local ok, value = pcall(function()
            return G.FruitGrowRate(name)
        end)

        value = ok and tonumber(value) or .025

        if not value or value <= 0 then
            value = .025
        end

        State.GrowRateCache[name] = value
        return value
    end

    local function sellKey(...)
        local names = {...}

        for _, name in ipairs(names) do
            if name and G.Sell[name] ~= nil then
                return name
            end
        end

        for _, name in ipairs(names) do
            if name then
                local found = State.SellNorm[norm(name)]

                if found then
                    return found
                end
            end
        end

        return names[1]
    end

    -- Preserve the standalone Growing Values price model exactly.
    local function calculateValue(name, size, mutation, decayAlpha)
        if not name then
            return 0
        end

        local base = tonumber(G.Sell[name]) or 0
        size = tonumber(size) or 1

        local exponent = 2.5

        if name == "Mushroom" then
            exponent = 1.9
        elseif name == "Bamboo" then
            exponent = 1.75
        end

        local sizeValue = size ^ exponent
        local knee = 5
        local tailExponent = 1.5

        if size > knee then
            sizeValue =
                knee ^ exponent
                * (size / knee) ^ math.min(tailExponent, exponent)
        end

        local mutationValue = 1

        if mutation and mutation ~= "" then
            mutationValue = mutationMulti(mutation)

            if State.SingleHarvest[name] and mutationValue > 1 then
                mutationValue =
                    1 + (mutationValue - 1) * .15
            end
        end

        local decayMultiplier = 1

        if type(decayAlpha) == "number" and decayAlpha > 0 then
            decayMultiplier =
                1 - math.clamp(decayAlpha, 0, 1) * .8
        end

        local friends = tonumber(P:GetAttribute("Friends")) or 0
        local friendMultiplier = 1 + friends * .1

        local value = math.floor(
            base
            * sizeValue
            * mutationValue
            * decayMultiplier
            * friendMultiplier
        )

        if name == "Carrot" then
            value = math.max(value, 4)
        end

        return value
    end

    local function resetSyncCache()
        table.clear(State.SyncCache)
    end

    local function syncedPlant(plant)
        local cached = State.SyncCache[plant]

        if cached ~= nil then
            return cached ~= false and cached or nil
        end

        local userId =
            tonumber(plant:GetAttribute("UserId"))
            or P.UserId

        local plantId = plant:GetAttribute("PlantId")

        if not plantId then
            State.SyncCache[plant] = false
            return nil
        end

        local ok, data = pcall(function()
            return G.GardenSync:GetPlant(userId, plantId)
        end)

        if not ok or type(data) ~= "table" then
            State.SyncCache[plant] = false
            return nil
        end

        State.SyncCache[plant] = data
        return data
    end

    local function syncedFruit(plantData, fruit)
        if not plantData or type(plantData.Fruits) ~= "table" then
            return nil
        end

        local fruitId = fruit:GetAttribute("FruitId")

        if fruitId == nil then
            return nil
        end

        return plantData.Fruits[fruitId]
            or plantData.Fruits[tostring(fruitId)]
    end

    local function atlanticGrowth(seconds)
        seconds = math.max(tonumber(seconds) or 0, 0)

        if seconds <= 0 then
            return 1
        end

        return math.min(
            1 + .0128 * (math.log(1 + seconds / 1800) ^ 2.55),
            25
        )
    end

    local function multiInfo(plant, fruit, plantData, serverNow)
        local seed = plant:GetAttribute("SeedName")
        local resolved = resolveFruit(seed)
        local core = fruit:GetAttribute("CorePartName") or resolved
        local synced = syncedFruit(plantData, fruit)

        local size =
            tonumber(fruit:GetAttribute("SizeMulti"))
            or tonumber(synced and synced.SizeMultiplier)
            or tonumber(fruit:GetAttribute("SizeMultiplier"))
            or 1

        local overtime =
            tonumber(synced and synced.OvertimeGrowth)
            or tonumber(fruit:GetAttribute("OvertimeGrowth"))
            or 1

        overtime = math.max(overtime, 1)

        local isAtlantic =
            norm(resolved) == "atlanticgiantpumpkin"
            or norm(core) == "atlanticgiantpumpkin"
            or norm(seed) == "atlanticgiantpumpkin"

        if isAtlantic then
            local finished =
                tonumber(synced and synced.FinishedGrowingAt)
                or tonumber(fruit:GetAttribute("FinishedGrowingAt"))

            if finished and finished > 0 then
                overtime = atlanticGrowth(
                    math.max(serverNow - finished, 0)
                )
            end
        end

        local weightBase = baseWeight(G.FruitModules, core)

        if not weightBase and resolved then
            weightBase = baseWeight(G.FruitModules, resolved)
        end

        weightBase = weightBase or 0

        local expectedKG = weightBase * size
        local weight = expectedKG * overtime

        local mutation =
            (synced and synced.Mutation)
            or fruit:GetAttribute("Mutation")

        if mutation == "" then
            mutation = nil
        end

        local valueName = sellKey(core, resolved, seed)

        local decay =
            (synced and synced.DecayAlpha)
            or fruit:GetAttribute("DecayAlpha")

        local value = calculateValue(
            valueName,
            size,
            mutation,
            decay
        )

        local age =
            tonumber(fruit:GetAttribute("Age"))
            or tonumber(synced and synced.Age)
            or 0

        local maxAge =
            tonumber(fruit:GetAttribute("MaxAge"))
            or tonumber(synced and synced.MaxAge)
            or 0

        local rate =
            tonumber(synced and synced.GrowRate)
            or tonumber(fruit:GetAttribute("GrowRate"))

        if not rate or rate <= 0 then
            rate = getFruitGrowRate(seed or resolved or core)
        end

        local plantId = plant:GetAttribute("PlantId")
        local fruitId = fruit:GetAttribute("FruitId")

        return {
            key = "M|" .. tostring(plantId) .. "|" .. tostring(fruitId),
            name = seed or resolved or core or fruit.Name,
            type = "Multi",

            kg = weight,
            expectedKG = expectedKG,
            value = value,

            size = size,
            overtime = overtime,

            mutation = mutation,
            multi = mutationMulti(mutation),

            age = age,
            max = maxAge,
            growRate = rate,

            object = fruit,
            plant = plant,

            plantId = plantId,
            fruitId = fruitId,

            forever = growsForever(core or resolved),
            atlantic = isAtlantic,
        }
    end

    local function singleInfo(plant, plantData)
        if not plantData then
            return nil
        end

        local seed = plant:GetAttribute("SeedName")
        local resolved = resolveFruit(seed)

        local size = tonumber(plantData.SizeMultiplier) or 1
        local overtime =
            math.max(tonumber(plantData.OvertimeGrowth) or 1, 1)

        local weightBase =
            baseWeight(G.PlantModules, seed)
            or baseWeight(G.PlantModules, plantData.PlantName)
            or 0

        local expectedKG = weightBase * size
        local weight =
            tonumber(plantData.Weight)
            or expectedKG * overtime

        local mutation =
            plantData.Mutation
            or plant:GetAttribute("Mutation")

        if mutation == "" then
            mutation = nil
        end

        local valueName = sellKey(
            resolved,
            seed,
            plantData.PlantName
        )

        local decay =
            plantData.DecayAlpha
            or plant:GetAttribute("DecayAlpha")

        local value = calculateValue(
            valueName,
            size,
            mutation,
            decay
        )

        local age =
            tonumber(plant:GetAttribute("Age"))
            or tonumber(plantData.Age)
            or 0

        local maxAge =
            tonumber(plant:GetAttribute("MaxAge"))
            or tonumber(plantData.MaxAge)
            or 0

        local rate =
            tonumber(plantData.GrowRate)
            or tonumber(plant:GetAttribute("GrowRate"))
            or tonumber(plant:GetAttribute("GrowRateMulti"))
            or 1

        if rate <= 0 then
            rate = 1
        end

        local plantId = plant:GetAttribute("PlantId")

        return {
            key = "S|" .. tostring(plantId),
            name = seed or plantData.PlantName or plant.Name,
            type = "Single",

            kg = weight,
            expectedKG = expectedKG,
            value = value,

            size = size,
            overtime = overtime,

            mutation = mutation,
            multi = mutationMulti(mutation),

            age = age,
            max = maxAge,
            growRate = rate,

            object = plant,
            plant = plant,

            plantId = plantId,
            fruitId = "",

            forever = growsForever(resolved or seed),
            atlantic = false,
        }
    end

    -- V53: age/countdown continue locally between full garden scans.
    -- A scan records _snapshotClock on each item, then visible rows can
    -- advance age cheaply from elapsed local time instead of rescanning.
    local function getCurrentAge(data)
        local age = tonumber(data.age) or 0
        local maxAge = tonumber(data.max) or 0

        if maxAge <= 0 then
            return age
        end

        local rate = tonumber(data.growRate) or 1
        if rate <= 0 then
            rate = 1
        end

        local snapshotClock = tonumber(data._snapshotClock)
        if snapshotClock then
            age += math.max(0, os.clock() - snapshotClock) * rate
        end

        return math.min(age, maxAge)
    end

    local function isReady(data)
        return data.max <= 0 or getCurrentAge(data) >= data.max
    end

    local function getRemaining(data)
        if data.max <= 0 then
            return 0
        end

        local rate = tonumber(data.growRate) or 1

        if rate <= 0 then
            rate = 1
        end

        return math.max(
            (data.max - getCurrentAge(data)) / rate,
            0
        )
    end

    local function fmtTime(seconds)
        seconds = math.max(
            0,
            math.ceil(tonumber(seconds) or 0)
        )

        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = seconds % 60

        if hours > 0 then
            return string.format(
                "%02d:%02d:%02d",
                hours,
                minutes,
                secs
            )
        end

        return string.format("%02d:%02d", minutes, secs)
    end

    local function fmt(value)
        value = tonumber(value) or 0

        local result

        if value >= 1e24 then
            result = string.format("%.2fSp", value / 1e24)
        elseif value >= 1e21 then
            result = string.format("%.2fSx", value / 1e21)
        elseif value >= 1e18 then
            result = string.format("%.2fQi", value / 1e18)
        elseif value >= 1e15 then
            result = string.format("%.2fQ", value / 1e15)
        elseif value >= 1e12 then
            result = string.format("%.2fT", value / 1e12)
        elseif value >= 1e9 then
            result = string.format("%.2fB", value / 1e9)
        elseif value >= 1e6 then
            result = string.format("%.2fM", value / 1e6)
        elseif value >= 1e3 then
            result = string.format("%.2fK", value / 1e3)
        else
            return tostring(math.floor(value))
        end

        return result
            :gsub("%.00", "")
            :gsub("(%.[0-9])0", "%1")
    end

    local function fmtkg(value)
        value = tonumber(value)

        if not value then
            return "? kg"
        end

        if value >= 1000000 then
            return string.format("%.2fM kg", value / 1000000)
        elseif value >= 1000 then
            return string.format("%.2fK kg", value / 1000)
        end

        return string.format("%.2f kg", value)
    end

    local function searchMatch(data)
        if State.SearchText == "" then
            return true
        end

        local query = State.SearchText:lower()
        local name = tostring(data.name or ""):lower()
        local mutation = tostring(data.mutation or ""):lower()

        return string.find(name, query, 1, true) ~= nil
            or string.find(mutation, query, 1, true) ~= nil
    end

    local function getDisplayedKG(data)
        if isReady(data) then
            return tonumber(data.kg) or 0
        end

        return tonumber(data.expectedKG)
            or tonumber(data.kg)
            or 0
    end

    local function advancedFilterMatch(data)
        if data.type == "Multi" and not State.FilterMulti then
            return false
        end

        if data.type ~= "Multi" and not State.FilterSingle then
            return false
        end

        if getDisplayedKG(data) < (tonumber(State.FilterMinKG) or 0) then
            return false
        end

        if (tonumber(data.value) or 0) < (tonumber(State.FilterMinValue) or 0) then
            return false
        end

        local mutationFilter =
            tostring(State.FilterMutation or ""):lower()

        if mutationFilter ~= "" then
            local mutation =
                tostring(data.mutation or "Normal"):lower()

            if not string.find(
                mutation,
                mutationFilter,
                1,
                true
            ) then
                return false
            end
        end

        return true
    end

    local function itemVisible(data)
        if not searchMatch(data)
            or not advancedFilterMatch(data) then
            return false
        end

        if State.CurrentTab == "Ready" then
            return isReady(data)
        elseif State.CurrentTab == "Growing" then
            return not isReady(data)
        end

        return true
    end

    local function sortVisibleItems(items)
        local mode = State.SortMode

        if mode == "Default" or #items <= 1 then
            return
        end

        table.sort(items, function(a, b)
            if mode == "Highest Value" then
                local av = tonumber(a.value) or 0
                local bv = tonumber(b.value) or 0

                if av ~= bv then
                    return av > bv
                end

                return getDisplayedKG(a) > getDisplayedKG(b)
            elseif mode == "Highest KG" then
                local ak = getDisplayedKG(a)
                local bk = getDisplayedKG(b)

                if math.abs(ak - bk) > .0001 then
                    return ak > bk
                end

                return (tonumber(a.value) or 0)
                    > (tonumber(b.value) or 0)
            elseif mode == "Fastest Ready" then
                local ar = isReady(a)
                local br = isReady(b)

                if ar ~= br then
                    return ar
                end

                if not ar then
                    local at = getRemaining(a)
                    local bt = getRemaining(b)

                    if math.abs(at - bt) > .01 then
                        return at < bt
                    end
                end

                return (tonumber(a.value) or 0)
                    > (tonumber(b.value) or 0)
            elseif mode == "Name A-Z" then
                local an = tostring(a.name or ""):lower()
                local bn = tostring(b.name or ""):lower()

                if an ~= bn then
                    return an < bn
                end

                return (tonumber(a.value) or 0)
                    > (tonumber(b.value) or 0)
            end

            return false
        end)
    end

    -- ==============================================================
    -- ROWS - V47 VIRTUALIZED
    --
    -- Data count can be 700+ while physical GUI row count stays near the
    -- viewport size (normally ~8-12, hard-capped at 18).
    -- ==============================================================

    local applyVisibilityAndSummary
    local requestRefresh
    local harvestItem
    local renderVirtualRows

    local function createVirtualRow()
        local Row = C(N("Frame", {
            Name = "GardenValueRow",
            Position = UDim2.new(0, 1, 0, 0),
            Size = UDim2.new(1, -4, 0, VIRTUAL_ROW_HEIGHT),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = .05,
            BorderSizePixel = 0,
            Visible = false,
        }, Scroll), 6)
        S(Row, T.Line, .58, 1)

        local Name = label(
            Row,
            "",
            UDim2.new(0, 8, 0, 3),
            UDim2.new(.34, -8, 0, 23),
            11,
            T.White,
            T.Font
        )
        Name.TextTruncate = Enum.TextTruncate.AtEnd

        local KG = label(
            Row,
            "",
            UDim2.new(.34, 0, 0, 3),
            UDim2.new(.17, -2, 0, 23),
            11,
            T.Success,
            T.Font,
            Enum.TextXAlignment.Right
        )

        local Value = label(
            Row,
            "",
            UDim2.new(.51, 0, 0, 3),
            UDim2.new(.16, -3, 0, 23),
            11,
            WarningColor,
            T.Font,
            Enum.TextXAlignment.Right
        )

        local Status = label(
            Row,
            "",
            UDim2.new(.67, 2, 0, 1),
            UDim2.new(.17, -4, 0, 27),
            9,
            T.Muted,
            T.Font,
            Enum.TextXAlignment.Center
        )
        Status.TextWrapped = true

        local Harvest = C(N("TextButton", {
            Text = "Harvest",
            Position = UDim2.new(.84, 2, 0, 4),
            Size = UDim2.new(.16, -8, 0, 23),
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 9,
            AutoButtonColor = false,
        }, Row), 5)

        local Details = label(
            Row,
            "",
            UDim2.new(0, 8, 0, 29),
            UDim2.new(1, -16, 0, 17),
            10,
            T.Muted,
            T.Body
        )
        Details.TextTruncate = Enum.TextTruncate.AtEnd

        local Expected = label(
            Row,
            "",
            UDim2.new(0, 8, 0, 49),
            UDim2.new(1, -16, 0, 15),
            9,
            T.Success,
            T.Font
        )
        Expected.TextTruncate = Enum.TextTruncate.AtEnd

        local record = {
            Frame = Row,
            Name = Name,
            KG = KG,
            Value = Value,
            Status = Status,
            Harvest = Harvest,
            Details = Details,
            Expected = Expected,
            Data = nil,
            ItemIndex = 0,
        }

        TrackConnection(
            Harvest.Activated:Connect(function()
                local data = record.Data
                if data then
                    harvestItem(data, Harvest)
                end
            end)
        )

        State.RowPool[#State.RowPool + 1] = record
        return record
    end

    local function requiredVirtualRows()
        local viewportHeight = Scroll.AbsoluteWindowSize.Y

        if not viewportHeight or viewportHeight <= 0 then
            viewportHeight = Scroll.AbsoluteSize.Y
        end

        local required =
            math.ceil(math.max(viewportHeight, VIRTUAL_ROW_HEIGHT)
                / VIRTUAL_ROW_STRIDE)
            + VIRTUAL_BUFFER_ROWS

        return math.clamp(
            required,
            VIRTUAL_MIN_ROWS,
            VIRTUAL_MAX_ROWS
        )
    end

    local function ensureVirtualRowPool()
        local required = requiredVirtualRows()

        while #State.RowPool < required do
            createVirtualRow()
        end
    end

    local function updateRow(record, data, itemIndex)
        record.Data = data
        record.ItemIndex = itemIndex

        local ready = isReady(data)
        local displayedKG = getDisplayedKG(data)

        local targetY =
            (itemIndex - 1) * VIRTUAL_ROW_STRIDE + 1

        local targetPosition =
            UDim2.new(0, 1, 0, targetY)

        if record.Frame.Position ~= targetPosition then
            record.Frame.Position = targetPosition
        end

        if not record.Frame.Visible then
            record.Frame.Visible = true
        end

        setText(record.Name, data.name)
        setText(record.KG, fmtkg(displayedKG))
        setText(record.Value, "$ " .. fmt(data.value))

        if ready then
            setText(record.Status, "READY")
            setColor(record.Status, T.Success)

            setText(record.Harvest, "Harvest")
            record.Harvest.BackgroundColor3 = T.RedDark
            record.Harvest.TextColor3 = T.White
            record.Harvest.Active = true
        else
            setText(
                record.Status,
                "NOT READY\n" .. fmtTime(getRemaining(data))
            )
            setColor(record.Status, WarningColor)

            setText(record.Harvest, "Growing")
            record.Harvest.BackgroundColor3 = T.Surface3
            record.Harvest.TextColor3 = T.Muted
            record.Harvest.Active = false
        end

        local currentAge = getCurrentAge(data)

        local growth =
            data.max > 0
            and math.floor(
                math.clamp(currentAge / data.max, 0, 1) * 100
            )
            or 0

        local mutationText = ""

        if data.mutation then
            mutationText =
                " | "
                .. tostring(data.mutation)
                .. " x"
                .. tostring(data.multi)
        end

        local overtimeText = ""

        if data.overtime and data.overtime > 1.0001 then
            overtimeText =
                " | Overtime x"
                .. string.format("%.3f", data.overtime)
        end

        setText(
            record.Details,
            data.type
            .. " Harvest | Size x"
            .. string.format("%.3f", data.size)
            .. " | Growth "
            .. tostring(growth)
            .. "%"
            .. overtimeText
            .. mutationText
        )

        if not ready then
            setText(
                record.Expected,
                "Expected at 100%: " .. fmtkg(data.expectedKG)
            )
        elseif data.atlantic and data.overtime > 1.0001 then
            setText(
                record.Expected,
                "Mature KG: "
                .. fmtkg(data.expectedKG)
                .. " | Current KG: "
                .. fmtkg(data.kg)
            )
        else
            setText(record.Expected, "Fully grown")
        end
    end

    local function updateVirtualCanvas()
        local count = #State.VisibleItems
        local canvasHeight = 0

        if count > 0 then
            canvasHeight =
                count * VIRTUAL_ROW_STRIDE
                - VIRTUAL_ROW_GAP
                + 2
        end

        local targetCanvas =
            UDim2.new(0, 0, 0, canvasHeight)

        if Scroll.CanvasSize ~= targetCanvas then
            Scroll.CanvasSize = targetCanvas
        end

        local viewportHeight = Scroll.AbsoluteWindowSize.Y

        if not viewportHeight or viewportHeight <= 0 then
            viewportHeight = Scroll.AbsoluteSize.Y
        end

        local maxY =
            math.max(0, canvasHeight - viewportHeight)

        if Scroll.CanvasPosition.Y > maxY then
            Scroll.CanvasPosition =
                Vector2.new(0, maxY)
        end
    end

    renderVirtualRows = function()
        if not State.Running
            or not ScoopHubRunAlive()
            or not Scroll.Parent then
            return
        end

        ensureVirtualRowPool()

        local visibleItems = State.VisibleItems
        local firstIndex =
            math.floor(
                math.max(0, Scroll.CanvasPosition.Y)
                / VIRTUAL_ROW_STRIDE
            ) + 1

        for poolIndex, record in ipairs(State.RowPool) do
            local itemIndex = firstIndex + poolIndex - 1
            local data = visibleItems[itemIndex]

            if data then
                updateRow(record, data, itemIndex)
            else
                record.Data = nil
                record.ItemIndex = 0

                if record.Frame.Visible then
                    record.Frame.Visible = false
                end
            end
        end
    end

    local function queueVirtualRender()
        if State.VirtualRenderQueued then
            return
        end

        State.VirtualRenderQueued = true

        task.defer(function()
            State.VirtualRenderQueued = false

            if State.Running
                and ScoopHubRunAlive()
                and Garden.Parent then
                renderVirtualRows()
            end
        end)
    end

    applyVisibilityAndSummary = function()
        local visibleItems = {}
        local shown = 0
        local readyCount = 0
        local growingCount = 0
        local multiCount = 0
        local singleCount = 0
        local total = 0

        -- Important: this loop touches lightweight Lua records only.
        -- It no longer creates/hides/updates one GuiObject tree per item.
        for _, data in ipairs(State.LatestItems) do
            if itemVisible(data) then
                visibleItems[#visibleItems + 1] = data
                shown += 1
                total += data.value

                if isReady(data) then
                    readyCount += 1
                else
                    growingCount += 1
                end

                if data.type == "Multi" then
                    multiCount += 1
                else
                    singleCount += 1
                end
            end
        end

        sortVisibleItems(visibleItems)

        State.VisibleItems = visibleItems
        updateVirtualCanvas()
        renderVirtualRows()

        -- Keep a manual-harvest warning visible briefly instead of letting the
        -- normal Garden summary overwrite it on the next lightweight refresh.
        if State.ManualHarvestMessage
            and os.clock() < (tonumber(State.ManualHarvestMessageUntil) or 0) then
            setText(Info, State.ManualHarvestMessage)
            setColor(Info, WarningColor)
            return
        elseif State.ManualHarvestMessage then
            State.ManualHarvestMessage = nil
            State.ManualHarvestMessageUntil = 0
        end

        if shown == 0 then
            local advancedFiltersActive =
                not State.FilterMulti
                or not State.FilterSingle
                or (tonumber(State.FilterMinKG) or 0) > 0
                or (tonumber(State.FilterMinValue) or 0) > 0
                or tostring(State.FilterMutation or "") ~= ""

            if State.SearchText ~= "" then
                setText(
                    Info,
                    "No matching fruits, plants or mutations"
                )
            elseif advancedFiltersActive then
                setText(Info, "No items match current filters")
            elseif State.CurrentTab == "Ready" then
                setText(Info, "No fully grown fruits")
            elseif State.CurrentTab == "Growing" then
                setText(Info, "No growing plants")
            else
                setText(Info, "No plants found")
            end

            return
        end

        setText(
            Info,
            tostring(shown)
            .. " items  •  Ready "
            .. tostring(readyCount)
            .. "  •  Growing "
            .. tostring(growingCount)
            .. "  •  Multi "
            .. tostring(multiCount)
            .. "  •  Single "
            .. tostring(singleCount)
            .. "  •  $"
            .. fmt(total)
        )
    end

    TrackConnection(
        Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            queueVirtualRender()
        end)
    )

    TrackConnection(
        Scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
            updateVirtualCanvas()
            queueVirtualRender()
        end)
    )

    -- ==============================================================
    -- MANUAL GARDEN HARVEST DELIVERY CHECK
    -- ==============================================================
    -- This belongs only to the Garden tab's manual Harvest button.
    -- Auto Harvest / Automation workers are intentionally untouched.
    --
    -- A normal harvest should create a new HarvestedFruit inventory entry.
    -- Track unique fruit Ids so a fruit that briefly enters Backpack and is
    -- immediately moved/sold still counts as successfully delivered.
    local GardenHarvestDeliveryRevision = 0
    local GardenKnownHarvestedFruitIds = {}

    local function registerGardenHarvestedFruit(item, countAsDelivery)
        if not item or not item.Parent then
            return false
        end

        if item:GetAttribute("HarvestedFruit") ~= true then
            return false
        end

        local fruitId = item:GetAttribute("Id")
        if fruitId == nil or tostring(fruitId) == "" then
            return false
        end

        local key = tostring(fruitId)
        if GardenKnownHarvestedFruitIds[key] then
            return true
        end

        GardenKnownHarvestedFruitIds[key] = true

        if countAsDelivery then
            GardenHarvestDeliveryRevision += 1
        end

        return true
    end

    local function watchGardenHarvestInventoryItem(item)
        if registerGardenHarvestedFruit(item, true) then
            return
        end

        local connection
        connection = item.AttributeChanged:Connect(function(attributeName)
            if attributeName ~= "HarvestedFruit" and attributeName ~= "Id" then
                return
            end

            if registerGardenHarvestedFruit(item, true) and connection then
                connection:Disconnect()
                connection = nil
            end
        end)

        TrackConnection(connection)

        task.delay(2, function()
            if connection then
                pcall(function()
                    connection:Disconnect()
                end)
                connection = nil
            end
        end)
    end

    local function watchGardenHarvestInventoryContainer(container)
        if not container then
            return
        end

        -- Prime existing IDs without counting them as a new delivery.
        for _, item in ipairs(container:GetChildren()) do
            registerGardenHarvestedFruit(item, false)
        end

        TrackConnection(container.ChildAdded:Connect(function(item)
            watchGardenHarvestInventoryItem(item)
        end))
    end

    local GardenBackpack = P:FindFirstChild("Backpack") or P:WaitForChild("Backpack", 10)
    watchGardenHarvestInventoryContainer(GardenBackpack)

    if P.Character then
        watchGardenHarvestInventoryContainer(P.Character)
    end

    TrackConnection(P.CharacterAdded:Connect(function(character)
        watchGardenHarvestInventoryContainer(character)
    end))

    -- Garden-only harvest warning.  Keep this inside the Garden page instead of
    -- using Auto Harvest/Auto Buy notifications, so manual Garden harvesting is
    -- the only system that can show it.
    local GardenHarvestWarningToast = nil
    local GardenHarvestWarningText = nil
    local GardenHarvestWarningSerial = 0

    local function ensureGardenHarvestWarningToast()
        if GardenHarvestWarningToast and GardenHarvestWarningToast.Parent then
            return GardenHarvestWarningToast
        end

        GardenHarvestWarningToast = C(N("Frame", {
            Name = "GardenHarvestWarning",
            AnchorPoint = Vector2.new(.5, 1),
            Position = UDim2.new(.5, 0, 1, -8),
            Size = UDim2.new(1, -24, 0, 54),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = .03,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 220,
        }, Garden), 7)

        N("UIStroke", {
            Color = WarningColor,
            Thickness = 1.4,
            Transparency = .08,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, GardenHarvestWarningToast)

        N("TextLabel", {
            Name = "Title",
            Text = "RETURN TO YOUR GARDEN",
            Position = UDim2.new(0, 12, 0, 6),
            Size = UDim2.new(1, -24, 0, 17),
            BackgroundTransparency = 1,
            TextColor3 = WarningColor,
            Font = T.Font,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 221,
        }, GardenHarvestWarningToast)

        GardenHarvestWarningText = N("TextLabel", {
            Name = "Message",
            Text = "",
            Position = UDim2.new(0, 12, 0, 24),
            Size = UDim2.new(1, -24, 0, 22),
            BackgroundTransparency = 1,
            TextColor3 = T.Text,
            Font = T.Body,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 221,
        }, GardenHarvestWarningToast)

        return GardenHarvestWarningToast
    end

    local function showReturnToGardenMessage()
        local message =
            "Harvest did not reach your Backpack. Return to your garden and try again."

        -- Keep the lightweight Garden info line as a secondary status, but make
        -- the real warning impossible to miss with a large Garden-page toast.
        State.ManualHarvestMessage = message
        State.ManualHarvestMessageUntil = os.clock() + 4.5
        setText(Info, message)
        setColor(Info, WarningColor)

        local toast = ensureGardenHarvestWarningToast()
        GardenHarvestWarningSerial += 1
        local mySerial = GardenHarvestWarningSerial

        if GardenHarvestWarningText then
            GardenHarvestWarningText.Text = message
        end
        toast.Visible = true

        task.delay(4.5, function()
            if not State.Running or not ScoopHubRunAlive() then
                return
            end

            if mySerial ~= GardenHarvestWarningSerial then
                return
            end

            if toast and toast.Parent then
                toast.Visible = false
            end

            if os.clock() >= (tonumber(State.ManualHarvestMessageUntil) or 0) then
                State.ManualHarvestMessage = nil
                State.ManualHarvestMessageUntil = 0

                if requestRefresh then
                    requestRefresh()
                end
            end
        end)
    end

    -- ==============================================================
    -- HARVEST
    -- ==============================================================

    -- Atlantic Giant Pumpkin shows the game's "Harvest?" confirmation because
    -- it can keep growing forever. Only the Garden tab's MANUAL Harvest button
    -- arms this short-lived confirmer; Auto Harvest and every other GUI remain
    -- untouched.
    local function getGardenConfirmButtonText(button)
        if not button or not button:IsA("GuiButton") then
            return ""
        end

        if button:IsA("TextButton") then
            local text = tostring(button.Text or "")
            if text ~= "" then
                return string.lower(text:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
            end
        end

        for _, child in ipairs(button:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                local text = tostring(child.Text or "")
                if text ~= "" then
                    return string.lower(text:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
                end
            end
        end

        return ""
    end

    local function clickGardenConfirmButton(button)
        if not button or not button.Parent or not button:IsA("GuiButton") then
            return false
        end

        if type(firesignal) == "function" then
            local ok = pcall(function()
                firesignal(button.Activated)
            end)
            if ok then
                return true
            end
        end

        local ok, vim = pcall(function()
            return game:GetService("VirtualInputManager")
        end)
        if not ok or not vim then
            return false
        end

        local center = button.AbsolutePosition + (button.AbsoluteSize / 2)
        return pcall(function()
            vim:SendMouseMoveEvent(center.X, center.Y, game)
            vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            task.wait(0.04)
            vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end)
    end

    local function tryConfirmAtlanticHarvestPopup()
        local playerGui = P:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            return false
        end

        local messageObject = nil

        for _, object in ipairs(playerGui:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible then
                local text = string.lower(tostring(object.Text or ""))
                if text:find("grow forever", 1, true)
                    and text:find("harvest", 1, true) then
                    messageObject = object
                    break
                end
            end
        end

        if not messageObject then
            return false
        end

        -- Requiring BOTH Yes and No keeps this scoped to the harvest warning
        -- instead of clicking an unrelated Yes button elsewhere in PlayerGui.
        local container = messageObject.Parent
        for _ = 1, 8 do
            if not container or container == playerGui then
                break
            end

            local yesButton = nil
            local hasNoButton = false

            for _, object in ipairs(container:GetDescendants()) do
                if object:IsA("GuiButton") and object.Visible then
                    local text = getGardenConfirmButtonText(object)
                    if text == "yes" then
                        yesButton = object
                    elseif text == "no" then
                        hasNoButton = true
                    end
                end
            end

            if yesButton and hasNoButton then
                -- Hide only this harvest-confirmation container before firing Yes.
                -- Because the confirmer is armed before HarvestPrompt fires, this
                -- normally happens before Roblox renders the popup at all.
                if container:IsA("GuiObject") and type(firesignal) == "function" then
                    local wasVisible = container.Visible
                    container.Visible = false

                    local clicked = clickGardenConfirmButton(yesButton)
                    if clicked then
                        -- The game's handler normally removes the confirmation
                        -- immediately. Restore only as a fail-safe if it somehow
                        -- remains alive instead of leaving unrelated UI hidden.
                        task.delay(0.35, function()
                            if container and container.Parent then
                                container.Visible = wasVisible
                            end
                        end)
                        return true
                    end

                    container.Visible = wasVisible
                end

                return clickGardenConfirmButton(yesButton)
            end

            container = container.Parent
        end

        return false
    end

    local function armAtlanticHarvestAutoConfirm()
        local playerGui = P:FindFirstChildOfClass("PlayerGui")
        local confirmed = false
        local addedConnection = nil

        local function tryNow()
            if confirmed
                or not State.Running
                or not ScoopHubRunAlive() then
                return
            end

            if tryConfirmAtlanticHarvestPopup() then
                confirmed = true
                if addedConnection then
                    addedConnection:Disconnect()
                    addedConnection = nil
                end
            end
        end

        -- React as the popup hierarchy is created instead of waiting for the
        -- polling interval. task.defer lets the rest of the Yes/No controls be
        -- parented first, while still running before the next rendered frame in
        -- the normal popup path.
        if playerGui then
            addedConnection = playerGui.DescendantAdded:Connect(function()
                task.defer(tryNow)
            end)
        end

        task.spawn(function()
            local deadline = os.clock() + 2

            while not confirmed
                and State.Running
                and ScoopHubRunAlive()
                and os.clock() < deadline do
                tryNow()
                task.wait(0.03)
            end

            if addedConnection then
                addedConnection:Disconnect()
                addedConnection = nil
            end
        end)
    end

    local function stillExists(data)
        if data.type == "Multi" then
            local fruit = data.object

            return fruit ~= nil
                and fruit.Parent ~= nil
                and fruit:GetAttribute("FruitId") == data.fruitId
        end

        return data.object ~= nil
            and data.object.Parent ~= nil
    end

    local function removeRowInstant(data)
        State.PendingHarvest[data.key] = true

        -- V47: rows are pooled/reused, so remove only the lightweight data
        -- record. The visible row pool is reassigned immediately.
        for index = #State.LatestItems, 1, -1 do
            if State.LatestItems[index].key == data.key then
                table.remove(State.LatestItems, index)
                break
            end
        end

        applyVisibilityAndSummary()
    end

    harvestItem = function(data)
        if not data
            or not isReady(data)
            or State.PendingHarvest[data.key] then
            return
        end

        local prompt =
            data.object
            and data.object.Parent
            and data.object:FindFirstChild(
                "HarvestPrompt",
                true
            )

        -- Snapshot the delivery revision before this manual Garden harvest.
        -- If no new HarvestedFruit reaches inventory after the request, the
        -- Garden tab can explain that the player should return to their garden.
        local deliveryRevisionBefore = GardenHarvestDeliveryRevision
        local fired = false

        -- Arm the confirmer before the game's HarvestPrompt is fired so the
        -- Atlantic Giant Pumpkin popup can be accepted as soon as it appears.
        if data.atlantic then
            armAtlanticHarvestAutoConfirm()
        end

        if data.forever then
            if prompt and fireproximityprompt then
                fired = pcall(function()
                    fireproximityprompt(prompt)
                end)
            end
        else
            fired = pcall(function()
                G.Networking.Garden.CollectFruit:Fire(
                    data.plantId,
                    data.fruitId or ""
                )
            end)

            if not fired
                and prompt
                and fireproximityprompt then
                fired = pcall(function()
                    fireproximityprompt(prompt)
                end)
            end
        end

        if not fired then
            showReturnToGardenMessage()
            return
        end

        removeRowInstant(data)

        -- Separate from the row/object confirmation below: the garden object can
        -- disappear even when the harvested fruit never reaches Backpack because
        -- the player is outside the valid garden zone.
        task.spawn(function()
            local deadline = os.clock() + 1.5

            while State.Running
                and ScoopHubRunAlive()
                and os.clock() < deadline do
                if GardenHarvestDeliveryRevision > deliveryRevisionBefore then
                    return
                end

                task.wait(0.05)
            end

            if State.Running
                and ScoopHubRunAlive()
                and GardenHarvestDeliveryRevision <= deliveryRevisionBefore then
                showReturnToGardenMessage()
            end
        end)

        task.spawn(function()
            task.wait(.35)

            if not State.Running
                or not ScoopHubRunAlive() then
                return
            end

            if not stillExists(data) then
                State.PendingHarvest[data.key] = nil
                return
            end

            task.wait(.35)

            if not State.Running
                or not ScoopHubRunAlive() then
                return
            end

            if stillExists(data) then
                State.PendingHarvest[data.key] = nil
                showReturnToGardenMessage()

                requestRefresh()
            else
                State.PendingHarvest[data.key] = nil
            end
        end)
    end

    -- ==============================================================
    -- SCAN / APPLY / REFRESH
    -- ==============================================================

    local FULL_SCAN_INTERVAL = 3
    local LIGHTWEIGHT_TICK_INTERVAL = 1
    local SCAN_TIME_BUDGET = 0.0025

    local function scanGarden()
        -- GardenSync cache behavior intentionally stays unchanged in V53.
        -- That optimization is kept separate for the next test version.
        resetSyncCache()

        local output = {}
        local plot = getPlot()
        local plants =
            plot
            and plot:FindFirstChild("Plants")

        if not plants then
            setText(HeaderStatus, "NO GARDEN")
            setColor(HeaderStatus, T.Muted)
            return output
        end

        setText(HeaderStatus, "LIVE")
        setColor(HeaderStatus, T.Success)

        local serverNow = WS:GetServerTimeNow()
        local sliceStartedAt = os.clock()

        -- V53: yield according to actual time spent in the current scheduler
        -- slice rather than an arbitrary "every 100 items". Fast devices can
        -- process more per slice; slower devices yield sooner.
        local function yieldIfBudgetSpent()
            if os.clock() - sliceStartedAt >= SCAN_TIME_BUDGET then
                task.wait()
                sliceStartedAt = os.clock()
            end
        end

        for _, plant in ipairs(plants:GetChildren()) do
            local seed = plant:GetAttribute("SeedName")

            if seed then
                local multi = isMulti(seed)
                local plantData = syncedPlant(plant)

                if multi then
                    local fruits = plant:FindFirstChild("Fruits")

                    if fruits then
                        for _, fruit in ipairs(fruits:GetChildren()) do
                            if fruit:GetAttribute("FruitId") ~= nil then
                                local ok, data = pcall(
                                    multiInfo,
                                    plant,
                                    fruit,
                                    plantData,
                                    serverNow
                                )

                                if ok and data then
                                    data._snapshotClock = os.clock()
                                    output[#output + 1] = data
                                end

                                yieldIfBudgetSpent()
                            end
                        end
                    end
                else
                    local ok, data = pcall(
                        singleInfo,
                        plant,
                        plantData
                    )

                    if ok and data then
                        data._snapshotClock = os.clock()
                        output[#output + 1] = data
                    end

                    yieldIfBudgetSpent()
                end
            end
        end

        table.sort(output, function(a, b)
            local aReady = isReady(a)
            local bReady = isReady(b)

            if aReady ~= bReady then
                return aReady
            end

            if not aReady then
                local aTime = getRemaining(a)
                local bTime = getRemaining(b)

                if math.abs(aTime - bTime) > .01 then
                    return aTime < bTime
                end
            end

            return a.value > b.value
        end)

        return output
    end

    local function applyItems(list)
        local activeItems = {}

        for _, data in ipairs(list) do
            if not State.PendingHarvest[data.key] then
                activeItems[#activeItems + 1] = data
            end
        end

        -- V47: hundreds of garden entries remain lightweight Lua records.
        -- applyVisibilityAndSummary() feeds only the viewport-sized RowPool.
        State.LatestItems = activeItems
        applyVisibilityAndSummary()
    end

    local function refresh()
        if State.Refreshing
            or not State.Running
            or not ScoopHubRunAlive()
            or not Garden.Visible then
            return
        end

        State.Refreshing = true

        local ok, err = pcall(function()
            local list = scanGarden()
            applyItems(list)
        end)

        State.Refreshing = false

        if not ok then
            setText(Info, "Refresh error - check console")
            setColor(Info, T.Text)

            warn(
                "[ScoopHub Garden] refresh failed:",
                err
            )
        else
            setColor(Info, T.Muted)
        end
    end

    requestRefresh = function()
        if State.RefreshRequested then
            return
        end

        State.RefreshRequested = true

        task.spawn(function()
            while State.Refreshing
                and State.Running
                and ScoopHubRunAlive() do
                task.wait()
            end

            State.RefreshRequested = false

            if State.Running
                and ScoopHubRunAlive()
                and Garden.Parent
                and Garden.Visible then
                refresh()
            end
        end)
    end

    -- ==============================================================
    -- V54 SORT / ADVANCED FILTER BEHAVIOR
    -- ==============================================================

    local function parseGardenFilterNumber(value)
        local textValue =
            tostring(value or "")
            :lower()
            :gsub("[%s,$]", "")

        if textValue == "" then
            return 0
        end

        local multiplier = 1
        local suffix = textValue:sub(-1)

        if suffix == "k" then
            multiplier = 1e3
            textValue = textValue:sub(1, -2)
        elseif suffix == "m" then
            multiplier = 1e6
            textValue = textValue:sub(1, -2)
        elseif suffix == "b" then
            multiplier = 1e9
            textValue = textValue:sub(1, -2)
        elseif suffix == "t" then
            multiplier = 1e12
            textValue = textValue:sub(1, -2)
        end

        return math.max(
            0,
            (tonumber(textValue) or 0) * multiplier
        )
    end

    local function gardenFiltersActive()
        return not State.FilterMulti
            or not State.FilterSingle
            or (tonumber(State.FilterMinKG) or 0) > 0
            or (tonumber(State.FilterMinValue) or 0) > 0
            or tostring(State.FilterMutation or "") ~= ""
    end

    local function updateGardenAdvancedControls()
        local sortLabels = {
            ["Default"] = "DEFAULT",
            ["Highest Value"] = "VALUE",
            ["Highest KG"] = "KG",
            ["Fastest Ready"] = "READY",
            ["Name A-Z"] = "A-Z",
        }

        setText(
            State.AdvancedUI.SortButton,
            "SORT: " .. (sortLabels[State.SortMode] or "DEFAULT")
        )

        local active = gardenFiltersActive()

        State.AdvancedUI.FilterButton.BackgroundColor3 =
            active and T.RedDark or T.Surface3
        setText(
            State.AdvancedUI.FilterButton,
            active and "FILTERS •" or "FILTERS"
        )

        State.AdvancedUI.MultiToggle.BackgroundColor3 =
            State.FilterMulti and T.RedDark or T.Surface3
        State.AdvancedUI.MultiToggle.TextColor3 =
            State.FilterMulti and T.White or T.Muted
        setText(
            State.AdvancedUI.MultiToggle,
            State.FilterMulti and "MULTI  ON" or "MULTI  OFF"
        )

        State.AdvancedUI.SingleToggle.BackgroundColor3 =
            State.FilterSingle and T.RedDark or T.Surface3
        State.AdvancedUI.SingleToggle.TextColor3 =
            State.FilterSingle and T.White or T.Muted
        setText(
            State.AdvancedUI.SingleToggle,
            State.FilterSingle and "SINGLE  ON" or "SINGLE  OFF"
        )
    end

    local function closeGardenPopups()
        State.AdvancedUI.SortPanel.Visible = false
        State.AdvancedUI.FilterPanel.Visible = false
    end

    local sortOptions = {
        {"Default", "DEFAULT"},
        {"Highest Value", "HIGHEST VALUE"},
        {"Highest KG", "HIGHEST KG"},
        {"Fastest Ready", "FASTEST READY"},
        {"Name A-Z", "NAME A-Z"},
    }

    for index, option in ipairs(sortOptions) do
        local sortMode = option[1]
        local row = C(N("TextButton", {
            Name = "GardenSort" .. sortMode:gsub("%W", ""),
            Position = UDim2.fromOffset(5, 5 + (index - 1) * 28),
            Size = UDim2.new(1, -10, 0, 25),
            BackgroundColor3 = T.Surface2,
            BorderSizePixel = 0,
            Text = option[2],
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 9,
            AutoButtonColor = false,
            ZIndex = 302,
        }, State.AdvancedUI.SortPanel), 5)

        TrackConnection(row.Activated:Connect(function()
            State.SortMode = sortMode
            Scroll.CanvasPosition = Vector2.zero
            closeGardenPopups()
            updateGardenAdvancedControls()
            applyVisibilityAndSummary()
        end))

        TrackConnection(row.MouseEnter:Connect(function()
            tw(row, {BackgroundColor3 = T.RedDark}, .10)
        end))

        TrackConnection(row.MouseLeave:Connect(function()
            tw(
                row,
                {
                    BackgroundColor3 =
                        State.SortMode == sortMode
                        and T.RedDark
                        or T.Surface2
                },
                .10
            )
        end))
    end

    TrackConnection(
        State.AdvancedUI.SortButton.Activated:Connect(function()
            local open = not State.AdvancedUI.SortPanel.Visible
            State.AdvancedUI.FilterPanel.Visible = false
            State.AdvancedUI.SortPanel.Visible = open
        end)
    )

    TrackConnection(
        State.AdvancedUI.FilterButton.Activated:Connect(function()
            local open = not State.AdvancedUI.FilterPanel.Visible
            State.AdvancedUI.SortPanel.Visible = false
            State.AdvancedUI.FilterPanel.Visible = open
        end)
    )

    TrackConnection(
        State.AdvancedUI.MultiToggle.Activated:Connect(function()
            if State.FilterMulti and not State.FilterSingle then
                return
            end

            State.FilterMulti = not State.FilterMulti
            Scroll.CanvasPosition = Vector2.zero
            updateGardenAdvancedControls()
            applyVisibilityAndSummary()
        end)
    )

    TrackConnection(
        State.AdvancedUI.SingleToggle.Activated:Connect(function()
            if State.FilterSingle and not State.FilterMulti then
                return
            end

            State.FilterSingle = not State.FilterSingle
            Scroll.CanvasPosition = Vector2.zero
            updateGardenAdvancedControls()
            applyVisibilityAndSummary()
        end)
    )

    local function applyGardenNumericFilters()
        State.FilterMinKG =
            parseGardenFilterNumber(State.AdvancedUI.MinKGBox.Text)
        State.FilterMinValue =
            parseGardenFilterNumber(State.AdvancedUI.MinValueBox.Text)

        Scroll.CanvasPosition = Vector2.zero
        updateGardenAdvancedControls()
        applyVisibilityAndSummary()
    end

    TrackConnection(
        State.AdvancedUI.MinKGBox.FocusLost:Connect(
            applyGardenNumericFilters
        )
    )

    TrackConnection(
        State.AdvancedUI.MinValueBox.FocusLost:Connect(
            applyGardenNumericFilters
        )
    )

    TrackConnection(
        State.AdvancedUI.MutationBox
            :GetPropertyChangedSignal("Text")
            :Connect(function()
                State.FilterMutation =
                    State.AdvancedUI.MutationBox.Text
                Scroll.CanvasPosition = Vector2.zero
                updateGardenAdvancedControls()
                applyVisibilityAndSummary()
            end)
    )

    TrackConnection(
        State.AdvancedUI.ResetFilters.Activated:Connect(function()
            State.FilterMulti = true
            State.FilterSingle = true
            State.FilterMinKG = 0
            State.FilterMinValue = 0
            State.FilterMutation = ""

            State.AdvancedUI.MinKGBox.Text = ""
            State.AdvancedUI.MinValueBox.Text = ""
            State.AdvancedUI.MutationBox.Text = ""

            Scroll.CanvasPosition = Vector2.zero
            updateGardenAdvancedControls()
            applyVisibilityAndSummary()
        end)
    )

    updateGardenAdvancedControls()

    -- ==============================================================
    -- FILTER / SEARCH EVENTS
    -- ==============================================================

    local function setTab(tabName)
        State.CurrentTab = tabName
        Scroll.CanvasPosition = Vector2.zero
        updateGardenTabs()
        applyVisibilityAndSummary()
        renderVirtualRows()
    end

    TrackConnection(
        OverallTab.Activated:Connect(function()
            setTab("Overall")
        end)
    )

    TrackConnection(
        ReadyTab.Activated:Connect(function()
            setTab("Ready")
        end)
    )

    TrackConnection(
        GrowingTab.Activated:Connect(function()
            setTab("Growing")
        end)
    )

    TrackConnection(
        Search:GetPropertyChangedSignal("Text"):Connect(function()
            State.SearchText = Search.Text
            applyVisibilityAndSummary()
        end)
    )

    TrackConnection(
        Garden:GetPropertyChangedSignal("Visible"):Connect(function()
            if Garden.Visible then
                requestRefresh()
            else
                State.AdvancedUI.SortPanel.Visible = false
                State.AdvancedUI.FilterPanel.Visible = false
            end
        end)
    )

    updateGardenTabs()

    -- ==============================================================
    -- V53 LOW-END UPDATE SCHEDULER
    --
    -- FULL SCAN:
    --   about every 3 seconds while Garden is visible.
    --
    -- LIGHTWEIGHT TICK:
    --   every 1 second, updating only the pooled visible rows
    --   (normally 8-18 GUI cards). No Workspace/GardenSync scan.
    --
    -- HIDDEN:
    --   Garden stays effectively asleep.
    -- ==============================================================

    task.spawn(function()
        while State.Running
            and ScoopHubRunAlive()
            and Garden.Parent do

            if Garden.Visible then
                local started = os.clock()

                refresh()

                local elapsed = os.clock() - started
                task.wait(
                    math.max(
                        FULL_SCAN_INTERVAL - elapsed,
                        .10
                    )
                )
            else
                task.wait(1)
            end
        end
    end)

    task.spawn(function()
        while State.Running
            and ScoopHubRunAlive()
            and Garden.Parent do

            if Garden.Visible then
                -- Virtualization makes this cheap: only currently pooled rows
                -- are touched, not all 700+ garden records.
                renderVirtualRows()
            end

            task.wait(LIGHTWEIGHT_TICK_INTERVAL)
        end
    end)
end)()


    return true
end

Module.Version = "ScoopHub-V2.2-Garden-Remote-1"
return Module
