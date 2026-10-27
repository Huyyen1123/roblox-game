--[[
	Environment
	Applies EnvironmentConfig to Lighting, its post effects, the Sky and Terrain clouds.
	Existing instances of each class are reused rather than duplicated, so this is safe to run
	in edit mode (to preview) and again at runtime.
]]

local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
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

-- Uses each configured MaterialVariant as the override for its base material, when present.
local function applyMaterialOverrides()
	for _, entry in Config.MaterialOverrides do
		if entry.Variant == false then
			-- The stock material
			MaterialService:SetBaseMaterialOverride(entry.Material, "")
			continue
		end
		local variant = MaterialService:FindFirstChild(entry.Variant, true)
		if variant and variant:IsA("MaterialVariant") and variant.BaseMaterial == entry.Material then
			variant.StudsPerTile = entry.StudsPerTile
			-- A stand-in base material (e.g. Salt for groomed snow) keeps the physical
			-- properties of the material it represents
			if entry.PhysicsLike then
				variant.CustomPhysicalProperties = PhysicalProperties.new(entry.PhysicsLike)
			end
			if entry.Pattern then
				variant.MaterialPattern = entry.Pattern
			end
			MaterialService:SetBaseMaterialOverride(entry.Material, entry.Variant)
		else
			warn(`[Environment] MaterialVariant {entry.Variant} not found; {entry.Material.Name} uses the stock texture`)
		end
	end
end

function Environment.Apply()
	apply(Lighting, Config.Lighting)
	apply(getOrCreate(Lighting, "Atmosphere", "Atmosphere"), Config.Atmosphere)
	if Config.Sky then
		apply(getOrCreate(Lighting, "Sky", "Sky"), Config.Sky)
	else
		for _, sky in Lighting:GetChildren() do
			if sky:IsA("Sky") then
				sky:Destroy()
			end
		end
	end
	apply(getOrCreate(Lighting, "ColorCorrectionEffect", "ColorCorrection"), Config.ColorCorrection)
	apply(getOrCreate(Lighting, "BloomEffect", "Bloom"), Config.Bloom)
	apply(getOrCreate(Lighting, "SunRaysEffect", "SunRays"), Config.SunRays)
	apply(getOrCreate(Workspace.Terrain, "Clouds", "Clouds"), Config.Clouds)
	for material, color in Config.TerrainColors or {} do
		Workspace.Terrain:SetMaterialColor(material, color)
	end
	applyMaterialOverrides()
end

return Environment
