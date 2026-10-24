--[[
	PoseConfig
	Riding stance for R15 characters, applied procedurally (see client/Animation/RiderPose).
	Angles are in degrees.

	Crouch: hip flex angle; the knee bends twice that and the ankle compensates, so the shins
	tilt forward and the feet stay flat and directly under the hips. The hips drop by exactly
	the height the bent legs lose, keeping the feet on the skis or board.
	Values blend between the normal and Tuck columns by how far the rider is into a tuck.
]]

return {
	Ski = {
		Crouch = 22, -- knees bent while riding normally
		TuckCrouch = 52, -- deep tuck
		AirCrouch = 32, -- knees drawn up in the air
		ChargeCrouch = 16, -- extra knee load while charging a jump
		BrakeCrouch = 30,
		TorsoPitch = 16, -- forward lean of the upper body
		TuckTorsoPitch = 42,
		ArmForward = 32, -- arms raised forward, as if holding poles
		TuckArmForward = 78,
		Elbow = 38,
		TuckElbow = 100,
		ArmOut = 12, -- arms slightly away from the body
		Angulation = 10, -- upper body stays more upright than the legs in a turn
		NeckCompensation = 0.7, -- share of the torso lean the head undoes, to keep looking ahead
		StanceYaw = 0,
		HeadYaw = 0,
		Spread = 0, -- hip abduction
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
		Angulation = 0,
		NeckCompensation = 0.5,
		StanceYaw = 80, -- body turned sideways on the board (regular: left foot forward)
		HeadYaw = 65, -- head turned back toward the direction of travel
		Spread = 11, -- feet apart along the board, over the bindings
	},

	-- Easing of every joint target (higher = snappier)
	Responsiveness = 12,
	-- Extra crouch on landing, per stud/s of impact, and how fast it springs back
	LandingCompressionPerImpact = 0.6,
	MaxLandingCompression = 25,
	LandingRecovery = 7,
	-- Wobble while stumbling
	StumbleWobble = 14,

	-- Riding state shared with other players so they see your stance (sends per second, max)
	ReplicationRate = 10,
}
