--[[
	Snowfall
	Light falling snow around the local camera (visual only, nothing replicates). One
	invisible, non-colliding part holds a ParticleEmitter whose box sits above the camera and
	follows it, so flakes are always falling around the player wherever they ride. Flakes
	inherit none of the rider's speed, so at racing speed they stream past naturally.
	Rate drops on low graphics settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EffectsConfig = require(ReplicatedStorage.Shared.Config.EffectsConfig)

local Settings = EffectsConfig.Snowfall

local Snowfall = {}

local function graphicsQuality(): number
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	return if ok and level > 0 then level else 10
end

function Snowfall.Start()
	if not Settings.Enabled then
		return
	end
	local holder = Instance.new("Part")
	holder.Name = "Snowfall"
	holder.Size = Settings.Area
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds" -- soft round flakes
	emitter.Color = ColorSequence.new(Color3.fromRGB(248, 250, 255))
	emitter.LightEmission = 0.15
	emitter.LightInfluence = 0.6
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Settings.Size.Min),
		NumberSequenceKeypoint.new(1, Settings.Size.Max),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.15),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Speed = Settings.FallSpeed
	emitter.Lifetime = Settings.Lifetime
	emitter.Acceleration = Settings.Drift
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Rate = Settings.Rate
	emitter.Parent = holder
	holder.Parent = Workspace

	local qualityTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		holder.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, Settings.Height, 0))
		qualityTimer -= dt
		if qualityTimer <= 0 then
			qualityTimer = 2
			emitter.Rate = Settings.Rate * (if graphicsQuality() < EffectsConfig.LowQualityLevel then Settings.LowQualityScale else 1)
		end
	end)
end

return Snowfall
