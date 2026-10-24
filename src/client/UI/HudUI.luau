--[[
	HudUI
	Minimal riding HUD:
	  - Compact speedometer, bottom-right: large km/h number, thin speed line, jump-charge line,
	    and a small status word only when it matters (tuck, brake, get ready).
	  - Control hints, bottom-left, as small chips; each fades out once the player has used it.
	  - Camera mode, shown briefly only when it changes.
	  - A small "Change Sport" button, top-right.
	  - Short centre callouts for landings (with spin: 180/360/…), crashes and resets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config.MovementConfig)
local Create = require(ReplicatedStorage.Shared.Util.Create)
local Units = require(ReplicatedStorage.Shared.Util.Units)

local player = Players.LocalPlayer

local CAMERA_LABELS = { ThirdPerson = "THIRD PERSON", FirstPerson = "FIRST PERSON" }
local CALLOUT_COLORS = {
	Clean = Color3.fromRGB(150, 235, 165),
	Sketchy = Color3.fromRGB(255, 205, 100),
	Hard = Color3.fromRGB(255, 170, 110),
	Crash = Color3.fromRGB(255, 95, 95),
	Info = Color3.fromRGB(210, 225, 255),
}
local TEXT = Color3.fromRGB(245, 248, 255)
local SUBTLE = Color3.fromRGB(180, 195, 215)
local ACCENT = Color3.fromRGB(110, 205, 255)
local CAMERA_LABEL_TIME = 1.6
-- Every hint fades after this long riding, even if unused
local HINT_TIMEOUT = 90

local HudUI = {}

local Movement
local Camera
local SportSelect
local screen: ScreenGui
local speedLabel: TextLabel
local barFill: Frame
local chargeFill: Frame
local statusLabel: TextLabel
local cameraLabel: TextLabel
local callout: TextLabel
local displayedSpeed = 0
local hints = {} -- [action] = chip
local ridingTime = 0

local function corner(radius: number)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function label(properties)
	properties.BackgroundTransparency = 1
	properties.Font = properties.Font or Enum.Font.GothamBold
	properties.TextColor3 = properties.TextColor3 or TEXT
	-- Dark outline keeps text readable against bright snow
	properties.TextStrokeColor3 = properties.TextStrokeColor3 or Color3.fromRGB(8, 14, 24)
	if not properties.TextSize then
		properties.TextScaled = true
	end
	return Create("TextLabel", properties)
end

local function fadeOut(instance: GuiObject, time: number, delay: number?)
	local goal = {}
	if instance:IsA("TextLabel") then
		goal.TextTransparency = 1
		goal.TextStrokeTransparency = 1
	end
	if instance.BackgroundTransparency < 1 then
		goal.BackgroundTransparency = 1
	end
	local tween = TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay or 0), goal)
	tween:Play()
	return tween
end

-- { action, key label, description }
local function hintList()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return {
			{ "Steer", "Stick", "Steer" },
			{ "Tuck", "Tuck", "Speed" },
			{ "Brake", "Brake", "Slow" },
			{ "Jump", "Jump", "Hold to charge" },
		}
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return {
			{ "Steer", "L-Stick", "Steer / spin" },
			{ "Tuck", "RT", "Tuck" },
			{ "Brake", "LT", "Brake" },
			{ "Jump", "A", "Hold to charge jump" },
			{ "Grab", "X/B/RB", "Grab (board, in the air)" },
			{ "Camera", "Y", "Camera" },
			{ "Reset", "Back", "Reset" },
		}
	end
	return {
		{ "Steer", "A / D", "Steer · spin in the air" },
		{ "Tuck", "Shift", "Tuck" },
		{ "Brake", "Ctrl", "Brake" },
		{ "Jump", "Space", "Hold to charge jump" },
		{ "Grab", "Q / E / F", "Grab: indy, melon, method" },
		{ "Press", "W / S", "Nose / tail press (board)" },
		{ "Camera", "V", "Camera" },
		{ "Reset", "R", "Reset" },
	}
end

local function buildHints()
	local list = Create("Frame", {
		Name = "Hints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(260, 200),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 4),
		}),
	})
	for index, hint in hintList() do
		local chip = Create("Frame", {
			Name = hint[1],
			LayoutOrder = index,
			Size = UDim2.fromOffset(240, 22),
			BackgroundTransparency = 1,
			Parent = list,
		})
		local key = label({
			Name = "Key",
			Text = hint[2],
			TextSize = 12,
			BackgroundColor3 = Color3.fromRGB(10, 16, 26),
			Size = UDim2.fromOffset(56, 20),
			Parent = chip,
		}, nil)
		key.BackgroundTransparency = 0.45
		corner(5).Parent = key
		label({
			Name = "Action",
			Text = hint[3],
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextStrokeTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(64, 0),
			Size = UDim2.new(1, -64, 1, 0),
			Parent = chip,
		})
		hints[hint[1]] = chip
	end
end

-- The player has used this control: fade its hint away.
local function learned(action: string)
	local chip = hints[action]
	if not chip then
		return
	end
	hints[action] = nil
	for _, child in chip:GetChildren() do
		if child:IsA("GuiObject") then
			fadeOut(child, 0.8, 0.6)
		end
	end
	task.delay(1.6, function()
		chip:Destroy()
	end)
end

local function build()
	screen = Create("ScreenGui", {
		Name = "DownhillHUD",
		ResetOnSpawn = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- Speedometer, bottom-right
	local speedo = Create("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -20),
		Size = UDim2.fromOffset(150, 74),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	speedLabel = label({
		Name = "Speed",
		Text = "0",
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.45,
		Size = UDim2.new(1, -44, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = speedo,
	})
	label({
		Name = "Unit",
		Text = "KM/H",
		TextSize = 12,
		TextColor3 = SUBTLE,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 28),
		Size = UDim2.fromOffset(40, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = speedo,
	})

	local bar = Create("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Color3.fromRGB(10, 16, 26),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Parent = speedo,
	}, { corner(2) })
	barFill = Create("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = bar,
	}, { corner(2) })
	-- Jump charge: a thin amber line under the speed line, only visible while charging
	chargeFill = Create("Frame", {
		Name = "JumpCharge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 3),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Color3.fromRGB(255, 190, 70),
		BorderSizePixel = 0,
		Parent = bar,
	})
	statusLabel = label({
		Name = "Status",
		Text = "",
		TextSize = 11,
		TextColor3 = SUBTLE,
		TextStrokeTransparency = 0.5,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = speedo,
	})

	-- Top-right: small change-sport button, with the camera mode briefly shown below it
	local changeSport = Create("TextButton", {
		Name = "ChangeSport",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(112, 26),
		BackgroundColor3 = Color3.fromRGB(10, 16, 26),
		BackgroundTransparency = 0.5,
		Text = "CHANGE SPORT",
		Font = Enum.Font.GothamBold,
		TextColor3 = TEXT,
		TextSize = 11,
		Parent = screen,
	}, { corner(6) })
	changeSport.Activated:Connect(function()
		SportSelect.Open()
	end)
	cameraLabel = label({
		Name = "CameraMode",
		Text = "",
		TextSize = 13,
		TextColor3 = TEXT,
		TextStrokeTransparency = 0.7,
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(240, 18),
		Parent = screen,
	})

	buildHints()

	-- Centre callout
	callout = label({
		Name = "Callout",
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(380, 36),
		TextTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = screen,
	})

	screen.Parent = player:WaitForChild("PlayerGui")
end

local function showCallout(message: string, color: Color3)
	callout.Text = message
	callout.TextColor3 = color
	callout.TextTransparency = 0
	callout.TextStrokeTransparency = 0.5
	fadeOut(callout, 1.0, 0.7)
end

local cameraTween
local function showCameraMode()
	cameraLabel.Text = CAMERA_LABELS[Camera.GetModeName()] or Camera.GetModeName()
	if cameraTween then
		cameraTween:Cancel()
	end
	cameraLabel.TextTransparency = 0
	cameraLabel.TextStrokeTransparency = 0.7
	cameraTween = fadeOut(cameraLabel, 0.6, CAMERA_LABEL_TIME)
end

-- Only the states worth knowing about; normal riding shows nothing.
local function statusText(state): string
	if state.Mode == "Frozen" then
		return "GET READY"
	elseif state.JumpCharge > 0.05 then
		return "JUMP"
	elseif state.Braking then
		return "BRAKE"
	elseif state.Tucking then
		return "TUCK"
	end
	return ""
end

-- Spin rounded to the nearest 180 (a spin within 40° of one counts as that trick)
local function spinName(degrees: number): string?
	local halves = math.floor(degrees / 180 + 0.5)
	if halves < 1 or math.abs(degrees - halves * 180) > 40 then
		return nil
	end
	return tostring(halves * 180)
end

local function update(dt: number)
	local state = Movement.State
	displayedSpeed += (state.Speed - displayedSpeed) * (1 - math.exp(-12 * dt))
	speedLabel.Text = tostring(math.floor(Units.StudsPerSecondToKmh(displayedSpeed) + 0.5))
	barFill.Size = UDim2.fromScale(math.clamp(displayedSpeed / Config.MaxSpeed, 0, 1), 1)
	chargeFill.Size = UDim2.new(state.JumpCharge, 0, 0, 2)
	statusLabel.Text = statusText(state)

	-- Hints fade once each control has been used
	if math.abs(state.Steer) > 0.5 then
		learned("Steer")
	end
	if state.Tucking then
		learned("Tuck")
	end
	if state.Braking then
		learned("Brake")
	end
	if state.Grab ~= 0 then
		learned("Grab")
	end
	if state.Press ~= 0 then
		learned("Press")
	end
	ridingTime += dt
	if ridingTime > HINT_TIMEOUT then
		for action in hints do
			learned(action)
		end
	end
end

function HudUI.Start(movementController, cameraController, sportSelectUI)
	Movement = movementController
	Camera = cameraController
	SportSelect = sportSelectUI
	build()

	Camera.ModeChanged:Connect(function()
		showCameraMode()
		learned("Camera")
	end)

	Movement.Activated:Connect(function()
		screen.Enabled = true
	end)
	Movement.Deactivated:Connect(function()
		screen.Enabled = false
	end)
	screen.Enabled = Movement.IsActive()

	Movement.Jumped:Connect(function()
		learned("Jump")
	end)
	Movement.Landed:Connect(function(quality, _impact, airTime, spin, grab)
		local trick = spinName(spin or 0)
		if airTime < 0.4 and not trick and not grab then
			return
		end
		local word = if quality == "Clean" then "CLEAN" elseif quality == "Sketchy" then "SKETCHY" else "HARD"
		local name = table.concat({ grab or "", trick or "" }, " "):match("^%s*(.-)%s*$")
		local message = if name ~= "" then `{word} {name}` else `{word} LANDING`
		showCallout(`{message}  ·  {string.format("%.1f", airTime)}s`, CALLOUT_COLORS[quality])
	end)
	Movement.Crashed:Connect(function(reason)
		showCallout(if reason == "Collision" then "WIPEOUT" else "BAD LANDING", CALLOUT_COLORS.Crash)
	end)
	Movement.Stumbled:Connect(function(reason)
		if reason ~= "Recovery" then
			showCallout("STUMBLE", CALLOUT_COLORS.Sketchy)
		end
	end)
	Movement.Reset:Connect(function()
		learned("Reset")
		showCallout("RESET TO START", CALLOUT_COLORS.Info)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if screen.Enabled then
			update(dt)
		end
	end)
end

return HudUI
