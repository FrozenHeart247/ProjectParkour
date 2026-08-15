local Definitions = require "Parkour/Parkour_ProgressionDefinitions"

local Progression = {}
local antiFarmByCharacter = setmetatable({}, { __mode = "k" })
local ANTI_FARM_COOLDOWN_MS = 30000
local ANTI_FARM_RESET_DISTANCE_SQ = 20 * 20
local ANTI_FARM_MAX_ENTRIES = 64
local SPRINT_XP_DISTANCE_THRESHOLD = 30
local SPRINT_XP_REWARD = 5
local SPRINT_XP_MAX_SAMPLE_DISTANCE = 4
local sprintXPByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local values = SandboxVars and SandboxVars.Parkour
    if values and values.DebugLogging then
        print("[Parkour Progression] " .. message)
    end
end

local TORSO_PARTS = {
    [BodyPartType.Torso_Upper] = true, [BodyPartType.Torso_Lower] = true,
    [BodyPartType.Groin] = true,
}
local LEG_PARTS = {
    [BodyPartType.UpperLeg_L] = true, [BodyPartType.UpperLeg_R] = true,
    [BodyPartType.LowerLeg_L] = true, [BodyPartType.LowerLeg_R] = true,
    [BodyPartType.Foot_L] = true, [BodyPartType.Foot_R] = true,
}
local ARM_PARTS = {
    [BodyPartType.UpperArm_L] = true, [BodyPartType.UpperArm_R] = true,
    [BodyPartType.ForeArm_L] = true, [BodyPartType.ForeArm_R] = true,
    [BodyPartType.Hand_L] = true, [BodyPartType.Hand_R] = true,
}

local function settings()
    return SandboxVars and SandboxVars.Parkour or nil
end

local function optionNumber(name, fallback)
    local values = settings()
    local value = values and tonumber(values[name])
    if value == nil then
        return fallback
    end
    return value
end

function Progression.isEnabled()
    local values = settings()
    return not values or values.EnableProgression ~= false
end

function Progression.isUnlockAllEnabled()
    local values = settings()
    return values and values.UnlockAllParkour == true
end

function Progression.getPerk()
    return Perks and Perks.Parkour or nil
end

function Progression.getLevel(character)
    local perk = Progression.getPerk()
    if not character or not perk then
        return 0
    end
    return character:getPerkLevel(perk)
end

function Progression.getRequiredLevel(featureId)
    local definition = Definitions.get(featureId)
    if not definition then
        return nil
    end
    if featureId == "WallRunUp" then
        local values = settings()
        if values and values.UnlockWallRunAtLevel5 == true then
            return 5
        end
        return math.max(0, math.min(10, math.floor(
            optionNumber("WallRunUnlockLevel", definition.level)
        )))
    end
    return definition.level
end

function Progression.isUnlocked(character, featureId)
    local requiredLevel = Progression.getRequiredLevel(featureId)
    if requiredLevel == nil then
        return false
    end
    if not Progression.isEnabled() or Progression.isUnlockAllEnabled() then
        return true
    end
    return Progression.getLevel(character) >= requiredLevel
end

function Progression.getEndurance(character)
    local stats = character and character:getStats()
    if not stats then
        return 0
    end
    return stats:get(CharacterStat.ENDURANCE)
end

function Progression.getMinimumEndurance(featureId)
    local definition = Definitions.get(featureId)
    local base = definition and definition.endurance or 0
    return math.max(0, math.min(1, base * optionNumber("MinimumEnduranceMultiplier", 1.0)))
end

local function masteryCostMultiplier(level)
    if level >= 10 then return 0.75 end
    if level == 9 then return 0.80 end
    if level == 8 then return 0.85 end
    if level == 7 then return 0.90 end
    if level == 6 then return 0.95 end
    return 1.00
end

function Progression.getEnduranceCost(character, featureId)
    local values = settings()
    if values and values.EnableEnduranceCosts == false then
        return 0
    end
    local definition = Definitions.get(featureId)
    if not definition or not definition.cost then
        return 0
    end

    local level = Progression.getLevel(character)
    local cost = definition.cost
    if featureId == "WallRunUp" then
        if level >= 10 then
            cost = 0.10
        elseif level >= 9 then
            cost = 0.12
        else
            cost = 0.14
        end
    elseif definition.costProfile == "dodge" then
        local startCost = optionNumber("DodgeCostLevel3", 10) / 100
        local endCost = optionNumber("DodgeCostLevel10", 6) / 100
        local mastery = math.max(0, math.min(1, (level - 3) / 7))
        cost = startCost + (endCost - startCost) * mastery
    else
        cost = cost * masteryCostMultiplier(level)
    end
    return math.max(0, cost * optionNumber("ActionCostMultiplier", 1.0))
end

function Progression.spendEndurance(character, featureId)
    local cost = Progression.getEnduranceCost(character, featureId)
    if cost <= 0 or not character then
        return 0
    end
    local stats = character:getStats()
    local current = stats:get(CharacterStat.ENDURANCE)
    stats:set(CharacterStat.ENDURANCE, math.max(0, current - cost))
    return cost
end

local function hasRelevantSeriousInjury(character, mode, featureId)
    if mode <= 1 then
        return false
    end
    local bodyDamage = character and character:getBodyDamage()
    local bodyParts = bodyDamage and bodyDamage:getBodyParts()
    if not bodyParts then
        return false
    end

    local definition = Definitions.get(featureId)
    local injuryGroup = definition and definition.injuryGroup
    if not injuryGroup then
        return false
    end

    for index = 0, bodyParts:size() - 1 do
        local bodyPart = bodyParts:get(index)
        local bodyPartType = bodyPart:getType()
        local relevant = mode >= 3
            or TORSO_PARTS[bodyPartType] == true
            or LEG_PARTS[bodyPartType] == true
            or (injuryGroup == "climb" and ARM_PARTS[bodyPartType] == true)
        if relevant and (bodyPart:isDeepWounded() or bodyPart:getFractureTime() > 0) then
            return true
        end
    end
    return false
end

local function hasEquippedBackpack(character)
    local wornItems = character and character:getWornItems()
    if not wornItems then
        return false
    end
    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index)
        local item = wornItem and wornItem:getItem()
        if item
            and wornItem:getLocation() == ItemBodyLocation.BACK
            and instanceof(item, "InventoryContainer") then
            return true
        end
    end
    return false
end

local function isLoadAllowed(character, level, mode)
    if mode <= 1 then
        return true
    end
    local checkBackpack = mode == 2 or mode == 4
    local checkWeight = mode == 3 or mode == 4
    if checkBackpack and level < 2 and hasEquippedBackpack(character) then
        return false
    end
    if checkWeight then
        local maxWeight = math.max(1, character:getMaxWeight())
        -- Normal carried weight must never suppress an unlocked move.  Only
        -- the game's actual overloaded state is restrictive; 9.9/10, for
        -- example, remains valid while anything above 10 is blocked.
        return character:getInventoryWeight() <= maxWeight
    end
    return true
end

function Progression.isOverloaded(character)
    if not character then
        return false
    end
    local maxWeight = math.max(1, character:getMaxWeight())
    return character:getInventoryWeight() > maxWeight
end

function Progression.canUse(character, featureId)
    -- Collision callbacks may pass non-player moving objects through callers
    -- before they have been filtered.  Never invoke IsoPlayer-only methods on
    -- those objects.
    if not character or not instanceof(character, "IsoPlayer") then
        return false, "character"
    end
    if character:isDead() then
        return false, "character"
    end
    if not Progression.isUnlocked(character, featureId) then
        return false, "level"
    end
    -- Actual overloading is a hard rule for every mod-owned mechanic.  It is
    -- intentionally independent of the optional backpack/load Sandbox mode
    -- and is therefore enforced by the same shared check on client and server.
    if Progression.isOverloaded(character) then
        return false, "load"
    end
    if Progression.getEndurance(character) < Progression.getMinimumEndurance(featureId) then
        return false, "endurance"
    end

    local level = Progression.getLevel(character)
    if not isLoadAllowed(character, level, optionNumber("LoadRestrictionMode", 4)) then
        return false, "load"
    end
    if hasRelevantSeriousInjury(character, optionNumber("InjuryRestrictionMode", 2), featureId) then
        return false, "injury"
    end
    return true
end

function Progression.getFreeJumpFeature(distance, isDrop)
    return Definitions.getFreeJumpFeature(distance, isDrop)
end

function Progression.getMaximumFreeJumpDistance(character)
    if not Progression.isEnabled() or Progression.isUnlockAllEnabled() then
        return 4
    end
    local level = Progression.getLevel(character)
    if level >= 2 then
        return 4
    end
    return 0
end

function Progression.getFailureTextKey(reason)
    local keys = {
        level = "UI_Parkour_Progression_Locked",
        endurance = "UI_Parkour_Progression_Endurance",
        load = "UI_Parkour_Progression_Load",
        injury = "UI_Parkour_Progression_Injury",
    }
    return keys[reason] or "UI_Parkour_Progression_Invalid"
end

local function trimAntiFarmEntries(entries)
    local count = 0
    local oldestSignature
    local oldestAt
    for signature, entry in pairs(entries) do
        count = count + 1
        if oldestAt == nil or entry.lastAt < oldestAt then
            oldestAt = entry.lastAt
            oldestSignature = signature
        end
    end
    if count > ANTI_FARM_MAX_ENTRIES and oldestSignature then
        entries[oldestSignature] = nil
    end
end

function Progression.makeObstacleSignature(actionId, x1, y1, z1, x2, y2, z2)
    local obstacleType = tostring(actionId or "Parkour")
    if string.sub(obstacleType, 1, 5) == "Fence" then
        obstacleType = "Fence"
    elseif obstacleType == "WindowVault" or obstacleType == "SprintWindowVault" then
        obstacleType = "Window"
    end

    local endpointA = string.format(
        "%d:%d:%d",
        math.floor(tonumber(x1) or 0),
        math.floor(tonumber(y1) or 0),
        math.floor(tonumber(z1) or 0)
    )
    local endpointB = string.format(
        "%d:%d:%d",
        math.floor(tonumber(x2) or 0),
        math.floor(tonumber(y2) or 0),
        math.floor(tonumber(z2) or 0)
    )
    if endpointB < endpointA then
        endpointA, endpointB = endpointB, endpointA
    end
    return obstacleType .. ":" .. endpointA .. ">" .. endpointB
end

function Progression.updateAntiFarmMovement(character)
    local entries = character and antiFarmByCharacter[character]
    if not entries then
        return
    end
    local x = character:getX()
    local y = character:getY()
    for _, entry in pairs(entries) do
        if not entry.leftRadius then
            local dx = x - entry.originX
            local dy = y - entry.originY
            if dx * dx + dy * dy >= ANTI_FARM_RESET_DISTANCE_SQ then
                entry.leftRadius = true
            end
        end
    end
end

local function getAntiFarmMultiplier(character, signature, now, originX, originY, cooldownMs)
    local values = settings()
    if not signature or (values and values.EnableAntiFarm == false) then
        return 1
    end
    local characterEntries = antiFarmByCharacter[character]
    if not characterEntries then
        characterEntries = {}
        antiFarmByCharacter[character] = characterEntries
    end
    local entry = characterEntries[signature]
    if not entry then
        characterEntries[signature] = {
            lastAt = now,
            originX = tonumber(originX) or character:getX(),
            originY = tonumber(originY) or character:getY(),
            leftRadius = false,
        }
        trimAntiFarmEntries(characterEntries)
        return 1
    end

    local requiredCooldown = math.max(
        0,
        tonumber(cooldownMs) or ANTI_FARM_COOLDOWN_MS
    )
    if now - entry.lastAt >= requiredCooldown and entry.leftRadius then
        entry.lastAt = now
        entry.originX = tonumber(originX) or character:getX()
        entry.originY = tonumber(originY) or character:getY()
        entry.leftRadius = false
        return 1
    end
    return 0
end

-- Call only from the authoritative server, or from single-player. The B42
-- addXp() helper deliberately does nothing on an MP client and performs the
-- normal server sync when invoked server-side.
function Progression.awardXP(character, baseAmount, signature, originX, originY, cooldownMs)
    if not Progression.isEnabled() then
        return 0
    end
    local perk = Progression.getPerk()
    if not character or not perk or character:getPerkLevel(perk) >= 10 then
        return 0
    end
    local amount = math.max(0, tonumber(baseAmount) or 0)
    local configuredMultiplier = optionNumber("XPMultiplier", 1.0)
    local antiFarmMultiplier = getAntiFarmMultiplier(
        character,
        signature,
        getTimestampMs(),
        originX,
        originY,
        cooldownMs
    )
    amount = amount * configuredMultiplier * antiFarmMultiplier
    if amount <= 0 then
        debugLog(string.format(
            "XP suppressed: base=%.3f multiplier=%.3f antiFarm=%.1f level=%d",
            tonumber(baseAmount) or 0,
            configuredMultiplier,
            antiFarmMultiplier,
            Progression.getLevel(character)
        ))
        return 0
    end

    local intendedAmount = amount
    -- Custom skills without a profession/trait boost are reduced to 25% by
    -- the vanilla XP path. Compensate only for that exact unboosted case.
    if character:getXp():getPerkBoost(perk) == 0 then
        amount = amount * 4
    end
    local beforeXP = character:getXp():getXP(perk)
    addXp(character, perk, amount)
    debugLog(string.format(
        "XP awarded: intended=%.3f total=%.3f->%.3f level=%d",
        intendedAmount,
        beforeXP,
        character:getXp():getXP(perk),
        Progression.getLevel(character)
    ))
    return intendedAmount
end

-- Sprint XP is based on actual distance rather than time spent holding the
-- sprint key. In MP this function is called only by the authoritative server.
-- Teleport-sized deltas are discarded so parkour actions and corrections do
-- not accidentally count as sprinting distance.
function Progression.updateSprintXP(character)
    if not character then
        return 0
    end
    if character:isDead() or character:getVehicle() then
        sprintXPByCharacter[character] = nil
        return 0
    end

    if not Progression.isEnabled() or Progression.getLevel(character) >= 10 then
        sprintXPByCharacter[character] = nil
        return 0
    end

    local x = character:getX()
    local y = character:getY()
    local z = math.floor(character:getZ())
    local sprinting = character:isSprinting() == true
    local state = sprintXPByCharacter[character]
    if not state then
        sprintXPByCharacter[character] = {
            lastX = x,
            lastY = y,
            lastZ = z,
            wasSprinting = sprinting,
            distance = 0,
        }
        return 0
    end

    local dx = x - state.lastX
    local dy = y - state.lastY
    local distance = math.sqrt(dx * dx + dy * dy)
    if sprinting and state.wasSprinting and z == state.lastZ
        and distance > 0.001
        and distance <= SPRINT_XP_MAX_SAMPLE_DISTANCE then
        state.distance = state.distance + distance
    end

    state.lastX = x
    state.lastY = y
    state.lastZ = z
    state.wasSprinting = sprinting

    if state.distance < SPRINT_XP_DISTANCE_THRESHOLD then
        return 0
    end

    state.distance = state.distance - SPRINT_XP_DISTANCE_THRESHOLD
    local awarded = Progression.awardXP(character, SPRINT_XP_REWARD, nil, x, y)
    if awarded > 0 then
        debugLog(string.format(
            "Sprint XP: award=%.3f distanceRemainder=%.3f level=%d",
            awarded,
            state.distance,
            Progression.getLevel(character)
        ))
    end
    return awarded
end

function Progression.setLevelAuthoritative(character, targetLevel)
    local perk = Progression.getPerk()
    if not character or not perk then
        return false
    end
    local level = math.max(0, math.min(10, math.floor(tonumber(targetLevel) or 0)))
    local targetXP = perk:getTotalXpForLevel(level)
    local currentXP = character:getXp():getXP(perk)
    addXpNoMultiplier(character, perk, targetXP - currentXP)
    return true
end

function Progression.showFailure(character, reason)
    if character and HaloTextHelper and HaloTextHelper.addBadText then
        local key = Progression.getFailureTextKey(reason)
        if getTextOrNull and getTextOrNull(key) == nil then
            key = "UI_Parkour_Progression_Invalid"
        end
        HaloTextHelper.addBadText(character, getText(key))
    end
end

return Progression
