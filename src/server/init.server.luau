--[[
	Server bootstrap. Services initialise in dependency order:
	PlayerService hooks up players immediately, and waits on CourseService before spawning anyone.
]]

local Services = script.Services

local CourseService = require(Services.CourseService)
local EquipmentService = require(Services.EquipmentService)
local PlayerService = require(Services.PlayerService)

PlayerService.Init({
	CourseService = CourseService,
	EquipmentService = EquipmentService,
})

CourseService.Init()
PlayerService.Start()
