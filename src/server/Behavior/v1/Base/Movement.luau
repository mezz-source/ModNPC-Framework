local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Movement = {}
Movement.__index = Movement

local MovementEnum = TypeMovement.MovementEnum
local MoveStateEnum = TypeState.MoveStateEnum
local DodgeStateEnum = TypeState.DodgeStateEnum
local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local StateEvents = TypeCharacterEvents.Names.State
local SPRINT_COST = TypeStamina.Costs.Sprint
local DODGE_COST = TypeStamina.Costs.Dodge
local MOVE_STATE_KEY = TypeState.Keys.MoveState
local DODGE_STATE_KEY = TypeState.Keys.DodgeState

-- How long a dodge is active (seconds), and the velocity change (studs/s) it throws the character with
local DODGE_DURATION = 0.3
local DODGE_IMPULSE = 130
-- The dodge animations are the ones in the Dodges category of the NPC's Assets/Animations. There is none for Forward,
-- a forward dodge is only the burst of movement.
local DODGE_ANIMATION_CATEGORY = "Dodges"
local DODGE_ANIMATION_PRIORITY = Enum.AnimationPriority.Action3
local DODGE_ANIMATION_FADE = 0.1
local DODGE_ANIMATIONS: { [TypeMovement.MovementDirection]: string } = {
	[MovementEnum.Left] = "DodgeLeft",
	[MovementEnum.Right] = "DodgeRight",
	[MovementEnum.Backward] = "DodgeBack",
}

-- A directional move only leads a few studs ahead of the character, and "relative to facing" shifts as it turns,
-- so a held walk is re-issued this often (seconds). Unchanged directions in between cost no request.
local WALK_REFRESH = 0.1
-- Fixed order so the same set of directions always produces the same signature
local WALK_ORDER = { MovementEnum.Forward, MovementEnum.Backward, MovementEnum.Left, MovementEnum.Right }

function Movement.new(base, character)
	local self = setmetatable({}, Movement)
	self.Base = base
	self.Character = character
	self.CharacterAPI = base.CharacterAPI
	self.rotationLocked = false
	-- Whether sprinting is the current speed, regardless of whether we're moving right now
	self.sprinting = false
	-- The sources holding the character still, keyed by that source
	self.movementLocks = {} :: { [any]: boolean }
	-- The direction each walk source (usually a Walk task) is holding, keyed by that source
	self.walkDirections = {} :: { [any]: TypeMovement.MovementDirection }
	-- What the last walk request was for, and when, so identical holds aren't re-sent every frame
	self.walkSignature = ""
	self.walkIssuedAt = 0
	-- Whether the character could move when the walk was last applied, so a change is acted on once, not on every state
	self.walkAllowed = true
	-- Ends the dodge that is active, so a destroyed character doesn't touch its state afterwards
	self.dodgeThread = nil :: thread?

	self.Base.State:Register(MOVE_STATE_KEY, MoveStateEnum)
	self.Base.State:Register(DODGE_STATE_KEY, DodgeStateEnum)
	self.EventSubscriptions = {
		self.Base.Events:Subscribe(HumanoidEvents.MoveBegan, function()
			self:_setMoving(true)
		end),
		self.Base.Events:Subscribe(HumanoidEvents.MoveEnded, function()
			self:_setMoving(false)
		end),
		-- Landing or recovering from a stagger picks the held walks back up, and being launched drops them
		self.Base.Events:Subscribe(StateEvents.Changed, function()
			self:_onStateChanged()
		end),
	}

	return self
end

-- Whether the character may move right now. Asked through the function so mods can hook it.
function Movement:_canMove(): boolean
	return self.Base.Functions:CallFunction(FunctionEnum.CanMove) and true or false
end

-- Holds only change what is walked when whether we can move flips, so this only does anything then
function Movement:_onStateChanged()
	-- Nothing to pick up or drop, and no reason to ask before there is something to walk
	if next(self.walkDirections) == nil then
		return
	end

	if self:_canMove() ~= self.walkAllowed then
		self:_applyWalk(true)
	end
end

function Movement:_setMoving(isMoving: boolean)
	if not isMoving then
		self.Base.State:Set(MOVE_STATE_KEY, MoveStateEnum.None)
	elseif self.sprinting then
		self.Base.State:Set(MOVE_STATE_KEY, MoveStateEnum.Sprinting)
	else
		self.Base.State:Set(MOVE_STATE_KEY, MoveStateEnum.Walking)
	end
end

-- Speed changes while already moving switch Walking <-> Sprinting; while standing still the state stays None
function Movement:_refreshMoveState()
	if not self.Base.State:Is(MOVE_STATE_KEY, MoveStateEnum.None) then
		self:_setMoving(true)
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

-- The walk speed follows the sprinting flag, unless the character is held still
function Movement:_applyWalkSpeed()
	local speed
	if next(self.movementLocks) ~= nil then
		speed = 0
	elseif self.sprinting then
		speed = self.Base.Configuration:GetMovementSetting("SprintSpeed")
	else
		speed = self.Base.Configuration:GetMovementSetting("WalkSpeed")
	end

	self.Base.CharacterAPI:SetWalkSpeed(speed)
end

-- Starting a sprint costs the sprint price once (on top of what the sprint drains while it lasts), and an exhausted
-- character can't pay it. Whether it started is returned, with why not if it didn't; asking again while sprinting is free.
function Movement:StartSprinting(): (boolean, string?)
	if self.sprinting then
		return true
	end

	local paid, declinedReason = self.Base.Functions:CallFunction(FunctionEnum.PurchaseStamina, SPRINT_COST, true)
	if paid == false then
		return false, declinedReason
	end

	self.sprinting = true
	self:_applyWalkSpeed()
	self:_refreshMoveState()

	return true
end

function Movement:StopSprinting()
	self.sprinting = false
	self:_applyWalkSpeed()
	self:_refreshMoveState()
end

-- Holds the character still on behalf of `source` (an attack that cannot be walked out of, ...) until it lets go.
-- Sprinting can still be toggled meanwhile, it just takes effect once the last hold is released.
function Movement:LockMovement(source: any)
	if self.movementLocks[source] then
		return
	end

	self.movementLocks[source] = true
	self:_applyWalkSpeed()
end

function Movement:UnlockMovement(source: any)
	if not self.movementLocks[source] then
		return
	end

	self.movementLocks[source] = nil
	self:_applyWalkSpeed()
end

function Movement:SetSprinting(isSprinting: boolean)
	if isSprinting then
		return self:StartSprinting()
	else
		return self:StopSprinting()
	end
end

function Movement:Jump()
	if not self:_canMove() then
		return
	end

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

-- Relative to the way the character faces; the API works out where that is. Does nothing while the character can't move.
function Movement:Move(direction: TypeMovement.MovementDirection)
	if not self:_canMove() then
		return
	end

	return self.CharacterAPI:MoveInDirection(direction)
end

function Movement:MoveTo(position: Vector3)
	if not self:_canMove() then
		return
	end

	return self.CharacterAPI:MoveTo(position)
end

-- Immediate stop. Walks that are still being held will pick the character back up on their next refresh,
-- so stop those at the source (end the Walk task) instead.
function Movement:StopMoving()
	return self.CharacterAPI:StopMoving()
end

-- The distinct directions currently held, in a stable order
function Movement:_getHeldDirections(): { TypeMovement.MovementDirection }
	local held = {}
	for _, direction in self.walkDirections do
		held[direction] = true
	end

	local directions = {}
	for _, direction in WALK_ORDER do
		if held[direction] then
			table.insert(directions, direction)
		end
	end
	return directions
end

-- Walks the combination of everything held. Holding nothing, or only directions that cancel, stands still, and so does
-- a character that can't move (what is held is kept, and walked again once it can).
-- Without `force`, an unchanged hold is only re-sent once the refresh interval has passed. Standing still has nothing
-- to refresh.
function Movement:_applyWalk(force: boolean)
	self.walkAllowed = self:_canMove()
	local directions = if self.walkAllowed then self:_getHeldDirections() else {}
	local signature = table.concat(directions, ",")
	local now = os.clock()

	if not force and signature == self.walkSignature and (signature == "" or now - self.walkIssuedAt < WALK_REFRESH) then
		return
	end

	self.walkSignature = signature
	self.walkIssuedAt = now
	if #directions == 0 then
		self.CharacterAPI:StopMoving()
	else
		self.CharacterAPI:MoveInDirection(directions)
	end
end

-- Hold a walk direction on behalf of `source` until it is cleared. Safe to call every frame; a source can
-- change its direction by calling again. Directions held by different sources are walked together.
function Movement:SetWalkDirection(source: any, direction: TypeMovement.MovementDirection)
	if not table.find(WALK_ORDER, direction) then
		error("Invalid walk direction: " .. tostring(direction))
	end

	local changed = self.walkDirections[source] ~= direction
	self.walkDirections[source] = direction
	self:_applyWalk(changed)
end

-- Let go of `source`'s direction, walking whatever is still held or stopping if that was the last
function Movement:ClearWalkDirection(source: any)
	if self.walkDirections[source] == nil then
		return
	end

	self.walkDirections[source] = nil
	self:_applyWalk(true)
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

function Movement:DodgeLeft(): (boolean, string?)
	return self:Dodge(MovementEnum.Left)
end

function Movement:DodgeRight(): (boolean, string?)
	return self:Dodge(MovementEnum.Right)
end

function Movement:DodgeForward(): (boolean, string?)
	return self:Dodge(MovementEnum.Forward)
end

function Movement:DodgeBackward(): (boolean, string?)
	return self:Dodge(MovementEnum.Backward)
end

-- Loads the dodge animations. Runs once the character is built and its functions are registered, because loading is a
-- function.
function Movement:InitDodges()
	local animations = {}
	for _, animation in ipairs(self.Base.Assets:GetData().Animations[DODGE_ANIMATION_CATEGORY] or {}) do
		animations[animation.Name] = animation
	end

	for _, animationName in pairs(DODGE_ANIMATIONS) do
		local animation = animations[animationName]
		if not animation then
			warn("Missing dodge animation:", DODGE_ANIMATION_CATEGORY .. "/" .. animationName)
			continue
		end

		-- looped is false: a dodge is a one-shot
		self.Base.Functions:CallFunction(
			FunctionEnum.LoadAnimation,
			animation,
			animationName,
			DODGE_ANIMATION_PRIORITY,
			false
		)
	end
end

-- Dodges in a random direction
function Movement:DodgeRandomDirection(): (boolean, string?)
	return self:Dodge(WALK_ORDER[math.random(1, #WALK_ORDER)])
end

-- Throws the character in `direction` (relative to the way it faces) and holds the dodge state Active for the dodge's
-- duration. Refuses while a dodge is already active, or when CanDodge says no.
function Movement:Dodge(direction: TypeMovement.MovementDirection): (boolean, string?)
	local functions = self.Base.Functions
	if self.Base.State:Is(DODGE_STATE_KEY, DodgeStateEnum.Active) then
		return false, "Already dodging"
	end
	local canDodge, reason = functions:CallFunction(FunctionEnum.CanDodge, direction)
	if not canDodge then
		return false, reason or "Cannot dodge"
	end

	local mustBeRested = true

	-- Only once the dodge is certain to happen, and before anything of it does: a dodge that can't be paid for doesn't happen
	local paid, declinedReason = functions:CallFunction(FunctionEnum.PurchaseStamina, DODGE_COST, mustBeRested)
	if not paid then
		return false, declinedReason or "Cannot afford to dodge"
	end

	local animationName = DODGE_ANIMATIONS[direction]
	if animationName then
		functions:CallFunction(FunctionEnum.PlayAnimation, animationName, DODGE_ANIMATION_FADE, nil, false)
	end

	-- The dodge takes over: a held walk or chase would otherwise keep steering the character during it
	for _, task in self.Base.Scheduler:GetTasks(TypeTask.CategoriesEnum.Movement) do
		self.Base.Scheduler:Stop(task, "Dodge started")
	end

	self.Base.State:Set(DODGE_STATE_KEY, DodgeStateEnum.Active)
	self.CharacterAPI:ApplyImpulseInDirection(direction, DODGE_IMPULSE)
	self.Base.Functions:CallFunction(FunctionEnum.PlaySoundCategory, "Dodge")

	self.dodgeThread = task.delay(DODGE_DURATION, function()
		self.dodgeThread = nil
		self.Base.State:Set(DODGE_STATE_KEY, DodgeStateEnum.None)
	end)

	return true
end

function Movement:Init()
	self:SetSprinting(false)
end

function Movement:Destroy()
	if self.dodgeThread then
		task.cancel(self.dodgeThread)
		self.dodgeThread = nil
	end
	table.clear(self.walkDirections)
	table.clear(self.movementLocks)
	for _, subscription in ipairs(self.EventSubscriptions) do
		subscription.Unsubscribe()
	end
	self.EventSubscriptions = {}
end

return Movement
