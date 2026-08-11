local ParkourDodgeSelector = {}

-- Each direction owns an independent shuffled bag. New animations only need
-- one profile here, one conditioned AnimNode, and one Sandbox option.
local VARIANTS_BY_DIRECTION = {
    Forward = {
        {
            id = "DiveRollForward",
            sandboxKey = "EnableDodgeDiveRollForward",
            movementDurationMs = 700,
            linearMovementBlend = 0,
            distance = 3,
            failsafeDurationMs = 2200,
        },
    },
    Backward = {
        {
            id = "CorkscrewEvadeBack",
            sandboxKey = "EnableDodgeCorkscrewEvadeBack",
            movementDurationMs = 1600,
            linearMovementBlend = 0.65,
            distance = 3,
            failsafeDurationMs = 2200,
        },
    },
    Left = {
        {
            id = "DiveRollLeft",
            sandboxKey = "EnableDodgeDiveRollLeft",
            movementDurationMs = 700,
            linearMovementBlend = 0,
            distance = 3,
            failsafeDurationMs = 2200,
        },
    },
    Right = {
        {
            id = "ButterflyDodgeRight",
            sandboxKey = "EnableDodgeButterflyRight",
            movementDurationMs = 1600,
            linearMovementBlend = 0.65,
            distance = 3,
            failsafeDurationMs = 2200,
        },
    },
}

local bagsByCharacter = {}
local lastVariantByCharacter = {}

local function getSettings()
    return SandboxVars and SandboxVars.Parkour or nil
end

local function isEnabled(settings, sandboxKey)
    -- Variants default to enabled for saves created before their option existed.
    return not sandboxKey or not settings or settings[sandboxKey] ~= false
end

local function buildEnabledVariants(direction)
    local variants = VARIANTS_BY_DIRECTION[direction] or {}
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(variants) do
        if isEnabled(settings, variant.sandboxKey) then
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
    local enabled = buildEnabledVariants(direction)
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
