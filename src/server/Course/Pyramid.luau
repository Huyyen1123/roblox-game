--[[
	Pyramid
	Builds a four-sided pyramid from four CornerWedgeParts that share one apex. Each side can
	have its own base extent, so peaks come out irregular rather than perfectly square.

	A CornerWedgePart's apex sits above its local (+X, -Z) top corner, so a wedge whose apex
	corner is placed at the pyramid's centre fills the quadrant toward local -X and +Z.
	Rotating by 90 degrees per quadrant covers all four sides.
]]

local Pyramid = {}

local QUADRANT_ROTATIONS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(0, math.pi / 2, 0),
	CFrame.Angles(0, math.pi, 0),
	CFrame.Angles(0, math.pi * 3 / 2, 0),
}

--[[
	apex: world position of the tip
	height: apex to base
	extents: { [1..4] = number } base extent from the centre in four directions, which are
	         the yaw-rotated -X, +Z, +X, -Z (all must be <= 2048)
	properties: applied to every wedge (Color, Material, CanCollide, ...)
]]
function Pyramid.Build(parent: Instance, apex: Vector3, height: number, extents: { number }, yaw: number, properties: { [string]: any }): { BasePart }
	local parts = table.create(4)
	local frame = CFrame.new(apex) * CFrame.Angles(0, yaw, 0)

	for quadrant = 1, 4 do
		local a = extents[quadrant]
		local b = extents[quadrant % 4 + 1]
		local rotation = frame * QUADRANT_ROTATIONS[quadrant]

		local wedge = Instance.new("CornerWedgePart")
		wedge.Size = Vector3.new(a, height, b)
		wedge.CFrame = rotation * CFrame.new(-a / 2, -height / 2, b / 2)
		wedge.Anchored = true
		for key, value in properties do
			(wedge :: any)[key] = value
		end
		wedge.Parent = parent
		parts[quadrant] = wedge
	end

	return parts
end

-- Same pyramid scaled toward its apex and nudged up, so it covers only the top part:
-- used for snow caps on peaks.
function Pyramid.BuildCap(parent: Instance, apex: Vector3, height: number, extents: { number }, yaw: number, fraction: number, lift: number, properties)
	local scaled = table.create(4)
	for i, extent in extents do
		scaled[i] = extent * fraction
	end
	return Pyramid.Build(parent, apex + Vector3.new(0, lift, 0), height * fraction, scaled, yaw, properties)
end

return Pyramid
