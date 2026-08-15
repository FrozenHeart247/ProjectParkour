local ParkourBumpRecovery = {}

local FINISH_VARIABLE = "ParkourBumpRecoveryFinish"

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour] " .. message)
    end
end

local function finishRecovery(character)
    -- Do not use BumpFallAnimFinished here: BumpedState interprets it as a
    -- completed knockdown and forces an on-ground state. Convert the final
    -- frames into a completed ordinary bump instead.
    character:setBumpFall(false)
    character:setVariable("BumpFall", false)
    character:setBumpDone(true)
    character:setVariable("BumpDone", true)
    character:setVariable("BumpStaggered", false)
    character:clearVariable("BumpFallAnimFinished")
    character:clearVariable(FINISH_VARIABLE)
    debugLog("Finished Parkour_BumpRecovery standing")
end

local function onPlayerUpdate(character)
    if not character or not instanceof(character, "IsoPlayer") then
        return
    end

    if character:getVariableBoolean(FINISH_VARIABLE) then
        finishRecovery(character)
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)

return ParkourBumpRecovery
