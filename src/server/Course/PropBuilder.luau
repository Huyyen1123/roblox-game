--[[
	PropBuilder
	Course props: start area, finish arch, kickers, slalom gates and safety fences.
	Everything is placed from the heightfield so props follow the generated terrain.
	Trees live in ForestBuilder; rocks are terrain boulders built by TerrainBuilder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require(ReplicatedStorage.Shared.Util.Create)

local SNOW_WHITE = Color3.fromRGB(240, 246, 252)
local SNOW_MATERIAL = Enum.Material.Snow

local PropBuilder = {}

local function anchoredPart(properties, className: string?)
	properties.Anchored = true
	properties.TopSurface = Enum.SurfaceType.Smooth
	properties.BottomSurface = Enum.SurfaceType.Smooth
	return Create(className or "Part", properties)
end

-- Decorative parts riders can pass through.
local function decoration(properties)
	properties.CanCollide = false
	properties.CanQuery = false
	properties.CanTouch = false
	return anchoredPart(properties)
end

local function addLabel(part: BasePart, text: string, face: Enum.NormalId, color: Color3)
	Create("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
		LightInfluence = 0,
		Parent = part,
	}, {
		Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = text,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = color,
		}),
	})
end

local function buildArch(parent: Instance, name: string, baseCFrame: CFrame, span: number, text: string, colors)
	local model = Create("Model", { Name = name })
	local height = 14
	for _, side in { -1, 1 } do
		decoration({
			Name = "Pillar",
			Size = Vector3.new(2.5, height, 2.5),
			CFrame = baseCFrame * CFrame.new(side * span / 2, height / 2, 0),
			Color = colors.Pillar,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
	local banner = decoration({
		Name = "Banner",
		Size = Vector3.new(span + 2.5, 3.5, 1),
		CFrame = baseCFrame * CFrame.new(0, height + 1, 0),
		Color = colors.Banner,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	addLabel(banner, text, Enum.NormalId.Front, colors.Text)
	addLabel(banner, text, Enum.NormalId.Back, colors.Text)
	model.Parent = parent
	return model
end

local function buildStart(heightfield, folder)
	local course = heightfield.Course
	local z = course.Start.Z
	local x = heightfield:CenterX(z)
	local base = heightfield:GetUprightCFrame(x, z, 0)

	anchoredPart({
		Name = "StartPad",
		Size = Vector3.new(46, 2, 40),
		CFrame = base * CFrame.new(0, -0.6, 0),
		Color = Color3.fromRGB(120, 85, 60),
		Material = Enum.Material.WoodPlanks,
		Parent = folder,
	})

	local gateZ = z + 22
	buildArch(folder, "StartArch", heightfield:GetUprightCFrame(heightfield:CenterX(gateZ), gateZ, 0), 30, course.DisplayName:upper() .. "  START", {
		Pillar = Color3.fromRGB(40, 50, 70),
		Banner = Color3.fromRGB(30, 110, 200),
		Text = Color3.new(1, 1, 1),
	})
end

local function buildFinish(heightfield, folder)
	local z = heightfield.Course.Finish.Z
	local x = heightfield:CenterX(z)
	local base = heightfield:GetUprightCFrame(x, z, 0)

	buildArch(folder, "FinishArch", base, 40, "FINISH", {
		Pillar = Color3.fromRGB(30, 30, 30),
		Banner = Color3.fromRGB(210, 40, 40),
		Text = Color3.new(1, 1, 1),
	})

	decoration({
		Name = "FinishLine",
		Size = Vector3.new(heightfield.World.Piste.HalfWidth * 2, 0.2, 2),
		CFrame = heightfield:GetSurfaceCFrame(x, z) * CFrame.new(0, 0.3, 0),
		Color = Color3.fromRGB(255, 60, 60),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function buildKickers(heightfield, folder)
	for index, kicker in heightfield.Course.Kickers do
		local x = heightfield:CenterX(kicker.Z) + kicker.OffsetX
		local surface = heightfield:GetSurfaceCFrame(x, kicker.Z)
		-- A WedgePart's slope rises toward +Z, so turn it to face uphill: riders climb it going downhill.
		anchoredPart({
			Name = "Kicker" .. index,
			Size = Vector3.new(kicker.Width, kicker.Height, kicker.Length),
			CFrame = surface * CFrame.new(0, kicker.Height / 2 - 0.4, 0) * CFrame.Angles(0, math.pi, 0),
			Color = SNOW_WHITE,
			Material = SNOW_MATERIAL,
			Parent = folder,
		}, "WedgePart")
	end
end

local function nearKicker(course, z: number): boolean
	for _, kicker in course.Kickers do
		if math.abs(kicker.Z - z) < course.Gates.KickerClearance then
			return true
		end
	end
	return false
end

local function buildGates(heightfield, folder)
	local course = heightfield.Course
	local gates = course.Gates
	local side = 1
	local index = 0

	for z = gates.StartZ, gates.EndZ, gates.Spacing do
		if nearKicker(course, z) then
			continue
		end
		index += 1
		side = -side

		local color = if side > 0 then Color3.fromRGB(220, 40, 40) else Color3.fromRGB(40, 90, 220)
		local centerX = heightfield:CenterX(z) + side * gates.Offset
		local gate = Create("Model", { Name = "Gate" .. index })

		for _, poleSide in { -1, 1 } do
			local px = centerX + poleSide * 3
			local base = heightfield:GetUprightCFrame(px, z, 0)
			decoration({
				Name = "Pole",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(7, 0.35, 0.35),
				CFrame = base * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				Parent = gate,
			})
		end

		local panelBase = heightfield:GetUprightCFrame(centerX, z, 0)
		decoration({
			Name = "Panel",
			Size = Vector3.new(5.6, 2.2, 0.1),
			CFrame = panelBase * CFrame.new(0, 5.2, 0),
			Color = color,
			Material = Enum.Material.Fabric,
			Parent = gate,
		})

		gate.Parent = folder
	end
end

local FENCE_COLOR = Color3.fromRGB(205, 32, 42)
local POST_COLOR = Color3.fromRGB(45, 48, 56)
local FENCE_HEIGHT = 2.8

local function fenceSegment(parent: Instance, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	anchoredPart({
		Name = "Net",
		Size = Vector3.new(0.25, FENCE_HEIGHT, length),
		CFrame = CFrame.lookAt(middle, to) * CFrame.new(0, FENCE_HEIGHT / 2 + 0.4, 0),
		Color = FENCE_COLOR,
		Material = Enum.Material.Fabric,
		CanTouch = false,
		Parent = parent,
	})
	decoration({
		Name = "Post",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(FENCE_HEIGHT + 0.8, 0.3, 0.3),
		CFrame = CFrame.new(from + Vector3.new(0, (FENCE_HEIGHT + 0.8) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = POST_COLOR,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
end

-- Red safety netting along both piste edges, plus a barrier across the end of the plaza.
local function buildFences(heightfield, folder)
	local course = heightfield.Course
	local world = heightfield.World
	local fences = course.Fences
	local origin = course.Origin
	local offset = world.Piste.HalfWidth + fences.Inset

	local function point(x: number, z: number): Vector3
		return origin + Vector3.new(x, heightfield:GetHeight(x, z), z)
	end

	for _, side in { -1, 1 } do
		for z = fences.StartZ, fences.EndZ - fences.SegmentLength, fences.SegmentLength do
			local z2 = z + fences.SegmentLength
			fenceSegment(
				folder,
				point(heightfield:CenterX(z) + side * offset, z),
				point(heightfield:CenterX(z2) + side * offset, z2)
			)
		end
	end

	local endZ = heightfield.Length + world.RunOut.Length + world.Plaza.Length - 20
	local centerX = heightfield:CenterX(endZ)
	for x = -offset, offset - fences.SegmentLength, fences.SegmentLength do
		fenceSegment(folder, point(centerX + x, endZ), point(centerX + x + fences.SegmentLength, endZ))
	end
end

function PropBuilder.Build(heightfield, courseFolder: Folder)
	local props = Create("Folder", { Name = "Props", Parent = courseFolder })
	local gates = Create("Folder", { Name = "Gates", Parent = courseFolder })
	local fences = Create("Folder", { Name = "Fences", Parent = courseFolder })

	buildStart(heightfield, props)
	buildFinish(heightfield, props)
	buildKickers(heightfield, props)
	buildGates(heightfield, gates)
	buildFences(heightfield, fences)
end

return PropBuilder
