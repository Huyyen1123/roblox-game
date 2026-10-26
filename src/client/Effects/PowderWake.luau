--[[
	PowderWake (prototype)
	Real geometry for skis and snowboards moving through powder, built with EditableMesh on
	the client. One mesh per rider, with one "channel" per piece of gear: two narrow ones
	for skis, one wide one for a board.

	Each channel is one continuous snow surface: a track the width of the gear with a soft
	shoulder on each side. It starts at the nose, runs alongside the gear and on behind it,
	so there is no join between the snow around the gear and the track: every row has the
	same cross-section and neighbouring rows share their vertices (and so their shading).
	  - Rows beside the gear ("stations", nose → tail): the powder the gear is pushing
	    through. Deeper than the track it leaves: it climbs to the gear's edges so the gear
	    looks partly submerged, rising from nothing at the nose (the nose and top stay
	    visible) and growing with speed. Carving pushes it up and outward on the engaged
	    edge; braking piles it at the front; landing swells it; it falls away in the air.
	  - The live row follows the tail every frame, so the track meets the gear.
	  - Laid rows: a cross-section is left every Spacing studs. The track's rims are low,
	    soft and uneven, slump and sink as they age, and the end tapers off.

	Every point is measured from the terrain under it (raycasts), so the snow follows turns
	and uneven slopes. The track floor and the outer edges dive under the terrain: the
	terrain itself (with the groove trail's shading) is the floor, and the rims rise gently
	from it. The inner walls are tinted blue-grey (compressed, shadowed snow); the rest
	matches the terrain's snow, with texture coordinates from world position so the texture
	lines up too, and the outer shoulders fade out (vertex alpha) so there is no hard line
	where the snow meets the terrain. The gear, boots and bindings are not touched; this only draws snow.

	Requires EditableMesh. In a published place that needs the owner's ID verification and
	"Allow Mesh & Image APIs"; PowderWake.Available() returns false when it can't be used and
	the caller falls back to the plain groove trail.

	Mesh layout: all faces are made once; after that only vertices move (adding and
	removing faces is far more expensive). The rows beside the gear are rewritten every
	frame. The track is a ring of rows joined in a loop: the head row follows the tail, and
	every Spacing studs it is left behind and the next row becomes the head, overwriting
	the oldest. The two rows in front of the head are collapsed to single points, so the
	strip where the loop closes has no area; a break after a jump is two more collapsed
	rows. Older rows are re-aged a few at a time. Two unused anchor vertices pin the mesh
	bounds so the MeshPart's scale never changes; the part is re-centred every so often.
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

-- Columns across a channel, left → right of travel, from a kind's one-sided profile
-- (centre outward). Lateral = studs from the gear's centre line.
local function buildColumns(kind, gearHalfWidth: number)
	local columns = {}
	local profile = kind.Profile
	for i = #profile, 1, -1 do
		local p = profile[i]
		table.insert(columns, { Side = -1, D = p.D, Wall = p.Wall, Offset = p.Offset, Shade = p.Shade or 0, Alpha = p.Alpha or 1 })
	end
	for _, p in profile do
		table.insert(columns, { Side = 1, D = p.D, Wall = p.Wall, Offset = p.Offset, Shade = p.Shade or 0, Alpha = p.Alpha or 1 })
	end
	for _, column in columns do
		column.Lateral = column.Side * (gearHalfWidth + column.D)
	end
	return columns
end

-- Lateral position of a column; spread widens (> 1) or narrows the shoulder beyond the crest
local function lateral(channel, column, leftSpread: number, rightSpread: number): number
	local crest = channel.Kind.Crest
	if column.D <= crest then
		return column.Lateral
	end
	local spread = if column.Side < 0 then leftSpread else rightSpread
	return column.Side * (channel.HalfWidth + crest + (column.D - crest) * spread)
end

-- Terrain points and normals across the channel (one ray per column; nil if any miss)
local function crossSection(channel, center: Vector3, across: Vector3, leftSpread: number, rightSpread: number)
	local points, normals = {}, {}
	for i, column in channel.Columns do
		local p, n = ground(center + across * lateral(channel, column, leftSpread, rightSpread))
		if not p then
			return nil, nil
		end
		points[i], normals[i] = p, n
	end
	return points, normals
end

-- Cheaper cross-section for the rows beside the gear, rewritten every frame: three rays
-- (both outer edges and the middle), the columns in between interpolated
local function quickSection(channel, center: Vector3, across: Vector3, leftSpread: number, rightSpread: number)
	local columns = channel.Columns
	local leftEdge = lateral(channel, columns[1], leftSpread, rightSpread)
	local rightEdge = lateral(channel, columns[#columns], leftSpread, rightSpread)
	local mid, midN = ground(center)
	local left, leftN = ground(center + across * leftEdge)
	local right, rightN = ground(center + across * rightEdge)
	if not (mid and left and right) then
		return nil, nil
	end
	local points, normals = {}, {}
	for i, column in columns do
		local x = lateral(channel, column, leftSpread, rightSpread)
		if x < 0 then
			local t = x / leftEdge
			points[i], normals[i] = mid:Lerp(left, t), midN:Lerp(leftN, t).Unit
		else
			local t = x / rightEdge
			points[i], normals[i] = mid:Lerp(right, t), midN:Lerp(rightN, t).Unit
		end
	end
	return points, normals
end

-- Adds rows × columns vertices (no faces yet). Each vertex gets its own UV (uvs[vertex]) so
-- the texture can be mapped from world position, and a colour and opacity from its column
-- (the outer shoulder fades into the terrain).
local function addRows(self, rows: number, columns)
	local mesh = self.Mesh
	local grid = table.create(rows)
	for r = 1, rows do
		local row = table.create(#columns)
		for c, column in columns do
			local id = mesh:AddVertex(Vector3.new(c, 0, r))
			self.UV[id] = mesh:AddUV(Vector2.zero)
			self.Colors[id] = mesh:AddColor(Color3.new(1, 1, 1):Lerp(Settings.ShadeColor, column.Shade), column.Alpha)
			row[c] = id
		end
		grid[r] = row
	end
	return grid
end

-- Joins two rows with a strip of quads. front is the row nearer the nose, back the one
-- behind it; columns run left → right of travel. A triangle's normal is
-- (p2 − p1) × (p3 − p1), so in that layout (a, c, b) faces up. Returns the face ids.
local function addStrip(self, front, back)
	local mesh, uvs, colors = self.Mesh, self.UV, self.Colors
	local faces = {}
	for c = 1, #front - 1 do
		local a, b, cc, d = front[c], front[c + 1], back[c], back[c + 1]
		for _, tri in { { a, cc, b }, { b, cc, d } } do
			local f = mesh:AddTriangle(tri[1], tri[2], tri[3])
			mesh:SetFaceUVs(f, { uvs[tri[1]], uvs[tri[2]], uvs[tri[3]] })
			mesh:SetFaceColors(f, { colors[tri[1]], colors[tri[2]], colors[tri[3]] })
			table.insert(faces, f)
		end
	end
	return faces
end

-- gears: the Ski parts or the Board part of one rider
function PowderWake.new(gears: { BasePart })
	local self = setmetatable({}, PowderWake)
	self.Depth = 0
	self.Swell = 0

	local mesh = AssetService:CreateEditableMesh()
	self.Mesh = mesh
	self.UV = {}
	self.Colors = {}
	local bound = Settings.Bound
	mesh:AddVertex(Vector3.new(-bound, -bound, -bound))
	mesh:AddVertex(Vector3.new(bound, bound, bound))

	-- One channel per piece of gear: the station rows beside the gear (nose → tail, the last
	-- one at the tail), and the track's ring of rows. All faces are made here, once.
	self.Channels = {}
	local hidden = gears[1].Position - Vector3.yAxis * 50
	for _, gear in gears do
		local kind = Settings.Kinds[gear.Name] or Settings.Kinds.Board
		local channel = {
			Gear = gear,
			Kind = kind,
			HalfWidth = gear.Size.X / 2,
			Contents = {}, -- [ring row] = laid section, or { Cap = point }
			Order = {}, -- ring rows holding sections, newest first
			Head = 1, -- ring row at the tail of the gear (the live row while on the snow)
			LastSection = nil :: Vector3?,
			Travel = math.random() * 100, -- distance along the track, for the uneven rims
		}
		channel.Columns = buildColumns(kind, channel.HalfWidth)
		local stations = #Settings.Stations
		channel.Stations = addRows(self, stations + 1, channel.Columns)
		for r = 1, stations do
			addStrip(self, channel.Stations[r], channel.Stations[r + 1])
		end
		-- Ring: rows joined in a loop, each to the next (older) one, the last back to the
		-- first. Two rows in front of the head are always collapsed to single points, so
		-- the strip where the loop closes has no area.
		local count = kind.Sections + 2
		channel.Ring = addRows(self, count, channel.Columns)
		for i = 1, count do
			addStrip(self, channel.Ring[i], channel.Ring[i % count + 1])
		end
		for i = 1, count do
			channel.Contents[i] = { Cap = hidden }
		end
		table.insert(self.Channels, channel)
	end
	self.Tick = 0

	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
	part.Name = "PowderWake"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = Settings.CastShadow
	part.Material = Enum.Material.Snow
	part.Color = Workspace.Terrain:GetMaterialColor(Enum.Material.Snow)
	part.Transparency = 1 -- shown on the first update
	part.Parent = getFolder()
	self.Part = part
	self.Origin = gears[1].Position
	part.CFrame = CFrame.new(self.Origin)
	-- Everything starts collapsed out of sight
	for _, channel in self.Channels do
		for _, row in channel.Ring do
			for _, id in row do
				mesh:SetPosition(id, hidden - self.Origin)
			end
		end
		for _, row in channel.Stations do
			for _, id in row do
				mesh:SetPosition(id, hidden - self.Origin)
			end
		end
	end
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

-- Writes one row across a channel: leftWall / rightWall = studs the snow on each side rises
-- above the terrain; sink = studs the whole row has sunk
local function writeRow(self, channel, row, points, normals, leftWall: number, rightWall: number, sink: number)
	for c, column in channel.Columns do
		local wall = if column.Side < 0 then leftWall else rightWall
		setPos(self, row[c], points[c] + normals[c] * (column.Wall * wall + column.Offset - sink))
	end
end

local function ringIndex(channel, i: number): number
	local count = #channel.Ring
	return (i - 1) % count + 1
end

-- A point under the terrain in the middle of a ring row (where its caps collapse to)
local function capPoint(channel, index: number): Vector3
	local content = channel.Contents[index]
	if content.Cap then
		return content.Cap
	end
	local middle = #channel.Columns // 2
	return content.Points[middle]:Lerp(content.Points[middle + 1], 0.5) - content.Normals[middle] * 0.4
end

local function collapse(self, channel, index: number, point: Vector3)
	channel.Contents[index] = { Cap = point }
	local mesh, local_ = self.Mesh, point - self.Origin
	for _, id in channel.Ring[index] do
		mesh:SetPosition(id, local_)
	end
end

-- Writes a ring row holding a laid section. ordinal: 1 = newest; the last TaperRows rows
-- shrink to nothing so the track doesn't end abruptly. uv: also rewrite texture
-- coordinates (only needed when the row gets new content)
local function writeSection(self, channel, index: number, ordinal: number, now: number, uv: boolean)
	local section = channel.Contents[index]
	local kind = channel.Kind
	local life = math.clamp(1 - (now - section.Time) / Settings.Lifetime, 0, 1)
	local taper = math.clamp((#channel.Order - ordinal) / Settings.TaperRows, 0, 1)
	local wall = kind.TrackHeight * section.Strength * life * taper
	local sink = (1 - life) * Settings.Sink
	local mesh, origin = self.Mesh, self.Origin
	local row = channel.Ring[index]
	for c, column in channel.Columns do
		local side = if column.Side < 0 then section.Left else section.Right
		local world = section.Points[c] + section.Normals[c] * (column.Wall * wall * side + column.Offset - sink)
		if uv then
			setPos(self, row[c], world)
		else
			mesh:SetPosition(row[c], world - origin)
		end
	end
end

-- Keeps the two rows in front of the head collapsed: one under the head, one under the
-- oldest row (the end of the track)
local function capFront(self, channel)
	local head = channel.Head
	collapse(self, channel, ringIndex(channel, head - 1), capPoint(channel, head))
	collapse(self, channel, ringIndex(channel, head - 2), capPoint(channel, ringIndex(channel, head - 3)))
end

-- Moves the head one row forward around the ring and gives it new content: a section (the
-- new live row) or a cap point (a break in the track after a jump). The row it takes over
-- was one of the collapsed ones; the oldest section drops off the end.
local function advance(self, channel, content, now: number)
	channel.Head = ringIndex(channel, channel.Head - 1)
	local head = channel.Head
	local order = channel.Order
	-- Rows about to be collapsed / overwritten are the oldest: drop them from the order
	local front, endCap = ringIndex(channel, head - 1), ringIndex(channel, head - 2)
	while order[#order] == head or order[#order] == front or order[#order] == endCap do
		table.remove(order)
	end
	if content.Cap then
		collapse(self, channel, head, content.Cap)
	else
		channel.Contents[head] = content
		table.insert(order, 1, head)
		writeSection(self, channel, head, 1, now, true)
	end
	capFront(self, channel)
	-- The end of the track tapers: those rows change with every new section
	for i = math.max(2, #order - Settings.TaperRows), #order do
		writeSection(self, channel, order[i], i, now, false)
	end
end

local function updateChannel(self, channel, now: number, contact: boolean, carve: number, carveSide: number, speed: number, braking: boolean, switch: boolean)
	local gear = channel.Gear
	local kind = channel.Kind
	local gcf = gear.CFrame

	-- Leading direction along the gear (the +Z end leads when riding switch); across = to
	-- the right of travel
	local lead = if switch then 1 else -1
	local half = gear.Size.Z / 2
	local across = gcf.RightVector * -lead
	local tail = gcf * Vector3.new(0, 0, -lead * half)

	-- Carving: the engaged edge builds up and pushes outward; the other side flattens
	local function sideScale(side: number): number
		if carveSide == 0 then
			return 1
		end
		return if side == carveSide then 1 + Settings.CarveRaise * carve else 1 - Settings.CarveLower * carve
	end
	local function sidePush(side: number): number
		return if side == carveSide then 1 + Settings.CarvePush * carve else 1
	end

	-- Live row at the tail: the head of the ring follows it; every Spacing studs the head
	-- is left behind as a laid section and a new head starts
	local live = nil
	if contact then
		local start = channel.LastSection == nil
		local moved = if channel.LastSection then (tail - channel.LastSection).Magnitude else kind.Spacing
		local travel = channel.Travel + moved
		-- The rims rise and fall and wander in and out along the track (two octaves)
		local scale = Settings.WobbleScale
		local function wobble(seed: number): number
			return math.noise(travel * scale, seed) + 0.5 * math.noise(travel * scale * 3.1, seed + 20)
		end
		local leftSpread = (1 + Settings.Spread * wobble(40.5)) * sidePush(-1)
		local rightSpread = (1 + Settings.Spread * wobble(60.5)) * sidePush(1)
		local points, normals = crossSection(channel, tail, across, leftSpread, rightSpread)
		if points then
			live = {
				Points = points,
				Normals = normals,
				Time = now,
				Strength = self.Depth * (1 + self.Swell), -- landings leave a bigger rim
				Left = (1 + Settings.Wobble * wobble(0.5)) * sideScale(-1),
				Right = (1 + Settings.Wobble * wobble(7.5)) * sideScale(1),
				LeftSpread = leftSpread,
				RightSpread = rightSpread,
			}
			if start then
				-- A new track: break it off the old one with two caps (under the old track's
				-- end and under the new start), whose joining strip has no area
				if channel.Order[1] then
					advance(self, channel, { Cap = capPoint(channel, channel.Head) }, now)
				end
				local middle = #channel.Columns // 2
				advance(self, channel, { Cap = points[middle]:Lerp(points[middle + 1], 0.5) - normals[middle] * 0.4 }, now)
				advance(self, channel, live, now)
				channel.LastSection = tail
				channel.Travel = travel
			elseif moved >= kind.Spacing then
				-- The head stays where it is (it was written last frame); a new head starts
				channel.Travel = travel
				channel.LastSection = tail
				advance(self, channel, live, now)
			else
				channel.Contents[channel.Head] = live
				writeSection(self, channel, channel.Head, 1, now, true)
				capFront(self, channel)
			end
		end
	else
		-- Off the snow: the next contact starts a new track rather than bridging the gap
		channel.LastSection = nil
	end

	local depth = self.Depth * (1 + self.Swell)
	local mesh = self.Mesh
	local stations = channel.Stations
	local headRow = channel.Ring[channel.Head]

	-- The last station row sits exactly on the head, so the snow beside the gear runs
	-- into the track
	local last = stations[#stations]
	for c, id in last do
		setPos(self, id, mesh:GetPosition(headRow[c]) + self.Origin)
	end

	-- Stations beside the gear: the powder it's pushing through, deeper than the track (it
	-- settles to the track's rim height at the tail) and growing with speed
	local written = false
	if depth > 0.02 and live then
		local moving = Settings.StandingShare + (1 - Settings.StandingShare) * math.clamp(speed / Settings.BuildUpSpeed, 0, 1)
		local buildUp = kind.BuildUp * depth * moving
		local track = kind.TrackHeight * live.Strength
		written = true
		for r, station in Settings.Stations do
			local z = lead * half * (1 - 2 * station.T)
			local points, normals = quickSection(channel, gcf * Vector3.new(0, 0, z), across, live.LeftSpread, live.RightSpread)
			if not points then
				written = false
				break
			end
			local height = buildUp * station.Height + (track - buildUp) * station.Settle
			local extra = if braking and station.T < 0.4 then Settings.BrakeRaise * depth else 0
			writeRow(self, channel, stations[r], points, normals, height * live.Left + extra, height * live.Right + extra, 0)
		end
	end
	if not written then
		-- In the air (or off the terrain): fold onto the end of the track
		for r = 1, #stations - 1 do
			for c, id in stations[r] do
				mesh:SetPosition(id, mesh:GetPosition(last[c]))
			end
		end
	end
end

--[[
	contact: the gear is on snow
	steer:   body-frame steer (positive = turning to the body's right)
	speed:   studs/s
	braking: boolean
	switch:  riding switch (the gear's +Z end leads)
]]
function PowderWake:Update(dt: number, contact: boolean, steer: number, speed: number, braking: boolean, switch: boolean)
	local now = os.clock()

	-- Settle in on the snow, fall away quickly in the air
	local target = if contact then 1 else 0
	local rate = if target > self.Depth then Settings.SinkInRate else Settings.LiftOutRate
	self.Depth += (target - self.Depth) * (1 - math.exp(-rate * dt))
	self.Swell *= math.exp(-Settings.SwellRecovery * dt)

	-- Re-centre the mesh when the rider has moved far from its origin
	local position = self.Channels[1].Gear.Position
	if (position - self.Origin).Magnitude > Settings.Recenter then
		self.Origin = position
		self.Part.CFrame = CFrame.new(self.Origin)
		for _, channel in self.Channels do
			for index, content in channel.Contents do
				if content.Cap then
					collapse(self, channel, index, content.Cap)
				end
			end
			for i, index in channel.Order do
				writeSection(self, channel, index, i, now, false)
			end
		end
	end

	local carve = math.abs(steer) * math.clamp(speed / Settings.CarveFullSpeed, 0, 1)
	local carveSide = if steer > 0 then 1 elseif steer < 0 then -1 else 0
	local visible = self.Depth > 0.02
	for _, channel in self.Channels do
		updateChannel(self, channel, now, contact, carve, carveSide, speed, braking, switch)
		visible = visible or channel.Order[1] ~= nil
	end
	self.Part.Transparency = if visible then Settings.Transparency else 1

	-- Laid rows slump and sink with age: re-age a share of them each frame
	self.Tick += 1
	local stride = Settings.AgeStride
	local phase = self.Tick % stride
	for _, channel in self.Channels do
		for i, index in channel.Order do
			if index % stride == phase and not (contact and i == 1) then
				writeSection(self, channel, index, i, now, false)
			end
		end
	end
end

return PowderWake
