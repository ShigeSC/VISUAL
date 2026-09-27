-- ScoopHub V2.2 remote page module
-- Readable build: obfuscate this file by itself before uploading.
local Module = {}

function Module.Init(Bridge)
    if type(Bridge) ~= "table" then error("[ScoopHub Pages] Bridge required") end
    local Inventory = Bridge.Inventory
    local LP = Bridge.LP or game:GetService("Players").LocalPlayer
    local T = Bridge.T
    local N = Bridge.N
    local C = Bridge.C
    local S = Bridge.S
    local tw = Bridge.Tween
    local label = Bridge.Label
    local gradient = Bridge.Gradient
    local panel = Bridge.Panel
    local TrackConnection = Bridge.TrackConnection
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local Notify = Bridge.Notify or function(title, content)
        warn("[ScoopHub] " .. tostring(title or "Notice") .. ": " .. tostring(content or ""))
    end

    if not Inventory or type(T) ~= "table" then error("[ScoopHub Inventory] GUI bridge incomplete") end

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

Module.Version = "ScoopHub-V2.2-Inventory-Remote-1"
return Module
