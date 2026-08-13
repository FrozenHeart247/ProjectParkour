local Validation = require "Parkour/Parkour_WallRunUpValidation"

local MODULE = "ParkourWallRunUp"
local REQUEST_LIFETIME_MS = 7200
local MIN_TRANSFER_DELAY_MS = 2400
local MAX_ORIGIN_DISTANCE = 2.75
local COOLDOWN_MS = 1000

local pendingByPlayer = setmetatable({}, { __mode = "k" })
local cooldownByPlayer = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour WallRunUp Server] " .. message)
    end
end

local function reject(player, requestId, phase, reason)
    sendServerCommand(player, MODULE, phase .. "Rejected", {
        requestId = requestId,
        reason = reason,
    })
    debugLog(string.format("Rejected %s request %s: %s", phase, tostring(requestId), reason))
end

local function isValidRequestId(value)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value < 9007199254740991
end

local function beginRequest(player, args)
    local requestId = args and args.requestId
    if not player or not isValidRequestId(requestId) then
        return
    end

    local now = getTimestampMs()
    if player:isDead() or player:getVehicle() or now < (cooldownByPlayer[player] or 0) then
        reject(player, requestId, "Begin", "character")
        return
    end

    local originX = math.floor(tonumber(args.originX) or -1000000)
    local originY = math.floor(tonumber(args.originY) or -1000000)
    local originZ = math.floor(tonumber(args.originZ) or -1000000)
    if math.floor(player:getX()) ~= originX
        or math.floor(player:getY()) ~= originY
        or math.floor(player:getZ()) ~= originZ then
        reject(player, requestId, "Begin", "origin")
        return
    end

    local facingName, facingAlignment = Validation.resolveFacing(player)
    if facingName ~= args.directionName or facingAlignment < 0.70 then
        reject(player, requestId, "Begin", "facing")
        return
    end

    local target, reason = Validation.findTargetFromOrigin(
        originX,
        originY,
        originZ,
        args.directionName,
        player
    )
    if not target then
        reject(player, requestId, "Begin", reason or "target")
        return
    end

    pendingByPlayer[player] = {
        requestId = requestId,
        startedAt = now,
        expiresAt = now + REQUEST_LIFETIME_MS,
        originX = originX,
        originY = originY,
        originZ = originZ,
        directionName = args.directionName,
    }
    cooldownByPlayer[player] = now + COOLDOWN_MS
    sendServerCommand(player, MODULE, "BeginAccepted", { requestId = requestId })
    debugLog("Accepted begin request " .. tostring(requestId))
end

local function completeRequest(player, args)
    local requestId = args and args.requestId
    local request = player and pendingByPlayer[player]
    if not request or request.requestId ~= requestId then
        if player and isValidRequestId(requestId) then
            reject(player, requestId, "Transfer", "request")
        end
        return
    end
    pendingByPlayer[player] = nil

    local now = getTimestampMs()
    if player:isDead()
        or player:getVehicle()
        or now < request.startedAt + MIN_TRANSFER_DELAY_MS
        or now > request.expiresAt
        or math.floor(player:getZ()) ~= request.originZ then
        reject(player, requestId, "Transfer", "timing")
        return
    end

    local dx = player:getX() - (request.originX + 0.5)
    local dy = player:getY() - (request.originY + 0.5)
    if dx * dx + dy * dy > MAX_ORIGIN_DISTANCE * MAX_ORIGIN_DISTANCE then
        reject(player, requestId, "Transfer", "distance")
        return
    end

    local target, reason = Validation.findTargetFromOrigin(
        request.originX,
        request.originY,
        request.originZ,
        request.directionName,
        player
    )
    if not target then
        reject(player, requestId, "Transfer", reason or "target")
        return
    end

    local transferX = target.targetX
    local transferY = target.targetY
    if math.floor(player:getX()) == math.floor(target.targetX)
        and math.floor(player:getY()) == math.floor(target.targetY) then
        transferX = player:getX()
        transferY = player:getY()
    end
    Validation.moveCharacter(player, transferX, transferY, target.targetZ)
    sendServerCommand(player, MODULE, "TransferAccepted", {
        requestId = requestId,
        x = transferX,
        y = transferY,
        z = target.targetZ,
    })
    debugLog("Transferred request " .. tostring(requestId))
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end
    if command == "Begin" then
        beginRequest(player, args)
    elseif command == "Transfer" then
        completeRequest(player, args)
    end
end

Events.OnClientCommand.Add(onClientCommand)
