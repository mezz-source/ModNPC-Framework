local ServerScriptService = game:GetService("ServerScriptService")
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local CombatEvents = TypeCharacterEvents.Names.Combat
local StimulantNames = TypeStimulant.Names
local Priorities = TypeStimulant.Priorities
local AttackStateEnum = TypeState.AttackStateEnum
local ATTACK_STATE_KEY = TypeState.Keys.AttackState
local Limbs = TypeAttack.Limbs

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- The limbs an attack uses are resources, so starting it cancels whatever else is using them
local LIMB_RESOURCES = {
	[Limbs.Arms] = { ResourceEnum.Arms },
	[Limbs.Legs] = { ResourceEnum.Legs },
	[Limbs.All] = { ResourceEnum.Arms, ResourceEnum.Legs },
}

-- Seconds the attack waits for the next hit's animation event before it gives up on it
local HIT_TIMEOUT = 10
local FADE_TIME = 0.1

-- One attack, from its first swing to its last hit. It plays the attack's animation (loaded in advance by Attacks) and
-- lets each hit land when the animation reaches the hit's event. The attack's data decides the rest:
--   DesiredRange    the target must be within it, or there is no task at all (getting there is up to whoever attacks)
--   Limbs           the arms and/or legs it claims, which cancels the tasks already using them
--   AllowMoving     when off, the movement tasks are stopped and the character is held still until the attack is over
--   AllowInterrupts when on, stopping the task cuts the animation short. When off the animation plays out, the task
--                   just stops caring about it.
--   IsCombo         how many hits it has
--   Debounce        how long the attack state stays Swinging once the last hit has landed
-- The target is warned of each hit with an IncomingAttack stimulant: the first as soon as the attack is paid for, each
-- next one of a combo as the previous lands. It lasts until the hit's animation event (or the rest of the animation, while
-- the event's time isn't known) and is retracted once the hit resolves or the attack is cut short.
-- An exhausted character attacks at the speed of its stamina efficiency (animation and debounce) and its hits do that share
-- of their damage.
-- Replace on purpose: starting an attack cuts short whatever else is using the limbs it needs.
local AttackTask = {}
AttackTask.__index = AttackTask
setmetatable(AttackTask, Task)

-- The hits to wait for, in order. Only a combo goes past the first.
local function buildHitContexts(attack: TypeAttack.AttackData): { TypeAttack.HitContext }
	local hitContexts: { TypeAttack.HitContext } = {}

	for index, hit in ipairs(attack.Hits) do
		if index > 1 and not attack.IsCombo then
			break
		end

		table.insert(hitContexts, {
			Name = hit.Name,
			EventName = hit.AnimationEventName,
			BaseDamage = hit.BaseDamage,
			DamageType = hit.DamageType,
			AttackWeight = hit.AttackWeight,
			LungeForce = hit.LungeForce,
			KnockbackForce = hit.KnockbackForce,
			HitSoundName = hit.HitSoundName,
			HitVFXName = hit.HitVFXName,
			Special = hit.Special,
			MaxStaggerTime = hit.MaxStaggerTime,
		})
	end

	return hitContexts
end

function AttackTask.new(base, context: TypeAttack.AttackContext)
	if type(context) ~= "table" or typeof(context.Target) ~= "Instance" then
		return nil, "Attack needs a context with a target"
	end

	local attack = context.Attack
	if type(attack) ~= "table" or type(attack.Hits) ~= "table" or #attack.Hits == 0 then
		return nil, "Attack needs a context with a stored attack that has hits"
	end
	if type(context.AnimationName) ~= "string" then
		return nil, "Attack needs a context with the name of its animation"
	end

	local resources = LIMB_RESOURCES[attack.Limbs]
	if not resources then
		return nil, "Attack " .. tostring(attack.Name) .. " has unknown limbs"
	end
	if type(attack.DesiredRange) ~= "number" then
		return nil, "Attack " .. tostring(attack.Name) .. " has no desired range"
	end

	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Attack,
		Resources = resources,
		Dependencies = {
			Dependencies.Distance,
			Dependencies.Events,
			Dependencies.Functions,
			Dependencies.Scheduler,
			Dependencies.State,
		},
		Policy = TypeTask.Policy.Replace,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, AttackTask)
	self.CharacterAPI = base.CharacterAPI
	self.Distance = base.Distance
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler
	self.State = base.State
	self.Context = context

	-- Checked here, before the scheduler gets to cancel anything for us
	if self.State:Is(ATTACK_STATE_KEY, AttackStateEnum.Swinging) then
		return nil, "Already attacking"
	end

	if not self.Distance:IsWithin(context.Target, attack.DesiredRange) then
		return nil, "Target is further than the " .. attack.DesiredRange .. " studs " .. attack.Name .. " is made from"
	end

	self.Hits = buildHitContexts(attack)
	-- The hit we are waiting on, and how long we have been
	self.HitIndex = 0
	self.Waited = 0
	self.HitConnection = nil
	self.Handle = nil
	-- Whether we hold the attack state, so one we never took is never given back
	self.HoldsState = false
	self.MovementHeld = false
	-- Set when the last hit lands. A task that ended any other way was interrupted.
	self.Finished = false
	-- Set by Cancel: the attack is cut short even if its data doesn't allow interrupts
	self.Cancelled = false
	-- The IncomingAttack stimulant out for the hit we are waiting on, to retract once it is no longer true
	self.StimulantId = nil :: number?

	return self
end

function AttackTask:Start()
	if self.State:Is(ATTACK_STATE_KEY, AttackStateEnum.Swinging) then
		return false, "Already attacking"
	end

	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (last hit, interrupted, replaced, death), let go of everything we took
	self.Terminated:Connect(function()
		self:_cleanup()
	end)

	local context = self.Context
	local attack = context.Attack

	-- The first hit is paid for before anything else is touched: an attack that can't be paid for doesn't happen
	local paid, declinedReason = self:_payForHit(self.Hits[1])
	if not paid then
		local reason = declinedReason or "Attack could not be paid for"
		self:Stop(reason)
		return false, reason
	end

	-- before anything else is touched, so an attack that cannot be shown fails clean
	local handle = self.Functions:CallFunction(FunctionEnum.PlayAnimation, context.AnimationName, FADE_TIME)
	if not handle then
		local reason = "Attack animation could not be played: " .. context.AnimationName
		self:Stop(reason)
		return false, reason
	end



	self.Handle = handle
	-- Asked after the first hit was paid for: that payment is what can leave the character exhausted
	self:_applySpeed()
	-- after the speed, so the warning lasts as long as the hit really takes
	self:_warnTarget(1)
	self.State:Set(ATTACK_STATE_KEY, AttackStateEnum.Swinging)
	self.HoldsState = true

	if not attack.AllowMoving then
		self:_holdStill()
	end

	-- one swing for the whole attack, a combo included
	self:_playSound(attack.SwingSoundName)
	self:_listenForHit(1)

	return true
end

-- Buys the stamina a hit costs, by its weight. Declined (with why) when the character can't pay it.
function AttackTask:_payForHit(hit: TypeAttack.HitContext): (boolean, string?)
	local cost = TypeAttack.WeightCosts[hit.AttackWeight]
	if not cost then
		return false, "Unknown attack weight: " .. tostring(hit.AttackWeight)
	end

	return self.Functions:CallFunction(FunctionEnum.PurchaseStamina, cost)
end

-- How well the character does things right now (1 rested, less when exhausted, see Stamina). An attack goes at this speed
-- and its hits do this share of their damage.
function AttackTask:_getEfficiency(): number
	local efficiency = self.Functions:CallFunction(FunctionEnum.GetStaminaEfficiency)

	return if type(efficiency) == "number" and efficiency > 0 then efficiency else 1
end

-- The animation plays at the speed of the efficiency. Always set, even at 1: the track keeps the speed of its last swing.
function AttackTask:_applySpeed()
	self.Handle:AdjustSpeed(self:_getEfficiency())
end

-- Whether the attack lets itself be cut short: only while it is running, and only if its data allows interrupts
function AttackTask:CanBeInterrupted(): boolean
	return self:IsRunning() and self.Context.Attack.AllowInterrupts
end

-- Ends the attack whether or not its data allows interrupts, and its animation with it. For things that take the
-- character's control away (a stagger); a hit that merely tries to interrupt goes through CanBeInterrupted instead.
function AttackTask:Cancel(reason: string?): boolean
	self.Cancelled = true
	return self:Stop(reason or "Attack cancelled")
end

-- Sounds are looked up in the attack's own source first. An empty name is a silent hit.
function AttackTask:_playSound(soundName: string)
	if soundName == "" then
		return
	end

	self.Functions:CallFunction(FunctionEnum.PlaySound, soundName, self.Context.Source)
end

-- Played at the target's root part (the API finds it), looked up in the attack's own source first. An empty name is a
-- hit with no effect.
function AttackTask:_playHitVFX(vfxName: string, target: Model)
	if vfxName == "" then
		return
	end

	self.Functions:CallFunction(FunctionEnum.PlayVFX, vfxName, target, self.Context.Source)
end

-- Tells the target a hit is on its way (an IncomingAttack stimulant) with what it needs to decide how to meet it.
-- It lasts until the hit's animation event, or the rest of the animation while the event's time isn't known yet.
function AttackTask:_warnTarget(index: number)
	self:_retractWarning()

	local hit = self.Hits[index]
	local lasting = self.Handle:GetTimeUntilMarker(hit.EventName) or self.Handle:GetTimeRemaining()
	if not lasting or lasting <= 0 then
		return
	end

	local result = self.Base
		:NewStimulant(StimulantNames.IncomingAttack)
		:To(self.Context.Target)
		:WithPriority(Priorities.High)
		:Lasting(lasting)
		:WithData({
			AttackWeight = hit.AttackWeight,
			BaseDamage = hit.BaseDamage,
			DamageType = hit.DamageType,
			Special = hit.Special,
			MaxStaggerTime = hit.MaxStaggerTime,
		} :: TypeAttack.HitStimulantContext)
		:Emit()

	-- a target that can't hear stimulants (a player, a plain humanoid) got nothing, so there is nothing to retract later
	self.StimulantId = if result and result.Delivered > 0 then result.Id else nil
end

-- The warning for the hit we were waiting on is no longer true: it resolved, or the attack was cut short
function AttackTask:_retractWarning()
	local id = self.StimulantId
	if not id then
		return
	end

	self.StimulantId = nil
	self.CharacterAPI:RetractStimulant(id)
end

-- Walking tasks end, and the character is held still until we let go (so nothing can walk it again meanwhile)
function AttackTask:_holdStill()
	for _, movementTask in ipairs(self.Scheduler:GetTasks(CategoryEnum.Movement)) do
		movementTask:Stop("Attack does not allow moving")
	end

	self.Functions:CallFunction(FunctionEnum.LockMovement, self)
	self.MovementHeld = true
end

-- Connects to the animation event of one hit and waits for it. Only this hit is listened to: events that come out of
-- order are ignored.
function AttackTask:_listenForHit(index: number)
	local hit = self.Hits[index]
	self.HitIndex = index
	self.Waited = 0

	self.HitConnection = self.Handle:GetMarkerReachedSignal(hit.EventName):Connect(function()
		self:_hitReached(index)
	end)
end

function AttackTask:_disconnectHit()
	if self.HitConnection then
		self.HitConnection:Disconnect()
		self.HitConnection = nil
	end
end

-- Tells the character's listeners how a hit of this attack went (landed, defended or missed), see Names.Combat
function AttackTask:_announceOutcome(eventName: string, hit: TypeAttack.HitContext, dealt: TypeDamage.OutgoingDamageContext?)
	self.Events:Dispatch(eventName, {
		Target = self.Context.Target,
		AttackName = self.Context.Attack.Name,
		HitName = hit.Name,
		Amount = if dealt then dealt.Amount else 0,
		RecieveType = if dealt then dealt.RecieveType else nil,
	} :: TypeCharacterEvents.AttackOutcome)
end

-- The animation reached the event of a hit: it lands. After the last one the attack is over.
function AttackTask:_hitReached(index: number)
	if not self:IsRunning() or index ~= self.HitIndex then
		return
	end

	self:_disconnectHit()
	-- the hit is here, whatever it turns out to be
	self:_retractWarning()

	local hit = self.Hits[index]
	local target = self.Context.Target

	if hit.LungeForce > 0 then
		self.CharacterAPI:ApplyForwardImpulse(hit.LungeForce)
	end

	-- The target may have moved (or be gone) since the swing began: a hit that finds it out of range whiffs, and a
	-- combo carries on to its next hit
	if self.Distance:IsWithin(target, self.Context.Attack.DesiredRange) then
		-- The target may have blocked it, so what counts is the damage that went through
		-- an empty special is a hit without one
		local special = if hit.Special ~= "" then hit.Special :: TypeDamage.DamageSpecial else nil
		local response =
			self.CharacterAPI:DealDamage(
				target,
				hit.BaseDamage * self:_getEfficiency(),
				hit.DamageType,
				special,
				hit.MaxStaggerTime
			)
		local dealt = if response then response.Data else nil
		-- A hit that connected sounds like one and pushes the target back, a blocked one included (it connected, it just
		-- did no damage). A dodged hit didn't connect, so it has neither.
		if dealt and dealt.DidHit then
			self:_playSound(hit.HitSoundName)
			self:_playHitVFX(hit.HitVFXName, target)
			if hit.KnockbackForce > 0 then
				self.CharacterAPI:PushAway(target, hit.KnockbackForce)
			end
		end
		-- without an answer from the target there is nothing to say about how the hit went. A blocked hit connected but
		-- the attack still failed to land.
		if dealt then
			local landed = dealt.RecieveType == TypeDamage.RecieveTypes.Hit
			self:_announceOutcome(if landed then CombatEvents.AttackLanded else CombatEvents.AttackDefended, hit, dealt)
		end
	else
		self:_announceOutcome(CombatEvents.AttackMissed, hit, nil)
	end

	if index < #self.Hits then
		-- The next hit of a combo is paid for as the last one lands. If the character can't, the combo ends here: the rest of
		-- the animation is cut off, and the debounce still holds the attack state as for any finished attack.
		if self:_payForHit(self.Hits[index + 1]) then
			-- the payment may have tired the character, and the rest of the combo with it
			self:_applySpeed()
			self:_listenForHit(index + 1)
			self:_warnTarget(index + 1)
			return
		end

		self.Functions:CallFunction(FunctionEnum.StopAnimation, self.Context.AnimationName, FADE_TIME)
		self.Finished = true
		self:Complete("Out of stamina for the next hit")
		return
	end

	self.Finished = true
	self:Complete("Attack finished")
end

function AttackTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.Waited += deltaTime
	if self.Waited > HIT_TIMEOUT then
		local hit = self.Hits[self.HitIndex]
		warn(
			"Attack",
			self.Context.Attack.Name,
			"waited more than",
			HIT_TIMEOUT,
			"seconds for the animation event",
			hit.EventName,
			"- its animation is likely missing the event"
		)
		self:Stop("Timed out waiting for the animation event " .. hit.EventName)
	end
end

function AttackTask:_releaseState()
	if self.State:Is(ATTACK_STATE_KEY, AttackStateEnum.Swinging) then
		self.State:Set(ATTACK_STATE_KEY, AttackStateEnum.None)
	end
end

function AttackTask:_cleanup()
	self:_disconnectHit()
	self:_retractWarning()

	if self.MovementHeld then
		self.MovementHeld = false
		self.Functions:CallFunction(FunctionEnum.UnlockMovement, self)
	end

	if not self.HoldsState then
		return
	end
	self.HoldsState = false

	local attack = self.Context.Attack

	-- All hits landed: the attack state stays up for the debounce, after the task itself is gone. A slower attack recovers
	-- slower as well.
	if self.Finished then
		if attack.Debounce > 0 then
			task.delay(attack.Debounce / self:_getEfficiency(), function()
				self:_releaseState()
			end)
		else
			self:_releaseState()
		end

		return
	end

	-- Interrupted. An attack that allows it (or was cancelled) is cut short, any other plays its animation out and only
	-- stops mattering.
	if (attack.AllowInterrupts or self.Cancelled) and self.Handle then
		self.Functions:CallFunction(FunctionEnum.StopAnimation, self.Context.AnimationName, FADE_TIME)
	end

	self:_releaseState()
end

return AttackTask
