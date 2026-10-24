--[[
	PoseConfig
	Riding stance for R15 characters, applied procedurally (see client/Animation/RiderPose).
	Angles are in degrees.

	Crouch: hip flex angle; the knee bends twice that and the ankle compensates, so the shins
	tilt forward and the feet stay flat and directly under the hips. The hips drop by the height
	the bent legs lose, keeping the feet on the skis or board.
	Values blend between the normal and Tuck columns by how far the rider is into a tuck.

	Turning (skis): both knees drive into the turn (Inclination), the inside leg bends more and
	the outside leg extends, and the upper body counter-rotates to keep facing down the hill.
	Poles trail behind while riding, tuck under the arms in a tuck, and the inside pole
	swings forward and plants at the start of each turn.
]]

return {
	Ski = {
		Crouch = 24, -- knees bent while riding normally
		TuckCrouch = 52, -- deep tuck
		AirCrouch = 34, -- knees drawn up in the air
		ChargeCrouch = 16, -- extra knee load while charging a jump
		BrakeCrouch = 32,
		TorsoPitch = 18, -- forward lean of the upper body
		TuckTorsoPitch = 44,
		ArmForward = 30, -- upper arms forward, hands in front holding the poles
		TuckArmForward = 58,
		Elbow = 40,
		TuckElbow = 48,
		ArmOut = 14, -- arms slightly away from the body (poles clear the skis)
		Wrist = -12, -- poles trail down and back, tips just above the snow
		TuckWrist = -95, -- poles tucked under the arms, pointing back
		Angulation = 10, -- upper body stays more upright than the legs in a turn
		NeckCompensation = 0.7, -- share of the torso lean the head undoes, to keep looking ahead
		StanceYaw = 0,
		HeadYaw = 0,
		Spread = 4, -- legs angled slightly apart: an athletic, hip-width stance

		Inclination = 11, -- knees driven into the turn
		InsideLegBend = 9, -- inside leg flexes more…
		OutsideLegExtend = 6, -- …outside leg extends, as in a real carve
		CounterRotation = 8, -- upper body yaws against the turn to keep facing downhill

		PoleTrigger = 0.35, -- |steer| that counts as starting a turn
		PlantForward = 32, -- inside arm swings forward to plant the pole
		PlantWrist = 40, -- pole tip swings forward to touch the snow
		PlantDuration = 0.4,
	},

	Snowboard = {
		Crouch = 20,
		TuckCrouch = 40,
		AirCrouch = 32,
		ChargeCrouch = 16,
		BrakeCrouch = 30,
		TorsoPitch = 10,
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
		Spread = 11, -- feet apart along the board, over the bindings

		Inclination = 0,
		InsideLegBend = 0,
		OutsideLegExtend = 0,
		CounterRotation = 0,

		PoleTrigger = 2, -- never (no poles)
		PlantForward = 0,
		PlantWrist = 0,
		PlantDuration = 0.4,
	},

	-- Easing of every joint target (higher = snappier)
	Responsiveness = 12,
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
