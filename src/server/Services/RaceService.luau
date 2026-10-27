--[[
	RaceService
	Server-authoritative race timing on courses with a Race definition (Summit Ridge).

	A run starts when a rider placed at the summit crosses the start line, then must cross
	every checkpoint in order (each spans the whole mountain, so any route between them
	counts) and the finish. The server reads positions from its own view of each character
	(10 times a second) and rejects a run that covers more ground than the course's MaxSpeed
	allows over the last second (teleports, speed hacks). Positions replicate in bursts, so
	single checks are never judged on their own. Riders sent to a practice spot (the trick
	park) ride free, untimed, until they go back to the summit.

	Each change is sent to that rider's client through Remotes.RaceEvent:
	  ("Ready")                          at the summit, waiting for the start line
	  ("Start")                          clock started
	  ("Checkpoint", index, count, time) checkpoint passed (seconds since the start)
	  ("Finish", time, best)             finished (best = the rider's best time)
	  ("Free")                           practising, untimed
	  ("Invalid")                        the run was rejected
	Phase and best time are also player attributes (RacePhase, BestTime).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)

local Remotes = ReplicatedStorage.Remotes

local CHECK_INTERVAL = 0.1
local SPEED_WINDOW = 1 -- seconds of history the speed check looks back over
local SPEED_SLACK = 40 -- studs of allowance on top (network jitter)

local RaceService = {}

local runs: { [Player]: any } = {}

local function send(player: Player, ...)
	Remotes.RaceEvent:FireClient(player, ...)
end

local function setPhase(player: Player, run, phase: string)
	run.Phase = phase
	player:SetAttribute("RacePhase", phase)
	player:SetAttribute(Constants.Attributes.InRace, phase == "Racing")
end

local function courseOf(player: Player)
	local id = player:GetAttribute("Course") or Courses.Default
	local course = Courses.List[id]
	return if course and course.Race then course else nil
end

-- Called by PlayerService after every teleport. spot: "Summit" starts a fresh run; any
-- other spot rides free.
function RaceService.OnPlaced(player: Player, spot: string)
	local course = courseOf(player)
	local run = { Phase = "Free", Next = 1, Start = 0, History = {} }
	runs[player] = run
	if course and spot == "Summit" then
		setPhase(player, run, "Ready")
		send(player, "Ready")
	else
		setPhase(player, run, "Free")
		send(player, "Free")
	end
end

local function invalidate(player: Player, run)
	setPhase(player, run, "Free")
	send(player, "Invalid")
end

local function check(player: Player, run, now: number)
	local course = courseOf(player)
	local _, root = CharacterUtil.GetAlive(player.Character)
	if not course or not root then
		return
	end
	local race = course.Race
	local position = root.Position - course.Origin

	-- Plausibility: no more ground covered over the last second than the course allows
	local history = run.History
	table.insert(history, { Position = position, Time = now })
	while #history > 2 and now - history[2].Time >= SPEED_WINDOW do
		table.remove(history, 1)
	end
	local oldest = history[1]
	if run.Phase == "Racing" and now - oldest.Time > 0 then
		local allowed = race.MaxSpeed * (now - oldest.Time) + SPEED_SLACK
		if (position - oldest.Position).Magnitude > allowed then
			invalidate(player, run)
		end
	end

	if run.Phase == "Ready" then
		if position.Z >= race.StartLineZ then
			run.Start = now
			run.Next = 1
			setPhase(player, run, "Racing")
			send(player, "Start")
		end
	elseif run.Phase == "Racing" then
		local checkpoint = race.Checkpoints[run.Next]
		if checkpoint and position.Z >= checkpoint.Z then
			send(player, "Checkpoint", run.Next, #race.Checkpoints, now - run.Start)
			run.Next += 1
		elseif not checkpoint and position.Z >= race.FinishZ then
			local time = now - run.Start
			local best = player:GetAttribute("BestTime")
			if not best or time < best then
				best = time
				player:SetAttribute("BestTime", best)
			end
			setPhase(player, run, "Finished")
			send(player, "Finish", time, best)
		end
	end
end

function RaceService.Init()
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then
			return
		end
		elapsed = 0
		local now = os.clock()
		for player, run in runs do
			if player.Parent then
				check(player, run, now)
			end
		end
	end)
end

return RaceService
