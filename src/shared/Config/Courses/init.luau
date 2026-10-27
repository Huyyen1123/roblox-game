--[[
	Course registry. Add new mountains here.
	CourseService builds every course in Build (each in its own area of the world, sharing one
	Terrain), plus DevBuild in Studio, and spawns players on Default.
]]

return {
	Default = "SummitRidge",
	Build = { "SummitRidge" },
	-- Also built in Studio only (dev shortcut F9); live servers skip them to save memory
	DevBuild = { "Frostpeak" },
	List = {
		SummitRidge = require(script.SummitRidge),
		Frostpeak = require(script.Frostpeak),
	},
}
