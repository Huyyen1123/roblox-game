--[[
	EnvironmentConfig
	Cinematic winter-afternoon lighting. Applied by the server's Environment module.
	Lighting.Technology can't be set from scripts; it's set to Future in default.project.json.

	Goals (approved reference board): a clear, sunny alpine afternoon. Deep blue sky with
	soft clouds (Roblox's own sky, no painted skybox: the distant mountains are real
	low-poly peaks), a warm sun low enough to rake across the snow so its relief reads,
	cool blue-grey shadows, and haze that turns distant peaks blue for scale. Exposure is
	kept down so sunlit snow keeps its shading instead of clipping to white.
]]

return {
	Lighting = {
		ClockTime = 15.7,
		GeographicLatitude = 38,
		Brightness = 2.9,
		ExposureCompensation = -0.55,
		Ambient = Color3.fromRGB(40, 50, 76),
		OutdoorAmbient = Color3.fromRGB(118, 134, 170),
		ColorShift_Top = Color3.fromRGB(255, 224, 182),
		ColorShift_Bottom = Color3.fromRGB(150, 170, 205),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.3,
		GlobalShadows = true,
		ShadowSoftness = 0.12,
	},

	-- Haze is tuned with the skybox: thick enough to hide the seam where the painted
	-- mountains meet the horizon, thin enough that their peaks rise clearly out of the mist.
	Atmosphere = {
		Density = 0.36,
		Offset = 0.2,
		Color = Color3.fromRGB(188, 210, 242),
		Decay = Color3.fromRGB(104, 132, 186),
		Glare = 0.5,
		Haze = 1.1,
	},

	-- No painted skybox: Roblox's own blue sky. Any Sky in the place is removed (the old
	-- "Snowy Mountain Skybox" painted hazy mountains that clashed with the real ones).
	Sky = false,

	Clouds = {
		Cover = 0.5,
		Density = 0.5,
		Color = Color3.fromRGB(246, 249, 255),
	},

	ColorCorrection = {
		Brightness = 0,
		Contrast = 0.26,
		Saturation = 0.14,
		TintColor = Color3.fromRGB(255, 251, 246),
	},

	-- Terrain colours (multiply the material textures). Powder a touch below pure white so
	-- sunlit snow keeps its shading.
	TerrainColors = {
		[Enum.Material.Snow] = Color3.fromRGB(228, 236, 248),
		-- Lighter, warmer rock so cliff faces read grey-brown in sun and shadow
		[Enum.Material.Rock] = Color3.fromRGB(150, 140, 134),
		[Enum.Material.Slate] = Color3.fromRGB(128, 124, 128),
	},

	Bloom = {
		Intensity = 0.35,
		Size = 22,
		Threshold = 1.6,
	},

	SunRays = {
		Intensity = 0.1,
		Spread = 0.55,
	},

	-- Terrain surface textures: MaterialVariants (AI-generated PBR, stored in the place's
	-- MaterialService) that replace the stock look of each base material. StudsPerTile is kept
	-- large so the texture doesn't visibly repeat across wide slopes.
	MaterialOverrides = {
		-- Powder (course edges and the mountain) and groomed corduroy (the racing line). Built
		-- from CC0 ambientCG photo sets (Snow004, Snow005) with procedural grooves; see
		-- docs/SNOW_SYSTEM_PLAN.md. AlpineSnowWhite1 stays in the place as the previous look.
		-- Organic pattern randomly rotates and offsets the tiles to hide repetition (not used on
		-- the groomed line, where the faint corduroy must stay aligned with the fall line).
		{ Material = Enum.Material.Snow, Variant = "PowderSoft", StudsPerTile = 22, Pattern = Enum.MaterialPattern.Organic },
		{ Material = Enum.Material.Salt, Variant = "GroomedCorduroy", StudsPerTile = 20, PhysicsLike = Enum.Material.Snow },
		{
			Material = Enum.Material.Limestone,
			Variant = "PackedSnow",
			StudsPerTile = 18,
			Pattern = Enum.MaterialPattern.Organic,
			PhysicsLike = Enum.Material.Snow,
		},
		{ Material = Enum.Material.Rock, Variant = "AlpineGraniteCliff", StudsPerTile = 32 },
		{ Material = Enum.Material.Slate, Variant = "AlpineDarkSlate", StudsPerTile = 32 },
	},
}
