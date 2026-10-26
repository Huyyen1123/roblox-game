--[[
	PowderWake (prototype, snowboard)
	Real geometry for a board cutting through powder, built with EditableMesh on the client:
	  - Side banks: a smooth, continuous snow surface along both edges of the board, rising
	    from the terrain under the board's edge to a rounded crest and tucking back under the
	    terrain at its outer edge (no seam). Low at the nose, highest toward the tail, so the
	    nose rides out. The engaged carving edge builds up, the other side flattens; braking
	    pushes snow up at the front; landing swells it; it sinks away in the air.
	  - Groove: a ribbon behind the board with two raised walls (crest above the terrain) and
	    a floor tucked just under the terrain, so the terrain itself is the floor and the walls
	    stand up from it. Walls slump and sink as they age.

	Heights are measured from the terrain under each point (raycasts at the nose, middle and
	tail of the board and along the groove), so the snow always follows the slope. The board,
	boots and bindings are not touched; this only draws snow around them.

	Requires EditableMesh. In a published place that needs the owner's ID verification and
	"Allow Mesh & Image APIs"; PowderWake.Available() returns false when it can't be used and
	the caller falls back to the plain groove trail.

	Mesh layout: one EditableMesh per board (banks + groove), shown through one MeshPart.
	Vertex positions are rewritten every frame (a few hundred SetPosition calls), topology is
	fixed. Two unused anchor vertices pin the mesh bounds so the MeshPart's scale never
	changes; the part is re-centred on the rider every so often.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EffectsConfig = require(ReplicatedStorage.Shared.Config.EffectsConfig)

local Settings = EffectsConfig.Wake

local PowderWake = {}
PowderWake.__index = PowderWake

local available: boolean? = nil
function PowderWake.Available(): boolean
	if available == nil then
		available = pcall(function()
			local probe = AssetService:CreateEditableMesh()
			probe:AddVertex(Vector3.zero)
			probe:Destroy()
		end)
	end
	return available :: boolean
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }

local folder: Folder? = nil
local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "PowderWake"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- Terrain point and normal straight below a world position (nil off the terrain)
local function ground(position: Vector3): (Vector3?, Vector3?)
	local hit = Workspace:Raycast(position + Vector3.yAxis * 3, Vector3.new(0, -7, 0), rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Adds a grid of vertices (rows × columns) with quads between them, faces pointing up.
-- Returns the vertex id grid [row][column].
local function addGrid(mesh, rows: number, columns: number, testRowStep: Vector3, testColumnStep: Vector3)
	local grid = table.create(rows)
	for r = 1, rows do
		local row = table.create(columns)
		for c = 1, columns do
			row[c] = mesh:AddVertex(testRowStep * r + testColumnStep * c)
		end
		grid[r] = row
	end
	-- Pick the winding that faces up for this grid's orientation. A triangle's normal is
	-- (p2 − p1) × (p3 − p1), so (a, b, c) faces up when column × row points up.
	local flip = testColumnStep:Cross(testRowStep).Y < 0
	for r = 1, rows - 1 do
		for c = 1, columns - 1 do
			local a, b, cc, d = grid[r][c], grid[r][c + 1], grid[r + 1][c], grid[r + 1][c + 1]
			if flip then
				mesh:AddTriangle(a, cc, b)
				mesh:AddTriangle(b, cc, d)
			else
				mesh:AddTriangle(a, b, cc)
				mesh:AddTriangle(b, d, cc)
			end
		end
	end
	return grid
end

function PowderWake.new(gear: BasePart)
	local self = setmetatable({}, PowderWake)
	self.Gear = gear
	self.Depth = 0
	self.Swell = 0
	self.Sections = {} -- groove cross-sections, newest first: { Points, Normals, Time }
	self.LastSection = nil :: Vector3?

	local mesh = AssetService:CreateEditableMesh()
	self.Mesh = mesh
	local bound = Settings.Bound
	mesh:AddVertex(Vector3.new(-bound, -bound, -bound))
	mesh:AddVertex(Vector3.new(bound, bound, bound))

	-- Banks: one grid per side (rows along the board, columns outward from the edge).
	-- Built with test steps matching their real orientation so the winding faces up.
	local banks = Settings.Banks
	self.Banks = {}
	for _, side in { -1, 1 } do
		local grid = addGrid(mesh, #banks.Stations, #banks.Profile, Vector3.new(0, 0, 1), Vector3.new(side, 0, 0))
		table.insert(self.Banks, { Side = side, Grid = grid })
	end
	-- Groove: rows = sections (newest first, going backward), columns across left → right
	local groove = Settings.Groove
	self.GrooveGrid = addGrid(mesh, groove.Sections, #groove.Profile, Vector3.new(0, 0, 1), Vector3.new(1, 0, 0))

	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
	part.Name = "PowderWake"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = Settings.CastShadow
	part.Material = Enum.Material.Snow
	part.Color = Settings.Color
	part.Transparency = 1
	part.Parent = getFolder()
	self.Part = part
	self.Origin = gear.Position
	part.CFrame = CFrame.new(self.Origin)
	return self
end

function PowderWake:OnLanded(impact: number)
	self.Swell = math.min(impact * Settings.SwellPerImpact, Settings.MaxSwell)
end

function PowderWake:Destroy()
	self.Part:Destroy()
	self.Mesh:Destroy()
end

local function setPos(self, id: number, world: Vector3)
	self.Mesh:SetPosition(id, world - self.Origin)
end

--[[
	contact: the board is on snow
	steer:   body-frame steer (positive = turning to the body's right)
	speed:   studs/s
	braking: boolean
	switch:  riding switch (the board's +Z end leads)
]]
function PowderWake:Update(dt: number, contact: boolean, steer: number, speed: number, braking: boolean, switch: boolean)
	local gear = self.Gear
	local gcf = gear.CFrame
	local now = os.clock()

	-- Settle in on the snow, sink away quickly in the air
	local target = if contact then 1 else 0
	local rate = if target > self.Depth then Settings.SinkInRate else Settings.LiftOutRate
	self.Depth += (target - self.Depth) * (1 - math.exp(-rate * dt))
	self.Swell *= math.exp(-Settings.SwellRecovery * dt)

	-- Re-centre the mesh when the rider has moved far from its origin
	if (gcf.Position - self.Origin).Magnitude > Settings.Recenter then
		self.Origin = gcf.Position
		self.Part.CFrame = CFrame.new(self.Origin)
	end

	-- Leading direction along the board (the +Z end leads when riding switch)
	local lead = if switch then 1 else -1
	local half = gear.Size.Z / 2
	local width = gear.Size.X / 2

	-- Groove: add a cross-section every Spacing studs while on the snow
	local groove = Settings.Groove
	local tail = gcf * Vector3.new(0, 0, -lead * half)
	if contact and speed > groove.MinSpeed and (not self.LastSection or (tail - self.LastSection).Magnitude >= groove.Spacing) then
		-- Across, to the right of travel (keeps the groove's faces pointing up when switch)
		local across = gcf.RightVector * -lead
		local points, normals = {}, {}
		local valid = true
		for i, column in groove.Profile do
			local p, n = ground(tail + across * (column.X * (width + groove.Extra)))
			if not p then
				valid = false
				break
			end
			points[i], normals[i] = p, n
		end
		if valid then
			table.insert(self.Sections, 1, { Points = points, Normals = normals, Time = now, Strength = self.Depth })
			self.Sections[groove.Sections + 1] = nil
			self.LastSection = tail
		end
	end

	local visible = self.Depth > 0.02 or #self.Sections > 0
	self.Part.Transparency = if visible then 0 else 1
	if not visible then
		return
	end

	-- Banks along the board
	local banks = Settings.Banks
	local carve = math.abs(steer) * math.clamp(speed / Settings.CarveFullSpeed, 0, 1)
	local carveSide = if steer > 0 then 1 elseif steer < 0 then -1 else 0
	local depth = self.Depth * (1 + self.Swell)
	for _, bank in self.Banks do
		local side = bank.Side
		local scale = 1
		if carveSide ~= 0 then
			scale = if side == carveSide then 1 + Settings.CarveRaise * carve else 1 - Settings.CarveLower * carve
		end
		local count = #banks.Stations
		for r = 1, count do
			-- Rows always run toward the board's +Z end (keeps the faces pointing up); the
			-- stations (T: 0 = leading nose … 1 = tail, > 1 just past it) are read in the
			-- matching order
			local station = banks.Stations[if switch then count + 1 - r else r]
			local z = lead * half * (1 - 2 * station.T)
			local crest = banks.Peak * station.Height * scale * depth
			if braking and station.T < 0.4 then
				crest += Settings.BrakeRaise * depth
			end
			-- Terrain under the inner (board edge) and outer columns; interpolate between
			local inner, innerN = ground(gcf * Vector3.new(side * (width - 0.15), 0, z))
			local outer, outerN = ground(gcf * Vector3.new(side * (width + banks.Reach), 0, z))
			if not inner or not outer then
				inner = (gcf * Vector3.new(side * width, -gear.Size.Y / 2, z))
				outer, innerN, outerN = inner, gcf.UpVector, gcf.UpVector
			end
			for c, column in banks.Profile do
				local t = column.T -- 0 = under the board's edge, 1 = outer edge
				local base = inner:Lerp(outer, t)
				local up = innerN:Lerp(outerN, t).Unit
				local h = if depth > 0.02 then crest * column.H + column.Offset else -0.2
				setPos(self, bank.Grid[r][c], base + up * h)
			end
		end
	end

	-- Groove ribbon: walls slump and sink with age; unused rows fold onto the newest section
	local sections = self.Sections
	for r = 1, groove.Sections do
		local section = sections[r] or sections[#sections]
		local row = self.GrooveGrid[r]
		if section then
			local age = now - section.Time
			local life = math.clamp(1 - age / groove.Lifetime, 0, 1)
			local wall = groove.WallHeight * section.Strength * life
			for c, column in groove.Profile do
				local h = if sections[r] then column.Wall * wall + column.Offset - (1 - life) * groove.Sink else -0.3
				setPos(self, row[c], section.Points[c] + section.Normals[c] * h)
			end
		else
			-- No groove yet: hide under the board
			for c in groove.Profile do
				setPos(self, row[c], gcf.Position - Vector3.yAxis * 5)
			end
		end
	end
end

return PowderWake
