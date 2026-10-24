--[[
	MovementConfig
	Tuning for the downhill controller. Units are studs and seconds; 1 stud = 0.28 m, so
	studs/s × 1.008 = km/h (see Shared.Util.Units).

	Speeds restored to the original prototype values (2026-10-24, by request):
	  ~80 km/h on 10–14° slopes, ~125 km/h on 24° untucked, ~160 tucked, cap 220 studs/s.
	Gameplay improvements made since the prototype (energy-conserving carving, charged jumps,
	stumble/wipeout, stance) are kept; only the speed-related values are the prototype's.
	Terminal speed solves SlopeGravity·sin θ − friction = drag·v², so slope angle, SlopeGravity,
	SnowFriction and DragCoefficient together set every number above. Change them together
	and re-measure on the Studio test lanes (see docs/PHASE1_MOVEMENT.md).
]]

return {
	-- Writes Debug* attributes on the local HumanoidRootPart every step (visible in Properties).
	Debug = false,

	-- Gravity along the snow (sets acceleration and terminal speeds on slopes)
	SlopeGravity = 110,
	-- Gravity while airborne. A little lower than on the snow so jumps hang long enough
	-- for a 360 without feeling floaty.
	AirGravity = 92,
	MaxSpeed = 220,

	-- Speed loss on the snow: drag·v² + friction·SlopeGravity·cos θ (+ turning, + braking)
	DragCoefficient = 0.0024,
	SnowFriction = 0.04,

	Tuck = {
		DragMultiplier = 0.6, -- 24° terminal: ~125 km/h untucked → ~160 tucked
		TurnMultiplier = 0.55,
		InTime = 0.35, -- seconds to fully settle into the tuck
		OutTime = 0.2,
	},

	Brake = {
		Deceleration = 70, -- studs/s² (prototype value)
		SlopeHold = 0, -- 0 = plain braking force, as in the prototype
		Grip = 2.5, -- lower grip lets the skis skid sideways while braking
		LateralSlip = 0.3, -- share of sideways gravity that slides the rider while braking
		TurnMultiplier = 1.25,
	},

	-- Carving: edges bleed off sideways slide; CarveEfficiency is the share of that sideways
	-- kinetic energy redirected forward (turns never add speed)
	CarveGrip = 7,
	CarveEfficiency = 0.85,
	-- Extra speed loss from steering: TurnDrag · |steer| · speed (studs/s²)
	TurnDrag = 0,

	-- Turning (radians per second), interpolated from low to high speed
	TurnRateLowSpeed = 2.6,
	TurnRateHighSpeed = 1.3,
	TurnRateSpeedRef = 150,
	SteerResponse = 10,

	-- Skating push (W) at low speed, e.g. off the start pad
	Push = {
		Acceleration = 30,
		MaxSpeed = 22,
	},

	Jump = {
		HopPower = 15, -- tap: small hop (~1.5 studs)
		FullPower = 36, -- full charge: ~7 studs high, ~0.8 s of air on flat ground
		ChargeTime = 0.55, -- seconds of holding for a full charge
		UpBias = 0.35, -- 0 = along slope normal, 1 = straight up
		Cooldown = 0.3,
		GroundLock = 0.18, -- seconds after a jump before ground snapping is allowed
		CoyoteTime = 0.12,
	},

	-- Airborne
	AirDragCoefficient = 0.0015,
	AirLevelingRate = 2,
	Air = {
		SpinRate = 9.5, -- radians/s at full A/D (~545°/s: a 360 in about 0.7 s)
		SpinAcceleration = 50, -- how fast a spin builds and slows (smooth, not instant)
		-- With A/D released, the rider rotates toward the travel direction, finishing a
		-- nearly-complete spin or unwinding a small one, so landings line up naturally.
		AlignRate = 5.5,
	},

	-- Ground following
	HoverStiffness = 14,
	MaxHoverCorrection = 45,
	SnapDistance = 2.2,
	LandingDistance = 0.6,
	GroundProbeExtra = 6,
	GroundProbeSpread = 1.4,
	NormalSmoothing = 14,
	MaxGroundAngle = 55,

	-- Visual lean into turns (the whole body and the skis/board tilt onto their edges)
	LeanAngle = 26,
	LeanSpeedRef = 80,

	Landing = {
		CleanAngle = 25, -- degrees between facing and travel direction
		StumbleAngle = 70, -- beyond this a landing is a wipeout
		-- Impact speeds (studs/s into the surface). A full-charge jump lands at ~35, so normal
		-- jumps stay clean; drops from big airs grade into Hard, Stumble, then Wipeout.
		SoftImpact = 45, -- above this the landing is "Hard" (small speed loss)
		StumbleImpact = 75, -- a hard landing above this stumbles
		WipeoutImpact = 125,
		HardSpeedLossPerImpact = 0.004,
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
		Deceleration = 80, -- slide to a stop from prototype speeds within the wipeout
		LeanAngle = 50,
		RecoveryStumble = 0.5,
	},

	-- Impacts with obstacles: the engine produced much less velocity than commanded
	Impact = {
		Deviation = 25, -- commanded vs actual difference that counts as a hit
		StumbleSpeedLoss = 15,
		WipeoutSpeedLoss = 55,
		WipeoutMinSpeed = 45,
		Grace = 0.12, -- seconds after a deliberate velocity change with no impact checks
	},

	Orientation = {
		GroundResponsiveness = 35,
		AirResponsiveness = 30, -- crisp enough to follow fast spins
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
