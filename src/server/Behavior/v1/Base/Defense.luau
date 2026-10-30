local ServerScriptService = game:GetService("ServerScriptService")
local TypeBlock = require(ServerScriptService.ModNPCServer.Types.v1.TypeBlock)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeDefense = require(ServerScriptService.ModNPCServer.Types.v1.TypeDefense)
local TypeDisposition = require(ServerScriptService.ModNPCServer.Types.v1.TypeDisposition)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeSkills = require(ServerScriptService.ModNPCServer.Types.v1.TypeSkills)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

-- How the character meets the hits it sees coming. An attacker warns its target of each hit with an IncomingAttack
-- stimulant that lasts until the hit lands; on the reaction tick that finds it queued we consume it and decide, once per hit:
--   a guard that is already up keeps taking hits as long as it can pay for one this heavy (Guarded)
--   otherwise, with enough time left to get a dodge off (DodgeReactionTime) and an Agility roll made, we dodge. The dodge is
--   timed to go off just before the hit (DODGE_LEAD), so its active span covers the moment it lands.
--   failing that (too late, the roll failed, can't pay), a guard is raised at the last moment if it still can be (Block). That
--   is an effort, not a sure thing: below BlockSureTime it is likelier to be too slow the less time is left, and a guarded
--   character (the Guard axis) gets its arms up more readily. It is held until the hit is over and a moment after
--   (GUARD_HOLD), then put down again unless Engage took it over.
-- A dodge usually takes the character out of the hit's reach, so the attacker finds it out of range and the hit never gets
-- to Damage. Such a hit is announced as dodged here (DefenseSucceeded), as Damage would have.
-- From the decision until it is carried out the character is Reacting (DefenseState), and doesn't start an attack meanwhile.
-- How fast the character reacts is its thought process' reaction ticks: a slow one sees the hit later, with less time left.
-- The decision itself is ReactToIncomingAttack, a function, so a mod can replace how a character defends itself.
local Defense = {}
Defense.__index = Defense

type StimulantEvent = TypeStimulant.StimulantEvent

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Reactions = TypeDefense.Reactions
local Settings = TypeDefense.Settings
local Skills = TypeSkills.Skills
local MovementEnum = TypeMovement.MovementEnum
local CombatEvents = TypeCharacterEvents.Names.Combat
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local StimulantEvents = TypeCharacterEvents.Names.Stimulant
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local INCOMING_ATTACK = TypeStimulant.Names.IncomingAttack
local DEFENSE_STATE_KEY = TypeState.Keys.DefenseState
local DefenseStateEnum = TypeState.DefenseStateEnum

-- The skills a dodge is rolled against
local DODGE_SKILLS: { TypeSkills.Skill } = { Skills.Agility }

-- What a setting of Config/Defense is when the folder doesn't have it (see TypeDefense.Settings)
local SETTING_DEFAULTS: { [string]: number } = table.freeze({
	[Settings.DodgeReactionTime] = 0.15,
	[Settings.BlockReactionTime] = 0.05,
	[Settings.BlockSureTime] = 0.3,
	[Settings.DodgeBonus] = 0,
})

-- Seconds before the hit the dodge goes off: inside the dodge's active span (0.3s, see Movement) with room either side, so
-- a hit landing a little early or late is still inside it
local DODGE_LEAD = 0.12
-- Seconds a last moment guard stays up once the hit it was raised for is over, so a combo's next hit (warned as the previous
-- one lands) still finds it up
local GUARD_HOLD = 0.35
-- Who holds a Block task we raised (see BlockTask.Holder). Engage writes its own name over it when it takes the guard over.
local HOLDER = "Defense"
-- Dodges that go off to the side, as opposed to back, at no Aggression and at full Aggression. A wary character gets out of
-- reach, an aggressive one stays in it to answer.
local SIDE_DODGE_WARY = 0.3
local SIDE_DODGE_AGGRESSIVE = 0.9
local SIDE_DIRECTIONS = { MovementEnum.Left, MovementEnum.Right }
-- Rolls are scaled to 0-100 (see Skills), and a DodgeBonus is a share of that
local ROLL_SCALE = TypeSkills.MaxLevel
-- How much the Guard axis moves the odds of a last moment guard: none at 0.5, x(1 - this) at 0 and x(1 + this) at 1
local GUARD_ODDS_SPREAD = 0.5
-- Seconds past a dodged hit's time we wait to hear from Damage how it went, before taking it that the hit found us out of
-- reach. (A hit that resolves isn't retracted to us: its warning has run out by then, see the Stimulants API.)
local DODGE_OUTCOME_GRACE = 0.2

function Defense.new(Base: any, character: Model)
	local self = setmetatable({}, Defense)
	self.Base = Base
	self.Character = character
	self.Configuration = Base.Configuration
	self.State = Base.State

	Base.State:Register(DEFENSE_STATE_KEY, DefenseStateEnum)

	-- Stimulant id -> os.clock time until which we are dealing with that hit. Reacting while it has anything left.
	self.awaiting = {} :: { [number]: number }
	-- Stimulant id -> the thread that dodges it
	self.pendingDodges = {} :: { [number]: thread }
	-- Stimulant id -> the hits we dodged, until they are over: who from, when it was due, and whether Damage told of the
	-- outcome itself
	self.dodged = {} :: { [number]: { Attacker: Model?, HitAt: number, Resolved: boolean } }
	-- The guard we raised, until when it is held up, and which hits it was raised or kept up for
	self.guard = nil :: { Task: any, Until: number, Ids: { [number]: boolean } }?

	self.Subscriptions = {}

	return self
end

-- Runs once the functions are registered, since it hooks one (DropStimulant, to hear of retracted hits)
function Defense:Init()
	local events = self.Base.Events

	table.insert(
		self.Subscriptions,
		events:Subscribe(StimulantEvents.Pending, function(pending)
			self:_onPending(pending)
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(ThoughtEvents.ReactionUpdate, function()
			self:_refresh()
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(HumanoidEvents.Died, function()
			self:_clear()
		end)
	)

	-- What Damage made of a hit we dodged, so a hit it did hear of is not announced twice
	for _, outcome in { CombatEvents.DefenseSucceeded, CombatEvents.DamageTaken } do
		table.insert(
			self.Subscriptions,
			events:Subscribe(outcome, function(payload)
				self:_onOutcome(payload)
			end)
		)
	end

	-- A hit is retracted when its attack is cut short before it lands (see the Attack task). Last, so it is heard whatever
	-- the queue did with it: by now we have consumed it and the queue itself no longer knows it.
	table.insert(
		self.Subscriptions,
		self.Base.Functions:SubscribeFunction(FunctionEnum.DropStimulant, function(id)
			self:_onRetracted(id)
		end, "Last")
	)
end

function Defense:_getSetting(settingName: string): number
	local value = self.Configuration:Get({ TypeDefense.Folder, settingName })

	return if type(value) == "number" and value == value then value else SETTING_DEFAULTS[settingName]
end

-- Every hit we were warned of and have not decided on yet is decided on now, most urgent first
function Defense:_onPending(pending: { StimulantEvent })
	if type(pending) ~= "table" then
		return
	end

	local functions = self.Base.Functions
	for _, stimulant in pending do
		if stimulant.Name ~= INCOMING_ATTACK then
			continue
		end

		-- nil when it was retracted or ran out since the list was made, and then there is nothing to meet
		local taken: StimulantEvent? = functions:CallFunction(FunctionEnum.ConsumeStimulant, stimulant.Id)
		if taken then
			functions:CallFunction(FunctionEnum.ReactToIncomingAttack, taken)
		end
	end
end

-- Decides how to meet a hit we were warned of (an IncomingAttack stimulant) and sets it in motion. Returns the reaction and,
-- when it isn't the first choice, why. Announced as Combat.DefenseReaction.
function Defense:ReactToIncomingAttack(stimulant: StimulantEvent): (TypeDefense.Reaction, string?)
	local timeLeft = stimulant.ExpiresAt - os.clock()
	local reaction, reason = self:_decide(stimulant, timeLeft)
	self:_announce(stimulant, reaction, timeLeft, reason)
	self:_refresh()

	return reaction, reason
end

function Defense:_announce(stimulant: StimulantEvent, reaction: TypeDefense.Reaction, timeLeft: number, reason: string?)
	self.Base.Events:Dispatch(CombatEvents.DefenseReaction, {
		Attacker = stimulant.Source,
		Reaction = reaction,
		TimeLeft = timeLeft,
		Reason = reason,
	} :: TypeDefense.DefenseReaction)
end

function Defense:_decide(stimulant: StimulantEvent, timeLeft: number): (TypeDefense.Reaction, string?)
	if timeLeft <= 0 then
		return Reactions.None, "Too late"
	end

	local functions = self.Base.Functions
	local blockCost = self:_getBlockCost(stimulant)

	-- A guard that is up takes the hit for its price, which is less than a dodge's, and a dodge would leave it behind
	if functions:CallFunction(FunctionEnum.IsBlocking) and functions:CallFunction(FunctionEnum.CanAffordStamina, blockCost) then
		self:_keepGuard(stimulant)
		return Reactions.Guarded
	end

	local dodgeReason = self:_tryDodge(stimulant, timeLeft)
	if not dodgeReason then
		return Reactions.Dodge
	end

	local blockReason = self:_raiseGuard(stimulant, timeLeft)
	if not blockReason then
		return Reactions.Block, dodgeReason
	end

	return Reactions.None, dodgeReason .. ", " .. blockReason
end

-- What holding a guard against the hit costs, by its weight. The weight is the one the guard will be charged by: the
-- damage the attacker says the hit comes with (see Damage:GetHitCategory).
function Defense:_getBlockCost(stimulant: StimulantEvent): TypeStamina.Cost
	local data = stimulant.Data
	local damage = if type(data) == "table" and type(data.BaseDamage) == "number" then data.BaseDamage else math.huge
	local category = self.Base.Functions:CallFunction(FunctionEnum.GetHitCategory, damage)

	return TypeBlock.HitCosts[category] or TypeBlock.HitCosts.Heavy
end

-- Rolls the dodge against our Agility, with the character's DodgeBonus on top. Exhaustion is already in the roll (see Skills).
function Defense:_rollDodge(): boolean
	local result = self.Base.Functions:CallFunction(FunctionEnum.RollSkills, DODGE_SKILLS)
	if type(result) ~= "table" or type(result.Roll) ~= "number" or type(result.Target) ~= "number" then
		return false
	end

	return result.Roll <= result.Target + self:_getSetting(Settings.DodgeBonus) * ROLL_SCALE
end

-- Commits to dodging the hit, if there is the time, the ability and the stamina for it and the roll is made. Returns why
-- not, or nil when the dodge is on its way.
function Defense:_tryDodge(stimulant: StimulantEvent, timeLeft: number): string?
	if timeLeft < self:_getSetting(Settings.DodgeReactionTime) then
		return "Too late to dodge"
	end

	local functions = self.Base.Functions
	local canDodge, reason = functions:CallFunction(FunctionEnum.CanDodge)
	if not canDodge then
		return reason or "Cannot dodge"
	end
	-- a dodge asks for rested stamina (see Movement:Dodge)
	if not functions:CallFunction(FunctionEnum.CanAffordStamina, TypeStamina.Costs.Dodge, true) then
		return "Cannot afford to dodge"
	end

	if not self:_rollDodge() then
		return "Dodge roll failed"
	end

	self:_scheduleDodge(stimulant, timeLeft)

	return nil
end

-- Which way to dodge: to the side, staying in reach to answer, or back out of it. The more aggressive we feel the more
-- often it is the side.
function Defense:_pickDodgeDirection(): string
	local aggression: any = self.Base.Functions:CallFunction(FunctionEnum.GetDisposition, TypeDisposition.Axes.Aggression)
	local leaning: number = if type(aggression) == "number" then math.clamp(aggression, 0, 1) else 0.5
	local side = SIDE_DODGE_WARY + (SIDE_DODGE_AGGRESSIVE - SIDE_DODGE_WARY) * leaning

	if math.random() < side then
		return SIDE_DIRECTIONS[math.random(#SIDE_DIRECTIONS)]
	end

	return MovementEnum.Backward
end

-- The dodge goes off DODGE_LEAD before the hit, or straight away when there is less left than that. A dodge refused at that
-- moment (staggered meanwhile, out of stamina) falls back to a last moment guard.
function Defense:_scheduleDodge(stimulant: StimulantEvent, timeLeft: number)
	local id = stimulant.Id
	local delay = math.max(timeLeft - DODGE_LEAD, 0)
	local direction = self:_pickDodgeDirection()

	self.awaiting[id] = os.clock() + delay
	self.pendingDodges[id] = task.delay(delay, function()
		self.pendingDodges[id] = nil
		self.awaiting[id] = nil
		if not self.Base or not self.Base:IsAlive() then
			return
		end

		local dodged, reason = self.Base.Functions:CallFunction(FunctionEnum.Dodge, direction)
		if dodged then
			self.dodged[id] = { Attacker = stimulant.Source, HitAt = stimulant.ExpiresAt, Resolved = false }
		else
			local left = stimulant.ExpiresAt - os.clock()
			local blockReason = self:_raiseGuard(stimulant, left)
			local why = "Dodge refused: " .. tostring(reason)
			if blockReason then
				self:_announce(stimulant, Reactions.None, left, why .. ", " .. blockReason)
			else
				self:_announce(stimulant, Reactions.Block, left, why)
			end
		end

		self:_refresh()
	end)
end

-- Raises a guard for the hit at the last moment, if it can still go up in time and we can block at all. Returns why not, or
-- nil when it is up.
function Defense:_raiseGuard(stimulant: StimulantEvent, timeLeft: number): string?
	if timeLeft < self:_getSetting(Settings.BlockReactionTime) then
		return "Too late to block"
	end

	local functions = self.Base.Functions
	local canBlock, reason = functions:CallFunction(FunctionEnum.CanBlock)
	if not canBlock then
		return reason or "Cannot block"
	end
	-- a guard that can't pay for even the lightest hit would only break
	if not functions:CallFunction(FunctionEnum.CanAffordStamina, TypeStamina.Costs.BlockLight) then
		return "Cannot afford to block"
	end
	if math.random() >= self:_getGuardOdds(timeLeft) then
		return "Guard too slow"
	end

	local block, createError = self.Base.CharacterTasks.Block.new()
	if not block then
		return "Could not create block: " .. tostring(createError)
	end
	local started, startError = self.Base.Scheduler:Start(block)
	if not started then
		return "Could not start block: " .. tostring(startError)
	end

	block.Holder = HOLDER
	self.guard = { Task = block, Until = stimulant.ExpiresAt + GUARD_HOLD, Ids = { [stimulant.Id] = true } }
	self.awaiting[stimulant.Id] = stimulant.ExpiresAt + GUARD_HOLD

	return nil
end

-- The odds (0-1) a last moment guard gets up in time: sure from BlockSureTime before the hit, down to none at the
-- BlockReactionTime, and leaned by how guarded we feel
function Defense:_getGuardOdds(timeLeft: number): number
	local soonest = self:_getSetting(Settings.BlockReactionTime)
	local sure = math.max(self:_getSetting(Settings.BlockSureTime), soonest + 0.01)
	local odds = math.clamp((timeLeft - soonest) / (sure - soonest), 0, 1)

	local guard: any = self.Base.Functions:CallFunction(FunctionEnum.GetDisposition, TypeDisposition.Axes.Guard)
	local leaning: number = if type(guard) == "number" then math.clamp(guard, 0, 1) else 0.5

	return math.clamp(odds * (1 + (leaning - 0.5) * 2 * GUARD_ODDS_SPREAD), 0, 1)
end

-- Damage heard of a hit from someone whose hit we dodged: it was a dodge that hit didn't get out of, or one it did
function Defense:_onOutcome(payload: any)
	local attacker = if type(payload) == "table" then payload.Attacker else nil
	for _, entry in self.dodged do
		if entry.Attacker == attacker then
			entry.Resolved = true
		end
	end
end

-- A guard that is up takes this hit too. One we raised is held up until it is over; one Engage holds is Engage's to put
-- down, we only don't start an attack meanwhile.
function Defense:_keepGuard(stimulant: StimulantEvent)
	local guard = self.guard
	if guard and guard.Task:IsRunning() and guard.Task.Holder == HOLDER then
		guard.Until = math.max(guard.Until, stimulant.ExpiresAt + GUARD_HOLD)
		guard.Ids[stimulant.Id] = true
	end

	self.awaiting[stimulant.Id] = stimulant.ExpiresAt + GUARD_HOLD
end

-- The hit won't come: its attack was cut short. A dodge still waiting for it is called off, a dodge already made for it
-- avoided nothing, and a guard raised for it stays up only a moment longer.
function Defense:_onRetracted(id: any)
	if type(id) ~= "number" then
		return
	end

	local thread = self.pendingDodges[id]
	if thread then
		self.pendingDodges[id] = nil
		task.cancel(thread)
	end
	self.awaiting[id] = nil

	self.dodged[id] = nil

	local guard = self.guard
	if guard and guard.Ids[id] then
		guard.Ids[id] = nil
		if next(guard.Ids) == nil then
			guard.Until = math.min(guard.Until, os.clock() + GUARD_HOLD)
		end
	end

	self:_refresh()
end

-- Lets go of what is over: hits that are past, and a guard of ours that is no longer needed. Then the DefenseState follows.
function Defense:_refresh()
	if not self.Base then
		return
	end

	local now = os.clock()

	-- a dodged hit whose time is past without Damage hearing of it found us out of reach: a dodge all the same
	for id, dodged in self.dodged do
		if now >= dodged.HitAt + DODGE_OUTCOME_GRACE then
			self.dodged[id] = nil
			if not dodged.Resolved and self.Base:IsAlive() then
				self.Base.Events:Dispatch(CombatEvents.DefenseSucceeded, {
					Attacker = dodged.Attacker,
					RecieveType = TypeDamage.RecieveTypes.Dodged,
				} :: TypeCharacterEvents.DefenseSucceeded)
			end
		end
	end

	for id, untilTime in self.awaiting do
		if untilTime <= now and not self.pendingDodges[id] then
			self.awaiting[id] = nil
		end
	end

	local guard = self.guard
	if guard then
		if not guard.Task:IsRunning() or guard.Task.Holder ~= HOLDER then
			-- it ended without us (an attack, a break) or Engage holds it now
			self.guard = nil
		elseif guard.Until <= now then
			self.guard = nil
			guard.Task:Stop("Defense lowered the guard")
		end
	end

	local reacting = next(self.awaiting) ~= nil
	self.State:Set(DEFENSE_STATE_KEY, if reacting then DefenseStateEnum.Reacting else DefenseStateEnum.None)
end

-- Whether a reaction to a hit is under way (a dodge waiting for it, a guard held for it)
function Defense:IsReacting(): boolean
	return self.State:Is(DEFENSE_STATE_KEY, DefenseStateEnum.Reacting)
end

function Defense:_clear()
	for _, thread in self.pendingDodges do
		task.cancel(thread)
	end
	self.pendingDodges = {}
	self.dodged = {}
	self.awaiting = {}
	self.guard = nil
	if self.State then
		self.State:Set(DEFENSE_STATE_KEY, DefenseStateEnum.None)
	end
end

function Defense:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end
	self.Subscriptions = {}
	self:_clear()
	self.Configuration = nil
	self.State = nil
	self.Base = nil
end

return Defense
