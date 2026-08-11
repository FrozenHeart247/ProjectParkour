ParkourDodgeConfig = ParkourDodgeConfig or {}

local CATEGORY_TEXT = "UI_optionscreen_binding_ParkourDodge_Category"
local KEY_TEXT = "UI_optionscreen_binding_ParkourDodge"
local TOOLTIP_TEXT = "UI_optionscreen_binding_ParkourDodge_tooltip"

ParkourDodgeConfig.keyBind = nil

local function loadConfig()
    if not PZAPI or not PZAPI.ModOptions then
        return
    end

    -- This creates the Parkour page under Options -> Mods. Future local
    -- Parkour settings can share the same page and mod-options identifier.
    local options = PZAPI.ModOptions:create("Parkour", getText(CATEGORY_TEXT))
    -- Zero means that no key is assigned by default.
    ParkourDodgeConfig.keyBind = options:addKeyBind(
        "DodgeKey",
        getText(KEY_TEXT),
        0,
        getText(TOOLTIP_TEXT)
    )
end

function ParkourDodgeConfig.getKey()
    if not ParkourDodgeConfig.keyBind then
        return 0
    end
    return ParkourDodgeConfig.keyBind:getValue() or 0
end

loadConfig()

return ParkourDodgeConfig
