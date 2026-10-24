--[[
	EquipmentService
	Attaches placeholder skis or a snowboard under the character's feet, plus ski poles.
	Skis and board are welded to the HumanoidRootPart so they stay flat on the snow (the riding
	pose keeps the feet planted on them). Poles are welded into the hands, so they follow the
	client-side arm pose: trailing while riding, tucked under the arms, planting on turns.
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

-- One ski pole in pole-local space (grip at the origin, shaft running down -Y), welded into
-- the hand so the shaft points backward from the hand; the riding pose angles it from there.
local POLE_MOUNT = CFrame.new(0, -0.1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local function polePart(hand: BasePart, model: Model, name: string, length: number, diameter: number, centerY: number, color: Color3, material: Enum.Material)
	-- Cylinders run along X, so rotate them to run along the pole (Y)
	local localFrame = CFrame.new(0, centerY, 0) * CFrame.Angles(0, 0, math.rad(90))
	local part = Create("Part", {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = hand.CFrame * POLE_MOUNT * localFrame,
		Color = color,
		Material = material,
		Massless = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	Create("Weld", { Part0 = hand, Part1 = part, C0 = POLE_MOUNT * localFrame, Parent = part })
end

local function buildPoles(character: Model, model: Model, spec)
	local length = spec.Length
	for _, handName in { "LeftHand", "RightHand" } do
		local hand = character:FindFirstChild(handName) :: BasePart?
		if not hand then
			continue -- R6 rigs have no hands; skip poles
		end
		polePart(hand, model, "PoleGrip", 0.55, 0.24, -0.05, spec.GripColor, Enum.Material.Rubber)
		polePart(hand, model, "PoleShaft", length - 0.3, 0.1, -0.3 - (length - 0.3) / 2, spec.ShaftColor, Enum.Material.Metal)
		polePart(hand, model, "PoleBasket", 0.06, 0.45, -(length - 0.35), spec.BasketColor, Enum.Material.SmoothPlastic)
		polePart(hand, model, "PoleTip", 0.15, 0.06, -length - 0.05, spec.TipColor, Enum.Material.Metal)
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
		if spec.Poles then
			buildPoles(character, model, spec.Poles)
		end
	else
		buildBoard(root, model, spec, footY)
	end

	model.Parent = character
end

return EquipmentService
