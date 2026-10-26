--[[
	PowderWake (prototype, snowboard)
	Real geometry for a board cutting through powder, built with EditableMesh on the client.

	One continuous snow surface: a channel the width of the board with a soft berm on each
	side. It starts at the nose, runs alongside the board and on behind it as the groove, so
	there is no join between "banks" and "groove": every row of the mesh has the same
	cross-section and neighbouring rows share their vertices (and so their shading).
	  - Rows beside the board ("stations", nose → tail): the berms rise from nothing at the
	    nose to full height toward the tail, so the nose rides out. The engaged carving edge
	    builds up and the other side flattens; braking pushes snow up at the front; landing
	    swells it; it sinks away in the air.
	  - The live row follows the tail every frame, so the groove meets the board.
	  - Laid rows: a cross-section is left behind every Spacing studs. Walls slump and sink
	    as they age, and rise and fall a little along the groove.

	Every point is measured from the terrain under it (raycasts), so the snow follows the
	slope. The floor and outer edges dive under the terrain: the terrain itself is the floor
	and the berms stand up from it. Texture coordinates come from world position, so the
	snow texture lines up with the terrain's. The board, boots and bindings are not touched;
	this only draws snow around them.

	Requires EditableMesh. In a published place that needs the owner's ID verification and
	"Allow Mesh & Image APIs"; PowderWake.Available() returns false when it can't be used and
	the caller falls back to the plain groove trail.

	Mesh layout: one EditableMesh per board, shown through one MeshPart. The rows beside the
	board and the live row are rewritten every frame. The laid sections are a ring buffer:
	a new section overwrites the oldest row and only the triangle strips around it are
	re-linked, so the cost doesn't grow with the groove's length; older rows are re-aged a
	few at a time. Two unused anchor vertices pin the mesh bounds so the MeshPart's scale
	never changes; the part is re-centred on the rider every so often.
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

-- Terrain points and normals across the channel at a position (nil if any miss). spread
-- widens (> 1) or narrows the berms on each side.
local function crossSection(center: Vector3, across: Vector3, halfWidth: number, leftSpread: number?, rightSpread: number?)
	local points, normals = {}, {}
	for i, column in Settings.Profile do
		local x = column.X
		if math.abs(x) > 0.5 then
			-- Only the berm's outer slope moves; the channel itself keeps the board's width
			local spread = (if x < 0 then leftSpread else rightSpread) or 1
			x = math.sign(x) * (0.5 + (math.abs(x) - 0.5) * spread)
		end
		local p, n = ground(center + across * (x * halfWidth))
		if not p then
			return nil, nil
		end
		points[i], normals[i] = p, n
	end
	return points, normals
end

-- Cheaper cross-section for the rows beside the board, rewritten every frame: three rays
-- (both outer edges and the middle), the columns in between interpolated
local function quickSection(center: Vector3, across: Vector3, halfWidth: number)
	local mid, midN = ground(center)
	local left, leftN = ground(center - across * halfWidth)
	local right, rightN = ground(center + across * halfWidth)
	if not (mid and left and right) then
		return nil, nil
	end
	local points, normals = {}, {}
	for i, column in Settings.Profile do
		local x = column.X
		if x < 0 then
			points[i], normals[i] = mid:Lerp(left, -x), midN:Lerp(leftN, -x).Unit
		else
			points[i], normals[i] = mid:Lerp(right, x), midN:Lerp(rightN, x).Unit
		end
	end
	return points, normals
end

-- Adds rows × columns vertices (no faces yet), each with its own UV (uvs[vertex]) so the
-- texture can be mapped from world position. Returns the vertex id grid [row][column].
local function addRows(mesh, uvs, rows: number, columns: number)
	local grid = table.create(rows)
	for r = 1, rows do
		local row = table.create(columns)
		for c = 1, columns do
			local id = mesh:AddVertex(Vector3.new(c, 0, r))
			uvs[id] = mesh:AddUV(Vector2.zero)
			row[c] = id
		end
		grid[r] = row
	end
	return grid
end

-- Joins two rows with a strip of quads. front is the row nearer the nose, back the one
-- behind it; columns run left → right of travel. A triangle's normal is
-- (p2 − p1) × (p3 − p1), so in that layout (a, c, b) faces up. Returns the face ids.
local function addStrip(mesh, uvs, front, back)
	local faces = {}
	for c = 1, #front - 1 do
		local a, b, cc, d = front[c], front[c + 1], back[c], back[c + 1]
		for _, tri in { { a, cc, b }, { b, cc, d } } do
			local f = mesh:AddTriangle(tri[1], tri[2], tri[3])
			mesh:SetFaceUVs(f, { uvs[tri[1]], uvs[tri[2]], uvs[tri[3]] })
			table.insert(faces, f)
		end
	end
	return faces
end

function PowderWake.new(gear: BasePart)
	local self = setmetatable({}, PowderWake)
	self.Gear = gear
	self.Depth = 0
	self.Swell = 0
	self.Order = {} -- slots of the laid sections, newest first
	self.Slots = {} -- [slot] = laid section
	self.Links = {} -- [slot] = faces joining that slot's row to the row in front of it
	self.Tick = 0
	self.LastSection = nil :: Vector3?
	self.Travel = math.random() * 100 -- distance along the groove, for the uneven walls

	local mesh = AssetService:CreateEditableMesh()
	self.Mesh = mesh
	self.UV = {}
	local bound = Settings.Bound
	mesh:AddVertex(Vector3.new(-bound, -bound, -bound))
	mesh:AddVertex(Vector3.new(bound, bound, bound))

	-- Rows: the stations beside the board (nose → tail), the live row at the tail, then one
	-- per laid-section slot. Columns across the channel, left → right of travel. The
	-- stations and the live row are joined once; slots are joined as sections are laid.
	local stations = #Settings.Stations
	self.StationCount = stations
	self.Grid = addRows(mesh, self.UV, stations + 1 + Settings.Sections, #Settings.Profile)
	for r = 1, stations do
		addStrip(mesh, self.UV, self.Grid[r], self.Grid[r + 1])
	end
	self.LiveRow = self.Grid[stations + 1]

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

-- Texture mapped from world position (top-down), so it lines up with the terrain's snow
local uvScale = 1 / Settings.StudsPerTile
local function setPos(self, id: number, world: Vector3)
	self.Mesh:SetPosition(id, world - self.Origin)
	self.Mesh:SetUV(self.UV[id], Vector2.new(world.X * uvScale, world.Z * uvScale))
end

-- Writes one row across the channel: leftWall / rightWall = studs the berm on each side
-- rises above the terrain; sink = studs the whole row has sunk
local function writeRow(self, row, points, normals, leftWall: number, rightWall: number, sink: number)
	for c, column in Settings.Profile do
		local wall = if column.X < 0 then leftWall else rightWall
		setPos(self, row[c], points[c] + normals[c] * (column.Wall * wall + column.Offset - sink))
	end
end

-- Folds a row out of sight onto one point
local function hideRow(self, row, point: Vector3)
	for _, id in row do
		setPos(self, id, point)
	end
end

local function slotRow(self, slot: number)
	return self.Grid[self.StationCount + 1 + slot]
end

local function unlink(self, slot: number)
	local faces = self.Links[slot]
	if faces then
		for _, f in faces do
			self.Mesh:RemoveFace(f)
		end
		self.Links[slot] = nil
	end
end

-- Writes a laid section's row. ordinal: 1 = newest; the last TaperRows rows of the groove
-- shrink to nothing so it doesn't end abruptly. uv: also rewrite texture coordinates (only
-- needed when the row gets a new section)
local function writeSection(self, slot: number, ordinal: number, now: number, uv: boolean)
	local section = self.Slots[slot]
	local life = math.clamp(1 - (now - section.Time) / Settings.Lifetime, 0, 1)
	local taper = math.clamp((#self.Order - ordinal) / Settings.TaperRows, 0, 1)
	local wall = Settings.WallHeight * section.Strength * life * taper
	local sink = (1 - life) * Settings.Sink
	local mesh, origin = self.Mesh, self.Origin
	for c, column in Settings.Profile do
		local side = if column.X < 0 then section.Left else section.Right
		local id = slotRow(self, slot)[c]
		local world = section.Points[c] + section.Normals[c] * (column.Wall * wall * side + column.Offset - sink)
		if uv then
			setPos(self, id, world)
		else
			mesh:SetPosition(id, world - origin)
		end
	end
end

-- Lays a new section: it takes the oldest slot when the ring is full and is linked between
-- the live row and the previous newest (unless it starts a new groove after a jump)
local function lay(self, section, now: number)
	local order = self.Order
	local slot
	if #order >= Settings.Sections then
		slot = table.remove(order)
		unlink(self, slot)
	else
		slot = #order + 1
	end
	local previous = order[1]
	if previous then
		unlink(self, previous)
		if not section.Start then
			self.Links[previous] = addStrip(self.Mesh, self.UV, slotRow(self, slot), slotRow(self, previous))
		end
	end
	table.insert(order, 1, slot)
	self.Slots[slot] = section
	self.Links[slot] = addStrip(self.Mesh, self.UV, self.LiveRow, slotRow(self, slot))
	writeSection(self, slot, 1, now, true)
	-- The tail end of the groove tapers: those rows change with every new section
	for i = math.max(2, #order - Settings.TaperRows), #order do
		writeSection(self, order[i], i, now, false)
	end
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
		for i, slot in self.Order do
			writeSection(self, slot, i, now, false)
		end
	end

	-- Leading direction along the board (the +Z end leads when riding switch); across = to
	-- the right of travel
	local lead = if switch then 1 else -1
	local half = gear.Size.Z / 2
	local across = gcf.RightVector * -lead
	local halfWidth = gear.Size.X / 2 + Settings.Extra
	local tail = gcf * Vector3.new(0, 0, -lead * half)

	-- Carving: the engaged edge builds up, the other side flattens (kept in the groove too)
	local carve = math.abs(steer) * math.clamp(speed / Settings.CarveFullSpeed, 0, 1)
	local carveSide = if steer > 0 then 1 elseif steer < 0 then -1 else 0
	local function sideScale(side: number): number
		if carveSide == 0 then
			return 1
		end
		return if side == carveSide then 1 + Settings.CarveRaise * carve else 1 - Settings.CarveLower * carve
	end

	-- Live row at the tail; lay a section every Spacing studs travelled
	local live = nil
	if contact then
		local start = self.LastSection == nil
		local moved = if self.LastSection then (tail - self.LastSection).Magnitude else Settings.Spacing
		local travel = self.Travel + moved
		-- The berms rise and fall and wander in and out along the groove (two octaves)
		local scale = Settings.WobbleScale
		local function wobble(seed: number): number
			return math.noise(travel * scale, seed) + 0.5 * math.noise(travel * scale * 3.1, seed + 20)
		end
		local points, normals = crossSection(tail, across, halfWidth, 1 + Settings.Spread * wobble(40.5), 1 + Settings.Spread * wobble(60.5))
		if points then
			live = {
				Points = points,
				Normals = normals,
				Time = now,
				Strength = self.Depth * (1 + self.Swell), -- landings leave a bigger rim
				Start = start, -- first section after a jump: not joined to the old groove
				Left = (1 + Settings.Wobble * wobble(0.5)) * sideScale(-1),
				Right = (1 + Settings.Wobble * wobble(7.5)) * sideScale(1),
			}
			if moved >= Settings.Spacing then
				self.Travel = travel
				self.LastSection = tail
				lay(self, live, now)
			end
		end
	else
		-- Off the snow: the next contact starts a new groove rather than bridging the gap
		self.LastSection = nil
	end

	local order = self.Order
	local newest = if order[1] then self.Slots[order[1]] else nil
	local depth = self.Depth * (1 + self.Swell)
	local visible = depth > 0.02 or newest ~= nil
	self.Part.Transparency = if visible then 0 else 1
	if not visible then
		return
	end
	local grid = self.Grid
	local stations = self.StationCount

	-- Live row at the tail. In the air it folds onto the newest laid row, and the rows
	-- beside the board fold onto it, so nothing is left hanging around the board.
	if live then
		writeRow(self, self.LiveRow, live.Points, live.Normals, Settings.WallHeight * live.Strength * live.Left, Settings.WallHeight * live.Strength * live.Right, 0)
	elseif newest then
		local newestRow = slotRow(self, order[1])
		for c, id in self.LiveRow do
			setPos(self, id, self.Mesh:GetPosition(newestRow[c]) + self.Origin)
		end
	else
		hideRow(self, self.LiveRow, gcf.Position - Vector3.yAxis * 5)
	end

	-- Stations beside the board: berms grow from the nose toward the tail (shaped like the
	-- live row: carve and unevenness); braking piles snow at the front
	local stationsWritten = false
	if depth > 0.02 and live then
		local wallHeight = Settings.WallHeight * depth
		local left = wallHeight * live.Left
		local right = wallHeight * live.Right
		stationsWritten = true
		for r, station in Settings.Stations do
			local z = lead * half * (1 - 2 * station.T)
			local points, normals = quickSection(gcf * Vector3.new(0, 0, z), across, halfWidth)
			if not points then
				stationsWritten = false
				break
			end
			local extra = if braking and station.T < 0.4 then Settings.BrakeRaise * depth else 0
			writeRow(self, grid[r], points, normals, left * station.Height + extra, right * station.Height + extra, 0)
		end
	end
	if not stationsWritten then
		for r = 1, stations do
			for c, id in grid[r] do
				self.Mesh:SetPosition(id, self.Mesh:GetPosition(self.LiveRow[c]))
			end
		end
	end

	-- Laid rows slump and sink with age: re-age a share of them each frame
	self.Tick += 1
	local stride = Settings.AgeStride
	local phase = self.Tick % stride
	for i, slot in order do
		if slot % stride == phase then
			writeSection(self, slot, i, now, false)
		end
	end
end

return PowderWake
