local Definitions = require "Parkour/Parkour_ProgressionDefinitions"
local Progression = require "Parkour/Parkour_Progression"
local AnimationSync = require "Parkour/Parkour_AnimationSync"

local lastStateByCharacter = setmetatable({}, { __mode = "k" })
local updateCounterByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Progression] " .. message)
    end
end

local function buildState(character)
    local values = {}
    local settings = SandboxVars and SandboxVars.Parkour or nil
    for variableName, entry in pairs(Definitions.ANIMATION_VARIABLES) do
        -- These variables may be consumed by several consecutive AnimNodes.
        -- Keep them level-only and stable; live endurance/load checks belong to
        -- action selectors, otherwise a start clip could unlock and its end
        -- clip could switch back to vanilla halfway through the same action.
        local sandboxEnabled = not settings or settings[entry.sandboxKey] ~= false
        values[variableName] = sandboxEnabled
            and Progression.isUnlocked(character, entry.feature)
    end
    return values
end

local function applyState(character, force)
    if not character or not instanceof(character, "IsoPlayer") then
        return
    end
    local nextState = buildState(character)
    local previous = lastStateByCharacter[character]
    for variableName, value in pairs(nextState) do
        if force or not previous or previous[variableName] ~= value then
            AnimationSync.setVariable(character, variableName, value)
        end
    end
    lastStateByCharacter[character] = nextState
end

local function onCreatePlayer(playerIndex, character)
    if character and character:isLocalPlayer() then
        applyState(character, true)
    end
end

local function onLevelPerk(character, perk, level)
    if not character or not character:isLocalPlayer()
        or perk ~= Progression.getPerk() then
        return
    end

    -- Refresh immediately on the exact engine level-up event.  The periodic
    -- update remains as a safety net for reconnects and server synchronization.
    applyState(character, true)
    local xp = character:getXp():getXP(perk)
    debugLog(string.format(
        "Parkour level changed: level=%d xp=%.3f",
        tonumber(level) or Progression.getLevel(character),
        xp
    ))
end

local function onPlayerUpdate(character)
    if not character or not instanceof(character, "IsoPlayer")
        or not character:isLocalPlayer() then
        return
    end
    local counter = (updateCounterByCharacter[character] or 0) + 1
    if counter >= 15 then
        counter = 0
        Progression.updateAntiFarmMovement(character)
        -- In multiplayer sprint distance is measured by the authoritative
        -- server. Only true single-player awards it from the local character.
        if not isClient() and not isServer() then
            Progression.updateSprintXP(character)
        end
        applyState(character, false)
    end
    updateCounterByCharacter[character] = counter
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.LevelPerk.Add(onLevelPerk)

return true
