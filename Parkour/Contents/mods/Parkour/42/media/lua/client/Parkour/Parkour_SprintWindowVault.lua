local ParkourSprintWindowVault = {}
local Progression = require "Parkour/Parkour_Progression"
local AnimationSync = require "Parkour/Parkour_AnimationSync"

local WINDOW_VAULT_VARIABLE = "ParkourSprintWindowVault"
local VAULT_VARIANT_VARIABLE = "ParkourVaultVariant"
local WINDOW_VAULT_VARIANT = "WindowVault"
local WINDOW_SMASH_TRIGGER_VARIABLE = "ParkourWindowSmashNow"
local MIN_SPRINT_TICKS = 7
local TRIGGER_COOLDOWN_MS = 1250
local ENTER_STATE_TIMEOUT_MS = 3000
local ACTIVE_STATE_TIMEOUT_MS = 8000
local CLEANUP_DELAY_TICKS = 8
local MIN_NORMAL_ALIGNMENT = 0.55

local cooldownByCharacter = setmetatable({}, { __mode = "k" })
local pendingByCharacter = setmetatable({}, { __mode = "k" })

local function getSettings()
    return SandboxVars and SandboxVars.Parkour
end

local function debugLog(message)
    local settings = getSettings()
    if settings and settings.DebugLogging then
        print("[Parkour Window Vault] " .. message)
    end
end

local function isEnabled(character)
    local settings = getSettings()
    return (not settings or settings.EnableSprintWindowVault ~= false)
        and Progression.canUse(character, "SprintWindowVault")
end

local function isWindowFrame(object)
    if instanceof(object, "IsoWindowFrame") then
        return true
    end

    -- Some map-made empty frames may still arrive as a generic IsoObject.
    return IsoWindowFrame and IsoWindowFrame.isWindowFrame
        and IsoWindowFrame.isWindowFrame(object)
end

local function isWindowThumpable(object)
    if not instanceof(object, "IsoThumpable") then
        return false
    end

    if object:isWindow() then
        return true
    end

    local sprite = object:getSprite()
    local properties = sprite and sprite:getProperties()
    return properties and (
        properties:has(IsoFlagType.WindowN)
        or properties:has(IsoFlagType.WindowW)
        or properties:has(IsoFlagType.windowN)
        or properties:has(IsoFlagType.windowW)
    )
end

local function canUseWindow(character, object)
    if instanceof(object, "IsoWindow") then
        -- A sprint vault may smash an intact window, but must never bypass a
        -- barricade or an explicitly indestructible map window.
        if not object:IsOpen() and not object:isSmashed() then
            if object:isBarricaded() or object:isInvincible() then
                return false, false, false
            end
            return true, false, true
        end
        return object:canClimbThrough(character), false, false
    end

    if instanceof(object, "IsoWindowFrame") then
        return object:canClimbThrough(character), true, false
    end

    if isWindowFrame(object) then
        return IsoWindowFrame.canClimbThrough(object, character), true, false
    end

    if isWindowThumpable(object) then
        return object:canClimbThrough(character), false, false
    end

    return false, false, false
end

local function getWindowNorth(object)
    if instanceof(object, "IsoWindow")
        or instanceof(object, "IsoWindowFrame")
        or instanceof(object, "IsoThumpable") then
        return object:getNorth()
    end

    local sprite = object:getSprite()
    local properties = sprite and sprite:getProperties()
    return properties and (
        properties:has(IsoFlagType.WindowN)
        or properties:has(IsoFlagType.windowN)
    )
end

local function getTraversalDirection(character, object)
    local forward = character:getForwardDirection()
    if not forward then
        return nil, 0
    end

    -- A north-facing window lies along the X axis, so traversal is along Y.
    if getWindowNorth(object) then
        local y = forward:getY()
        return y >= 0 and IsoDirections.S or IsoDirections.N, math.abs(y)
    else
        local x = forward:getX()
        return x >= 0 and IsoDirections.E or IsoDirections.W, math.abs(x)
    end
end

local function clearRequest(character, reason)
    if not pendingByCharacter[character] then
        return
    end

    pendingByCharacter[character] = nil
    AnimationSync.setVariable(character, WINDOW_VAULT_VARIABLE, false)
    character:setVariable(WINDOW_SMASH_TRIGGER_VARIABLE, false)
    debugLog("Finished: " .. reason)
end

local function canTrigger(character, object, now)
    if not character
        or not object
        or not instanceof(character, "IsoPlayer")
        or not character:isLocalPlayer()
        or character:isDead()
        or not isEnabled(character)
        or character:getVehicle()
        or not character:isSprinting()
        or character:getBeenSprintingFor() < MIN_SPRINT_TICKS
        or character:hasTimedActions()
        or pendingByCharacter[character]
        or now < (cooldownByCharacter[character] or 0) then
        return false, false
    end

    if object:getObjectIndex() == -1 then
        return false, false
    end

    local usable, frame, needsSmash = canUseWindow(character, object)
    local direction, normalAlignment = getTraversalDirection(character, object)
    if not usable or not direction or normalAlignment < MIN_NORMAL_ALIGNMENT then
        return false, false
    end

    return true, frame, direction, needsSmash
end


local function onObjectCollide(character, object)
    local now = getTimestampMs()
    local canStart, frame, direction, needsSmash = canTrigger(character, object, now)
    if not canStart then
        return
    end

    -- Treat the window as the trigger, but use the stable low-fence traversal
    -- state. This is the core technique used by DiveThroughWindows, isolated
    -- behind a dedicated variant so ordinary low-fence vaults stay untouched.
    local stateBefore = tostring(character:getCurrentState())
    cooldownByCharacter[character] = now + TRIGGER_COOLDOWN_MS
    pendingByCharacter[character] = {
        expiresAt = now + ENTER_STATE_TIMEOUT_MS,
        enteredState = false,
        stateExited = false,
        cleanupTicks = 0,
        object = object,
        frame = frame,
        direction = direction,
        needsSmash = needsSmash,
        smashedWindow = false,
    }
    AnimationSync.setVariable(character, WINDOW_VAULT_VARIABLE, true)
    AnimationSync.setVariable(character, VAULT_VARIANT_VARIABLE, WINDOW_VAULT_VARIANT)
    character:setVariable(WINDOW_SMASH_TRIGGER_VARIABLE, false)

    character:setSprinting(true)

    -- IsoGameCharacter.climbOverFence() validates that the destination edge is
    -- an actual low fence, so B42 rejects it at a window. Prepare the same state
    -- directly, notify the player ActionContext, and then enter it explicitly.
    local fenceState = ClimbOverFenceState.instance()
    fenceState:setParams(character, direction)
    character:reportEvent("EventClimbFence")
    character:changeState(fenceState)

    local request = pendingByCharacter[character]
    local calculatedOutcome = character:getVariableString("ClimbFenceOutcome")
    if calculatedOutcome ~= "success" then
        if request then
            request.calculatedOutcome = calculatedOutcome
        end
        character:setVariable("ClimbFenceOutcome", "success")
        debugLog("Overrode window-vault fence outcome after entry: " .. tostring(calculatedOutcome) .. " -> success")
    end

    if request and character:getCurrentState() == fenceState then
        request.enteredState = true
        request.expiresAt = now + ACTIVE_STATE_TIMEOUT_MS
    end

    debugLog(string.format(
        "Fence-state request at %.3f, %.3f, %d (%s), dir=%s; state %s -> %s; started=%s outcome=%s",
        character:getX(),
        character:getY(),
        math.floor(character:getZ()),
        frame and "frame" or "window",
        tostring(direction),
        stateBefore,
        tostring(character:getCurrentState()),
        tostring(character:getVariableBoolean("ClimbFenceStarted")),
        tostring(character:getVariableString("ClimbFenceOutcome"))
    ))
end

local function onAIStateChange(character, currentState, previousState)
    local request = pendingByCharacter[character]
    if not request then
        return
    end

    local fenceState = ClimbOverFenceState.instance()
    if currentState == fenceState then
        local calculatedOutcome = character:getVariableString("ClimbFenceOutcome")
        request.calculatedOutcome = calculatedOutcome
        if calculatedOutcome ~= "success" then
            character:setVariable("ClimbFenceOutcome", "success")
            debugLog("Overrode window-vault fence outcome: " .. tostring(calculatedOutcome) .. " -> success")
        end

        request.enteredState = true
        request.expiresAt = getTimestampMs() + ACTIVE_STATE_TIMEOUT_MS
        return
    end

    if previousState == fenceState and request.enteredState then
        request.stateExited = true
        request.cleanupTicks = CLEANUP_DELAY_TICKS
        debugLog("Fence state exited; retaining window variant for blend-out")
    end
end

local function onPlayerUpdate(character)
    local request = pendingByCharacter[character]
    if not request then
        return
    end

    if request.needsSmash
        and not request.smashedWindow
        and character:getVariableBoolean(WINDOW_SMASH_TRIGGER_VARIABLE) then
        request.smashedWindow = true
        character:setVariable(WINDOW_SMASH_TRIGGER_VARIABLE, false)

        if request.object:getObjectIndex() ~= -1
            and instanceof(request.object, "IsoWindow")
            and not request.object:IsOpen()
            and not request.object:isSmashed() then
            request.object:smashWindow()
            request.object:update()
            debugLog("Smashed intact window at animation event")
        end
    end

    if request.stateExited then
        request.cleanupTicks = request.cleanupTicks - 1
        if request.cleanupTicks <= 0 then
            clearRequest(character, "fence animation blend-out completed")
        end
        return
    end

    if character:isDead() then
        clearRequest(character, "character died")
    elseif getTimestampMs() > request.expiresAt then
        debugLog(string.format(
            "Timeout detail: state=%s timedActions=%s started=%s outcome=%s",
            tostring(character:getCurrentState()),
            tostring(character:hasTimedActions()),
            tostring(character:getVariableBoolean("ClimbFenceStarted")),
            tostring(character:getVariableString("ClimbFenceOutcome"))
        ))
        clearRequest(character, "request timeout")
    end
end

Events.OnObjectCollide.Add(onObjectCollide)
Events.OnAIStateChange.Add(onAIStateChange)
Events.OnPlayerUpdate.Add(onPlayerUpdate)

return ParkourSprintWindowVault
