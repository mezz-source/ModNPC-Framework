local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local TargettingRanges = TypeTargetting.Ranges
local AttackTypes = TypeAttack.AttackTypes

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies

-- The attack we make for each targetting range: close up is melee, from a distance is ranged
local ATTACK_TYPES = {
	[TargettingRanges.Close] = AttackTypes.Melee,
	[TargettingRanges.Long] = AttackTypes.Ranged,
}
local ATTACK_FUNCTIONS = {
	[TargettingRanges.Close] = FunctionEnum.MeleeAttackCurrentTarget,
	[TargettingRanges.Long] = FunctionEnum.RangeAttackCurrentTarget,
}

-- Decides when to attack. It runs for as long as it is started and holds no resources: the attacks it calls are tasks
-- of their own and claim the limbs they use themselves, so they never stop this one.
--
-- It always has an attack in mind (the desired attack, picked for our targetting range) while it has someone to fight.
-- ChaseTargets and Engage hold the distance that attack is made from (the attack's standoff, see GetHoldDistance), and on
-- each reaction tick, once the focus target is within that standoff, the attack is made through the melee or ranged attack
-- function. The decision to attack is only ever made here, whatever the movement tasks are doing: an attack can be made
-- while still closing in, as soon as the target is near enough. A target that is already near enough is attacked on the
-- very tick the attack is picked. A new attack is picked straight after each one, so there is always a distance to hold.
-- Deciding only on reaction ticks is what makes a character's attack timing depend on its reaction speed.
local AttackTargetsTask = {}
AttackTargetsTask.__index = AttackTargetsTask
setmetatable(AttackTargetsTask, Task)

function AttackTargetsTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Attack,
		Resources = {},
		Dependencies = {
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

	local self = setmetatable(task, AttackTargetsTask)
	self.Configuration = base.Configuration
	self.Distance = base.Distance
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler

	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
	-- The target we are fighting, if any
	self.FocusTarget = nil :: TypeTargetting.TargettingContext?

	return self
end

-- we do this in case this changes later
function AttackTargetsTask:UpdateTargettingRange()
	self.targettingRange = self.Configuration:GetThoughtSetting("TargettingRange") :: TypeTargetting.TargettingRange
end

-- A new target is not acted on straight away, we notice them on our next reaction tick
function AttackTargetsTask:SetFocusTarget(target: TypeTargetting.TargettingContext?)
	self.FocusTarget = target
end

-- The focus events are how we normally hear about a new target. This reads the same state straight from the
-- targetting task, so a missed event (or a task started late) can't leave us fighting someone out of date.
function AttackTargetsTask:SyncFocusTarget()
	local targettingTask = self.Scheduler:GetTask(CategoryEnum.Targetting) :: any
	if targettingTask then
		self:SetFocusTarget(targettingTask.FocusTarget)
	end
end

-- The type of attack we make from where we stand: melee up close, ranged from a distance
function AttackTargetsTask:GetAttackType(): TypeAttack.AttackType?
	return ATTACK_TYPES[self.targettingRange]
end

-- The attack we have in mind, picked now if there is none yet (or the one we had is gone, like a weapon unequipped).
-- Nil when the character has no attack of the type to make.
function AttackTargetsTask:PickDesiredAttack(): TypeAttack.AttackData?
	local desired = self.Functions:CallFunction(FunctionEnum.GetDesiredAttack)
	if desired then
		return desired
	end

	local attackType = self:GetAttackType()
	if not attackType then
		return nil
	end

	return (self.Functions:CallFunction(FunctionEnum.PickDesiredAttack, attackType))
end

-- Calls the attack function for our targetting range, which crosses the function boundary so mods can hook it
function AttackTargetsTask:Attack(target: TypeTargetting.TargettingContext)
	local attackFunction = ATTACK_FUNCTIONS[self.targettingRange]
	if not attackFunction then
		return
	end

	self.Functions:CallFunction(attackFunction)

	-- Whatever happened, the next attack to get in position for is decided now, not on the next tick
	local attackType = self:GetAttackType()
	if attackType then
		self.Functions:CallFunction(FunctionEnum.PickDesiredAttack, attackType)
	end
end

-- Where the desired attack is made from: its standoff, inside the range the hit is checked against so the target has room
-- to step back during the windup. Asked of the functions so it matches the distance the movement tasks hold.
function AttackTargetsTask:GetLaunchDistance(attack: TypeAttack.AttackData): number
	local standoff = self.Functions:CallFunction(FunctionEnum.GetAttackStandoff, attack)
	return if type(standoff) == "number" and standoff == standoff then standoff else attack.DesiredRange
end

-- One decision per reaction tick. The attack is made as soon as the target is within the desired attack's standoff; until
-- then ChaseTargets is walking us there. Nothing is started while the last attack is still swinging.
function AttackTargetsTask:OnReactionUpdate()
	if not self:IsRunning() then
		return
	end

	self:SyncFocusTarget()

	local target = self.FocusTarget
	if not target then
		return
	end

	-- The attack in mind is picked even when we can't attack right now, so it is ready to make. While we can't, the movement
	-- tasks don't hold its standoff, they back the character off (see GetHoldDistance).
	local attack = self:PickDesiredAttack()
	if not attack or not self.Functions:CallFunction(FunctionEnum.CanAttack) then
		return
	end

	-- Resting between exchanges: the character keeps out of reach and defends itself (guarding, circling) until it is done,
	-- how long being up to its Tempo and Commitment (see Attacks). The decision to attack is still only made here.
	if not self.Functions:CallFunction(FunctionEnum.IsReadyToAttack) then
		return
	end

	-- Not enough stamina for the attack in mind: it is kept (the stamina will come back) and made once it can be paid for
	if not self.Functions:CallFunction(FunctionEnum.CanAffordAttack, attack) then
		return
	end

	if self.Distance:IsWithin(target.Character, self:GetLaunchDistance(attack)) then
		self:Attack(target)
	end
end

function AttackTargetsTask:Start()
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

		self.FocusTarget = nil
		-- the attack in mind is ours, the movement tasks go back to holding the usual engage distance without it
		self.Functions:CallFunction(FunctionEnum.ClearDesiredAttack)
	end)

	-- We may have started after targetting already picked someone, so catch up instead of waiting for a change
	self:SyncFocusTarget()

	return true
end

return AttackTargetsTask
