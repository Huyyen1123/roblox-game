--[[
	CameraController
	Owns the camera while riding. Each mode is a module with new/Enter/Exit/Update and a Fov
	table; adding a mode (e.g. replay or spectator) means adding it to the Modes table and to
	CameraConfig.ModeOrder. Speed-based field of view is handled here for every mode.

	When the movement controller is inactive the default Roblox camera is restored.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Cameras = script.Parent.Parent.Cameras
local CameraMath = require(Cameras.CameraMath)

local RENDER_STEP_NAME = "DownhillCamera"
local DEFAULT_FOV = 70

local CameraController = {}
CameraController.ModeChanged = Signal.new()

local Modes = {
	ThirdPerson = require(Cameras.ThirdPersonCamera),
	FirstPerson = require(Cameras.FirstPersonCamera),
}

local Movement
local Input
local instances = {}
local currentModeName = CameraConfig.DefaultMode
local running = false
local raycastParams = RaycastParams.new()
local frameInput = { Look = Vector2.zero, Zoom = 0, Looking = false, RaycastParams = raycastParams }

local function getMode()
	local mode = instances[currentModeName]
	if not mode then
		mode = Modes[currentModeName].new()
		instances[currentModeName] = mode
	end
	return mode
end

local function refreshRaycastParams(character: Model?)
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = if character then { character } else {}
	raycastParams.RespectCanCollide = true
	if PhysicsService:IsCollisionGroupRegistered(Constants.RiderCollisionGroup) then
		raycastParams.CollisionGroup = Constants.RiderCollisionGroup
	end
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local state = Movement.State
	if not state.Root then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	if Input.IsRightMouseDown() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end

	frameInput.Look = Input.ConsumeLook(dt)
	frameInput.Zoom = Input.ConsumeZoom()
	frameInput.Looking = Input.HasActiveLookInput()

	local mode = getMode()
	mode:Update(dt, camera, state, frameInput)

	local fov = mode.Fov
	local speedT = math.clamp(state.Speed / fov.SpeedForMax, 0, 1)
	local targetFov = fov.Base + (fov.Max - fov.Base) * speedT * speedT
	camera.FieldOfView += (targetFov - camera.FieldOfView) * CameraMath.ExpAlpha(fov.Responsiveness, dt)
end

local function start()
	if running then
		return
	end
	running = true
	refreshRaycastParams(Movement.State.Character)
	getMode():Enter(Workspace.CurrentCamera, Movement.State)
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

local function stop()
	if not running then
		return
	end
	running = false
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	getMode():Exit(Workspace.CurrentCamera, Movement.State)

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = DEFAULT_FOV
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function CameraController.GetModeName(): string
	return currentModeName
end

function CameraController.SetMode(name: string)
	if not Modes[name] or name == currentModeName then
		return
	end
	local camera = Workspace.CurrentCamera
	if running then
		getMode():Exit(camera, Movement.State)
	end
	currentModeName = name
	if running then
		getMode():Enter(camera, Movement.State)
	end
	CameraController.ModeChanged:Fire(name)
end

function CameraController.Toggle()
	local order = CameraConfig.ModeOrder
	local index = table.find(order, currentModeName) or 0
	CameraController.SetMode(order[index % #order + 1])
end

function CameraController.Start(movementController, inputController)
	Movement = movementController
	Input = inputController

	Input.CameraToggled:Connect(CameraController.Toggle)
	Movement.Activated:Connect(start)
	Movement.Deactivated:Connect(stop)
	if Movement.IsActive() then
		start()
	end
end

return CameraController
