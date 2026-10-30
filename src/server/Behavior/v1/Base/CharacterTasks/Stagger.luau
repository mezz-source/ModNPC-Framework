local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local PhasedStagger = require(script.Parent._PhasedStagger)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Phases = PhasedStagger.Phases

-- A character that has lost control of itself for a while. It plays the start animation, loops for `duration` seconds,
-- and then plays the end animation; the character is staggered (no moving, attacking or dodging) from the first of
-- those to the last, and recovers once the end animation has finished. See PhasedStagger for the phases.
--   Starting it takes the stagger state, which cancels the movement and attack tasks (see Damage:BeginStagger), so a
--   character that is already staggered, launched or dead refuses to start one.
local StaggerTask = {}
StaggerTask.__index = StaggerTask
setmetatable(StaggerTask, PhasedStagger)

function StaggerTask.new(base, duration: number)
	-- written this way round so NaN fails too
	if type(duration) ~= "number" or not (duration >= 0) then
		return nil, "Stagger needs a duration of zero or more seconds"
	end

	local self, errorMessage = PhasedStagger.new(base, StaggerTask, {
		Animations = TypeDamage.StaggerAnimations,
		Begin = FunctionEnum.BeginStagger,
		End = FunctionEnum.EndStagger,
	})
	if not self then
		return nil, errorMessage
	end

	self.Duration = duration

	return self
end

-- The loop lasts as long as the duration
function StaggerTask:_holdOver(): boolean
	return self.Phase == Phases.Loop and self.PhaseElapsed >= self.Duration
end

return StaggerTask
