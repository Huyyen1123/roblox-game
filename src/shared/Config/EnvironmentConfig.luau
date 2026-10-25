--[[
	EnvironmentConfig
	Cinematic winter-afternoon lighting. Applied by the server's Environment module.
	Lighting.Technology can't be set from scripts; it's set to Future in default.project.json.

	Goals (Steep-inspired reference): late-afternoon alpine light. A lower, warm sun rakes
	across the snow so its relief, grooves and drifts read; shadows and sky-lit snow go cool
	blue-grey; clearer air so distant peaks stay crisp.
]]

return {
	Lighting = {
		ClockTime = 16.1,
		GeographicLatitude = 38,
		Brightness = 3.4,
		ExposureCompensation = -0.55,
		Ambient = Color3.fromRGB(46, 54, 76),
		OutdoorAmbient = Color3.fromRGB(112, 126, 160),
		ColorShift_Top = Color3.fromRGB(255, 238, 214),
		ColorShift_Bottom = Color3.fromRGB(150, 170, 205),
		EnvironmentDiffuseScale = 0.8,
		EnvironmentSpecularScale = 0.35,
		GlobalShadows = true,
		ShadowSoftness = 0.12,
	},

	-- Haze is tuned with the skybox: thick enough to hide the seam where the painted
	-- mountains meet the horizon, thin enough that their peaks rise clearly out of the mist.
	Atmosphere = {
		Density = 0.14,
		Offset = 0.3,
		Color = Color3.fromRGB(214, 224, 240),
		Decay = Color3.fromRGB(150, 166, 196),
		Glare = 0.35,
		Haze = 0.6,
	},

	-- Distant mountain panorama ("Snowy Mountain Skybox", Creator Store asset 402232085,
	-- audited: a plain Sky with image textures, no scripts).
	Sky = {
		SkyboxBk = "rbxassetid://402229526",
		SkyboxFt = "rbxassetid://402229293",
		SkyboxUp = "rbxassetid://402229564",
		SkyboxDn = "rbxassetid://402229596",
		SkyboxLf = "rbxassetid://402229368",
		SkyboxRt = "rbxassetid://402229417",
		CelestialBodiesShown = true,
		SunAngularSize = 13,
		MoonAngularSize = 9,
		StarCount = 0,
	},

	Clouds = {
		Cover = 0.28,
		Density = 0.4,
		Color = Color3.fromRGB(246, 249, 255),
	},

	ColorCorrection = {
		Brightness = 0,
		Contrast = 0.18,
		Saturation = 0.06,
		TintColor = Color3.fromRGB(255, 253, 250),
	},

	Bloom = {
		Intensity = 0.35,
		Size = 22,
		Threshold = 1.6,
	},

	SunRays = {
		Intensity = 0.05,
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
