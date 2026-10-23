--[[
	InputController
	One place that turns keyboard, gamepad and touch into riding intents.

	- Steering, tuck and brake are axes combined from WASD/arrow keys, the left gamepad stick,
	  and on touch the default thumbstick (if the PlayerModule exists) or our own buttons.
	- Discrete actions (jump, camera toggle, reset, zoom) are bound with ContextActionService
	  only while riding, at high priority so they override the default humanoid jump.
	- Camera look input (right-mouse drag, right thumbstick, touch swipe) accumulates until the
	  camera consumes it each frame.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputConfig = require(ReplicatedStorage.Shared.Config.InputConfig)
local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local player = Players.LocalPlayer

local InputController = {}
InputController.CameraToggled = Signal.new()
InputController.ResetRequested = Signal.new()

local STICK_DEADZONE = 0.15

local controls = nil
local ridingEnabled = false
local jumpQueued = false
local jumpHeld = false
local lookDelta = Vector2.zero
local zoomDelta = 0
local gamepadLook = Vector2.zero
local gamepadMove = Vector2.zero
local touchMove = { Left = false, Right = false, Tuck = false, Brake = false }
local rightMouseDown = false
local lookTouch: InputObject? = nil

-- The PlayerModule is optional (some places don't ship it). Never yield here: this runs
-- inside the physics step.
local function getControls()
	if controls == nil then
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		if not playerModule then
			return nil
		end
		local ok, module = pcall(require, playerModule)
		controls = if ok then module:GetControls() else false
	end
	return controls or nil
end

local function anyKeyDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function actionName(name: string): string
	return "Downhill" .. name
end

local handlers = {
	Jump = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			jumpQueued = true
			jumpHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			jumpHeld = false
		end
	end,
	ToggleCamera = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			InputController.CameraToggled:Fire()
		end
	end,
	Reset = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			InputController.ResetRequested:Fire()
		end
	end,
	ZoomIn = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			zoomDelta -= 1
		end
	end,
	ZoomOut = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			zoomDelta += 1
		end
	end,
}

local function bindActions()
	for name, action in InputConfig.Actions do
		local handler = handlers[name]
		if not handler then
			continue
		end
		ContextActionService:BindActionAtPriority(actionName(name), function(_, state)
			handler(state)
			return Enum.ContextActionResult.Sink
		end, action.TouchButton ~= nil, InputConfig.ActionPriority, table.unpack(action.Keys))

		if action.TouchButton then
			ContextActionService:SetTitle(actionName(name), action.TouchButton.Title)
			ContextActionService:SetPosition(actionName(name), action.TouchButton.Position)
		end
	end
end

-- On-screen steer/tuck/brake buttons, only for touch devices without the default thumbstick.
local function bindTouchMoveButtons()
	if not UserInputService.TouchEnabled or getControls() then
		return
	end
	for name, button in InputConfig.TouchMoveButtons do
		ContextActionService:BindAction(actionName(name), function(_, state)
			touchMove[name] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle(actionName(name), button.Title)
		ContextActionService:SetPosition(actionName(name), button.Position)
	end
end

local function unbindActions()
	for name in InputConfig.Actions do
		ContextActionService:UnbindAction(actionName(name))
	end
	for name in InputConfig.TouchMoveButtons do
		ContextActionService:UnbindAction(actionName(name))
		touchMove[name] = false
	end
end

function InputController.SetRidingEnabled(enabled: boolean)
	if enabled == ridingEnabled then
		return
	end
	ridingEnabled = enabled
	jumpQueued = false
	jumpHeld = false
	if enabled then
		bindActions()
		bindTouchMoveButtons()
	else
		unbindActions()
	end
end

-- Combined move vector: X = right, Z = backward (W gives Z = -1), each axis clamped to [-1, 1].
function InputController.GetMoveVector(): Vector3
	local x, z = 0, 0

	if not UserInputService:GetFocusedTextBox() then
		local keys = InputConfig.MoveKeys
		x += (if anyKeyDown(keys.Right) then 1 else 0) - (if anyKeyDown(keys.Left) then 1 else 0)
		z += (if anyKeyDown(keys.Back) then 1 else 0) - (if anyKeyDown(keys.Forward) then 1 else 0)
	end

	if gamepadMove.Magnitude > STICK_DEADZONE then
		x += gamepadMove.X
		z -= gamepadMove.Y
	end

	x += (if touchMove.Right then 1 else 0) - (if touchMove.Left then 1 else 0)
	z += (if touchMove.Brake then 1 else 0) - (if touchMove.Tuck then 1 else 0)

	local c = getControls()
	if c and UserInputService.TouchEnabled then
		-- Default mobile thumbstick, when the place has the PlayerModule.
		local moduleVector = c:GetMoveVector()
		x += moduleVector.X
		z += moduleVector.Z
	end

	return Vector3.new(math.clamp(x, -1, 1), 0, math.clamp(z, -1, 1))
end

function InputController.GetSteer(): number
	return math.clamp(InputController.GetMoveVector().X, -1, 1)
end

function InputController.IsTucking(): boolean
	return InputController.GetMoveVector().Z < -InputConfig.TuckThreshold
end

function InputController.IsBraking(): boolean
	return InputController.GetMoveVector().Z > InputConfig.BrakeThreshold
end

function InputController.ConsumeJump(): boolean
	local queued = jumpQueued
	jumpQueued = false
	return queued
end

function InputController.IsJumpHeld(): boolean
	return jumpHeld
end

function InputController.IsRightMouseDown(): boolean
	return rightMouseDown
end

function InputController.HasActiveLookInput(): boolean
	return rightMouseDown or lookTouch ~= nil or gamepadLook.Magnitude > 0.15
end

function InputController.ConsumeLook(dt: number): Vector2
	local stick = gamepadLook
	if stick.Magnitude < 0.15 then
		stick = Vector2.zero
	end
	local delta = lookDelta + Vector2.new(stick.X, -stick.Y) * CameraConfig.GamepadLookSpeed * dt
	lookDelta = Vector2.zero
	return delta
end

function InputController.ConsumeZoom(): number
	local delta = zoomDelta
	zoomDelta = 0
	return delta
end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			rightMouseDown = true
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed and ridingEnabled then
			local viewport = workspace.CurrentCamera.ViewportSize
			if input.Position.X > viewport.X * 0.5 and lookTouch == nil then
				lookTouch = input
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightMouseDown = false
		elseif input == lookTouch then
			lookTouch = nil
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseMovement then
			if rightMouseDown then
				lookDelta += Vector2.new(input.Delta.X, input.Delta.Y)
			end
		elseif inputType == Enum.UserInputType.MouseWheel then
			if not processed then
				zoomDelta -= input.Position.Z
			end
		elseif input == lookTouch then
			lookDelta += Vector2.new(input.Delta.X, input.Delta.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			gamepadMove = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
end

return InputController
