--[[
	SnowDriftBuilder
	Soft powder drifts and small ridges along both edges of the course, outside the fences,
	so the powder reads as thick snow rather than a flat textured slope.

	Visual only. Every drift is an anchored ball with CanCollide, CanQuery and CanTouch off,
	so collision, ground detection, camera collision and gameplay never see it. Each ball is
	sunk into the slope so only a low, soft cap shows (a sphere cap is a natural drift shape),
	and uses the Snow material, so it gets the same powder texture as the terrain around it.
	Placement is seeded, so every server builds the same drifts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require(ReplicatedStorage.Shared.Util.Create)

local SnowDriftBuilder = {}

local SNOW_COLOR = Color3.fromRGB(236, 242, 250)

-- Ball whose visible cap above the ground is `cap` studs high.
local function drift(folder: Instance, position: Vector3, radius: number, cap: number)
	Create("Part", {
		Name = "Drift",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 2,
		Position = position - Vector3.new(0, radius - cap, 0),
		Material = Enum.Material.Snow,
		Color = SNOW_COLOR,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = true,
		Parent = folder,
	})
end

function SnowDriftBuilder.Build(heightfield, courseFolder: Instance): number
	local course = heightfield.Course
	local settings = course.Drifts
	if not settings then
		return 0
	end
	local world = heightfield.World
	local origin = course.Origin
	local fenceOffset = world.Piste.HalfWidth + course.Fences.Inset
	local rockSlope = world.Materials.EdgeRockSlope
	local random = Random.new(heightfield.Seed + 400)

	local folder = Create("Folder", { Name = "SnowDrifts" })
	local count = 0
	for _, side in { -1, 1 } do
		local z = settings.StartZ
		while z < settings.EndZ do
			local offset = fenceOffset + random:NextNumber(settings.MinOffset, settings.MaxOffset)
			local x = heightfield:CenterX(z) + side * offset
			local height = heightfield:GetHeight(x, z)
			if heightfield:GetSlope(x, z) < rockSlope and not heightfield:IsLake(x, z, height) then
				local radius = random:NextNumber(settings.MinRadius, settings.MaxRadius)
				local cap = random:NextNumber(settings.MinCap, settings.MaxCap)
				drift(folder, origin + Vector3.new(x, height, z), radius, cap)
				count += 1
				-- Companion drift a little further along: together they read as a ridge
				if random:NextNumber() < settings.RidgeChance then
					local z2 = z + random:NextNumber(3, 6)
					local x2 = x + side * random:NextNumber(-2, 3)
					drift(folder, origin + Vector3.new(x2, heightfield:GetHeight(x2, z2), z2), radius * 0.7, cap * 0.75)
					count += 1
				end
			end
			z += settings.Spacing * random:NextNumber(0.6, 1.4)
		end
	end
	folder.Parent = courseFolder
	return count
end

return SnowDriftBuilder
