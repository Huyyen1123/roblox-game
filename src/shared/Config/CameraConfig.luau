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
		Distance = 16,
		MinDistance = 8,
		MaxDistance = 32,
		ZoomStep = 2,
		FocusHeight = 2.5,
		Pitch = 14,
		SlopePitchFollow = 0.5,
		VelocityBlend = 0.5, -- 0 = follow facing, 1 = follow travel direction
		YawResponsiveness = 6,
		PitchResponsiveness = 4,
		DistanceResponsiveness = 4,
		SpeedDistanceBonus = 5,
		SpeedForMaxBonus = 70,
		CollisionRadius = 0.8,
		OrbitSensitivity = 0.25, -- degrees per pixel
		MaxOrbitPitch = 60,
		OrbitReturnDelay = 1.2,
		OrbitReturnRate = 3,
		Fov = { Base = 70, Max = 86, SpeedForMax = 70, Responsiveness = 4 },
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
		BobSpeedRef = 60,
		LookSensitivity = 0.2,
		MaxLookYaw = 70,
		MaxLookPitch = 50,
		LookReturnDelay = 0.8,
		LookReturnRate = 3,
		Fov = { Base = 78, Max = 92, SpeedForMax = 70, Responsiveness = 4 },
	},

	GamepadLookSpeed = 360, -- pixels-equivalent per second at full stick
}
