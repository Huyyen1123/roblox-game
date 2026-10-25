--[[
	Frostpeak.
	Coordinates are course-local: Z runs downhill from the start (Z = 0), X is across the slope.
	World position = Origin + local position. Segment Z ranges are listed in comments.

	The racing line (segments, meander, kickers, gates, start/finish) defines gameplay.
	The World table only shapes the scenery around it: a mountainside rising on the -X side,
	a drop into a wide valley on the +X side, a summit behind the start and a resort plaza
	below the finish. Bump World.TerrainVersion whenever a terrain-affecting value changes so
	baked terrain in the place file gets regenerated.
]]

return {
	Id = "Frostpeak",
	DisplayName = "Frostpeak",
	Seed = 1337,

	-- Placed away from the world origin, leaving room for other areas.
	Origin = Vector3.new(0, 0, 1500),
	StartY = 600,

	Segments = {
		{ Length = 80, Angle = 2 }, -- 0-80     start area (gentle pitch so riders roll toward the gate)
		{ Length = 300, Angle = 14 }, -- 80-380   warm-up
		{ Length = 250, Angle = 22 }, -- 380-630  first steep
		{ Length = 220, Angle = 10 }, -- 630-850  mellow
		{ Length = 300, Angle = 18 }, -- 850-1150 cruiser
		{ Length = 220, Angle = 9 }, -- 1150-1370 jump zone
		{ Length = 350, Angle = 24 }, -- 1370-1720 the wall
		{ Length = 240, Angle = 13 }, -- 1720-1960 rollers
		{ Length = 150, Angle = 5 }, -- 1960-2110 run-out
		{ Length = 200, Angle = 0 }, -- 2110-2310 finish flat
	},
	TransitionLength = 40,

	Meander = { Amplitude = 70, Wavelength = 700, Start = 150, EndFade = 350 },

	Rollers = {
		{ StartZ = 1730, EndZ = 1950, Amplitude = 2.5, Wavelength = 55 },
	},

	World = {
		TerrainVersion = 12,

		-- Terrain is generated this far from the centre line / course ends.
		Extent = { Mountain = 640, Valley = 1500, Uphill = 420, Downhill = 1400 },

		Piste = { HalfWidth = 70, NoiseScale = 45, NoiseAmplitude = 0.8 },

		-- -X side: snow berm, then a mountainside with ridged cliff bands.
		MountainSide = { BermWidth = 35, BermHeight = 9, RiseSlope = 0.6, RidgeAmplitude = 110, RidgeScale = 380, RidgeFadeIn = 200 },

		-- +X side: a low lip, then the slope falls away into a valley.
		ValleySide = { LipWidth = 20, LipHeight = 3, DropStart = 40, DropSlope = 0.8, FloorY = -170, FloorNoise = 10 },

		-- Mountain ranges across the valley (+X) and beyond the resort (downhill), measured from
		-- the centre line / course end. Height is above the valley floor.
		Ranges = {
			Valley = { Start = 820, FullAt = 1300, BaseHeight = 260, PeakHeight = 520, Scale = 650, CrestWeight = 0.35 },
			Downhill = { Start = 760, FullAt = 1250, BaseHeight = 280, PeakHeight = 560, Scale = 700, CrestWeight = 0.35 },
		},

		-- Behind the start the mountain keeps rising to a summit.
		Summit = { RiseSlope = 0.5, Curve = 0.0012 },

		-- Below the finish: a gentle uphill run-out that stops riders, a flat resort plaza, then the valley.
		RunOut = { Length = 150, Angle = 6 },
		Plaza = { Length = 220, DropSlope = 0.7 },

		Noise = { Scale = 110, Amplitude = 6 },
		Materials = { RockSlope = 1.25, MixedSlope = 0.8, SnowyEdge = 90, EdgeRockSlope = 1.7 },
		-- Three snow surfaces, each its own base material so each gets its own texture:
		-- groomed racing line → wind-packed band → powder. Both boundaries are ragged (two
		-- noise scales), so there is no straight line anywhere.
		Surfaces = {
			Groomed = Enum.Material.Salt,
			Packed = Enum.Material.Limestone,
			BlendWidth = 12, -- how ragged the groomed edge is
			PackedWidth = 22, -- average width of the packed band beyond the piste edge
			BlendNoiseScale = 9,
			FineNoiseScale = 3,
		},
		Lake = { Scale = 380, Threshold = 0.12 },

		Boulders = { Count = 90, MinRadius = 3, MaxRadius = 10 },

		Forest = { Spacing = 15, NearDistance = 150, MaxDistance = 700, MinPisteGap = 14, MaxSlope = 0.75, Density = 0.55, FarDensity = 0.3, NoiseScale = 180 },

	},

	-- Soft powder drifts and ridges along both edges, outside the fences. Visual only: no
	-- collision, no queries, so riding and ground detection never see them. Each is a large
	-- sphere sunk into the slope so only a low, soft cap shows.
	Drifts = {
		StartZ = 40,
		EndZ = 2440,
		Spacing = 6.5, -- studs between drifts along each edge (jittered)
		MinOffset = 4, -- studs beyond the fence line
		MaxOffset = 40,
		MinRadius = 7,
		MaxRadius = 20,
		MinCap = 0.9, -- visible height
		MaxCap = 3.6,
		RidgeChance = 0.45, -- some drifts get a smaller companion, forming a ridge
	},

	-- Placed so each lands on a steeper section below it.
	Kickers = {
		{ Z = 330, Width = 14, Height = 3.5, Length = 16, OffsetX = 0 },
		{ Z = 820, Width = 18, Height = 5, Length = 22, OffsetX = 0 },
		{ Z = 1240, Width = 14, Height = 3.5, Length = 16, OffsetX = -20 },
		{ Z = 1240, Width = 14, Height = 3.5, Length = 16, OffsetX = 20 },
		{ Z = 1335, Width = 20, Height = 6, Length = 26, OffsetX = 0 },
	},

	-- On-piste obstacles, built as snow-capped terrain boulders.
	Rocks = {
		{ Z = 500, OffsetX = 32, Size = 7 },
		{ Z = 980, OffsetX = -36, Size = 8 },
		{ Z = 1600, OffsetX = 26, Size = 6 },
		{ Z = 1850, OffsetX = -30, Size = 7 },
	},

	Gates = { StartZ = 180, EndZ = 2000, Spacing = 150, Offset = 22, KickerClearance = 45 },
	Fences = { StartZ = 60, EndZ = 2440, SegmentLength = 16, Inset = 6 },

	-- Detailed course dressing. Applied to the benchmark section first; widen the range once
	-- that section is signed off.
	Dressing = {
		StartZ = 0,
		EndZ = 650,
		SnowbankHeight = 2.4, -- smooth ridge of snow piled against the netting (terrain)
		SnowbankWidth = 3.5,
		BannerSpacing = 64, -- red banners on poles along the netting
		MarkerSpacing = 40, -- trail marker poles just outside the piste
	},

	Start = { Z = 25 },
	Finish = { Z = 2150 },

	KillDepth = 80, -- below the lowest point of the terrain
}
