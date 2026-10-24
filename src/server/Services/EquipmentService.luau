--[[
	EquipmentService
	Builds skis (with bindings and poles) or a snowboard (with strap bindings) under the
	character's feet, plus boots. Temporary primitive geometry, proportioned to an R15 avatar;
	the final MeshPart spec is in docs/EQUIPMENT_ASSETS.md.
	Feet and gear are one system: skis (and their bindings) and boots are welded to the feet,
	so they follow every pose; the snowboard is welded to the HumanoidRootPart and the riding
	pose solves both feet onto its bindings (see client/Animation/RiderPose). Poles are welded into the hands, so they follow the
	client-side arm pose: trailing while riding, tucked under the arms, planting on turns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local EquipmentService = {}

local rad = math.rad
-- Equipment base sits this far below the feet (matches the ride height used by movement).
local BASE_DROP = MovementConfig.EquipmentThickness
-- Roblox cylinders run along X; this turns one into a flat disc lying in the XZ plane.
local DISC = CFrame.Angles(0, 0, rad(90))

local function newPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	return Create("Part", {
		Name = name,
		Shape = shape or Enum.PartType.Block,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Massless = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = model,
	})
end

-- A part placed at `offset` in `base` space and welded to it.
local function attach(base: BasePart, model: Model, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local part = newPart(model, name, size, color, material, shape)
	part.CFrame = base.CFrame * offset
	Create("Weld", { Part0 = base, Part1 = part, C0 = offset, Parent = part })
	return part
end

--[[
	An upturned, rounded end (ski tip/tail, board nose/tail). `frame` is the centre of the flat
	section's end edge on the base's mid-plane, looking outward (-Z = outward). The end turns
	up by `angle` and finishes in a half-disc of the given width.
]]
local function roundedEnd(root: BasePart, model: Model, name: string, frame: CFrame, width: number, thickness: number, length: number, angle: number, color: Color3)
	local radius = width / 2
	local bent = frame * CFrame.Angles(rad(angle), 0, 0)
	local straight = math.max(length - radius, 0.02)
	attach(root, model, name, Vector3.new(width, thickness, straight), bent * CFrame.new(0, 0, -straight / 2), color)
	attach(root, model, name .. "Round", Vector3.new(thickness, width, width), bent * CFrame.new(0, 0, -straight) * DISC, color, nil, Enum.PartType.Cylinder)
end

-- Boots welded to the feet, so they follow the riding pose. Ski boots add a shin cuff.
local function buildBoots(character: Model, model: Model, color: Color3, cuff: boolean)
	for _, side in { "Left", "Right" } do
		local foot = character:FindFirstChild(side .. "Foot") :: BasePart?
		if foot then
			local size = foot.Size
			-- Sole sits a little below the foot, onto the binding
			local height = size.Y + 0.3
			attach(foot, model, "Boot", Vector3.new(size.X + 0.08, height, size.Z + 0.14), CFrame.new(0, (height - size.Y) / 2 - 0.1, 0), color)
		end
		local shin = character:FindFirstChild(side .. "LowerLeg") :: BasePart?
		if cuff and shin then
			local size = shin.Size
			local height = math.min(0.65, size.Y * 0.5)
			attach(shin, model, "BootCuff", Vector3.new(size.X + 0.1, height, size.Z + 0.1), CFrame.new(0, -size.Y / 2 + height / 2, 0), color)
		end
	end
end

-- Skis (with their bindings) are welded to the feet, so each ski follows its boot through
-- every pose. Offsets are laid out in root space for a foot standing on its ski, then
-- converted into that foot's space. The riding pose (RiderPose) puts the feet exactly there.
local function buildSkis(character: Model, root: BasePart, model: Model, spec, footY: number)
	local thickness = spec.Thickness
	local y = footY - BASE_DROP + thickness / 2 -- ski base on the snow
	local top = y + thickness / 2
	local riser = footY - 0.1 - top -- binding plate fills the gap up to the boot sole
	local length = spec.Length
	local restLeft = CharacterUtil.GetRestFootCFrame(character, "Left")
	local restRight = CharacterUtil.GetRestFootCFrame(character, "Right")
	local footZ = if restLeft and restRight then (restLeft.Position.Z + restRight.Position.Z) / 2 else 0
	local centerZ = footZ - spec.MountOffset -- boot slightly behind the ski's centre

	for _, side in { -1, 1 } do
		local x = side * spec.Spacing / 2
		local foot = character:FindFirstChild(if side < 0 then "LeftFoot" else "RightFoot") :: BasePart?
		-- Base part and the transform from root-space layout into its space
		local base, mount = root, CFrame.identity
		if foot and restLeft then
			base = foot
			mount = CFrame.new(x, footY + foot.Size.Y / 2, footZ):Inverse()
		end
		local function part(name: string, size: Vector3, offset: CFrame, color: Color3)
			attach(base, model, name, size, mount * offset, color)
		end

		local center = CFrame.new(x, y, centerZ)
		-- Waist, with wider forebody and tail sections (sidecut)
		part("Ski", Vector3.new(spec.Width, thickness, length), center, spec.Color)
		local fore, aft = length * 0.22, length * 0.16
		part("SkiShovel", Vector3.new(spec.ShovelWidth, thickness, fore), center * CFrame.new(0, 0, -length / 2 + fore / 2), spec.Color)
		part("SkiTailSection", Vector3.new(spec.ShovelWidth * 0.95, thickness, aft), center * CFrame.new(0, 0, length / 2 - aft / 2), spec.Color)
		-- Rounded tip and tail
		roundedEnd(base, model, "SkiTip", mount * center * CFrame.new(0, 0, -length / 2), spec.ShovelWidth, thickness, spec.TipLength, spec.TipAngle, spec.Color)
		roundedEnd(base, model, "SkiTail", mount * center * CFrame.new(0, 0, length / 2) * CFrame.Angles(0, math.pi, 0), spec.ShovelWidth * 0.95, thickness, spec.TailLength, spec.TailAngle, spec.Color)
		-- Top-sheet stripe
		part("SkiStripe", Vector3.new(spec.Width * 0.3, 0.012, length * 0.8), center * CFrame.new(0, thickness / 2 + 0.006, 0), spec.StripeColor)
		-- Binding: plate under the boot, toe and heel pieces
		if riser > 0.01 then
			part("BindingPlate", Vector3.new(spec.Width * 0.9, riser, 1.3), CFrame.new(x, top + riser / 2, footZ), spec.BindingColor)
		end
		part("BindingToe", Vector3.new(spec.Width + 0.04, 0.2, 0.32), CFrame.new(x, footY - 0.05, footZ - 0.72), spec.BindingColor)
		part("BindingHeel", Vector3.new(spec.Width + 0.04, 0.26, 0.4), CFrame.new(x, footY - 0.02, footZ + 0.76), spec.BindingColor)
	end
end

local function buildBoard(root: BasePart, model: Model, spec, footY: number)
	local thickness = spec.Thickness
	local y = footY - BASE_DROP + thickness / 2
	local top = y + thickness / 2
	local kick = spec.KickLength
	local flat = spec.Length - 2 * kick * math.cos(rad(spec.KickAngle))
	local center = CFrame.new(0, y, 0)

	attach(root, model, "Board", Vector3.new(spec.Width, thickness, flat), center, spec.Color)
	-- Wider nose and tail sections (sidecut)
	local section = flat * 0.2
	for _, z in { -1, 1 } do
		attach(root, model, "BoardSection", Vector3.new(spec.NoseWidth, thickness, section), center * CFrame.new(0, 0, z * (flat - section) / 2), spec.Color)
	end
	-- Dark base and edges peeking out underneath
	attach(root, model, "BoardBase", Vector3.new(spec.Width + 0.03, 0.03, flat), center * CFrame.new(0, -thickness / 2 - 0.01, 0), spec.BaseColor)
	roundedEnd(root, model, "BoardNose", center * CFrame.new(0, 0, -flat / 2), spec.NoseWidth, thickness, kick, spec.KickAngle, spec.Color)
	roundedEnd(root, model, "BoardTail", center * CFrame.new(0, 0, flat / 2) * CFrame.Angles(0, math.pi, 0), spec.NoseWidth, thickness, kick, spec.KickAngle, spec.Color)

	-- Bindings: baseplate, highback on the heel side, ankle and toe straps.
	-- Regular stance faces +X (right of travel), so the heel side is -X.
	local plate = math.max(footY - 0.1 - top, 0.05)
	for _, z in { -1, 1 } do
		local bz = z * spec.BindingSpacing / 2
		attach(root, model, "BindingBase", Vector3.new(1.15, plate, 0.95), CFrame.new(0, top + plate / 2, bz), spec.BindingColor)
		attach(root, model, "Highback", Vector3.new(0.12, 0.85, 0.85), CFrame.new(-0.6, footY + 0.32, bz) * CFrame.Angles(0, 0, rad(-12)), spec.BindingColor)
		attach(root, model, "AnkleStrap", Vector3.new(0.5, 0.1, 1.12), CFrame.new(-0.12, footY + 0.42, bz), spec.StrapColor)
		attach(root, model, "ToeStrap", Vector3.new(0.22, 0.08, 1.1), CFrame.new(0.42, footY + 0.25, bz), spec.StrapColor)
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

-- Accessories join their handle to the body with an AccessoryWeld (older) or a
-- RigidConstraint between attachments (newer).
local function isAttachedTo(handle: BasePart, part: BasePart): boolean
	for _, joint in handle:GetChildren() do
		if joint:IsA("JointInstance") and (joint.Part0 == part or joint.Part1 == part) then
			return true
		end
		if joint:IsA("RigidConstraint") then
			local a0, a1 = joint.Attachment0, joint.Attachment1
			if (a0 and a0.Parent == part) or (a1 and a1.Parent == part) then
				return true
			end
		end
	end
	return false
end

-- Bounds (in head space) of the head plus anything welded to it (hair, hats, face meshes),
-- so the helmet fits whatever the avatar wears.
local function headBounds(character: Model, head: BasePart): (Vector3, Vector3)
	local low, high = -head.Size / 2, head.Size / 2
	for _, accessory in character:GetChildren() do
		local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle") :: BasePart?
		if handle and isAttachedTo(handle, head) then
			local frame = head.CFrame:ToObjectSpace(handle.CFrame)
			local half = handle.Size / 2
			for _, corner in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
				local point = frame * (half * corner)
				low = low:Min(point)
				high = high:Max(point)
			end
		end
	end
	return low, high
end

-- Helmet, goggles and backpack, welded to the head and upper torso so they follow the pose.
local function buildOutfit(character: Model, model: Model)
	local outfit = SportConfig.Outfit
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		local low, high = headBounds(character, head)
		local size = high - low
		local center = (low + high) / 2
		-- Shell over the top of the head, slightly larger than everything it covers
		local shellHeight = size.Y * 0.38
		local shellY = high.Y - shellHeight / 2 - 0.04
		attach(head, model, "Helmet", Vector3.new(size.X + 0.04, shellHeight, size.Z + 0.06), CFrame.new(center.X, shellY, center.Z), outfit.HelmetColor)
		-- Goggles resting on the helmet's front edge
		local goggleY = shellY - shellHeight / 2 + 0.05
		local front = low.Z - 0.08
		attach(head, model, "GoggleFrame", Vector3.new(size.X * 0.92, size.Y * 0.16, 0.14), CFrame.new(center.X, goggleY, front), outfit.GoggleFrameColor)
		local lens = attach(head, model, "GoggleLens", Vector3.new(size.X * 0.8, size.Y * 0.11, 0.06), CFrame.new(center.X, goggleY, front - 0.08), outfit.LensColor)
		lens.Reflectance = 0.25
	end
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local size = torso.Size
		local pack = attach(torso, model, "Backpack", Vector3.new(size.X * 0.7, size.Y * 0.8, 0.5), CFrame.new(0, -size.Y * 0.05, size.Z / 2 + 0.25), outfit.BackpackColor)
		attach(pack, model, "BackpackLogo", Vector3.new(0.4, 0.3, 0.02), CFrame.new(0, 0.15, 0.26), outfit.BackpackAccentColor)
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
	local footY = -CharacterUtil.GetFootOffset(character) -- bottom of the feet, in root space

	buildOutfit(character, model)
	buildBoots(character, model, spec.BootColor, spec.Kind == "Skis")
	if spec.Kind == "Skis" then
		buildSkis(character, root, model, spec, footY)
		if spec.Poles then
			buildPoles(character, model, spec.Poles)
		end
	else
		buildBoard(root, model, spec, footY)
	end

	model.Parent = character
end

return EquipmentService
