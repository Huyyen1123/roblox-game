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
			-- Proportioned to a ~5.6-stud blocky R15 avatar (see the style guide): about as wide
			-- as the boot, with a rounded, upturned tip and a small tail kick.
			Color = Color3.fromRGB(220, 50, 50),
			StripeColor = Color3.fromRGB(245, 245, 245),
			Length = 6.8, -- flat running length (the tip kick adds ~0.8 more)
			Width = 0.85, -- waist, under the boot (the boot is ~1.1 wide)
			ShovelWidth = 0.95, -- tip and tail are wider (sidecut)
			Thickness = 0.12,
			TipLength = 0.8,
			TipAngle = 24, -- degrees the tip turns up
			TailLength = 0.35,
			TailAngle = 10,
			MountOffset = 0.3, -- boot sits slightly behind the ski's centre
			Spacing = 1.3, -- matches the hip-width riding stance so each ski sits under a foot
			BindingColor = Color3.fromRGB(35, 35, 40),
			BootColor = Color3.fromRGB(40, 44, 52),
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
			-- Proportioned to a ~5.6-stud R15 avatar: a bit wider than the feet are long, thin,
			-- with a rounded, upturned nose and tail and strap bindings.
			Color = Color3.fromRGB(40, 110, 220),
			BaseColor = Color3.fromRGB(20, 22, 28), -- edges and base
			Length = 6.6, -- tip to tail, including the kicks
			Width = 1.45, -- waist
			NoseWidth = 1.65, -- nose and tail are wider (sidecut)
			Thickness = 0.12,
			KickLength = 1.1, -- length of each upturned end (nose and tail)
			KickAngle = 16,
			BindingSpacing = 1.8, -- stance width between binding centres
			BindingColor = Color3.fromRGB(30, 30, 35),
			StrapColor = Color3.fromRGB(70, 72, 80),
			BootColor = Color3.fromRGB(50, 50, 58),
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
