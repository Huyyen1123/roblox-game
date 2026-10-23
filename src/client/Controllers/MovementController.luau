--[[
	MovementController
	Custom downhill physics for the local character.

	The Humanoid is put in the Physics state so it stops driving the body. Each PreSimulation
	step this controller integrates its own velocity (gravity along the slope, drag, carving,
	jumps) and hands the result to two constraints on the HumanoidRootPart:
	  - LinearVelocity: the commanded velocity, including a spring term that holds ride height
	  - AlignOrientation: stand perpendicular to the smoothed slope normal, face the heading,
	    lean into turns
	The physics engine still resolves collisions, so comparing the commanded velocity with the
	velocity the engine actually produced detects impacts with trees and rocks.

	Modes: Inactive -> Grounded <-> Airborne -> Crashed -> (recover) ; Frozen briefly after resets.
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

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local WORLD_UP = Vector3.yAxis
local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

local MovementController = {}
MovementController.Activated = Signal.new()
MovementController.Deactivated = Signal.new()
MovementController.ModeChanged = Signal.new() -- (newMode, oldMode)
MovementController.Landed = Signal.new() -- (quality: "Clean" | "Sketchy" | "Hard", impactSpeed, airTime)
MovementController.Crashed = Signal.new() -- (reason: "Collision" | "BadLanding")
MovementController.Reset = Signal.new()

-- Snapshot read by the camera and HUD every frame.
local state = {
	Active = false,
	Mode = "Inactive",
	Velocity = Vector3.zero,
	Speed = 0,
	Heading = Vector3.new(0, 0, -1), -- flat (horizontal) facing direction
	Forward = Vector3.new(0, 0, -1), -- heading projected onto the ground plane
	Up = WORLD_UP, -- smoothed ground normal
	Steer = 0,
	Tucking = false,
	Braking = false,
	Grounded = false,
	AirTime = 0,
	Root = nil :: BasePart?,
	Character = nil :: Model?,
}
MovementController.State = state

local Input -- InputController, injected in Start

-- Per-character runtime
local character: Model?
local humanoid: Humanoid?
local root: BasePart?
local attachment: Attachment?
local linearVelocity: LinearVelocity?
local alignOrientation: AlignOrientation?
local stepConnection: RBXScriptConnection?
local raycastParams: RaycastParams?
local rideHeight = 3
local stats = SportConfig.BaseStats

local lastCommand: Vector3? = nil
local timeSinceGrounded = math.huge
local jumpCooldown = 0
local groundLock = 0
local modeTimer = 0
local skipLandingCheck = false
local lastResetRequest = 0
local impactGrace = 0
local debugBumps = 0
local debugJumps = 0

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

local function projectOnPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

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
-- Ground probing
----------------------------------------------------------------------------------------------

-- Five downward rays (centre + four around it) for a stable normal on bumpy voxel terrain.
local function probeGround()
	local origin = root.Position
	local heading = state.Heading
	local right = heading:Cross(WORLD_UP)
	local spread = Config.GroundProbeSpread
	local length = rideHeight * 1.8 + Config.SnapDistance + Config.GroundProbeExtra
	local direction = -WORLD_UP * length

	local offsets = {
		Vector3.zero,
		heading * spread,
		-heading * spread,
		right * spread,
		-right * spread,
	}

	local normalSum = Vector3.zero
	local hits = 0
	local centerHit = nil
	for i, offset in offsets do
		local result = Workspace:Raycast(origin + offset, direction, raycastParams)
		if result then
			normalSum += result.Normal
			hits += 1
			if i == 1 then
				centerHit = result
			end
		end
	end

	if hits == 0 then
		return nil
	end

	local normal = normalSum.Unit
	local position = if centerHit then centerHit.Position else origin - WORLD_UP * length
	if not centerHit then
		-- Estimate the surface under the centre from the averaged plane of the side hits.
		local result = Workspace:Raycast(origin, -normal * length, raycastParams)
		if not result then
			return nil
		end
		position = result.Position
	end

	return {
		Position = position,
		Normal = normal,
		Distance = (origin - position):Dot(normal), -- distance along the normal
	}
end

----------------------------------------------------------------------------------------------
-- Crash and recovery
----------------------------------------------------------------------------------------------

local function crash(reason: string)
	setMode("Crashed")
	modeTimer = Config.Crash.Duration
	linearVelocity.Enabled = false
	alignOrientation.Enabled = false

	local spin = Config.Crash.TumbleSpin
	root.AssemblyLinearVelocity = state.Velocity * 0.45 + WORLD_UP * 15
	root.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 2 * spin,
		(math.random() - 0.5) * spin,
		(math.random() - 0.5) * 2 * spin
	)
	lastCommand = nil
	state.Grounded = false
	MovementController.Crashed:Fire(reason)
end

local function placeUpright(position: Vector3, facing: Vector3)
	character:PivotTo(CFrame.lookAt(position, position + facing))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	state.Velocity = Vector3.zero
	state.Heading = facing
	state.Up = WORLD_UP
	lastCommand = nil
end

local function recover()
	local probe = Workspace:Raycast(root.Position + WORLD_UP * 8, -WORLD_UP * Config.Crash.RecoverProbeDistance, raycastParams)
	if not probe then
		MovementController.RequestReset()
		modeTimer = 0.5
		return
	end

	local facing = flatten(state.Velocity) or state.Heading
	placeUpright(probe.Position + WORLD_UP * (rideHeight + 0.5), facing)
	linearVelocity.Enabled = true
	alignOrientation.Enabled = true
	skipLandingCheck = true
	setMode("Airborne")
end

----------------------------------------------------------------------------------------------
-- Integration
----------------------------------------------------------------------------------------------

local function turnHeading(rate: number, dt: number)
	local angle = -state.Steer * rate * dt
	state.Heading = (CFrame.Angles(0, angle, 0) * state.Heading).Unit
end

local function planeBasis(normal: Vector3): (Vector3, Vector3)
	local forward = projectOnPlane(state.Heading, normal)
	if forward.Magnitude < 1e-3 then
		forward = projectOnPlane(-WORLD_UP:Cross(normal), normal)
	end
	forward = forward.Unit
	return forward, forward:Cross(normal).Unit
end

-- Returns false if the landing was a crash.
local function land(normal: Vector3): boolean
	local velocity = state.Velocity
	local impact = -velocity:Dot(normal)
	local planar = projectOnPlane(velocity, normal)
	local landing = Config.Landing

	if skipLandingCheck then
		skipLandingCheck = false
		state.Velocity = planar
		return true
	end

	local forward = planeBasis(normal)
	local angle = 0
	if planar.Magnitude > 10 then
		angle = math.deg(math.acos(math.clamp(planar.Unit:Dot(forward), -1, 1)))
	end

	local stability = stats.Stability
	if impact > landing.CrashImpact * stability or (angle > landing.SketchyAngle and planar.Magnitude > 25) then
		crash("BadLanding")
		return false
	end

	local quality = "Clean"
	local speedLoss = 0
	if angle > landing.CleanAngle then
		quality = "Sketchy"
		speedLoss += landing.SketchySpeedLoss
		state.Heading = flatten(planar) or state.Heading
	end
	local softImpact = landing.SoftImpact * stability
	if impact > softImpact then
		speedLoss += (impact - softImpact) * landing.HardSpeedLossPerImpact
		if quality == "Clean" then
			quality = "Hard"
		end
	end

	state.Velocity = planar * (1 - math.clamp(speedLoss, 0, 0.9))
	-- The landing deliberately removes the velocity into the surface; don't read that as an impact.
	impactGrace = Config.Crash.ImpactGrace
	MovementController.Landed:Fire(quality, impact, state.AirTime)
	return true
end

local function groundedStep(dt: number, ground): Vector3
	local normal = ground.Normal
	local gravity = Config.Gravity
	local velocity = projectOnPlane(state.Velocity, normal)

	-- Gravity along the slope
	local gravityVector = -WORLD_UP * gravity
	velocity += projectOnPlane(gravityVector, normal) * stats.Acceleration * dt

	-- Steering: rotate the heading, faster at low speed
	local speed = velocity.Magnitude
	local speedT = math.clamp(speed / Config.TurnRateSpeedRef, 0, 1)
	local turnRate = (Config.TurnRateLowSpeed + (Config.TurnRateHighSpeed - Config.TurnRateLowSpeed) * speedT) * stats.Handling
	if state.Tucking then
		turnRate *= Config.TuckTurnMultiplier
	elseif state.Braking then
		turnRate *= Config.BrakeTurnMultiplier
	end
	turnHeading(turnRate, dt)

	-- Drag, snow friction, braking
	local drag = Config.DragCoefficient / (stats.Speed * stats.Speed)
	if state.Tucking then
		drag *= Config.TuckDragMultiplier
	end
	local deceleration = drag * speed * speed + Config.SnowFriction * gravity * normal.Y
	if state.Braking then
		deceleration += Config.BrakeDeceleration
	end
	if speed > 1e-3 then
		velocity *= math.max(speed - deceleration * dt, 0) / speed
	end

	-- Carving: edges bleed off sideways slide and redirect most of it forward
	local forward, right = planeBasis(normal)
	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = velocity:Dot(right)
	local grip = (if state.Braking then Config.BrakeGrip else Config.CarveGrip) * stats.Handling
	local newSideSpeed = sideSpeed * math.exp(-grip * dt)
	local recovered = (math.abs(sideSpeed) - math.abs(newSideSpeed)) * Config.CarveEfficiency
	forwardSpeed += if forwardSpeed >= 0 then recovered else -recovered

	-- Skating on flat ground
	if state.Tucking and forwardSpeed >= -1 and forwardSpeed < Config.PushMaxSpeed then
		forwardSpeed += Config.PushAcceleration * stats.Acceleration * dt
	end

	velocity = forward * forwardSpeed + right * newSideSpeed
	if velocity.Magnitude > Config.MaxSpeed then
		velocity = velocity.Unit * Config.MaxSpeed
	end
	state.Velocity = velocity
	state.Forward = forward

	-- Spring that holds the root at ride height above the surface
	local correction = math.clamp((rideHeight - ground.Distance) * Config.HoverStiffness, -Config.MaxHoverCorrection, Config.MaxHoverCorrection)
	return velocity + normal * correction
end

local function airborneStep(dt: number): Vector3
	local velocity = state.Velocity - WORLD_UP * Config.Gravity * dt
	local speed = velocity.Magnitude
	if speed > 1e-3 then
		velocity *= math.max(speed - Config.AirDragCoefficient * speed * speed * dt, 0) / speed
	end
	turnHeading(Config.AirTurnRate, dt)
	state.Velocity = velocity
	state.Forward = projectOnPlane(state.Heading, state.Up).Unit
	return velocity
end

local function updateOrientation(dt: number, ground)
	if ground and state.Grounded then
		state.Up = state.Up:Lerp(ground.Normal, expAlpha(Config.NormalSmoothing, dt)).Unit
	else
		state.Up = state.Up:Lerp(WORLD_UP, expAlpha(Config.AirLevelingRate, dt)).Unit
	end

	local up = state.Up
	local forward = projectOnPlane(state.Heading, up).Unit

	if state.Grounded then
		local lean = math.rad(Config.LeanAngle) * state.Steer * math.clamp(state.Speed / Config.LeanSpeedRef, 0, 1)
		up = CFrame.fromAxisAngle(forward, lean) * up
	end

	alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, forward, up)
	alignOrientation.Responsiveness = if state.Grounded
		then Config.Orientation.GroundResponsiveness
		else Config.Orientation.AirResponsiveness
end

local function step(dt: number)
	dt = math.min(dt, 1 / 20)

	if not root or not root.Parent or not humanoid or humanoid.Health <= 0 then
		MovementController.Deactivate()
		return
	end
	if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	-- Input
	local targetSteer = Input.GetSteer()
	state.Steer += (targetSteer - state.Steer) * expAlpha(Config.SteerResponse, dt)
	state.Tucking = Input.IsTucking()
	state.Braking = Input.IsBraking()

	local killY = getKillY()
	if killY and root.Position.Y < killY then
		MovementController.RequestReset()
	end

	jumpCooldown -= dt
	groundLock -= dt

	if state.Mode == "Frozen" then
		modeTimer -= dt
		linearVelocity.VectorVelocity = Vector3.zero
		Input.ConsumeJump()
		if modeTimer <= 0 then
			setMode("Airborne")
		end
		return
	elseif state.Mode == "Crashed" then
		modeTimer -= dt
		state.Velocity = root.AssemblyLinearVelocity
		state.Speed = state.Velocity.Magnitude
		Input.ConsumeJump()
		if modeTimer <= 0 then
			recover()
		end
		return
	end

	-- Impact detection: the engine stopped us much harder than we asked for
	local actual = root.AssemblyLinearVelocity
	impactGrace -= dt
	if lastCommand and impactGrace <= 0 and (lastCommand - actual).Magnitude > Config.Crash.CollisionDeviation then
		local speedLoss = lastCommand.Magnitude - actual.Magnitude
		if lastCommand.Magnitude > Config.Crash.MinSpeedForCollisionCrash and speedLoss > Config.Crash.CollisionSpeedLoss then
			crash("Collision")
			return
		end
		state.Velocity = actual
		debugBumps += 1
	end

	-- Ground state
	local ground = probeGround()
	local wasGrounded = state.Grounded
	local canGround = false
	if ground and groundLock <= 0 and ground.Normal.Y >= math.cos(math.rad(Config.MaxGroundAngle)) then
		local reach = rideHeight + (if wasGrounded then Config.SnapDistance else Config.LandingDistance)
		canGround = ground.Distance <= reach and (wasGrounded or state.Velocity:Dot(ground.Normal) <= 1)
	end

	if canGround and not wasGrounded then
		if not land(ground.Normal) then
			return
		end
	end

	local command
	if canGround then
		state.Grounded = true
		timeSinceGrounded = 0
		state.AirTime = 0
		setMode("Grounded")
		command = groundedStep(dt, ground)
	else
		state.Grounded = false
		timeSinceGrounded += dt
		state.AirTime += dt
		setMode("Airborne")
		command = airborneStep(dt)
	end

	-- Jump (with a short coyote window after leaving the ground)
	if Input.ConsumeJump() and jumpCooldown <= 0 and timeSinceGrounded <= Config.CoyoteTime then
		local normal = if ground then ground.Normal else WORLD_UP
		local direction = normal:Lerp(WORLD_UP, Config.JumpUpBias).Unit
		state.Velocity = projectOnPlane(state.Velocity, normal) + direction * Config.JumpPower * stats.Airtime
		command = state.Velocity
		state.Grounded = false
		timeSinceGrounded = math.huge
		jumpCooldown = Config.JumpCooldown
		debugJumps += 1
		impactGrace = Config.Crash.ImpactGrace
		groundLock = Config.JumpGroundLock
		setMode("Airborne")
	end

	state.Speed = state.Velocity.Magnitude
	updateOrientation(dt, ground)

	linearVelocity.MaxForce = root.AssemblyMass * Config.MaxForcePerMass
	linearVelocity.VectorVelocity = command
	lastCommand = command

	if Config.Debug then
		root:SetAttribute("DebugMode", state.Mode)
		root:SetAttribute("DebugSpeed", state.Speed)
		root:SetAttribute("DebugBumps", debugBumps)
		root:SetAttribute("DebugJumps", debugJumps)
		root:SetAttribute("DebugSlope", if ground then math.deg(math.acos(math.clamp(ground.Normal.Y, -1, 1))) else -1)
		root:SetAttribute("DebugGroundDistance", if ground then ground.Distance - rideHeight else -1)
		root:SetAttribute("DebugCommand", command)
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

function MovementController.Activate()
	if state.Active then
		return
	end
	local h, r = CharacterUtil.GetAlive(player.Character)
	if not h or not r then
		return
	end

	character, humanoid, root = player.Character, h, r
	stats = SportConfig.GetStats(player:GetAttribute(Constants.Attributes.Sport))
	rideHeight = CharacterUtil.GetFootOffset(character) + Config.EquipmentThickness
	raycastParams = buildRaycastParams()

	for _, stateType in DISABLED_STATES do
		humanoid:SetStateEnabled(stateType, false)
	end
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	attachment = Instance.new("Attachment")
	attachment.Name = "DownhillAttachment"
	attachment.Parent = root

	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DownhillVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.MaxForce = root.AssemblyMass * Config.MaxForcePerMass
	linearVelocity.VectorVelocity = root.AssemblyLinearVelocity
	linearVelocity.Parent = root

	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "DownhillOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = Config.Orientation.MaxTorque
	alignOrientation.Responsiveness = Config.Orientation.GroundResponsiveness
	alignOrientation.CFrame = root.CFrame.Rotation
	alignOrientation.Parent = root

	state.Heading = flatten(root.CFrame.LookVector) or Vector3.new(0, 0, 1)
	state.Velocity = root.AssemblyLinearVelocity
	state.Up = WORLD_UP
	state.Grounded = false
	state.Root = root
	state.Character = character
	state.Active = true
	lastCommand = nil
	timeSinceGrounded = math.huge
	skipLandingCheck = true

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
	for _, instance in { linearVelocity, alignOrientation, attachment } do
		if instance then
			instance:Destroy()
		end
	end
	linearVelocity, alignOrientation, attachment = nil, nil, nil

	if humanoid and humanoid.Parent then
		for _, stateType in DISABLED_STATES do
			humanoid:SetStateEnabled(stateType, true)
		end
		humanoid.AutoRotate = true
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	character, humanoid, root = nil, nil, nil
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
			-- Sport switched mid-session: just pick up the (identical) stats.
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
	placeUpright(target.Position, flatten(target.LookVector) or state.Heading)
	linearVelocity.Enabled = true
	alignOrientation.Enabled = true
	state.Grounded = false
	state.Speed = 0
	skipLandingCheck = true
	modeTimer = Config.FrozenAfterReset
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
