local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDisposition = require(ServerScriptService.ModNPCServer.Types.v1.TypeDisposition)
local TypeDistance = require(ServerScriptService.ModNPCServer.Types.v1.TypeDistance)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local StateEvents = TypeCharacterEvents.Names.State
local MovementEnum = TypeMovement.MovementEnum
local RangeStates = TypeDistance.RangeStates
local Axes = TypeDisposition.Axes
local ENGAGE_STATE_KEY = TypeState.Keys.EngageState
local EngageStateEnum = TypeState.EngageStateEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- Each strafe lasts a random time in this range (seconds)
local STRAFE_MIN_DURATION = 0.4
local STRAFE_MAX_DURATION = 1.5
-- Strafes started per second by a character at full Evasiveness while it is free to. A rate rather than a chance per
-- reaction tick, so how often a character strafes doesn't depend on how fast it reacts, and a character that is very
-- evasive still goes a while between strafes instead of starting the next as one ends.
local STRAFE_RATE = 1.5
local STRAFE_DIRECTIONS = { MovementEnum.Left, MovementEnum.Right }

-- Distance checks cost an API request, so we decide what to do ten times a second instead of every frame.
-- The walk tasks we started keep the character moving in between.
local ENGAGE_INTERVAL = 0.1

-- The guard goes up once the Guard axis (0-1) of our disposition is at or above RAISE_GUARD and comes down once it is at or
-- below LOWER_GUARD. In between it stays as it is, so a Guard hovering around one number doesn't put it up and down.
-- A held guard is for a character that feels guarded: hits it sees coming are met on their own (see Defense, which dodges
-- or raises a guard at the last moment), so a guard held at an ordinary Guard only turned fights into blocking matches.
local RAISE_GUARD = 0.7
local LOWER_GUARD = 0.5
-- While resting between exchanges (out of reach, nothing of ours to make) the character is on the defense, so the guard
-- goes up at a lower Guard
local RAISE_GUARD_RESTING = 0.5
local LOWER_GUARD_RESTING = 0.35
-- While resting the character means to be out of reach, so it only puts up with this share of the usual TooCloseDiff: it
-- backs off to near the hold distance instead of stopping as soon as it is inside the band
local REST_BAND_SHARE = 0.4

-- A target is much too close once it is nearer than this share of the hold distance. That is measured against the distance
-- itself, not the TooCloseDiff band: the band can be wide enough that it never gets near the target. Only then is backing
-- off on foot not enough and a backward dodge worth it.
local RETREAT_DISTANCE_SHARE = 0.5
-- The share of stamina a character wants left to feel comfortable enough to dodge away (it keeps the rest for blocking and
-- attacking), and the seconds between two retreats
local RETREAT_MIN_STAMINA = 0.5
local RETREAT_COOLDOWN = 1.5
-- Retreats started per second by a character at full Evasiveness while it is much too close and comfortable
local RETREAT_RATE = 5

-- A sprint to close in lasts a random time in this range (seconds), and ends early once we're no longer closing in
local SPRINT_MIN_DURATION = 0.5
local SPRINT_MAX_DURATION = 1.5
-- Sprints started per second by a character at full Aggression while it wants to attack and is out of reach
local SPRINT_RATE = 4
-- The share of stamina below which a character doesn't sprint in (a sprint stops regeneration and burns it by the second):
-- what is left is kept for defending itself and the attack itself
local SPRINT_MIN_STAMINA = 0.4
-- A sprint already under way carries on this far into the band (as a share of TooCloseDiff) before it ends, so reaching
-- the edge of the band doesn't end it after a tick. Stopping short of the near edge keeps it from overshooting into "too close".
local LUNGE_BAND_SHARE = 0.5

-- Holds the spacing to the target once ChaseTargets has brought us to it. Control moves between the two through the
-- EngageState (see Distance): we act only while Engaged, and we are the one that ends it, by the target getting further
-- from us than the engage distance allows, at which point ChaseTargets takes the target back.
--
-- The band we hold is [hold distance - TooCloseDiff, hold distance]: we back off from a target that is closer than
-- that, close in on one a little past it, and stand (or strafe around them) in between. ChaseTargets keeps us facing the
-- target, so strafing left and right circles them.
--
-- It also decides when the guard is up: while engaged, the Guard axis of our disposition raises a Block task and lowers it
-- again (see UpdateGuard). That is decided on the reaction tick, so a guard goes up at the character's reaction speed. An
-- attack cancels the guard on its own (see Attacks), and it is simply raised again later if the Guard calls for it.
local EngageTask = {}
EngageTask.__index = EngageTask
setmetatable(EngageTask, Task)

function EngageTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Engage,
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

	local self = setmetatable(task, EngageTask)
	self.CharacterTasks = base.CharacterTasks
	self.Configuration = base.Configuration
	self.Distance = base.Distance
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler

	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
	-- The target we are engaging, if any
	self.FocusTarget = nil :: TypeTargetting.TargettingContext?
	-- Whether the last decision left us free to strafe: inside the band, or too close to it (we are backing off)
	self.canStrafe = false
	-- The walks we have running. Each is its own task, so they combine (strafing while backing up, say).
	-- The drive walk closes or opens the distance, and the strafe walk circles the target.
	self.driveWalk = nil :: TypeTask.Task?
	self.driveDirection = nil :: string?
	self.strafeWalk = nil :: TypeTask.Task?
	-- Whether the last decision found the target much too close (see RETREAT_DISTANCE_SHARE), so a backward dodge is on the table
	self.muchTooClose = false
	self.lastRetreat = 0
	-- Whether the last decision had us out of reach of a target we want to attack, so a sprint to close in is on the table.
	-- A sprint that was rolled lasts until sprintUntil (os.clock) or until that stops being so.
	self.wantsToCloseIn = false
	self.sprintUntil = 0
	self.sprinting = false
	-- The Block task we raised. It can end without us (an attack cancels it, a hit it can't pay for breaks it), so it is
	-- only a guard that is up while it is running.
	self.blockTask = nil :: TypeTask.Task?
	-- Time since we last decided what to do. Starts full so the first update acts immediately.
	self.sinceEngage = ENGAGE_INTERVAL

	return self
end

-- we do this in case this changes later
function EngageTask:UpdateTargettingRange()
	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
end

-- The distance we hold from the target, the hold distance of our targetting range: the engage distance (moved by how
-- aggressive we feel), or closer if the attack we mean to make needs it. A character that can't attack is asked for its own
-- spacing again, so it backs off from where an attack had it standing. It is asked the same way by ChaseTargets, which is
-- what makes the two agree on where the handoff happens.
function EngageTask:GetIdealDistance(): number?
	return self.Functions:CallFunction(FunctionEnum.GetHoldDistance, self.targettingRange)
end

-- Start a walk task. It clears `field` on itself when it ends (duration, stopped by us, or replaced), so a
-- field that still holds a task always holds a running one.
function EngageTask:StartWalk(field: "driveWalk" | "strafeWalk", direction: string, duration: number?)
	local walk, createError = self.CharacterTasks.Walk.new(direction, duration)
	if not walk then
		warn("Engage could not create walk:", createError)
		return
	end

	local started, startError = self.Scheduler:Start(walk)
	if not started then
		warn("Engage could not start walk:", startError)
		return
	end

	self[field] = walk
	walk.Terminated:Connect(function()
		if self[field] == walk then
			self[field] = nil
			if field == "driveWalk" then
				self.driveDirection = nil
			end
		end
	end)
end

-- Walk straight toward or away from the target, or nil to stop doing either. Does nothing if we already are.
function EngageTask:SetDrive(direction: string?)
	if self.driveDirection == direction then
		return
	end

	local previous = self.driveWalk
	self.driveWalk = nil
	self.driveDirection = nil
	if previous then
		previous:Stop("Engage changed direction")
	end

	if direction then
		self:StartWalk("driveWalk", direction)
		if self.driveWalk then
			self.driveDirection = direction
		end
	end
end

function EngageTask:StopStrafe()
	local strafe = self.strafeWalk
	self.strafeWalk = nil
	if strafe then
		strafe:Stop("Engage stopped strafing")
	end
end

-- Starting is asked for every time the sprint is wanted (a sprint can be lost without us, and asking while sprinting is
-- free); a sprint that is declined doesn't count as started. Stopping only touches the walk speed when the sprint was ours.
function EngageTask:SetSprinting(isSprinting: boolean)
	if not isSprinting then
		if self.sprinting then
			self.sprinting = false
			self.Functions:CallFunction(FunctionEnum.StopSprinting)
		end
		return
	end

	-- (a replacement that returns nothing counts as started)
	local started = self.Functions:CallFunction(FunctionEnum.StartSprinting)
	self.sprinting = started ~= false
end

-- Ends every walk we started, puts the guard down and stands the character down
function EngageTask:StopMoving()
	self:SetDrive(nil)
	self:StopStrafe()
	self:SetSprinting(false)
	self:LowerGuard("Engage stood down")
	self.canStrafe = false
	self.muchTooClose = false
	self.wantsToCloseIn = false
	self.sprintUntil = 0
end

-- Whether the character is at ease enough to spend a dodge on getting away: it can pay for one with plenty left, and it is
-- not busy guarding (a dodge would drop the block)
function EngageTask:IsComfortable(): boolean
	-- (any guard, ours or one Defense raised for a hit)
	if self:IsGuardUp() or self.Functions:CallFunction(FunctionEnum.IsBlocking) then
		return false
	end

	if not self.Functions:CallFunction(FunctionEnum.CanAffordStamina, TypeStamina.Costs.Dodge, true) then
		return false
	end

	local current, max = self.Functions:CallFunction(FunctionEnum.GetStamina)
	if type(current) ~= "number" or type(max) ~= "number" or max <= 0 then
		return true
	end

	return current / max >= RETREAT_MIN_STAMINA
end

-- Rolls a backward dodge when the target is much too close and we are comfortable. As a rate like the strafe, so the
-- chance doesn't depend on how fast the character reacts, and with a cooldown so retreats don't come back to back.
function EngageTask:TryRetreat(seconds: number)
	if not self.muchTooClose or os.clock() - self.lastRetreat < RETREAT_COOLDOWN then
		return
	end

	local evasiveness = self.Functions:CallFunction(FunctionEnum.GetDisposition, Axes.Evasiveness)
	if type(evasiveness) ~= "number" then
		return
	end

	local chance = 1 - math.exp(-math.clamp(evasiveness :: number, 0, 1) * RETREAT_RATE * seconds)
	if math.random() >= chance then
		return
	end

	if not self.Functions:CallFunction(FunctionEnum.CanBeEvasive) or not self:IsComfortable() then
		return
	end

	-- a refused dodge (already dodging, can't pay) is not a retreat, so we may try again on the next tick
	if self.Functions:CallFunction(FunctionEnum.DodgeBackward) then
		self.lastRetreat = os.clock()
	end
end

-- Rolls a sprint to close in when we want to attack and are out of reach. Aggression is how often.
function EngageTask:TrySprint(seconds: number)
	if not self.wantsToCloseIn or os.clock() < self.sprintUntil then
		return
	end

	local aggression = self.Functions:CallFunction(FunctionEnum.GetDisposition, Axes.Aggression)
	if type(aggression) ~= "number" then
		return
	end

	local chance = 1 - math.exp(-math.clamp(aggression :: number, 0, 1) * SPRINT_RATE * seconds)
	if math.random() >= chance then
		return
	end

	local current, max = self.Functions:CallFunction(FunctionEnum.GetStamina)
	if type(current) == "number" and type(max) == "number" and max > 0 and current / max < SPRINT_MIN_STAMINA then
		return
	end

	self.sprintUntil = os.clock() + SPRINT_MIN_DURATION + math.random() * (SPRINT_MAX_DURATION - SPRINT_MIN_DURATION)
	-- applied now rather than on the next decision. One we couldn't start (not enough stamina) is not kept.
	self:SetSprinting(true)
	if not self.sprinting then
		self.sprintUntil = 0
	end
end

function EngageTask:IsGuardUp(): boolean
	local block = self.blockTask
	return block ~= nil and block:IsRunning()
end

-- A guard that is already up without us (Defense raised it at the last moment for a hit), which we take over instead of
-- raising our own: it stays up for as long as the Guard calls for it, and from now on it is ours to put down
function EngageTask:AdoptGuard(): boolean
	for _, block in ipairs(self.Scheduler:GetTasks(CategoryEnum.Block)) do
		if block:IsRunning() then
			local guard: any = block
			guard.Holder = "Engage"
			self.blockTask = block
			return true
		end
	end

	return false
end

-- Raises the guard: a Block task. Whether it can go up is asked first, as starting a block takes the arms from whatever is
-- using them, and a guard that couldn't have gone up anyway must not cut an attack short.
function EngageTask:RaiseGuard()
	if self:AdoptGuard() then
		return
	end

	if not self.Functions:CallFunction(FunctionEnum.CanBlock) then
		return
	end

	-- a guard we couldn't pay for even the lightest hit of would break on the first one
	if not self.Functions:CallFunction(FunctionEnum.CanAffordStamina, TypeStamina.Costs.BlockLight) then
		return
	end

	local block, createError = self.CharacterTasks.Block.new()
	if not block then
		warn("Engage could not create block:", createError)
		return
	end

	local started, startError = self.Scheduler:Start(block)
	if not started then
		warn("Engage could not start block:", startError)
		return
	end

	local guard: any = block
	guard.Holder = "Engage"
	self.blockTask = block
end

-- Lowers the guard we raised, if it is still up. It ends with its ending animation, as a guard being put down.
function EngageTask:LowerGuard(reason: string)
	local block = self.blockTask
	self.blockTask = nil
	if block and block:IsRunning() then
		block:Stop(reason)
	end
end

-- Puts the guard up and down by the Guard axis of our disposition. There is only anything to guard against while we are
-- in each other's face.
function EngageTask:UpdateGuard()
	if not self.FocusTarget or not self.Distance:IsEngaged() then
		self:LowerGuard("Nothing to guard against")
		return
	end

	local guard = self.Functions:CallFunction(FunctionEnum.GetDisposition, Axes.Guard)
	if type(guard) ~= "number" then
		return
	end

	local resting = not self.Functions:CallFunction(FunctionEnum.IsReadyToAttack)
	local raiseAt = if resting then RAISE_GUARD_RESTING else RAISE_GUARD
	local lowerAt = if resting then LOWER_GUARD_RESTING else LOWER_GUARD

	if self:IsGuardUp() then
		if guard <= lowerAt then
			self:LowerGuard("Guard lowered")
		end
	elseif guard >= raiseAt then
		self:RaiseGuard()
	end
end

-- On a thought tick we settle the guard, and while we're free to, maybe start strafing for a random time. Our disposition's
-- Evasiveness (0-1) is how often: at full Evasiveness STRAFE_RATE strafes a second are started (as odds for the time since the
-- last tick, so a slow reaction doesn't strafe less).
function EngageTask:OnReactionUpdate(elapsed: number?)
	if not self:IsRunning() then
		return
	end

	self:UpdateGuard()

	if not self.Distance:IsEngaged() or not self.FocusTarget then
		return
	end

	local seconds = math.clamp(if type(elapsed) == "number" then elapsed else ENGAGE_INTERVAL, 0, 1)
	self:TryRetreat(seconds)
	self:TrySprint(seconds)

	if not self.canStrafe or self.strafeWalk then
		return
	end

	local evasiveness = self.Functions:CallFunction(FunctionEnum.GetDisposition, Axes.Evasiveness)
	if type(evasiveness) ~= "number" then
		return
	end

	local chance = 1 - math.exp(-math.clamp(evasiveness :: number, 0, 1) * STRAFE_RATE * seconds)
	if math.random() >= chance then
		return
	end

	if not self.Functions:CallFunction(FunctionEnum.CanBeEvasive) then
		return
	end

	local direction = STRAFE_DIRECTIONS[math.random(#STRAFE_DIRECTIONS)]
	local duration = STRAFE_MIN_DURATION + math.random() * (STRAFE_MAX_DURATION - STRAFE_MIN_DURATION)
	self:StartWalk("strafeWalk", direction, duration)
end

-- Having no one to engage ends the engagement, so the next target is met by ChaseTargets again
function EngageTask:SetFocusTarget(target: TypeTargetting.TargettingContext?)
	local previous = self.FocusTarget
	self.FocusTarget = target

	local sameCharacter = (if previous then previous.Character else nil) == (if target then target.Character else nil)
	if sameCharacter then
		return
	end

	if target then
		-- a new target deserves an immediate decision, not whatever is left of the interval
		self.sinceEngage = ENGAGE_INTERVAL
	else
		self:StopMoving()
		self.Distance:ResetEngagement()
	end
end

-- The focus events are how we normally hear about a new target. This reads the same state straight from the
-- targetting task, so a missed event (or a task started late) can't leave us engaging someone out of date.
function EngageTask:SyncFocusTarget()
	local targettingTask = self.Scheduler:GetTask(CategoryEnum.Targetting) :: any
	if targettingTask then
		self:SetFocusTarget(targettingTask.FocusTarget)
	end
end

-- Keep the target inside [ideal - TooCloseDiff, ideal] (a tighter band while resting, see REST_BAND_SHARE). A target only a little past the ideal is closed in on at a
-- walk, any further and the engagement ends and ChaseTargets gets them. Leaving the band cancels any strafe, since
-- we're back to walking toward or away from them.
function EngageTask:Engage(target: TypeTargetting.TargettingContext)
	local ideal = self:GetIdealDistance()
	local distance = self.Distance:GetDistanceTo(target.Character)
	if not ideal or not distance then
		self:StopMoving()
		return
	end

	-- Whether the target is still ours is up to the distance, and so is handing them back
	if self.Distance:UpdateEngagement(distance, ideal) ~= EngageStateEnum.Engaged then
		self:StopMoving()
		return
	end

	local tooCloseDiff = self.Distance:GetTooCloseDiff()
	if not self.Functions:CallFunction(FunctionEnum.IsReadyToAttack) then
		tooCloseDiff *= REST_BAND_SHARE
	end

	local rangeState = self.Distance.Classify(distance, ideal, tooCloseDiff)
	-- circling goes along with backing off (the walks combine), it is only closing in that has no time for it
	self.canStrafe = rangeState ~= RangeStates.TooFar

	-- a strafe that has run out of time has already ended itself, this only cuts short one that shouldn't go on
	if self.strafeWalk and (not self.canStrafe or not self.Functions:CallFunction(FunctionEnum.CanBeEvasive)) then
		self:StopStrafe()
	end

	self.muchTooClose = distance < ideal * RETREAT_DISTANCE_SHARE

	-- a sprint is only for closing in on a target we mean to attack: ready to, with an attack in mind to get in range of.
	-- One is started while we're out of reach, but once rolled it runs its whole time (it is a lunge, and the attack
	-- itself ends it by taking the legs) unless we get too close or no longer mean to attack.
	local meansToAttack = self.Functions:CallFunction(FunctionEnum.IsReadyToAttack)
		and self.Functions:CallFunction(FunctionEnum.GetDesiredAttack) ~= nil
	self.wantsToCloseIn = meansToAttack and rangeState == RangeStates.TooFar
	local lungeEnd = ideal - self.Distance:GetTooCloseDiff() * LUNGE_BAND_SHARE
	local lunging = meansToAttack and distance > lungeEnd and os.clock() < self.sprintUntil
	if self.sprinting or self.sprintUntil > 0 then
		-- asking again is free, and the sprint can be lost without us
		self:SetSprinting(lunging)
	end

	if rangeState == RangeStates.TooFar or lunging then
		self:SetDrive(MovementEnum.Forward)
	elseif rangeState == RangeStates.TooClose then
		self:SetDrive(MovementEnum.Backward)
	else
		self:SetDrive(nil)
	end
end

function EngageTask:Start()
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
		self.Events:Subscribe(ThoughtEvents.ReactionUpdate, function(elapsed)
			self:OnReactionUpdate(elapsed)
		end),
		-- ChaseTargets reaching the target is our cue to take over right now, and anything taking the target from us
		-- means we let go of the character right now
		self.Events:Subscribe(StateEvents.Changed, function(change)
			if change.Key ~= ENGAGE_STATE_KEY then
				return
			end

			if change.New == EngageStateEnum.Engaged then
				self.sinceEngage = ENGAGE_INTERVAL
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

		-- the walks are separate tasks and wouldn't end with us, and ChaseTargets has to be able to take the target back
		self:StopMoving()
		self.Distance:ResetEngagement()
		self.FocusTarget = nil
	end)

	-- We may have started after targetting already picked someone, so catch up instead of waiting for a change
	self:SyncFocusTarget()

	return true
end

function EngageTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.sinceEngage += deltaTime
	if self.sinceEngage < ENGAGE_INTERVAL then
		return
	end

	self.sinceEngage = 0

	self:SyncFocusTarget()

	-- Pursuing means the way to the target is ChaseTargets'
	if not self.Distance:IsEngaged() then
		return
	end

	local target = self.FocusTarget
	if target then
		self:Engage(target)
	end
end

return EngageTask
