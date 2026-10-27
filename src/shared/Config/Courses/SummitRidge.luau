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

	Race: start at the summit, finish in the basin. Checkpoints span the whole mountain (any
	route between them counts); orange beams mark them. Route character:
	  left    trick park in the upper bowl, then gentle powder and a pine forest to dodge
	  centre  fast rollers, two big kickers, a cave tunnel
	  right   steep pitches and benches, a narrow rock passage, the frozen waterfall
	The lower valley rejoins them for the big air above the finish and the frozen lake.
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

	-- Race checkpoints (course-local Z; each spans the whole mountain). Beams mark where routes
	-- cross them: Beams = X positions, or corridor indexes resolved at that Z.
	Race = {
		StartLineZ = 40, -- the clock starts when a rider crosses this
		Checkpoints = {
			{ Z = 640, Beams = { -760, 0 } },
			{ Z = 1500, Corridors = { 1, 2, 3 } },
			{ Z = 2400, Corridors = { 1, 2, 3 } },
			{ Z = 3300, Corridors = { 1, 2, 3 } },
			{ Z = 4150, Corridors = { 1, 2, 3 } },
			{ Z = 4800, Beams = { 0 } },
		},
		FinishZ = 5450,
		-- Checkpoint crossings faster than this (studs/s between checks) are rejected
		MaxSpeed = 260,
	},

	-- Places a rider can ask to go (HUD buttons / keys): local X, Z
	Spots = {
		Summit = { X = 0, Z = 0 },
		TrickPark = { X = -760, Z = 200 },
	},

	World = {
		TerrainVersion = 7,
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
		Walls = { StartX = 1060, Rise = 0.95, Knee = 60, MaxRise = 300 },

		-- Mountain range around the playable area (terrain, baked with the course). Inner box
		-- = the area it leaves alone; Fade = distance outside it over which the range grows.
		Range = {
			Bounds = { HalfWidth = 3300, Uphill = 2300, Downhill = 8100 },
			InnerX = 1150,
			InnerUphill = -380,
			InnerDownhill = 5800,
			Fade = { 60, 700 },
			Base = 160,
			PeakScale = 900, -- spacing of the main peaks
			PeakHeight = 850,
			PeakSharpness = 2, -- higher = narrower, sharper peaks
			RidgeScale = 260, -- secondary ridges and spurs
			RidgeHeight = 220,
		},

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
		Materials = { RockSlope = 1.0, SlateSlope = 1.35, PatchScale = 26, RangeSnowBonus = 0.9 },

		-- Shaped into the terrain (FreerideHeightfield). Kickers: X, or Corridor (+ Offset);
		-- Z is the lip; Height above the slope; Length of the ramp; Width. The lip angle above
		-- the slope is about atan(2 · Height / Length); behind the lip the snow rolls back
		-- down over half the ramp length (a knuckle) onto the natural landing slope.
		Features = {
			Kickers = {
				-- Trick park: four sizes in a row, small to extra large. Lip angles (above the
				-- slope) grow with size: ~20°, 23°, 27°, 32°. Natural air ~0.3, 0.6, 0.65, 1.0 s;
				-- a charged jump at the XL lip gives ~1.6 s (a double flip).
				{ Name = "Park S", X = -760, Z = 330, Height = 3, Length = 16, Width = 26 },
				{ Name = "Park M", X = -760, Z = 520, Height = 5, Length = 24, Width = 30 },
				{ Name = "Park L", X = -760, Z = 740, Height = 8, Length = 32, Width = 34 },
				{ Name = "Park XL", X = -760, Z = 1000, Height = 16, Length = 52, Width = 44 },
				-- Along the routes
				{ Corridor = 2, Z = 1880, Height = 6, Length = 28, Width = 64 },
				{ Corridor = 2, Z = 3020, Height = 8, Length = 34, Width = 64 },
				{ Corridor = 1, Z = 1420, Height = 3.5, Length = 18, Width = 46 },
				{ Corridor = 1, Z = 3800, Height = 4.5, Length = 22, Width = 50 },
				{ Corridor = 3, Z = 4000, Height = 5, Length = 24, Width = 50 },
				-- Big air above the finish
				{ Name = "Big Air", X = 0, Z = 4620, Height = 18, Length = 56, Width = 90 },
			},
			-- Frozen lake beside the run-out (flat ice, soft shore)
			Lake = { X = 620, Z = 5080, RadiusX = 190, RadiusZ = 120, Shore = 0.35, Depth = 1.5 },
		},

		-- Scenery built from parts (server/Course/MountainBuilder), placed from the terrain
		Scenery = {
			-- Pine forest: jittered grid, density from noise stands plus the sections below
			Forest = {
				Spacing = 22,
				BaseDensity = 0.04,
				StandScale = 260,
				StandDensity = 0.42, -- extra density inside stands
				MaxSlope = 0.85,
				-- Dense sections riders thread through (no clear lane)
				Sections = {
					{ Corridor = 1, FromZ = 1700, ToZ = 2700, HalfWidth = 170, Density = 0.42 },
					{ Corridor = 3, FromZ = 3350, ToZ = 3800, HalfWidth = 150, Density = 0.3 },
				},
				-- Kept clear: fast lanes and feature run-ins (corridor, half width)
				ClearLanes = {
					{ Corridor = 2, HalfWidth = 46 },
					{ Corridor = 3, HalfWidth = 30 },
				},
				ClearRadius = 70, -- around kickers, checkpoint beams, the cave and the start/finish
				ParkLane = { X = -760, HalfWidth = 70, FromZ = 150, ToZ = 1150 },
				ColliderDistance = 150, -- trees this close to a corridor centre get a trunk collider
			},
			-- Angular rock formations
			Rocks = {
				RidgeSpacing = 230, -- clusters along the ridgelines between corridors
				WallSpacing = 70, -- cliff columns along the boundary walls
				-- Formations lining the routes: every RouteSpacing studs each side of each
				-- corridor has this chance of a cluster, RouteOffset studs from its centre
				RouteSpacing = 260,
				RouteChance = 0.55,
				RouteOffset = { 75, 150 },
				WallX = 1095,
				-- A narrow rock passage across the right corridor (gap at its centre)
				Passage = { Corridor = 3, Z = 2650, Gap = 34, Depth = 70 },
				-- Rock outcrops and drops placed by hand
				Outcrops = {
					{ Corridor = 3, Z = 2150, Offset = 0, Size = 16, Drop = true },
					{ Corridor = 1, Z = 3050, Offset = 60, Size = 22 },
					{ Corridor = 2, Z = 2450, Offset = -80, Size = 18 },
					{ X = 250, Z = 4400, Size = 26 },
					{ X = -330, Z = 4950, Size = 20 },
				},
			},
			-- Cave tunnel over the centre route
			Cave = { Corridor = 2, FromZ = 3480, ToZ = 3570, Width = 34, Height = 22 },
			-- Frozen waterfall on the right wall, with a frozen pool below
			Waterfall = { X = 1050, Z = 3920, Height = 80, Width = 26 },
			-- Distant low-poly mountains around the map (scale; the atmosphere hazes them).
			-- Distance beyond the map edge; Height of the tallest peak in a massif; Sink = how
			-- far below the course's profile the bases sit.
			Panorama = {
				-- Beyond the terrain mountain range: the far horizon
				Bands = {
					{ Distance = { 2700, 3900 }, Height = { 1400, 2300 }, Spacing = 1500, Sink = 700 },
				},
			},
		},
	},
}
