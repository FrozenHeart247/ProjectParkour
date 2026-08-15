require "Parkour/Parkour_DodgeConfig"
require "Parkour/TimedActions/ISParkourFreeJumpAction"

local Validation = require "Parkour/Parkour_FreeJumpValidation"
local Progression = require "Parkour/Parkour_Progression"

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

    local maximumDistance = Progression.getMaximumFreeJumpDistance(character)
    if maximumDistance < 2 then
        Progression.showFailure(character, "level")
        debugLog("Blocked by progression: level")
        return
    end

    local preferredDistance = math.min(
        Validation.getPreferredDistance(character),
        maximumDistance
    )
    local target, reason = Validation.findTarget(
        character,
        preferredDistance,
        MIN_FACING_ALIGNMENT
    )
    local featureId = target and (
        target.crossesLowVehicle
            and "FreeJumpVehicle"
            or Progression.getFreeJumpFeature(target.distance, target.dropLanding == true)
    )
    local progressionAllowed, progressionReason = false, nil
    if target then
        -- Keep both return values.  Wrapping this call in `target and ...`
        -- collapses Lua's multiple returns and loses the rejection reason.
        progressionAllowed, progressionReason = Progression.canUse(
            character,
            featureId
        )
    end
    local startAllowed, startReason = false, nil
    if target and progressionAllowed then
        startAllowed, startReason = ISParkourFreeJumpAction.canStart(
            character,
            target,
            false
        )
    end
    if not target
        or not progressionAllowed
        or not startAllowed then
        cooldownByCharacter[character] = now + 250
        if target and not progressionAllowed then
            Progression.showFailure(character, progressionReason)
            debugLog(string.format(
                "Blocked by progression: %s level=%d endurance=%.3f load=%.3f/%.3f",
                tostring(progressionReason or "unknown"),
                Progression.getLevel(character),
                Progression.getEndurance(character),
                character:getInventoryWeight(),
                character:getMaxWeight()
            ))
        else
            showInvalidFeedback(character)
        end
        debugLog("Blocked before start: " .. tostring(
            progressionReason or startReason or reason or "unknown"
        ))
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
