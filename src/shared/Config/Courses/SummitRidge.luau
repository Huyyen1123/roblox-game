--[[
	Summit Ridge (working name): open-mountain freeride test map.
	Coordinates are course-local: Z runs downhill from the summit start (Z = 0), X is across
	the mountain. World position = Origin + local position.

	Unlike Frostpeak there is no single racing line: the terrain is a full 2-D mountain built by
	server/Course/FreerideHeightfield. A wide summit plateau leads into a powder bowl that
	splits into three corridors separated by rounded ridgelines, which rejoin in a lower valley
	above the finish basin:
	  left    gentle and steady (beginner)
	  centre  direct fall line with rollovers (fast)
	  right   steep pitches with flat benches between (advanced)
	Snow depth comes from the terrain shape itself (wind ridges, rounded drifts, snowbanks),
	not from extra parts. Bump TerrainVersion whenever a terrain-affecting value changes.
]]

return {
	Id = "SummitRidge",
	DisplayName = "Summit Ridge",
	Kind = "Freeride",
	Seed = 2718,

	-- Well clear of Frostpeak (which ends near world X = +1600) and the dev test lanes (X = -3000)
	Origin = Vector3.new(7000, 0, 0),
	StartY = 1500,
	KillDepth = 120,

	Start = { Z = 0 },
	Finish = { Z = 5450 },

	World = {
		TerrainVersion = 1,
		-- Per-course bake marker on Workspace.Terrain (several courses share one Terrain)
		BakeAttribute = "CourseTerrain_SummitRidge",

		-- Generated area (local studs): playable is roughly |X| < 1050, Z -150..5650
		Bounds = { HalfWidth = 1300, Uphill = 520, Downhill = 5950 },

		-- Fall-line profile, top to bottom. Angle = degrees downhill (negative climbs).
		-- FromZ is where the segment starts; the profile is smoothed over TransitionLength.
		Profile = {
			{ FromZ = -520, Angle = 22 }, -- peak behind the start
			{ FromZ = -200, Angle = 3 }, -- summit plateau (start area)
			{ FromZ = 220, Angle = 13 }, -- upper powder bowl
			{ FromZ = 1000, Angle = 11 }, -- corridors (shaped per corridor below)
			{ FromZ = 4300, Angle = 12 }, -- lower valley
			{ FromZ = 5000, Angle = 5 }, -- run-out
			{ FromZ = 5300, Angle = 1 }, -- finish basin
			{ FromZ = 5720, Angle = -9 }, -- lip that closes the basin
		},
		TransitionLength = 160,

		Corridors = {
			StartZ = 1000,
			EndZ = 4300,
			FadeLength = 450, -- corridors and ridges fade in and out over this distance
			Width = 230, -- gaussian width of each corridor's influence
			Centers = { -640, 0, 640 }, -- left, centre, right
			Meander = { Amplitude = 70, Wavelength = 1300 },
			-- Centre: rollovers
			Roller = { Amplitude = 7, Wavelength = 190 },
			-- Right: steep pitches with benches. Each period drops the same height as the base
			-- slope; Pitch is the share of the period that does the dropping.
			Steps = { Period = 420, Pitch = 0.5 },
			-- Rounded ridgelines between the corridors
			Ridge = { Height = 55, Width = 115 },
		},

		-- Rounded overall bowl shape and the steep rocky walls that bound the map
		Bowl = { Curvature = 0.00004 },
		Walls = { StartX = 1060, Rise = 0.95, Knee = 60 },

		-- Natural relief, in studs. Noise fades out around the start and finish so they stay clean.
		Relief = {
			Large = { Scale = 420, Amplitude = 16 },
			Medium = { Scale = 130, Amplitude = 5 },
			WindRidges = { ScaleX = 38, ScaleZ = 150, Amplitude = 2.2 }, -- along the fall line
			Drifts = { Scale = 30, Amplitude = 2.6 }, -- rounded mounds only (no pits)
			Snowbank = { Height = 3.5, Width = 26 }, -- along the foot of the walls
			CleanRadius = 170, -- calm ground around the start and finish
		},

		-- Snow everywhere; rock only where it's too steep to hold snow (> ~45°)
		Materials = { RockSlope = 1.0, SlateSlope = 1.35, PatchScale = 26 },
	},
}
