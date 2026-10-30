local ServerScriptService = game:GetService("ServerScriptService")
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDisposition = require(ServerScriptService.ModNPCServer.Types.v1.TypeDisposition)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local Disposition = {}
Disposition.__index = Disposition

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Axes = TypeDisposition.Axes
local Factors = TypeDisposition.Factors
local Settings = TypeDisposition.Settings
local CombatEvents = TypeCharacterEvents.Names.Combat
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local StimulantEvents = TypeCharacterEvents.Names.Stimulant
local StimulantNames = TypeStimulant.Names
local EXHAUSTION_STATE_KEY = TypeState.Keys.ExhaustionState
local ExhaustionStateEnum = TypeState.ExhaustionStateEnum

-- Where each axis rests before any factor leans it, and what it rests at when the character's configuration doesn't say
local AXIS_BASELINES: { [string]: { Path: { string }, Default: number } } = table.freeze({
	[Axes.Aggression] = { Path = { "ThoughtProcess", "AggressionScale" }, Default = 0.5 },
	[Axes.Evasiveness] = { Path = { "ThoughtProcess", "Evasiveness" }, Default = 0.5 },
	[Axes.Guard] = { Path = { TypeDisposition.Folder, TypeDisposition.BaselineFolder, "Guard" }, Default = 0.3 },
	[Axes.Tempo] = { Path = { TypeDisposition.Folder, TypeDisposition.BaselineFolder, "Tempo" }, Default = 0.5 },
	[Axes.Commitment] = { Path = { TypeDisposition.Folder, TypeDisposition.BaselineFolder, "Commitment" }, Default = 0.5 },
})

-- How strongly each factor leans each axis at full strength, when the character's Config/Disposition doesn't say.
-- Positive pushes the axis up, negative down. Importance multiplies all of them.
local DEFAULT_EFFECTS: { [string]: { [string]: number } } = table.freeze({
	-- Hurt characters pull back and guard, and favor attacks that leave them free to move
	[Factors.Injury] = {
		[Axes.Aggression] = -0.8,
		[Axes.Evasiveness] = 0.6,
		[Axes.Guard] = 0.7,
		[Axes.Tempo] = 0.3,
		[Axes.Commitment] = -0.5,
	},
	-- Attacks that don't work make a character push harder, and try things that are easier to take back
	[Factors.FailedAttacks] = {
		[Axes.Aggression] = 0.5,
		[Axes.Evasiveness] = -0.4,
		[Axes.Tempo] = 0.3,
		[Axes.Commitment] = -0.5,
	},
	-- Being battered makes a character guard itself, whatever its health still is
	[Factors.Pressure] = {
		[Axes.Aggression] = -0.4,
		[Axes.Evasiveness] = 0.3,
		[Axes.Guard] = 0.8,
	},
	[Factors.Momentum] = {
		[Axes.Aggression] = 0.6,
		[Axes.Evasiveness] = -0.2,
		[Axes.Tempo] = 0.4,
		[Axes.Commitment] = 0.5,
	},
	-- Nothing happening is what keeps a character from standing around: it gets bored and goes in
	[Factors.Stalemate] = {
		[Axes.Aggression] = 0.7,
		[Axes.Guard] = -0.3,
		[Axes.Tempo] = 0.3,
	},
	[Factors.Opening] = {
		[Axes.Aggression] = 0.8,
		[Axes.Evasiveness] = -0.3,
		[Axes.Guard] = -0.5,
		[Axes.Tempo] = 0.6,
	},
	-- A character running out of breath slows down, covers itself and picks fights it can afford
	[Factors.Stamina] = {
		[Axes.Aggression] = -0.3,
		[Axes.Guard] = 0.6,
		[Axes.Tempo] = -0.7,
		[Axes.Commitment] = -0.3,
	},
	-- A hurt target is worth going in for: get close, keep at it, and don't hold back
	[Factors.TargetWeak] = {
		[Axes.Aggression] = 0.5,
		[Axes.Evasiveness] = -0.2,
		[Axes.Guard] = -0.4,
		[Axes.Tempo] = 0.5,
		[Axes.Commitment] = 0.4,
	},
	-- An exhausted character can do very little, so it keeps away, circles and takes its time. As strong as an effect gets;
	-- the Importance in the configuration makes it stronger still. It guards only a little more: an exhausted guard still
	-- pays for every hit and lets part of it through, so a character that held one up would never get its breath back.
	[Factors.Exhaustion] = {
		[Axes.Aggression] = -1,
		[Axes.Evasiveness] = 0.5,
		[Axes.Guard] = 0.4,
		[Axes.Tempo] = -1,
		[Axes.Commitment] = -0.8,
	},
	-- A hit coming at us makes a character wary for a moment: it covers itself and keeps moving, and thinks twice about
	-- locking itself into an attack
	[Factors.Threatened] = {
		[Axes.Aggression] = -0.2,
		[Axes.Evasiveness] = 0.3,
		[Axes.Guard] = 0.5,
		[Axes.Commitment] = -0.2,
	},
	-- A broken guard is the best opening there is: go in now, fast and all in, with no thought for defending
	[Factors.TargetOpen] = {
		[Axes.Aggression] = 0.8,
		[Axes.Evasiveness] = -0.3,
		[Axes.Guard] = -0.6,
		[Axes.Tempo] = 0.8,
		[Axes.Commitment] = 0.6,
	},
	-- A target that just ran out of breath can barely hit back: press it while it lasts
	[Factors.TargetTired] = {
		[Axes.Aggression] = 0.6,
		[Axes.Guard] = -0.3,
		[Axes.Tempo] = 0.5,
		[Axes.Commitment] = 0.4,
	},
	-- Someone rushing in: brace for them and be ready to get out of the way, rather than commit to anything
	[Factors.Charged] = {
		[Axes.Evasiveness] = 0.4,
		[Axes.Guard] = 0.6,
		[Axes.Commitment] = -0.3,
	},
})

local DEFAULT_IMPORTANCE = 1

-- Event factors are counts that fade away: each failure or landed attack adds one, and the count halves every half life.
-- Saturation is the count at which the factor is at full strength.
local FAILED_HALF_LIFE = 10
local FAILED_SATURATION = 3
local MOMENTUM_HALF_LIFE = 10
local MOMENTUM_SATURATION = 3
-- Pressure counts damage as a share of max health. It fades fast, as it is about the last few seconds.
local PRESSURE_HALF_LIFE = 4
local PRESSURE_SATURATION = 0.25
-- Stalemate starts building once the characters have been in each other's face this long without anything happening,
-- and is at full strength a ramp later
local STALEMATE_GRACE = 4
local STALEMATE_RAMP = 8
-- Seconds the other side stays open after a defense that worked
local OPENING_DURATION = 2.5
-- How weak a target counts as while it is staggered (it can't defend at all: as weak as one nearly down) or exhausted (it
-- is slower and its guard lets damage through, but it still fights back; characters are exhausted for a good part of a
-- long fight, so this is a lasting lean, and the moment it tires is the TargetTired stimulant's burst). The target counts
-- as weak by whichever is most of its health and these.
local EXHAUSTED_TARGET_WEAKNESS = 0.6
local STAGGERED_TARGET_WEAKNESS = 1

-- The stimulant factors: which stimulant feeds each, the seconds it lasts once perceived (it fades from its strength to
-- nothing over them), and how strong (0-1) the stimulant makes it. A stimulant only counts once, however many ticks it is
-- still queued for; the same thing perceived again while the pulse lasts restarts it if it is at least as strong.
local CHARGE_NEAR = 10
local CHARGE_FAR = 40
local CHARGE_MIN_STRENGTH = 0.3
local THREAT_BY_WEIGHT: { [string]: number } = table.freeze({
	[TypeAttack.AttackWeights.Light] = 0.6,
	[TypeAttack.AttackWeights.Medium] = 0.8,
	[TypeAttack.AttackWeights.Heavy] = 1,
})
-- How low the stamina efficiency of an exhausted character goes (see Stamina), which is a fully tired target
local MIN_TARGET_EFFICIENCY = 0.5

local function dataNumber(stimulant: any, field: string): number?
	local data = stimulant.Data
	local value = if type(data) == "table" then data[field] else nil

	return if type(value) == "number" and value == value then value else nil
end

local STIMULANT_FACTORS: { [string]: { Factor: string, Hold: number, Strength: (stimulant: any) -> number } } =
	table.freeze({
		-- the heavier the hit, the warier
		[StimulantNames.IncomingAttack] = {
			Factor = Factors.Threatened,
			Hold = 1.5,
			Strength = function(stimulant)
				local data = stimulant.Data
				local weight = if type(data) == "table" then data.AttackWeight else nil
				return THREAT_BY_WEIGHT[weight] or THREAT_BY_WEIGHT[TypeAttack.AttackWeights.Medium]
			end,
		},
		[StimulantNames.BlockBroken] = {
			Factor = Factors.TargetOpen,
			Hold = 2,
			Strength = function()
				return 1
			end,
		},
		-- as tired as its efficiency fell: all the way down is full strength
		[StimulantNames.Exhausted] = {
			Factor = Factors.TargetTired,
			Hold = 3,
			Strength = function(stimulant)
				local efficiency = dataNumber(stimulant, "Efficiency")
				if not efficiency then
					return 1
				end
				return math.clamp((1 - efficiency) / (1 - MIN_TARGET_EFFICIENCY), 0, 1)
			end,
		},
		-- a sprint from close by is more of a threat than one from across the field
		[StimulantNames.SprintingTowards] = {
			Factor = Factors.Charged,
			Hold = 1.5,
			Strength = function(stimulant)
				local distance = dataNumber(stimulant, "Distance") or CHARGE_FAR
				local near = 1 - (distance - CHARGE_NEAR) / (CHARGE_FAR - CHARGE_NEAR)
				return math.clamp(near, CHARGE_MIN_STRENGTH, 1)
			end,
		},
	})

-- Axes ease toward where the factors want them instead of jumping, so the character's behavior shifts instead of flicking
local AXIS_SMOOTH_TIME = 0.75
-- A reaction tick that was held up (a stall) shouldn't decay or ease everything in one go
local MAX_STEP = 1

-- How far Aggression moves the distance we hold from the target, as a share of it: none at 0.5, this much further out at 0
-- and this much closer at 1. A character at full aggression holds 40% less distance than its configuration says, one at
-- no aggression 40% more.
local ENGAGE_DISTANCE_SPREAD = 0.8
-- Studs the engage distance keeps over the too close diff, so the band we hold never collapses
local MIN_ENGAGE_GAP = 2
-- The share of an attack's DesiredRange we stand at to make it, so the target can step back during the windup and the hit
-- still lands (a hit is checked against the full range as it lands). A wary character makes its attacks from near the edge
-- of their reach, an aggressive one presses in closer.
local ATTACK_STANDOFF_WARY = 0.9
local ATTACK_STANDOFF_AGGRESSIVE = 0.75
-- Studs the standoff never goes under (an attack with a shorter range keeps its range): two characters can't stand closer
-- than their bodies allow
local MIN_ATTACK_STANDOFF = 2.5
-- Every this many studs an attack asks us to walk past where we would settle on our own halves its odds of being the one
-- picked (see GetAttackFit)
local ATTACK_FIT_HALF_DISTANCE = 4
-- How much a mismatch between Commitment and how committing an attack is (see GetAttackFit) takes off its odds: none when
-- they match, this share of them at the furthest apart
local COMMITMENT_FIT_STRENGTH = 0.75
-- Seconds of rest out of reach after an exchange, at the slowest and the fastest Tempo. A guarded character rests longer
-- (REST_GUARD_SPREAD of it either way), and every rest varies by REST_JITTER so the rhythm isn't a metronome.
local REST_SLOWEST = 4
local REST_FASTEST = 1
local REST_GUARD_SPREAD = 0.5
local REST_JITTER = 0.25
-- How much of Commitment goes into pressing on after an attack. The odds are (Commitment * this) to the power of the
-- attacks made in the exchange so far, so a long exchange gets ever less likely and always ends.
local PRESS_ON_SHARE = 0.8

-- DEBUG: one overhead bar per axis, below the health and stamina bars. Remove with DEBUG_BARS, _updateDebugBars and its
-- call in Update.
local DEBUG_BAR_SIZE = 0.05
local DEBUG_BAR_FIRST_ORDER = 10
local DEBUG_BARS: { { Axis: string, Color: Color3 } } = table.freeze({
	{ Axis = Axes.Aggression, Color = Color3.fromRGB(255, 0, 0) },
	{ Axis = Axes.Evasiveness, Color = Color3.fromRGB(255, 140, 0) },
	{ Axis = Axes.Guard, Color = Color3.fromRGB(0, 170, 255) },
	{ Axis = Axes.Tempo, Color = Color3.fromRGB(255, 230, 0) },
	{ Axis = Axes.Commitment, Color = Color3.fromRGB(160, 50, 255) },
})

local function decay(value: number, deltaTime: number, halfLife: number): number
	return value * 0.5 ^ (deltaTime / halfLife)
end

-- How the character is feeling about the fight, as a few axes (see TypeDisposition.Axes) that everything which decides how
-- it behaves in a fight reads. Each axis rests at a baseline of the character's configuration and is leaned by factors:
--   a factor measures one thing about the fight as a strength from 0 to 1 (how hurt we are, how many attacks of ours failed)
--   and leans the axes by it, as strongly as its effects (code defaults, replaced by the character's Config/Disposition)
--   say, times its Importance. What a character values is therefore only configuration: a cautious one has a high
--   Importance on Injury, a berserker turns its effects around.
-- Factors from events (failed attacks, pressure, ...) are counts that fade, so a fight that went badly is forgotten in time.
-- The axes ease toward their target on every reaction tick.
function Disposition.new(Base: any, character: Model)
	local self = setmetatable({}, Disposition)
	self.Base = Base
	self.Character = character
	self.Configuration = Base.Configuration
	self.Distance = Base.Distance
	self.CharacterAPI = Base.CharacterAPI
	self.State = Base.State
	-- The raw humanoid, read only (Base.Humanoid is replaced by its module after we are built)
	self.Humanoid = Base.Humanoid :: Humanoid

	self.Subscriptions = {}

	-- The character we are fighting, if any, which is who TargetWeak looks at
	self.focusTarget = nil :: Model?

	-- The counts the event factors are made of
	self.failedAttacks = 0
	self.landedAttacks = 0
	self.pressure = 0
	-- Seconds of the opening left
	self.opening = 0
	-- Seconds we have been engaged without anything being exchanged
	self.sinceExchange = 0
	-- The stimulant factors' pulses: how strong each was perceived, and the seconds of it left
	self.pulses = {} :: { [string]: { Strength: number, Hold: number, Left: number } }
	-- The stimulants already perceived (id -> when they expire), so each counts once
	self.perceived = {} :: { [number]: number }

	self.Values = {} :: { [string]: number }
	for axis in Axes do
		self.Values[axis] = self:_getBaseline(axis)
	end
	self.Signals = {} :: { [string]: number }
	-- DEBUG (see _updateDebugBars)
	self.debugBars = nil :: { [string]: any }?

	return self
end

-- Runs once Events exist, which every module is built after
function Disposition:Init()
	local events = self.Base.Events

	table.insert(
		self.Subscriptions,
		events:Subscribe(ThoughtEvents.ReactionUpdate, function(elapsed)
			self:Update(elapsed)
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(CombatEvents.DamageTaken, function(payload)
			self:_onDamageTaken(payload)
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(CombatEvents.DefenseSucceeded, function()
			self.opening = OPENING_DURATION
			self.sinceExchange = 0
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(CombatEvents.AttackLanded, function()
			self.landedAttacks += 1
			self.sinceExchange = 0
		end)
	)
	for _, failed in { CombatEvents.AttackDefended, CombatEvents.AttackMissed } do
		table.insert(
			self.Subscriptions,
			events:Subscribe(failed, function()
				self.failedAttacks += 1
				self.sinceExchange = 0
			end)
		)
	end

	-- What other characters made us aware of. Only perceived, never consumed: the mood a stimulant leaves is no reason to take
	-- it from whoever acts on it (Defense, for an incoming hit).
	table.insert(
		self.Subscriptions,
		events:Subscribe(StimulantEvents.Pending, function(pending)
			self:_perceive(pending)
		end)
	)

	-- Who we are fighting, as targetting announces it
	table.insert(
		self.Subscriptions,
		events:Subscribe(TargettingEvents.NewFocusTarget, function(context)
			self:_setFocusTarget(context)
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(TargettingEvents.FocusedTargetChanged, function(change)
			self:_setFocusTarget(if type(change) == "table" then change.Current else nil)
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(TargettingEvents.LostFocusTarget, function()
			self.focusTarget = nil
		end)
	)
end

function Disposition:_setFocusTarget(context: any)
	self.focusTarget = if type(context) == "table" and typeof(context.Character) == "Instance"
		then context.Character :: Model
		else nil
end

function Disposition:_onDamageTaken(payload: any)
	-- events can come from outside the character, so the payload is not taken on trust
	if type(payload) ~= "table" or type(payload.Amount) ~= "number" or payload.Amount ~= payload.Amount then
		return
	end

	local maxHealth = if type(payload.MaxHealth) == "number" and payload.MaxHealth > 0
		then payload.MaxHealth
		else self.Humanoid.MaxHealth
	self.pressure += math.max(payload.Amount, 0) / math.max(maxHealth, 1)
	self.sinceExchange = 0
end

-- Starts the pulse of each stimulant factor whose stimulant is pending and wasn't perceived before
function Disposition:_perceive(pending: any)
	if type(pending) ~= "table" then
		return
	end

	for _, stimulant in pending do
		local entry = if type(stimulant) == "table" then STIMULANT_FACTORS[stimulant.Name] else nil
		if not entry or type(stimulant.Id) ~= "number" or self.perceived[stimulant.Id] then
			continue
		end
		self.perceived[stimulant.Id] = if type(stimulant.ExpiresAt) == "number" then stimulant.ExpiresAt else 0

		local strength = math.clamp(entry.Strength(stimulant), 0, 1)
		local pulse = self.pulses[entry.Factor]
		if not pulse or strength >= pulse.Strength * pulse.Left / pulse.Hold then
			self.pulses[entry.Factor] = { Strength = strength, Hold = entry.Hold, Left = entry.Hold }
		end
	end
end

-- Where the axis rests: the character's configured value, clamped to the axis' 0-1
function Disposition:_getBaseline(axis: string): number
	local baseline = AXIS_BASELINES[axis]
	local value = self.Configuration:Get(baseline.Path)

	return math.clamp(if type(value) == "number" and value == value then value else baseline.Default, 0, 1)
end

function Disposition:_getImportance(factor: string): number
	local value = self.Configuration:Get({ TypeDisposition.Folder, factor, Settings.Importance })

	return if type(value) == "number" and value == value then value else DEFAULT_IMPORTANCE
end

-- How strongly the factor leans the axis at full strength: the character's own value if it has one, else the default
function Disposition:_getEffect(factor: string, axis: string): number
	local value = self.Configuration:Get({ TypeDisposition.Folder, factor, axis })
	if type(value) == "number" and value == value then
		return value
	end

	return DEFAULT_EFFECTS[factor][axis] or 0
end

-- How weak the character we are fighting is, from 0 (unhurt and rested, or no one to fight) to 1 (nothing left). It is the
-- more of how hurt it is and whether it is exhausted. Asked of the API, as the target is another character; a target
-- whose health can't be read counts as unhurt.
function Disposition:_measureTargetWeakness(): number
	local target = self.focusTarget
	if not target then
		return 0
	end

	local weakness = 0
	local info = self.CharacterAPI:GetHealthInfo(target)
	if type(info) == "table" and type(info.Fraction) == "number" and info.Fraction == info.Fraction then
		-- squared like injury: a target that took a few knocks isn't weak yet, one that is nearly down very much is
		local missing = 1 - math.clamp(info.Fraction :: number, 0, 1)
		weakness = missing * missing
	end

	-- the target's own state says whether it is exhausted or staggered, all or nothing like our Exhaustion factor. Each is a
	-- request, so one is only made when the weakness so far is still below what it would give.
	if weakness < STAGGERED_TARGET_WEAKNESS and self.CharacterAPI:IsStaggered(target) then
		weakness = STAGGERED_TARGET_WEAKNESS
	end
	if weakness < EXHAUSTED_TARGET_WEAKNESS and self.CharacterAPI:IsExhausted(target) then
		weakness = EXHAUSTED_TARGET_WEAKNESS
	end

	return weakness
end

-- How strong each factor is right now, from 0 to 1
function Disposition:_measureSignals(): { [string]: number }
	local maxHealth = self.Humanoid.MaxHealth
	local missingHealth = if maxHealth > 0 then 1 - math.clamp(self.Humanoid.Health / maxHealth, 0, 1) else 0

	-- Asked of the stamina through its function, as it is a behavior module. A character that can't have any is out of it.
	local stamina, maxStamina = self.Base.Functions:CallFunction(FunctionEnum.GetStamina)
	local missingStamina = if type(maxStamina) == "number" and maxStamina > 0
		then 1 - math.clamp((stamina :: number) / maxStamina, 0, 1)
		else 1

	local signals: { [string]: number } = {
		-- squared, so a scratch hardly counts and being nearly dead counts for nearly everything
		[Factors.Injury] = missingHealth * missingHealth,
		[Factors.FailedAttacks] = math.clamp(self.failedAttacks / FAILED_SATURATION, 0, 1),
		[Factors.Pressure] = math.clamp(self.pressure / PRESSURE_SATURATION, 0, 1),
		[Factors.Momentum] = math.clamp(self.landedAttacks / MOMENTUM_SATURATION, 0, 1),
		[Factors.Stalemate] = math.clamp((self.sinceExchange - STALEMATE_GRACE) / STALEMATE_RAMP, 0, 1),
		[Factors.Opening] = math.clamp(self.opening / OPENING_DURATION, 0, 1),
		-- squared like injury: being a little winded doesn't change how a character fights, being spent does
		[Factors.Stamina] = missingStamina * missingStamina,
		[Factors.TargetWeak] = self:_measureTargetWeakness(),
		-- all or nothing: the state is exactly what the Stamina module decided
		[Factors.Exhaustion] = if self.State:Is(EXHAUSTION_STATE_KEY, ExhaustionStateEnum.Exhausted) then 1 else 0,
	}

	-- the stimulant factors, fading over their hold
	for factor, pulse in self.pulses do
		signals[factor] = pulse.Strength * math.clamp(pulse.Left / pulse.Hold, 0, 1)
	end

	return signals
end

-- Where the axis ends up from its baseline and the sum of what the factors lean it by. A small lean moves it about as far
-- as it says, a big one less and less: it nears 0 or 1 without reaching them. Clamping instead pins an axis at the edge as
-- soon as a couple of factors agree, where characters stop being told apart and a factor leaning the other way isn't felt
-- at all until the others fade.
local function saturate(baseline: number, lean: number): number
	local room = if lean >= 0 then 1 - baseline else baseline
	if room <= 0 then
		return baseline
	end

	return baseline + math.sign(lean) * room * (1 - math.exp(-math.abs(lean) / room))
end

-- Where the factors want the axis: its baseline plus what each of them leans it by, eased into the 0-1 (see saturate)
function Disposition:_getTarget(axis: string, signals: { [string]: number }): number
	local baseline = self:_getBaseline(axis)
	local lean = 0
	for factor, signal in signals do
		if signal > 0 then
			lean += self:_getImportance(factor) * signal * self:_getEffect(factor, axis)
		end
	end

	return math.clamp(saturate(baseline, lean), 0, 1)
end

-- Runs on every reaction tick, with the seconds since the last one
function Disposition:Update(deltaTime: number)
	local step = math.clamp(if type(deltaTime) == "number" then deltaTime else 0, 0, MAX_STEP)

	self.failedAttacks = decay(self.failedAttacks, step, FAILED_HALF_LIFE)
	self.landedAttacks = decay(self.landedAttacks, step, MOMENTUM_HALF_LIFE)
	self.pressure = decay(self.pressure, step, PRESSURE_HALF_LIFE)
	self.opening = math.max(self.opening - step, 0)
	for factor, pulse in self.pulses do
		pulse.Left -= step
		if pulse.Left <= 0 then
			self.pulses[factor] = nil
		end
	end
	-- a stimulant that ran out can't be perceived again, so it needn't be remembered
	local now = os.clock()
	for id, expiresAt in self.perceived do
		if expiresAt <= now then
			self.perceived[id] = nil
		end
	end
	-- only a fight in each other's face can stall
	if self.Distance:IsEngaged() then
		self.sinceExchange += step
	else
		self.sinceExchange = 0
	end

	local signals = self:_measureSignals()
	self.Signals = signals

	local ease = 1 - math.exp(-step / AXIS_SMOOTH_TIME)
	for axis in Axes do
		local current = self.Values[axis]
		self.Values[axis] = current + (self:_getTarget(axis, signals) - current) * ease
	end

	self:_updateDebugBars()
end

-- DEBUG: shows each axis' current value as the fill of its own bar. The bars are made on the first tick, as the API is not
-- ready to make them while the module is built, and a failed one is skipped (the API warns).
function Disposition:_updateDebugBars()
	local bars = self.debugBars
	if not bars then
		bars = {}
		self.debugBars = bars
		for index, entry in DEBUG_BARS do
			bars[entry.Axis] = self.CharacterAPI:CreateBar("Disposition" .. entry.Axis, {
				Fill = self.Values[entry.Axis],
				FillColor = entry.Color,
				ChangeFillColor = entry.Color,
				Size = DEBUG_BAR_SIZE,
				LayoutOrder = DEBUG_BAR_FIRST_ORDER + index,
			})
		end
	end

	for axis, bar in bars do
		bar:SetFill(self.Values[axis])
	end
end

-- The axis' current value, from 0 to 1
function Disposition:GetDisposition(axis: string): number
	local value = self.Values[axis]
	if value == nil then
		warn("Unknown disposition axis:", axis)
		return 0
	end

	return value
end

-- A copy of every axis' current value
function Disposition:GetAxes(): { [string]: number }
	return table.clone(self.Values)
end

-- A copy of how strong each factor was on the last tick
function Disposition:GetSignals(): { [string]: number }
	return table.clone(self.Signals)
end

-- The distance we hold from our target: the one our configuration has for the targetting range, moved by how aggressive we
-- feel. Aggressive characters get in close and wary ones keep their distance. Nil if the range isn't configured.
function Disposition:GetEngageDistance(targettingRange: TypeTargetting.TargettingRange): number?
	local configured = self.Distance:GetEngageDistance(targettingRange)
	if not configured then
		return nil
	end

	local scale = 1 + (0.5 - self.Values[Axes.Aggression]) * ENGAGE_DISTANCE_SPREAD

	return math.max(configured * scale, self.Distance:GetTooCloseDiff() + MIN_ENGAGE_GAP)
end

-- The distance we stand at to make an attack: a share of its DesiredRange, closer the more aggressive we feel. This is
-- also where the attack is made from (see AttackTargets), so holding it and attacking from it are the same distance.
function Disposition:GetAttackStandoff(attack: TypeAttack.AttackData): number
	local range = attack.DesiredRange
	local share = ATTACK_STANDOFF_WARY
		+ (ATTACK_STANDOFF_AGGRESSIVE - ATTACK_STANDOFF_WARY) * self.Values[Axes.Aggression]

	return math.clamp(range * share, math.min(MIN_ATTACK_STANDOFF, range), range)
end

-- The distance ChaseTargets and Engage hold from the target, which they both ask so they agree on where the handoff
-- happens. It is the engage distance (what we like) unless the attack we mean to make needs us closer, in which case it is
-- the attack's standoff: the attack only ever pulls us in past our preference, it never keeps us further out than it. A
-- character that can't attack (or can't afford the attack) has nothing to close in for and goes back to its own spacing, which backs it off from where
-- the attack had it standing (after a swing, say, or when staggered). So does one that is resting between exchanges, which
-- is the spacing it defends from: out of reach, guarding and circling. An attack that presses on into another is the one
-- exception to backing off after a swing, the character stays in reach to make the follow-up.
function Disposition:GetHoldDistance(targettingRange: TypeTargetting.TargettingRange): number?
	local preferred: number? = self:GetEngageDistance(targettingRange)
	if preferred == nil then
		return nil
	end

	local functions = self.Base.Functions
	if not functions:CallFunction(FunctionEnum.IsReadyToAttack) then
		return preferred
	end

	if not functions:CallFunction(FunctionEnum.CanAttack) and not functions:CallFunction(FunctionEnum.IsPressingOn) then
		return preferred
	end

	local attack = functions:CallFunction(FunctionEnum.GetDesiredAttack)
	if not attack then
		return preferred
	end

	-- An attack we can't pay for is not worth closing in for either
	if not functions:CallFunction(FunctionEnum.CanAffordAttack, attack) then
		return preferred
	end

	-- (a mod's replacement may answer with nothing, then the attack has no say)
	local standoff: number? = functions:CallFunction(FunctionEnum.GetAttackStandoff, attack)
	if not standoff or standoff ~= standoff then
		return preferred
	end

	return math.min(preferred, standoff)
end

-- How well an attack suits where we are, from above 0 to 1, for choosing the next attack (see Attacks:PickDesiredAttack).
-- An attack we can already make from where we would settle is 1; one that has us walk further in is less likely the
-- further that is. `distance` is how far the target is now, passed in because measuring it is a request and the picker
-- asks about every candidate. Without it, or without a target, nothing is better than anything else.
function Disposition:GetAttackFit(attack: TypeAttack.AttackData, distance: number?): number
	return self:_getReachFit(attack, distance) * self:_getCommitmentFit(attack)
end

function Disposition:_getReachFit(attack: TypeAttack.AttackData, distance: number?): number
	-- (also catches a NaN, which is the one number that isn't equal to itself)
	if not distance or distance ~= distance then
		return 1
	end

	local preferred = self:GetEngageDistance(self.Configuration:GetThoughtSetting("TargettingRange"))
	-- asked through the functions like everywhere else, so a mod that changes the standoff changes the fit with it
	local standoff = self.Base.Functions:CallFunction(FunctionEnum.GetAttackStandoff, attack)
	if type(standoff) ~= "number" or standoff ~= standoff then
		return 1
	end

	-- where we would stand left to our own spacing: where we are if that is already closer than we like
	local settled: number = if preferred then math.min(distance, preferred) else distance
	local walk = math.max(settled - standoff, 0)

	return 0.5 ^ (walk / ATTACK_FIT_HALF_DISTANCE)
end

-- How committing an attack is, from 0 to 1: one third for each of not being able to move through it, not being able to
-- cut it short, and being a combo. A committed character favours the attacks that commit it, a tentative one the attacks
-- it can walk out of or stop.
function Disposition:_getCommitmentFit(attack: TypeAttack.AttackData): number
	local commits = (if attack.AllowMoving then 0 else 1)
		+ (if attack.AllowInterrupts then 0 else 1)
		+ (if attack.IsCombo then 1 else 0)
	local mismatch = math.abs(self.Values[Axes.Commitment] - commits / 3)

	return 1 - COMMITMENT_FIT_STRENGTH * mismatch
end

-- How the character carries on from an attack it is beginning, `chain` being the number of attacks in this exchange so far
-- (this one included). A committed character presses on: it stays in reach and makes another straight away, with the odds
-- of (Commitment * PRESS_ON_SHARE) ^ chain. Otherwise the exchange is over once this attack is, and the character rests out
-- of reach for a time: shorter the higher its Tempo, longer the more it guards.
function Disposition:GetAttackPace(chain: number): TypeAttack.AttackPace
	local pressOn = math.random() < (self.Values[Axes.Commitment] * PRESS_ON_SHARE) ^ math.max(chain, 1)

	local rest = REST_SLOWEST + (REST_FASTEST - REST_SLOWEST) * self.Values[Axes.Tempo]
	rest *= 1 + (self.Values[Axes.Guard] - 0.5) * 2 * REST_GUARD_SPREAD
	rest *= 1 + (math.random() * 2 - 1) * REST_JITTER

	return { PressOn = pressOn, Rest = rest }
end

function Disposition:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end
	self.Subscriptions = {}
	self.Configuration = nil
	self.Distance = nil
	self.CharacterAPI = nil
	self.State = nil
	self.focusTarget = nil
	self.pulses = {}
	self.perceived = {}
	self.debugBars = nil
	self.Base = nil
end

return Disposition
