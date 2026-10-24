--[[
	HudUI
	Riding HUD: speedometer (km/h + bar), movement status, camera mode, control hints,
	a "Change Sport" button, and short centre-screen callouts for landings and crashes.
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
	Clean = Color3.fromRGB(120, 230, 140),
	Sketchy = Color3.fromRGB(255, 200, 80),
	Hard = Color3.fromRGB(255, 160, 90),
	Crash = Color3.fromRGB(255, 80, 80),
	Info = Color3.fromRGB(200, 220, 255),
}

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

local function corner(radius: number)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function label(properties)
	properties.BackgroundTransparency = 1
	properties.Font = properties.Font or Enum.Font.GothamBold
	properties.TextColor3 = properties.TextColor3 or Color3.new(1, 1, 1)
	properties.TextScaled = true
	return Create("TextLabel", properties)
end

local function hintText(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Stick steer  ·  Tuck  ·  Brake  ·  hold Jump to charge  ·  Cam  ·  Reset"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "L-Stick steer  ·  RT tuck  ·  LT brake  ·  hold A to charge jump  ·  Y camera  ·  Back reset"
	end
	return "A/D steer  ·  Shift tuck  ·  Ctrl brake  ·  hold Space to charge jump  ·  W push  ·  V camera  ·  R reset"
end

local function build()
	screen = Create("ScreenGui", {
		Name = "DownhillHUD",
		ResetOnSpawn = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- Speedometer
	local speedo = Create("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(260, 110),
		BackgroundColor3 = Color3.fromRGB(10, 16, 26),
		BackgroundTransparency = 0.3,
		Parent = screen,
	}, { corner(12) })

	speedLabel = label({
		Name = "Speed",
		Text = "0",
		Font = Enum.Font.GothamBlack,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.fromOffset(150, 58),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = speedo,
	})
	label({
		Name = "Unit",
		Text = "KM/H",
		TextColor3 = Color3.fromRGB(160, 180, 205),
		Position = UDim2.fromOffset(172, 30),
		Size = UDim2.fromOffset(70, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = speedo,
	})

	local bar = Create("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor3 = Color3.fromRGB(40, 50, 66),
		Parent = speedo,
	}, { corner(4) })
	barFill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(90, 200, 255),
		Parent = bar,
	}, { corner(4) })
	-- Jump charge: a thin amber line under the speed bar, only visible while charging
	chargeFill = Create("Frame", {
		Name = "JumpCharge",
		Position = UDim2.new(0, 0, 1, 2),
		Size = UDim2.new(0, 0, 0, 3),
		BackgroundColor3 = Color3.fromRGB(255, 190, 70),
		BorderSizePixel = 0,
		Parent = bar,
	})

	statusLabel = label({
		Name = "Status",
		Text = "",
		TextColor3 = Color3.fromRGB(160, 180, 205),
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -32, 0, 18),
		Parent = speedo,
	})

	-- Top-right: camera mode + change sport
	local topRight = Create("Frame", {
		Name = "TopRight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(200, 80),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	cameraLabel = label({
		Name = "CameraMode",
		Text = "",
		TextColor3 = Color3.fromRGB(200, 215, 235),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = topRight,
	})
	local changeSport = Create("TextButton", {
		Name = "ChangeSport",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 28),
		Size = UDim2.fromOffset(150, 36),
		BackgroundColor3 = Color3.fromRGB(22, 30, 44),
		BackgroundTransparency = 0.15,
		Text = "CHANGE SPORT",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Parent = topRight,
	}, { corner(8) })
	changeSport.Activated:Connect(function()
		SportSelect.Open()
	end)

	-- Bottom-left: control hints
	label({
		Name = "Hints",
		Text = hintText(),
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(220, 230, 245),
		TextStrokeTransparency = 0.6,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -140),
		Size = UDim2.new(0.5, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = screen,
	})

	-- Centre callout
	callout = label({
		Name = "Callout",
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(420, 50),
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
	callout.TextStrokeTransparency = 0.4
	TweenService:Create(callout, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function statusText(state): string
	if state.Mode == "Wipeout" then
		return "WIPEOUT"
	elseif state.Mode == "Stumbling" then
		return "STUMBLE"
	elseif state.Mode == "Frozen" then
		return "GET READY"
	elseif not state.Grounded then
		return "AIRBORNE"
	elseif state.JumpCharge > 0.05 then
		return "CHARGING JUMP"
	elseif state.Braking then
		return "BRAKING"
	elseif state.Tucking then
		return "TUCK"
	elseif state.Speed < 3 then
		return "READY"
	end
	return "CARVING"
end

local function update(dt: number)
	local state = Movement.State
	displayedSpeed += (state.Speed - displayedSpeed) * (1 - math.exp(-12 * dt))
	speedLabel.Text = tostring(math.floor(Units.StudsPerSecondToKmh(displayedSpeed) + 0.5))
	barFill.Size = UDim2.fromScale(math.clamp(displayedSpeed / Config.MaxSpeed, 0, 1), 1)
	chargeFill.Size = UDim2.new(state.JumpCharge, 0, 0, 3)
	statusLabel.Text = statusText(state)
end

function HudUI.Start(movementController, cameraController, sportSelectUI)
	Movement = movementController
	Camera = cameraController
	SportSelect = sportSelectUI
	build()

	local function refreshCamera()
		cameraLabel.Text = `CAMERA: {CAMERA_LABELS[Camera.GetModeName()] or Camera.GetModeName()}`
	end
	refreshCamera()
	Camera.ModeChanged:Connect(refreshCamera)

	Movement.Activated:Connect(function()
		screen.Enabled = true
	end)
	Movement.Deactivated:Connect(function()
		screen.Enabled = false
	end)
	screen.Enabled = Movement.IsActive()

	Movement.Landed:Connect(function(quality, _impact, airTime)
		if airTime < 0.4 then
			return
		end
		local message = if quality == "Clean" then "CLEAN LANDING" elseif quality == "Sketchy" then "SKETCHY LANDING" else "HARD LANDING"
		showCallout(`{message}  ·  {string.format("%.1f", airTime)}s AIR`, CALLOUT_COLORS[quality])
	end)
	Movement.Crashed:Connect(function(reason)
		showCallout(if reason == "Collision" then "WIPEOUT!" else "BAD LANDING!", CALLOUT_COLORS.Crash)
	end)
	Movement.Stumbled:Connect(function(reason)
		if reason ~= "Recovery" then
			showCallout("STUMBLE", CALLOUT_COLORS.Sketchy)
		end
	end)
	Movement.Reset:Connect(function()
		showCallout("RESET TO START", CALLOUT_COLORS.Info)
	end)

	RunService.RenderStepped:Connect(function(dt)
		if screen.Enabled then
			update(dt)
		end
	end)
end

return HudUI
