--[[
	PoseConfig
	Riding stance for R15 characters, applied procedurally (see client/Animation/RiderPose).
	Angles are in degrees.

	Feet always stay on the equipment: the legs are solved (IK) to reach the skis or the board
	bindings. Crouch sets how far the pelvis drops (as a hip-flex angle); the knees bend as much
	as needed to keep the feet planted. Values blend between the normal and Tuck columns by how
	far the rider is into a tuck.

	Turning (skis): the inside ski rides higher as the body leans (edges on the snow), the feet
	shift to the outside of the turn, and the upper body counter-rotates to keep facing down
	the hill. Poles trail behind while riding, tuck under the arms in a tuck, and the inside
	pole swings forward and plants at the start of each turn.
]]

return {
	Ski = {
		Crouch = 30, -- low, athletic stance: hips down, knees well bent
		TuckCrouch = 56, -- deep tuck
		AirCrouch = 40, -- knees drawn up in the air
		ChargeCrouch = 26, -- extra knee load while charging a jump
		ChargeTorso = 10, -- chest drops over the knees while charging
		ChargeArmBack = 28, -- arms (and poles) swing back, ready to throw forward
		PopCrouch = 4, -- legs snap almost straight at takeoff…
		PopArmForward = 28, -- …as the arms swing forward
		BrakeCrouch = 38,
		TorsoPitch = 24, -- upper body leans forward, down the hill
		TuckTorsoPitch = 46,
		ArmForward = 30, -- upper arms forward, hands in front holding the poles
		TuckArmForward = 58,
		Elbow = 40,
		TuckElbow = 48,
		ArmOut = 14, -- arms slightly away from the body (poles clear the skis)
		Wrist = -12, -- poles trail down and back, tips just above the snow
		TuckWrist = -95, -- poles tucked under the arms, pointing back
		Angulation = 14, -- upper body stays more upright than the legs in a turn
		NeckCompensation = 0.7, -- share of the torso lean the head undoes, to keep looking ahead
		StanceYaw = 0,
		HeadYaw = 0,
		-- Feet shift this far (studs) to the outside of a turn: hips inside, skis outside
		CarveShift = 0.3,
		CounterRotation = 10, -- upper body yaws against the turn to keep facing downhill
		CarveArmForward = 12, -- inside hand drives forward through a carve
		CarveArmOut = 10, -- outside arm lifts slightly for balance
		AirArmOut = 12, -- arms open a little in the air (balance through spins)

		PoleTrigger = 0.35, -- |steer| that counts as starting a turn
		PlantForward = 32, -- inside arm swings forward to plant the pole
		PlantWrist = 40, -- pole tip swings forward to touch the snow
		PlantDuration = 0.4,
	},

	Snowboard = {
		Crouch = 28,
		TuckCrouch = 44,
		AirCrouch = 40,
		ChargeCrouch = 26,
		ChargeTorso = 12,
		ChargeArmBack = 18,
		PopCrouch = 4,
		PopArmForward = 18,
		BrakeCrouch = 36,
		TorsoPitch = 14,
		TuckTorsoPitch = 24,
		ArmForward = 12,
		TuckArmForward = 30,
		Elbow = 25,
		TuckElbow = 50,
		ArmOut = 40, -- arms out for balance
		Wrist = 0,
		TuckWrist = 0,
		Angulation = 0,
		NeckCompensation = 0.5,
		StanceYaw = 80, -- body turned sideways on the board (regular: left foot forward)
		HeadYaw = 65, -- head turned back toward the direction of travel
		CarveShift = 0, -- feet are fixed in the bindings
		CounterRotation = 0,
		CarveArmForward = 0,
		CarveArmOut = 8,
		AirArmOut = 18,

		PoleTrigger = 2, -- never (no poles)
		PlantForward = 0,
		PlantWrist = 0,
		PlantDuration = 0.4,
	},

	-- Easing of every joint target (higher = snappier)
	Responsiveness = 12,
	-- Jump: loading the knees while charging, then a quick pop (legs extend) at takeoff
	ChargeResponsiveness = 18,
	PopDuration = 0.18,
	PopResponsiveness = 30,
	-- Extra crouch on landing, per stud/s of impact, and how fast it springs back
	LandingCompressionPerImpact = 0.5,
	MaxLandingCompression = 25,
	LandingRecovery = 7,
	-- Knees absorb terrain: extra crouch per stud/s² of upward acceleration (dips), and the
	-- legs extend over crests. Clamped and smoothed.
	AbsorbPerAccel = 0.05,
	MaxAbsorb = 12,
	AbsorbResponsiveness = 8,
	-- Wobble while stumbling
	StumbleWobble = 14,

	-- Riding state shared with other players so they see your stance (sends per second, max)
	ReplicationRate = 10,
}
