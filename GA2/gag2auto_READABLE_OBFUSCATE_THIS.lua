-- ScoopHub V2.2 - Remote Automation module
-- Readable build: obfuscate this file by itself before uploading as gag2auto.lua.
local Module = { Version = "ScoopHub-V2.2-Automation-Remote-1" }

function Module.Init(Bridge)
    if type(Bridge) ~= "table" then error("[ScoopHub Automation] Bridge required") end

    local T = Bridge.T
    local N = Bridge.N
    local C = Bridge.C
    local S = Bridge.S
    local tw = Bridge.Tween
    local label = Bridge.Label
    local button = Bridge.Button
    local panel = Bridge.Panel
    local Automation = Bridge.Automation
    local SG = Bridge.SG
    local Scale = Bridge.Scale
    local Players = Bridge.Players or game:GetService("Players")
    local UIS = Bridge.UIS or game:GetService("UserInputService")
    local TrackConnection = Bridge.TrackConnection
    local RegisterScoopHubCleanup = Bridge.RegisterCleanup
    local ScoopHubRunAlive = Bridge.RunAlive
    local AccentSelectedBg = Bridge.AccentSelectedBg

    if type(T) ~= "table" or not Automation or not SG or not Scale then
        error("[ScoopHub Automation] GUI bridge incomplete")
    end
    if type(N) ~= "function" or type(C) ~= "function" or type(S) ~= "function"
        or type(label) ~= "function" or type(TrackConnection) ~= "function"
        or type(ScoopHubRunAlive) ~= "function" then
        error("[ScoopHub Automation] runtime bridge incomplete")
    end

local function __ScoopHubInitAutomation()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

local AutomationWorldData = _G.ScoopHubWorldData or {}
local AutomationCurrentWorld = AutomationWorldData.Current or { Key = "Unsupported", Seeds = {}, Gears = {} }
local AllSeeds = AutomationWorldData.CloneList
    and AutomationWorldData.CloneList(AutomationCurrentWorld.Seeds or {})
    or table.clone(AutomationCurrentWorld.Seeds or {})
local IsFallAutomationWorld = AutomationCurrentWorld.Key == "FallHarvestWorld"

local RarityOptions = {
    "Any",
    "Common",
    "Uncommon",
    "Rare",
    "Legendary",
    "Mythic",
    "Divine",
    "Prismatic",
    "Unknown",
}

local MutationOptions = {
    "Any",
    "Normal",
    "Gold",
    "Rainbow",
    "Wet",
    "Chilled",
    "Frozen",
    "Shocked",
    "Choc",
    "Moonlit",
    "Bloodlit",
    "Celestial",
    "Zombified",
    "Plasma",
    "Voidtouched",
    "Pollinated",
    "Twisted",
    "Disco",
    "Windstruck",
    "Dawnbound",
    "Electric",
    "Burnt",
    "HoneyGlazed",
    "Cooked",
    "Molten",
    "Sundried",
    "Wilted",
    "Alienlike",
}

local FALLBACK_SPRINKLER_DATA = {
    { SprinklerName = "Common Sprinkler", Radius = 20 },
    { SprinklerName = "Uncommon Sprinkler", Radius = 25 },
    { SprinklerName = "Rare Sprinkler", Radius = 30 },
    { SprinklerName = "Legendary Sprinkler", Radius = 40 },
    { SprinklerName = "Super Sprinkler", Radius = 55 },
    { SprinklerName = "Syrup Sprinkler", Radius = 20 },
    { SprinklerName = "Super Syrup Sprinkler", Radius = 55 },
}

local AllowedSprinklerLookup = {}
do
    local worldSprinklers = AutomationWorldData.GetWorldSprinklers
        and AutomationWorldData.GetWorldSprinklers()
        or {}
    for _, sprinklerName in ipairs(worldSprinklers) do
        AllowedSprinklerLookup[tostring(sprinklerName)] = true
    end
end

local function loadSprinklerCatalog()
    local source = FALLBACK_SPRINKLER_DATA

    local ok, data = pcall(function()
        local sharedModules = ReplicatedStorage:WaitForChild("SharedModules")
        local sprinklerData = sharedModules:WaitForChild("SprinklerData")
        return require(sprinklerData)
    end)

    if ok and type(data) == "table" then
        source = data
    end

    local options = {}
    local radii = {}
    local seen = {}

    for _, entry in ipairs(source) do
        if type(entry) == "table" then
            local name = tostring(entry.SprinklerName or "")
            local radius = tonumber(entry.Radius)

            if name ~= "" and radius and radius > 0 and not seen[name]
                and AllowedSprinklerLookup[name] then
                seen[name] = true
                radii[name] = radius
                table.insert(options, name)
            end
        end
    end

    if #options == 0 then
        for _, entry in ipairs(FALLBACK_SPRINKLER_DATA) do
            if AllowedSprinklerLookup[entry.SprinklerName] then
                radii[entry.SprinklerName] = entry.Radius
                table.insert(options, entry.SprinklerName)
            end
        end
    end

    return options, radii
end

local SprinklerTypeOptions, SprinklerRadiusByType = loadSprinklerCatalog()

local function getSprinklerRadiusForType(sprinklerType)
    return tonumber(SprinklerRadiusByType[tostring(sprinklerType or "")]) or 20
end

local REFERENCE_SUPER_DATA_RADIUS = 55
local REFERENCE_SUPER_PLANT_RADIUS = 20
local SPRINKLER_PLANT_RADIUS_SCALE =
    REFERENCE_SUPER_PLANT_RADIUS / REFERENCE_SUPER_DATA_RADIUS

local function getSprinklerPlantRadiusForType(sprinklerType)
    local dataRadius = getSprinklerRadiusForType(sprinklerType)
    return dataRadius * SPRINKLER_PLANT_RADIUS_SCALE
end

local DEFAULT_SPRINKLER_TYPE = SprinklerTypeOptions[1] or ""
for _, sprinklerName in ipairs(SprinklerTypeOptions) do
    if string.find(string.lower(sprinklerName), "super", 1, true) then
        DEFAULT_SPRINKLER_TYPE = sprinklerName
        break
    end
end

local State = {
    PlantNames = {},
    HarvestNames = {},
    SellNames = {},

    PlantEnabled = false,
    HarvestEnabled = false,
    SellEnabled = false,
    TrowelEnabled = false,
    PotEnabled = false,
    MergeEnabled = false,

    PlantDelay = 0.18,
    PlantLocation = "Random",
    SprinklerType = DEFAULT_SPRINKLER_TYPE,
    SprinklerRadius = getSprinklerRadiusForType(DEFAULT_SPRINKLER_TYPE),
    HarvestDelay = 0,

    HarvestMaxKg = 100,
    SellMaxKg = 3,

    HarvestRarities = {},
    HarvestMutations = {},

    SellRarities = {},
    SellMutations = {},

    HarvestDirection = "Below",
    SellDirection = "Below",

    TrowelPlantName = "All Plants",
    TrowelRarity = "Any",
    TrowelDelay = 1,
    TrowelPosition = nil,
    TrowelRunId = 0,

    PotPlantNames = { "All Plants" },

    HarvestBusy = false,
    SellBusy = false,
    SellRunId = 0,
}

local Stats = {
    Plants = 0,
    Harvests = 0,
    Sells = 0,
    Trowels = 0,
    Potted = 0,
    Merged = 0,
    LastAction = "Waiting for automation",
}

local function normalizeAutomationName(value)
    return string.lower(tostring(value or ""))
        :gsub("%s*[Ss]eed%s*$", "")
        :gsub("[^%w]", "")
end

local function listLookup(list)
    local lookup = {}

    for _, value in ipairs(list or {}) do
        local normalized = normalizeAutomationName(value)
        if normalized ~= "" then
            lookup[normalized] = true
            if IsFallAutomationWorld then
                local withoutMaple = normalized:gsub("^maple", "")
                if withoutMaple ~= "" then
                    lookup[withoutMaple] = true
                end
            end
        end
    end

    return lookup
end

local function isSelectedName(lookup, value)
    local normalized = normalizeAutomationName(value)
    if normalized == "" then
        return false
    end

    if lookup[normalized] == true then
        return true
    end

    if IsFallAutomationWorld then
        local withoutMaple = normalized:gsub("^maple", "")
        return withoutMaple ~= "" and lookup[withoutMaple] == true
    end

    return false
end

local function automationNamesEquivalent(a, b)
    local left = normalizeAutomationName(a)
    local right = normalizeAutomationName(b)
    if left == "" or right == "" then
        return false
    end
    if left == right then
        return true
    end
    if IsFallAutomationWorld then
        return left:gsub("^maple", "") == right:gsub("^maple", "")
    end
    return false
end

local function readAttribute(primary, fallback, names)
    local function read(object)
        if not object then
            return nil
        end

        for _, name in ipairs(names) do
            local value = object:GetAttribute(name)

            if value ~= nil then
                return tostring(value)
            end
        end

        return nil
    end

    return read(primary) or read(fallback)
end

local function matchesFilter(value, selected)
    if type(selected) ~= "table" or #selected == 0 then
        return true
    end

    local actual = tostring(value or "Unknown"):lower()

    for _, wanted in ipairs(selected) do
        wanted = tostring(wanted):lower()

        if wanted == "any" or wanted == actual then
            return true
        end
    end

    return false
end

local function matchesPlantFilters(primary, fallback, rarities, mutations)
    local rarity = readAttribute(
        primary,
        fallback,
        {
            "Rarity",
            "PlantRarity",
            "FruitRarity",
            "Tier",
        }
    ) or "Unknown"

    local mutation = readAttribute(
        primary,
        fallback,
        {
            "Mutation",
            "MutationName",
            "Mutations",
            "Variant",
            "FruitMutation",
        }
    ) or "Normal"

    return matchesFilter(rarity, rarities)
        and matchesFilter(mutation, mutations)
end

local function matchesWeight(weight, limit, direction)
    limit = tonumber(limit)

    if not limit then
        return false
    end

    if limit <= 0 then
        return true
    end

    weight = tonumber(weight)
    if not weight then
        return false
    end

    if direction == "Above" then
        return weight >= limit
    end

    return weight < limit
end

local function getNetworking()
    local ok, networking = pcall(function()
        return require(
            ReplicatedStorage
                :WaitForChild("SharedModules")
                :WaitForChild("Networking")
        )
    end)

    if ok and type(networking) == "table" then
        return networking
    end

    return nil
end

local function getFruitVisualizer()
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local controllers = scripts and scripts:FindFirstChild("Controllers")
    local controller = controllers and controllers:FindFirstChild("FruitVisualizerController")

    if not controller then
        return nil
    end

    local ok, result = pcall(require, controller)

    return ok and result or nil
end

local function getPlot()
    local gardens = Workspace:FindFirstChild("Gardens")
    if not gardens then
        return nil
    end

    local plotId = LocalPlayer:GetAttribute("PlotId")
    if plotId ~= nil then
        local plot = gardens:FindFirstChild("Plot" .. tostring(plotId))
        if plot then
            return plot
        end
    end

    for _, plot in ipairs(gardens:GetChildren()) do
        local owner = plot:GetAttribute("Owner")
            or plot:GetAttribute("OwnerName")
            or plot:GetAttribute("OwnerUserName")
        local ownerUserId = plot:GetAttribute("OwnerUserId")
            or plot:GetAttribute("OwnerId")
            or plot:GetAttribute("UserId")

        if tostring(owner or "") == LocalPlayer.Name
            or tonumber(ownerUserId) == LocalPlayer.UserId then
            return plot
        end
    end

    return nil
end

AutomationWorldData.RefreshLiveMutationOptions = function()
    local seen = {}
    for _, option in ipairs(MutationOptions) do
        seen[string.lower(tostring(option))] = true
    end

    local function registerMutation(value)
        if value == nil then
            return
        end

        local mutation = tostring(value)
            :gsub("^%s+", "")
            :gsub("%s+$", "")

        if mutation == "" then
            return
        end

        local lower = string.lower(mutation)
        if lower == "none" or lower == "nil" then
            mutation = "Normal"
            lower = "normal"
        end

        if not seen[lower] then
            seen[lower] = true
            table.insert(MutationOptions, mutation)
        end
    end

    local function scanMutationAttributes(object)
        if not object then
            return
        end

        for _, attributeName in ipairs({
            "Mutation",
            "MutationName",
            "Mutations",
            "Variant",
            "FruitMutation",
        }) do
            registerMutation(object:GetAttribute(attributeName))
        end
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if plantsFolder then
        for _, plant in ipairs(plantsFolder:GetChildren()) do

            scanMutationAttributes(plant)

            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    scanMutationAttributes(fruit)
                end
            end
        end
    end

    for _, container in ipairs({
        LocalPlayer:FindFirstChild("Backpack"),
        LocalPlayer.Character,
    }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                scanMutationAttributes(item)
            end
        end
    end
end

pcall(AutomationWorldData.RefreshLiveMutationOptions)

local function getPlantArea(plot)
    if not plot then
        return nil
    end

    for _, object in ipairs(plot:GetDescendants()) do
        if object:IsA("BasePart")
            and CollectionService:HasTag(object, "PlantArea") then

            return object
        end
    end

    return nil
end

local function getPlantName(plant)
    if not plant then
        return nil
    end

    return plant:GetAttribute("SeedName")
        or plant:GetAttribute("PlantName")
        or plant:GetAttribute("FruitName")
end

local function getPlantPosition(plant)
    if not plant then
        return nil
    end

    local ok, position = pcall(function()
        return plant:GetPivot().Position
    end)

    return ok and position or nil
end

local function findSeedTool(seedName)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")

    for _, container in ipairs({ character, backpack }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    for _, attributeName in ipairs({
                        "SeedName",
                        "ItemName",
                        "PlantName",
                        "FruitName",
                    }) do
                        local candidate = tool:GetAttribute(attributeName)
                        if candidate ~= nil and automationNamesEquivalent(candidate, seedName) then
                            return tool
                        end
                    end

                    local cleanedToolName = tostring(tool.Name or "")
                        :gsub("%s*%[[^%]]+%]%s*$", "")
                        :gsub("%s*[xX]%d+%s*$", "")
                        :gsub("^%s+", "")
                        :gsub("%s+$", "")

                    if automationNamesEquivalent(cleanedToolName, seedName) then
                        return tool
                    end
                end
            end
        end
    end

    return nil
end

local PLANT_MIN_DISTANCE = 1.5

local function getOccupiedPlantPositions(plot)
    local occupied = {}
    local plantsFolder = plot and plot:FindFirstChild("Plants")

    if plantsFolder then
        for _, plant in ipairs(plantsFolder:GetChildren()) do
            local position = getPlantPosition(plant)
            if position then
                table.insert(
                    occupied,
                    Vector3.new(position.X, 0, position.Z)
                )
            end
        end
    end

    return occupied
end

local function isPlantPositionTooClose(position, occupied)
    local flat = Vector3.new(position.X, 0, position.Z)

    for _, other in ipairs(occupied or {}) do
        if (flat - other).Magnitude < PLANT_MIN_DISTANCE then
            return true
        end
    end

    return false
end

local function getPlantSurfaceY(plot, fallbackY)
    local area = getPlantArea(plot)

    if area then
        local top =
            area.CFrame:PointToWorldSpace(
                Vector3.new(0, area.Size.Y / 2, 0)
            )
        return top.Y
    end

    return fallbackY
end

local function compactSprinklerName(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function sprinklerCandidateMatches(candidate, wanted)
    local compact = compactSprinklerName(candidate)
    if compact == "" or wanted == "" then
        return false
    end

    if compact == wanted then
        return true
    end

    if compact:sub(1, #wanted) == wanted then
        local suffix = compact:sub(#wanted + 1)
        if suffix ~= "" and suffix:match("^%d+$") then
            return true
        end
    end

    return false
end

local function findExistingSprinkler(plot)
    local sprinklers = plot and plot:FindFirstChild("Sprinklers")
    if not sprinklers then
        return nil
    end

    local wanted = compactSprinklerName(State.SprinklerType)
    if wanted == "" then
        return nil
    end

    for _, sprinkler in ipairs(sprinklers:GetChildren()) do
        if sprinkler:IsA("Model") then

            local candidates = { sprinkler.Name }
            for _, attributeName in ipairs({
                "SprinklerName",
                "Sprinkler",
                "GearName",
                "ItemName",
                "Type",
            }) do
                local value = sprinkler:GetAttribute(attributeName)
                if value ~= nil then
                    table.insert(candidates, value)
                end
            end

            for _, candidate in ipairs(candidates) do
                if sprinklerCandidateMatches(candidate, wanted) then
                    return sprinkler
                end
            end

            for _, object in ipairs(sprinkler:GetDescendants()) do
                if object:IsA("StringValue") then
                    local key = compactSprinklerName(object.Name)
                    if key == "sprinkler"
                        or key == "sprinklername"
                        or key == "gearname"
                        or key == "itemname"
                        or key == "type" then

                        if sprinklerCandidateMatches(object.Value, wanted) then
                            return sprinkler
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function chooseRandomPlantPosition(plot, occupied)
    local area = getPlantArea(plot)
    if not area then
        return nil
    end

    for _ = 1, 20 do
        local x =
            (math.random() - 0.5)
            * math.max(area.Size.X - 2, 1)

        local z =
            (math.random() - 0.5)
            * math.max(area.Size.Z - 2, 1)

        local position =
            area.CFrame:PointToWorldSpace(
                Vector3.new(
                    x,
                    area.Size.Y / 2,
                    z
                )
            )

        if not isPlantPositionTooClose(position, occupied) then
            return position
        end
    end

    return nil
end

local function chooseSprinklerPlantPosition(plot, occupied)
    local sprinkler = findExistingSprinkler(plot)
    if not sprinkler then
        warn(
            "[ScoopHub] Auto Plant: selected "
                .. tostring(State.SprinklerType)
                .. " is not currently active in your garden; planting paused"
        )
        return nil
    end

    local center = sprinkler:GetPivot().Position
    local plantY = getPlantSurfaceY(plot, center.Y)

    local dataRadius = getSprinklerRadiusForType(State.SprinklerType)
    local radius = getSprinklerPlantRadiusForType(State.SprinklerType)
    State.SprinklerRadius = dataRadius

    for _ = 1, 15 do
        local angle = math.random() * math.pi * 2
        local distance = math.random() * radius

        local position =
            Vector3.new(
                center.X + math.cos(angle) * distance,
                plantY,
                center.Z + math.sin(angle) * distance
            )

        if not isPlantPositionTooClose(position, occupied) then
            return position
        end
    end

    local angle = math.random() * math.pi * 2
    local distance = math.random() * radius

    return Vector3.new(
        center.X + math.cos(angle) * distance,
        plantY,
        center.Z + math.sin(angle) * distance
    )
end

local function choosePlayerPlantPosition(plot)
    local character = LocalPlayer.Character
    local root =
        character
        and character:FindFirstChild("HumanoidRootPart")

    if not root then
        warn("[ScoopHub] Auto Plant: player position unavailable")
        return nil
    end

    local current = root.Position

    return Vector3.new(
        current.X,
        getPlantSurfaceY(plot, current.Y),
        current.Z
    )
end

local function choosePlantPosition(plot)
    local mode = tostring(State.PlantLocation or "Random")
    local occupied = getOccupiedPlantPositions(plot)

    if mode == "Sprinkler Radius" then
        return chooseSprinklerPlantPosition(plot, occupied)
    elseif mode == "Player Position" then
        return choosePlayerPlantPosition(plot)
    end

    return chooseRandomPlantPosition(plot, occupied)
end

local function parseKgFromName(value)
    local text = tostring(value or "")
    return tonumber(text:match("%[([%d%.]+)%s*[Kk][Gg]%]"))
        or tonumber(text:match("([%d%.]+)%s*[Kk][Gg]"))
end

local function getPlantWeight(plant, visualizer)
    if visualizer
        and type(visualizer.CalculatePlantWeight) == "function" then

        local ok, weight = pcall(function()
            return visualizer:CalculatePlantWeight(plant)
        end)

        if ok and type(weight) == "number" then
            return weight
        end
    end

    return tonumber(
        plant:GetAttribute("Weight")
        or plant:GetAttribute("Kg")
        or plant:GetAttribute("FruitWeight")
    ) or parseKgFromName(plant.Name)
end

local function getFruitWeight(fruit, visualizer)
    if visualizer
        and type(visualizer.CalculateFruitWeight) == "function" then

        local ok, weight = pcall(function()
            return visualizer:CalculateFruitWeight(fruit)
        end)

        if ok and type(weight) == "number" then
            return weight
        end
    end

    return tonumber(
        fruit:GetAttribute("Weight")
        or fruit:GetAttribute("Kg")
        or fruit:GetAttribute("FruitWeight")
    ) or parseKgFromName(fruit.Name)
end

local function findHarvestPrompt(plant)
    for _, object in ipairs(plant:GetDescendants()) do
        if object:IsA("ProximityPrompt") then
            local action =
                tostring(object.ActionText or ""):lower()

            if object.Name == "HarvestPrompt"
                or action:find("harvest", 1, true) then

                return object
            end
        end
    end

    return nil
end

local refreshSummary

local function recordAction(text)
    Stats.LastAction = tostring(text)

    if refreshSummary then
        refreshSummary()
    end
end

local lastAutomationDiagnostic = ""
local lastAutomationDiagnosticAt = 0
local function recordDiagnostic(text)
    text = tostring(text or "")
    local now = os.clock()
    if text ~= lastAutomationDiagnostic or now - lastAutomationDiagnosticAt >= 4 then
        lastAutomationDiagnostic = text
        lastAutomationDiagnosticAt = now
        recordAction(text)
    end
end

local TrowelRuntime = {}
do
local TrowelMovedPlantIds = {}
local TrowelQueuedPlantIds = {}
local TrowelQueue = {}
local TrowelDrainRunning = false
local TrowelSourceFolder = nil
local TrowelSourceAddedConnection = nil
local TrowelSourceRemovedConnection = nil
local TrowelRejectConnection = nil
local TrowelActivePlantId = nil
local TrowelActivePlantName = nil
local TrowelActiveAttempt = nil
local TrowelAttemptSerial = 0
local TrowelPlantOptions = { "All Plants" }
local TrowelMouse = LocalPlayer:GetMouse()
local TrowelSeedRarityByName = nil
local queueTrowelPass

local function getTrowelPlantId(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("PlantId")
        or plant:GetAttribute("Id")
        or plant:GetAttribute("PlantID")

    if value == nil then
        return nil
    end

    return tostring(value)
end

local function getTrowelPlantName(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("SeedName")
        or plant:GetAttribute("PlantName")

    if value == nil or tostring(value) == "" then
        return nil
    end

    return tostring(value)
end

local function getTrowelPlantRarity(plant)
    if not plant then
        return "Unknown"
    end

    local directRarity = plant:GetAttribute("Rarity")
        or plant:GetAttribute("SeedRarity")
        or plant:GetAttribute("PlantRarity")

    if directRarity ~= nil and tostring(directRarity) ~= "" then
        return tostring(directRarity)
    end

    local plantName = getTrowelPlantName(plant)
    if not plantName then
        return "Unknown"
    end

    if TrowelSeedRarityByName == nil then
        TrowelSeedRarityByName = {}

        pcall(function()
            local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
            local seedDataModule = sharedModules and sharedModules:FindFirstChild("SeedData")
            local seedData = seedDataModule and require(seedDataModule)

            if type(seedData) == "table" then
                for _, data in pairs(seedData) do
                    if type(data) == "table" and data.SeedName and data.Rarity then
                        local seedName = tostring(data.SeedName)
                        local rarity = tostring(data.Rarity)

                        TrowelSeedRarityByName[seedName] = rarity
                        TrowelSeedRarityByName[string.lower(seedName)] = rarity
                    end
                end
            end
        end)
    end

    return TrowelSeedRarityByName[plantName]
        or TrowelSeedRarityByName[string.lower(plantName)]
        or "Unknown"
end

local function trowelPlantMatches(plant)
    local plantName = getTrowelPlantName(plant)
    if not plantName then
        return false
    end

    if State.TrowelPlantName ~= "All Plants"
        and plantName ~= State.TrowelPlantName then
        return false
    end

    if State.TrowelRarity ~= "Any"
        and getTrowelPlantRarity(plant) ~= State.TrowelRarity then
        return false
    end

    return true
end

local function refreshTrowelPlantOptions()
    local names = {}
    local seen = {}

    local function addName(value)
        value = tostring(value or "")
        if value == "" or value == "All Plants" or seen[value] then
            return
        end
        seen[value] = true
        table.insert(names, value)
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if plantsFolder then
        for _, plant in ipairs(plantsFolder:GetChildren()) do
            addName(getTrowelPlantName(plant))
        end
    end

    addName(State.TrowelPlantName)

    table.sort(names)

    table.clear(TrowelPlantOptions)
    table.insert(TrowelPlantOptions, "All Plants")
    for _, name in ipairs(names) do
        table.insert(TrowelPlantOptions, name)
    end
end

local function findTrowelTool(container)
    local function scan(target)
        if not target then
            return nil
        end

        for _, object in ipairs(target:GetChildren()) do
            if object:IsA("Tool")
                and string.find(string.lower(object.Name), "trowel", 1, true) then
                return object
            end
        end

        return nil
    end

    if container then
        return scan(container)
    end

    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    return scan(character) or scan(backpack)
end

local function getEquippedTrowel()
    local character = LocalPlayer.Character
    return character and findTrowelTool(character) or nil
end

local function equipTrowelTool()
    local character = LocalPlayer.Character
    if not character then
        return false
    end

    local equipped = getEquippedTrowel()
    if equipped then
        return true
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local tool = backpack and findTrowelTool(backpack)
    if not tool then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)

    if not ok then
        return false
    end

    local deadline = os.clock() + 0.6
    repeat
        if getEquippedTrowel() then
            return true
        end
        task.wait(0.03)
    until os.clock() >= deadline

    return getEquippedTrowel() ~= nil
end

local function getTrowelPlantPosition(plant)
    if not plant or not plant.Parent then
        return nil
    end

    if plant:IsA("Model") then
        local ok, pivot = pcall(function()
            return plant:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    elseif plant:IsA("BasePart") then
        return plant.Position
    end

    local part = plant:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function trowelPlantReachedTarget(plant, target)
    local position = getTrowelPlantPosition(plant)
    if not position or typeof(target) ~= "Vector3" then
        return false
    end

    return (position - target).Magnitude <= 2.5
end

local function clearActiveTrowelAttempt(attempt)
    if TrowelActiveAttempt == attempt then
        TrowelActiveAttempt = nil
    end

    if attempt and TrowelActivePlantId == attempt.PlantId then
        TrowelActivePlantId = nil
        TrowelActivePlantName = nil
    end
end

local function ensureTrowelRejectListener()
    if TrowelRejectConnection and TrowelRejectConnection.Connected then
        return
    end

    local networking = getNetworking()
    local rejected = networking
        and networking.Trowel
        and networking.Trowel.MoveRejected

    if not rejected or not rejected.OnClientEvent then
        return
    end

    TrowelRejectConnection = rejected.OnClientEvent:Connect(function(reason)

        local attempt = TrowelActiveAttempt
        if attempt then
            attempt.Rejected = true
            attempt.Reason = reason

            recordAction(
                "Auto Trowel rejected"
                .. (reason ~= nil and (": " .. tostring(reason)) or "")
            )
        end
    end)

    TrackConnection(TrowelRejectConnection)
end

local function clearTrowelQueue()
    table.clear(TrowelQueuedPlantIds)
    table.clear(TrowelQueue)
end

local function resetTrowelProgress(rescan)
    table.clear(TrowelMovedPlantIds)
    clearTrowelQueue()

    if rescan and State.TrowelEnabled and queueTrowelPass then
        queueTrowelPass()
    end
end

local function performTrowelMoveAttempt(plant, plantId, seedName, target, movePlant, runId)
    if not State.TrowelEnabled
        or State.TrowelRunId ~= runId
        or not plant
        or not plant.Parent then
        return false, "stopped", false
    end

    if trowelPlantReachedTarget(plant, target) then
        return true, "already_at_target", false
    end

    if not equipTrowelTool() then
        return false, "trowel_not_equipped", false
    end

    if not getEquippedTrowel() and not equipTrowelTool() then
        return false, "trowel_not_equipped", false
    end

    TrowelAttemptSerial += 1
    local attempt = {
        Serial = TrowelAttemptSerial,
        PlantId = plantId,
        PlantName = seedName,
        Rejected = false,
        Reason = nil,
    }

    TrowelActiveAttempt = attempt
    TrowelActivePlantId = plantId
    TrowelActivePlantName = seedName

    local fired = pcall(function()
        movePlant:Fire(
            tostring(plantId),
            target,
            0
        )
    end)

    if not fired then
        clearActiveTrowelAttempt(attempt)
        return false, "fire_failed", false
    end

    local deadline = os.clock() + 0.85
    while os.clock() < deadline
        and State.TrowelEnabled
        and State.TrowelRunId == runId
        and plant
        and plant.Parent do

        if trowelPlantReachedTarget(plant, target) then
            clearActiveTrowelAttempt(attempt)
            return true, "confirmed", true
        end

        if attempt.Rejected then

            task.wait(0.08)
            local movedAnyway = trowelPlantReachedTarget(plant, target)
            clearActiveTrowelAttempt(attempt)

            if movedAnyway then
                return true, "moved_despite_rejection", true
            end

            return false,
                "rejected"
                .. (attempt.Reason ~= nil and (": " .. tostring(attempt.Reason)) or ""),
                true
        end

        task.wait(0.05)
    end

    local confirmed = trowelPlantReachedTarget(plant, target)
    clearActiveTrowelAttempt(attempt)

    if confirmed then
        return true, "confirmed", true
    end

    return false, "unconfirmed", true
end

local function allMatchingTrowelPlantsAtTarget()
    if not State.TrowelPosition then
        return false
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        return false
    end

    local foundMatchingPlant = false

    for _, plant in ipairs(plantsFolder:GetChildren()) do
        local plantId = getTrowelPlantId(plant)
        if plantId and trowelPlantMatches(plant) then
            foundMatchingPlant = true

            if not trowelPlantReachedTarget(plant, State.TrowelPosition) then
                return false
            end
        end
    end

    return foundMatchingPlant
end

local function autoFinishTrowelIfComplete(runId)
    if not State.TrowelEnabled
        or State.TrowelRunId ~= runId
        or TrowelDrainRunning
        or TrowelActivePlantId ~= nil
        or #TrowelQueue > 0
        or not allMatchingTrowelPlantsAtTarget() then
        return
    end

    local onCompleted = TrowelRuntime.OnCompleted
    if type(onCompleted) ~= "function" then
        return
    end

    task.defer(function()
        if State.TrowelEnabled
            and State.TrowelRunId == runId
            and not TrowelDrainRunning
            and TrowelActivePlantId == nil
            and #TrowelQueue == 0
            and allMatchingTrowelPlantsAtTarget() then
            onCompleted()
        end
    end)
end

local function queueTrowelPlant(plant)
    if not State.TrowelEnabled
        or not State.TrowelPosition
        or not plant
        or not plant.Parent then
        return
    end

    local plantId = getTrowelPlantId(plant)
    if not plantId
        or TrowelQueuedPlantIds[plantId]
        or TrowelActivePlantId == plantId
        or not trowelPlantMatches(plant) then
        return
    end

    if trowelPlantReachedTarget(plant, State.TrowelPosition) then
        TrowelMovedPlantIds[plantId] = true
        return
    end

    TrowelMovedPlantIds[plantId] = nil
    TrowelQueuedPlantIds[plantId] = true
    table.insert(TrowelQueue, plant)

    if TrowelDrainRunning then
        return
    end

    TrowelDrainRunning = true
    local runId = State.TrowelRunId

    task.spawn(function()
        while ScoopHubRunAlive()
            and SG.Parent
            and State.TrowelEnabled
            and State.TrowelRunId == runId
            and #TrowelQueue > 0 do

            local current = table.remove(TrowelQueue, 1)
            local currentId = getTrowelPlantId(current)

            if current
                and current.Parent
                and currentId
                and not TrowelMovedPlantIds[currentId]
                and trowelPlantMatches(current) then

                ensureTrowelRejectListener()

                local networking = getNetworking()
                local movePlant = networking
                    and networking.Trowel
                    and networking.Trowel.MovePlant

                if not movePlant then
                    recordDiagnostic("Auto Trowel: Trowel.MovePlant unavailable")
                    if currentId then
                        TrowelQueuedPlantIds[currentId] = nil
                    end
                    clearTrowelQueue()
                    break
                end

                local target = State.TrowelPosition
                local seedName = getTrowelPlantName(current) or "Unknown"

                local success, reason, didFire = performTrowelMoveAttempt(
                    current,
                    currentId,
                    seedName,
                    target,
                    movePlant,
                    runId
                )
                local anyFired = didFire == true

                if not success
                    and reason ~= "stopped"
                    and State.TrowelEnabled
                    and State.TrowelRunId == runId
                    and current
                    and current.Parent then

                    task.wait(0.35)

                    local retrySuccess, retryReason, retryFired = performTrowelMoveAttempt(
                        current,
                        currentId,
                        seedName,
                        target,
                        movePlant,
                        runId
                    )

                    success = retrySuccess
                    reason = retryReason
                    anyFired = anyFired or retryFired == true
                end

                if success then
                    TrowelMovedPlantIds[currentId] = true
                    if anyFired then
                        Stats.Trowels += 1
                        recordAction("Troweled " .. seedName)
                    end
                else
                    TrowelMovedPlantIds[currentId] = nil

                    if reason == "trowel_not_equipped" then
                        recordDiagnostic("Auto Trowel: Trowel tool not found/equipped")
                    elseif reason ~= "stopped" then
                        recordDiagnostic("Auto Trowel: " .. tostring(reason))
                    end
                end

                TrowelQueuedPlantIds[currentId] = nil

                local delay = math.clamp(
                    tonumber(State.TrowelDelay) or 1,
                    0.05,
                    5
                )
                task.wait(delay)
            elseif currentId then
                TrowelQueuedPlantIds[currentId] = nil
            end
        end

        clearActiveTrowelAttempt(TrowelActiveAttempt)
        TrowelDrainRunning = false

        if State.TrowelEnabled
            and State.TrowelPosition
            and #TrowelQueue > 0 then

            local pending = table.remove(TrowelQueue, 1)
            local pendingId = getTrowelPlantId(pending)
            if pendingId then
                TrowelQueuedPlantIds[pendingId] = nil
            end
            queueTrowelPlant(pending)
        else

            autoFinishTrowelIfComplete(runId)
        end
    end)
end

local function queueTrowelPlantWhenReady(plant)
    task.spawn(function()
        for _ = 1, 20 do
            if not State.TrowelEnabled or not plant or not plant.Parent then
                return
            end

            if getTrowelPlantId(plant) and getTrowelPlantName(plant) then
                queueTrowelPlant(plant)
                return
            end

            task.wait(0.1)
        end
    end)
end

local function bindTrowelPlantSource()
    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")

    if plantsFolder == TrowelSourceFolder then
        return plantsFolder
    end

    if TrowelSourceAddedConnection then
        pcall(function() TrowelSourceAddedConnection:Disconnect() end)
        TrowelSourceAddedConnection = nil
    end

    if TrowelSourceRemovedConnection then
        pcall(function() TrowelSourceRemovedConnection:Disconnect() end)
        TrowelSourceRemovedConnection = nil
    end

    TrowelSourceFolder = plantsFolder

    if plantsFolder then
        TrowelSourceAddedConnection = plantsFolder.ChildAdded:Connect(function(plant)
            if State.TrowelEnabled then
                queueTrowelPlantWhenReady(plant)
            end
        end)

        TrowelSourceRemovedConnection = plantsFolder.ChildRemoved:Connect(function(plant)
            local plantId = getTrowelPlantId(plant)
            if plantId then
                TrowelMovedPlantIds[plantId] = nil
                TrowelQueuedPlantIds[plantId] = nil
            end
        end)

        TrackConnection(TrowelSourceAddedConnection)
        TrackConnection(TrowelSourceRemovedConnection)
    end

    return plantsFolder
end

queueTrowelPass = function()
    if not State.TrowelEnabled or not State.TrowelPosition then
        return
    end

    local plantsFolder = bindTrowelPlantSource()
    if not plantsFolder then
        recordDiagnostic("Auto Trowel: your garden plot was not found")
        return
    end

    for _, plant in ipairs(plantsFolder:GetChildren()) do
        queueTrowelPlant(plant)
    end
end

local function startAutoTrowel()
    if not State.TrowelPosition then
        return false
    end

    State.TrowelRunId += 1
    local runId = State.TrowelRunId
    clearTrowelQueue()
    table.clear(TrowelMovedPlantIds)
    ensureTrowelRejectListener()
    bindTrowelPlantSource()
    queueTrowelPass()

    autoFinishTrowelIfComplete(runId)

    return true
end

local function stopAutoTrowel()
    State.TrowelRunId += 1
    clearTrowelQueue()
    TrowelActiveAttempt = nil
    TrowelActivePlantId = nil
    TrowelActivePlantName = nil
end

refreshTrowelPlantOptions()

TrowelRuntime.PlantOptions = TrowelPlantOptions
TrowelRuntime.Mouse = TrowelMouse
TrowelRuntime.QueuePass = queueTrowelPass
TrowelRuntime.RefreshPlantOptions = refreshTrowelPlantOptions
TrowelRuntime.ResetProgress = resetTrowelProgress
TrowelRuntime.BindPlantSource = bindTrowelPlantSource
TrowelRuntime.Start = startAutoTrowel
TrowelRuntime.Stop = stopAutoTrowel
end

local AutoPotRuntime = {}
do
local AUTO_POT_DELAY = 0.10
local AUTO_POT_CONFIRM_TIMEOUT = 4
local AutoPotPlantOptions = { "All Plants" }
local AutoPotRunId = 0
local AutoPotPottedThisRun = 0
local AutoPotCurrentPlantName = nil
local AutoPotStatusText = "Off"

local function getAutoPotPlantId(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("PlantId")
        or plant:GetAttribute("Id")
        or plant:GetAttribute("PlantID")

    if value == nil then
        return nil
    end

    return tostring(value)
end

local function getAutoPotPlantName(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("SeedName")
        or plant:GetAttribute("PlantName")

    if value == nil or tostring(value) == "" then
        return nil
    end

    return tostring(value)
end

local function getAutoPotSelectionLookup()
    local lookup = {}
    for _, value in ipairs(State.PotPlantNames or {}) do
        lookup[tostring(value)] = true
    end
    return lookup
end

local function autoPotPlantMatches(plant)
    local plantName = getAutoPotPlantName(plant)
    if not plantName or not getAutoPotPlantId(plant) then
        return false
    end

    local selected = getAutoPotSelectionLookup()
    if selected["All Plants"] then
        return true
    end

    return selected[plantName] == true
end

local function refreshAutoPotPlantOptions()
    local names = {}
    local seen = {}

    local function addName(value)
        value = tostring(value or "")
        if value == "" or value == "All Plants" or seen[value] then
            return
        end
        seen[value] = true
        table.insert(names, value)
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if plantsFolder then
        for _, plant in ipairs(plantsFolder:GetChildren()) do
            addName(getAutoPotPlantName(plant))
        end
    end

    for _, savedName in ipairs(State.PotPlantNames or {}) do
        addName(savedName)
    end

    table.sort(names)
    table.clear(AutoPotPlantOptions)
    table.insert(AutoPotPlantOptions, "All Plants")
    for _, name in ipairs(names) do
        table.insert(AutoPotPlantOptions, name)
    end
end

local function findAutoPotPlantById(plantsFolder, plantId)
    if not plantsFolder or not plantId then
        return nil
    end

    plantId = tostring(plantId)
    for _, plant in ipairs(plantsFolder:GetChildren()) do
        if getAutoPotPlantId(plant) == plantId then
            return plant
        end
    end

    return nil
end

local function findAutoPotPottedItem(plantId)
    plantId = tostring(plantId or "")

    local function scan(container)
        if not container then
            return nil
        end

        for _, item in ipairs(container:GetChildren()) do
            if item:GetAttribute("PottedPlant") == true
                and tostring(item:GetAttribute("Id") or "") == plantId then
                return item
            end
        end

        return nil
    end

    return scan(LocalPlayer:FindFirstChild("Backpack"))
        or scan(LocalPlayer.Character)
end

local function getAutoPotToolCount(tool)
    if not tool or not tool:IsA("Tool") or tool:GetAttribute("EmptyPot") == nil then
        return 0
    end

    local count = tonumber(tool:GetAttribute("Count"))
    if count ~= nil then
        return math.max(0, math.floor(count))
    end

    return 1
end

local function getAutoPotsLeft()
    local total = 0

    local function scan(container)
        if not container then
            return
        end

        for _, object in ipairs(container:GetChildren()) do
            total += getAutoPotToolCount(object)
        end
    end

    scan(LocalPlayer:FindFirstChild("Backpack"))
    scan(LocalPlayer.Character)

    return total
end

local function findAvailableAutoPotTool()
    local function scan(container)
        if not container then
            return nil
        end

        for _, object in ipairs(container:GetChildren()) do
            if object:IsA("Tool")
                and object:GetAttribute("EmptyPot") ~= nil
                and getAutoPotToolCount(object) > 0 then
                return object
            end
        end

        return nil
    end

    return scan(LocalPlayer.Character)
        or scan(LocalPlayer:FindFirstChild("Backpack"))
end

local function equipAutoPotTool(runId)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then
        return nil, "character is not ready"
    end

    local tool = findAvailableAutoPotTool()
    if not tool then
        return nil, "no empty pots left"
    end

    if tool.Parent == character then
        return tool
    end

    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    if not ok then
        return nil, "could not equip an empty pot"
    end

    local deadline = os.clock() + 1.2
    while ScoopHubRunAlive()
        and State.PotEnabled
        and runId == AutoPotRunId
        and os.clock() < deadline do
        if tool.Parent == character then

            task.wait(0.12)
            return tool
        end
        task.wait(0.03)
    end

    if tool.Parent == character then
        return tool
    end

    return nil, "could not equip an empty pot"
end

local function countMatchingAutoPotPlants()
    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        return 0
    end

    local count = 0
    for _, plant in ipairs(plantsFolder:GetChildren()) do
        if autoPotPlantMatches(plant) then
            count += 1
        end
    end

    return count
end

local function getNextAutoPotPlant()
    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        return nil, nil
    end

    local candidates = {}
    for _, plant in ipairs(plantsFolder:GetChildren()) do
        if autoPotPlantMatches(plant) then
            table.insert(candidates, plant)
        end
    end

    table.sort(candidates, function(a, b)
        local aName = string.lower(getAutoPotPlantName(a) or "")
        local bName = string.lower(getAutoPotPlantName(b) or "")
        if aName == bName then
            return (getAutoPotPlantId(a) or "") < (getAutoPotPlantId(b) or "")
        end
        return aName < bName
    end)

    return candidates[1], plantsFolder
end

local function updateAutoPotCardStatus()
    local statusLabel = AutoPotRuntime.StatusLabel
    if not statusLabel or not statusLabel.Parent then
        return
    end

    local prefix = AutoPotStatusText
    if State.PotEnabled and AutoPotCurrentPlantName then
        prefix = "Potting " .. AutoPotCurrentPlantName
    elseif State.PotEnabled then
        prefix = "Running"
    end

    statusLabel.Text = string.format(
        "%s  \u{2022}  %d potted  \u{2022}  %d on plot  \u{2022}  %d pots left",
        prefix,
        AutoPotPottedThisRun,
        countMatchingAutoPotPlants(),
        getAutoPotsLeft()
    )

    statusLabel.TextColor3 = State.PotEnabled and T.Success or T.Muted
end

local function waitForAutoPotConfirmation(plantsFolder, plantId, runId)
    local deadline = os.clock() + AUTO_POT_CONFIRM_TIMEOUT

    while ScoopHubRunAlive()
        and State.PotEnabled
        and runId == AutoPotRunId
        and os.clock() < deadline do
        local originalExists = findAutoPotPlantById(plantsFolder, plantId) ~= nil
        local pottedItem = findAutoPotPottedItem(plantId)

        if not originalExists and pottedItem then
            return true
        end

        task.wait(0.05)
    end

    return findAutoPotPlantById(plantsFolder, plantId) == nil
end

local function finishAutoPotRun(runId, reason, detail)
    if runId ~= AutoPotRunId then
        return
    end

    State.PotEnabled = false
    AutoPotRunId += 1
    AutoPotCurrentPlantName = nil

    if reason == "complete" then
        AutoPotStatusText = "Complete"
    elseif reason == "no_pots" then
        AutoPotStatusText = "No pots left"
    elseif reason == "failed" then
        AutoPotStatusText = "Failed"
    else
        AutoPotStatusText = "Stopped"
    end

    updateAutoPotCardStatus()

    if type(AutoPotRuntime.OnFinished) == "function" then
        pcall(AutoPotRuntime.OnFinished, reason, detail)
    end
end

local function startAutoPot()
    if type(State.PotPlantNames) ~= "table" or #State.PotPlantNames == 0 then
        AutoPotStatusText = "Select plants"
        updateAutoPotCardStatus()
        return false, "Auto Pot: select at least one plant"
    end

    local networking = getNetworking()
    local remote = networking and networking.Garden and networking.Garden.PotPlant
    if not remote or type(remote.Fire) ~= "function" then
        AutoPotStatusText = "Unavailable"
        updateAutoPotCardStatus()
        return false, "Auto Pot: Garden.PotPlant unavailable"
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        AutoPotStatusText = "No plot"
        updateAutoPotCardStatus()
        return false, "Auto Pot: your garden plot was not found"
    end

    if countMatchingAutoPotPlants() <= 0 then
        AutoPotStatusText = "Nothing to pot"
        updateAutoPotCardStatus()
        return false, "Auto Pot: no matching plants on your plot"
    end

    if getAutoPotsLeft() <= 0 then
        AutoPotStatusText = "No pots left"
        updateAutoPotCardStatus()
        return false, "Auto Pot: no empty pots left"
    end

    AutoPotRunId += 1
    local runId = AutoPotRunId
    AutoPotPottedThisRun = 0
    AutoPotCurrentPlantName = nil
    AutoPotStatusText = "Running"
    updateAutoPotCardStatus()

    task.spawn(function()
        while ScoopHubRunAlive()
            and State.PotEnabled
            and runId == AutoPotRunId do

            local plant, currentPlantsFolder = getNextAutoPotPlant()
            if not plant or not currentPlantsFolder then
                finishAutoPotRun(runId, "complete", "all matching plants are potted")
                return
            end

            if getAutoPotsLeft() <= 0 then
                finishAutoPotRun(runId, "no_pots", "no empty pots left")
                return
            end

            local plantId = getAutoPotPlantId(plant)
            local plantName = getAutoPotPlantName(plant) or "Unknown"
            if not plantId then
                task.wait(0.05)
                continue
            end

            AutoPotCurrentPlantName = plantName
            updateAutoPotCardStatus()

            local tool, equipError = equipAutoPotTool(runId)
            if not tool then
                finishAutoPotRun(runId, getAutoPotsLeft() <= 0 and "no_pots" or "failed", equipError)
                return
            end

            if not findAutoPotPlantById(currentPlantsFolder, plantId) then
                AutoPotCurrentPlantName = nil
                task.wait(0.03)
                continue
            end

            local fired, fireError = pcall(function()
                remote:Fire(plantId)
            end)

            if not fired then
                finishAutoPotRun(runId, "failed", tostring(fireError))
                return
            end

            local confirmed = waitForAutoPotConfirmation(currentPlantsFolder, plantId, runId)

            if not confirmed
                and State.PotEnabled
                and runId == AutoPotRunId
                and findAutoPotPlantById(currentPlantsFolder, plantId) then

                task.wait(0.35)

                if State.PotEnabled
                    and runId == AutoPotRunId
                    and findAutoPotPlantById(currentPlantsFolder, plantId) then
                    pcall(function()
                        remote:Fire(plantId)
                    end)
                    confirmed = waitForAutoPotConfirmation(currentPlantsFolder, plantId, runId)
                end
            end

            if not State.PotEnabled or runId ~= AutoPotRunId then
                return
            end

            if not confirmed then
                finishAutoPotRun(runId, "failed", "could not confirm " .. plantName)
                return
            end

            AutoPotPottedThisRun += 1
            Stats.Potted += 1
            AutoPotCurrentPlantName = nil
            recordAction("Auto Pot: potted " .. plantName)
            updateAutoPotCardStatus()

            local deadline = os.clock() + AUTO_POT_DELAY
            while ScoopHubRunAlive()
                and State.PotEnabled
                and runId == AutoPotRunId
                and os.clock() < deadline do
                task.wait(0.02)
            end
        end
    end)

    return true
end

local function stopAutoPot()
    AutoPotRunId += 1
    AutoPotCurrentPlantName = nil
    AutoPotStatusText = "Off"
    updateAutoPotCardStatus()
end

refreshAutoPotPlantOptions()

AutoPotRuntime.PlantOptions = AutoPotPlantOptions
AutoPotRuntime.RefreshPlantOptions = refreshAutoPotPlantOptions
AutoPotRuntime.CountMatchingPlants = countMatchingAutoPotPlants
AutoPotRuntime.GetPotsLeft = getAutoPotsLeft
AutoPotRuntime.UpdateCardStatus = updateAutoPotCardStatus
AutoPotRuntime.Start = startAutoPot
AutoPotRuntime.Stop = stopAutoPot
end

local AutoMergeRuntime = {}
do
local AUTO_MERGE_CONFIRM_TIMEOUT = 12
local AUTO_MERGE_IDLE_DELAY = 0.50
local AUTO_MERGE_TOO_FAR_DELAY = 1.00
local AUTO_MERGE_BUSY_DELAY = 0.75

local AutoMergeRunId = 0
local AutoMergeMergedThisRun = 0
local AutoMergeStatusText = "Off"
local AutoMergeDetailText = "Moon Bloom + Sun Bloom → Eclipse Bloom"
local AutoMergeOwnPlantsFolder = nil
local AutoMergeReservedSunIds = {}
local AutoMergeReservedMoonIds = {}
local AutoMergeLastTooFarSunId = nil
local AutoMergeLastTooFarMoonId = nil
local AutoMergeLastTooFarDistance = nil
local AutoMergeLastAcceptedSunId = nil
local AutoMergeLastAcceptedMoonId = nil

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

do
    local standalone = rawget(_G, "ScoopHubStandaloneAutoMerge")
    if type(standalone) == "table" then
        standalone.Enabled = false
        standalone.Alive = false
        standalone.RunId = (tonumber(standalone.RunId) or 0) + 1

        for _, connection in ipairs(standalone.Connections or {}) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        if standalone.Gui then
            pcall(function()
                standalone.Gui:Destroy()
            end)
        end
    end
end

local PresentationGate = rawget(_G, "ScoopHubAutoMergePresentationGate")
if type(PresentationGate) ~= "table" then
    PresentationGate = {
        Active = false,
        BlockUntil = 0,
        CutsceneInstalled = false,
        CutsceneMode = "none",
        MergeAnimationInstalled = false,
        MergeAnimationMode = "none",
        CutscenesBlocked = 0,
        MergeAnimationsBlocked = 0,
    }
    _G.ScoopHubAutoMergePresentationGate = PresentationGate
end

PresentationGate.Active = false
PresentationGate.BlockUntil = 0

local OfflineAnimationGui = nil
local OfflineAnimationWasEnabled = nil
local OfflineAnimationEnabledConnection = nil
local EclipseMergeFlashGui = nil
local EclipseMergeFlashWasEnabled = nil
local EclipseMergeFlashEnabledConnection = nil

local function getAutoMergePlantId(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("PlantId")
        or plant:GetAttribute("Id")
        or plant:GetAttribute("PlantID")

    if value == nil then
        return nil
    end

    return tostring(value)
end

local function getAutoMergePlantName(plant)
    if not plant then
        return nil
    end

    local value = plant:GetAttribute("SeedName")
        or plant:GetAttribute("PlantName")

    if value == nil or tostring(value) == "" then
        return nil
    end

    return tostring(value)
end

local function getAutoMergePlantPosition(plant)
    if not plant then
        return nil
    end

    if plant:IsA("Model") then
        local ok, pivot = pcall(function()
            return plant:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    elseif plant:IsA("BasePart") then
        return plant.Position
    end

    local part = plant:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function getAutoMergePlantsFolder()
    local cached = AutoMergeOwnPlantsFolder
    if cached and cached.Parent then
        return cached
    end

    AutoMergeOwnPlantsFolder = nil

    local plot = getPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if plants then
        AutoMergeOwnPlantsFolder = plants
    end

    return plants
end

local function findAutoMergePlantById(plantsFolder, plantId)
    if not plantsFolder or not plantId then
        return nil
    end

    plantId = tostring(plantId)
    for _, plant in ipairs(plantsFolder:GetChildren()) do
        if getAutoMergePlantId(plant) == plantId then
            return plant
        end
    end

    return nil
end

local function getAutoMergeCounts()
    local plantsFolder = getAutoMergePlantsFolder()
    if not plantsFolder then
        return 0, 0
    end

    local moon = 0
    local sun = 0

    for _, plant in ipairs(plantsFolder:GetChildren()) do
        local plantName = getAutoMergePlantName(plant)
        if plantName == "Moon Bloom" then
            moon += 1
        elseif plantName == "Sun Bloom" then
            sun += 1
        end
    end

    return moon, sun
end

local function getClosestAutoMergePair()
    local plantsFolder = getAutoMergePlantsFolder()
    if not plantsFolder then
        return nil, nil, nil, nil
    end

    local suns = {}
    local moons = {}

    for _, plant in ipairs(plantsFolder:GetChildren()) do
        local plantName = getAutoMergePlantName(plant)
        local plantId = getAutoMergePlantId(plant)

        if plantId then
            if plantName == "Sun Bloom"
                and not AutoMergeReservedSunIds[plantId] then
                suns[#suns + 1] = {
                    Plant = plant,
                    Position = getAutoMergePlantPosition(plant),
                }
            elseif plantName == "Moon Bloom"
                and not AutoMergeReservedMoonIds[plantId] then
                moons[#moons + 1] = {
                    Plant = plant,
                    Position = getAutoMergePlantPosition(plant),
                }
            end
        end
    end

    if #suns == 0 or #moons == 0 then
        return nil, nil, plantsFolder, nil
    end

    local bestSun = nil
    local bestMoon = nil
    local bestDistance = math.huge

    for _, sunEntry in ipairs(suns) do
        if sunEntry.Position then
            for _, moonEntry in ipairs(moons) do
                if moonEntry.Position then
                    local distance = (sunEntry.Position - moonEntry.Position).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
                        bestSun = sunEntry.Plant
                        bestMoon = moonEntry.Plant
                    end
                end
            end
        end
    end

    if not bestSun or not bestMoon then
        return suns[1].Plant, moons[1].Plant, plantsFolder, nil
    end

    return bestSun, bestMoon, plantsFolder, bestDistance
end

local function waitForAutoMergeSourcesGone(plantsFolder, sunId, moonId, runId)
    if not plantsFolder or not plantsFolder.Parent then
        return false
    end

    local sunGone = findAutoMergePlantById(plantsFolder, sunId) == nil
    local moonGone = findAutoMergePlantById(plantsFolder, moonId) == nil

    if sunGone and moonGone then
        return true
    end

    local connection
    connection = plantsFolder.ChildRemoved:Connect(function(plant)
        local removedId = getAutoMergePlantId(plant)
        if removedId == sunId then
            sunGone = true
        elseif removedId == moonId then
            moonGone = true
        end
    end)

    local deadline = os.clock() + AUTO_MERGE_CONFIRM_TIMEOUT

    while ScoopHubRunAlive()
        and State.MergeEnabled
        and runId == AutoMergeRunId
        and os.clock() < deadline
        and not (sunGone and moonGone) do
        task.wait(0.10)
    end

    pcall(function()
        connection:Disconnect()
    end)

    return sunGone and moonGone
end

local function shouldBlockAutoMergePresentation()
    return PresentationGate.Active == true
        and os.clock() <= (tonumber(PresentationGate.BlockUntil) or 0)
end

local function installAutoMergeCutsceneHook()
    if PresentationGate.CutsceneInstalled then
        return true
    end

    if type(hookfunction) ~= "function" then
        return false
    end

    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local controllers = scripts and scripts:FindFirstChild("Controllers")
    local moduleScript = controllers and controllers:FindFirstChild("OfflineGrowthAnimationController")

    if moduleScript and moduleScript:IsA("ModuleScript") then
        local okRequire, controller = pcall(require, moduleScript)
        if okRequire and type(controller) == "table"
            and type(controller.PlayOfflineCutscene) == "function" then
            local original
            local okHook = pcall(function()
                original = hookfunction(controller.PlayOfflineCutscene, function(...)
                    if shouldBlockAutoMergePresentation() then
                        PresentationGate.CutscenesBlocked = (PresentationGate.CutscenesBlocked or 0) + 1
                        return nil
                    end
                    return original(...)
                end)
            end)

            if okHook then
                PresentationGate.CutsceneInstalled = true
                PresentationGate.CutsceneMode = "controller-table"
                return true
            end
        end
    end

    if type(getgc) ~= "function"
        or not debug
        or type(debug.info) ~= "function" then
        return false
    end

    local candidate = nil
    pcall(function()
        for _, object in ipairs(getgc(true)) do
            if type(object) == "function" then
                local okInfo, source, name = pcall(function()
                    return debug.info(object, "sn")
                end)

                if okInfo
                    and tostring(name or "") == "PlayOfflineCutscene"
                    and string.find(
                        string.lower(tostring(source or "")),
                        "offlinegrowthanimationcontroller",
                        1,
                        true
                    ) then
                    candidate = object
                    break
                end
            end
        end
    end)

    if type(candidate) ~= "function" then
        return false
    end

    local original
    local okHook = pcall(function()
        original = hookfunction(candidate, function(...)
            if shouldBlockAutoMergePresentation() then
                PresentationGate.CutscenesBlocked = (PresentationGate.CutscenesBlocked or 0) + 1
                return nil
            end
            return original(...)
        end)
    end)

    if okHook then
        PresentationGate.CutsceneInstalled = true
        PresentationGate.CutsceneMode = "getgc-function"
        return true
    end

    return false
end

local function installAutoMergeAnimationHook()
    if PresentationGate.MergeAnimationInstalled then
        return true
    end

    if type(hookfunction) ~= "function" then
        return false
    end

    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local controllers = scripts and scripts:FindFirstChild("Controllers")
    local moduleScript = controllers and controllers:FindFirstChild("EclipseMergeController")

    if moduleScript and moduleScript:IsA("ModuleScript") then
        local okRequire, controller = pcall(require, moduleScript)
        if okRequire and type(controller) == "table" then
            local candidate = controller.playMergeAnimation or controller.PlayMergeAnimation
            if type(candidate) == "function" then
                local original
                local okHook = pcall(function()
                    original = hookfunction(candidate, function(...)
                        if shouldBlockAutoMergePresentation() then
                            PresentationGate.MergeAnimationsBlocked = (PresentationGate.MergeAnimationsBlocked or 0) + 1
                            return nil
                        end
                        return original(...)
                    end)
                end)

                if okHook then
                    PresentationGate.MergeAnimationInstalled = true
                    PresentationGate.MergeAnimationMode = "controller-table"
                    return true
                end
            end
        end
    end

    if type(getgc) ~= "function"
        or not debug
        or type(debug.info) ~= "function" then
        return false
    end

    local candidate = nil
    pcall(function()
        for _, object in ipairs(getgc(true)) do
            if type(object) == "function" then
                local okInfo, source, name = pcall(function()
                    return debug.info(object, "sn")
                end)

                if okInfo
                    and string.lower(tostring(name or "")) == "playmergeanimation"
                    and string.find(
                        string.lower(tostring(source or "")),
                        "eclipsemergecontroller",
                        1,
                        true
                    ) then
                    candidate = object
                    break
                end
            end
        end
    end)

    if type(candidate) ~= "function" then
        return false
    end

    local original
    local okHook = pcall(function()
        original = hookfunction(candidate, function(...)
            if shouldBlockAutoMergePresentation() then
                PresentationGate.MergeAnimationsBlocked = (PresentationGate.MergeAnimationsBlocked or 0) + 1
                return nil
            end
            return original(...)
        end)
    end)

    if okHook then
        PresentationGate.MergeAnimationInstalled = true
        PresentationGate.MergeAnimationMode = "getgc-function"
        return true
    end

    return false
end

local function getOfflineAnimationGui()
    local gui = PlayerGui:FindFirstChild("OfflineAnimation")
    return gui and gui:IsA("ScreenGui") and gui or nil
end

local function getEclipseMergeFlashGui()
    local gui = PlayerGui:FindFirstChild("EclipseMergeFlash")
    return gui and gui:IsA("ScreenGui") and gui or nil
end

local function bindOfflineAnimationGui(gui)
    if not gui or not gui:IsA("ScreenGui") then
        return
    end

    if OfflineAnimationGui == gui and OfflineAnimationEnabledConnection then
        return
    end

    if OfflineAnimationEnabledConnection then
        pcall(function() OfflineAnimationEnabledConnection:Disconnect() end)
    end

    OfflineAnimationGui = gui
    if OfflineAnimationWasEnabled == nil then
        OfflineAnimationWasEnabled = gui.Enabled
    end

    OfflineAnimationEnabledConnection = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if (State.MergeEnabled or PresentationGate.Active) and gui.Enabled then
            task.defer(function()
                if ScoopHubRunAlive()
                    and (State.MergeEnabled or PresentationGate.Active)
                    and gui.Parent
                    and gui.Enabled then
                    gui.Enabled = false
                end
            end)
        end
    end)
    TrackConnection(OfflineAnimationEnabledConnection)

    if (State.MergeEnabled or PresentationGate.Active) and gui.Enabled then
        gui.Enabled = false
    end
end

local function bindEclipseMergeFlashGui(gui)
    if not gui or not gui:IsA("ScreenGui") then
        return
    end

    if EclipseMergeFlashGui == gui and EclipseMergeFlashEnabledConnection then
        return
    end

    if EclipseMergeFlashEnabledConnection then
        pcall(function() EclipseMergeFlashEnabledConnection:Disconnect() end)
    end

    EclipseMergeFlashGui = gui
    if EclipseMergeFlashWasEnabled == nil then
        EclipseMergeFlashWasEnabled = gui.Enabled
    end

    EclipseMergeFlashEnabledConnection = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if (State.MergeEnabled or PresentationGate.Active) and gui.Enabled then
            task.defer(function()
                if ScoopHubRunAlive()
                    and (State.MergeEnabled or PresentationGate.Active)
                    and gui.Parent
                    and gui.Enabled then
                    gui.Enabled = false
                end
            end)
        end
    end)
    TrackConnection(EclipseMergeFlashEnabledConnection)

    if (State.MergeEnabled or PresentationGate.Active) and gui.Enabled then
        gui.Enabled = false
    end
end

local function suppressAutoMergePresentationGuis()
    local offline = getOfflineAnimationGui()
    if offline then
        bindOfflineAnimationGui(offline)
        if offline.Enabled then
            offline.Enabled = false
        end
    end

    local flash = getEclipseMergeFlashGui()
    if flash then
        bindEclipseMergeFlashGui(flash)
        if flash.Enabled then
            flash.Enabled = false
        end
    end
end

local function restoreAutoMergePresentationGuis()
    local offline = OfflineAnimationGui
    if offline and offline.Parent and OfflineAnimationWasEnabled ~= nil then
        pcall(function()
            offline.Enabled = OfflineAnimationWasEnabled
        end)
    end

    local flash = EclipseMergeFlashGui
    if flash and flash.Parent and EclipseMergeFlashWasEnabled ~= nil then
        local frame = flash:FindFirstChild("Frame")
        if frame and frame:IsA("GuiObject") then
            pcall(function()
                frame.BackgroundTransparency = 1
            end)
        end
        pcall(function()
            flash.Enabled = EclipseMergeFlashWasEnabled
        end)
    end

    OfflineAnimationWasEnabled = nil
    EclipseMergeFlashWasEnabled = nil
end

local function autoMergePairStillPresent(sunId, moonId)
    local plantsFolder = getAutoMergePlantsFolder()
    if not plantsFolder or not sunId or not moonId then
        return false
    end

    return findAutoMergePlantById(plantsFolder, sunId) ~= nil
        or findAutoMergePlantById(plantsFolder, moonId) ~= nil
end

local function restoreAutoMergePresentationAfterPair(sunId, moonId)
    task.spawn(function()
        local deadline = os.clock() + 15

        while ScoopHubRunAlive()
            and not State.MergeEnabled
            and os.clock() < deadline do
            if not autoMergePairStillPresent(sunId, moonId) then
                task.wait(1.25)
                if ScoopHubRunAlive() and not State.MergeEnabled then
                    PresentationGate.Active = false
                    PresentationGate.BlockUntil = 0
                    restoreAutoMergePresentationGuis()
                end
                return
            end
            task.wait(0.10)
        end

        if ScoopHubRunAlive() and not State.MergeEnabled then
            PresentationGate.Active = false
            PresentationGate.BlockUntil = 0
            restoreAutoMergePresentationGuis()
        end
    end)
end

TrackConnection(PlayerGui.ChildAdded:Connect(function(child)
    if not child:IsA("ScreenGui") then
        return
    end

    if child.Name == "OfflineAnimation" then
        task.defer(function()
            if child.Parent then
                bindOfflineAnimationGui(child)
            end
        end)
    elseif child.Name == "EclipseMergeFlash" then
        task.defer(function()
            if child.Parent then
                bindEclipseMergeFlashGui(child)
            end
        end)
    end
end))

local function updateAutoMergeCardStatus()
    local moon, sun = getAutoMergeCounts()

    if AutoMergeRuntime.StatusLabel then
        AutoMergeRuntime.StatusLabel.Text = string.format(
            "%s  •  %d merged  •  %d Moon  •  %d Sun",
            AutoMergeStatusText,
            AutoMergeMergedThisRun,
            moon,
            sun
        )
        AutoMergeRuntime.StatusLabel.TextColor3 = State.MergeEnabled and T.Success or T.Muted
    end

    if AutoMergeRuntime.DetailLabel then
        AutoMergeRuntime.DetailLabel.Text = AutoMergeDetailText
    end
end

local function setAutoMergeStatus(status, detail)
    AutoMergeStatusText = tostring(status or "Running")
    if detail ~= nil then
        AutoMergeDetailText = tostring(detail)
    end
    updateAutoMergeCardStatus()
end

local function requestAutoMerge(remote, sunId, moonId)
    local ok, packedOrError = pcall(function()
        return table.pack(remote:Fire(sunId, moonId))
    end)

    if not ok then
        return false, tostring(packedOrError)
    end

    local packed = packedOrError
    return packed[1] == true,
        tostring(packed[2] or (packed[1] == true and "Merging!" or "Merge rejected"))
end

local function stopAutoMerge()
    AutoMergeRunId += 1
    AutoMergeStatusText = "Off"
    AutoMergeDetailText = "Moon Bloom + Sun Bloom → Eclipse Bloom"

    local lastSunId = AutoMergeLastAcceptedSunId
    local lastMoonId = AutoMergeLastAcceptedMoonId
    local stillResolving = autoMergePairStillPresent(lastSunId, lastMoonId)

    if stillResolving then
        PresentationGate.Active = true
        PresentationGate.BlockUntil = math.max(
            tonumber(PresentationGate.BlockUntil) or 0,
            os.clock() + 15
        )
        suppressAutoMergePresentationGuis()
        restoreAutoMergePresentationAfterPair(lastSunId, lastMoonId)
    else
        PresentationGate.Active = false
        PresentationGate.BlockUntil = 0
        restoreAutoMergePresentationGuis()
    end

    updateAutoMergeCardStatus()
end

local function startAutoMerge()
    local networking = getNetworking()
    local remote = networking and networking.Garden and networking.Garden.RequestMerge
    if not remote or type(remote.Fire) ~= "function" then
        setAutoMergeStatus("Unavailable", "Garden.RequestMerge unavailable")
        return false, "Auto Merge: Garden.RequestMerge unavailable"
    end

    if not installAutoMergeCutsceneHook() then
        setAutoMergeStatus("Unavailable", "PlayOfflineCutscene hook unavailable")
        return false, "Auto Merge: cutscene hook unavailable"
    end

    if not installAutoMergeAnimationHook() then
        setAutoMergeStatus("Unavailable", "Eclipse merge animation hook unavailable")
        return false, "Auto Merge: merge animation hook unavailable"
    end

    local plantsFolder = getAutoMergePlantsFolder()
    if not plantsFolder then
        setAutoMergeStatus("No plot", "Your garden Plants folder was not found")
        return false, "Auto Merge: your garden plot was not found"
    end

    AutoMergeRunId += 1
    local runId = AutoMergeRunId
    AutoMergeMergedThisRun = 0
    AutoMergeLastTooFarSunId = nil
    AutoMergeLastTooFarMoonId = nil
    AutoMergeLastTooFarDistance = nil
    AutoMergeLastAcceptedSunId = nil
    AutoMergeLastAcceptedMoonId = nil
    table.clear(AutoMergeReservedSunIds)
    table.clear(AutoMergeReservedMoonIds)

    PresentationGate.Active = true
    PresentationGate.BlockUntil = 0
    suppressAutoMergePresentationGuis()
    setAutoMergeStatus("Running", "Finding the closest Moon Bloom + Sun Bloom pair")

    task.spawn(function()
        while ScoopHubRunAlive()
            and State.MergeEnabled
            and runId == AutoMergeRunId do

            local sunPlant, moonPlant, currentPlantsFolder, pairDistance = getClosestAutoMergePair()

            if not currentPlantsFolder then
                setAutoMergeStatus("Waiting", "Your garden plot is not available")
                AutoMergeOwnPlantsFolder = nil
                task.wait(AUTO_MERGE_IDLE_DELAY)
                continue
            end

            if not sunPlant or not moonPlant then
                setAutoMergeStatus("Idle", "No complete Moon Bloom + Sun Bloom pair right now")
                task.wait(AUTO_MERGE_IDLE_DELAY)
                continue
            end

            local sunId = getAutoMergePlantId(sunPlant)
            local moonId = getAutoMergePlantId(moonPlant)
            if not sunId or not moonId then
                task.wait(0.25)
                continue
            end

            local sameRejectedPair = AutoMergeLastTooFarSunId == sunId
                and AutoMergeLastTooFarMoonId == moonId
            local distanceUnchanged = pairDistance ~= nil
                and AutoMergeLastTooFarDistance ~= nil
                and math.abs(pairDistance - AutoMergeLastTooFarDistance) < 0.50

            if sameRejectedPair and distanceUnchanged then
                setAutoMergeStatus(
                    "Waiting",
                    string.format("Closest pair is still too far apart (%.1f studs)", pairDistance)
                )
                task.wait(AUTO_MERGE_TOO_FAR_DELAY)
                continue
            end

            setAutoMergeStatus(
                "Running",
                pairDistance
                    and string.format("Requesting closest pair (%.1f studs)", pairDistance)
                    or "Requesting closest Moon Bloom + Sun Bloom pair"
            )

            PresentationGate.Active = true
            PresentationGate.BlockUntil = math.max(
                tonumber(PresentationGate.BlockUntil) or 0,
                os.clock() + 15
            )
            suppressAutoMergePresentationGuis()

            local accepted, message = requestAutoMerge(remote, sunId, moonId)

            if not State.MergeEnabled or runId ~= AutoMergeRunId then
                return
            end

            if not accepted then
                local lowerMessage = string.lower(tostring(message or ""))

                if string.find(lowerMessage, "already in progress", 1, true) then
                    setAutoMergeStatus("Waiting", "Server is still finishing the previous merge")
                    PresentationGate.BlockUntil = math.max(
                        tonumber(PresentationGate.BlockUntil) or 0,
                        os.clock() + 3
                    )
                    task.wait(AUTO_MERGE_BUSY_DELAY)
                    continue
                end

                if string.find(lowerMessage, "too far apart", 1, true) then
                    AutoMergeLastTooFarSunId = sunId
                    AutoMergeLastTooFarMoonId = moonId
                    AutoMergeLastTooFarDistance = pairDistance
                    PresentationGate.BlockUntil = 0

                    setAutoMergeStatus(
                        "Waiting",
                        pairDistance
                            and string.format("Closest pair is too far apart (%.1f studs)", pairDistance)
                            or "Closest pair is too far apart"
                    )
                    task.wait(AUTO_MERGE_TOO_FAR_DELAY)
                    continue
                end

                setAutoMergeStatus("Rejected", "Server response: " .. tostring(message))
                State.MergeEnabled = false
                if AutoMergeRuntime.Toggle then
                    AutoMergeRuntime.Toggle:Set(false, false)
                end
                stopAutoMerge()
                recordAction("Auto Merge stopped - " .. tostring(message))
                if refreshSummary then
                    refreshSummary()
                end
                return
            end

            AutoMergeReservedSunIds[sunId] = true
            AutoMergeReservedMoonIds[moonId] = true
            AutoMergeLastAcceptedSunId = sunId
            AutoMergeLastAcceptedMoonId = moonId
            AutoMergeLastTooFarSunId = nil
            AutoMergeLastTooFarMoonId = nil
            AutoMergeLastTooFarDistance = nil
            AutoMergeMergedThisRun += 1
            Stats.Merged += 1

            setAutoMergeStatus("Merging", "Server accepted: " .. tostring(message))
            recordAction("Auto Merge: Moon Bloom + Sun Bloom accepted")

            local finished = waitForAutoMergeSourcesGone(
                currentPlantsFolder,
                sunId,
                moonId,
                runId
            )

            if not State.MergeEnabled or runId ~= AutoMergeRunId then
                return
            end

            if not finished then
                setAutoMergeStatus("Failed", "Accepted merge did not finish within 12 seconds")
                State.MergeEnabled = false
                if AutoMergeRuntime.Toggle then
                    AutoMergeRuntime.Toggle:Set(false, false)
                end
                stopAutoMerge()
                recordAction("Auto Merge stopped - merge confirmation timed out")
                if refreshSummary then
                    refreshSummary()
                end
                return
            end

            task.wait(0.05)
        end
    end)

    return true
end

do
    local offline = getOfflineAnimationGui()
    if offline then
        bindOfflineAnimationGui(offline)
    end

    local flash = getEclipseMergeFlashGui()
    if flash then
        bindEclipseMergeFlashGui(flash)
    end
end

AutoMergeRuntime.Start = startAutoMerge
AutoMergeRuntime.Stop = stopAutoMerge
AutoMergeRuntime.UpdateCardStatus = updateAutoMergeCardStatus
AutoMergeRuntime.GetCounts = getAutoMergeCounts
AutoMergeRuntime.GetStatusText = function()
    return AutoMergeStatusText
end
AutoMergeRuntime.GetHookStatus = function()
    return PresentationGate.CutsceneInstalled == true,
        PresentationGate.MergeAnimationInstalled == true,
        tostring(PresentationGate.CutsceneMode or "none"),
        tostring(PresentationGate.MergeAnimationMode or "none")
end
end

local function automationPlantOnce()
    if #State.PlantNames == 0 then
        return
    end

    local plot = getPlot()
    local networking = getNetworking()
    local character = LocalPlayer.Character

    if not plot then
        recordDiagnostic("Auto Plant: your garden plot was not found")
        return
    end
    if not character then
        recordDiagnostic("Auto Plant: character is not loaded")
        return
    end
    if not networking or not networking.Plant or not networking.Plant.PlantSeed then
        recordDiagnostic("Auto Plant: Plant.PlantSeed unavailable")
        return
    end

    for _, seedName in ipairs(State.PlantNames) do
        if not State.PlantEnabled then
            break
        end

        local tool = findSeedTool(seedName)
        local position = choosePlantPosition(plot)

        if not position and State.PlantLocation == "Sprinkler Radius" then
            recordDiagnostic(
                "Auto Plant: waiting for active "
                    .. tostring(State.SprinklerType)
                    .. " in your garden"
            )
        end

        if not tool then
            recordDiagnostic("Auto Plant: seed tool not found for " .. tostring(seedName))
        elseif not position then
            if State.PlantLocation ~= "Sprinkler Radius" then
                recordDiagnostic("Auto Plant: no valid planting position found")
            end
        else
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if humanoid and tool.Parent ~= character then
                pcall(function()
                    humanoid:EquipTool(tool)
                end)
                task.wait(0.06)
            end

            local planted = pcall(function()
                networking.Plant.PlantSeed:Fire(
                    position,
                    seedName,
                    tool
                )
            end)

            if planted then
                Stats.Plants += 1
                recordAction("Planted " .. tostring(seedName))
            end

            task.wait(State.PlantDelay)
        end
    end
end

local AUTO_PLANT_SAFETY_SECONDS = 1.0

local PlantEventPending = false
local PlantDrainRunning = false
local PlantLastCompletedAt = 0

local PlantEventConnections = {}
local PlantWatcherSignature = nil

local function disconnectPlantEventSources()
    for index = #PlantEventConnections, 1, -1 do
        local connection = PlantEventConnections[index]
        pcall(function()
            connection:Disconnect()
        end)
        PlantEventConnections[index] = nil
    end

    PlantWatcherSignature = nil
end

RegisterScoopHubCleanup(function()
    disconnectPlantEventSources()
end)

local queueAutoPlant
local refreshPlantEventSources

local function addPlantEventConnection(connection)
    if connection then
        PlantEventConnections[#PlantEventConnections + 1] = connection
    end
    return connection
end

local function schedulePlantSourceRefresh()
    task.defer(function()
        if not ScoopHubRunAlive() or not State.PlantEnabled then
            return
        end

        if refreshPlantEventSources then
            refreshPlantEventSources(true)
        end

        if queueAutoPlant then
            queueAutoPlant("source_refresh")
        end
    end)
end

refreshPlantEventSources = function(force)
    if not State.PlantEnabled or not ScoopHubRunAlive() then
        disconnectPlantEventSources()
        return
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local character = LocalPlayer.Character
    local gardens = Workspace:FindFirstChild("Gardens")
    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    local sprinklersFolder = plot and plot:FindFirstChild("Sprinklers")

    local signature = table.concat({
        tostring(backpack),
        tostring(character),
        tostring(gardens),
        tostring(plot),
        tostring(plantsFolder),
        tostring(sprinklersFolder),
    }, "|")

    if not force and signature == PlantWatcherSignature then
        return
    end

    disconnectPlantEventSources()
    PlantWatcherSignature = signature

    local function queueChanged()
        if queueAutoPlant then
            queueAutoPlant("game_change")
        end
    end

    if backpack then
        addPlantEventConnection(backpack.ChildAdded:Connect(queueChanged))
        addPlantEventConnection(backpack.ChildRemoved:Connect(queueChanged))
    end

    if character then
        addPlantEventConnection(character.ChildAdded:Connect(queueChanged))
        addPlantEventConnection(character.ChildRemoved:Connect(queueChanged))
    end

    addPlantEventConnection(
        LocalPlayer:GetAttributeChangedSignal("PlotId"):Connect(
            schedulePlantSourceRefresh
        )
    )

    if gardens then
        addPlantEventConnection(gardens.ChildAdded:Connect(schedulePlantSourceRefresh))
        addPlantEventConnection(gardens.ChildRemoved:Connect(schedulePlantSourceRefresh))
    end

    if plot then

        addPlantEventConnection(plot.ChildAdded:Connect(schedulePlantSourceRefresh))
        addPlantEventConnection(plot.ChildRemoved:Connect(schedulePlantSourceRefresh))
    end

    if plantsFolder then

        addPlantEventConnection(plantsFolder.ChildAdded:Connect(queueChanged))
        addPlantEventConnection(plantsFolder.ChildRemoved:Connect(queueChanged))
    end

    if sprinklersFolder then

        addPlantEventConnection(sprinklersFolder.ChildAdded:Connect(queueChanged))
        addPlantEventConnection(sprinklersFolder.ChildRemoved:Connect(queueChanged))
        addPlantEventConnection(sprinklersFolder.DescendantAdded:Connect(queueChanged))
        addPlantEventConnection(sprinklersFolder.DescendantRemoving:Connect(queueChanged))
    end
end

queueAutoPlant = function(_reason)
    if not ScoopHubRunAlive()
        or not SG.Parent
        or not State.PlantEnabled then
        return
    end

    PlantEventPending = true

    if PlantDrainRunning then
        return
    end

    PlantDrainRunning = true

    task.defer(function()
        while ScoopHubRunAlive()
            and SG.Parent
            and State.PlantEnabled
            and PlantEventPending do

            PlantEventPending = false

            local ok = pcall(automationPlantOnce)
            PlantLastCompletedAt = os.clock()

            if not ok then
                recordAction("Auto Plant encountered an error")
            end
        end

        PlantDrainRunning = false
    end)
end

local function startAutoPlantScheduler()
    if not State.PlantEnabled then
        return
    end

    refreshPlantEventSources(true)
    queueAutoPlant("enabled")
end

local function stopAutoPlantScheduler()
    PlantEventPending = false
    disconnectPlantEventSources()
end

local function automationHarvestOnce()
    if State.HarvestBusy then return end
    State.HarvestBusy = true

    local selected = {}
    for _, value in ipairs(State.HarvestNames or {}) do
        selected[tostring(value)] = true
    end

    if next(selected) == nil then
        State.HarvestBusy = false
        return
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        State.HarvestBusy = false
        return
    end

    local networking = getNetworking()
    local visualizer = getFruitVisualizer()

    for _, plant in ipairs(plantsFolder:GetChildren()) do
        if not State.HarvestEnabled then break end

        local fruits = plant:FindFirstChild("Fruits")
        if fruits and networking and networking.Garden and networking.Garden.CollectFruit then
            for _, fruit in ipairs(fruits:GetChildren()) do
                if not State.HarvestEnabled then break end

                local fruitName = fruit:GetAttribute("CorePartName")
                local plantId = fruit:GetAttribute("PlantId")
                local fruitId = fruit:GetAttribute("FruitId")
                local age = tonumber(fruit:GetAttribute("Age"))
                local maxAge = tonumber(fruit:GetAttribute("MaxAge"))
                local ready = (not maxAge or not age or age >= maxAge)

                local nameSelected = fruitName and selected[tostring(fruitName)] == true
                if fruitName and not nameSelected and IsFallAutomationWorld then
                    local parentSeedName = plant:GetAttribute("SeedName")
                    if parentSeedName and selected[tostring(parentSeedName)] == true then
                        nameSelected = true
                    else
                        for selectedName in pairs(selected) do
                            if automationNamesEquivalent(selectedName, fruitName) then
                                nameSelected = true
                                break
                            end
                        end
                    end
                end

                if fruitName and nameSelected and plantId and fruitId and ready
                    and matchesPlantFilters(fruit, plant, State.HarvestRarities, State.HarvestMutations) then
                    local ok, weight = pcall(function()
                        return visualizer and visualizer.CalculateFruitWeight
                            and visualizer:CalculateFruitWeight(fruit)
                    end)

                    if ok and matchesWeight(weight, State.HarvestMaxKg, State.HarvestDirection) then
                        pcall(function()
                            networking.Garden.CollectFruit:Fire(tostring(plantId), tostring(fruitId))
                        end)
                        task.wait(0.03)
                    end
                end
            end
        else

            local plantName = getPlantName(plant)

            local weight
            if visualizer and type(visualizer.CalculatePlantWeight) == "function" then
                local ok, calculatedWeight = pcall(function()
                    return visualizer:CalculatePlantWeight(plant)
                end)
                if ok and type(calculatedWeight) == "number" then
                    weight = calculatedWeight
                end
            end
            if type(weight) ~= "number" then
                local attrWeight = plant:GetAttribute("Weight") or plant:GetAttribute("Kg")
                weight = type(attrWeight) == "number" and attrWeight or nil
            end

            if plantName and selected[tostring(plantName)]
                and matchesPlantFilters(plant, nil, State.HarvestRarities, State.HarvestMutations)
                and matchesWeight(weight, State.HarvestMaxKg, State.HarvestDirection) then
                local prompt = findHarvestPrompt(plant)
                if prompt and prompt.Enabled then
                    pcall(function() fireproximityprompt(prompt) end)
                    task.wait(State.HarvestDelay)
                end
            end
        end
    end

    State.HarvestBusy = false
end

local PendingSellIds = {}
local SELL_RETRY_SECONDS = 0
local SELL_REQUEST_GAP = 0

local function automationSellOnce(runId)
    if not State.SellEnabled
        or runId ~= State.SellRunId
        or State.SellBusy then
        return
    end

    State.SellBusy = true

    local selected = listLookup(State.SellNames)
    if next(selected) == nil then
        State.SellBusy = false
        recordDiagnostic("Auto Sell: no fruits selected")
        return
    end

    local networking = getNetworking()
    local sellFruit = networking
        and networking.NPCS
        and networking.NPCS.SellFruit

    if not sellFruit then
        State.SellBusy = false
        recordDiagnostic("Auto Sell: NPCS.SellFruit unavailable")
        return
    end

    local containers = {
        LocalPlayer:FindFirstChild("Backpack"),
        LocalPlayer.Character,
    }

    if IsFallAutomationWorld then
        local requests = 0
        local candidates = 0
        local matched = 0
        local seen = {}

        for _, container in ipairs(containers) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if not State.SellEnabled or runId ~= State.SellRunId then
                        break
                    end
                    if seen[item] then
                        continue
                    end
                    seen[item] = true

                    local itemId = item:GetAttribute("Id")
                        or item:GetAttribute("FruitId")

                    local fruitName = item:GetAttribute("FruitName")
                        or item:GetAttribute("CorePartName")
                        or item:GetAttribute("SeedName")
                        or item:GetAttribute("PlantName")

                    if itemId and fruitName then
                        candidates += 1

                        local weight = tonumber(
                            item:GetAttribute("Weight")
                            or item:GetAttribute("Kg")
                            or item:GetAttribute("FruitWeight")
                        ) or parseKgFromName(item.Name)

                        if isSelectedName(selected, fruitName)
                            and matchesPlantFilters(
                                item,
                                nil,
                                State.SellRarities,
                                State.SellMutations
                            )
                            and matchesWeight(
                                weight,
                                State.SellMaxKg,
                                State.SellDirection
                            )
                        then
                            matched += 1
                            local sent = pcall(function()
                                sellFruit:Fire(tostring(itemId))
                            end)

                            if sent then
                                requests += 1
                            end
                        end
                    end
                end
            end
        end

        if requests > 0 then
            Stats.Sells += requests
            recordAction(
                "Auto Sell: sent " .. tostring(requests)
                    .. " Fall fruit request" .. (requests == 1 and "" or "s")
            )
        elseif candidates == 0 then
            recordDiagnostic("Auto Sell: no Fall fruit Id/FruitName found")
        elseif matched == 0 then
            recordDiagnostic("Auto Sell: 0 matching Fall fruits (check selection/KG/filters)")
        end

        State.SellBusy = false
        return
    end

    local seenObjects = {}
    local presentIds = {}
    local candidates = {}
    local candidateCount = 0
    local matchedCount = 0

    for _, container in ipairs(containers) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if seenObjects[item] then
                    continue
                end
                seenObjects[item] = true

                local itemId = item:GetAttribute("Id")
                    or item:GetAttribute("FruitId")

                local fruitName = item:GetAttribute("FruitName")
                    or item:GetAttribute("CorePartName")
                    or item:GetAttribute("SeedName")
                    or item:GetAttribute("PlantName")

                if itemId and fruitName then
                    local idKey = tostring(itemId)
                    presentIds[idKey] = true
                    candidateCount += 1

                    local weight = tonumber(
                        item:GetAttribute("Weight")
                        or item:GetAttribute("Kg")
                        or item:GetAttribute("FruitWeight")
                    ) or parseKgFromName(item.Name)

                    if isSelectedName(selected, fruitName)
                        and matchesPlantFilters(
                            item,
                            nil,
                            State.SellRarities,
                            State.SellMutations
                        )
                        and matchesWeight(
                            weight,
                            State.SellMaxKg,
                            State.SellDirection
                        )
                    then
                        matchedCount += 1
                        table.insert(candidates, {
                            Id = idKey,
                            Name = tostring(fruitName),
                        })
                    end
                end
            end
        end
    end

    for idKey, pending in pairs(PendingSellIds) do
        if not presentIds[idKey] then
            PendingSellIds[idKey] = nil
            Stats.Sells += 1
            recordAction("Sold " .. tostring(pending.Name or "fruit"))
        end
    end

    local now = os.clock()
    local requestsThisPass = 0

    for _, fruit in ipairs(candidates) do
        if not State.SellEnabled or runId ~= State.SellRunId then
            break
        end

        local pending = PendingSellIds[fruit.Id]
        if not pending or now - (pending.At or 0) >= SELL_RETRY_SECONDS then
            local sent = pcall(function()
                sellFruit:Fire(fruit.Id)
            end)

            if sent then
                PendingSellIds[fruit.Id] = {
                    At = os.clock(),
                    Name = fruit.Name,
                }
                requestsThisPass += 1
            end
        end
    end

    if requestsThisPass > 0 then
        recordAction(
            "Auto Sell: sent " .. tostring(requestsThisPass)
                .. " request" .. (requestsThisPass == 1 and "" or "s")
        )
    elseif State.SellEnabled and candidateCount == 0 then
        recordDiagnostic("Auto Sell: no fruit Id/FruitName found in Backpack/Character")
    elseif State.SellEnabled and matchedCount == 0 then
        recordDiagnostic("Auto Sell: 0 matching fruits (check selection/KG/filters)")
    end

    State.SellBusy = false
end

local function formatList(items)
    if type(items) ~= "table"
        or #items == 0 then

        return "Select..."
    end

    if #items == 1 then
        return items[1]
    end

    if #items == 2 then
        return items[1]
            .. ", "
            .. items[2]
    end

    return items[1]
        .. ", "
        .. items[2]
        .. " +"
        .. (#items - 2)
end

local function createCard(
    xScale,
    xOffset,
    y,
    widthScale,
    widthOffset,
    height,
    title
)
    return panel(
        AutomationScroll,
        UDim2.new(
            xScale,
            xOffset,
            0,
            y
        ),
        UDim2.new(
            widthScale,
            widthOffset,
            0,
            height
        ),
        title
    )
end

local function createFieldButton(
    parentFrame,
    title,
    y,
    initialText
)
    label(
        parentFrame,
        title,
        UDim2.new(0, 10, 0, y),
        UDim2.new(1, -20, 0, 14),
        10,
        T.Muted,
        T.Font
    )

    local btn = C(N("TextButton", {
        Text = initialText or "Select...",

        Font = T.Body,
        TextSize = 11,

        TextColor3 = T.White,
        TextXAlignment = Enum.TextXAlignment.Left,

        TextTruncate = Enum.TextTruncate.AtEnd,

        BackgroundColor3 = T.Input,
        BorderSizePixel = 0,

        AutoButtonColor = false,

        Position = UDim2.new(
            0,
            10,
            0,
            y + 17
        ),

        Size = UDim2.new(
            1,
            -20,
            0,
            27
        )
    }, parentFrame), 5)

    N("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, btn)

    S(
        btn,
        T.Stroke,
        .82,
        1
    )

    return btn
end

local function createInput(
    parentFrame,
    title,
    x,
    y,
    width,
    initialValue,
    callback
)

    local xOffset = (x == 0) and 10 or 0

    label(
        parentFrame,
        title,
        UDim2.new(x, xOffset, 0, y),
        UDim2.new(width, -5, 0, 14),
        10,
        T.Muted,
        T.Font
    )

    local box = C(N("TextBox", {
        Text = tostring(initialValue),

        Font = T.Font,
        TextSize = 11,

        TextColor3 = T.White,

        BackgroundColor3 = T.Input,
        BorderSizePixel = 0,

        ClearTextOnFocus = false,

        Position = UDim2.new(
            x,
            xOffset,
            0,
            y + 17
        ),

        Size = UDim2.new(
            width,
            -5,
            0,
            27
        )
    }, parentFrame), 5)

    S(
        box,
        T.Stroke,
        .82,
        1
    )

    box.FocusLost:Connect(function()
        if callback then
            callback(box.Text, box)
        end
    end)

    return box
end

local function createCycleButton(
    parentFrame,
    title,
    x,
    y,
    width,
    values,
    initialValue,
    callback
)
    label(
        parentFrame,
        title,
        UDim2.new(x, 0, 0, y),
        UDim2.new(width, -5, 0, 14),
        10,
        T.Muted,
        T.Font
    )

    local index = 1

    for i, value in ipairs(values) do
        if value == initialValue then
            index = i
            break
        end
    end

    local btn = C(N("TextButton", {
        Text =
            tostring(values[index])
            .. "  ▼",

        Font = T.Font,
        TextSize = 11,

        TextColor3 = T.White,
        TextXAlignment = Enum.TextXAlignment.Left,

        BackgroundColor3 = T.Input,
        BorderSizePixel = 0,

        AutoButtonColor = false,

        Position = UDim2.new(
            x,
            0,
            0,
            y + 17
        ),

        Size = UDim2.new(
            width,
            -5,
            0,
            27
        )
    }, parentFrame), 5)

    N("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, btn)

    S(
        btn,
        T.Stroke,
        .82,
        1
    )

    btn.Activated:Connect(function()
        index += 1

        if index > #values then
            index = 1
        end

        local value =
            values[index]

        btn.Text =
            tostring(value)
            .. "  ▼"

        if callback then
            callback(value)
        end
    end)

    return btn
end

local function createToggle(
    parentFrame,
    title,
    subtitle,
    y,
    initial,
    callback
)
    label(
        parentFrame,
        title,
        UDim2.new(0, 10, 0, y),
        UDim2.new(1, -82, 0, 14),
        11,
        T.White,
        T.Font
    )

    if subtitle then
        label(
            parentFrame,
            subtitle,
            UDim2.new(
                0,
                10,
                0,
                y + 14
            ),
            UDim2.new(
                1,
                -82,
                0,
                13
            ),
            9,
            T.Muted,
            T.Body
        )
    end

    local state =
        initial == true

    local toggle = C(N("TextButton", {
        Text = "",

        BackgroundColor3 =
            state
            and T.Success
            or T.RedDark,

        BorderSizePixel = 0,

        AutoButtonColor = false,

        Position = UDim2.new(
            1,
            -58,
            0,
            y + 2
        ),

        Size = UDim2.fromOffset(
            48,
            23
        )
    }, parentFrame), 12)

    local knob = C(N("Frame", {
        BackgroundColor3 = T.White,
        BorderSizePixel = 0,

        AnchorPoint = Vector2.new(
            0,
            .5
        ),

        Position =
            state
            and UDim2.new(
                1,
                -20,
                .5,
                0
            )
            or UDim2.new(
                0,
                3,
                .5,
                0
            ),

        Size = UDim2.fromOffset(
            17,
            17
        )
    }, toggle), 10)

    local api = {}

    function api:Set(value, fireCallback)
        state = value == true

        toggle.BackgroundColor3 =
            state
            and T.Success
            or T.RedDark

        tw(
            knob,
            {
                Position =
                    state
                    and UDim2.new(
                        1,
                        -20,
                        .5,
                        0
                    )
                    or UDim2.new(
                        0,
                        3,
                        .5,
                        0
                    )
            },
            .15
        )

        if fireCallback ~= false
            and callback then

            callback(state)
        end
    end

    function api:Get()
        return state
    end

    toggle.Activated:Connect(function()
        api:Set(not state)
    end)

    return api
end

label(
    Automation,
    "AUTOMATION",
    UDim2.new(0, 8, 0, 1),
    UDim2.new(.5, 0, 0, 20),
    11,
    T.Text,
    T.Font
)

local HeaderStatus = label(
    Automation,
    "● READY",
    UDim2.new(.5, 0, 0, 1),
    UDim2.new(.5, -8, 0, 20),
    10,
    T.Success,
    T.Font,
    Enum.TextXAlignment.Right
)

AutomationScroll = N("ScrollingFrame", {
    Name = "AutomationScroll",

    Position = UDim2.new(
        0,
        0,
        0,
        24
    ),

    Size = UDim2.new(
        1,
        0,
        1,
        -24
    ),

    BackgroundTransparency = 1,
    BorderSizePixel = 0,

    CanvasSize = UDim2.new(
        0,
        0,
        0,
        1060
    ),

    ScrollBarThickness = 4,
    ScrollBarImageColor3 = T.Red
}, Automation)

local Picker = C(N("Frame", {
    Name = "AutomationPicker",

    Visible = false,

    BackgroundColor3 = T.Panel,
    BorderSizePixel = 0,

    Position = UDim2.new(
        0,
        24,
        0,
        35
    ),

    Size = UDim2.new(
        1,
        -48,
        1,
        -55
    ),

    ZIndex = 100
}, Automation), 8)

S(
    Picker,
    T.Red,
    .05,
    1.4
)

local PickerTitle = label(
    Picker,
    "SELECT ITEMS",
    UDim2.new(0, 12, 0, 8),
    UDim2.new(1, -100, 0, 20),
    11,
    T.White,
    T.Font
)
PickerTitle.ZIndex = 101

local PickerDone = button(
    Picker,
    "DONE",
    UDim2.new(1, -74, 0, 7),
    UDim2.fromOffset(62, 23),
    T.Red
)
PickerDone.ZIndex = 102

local PickerSearch = C(N("TextBox", {
    Text = "",
    PlaceholderText = "Search...",

    Font = T.Body,
    TextSize = 11,

    TextColor3 = T.White,
    PlaceholderColor3 = T.Muted,

    BackgroundColor3 = T.Input,
    BorderSizePixel = 0,

    ClearTextOnFocus = false,

    Position = UDim2.new(
        0,
        12,
        0,
        38
    ),

    Size = UDim2.new(
        1,
        -24,
        0,
        27
    ),

    ZIndex = 101
}, Picker), 5)

N("UIPadding", {
    PaddingLeft = UDim.new(0, 8)
}, PickerSearch)

local PickerActionRow = N("Frame", {
    BackgroundTransparency = 1,

    Position = UDim2.new(
        0,
        12,
        0,
        72
    ),

    Size = UDim2.new(
        1,
        -24,
        0,
        24
    ),

    ZIndex = 101
}, Picker)

local PickerSelectAll = button(
    PickerActionRow,
    "SELECT ALL",
    UDim2.new(0, 0, 0, 0),
    UDim2.new(.5, -4, 1, 0),
    T.RedDark
)
PickerSelectAll.ZIndex = 102

local PickerClear = button(
    PickerActionRow,
    "CLEAR ALL",
    UDim2.new(.5, 4, 0, 0),
    UDim2.new(.5, -4, 1, 0),
    T.Surface3
)
PickerClear.ZIndex = 102

local PickerScroll = N("ScrollingFrame", {
    BackgroundColor3 = T.Bg,
    BackgroundTransparency = .08,

    BorderSizePixel = 0,

    Position = UDim2.new(
        0,
        12,
        0,
        103
    ),

    Size = UDim2.new(
        1,
        -24,
        1,
        -115
    ),

    CanvasSize = UDim2.new(
        0,
        0,
        0,
        0
    ),

    ScrollBarThickness = 4,
    ScrollBarImageColor3 = T.Red,

    ZIndex = 101
}, Picker)

C(PickerScroll, 5)

N("UIListLayout", {
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, PickerScroll)

local PickerData = {
    Options = {},
    Selected = {},
    Callback = nil,
}

local function selectedToList(set)
    local output = {}

    for name, enabled in pairs(set or {}) do
        if enabled then
            table.insert(output, name)
        end
    end

    table.sort(output)

    return output
end

local function rebuildPicker()
    for _, child in ipairs(PickerScroll:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    local query =
        tostring(PickerSearch.Text or "")
        :lower()

    local rowCount = 0

    for _, name in ipairs(PickerData.Options) do
        if query == ""
            or string.find(
                string.lower(name),
                query,
                1,
                true
            )
        then
            rowCount += 1

            local selected =
                PickerData.Selected[name] == true

            local row = C(N("TextButton", {
                Text = "",

                BackgroundColor3 =
                    selected
                    and Color3.fromRGB(
                        56,
                        25,
                        32
                    )
                    or T.Surface2,

                BorderSizePixel = 0,

                AutoButtonColor = false,

                Size = UDim2.new(
                    1,
                    -4,
                    0,
                    29
                ),

                LayoutOrder = rowCount,

                ZIndex = 102
            }, PickerScroll), 4)

            local check = label(
                row,
                selected and "\u{2713}" or "",
                UDim2.new(
                    0,
                    8,
                    0,
                    0
                ),
                UDim2.fromOffset(
                    18,
                    29
                ),
                12,
                T.Success,
                T.Font
            )
            check.ZIndex = 103

            local txt = label(
                row,
                name,
                UDim2.new(
                    0,
                    30,
                    0,
                    0
                ),
                UDim2.new(
                    1,
                    -38,
                    1,
                    0
                ),
                10,
                T.White,
                T.Body
            )
            txt.ZIndex = 103

            row.Activated:Connect(function()
                PickerData.Selected[name] =
                    not PickerData.Selected[name]

                local enabled =
                    PickerData.Selected[name] == true

                check.Text =
                    enabled and "\u{2713}" or ""

                row.BackgroundColor3 =
                    enabled
                    and Color3.fromRGB(
                        56,
                        25,
                        32
                    )
                    or T.Surface2
            end)
        end
    end

    PickerScroll.CanvasSize =
        UDim2.new(
            0,
            0,
            0,
            rowCount * 32
        )
end

local function openPicker(
    title,
    options,
    current,
    callback
)
    PickerTitle.Text = title

    PickerData.Options =
        options or {}

    PickerData.Selected = {}

    for _, value in ipairs(current or {}) do
        PickerData.Selected[value] = true
    end

    PickerData.Callback = callback

    PickerSearch.Text = ""

    rebuildPicker()

    Picker.Visible = true
end

PickerSearch
    :GetPropertyChangedSignal("Text")
    :Connect(rebuildPicker)

PickerSelectAll.Activated:Connect(function()
    for _, name in ipairs(PickerData.Options) do
        PickerData.Selected[name] = true
    end

    rebuildPicker()
end)

PickerClear.Activated:Connect(function()
    table.clear(PickerData.Selected)

    rebuildPicker()
end)

PickerDone.Activated:Connect(function()
    Picker.Visible = false

    local callback =
        PickerData.Callback

    if callback then
        callback(
            selectedToList(
                PickerData.Selected
            )
        )
    end
end)

local PlantCard = createCard(
    0,
    8,
    0,
    .5,
    -13,
    235,
    "AUTO PLANT"
)

local PlantSelector =
    createFieldButton(
        PlantCard,
        "SEEDS",
        26,
        "Select seeds..."
    )

local ActiveCompactAutomationDropdown = nil
local ActiveCompactAutomationChevron = nil

local function setupCompactAutomationMultiPicker(selector, options, getValues, setValues, config)
    config = config or {}
    options = options or {}

    local emptyText = config.EmptyText or "Select..."
    local searchPlaceholder = config.SearchPlaceholder or "Search..."
    local singleSelect = config.SingleSelect == true

    selector.Text = ""
    selector.ClipsDescendants = true
    selector.AutoButtonColor = false

    if config.PreserveSize ~= true then
        selector.Size = UDim2.new(1, -20, 0, 27)
    end

    local oldPadding = selector:FindFirstChildOfClass("UIPadding")
    if oldPadding then
        oldPadding:Destroy()
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

    local selectorChevron = N("Frame", {
        Name = "CompactSelectorChevron",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -20, 0.5, -5),
        Size = UDim2.fromOffset(14, 10),
        Rotation = 0,
        ZIndex = 6,
    }, selector)

    N("Frame", {
        Name = "ChevronLeft",
        BackgroundColor3 = T.Muted,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, -2, 0.5, 0),
        Size = UDim2.fromOffset(7, 2),
        Rotation = 45,
        ZIndex = 7,
    }, selectorChevron)

    N("Frame", {
        Name = "ChevronRight",
        BackgroundColor3 = T.Muted,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 2, 0.5, 0),
        Size = UDim2.fromOffset(7, 2),
        Rotation = -45,
        ZIndex = 7,
    }, selectorChevron)

    local function setSelectorChevron(open, instant)
        local targetRotation = open and 180 or 0

        if instant then
            selectorChevron.Rotation = targetRotation
        else

            tw(selectorChevron, {Rotation = targetRotation}, .14)
        end
    end

    local dropdown = C(N("Frame", {
        Name = "CompactAutomationDropdown",
        Visible = false,
        BackgroundColor3 = T.Surface2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(230, 240),
        ZIndex = 150,
    }, Automation), 6)
    S(dropdown, T.Red, 0, 1.5)

    local searchBox = C(N("TextBox", {
        Name = "CompactAutomationSearch",
        Text = "",
        PlaceholderText = searchPlaceholder,
        Font = T.Body,
        TextSize = 12,
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
        Name = "CompactAutomationActions",
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
        TextSize = 11,
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
        TextSize = 11,
        TextColor3 = T.White,
        BackgroundColor3 = T.Surface3,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Position = UDim2.new(0.5, 2, 0, 0),
        Size = UDim2.new(0.5, -2, 1, 0),
        ZIndex = 152,
    }, actionRow), 4)

    local itemScroll = N("ScrollingFrame", {
        Name = "CompactAutomationScroll",
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

    local function currentValues()
        local ok, values = pcall(getValues)
        if ok and type(values) == "table" then
            return values
        end
        return {}
    end

    local function updateSelector()
        local values = currentValues()
        selectorText.Text = #values > 0 and formatList(values) or emptyText
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
            local basePos = Automation.AbsolutePosition
            local baseSize = Automation.AbsoluteSize
            local buttonPos = selector.AbsolutePosition
            local buttonSize = selector.AbsoluteSize

            local pageWidth = baseSize.X / scaleValue
            local pageHeight = baseSize.Y / scaleValue
            local buttonX = (buttonPos.X - basePos.X) / scaleValue
            local buttonTop = (buttonPos.Y - basePos.Y) / scaleValue
            local buttonHeight = buttonSize.Y / scaleValue
            local buttonBottom = buttonTop + buttonHeight
            local margin = 4

            currentWidth = buttonSize.X / scaleValue

            local x = math.clamp(
                buttonX,
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

    local lastRebuildSignature = nil

    local rebuild
    rebuild = function(filterText, force)
        local query = string.lower(tostring(filterText or ""))
        local selectedForSignature = selectedLookup()
        local signatureParts = { query }

        for _, option in ipairs(options) do
            signatureParts[#signatureParts + 1] =
                tostring(option) .. "=" .. (selectedForSignature[option] and "1" or "0")
        end

        local signature = table.concat(signatureParts, "|")
        if not force and lastRebuildSignature == signature then
            return
        end
        lastRebuildSignature = signature

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
                TextSize = 12,
                TextColor3 = T.Muted,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 30),
                LayoutOrder = 1,
                ZIndex = 152,
            }, itemScroll)

            itemScroll.CanvasSize = UDim2.new(0, 0, 0, 32)
            resizeDropdown(1)
            return
        end

        local selected = selectedLookup()

        for index, option in ipairs(filtered) do
            local isSelected = selected[option] == true
            local row = C(N("TextButton", {
                Name = "CompactAutomationOption",
                Text = "",
                BackgroundColor3 = isSelected and (T.UserActiveBgAlt or AccentSelectedBg()) or T.Surface2,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, rowHeight),
                LayoutOrder = index,
                ZIndex = 152,
            }, itemScroll), 4)

            local check = N("TextLabel", {
                Name = "OptionCheck",
                Text = isSelected and "\u{2713}" or "",
                Font = T.Font,
                TextSize = 14,
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
                TextSize = 12,
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
                    if ActiveCompactAutomationChevron == selectorChevron then
                        ActiveCompactAutomationChevron = nil
                    end
                    if ActiveCompactAutomationDropdown == dropdown then
                        ActiveCompactAutomationDropdown = nil
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

        if ActiveCompactAutomationDropdown and ActiveCompactAutomationDropdown ~= dropdown then
            ActiveCompactAutomationDropdown.Visible = false

            if ActiveCompactAutomationChevron then
                tw(ActiveCompactAutomationChevron, {Rotation = 0}, .14)
                ActiveCompactAutomationChevron = nil
            end
        end

        dropdown.Visible = opening
        setSelectorChevron(opening, false)

        if opening then
            ActiveCompactAutomationDropdown = dropdown
            ActiveCompactAutomationChevron = selectorChevron

            if type(config.OnOpen) == "function" then
                pcall(config.OnOpen)
            end

            updateDropdownPosition()
            searchBox.Text = ""
            rebuild("")
        else
            if ActiveCompactAutomationChevron == selectorChevron then
                ActiveCompactAutomationChevron = nil
            end

            if ActiveCompactAutomationDropdown == dropdown then
                ActiveCompactAutomationDropdown = nil
            end
        end
    end)

    AutomationScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        dropdown.Visible = false
        setSelectorChevron(false, false)

        if ActiveCompactAutomationChevron == selectorChevron then
            ActiveCompactAutomationChevron = nil
        end

        if ActiveCompactAutomationDropdown == dropdown then
            ActiveCompactAutomationDropdown = nil
        end
    end)

    Automation:GetPropertyChangedSignal("Visible"):Connect(function()
        if not Automation.Visible then
            dropdown.Visible = false
            setSelectorChevron(false, true)

            if ActiveCompactAutomationChevron == selectorChevron then
                ActiveCompactAutomationChevron = nil
            end

            if ActiveCompactAutomationDropdown == dropdown then
                ActiveCompactAutomationDropdown = nil
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

            if ActiveCompactAutomationChevron == selectorChevron then
                ActiveCompactAutomationChevron = nil
            end

            if ActiveCompactAutomationDropdown == dropdown then
                ActiveCompactAutomationDropdown = nil
            end
        end
    end))

    updateSelector()

    return {
        Refresh = updateSelector,
        Close = function()
            dropdown.Visible = false
            setSelectorChevron(false, false)

            if ActiveCompactAutomationChevron == selectorChevron then
                ActiveCompactAutomationChevron = nil
            end

            if ActiveCompactAutomationDropdown == dropdown then
                ActiveCompactAutomationDropdown = nil
            end
        end,
    }
end

local PlantPickerControl = setupCompactAutomationMultiPicker(
    PlantSelector,
    AllSeeds,
    function() return State.PlantNames end,
    function(values)
        State.PlantNames = values
        if State.PlantEnabled and queueAutoPlant then
            queueAutoPlant("selection_changed")
        end
    end,
    {
        EmptyText = "Select seeds...",
        SearchPlaceholder = "Search seeds...",
    }
)

local PlantLocationOptions = {
    "Random",
    "Sprinkler Radius",
    "Player Position",
}

label(
    PlantCard,
    "PLANT LOCATION",
    UDim2.new(0, 10, 0, 78),
    UDim2.new(1, -20, 0, 14),
    10,
    T.Muted,
    T.Font
)

local PlantLocationButton = C(N("TextButton", {
    Text = State.PlantLocation .. "  ▼",
    Font = T.Font,
    TextSize = 11,
    TextColor3 = T.White,
    TextXAlignment = Enum.TextXAlignment.Left,
    BackgroundColor3 = T.Input,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Position = UDim2.new(0, 10, 0, 95),
    Size = UDim2.new(1, -20, 0, 27),
}, PlantCard), 5)

N("UIPadding", {
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8),
}, PlantLocationButton)

S(
    PlantLocationButton,
    T.Stroke,
    .82,
    1
)

local PlantLocationPickerControl
local SprinklerTypeLabel
local SprinklerTypeButton
local SprinklerTypePickerControl

local SprinklerTypeDisplayOptions = {}
local SprinklerTypeNameByDisplay = {}
local SprinklerTypeDisplayByName = {}

for _, sprinklerName in ipairs(SprinklerTypeOptions) do
    local plantRadius = getSprinklerPlantRadiusForType(sprinklerName)
    local displayName = tostring(sprinklerName)
        .. "  \u{2022}  "
        .. string.format("%.1f", plantRadius)
        .. " plant studs"

    table.insert(SprinklerTypeDisplayOptions, displayName)
    SprinklerTypeNameByDisplay[displayName] = sprinklerName
    SprinklerTypeDisplayByName[sprinklerName] = displayName
end

local function updateSprinklerTypeButton()
    local radius = getSprinklerRadiusForType(State.SprinklerType)
    State.SprinklerRadius = radius

    if SprinklerTypePickerControl and SprinklerTypePickerControl.Refresh then
        SprinklerTypePickerControl.Refresh()
    end
end

local function closeSprinklerTypeDropdown()
    if SprinklerTypePickerControl and SprinklerTypePickerControl.Close then
        SprinklerTypePickerControl.Close()
    end
end

local function refreshSprinklerTypeControl()
    local visible = State.PlantLocation == "Sprinkler Radius"

    if SprinklerTypeLabel then
        SprinklerTypeLabel.Visible = visible
    end

    if SprinklerTypeButton then
        SprinklerTypeButton.Visible = visible
    end

    if not visible then
        closeSprinklerTypeDropdown()
    end
end

local function setSprinklerType(value)
    value = tostring(value or "")

    if not SprinklerRadiusByType[value] then
        value = DEFAULT_SPRINKLER_TYPE
    end

    State.SprinklerType = value
    State.SprinklerRadius = getSprinklerRadiusForType(value)
    updateSprinklerTypeButton()

    if State.PlantEnabled and queueAutoPlant then
        queueAutoPlant("sprinkler_type_changed")
    end

    recordAction(
        "Sprinkler: "
        .. State.SprinklerType
        .. " (plant radius "
        .. string.format("%.2f", getSprinklerPlantRadiusForType(State.SprinklerType))
        .. ")"
    )
end

local function setPlantLocation(value)
    local valid = false

    for _, option in ipairs(PlantLocationOptions) do
        if value == option then
            valid = true
            break
        end
    end

    State.PlantLocation = valid and value or "Random"

    if PlantLocationPickerControl and PlantLocationPickerControl.Refresh then
        PlantLocationPickerControl.Refresh()
    end

    refreshSprinklerTypeControl()

    if State.PlantEnabled then
        if refreshPlantEventSources then
            refreshPlantEventSources(true)
        end
        if queueAutoPlant then
            queueAutoPlant("plant_location_changed")
        end
    end

    recordAction("Plant location: " .. State.PlantLocation)
end

PlantLocationPickerControl = setupCompactAutomationMultiPicker(
    PlantLocationButton,
    PlantLocationOptions,
    function()
        return { State.PlantLocation }
    end,
    function(values)
        local chosen = values and values[1]
        setPlantLocation(chosen or "Random")
    end,
    {
        EmptyText = "Select location...",
        SearchPlaceholder = "Search location...",
        SingleSelect = true,
    }
)

local PlantDelayBox =
    createInput(
        PlantCard,
        "DELAY",
        0,
        129,
        .48,
        State.PlantDelay,

        function(text, box)
            local value = tonumber(text)

            if not value then
                box.Text = tostring(State.PlantDelay)
                return
            end

            State.PlantDelay = math.clamp(value, 0.03, 5)
            box.Text = tostring(State.PlantDelay)

            if State.PlantEnabled and queueAutoPlant then
                queueAutoPlant("plant_delay_changed")
            end
        end
    )

PlantDelayBox.Position = UDim2.new(0, 10, 0, 146)
PlantDelayBox.Size = UDim2.new(.48, -5, 0, 27)

SprinklerTypeLabel = label(
    PlantCard,
    "SPRINKLER TYPE",
    UDim2.new(.52, 4, 0, 129),
    UDim2.new(.48, -14, 0, 14),
    8,
    T.Muted,
    T.Font
)

SprinklerTypeButton = C(N("TextButton", {
    Text = "",
    Font = T.Font,
    TextSize = 9,
    TextColor3 = T.White,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    BackgroundColor3 = T.Input,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Position = UDim2.new(.52, 4, 0, 146),
    Size = UDim2.new(.48, -14, 0, 27),
}, PlantCard), 5)

S(SprinklerTypeButton, T.Stroke, .82, 1)

SprinklerTypePickerControl = setupCompactAutomationMultiPicker(
    SprinklerTypeButton,
    SprinklerTypeDisplayOptions,
    function()
        local displayName = SprinklerTypeDisplayByName[State.SprinklerType]
        return displayName and { displayName } or {}
    end,
    function(values)

        local chosenDisplay = values and values[#values]
        local sprinklerName = chosenDisplay and SprinklerTypeNameByDisplay[chosenDisplay]

        if sprinklerName then
            setSprinklerType(sprinklerName)
        else
            updateSprinklerTypeButton()
        end
    end,
    {
        EmptyText = "Select sprinkler...",
        SearchPlaceholder = "Search sprinkler...",
        PreserveSize = true,
        SingleSelect = true,
    }
)

updateSprinklerTypeButton()
refreshSprinklerTypeControl()

local PlantToggle =
    createToggle(
        PlantCard,
        "AUTO PLANT",
        "Plant selected seeds",
        188,
        false,

        function(value)
            State.PlantEnabled =
                value == true

            if State.PlantEnabled then
                startAutoPlantScheduler()
            else
                stopAutoPlantScheduler()
            end

            recordAction(
                State.PlantEnabled
                and "Auto Plant enabled"
                or "Auto Plant disabled"
            )

            if refreshSummary then
                refreshSummary()
            end
        end
    )

local HarvestCard = createCard(
    .5,
    5,
    0,
    .5,
    -13,
    285,
    "AUTO HARVEST"
)

local HarvestSelector =
    createFieldButton(
        HarvestCard,
        "PLANTS",
        26,
        "Select plants..."
    )

local HarvestPickerControl = setupCompactAutomationMultiPicker(
    HarvestSelector,
    AllSeeds,
    function() return State.HarvestNames end,
    function(values) State.HarvestNames = values end,
    {
        EmptyText = "Select plants...",
        SearchPlaceholder = "Search plants...",
    }
)

local HarvestRarity =
    createFieldButton(
        HarvestCard,
        "RARITY FILTER",
        77,
        "Any"
    )

local HarvestRarityPickerControl = setupCompactAutomationMultiPicker(
    HarvestRarity,
    RarityOptions,
    function() return State.HarvestRarities end,
    function(values) State.HarvestRarities = values end,
    {
        EmptyText = "Any",
        SearchPlaceholder = "Search rarity...",
    }
)

local HarvestMutation =
    createFieldButton(
        HarvestCard,
        "MUTATION FILTER",
        128,
        "Any"
    )

local HarvestMutationPickerControl = setupCompactAutomationMultiPicker(
    HarvestMutation,
    MutationOptions,
    function() return State.HarvestMutations end,
    function(values) State.HarvestMutations = values end,
    {
        EmptyText = "Any",
        SearchPlaceholder = "Search mutations...",
        OnOpen = AutomationWorldData.RefreshLiveMutationOptions,
    }
)

local HarvestKgBox =
    createInput(
        HarvestCard,
        "KG LIMIT",
        0,
        180,
        .48,
        State.HarvestMaxKg,

        function(text, box)
            local value =
                tonumber(text)

            if not value then
                box.Text =
                    tostring(
                        State.HarvestMaxKg
                    )

                return
            end

            State.HarvestMaxKg =
                math.max(0, value)

            box.Text =
                tostring(
                    State.HarvestMaxKg
                )
        end
    )

HarvestKgBox.Position =
    UDim2.new(
        0,
        10,
        0,
        197
    )

HarvestKgBox.Size =
    UDim2.new(
        .48,
        -5,
        0,
        27
    )

local HarvestDirectionButton = createCycleButton(
    HarvestCard,
    "DIRECTION",
    .52,
    180,
    .48,
    {
        "Below",
        "Above",
    },
    State.HarvestDirection,

    function(value)
        State.HarvestDirection =
            value
    end
)

local HarvestToggle =
    createToggle(
        HarvestCard,
        "AUTO HARVEST",
        "Harvest matching crops only",
        239,
        false,

        function(value)
            State.HarvestEnabled =
                value == true

            recordAction(
                State.HarvestEnabled
                and "Auto Harvest enabled"
                or "Auto Harvest disabled"
            )

            if refreshSummary then
                refreshSummary()
            end
        end
    )

local SellCard = createCard(
    0,
    8,
    245,
    .5,
    -13,
    285,
    "AUTO SELL FRUIT"
)

local SellSelector =
    createFieldButton(
        SellCard,
        "FRUITS",
        26,
        "Select fruits..."
    )

local SellPickerControl = setupCompactAutomationMultiPicker(
    SellSelector,
    AllSeeds,
    function() return State.SellNames end,
    function(values) State.SellNames = values end,
    {
        EmptyText = "Select fruits...",
        SearchPlaceholder = "Search fruits...",
    }
)

local SellRarity =
    createFieldButton(
        SellCard,
        "RARITY FILTER",
        77,
        "Any"
    )

local SellRarityPickerControl = setupCompactAutomationMultiPicker(
    SellRarity,
    RarityOptions,
    function() return State.SellRarities end,
    function(values) State.SellRarities = values end,
    {
        EmptyText = "Any",
        SearchPlaceholder = "Search rarity...",
    }
)

local SellMutation =
    createFieldButton(
        SellCard,
        "MUTATION FILTER",
        128,
        "Any"
    )

local SellMutationPickerControl = setupCompactAutomationMultiPicker(
    SellMutation,
    MutationOptions,
    function() return State.SellMutations end,
    function(values) State.SellMutations = values end,
    {
        EmptyText = "Any",
        SearchPlaceholder = "Search mutations...",
        OnOpen = AutomationWorldData.RefreshLiveMutationOptions,
    }
)

local SellKgBox =
    createInput(
        SellCard,
        "KG LIMIT",
        0,
        180,
        .48,
        State.SellMaxKg,

        function(text, box)
            local value =
                tonumber(text)

            if not value then
                box.Text =
                    tostring(
                        State.SellMaxKg
                    )

                return
            end

            State.SellMaxKg =
                math.max(0, value)

            box.Text =
                tostring(
                    State.SellMaxKg
                )
        end
    )

SellKgBox.Position =
    UDim2.new(
        0,
        10,
        0,
        197
    )

SellKgBox.Size =
    UDim2.new(
        .48,
        -5,
        0,
        27
    )

local SellDirectionButton = createCycleButton(
    SellCard,
    "DIRECTION",
    .52,
    180,
    .48,
    {
        "Below",
        "Above",
    },
    State.SellDirection,

    function(value)
        State.SellDirection =
            value
    end
)

local SellToggle =
    createToggle(
        SellCard,
        "AUTO SELL",
        "Sell matching backpack fruit",
        239,
        false,

        function(value)
            State.SellEnabled =
                value == true

            State.SellRunId += 1

            for idKey in pairs(PendingSellIds) do
                PendingSellIds[idKey] = nil
            end

            recordAction(
                State.SellEnabled
                and "Auto Sell enabled"
                or "Auto Sell disabled"
            )

            if State.SellEnabled then
                local runId =
                    State.SellRunId

                task.spawn(function()
                    local ok =
                        pcall(function()
                            automationSellOnce(
                                runId
                            )
                        end)

                    if not ok then
                        State.SellBusy =
                            false
                    end
                end)
            end

            if refreshSummary then
                refreshSummary()
            end
        end
    )

local TrowelCard = createCard(
    .5,
    5,
    295,
    .5,
    -13,
    285,
    "AUTO TROWEL"
)

local TrowelPlantSelector = createFieldButton(
    TrowelCard,
    "PLANT",
    26,
    "All Plants"
)

local TrowelPlantPickerControl = setupCompactAutomationMultiPicker(
    TrowelPlantSelector,
    TrowelRuntime.PlantOptions,
    function()
        return { State.TrowelPlantName or "All Plants" }
    end,
    function(values)
        State.TrowelPlantName = tostring(
            (values and values[1])
            or "All Plants"
        )

        TrowelRuntime.ResetProgress(true)
    end,
    {
        EmptyText = "All Plants",
        SearchPlaceholder = "Search plants...",
        SingleSelect = true,
        OnOpen = TrowelRuntime.RefreshPlantOptions,
    }
)

local TrowelRaritySelector = createFieldButton(
    TrowelCard,
    "RARITY",
    77,
    "Any"
)

local TrowelRarityPickerControl = setupCompactAutomationMultiPicker(
    TrowelRaritySelector,
    RarityOptions,
    function()
        return { State.TrowelRarity or "Any" }
    end,
    function(values)
        State.TrowelRarity = tostring(
            (values and values[1])
            or "Any"
        )

        TrowelRuntime.ResetProgress(true)
    end,
    {
        EmptyText = "Any",
        SearchPlaceholder = "Search rarity...",
        SingleSelect = true,
    }
)

local TrowelPositionButton = createFieldButton(
    TrowelCard,
    "STACK POSITION",
    128,
    "Click to set position"
)

local TrowelSelectingPosition = false

local function updateTrowelPositionButton()
    local position = State.TrowelPosition
    if typeof(position) == "Vector3" then
        TrowelPositionButton.Text = string.format(
            "Saved: %.1f, %.1f, %.1f",
            position.X,
            position.Y,
            position.Z
        )
    else
        TrowelPositionButton.Text = "Click to set position"
    end
end

TrowelPositionButton.Activated:Connect(function()
    TrowelSelectingPosition = true
    TrowelPositionButton.Text = "Click position inside your plot..."
    recordAction("Auto Trowel: select a stack position")
end)

TrackConnection(TrowelRuntime.Mouse.Button1Down:Connect(function()
    if not TrowelSelectingPosition then
        return
    end

    local targetPart = TrowelRuntime.Mouse.Target
    if not targetPart then
        return
    end

    local plot = getPlot()
    if not plot then
        recordAction("Auto Trowel: your garden plot was not found")
        return
    end

    if not targetPart:IsDescendantOf(plot) then
        recordAction("Auto Trowel: click inside your own plot")
        return
    end

    State.TrowelPosition = TrowelRuntime.Mouse.Hit.Position

    TrowelSelectingPosition = false
    updateTrowelPositionButton()
    TrowelRuntime.ResetProgress(true)

    recordAction(
        string.format(
            "Trowel position saved: %.1f, %.1f, %.1f",
            State.TrowelPosition.X,
            State.TrowelPosition.Y,
            State.TrowelPosition.Z
        )
    )
end))

local TrowelDelayBox = createInput(
    TrowelCard,
    "DELAY",
    0,
    180,
    1,
    State.TrowelDelay,
    function(textValue, box)
        local value = tonumber(textValue)
        if not value then
            box.Text = tostring(State.TrowelDelay)
            return
        end

        State.TrowelDelay = math.clamp(value, 0.05, 5)
        box.Text = tostring(State.TrowelDelay)
    end
)

TrowelDelayBox.Position = UDim2.new(0, 10, 0, 197)
TrowelDelayBox.Size = UDim2.new(1, -20, 0, 27)

local TrowelToggle
TrowelToggle = createToggle(
    TrowelCard,
    "AUTO TROWEL",
    "Stack matching plants at the saved position",
    239,
    false,
    function(value)
        if value == true and not State.TrowelPosition then
            State.TrowelEnabled = false
            TrowelToggle:Set(false, false)
            recordAction("Auto Trowel: set a stack position first")

            if refreshSummary then
                refreshSummary()
            end
            return
        end

        State.TrowelEnabled = value == true

        if State.TrowelEnabled then
            TrowelRuntime.Start()
        else
            TrowelRuntime.Stop()
        end

        recordAction(
            State.TrowelEnabled
            and "Auto Trowel enabled"
            or "Auto Trowel disabled"
        )

        if refreshSummary then
            refreshSummary()
        end
    end
)

TrowelRuntime.OnCompleted = function()
    if not State.TrowelEnabled then
        return
    end

    State.TrowelEnabled = false
    TrowelRuntime.Stop()
    TrowelToggle:Set(false, false)
    recordAction("Auto Trowel completed - all matching plants stacked")

    if refreshSummary then
        refreshSummary()
    end
end

updateTrowelPositionButton()

do
    local PotCard = createCard(
        .5,
        5,
        590,
        .5,
        -13,
        170,
        "AUTO POT"
    )

    local PotPlantSelector = createFieldButton(
        PotCard,
        "PLANTS TO POT",
        26,
        "All Plants"
    )

    AutoPotRuntime.PickerControl = setupCompactAutomationMultiPicker(
        PotPlantSelector,
        AutoPotRuntime.PlantOptions,
        function()
            return State.PotPlantNames or { "All Plants" }
        end,
        function(values)
            values = type(values) == "table" and values or {}

            local hasAllPlants = false
            for _, value in ipairs(values) do
                if value == "All Plants" then
                    hasAllPlants = true
                    break
                end
            end

            if hasAllPlants then
                State.PotPlantNames = { "All Plants" }
            else
                State.PotPlantNames = table.clone(values)
            end

            AutoPotRuntime.UpdateCardStatus()
        end,
        {
            EmptyText = "Select plants...",
            SearchPlaceholder = "Search plants...",
            OnOpen = AutoPotRuntime.RefreshPlantOptions,
        }
    )

    AutoPotRuntime.Toggle = createToggle(
        PotCard,
        "AUTO POT",
        "Pot selected plants using available pots",
        82,
        false,
        function(value)
            State.PotEnabled = value == true

            if State.PotEnabled then
                local started, startError = AutoPotRuntime.Start()
                if not started then
                    State.PotEnabled = false
                    AutoPotRuntime.Toggle:Set(false, false)
                    recordAction(startError or "Auto Pot could not start")
                else
                    recordAction("Auto Pot enabled")
                end
            else
                AutoPotRuntime.Stop()
                recordAction("Auto Pot disabled")
            end

            AutoPotRuntime.UpdateCardStatus()
            if refreshSummary then
                refreshSummary()
            end
        end
    )

    label(
        PotCard,
        "STATUS",
        UDim2.new(0, 10, 0, 124),
        UDim2.new(1, -20, 0, 14),
        9,
        T.Muted,
        T.Font
    )

    AutoPotRuntime.StatusLabel = label(
        PotCard,
        "Off",
        UDim2.new(0, 10, 0, 141),
        UDim2.new(1, -20, 0, 18),
        9,
        T.Muted,
        T.Body
    )
    AutoPotRuntime.StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd

    AutoPotRuntime.OnFinished = function(reason, detail)
        State.PotEnabled = false

        if AutoPotRuntime.Toggle then
            AutoPotRuntime.Toggle:Set(false, false)
        end

        if reason == "complete" then
            recordAction("Auto Pot completed - all matching plants potted")
        elseif reason == "no_pots" then
            recordAction("Auto Pot stopped - no empty pots left")
        else
            recordAction("Auto Pot stopped - " .. tostring(detail or reason or "unknown error"))
        end

        AutoPotRuntime.UpdateCardStatus()
        if refreshSummary then
            refreshSummary()
        end
    end

    AutoPotRuntime.UpdateCardStatus()
end

do
    local MergeCard = createCard(
        0,
        8,
        540,
        .5,
        -13,
        175,
        "AUTO MERGE"
    )

    AutoMergeRuntime.Toggle = createToggle(
        MergeCard,
        "AUTO MERGE",
        "Merge closest Moon + Sun pair",
        26,
        false,
        function(value)
            State.MergeEnabled = value == true

            if State.MergeEnabled then
                local started, startError = AutoMergeRuntime.Start()
                if not started then
                    State.MergeEnabled = false
                    AutoMergeRuntime.Toggle:Set(false, false)
                    recordAction(startError or "Auto Merge could not start")
                else
                    local cutsceneHook, mergeHook, cutsceneMode, mergeMode =
                        AutoMergeRuntime.GetHookStatus()

                    recordAction(
                        "Auto Merge enabled"
                        .. (cutsceneHook and mergeHook
                            and " - presentation blocked"
                            or "")
                    )

                    if not cutsceneHook or not mergeHook then
                        recordDiagnostic(
                            "Auto Merge hooks: cutscene="
                            .. tostring(cutsceneMode)
                            .. ", merge="
                            .. tostring(mergeMode)
                        )
                    end
                end
            else
                AutoMergeRuntime.Stop()
                recordAction("Auto Merge disabled")
            end

            AutoMergeRuntime.UpdateCardStatus()
            if refreshSummary then
                refreshSummary()
            end
        end
    )

    label(
        MergeCard,
        "RECIPE",
        UDim2.new(0, 10, 0, 80),
        UDim2.new(1, -20, 0, 13),
        8,
        T.Muted,
        T.Font
    )

    label(
        MergeCard,
        "Moon Bloom + Sun Bloom  →  Eclipse Bloom",
        UDim2.new(0, 10, 0, 95),
        UDim2.new(1, -20, 0, 15),
        9,
        T.White,
        T.Font
    )

    label(
        MergeCard,
        "STATUS",
        UDim2.new(0, 10, 0, 117),
        UDim2.new(1, -20, 0, 13),
        8,
        T.Muted,
        T.Font
    )

    AutoMergeRuntime.StatusLabel = label(
        MergeCard,
        "Off  •  0 merged  •  0 Moon  •  0 Sun",
        UDim2.new(0, 10, 0, 132),
        UDim2.new(1, -20, 0, 15),
        9,
        T.Muted,
        T.Font
    )
    AutoMergeRuntime.StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd

    AutoMergeRuntime.DetailLabel = label(
        MergeCard,
        "Moon Bloom + Sun Bloom → Eclipse Bloom",
        UDim2.new(0, 10, 0, 149),
        UDim2.new(1, -20, 0, 14),
        8,
        T.Muted,
        T.Body
    )
    AutoMergeRuntime.DetailLabel.TextTruncate = Enum.TextTruncate.AtEnd

    AutoMergeRuntime.UpdateCardStatus()
end

local StatusCard = createCard(
    .5,
    5,
    770,
    .5,
    -13,
    274,
    "AUTOMATION STATUS"
)

local function statusRow(title, y)
    label(
        StatusCard,
        title,
        UDim2.new(0, 10, 0, y),
        UDim2.new(.55, -10, 0, 16),
        9,
        T.Muted,
        T.Font
    )

    return label(
        StatusCard,
        "IDLE",
        UDim2.new(.55, 0, 0, y),
        UDim2.new(.45, -10, 0, 16),
        9,
        T.White,
        T.Font,
        Enum.TextXAlignment.Right
    )
end

local PlantStatus =
    statusRow(
        "PLANT LOOP",
        29
    )

local HarvestStatus =
    statusRow(
        "HARVEST LOOP",
        51
    )

local SellStatus =
    statusRow(
        "SELL LOOP",
        73
    )

local TrowelStatus =
    statusRow(
        "TROWEL LOOP",
        95
    )

AutoPotRuntime.StatusRow =
    statusRow(
        "POT LOOP",
        117
    )

AutoMergeRuntime.StatusRow =
    statusRow(
        "MERGE LOOP",
        139
    )

local SelectedStatus =
    statusRow(
        "TARGETS",
        161
    )

local ActionDivider =
    N("Frame", {
        BackgroundColor3 = T.Line,
        BackgroundTransparency = .55,

        BorderSizePixel = 0,

        Position = UDim2.new(
            0,
            10,
            0,
            186
        ),

        Size = UDim2.new(
            1,
            -20,
            0,
            1
        )
    }, StatusCard)

local LastActionLabel = label(
    StatusCard,
    "Waiting for automation",
    UDim2.new(0, 10, 0, 194),
    UDim2.new(1, -20, 0, 24),
    9,
    T.Muted,
    T.Body
)

LastActionLabel.TextWrapped = true

local StatsLabel = label(
    StatusCard,
    "0 planted  \u{2022}  0 harvested  \u{2022}  0 sold  \u{2022}  0 potted  \u{2022}  0 merged",
    UDim2.new(0, 10, 1, -27),
    UDim2.new(1, -20, 0, 16),
    8,
    T.Text,
    T.Font,
    Enum.TextXAlignment.Center
)

refreshSummary = function()
    local running =
        State.PlantEnabled
        or State.HarvestEnabled
        or State.SellEnabled
        or State.TrowelEnabled
        or State.PotEnabled
        or State.MergeEnabled

    HeaderStatus.Text =
        running
        and "● RUNNING"
        or "● READY"

    HeaderStatus.TextColor3 =
        running
        and T.Success
        or T.Muted

    PlantStatus.Text =
        State.PlantEnabled
        and "RUNNING"
        or "IDLE"

    PlantStatus.TextColor3 =
        State.PlantEnabled
        and T.Success
        or T.Muted

    HarvestStatus.Text =
        State.HarvestEnabled
        and "RUNNING"
        or "IDLE"

    HarvestStatus.TextColor3 =
        State.HarvestEnabled
        and T.Success
        or T.Muted

    SellStatus.Text =
        State.SellEnabled
        and "RUNNING"
        or "IDLE"

    SellStatus.TextColor3 =
        State.SellEnabled
        and T.Success
        or T.Muted

    TrowelStatus.Text =
        State.TrowelEnabled
        and "RUNNING"
        or "IDLE"

    TrowelStatus.TextColor3 =
        State.TrowelEnabled
        and T.Success
        or T.Muted

    if AutoPotRuntime.StatusRow then
        AutoPotRuntime.StatusRow.Text =
            State.PotEnabled
            and "RUNNING"
            or "IDLE"

        AutoPotRuntime.StatusRow.TextColor3 =
            State.PotEnabled
            and T.Success
            or T.Muted
    end

    AutoPotRuntime.UpdateCardStatus()

    if AutoMergeRuntime.StatusRow then
        local mergeStatus = AutoMergeRuntime.GetStatusText()
        AutoMergeRuntime.StatusRow.Text =
            State.MergeEnabled
            and string.upper(tostring(mergeStatus or "RUNNING"))
            or "IDLE"

        AutoMergeRuntime.StatusRow.TextColor3 =
            State.MergeEnabled
            and T.Success
            or T.Muted
    end

    AutoMergeRuntime.UpdateCardStatus()

    SelectedStatus.Text =
        tostring(
            #State.PlantNames
            + #State.HarvestNames
            + #State.SellNames
            + #(State.PotPlantNames or {})
        )

    LastActionLabel.Text =
        Stats.LastAction

    StatsLabel.Text =
        tostring(Stats.Plants)
        .. " planted  \u{2022}  "
        .. tostring(Stats.Harvests)
        .. " harvested  \u{2022}  "
        .. tostring(Stats.Sells)
        .. " sold  \u{2022}  "
        .. tostring(Stats.Potted)
        .. " potted  \u{2022}  "
        .. tostring(Stats.Merged)
        .. " merged"
end

refreshSummary()

task.spawn(function()
    while ScoopHubRunAlive() and SG.Parent do
        if State.PlantEnabled then
            refreshPlantEventSources(false)

            if not PlantDrainRunning
                and (os.clock() - PlantLastCompletedAt) >= AUTO_PLANT_SAFETY_SECONDS then

                queueAutoPlant("safety")
            end

            task.wait(AUTO_PLANT_SAFETY_SECONDS)
        else
            if #PlantEventConnections > 0 then
                stopAutoPlantScheduler()
            end
            task.wait(1)
        end
    end

    stopAutoPlantScheduler()
end)

task.spawn(function()
    while ScoopHubRunAlive() and SG.Parent do
        if State.HarvestEnabled then
            local ok =
                pcall(
                    automationHarvestOnce
                )

            if not ok then
                State.HarvestBusy =
                    false

                recordAction(
                    "Auto Harvest encountered an error"
                )
            end
        end

        task.wait(
            State.HarvestEnabled
            and 0.2
            or 0.5
        )
    end
end)

task.spawn(function()
    while ScoopHubRunAlive() and SG.Parent do
        if State.TrowelEnabled then
            TrowelRuntime.BindPlantSource()
            TrowelRuntime.QueuePass()
            task.wait(1)
        else
            task.wait(0.75)
        end
    end

    TrowelRuntime.Stop()
end)

local SellDrainRunning = false
local SellEventPending = false

local function queueImmediateAutoSell()
    if not State.SellEnabled then
        return
    end

    SellEventPending = true

    if SellDrainRunning then
        return
    end

    SellDrainRunning = true

    while ScoopHubRunAlive() and State.SellEnabled and SellEventPending do
        SellEventPending = false

        local runId = State.SellRunId
        local ok = pcall(function()
            automationSellOnce(runId)
        end)

        if not ok then
            State.SellBusy = false
            recordDiagnostic("Auto Sell encountered an error")
        end
    end

    SellDrainRunning = false
end

local SellWatchedItems = setmetatable({}, { __mode = "k" })

local function watchSellItem(item)
    if not item or SellWatchedItems[item] then
        return
    end
    SellWatchedItems[item] = true

    local watchedAttributes = {
        "Id", "FruitId", "FruitName", "CorePartName", "SeedName", "PlantName",
        "Weight", "Kg", "FruitWeight", "Mutation", "Rarity",
    }

    for _, attributeName in ipairs(watchedAttributes) do
        TrackConnection(item:GetAttributeChangedSignal(attributeName):Connect(queueImmediateAutoSell))
    end
end

local function watchSellContainer(container)
    if not container then
        return
    end

    for _, item in ipairs(container:GetChildren()) do
        watchSellItem(item)
    end

    TrackConnection(container.ChildAdded:Connect(function(item)
        watchSellItem(item)
        queueImmediateAutoSell()
    end))

    TrackConnection(container.ChildRemoved:Connect(queueImmediateAutoSell))
end

watchSellContainer(LocalPlayer:FindFirstChild("Backpack"))
watchSellContainer(LocalPlayer.Character)

TrackConnection(LocalPlayer.CharacterAdded:Connect(function(character)
    watchSellContainer(character)
    queueImmediateAutoSell()
end))

task.spawn(function()
    while ScoopHubRunAlive() and SG.Parent do
        if State.SellEnabled then
            queueImmediateAutoSell()
        end
        task.wait(0.75)
    end
end)

do
    local AutomationSummaryGeneration = 0

    local function RestartAutomationSummaryWorker()
        AutomationSummaryGeneration += 1
        local myGeneration = AutomationSummaryGeneration

        if not Automation
            or not Automation.Visible
            or not refreshSummary then
            return
        end

        refreshSummary()

        task.spawn(function()
            while ScoopHubRunAlive()
                and SG.Parent
                and Automation.Parent
                and Automation.Visible
                and AutomationSummaryGeneration == myGeneration do

                task.wait(0.5)

                if not ScoopHubRunAlive()
                    or not SG.Parent
                    or not Automation.Parent
                    or not Automation.Visible
                    or AutomationSummaryGeneration ~= myGeneration then
                    break
                end

                if refreshSummary then
                    refreshSummary()
                end
            end
        end)
    end

    TrackConnection(
        Automation:GetPropertyChangedSignal("Visible"):Connect(
            RestartAutomationSummaryWorker
        )
    )

    RestartAutomationSummaryWorker()
end

_G.ScoopHubAutomationAPI = {

    Stop = function()
        State.PlantEnabled = false
        State.HarvestEnabled = false
        State.SellEnabled = false
        State.TrowelEnabled = false
        State.PotEnabled = false
        State.MergeEnabled = false

        stopAutoPlantScheduler()
        TrowelRuntime.Stop()
        AutoPotRuntime.Stop()
        AutoMergeRuntime.Stop()

        State.SellRunId += 1

        PlantToggle:Set(
            false,
            false
        )

        HarvestToggle:Set(
            false,
            false
        )

        SellToggle:Set(
            false,
            false
        )

        TrowelToggle:Set(
            false,
            false
        )

        if AutoPotRuntime.Toggle then
            AutoPotRuntime.Toggle:Set(false, false)
        end

        if AutoMergeRuntime.Toggle then
            AutoMergeRuntime.Toggle:Set(false, false)
        end

        recordAction(
            "Automation stopped"
        )

        refreshSummary()
    end,

    GetSettings = function()
        return {
            PlantNames =
                table.clone(
                    State.PlantNames
                ),

            HarvestNames =
                table.clone(
                    State.HarvestNames
                ),

            SellNames =
                table.clone(
                    State.SellNames
                ),

            PlantEnabled =
                State.PlantEnabled,

            HarvestEnabled =
                State.HarvestEnabled,

            SellEnabled =
                State.SellEnabled,

            TrowelEnabled =
                State.TrowelEnabled,

            PotEnabled =
                State.PotEnabled,

            MergeEnabled =
                State.MergeEnabled,

            PotPlantNames =
                table.clone(State.PotPlantNames or {}),

            TrowelPlantName =
                State.TrowelPlantName,

            TrowelRarity =
                State.TrowelRarity,

            TrowelDelay =
                State.TrowelDelay,

            TrowelPosition =
                typeof(State.TrowelPosition) == "Vector3"
                and {
                    X = State.TrowelPosition.X,
                    Y = State.TrowelPosition.Y,
                    Z = State.TrowelPosition.Z,
                }
                or nil,

            PlantDelay =
                State.PlantDelay,

            PlantLocation =
                State.PlantLocation,

            SprinklerType =
                State.SprinklerType,

            SprinklerRadius =
                getSprinklerRadiusForType(State.SprinklerType),

            HarvestMaxKg =
                State.HarvestMaxKg,

            SellMaxKg =
                State.SellMaxKg,

            HarvestRarities =
                table.clone(
                    State.HarvestRarities
                ),

            HarvestMutations =
                table.clone(
                    State.HarvestMutations
                ),

            SellRarities =
                table.clone(
                    State.SellRarities
                ),

            SellMutations =
                table.clone(
                    State.SellMutations
                ),

            HarvestDirection =
                State.HarvestDirection,

            SellDirection =
                State.SellDirection,
        }
    end,

    ApplySettings = function(data)
        if type(data) ~= "table" then
            return false
        end

        local function copyList(value)
            return type(value) == "table" and table.clone(value) or {}
        end

        local filterAllowed = AutomationWorldData.FilterAllowed
        State.PlantNames = filterAllowed
            and filterAllowed(copyList(data.PlantNames), AllSeeds)
            or copyList(data.PlantNames)
        State.HarvestNames = filterAllowed
            and filterAllowed(copyList(data.HarvestNames), AllSeeds)
            or copyList(data.HarvestNames)
        State.SellNames = filterAllowed
            and filterAllowed(copyList(data.SellNames), AllSeeds)
            or copyList(data.SellNames)
        State.HarvestRarities = copyList(data.HarvestRarities)
        State.HarvestMutations = copyList(data.HarvestMutations)
        State.SellRarities = copyList(data.SellRarities)
        State.SellMutations = copyList(data.SellMutations)

        if data.PotPlantNames == nil then
            State.PotPlantNames = { "All Plants" }
        else
            State.PotPlantNames = copyList(data.PotPlantNames)
        end

        State.TrowelPlantName = tostring(data.TrowelPlantName or "All Plants")
        if State.TrowelPlantName == "" then
            State.TrowelPlantName = "All Plants"
        end

        State.TrowelRarity = tostring(data.TrowelRarity or "Any")
        if State.TrowelRarity == "" then
            State.TrowelRarity = "Any"
        end

        State.TrowelDelay = math.clamp(tonumber(data.TrowelDelay) or 1, 0.05, 5)

        local savedTrowelPosition = data.TrowelPosition
        if type(savedTrowelPosition) == "table" then
            local x = tonumber(savedTrowelPosition.X or savedTrowelPosition.x or savedTrowelPosition[1])
            local y = tonumber(savedTrowelPosition.Y or savedTrowelPosition.y or savedTrowelPosition[2])
            local z = tonumber(savedTrowelPosition.Z or savedTrowelPosition.z or savedTrowelPosition[3])

            if x and y and z then
                State.TrowelPosition = Vector3.new(x, y, z)
            else
                State.TrowelPosition = nil
            end
        else
            State.TrowelPosition = nil
        end

        State.PlantDelay = math.clamp(tonumber(data.PlantDelay) or 0.18, 0.03, 5)
        local savedPlantLocation = tostring(data.PlantLocation or "Random")
        if savedPlantLocation ~= "Sprinkler Radius"
            and savedPlantLocation ~= "Player Position" then
            savedPlantLocation = "Random"
        end
        State.PlantLocation = savedPlantLocation

        local savedSprinklerType = tostring(data.SprinklerType or "")
        if not SprinklerRadiusByType[savedSprinklerType] then

            local legacyRadius = tonumber(data.SprinklerRadius)
            if legacyRadius then
                for _, option in ipairs(SprinklerTypeOptions) do
                    if getSprinklerRadiusForType(option) == legacyRadius then
                        savedSprinklerType = option
                        break
                    end
                end
            end
        end

        if not SprinklerRadiusByType[savedSprinklerType] then
            savedSprinklerType = DEFAULT_SPRINKLER_TYPE
        end

        State.SprinklerType = savedSprinklerType
        State.SprinklerRadius = getSprinklerRadiusForType(savedSprinklerType)
        State.HarvestMaxKg = math.max(0, tonumber(data.HarvestMaxKg) or 100)
        State.SellMaxKg = math.max(0, tonumber(data.SellMaxKg) or 3)
        State.HarvestDirection = data.HarvestDirection == "Above" and "Above" or "Below"
        State.SellDirection = data.SellDirection == "Above" and "Above" or "Below"

        PlantDelayBox.Text = tostring(State.PlantDelay)
        if PlantLocationPickerControl and PlantLocationPickerControl.Refresh then
            PlantLocationPickerControl.Refresh()
        end
        updateSprinklerTypeButton()
        refreshSprinklerTypeControl()
        HarvestKgBox.Text = tostring(State.HarvestMaxKg)
        SellKgBox.Text = tostring(State.SellMaxKg)
        HarvestDirectionButton.Text = State.HarvestDirection .. "  ▼"
        SellDirectionButton.Text = State.SellDirection .. "  ▼"
        TrowelDelayBox.Text = tostring(State.TrowelDelay)
        TrowelRuntime.RefreshPlantOptions()
        AutoPotRuntime.RefreshPlantOptions()
        updateTrowelPositionButton()

        for _, control in ipairs({
            PlantPickerControl, HarvestPickerControl, HarvestRarityPickerControl,
            HarvestMutationPickerControl, SellPickerControl, SellRarityPickerControl,
            SellMutationPickerControl, TrowelPlantPickerControl, TrowelRarityPickerControl,
            AutoPotRuntime.PickerControl,
        }) do
            if control and control.Refresh then
                control.Refresh()
            end
        end

        PlantToggle:Set(data.PlantEnabled == true, true)
        HarvestToggle:Set(data.HarvestEnabled == true, true)
        SellToggle:Set(data.SellEnabled == true, true)
        TrowelToggle:Set(data.TrowelEnabled == true, true)
        if AutoPotRuntime.Toggle then
            AutoPotRuntime.Toggle:Set(data.PotEnabled == true, true)
        end
        if AutoMergeRuntime.Toggle then
            AutoMergeRuntime.Toggle:Set(data.MergeEnabled == true, true)
        end

        refreshSummary()
        return true
    end,

    GetStats = function()
        return {
            Plants =
                Stats.Plants,

            Harvests =
                Stats.Harvests,

            Sells =
                Stats.Sells,

            Trowels =
                Stats.Trowels,

            Potted =
                Stats.Potted,

            Merged =
                Stats.Merged,

            LastAction =
                Stats.LastAction,
        }
    end,
}

_G.__ScoopHubSilentLog(
    "[ScoopHub] Automation page initialized."
)

end

__ScoopHubInitAutomation()

    return true
end

return Module
