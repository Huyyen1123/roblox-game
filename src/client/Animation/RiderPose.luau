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
		Grab: number,          -- 0 none, 1..4 (in the air)
		Flip: number,          -- -1..1, how fast the rider is flipping (tucks the body)
	}

	Grabs: each sport has four (board: indy, melon, method, tail; skis: safety, mute, japan,
	tail). The hand is solved onto the gear with arm IK; for skis the knees pull the skis up
	to the hand (the skis are welded to the feet, so moving the feet moves the skis).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
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
local BOARD_EASED = { "Edge", "Tweak", "Spin", "AirTilt", "Lift" }
-- Channels that only exist in the air: snapped back on the snow so the board never floats
local AIR_ONLY = { Tweak = true, AirTilt = true, Lift = true }
-- Grab channels per sport, in Grab1..Grab4 order
local BOARD_GRABS = { "Indy", "Melon", "Method", "Tail" }
local SKI_GRABS = { "Safety", "Mute", "Japan", "Tail" }
-- How fast grabs let go just before touchdown and on the snow
local GRAB_RELEASE_RESPONSIVENESS = 40

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
	local equipmentSpec = sport.Equipment
	local grabChannels = if equipmentSpec.Kind == "Board" then BOARD_GRABS else SKI_GRABS
	for _, key in grabChannels do
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
		GrabChannels = grabChannels,
		-- Ski centre relative to its foot's centre (the ski is welded to the foot)
		SkiOffset = if equipment.Kind == "Board"
			then CFrame.identity
			else CFrame.new(
				0,
				-footPart.Size.Y / 2 - MovementConfig.EquipmentThickness + equipment.Thickness / 2,
				-equipment.MountOffset
			),
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
		Switch = false,
		Root = character:FindFirstChild("HumanoidRootPart"),
		-- Head look (see UpdateLook): world yaw being looked at, and the eased neck/shoulder turn
		LookYaw = nil,
		NeckYaw = 0,
		ShoulderYaw = 0,
		LookSide = 1,
		-- Landing reactions: hard-landing fold (1 → 0) and the stumble stagger
		Hard = 0,
		Dig = 0, -- 0..1, how far the gear has settled into powder
		StumbleTime = 0,
		StumbleAmount = 0,
		StumbleSide = 1,
	}, RiderPose)
end

-- Touchdown: knees absorb by impact; a hard landing also folds the chest and throws the arms
-- out. (Stumbles come through the riding state, for this rider and others alike.)
function RiderPose:OnLanded(impact: number, quality: string?)
	local landing = PoseConfig.Landing
	self.LandingCrouch = math.max(self.LandingCrouch, math.min(impact * landing.CompressionPerImpact, landing.MaxCompression))
	if quality == "Hard" then
		self.Hard = 1
	end
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
	local landing = PoseConfig.Landing
	-- Settle into powder on the snow; lift out quickly on takeoff
	local digTarget = if input.Powder then 1 else 0
	local digRate = if digTarget > self.Dig then PoseConfig.Dig.InRate else PoseConfig.Dig.OutRate
	self.Dig += (digTarget - self.Dig) * (1 - math.exp(-digRate * dt))
	self.LandingCrouch *= math.exp(-landing.Recovery * dt)
	self.Hard *= math.exp(-landing.HardRecovery * dt)
	-- Stumble stagger: starts strong and settles; eases away once the stumble is over
	if input.Stumble then
		if self.StumbleAmount < 0.05 then
			self.StumbleTime = 0
			self.StumbleSide = if (input.StumbleSide or 1) >= 0 then 1 else -1
		end
		self.StumbleTime += dt
		self.StumbleAmount = math.exp(-landing.StumbleDecay * self.StumbleTime)
	else
		self.StumbleAmount *= math.exp(-6 * dt)
	end
	self:DetectPolePlant(steer, input.Air)
	-- In the air the skis stay level with the body; on the snow they follow the lean
	local leanTarget = if input.Air then 0 else math.clamp(input.Lean or 0, -MAX_LEAN, MAX_LEAN)
	self.Lean += (leanTarget - self.Lean) * (1 - math.exp(-PoseConfig.Responsiveness * dt))

	-- Takeoff from a charged jump: the legs pop straight and the arms throw forward
	if input.Air and not self.WasAir and self.LastCharge > 0.05 then
		self.PopTime = 0
	end
	self.Air = input.Air
	self.Switch = input.Switch == true
	self:UpdateLook(dt, input)
	self.WasAir = input.Air
	self.LastCharge = charge
	local popping = self.PopTime < PoseConfig.PopDuration

	-- Targets
	local crouch = lerp(style.Crouch, style.TuckCrouch, tuck)
	if input.Brake then
		crouch = math.max(crouch, style.BrakeCrouch)
	end
	-- Just before touchdown the legs reach down to meet the snow (and the board levels out)
	local landingPrep = 0
	if input.Air then
		landingPrep = math.clamp(1 - (input.TimeToLand or math.huge) / landing.PrepTime, 0, 1)
		crouch = math.max(crouch, lerp(style.AirCrouch, landing.ReachCrouch, landingPrep))
	end
	crouch += style.ChargeCrouch * charge + self.LandingCrouch + landing.StumbleCrouch * self.StumbleAmount

	-- Grabs (both sports): held in the air, released just before touchdown
	local grabTargets = {}
	for _, key in self.GrabChannels do
		grabTargets[key] = 0
	end
	local grab = if input.Air and landingPrep < 0.5 then self.GrabChannels[input.Grab or 0] else nil
	if grab then
		grabTargets[grab] = 1
	end
	-- Flips: tuck tight while rotating
	local flip = if input.Air then math.min(math.abs(input.Flip or 0), 1) else 0
	crouch += PoseConfig.Flip.Crouch * flip

	-- Snowboard: toe/heel carve depth grows with speed; tweaks in the air
	local board = style.Board
	local edge, tweak = 0, 0
	if board then
		local depth = math.clamp((input.Speed or 0) / board.CarveFullSpeed, board.CarveMinDepth, 1)
		-- Regular riders face right of travel, so a right turn is on the toe edge
		edge = if input.Air then 0 else steer * -self.StanceSign * depth
		-- Braking is a hard heel-side skid
		if input.Brake and not input.Air then
			edge = math.clamp(edge - board.BrakeEdge, -1, 1)
		end
		tweak = if input.Air then math.clamp(input.Tweak or 0, -1, 1) else 0
		-- Just before touchdown the board levels out
		tweak *= 1 - landingPrep
		crouch += math.max(edge, 0) * board.ToeCrouch + math.max(-edge, 0) * board.HeelCrouch + math.abs(tweak) * board.TweakCrouch
		if grab then
			crouch += board.GrabCrouch
		end
	elseif grab then
		crouch += style.Grabs.Crouch
	end
	if popping then
		crouch = style.PopCrouch
	end

	local armOut = style.ArmOut + (if input.Switch then style.SwitchArmOut else 0) + landing.HardArmOut * self.Hard
		- PoseConfig.Flip.ArmIn * flip

	local absorb = 0
	if not input.Air then
		absorb = math.clamp((input.VerticalAccel or 0) * PoseConfig.AbsorbPerAccel, -PoseConfig.MaxAbsorb, PoseConfig.MaxAbsorb)
	end

	local targets = {
		Crouch = math.min(crouch, 70),
		Torso = lerp(style.TorsoPitch * (if input.Switch then style.SwitchTorsoScale else 1), style.TuckTorsoPitch, tuck)
			+ style.ChargeTorso * charge
			+ landing.HardFold * self.Hard
			+ PoseConfig.Flip.Torso * flip
			+ (if grab and not board then style.Grabs.Torso else 0),
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
		Tweak = tweak,
		Spin = if input.Air then input.Spin or 0 else 0,
		AirTilt = if input.Air then steer * (1 - landingPrep) else 0,
		Lift = if input.Air then 1 - landingPrep else 0,
	}
	for key, value in grabTargets do
		targets[key] = value
	end

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
		local snapAlpha = 1 - math.exp(-board.GroundSnapResponsiveness * dt)
		for _, key in BOARD_EASED do
			local rate = if AIR_ONLY[key] and (not input.Air or landingPrep > 0) then snapAlpha else alpha
			current[key] += (targets[key] - current[key]) * rate
		end
	end
	local grabRate = if input.Air and landingPrep <= 0
		then (if board then board.GrabResponsiveness else style.Grabs.Responsiveness)
		else GRAB_RELEASE_RESPONSIVENESS
	local grabAlpha = 1 - math.exp(-grabRate * dt)
	for _, key in self.GrabChannels do
		current[key] += (targets[key] - current[key]) * grabAlpha
	end

	self:Apply()
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Flat yaw of a direction (0 = -Z, positive = toward -X), matching CFrame.Angles(0, yaw, 0).
local function yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

--[[
	Where the rider looks, in the world: along the direction of travel, turned into the turn
	ahead of the body. In the air the travel direction is where the rider will land, so the
	head spots the landing through spins. Eased in world space, so it stays steady while the
	body rotates under it.
]]
function RiderPose:UpdateLook(dt: number, input)
	local root = self.Root
	if not root then
		return
	end
	local look = PoseConfig.Look
	local rootYaw = yawOf(root.CFrame.LookVector)
	local travel = input.Travel or Vector3.zero
	local flat = Vector3.new(travel.X, 0, travel.Z)
	local target
	if flat.Magnitude > look.MinSpeed then
		target = yawOf(flat)
	else
		-- Stopped: look where the gear points (backwards from the body when riding switch)
		target = rootYaw + (if self.Switch then math.pi else 0)
	end
	-- Lead into the turn: Turn is body-relative (positive = to the body's right = negative yaw)
	if not input.Air then
		target -= math.rad(look.TurnLead) * self.Current.Turn
	end
	if not self.LookYaw then
		self.LookYaw = target
	end
	self.LookYaw += wrapAngle(target - self.LookYaw) * (1 - math.exp(-look.Responsiveness * dt))
	self.LookDt = dt
end

-- Neck and extra shoulder turn (radians) to look at LookYaw from a torso facing torsoYaw
-- (root space). Clamped to believable limits and eased, with hysteresis on the shoulder used
-- when the target is nearly straight behind.
function RiderPose:LookTurn(torsoYaw: number): (number, number)
	local look = PoseConfig.Look
	local root = self.Root
	if not root or not self.LookYaw then
		return 0, 0
	end
	local relative = wrapAngle(self.LookYaw - yawOf(root.CFrame.LookVector) - torsoYaw)
	if math.abs(relative) > math.rad(look.SideHysteresis) and math.sign(relative) ~= self.LookSide then
		relative = self.LookSide * math.rad(look.SideHysteresis)
	elseif math.abs(relative) > 0.05 then
		self.LookSide = math.sign(relative)
	end
	local neckLimit, shoulderLimit = math.rad(look.NeckLimit), math.rad(look.ShoulderLimit)
	local beyond = relative - math.clamp(relative, -neckLimit, neckLimit)
	local shoulders = math.clamp(beyond, -shoulderLimit, shoulderLimit)
	local neck = math.clamp(relative - shoulders, -neckLimit, neckLimit)
	local alpha = 1 - math.exp(-look.NeckResponsiveness * (self.LookDt or 1 / 60))
	self.NeckYaw += (neck - self.NeckYaw) * alpha
	self.ShoulderYaw += (shoulders - self.ShoulderYaw) * alpha
	return self.NeckYaw, self.ShoulderYaw
end

--[[
	Stumble stagger, in the body's frame: the pelvis buckles toward StumbleSide (its knee
	gives), the torso lurches the same way, and the arm on the far side windmills for
	balance. Returns pelvis roll and torso roll (radians, Z rotation) and, per arm side, extra
	forward and outward swing (degrees).
]]
function RiderPose:Stagger(): (number, number, { [number]: { number } })
	local landing = PoseConfig.Landing
	local amount = self.StumbleAmount
	if amount < 0.01 then
		return 0, 0, { [-1] = { 0, 0 }, [1] = { 0, 0 } }
	end
	local side = self.StumbleSide
	-- Z rotation toward +X (the body's right) is negative
	local pelvis = -side * math.rad(landing.StumbleBuckle) * amount
	local torso = -side * math.rad(landing.StumbleLurch) * amount
	local swing = landing.StumbleArm * amount
	local phase = self.StumbleTime * landing.StumbleArmRate
	local arms = {
		[side] = { -swing * 0.2, swing * 0.15 }, -- near arm braces down and out
		[-side] = { swing * (0.6 + 0.4 * math.sin(phase)), swing * 0.5 }, -- far arm windmills
	}
	return pelvis, torso, arms
end

-- How far the gear sits down into powder, and its nose-up pitch (radians). The nose is the
-- end facing the travel direction, which is behind the body when riding switch.
function RiderPose:DigOffset(kind: string): (number, number)
	local dig = PoseConfig.Dig[kind]
	local amount = self.Dig
	local pitch = math.rad(dig.Pitch) * amount * (if self.Switch then -1 else 1)
	return dig.Depth * amount, pitch
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
	-- Dug into powder: lower, tail down (Rx > 0 lowers +Z, the tail)
	local depth, pitch = self:DigOffset("Ski")
	local dig = CFrame.Angles(pitch, 0, 0)
	return CFrame.new(leftX, y - depth - leftX * slope, z) * CFrame.Angles(0, -toeIn, 0) * dig,
		CFrame.new(rightX, y - depth - rightX * slope, z) * CFrame.Angles(0, toeIn, 0) * dig
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
	local stagger, lurch, staggerArms = self:Stagger()
	local buckle = CFrame.Angles(0, 0, stagger)
	local leftTarget, rightTarget = self:FootTargets()

	-- Grabs: the knees pull the skis up toward the body and tip them (the skis are welded to
	-- the feet, so they follow); the strongest grab decides which hand reaches which ski
	local grabs = style.Grabs
	local grabTotal, grabIndex, grabWeight = 0, nil, 0
	local grabPitch, grabCross = 0, 0
	for i, key in self.GrabChannels do
		local weight = current[key]
		grabTotal += weight
		grabPitch += rad(grabs[i].Pitch) * weight
		grabCross += grabs[i].Cross * weight
		if weight > grabWeight then
			grabIndex, grabWeight = i, weight
		end
	end
	grabTotal = math.min(grabTotal, 1)
	if grabTotal > 0.01 then
		local lift = CFrame.new(0, grabs.Lift * grabTotal, grabs.Back * grabTotal)
		local tip = CFrame.Angles(grabPitch, 0, 0)
		leftTarget = lift * CFrame.new(grabCross, 0, 0) * leftTarget * tip
		rightTarget = lift * CFrame.new(-grabCross, 0, 0) * rightTarget * tip
	end
	local restLowerTorso = self.RootC0 * bodyYaw * buckle * self.RootC1:Inverse()
	local crouchDrop = self.LegLength * (1 - math.cos(rad(math.clamp(current.Crouch + current.Absorb, 0, 75))))
	local drop = math.max(
		crouchDrop,
		requiredDrop(self.Legs.Left, restLowerTorso, leftTarget),
		requiredDrop(self.Legs.Right, restLowerTorso, rightTarget)
	)
	local rootT = CFrame.new(0, -drop, 0) * bodyYaw * buckle
	joints.Root.Transform = rootT
	local lowerTorso = self.RootC0 * rootT * self.RootC1:Inverse()

	solveLeg(self.Legs.Left, lowerTorso, leftTarget)
	solveLeg(self.Legs.Right, lowerTorso, rightTarget)

	-- Upper body: forward lean, counter-rotation and angulation through turns; the head looks
	-- along the direction of travel (over a shoulder when riding switch, which also twists the
	-- shoulders toward that side)
	local torso = rad(current.Torso)
	local counterYaw = rad(turn * style.CounterRotation)
	local angulation = rad(turn * style.Angulation)
	local neckYaw, shoulderYaw = self:LookTurn(counterYaw)
	-- (the torso straightens against the pelvis buckle, then lurches toward the stumble)
	local waistT = CFrame.Angles(0, counterYaw + shoulderYaw, 0) * CFrame.Angles(-torso, 0, angulation - stagger + lurch)
	joints.Waist.Transform = waistT
	joints.Neck.Transform = CFrame.Angles(0, neckYaw, 0) * CFrame.Angles(torso * style.NeckCompensation, 0, 0)

	-- Grab: where the grabbing hand goes (root space), on the ski's top edge
	local grabHand, grabPoint = nil, nil
	if grabIndex and grabWeight > 0.01 then
		local spec = grabs[grabIndex]
		local equipment = self.Equipment
		local skiFrame = (if spec.Ski > 0 then rightTarget else leftTarget) * self.SkiOffset
		local z = if spec.Z == "Tail" then equipment.Length / 2 - 0.5 else spec.Z
		grabHand = spec.Hand
		grabPoint = (skiFrame * CFrame.new(spec.Ski * equipment.Width / 2, equipment.Thickness / 2 + 0.1, z)).Position
	end
	local upperTorso = lowerTorso * self.WaistC0 * waistT * self.WaistC1:Inverse()

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
		local extra = staggerArms[side]
		local forward = rad(current.ArmForward + style.PlantForward * plantAmount + style.CarveArmForward * inside + style.BrakeArmForward * current.Brake + extra[1])
		local out = armOut + rad(style.CarveArmOut * outside + style.BrakeArmOut * current.Brake + extra[2])
		local shoulderT = CFrame.Angles(0, 0, side * out) * CFrame.Angles(forward, 0, 0)
		local elbowT = CFrame.Angles(elbow, 0, 0)
		local wristT = CFrame.Angles(rad(current.Wrist + style.PlantWrist * plantAmount), 0, 0)
		if grabHand == side and grabPoint then
			-- Reach the hand to the ski (two-bone IK, elbow bending back)
			local data = self.Arms[side]
			local shoulderPivot = upperTorso * data.ShoulderC0
			local wristTarget = grabPoint + (shoulderPivot.Position - grabPoint).Unit * 0.3
			local grabShoulder, grabElbow = solveTwoBone(shoulderPivot, wristTarget, data.Upper, data.Lower, -1)
			local weight = math.min(grabWeight, 1)
			shoulderT = shoulderT:Lerp(grabShoulder, weight)
			elbowT = elbowT:Lerp(grabElbow, weight)
			wristT = wristT:Lerp(CFrame.identity, weight)
		end
		shoulder.Transform = shoulderT
		elbowJoint.Transform = elbowT
		wrist.Transform = wristT
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
	Snowboard pose. The board can move on its joint (braking skid, and in the air: lift, tilt,
	tweaks, grabs) and
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
	local tweak = current.Tweak
	local indy, melon, method, tailGrab = current.Indy, current.Melon, current.Method, current.Tail
	local grab = math.min(indy + melon + method + tailGrab, 1)
	local idle = if self.Air then 0 else 1

	-- Board tweak (board space). On the snow the board stays flat on its base (it only edges
	-- with the body lean and skids when braking); in the air it rises to the body, tilts with
	-- steering and grabs, and W/S tweak the nose or tail up.
	local roll = toeSign * rad(cfg.IndyTilt * indy - cfg.MelonTilt * melon - cfg.MethodTilt * method)
		- rad(cfg.AirTilt) * current.AirTilt
	local lift = cfg.AirLift * current.Lift + cfg.GrabLift * grab
	local skid = CFrame.Angles(0, toeSign * rad(cfg.SkidYaw) * current.Brake, 0)
	-- Dug into powder: the board sits lower, nose up and tail down (Rx > 0 lowers +Z, the tail)
	local digDepth, digPitch = self:DigOffset("Board")
	local boardOffset = CFrame.new(0, -digDepth, 0) * CFrame.Angles(digPitch, 0, 0) * skid
		* CFrame.new(0, lift, 0)
		* CFrame.Angles(rad(cfg.MethodPitch) * method - rad(cfg.TailGrabPitch) * tailGrab, 0, 0)
		* CFrame.Angles(0, 0, roll)
		* CFrame.Angles(rad(cfg.TweakAngle) * tweak, 0, 0)

	local boardJoint = self:BoardJoint()
	local boardC0 = if boardJoint then boardJoint.C0 else CFrame.identity
	if boardJoint then
		boardJoint.Transform = boardOffset
	else
		boardOffset = CFrame.identity
	end
	local boardFrame = boardC0 * boardOffset

	-- Feet: across the board in the bindings, wherever the board is
	local bodyYaw = CFrame.Angles(0, rad(style.StanceYaw) * stance, 0)
	local leftZ = stance * spec.BindingSpacing / 2
	local function onBoard(rest: CFrame): CFrame
		return boardFrame * (boardC0:Inverse() * rest)
	end
	local leftTarget = onBoard(CFrame.new(0, self.FootCenterY, leftZ) * bodyYaw)
	local rightTarget = onBoard(CFrame.new(0, self.FootCenterY, -leftZ) * bodyYaw)

	-- Pelvis: over the toes or back over the heels, toward a tweaked end, with a slow sway
	local toeDir = bodyYaw.LookVector
	local shift = toeDir * (toe * cfg.ToeHipShift - heel * cfg.HeelHipShift + idle * 0.04 * math.sin(t * 1.3))
		+ Vector3.new(0, 0, -tweak * cfg.TweakHipShift)
	local planar = CFrame.new(shift.X, 0, shift.Z)
	local stagger, lurch, staggerArms = self:Stagger()
	local buckle = CFrame.Angles(0, 0, stagger)
	local restLowerTorso = self.RootC0 * planar * bodyYaw * buckle * self.RootC1:Inverse()
	local knees = current.Crouch + current.Absorb + idle * cfg.IdleKnee * (math.sin(t * 1.8) + 0.5 * math.sin(t * 2.9 + 1))
	local crouchDrop = self.LegLength * (1 - math.cos(rad(math.clamp(knees, 0, 75))))
	local drop = math.max(
		crouchDrop,
		requiredDrop(self.Legs.Left, restLowerTorso, leftTarget),
		requiredDrop(self.Legs.Right, restLowerTorso, rightTarget)
	)
	local rootT = CFrame.new(shift.X, -drop, shift.Z) * bodyYaw * buckle
	joints.Root.Transform = rootT
	local lowerTorso = self.RootC0 * rootT * self.RootC1:Inverse()
	solveLeg(self.Legs.Left, lowerTorso, leftTarget)
	solveLeg(self.Legs.Right, lowerTorso, rightTarget)

	-- Upper body: shoulders toward the nose (more on heel-side), the chest leads spins
	local spinLead = math.clamp(current.Spin * cfg.SpinLead, -cfg.MaxSpinLead, cfg.MaxSpinLead)
	-- Shoulders open toward the leading end: the nose, or the tail when riding switch
	local open = cfg.ShoulderOpen + toe * cfg.ToeShoulderOpen + heel * cfg.HeelShoulderOpen
	local leadEnd = if self.Switch then -1 else 1
	local baseYaw = rad(open) * toeSign * leadEnd + rad(spinLead)
	-- The head looks along the travel direction (spotting the landing in spins); the
	-- shoulders help when the neck alone can't reach
	local neckYaw, shoulderYaw = self:LookTurn(rad(style.StanceYaw) * stance + baseYaw)
	local waistYaw = baseYaw + shoulderYaw
	local torsoPitch = rad(math.min(current.Torso + toe * cfg.ToeTorso + heel * cfg.HeelTorso + grab * cfg.GrabTorso, cfg.MaxTorso))
	local sway = rad(cfg.IdleSway * idle * math.sin(t * 1.3))
	local waistT = CFrame.Angles(0, waistYaw, 0) * CFrame.Angles(-torsoPitch, 0, sway - stagger + lurch)
	joints.Waist.Transform = waistT
	joints.Neck.Transform = CFrame.Angles(0, neckYaw, 0) * CFrame.Angles(torsoPitch * style.NeckCompensation, 0, 0)

	-- Arms: balance poses for each edge, tucked in fast spins, then grabs blend in with IK
	local frontSide = if stance < 0 then -1 else 1 -- regular leads with the left
	local spinTuck = math.min(math.abs(current.Spin) / 8, 1)
	local upperTorso = lowerTorso * self.WaistC0 * waistT * self.WaistC1:Inverse()
	local grabZ = spec.BindingSpacing * 0.15
	for _, side in { -1, 1 } do
		local arm = self.Arms[side]
		local isFront = side == frontSide
		local extra = staggerArms[side]
		local forward = current.ArmForward + idle * cfg.IdleArm * math.sin(t * 1.1 + side) + toe * cfg.ToeArmForward + spinTuck * 10 + extra[1]
		local out = current.ArmOut - spinTuck * cfg.SpinArmTuck + math.abs(tweak) * 12 + extra[2]
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

		-- Grab: indy is the rear hand on the toe edge; melon and method the front hand on the
		-- heel edge; tail grab the rear hand on the tail
		local weight = if isFront then melon + method else indy + tailGrab
		if weight > 0.01 then
			local edgeX = (if isFront then -toeSign else toeSign) * spec.Width / 2
			local gripZ = if isFront then -grabZ else grabZ
			if not isFront and tailGrab > indy then
				-- The tail is the board's +Z end (the nose leads at -Z)
				edgeX = 0
				gripZ = self.BoardFlat / 2 * 0.9
			end
			local grip = (boardFrame * CFrame.new(edgeX, spec.Thickness / 2 + 0.1, gripZ)).Position
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
