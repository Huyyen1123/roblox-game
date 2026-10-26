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

function FreerideHeightfield:GetHeight(x: number, z: number): number
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
		height += walls.Rise * beyond * beyond / (beyond + walls.Knee)
			+ fbm(x / 70, z / 70, seed + 90, 3) * 18 * smoothstep(0, 120, beyond)
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

function FreerideHeightfield:IsLake(_x: number, _z: number, _height: number): boolean
	return false
end

-- Powder snow everywhere it can hold; rock bands only on faces too steep for snow.
function FreerideHeightfield:ChooseMaterial(x: number, z: number, _height: number, slope: number)
	local materials = self.World.Materials
	local patch = valueNoise(x / materials.PatchScale, z / materials.PatchScale, self.Seed + 60) * 0.12
	if slope + patch < materials.RockSlope then
		return Enum.Material.Snow
	end
	return if slope > materials.SlateSlope then Enum.Material.Slate else Enum.Material.Rock
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

return FreerideHeightfield
