--[[
	InputController
	Turns keyboard, gamepad and touch into riding actions. Gameplay code asks for actions
	("is Tuck held?", "was Jump released?") and never reads keys directly; bindings live in
	InputConfig.

	- Steer: axis from keys, the left stick, the default mobile thumbstick (when the place has
	  a PlayerModule) or touch buttons.
	- Held actions (Tuck, Brake, Push, tweaks, grabs) and discrete actions (Jump, camera, reset, zoom) are bound
	  through ContextActionService only while riding, at high priority, so they override the
	  default humanoid jump and shift-lock.
	- Jump reports press and release separately so the movement code can charge jumps.
	- Camera look input (right-mouse drag, right stick, touch swipe) accumulates until the camera
	  consumes it each frame.
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

local controls = nil
local ridingEnabled = false

-- Held action name -> set of inputs currently holding it (several keys can share one action)
local heldInputs: { [string]: { [any]: boolean } } = {}
local jumpHeld = false
local jumpReleaseQueued = false

local lookDelta = Vector2.zero
local zoomDelta = 0
local gamepadLook = Vector2.zero
local gamepadMove = Vector2.zero
local touchSteer = { Left = false, Right = false }
local rightMouseDown = false
local lookTouch: InputObject? = nil

for name in InputConfig.Held do
	heldInputs[name] = {}
end

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

local function isDown(state: Enum.UserInputState): boolean
	return state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
end

local actionHandlers = {
	Jump = function(state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			jumpHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if jumpHeld then
				jumpReleaseQueued = true
			end
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

local function bind(name: string, handler, binding)
	ContextActionService:BindActionAtPriority(actionName(name), function(_, state, input)
		handler(state, input)
		return Enum.ContextActionResult.Sink
	end, binding.TouchButton ~= nil, InputConfig.ActionPriority, table.unpack(binding.Keys or {}))
	if binding.TouchButton then
		ContextActionService:SetTitle(actionName(name), binding.TouchButton.Title)
		ContextActionService:SetPosition(actionName(name), binding.TouchButton.Position)
	end
end

local function bindActions()
	for name, binding in InputConfig.Actions do
		bind(name, actionHandlers[name], binding)
	end

	for name, binding in InputConfig.Held do
		local holders = heldInputs[name]
		bind(name, function(state, input)
			-- Touch buttons arrive as one InputObject per press; keys arrive per KeyCode.
			local key = if input.UserInputType == Enum.UserInputType.Touch then input else input.KeyCode
			holders[key] = if isDown(state) then true else nil
		end, binding)
	end

	-- On-screen steer buttons only for touch devices without the default thumbstick.
	if UserInputService.TouchEnabled and not getControls() then
		for name, button in InputConfig.TouchSteerButtons do
			bind("Steer" .. name, function(state)
				touchSteer[name] = isDown(state)
			end, { TouchButton = button })
		end
	end
end

local function unbindActions()
	for name in InputConfig.Actions do
		ContextActionService:UnbindAction(actionName(name))
	end
	for name in InputConfig.Held do
		ContextActionService:UnbindAction(actionName(name))
		table.clear(heldInputs[name])
	end
	for name in InputConfig.TouchSteerButtons do
		ContextActionService:UnbindAction(actionName("Steer" .. name))
		touchSteer[name] = false
	end
end

function InputController.SetRidingEnabled(enabled: boolean)
	if enabled == ridingEnabled then
		return
	end
	ridingEnabled = enabled
	jumpHeld = false
	jumpReleaseQueued = false
	if enabled then
		bindActions()
	else
		unbindActions()
	end
end

-- Steering in [-1, 1], positive = right.
function InputController.GetSteer(): number
	local steer = 0
	if not UserInputService:GetFocusedTextBox() then
		steer += (if anyKeyDown(InputConfig.Steer.Right) then 1 else 0) - (if anyKeyDown(InputConfig.Steer.Left) then 1 else 0)
	end
	if math.abs(gamepadMove.X) > InputConfig.StickDeadzone then
		steer += gamepadMove.X
	end
	steer += (if touchSteer.Right then 1 else 0) - (if touchSteer.Left then 1 else 0)

	local c = getControls()
	if c and UserInputService.TouchEnabled then
		steer += c:GetMoveVector().X
	end
	return math.clamp(steer, -1, 1)
end

-- Clears every held input; used when the window loses focus, because the release events for
-- keys held at that moment never arrive (e.g. Cmd+Shift+4 or alt-tabbing leaves Shift "down").
local function releaseAll()
	for _, holders in heldInputs do
		table.clear(holders)
	end
	if jumpHeld then
		jumpHeld = false
		jumpReleaseQueued = false
	end
end

function InputController.IsHeld(name: string): boolean
	local holders = heldInputs[name]
	-- Self-heal keyboard keys whose release was missed: trust the live key state.
	for key in holders do
		if typeof(key) == "EnumItem" and not string.find(key.Name, "^Button") and not UserInputService:IsKeyDown(key) then
			holders[key] = nil
		end
	end
	if next(holders) ~= nil then
		return true
	end
	-- Analog alternatives
	if name == "Push" then
		if gamepadMove.Y > InputConfig.StickPushThreshold then
			return true
		end
		local c = getControls()
		if c and UserInputService.TouchEnabled and c:GetMoveVector().Z < -InputConfig.StickPushThreshold then
			return true
		end
	elseif name == "TailTweak" then
		if gamepadMove.Y < -InputConfig.StickPushThreshold then
			return true
		end
	end
	return false
end

function InputController.IsJumpHeld(): boolean
	return jumpHeld
end

-- True once after the jump input is released.
function InputController.ConsumeJumpRelease(): boolean
	local released = jumpReleaseQueued
	jumpReleaseQueued = false
	return released
end

function InputController.IsRightMouseDown(): boolean
	return rightMouseDown
end

function InputController.HasActiveLookInput(): boolean
	return rightMouseDown or lookTouch ~= nil or gamepadLook.Magnitude > InputConfig.StickDeadzone
end

function InputController.ConsumeLook(dt: number): Vector2
	local stick = gamepadLook
	if stick.Magnitude < InputConfig.StickDeadzone then
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
	UserInputService.WindowFocusReleased:Connect(releaseAll)

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
