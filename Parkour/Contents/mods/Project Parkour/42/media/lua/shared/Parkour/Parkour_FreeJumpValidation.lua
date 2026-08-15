local ParkourFreeJumpValidation = {}

ParkourFreeJumpValidation.MIN_DISTANCE = 2
ParkourFreeJumpValidation.MAX_DISTANCE = 4

local DIAGONAL = 0.70710678118655
local SAMPLE_STEP = 0.05
local VEHICLE_PATH_HALF_WIDTH = 0.16
local LANDING_VEHICLE_CLEARANCE = 0.10
local MAX_ROUTE_VEHICLES = 1
-- Vanilla passenger cars, SUVs, off-roaders and pickups top out around 0.70.
-- Vans begin at 0.725, while ambulances and step vans are 0.89+, so 0.72 is
-- an intentionally conservative line between a car and a tall vehicle.
local MAX_JUMPABLE_VEHICLE_HEIGHT = 0.72
local MAX_JUMPABLE_VEHICLE_WIDTH = 1.05
local MAX_JUMPABLE_VEHICLE_LENGTH = 2.80
local MAX_JUMPABLE_VEHICLE_SPEED_KMH = 0.50
local MIN_UPRIGHT_VEHICLE_DOT = 0.90

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

local function debugLog(message)
    local settings = SandboxVars and SandboxVars.Parkour
    if settings and settings.DebugLogging then
        print("[Parkour FreeJump Validation] " .. message)
    end
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

local function airEdgeIsBlocked(fromSquare, toSquare, dx, dy)
    -- Empty upper levels frequently have no IsoGridSquare at all. Inspect the
    -- real side of the edge when one exists instead of treating missing air as
    -- an opaque wall.
    local edgeSquare
    local north
    if dx < 0 then
        edgeSquare = fromSquare
        north = false
    elseif dx > 0 then
        edgeSquare = toSquare
        north = false
    elseif dy < 0 then
        edgeSquare = fromSquare
        north = true
    else
        edgeSquare = toSquare
        north = true
    end
    if not edgeSquare then
        return false
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
        if lowFence then
            return false
        end
        return tallFence or window or door
            or hasFlag(edgeSquare, IsoFlagType.collideN)
            or hasFlag(edgeSquare, IsoFlagType.cutN)
            or hasFlag(edgeSquare, IsoFlagType.WallN)
            or hasFlag(edgeSquare, IsoFlagType.WallNTrans)
            or hasFlag(edgeSquare, IsoFlagType.WallNW)
    end

    lowFence = hasFlag(edgeSquare, IsoFlagType.HoppableW)
    tallFence = hasFlag(edgeSquare, IsoFlagType.TallHoppableW)
    window = hasFlag(edgeSquare, IsoFlagType.WindowW)
        or hasFlag(edgeSquare, IsoFlagType.windowW)
    door = hasFlag(edgeSquare, IsoFlagType.DoorWallW)
        or hasFlag(edgeSquare, IsoFlagType.doorW)
    if lowFence then
        return false
    end
    return tallFence or window or door
        or hasFlag(edgeSquare, IsoFlagType.collideW)
        or hasFlag(edgeSquare, IsoFlagType.cutW)
        or hasFlag(edgeSquare, IsoFlagType.WallW)
        or hasFlag(edgeSquare, IsoFlagType.WallWTrans)
        or hasFlag(edgeSquare, IsoFlagType.WallNW)
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
        if dx == 0 or dy == 0 then
            return not airEdgeIsBlocked(fromSquare, toSquare, dx, dy)
        end

        local horizontal = cell:getGridSquare(fromX + dx, fromY, z)
        local vertical = cell:getGridSquare(fromX, fromY + dy, z)
        return not airEdgeIsBlocked(fromSquare, horizontal, dx, 0)
            and not airEdgeIsBlocked(fromSquare, vertical, 0, dy)
            and not airEdgeIsBlocked(horizontal, toSquare, 0, dy)
            and not airEdgeIsBlocked(vertical, toSquare, dx, 0)
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

local function collectVehicles(cell)
    local vehicles = {}
    local cellVehicles = cell and cell:getVehicles()
    if not cellVehicles then
        return vehicles
    end

    local vehicleIterator = cellVehicles:iterator()
    while vehicleIterator:hasNext() do
        vehicles[#vehicles + 1] = vehicleIterator:next()
    end
    return vehicles
end

local function vehicleIsJumpable(vehicle, z)
    if not vehicle or math.floor(vehicle:getZ()) ~= z then
        return false
    end

    local script = vehicle:getScript()
    local extents = script and script:getExtents()
    local modelScale = script and script:getModelScale() or 0
    local width = extents and modelScale > 0 and extents:x() / modelScale or nil
    local height = extents and modelScale > 0 and extents:y() / modelScale or nil
    local length = extents and modelScale > 0 and extents:z() / modelScale or nil
    if not width
        or width > MAX_JUMPABLE_VEHICLE_WIDTH
        or height > MAX_JUMPABLE_VEHICLE_HEIGHT
        or length > MAX_JUMPABLE_VEHICLE_LENGTH then
        if script and extents and modelScale > 0 then
            debugLog(string.format(
                "Vehicle %s blocked by normalized size %.3f x %.3f x %.3f (scale %.3f)",
                tostring(script:getFullName()),
                width,
                height,
                length,
                modelScale
            ))
        else
            debugLog("Vehicle blocked: missing script/extents/model scale")
        end
        return false
    end

    -- A vehicle is only a predictable obstacle while it is fully stationary,
    -- upright and independent. Never jump a car carrying somebody or anything
    -- that is towing/being towed; those can start moving during the animation.
    if math.abs(vehicle:getCurrentSpeedKmHour())
            > MAX_JUMPABLE_VEHICLE_SPEED_KMH
        or vehicle:getUpVectorDot() < MIN_UPRIGHT_VEHICLE_DOT
        or vehicle:getVehicleTowing()
        or vehicle:getVehicleTowedBy() then
        debugLog(string.format(
            "Vehicle %s blocked by state speed=%.3f up=%.3f towing=%s towed=%s",
            tostring(script:getFullName()),
            vehicle:getCurrentSpeedKmHour(),
            vehicle:getUpVectorDot(),
            tostring(vehicle:getVehicleTowing() ~= nil),
            tostring(vehicle:getVehicleTowedBy() ~= nil)
        ))
        return false
    end

    for seat = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(seat) then
            debugLog(string.format(
                "Vehicle %s blocked: occupied seat %d",
                tostring(script:getFullName()),
                seat
            ))
            return false
        end
    end
    return true
end

local function vehicleTouchesPath(vehicle, x, y, perpendicularX, perpendicularY)
    if vehicle:isInBounds(x, y) then
        return true
    end

    local offsetX = perpendicularX * VEHICLE_PATH_HALF_WIDTH
    local offsetY = perpendicularY * VEHICLE_PATH_HALF_WIDTH
    return vehicle:isInBounds(x + offsetX, y + offsetY)
        or vehicle:isInBounds(x - offsetX, y - offsetY)
end

local function vehicleTouchesEndpoint(vehicle, x, y, z, clearance)
    if not vehicle or math.floor(vehicle:getZ()) ~= z then
        return false
    end
    if vehicle:isInBounds(x, y) then
        return true
    end

    clearance = clearance or 0
    if clearance <= 0 then
        return false
    end
    return vehicle:isInBounds(x + clearance, y)
        or vehicle:isInBounds(x - clearance, y)
        or vehicle:isInBounds(x, y + clearance)
        or vehicle:isInBounds(x, y - clearance)
end

local function anyVehicleTouchesEndpoint(vehicles, x, y, z, clearance)
    for index = 1, #vehicles do
        if vehicleTouchesEndpoint(vehicles[index], x, y, z, clearance) then
            return true
        end
    end
    return false
end

local function routeIsClear(cell, startX, startY, targetX, targetY, z, vehicles)
    local deltaX = targetX - startX
    local deltaY = targetY - startY
    local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local samples = math.max(1, math.ceil(length / SAMPLE_STEP))
    local perpendicularX = -deltaY / length
    local perpendicularY = deltaX / length
    vehicles = vehicles or collectVehicles(cell)
    local routeVehicles = {}
    local routeVehicleCount = 0
    local crossesUnsupportedFloor = false
    local previousX = math.floor(startX)
    local previousY = math.floor(startY)

    for index = 1, samples do
        local progress = index / samples
        local sampleX = startX + deltaX * progress
        local sampleY = startY + deltaY * progress
        local squareX = math.floor(sampleX)
        local squareY = math.floor(sampleY)
        local sampleSquare = cell:getGridSquare(squareX, squareY, z)
        if not sampleSquare or not sampleSquare:TreatAsSolidFloor() then
            crossesUnsupportedFloor = true
        end

        -- Vehicle collision is evaluated against its rotated footprint rather
        -- than the whole tile. Only one low, stationary vehicle may occupy the
        -- route; source and landing tiles remain strictly vehicle-free.
        for vehicleIndex = 1, #vehicles do
            local vehicle = vehicles[vehicleIndex]
            if math.floor(vehicle:getZ()) == z
                and vehicleTouchesPath(
                    vehicle,
                    sampleX,
                    sampleY,
                    perpendicularX,
                    perpendicularY
                ) then
                if not vehicleIsJumpable(vehicle, z) then
                    return false, false
                end
                if not routeVehicles[vehicle] then
                    routeVehicles[vehicle] = true
                    routeVehicleCount = routeVehicleCount + 1
                    if routeVehicleCount > MAX_ROUTE_VEHICLES then
                        return false, false
                    end
                end
            end
        end

        if squareX ~= previousX or squareY ~= previousY then
            local crossedSquare = cell:getGridSquare(squareX, squareY, z)
            if crossedSquare and (
                crossedSquare:HasStairs()
                or crossedSquare:hasSlopedSurface()
            ) then
                return false, false
            end
            if not transitionIsClear(
                cell,
                previousX,
                previousY,
                squareX,
                squareY,
                z
            ) then
                return false, false
            end
            previousX = squareX
            previousY = squareY
        end
    end
    return true, crossesUnsupportedFloor, routeVehicleCount > 0
end

local function isLandingSquareClear(
    square,
    allowedCharacter,
    vehicles,
    targetX,
    targetY,
    z
)
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
    if movingObjects then
        for index = 0, movingObjects:size() - 1 do
            if movingObjects:get(index) ~= allowedCharacter then
                return false
            end
        end
    end
    if anyVehicleTouchesEndpoint(
        vehicles,
        targetX,
        targetY,
        z,
        LANDING_VEHICLE_CLEARANCE
    ) then
        return false
    end
    return true
end

local function isAirEndpointClear(square, allowedCharacter, vehicles, x, y, z)
    -- A missing IsoGridSquare on an upper level is ordinary empty air, not an
    -- invalid destination. Only an existing blocking square rejects the drop.
    if square and (
        square:isSolid()
        or square:isSolidTrans()
        or square:HasStairs()
        or square:hasSlopedSurface()
        or square:TreatAsSolidFloor()
    ) then
        return false
    end

    local movingObjects = square and square:getMovingObjects()
    if movingObjects then
        for index = 0, movingObjects:size() - 1 do
            if movingObjects:get(index) ~= allowedCharacter then
                return false
            end
        end
    end
    return not anyVehicleTouchesEndpoint(
        vehicles,
        x,
        y,
        z,
        LANDING_VEHICLE_CLEARANCE
    )
end

local function findLowerLanding(
    cell,
    x,
    y,
    originZ,
    allowedCharacter,
    vehicles
)
    local squareX = math.floor(x)
    local squareY = math.floor(y)
    for z = originZ - 1, 0, -1 do
        local square = cell:getGridSquare(squareX, squareY, z)
        if square and square:TreatAsSolidFloor() then
            if isLandingSquareClear(
                square,
                allowedCharacter,
                vehicles,
                x,
                y,
                z
            ) then
                return square
            end
            -- A blocked floor catches the fall; do not search through it for a
            -- second floor farther below.
            return nil
        end
        if square and (square:isSolid() or square:isSolidTrans()) then
            return nil
        end
    end
    return nil
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
        or sourceSquare:hasSlopedSurface() then
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
    local vehicles = collectVehicles(cell)
    if anyVehicleTouchesEndpoint(vehicles, startX, startY, originZ, 0) then
        return nil, "source-vehicle"
    end

    local rawTargetX = startX + direction.dx * distance
    local rawTargetY = startY + direction.dy * distance
    local targetSquareX = math.floor(rawTargetX)
    local targetSquareY = math.floor(rawTargetY)
    -- Keep the endpoint away from exact tile borders. This prevents tiny
    -- client/server floating-point differences from selecting adjacent tiles.
    local targetX = math.max(targetSquareX + 0.10, math.min(rawTargetX, targetSquareX + 0.90))
    local targetY = math.max(targetSquareY + 0.10, math.min(rawTargetY, targetSquareY + 0.90))
    local sameLevelSquare = cell:getGridSquare(
        targetSquareX,
        targetSquareY,
        originZ
    )
    local landingSquare = sameLevelSquare
    local dropLanding = false
    if not isLandingSquareClear(
        sameLevelSquare,
        allowedCharacter,
        vehicles,
        targetX,
        targetY,
        originZ
    ) then
        -- An existing but unsafe same-level floor must still block the jump.
        -- Only a genuinely open edge may fall through to a clear floor below.
        if sameLevelSquare and sameLevelSquare:TreatAsSolidFloor() then
            return nil, "landing"
        end
        if not isAirEndpointClear(
            sameLevelSquare,
            allowedCharacter,
            vehicles,
            targetX,
            targetY,
            originZ
        ) then
            return nil, "landing"
        end
        landingSquare = findLowerLanding(
            cell,
            targetX,
            targetY,
            originZ,
            allowedCharacter,
            vehicles
        )
        if not landingSquare then
            return nil, "landing"
        end
        dropLanding = true
    end
    local routeClear, requiresDeferredTransfer, crossesLowVehicle = routeIsClear(
        cell,
        startX,
        startY,
        targetX,
        targetY,
        originZ,
        vehicles
    )
    if not routeClear then
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
        -- Movement remains at the take-off Z for the authored horizontal arc.
        -- For a roof drop, vanilla falling begins only after the final event.
        targetZ = originZ,
        landingZ = landingSquare:getZ(),
        dropLanding = dropLanding,
        requiresDeferredTransfer = requiresDeferredTransfer,
        crossesLowVehicle = crossesLowVehicle == true,
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
