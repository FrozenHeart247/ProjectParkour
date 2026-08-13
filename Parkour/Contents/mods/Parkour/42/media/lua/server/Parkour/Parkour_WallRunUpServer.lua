local Validation = require "Parkour/Parkour_WallRunUpValidation"
local ZombieAttackGuard = require "Parkour/Parkour_ZombieAttackGuard"

local MODULE = "ParkourWallRunUp"
local REQUEST_LIFETIME_MS = 4500
local MIN_AIRBORNE_DELAY_MS = 100
local MAX_AIRBORNE_DURATION_MS = 2500
local ATTACK_TAIL_GUARD_MS = 1500
local MIN_TRANSFER_DELAY_MS = 850
local MAX_PATH_OVERSHOOT = 0.75
local MAX_LATERAL_DEVIATION = 0.90
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

local function isInsideMovementCorridor(player, request)
    local direction = Validation.DIRECTIONS[request.directionName]
    if not direction then
        return false
    end

    local dx = player:getX() - (request.originX + 0.5)
    local dy = player:getY() - (request.originY + 0.5)
    local forward = dx * direction.dx + dy * direction.dy
    local lateral = math.abs(dx * -direction.dy + dy * direction.dx)
    return forward >= -MAX_PATH_OVERSHOOT
        and forward <= Validation.TRAVEL_TILES + MAX_PATH_OVERSHOOT
        and lateral <= MAX_LATERAL_DEVIATION
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
    if math.floor(player:getX()) ~= originX
        or math.floor(player:getY()) ~= originY
        or math.floor(player:getZ()) ~= originZ then
        reject(player, requestId, "Begin", "origin")
        return
    end

    local facingAlignment = Validation.getDirectionAlignment(player, args.directionName)
    if facingAlignment < 0.70 then
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
        airborne = false,
        airborneExpiresAt = nil,
        airborneAttackers = ZombieAttackGuard.newAttackerSet(),
        interruptedAttackerCount = 0,
    }
    cooldownByPlayer[player] = now + COOLDOWN_MS
    sendServerCommand(player, MODULE, "BeginAccepted", { requestId = requestId })
    debugLog("Accepted begin request " .. tostring(requestId))
end

local function beginAirborneRequest(player, args)
    local requestId = args and args.requestId
    local request = player and pendingByPlayer[player]
    if not request or request.requestId ~= requestId then
        if player and isValidRequestId(requestId) then
            reject(player, requestId, "Airborne", "request")
        end
        return
    end

    if request.airborne then
        sendServerCommand(player, MODULE, "AirborneAccepted", {
            requestId = requestId,
        })
        return
    end

    local now = getTimestampMs()
    if player:isDead()
        or player:getVehicle()
        or now < request.startedAt + MIN_AIRBORNE_DELAY_MS
        or now > request.expiresAt
        or math.floor(player:getZ()) ~= request.originZ
        or not isInsideMovementCorridor(player, request) then
        reject(player, requestId, "Airborne", "timing")
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
        reject(player, requestId, "Airborne", reason or "target")
        return
    end

    request.airborne = true
    request.airborneExpiresAt = math.min(
        request.expiresAt,
        now + MAX_AIRBORNE_DURATION_MS
    )
    sendServerCommand(player, MODULE, "AirborneAccepted", {
        requestId = requestId,
    })
    debugLog("Accepted airborne guard " .. tostring(requestId))
end

local function finishAirborneGuard(player, request)
    if not request or not request.airborne then
        return
    end

    request.airborne = false
    ZombieAttackGuard.beginTailGuard(
        player,
        request.airborneAttackers,
        ATTACK_TAIL_GUARD_MS
    )
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
    finishAirborneGuard(player, request)

    local now = getTimestampMs()
    if player:isDead()
        or player:getVehicle()
        or now < request.startedAt + MIN_TRANSFER_DELAY_MS
        or now > request.expiresAt
        or math.floor(player:getZ()) ~= request.originZ then
        reject(player, requestId, "Transfer", "timing")
        return
    end

    if not isInsideMovementCorridor(player, request) then
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

local function cancelRequest(player, args)
    local requestId = args and args.requestId
    local request = player and pendingByPlayer[player]
    if not request or request.requestId ~= requestId then
        return
    end

    pendingByPlayer[player] = nil
    finishAirborneGuard(player, request)
    debugLog("Cancelled request " .. tostring(requestId))
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end
    if command == "Begin" then
        beginRequest(player, args)
    elseif command == "Airborne" then
        beginAirborneRequest(player, args)
    elseif command == "Transfer" then
        completeRequest(player, args)
    elseif command == "Cancel" then
        cancelRequest(player, args)
    end
end

local function updateAirborneGuards()
    local now = getTimestampMs()

    for player, request in pairs(pendingByPlayer) do
        if not player
            or player:isDead()
            or player:getVehicle()
            or now > request.expiresAt then
            pendingByPlayer[player] = nil
            finishAirborneGuard(player, request)
        elseif request.airborne then
            if now > request.airborneExpiresAt
                or math.floor(player:getZ()) ~= request.originZ then
                finishAirborneGuard(player, request)
            else
                local newlyInterrupted = ZombieAttackGuard.interruptNearby(
                    player,
                    request.airborneAttackers
                )
                if newlyInterrupted > 0 then
                    request.interruptedAttackerCount = request.interruptedAttackerCount
                        + newlyInterrupted
                    debugLog(
                        "Airborne interrupted zombie attackers: "
                            .. tostring(request.interruptedAttackerCount)
                    )
                end
            end
        end
    end

    ZombieAttackGuard.updateAllTailGuards()
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(updateAirborneGuards)
