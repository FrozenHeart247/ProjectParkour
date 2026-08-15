local ParkourVaultSelector = {}
local Progression = require "Parkour/Parkour_Progression"

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
    { id = "FrontFlip", sandboxKey = "EnableFrontFlip", feature = "FrontFlip" },
    { id = "CorkscrewVault", sandboxKey = "EnableCorkscrewVault", feature = "CorkscrewVault" },
    { id = "DashVault", sandboxKey = "EnableDashVault", feature = "DashVault" },
    { id = "DiveRoll", sandboxKey = "EnableDiveRoll", feature = "DiveRoll" },
    { id = "BackflipVault", sandboxKey = "EnableBackflipVault", feature = "BackflipVault" },
}

local SPRINT_VARIANTS = {
    { id = "SpeedVault", sandboxKey = "EnableSpeedVault", feature = "SpeedVault" },
    { id = "VaultOver", sandboxKey = "EnableVaultOver", feature = "VaultOver" },
}

local WALK_VARIANTS = {
    { id = "ReverseVault", sandboxKey = "EnableReverseVault", feature = "ReverseVault" },
}

-- Each character owns a separate shuffled bag for walk, run, and sprint vaults.
-- Every enabled animation is played once before its bag is shuffled again.
local bagsByCharacter = setmetatable({}, { __mode = "k" })
local lastVariantByCharacter = setmetatable({}, { __mode = "k" })

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

local function buildEnabledVariants(character, variants)
    local settings = getSettings()
    local enabled = {}

    for _, variant in ipairs(variants) do
        -- A vanilla fence traversal is going to happen regardless of the
        -- selected visual clip.  Applying live endurance/load/injury gates
        -- here only makes an already-unlocked animation silently fall back to
        -- vanilla; it does not prevent the traversal itself.  Keep animation
        -- pools level-gated and reserve canUse() for mechanics that the mod
        -- actually owns (dodge, free jump, wall run, sprint-window vault).
        if isEnabled(settings, variant.sandboxKey)
            and Progression.isUnlocked(character, variant.feature) then
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
    local enabled = buildEnabledVariants(character, variants)
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
            debugLog(string.format(
                "Selected sprint-vault variant: %s (Parkour level %d)",
                selected,
                Progression.getLevel(character)
            ))
        elseif outcome == "success" and character:getVariableBoolean("VaultOverRun") then
            local selected = chooseVariant(character, "run", RUN_VARIANTS)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog(string.format(
                "Selected running-vault variant: %s (Parkour level %d)",
                selected,
                Progression.getLevel(character)
            ))

            -- Keep the condition alive after ClimbOverFenceState exits so the
            -- selected AnimNode can finish blending out. The next vault always
            -- overwrites this value before its animation is selected.
        elseif outcome == "success"
            and not character:getVariableBoolean("VaultOverSprint")
            and not character:getVariableBoolean("VaultOverRun") then
            local selected = chooseVariant(character, "walk", WALK_VARIANTS)
            character:setVariable(VARIANT_VARIABLE, selected)
            debugLog(string.format(
                "Selected walking-vault variant: %s (Parkour level %d)",
                selected,
                Progression.getLevel(character)
            ))
        end
    end
end

Events.OnAIStateChange.Add(onAIStateChange)

return ParkourVaultSelector
