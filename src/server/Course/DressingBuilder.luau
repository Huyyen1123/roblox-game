--[[
	DressingBuilder
	Race-course set dressing within course.Dressing's Z range: red sponsor-style banners on
	poles behind the safety netting, orange trail-marker poles along the piste edge, and a run
	sign at the start. Snowbanks against the netting are part of the terrain (see Heightfield:Snowbank).

	Everything here is decoration (no collision or queries); it sits behind the netting, which
	is the real barrier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Create = require(ReplicatedStorage.Shared.Util.Create)

local BANNER_RED = Color3.fromRGB(196, 28, 40)
local POLE_GREY = Color3.fromRGB(52, 55, 62)
local MARKER_ORANGE = Color3.fromRGB(255, 120, 20)
local MARKER_BLACK = Color3.fromRGB(25, 25, 28)

local DressingBuilder = {}

local function decoration(className: string, properties)
	properties.Anchored = true
	properties.CanCollide = false
	properties.CanQuery = false
	properties.CanTouch = false
	properties.TopSurface = Enum.SurfaceType.Smooth
	properties.BottomSurface = Enum.SurfaceType.Smooth
	return Create(className, properties)
end

local function label(part: BasePart, face: Enum.NormalId, text: string, rotation: number, color: Color3)
	Create("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 1,
		Parent = part,
	}, {
		Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			-- Swap axes when rotated so the text runs along the banner's length
			Size = if rotation ~= 0
				then UDim2.fromScale(part.Size.Y / part.Size.X * 0.92, part.Size.X / part.Size.Y * 0.8)
				else UDim2.fromScale(0.92, 0.8),
			Rotation = rotation,
			BackgroundTransparency = 1,
			Text = text,
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = color,
		}),
	})
end

-- Tall vertical banner on a pole, facing across the piste.
local function buildBanner(parent: Instance, ground: Vector3, facing: Vector3, text: string)
	local model = Create("Model", { Name = "Banner" })
	local poleHeight = 12
	local frame = CFrame.lookAt(ground, ground + facing)

	decoration("Part", {
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(poleHeight, 0.35, 0.35),
		CFrame = frame * CFrame.new(0, poleHeight / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = POLE_GREY,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local flag = decoration("Part", {
		Name = "Flag",
		Size = Vector3.new(2.8, 8, 0.12),
		CFrame = frame * CFrame.new(1.6, poleHeight - 4.6, 0),
		Color = BANNER_RED,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	label(flag, Enum.NormalId.Front, text, -90, Color3.new(1, 1, 1))
	label(flag, Enum.NormalId.Back, text, 90, Color3.new(1, 1, 1))

	model.Parent = parent
end

local function buildMarker(parent: Instance, ground: Vector3)
	local model = Create("Model", { Name = "TrailMarker" })
	decoration("Part", {
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 0.3, 0.3),
		CFrame = CFrame.new(ground + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = MARKER_ORANGE,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	decoration("Part", {
		Name = "Band",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 0.34, 0.34),
		CFrame = CFrame.new(ground + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = MARKER_BLACK,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	model.Parent = parent
end

local function buildRunSign(parent: Instance, heightfield)
	local course = heightfield.Course
	local z = course.Start.Z + 30
	local x = heightfield:CenterX(z) - (heightfield.World.Piste.HalfWidth - 8)
	local base = heightfield:GetUprightCFrame(x, z, 0) * CFrame.Angles(0, math.rad(-25), 0)

	local model = Create("Model", { Name = "RunSign" })
	for _, side in { -1, 1 } do
		decoration("Part", {
			Name = "Post",
			Size = Vector3.new(0.4, 7, 0.4),
			CFrame = base * CFrame.new(side * 2.6, 3.5, 0),
			Color = Color3.fromRGB(90, 66, 48),
			Material = Enum.Material.Wood,
			Parent = model,
		})
	end
	local board = decoration("Part", {
		Name = "Board",
		Size = Vector3.new(6.4, 3.2, 0.3),
		CFrame = base * CFrame.new(0, 6, 0),
		Color = Color3.fromRGB(196, 28, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- The run's name faces riders arriving from the start (uphill side)
	label(board, Enum.NormalId.Back, `{course.DisplayName:upper()} DOWNHILL`, 0, Color3.new(1, 1, 1))
	model.Parent = parent
end

function DressingBuilder.Build(heightfield, courseFolder: Instance)
	local course = heightfield.Course
	local dressing = course.Dressing
	local origin = course.Origin
	local fenceOffset = heightfield.World.Piste.HalfWidth + course.Fences.Inset

	local folder = Create("Folder", { Name = "Dressing", Parent = courseFolder })

	local function ground(x: number, z: number): Vector3
		return origin + Vector3.new(x, heightfield:GetHeight(x, z), z)
	end

	-- Banners alternate sides, just behind the netting, facing the centre line
	local side = 1
	for z = math.max(dressing.StartZ, course.Fences.StartZ) + 20, dressing.EndZ, dressing.BannerSpacing do
		side = -side
		local centerX = heightfield:CenterX(z)
		local position = ground(centerX + side * (fenceOffset + 2.5), z)
		local facing = Vector3.new(-side, 0, 0)
		buildBanner(folder, position, facing, course.DisplayName:upper())
	end

	-- Trail markers on both edges, inside the netting
	for z = math.max(dressing.StartZ, course.Fences.StartZ), dressing.EndZ, dressing.MarkerSpacing do
		for _, markerSide in { -1, 1 } do
			buildMarker(folder, ground(heightfield:CenterX(z) + markerSide * (fenceOffset - 4), z))
		end
	end

	buildRunSign(folder, heightfield)
end

return DressingBuilder
