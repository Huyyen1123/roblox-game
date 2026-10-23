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

	Atmosphere = {
		Density = 0.24,
		Offset = 0.2,
		Color = Color3.fromRGB(214, 224, 240),
		Decay = Color3.fromRGB(150, 166, 196),
		Glare = 0.2,
		Haze = 0.8,
	},

	Sky = {
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
}
