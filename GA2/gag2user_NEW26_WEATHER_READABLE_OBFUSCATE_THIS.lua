--==================================================
-- SCOOPHUB V2.2 - USER BACKEND MODULE (new26)
-- new26.lua owns PLAYER INFO / SESSION INFO / PREFERENCES UI.
-- This remote module contains only the behavior behind ScoopHub's USER actions.
-- Obfuscate this file, then replace the contents of:
--   VISUAL/GA2/gag2user_READABLE_OBFUSCATE_THIS.lua
--==================================================

local Module = {}
Module.Version = "2.2-user-backend-new26-weather-3"

function Module.Init(Bridge)
    Bridge = type(Bridge) == "table" and Bridge or {}

    local Players = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local Workspace = game:GetService("Workspace")

    local LP = Bridge.LP or Players.LocalPlayer
    local QueueAfterTeleport = type(Bridge.QueueAfterTeleport) == "function"
        and Bridge.QueueAfterTeleport
        or function() return false end

    local GARDEN_VALLEY_PLACE_ID = 97598239454123
    local FALL_HARVEST_PLACE_ID = 126987765280963
    local FALL_HARVEST_ALT_PLACE_ID = 129343810645058

    local API = {
        Version = Module.Version,
        Worlds = {
            GardenValleyPlaceId = GARDEN_VALLEY_PLACE_ID,
            FallHarvestPlaceId = FALL_HARVEST_PLACE_ID,
            FallHarvestAltPlaceId = FALL_HARVEST_ALT_PLACE_ID,
        },
    }

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
            local ok = pcall(api.SetAutoRejoin, value == true)
            return ok
        end
        return false
    end

    function API.SetLowGraphics(value)
        local api = miscAPI()
        if api and type(api.SetCleanup) == "function" then
            local ok = pcall(api.SetCleanup, value == true)
            return ok
        end
        return false
    end

    function API.SetWalkSpeed(value)
        local api = miscAPI()
        if api and type(api.SetWalkSpeed) == "function" then
            local ok, result = pcall(api.SetWalkSpeed, value)
            return ok and result ~= false
        end
        return false
    end

    function API.SetInfiniteJump(value)
        local api = miscAPI()
        if api and type(api.SetInfiniteJump) == "function" then
            local ok, result = pcall(api.SetInfiniteJump, value == true)
            return ok and result ~= false
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
                    if ok then return true end
                end

                local center = teleportButton.AbsolutePosition + (teleportButton.AbsoluteSize / 2)
                local ok = pcall(function()
                    VirtualInputManager:SendMouseMoveEvent(center.X, center.Y, game)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    task.wait(.05)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                end)
                if ok then return true end
            end
        end

        return false
    end

    function API.TeleportWorld(worldName, placeId)
        placeId = tonumber(placeId)
        if not placeId then return false, "invalid place" end
        if API.IsCurrentWorld(placeId) then return true, "current" end

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
                .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
            )
        end)
        if not ok then return false, tostring(body) end

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
            if server.id and server.id ~= game.JobId and maxPlayers > 0 and playing < maxPlayers then
                choices[#choices + 1] = server
            end
        end

        table.sort(choices, function(a, b)
            return (tonumber(a.playing) or 0) < (tonumber(b.playing) or 0)
        end)

        if not choices[1] then return false, "no server found" end

        pcall(QueueAfterTeleport)
        local teleportOk, teleportErr = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, choices[1].id, LP)
        end)
        return teleportOk, teleportErr
    end


    -- WEATHER BACKEND ------------------------------------------------------
    -- UI stays in MAIN. This module owns the HTTP request/cache so the visible
    -- USER page never blocks while the schedule is downloading.
    local WEATHER_API_URL = "https://api.gag2.gg/api/live/weather"
    local WEATHER_REFRESH_SECONDS = 30
    local weatherEvents = {}
    local weatherLastFetchUnix = nil
    local weatherLastError = nil

    local function weatherNowUnix()
        local ok, value = pcall(function()
            return Workspace:GetServerTimeNow()
        end)
        if ok and tonumber(value) then
            return tonumber(value)
        end
        return os.time()
    end

    local function weatherFetchUrl(url)
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

    local function copyWeatherEvents()
        local result = {}
        for index, entry in ipairs(weatherEvents) do
            result[index] = {
                Name = tostring(entry.Name or ""),
                Boundary = tonumber(entry.Boundary),
            }
        end
        return result
    end

    local function refreshWeatherCache()
        local ok, result = pcall(function()
            local body = weatherFetchUrl(WEATHER_API_URL)
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
            weatherLastFetchUnix = weatherNowUnix()
            weatherLastError = nil
            return true
        end

        weatherLastError = tostring(result)
        return false
    end

    function API.GetWeatherSnapshot(forceRefresh)
        local now = weatherNowUnix()
        local stale = not weatherLastFetchUnix
            or (now - weatherLastFetchUnix) >= WEATHER_REFRESH_SECONDS

        if forceRefresh == true or stale then
            refreshWeatherCache()
        end

        return {
            Events = copyWeatherEvents(),
            LastFetchUnix = weatherLastFetchUnix,
            LastError = weatherLastError,
            RefreshSeconds = WEATHER_REFRESH_SECONDS,
            Now = weatherNowUnix(),
        }
    end

    function API.RefreshWeather()
        refreshWeatherCache()
        return API.GetWeatherSnapshot(false)
    end


    return API
end

return Module
