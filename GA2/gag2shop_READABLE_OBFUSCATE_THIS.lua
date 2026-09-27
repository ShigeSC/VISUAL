-- ScoopHub V2.2 remote page module
-- Readable build: obfuscate this file by itself before uploading.
local Module = {}

function Module.Init(Bridge)
    if type(Bridge) ~= "table" then error("[ScoopHub Pages] Bridge required") end
    local Shop = Bridge.Shop
    local SG = Bridge.SG
    local Scale = Bridge.Scale
    local UIS = Bridge.UIS or game:GetService("UserInputService")
    local T = Bridge.T
    local N = Bridge.N
    local C = Bridge.C
    local S = Bridge.S
    local tw = Bridge.Tween
    local label = Bridge.Label
    local panel = Bridge.Panel
    local TrackConnection = Bridge.TrackConnection
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local ScoopHubRunAlive = Bridge.RunAlive
    local AccentSelectedBg = Bridge.AccentSelectedBg

    if not Shop or not SG or not Scale or type(T) ~= "table" then error("[ScoopHub Shop] GUI bridge incomplete") end

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
            if Picker and Picker.Visible then Picker.Visible = false end
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



    return true
end

Module.Version = "ScoopHub-V2.2-Shop-Remote-1"
return Module
