--[[
	GroundProbe
	Finds the snow under the rider: five downward rays (centre + four around it) averaged into
	one normal, which stays stable on bumpy voxel terrain.

	Returns nil when nothing is below, otherwise:
	  { Position: Vector3, Normal: Vector3, Distance: number }  -- Distance is along the normal
]]

local Workspace = game:GetService("Workspace")

local WORLD_UP = Vector3.yAxis

local GroundProbe = {}

function GroundProbe.Probe(origin: Vector3, heading: Vector3, rideHeight: number, params: RaycastParams, config)
	local right = heading:Cross(WORLD_UP)
	local spread = config.GroundProbeSpread
	local length = rideHeight * 1.8 + config.SnapDistance + config.GroundProbeExtra
	local direction = -WORLD_UP * length

	local offsets = {
		Vector3.zero,
		heading * spread,
		-heading * spread,
		right * spread,
		-right * spread,
	}

	local normalSum = Vector3.zero
	local hits = 0
	local centerHit = nil
	for i, offset in offsets do
		local result = Workspace:Raycast(origin + offset, direction, params)
		if result then
			normalSum += result.Normal
			hits += 1
			if i == 1 then
				centerHit = result
			end
		end
	end

	if hits == 0 then
		return nil
	end

	local normal = normalSum.Unit
	local position
	if centerHit then
		position = centerHit.Position
	else
		-- Estimate the surface under the centre from the averaged plane of the side hits.
		local result = Workspace:Raycast(origin, -normal * length, params)
		if not result then
			return nil
		end
		position = result.Position
	end

	return {
		Position = position,
		Normal = normal,
		Distance = (origin - position):Dot(normal),
	}
end

return GroundProbe
