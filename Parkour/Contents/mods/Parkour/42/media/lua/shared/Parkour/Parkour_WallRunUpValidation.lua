local ParkourWallRunUpValidation = {}

-- The current clip travels roughly one tile. Landing on the first roof square
-- also matches how a ledge climb behaves and avoids a second-tile correction.
ParkourWallRunUpValidation.TRAVEL_TILES = 1

ParkourWallRunUpValidation.DIRECTIONS = {
    N = { dx = 0, dy = -1, iso = IsoDirections.N },
    S = { dx = 0, dy = 1, iso = IsoDirections.S },
    W = { dx = -1, dy = 0, iso = IsoDirections.W },
    E = { dx = 1, dy = 0, iso = IsoDirections.E },
}

local function hasFlag(square, flag)
    return square and flag and square:has(flag) or false
end

local function isEnabled()
    local settings = SandboxVars and SandboxVars.Parkour
    return not settings or settings.EnableWallRunUp ~= false
end

local function getEdgeSquare(sourceSquare, frontSquare, directionName)
    if directionName == "N" or directionName == "W" then
        return sourceSquare
    end
    return frontSquare
end

local function edgeUsesNorthFlags(directionName)
    return directionName == "N" or directionName == "S"
end

local function hasOpeningOrFence(sourceSquare, frontSquare, edgeSquare, north)
    if north then
        return hasFlag(edgeSquare, IsoFlagType.WindowN)
            or hasFlag(edgeSquare, IsoFlagType.windowN)
            or hasFlag(edgeSquare, IsoFlagType.DoorWallN)
            or hasFlag(edgeSquare, IsoFlagType.doorN)
            or hasFlag(edgeSquare, IsoFlagType.HoppableN)
            or hasFlag(edgeSquare, IsoFlagType.TallHoppableN)
            or sourceSquare:isWindowTo(frontSquare)
            or sourceSquare:isDoorTo(frontSquare)
            or sourceSquare:isHoppableTo(frontSquare)
    end

    return hasFlag(edgeSquare, IsoFlagType.WindowW)
        or hasFlag(edgeSquare, IsoFlagType.windowW)
        or hasFlag(edgeSquare, IsoFlagType.DoorWallW)
        or hasFlag(edgeSquare, IsoFlagType.doorW)
        or hasFlag(edgeSquare, IsoFlagType.HoppableW)
        or hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
        or sourceSquare:isWindowTo(frontSquare)
        or sourceSquare:isDoorTo(frontSquare)
        or sourceSquare:isHoppableTo(frontSquare)
end

local function hasFullWall(sourceSquare, frontSquare, edgeSquare, north)
    if not edgeSquare
        or hasOpeningOrFence(sourceSquare, frontSquare, edgeSquare, north) then
        return false
    end

    -- isWallTo() covers wall sprites that do not expose the exact flag variant
    -- used below. Openings and fences were deliberately excluded first.
    if sourceSquare:isWallTo(frontSquare) then
        return true
    end

    if north then
        return hasFlag(edgeSquare, IsoFlagType.collideN)
            or hasFlag(edgeSquare, IsoFlagType.WallN)
            or hasFlag(edgeSquare, IsoFlagType.WallNTrans)
            or hasFlag(edgeSquare, IsoFlagType.WallNW)
    end

    return hasFlag(edgeSquare, IsoFlagType.collideW)
        or hasFlag(edgeSquare, IsoFlagType.WallW)
        or hasFlag(edgeSquare, IsoFlagType.WallWTrans)
        or hasFlag(edgeSquare, IsoFlagType.WallNW)
end

local function hasAnyUpperBarrier(edgeSquare, north)
    if not edgeSquare then
        return false
    end

    if north then
        return hasFlag(edgeSquare, IsoFlagType.collideN)
            or hasFlag(edgeSquare, IsoFlagType.WindowN)
            or hasFlag(edgeSquare, IsoFlagType.windowN)
            or hasFlag(edgeSquare, IsoFlagType.DoorWallN)
            or hasFlag(edgeSquare, IsoFlagType.doorN)
            or hasFlag(edgeSquare, IsoFlagType.HoppableN)
            or hasFlag(edgeSquare, IsoFlagType.TallHoppableN)
    end

    return hasFlag(edgeSquare, IsoFlagType.collideW)
        or hasFlag(edgeSquare, IsoFlagType.WindowW)
        or hasFlag(edgeSquare, IsoFlagType.windowW)
        or hasFlag(edgeSquare, IsoFlagType.DoorWallW)
        or hasFlag(edgeSquare, IsoFlagType.doorW)
        or hasFlag(edgeSquare, IsoFlagType.HoppableW)
        or hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
end

local function isLandingSquareClear(square, allowedCharacter)
    if not square
        or square:isSolid()
        or square:isSolidTrans()
        or square:HasStairs()
        or square:hasSlopedSurface()
        or not square:TreatAsSolidFloor()
        or not square:canStand() then
        return false
    end

    local movingObjects = square:getMovingObjects()
    if not movingObjects then
        return true
    end
    for index = 0, movingObjects:size() - 1 do
        if movingObjects:get(index) ~= allowedCharacter then
            return false
        end
    end
    return true
end

local function getDirectionAlignment(character, directionName)
    local direction = ParkourWallRunUpValidation.DIRECTIONS[directionName]
    local forward = character and character:getForwardDirection()
    if not direction or not forward then
        return -1
    end
    return forward:getX() * direction.dx + forward:getY() * direction.dy
end

function ParkourWallRunUpValidation.getDirectionAlignment(character, directionName)
    return getDirectionAlignment(character, directionName)
end

function ParkourWallRunUpValidation.resolveFacing(character)
    if not character then
        return nil
    end

    local forward = character:getForwardDirection()
    if not forward then
        return nil
    end

    local x = forward:getX()
    local y = forward:getY()
    if math.abs(x) > math.abs(y) then
        return x >= 0 and "E" or "W", math.abs(x)
    end
    return y >= 0 and "S" or "N", math.abs(y)
end

function ParkourWallRunUpValidation.findTargetFromOrigin(
    originX,
    originY,
    originZ,
    directionName,
    allowedCharacter
)
    if not isEnabled() then
        return nil, "disabled"
    end

    local direction = ParkourWallRunUpValidation.DIRECTIONS[directionName]
    local cell = getCell()
    if not direction or not cell then
        return nil, "direction"
    end

    originX = math.floor(originX)
    originY = math.floor(originY)
    originZ = math.floor(originZ)
    if originZ < 0 or originZ >= 31 then
        return nil, "height"
    end

    local sourceSquare = cell:getGridSquare(originX, originY, originZ)
    local frontSquare = cell:getGridSquare(
        originX + direction.dx,
        originY + direction.dy,
        originZ
    )
    if not sourceSquare
        or not frontSquare
        or sourceSquare:HasStairs()
        or sourceSquare:hasSlopedSurface() then
        return nil, "source"
    end

    local north = edgeUsesNorthFlags(directionName)
    local lowerEdgeSquare = getEdgeSquare(sourceSquare, frontSquare, directionName)
    if not hasFullWall(sourceSquare, frontSquare, lowerEdgeSquare, north) then
        return nil, "wall"
    end

    local upperSource = cell:getGridSquare(originX, originY, originZ + 1)
    local roofEdgeSquare = cell:getGridSquare(
        originX + direction.dx,
        originY + direction.dy,
        originZ + 1
    )
    local landingSquare = roofEdgeSquare
    if not isLandingSquareClear(landingSquare, allowedCharacter) then
        return nil, "landing"
    end

    -- A floor or solid object directly above the source blocks the ascent even
    -- when the adjacent roof tile itself is otherwise valid.
    if upperSource and (
        upperSource:TreatAsSolidFloor()
        or upperSource:isSolid()
        or upperSource:isSolidTrans()
        or upperSource:HasStairs()
        or upperSource:hasSlopedSurface()
    ) then
        return nil, "headroom"
    end

    local upperEdgeSquare = getEdgeSquare(upperSource, roofEdgeSquare, directionName)
    if hasAnyUpperBarrier(upperEdgeSquare, north) then
        return nil, "roof-edge"
    end
    if upperSource and (
        upperSource:isBlockedTo(roofEdgeSquare)
        or upperSource:testCollideSpecialObjects(roofEdgeSquare)
    ) then
        return nil, "roof-edge"
    end

    local targetX = landingSquare:getX() + 0.5
    local targetY = landingSquare:getY() + 0.5
    if allowedCharacter then
        -- Keep the coordinate parallel to the wall. Snapping both axes to the
        -- tile centre creates a visible sideways twitch near corners.
        if direction.dx ~= 0 then
            targetY = math.max(
                landingSquare:getY() + 0.15,
                math.min(landingSquare:getY() + 0.85, allowedCharacter:getY())
            )
        else
            targetX = math.max(
                landingSquare:getX() + 0.15,
                math.min(landingSquare:getX() + 0.85, allowedCharacter:getX())
            )
        end
    end

    return {
        originX = originX,
        originY = originY,
        originZ = originZ,
        targetX = targetX,
        targetY = targetY,
        targetZ = landingSquare:getZ(),
        directionName = directionName,
        direction = direction,
        sourceSquare = sourceSquare,
        landingSquare = landingSquare,
    }
end

function ParkourWallRunUpValidation.findTarget(character, minimumAlignment)
    if not character or character:isDead() or character:getVehicle() then
        return nil, "character"
    end

    local primaryName, primaryAlignment = ParkourWallRunUpValidation.resolveFacing(character)
    local threshold = minimumAlignment or 0.70
    if not primaryName or primaryAlignment < threshold then
        return nil, "alignment"
    end

    local originX = math.floor(character:getX())
    local originY = math.floor(character:getY())
    local originZ = math.floor(character:getZ())
    local target, reason = ParkourWallRunUpValidation.findTargetFromOrigin(
        originX,
        originY,
        originZ,
        primaryName,
        character
    )
    if target then
        return target
    end

    -- Near a diagonal, try the other cardinal component. This avoids rejecting
    -- a real wall merely because the equally valid dominant axis had no wall.
    local forward = character:getForwardDirection()
    local secondaryName
    if primaryName == "N" or primaryName == "S" then
        secondaryName = forward:getX() >= 0 and "E" or "W"
    else
        secondaryName = forward:getY() >= 0 and "S" or "N"
    end
    if getDirectionAlignment(character, secondaryName) < threshold then
        return nil, reason
    end

    local secondaryTarget, secondaryReason = ParkourWallRunUpValidation.findTargetFromOrigin(
        math.floor(character:getX()),
        math.floor(character:getY()),
        math.floor(character:getZ()),
        secondaryName,
        character
    )
    return secondaryTarget, secondaryReason or reason
end

function ParkourWallRunUpValidation.moveCharacter(character, x, y, z)
    character:setX(x)
    character:setY(y)
    character:setZ(z)
    character:setLastX(x)
    character:setLastY(y)
    character:setLastZ(z)
end

return ParkourWallRunUpValidation
