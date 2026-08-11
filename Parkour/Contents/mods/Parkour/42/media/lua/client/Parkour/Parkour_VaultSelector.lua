local ParkourVaultSelector = {}

local VARIANT_VARIABLE = "ParkourVaultVariant"
local VANILLA_VARIANT = "Vanilla"

-- To add another animation later:
-- 1. Put its GLB into media/anims_X/Bob.
-- 2. Add its Sandbox option to media/sandbox-options.txt.
-- 3. Add one entry here.
-- 4. Add the matching conditioned AnimNode files.
local VARIANTS = {
    { id = "FrontFlip", sandboxKey = "EnableFrontFlip" },
    { id = "CorkscrewVault", sandboxKey = "EnableCorkscrewVault" },
    { id = "DashVault", sandboxKey = "EnableDashVault" },
}

-- Each character owns a shuffled bag. Every enabled animation is played once
-- before the bag is filled and shuffled again.
local bagsByCharacter = {}
local lastVariantByCharacter = {}

local function getSettings()
    if not SandboxVars then
        return nil
    end
    return SandboxVars.Parkour
end

local function isEnabled(settings, sandboxKey)
    -- Defaults remain enabled if a save made before these options is loaded.
    return not settings or settings[sandboxKey] ~= false
end

local function buildEnabledVariants()
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(VARIANTS) do
        if isEnabled(settings, variant.sandboxKey) then
            enabled[#enabled + 1] = variant.id
        end
    end

    return enabled
end

local function getPoolSignature(enabled)
    return table.concat(enabled, "|")
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

    -- table.remove() takes the final element. Move an immediate repeat away
    -- from that position whenever at least two variants are available.
    local lastVariant = lastVariantByCharacter[character]
    if #values > 1 and values[#values] == lastVariant then
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

    local signature = getPoolSignature(enabled)
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

    local climbState = ClimbOverFenceState.instance()
    if currentState == climbState then
        local isRunningVault = character:getVariableBoolean("VaultOverRun")
        local outcome = character:getVariableString("ClimbFenceOutcome")

        if isRunningVault and outcome == "success" then
            local selected = chooseVariant(character)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog("Selected running-vault variant: " .. selected)

            -- Keep the condition alive after ClimbOverFenceState exits so the
            -- selected AnimNode can finish blending out. The next vault always
            -- overwrites this value before its animation is selected.
        end
    end
end

Events.OnAIStateChange.Add(onAIStateChange)

return ParkourVaultSelector
