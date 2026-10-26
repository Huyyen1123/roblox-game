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

-- Back to the top of the player's course (Summit Ridge unless a dev teleport chose another)
local function teleportToStart(player: Player)
	PlayerService.TeleportTo(player, CourseService.GetSpawnCFrame(spawnSlots[player], player:GetAttribute("Course")))
end

-- Moves a player to another course's start (dev shortcut).
function PlayerService.SendToCourse(player: Player, courseId: string)
	if not CourseService.IsCourse(courseId) then
		return
	end
	player:SetAttribute("Course", courseId)
	teleportToStart(player)
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
	-- Hair, hats and face meshes can finish loading after spawn: refit the gear (the helmet is
	-- sized from them) once the avatar is complete.
	player.CharacterAppearanceLoaded:Connect(function(character)
		local sport = player:GetAttribute(Attributes.Sport)
		if sport and player.Character == character then
			EquipmentService.Equip(character, sport)
		end
	end)

	CourseService.WaitUntilReady()
	if player.Parent then
		player:LoadCharacter()
	end
end

-- Snowboard stance: which foot leads. The board's highbacks sit on the heel side, so the gear
-- is rebuilt when it changes.
local function onSelectStance(player: Player, stance: any)
	if stance ~= "Regular" and stance ~= "Goofy" then
		return
	end
	if player:GetAttribute("Stance") == stance then
		return
	end
	local now = os.clock()
	if now - (lastSportChange[player] or 0) < SPORT_CHANGE_COOLDOWN then
		return
	end
	lastSportChange[player] = now
	player:SetAttribute("Stance", stance)
	local sport = player:GetAttribute(Attributes.Sport)
	if sport and player.Character then
		EquipmentService.Equip(player.Character, sport)
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

-- Riding stance state from a rider's client, republished as character attributes so every
-- client can pose that rider. Purely cosmetic, but still type- and rate-checked.
local RIDER_STATE_MAX_PER_SECOND = 20
local riderStateWindow: { [Player]: { Start: number, Count: number } } = {}

local function onRiderState(player: Player, packet: any)
	local now = os.clock()
	local window = riderStateWindow[player]
	if not window or now - window.Start >= 1 then
		window = { Start = now, Count = 0 }
		riderStateWindow[player] = window
	end
	window.Count += 1
	if window.Count > RIDER_STATE_MAX_PER_SECOND then
		return
	end

	if type(packet) ~= "table" then
		return
	end
	local tuck, charge, steer = packet.Tuck, packet.Charge, packet.Steer
	if type(tuck) ~= "number" or type(charge) ~= "number" or type(steer) ~= "number" then
		return
	end
	if type(packet.Air) ~= "boolean" or type(packet.Brake) ~= "boolean" or type(packet.Stumble) ~= "boolean" or type(packet.Switch) ~= "boolean" then
		return
	end
	local tweak, grab = packet.Tweak, packet.Grab
	if type(tweak) ~= "number" or type(grab) ~= "number" then
		return
	end
	local landSeq, landImpact, landQuality, stumbleSide = packet.LandSeq, packet.LandImpact, packet.LandQuality, packet.StumbleSide
	if type(landSeq) ~= "number" or type(landImpact) ~= "number" or type(landQuality) ~= "number" or type(stumbleSide) ~= "number" then
		return
	end
	local character = player.Character
	if not character or not player:GetAttribute(Attributes.Sport) then
		return
	end

	character:SetAttribute("RiderTuck", math.clamp(math.floor(tuck), 0, 10) / 10)
	character:SetAttribute("RiderCharge", math.clamp(math.floor(charge), 0, 10) / 10)
	character:SetAttribute("RiderSteer", math.clamp(math.floor(steer), -10, 10) / 10)
	character:SetAttribute("RiderAir", packet.Air)
	character:SetAttribute("RiderBrake", packet.Brake)
	character:SetAttribute("RiderStumble", packet.Stumble)
	character:SetAttribute("RiderSwitch", packet.Switch)
	character:SetAttribute("RiderStumbleSide", if stumbleSide >= 0 then 1 else -1)
	-- Landing event (a counter, so every landing replays once on other clients)
	character:SetAttribute("RiderLandImpact", math.clamp(math.round(landImpact), 0, 40))
	character:SetAttribute("RiderLandQuality", math.clamp(math.round(landQuality), 1, 3))
	character:SetAttribute("RiderLandSeq", math.clamp(math.round(landSeq), 0, 255))
	-- Tweaks and grabs only exist in the air
	local air = packet.Air
	character:SetAttribute("RiderTweak", if air then math.clamp(math.round(tweak), -1, 1) else 0)
	character:SetAttribute("RiderGrab", if air then math.clamp(math.round(grab), 0, 4) else 0)
	-- Flip rate, -4..4 (the rotation itself replicates with the character)
	local flip = if type(packet.Flip) == "number" and air then math.clamp(math.round(packet.Flip), -4, 4) else 0
	character:SetAttribute("RiderFlip", flip / 4)
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
	Remotes.SelectStance.OnServerEvent:Connect(onSelectStance)
	Remotes.RequestReset.OnServerEvent:Connect(onRequestReset)
	Remotes.RiderState.OnServerEvent:Connect(onRiderState)

	Players.PlayerRemoving:Connect(function(player)
		riderStateWindow[player] = nil
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
