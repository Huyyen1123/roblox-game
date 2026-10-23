--[[
	Course registry. Add new mountains here; CourseService builds the one named by Default.
]]

return {
	Default = "Frostpeak",
	List = {
		Frostpeak = require(script.Frostpeak),
	},
}
