--[[
	DevService (Studio only)
	Developer tools for measuring and tuning movement:
	  - builds the test lanes (TestSlopes)
	  - handles DevTeleport requests: lane index (number) or "Course" (back to the start gate)

	Init returns immediately outside Studio, and the remote handler re-checks RunService:IsStudio()
	so a live server can never be asked to teleport anyone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevConfig = require(ReplicatedStorage.Shared.Config.DevConfig)
local TestSlopes = require(script.Parent.TestSlopes)

local DevService = {}

function DevService.Init(services)
	if not RunService:IsStudio() then
		return
	end

	local PlayerService = services.PlayerService
	local CourseService = services.CourseService
	TestSlopes.Build(DevConfig.TestLanes)

	ReplicatedStorage.Remotes.DevTeleport.OnServerEvent:Connect(function(player, destination)
		if not RunService:IsStudio() then
			return
		end
		if destination == "Course" then
			PlayerService.TeleportTo(player, CourseService.GetSpawnCFrame(0))
		elseif type(destination) == "number" then
			local lane = TestSlopes.Lanes[destination]
			if lane then
				PlayerService.TeleportTo(player, lane.Start)
			end
		end
	end)
end

return DevService
