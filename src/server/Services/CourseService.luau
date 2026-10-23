--[[
	CourseService
	Builds the active course at server start and answers spawn/bounds questions about it.
	Clients read the Course folder's attributes (KillY, CourseReady) rather than course config.

	Terrain is the slow part (several seconds), so it can be baked into the place file:
	Terrain carries a "CourseTerrain" attribute ("<course id>:<TerrainVersion>"), and when it
	matches the config the terrain is reused instead of regenerated. Run CourseService.Init()
	in edit mode (see docs/VISUALS.md) and save the place to bake it. Props, forest and
	backdrop are always rebuilt at runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local Course = script.Parent.Parent.Course
local Heightfield = require(Course.Heightfield)
local TerrainBuilder = require(Course.TerrainBuilder)
local PropBuilder = require(Course.PropBuilder)
local ForestBuilder = require(Course.ForestBuilder)
local BackdropBuilder = require(Course.BackdropBuilder)
local Environment = require(Course.Environment)

local SPAWN_HEIGHT = 5
local SPAWN_COLUMNS = 5
local SPAWN_SPACING = 6

local CourseService = {}
CourseService.Heightfield = nil
CourseService.Folder = nil

local readyEvent = Instance.new("BindableEvent")

local TERRAIN_ATTRIBUTE = "CourseTerrain"

-- Regenerates terrain only when the baked version doesn't match the config.
local function ensureTerrain(definition, heightfield): boolean
	local terrain = Workspace.Terrain
	local version = `{definition.Id}:{definition.World.TerrainVersion}`
	local baked = terrain:GetAttribute(TERRAIN_ATTRIBUTE)
	if baked == version then
		return false
	end
	if baked ~= nil then
		-- Our own older terrain: clear it so nothing stale is left floating above the new surface.
		terrain:Clear()
	end
	TerrainBuilder.Build(heightfield)
	terrain:SetAttribute(TERRAIN_ATTRIBUTE, version)
	return true
end

function CourseService.Init()
	local definition = Courses.List[Courses.Default]
	assert(definition, `Unknown default course {Courses.Default}`)

	local started = os.clock()
	local heightfield = Heightfield.new(definition)
	CourseService.Heightfield = heightfield

	local existing = Workspace:FindFirstChild(Constants.CourseFolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Create("Folder", { Name = Constants.CourseFolderName })
	folder:SetAttribute("CourseId", definition.Id)
	folder:SetAttribute(Constants.Attributes.KillY, definition.Origin.Y + heightfield.MinY - definition.KillDepth)
	folder.Parent = Workspace
	CourseService.Folder = folder

	Environment.Apply()
	local generated = ensureTerrain(definition, heightfield)
	local terrainTime = os.clock() - started
	PropBuilder.Build(heightfield, folder)
	local trees = ForestBuilder.Build(heightfield, folder)
	BackdropBuilder.Build(heightfield, folder)

	folder:SetAttribute(Constants.Attributes.CourseReady, true)
	readyEvent:Fire()
	print(string.format(
		"[CourseService] Built %s in %.2fs (terrain %s %.2fs, %d trees)",
		definition.DisplayName,
		os.clock() - started,
		if generated then "generated" else "baked",
		terrainTime,
		trees
	))
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

-- Spread players across the start pad so they don't stack on one point.
function CourseService.GetSpawnCFrame(slot: number?): CFrame
	local heightfield = CourseService.Heightfield
	local start = heightfield.Course.Start
	local index = (slot or 0) % (SPAWN_COLUMNS * 2)
	local column = index % SPAWN_COLUMNS - (SPAWN_COLUMNS - 1) / 2
	local row = math.floor(index / SPAWN_COLUMNS)

	local z = start.Z - row * SPAWN_SPACING
	local x = heightfield:CenterX(z) + column * SPAWN_SPACING
	return heightfield:GetUprightCFrame(x, z, SPAWN_HEIGHT)
end

return CourseService
