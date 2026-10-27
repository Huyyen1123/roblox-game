--[[
	RaceUI
	Race guidance at the top of the screen, driven by the server's RaceEvent (RaceService):
	  - the run clock and checkpoint count while racing
	  - a small arrow toward the nearest beam of the next checkpoint (or the finish), and how
	    far it is; nothing else, so routes stay the rider's choice
	  - short split / finish / best-time callouts
	At the summit it asks the rider to cross the start line; in the trick park it shows that
	the ride is untimed. Hidden when not riding.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Create = require(ReplicatedStorage.Shared.Util.Create)
local CourseMap = require(script.Parent.CourseMap)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local TEXT = Color3.fromRGB(245, 248, 255)
local SUBTLE = Color3.fromRGB(190, 205, 225)
local ORANGE = Color3.fromRGB(255, 150, 60)
local GOOD = Color3.fromRGB(150, 235, 165)
local STUDS_TO_METRES = 0.28

local RaceUI = {}

local Movement
local screen: ScreenGui
local clockLabel: TextLabel
local infoLabel: TextLabel
local arrow: TextLabel
local distanceLabel: TextLabel
local splitLabel: TextLabel

local phase = "Free"
local startedAt = 0 -- os.clock() when the run started (client-side display only)
local nextIndex = 1
local finalTime: number? = nil

local function formatTime(seconds: number): string
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%04.1f", minutes, seconds - minutes * 60)
end

local function label(properties)
	properties.BackgroundTransparency = 1
	properties.Font = properties.Font or Enum.Font.GothamBold
	properties.TextColor3 = properties.TextColor3 or TEXT
	properties.TextStrokeColor3 = Color3.fromRGB(8, 14, 24)
	properties.TextStrokeTransparency = properties.TextStrokeTransparency or 0.45
	return Create("TextLabel", properties)
end

local function flash(text: string, color: Color3)
	splitLabel.Text = text
	splitLabel.TextColor3 = color
	splitLabel.TextTransparency = 0
	splitLabel.TextStrokeTransparency = 0.45
	TweenService:Create(splitLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function build()
	screen = Create("ScreenGui", {
		Name = "RaceHUD",
		ResetOnSpawn = false,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local panel = Create("Frame", {
		Name = "Race",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(260, 92),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	clockLabel = label({
		Name = "Clock",
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = panel,
	})
	infoLabel = label({
		Name = "Info",
		Text = "",
		TextSize = 13,
		TextColor3 = SUBTLE,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = panel,
	})
	-- Direction to the next checkpoint: a small chevron that turns with the camera
	arrow = label({
		Name = "Arrow",
		Text = "▲",
		TextSize = 20,
		TextColor3 = ORANGE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -22, 0, 64),
		Size = UDim2.fromOffset(24, 24),
		Parent = panel,
	})
	distanceLabel = label({
		Name = "Distance",
		Text = "",
		TextSize = 12,
		TextColor3 = SUBTLE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.5, -6, 0, 57),
		Size = UDim2.fromOffset(90, 14),
		Parent = panel,
	})
	splitLabel = label({
		Name = "Split",
		Text = "",
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(420, 26),
		Parent = screen,
	})
	screen.Parent = player:WaitForChild("PlayerGui")
end

local function onRaceEvent(kind: string, a: any, b: any, c: any)
	if kind == "Ready" then
		phase = "Ready"
		nextIndex = 1
		finalTime = nil
	elseif kind == "Start" then
		phase = "Racing"
		startedAt = os.clock()
		nextIndex = 1
		flash("GO!", GOOD)
	elseif kind == "Checkpoint" then
		nextIndex = a + 1
		-- Keep the display clock in step with the server's
		startedAt = os.clock() - c
		flash(`CHECKPOINT {a}/{b}   {formatTime(c)}`, ORANGE)
	elseif kind == "Finish" then
		phase = "Finished"
		finalTime = a
		if math.abs(a - b) < 0.01 then
			flash(`FINISH  {formatTime(a)}  ·  NEW BEST`, GOOD)
		else
			flash(`FINISH  {formatTime(a)}  ·  BEST {formatTime(b)}`, TEXT)
		end
	elseif kind == "Free" then
		phase = "Free"
	elseif kind == "Invalid" then
		phase = "Free"
		flash("RUN NOT COUNTED", Color3.fromRGB(255, 120, 110))
	end
end

-- Where to head: the nearest beam of the next checkpoint, or the finish
local function target(map, position: Vector3): Vector3?
	if phase == "Ready" then
		return map.Start
	elseif phase ~= "Racing" then
		return nil
	end
	local checkpoint = map.Checkpoints[nextIndex]
	if not checkpoint then
		return map.Finish
	end
	local best, bestDistance = nil, math.huge
	for _, beam in checkpoint.Beams do
		local distance = (beam - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = beam, distance
		end
	end
	return best
end

local function update()
	local map = CourseMap.Get()
	local root = Movement.State.Root
	if not map or not root then
		clockLabel.Text = ""
		infoLabel.Text = ""
		arrow.Visible = false
		distanceLabel.Text = ""
		return
	end
	local count = #map.Checkpoints
	if phase == "Racing" then
		clockLabel.Text = formatTime(os.clock() - startedAt)
		infoLabel.Text = if nextIndex <= count then `CHECKPOINT {nextIndex - 1}/{count}` else "TO THE FINISH"
	elseif phase == "Ready" then
		clockLabel.Text = "0:00.0"
		infoLabel.Text = "CROSS THE START LINE"
	elseif phase == "Finished" then
		clockLabel.Text = if finalTime then formatTime(finalTime) else ""
		infoLabel.Text = "FINISHED  ·  R TO RACE AGAIN"
	else
		clockLabel.Text = ""
		infoLabel.Text = if player:GetAttribute("Spot") == "TrickPark" then "TRICK PARK  ·  FREE RIDE" else "FREE RIDE"
	end

	local goal = target(map, root.Position)
	if goal then
		local camera = Workspace.CurrentCamera
		local look = camera.CFrame.LookVector
		local toGoal = goal - root.Position
		local flatLook = Vector2.new(look.X, look.Z)
		local flatGoal = Vector2.new(toGoal.X, toGoal.Z)
		if flatLook.Magnitude > 1e-3 and flatGoal.Magnitude > 1e-3 then
			flatLook, flatGoal = flatLook.Unit, flatGoal.Unit
			-- Signed angle from the view direction to the goal (clockwise on screen)
			local angle = math.atan2(flatLook.X * flatGoal.Y - flatLook.Y * flatGoal.X, flatLook:Dot(flatGoal))
			arrow.Rotation = math.deg(angle)
		end
		arrow.Visible = true
		distanceLabel.Text = string.format("%d m", math.floor(toGoal.Magnitude * STUDS_TO_METRES + 0.5))
	else
		arrow.Visible = false
		distanceLabel.Text = ""
	end
end

function RaceUI.Start(movementController)
	Movement = movementController
	build()
	Remotes:WaitForChild("RaceEvent").OnClientEvent:Connect(onRaceEvent)
	phase = player:GetAttribute("RacePhase") or "Free"
	Movement.Activated:Connect(function()
		screen.Enabled = true
	end)
	Movement.Deactivated:Connect(function()
		screen.Enabled = false
	end)
	screen.Enabled = Movement.IsActive()
	RunService.RenderStepped:Connect(function()
		if screen.Enabled then
			update()
		end
	end)
end

return RaceUI
