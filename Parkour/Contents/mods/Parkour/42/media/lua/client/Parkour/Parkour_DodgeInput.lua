require "Parkour/Parkour_DodgeConfig"
require "Parkour/TimedActions/ISParkourDodgeAction"
local ParkourDodgeSelector = require "Parkour/Parkour_DodgeSelector"

local ParkourDodgeInput = {}

local INPUT_DEAD_ZONE = 0.15
local COOLDOWN_MS = 750

local cooldownByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Dodge] " .. message)
    end
end

local function normalized(x, y, fallbackX, fallbackY)
    local length = math.sqrt(x * x + y * y)
    if length <= 0.0001 then
        return fallbackX, fallbackY
    end
    return x / length, y / length
end

local function getFacing(character)
    local facing = character:getForwardDirection()
    if facing then
        return normalized(facing:getX(), facing:getY(), 1, 0)
    end

    local angle = character:getAnimAngleRadians()
    return math.cos(angle), math.sin(angle)
end

local function getMovementInput(character)
    local destination = Vector2.new(0, 0)
    local movement = character:getInputMoveVector(destination) or destination
    return movement:getX(), movement:getY()
end

local function resolveDirection(character)
    local facingX, facingY = getFacing(character)

    -- Outside combat stance a standalone press always dodges forward.
    if not character:isAiming() then
        return "Forward", facingX, facingY, facingX, facingY
    end

    local inputX, inputY = getMovementInput(character)
    local inputLength = math.sqrt(inputX * inputX + inputY * inputY)

    -- In combat stance a press without movement is a defensive back dodge.
    if inputLength < INPUT_DEAD_ZONE then
        return "Backward", -facingX, -facingY, facingX, facingY
    end

    inputX, inputY = normalized(inputX, inputY, facingX, facingY)

    -- PZ world Y grows southward, so this is the local right vector.
    local rightX, rightY = -facingY, facingX
    local forwardAmount = inputX * facingX + inputY * facingY
    local rightAmount = inputX * rightX + inputY * rightY

    if math.abs(forwardAmount) >= math.abs(rightAmount) then
        if forwardAmount >= 0 then
            return "Forward", facingX, facingY, facingX, facingY
        end
        return "Backward", -facingX, -facingY, facingX, facingY
    end

    if rightAmount >= 0 then
        return "Right", rightX, rightY, facingX, facingY
    end
    return "Left", -rightX, -rightY, facingX, facingY
end

local function tryStartDodge(character)
    if not character or not character:isLocalPlayer() then
        return
    end

    local now = getTimestampMs()
    if now < (cooldownByCharacter[character] or 0) then
        return
    end

    local direction, travelX, travelY, facingX, facingY = resolveDirection(character)
    if not ISParkourDodgeAction.canStart(character, travelX, travelY) then
        debugLog("Blocked before start: " .. direction)
        return
    end

    local variant = ParkourDodgeSelector.choose(character, direction)
    if not variant then
        debugLog("No enabled dodge variant for direction: " .. direction)
        return
    end

    cooldownByCharacter[character] = now + COOLDOWN_MS
    ISTimedActionQueue.add(ISParkourDodgeAction:new(
        character,
        direction,
        travelX,
        travelY,
        facingX,
        facingY,
        variant
    ))
    debugLog(string.format(
        "Started %s/%s (travel %.3f, %.3f; facing %.3f, %.3f)",
        direction,
        variant.id,
        travelX,
        travelY,
        facingX,
        facingY
    ))
end

local function onKeyStartPressed(key)
    local dodgeKey = ParkourDodgeConfig.getKey()
    if dodgeKey <= 0 or key ~= dodgeKey then
        return
    end

    tryStartDodge(getPlayer())
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)

return ParkourDodgeInput
