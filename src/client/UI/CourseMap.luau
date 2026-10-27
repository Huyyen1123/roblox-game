--[[
	CourseMap
	Client-side view of the current freeride course for the HUD: the same heightfield the
	server builds the mountain from (shared module), plus where the race checkpoints, start
	and finish are. Built once per course on first use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local FreerideHeightfield = require(ReplicatedStorage.Shared.Course.FreerideHeightfield)

local CourseMap = {}

local cache = {}

-- The local player's course (only freeride courses with a race have a map)
function CourseMap.Get()
	local id = Players.LocalPlayer:GetAttribute("Course") or Courses.Default
	local course = Courses.List[id]
	if not course or course.Kind ~= "Freeride" or not course.Race then
		return nil
	end
	local map = cache[id]
	if map then
		return map
	end
	local heightfield = FreerideHeightfield.new(course)
	local checkpoints = {}
	for index, checkpoint in course.Race.Checkpoints do
		checkpoints[index] = { Z = checkpoint.Z, Beams = heightfield:CheckpointBeams(checkpoint) }
	end
	local origin = course.Origin
	map = {
		Id = id,
		Course = course,
		Heightfield = heightfield,
		Origin = origin,
		Checkpoints = checkpoints,
		Start = origin + Vector3.new(0, heightfield:GetHeight(0, course.Race.StartLineZ), course.Race.StartLineZ),
		Finish = origin + Vector3.new(0, heightfield:GetHeight(0, course.Race.FinishZ), course.Race.FinishZ),
	}
	cache[id] = map
	return map
end

return CourseMap
