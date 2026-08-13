require "Parkour/Parkour_DodgeConfig"
require "Parkour/TimedActions/ISParkourWallRunUpAction"

local Validation = require "Parkour/Parkour_WallRunUpValidation"

local COOLDOWN_MS = 1000
local MIN_FACING_ALIGNMENT = 0.70
local cooldownByCharacter = setmetatable({}, { __mode = "k" })

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour WallRunUp Input] " .. message)
    end
end

local function showInvalidFeedback(character)
    if HaloTextHelper and HaloTextHelper.addBadText then
        HaloTextHelper.addBadText(character, getText("UI_Parkour_WallRunUp_Invalid"))
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

    local target, reason = Validation.findTarget(character, MIN_FACING_ALIGNMENT)
    if not target or not ISParkourWallRunUpAction.canStart(character, target, false) then
        cooldownByCharacter[character] = now + 250
        showInvalidFeedback(character)
        debugLog("Blocked before start: " .. tostring(reason))
        return
    end

    cooldownByCharacter[character] = now + COOLDOWN_MS
    ISTimedActionQueue.add(ISParkourWallRunUpAction:new(character, target))
end

local function onKeyStartPressed(key)
    local wallRunKey = ParkourDodgeConfig.getWallRunUpKey()
    if wallRunKey <= 0 or key ~= wallRunKey then
        return
    end
    tryStart(getPlayer())
end

local function onPlayerUpdate(character)
    if character and character:isLocalPlayer() then
        ISParkourWallRunUpAction.updateNetwork()
    end
end

Events.OnKeyStartPressed.Add(onKeyStartPressed)
Events.OnPlayerUpdate.Add(onPlayerUpdate)

return true
