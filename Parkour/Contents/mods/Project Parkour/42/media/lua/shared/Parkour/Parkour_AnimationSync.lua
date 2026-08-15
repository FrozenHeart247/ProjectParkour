local ParkourAnimationSync = {}

local MODULE = "ParkourAnimationSync"
local pendingByOnlineId = {}

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Animation Sync] " .. message)
    end
end

local function findOnlinePlayer(onlineId)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then
        return nil
    end
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        if player and player:getOnlineID() == onlineId then
            return player
        end
    end
    return nil
end

local function applyPayload(payload)
    if not payload or type(payload.onlineId) ~= "number" then
        return false
    end
    local player = findOnlinePlayer(payload.onlineId)
    if not player then
        local queued = pendingByOnlineId[payload.onlineId]
        if not queued then
            queued = {}
            pendingByOnlineId[payload.onlineId] = queued
        end
        local key = payload.kind == "position"
            and "__position"
            or tostring(payload.variable)
        queued[key] = payload
        return false
    end

    local localPlayer = getPlayer and getPlayer() or nil
    if localPlayer and localPlayer:getOnlineID() == payload.onlineId then
        return true
    end

    if payload.kind == "position" then
        local x = tonumber(payload.x)
        local y = tonumber(payload.y)
        local z = tonumber(payload.z)
        if not x or not y or not z then
            return false
        end
        player:setX(x)
        player:setY(y)
        player:setZ(z)
        player:setLastX(x)
        player:setLastY(y)
        player:setLastZ(z)
        debugLog(string.format(
            "Applied remote position id=%d %.3f,%.3f,%.3f",
            payload.onlineId,
            x,
            y,
            z
        ))
        return true
    end

    if type(payload.variable) ~= "string" then
        return false
    end
    if payload.clear == true then
        player:clearVariable(payload.variable)
    else
        player:setVariable(payload.variable, payload.value)
    end
    debugLog(string.format(
        "Applied remote variable id=%d %s=%s clear=%s",
        payload.onlineId,
        payload.variable,
        tostring(payload.value),
        tostring(payload.clear == true)
    ))
    return true
end

local function sendVariable(character, variableName, value, clear)
    if not isClient() or not character or not character:isLocalPlayer() then
        return
    end
    sendClientCommand(character, MODULE, "Variable", {
        variable = variableName,
        value = value,
        clear = clear == true,
    })
end

function ParkourAnimationSync.setVariable(character, variableName, value)
    if not character then
        return
    end
    character:setVariable(variableName, value)
    sendVariable(character, variableName, value, false)
end

function ParkourAnimationSync.broadcastVariable(character, variableName, value)
    sendVariable(character, variableName, value, false)
end

function ParkourAnimationSync.clearVariable(character, variableName)
    if not character then
        return
    end
    character:clearVariable(variableName)
    sendVariable(character, variableName, nil, true)
end

function ParkourAnimationSync.broadcastPosition(character, x, y, z)
    if not isServer() or not character then
        return
    end
    sendServerCommand(MODULE, "Apply", {
        kind = "position",
        onlineId = character:getOnlineID(),
        x = x,
        y = y,
        z = z,
    })
end

local function onServerCommand(module, command, args)
    if module ~= MODULE or command ~= "Apply" then
        return
    end
    applyPayload(args)
end

local function retryPending(character)
    if not character or not instanceof(character, "IsoPlayer") then
        return
    end
    local onlineId = character:getOnlineID()
    local queued = pendingByOnlineId[onlineId]
    if queued then
        pendingByOnlineId[onlineId] = nil
        for _, payload in pairs(queued) do
            applyPayload(payload)
        end
    end
end

local function requestSnapshot(playerIndex, character)
    if isClient() and character and character:isLocalPlayer() then
        sendClientCommand(character, MODULE, "Snapshot", {})
    end
end

if not isServer() then
    Events.OnServerCommand.Add(onServerCommand)
    Events.OnPlayerUpdate.Add(retryPending)
    Events.OnCreatePlayer.Add(requestSnapshot)
end

return ParkourAnimationSync
