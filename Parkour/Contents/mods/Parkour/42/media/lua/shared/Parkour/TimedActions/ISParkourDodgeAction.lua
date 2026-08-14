require "TimedActions/ISBaseTimedAction"

ISParkourDodgeAction = ISBaseTimedAction:derive("ISParkourDodgeAction")

local ACTION_ANIMATION = "ParkourDodge"
local DIRECTION_VARIABLE = "ParkourDodgeDirection"
local VARIANT_VARIABLE = "ParkourDodgeVariant"
local REACTION_DODGE_NAME = "ParkourDodgeReaction"
local HIT_REACTION_ACTION_STATE = "hitreaction"
local ACTIVE_ANIM_FINISHING_EVENT = "ActiveAnimFinishing"
local DEFAULT_DODGE_DISTANCE = 3
local DEFAULT_MOVEMENT_DURATION_MS = 700
local DEFAULT_FAILSAFE_DURATION_MS = 2200
local ANIMATION_START_TIMEOUT_MS = 500
local REACTION_TAIL_GUARD_MS = 1500
local REACTION_ATTACK_CAPTURE_RADIUS = 3.5
local MAX_MOVEMENT_STEP = 0.08

local reactionTailByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Dodge] " .. message)
    end
end

local function isCurrentState(character, stateClass)
    return stateClass
        and stateClass.instance
        and character:getCurrentState() == stateClass.instance()
end

local function isHitReactionState(character)
    if character:hasHitReaction() then
        return true
    end

    return isCurrentState(character, PlayerHitReactionState)
        or isCurrentState(character, PlayerHitReactionPVPState)
end

local function isEscapableReactionState(character)
    return isHitReactionState(character)
        or isCurrentState(character, BumpedState)
        or isCurrentState(character, StaggerBackState)
end

local function isHardForcedState(character)
    return isCurrentState(character, PlayerFallDownState)
        or isCurrentState(character, PlayerFallingState)
        or isCurrentState(character, PlayerKnockedDown)
        or isCurrentState(character, PlayerOnGroundState)
        or isCurrentState(character, PlayerGetUpState)
        or isCurrentState(character, VehicleCollisionMinorStaggerState)
        or isCurrentState(character, VehicleCollisionOnGroundState)
        or isCurrentState(character, VehicleCollisionState)
        or isCurrentState(character, GrappledThrownIntoContainerState)
        or isCurrentState(character, GrappledThrownOutWindowState)
        or isCurrentState(character, GrappledThrownOverFenceState)
end

local function isFallingState(character)
    return character:isbFalling()
        or isCurrentState(character, PlayerFallingState)
end

local function isForcedPlayerState(character)
    return isEscapableReactionState(character) or isHardForcedState(character)
end

local function leaveHitReactionState(character)
    character:setHitReaction("")

    if isHitReactionState(character)
        and PlayerMovementState
        and PlayerMovementState.instance then
        character:changeState(PlayerMovementState.instance())
        debugLog("Cleared trailing hit-reaction state")
    end
end

local function finishStaleReactionActionState(character)
    -- changeState(PlayerMovementState) only changes the Java state. When a bite
    -- was interrupted, the animation state machine can remain in hitreaction
    -- and play its stale node several steps later. The vanilla player action
    -- graph exits hitreaction on ActiveAnimFinishing, so report that same event
    -- after the old reaction payload is completely gone. A genuinely new hit
    -- still has either a reaction state/name or an attacker and is left alone.
    if character:getActionStateName() ~= HIT_REACTION_ACTION_STATE
        or not isCurrentState(character, PlayerMovementState)
        or character:hasHitReaction()
        or character:getAttackedBy() ~= nil then
        return false
    end

    character:reportEvent(ACTIVE_ANIM_FINISHING_EVENT)
    debugLog("Requested stale action-state finish: ActiveAnimFinishing")
    return true
end

local function beginReactionTailGuard(action)
    reactionTailByCharacter[action.character] = {
        expiresAt = getTimestampMs() + REACTION_TAIL_GUARD_MS,
        action = action,
    }
end

local function isPendingZombieAttack(zombie, character)
    if not zombie or zombie:isDead() then
        return false
    end

    local outcome = zombie:getVariableString("AttackOutcome")
    return zombie:getTarget() == character
        and (zombie:isAttacking()
            or outcome == "start"
            or outcome == "success")
end

local function trackReactionAttacker(action, zombie)
    if not zombie or zombie:isDead() or not zombie:isZombie() then
        return
    end

    action.reactionAttackers[zombie] = true
end

local function rememberReactionAttackers(action)
    if not action.reactionAnimation then
        return
    end

    local attackedBy = action.character:getAttackedBy()
    if attackedBy and attackedBy:isZombie() then
        -- getAttackedBy() is the authoritative source here. Do not require
        -- AttackOutcome or getTarget(): by the time Lua observes the player
        -- reaction, the zombie may already have advanced past that phase.
        trackReactionAttacker(action, attackedBy)
    end

    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then
        return
    end

    for index = 0, zombies:size() - 1 do
        local zombie = zombies:get(index)
        if zombie:DistTo(action.character) <= REACTION_ATTACK_CAPTURE_RADIUS
            and isPendingZombieAttack(zombie, action.character) then
            trackReactionAttacker(action, zombie)
        end
    end
end

local function clearReactionPayload(character)
    character:setAttackedBy(nil)
    character:setHitForce(0)
    -- Bite/push reactions also leave a separate BumpedState payload. It can
    -- remain dormant through the dodge and fire only after locomotion resumes.
    character:setBumpFall(false)
    character:setVariable("BumpFall", false)
    character:setBumpDone(true)
    character:setVariable("BumpDone", true)
    character:setVariable("BumpStaggered", false)
    character:setBumpType("")
    character:clearVariable("BumpFallType")
    character:clearVariable("BumpFallAnimFinished")
    character:clearVariable("ParkourBumpRecoveryFinish")
end

local function interruptReactionAttackers(action)
    rememberReactionAttackers(action)

    local newlyInterrupted = 0
    for zombie in pairs(action.reactionAttackers) do
        if zombie and not zombie:isDead() then
            -- Reassert this for the whole reaction dodge. A zombie AnimNode
            -- can otherwise write AttackOutcome=success again on a later
            -- frame and leave PlayerHitReaction=Bite queued behind our dodge.
            zombie:setAttackOutcome("interrupted")
            zombie:setVariable("AttackOutcome", "interrupted")
            zombie:clearVariable("PlayerHitReaction")
            zombie:setVariable("ZombieBiteDone", true)

            if not action.interruptedReactionAttackers[zombie] then
                action.interruptedReactionAttackers[zombie] = true
                action.interruptedReactionAttackerCount =
                    action.interruptedReactionAttackerCount + 1
                newlyInterrupted = newlyInterrupted + 1
            end
        end
    end

    -- PushAwayZombie reads these fields from the old reaction. Clear only the
    -- stale reaction payload; health and body damage are deliberately untouched.
    clearReactionPayload(action.character)
    return newlyInterrupted
end

function ISParkourDodgeAction.isForcedPlayerState(character)
    return character and isForcedPlayerState(character) or false
end

function ISParkourDodgeAction.isEscapableReactionState(character)
    return character and isEscapableReactionState(character) or false
end

function ISParkourDodgeAction.isHitReactionState(character)
    return character and isHitReactionState(character) or false
end

function ISParkourDodgeAction.updateReactionTailGuard(character)
    local guard = reactionTailByCharacter[character]
    if not guard then
        return false
    end

    local now = getTimestampMs()
    if now > guard.expiresAt
        or character:isDead()
        or character:getVehicle() then
        reactionTailByCharacter[character] = nil
        return false
    end

    -- The animation graph may reassert hitreaction one update after the Java
    -- state was changed, so keep this narrowly-scoped check for the tail guard.
    finishStaleReactionActionState(character)

    local attacker = character:getAttackedBy()
    local interruptedAttackers = guard.action
        and guard.action.reactionAttackers
    local attackerWasInterrupted = attacker
        and interruptedAttackers
        and interruptedAttackers[attacker] == true
    local attackerOutcome = attacker
        and attacker:getVariableString("AttackOutcome") or ""
    local attackerBiteDone = attacker
        and attacker:getVariableBoolean("ZombieBiteDone") or false
    local comesFromInterruptedAttack = attacker == nil
        or (attackerWasInterrupted
            and (attackerOutcome == "interrupted" or attackerBiteDone))

    if comesFromInterruptedAttack and isEscapableReactionState(character) then
        local staleState = tostring(character:getCurrentState())
        -- This is deliberately one-shot. Do not touch the zombie here: a later
        -- AttackOutcome=start/success is a genuinely new attack and must pass.
        clearReactionPayload(character)
        character:setHitReaction("")
        if PlayerMovementState and PlayerMovementState.instance then
            character:changeState(PlayerMovementState.instance())
        end
        character:setIgnoreMovement(false)
        reactionTailByCharacter[character] = nil
        debugLog(
            "Suppressed delayed reaction state: " .. staleState
                .. "; attacker=" .. tostring(attacker)
                .. "; outcome=" .. tostring(attackerOutcome)
                .. "; biteDone=" .. tostring(attackerBiteDone)
        )
        return true
    end

    return false
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

local function canStartInternal(character, travelX, travelY, ignoreActionQueue, allowReactionEscape)
    if not character or character:isDead() or character:getVehicle() then
        return false
    end
    local escapingReaction = allowReactionEscape or isEscapableReactionState(character)
    if (not ignoreActionQueue and character:hasTimedActions())
        or (character:isBlockMovement() and not escapingReaction)
        or (character:getIgnoreMovement() and not escapingReaction)
        or (character:isAttacking() and not escapingReaction)
        or isHardForcedState(character) then
        return false
    end
    if character:isOnFloor() then
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

function ISParkourDodgeAction.canStart(character, travelX, travelY, allowReactionEscape)
    return canStartInternal(character, travelX, travelY, false, allowReactionEscape)
end

function ISParkourDodgeAction:isValidStart()
    -- At this point the action itself is already present in the queue.
    return canStartInternal(
        self.character,
        self.travelX,
        self.travelY,
        true,
        self.escapeFromReaction
    )
end

function ISParkourDodgeAction:isValid()
    if self.startedAt and isHardForcedState(self.character) then
        self.isInvalid = true
        debugLog("Interrupted by a hard player state: " .. self.direction .. "/" .. self.variant)
    end
    return not self.isInvalid
end

function ISParkourDodgeAction:start()
    self.action:setUseProgressBar(false)
    self.startedAt = getTimestampMs()

    self.character:setVariable(DIRECTION_VARIABLE, self.direction)
    self.character:setVariable(VARIANT_VARIABLE, self.variant)
    if self.reactionAnimation then
        interruptReactionAttackers(self)
        -- Keep the existing Java reaction state and select a dedicated dodge
        -- node inside its AnimSet. This is the only route that remains stable
        -- while several zombies are trying to re-enter the bite reaction.
        self.character:setHitReaction(REACTION_DODGE_NAME)
        self.animationStarted = true
        self.animationStartedAt = self.startedAt + self.reactionAnimationLeadMs
        self.reactionAnimationEndsAt = self.startedAt + self.reactionAnimationDurationMs
        debugLog("Reaction dodge animation armed: " .. self.direction .. "/" .. self.variant)
    end
    self.character:setForwardDirection(self.facingX, self.facingY)
    -- A reaction escape explicitly takes ownership of the old hit-reaction
    -- movement lock. This lets us release it reliably after the dodge.
    self.ownsMovementLock = self.escapeFromReaction
        or not self.character:getIgnoreMovement()
    self.character:setIgnoreMovement(true)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self:setActionAnim(ACTION_ANIMATION)
    if self.reactionAnimation then
        debugLog("Prepared reaction dodge action: " .. self.direction .. "/" .. self.variant)
    end
end

function ISParkourDodgeAction:update()
    if self.reactionAnimation then
        -- Capture and terminate attackers immediately, then keep the vanilla
        -- interrupted outcome asserted until this dodge is complete. Waiting
        -- until release is too late: success.xml has already queued Bite.
        interruptReactionAttackers(self)
        -- A later attacker may write Bite/BiteLEFT again. Reassert our node so
        -- the reaction AnimSet cannot fall back to its vanilla HitReaction.
        self.character:setHitReaction(REACTION_DODGE_NAME)
    end

    self.character:setIgnoreMovement(true)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self.character:setForwardDirection(self.facingX, self.facingY)

    local now = getTimestampMs()
    if not self.animationStarted then
        -- Never move the character until the selected AnimNode confirms that
        -- it is actually playing. This prevents animation-less displacement
        -- when another state wins the transition.
        if now - self.startedAt >= ANIMATION_START_TIMEOUT_MS then
            debugLog(
                "Animation start timeout: " .. self.direction .. "/" .. self.variant
                    .. "; state=" .. tostring(self.character:getCurrentState())
                    .. "; hitReaction=" .. tostring(self.character:hasHitReaction())
                    .. "; ignoreMovement=" .. tostring(self.character:getIgnoreMovement())
                    .. "; performingAction="
                    .. tostring(self.character:getVariableString("PerformingAction"))
                    .. "; directionVar="
                    .. tostring(self.character:getVariableString(DIRECTION_VARIABLE))
                    .. "; variantVar="
                    .. tostring(self.character:getVariableString(VARIANT_VARIABLE))
            )
            self:forceComplete()
        end
        return
    end

    local elapsed = now - self.animationStartedAt
    local movementProgress = math.min(math.max(elapsed / self.movementDurationMs, 0), 1)
    local smoothProgress = movementProgress * movementProgress * (3 - 2 * movementProgress)
    local easedProgress = smoothProgress
        + (movementProgress - smoothProgress) * self.linearMovementBlend
    local targetDistance = self.dodgeDistance * easedProgress

    if not self.movementBlocked and targetDistance > self.distanceMoved then
        moveDistance(self, targetDistance - self.distanceMoved)
    end

    if self.reactionAnimation and now >= self.reactionAnimationEndsAt then
        debugLog("Reaction dodge completed: " .. self.direction .. "/" .. self.variant)
        self:forceComplete()
        return
    end

    -- Prevent a missing or rejected AnimNode from locking the player forever.
    if elapsed >= self.failsafeDurationMs then
        debugLog("Failsafe completion: " .. self.direction .. "/" .. self.variant)
        self:forceComplete()
    end
end

function ISParkourDodgeAction:animEvent(event, parameter)
    if event == "ParkourDodgeStarted" and not self.animationStarted then
        self.animationStarted = true
        self.animationStartedAt = getTimestampMs()
        debugLog("Animation confirmed: " .. self.direction .. "/" .. self.variant)
    elseif event == "ParkourDodgeDone" then
        self:forceComplete()
    end
end

function ISParkourDodgeAction:releaseControl()
    if self.controlReleased then
        return
    end
    self.controlReleased = true

    if self.reactionAnimation then
        -- Clearing the selector alone leaves the Java reaction state alive,
        -- allowing a queued Bite node to play after the dodge. Explicitly
        -- return to normal movement once our reaction dodge releases control.
        interruptReactionAttackers(self)
        debugLog(
            "Interrupted reaction attackers: "
                .. tostring(self.interruptedReactionAttackerCount)
        )
        -- Leave the Java state while the reaction node's conditions are still
        -- valid. Clearing direction/variant first gives the fallback vanilla
        -- HitReaction one animation update in which it can become active.
        leaveHitReactionState(self.character)
        beginReactionTailGuard(self)
        finishStaleReactionActionState(self.character)
    end
    self.character:clearVariable(DIRECTION_VARIABLE)
    self.character:clearVariable(VARIANT_VARIABLE)
    if self.ownsMovementLock then
        -- canStart() guarantees that IgnoreMovement was false before the
        -- dodge. If a hit reaction interrupted us, that state now owns the
        -- lock and will release it on exit; otherwise release our lock here.
        -- Falling after a roof-edge dodge does not own the lock that this
        -- action set in start(). Leaving it enabled permanently blocks input
        -- and preserves the last locomotion vector. Other forced reactions
        -- keep their own lock and release it through their normal state exit.
        if not isForcedPlayerState(self.character)
            or isFallingState(self.character) then
            self.character:setIgnoreMovement(false)
        end
        self.ownsMovementLock = false
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

function ISParkourDodgeAction:new(
    character,
    direction,
    travelX,
    travelY,
    facingX,
    facingY,
    variantProfile,
    escapeFromReaction,
    reactionAnimation
)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.direction = direction
    action.travelX = travelX
    action.travelY = travelY
    action.facingX = facingX
    action.facingY = facingY
    action.variant = variantProfile and variantProfile.id or "Default"
    action.dodgeDistance = variantProfile and variantProfile.distance or DEFAULT_DODGE_DISTANCE
    action.movementDurationMs = variantProfile and variantProfile.movementDurationMs
        or DEFAULT_MOVEMENT_DURATION_MS
    action.linearMovementBlend = variantProfile and variantProfile.linearMovementBlend or 0
    action.failsafeDurationMs = variantProfile and variantProfile.failsafeDurationMs
        or DEFAULT_FAILSAFE_DURATION_MS
    action.distanceMoved = 0
    action.movementBlocked = false
    action.isInvalid = false
    action.controlReleased = false
    action.ownsMovementLock = false
    action.animationStarted = false
    action.animationStartedAt = nil
    action.escapeFromReaction = escapeFromReaction == true
    action.reactionAnimation = reactionAnimation == true
    action.reactionAttackers = setmetatable({}, { __mode = "k" })
    action.interruptedReactionAttackers = setmetatable({}, { __mode = "k" })
    action.interruptedReactionAttackerCount = 0
    action.reactionAnimationLeadMs = 50
    action.reactionAnimationEndsAt = nil
    action.reactionAnimationDurationMs =
        variantProfile and variantProfile.reactionDurationMs
        or action.movementDurationMs
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.maxTime = action:getDuration()
    return action
end

return ISParkourDodgeAction
