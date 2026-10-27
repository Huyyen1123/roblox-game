--[[
	Minimap
	A small round map, top-right. Downhill is up, centred on the rider; the arrow shows
	which way the rider faces. Drawn once from the shared course data (CourseMap):
	  - forest stands (dark green), rock walls along the edges, the frozen lake
	  - the race route through the checkpoints (orange), checkpoint markers (the next one
	    highlighted), start (green), finish (red), the trick park
	  - other riders as white dots
	Everything is plain frames inside one CanvasGroup (round clip), so nothing is rebuilt
	while riding: only the content's position, the arrow and the rider dots move.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Create = require(ReplicatedStorage.Shared.Util.Create)
local CourseMap = require(script.Parent.CourseMap)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local SIZE = 176 -- pixels across
local SCALE = 0.1 -- pixels per stud (shows ~880 studs around the rider)
local ORANGE = Color3.fromRGB(255, 130, 45)

local Minimap = {}

local Movement
local screen: ScreenGui
local canvas: CanvasGroup
local content: Frame?
local contentFor: string? = nil
local arrow: ImageLabel
local checkpointDots = {}
local riderDots = {}
local nextIndex = 1
local halfWidth = 1300
local topZ = 6000

-- Map position (pixels in the content frame) of a course-local point. Downhill (+Z) is up;
-- facing downhill, +X is to the rider's left, so it goes left on the map.
local function toMap(x: number, z: number): UDim2
	return UDim2.fromOffset((halfWidth - x) * SCALE, (topZ - z) * SCALE)
end

local function dot(parent: Instance, x: number, z: number, size: number, color: Color3, transparency: number?, zIndex: number?)
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(x, z),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
		Parent = parent,
	}, { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

-- A straight segment between two course-local points
local function segment(parent: Instance, x0: number, z0: number, x1: number, z1: number, width: number, color: Color3, zIndex: number)
	local a = Vector2.new((halfWidth - x0) * SCALE, (topZ - z0) * SCALE)
	local b = Vector2.new((halfWidth - x1) * SCALE, (topZ - z1) * SCALE)
	local mid = (a + b) / 2
	local delta = b - a
	Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(delta.Magnitude + width * 0.5, width),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = parent,
	})
end

local function buildContent(map)
	if content then
		content:Destroy()
	end
	table.clear(checkpointDots)
	local hf = map.Heightfield
	local course = map.Course
	local _, maxX, minZ, maxZ = hf:GetBounds()
	halfWidth = maxX
	topZ = maxZ
	local frame = Create("Frame", {
		Name = "Content",
		Size = UDim2.fromOffset(maxX * 2 * SCALE, (maxZ - minZ) * SCALE),
		BackgroundColor3 = Color3.fromRGB(232, 239, 248),
		BorderSizePixel = 0,
		Parent = canvas,
	})

	-- Rock walls along both edges
	local walls = hf.World.Walls
	if walls then
		for _, side in { -1, 1 } do
			local inner = side * walls.StartX
			Create("Frame", {
				AnchorPoint = Vector2.new(if side > 0 then 1 else 0, 0),
				Position = UDim2.fromOffset((halfWidth - inner) * SCALE, 0),
				Size = UDim2.fromOffset((maxX - walls.StartX) * SCALE, (maxZ - minZ) * SCALE),
				BackgroundColor3 = Color3.fromRGB(150, 150, 160),
				BorderSizePixel = 0,
				Parent = frame,
			})
		end
	end

	-- Forest stands: where the scenery builder plants trees most densely
	local scenery = hf.World.Scenery
	local forest = scenery and scenery.Forest
	if forest then
		local step = 70
		for z = minZ, maxZ, step do
			for x = -maxX, maxX, step do
				local stand = math.noise(x / forest.StandScale, z / forest.StandScale, course.Seed % 97 + 0.31)
				local dense = stand > 0.2
				for _, section in forest.Sections do
					if z > section.FromZ and z < section.ToZ and math.abs(x - hf:CorridorCenter(section.Corridor, z)) < section.HalfWidth then
						dense = true
					end
				end
				if dense and math.abs(x) < (walls and walls.StartX or maxX) then
					-- Overlapping soft blobs merge into forest patches
					dot(frame, x, z, step * SCALE * 1.7, Color3.fromRGB(96, 140, 110), 0.55)
				end
			end
		end
	end

	-- Frozen lake
	local lake = hf.Lake
	if lake then
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMap(lake.X, lake.Z),
			Size = UDim2.fromOffset(lake.RadiusX * 2 * SCALE, lake.RadiusZ * 2 * SCALE),
			BackgroundColor3 = Color3.fromRGB(120, 180, 225),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = frame,
		}, { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end

	-- Route through the checkpoints (via the beam nearest the middle of the mountain),
	-- start and finish
	local origin = map.Origin
	local points = { { 0, course.Race.StartLineZ } }
	for _, checkpoint in map.Checkpoints do
		local middle = checkpoint.Beams[1]
		for _, beam in checkpoint.Beams do
			if math.abs(beam.X - origin.X) < math.abs(middle.X - origin.X) then
				middle = beam
			end
		end
		table.insert(points, { middle.X - origin.X, middle.Z - origin.Z })
	end
	table.insert(points, { 0, course.Race.FinishZ })
	for i = 1, #points - 1 do
		segment(frame, points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], 3, ORANGE, 3)
	end
	for index, checkpoint in map.Checkpoints do
		local dots = {}
		for _, beam in checkpoint.Beams do
			table.insert(dots, dot(frame, beam.X - origin.X, beam.Z - origin.Z, 9, ORANGE, 0, 4))
		end
		checkpointDots[index] = dots
	end
	dot(frame, 0, course.Race.StartLineZ, 13, Color3.fromRGB(60, 200, 110), 0, 5)
	dot(frame, 0, course.Race.FinishZ, 15, Color3.fromRGB(230, 60, 60), 0, 5)
	local park = course.Spots and course.Spots.TrickPark
	if park then
		local marker = dot(frame, park.X, park.Z + 400, 14, Color3.fromRGB(150, 110, 230), 0, 5)
		Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "P",
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 6,
			Parent = marker,
		})
	end

	content = frame
	contentFor = map.Id
end

local function build()
	screen = Create("ScreenGui", {
		Name = "Minimap",
		ResetOnSpawn = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	canvas = Create("CanvasGroup", {
		Name = "Map",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(232, 239, 248),
		GroupTransparency = 0.05,
		Parent = screen,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	-- Rim
	Create("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Create("UIStroke", { Color = Color3.fromRGB(245, 248, 255), Thickness = 3, Transparency = 0.15 }),
	})
	-- The rider: an arrow at the centre
	arrow = Create("ImageLabel", {
		Name = "Rider",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -16 - SIZE / 2, 0, 14 + SIZE / 2),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Image = "",
		Parent = screen,
	}, {
		Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "▲",
			TextScaled = true,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(235, 40, 40),
			TextStrokeColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0,
		}),
	})
	screen.Parent = player:WaitForChild("PlayerGui")
end

local function riderDot(index: number): Frame
	local existing = riderDots[index]
	if existing then
		return existing
	end
	local frame = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 7,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		Create("UIStroke", { Color = Color3.fromRGB(30, 40, 60), Thickness = 1.5 }),
	})
	riderDots[index] = frame
	return frame
end

local function update()
	local map = CourseMap.Get()
	local root = Movement.State.Root
	if not map or not root then
		canvas.Visible = false
		arrow.Visible = false
		return
	end
	canvas.Visible = true
	arrow.Visible = true
	if contentFor ~= map.Id then
		buildContent(map)
	end
	local origin = map.Origin
	local here = root.Position - origin
	-- Keep the rider at the centre
	content.Position = UDim2.fromOffset(SIZE / 2 - (halfWidth - here.X) * SCALE, SIZE / 2 - (topZ - here.Z) * SCALE)
	-- Facing: map up is +Z, map right is -X
	local heading = Movement.State.Heading
	arrow.Rotation = math.deg(math.atan2(-heading.X, heading.Z))

	-- Highlight the next checkpoint
	for index, dots in checkpointDots do
		local isNext = index == nextIndex
		for _, d in dots do
			d.Size = UDim2.fromOffset(if isNext then 13 else 8, if isNext then 13 else 8)
			d.BackgroundColor3 = if index < nextIndex then Color3.fromRGB(170, 170, 180) else ORANGE
		end
	end

	-- Other riders
	local used = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local otherRoot = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if otherRoot then
				used += 1
				local d = riderDot(used)
				local p = otherRoot.Position - origin
				d.Position = toMap(p.X, p.Z)
				d.Parent = content
			end
		end
	end
	for i = used + 1, #riderDots do
		riderDots[i].Parent = nil
	end
end

function Minimap.Start(movementController)
	Movement = movementController
	build()
	Remotes:WaitForChild("RaceEvent").OnClientEvent:Connect(function(kind, index)
		if kind == "Ready" or kind == "Start" then
			nextIndex = 1
		elseif kind == "Checkpoint" then
			nextIndex = index + 1
		end
	end)
	Movement.Activated:Connect(function()
		screen.Enabled = true
	end)
	Movement.Deactivated:Connect(function()
		screen.Enabled = false
	end)
	screen.Enabled = Movement.IsActive()
	RunService.RenderStepped:Connect(function()
		if screen.Enabled then
			update()
		end
	end)
end

return Minimap
