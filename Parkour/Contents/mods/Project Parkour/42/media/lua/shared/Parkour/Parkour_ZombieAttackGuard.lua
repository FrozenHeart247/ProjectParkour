local ParkourZombieAttackGuard = {}

local DEFAULT_RADIUS = 3.5
local DEFAULT_TAIL_MS = 1500
local HIT_REACTION_ACTION_STATE = "hitreaction"
local ACTIVE_ANIM_FINISHING_EVENT = "ActiveAnimFinishing"

local tailByCharacter = setmetatable({}, { __mode = "k" })

local function isZombie(object)
    return object and instanceof(object, "IsoZombie")
end

local function hasEntries(values)
    if not values then
        return false
    end
    for _ in pairs(values) do
        return true
    end
    return false
end

local function isCurrentState(character, stateClass)
    return stateClass
        and stateClass.instance
        and character:getCurrentState() == stateClass.instance()
end

local function isEscapableReactionState(character)
    return character:hasHitReaction()
        or isCurrentState(character, PlayerHitReactionState)
        or isCurrentState(character, PlayerHitReactionPVPState)
        or isCurrentState(character, BumpedState)
        or isCurrentState(character, StaggerBackState)
end

local function isPendingZombieAttack(zombie, character)
    if not zombie or zombie:isDead() or zombie:getTarget() ~= character then
        return false
    end

    local outcome = zombie:getVariableString("AttackOutcome")
    return zombie:isAttacking()
        or outcome == "start"
        or outcome == "success"
end

local function trackAttacker(attackers, zombie)
    if not isZombie(zombie) or zombie:isDead() then
        return false
    end
    if attackers[zombie] then
        return false
    end

    attackers[zombie] = true
    return true
end

local function interruptZombie(zombie)
    zombie:setAttackOutcome("interrupted")
    zombie:setVariable("AttackOutcome", "interrupted")
    zombie:clearVariable("PlayerHitReaction")
    zombie:setVariable("ZombieBiteDone", true)
end

local function clearReactionPayload(character)
    character:setAttackedBy(nil)
    character:setHitForce(0)
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

local function visitNearbyZombies(character, radius, callback)
    local cell = getCell()
    if not cell then
        return
    end

    local tileRadius = math.ceil(radius)
    local centerX = math.floor(character:getX())
    local centerY = math.floor(character:getY())
    local centerZ = math.floor(character:getZ())
    local seen = setmetatable({}, { __mode = "k" })

    for x = centerX - tileRadius, centerX + tileRadius do
        for y = centerY - tileRadius, centerY + tileRadius do
            local square = cell:getGridSquare(x, y, centerZ)
            local movingObjects = square and square:getMovingObjects()
            if movingObjects then
                for index = 0, movingObjects:size() - 1 do
                    local object = movingObjects:get(index)
                    if isZombie(object) and not seen[object] then
                        seen[object] = true
                        if object:DistTo(character) <= radius then
                            callback(object)
                        end
                    end
                end
            end
        end
    end
end

function ParkourZombieAttackGuard.newAttackerSet()
    return setmetatable({}, { __mode = "k" })
end

function ParkourZombieAttackGuard.interruptNearby(character, attackers, radius)
    if not character or character:isDead() then
        return 0
    end

    attackers = attackers or ParkourZombieAttackGuard.newAttackerSet()
    radius = radius or DEFAULT_RADIUS
    local newlyTracked = 0
    local attackedBy = character:getAttackedBy()

    if isZombie(attackedBy) then
        if trackAttacker(attackers, attackedBy) then
            newlyTracked = newlyTracked + 1
        end
    end

    visitNearbyZombies(character, radius, function(zombie)
        if isPendingZombieAttack(zombie, character)
            and trackAttacker(attackers, zombie) then
            newlyTracked = newlyTracked + 1
        end
    end)

    for zombie in pairs(attackers) do
        if not zombie or zombie:isDead() then
            attackers[zombie] = nil
        elseif zombie:getTarget() == character or character:getAttackedBy() == zombie then
            interruptZombie(zombie)
        else
            -- Do not prevent a zombie from legitimately switching to another target.
            attackers[zombie] = nil
        end
    end

    attackedBy = character:getAttackedBy()
    if attackedBy and attackers[attackedBy] then
        clearReactionPayload(character)
        character:setHitReaction("")
    end

    return newlyTracked
end

function ParkourZombieAttackGuard.beginTailGuard(character, attackers, durationMs)
    if not character or not hasEntries(attackers) then
        return false
    end

    tailByCharacter[character] = {
        attackers = attackers,
        expiresAt = getTimestampMs() + (durationMs or DEFAULT_TAIL_MS),
    }
    return true
end

function ParkourZombieAttackGuard.updateTailGuard(character)
    local guard = character and tailByCharacter[character]
    if not guard then
        return false
    end

    if getTimestampMs() > guard.expiresAt
        or character:isDead()
        or character:getVehicle() then
        tailByCharacter[character] = nil
        return false
    end

    local attackedBy = character:getAttackedBy()
    local attackerWasInterrupted = attackedBy
        and guard.attackers[attackedBy] == true
    local attackerOutcome = attackedBy
        and attackedBy:getVariableString("AttackOutcome") or ""
    local attackerBiteDone = attackedBy
        and attackedBy:getVariableBoolean("ZombieBiteDone") or false
    local staleInterruptedReaction = attackedBy == nil
        or (attackerWasInterrupted
            and (attackerOutcome == "interrupted" or attackerBiteDone))

    if staleInterruptedReaction and isEscapableReactionState(character) then
        clearReactionPayload(character)
        character:setHitReaction("")
        if PlayerMovementState and PlayerMovementState.instance then
            character:changeState(PlayerMovementState.instance())
        end
        character:setIgnoreMovement(false)
        tailByCharacter[character] = nil
        return true
    end

    if character:getActionStateName() == HIT_REACTION_ACTION_STATE
        and isCurrentState(character, PlayerMovementState)
        and not character:hasHitReaction()
        and character:getAttackedBy() == nil then
        character:reportEvent(ACTIVE_ANIM_FINISHING_EVENT)
    end

    return false
end

function ParkourZombieAttackGuard.updateAllTailGuards()
    for character in pairs(tailByCharacter) do
        ParkourZombieAttackGuard.updateTailGuard(character)
    end
end

return ParkourZombieAttackGuard
