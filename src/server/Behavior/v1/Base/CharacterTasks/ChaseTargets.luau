local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeDisposition = require(ServerScriptService.ModNPCServer.Types.v1.TypeDisposition)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

local Axes = TypeDisposition.Axes
local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local StateEvents = TypeCharacterEvents.Names.State
local MovementEnum = TypeMovement.MovementEnum
local ENGAGE_STATE_KEY = TypeState.Keys.EngageState
local EngageStateEnum = TypeState.EngageStateEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- Distance checks cost an API request, so we decide what to do ten times a second instead of every frame.
-- The walk tasks we started keep the character moving in between.
local CHASE_INTERVAL = 0.1

-- Not far enough out for the usual sprint (see GetSprintDeviation), a character that means to attack may still sprint the
-- rest of the way in now and then: a lunge that lasts a random time in this range (seconds), started at LUNGE_RATE a second
-- by a character at full Aggression
local LUNGE_MIN_DURATION = 0.6
local LUNGE_MAX_DURATION = 1.5
local LUNGE_RATE = 3

-- Seconds the target hears of a sprint at it (SprintingTowards). Short on purpose: it is a heads-up, not a promise.
local SPRINT_STIMULANT_DURATION = 1

-- Gets the character to the target: walks toward them (sprinting while they are far) until we are as close as the engage
-- distance asks, and then hands them over to Engage, which holds the spacing from there. Control moves between the two
-- through the EngageState (see Distance): we act only while Pursuing, and we are the one that ends it by reaching them.
-- We keep the character facing the target the whole time, Engage's strafing relies on it.
local ChaseTargetsTask = {}
ChaseTargetsTask.__index = ChaseTargetsTask
setmetatable(ChaseTargetsTask, Task)

function ChaseTargetsTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Targetting,
		Resources = { ResourceEnum.Movement },
		Dependencies = {
			Dependencies.CharacterTasks,
			Dependencies.Configuration,
			Dependencies.Distance,
			Dependencies.Events,
			Dependencies.Functions,
			Dependencies.Scheduler,
		},
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, ChaseTargetsTask)
	self.Character = base.Character
	self.CharacterTasks = base.CharacterTasks
	self.Configuration = base.Configuration
	self.Distance = base.Distance
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler

	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
	-- The target we are chasing and keeping our eyes on, if any
	self.FocusTarget = nil :: TypeTargetting.TargettingContext?
	self.sprinting = false
	-- Until when (os.clock) a lunge that was rolled lasts
	self.lungeUntil = 0
	-- The walk toward the target we have running, its own task so it can be stopped on its own
	self.driveWalk = nil :: TypeTask.Task?
	self.driveDirection = nil :: string?
	-- Time since we last decided what to do. Starts full so the first update acts immediately.
	self.sinceChase = CHASE_INTERVAL

	return self
end

-- we do this in case this changes later
function ChaseTargetsTask:UpdateTargettingRange()
	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
end

-- How far past the ideal distance we can be before it's worth sprinting, nil if unconfigured (never sprint)
function ChaseTargetsTask:GetSprintDeviation(): number?
	local deviation = self.Configuration:GetRange("SprintDiff")
	return if type(deviation) == "number" then math.max(deviation :: number, 0) else nil
end

-- Stopping only touches the walk speed when the state actually flips, not every frame. Starting is asked for every time
-- the chase wants a sprint: the character can lose the sprint without us (an exhausted one is made to stop, see Stamina),
-- and one that is still sprinting makes asking again free. A sprint that is declined (starting one costs stamina, and an
-- exhausted character can't pay it) doesn't count as started either.
function ChaseTargetsTask:SetSprinting(isSprinting: boolean)
	if not isSprinting then
		if self.sprinting then
			self.sprinting = false
			self.Functions:CallFunction(FunctionEnum.StopSprinting)
		end
		return
	end

	-- (a replacement that returns nothing counts as started)
	local wasSprinting = self.sprinting
	local started = self.Functions:CallFunction(FunctionEnum.StartSprinting)
	self.sprinting = started ~= false

	if self.sprinting and not wasSprinting then
		self:_announceSprint()
	end
end

-- Lets whoever we're chasing know we just broke into a sprint at them (a SprintingTowards stimulant)
function ChaseTargetsTask:_announceSprint()
	local target = self.FocusTarget
	if not target then
		return
	end

	local distance = self.Distance:GetDistanceTo(target.Character)
	self.Base
		:NewStimulant(TypeStimulant.Names.SprintingTowards)
		:To(target.Character)
		:WithPriority(TypeStimulant.Priorities.Low)
		:Lasting(SPRINT_STIMULANT_DURATION)
		:WithData({ Distance = distance or 0 } :: TypeStimulant.SprintingTowardsData)
		:Send()
end

-- Start a walk task. It clears `driveWalk` on itself when it ends (stopped by us, or replaced), so a field that still
-- holds a task always holds a running one.
function ChaseTargetsTask:StartWalk(direction: string)
	local walk, createError = self.CharacterTasks.Walk.new(direction)
	if not walk then
		warn("Chase could not create walk:", createError)
		return
	end

	local started, startError = self.Scheduler:Start(walk)
	if not started then
		warn("Chase could not start walk:", startError)
		return
	end

	self.driveWalk = walk
	walk.Terminated:Connect(function()
		if self.driveWalk == walk then
			self.driveWalk = nil
			self.driveDirection = nil
		end
	end)
end

-- Walk straight toward the target, or nil to stop doing so. Does nothing if we already are.
function ChaseTargetsTask:SetDrive(direction: string?)
	if self.driveDirection == direction then
		return
	end

	local previous = self.driveWalk
	self.driveWalk = nil
	self.driveDirection = nil
	if previous then
		previous:Stop("Chase changed direction")
	end

	if direction then
		self:StartWalk(direction)
		if self.driveWalk then
			self.driveDirection = direction
		end
	end
end

-- Ends the walk we started and stands the character down
function ChaseTargetsTask:StopMoving()
	self:SetDrive(nil)
	self:SetSprinting(false)
end

-- Always face whoever we're chasing, so walking forward is walking toward them
function ChaseTargetsTask:SetFocusTarget(target: TypeTargetting.TargettingContext?)
	local previous = self.FocusTarget
	self.FocusTarget = target

	local sameCharacter = (if previous then previous.Character else nil) == (if target then target.Character else nil)
	if sameCharacter then
		-- already facing them (or still nothing), only the context was refreshed
		return
	end

	if target then
		self.Functions:CallFunction(FunctionEnum.SetFocusTarget, target.Character)
		-- a new target deserves an immediate decision, not whatever is left of the interval
		self.sinceChase = CHASE_INTERVAL
	else
		self.Functions:CallFunction(FunctionEnum.RemoveFocusTarget)
		self:StopMoving()
	end
end

-- The distance we mean to close to, the hold distance of our targetting range: the engage distance (moved by how aggressive
-- we feel), or closer if the attack we mean to make needs it. It is asked the same way by Engage, which is what makes the
-- two agree on where the handoff happens.
function ChaseTargetsTask:GetIdealDistance(): number?
	return self.Functions:CallFunction(FunctionEnum.GetHoldDistance, self.targettingRange)
end

-- Whether to be sprinting in on the target as a lunge: only when we mean to attack (ready to, with an attack in mind to get
-- in range of). A lunge is rolled on the chase tick and then lasts its whole time.
function ChaseTargetsTask:ShouldLunge(): boolean
	local meansToAttack = self.Functions:CallFunction(FunctionEnum.IsReadyToAttack)
		and self.Functions:CallFunction(FunctionEnum.GetDesiredAttack) ~= nil
	if not meansToAttack then
		self.lungeUntil = 0
		return false
	end

	if os.clock() < self.lungeUntil then
		return true
	end

	local aggression = self.Functions:CallFunction(FunctionEnum.GetDisposition, Axes.Aggression)
	if type(aggression) ~= "number" then
		return false
	end

	local chance = 1 - math.exp(-math.clamp(aggression :: number, 0, 1) * LUNGE_RATE * CHASE_INTERVAL)
	if math.random() >= chance then
		return false
	end

	self.lungeUntil = os.clock() + LUNGE_MIN_DURATION + math.random() * (LUNGE_MAX_DURATION - LUNGE_MIN_DURATION)
	return true
end

-- Walk toward the target until we are as close as the ideal distance. Reaching it is the end of the chase: we stand
-- still and, if there is an Engage task to take over, hand the target to it.
function ChaseTargetsTask:Chase(target: TypeTargetting.TargettingContext)
	local ideal = self:GetIdealDistance()
	local distance = self.Distance:GetDistanceTo(target.Character)
	if not ideal or not distance then
		self:StopMoving()
		return
	end

	if distance <= ideal then
		self:StopMoving()
		-- without an Engage task nothing would hold the spacing, so we stay in charge and just stand here
		if self.Scheduler:GetTask(CategoryEnum.Engage) then
			self.Distance:UpdateEngagement(distance, ideal)
		end
		return
	end

	-- sprint while we're far from where we want to be, walk once we're close to it
	local sprintDeviation = self:GetSprintDeviation()
	local farOut = sprintDeviation ~= nil and self.Distance.IsFarPast(distance, ideal, sprintDeviation)
	self:SetSprinting(farOut or self:ShouldLunge())
	self:SetDrive(MovementEnum.Forward)
end

function ChaseTargetsTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	local subscriptions = {
		self.Events:Subscribe(TargettingEvents.NewFocusTarget, function(context)
			self:SetFocusTarget(context)
		end),
		self.Events:Subscribe(TargettingEvents.FocusedTargetChanged, function(change)
			self:SetFocusTarget(change.Current)
		end),
		self.Events:Subscribe(TargettingEvents.LostFocusTarget, function()
			self:SetFocusTarget(nil)
		end),
		-- Engage handing the target back is our cue to take over right now, and anything taking it from us means we let go
		-- of the character right now
		self.Events:Subscribe(StateEvents.Changed, function(change)
			if change.Key ~= ENGAGE_STATE_KEY then
				return
			end

			if change.New == EngageStateEnum.Pursuing then
				self.sinceChase = CHASE_INTERVAL
			else
				self:StopMoving()
			end
		end),
		-- pick up configuration edits while running instead of keeping the value read at construction
		self.Configuration:Observe({ "ThoughtProcess", "TargettingRange" }, function()
			self:UpdateTargettingRange()
		end),
	}

	self.Terminated:Connect(function()
		for _, subscription in subscriptions do
			subscription:Unsubscribe()
		end

		if self.FocusTarget then
			self.Functions:CallFunction(FunctionEnum.RemoveFocusTarget)
		end
		-- the walk is a separate task and wouldn't end with us
		self:StopMoving()
		self.FocusTarget = nil
	end)

	-- We may have started after targetting already picked someone, so catch up instead of waiting for a change
	self:SyncFocusTarget()

	return true
end

-- The focus events are how we normally hear about a new target. This reads the same state straight from the
-- targetting task, so a missed event (or a task started late) can't leave us chasing someone out of date.
function ChaseTargetsTask:SyncFocusTarget()
	local targettingTask = self.Scheduler:GetTask(CategoryEnum.Targetting) :: any
	if targettingTask then
		self:SetFocusTarget(targettingTask.FocusTarget)
	end
end

function ChaseTargetsTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.sinceChase += deltaTime
	if self.sinceChase < CHASE_INTERVAL then
		return
	end

	self.sinceChase = 0

	self:SyncFocusTarget()

	-- Engaged means the way to the target is Engage's, we only keep our eyes on them
	if not self.Distance:IsPursuing() then
		return
	end

	local target = self.FocusTarget
	if target then
		self:Chase(target)
	end
end

return ChaseTargetsTask
