--[[
	BackdropBuilder
	Horizon peaks beyond the generated terrain. Real terrain mountain ranges surround the
	course (see Heightfield:Ranges); these faceted pyramids only fill the far horizon, where the
	atmosphere fades them to pale snowy silhouettes. They are decoration only (no collision,
	queries or shadows) and live in a Persistent model so clients always have them.
]]

local MAX_PART_SIZE = 2000

local Pyramid = require(script.Parent.Pyramid)

local ROCK = {
	Color = Color3.fromRGB(150, 160, 178),
	Material = Enum.Material.Slate,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}
local SNOW = {
	Color = Color3.fromRGB(244, 248, 254),
	Material = Enum.Material.Snow,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}

local BackdropBuilder = {}

local function buildPeak(parent: Instance, random: Random, baseCenter: Vector3, height: number)
	height = math.min(height, MAX_PART_SIZE)
	local extents = table.create(4)
	for i = 1, 4 do
		extents[i] = math.min(height * random:NextNumber(0.9, 1.6), MAX_PART_SIZE)
	end
	local yaw = random:NextNumber(0, math.pi * 2)
	local apex = baseCenter + Vector3.new(0, height, 0)

	local peak = Instance.new("Model")
	peak.Name = "Peak"
	Pyramid.Build(peak, apex, height, extents, yaw, ROCK)
	-- Large snow cap so only the lower flanks show rock
	Pyramid.BuildCap(peak, apex, height, extents, yaw, random:NextNumber(0.6, 0.8), 2 + height * 0.004, SNOW)
	peak.Parent = parent
end

-- Nearest distance from a point to the terrain rectangle (0 inside).
local function distanceToRect(x: number, z: number, minX: number, maxX: number, minZ: number, maxZ: number): number
	local dx = math.max(minX - x, 0, x - maxX)
	local dz = math.max(minZ - z, 0, z - maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

function BackdropBuilder.Build(heightfield, courseFolder: Instance)
	local course = heightfield.Course
	local settings = course.World.Backdrop
	local origin = course.Origin
	local random = Random.new(course.Seed + 21)
	local baseY = origin.Y + course.World.ValleySide.FloorY - 150

	local model = Instance.new("Model")
	model.Name = "Backdrop"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local minX, maxX, minZ, maxZ = heightfield:GetBounds()
	local centerX, centerZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local halfDiagonal = math.sqrt((maxX - minX) ^ 2 + (maxZ - minZ) ^ 2) / 2

	local placed, attempts = 0, 0
	while placed < settings.Peaks and attempts < settings.Peaks * 30 do
		attempts += 1
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = halfDiagonal * 0.6 + random:NextNumber(settings.Radius[1], settings.Radius[2])
		local x = centerX + math.cos(angle) * radius
		local z = centerZ + math.sin(angle) * radius
		local clearance = distanceToRect(x, z, minX, maxX, minZ, maxZ)
		if clearance > settings.Radius[1] * 0.6 then
			-- Taller further out, so ranges layer up toward the horizon
			local height = 900 + math.min(clearance / settings.Radius[2], 1) * 1000 + random:NextNumber(-150, 150)
			buildPeak(model, random, Vector3.new(origin.X + x, baseY, origin.Z + z), height)
			placed += 1
		end
	end

	model.Parent = courseFolder
end

return BackdropBuilder
