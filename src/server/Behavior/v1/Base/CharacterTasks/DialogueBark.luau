--[[
	Listens for what happens to the character and barks a line about it: a character event comes in, and a line category
	is said through Functions (SayLine), so priorities, cooldowns and chattiness all apply and mods can hook it.

	It takes up nothing (no resources) and runs alongside everything else for as long as the character lives. It is a start
	task (StartTasks/DialogueBark).

	To add a bark, add an entry to BARKS: the character event to listen for, and a function that turns its payload into the
	line category to say and its SayData (or nil to say nothing for this one).

		[TypeCharacterEvents.Names.Targetting.TargetSpotted] = function(_self, context)
			return "SpotEnemyIndividual", { RollChattiness = true }
		end,
]]

local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeDialogueFrame = require(ServerScriptService.ModNPCServer.Types.v1.TypeDialogueFrame)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local EventNames = TypeCharacterEvents.Names
local Specials = TypeDamage.Specials
local StimulantNames = TypeStimulant.Names

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies

type SayData = TypeDialogueFrame.SayData

local DialogueBarkTask = {}
DialogueBarkTask.__index = DialogueBarkTask
setmetatable(DialogueBarkTask, Task)

-- What payload of which event says which line. A handler returns the category and its SayData, or nil to stay quiet.
type BarkHandler = (self: any, payload: any) -> (string?, SayData?)

local BARKS: { [string]: BarkHandler } = {
	-- One of our hits landed and put a special on the target (AttackLanded is only for hits that weren't blocked or dodged)
	[EventNames.Combat.AttackLanded] = function(_self, outcome: TypeCharacterEvents.AttackOutcome)
		return if outcome.Special then "CombatDealCrit" else nil, nil
	end,

	-- We are being thrown
	[EventNames.Combat.Launched] = function()
		return "CombatLaunched", nil
	end,

	-- A hit took health off us and staggered us (a launch has its own line above)
	[EventNames.Combat.DamageTaken] = function(_self, taken: TypeCharacterEvents.DamageTaken)
		local staggered = taken.Special == Specials.Stagger or taken.Special == Specials.StaggerBackwards
		return if staggered then "CombatRecieveCrit" else nil, nil
	end,

	-- Our guard was broken: as bad as being staggered
	[EventNames.Combat.BlockBroken] = function()
		return "CombatRecieveCrit", nil
	end,

	-- A hit we dodged, or that a dodge took us out of the reach of (a blocked hit is a defense too, but not this one)
	[EventNames.Combat.DefenseSucceeded] = function(_self, defended: TypeCharacterEvents.DefenseSucceeded)
		return if defended.RecieveType == TypeDamage.RecieveTypes.Dodged then "CombatDodged" else nil, nil
	end,

	-- We got back up from a launch, rather than having it cut short
	[EventNames.Combat.LaunchEnded] = function(_self, ended: TypeCharacterEvents.LaunchEnded)
		return if ended.Recovered then "CombatRecover" else nil, nil
	end,

	-- Out of breath (the exhaustion is already applied when this is heard)
	[EventNames.Stamina.ExhaustionStarted] = function()
		return "StaminaExhausted", nil
	end,

	-- Got our breath back
	[EventNames.Stamina.ExhaustionEnded] = function()
		return "StaminaRecovered", nil
	end,

	-- Our last words. Exclusive, so they cut off anything else; a death is never on cooldown.
	[EventNames.Humanoid.Died] = function()
		return "Death", { IgnoreCooldown = true }
	end,

	-- Talking to ourselves on a stroll. Nonessential, so it rolls for chattiness.
	[EventNames.Wander.NewPosition] = function()
		return "Idle", { RollChattiness = true }
	end,

	-- Someone to fight
	[EventNames.Targetting.NewFocusTarget] = function()
		return "SpotEnemyIndividual", nil
	end,

	-- Someone died (the Died stimulant is broadcast to everyone). If it was the last target we focused, we won. Only read,
	-- never consumed, so whatever else reacts to deaths still sees it.
	[EventNames.Stimulant.Pending] = function(self, pending: { TypeStimulant.StimulantEvent })
		for _, stimulant in pending do
			if stimulant.Name == StimulantNames.Died and self:_isNewDeath(stimulant) then
				local fallen = stimulant.Source
				if fallen and fallen == self.lastFocus then
					self.lastFocus = nil
					return "CombatEndVictory", nil
				end
			end
		end

		return nil, nil
	end,
}

function DialogueBarkTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Dialogue,
		Resources = {},
		Dependencies = {
			Dependencies.Events,
			Dependencies.Functions,
		},
		Policy = TypeTask.Policy.Parallel,
		Essential = true,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, DialogueBarkTask)
	self.Events = base.Events
	self.Functions = base.Functions
	self.subscriptions = {} :: { any }
	-- The last character we focused. Kept after the focus is lost: a target that dies is dropped from our targets, quite
	-- possibly before its Died stimulant is read, and it should still count as ours.
	self.lastFocus = nil :: Model?
	-- Died stimulants already looked at, by id, until they expire: Pending offers them again on every reaction tick
	self.seenDeaths = {} :: { [number]: number }

	return self
end

-- Whether this Died stimulant hasn't been looked at before (and remembers it now). Forgets the ones that have expired.
function DialogueBarkTask:_isNewDeath(stimulant: TypeStimulant.StimulantEvent): boolean
	local now = os.clock()
	for id, expiresAt in self.seenDeaths do
		if expiresAt <= now then
			self.seenDeaths[id] = nil
		end
	end

	if self.seenDeaths[stimulant.Id] then
		return false
	end

	self.seenDeaths[stimulant.Id] = stimulant.ExpiresAt
	return true
end

-- Keeps lastFocus up to date
function DialogueBarkTask:_trackFocus()
	self:Listen(EventNames.Targetting.NewFocusTarget, function(context: TypeTargetting.TargettingContext)
		self.lastFocus = context.Character
	end)
	self:Listen(EventNames.Targetting.FocusedTargetChanged, function(change)
		self.lastFocus = change.Current.Character
	end)
end

-- Says a random line of the category (see Dialogue:SayLine). Returns whether it is playing.
function DialogueBarkTask:Bark(category: string, data: SayData?): boolean
	if not self:IsRunning() then
		return false
	end

	return self.Functions:CallFunction(FunctionEnum.SayLine, category, data) == true
end

-- Calls the handler on every dispatch of the event while the task runs; unsubscribed when it ends
function DialogueBarkTask:Listen(eventName: string, handler: (payload: any) -> ())
	table.insert(
		self.subscriptions,
		self.Events:Subscribe(eventName, function(payload)
			if self:IsRunning() then
				handler(payload)
			end
		end)
	)
end

function DialogueBarkTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- Before the barks, so a bark reading lastFocus on the same event already sees it
	self:_trackFocus()

	-- After any of our attacks: maybe some banter at the target (the Dialogue module rolls, speaks, and asks for the answer)
	self:Listen(EventNames.Combat.AttackEnded, function(ended: TypeCharacterEvents.AttackEnded)
		self.Functions:CallFunction(FunctionEnum.StartBanter, ended.Target)
	end)

	for eventName, handler in BARKS do
		self:Listen(eventName, function(payload)
			local category, data = handler(self, payload)
			if category then
				self:Bark(category, data)
			end
		end)
	end

	self.Terminated:Connect(function()
		for _, subscription in self.subscriptions do
			subscription.Unsubscribe()
		end
		table.clear(self.subscriptions)
		table.clear(self.seenDeaths)
		self.lastFocus = nil
	end)

	return true
end

-- Everything happens in the event handlers
function DialogueBarkTask:Update(_deltaTime: number) end

return DialogueBarkTask
