local ParkourHighFenceSelector = {}

local VARIANT_VARIABLE = "ParkourHighFenceVariant"
local VANILLA_VARIANT = "Vanilla"

-- Add future successful high-fence animations here. Each character receives
-- an independent shuffled bag, so every enabled clip plays once per cycle.
local HIGH_FENCE_VARIANTS = {
    { id = "HighFenceFrontFlip", sandboxKey = "EnableHighFenceFrontFlip" },
    { id = "HighFenceVault02", sandboxKey = "EnableHighFenceVault02" },
}

local bagsByCharacter = {}
local lastVariantByCharacter = {}

local function getSettings()
    return SandboxVars and SandboxVars.Parkour or nil
end

local function isEnabled(settings, sandboxKey)
    -- New options remain enabled in saves created before the option existed.
    return not settings or settings[sandboxKey] ~= false
end

local function buildEnabledVariants()
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(HIGH_FENCE_VARIANTS) do
        if isEnabled(settings, variant.sandboxKey) then
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
    local enabled = buildEnabledVariants()
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
    if not instanceof(character, "IsoPlayer") then
        return
    end

    if currentState ~= ClimbOverWallState.instance() then
        return
    end

    -- Select on state entry, before the first climbwall AnimNode is resolved.
    -- Failed and struggle outcomes ignore this variable and remain vanilla.
    local selected = chooseVariant(character)
    character:setVariable(VARIANT_VARIABLE, selected)
    debugLog("Selected high-fence variant: " .. selected)
end

Events.OnAIStateChange.Add(onAIStateChange)

return ParkourHighFenceSelector
