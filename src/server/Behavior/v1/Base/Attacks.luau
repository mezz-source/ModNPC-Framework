local ServerScriptService = game:GetService("ServerScriptService")
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)

local Attacks = {}
Attacks.__index = Attacks

local ContentEvents = TypeCharacterEvents.Names.Content
local StateEvents = TypeCharacterEvents.Names.State
local FunctionEnum = TypeCharacterFunctions.FunctionEnum

local AttackTypes = TypeAttack.AttackTypes

-- An attack's animation is the one named like it in the Attacks category of the same source's Assets/Animations
local ANIMATION_CATEGORY = "Attacks"
local ANIMATION_PRIORITY = Enum.AnimationPriority.Action

local ATTACK_STATE_KEY = TypeState.Keys.AttackState
local AttackStateEnum = TypeState.AttackStateEnum

function Attacks.new(Base: any, character: Model)
	local self = setmetatable({}, Attacks)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	-- Swinging from the moment an attack starts until its debounce is over, owned by the attack task
	Base.State:Register(ATTACK_STATE_KEY, AttackStateEnum)
	-- The attacks of each content source, keyed by source. A weapon's attacks only exist while it is equipped.
	self.Sources = { [Base.Assets.BaseSource] = self.CharacterAPI:GetAttacksIndex() or {} } :: {
		[TypeCDN.ContentSource]: TypeAttack.AttackIndex,
	}
	-- The attack the character means to make next, so the others can get into position for it (see PickDesiredAttack)
	self.Desired = nil :: TypeAttack.AttackCandidate?
	-- The attack task that is running, so it can be cancelled (see CancelCurrentAttack)
	self.CurrentAttackTask = nil :: any

	-- The rhythm of the fight: attacks come in exchanges of one or more, and the character rests out of reach between them.
	-- How an exchange goes is decided as each of its attacks begins (see _onAttackStateChanged).
	-- The attacks made in the exchange so far
	self.Chain = 0
	-- Whether the attack being made presses on into another, and how long the rest is if it doesn't
	self.PressingOn = false
	self.PendingRest = 0
	-- Until when (os.clock) the character is resting. Nothing is started while it is.
	self.RestUntil = 0

	self.Subscriptions = {
		Base.Events:Subscribe(ContentEvents.SourceAdded, function(payload: TypeCharacterEvents.ContentSourceAdded)
			self:_loadSource(payload.Source)
		end),
		-- The attack animations need no unloading here: Animation drops the tracks of a source when it is removed
		Base.Events:Subscribe(ContentEvents.SourceRemoved, function(payload: TypeCharacterEvents.ContentSourceRemoved)
			self.Sources[payload.Source] = nil
		end),
		Base.Events:Subscribe(StateEvents.Changed, function(change: TypeCharacterEvents.CharacterStateChanged)
			if change.Key == ATTACK_STATE_KEY then
				self:_onAttackStateChanged(change.New)
			end
		end),
	}

	return self
end

-- The attack state is what marks an attack's beginning and its end (debounce included), so the rhythm follows it.
--   Swinging   the attack is committed to, and with it how the exchange goes on: Disposition decides (GetAttackPace) whether
--              it presses on into another attack and how long the rest is once the exchange is over
--   anything else   the attack is over. If it pressed on the character is ready for the next one at once, if not the
--              exchange is over and it rests, out of reach, before the next one.
function Attacks:_onAttackStateChanged(state: string)
	if state == AttackStateEnum.Swinging then
		self.Chain += 1
		-- (a mod's replacement may answer with nothing, then the exchange is a single attack with no rest)
		local pace: TypeAttack.AttackPace? = self.Base.Functions:CallFunction(FunctionEnum.GetAttackPace, self.Chain)
		self.PressingOn = pace ~= nil and pace.PressOn
		self.PendingRest = if pace then math.max(pace.Rest, 0) else 0
		return
	end

	if self.PressingOn then
		self.PressingOn = false
		self.RestUntil = 0
		return
	end

	-- not every end follows a swing we saw begin (a state that was already None), and there is only a rest to take after one
	if self.Chain > 0 then
		self.Chain = 0
		self.RestUntil = os.clock() + self.PendingRest
	end
end

-- Whether the character is done resting and willing to make its next attack. This is the pacing, not the ability: a
-- character that can't attack (see CanAttack) may well be ready to.
function Attacks:IsReadyToAttack(): boolean
	return os.clock() >= self.RestUntil
end

-- Whether the attack being made is committed to a follow-up, in which case the character stays in reach through it instead
-- of backing off. It only holds while the attack is being made.
function Attacks:IsPressingOn(): boolean
	return self.PressingOn
end

-- Only weapons are loaded here, the NPC's own attacks are read when this is built
function Attacks:_loadSource(source: TypeCDN.ContentSource)
	if typeof(source) ~= "Instance" then
		return
	end

	local index = self.CharacterAPI:GetAttacksIndex(source)
	if not index then
		warn("Could not read the attacks of weapon:", source:GetFullName())
		return
	end

	self.Sources[source] = index
	self:_loadAnimations(source)
end

-- Loads the NPC's own attack animations. Runs once the character is built and its functions are registered, because
-- loading is a function.
function Attacks:Init()
	self:_loadAnimations(self.Base.Assets.BaseSource)
end

-- The track name of an attack's animation. Weapons can share attack names with the NPC or each other, so the name
-- carries the source (weapons are named uniquely within the character).
function Attacks:GetAnimationName(attackName: string, source: TypeCDN.ContentSource?): string
	local trackName = ANIMATION_CATEGORY .. "/" .. attackName
	if typeof(source) == "Instance" then
		return source.Name .. "/" .. trackName
	end

	return trackName
end

-- Loads the animation of every attack one source has, as that source's content so they go when it does. Only the
-- source's own animations are looked at: a weapon attack without one has none, it does not borrow the NPC's.
function Attacks:_loadAnimations(source: TypeCDN.ContentSource)
	local animations = {}
	for _, animation in ipairs(self.Base.Assets:GetData(source).Animations[ANIMATION_CATEGORY] or {}) do
		animations[animation.Name] = animation
	end

	for attackName in pairs(self.Sources[source] or {}) do
		local animation = animations[attackName]
		if not animation then
			warn("Attack", attackName, "has no", ANIMATION_CATEGORY .. "/" .. attackName, "animation")
			continue
		end

		-- looped is false: an attack is a one-shot
		self.Base.Functions:CallFunction(
			FunctionEnum.LoadAnimation,
			animation,
			self:GetAnimationName(attackName, source),
			ANIMATION_PRIORITY,
			false,
			source
		)
	end
end

-- Attacks are searched like assets: the NPC first, then weapons in the order they were equipped. A source passed in
-- is searched first, and then the NPC. Returns the attack and the source it was found in.
function Attacks:GetAttack(attackName: string, source: TypeCDN.ContentSource?): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	for _, candidate in ipairs(self.Base.Assets:GetSearchOrder(source)) do
		local index = self.Sources[candidate]
		local attack = if index then index[attackName] else nil
		if attack then
			return attack, candidate
		end
	end

	return nil, nil
end

-- Every attack one source has, the NPC's by default
function Attacks:GetAttackIndex(source: TypeCDN.ContentSource?): TypeAttack.AttackIndex
	return self.Sources[source or self.Base.Assets.BaseSource] or {}
end

-- A request for a Melee or Ranged attack only takes attacks of that type. Generic takes any of them; no stored attack
-- is Generic itself.
local function fitsRequest(attack: TypeAttack.AttackData, attackType: TypeAttack.AttackType): boolean
	return attackType == AttackTypes.Generic or attack.Type == attackType
end

-- Every attack that fits the request, from every source the search covers. The sources come in search order (the NPC,
-- then weapons as they were equipped, or the source passed in first and then the NPC) and each source's attacks are
-- sorted by name, so the same request always gives the same list.
function Attacks:GetAttackCandidates(
	attackType: TypeAttack.AttackType,
	source: TypeCDN.ContentSource?
): { TypeAttack.AttackCandidate }
	local candidates: { TypeAttack.AttackCandidate } = {}

	for _, candidateSource in ipairs(self.Base.Assets:GetSearchOrder(source)) do
		local names = {}
		for attackName, attack in pairs(self.Sources[candidateSource] or {}) do
			if fitsRequest(attack, attackType) then
				table.insert(names, attackName)
			end
		end
		table.sort(names)

		for _, attackName in ipairs(names) do
			table.insert(candidates, {
				Attack = self.Sources[candidateSource][attackName],
				Source = candidateSource,
			})
		end
	end

	return candidates
end

-- The attacks that fit the request from the first source in the search order that has any. Variants of an attack are
-- separate attacks (Punch1, Punch2), and they are all from the same source.
function Attacks:_getFirstSourceCandidates(
	attackType: TypeAttack.AttackType,
	source: TypeCDN.ContentSource?
): { TypeAttack.AttackCandidate }
	local candidates = self:GetAttackCandidates(attackType, source)
	local first = candidates[1]
	if not first then
		return {}
	end

	local fromFirstSource = {}
	for _, candidate in ipairs(candidates) do
		if candidate.Source == first.Source then
			table.insert(fromFirstSource, candidate)
		end
	end

	return fromFirstSource
end

-- One attack that fits the request, and the source it is from. It comes from the first source in the search order that
-- has any fitting attack, and is picked at random among that source's.
function Attacks:FindAttack(
	attackType: TypeAttack.AttackType,
	source: TypeCDN.ContentSource?
): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	local candidates = self:_getFirstSourceCandidates(attackType, source)
	if #candidates == 0 then
		return nil, nil
	end

	local picked = candidates[math.random(1, #candidates)]
	return picked.Attack, picked.Source
end

-- Picks among candidates at random, leaning toward the ones that suit where the character stands (GetAttackFit), so an
-- attack that has it walk a long way to make is rarer than one it can make from where it is. Still random: variants of an
-- attack stay in rotation, only less often the worse they fit.
function Attacks:_pickFittingCandidate(candidates: { TypeAttack.AttackCandidate }): TypeAttack.AttackCandidate
	local target = self:GetCurrentTarget()
	-- measured once, it is a request
	local distance = if target then self.Base.Distance:GetDistanceTo(target) else nil

	local weights = {}
	local total = 0
	for index, candidate in ipairs(candidates) do
		local fit = self.Base.Functions:CallFunction(FunctionEnum.GetAttackFit, candidate.Attack, distance)
		-- what can't be judged counts as fitting like the rest
		local weight = if type(fit) == "number" and fit >= 0 then fit else 1
		weights[index] = weight
		total += weight
	end

	if total <= 0 then
		return candidates[math.random(1, #candidates)]
	end

	local roll = math.random() * total
	for index, candidate in ipairs(candidates) do
		roll -= weights[index]
		if roll <= 0 then
			return candidate
		end
	end

	return candidates[#candidates]
end

-- Settles on the attack to make next, from the NPC's attacks or a source passed in first, and holds on to it until another
-- is picked. The pick favours attacks that suit where the character stands (see _pickFittingCandidate). This is what makes
-- the character close in to the attack's standoff before attacking (see Disposition:GetHoldDistance).
function Attacks:PickDesiredAttack(
	attackType: TypeAttack.AttackType,
	source: TypeCDN.ContentSource?
): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	local candidates = self:_getFirstSourceCandidates(attackType, source)
	if #candidates == 0 then
		self.Desired = nil
		return nil, nil
	end

	local picked = self:_pickFittingCandidate(candidates)
	self.Desired = picked
	return picked.Attack, picked.Source
end

-- The attack we mean to make next, if it is still there to be made (a weapon unequipped since takes its attacks along)
function Attacks:GetDesiredAttack(): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	local desired = self.Desired
	if not desired then
		return nil, nil
	end

	local index = self.Sources[desired.Source]
	if not index or index[desired.Attack.Name] ~= desired.Attack then
		self.Desired = nil
		return nil, nil
	end

	return desired.Attack, desired.Source
end

function Attacks:ClearDesiredAttack()
	self.Desired = nil
end

-- Whether the character could pay for the attack's first hit right now, which is what it takes to start it (the later hits
-- of a combo are paid for as the combo goes on, see the attack task). If it couldn't, why.
function Attacks:CanAffordAttack(attack: TypeAttack.AttackData): (boolean, string?)
	local cost = TypeAttack.WeightCosts[attack.Hits[1].AttackWeight]
	if not cost then
		return false, "Unknown attack weight: " .. tostring(attack.Hits[1].AttackWeight)
	end

	return self.Base.Functions:CallFunction(FunctionEnum.CanAffordStamina, cost)
end

function Attacks:FindMeleeAttack(source: TypeCDN.ContentSource?): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	return self:FindAttack(AttackTypes.Melee, source)
end

function Attacks:FindRangedAttack(source: TypeCDN.ContentSource?): (TypeAttack.AttackData?, TypeCDN.ContentSource?)
	return self:FindAttack(AttackTypes.Ranged, source)
end

function Attacks:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end

	self.Subscriptions = {}
	self.Sources = {}
	self.Desired = nil
	self.CurrentAttackTask = nil
end

-- The target of our targetting task, if we have one. Reads the same state ChaseTargets does.
function Attacks:GetCurrentTarget(): Model?
	local targettingTask = self.Base.Scheduler:GetTask(TypeTask.CategoriesEnum.Targetting) :: any
	local focusTarget = if targettingTask then targettingTask.FocusTarget else nil
	return if focusTarget then focusTarget.Character else nil
end

-- Every attack ends up here. It makes the attack we desire if it fits the request (and the source passed in, if any),
-- or else picks one that does, makes the attack's task and starts it, the task does the rest. One attack is made at a
-- time: it refuses while the last one is still swinging, which includes the attack's debounce.
function Attacks:Attack(
	attackType: TypeAttack.AttackType,
	target: Model,
	source: TypeCDN.ContentSource?
): (boolean, string?)
	-- Covers the attack still swinging as well as being staggered, airborne and so on
	local canAttack, reason = self.Base.Functions:CallFunction(FunctionEnum.CanAttack)
	if not canAttack then
		return false, reason or "Cannot attack"
	end

	local attack, attackSource = self:GetDesiredAttack()
	if attack and (not fitsRequest(attack, attackType) or (source ~= nil and attackSource ~= source)) then
		attack, attackSource = nil, nil
	end
	if not attack then
		attack, attackSource = self:FindAttack(attackType, source)
	end
	if not attack or not attackSource then
		return false, "No " .. attackType .. " attack available"
	end

	-- Before the guard is dropped below: an attack the character can't pay for must leave it as it was
	local affordable, declinedReason = self:CanAffordAttack(attack)
	if not affordable then
		return false, declinedReason or "Cannot afford the attack"
	end

	local context: TypeAttack.AttackContext = {
		Type = attackType,
		Source = attackSource,
		Target = target,
		Attack = attack,
		AnimationName = self:GetAnimationName(attack.Name, attackSource),
	}

	local attackTask, createError = self.Base.CharacterTasks.Attack.new(context)
	if not attackTask then
		warn("Attack could not create task:", createError)
		return false, createError
	end

	-- An attack drops the guard, whichever limbs it uses (a kick doesn't need the arms, but a character is guarding or
	-- attacking). So a guard never gets in the way of an attack request: it just ends, and the character is open.
	for _, blockTask in ipairs(self.Base.Scheduler:GetTasks(TypeTask.CategoriesEnum.Block)) do
		if blockTask:IsRunning() then
			local guard: any = blockTask
			guard:Cancel("Attacking")
		end
	end

	local started, startError = self.Base.Scheduler:Start(attackTask)
	if not started then
		warn("Attack could not start task:", startError)
		return false, startError
	end

	self.CurrentAttackTask = attackTask
	attackTask.Terminated:Connect(function()
		if self.CurrentAttackTask == attackTask then
			self.CurrentAttackTask = nil
		end
	end)

	return true
end

-- Tries to cut the attack being made short. It only does if the attack allows interrupts; one that doesn't plays out as
-- it would have. With `force` the attack is cut short regardless (a stagger takes the character's control away).
-- Returns whether the attack was cancelled, and why not if it wasn't.
function Attacks:CancelCurrentAttack(force: boolean?): (boolean, string?)
	local attackTask = self.CurrentAttackTask
	if not attackTask or not attackTask:IsRunning() then
		return false, "Not attacking"
	end

	if force then
		return attackTask:Cancel("Attack cancelled"), nil
	end

	if not attackTask:CanBeInterrupted() then
		return false, "Attack can't be interrupted"
	end

	return self.Base.Scheduler:Stop(attackTask, "Attack interrupted"), nil
end

-- The attacks below only differ in the kind of attack they make. All of them go for the current focus target.
function Attacks:_attackCurrentTarget(attackType: TypeAttack.AttackType): (boolean, string?)
	local target = self:GetCurrentTarget()
	if not target then
		return false, "No current target"
	end

	return self:Attack(attackType, target)
end

function Attacks:AttackCurrentTarget(): (boolean, string?)
	return self:_attackCurrentTarget(AttackTypes.Generic)
end

function Attacks:MeleeAttackCurrentTarget(): (boolean, string?)
	return self:_attackCurrentTarget(AttackTypes.Melee)
end

function Attacks:RangeAttackCurrentTarget(): (boolean, string?)
	return self:_attackCurrentTarget(AttackTypes.Ranged)
end

return Attacks
