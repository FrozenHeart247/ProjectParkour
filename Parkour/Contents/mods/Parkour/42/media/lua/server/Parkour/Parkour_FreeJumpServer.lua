local Validation = require "Parkour/Parkour_FreeJumpValidation"

local MODULE = "ParkourFreeJump"
local REQUEST_LIFETIME_MS = 4000
local MIN_TRANSFER_DELAY_MS = 650
local MIN_DEFERRED_TRANSFER_DELAY_MS = 300
local MAX_PATH_OVERSHOOT = 0.75
local MAX_LATERAL_DEVIATION = 0.90
local COOLDOWN_MS = 800

local pendingByPlayer = setmetatable({}, { __mode = "k" })
local cooldownByPlayer = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour FreeJump Server] " .. message)
    end
end

local function reject(player, requestId, phase, reason)
    sendServerCommand(player, MODULE, phase .. "Rejected", {
        requestId = requestId,
        reason = reason,
    })
    debugLog(string.format(
        "Rejected %s request %s: %s",
        phase,
        tostring(requestId),
        reason
    ))
end

local function rollbackRequest(player, request, reason)
    if not player or not request or player:isDead() or player:getVehicle() then
        return
    end
    local succeeded, failure = pcall(
        Validation.moveCharacter,
        player,
        request.startX,
        request.startY,
        request.originZ
    )
    if succeeded then
        debugLog(string.format(
            "Rolled request %s back to origin (%s)",
            tostring(request.requestId),
            tostring(reason)
        ))
    else
        debugLog("Server rollback failed: " .. tostring(failure))
    end
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
    if player:isDead()
        or player:getVehicle()
        or player:isOnFloor()
        or player:hasHitReaction()
        or pendingByPlayer[player] ~= nil
        or now < (cooldownByPlayer[player] or 0) then
        reject(player, requestId, "Begin", "character")
        return
    end

    local originX = math.floor(tonumber(args.originX) or -1000000)
    local originY = math.floor(tonumber(args.originY) or -1000000)
    local originZ = math.floor(tonumber(args.originZ) or -1000000)
    local distance = math.floor((tonumber(args.distance) or -1000000) + 0.5)
    if math.floor(player:getX()) ~= originX
        or math.floor(player:getY()) ~= originY
        or math.floor(player:getZ()) ~= originZ then
        reject(player, requestId, "Begin", "origin")
        return
    end

    local facingName, facingAlignment = Validation.resolveFacing(player)
    if facingName ~= args.directionName or facingAlignment < 0.85 then
        reject(player, requestId, "Begin", "facing")
        return
    end

    local target, reason = Validation.findTargetFromOrigin(
        originX,
        originY,
        originZ,
        args.directionName,
        distance,
        player,
        player:getX(),
        player:getY()
    )
    if not target then
        reject(player, requestId, "Begin", reason or "target")
        return
    end
    if target.landingSquare:getX() ~= math.floor(tonumber(args.landingSquareX) or -1000000)
        or target.landingSquare:getY() ~= math.floor(tonumber(args.landingSquareY) or -1000000)
        or target.landingSquare:getZ() ~= math.floor(tonumber(args.landingSquareZ) or -1000000) then
        reject(player, requestId, "Begin", "landing")
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
        distance = distance,
        startX = target.startX,
        startY = target.startY,
        requiresDeferredTransfer = target.requiresDeferredTransfer == true,
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
    local minimumTransferDelay = MIN_TRANSFER_DELAY_MS
    if request.requiresDeferredTransfer then
        minimumTransferDelay = MIN_DEFERRED_TRANSFER_DELAY_MS
    end
    if player:isDead()
        or player:getVehicle()
        or player:isOnFloor()
        or player:hasHitReaction()
        or now < request.startedAt + minimumTransferDelay
        or now > request.expiresAt
        or math.floor(player:getZ()) ~= request.originZ then
        rollbackRequest(player, request, "timing")
        reject(player, requestId, "Transfer", "timing")
        return
    end

    -- The client-side controller advances the character along the route after
    -- BeginAccepted. Validate a narrow corridor instead of requiring it to
    -- remain at the origin until the final event.
    local direction = Validation.DIRECTIONS[request.directionName]
    local dx = player:getX() - request.startX
    local dy = player:getY() - request.startY
    local forward = direction and (dx * direction.dx + dy * direction.dy) or -1000000
    local lateral = direction and math.abs(dx * direction.dy - dy * direction.dx) or 1000000
    if forward < -MAX_PATH_OVERSHOOT
        or forward > request.distance + MAX_PATH_OVERSHOOT
        or lateral > MAX_LATERAL_DEVIATION then
        rollbackRequest(player, request, "distance")
        reject(player, requestId, "Transfer", "distance")
        return
    end

    local target, reason = Validation.findTargetFromOrigin(
        request.originX,
        request.originY,
        request.originZ,
        request.directionName,
        request.distance,
        player,
        request.startX,
        request.startY
    )
    if not target then
        rollbackRequest(player, request, reason or "target")
        reject(player, requestId, "Transfer", reason or "target")
        return
    end

    local transferX = target.targetX
    local transferY = target.targetY
    Validation.moveCharacter(player, transferX, transferY, target.targetZ)
    sendServerCommand(player, MODULE, "TransferAccepted", {
        requestId = requestId,
        x = transferX,
        y = transferY,
        z = target.targetZ,
        landingZ = target.landingZ,
        dropLanding = target.dropLanding == true,
    })
    debugLog("Transferred request " .. tostring(requestId))
end

local function cancelRequest(player, args)
    local requestId = args and args.requestId
    local request = player and pendingByPlayer[player]
    if not request or request.requestId ~= requestId then
        return
    end
    pendingByPlayer[player] = nil
    rollbackRequest(player, request, "cancel")
    debugLog("Cancelled request " .. tostring(requestId))
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end
    if command == "Begin" then
        beginRequest(player, args)
    elseif command == "Transfer" then
        completeRequest(player, args)
    elseif command == "Cancel" then
        cancelRequest(player, args)
    end
end

local function removeExpiredRequests()
    local now = getTimestampMs()
    for player, request in pairs(pendingByPlayer) do
        local expired = now > request.expiresAt
        if expired then
            rollbackRequest(player, request, "timeout")
        end
        if not player or player:isDead() or player:getVehicle() or expired then
            pendingByPlayer[player] = nil
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(removeExpiredRequests)
