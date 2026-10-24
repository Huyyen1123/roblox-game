--[[
	RiderPose
	Procedural riding stance for one R15 character, written to each joint's Transform every
	frame (PreSimulation). Works with both R15 joint types: classic Motor6Ds and the newer
	AnimationConstraints (Roblox can hand out either for the same avatar). Both expose Transform
	with the same convention.

	Leg geometry: the hip flexes by a, the knee bends by 2a and the ankle by a, so the shins tilt
	forward while the feet stay flat and directly below the hips. The LowerTorso is lowered by
	exactly the height the bent legs lose, so the feet stay planted on the skis or board (which
	are welded to the HumanoidRootPart).

	Joint convention (R15 rig attachments/C0/C1 have identity rotations): rotating +X swings a
	hanging limb forward and tips a part's top backward; rotating +Z swings a hanging limb
	toward +X.

	input = {
		Tuck: number,      -- 0..1
		Air: boolean,
		Brake: boolean,
		Charge: number,    -- 0..1 jump charge
		Steer: number,     -- -1..1 (local rider only; remote riders use 0)
		Stumble: boolean,
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseConfig = require(ReplicatedStorage.Shared.Config.PoseConfig)

local RiderPose = {}
RiderPose.__index = RiderPose

local JOINTS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	LeftHip = { "LeftUpperLeg", "LeftHip" },
	LeftKnee = { "LeftLowerLeg", "LeftKnee" },
	LeftAnkle = { "LeftFoot", "LeftAnkle" },
	RightHip = { "RightUpperLeg", "RightHip" },
	RightKnee = { "RightLowerLeg", "RightKnee" },
	RightAnkle = { "RightFoot", "RightAnkle" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	LeftElbow = { "LeftLowerArm", "LeftElbow" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	RightElbow = { "RightLowerArm", "RightElbow" },
}

local EASED = { "Crouch", "Torso", "ArmForward", "Elbow", "ArmOut", "Angulation" }

-- Joint offsets in Part0 / Part1 space, whichever joint type the rig uses.
local function jointFrames(joint: Instance): (CFrame, CFrame)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	end
	return (joint :: AnimationConstraint).Attachment0.CFrame, (joint :: AnimationConstraint).Attachment1.CFrame
end

local function isJoint(instance: Instance?): boolean
	if not instance then
		return false
	end
	if instance:IsA("Motor6D") then
		return true
	end
	return instance:IsA("AnimationConstraint") and instance.Attachment0 ~= nil and instance.Attachment1 ~= nil
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Returns nil for rigs that can't be posed (R6, or missing joints).
function RiderPose.new(character: Model, sportId: string?, stance: string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end

	local joints = {}
	for name, path in JOINTS do
		local part = character:FindFirstChild(path[1])
		local joint = part and part:FindFirstChild(path[2])
		if not isJoint(joint) then
			return nil
		end
		joints[name] = joint
	end

	local _, hipInThigh = jointFrames(joints.LeftHip)
	local kneeInThigh, kneeInShin = jointFrames(joints.LeftKnee)
	local ankleInShin = jointFrames(joints.LeftAnkle)
	local thigh = (hipInThigh.Position - kneeInThigh.Position).Magnitude
	local shin = (kneeInShin.Position - ankleInShin.Position).Magnitude
	local style = PoseConfig[sportId or "Ski"] or PoseConfig.Ski

	local current = {}
	for _, key in EASED do
		current[key] = 0
	end

	return setmetatable({
		Joints = joints,
		LegLength = thigh + shin,
		Style = style,
		-- Regular stance leads with the left foot: the body faces right of the travel direction.
		StanceSign = if stance == "Goofy" then 1 else -1,
		Current = current,
		LandingCrouch = 0,
		Clock = 0,
	}, RiderPose)
end

function RiderPose:OnLanded(impact: number)
	self.LandingCrouch = math.min(impact * PoseConfig.LandingCompressionPerImpact, PoseConfig.MaxLandingCompression)
end

function RiderPose:Update(dt: number, input)
	local style = self.Style
	local tuck = math.clamp(input.Tuck or 0, 0, 1)
	self.Clock += dt
	self.LandingCrouch *= math.exp(-PoseConfig.LandingRecovery * dt)

	-- Targets
	local crouch = lerp(style.Crouch, style.TuckCrouch, tuck)
	if input.Brake then
		crouch = math.max(crouch, style.BrakeCrouch)
	end
	if input.Air then
		crouch = math.max(crouch, style.AirCrouch)
	end
	crouch += style.ChargeCrouch * math.clamp(input.Charge or 0, 0, 1) + self.LandingCrouch

	local armOut = style.ArmOut
	if input.Stumble then
		armOut += PoseConfig.StumbleWobble * (1 + math.sin(self.Clock * 14))
	end

	local targets = {
		Crouch = math.min(crouch, 70),
		Torso = lerp(style.TorsoPitch, style.TuckTorsoPitch, tuck),
		ArmForward = lerp(style.ArmForward, style.TuckArmForward, tuck),
		Elbow = lerp(style.Elbow, style.TuckElbow, tuck),
		ArmOut = armOut,
		Angulation = (input.Steer or 0) * style.Angulation,
	}

	-- Ease toward targets so states blend instead of snapping
	local alpha = 1 - math.exp(-PoseConfig.Responsiveness * dt)
	local current = self.Current
	for _, key in EASED do
		current[key] += (targets[key] - current[key]) * alpha
	end

	self:Apply()
end

function RiderPose:Apply()
	local joints = self.Joints
	local style = self.Style
	local current = self.Current
	local rad = math.rad

	local a = rad(current.Crouch)
	local spread = rad(style.Spread)
	local drop = self.LegLength * (1 - math.cos(a) * math.cos(spread))
	local bodyYaw = rad(style.StanceYaw) * self.StanceSign
	local headYaw = -rad(style.HeadYaw) * self.StanceSign
	local torso = rad(current.Torso)

	joints.Root.Transform = CFrame.new(0, -drop, 0) * CFrame.Angles(0, bodyYaw, 0)
	joints.Waist.Transform = CFrame.Angles(-torso, 0, rad(current.Angulation))
	joints.Neck.Transform = CFrame.Angles(0, headYaw, 0) * CFrame.Angles(torso * style.NeckCompensation, 0, 0)

	joints.LeftHip.Transform = CFrame.Angles(0, 0, -spread) * CFrame.Angles(a, 0, 0)
	joints.RightHip.Transform = CFrame.Angles(0, 0, spread) * CFrame.Angles(a, 0, 0)
	joints.LeftKnee.Transform = CFrame.Angles(-2 * a, 0, 0)
	joints.RightKnee.Transform = CFrame.Angles(-2 * a, 0, 0)
	joints.LeftAnkle.Transform = CFrame.Angles(a, 0, spread)
	joints.RightAnkle.Transform = CFrame.Angles(a, 0, -spread)

	local armForward = rad(current.ArmForward)
	local armOut = rad(current.ArmOut)
	local elbow = rad(current.Elbow)
	joints.LeftShoulder.Transform = CFrame.Angles(0, 0, -armOut) * CFrame.Angles(armForward, 0, 0)
	joints.RightShoulder.Transform = CFrame.Angles(0, 0, armOut) * CFrame.Angles(armForward, 0, 0)
	joints.LeftElbow.Transform = CFrame.Angles(elbow, 0, 0)
	joints.RightElbow.Transform = CFrame.Angles(elbow, 0, 0)
end

-- Returns the character to its default pose (when riding stops).
function RiderPose:Reset()
	for _, joint in self.Joints do
		if joint.Parent then
			joint.Transform = CFrame.identity
		end
	end
end

return RiderPose
