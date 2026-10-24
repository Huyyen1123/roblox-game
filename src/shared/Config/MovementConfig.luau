--[[
	MovementConfig
	Tuning for the downhill controller. Units are studs and seconds; 1 stud = 0.28 m, so
	studs/s × 1.008 = km/h (see Shared.Util.Units).

	Speed targets (retuned after playtesting, 2026-10-23) and how they're reached on the
	course's real slopes (9°–24°):
	  Cruising  35–40 km/h → untucked terminal speed on 13–14° (the typical course slope)
	  Racing    45–55      → untucked terminal speed on 18–24°
	  Tucking   60–65      → tucked terminal speed on 22–24°
	  Hard cap  ~70        → MaxSpeed
	Terminal speed solves SlopeGravity·sin θ − friction = drag·v², so slope angle, SlopeGravity,
	SnowFriction and DragCoefficient together set every number above. Change them together
	and re-measure on the Studio test lanes (see docs/PHASE1_MOVEMENT.md).
]]

return {
	-- Writes Debug* attributes on the local HumanoidRootPart every step (visible in Properties).
	Debug = false,

	-- Gravity along the snow (sets acceleration and terminal speeds on slopes)
	SlopeGravity = 68,
	-- Gravity while airborne (kept higher so jumps feel weighty, not floaty)
	AirGravity = 110,
	MaxSpeed = 69.4, -- 70 km/h

	-- Speed loss on the snow: drag·v² + friction·SlopeGravity·cos θ (+ turning, + braking)
	DragCoefficient = 0.0097,
	SnowFriction = 0.03,

	Tuck = {
		DragMultiplier = 0.70, -- 24° terminal: ~52 km/h untucked → ~62 tucked
		TurnMultiplier = 0.5,
		InTime = 0.35, -- seconds to fully settle into the tuck
		OutTime = 0.2,
	},

	Brake = {
		Deceleration = 16, -- studs/s² on top of cancelling the slope (SlopeHold)
		SlopeHold = 1, -- 1 = braking fully counters the downhill pull of any slope
		Grip = 3, -- lower grip lets the skis skid sideways while braking
		LateralSlip = 0.3, -- share of sideways gravity that slides the rider while braking
		TurnMultiplier = 1.2,
	},

	-- Carving: edges bleed off sideways slide; CarveEfficiency is the share of that sideways
	-- kinetic energy redirected forward (turns never add speed)
	CarveGrip = 7,
	CarveEfficiency = 0.85,
	-- Extra speed loss from steering: TurnDrag · |steer| · speed (studs/s²)
	TurnDrag = 0.22,

	-- Turning (radians per second), interpolated from low to high speed
	TurnRateLowSpeed = 2.4,
	TurnRateHighSpeed = 1.3,
	TurnRateSpeedRef = 65,
	SteerResponse = 9,

	-- Skating push (W) at low speed, e.g. off the start pad
	Push = {
		Acceleration = 14,
		MaxSpeed = 12,
	},

	Jump = {
		HopPower = 16, -- tap: small hop (measured ~0.6 studs)
		FullPower = 32, -- full charge (measured ~3 studs, ~0.5 s air)
		ChargeTime = 0.55, -- seconds of holding for a full charge
		UpBias = 0.35, -- 0 = along slope normal, 1 = straight up
		Cooldown = 0.3,
		GroundLock = 0.18, -- seconds after a jump before ground snapping is allowed
		CoyoteTime = 0.12,
	},

	-- Airborne
	AirDragCoefficient = 0.0015,
	AirTurnRate = 3.2,
	AirLevelingRate = 2,

	-- Ground following
	HoverStiffness = 14,
	MaxHoverCorrection = 45,
	SnapDistance = 2.2,
	LandingDistance = 0.6,
	GroundProbeExtra = 6,
	GroundProbeSpread = 1.4,
	NormalSmoothing = 14,
	MaxGroundAngle = 55,

	-- Visual lean into turns
	LeanAngle = 18,
	LeanSpeedRef = 50,

	Landing = {
		CleanAngle = 25, -- degrees between facing and travel direction
		StumbleAngle = 70, -- beyond this a landing is a wipeout
		-- Impact speeds (studs/s into the surface). A full-charge jump lands at ~30, so normal
		-- jumps stay clean; drops from big airs grade into Hard, Stumble, then Wipeout.
		SoftImpact = 36, -- above this the landing is "Hard" (small speed loss)
		StumbleImpact = 48, -- a hard landing above this stumbles
		WipeoutImpact = 75,
		HardSpeedLossPerImpact = 0.006,
		MinSpeedForAngle = 8, -- slower than this, facing doesn't matter on landing
	},

	-- Short loss of control after a poor landing or a bump
	Stumble = {
		Duration = 0.7,
		SpeedLoss = 0.2,
		SteerMultiplier = 0.4,
		WobbleAngle = 10,
	},

	-- Severe impact: slide to a stop, then get back up. No ragdoll or physics tumble.
	Wipeout = {
		Duration = 1.6,
		Deceleration = 35,
		LeanAngle = 50,
		RecoveryStumble = 0.5,
	},

	-- Impacts with obstacles: the engine produced much less velocity than commanded
	Impact = {
		Deviation = 10, -- commanded vs actual difference that counts as a hit
		StumbleSpeedLoss = 6,
		WipeoutSpeedLoss = 16,
		WipeoutMinSpeed = 18,
		Grace = 0.12, -- seconds after a deliberate velocity change with no impact checks
	},

	Orientation = {
		GroundResponsiveness = 35,
		AirResponsiveness = 14,
		MaxTorque = 1e7,
	},

	-- Must be high enough to reach a jump's velocity change within a frame or two.
	MaxForcePerMass = 3000,
	EquipmentThickness = 0.3,

	-- Server rules
	RidersCollide = false,
	ResetCooldown = 1,
	RespawnDelay = 3,
	FrozenAfterReset = 0.35,
}
