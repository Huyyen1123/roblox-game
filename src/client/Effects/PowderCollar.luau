--[[
	PowderCollar
	Deep-powder look for one piece of gear (one ski, or the board), without moving the gear:
	soft snow built up around it so the snow surface appears higher than its base, plus a
	compressed trench left behind.

	Everything sits on a "snow plane": the terrain surface under the gear (one raycast per
	frame), facing along the gear. Not welded to the gear: when the gear rolls onto an edge in a
	carve, welded snow would tip up into the air on one side and dig in on the other. On the
	plane the snow always meets the terrain.

	Each bank along the gear's side is a sunk capsule (two large-radius cylinders joined by a
	ball of the same radius), so only a thin, smooth, rounded strip shows: one continuous wall
	of snow with no scallops or flat faces. It rises from below the surface at the nose to its
	peak toward the tail, then falls back below the surface behind the tail, so the nose rides
	out of the powder and snow piles around the tail. They use the
	same material and colour as the terrain, so they read as part of it. Depth is changed by
	moving and tilting them, never by resizing.
	Carving raises the bank on the engaged edge and lowers the other; braking pushes snow up
	at the front; takeoff sinks the collar away; landing swells it briefly.

	The trench: a darker blue-grey Trail the width of the gear, between two thin bright rims,
	all riding on the snow plane so it lies on the surface.

	Visual only: no collision, no queries, no touch. Parts live in a client-side folder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EffectsConfig = require(ReplicatedStorage.Shared.Config.EffectsConfig)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local Settings = EffectsConfig.Powder

local PowderCollar = {}
PowderCollar.__index = PowderCollar

local folder: Folder? = nil
local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = Create("Folder", { Name = "PowderEffects", Parent = Workspace })
	end
	return folder :: Folder
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }

local HIDDEN = CFrame.new(0, -1e5, 0)

local function snowShape(shape: Enum.PartType, size: Vector3)
	return Create("Part", {
		Name = "Powder",
		Shape = shape,
		Size = size,
		Material = Enum.Material.Snow,
		Color = Settings.Color,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		CFrame = HIDDEN,
		Parent = getFolder(),
	})
end

local function trail(anchor: BasePart, x0: number, x1: number, y: number, z: number, color: Color3, startTransparency: number, lifetime: number)
	local a0 = Create("Attachment", { Position = Vector3.new(x0, y, z), Parent = anchor })
	local a1 = Create("Attachment", { Position = Vector3.new(x1, y, z), Parent = anchor })
	return Create("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(color),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, startTransparency),
			NumberSequenceKeypoint.new(0.6, (1 + startTransparency) / 2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = lifetime,
		LightInfluence = 1,
		LightEmission = 0,
		FaceCamera = false,
		MinLength = 0.15,
		Enabled = false,
		Parent = anchor,
	})
end

-- gear: the main Ski or Board part. kind: "Ski" or "Board".
function PowderCollar.new(gear: BasePart, kind: string)
	local self = setmetatable({}, PowderCollar)
	self.Gear = gear
	self.Kind = kind
	self.Depth = 0 -- current overall depth factor (eased); 0 = no collar
	self.Swell = 0 -- landing swell, decays
	self.Parts = {}

	local length, width = gear.Size.Z, gear.Size.X
	local layout = if kind == "Board" then Settings.Board else Settings.Ski
	self.Layout = layout

	-- For skis, the side facing the other ski (kept lower so the ski tops stay visible)
	local inner = 0
	if kind == "Ski" then
		local equipment = gear:FindFirstAncestorOfClass("Model")
		local character = equipment and equipment:FindFirstAncestorOfClass("Model")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			inner = if root.CFrame:PointToObjectSpace(gear.Position).X < 0 then 1 else -1
		end
	end

	-- Side banks: a sunk capsule per side (front cylinder, joint ball, rear cylinder)
	local radius = layout.BankRadius
	local noseZ = -length / 2
	local peakZ = layout.PeakAt * length / 2
	local endZ = length / 2 + layout.TailExtend
	self.Banks = {}
	for _, side in { -1, 1 } do
		local front = snowShape(Enum.PartType.Cylinder, Vector3.new(peakZ - noseZ, radius * 2, radius * 2))
		local joint = snowShape(Enum.PartType.Ball, Vector3.one * radius * 2)
		local rear = snowShape(Enum.PartType.Cylinder, Vector3.new(endZ - peakZ, radius * 2, radius * 2))
		for _, part in { front, joint, rear } do
			table.insert(self.Parts, part)
		end
		table.insert(self.Banks, {
			Front = front,
			Joint = joint,
			Rear = rear,
			Side = side,
			X = side * (width / 2 + layout.BankOutset),
			Scale = if side == inner then layout.InnerScale else 1,
		})
	end
	self.NoseZ, self.PeakZ, self.EndZ = noseZ, peakZ, endZ

	-- Snow plane anchor (invisible) carrying the trench trails
	local anchor = Create("Part", {
		Name = "SnowPlane",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = HIDDEN,
		Parent = getFolder(),
	})
	table.insert(self.Parts, anchor)
	self.Anchor = anchor
	local trench = Settings.Trench
	local tz = length / 2 - 0.3
	local half = width / 2 * trench.WidthShare
	self.Trails = {
		trail(anchor, -half, half, trench.Lift, tz, trench.GrooveColor, trench.GrooveTransparency, trench.Lifetime),
		trail(anchor, -half - trench.RimWidth, -half, trench.Lift + 0.01, tz, trench.RimColor, trench.RimTransparency, trench.Lifetime * 0.8),
		trail(anchor, half, half + trench.RimWidth, trench.Lift + 0.01, tz, trench.RimColor, trench.RimTransparency, trench.Lifetime * 0.8),
	}
	self.TrailsOn = false
	self.Hidden = true
	return self
end

function PowderCollar:OnLanded(impact: number)
	self.Swell = math.min(impact * Settings.SwellPerImpact, Settings.MaxSwell)
end

local function setTrails(self, on: boolean)
	if self.TrailsOn ~= on then
		self.TrailsOn = on
		for _, t in self.Trails do
			t.Enabled = on
		end
	end
end

--[[
	contact: the rider is on snow (from the movement state / effects gate)
	steer:   body-frame steer, -1..1 (positive = turning to the body's right)
	speed:   studs/s
	braking: true while braking
	parts / cframes: arrays this collar appends to, moved together with BulkMoveTo
]]
function PowderCollar:Update(dt: number, contact: boolean, steer: number, speed: number, braking: boolean, parts, cframes)
	local gear = self.Gear
	local layout = self.Layout

	-- Snow under this piece of gear
	local plane
	if contact then
		local gcf = gear.CFrame
		local hit = Workspace:Raycast(gcf.Position + Vector3.yAxis * 2, Vector3.new(0, -2 - Settings.ContactDistance - gear.Size.Y, 0), rayParams)
		if hit then
			local forward = gcf.LookVector - hit.Normal * gcf.LookVector:Dot(hit.Normal)
			if forward.Magnitude > 1e-3 then
				plane = CFrame.lookAt(hit.Position, hit.Position + forward.Unit, hit.Normal)
			end
		end
	end

	-- Depth eases in on the snow and sinks away quickly on takeoff
	local target = if plane then 1 else 0
	local rate = if target > self.Depth then Settings.SinkInRate else Settings.LiftOutRate
	self.Depth += (target - self.Depth) * (1 - math.exp(-rate * dt))
	self.Swell *= math.exp(-Settings.SwellRecovery * dt)

	if not plane or self.Depth < 0.02 then
		if not self.Hidden then
			self.Hidden = true
			for _, part in self.Parts do
				table.insert(parts, part)
				table.insert(cframes, HIDDEN)
			end
		end
		setTrails(self, false)
		return
	end
	self.Hidden = false

	local carve = math.abs(steer) * math.clamp(speed / Settings.CarveFullSpeed, 0, 1)
	local carveSide = if steer > 0 then 1 elseif steer < 0 then -1 else 0
	local depth = self.Depth * (1 + self.Swell)
	local radius = layout.BankRadius
	local sink = radius + Settings.Sink
	local toCylinder = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) onto the look direction
	-- Follow the terrain: lower each bank point by however far the ground dips below the
	-- snow plane under the bank and at its outer edge, so edges never hang in the air on
	-- crests and bumps
	local up = plane.UpVector
	local reach = math.sqrt(math.max(2 * radius * layout.PeakHeight, 0)) -- half-width of the visible strip
	local function dip(x: number, z: number, side: number): number
		local lowest = 0
		for _, dx in { 0, side * reach } do
			local q = plane * Vector3.new(x + dx, 0, z)
			local hit = Workspace:Raycast(q + up * 1.5, -up * 3, rayParams)
			local d = if hit then (hit.Position - q):Dot(up) else -1.5
			lowest = math.min(lowest, d)
		end
		return lowest
	end
	for _, bank in self.Banks do
		local scale = bank.Scale
		if carveSide ~= 0 then
			scale *= if bank.Side == carveSide then 1 + Settings.CarveRaise * carve else 1 - Settings.CarveLower * carve
		end
		-- Axis points (plane space): visible height − radius at the nose, peak and end
		local nose = Vector3.new(bank.X, layout.NoseHeight + (if braking then Settings.BrakeRaise * depth else 0) - sink + dip(bank.X, self.NoseZ, bank.Side), self.NoseZ)
		local peak = Vector3.new(bank.X, layout.PeakHeight * scale * depth - sink + dip(bank.X, self.PeakZ, bank.Side), self.PeakZ)
		local finish = Vector3.new(bank.X, layout.EndHeight - sink + dip(bank.X, self.EndZ, bank.Side), self.EndZ)
		local p0, p1, p2 = plane * nose, plane * peak, plane * finish
		table.insert(parts, bank.Front)
		table.insert(cframes, CFrame.lookAt((p0 + p1) / 2, p1, plane.UpVector) * toCylinder)
		table.insert(parts, bank.Joint)
		table.insert(cframes, CFrame.new(p1))
		table.insert(parts, bank.Rear)
		table.insert(cframes, CFrame.lookAt((p1 + p2) / 2, p2, plane.UpVector) * toCylinder)
	end
	table.insert(parts, self.Anchor)
	table.insert(cframes, plane)
	setTrails(self, speed > Settings.TrailMinSpeed)
end

function PowderCollar:Destroy()
	for _, part in self.Parts do
		part:Destroy()
	end
	table.clear(self.Parts)
end

return PowderCollar
