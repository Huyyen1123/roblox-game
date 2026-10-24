--[[
	ThirdPersonCamera
	Chase camera. Yaw follows a blend of facing and travel direction with smoothing and leads
	slightly into turns, pitch tilts down on steep slopes, distance grows slightly with speed,
	and a spherecast keeps the camera out of terrain and trees. In the air the camera follows
	the travel direction only, so spins don't swing it around. Landings dip it briefly and very
	high speeds add a faint buzz. Mouse/stick orbiting is temporary and eases back behind the
	rider.

	The camera is positioned relative to the root's current position (no positional lag), so it
	never jitters or falls behind at high speed; only angles and distance are smoothed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local CameraMath = require(script.Parent.CameraMath)

local Config = CameraConfig.ThirdPerson

local ThirdPersonCamera = {}
ThirdPersonCamera.__index = ThirdPersonCamera
ThirdPersonCamera.Fov = Config.Fov

function ThirdPersonCamera.new()
	return setmetatable({
		Yaw = 0,
		Pitch = math.rad(Config.Pitch),
		OrbitYaw = 0,
		OrbitPitch = 0,
		OrbitIdle = 0,
		Distance = Config.Distance,
		TargetDistance = Config.Distance,
		CurrentDistance = Config.Distance,
		Lead = 0,
		Dip = 0,
		Clock = 0,
	}, ThirdPersonCamera)
end

function ThirdPersonCamera:OnLanded(impact: number)
	self.Dip = math.max(self.Dip, math.min(impact * Config.LandingDipPerImpact, Config.MaxLandingDip))
end

function ThirdPersonCamera:Enter(_camera: Camera, state)
	local facing = CameraMath.Flat(state.Heading) or Vector3.new(0, 0, -1)
	self.Yaw = CameraMath.YawFromDirection(facing)
	self.OrbitYaw, self.OrbitPitch = 0, 0
	self.CurrentDistance = self.TargetDistance
end

function ThirdPersonCamera:Exit(_camera: Camera, _state) end

function ThirdPersonCamera:Update(dt: number, camera: Camera, state, input)
	local root = state.Root
	if not root then
		return
	end

	-- Zoom
	if input.Zoom ~= 0 then
		self.TargetDistance = math.clamp(self.TargetDistance + input.Zoom * Config.ZoomStep, Config.MinDistance, Config.MaxDistance)
	end

	-- Orbit from look input, easing back to behind-the-rider when released
	if input.Look.Magnitude > 0 then
		local sensitivity = math.rad(Config.OrbitSensitivity)
		self.OrbitYaw -= input.Look.X * sensitivity
		self.OrbitPitch = math.clamp(self.OrbitPitch + input.Look.Y * sensitivity, -math.rad(Config.MaxOrbitPitch), math.rad(Config.MaxOrbitPitch))
	end
	if input.Looking then
		self.OrbitIdle = 0
	else
		self.OrbitIdle += dt
		if self.OrbitIdle > Config.OrbitReturnDelay then
			local alpha = CameraMath.ExpAlpha(Config.OrbitReturnRate, dt)
			self.OrbitYaw = CameraMath.LerpAngle(self.OrbitYaw, 0, alpha)
			self.OrbitPitch += (0 - self.OrbitPitch) * alpha
		end
	end

	-- Base yaw: facing blended toward travel direction once moving (travel only in the air)
	local leadTarget = 0
	if state.Mode ~= "Wipeout" then
		local facing = CameraMath.Flat(state.Heading)
		local travel = CameraMath.Flat(state.Velocity)
		local target = facing
		if travel and state.Speed > 8 then
			if not state.Grounded then
				target = travel
			elseif facing then
				target = CameraMath.Flat(facing:Lerp(travel, Config.VelocityBlend)) or facing
			end
		end
		if target then
			self.Yaw = CameraMath.LerpAngle(self.Yaw, CameraMath.YawFromDirection(target), CameraMath.ExpAlpha(Config.YawResponsiveness, dt))
		end
		if state.Grounded then
			leadTarget = -state.Steer * math.rad(Config.TurnLead) -- steer right (+) = yaw right (-)
		end
	end
	self.Lead += (leadTarget - self.Lead) * CameraMath.ExpAlpha(Config.TurnLeadResponsiveness, dt)

	-- Pitch down further on steep ground so the slope ahead stays in view
	local slopePitch = 0
	if state.Grounded then
		slopePitch = -math.asin(math.clamp(state.Forward.Y, -1, 1)) * Config.SlopePitchFollow
	end
	local targetPitch = math.rad(Config.Pitch) + slopePitch
	self.Pitch += (targetPitch - self.Pitch) * CameraMath.ExpAlpha(Config.PitchResponsiveness, dt)

	-- Distance with speed bonus
	local speedT = math.clamp(state.Speed / Config.SpeedForMaxBonus, 0, 1)
	local desiredDistance = self.TargetDistance + Config.SpeedDistanceBonus * speedT

	self.Dip *= math.exp(-Config.LandingDipRecovery * dt)
	local rotation = CFrame.Angles(0, self.Yaw + self.OrbitYaw + self.Lead, 0) * CFrame.Angles(-(self.Pitch + self.OrbitPitch), 0, 0)
	local focus = root.Position + Vector3.yAxis * (Config.FocusHeight - self.Dip)
	local direction = -rotation.LookVector

	-- Collision: pull in instantly, ease back out
	local allowed = desiredDistance
	local hit = Workspace:Spherecast(focus, Config.CollisionRadius, direction * desiredDistance, input.RaycastParams)
	if hit then
		allowed = math.max(hit.Distance - 0.2, 1.5)
	end
	if allowed < self.CurrentDistance then
		self.CurrentDistance = allowed
	else
		self.CurrentDistance += (allowed - self.CurrentDistance) * CameraMath.ExpAlpha(Config.DistanceResponsiveness, dt)
	end

	local position = focus + direction * self.CurrentDistance
	local cframe = CFrame.lookAt(position, focus)

	-- Faint high-speed buzz: smooth noise, ramping in above Buzz.StartSpeed
	local buzz = Config.Buzz
	local buzzT = math.clamp((state.Speed - buzz.StartSpeed) / (buzz.FullSpeed - buzz.StartSpeed), 0, 1)
	if buzzT > 0 and state.Grounded then
		self.Clock += dt * buzz.Frequency
		local t = self.Clock
		local nx, ny = math.noise(t, 0.3), math.noise(0.7, t)
		cframe *= CFrame.new(nx * buzz.Position * buzzT, ny * buzz.Position * buzzT, 0)
			* CFrame.Angles(0, 0, math.rad(math.noise(t, 5.1) * buzz.Angle * buzzT))
	end
	camera.CFrame = cframe
	camera.Focus = CFrame.new(focus)
end

return ThirdPersonCamera
