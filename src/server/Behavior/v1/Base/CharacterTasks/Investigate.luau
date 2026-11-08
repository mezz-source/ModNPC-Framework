local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local InvestigateEvents = TypeCharacterEvents.Names.Investigate
local INVESTIGATE_STATE_KEY = TypeState.Keys.InvestigateState
local InvestigateStateEnum = TypeState.InvestigateStateEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- How close (studs, on the ground plane) counts as having reached the position (same reasoning as WalkTo)
local ARRIVE_DISTANCE = 3
-- An investigation that hasn't arrived by now (blocked, can't move, fell off) is given up on, so a stuck character
-- doesn't hold movement forever
local DEFAULT_TIMEOUT = 20
-- The move (and the sprint, which can be declined or taken away by Stamina) is re-asked for this often (seconds)
local REFRESH_INTERVAL = 0.5

-- Sprints to a position. Completes on arrival, and stops as soon as a new focus target is acquired: finding someone is
-- what investigating is for, and the chase takes it from there.
--
-- Takes movement entirely: starting it ends every other task holding Movement. It does that with StopResource rather
-- than a Replace policy so the essential tasks survive (ChaseTargets holds Movement too, sits idle without a focus
-- target, and has to still be running when we end on one). Holds the InvestigateState while it runs, which keeps Wander
-- from starting walks of its own over the top of us.
local InvestigateTask = {}
InvestigateTask.__index = InvestigateTask
setmetatable(InvestigateTask, Task)

function InvestigateTask.new(base, position: Vector3, timeout: number?)
	if typeof(position) ~= "Vector3" then
		return nil, "Investigate position must be a Vector3"
	end
	if timeout ~= nil and (type(timeout) ~= "number" or timeout <= 0) then
		return nil, "Investigate timeout must be a positive number"
	end

	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Movement,
		Resources = { ResourceEnum.Movement },
		Dependencies = { Dependencies.Events, Dependencies.Functions, Dependencies.Scheduler, Dependencies.State },
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, InvestigateTask)
	self.Character = base.Character
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler
	self.State = base.State

	self.Position = position
	self.Timeout = timeout or DEFAULT_TIMEOUT
	self.Elapsed = 0
	self.sinceIssued = 0
	self.sprinting = false
	-- The focus target that ended us, if one did
	self.foundTarget = nil :: Model?

	return self
end

-- Distance to the position along the ground, nil if the character has no body to measure from
function InvestigateTask:GetDistance(): number?
	local rootPart = self.Character.PrimaryPart
	if not rootPart then
		return nil
	end

	local offset = self.Position - rootPart.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

-- Asks for the move and the sprint again. Sprinting is asked every time (free while already sprinting) because Stamina
-- can make an exhausted character stop, and a declined sprint (can't pay) is retried once it can.
function InvestigateTask:_issue()
	self.Functions:CallFunction(FunctionEnum.MoveTo, self.Position)

	-- (a replacement that returns nothing counts as started)
	local started = self.Functions:CallFunction(FunctionEnum.StartSprinting)
	self.sprinting = started ~= false
end

function InvestigateTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- Take movement over: end every other Movement holder (walks, wander's walk, Engage). Essential ones are skipped by
	-- design, which keeps the idle ChaseTargets alive. We aren't in the scheduler's list until Start returns, so this
	-- can't catch us.
	self.Scheduler:StopResource(ResourceEnum.Movement, "Investigating")
	self.State:Set(INVESTIGATE_STATE_KEY, InvestigateStateEnum.Investigating)

	local subscriptions = {
		self.Events:Subscribe(TargettingEvents.NewFocusTarget, function(context)
			if context then
				self:_targetFound(context.Character)
			end
		end),
		self.Events:Subscribe(TargettingEvents.FocusedTargetChanged, function(change)
			if change.Current then
				self:_targetFound(change.Current.Character)
			end
		end),
	}

	self.Terminated:Connect(function(reason: string)
		for _, subscription in subscriptions do
			subscription:Unsubscribe()
		end

		-- however we end, don't leave the character sprinting to a place nobody wants it at any more
		if self.sprinting then
			self.sprinting = false
			self.Functions:CallFunction(FunctionEnum.StopSprinting)
		end
		self.Functions:CallFunction(FunctionEnum.StopMoving)
		self.State:Set(INVESTIGATE_STATE_KEY, InvestigateStateEnum.None)

		self.Events:Dispatch(InvestigateEvents.Ended, {
			Position = self.Position,
			FoundTarget = self.foundTarget ~= nil,
			Target = self.foundTarget,
			Reason = reason,
		} :: TypeCharacterEvents.InvestigationEnded)
	end)

	self:_issue()

	self.Events:Dispatch(InvestigateEvents.Started, {
		Position = self.Position,
	} :: TypeCharacterEvents.InvestigationStarted)

	return true
end

function InvestigateTask:_targetFound(target: Model)
	if not self:IsRunning() then
		return
	end

	self.foundTarget = target
	self:Stop("Focus target acquired")
end

function InvestigateTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.Elapsed += deltaTime
	local distance = self:GetDistance()
	if not distance then
		self:Stop("Character has no root part")
		return
	end

	if distance <= ARRIVE_DISTANCE then
		self:Complete("Arrived")
		return
	end

	if self.Elapsed >= self.Timeout then
		self:Stop("Timed out")
		return
	end

	self.sinceIssued += deltaTime
	if self.sinceIssued >= REFRESH_INTERVAL then
		self.sinceIssued = 0
		self:_issue()
	end
end

return InvestigateTask
