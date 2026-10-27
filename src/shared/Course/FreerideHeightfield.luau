--[[
	FreerideHeightfield
	Height and surface for an open freeride mountain (see Config/Courses/SummitRidge), with the
	same interface TerrainBuilder and CourseService use for Frostpeak's Heightfield:
	GetHeight, GetNormal, GetSlope, GetBounds, GetUprightCFrame, CenterX, ChooseMaterial, MinY.

	Height(x, z) = fall-line profile
	             + per-corridor shaping (rollovers in the centre, pitches and benches on the right)
	             + rounded ridgelines between corridors
	             + overall bowl curvature and the rocky boundary walls
	             + natural relief (large swells, wind ridges along the fall line, rounded drifts,
	               snowbanks at the foot of the walls), calmed around the start and finish
	             + features (World.Features): natural kickers shaped into the snow, and a
	               frozen lake flattened into the valley

	Shared (client and server): the server bakes the terrain and builds the scenery from it,
	and the client draws the minimap from the same data.

	Noise is a small self-contained value noise (not math.noise), so tools outside Roblox can
	reproduce the exact same mountain (e.g. to render the minimap image offline).
]]

local PROFILE_STEP = 8

local FreerideHeightfield = {}
FreerideHeightfield.__index = FreerideHeightfield

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Deterministic hash of a lattice point to [-1, 1]
local function hash(ix: number, iz: number, seed: number): number
	local s = math.sin(ix * 127.1 + iz * 311.7 + seed * 74.7) * 43758.5453
	return (s - math.floor(s)) * 2 - 1
end

-- Smooth value noise in [-1, 1]
local function valueNoise(x: number, z: number, seed: number): number
	local ix, iz = math.floor(x), math.floor(z)
	local fx, fz = x - ix, z - iz
	local ux, uz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
	local a = hash(ix, iz, seed)
	local b = hash(ix + 1, iz, seed)
	local c = hash(ix, iz + 1, seed)
	local d = hash(ix + 1, iz + 1, seed)
	return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz
end

local function fbm(x: number, z: number, seed: number, octaves: number): number
	local sum, amplitude, total = 0, 1, 0
	for i = 0, octaves - 1 do
		sum += valueNoise(x, z, seed + i * 13) * amplitude
		total += amplitude
		amplitude *= 0.5
		x *= 2.03
		z *= 2.03
	end
	return sum / total
end

function FreerideHeightfield.new(course)
	local self = setmetatable({}, FreerideHeightfield)
	self.Course = course
	self.World = course.World
	self.Seed = course.Seed % 1000 + 0.5
	local world = course.World
	local bounds = world.Bounds

	-- Integrate the fall-line profile, then smooth it so slope changes are gradual
	local z0 = -bounds.Uphill
	local count = math.ceil((bounds.Downhill - z0) / PROFILE_STEP)
	local angles = table.create(count, 0)
	for i = 1, count do
		local z = z0 + (i - 0.5) * PROFILE_STEP
		local angle = world.Profile[1].Angle
		for _, segment in world.Profile do
			if z >= segment.FromZ then
				angle = segment.Angle
			end
		end
		angles[i] = angle
	end
	local radius = math.max(1, math.floor(world.TransitionLength / 2 / PROFILE_STEP))
	local profile = table.create(count + 1, 0)
	-- Height at z = 0 equals StartY
	local raw = table.create(count + 1, 0)
	for i = 1, count do
		local sum, n = 0, 0
		for j = math.max(1, i - radius), math.min(count, i + radius) do
			sum += angles[j]
			n += 1
		end
		raw[i + 1] = raw[i] - math.tan(math.rad(sum / n)) * PROFILE_STEP
	end
	local zeroIndex = (0 - z0) / PROFILE_STEP + 1
	local i0 = math.floor(zeroIndex)
	local atZero = raw[i0] + (raw[i0 + 1] - raw[i0]) * (zeroIndex - i0)
	for i = 1, count + 1 do
		profile[i] = raw[i] - atZero + course.StartY
	end
	self.ProfileStart = z0
	self.Profile = profile

	-- Base drop per step-period on the right corridor (matches the corridor zone's slope)
	local corridors = world.Corridors
	local slope = math.tan(math.rad(11))
	for _, segment in world.Profile do
		if segment.FromZ == corridors.StartZ then
			slope = math.tan(math.rad(segment.Angle))
		end
	end
	self.StepDrop = slope * corridors.Steps.Period

	-- Features: kickers are placed once (their centre line is fixed at the lip), the lake's
	-- water level is the lowest ground inside it
	local features = world.Features or {}
	self.Kickers = {}
	for _, kicker in features.Kickers or {} do
		table.insert(self.Kickers, {
			X = self:FeatureX(kicker),
			Z = kicker.Z,
			Height = kicker.Height,
			Length = kicker.Length,
			Width = kicker.Width,
			Drop = kicker.Length * (kicker.DropShare or 0.5),
			Name = kicker.Name,
		})
	end
	local lake = features.Lake
	if lake then
		local level = math.huge
		for a = 0, 2 * math.pi, math.pi / 12 do
			for r = 0, 1, 0.25 do
				local x = lake.X + math.cos(a) * lake.RadiusX * r
				local z = lake.Z + math.sin(a) * lake.RadiusZ * r
				level = math.min(level, self:BaseHeight(x, z))
			end
		end
		self.Lake = { X = lake.X, Z = lake.Z, RadiusX = lake.RadiusX, RadiusZ = lake.RadiusZ, Shore = lake.Shore, Level = level - lake.Depth }
	end

	-- Lowest generated point, for the kill plane
	local minY = math.huge
	for x = -bounds.HalfWidth, bounds.HalfWidth, 64 do
		for z = -bounds.Uphill, bounds.Downhill, 64 do
			minY = math.min(minY, self:GetHeight(x, z))
		end
	end
	self.MinY = minY - 40
	return self
end

function FreerideHeightfield:ProfileY(z: number): number
	local f = (z - self.ProfileStart) / PROFILE_STEP + 1
	local profile = self.Profile
	local i = math.clamp(math.floor(f), 1, #profile - 1)
	local t = math.clamp(f - i, 0, 1)
	return profile[i] + (profile[i + 1] - profile[i]) * t
end

-- The freeride map has no racing line; spawns and markers centre on X = 0.
function FreerideHeightfield:CenterX(_z: number): number
	return 0
end

-- 0 outside the corridor zone, rising to 1 over FadeLength at each end.
function FreerideHeightfield:CorridorEnvelope(z: number): number
	local c = self.World.Corridors
	return smoothstep(c.StartZ, c.StartZ + c.FadeLength, z) * (1 - smoothstep(c.EndZ - c.FadeLength, c.EndZ, z))
end

function FreerideHeightfield:CorridorCenter(index: number, z: number): number
	local c = self.World.Corridors
	local wave = math.sin(2 * math.pi * z / c.Meander.Wavelength + index * 2.1)
	return c.Centers[index] + c.Meander.Amplitude * wave
end

-- Height change each corridor applies relative to the base profile (studs).
function FreerideHeightfield:CorridorShape(index: number, z: number): number
	local c = self.World.Corridors
	if index == 2 then
		return c.Roller.Amplitude * math.sin(2 * math.pi * (z - c.StartZ) / c.Roller.Wavelength)
	elseif index == 3 then
		-- Pitches and benches: the same drop per period as the base slope, but taken in a
		-- smooth steep step followed by a near-flat bench
		local u = ((z - c.StartZ) % c.Steps.Period) / c.Steps.Period
		local pitch = c.Steps.Pitch
		local drop = 0.5 - 0.5 * math.cos(math.pi * math.min(u / pitch, 1))
		return self.StepDrop * (u - drop)
	end
	return 0
end

-- X of a feature given either directly (X) or as a corridor plus an offset from its centre
function FreerideHeightfield:FeatureX(feature): number
	if feature.X then
		return feature.X
	end
	return self:CorridorCenter(feature.Corridor, feature.Z) + (feature.Offset or 0)
end

-- Height a kicker adds: a curved ramp rising to its lip, then a short drop back to the slope
local function kickerHeight(kicker, x: number, z: number): number
	local u = z - kicker.Z
	if u < -kicker.Length or u > kicker.Drop then
		return 0
	end
	local half = kicker.Width / 2
	local across = math.abs(x - kicker.X)
	local shoulder = 14
	if across > half + shoulder then
		return 0
	end
	local lateral = 1 - smoothstep(half, half + shoulder, across)
	local along
	if u <= 0 then
		local t = (u + kicker.Length) / kicker.Length
		along = t * t
	else
		along = 1 - smoothstep(0, kicker.Drop, u)
	end
	return kicker.Height * along * lateral
end

function FreerideHeightfield:GetHeight(x: number, z: number): number
	local height = self:BaseHeight(x, z)
	for _, kicker in self.Kickers do
		height += kickerHeight(kicker, x, z)
	end
	local lake = self.Lake
	if lake then
		local dx, dz = (x - lake.X) / lake.RadiusX, (z - lake.Z) / lake.RadiusZ
		local r = math.sqrt(dx * dx + dz * dz)
		if r < 1 + lake.Shore then
			-- Flat ice inside, a soft shore blending back to the ground outside
			local blend = 1 - smoothstep(1, 1 + lake.Shore, r)
			height += (math.min(height, lake.Level) - height) * blend
		end
	end
	return height
end

-- Inside the frozen lake (flat ice)
function FreerideHeightfield:InLake(x: number, z: number): boolean
	local lake = self.Lake
	if not lake then
		return false
	end
	local dx, dz = (x - lake.X) / lake.RadiusX, (z - lake.Z) / lake.RadiusZ
	return dx * dx + dz * dz < 1
end

-- 0 inside the playable area, rising to 1 across the mountain range around it
function FreerideHeightfield:RangeMask(x: number, z: number): number
	local range = self.World.Range
	if not range then
		return 0
	end
	local dx = math.max(math.abs(x) - range.InnerX, 0)
	local dz = math.max(range.InnerUphill - z, 0) + math.max(z - range.InnerDownhill, 0)
	return smoothstep(range.Fade[1], range.Fade[2], math.sqrt(dx * dx + dz * dz))
end

-- The mountain without features
function FreerideHeightfield:BaseHeight(x: number, z: number): number
	local world = self.World
	local seed = self.Seed
	local c = world.Corridors
	local relief = world.Relief
	local height = self:ProfileY(z)

	-- Corridors and the ridgelines between them
	local envelope = self:CorridorEnvelope(z)
	if envelope > 0 then
		local centers = { self:CorridorCenter(1, z), self:CorridorCenter(2, z), self:CorridorCenter(3, z) }
		local weightSum, shape = 0, 0
		for i = 1, 3 do
			local d = (x - centers[i]) / c.Width
			local w = math.exp(-d * d)
			weightSum += w
			shape += w * self:CorridorShape(i, z)
		end
		if weightSum > 1e-4 then
			height += envelope * shape / weightSum
		end
		for i = 1, 2 do
			local mid = (centers[i] + centers[i + 1]) / 2
			local d = (x - mid) / c.Ridge.Width
			local crest = 0.8 + 0.4 * valueNoise(z / 260, i * 7.3, seed + 50)
			height += envelope * c.Ridge.Height * crest * math.exp(-d * d)
		end
	end

	-- Rounded bowl and the boundary walls
	local ax = math.abs(x)
	height += world.Bowl.Curvature * x * x
	local walls = world.Walls
	local beyond = ax - walls.StartX
	if beyond > 0 then
		local rise = walls.Rise * beyond * beyond / (beyond + walls.Knee)
		if walls.MaxRise then
			-- The wall levels off into the foot of the mountain range beyond it
			rise = walls.MaxRise * (1 - math.exp(-rise / walls.MaxRise))
		end
		height += rise + fbm(x / 70, z / 70, seed + 90, 3) * 18 * smoothstep(0, 120, beyond)
	end

	-- Mountain range all around the playable area: ridged noise gives sharp ridgelines and
	-- peaks; slope decides snow or rock, so steep faces come out rocky
	local range = world.Range
	if range then
		local mask = self:RangeMask(x, z)
		if mask > 0 then
			local ridge = 1 - math.abs(valueNoise(x / range.PeakScale, z / range.PeakScale, seed + 300))
			local ridge2 = 1 - math.abs(valueNoise(x / range.RidgeScale, z / range.RidgeScale, seed + 310))
			height += mask
				* (range.Base + ridge ^ range.PeakSharpness * range.PeakHeight + ridge2 ^ 2 * range.RidgeHeight + fbm(x / 90, z / 90, seed + 320, 2) * 30)
		end
	end

	-- Natural relief, calm around the start and finish
	local calm = math.min(
		smoothstep(0, relief.CleanRadius, math.sqrt(x * x + z * z)),
		smoothstep(0, relief.CleanRadius * 1.5, math.sqrt(x * x + (z - self.Course.Finish.Z) ^ 2))
	)
	height += fbm(x / relief.Large.Scale, z / relief.Large.Scale, seed, 3) * relief.Large.Amplitude * (0.4 + 0.6 * calm)
	height += fbm(x / relief.Medium.Scale, z / relief.Medium.Scale, seed + 20, 2) * relief.Medium.Amplitude * calm
	local wind = 1 - math.abs(valueNoise(x / relief.WindRidges.ScaleX, z / relief.WindRidges.ScaleZ, seed + 30))
	height += wind * wind * wind * relief.WindRidges.Amplitude * calm
	local drift = math.max(fbm(x / relief.Drifts.Scale, z / relief.Drifts.Scale, seed + 40, 2), 0)
	height += drift ^ 1.5 * relief.Drifts.Amplitude * 2 * calm
	local bank = (ax - walls.StartX) / relief.Snowbank.Width
	height += relief.Snowbank.Height * math.exp(-bank * bank)

	return height
end

function FreerideHeightfield:GetNormal(x: number, z: number): Vector3
	local e = 2
	local dx = (self:GetHeight(x + e, z) - self:GetHeight(x - e, z)) / (2 * e)
	local dz = (self:GetHeight(x, z + e) - self:GetHeight(x, z - e)) / (2 * e)
	return Vector3.new(-dx, 1, -dz).Unit
end

function FreerideHeightfield:GetSlope(x: number, z: number): number
	local normal = self:GetNormal(x, z)
	return math.sqrt(1 - normal.Y * normal.Y) / normal.Y
end

function FreerideHeightfield:IsLake(x: number, z: number, _height: number): boolean
	return self:InLake(x, z)
end

-- Powder snow everywhere it can hold; rock bands only on faces too steep for snow; ice on
-- the frozen lake.
function FreerideHeightfield:ChooseMaterial(x: number, z: number, _height: number, slope: number)
	local materials = self.World.Materials
	if self:InLake(x, z) then
		return Enum.Material.Glacier
	end
	local patch = valueNoise(x / materials.PatchScale, z / materials.PatchScale, self.Seed + 60) * 0.12
	-- Snow clings to steeper faces on the surrounding range (mostly white peaks, rock ribs)
	local rockSlope = materials.RockSlope + (materials.RangeSnowBonus or 0) * self:RangeMask(x, z)
	if slope + patch < rockSlope then
		return Enum.Material.Snow
	end
	-- Dark slate only on the sheerest faces (further up on the range, where snow holds longer)
	return if slope > materials.SlateSlope + (rockSlope - materials.RockSlope) then Enum.Material.Slate else Enum.Material.Rock
end

-- World positions (on the snow) of a race checkpoint's beams: Beams = X positions,
-- Corridors = corridor centres at the checkpoint's Z
function FreerideHeightfield:CheckpointBeams(checkpoint): { Vector3 }
	local positions = {}
	local origin = self.Course.Origin
	local xs = table.clone(checkpoint.Beams or {})
	for _, index in checkpoint.Corridors or {} do
		table.insert(xs, self:CorridorCenter(index, checkpoint.Z))
	end
	for _, x in xs do
		table.insert(positions, origin + Vector3.new(x, self:GetHeight(x, checkpoint.Z), checkpoint.Z))
	end
	return positions
end

-- World-space flat CFrame facing down the fall line (+Z), for spawns.
function FreerideHeightfield:GetUprightCFrame(x: number, z: number, heightAbove: number): CFrame
	local origin = self.Course.Origin
	local position = origin + Vector3.new(x, self:GetHeight(x, z) + heightAbove, z)
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

-- Local-space bounds of the generated terrain: minX, maxX, minZ, maxZ.
function FreerideHeightfield:GetBounds(): (number, number, number, number)
	local bounds = self.World.Bounds
	return -bounds.HalfWidth, bounds.HalfWidth, -bounds.Uphill, bounds.Downhill
end

-- Bounds of the terrain to bake: the playable area plus the mountain range around it
function FreerideHeightfield:GetTerrainBounds(): (number, number, number, number)
	local range = self.World.Range
	if not range then
		return self:GetBounds()
	end
	local bounds = range.Bounds
	return -bounds.HalfWidth, bounds.HalfWidth, -bounds.Uphill, bounds.Downhill
end

return FreerideHeightfield
