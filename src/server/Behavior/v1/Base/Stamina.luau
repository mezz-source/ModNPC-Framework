local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)

local RunService = game:GetService("RunService")

local Stamina = {}
Stamina.__index = Stamina

local CostSettings = TypeStamina.CostSettings
local Settings = TypeStamina.Settings
local StaminaEvents = TypeCharacterEvents.Names.Stamina
local StateEvents = TypeCharacterEvents.Names.State
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local StateKeys = TypeState.Keys
local ExhaustionStateEnum = TypeState.ExhaustionStateEnum
local FunctionEnum = TypeCharacterFunctions.FunctionEnum

-- What a setting of Config/Stamina is when the folder doesn't have it, or it isn't a usable number
local DEFAULT_MAX = 100
local DEFAULT_MULTIPLIER = 1
-- A character whose folder has no regeneration rate doesn't regenerate
local DEFAULT_REGENERATION_RATE = 0
-- A character whose folder has no exhaustion threshold is exhausted only when it has nothing left, and one with no recover
-- threshold recovers as soon as it has anything
local DEFAULT_EXHAUSTION_THRESHOLD = 0
local DEFAULT_RECOVER_THRESHOLD = 0
-- Seconds our target hears that we just became exhausted (an Exhausted stimulant)
local EXHAUSTED_STIMULANT_DURATION = 2

-- How many times faster the stamina comes back while the character is exhausted
local EXHAUSTED_REGENERATION_MULTIPLIER = 0.7

-- How well an exhausted character does things (see GetEfficiency): this much when it has no stamina left, rising with the
-- square of how full the stamina is, so a character that is exhausted but at 65% still manages about 0.7. A rested character
-- does everything at full efficiency.
local MIN_EXHAUSTED_EFFICIENCY = 0.5
local EFFICIENCY_CURVE = 2

-- Seconds per full flash of the bar while the character is exhausted
local EXHAUSTED_FLASH_PERIOD = 0.5

-- Seconds between the steps of the sprint drain and the regeneration. Rates are per second, so a step is worth its elapsed
-- time, and a rate of 5 comes as 1 stamina every 1/5 second.
local UPDATE_INTERVAL = 0.2

-- The states that change what stamina is doing: they are what _refresh is run for
local WATCHED_STATES = table.freeze({
	[StateKeys.AttackState] = true,
	[StateKeys.StaggerState] = true,
	[StateKeys.MoveState] = true,
})

-- Spending floats (a sprint is charged every tick) can leave a hair less than the price when it should be exactly enough
local EPSILON = 1e-6

-- A usable amount of stamina: a number that is not NaN, infinite or negative
local function isAmount(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

-- The character's stamina, and the vendor everything that costs it goes through. What something costs is in the character's
-- Config/Stamina (see TypeStamina), and the vendor decides whether the character can pay: a purchase it can afford comes off
-- the stamina and is accepted, one it can't is declined and costs nothing. So whoever wants to attack, dodge or sprint asks
-- here first, and does it only when the answer is yes.
--
-- Stamina does these on its own, from watching the character's states (see _refresh):
--   it drains while the character is sprinting (MoveState Sprinting), at the Sprint price per second
--   it regenerates, at Config/Stamina/RegenerationRate per second, while the character is not attacking, staggered or
--   sprinting
--   it sets the ExhaustionState to Exhausted when the stamina falls to the ExhaustionThreshold and back to None when it
--   is at the RecoverThreshold again, announcing both (ExhaustionStarted, ExhaustionEnded). While exhausted it
--   regenerates faster, the bar flashes, and a purchase that asks for rested stamina (requireRested) is declined, even if
--   there is enough.
-- Exhaustion also has consequences, but they are not applied here: GetEfficiency says how well the character does things
-- (1 when rested, 0.5 to 1 while exhausted) and it is up to every module that has something to scale (damage dealt, attack
-- speed, roll chances, ...) to ask for it and apply it.
-- Everything else that costs stamina is for callers to decide: they ask here first. It is shown on an overhead bar.
function Stamina.new(Base: any, character: Model)
	local self = setmetatable({}, Stamina)
	self.Base = Base
	self.Character = character
	self.Configuration = Base.Configuration
	self.CharacterAPI = Base.CharacterAPI

	self.Max = self:_readMax()
	-- A character starts out with all it has
	self.Current = self.Max

	self.Subscriptions = {}
	self.bar = nil :: TypeBars.Bar?
	self.alive = true
	-- Runs while there is something to drain or regenerate, and is off otherwise
	self.updateConnection = nil :: RBXScriptConnection?
	self.sinceUpdate = 0

	-- Owned here; State is built before the stamina, so it can be registered
	Base.State:Register(StateKeys.ExhaustionState, ExhaustionStateEnum)

	return self
end

-- Runs once the character is set up enough to put a bar on it and to hear about configuration and state changes
function Stamina:Init()
	table.insert(
		self.Subscriptions,
		self.Configuration:Observe({ TypeStamina.Folder, Settings.MaxStamina }, function()
			self:_onMaxChanged()
		end)
	)
	-- A rate that turns on (or off) while the character is idle starts (or stops) the regeneration, and a threshold that
	-- moves can put the stamina on the other side of it
	for _, setting in {
		Settings.RegenerationRate,
		Settings.RegenerationMultiplier,
		Settings.ExhaustionThreshold,
		Settings.RecoverThreshold,
	} do
		table.insert(
			self.Subscriptions,
			self.Configuration:Observe({ TypeStamina.Folder, setting }, function()
				self:_updateExhaustion()
				self:_refresh()
			end)
		)
	end

	local events = self.Base.Events
	table.insert(
		self.Subscriptions,
		events:Subscribe(StateEvents.Changed, function(change: TypeCharacterEvents.CharacterStateChanged)
			if WATCHED_STATES[change.Key] then
				-- A sprint that started on the last of the stamina (or while exhausted) doesn't get to go on
				self:_stopSprintingIfExhausted()
				self:_refresh()
			end
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(HumanoidEvents.Died, function()
			self.alive = false
			self:_refresh()
		end)
	)

	self:_createBar()
	self:_updateExhaustion()
	self:_refresh()
end

-- Whether the character is exhausted: out of breath until it has recovered (see _updateExhaustion)
function Stamina:IsExhausted(): boolean
	return self.Base.State:Is(StateKeys.ExhaustionState, ExhaustionStateEnum.Exhausted)
end

-- How efficient the character is: a multiplier from 0.5 to 1 for whatever it does. 1 unless it is exhausted; then it goes
-- from MIN_EXHAUSTED_EFFICIENCY with an empty stamina up with how full it is again (about 0.7 at 65%).
function Stamina:GetEfficiency(): number
	if not self:IsExhausted() then
		return 1
	end

	return MIN_EXHAUSTED_EFFICIENCY + (1 - MIN_EXHAUSTED_EFFICIENCY) * self:GetFraction() ^ EFFICIENCY_CURVE
end

-- An amount of stamina out of Config/Stamina, or the default when it isn't a usable number
function Stamina:_readAmount(setting: string, default: number): number
	local value = self.Configuration:Get({ TypeStamina.Folder, setting })

	return if isAmount(value) then value else default
end

-- Exhaustion begins when the stamina is at or below the ExhaustionThreshold and ends when it is at or above the
-- RecoverThreshold. In between nothing changes, so it takes more than a little stamina to get out of it. (With the two
-- thresholds equal that is a single step of regeneration.)
function Stamina:_updateExhaustion()
	if not self.Base then
		return
	end

	if self:IsExhausted() then
		if self.Current >= self:_readAmount(Settings.RecoverThreshold, DEFAULT_RECOVER_THRESHOLD) - EPSILON then
			self:_setExhausted(false)
		end
	elseif self.Current <= self:_readAmount(Settings.ExhaustionThreshold, DEFAULT_EXHAUSTION_THRESHOLD) + EPSILON then
		self:_setExhausted(true)
	end
end

function Stamina:_setExhausted(exhausted: boolean)
	self.Base.State:Set(
		StateKeys.ExhaustionState,
		if exhausted then ExhaustionStateEnum.Exhausted else ExhaustionStateEnum.None
	)
	self:_updateFlash()

	if exhausted then
		self:_stopSprintingIfExhausted()
		self:_announceExhaustion()
	end

	-- Last, so the listeners find the character in its new state, with the sprint already stopped
	self.Base.Events:Dispatch(if exhausted then StaminaEvents.ExhaustionStarted else StaminaEvents.ExhaustionEnded, {
		Current = self.Current,
		Max = self.Max,
		Efficiency = self:GetEfficiency(),
	} :: TypeCharacterEvents.StaminaExhaustion)
end

-- The bar flashes for as long as the character is exhausted
-- Lets the character we are fighting know we just ran out (an Exhausted stimulant). The target is the focus target of our
-- targetting task, the same one Attacks goes by; without one nobody is told.
function Stamina:_announceExhaustion()
	local targettingTask = self.Base.Scheduler:GetTask(TypeTask.CategoriesEnum.Targetting) :: any
	local focusTarget = if targettingTask then targettingTask.FocusTarget else nil
	local target = if focusTarget then focusTarget.Character else nil
	if not target then
		return
	end

	self.Base
		:NewStimulant(TypeStimulant.Names.Exhausted)
		:To(target)
		:Lasting(EXHAUSTED_STIMULANT_DURATION)
		:WithData({ Efficiency = self:GetEfficiency() } :: TypeStimulant.ExhaustedData)
		:Send()
end

function Stamina:_updateFlash()
	local bar = self.bar
	if not bar or bar:IsDestroyed() then
		return
	end

	if self:IsExhausted() then
		bar:StartFillFlash(TypeStamina.Bar.FlashColor, EXHAUSTED_FLASH_PERIOD)
	else
		bar:StopFillFlash()
	end
end

-- An exhausted character can't sprint. The Movement it is asked of is a behavior module, so it goes through Functions.
function Stamina:_stopSprintingIfExhausted()
	if self:IsExhausted() and self:_isSprinting() then
		self.Base.Functions:CallFunction(FunctionEnum.StopSprinting)
	end
end

function Stamina:_isSprinting(): boolean
	return self.Base.State:Is(StateKeys.MoveState, TypeState.MoveStateEnum.Sprinting)
end

-- Stamina comes back while the character is not swinging, not staggered (or launched) and not sprinting, and is alive. A
-- guard that is up does not stop it: a character can recover while it blocks.
function Stamina:CanRegenerate(): boolean
	if not self.alive then
		return false
	end

	local state = self.Base.State
	return not state:Is(StateKeys.AttackState, TypeState.AttackStateEnum.Swinging)
		and not state:Is(StateKeys.StaggerState, TypeState.StaggerStateEnum.Staggered)
		and not state:Is(StateKeys.StaggerState, TypeState.StaggerStateEnum.Launched)
		and not self:_isSprinting()
end

-- Stamina gained per second while regenerating: the RegenerationRate times the RegenerationMultiplier, and twice that
-- while the character is exhausted
function Stamina:_getRegenerationRate(): number
	local rate = self:_readAmount(Settings.RegenerationRate, DEFAULT_REGENERATION_RATE)
		* self:_readAmount(Settings.RegenerationMultiplier, DEFAULT_MULTIPLIER)

	return if self:IsExhausted() then rate * EXHAUSTED_REGENERATION_MULTIPLIER else rate
end

-- Whether there is anything to drain or regenerate right now
function Stamina:_hasWork(): boolean
	if not self.alive then
		return false
	end

	if self:_isSprinting() then
		return true
	end

	return self.Current < self.Max and self:CanRegenerate() and self:_getRegenerationRate() > 0
end

-- Starts the update loop when there is work and stops it when there isn't, so a character at full stamina that isn't
-- sprinting costs nothing. Runs on every state change that matters and every change of the stamina.
function Stamina:_refresh()
	if not self.Base then
		return
	end

	local shouldRun = self:_hasWork()
	if shouldRun and not self.updateConnection then
		self.sinceUpdate = 0
		self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
			self:_onHeartbeat(deltaTime)
		end)
	elseif not shouldRun and self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
end

function Stamina:_onHeartbeat(deltaTime: number)
	self.sinceUpdate += deltaTime
	if self.sinceUpdate < UPDATE_INTERVAL then
		return
	end

	local elapsed = self.sinceUpdate
	self.sinceUpdate = 0
	self:_update(elapsed)
end

-- One step of the loop, worth `elapsed` seconds. Sprinting takes its price for those seconds (what is left, if it is
-- less: a sprint can empty the stamina but not overdraw it), otherwise it regenerates.
function Stamina:_update(elapsed: number)
	if self:_isSprinting() then
		local price = self:GetCost(TypeStamina.Costs.Sprint) :: number
		self:Spend(math.min(price * elapsed, self.Current), "SprintDrain")
	elseif self:CanRegenerate() then
		self:Restore(self:_getRegenerationRate() * elapsed, "Regeneration")
	end

	-- The step may have filled the stamina, or emptied what the sprint was paying for
	self:_refresh()
end

-- Shows the stamina above the character's head. A failure (no head, no bar template) is warned about by the API and leaves
-- the character without a bar, which changes nothing else.
function Stamina:_createBar()
	local barSettings = TypeStamina.Bar
	local bar = self.CharacterAPI:CreateBar(barSettings.Name, {
		Fill = self:GetFraction(),
		FillColor = barSettings.FillColor,
		ChangeFillColor = barSettings.ChangeFillColor,
		Size = barSettings.Size,
		LayoutOrder = barSettings.LayoutOrder,
	})

	self.bar = bar
	self:_updateFlash()
end

-- The most stamina the character can have: its MaxStamina setting
function Stamina:_readMax(): number
	local value = self.Configuration:Get({ TypeStamina.Folder, Settings.MaxStamina })

	return if isAmount(value) then value else DEFAULT_MAX
end

function Stamina:_readMultiplier(): number
	local value = self.Configuration:Get({ TypeStamina.Folder, Settings.ConsumptionMultiplier })

	return if isAmount(value) then value else DEFAULT_MULTIPLIER
end

-- Puts the bar and the listeners right with a stamina or maximum that changed
function Stamina:_announce(previous: number, previousMax: number, reason: string?)
	if self.Current == previous and self.Max == previousMax then
		return
	end

	local bar = self.bar
	if bar and not bar:IsDestroyed() then
		bar:SetFill(self:GetFraction())
	end

	-- Before the listeners hear about it, so they see the exhaustion that came with this change
	self:_updateExhaustion()

	self.Base.Events:Dispatch(StaminaEvents.Changed, {
		Previous = previous,
		Current = self.Current,
		Max = self.Max,
		Reason = reason,
	} :: TypeCharacterEvents.StaminaChanged)

	-- Spending starts the regeneration and filling the stamina ends it
	self:_refresh()
end

-- A lowered maximum takes the stamina down with it, a raised one leaves it where it was (the character isn't refilled by it)
function Stamina:_onMaxChanged()
	local previous, previousMax = self.Current, self.Max

	self.Max = self:_readMax()
	self.Current = math.min(self.Current, self.Max)
	self:_announce(previous, previousMax, "MaxChanged")
end

-- How much stamina the character has and the most it can have
function Stamina:GetStamina(): (number, number)
	return self.Current, self.Max
end

-- How full the stamina is, from 0 to 1. A character that can have none counts as empty.
function Stamina:GetFraction(): number
	if self.Max <= 0 then
		return 0
	end

	return math.clamp(self.Current / self.Max, 0, 1)
end

-- What the cost comes to for this character: its price in Config/Stamina times the ConsumptionMultiplier. A cost the
-- configuration has no price for is free. Nil for something that isn't a cost at all.
function Stamina:GetCost(cost: TypeStamina.Cost): number?
	local settingName = CostSettings[cost]
	if not settingName then
		return nil
	end

	local price = self.Configuration:Get({ TypeStamina.Folder, settingName })
	if not isAmount(price) then
		price = 0
	end

	return (price :: number) * self:_readMultiplier()
end

-- Whether the character could pay for the cost right now. If it couldn't, why. With `requireRested` a character that is
-- exhausted can't, whatever it has.
function Stamina:CanAfford(cost: TypeStamina.Cost, requireRested: boolean?): (boolean, string?)
	local amount = self:GetCost(cost)
	if not amount then
		return false, "Unknown stamina cost: " .. tostring(cost)
	end

	if requireRested and self:IsExhausted() then
		return false, "Too exhausted for " .. cost
	end

	if amount > self.Current + EPSILON then
		return false, string.format("Not enough stamina for %s (have %.1f, need %.1f)", cost, self.Current, amount)
	end

	return true
end

-- Takes an amount of stamina, as it is (the ConsumptionMultiplier is part of what GetCost says, not of this). Accepted and
-- taken if the character has that much, declined with the reason and nothing taken if it doesn't. With `requireRested` it
-- is declined too if the character is exhausted, even if it has that much.
function Stamina:Spend(amount: number, reason: string?, requireRested: boolean?): (boolean, string?)
	if not isAmount(amount) then
		return false, "Invalid amount of stamina: " .. tostring(amount)
	end

	if requireRested and self:IsExhausted() then
		return false, "Too exhausted to spend stamina"
	end

	if amount > self.Current + EPSILON then
		return false, string.format("Not enough stamina (have %.1f, need %.1f)", self.Current, amount)
	end

	local previous = self.Current
	self.Current = math.max(self.Current - amount, 0)
	self:_announce(previous, self.Max, reason or "Spend")

	return true
end

-- The vendor's main door: buys one of the costs, at its price for this character. Accepted if the character can pay it, in
-- which case it is paid, declined (with why) if it can't. `requireRested` declines it for a character that is exhausted.
function Stamina:Purchase(cost: TypeStamina.Cost, requireRested: boolean?): (boolean, string?)
	local affordable, declinedReason = self:CanAfford(cost, requireRested)
	if not affordable then
		return false, declinedReason
	end

	return self:Spend(self:GetCost(cost) :: number, cost, requireRested)
end

-- Gives stamina back, up to the maximum, whether or not the character is allowed to regenerate (that is only for the
-- regeneration on its own). The regeneration is this with the reason "Regeneration".
function Stamina:Restore(amount: number, reason: string?): (boolean, string?)
	if not isAmount(amount) then
		return false, "Invalid amount of stamina: " .. tostring(amount)
	end

	local previous = self.Current
	self.Current = math.min(self.Current + amount, self.Max)
	self:_announce(previous, self.Max, reason or "Restore")

	return true
end

-- Breaks the character's stamina: it drops to the ExhaustionThreshold at once, which exhausts it. For whatever wears a
-- character out in one go. A character that is at or below the threshold already keeps what it has (it is not topped up to
-- it), and is exhausted all the same.
function Stamina:Break(reason: string?): (boolean, string?)
	local threshold = math.min(self:_readAmount(Settings.ExhaustionThreshold, DEFAULT_EXHAUSTION_THRESHOLD), self.Max)

	local previous = self.Current
	self.Current = math.min(self.Current, threshold)
	self:_announce(previous, self.Max, reason or "Break")
	-- _announce only looks at the exhaustion when something changed, and a character already at the threshold is not changed
	self:_updateExhaustion()

	return true
end

function Stamina:Destroy()
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	for _, subscription in ipairs(self.Subscriptions) do
		subscription.Unsubscribe()
	end
	self.Subscriptions = {}

	local bar = self.bar
	self.bar = nil
	if bar and not bar:IsDestroyed() then
		bar:Destroy()
	end

	self.Configuration = nil
	self.CharacterAPI = nil
	self.Base = nil
end

return Stamina
