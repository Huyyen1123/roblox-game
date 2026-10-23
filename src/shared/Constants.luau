--[[
	Names shared between client and server so they never drift apart.
]]

return {
	RiderCollisionGroup = "Riders",
	CourseFolderName = "Course",
	EquipmentModelName = "Equipment",

	Attributes = {
		Sport = "Sport", -- Player: selected sport id
		InRace = "InRace", -- Player: true while in an active race (Phase 4)
		CourseReady = "CourseReady", -- Course folder: true once built
		KillY = "KillY", -- Course folder: riders below this are reset
	},
}
