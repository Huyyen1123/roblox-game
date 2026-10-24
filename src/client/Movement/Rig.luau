--[[
	Rig
	Owns everything the controller attaches to a character: the Humanoid state changes that
	stop default walking physics, and the two constraints that drive the HumanoidRootPart.
	  LinearVelocity   – the velocity the controller commands each step
	  AlignOrientation – the orientation the controller commands each step
]]

local Rig = {}
Rig.__index = Rig

local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.StrafingNoPhysics,
}

function Rig.new(humanoid: Humanoid, root: BasePart, config)
	for _, stateType in DISABLED_STATES do
		humanoid:SetStateEnabled(stateType, false)
	end
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local attachment = Instance.new("Attachment")
	attachment.Name = "DownhillAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DownhillVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.MaxForce = root.AssemblyMass * config.MaxForcePerMass
	linearVelocity.VectorVelocity = root.AssemblyLinearVelocity
	linearVelocity.Parent = root

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "DownhillOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment
	alignOrientation.MaxTorque = config.Orientation.MaxTorque
	alignOrientation.Responsiveness = config.Orientation.GroundResponsiveness
	alignOrientation.CFrame = root.CFrame.Rotation
	alignOrientation.Parent = root

	return setmetatable({
		Humanoid = humanoid,
		Root = root,
		Config = config,
		Attachment = attachment,
		LinearVelocity = linearVelocity,
		AlignOrientation = alignOrientation,
	}, Rig)
end

-- Keeps the Humanoid out of its own states (it can be knocked out of Physics by the engine).
function Rig:EnforcePhysicsState()
	if self.Humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
		self.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

function Rig:Drive(velocity: Vector3)
	self.LinearVelocity.MaxForce = self.Root.AssemblyMass * self.Config.MaxForcePerMass
	self.LinearVelocity.VectorVelocity = velocity
end

function Rig:Orient(rotation: CFrame, responsiveness: number)
	self.AlignOrientation.CFrame = rotation
	self.AlignOrientation.Responsiveness = responsiveness
end

function Rig:Destroy()
	self.LinearVelocity:Destroy()
	self.AlignOrientation:Destroy()
	self.Attachment:Destroy()

	local humanoid = self.Humanoid
	if humanoid.Parent then
		for _, stateType in DISABLED_STATES do
			humanoid:SetStateEnabled(stateType, true)
		end
		humanoid.AutoRotate = true
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

return Rig
