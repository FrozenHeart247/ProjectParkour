local ParkourHighFenceSelector = {}
local Progression = require "Parkour/Parkour_Progression"
local AnimationSync = require "Parkour/Parkour_AnimationSync"

local VARIANT_VARIABLE = "ParkourHighFenceVariant"
local VANILLA_VARIANT = "Vanilla"

-- Add future successful high-fence animations here. Each character receives
-- an independent shuffled bag, so every enabled clip plays once per cycle.
local HIGH_FENCE_VARIANTS = {
    { id = "HighFenceFrontFlip", sandboxKey = "EnableHighFenceFrontFlip", feature = "HighFenceFrontFlip" },
    { id = "HighFenceVault02", sandboxKey = "EnableHighFenceVault02", feature = "HighFenceVault02" },
}

local bagsByCharacter = setmetatable({}, { __mode = "k" })
local lastVariantByCharacter = setmetatable({}, { __mode = "k" })

local function getSettings()
    return SandboxVars and SandboxVars.Parkour or nil
end

local function isEnabled(settings, sandboxKey)
    -- New options remain enabled in saves created before the option existed.
    return not settings or settings[sandboxKey] ~= false
end

local function buildEnabledVariants(character)
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(HIGH_FENCE_VARIANTS) do
        -- This selector replaces only the clip of a vanilla traversal.  Live
        -- physical restrictions cannot cancel that traversal and therefore
        -- must not make an unlocked animation disappear from its pool.
        if isEnabled(settings, variant.sandboxKey)
            and Progression.isUnlocked(character, variant.feature) then
            enabled[#enabled + 1] = variant.id
        end
    end

    return enabled
end

local function shuffle(values)
    for index = #values, 2, -1 do
        local otherIndex = ZombRand(index) + 1
        values[index], values[otherIndex] = values[otherIndex], values[index]
    end
end

local function refillBag(character, enabled, signature)
    local values = {}
    for index = 1, #enabled do
        values[index] = enabled[index]
    end

    shuffle(values)

    if #values > 1 and values[#values] == lastVariantByCharacter[character] then
        values[1], values[#values] = values[#values], values[1]
    end

    local bag = {
        values = values,
        signature = signature,
    }
    bagsByCharacter[character] = bag
    return bag
end

local function chooseVariant(character)
    local enabled = buildEnabledVariants(character)
    if #enabled == 0 then
        return VANILLA_VARIANT
    end

    local signature = table.concat(enabled, "|")
    local bag = bagsByCharacter[character]
    if not bag or bag.signature ~= signature or #bag.values == 0 then
        bag = refillBag(character, enabled, signature)
    end

    local selected = table.remove(bag.values)
    lastVariantByCharacter[character] = selected
    return selected
end

local function debugLog(message)
    local settings = getSettings()
    if settings and settings.DebugLogging then
        print("[Parkour] " .. message)
    end
end

local function onAIStateChange(character, currentState, previousState)
    if not instanceof(character, "IsoPlayer") or not character:isLocalPlayer() then
        return
    end

    if currentState ~= ClimbOverWallState.instance() then
        return
    end

    -- Select on state entry, before the first climbwall AnimNode is resolved.
    -- Failed and struggle outcomes ignore this variable and remain vanilla.
    local selected = chooseVariant(character)
    AnimationSync.setVariable(character, VARIANT_VARIABLE, selected)
    debugLog(string.format(
        "Selected high-fence variant: %s (Parkour level %d)",
        selected,
        Progression.getLevel(character)
    ))
end

Events.OnAIStateChange.Add(onAIStateChange)

return ParkourHighFenceSelector
