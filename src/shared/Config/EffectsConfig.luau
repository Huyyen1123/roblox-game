--[[
	EffectsConfig
	Client-side riding feedback: ski/board trails, carving and braking snow spray, landing
	puffs and wind streaks at high speed. Purely visual; nothing here affects physics.
	Speeds are studs/s (× 1.008 = km/h).
]]

return {
	-- Effects are skipped for riders farther than this from the camera
	MaxDistance = 300,

	Trail = {
		Lifetime = 2.5,
		MinSpeed = 4,
		Color = Color3.fromRGB(214, 226, 240), -- compressed snow, slightly blue-grey
		StartTransparency = 0.45,
		Inset = 0.25, -- studs in from the tail end
	},

	Spray = {
		-- Built-in soft puff texture (no upload needed)
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		-- Shadowed blue-white fading to bright: pure white disappears against sunlit snow
		Color = ColorSequence.new(Color3.fromRGB(170, 186, 210), Color3.fromRGB(226, 234, 246)),
		LightInfluence = 0.3,
		StartTransparency = 0.05,
		MinSpeed = 12,
		-- Outside-edge spray while carving: particles/s per (stud/s of speed × |steer|)
		CarvePerSpeed = 2.4,
		-- Both edges while braking: particles/s per stud/s of speed
		BrakePerSpeed = 1.1,
		-- Light snow dust at speed even when running straight
		CruisePerSpeed = 0.08,
		MaxRate = 260,
		LaunchAngle = 45, -- degrees above horizontal the spray is thrown
		BackSweep = 35, -- degrees the spray is angled back from straight sideways
		Speed = NumberRange.new(12, 24),
		Lifetime = NumberRange.new(0.5, 1.0),
		Size = { 0.3, 1.3 },
		Gravity = 35,
		Drag = 1.2,
		-- Share of the rider's velocity the spray keeps, so it travels with the rider and
		-- trails off behind instead of being left behind instantly at speed
		VelocityInheritance = 0.55,
	},

	LandingPuff = {
		Base = 10, -- particles on every landing
		PerImpact = 0.6, -- more for harder landings (per stud/s of impact)
		Max = 50,
	},

	WindStreaks = {
		Count = 18,
		StartSpeed = 95, -- below this, no streaks
		FullSpeed = 175,
		MaxOpacity = 0.45,
		Speed = 1.6, -- screen radii per second
	},
}
