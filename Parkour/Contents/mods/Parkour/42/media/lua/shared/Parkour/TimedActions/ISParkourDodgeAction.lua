require "TimedActions/ISBaseTimedAction"

ISParkourDodgeAction = ISBaseTimedAction:derive("ISParkourDodgeAction")

local ACTION_ANIMATION = "ParkourDodge"
local DIRECTION_VARIABLE = "ParkourDodgeDirection"

local DODGE_DISTANCE = 2.0
local DEFAULT_MOVEMENT_DURATION_MS = 600
local BACKWARD_MOVEMENT_DURATION_MS = 1300 --1650
local BACKWARD_LINEAR_MOVEMENT_BLEND = 0.65
-- The backward dodge currently lasts about 1.69 seconds at SpeedScale 1.50.
-- Keep the emergency timeout beyond the animation event so it cannot cut the
-- clip short and force an abrupt transition back to locomotion.
local FAILSAFE_DURATION_MS = 2200
local MAX_MOVEMENT_STEP = 0.08

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Dodge] " .. message)
    end
end

local function isEdgeBlocked(fromSquare, toSquare)
    if not fromSquare or not toSquare then
        return true
    end
    if fromSquare:isBlockedTo(toSquare) then
        return true
    end
    if fromSquare:testCollideSpecialObjects(toSquare) then
        return true
    end
    return toSquare:isSolid() or toSquare:isSolidTrans()
end

local function isVehicleBlocked(character, targetX, targetY)
    local vehicle = character:getNearVehicle()
    return vehicle and vehicle:isInBounds(targetX, targetY)
end

local function canMoveTo(character, targetX, targetY)
    if isVehicleBlocked(character, targetX, targetY) then
        return false
    end

    local cell = getCell()
    if not cell then
        return false
    end

    local z = math.floor(character:getZ())
    local sourceX = math.floor(character:getX())
    local sourceY = math.floor(character:getY())
    local targetSquareX = math.floor(targetX)
    local targetSquareY = math.floor(targetY)

    local fromSquare = cell:getGridSquare(sourceX, sourceY, z)
    local toSquare = cell:getGridSquare(targetSquareX, targetSquareY, z)
    if not fromSquare or not toSquare then
        return false
    end
    if fromSquare == toSquare then
        return true
    end

    local stepX = targetSquareX - sourceX
    local stepY = targetSquareY - sourceY
    if math.abs(stepX) > 1 or math.abs(stepY) > 1 then
        return false
    end

    if stepX == 0 or stepY == 0 then
        return not isEdgeBlocked(fromSquare, toSquare)
    end

    -- A diagonal is allowed only when both sides of the corner are open.
    local horizontalSquare = cell:getGridSquare(sourceX + stepX, sourceY, z)
    local verticalSquare = cell:getGridSquare(sourceX, sourceY + stepY, z)
    if isEdgeBlocked(fromSquare, horizontalSquare)
        or isEdgeBlocked(fromSquare, verticalSquare)
        or isEdgeBlocked(horizontalSquare, toSquare)
        or isEdgeBlocked(verticalSquare, toSquare) then
        return false
    end

    return true
end

local function moveDistance(action, distance)
    local remaining = distance

    while remaining > 0.0001 do
        local step = math.min(remaining, MAX_MOVEMENT_STEP)
        local targetX = action.character:getX() + action.travelX * step
        local targetY = action.character:getY() + action.travelY * step

        if not canMoveTo(action.character, targetX, targetY) then
            action.movementBlocked = true
            debugLog("Movement stopped by collision: " .. action.direction)
            return
        end

        action.character:moveUnmodded(action.travelX * step, action.travelY * step)
        action.distanceMoved = action.distanceMoved + step
        remaining = remaining - step
    end
end

local function canStartInternal(character, travelX, travelY, ignoreActionQueue)
    if not character or character:isDead() or character:getVehicle() then
        return false
    end
    if (not ignoreActionQueue and character:hasTimedActions()) or character:isBlockMovement() then
        return false
    end
    if character:isOnFloor() or character:isCurrentState(PlayerFallingState.instance()) then
        return false
    end

    local square = character:getCurrentSquare()
    if not square or square:HasStairs() then
        return false
    end

    return canMoveTo(
        character,
        character:getX() + travelX * 0.12,
        character:getY() + travelY * 0.12
    )
end

function ISParkourDodgeAction.canStart(character, travelX, travelY)
    return canStartInternal(character, travelX, travelY, false)
end

function ISParkourDodgeAction:isValidStart()
    -- At this point the action itself is already present in the queue.
    return canStartInternal(self.character, self.travelX, self.travelY, true)
end

function ISParkourDodgeAction:isValid()
    return not self.isInvalid
end

function ISParkourDodgeAction:start()
    self.action:setUseProgressBar(false)
    self.startedAt = getTimestampMs()
    self.wasIgnoringMovement = self.character:getIgnoreMovement()
    self.wasRunning = self.character:isRunning()
    self.wasSprinting = self.character:isSprinting()

    self.character:setVariable(DIRECTION_VARIABLE, self.direction)
    self.character:setForwardDirection(self.facingX, self.facingY)
    self.character:setIgnoreMovement(true)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self:setActionAnim(ACTION_ANIMATION)
end

function ISParkourDodgeAction:update()
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setForwardDirection(self.facingX, self.facingY)

    local elapsed = getTimestampMs() - self.startedAt
    local movementDuration = DEFAULT_MOVEMENT_DURATION_MS
    local linearMovementBlend = 0
    if self.direction == "Backward" then
        movementDuration = BACKWARD_MOVEMENT_DURATION_MS
        linearMovementBlend = BACKWARD_LINEAR_MOVEMENT_BLEND
    end

    local movementProgress = math.min(math.max(elapsed / movementDuration, 0), 1)
    local smoothProgress = movementProgress * movementProgress * (3 - 2 * movementProgress)
    -- The backward evade keeps some linear velocity near its exit so the
    -- locomotion state can take over without a visible stop-and-start.
    local easedProgress = smoothProgress + (movementProgress - smoothProgress) * linearMovementBlend
    local targetDistance = DODGE_DISTANCE * easedProgress

    if not self.movementBlocked and targetDistance > self.distanceMoved then
        moveDistance(self, targetDistance - self.distanceMoved)
    end

    -- Prevent a missing or rejected AnimNode from locking the player forever.
    if elapsed >= FAILSAFE_DURATION_MS then
        debugLog("Failsafe completion: " .. self.direction)
        self:forceComplete()
    end
end

function ISParkourDodgeAction:animEvent(event, parameter)
    if event == "ParkourDodgeDone" then
        self:forceComplete()
    end
end

function ISParkourDodgeAction:releaseControl()
    if self.controlReleased then
        return
    end
    self.controlReleased = true

    self.character:clearVariable(DIRECTION_VARIABLE)
    if self.startedAt then
        self.character:setIgnoreMovement(self.wasIgnoringMovement == true)
        self.character:setRunning(self.wasRunning == true)
        self.character:setSprinting(self.wasSprinting == true)
    end
end

function ISParkourDodgeAction:stop()
    self:releaseControl()
    ISBaseTimedAction.stop(self)
end

function ISParkourDodgeAction:perform()
    self:releaseControl()
    ISBaseTimedAction.perform(self)
end

function ISParkourDodgeAction:complete()
    return true
end

function ISParkourDodgeAction:getDuration()
    return -1
end

function ISParkourDodgeAction:new(character, direction, travelX, travelY, facingX, facingY)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.direction = direction
    action.travelX = travelX
    action.travelY = travelY
    action.facingX = facingX
    action.facingY = facingY
    action.distanceMoved = 0
    action.movementBlocked = false
    action.isInvalid = false
    action.controlReleased = false
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.maxTime = action:getDuration()
    return action
end

return ISParkourDodgeAction
