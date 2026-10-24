--[[
	SportConfig
	Skiing and snowboarding definitions. Both sports share the exact same BaseStats so neither
	has a competitive advantage. Equipment (Phase 6) will apply multipliers on top of these.
]]

local BaseStats = table.freeze({
	Speed = 1,
	Acceleration = 1,
	Handling = 1,
	Stability = 1,
	Airtime = 1,
})

local Sports = {
	Ski = {
		Id = "Ski",
		DisplayName = "Skiing",
		Tagline = "Two edges. Precise carving.",
		Description = "Classic downhill on twin skis. Quick edge changes and a forward-facing stance.",
		AccentColor = Color3.fromRGB(230, 70, 70),
		Equipment = {
			Kind = "Skis",
			Color = Color3.fromRGB(220, 50, 50),
			Size = Vector3.new(0.35, 0.18, 6.5),
			Spacing = 1.3, -- matches the hip-width riding stance so each ski sits under a foot
			Poles = {
				Length = 3.8,
				ShaftColor = Color3.fromRGB(190, 195, 205),
				GripColor = Color3.fromRGB(30, 30, 35),
				BasketColor = Color3.fromRGB(25, 25, 28),
				TipColor = Color3.fromRGB(120, 120, 125),
			},
		},
	},
	Snowboard = {
		Id = "Snowboard",
		DisplayName = "Snowboarding",
		Tagline = "One board. Big style.",
		Description = "A single board with a sideways stance. Smooth, flowing turns and a freestyle feel.",
		AccentColor = Color3.fromRGB(60, 140, 235),
		Equipment = {
			Kind = "Board",
			Color = Color3.fromRGB(40, 110, 220),
			Size = Vector3.new(1.4, 0.2, 5.6),
		},
	},
}

local SportConfig = {
	Sports = Sports,
	Order = { "Ski", "Snowboard" },
	BaseStats = BaseStats,
}

function SportConfig.IsValid(sportId: any): boolean
	return type(sportId) == "string" and Sports[sportId] ~= nil
end

function SportConfig.GetStats(_sportId: string?)
	-- Identical for every sport by design; equipment modifiers are layered on in Phase 6.
	return BaseStats
end

return SportConfig
