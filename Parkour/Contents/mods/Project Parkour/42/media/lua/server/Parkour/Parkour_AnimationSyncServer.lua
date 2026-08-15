local MODULE = "ParkourAnimationSync"

local stateByOnlineId = {}

local ALLOWED_VALUES = {
    PerformingAction = {
        ParkourDodge = true,
        ParkourFreeJump = true,
        ParkourWallRunUp = true,
    },
    ParkourVaultVariant = {
        Vanilla = true,
        FrontFlip = true,
        CorkscrewVault = true,
        DashVault = true,
        DiveRoll = true,
        BackflipVault = true,
        SpeedVault = true,
        VaultOver = true,
        ReverseVault = true,
        WindowVault = true,
    },
    ParkourHighFenceVariant = {
        Vanilla = true,
        HighFenceFrontFlip = true,
        HighFenceVault02 = true,
    },
    ParkourDodgeDirection = {
        Forward = true,
        Backward = true,
        Left = true,
        Right = true,
    },
    ParkourDodgeVariant = {
        ForwardRollDodge = true,
        CombatRollForward = true,
        LowDiveDodgeForward = true,
        CorkscrewEvadeBack = true,
        BackflipDodge = true,
        SideFlipDodgeLeft = true,
        ButterflyDodgeRight = true,
    },
    ParkourFreeJumpDistance = { ["2"] = true, ["3"] = true, ["4"] = true },
    ParkourFreeJumpDeferred = { ["true"] = true, ["false"] = true },
}

local ALLOWED_BOOLEANS = {
    ParkourSprintWindowVault = true,
    ParkourUnlockWindowVault = true,
    ParkourUnlockFallRoll = true,
    ParkourUnlockGetUpBack = true,
    ParkourUnlockBumpRecovery = true,
    ParkourUnlockVaultStumble = true,
}

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour Animation Sync Server] " .. message)
    end
end

local function isAllowed(variableName, value, clear)
    if type(variableName) ~= "string" then
        return false
    end
    if clear == true then
        return ALLOWED_VALUES[variableName] ~= nil
            or ALLOWED_BOOLEANS[variableName] == true
    end
    if ALLOWED_BOOLEANS[variableName] then
        return type(value) == "boolean"
    end
    local values = ALLOWED_VALUES[variableName]
    return values ~= nil and values[tostring(value)] == true
end

local function broadcastVariable(player, variableName, value, clear, targetClient)
    local payload = {
        kind = "variable",
        onlineId = player:getOnlineID(),
        variable = variableName,
        value = value,
        clear = clear == true,
    }
    if targetClient then
        sendServerCommand(targetClient, MODULE, "Apply", payload)
    else
        sendServerCommand(MODULE, "Apply", payload)
    end
end

local function updateVariable(player, args)
    local variableName = args and args.variable
    local value = args and args.value
    local clear = args and args.clear == true
    if not player or not isAllowed(variableName, value, clear) then
        debugLog("Rejected variable " .. tostring(variableName))
        return
    end

    if clear then
        player:clearVariable(variableName)
    else
        player:setVariable(variableName, value)
    end

    local onlineId = player:getOnlineID()
    local state = stateByOnlineId[onlineId]
    if not state then
        state = {}
        stateByOnlineId[onlineId] = state
    end
    if clear then
        state[variableName] = nil
    else
        state[variableName] = value
    end
    broadcastVariable(player, variableName, value, clear)
end

local function sendSnapshot(targetClient)
    for onlineId, state in pairs(stateByOnlineId) do
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if players then
            for index = 0, players:size() - 1 do
                local player = players:get(index)
                if player and player:getOnlineID() == onlineId then
                    for variableName, value in pairs(state) do
                        broadcastVariable(player, variableName, value, false, targetClient)
                    end
                    break
                end
            end
        end
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end
    if command == "Variable" then
        updateVariable(player, args)
    elseif command == "Snapshot" and player then
        sendSnapshot(player)
    end
end

Events.OnClientCommand.Add(onClientCommand)
if Events.OnPlayerDisconnect and Events.OnPlayerDisconnect.Add then
    Events.OnPlayerDisconnect.Add(function(player)
        if player then
            stateByOnlineId[player:getOnlineID()] = nil
        end
    end)
end

return true
