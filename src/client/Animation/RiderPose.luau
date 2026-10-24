--[[
	RiderPose
	Procedural riding stance for one R15 character, written to each joint's Transform every
	frame (PreSimulation). Works with both R15 joint types: classic Motor6Ds and the newer
	AnimationConstraints (Roblox can hand out either for the same avatar). Both expose Transform
	with the same convention.

	Leg geometry: each hip flexes by a, its knee bends by 2a and its ankle by a, so the shins
	tilt forward while the feet stay flat and below the hips. The LowerTorso is lowered by the
	height the bent legs lose, so the feet stay planted on the skis or board (which are welded
	to the HumanoidRootPart).

	Turning (skis): both legs roll into the turn, the inside leg bends more and the outside leg
	extends, and the upper body counter-rotates and angulates. At the start of each turn the
	inside pole swings forward and plants.

	Joint convention (R15 rig attachments/C0/C1 have identity rotations): rotating +X swings a
	hanging limb forward and tips a part's top backward; rotating +Z swings a hanging limb
	toward +X; rotating +Y turns a part toward -X (left).

	input = {
		Tuck: number,          -- 0..1
		Air: boolean,
		Brake: boolean,
		Charge: number,        -- 0..1 jump charge
		Steer: number,         -- -1..1, positive = turning right
		Stumble: boolean,
		VerticalAccel: number, -- studs/s², for knees absorbing terrain
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
	LeftWrist = { "LeftHand", "LeftWrist" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	RightElbow = { "RightLowerArm", "RightElbow" },
	RightWrist = { "RightHand", "RightWrist" },
}

local EASED = { "Crouch", "Torso", "ArmForward", "Elbow", "ArmOut", "Wrist", "Turn", "Absorb" }

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
		LastSteer = 0,
		PlantSide = 0, -- -1 left pole, 1 right pole
		PlantTime = math.huge,
	}, RiderPose)
end

function RiderPose:OnLanded(impact: number)
	self.LandingCrouch = math.min(impact * PoseConfig.LandingCompressionPerImpact, PoseConfig.MaxLandingCompression)
end

-- Starts a pole plant on the inside of a new turn (turning right plants the right pole).
function RiderPose:DetectPolePlant(steer: number, airborne: boolean)
	local style = self.Style
	local trigger = style.PoleTrigger
	local last = self.LastSteer
	self.LastSteer = steer
	if airborne or math.abs(steer) < trigger then
		return
	end
	local startedTurning = math.abs(last) < trigger
	local switchedSides = math.sign(last) ~= math.sign(steer)
	if startedTurning or switchedSides then
		self.PlantSide = math.sign(steer)
		self.PlantTime = 0
	end
end

function RiderPose:Update(dt: number, input)
	local style = self.Style
	local tuck = math.clamp(input.Tuck or 0, 0, 1)
	local steer = math.clamp(input.Steer or 0, -1, 1)
	self.Clock += dt
	self.PlantTime += dt
	self.LandingCrouch *= math.exp(-PoseConfig.LandingRecovery * dt)
	self:DetectPolePlant(steer, input.Air)

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

	local absorb = 0
	if not input.Air then
		absorb = math.clamp((input.VerticalAccel or 0) * PoseConfig.AbsorbPerAccel, -PoseConfig.MaxAbsorb, PoseConfig.MaxAbsorb)
	end

	local targets = {
		Crouch = math.min(crouch, 70),
		Torso = lerp(style.TorsoPitch, style.TuckTorsoPitch, tuck),
		ArmForward = lerp(style.ArmForward, style.TuckArmForward, tuck),
		Elbow = lerp(style.Elbow, style.TuckElbow, tuck),
		ArmOut = armOut + (if input.Air then style.AirArmOut else 0),
		Wrist = lerp(style.Wrist, style.TuckWrist, tuck),
		Turn = if input.Air then 0 else steer,
		Absorb = absorb,
	}

	-- Ease toward targets so states blend instead of snapping
	local alpha = 1 - math.exp(-PoseConfig.Responsiveness * dt)
	local absorbAlpha = 1 - math.exp(-PoseConfig.AbsorbResponsiveness * dt)
	local current = self.Current
	for _, key in EASED do
		local rate = if key == "Absorb" then absorbAlpha else alpha
		current[key] += (targets[key] - current[key]) * rate
	end

	self:Apply()
end

function RiderPose:Apply()
	local joints = self.Joints
	local style = self.Style
	local current = self.Current
	local rad = math.rad

	-- Per-leg crouch: in a turn the inside leg bends more and the outside leg extends.
	local turn = current.Turn
	local baseCrouch = current.Crouch + current.Absorb
	local rightAdjust = if turn > 0 then turn * style.InsideLegBend else turn * style.OutsideLegExtend
	local leftAdjust = if turn < 0 then -turn * style.InsideLegBend else -turn * style.OutsideLegExtend
	local aLeft = rad(math.clamp(baseCrouch + leftAdjust, 0, 75))
	local aRight = rad(math.clamp(baseCrouch + rightAdjust, 0, 75))
	local aMean = (aLeft + aRight) / 2

	local spread = rad(style.Spread)
	local incline = rad(turn * style.Inclination)
	local drop = self.LegLength * (1 - math.cos(aMean) * math.cos(spread) * math.cos(incline))

	local bodyYaw = rad(style.StanceYaw) * self.StanceSign
	local headYaw = -rad(style.HeadYaw) * self.StanceSign
	local torso = rad(current.Torso)
	local counterYaw = rad(turn * style.CounterRotation)
	local angulation = rad(turn * style.Angulation)

	joints.Root.Transform = CFrame.new(0, -drop, 0) * CFrame.Angles(0, bodyYaw, 0)
	joints.Waist.Transform = CFrame.Angles(0, counterYaw, 0) * CFrame.Angles(-torso, 0, angulation)
	joints.Neck.Transform = CFrame.Angles(0, headYaw - counterYaw, 0) * CFrame.Angles(torso * style.NeckCompensation, 0, 0)

	-- Legs: spread apart, rolled into the turn; ankles counter-roll to keep the feet flat
	joints.LeftHip.Transform = CFrame.Angles(0, 0, -spread + incline) * CFrame.Angles(aLeft, 0, 0)
	joints.RightHip.Transform = CFrame.Angles(0, 0, spread + incline) * CFrame.Angles(aRight, 0, 0)
	joints.LeftKnee.Transform = CFrame.Angles(-2 * aLeft, 0, 0)
	joints.RightKnee.Transform = CFrame.Angles(-2 * aRight, 0, 0)
	joints.LeftAnkle.Transform = CFrame.Angles(aLeft, 0, spread - incline)
	joints.RightAnkle.Transform = CFrame.Angles(aRight, 0, -spread - incline)

	-- Arms, with the pole plant on the inside of a new turn
	local plant = 0
	if self.PlantTime < style.PlantDuration then
		plant = math.sin(math.pi * self.PlantTime / style.PlantDuration)
	end
	local leftPlant = if self.PlantSide < 0 then plant else 0
	local rightPlant = if self.PlantSide > 0 then plant else 0

	local armOut = rad(current.ArmOut)
	local elbow = rad(current.Elbow)
	-- Through a carve the inside hand drives forward and the outside arm lifts for balance
	local function arm(shoulder, elbowJoint, wrist, side: number, plantAmount: number)
		local inside = math.max(turn * side, 0)
		local outside = math.max(-turn * side, 0)
		local forward = rad(current.ArmForward + style.PlantForward * plantAmount + style.CarveArmForward * inside)
		local out = armOut + rad(style.CarveArmOut * outside)
		shoulder.Transform = CFrame.Angles(0, 0, side * out) * CFrame.Angles(forward, 0, 0)
		elbowJoint.Transform = CFrame.Angles(elbow, 0, 0)
		wrist.Transform = CFrame.Angles(rad(current.Wrist + style.PlantWrist * plantAmount), 0, 0)
	end
	arm(joints.LeftShoulder, joints.LeftElbow, joints.LeftWrist, -1, leftPlant)
	arm(joints.RightShoulder, joints.RightElbow, joints.RightWrist, 1, rightPlant)
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
