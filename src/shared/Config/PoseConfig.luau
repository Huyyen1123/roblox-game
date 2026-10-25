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
		-- Riding switch (backwards): a bit taller and more open for balance
		SwitchTorsoScale = 0.7,
		SwitchArmOut = 10,
		-- Feet shift this far (studs) to the outside of a turn: hips inside, skis outside
		CarveShift = 0.3,
		-- Braking: snowplow (tips in, tails out, feet wider, poles out for balance)
		SnowplowAngle = 8, -- degrees each ski turns in (tips stay apart at this length)
		SnowplowWiden = 0.45, -- studs each foot moves out
		BrakeArmOut = 14,
		BrakeArmForward = 10,
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
		SwitchTorsoScale = 1,
		SwitchArmOut = 0,
		CarveShift = 0, -- feet are fixed in the bindings
		CounterRotation = 0,

		-- Snowboard-only shaping (see RiderPose:ApplyBoard). Toe-side and heel-side carves are
		-- different shapes; carve depth grows with speed.
		Board = {
			CarveFullSpeed = 70, -- studs/s at which carves reach full depth
			CarveMinDepth = 0.35, -- share of full depth at low speed
			-- Toe-side: knees and hips drive over the toes, chest folds forward, hands reach low
			ToeHipShift = 0.35, -- studs toward the toes
			ToeCrouch = 10,
			ToeTorso = 7,
			ToeShoulderOpen = 6,
			ToeArmForward = 32,
			-- Heel-side: sit low and back, open the shoulders down the hill, rear hand drags
			HeelHipShift = 0.65, -- studs toward the heels
			HeelCrouch = 28,
			HeelTorso = -6,
			HeelShoulderOpen = 22,
			HeelFrontArmOut = 28, -- front arm lifts toward the nose
			HeelRearArmBack = 60, -- rear arm sweeps back and down toward the snow
			-- Riding: shoulders slightly toward the nose, small continuous movement
			ShoulderOpen = 14,
			IdleKnee = 1.6, -- degrees of slow knee bob
			IdleSway = 1.5, -- degrees of torso sway
			IdleArm = 5, -- degrees of arm drift
			-- In the air only: W/S tweak the nose or tail up (board pitches about its centre)
			TweakAngle = 22,
			TweakHipShift = 0.25, -- weight moves toward the raised end
			TweakCrouch = 8,
			-- Air
			AirLift = 0.35, -- board comes up toward the body (knees tuck)
			AirTilt = 8, -- degrees the board tilts with steering in the air
			SpinLead = 4, -- degrees of upper-body lead per rad/s of spin
			MaxSpinLead = 35,
			SpinArmTuck = 20, -- arms pull in during fast spins
			-- Grabs (indy: rear hand, toe edge; melon: front hand, heel edge; method: front hand,
			-- heel edge, board tweaked up behind)
			GrabCrouch = 30,
			GrabTorso = 18,
			GrabLift = 0.7, -- board pulled up to the hand
			IndyTilt = 10, -- toe edge up
			MelonTilt = 14, -- heel edge up
			MethodTilt = 38, -- heel edge up, board shown off behind
			MethodPitch = 14, -- nose up
			GrabResponsiveness = 11,
			-- On the snow, air-only channels (board lift, tilt, tweaks, grabs) return this fast,
			-- so the board is back flat on the snow right at touchdown
			GroundSnapResponsiveness = 40,
			-- Braking: hard heel-side skid, board swung across the fall line
			BrakeEdge = 0.85,
			SkidYaw = 14,
			-- Limits so stacked poses (e.g. toe carve + nose press) never fold the rider in half
			MaxTorso = 30,
			-- Deep fast heel-side carves: rear hand reaches back to the snow
			HeelHandDrag = 0.8,
		},
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

	-- Head: looks along the direction of travel (over the downhill shoulder when riding
	-- switch), leads into turns, and spots the landing in the air. The neck turns up to
	-- NeckLimit; beyond that the shoulders help, up to ShoulderLimit.
	Look = {
		NeckLimit = 75,
		ShoulderLimit = 35,
		TurnLead = 22, -- degrees the head turns into a turn at full steer (ahead of the body)
		Responsiveness = 7, -- easing of where the rider looks (in the world)
		NeckResponsiveness = 10, -- easing of the neck and shoulder turn
		MinSpeed = 3, -- below this, look where the gear points
		-- Looking almost straight back: keep the current shoulder unless the target is
		-- clearly on the other side (stops the head flipping between shoulders)
		SideHysteresis = 150,
	},
	-- Jump: loading the knees while charging, then a quick pop (legs extend) at takeoff
	ChargeResponsiveness = 18,
	PopDuration = 0.18,
	PopResponsiveness = 30,
	-- Takeoff to touchdown (both sports)
	Landing = {
		-- Knees compress per stud/s of impact, up to Max, and spring back at Recovery
		CompressionPerImpact = 0.5,
		MaxCompression = 25,
		Recovery = 7,
		-- In the last PrepTime seconds before touchdown the legs reach down to meet the snow
		PrepTime = 0.22,
		ReachCrouch = 14,
		-- Hard landing: chest folds forward and the arms are thrown out, then recover slowly
		HardFold = 16,
		HardArmOut = 24,
		HardRecovery = 3,
		-- Stumble (sketchy landing or a bump): hips buckle toward one side, the torso
		-- lurches, the arm on the far side windmills for balance; fades as balance returns
		StumbleBuckle = 9, -- degrees the pelvis rolls
		StumbleLurch = 14, -- degrees the torso leans
		StumbleArm = 70, -- degrees of arm windmill
		StumbleArmRate = 9, -- windmill speed (radians/s)
		StumbleDecay = 2.2, -- how fast the stagger settles
		StumbleCrouch = 10,
	},
	-- Knees absorb terrain: extra crouch per stud/s² of upward acceleration (dips), and the
	-- legs extend over crests. Clamped and smoothed.
	AbsorbPerAccel = 0.05,
	MaxAbsorb = 12,
	AbsorbResponsiveness = 8,

	-- Riding state shared with other players so they see your stance (sends per second, max)
	ReplicationRate = 10,
}
