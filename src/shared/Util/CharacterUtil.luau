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

-- A joint's offsets in Part0 / Part1 space, for both R15 joint types (Motor6D and the newer
-- AnimationConstraint). Part1 = Part0 * c0 * Transform * c1:Inverse().
function CharacterUtil.JointFrames(joint: Instance): (CFrame, CFrame)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	end
	local constraint = joint :: AnimationConstraint
	return constraint.Attachment0.CFrame, constraint.Attachment1.CFrame
end

local LEG_CHAIN = {
	{ "LowerTorso", "Root" },
	{ "UpperLeg", "Hip" },
	{ "LowerLeg", "Knee" },
	{ "Foot", "Ankle" },
}

--[[
	Where an R15 foot sits relative to the HumanoidRootPart in the unposed (rest) rig, from the
	joint offsets alone, so it doesn't depend on whatever animation is playing. Riding gear is
	placed from this, and the riding pose puts the feet back onto the gear. nil for R6 rigs.
]]
function CharacterUtil.GetRestFootCFrame(character: Model, side: string): CFrame?
	local frame = CFrame.identity
	for _, link in LEG_CHAIN do
		local partName = if link[1] == "LowerTorso" then link[1] else side .. link[1]
		local jointName = if link[2] == "Root" then link[2] else side .. link[2]
		local part = character:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if not joint or not (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return nil
		end
		local c0, c1 = CharacterUtil.JointFrames(joint)
		frame = frame * c0 * c1:Inverse()
	end
	return frame
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
