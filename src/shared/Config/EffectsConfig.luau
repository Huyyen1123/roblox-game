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
		CarvePerSpeed = 1.3,
		-- Both edges while braking: particles/s per stud/s of speed
		BrakePerSpeed = 1.1,
		-- Light snow dust at speed even when running straight
		CruisePerSpeed = 0.04,
		MaxRate = 130,
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

	-- Deep-powder look (client/Effects/PowderCollar): snow built up around each piece of gear
	-- on the terrain surface, plus a compressed trench behind it. Heights are the visible cap
	-- above the surface in studs (medium-deep: up to about the top of the board / ski).
	Powder = {
		Color = Color3.fromRGB(236, 242, 250), -- exactly the terrain snow colour
		-- Each bank is a sunk "capsule" (two large-radius cylinders joined by a ball of the same
		-- radius) so only a thin, smooth, rounded strip shows. It rises from below the surface
		-- at the nose (NoseHeight) to PeakHeight at PeakAt (share of the half-length toward
		-- the tail), then falls back below the surface TailExtend studs behind the tail, so
		-- snow piles up around and behind the tail and the nose rides out. Both flat cylinder
		-- ends stay underground. BankOutset puts the axis beyond the gear's side so the snow
		-- covers the edge (about 0.18 high there) without covering the top.
		Ski = {
			BankRadius = 3.5,
			BankOutset = 0.74,
			NoseHeight = -0.06,
			PeakHeight = 0.26,
			PeakAt = 0.45,
			TailExtend = 1.2,
			EndHeight = -0.04,
			InnerScale = 0.45, -- banks between the two skis stay low so the ski tops show
		},
		Board = {
			BankRadius = 3.5,
			BankOutset = 0.74,
			NoseHeight = -0.05,
			PeakHeight = 0.28,
			PeakAt = 0.5,
			TailExtend = 1.2,
			EndHeight = -0.04,
			InnerScale = 1,
		},
		Sink = 0.02, -- extra depth so cap edges meet the terrain without a sliver
		CarveRaise = 0.6, -- engaged-edge bank grows by this share at full carve
		CarveLower = 0.5, -- outside bank shrinks by this share
		CarveFullSpeed = 60, -- studs/s at which carving reaches full effect
		BrakeRaise = 0.1, -- snow pushed up at the front while braking
		SinkInRate = 8, -- how quickly the gear settles into the snow
		LiftOutRate = 25, -- how quickly the collar sinks away on takeoff
		SwellPerImpact = 0.012, -- landing swell (share of depth) per stud/s of impact
		MaxSwell = 0.6,
		SwellRecovery = 4,
		ContactDistance = 0.6, -- snow within this below the gear counts as contact
		TrailMinSpeed = 4,
		MaxDistance = 150, -- full effect for riders within this of the camera
		Trench = {
			WidthShare = 0.9,
			Lift = 0.03, -- above the surface (avoids z-fighting)
			GrooveColor = Color3.fromRGB(150, 168, 200), -- shadowed, compressed snow
			GrooveTransparency = 0.2,
			RimColor = Color3.fromRGB(236, 242, 250), -- pushed-up lips, barely brighter than snow
			RimTransparency = 0.75,
			RimWidth = 0.12,
			Lifetime = 5,
		},
	},
	-- Terrain materials that count as snow for effects (spray, edges, trails)
	SnowMaterials = { "Snow", "Salt", "Limestone" },

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
