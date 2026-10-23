--[[
	MovementConfig
	All tuning values for the custom downhill controller. Units are studs and seconds.
	Gravity here is the controller's own gravity, independent of Workspace.Gravity.
]]

return {
	-- Writes Debug* attributes on the local HumanoidRootPart every step (visible in Properties).
	Debug = false,

	Gravity = 110,
	MaxSpeed = 220,

	-- Speed loss: drag * speed^2 + snow friction * gravity * normal.Y
	DragCoefficient = 0.0024,
	TuckDragMultiplier = 0.6,
	SnowFriction = 0.04,
	BrakeDeceleration = 70,

	-- Carving: how strongly edges kill sideways sliding, and how much of that
	-- sideways speed is redirected forward instead of lost.
	CarveGrip = 7,
	BrakeGrip = 2.5,
	CarveEfficiency = 0.85,

	-- Turning (radians per second), interpolated by speed
	TurnRateLowSpeed = 2.6,
	TurnRateHighSpeed = 1.3,
	TurnRateSpeedRef = 150,
	TuckTurnMultiplier = 0.55,
	BrakeTurnMultiplier = 1.25,
	SteerResponse = 10,

	-- Skating/pushing on flat ground
	PushAcceleration = 30,
	PushMaxSpeed = 22,

	-- Jumping
	JumpPower = 38,
	JumpUpBias = 0.35, -- 0 = jump along slope normal, 1 = straight up
	JumpCooldown = 0.35,
	JumpGroundLock = 0.2, -- seconds after a jump before ground snapping is allowed
	CoyoteTime = 0.12,

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
	LeanSpeedRef = 80,

	Landing = {
		CleanAngle = 25, -- degrees between facing and travel direction
		SketchyAngle = 60,
		SketchySpeedLoss = 0.25,
		SoftImpact = 45, -- studs/s into the surface
		CrashImpact = 125,
		HardSpeedLossPerImpact = 0.004,
	},

	Crash = {
		CollisionDeviation = 25, -- commanded vs actual velocity difference that counts as a hit
		ImpactGrace = 0.12, -- seconds after a deliberate velocity jump (jumping) with no impact checks
		CollisionSpeedLoss = 55,
		MinSpeedForCollisionCrash = 45,
		Duration = 2.2,
		TumbleSpin = 8,
		RecoverProbeDistance = 80,
	},

	Orientation = {
		GroundResponsiveness = 35,
		AirResponsiveness = 14,
		MaxTorque = 1e7,
	},

	-- Must be high enough to reach a jump's velocity change within a frame or two (38 * 60 ≈ 2300).
	MaxForcePerMass = 3000,
	EquipmentThickness = 0.3,

	-- Server rules
	RidersCollide = false,
	ResetCooldown = 1,
	RespawnDelay = 3,
	FrozenAfterReset = 0.35,
}
