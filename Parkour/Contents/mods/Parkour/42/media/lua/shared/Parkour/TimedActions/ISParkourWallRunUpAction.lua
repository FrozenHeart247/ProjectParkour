require "TimedActions/ISBaseTimedAction"

local Validation = require "Parkour/Parkour_WallRunUpValidation"

ISParkourWallRunUpAction = ISBaseTimedAction:derive("ISParkourWallRunUpAction")

local MODULE = "ParkourWallRunUp"
local ACTION_ANIMATION = "ParkourWallRunUp"
local ANIMATION_START_TIMEOUT_MS = 600
local ANIMATION_FAILSAFE_MS = 6200
local NETWORK_REQUEST_LIFETIME_MS = 8200

local pendingNetworkRequests = {}
local nextRequestId = 1

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour WallRunUp] " .. message)
    end
end

local function allocateRequestId()
    nextRequestId = nextRequestId + 1
    if nextRequestId > 1000000000 then
        nextRequestId = 1
    end
    return nextRequestId
end

local function sendBegin(action)
    if not isClient() then
        return
    end
    sendClientCommand(action.character, MODULE, "Begin", {
        requestId = action.requestId,
        originX = action.target.originX,
        originY = action.target.originY,
        originZ = action.target.originZ,
        directionName = action.target.directionName,
    })
end

local function performLocalTransfer(action)
    local target, reason = Validation.findTargetFromOrigin(
        action.target.originX,
        action.target.originY,
        action.target.originZ,
        action.target.directionName,
        action.character
    )
    if not target then
        return false, reason
    end

    local transferX = target.targetX
    local transferY = target.targetY
    if math.floor(action.character:getX()) == math.floor(target.targetX)
        and math.floor(action.character:getY()) == math.floor(target.targetY) then
        transferX = action.character:getX()
        transferY = action.character:getY()
    end
    Validation.moveCharacter(action.character, transferX, transferY, target.targetZ)
    action.transferred = true
    return true
end

function ISParkourWallRunUpAction.canStart(character, target, ignoreQueue)
    if not character
        or not target
        or character:isDead()
        or character:getVehicle()
        or character:isOnFloor()
        or character:isBlockMovement()
        or character:getIgnoreMovement()
        or character:isAttacking()
        or (not ignoreQueue and character:hasTimedActions()) then
        return false
    end

    local refreshed = Validation.findTargetFromOrigin(
        target.originX,
        target.originY,
        target.originZ,
        target.directionName,
        character
    )
    return refreshed ~= nil
end

function ISParkourWallRunUpAction:isValidStart()
    return ISParkourWallRunUpAction.canStart(self.character, self.target, true)
end

function ISParkourWallRunUpAction:isValid()
    return not self.invalid and not self.character:isDead() and not self.character:getVehicle()
end

function ISParkourWallRunUpAction:start()
    self.action:setUseProgressBar(false)
    self.startedAt = getTimestampMs()
    self.character:setForwardDirection(self.facingX, self.facingY)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self.character:setIgnoreMovement(true)
    self.ownsMovementLock = true
    self:setActionAnim(ACTION_ANIMATION)

    pendingNetworkRequests[self.requestId] = {
        action = self,
        expiresAt = self.startedAt + NETWORK_REQUEST_LIFETIME_MS,
    }
    sendBegin(self)
    debugLog(string.format(
        "Started request %s from %d,%d,%d toward %s",
        tostring(self.requestId),
        self.target.originX,
        self.target.originY,
        self.target.originZ,
        self.target.directionName
    ))
end

function ISParkourWallRunUpAction:update()
    self.character:setIgnoreMovement(true)
    self.character:setRunning(false)
    self.character:setSprinting(false)
    self.character:setIsAiming(false)
    self.character:setForwardDirection(self.facingX, self.facingY)
    self.character:setMetabolicTarget(Metabolics.JumpFence)

    local now = getTimestampMs()
    if not self.animationStarted then
        if now - self.startedAt >= ANIMATION_START_TIMEOUT_MS then
            self.invalid = true
            debugLog("Animation start timeout for request " .. tostring(self.requestId))
            self:forceComplete()
        end
        return
    end

    if now - self.animationStartedAt >= ANIMATION_FAILSAFE_MS then
        debugLog("Animation failsafe for request " .. tostring(self.requestId))
        self:forceComplete()
    end
end

function ISParkourWallRunUpAction:requestTransfer()
    if self.transferRequested or self.transferred then
        return
    end
    self.transferRequested = true

    if isClient() then
        sendClientCommand(self.character, MODULE, "Transfer", {
            requestId = self.requestId,
        })
        debugLog("Requested server transfer " .. tostring(self.requestId))
        return
    end

    local moved, reason = performLocalTransfer(self)
    if not moved then
        self.invalid = true
        debugLog("Local transfer rejected: " .. tostring(reason))
        self:forceComplete()
    else
        pendingNetworkRequests[self.requestId] = nil
        debugLog("Local transfer completed " .. tostring(self.requestId))
    end
end

function ISParkourWallRunUpAction:animEvent(event, parameter)
    if event == "ParkourWallRunStarted" and not self.animationStarted then
        self.animationStarted = true
        self.animationStartedAt = getTimestampMs()
        debugLog("Animation confirmed " .. tostring(self.requestId))
    elseif event == "ParkourWallRunTransfer" then
        self:requestTransfer()
    elseif event == "ParkourWallRunDone" then
        self.animationDone = true
        if not self.transferRequested then
            self:requestTransfer()
        end
        -- In multiplayer keep movement locked for the short interval between
        -- the final animation event and the authoritative server response.
        if not isClient() or self.transferred or self.invalid then
            self:forceComplete()
        end
    end
end

function ISParkourWallRunUpAction:releaseControl()
    if self.controlReleased then
        return
    end
    self.controlReleased = true
    if self.ownsMovementLock then
        self.character:setIgnoreMovement(false)
        self.ownsMovementLock = false
    end
    pendingNetworkRequests[self.requestId] = nil
end

function ISParkourWallRunUpAction:stop()
    self:releaseControl()
    ISBaseTimedAction.stop(self)
end

function ISParkourWallRunUpAction:perform()
    self:releaseControl()
    ISBaseTimedAction.perform(self)
end

function ISParkourWallRunUpAction:complete()
    return true
end

function ISParkourWallRunUpAction:getDuration()
    return -1
end

function ISParkourWallRunUpAction.onServerCommand(module, command, args)
    if module ~= MODULE or not args then
        return
    end

    local entry = pendingNetworkRequests[args.requestId]
    local action = entry and entry.action
    if not action then
        return
    end

    if command == "BeginAccepted" then
        action.serverApproved = true
        debugLog("Server approved " .. tostring(args.requestId))
    elseif command == "BeginRejected" then
        pendingNetworkRequests[args.requestId] = nil
        action.invalid = true
        debugLog("Server rejected start: " .. tostring(args.reason))
        action:forceComplete()
    elseif command == "TransferAccepted" then
        pendingNetworkRequests[args.requestId] = nil
        Validation.moveCharacter(action.character, args.x, args.y, args.z)
        action.transferred = true
        debugLog("Server transfer accepted " .. tostring(args.requestId))
        if action.animationDone then
            action:forceComplete()
        end
    elseif command == "TransferRejected" then
        pendingNetworkRequests[args.requestId] = nil
        action.invalid = true
        debugLog("Server transfer rejected: " .. tostring(args.reason))
        action:forceComplete()
    end
end

function ISParkourWallRunUpAction.updateNetwork()
    local now = getTimestampMs()
    for requestId, entry in pairs(pendingNetworkRequests) do
        if now > entry.expiresAt then
            pendingNetworkRequests[requestId] = nil
            if entry.action and not entry.action.transferred then
                entry.action.invalid = true
                entry.action:forceComplete()
                debugLog("Network request timed out " .. tostring(requestId))
            end
        end
    end
end

function ISParkourWallRunUpAction:new(character, target)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.target = target
    action.facingX = target.direction.dx
    action.facingY = target.direction.dy
    action.requestId = allocateRequestId()
    action.invalid = false
    action.animationStarted = false
    action.animationStartedAt = nil
    action.animationDone = false
    action.transferRequested = false
    action.transferred = false
    action.serverApproved = not isClient()
    action.controlReleased = false
    action.ownsMovementLock = false
    action.stopOnWalk = false
    action.stopOnRun = false
    action.stopOnAim = false
    action.maxTime = action:getDuration()
    return action
end

if isClient() then
    Events.OnServerCommand.Add(ISParkourWallRunUpAction.onServerCommand)
end

return ISParkourWallRunUpAction
