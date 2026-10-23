--[[
	EquipmentService
	Attaches placeholder skis or a snowboard under the character's feet.
	Parts are welded to the HumanoidRootPart (not the feet) so they stay flat regardless of
	animations; Phase 2 animation work can move them onto the feet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local EquipmentService = {}

local function weldedPart(root: BasePart, model: Model, name: string, size: Vector3, offset: CFrame, color: Color3)
	local part = Create("Part", {
		Name = name,
		Size = size,
		CFrame = root.CFrame * offset,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Massless = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = model,
	})
	Create("WeldConstraint", { Part0 = root, Part1 = part, Parent = part })
	return part
end

local function buildSkis(root: BasePart, model: Model, spec, footY: number)
	for _, side in { -1, 1 } do
		local x = side * spec.Spacing / 2
		weldedPart(root, model, "Ski", spec.Size, CFrame.new(x, footY, -0.4), spec.Color)
		-- Upturned tip
		local tipLength = 0.9
		weldedPart(
			root,
			model,
			"SkiTip",
			Vector3.new(spec.Size.X, spec.Size.Y, tipLength),
			CFrame.new(x, footY, -0.4 - spec.Size.Z / 2) * CFrame.Angles(math.rad(30), 0, 0) * CFrame.new(0, 0, -tipLength / 2),
			spec.Color
		)
	end
end

local function buildBoard(root: BasePart, model: Model, spec, footY: number)
	weldedPart(root, model, "Board", spec.Size, CFrame.new(0, footY, 0), spec.Color)
	for _, z in { -1, 1 } do
		weldedPart(
			root,
			model,
			"Binding",
			Vector3.new(1.1, 0.35, 0.7),
			CFrame.new(0, footY + 0.25, z * 0.9),
			Color3.fromRGB(30, 30, 35)
		)
	end
end

function EquipmentService.Unequip(character: Model)
	local existing = character:FindFirstChild(Constants.EquipmentModelName)
	if existing then
		existing:Destroy()
	end
end

function EquipmentService.Equip(character: Model, sportId: string)
	local sport = SportConfig.Sports[sportId]
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not sport or not root then
		return
	end

	EquipmentService.Unequip(character)

	local model = Create("Model", { Name = Constants.EquipmentModelName })
	model:SetAttribute("Sport", sportId)
	local spec = sport.Equipment
	local footY = -CharacterUtil.GetFootOffset(character) - MovementConfig.EquipmentThickness / 2

	if spec.Kind == "Skis" then
		buildSkis(root, model, spec, footY)
	else
		buildBoard(root, model, spec, footY)
	end

	model.Parent = character
end

return EquipmentService
