--[[
	Heightfield
	Turns a course definition into a continuous surface: height(x, z) in course-local space.

	Racing line: segment angles are box-blurred over TransitionLength so slope changes are
	smooth, then integrated along Z. The centre line meanders sideways. This part is gameplay
	and is unchanged by scenery settings.

	Scenery (course.World): the cross-section beyond the piste is a snow berm and a ridged
	mountainside on -X, and a lip and drop into a valley on +X. Behind the start the slope keeps
	rising to a summit; below the finish a run-out and resort plaza lead to the valley. Ridged
	mountain ranges rise across the valley and beyond the resort, which also keeps the edges of
	the generated area out of sight.
]]

local PROFILE_STEP = 2

local Heightfield = {}
Heightfield.__index = Heightfield

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Smooth max: like math.max but rounds the crease over roughly k studs.
local function smoothMax(a: number, b: number, k: number): number
	local d = a - b
	return (a + b + math.sqrt(d * d + k * k)) / 2
end

-- Soft ramp: exactly 0 for x <= 0, then eases into slope 1 (approaching x - knee).
-- Smooth at 0, so terrain built from it has no step where a feature begins.
local function softRamp(x: number, knee: number): number
	if x <= 0 then
		return 0
	end
	return x * x / (x + knee)
end

function Heightfield.new(course)
	local self = setmetatable({}, Heightfield)
	self.Course = course
	self.World = course.World
	self.Seed = course.Seed % 1000 + 0.5

	-- Raw angle per profile sample
	local rawAngles = {}
	local length = 0
	for _, segment in course.Segments do
		local samples = math.floor(segment.Length / PROFILE_STEP)
		for _ = 1, samples do
			table.insert(rawAngles, segment.Angle)
		end
		length += samples * PROFILE_STEP
	end
	self.Length = length

	-- Blur so the slope never changes abruptly
	local radius = math.max(1, math.floor(course.TransitionLength / 2 / PROFILE_STEP))
	local count = #rawAngles
	local angles = table.create(count, 0)
	for i = 1, count do
		local sum, n = 0, 0
		for j = math.max(1, i - radius), math.min(count, i + radius) do
			sum += rawAngles[j]
			n += 1
		end
		angles[i] = sum / n
	end

	-- Integrate into heights. profile[i + 1] is the height at z = i * PROFILE_STEP
	local profile = table.create(count + 1, 0)
	profile[1] = course.StartY
	for i = 1, count do
		profile[i + 1] = profile[i] - math.tan(math.rad(angles[i])) * PROFILE_STEP
	end
	self.Profile = profile
	self.EndY = profile[count + 1]

	-- Lowest point of any generated terrain: the racing line or the valley floor
	local minY = math.huge
	for _, y in profile do
		minY = math.min(minY, y)
	end
	self.MinY = math.min(minY, self.World.ValleySide.FloorY - self.World.ValleySide.FloorNoise)

	return self
end

----------------------------------------------------------------------------------------------
-- Racing line
----------------------------------------------------------------------------------------------

-- Height of the racing line at z, extended past both ends by the summit and the run-out.
function Heightfield:ProfileY(z: number): number
	local world = self.World
	if z <= 0 then
		local u = -z
		return self.Course.StartY + world.Summit.RiseSlope * softRamp(u - 10, 30) + world.Summit.Curve * u * u
	elseif z >= self.Length then
		local over = z - self.Length
		local runOut = world.RunOut
		local plaza = world.Plaza
		local y = self.EndY + math.tan(math.rad(runOut.Angle)) * math.min(over, runOut.Length)
		local dropStart = runOut.Length + plaza.Length
		y -= plaza.DropSlope * softRamp(over - dropStart, 40)
		return y
	end

	local f = z / PROFILE_STEP
	local i = math.floor(f)
	local t = f - i
	local a = self.Profile[i + 1]
	local b = self.Profile[i + 2] or a
	return a + (b - a) * t
end

function Heightfield:CenterX(z: number): number
	local meander = self.Course.Meander
	local fadeIn = smoothstep(meander.Start, meander.Start + 200, z)
	local fadeOut = 1 - smoothstep(self.Length - meander.EndFade, self.Length - meander.EndFade + 200, z)
	return meander.Amplitude * math.sin(z / meander.Wavelength * math.pi * 2) * fadeIn * fadeOut
end

function Heightfield:RollerOffset(z: number): number
	local offset = 0
	for _, roller in self.Course.Rollers do
		if z > roller.StartZ and z < roller.EndZ then
			local along = z - roller.StartZ
			local window = math.sin(math.pi * along / (roller.EndZ - roller.StartZ))
			offset += roller.Amplitude * math.sin(along / roller.Wavelength * math.pi * 2) * window
		end
	end
	return offset
end

-- Signed distance across the slope from the centre line (+X = valley side).
function Heightfield:Offset(x: number, z: number): number
	return x - self:CenterX(z)
end

-- Distance outside the groomed piste (0 on the piste).
function Heightfield:DistanceFromPiste(x: number, z: number): number
	return math.max(0, math.abs(self:Offset(x, z)) - self.World.Piste.HalfWidth)
end

----------------------------------------------------------------------------------------------
-- Noise
----------------------------------------------------------------------------------------------

-- Fractal noise in roughly [-1, 1].
function Heightfield:Fbm(x: number, z: number, scale: number, octaves: number): number
	local sum, amplitude, frequency, norm = 0, 1, 1 / scale, 0
	for octave = 1, octaves do
		sum += math.noise(x * frequency, z * frequency, self.Seed + octave * 3.7) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	end
	return sum / norm * 2
end

-- Ridged noise in [0, 1]: sharp crests, which read as mountain ridges and cliff bands.
-- Lower gain keeps the fine octaves from crumpling the surface.
function Heightfield:Ridged(x: number, z: number, scale: number, octaves: number?, gain: number?): number
	local sum, amplitude, frequency, norm = 0, 1, 1 / scale, 0
	for octave = 1, octaves or 3 do
		local n = 1 - math.min(1, math.abs(math.noise(x * frequency, z * frequency, self.Seed + 20 + octave * 5.3)) * 2.2)
		sum += n * n * amplitude
		norm += amplitude
		amplitude *= gain or 0.4
		frequency *= 2.1
	end
	return sum / norm
end

----------------------------------------------------------------------------------------------
-- Surface
----------------------------------------------------------------------------------------------

-- Height of the scenery beside the piste, relative to the racing line at this z.
function Heightfield:SideHeight(x: number, z: number, offset: number): number
	local world = self.World
	local beyond = math.abs(offset) - world.Piste.HalfWidth
	if beyond <= 0 then
		return 0
	end

	if offset < 0 then
		local side = world.MountainSide
		local berm = side.BermHeight * smoothstep(0, side.BermWidth, beyond)
		local rise = side.RiseSlope * softRamp(beyond - side.BermWidth, 40)
		local ridges = self:Ridged(x, z, side.RidgeScale) * side.RidgeAmplitude * smoothstep(side.BermWidth, side.BermWidth + side.RidgeFadeIn, beyond)
		return berm + rise + ridges
	end

	local side = world.ValleySide
	local lip = side.LipHeight * smoothstep(0, side.LipWidth * 0.5, beyond) * (1 - smoothstep(side.LipWidth * 0.5, side.LipWidth * 1.5, beyond))
	local drop = side.DropSlope * softRamp(beyond - side.DropStart, 60)
	local ridges = self:Ridged(x + 900, z, 200) * 30 * smoothstep(side.DropStart, side.DropStart + 200, beyond)
	return lip - drop + ridges
end

function Heightfield:ValleyFloor(x: number, z: number): number
	local side = self.World.ValleySide
	return side.FloorY + self:Fbm(x, z, 260, 3) * side.FloorNoise
end

-- Smooth ridge of snow piled against the safety netting, within the dressed Z range.
function Heightfield:Snowbank(z: number, offset: number): number
	local course = self.Course
	local dressing = course.Dressing
	if z < dressing.StartZ - 20 or z > dressing.EndZ + 20 then
		return 0
	end
	local window = smoothstep(dressing.StartZ - 20, dressing.StartZ + 20, z) * (1 - smoothstep(dressing.EndZ - 20, dressing.EndZ + 20, z))
	local fence = self.World.Piste.HalfWidth + course.Fences.Inset - 1
	local d = (math.abs(offset) - fence) / dressing.SnowbankWidth
	return dressing.SnowbankHeight * math.exp(-d * d) * window
end

-- Height of one mountain range above the valley floor, given how far into it the point is.
function Heightfield:RangeHeight(x: number, z: number, distance: number, range, seedOffset: number): number
	local envelope = smoothstep(range.Start, range.FullAt, distance)
	if envelope <= 0 then
		return 0
	end
	-- Broad massifs from low-frequency noise, with ridged crests on top for sharp summits
	local massif = math.clamp(self:Fbm(x - seedOffset, z, range.Scale * 1.6, 2) * 0.5 + 0.55, 0, 1)
	local crests = self:Ridged(x + seedOffset, z - seedOffset, range.Scale, 3, 0.35)
	return envelope * (range.BaseHeight * (0.5 + 0.5 * massif) + range.PeakHeight * massif * (1 - range.CrestWeight + range.CrestWeight * crests))
end

-- Mountain ranges across the valley and beyond the resort. They also hide the edges of the
-- generated terrain from the course.
function Heightfield:Ranges(x: number, z: number, offset: number): number
	local ranges = self.World.Ranges
	local height = 0
	if offset > 0 then
		height = math.max(height, self:RangeHeight(x, z, offset, ranges.Valley, 1200))
	end
	local past = z - self.Length
	if past > 0 then
		height = math.max(height, self:RangeHeight(x, z, past, ranges.Downhill, 2600))
	end
	return height
end

function Heightfield:GetHeight(x: number, z: number): number
	local world = self.World
	local offset = self:Offset(x, z)
	local beyond = math.abs(offset) - world.Piste.HalfWidth

	local h = self:ProfileY(z) + self:RollerOffset(z) + self:SideHeight(x, z, offset) + self:Snowbank(z, offset)

	-- Gentle undulation on the piste, rougher terrain away from it
	local roughness = smoothstep(0, 120, beyond)
	h += self:Fbm(x, z, world.Piste.NoiseScale, 2) * world.Piste.NoiseAmplitude * (1 - roughness)
	h += self:Fbm(x + 400, z, world.Noise.Scale, 4) * world.Noise.Amplitude * roughness

	-- Valley floor catches the drop on the valley side and the descent below the plaza
	h = smoothMax(h, self:ValleyFloor(x, z), 30)

	local range = self:Ranges(x, z, offset)
	if range > 0 then
		h = smoothMax(h, self:ValleyFloor(x, z) + range, 40)
	end

	return h
end

-- True where the valley floor holds a frozen lake (flat ice).
function Heightfield:IsLake(x: number, z: number, height: number): boolean
	local lake = self.World.Lake
	if height > self.World.ValleySide.FloorY + 4 then
		return false
	end
	return math.noise(x / lake.Scale, z / lake.Scale, self.Seed + 50) > lake.Threshold
end

function Heightfield:GetNormal(x: number, z: number): Vector3
	local e = 2
	local dx = (self:GetHeight(x + e, z) - self:GetHeight(x - e, z)) / (2 * e)
	local dz = (self:GetHeight(x, z + e) - self:GetHeight(x, z - e)) / (2 * e)
	return Vector3.new(-dx, 1, -dz).Unit
end

-- Rise over run at (x, z).
function Heightfield:GetSlope(x: number, z: number): number
	local normal = self:GetNormal(x, z)
	return math.sqrt(1 - normal.Y * normal.Y) / normal.Y
end

-- Direction of travel down the centre line at z (includes the slope pitch).
function Heightfield:GetDownhill(z: number): Vector3
	local e = 2
	return Vector3.new(self:CenterX(z + e) - self:CenterX(z - e), self:ProfileY(z + e) - self:ProfileY(z - e), 2 * e).Unit
end

-- World-space CFrame on the surface at local (x, z): up = surface normal, look = downhill.
function Heightfield:GetSurfaceCFrame(x: number, z: number): CFrame
	local origin = self.Course.Origin
	local position = origin + Vector3.new(x, self:GetHeight(x, z), z)
	local normal = self:GetNormal(x, z)
	local downhill = self:GetDownhill(z)
	local forward = (downhill - normal * downhill:Dot(normal)).Unit
	return CFrame.lookAt(position, position + forward, normal)
end

-- World-space flat CFrame facing downhill, used for spawning and upright props.
function Heightfield:GetUprightCFrame(x: number, z: number, heightAbove: number): CFrame
	local origin = self.Course.Origin
	local position = origin + Vector3.new(x, self:GetHeight(x, z) + heightAbove, z)
	local downhill = self:GetDownhill(z)
	local flat = Vector3.new(downhill.X, 0, downhill.Z).Unit
	return CFrame.lookAt(position, position + flat)
end

-- Local-space bounds of the generated terrain: minX, maxX, minZ, maxZ.
function Heightfield:GetBounds(): (number, number, number, number)
	local world = self.World
	local meander = self.Course.Meander.Amplitude
	return -(meander + world.Extent.Mountain), meander + world.Extent.Valley, -world.Extent.Uphill, self.Length + world.Extent.Downhill
end

return Heightfield
