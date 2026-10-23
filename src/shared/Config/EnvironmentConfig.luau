--[[
	EnvironmentConfig
	Cinematic winter-afternoon lighting. Applied by the server's Environment module.
	Lighting.Technology can't be set from scripts; it's set to Future in default.project.json.

	Goals: crisp white snow without blowing out, cool blue shadows, a warm low sun,
	and haze that gives distance without hiding the course.
]]

return {
	Lighting = {
		ClockTime = 14.6,
		GeographicLatitude = 38,
		Brightness = 3.2,
		ExposureCompensation = 0,
		Ambient = Color3.fromRGB(60, 66, 82),
		OutdoorAmbient = Color3.fromRGB(140, 146, 162),
		ColorShift_Top = Color3.fromRGB(255, 244, 228),
		ColorShift_Bottom = Color3.fromRGB(170, 182, 205),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 0.5,
		GlobalShadows = true,
		ShadowSoftness = 0.15,
	},

	-- Haze is tuned with the skybox: thick enough to hide the seam where the painted
	-- mountains meet the horizon, thin enough that their peaks rise clearly out of the mist.
	Atmosphere = {
		Density = 0.22,
		Offset = 0.35,
		Color = Color3.fromRGB(214, 224, 240),
		Decay = Color3.fromRGB(150, 166, 196),
		Glare = 0.2,
		Haze = 1.2,
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
		Cover = 0.55,
		Density = 0.4,
		Color = Color3.fromRGB(246, 249, 255),
	},

	ColorCorrection = {
		Brightness = 0,
		Contrast = 0.1,
		Saturation = -0.02,
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
		{ Material = Enum.Material.Snow, Variant = "AlpineSnowWhite1", StudsPerTile = 16 },
		{ Material = Enum.Material.Rock, Variant = "AlpineGraniteCliff", StudsPerTile = 32 },
		{ Material = Enum.Material.Slate, Variant = "AlpineDarkSlate", StudsPerTile = 32 },
	},
}
