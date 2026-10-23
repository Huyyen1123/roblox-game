--[[
	InputConfig
	Key bindings. Steering/tuck/brake are axes read every frame from MoveKeys, the left gamepad
	thumbstick, and on touch either the default thumbstick or TouchMoveButtons.
	Discrete actions are bound through ContextActionService.
]]

return {
	MoveKeys = {
		Left = { Enum.KeyCode.A, Enum.KeyCode.Left },
		Right = { Enum.KeyCode.D, Enum.KeyCode.Right },
		Forward = { Enum.KeyCode.W, Enum.KeyCode.Up },
		Back = { Enum.KeyCode.S, Enum.KeyCode.Down },
	},

	-- Used only on touch devices when the place has no PlayerModule thumbstick.
	TouchMoveButtons = {
		Left = { Title = "<", Position = UDim2.new(0, 30, 1, -100) },
		Right = { Title = ">", Position = UDim2.new(0, 110, 1, -100) },
		Tuck = { Title = "Tuck", Position = UDim2.new(0, 70, 1, -175) },
		Brake = { Title = "Brake", Position = UDim2.new(1, -170, 1, -135) },
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

	ActionPriority = Enum.ContextActionPriority.High.Value,
	TuckThreshold = 0.5,
	BrakeThreshold = 0.5,
}
