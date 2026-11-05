local ServerScriptService = game:GetService("ServerScriptService")
local TypeBounce = require(ServerScriptService.ModNPCServer.Types.v1.TypeBounce)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local MovementEnum = TypeMovement.MovementEnum
local BounceStateEnum = TypeState.BounceStateEnum
local BOUNCE_STATE_KEY = TypeState.Keys.BounceState

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies

local FADE_TIME = 0.1

-- A character whose attack just bounced off the one coming the other way (see Attacks:BounceAttack). It is thrown back, plays
-- the Bounce sound, the BounceEffect VFX and a random AttackBounce animation of the equipped weapon, and holds the bounce state
-- until that animation ends, during which it can't attack (see Abilities). It is free to do anything else.
-- A character with no such animation has nothing to hold on to, so its bounce is over at once.
-- Claims no resources on purpose: a guard or a parry taking the arms must not end the wait for the next attack.
local BounceTask = {}
BounceTask.__index = BounceTask
setmetatable(BounceTask, Task)

function BounceTask.new(base)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Bounce,
		Dependencies = {
			Dependencies.Assets,
			Dependencies.Functions,
			Dependencies.State,
		},
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, BounceTask)
	self.Assets = base.Assets
	self.CharacterAPI = base.CharacterAPI
	self.Functions = base.Functions
	self.State = base.State

	-- The track playing, and how long it has been
	self.AnimationName = nil :: string?
	self.Waited = 0
	self.StoppedConnection = nil :: any
	-- Set when the weapon holding the animation went: its tracks are unloaded already
	self.AnimationsGone = false

	return self
end

function BounceTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (animation over, staggered, weapon gone, death), let go of everything we took
	self.Terminated:Connect(function()
		self:_cleanup()
	end)

	self.State:Set(BOUNCE_STATE_KEY, BounceStateEnum.Bouncing)
	self.CharacterAPI:ApplyImpulseInDirection(MovementEnum.Backward, TypeBounce.BackwardImpulse)

	local weapon = self.Functions:CallFunction(FunctionEnum.GetEquippedWeapon)
	if weapon then
		self.Functions:CallFunction(FunctionEnum.PlaySound, TypeBounce.Sound, weapon)
		self.Functions:CallFunction(FunctionEnum.PlayVFX, TypeBounce.VFX, weapon, weapon)
	end

	local handle = self:_playAnimation(weapon)
	if not handle then
		self:Complete("No bounce animation")
		return true
	end

	-- Stopped fires when the animation ends as well as when it is stopped
	self.StoppedConnection = handle.Stopped:Connect(function()
		self:Complete("Bounce finished")
	end)

	return true
end

-- A random animation of the weapon's category. Only the weapon's own were loaded, so the NPC's are no fallback.
function BounceTask:_playAnimation(weapon: Instance?): any
	local animations = if weapon then self.Assets:GetData(weapon).Animations[TypeBounce.AnimationCategory] else nil
	if not animations or #animations == 0 then
		return nil
	end

	local animationName = animations[math.random(1, #animations)].Name
	local handle = self.Functions:CallFunction(FunctionEnum.PlayAnimation, animationName, FADE_TIME, nil, false)
	if handle then
		self.AnimationName = animationName
	end

	return handle
end

function BounceTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	-- an animation that never ends must not keep the character from attacking forever
	self.Waited += deltaTime
	if self.Waited > TypeBounce.Timeout then
		self:Stop("Timed out waiting for the bounce animation")
	end
end

-- Ends the task because something else takes the character over. With `animationsGone` (the weapon that held them was
-- unequipped) there are no tracks left to put away.
function BounceTask:Cancel(reason: string?, animationsGone: boolean?): boolean
	self.AnimationsGone = animationsGone == true

	return self:Stop(reason or "Bounce cancelled")
end

function BounceTask:_cleanup()
	if self.StoppedConnection then
		self.StoppedConnection:Disconnect()
		self.StoppedConnection = nil
	end

	self.State:Set(BOUNCE_STATE_KEY, BounceStateEnum.None)

	-- A dead character has no tracks left to stop, and neither does one whose weapon went
	if self.AnimationName and self.Base:IsAlive() and not self.AnimationsGone then
		self.Functions:CallFunction(FunctionEnum.StopAnimation, self.AnimationName, FADE_TIME)
	end
end

return BounceTask
