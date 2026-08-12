local ParkourDodgeDirection = {}

local INPUT_DEAD_ZONE = 0.15

local function normalized(x, y, fallbackX, fallbackY)
    local length = math.sqrt(x * x + y * y)
    if length <= 0.0001 then
        return fallbackX, fallbackY
    end
    return x / length, y / length
end

local function screenToWorld(horizontal, vertical)
    -- PZ's movement bindings are screen-relative. On the isometric grid:
    -- W=(-1,-1), S=(1,1), A=(-1,1), D=(1,-1).
    return vertical + horizontal, vertical - horizontal
end

local function isBindingDown(binding)
    local key = getCore():getKey(binding)
    return key and key > 0 and isKeyDown(key)
end

local function getKeyboardMovement()
    local forward = isBindingDown("Forward")
    local backward = isBindingDown("Backward")
    local left = isBindingDown("Left")
    local right = isBindingDown("Right")
    local anyDown = forward or backward or left or right

    local horizontal = (right and 1 or 0) - (left and 1 or 0)
    local vertical = (backward and 1 or 0) - (forward and 1 or 0)
    local worldX, worldY = screenToWorld(horizontal, vertical)
    return worldX, worldY, anyDown
end

local function getJoypadMovement(character)
    local joypad = character:getJoypadBind()
    if not joypad or joypad < 0
        or not getJoypadMovementAxisX or not getJoypadMovementAxisY then
        return 0, 0, false
    end

    local horizontal = getJoypadMovementAxisX(joypad)
    local vertical = getJoypadMovementAxisY(joypad)
    local worldX, worldY = screenToWorld(horizontal, vertical)
    return worldX, worldY, math.sqrt(worldX * worldX + worldY * worldY) >= INPUT_DEAD_ZONE
end

local function getFacing(character)
    local facing = character:getForwardDirection()
    if facing then
        return normalized(facing:getX(), facing:getY(), 1, 0)
    end

    local angle = character:getAnimAngleRadians()
    return math.cos(angle), math.sin(angle)
end

local function classify(facingX, facingY, inputX, inputY)
    inputX, inputY = normalized(inputX, inputY, facingX, facingY)

    local rightX, rightY = -facingY, facingX
    local forwardAmount = inputX * facingX + inputY * facingY
    local rightAmount = inputX * rightX + inputY * rightY

    if math.abs(forwardAmount) >= math.abs(rightAmount) then
        if forwardAmount >= 0 then
            return "Forward", facingX, facingY, forwardAmount, rightAmount
        end
        return "Backward", -facingX, -facingY, forwardAmount, rightAmount
    end

    if rightAmount >= 0 then
        return "Right", rightX, rightY, forwardAmount, rightAmount
    end
    return "Left", -rightX, -rightY, forwardAmount, rightAmount
end

function ParkourDodgeDirection.resolve(character)
    local facingX, facingY = getFacing(character)

    -- Outside combat stance a standalone press always dodges forward.
    if not character:isAiming() then
        return "Forward", facingX, facingY, facingX, facingY, "facing", 1, 0
    end

    -- Read physical bindings directly. getInputMoveVector() is updated by the
    -- character input component and can be one frame stale in OnKeyStartPressed.
    local inputX, inputY, hasInput = getKeyboardMovement()
    local inputSource = "keyboard"
    if not hasInput then
        inputX, inputY, hasInput = getJoypadMovement(character)
        inputSource = "joypad"
    end

    if not hasInput or math.sqrt(inputX * inputX + inputY * inputY) < INPUT_DEAD_ZONE then
        return "Backward", -facingX, -facingY, facingX, facingY, "none", -1, 0
    end

    local direction, travelX, travelY, forwardAmount, rightAmount = classify(
        facingX,
        facingY,
        inputX,
        inputY
    )
    return direction, travelX, travelY, facingX, facingY,
        inputSource, forwardAmount, rightAmount
end

-- Pure helpers kept public for regression tests.
ParkourDodgeDirection.screenToWorld = screenToWorld
ParkourDodgeDirection.classify = classify

return ParkourDodgeDirection
