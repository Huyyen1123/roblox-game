--[[
	FirstPersonCamera
	Eye-level view. Looks along the riding direction with partial slope pitch, a small roll into
	turns and a very light speed bob (kept subtle to avoid motion sickness). Free-look offsets
	from mouse/stick are clamped and drift back to centre. The rider's body is hidden locally;
	the equipment stays visible so you can see your skis or board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CameraMath = require(script.Parent.CameraMath)

local Config = CameraConfig.FirstPerson

local FirstPersonCamera = {}
FirstPersonCamera.__index = FirstPersonCamera
FirstPersonCamera.Fov = Config.Fov

function FirstPersonCamera.new()
	return setmetatable({
		LookDirection = Vector3.new(0, 0, -1),
		LookYaw = 0,
		LookPitch = 0,
		LookIdle = 0,
		Roll = 0,
		BobTime = 0,
	}, FirstPersonCamera)
end

local function setBodyHidden(character: Model?, hidden: boolean)
	if not character then
		return
	end
	local equipment = character:FindFirstChild(Constants.EquipmentModelName)
	local modifier = if hidden then 1 else 0
	for _, descendant in character:GetDescendants() do
		if (descendant:IsA("BasePart") or descendant:IsA("Decal")) and not (equipment and descendant:IsDescendantOf(equipment)) then
			descendant.LocalTransparencyModifier = modifier
		end
	end
end

function FirstPersonCamera:Enter(_camera: Camera, state)
	self.LookDirection = state.Forward
	self.LookYaw, self.LookPitch = 0, 0
end

function FirstPersonCamera:Exit(_camera: Camera, state)
	setBodyHidden(state.Character, false)
end

function FirstPersonCamera:Update(dt: number, camera: Camera, state, input)
	local root = state.Root
	if not root then
		return
	end
	setBodyHidden(state.Character, true)

	-- Free look
	if input.Look.Magnitude > 0 then
		local sensitivity = math.rad(Config.LookSensitivity)
		self.LookYaw = math.clamp(self.LookYaw - input.Look.X * sensitivity, -math.rad(Config.MaxLookYaw), math.rad(Config.MaxLookYaw))
		self.LookPitch = math.clamp(self.LookPitch - input.Look.Y * sensitivity, -math.rad(Config.MaxLookPitch), math.rad(Config.MaxLookPitch))
	end
	if input.Looking then
		self.LookIdle = 0
	else
		self.LookIdle += dt
		if self.LookIdle > Config.LookReturnDelay then
			local alpha = CameraMath.ExpAlpha(Config.LookReturnRate, dt)
			self.LookYaw += (0 - self.LookYaw) * alpha
			self.LookPitch += (0 - self.LookPitch) * alpha
		end
	end

	-- Base direction: along the slope, partly toward travel direction
	if state.Mode ~= "Wipeout" then
		local target = state.Forward
		if state.Speed > 10 then
			target = target:Lerp(state.Velocity.Unit, Config.VelocityBlend)
		end
		local flat = CameraMath.Flat(target) or CameraMath.Flat(self.LookDirection) or Vector3.new(0, 0, -1)
		local slopePitch = math.asin(math.clamp(target.Unit.Y, -1, 1)) * Config.SlopePitchFollow
		local pitched = (CFrame.lookAt(Vector3.zero, flat) * CFrame.Angles(slopePitch + math.rad(Config.ExtraPitch), 0, 0)).LookVector
		self.LookDirection = self.LookDirection:Lerp(pitched, CameraMath.ExpAlpha(Config.LookResponsiveness, dt)).Unit
	end

	local targetRoll = -math.rad(Config.RollFromSteer) * state.Steer * (if state.Grounded then 1 else 0)
	self.Roll += (targetRoll - self.Roll) * CameraMath.ExpAlpha(6, dt)

	-- Subtle bob while riding fast on the ground
	local bob = Vector3.zero
	if state.Grounded then
		self.BobTime += dt
		local amount = Config.BobAmplitude * math.clamp(state.Speed / Config.BobSpeedRef, 0, 1)
		bob = state.Up * math.sin(self.BobTime * Config.BobFrequency) * amount
	end

	local eye = root.Position + state.Up * Config.EyeHeight + CameraMath.Flat(self.LookDirection) * Config.ForwardOffset + bob
	local base = CFrame.lookAt(eye, eye + self.LookDirection)
	camera.CFrame = base * CFrame.Angles(0, self.LookYaw, 0) * CFrame.Angles(self.LookPitch, 0, 0) * CFrame.Angles(0, 0, self.Roll)
	camera.Focus = CFrame.new(eye)
end

return FirstPersonCamera
