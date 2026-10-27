--[[
	SnowGroove
	The channel a ski or snowboard cuts into the powder, left behind as a trail.

	A Trail with a groove texture (soft rim, shadowed wall, mid-tone floor, lit wall, soft rim)
	so it reads as a channel cut into the snow rather than a painted stripe. It rides on a
	"snow plane": the terrain surface under the gear (one raycast per frame), facing along the
	gear. On the plane rather than on the gear, so when the gear rolls onto an edge the groove
	still lies flat on the snow instead of tilting into it or floating.

	Off the snow (in the air, on rock or ice) the trail stops, and starts again on landing.
	Visual only: no collision, no queries, no touch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EffectsConfig = require(ReplicatedStorage.Shared.Config.EffectsConfig)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local Settings = EffectsConfig.Groove

local SnowGroove = {}
SnowGroove.__index = SnowGroove

local folder: Folder? = nil
local function getFolder(): Folder
	if not folder or not folder.Parent then
		folder = Create("Folder", { Name = "SnowGrooves", Parent = Workspace })
	end
	return folder :: Folder
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { Workspace.Terrain }

local HIDDEN = CFrame.new(0, -1e5, 0)

-- gear: the main Ski or Board part
function SnowGroove.new(gear: BasePart)
	local self = setmetatable({}, SnowGroove)
	self.Gear = gear

	local anchor = Create("Part", {
		Name = "SnowPlane",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = HIDDEN,
		Parent = getFolder(),
	})
	self.Anchor = anchor

	-- Across the gear near its nose, wider than the gear (the channel walls): the trail then
	-- runs alongside the gear as well as behind it, so it sits in a trough
	local half = gear.Size.X / 2 * Settings.WidthScale
	local z = -gear.Size.Z / 2 + Settings.NoseInset
	local a0 = Create("Attachment", { Position = Vector3.new(-half, Settings.Lift, z), Parent = anchor })
	local a1 = Create("Attachment", { Position = Vector3.new(half, Settings.Lift, z), Parent = anchor })
	self.Trail = Create("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Texture = Settings.Texture,
		TextureMode = Enum.TextureMode.Stretch,
		Color = ColorSequence.new(Settings.Color),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, Settings.StartTransparency),
			NumberSequenceKeypoint.new(0.7, (1 + Settings.StartTransparency) / 2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = Settings.Lifetime,
		LightInfluence = Settings.LightInfluence,
		LightEmission = 0,
		FaceCamera = false,
		MinLength = 0.1,
		Enabled = false,
		Parent = anchor,
	})
	self.On = false
	self.Hidden = true
	return self
end

local function setOn(self, on: boolean)
	if self.On ~= on then
		self.On = on
		self.Trail.Enabled = on
	end
end

-- contact: the gear is on snow. Appends the anchor's move to parts / cframes (BulkMoveTo).
function SnowGroove:Update(contact: boolean, speed: number, parts, cframes)
	local plane
	if contact then
		local gcf = self.Gear.CFrame
		local hit = Workspace:Raycast(gcf.Position + Vector3.yAxis * 2, Vector3.new(0, -2.8 - self.Gear.Size.Y, 0), rayParams)
		if hit then
			-- Along the direction of travel (the gear's nose points backwards when riding
			-- switch), so the channel always starts at the leading end
			local velocity = self.Gear.AssemblyLinearVelocity
			local along = if velocity.Magnitude > 1 then velocity.Unit else gcf.LookVector
			local forward = along - hit.Normal * along:Dot(hit.Normal)
			if forward.Magnitude > 1e-3 then
				plane = CFrame.lookAt(hit.Position, hit.Position + forward.Unit, hit.Normal)
			end
		end
	end
	if not plane then
		setOn(self, false)
		if not self.Hidden then
			self.Hidden = true
			table.insert(parts, self.Anchor)
			table.insert(cframes, HIDDEN)
		end
		return
	end
	self.Hidden = false
	table.insert(parts, self.Anchor)
	table.insert(cframes, plane)
	setOn(self, speed > Settings.MinSpeed)
end

function SnowGroove:Destroy()
	self.Anchor:Destroy()
end

return SnowGroove
