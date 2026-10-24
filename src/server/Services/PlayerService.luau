--[[
	PlayerService
	Server authority for spawning, sport selection, and resets.

	The client simulates its own character (it has network ownership), but every decision
	that matters - which sport you ride, where you respawn, how often you may reset - is
	validated here.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MovementConfig = require(ReplicatedStorage.Shared.Config.MovementConfig)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local CharacterUtil = require(ReplicatedStorage.Shared.Util.CharacterUtil)

local Remotes = ReplicatedStorage.Remotes
local Attributes = Constants.Attributes

local OUT_OF_BOUNDS_CHECK_INTERVAL = 1
local SPORT_CHANGE_COOLDOWN = 0.5

local PlayerService = {}

local CourseService
local EquipmentService

local lastReset: { [Player]: number } = {}
local lastSportChange: { [Player]: number } = {}
local spawnSlots: { [Player]: number } = {}
local nextSpawnSlot = 0

local function setupCollisionGroups()
	local group = Constants.RiderCollisionGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	PhysicsService:CollisionGroupSetCollidable(group, group, MovementConfig.RidersCollide)
end

local function assignCollisionGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = Constants.RiderCollisionGroup
	end
end

-- Moves a living character and tells its client to reset movement state there.
-- The only way the server relocates riders, so every teleport takes the same path.
function PlayerService.TeleportTo(player: Player, target: CFrame)
	local character = player.Character
	local _, root = CharacterUtil.GetAlive(character)
	if not root then
		return
	end

	pcall(player.RequestStreamAroundAsync, player, target.Position)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(target)
	Remotes.ResetState:FireClient(player, target)
end

local function teleportToStart(player: Player)
	PlayerService.TeleportTo(player, CourseService.GetSpawnCFrame(spawnSlots[player]))
end

local function onCharacterAdded(player: Player, character: Model)
	for _, descendant in character:GetDescendants() do
		assignCollisionGroup(descendant)
	end
	character.DescendantAdded:Connect(assignCollisionGroup)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		task.delay(MovementConfig.RespawnDelay, function()
			if player.Parent and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end)

	character:WaitForChild("HumanoidRootPart")
	local sport = player:GetAttribute(Attributes.Sport)
	if sport then
		EquipmentService.Equip(character, sport)
	end

	-- Defer one frame so the default spawn placement has finished before we move the character.
	task.defer(teleportToStart, player)
end

local function onPlayerAdded(player: Player)
	spawnSlots[player] = nextSpawnSlot
	nextSpawnSlot += 1

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	CourseService.WaitUntilReady()
	if player.Parent then
		player:LoadCharacter()
	end
end

local function onSelectSport(player: Player, sportId: any)
	if not SportConfig.IsValid(sportId) then
		return
	end
	if player:GetAttribute(Attributes.InRace) then
		return
	end

	local now = os.clock()
	if now - (lastSportChange[player] or 0) < SPORT_CHANGE_COOLDOWN then
		return
	end
	lastSportChange[player] = now

	player:SetAttribute(Attributes.Sport, sportId)
	if player.Character then
		EquipmentService.Equip(player.Character, sportId)
	end
end

local function onRequestReset(player: Player)
	local now = os.clock()
	if now - (lastReset[player] or 0) < MovementConfig.ResetCooldown then
		return
	end
	lastReset[player] = now
	teleportToStart(player)
end

-- Server-side safety net in case a client never asks for a reset after falling off the world.
local function startOutOfBoundsWatch()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < OUT_OF_BOUNDS_CHECK_INTERVAL then
			return
		end
		elapsed = 0

		local killY = CourseService.GetKillY()
		for _, player in Players:GetPlayers() do
			local _, root = CharacterUtil.GetAlive(player.Character)
			if root and root.Position.Y < killY - 40 then
				lastReset[player] = os.clock()
				teleportToStart(player)
			end
		end
	end)
end

function PlayerService.Init(services)
	CourseService = services.CourseService
	EquipmentService = services.EquipmentService

	setupCollisionGroups()

	Remotes.SelectSport.OnServerEvent:Connect(onSelectSport)
	Remotes.RequestReset.OnServerEvent:Connect(onRequestReset)

	Players.PlayerRemoving:Connect(function(player)
		lastReset[player] = nil
		lastSportChange[player] = nil
		spawnSlots[player] = nil
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function PlayerService.Start()
	startOutOfBoundsWatch()
end

return PlayerService
