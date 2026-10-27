--[[
	TerrainBuilder
	Writes the heightfield into smooth Terrain with WriteVoxels, in 64x64-stud column chunks so
	each write only spans the height range it needs. Occupancy is the fraction of each voxel
	below the surface, which gives a smooth surface instead of 4-stud steps.

	Materials come from slope and position: groomed snow (Salt, with the corduroy variant) on
	the piste blending into powder Snow at its edges, Snow on gentle ground,
	patchy Snow/Rock on steeper ground, Rock and Slate cliffs on the steepest faces, and a
	frozen Glacier lake on the valley floor. Boulders are terrain balls with snow caps, so they
	blend into the slope with no hard part edges.
]]

local Workspace = game:GetService("Workspace")

local RESOLUTION = 4
local CHUNK_COLUMNS = 16
local SHELL_DEPTH = 16
local YIELD_BUDGET = 0.03 -- seconds of work between yields

local MATERIAL_COLORS = {
	[Enum.Material.Snow] = Color3.fromRGB(228, 236, 248), -- powder (EnvironmentConfig.TerrainColors)
	[Enum.Material.Salt] = Color3.fromRGB(234, 240, 249), -- groomed: smooth, bright
	[Enum.Material.Limestone] = Color3.fromRGB(232, 239, 249), -- wind-packed band
	[Enum.Material.Rock] = Color3.fromRGB(150, 140, 134),
	[Enum.Material.Slate] = Color3.fromRGB(128, 124, 128),
	[Enum.Material.Glacier] = Color3.fromRGB(168, 205, 230),
}

local TerrainBuilder = {}

local function alignDown(value: number): number
	return math.floor(value / RESOLUTION) * RESOLUTION
end

local function alignUp(value: number): number
	return math.ceil(value / RESOLUTION) * RESOLUTION
end

local lastYield = 0
local function maybeYield()
	if os.clock() - lastYield > YIELD_BUDGET then
		task.wait()
		lastYield = os.clock()
	end
end

-- Surface material for one column. Courses with their own rule (freeride maps) supply
-- heightfield:ChooseMaterial.
local function chooseMaterial(heightfield, x: number, z: number, height: number, slope: number)
	if heightfield.ChooseMaterial then
		return heightfield:ChooseMaterial(x, z, height, slope)
	end
	local world = heightfield.World
	local materials = world.Materials

	-- Groomed racing line with a ragged, noisy edge (two noise scales) that blends into powder
	local surfaces = world.Surfaces
	local signed = math.abs(heightfield:Offset(x, z)) - world.Piste.HalfWidth
	if signed < surfaces.BlendWidth + surfaces.PackedWidth * 1.6 then
		local ragged = math.noise(x / surfaces.BlendNoiseScale, z / surfaces.BlendNoiseScale, heightfield.Seed + 200) * 0.7
			+ math.noise(x / surfaces.FineNoiseScale, z / surfaces.FineNoiseScale, heightfield.Seed + 210) * 0.3
		if signed + ragged * surfaces.BlendWidth < 0 then
			return surfaces.Groomed
		end
		-- Wind-packed band between the groomed line and the powder, with its own ragged edge
		local band = surfaces.PackedWidth * (1 + 0.6 * math.noise(x / 31, z / 31, heightfield.Seed + 220))
			+ math.noise(x / surfaces.FineNoiseScale, z / surfaces.FineNoiseScale, heightfield.Seed + 230) * 4
		if signed < band and slope < materials.EdgeRockSlope then
			return surfaces.Packed
		end
	end
	local beyond = math.max(signed, 0)
	if beyond <= 0 then
		return Enum.Material.Snow
	end
	-- Snow holds on the banks right beside the piste; bare rock only on genuinely sheer drops
	if beyond < materials.SnowyEdge and slope < materials.EdgeRockSlope then
		return Enum.Material.Snow
	end
	if heightfield:IsLake(x, z, height) then
		return Enum.Material.Glacier
	end

	local rockiness = (slope - materials.MixedSlope) / (materials.RockSlope - materials.MixedSlope)
	if rockiness <= 0 then
		return Enum.Material.Snow
	end
	-- Patchy transition so snow lingers on ledges between rock bands
	local patch = math.noise(x / 22, z / 22, heightfield.Seed + 90) * 0.9
	if rockiness + patch < 0.5 then
		return Enum.Material.Snow
	end
	local variety = math.noise(x / 160, z / 160, heightfield.Seed + 120)
	return if variety > 0.1 then Enum.Material.Slate else Enum.Material.Rock
end

local function writeChunk(terrain: Terrain, heightfield, origin: Vector3, x0: number, z0: number, nx: number, nz: number)
	local valley = heightfield.World.ValleySide
	local lakeFloor = origin.Y + (if valley then valley.FloorY else -math.huge)

	-- Column heights with a 1-column border for slope estimation. The border also counts toward
	-- minH: each column must stay solid down past its neighbours' surfaces, or steep ground
	-- leaves gaps between chunks that look like floating slabs and pillars.
	local heights = table.create(nx + 2)
	local minH, maxH = math.huge, -math.huge
	for ix = 0, nx + 1 do
		local column = {}
		local lx = x0 + (ix - 0.5) * RESOLUTION - origin.X
		for iz = 0, nz + 1 do
			local lz = z0 + (iz - 0.5) * RESOLUTION - origin.Z
			local h = origin.Y + heightfield:GetHeight(lx, lz)
			column[iz] = h
			minH = math.min(minH, h)
			if ix >= 1 and ix <= nx and iz >= 1 and iz <= nz then
				maxH = math.max(maxH, h)
			end
		end
		heights[ix] = column
	end

	-- Surface material per column (lakes are flattened to the lake level)
	local surface = table.create(nx)
	for ix = 1, nx do
		local column = heights[ix]
		local row = table.create(nz)
		local lx = x0 + (ix - 0.5) * RESOLUTION - origin.X
		for iz = 1, nz do
			local lz = z0 + (iz - 0.5) * RESOLUTION - origin.Z
			local slopeX = (heights[ix + 1][iz] - heights[ix - 1][iz]) / (2 * RESOLUTION)
			local slopeZ = (column[iz + 1] - column[iz - 1]) / (2 * RESOLUTION)
			local slope = math.sqrt(slopeX * slopeX + slopeZ * slopeZ)
			local material = chooseMaterial(heightfield, lx, lz, column[iz] - origin.Y, slope)
			if material == Enum.Material.Glacier and valley then
				-- Frostpeak's lake is flattened here (freeride lakes are flat in the heightfield)
				column[iz] = math.min(column[iz], lakeFloor + 1)
			end
			row[iz] = material
		end
		surface[ix] = row
	end

	local y0 = alignDown(minH - SHELL_DEPTH)
	local y1 = alignUp(maxH + RESOLUTION)
	local ny = (y1 - y0) / RESOLUTION
	local air = Enum.Material.Air

	local materials = table.create(nx)
	local occupancies = table.create(nx)
	for ix = 1, nx do
		local matX = table.create(ny)
		local occX = table.create(ny)
		local column = heights[ix]
		local surfaceRow = surface[ix]
		for iy = 1, ny do
			local matY = table.create(nz)
			local occY = table.create(nz)
			local voxelBottom = y0 + (iy - 1) * RESOLUTION
			for iz = 1, nz do
				local occupancy = math.clamp((column[iz] - voxelBottom) / RESOLUTION, 0, 1)
				if occupancy <= 0 then
					matY[iz] = air
					occY[iz] = 0
				else
					matY[iz] = surfaceRow[iz]
					occY[iz] = occupancy
				end
			end
			matX[iy] = matY
			occX[iy] = occY
		end
		materials[ix] = matX
		occupancies[ix] = occX
	end

	local region = Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x0 + nx * RESOLUTION, y1, z0 + nz * RESOLUTION))
	terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)
end

local function placeBoulder(terrain: Terrain, center: Vector3, radius: number)
	terrain:FillBall(center, radius, Enum.Material.Rock)
	-- Snow cap: a flatter, offset ball covering the top of the rock
	terrain:FillBall(center + Vector3.new(0, radius * 0.55, 0), radius * 0.72, Enum.Material.Snow)
end

local function buildBoulders(terrain: Terrain, heightfield)
	local course = heightfield.Course
	local world = heightfield.World
	if not (course.Rocks and world.Boulders) then
		return
	end
	local origin = course.Origin
	local random = Random.new(course.Seed + 7)

	-- Gameplay obstacles on the piste
	for _, rock in course.Rocks do
		local x = heightfield:CenterX(rock.Z) + rock.OffsetX
		local radius = rock.Size / 2 + 1
		placeBoulder(terrain, origin + Vector3.new(x, heightfield:GetHeight(x, rock.Z) + radius * 0.3, rock.Z), radius)
	end

	-- Scenery boulders scattered beside the piste and on the mountainside
	local settings = world.Boulders
	local placed = 0
	local attempts = 0
	while placed < settings.Count and attempts < settings.Count * 20 do
		attempts += 1
		local z = random:NextNumber(-100, heightfield.Length + 150)
		local side = if random:NextNumber() < 0.65 then -1 else 1
		local gap = random:NextNumber(8, 260)
		local x = heightfield:CenterX(z) + side * (world.Piste.HalfWidth + gap)
		if heightfield:GetSlope(x, z) < 0.9 then
			local radius = random:NextNumber(settings.MinRadius, settings.MaxRadius)
			placeBoulder(terrain, origin + Vector3.new(x, heightfield:GetHeight(x, z) + radius * 0.2, z), radius)
			placed += 1
			maybeYield()
		end
	end
end

-- Empties this course's area (used before rebuilding it, so nothing stale is left floating).
-- Only touches the course's own bounds: other courses sharing the Terrain are untouched.
function TerrainBuilder.ClearArea(heightfield)
	local terrain = Workspace.Terrain
	local origin = heightfield.Course.Origin
	local minX, maxX, minZ, maxZ = (heightfield.GetTerrainBounds or heightfield.GetBounds)(heightfield)
	-- From below the lowest ground to well above the highest (mountain ranges included)
	local y0 = alignDown(origin.Y + heightfield.MinY - 64)
	local y1 = alignUp(origin.Y + heightfield.Course.StartY + 2600)
	local step = 256
	for x = alignDown(origin.X + minX), alignUp(origin.X + maxX) - 1, step do
		for z = alignDown(origin.Z + minZ), alignUp(origin.Z + maxZ) - 1, step do
			local region = Region3.new(Vector3.new(x, y0, z), Vector3.new(x + step, y1, z + step))
			terrain:FillRegion(region:ExpandToGrid(RESOLUTION), RESOLUTION, Enum.Material.Air)
			maybeYield()
		end
	end
end

function TerrainBuilder.Build(heightfield)
	local terrain = Workspace.Terrain
	local origin = heightfield.Course.Origin
	lastYield = os.clock()

	for material, color in MATERIAL_COLORS do
		terrain:SetMaterialColor(material, color)
	end

	local minX, maxX, minZ, maxZ = (heightfield.GetTerrainBounds or heightfield.GetBounds)(heightfield)
	local x0 = alignDown(origin.X + minX)
	local x1 = alignUp(origin.X + maxX)
	local z0 = alignDown(origin.Z + minZ)
	local z1 = alignUp(origin.Z + maxZ)
	local columnsX = (x1 - x0) / RESOLUTION
	local columnsZ = (z1 - z0) / RESOLUTION

	for cz = 0, columnsZ - 1, CHUNK_COLUMNS do
		for cx = 0, columnsX - 1, CHUNK_COLUMNS do
			local nx = math.min(CHUNK_COLUMNS, columnsX - cx)
			local nz = math.min(CHUNK_COLUMNS, columnsZ - cz)
			writeChunk(terrain, heightfield, origin, x0 + cx * RESOLUTION, z0 + cz * RESOLUTION, nx, nz)
			maybeYield()
		end
	end

	buildBoulders(terrain, heightfield)
end

return TerrainBuilder
