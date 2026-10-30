local ServerScriptService = game:GetService("ServerScriptService")
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeSkills = require(ServerScriptService.ModNPCServer.Types.v1.TypeSkills)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)

local Damage = {}
Damage.__index = Damage

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local CombatEvents = TypeCharacterEvents.Names.Combat
local StaminaEvents = TypeCharacterEvents.Names.Stamina
local StateEvents = TypeCharacterEvents.Names.State
local AnimationCategories = TypeDamage.AnimationCategories
local Specials = TypeDamage.Specials
local Settings = TypeDamage.Settings
local HealthSettings = TypeDamage.HealthSettings
local MovementEnum = TypeMovement.MovementEnum
local Skills = TypeSkills.Skills

local HEALTH_STATUS_KEY = TypeState.Keys.HealthStatus
local HealthStatusEnum = TypeState.HealthStatusEnum
local STAGGER_STATE_KEY = TypeState.Keys.StaggerState
local DODGE_STATE_KEY = TypeState.Keys.DodgeState
local BLOCK_STATE_KEY = TypeState.Keys.BlockState
local BLOCK_BREAK_STATE_KEY = TypeState.Keys.BlockBreakState
local StaggerStateEnum = TypeState.StaggerStateEnum
local DodgeStateEnum = TypeState.DodgeStateEnum
local BlockStateEnum = TypeState.BlockStateEnum
local BlockBreakStateEnum = TypeState.BlockBreakStateEnum
local HitCategories = TypeDamage.HitCategories

-- What a setting of the character's Config/Damage (or Config/Health) folder is when the folder doesn't have it, see
-- TypeDamage.Settings and TypeDamage.HealthSettings
local SETTING_DEFAULTS: { [string]: number } = table.freeze({
	[HealthSettings.StablePercent] = 70,
	[HealthSettings.InjuredPercent] = 40,
	[Settings.RecieveMultiplier] = 1,
	-- Which hit reaction plays depends on the damage actually taken, not on the share of our health it was
	[Settings.LightThreshold] = 30,
	[Settings.MediumThreshold] = 50,
	[Settings.MinReactionThreshold] = 5,
	-- A bit weaker than a dodge's 130 (about 4.5 studs against 6.4); much below this friction eats it
	[Settings.StaggerBackwardImpulse] = 70,
	-- About 13 studs up and 13 back, over 0.7s in the air. A humanoid keeps braking its sideways speed in the air too, so
	-- the backward throw is far from linear (20 goes 1.4 studs, 40 goes 5.7).
	[Settings.LaunchUpwardImpulse] = 70,
	[Settings.LaunchBackwardImpulse] = 60,
	[Settings.ResistedStaggerMultiplier] = 0.5,
})

local REACTION_FADE_TIME = 0.1
-- Seconds a StaggerBackwards waits for its animation to finish before it lets go of the character anyway
local STAGGER_BACKWARDS_TIMEOUT = 5

-- How a broken guard shows (see _showBlockBreak): a red fill and outline at once, the fill fading out over
-- BLOCK_BREAK_FLASH_TIME, then the outline pulsing (BLOCK_BREAK_PULSE_PERIOD seconds per pulse) until the break is over,
-- when it fades out over BLOCK_BREAK_FADE_OUT_TIME
local BLOCK_BREAK_HIGHLIGHT = "BlockBreak"
local BLOCK_BREAK_COLOR = Color3.fromRGB(255, 35, 35)
local BLOCK_BREAK_FILL_TRANSPARENCY = 0.35
local BLOCK_BREAK_FLASH_TIME = 0.4
local BLOCK_BREAK_PULSE_PERIOD = 0.6
local BLOCK_BREAK_FADE_OUT_TIME = 0.3

-- A setting that is missing, or isn't a number, is its default
local function numberOrDefault(value: any, settingName: string): number
	if type(value) == "number" and value == value then
		return value
	end

	return SETTING_DEFAULTS[settingName]
end

function Damage.new(Base: any, character: Model)
	local self = setmetatable({}, Damage)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Humanoid = Base.Humanoid :: Humanoid

	-- A character can spawn already hurt, so the starting status comes from its health. Configuration doesn't exist yet,
	-- so this is by the default percents; Init works it out again by the character's own.
	Base.State:Register(
		HEALTH_STATUS_KEY,
		HealthStatusEnum,
		self:_healthStatusFor(self.Humanoid.Health, self.Humanoid.MaxHealth)
	)

	-- Held by a Stagger task, or by a StaggerBackwards for as long as its animation plays (see BeginStagger)
	Base.State:Register(STAGGER_STATE_KEY, StaggerStateEnum)

	-- Held by a Block task for as long as it guards (see BeginBlock). Hits that come in meanwhile are absorbed.
	Base.State:Register(BLOCK_STATE_KEY, BlockStateEnum)

	-- Active from a guard break until the exhaustion it forces is over (see BreakBlock). The guard can't go up meanwhile.
	Base.State:Register(BLOCK_BREAK_STATE_KEY, BlockBreakStateEnum, BlockBreakStateEnum.Inactive)
	-- The highlight of the break in progress, and one still fading out from the last break
	self.blockBreakHighlight = nil :: TypeHighlights.Highlight?
	self.fadingBlockBreakHighlight = nil :: TypeHighlights.Highlight?
	-- Identifies the break in progress, so the pulse of an earlier one that is already over doesn't start late
	self.blockBreakToken = nil :: {}?

	-- The hit reaction animation currently playing, so the next hit can replace it
	self.reactionAnimation = nil :: string?
	-- Identifies the StaggerBackwards in progress, so a late animation end can't release a stagger that isn't its own
	self.backwardsToken = nil :: {}?

	-- Counts the health changes we caused ourselves and haven't seen come in yet, so they aren't mistaken for unregistered
	-- damage. A count, not a flag: reverting unregistered damage and then taking it again is two changes in a row, and with
	-- deferred signals both can arrive after we made them.
	self.pendingSelfChanges = 0
	self.lastHealth = self.Humanoid.Health

	self.healthChangedConnection = self.Humanoid.HealthChanged:Connect(function(newHealth: number)
		self:_onHealthChanged(newHealth)
	end)

	self.ConfigSubscriptions = {}
	self.EventSubscriptions = {}

	return self
end

-- Runs once Configuration exists. The health status goes by the percents of Config/Health, so it is worked out again
-- now and whenever they are edited.
function Damage:Init()
	self:_updateHealthStatus()

	for _, settingName in HealthSettings do
		table.insert(
			self.ConfigSubscriptions,
			self.Base.Configuration:Observe({ "Health", settingName }, function()
				self:_updateHealthStatus()
			end)
		)
	end

	-- A broken guard is over once the character has recovered from the exhaustion, or once it is dead
	local events = self.Base.Events
	table.insert(
		self.EventSubscriptions,
		events:Subscribe(StaminaEvents.ExhaustionEnded, function()
			self:_endBlockBreak()
		end)
	)
	table.insert(
		self.EventSubscriptions,
		events:Subscribe(StateEvents.Changed, function(change: TypeCharacterEvents.CharacterStateChanged)
			if change.Key == HEALTH_STATUS_KEY and change.New == HealthStatusEnum.Dead then
				self:_endBlockBreak()
			end
		end)
	)
end

-- Damage that came through the API (attacker aware). Health is still ours to take.
function Damage:ReceiveRegistered(incoming: TypeDamage.IncomingDamageContext): TypeDamage.OutgoingDamageContext
	return self:Receive({
		Attacker = incoming.Attacker,
		Receiver = self.Character,
		Amount = incoming.Amount,
		DamageType = incoming.DamageType,
		Special = incoming.Special,
		MaxStaggerTime = incoming.MaxStaggerTime,
		Registered = true,
	})
end

-- A setting of Config/Damage. Read every time it is needed, so edits to the configuration apply to the next hit.
function Damage:_getSetting(settingName: string): number
	local configuration = self.Base.Configuration
	return numberOrDefault(if configuration then configuration:GetDamageSetting(settingName) else nil, settingName)
end

-- A setting of Config/Health
function Damage:_getHealthSetting(settingName: string): number
	local configuration = self.Base.Configuration
	return numberOrDefault(if configuration then configuration:GetHealthSetting(settingName) else nil, settingName)
end

-- Anything alive below the injured percent is critical
function Damage:_healthStatusFor(health: number, maxHealth: number): string
	if health <= 0 then
		return HealthStatusEnum.Dead
	end

	local percent = if maxHealth > 0 then health / maxHealth * 100 else 0
	if percent >= self:_getHealthSetting(HealthSettings.StablePercent) then
		return HealthStatusEnum.Stable
	elseif percent >= self:_getHealthSetting(HealthSettings.InjuredPercent) then
		return HealthStatusEnum.Injured
	end

	return HealthStatusEnum.Critical
end

-- Damage from something that never told us (a legacy script touching the humanoid). The health is already gone, so it is
-- given back and the damage is received again as registered Generic damage: it can be dodged, blocked and scaled like any
-- other hit. Damage that killed the character can't be given back, so that is only received as it is.
function Damage:ReceiveUnregistered(amount: number): TypeDamage.OutgoingDamageContext
	if self:_restoreSelfHealth(amount) then
		return self:ReceiveRegistered({
			Attacker = nil,
			Receiver = self.Character,
			Amount = amount,
			DamageType = TypeDamage.DamageTypes.Generic,
		})
	end

	return self:Receive({
		Attacker = nil,
		Receiver = self.Character,
		Amount = amount,
		Registered = false,
	})
end

function Damage:_isDodging(): boolean
	return self.Base.State:Is(DODGE_STATE_KEY, DodgeStateEnum.Active)
end

-- Every hit on this character ends up here. Whether it is defended against is decided before it lands, not here: the
-- attacker warned us of it (an IncomingAttack stimulant) and Defense met it with a dodge, whose active span is what makes it
-- miss, or a guard, which takes it. A hit nobody warned us of meets whatever we were already doing.
function Damage:Receive(context: TypeDamage.ReceivedDamageContext): TypeDamage.OutgoingDamageContext
	-- Unregistered damage has already landed, so there is nothing left to dodge or block
	local recieveType = TypeDamage.RecieveTypes.Hit
	-- Whether a Block task is the one that took the hit, which then has to be told how heavy it was
	local absorbedByBlock = false
	if context.Registered then
		-- we're in an active dodge and further damage is ignored
		if self:_isDodging() then
			recieveType = TypeDamage.RecieveTypes.Dodged
		elseif self:IsBlocking() then
			-- a guard that is up takes the hit
			recieveType = TypeDamage.RecieveTypes.Blocked
			absorbedByBlock = true
		end
	end

	-- Only a hit that came through does its damage and carries its special. A blocked hit still connected (the attacker's
	-- hit sound and knockback take effect), it just does nothing to us; a dodged one didn't connect at all.
	local landed = recieveType == TypeDamage.RecieveTypes.Hit
	local didHit = landed or recieveType == TypeDamage.RecieveTypes.Blocked
	local special = if landed then context.Special else nil
	local staggerDuration = if special == Specials.Stagger then self:_rollStaggerDuration(context.MaxStaggerTime) else nil
	local amount = if landed then context.Amount else 0
	-- A guard absorbs as much of the hit as the character's stamina efficiency: all of it when rested, and part of the damage
	-- gets through when exhausted. Asked now, before the block pays for the hit, since that payment is what can leave the
	-- character exhausted.
	if absorbedByBlock then
		amount = context.Amount * (1 - self:_getBlockEfficiency())
	end
	-- Unregistered damage was taken in full already, there is nothing left to scale
	if context.Registered then
		amount *= math.max(self:_getSetting(Settings.RecieveMultiplier), 0)
	end

	-- The hit landed with its damage; now Vitality gets to soften what comes with it
	local resisted = false
	if special ~= nil then
		special, staggerDuration, resisted = self:_resistSpecial(special, staggerDuration)
	end

	local outgoing: TypeDamage.OutgoingDamageContext = {
		Attacker = context.Attacker,
		Receiver = context.Receiver,
		Amount = amount,
		DamageType = context.DamageType,
		DidHit = didHit,
		RecieveType = recieveType,
		Special = special,
		StaggerDuration = staggerDuration,
		Resisted = resisted,
	}

	-- Registered damage hasn't touched the humanoid yet
	if context.Registered and outgoing.Amount > 0 then
		self:DealSelfDamage(outgoing.Amount)
	end

	-- Before the outcome is announced: a block that breaks on this hit is already gone by the time anyone hears of it
	if absorbedByBlock then
		self:_absorbWithBlock(context.Amount, context.Attacker)
	end

	self:Post(outgoing)

	return outgoing
end

-- How heavy a hit is, by the damage it comes with: up to the LightThreshold it is light, up to the MediumThreshold medium
-- and above that heavy. The thresholds are the ones the hit reactions go by.
function Damage:GetHitCategory(amount: number): TypeDamage.HitCategory
	if amount <= self:_getSetting(Settings.LightThreshold) then
		return HitCategories.Light
	elseif amount <= self:_getSetting(Settings.MediumThreshold) then
		return HitCategories.Medium
	end

	return HitCategories.Heavy
end

-- The share (0-1) of a hit a guard absorbs: the stamina efficiency of the character
function Damage:_getBlockEfficiency(): number
	local efficiency: any = self.Base.Functions:CallFunction(FunctionEnum.GetStaminaEfficiency)

	return if type(efficiency) == "number" and efficiency == efficiency then math.clamp(efficiency, 0, 1) else 1
end

-- Hands a hit the block took to the Block task, which pays for it and breaks if it can't. The hit is absorbed either way.
-- The attacker (if known) is who gets told when the guard breaks.
function Damage:_absorbWithBlock(amount: number, attacker: Model?)
	-- the scheduler keeps a task that just stopped in its list until it next cleans up, so only a running one is the guard
	for _, blockTask in ipairs(self.Base.Scheduler:GetTasks(TypeTask.CategoriesEnum.Block)) do
		if blockTask:IsRunning() then
			local guard: any = blockTask
			guard:Absorb(self:GetHitCategory(amount), attacker)
			return
		end
	end
end

function Damage:IsBlocking(): boolean
	return self.Base.State:Is(BLOCK_STATE_KEY, BlockStateEnum.Blocking)
end

-- Takes the block state: from now on hits are absorbed. Refuses when the character can't block right now (CanBlock: dead,
-- staggered, in the middle of an attack, or already blocking). Whoever takes the state gives it back with EndBlock.
function Damage:BeginBlock(): (boolean, string?)
	local canBlock, reason = self.Base.Functions:CallFunction(FunctionEnum.CanBlock)
	if not canBlock then
		return false, reason or "Cannot block"
	end

	self.Base.State:Set(BLOCK_STATE_KEY, BlockStateEnum.Blocking)

	return true
end

function Damage:EndBlock()
	if self:IsBlocking() then
		self.Base.State:Set(BLOCK_STATE_KEY, BlockStateEnum.None)
	end
end

function Damage:IsBlockBroken(): boolean
	return self.Base.State:Is(BLOCK_BREAK_STATE_KEY, BlockBreakStateEnum.Active)
end

-- The guard was broken (a Block task calls this as it breaks). The character is left exhausted, if it wasn't already, and
-- the BlockBreakState is Active until that exhaustion is over (ExhaustionEnded), during which it can't block (CanBlock).
-- Shows the break with a red highlight and the BlockBreakEffect VFX.
function Damage:BreakBlock(reason: string?)
	if self.Base.State:Is(HEALTH_STATUS_KEY, HealthStatusEnum.Dead) then
		return
	end

	-- First, so whatever hears of the exhaustion below finds the guard already unable to go up
	self.Base.State:Set(BLOCK_BREAK_STATE_KEY, BlockBreakStateEnum.Active)

	local functions = self.Base.Functions
	if not functions:CallFunction(FunctionEnum.IsExhausted) then
		functions:CallFunction(FunctionEnum.BreakStamina, reason or "Guard broken")
	end

	self:_showBlockBreak()

	-- Only the end of an exhaustion ends the break, so a character that couldn't be exhausted (a mod replaced the stamina
	-- break) would never block again; for it the break is over at once
	if not functions:CallFunction(FunctionEnum.IsExhausted) then
		self:_endBlockBreak()
	end
end

-- The red flash of a broken guard: fill and outline at once, the fill fading out, then the outline pulsing until
-- _endBlockBreak. Emits the BlockBreakEffect VFX on the character as well.
function Damage:_showBlockBreak()
	self.Base.Functions:CallFunction(FunctionEnum.PlayVFX, TypeDamage.BlockBreakVFX, self.Character)

	-- a highlight still fading from the last break has the name the new one needs
	local fading = self.fadingBlockBreakHighlight
	self.fadingBlockBreakHighlight = nil
	if fading then
		fading:Destroy()
	end

	local highlight = self.blockBreakHighlight
	if not highlight or highlight:IsDestroyed() then
		highlight = self.CharacterAPI:CreateHighlight(BLOCK_BREAK_HIGHLIGHT, {
			FillColor = BLOCK_BREAK_COLOR,
			OutlineColor = BLOCK_BREAK_COLOR,
		})
		self.blockBreakHighlight = highlight
	end
	if not highlight then
		return
	end

	local token = {}
	self.blockBreakToken = token

	highlight:SetFillTransparency(BLOCK_BREAK_FILL_TRANSPARENCY)
	highlight:SetOutlineTransparency(0)
	highlight:TweenFillTransparency(1, BLOCK_BREAK_FLASH_TIME)

	task.delay(BLOCK_BREAK_FLASH_TIME, function()
		if self.blockBreakToken ~= token or highlight:IsDestroyed() then
			return
		end

		-- out to nothing and back, over and over, until the end of the break tweens it away
		local pulse =
			TweenInfo.new(BLOCK_BREAK_PULSE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		highlight:TweenOutlineTransparency(1, pulse)
	end)
end

-- The break is over: the BlockBreakState goes back to Inactive, and the highlight fades out and goes
function Damage:_endBlockBreak()
	if not self:IsBlockBroken() then
		return
	end

	self.Base.State:Set(BLOCK_BREAK_STATE_KEY, BlockBreakStateEnum.Inactive)
	self.blockBreakToken = nil

	local highlight = self.blockBreakHighlight
	self.blockBreakHighlight = nil
	if not highlight or highlight:IsDestroyed() then
		return
	end

	-- a tween of each transparency cuts its running one (the fill fade, the outline pulse) short
	highlight:TweenFillTransparency(1, BLOCK_BREAK_FADE_OUT_TIME)
	highlight:TweenOutlineTransparency(1, BLOCK_BREAK_FADE_OUT_TIME)
	self.fadingBlockBreakHighlight = highlight
	task.delay(BLOCK_BREAK_FADE_OUT_TIME, function()
		if self.fadingBlockBreakHighlight == highlight then
			self.fadingBlockBreakHighlight = nil
		end
		highlight:Destroy()
	end)
end

-- Runs once the damage has been fully received (health is final by now)
function Damage:Post(outgoing: TypeDamage.OutgoingDamageContext)
	self:_updateHealthStatus()
	self:_announceOutcome(outgoing)
	if outgoing.Resisted and not self.Base.State:Is(HEALTH_STATUS_KEY, HealthStatusEnum.Dead) then
		self:_playSound(TypeDamage.ResistSound)
	end
	-- Before the reaction: a staggered character has the stagger's animation instead of a flinch
	self:_applySpecial(outgoing)

	-- A guard that takes a hit shows it with the block's own animation (BlockHit), not a flinch on top of it, even when
	-- some of the damage got through
	if outgoing.RecieveType ~= TypeDamage.RecieveTypes.Blocked then
		self:_playReaction(outgoing.Amount)
	end
end

-- Lets the character's listeners know how the hit went for us: it took health off, and/or it was dodged or blocked. A hit
-- that landed for nothing (no damage) is neither. A blocked hit counts as a defense even though it connected, and when
-- some of its damage got through (an exhausted guard) it is announced as damage taken as well.
function Damage:_announceOutcome(outgoing: TypeDamage.OutgoingDamageContext)
	local events = self.Base.Events

	if outgoing.RecieveType ~= TypeDamage.RecieveTypes.Hit then
		events:Dispatch(CombatEvents.DefenseSucceeded, {
			Attacker = outgoing.Attacker,
			RecieveType = outgoing.RecieveType,
		} :: TypeCharacterEvents.DefenseSucceeded)
	end

	if outgoing.Amount > 0 then
		events:Dispatch(CombatEvents.DamageTaken, {
			Attacker = outgoing.Attacker,
			Amount = outgoing.Amount,
			MaxHealth = self.Humanoid.MaxHealth,
			DamageType = outgoing.DamageType,
			Special = outgoing.Special,
		} :: TypeCharacterEvents.DamageTaken)
	end
end

-- Whether a special would take hold of the character right now. A character that is launched takes nothing, a staggered
-- one only takes a launch (which breaks the stagger). There is nothing for Vitality to resist otherwise.
function Damage:_canTakeSpecial(special: string): boolean
	if self:IsLaunched() then
		return false
	end

	return not self:IsStaggered() or special == Specials.Launch
end

-- Vitality softens the stagger or launch a landed hit comes with, and works on the pipeline's result before it is applied:
--   a full Stagger or Launch is rolled for first, and if Vitality holds it is turned into a StaggerBackwards
--   a Stagger that Vitality did not hold off is rolled for again, and if that holds its time is cut down
-- A StaggerBackwards is already the lightest there is. Returns the special and stagger time that are left, and whether
-- Vitality saved the character from any of it. Runs from Receive, which is a runtime path, so going through CallFunction
-- is safe.
function Damage:_resistSpecial(special: string, staggerDuration: number?): (string, number?, boolean)
	if special == Specials.StaggerBackwards or not self:_canTakeSpecial(special) then
		return special, staggerDuration, false
	end

	local functions = self.Base.Functions
	if functions:CallFunction(FunctionEnum.RollSkill, Skills.Vitality).Success then
		return Specials.StaggerBackwards, nil, true
	end

	if special == Specials.Stagger and functions:CallFunction(FunctionEnum.RollSkill, Skills.Vitality).Success then
		local multiplier = math.max(self:_getSetting(Settings.ResistedStaggerMultiplier), 0)
		return special, (staggerDuration or 0) * multiplier, true
	end

	return special, staggerDuration, false
end

-- Somewhere between no time at all and what the hit allows
function Damage:_rollStaggerDuration(maxStaggerTime: number?): number
	return math.random() * math.max(maxStaggerTime or 0, 0)
end

-- Carries out the special effect the hit had, if it landed with one
function Damage:_applySpecial(outgoing: TypeDamage.OutgoingDamageContext)
	if outgoing.Special == Specials.Stagger then
		self:_startStagger(outgoing.StaggerDuration or 0)
	elseif outgoing.Special == Specials.StaggerBackwards then
		self:_staggerBackwards()
	elseif outgoing.Special == Specials.Launch then
		self:_startLaunch()
	else
		return
	end

	-- we dont care if this succedes, this is just a penalty
	self.Base.Functions:CallFunction(FunctionEnum.PurchaseStamina, TypeStamina.Costs.Stagger)
end

-- A Launch is a task of its own: it throws the character up and back, and holds it until it has landed. Starting it takes
-- the launched state, so a character that is already launched (or dead) just doesn't get one. A staggered character does,
-- the launch is the stronger effect and breaks the stagger.
function Damage:_startLaunch()
	if self:IsLaunched() then
		return
	end

	local launchTask, createError = self.Base.CharacterTasks.Launch.new(
		self:_getSetting(Settings.LaunchUpwardImpulse),
		self:_getSetting(Settings.LaunchBackwardImpulse)
	)
	if not launchTask then
		warn("Launch could not create task:", createError)
		return
	end

	local _, startError = self.Base.Scheduler:Start(launchTask)
	if startError then
		warn("Launch could not start task:", startError)
	end
end

-- A Stagger is a task of its own: it starts, loops for the duration and ends. Starting it takes the stagger state, so a
-- character that is already staggered (or dead) just doesn't get one.
function Damage:_startStagger(duration: number)
	if self:IsStaggered() or self:IsLaunched() then
		return
	end

	local staggerTask, createError = self.Base.CharacterTasks.Stagger.new(duration)
	if not staggerTask then
		warn("Stagger could not create task:", createError)
		return
	end

	local _, startError = self.Base.Scheduler:Start(staggerTask)
	if startError then
		warn("Stagger could not start task:", startError)
	else
		self:_playSoundCategory("Stagger")
	end
end

-- Takes the character's control away by putting it in the stagger state (Staggered or Launched): movement and attack
-- tasks are cancelled, even an attack that doesn't allow interrupts.
function Damage:_loseControl(state: string)
	-- First, so the walks stopped below leave the character standing instead of being taken up again
	self.Base.State:Set(STAGGER_STATE_KEY, state)

	local functions = self.Base.Functions
	functions:CallFunction(FunctionEnum.CancelCurrentAttack, true)
	for _, movementTask in ipairs(self.Base.Scheduler:GetTasks(TypeTask.CategoriesEnum.Movement)) do
		movementTask:Stop("Lost control")
	end
	functions:CallFunction(FunctionEnum.StopMoving)
end

-- Takes the stagger state, and with it the character's control. Refuses a character that is dead or already staggered or
-- launched. Whoever takes the state gives it back with EndStagger.
function Damage:BeginStagger(): (boolean, string?)
	if self.Base.State:Is(HEALTH_STATUS_KEY, HealthStatusEnum.Dead) then
		return false, "Dead"
	end
	if self:IsStaggered() or self:IsLaunched() then
		return false, "Already staggered"
	end

	self:_loseControl(StaggerStateEnum.Staggered)

	return true
end

function Damage:EndStagger()
	if self:IsStaggered() then
		self.Base.State:Set(STAGGER_STATE_KEY, StaggerStateEnum.None)
	end
end

-- Takes the launched state, and with it the character's control. Refuses a character that is dead or already launched. A
-- character that is staggered is launched all the same, its stagger is broken first. Whoever takes the state gives it
-- back with EndLaunch.
function Damage:BeginLaunch(): (boolean, string?)
	if self.Base.State:Is(HEALTH_STATUS_KEY, HealthStatusEnum.Dead) then
		return false, "Dead"
	end
	if self:IsLaunched() then
		return false, "Already launched"
	end

	if self:IsStaggered() then
		self:_breakStagger()
	end
	self:_loseControl(StaggerStateEnum.Launched)

	return true
end

function Damage:EndLaunch()
	if self:IsLaunched() then
		self.Base.State:Set(STAGGER_STATE_KEY, StaggerStateEnum.None)
	end
end

-- Ends the stagger the character is in, whichever kind it is, so the state is free to be taken
function Damage:_breakStagger()
	-- a Stagger task puts its animations away and gives the state back as it ends
	for _, staggerTask in ipairs(self.Base.Scheduler:GetTasks(TypeTask.CategoriesEnum.Stagger)) do
		staggerTask:Stop("Stagger broken")
	end

	-- a StaggerBackwards has no task, only its token and the animation it holds the character for
	if self.backwardsToken then
		self.backwardsToken = nil
		if self.reactionAnimation then
			self.Base.Functions:CallFunction(FunctionEnum.StopAnimation, self.reactionAnimation, REACTION_FADE_TIME)
		end
	end

	self:EndStagger()
end

-- Throws the character back and holds it staggered until the animation has ended. Has no task: it is one animation, so
-- nothing loops and there is no duration.
function Damage:_staggerBackwards()
	local began = self:BeginStagger()
	if not began then
		return
	end

	local token = {}
	self.backwardsToken = token

	local connection = nil
	local function finish()
		-- first, so a stagger that was broken meanwhile (see _breakStagger) doesn't leave this hanging on the animation
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if self.backwardsToken ~= token then
			return
		end

		self.backwardsToken = nil
		self:EndStagger()
	end

	self.CharacterAPI:ApplyImpulseInDirection(MovementEnum.Backward, self:_getSetting(Settings.StaggerBackwardImpulse))
	self:_playSoundCategory("StaggerBackwards")

	local handle = self:_playRandomAnimation(AnimationCategories.StaggerBackwards)
	if not handle then
		-- nothing to hold the character for
		finish()
		return
	end

	connection = handle.Stopped:Connect(finish)
	-- an animation that never ends (unloaded, character died) must not hold the character forever
	task.delay(STAGGER_BACKWARDS_TIMEOUT, finish)
end

-- The reaction category for the damage we took, nil when it was too little to react to
function Damage:_reactionCategoryFor(amount: number): string?
	if amount < self:_getSetting(Settings.MinReactionThreshold) then
		return nil
	elseif amount <= self:_getSetting(Settings.LightThreshold) then
		return AnimationCategories.Light
	elseif amount <= self:_getSetting(Settings.MediumThreshold) then
		return AnimationCategories.Medium
	end

	return AnimationCategories.Heavy
end

-- Whether a hit of this category tries to interrupt the attack being made. Medium and heavy hits do for now; once
-- characters have levels this becomes a chance.
local function interruptsAttack(categoryName: string): boolean
	return categoryName == AnimationCategories.Medium or categoryName == AnimationCategories.Heavy
end

-- Plays a random animation of the category the damage falls in. A blocked hit has an amount of 0, so it never gets here.
-- Runs from Post, which is a runtime path, so going through CallFunction is safe.
function Damage:_playReaction(amount: number)
	local categoryName = self:_reactionCategoryFor(amount)
	if not categoryName then
		return
	end

	-- A dead character has its own animation, and its tracks are gone
	if self.Base.State:Is(HEALTH_STATUS_KEY, HealthStatusEnum.Dead) then
		return
	end

	-- A staggered character is already showing its stagger, a flinch would only fight it
	if self:IsStaggered() or self:IsLaunched() then
		return
	end

	-- Before the reaction plays, so a cut-short attack's animation fades out under it. The attack decides whether it
	-- can actually be interrupted.
	if interruptsAttack(categoryName) then
		self.Base.Functions:CallFunction(FunctionEnum.CancelCurrentAttack)
	end

	self:_playRandomAnimation(categoryName)
end

-- An individual sound of the character (or the weapon it holds)
function Damage:_playSound(soundName: string)
	if soundName == "" then
		return
	end

	self.Base.Functions:CallFunction(FunctionEnum.PlaySound, soundName)
end

function Damage:_playSoundCategory(soundName: string)
	if soundName == "" then
		return
	end

	self.Base.Functions:CallFunction(FunctionEnum.PlaySoundCategory, soundName)
end

-- Plays a random animation of the category, replacing the reaction that was playing. Returns its handle, nil when the
-- character has none of the category (or it could not be played).
function Damage:_playRandomAnimation(categoryName: string): any
	-- Animation only loads the NPC's own animations of a category, so only look there
	local animations = self.Base.Assets:GetAnimationCategory(categoryName, self.Base.Assets.BaseSource)
	if not animations or #animations == 0 then
		return nil
	end

	local animationName = animations[math.random(1, #animations)].Name
	if self.reactionAnimation and self.reactionAnimation ~= animationName then
		self.Base.Functions:CallFunction(FunctionEnum.StopAnimation, self.reactionAnimation, REACTION_FADE_TIME)
	end

	self.reactionAnimation = animationName
	return self.Base.Functions:CallFunction(FunctionEnum.PlayAnimation, animationName, REACTION_FADE_TIME, nil, false)
end

function Damage:IsStaggered(): boolean
	return self.Base.State:Is(STAGGER_STATE_KEY, StaggerStateEnum.Staggered)
end

function Damage:IsLaunched(): boolean
	return self.Base.State:Is(STAGGER_STATE_KEY, StaggerStateEnum.Launched)
end

function Damage:_updateHealthStatus()
	self.Base.State:Set(HEALTH_STATUS_KEY, self:_healthStatusFor(self.Humanoid.Health, self.Humanoid.MaxHealth))end

-- this safely changes the health prop without triggering an unregistered damage pickup
function Damage:DealSelfDamage(amount: number)
	self.pendingSelfChanges += 1
	local response = self.CharacterAPI:DealSelfHumanoidDamage(amount)
	-- a refused request changed nothing, so there is no change to wait for
	if not response.Success then
		self.pendingSelfChanges -= 1
	end

	return response
end

-- Gives back health the same way DealSelfDamage takes it. Whether it was given back.
function Damage:_restoreSelfHealth(amount: number): boolean
	self.pendingSelfChanges += 1
	local response = self.CharacterAPI:RestoreSelfHumanoidHealth(amount)
	if not response.Success then
		self.pendingSelfChanges -= 1
	end

	return response.Success
end

function Damage:IsProcessingDamage(): boolean
	return self.pendingSelfChanges > 0
end

function Damage:_onHealthChanged(newHealth: number)
	local previousHealth = self.lastHealth
	self.lastHealth = newHealth

	if self:IsProcessingDamage() then
		-- one of the changes we made ourselves has come in
		self.pendingSelfChanges -= 1
		return
	end

	if newHealth < previousHealth then
		self:ReceiveUnregistered(previousHealth - newHealth)
		return
	end

	warn("Humanoid health unexpectedly changed for character:", self.Character.Name, "New health:", newHealth)
end

function Damage:Destroy()
	self.backwardsToken = nil
	for _, subscription in ipairs(self.ConfigSubscriptions) do
		subscription.Unsubscribe()
	end
	self.ConfigSubscriptions = {}
	for _, subscription in ipairs(self.EventSubscriptions) do
		subscription.Unsubscribe()
	end
	self.EventSubscriptions = {}
	self.blockBreakToken = nil
	if self.blockBreakHighlight then
		self.blockBreakHighlight:Destroy()
	end
	if self.fadingBlockBreakHighlight then
		self.fadingBlockBreakHighlight:Destroy()
	end
	self.blockBreakHighlight = nil
	self.fadingBlockBreakHighlight = nil
	if self.healthChangedConnection then
		self.healthChangedConnection:Disconnect()
		self.healthChangedConnection = nil
	end
end

return Damage
