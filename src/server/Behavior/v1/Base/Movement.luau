local ServerScriptService = game:GetService("ServerScriptService")
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local Movement = {}
Movement.__index = Movement

local MovementEnum = TypeMovement.MovementEnum

function Movement.new(base, character)
	local self = setmetatable({}, Movement)
	self.Base = base
	self.Character = character
	self.CharacterAPI = base.CharacterAPI
	self.rotationLocked = false

	return self
end

function Movement:_directionToMoveVector(direction: TypeMovement.MovementDirection): Vector3
	if direction == MovementEnum.Left then
		return -self.Character.PrimaryPart.CFrame.RightVector
	elseif direction == MovementEnum.Right then
		return self.Character.PrimaryPart.CFrame.RightVector
	elseif direction == MovementEnum.Forward then
		return self.Character.PrimaryPart.CFrame.LookVector
	elseif direction == MovementEnum.Backward then
		return -self.Character.PrimaryPart.CFrame.LookVector
	else
		return Vector3.zero
	end
end

function Movement:_lockRotation()
	self.rotationLocked = true
	return self.CharacterAPI:LockRotation()
end

function Movement:_unlockRotation()
	self.rotationLocked = false
	return self.CharacterAPI:UnlockRotation()
end

function Movement:StartSprinting()
	local sprintSpeed = self.Base.Configuration:GetMovementSetting("SprintSpeed")
	self.Base.CharacterAPI:SetWalkSpeed(sprintSpeed)
end

function Movement:StopSprinting()
	local walkSpeed = self.Base.Configuration:GetMovementSetting("WalkSpeed")
	self.Base.CharacterAPI:SetWalkSpeed(walkSpeed)
end

function Movement:SetSprinting(isSprinting: boolean)
	if isSprinting then
		self:StartSprinting()
	else
		self:StopSprinting()
	end
end

function Movement:Jump()
	self.Base.CharacterAPI:Jump()
end

function Movement:MoveLeft()
	self:Move(MovementEnum.Left)
end

function Movement:MoveRight()
	self:Move(MovementEnum.Right)
end

function Movement:MoveForward()
	self:Move(MovementEnum.Forward)
end

function Movement:MoveBackward()
	self:Move(MovementEnum.Backward)
end

function Movement:Move(direction: TypeMovement.MovementDirection)
	local moveDirection = self:_directionToMoveVector(direction)
	return self.CharacterAPI:MoveTo(self.Character.PrimaryPart.Position + moveDirection)
end

function Movement:MoveTo(position: Vector3)
	return self.CharacterAPI:MoveTo(position)
end

function Movement:WalkTo(position: Vector3)
	return self.CharacterAPI:WalkTo(position)
end

function Movement:SetFocusTarget(target: Instance)
	self:_lockRotation()
	return self.CharacterAPI:SetFocusTarget(target)
end

function Movement:RemoveFocusTarget()
	self:_unlockRotation()
	return self.CharacterAPI:RemoveFocusTarget()
end

function Movement:ApplyImpulse(velocityChange: Vector3)
	return self.CharacterAPI:ApplyImpulse(velocityChange)
end

function Movement:ApplyAngularImpulse(angularVelocityChange: Vector3)
	return self.CharacterAPI:ApplyAngularImpulse(angularVelocityChange)
end

function Movement:DodgeLeft()
	self:Dodge(MovementEnum.Left)
end

function Movement:DodgeRight()
	self:Dodge(MovementEnum.Right)
end

function Movement:DodgeForward()
	self:Dodge(MovementEnum.Forward)
end

function Movement:DodgeBackward()
	self:Dodge(MovementEnum.Backward)
end

function Movement:Dodge(direction: TypeMovement.MovementDirection)
	local dodgeDirection = self:_directionToMoveVector(direction)
	-- TODO: dodging
end

function Movement:Init()
	self:SetSprinting(false)
end

return Movement
