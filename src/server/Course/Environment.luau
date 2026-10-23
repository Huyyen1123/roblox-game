--[[
	Environment
	Applies EnvironmentConfig to Lighting, its post effects, the Sky and Terrain clouds.
	Existing instances of each class are reused rather than duplicated, so this is safe to run
	in edit mode (to preview) and again at runtime.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.EnvironmentConfig)

local Environment = {}

local function getOrCreate(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function apply(instance: Instance, properties: { [string]: any })
	for key, value in properties do
		(instance :: any)[key] = value
	end
end

function Environment.Apply()
	apply(Lighting, Config.Lighting)
	apply(getOrCreate(Lighting, "Atmosphere", "Atmosphere"), Config.Atmosphere)
	apply(getOrCreate(Lighting, "Sky", "Sky"), Config.Sky)
	apply(getOrCreate(Lighting, "ColorCorrectionEffect", "ColorCorrection"), Config.ColorCorrection)
	apply(getOrCreate(Lighting, "BloomEffect", "Bloom"), Config.Bloom)
	apply(getOrCreate(Lighting, "SunRaysEffect", "SunRays"), Config.SunRays)
	apply(getOrCreate(Workspace.Terrain, "Clouds", "Clouds"), Config.Clouds)
end

return Environment
