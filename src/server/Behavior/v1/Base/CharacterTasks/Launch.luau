local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local PhasedStagger = require(script.Parent._PhasedStagger)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local LaunchSounds = TypeDamage.LaunchSounds
local MovementEnum = TypeMovement.MovementEnum
local AirStateEnum = TypeState.AirStateEnum
local AIR_STATE_KEY = TypeState.Keys.AirState
local Phases = PhasedStagger.Phases

-- Seconds in the air after which the launch is over whether or not the character has come down
local LAUNCH_TIMEOUT = 5
-- Seconds a character that has not left the ground yet (the lift took a moment, or was too weak to) is waited for
-- before it counts as landed
local LEAVE_GROUND_GRACE = 0.5

-- A character thrown up and back, the heaviest way to lose control. It is lifted with an upward impulse as the task starts
-- and thrown back with a backward one as it leaves the ground, plays the start animation with the loop behind it, and
-- lands: once it is back on the ground (or LAUNCH_TIMEOUT has passed) the end animation plays, and the character
-- recovers when that has finished. The character is launched (no moving, attacking or dodging) the whole time. See
-- PhasedStagger for the phases.
--   Starting it takes the launched state, which cancels the movement and attack tasks and breaks a stagger the character
--   was in (see Damage:BeginLaunch), so only a character that is already launched or dead refuses to start one.
local LaunchTask = {}
LaunchTask.__index = LaunchTask
setmetatable(LaunchTask, PhasedStagger)

function LaunchTask.new(base, upwardImpulse: number, backwardImpulse: number)
	-- written this way round so NaN fails too
	if type(upwardImpulse) ~= "number" or not (upwardImpulse >= 0) then
		return nil, "Launch needs an upward impulse of zero or more"
	end
	if type(backwardImpulse) ~= "number" or not (backwardImpulse >= 0) then
		return nil, "Launch needs a backward impulse of zero or more"
	end

	local self, errorMessage = PhasedStagger.new(base, LaunchTask, {
		Animations = TypeDamage.LaunchAnimations,
		Begin = FunctionEnum.BeginLaunch,
		End = FunctionEnum.EndLaunch,
		Dependencies = { TypeTask.Dependencies.State },
	})
	if not self then
		return nil, errorMessage
	end

	self.CharacterAPI = base.CharacterAPI
	self.State = base.State
	self.UpwardImpulse = upwardImpulse
	self.BackwardImpulse = backwardImpulse
	-- Set once the character has been seen in the air, so the ground it has not left yet is not taken for a landing
	self.LeftGround = false

	return self
end

function LaunchTask:_playSound(soundName: string)
	self.Functions:CallFunction(FunctionEnum.PlaySound, soundName)
end

-- Only the lift is applied as the task begins. A humanoid on the ground keeps setting its own horizontal velocity, which
-- would eat a backward impulse sent at the same moment, so that one waits until the character has left the ground.
function LaunchTask:_onBegin()
	self.CharacterAPI:ApplyImpulse(Vector3.new(0, self.UpwardImpulse, 0))
	self:_playSound(LaunchSounds.Start)
end

-- Notices the character leaving the ground, and throws it back the moment it does
function LaunchTask:_watchTakeoff()
	if self.LeftGround or not self.State:Is(AIR_STATE_KEY, AirStateEnum.Falling) then
		return
	end

	self.LeftGround = true
	self.CharacterAPI:ApplyImpulseInDirection(MovementEnum.Backward, self.BackwardImpulse)
end

function LaunchTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self:_watchTakeoff()
	PhasedStagger.Update(self, deltaTime)
end

-- The landing sound goes with the end animation, which is also what plays when the launch times out
function LaunchTask:_onEnterPhase(phase: string)
	if phase == Phases.End then
		self:_playSound(LaunchSounds.Land)
	end
end

-- The launch is over once the character is back on the ground, or has been up for too long
function LaunchTask:_holdOver(): boolean
	if self.Elapsed >= LAUNCH_TIMEOUT then
		return true
	end

	-- in the air (_watchTakeoff has seen it leave), it is not over until it comes down
	if self.State:Is(AIR_STATE_KEY, AirStateEnum.Falling) then
		return false
	end

	return self.LeftGround or self.Elapsed >= LEAVE_GROUND_GRACE
end

return LaunchTask
