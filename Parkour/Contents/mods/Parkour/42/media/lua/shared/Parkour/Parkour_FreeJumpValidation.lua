local ParkourFreeJumpValidation = {}

ParkourFreeJumpValidation.MIN_DISTANCE = 2
ParkourFreeJumpValidation.MAX_DISTANCE = 4

local DIAGONAL = 0.70710678118655
local SAMPLE_STEP = 0.05

ParkourFreeJumpValidation.DIRECTIONS = {
    N = { dx = 0, dy = -1 },
    NE = { dx = DIAGONAL, dy = -DIAGONAL },
    E = { dx = 1, dy = 0 },
    SE = { dx = DIAGONAL, dy = DIAGONAL },
    S = { dx = 0, dy = 1 },
    SW = { dx = -DIAGONAL, dy = DIAGONAL },
    W = { dx = -1, dy = 0 },
    NW = { dx = -DIAGONAL, dy = -DIAGONAL },
}

local DIRECTION_ORDER = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function hasFlag(square, flag)
    return square and flag and square:has(flag) or false
end

local function isEnabled()
    local settings = SandboxVars and SandboxVars.Parkour
    return not settings or settings.EnableFreeJump ~= false
end

local function normalizeDistance(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if value < ParkourFreeJumpValidation.MIN_DISTANCE
        or value > ParkourFreeJumpValidation.MAX_DISTANCE then
        return nil
    end
    return value
end

local function edgeData(fromSquare, toSquare)
    if not fromSquare or not toSquare or fromSquare:getZ() ~= toSquare:getZ() then
        return nil
    end

    local dx = toSquare:getX() - fromSquare:getX()
    local dy = toSquare:getY() - fromSquare:getY()
    if math.abs(dx) + math.abs(dy) ~= 1 then
        return nil
    end

    if dx < 0 then
        return fromSquare, false
    elseif dx > 0 then
        return toSquare, false
    elseif dy < 0 then
        return fromSquare, true
    end
    return toSquare, true
end

local function edgeIsBlocked(fromSquare, toSquare)
    local edgeSquare, north = edgeData(fromSquare, toSquare)
    if not edgeSquare then
        return true
    end

    local lowFence
    local tallFence
    local window
    local door
    if north then
        lowFence = hasFlag(edgeSquare, IsoFlagType.HoppableN)
        tallFence = hasFlag(edgeSquare, IsoFlagType.TallHoppableN)
        window = hasFlag(edgeSquare, IsoFlagType.WindowN)
            or hasFlag(edgeSquare, IsoFlagType.windowN)
        door = hasFlag(edgeSquare, IsoFlagType.DoorWallN)
            or hasFlag(edgeSquare, IsoFlagType.doorN)
    else
        lowFence = hasFlag(edgeSquare, IsoFlagType.HoppableW)
        tallFence = hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
        window = hasFlag(edgeSquare, IsoFlagType.WindowW)
            or hasFlag(edgeSquare, IsoFlagType.windowW)
        door = hasFlag(edgeSquare, IsoFlagType.DoorWallW)
            or hasFlag(edgeSquare, IsoFlagType.doorW)
    end

    -- Tall fences, windows and doors must never be bypassed. A low fence can
    -- also report wall/collision flags in B42, so accept a confirmed hoppable
    -- edge before testing those generic blockers.
    if tallFence or window or door
        or fromSquare:isWindowTo(toSquare)
        or fromSquare:isDoorTo(toSquare) then
        return true
    end

    if lowFence and fromSquare:isHoppableTo(toSquare) then
        return false
    end

    if fromSquare:isWallTo(toSquare) then
        return true
    end

    if north then
        if hasFlag(edgeSquare, IsoFlagType.collideN)
            or hasFlag(edgeSquare, IsoFlagType.cutN)
            or hasFlag(edgeSquare, IsoFlagType.WallN)
            or hasFlag(edgeSquare, IsoFlagType.WallNTrans)
            or hasFlag(edgeSquare, IsoFlagType.WallNW) then
            return true
        end
    elseif hasFlag(edgeSquare, IsoFlagType.collideW)
        or hasFlag(edgeSquare, IsoFlagType.cutW)
        or hasFlag(edgeSquare, IsoFlagType.WallW)
        or hasFlag(edgeSquare, IsoFlagType.WallWTrans)
        or hasFlag(edgeSquare, IsoFlagType.WallNW) then
        return true
    end

    if fromSquare:isBlockedTo(toSquare) then
        return true
    end

    -- Do not apply testCollideSpecialObjects here: it includes furniture and
    -- rocks inside a tile, which are exactly the obstacles this jump clears.
    return false
end

local function transitionIsClear(cell, fromX, fromY, toX, toY, z)
    local dx = toX - fromX
    local dy = toY - fromY
    if math.abs(dx) > 1 or math.abs(dy) > 1 or (dx == 0 and dy == 0) then
        return false
    end

    local fromSquare = cell:getGridSquare(fromX, fromY, z)
    local toSquare = cell:getGridSquare(toX, toY, z)
    if not fromSquare or not toSquare then
        return false
    end

    if dx == 0 or dy == 0 then
        return not edgeIsBlocked(fromSquare, toSquare)
    end

    -- Crossing a grid corner is conservative: both routes around that corner
    -- must be open. This prevents diagonal slipping through wall corners.
    local horizontal = cell:getGridSquare(fromX + dx, fromY, z)
    local vertical = cell:getGridSquare(fromX, fromY + dy, z)
    if not horizontal or not vertical then
        return false
    end
    return not edgeIsBlocked(fromSquare, horizontal)
        and not edgeIsBlocked(fromSquare, vertical)
        and not edgeIsBlocked(horizontal, toSquare)
        and not edgeIsBlocked(vertical, toSquare)
end

local function routeIsClear(cell, startX, startY, targetX, targetY, z)
    local deltaX = targetX - startX
    local deltaY = targetY - startY
    local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local samples = math.max(1, math.ceil(length / SAMPLE_STEP))
    local previousX = math.floor(startX)
    local previousY = math.floor(startY)

    for index = 1, samples do
        local progress = index / samples
        local squareX = math.floor(startX + deltaX * progress)
        local squareY = math.floor(startY + deltaY * progress)
        if squareX ~= previousX or squareY ~= previousY then
            local crossedSquare = cell:getGridSquare(squareX, squareY, z)
            if not crossedSquare
                or crossedSquare:HasStairs()
                or crossedSquare:hasSlopedSurface()
                or crossedSquare:isVehicleIntersecting() then
                return false
            end
            if not transitionIsClear(
                cell,
                previousX,
                previousY,
                squareX,
                squareY,
                z
            ) then
                return false
            end
            previousX = squareX
            previousY = squareY
        end
    end
    return true
end

local function isLandingSquareClear(square, allowedCharacter)
    if not square
        or square:isSolid()
        or square:isSolidTrans()
        or square:HasStairs()
        or square:hasSlopedSurface()
        or square:isVehicleIntersecting()
        or not square:TreatAsSolidFloor()
        or not square:canStand() then
        return false
    end

    local movingObjects = square:getMovingObjects()
    if movingObjects then
        for index = 0, movingObjects:size() - 1 do
            if movingObjects:get(index) ~= allowedCharacter then
                return false
            end
        end
    end
    return true
end

function ParkourFreeJumpValidation.getPreferredDistance(character)
    if character and character:isSprinting() then
        return 4
    end
    if character and character:isRunning() then
        return 3
    end
    return 2
end

function ParkourFreeJumpValidation.resolveFacing(character)
    if not character then
        return nil
    end
    local forward = character:getForwardDirection()
    if not forward then
        return nil
    end

    local x = forward:getX()
    local y = forward:getY()
    local length = math.sqrt(x * x + y * y)
    if length < 0.0001 then
        return nil
    end
    x = x / length
    y = y / length

    local bestName
    local bestAlignment = -2
    for _, name in ipairs(DIRECTION_ORDER) do
        local direction = ParkourFreeJumpValidation.DIRECTIONS[name]
        local alignment = x * direction.dx + y * direction.dy
        if alignment > bestAlignment then
            bestName = name
            bestAlignment = alignment
        end
    end
    return bestName, bestAlignment
end

function ParkourFreeJumpValidation.findTargetFromOrigin(
    originX,
    originY,
    originZ,
    directionName,
    distance,
    allowedCharacter,
    startX,
    startY
)
    if not isEnabled() then
        return nil, "disabled"
    end

    distance = normalizeDistance(distance)
    local direction = ParkourFreeJumpValidation.DIRECTIONS[directionName]
    local cell = getCell()
    if not distance or not direction or not cell then
        return nil, "direction"
    end

    originX = math.floor(tonumber(originX) or -1000000)
    originY = math.floor(tonumber(originY) or -1000000)
    originZ = math.floor(tonumber(originZ) or -1000000)
    if originZ < 0 or originZ >= 32 then
        return nil, "height"
    end

    local sourceSquare = cell:getGridSquare(originX, originY, originZ)
    if not sourceSquare
        or sourceSquare:HasStairs()
        or sourceSquare:hasSlopedSurface()
        or sourceSquare:isVehicleIntersecting() then
        return nil, "source"
    end

    if startX == nil and allowedCharacter then
        startX = allowedCharacter:getX()
    end
    if startY == nil and allowedCharacter then
        startY = allowedCharacter:getY()
    end
    startX = tonumber(startX) or (originX + 0.5)
    startY = tonumber(startY) or (originY + 0.5)
    if math.floor(startX) ~= originX or math.floor(startY) ~= originY then
        return nil, "origin-position"
    end

    local rawTargetX = startX + direction.dx * distance
    local rawTargetY = startY + direction.dy * distance
    local targetSquareX = math.floor(rawTargetX)
    local targetSquareY = math.floor(rawTargetY)
    -- Keep the endpoint away from exact tile borders. This prevents tiny
    -- client/server floating-point differences from selecting adjacent tiles.
    local targetX = math.max(targetSquareX + 0.10, math.min(rawTargetX, targetSquareX + 0.90))
    local targetY = math.max(targetSquareY + 0.10, math.min(rawTargetY, targetSquareY + 0.90))
    local landingSquare = cell:getGridSquare(
        targetSquareX,
        targetSquareY,
        originZ
    )
    if not isLandingSquareClear(landingSquare, allowedCharacter) then
        return nil, "landing"
    end
    if not routeIsClear(cell, startX, startY, targetX, targetY, originZ) then
        return nil, "barrier"
    end

    return {
        originX = originX,
        originY = originY,
        originZ = originZ,
        startX = startX,
        startY = startY,
        targetX = targetX,
        targetY = targetY,
        targetZ = originZ,
        distance = distance,
        directionName = directionName,
        direction = direction,
        sourceSquare = sourceSquare,
        landingSquare = landingSquare,
    }
end

function ParkourFreeJumpValidation.findTarget(character, preferredDistance, minimumAlignment)
    if not character or character:isDead() or character:getVehicle() then
        return nil, "character"
    end

    local directionName, alignment = ParkourFreeJumpValidation.resolveFacing(character)
    if not directionName or alignment < (minimumAlignment or 0.90) then
        return nil, "alignment"
    end

    preferredDistance = normalizeDistance(preferredDistance)
        or ParkourFreeJumpValidation.getPreferredDistance(character)
    local startX = character:getX()
    local startY = character:getY()
    local lastReason = "landing"
    for distance = preferredDistance, ParkourFreeJumpValidation.MIN_DISTANCE, -1 do
        local target, reason = ParkourFreeJumpValidation.findTargetFromOrigin(
            math.floor(character:getX()),
            math.floor(character:getY()),
            math.floor(character:getZ()),
            directionName,
            distance,
            character,
            startX,
            startY
        )
        if target then
            return target
        end
        lastReason = reason or lastReason
    end
    return nil, lastReason
end

function ParkourFreeJumpValidation.moveCharacter(character, x, y, z)
    character:setX(x)
    character:setY(y)
    character:setZ(z)
    character:setLastX(x)
    character:setLastY(y)
    character:setLastZ(z)
end

return ParkourFreeJumpValidation
