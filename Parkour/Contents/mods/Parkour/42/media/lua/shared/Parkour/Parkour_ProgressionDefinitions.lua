local Definitions = {}

-- This is the single source of truth for unlock levels and the physical
-- requirements of custom Parkour actions/animations. Selectors use the same
-- entries as the manual actions, so a Sandbox change cannot leave the two
-- systems disagreeing about an unlock.
Definitions.FEATURES = {
    ReverseVault = { level = 1, endurance = 0.10, injuryGroup = "legs" },
    WindowVault = { level = 1, endurance = 0.10, injuryGroup = "climb" },
    VaultStumble = { level = 1 },
    GetUpBack = { level = 1 },
    BumpRecovery = { level = 1 },

    FreeJump2 = { level = 2, endurance = 0.20, cost = 0.04, injuryGroup = "legs" },
    FreeJumpDrop2 = { level = 2, endurance = 0.20, cost = 0.04, injuryGroup = "legs" },
    FreeJump3 = { level = 2, endurance = 0.25, cost = 0.06, injuryGroup = "legs" },
    FreeJumpDrop3 = { level = 2, endurance = 0.25, cost = 0.06, injuryGroup = "legs" },
    FreeJump4 = { level = 2, endurance = 0.30, cost = 0.08, injuryGroup = "legs" },
    FreeJumpDrop4 = { level = 2, endurance = 0.30, cost = 0.08, injuryGroup = "legs" },
    FreeJumpVehicle = { level = 2, endurance = 0.30, cost = 0.08, injuryGroup = "legs" },
    FallRollLanding = { level = 2, endurance = 0.10, cost = 0.02, injuryGroup = "legs" },
    DashVault = { level = 2, endurance = 0.15, injuryGroup = "legs" },
    CorkscrewVault = { level = 2, endurance = 0.15, injuryGroup = "legs" },

    Dodge = { level = 3, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    ForwardRollDodge = { level = 3, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    CorkscrewEvadeBack = { level = 3, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    ButterflyDodgeRight = { level = 3, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    SideFlipDodgeLeft = { level = 3, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    DiveRoll = { level = 3, endurance = 0.15, injuryGroup = "legs" },

    SprintWindowVault = { level = 4, endurance = 0.25, cost = 0.04, injuryGroup = "climb" },
    SpeedVault = { level = 4, endurance = 0.20, injuryGroup = "legs" },
    VaultOver = { level = 4, endurance = 0.20, injuryGroup = "legs" },
    HighFenceVault02 = { level = 4, endurance = 0.25, injuryGroup = "climb" },

    FrontFlip = { level = 5, endurance = 0.15, injuryGroup = "legs" },
    BackflipVault = { level = 5, endurance = 0.15, injuryGroup = "legs" },
    HighFenceFrontFlip = { level = 5, endurance = 0.25, injuryGroup = "climb" },
    CombatRollForward = { level = 5, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    LowDiveDodgeForward = { level = 5, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },
    BackflipDodge = { level = 5, endurance = 0.20, cost = 0.10, costProfile = "dodge", injuryGroup = "legs" },

    WallRunUp = { level = 8, endurance = 0.35, cost = 0.14, injuryGroup = "climb" },
}

Definitions.ANIMATION_VARIABLES = {
    ParkourUnlockWindowVault = { feature = "WindowVault", sandboxKey = "EnableWindowVault" },
    ParkourUnlockFallRoll = { feature = "FallRollLanding", sandboxKey = "EnableFallRollLanding" },
    ParkourUnlockGetUpBack = { feature = "GetUpBack", sandboxKey = "EnableGetUpBack" },
    ParkourUnlockBumpRecovery = { feature = "BumpRecovery", sandboxKey = "EnableBumpRecovery" },
    ParkourUnlockVaultStumble = { feature = "VaultStumble", sandboxKey = "EnableVaultStumble" },
}

Definitions.XP_ACTIONS = {
    FenceWalk = { xp = 2, minimumDurationMs = 180, minimumTravel = 0.35 },
    FenceRun = { xp = 3, minimumDurationMs = 180, minimumTravel = 0.35 },
    FenceSprint = { xp = 4, minimumDurationMs = 180, minimumTravel = 0.35 },
    WindowVault = { xp = 2, minimumDurationMs = 180, minimumTravel = 0.35 },
    SprintWindowVault = { xp = 5, minimumDurationMs = 180, minimumTravel = 0.35 },
    HighFence = { xp = 6, minimumDurationMs = 300, minimumTravel = 0.35 },
}

function Definitions.get(featureId)
    return Definitions.FEATURES[featureId]
end

function Definitions.getXPAction(actionId)
    return Definitions.XP_ACTIONS[actionId]
end

function Definitions.getFreeJumpFeature(distance, isDrop)
    local suffix = tostring(math.max(2, math.min(4, math.floor(tonumber(distance) or 2))))
    if isDrop then
        return "FreeJumpDrop" .. suffix
    end
    return "FreeJump" .. suffix
end

return Definitions
