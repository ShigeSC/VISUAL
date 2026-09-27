local RemotePages = {
    Version = "ScoopHub-V2.2-RemotePages-1",
}

function RemotePages.Init(Bridge)
    if type(Bridge) ~= "table" then
        error("[ScoopHub Pages] Bridge table is required.")
    end

    -- Shared ScoopHub shell/page objects.
    local Pages = Bridge.Pages
    local LP = Bridge.LP or game:GetService("Players").LocalPlayer
    local Shop = Bridge.Shop or (Pages and Pages.Shop)
    local Inventory = Bridge.Inventory or (Pages and Pages.Inventory)
    local SG = Bridge.SG
    local Scale = Bridge.Scale
    local UIS = Bridge.UIS or game:GetService("UserInputService")

    -- Shared ScoopHub theme / GUI helpers. Passing the functions themselves
    -- preserves the main GUI's theme and lets this remote file remain small.
    local T = Bridge.T
    local N = Bridge.N
    local C = Bridge.C
    local S = Bridge.S
    local tw = Bridge.Tween
    local label = Bridge.Label
    local gradient = Bridge.Gradient
    local panel = Bridge.Panel

    -- Shared runtime lifecycle helpers.
    local TrackConnection = Bridge.TrackConnection
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local ScoopHubRunAlive = Bridge.RunAlive
    local AccentSelectedBg = Bridge.AccentSelectedBg

    -- Inventory has two old notification calls. The original source could
    -- resolve these only when a compatible notifier was available, so keep a
    -- safe bridge instead of allowing a nil-call to stop Inventory.
    local Notify = Bridge.Notify or function(title, content)
        warn("[ScoopHub] " .. tostring(title or "Notice") .. ": " .. tostring(content or ""))
    end

    if type(Pages) ~= "table" then
        error("[ScoopHub Pages] Pages bridge is missing.")
    end
    if not Shop or not Inventory then
        error("[ScoopHub Pages] Shop/Inventory page bridge is missing.")
    end
    if type(N) ~= "function"
        or type(C) ~= "function"
        or type(S) ~= "function"
        or type(label) ~= "function"
        or type(TrackConnection) ~= "function"
        or type(RegisterScoopHubCleanup) ~= "function"
        or type(ScoopHubRunAlive) ~= "function" then
        error("[ScoopHub Pages] Main GUI/runtime bridge is incomplete.")
    end

;
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

--==================================================
-- SHOP PAGE
-- World-specific Seeds / Gear / Crates + Garden Valley Auction.
-- V13: Restock detection uses a cached Timer.Text event + 1s repair fallback.
-- Live stock / restock logic is based on the working reference supplied by
-- the user, adapted to this V2.2 custom GUI instead of MAGANDAU.
--==================================================
local function __ScoopHubInitShop()
    local Page = Shop
    local PlayersService = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local SoundService = game:GetService("SoundService")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = PlayersService.LocalPlayer

    local WorldRoot = _G.ScoopHubWorldData
    local CurrentWorld = WorldRoot and WorldRoot.Current or {
        Key = "Unsupported", Name = "Unsupported World", Supported = false,
        HasAuction = false, ReturnToGardenAfterSeedBuy = false,
        Seeds = {}, Gears = {}, Crates = {}, AuctionEggs = {}, AuctionSeedPacks = {},
    }

    local function cloneList(source)
        local output = {}
        for _, value in ipairs(source or {}) do
            output[#output + 1] = value
        end
        return output
    end

    local function filterAllowed(values, allowed)
        if WorldRoot and type(WorldRoot.FilterAllowed) == "function" then
            local ok, result = pcall(WorldRoot.FilterAllowed, values or {}, allowed or {})
            if ok and type(result) == "table" then return result end
        end

        local lookup, output = {}, {}
        for _, value in ipairs(allowed or {}) do lookup[tostring(value)] = true end
        for _, value in ipairs(values or {}) do
            value = tostring(value)
            if lookup[value] then output[#output + 1] = value end
        end
        return output
    end

    local AllSeeds = cloneList(CurrentWorld.Seeds)
    local AllGears = cloneList(CurrentWorld.Gears)
    local AllCrates = cloneList(CurrentWorld.Crates)
    local StaticAuctionEggs = cloneList(CurrentWorld.AuctionEggs)
    local StaticAuctionSeedPacks = cloneList(CurrentWorld.AuctionSeedPacks)

    -- Auction reuses the exact same CurrentWorld object already resolved for Shop.
    -- Keep the shared world catalog untouched: Fall Auction support is local to
    -- this Auction implementation only.
    local IsGardenAuctionWorld = CurrentWorld.Key == "GardenValley"
    local IsFallAuctionWorld = CurrentWorld.Key == "FallHarvestWorld"
    local AuctionWorldEnabled = CurrentWorld.Supported == true
        and (IsGardenAuctionWorld or IsFallAuctionWorld)
    local AuctionCurrencyName = IsFallAuctionWorld and "Leaves" or "Sheckles"

    -- Auction options start from this world's existing catalog, then learn
    -- auction-only entries from CURRENT-WORLD live lot tables. The live scan is
    -- world-locked by lotId, so stale Garden lots can never leak into Fall and
    -- stale Fall lots can never leak into Garden after a teleport/re-execution.
    local AuctionSeeds = cloneList(AllSeeds)
    local AuctionGears = cloneList(AllGears)
    local AuctionCrates = cloneList(AllCrates)
    local AuctionEggs = cloneList(StaticAuctionEggs)
    local AuctionSeedPacks = cloneList(StaticAuctionSeedPacks)

    local function auctionNameKey(value)
        return string.lower(tostring(value or "")):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function auctionCategoryKey(value)
        return string.lower(tostring(value or "")):gsub("[^%w]", "")
    end

    local function isCurrentWorldAuctionLot(lot)
        if type(lot) ~= "table" then return false end
        local lotId = tostring(lot.lotId or lot.LotId or lot.id or lot.Id or "")
        if IsFallAuctionWorld then
            return string.match(lotId, "^auction:FallHarvest:") ~= nil
        end
        if IsGardenAuctionWorld then
            return string.match(lotId, "^auction:%d+:") ~= nil
        end
        return false
    end

    local function isRobuxOnlyAuctionLot(lot)
        local dualCurrency = lot.dualCurrency
        if dualCurrency == nil then dualCurrency = lot.DualCurrency end
        if dualCurrency == true then
            return false
        end

        local currency = lot.currency or lot.Currency
            or lot.currencyType or lot.CurrencyType
            or lot.paymentType or lot.PaymentType
            or lot.purchaseType or lot.PurchaseType
        if currency ~= nil then
            local text = string.lower(tostring(currency))
            if string.find(text, "robux", 1, true) then
                return true
            end
        end

        local robuxPrice = tonumber(lot.robuxPrice or lot.RobuxPrice)
        return robuxPrice ~= nil and robuxPrice > 0
    end

    -- getgc(true) is expensive in this game (the client can have well over a
    -- million GC objects). Never run that scan every Auction worker tick.
    -- Keep direct references to the current rotation's lot tables and only do a
    -- full refresh when the rotation changes, or when no lots were available.
    local AuctionLotCache = {}
    local AuctionLotCacheRefreshAt = nil
    local AuctionLotLastFullScanClock = -math.huge
    local AUCTION_EMPTY_RESCAN_SECONDS = 5
    local AUCTION_ROTATION_FALLBACK_SECONDS = 900

    local function scanCurrentWorldAuctionLots()
        if type(getgc) ~= "function" then
            return AuctionLotCache
        end

        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then
            return AuctionLotCache
        end

        local candidates = {}
        local latestRolledAt = nil

        for _, value in ipairs(objects) do
            if type(value) == "table"
                and rawget(value, "lotId")
                and rawget(value, "displayName")
                and isCurrentWorldAuctionLot(value) then

                local rolledAt = tonumber(value.rolledAt or value.RolledAt) or 0
                candidates[#candidates + 1] = value
                if latestRolledAt == nil or rolledAt > latestRolledAt then
                    latestRolledAt = rolledAt
                end
            end
        end

        -- getgc can temporarily retain tables from the previous rotation. Keep
        -- only the newest rotation so stale lots cannot be processed.
        local lots = {}
        local refreshAt = nil
        for _, lot in ipairs(candidates) do
            local rolledAt = tonumber(lot.rolledAt or lot.RolledAt) or 0
            if latestRolledAt == nil or rolledAt == latestRolledAt then
                lots[#lots + 1] = lot

                -- Normal Leaves/Sheckles lots expose stockQuantity. Their expiry
                -- is the cleanest signal for when the next Auction rotation needs
                -- one new full scan.
                local stockQuantity = tonumber(lot.stockQuantity or lot.StockQuantity)
                local expiresAt = tonumber(lot.expiresAt or lot.ExpiresAt)
                if stockQuantity ~= nil and expiresAt ~= nil
                    and (refreshAt == nil or expiresAt < refreshAt) then
                    refreshAt = expiresAt
                end
            end
        end

        AuctionLotLastFullScanClock = os.clock()

        if #lots > 0 then
            AuctionLotCache = lots
            AuctionLotCacheRefreshAt = refreshAt
                or ((latestRolledAt or workspace:GetServerTimeNow())
                    + AUCTION_ROTATION_FALLBACK_SECONDS)
        end

        return AuctionLotCache
    end

    local function getCurrentWorldAuctionLots(forceRefresh)
        local now = workspace:GetServerTimeNow()
        local sinceFullScan = os.clock() - AuctionLotLastFullScanClock
        local needsRefresh = forceRefresh == true

        if #AuctionLotCache == 0 then
            -- If the Auction snapshot was not ready yet, retry occasionally
            -- instead of freezing the client with a getgc scan every 0.4s.
            needsRefresh = needsRefresh
                or sinceFullScan >= AUCTION_EMPTY_RESCAN_SECONDS
        elseif AuctionLotCacheRefreshAt ~= nil and now >= AuctionLotCacheRefreshAt then
            -- A new rotation should now exist. Limit retries in case the server
            -- publishes its new snapshot a few seconds late.
            needsRefresh = needsRefresh
                or sinceFullScan >= AUCTION_EMPTY_RESCAN_SECONDS
        end

        if needsRefresh then
            return scanCurrentWorldAuctionLots()
        end

        return AuctionLotCache
    end

    local function listContains(values, wanted)
        local wantedKey = auctionNameKey(wanted)
        for _, value in ipairs(values or {}) do
            if auctionNameKey(value) == wantedKey then
                return true
            end
        end
        return false
    end

    local function addAuctionOption(values, seen, name)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local key = auctionNameKey(name)
        if key == "" or seen[key] then return false end
        seen[key] = true
        values[#values + 1] = name
        return true
    end

    local AuctionOptionSeen = { Seeds = {}, Gears = {}, Crates = {}, Eggs = {}, SeedPacks = {} }
    for _, value in ipairs(AuctionSeeds) do AuctionOptionSeen.Seeds[auctionNameKey(value)] = true end
    for _, value in ipairs(AuctionGears) do AuctionOptionSeen.Gears[auctionNameKey(value)] = true end
    for _, value in ipairs(AuctionCrates) do AuctionOptionSeen.Crates[auctionNameKey(value)] = true end
    for _, value in ipairs(AuctionEggs) do AuctionOptionSeen.Eggs[auctionNameKey(value)] = true end
    for _, value in ipairs(AuctionSeedPacks) do AuctionOptionSeen.SeedPacks[auctionNameKey(value)] = true end

    local function mergeLiveAuctionOptions(lots)
        local changed = false

        for _, lot in ipairs(lots or {}) do
            -- Discover every item from the current world's Auction, including a
            -- Robux copy. Purchase filtering stays separate below, so a target can
            -- already be selected before its Leaves/Sheckles listing appears.
            if isCurrentWorldAuctionLot(lot) then
                local name = lot.displayName or lot.DisplayName or lot.item or lot.Item or lot.name or lot.Name
                local category = auctionCategoryKey(lot.category or lot.Category)
                local bucket, seen

                if category == "seeds" or category == "seed" then
                    bucket, seen = AuctionSeeds, AuctionOptionSeen.Seeds
                elseif category == "eggs" or category == "egg" then
                    bucket, seen = AuctionEggs, AuctionOptionSeen.Eggs
                elseif category == "seedpacks" or category == "seedpack" then
                    bucket, seen = AuctionSeedPacks, AuctionOptionSeen.SeedPacks
                elseif category == "crates" or category == "crate" then
                    bucket, seen = AuctionCrates, AuctionOptionSeen.Crates
                elseif category == "gears" or category == "gear"
                    or category == "sprinklers" or category == "sprinkler"
                    or category == "wateringcans" or category == "wateringcan"
                    or category == "mushrooms" or category == "mushroom"
                    or category == "tools" or category == "tool" then
                    bucket, seen = AuctionGears, AuctionOptionSeen.Gears
                elseif listContains(AllSeeds, name) then
                    bucket, seen = AuctionSeeds, AuctionOptionSeen.Seeds
                elseif listContains(AllGears, name) then
                    bucket, seen = AuctionGears, AuctionOptionSeen.Gears
                elseif listContains(AllCrates, name) then
                    bucket, seen = AuctionCrates, AuctionOptionSeen.Crates
                elseif listContains(StaticAuctionEggs, name) then
                    bucket, seen = AuctionEggs, AuctionOptionSeen.Eggs
                elseif listContains(StaticAuctionSeedPacks, name) then
                    bucket, seen = AuctionSeedPacks, AuctionOptionSeen.SeedPacks
                end

                if bucket and addAuctionOption(bucket, seen, name) then
                    changed = true
                end
            end
        end

        if changed then
            table.sort(AuctionSeeds, function(a, b) return string.lower(a) < string.lower(b) end)
            table.sort(AuctionGears, function(a, b) return string.lower(a) < string.lower(b) end)
            table.sort(AuctionCrates, function(a, b) return string.lower(a) < string.lower(b) end)
            table.sort(AuctionEggs, function(a, b) return string.lower(a) < string.lower(b) end)
            table.sort(AuctionSeedPacks, function(a, b) return string.lower(a) < string.lower(b) end)
        end

        return changed
    end

    if AuctionWorldEnabled then
        mergeLiveAuctionOptions(getCurrentWorldAuctionLots(true))
    end

    local previousState = _G.ScoopHubShopState
    local State
    if type(previousState) == "table" and previousState.WorldKey == CurrentWorld.Key then
        State = previousState
    else
        State = {
            WorldKey = CurrentWorld.Key,
            SelectedSeeds = {}, SelectedGears = {}, SelectedCrates = {},
            BuySelectedSeeds = false, BuyAllSeeds = false,
            BuySelectedGears = false, BuyAllGears = false,
            BuySelectedCrates = false, BuyAllCrates = false,
            AuctionSeeds = {}, AuctionGears = {}, AuctionCrates = {},
            AuctionEggs = {}, AuctionSeedPacks = {}, AuctionMaxPrice = 0,
            AuctionEnabled = false,
        }
    end
    _G.ScoopHubShopState = State

    State.SelectedSeeds = filterAllowed(State.SelectedSeeds, AllSeeds)
    State.SelectedGears = filterAllowed(State.SelectedGears, AllGears)
    State.SelectedCrates = filterAllowed(State.SelectedCrates, AllCrates)
    State.AuctionSeeds = filterAllowed(State.AuctionSeeds, AuctionSeeds)
    State.AuctionGears = filterAllowed(State.AuctionGears, AuctionGears)
    State.AuctionCrates = filterAllowed(State.AuctionCrates, AuctionCrates)
    State.AuctionEggs = filterAllowed(State.AuctionEggs, AuctionEggs)
    State.AuctionSeedPacks = filterAllowed(State.AuctionSeedPacks, AuctionSeedPacks)
    State.AuctionMaxPrice = math.max(0, tonumber(State.AuctionMaxPrice) or 0)
    State.AuctionEnabled = AuctionWorldEnabled and State.AuctionEnabled == true or false

    Page.ClipsDescendants = false

    label(
        Page,
        "SHOP",
        UDim2.new(0, 8, 0, 1),
        UDim2.new(.42, 0, 0, 20),
        11,
        T.Text,
        T.Font
    )

    local WorldLabel = label(
        Page,
        CurrentWorld.Name,
        UDim2.new(.42, 0, 0, 1),
        UDim2.new(.58, -8, 0, 20),
        9,
        CurrentWorld.Supported and T.Muted or T.Red,
        T.Font,
        Enum.TextXAlignment.Right
    )

    local ShopScroll = N("ScrollingFrame", {
        Name = "ShopScroll",
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, -8, 1, -24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 462),
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = T.Red,
    }, Page)

    local StatusLabel = label(
        Page,
        CurrentWorld.Supported and "● READY" or "● UNSUPPORTED",
        UDim2.new(.48, 0, 0, 1),
        UDim2.new(.52, -8, 0, 20),
        9,
        CurrentWorld.Supported and T.Success or T.Red,
        T.Font,
        Enum.TextXAlignment.Right
    )
    WorldLabel.Visible = false -- status occupies the compact header; world is shown in cards/status text.

    local lastStatusAt = 0
    local function setStatus(message, good)
        if not StatusLabel or not StatusLabel.Parent then return end
        StatusLabel.Text = tostring(message or "")
        if good == true then
            StatusLabel.TextColor3 = T.Success
        elseif good == false then
            StatusLabel.TextColor3 = T.Red
        else
            StatusLabel.TextColor3 = T.Muted
        end
        lastStatusAt = os.clock()
    end

    local function formatSelection(items, emptyText)
        if type(items) ~= "table" or #items == 0 then
            return emptyText or "Select options..."
        end
        if #items == 1 then return items[1] end
        if #items == 2 then return items[1] .. ", " .. items[2] end
        return items[1] .. ", " .. items[2] .. " +" .. tostring(#items - 2)
    end

    local function decorateShopCard(card, badgeText, badgeColor)
        N("Frame", {
            BackgroundColor3 = T.Line,
            BackgroundTransparency = 0.55,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 10, 0, 21),
            Size = UDim2.new(1, -20, 0, 1),
        }, card)

        if badgeText and badgeText ~= "" then
            local badge = C(N("Frame", {
                BackgroundColor3 = badgeColor or T.RedDark,
                BorderSizePixel = 0,
                Position = UDim2.new(1, -88, 0, 6),
                Size = UDim2.fromOffset(78, 15),
            }, card), 999)

            S(badge, badgeColor or T.Line, 0.45, 1)

            label(
                badge,
                tostring(badgeText),
                UDim2.new(0, 0, 0, 0),
                UDim2.new(1, 0, 1, 0),
                8,
                T.White,
                T.Font,
                Enum.TextXAlignment.Center
            )
        end
    end

    local function addShopInfoLines(parent, lines, startY)
        local y = startY or 0
        for _, entry in ipairs(lines or {}) do
            local textValue = entry
            local textColor = T.Muted
            local fontValue = T.Body

            if type(entry) == "table" then
                textValue = entry.Text or ""
                textColor = entry.Color or textColor
                fontValue = entry.Font or fontValue
            end

            label(
                parent,
                tostring(textValue),
                UDim2.new(0, 10, 0, y),
                UDim2.new(1, -20, 0, 16),
                9,
                textColor,
                fontValue
            )
            y = y + 15
        end

        return y
    end

    local function makeSelectorRow(parent, titleText, subtitleText, y)
        label(parent, titleText, UDim2.new(0, 10, 0, y + 1), UDim2.new(.46, -14, 0, 16), 11, T.White, T.Font)
        label(parent, subtitleText, UDim2.new(0, 10, 0, y + 17), UDim2.new(.46, -14, 0, 14), 9, T.Muted, T.Body)

        local selector = C(N("TextButton", {
            Text = "Select options...",
            Font = T.Font,
            TextSize = 11,
            TextColor3 = T.White,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            BackgroundColor3 = T.Input,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Position = UDim2.new(.50, 0, 0, y + 2),
            -- Match the toggle row's right edge (toggle ends at -11px).
            -- This applies to Seeds, Gear, Crates, and every Auction filter
            -- because all Shop filters are built through makeSelectorRow().
            Size = UDim2.new(.50, -11, 0, 31),
        }, parent), 5)
        N("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, selector)
        S(selector, T.Stroke, .75, 1)

        return selector
    end

    local function makeToggleRow(parent, titleText, subtitleText, y, initial, callback)
        label(parent, titleText, UDim2.new(0, 10, 0, y + 1), UDim2.new(1, -67, 0, 16), 11, T.White, T.Font)
        label(parent, subtitleText, UDim2.new(0, 10, 0, y + 17), UDim2.new(1, -67, 0, 14), 9, T.Muted, T.Body)

        local state = initial == true
        local toggle = C(N("TextButton", {
            Text = "",
            BackgroundColor3 = state and T.Success or T.RedDark,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Position = UDim2.new(1, -55, 0, y + 6),
            Size = UDim2.fromOffset(44, 22),
        }, parent), 10)

        local knob = C(N("Frame", {
            BackgroundColor3 = T.White,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, .5),
            Position = state and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0),
            Size = UDim2.fromOffset(16, 16),
        }, toggle), 8)

        local api = {}
        function api:Set(value, fire)
            state = value == true
            toggle.BackgroundColor3 = state and T.Success or T.RedDark
            tw(knob, { Position = state and UDim2.new(1, -18, .5, 0) or UDim2.new(0, 3, .5, 0) }, .12)
            if fire ~= false and callback then callback(state) end
        end
        function api:Get() return state end
        toggle.Activated:Connect(function() api:Set(not state, true) end)
        return api
    end

    local function makeInputRow(parent, titleText, subtitleText, y, initial, callback)
        label(parent, titleText, UDim2.new(0, 10, 0, y + 1), UDim2.new(.46, -14, 0, 16), 11, T.White, T.Font)
        label(parent, subtitleText, UDim2.new(0, 10, 0, y + 17), UDim2.new(.46, -14, 0, 14), 9, T.Muted, T.Body)
        local box = C(N("TextBox", {
            Text = tostring(initial or ""),
            PlaceholderText = "Input value",
            ClearTextOnFocus = false,
            Font = T.Font,
            TextSize = 11,
            TextColor3 = T.White,
            PlaceholderColor3 = T.Muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = T.Input,
            BorderSizePixel = 0,
            Position = UDim2.new(.50, 0, 0, y + 2),
            Size = UDim2.new(.46, -10, 0, 31),
        }, parent), 5)
        N("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
        S(box, T.Stroke, .75, 1)
        box.FocusLost:Connect(function()
            if callback then callback(box.Text, box) end
        end)
        return box
    end

    -- Compact Shop multi-select dropdown.
    -- This reuses the same smooth search/filter style as the Automation tab:
    -- inline dropdown under the field, search, SELECT ALL, CLEAR ALL,
    -- checkmarks, and proper follow/close behavior while the main GUI moves.
    local ActiveCompactShopDropdown = nil
    local ActiveCompactShopChevron = nil

    local function setupCompactShopMultiPicker(selector, options, getValues, setValues, config)
        config = config or {}
        options = options or {}

        local emptyText = config.EmptyText or "Select..."
        local searchPlaceholder = config.SearchPlaceholder or "Search..."
        local singleSelect = config.SingleSelect == true

        -- V42: every Shop dropdown chevron animates, including Auction.
        -- This is visual-only; Auction still keeps its legacy row rebuild path
        -- because ReuseRows remains false for Auction selectors.
        local animateChevron = true

        selector.Text = ""
        selector.ClipsDescendants = true
        selector.AutoButtonColor = false
        -- IMPORTANT: keep the Shop row's original field width. The previous
        -- version forced this to full-card width, so the button was clipped by
        -- the card while the floating dropdown used the larger hidden width.
        -- That made the dropdown overlap the Auction column/borders.
        if config.PreserveSize ~= true then
            selector.Size = UDim2.new(1, -20, 0, 27)
        end

        local oldPadding = selector:FindFirstChildOfClass("UIPadding")
        if oldPadding then
            oldPadding:Destroy()
        end

        local oldText = selector:FindFirstChild("CompactSelectorText")
        if oldText then oldText:Destroy() end
        local oldChevron = selector:FindFirstChild("CompactSelectorChevron")
        if oldChevron then oldChevron:Destroy() end

        -- Remove legacy text-glyph arrows from older Shop selector builds.
        -- Some fonts/executors render those Unicode chevrons as a small box.
        for _, child in ipairs(selector:GetChildren()) do
            if child:IsA("TextLabel") and child.Name ~= "CompactSelectorText" then
                child:Destroy()
            end
        end

        local selectorText = N("TextLabel", {
            Name = "CompactSelectorText",
            Text = emptyText,
            Font = T.Body,
            TextSize = 12,
            TextColor3 = T.White,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 8, 0, 0),
            Size = UDim2.new(1, -28, 1, 0),
            ZIndex = 6,
        }, selector)

        -- Draw the dropdown arrow with two Frames instead of a Unicode glyph.
        -- This prevents the "square/box" fallback icon shown by some fonts.
        local chevron = N("Frame", {
            Name = "CompactSelectorChevron",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(1, -20, 0.5, -5),
            Size = UDim2.fromOffset(14, 10),
            Rotation = 0,
            ZIndex = 6,
        }, selector)

        local function setSelectorChevron(open, instant)
            -- All Shop selectors now animate, including Auction.
            if not animateChevron then
                return
            end

            local targetRotation = open and 180 or 0

            if instant then
                chevron.Rotation = targetRotation
            else
                -- Same 0.14s V <-> ^ tween as Automation.
                tw(chevron, {Rotation = targetRotation}, .14)
            end
        end

        N("Frame", {
            Name = "ChevronLeft",
            BackgroundColor3 = T.Muted,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, -2, 0.5, 0),
            Size = UDim2.fromOffset(7, 2),
            Rotation = 45,
            ZIndex = 7,
        }, chevron)

        N("Frame", {
            Name = "ChevronRight",
            BackgroundColor3 = T.Muted,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 2, 0.5, 0),
            Size = UDim2.fromOffset(7, 2),
            Rotation = -45,
            ZIndex = 7,
        }, chevron)

        local dropdown = C(N("Frame", {
            Name = "CompactShopDropdown",
            Visible = false,
            BackgroundColor3 = T.Surface2,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(230, 240),
            ZIndex = 150,
        }, Page), 6)
        S(dropdown, T.Red, 0, 1.5)

        local searchBox = C(N("TextBox", {
            Name = "CompactShopSearch",
            Text = "",
            PlaceholderText = searchPlaceholder,
            Font = T.Body,
            TextSize = 13,
            TextColor3 = T.White,
            PlaceholderColor3 = T.Muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Position = UDim2.new(0, 4, 0, 4),
            Size = UDim2.new(1, -8, 0, 26),
            ZIndex = 151,
        }, dropdown), 5)
        N("UIPadding", { PaddingLeft = UDim.new(0, 8) }, searchBox)

        local actionRow = N("Frame", {
            Name = "CompactShopActions",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 4, 0, 34),
            Size = UDim2.new(1, -8, 0, 26),
            Visible = not singleSelect,
            ZIndex = 151,
        }, dropdown)

        local selectAll = C(N("TextButton", {
            Name = "SelectAll",
            Text = "SELECT ALL",
            Font = T.Font,
            TextSize = 12,
            TextColor3 = T.White,
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0.5, -2, 1, 0),
            ZIndex = 152,
        }, actionRow), 4)

        local clearAll = C(N("TextButton", {
            Name = "ClearAll",
            Text = "CLEAR ALL",
            Font = T.Font,
            TextSize = 12,
            TextColor3 = T.White,
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Position = UDim2.new(0.5, 2, 0, 0),
            Size = UDim2.new(0.5, -2, 1, 0),
            ZIndex = 152,
        }, actionRow), 4)

        local itemScroll = N("ScrollingFrame", {
            Name = "CompactShopScroll",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 4, 0, singleSelect and 34 or 64),
            Size = UDim2.new(1, -8, 1, singleSelect and -38 or -68),
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.Red,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 151,
        }, dropdown)
        N("UIListLayout", {
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, itemScroll)

        local maxVisibleRows = 6
        local rowHeight = 34
        local dropdownHeaderHeight = singleSelect and 34 or 64
        local currentWidth = 230
        local desiredDropdownHeight = 240
        local updateDropdownPosition

        -- V22 SHOP GUI PERFORMANCE:
        -- Regular Seeds/Gear/Crates selectors reuse option rows instead of
        -- destroying and recreating them after every search/selection change.
        -- Auction explicitly keeps the legacy rebuild path.
        local rowReuse = config.ReuseRows == true and {
            Rows = {},
            Empty = nil,
        } or nil

        -- V40: regular Shop dropdowns are the row-reuse selectors.
        -- Use rowReuse directly so Seeds/Gear/Crates always animate exactly
        -- like Automation; Auction remains on the legacy static path.
        local function currentValues()
            local ok, values = pcall(getValues)
            if ok and type(values) == "table" then
                return values
            end
            return {}
        end

        local function updateSelector()
            local values = filterAllowed(currentValues(), options)
            selectorText.Text = #values > 0 and formatSelection(values, emptyText) or emptyText
        end

        local function selectedLookup()
            local set = {}
            for _, value in ipairs(currentValues()) do
                set[value] = true
            end
            return set
        end

        local function applySelectedSet(set)
            local values = {}
            for _, option in ipairs(options) do
                if set[option] then
                    table.insert(values, option)
                end
            end
            values = filterAllowed(values, options)
            setValues(values)
            updateSelector()
            if refreshSummary then
                refreshSummary()
            end
        end

        local function setSelected(value, enabled)
            local set = selectedLookup()
            if enabled then
                set[value] = true
            else
                set[value] = nil
            end
            applySelectedSet(set)
        end

        local function resizeDropdown(matchCount)
            local visibleRows = math.clamp(matchCount, 1, maxVisibleRows)
            desiredDropdownHeight = dropdownHeaderHeight + (visibleRows * (rowHeight + 2)) + 4

            if dropdown.Visible and updateDropdownPosition then
                updateDropdownPosition()
            else
                dropdown.Size = UDim2.new(0, currentWidth, 0, desiredDropdownHeight)
            end
        end

        updateDropdownPosition = function()
            local ok = pcall(function()
                local scaleValue = math.max(tonumber(Scale.Scale) or 1, 0.01)
                local basePos = Page.AbsolutePosition
                local baseSize = Page.AbsoluteSize
                local buttonPos = selector.AbsolutePosition
                local buttonSize = selector.AbsoluteSize
                local card = selector.Parent
                local cardPos = card and card.AbsolutePosition or buttonPos
                local cardSize = card and card.AbsoluteSize or buttonSize

                local pageWidth = baseSize.X / scaleValue
                local pageHeight = baseSize.Y / scaleValue
                local buttonX = (buttonPos.X - basePos.X) / scaleValue
                local buttonTop = (buttonPos.Y - basePos.Y) / scaleValue
                local buttonHeight = buttonSize.Y / scaleValue
                local buttonBottom = buttonTop + buttonHeight
                local cardX = (cardPos.X - basePos.X) / scaleValue
                local cardWidth = cardSize.X / scaleValue
                local margin = 4

                -- Make the popup comfortable like Automation: use almost the
                -- whole card width, not the tiny inline selector width.
                -- This keeps SELECT ALL / CLEAR ALL readable without crossing
                -- into the neighboring Shop/Auction card.
                currentWidth = math.max(buttonSize.X / scaleValue, cardWidth - 20)
                currentWidth = math.min(currentWidth, pageWidth - (margin * 2))

                local desiredX = cardX + 10
                local x = math.clamp(
                    desiredX,
                    margin,
                    math.max(margin, pageWidth - currentWidth - margin)
                )

                local availableBelow = math.max(0, pageHeight - buttonBottom - margin)
                local availableAbove = math.max(0, buttonTop - margin)

                local openAbove = desiredDropdownHeight > availableBelow
                    and availableAbove > availableBelow

                local availableHeight = openAbove and availableAbove or availableBelow
                local actualHeight = math.min(desiredDropdownHeight, availableHeight)

                if actualHeight < 100 then
                    if availableAbove > availableBelow then
                        openAbove = true
                        availableHeight = availableAbove
                    else
                        openAbove = false
                        availableHeight = availableBelow
                    end
                    actualHeight = math.min(desiredDropdownHeight, availableHeight)
                end

                actualHeight = math.max(0, actualHeight)

                local y
                if openAbove then
                    y = buttonTop - actualHeight - margin
                else
                    y = buttonBottom + margin
                end

                y = math.clamp(y, margin, math.max(margin, pageHeight - actualHeight - margin))

                dropdown.Position = UDim2.fromOffset(x, y)
                dropdown.Size = UDim2.new(0, currentWidth, 0, actualHeight)
            end)

            if not ok then
                dropdown.Position = UDim2.fromOffset(10, 72)
                dropdown.Size = UDim2.new(0, currentWidth, 0, desiredDropdownHeight)
            end
        end

        local rebuild
        rebuild = function(filterText)
            local query = string.lower(tostring(filterText or ""))

            -- V22: normal Shop selectors keep one row per option and only update
            -- visibility/checkmark/background/layout state. No row destruction
            -- occurs during search, select/deselect, SELECT ALL, CLEAR ALL, or
            -- close/reopen after the row has been created once.
            if rowReuse then
                local selected = selectedLookup()
                local matchCount = 0

                for _, rowData in pairs(rowReuse.Rows) do
                    if rowData.Row and rowData.Row.Parent then
                        rowData.Row.Visible = false
                    end
                end

                for _, option in ipairs(options) do
                    if query == ""
                        or string.find(string.lower(option), query, 1, true) then

                        matchCount += 1

                        local rowData = rowReuse.Rows[option]
                        if not rowData or not rowData.Row or not rowData.Row.Parent then
                            local row = C(N("TextButton", {
                                Name = "CompactShopOption",
                                Text = "",
                                BackgroundColor3 = T.Surface2,
                                BackgroundTransparency = 0,
                                BorderSizePixel = 0,
                                AutoButtonColor = false,
                                Size = UDim2.new(1, 0, 0, rowHeight),
                                LayoutOrder = matchCount,
                                ZIndex = 152,
                            }, itemScroll), 4)

                            local check = N("TextLabel", {
                                Name = "OptionCheck",
                                Text = "",
                                Font = T.Font,
                                TextSize = 15,
                                TextColor3 = T.Success,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                BackgroundTransparency = 1,
                                Position = UDim2.new(0, 8, 0, 0),
                                Size = UDim2.new(0, 18, 1, 0),
                                ZIndex = 153,
                            }, row)

                            N("TextLabel", {
                                Name = "OptionName",
                                Text = option,
                                Font = T.Body,
                                TextSize = 13,
                                TextColor3 = T.White,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                TextTruncate = Enum.TextTruncate.AtEnd,
                                BackgroundTransparency = 1,
                                Position = UDim2.new(0, 28, 0, 0),
                                Size = UDim2.new(1, -36, 1, 0),
                                ZIndex = 153,
                            }, row)

                            rowData = {
                                Row = row,
                                Check = check,
                                Option = option,
                                Selected = false,
                            }
                            rowReuse.Rows[option] = rowData

                            row.MouseEnter:Connect(function()
                                if not rowData.Selected then
                                    row.BackgroundColor3 = T.RedDark
                                end
                            end)

                            row.MouseLeave:Connect(function()
                                row.BackgroundColor3 = rowData.Selected
                                    and (T.UserActiveBgAlt or AccentSelectedBg())
                                    or T.Surface2
                            end)

                            row.Activated:Connect(function()
                                if singleSelect then
                                    setValues({ rowData.Option })
                                    updateSelector()
                                    if refreshSummary then
                                        refreshSummary()
                                    end
                                    dropdown.Visible = false
                                    setSelectorChevron(false, false)
                                    if ActiveCompactShopChevron == chevron then
                                        ActiveCompactShopChevron = nil
                                    end
                                    if ActiveCompactShopDropdown == dropdown then
                                        ActiveCompactShopDropdown = nil
                                    end
                                else
                                    setSelected(
                                        rowData.Option,
                                        not selectedLookup()[rowData.Option]
                                    )
                                    rebuild(searchBox.Text)
                                end
                            end)
                        end

                        local isSelected = selected[option] == true
                        rowData.Selected = isSelected
                        rowData.Row.Visible = true
                        rowData.Row.LayoutOrder = matchCount
                        rowData.Row.BackgroundColor3 = isSelected
                            and (T.UserActiveBgAlt or AccentSelectedBg())
                            or T.Surface2
                        rowData.Check.Text = isSelected and "\u{2713}" or ""
                    end
                end

                if not rowReuse.Empty or not rowReuse.Empty.Parent then
                    rowReuse.Empty = N("TextLabel", {
                        Name = "CompactShopEmpty",
                        Text = "No matches",
                        Font = T.Body,
                        TextSize = 13,
                        TextColor3 = T.Muted,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, 34),
                        LayoutOrder = 1,
                        Visible = false,
                        ZIndex = 152,
                    }, itemScroll)
                end

                rowReuse.Empty.Visible = matchCount == 0
                itemScroll.CanvasSize = UDim2.new(
                    0,
                    0,
                    0,
                    math.max(1, matchCount) * (rowHeight + 2)
                )
                resizeDropdown(math.max(1, matchCount))
                return
            end

            -- Legacy path intentionally retained for Auction.
            for _, child in ipairs(itemScroll:GetChildren()) do
                if not child:IsA("UIListLayout") then
                    child:Destroy()
                end
            end

            local filtered = {}
            for _, option in ipairs(options) do
                if query == "" or string.find(string.lower(option), query, 1, true) then
                    table.insert(filtered, option)
                end
            end

            if #filtered == 0 then
                N("TextLabel", {
                    Text = "No matches",
                    Font = T.Body,
                    TextSize = 13,
                    TextColor3 = T.Muted,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 30),
                    LayoutOrder = 1,
                    ZIndex = 152,
                }, itemScroll)

                itemScroll.CanvasSize = UDim2.new(0, 0, 0, rowHeight + 2)
                resizeDropdown(1)
                return
            end

            local selected = selectedLookup()

            for index, option in ipairs(filtered) do
                local isSelected = selected[option] == true
                local row = C(N("TextButton", {
                    Name = "CompactShopOption",
                    Text = "",
                    BackgroundColor3 = isSelected and (T.UserActiveBgAlt or AccentSelectedBg()) or T.Surface2,
                    BackgroundTransparency = 0,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 0, rowHeight),
                    LayoutOrder = index,
                    ZIndex = 152,
                }, itemScroll), 4)

                N("TextLabel", {
                    Name = "OptionCheck",
                    Text = isSelected and "\u{2713}" or "",
                    Font = T.Font,
                    TextSize = 15,
                    TextColor3 = T.Success,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 8, 0, 0),
                    Size = UDim2.new(0, 18, 1, 0),
                    ZIndex = 153,
                }, row)

                N("TextLabel", {
                    Name = "OptionName",
                    Text = option,
                    Font = T.Body,
                    TextSize = 13,
                    TextColor3 = T.White,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 28, 0, 0),
                    Size = UDim2.new(1, -36, 1, 0),
                    ZIndex = 153,
                }, row)

                row.MouseEnter:Connect(function()
                    if not selectedLookup()[option] then
                        row.BackgroundColor3 = T.RedDark
                    end
                end)

                row.MouseLeave:Connect(function()
                    row.BackgroundColor3 = selectedLookup()[option]
                        and (T.UserActiveBgAlt or AccentSelectedBg())
                        or T.Surface2
                end)

                row.Activated:Connect(function()
                    if singleSelect then
                        setValues({ option })
                        updateSelector()
                        if refreshSummary then
                            refreshSummary()
                        end
                        dropdown.Visible = false
                        setSelectorChevron(false, false)
                        if ActiveCompactShopChevron == chevron then
                            ActiveCompactShopChevron = nil
                        end
                        if ActiveCompactShopDropdown == dropdown then
                            ActiveCompactShopDropdown = nil
                        end
                    else
                        setSelected(option, not selectedLookup()[option])
                        rebuild(searchBox.Text)
                    end
                end)
            end

            itemScroll.CanvasSize = UDim2.new(0, 0, 0, #filtered * (rowHeight + 2))
            resizeDropdown(#filtered)
        end

        local function pointInside(gui, point)
            local pos = gui.AbsolutePosition
            local size = gui.AbsoluteSize
            return point.X >= pos.X
                and point.X <= pos.X + size.X
                and point.Y >= pos.Y
                and point.Y <= pos.Y + size.Y
        end

        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            rebuild(searchBox.Text)
        end)

        selectAll.Activated:Connect(function()
            local set = selectedLookup()
            for _, option in ipairs(options) do
                set[option] = true
            end
            applySelectedSet(set)
            rebuild(searchBox.Text)
        end)

        clearAll.Activated:Connect(function()
            applySelectedSet({})
            rebuild(searchBox.Text)
        end)

        selector.Activated:Connect(function()
            local opening = not dropdown.Visible

            if ActiveCompactShopDropdown and ActiveCompactShopDropdown ~= dropdown then
                ActiveCompactShopDropdown.Visible = false
                if ActiveCompactShopChevron then
                    tw(ActiveCompactShopChevron, {Rotation = 0}, .14)
                    ActiveCompactShopChevron = nil
                end
            end

            dropdown.Visible = opening
            setSelectorChevron(opening, false)

            if animateChevron then
                ActiveCompactShopChevron = opening and chevron or nil
            end

            if opening then
                ActiveCompactShopDropdown = dropdown
                updateDropdownPosition()

                if rowReuse then
                    -- Avoid a duplicate rebuild: changing Text already fires the
                    -- search listener. If it is already empty, refresh once here.
                    if searchBox.Text ~= "" then
                        searchBox.Text = ""
                    else
                        rebuild("")
                    end
                else
                    -- Keep Auction's legacy open behavior unchanged.
                    searchBox.Text = ""
                    rebuild("")
                end
            elseif ActiveCompactShopDropdown == dropdown then
                ActiveCompactShopDropdown = nil
            end
        end)

        ShopScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            dropdown.Visible = false
            setSelectorChevron(false, false)
            if ActiveCompactShopChevron == chevron then
                ActiveCompactShopChevron = nil
            end
            if ActiveCompactShopDropdown == dropdown then
                ActiveCompactShopDropdown = nil
            end
        end)

        Page:GetPropertyChangedSignal("Visible"):Connect(function()
            if not Page.Visible then
                dropdown.Visible = false
                setSelectorChevron(false, true)
                if ActiveCompactShopChevron == chevron then
                    ActiveCompactShopChevron = nil
                end
                if ActiveCompactShopDropdown == dropdown then
                    ActiveCompactShopDropdown = nil
                end
            end
        end)

        Scale:GetPropertyChangedSignal("Scale"):Connect(function()
            if dropdown.Visible then
                updateDropdownPosition()
            end
        end)

        TrackConnection(UIS.InputBegan:Connect(function(input)
            if not dropdown.Visible then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local point = input.Position
            if not pointInside(dropdown, point)
                and not pointInside(selector, point) then
                dropdown.Visible = false
                setSelectorChevron(false, false)
                if ActiveCompactShopChevron == chevron then
                    ActiveCompactShopChevron = nil
                end
                if ActiveCompactShopDropdown == dropdown then
                    ActiveCompactShopDropdown = nil
                end
            end
        end))

        updateSelector()

        return {
            Refresh = updateSelector,
            Close = function()
                dropdown.Visible = false
                setSelectorChevron(false, false)
                if ActiveCompactShopChevron == chevron then
                    ActiveCompactShopChevron = nil
                end
                if ActiveCompactShopDropdown == dropdown then
                    ActiveCompactShopDropdown = nil
                end
            end,
        }
    end

    local function bindMultiSelect(selector, titleText, options, getter, setter, emptyText)
        local searchPlaceholder = "Search..."
        local upperTitle = string.upper(tostring(titleText or ""))
        if string.find(upperTitle, "SEED", 1, true) then
            searchPlaceholder = "Search seeds..."
        elseif string.find(upperTitle, "GEAR", 1, true) then
            searchPlaceholder = "Search gear..."
        elseif string.find(upperTitle, "CRATE", 1, true) then
            searchPlaceholder = "Search crates..."
        elseif string.find(upperTitle, "EGG", 1, true) then
            searchPlaceholder = "Search eggs..."
        elseif string.find(upperTitle, "PACK", 1, true) then
            searchPlaceholder = "Search packs..."
        end

        return setupCompactShopMultiPicker(
            selector,
            options,
            getter,
            function(values)
                setter(values)
            end,
            {
                EmptyText = emptyText or "Select...",
                SearchPlaceholder = searchPlaceholder,
                PreserveSize = true,

                -- V22: cache rows only for normal Shop selectors.
                -- Auction keeps the original destroy/rebuild implementation.
                ReuseRows = not string.find(
                    upperTitle,
                    "AUCTION",
                    1,
                    true
                ),

            }
        )
    end

    -- V23 SHOP VISUAL REFINE:
    -- Keep both worlds on the same cleaner two-column rhythm, tighten the
    -- gutters, and fill Fall Harvest's empty lower-right area with a compact
    -- overview card so the tab feels more balanced.
    local columnGap = 10
    local cardWidthScale = .5
    local cardWidthOffset = -5
    local smallCardHeight = 156
    local rowGap = 10
    local secondRowY = smallCardHeight + rowGap
    local thirdRowY = (smallCardHeight * 2) + (rowGap * 2)
    local auctionCardHeight = (smallCardHeight * 3) + (rowGap * 2)

    local leftColumnPos = UDim2.new(0, 1, 0, 0)
    local rightColumnPos = UDim2.new(.5, math.floor(columnGap / 2) - 1, 0, 0)
    local rightSecondRowPos = UDim2.new(.5, math.floor(columnGap / 2) - 1, 0, secondRowY)

    -- Fall Harvest's world name is long enough that it visually collides with
    -- the selector box inside the compact two-column cards. Use a shorter UI
    -- label for the selector helper text only, while keeping the full world
    -- name everywhere else (status, logs, shop info, etc.).
    local ShopWorldLabel = CurrentWorld.Key == "FallHarvestWorld"
        and "Fall Harvest"
        or CurrentWorld.Name

    local SeedsCard = panel(ShopScroll, leftColumnPos, UDim2.new(cardWidthScale, -math.ceil(columnGap / 2), 0, smallCardHeight), "SEEDS")
    decorateShopCard(SeedsCard, "LIVE SHOP", T.RedDark)
    local SeedSelector = makeSelectorRow(SeedsCard, "Seed Type", "Select " .. ShopWorldLabel .. " seeds", 25)
    local SeedSelectControl = bindMultiSelect(SeedSelector, "SELECT SEEDS", AllSeeds,
        function() return State.SelectedSeeds end,
        function(values) State.SelectedSeeds = filterAllowed(values, AllSeeds) end,
        "Select seeds...")
    local SeedSelectedToggle = makeToggleRow(SeedsCard, "Buy Selected", "Buy only selected seeds", 72, State.BuySelectedSeeds, function(value)
        State.BuySelectedSeeds = value == true
    end)
    local SeedAllToggle = makeToggleRow(SeedsCard, "Buy All Seeds", "Buy all available seeds", 114, State.BuyAllSeeds, function(value)
        State.BuyAllSeeds = value == true
    end)

    local GearCardPosition = AuctionWorldEnabled
        and UDim2.new(0, 1, 0, secondRowY)
        or rightColumnPos
    local GearCard = panel(ShopScroll, GearCardPosition, UDim2.new(cardWidthScale, -math.ceil(columnGap / 2), 0, smallCardHeight), "GEAR")
    decorateShopCard(GearCard, "LIVE SHOP", T.RedDark)
    local GearSelector = makeSelectorRow(GearCard, "Select Gear", "Choose " .. ShopWorldLabel .. " gear", 25)
    local GearSelectControl = bindMultiSelect(GearSelector, "SELECT GEAR", AllGears,
        function() return State.SelectedGears end,
        function(values) State.SelectedGears = filterAllowed(values, AllGears) end,
        "Select gear...")
    local GearSelectedToggle = makeToggleRow(GearCard, "Buy Selected", "Buy only selected gear", 72, State.BuySelectedGears, function(value)
        State.BuySelectedGears = value == true
    end)
    local GearAllToggle = makeToggleRow(GearCard, "Buy All Gears", "Buy all available gear", 114, State.BuyAllGears, function(value)
        State.BuyAllGears = value == true
    end)

    local CrateCardPosition = AuctionWorldEnabled
        and UDim2.new(0, 1, 0, thirdRowY)
        or UDim2.new(0, 1, 0, secondRowY)
    local CrateCard = panel(ShopScroll, CrateCardPosition, UDim2.new(cardWidthScale, -math.ceil(columnGap / 2), 0, smallCardHeight), "CRATES")
    decorateShopCard(CrateCard, "LIVE SHOP", T.RedDark)
    local CrateSelector = makeSelectorRow(CrateCard, "Select Crate", "Choose " .. ShopWorldLabel .. " crates", 25)
    local CrateSelectControl = bindMultiSelect(CrateSelector, "SELECT CRATES", AllCrates,
        function() return State.SelectedCrates end,
        function(values) State.SelectedCrates = filterAllowed(values, AllCrates) end,
        "Select crates...")
    local CrateSelectedToggle = makeToggleRow(CrateCard, "Buy Selected", "Buy only selected crates", 72, State.BuySelectedCrates, function(value)
        State.BuySelectedCrates = value == true
    end)
    local CrateAllToggle = makeToggleRow(CrateCard, "Buy All Crates", "Buy all available crates", 114, State.BuyAllCrates, function(value)
        State.BuyAllCrates = value == true
    end)

    local AuctionControls = {}
    local AuctionMaxPriceBox
    local AuctionToggle
    local startAuctionWorker
    local stopAuctionWorker

    if AuctionWorldEnabled then
        local AuctionCard = panel(
            ShopScroll,
            rightColumnPos,
            UDim2.new(cardWidthScale, -math.ceil(columnGap / 2), 0, auctionCardHeight),
            "AUTO BUY AUCTION"
        )
        decorateShopCard(AuctionCard, IsFallAuctionWorld and "LEAVES" or "SHECKLES", T.Success)

        local function auctionSelector(titleText, subtitle, y, options, getter, setter, empty)
            local selector = makeSelectorRow(AuctionCard, titleText, subtitle, y)
            local control = bindMultiSelect(selector, string.upper(titleText), options, getter, setter, empty)
            AuctionControls[#AuctionControls + 1] = control
            return control
        end

        auctionSelector("Auction Seeds", "Seeds from Auction", 28, AuctionSeeds,
            function() return State.AuctionSeeds end,
            function(values) State.AuctionSeeds = filterAllowed(values, AuctionSeeds) end,
            "Select seeds...")
        auctionSelector("Auction Gears", "Gear from Auction", 76, AuctionGears,
            function() return State.AuctionGears end,
            function(values) State.AuctionGears = filterAllowed(values, AuctionGears) end,
            "Select gear...")
        auctionSelector("Auction Crates", "Crates from Auction", 124, AuctionCrates,
            function() return State.AuctionCrates end,
            function(values) State.AuctionCrates = filterAllowed(values, AuctionCrates) end,
            "Select crates...")
        auctionSelector("Auction Eggs", "Eggs from Auction", 172, AuctionEggs,
            function() return State.AuctionEggs end,
            function(values) State.AuctionEggs = filterAllowed(values, AuctionEggs) end,
            "Select eggs...")
        auctionSelector("Auction SeedPacks", "Seed packs from Auction", 220, AuctionSeedPacks,
            function() return State.AuctionSeedPacks end,
            function(values) State.AuctionSeedPacks = filterAllowed(values, AuctionSeedPacks) end,
            "Select packs...")

        AuctionMaxPriceBox = makeInputRow(AuctionCard, "Max Price", "Example: 50000000 = 50M", 268, State.AuctionMaxPrice > 0 and State.AuctionMaxPrice or "", function(textValue, box)
            State.AuctionMaxPrice = math.max(0, tonumber(textValue) or 0)
            box.Text = State.AuctionMaxPrice > 0 and tostring(State.AuctionMaxPrice) or ""
        end)

        AuctionToggle = makeToggleRow(AuctionCard, "Enable Auto Buy Auction", "Buy selected lots using " .. AuctionCurrencyName, 312, State.AuctionEnabled, function(value)
            -- Commit the custom Max Price field before starting. In the old
            -- merged build the auction worker could remain idle when the field
            -- had not fired FocusLost yet.
            if AuctionMaxPriceBox then
                State.AuctionMaxPrice = math.max(0, tonumber(AuctionMaxPriceBox.Text) or 0)
                AuctionMaxPriceBox.Text = State.AuctionMaxPrice > 0 and tostring(State.AuctionMaxPrice) or ""
            end

            State.AuctionEnabled = value == true

            if State.AuctionEnabled then
                if State.AuctionMaxPrice <= 0 then
                    setStatus("● AUCTION • SET MAX PRICE", false)
                else
                    setStatus("● AUCTION ON", true)
                end

                if startAuctionWorker then
                    startAuctionWorker()
                end
            else
                if stopAuctionWorker then
                    stopAuctionWorker()
                end
                setStatus("● READY", nil)
            end
        end)

        local AuctionInfoBox = C(N("Frame", {
            BackgroundColor3 = T.Surface2,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 10, 0, 358),
            Size = UDim2.new(1, -20, 0, 70),
        }, AuctionCard), 5)
        S(AuctionInfoBox, T.Stroke, 0.55, 1)

        addShopInfoLines(AuctionInfoBox, {
            { Text = CurrentWorld.Name .. " • " .. AuctionCurrencyName, Color = T.White, Font = T.Font },
            "• Current-world catalog + live auction-only items",
            "• Robux-only listings are ignored",
            "• Keep Max Price set before enabling auction buying",
        }, 8)

        ShopScroll.CanvasSize = UDim2.new(0, 0, 0, auctionCardHeight + 8)
    else
        local OverviewCard = panel(
            ShopScroll,
            rightSecondRowPos,
            UDim2.new(cardWidthScale, -math.ceil(columnGap / 2), 0, smallCardHeight),
            "SHOP INFO"
        )
        decorateShopCard(OverviewCard, "OVERVIEW", T.Success)

        addShopInfoLines(OverviewCard, {
            { Text = CurrentWorld.Name, Color = T.White, Font = T.Font },
            "• Buy Selected uses only your chosen dropdown items",
            "• Buy All ignores filters and purchases live stock",
            "• Auction is unavailable in this world",
            "• Restock scanning still works for Seeds, Gear, and Crates",
        }, 32)

        ShopScroll.CanvasSize = UDim2.new(0, 0, 0, secondRowY + smallCardHeight + 6)
    end

    if not CurrentWorld.Supported then
        SeedSelectedToggle:Set(false, false); SeedAllToggle:Set(false, false)
        GearSelectedToggle:Set(false, false); GearAllToggle:Set(false, false)
        CrateSelectedToggle:Set(false, false); CrateAllToggle:Set(false, false)
        State.BuySelectedSeeds, State.BuyAllSeeds = false, false
        State.BuySelectedGears, State.BuyAllGears = false, false
        State.BuySelectedCrates, State.BuyAllCrates = false, false
        setStatus("● UNSUPPORTED PLACE", false)
    else
        setStatus("● " .. CurrentWorld.Name:upper(), true)
    end

    local function getNetworking()
        local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
        local networkingModule = sharedModules and sharedModules:FindFirstChild("Networking")
        if not networkingModule then return nil end
        local ok, networking = pcall(require, networkingModule)
        return ok and type(networking) == "table" and networking or nil
    end

    local function normalizedName(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    local IsFallShopWorld = CurrentWorld.Key == "FallHarvestWorld"

    local function getShopFrame(shopName)
        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local shopGui = gui and gui:FindFirstChild(shopName)
        return shopGui and shopGui:FindFirstChild("Frame")
    end

    local function getShopItemsRoot(shopName)
        local frame = getShopFrame(shopName)
        if not frame then return nil end

        if shopName == "SeedShop" then
            return frame:FindFirstChild("NormalShop")
                or frame:FindFirstChild("NormalShop", true)
        end

        -- FALL GEAR FIX:
        -- Fall Harvest's GearShop is not guaranteed to use the exact same
        -- container hierarchy as CrateShop. Prefer its known containers, but
        -- fall back to the whole Frame so display-name based discovery below
        -- can still find gear cards whose Instance names are generic/internal.
        if shopName == "GearShop" and IsFallShopWorld then
            return frame:FindFirstChild("ScrollingFrame")
                or frame:FindFirstChild("ScrollingFrame", true)
                or frame:FindFirstChild("NormalShop")
                or frame:FindFirstChild("NormalShop", true)
                or frame:FindFirstChild("Items")
                or frame:FindFirstChild("Items", true)
                or frame
        end

        -- Keep the already-working Crate path unchanged.
        return frame:FindFirstChild("ScrollingFrame")
            or frame:FindFirstChild("ScrollingFrame", true)
    end

    local function parseShopStockText(value)
        local clean = tostring(value or ""):gsub("<[^>]->", "")
        local lower = string.lower(clean)

        if string.find(lower, "sold out", 1, true)
            or string.find(lower, "out of stock", 1, true) then
            return 0
        end

        return tonumber(clean:match("[xX]%s*(%d+)%s*[iI][nN]%s*[sS]tock"))
            or tonumber(clean:match("(%d+)%s*[iI][nN]%s*[sS]tock"))
            or tonumber(clean:match("[sS]tock%s*[:%-]?%s*[xX]?%s*(%d+)"))
            or tonumber(clean:match("[xX]%s*(%d+)"))
    end

    local function findStockLabel(container)
        if not container then return nil end

        local direct = container:FindFirstChild("Stock_Text")
            or container:FindFirstChild("Stock_Text", true)
        if direct and (direct:IsA("TextLabel") or direct:IsA("TextButton")) then
            return direct
        end

        for _, object in ipairs(container:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton"))
                and string.find(normalizedName(object.Name), "stock", 1, true) then
                return object
            end
        end

        return nil
    end

    local function cardLooksSoldOut(container)
        if not container then return false end

        for _, object in ipairs(container:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                local lower = string.lower(tostring(object.Text or ""):gsub("<[^>]->", ""))
                if string.find(lower, "sold out", 1, true)
                    or string.find(lower, "out of stock", 1, true) then
                    return true
                end
            end
        end

        return false
    end

    local function findFallGearCard(root, frame, itemName)
        local wanted = normalizedName(itemName)
        if wanted == "" then return nil end

        -- First keep the old exact/normalized Instance-name behavior.
        local item = root and (root:FindFirstChild(itemName) or root:FindFirstChild(itemName, true))
        if item then return item end

        local searchRoot = frame or root
        if not searchRoot then return nil end

        for _, object in ipairs(searchRoot:GetDescendants()) do
            if normalizedName(object.Name) == wanted then
                return object
            end
        end

        -- Fall Gear cards can use generic/internal Instance names while the
        -- visible TextLabel contains "Super Syrup Sprinkler", "Wind Staff", etc.
        -- Find that display label, then walk upward to the nearest card that
        -- owns a stock label.
        local bestTextMatch = nil
        for _, object in ipairs(searchRoot:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                local shown = normalizedName(object.Text)
                if shown == wanted then
                    bestTextMatch = object
                    break
                elseif not bestTextMatch
                    and shown ~= ""
                    and string.find(shown, wanted, 1, true) then
                    bestTextMatch = object
                end
            end
        end

        if bestTextMatch then
            local current = bestTextMatch.Parent
            local steps = 0
            while current and current ~= searchRoot.Parent and steps < 8 do
                if findStockLabel(current) then
                    return current
                end
                current = current.Parent
                steps += 1
            end

            -- Even without a named Stock_Text, keep the nearest reasonable
            -- parent as a last-resort card. The sold-out check below still
            -- prevents obvious unavailable entries from being purchased.
            return bestTextMatch.Parent
        end

        return nil
    end

    local function getLiveStockCount(shopName, itemName)
        local root = getShopItemsRoot(shopName)
        if not root then return nil end

        local frame = getShopFrame(shopName)
        local item

        if shopName == "GearShop" and IsFallShopWorld then
            item = findFallGearCard(root, frame, itemName)
        else
            -- Preserve the known-working Seed/Crate lookup behavior.
            item = root:FindFirstChild(itemName) or root:FindFirstChild(itemName, true)
            if not item then
                local wanted = normalizedName(itemName)
                for _, object in ipairs(root:GetDescendants()) do
                    if normalizedName(object.Name) == wanted then
                        item = object
                        break
                    end
                end
            end
        end

        if not item then return nil end

        -- Existing Seed/Crate cards normally keep Stock_Text under Main_Frame.
        -- Fall Gear additionally accepts Stock_Text anywhere in the matched card.
        local main = item:FindFirstChild("Main_Frame") or item:FindFirstChild("Main_Frame", true)
        local stock = main and findStockLabel(main) or findStockLabel(item)

        if stock then
            local parsed = parseShopStockText(stock.Text)
            if parsed ~= nil then
                return parsed
            end
        end

        if shopName == "GearShop" and IsFallShopWorld then
            -- Some Fall gear cards expose the item/display state but not the
            -- same Stock_Text hierarchy used by Seeds/Crates. If the card is
            -- clearly sold out, report zero. Otherwise allow ONE purchase
            -- request so the server remains the source of truth.
            --
            -- This fallback applies ONLY to Fall Gear and cannot alter the
            -- already-working Seed or Crate behavior.
            if cardLooksSoldOut(item) then
                return 0
            end
            return 1
        end

        return nil
    end

    local function appendAvailable(result, seen, shopName, names)
        for _, itemName in ipairs(names or {}) do
            local count = getLiveStockCount(shopName, itemName)
            local key = shopName .. "\0" .. itemName
            if count and count > 0 and not seen[key] then
                seen[key] = true
                result[#result + 1] = { shop = shopName, item = itemName, stock = count }
            end
        end
    end

    local function getAvailableChosenItems()
        local result, seen = {}, {}
        if State.BuySelectedSeeds then appendAvailable(result, seen, "SeedShop", State.SelectedSeeds) end
        if State.BuyAllSeeds then appendAvailable(result, seen, "SeedShop", AllSeeds) end
        if State.BuySelectedGears then appendAvailable(result, seen, "GearShop", State.SelectedGears) end
        if State.BuyAllGears then appendAvailable(result, seen, "GearShop", AllGears) end
        if State.BuySelectedCrates then appendAvailable(result, seen, "CrateShop", State.SelectedCrates) end
        if State.BuyAllCrates then appendAvailable(result, seen, "CrateShop", AllCrates) end
        return result
    end

    local function parseRestockText(textValue)
        local clean = tostring(textValue or ""):gsub("<[^>]->", ""):lower()
        local minutes, seconds = clean:match("restock%s+in%s+(%d+)%s*m%s+(%d+)%s*s")
        if minutes then return tonumber(minutes) * 60 + tonumber(seconds) end
        local secondsOnly = clean:match("restock%s+in%s+(%d+)%s*s")
        if secondsOnly then return tonumber(secondsOnly) end
        return nil
    end

    -- V13: cache the game's live restock Timer instead of walking all three
    -- shop GUIs four times per second.
    local cachedRestockTimer = nil
    local cachedRestockTimerConnection = nil
    local cachedRestockTimerShop = nil
    local onCachedRestockTimerChanged = nil

    local function disconnectCachedRestockTimer()
        if cachedRestockTimerConnection then
            pcall(function()
                cachedRestockTimerConnection:Disconnect()
            end)
            cachedRestockTimerConnection = nil
        end

        cachedRestockTimer = nil
        cachedRestockTimerShop = nil
    end

    local function isCachedRestockTimerValid()
        local timer = cachedRestockTimer
        if not (timer and timer.Parent and timer:IsA("TextLabel")) then
            return false
        end

        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not gui then
            return false
        end

        local ok, isDescendant = pcall(function()
            return timer:IsDescendantOf(gui)
        end)

        return ok and isDescendant == true
    end

    local function findLiveRestockTimer()
        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not gui then return nil, nil end

        -- The three shops share the same restock cycle. Prefer SeedShop because
        -- it is the shop we already teleport to before the confirmed working
        -- Seed/Gear/Crate purchase pass, then use Gear/Crate as fallbacks.
        for _, shopName in ipairs({ "SeedShop", "GearShop", "CrateShop" }) do
            local shopGui = gui:FindFirstChild(shopName)
            local frame = shopGui and shopGui:FindFirstChild("Frame")
            local header = frame and (
                frame:FindFirstChild("Header")
                or frame:FindFirstChild("Header", true)
            )

            if header then
                local refreshIn = header:FindFirstChild("RefreshIn")
                    or header:FindFirstChild("RefreshIn", true)

                local timer = refreshIn and (
                    refreshIn:FindFirstChild("Timer")
                    or refreshIn:FindFirstChild("Timer", true)
                )

                if not timer then
                    timer = header:FindFirstChild("Timer", true)
                end

                if timer and timer:IsA("TextLabel")
                    and parseRestockText(timer.Text) ~= nil then
                    return timer, shopName
                end
            end
        end

        return nil, nil
    end

    local function bindLiveRestockTimer(force)
        if not force and isCachedRestockTimerValid() then
            return cachedRestockTimer
        end

        local foundTimer, foundShop = findLiveRestockTimer()

        if foundTimer == cachedRestockTimer and isCachedRestockTimerValid() then
            return cachedRestockTimer
        end

        disconnectCachedRestockTimer()

        if not foundTimer then
            return nil
        end

        cachedRestockTimer = foundTimer
        cachedRestockTimerShop = foundShop

        cachedRestockTimerConnection = TrackConnection(
            foundTimer:GetPropertyChangedSignal("Text"):Connect(function()
                if onCachedRestockTimerChanged then
                    onCachedRestockTimerChanged("TIMER_TEXT")
                end
            end)
        )

        return cachedRestockTimer
    end

    local function getCachedRestockSeconds()
        if not isCachedRestockTimerValid() then
            bindLiveRestockTimer(true)
        end

        local timer = cachedRestockTimer
        if not timer then
            return nil
        end

        return parseRestockText(timer.Text)
    end

    local function clickGuiButton(buttonObject)
        if not (buttonObject and buttonObject:IsA("GuiButton") and buttonObject.Visible) then return false end
        if type(firesignal) == "function" then
            local ok = pcall(function() firesignal(buttonObject.Activated) end)
            if ok then return true end
        end
        local center = buttonObject.AbsolutePosition + buttonObject.AbsoluteSize / 2
        return pcall(function()
            VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
        end)
    end

    local function getTeleportButton(name)
        local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local root = gui and gui:FindFirstChild("TeleportButtons")
        local container = root and root:FindFirstChild("TeleportButtons")
        return container and container:FindFirstChild(name)
    end

    local function teleportToSeeds()
        local ok = clickGuiButton(getTeleportButton("SeedsButton"))
        if ok then task.wait(1.25) end
        return ok
    end

    local function teleportToGarden()
        local ok = clickGuiButton(getTeleportButton("GardenButton"))
        if ok then task.wait(1.25) end
        return ok
    end

    local lastPurchaseErrorAt = 0
    local function purchaseAvailable(reason)
        local available = getAvailableChosenItems()
        if #available == 0 then return true, 0 end

        if not teleportToSeeds() then
            if os.clock() - lastPurchaseErrorAt > 8 then
                lastPurchaseErrorAt = os.clock()
                setStatus("● WAITING FOR SEEDS TELEPORT", false)
            end
            return false, 0
        end

        task.wait(0.35)
        available = getAvailableChosenItems()
        if #available == 0 then return true, 0 end

        local networking = getNetworking()
        if not networking then
            setStatus("● NETWORKING LOADING", false)
            return false, 0
        end

        local requests, seedRequests = 0, 0
        for _, entry in ipairs(available) do
            for _ = 1, entry.stock do
                local sent = pcall(function()
                    if entry.shop == "SeedShop" and networking.SeedShop and networking.SeedShop.PurchaseSeed then
                        networking.SeedShop.PurchaseSeed:Fire(entry.item)
                    elseif entry.shop == "GearShop" and networking.GearShop and networking.GearShop.PurchaseGear then
                        networking.GearShop.PurchaseGear:Fire(entry.item)
                    elseif entry.shop == "GearShop" then
                        error("GearShop.PurchaseGear unavailable")
                    elseif entry.shop == "CrateShop" and networking.CrateShop and networking.CrateShop.PurchaseCrate then
                        networking.CrateShop.PurchaseCrate:Fire(entry.item)
                    else
                        error("Purchase remote unavailable")
                    end
                end)
                if not sent then break end
                requests += 1
                if entry.shop == "SeedShop" then seedRequests += 1 end
                task.wait(0.11)
            end
        end

        if requests > 0 then
            setStatus("● BOUGHT " .. tostring(requests) .. " • " .. tostring(reason), true)

            -- After the complete Seed/Gear/Crate purchase pass, return to the
            -- player's garden by clicking the game's own GardenButton, exactly
            -- like the old Fall Harvest shop script.  This is intentionally
            -- done only once after ALL purchase requests finish, not once per
            -- item, so buying several stocked items does not spam teleports.
            task.wait(0.15)
            local returnedToGarden = teleportToGarden()
            if returnedToGarden then
                setStatus("● BOUGHT " .. tostring(requests) .. " • RETURNED TO GARDEN", true)
            else
                -- Buying already completed successfully.  A missing/not-yet-
                -- replicated GardenButton should not mark the purchase as a
                -- failure or restart the buy pass.
                setStatus("● BOUGHT " .. tostring(requests) .. " • GARDEN BUTTON UNAVAILABLE", true)
            end
        else
            setStatus("● NO MATCHING STOCK", nil)
        end
        return true, requests
    end

    local function anyShopAutoBuy()
        return CurrentWorld.Supported and (
            State.BuySelectedSeeds or State.BuyAllSeeds
            or State.BuySelectedGears or State.BuyAllGears
            or State.BuySelectedCrates or State.BuyAllCrates
        )
    end

    local function targetSignature()
        local function list(values)
            local copy = cloneList(values)
            table.sort(copy)
            return table.concat(copy, "\31")
        end
        return table.concat({
            tostring(State.BuySelectedSeeds), tostring(State.BuyAllSeeds), list(State.SelectedSeeds),
            tostring(State.BuySelectedGears), tostring(State.BuyAllGears), list(State.SelectedGears),
            tostring(State.BuySelectedCrates), tostring(State.BuyAllCrates), list(State.SelectedCrates),
        }, "\30")
    end

    -- SoundService itself has no `Volume` property.  The old merged Shop
    -- touched SoundService.Volume during initialization, which threw even when
    -- every auto-buy toggle was OFF and prevented the Shop from loading.
    --
    -- Mute only actual Sound instances while Shop auto-buy is active, and
    -- restore each sound's previous volume when auto-buy stops.
    local mutedSoundVolumes = setmetatable({}, {__mode = "k"})
    local shopSoundsMuted = false

    local function muteShopSounds()
        if shopSoundsMuted then return end
        shopSoundsMuted = true

        for _, object in ipairs(SoundService:GetDescendants()) do
            if object:IsA("Sound") then
                if mutedSoundVolumes[object] == nil then
                    mutedSoundVolumes[object] = object.Volume
                end
                pcall(function()
                    object.Volume = 0
                end)
            end
        end
    end

    local function restoreShopSounds()
        if not shopSoundsMuted and next(mutedSoundVolumes) == nil then return end
        shopSoundsMuted = false

        for sound, previousVolume in pairs(mutedSoundVolumes) do
            if sound and sound.Parent then
                pcall(function()
                    sound.Volume = previousVolume
                end)
            end
            mutedSoundVolumes[sound] = nil
        end
    end

    -- If the game creates a new Sound while auto-buy is already active,
    -- silence that Sound too without touching the SoundService object itself.
    local shopSoundAddedConnection = TrackConnection(SoundService.DescendantAdded:Connect(function(object)
        if shopSoundsMuted and object:IsA("Sound") then
            if mutedSoundVolumes[object] == nil then
                mutedSoundVolumes[object] = object.Volume
            end
            pcall(function()
                object.Volume = 0
            end)
        end
    end))

    -- V14: no dedicated 0.2-second sound watcher.
    -- The existing V13 Shop safety pass already knows whether any Shop
    -- Auto Buy toggle is active, so use that same pass to synchronize
    -- the mute state only when it actually changes.
    local function syncShopSoundMute(enabled)
        if enabled then
            if not shopSoundsMuted then
                muteShopSounds()
            end
        elseif shopSoundsMuted or next(mutedSoundVolumes) ~= nil then
            restoreShopSounds()
        end
    end

    RegisterScoopHubCleanup(function()
        restoreShopSounds()
    end)

    -- ============================================================
    -- V13 SHOP RESTOCK EVENT WATCHER + V14 SOUND STATE MERGE
    --
    -- V14 removes the separate 0.2s Shop sound polling worker and reuses
    -- this existing 1s Shop safety/reconciliation worker.
    --
    -- Normal path:
    --   cached Timer.Text changes -> queue an immediate state pass
    --
    -- Safety path:
    --   every 1 second -> validate/rebind Timer + detect selection/toggle
    --   changes + retry transient failures.
    --
    -- purchaseAvailable() itself is intentionally unchanged.
    -- ============================================================
    do
        local lastSeconds = nil
        local sawZero = false
        local pendingRestock = false
        local watcherArmed = false
        local initialScanPending = false
        local wasEnabled = false
        local lastSignature = nil
        local lastMissingNoticeAt = 0

        local restockEventPending = false
        local restockDrainRunning = false
        local delayedRestockSerial = 0

        local function resetRestockState()
            delayedRestockSerial += 1

            lastSeconds = nil
            sawZero = false
            pendingRestock = false
            watcherArmed = false
            initialScanPending = false
            wasEnabled = false
            lastSignature = nil
            restockEventPending = false

            disconnectCachedRestockTimer()
        end

        local queueRestockPass

        local function processRestockPass(reason)
            if not ScoopHubRunAlive() or not SG.Parent then
                return
            end

            local enabled = anyShopAutoBuy()
            syncShopSoundMute(enabled)

            if not enabled then
                if wasEnabled or cachedRestockTimer then
                    resetRestockState()
                end
                return
            end

            if not wasEnabled then
                wasEnabled = true
                initialScanPending = true
                lastSignature = targetSignature()
                setStatus("● CHECKING LIVE STOCK", nil)
            end

            local signature = targetSignature()
            if signature ~= lastSignature then
                lastSignature = signature
                initialScanPending = true
                pendingRestock = false
                delayedRestockSerial += 1
                setStatus("● SELECTION UPDATED", nil)
            end

            local timer = getCachedRestockSeconds()
            if timer == nil then
                if os.clock() - lastMissingNoticeAt > 8 then
                    lastMissingNoticeAt = os.clock()
                    setStatus("● WAITING FOR RESTOCK TIMER", false)
                end
                return
            end

            if initialScanPending then
                local complete = purchaseAvailable("CURRENT STOCK")
                if not complete then
                    return
                end
                initialScanPending = false

                -- purchaseAvailable teleports away and back. Roblox can replace
                -- shop GUI objects during that trip, so the 1-second safety pass
                -- will repair the Timer binding if needed.
            end

            if not watcherArmed then
                watcherArmed = true
                lastSeconds = timer
                sawZero = timer <= 1
                setStatus("● WATCHING RESTOCK • " .. CurrentWorld.Name:upper(), true)
                return
            end

            if pendingRestock then
                return
            end

            if timer <= 1 then
                sawZero = true
            end

            if sawZero
                and lastSeconds ~= nil
                and lastSeconds <= 2
                and timer >= 10 then

                pendingRestock = true
                sawZero = false
                setStatus("● RESTOCK DETECTED", true)

                delayedRestockSerial += 1
                local mySerial = delayedRestockSerial

                -- Preserve V12's 0.75s settling delay, but schedule it instead
                -- of keeping a 0.25s polling loop alive.
                task.delay(0.75, function()
                    if mySerial ~= delayedRestockSerial
                        or not ScoopHubRunAlive()
                        or not SG.Parent
                        or not anyShopAutoBuy() then
                        return
                    end

                    local complete = purchaseAvailable("RESTOCK")
                    if complete then
                        pendingRestock = false
                    end

                    if queueRestockPass then
                        queueRestockPass(
                            complete and "POST_RESTOCK" or "RESTOCK_RETRY"
                        )
                    end
                end)
            end

            lastSeconds = timer
        end

        queueRestockPass = function(reason)
            if not ScoopHubRunAlive() or not SG.Parent then
                return
            end

            restockEventPending = true

            if restockDrainRunning then
                return
            end

            restockDrainRunning = true

            task.defer(function()
                while ScoopHubRunAlive()
                    and SG.Parent
                    and restockEventPending do

                    restockEventPending = false

                    local ok, err = pcall(function()
                        processRestockPass(reason)
                    end)

                    if not ok then
                        warn(
                            "[ScoopHub Shop] Restock watcher error: "
                            .. tostring(err)
                        )
                    end
                end

                restockDrainRunning = false
            end)
        end

        -- The cached TextLabel calls this immediately whenever Roblox updates
        -- "Restock in ...". No recurring GUI traversal is needed.
        onCachedRestockTimerChanged = function(reason)
            queueRestockPass(reason or "TIMER_TEXT")
        end

        RegisterScoopHubCleanup(function()
            delayedRestockSerial += 1
            onCachedRestockTimerChanged = nil
            disconnectCachedRestockTimer()
        end)

        task.spawn(function()
            task.wait(1.5)

            while ScoopHubRunAlive() and SG.Parent do
                local enabled = anyShopAutoBuy()

                -- V14: this replaces the old separate 0.2s sound watcher.
                -- Sound state is synchronized on the same 1s Shop safety pass.
                syncShopSoundMute(enabled)

                if enabled then
                    -- Rebind only when the cached label became stale/replaced.
                    if not isCachedRestockTimerValid() then
                        bindLiveRestockTimer(true)
                    end

                    -- One lightweight safety/reconciliation pass per second.
                    -- This also catches selection changes because the current
                    -- compact Shop toggles do not expose a shared change event.
                    queueRestockPass("SAFETY")
                    task.wait(1)
                else
                    if wasEnabled or cachedRestockTimer then
                        resetRestockState()
                    end
                    task.wait(1)
                end
            end

            syncShopSoundMute(false)
            resetRestockState()
            onCachedRestockTimerChanged = nil
        end)
    end

    -- ============================================================
    -- AUCTION AUTO-BUY
    -- Uses the same logic as the standalone Garden Valley auction that was
    -- confirmed working: direct Networking.Auctioneer access, getgc lot scan,
    -- live decreasing-price calculation, then PurchaseLot:Fire(lotId, price).
    -- ============================================================
    local auctionRunId = 0

    stopAuctionWorker = function()
        auctionRunId = auctionRunId + 1
    end

    startAuctionWorker = function()
        if not AuctionWorldEnabled then return end

        -- Invalidate any older worker before starting a fresh one.
        auctionRunId = auctionRunId + 1
        local myRunId = auctionRunId

        task.spawn(function()
            local ok, err = pcall(function()
                local Networking = require(ReplicatedStorage.SharedModules.Networking)
                local Auctioneer = Networking.Auctioneer

                if not Auctioneer or not Auctioneer.PurchaseLot then
                    error("Networking.Auctioneer.PurchaseLot is unavailable")
                end

                local function buildSelectedAuctionTargets()
                    local selected = {}
                    local function add(values)
                        for _, value in ipairs(values or {}) do
                            local key = auctionNameKey(value)
                            if key ~= "" then
                                selected[key] = true
                            end
                        end
                    end
                    add(State.AuctionSeeds)
                    add(State.AuctionGears)
                    add(State.AuctionCrates)
                    add(State.AuctionEggs)
                    add(State.AuctionSeedPacks)
                    return selected
                end

                local function getCurrentPrice(lot)
                    local startPrice = tonumber(lot.startPrice or lot.StartPrice)
                    local minPrice = tonumber(lot.minPrice or lot.MinPrice)
                    local rolledAt = tonumber(lot.rolledAt or lot.RolledAt)
                    local intervalSeconds = tonumber(
                        lot.decrementIntervalSeconds or lot.DecrementIntervalSeconds
                    )
                    local decrementPercent = tonumber(
                        lot.decrementPercent or lot.DecrementPercent
                    )

                    -- Updated Auction pricing decreases by a percentage of the
                    -- starting price once per decrement interval, then clamps to
                    -- minPrice. This replaces the old hard-coded 300-second linear
                    -- interpolation, which could make Max Price comparisons wrong.
                    if startPrice and minPrice and rolledAt
                        and intervalSeconds and intervalSeconds > 0
                        and decrementPercent then

                        local elapsed = math.max(0, workspace:GetServerTimeNow() - rolledAt)
                        local intervals = math.floor(elapsed / intervalSeconds)
                        local decrementPerInterval = startPrice * (decrementPercent / 100)
                        local currentPrice = startPrice - (decrementPerInterval * intervals)

                        return math.max(minPrice, currentPrice)
                    end

                    -- Compatibility fallback for any legacy lot that does not yet
                    -- expose the new decrement fields.
                    local currentPrice = tonumber(lot.currentPrice or lot.CurrentPrice
                        or lot.price or lot.Price)
                    if currentPrice then
                        return currentPrice
                    end

                    return startPrice or minPrice or 0
                end

                local function getAuctionCurrencyBalance()
                    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
                    local valueObject = leaderstats and leaderstats:FindFirstChild(AuctionCurrencyName)
                    if not valueObject then return nil end

                    local ok, value = pcall(function()
                        return valueObject.Value
                    end)
                    if not ok then return nil end
                    return tonumber(value)
                end

                while ScoopHubRunAlive() and State.AuctionEnabled
                    and myRunId == auctionRunId
                    and SG.Parent do

                    -- Keep reading the textbox-backed state every pass so the
                    -- user can change Max Price while Auction is already ON.
                    local maxPrice = tonumber(State.AuctionMaxPrice) or 0
                    local lots = getCurrentWorldAuctionLots()
                    mergeLiveAuctionOptions(lots)
                    local selectedTargets = buildSelectedAuctionTargets()
                    local balance = getAuctionCurrencyBalance()
                    local matched = 0
                    local attempted = 0
                    local insufficientFunds = false

                    for _, lot in ipairs(lots) do
                        if not State.AuctionEnabled or myRunId ~= auctionRunId then
                            break
                        end

                        local name = lot.displayName or lot.name or ""
                        local nameKey = auctionNameKey(name)
                        if selectedTargets[nameKey]
                            and not isRobuxOnlyAuctionLot(lot) then
                            matched = matched + 1

                            local price = getCurrentPrice(lot)
                            local stock = tonumber(
                                lot.stockQuantity or lot.StockQuantity
                                or lot.stock or lot.Stock
                            )
                            if stock == nil then stock = 1 end

                            if price > 0
                                and maxPrice > 0
                                and price <= maxPrice
                                and stock > 0 then

                                if balance ~= nil and price > balance then
                                    insufficientFunds = true
                                else
                                    local lotId = lot.lotId or lot.id
                                    if lotId then
                                        attempted = attempted + 1
                                        pcall(function()
                                            Auctioneer.PurchaseLot:Fire(lotId, price)
                                        end)
                                    end
                                end
                            end
                        end
                    end

                    if maxPrice <= 0 then
                        setStatus("● AUCTION • SET MAX PRICE", false)
                    elseif #lots == 0 then
                        setStatus("● AUCTION ON • WAITING FOR LOTS", nil)
                    elseif matched == 0 then
                        setStatus("● AUCTION ON • NO TARGET LOT", nil)
                    elseif attempted > 0 then
                        setStatus("● AUCTION BUYING • " .. string.upper(AuctionCurrencyName), true)
                    elseif insufficientFunds then
                        setStatus("● AUCTION • NOT ENOUGH " .. string.upper(AuctionCurrencyName), false)
                    else
                        setStatus("● AUCTION ON • ABOVE MAX", nil)
                    end

                    task.wait(0.4)
                end
            end)

            if not ok and State.AuctionEnabled and myRunId == auctionRunId then
                warn("[ScoopHub] Auction worker error: " .. tostring(err))
                setStatus("● AUCTION ERROR", false)
            end
        end)
    end

    local function refreshControls()
        State.SelectedSeeds = filterAllowed(State.SelectedSeeds, AllSeeds)
        State.SelectedGears = filterAllowed(State.SelectedGears, AllGears)
        State.SelectedCrates = filterAllowed(State.SelectedCrates, AllCrates)
        State.AuctionSeeds = filterAllowed(State.AuctionSeeds, AuctionSeeds)
        State.AuctionGears = filterAllowed(State.AuctionGears, AuctionGears)
        State.AuctionCrates = filterAllowed(State.AuctionCrates, AuctionCrates)
        State.AuctionEggs = filterAllowed(State.AuctionEggs, AuctionEggs)
        State.AuctionSeedPacks = filterAllowed(State.AuctionSeedPacks, AuctionSeedPacks)

        SeedSelectControl.Refresh(); GearSelectControl.Refresh(); CrateSelectControl.Refresh()
        SeedSelectedToggle:Set(State.BuySelectedSeeds, false); SeedAllToggle:Set(State.BuyAllSeeds, false)
        GearSelectedToggle:Set(State.BuySelectedGears, false); GearAllToggle:Set(State.BuyAllGears, false)
        CrateSelectedToggle:Set(State.BuySelectedCrates, false); CrateAllToggle:Set(State.BuyAllCrates, false)
        for _, control in ipairs(AuctionControls) do if control.Refresh then control.Refresh() end end
        if AuctionMaxPriceBox then AuctionMaxPriceBox.Text = State.AuctionMaxPrice > 0 and tostring(State.AuctionMaxPrice) or "" end
        if AuctionToggle then AuctionToggle:Set(State.AuctionEnabled, false) end
    end

    _G.ScoopHubShopAPI = {
        Stop = function()
            State.BuySelectedSeeds, State.BuyAllSeeds = false, false
            State.BuySelectedGears, State.BuyAllGears = false, false
            State.BuySelectedCrates, State.BuyAllCrates = false, false
            State.AuctionEnabled = false
            if stopAuctionWorker then stopAuctionWorker() end
            SeedSelectedToggle:Set(false, false); SeedAllToggle:Set(false, false)
            GearSelectedToggle:Set(false, false); GearAllToggle:Set(false, false)
            CrateSelectedToggle:Set(false, false); CrateAllToggle:Set(false, false)
            if AuctionToggle then AuctionToggle:Set(false, false) end
            if Picker.Visible then Picker.Visible = false end
            restoreShopSounds()
            setStatus("● STOPPED", false)
        end,

        Refresh = function()
            refreshControls()
            if CurrentWorld.Supported then
                setStatus("● " .. CurrentWorld.Name:upper(), true)
            else
                setStatus("● UNSUPPORTED PLACE", false)
            end
        end,

        GetSettings = function()
            return {
                WorldKey = CurrentWorld.Key,
                SelectedSeeds = cloneList(State.SelectedSeeds),
                SelectedGears = cloneList(State.SelectedGears),
                SelectedCrates = cloneList(State.SelectedCrates),
                BuySelectedSeeds = State.BuySelectedSeeds,
                BuyAllSeeds = State.BuyAllSeeds,
                BuySelectedGears = State.BuySelectedGears,
                BuyAllGears = State.BuyAllGears,
                BuySelectedCrates = State.BuySelectedCrates,
                BuyAllCrates = State.BuyAllCrates,
                AuctionSeeds = cloneList(State.AuctionSeeds),
                AuctionGears = cloneList(State.AuctionGears),
                AuctionCrates = cloneList(State.AuctionCrates),
                AuctionEggs = cloneList(State.AuctionEggs),
                AuctionSeedPacks = cloneList(State.AuctionSeedPacks),
                AuctionMaxPrice = State.AuctionMaxPrice,
                AuctionEnabled = State.AuctionEnabled,
            }
        end,

        ApplySettings = function(data)
            if type(data) ~= "table" then return false end

            -- A named config may exist in both worlds. Never import a saved
            -- Fall shop catalog into Garden Valley or vice versa.
            if data.WorldKey ~= nil and tostring(data.WorldKey) ~= tostring(CurrentWorld.Key) then
                State.SelectedSeeds, State.SelectedGears, State.SelectedCrates = {}, {}, {}
                State.BuySelectedSeeds, State.BuyAllSeeds = false, false
                State.BuySelectedGears, State.BuyAllGears = false, false
                State.BuySelectedCrates, State.BuyAllCrates = false, false
                State.AuctionSeeds, State.AuctionGears, State.AuctionCrates = {}, {}, {}
                State.AuctionEggs, State.AuctionSeedPacks = {}, {}
                State.AuctionMaxPrice, State.AuctionEnabled = 0, false
                refreshControls()
                setStatus("● CONFIG WORLD MISMATCH", false)
                return false
            end

            State.SelectedSeeds = filterAllowed(data.SelectedSeeds or {}, AllSeeds)
            State.SelectedGears = filterAllowed(data.SelectedGears or {}, AllGears)
            State.SelectedCrates = filterAllowed(data.SelectedCrates or {}, AllCrates)
            State.BuySelectedSeeds = data.BuySelectedSeeds == true
            State.BuyAllSeeds = data.BuyAllSeeds == true
            State.BuySelectedGears = data.BuySelectedGears == true
            State.BuyAllGears = data.BuyAllGears == true
            State.BuySelectedCrates = data.BuySelectedCrates == true
            State.BuyAllCrates = data.BuyAllCrates == true

            State.AuctionSeeds = filterAllowed(data.AuctionSeeds or {}, AuctionSeeds)
            State.AuctionGears = filterAllowed(data.AuctionGears or {}, AuctionGears)
            State.AuctionCrates = filterAllowed(data.AuctionCrates or {}, AuctionCrates)
            State.AuctionEggs = filterAllowed(data.AuctionEggs or {}, AuctionEggs)
            State.AuctionSeedPacks = filterAllowed(data.AuctionSeedPacks or {}, AuctionSeedPacks)
            State.AuctionMaxPrice = math.max(0, tonumber(data.AuctionMaxPrice) or 0)
            State.AuctionEnabled = AuctionWorldEnabled and data.AuctionEnabled == true or false

            refreshControls()
            if State.AuctionEnabled then
                if startAuctionWorker then startAuctionWorker() end
            else
                if stopAuctionWorker then stopAuctionWorker() end
            end
            setStatus("● CONFIG APPLIED • " .. CurrentWorld.Name:upper(), true)
            return true
        end,
    }

    refreshControls()
    if State.AuctionEnabled and startAuctionWorker then
        startAuctionWorker()
    end
    _G.__ScoopHubSilentLog("[ScoopHub] Shop initialized for " .. tostring(CurrentWorld.Name) .. ".")
end

-- The Shop is an isolated feature. A Shop UI/networking incompatibility must
-- never prevent the core ScoopHub window (User, close, minimize, drag, etc.)
-- from finishing initialization.
local __shopInitOk, __shopInitErr = pcall(__ScoopHubInitShop)
if not __shopInitOk then
    warn("[ScoopHub] Shop init error: " .. tostring(__shopInitErr))

    -- Show the failure inside Shop instead of killing the entire GUI.
    pcall(function()
        for _, child in ipairs(Shop:GetChildren()) do
            child:Destroy()
        end

        local ErrorPanel = panel(
            Shop,
            UDim2.fromScale(0, 0),
            UDim2.fromScale(1, 1),
            "SHOP"
        )

        label(
            ErrorPanel,
            "Shop failed to initialize, but the main ScoopHub UI is still active.",
            UDim2.new(0, 12, 0, 34),
            UDim2.new(1, -24, 0, 34),
            10,
            T.White,
            T.Body
        ).TextWrapped = true

        local errLabel = label(
            ErrorPanel,
            tostring(__shopInitErr),
            UDim2.new(0, 12, 0, 76),
            UDim2.new(1, -24, 1, -88),
            9,
            T.Red,
            T.Body
        )
        errLabel.TextWrapped = true
        errLabel.TextYAlignment = Enum.TextYAlignment.Top
    end)
end


--==================================================
-- INVENTORY PAGE - SELECT / QTY / OWNED + MAIL-ELIGIBLE DROP
-- V63:
--   * Keeps the compact reference layout: checkbox | item + rarity/details | Qty | Owned/Value.
--   * DROP button is below the inventory list instead of beside Search.
--   * Mail eligibility is resolved directly from the same Mail category rules.
--   * Fixes disabled checkboxes/Qty fields caused by an empty Mail lookup.
--   * Multiple checked rows are queued and dropped sequentially.
--   * RequestDrop still uses the live Tool MainCategory whenever available so
--     Gear/SeedPack/Egg/etc. keep the game's own category identity.
--   * HarvestedFruit entries are shown as individual FRUITS rows with mutation, live/fallback value, and stock multiplier.
-- V68:
--   * Normalizes Plant/Plants to the server-facing Plants drop category.
--   * HarvestedFruit Configuration entries are selected through the game's own
--     InventoryController slot before RequestDrop, matching normal backpack holding.
--   * Keeps V7 held-item, count-confirmation, cooldown, retry, and cleanup logic.
-- V69 PERFORMANCE ONLY:
--   * Inventory refreshes are coalesced/event-driven instead of rescanning every 0.75s.
--   * Stack Count changes trigger a lightweight dirty refresh while Inventory is open.
--   * Hidden Inventory has no permanent polling loop; a 3s safety reconciler exists only
--     while the page is visible, then exits immediately when the page is hidden.
--   * Static Tool category/mail/rarity metadata is cached per live Tool instance.
-- V71:
--   * Pet rows keep stable FAV / UNFAV buttons while virtual rows are recycled during scrolling.
--   * HarvestedFruit rows now support FAV / UNFAV through Backpack.SetFruitFavorite(FruitId, boolean).
--   * Pet/fruit favorite attribute changes refresh the Inventory row state immediately.
-- V72:
--   * Recycled Inventory rows are hidden while their contents are rebound, then shown only
--     after every child control (including FAV/UNFAV) has the new row state. This prevents
--     the favorite button from briefly appearing on the neighboring row while scrolling.
-- V73:
--   * FAV / UNFAV is no longer a child of the recycled virtual row pool. Each favorite-capable
--     logical Inventory entry gets its own button anchored directly to its content-row position
--     inside the ScrollingFrame, so scrolling cannot transfer a button from one row to another.
--   * No Mail, Automation, Shop/Auction, Auto Buy Pet, Garden, Config, or Misc logic changed.
--==================================================
local function __ScoopHubInitInventoryDrop()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = LP
    local Backpack = LocalPlayer:WaitForChild("Backpack")

    local EQUIP_TIMEOUT = 1.00
    local EQUIP_SETTLE_DELAY = 0.12
    local FIRST_DROP_CONFIRM_TIMEOUT = 3.00
    local FOLLOWUP_CONFIRM_TIMEOUT = 0.50
    local FOLLOWUP_REQUEST_INTERVAL = 1.02
    local POST_CONFIRM_REQUEST_DELAY = 0.92
    local RETRY_DELAY = 0.20
    local COUNT_POLL_INTERVAL = 0.05
    local MAX_CONSECUTIVE_TIMEOUTS = 8

    local SharedModules = ReplicatedStorage:WaitForChild("SharedModules", 20)
    local NetworkingModule = SharedModules and SharedModules:WaitForChild("Networking", 20)
    local okNetworking, Networking = false, nil
    if NetworkingModule then
        okNetworking, Networking = pcall(require, NetworkingModule)
    end

    local RequestDrop = okNetworking and type(Networking) == "table"
        and Networking.DroppedItem
        and Networking.DroppedItem.RequestDrop
        or nil

    -- Mail owns the authoritative harvested-fruit value cache and stock
    -- multiplier watcher.  Access it through the explicit bridge instead of
    -- trying to reference Mail's private locals from this later function.
    local FruitInventoryAPI = _G.ScoopHubMailFruitInventoryAPI

    -- V71: one favorite runtime supports both Backpack favorite remotes.
    -- Pet:   SetPetFavorite(PetId, boolean)
    -- Fruit: SetFruitFavorite(FruitId, boolean)
    -- Keep the helpers in one table so this already-large Inventory function does
    -- not gain a collection of long-lived locals.
    local FavoriteRuntime = {
        Remotes = {
            Pet = okNetworking and type(Networking) == "table"
                and Networking.Backpack
                and Networking.Backpack.SetPetFavorite
                or nil,
            Fruit = okNetworking and type(Networking) == "table"
                and Networking.Backpack
                and Networking.Backpack.SetFruitFavorite
                or nil,
        },
        Busy = {},
    }

    function FavoriteRuntime.IsFavorite(instance)
        return instance ~= nil
            and (instance:GetAttribute("IsFavorite") == true
                or instance:GetAttribute("Favorite") == true)
    end

    function FavoriteRuntime.AddEntry(row, kind, id, instance)
        if not row or (kind ~= "Pet" and kind ~= "Fruit") then return end
        if id == nil or tostring(id) == "" then return end

        row.FavoriteKind = kind
        row.FavoriteEntries = row.FavoriteEntries or {}
        row.FavoriteTotal = (tonumber(row.FavoriteTotal) or 0) + 1

        local isFavorite = FavoriteRuntime.IsFavorite(instance)
        if isFavorite then
            row.FavoriteCount = (tonumber(row.FavoriteCount) or 0) + 1
        end

        row.FavoriteEntries[#row.FavoriteEntries + 1] = {
            Kind = kind,
            Id = tostring(id),
            Instance = instance,
            Favorite = isFavorite,
        }
    end

    function FavoriteRuntime.AddPet(row, tool)
        FavoriteRuntime.AddEntry(row, "Pet", tool and tool:GetAttribute("PetId"), tool)
    end

    function FavoriteRuntime.AddFruit(row, instance, fruitId)
        FavoriteRuntime.AddEntry(row, "Fruit", fruitId, instance)
    end

    local function inventoryFormatFruitMultiplier(value)
        local fn = FruitInventoryAPI and FruitInventoryAPI.FormatFruitPriceMultiplier
        if type(fn) == "function" then
            local ok, result = pcall(fn, value)
            if ok and result ~= nil then
                return tostring(result)
            end
        end
        local number = tonumber(value) or 1
        local rounded = math.floor(number * 100 + 0.5) / 100
        return "x" .. string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
    end

    -- Match the Garden tab's value presentation exactly: compact amount only,
    -- with the "$ " prefix added by the row renderer (no "Value" label / no cent sign).
    local INVENTORY_FRUIT_VALUE_COLOR = Color3.fromRGB(255, 199, 74)

    local function inventoryFormatFruitValue(value)
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

    local function requestInventoryFruitValueRefresh()
        local fn = FruitInventoryAPI and FruitInventoryAPI.ScanBackpackFruitValues
        if type(fn) == "function" then
            pcall(fn, false)
        end
    end

    local running = false
    local runId = 0
    local activeDropCategory = nil
    local activeDropName = nil
    local activeDropItemKey = nil
    local activeDropDisplayName = nil
    local activeDropTarget = 0
    local activeDropConfirmed = 0
    local activeDropAttempts = 0
    local alive = true

    local State = {
        SearchText = "",
        CurrentTab = "All",
        LatestItems = {},
        VisibleItems = {},
        RowPool = {},
        LastSignature = nil,
        Selected = {},
        Quantities = {},
        QueueRunning = false,
        QueueRunId = 0,
    }

    -- V69: UI refresh state. Gameplay/drop confirmation never depends on this cache;
    -- getOwnedCount() still reads Backpack + Character directly for every drop check.
    local InventoryRefreshDirty = true
    local InventoryRefreshScheduled = false
    local InventoryRefreshResetScroll = false
    local InventoryReconcileGeneration = 0
    local InventoryCountWatchers = setmetatable({}, { __mode = "k" })

    RegisterScoopHubCleanup(function()
        alive = false
    end)

    local function trim(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- Inventory mirrors the Mail page's mailable-item rules, but it must be
    -- self-contained.  The Mail resolver tables are locals inside
    -- __ScoopHubInitMail(), so referencing them from this later Inventory scope
    -- produced errors such as "attempt to index nil with 'Pets'".  V61 builds
    -- its own read-only category lookup from the same ReplicatedStorage assets.
    local INVENTORY_MAILABLE_CATEGORIES = {
        Seeds = true,
        WateringCans = true,
        SeedPacks = true,
        Sprinklers = true,
        Trowels = true,
        Crates = true,
        Mushrooms = true,
        Tools = true,
        Eggs = true,
        Plants = true,
        Pets = true,
        HarvestedFruits = true,
    }

    local INVENTORY_ASSET_FOLDER_TO_MAIL_CATEGORY = {
        Pets = "Pets",
        Crates = "Crates",
        WateringCans = "WateringCans",
        Sprinklers = "Sprinklers",
        Seeds = "Seeds",
        SeedPacks = "SeedPacks",
        Props = "Tools",
        Eggs = "Eggs",
    }

    local InventoryAssetItems = {}
    local InventoryAssetCategorySets = {}
    local InventoryPetNames = {}

    local function registerInventoryAsset(asset, mailCategory)
        if not asset or not mailCategory then
            return
        end

        local assetName = tostring(asset.Name or "")
        if assetName == "" then
            return
        end

        local set = InventoryAssetCategorySets[assetName]
        if not set then
            set = {}
            InventoryAssetCategorySets[assetName] = set
        end
        set[mailCategory] = true

        -- Match the Mail page's collision preference: a known Seeds identity
        -- wins over SeedPacks when the same display name exists in both folders.
        if InventoryAssetItems[assetName] == nil
            or mailCategory == "Seeds"
            or (InventoryAssetItems[assetName] ~= "Seeds" and mailCategory ~= "SeedPacks") then
            InventoryAssetItems[assetName] = mailCategory
        end

        if mailCategory == "Pets" then
            InventoryPetNames[assetName] = true
        end
    end

    local function loadInventoryAssetCategories()
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        if not assets then
            return
        end

        for folderName, mailCategory in pairs(INVENTORY_ASSET_FOLDER_TO_MAIL_CATEGORY) do
            local folder = assets:FindFirstChild(folderName)
            if folder then
                for _, asset in ipairs(folder:GetChildren()) do
                    registerInventoryAsset(asset, mailCategory)
                end

                -- Keep newly-added runtime assets eligible without re-executing.
                TrackConnection(folder.ChildAdded:Connect(function(asset)
                    registerInventoryAsset(asset, mailCategory)
                end))
            end
        end
    end

    loadInventoryAssetCategories()

    local function stripInventorySizePrefix(name)
        local result = trim(name)
        result = result:gsub("^[Bb]ig%s+", "")
        result = result:gsub("^[Hh]uge%s+", "")
        return trim(result)
    end

    local function normalizeMailCategoryFromMainCategory(rawCategory)
        local lower = string.lower(trim(rawCategory))
        if lower == "seed" or lower == "seeds" then
            return "Seeds"
        elseif lower == "wateringcan" or lower == "wateringcans"
            or lower:find("watering", 1, true) then
            return "WateringCans"
        elseif lower == "seedpack" or lower == "seedpacks" then
            return "SeedPacks"
        elseif lower == "sprinkler" or lower == "sprinklers" then
            return "Sprinklers"
        elseif lower == "trowel" or lower == "trowels" then
            return "Trowels"
        elseif lower == "crate" or lower == "crates" then
            return "Crates"
        elseif lower == "mushroom" or lower == "mushrooms" then
            return "Mushrooms"
        elseif lower == "gear" or lower == "gears"
            or lower == "tool" or lower == "tools"
            or lower == "prop" or lower == "props" then
            return "Tools"
        elseif lower == "egg" or lower == "eggs" then
            return "Eggs"
        elseif lower == "plant" or lower == "plants" then
            return "Plants"
        elseif lower == "pet" or lower == "pets" then
            return "Pets"
        elseif lower == "harvestedfruit" or lower == "harvestedfruits" then
            return "HarvestedFruits"
        end
        return nil
    end

    local function getReplicatedMailCategory(name)
        local direct = InventoryAssetItems[name]
        if direct and INVENTORY_MAILABLE_CATEGORIES[direct] then
            return direct
        end

        local baseName = stripInventorySizePrefix(name)
        local base = InventoryAssetItems[baseName]
        if base and INVENTORY_MAILABLE_CATEGORIES[base] then
            return base
        end

        return nil
    end

    local function resolveMailEntry(tool)
        if not tool or not tool:IsA("Tool") then
            return nil
        end

        local name = tostring(tool.Name or "")
        if name == "" then
            return nil
        end

        local lowerName = string.lower(name)
        local baseName = stripInventorySizePrefix(name)
        local rawCategory = trim(tool:GetAttribute("MainCategory"))
        local categoryLower = string.lower(rawCategory)
        local mainMailCategory = normalizeMailCategoryFromMainCategory(rawCategory)
        local hasPetId = tool:GetAttribute("PetId") ~= nil
        local hasPetMarker = tool:GetAttribute("Pet") ~= nil
        local isPet = hasPetId
            or hasPetMarker
            or InventoryPetNames[name] == true
            or InventoryPetNames[baseName] == true
            or mainMailCategory == "Pets"

        -- Mail Fruits uses unique IDs. Keep it eligible when the live Tool exposes
        -- the same harvested-fruit identity markers.
        local isHarvestedFruit = tool:GetAttribute("HarvestedFruit") == true
            or mainMailCategory == "HarvestedFruits"
        if isHarvestedFruit then
            local fruitId = tool:GetAttribute("Id") or tool:GetAttribute("FruitId")
            if fruitId ~= nil and tostring(fruitId) ~= "" then
                return {
                    Name = name,
                    Category = "HarvestedFruits",
                    ItemKey = tostring(fruitId),
                    IsFruit = true,
                }
            end
        end

        local replicatedCategory = getReplicatedMailCategory(name)
        local explicitSeedPack = mainMailCategory == "SeedPacks"
            or categoryLower == "seedpack"
            or categoryLower == "seedpacks"
            or lowerName:find("pack", 1, true) ~= nil
        local replicatedCategories = InventoryAssetCategorySets[name]
            or InventoryAssetCategorySets[baseName]
        local assetIsSeed = replicatedCategories and replicatedCategories.Seeds == true
        local isSeedItem = mainMailCategory == "Seeds"
            or categoryLower == "seed"
            or categoryLower == "seeds"
            or (lowerName:find("seed", 1, true) ~= nil and not explicitSeedPack)
            or (assetIsSeed and not explicitSeedPack)

        local mailCategory = nil

        if isPet then
            mailCategory = "Pets"
        elseif explicitSeedPack then
            mailCategory = "SeedPacks"
        elseif isSeedItem then
            mailCategory = "Seeds"
        elseif mainMailCategory and INVENTORY_MAILABLE_CATEGORIES[mainMailCategory] then
            mailCategory = mainMailCategory
        elseif replicatedCategory and INVENTORY_MAILABLE_CATEGORIES[replicatedCategory] then
            mailCategory = replicatedCategory
        elseif lowerName:find("trowel", 1, true) then
            mailCategory = "Trowels"
        elseif lowerName:find("sprinkler", 1, true) then
            mailCategory = "Sprinklers"
        elseif lowerName:find("watering", 1, true)
            or categoryLower:find("watering", 1, true) then
            mailCategory = "WateringCans"
        elseif lowerName:find("crate", 1, true) then
            mailCategory = "Crates"
        elseif lowerName:find("mushroom", 1, true) then
            mailCategory = "Mushrooms"
        elseif lowerName:find("egg", 1, true)
            or categoryLower == "egg"
            or categoryLower == "eggs" then
            mailCategory = "Eggs"
        elseif categoryLower == "gear"
            or categoryLower == "gears"
            or categoryLower == "tool"
            or categoryLower == "tools"
            or categoryLower == "prop"
            or categoryLower == "props"
            or lowerName:find("pot", 1, true)
            or lowerName:find("sign", 1, true)
            or lowerName:find("gnome", 1, true)
            or lowerName:find("teleporter", 1, true)
            or lowerName:find("flashbang", 1, true) then
            mailCategory = "Tools"
        end

        -- World Gear catalog fallback for ordinary tools that expose neither
        -- MainCategory nor a matching ReplicatedStorage asset.
        if not mailCategory then
            local worldData = _G.ScoopHubWorldData
            local current = worldData and worldData.Current
            for _, gearName in ipairs(current and current.Gears or {}) do
                if tostring(gearName) == name then
                    mailCategory = "Tools"
                    break
                end
            end
        end

        if not mailCategory or not INVENTORY_MAILABLE_CATEGORIES[mailCategory] then
            return nil
        end

        local itemKey = name
        if isPet then
            local petId = tool:GetAttribute("PetId")
            if petId ~= nil and tostring(petId) ~= "" then
                itemKey = tostring(petId)
            end
        end

        return {
            Name = name,
            Category = mailCategory,
            ItemKey = itemKey,
            IsPet = isPet,
        }
    end

    local function normalizeDropCategory(value)
        local lower = string.lower(trim(value))
        if lower == 'seed' or lower == 'seeds' then
            return 'Seeds'
        elseif lower == 'crate' or lower == 'crates' then
            return 'Crates'
        elseif lower == 'wateringcan'
            or lower == 'wateringcans'
            or lower:find('watering', 1, true) then
            return 'WateringCans'
        elseif lower == 'seedpack' or lower == 'seedpacks' then
            return 'SeedPacks'
        elseif lower == 'pet' or lower == 'pets' then
            return 'Pets'
        elseif lower == 'plant' or lower == 'plants' then
            return 'Plants'
        elseif lower == 'harvestedfruit' or lower == 'harvestedfruits' then
            return 'HarvestedFruits'
        elseif lower == 'egg' or lower == 'eggs' then
            return 'Eggs'
        elseif lower == 'gear' or lower == 'gears'
            or lower == 'tool' or lower == 'tools'
            or lower == 'prop' or lower == 'props' then
            return 'Gear'
        end
        return trim(value)
    end

    local seedLookup = {}
    do
        local worldData = _G.ScoopHubWorldData
        local current = worldData and worldData.Current
        for _, name in ipairs(current and current.Seeds or {}) do
            seedLookup[tostring(name)] = true
        end
    end

    local function rawDropCategoryForTool(tool)
        if not tool or not tool:IsA('Tool') then
            return nil
        end

        -- Harvested fruits can share the exact same visible name as their seed
        -- (for example Maple Bamboo).  They must be identified before the seed
        -- name lookup so RequestDrop receives HarvestedFruits + the unique fruit Id.
        if tool:GetAttribute('HarvestedFruit') == true then
            return 'HarvestedFruits'
        end

        local name = tostring(tool.Name)
        local lowerName = string.lower(name)

        if lowerName:find('crate', 1, true) then
            return 'Crates'
        elseif lowerName:find('watering', 1, true) then
            return 'WateringCans'
        elseif seedLookup[name] then
            return 'Seeds'
        end

        local rawCategory = trim(tool:GetAttribute('MainCategory'))
        if rawCategory ~= '' then
            return normalizeDropCategory(rawCategory)
        end

        return nil
    end

    local function inferDropCategory(tool, mailEntry)
        local liveCategory = rawDropCategoryForTool(tool)
        if liveCategory and liveCategory ~= '' then
            return liveCategory
        end

        local mailCategory = mailEntry and trim(mailEntry.Category) or ''
        if mailCategory == '' then
            return nil
        end

        if mailCategory == 'Tools'
            or mailCategory == 'Trowels'
            or mailCategory == 'Sprinklers'
            or mailCategory == 'Mushrooms' then
            return 'Gear'
        end

        return normalizeDropCategory(mailCategory)
    end

    local function getRequestDropItemKey(heldTool, category, itemName, itemKey)
        if itemKey ~= nil and tostring(itemKey) ~= ''
            and (category == 'HarvestedFruits' or category == 'Pets') then
            return tostring(itemKey)
        end

        if heldTool and category == 'Pets' then
            local petId = heldTool:GetAttribute('PetId')
            if petId ~= nil and tostring(petId) ~= '' then
                return tostring(petId)
            end
        elseif heldTool and category == 'HarvestedFruits' then
            local fruitId = heldTool:GetAttribute('Id') or heldTool:GetAttribute('FruitId')
            if fruitId ~= nil and tostring(fruitId) ~= '' then
                return tostring(fruitId)
            end
        end
        return tostring(itemName)
    end

    local INVENTORY_RARITY_COLORS = {
        Common = Color3.fromRGB(220, 220, 220),
        Uncommon = Color3.fromRGB(91, 235, 120),
        Rare = Color3.fromRGB(82, 184, 255),
        Legendary = Color3.fromRGB(255, 211, 75),
        Mythic = Color3.fromRGB(255, 83, 99),
        Divine = Color3.fromRGB(255, 145, 72),
        Prismatic = Color3.fromRGB(196, 113, 255),
        Super = Color3.fromRGB(196, 113, 255),
        Secret = Color3.fromRGB(255, 255, 255),
        Unknown = T.Muted,
    }

    local function normalizeInventoryRarity(value)
        local text = trim(value)
        if text == "" then
            return nil
        end
        local lower = string.lower(text)
        for _, rarity in ipairs({
            "Common", "Uncommon", "Rare", "Legendary", "Mythic",
            "Divine", "Prismatic", "Super", "Secret"
        }) do
            if lower == string.lower(rarity) then
                return rarity
            end
        end
        return nil
    end

    local function readInventoryRarity(instance)
        if not instance then
            return nil
        end

        for _, attributeName in ipairs({
            "Rarity", "ItemRarity", "SeedRarity", "GearRarity", "Tier"
        }) do
            local rarity = normalizeInventoryRarity(instance:GetAttribute(attributeName))
            if rarity then
                return rarity
            end
        end

        for _, valueName in ipairs({ "Rarity", "ItemRarity", "Tier" }) do
            local valueObject = instance:FindFirstChild(valueName)
            if valueObject and valueObject:IsA("StringValue") then
                local rarity = normalizeInventoryRarity(valueObject.Value)
                if rarity then
                    return rarity
                end
            end
        end

        return nil
    end

    local function inferInventoryRarity(tool)
        local rarity = readInventoryRarity(tool)
        if rarity then
            return rarity
        end

        local assets = ReplicatedStorage:FindFirstChild("Assets")
        if assets then
            local itemName = tostring(tool and tool.Name or "")
            for _, folderName in ipairs({
                "Seeds", "Props", "Crates", "WateringCans", "Sprinklers",
                "SeedPacks", "Eggs", "Pets"
            }) do
                local folder = assets:FindFirstChild(folderName)
                local asset = folder and folder:FindFirstChild(itemName)
                rarity = readInventoryRarity(asset)
                if rarity then
                    return rarity
                end
            end
        end

        local lowerName = string.lower(tostring(tool and tool.Name or ""))
        for _, candidate in ipairs({
            "Secret", "Prismatic", "Divine", "Super", "Mythic",
            "Legendary", "Uncommon", "Rare", "Common"
        }) do
            if lowerName:find(string.lower(candidate), 1, true) then
                return candidate
            end
        end

        return "Unknown"
    end

    local function getDisplayCategory(tool)
        if not tool then
            return "Other"
        end

        if tool:GetAttribute("HarvestedFruit") == true then
            return "Fruits"
        end

        if not tool:IsA("Tool") then
            return "Other"
        end

        local raw = trim(tool:GetAttribute("MainCategory"))
        if raw ~= "" then
            local normalized = normalizeDropCategory(raw)
            if normalized == "WateringCans" then
                return "Watering Cans"
            end
            return normalized ~= "" and normalized or raw
        end

        local mailEntry = resolveMailEntry(tool)
        local dropCategory = mailEntry and inferDropCategory(tool, mailEntry) or nil
        if dropCategory == "WateringCans" then
            return "Watering Cans"
        elseif dropCategory then
            return dropCategory
        end

        return "Other"
    end

    -- V69: Category/mail/rarity data is static for the lifetime of almost every Tool.
    -- Cache it per instance so a safety refresh does not repeatedly walk replicated
    -- asset folders and Mail classification rules for the same stack.
    local InventoryToolMetadataCache = setmetatable({}, { __mode = "k" })

    local function getInventoryToolMetadata(tool)
        if not tool or not tool:IsA("Tool") then
            return nil
        end

        local signature = table.concat({
            tostring(tool.Name),
            tostring(tool:GetAttribute("MainCategory")),
            tostring(tool:GetAttribute("PetId")),
            tostring(tool:GetAttribute("Pet")),
            tostring(tool:GetAttribute("SeedTool")),
            tostring(tool:GetAttribute("Crate")),
            tostring(tool:GetAttribute("SeedPack")),
            tostring(tool:GetAttribute("Egg")),
            tostring(tool:GetAttribute("Sprinkler")),
            tostring(tool:GetAttribute("WateringCan")),
            tostring(tool:GetAttribute("Trowel")),
            tostring(tool:GetAttribute("Plant")),
        }, "\31")

        local cached = InventoryToolMetadataCache[tool]
        if cached and cached.Signature == signature then
            return cached
        end

        local displayCategory = getDisplayCategory(tool)
        local mailEntry = resolveMailEntry(tool)
        local canMail = mailEntry ~= nil
        local dropCategory = canMail and inferDropCategory(tool, mailEntry) or nil

        cached = {
            Signature = signature,
            DisplayCategory = displayCategory,
            MailEntry = mailEntry,
            CanMail = canMail,
            DropCategory = dropCategory,
            Rarity = inferInventoryRarity(tool),
        }
        InventoryToolMetadataCache[tool] = cached
        return cached
    end

    local function itemMatches(tool, category, itemName, itemKey)
        if not tool then
            return false
        end

        -- Harvested fruits are commonly Configuration instances in Backpack, not
        -- Roblox Tools. Match them by the same unique Id used by Mail Fruits.
        if category == "HarvestedFruits" then
            if tool:GetAttribute("HarvestedFruit") ~= true then
                return false
            end

            if itemKey ~= nil and tostring(itemKey) ~= "" then
                local fruitId = tool:GetAttribute("Id") or tool:GetAttribute("FruitId")
                return fruitId ~= nil and tostring(fruitId) == tostring(itemKey)
            end

            return tostring(tool.Name) == tostring(itemName)
        end

        if not tool:IsA("Tool") then
            return false
        end

        if tostring(tool.Name) ~= tostring(itemName) then
            return false
        end

        -- Unique-ID pet rows can also be narrowed when a concrete PetId is supplied.
        if category == "Pets" then
            local entry = resolveMailEntry(tool)
            if not entry or entry.Category ~= "Pets" then
                return false
            end
            if itemKey ~= nil and tostring(itemKey) ~= "" then
                local petId = tool:GetAttribute("PetId")
                return petId ~= nil and tostring(petId) == tostring(itemKey)
            end
            return true
        end

        local liveCategory = rawDropCategoryForTool(tool)
        if liveCategory and liveCategory ~= "" then
            return liveCategory == category
        end

        -- Some mailable Tools do not expose MainCategory. At that point the exact
        -- Tool name is still the strongest identity we have, and the row's category
        -- came from the existing Mail resolver.
        return trim(category) ~= ""
    end

    local function getStackCount(tool)
        if not tool then
            return 0
        end

        local count = tonumber(tool:GetAttribute("Count"))
        if count == nil then
            count = 1
        elseif count <= 0 and (tool:GetAttribute("PetId") ~= nil or tool:GetAttribute("Pet") ~= nil) then
            -- Mail treats owned pets as unique x1 items even when Count is 0.
            count = 1
        end

        return math.max(0, count)
    end

    local function getOwnedCount(category, itemName, itemKey)
        local total = 0
        local seen = {}

        local function scan(container)
            if not container then
                return
            end

            for _, tool in ipairs(container:GetChildren()) do
                if not seen[tool] and itemMatches(tool, category, itemName, itemKey) then
                    seen[tool] = true
                    total += getStackCount(tool)
                end
            end
        end

        scan(Backpack)
        scan(LocalPlayer.Character)
        return total
    end

    local function getFruitInventoryDetails(item)
        local fruitId = item:GetAttribute("Id") or item:GetAttribute("FruitId")
        local fruitName = item:GetAttribute("FruitName") or tostring(item.Name)
        local mutation = item:GetAttribute("Mutation")
            or item:GetAttribute("MutationName")
            or item:GetAttribute("Mutations")
            or item:GetAttribute("Variant")
            or item:GetAttribute("FruitMutation")
        local weight = tonumber(item:GetAttribute("Weight")) or 0

        local valueCache = FruitInventoryAPI and FruitInventoryAPI.FruitValueCache
        local multiplierTable = FruitInventoryAPI and FruitInventoryAPI.FruitPriceStockMultipliers
        local cached = fruitId and valueCache and valueCache[tostring(fruitId)]
        local value = cached and cached.Value or nil

        if value == nil then
            local calculate = FruitInventoryAPI and FruitInventoryAPI.CalculateFruitValue
            if type(calculate) == "function" then
                local ok, result = pcall(calculate, fruitName, weight, item, mutation)
                if ok then
                    value = result
                end
            end
        end

        local multiplier = multiplierTable and multiplierTable[fruitName] or 1

        return {
            Id = fruitId and tostring(fruitId) or nil,
            FruitName = tostring(fruitName),
            Mutation = tostring(mutation or "Normal"),
            Weight = weight,
            Value = math.floor(tonumber(value) or 0),
            Multiplier = tonumber(multiplier) or 1,
        }
    end

    local function collectInventory()
        local grouped = {}
        local seen = {}

        local function scan(container, held)
            if not container then
                return
            end

            for _, tool in ipairs(container:GetChildren()) do
                local isHarvestedFruit = tool:GetAttribute("HarvestedFruit") == true
                if (tool:IsA("Tool") or isHarvestedFruit) and not seen[tool] then
                    seen[tool] = true

                    if isHarvestedFruit then
                        local fruit = getFruitInventoryDetails(tool)
                        local rawName = tostring(tool.Name)

                        -- Mail Fruits itself treats HarvestedFruit + Id as the
                        -- authoritative identity. These entries are usually
                        -- Configuration instances, so do not require IsA("Tool").
                        local canMail = fruit.Id ~= nil and tostring(fruit.Id) ~= ""
                        local dropCategory = canMail and "HarvestedFruits" or nil
                        local uniqueToken = fruit.Id or (rawName .. "@" .. tostring(tool))
                        local key = "fruit\31" .. string.lower(tostring(uniqueToken))

                        local fruitRow = {
                            Key = key,
                            Name = rawName,
                            DisplayName = fruit.FruitName ~= "Unknown" and fruit.FruitName or rawName,
                            Category = "Fruits",
                            Rarity = "Unknown",
                            MailCategory = "HarvestedFruits",
                            Mailable = canMail,
                            DropCategory = dropCategory,
                            Droppable = canMail and dropCategory ~= nil,
                            Count = 1,
                            BackpackCount = held and 0 or 1,
                            HeldCount = held and 1 or 0,
                            Instances = 1,
                            IsFruit = true,
                            ItemKey = fruit.Id,
                            Mutation = fruit.Mutation,
                            Weight = fruit.Weight,
                            Value = fruit.Value,
                            Multiplier = fruit.Multiplier,
                        }
                        grouped[key] = fruitRow
                        FavoriteRuntime.AddFruit(fruitRow, tool, fruit.Id)
                    elseif tool:IsA("Tool") then
                        local count = getStackCount(tool)
                        if count > 0 then
                            local name = tostring(tool.Name)
                            local meta = getInventoryToolMetadata(tool)
                            local displayCategory = meta and meta.DisplayCategory or getDisplayCategory(tool)
                            local mailEntry = meta and meta.MailEntry or resolveMailEntry(tool)
                            local canMail = meta and meta.CanMail or (mailEntry ~= nil)
                            local dropCategory = meta and meta.DropCategory
                                or (canMail and inferDropCategory(tool, mailEntry) or nil)
                            local key = string.lower(displayCategory)
                                .. "\31"
                                .. string.lower(name)

                            local row = grouped[key]
                            if not row then
                                row = {
                                    Key = key,
                                    Name = name,
                                    DisplayName = name,
                                    Category = displayCategory,
                                    Rarity = meta and meta.Rarity or inferInventoryRarity(tool),
                                    MailCategory = mailEntry and mailEntry.Category or nil,
                                    Mailable = canMail,
                                    DropCategory = dropCategory,
                                    Droppable = canMail and dropCategory ~= nil,
                                    Count = 0,
                                    BackpackCount = 0,
                                    HeldCount = 0,
                                    Instances = 0,
                                    IsFruit = false,
                                    ItemKey = nil,
                                }
                                grouped[key] = row
                            end

                            row.Count += count
                            row.Instances += 1
                            FavoriteRuntime.AddPet(row, tool)
                            if held then
                                row.HeldCount += count
                            else
                                row.BackpackCount += count
                            end

                            if canMail then
                                row.Mailable = true
                                row.MailCategory = row.MailCategory or (mailEntry and mailEntry.Category)
                            end
                            if not row.DropCategory and dropCategory then
                                row.DropCategory = dropCategory
                            end
                            row.Droppable = row.Mailable == true and row.DropCategory ~= nil
                        end
                    end
                end
            end
        end

        scan(Backpack, false)
        scan(LocalPlayer.Character, true)

        local rows = {}
        for _, row in pairs(grouped) do
            rows[#rows + 1] = row
        end

        table.sort(rows, function(a, b)
            if a.IsFruit ~= b.IsFruit then
                return not a.IsFruit
            end
            if a.IsFruit and b.IsFruit and a.Value ~= b.Value then
                return a.Value > b.Value
            end
            local an = string.lower(a.DisplayName or a.Name)
            local bn = string.lower(b.DisplayName or b.Name)
            if an == bn then
                return string.lower(a.Category) < string.lower(b.Category)
            end
            return an < bn
        end)

        return rows
    end

    local function inventorySignature(rows)
        local parts = {}
        for _, row in ipairs(rows) do
            parts[#parts + 1] = table.concat({
                row.Name,
                tostring(row.DisplayName),
                row.Category,
                tostring(row.Rarity),
                tostring(row.Count),
                tostring(row.BackpackCount),
                tostring(row.HeldCount),
                tostring(row.Mailable),
                tostring(row.MailCategory),
                tostring(row.DropCategory),
                tostring(row.Droppable),
                tostring(row.IsFruit),
                tostring(row.ItemKey),
                tostring(row.Mutation),
                tostring(row.Weight),
                tostring(row.Value),
                tostring(row.Multiplier),
                tostring(row.FavoriteKind),
                tostring(row.FavoriteCount),
                tostring(row.FavoriteTotal),
            }, "|")
        end
        return table.concat(parts, "\30")
    end

    local function findHeldMatchingTool(category, itemName, itemKey)
        local character = LocalPlayer.Character
        if not character then
            return nil
        end

        for _, tool in ipairs(character:GetChildren()) do
            if itemMatches(tool, category, itemName, itemKey)
                and getStackCount(tool) > 0 then
                return tool
            end
        end

        return nil
    end

    local function findBackpackMatchingTool(category, itemName, itemKey)
        local best = nil
        local bestCount = -1

        for _, tool in ipairs(Backpack:GetChildren()) do
            if itemMatches(tool, category, itemName, itemKey) then
                local count = getStackCount(tool)
                if count > bestCount then
                    best = tool
                    bestCount = count
                end
            end
        end

        return best
    end

    local function getHumanoid()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        return character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 5)
    end

    -- Harvested fruits are Configuration instances, but the game's own
    -- InventoryController still treats them as selectable/equippable inventory
    -- entries. Keep the bridge in one table so this large function does not burn
    -- extra Luau registers for every helper closure.
    local FruitHold = {}

    function FruitHold.CollectUpvalues(fn)
        local groups = {}

        if type(getupvalues) == "function" then
            local ok, values = pcall(getupvalues, fn)
            if ok and type(values) == "table" then
                groups[#groups + 1] = values
            end
        end

        if debug and type(debug.getupvalues) == "function" then
            local ok, values = pcall(debug.getupvalues, fn)
            if ok and type(values) == "table" then
                groups[#groups + 1] = values
            end
        end

        return groups
    end

    function FruitHold.Id(instance)
        if not instance or typeof(instance) ~= "Instance" then
            return nil
        end
        if instance:GetAttribute("HarvestedFruit") ~= true then
            return nil
        end
        local id = instance:GetAttribute("Id") or instance:GetAttribute("FruitId")
        if id == nil or tostring(id) == "" then
            return nil
        end
        return tostring(id)
    end

    function FruitHold.FindInstance(itemKey)
        local wanted = tostring(itemKey or "")
        if wanted == "" then
            return nil
        end

        local containers = { Backpack, LocalPlayer.Character }
        for _, container in ipairs(containers) do
            if container then
                for _, instance in ipairs(container:GetChildren()) do
                    if FruitHold.Id(instance) == wanted then
                        return instance
                    end
                end
            end
        end
        return nil
    end

    function FruitHold.FindBinding(itemKey)
        if type(getconnections) ~= "function" then
            return nil, nil, nil, nil, nil,
                "getconnections is unavailable; cannot use InventoryController fruit selection."
        end

        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        local backpackGui = playerGui and playerGui:FindFirstChild("BackpackGui")
        if not backpackGui then
            return nil, nil, nil, nil, nil, "BackpackGui not found."
        end

        local wanted = tostring(itemKey or "")
        for _, slot in ipairs(backpackGui:GetDescendants()) do
            if slot:IsA("GuiButton") then
                local okConnections, connections = pcall(getconnections, slot.MouseButton1Click)
                if okConnections and type(connections) == "table" then
                    for _, connection in ipairs(connections) do
                        local fn
                        pcall(function()
                            fn = connection.Function
                        end)

                        if type(fn) == "function" then
                            for _, values in ipairs(FruitHold.CollectUpvalues(fn)) do
                                for _, value in pairs(values) do
                                    if type(value) == "table" then
                                        local frame = rawget(value, "Frame")
                                        local inventoryObject = rawget(value, "Tool")
                                        if frame == slot
                                            and typeof(inventoryObject) == "Instance"
                                            and FruitHold.Id(inventoryObject) == wanted then
                                            return value, slot, inventoryObject, connection, fn, nil
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return nil, nil, FruitHold.FindInstance(itemKey), nil, nil,
            "Exact harvested-fruit InventoryController slot was not found."
    end

    function FruitHold.BindingIsEquipped(binding, inventoryObject)
        if inventoryObject and inventoryObject.Parent == LocalPlayer.Character then
            return true
        end

        local isEquipped = binding and rawget(binding, "IsEquipped")
        if type(isEquipped) == "function" then
            local ok, result = pcall(isEquipped)
            if ok and result == true then
                return true
            end
            ok, result = pcall(isEquipped, binding)
            if ok and result == true then
                return true
            end
        end

        return false
    end

    function FruitHold.Activate(binding, slot, connection, fn)
        -- Prefer the actual GUI signal/callback. This is closest to a normal
        -- backpack click and lets InventoryController perform every side effect.
        if type(firesignal) == "function" and slot then
            local ok = pcall(firesignal, slot.MouseButton1Click)
            if ok then
                return true
            end
        end

        if connection then
            local ok = pcall(function()
                if type(connection.Fire) == "function" then
                    connection:Fire()
                else
                    error("connection.Fire unavailable")
                end
            end)
            if ok then
                return true
            end
        end

        if type(fn) == "function" then
            local ok = pcall(fn)
            if ok then
                return true
            end
        end

        local selectFn = binding and rawget(binding, "Select")
        if type(selectFn) == "function" then
            local ok = pcall(selectFn)
            if ok then
                return true
            end
            ok = pcall(selectFn, binding)
            if ok then
                return true
            end
        end

        return false
    end

    function FruitHold.IsHeld(itemKey)
        local binding, slot, inventoryObject, connection, fn = FruitHold.FindBinding(itemKey)

        if FruitHold.BindingIsEquipped(binding, inventoryObject) then
            return true, binding, slot, inventoryObject, connection, fn
        end

        local exact = FruitHold.FindInstance(itemKey)
        if exact and exact.Parent == LocalPlayer.Character then
            return true, binding, slot, exact, connection, fn
        end

        return false, binding, slot, inventoryObject or exact, connection, fn
    end

    function FruitHold.Ensure(itemKey)
        local held, binding, slot, inventoryObject, connection, fn = FruitHold.IsHeld(itemKey)
        if held then
            task.wait(EQUIP_SETTLE_DELAY)
            return binding or inventoryObject or true
        end

        if not binding or not slot then
            local _, _, _, _, _, reason = FruitHold.FindBinding(itemKey)
            return nil, reason or "Harvested-fruit slot binding not found."
        end

        if not FruitHold.Activate(binding, slot, connection, fn) then
            return nil, "Could not activate harvested-fruit InventoryController slot."
        end

        local started = os.clock()
        while os.clock() - started < EQUIP_TIMEOUT do
            local nowHeld, newBinding, _, newObject = FruitHold.IsHeld(itemKey)
            if nowHeld then
                task.wait(EQUIP_SETTLE_DELAY)
                return newBinding or newObject or binding
            end
            task.wait(0.03)
        end

        return nil, "Harvested fruit was selected, but InventoryController did not report it held."
    end

    local function ensureItemHeld(category, itemName, itemKey)
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = getHumanoid()
        if not humanoid then
            return nil, "Humanoid not found"
        end

        local held = findHeldMatchingTool(category, itemName, itemKey)
        if held then
            return held
        end

        local candidate = findBackpackMatchingTool(category, itemName, itemKey)
        if not candidate then
            return nil, "Matching item not found in Backpack"
        end

        local equipped, equipError = pcall(function()
            humanoid:EquipTool(candidate)
        end)
        if not equipped then
            return nil, "EquipTool failed: " .. tostring(equipError)
        end

        local started = os.clock()
        while os.clock() - started < EQUIP_TIMEOUT do
            if candidate.Parent == character then
                task.wait(EQUIP_SETTLE_DELAY)
                if candidate.Parent == character
                    and itemMatches(candidate, category, itemName, itemKey) then
                    return candidate
                end
            end

            local replacement = findHeldMatchingTool(category, itemName, itemKey)
            if replacement then
                task.wait(EQUIP_SETTLE_DELAY)
                return replacement
            end

            task.wait(0.03)
        end

        return nil, "Item did not move into Character after EquipTool"
    end

    local function waitForInventoryDecrease(category, itemName, itemKey, previousCount, timeout, myRunId)
        local started = os.clock()

        while os.clock() - started < timeout do
            if myRunId ~= runId then
                return false, getOwnedCount(category, itemName, itemKey), os.clock() - started, true
            end

            local current = getOwnedCount(category, itemName, itemKey)
            if current < previousCount then
                return true, current, os.clock() - started, false
            end

            task.wait(COUNT_POLL_INTERVAL)
        end

        return false, getOwnedCount(category, itemName, itemKey), os.clock() - started, false
    end

    local function unholdSelectedItem(category, itemName, itemKey)
        if category == "HarvestedFruits" then
            local held, binding, slot, inventoryObject, connection, fn =
                FruitHold.IsHeld(itemKey)

            -- A successful drop removes the exact fruit, so there may be nothing
            -- left to deselect. If it still exists and is selected, click the same
            -- InventoryController slot again to mirror normal backpack unholding.
            if not held then
                return true
            end

            if not binding or not slot then
                return false
            end

            if not FruitHold.Activate(binding, slot, connection, fn) then
                return false
            end

            local started = os.clock()
            while os.clock() - started < 1.0 do
                local stillHeld = FruitHold.IsHeld(itemKey)
                if not stillHeld then
                    return true
                end
                task.wait(0.03)
            end

            return not FruitHold.IsHeld(itemKey)
        end

        local heldTool = findHeldMatchingTool(category, itemName, itemKey)
        if not heldTool then
            return true
        end

        local humanoid = getHumanoid()
        if not humanoid then
            return false
        end

        local ok = pcall(function()
            humanoid:UnequipTools()
        end)
        if not ok then
            return false
        end

        local started = os.clock()
        while os.clock() - started < 1.0 do
            if heldTool.Parent ~= LocalPlayer.Character then
                return true
            end
            task.wait(0.03)
        end

        return heldTool.Parent ~= LocalPlayer.Character
    end

    local function automationIsBusy()
        local api = _G.ScoopHubAutomationAPI
        if not api or type(api.GetSettings) ~= "function" then
            return false
        end

        local ok, settings = pcall(api.GetSettings)
        if not ok or type(settings) ~= "table" then
            return false
        end

        return settings.PlantEnabled == true
            or settings.HarvestEnabled == true
            or settings.SellEnabled == true
            or settings.TrowelEnabled == true
            or settings.PotEnabled == true
            or settings.MergeEnabled == true
    end

    -- ==============================================================
    -- GARDEN-STYLE PAGE UI
    -- ============================================================== 

    label(
        Inventory,
        "INVENTORY",
        UDim2.new(0, 4, 0, 2),
        UDim2.new(0.5, -4, 0, 16),
        12,
        T.Text,
        T.Font
    )

    local HeaderStatus = label(
        Inventory,
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
    }, Inventory), 6)
    S(TabHolder, T.Line, .30, 1)

    local InventoryTabButtons = {}

    local function createInventoryTabButton(textValue, key, index)
        local buttonWidth = 1 / 3
        local button = C(N("TextButton", {
            Name = "Inventory" .. key .. "Tab",
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

        InventoryTabButtons[key] = button
        return button
    end

    createInventoryTabButton("ALL", "All", 1)
    createInventoryTabButton("ITEMS", "Items", 2)
    createInventoryTabButton("FRUITS", "Fruits", 3)

    local Info = label(
        Inventory,
        "Open Inventory tab to scan backpack...",
        UDim2.new(0, 5, 0, 57),
        UDim2.new(1, -10, 0, 14),
        9,
        T.Muted,
        T.Body
    )
    Info.TextTruncate = Enum.TextTruncate.AtEnd

    local Search = C(N("TextBox", {
        Name = "InventorySearch",
        Position = UDim2.new(0, 4, 0, 75),
        Size = UDim2.new(.56, -6, 0, 30),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Search backpack items...",
        PlaceholderColor3 = T.White,
        TextColor3 = T.White,
        TextStrokeTransparency = 1,
        Font = T.Body,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    }, Inventory), 6)
    N("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, Search)

    local SearchStroke = N("UIStroke", {
        Color = T.Red,
        Thickness = 1.15,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, Search)

    TrackConnection(Search.Focused:Connect(function()
        tw(SearchStroke, {Transparency = 0}, .12)
    end))

    TrackConnection(Search.FocusLost:Connect(function()
        tw(SearchStroke, {Transparency = 1}, .12)
    end))

    -- Selected harvested-fruit total shown beside Refresh.  This uses the exact
    -- same compact formatter / gold Sheckles color as the fruit value rows.
    local InventoryTotalValueLabel = N("TextLabel", {
        Name = "InventoryTotalFruitValue",
        Position = UDim2.new(.57, 0, 0, 75),
        Size = UDim2.new(.24, 0, 0, 30),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "TOTAL  $ 0",
        TextColor3 = INVENTORY_FRUIT_VALUE_COLOR,
        Font = T.Font,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, Inventory)

    local RefreshButton = C(N("TextButton", {
        Name = "InventoryRefresh",
        Position = UDim2.new(.82, 2, 0, 75),
        Size = UDim2.new(.18, -6, 0, 30),
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        Text = "REFRESH",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 8,
        AutoButtonColor = false,
    }, Inventory), 6)
    S(RefreshButton, T.Line, .62, 1)

    local DropSelectedButton = C(N("TextButton", {
        Name = "InventoryDropSelected",
        Position = UDim2.new(0, 4, 1, -35),
        Size = UDim2.new(1, -8, 0, 31),
        BackgroundColor3 = T.RedDark,
        BorderSizePixel = 0,
        Text = "DROP",
        TextColor3 = T.White,
        Font = T.Font,
        TextSize = 10,
        AutoButtonColor = false,
    }, Inventory), 6)
    S(DropSelectedButton, T.Line, .42, 1)

    local ListPanel = C(N("Frame", {
        Position = UDim2.new(0, 4, 0, 111),
        Size = UDim2.new(1, -8, 1, -151),
        BackgroundColor3 = T.Panel,
        BackgroundTransparency = .12,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, Inventory), 6)
    gradient(
        ListPanel,
        Color3.fromRGB(43, 17, 24),
        Color3.fromRGB(18, 8, 12)
    )
    S(ListPanel, T.Line, .28, 1)

    local Scroll = N("ScrollingFrame", {
        Name = "InventoryItemList",
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

    local VIRTUAL_ROW_HEIGHT = 52
    local VIRTUAL_ROW_GAP = 4
    local VIRTUAL_ROW_STRIDE = VIRTUAL_ROW_HEIGHT + VIRTUAL_ROW_GAP
    local VIRTUAL_BUFFER_ROWS = 3
    local VIRTUAL_MIN_ROWS = 7
    local VIRTUAL_MAX_ROWS = 18

    local refreshInventory
    local renderVirtualRows
    local runDrop
    local runSelectedQueue
    local stopDropJob
    local setHeaderStatus

    -- V73: Favorite buttons live in their own logical-item layer instead of inside
    -- recycled virtual row Frames. A button is keyed to data.Key for its whole
    -- lifetime, so it can never be temporarily reused by a neighboring row.
    FavoriteRuntime.Buttons = {}
    FavoriteRuntime.ButtonData = {}
    FavoriteRuntime.VisibleKeys = {}
    FavoriteRuntime.NextVisibleKeys = {}

    function FavoriteRuntime.GetButton(data)
        local key = tostring(data and data.Key or "")
        if key == "" then return nil end

        local existing = FavoriteRuntime.Buttons[key]
        if existing and existing.Parent == Scroll then
            return existing
        end

        local button = C(N("TextButton", {
            Name = "InventoryFavoriteAction",
            Text = "FAV",
            Position = UDim2.new(.58, 2, 0, 0),
            Size = UDim2.new(.10, -2, 0, 28),
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 8,
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 20,
        }, Scroll), 6)
        S(button, T.Line, .58, 1)

        FavoriteRuntime.Buttons[key] = button
        TrackConnection(button.Activated:Connect(function()
            FavoriteRuntime.Toggle(FavoriteRuntime.ButtonData[key])
        end))

        return button
    end

    function FavoriteRuntime.BeginButtonPass()
        table.clear(FavoriteRuntime.NextVisibleKeys)
    end

    function FavoriteRuntime.RenderButton(data, itemIndex)
        local favoriteTotal = tonumber(data and data.FavoriteTotal) or 0
        if favoriteTotal <= 0 then return end

        local key = tostring(data.Key or "")
        local button = FavoriteRuntime.GetButton(data)
        if not button then return end

        FavoriteRuntime.ButtonData[key] = data
        FavoriteRuntime.NextVisibleKeys[key] = true

        -- Anchor to the LOGICAL item's canvas row, not to a pooled Frame.
        local targetY = (itemIndex - 1) * VIRTUAL_ROW_STRIDE + 1
        button.Position = UDim2.new(.58, 2, 0, targetY + 12)

        local favoriteBusy = FavoriteRuntime.Busy[data.Key] == true
        local allFavorite = (tonumber(data.FavoriteCount) or 0) >= favoriteTotal
        button.Active = not favoriteBusy and not State.QueueRunning

        if favoriteBusy then
            button.Text = "..."
            button.BackgroundColor3 = T.Red
        elseif allFavorite then
            button.Text = "UNFAV"
            button.BackgroundColor3 = T.RedDark
        else
            button.Text = "FAV"
            button.BackgroundColor3 = T.Surface3
        end
        button.TextColor3 = T.White
        button.Visible = true
    end

    function FavoriteRuntime.EndButtonPass()
        for key in pairs(FavoriteRuntime.VisibleKeys) do
            if not FavoriteRuntime.NextVisibleKeys[key] then
                local button = FavoriteRuntime.Buttons[key]
                if button then
                    button.Visible = false
                    button.Active = false
                end
                FavoriteRuntime.VisibleKeys[key] = nil
            end
        end

        for key in pairs(FavoriteRuntime.NextVisibleKeys) do
            FavoriteRuntime.VisibleKeys[key] = true
        end
    end

    function FavoriteRuntime.Prune(rows)
        local keep = {}
        for _, data in ipairs(rows or {}) do
            if (tonumber(data.FavoriteTotal) or 0) > 0 then
                keep[tostring(data.Key)] = true
            end
        end

        for key, button in pairs(FavoriteRuntime.Buttons) do
            if not keep[key] then
                if button then pcall(function() button:Destroy() end) end
                FavoriteRuntime.Buttons[key] = nil
                FavoriteRuntime.ButtonData[key] = nil
                FavoriteRuntime.VisibleKeys[key] = nil
                FavoriteRuntime.NextVisibleKeys[key] = nil
            end
        end
    end

    function FavoriteRuntime.Toggle(data)
        if not data or type(data.FavoriteEntries) ~= "table" or #data.FavoriteEntries == 0 then
            return
        end
        if State.QueueRunning or FavoriteRuntime.Busy[data.Key] then
            return
        end

        local kind = data.FavoriteKind or (data.IsFruit and "Fruit" or "Pet")
        local remote = FavoriteRuntime.Remotes[kind]
        if not remote or type(remote.Fire) ~= "function" then
            setHeaderStatus("FAVORITE ERROR", T.Red)
            Info.Text = "Networking.Backpack.Set" .. tostring(kind) .. "Favorite was not found."
            return
        end

        local rowKey = data.Key
        local displayName = tostring(data.DisplayName or data.Name or kind)
        local targetState = not ((tonumber(data.FavoriteTotal) or 0) > 0
            and (tonumber(data.FavoriteCount) or 0) >= (tonumber(data.FavoriteTotal) or 0))
        local entries = data.FavoriteEntries

        FavoriteRuntime.Busy[rowKey] = true
        if renderVirtualRows then renderVirtualRows() end

        task.spawn(function()
            local changed = 0
            local failed = 0

            for _, entry in ipairs(entries) do
                if not alive then break end

                local current = FavoriteRuntime.IsFavorite(entry.Instance)
                if current ~= targetState then
                    local callOk, response = pcall(function()
                        return remote:Fire(entry.Id, targetState)
                    end)

                    if callOk and response == true then
                        changed += 1
                    else
                        failed += 1
                    end
                    task.wait(0.05)
                end
            end

            local deadline = os.clock() + 1.5
            while alive and os.clock() < deadline do
                local ready = true
                for _, entry in ipairs(entries) do
                    if entry.Instance and entry.Instance.Parent
                        and FavoriteRuntime.IsFavorite(entry.Instance) ~= targetState then
                        ready = false
                        break
                    end
                end
                if ready then break end
                task.wait(0.05)
            end

            FavoriteRuntime.Busy[rowKey] = nil
            if alive then
                refreshInventory(false)
                if failed > 0 then
                    setHeaderStatus("FAVORITE PARTIAL", T.Red)
                    Info.Text = displayName .. ": " .. tostring(failed) .. " favorite request(s) failed."
                else
                    setHeaderStatus(targetState and "FAVORITED" or "UNFAVORITED", T.Success)
                    local noun = kind == "Fruit" and "fruit(s)" or "pet(s)"
                    Info.Text = displayName
                        .. ": "
                        .. tostring(changed)
                        .. (targetState and (" " .. noun .. " favorited.") or (" " .. noun .. " unfavorited."))
                end
            end
        end)
    end
    setHeaderStatus = function(textValue, color)
        HeaderStatus.Text = tostring(textValue or "")
        HeaderStatus.TextColor3 = color or T.Success
    end

    local function updateInventoryTabs()
        for key, button in pairs(InventoryTabButtons) do
            local active = State.CurrentTab == key
            button.BackgroundTransparency = active and 0 or 1
            button.BackgroundColor3 = active and T.RedDark or T.Surface2
            button.TextColor3 = active and T.White or T.Muted
        end
    end

    local function applyFilters(resetScroll)
        local query = string.lower(trim(State.SearchText))
        local filtered = {}

        for _, item in ipairs(State.LatestItems) do
            local tabMatch = State.CurrentTab == "All"
                or (State.CurrentTab == "Items" and item.IsFruit ~= true)
                or (State.CurrentTab == "Fruits" and item.IsFruit == true)

            local searchMatch = query == ""
                or string.find(string.lower(item.DisplayName or item.Name), query, 1, true)
                or string.find(string.lower(item.Name), query, 1, true)
                or string.find(string.lower(item.Category), query, 1, true)
                or (item.IsFruit and string.find(string.lower(tostring(item.Mutation or "")), query, 1, true))

            if tabMatch and searchMatch then
                filtered[#filtered + 1] = item
            end
        end

        State.VisibleItems = filtered
        Scroll.CanvasSize = UDim2.new(
            0,
            0,
            0,
            math.max(0, #filtered * VIRTUAL_ROW_STRIDE)
        )

        if resetScroll then
            Scroll.CanvasPosition = Vector2.new(0, 0)
        end

        if renderVirtualRows then
            renderVirtualRows()
        end
    end

    local function updateInfo()
        local totalUnits = 0
        local droppableTypes = 0
        local fruitCount = 0
        local selectedFruitValue = 0

        for _, item in ipairs(State.LatestItems) do
            totalUnits += item.Count
            if item.Droppable then
                droppableTypes += 1
            end
            if item.IsFruit then
                fruitCount += 1
                if State.Selected[item.Key] == true then
                    selectedFruitValue += tonumber(item.Value) or 0
                end
            end
        end

        -- The Sheckles total is selection-driven: unchecked fruits contribute 0.
        -- This makes the number a live total for the exact fruits queued to drop.
        InventoryTotalValueLabel.Text = "TOTAL  $ " .. inventoryFormatFruitValue(selectedFruitValue)

        if running then
            Info.Text = string.format(
                "Dropping %s  •  %d/%d confirmed  •  %d attempts",
                tostring(activeDropDisplayName or activeDropName or "item"),
                activeDropConfirmed,
                activeDropTarget,
                activeDropAttempts
            )
            return
        end

        Info.Text = string.format(
            "%d rows  •  %d total owned  •  %d mail/drop  •  %d fruits",
            #State.LatestItems,
            totalUnits,
            droppableTypes,
            fruitCount
        )
    end

    local function requiredVirtualRows()
        local viewportHeight = Scroll.AbsoluteWindowSize.Y
        if not viewportHeight or viewportHeight <= 0 then
            viewportHeight = Scroll.AbsoluteSize.Y
        end

        local required = math.ceil(
            math.max(viewportHeight, VIRTUAL_ROW_HEIGHT)
            / VIRTUAL_ROW_STRIDE
        ) + VIRTUAL_BUFFER_ROWS

        return math.clamp(required, VIRTUAL_MIN_ROWS, VIRTUAL_MAX_ROWS)
    end

    local function createVirtualRow()
        local Row = C(N("Frame", {
            Name = "InventoryItemRow",
            Position = UDim2.new(0, 1, 0, 0),
            Size = UDim2.new(1, -4, 0, VIRTUAL_ROW_HEIGHT),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = .05,
            BorderSizePixel = 0,
            Visible = false,
        }, Scroll), 6)
        S(Row, T.Line, .70, 1)

        local Check = C(N("TextButton", {
            Name = "Select",
            Text = "",
            Position = UDim2.fromOffset(8, 11),
            Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 13,
            AutoButtonColor = false,
        }, Row), 5)
        S(Check, T.Line, .58, 1)

        local Name = label(
            Row,
            "",
            UDim2.fromOffset(45, 5),
            UDim2.new(.57, -45, 0, 20),
            11,
            T.White,
            T.Font
        )
        Name.TextTruncate = Enum.TextTruncate.AtEnd

        local Rarity = label(
            Row,
            "",
            UDim2.fromOffset(45, 27),
            UDim2.new(.57, -45, 0, 16),
            9,
            T.Muted,
            T.Font
        )
        Rarity.TextTruncate = Enum.TextTruncate.AtEnd

        local Qty = C(N("TextBox", {
            Name = "Qty",
            Position = UDim2.new(.69, 0, .5, -16),
            Size = UDim2.new(.14, 0, 0, 32),
            BackgroundColor3 = Color3.fromRGB(7, 7, 11),
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Qty",
            PlaceholderColor3 = T.Muted,
            TextColor3 = T.White,
            Font = T.Body,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Center,
            ClearTextOnFocus = false,
        }, Row), 7)
        S(Qty, T.Line, .58, 1)

        local Owned = label(
            Row,
            "",
            UDim2.new(.84, 4, 0, 0),
            UDim2.new(.16, -12, 1, 0),
            10,
            T.Muted,
            T.Body,
            Enum.TextXAlignment.Right
        )

        local record = {
            Frame = Row,
            Check = Check,
            Name = Name,
            Rarity = Rarity,
            Qty = Qty,
            Owned = Owned,
            Data = nil,
        }

        TrackConnection(Check.Activated:Connect(function()
            local data = record.Data
            if not data or State.QueueRunning then
                return
            end

            if not data.Droppable or not data.DropCategory then
                setHeaderStatus("DISPLAY ONLY", T.Muted)
                Info.Text = data.Name
                    .. " is not classified as mailable by the current inventory rules."
                return
            end

            State.Selected[data.Key] = not State.Selected[data.Key]
            if State.Selected[data.Key] then
                if data.IsFruit then
                    State.Quantities[data.Key] = 1
                elseif not State.Quantities[data.Key] then
                    State.Quantities[data.Key] = 1
                end
            end
            updateInfo()
            renderVirtualRows()
        end))

        TrackConnection(Qty.FocusLost:Connect(function()
            local data = record.Data
            if not data then
                return
            end

            if data.IsFruit then
                State.Quantities[data.Key] = 1
                Qty.Text = "1"
                return
            end

            local raw = trim(Qty.Text)
            if raw == "" then
                State.Quantities[data.Key] = nil
                return
            end

            local amount = math.clamp(
                math.max(1, math.floor(tonumber(raw) or 1)),
                1,
                math.max(1, data.Count)
            )
            State.Quantities[data.Key] = amount
            Qty.Text = tostring(amount)
        end))

        State.RowPool[#State.RowPool + 1] = record
        return record
    end

    local function ensureVirtualRowPool()
        local required = requiredVirtualRows()
        while #State.RowPool < required do
            createVirtualRow()
        end
    end

    local function updateVirtualRow(record, data, itemIndex)
        -- Inventory rows are virtualized and the same physical Frame is reused for
        -- different items while scrolling. Hide the WHOLE row while rebinding it.
        -- Showing the parent before all children were updated allowed one rendered
        -- frame where the new item name could be paired with the old FAV/UNFAV state.
        record.Frame.Visible = false
        record.Data = data

        local targetY = (itemIndex - 1) * VIRTUAL_ROW_STRIDE + 1
        record.Frame.Position = UDim2.new(0, 1, 0, targetY)

        local selected = State.Selected[data.Key] == true
        local isActive = running
            and data.DropCategory == activeDropCategory
            and data.Name == activeDropName
            and (data.ItemKey == nil or tostring(data.ItemKey) == tostring(activeDropItemKey))

        record.Name.Text = data.DisplayName or data.Name

        if data.IsFruit then
            local mutation = tostring(data.Mutation or "Normal")
            record.Rarity.Text = mutation .. "  •  " .. inventoryFormatFruitMultiplier(data.Multiplier)
            record.Rarity.TextColor3 = T.Success

            -- Same value style as Garden: bold theme font + gold warning color + "$ amount".
            record.Owned.Text = "$ " .. inventoryFormatFruitValue(data.Value)
            record.Owned.TextColor3 = INVENTORY_FRUIT_VALUE_COLOR
            record.Owned.Font = T.Font
            record.Owned.TextSize = 11
        else
            -- Restore the normal item-owned style when a virtual row is recycled.
            record.Owned.TextColor3 = T.Muted
            record.Owned.Font = T.Body
            record.Owned.TextSize = 10

            local rarity = tostring(data.Rarity or "Unknown")
            if rarity == "Unknown" then
                record.Rarity.Text = data.Category
                record.Rarity.TextColor3 = T.Muted
            else
                record.Rarity.Text = rarity
                record.Rarity.TextColor3 = INVENTORY_RARITY_COLORS[rarity] or T.Muted
            end
            record.Owned.Text = "Owned  " .. tostring(data.Count)
        end

        local storedQty = State.Quantities[data.Key]
        if data.IsFruit then
            State.Quantities[data.Key] = 1
            if not record.Qty:IsFocused() then
                record.Qty.Text = "1"
            end
            record.Qty.TextEditable = false
            record.Qty.PlaceholderText = "1"
            record.Qty.BackgroundColor3 = T.Surface3
        else
            if not record.Qty:IsFocused() then
                record.Qty.Text = storedQty and tostring(storedQty) or ""
            end
            record.Qty.TextEditable = data.Droppable and not State.QueueRunning
            record.Qty.PlaceholderText = data.Droppable and "Qty" or "--"
            record.Qty.BackgroundColor3 = data.Droppable
                and Color3.fromRGB(7, 7, 11)
                or T.Surface3
        end

        if isActive then
            record.Check.Text = "…"
            record.Check.BackgroundColor3 = T.Red
            record.Check.TextColor3 = T.White
        elseif selected then
            record.Check.Text = "✓"
            record.Check.BackgroundColor3 = T.RedDark
            record.Check.TextColor3 = T.White
        else
            record.Check.Text = ""
            record.Check.BackgroundColor3 = T.Surface3
            record.Check.TextColor3 = T.White
        end

        record.Check.Active = data.Droppable and not State.QueueRunning
        record.Frame.BackgroundTransparency = selected and .00 or .05

        -- Publish the completely rebound row in one step. This keeps the pet/fruit
        -- favorite button visually attached to the correct item during fast scroll.
        record.Frame.Visible = true
    end

    renderVirtualRows = function()
        ensureVirtualRowPool()
        FavoriteRuntime.BeginButtonPass()

        local firstIndex = math.floor(
            math.max(0, Scroll.CanvasPosition.Y) / VIRTUAL_ROW_STRIDE
        ) + 1

        local poolIndex = 1
        for itemIndex = firstIndex, math.min(
            #State.VisibleItems,
            firstIndex + #State.RowPool - 1
        ) do
            local data = State.VisibleItems[itemIndex]
            local record = State.RowPool[poolIndex]
            updateVirtualRow(record, data, itemIndex)
            FavoriteRuntime.RenderButton(data, itemIndex)
            poolIndex += 1
        end

        for index = poolIndex, #State.RowPool do
            local record = State.RowPool[index]
            record.Data = nil
            record.Frame.Visible = false
        end

        FavoriteRuntime.EndButtonPass()
    end

    refreshInventory = function(resetScroll)
        local rows = collectInventory()
        FavoriteRuntime.Prune(rows)
        State.LatestItems = rows
        State.LastSignature = inventorySignature(rows)
        InventoryRefreshDirty = false
        InventoryRefreshResetScroll = false
        updateInfo()
        applyFilters(resetScroll == true)
    end

    stopDropJob = function(reason)
        if not running then
            return
        end

        runId += 1
        running = false
        setHeaderStatus("STOPPED", T.Red)
        Info.Text = tostring(reason or "Drop job stopped.")
        renderVirtualRows()
    end

    runDrop = function(category, itemName, requestedAmount, itemKey, displayName)
        if not RequestDrop then
            setHeaderStatus("ERROR", T.Red)
            Info.Text = "Networking.DroppedItem.RequestDrop was not found."
            return
        end

        if automationIsBusy() then
            setHeaderStatus("AUTOMATION ACTIVE", T.Red)
            Info.Text = "Stop Auto Plant / Auto Harvest / Auto Sell / Auto Trowel before dropping."
            return
        end

        local startingCount = getOwnedCount(category, itemName, itemKey)
        if startingCount <= 0 then
            setHeaderStatus("NOT FOUND", T.Red)
            Info.Text = "The selected item is no longer in inventory."
            refreshInventory(true)
            return
        end

        local actualDropAmount = math.min(
            math.max(1, math.floor(requestedAmount)),
            startingCount
        )
        local targetRemaining = startingCount - actualDropAmount
        local myRunId = runId + 1
        runId = myRunId
        running = true

        activeDropCategory = category
        activeDropName = itemName
        activeDropItemKey = itemKey
        activeDropDisplayName = displayName or itemName
        activeDropTarget = actualDropAmount
        activeDropConfirmed = 0
        activeDropAttempts = 0

        setHeaderStatus("DROPPING", T.Success)
        updateInfo()
        renderVirtualRows()

        task.spawn(function()
            local requestAttempts = 0
            local consecutiveFailures = 0
            local completed = false
            local stopReason = nil
            local hasConfirmedFirstDrop = false
            local lastRequestFireAt = nil
            local lastConfirmedAt = nil
            local isDirectFruitDrop = category == "HarvestedFruits"
                and itemKey ~= nil
                and tostring(itemKey) ~= ""

            local function waitForRequestSlot()
                if not lastRequestFireAt and not lastConfirmedAt then
                    return true
                end

                local now = os.clock()
                local fireRemaining = lastRequestFireAt
                    and (FOLLOWUP_REQUEST_INTERVAL - (now - lastRequestFireAt))
                    or 0
                local confirmRemaining = lastConfirmedAt
                    and (POST_CONFIRM_REQUEST_DELAY - (now - lastConfirmedAt))
                    or 0
                local remaining = math.max(0, fireRemaining, confirmRemaining)

                if remaining > 0 then
                    local finishAt = os.clock() + remaining
                    while os.clock() < finishAt do
                        if myRunId ~= runId then
                            return false
                        end
                        task.wait(math.min(0.05, finishAt - os.clock()))
                    end
                end

                return myRunId == runId
            end

            while myRunId == runId do
                local currentCount = getOwnedCount(category, itemName, itemKey)

                if currentCount <= targetRemaining then
                    completed = true
                    stopReason = "Target remaining count reached."
                    break
                end

                if currentCount <= 0 then
                    stopReason = "Item no longer exists in inventory."
                    break
                end

                local heldTool = nil
                local holdError = nil

                if isDirectFruitDrop then
                    heldTool, holdError = FruitHold.Ensure(itemKey)
                else
                    heldTool, holdError = ensureItemHeld(category, itemName, itemKey)
                end

                if myRunId ~= runId then
                    break
                end

                if not heldTool then
                    consecutiveFailures += 1
                    setHeaderStatus("HOLD RETRY", T.Red)
                    Info.Text = tostring(holdError)
                        .. "  •  retry "
                        .. tostring(consecutiveFailures)
                        .. "/"
                        .. tostring(MAX_CONSECUTIVE_TIMEOUTS)

                    if consecutiveFailures >= MAX_CONSECUTIVE_TIMEOUTS then
                        stopReason = "Could not hold selected item."
                        break
                    end

                    task.wait(RETRY_DELAY)
                    continue
                end

                if not waitForRequestSlot() then
                    break
                end

                local before = getOwnedCount(category, itemName, itemKey)
                if before <= targetRemaining then
                    completed = true
                    stopReason = "Target remaining count reached."
                    break
                end

                requestAttempts += 1
                activeDropAttempts = requestAttempts
                updateInfo()
                renderVirtualRows()

                if isDirectFruitDrop then
                    local fruitHeld = FruitHold.IsHeld(itemKey)
                    if not fruitHeld then
                        consecutiveFailures += 1
                        setHeaderStatus("HOLD RETRY", T.Red)
                        Info.Text = "Harvested fruit stopped being selected before RequestDrop."
                        task.wait(RETRY_DELAY)
                        continue
                    end
                else
                    local character = LocalPlayer.Character
                    if not character or not heldTool or heldTool.Parent ~= character then
                        consecutiveFailures += 1
                        task.wait(RETRY_DELAY)
                        continue
                    end
                end

                -- Normal Tools use Humanoid:EquipTool(). Harvested fruits use the
                -- game's InventoryController Select path first, then RequestDrop
                -- receives HarvestedFruits + the exact unique fruit Id.
                local requestItemKey = getRequestDropItemKey(heldTool, category, itemName, itemKey)
                local requestFireAt = nil
                local fired, fireError = pcall(function()
                    requestFireAt = os.clock()
                    RequestDrop:Fire(category, requestItemKey)
                end)

                if not fired then
                    consecutiveFailures += 1
                    setHeaderStatus("FIRE RETRY", T.Red)
                    Info.Text = tostring(fireError)

                    if consecutiveFailures >= MAX_CONSECUTIVE_TIMEOUTS then
                        stopReason = "Too many consecutive Fire/hold failures."
                        break
                    end

                    task.wait(RETRY_DELAY)
                    continue
                end

                lastRequestFireAt = requestFireAt or os.clock()

                local confirmationTimeout = hasConfirmedFirstDrop
                    and FOLLOWUP_CONFIRM_TIMEOUT
                    or FIRST_DROP_CONFIRM_TIMEOUT

                local changed, after, _, cancelled = waitForInventoryDecrease(
                    category,
                    itemName,
                    itemKey,
                    before,
                    confirmationTimeout,
                    myRunId
                )

                if cancelled or myRunId ~= runId then
                    break
                end

                if changed then
                    consecutiveFailures = 0
                    hasConfirmedFirstDrop = true
                    lastConfirmedAt = os.clock()

                    local totalConfirmed = math.max(0, startingCount - after)
                    activeDropConfirmed = math.min(totalConfirmed, actualDropAmount)
                    setHeaderStatus("DROPPING", T.Success)
                    refreshInventory(false)

                    if after <= targetRemaining then
                        completed = true
                        stopReason = "Target remaining count reached."
                        break
                    end
                else
                    consecutiveFailures += 1
                    setHeaderStatus("REQUEST IGNORED", T.Red)
                    Info.Text = "Inventory stayed at "
                        .. tostring(after)
                        .. ". Retrying "
                        .. tostring(consecutiveFailures)
                        .. "/"
                        .. tostring(MAX_CONSECUTIVE_TIMEOUTS)
                        .. "."

                    if consecutiveFailures >= MAX_CONSECUTIVE_TIMEOUTS then
                        stopReason = "Too many consecutive ignored requests/timeouts."
                        break
                    end

                    task.wait(RETRY_DELAY)
                end
            end

            if not isDirectFruitDrop then
                unholdSelectedItem(category, itemName, itemKey)
            end

            if myRunId == runId then
                local finalCount = getOwnedCount(category, itemName, itemKey)
                local confirmedTotal = math.max(0, startingCount - finalCount)
                running = false
                activeDropConfirmed = math.min(confirmedTotal, actualDropAmount)

                refreshInventory(false)

                if completed then
                    setHeaderStatus("FINISHED", T.Success)
                    Info.Text = tostring(confirmedTotal)
                        .. " "
                        .. tostring(displayName or itemName)
                        .. " dropped successfully  •  "
                        .. tostring(finalCount)
                        .. " remaining"
                else
                    setHeaderStatus("STOPPED", T.Red)
                    Info.Text = tostring(stopReason or "Drop job stopped.")
                end

                renderVirtualRows()
            end
        end)
    end

    runSelectedQueue = function()
        if State.QueueRunning then
            State.QueueRunId += 1
            State.QueueRunning = false
            DropSelectedButton.Text = "DROP"
            DropSelectedButton.BackgroundColor3 = T.RedDark

            local category = activeDropCategory
            local itemName = activeDropName
            local itemKey = activeDropItemKey
            stopDropJob("Drop queue stopped by user.")
            if category and itemName then
                task.spawn(function()
                    unholdSelectedItem(category, itemName, itemKey)
                    task.wait(0.05)
                    refreshInventory(false)
                end)
            end
            return
        end

        local jobs = {}
        for _, item in ipairs(State.LatestItems) do
            if State.Selected[item.Key] and item.Droppable and item.DropCategory then
                local amount
                if item.IsFruit then
                    amount = 1
                else
                    amount = math.clamp(
                        math.max(1, math.floor(tonumber(State.Quantities[item.Key]) or 1)),
                        1,
                        math.max(1, item.Count)
                    )
                end
                State.Quantities[item.Key] = amount
                jobs[#jobs + 1] = {
                    Key = item.Key,
                    Name = item.Name,
                    DisplayName = item.DisplayName or item.Name,
                    Category = item.DropCategory,
                    ItemKey = item.ItemKey,
                    Amount = amount,
                    IsFruit = item.IsFruit == true,
                }
            end
        end

        if #jobs == 0 then
            setHeaderStatus("NOTHING SELECTED", T.Red)
            Info.Text = "Check one or more mailable items and enter Qty for each."
            if Notify then
                Notify("Inventory", "Check one or more items and enter Qty for each.", 2)
            end
            return
        end

        if automationIsBusy() then
            setHeaderStatus("AUTOMATION ACTIVE", T.Red)
            Info.Text = "Stop Auto Plant / Auto Harvest / Auto Sell / Auto Trowel before dropping."
            return
        end

        State.QueueRunId += 1
        local myQueueId = State.QueueRunId
        State.QueueRunning = true
        DropSelectedButton.Text = "STOP"
        DropSelectedButton.BackgroundColor3 = T.Red
        renderVirtualRows()

        task.spawn(function()
            for index, job in ipairs(jobs) do
                if not alive or myQueueId ~= State.QueueRunId or not State.QueueRunning then
                    break
                end

                Info.Text = string.format(
                    "Queue %d/%d  •  %s  •  Qty %d",
                    index,
                    #jobs,
                    job.DisplayName or job.Name,
                    job.Amount
                )

                runDrop(job.Category, job.Name, job.Amount, job.ItemKey, job.DisplayName)

                while alive
                    and myQueueId == State.QueueRunId
                    and State.QueueRunning
                    and running do
                    task.wait(0.05)
                end

                if myQueueId ~= State.QueueRunId or not State.QueueRunning then
                    break
                end

                if activeDropName == job.Name
                    and activeDropCategory == job.Category
                    and (job.ItemKey == nil or tostring(activeDropItemKey) == tostring(job.ItemKey))
                    and activeDropConfirmed >= job.Amount then
                    State.Selected[job.Key] = nil
                    State.Quantities[job.Key] = nil
                end

                task.wait(0.05)
            end

            if myQueueId == State.QueueRunId then
                State.QueueRunning = false
                DropSelectedButton.Text = "DROP"
                DropSelectedButton.BackgroundColor3 = T.RedDark
                refreshInventory(false)
                renderVirtualRows()

                if not running then
                    setHeaderStatus("READY", T.Success)
                    updateInfo()
                end
            end
        end)
    end

    for key, button in pairs(InventoryTabButtons) do
        TrackConnection(button.Activated:Connect(function()
            State.CurrentTab = key
            updateInventoryTabs()
            applyFilters(true)
        end))
    end

    TrackConnection(Search:GetPropertyChangedSignal("Text"):Connect(function()
        State.SearchText = Search.Text
        applyFilters(true)
    end))

    TrackConnection(DropSelectedButton.Activated:Connect(function()
        runSelectedQueue()
    end))

    TrackConnection(RefreshButton.Activated:Connect(function()
        requestInventoryFruitValueRefresh()
        refreshInventory(false)
        setHeaderStatus(running and "DROPPING" or "REFRESHED", T.Success)
    end))

    TrackConnection(Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        renderVirtualRows()
    end))

    TrackConnection(Scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        renderVirtualRows()
    end))

    -- V69 PERFORMANCE: coalesce bursts of Backpack/Character changes into one
    -- refresh. If Inventory is hidden we only mark it dirty; opening the page
    -- performs one fresh scan instead of doing background work.
    local function scheduleInventoryRefresh(delaySeconds, resetScroll)
        InventoryRefreshDirty = true
        if resetScroll then
            InventoryRefreshResetScroll = true
        end

        if not alive or not Inventory.Visible or InventoryRefreshScheduled then
            return
        end

        InventoryRefreshScheduled = true
        task.delay(delaySeconds or 0.08, function()
            InventoryRefreshScheduled = false

            if not alive or not Inventory.Visible or not InventoryRefreshDirty then
                return
            end

            local shouldReset = InventoryRefreshResetScroll
            refreshInventory(shouldReset)
        end)
    end

    local function watchInventoryStack(instance)
        if not instance or InventoryCountWatchers[instance] then
            return
        end
        if not instance:IsA("Tool") and instance:GetAttribute("HarvestedFruit") ~= true then
            return
        end

        local connections = {}
        if instance:IsA("Tool") then
            connections[#connections + 1] = instance:GetAttributeChangedSignal("Count"):Connect(function()
                -- Count changes are the normal path for stacked Seeds/Gear/Crates/etc.
                scheduleInventoryRefresh(0.06, false)
            end)
        end
        connections[#connections + 1] = instance:GetAttributeChangedSignal("IsFavorite"):Connect(function()
            scheduleInventoryRefresh(0.02, false)
        end)
        connections[#connections + 1] = instance:GetAttributeChangedSignal("Favorite"):Connect(function()
            scheduleInventoryRefresh(0.02, false)
        end)

        InventoryCountWatchers[instance] = connections
        for _, connection in ipairs(connections) do
            TrackConnection(connection)
        end
    end

    local CharacterChildAddedConnection
    local CharacterChildRemovedConnection

    local function bindCharacterInventory(character)
        if CharacterChildAddedConnection then
            CharacterChildAddedConnection:Disconnect()
            CharacterChildAddedConnection = nil
        end
        if CharacterChildRemovedConnection then
            CharacterChildRemovedConnection:Disconnect()
            CharacterChildRemovedConnection = nil
        end

        if not character then
            return
        end

        for _, instance in ipairs(character:GetChildren()) do
            watchInventoryStack(instance)
        end

        CharacterChildAddedConnection = character.ChildAdded:Connect(function(instance)
            watchInventoryStack(instance)
            scheduleInventoryRefresh(0.06, false)
        end)
        CharacterChildRemovedConnection = character.ChildRemoved:Connect(function()
            scheduleInventoryRefresh(0.06, false)
        end)
        TrackConnection(CharacterChildAddedConnection)
        TrackConnection(CharacterChildRemovedConnection)
    end

    for _, instance in ipairs(Backpack:GetChildren()) do
        watchInventoryStack(instance)
    end
    bindCharacterInventory(LocalPlayer.Character)

    TrackConnection(Backpack.ChildAdded:Connect(function(instance)
        watchInventoryStack(instance)
        scheduleInventoryRefresh(0.06, false)
    end))
    TrackConnection(Backpack.ChildRemoved:Connect(function()
        scheduleInventoryRefresh(0.06, false)
    end))

    TrackConnection(LocalPlayer.CharacterAdded:Connect(function(character)
        bindCharacterInventory(character)
        InventoryToolMetadataCache = setmetatable({}, { __mode = "k" })
        scheduleInventoryRefresh(0.25, false)
    end))

    -- Safety reconciliation is visibility-driven. It exists only while this page
    -- is open and catches rare changes that do not touch Backpack children or Count.
    local function restartInventoryReconciler()
        InventoryReconcileGeneration += 1
        local myGeneration = InventoryReconcileGeneration

        if not alive or not Inventory.Visible then
            return
        end

        requestInventoryFruitValueRefresh()
        scheduleInventoryRefresh(0, false)
        setHeaderStatus(running and "DROPPING" or "READY", T.Success)

        task.spawn(function()
            while alive
                and Inventory.Visible
                and InventoryReconcileGeneration == myGeneration do

                task.wait(3.0)

                if not alive
                    or not Inventory.Visible
                    or InventoryReconcileGeneration ~= myGeneration then
                    break
                end

                local rows = collectInventory()
                local signature = inventorySignature(rows)
                if signature ~= State.LastSignature then
                    State.LatestItems = rows
                    State.LastSignature = signature
                    InventoryRefreshDirty = false
                    updateInfo()
                    applyFilters(false)
                end
            end
        end)
    end

    TrackConnection(Inventory:GetPropertyChangedSignal("Visible"):Connect(function()
        if Inventory.Visible then
            -- Always treat opening as dirty because Mail fruit values/multipliers can
            -- change while Inventory is hidden without touching Backpack children.
            InventoryRefreshDirty = true
        end
        restartInventoryReconciler()
    end))

    _G.ScoopHubInventoryAPI = {
        Stop = function()
            State.QueueRunId += 1
            State.QueueRunning = false
            DropSelectedButton.Text = "DROP"
            DropSelectedButton.BackgroundColor3 = T.RedDark
            local category = activeDropCategory
            local itemName = activeDropName
            local itemKey = activeDropItemKey
            stopDropJob("Inventory drop stopped.")
            if category and itemName then
                task.spawn(function()
                    unholdSelectedItem(category, itemName, itemKey)
                    task.wait(0.05)
                    refreshInventory(false)
                end)
            end
        end,
        Refresh = function()
            InventoryRefreshDirty = true
            if Inventory.Visible then
                scheduleInventoryRefresh(0, false)
            else
                -- Explicit API refresh keeps its old semantics even while hidden.
                refreshInventory(false)
            end
        end,
        IsRunning = function()
            return running
        end,
    }

    RegisterScoopHubCleanup(function()
        if _G.ScoopHubInventoryAPI and _G.ScoopHubInventoryAPI.Stop then
            pcall(_G.ScoopHubInventoryAPI.Stop)
        end
    end)

    updateInventoryTabs()
    if Inventory.Visible then
        refreshInventory(true)
        restartInventoryReconciler()
    else
        -- Lazy first build: opening Inventory performs the authoritative scan.
        InventoryRefreshDirty = true
    end
    _G.__ScoopHubSilentLog("[ScoopHub] Inventory page initialized (V69 event-driven performance optimization).")
end

local __inventoryInitOk, __inventoryInitErr = pcall(__ScoopHubInitInventoryDrop)
if not __inventoryInitOk then
    warn("[ScoopHub] Inventory init error: " .. tostring(__inventoryInitErr))
    pcall(function()
        for _, child in ipairs(Inventory:GetChildren()) do
            child:Destroy()
        end

        local ErrorPanel = panel(
            Inventory,
            UDim2.fromScale(0, 0),
            UDim2.fromScale(1, 1),
            "INVENTORY"
        )

        local errLabel = label(
            ErrorPanel,
            "Inventory failed to initialize:\n" .. tostring(__inventoryInitErr),
            UDim2.new(0, 12, 0, 34),
            UDim2.new(1, -24, 1, -46),
            9,
            T.Red,
            T.Body
        )
        errLabel.TextWrapped = true
        errLabel.TextYAlignment = Enum.TextYAlignment.Top
    end)
end





    return true
end

_G.ScoopHubRemotePagesExport = RemotePages
return RemotePages
