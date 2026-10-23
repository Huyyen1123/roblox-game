--[[
	Small math helpers shared by the camera modes.
]]

local CameraMath = {}

function CameraMath.ExpAlpha(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function CameraMath.Flat(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

-- Yaw such that CFrame.Angles(0, yaw, 0).LookVector points along the flat direction.
function CameraMath.YawFromDirection(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

function CameraMath.LerpAngle(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

return CameraMath
