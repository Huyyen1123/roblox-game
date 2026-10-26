--[[
	Landing
	Judges a touchdown from the velocity at impact, the slope normal and where the rider faces.

	Returns:
	{
		Quality: "Clean" | "Hard" | "Sketchy" | "Wipeout",
		Stumble: boolean,      -- poor but recoverable: brief loss of speed and control
		Impact: number,        -- studs/s into the surface
		Angle: number,         -- degrees between facing and travel direction
		Velocity: Vector3,     -- velocity after touchdown (into-surface part removed)
		Heading: Vector3?,     -- new facing when the landing twisted the rider round
		Switch: boolean,       -- landed backwards (after a 180): the rider now rides switch
	}

	tilt: degrees a flip has left the body rotated at touchdown (0 = no flip). Rotations
	are never finished for the rider: badly under- or over-rotated landings fail.
]]

local Physics = require(script.Parent.Physics)

local Landing = {}

function Landing.Evaluate(velocity: Vector3, heading: Vector3, normal: Vector3, stats, config, tilt: number?)
	local landing = config.Landing
	local impact = -velocity:Dot(normal)
	local planar = Physics.ProjectOnPlane(velocity, normal)
	local forward = Physics.PlaneBasis(heading, normal)

	local angle = 0
	local switch = false
	if planar.Magnitude > 1 then
		angle = math.deg(math.acos(math.clamp(planar.Unit:Dot(forward), -1, 1)))
		-- Landing backwards after a 180 (or 540…) is a switch landing: the rider keeps facing
		-- the way they spun and rides away switch (judged against the nearer direction). This
		-- is decided at any speed so the stance always matches the way the body faces.
		if angle > 90 then
			angle = 180 - angle
			switch = true
		end
		-- Too slow for the landing angle to matter for quality
		if planar.Magnitude <= landing.MinSpeedForAngle then
			angle = 0
		end
	end

	local stability = stats.Stability
	local result = {
		Quality = "Clean",
		Stumble = false,
		Impact = impact,
		Angle = angle,
		Velocity = planar,
		Heading = if switch then Physics.Flatten(planar) else nil,
		Switch = switch,
	}

	tilt = tilt or 0
	result.Tilt = tilt
	if impact > landing.WipeoutImpact * stability or angle > landing.StumbleAngle or tilt > landing.TiltSketchy then
		result.Quality = "Wipeout"
		return result
	end

	local speedLoss = 0
	local softImpact = landing.SoftImpact * stability
	if impact > softImpact then
		result.Quality = "Hard"
		speedLoss += (impact - softImpact) * landing.HardSpeedLossPerImpact
		result.Stumble = impact > landing.StumbleImpact * stability
	end
	if angle > landing.CleanAngle then
		result.Quality = "Sketchy"
		result.Stumble = true
		result.Heading = Physics.Flatten(planar)
	end
	if tilt > landing.TiltClean then
		result.Quality = "Sketchy"
		result.Stumble = true
	end

	result.Velocity = planar * (1 - math.clamp(speedLoss, 0, 0.6))
	return result
end

return Landing
