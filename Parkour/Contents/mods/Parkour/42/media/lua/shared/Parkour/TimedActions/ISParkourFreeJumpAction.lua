require "TimedActions/ISBaseTimedAction"

local Validation = require "Parkour/Parkour_FreeJumpValidation"

ISParkourFreeJumpAction = ISBaseTimedAction:derive("ISParkourFreeJumpAction")

local MODULE = "ParkourFreeJump"
local ACTION_ANIMATION = "ParkourFreeJump"
local DISTANCE_VARIABLE = "ParkourFreeJumpDistance"
local DEFERRED_VARIABLE = "ParkourFreeJumpDeferred"
local ANIMATION_START_TIMEOUT_MS = 600
local ANIMATION_FAILSAFE_MS = 2300
local NETWORK_REQUEST_LIFETIME_MS = 6000
-- Frames 1..31 at 30 FPS contain one second of authored movement. Horizontal
-- Translation Data is intentionally removed from the exported clips; this
-- controller is the single owner of the character's world X/Y during a jump.
local MOVEMENT_DURATION_MS = 1000
-- B42 enters PlayerFallingState after roughly half a second without a floor,
-- even when fallTime and logical Z are continuously held. Finish the approved
-- horizontal crossing before that threshold and then hand control to vanilla
-- falling at the endpoint.
local DEFERRED_TAKEOFF_DURATION_MS = 120
local DEFERRED_MOVEMENT_DURATION_MS = 400

local pendingNetworkRequests = {}
local nextRequestId = 1

local function isCurrentState(character, stateClass)
    return stateClass
        and stateClass.instance
        and character:getCurrentState() == stateClass.instance()
end

local function isForcedPlayerState(character)
    return character:hasHitReaction()
        or isCurrentState(character, PlayerHitReactionState)
        or isCurrentState(character, PlayerHitReactionPVPState)
        or isCurrentState(character, BumpedState)
        or isCurrentState(character, StaggerBackState)
        or isCurrentState(character, PlayerFallDownState)
        or isCurrentState(character, PlayerFallingState)
        or isCurrentState(character, PlayerKnockedDown)
        or isCurrentState(character, PlayerOnGroundState)
        or isCurrentState(character, PlayerGetUpState)
        or isCurrentState(character, VehicleCollisionMinorStaggerState)
        or isCurrentState(character, VehicleCollisionOnGroundState)
        or isCurrentState(character, VehicleCollisionState)
end

local function isFallingState(character)
    return character:isbFalling()
        or isCurrentState(character, PlayerFallingState)
end

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour FreeJump] " .. message)
    end
end

local function allocateRequestId()
    nextRequestId = nextRequestId + 1
    if nextRequestId > 1000000000 then
        nextRequestId = 1
    end
    return nextRequestId
end

local function sendBegin(action)
    if not isClient() then
        return
    end
    sendClientCommand(action.character, MODULE, "Begin", {
        requestId = action.requestId,
        originX = action.target.originX,
        originY = action.target.originY,
        originZ = action.target.originZ,
        directionName = action.target.directionName,
        distance = action.target.distance,
        landingSquareX = action.target.landingSquare:getX(),
        landingSquareY = action.target.landingSquare:getY(),
        landingSquareZ = action.target.landingSquare:getZ(),
    })
end

local function sendCancel(action)
    if not isClient() or action.transferred then
        return
    end
    sendClientCommand(action.character, MODULE, "Cancel", {
        requestId = action.requestId,
    })
end

local function startApprovedAnimation(action)
    if action.animationRequestedAt then
        return
    end
    action.animationRequestedAt = getTimestampMs()
    action:setActionAnim(ACTION_ANIMATION)
end

local function stabilizeDeferredMovement(action)
    if not action.target.requiresDeferredTransfer or action.transferred then
        return
    end

    local character = action.character
    character:setFallTime(0)
    character:setZ(action.target.originZ)
    character:setLastZ(action.target.originZ)
    character:setbFalling(false)

    local currentSquare = character:getCurrentSquare()
    if currentSquare and currentSquare ~= action.lastKnownSquare then
        -- Build 42's jump implementation uses this when crossing a loaded air
        -- square. It initializes the surrounding square references without
        -- creating a fake floor or modifying the map.
        if not currentSquare:hasFloor() then
            currentSquare:EnsureSurroundNotNull()
        end
        action.lastKnownSquare = currentSquare
    end
end

local function performLocalTransfer(action)
    local target, reason = Validation.findTargetFromOrigin(
        action.target.originX,
        action.target.originY,
        action.target.originZ,
        action.target.directionName,
        action.target.distance,
        action.character,
        action.target.startX,
        action.target.startY
    )
    if not target then
        return false, reason
    end

    debugLog(string.format(
        "Finalizing movement: current=(%.3f, %.3f), target=(%.3f, %.3f), progress=%.3f",
        action.character:getX(),
        action.character:getY(),
        target.targetX,
        target.targetY,
        action.movementProgress or 0
    ))
    Validation.moveCharacter(
        action.character,
        target.targetX,
        target.targetY,
        target.targetZ
    )
    action.dropLanding = target.dropLanding == true
    action.transferred = true
    return true
end

local function updateProgressiveMovement(action, now)
    if not action.animationStarted or action.transferred then
        return
    end
    local movementStartedAt = action.animationStartedAt
    local movementDuration = MOVEMENT_DURATION_MS
    if action.target.requiresDeferredTransfer then
        -- Let the first jump frames read as a take-off while the character is
        -- still supported by the roof. The actual air-square crossing keeps
        -- its proven 400 ms window, so slowing the visible clip does not bring
        -- back PlayerFallingState before the endpoint.
        movementStartedAt = movementStartedAt + DEFERRED_TAKEOFF_DURATION_MS
        movementDuration = DEFERRED_MOVEMENT_DURATION_MS
    end
    local linearProgress = (now - movementStartedAt) / movementDuration
    if linearProgress < 0 then
        linearProgress = 0
    elseif linearProgress > 1 then
        linearProgress = 1
    end

    local progress = linearProgress
    if action.target.requiresDeferredTransfer then
        -- Smoothstep keeps the same safe crossing duration, but removes the
        -- velocity snap after take-off and the hard stop before vanilla fall.
        progress = linearProgress * linearProgress * (3 - 2 * linearProgress)
    end

    local desiredX = action.target.startX
        + (action.target.targetX - action.target.startX) * progress
    local desiredY = action.target.startY
        + (action.target.targetY - action.target.startY) * progress
    if action.target.requiresDeferredTransfer then
        local cell = getCell()
        local destinationSquare = cell and cell:getGridSquare(
            math.floor(desiredX),
            math.floor(desiredY),
            action.target.originZ
        )
        if destinationSquare and not destinationSquare:hasFloor() then
            destinationSquare:EnsureSurroundNotNull()
        end
    end
    -- Direct position updates deliberately bypass the collision response of
    -- the low fence/furniture that was approved by the route validator. Do not
    -- overwrite LastX/LastY every frame: those values carry the movement delta
    -- used by interpolation and multiplayer replication. The final commit (or
    -- an abort rollback) synchronizes both current and last coordinates once.
    action.character:setX(desiredX)
    action.character:setY(desiredY)
    if action.target.requiresDeferredTransfer then
        -- Match the current B42 Jump implementation while crossing an air
        -- square. Keeping Last* synchronized prevents the engine from treating
        -- the controlled horizontal displacement as an accumulated fall.
        action.character:setLastX(desiredX)
        action.character:setLastY(desiredY)
        action.character:setLastZ(action.target.originZ)
    end
    action.movementProgress = progress

    if action.target.requiresDeferredTransfer
        and linearProgress >= 1
        and not action.transferRequested then
        action:requestTransfer()
    end
end

local function rollbackIncompleteMovement(action)
    if action.transferred or (action.movementProgress or 0) <= 0 then
        return
    end

    local succeeded, failure = pcall(
        Validation.moveCharacter,
        action.character,
        action.target.startX,
        action.target.startY,
        action.target.originZ
    )
    if succeeded then
        debugLog(string.format(
            "Rolled incomplete movement back to (%.3f, %.3f) at progress %.3f",
            action.target.startX,
            action.target.startY,
            action.movementProgress or 0
        ))
        action.movementProgress = 0
    else
        debugLog("Rollback failed: " .. tostring(failure))
    end
end

function ISParkourFreeJumpAction.canStart(character, target, ignoreQueue)
    if not character
        or not target
        or character:isDead()
        or character:getVehicle()
        or character:isOnFloor()
        or character:isBlockMovement()
        or character:getIgnoreMovement()
        or character:isAttacking()
        or character:isbFalling()
        or isForcedPlayerState(character)
        or (not ignoreQueue and character:hasTimedActions()) then
        return false
    end
    if math.floor(character:getX()) ~= target.originX
        or math.floor(character:getY()) ~= target.originY
        or math.floor(character:getZ()) ~= target.originZ
        or math.abs(character:getX() - target.startX) > 0.75
        or math.abs(character:getY() - target.startY) > 0.75 then
        return false
    end

    local refreshed = Validation.findTargetFromOrigin(
        target.originX,
        target.originY,
        target.originZ,
        target.directionName,
        target.distance,
        character,
        target.startX,
        target.startY
    )
    return refreshed ~= nil
end

function ISParkourFreeJumpAction:isValidStart()
    return ISParkourFreeJumpAction.canStart(self.character, self.target, true)
end

function ISParkourFreeJumpAction:isValid()
    return not self.invalid
        and not self.character:isDead()
        and not self.character:getVehicle()
end

function ISParkourFreeJumpAction:start()
    self.action:setUseProgressBar(false)
    self.startedAt = getTimestampMs()
    self.character:setVariable(DISTANCE_VARIABLE, tostring(self.target.distance))
    self.character:setVariable(
        DEFERRED_VARIABLE,
        tostring(self.target.requiresDeferredTransfer == true)
    )
    self.character:setForwardDirection(self.facingX, self.facingY)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self.character:setIgnoreMovement(true)
    self.ownsMovementLock = true
    if self.target.requiresDeferredTransfer then
        self.lastKnownSquare = self.character:getCurrentSquare()
        self.fallGuardCallback = function()
            stabilizeDeferredMovement(self)
        end
        Events.OnTick.Add(self.fallGuardCallback)
        stabilizeDeferredMovement(self)
    end

    pendingNetworkRequests[self.requestId] = {
        action = self,
        expiresAt = self.startedAt + NETWORK_REQUEST_LIFETIME_MS,
    }
    sendBegin(self)
    if not isClient() then
        startApprovedAnimation(self)
    end
    debugLog(string.format(
        "Started request %s: %s, %d tiles; drop=%s landingZ=%d deferred=%s",
        tostring(self.requestId),
        self.target.directionName,
        self.target.distance,
        tostring(self.target.dropLanding == true),
        self.target.landingZ,
        tostring(self.target.requiresDeferredTransfer == true)
    ))
end

function ISParkourFreeJumpAction:update()
    stabilizeDeferredMovement(self)
    if isForcedPlayerState(self.character) then
        self.invalid = true
        debugLog("Interrupted by forced player state: " .. tostring(self.character:getCurrentState()))
        self:forceComplete()
        return
    end

    self.character:setIgnoreMovement(true)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self.character:setForwardDirection(self.facingX, self.facingY)
    self.character:setMetabolicTarget(Metabolics.JumpFence)

    local now = getTimestampMs()
    if isClient() and not self.serverApproved then
        return
    end
    if not self.animationRequestedAt then
        startApprovedAnimation(self)
    end
    if not self.animationStarted then
        if now - self.animationRequestedAt >= ANIMATION_START_TIMEOUT_MS then
            self.invalid = true
            debugLog("Animation start timeout for request " .. tostring(self.requestId))
            self:forceComplete()
        end
        return
    end

    updateProgressiveMovement(self, now)

    if now - self.animationStartedAt >= ANIMATION_FAILSAFE_MS
        and (not self.transferRequested or self.transferred) then
        self.invalid = true
        debugLog("Animation failsafe for request " .. tostring(self.requestId))
        self:forceComplete()
    end
end

function ISParkourFreeJumpAction:requestTransfer()
    if self.transferRequested or self.transferred then
        return
    end
    self.transferRequested = true

    if isClient() then
        sendClientCommand(self.character, MODULE, "Transfer", {
            requestId = self.requestId,
        })
        debugLog("Requested server transfer " .. tostring(self.requestId))
        return
    end

    local moved, reason = performLocalTransfer(self)
    if not moved then
        self.invalid = true
        debugLog("Local transfer rejected: " .. tostring(reason))
        self:forceComplete()
    else
        pendingNetworkRequests[self.requestId] = nil
        debugLog("Local transfer completed " .. tostring(self.requestId))
        if self.target.requiresDeferredTransfer then
            -- Transfer is already at 99% of the clip. Finish immediately so
            -- the next engine update can enter vanilla falling without this
            -- action reasserting IgnoreMovement.
            self.animationDone = true
            self:forceComplete()
        end
    end
end

function ISParkourFreeJumpAction:animEvent(event, parameter)
    if event == "ParkourFreeJumpStarted" and not self.animationStarted then
        self.animationStarted = true
        self.animationStartedAt = getTimestampMs()
        debugLog(string.format(
            "Animation confirmed %s; movement=(%.3f, %.3f)->(%.3f, %.3f)",
            tostring(self.requestId),
            self.target.startX,
            self.target.startY,
            self.target.targetX,
            self.target.targetY
        ))
    elseif event == "ParkourFreeJumpTransfer" then
        self:requestTransfer()
    elseif event == "ParkourFreeJumpDone" then
        self.animationDone = true
        if not self.transferRequested then
            self:requestTransfer()
        end
        if not isClient() or self.transferred or self.invalid then
            self:forceComplete()
        end
    end
end

function ISParkourFreeJumpAction:releaseControl()
    if self.controlReleased then
        return
    end
    self.controlReleased = true
    if self.fallGuardCallback then
        Events.OnTick.Remove(self.fallGuardCallback)
        self.fallGuardCallback = nil
    end
    rollbackIncompleteMovement(self)
    self.character:clearVariable(DISTANCE_VARIABLE)
    self.character:clearVariable(DEFERRED_VARIABLE)
    if self.ownsMovementLock then
        -- A hit/fall state owns its own movement lock. Do not clear that lock
        -- when the jump is interrupted; the state will release it normally.
        if not isForcedPlayerState(self.character)
            or isFallingState(self.character)
            or self.dropLanding then
            self.character:setIgnoreMovement(false)
        end
        self.ownsMovementLock = false
    end
    sendCancel(self)
    pendingNetworkRequests[self.requestId] = nil
end

function ISParkourFreeJumpAction:stop()
    self:releaseControl()
    ISBaseTimedAction.stop(self)
end

function ISParkourFreeJumpAction:perform()
    self:releaseControl()
    ISBaseTimedAction.perform(self)
end

function ISParkourFreeJumpAction:complete()
    return true
end

function ISParkourFreeJumpAction:getDuration()
    return -1
end

function ISParkourFreeJumpAction.onServerCommand(module, command, args)
    if module ~= MODULE or not args then
        return
    end

    local entry = pendingNetworkRequests[args.requestId]
    local action = entry and entry.action
    if not action then
        return
    end

    if command == "BeginAccepted" then
        action.serverApproved = true
        startApprovedAnimation(action)
        debugLog("Server approved " .. tostring(args.requestId))
    elseif command == "BeginRejected" then
        pendingNetworkRequests[args.requestId] = nil
        action.invalid = true
        debugLog("Server rejected start: " .. tostring(args.reason))
        action:forceComplete()
    elseif command == "TransferAccepted" then
        Validation.moveCharacter(action.character, args.x, args.y, args.z)
        action.dropLanding = args.dropLanding == true
            or action.target.dropLanding == true
        action.transferred = true
        pendingNetworkRequests[args.requestId] = nil
        debugLog("Server transfer accepted " .. tostring(args.requestId))
        if action.animationDone or action.target.requiresDeferredTransfer then
            action.animationDone = true
            action:forceComplete()
        end
    elseif command == "TransferRejected" then
        pendingNetworkRequests[args.requestId] = nil
        action.invalid = true
        debugLog("Server transfer rejected: " .. tostring(args.reason))
        action:forceComplete()
    end
end

function ISParkourFreeJumpAction.updateNetwork(character)
    local now = getTimestampMs()
    for requestId, entry in pairs(pendingNetworkRequests) do
        if now > entry.expiresAt then
            pendingNetworkRequests[requestId] = nil
            if entry.action and not entry.action.transferred then
                entry.action.invalid = true
                entry.action:forceComplete()
                debugLog("Network request timed out " .. tostring(requestId))
            end
        end
    end
end

function ISParkourFreeJumpAction:new(character, target)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.target = target
    action.facingX = target.direction.dx
    action.facingY = target.direction.dy
    action.requestId = allocateRequestId()
    action.invalid = false
    action.animationStarted = false
    action.animationStartedAt = nil
    action.animationRequestedAt = nil
    action.animationDone = false
    action.transferRequested = false
    action.transferred = false
    action.movementProgress = 0
    action.dropLanding = target.dropLanding == true
    action.serverApproved = not isClient()
    action.controlReleased = false
    action.ownsMovementLock = false
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.maxTime = action:getDuration()
    return action
end

if isClient() then
    Events.OnServerCommand.Add(ISParkourFreeJumpAction.onServerCommand)
end

return ISParkourFreeJumpAction
