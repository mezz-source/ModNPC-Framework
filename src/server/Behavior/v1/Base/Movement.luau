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

-- Relative to the way the character faces; the API works out where that is
function Movement:Move(direction: TypeMovement.MovementDirection)
	return self.CharacterAPI:MoveInDirection(direction)
end

function Movement:MoveTo(position: Vector3)
	return self.CharacterAPI:MoveTo(position)
end

function Movement:StopMoving()
	return self.CharacterAPI:StopMoving()
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
	-- TODO: dodging, which will need an API primitive for the burst of movement in `direction`
end

-- Whether the character is currently able to be evasive (strafing, dodging, ...)
-- TODO: stub, should account for things like stuns, attacks in progress, and being airborne
function Movement:CanBeEvasive(): boolean
	return true
end

function Movement:Init()
	self:SetSprinting(false)
end

return Movement
