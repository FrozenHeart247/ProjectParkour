require "ISUI/ISContextMenu"

local Progression = require "Parkour/Parkour_Progression"
local MODULE = "ParkourProgression"

local function hasPermission(character)
    if not character then
        return false
    end
    if isClient() then
        local role = character:getRole()
        return role
            and role:hasCapability(Capability.CanModifyPlayerStatsInThePlayerStatsUI)
    end
    return isDebugEnabled()
end

local function setLevel(character, level)
    if isClient() then
        sendClientCommand(character, MODULE, "DebugSetLevel", { level = level })
    else
        Progression.setLevelAuthoritative(character, level)
    end
end

local function levelDown(character)
    setLevel(character, Progression.getLevel(character) - 1)
end

local function levelUp(character)
    setLevel(character, Progression.getLevel(character) + 1)
end

local function resetLevel(character)
    setLevel(character, 0)
end

local function onFillWorldObjectContextMenu(playerIndex, context, worldObjects, test)
    if test then
        return
    end
    local character = getSpecificPlayer(playerIndex)
    if not hasPermission(character) then
        return
    end

    local level = Progression.getLevel(character)
    local endurance = Progression.getEndurance(character) * 100
    local root = context:addDebugOption(getText("UI_Parkour_Debug_Title"), character, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(root, menu)

    local status = menu:addOption(
        getText("UI_Parkour_Debug_Status", level, string.format("%.1f", endurance)),
        character,
        nil
    )
    status.notAvailable = true
    menu:addOption(getText("UI_Parkour_Debug_LevelUp"), character, levelUp)
    menu:addOption(getText("UI_Parkour_Debug_LevelDown"), character, levelDown)
    menu:addOption(getText("UI_Parkour_Debug_Reset"), character, resetLevel)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

return true
