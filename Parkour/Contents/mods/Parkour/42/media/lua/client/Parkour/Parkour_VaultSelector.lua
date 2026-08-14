local ParkourVaultSelector = {}

local VARIANT_VARIABLE = "ParkourVaultVariant"
local VANILLA_VARIANT = "Vanilla"

-- To add another animation later:
-- 1. Put its GLB into media/anims_X/Bob.
-- 2. Add its Sandbox option to media/sandbox-options.txt.
-- 3. Add one entry here.
-- 4. Add the matching conditioned AnimNode files. New vault variants should
--    inherit or declare Priority/ConditionPriority 20 so sex-specific vanilla
--    animation packs cannot win an otherwise equal AnimNode match.
local RUN_VARIANTS = {
    { id = "FrontFlip", sandboxKey = "EnableFrontFlip" },
    { id = "CorkscrewVault", sandboxKey = "EnableCorkscrewVault" },
    { id = "DashVault", sandboxKey = "EnableDashVault" },
    { id = "DiveRoll", sandboxKey = "EnableDiveRoll" },
}

local SPRINT_VARIANTS = {
    { id = "SpeedVault", sandboxKey = "EnableSpeedVault" },
    { id = "VaultOver", sandboxKey = "EnableVaultOver" },
}

local WALK_VARIANTS = {
    { id = "ReverseVault", sandboxKey = "EnableReverseVault" },
}

-- Each character owns a separate shuffled bag for walk, run, and sprint vaults.
-- Every enabled animation is played once before its bag is shuffled again.
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

local function buildEnabledVariants(variants)
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(variants) do
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

local function refillBag(character, poolName, enabled, signature)
    local values = {}
    for index = 1, #enabled do
        values[index] = enabled[index]
    end

    shuffle(values)

    -- table.remove() takes the final element. Move an immediate repeat away
    -- from that position whenever at least two variants are available.
    local characterLastVariants = lastVariantByCharacter[character]
    local lastVariant = characterLastVariants and characterLastVariants[poolName]
    if #values > 1 and values[#values] == lastVariant then
        values[1], values[#values] = values[#values], values[1]
    end

    local bag = {
        values = values,
        signature = signature,
    }
    local characterBags = bagsByCharacter[character]
    if not characterBags then
        characterBags = {}
        bagsByCharacter[character] = characterBags
    end
    characterBags[poolName] = bag
    return bag
end

local function chooseVariant(character, poolName, variants)
    local enabled = buildEnabledVariants(variants)
    if #enabled == 0 then
        return VANILLA_VARIANT
    end

    local signature = getPoolSignature(enabled)
    local characterBags = bagsByCharacter[character]
    local bag = characterBags and characterBags[poolName]
    if not bag or bag.signature ~= signature or #bag.values == 0 then
        bag = refillBag(character, poolName, enabled, signature)
    end

    local selected = table.remove(bag.values)
    local characterLastVariants = lastVariantByCharacter[character]
    if not characterLastVariants then
        characterLastVariants = {}
        lastVariantByCharacter[character] = characterLastVariants
    end
    characterLastVariants[poolName] = selected
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
        if character:getVariableBoolean("ParkourSprintWindowVault") then
            character:setVariable(VARIANT_VARIABLE, "WindowVault")
            debugLog("Selected sprint-window-vault variant")
            return
        end

        local outcome = character:getVariableString("ClimbFenceOutcome")

        if outcome == "success" and character:getVariableBoolean("VaultOverSprint") then
            local selected = chooseVariant(character, "sprint", SPRINT_VARIANTS)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog("Selected sprint-vault variant: " .. selected)
        elseif outcome == "success" and character:getVariableBoolean("VaultOverRun") then
            local selected = chooseVariant(character, "run", RUN_VARIANTS)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog("Selected running-vault variant: " .. selected)

            -- Keep the condition alive after ClimbOverFenceState exits so the
            -- selected AnimNode can finish blending out. The next vault always
            -- overwrites this value before its animation is selected.
        elseif outcome == "success"
            and not character:getVariableBoolean("VaultOverSprint")
            and not character:getVariableBoolean("VaultOverRun") then
            local selected = chooseVariant(character, "walk", WALK_VARIANTS)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog("Selected walking-vault variant: " .. selected)
        end
    end
end

Events.OnAIStateChange.Add(onAIStateChange)

return ParkourVaultSelector
