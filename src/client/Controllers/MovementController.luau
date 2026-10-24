--[[
	MovementController
	Downhill movement for the local character. This module coordinates; the work happens in:
	  Movement/Rig          constraints + Humanoid state
	  Movement/GroundProbe  finding the snow under the rider
	  Movement/Physics      one integration step (grounded / airborne / jump velocity)
	  Movement/Landing      judging touchdowns

	Each PreSimulation step: read intent from the InputController, detect impacts, probe the
	ground, judge landings, integrate, handle charged jumps, then command the constraints.

	Modes (state.Mode):
	  Inactive   no sport selected / no character
	  Frozen     briefly after a reset
	  Grounded   riding normally
	  Stumbling  grounded with reduced control after a poor landing or a bump
	  Airborne   in the air
	  Wipeout    severe impact: sliding to a stop, then a short stumble while getting up

	The client simulates its own character for responsiveness; the server owns spawning,
	resets and (from Phase 4) race validation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Movement = script.Parent.Parent.Movement
local Rig = require(Movement.Rig)
local GroundProbe = require(Movement.GroundProbe)
local Physics = require(Movement.Physics)
local Landing = require(Movement.Landing)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local WORLD_UP = Vector3.yAxis

local MovementController = {}
MovementController.Activated = Signal.new()
MovementController.Deactivated = Signal.new()
MovementController.ModeChanged = Signal.new() -- (newMode, oldMode)
MovementController.Landed = Signal.new() -- (quality: "Clean" | "Hard" | "Sketchy", impactSpeed, airTime)
MovementController.Stumbled = Signal.new() -- (reason: "Landing" | "Bump" | "Recovery")
MovementController.Crashed = Signal.new() -- wipeout (reason: "Collision" | "BadLanding")
MovementController.Jumped = Signal.new() -- (charge: number 0..1)
MovementController.Reset = Signal.new()

-- Snapshot read by the camera, HUD and dev tools every frame.
local state = {
	Active = false,
	Mode = "Inactive",
	Velocity = Vector3.zero,
	Speed = 0,
	Heading = Vector3.new(0, 0, -1), -- flat (horizontal) facing direction
	Forward = Vector3.new(0, 0, -1), -- heading projected onto the ground plane
	Up = WORLD_UP, -- smoothed ground normal
	Steer = 0,
	Tuck = 0, -- 0..1, eased
	Tucking = false,
	Braking = false,
	Grounded = false,
	JumpCharge = 0, -- 0..1 while Jump is held on the ground
	AirTime = 0,
	SlopeAngle = 0,
	CoastDeceleration = 0,
	Root = nil :: BasePart?,
	Character = nil :: Model?,
}
MovementController.State = state

local Input -- InputController, injected in Start

-- Per-character runtime
local character: Model?
local root: BasePart?
local rig
local stepConnection: RBXScriptConnection?
local raycastParams: RaycastParams?
local rideHeight = 3
local stats = SportConfig.BaseStats

local lastCommand: Vector3? = nil
local timeSinceGrounded = math.huge
local jumpCooldown = 0
local jumpCharge = 0
local groundLock = 0
local impactGrace = 0
local frozenTimer = 0
local stumbleTimer = 0
local stumbleDuration = 1
local wipeoutTimer = 0
local skipLandingCheck = false
local lastResetRequest = 0
local clock = 0
local debugCounters = { Bumps = 0, Jumps = 0, Stumbles = 0, Wipeouts = 0 }

local function expAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function setMode(mode: string)
	if state.Mode ~= mode then
		local old = state.Mode
		state.Mode = mode
		MovementController.ModeChanged:Fire(mode, old)
	end
end

local function getKillY(): number?
	local course = Workspace:FindFirstChild(Constants.CourseFolderName)
	return course and course:GetAttribute(Constants.Attributes.KillY)
end

function MovementController.RequestReset()
	local now = os.clock()
	if now - lastResetRequest < Config.ResetCooldown then
		return
	end
	lastResetRequest = now
	Remotes.RequestReset:FireServer()
end

----------------------------------------------------------------------------------------------
-- Stumble and wipeout
----------------------------------------------------------------------------------------------

local function startStumble(reason: string, duration: number?)
	if wipeoutTimer > 0 then
		return
	end
	duration = duration or Config.Stumble.Duration
	if reason ~= "Recovery" then
		state.Velocity *= 1 - Config.Stumble.SpeedLoss
	end
	stumbleDuration = duration
	stumbleTimer = math.max(stumbleTimer, duration)
	jumpCharge = 0
	debugCounters.Stumbles += 1
	MovementController.Stumbled:Fire(reason)
end

local function startWipeout(reason: string)
	if wipeoutTimer > 0 then
		return
	end
	wipeoutTimer = Config.Wipeout.Duration
	stumbleTimer = 0
	jumpCharge = 0
	state.CoastDeceleration = Config.Wipeout.Deceleration
	impactGrace = Config.Wipeout.Duration
	debugCounters.Wipeouts += 1
	MovementController.Crashed:Fire(reason)
end

local function endWipeout()
	wipeoutTimer = 0
	state.CoastDeceleration = 0
	state.Heading = Physics.Flatten(state.Velocity) or state.Heading
	startStumble("Recovery", Config.Wipeout.RecoveryStumble)
end

----------------------------------------------------------------------------------------------
-- Step
----------------------------------------------------------------------------------------------

local function readIntent(dt: number)
	local canAct = wipeoutTimer <= 0
	local steady = canAct and stumbleTimer <= 0

	state.Steer += (Input.GetSteer() - state.Steer) * expAlpha(Config.SteerResponse, dt)

	local tuckTarget = if steady and Input.IsHeld("Tuck") then 1 else 0
	local tuckTime = if tuckTarget > state.Tuck then Config.Tuck.InTime else Config.Tuck.OutTime
	state.Tuck = math.clamp(state.Tuck + math.sign(tuckTarget - state.Tuck) * dt / tuckTime, 0, 1)
	state.Tucking = state.Tuck > 0.5
	state.Braking = canAct and Input.IsHeld("Brake")

	return {
		Steer = state.Steer * (if stumbleTimer > 0 then Config.Stumble.SteerMultiplier else 1),
		Tuck = state.Tuck,
		Brake = state.Braking,
		Push = canAct and Input.IsHeld("Push"),
		Coast = not canAct,
	}
end

-- Engine resolved a collision: compare what we asked for with what we got.
local function detectImpact(): boolean
	local actual = root.AssemblyLinearVelocity
	if not lastCommand or impactGrace > 0 or (lastCommand - actual).Magnitude <= Config.Impact.Deviation then
		return false
	end

	local speedLoss = lastCommand.Magnitude - actual.Magnitude
	state.Velocity = actual
	debugCounters.Bumps += 1
	if lastCommand.Magnitude > Config.Impact.WipeoutMinSpeed and speedLoss > Config.Impact.WipeoutSpeedLoss then
		startWipeout("Collision")
		return true
	elseif speedLoss > Config.Impact.StumbleSpeedLoss then
		startStumble("Bump")
	end
	return false
end

local function touchDown(normal: Vector3)
	if skipLandingCheck then
		skipLandingCheck = false
		state.Velocity = Physics.ProjectOnPlane(state.Velocity, normal)
		return
	end

	local result = Landing.Evaluate(state.Velocity, state.Heading, normal, stats, Config)
	state.Velocity = result.Velocity
	-- The landing deliberately removes velocity into the surface; don't read that as an impact.
	impactGrace = math.max(impactGrace, Config.Impact.Grace)

	if result.Quality == "Wipeout" then
		startWipeout("BadLanding")
		return
	end
	if result.Heading then
		state.Heading = result.Heading
	end
	MovementController.Landed:Fire(result.Quality, result.Impact, state.AirTime)
	if result.Stumble then
		startStumble("Landing")
	end
end

local function updateJump(dt: number, ground, command: Vector3): Vector3
	local eligible = wipeoutTimer <= 0 and stumbleTimer <= 0 and jumpCooldown <= 0
	local onGround = timeSinceGrounded <= Config.Jump.CoyoteTime

	if Input.IsJumpHeld() and eligible and state.Grounded then
		jumpCharge = math.min(jumpCharge + dt, Config.Jump.ChargeTime)
	end

	if Input.ConsumeJumpRelease() then
		if eligible and onGround then
			local charge = jumpCharge / Config.Jump.ChargeTime
			local power = (Config.Jump.HopPower + (Config.Jump.FullPower - Config.Jump.HopPower) * charge) * stats.Airtime
			local normal = if ground then ground.Normal else WORLD_UP
			state.Velocity = Physics.JumpVelocity(state.Velocity, normal, power, Config.Jump.UpBias)
			command = state.Velocity
			state.Grounded = false
			timeSinceGrounded = math.huge
			jumpCooldown = Config.Jump.Cooldown
			groundLock = Config.Jump.GroundLock
			impactGrace = math.max(impactGrace, Config.Impact.Grace)
			debugCounters.Jumps += 1
			MovementController.Jumped:Fire(charge)
		end
		jumpCharge = 0
	end

	state.JumpCharge = jumpCharge / Config.Jump.ChargeTime
	return command
end

local function updateOrientation(dt: number, ground)
	if ground and state.Grounded then
		state.Up = state.Up:Lerp(ground.Normal, expAlpha(Config.NormalSmoothing, dt)).Unit
	else
		state.Up = state.Up:Lerp(WORLD_UP, expAlpha(Config.AirLevelingRate, dt)).Unit
	end

	local up = state.Up
	local forward = Physics.ProjectOnPlane(state.Heading, up).Unit

	local roll = 0
	if state.Grounded then
		roll = math.rad(Config.LeanAngle) * state.Steer * math.clamp(state.Speed / Config.LeanSpeedRef, 0, 1)
	end
	if stumbleTimer > 0 then
		-- Wobble that fades out as the rider regains balance
		local fade = stumbleTimer / stumbleDuration
		roll += math.rad(Config.Stumble.WobbleAngle) * math.sin(clock * 18) * fade
	end
	if wipeoutTimer > 0 then
		-- Down on one side while sliding to a stop
		local side = if state.Velocity:Dot(forward:Cross(up)) >= 0 then 1 else -1
		roll += math.rad(Config.Wipeout.LeanAngle) * side
	end
	up = CFrame.fromAxisAngle(forward, roll) * up

	rig:Orient(
		CFrame.lookAt(Vector3.zero, forward, up),
		if state.Grounded then Config.Orientation.GroundResponsiveness else Config.Orientation.AirResponsiveness
	)
end

local function writeDebug(ground, command: Vector3)
	root:SetAttribute("DebugMode", state.Mode)
	root:SetAttribute("DebugSpeed", state.Speed)
	root:SetAttribute("DebugTuck", state.Tuck)
	root:SetAttribute("DebugJumpCharge", state.JumpCharge)
	root:SetAttribute("DebugSlope", state.SlopeAngle)
	root:SetAttribute("DebugGroundDistance", if ground then ground.Distance - rideHeight else -1)
	root:SetAttribute("DebugCommand", command)
	for name, count in debugCounters do
		root:SetAttribute("Debug" .. name, count)
	end
end

local function step(dt: number)
	dt = math.min(dt, 1 / 20)
	clock += dt

	if not root or not root.Parent or not rig or rig.Humanoid.Health <= 0 then
		MovementController.Deactivate()
		return
	end
	rig:EnforcePhysicsState()

	local intent = readIntent(dt)

	local killY = getKillY()
	if killY and root.Position.Y < killY then
		MovementController.RequestReset()
	end

	jumpCooldown -= dt
	groundLock -= dt
	impactGrace -= dt
	stumbleTimer = math.max(stumbleTimer - dt, 0)
	if wipeoutTimer > 0 then
		wipeoutTimer -= dt
		if wipeoutTimer <= 0 then
			endWipeout()
		end
	end

	if state.Mode == "Frozen" then
		frozenTimer -= dt
		rig:Drive(Vector3.zero)
		Input.ConsumeJumpRelease()
		jumpCharge = 0
		if frozenTimer <= 0 then
			setMode("Airborne")
		end
		return
	end

	if detectImpact() then
		intent = readIntent(0)
	end

	-- Ground state
	local ground = GroundProbe.Probe(root.Position, state.Heading, rideHeight, raycastParams, Config)
	local wasGrounded = state.Grounded
	local canGround = false
	if ground and groundLock <= 0 and ground.Normal.Y >= math.cos(math.rad(Config.MaxGroundAngle)) then
		local reach = rideHeight + (if wasGrounded then Config.SnapDistance else Config.LandingDistance)
		canGround = ground.Distance <= reach and (wasGrounded or state.Velocity:Dot(ground.Normal) <= 1)
	end

	if canGround and not wasGrounded then
		touchDown(ground.Normal)
		if wipeoutTimer > 0 then
			intent = readIntent(0)
		end
	end

	local command
	if canGround then
		state.Grounded = true
		timeSinceGrounded = 0
		state.AirTime = 0
		state.SlopeAngle = math.deg(math.acos(math.clamp(ground.Normal.Y, -1, 1)))
		command = Physics.Grounded(state, ground, intent, stats, Config, rideHeight, dt)
	else
		state.Grounded = false
		timeSinceGrounded += dt
		state.AirTime += dt
		command = Physics.Airborne(state, intent, Config, dt)
	end

	command = updateJump(dt, ground, command)

	if wipeoutTimer > 0 then
		setMode("Wipeout")
	elseif not state.Grounded then
		setMode("Airborne")
	elseif stumbleTimer > 0 then
		setMode("Stumbling")
	else
		setMode("Grounded")
	end

	state.Speed = state.Velocity.Magnitude
	updateOrientation(dt, ground)
	rig:Drive(command)
	lastCommand = command

	if Config.Debug then
		writeDebug(ground, command)
	end
end

----------------------------------------------------------------------------------------------
-- Activation
----------------------------------------------------------------------------------------------

local function buildRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	if PhysicsService:IsCollisionGroupRegistered(Constants.RiderCollisionGroup) then
		-- Rays then pass through other riders, exactly like the riders' bodies do.
		params.CollisionGroup = Constants.RiderCollisionGroup
	end
	return params
end

local function resetTimers()
	lastCommand = nil
	timeSinceGrounded = math.huge
	jumpCooldown = 0
	jumpCharge = 0
	groundLock = 0
	impactGrace = 0
	stumbleTimer = 0
	wipeoutTimer = 0
	state.CoastDeceleration = 0
	state.JumpCharge = 0
	state.Tuck = 0
	skipLandingCheck = true
end

function MovementController.Activate()
	if state.Active then
		return
	end
	local humanoid, r = CharacterUtil.GetAlive(player.Character)
	if not humanoid or not r then
		return
	end

	character, root = player.Character, r
	stats = SportConfig.GetStats(player:GetAttribute(Constants.Attributes.Sport))
	rideHeight = CharacterUtil.GetFootOffset(character) + Config.EquipmentThickness
	raycastParams = buildRaycastParams()
	rig = Rig.new(humanoid, root, Config)

	state.Heading = Physics.Flatten(root.CFrame.LookVector) or Vector3.new(0, 0, 1)
	state.Velocity = root.AssemblyLinearVelocity
	state.Up = WORLD_UP
	state.Grounded = false
	state.Root = root
	state.Character = character
	state.Active = true
	resetTimers()

	Input.SetRidingEnabled(true)
	setMode("Airborne")
	stepConnection = RunService.PreSimulation:Connect(step)
	MovementController.Activated:Fire()
end

function MovementController.Deactivate()
	if not state.Active then
		return
	end
	state.Active = false

	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
	if rig then
		rig:Destroy()
		rig = nil
	end

	character, root = nil, nil
	state.Root = nil
	state.Character = nil
	state.Grounded = false
	state.Velocity = Vector3.zero
	state.Speed = 0
	Input.SetRidingEnabled(false)
	setMode("Inactive")
	MovementController.Deactivated:Fire()
end

function MovementController.IsActive(): boolean
	return state.Active
end

local function refresh()
	local hasSport = player:GetAttribute(Constants.Attributes.Sport) ~= nil
	local alive = CharacterUtil.GetAlive(player.Character) ~= nil

	if hasSport and alive then
		if state.Active then
			stats = SportConfig.GetStats(player:GetAttribute(Constants.Attributes.Sport))
		else
			MovementController.Activate()
		end
	elseif state.Active then
		MovementController.Deactivate()
	end
end

local function onResetState(target: CFrame)
	if not state.Active or not root then
		return
	end
	local facing = Physics.Flatten(target.LookVector) or state.Heading
	character:PivotTo(CFrame.lookAt(target.Position, target.Position + facing))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	state.Velocity = Vector3.zero
	state.Heading = facing
	state.Up = WORLD_UP
	state.Grounded = false
	state.Speed = 0
	resetTimers()
	frozenTimer = Config.FrozenAfterReset
	setMode("Frozen")
	MovementController.Reset:Fire()
end

function MovementController.Start(inputController)
	Input = inputController

	Input.ResetRequested:Connect(MovementController.RequestReset)
	Remotes.ResetState.OnClientEvent:Connect(onResetState)

	player:GetAttributeChangedSignal(Constants.Attributes.Sport):Connect(refresh)
	player.CharacterAdded:Connect(function(newCharacter)
		if state.Active then
			MovementController.Deactivate()
		end
		newCharacter:WaitForChild("HumanoidRootPart")
		newCharacter:WaitForChild("Humanoid")
		refresh()
	end)
	player.CharacterRemoving:Connect(function()
		MovementController.Deactivate()
	end)

	if player.Character then
		task.spawn(refresh)
	end
end

return MovementController
