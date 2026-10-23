--[[
	ForestBuilder
	Places pine forests on the slopes around the course.

	Placement: a jittered grid over the terrain, kept off the piste, cliffs, lakes and the
	finish area. Density follows low-frequency noise so trees form natural stands and
	clearings instead of an even carpet, and thins out away from the course.

	Trees: Models in ServerStorage.Assets.Trees (snow-covered spruce MeshParts imported from the
	Creator Store; they live in the place file, not in Rojo) are cloned, sized to a target
	height and grounded by their real lowest point. Identical meshes are instanced by the
	renderer, so hundreds of copies stay cheap. Meshes never collide; trees near the piste get
	one invisible trunk collider, and far trees skip shadows.
	Without templates, a procedural low-poly pine is built from pyramid tiers as a fallback.
]]

local ServerStorage = game:GetService("ServerStorage")

local Pyramid = require(script.Parent.Pyramid)

local YIELD_BUDGET = 0.03

local TIER_COLORS = {
	Color3.fromRGB(30, 62, 47),
	Color3.fromRGB(37, 74, 56),
	Color3.fromRGB(182, 204, 204), -- snow-dusted crown
}
local TRUNK_COLOR = Color3.fromRGB(78, 56, 42)

local ForestBuilder = {}

local SINK = 0.6 -- studs the base is buried so trees never float on uneven snow

-- Imported models come with arbitrary pivots and sizes, so each template is measured once:
-- its height, and how far its pivot sits above its lowest point.
local function getTemplates(): { { Template: Model, Height: number, Lift: number, Rotation: CFrame } }
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Trees")
	local templates = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				local box, size = child:GetBoundingBox()
				local pivot = child:GetPivot()
				table.insert(templates, {
					Template = child,
					Height = size.Y,
					Lift = pivot.Position.Y - (box.Position.Y - size.Y / 2),
					Rotation = pivot.Rotation,
				})
			end
		end
	end
	return templates
end

local function placeTemplate(parent: Instance, info, ground: Vector3, height: number, yaw: number, near: boolean)
	local scale = height / info.Height
	local tree = info.Template:Clone()
	tree:ScaleTo(tree:GetScale() * scale)
	tree:PivotTo(CFrame.new(ground + Vector3.new(0, info.Lift * scale - SINK, 0)) * CFrame.Angles(0, yaw, 0) * info.Rotation)

	-- Visual meshes never collide; near the course an invisible trunk collider stands in,
	-- which is far cheaper than mesh collision and doesn't snag riders on branch tips.
	for _, part in tree:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = near
		end
	end
	if near then
		local radius = math.max(0.8, height * 0.035)
		local collider = Instance.new("Part")
		collider.Name = "TrunkCollider"
		collider.Shape = Enum.PartType.Cylinder
		collider.Size = Vector3.new(height * 0.6, radius * 2, radius * 2)
		collider.CFrame = CFrame.new(ground + Vector3.new(0, height * 0.3 - SINK, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		collider.Transparency = 1
		collider.Anchored = true
		collider.CanTouch = false
		collider.CastShadow = false
		collider.Parent = tree
	end
	tree.Parent = parent
end

local function buildPine(parent: Instance, ground: Vector3, height: number, yaw: number, near: boolean)
	local tree = Instance.new("Model")
	tree.Name = "Pine"

	local width = height * 0.42
	local tiers = if near then 3 else 2
	local first = if near then 1 else 2

	if near then
		local trunk = Instance.new("Part")
		trunk.Name = "Trunk"
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(height * 0.3, height * 0.07, height * 0.07)
		trunk.CFrame = CFrame.new(ground + Vector3.new(0, height * 0.15 - 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		trunk.Color = TRUNK_COLOR
		trunk.Material = Enum.Material.Wood
		trunk.Anchored = true
		trunk.CanTouch = false
		trunk.Parent = tree
	end

	local properties = {
		Material = Enum.Material.SmoothPlastic,
		CanCollide = near,
		CanQuery = near,
		CanTouch = false,
		CastShadow = near,
	}
	local trunkHeight = height * (if near then 0.12 else 0.02)
	for tier = 1, tiers do
		-- Tiers shrink and overlap upward; each is rotated so the silhouette isn't square
		local t = (tier - 1) / tiers
		local tierHeight = height * (0.48 - t * 0.12)
		local tierBase = trunkHeight + t * (height - trunkHeight) * 0.55
		local extent = width * (1 - t * 0.38)
		properties.Color = TIER_COLORS[first + tier - 1] or TIER_COLORS[#TIER_COLORS]
		Pyramid.Build(
			tree,
			ground + Vector3.new(0, tierBase + tierHeight - 0.5, 0),
			tierHeight,
			{ extent, extent, extent, extent },
			yaw + tier * math.pi / 4,
			properties
		)
	end

	tree.Parent = parent
end

function ForestBuilder.Build(heightfield, courseFolder: Instance)
	local course = heightfield.Course
	local world = heightfield.World
	local settings = world.Forest
	local origin = course.Origin
	local random = Random.new(course.Seed + 3)
	local templates = getTemplates()

	local folder = Instance.new("Folder")
	folder.Name = "Forest"
	folder.Parent = courseFolder

	local minX, maxX, minZ, maxZ = heightfield:GetBounds()
	local spacing = settings.Spacing
	local halfWidth = world.Piste.HalfWidth
	local finishZ = course.Finish.Z
	local plazaEnd = heightfield.Length + world.RunOut.Length + world.Plaza.Length
	local lastYield = os.clock()
	local count = 0

	for z = minZ + spacing / 2, maxZ, spacing do
		for x = minX + spacing / 2, maxX, spacing do
			local px = x + random:NextNumber(-0.45, 0.45) * spacing
			local pz = z + random:NextNumber(-0.45, 0.45) * spacing
			local beyond = math.abs(heightfield:Offset(px, pz)) - halfWidth

			if beyond < settings.MinPisteGap or beyond > settings.MaxDistance then
				continue
			end
			-- Keep the finish arena and plaza open
			if pz > finishZ - 40 and pz < plazaEnd and beyond < 160 then
				continue
			end

			local near = beyond < settings.NearDistance
			local stand = heightfield:Fbm(px, pz, settings.NoiseScale, 2)
			local density = settings.Density * math.clamp((stand + 0.15) / 0.6, 0, 1)
			if not near then
				density *= settings.FarDensity
			end
			if random:NextNumber() >= density then
				continue
			end

			local height = heightfield:GetHeight(px, pz)
			if heightfield:GetSlope(px, pz) > settings.MaxSlope or heightfield:IsLake(px, pz, height) then
				continue
			end

			local ground = origin + Vector3.new(px, height, pz)
			local yaw = random:NextNumber(0, math.pi * 2)
			local scale = random:NextNumber(0.7, 1.35)
			if #templates > 0 then
				placeTemplate(folder, templates[random:NextInteger(1, #templates)], ground, (if near then 30 else 38) * scale, yaw, near)
			else
				buildPine(folder, ground, (if near then 22 else 28) * scale, yaw, near)
			end
			count += 1

			if os.clock() - lastYield > YIELD_BUDGET then
				task.wait()
				lastYield = os.clock()
			end
		end
	end

	folder:SetAttribute("TreeCount", count)
	return count
end

return ForestBuilder
