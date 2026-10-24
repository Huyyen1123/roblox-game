--[[
	InputConfig
	Every binding lives here so gameplay code only ever sees actions ("Tuck", "Jump"),
	never keys. PC is the primary target; gamepad and touch bindings sit alongside.

	Kinds of input:
	  Steer     – axis from keys, the left stick, or touch.
	  Held      – true while any bound input is down (Tuck, Brake, Push).
	  Actions   – discrete presses/releases (Jump, ToggleCamera, Reset, Zoom).
	Snowboard tricks: Q/E/F grab in the air (indy, melon, method); W/S nose/tail press on the
	snow (W only presses above push speed). A/D spin in the air.
	Reserved for Phase 4: W/S flip in the air.
]]

return {
	Steer = {
		Left = { Enum.KeyCode.A, Enum.KeyCode.Left },
		Right = { Enum.KeyCode.D, Enum.KeyCode.Right },
	},

	Held = {
		Tuck = {
			Keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR2 },
			TouchButton = { Title = "Tuck", Position = UDim2.new(1, -170, 1, -135) },
		},
		Brake = {
			Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl, Enum.KeyCode.ButtonL2 },
			TouchButton = { Title = "Brake", Position = UDim2.new(1, -245, 1, -60) },
		},
		Push = {
			Keys = { Enum.KeyCode.W, Enum.KeyCode.Up },
		},
		TailPress = {
			Keys = { Enum.KeyCode.S, Enum.KeyCode.Down },
		},
		GrabIndy = {
			Keys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
		},
		GrabMelon = {
			Keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonB },
		},
		GrabMethod = {
			Keys = { Enum.KeyCode.F, Enum.KeyCode.ButtonR1 },
		},
	},

	Actions = {
		Jump = {
			Keys = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA },
			TouchButton = { Title = "Jump", Position = UDim2.new(1, -95, 1, -90) },
		},
		ToggleCamera = {
			Keys = { Enum.KeyCode.V, Enum.KeyCode.ButtonY },
			TouchButton = { Title = "Cam", Position = UDim2.new(1, -170, 1, -60) },
		},
		Reset = {
			Keys = { Enum.KeyCode.R, Enum.KeyCode.ButtonSelect },
			TouchButton = { Title = "Reset", Position = UDim2.new(1, -95, 1, -165) },
		},
		ZoomIn = {
			Keys = { Enum.KeyCode.I, Enum.KeyCode.DPadUp },
		},
		ZoomOut = {
			Keys = { Enum.KeyCode.O, Enum.KeyCode.DPadDown },
		},
	},

	-- Touch steering buttons, used only when the place has no default thumbstick.
	TouchSteerButtons = {
		Left = { Title = "<", Position = UDim2.new(0, 30, 1, -100) },
		Right = { Title = ">", Position = UDim2.new(0, 110, 1, -100) },
	},

	ActionPriority = Enum.ContextActionPriority.High.Value,
	StickDeadzone = 0.15,
	StickPushThreshold = 0.6, -- left stick forward beyond this counts as Push
}
