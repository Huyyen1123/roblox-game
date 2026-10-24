--[[
	RiderPose
	Procedural riding stance for one R15 character, written to each joint's Transform every
	frame (PreSimulation). Works with both R15 joint types: classic Motor6Ds and the newer
	AnimationConstraints (Roblox can hand out either for the same avatar).

	Feet and equipment are one system. The equipment decides where each foot must be, and the
	legs are solved to reach it exactly (two-bone IK through hip and knee, with the ankle turned
	to sit flat in the binding):
	  - Skis are welded to the feet (EquipmentService), so each ski goes wherever its boot goes.
	    The feet are placed on the snow under the hips, the inside ski higher when the body
	    leans into a turn (both edges stay on the snow), and both shift slightly to the outside
	    of the turn (hips inside, feet outside).
	  - The snowboard is rigid on the HumanoidRootPart, so both feet are solved onto its fixed
	    binding positions.
	Crouching lowers the pelvis; the IK then bends the knees to keep the feet planted. The
	pelvis always drops at least far enough for both feet to reach, so the legs never
	over-stretch and the feet never leave their bindings.

	Joint convention (R15 rig attachments/C0/C1 have identity rotations): rotating +X swings a
	hanging limb forward; rotating +Z swings a hanging limb toward +X; rotating +Y turns a part
	toward -X (left).

	input = {
		Tuck: number,          -- 0..1
		Air: boolean,
		Brake: boolean,
		Charge: number,        -- 0..1 jump charge
		Steer: number,         -- -1..1, positive = turning right
		Stumble: boolean,
		VerticalAccel: number, -- studs/s², for knees absorbing terrain
		Lean: number,          -- radians the rider is rolled (positive = right side up)
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoseConfig = require(ReplicatedStorage.Shared.Config.PoseConfig)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)

local jointFrames = CharacterUtil.JointFrames

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

-- Legs never straighten past this share of their length (keeps the knee solution stable)
local MAX_REACH = 0.995
local MAX_LEAN = math.rad(40)

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

local function legData(joints, side: string)
	local hipC0, hipC1 = jointFrames(joints[side .. "Hip"])
	local kneeC0, kneeC1 = jointFrames(joints[side .. "Knee"])
	local ankleC0, ankleC1 = jointFrames(joints[side .. "Ankle"])
	return {
		Hip = joints[side .. "Hip"],
		Knee = joints[side .. "Knee"],
		Ankle = joints[side .. "Ankle"],
		HipC0 = hipC0,
		HipC1 = hipC1,
		KneeC0 = kneeC0,
		KneeC1 = kneeC1,
		AnkleC0 = ankleC0,
		AnkleC1 = ankleC1,
		Thigh = (hipC1.Position - kneeC0.Position).Magnitude,
		Shin = (kneeC1.Position - ankleC0.Position).Magnitude,
	}
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
	local leftFoot = CharacterUtil.GetRestFootCFrame(character, "Left")
	local rightFoot = CharacterUtil.GetRestFootCFrame(character, "Right")
	local footPart = character:FindFirstChild("LeftFoot") :: BasePart?
	if not leftFoot or not rightFoot or not footPart then
		return nil
	end

	local sport = SportConfig.Sports[sportId or "Ski"] or SportConfig.Sports.Ski
	local style = PoseConfig[sport.Id] or PoseConfig.Ski
	local current = {}
	for _, key in EASED do
		current[key] = 0
	end
	local rootC0, rootC1 = jointFrames(joints.Root)
	local left, right = legData(joints, "Left"), legData(joints, "Right")

	return setmetatable({
		Joints = joints,
		Legs = { Left = left, Right = right },
		RootC0 = rootC0,
		RootC1 = rootC1,
		LegLength = left.Thigh + left.Shin,
		-- Height of a foot's centre (root space) when its sole is on the snow / binding
		FootCenterY = -CharacterUtil.GetFootOffset(character) + footPart.Size.Y / 2,
		RestFootZ = (leftFoot.Position.Z + rightFoot.Position.Z) / 2,
		Equipment = sport.Equipment,
		Style = style,
		-- Regular stance leads with the left foot: the body faces right of the travel direction.
		StanceSign = if stance == "Goofy" then 1 else -1,
		Current = current,
		LandingCrouch = 0,
		Clock = 0,
		LastSteer = 0,
		PlantSide = 0, -- -1 left pole, 1 right pole
		PlantTime = math.huge,
		PopTime = math.huge, -- time since takeoff from a charged jump
		WasAir = false,
		LastCharge = 0,
		Lean = 0,
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
	local charge = math.clamp(input.Charge or 0, 0, 1)
	self.Clock += dt
	self.PlantTime += dt
	self.PopTime += dt
	self.LandingCrouch *= math.exp(-PoseConfig.LandingRecovery * dt)
	self:DetectPolePlant(steer, input.Air)
	-- In the air the skis stay level with the body; on the snow they follow the lean
	local leanTarget = if input.Air then 0 else math.clamp(input.Lean or 0, -MAX_LEAN, MAX_LEAN)
	self.Lean += (leanTarget - self.Lean) * (1 - math.exp(-PoseConfig.Responsiveness * dt))

	-- Takeoff from a charged jump: the legs pop straight and the arms throw forward
	if input.Air and not self.WasAir and self.LastCharge > 0.05 then
		self.PopTime = 0
	end
	self.WasAir = input.Air
	self.LastCharge = charge
	local popping = self.PopTime < PoseConfig.PopDuration

	-- Targets
	local crouch = lerp(style.Crouch, style.TuckCrouch, tuck)
	if input.Brake then
		crouch = math.max(crouch, style.BrakeCrouch)
	end
	if input.Air then
		crouch = math.max(crouch, style.AirCrouch)
	end
	crouch += style.ChargeCrouch * charge + self.LandingCrouch
	if popping then
		crouch = style.PopCrouch
	end

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
		Torso = lerp(style.TorsoPitch, style.TuckTorsoPitch, tuck) + style.ChargeTorso * charge,
		ArmForward = lerp(style.ArmForward, style.TuckArmForward, tuck)
			- style.ChargeArmBack * charge
			+ (if popping then style.PopArmForward else 0),
		Elbow = lerp(style.Elbow, style.TuckElbow, tuck),
		ArmOut = armOut + (if input.Air then style.AirArmOut else 0),
		Wrist = lerp(style.Wrist, style.TuckWrist, tuck),
		Turn = if input.Air then 0 else steer,
		Absorb = absorb,
	}

	-- Ease toward targets so states blend instead of snapping
	local responsiveness = PoseConfig.Responsiveness
	if popping then
		responsiveness = PoseConfig.PopResponsiveness
	elseif charge > 0 then
		responsiveness = PoseConfig.ChargeResponsiveness
	end
	local alpha = 1 - math.exp(-responsiveness * dt)
	local absorbAlpha = 1 - math.exp(-PoseConfig.AbsorbResponsiveness * dt)
	local current = self.Current
	for _, key in EASED do
		local rate = if key == "Absorb" then absorbAlpha else alpha
		current[key] += (targets[key] - current[key]) * rate
	end

	self:Apply()
end

-- Where each foot's centre must be (root space): on its ski's track, or in its board binding.
function RiderPose:FootTargets(): (CFrame, CFrame)
	local equipment = self.Equipment
	local y = self.FootCenterY

	if equipment.Kind == "Board" then
		-- Feet across the board, pointing where the body faces; regular rides left foot forward
		local yaw = CFrame.Angles(0, math.rad(self.Style.StanceYaw) * self.StanceSign, 0)
		local leftZ = self.StanceSign * equipment.BindingSpacing / 2
		return CFrame.new(0, y, leftZ) * yaw, CFrame.new(0, y, -leftZ) * yaw
	end

	-- Skis: hip-width apart, shifted to the outside of the turn; when the body leans, the
	-- inside ski sits higher so both edges stay on the snow
	local z = self.RestFootZ
	local shift = -self.Current.Turn * self.Style.CarveShift
	local slope = math.tan(self.Lean)
	local half = equipment.Spacing / 2
	local leftX, rightX = -half + shift, half + shift
	return CFrame.new(leftX, y - leftX * slope, z), CFrame.new(rightX, y - rightX * slope, z)
end

-- Two-bone IK: joint transforms that put this leg's foot exactly at footTarget (root space).
local function solveLeg(leg, lowerTorso: CFrame, footTarget: CFrame)
	local hipPivot = lowerTorso * leg.HipC0
	local ankleTarget = (footTarget * leg.AnkleC1).Position
	local toAnkle = hipPivot:PointToObjectSpace(ankleTarget)
	local thigh, shin = leg.Thigh, leg.Shin
	local reach = math.clamp(toAnkle.Magnitude, math.abs(thigh - shin) + 1e-3, (thigh + shin) * MAX_REACH)

	-- Aim the leg's rest axis (-Y) at the ankle target, keeping the knee pointing forward
	local up = -toAnkle.Unit
	local back = Vector3.zAxis - up * up.Z
	if back.Magnitude < 1e-3 then
		back = Vector3.xAxis:Cross(up)
	end
	back = back.Unit
	local aim = CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back)

	-- Law of cosines: thigh swings forward from the aim line, knee bends back to meet the target
	local hipAngle = math.acos(math.clamp((thigh * thigh + reach * reach - shin * shin) / (2 * thigh * reach), -1, 1))
	local kneeInner = math.acos(math.clamp((thigh * thigh + shin * shin - reach * reach) / (2 * thigh * shin), -1, 1))
	local hipT = aim * CFrame.Angles(hipAngle, 0, 0)
	local kneeT = CFrame.Angles(-(math.pi - kneeInner), 0, 0)

	-- Ankle: turn the foot to the target orientation (flat in the binding)
	local thighFrame = hipPivot * hipT * leg.HipC1:Inverse()
	local shinFrame = thighFrame * leg.KneeC0 * kneeT * leg.KneeC1:Inverse()
	local ankleT = ((shinFrame * leg.AnkleC0):Inverse() * footTarget * leg.AnkleC1).Rotation

	leg.Hip.Transform = hipT
	leg.Knee.Transform = kneeT
	leg.Ankle.Transform = ankleT
end

-- How far the pelvis must drop (from rest) for a leg to reach its target without over-stretching.
local function requiredDrop(leg, restLowerTorso: CFrame, footTarget: CFrame): number
	local hip = (restLowerTorso * leg.HipC0).Position
	local ankle = (footTarget * leg.AnkleC1).Position
	local maxReach = (leg.Thigh + leg.Shin) * MAX_REACH
	local horizontal = Vector2.new(hip.X - ankle.X, hip.Z - ankle.Z).Magnitude
	local vertical = math.sqrt(math.max(maxReach * maxReach - horizontal * horizontal, 0))
	return (hip.Y - ankle.Y) - vertical
end

function RiderPose:Apply()
	local joints = self.Joints
	local style = self.Style
	local current = self.Current
	local rad = math.rad
	local turn = current.Turn

	-- Pelvis: lowered by the crouch, and always far enough for both feet to reach their gear
	local bodyYaw = CFrame.Angles(0, rad(style.StanceYaw) * self.StanceSign, 0)
	local leftTarget, rightTarget = self:FootTargets()
	local restLowerTorso = self.RootC0 * bodyYaw * self.RootC1:Inverse()
	local crouchDrop = self.LegLength * (1 - math.cos(rad(math.clamp(current.Crouch + current.Absorb, 0, 75))))
	local drop = math.max(
		crouchDrop,
		requiredDrop(self.Legs.Left, restLowerTorso, leftTarget),
		requiredDrop(self.Legs.Right, restLowerTorso, rightTarget)
	)
	local rootT = CFrame.new(0, -drop, 0) * bodyYaw
	joints.Root.Transform = rootT
	local lowerTorso = self.RootC0 * rootT * self.RootC1:Inverse()

	solveLeg(self.Legs.Left, lowerTorso, leftTarget)
	solveLeg(self.Legs.Right, lowerTorso, rightTarget)

	-- Upper body: forward lean, counter-rotation and angulation through turns
	local headYaw = -rad(style.HeadYaw) * self.StanceSign
	local torso = rad(current.Torso)
	local counterYaw = rad(turn * style.CounterRotation)
	local angulation = rad(turn * style.Angulation)
	joints.Waist.Transform = CFrame.Angles(0, counterYaw, 0) * CFrame.Angles(-torso, 0, angulation)
	joints.Neck.Transform = CFrame.Angles(0, headYaw - counterYaw, 0) * CFrame.Angles(torso * style.NeckCompensation, 0, 0)

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
