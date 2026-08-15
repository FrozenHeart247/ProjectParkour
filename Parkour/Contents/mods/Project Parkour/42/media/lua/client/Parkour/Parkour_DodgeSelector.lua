local ParkourDodgeSelector = {}
local Progression = require "Parkour/Parkour_Progression"

-- Each direction owns an independent shuffled bag. New animations only need
-- one profile here, one conditioned AnimNode, and one Sandbox option.
local VARIANTS_BY_DIRECTION = {
    Forward = {
        {
            id = "ForwardRollDodge", --DefaultRoll
            feature = "ForwardRollDodge",
            sandboxKey = "EnableDodgeForwardRollForward",
            movementDurationMs = 980, --1150
            -- 1.20 s clip / 1.35 speed, released before ActiveAnimFinished.
            reactionDurationMs = 820,
            linearMovementBlend = 0.65,
            distance = 5,
            failsafeDurationMs = 2200,
        },
        {
            id = "CombatRollForward", --SpinRoll
            feature = "CombatRollForward",
            sandboxKey = "EnableDodgeCombatRollForward",
            movementDurationMs = 1300,--1500
            -- 2.10 s clip / 1.30 speed. The release stays just ahead of
            -- ActiveAnimFinished so the hit-reaction branch cannot fall back.
            reactionDurationMs = 1480,--1480
            linearMovementBlend = 0.65,
            distance = 5,
            failsafeDurationMs = 2600,
        },
        {
            id = "LowDiveDodgeForward",
            feature = "LowDiveDodgeForward",
            sandboxKey = "EnableDodgeLowDiveForward",
            movementDurationMs = 1250,
            -- 1.57 s clip / 1.20 speed.
            reactionDurationMs = 1200,
            linearMovementBlend = 0.65,
            distance = 5,
            failsafeDurationMs = 2200,
        },
    },
    Backward = {
        {
            id = "CorkscrewEvadeBack",
            feature = "CorkscrewEvadeBack",
            sandboxKey = "EnableDodgeCorkscrewEvadeBack",
            movementDurationMs = 1600,
            -- 2.533 s clip / 1.50 speed.
            reactionDurationMs = 1550,
            linearMovementBlend = 0.65,
            distance = 4,
            failsafeDurationMs = 2200,
        },
        {
            id = "BackflipDodge",
            feature = "BackflipDodge",
            sandboxKey = "EnableDodgeBackflipBack",
            movementDurationMs = 1600,
            -- 2.20 s clip / 1.30 speed.
            reactionDurationMs = 1550,
            linearMovementBlend = 0.65,
            distance = 4,
            failsafeDurationMs = 2400,
        },
    },
    Left = {
        {
            id = "SideFlipDodgeLeft",
            feature = "SideFlipDodgeLeft",
            sandboxKey = "EnableDodgeSideFlipLeft",
            movementDurationMs = 1600,
            -- 2.60 s clip / 1.30 speed.
            reactionDurationMs = 1840,
            linearMovementBlend = 0.65,
            distance = 4,
            failsafeDurationMs = 2200,
        },
    },
    Right = {
        {
            id = "ButterflyDodgeRight",
            feature = "ButterflyDodgeRight",
            sandboxKey = "EnableDodgeButterflyRight",
            movementDurationMs = 1600,
            -- 2.70 s clip / 1.50 speed.
            reactionDurationMs = 1660,
            linearMovementBlend = 0.65,
            distance = 4,
            failsafeDurationMs = 2200,
        },
    },
}

local bagsByCharacter = setmetatable({}, { __mode = "k" })
local lastVariantByCharacter = setmetatable({}, { __mode = "k" })

local function getSettings()
    return SandboxVars and SandboxVars.Parkour or nil
end

local function isEnabled(settings, sandboxKey)
    -- Variants default to enabled for saves created before their option existed.
    return not sandboxKey or not settings or settings[sandboxKey] ~= false
end

local function buildEnabledVariants(character, direction)
    local variants = VARIANTS_BY_DIRECTION[direction] or {}
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(variants) do
        -- DodgeInput performs the common live restrictions once before an
        -- action starts.  The selector is responsible only for which variants
        -- the current Parkour level has unlocked; re-running canUse() here can
        -- otherwise turn a valid request into an unexplained empty pool.
        if isEnabled(settings, variant.sandboxKey)
            and Progression.isUnlocked(character, variant.feature) then
            enabled[#enabled + 1] = variant
        end
    end

    return enabled
end

local function getPoolSignature(enabled)
    local ids = {}
    for index, variant in ipairs(enabled) do
        ids[index] = variant.id
    end
    return table.concat(ids, "|")
end

local function shuffle(values)
    for index = #values, 2, -1 do
        local otherIndex = ZombRand(index) + 1
        values[index], values[otherIndex] = values[otherIndex], values[index]
    end
end

local function refillBag(character, direction, enabled, signature)
    local values = {}
    for index, variant in ipairs(enabled) do
        values[index] = variant
    end
    shuffle(values)

    local characterLastVariants = lastVariantByCharacter[character]
    local lastVariant = characterLastVariants and characterLastVariants[direction]
    if #values > 1 and values[#values].id == lastVariant then
        values[1], values[#values] = values[#values], values[1]
    end

    local characterBags = bagsByCharacter[character]
    if not characterBags then
        characterBags = {}
        bagsByCharacter[character] = characterBags
    end

    local bag = {
        values = values,
        signature = signature,
    }
    characterBags[direction] = bag
    return bag
end

function ParkourDodgeSelector.choose(character, direction)
    local enabled = buildEnabledVariants(character, direction)
    if #enabled == 0 then
        return nil
    end

    local signature = getPoolSignature(enabled)
    local characterBags = bagsByCharacter[character]
    local bag = characterBags and characterBags[direction]
    if not bag or bag.signature ~= signature or #bag.values == 0 then
        bag = refillBag(character, direction, enabled, signature)
    end

    local selected = table.remove(bag.values)
    local characterLastVariants = lastVariantByCharacter[character]
    if not characterLastVariants then
        characterLastVariants = {}
        lastVariantByCharacter[character] = characterLastVariants
    end
    characterLastVariants[direction] = selected.id
    return selected
end

return ParkourDodgeSelector
