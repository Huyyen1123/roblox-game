--[[
	CourseService
	Builds every course listed in Courses.Build at server start, each in its own area of the
	world, and answers spawn/bounds questions. Players spawn on Courses.Default unless their
	"Course" attribute names another one (set by the dev teleport).
	Clients read the Course folder's attributes (KillY, CourseReady) rather than course config.

	Terrain is the slow part, so it is baked into the place file: each course has its own bake
	marker attribute on Workspace.Terrain ("<course id>:<TerrainVersion>"). When the marker
	matches the config the terrain is reused; otherwise only that course's area is cleared and
	regenerated. Run CourseService.Init() in edit mode and save the place to bake. Props,
	forest and dressing are always rebuilt at runtime (Frostpeak only; freeride maps have none
	yet).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local Course = script.Parent.Parent.Course
local Heightfield = require(Course.Heightfield)
local FreerideHeightfield = require(Course.FreerideHeightfield)
local TerrainBuilder = require(Course.TerrainBuilder)
local PropBuilder = require(Course.PropBuilder)
local ForestBuilder = require(Course.ForestBuilder)
local DressingBuilder = require(Course.DressingBuilder)
local SnowDriftBuilder = require(Course.SnowDriftBuilder)
local Environment = require(Course.Environment)

local SPAWN_HEIGHT = 5
local SPAWN_COLUMNS = 5
local SPAWN_SPACING = 6

local CourseService = {}
CourseService.Courses = {} -- [id] = { Definition, Heightfield, Folder }
CourseService.Heightfield = nil -- default course's heightfield
CourseService.Folder = nil -- parent folder of all courses

local readyEvent = Instance.new("BindableEvent")

local function newHeightfield(definition)
	if definition.Kind == "Freeride" then
		return FreerideHeightfield.new(definition)
	end
	return Heightfield.new(definition)
end

-- Regenerates a course's terrain only when its bake marker doesn't match the config.
local function ensureTerrain(definition, heightfield): boolean
	local terrain = Workspace.Terrain
	local attribute = definition.World.BakeAttribute or `CourseTerrain_{definition.Id}`
	local version = `{definition.Id}:{definition.World.TerrainVersion}`
	local baked = terrain:GetAttribute(attribute)
	if baked == version then
		return false
	end
	if baked ~= nil then
		-- Our own older terrain: clear this course's area so nothing stale is left floating
		TerrainBuilder.ClearArea(heightfield)
	end
	TerrainBuilder.Build(heightfield)
	terrain:SetAttribute(attribute, version)
	return true
end

local function buildCourse(definition, parent: Instance)
	local started = os.clock()
	local heightfield = newHeightfield(definition)
	local folder = Create("Folder", { Name = definition.Id })
	folder:SetAttribute("CourseId", definition.Id)
	folder.Parent = parent

	local generated = ensureTerrain(definition, heightfield)
	local terrainTime = os.clock() - started
	local trees = 0
	if definition.Kind ~= "Freeride" then
		PropBuilder.Build(heightfield, folder)
		trees = ForestBuilder.Build(heightfield, folder)
		DressingBuilder.Build(heightfield, folder)
		SnowDriftBuilder.Build(heightfield, folder)
	end

	CourseService.Courses[definition.Id] = { Definition = definition, Heightfield = heightfield, Folder = folder }
	print(string.format(
		"[CourseService] Built %s in %.2fs (terrain %s %.2fs, %d trees)",
		definition.DisplayName,
		os.clock() - started,
		if generated then "generated" else "baked",
		terrainTime,
		trees
	))
	return heightfield
end

function CourseService.Init()
	assert(Courses.List[Courses.Default], `Unknown default course {Courses.Default}`)

	local existing = Workspace:FindFirstChild(Constants.CourseFolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Create("Folder", { Name = Constants.CourseFolderName })
	folder:SetAttribute("CourseId", Courses.Default)
	folder.Parent = Workspace
	CourseService.Folder = folder

	Environment.Apply()
	local killY = math.huge
	for _, id in Courses.Build do
		local definition = Courses.List[id]
		local heightfield = buildCourse(definition, folder)
		killY = math.min(killY, definition.Origin.Y + heightfield.MinY - definition.KillDepth)
	end
	CourseService.Heightfield = CourseService.Courses[Courses.Default].Heightfield

	-- One kill plane below every course
	folder:SetAttribute(Constants.Attributes.KillY, killY)
	folder:SetAttribute(Constants.Attributes.CourseReady, true)
	readyEvent:Fire()
end

function CourseService.WaitUntilReady()
	local folder = CourseService.Folder
	if not (folder and folder:GetAttribute(Constants.Attributes.CourseReady)) then
		readyEvent.Event:Wait()
	end
end

function CourseService.GetKillY(): number
	return CourseService.Folder:GetAttribute(Constants.Attributes.KillY)
end

function CourseService.IsCourse(id: any): boolean
	return type(id) == "string" and CourseService.Courses[id] ~= nil
end

-- Spread players across the start area so they don't stack on one point.
function CourseService.GetSpawnCFrame(slot: number?, courseId: string?): CFrame
	local entry = CourseService.Courses[courseId or Courses.Default] or CourseService.Courses[Courses.Default]
	local heightfield = entry.Heightfield
	local start = heightfield.Course.Start
	local index = (slot or 0) % (SPAWN_COLUMNS * 2)
	local column = index % SPAWN_COLUMNS - (SPAWN_COLUMNS - 1) / 2
	local row = math.floor(index / SPAWN_COLUMNS)

	local z = start.Z - row * SPAWN_SPACING
	local x = heightfield:CenterX(z) + column * SPAWN_SPACING
	return heightfield:GetUprightCFrame(x, z, SPAWN_HEIGHT)
end

return CourseService
