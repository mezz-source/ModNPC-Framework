local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum

local CategoryEnum = TypeTask.CategoriesEnum
local ResourceEnum = TypeTask.ResourcesEnum

local FADE_TIME = 0.1
-- Seconds the start or end animation gets to finish before the task gives up on it and moves on
local ANIMATION_TIMEOUT = 5

local Phases = table.freeze({
	Start = "Start",
	Loop = "Loop",
	End = "End",
})

-- Not a task of its own (the leading underscore keeps CharacterTasks from loading it), the shared body of the tasks that
-- take the character's control away for a while: Stagger and Launch. The character holds a state (taken with the
-- options' Begin function, which also cancels its movement and attack tasks, and given back with End) from the first
-- animation to the last:
--   Start   plays the start animation, and moves on when it has finished
--   Loop    plays the loop animation until the subclass says the hold is over
--   End     plays the end animation, and recovers once it has finished
-- A missing animation is skipped. A subclass decides when the hold is over by overriding _holdOver, and can act as the
-- task begins and as a phase is entered with _onBegin and _onEnterPhase.
-- Parallel on purpose: the AI tasks (chasing, attacking) have to survive it and pick up where they were. The state is what
-- keeps them from acting meanwhile.
local PhasedStagger = {}
PhasedStagger.__index = PhasedStagger
setmetatable(PhasedStagger, Task)

PhasedStagger.Phases = Phases

export type Options = {
	-- Names of the animations of each phase, as they are loaded on the character
	Animations: { Start: string, Loop: string, End: string },
	-- Functions that take and give back the state the character is held in
	Begin: string,
	End: string,
	-- The Base modules the subclass reads, on top of Functions
	Dependencies: { string }?,
}

-- `class` is the subclass the task is made an instance of
function PhasedStagger.new(base, class, options: Options)
	local dependencies = { TypeTask.Dependencies.Functions }
	for _, dependency in ipairs(options.Dependencies or {}) do
		table.insert(dependencies, dependency)
	end

	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Stagger,
		Resources = { ResourceEnum.Movement, ResourceEnum.Arms, ResourceEnum.Legs },
		Dependencies = dependencies,
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, class)
	self.Functions = base.Functions
	self.Animations = options.Animations
	self.BeginFunction = options.Begin
	self.EndFunction = options.End
	-- Where we are, how long we have been there, and how long we have been going
	self.Phase = nil :: string?
	self.PhaseElapsed = 0
	self.Elapsed = 0
	-- Waits for the animation of the start and end phases to finish
	self.PhaseConnection = nil :: any
	-- Whether we hold the state, so one we never took is never given back
	self.HoldsState = false
	-- Set when the end animation has finished. A task that ended any other way was cut short.
	self.Finished = false

	return self
end

-- Overridable. Runs once the state has been taken, before the first animation.
function PhasedStagger:_onBegin() end

-- Overridable. Runs as a phase is entered, before its animation plays.
function PhasedStagger:_onEnterPhase(_phase: string) end

-- Overridable. Asked on every update until the end phase: whether the hold is over, so the end animation plays. The
-- phase we are in is self.Phase.
function PhasedStagger:_holdOver(): boolean
	return true
end

function PhasedStagger:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (finished, replaced, death), let go of everything we took
	self.Terminated:Connect(function()
		self:_cleanup()
	end)

	local began, reason = self.Functions:CallFunction(self.BeginFunction)
	if not began then
		local failure = reason or "Cannot begin"
		self:Stop(failure)
		return false, failure
	end

	self.HoldsState = true
	self:_onBegin()
	self:_enterPhase(Phases.Start)

	return true
end

function PhasedStagger:_disconnectPhase()
	if self.PhaseConnection then
		self.PhaseConnection:Disconnect()
		self.PhaseConnection = nil
	end
end

-- The start and end phases last as long as their animation does, the loop lasts until the hold is over
function PhasedStagger:_enterPhase(phase: string)
	self:_disconnectPhase()
	self.Phase = phase
	self.PhaseElapsed = 0

	-- the end takes over from whatever came before it
	if phase == Phases.End then
		self.Functions:CallFunction(FunctionEnum.StopAnimation, self.Animations.Start, FADE_TIME)
		self.Functions:CallFunction(FunctionEnum.StopAnimation, self.Animations.Loop, FADE_TIME)
	end

	self:_onEnterPhase(phase)

	local isLoop = phase == Phases.Loop
	local handle = self.Functions:CallFunction(
		FunctionEnum.PlayAnimation,
		self.Animations[phase],
		FADE_TIME,
		nil,
		isLoop
	)
	if isLoop then
		return
	end

	if not handle then
		self:_phaseFinished(phase)
		return
	end

	self.PhaseConnection = handle.Stopped:Connect(function()
		self:_phaseFinished(phase)
	end)
end

-- Only the phase we are in can finish: a late signal from one that is already over is ignored
function PhasedStagger:_phaseFinished(phase: string)
	if not self:IsRunning() or self.Phase ~= phase then
		return
	end

	if phase == Phases.Start then
		self:_enterPhase(Phases.Loop)
	elseif phase == Phases.End then
		self.Finished = true
		self:Complete("Finished")
	end
end

function PhasedStagger:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.PhaseElapsed += deltaTime
	self.Elapsed += deltaTime

	if self.Phase ~= Phases.End and self:_holdOver() then
		self:_enterPhase(Phases.End)
		return
	end

	if self.Phase ~= Phases.Loop and self.PhaseElapsed > ANIMATION_TIMEOUT then
		warn("Waited more than", ANIMATION_TIMEOUT, "seconds for the", self.Phase, "animation to finish")
		self:_phaseFinished(self.Phase :: string)
	end
end

function PhasedStagger:_cleanup()
	self:_disconnectPhase()

	if not self.HoldsState then
		return
	end
	self.HoldsState = false

	-- Cut short: whichever animation we were showing goes with us. A dead character has none left to stop.
	if not self.Finished and self.Base:IsAlive() then
		for _, animationName in pairs(self.Animations) do
			self.Functions:CallFunction(FunctionEnum.StopAnimation, animationName, FADE_TIME)
		end
	end

	self.Functions:CallFunction(self.EndFunction)
end

return PhasedStagger
