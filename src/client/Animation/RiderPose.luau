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

local Constants = require(ReplicatedStorage.Shared.Constants)
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

local EASED = { "Crouch", "Torso", "ArmForward", "Elbow", "ArmOut", "Wrist", "Turn", "Absorb", "Brake" }
-- Snowboard-only channels (stay at 0 for skis)
local BOARD_EASED = { "Edge", "Press", "Spin", "AirTilt", "Lift" }
local GRABS = { "Indy", "Melon", "Method" }

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

local function armData(joints, side: string)
	local shoulderC0, shoulderC1 = jointFrames(joints[side .. "Shoulder"])
	local elbowC0, elbowC1 = jointFrames(joints[side .. "Elbow"])
	local wristC0 = jointFrames(joints[side .. "Wrist"])
	return {
		Shoulder = joints[side .. "Shoulder"],
		Elbow = joints[side .. "Elbow"],
		Wrist = joints[side .. "Wrist"],
		ShoulderC0 = shoulderC0,
		Upper = (shoulderC1.Position - elbowC0.Position).Magnitude,
		Lower = (elbowC1.Position - wristC0.Position).Magnitude,
	}
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
	for _, key in BOARD_EASED do
		current[key] = 0
	end
	for _, key in GRABS do
		current[key] = 0
	end
	local rootC0, rootC1 = jointFrames(joints.Root)
	local waistC0, waistC1 = jointFrames(joints.Waist)
	local left, right = legData(joints, "Left"), legData(joints, "Right")
	local equipment = sport.Equipment

	return setmetatable({
		Joints = joints,
		Legs = { Left = left, Right = right },
		Arms = { [-1] = armData(joints, "Left"), [1] = armData(joints, "Right") },
		RootC0 = rootC0,
		RootC1 = rootC1,
		WaistC0 = waistC0,
		WaistC1 = waistC1,
		Character = character,
		IsBoard = equipment.Kind == "Board",
		BoardFlat = if equipment.Kind == "Board"
			then equipment.Length - 2 * equipment.KickLength * math.cos(math.rad(equipment.KickAngle))
			else 0,
		LegLength = left.Thigh + left.Shin,
		-- Height of a foot's centre (root space) when its sole is on the snow / binding
		FootCenterY = -CharacterUtil.GetFootOffset(character) + footPart.Size.Y / 2,
		RestFootZ = (leftFoot.Position.Z + rightFoot.Position.Z) / 2,
		Equipment = equipment,
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
		Air = false,
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
	-- Snowboard touchdown: knees absorb (other players' riders have no local Landed event)
	if style.Board and self.WasAir and not input.Air then
		self.LandingCrouch = math.max(self.LandingCrouch, PoseConfig.DefaultLandingCrouch)
	end
	self.Air = input.Air
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

	-- Snowboard: toe/heel carve depth grows with speed; presses and grabs
	local board = style.Board
	local edge, press, grabTargets = 0, 0, { Indy = 0, Melon = 0, Method = 0 }
	if board then
		local depth = math.clamp((input.Speed or 0) / board.CarveFullSpeed, board.CarveMinDepth, 1)
		-- Regular riders face right of travel, so a right turn is on the toe edge
		edge = if input.Air then 0 else steer * -self.StanceSign * depth
		-- Braking is a hard heel-side skid
		if input.Brake and not input.Air then
			edge = math.clamp(edge - board.BrakeEdge, -1, 1)
		end
		press = if input.Air then 0 else math.clamp(input.Press or 0, -1, 1)
		local grab = if input.Air then GRABS[input.Grab or 0] else nil
		if grab then
			grabTargets[grab] = 1
		end
		crouch += math.max(edge, 0) * board.ToeCrouch + math.max(-edge, 0) * board.HeelCrouch + math.abs(press) * board.PressCrouch
		if grab then
			crouch += board.GrabCrouch
		end
	end
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
		Brake = if input.Brake and not input.Air then 1 else 0,
		Edge = edge,
		Press = press,
		Spin = if input.Air then input.Spin or 0 else 0,
		AirTilt = if input.Air then steer else 0,
		Lift = if input.Air then 1 else 0,
		Indy = grabTargets.Indy,
		Melon = grabTargets.Melon,
		Method = grabTargets.Method,
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
	if board then
		for _, key in BOARD_EASED do
			current[key] += (targets[key] - current[key]) * alpha
		end
		local grabAlpha = 1 - math.exp(-board.GrabResponsiveness * dt)
		for _, key in GRABS do
			current[key] += (targets[key] - current[key]) * grabAlpha
		end
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
	local style = self.Style
	local z = self.RestFootZ
	local shift = -self.Current.Turn * style.CarveShift
	local slope = math.tan(self.Lean)
	-- Snowplow when braking: feet wider, tips turned in
	local brake = self.Current.Brake
	local half = equipment.Spacing / 2 + brake * style.SnowplowWiden
	local toeIn = math.rad(style.SnowplowAngle) * brake
	local leftX, rightX = -half + shift, half + shift
	return CFrame.new(leftX, y - leftX * slope, z) * CFrame.Angles(0, -toeIn, 0),
		CFrame.new(rightX, y - rightX * slope, z) * CFrame.Angles(0, toeIn, 0)
end

--[[
	Two-bone IK. pivot is the first joint's frame (before its Transform); target is where the
	end joint's pivot must be, in the same space as pivot. Returns the Transforms for the first
	and middle joints. bendSign 1 bends like a knee (thigh forward, shin back); -1 bends like an
	elbow (upper arm back, forearm forward).
]]
local function solveTwoBone(pivot: CFrame, target: Vector3, upper: number, lower: number, bendSign: number): (CFrame, CFrame)
	local toEnd = pivot:PointToObjectSpace(target)
	local reach = math.clamp(toEnd.Magnitude, math.abs(upper - lower) + 1e-3, (upper + lower) * MAX_REACH)

	-- Aim the limb's rest axis (-Y) at the target, keeping the bend in the forward/back plane
	local up = -toEnd.Unit
	local back = Vector3.zAxis - up * up.Z
	if back.Magnitude < 1e-3 then
		back = Vector3.xAxis:Cross(up)
	end
	back = back.Unit
	local aim = CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back)

	-- Law of cosines
	local firstAngle = math.acos(math.clamp((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1))
	local middleInner = math.acos(math.clamp((upper * upper + lower * lower - reach * reach) / (2 * upper * lower), -1, 1))
	return aim * CFrame.Angles(bendSign * firstAngle, 0, 0), CFrame.Angles(-bendSign * (math.pi - middleInner), 0, 0)
end

-- Puts this leg's foot exactly at footTarget (root space), flat in its binding.
local function solveLeg(leg, lowerTorso: CFrame, footTarget: CFrame)
	local hipPivot = lowerTorso * leg.HipC0
	local hipT, kneeT = solveTwoBone(hipPivot, (footTarget * leg.AnkleC1).Position, leg.Thigh, leg.Shin, 1)

	-- Ankle: turn the foot to the target orientation
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
	if self.IsBoard then
		self:ApplyBoard()
		return
	end
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
		local forward = rad(current.ArmForward + style.PlantForward * plantAmount + style.CarveArmForward * inside + style.BrakeArmForward * current.Brake)
		local out = armOut + rad(style.CarveArmOut * outside + style.BrakeArmOut * current.Brake)
		shoulder.Transform = CFrame.Angles(0, 0, side * out) * CFrame.Angles(forward, 0, 0)
		elbowJoint.Transform = CFrame.Angles(elbow, 0, 0)
		wrist.Transform = CFrame.Angles(rad(current.Wrist + style.PlantWrist * plantAmount), 0, 0)
	end
	arm(joints.LeftShoulder, joints.LeftElbow, joints.LeftWrist, -1, leftPlant)
	arm(joints.RightShoulder, joints.RightElbow, joints.RightWrist, 1, rightPlant)
end

-- The board's joint on the root (EquipmentService), re-found when the gear is rebuilt.
function RiderPose:BoardJoint(): Motor6D?
	local joint = self.BoardJointCache
	if joint and joint.Parent then
		return joint
	end
	local equipment = self.Character:FindFirstChild(Constants.EquipmentModelName)
	local board = equipment and equipment:FindFirstChild("Board")
	joint = board and board:FindFirstChild("BoardJoint") :: Motor6D?
	self.BoardJointCache = joint
	return joint
end

--[[
	Snowboard pose. The board can move on its joint (presses, butters, air tweaks, grabs) and
	the feet are solved onto its bindings wherever it goes. Toe-side carves drive the hips and
	knees over the toes with the chest folded forward; heel-side carves sit low and back with
	the shoulders open down the hill and the rear hand sweeping toward the snow. In the air the
	board comes up to the rider, the upper body leads spins, and grabs reach the hand to the
	board edge with arm IK.
]]
function RiderPose:ApplyBoard()
	local joints = self.Joints
	local style = self.Style
	local cfg = style.Board
	local current = self.Current
	local spec = self.Equipment
	local rad = math.rad
	local t = self.Clock
	local stance = self.StanceSign
	local toeSign = -stance -- regular faces +X: toes toward +X, nose on the body's left
	local edge = current.Edge
	local toe, heel = math.max(edge, 0), math.max(-edge, 0)
	local press = current.Press
	local indy, melon, method = current.Indy, current.Melon, current.Method
	local grab = math.min(indy + melon + method, 1)
	local idle = if self.Air then 0 else 1

	-- Board tweak (board space). Presses pivot on the end that stays on the snow and butter
	-- with steering; in the air the board rises to the body and tilts with steering and grabs.
	local half = self.BoardFlat / 2
	local pivot = CFrame.new(0, -spec.Thickness / 2, if press >= 0 then -half else half)
	local butter = rad(cfg.ButterYaw) * -current.Turn * math.abs(press)
	local pressRot = pivot * CFrame.Angles(0, butter, 0) * CFrame.Angles(-rad(cfg.PressAngle) * press, 0, 0) * pivot:Inverse()
	local roll = toeSign * rad(cfg.IndyTilt * indy - cfg.MelonTilt * melon - cfg.MethodTilt * method)
		- rad(cfg.AirTilt) * current.AirTilt
	local lift = cfg.AirLift * current.Lift + cfg.GrabLift * grab
	local skid = CFrame.Angles(0, toeSign * rad(cfg.SkidYaw) * current.Brake, 0)
	local tweak = skid
		* CFrame.new(0, lift, 0)
		* CFrame.Angles(rad(cfg.MethodPitch) * method, 0, 0)
		* CFrame.Angles(0, 0, roll)
		* pressRot

	local boardJoint = self:BoardJoint()
	local boardC0 = if boardJoint then boardJoint.C0 else CFrame.identity
	if boardJoint then
		boardJoint.Transform = tweak
	else
		tweak = CFrame.identity
	end
	local boardFrame = boardC0 * tweak

	-- Feet: across the board in the bindings, wherever the board is
	local bodyYaw = CFrame.Angles(0, rad(style.StanceYaw) * stance, 0)
	local leftZ = stance * spec.BindingSpacing / 2
	local function onBoard(rest: CFrame): CFrame
		return boardFrame * (boardC0:Inverse() * rest)
	end
	local leftTarget = onBoard(CFrame.new(0, self.FootCenterY, leftZ) * bodyYaw)
	local rightTarget = onBoard(CFrame.new(0, self.FootCenterY, -leftZ) * bodyYaw)

	-- Pelvis: over the toes or back over the heels, toward a pressed end, with a slow sway
	local toeDir = bodyYaw.LookVector
	local shift = toeDir * (toe * cfg.ToeHipShift - heel * cfg.HeelHipShift + idle * 0.04 * math.sin(t * 1.3))
		+ Vector3.new(0, 0, -press * cfg.PressHipShift)
	local planar = CFrame.new(shift.X, 0, shift.Z)
	local restLowerTorso = self.RootC0 * planar * bodyYaw * self.RootC1:Inverse()
	local knees = current.Crouch + current.Absorb + idle * cfg.IdleKnee * (math.sin(t * 1.8) + 0.5 * math.sin(t * 2.9 + 1))
	local crouchDrop = self.LegLength * (1 - math.cos(rad(math.clamp(knees, 0, 75))))
	local drop = math.max(
		crouchDrop,
		requiredDrop(self.Legs.Left, restLowerTorso, leftTarget),
		requiredDrop(self.Legs.Right, restLowerTorso, rightTarget)
	)
	local rootT = CFrame.new(shift.X, -drop, shift.Z) * bodyYaw
	joints.Root.Transform = rootT
	local lowerTorso = self.RootC0 * rootT * self.RootC1:Inverse()
	solveLeg(self.Legs.Left, lowerTorso, leftTarget)
	solveLeg(self.Legs.Right, lowerTorso, rightTarget)

	-- Upper body: shoulders toward the nose (more on heel-side), the chest leads spins
	local spinLead = math.clamp(current.Spin * cfg.SpinLead, -cfg.MaxSpinLead, cfg.MaxSpinLead)
	local open = cfg.ShoulderOpen + toe * cfg.ToeShoulderOpen + heel * cfg.HeelShoulderOpen
	local waistYaw = rad(open) * toeSign + rad(spinLead)
	local torsoPitch = rad(math.min(current.Torso + toe * cfg.ToeTorso + heel * cfg.HeelTorso + grab * cfg.GrabTorso, cfg.MaxTorso))
	local sway = rad(cfg.IdleSway * idle * math.sin(t * 1.3))
	local waistT = CFrame.Angles(0, waistYaw, 0) * CFrame.Angles(-torsoPitch, 0, sway)
	joints.Waist.Transform = waistT
	-- Head keeps looking along the travel direction, spotting ahead in spins
	local headYaw = -rad(style.HeadYaw) * stance - waistYaw + rad(spinLead) * 0.5
	joints.Neck.Transform = CFrame.Angles(0, headYaw, 0) * CFrame.Angles(torsoPitch * style.NeckCompensation, 0, 0)

	-- Arms: balance poses for each edge, tucked in fast spins, then grabs blend in with IK
	local frontSide = if stance < 0 then -1 else 1 -- regular leads with the left
	local spinTuck = math.min(math.abs(current.Spin) / 8, 1)
	local upperTorso = lowerTorso * self.WaistC0 * waistT * self.WaistC1:Inverse()
	local grabZ = spec.BindingSpacing * 0.15
	for _, side in { -1, 1 } do
		local arm = self.Arms[side]
		local isFront = side == frontSide
		local forward = current.ArmForward + idle * cfg.IdleArm * math.sin(t * 1.1 + side) + toe * cfg.ToeArmForward + spinTuck * 10
		local out = current.ArmOut - spinTuck * cfg.SpinArmTuck + math.abs(press) * 12
		local elbow = current.Elbow + spinTuck * 15
		if isFront then
			out += heel * cfg.HeelFrontArmOut + indy * 25
		else
			forward -= heel * cfg.HeelRearArmBack
			out += melon * 30 + method * 40
			forward -= method * 30
		end
		local shoulderT = CFrame.Angles(0, 0, side * rad(out)) * CFrame.Angles(rad(forward), 0, 0)
		local elbowT = CFrame.Angles(rad(elbow), 0, 0)
		local wristT = CFrame.Angles(rad(current.Wrist), 0, 0)

		-- Deep heel-side carve: the rear hand reaches back to the snow beside the heel edge
		local drag = if isFront or self.Air then 0 else math.max(heel - 0.5, 0) * 2 * cfg.HeelHandDrag
		if drag > 0.01 then
			local snow = (boardFrame * CFrame.new(-toeSign * (spec.Width / 2 + 0.5), -spec.Thickness / 2 + 0.15, grabZ * 3)).Position
			local shoulderPivot = upperTorso * arm.ShoulderC0
			local dragShoulder, dragElbow = solveTwoBone(shoulderPivot, snow + (shoulderPivot.Position - snow).Unit * 0.3, arm.Upper, arm.Lower, -1)
			shoulderT = shoulderT:Lerp(dragShoulder, drag)
			elbowT = elbowT:Lerp(dragElbow, drag)
		end

		-- Grab: indy is the rear hand on the toe edge; melon and method the front hand on the heel edge
		local weight = if isFront then melon + method else indy
		if weight > 0.01 then
			local edgeX = (if isFront then -toeSign else toeSign) * spec.Width / 2
			local grip = (boardFrame * CFrame.new(edgeX, spec.Thickness / 2 + 0.1, if isFront then -grabZ else grabZ)).Position
			local shoulderPivot = upperTorso * arm.ShoulderC0
			local wristTarget = grip + (shoulderPivot.Position - grip).Unit * 0.3
			local grabShoulder, grabElbow = solveTwoBone(shoulderPivot, wristTarget, arm.Upper, arm.Lower, -1)
			weight = math.min(weight, 1)
			shoulderT = shoulderT:Lerp(grabShoulder, weight)
			elbowT = elbowT:Lerp(grabElbow, weight)
			wristT = wristT:Lerp(CFrame.identity, weight)
		end
		arm.Shoulder.Transform = shoulderT
		arm.Elbow.Transform = elbowT
		arm.Wrist.Transform = wristT
	end
end

-- Returns the character to its default pose (when riding stops).
function RiderPose:Reset()
	for _, joint in self.Joints do
		if joint.Parent then
			joint.Transform = CFrame.identity
		end
	end
	local boardJoint = self.BoardJointCache
	if boardJoint and boardJoint.Parent then
		boardJoint.Transform = CFrame.identity
	end
end

return RiderPose
