local ParkourWallRunUpValidation = {}

-- TranslationData controls the clip's visual offset; the authoritative transfer
-- still targets the second tile behind the wall, which is the landing square.
ParkourWallRunUpValidation.TRAVEL_TILES = 2

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

local function hasOpeningOrFence(edgeSquare, north)
    if north then
        return hasFlag(edgeSquare, IsoFlagType.WindowN)
            or hasFlag(edgeSquare, IsoFlagType.DoorWallN)
            or hasFlag(edgeSquare, IsoFlagType.HoppableN)
            or hasFlag(edgeSquare, IsoFlagType.TallHoppableN)
    end

    return hasFlag(edgeSquare, IsoFlagType.WindowW)
        or hasFlag(edgeSquare, IsoFlagType.DoorWallW)
        or hasFlag(edgeSquare, IsoFlagType.HoppableW)
        or hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
end

local function hasFullWall(edgeSquare, north)
    if not edgeSquare or hasOpeningOrFence(edgeSquare, north) then
        return false
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
            or hasFlag(edgeSquare, IsoFlagType.cutN)
            or hasFlag(edgeSquare, IsoFlagType.WindowN)
            or hasFlag(edgeSquare, IsoFlagType.DoorWallN)
            or hasFlag(edgeSquare, IsoFlagType.HoppableN)
            or hasFlag(edgeSquare, IsoFlagType.TallHoppableN)
    end

    return hasFlag(edgeSquare, IsoFlagType.collideW)
        or hasFlag(edgeSquare, IsoFlagType.cutW)
        or hasFlag(edgeSquare, IsoFlagType.WindowW)
        or hasFlag(edgeSquare, IsoFlagType.DoorWallW)
        or hasFlag(edgeSquare, IsoFlagType.HoppableW)
        or hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
end

local function isLandingSquareClear(square, allowedCharacter)
    if not square
        or square:isSolid()
        or square:isSolidTrans()
        or square:HasStairs()
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
    if not sourceSquare or not frontSquare or sourceSquare:HasStairs() then
        return nil, "source"
    end

    local north = edgeUsesNorthFlags(directionName)
    local lowerEdgeSquare = getEdgeSquare(sourceSquare, frontSquare, directionName)
    if not hasFullWall(lowerEdgeSquare, north) then
        return nil, "wall"
    end

    local upperSource = cell:getGridSquare(originX, originY, originZ + 1)
    local roofEdgeSquare = cell:getGridSquare(
        originX + direction.dx,
        originY + direction.dy,
        originZ + 1
    )
    local landingSquare = cell:getGridSquare(
        originX + direction.dx * ParkourWallRunUpValidation.TRAVEL_TILES,
        originY + direction.dy * ParkourWallRunUpValidation.TRAVEL_TILES,
        originZ + 1
    )
    if not isLandingSquareClear(roofEdgeSquare, allowedCharacter)
        or not isLandingSquareClear(landingSquare, allowedCharacter) then
        return nil, "landing"
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
    if roofEdgeSquare:isBlockedTo(landingSquare)
        or roofEdgeSquare:testCollideSpecialObjects(landingSquare) then
        return nil, "roof-path"
    end

    return {
        originX = originX,
        originY = originY,
        originZ = originZ,
        targetX = landingSquare:getX() + 0.5,
        targetY = landingSquare:getY() + 0.5,
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

    local directionName, alignment = ParkourWallRunUpValidation.resolveFacing(character)
    if not directionName or alignment < (minimumAlignment or 0.70) then
        return nil, "alignment"
    end

    return ParkourWallRunUpValidation.findTargetFromOrigin(
        math.floor(character:getX()),
        math.floor(character:getY()),
        math.floor(character:getZ()),
        directionName,
        character
    )
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
