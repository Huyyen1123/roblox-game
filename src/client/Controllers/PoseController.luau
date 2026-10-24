--[[
	PoseController
	Applies the riding stance (RiderPose) to every riding character on this client.

	Joint Transform changes don't replicate, so each client poses all riders itself:
	  - the local rider from the movement state, every frame;
	  - other riders from a few character attributes ("Rider*") the server sets from each
	    rider's RiderState updates. Their lean already comes from the replicated root.

	The local rider sends RiderState only when it changes, at most PoseConfig.ReplicationRate
	times per second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PoseConfig = require(ReplicatedStorage.Shared.Config.PoseConfig)

local RiderPose = require(script.Parent.Parent.Animation.RiderPose)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local localPlayer = Players.LocalPlayer

local PoseController = {}

local Movement
local posers: { [Model]: any } = {}
local lastVerticalSpeed: { [Model]: number } = {}
local lastSent = nil
local lastSendTime = 0

local function poserKey(player: Player): string
	return `{player:GetAttribute(Constants.Attributes.Sport)}/{player:GetAttribute("Stance") or "Regular"}`
end

local function ensurePoser(player: Player, character: Model)
	local key = poserKey(player)
	local existing = posers[character]
	if existing and existing.Key == key then
		return existing
	end
	if existing then
		existing:Reset()
	end
	local poser = RiderPose.new(character, player:GetAttribute(Constants.Attributes.Sport), player:GetAttribute("Stance"))
	if poser then
		poser.Key = key
	end
	posers[character] = poser
	return poser
end

local function removePoser(character: Model)
	local poser = posers[character]
	if poser then
		poser:Reset()
		posers[character] = nil
	end
end

-- The default Animate script's idle animation keys the torso, head and arm joints and is
-- applied after our pose each frame, so it's paused while riding. Playback replicates, so
-- stopping it on our own character stops it for every other client too.
local function setDefaultAnimations(character: Model?, enabled: boolean)
	if not character then
		return
	end
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = enabled
	end
	if not enabled then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.2)
			end
		end
	end
end

local function localInput()
	local state = Movement.State
	return {
		Tuck = state.Tuck,
		Air = state.TrickAir and state.Mode == "Airborne",
		Brake = state.Braking or state.Mode == "Wipeout",
		Charge = state.JumpCharge,
		Steer = state.Steer,
		Stumble = state.Mode == "Stumbling" or state.Mode == "Wipeout",
		Tweak = state.Tweak,
		Grab = state.Grab,
		Speed = state.Speed,
		TimeToLand = state.TimeToLand,
	}
end

local function remoteInput(character: Model)
	return {
		Tuck = character:GetAttribute("RiderTuck") or 0,
		Air = character:GetAttribute("RiderAir") == true,
		Brake = character:GetAttribute("RiderBrake") == true,
		Charge = character:GetAttribute("RiderCharge") or 0,
		Steer = character:GetAttribute("RiderSteer") or 0,
		Stumble = character:GetAttribute("RiderStumble") == true,
		Tweak = character:GetAttribute("RiderTweak") or 0,
		Grab = character:GetAttribute("RiderGrab") or 0,
	}
end

-- Sends the local rider's state when it changes (quantized, rate-limited).
local function replicate(input)
	local packet = {
		Tuck = math.floor(input.Tuck * 10 + 0.5),
		Charge = math.floor(input.Charge * 10 + 0.5),
		Steer = math.floor(input.Steer * 10 + 0.5),
		Air = input.Air,
		Brake = input.Brake,
		Stumble = input.Stumble,
		Tweak = input.Tweak,
		Grab = input.Grab,
	}
	local now = os.clock()
	if now - lastSendTime < 1 / PoseConfig.ReplicationRate then
		return
	end
	if lastSent
		and lastSent.Tuck == packet.Tuck
		and lastSent.Charge == packet.Charge
		and lastSent.Steer == packet.Steer
		and lastSent.Air == packet.Air
		and lastSent.Brake == packet.Brake
		and lastSent.Stumble == packet.Stumble
		and lastSent.Tweak == packet.Tweak
		and lastSent.Grab == packet.Grab
	then
		return
	end
	lastSent = packet
	lastSendTime = now
	Remotes.RiderState:FireServer(packet)
end

local function step(dt: number)
	local seen = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or not player:GetAttribute(Constants.Attributes.Sport) then
			continue
		end

		local input
		if player == localPlayer then
			if not Movement.IsActive() then
				continue
			end
			input = localInput()
			replicate(input)
		else
			local root = character:FindFirstChild("HumanoidRootPart")
			if not root then
				continue
			end
			input = remoteInput(character)
		end

		-- Vertical acceleration (from the replicated root) lets the knees absorb dips and crests;
		-- the root's roll tells the legs how far the rider leans into a turn
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			input.Lean = math.asin(math.clamp(root.CFrame.RightVector.Y, -1, 1))
			-- Spin rate drives the upper body leading a spin; speed sets how deep carves go
			input.Spin = root.AssemblyAngularVelocity.Y
			input.Speed = input.Speed or root.AssemblyLinearVelocity.Magnitude
			local verticalSpeed = root.AssemblyLinearVelocity.Y
			local previous = lastVerticalSpeed[character]
			lastVerticalSpeed[character] = verticalSpeed
			input.VerticalAccel = if previous and dt > 0 then (verticalSpeed - previous) / dt else 0
		end

		local poser = ensurePoser(player, character)
		if poser then
			seen[character] = true
			poser:Update(dt, input)
		end
	end

	for character in posers do
		if not seen[character] then
			removePoser(character)
			lastVerticalSpeed[character] = nil
		end
	end
end

function PoseController.Start(movementController)
	Movement = movementController

	Movement.Landed:Connect(function(_, impact)
		local character = localPlayer.Character
		local poser = character and posers[character]
		if poser then
			poser:OnLanded(impact)
		end
	end)
	Movement.Activated:Connect(function()
		setDefaultAnimations(localPlayer.Character, false)
	end)
	Movement.Deactivated:Connect(function()
		lastSent = nil
		setDefaultAnimations(localPlayer.Character, true)
	end)
	if Movement.IsActive() then
		setDefaultAnimations(localPlayer.Character, false)
	end

	RunService.PreSimulation:Connect(step)
end

return PoseController
