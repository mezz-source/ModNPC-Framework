local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)

local TargettingEvents = TypeCharacterEvents.Names.Targetting
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local TargettingRanges = TypeTargetting.Ranges
local MovementEnum = TypeMovement.MovementEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- Which Ranges configuration value to hold for each TargettingRange thought setting
local RANGE_SETTINGS = {
	[TargettingRanges.Close] = "CloseEngage",
	[TargettingRanges.Long] = "LongEngage",
}

-- What we last told the character to do, so we only issue a stop once instead of every frame
local STANDING = "Standing"
local ADVANCING = "Advancing"
local RETREATING = "Retreating"
local STRAFING = "Strafing"

-- Each strafe lasts a random time in this range (seconds)
local STRAFE_MIN_DURATION = 0.4
local STRAFE_MAX_DURATION = 1.5
local STRAFE_DIRECTIONS = { MovementEnum.Left, MovementEnum.Right }

-- Distance checks and move orders each cost an API request, so we decide what to do ten times a second
-- instead of every frame. The humanoid keeps walking toward its last order in between.
local CHASE_INTERVAL = 0.1

local ChaseTargetsTask = {}
ChaseTargetsTask.__index = ChaseTargetsTask
setmetatable(ChaseTargetsTask, Task)

function ChaseTargetsTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Movement,
		Resources = { ResourceEnum.Movement },
		Dependencies = {
			Dependencies.Configuration,
			Dependencies.Events,
			Dependencies.Movement,
			Dependencies.Scheduler,
		},
		Policy = TypeTask.Policy.Replace,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, ChaseTargetsTask)
	self.Character = base.Character
	self.CharacterAPI = base.CharacterAPI
	self.Configuration = base.Configuration
	self.Events = base.Events
	self.Movement = base.Movement
	self.Scheduler = base.Scheduler

	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
	-- The target we are chasing and keeping our eyes on, if any
	self.FocusTarget = nil :: TypeTargetting.TargettingContext?
	self.moveState = nil :: string?
	self.sprinting = false
	-- Whether the last Chase put us inside our desired range, which is the only place we strafe
	self.inRange = false
	-- The strafe in progress, if any
	self.strafe = nil :: { Direction: string, TimeLeft: number }?
	-- Time since we last decided what to do. Starts full so the first update acts immediately.
	self.sinceChase = CHASE_INTERVAL

	return self
end

-- we do this in case this changes later
function ChaseTargetsTask:UpdateTargettingRange()
	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
end

-- The distance we want to sit at from the focus target, or nil if the range isn't configured
function ChaseTargetsTask:GetIdealDistance(): number?
	local rangeSetting = RANGE_SETTINGS[self.targettingRange]
	if not rangeSetting then
		return nil
	end

	local distance = self.Configuration:GetRange(rangeSetting)
	return if type(distance) == "number" then distance else nil
end

-- How much closer than ideal we can get before we back up, 0 if unconfigured
function ChaseTargetsTask:GetTooCloseDeviation(): number
	local deviation = self.Configuration:GetRange("TooCloseDiff")
	return if type(deviation) == "number" then math.max(deviation, 0) else 0
end

-- How far past the ideal distance we can be before it's worth sprinting, nil if unconfigured (never sprint)
function ChaseTargetsTask:GetSprintDeviation(): number?
	local deviation = self.Configuration:GetRange("SprintDiff")
	return if type(deviation) == "number" then math.max(deviation, 0) else nil
end

-- Only touches the walk speed when the state actually flips, not every frame
function ChaseTargetsTask:SetSprinting(isSprinting: boolean)
	if self.sprinting == isSprinting then
		return
	end

	self.sprinting = isSprinting
	self.Movement:SetSprinting(isSprinting)
end

function ChaseTargetsTask:StopMoving()
	self.Movement:StopMoving()
	self.moveState = STANDING
	self.strafe = nil
	self:SetSprinting(false)
end

-- On a thought tick, while we're sitting in our desired range, maybe start strafing for a random time.
-- Evasiveness (0-1) is the chance that any given tick starts one.
function ChaseTargetsTask:OnReactionUpdate()
	if not self:IsRunning() or not self.FocusTarget or not self.inRange or self.strafe then
		return
	end

	local evasiveness = self.Configuration:GetThoughtSetting("Evasiveness")
	if type(evasiveness) ~= "number" or math.random() >= math.clamp(evasiveness, 0, 1) then
		return
	end

	if not self.Movement:CanBeEvasive() then
		return
	end

	self.strafe = {
		Direction = STRAFE_DIRECTIONS[math.random(#STRAFE_DIRECTIONS)],
		TimeLeft = STRAFE_MIN_DURATION + math.random() * (STRAFE_MAX_DURATION - STRAFE_MIN_DURATION),
	}
end

-- Side-step for the rest of the strafe. Our focus target keeps us facing them, so left and right circle them.
function ChaseTargetsTask:Strafe(strafe: { Direction: string, TimeLeft: number }, deltaTime: number)
	strafe.TimeLeft -= deltaTime
	if strafe.TimeLeft <= 0 or not self.Movement:CanBeEvasive() then
		self:StopMoving()
		return
	end

	self:SetSprinting(false)
	self.moveState = STRAFING
	self.Movement:Move(strafe.Direction)
end

-- Always face whoever we're chasing, so walking forward is walking toward them
-- and walking backward keeps them in view
function ChaseTargetsTask:SetFocusTarget(target: TypeTargetting.TargettingContext?)
	local previous = self.FocusTarget
	self.FocusTarget = target

	local sameCharacter = (if previous then previous.Character else nil) == (if target then target.Character else nil)
	if sameCharacter then
		-- already facing them (or still nothing), only the context was refreshed
		return
	end

	if target then
		self.Movement:SetFocusTarget(target.Character)
		-- a new target deserves an immediate decision, not whatever is left of the interval
		self.sinceChase = CHASE_INTERVAL
	else
		self.Movement:RemoveFocusTarget()
		self:StopMoving()
	end
end

-- Walk toward / away from the target so we end up in [ideal - deviation, ideal]
-- Between those we stand still, which stops us jittering back and forth around one exact distance
-- Leaving the range cancels any strafe, since we're back to walking toward/away from them
function ChaseTargetsTask:Chase(target: TypeTargetting.TargettingContext, deltaTime: number)
	local ideal = self:GetIdealDistance()
	local distance = self.CharacterAPI:GetDistanceTo(target.Character)
	if not ideal or not distance then
		self.inRange = false
		if self.moveState ~= STANDING then
			self:StopMoving()
		end
		return
	end

	local tooCloseLimit = ideal - self:GetTooCloseDeviation()
	self.inRange = distance <= ideal and distance >= tooCloseLimit
	if not self.inRange then
		self.strafe = nil
	end

	if distance > ideal then
		-- sprint while we're far from where we want to be, walk once we're close to it
		local sprintDeviation = self:GetSprintDeviation()
		self:SetSprinting(sprintDeviation ~= nil and distance - ideal > sprintDeviation)
		self.moveState = ADVANCING
		self.Movement:MoveForward()
	elseif distance < tooCloseLimit then
		self:SetSprinting(false)
		self.moveState = RETREATING
		self.Movement:MoveBackward()
	elseif self.strafe then
		self:Strafe(self.strafe, deltaTime)
	elseif self.moveState ~= STANDING then
		self:StopMoving()
	end
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
		self.Events:Subscribe(ThoughtEvents.ReactionUpdate, function()
			self:OnReactionUpdate()
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
			self.Movement:RemoveFocusTarget()
			self:StopMoving()
		end
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

	local elapsed = self.sinceChase
	self.sinceChase = 0

	self:SyncFocusTarget()

	local target = self.FocusTarget
	if target then
		self:Chase(target, elapsed)
	end
end

return ChaseTargetsTask
