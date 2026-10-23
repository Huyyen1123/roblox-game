--[[
	Client bootstrap.
]]

local StarterGui = game:GetService("StarterGui")

local Controllers = script.Controllers
local UI = script.UI

local InputController = require(Controllers.InputController)
local MovementController = require(Controllers.MovementController)
local CameraController = require(Controllers.CameraController)
local SportSelectUI = require(UI.SportSelectUI)
local HudUI = require(UI.HudUI)

InputController.Start()
MovementController.Start(InputController)
CameraController.Start(MovementController, InputController)
SportSelectUI.Start()
HudUI.Start(MovementController, CameraController, SportSelectUI)

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
