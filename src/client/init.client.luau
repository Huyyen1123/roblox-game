--[[
	Client bootstrap.
]]

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Controllers = script.Controllers
local UI = script.UI

local InputController = require(Controllers.InputController)
local MovementController = require(Controllers.MovementController)
local CameraController = require(Controllers.CameraController)
local PoseController = require(Controllers.PoseController)
local EffectsController = require(Controllers.EffectsController)
local SportSelectUI = require(UI.SportSelectUI)
local HudUI = require(UI.HudUI)
local RaceUI = require(UI.RaceUI)
local Minimap = require(UI.Minimap)

InputController.Start()
MovementController.Start(InputController)
CameraController.Start(MovementController, InputController)
PoseController.Start(MovementController)
EffectsController.Start(MovementController)
SportSelectUI.Start()
HudUI.Start(MovementController, CameraController, SportSelectUI)
RaceUI.Start(MovementController)
Minimap.Start(MovementController)

-- Practice spots (T: trick park)
InputController.SpotRequested:Connect(function(spot)
	game:GetService("ReplicatedStorage").Remotes.RequestSpot:FireServer(spot)
end)

if RunService:IsStudio() then
	require(script.Dev.DevTools).Start(MovementController)
end

-- Route the Roblox menu's "Reset Character" to a server-validated reset to the start gate.
local resetBindable = Instance.new("BindableEvent")
resetBindable.Event:Connect(MovementController.RequestReset)
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", resetBindable) then
			return
		end
		task.wait(1)
	end
end)
