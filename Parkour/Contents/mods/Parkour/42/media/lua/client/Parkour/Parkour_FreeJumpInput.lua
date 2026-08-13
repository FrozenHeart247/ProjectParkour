require "Parkour/Parkour_DodgeConfig"
require "Parkour/TimedActions/ISParkourFreeJumpAction"

local Validation = require "Parkour/Parkour_FreeJumpValidation"

local COOLDOWN_MS = 800
local MIN_FACING_ALIGNMENT = 0.90
local cooldownByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour FreeJump Input] " .. message)
    end
end

local function showInvalidFeedback(character)
    if HaloTextHelper and HaloTextHelper.addBadText then
        HaloTextHelper.addBadText(character, getText("UI_Parkour_FreeJump_Invalid"))
    end
end

local function tryStart(character)
    if not character or not character:isLocalPlayer() then
        return
    end

    local now = getTimestampMs()
    if now < (cooldownByCharacter[character] or 0) then
        return
    end

    local preferredDistance = Validation.getPreferredDistance(character)
    local target, reason = Validation.findTarget(
        character,
        preferredDistance,
        MIN_FACING_ALIGNMENT
    )
    if not target or not ISParkourFreeJumpAction.canStart(character, target, false) then
        cooldownByCharacter[character] = now + 250
        showInvalidFeedback(character)
        debugLog("Blocked before start: " .. tostring(reason))
        return
    end

    cooldownByCharacter[character] = now + COOLDOWN_MS
    ISTimedActionQueue.add(ISParkourFreeJumpAction:new(character, target))
end

local function onKeyStartPressed(key)
    local jumpKey = ParkourDodgeConfig.getFreeJumpKey()
    if jumpKey <= 0 or key ~= jumpKey then
        return
    end
    tryStart(getPlayer())
end

local function onPlayerUpdate(character)
    if character and character:isLocalPlayer() then
        ISParkourFreeJumpAction.updateNetwork(character)
    end
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)
Events.OnPlayerUpdate.Add(onPlayerUpdate)

return true
