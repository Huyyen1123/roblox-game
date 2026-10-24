--[[
	Physics
	One integration step of downhill motion. Pure with respect to the world: it reads the ground
	probe and the rider's intent, updates the movement state's Velocity/Heading/Forward, and
	returns the velocity to command (which includes a ride-height spring when grounded).

	intent = {
		Steer: number,   -- [-1, 1], already smoothed and scaled (e.g. weaker while stumbling)
		Tuck: number,    -- [0, 1], eased in and out by the controller
		Brake: boolean,
		Push: boolean,   -- skating push at low speed
		Coast: boolean,  -- wipeout slide: no control, strong deceleration
	}
]]

local WORLD_UP = Vector3.yAxis

local Physics = {}

local function projectOnPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end
Physics.ProjectOnPlane = projectOnPlane

function Physics.Flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

-- Forward (heading on the slope) and right vectors for a ground normal.
function Physics.PlaneBasis(heading: Vector3, normal: Vector3): (Vector3, Vector3)
	local forward = projectOnPlane(heading, normal)
	if forward.Magnitude < 1e-3 then
		forward = projectOnPlane(-WORLD_UP:Cross(normal), normal)
	end
	forward = forward.Unit
	return forward, forward:Cross(normal).Unit
end

local function turnHeading(state, steer: number, rate: number, dt: number)
	state.Heading = (CFrame.Angles(0, -steer * rate * dt, 0) * state.Heading).Unit
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Physics.Grounded(state, ground, intent, stats, config, rideHeight: number, dt: number): Vector3
	local normal = ground.Normal
	local gravity = config.SlopeGravity
	local velocity = projectOnPlane(state.Velocity, normal)

	-- Steering: rotate the heading, faster at low speed, slower in a tuck
	local speed = velocity.Magnitude
	local speedT = math.clamp(speed / config.TurnRateSpeedRef, 0, 1)
	local turnRate = lerp(config.TurnRateLowSpeed, config.TurnRateHighSpeed, speedT) * stats.Handling
	turnRate *= lerp(1, config.Tuck.TurnMultiplier, intent.Tuck)
	if intent.Brake then
		turnRate *= config.Brake.TurnMultiplier
	end
	if not intent.Coast then
		turnHeading(state, intent.Steer, turnRate, dt)
	end

	local forward, right = Physics.PlaneBasis(state.Heading, normal)
	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = velocity:Dot(right)

	-- Gravity along the slope. Only the part along the skis accelerates the rider; the
	-- sideways part is held by the edges (a little slips through while braking/skidding).
	-- Converting sideways gravity into forward speed would make zig-zagging faster than
	-- riding straight.
	local slopeGravity = projectOnPlane(-WORLD_UP * gravity, normal) * stats.Acceleration
	forwardSpeed += slopeGravity:Dot(forward) * dt
	local lateralSlip = if intent.Brake or intent.Coast then config.Brake.LateralSlip else 0
	sideSpeed += slopeGravity:Dot(right) * lateralSlip * dt

	-- Carving: edges bleed off sideways momentum (e.g. from turning) and redirect part of it
	-- forward. The redirect moves kinetic energy, not speed: adding the lost sideways speed
	-- straight onto forward speed would make every small turn step a net speed gain.
	local grip = (if intent.Brake then config.Brake.Grip else config.CarveGrip) * stats.Handling
	local newSideSpeed = sideSpeed * math.exp(-grip * dt)
	local redirectedEnergy = (sideSpeed * sideSpeed - newSideSpeed * newSideSpeed) * config.CarveEfficiency
	local forwardMagnitude = math.sqrt(forwardSpeed * forwardSpeed + redirectedEnergy)
	forwardSpeed = if forwardSpeed >= 0 then forwardMagnitude else -forwardMagnitude

	-- Speed loss: air drag (less in a tuck), snow friction, turning, braking, wipeout slide
	local drag = config.DragCoefficient / (stats.Speed * stats.Speed) * lerp(1, config.Tuck.DragMultiplier, intent.Tuck)
	local deceleration = drag * speed * speed
		+ config.SnowFriction * gravity * normal.Y
		+ config.TurnDrag * math.abs(intent.Steer) * speed
	if intent.Brake then
		-- Fixed braking force plus a hold that cancels the slope's downhill pull, so braking
		-- stops the rider in about the same time on a steep or a mellow slope.
		deceleration += config.Brake.Deceleration + config.Brake.SlopeHold * math.max(slopeGravity:Dot(forward), 0)
	end
	if intent.Coast then
		deceleration += state.CoastDeceleration or 0
	end
	local planarSpeed = math.sqrt(forwardSpeed * forwardSpeed + newSideSpeed * newSideSpeed)
	if planarSpeed > 1e-3 then
		local scale = math.max(planarSpeed - deceleration * dt, 0) / planarSpeed
		forwardSpeed *= scale
		newSideSpeed *= scale
	end

	-- Skating push at low speed
	if intent.Push and not intent.Coast and forwardSpeed >= -1 and forwardSpeed < config.Push.MaxSpeed then
		forwardSpeed = math.min(forwardSpeed + config.Push.Acceleration * stats.Acceleration * dt, config.Push.MaxSpeed)
	end

	velocity = forward * forwardSpeed + right * newSideSpeed
	-- Sliding tail-first (e.g. after a slow backwards landing, or sliding back uphill): the
	-- gear's travel direction flips and the rider is now riding switch; the body doesn't move
	if forwardSpeed < -config.SwitchSlideSpeed then
		state.Heading = -state.Heading
		state.Switch = not state.Switch
		forward = -forward
	end
	if velocity.Magnitude > config.MaxSpeed then
		velocity = velocity.Unit * config.MaxSpeed
	end
	state.Velocity = velocity
	state.Forward = forward

	-- Spring that holds the root at ride height above the surface
	local correction = math.clamp((rideHeight - ground.Distance) * config.HoverStiffness, -config.MaxHoverCorrection, config.MaxHoverCorrection)
	return velocity + normal * correction
end

-- Signed yaw (radians) from a to b, both flat directions; positive = b is to the left of a.
local function signedYaw(a: Vector3, b: Vector3): number
	return math.atan2(a:Cross(b).Y, a:Dot(b))
end

function Physics.Airborne(state, intent, config, dt: number): Vector3
	local velocity = state.Velocity - WORLD_UP * config.AirGravity * dt
	local speed = velocity.Magnitude
	if speed > 1e-3 then
		velocity *= math.max(speed - config.AirDragCoefficient * speed * speed * dt, 0) / speed
	end

	-- Spin: A/D drive a spin rate that builds and slows smoothly
	local air = config.Air
	local steer = if intent.Coast then 0 else intent.Steer
	local targetRate = -steer * air.SpinRate -- positive yaw = turning left
	local maxStep = air.SpinAcceleration * dt
	state.SpinRate += math.clamp(targetRate - state.SpinRate, -maxStep, maxStep)
	local yaw = state.SpinRate * dt

	-- Landing assist: with A/D released and the spin settled, line up with the travel
	-- direction, forwards or backwards (whichever is nearer), so 180s land switch
	local travel = Physics.Flatten(velocity)
	if math.abs(steer) < 0.1 and math.abs(state.SpinRate) < air.AlignRate and travel then
		local toTravel = signedYaw(state.Heading, travel)
		if math.abs(toTravel) > math.pi / 2 then
			toTravel = signedYaw(state.Heading, -travel)
		end
		yaw += math.clamp(toTravel, -air.AlignRate * dt, air.AlignRate * dt)
	end

	state.Heading = (CFrame.Angles(0, yaw, 0) * state.Heading).Unit
	state.AirSpin += yaw
	state.Velocity = velocity
	state.Forward = projectOnPlane(state.Heading, state.Up).Unit
	return velocity
end

-- Velocity for a jump: keeps momentum along the slope and adds the jump along the
-- slope normal, biased upward.
function Physics.JumpVelocity(velocity: Vector3, normal: Vector3, power: number, upBias: number): Vector3
	local direction = normal:Lerp(WORLD_UP, upBias).Unit
	return projectOnPlane(velocity, normal) + direction * power
end

return Physics
