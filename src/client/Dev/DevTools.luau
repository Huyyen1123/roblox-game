--[[
	DevTools (Studio only)
	  F6  start / stop a speed log. On stop, a summary and a per-second table print to Output,
	      and the summary is also stored in the LocalPlayer's "SpeedLogSummary" attribute.
	  F7  teleport to the next test lane (10° / 18° / 24°)
	  F8  Summit Ridge (freeride test mountain), from the summit
	  F9  Frostpeak (original course), from its start gate
	Speeds are shown in km/h using the same conversion as the HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DevConfig = require(ReplicatedStorage.Shared.Config.DevConfig)
local Units = require(ReplicatedStorage.Shared.Util.Units)

local player = Players.LocalPlayer

local DevTools = {}

local Movement
local logging = false
local samples = {}
local logStart = 0
local sampleAccumulator = 0
local nextLane = 1

local function kmh(studsPerSecond: number): number
	return Units.StudsPerSecondToKmh(studsPerSecond)
end

local function startLog()
	table.clear(samples)
	logStart = os.clock()
	sampleAccumulator = 0
	logging = true
	print("[SpeedLog] recording… press F6 again to stop")
end

local function stopLog()
	logging = false
	if #samples < 2 then
		print("[SpeedLog] not enough samples")
		return
	end

	local settings = DevConfig.SpeedLog
	local duration = samples[#samples].T
	local distance, maxSpeed, sum = 0, 0, 0
	for i, sample in samples do
		sum += sample.Speed
		maxSpeed = math.max(maxSpeed, sample.Speed)
		if i > 1 then
			distance += (sample.Position - samples[i - 1].Position).Magnitude
		end
	end
	local steadySum, steadyCount = 0, 0
	for _, sample in samples do
		if sample.T >= duration - settings.SteadyWindow then
			steadySum += sample.Speed
			steadyCount += 1
		end
	end

	local summary = string.format(
		"%.1fs  %.0f studs  avg %.1f km/h  max %.1f km/h  steady(last %ds) %.1f km/h",
		duration,
		distance,
		kmh(sum / #samples),
		kmh(maxSpeed),
		settings.SteadyWindow,
		kmh(steadySum / math.max(steadyCount, 1))
	)
	player:SetAttribute("SpeedLogSummary", summary)
	print("[SpeedLog] " .. summary)
	print("[SpeedLog]   t(s)   km/h   slope°  tuck  mode")
	local nextRow = 0
	for _, sample in samples do
		if sample.T >= nextRow then
			print(string.format("[SpeedLog] %6.1f %6.1f %7.1f %5.0f%%  %s", sample.T, kmh(sample.Speed), sample.Slope, sample.Tuck * 100, sample.Mode))
			nextRow += settings.PrintEvery
		end
	end
end

local function sample(dt: number)
	if not logging then
		return
	end
	sampleAccumulator += dt
	local interval = 1 / DevConfig.SpeedLog.SampleRate
	if sampleAccumulator < interval then
		return
	end
	sampleAccumulator -= interval

	local state = Movement.State
	if not state.Root then
		return
	end
	table.insert(samples, {
		T = os.clock() - logStart,
		Position = state.Root.Position,
		Speed = state.Speed,
		Slope = state.SlopeAngle,
		Tuck = state.Tuck,
		Mode = state.Mode,
	})
end

function DevTools.Start(movementController)
	if not RunService:IsStudio() then
		return
	end
	Movement = movementController
	local keys = DevConfig.Keys
	local remote = ReplicatedStorage.Remotes:WaitForChild("DevTeleport")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == keys.ToggleSpeedLog then
			if logging then
				stopLog()
			else
				startLog()
			end
		elseif input.KeyCode == keys.NextLane then
			remote:FireServer(nextLane)
			nextLane = nextLane % #DevConfig.TestLanes.Angles + 1
		elseif input.KeyCode == keys.SummitRidge then
			remote:FireServer("SummitRidge")
		elseif input.KeyCode == keys.Frostpeak then
			remote:FireServer("Frostpeak")
		elseif input.KeyCode == keys.TrickLaunch then
			Movement.DevLaunch(DevConfig.TrickLaunchSpeed)
		end
	end)

	RunService.Heartbeat:Connect(sample)
end

return DevTools
