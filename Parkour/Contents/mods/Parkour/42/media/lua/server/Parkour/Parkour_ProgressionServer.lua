local Definitions = require "Parkour/Parkour_ProgressionDefinitions"
local Progression = require "Parkour/Parkour_Progression"

local MODULE = "ParkourProgression"
local MAX_ACTION_DURATION_MS = 20000
local COMPLETION_POSITION_GRACE_MS = 1500
local ANTI_FARM_UPDATE_INTERVAL_MS = 500
local pendingByPlayer = setmetatable({}, { __mode = "k" })
local terminalByPlayer = setmetatable({}, { __mode = "k" })
local lastAntiFarmUpdateAt = 0

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Progression Server] " .. message)
    end
end

local function isValidToken(token)
    return type(token) == "number"
        and token == token
        and token >= 0
        and token < 9007199254740991
end

local function beginAction(player, args)
    local token = args and args.token
    local actionId = args and args.actionId
    local definition = Definitions.getXPAction(actionId)
    if not player or not isValidToken(token) or not definition
        or player:isDead() or player:getVehicle() then
        return
    end

    local terminal = terminalByPlayer[player]
    if terminal and terminal.token == token and getTimestampMs() <= terminal.expiresAt then
        return
    end

    local active = pendingByPlayer[player]
    if active then
        -- A repeated packet for the same action is harmless. A different token
        -- must not replace an in-flight traversal and later claim its finish.
        return
    end

    local originX = tonumber(args.originX)
    local originY = tonumber(args.originY)
    local originZ = tonumber(args.originZ)
    if not originX or not originY or not originZ
        or math.abs(player:getX() - originX) > 1.0
        or math.abs(player:getY() - originY) > 1.0
        or math.abs(player:getZ() - originZ) > 0.1 then
        return
    end

    pendingByPlayer[player] = {
        token = token,
        actionId = actionId,
        startedAt = getTimestampMs(),
        originX = originX,
        originY = originY,
        originZ = originZ,
    }
end

local function finalizeAction(player, active, now)
    local definition = Definitions.getXPAction(active.actionId)
    local elapsed = now - active.startedAt
    if not definition or player:isDead() or player:getVehicle()
        or elapsed < definition.minimumDurationMs
        or elapsed > MAX_ACTION_DURATION_MS then
        pendingByPlayer[player] = nil
        return
    end

    local dx = player:getX() - active.originX
    local dy = player:getY() - active.originY
    local travel = math.sqrt(dx * dx + dy * dy)
    if travel < definition.minimumTravel then
        if now - active.completionRequestedAt < COMPLETION_POSITION_GRACE_MS then
            return
        end
        pendingByPlayer[player] = nil
        debugLog(string.format(
            "Rejected completed %s after position grace: travel=%.3f",
            active.actionId,
            travel
        ))
        return
    end

    pendingByPlayer[player] = nil
    local signature = Progression.makeObstacleSignature(
        active.actionId,
        active.originX,
        active.originY,
        active.originZ,
        player:getX(),
        player:getY(),
        player:getZ()
    )
    local awarded = Progression.awardXP(
        player,
        definition.xp,
        signature,
        active.originX,
        active.originY
    )
    terminalByPlayer[player] = {
        token = active.token,
        expiresAt = getTimestampMs() + MAX_ACTION_DURATION_MS,
    }
    debugLog(string.format(
        "Completed %s token=%s travel=%.3f award=%.3f",
        active.actionId,
        tostring(active.token),
        travel,
        awarded
    ))
end

local function completeAction(player, args)
    local active = player and pendingByPlayer[player]
    if not active or active.token ~= (args and args.token)
        or active.actionId ~= (args and args.actionId) then
        return
    end
    if not active.completionRequestedAt then
        active.completionRequestedAt = getTimestampMs()
    end
    finalizeAction(player, active, getTimestampMs())
end

local function cancelAction(player, args)
    local active = player and pendingByPlayer[player]
    if active and active.token == (args and args.token) then
        pendingByPlayer[player] = nil
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end
    if command == "DebugSetLevel" then
        local role = player and player:getRole()
        if role and role:hasCapability(Capability.CanModifyPlayerStatsInThePlayerStatsUI) then
            Progression.setLevelAuthoritative(player, args and args.level)
            debugLog("Debug level set to " .. tostring(args and args.level))
        end
    elseif command == "Begin" then
        beginAction(player, args)
    elseif command == "Complete" then
        completeAction(player, args)
    elseif command == "Cancel" then
        cancelAction(player, args)
    end
end

local function expireActions()
    local now = getTimestampMs()
    for player, active in pairs(pendingByPlayer) do
        if player and active.completionRequestedAt then
            finalizeAction(player, active, now)
        end
        if not player or player:isDead() or now - active.startedAt > MAX_ACTION_DURATION_MS then
            pendingByPlayer[player] = nil
        end
    end
    for player, terminal in pairs(terminalByPlayer) do
        if not player or now > terminal.expiresAt then
            terminalByPlayer[player] = nil
        end
    end

    if now - lastAntiFarmUpdateAt >= ANTI_FARM_UPDATE_INTERVAL_MS then
        lastAntiFarmUpdateAt = now
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players then
            for index = 0, players:size() - 1 do
                local player = players:get(index)
                Progression.updateAntiFarmMovement(player)
                Progression.updateSprintXP(player)
            end
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(expireActions)

return true
