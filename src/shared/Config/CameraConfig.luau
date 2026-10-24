--[[
	CameraConfig
	Tuning for the third-person and first-person riding cameras.
	Angles are in degrees, responsiveness values are exponential smoothing rates (higher = snappier).
	Speed references (SpeedFor*, BobSpeedRef) are in studs/s and match MovementConfig.MaxSpeed.
]]

return {
	DefaultMode = "ThirdPerson",
	ModeOrder = { "ThirdPerson", "FirstPerson" },

	ThirdPerson = {
		-- Low and close behind the rider: the stance and the slope ahead both read clearly
		Distance = 12,
		MinDistance = 7,
		MaxDistance = 28,
		ZoomStep = 2,
		FocusHeight = 1.9, -- around the rider's shoulders in a crouch
		Pitch = 10,
		SlopePitchFollow = 0.5,
		VelocityBlend = 0.6, -- 0 = follow facing, 1 = follow travel direction
		YawResponsiveness = 5,
		PitchResponsiveness = 4,
		DistanceResponsiveness = 3,
		SpeedDistanceBonus = 4, -- pulls back gently as speed builds
		SpeedForMaxBonus = 170,
		CollisionRadius = 0.8,
		OrbitSensitivity = 0.25, -- degrees per pixel
		MaxOrbitPitch = 60,
		OrbitReturnDelay = 1.2,
		OrbitReturnRate = 3,
		-- Turn anticipation: the camera swings slightly into the turn ahead of the rider
		TurnLead = 7, -- degrees at full steer
		TurnLeadResponsiveness = 3,
		-- Landing: a short dip, scaled by impact speed
		LandingDipPerImpact = 0.02,
		MaxLandingDip = 0.9,
		LandingDipRecovery = 6,
		-- High-speed feedback: a very small, smooth buzz (no shake at normal speeds)
		Buzz = { StartSpeed = 110, FullSpeed = 200, Position = 0.035, Angle = 0.18, Frequency = 11 },
		Fov = { Base = 70, Max = 92, SpeedForMax = 170, Responsiveness = 4 },
	},

	FirstPerson = {
		EyeHeight = 1.6,
		ForwardOffset = 0.4,
		VelocityBlend = 0.3,
		LookResponsiveness = 10,
		SlopePitchFollow = 0.7,
		ExtraPitch = -6,
		RollFromSteer = 4,
		BobAmplitude = 0.06,
		BobFrequency = 9,
		BobSpeedRef = 120,
		LookSensitivity = 0.2,
		MaxLookYaw = 70,
		MaxLookPitch = 50,
		LookReturnDelay = 0.8,
		LookReturnRate = 3,
		Fov = { Base = 78, Max = 100, SpeedForMax = 170, Responsiveness = 4 },
	},

	GamepadLookSpeed = 360, -- pixels-equivalent per second at full stick
}
