--[[
	DevConfig
	Studio-only developer tools: movement test lanes and the speed logger.
	None of this exists on live servers (DevService and the client dev tools check IsStudio).

	Keys (Studio playtests only):
	  F6  start / stop a speed log (summary prints to Output)
	  F7  teleport to the next test lane
	  F8  teleport back to the course start
]]

return {
	TestLanes = {
		Angles = { 10, 18, 24 }, -- cruise / mid / racing-tuck reference slopes
		Origin = Vector3.new(-3000, 400, 0),
		LaneSpacing = 120,
		LaneWidth = 60,
		SlopeLength = 1600, -- long enough to reach top speed at prototype speeds
		RunoutLength = 500,
		ObstacleLane = 2, -- post in the middle of the 18° lane for impact tests
		ObstacleDistance = 300,
	},

	SpeedLog = {
		SampleRate = 10, -- samples per second
		PrintEvery = 1, -- seconds between rows in the printed table
		SteadyWindow = 3, -- seconds at the end of a log averaged as "steady" speed
	},

	Keys = {
		ToggleSpeedLog = Enum.KeyCode.F6,
		NextLane = Enum.KeyCode.F7,
		Course = Enum.KeyCode.F8,
	},
}
