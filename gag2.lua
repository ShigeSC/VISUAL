-- ScoopHub Remote Visual Features
-- Extracted from the supplied ScoopHub V2.2 source.
-- Heavy visual/client-side features live here so the main script stays smaller.

local Module = {}

local function createLowGraphics(B)
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = B.LP or game:GetService("Players").LocalPlayer
    local DisableDecorativeStars = type(B.DisableDecorativeStars) == "function"
        and B.DisableDecorativeStars
        or function() end
    local cleanupEnabled = false

-- ScoopHub cleanup behavior: keep the local player's own garden geometry,
-- but strip its texture/effect layers so trees/plants remain visible as plain
-- colored parts. Other gardens/world visuals still use the original aggressive
-- FPS cleanup. Your plot is detected dynamically from Owner / OwnerUserId.
local function getCleanupOwnedPlot()
    local gardens = Workspace:FindFirstChild("Gardens")
    if not gardens then
        return nil
    end

    for _, plot in ipairs(gardens:GetChildren()) do
        local owner = plot:GetAttribute("Owner")
        local ownerUserId = plot:GetAttribute("OwnerUserId")

        if tostring(owner or "") == LocalPlayer.Name
            or tonumber(ownerUserId) == LocalPlayer.UserId then
            return plot
        end
    end

    return nil
end

local function isInsideCleanupOwnedPlot(item, ownedPlot)
    if not item or not ownedPlot then
        return false
    end

    return item == ownedPlot or item:IsDescendantOf(ownedPlot)
end

local function stripOwnedGardenVisual(item)
    -- Keep all actual tree/plant parts/models so the user's garden is still
    -- visible. Only remove texture/effect layers and use SmoothPlastic while
    -- preserving each part's existing Color for a clean "pure color" look.
    if item:IsA("BasePart") then
        pcall(function()
            item.Material = Enum.Material.SmoothPlastic
            item.Reflectance = 0
        end)

        if item:IsA("MeshPart") then
            pcall(function()
                item.TextureID = ""
            end)
        end
    elseif item:IsA("SpecialMesh") then
        pcall(function()
            item.TextureId = ""
        end)
    elseif item:IsA("Texture") or item:IsA("Decal") or item:IsA("SurfaceAppearance")
        or item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
        pcall(function() item:Destroy() end)
    end
end

local function applyLowCPU()
    if not cleanupEnabled then return end

    local Lighting = game:GetService("Lighting")
    local ownedPlot = getCleanupOwnedPlot()

    -- Original cleanup: remove heavy plant/tree/decoration/effect objects from
    -- everywhere EXCEPT the local player's own plot. Their geometry stays.
    for _, item in ipairs(Workspace:GetDescendants()) do
        if not isInsideCleanupOwnedPlot(item, ownedPlot) then
            local nameLower = item.Name:lower()
            if nameLower:find("plant") or nameLower:find("tree") or nameLower:find("flower")
                or nameLower:find("bush") or nameLower:find("crop") or nameLower:find("grass")
                or nameLower:find("vine") or nameLower:find("mushroom") or nameLower:find("visual")
                or nameLower:find("decoration") or nameLower:find("leaf") or nameLower:find("petals") then
                pcall(function() item:Destroy() end)
            end
        end
    end

    -- Keep own-garden geometry but strip textures/effects. Everything else uses
    -- the original aggressive material simplification.
    for _, item in ipairs(Workspace:GetDescendants()) do
        if isInsideCleanupOwnedPlot(item, ownedPlot) then
            stripOwnedGardenVisual(item)
        else
            if item:IsA("BasePart") then
                item.Material = Enum.Material.SmoothPlastic
                item.Color = Color3.fromRGB(180, 180, 200)
                item.Reflectance = 0
            elseif item:IsA("Texture") or item:IsA("Decal") or item:IsA("SurfaceAppearance")
                or item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
                pcall(function() item:Destroy() end)
            elseif item:IsA("MeshPart") then
                pcall(function() item.TextureID = "" end)
            elseif item:IsA("SpecialMesh") then
                pcall(function() item.TextureId = "" end)
            end
        end
    end

    Lighting.GlobalShadows = false
    Lighting.Brightness = 2
    Lighting.ClockTime = 12
    Lighting.FogEnd = 100000
end

local function setCleanupEnabled(enabled)
    cleanupEnabled = enabled == true
    if cleanupEnabled then
        -- PERFORMANCE: remove purely decorative ScoopHub stars as part of
        -- Low Graphics. This does not affect buttons, text, panels, automation,
        -- notifications, or any game logic.
        DisableDecorativeStars()
        applyLowCPU()
    end
end



    return {
        SetLowGraphics = setCleanupEnabled,
        IsLowGraphicsEnabled = function()
            return cleanupEnabled == true
        end,
    }
end

local function createWildPetESP(B)
    local RegisterScoopHubCleanup = type(B.RegisterCleanup) == "function"
        and B.RegisterCleanup
        or function(callback) return callback end
    local getWildPetSpeciesName = B.GetWildPetSpeciesName
    local getWildPetSizeTier = B.GetWildPetSizeTier
    local getPetRarity = B.GetPetRarity

    if type(getWildPetSpeciesName) ~= "function" then
        getWildPetSpeciesName = function(pet)
            return pet and tostring(pet.Name or "Pet") or "Pet"
        end
    end
    if type(getWildPetSizeTier) ~= "function" then
        getWildPetSizeTier = function() return nil end
    end
    if type(getPetRarity) ~= "function" then
        getPetRarity = function() return "Unknown" end
    end

local startWildPetLabels, stopWildPetLabels

-- =========================================================
-- TOGGLE-CONTROLLED WILD PET LABELS
-- Labels are independent from Auto Buy Pet and exist only while PET ESP is ON.
-- Re-executing the hub removes any old labels and starts this toggle OFF.
-- =========================================================
-- REGISTER HEADROOM: Wild Pet label state is owned by its start/stop
-- closures and does not need main-function registers afterward.
do
local WILD_PET_LABEL_FOLDER = "ScoopHubWildPetLabels"
local WILD_PET_RARITY_COLORS = {
    Common = Color3.fromRGB(235, 235, 235),
    Uncommon = Color3.fromRGB(91, 235, 120),
    Rare = Color3.fromRGB(82, 184, 255),
    Legendary = Color3.fromRGB(255, 211, 75),
    Mythic = Color3.fromRGB(255, 83, 99),
    Super = Color3.fromRGB(196, 113, 255),
    Secret = Color3.fromRGB(255, 255, 255),
    Unknown = Color3.fromRGB(235, 235, 235),
}

local wildPetLabelConnections = {}
local wildPetLabels = {}
local sharedEnvironment = type(getgenv) == "function" and getgenv() or _G

if type(sharedEnvironment.ScoopHubStopWildPetLabels) == "function" then
    pcall(sharedEnvironment.ScoopHubStopWildPetLabels)
end

stopWildPetLabels = function()
    for _, connection in ipairs(wildPetLabelConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(wildPetLabelConnections)
    table.clear(wildPetLabels)

    local existingFolder = workspace:FindFirstChild(WILD_PET_LABEL_FOLDER)
    if existingFolder then
        existingFolder:Destroy()
    end
end

sharedEnvironment.ScoopHubStopWildPetLabels = stopWildPetLabels

RegisterScoopHubCleanup(function()
    pcall(stopWildPetLabels)
end)

startWildPetLabels = function()
    stopWildPetLabels()

    local labelFolder = Instance.new("Folder")
    labelFolder.Name = WILD_PET_LABEL_FOLDER
    labelFolder.Parent = workspace

    local function removeLabel(pet)
        local label = wildPetLabels[pet]
        if label then
            wildPetLabels[pet] = nil
            label:Destroy()
        end
    end

    local function addLabel(pet)
        if not pet or not pet:IsA("Model") or wildPetLabels[pet] or not pet.Parent then
            return
        end

        local adornee = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart", true)
        if not adornee then
            return
        end

        local petName = getWildPetSpeciesName(pet)
        local sizeTier = getWildPetSizeTier(pet) or "Normal"
        local rarity = getPetRarity(pet)

        local label = Instance.new("BillboardGui")
        label.Name = "WildPetLabel"
        label.Adornee = adornee
        label.AlwaysOnTop = true
        label.LightInfluence = 0
        label.Size = UDim2.fromOffset(240, 34)
        label.StudsOffset = Vector3.new(0, 4, 0)
        label.Parent = labelFolder

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.BorderSizePixel = 0
        text.Size = UDim2.fromScale(1, 1)
        text.Font = Enum.Font.GothamBold
        text.TextSize = 15
        text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        text.TextStrokeTransparency = 0.2
        text.TextColor3 = WILD_PET_RARITY_COLORS[rarity] or WILD_PET_RARITY_COLORS.Unknown
        text.Text = string.format("%s [%s] ● %s", petName, sizeTier, rarity)
        text.Parent = label

        wildPetLabels[pet] = label
        table.insert(wildPetLabelConnections, pet.AncestryChanged:Connect(function(_, parent)
            if not parent then
                removeLabel(pet)
            end
        end))
    end

    task.spawn(function()
        local deadline = os.clock() + 20
        local wildPetSpawns
        repeat
            local map = workspace:FindFirstChild("Map")
            wildPetSpawns = map and map:FindFirstChild("WildPetSpawns")
            if not wildPetSpawns then
                task.wait(0.25)
            end
        until wildPetSpawns or os.clock() >= deadline

        if not wildPetSpawns or not labelFolder.Parent then
            return
        end

        for _, pet in ipairs(wildPetSpawns:GetChildren()) do
            addLabel(pet)
            task.delay(1, function()
                addLabel(pet)
            end)
        end

        table.insert(wildPetLabelConnections, wildPetSpawns.ChildAdded:Connect(function(pet)
            task.delay(0.1, function()
                addLabel(pet)
            end)
            task.delay(1, function()
                addLabel(pet)
            end)
        end))
        table.insert(wildPetLabelConnections, wildPetSpawns.ChildRemoved:Connect(removeLabel))
    end)
end
end



    return {
        Start = startWildPetLabels,
        Stop = stopWildPetLabels,
        IsEnabled = function()
            return workspace:FindFirstChild("ScoopHubWildPetLabels") ~= nil
        end,
    }
end

function Module.CreateCore(B)
    B = type(B) == "table" and B or {}

    local low = createLowGraphics(B)
    local wild = createWildPetESP(B)

    local API = {}

    function API.SetLowGraphics(value)
        return low.SetLowGraphics(value == true)
    end

    function API.IsLowGraphicsEnabled()
        return low.IsLowGraphicsEnabled()
    end

    function API.SetWildPetESP(value)
        if value == true then
            wild.Start()
        else
            wild.Stop()
        end
        return true
    end

    function API.IsWildPetESPEnabled()
        return wild.IsEnabled()
    end

    function API.Destroy()
        pcall(wild.Stop)
        pcall(low.SetLowGraphics, false)
    end

    return API
end

local function mountCleanup(B)
    local Page = B.Page
    local card = B.Card
    local makeToggle = B.MakeToggle
    local ScoopHubRunAlive = B.RunAlive
    local SG = B.SG
    local TrackConnection = B.TrackConnection

    -- CLEANUP ---------------------------------------------------------------
    local cleanupInitial = false
    if _G.ScoopHubAutoBuyPetAPI and _G.ScoopHubAutoBuyPetAPI.IsCleanupEnabled then
        pcall(function()
            cleanupInitial = _G.ScoopHubAutoBuyPetAPI.IsCleanupEnabled() == true
        end)
    end

    local CleanupCard = card(1, 5, "CLEANUP", "FPS cleanup. Your garden stays visible as plain colors.")
    local CleanupToggle = makeToggle(CleanupCard, cleanupInitial, function(enabled)
        if _G.ScoopHubAutoBuyPetAPI and _G.ScoopHubAutoBuyPetAPI.SetCleanup then
            pcall(function()
                _G.ScoopHubAutoBuyPetAPI.SetCleanup(enabled)
            end)
        end
    end)

    -- V20 PERFORMANCE:
    -- Cleanup is only mirrored into Misc while Misc is actually visible.
    -- The real cleanup system remains fully independent of this presentation.
    do
        local CleanupMirrorGeneration = 0

        local function RefreshCleanupMirror()
            if _G.ScoopHubAutoBuyPetAPI
                and _G.ScoopHubAutoBuyPetAPI.IsCleanupEnabled then

                local ok, value = pcall(function()
                    return _G.ScoopHubAutoBuyPetAPI.IsCleanupEnabled()
                end)

                if ok
                    and CleanupToggle:Get() ~= (value == true) then

                    CleanupToggle:Set(
                        value == true,
                        false
                    )
                end
            end
        end

        local function RestartCleanupMirrorWorker()
            CleanupMirrorGeneration += 1
            local myGeneration = CleanupMirrorGeneration

            if not Page.Visible then
                return
            end

            RefreshCleanupMirror()

            task.spawn(function()
                while ScoopHubRunAlive()
                    and SG.Parent
                    and Page.Parent
                    and Page.Visible
                    and CleanupMirrorGeneration == myGeneration do

                    task.wait(0.5)

                    if not ScoopHubRunAlive()
                        or not SG.Parent
                        or not Page.Parent
                        or not Page.Visible
                        or CleanupMirrorGeneration ~= myGeneration then
                        break
                    end

                    RefreshCleanupMirror()
                end
            end)
        end

        TrackConnection(
            Page:GetPropertyChangedSignal("Visible"):Connect(
                RestartCleanupMirrorWorker
            )
        )

        RestartCleanupMirrorWorker()
    end



    return CleanupToggle
end

local function mountRemoveOtherGardens(B)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LP = B.LP
    local State = B.State
    local TrackConnection = B.TrackConnection
    local card = B.Card
    local makeToggle = B.MakeToggle

    -- REMOVE OTHER GARDENS --------------------------------------------------
    local hiddenFolder = ReplicatedStorage:FindFirstChild("ScoopHubHiddenGardens")
    if not hiddenFolder then
        hiddenFolder = Instance.new("Folder")
        hiddenFolder.Name = "ScoopHubHiddenGardens"
        hiddenFolder.Parent = ReplicatedStorage
    end

    local hiddenGardens = {}
    local gardenAddedConnection
    local RemoveGardenCard = card(2, 5, "REMOVE OTHER GARDENS", "Hide other plots only. Your plot stays.")
    local RemoveGardenToggle

    local function getOwnPlotName()
        local plotId = LP:GetAttribute("PlotId")
        if plotId == nil then
            return nil
        end
        return "Plot" .. tostring(plotId)
    end

    local function hideOtherGardens()
        local gardens = Workspace:FindFirstChild("Gardens")
        local ownPlotName = getOwnPlotName()
        if not gardens or not ownPlotName then
            return false
        end

        for _, plot in ipairs(gardens:GetChildren()) do
            if plot.Name ~= ownPlotName and plot.Name:match("^Plot") then
                hiddenGardens[plot] = gardens
                plot.Parent = hiddenFolder
            end
        end

        return true
    end

    local function restoreOtherGardens()
        if gardenAddedConnection then
            gardenAddedConnection:Disconnect()
            gardenAddedConnection = nil
        end

        local gardens = Workspace:FindFirstChild("Gardens")
        if not gardens then
            gardens = Instance.new("Folder")
            gardens.Name = "Gardens"
            gardens.Parent = Workspace
        end

        for plot in pairs(hiddenGardens) do
            if plot and plot.Parent == hiddenFolder then
                plot.Parent = gardens
            end
            hiddenGardens[plot] = nil
        end
    end

    local function setRemoveOtherGardens(enabled)
        State.RemoveOtherGardens = enabled == true

        if not State.RemoveOtherGardens then
            restoreOtherGardens()
            return true
        end

        if not hideOtherGardens() then
            State.RemoveOtherGardens = false
            return false
        end

        local gardens = Workspace:FindFirstChild("Gardens")
        if gardens then
            gardenAddedConnection = TrackConnection(gardens.ChildAdded:Connect(function(plot)
                if not State.RemoveOtherGardens then return end
                task.defer(function()
                    local ownPlotName = getOwnPlotName()
                    if ownPlotName
                        and plot.Parent == gardens
                        and plot.Name ~= ownPlotName
                        and plot.Name:match("^Plot") then
                        hiddenGardens[plot] = gardens
                        plot.Parent = hiddenFolder
                    end
                end)
            end))
        end

        return true
    end

    RemoveGardenToggle = makeToggle(RemoveGardenCard, State.RemoveOtherGardens, function(enabled)
        local ok = setRemoveOtherGardens(enabled)
        if not ok then
            RemoveGardenToggle:Set(false, false)
        end
    end)

    if State.RemoveOtherGardens then
        local ok = setRemoveOtherGardens(true)
        if not ok then
            RemoveGardenToggle:Set(false, false)
        end
    end




    return RemoveGardenToggle
end

local function mountBackpackValueESP(B)
    local LP = B.LP
    local State = B.State
    local TrackConnection = B.TrackConnection
    local RegisterScoopHubCleanup = B.RegisterCleanup
    local ScoopHubRunAlive = B.RunAlive
    local SG = B.SG
    local card = B.Card
    local makeToggle = B.MakeToggle

    -- BACKPACK VALUE ESP ----------------------------------------------------
    -- Display-only view over Mail Fruits' existing authoritative seller-value
    -- cache. Backpack ESP never starts its own seller scan, so equipping or
    -- unequipping a fruit cannot trigger competing GetFruitBid refreshes.
    -- The exact InventoryController slot -> fruit-instance mapping is preserved
    -- so duplicate fruits with identical names/weights still get the right value.
    local function createBackpackValueRuntime()
        local previous = rawget(_G, "ScoopHubBackpackValueESP")
        if type(previous) == "table" and type(previous.Stop) == "function" then
            pcall(previous.Stop)
        end

        local playerGui = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui")
        local backpack = LP:FindFirstChild("Backpack") or LP:WaitForChild("Backpack")
        local VALUE_COLOR = Color3.fromRGB(255, 199, 74)
        local VALUE_STROKE = Color3.fromRGB(0, 0, 0)
        local SLOT_LABEL_NAME = "ScoopHubFruitValue"
        local TOTAL_LABEL_NAME = "ScoopHubFruitTotalValue"

        local runtime = {
            Enabled = false,
            Connections = {},
            RefreshScheduled = false,
            Generation = 0,
        }

        local api = {}
        local refreshVisuals

        local function track(connection)
            runtime.Connections[#runtime.Connections + 1] = connection
            TrackConnection(connection)
            return connection
        end

        local function disconnectRuntimeConnections()
            for _, connection in ipairs(runtime.Connections) do
                pcall(function()
                    connection:Disconnect()
                end)
            end
            table.clear(runtime.Connections)
        end

        local function destroyOverlayLabels()
            for _, object in ipairs(playerGui:GetDescendants()) do
                if object.Name == SLOT_LABEL_NAME or object.Name == TOTAL_LABEL_NAME then
                    pcall(function()
                        object:Destroy()
                    end)
                end
            end
        end

        local function isHarvestedFruit(item)
            if not item or typeof(item) ~= "Instance" then
                return false
            end

            if item:GetAttribute("HarvestedFruit") ~= true then
                return false
            end

            return item:GetAttribute("Id") ~= nil
                and (item:GetAttribute("FruitName") or item:GetAttribute("Fruit")) ~= nil
                and tonumber(item:GetAttribute("Weight")) ~= nil
        end

        local function getInventoryParts()
            local backpackGui = playerGui:FindFirstChild("BackpackGui")
            local backpackFrame = backpackGui and backpackGui:FindFirstChild("Backpack")
            local inventory = backpackFrame and backpackFrame:FindFirstChild("Inventory")
            local scrolling = inventory and inventory:FindFirstChild("ScrollingFrame")
            local grid = scrolling and scrolling:FindFirstChild("UIGridFrame")
            local favorite = inventory and inventory:FindFirstChild("FavoriteFilter")
            local hotbar = backpackFrame and backpackFrame:FindFirstChild("Hotbar")
            return inventory, grid, favorite, hotbar
        end

        local function collectUpvalues(fn)
            local output = {}

            if type(getupvalues) == "function" then
                local ok, values = pcall(getupvalues, fn)
                if ok and type(values) == "table" then
                    output[#output + 1] = values
                end
            end

            if debug and type(debug.getupvalues) == "function" then
                local ok, values = pcall(debug.getupvalues, fn)
                if ok and type(values) == "table" then
                    output[#output + 1] = values
                end
            end

            return output
        end

        local function fruitFromSlot(slot)
            if not slot or not slot:IsA("GuiButton") or type(getconnections) ~= "function" then
                return nil
            end

            local ok, connections = pcall(getconnections, slot.MouseButton1Click)
            if not ok or type(connections) ~= "table" then
                return nil
            end

            for _, connection in ipairs(connections) do
                local fn
                pcall(function()
                    fn = connection.Function
                end)

                if type(fn) == "function" then
                    for _, values in ipairs(collectUpvalues(fn)) do
                        for _, value in pairs(values) do
                            if type(value) == "table" then
                                local frame = rawget(value, "Frame")
                                local tool = rawget(value, "Tool")

                                if frame == slot
                                    and typeof(tool) == "Instance"
                                    and isHarvestedFruit(tool) then
                                    return tool
                                end
                            end
                        end
                    end
                end
            end

            return nil
        end

        local function trimZeros(text)
            return tostring(text)
                :gsub("(%..-)0+$", "%1")
                :gsub("%.$", "")
        end

        local function compactNumber(value)
            value = tonumber(value) or 0
            local absolute = math.abs(value)
            local divisor = 1
            local suffix = ""

            if absolute >= 1e15 then
                divisor, suffix = 1e15, "Q"
            elseif absolute >= 1e12 then
                divisor, suffix = 1e12, "T"
            elseif absolute >= 1e9 then
                divisor, suffix = 1e9, "B"
            elseif absolute >= 1e6 then
                divisor, suffix = 1e6, "M"
            elseif absolute >= 1e3 then
                divisor, suffix = 1e3, "K"
            end

            if divisor == 1 then
                return tostring(math.floor(value + 0.5))
            end

            return trimZeros(string.format("%.2f", value / divisor)) .. suffix
        end

        local function formatMoney(value)
            return "$" .. compactNumber(value)
        end

        local function getFruitValue(item)
            if not isHarvestedFruit(item) then
                return nil
            end

            -- Mail Fruits is the single owner of seller quotes. Only display an
            -- authoritative cached GetFruitBid value here; never substitute the
            -- local calculator while Mail is still resolving the fruit.
            local bridge = _G.ScoopHubMailFruitInventoryAPI
            local id = tostring(item:GetAttribute("Id"))
            local cache = bridge and bridge.FruitValueCache
            local cached = cache and cache[id]
            local cachedValue = cached and tonumber(cached.Value)

            if cachedValue ~= nil then
                return math.floor(cachedValue)
            end

            return nil
        end

        local function ensureSlotValueLabel(slot)
            local labelObject = slot:FindFirstChild(SLOT_LABEL_NAME)
            if labelObject and not labelObject:IsA("TextLabel") then
                labelObject:Destroy()
                labelObject = nil
            end

            if not labelObject then
                labelObject = Instance.new("TextLabel")
                labelObject.Name = SLOT_LABEL_NAME
                labelObject.BackgroundTransparency = 1
                labelObject.BorderSizePixel = 0
                labelObject.Position = UDim2.new(0, 1, 0, 0)
                labelObject.Size = UDim2.new(1, -2, 0, 18)
                labelObject.Font = Enum.Font.GothamBold
                labelObject.TextSize = 14
                labelObject.TextColor3 = VALUE_COLOR
                labelObject.TextStrokeColor3 = VALUE_STROKE
                labelObject.TextStrokeTransparency = 0.25
                labelObject.TextXAlignment = Enum.TextXAlignment.Center
                labelObject.TextYAlignment = Enum.TextYAlignment.Center
                labelObject.TextTruncate = Enum.TextTruncate.AtEnd
                labelObject.ZIndex = 12
                labelObject.Parent = slot
            else
                labelObject.TextColor3 = VALUE_COLOR
            end

            return labelObject
        end

        local function ensureTotalLabel(inventory, favorite)
            if not inventory or not favorite then
                return nil
            end

            local totalLabel = inventory:FindFirstChild(TOTAL_LABEL_NAME)
            if totalLabel and not totalLabel:IsA("TextLabel") then
                totalLabel:Destroy()
                totalLabel = nil
            end

            if not totalLabel then
                totalLabel = Instance.new("TextLabel")
                totalLabel.Name = TOTAL_LABEL_NAME
                totalLabel.BackgroundTransparency = 1
                totalLabel.BorderSizePixel = 0
                totalLabel.AnchorPoint = Vector2.new(1, 0)
                totalLabel.Size = UDim2.fromOffset(125, 30)
                totalLabel.Font = Enum.Font.GothamBold
                totalLabel.TextSize = 12
                totalLabel.TextColor3 = VALUE_COLOR
                totalLabel.TextStrokeColor3 = VALUE_STROKE
                totalLabel.TextStrokeTransparency = 0.35
                totalLabel.TextXAlignment = Enum.TextXAlignment.Right
                totalLabel.TextYAlignment = Enum.TextYAlignment.Center
                totalLabel.ZIndex = math.max(2, favorite.ZIndex + 1)
                totalLabel.Parent = inventory
            else
                totalLabel.TextColor3 = VALUE_COLOR
            end

            totalLabel.Position = UDim2.new(
                favorite.Position.X.Scale,
                favorite.Position.X.Offset - 8,
                favorite.Position.Y.Scale,
                favorite.Position.Y.Offset
            )

            return totalLabel
        end

        local function collectHarvestedFruits()
            local list = {}
            local seen = {}

            local function scan(container)
                if not container then return end
                for _, item in ipairs(container:GetChildren()) do
                    if isHarvestedFruit(item) then
                        local id = tostring(item:GetAttribute("Id"))
                        if not seen[id] then
                            seen[id] = true
                            list[#list + 1] = item
                        end
                    end
                end
            end

            scan(backpack)
            scan(LP.Character)
            return list
        end

        local function renderFruitSlots(root)
            if not root then return end

            local candidates = { root }
            for _, object in ipairs(root:GetDescendants()) do
                candidates[#candidates + 1] = object
            end

            for _, slot in ipairs(candidates) do
                if slot:IsA("GuiButton") then
                    local fruit = fruitFromSlot(slot)
                    local existing = slot:FindFirstChild(SLOT_LABEL_NAME)

                    if fruit then
                        local valueLabel = ensureSlotValueLabel(slot)
                        local value = getFruitValue(fruit)
                        valueLabel.Text = value ~= nil and formatMoney(value) or ""
                        valueLabel.Visible = runtime.Enabled
                    elseif existing then
                        existing:Destroy()
                    end
                end
            end
        end

        refreshVisuals = function()
            if not runtime.Enabled then
                return
            end

            local inventory, grid, favorite, hotbar = getInventoryParts()
            if not inventory and not hotbar then
                return
            end

            local totalLabel = inventory and ensureTotalLabel(inventory, favorite) or nil

            if grid then
                renderFruitSlots(grid)
            end
            if hotbar then
                renderFruitSlots(hotbar)
            end

            local total = 0
            local unresolved = 0
            for _, fruit in ipairs(collectHarvestedFruits()) do
                local value = getFruitValue(fruit)
                if value ~= nil then
                    total += value
                else
                    unresolved += 1
                end
            end

            if totalLabel then
                totalLabel.Text = unresolved > 0
                    and "Total: ..."
                    or ("Total: " .. formatMoney(total))
                totalLabel.Visible = true
            end
        end

        local function scheduleRefresh(delaySeconds)
            if not runtime.Enabled then
                return
            end

            if runtime.RefreshScheduled then
                return
            end

            runtime.RefreshScheduled = true
            task.delay(delaySeconds or 0.12, function()
                runtime.RefreshScheduled = false
                if runtime.Enabled then
                    pcall(refreshVisuals)
                end
            end)
        end

        local function watchCharacter(character)
            if not character then return end
            track(character.ChildAdded:Connect(function()
                scheduleRefresh(0.18)
            end))
            track(character.ChildRemoved:Connect(function()
                scheduleRefresh(0.18)
            end))
        end

        function api.Start()
            if runtime.Enabled then
                pcall(refreshVisuals)
                return true
            end

            if type(getconnections) ~= "function" then
                warn("[ScoopHub] Backpack Value ESP requires getconnections support.")
                return false
            end

            runtime.Enabled = true
            runtime.Generation += 1
            local generation = runtime.Generation

            track(backpack.ChildAdded:Connect(function()
                scheduleRefresh(0.18)
            end))
            track(backpack.ChildRemoved:Connect(function()
                scheduleRefresh(0.18)
            end))

            track(LP.CharacterAdded:Connect(function(character)
                watchCharacter(character)
                scheduleRefresh(0.4)
            end))
            watchCharacter(LP.Character)

            track(playerGui.DescendantAdded:Connect(function(object)
                if object.Name == "UIGridFrame"
                    or object.Name == "Hotbar"
                    or object.Name == "FavoriteFilter"
                    or object.Name == "ToolName"
                    or object.Name == "ToolCount" then
                    scheduleRefresh(0.15)
                end
            end))

            scheduleRefresh(0.15)

            -- Lightweight visible-inventory reconciliation only redraws labels.
            -- Mail Fruits independently owns initial/new-fruit/price-reset scans.
            task.spawn(function()
                while runtime.Enabled
                    and runtime.Generation == generation
                    and ScoopHubRunAlive()
                    and SG.Parent do
                    local inventory, _, _, hotbar = getInventoryParts()
                    local inventoryVisible = inventory and inventory.Visible
                    local hotbarVisible = hotbar and hotbar.Visible

                    if inventoryVisible or hotbarVisible then
                        pcall(refreshVisuals)
                        task.wait(1)
                    else
                        task.wait(2)
                    end
                end
            end)

            return true
        end

        function api.Stop()
            runtime.Enabled = false
            runtime.Generation += 1
            runtime.RefreshScheduled = false
            disconnectRuntimeConnections()
            destroyOverlayLabels()
        end

        function api.Refresh()
            if runtime.Enabled then
                scheduleRefresh(0)
            end
        end

        function api.IsEnabled()
            return runtime.Enabled == true
        end

        _G.ScoopHubBackpackValueESP = api
        return api
    end

    local BackpackValueRuntime = createBackpackValueRuntime()
    RegisterScoopHubCleanup(function()
        BackpackValueRuntime.Stop()
    end)

    local BackpackValueCard = card(2, 6, "BACKPACK VALUE ESP", "Show live Sheckles values in Backpack / Hotbar.")
    local BackpackValueToggle
    BackpackValueToggle = makeToggle(BackpackValueCard, false, function(enabled)
        if enabled then
            local ok = BackpackValueRuntime.Start()
            State.BackpackValueESP = ok == true
            if not ok then
                BackpackValueToggle:Set(false, false)
            end
        else
            State.BackpackValueESP = false
            BackpackValueRuntime.Stop()
        end
    end)




    return BackpackValueToggle
end

local function mountWildPetESP(B)
    local card = B.Card
    local makeToggle = B.MakeToggle

    -- WILD PET ESP ----------------------------------------------------------
    -- Presentation control lives in Misc; the actual label engine remains
    -- owned by Auto Buy Pet so no pet logic is duplicated here.
    local WildPetEspCard = card(1, 6, "WILD PET ESP", "Show Name / Size / Rarity above wild pets.")
    local WildPetEspToggle
    WildPetEspToggle = makeToggle(WildPetEspCard, false, function(enabled)
        local api = _G.ScoopHubAutoBuyPetAPI
        if api and type(api.SetWildPetESP) == "function" then
            local ok = pcall(api.SetWildPetESP, enabled == true)
            if not ok then
                WildPetEspToggle:Set(false, false)
            end
        else
            WildPetEspToggle:Set(false, false)
        end
    end)

    -- ESP intentionally starts OFF on every execution, regardless of prior
    -- Misc/config state. This also clears any stale labels from an older run.
    if _G.ScoopHubAutoBuyPetAPI and type(_G.ScoopHubAutoBuyPetAPI.SetWildPetESP) == "function" then
        pcall(_G.ScoopHubAutoBuyPetAPI.SetWildPetESP, false)
    end



    return WildPetEspToggle
end

local function mountGardenESP(B)
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP = B.LP
    local State = B.State
    local Page = B.Page
    local card = B.Card
    local label = B.Label
    local N = B.N
    local C = B.C
    local S = B.S
    local T = B.T
    local TrackConnection = B.TrackConnection
    local RegisterScoopHubCleanup = B.RegisterCleanup
    local ScoopHubRunAlive = B.RunAlive
    local SG = B.SG
    local Scale = B.Scale
    local UIS = B.UIS
    local tw = B.Tween
    local GARDEN_ESP_CARD_H = tonumber(B.GardenEspCardHeight) or 170

    -- GARDEN ESP ------------------------------------------------------------
    -- Full-width Misc card. The runtime is completely idle while disabled or
    -- while either multi-select has no usable selection.
    local GardenESPFeature = (function()
        local feature = {}
        local runtime = {
            Enabled = false,
            FruitAll = false,
            MutationAll = true,
            SelectedFruits = {},
            SelectedMutations = {},
            KnownFruits = {},
            KnownMutations = {},
            Labels = {},
            Connections = {},
            WorkerGeneration = 0,
            ModulesReady = false,
            ModulesFailed = false,
            Modules = {},
            ModuleCache = {},
            ResolveCache = {},
            MultiCache = {},
            MutationCache = {},
            SyncCache = {},
            SellNorm = {},
            SingleHarvest = {},
            LastData = {},
        }

        local STATIC_MUTATIONS = {
            "Normal", "Gold", "Rainbow", "Wet", "Chilled", "Frozen",
            "Shocked", "Choc", "Moonlit", "Bloodlit", "Celestial",
            "Zombified", "Plasma", "Voidtouched", "Pollinated", "Twisted",
            "Disco", "Windstruck", "Dawnbound", "Electric", "Burnt",
            "HoneyGlazed", "Cooked", "Molten", "Sundried", "Wilted",
            "Alienlike",
        }

        for _, mutationName in ipairs(STATIC_MUTATIONS) do
            runtime.KnownMutations[mutationName] = true
        end

        local worldData = _G.ScoopHubWorldData
        local currentWorld = worldData and worldData.Current
        for _, seedName in ipairs(currentWorld and currentWorld.Seeds or {}) do
            local cleanName = tostring(seedName or "")
                :gsub("%s*[Ss]eed%s*$", "")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
            if cleanName ~= "" then
                runtime.KnownFruits[cleanName] = true
            end
        end

        local function sortedKeys(set)
            local output = {}
            for key, selected in pairs(set or {}) do
                if selected == true then
                    output[#output + 1] = tostring(key)
                end
            end
            table.sort(output, function(a, b)
                return string.lower(a) < string.lower(b)
            end)
            return output
        end

        local function selectedCount(set)
            local count = 0
            for _, selected in pairs(set or {}) do
                if selected == true then
                    count += 1
                end
            end
            return count
        end

        local function clearSet(set)
            for key in pairs(set) do
                set[key] = nil
            end
        end

        local function copyListIntoSet(list, destination, known)
            clearSet(destination)
            if type(list) ~= "table" then
                return
            end
            for _, value in ipairs(list) do
                local textValue = tostring(value or "")
                if textValue ~= "" then
                    destination[textValue] = true
                    if known then
                        known[textValue] = true
                    end
                end
            end
        end

        local function destroyLabels()
            for key, record in pairs(runtime.Labels) do
                if record.Billboard and record.Billboard.Parent then
                    pcall(function()
                        record.Billboard:Destroy()
                    end)
                end
                runtime.Labels[key] = nil
            end
        end

        local labelFolder = LP:FindFirstChildOfClass("PlayerGui")
            and LP:FindFirstChildOfClass("PlayerGui"):FindFirstChild("ScoopHubGardenESP")
        if labelFolder then
            labelFolder:Destroy()
            labelFolder = nil
        end

        local function ensureLabelFolder()
            if labelFolder and labelFolder.Parent then
                return labelFolder
            end

            local playerGui = LP:FindFirstChildOfClass("PlayerGui")
                or LP:WaitForChild("PlayerGui", 10)
            if not playerGui then
                return nil
            end

            local stale = playerGui:FindFirstChild("ScoopHubGardenESP")
            if stale then
                stale:Destroy()
            end

            labelFolder = Instance.new("Folder")
            labelFolder.Name = "ScoopHubGardenESP"
            labelFolder.Parent = playerGui
            return labelFolder
        end

        local function rgbHex(color)
            return string.format(
                "#%02X%02X%02X",
                math.floor(color.R * 255 + 0.5),
                math.floor(color.G * 255 + 0.5),
                math.floor(color.B * 255 + 0.5)
            )
        end

        local function escapeRichText(value)
            return tostring(value or "")
                :gsub("&", "&amp;")
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
                :gsub('"', "&quot;")
                :gsub("'", "&apos;")
        end

        local function formatCompact(value)
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

        local function formatKG(value)
            value = tonumber(value) or 0

            if value >= 1e6 then
                return (string.format("%.2fM", value / 1e6)
                    :gsub("%.00", "")
                    :gsub("(%.[0-9])0", "%1")) .. "kg"
            elseif value >= 1e3 then
                return (string.format("%.2fK", value / 1e3)
                    :gsub("%.00", "")
                    :gsub("(%.[0-9])0", "%1")) .. "kg"
            end

            return string.format("%.1f", value):gsub("%.0$", "") .. "kg"
        end

        local function buildESPText(data)
            return string.format(
                '<font color="%s"><b>%s</b></font> <font color="%s">[%s]</font> <font color="%s">%s</font> <font color="%s">•</font> <font color="%s"><b>%s</b></font>',
                rgbHex(T.White),
                escapeRichText(data.Name),
                rgbHex(T.Text),
                escapeRichText(data.Mutation or "Normal"),
                rgbHex(T.Muted),
                escapeRichText(formatKG(data.KG)),
                rgbHex(T.Muted),
                rgbHex(Color3.fromRGB(255, 199, 74)),
                escapeRichText(formatCompact(data.Value))
            )
        end

        local function findAnchorAndCenterOffset(object)
            if not object or not object.Parent then
                return nil, Vector3.zero
            end

            -- BasePart fruits are already centered on their own part.
            if object:IsA("BasePart") then
                return object, Vector3.zero
            end

            -- For Models, use any stable BasePart as the Billboard Adornee but
            -- offset the Billboard to the model's real bounding-box CENTER.
            -- This keeps the ESP literally inside/centered on the fruit instead
            -- of floating above it.
            if object:IsA("Model") then
                local anchor = object.PrimaryPart
                    or object:FindFirstChildWhichIsA("BasePart", true)

                if not anchor then
                    return nil, Vector3.zero
                end

                local ok, boxCFrame = pcall(function()
                    return object:GetBoundingBox()
                end)

                if ok and boxCFrame then
                    return anchor, boxCFrame.Position - anchor.Position
                end

                return anchor, Vector3.zero
            end

            -- Fallback for unusual fruit containers: choose the part closest
            -- to the container's average part position rather than the highest
            -- part, so the label still sits near the visual center.
            local parts = {}
            local sum = Vector3.zero

            for _, descendant in ipairs(object:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    parts[#parts + 1] = descendant
                    sum += descendant.Position
                end
            end

            if #parts == 0 then
                return nil, Vector3.zero
            end

            local center = sum / #parts
            local best = parts[1]
            local bestDistance = (best.Position - center).Magnitude

            for index = 2, #parts do
                local part = parts[index]
                local distance = (part.Position - center).Magnitude
                if distance < bestDistance then
                    best = part
                    bestDistance = distance
                end
            end

            return best, center - best.Position
        end

        local function ensureLabel(data)
            local record = runtime.Labels[data.Key]
            if record and record.Billboard and record.Billboard.Parent then
                return record
            end

            local folder = ensureLabelFolder()
            if not folder then
                return nil
            end

            local mobile = UIS.TouchEnabled and not UIS.KeyboardEnabled
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "GardenESP_" .. tostring(data.Key)
            billboard.Size = UDim2.fromOffset(mobile and 250 or 310, mobile and 20 or 24)
            billboard.StudsOffsetWorldSpace = Vector3.zero
            billboard.AlwaysOnTop = true
            billboard.LightInfluence = 0
            pcall(function()
                billboard.MaxDistance = 135
            end)
            billboard.Parent = folder

            local textObject = Instance.new("TextLabel")
            textObject.Name = "Text"
            textObject.Size = UDim2.fromScale(1, 1)
            textObject.BackgroundTransparency = 1
            textObject.BorderSizePixel = 0
            textObject.RichText = true
            textObject.Text = ""
            textObject.TextColor3 = T.White
            textObject.TextSize = mobile and 10 or 12
            textObject.TextStrokeColor3 = Color3.new(0, 0, 0)
            textObject.TextStrokeTransparency = 0.45
            textObject.Font = Enum.Font.Gotham
            textObject.TextXAlignment = Enum.TextXAlignment.Center
            textObject.TextYAlignment = Enum.TextYAlignment.Center
            textObject.Parent = billboard

            record = {
                Billboard = billboard,
                Text = textObject,
                Anchor = nil,
            }
            runtime.Labels[data.Key] = record
            return record
        end

        local function updateLabel(data)
            local anchor, centerOffset = findAnchorAndCenterOffset(data.Object)
            if not anchor then
                return false
            end

            local record = ensureLabel(data)
            if not record then
                return false
            end

            record.Anchor = anchor
            record.Billboard.Adornee = anchor
            record.Billboard.StudsOffsetWorldSpace = centerOffset
            record.Billboard.Enabled = true
            record.Text.Text = buildESPText(data)
            return true
        end

        local function hasUsableSelection()
            local fruitOK = runtime.FruitAll or selectedCount(runtime.SelectedFruits) > 0
            local mutationOK = runtime.MutationAll or selectedCount(runtime.SelectedMutations) > 0
            return fruitOK and mutationOK
        end

        local function compactFruitName(value)
            return tostring(value or "")
                :gsub("%s*[Ss]eed%s*$", "")
                :lower()
                :gsub("[^%w]", "")
        end

        local function fruitSelectionMatches(value)
            if runtime.FruitAll then
                return true
            end

            if runtime.SelectedFruits[tostring(value or "")] == true then
                return true
            end

            local actual = compactFruitName(value)
            if actual == "" then
                return false
            end

            for selectedName, selected in pairs(runtime.SelectedFruits) do
                if selected and compactFruitName(selectedName) == actual then
                    return true
                end
            end

            return false
        end

        local function mutationSelectionMatches(value)
            if runtime.MutationAll then
                return true
            end

            local actual = string.lower(tostring(value or "Normal"))
            for selectedName, selected in pairs(runtime.SelectedMutations) do
                if selected and string.lower(tostring(selectedName)) == actual then
                    return true
                end
            end
            return false
        end

        local function shouldShow(data)
            if not runtime.Enabled then
                return false
            end

            return fruitSelectionMatches(data.Name)
                and mutationSelectionMatches(data.Mutation)
        end

        local function applyData(dataList)
            runtime.LastData = dataList or {}
            local seen = {}

            if runtime.Enabled and hasUsableSelection() then
                for _, data in ipairs(runtime.LastData) do
                    if shouldShow(data) and updateLabel(data) then
                        seen[data.Key] = true
                    end
                end
            end

            for key, record in pairs(runtime.Labels) do
                if not seen[key] then
                    if record.Billboard and record.Billboard.Parent then
                        record.Billboard:Destroy()
                    end
                    runtime.Labels[key] = nil
                end
            end
        end

        local function need(parent, name, timeout)
            local object = parent and parent:WaitForChild(name, timeout or 10)
            if not object then
                error("Missing " .. tostring(name))
            end
            return object
        end

        local function normalize(value)
            return tostring(value or ""):lower():gsub("[^%w]", "")
        end

        local function ensureModules()
            if runtime.ModulesReady then
                return true
            end
            if runtime.ModulesFailed then
                return false
            end

            local ok, err = pcall(function()
                local sharedModules = need(ReplicatedStorage, "SharedModules", 10)
                local G = runtime.Modules
                G.Sell = require(need(sharedModules, "SellValueData", 10))
                G.MutationData = require(need(sharedModules, "MutationData", 10))
                G.SeedData = require(need(sharedModules, "SeedData", 10))
                G.FruitIdentity = require(need(sharedModules, "FruitIdentity", 10))

                local controllers = need(
                    need(LP, "PlayerScripts", 10),
                    "Controllers",
                    10
                )
                G.GardenSync = require(
                    need(controllers, "GardenSyncController", 10)
                )

                local generation = need(ReplicatedStorage, "PlantGenerationModules", 10)
                G.FruitModules = need(generation, "Fruits", 10)
                G.PlantModules = need(generation, "Plants", 10)

                clearSet(runtime.SellNorm)
                for key in pairs(G.Sell) do
                    runtime.SellNorm[normalize(key)] = key
                end

                clearSet(runtime.SingleHarvest)
                for _, value in pairs(G.SeedData) do
                    if type(value) == "table" and value.SeedName then
                        runtime.SingleHarvest[value.SeedName] = value.IsSingleHarvest == true
                    end
                end
            end)

            if not ok then
                runtime.ModulesFailed = true
                warn("[ScoopHub Garden ESP] Required modules unavailable: " .. tostring(err))
                return false
            end

            runtime.ModulesReady = true
            return true
        end

        local function getOwnPlot()
            local gardens = Workspace:FindFirstChild("Gardens")
            if not gardens then
                return nil
            end

            local plotId = LP:GetAttribute("PlotId")
            if plotId ~= nil then
                local direct = gardens:FindFirstChild("Plot" .. tostring(plotId))
                if direct then
                    return direct
                end
            end

            for _, plot in ipairs(gardens:GetChildren()) do
                if plot:GetAttribute("OwnerUserId") == LP.UserId
                    or plot:GetAttribute("Owner") == LP.Name then
                    return plot
                end
            end
            return nil
        end

        local function resolveFruit(seed)
            if not seed then
                return nil
            end
            if runtime.ResolveCache[seed] ~= nil then
                return runtime.ResolveCache[seed]
            end

            local G = runtime.Modules
            local ok, value = pcall(function()
                return G.FruitIdentity.ResolveFruitName(seed)
            end)
            value = ok and value or seed
            runtime.ResolveCache[seed] = value
            return value
        end

        local function isMulti(seed)
            if runtime.MultiCache[seed] ~= nil then
                return runtime.MultiCache[seed]
            end
            local resolved = resolveFruit(seed)
            local G = runtime.Modules
            local value = resolved ~= nil
                and G.FruitModules:FindFirstChild(resolved) ~= nil
                or false
            runtime.MultiCache[seed] = value
            return value
        end

        local function getModuleData(folder, name)
            if not name then
                return nil
            end

            local key = folder:GetFullName() .. "|" .. tostring(name)
            if runtime.ModuleCache[key] ~= nil then
                return runtime.ModuleCache[key] or nil
            end

            local module = folder:FindFirstChild(name)
            if not module then
                local wanted = normalize(name)
                for _, candidate in ipairs(folder:GetChildren()) do
                    if candidate:IsA("ModuleScript")
                        and normalize(candidate.Name) == wanted then
                        module = candidate
                        break
                    end
                end
            end

            if not module or not module:IsA("ModuleScript") then
                runtime.ModuleCache[key] = false
                return nil
            end

            local ok, data = pcall(require, module)
            if not ok or type(data) ~= "table" then
                runtime.ModuleCache[key] = false
                return nil
            end

            runtime.ModuleCache[key] = data
            return data
        end

        local function baseWeight(folder, name)
            local data = getModuleData(folder, name)
            return data
                and data.GrowData
                and tonumber(data.GrowData.BaseWeight)
                or nil
        end

        local function mutationMultiplier(name)
            if not name or name == "" then
                return 1
            end
            if runtime.MutationCache[name] ~= nil then
                return runtime.MutationCache[name]
            end

            local ok, value = pcall(function()
                return runtime.Modules.MutationData.ReturnPriceMultiplier(name)
            end)
            value = ok and tonumber(value) or 1
            runtime.MutationCache[name] = value
            return value
        end

        local function sellKey(...)
            local names = {...}
            local G = runtime.Modules

            for _, name in ipairs(names) do
                if name and G.Sell[name] ~= nil then
                    return name
                end
            end

            for _, name in ipairs(names) do
                if name then
                    local found = runtime.SellNorm[normalize(name)]
                    if found then
                        return found
                    end
                end
            end

            return names[1]
        end

        local function calculateValue(name, size, mutation, decayAlpha)
            if not name then
                return 0
            end

            local base = tonumber(runtime.Modules.Sell[name]) or 0
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
                sizeValue = knee ^ exponent
                    * (size / knee) ^ math.min(tailExponent, exponent)
            end

            local mutationValue = 1
            if mutation and mutation ~= "" then
                mutationValue = mutationMultiplier(mutation)
                if runtime.SingleHarvest[name] and mutationValue > 1 then
                    mutationValue = 1 + (mutationValue - 1) * 0.15
                end
            end

            local decayMultiplier = 1
            if type(decayAlpha) == "number" and decayAlpha > 0 then
                decayMultiplier = 1 - math.clamp(decayAlpha, 0, 1) * 0.8
            end

            local friends = tonumber(LP:GetAttribute("Friends")) or 0
            local friendMultiplier = 1 + friends * 0.1

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
            clearSet(runtime.SyncCache)
        end

        local function syncedPlant(plant)
            local cached = runtime.SyncCache[plant]
            if cached ~= nil then
                return cached ~= false and cached or nil
            end

            local plantId = plant:GetAttribute("PlantId")
            if not plantId then
                runtime.SyncCache[plant] = false
                return nil
            end

            local userId = tonumber(plant:GetAttribute("UserId")) or LP.UserId
            local ok, data = pcall(function()
                return runtime.Modules.GardenSync:GetPlant(userId, plantId)
            end)

            if not ok or type(data) ~= "table" then
                runtime.SyncCache[plant] = false
                return nil
            end

            runtime.SyncCache[plant] = data
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
                1 + 0.0128 * (math.log(1 + seconds / 1800) ^ 2.55),
                25
            )
        end

        local function makeMultiData(plant, fruit, plantData, serverNow)
            local seed = plant:GetAttribute("SeedName")
            local resolved = resolveFruit(seed)
            local core = fruit:GetAttribute("CorePartName") or resolved
            local synced = syncedFruit(plantData, fruit)

            local size = tonumber(fruit:GetAttribute("SizeMulti"))
                or tonumber(synced and synced.SizeMultiplier)
                or tonumber(fruit:GetAttribute("SizeMultiplier"))
                or 1

            local overtime = tonumber(synced and synced.OvertimeGrowth)
                or tonumber(fruit:GetAttribute("OvertimeGrowth"))
                or 1
            overtime = math.max(overtime, 1)

            local atlantic = normalize(resolved) == "atlanticgiantpumpkin"
                or normalize(core) == "atlanticgiantpumpkin"
                or normalize(seed) == "atlanticgiantpumpkin"

            if atlantic then
                local finished = tonumber(synced and synced.FinishedGrowingAt)
                    or tonumber(fruit:GetAttribute("FinishedGrowingAt"))
                if finished and finished > 0 then
                    overtime = atlanticGrowth(math.max(serverNow - finished, 0))
                end
            end

            local weightBase = baseWeight(runtime.Modules.FruitModules, core)
            if not weightBase and resolved then
                weightBase = baseWeight(runtime.Modules.FruitModules, resolved)
            end
            weightBase = weightBase or 0

            local mutation = (synced and synced.Mutation)
                or fruit:GetAttribute("Mutation")
            if mutation == "" then
                mutation = nil
            end

            local valueName = sellKey(core, resolved, seed)
            local decay = (synced and synced.DecayAlpha)
                or fruit:GetAttribute("DecayAlpha")

            return {
                Key = "M|"
                    .. tostring(plant:GetAttribute("PlantId"))
                    .. "|"
                    .. tostring(fruit:GetAttribute("FruitId")),
                Name = seed or resolved or core or fruit.Name,
                Mutation = mutation or "Normal",
                KG = weightBase * size * overtime,
                Value = calculateValue(valueName, size, mutation, decay),
                Object = fruit,
            }
        end

        local function makeSingleData(plant, plantData)
            if not plantData then
                return nil
            end

            local seed = plant:GetAttribute("SeedName")
            local resolved = resolveFruit(seed)
            local size = tonumber(plantData.SizeMultiplier) or 1
            local overtime = math.max(tonumber(plantData.OvertimeGrowth) or 1, 1)
            local weightBase = baseWeight(runtime.Modules.PlantModules, seed)
                or baseWeight(runtime.Modules.PlantModules, plantData.PlantName)
                or 0
            local weight = tonumber(plantData.Weight)
                or weightBase * size * overtime
            local mutation = plantData.Mutation
                or plant:GetAttribute("Mutation")
            if mutation == "" then
                mutation = nil
            end

            local valueName = sellKey(resolved, seed, plantData.PlantName)
            local decay = plantData.DecayAlpha
                or plant:GetAttribute("DecayAlpha")

            return {
                Key = "S|" .. tostring(plant:GetAttribute("PlantId")),
                Name = seed or plantData.PlantName or plant.Name,
                Mutation = mutation or "Normal",
                KG = weight,
                Value = calculateValue(valueName, size, mutation, decay),
                Object = plant,
            }
        end

        local function scanGarden()
            if not ensureModules() then
                return {}
            end

            resetSyncCache()
            local output = {}
            local plot = getOwnPlot()
            local plants = plot and plot:FindFirstChild("Plants")
            if not plants then
                return output
            end

            local serverNow = Workspace:GetServerTimeNow()
            local sliceStart = os.clock()

            local function yieldIfNeeded()
                if os.clock() - sliceStart >= 0.0025 then
                    task.wait()
                    sliceStart = os.clock()
                end
            end

            for _, plant in ipairs(plants:GetChildren()) do
                if not runtime.Enabled or not ScoopHubRunAlive() then
                    break
                end

                local seed = plant:GetAttribute("SeedName")
                if seed then
                    runtime.KnownFruits[tostring(seed)] = true

                    -- Do not calculate GardenSync/value data for fruit types the
                    -- user did not select. This keeps ESP cheap in huge gardens.
                    if not fruitSelectionMatches(seed) then
                        continue
                    end

                    local plantData = syncedPlant(plant)

                    if isMulti(seed) then
                        local fruits = plant:FindFirstChild("Fruits")
                        if fruits then
                            for _, fruit in ipairs(fruits:GetChildren()) do
                                if fruit:GetAttribute("FruitId") ~= nil then
                                    local ok, data = pcall(
                                        makeMultiData,
                                        plant,
                                        fruit,
                                        plantData,
                                        serverNow
                                    )
                                    if ok and data then
                                        runtime.KnownMutations[data.Mutation] = true
                                        output[#output + 1] = data
                                    end
                                    yieldIfNeeded()
                                end
                            end
                        end
                    else
                        local ok, data = pcall(makeSingleData, plant, plantData)
                        if ok and data then
                            runtime.KnownMutations[data.Mutation] = true
                            output[#output + 1] = data
                        end
                        yieldIfNeeded()
                    end
                end
            end

            return output
        end

        local function refreshNow()
            if not runtime.Enabled or not hasUsableSelection() then
                applyData({})
                return
            end

            local ok, result = pcall(scanGarden)
            if not ok then
                warn("[ScoopHub Garden ESP] Scan failed: " .. tostring(result))
                return
            end
            applyData(result)
        end

        local function restartWorker()
            runtime.WorkerGeneration += 1
            local generation = runtime.WorkerGeneration

            if not runtime.Enabled or not hasUsableSelection() then
                applyData({})
                return
            end

            task.spawn(function()
                while runtime.Enabled
                    and runtime.WorkerGeneration == generation
                    and ScoopHubRunAlive()
                    and SG.Parent do
                    refreshNow()
                    task.wait(2)
                end
            end)
        end

        -- ------------------------- UI -------------------------------------
        -- Automation-style Garden ESP card.
        -- It still occupies ONLY ONE Misc column; the extra height is vertical.
        local GardenEspCard = card(
            1,
            7,
            "GARDEN ESP",
            ""
        )
        GardenEspCard.Size = UDim2.new(.5, -3, 0, GARDEN_ESP_CARD_H)

        local function makeSelector(fieldTitle, y, initialText)
            -- Match Automation createFieldButton + compact multi-select exactly.
            label(
                GardenEspCard,
                fieldTitle,
                UDim2.new(0, 10, 0, y),
                UDim2.new(1, -20, 0, 14),
                10,
                T.Muted,
                T.Font
            )

            local buttonObject = C(N("TextButton", {
                Text = "",
                Font = T.Body,
                TextSize = 11,
                TextColor3 = T.White,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                BackgroundColor3 = T.Input,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Position = UDim2.new(0, 10, 0, y + 17),
                Size = UDim2.new(1, -20, 0, 27),
                ClipsDescendants = true,
                ZIndex = 5,
            }, GardenEspCard), 5)

            S(buttonObject, T.Stroke, .82, 1)

            local selectorText = N("TextLabel", {
                Name = "CompactSelectorText",
                Text = initialText,
                Font = T.Body,
                TextSize = 12,
                TextColor3 = T.White,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 8, 0, 0),
                Size = UDim2.new(1, -28, 1, 0),
                ZIndex = 6,
            }, buttonObject)

            local chevron = N("Frame", {
                Name = "CompactSelectorChevron",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(1, -20, 0.5, -5),
                Size = UDim2.fromOffset(14, 10),
                Rotation = 0,
                ZIndex = 6,
            }, buttonObject)

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

            return buttonObject, selectorText, chevron
        end

        local FruitSelector, FruitSelectorText, FruitChevron = makeSelector(
            "FRUITS TO SHOW",
            27,
            "None selected"
        )

        local MutationSelector, MutationSelectorText, MutationChevron = makeSelector(
            "MUTATIONS TO SHOW",
            78,
            "All mutations"
        )

        -- Match Automation createToggle exactly: title/subtitle on the left,
        -- 48x23 pill on the right, directly inside the card.
        local GardenEspToggleState = false

        label(
            GardenEspCard,
            "GARDEN ESP",
            UDim2.new(0, 10, 0, 132),
            UDim2.new(1, -82, 0, 14),
            11,
            T.White,
            T.Font
        )

        label(
            GardenEspCard,
            "Show selected fruits",
            UDim2.new(0, 10, 0, 146),
            UDim2.new(1, -82, 0, 13),
            9,
            T.Muted,
            T.Body
        )

        local GardenEspToggleButton = C(N("TextButton", {
            Text = "",
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Position = UDim2.new(1, -58, 0, 134),
            Size = UDim2.fromOffset(48, 23),
            ZIndex = 5,
        }, GardenEspCard), 12)

        local GardenEspToggleKnob = C(N("Frame", {
            BackgroundColor3 = T.White,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, .5),
            Position = UDim2.new(0, 3, .5, 0),
            Size = UDim2.fromOffset(17, 17),
            ZIndex = 6,
        }, GardenEspToggleButton), 10)

        local GardenEspToggle = {}

        function GardenEspToggle:Set(value, fireCallback)
            GardenEspToggleState = value == true

            GardenEspToggleButton.BackgroundColor3 =
                GardenEspToggleState
                and T.Success
                or T.RedDark

            tw(
                GardenEspToggleKnob,
                {
                    Position =
                        GardenEspToggleState
                        and UDim2.new(1, -20, .5, 0)
                        or UDim2.new(0, 3, .5, 0)
                },
                .15
            )

            if fireCallback ~= false then
                runtime.Enabled = GardenEspToggleState
                State.GardenESPEnabled = runtime.Enabled
                restartWorker()
            end
        end

        function GardenEspToggle:Get()
            return GardenEspToggleState
        end

        TrackConnection(GardenEspToggleButton.Activated:Connect(function()
            GardenEspToggle:Set(not GardenEspToggleState, true)
        end))

        -- Same compact open-dropdown structure as Automation:
        -- search -> SELECT ALL / CLEAR ALL -> scrollable options.
        local Dropdown = C(N("Frame", {
            Name = "GardenESPMultiSelect",
            Visible = false,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(230, 240),
            BackgroundColor3 = T.Surface2,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            ZIndex = 500,
        }, Page), 6)
        S(Dropdown, T.Red, 0, 1.5)

        local FilterBox = C(N("TextBox", {
            Position = UDim2.new(0, 4, 0, 4),
            Size = UDim2.new(1, -8, 0, 26),
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search...",
            PlaceholderColor3 = T.Muted,
            TextColor3 = T.White,
            Font = T.Body,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            ZIndex = 502,
        }, Dropdown), 5)
        N("UIPadding", {
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, FilterBox)

        local ActionRow = N("Frame", {
            Name = "GardenESPActions",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 4, 0, 34),
            Size = UDim2.new(1, -8, 0, 26),
            ZIndex = 501,
        }, Dropdown)

        local SelectAllButton = C(N("TextButton", {
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(.5, -2, 1, 0),
            BackgroundColor3 = T.RedDark,
            BorderSizePixel = 0,
            Text = "SELECT ALL",
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 11,
            AutoButtonColor = false,
            ZIndex = 502,
        }, ActionRow), 4)

        local ClearAllButton = C(N("TextButton", {
            Position = UDim2.new(.5, 2, 0, 0),
            Size = UDim2.new(.5, -2, 1, 0),
            BackgroundColor3 = T.Surface3,
            BorderSizePixel = 0,
            Text = "CLEAR ALL",
            TextColor3 = T.White,
            Font = T.Font,
            TextSize = 11,
            AutoButtonColor = false,
            ZIndex = 502,
        }, ActionRow), 4)

        local OptionScroll = N("ScrollingFrame", {
            Position = UDim2.new(0, 4, 0, 64),
            Size = UDim2.new(1, -8, 1, -68),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.new(),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = T.Red,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 501,
        }, Dropdown)

        local DropdownMode = nil
        local OptionRows = {}

        local function updateSelectorText()
            local fruitValues = sortedKeys(runtime.SelectedFruits)
            local mutationValues = sortedKeys(runtime.SelectedMutations)
            local fruitCount = #fruitValues
            local mutationCount = #mutationValues

            if runtime.FruitAll then
                FruitSelectorText.Text = "All fruits"
            elseif fruitCount == 0 then
                FruitSelectorText.Text = "None selected"
            elseif fruitCount == 1 then
                FruitSelectorText.Text = fruitValues[1]
            elseif fruitCount == 2 then
                FruitSelectorText.Text = fruitValues[1] .. ", " .. fruitValues[2]
            else
                FruitSelectorText.Text = fruitValues[1]
                    .. ", "
                    .. fruitValues[2]
                    .. " +"
                    .. tostring(fruitCount - 2)
            end

            if runtime.MutationAll then
                MutationSelectorText.Text = "All mutations"
            elseif mutationCount == 0 then
                MutationSelectorText.Text = "None selected"
            elseif mutationCount == 1 then
                MutationSelectorText.Text = mutationValues[1]
            elseif mutationCount == 2 then
                MutationSelectorText.Text = mutationValues[1] .. ", " .. mutationValues[2]
            else
                MutationSelectorText.Text = mutationValues[1]
                    .. ", "
                    .. mutationValues[2]
                    .. " +"
                    .. tostring(mutationCount - 2)
            end
        end

        local function setSelectorChevron(chevron, open, instant)
            local targetRotation = open and 180 or 0
            if instant then
                chevron.Rotation = targetRotation
            else
                tw(chevron, {Rotation = targetRotation}, .14)
            end
        end

        local function setDropdownOpen(opened)
            Dropdown.Visible = opened == true
            setSelectorChevron(
                FruitChevron,
                opened and DropdownMode == "Fruit",
                false
            )
            setSelectorChevron(
                MutationChevron,
                opened and DropdownMode == "Mutation",
                false
            )
        end

        local function clearOptionRows()
            for index = #OptionRows, 1, -1 do
                local row = OptionRows[index]
                if row and row.Parent then
                    row:Destroy()
                end
                OptionRows[index] = nil
            end
        end

        local function knownOptions()
            local source = DropdownMode == "Fruit"
                and runtime.KnownFruits
                or runtime.KnownMutations
            return sortedKeys(source)
        end

        local function isOptionSelected(option)
            if DropdownMode == "Fruit" then
                return runtime.FruitAll
                    or runtime.SelectedFruits[option] == true
            end
            return runtime.MutationAll
                or runtime.SelectedMutations[option] == true
        end

        local function materializeAllSelection()
            if DropdownMode == "Fruit" and runtime.FruitAll then
                clearSet(runtime.SelectedFruits)
                for option in pairs(runtime.KnownFruits) do
                    runtime.SelectedFruits[option] = true
                end
                runtime.FruitAll = false
            elseif DropdownMode == "Mutation" and runtime.MutationAll then
                clearSet(runtime.SelectedMutations)
                for option in pairs(runtime.KnownMutations) do
                    runtime.SelectedMutations[option] = true
                end
                runtime.MutationAll = false
            end
        end

        local rebuildDropdown
        rebuildDropdown = function()
            if not Dropdown.Visible or not DropdownMode then
                return
            end

            clearOptionRows()
            local query = string.lower(FilterBox.Text or "")
            local y = 0

            for _, option in ipairs(knownOptions()) do
                if query == "" or string.find(string.lower(option), query, 1, true) then
                    local selected = isOptionSelected(option)
                    local row = C(N("TextButton", {
                        Position = UDim2.fromOffset(0, y),
                        Size = UDim2.new(1, -4, 0, 27),
                        BackgroundColor3 = selected and T.RedDark or T.Surface2,
                        BackgroundTransparency = selected and .05 or .18,
                        BorderSizePixel = 0,
                        Text = (selected and "✓  " or "   ") .. option,
                        TextColor3 = selected and T.White or T.Muted,
                        Font = selected and T.Font or T.Body,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        AutoButtonColor = false,
                        ZIndex = 503,
                    }, OptionScroll), 5)
                    N("UIPadding", {
                        PaddingLeft = UDim.new(0, 8),
                        PaddingRight = UDim.new(0, 8),
                    }, row)

                    TrackConnection(row.Activated:Connect(function()
                        materializeAllSelection()

                        if DropdownMode == "Fruit" then
                            runtime.SelectedFruits[option] =
                                not runtime.SelectedFruits[option]
                                or nil
                        else
                            runtime.SelectedMutations[option] =
                                not runtime.SelectedMutations[option]
                                or nil
                        end

                        State.GardenESPFruitAll = runtime.FruitAll
                        State.GardenESPMutationAll = runtime.MutationAll
                        State.GardenESPFruits = sortedKeys(runtime.SelectedFruits)
                        State.GardenESPMutations = sortedKeys(runtime.SelectedMutations)

                        updateSelectorText()
                        rebuildDropdown()
                        restartWorker()
                    end))

                    OptionRows[#OptionRows + 1] = row
                    y += 30
                end
            end

            OptionScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(0, y - 3))
        end

        local function positionDropdown(buttonObject)
            local pagePos = Page.AbsolutePosition
            local pageSize = Page.AbsoluteSize
            local buttonPos = buttonObject.AbsolutePosition
            local buttonSize = buttonObject.AbsoluteSize

            local scaleValue = math.max(tonumber(Scale.Scale) or 1, 0.01)
            local pageWidth = pageSize.X / scaleValue
            local pageHeight = pageSize.Y / scaleValue
            local buttonX = (buttonPos.X - pagePos.X) / scaleValue
            local buttonTop = (buttonPos.Y - pagePos.Y) / scaleValue
            local buttonWidth = buttonSize.X / scaleValue
            local buttonHeight = buttonSize.Y / scaleValue

            -- Automation dropdowns match their selector width.
            local width = math.min(
                buttonWidth,
                math.max(0, pageWidth - 8)
            )
            local height = 240

            local x = math.clamp(
                buttonX,
                4,
                math.max(4, pageWidth - width - 4)
            )

            local below = buttonTop + buttonHeight + 4
            local above = buttonTop - height - 4
            local y = below

            if below + height > pageHeight then
                y = math.max(4, above)
            end

            Dropdown.Position = UDim2.fromOffset(x, y)
            Dropdown.Size = UDim2.fromOffset(width, height)
        end

        local function openDropdown(mode, buttonObject)
            if Dropdown.Visible and DropdownMode == mode then
                DropdownMode = nil
                setDropdownOpen(false)
                return
            end

            DropdownMode = mode
            FilterBox.Text = ""
            FilterBox.PlaceholderText = mode == "Fruit"
                and "Search fruits..."
                or "Search mutations..."
            positionDropdown(buttonObject)
            setDropdownOpen(true)
            rebuildDropdown()
        end

        TrackConnection(FruitSelector.Activated:Connect(function()
            openDropdown("Fruit", FruitSelector)
        end))

        TrackConnection(MutationSelector.Activated:Connect(function()
            openDropdown("Mutation", MutationSelector)
        end))

        TrackConnection(FilterBox:GetPropertyChangedSignal("Text"):Connect(function()
            rebuildDropdown()
        end))

        TrackConnection(SelectAllButton.Activated:Connect(function()
            if DropdownMode == "Fruit" then
                runtime.FruitAll = true
                clearSet(runtime.SelectedFruits)
            elseif DropdownMode == "Mutation" then
                runtime.MutationAll = true
                clearSet(runtime.SelectedMutations)
            end

            State.GardenESPFruitAll = runtime.FruitAll
            State.GardenESPMutationAll = runtime.MutationAll
            State.GardenESPFruits = sortedKeys(runtime.SelectedFruits)
            State.GardenESPMutations = sortedKeys(runtime.SelectedMutations)

            updateSelectorText()
            rebuildDropdown()
            restartWorker()
        end))

        TrackConnection(ClearAllButton.Activated:Connect(function()
            if DropdownMode == "Fruit" then
                runtime.FruitAll = false
                clearSet(runtime.SelectedFruits)
            elseif DropdownMode == "Mutation" then
                runtime.MutationAll = false
                clearSet(runtime.SelectedMutations)
            end

            State.GardenESPFruitAll = runtime.FruitAll
            State.GardenESPMutationAll = runtime.MutationAll
            State.GardenESPFruits = sortedKeys(runtime.SelectedFruits)
            State.GardenESPMutations = sortedKeys(runtime.SelectedMutations)

            updateSelectorText()
            rebuildDropdown()
            restartWorker()
        end))

        TrackConnection(UIS.InputBegan:Connect(function(input)
            if not Dropdown.Visible then
                return
            end
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

            if not inside(Dropdown)
                and not inside(FruitSelector)
                and not inside(MutationSelector) then
                DropdownMode = nil
                setDropdownOpen(false)
            end
        end))

        TrackConnection(Page:GetPropertyChangedSignal("Visible"):Connect(function()
            if not Page.Visible then
                DropdownMode = nil
                setDropdownOpen(false)
            end
        end))

        TrackConnection(Page:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if Dropdown.Visible then
                local source = DropdownMode == "Fruit"
                    and FruitSelector
                    or MutationSelector
                if source then
                    positionDropdown(source)
                end
            end
        end))

        -- Slow distance fallback. BillboardGui.MaxDistance handles this on normal
        -- clients; this keeps behavior consistent where executor/client support is odd.
        task.spawn(function()
            while ScoopHubRunAlive() and SG.Parent do
                task.wait(.35)
                if runtime.Enabled then
                    local camera = Workspace.CurrentCamera
                    local cameraPosition = camera and camera.CFrame.Position
                    if cameraPosition then
                        for _, record in pairs(runtime.Labels) do
                            if record.Billboard
                                and record.Billboard.Parent
                                and record.Anchor
                                and record.Anchor.Parent then
                                record.Billboard.Enabled =
                                    (record.Anchor.Position - cameraPosition).Magnitude <= 135
                            end
                        end
                    end
                end
            end
        end)

        function feature.GetSettings()
            return {
                Enabled = runtime.Enabled == true,
                FruitAll = runtime.FruitAll == true,
                Fruits = sortedKeys(runtime.SelectedFruits),
                MutationAll = runtime.MutationAll == true,
                Mutations = sortedKeys(runtime.SelectedMutations),
            }
        end

        function feature.ApplySettings(data)
            data = type(data) == "table" and data or {}

            runtime.FruitAll = data.FruitAll == true
            runtime.MutationAll = data.MutationAll ~= false
            copyListIntoSet(data.Fruits, runtime.SelectedFruits, runtime.KnownFruits)
            copyListIntoSet(data.Mutations, runtime.SelectedMutations, runtime.KnownMutations)

            -- If a newer config explicitly stores MutationAll=false, respect it.
            if data.MutationAll == false then
                runtime.MutationAll = false
            end

            State.GardenESPFruitAll = runtime.FruitAll
            State.GardenESPMutationAll = runtime.MutationAll
            State.GardenESPFruits = sortedKeys(runtime.SelectedFruits)
            State.GardenESPMutations = sortedKeys(runtime.SelectedMutations)

            updateSelectorText()
            if Dropdown.Visible then
                rebuildDropdown()
            end

            GardenEspToggle:Set(data.Enabled == true, true)
            return true
        end

        function feature.SetEnabled(value)
            GardenEspToggle:Set(value == true, true)
        end

        function feature.IsEnabled()
            return runtime.Enabled == true
        end

        function feature.Stop()
            runtime.Enabled = false
            runtime.WorkerGeneration += 1
            destroyLabels()
            if labelFolder and labelFolder.Parent then
                labelFolder:Destroy()
            end
            labelFolder = nil
            Dropdown.Visible = false
        end

        updateSelectorText()

        RegisterScoopHubCleanup(function()
            feature.Stop()
        end)

        return feature
    end)()



    return GardenESPFeature
end

function Module.MountMisc(B)
    B = type(B) == "table" and B or {}

    local result = {}
    result.CleanupToggle = mountCleanup(B)
    result.RemoveGardenToggle = mountRemoveOtherGardens(B)
    result.BackpackValueToggle = mountBackpackValueESP(B)
    result.WildPetEspToggle = mountWildPetESP(B)
    result.GardenESPFeature = mountGardenESP(B)
    return result
end

return Module
