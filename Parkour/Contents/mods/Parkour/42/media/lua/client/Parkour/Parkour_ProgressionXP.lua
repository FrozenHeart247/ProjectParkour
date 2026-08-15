local Definitions = require "Parkour/Parkour_ProgressionDefinitions"
local Progression = require "Parkour/Parkour_Progression"

local MODULE = "ParkourProgression"
local activeByCharacter = setmetatable({}, { __mode = "k" })
local nextToken = 1

local function allocateToken()
    nextToken = nextToken + 1
    if nextToken > 1000000000 then
        nextToken = 1
    end
    return nextToken
end

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Progression] " .. message)
    end
end

local function resolveActionId(character, state)
    if state == ClimbOverFenceState.instance() then
        if character:getVariableBoolean("ParkourSprintWindowVault") then
            return "SprintWindowVault"
        elseif character:getVariableBoolean("VaultOverSprint") then
            return "FenceSprint"
        elseif character:getVariableBoolean("VaultOverRun") then
            return "FenceRun"
        end
        return "FenceWalk"
    elseif state == ClimbThroughWindowState.instance() then
        return "WindowVault"
    elseif state == ClimbOverWallState.instance() then
        return "HighFence"
    end
    return nil
end

local function beginTrackedAction(character, state)
    local actionId = resolveActionId(character, state)
    if not actionId or not Definitions.getXPAction(actionId) then
        return
    end
    local outcomeVariable = state == ClimbThroughWindowState.instance()
        and "ClimbWindowOutcome"
        or "ClimbFenceOutcome"
    local active = {
        token = allocateToken(),
        actionId = actionId,
        state = state,
        startedAt = getTimestampMs(),
        originX = character:getX(),
        originY = character:getY(),
        originZ = character:getZ(),
        sawSuccess = character:getVariableString(outcomeVariable) == "success",
    }
    activeByCharacter[character] = active
    if isClient() then
        sendClientCommand(character, MODULE, "Begin", {
            token = active.token,
            actionId = active.actionId,
            originX = active.originX,
            originY = active.originY,
            originZ = active.originZ,
        })
    end
end

local function finishTrackedAction(character, previousState)
    local active = activeByCharacter[character]
    if not active or active.state ~= previousState then
        return
    end
    activeByCharacter[character] = nil

    local dx = character:getX() - active.originX
    local dy = character:getY() - active.originY
    local travel = math.sqrt(dx * dx + dy * dy)
    local definition = Definitions.getXPAction(active.actionId)
    local elapsed = getTimestampMs() - active.startedAt
    local succeeded = not character:isDead()
        and definition
        and active.sawSuccess
        and travel >= definition.minimumTravel
        and elapsed >= definition.minimumDurationMs

    if isClient() then
        sendClientCommand(character, MODULE, succeeded and "Complete" or "Cancel", {
            token = active.token,
            actionId = active.actionId,
        })
    elseif succeeded then
        local signature = Progression.makeObstacleSignature(
            active.actionId,
            active.originX,
            active.originY,
            active.originZ,
            character:getX(),
            character:getY(),
            character:getZ()
        )
        Progression.awardXP(
            character,
            definition.xp,
            signature,
            active.originX,
            active.originY
        )
    end
    debugLog(string.format(
        "%s %s travel=%.3f elapsed=%d",
        succeeded and "Completed" or "Cancelled",
        active.actionId,
        travel,
        elapsed
    ))
end

local function onPlayerUpdate(character)
    local active = activeByCharacter[character]
    if not active or active.sawSuccess then
        return
    end
    if active.state == ClimbThroughWindowState.instance() then
        active.sawSuccess = character:getVariableString("ClimbWindowOutcome") == "success"
    else
        active.sawSuccess = character:getVariableString("ClimbFenceOutcome") == "success"
    end
end

local function onAIStateChange(character, currentState, previousState)
    if not character or not instanceof(character, "IsoPlayer")
        or not character:isLocalPlayer() then
        return
    end

    if activeByCharacter[character] and currentState ~= activeByCharacter[character].state then
        finishTrackedAction(character, previousState)
    end
    if resolveActionId(character, currentState) then
        beginTrackedAction(character, currentState)
    end
end

Events.OnAIStateChange.Add(onAIStateChange)
Events.OnPlayerUpdate.Add(onPlayerUpdate)

return true
