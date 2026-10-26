--[[
	Course registry. Add new mountains here.
	CourseService builds every course in Build (each in its own area of the world, sharing one
	Terrain) and spawns players on Default.
]]

return {
	Default = "SummitRidge",
	Build = { "SummitRidge", "Frostpeak" },
	List = {
		SummitRidge = require(script.SummitRidge),
		Frostpeak = require(script.Frostpeak),
	},
}
