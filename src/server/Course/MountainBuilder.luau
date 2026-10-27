--[[
	MountainBuilder
	Scenery for freeride mountains (World.Scenery in the course config), placed from the
	heightfield so it sits on the generated terrain:
	  - pine forests: stylised low-poly pines in four variants (tall, short and wide, heavily
	    snow-laden, sparse ridge pines), dense sections to thread through, open fast lanes
	  - angular rock formations: clusters along the ridgelines, cliff columns along the
	    boundary walls, a narrow rock passage, outcrops and a rock drop
	  - a cave tunnel over the centre route, a frozen waterfall with a frozen pool
	  - checkpoint beams, the start gate and the finish arch
	  - distant low-poly peaks all around, for scale (the atmosphere hazes them)

	Style: deliberately blocky. Rocks are rotated blocks with snow slabs on their tops; trees
	are stacked faceted tiers with snow layers. Each tree variant is built once as a single
	union (GeometryService) and cloned, so a tree is one part and identical trees share one
	mesh. If unions aren't available the imported spruce templates are used instead.

	Gameplay: rocks, cliffs and cave walls collide (obstacles); trees near the routes get one
	invisible trunk collider (the visual tree never collides); everything else is visual.
	Placement is seeded, so every server builds the same mountain.
]]

local GeometryService = game:GetService("GeometryService")
local ServerStorage = game:GetService("ServerStorage")

local YIELD_BUDGET = 0.03

local MountainBuilder = {}

-- Palette
-- Warm brown-greys (reference cliffs); light enough to read in shadow
local ROCK_COLORS = { Color3.fromRGB(156, 138, 120), Color3.fromRGB(140, 126, 112), Color3.fromRGB(168, 152, 132) }
local SLATE_COLOR = Color3.fromRGB(118, 112, 112)
local SNOW_COLOR = Color3.fromRGB(242, 247, 255)
local NEEDLE_COLORS = { Color3.fromRGB(26, 62, 44), Color3.fromRGB(34, 76, 52) }
local TRUNK_COLOR = Color3.fromRGB(86, 60, 44)
local ICE_COLOR = Color3.fromRGB(176, 220, 244)
local BEAM_COLOR = Color3.fromRGB(255, 122, 40)

local lastYield = 0
local function maybeYield()
	if os.clock() - lastYield > YIELD_BUDGET then
		task.wait()
		lastYield = os.clock()
	end
end

local function part(properties, className: string?)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in properties do
		(p :: any)[key] = value
	end
	return p
end

----------------------------------------------------------------------------------------------
-- Trees
----------------------------------------------------------------------------------------------

local QUADRANTS = { CFrame.Angles(0, 0, 0), CFrame.Angles(0, math.pi / 2, 0), CFrame.Angles(0, math.pi, 0), CFrame.Angles(0, math.pi * 3 / 2, 0) }

-- Four corner wedges sharing an apex (frame = apex position and orientation): a square
-- pyramid hanging below the apex
local function pyramid(parts, frame: CFrame, height: number, extent: number, color: Color3, material: Enum.Material)
	for _, quadrant in QUADRANTS do
		table.insert(parts, part({
			Size = Vector3.new(extent, height, extent),
			CFrame = frame * quadrant * CFrame.new(-extent / 2, -height / 2, extent / 2),
			Color = color,
			Material = material,
		}, "CornerWedgePart"))
	end
end

-- Tree shapes for a unit-height tree. Tiers: { base, height, half-width }, bottom to top;
-- Cover: share of each tier the snow layers cover; Trunk: trunk width.
local TREE_VARIANTS = {
	Tall = {
		Tiers = {
			{ 0.12, 0.3, 0.42 },
			{ 0.26, 0.28, 0.37 },
			{ 0.4, 0.26, 0.31 },
			{ 0.53, 0.24, 0.25 },
			{ 0.66, 0.22, 0.19 },
			{ 0.78, 0.22, 0.12 },
		},
		Cover = 0.88,
		Trunk = 0.07,
	},
	Wide = {
		Tiers = { { 0.08, 0.36, 0.62 }, { 0.28, 0.33, 0.5 }, { 0.47, 0.3, 0.38 }, { 0.64, 0.36, 0.24 } },
		Cover = 0.9,
		Trunk = 0.09,
	},
	Heavy = {
		Tiers = { { 0.1, 0.34, 0.48 }, { 0.3, 0.32, 0.4 }, { 0.48, 0.3, 0.3 }, { 0.65, 0.35, 0.2 } },
		Cover = 0.99,
		Trunk = 0.08,
	},
	Sparse = {
		Tiers = { { 0.3, 0.26, 0.26 }, { 0.5, 0.24, 0.2 }, { 0.7, 0.3, 0.13 } },
		Cover = 0.8,
		Trunk = 0.05,
	},
}

-- Builds one variant as a single union (unit height, base at y = 0). Each tier is two
-- needle pyramids 45° apart (an eight-pointed skirt), tilted a few degrees so the silhouette
-- is irregular, with two snow layers resting on it at the angles in between, so dark green
-- tips show around blankets of snow.
local function buildTreeUnion(name: string, shape): BasePart?
	local random = Random.new(#name * 97 + #shape.Tiers)
	local parts = {}
	table.insert(parts, part({
		Size = Vector3.new(shape.Trunk, 0.24, shape.Trunk),
		CFrame = CFrame.new(0, 0.12, 0),
		Color = TRUNK_COLOR,
		Material = Enum.Material.Wood,
	}))
	for i, tier in shape.Tiers do
		local yaw = i * 0.37
		local tilt = CFrame.Angles(random:NextNumber(-0.09, 0.09), 0, random:NextNumber(-0.09, 0.09))
		local apex = CFrame.new(random:NextNumber(-0.01, 0.01), tier[1] + tier[2], random:NextNumber(-0.01, 0.01)) * tilt
		pyramid(parts, apex * CFrame.Angles(0, yaw, 0), tier[2], tier[3], NEEDLE_COLORS[i % 2 + 1], Enum.Material.SmoothPlastic)
		pyramid(parts, apex * CFrame.Angles(0, yaw + math.pi / 4, 0), tier[2], tier[3], NEEDLE_COLORS[(i + 1) % 2 + 1], Enum.Material.SmoothPlastic)
		local lift = CFrame.new(0, tier[2] * 0.07, 0)
		for k, offset in { math.pi / 8, math.pi * 3 / 8 } do
			local cover = shape.Cover * (if k == 1 then 0.97 else 0.88)
			pyramid(parts, apex * lift * CFrame.Angles(0, yaw + offset, 0), tier[2] * cover, tier[3] * cover, SNOW_COLOR, Enum.Material.Snow)
		end
	end
	local first = table.remove(parts, 1)
	local ok, result = pcall(function()
		return GeometryService:UnionAsync(first, parts, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
			SplitApart = false,
		})
	end)
	first:Destroy()
	for _, p in parts do
		p:Destroy()
	end
	if not ok or not result or not result[1] then
		warn("[MountainBuilder] tree union failed:", result)
		return nil
	end
	local union = result[1]
	union.UsePartColor = false
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	return union
end

-- Templates: { [variant] = { Part, Height } } (unit-height unions), or the imported spruce
local function treeTemplates()
	local templates = {}
	for name, shape in TREE_VARIANTS do
		local union = buildTreeUnion(name, shape)
		if union then
			templates[name] = union
		end
	end
	if next(templates) then
		return templates, nil
	end
	local assets = ServerStorage:FindFirstChild("Assets")
	local spruce = assets and assets:FindFirstChild("Trees") and assets.Trees:FindFirstChild("SpruceTall")
	return nil, spruce
end

----------------------------------------------------------------------------------------------
-- Rocks
----------------------------------------------------------------------------------------------

-- A block with a snow slab on its top face (follows the block's tilt)
local function rockBlock(folder: Instance, cframe: CFrame, size: Vector3, color: Color3, collide: boolean, capCollide: boolean?)
	part({
		Name = "Rock",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = if color == SLATE_COLOR then Enum.Material.Slate else Enum.Material.Rock,
		CanCollide = collide,
		CanQuery = collide,
		CanTouch = false,
		Parent = folder,
	})
	local thickness = math.clamp(size.Y * 0.06, 0.6, 2.4)
	part({
		Name = "Snow",
		Size = Vector3.new(size.X * 1.03, thickness, size.Z * 1.03),
		CFrame = cframe * CFrame.new(0, size.Y / 2 + thickness / 2 - 0.15, 0),
		Color = SNOW_COLOR,
		Material = Enum.Material.Snow,
		CanCollide = capCollide == true,
		CanQuery = capCollide == true,
		CanTouch = false,
		Parent = folder,
	})
end

-- A cluster of tilted angular blocks around a ground point. Returns its footprint radius.
local function rockCluster(ctx, folder: Instance, x: number, z: number, size: number, options)
	options = options or {}
	local random = ctx.Random
	local count = options.Count or random:NextInteger(3, 6)
	local collide = options.Collide ~= false
	for _ = 1, count do
		local w = size * random:NextNumber(0.45, 0.95)
		local h = size * random:NextNumber(options.MinHeight or 0.5, options.MaxHeight or 1.3)
		local d = size * random:NextNumber(0.45, 0.95)
		local ox = random:NextNumber(-0.55, 0.55) * size
		local oz = random:NextNumber(-0.55, 0.55) * size
		local px, pz = x + ox, z + oz
		local ground = ctx.Height(px, pz)
		local tilt = math.rad(options.Tilt or 12)
		local cframe = CFrame.new(ctx.Origin + Vector3.new(px, ground + h * 0.5 - h * 0.3, pz))
			* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
			* CFrame.Angles(random:NextNumber(-tilt, tilt), 0, random:NextNumber(-tilt, tilt))
		local color = if random:NextNumber() < 0.25 then SLATE_COLOR else ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)]
		rockBlock(folder, cframe, Vector3.new(w, h, d), color, collide)
	end
	table.insert(ctx.Footprints, { X = x, Z = z, R = size * 1.1 })
	maybeYield()
end

-- Columnar cliff along a boundary wall: tall thin prisms side by side, stepped heights
local function cliffColumns(ctx, folder: Instance, x: number, z: number, side: number)
	local random = ctx.Random
	local count = random:NextInteger(2, 4)
	local baseHeight = random:NextNumber(26, 70)
	for i = 1, count do
		local w = random:NextNumber(9, 16)
		local h = baseHeight * random:NextNumber(0.6, 1.15)
		local pz = z + (i - (count + 1) / 2) * w * 0.9
		local px = x + side * random:NextNumber(-6, 10)
		local ground = ctx.Height(px, pz)
		local cframe = CFrame.new(ctx.Origin + Vector3.new(px, ground + h / 2 - h * 0.18, pz))
			* CFrame.Angles(0, random:NextNumber(-0.25, 0.25), 0)
			* CFrame.Angles(random:NextNumber(-0.05, 0.05), 0, side * random:NextNumber(0, 0.12))
		rockBlock(folder, cframe, Vector3.new(w, h, w * random:NextNumber(0.8, 1.2)), ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], true)
	end
	maybeYield()
end

local function buildRocks(ctx)
	local hf = ctx.HF
	local settings = ctx.Scenery.Rocks
	local corridors = hf.World.Corridors
	local folder = Instance.new("Folder")
	folder.Name = "Rocks"
	folder.Parent = ctx.Folder
	local random = ctx.Random

	-- Ridgelines between the corridors
	for z = corridors.StartZ + 150, corridors.EndZ - 150, settings.RidgeSpacing do
		for i = 1, 2 do
			local pz = z + random:NextNumber(-60, 60)
			local mid = (hf:CorridorCenter(i, pz) + hf:CorridorCenter(i + 1, pz)) / 2
			if random:NextNumber() < 0.8 then
				rockCluster(ctx, folder, mid + random:NextNumber(-40, 40), pz, random:NextNumber(10, 22))
			end
		end
	end

	-- Rock formations lining the routes (beside the lanes, never in them or near jumps)
	local function nearKicker(x: number, z: number): boolean
		for _, kicker in hf.Kickers do
			if math.abs(x - kicker.X) < kicker.Width / 2 + 40 and z > kicker.Z - kicker.Length - 60 and z < kicker.Z + 180 then
				return true
			end
		end
		return false
	end
	for z = corridors.StartZ + 120, corridors.EndZ - 120, settings.RouteSpacing do
		for i = 1, 3 do
			for _, side in { -1, 1 } do
				if random:NextNumber() < settings.RouteChance then
					local pz = z + random:NextNumber(-80, 80)
					local x = hf:CorridorCenter(i, pz) + side * random:NextNumber(settings.RouteOffset[1], settings.RouteOffset[2])
					if not nearKicker(x, pz) and math.abs(x) < hf.World.Walls.StartX - 40 then
						rockCluster(ctx, folder, x, pz, random:NextNumber(16, 32), { MinHeight = 0.8, MaxHeight = 1.7, Tilt = 8 })
					end
				end
			end
		end
	end

	-- Cliff columns along both boundary walls
	local _, _, minZ, maxZ = hf:GetBounds()
	for z = minZ + 60, maxZ - 60, settings.WallSpacing do
		for _, side in { -1, 1 } do
			if random:NextNumber() < 0.85 then
				cliffColumns(ctx, folder, side * (settings.WallX + random:NextNumber(0, 40)), z + random:NextNumber(-20, 20), side)
			end
		end
	end

	-- Narrow passage across a corridor: two walls of rock with a gap at the corridor centre
	local passage = settings.Passage
	if passage then
		local center = hf:CorridorCenter(passage.Corridor, passage.Z)
		for _, side in { -1, 1 } do
			for dz = -passage.Depth / 2, passage.Depth / 2, 14 do
				local pz = passage.Z + dz
				local edge = hf:CorridorCenter(passage.Corridor, pz) + side * passage.Gap / 2
				local w = random:NextNumber(18, 30)
				local h = random:NextNumber(28, 48)
				local px = edge + side * w / 2
				local ground = hf:GetHeight(px, pz)
				local cframe = CFrame.new(ctx.Origin + Vector3.new(px, ground + h / 2 - 4, pz)) * CFrame.Angles(0, random:NextNumber(-0.2, 0.2), 0)
				rockBlock(folder, cframe, Vector3.new(w, h, random:NextNumber(14, 20)), ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], true)
				-- Rubble behind
				rockCluster(ctx, folder, px + side * random:NextNumber(14, 30), pz, random:NextNumber(14, 24), { Count = 2 })
			end
		end
		table.insert(ctx.Clear, { X = center, Z = passage.Z, R = passage.Depth })
	end

	-- Outcrops, and snow-covered rock drops riders can ride over
	for _, outcrop in settings.Outcrops or {} do
		local x = hf:FeatureX(outcrop)
		if outcrop.Drop then
			-- A flat-topped ledge: its snowy top is rideable, its downhill face is a drop
			local w, d, h = outcrop.Size * 2.2, outcrop.Size, outcrop.Size * 0.7
			local uphill = hf:GetHeight(x, outcrop.Z - d / 2)
			local downhill = hf:GetHeight(x, outcrop.Z + d / 2)
			local top = math.max(uphill + 0.5, downhill + h * 0.55)
			local slope = math.atan2(uphill - downhill, d) * 0.5
			local cframe = CFrame.new(ctx.Origin + Vector3.new(x, top - h / 2, outcrop.Z)) * CFrame.Angles(slope, 0, 0)
			rockBlock(folder, cframe, Vector3.new(w, h, d), ROCK_COLORS[1], true, true)
			table.insert(ctx.Footprints, { X = x, Z = outcrop.Z, R = w * 0.7 })
		else
			rockCluster(ctx, folder, x, outcrop.Z, outcrop.Size)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Cave tunnel and frozen waterfall
----------------------------------------------------------------------------------------------

local function buildCave(ctx)
	local hf = ctx.HF
	local cave = ctx.Scenery.Cave
	if not cave then
		return
	end
	local random = ctx.Random
	local folder = Instance.new("Folder")
	folder.Name = "Cave"
	folder.Parent = ctx.Folder
	local step = 7
	-- Segments overlap generously so no light leaks between them
	local overlap = 5
	for z = cave.FromZ, cave.ToZ, step do
		local center = hf:CorridorCenter(cave.Corridor, z)
		local ground = hf:GetHeight(center, z)
		local half = cave.Width / 2
		local height = cave.Height + random:NextNumber(-2, 3)
		-- Walls
		for _, side in { -1, 1 } do
			local thickness = random:NextNumber(10, 16)
			local x = center + side * (half + thickness / 2)
			local cframe = CFrame.new(ctx.Origin + Vector3.new(x, ground + height / 2 - 3, z))
				* CFrame.Angles(0, random:NextNumber(-0.08, 0.08), side * random:NextNumber(0.02, 0.1))
			rockBlock(folder, cframe, Vector3.new(thickness, height + 8, step + overlap), ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], true)
			-- Jagged outside
			rockBlock(
				folder,
				CFrame.new(ctx.Origin + Vector3.new(x + side * thickness * 0.6, ground + height * 0.4, z)) * CFrame.Angles(random:NextNumber(-0.2, 0.2), random:NextNumber(0, 6), random:NextNumber(-0.2, 0.2)),
				Vector3.new(thickness, height * random:NextNumber(0.6, 0.9), step * 1.4),
				SLATE_COLOR,
				true
			)
		end
		-- Roof, with snow on top
		local roofThickness = random:NextNumber(9, 12)
		local roof = CFrame.new(ctx.Origin + Vector3.new(center, ground + height + roofThickness / 2 - 3, z))
			* CFrame.Angles(random:NextNumber(-0.03, 0.03), 0, random:NextNumber(-0.04, 0.04))
		rockBlock(folder, roof, Vector3.new(cave.Width + 36, roofThickness, step + overlap), ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], true)
		maybeYield()
	end
	-- Rocky mouths at both ends
	for _, z in { cave.FromZ - 6, cave.ToZ + 6 } do
		local center = hf:CorridorCenter(cave.Corridor, z)
		for _, side in { -1, 1 } do
			rockCluster(ctx, folder, center + side * (cave.Width / 2 + 16), z, 18, { Count = 3, MinHeight = 0.9, MaxHeight = 1.6 })
		end
	end
	table.insert(ctx.Clear, { X = hf:CorridorCenter(cave.Corridor, (cave.FromZ + cave.ToZ) / 2), Z = (cave.FromZ + cave.ToZ) / 2, R = (cave.ToZ - cave.FromZ) / 2 + 50 })
end

local function buildWaterfall(ctx)
	local hf = ctx.HF
	local fall = ctx.Scenery.Waterfall
	if not fall then
		return
	end
	local random = ctx.Random
	local folder = Instance.new("Folder")
	folder.Name = "Waterfall"
	folder.Parent = ctx.Folder
	local side = if fall.X >= 0 then 1 else -1
	local ground = hf:GetHeight(fall.X, fall.Z)
	local base = ctx.Origin + Vector3.new(fall.X, ground, fall.Z)

	-- Cliff behind: tall columns either side of the ice, and a face behind it
	for i = -3, 3 do
		local w = random:NextNumber(12, 18)
		local h = fall.Height * random:NextNumber(0.8, 1.15) * (if i == 0 then 1.05 else 1)
		local z = fall.Z + i * 14
		local x = fall.X + side * (12 + math.abs(i) * 2)
		local g = math.min(hf:GetHeight(x, z), ground)
		local cframe = CFrame.new(ctx.Origin + Vector3.new(x, g + h / 2 - 6, z)) * CFrame.Angles(0, random:NextNumber(-0.15, 0.15), 0)
		rockBlock(folder, cframe, Vector3.new(16, h, w), ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], true)
	end
	-- Frozen cascade: overlapping ice slabs down the face, wider at the bottom
	local steps = 9
	for i = 1, steps do
		local t = (i - 1) / (steps - 1)
		local y = fall.Height * (1 - t) + 2
		local width = fall.Width * (0.6 + 0.5 * t) * random:NextNumber(0.9, 1.1)
		local slab = part({
			Name = "Ice",
			Size = Vector3.new(3 + t * 3, fall.Height / steps + 4, width),
			CFrame = CFrame.new(base + Vector3.new(side * (4 - t * 6), y, random:NextNumber(-2, 2))) * CFrame.Angles(0, 0, side * math.rad(6 + t * 10)),
			Color = ICE_COLOR,
			Material = Enum.Material.Glacier,
			Transparency = 0.12,
			Reflectance = 0.05,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		})
		slab:SetAttribute("Waterfall", true)
		-- Icicles hanging off each slab
		for _ = 1, 3 do
			local length = random:NextNumber(4, 9)
			part({
				Name = "Icicle",
				Size = Vector3.new(1.2, length, 1.2),
				CFrame = CFrame.new(base + Vector3.new(side * (2 - t * 6), y - fall.Height / steps / 2 - length / 2, random:NextNumber(-width / 2, width / 2))) * CFrame.Angles(0, random:NextNumber(0, 3), math.pi),
				Color = ICE_COLOR,
				Material = Enum.Material.Glacier,
				Transparency = 0.15,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = folder,
			}, "WedgePart")
		end
	end
	-- Frozen pool at the foot, rimmed with snowy rocks; tilted to the slope so no edge floats
	local poolX = fall.X - side * 22
	local poolNormal = hf:GetNormal(poolX, fall.Z)
	part({
		Name = "Pool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 58, 58),
		CFrame = CFrame.new(ctx.Origin + Vector3.new(poolX, hf:GetHeight(poolX, fall.Z) - 0.6, fall.Z))
			* CFrame.fromRotationBetweenVectors(Vector3.xAxis, poolNormal),
		Color = ICE_COLOR,
		Material = Enum.Material.Ice,
		CanCollide = true,
		CanTouch = false,
		Parent = folder,
	})
	for a = 0, math.pi * 2, math.pi / 4 do
		rockCluster(ctx, folder, fall.X - side * 22 + math.cos(a) * 34, fall.Z + math.sin(a) * 34, random:NextNumber(5, 8), { Count = 2, MaxHeight = 0.8 })
	end
	table.insert(ctx.Clear, { X = fall.X - side * 20, Z = fall.Z, R = 60 })
end

----------------------------------------------------------------------------------------------
-- Race markers
----------------------------------------------------------------------------------------------

local function beam(folder: Instance, position: Vector3, height: number, color: Color3)
	part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 3.2, 3.2),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
	-- Glow ring on the snow
	part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 14, 14),
		CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
end

local function banner(folder: Instance, center: Vector3, span: number, text: string, color: Color3)
	-- Tall enough that the chase camera passes under it
	local height = 30
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(2.6, height, 2.6),
			CFrame = CFrame.new(center + Vector3.new(side * span / 2, height / 2 - 1, 0)),
			Color = Color3.fromRGB(40, 44, 54),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanTouch = false,
			Parent = folder,
		})
	end
	local board = part({
		Name = "Banner",
		Size = Vector3.new(span + 2.6, 6, 0.8),
		CFrame = CFrame.new(center + Vector3.new(0, height - 2, 0)),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanTouch = false,
		Parent = folder,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		gui.Parent = board
	end
end

local function buildMarkers(ctx)
	local hf = ctx.HF
	local race = hf.Course.Race
	if not race then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Checkpoints"
	folder.Parent = ctx.Folder
	for index, checkpoint in race.Checkpoints do
		local cp = Instance.new("Folder")
		cp.Name = "Checkpoint" .. index
		cp:SetAttribute("Index", index)
		cp.Parent = folder
		for _, position in hf:CheckpointBeams(checkpoint) do
			beam(cp, position, 240, BEAM_COLOR)
			table.insert(ctx.Clear, { X = position.X - ctx.Origin.X, Z = position.Z - ctx.Origin.Z, R = 28 })
		end
	end
	-- Kickers: a snow pole each side of the lip (orange tops), so jumps read from a
	-- distance; the trick park's are labelled with their size
	local origin = ctx.Origin
	for _, kicker in hf.Kickers do
		for _, side in { -1, 1 } do
			local x = kicker.X + side * (kicker.Width / 2 + 3)
			local ground = origin + Vector3.new(x, hf:GetHeight(x, kicker.Z), kicker.Z)
			part({
				Name = "LipPole",
				Size = Vector3.new(0.5, 7, 0.5),
				CFrame = CFrame.new(ground + Vector3.new(0, 3, 0)),
				Color = Color3.fromRGB(240, 240, 235),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Parent = folder,
			})
			part({
				Name = "LipFlag",
				Size = Vector3.new(0.55, 1.6, 0.55),
				CFrame = CFrame.new(ground + Vector3.new(0, 7, 0)),
				Color = BEAM_COLOR,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = folder,
			})
		end
		if kicker.Name and string.find(kicker.Name, "^Park") then
			local size = string.match(kicker.Name, "Park (%w+)")
			local signAt = origin + Vector3.new(kicker.X - kicker.Width / 2 - 8, hf:GetHeight(kicker.X - kicker.Width / 2 - 8, kicker.Z - kicker.Length), kicker.Z - kicker.Length)
			local board = part({
				Name = "Sign",
				Size = Vector3.new(6, 4, 0.5),
				CFrame = CFrame.new(signAt + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.pi, 0),
				Color = Color3.fromRGB(120, 80, 200),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Parent = folder,
			})
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.LightInfluence = 0
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Text = size
			text.TextScaled = true
			text.Font = Enum.Font.GothamBlack
			text.TextColor3 = Color3.new(1, 1, 1)
			text.Parent = gui
			gui.Parent = board
		end
	end
	local spots = hf.Course.Spots
	if spots and spots.TrickPark then
		local park = spots.TrickPark
		banner(folder, origin + Vector3.new(park.X, hf:GetHeight(park.X, park.Z + 40), park.Z + 40), 60, "TRICK PARK", Color3.fromRGB(120, 80, 200))
	end

	-- Start gate and finish arch
	banner(folder, origin + Vector3.new(0, hf:GetHeight(0, race.StartLineZ), race.StartLineZ), 90, "START", Color3.fromRGB(30, 140, 90))
	local finish = origin + Vector3.new(0, hf:GetHeight(0, race.FinishZ), race.FinishZ)
	banner(folder, finish, 120, "FINISH", Color3.fromRGB(210, 50, 50))
	beam(folder, finish + Vector3.new(-66, 0, 0), 260, Color3.fromRGB(255, 70, 70))
	beam(folder, finish + Vector3.new(66, 0, 0), 260, Color3.fromRGB(255, 70, 70))
end

----------------------------------------------------------------------------------------------
-- Forest
----------------------------------------------------------------------------------------------

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function buildForest(ctx)
	local hf = ctx.HF
	local settings = ctx.Scenery.Forest
	local course = hf.Course
	local random = Random.new(course.Seed + 23)
	local folder = Instance.new("Folder")
	folder.Name = "Forest"
	folder.Parent = ctx.Folder

	local templates, spruce = treeTemplates()
	local minX, maxX, minZ, maxZ = hf:GetBounds()
	local spacing = settings.Spacing
	local corridors = hf.World.Corridors
	local park = settings.ParkLane

	local function blocked(x: number, z: number): boolean
		-- Start and finish areas, the lake
		if math.sqrt(x * x + z * z) < 110 or math.sqrt(x * x + (z - course.Finish.Z) ^ 2) < 260 then
			return true
		end
		local lake = hf.Lake
		if lake then
			local dx, dz = (x - lake.X) / (lake.RadiusX * 1.25), (z - lake.Z) / (lake.RadiusZ * 1.25)
			if dx * dx + dz * dz < 1 then
				return true
			end
		end
		-- Trick park lane
		if park and math.abs(x - park.X) < park.HalfWidth and z > park.FromZ and z < park.ToZ then
			return true
		end
		-- Kicker run-ins and landings
		for _, kicker in hf.Kickers do
			if math.abs(x - kicker.X) < kicker.Width / 2 + 25 and z > kicker.Z - kicker.Length - 40 and z < kicker.Z + 160 then
				return true
			end
		end
		-- Fast lanes stay open
		local envelope = hf:CorridorEnvelope(z)
		if envelope > 0.2 then
			for _, lane in settings.ClearLanes do
				if math.abs(x - hf:CorridorCenter(lane.Corridor, z)) < lane.HalfWidth then
					return true
				end
			end
		end
		-- Rocks, beams, cave, waterfall
		for _, spot in ctx.Footprints do
			if (x - spot.X) ^ 2 + (z - spot.Z) ^ 2 < (spot.R + 4) ^ 2 then
				return true
			end
		end
		for _, spot in ctx.Clear do
			if (x - spot.X) ^ 2 + (z - spot.Z) ^ 2 < spot.R ^ 2 then
				return true
			end
		end
		return false
	end

	local count = 0
	for z = minZ + spacing / 2, maxZ, spacing do
		for x = minX + spacing / 2, maxX, spacing do
			local px = x + random:NextNumber(-0.45, 0.45) * spacing
			local pz = z + random:NextNumber(-0.45, 0.45) * spacing
			local roll = random:NextNumber()
			if blocked(px, pz) then
				continue
			end

			-- Density: natural stands, thinner in the open upper bowl, plus the dense sections
			local stand = math.noise(px / settings.StandScale, pz / settings.StandScale, course.Seed % 97 + 0.31)
			local density = settings.BaseDensity + settings.StandDensity * smoothstep(0.05, 0.35, stand)
			if pz < corridors.StartZ then
				density *= 0.45
			end
			local inSection = false
			for _, section in settings.Sections do
				if pz > section.FromZ and pz < section.ToZ then
					local d = math.abs(px - hf:CorridorCenter(section.Corridor, pz))
					if d < section.HalfWidth then
						density = math.max(density, section.Density * (1 - smoothstep(section.HalfWidth * 0.7, section.HalfWidth, d)))
						inSection = true
					end
				end
			end
			if roll >= density then
				continue
			end
			if hf:GetSlope(px, pz) > settings.MaxSlope then
				continue
			end

			-- Distance to the nearest route: trees near routes collide and cast shadows
			local nearest = math.huge
			for i = 1, 3 do
				nearest = math.min(nearest, math.abs(px - hf:CorridorCenter(i, pz)))
			end
			if pz < corridors.StartZ or pz > corridors.EndZ then
				nearest = math.min(nearest, math.abs(px))
			end
			local near = nearest < settings.ColliderDistance or inSection

			-- Variant: sparse pines high on the ridgelines, otherwise a mix
			local ground = ctx.Origin + Vector3.new(px, hf:GetHeight(px, pz), pz)
			local pick = random:NextNumber()
			local variant, height
			local onRidge = hf:CorridorEnvelope(pz) > 0.3 and nearest > 220
			if onRidge and pick < 0.5 then
				variant, height = "Sparse", random:NextNumber(12, 20)
			elseif pick < 0.45 then
				variant, height = "Tall", random:NextNumber(22, 38)
			elseif pick < 0.7 then
				variant, height = "Wide", random:NextNumber(13, 21)
			elseif pick < 0.92 then
				variant, height = "Heavy", random:NextNumber(17, 28)
			else
				variant, height = "Sparse", random:NextNumber(12, 20)
			end
			local yaw = random:NextNumber(0, math.pi * 2)
			local widthScale = random:NextNumber(0.85, 1.18)

			local tree
			if templates then
				local template = templates[variant] or templates.Tall
				tree = template:Clone()
				tree.Size = Vector3.new(template.Size.X * height * widthScale, template.Size.Y * height, template.Size.Z * height * widthScale)
				tree.CFrame = CFrame.new(ground + Vector3.new(0, tree.Size.Y / 2 - 0.8, 0)) * CFrame.Angles(0, yaw, 0)
				tree.CastShadow = near
				tree.Name = variant
			elseif spruce then
				tree = spruce:Clone()
				local _, size = tree:GetBoundingBox()
				tree:ScaleTo(tree:GetScale() * height / size.Y)
				local box, scaled = tree:GetBoundingBox()
				tree:PivotTo(tree:GetPivot() + (ground - (box.Position - Vector3.new(0, scaled.Y / 2, 0))) - Vector3.new(0, 0.6, 0))
				for _, p in tree:GetDescendants() do
					if p:IsA("BasePart") then
						p.Anchored = true
						p.CanCollide = false
						p.CanQuery = false
						p.CanTouch = false
						p.CastShadow = near
					end
				end
			else
				continue
			end
			tree.Parent = folder

			if near then
				-- One invisible trunk collider stands in for the tree (cheap, never snags on
				-- branch tips)
				local radius = math.max(1.1, height * 0.07 * widthScale)
				part({
					Name = "TrunkCollider",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(height * 0.55, radius * 2, radius * 2),
					CFrame = CFrame.new(ground + Vector3.new(0, height * 0.27, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					Transparency = 1,
					CanTouch = false,
					CastShadow = false,
					Parent = folder,
				})
			end
			count += 1
			maybeYield()
		end
	end
	if templates then
		for _, template in templates do
			template:Destroy()
		end
	end
	folder:SetAttribute("TreeCount", count)
	return count
end

----------------------------------------------------------------------------------------------
-- Distant peaks
----------------------------------------------------------------------------------------------

local PEAK_SNOW = Color3.fromRGB(236, 242, 252)
local PEAK_ROCKS = { Color3.fromRGB(78, 80, 92), Color3.fromRGB(92, 90, 100), Color3.fromRGB(70, 74, 88) }

-- Irregular pyramid: each side its own base extent
local function peakPyramid(folder: Instance, apex: Vector3, height: number, extents: { number }, yaw: number, color: Color3, material: Enum.Material)
	local frame = CFrame.new(apex) * CFrame.Angles(0, yaw, 0)
	height = math.min(height, 2048)
	for q, quadrant in QUADRANTS do
		local a = math.min(extents[q], 2048)
		local b = math.min(extents[q % 4 + 1], 2048)
		part({
			Size = Vector3.new(a, height, b),
			CFrame = frame * quadrant * CFrame.new(-a / 2, -height / 2, b / 2),
			Color = color,
			Material = material,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		}, "CornerWedgePart")
	end
end

-- One peak: a snow pyramid with a dark rock pyramid turned 45° inside it, a little lower, so
-- rock ribs show through the snow on its faces
local function peak(folder: Instance, random: Random, base: Vector3, height: number, width: number)
	local extents = {}
	for i = 1, 4 do
		extents[i] = width * random:NextNumber(0.6, 1.0)
	end
	local yaw = random:NextNumber(0, math.pi * 2)
	peakPyramid(folder, base + Vector3.new(0, height, 0), height, extents, yaw, PEAK_SNOW, Enum.Material.Snow)
	local rock = {}
	for i = 1, 4 do
		rock[i] = extents[i] * random:NextNumber(0.85, 1.05)
	end
	local rockHeight = height * random:NextNumber(0.86, 0.95)
	peakPyramid(folder, base + Vector3.new(0, rockHeight, 0), rockHeight, rock, yaw + math.pi / 4 + random:NextNumber(-0.2, 0.2), PEAK_ROCKS[random:NextInteger(1, #PEAK_ROCKS)], Enum.Material.Slate)
end

-- A massif: several peaks along a ridge line, highest in the middle
local function massif(folder: Instance, random: Random, center: Vector3, direction: Vector3, count: number, height: number)
	for i = 1, count do
		local t = i - (count + 1) / 2
		local h = height * random:NextNumber(0.55, 1.0) * (1 - math.abs(t) / count * 0.6)
		local position = center + direction * t * height * 0.55 + Vector3.new(random:NextNumber(-80, 80), 0, random:NextNumber(-80, 80))
		peak(folder, random, position, h, h * random:NextNumber(0.75, 1.0))
		maybeYield()
	end
end

-- Distant mountains all around: a band of foothills, then high massifs behind them. Bases
-- sit far below the course so the peaks rise out of the haze with no visible bottom edge.
local function buildPanorama(ctx)
	local hf = ctx.HF
	local settings = ctx.Scenery.Panorama
	if not settings then
		return
	end
	local random = Random.new(hf.Course.Seed + 31)
	local folder = Instance.new("Folder")
	folder.Name = "Panorama"
	folder.Parent = ctx.Folder
	local _, maxX, minZ, maxZ = hf:GetBounds()
	local origin = ctx.Origin
	for _, band in settings.Bands do
		local function baseAt(z: number): number
			return hf:ProfileY(math.clamp(z, minZ, maxZ)) - band.Sink
		end
		-- Both sides, along the whole mountain
		for z = minZ - band.Distance[1], maxZ + band.Distance[1], band.Spacing do
			for _, side in { -1, 1 } do
				local x = side * (maxX + random:NextNumber(band.Distance[1], band.Distance[2]))
				local pz = z + random:NextNumber(-band.Spacing * 0.3, band.Spacing * 0.3)
				local direction = Vector3.new(-side * 0.3, 0, 1).Unit
				massif(folder, random, origin + Vector3.new(x, baseAt(pz), pz), direction, random:NextInteger(3, 5), random:NextNumber(band.Height[1], band.Height[2]))
			end
		end
		-- Behind the summit and beyond the finish
		for _, ends in { { minZ, -1 }, { maxZ, 1 } } do
			for x = -maxX * 2, maxX * 2, band.Spacing do
				local z = ends[1] + ends[2] * random:NextNumber(band.Distance[1], band.Distance[2])
				massif(folder, random, origin + Vector3.new(x + random:NextNumber(-200, 200), baseAt(z), z), Vector3.xAxis, random:NextInteger(3, 5), random:NextNumber(band.Height[1], band.Height[2]))
			end
		end
	end
end

----------------------------------------------------------------------------------------------

function MountainBuilder.Build(heightfield, courseFolder: Instance)
	local course = heightfield.Course
	local scenery = heightfield.World.Scenery
	if not scenery then
		return 0
	end
	lastYield = os.clock()
	local ctx = {
		HF = heightfield,
		Scenery = scenery,
		Origin = course.Origin,
		Folder = courseFolder,
		Random = Random.new(course.Seed + 11),
		Footprints = {}, -- rocks: trees keep clear
		Clear = {}, -- other features trees keep clear of
		Height = function(x: number, z: number): number
			return heightfield:GetHeight(x, z)
		end,
	}
	buildPanorama(ctx)
	buildRocks(ctx)
	buildCave(ctx)
	buildWaterfall(ctx)
	buildMarkers(ctx)
	return buildForest(ctx)
end

return MountainBuilder
