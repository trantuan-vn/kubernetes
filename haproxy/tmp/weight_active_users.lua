local core = require("core")
local timer = require("timer")
local json = require("json")  -- Yêu cầu có thư viện json (lua-cjson)

local BACKEND_NAME = "backendnodes"
local EXTERNAL_SERVICE_IP = "weight-service.default.svc.cluster.local"
local EXTERNAL_SERVICE_PORT = 9000
local PATH = "/weights"
local UPDATE_INTERVAL = 30 * 1000

local cached_weights = {}

local function fetch_weights()
    local socket = core.tcp()
    socket:settimeout(2000)

    local ok, err = socket:connect(EXTERNAL_SERVICE_IP, EXTERNAL_SERVICE_PORT)
    if not ok then
        core.Warning("Cannot connect to external service: " .. (err or ""))
        return nil
    end

    local req = "GET " .. PATH .. " HTTP/1.1\r\nHost: " .. EXTERNAL_SERVICE_IP .. "\r\nConnection: close\r\n\r\n"
    socket:send(req)

    local resp = socket:receive("*a")
    socket:close()

    if not resp then
        core.Warning("No response from external service")
        return nil
    end

    local body = resp:match("\r\n\r\n(.*)")
    if not body then
        core.Warning("Cannot parse response body")
        return nil
    end

    local ok, data = pcall(json.decode, body)
    if not ok then
        core.Warning("Invalid JSON: " .. tostring(data))
        return nil
    end

    return data
end

local function update_weights()
    local backend = core.backends[BACKEND_NAME]
    if not backend then
        core.Warning("Backend " .. BACKEND_NAME .. " not found")
        return
    end

    local weights = fetch_weights()
    if not weights then return end

    for _, server in ipairs(backend.servers) do
        local name = server:name()
        local weight = weights[name]
        if weight then
            if cached_weights[name] ~= weight then
                server:set_weight(weight)
                cached_weights[name] = weight
                core.Info("Updated weight " .. weight .. " for server " .. name)
            else
                core.Debug("No weight change for " .. name)
            end
        else
            core.Warning("No weight info for server " .. name)
        end
    end
end

local function periodic_update()
    update_weights()
    timer.add(UPDATE_INTERVAL, periodic_update)
end

timer.add(1000, periodic_update)
