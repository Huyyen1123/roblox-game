--[[
	TestSlopes (Studio only)
	Straight, uniform lanes for measuring movement against the design targets, away from the
	course. Each lane: a flat start pad, a constant-angle slope, a flat run-out, low side rails
	and an end wall. Lane angles come from DevConfig.TestLanes. One lane can carry an obstacle
	post for impact testing.

	Built only when running in Studio; live servers never create these parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Create = require(ReplicatedStorage.Shared.Util.Create)

local TestSlopes = {}
TestSlopes.Lanes = {} -- [index] = { Angle: number, Start: CFrame }

local function slab(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3)
	return Create("Part", {
		Name = name,
		Anchored = true,
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = Enum.Material.Snow,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = parent,
	})
end

function TestSlopes.Build(settings)
	local existing = Workspace:FindFirstChild("TestSlopes")
	if existing then
		existing:Destroy()
	end
	local folder = Create("Folder", { Name = "TestSlopes" })
	local snow = Color3.fromRGB(240, 245, 252)
	local rail = Color3.fromRGB(205, 32, 42)
	local thickness = 4
	local width = settings.LaneWidth

	for index, angle in settings.Angles do
		local lane = Create("Model", { Name = `Lane{index}_{angle}deg` })
		local theta = math.rad(angle)
		local x = settings.Origin.X + (index - 1) * settings.LaneSpacing
		local top = Vector3.new(x, settings.Origin.Y, settings.Origin.Z)

		-- Flat start pad ending at the top of the slope
		local padLength = 40
		slab(lane, "StartPad", CFrame.new(top + Vector3.new(0, -thickness / 2, -padLength / 2)), Vector3.new(width, thickness, padLength), snow)

		-- Constant-angle slope
		local down = Vector3.new(0, -math.sin(theta), math.cos(theta))
		local normal = Vector3.new(0, math.cos(theta), math.sin(theta))
		local length = settings.SlopeLength
		local center = top + down * (length / 2) - normal * (thickness / 2)
		slab(lane, "Slope", CFrame.lookAt(center, center + down, normal), Vector3.new(width, thickness, length), snow)

		-- Flat run-out and end wall
		local bottom = top + down * length
		local runout = settings.RunoutLength
		slab(lane, "Runout", CFrame.new(bottom + Vector3.new(0, -thickness / 2, runout / 2)), Vector3.new(width, thickness, runout), snow)
		slab(lane, "EndWall", CFrame.new(bottom + Vector3.new(0, 6, runout + 1)), Vector3.new(width, 12, 2), rail)

		-- Optional obstacle post in the middle of the lane, for impact testing
		if settings.ObstacleLane == index then
			local postCenter = top + down * settings.ObstacleDistance + normal * 4
			slab(lane, "ObstaclePost", CFrame.lookAt(postCenter, postCenter + down, normal), Vector3.new(4, 8, 4), rail)
		end

		-- Low rails along both sides of the slope
		for _, side in { -1, 1 } do
			local railCenter = top + down * (length / 2) + Vector3.new(side * (width / 2 + 0.5), 0, 0) + normal * 1
			slab(lane, "Rail", CFrame.lookAt(railCenter, railCenter + down, normal), Vector3.new(1, 2, length), rail)
		end

		Create("Part", {
			Name = "Label",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(16, 6, 1),
			CFrame = CFrame.new(top + Vector3.new(0, 12, -padLength)),
			Parent = lane,
		}, {
			Create("BillboardGui", { Size = UDim2.fromOffset(220, 60), AlwaysOnTop = true }, {
				Create("TextLabel", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = `TEST LANE {index}: {angle}°`,
					TextScaled = true,
					Font = Enum.Font.GothamBlack,
					TextColor3 = Color3.new(1, 1, 1),
					TextStrokeTransparency = 0.3,
				}),
			}),
		})

		lane.Parent = folder
		TestSlopes.Lanes[index] = {
			Angle = angle,
			Start = CFrame.lookAt(top + Vector3.new(0, 4, -padLength * 0.5), top + Vector3.new(0, 4, 0)),
		}
	end

	folder.Parent = Workspace
end

return TestSlopes
