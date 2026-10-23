--[[
	ForestBuilder
	Places pine forests on the slopes around the course.

	Placement: a jittered grid over the terrain, kept off the piste, cliffs, lakes and the
	finish area. Density follows low-frequency noise so trees form natural stands and
	clearings instead of an even carpet, and thins out away from the course.

	Trees: if ServerStorage.Assets.Trees contains Models or MeshParts (for example pines from a
	trusted Creator Store pack), random templates are cloned and scaled. Otherwise a
	procedural low-poly pine is built from pyramid tiers: near the course with a trunk,
	three tiers and collisions; far away with two tiers, no collisions and no shadows, to keep
	the part count reasonable for 8-player servers.
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

local function getTemplates(): { Instance }
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Trees")
	local templates = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") or child:IsA("BasePart") then
				table.insert(templates, child)
			end
		end
	end
	return templates
end

local function placeTemplate(parent: Instance, template: Instance, ground: Vector3, scale: number, yaw: number, near: boolean)
	local tree = template:Clone()
	local cframe = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	if tree:IsA("Model") then
		tree:ScaleTo(tree:GetScale() * scale)
		local _, size = tree:GetBoundingBox()
		tree:PivotTo(cframe * CFrame.new(0, size.Y / 2 - 0.5, 0))
	else
		tree.Size *= scale
		tree.CFrame = cframe * CFrame.new(0, tree.Size.Y / 2 - 0.5, 0)
	end
	for _, part in (if tree:IsA("BasePart") then { tree } else tree:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			part.CanCollide = near
			part.CastShadow = near
		end
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
				placeTemplate(folder, templates[random:NextInteger(1, #templates)], ground, scale, yaw, near)
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
