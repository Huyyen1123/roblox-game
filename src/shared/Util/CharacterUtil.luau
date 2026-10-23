--[[
	Character helpers shared by client and server.
]]

local CharacterUtil = {}

-- Distance from the HumanoidRootPart centre down to the bottom of the feet.
function CharacterUtil.GetFootOffset(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return 3
	end

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg") :: BasePart?
		return root.Size.Y / 2 + (leg and leg.Size.Y or 2)
	end

	return root.Size.Y / 2 + humanoid.HipHeight
end

function CharacterUtil.GetAlive(character: Model?): (Humanoid?, BasePart?)
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil, nil
end

return CharacterUtil
