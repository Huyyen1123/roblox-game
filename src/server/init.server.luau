--[[
	Server bootstrap. Services initialise in dependency order:
	PlayerService hooks up players immediately, and waits on CourseService before spawning anyone.
]]

local RunService = game:GetService("RunService")

local Services = script.Services

local CourseService = require(Services.CourseService)
local EquipmentService = require(Services.EquipmentService)
local PlayerService = require(Services.PlayerService)
local RaceService = require(Services.RaceService)

PlayerService.Init({
	CourseService = CourseService,
	EquipmentService = EquipmentService,
	RaceService = RaceService,
})

CourseService.Init()
RaceService.Init()
PlayerService.Start()

if RunService:IsStudio() then
	require(script.Dev.DevService).Init({
		PlayerService = PlayerService,
		CourseService = CourseService,
	})
end
