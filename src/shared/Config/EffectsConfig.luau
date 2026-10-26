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

	-- The channel each ski / the board cuts into the snow (client/Effects/SnowGroove): a
	-- trail with a groove texture (bright lip, shadowed wall, packed floor, lit wall) lying on
	-- the terrain surface under the gear.
	Groove = {
		-- Image X runs across the channel (lip, shadowed wall, floor, lit wall, lip)
		Texture = "rbxassetid://80142138968472",
		WidthScale = 1.8, -- channel is wider than the gear (its walls)
		-- The channel starts at the front of the gear, so it also runs alongside it: the gear
		-- sits in a trough instead of on flat snow
		NoseInset = 0.25,
		Lift = 0.03, -- above the surface (avoids z-fighting)
		StartTransparency = 0.05,
		Lifetime = 6,
		LightInfluence = 0.35, -- keeps the shading readable against bright sunlit snow
		MinSpeed = 3,
		ContactDistance = 0.6,
		MaxDistance = 200, -- grooves for riders within this of the camera
	},

	-- Prototype: EditableMesh powder wake for the snowboard (client/Effects/PowderWake). Needs
	-- EditableMesh; falls back to the Groove trail when it isn't available.
	Wake = {
		Enabled = true,
		Bound = 140, -- mesh bounds (studs); vertices stay within this of the origin
		Recenter = 45, -- re-centre the mesh when the rider is this far from its origin
		CastShadow = true,
		StudsPerTile = 22, -- texture scale; matches the PowderSoft snow variant
		ShadeColor = Color3.fromRGB(198, 212, 234), -- compressed, shadowed snow (inner walls)
		-- Vertex colours and vertex alpha only render on a (very slightly) transparent part
		Transparency = 0.02,
		-- One channel per piece of gear, by part name. Profile: one side of the cross-section,
		-- from under the gear outward. D = studs beyond the gear's edge (negative = under it);
		-- Wall = share of the snow height; Offset = studs added; Shade = share of ShadeColor;
		-- Alpha = opacity (the outer shoulder fades into the terrain).
		-- The floor and outer edge dive under the terrain (the terrain is the floor; the
		-- rendered terrain can sit a little below its collision surface). Crest = D beyond
		-- which the shoulder may widen or narrow. BuildUp = height of the powder beside the
		-- moving gear; TrackHeight = height of the rims of the track left behind.
		Kinds = {
			Board = {
				BuildUp = 0.2,
				TrackHeight = 0.07,
				Crest = 0.3,
				Sections = 64,
				Spacing = 1,
				Profile = {
					{ D = -0.3, Wall = 0, Offset = -0.35, Shade = 0.8 },
					{ D = -0.02, Wall = 0.55, Offset = -0.03, Shade = 0.6 },
					{ D = 0.12, Wall = 0.9, Offset = 0, Shade = 0.25 },
					{ D = 0.3, Wall = 1, Offset = 0 },
					{ D = 0.65, Wall = 0.55, Offset = 0, Alpha = 0.85 },
					{ D = 1.05, Wall = 0.18, Offset = -0.02, Alpha = 0.35 },
					{ D = 1.5, Wall = 0, Offset = -0.25, Alpha = 0 },
				},
			},
			Ski = {
				BuildUp = 0.14,
				TrackHeight = 0.05,
				Crest = 0.15,
				Sections = 48,
				Spacing = 1,
				Profile = {
					{ D = -0.2, Wall = 0, Offset = -0.3, Shade = 0.8 },
					{ D = -0.02, Wall = 0.55, Offset = -0.03, Shade = 0.6 },
					{ D = 0.06, Wall = 0.9, Offset = 0, Shade = 0.25 },
					{ D = 0.15, Wall = 1, Offset = 0 },
					{ D = 0.32, Wall = 0.55, Offset = 0, Alpha = 0.85 },
					{ D = 0.5, Wall = 0.18, Offset = -0.02, Alpha = 0.35 },
					{ D = 0.72, Wall = 0, Offset = -0.2, Alpha = 0 },
				},
			},
		},
		-- Rows beside the gear, from the leading nose (T = 0) toward the tail (the live row
		-- at the tail, T = 1, follows). Height = share of BuildUp; Settle = how far it has
		-- settled toward the track's rim height
		Stations = {
			{ T = 0, Height = 0, Settle = 0 },
			{ T = 0.15, Height = 0.45, Settle = 0 },
			{ T = 0.32, Height = 0.8, Settle = 0 },
			{ T = 0.5, Height = 1, Settle = 0 },
			{ T = 0.68, Height = 1, Settle = 0.15 },
			{ T = 0.85, Height = 0.9, Settle = 0.55 },
		},
		StandingShare = 0.45, -- powder beside the gear when standing still (share of BuildUp)
		BuildUpSpeed = 35, -- full build-up from this speed
		TaperRows = 8, -- the last rows of a track shrink to nothing
		AgeStride = 6, -- each frame 1 in this many laid rows is re-aged
		Wobble = 0.5, -- uneven rims: height varies by about ± this share / 2 along the track
		Spread = 0.6, -- and the shoulders widen / narrow by about ± this share / 2
		WobbleScale = 0.2, -- per stud travelled
		Lifetime = 8, -- rims slump to nothing over this many seconds
		Sink = 0.06, -- and sink this far
		CarveFullSpeed = 60,
		CarveRaise = 0.9, -- engaged edge: snow up to this much higher
		CarvePush = 0.6, -- and its shoulder pushed this much further out
		CarveLower = 0.5, -- other edge: this much lower
		BrakeRaise = 0.08, -- studs added at the front while braking
		SinkInRate = 8,
		LiftOutRate = 25,
		SwellPerImpact = 0.012,
		MaxSwell = 0.6,
		SwellRecovery = 4,
		-- Quality: full wake for the local rider plus the nearest few riders within range
		MaxRemote = 3,
		MaxDistance = 120,
		MinQualityLevel = 4, -- graphics quality below this: local rider only
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
