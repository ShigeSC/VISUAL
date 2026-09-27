--==================================================
-- SCOOPHUB V2.2 - USER BACKEND MODULE
-- UI stays in MAIN. This module owns USER behavior/data only.
-- Obfuscate this file separately, then upload the obfuscated output to:
--   VISUAL/GA2/gag2user_READABLE_OBFUSCATE_THIS.lua
--==================================================

local Module = {}
Module.Version = "2.2-user-backend-1"

function Module.Init(Bridge)
    Bridge = type(Bridge) == "table" and Bridge or {}

    local Players = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local Workspace = game:GetService("Workspace")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    local LP = Bridge.LP or Players.LocalPlayer
    local RunAlive = type(Bridge.RunAlive) == "function" and Bridge.RunAlive or function()
        return true
    end
    local QueueAfterTeleport = type(Bridge.QueueAfterTeleport) == "function"
        and Bridge.QueueAfterTeleport
        or function()
            return false
        end

    local GARDEN_VALLEY_PLACE_ID = 97598239454123
    local FALL_HARVEST_PLACE_ID = 126987765280963
    local FALL_HARVEST_ALT_PLACE_ID = 129343810645058

    local API = {
        Worlds = {
            GardenValleyPlaceId = GARDEN_VALLEY_PLACE_ID,
            FallHarvestPlaceId = FALL_HARVEST_PLACE_ID,
            FallHarvestAltPlaceId = FALL_HARVEST_ALT_PLACE_ID,
        },
        Version = Module.Version,
    }

    -- SESSION ---------------------------------------------------------------
    local initialTimeValue = math.max(0, tonumber(time()) or 0)
    local initialDistributedValue = math.max(0, tonumber(Workspace.DistributedGameTime) or 0)
    local sessionTimerFloor = math.max(initialTimeValue, initialDistributedValue)
    local sessionStartedAt = os.time() - math.floor(sessionTimerFloor)
    local lastPlaySeconds = sessionTimerFloor

    function API.GetSessionStartedAt()
        return sessionStartedAt
    end

    function API.GetLivePlaySeconds()
        local clientElapsed = math.max(0, tonumber(time()) or 0)
        local distributed = math.max(0, tonumber(Workspace.DistributedGameTime) or 0)
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

    function API.FormatDuration(total)
        total = math.max(0, math.floor(tonumber(total) or 0))
        local h = math.floor(total / 3600)
        local m = math.floor((total % 3600) / 60)
        local s = total % 60
        return string.format("%02d:%02d:%02d", h, m, s)
    end

    -- USER BUTTONS ----------------------------------------------------------
    function API.CopyUserId()
        local value = tostring(LP and LP.UserId or "")
        if value == "" then
            return false
        end

        if type(setclipboard) == "function" then
            return pcall(setclipboard, value)
        end
        if type(toclipboard) == "function" then
            return pcall(toclipboard, value)
        end
        return false
    end

    function API.IsCurrentWorld(placeId)
        placeId = tonumber(placeId)
        if placeId == FALL_HARVEST_PLACE_ID then
            return game.PlaceId == FALL_HARVEST_PLACE_ID
                or game.PlaceId == FALL_HARVEST_ALT_PLACE_ID
        end
        return game.PlaceId == placeId
    end

    local function triggerEventWorldTeleport(worldName)
        local playerGui = LP and LP:FindFirstChildOfClass("PlayerGui")
        local eventWorldsGui = playerGui and playerGui:FindFirstChild("EventWorldsTeleporter")
        local frame = eventWorldsGui and eventWorldsGui:FindFirstChild("Frame")
        local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
        if not scrollingFrame then
            return false
        end

        for _, worldFrame in ipairs(scrollingFrame:GetChildren()) do
            local mainFrame = worldFrame:FindFirstChild("Main_Frame")
                or worldFrame:FindFirstChild("Main_Frame", true)
            local nameLabel = mainFrame and mainFrame:FindFirstChild("Name", true)
            local teleportButton = mainFrame and mainFrame:FindFirstChild("TeleportButton", true)

            if nameLabel
                and teleportButton
                and nameLabel:IsA("TextLabel")
                and teleportButton:IsA("TextButton")
                and tostring(nameLabel.Text or ""):gsub("<[^>]->", "") == tostring(worldName)
            then
                if type(firesignal) == "function" then
                    local ok = pcall(function()
                        firesignal(teleportButton.Activated)
                    end)
                    if ok then
                        return true
                    end
                end

                local center = teleportButton.AbsolutePosition + (teleportButton.AbsoluteSize / 2)
                local ok = pcall(function()
                    VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    task.wait(0.05)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                end)
                if ok then
                    return true
                end
            end
        end

        return false
    end

    function API.TeleportWorld(worldName, placeId)
        placeId = tonumber(placeId)
        if not placeId then
            return false, "invalid place"
        end
        if API.IsCurrentWorld(placeId) then
            return true, "current"
        end

        pcall(QueueAfterTeleport)

        local started = triggerEventWorldTeleport(worldName)
        if not started then
            started = pcall(function()
                TeleportService:Teleport(placeId, LP)
            end)
        end

        return started == true, started and "started" or "failed"
    end

    function API.Rejoin()
        pcall(QueueAfterTeleport)
        local ok, err = pcall(function()
            if game.JobId and game.JobId ~= "" then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
            else
                TeleportService:Teleport(game.PlaceId, LP)
            end
        end)
        return ok, err
    end

    function API.ServerHop()
        local autoBuy = rawget(_G, "ScoopHubAutoBuyPetAPI")
        if type(autoBuy) == "table" and type(autoBuy.ForceHop) == "function" then
            local ok, result = pcall(autoBuy.ForceHop)
            return ok, ok and "autobuy" or tostring(result)
        end

        local ok, body = pcall(function()
            return game:HttpGet(
                "https://games.roblox.com/v1/games/"
                .. tostring(game.PlaceId)
                .. "/servers/Public?sortOrder=Asc&limit=100"
            )
        end)
        if not ok then
            return false, tostring(body)
        end

        local decodedOk, payload = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if not decodedOk or type(payload) ~= "table" or type(payload.data) ~= "table" then
            return false, "invalid server response"
        end

        local choices = {}
        for _, server in ipairs(payload.data) do
            local playing = tonumber(server.playing) or 0
            local maxPlayers = tonumber(server.maxPlayers) or 0
            if server.id and server.id ~= game.JobId and playing < maxPlayers then
                choices[#choices + 1] = server
            end
        end

        table.sort(choices, function(a, b)
            return (tonumber(a.playing) or 0) < (tonumber(b.playing) or 0)
        end)

        if not choices[1] then
            return false, "no server found"
        end

        pcall(QueueAfterTeleport)
        local teleportOk, teleportErr = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, choices[1].id, LP)
        end)
        return teleportOk, teleportErr
    end

    -- USER PREFERENCES BRIDGE ----------------------------------------------
    local function miscAPI()
        local api = rawget(_G, "ScoopHubMiscAPI")
        return type(api) == "table" and api or nil
    end

    function API.GetMiscSettings()
        local api = miscAPI()
        if api and type(api.GetSettings) == "function" then
            local ok, value = pcall(api.GetSettings)
            if ok and type(value) == "table" then
                return value
            end
        end
        return {}
    end

    function API.SetAutoRejoin(value)
        local api = miscAPI()
        if api and type(api.SetAutoRejoin) == "function" then
            return pcall(api.SetAutoRejoin, value == true)
        end
        return false
    end

    function API.SetLowGraphics(value)
        local api = miscAPI()
        if api and type(api.SetCleanup) == "function" then
            return pcall(api.SetCleanup, value == true)
        end
        return false
    end

    -- WEATHER BACKEND -------------------------------------------------------
    local WEATHER_API_URL = "https://api.gag2.gg/api/live/weather"
    local WEATHER_REFRESH_SECONDS = 30
    local weatherState = {
        Events = {},
        LastFetchUnix = nil,
        LastError = nil,
    }
    local weatherRunning = false
    local weatherGeneration = 0
    local weatherListenerId = 0
    local weatherListeners = {}

    function API.NowUnix()
        local ok, value = pcall(function()
            return Workspace:GetServerTimeNow()
        end)
        if ok and tonumber(value) then
            return tonumber(value)
        end
        return os.time()
    end

    function API.FormatClock(boundary)
        boundary = tonumber(boundary)
        if not boundary then
            return "--:--"
        end

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

    function API.FormatCountdown(boundary, currentTime)
        local remaining = math.max(
            0,
            math.floor((tonumber(boundary) or 0) - (tonumber(currentTime) or API.NowUnix()))
        )
        if remaining <= 0 then
            return "NOW"
        end

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

    local function snapshotWeather()
        local events = {}
        for index, entry in ipairs(weatherState.Events or {}) do
            events[index] = {
                Name = entry.Name,
                Boundary = entry.Boundary,
            }
        end
        return {
            Events = events,
            LastFetchUnix = weatherState.LastFetchUnix,
            LastError = weatherState.LastError,
        }
    end

    local function publishWeather()
        local snapshot = snapshotWeather()
        for id, callback in pairs(weatherListeners) do
            if type(callback) == "function" then
                local ok = pcall(callback, snapshot)
                if not ok then
                    weatherListeners[id] = nil
                end
            end
        end
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
            weatherState.Events = result
            weatherState.LastFetchUnix = API.NowUnix()
            weatherState.LastError = nil
        else
            weatherState.LastError = tostring(result)
        end

        publishWeather()
    end

    local function startWeatherWorker()
        if weatherRunning then
            return
        end

        weatherRunning = true
        weatherGeneration += 1
        local generation = weatherGeneration

        task.spawn(function()
            while weatherRunning
                and weatherGeneration == generation
                and RunAlive()
            do
                fetchWeatherSchedule()
                local waited = 0
                while weatherRunning
                    and weatherGeneration == generation
                    and RunAlive()
                    and waited < WEATHER_REFRESH_SECONDS
                do
                    task.wait(1)
                    waited += 1
                end
            end
        end)
    end

    function API.StartWeather(callback)
        weatherListenerId += 1
        local id = weatherListenerId
        if type(callback) == "function" then
            weatherListeners[id] = callback
            pcall(callback, snapshotWeather())
        end

        startWeatherWorker()

        local disconnected = false
        return function()
            if disconnected then
                return
            end
            disconnected = true
            weatherListeners[id] = nil
        end
    end

    function API.GetWeatherState()
        return snapshotWeather()
    end

    function API.Stop()
        weatherRunning = false
        weatherGeneration += 1
        table.clear(weatherListeners)
    end

    if type(Bridge.RegisterCleanup) == "function" then
        Bridge.RegisterCleanup(API.Stop)
    end

    return API
end

return Module
