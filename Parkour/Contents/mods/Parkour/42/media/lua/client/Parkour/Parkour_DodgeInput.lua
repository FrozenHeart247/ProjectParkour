require "Parkour/Parkour_DodgeConfig"
require "Parkour/TimedActions/ISParkourDodgeAction"
local ParkourDodgeSelector = require "Parkour/Parkour_DodgeSelector"
local ParkourDodgeDirection = require "Parkour/Parkour_DodgeDirection"
local Progression = require "Parkour/Parkour_Progression"

local ParkourDodgeInput = {}

local COOLDOWN_MS = 750
local DODGE_REQUEST_MS = 350

local cooldownByCharacter = setmetatable({}, { __mode = "k" })
local pendingByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Dodge] " .. message)
    end
end

local function buildRequest(character)
    local direction, travelX, travelY, facingX, facingY,
        inputSource, forwardAmount, rightAmount = ParkourDodgeDirection.resolve(character)

    return {
        direction = direction,
        travelX = travelX,
        travelY = travelY,
        facingX = facingX,
        facingY = facingY,
        inputSource = inputSource,
        forwardAmount = forwardAmount,
        rightAmount = rightAmount,
    }
end

local function startRequest(character, request, now, quiet)
    if now < (cooldownByCharacter[character] or 0) then
        return false
    end

    local direction = request.direction
    local travelX = request.travelX
    local travelY = request.travelY
    if not ISParkourDodgeAction.canStart(
        character,
        travelX,
        travelY,
        request.escapeFromReaction
    ) then
        if not quiet then
            debugLog("Blocked before start: " .. direction)
        end
        return false
    end

    local variant = ParkourDodgeSelector.choose(character, direction)
    if not variant then
        debugLog("No enabled dodge variant for direction: " .. direction)
        return false
    end

    cooldownByCharacter[character] = now + COOLDOWN_MS
    local dodgeAction = ISParkourDodgeAction:new(
        character,
        direction,
        travelX,
        travelY,
        request.facingX,
        request.facingY,
        variant,
        request.escapeFromReaction,
        request.reactionAnimation
    )
    ISTimedActionQueue.add(dodgeAction)
    debugLog(string.format(
        "Started %s/%s (input %s; local F %.3f/R %.3f; travel %.3f, %.3f; facing %.3f, %.3f)",
        direction,
        variant.id,
        request.inputSource,
        request.forwardAmount,
        request.rightAmount,
        travelX,
        travelY,
        request.facingX,
        request.facingY
    ))
    return true
end

local function tryStartDodge(character)
    if not character or not character:isLocalPlayer() then
        return
    end

    local allowed, progressionReason = Progression.canUse(character, "Dodge")
    if not allowed then
        Progression.showFailure(character, progressionReason)
        debugLog("Blocked by progression: " .. tostring(progressionReason))
        return
    end

    -- Never queue a second dodge behind an action that is already running.
    if character:hasTimedActions() then
        debugLog("Ignored dodge while another timed action is active")
        return
    end

    local now = getTimestampMs()
    local request = buildRequest(character)

    if ISParkourDodgeAction.isEscapableReactionState(character) then
        if not pendingByCharacter[character] then
            request.escapeFromReaction = true
            request.reactionAnimation = ISParkourDodgeAction.isHitReactionState(character)
            request.expiresAt = now + DODGE_REQUEST_MS
            pendingByCharacter[character] = request
            debugLog("Scheduled from player reaction: " .. request.direction)
        else
            debugLog("Ignored repeated reaction dodge")
        end
        return
    end

    if ISParkourDodgeAction.isForcedPlayerState(character) then
        debugLog("Blocked by a hard player state: " .. request.direction)
        return
    end

    -- A fresh safe-state press supersedes an older buffered request.
    pendingByCharacter[character] = nil
    startRequest(character, request, now, false)
end

local function onPlayerUpdate(character)
    ISParkourDodgeAction.updateReactionTailGuard(character)

    local request = pendingByCharacter[character]
    if not request then
        return
    end

    local now = getTimestampMs()
    if now > request.expiresAt
        or character:isDead()
        or character:getVehicle() then
        pendingByCharacter[character] = nil
        debugLog("Buffered dodge expired or became invalid")
        return
    end

    if ISParkourDodgeAction.isForcedPlayerState(character)
        and not ISParkourDodgeAction.isEscapableReactionState(character) then
        return
    end

    if startRequest(character, request, now, true) then
        pendingByCharacter[character] = nil
        debugLog("Started reaction dodge: " .. request.direction)
    end
end

local function onKeyStartPressed(key)
    local dodgeKey = ParkourDodgeConfig.getKey()
    if dodgeKey <= 0 or key ~= dodgeKey then
        return
    end

    tryStartDodge(getPlayer())
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)
Events.OnPlayerUpdate.Add(onPlayerUpdate)

return ParkourDodgeInput
