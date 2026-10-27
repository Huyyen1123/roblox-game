--[[
	EffectsController
	Riding feedback for every rider near the camera (see EffectsConfig):
	  - The channel each ski / the board cuts into the snow, left as a trail
	    (client/Effects/SnowGroove). The digging-in itself is in the riding pose.
	  - Snow spray off the outside edge while carving, off both edges while braking, and a
	    light dust at speed.
	  - Landing puffs.
	  - Wind streaks at the screen edges at high speed (local rider only).
	The local rider is driven from the movement state; other riders from the replicated
	Rider* attributes and their root velocity. All client-side and visual only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EffectsConfig = require(ReplicatedStorage.Shared.Config.EffectsConfig)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)
local Create = require(ReplicatedStorage.Shared.Util.Create)
local SnowGroove = require(script.Parent.Parent.Effects.SnowGroove)
local PowderWake = require(script.Parent.Parent.Effects.PowderWake)

local EffectsController = {}

local localPlayer = Players.LocalPlayer
local Movement
local rigs = {} -- [character] = rig

local function numberSequence(a: number, b: number)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function newEmitter(parent: Attachment, direction: Enum.NormalId)
	local spray = EffectsConfig.Spray
	return Create("ParticleEmitter", {
		Texture = spray.Texture,
		Color = spray.Color,
		LightInfluence = spray.LightInfluence,
		LightEmission = 0,
		Size = numberSequence(spray.Size[1], spray.Size[2]),
		-- Stays dense for the first half of its life, then thins out
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spray.StartTransparency),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = spray.Lifetime,
		Speed = spray.Speed,
		SpreadAngle = Vector2.new(18, 30),
		Acceleration = Vector3.new(0, -spray.Gravity, 0),
		Drag = spray.Drag,
		VelocityInheritance = spray.VelocityInheritance,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		EmissionDirection = direction,
		Rate = 0,
		Parent = parent,
	})
end

local snowMaterials = {}
for _, name in EffectsConfig.SnowMaterials do
	snowMaterials[Enum.Material[name]] = true
end
local contactParams = RaycastParams.new()
contactParams.FilterType = Enum.RaycastFilterType.Include
contactParams.FilterDescendantsInstances = { workspace.Terrain }

local function destroyRig(rig)
	rig.Added:Disconnect()
	for _, instance in rig.Instances do
		instance:Destroy()
	end
	for _, groove in rig.Grooves do
		groove:Destroy()
	end
	if rig.Wake then
		rig.Wake:Destroy()
		rig.Wake = nil
	end
end

local function buildRig(character: Model, equipment: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local sport = SportConfig.Sports[equipment:GetAttribute("Sport")]
	if not root or not sport then
		return nil
	end
	local spec = sport.Equipment
	local snowY = -CharacterUtil.GetFootOffset(character) - MovementConfig.EquipmentThickness + 0.04
	local inset = EffectsConfig.Trail.Inset
	local instances = {}
	local trails = {}
	-- The channel each ski / the board cuts into the snow
	local grooves = {}
	local gears = {}
	for _, gear in equipment:GetChildren() do
		if gear:IsA("BasePart") and (gear.Name == "Ski" or gear.Name == "Board") then
			table.insert(grooves, SnowGroove.new(gear))
			table.insert(gears, gear)
		end
	end

	local halfWidth, tailZ
	if spec.Kind == "Skis" then
		tailZ = -spec.MountOffset + spec.Length / 2 - inset
		halfWidth = spec.Spacing / 2 + spec.ShovelWidth / 2
	else
		tailZ = spec.Length / 2 - spec.KickLength - inset
		halfWidth = spec.Width / 2
	end

	-- Spray from each side of the tails, thrown outward, up and back (a rooster tail the
	-- chase camera can see); puffs from the centre
	local launch = math.rad(EffectsConfig.Spray.LaunchAngle)
	local sweep = math.rad(EffectsConfig.Spray.BackSweep)
	local sprayZ = tailZ * 0.6
	local leftAtt = Create("Attachment", {
		Name = "SprayLeft",
		CFrame = CFrame.new(-halfWidth, snowY + 0.1, sprayZ) * CFrame.Angles(0, sweep, 0) * CFrame.Angles(0, 0, -launch),
		Parent = root,
	})
	local rightAtt = Create("Attachment", {
		Name = "SprayRight",
		CFrame = CFrame.new(halfWidth, snowY + 0.1, sprayZ) * CFrame.Angles(0, -sweep, 0) * CFrame.Angles(0, 0, launch),
		Parent = root,
	})
	local puffAtt = Create("Attachment", { Name = "LandingPuff", Position = Vector3.new(0, snowY + 0.1, 0), Parent = root })
	local puff = newEmitter(puffAtt, Enum.NormalId.Top)
	puff.SpreadAngle = Vector2.new(80, 80)
	-- Rooster tail: a plume thrown up and back from the tail in hard, fast turns
	local rooster = EffectsConfig.RoosterTail
	local roosterAtt = Create("Attachment", {
		Name = "RoosterTail",
		CFrame = CFrame.new(0, snowY + 0.2, tailZ) * CFrame.Angles(-math.rad(rooster.LaunchAngle), 0, 0), -- back (+Z) tilted up
		Parent = root,
	})
	local roosterEmitter = newEmitter(roosterAtt, Enum.NormalId.Back)
	roosterEmitter.Speed = rooster.Speed
	roosterEmitter.SpreadAngle = Vector2.new(14, 22)
	roosterEmitter.Size = numberSequence(rooster.Size[1], rooster.Size[2])
	roosterEmitter.Lifetime = rooster.Lifetime
	table.insert(instances, leftAtt)
	table.insert(instances, rightAtt)
	table.insert(instances, puffAtt)
	table.insert(instances, roosterAtt)

	local rig
	-- Gear parts can arrive on the client after the Equipment model itself
	local added = equipment.ChildAdded:Connect(function(child)
		if rig and (child.Name == "Ski" or child.Name == "Board") then
			rig.Dirty = true
		end
	end)
	rig = {
		Added = added,
		Equipment = equipment,
		Root = root,
		Instances = instances,
		Trails = trails,
		Grooves = grooves,
		Gears = gears, -- the Ski parts or the Board
		Wake = nil, -- PowderWake, created when this rider gets a full-detail slot
		Dirty = false,
		RideHeight = -snowY + 0.04,
		Left = newEmitter(leftAtt, Enum.NormalId.Left),
		Right = newEmitter(rightAtt, Enum.NormalId.Right),
		Puff = puff,
		Rooster = roosterEmitter,
		WasAir = false,
	}
	return rig
end

local function riderInput(character: Model)
	if character == localPlayer.Character and Movement then
		local state = Movement.State
		-- Steer in the body's frame (the spray emitters sit on the body's left and right)
		local steer = if state.Switch then -state.Steer else state.Steer
		return state.Active and state.Mode ~= "Frozen", state.Speed, not state.Grounded, state.Braking, steer
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
	return true, speed, character:GetAttribute("RiderAir") == true, character:GetAttribute("RiderBrake") == true, character:GetAttribute("RiderSteer") or 0
end

local function isSwitch(character: Model): boolean
	if character == localPlayer.Character and Movement then
		return Movement.State.Switch
	end
	return character:GetAttribute("RiderSwitch") == true
end

-- Full-detail powder wake (prototype, skis and boards): the local rider plus the nearest few
-- riders within range; local rider only at low graphics quality. Timing is measured.
local wakeSlots = {} -- [character] = true
local wakeStats = { Frames = 0, Total = 0, Samples = {} }
_G.PowderWakeStats = wakeStats

local function graphicsQuality(): number
	local ok, level = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	-- 0 = Automatic: treat as high
	return if ok and level > 0 then level else 10
end

local function chooseWakeSlots(cameraPosition: Vector3)
	table.clear(wakeSlots)
	local settings = EffectsConfig.Wake
	if not settings.Enabled or not PowderWake.Available() then
		return
	end
	local local_ = localPlayer.Character
	if local_ then
		wakeSlots[local_] = true
	end
	if graphicsQuality() < settings.MinQualityLevel then
		return
	end
	local candidates = {}
	for character, rig in rigs do
		if character ~= local_ and #rig.Gears > 0 then
			local distance = (rig.Root.Position - cameraPosition).Magnitude
			if distance < settings.MaxDistance then
				table.insert(candidates, { character, distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a[2] < b[2]
	end)
	for i = 1, math.min(settings.MaxRemote, #candidates) do
		wakeSlots[candidates[i][1]] = true
	end
end

local function updateWake(rig, character: Model, dt: number, contact: boolean, steer: number, speed: number, braking: boolean)
	local wanted = #rig.Gears > 0 and wakeSlots[character] == true and not rig.WakeFailed
	if wanted and not rig.Wake then
		local ok, wake = pcall(PowderWake.new, rig.Gears)
		rig.Wake = if ok then wake else nil
		-- Don't retry every frame (e.g. the client's mesh memory budget is used up)
		rig.WakeFailed = not ok
	elseif not wanted and rig.Wake then
		rig.Wake:Destroy()
		rig.Wake = nil
	end
	if rig.Wake then
		local started = os.clock()
		rig.Wake:Update(dt, contact, steer, speed, braking, isSwitch(character))
		local elapsed = os.clock() - started
		wakeStats.Total += elapsed
		table.insert(wakeStats.Samples, elapsed)
		if #wakeStats.Samples > 600 then
			table.remove(wakeStats.Samples, 1)
		end
	end
end

-- Groove anchors for every rider are moved together in one BulkMoveTo
local moveParts, moveCFrames = {}, {}
local function updateGrooves(rig, contact: boolean, speed: number)
	for _, groove in rig.Grooves do
		groove:Update(contact, speed, moveParts, moveCFrames)
	end
end

local function setActive(rig, active: boolean)
	for _, trail in rig.Trails do
		trail.Enabled = active
	end
	if not active then
		updateGrooves(rig, false, 0)
	end
	if not active then
		rig.Left.Rate = 0
		rig.Right.Rate = 0
		rig.Rooster.Rate = 0
		-- Not riding (respawn, menu) or out of range: drop the mesh wake
		if rig.Wake then
			rig.Wake:Destroy()
			rig.Wake = nil
		end
	end
end

local function updateRig(rig, character: Model, cameraPosition: Vector3)
	local riding, speed, air, braking, steer = riderInput(character)
	local near = (rig.Root.Position - cameraPosition).Magnitude < EffectsConfig.MaxDistance
	if not riding or not near then
		setActive(rig, false)
		rig.WasAir = air
		return
	end

	-- Landing puff (other riders: detected from the air flag; local: from Movement.Landed)
	if rig.WasAir and not air and character ~= localPlayer.Character then
		rig.Puff:Emit(EffectsConfig.LandingPuff.Base)
		if rig.Wake then
			rig.Wake:OnLanded(30)
		end
	end
	-- Takeoff: snow falls away from the gear as it leaves the snow
	if air and not rig.WasAir and speed > EffectsConfig.Spray.MinSpeed then
		rig.Puff:Emit(EffectsConfig.LandingPuff.Takeoff)
	end
	rig.WasAir = air

	-- Touching snow: the movement says grounded, and the snow is right under the gear (also
	-- keeps effects off rock and ice, and off riders whose air flag hasn't arrived yet)
	local grounded = not air
	if grounded then
		local hit = workspace:Raycast(rig.Root.Position, -rig.Root.CFrame.UpVector * (rig.RideHeight + EffectsConfig.Groove.ContactDistance), contactParams)
		grounded = hit ~= nil and snowMaterials[hit.Material] == true
	end
	local nearGroove = (rig.Root.Position - cameraPosition).Magnitude < EffectsConfig.Groove.MaxDistance
	updateGrooves(rig, grounded and nearGroove, speed)
	updateWake(rig, character, rig.Dt or 1 / 60, grounded, steer, speed, braking)
	for _, trail in rig.Trails do
		trail.Enabled = grounded and speed > EffectsConfig.Trail.MinSpeed
	end

	local spray = EffectsConfig.Spray
	local left, right = 0, 0
	if grounded and speed > spray.MinSpeed then
		local cruise = speed * spray.CruisePerSpeed
		left, right = cruise, cruise
		local carve = speed * math.abs(steer) * spray.CarvePerSpeed
		-- Turning right throws snow off the left (outside) edge, and vice versa
		if steer > 0 then
			left += carve
		else
			right += carve
		end
		if braking then
			local brake = speed * spray.BrakePerSpeed
			left += brake
			right += brake
		end
	end
	-- Lighter for distant riders and low graphics settings
	local scale = 1
	if (rig.Root.Position - cameraPosition).Magnitude > EffectsConfig.DetailDistance then
		scale *= EffectsConfig.FarRateScale
	end
	if graphicsQuality() < EffectsConfig.LowQualityLevel then
		scale *= EffectsConfig.LowQualityRateScale
	end
	rig.Left.Rate = math.min(left, spray.MaxRate) * scale
	rig.Right.Rate = math.min(right, spray.MaxRate) * scale

	-- Rooster tail: only in hard turns at speed
	local rooster = EffectsConfig.RoosterTail
	local roosterRate = 0
	if grounded and speed > rooster.MinSpeed and math.abs(steer) > rooster.MinSteer then
		roosterRate = (speed - rooster.MinSpeed) * (math.abs(steer) - rooster.MinSteer) / (1 - rooster.MinSteer) * rooster.PerSpeed
	end
	rig.Rooster.Rate = math.min(roosterRate, rooster.MaxRate) * scale
end

-- Wind streaks: thin lines drifting outward near the screen edges at high speed
local streaks = {}
local streakGui

local function buildStreaks()
	streakGui = Create("ScreenGui", {
		Name = "WindStreaks",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = -1,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	for i = 1, EffectsConfig.WindStreaks.Count do
		local frame = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 60),
			Parent = streakGui,
		})
		streaks[i] = { Frame = frame, Angle = math.random() * 2 * math.pi, Radius = 0.6 + math.random() * 0.4, Length = 40 + math.random() * 90 }
	end
end

local function updateStreaks(dt: number)
	local settings = EffectsConfig.WindStreaks
	local state = Movement.State
	local intensity = 0
	if state.Active and state.Mode ~= "Wipeout" then
		intensity = math.clamp((state.Speed - settings.StartSpeed) / (settings.FullSpeed - settings.StartSpeed), 0, 1)
	end
	streakGui.Enabled = intensity > 0
	if intensity <= 0 then
		return
	end
	local viewport = Workspace.CurrentCamera.ViewportSize
	local half = viewport / 2
	for _, streak in streaks do
		streak.Radius += settings.Speed * dt * (0.6 + intensity)
		if streak.Radius > 1.15 then
			streak.Radius = 0.6 + math.random() * 0.15
			streak.Angle = math.random() * 2 * math.pi
			streak.Length = 40 + math.random() * 90
		end
		local fade = math.clamp((streak.Radius - 0.6) / 0.15, 0, 1) * math.clamp((1.15 - streak.Radius) / 0.2, 0, 1)
		local dir = Vector2.new(math.cos(streak.Angle), math.sin(streak.Angle))
		local frame = streak.Frame
		frame.Position = UDim2.fromOffset(half.X + dir.X * half.X * streak.Radius, half.Y + dir.Y * half.Y * streak.Radius)
		frame.Size = UDim2.fromOffset(2, streak.Length * (0.5 + intensity))
		frame.Rotation = math.deg(streak.Angle) + 90
		frame.BackgroundTransparency = 1 - settings.MaxOpacity * intensity * fade
	end
end

local slotTimer = 0
local function step(dt: number)
	local cameraPosition = Workspace.CurrentCamera.CFrame.Position
	slotTimer -= dt
	if slotTimer <= 0 then
		slotTimer = 0.5
		chooseWakeSlots(cameraPosition)
	end
	wakeStats.Frames += 1
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local equipment = character and character:FindFirstChild(Constants.EquipmentModelName)
		local rig = character and rigs[character]
		-- Rebuild when the gear changes, or when its parts replicated after the model did
		if rig and (rig.Equipment ~= equipment or rig.Dirty) then
			destroyRig(rig)
			rigs[character] = nil
			rig = nil
		end
		if character and equipment and not rig then
			rig = buildRig(character, equipment)
			rigs[character] = rig
		end
		if rig then
			rig.Dt = dt
			updateRig(rig, character, cameraPosition)
		end
	end
	-- Move every rider's powder shapes in one call
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveCFrames)
	end
	for character, rig in rigs do
		if not character.Parent then
			destroyRig(rig)
			rigs[character] = nil
		end
	end
	updateStreaks(dt)
end

function EffectsController.Start(movementController)
	Movement = movementController
	buildStreaks()
	Movement.Landed:Connect(function(_quality, impact)
		local rig = localPlayer.Character and rigs[localPlayer.Character]
		if rig then
			local settings = EffectsConfig.LandingPuff
			rig.Puff:Emit(math.min(settings.Base + impact * settings.PerImpact, settings.Max))
			if rig.Wake then
				rig.Wake:OnLanded(impact)
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return EffectsController
