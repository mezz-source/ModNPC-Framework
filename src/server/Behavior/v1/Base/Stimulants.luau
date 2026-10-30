local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

-- The stimulants this character has been told about and not yet dealt with. The API decides who hears a stimulant and
-- delivers it over the CharacterStimulant bind (CharacterAPI hands it to ReceiveStimulant); nothing reacts as it arrives.
-- Every reaction tick of the thought process the queue is pruned, and whatever is left goes out as StimulantsPending for
-- the character to decide what to do with. Whoever acts on one consumes it; the rest expire quietly in the background.
-- A behavior module: others reach it through Functions (ReceiveStimulant, DropStimulant, GetStimulants, PeekStimulant,
-- ConsumeStimulant).
local Stimulants = {}
Stimulants.__index = Stimulants

type StimulantEvent = TypeStimulant.StimulantEvent

local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local ThoughtEvents = TypeCharacterEvents.Names.Thought
local StimulantEvents = TypeCharacterEvents.Names.Stimulant
local PriorityRank = TypeStimulant.PriorityRank

-- Most stimulants a character keeps at once. Past it the least urgent one makes room.
local MAX_QUEUED = 32
-- Stands in for a stimulant without a source in the dedupe index
local NO_SOURCE = newproxy(false)

-- Higher priority first, then the one running out soonest
local function isMoreUrgent(a: StimulantEvent, b: StimulantEvent): boolean
	local rankA, rankB = PriorityRank[a.Priority], PriorityRank[b.Priority]
	if rankA ~= rankB then
		return rankA > rankB
	end
	return a.ExpiresAt < b.ExpiresAt
end

local function isWellFormed(stimulant: any): boolean
	return type(stimulant) == "table"
		and type(stimulant.Id) == "number"
		and type(stimulant.Name) == "string"
		and type(stimulant.ExpiresAt) == "number"
		and PriorityRank[stimulant.Priority] ~= nil
end

function Stimulants.new(Base, Character)
	local self = setmetatable({}, Stimulants)
	self.Base = Base
	self.Character = Character
	-- id -> stimulant
	self.Queue = {} :: { [number]: StimulantEvent }
	-- source -> name -> id. The same source saying the same thing again refreshes what we have instead of piling up.
	self.BySource = {} :: { [any]: { [string]: number } }
	self.Count = 0
	self.Subscriptions = {}

	return self
end

-- Runs once Events exist, which every module is built after
function Stimulants:Init()
	local events = self.Base.Events

	table.insert(
		self.Subscriptions,
		events:Subscribe(ThoughtEvents.ReactionUpdate, function()
			self:_think()
		end)
	)
	table.insert(
		self.Subscriptions,
		events:Subscribe(HumanoidEvents.Died, function()
			self:Clear()
		end)
	)
end

function Stimulants:_remove(id: number): StimulantEvent?
	local stimulant = self.Queue[id]
	if not stimulant then
		return nil
	end

	self.Queue[id] = nil
	self.Count -= 1

	local sourceKey = stimulant.Source or NO_SOURCE
	local names = self.BySource[sourceKey]
	if names and names[stimulant.Name] == id then
		names[stimulant.Name] = nil
		if next(names) == nil then
			self.BySource[sourceKey] = nil
		end
	end

	return stimulant
end

-- Lazy: only ever done when the queue is read, never on its own clock
function Stimulants:_prune()
	local now = os.clock()
	for id, stimulant in self.Queue do
		if stimulant.ExpiresAt <= now then
			self:_remove(id)
		end
	end
end

-- Makes room for one more by dropping the least urgent stimulant
function Stimulants:_evictOne()
	local leastUrgent: StimulantEvent? = nil
	for _, stimulant in self.Queue do
		if not leastUrgent or isMoreUrgent(leastUrgent, stimulant) then
			leastUrgent = stimulant
		end
	end

	if leastUrgent then
		self:_remove(leastUrgent.Id)
	end
end

-- Takes in a stimulant the API delivered. Returns whether it was queued: one that is malformed, already expired, or
-- arrives after death is not.
function Stimulants:Receive(stimulant: StimulantEvent): boolean
	if not self.Base:IsAlive() or not isWellFormed(stimulant) then
		return false
	end

	if stimulant.ExpiresAt <= os.clock() then
		return false
	end

	local sourceKey = stimulant.Source or NO_SOURCE
	local names = self.BySource[sourceKey]
	local previousId = names and names[stimulant.Name]
	if previousId then
		self:_remove(previousId)
	end

	if self.Count >= MAX_QUEUED then
		self:_prune()
		if self.Count >= MAX_QUEUED then
			self:_evictOne()
		end
	end

	self.Queue[stimulant.Id] = stimulant
	self.Count += 1

	names = self.BySource[sourceKey]
	if not names then
		names = {}
		self.BySource[sourceKey] = names
	end
	names[stimulant.Name] = stimulant.Id

	return true
end

-- Forgets a stimulant without acting on it: the API retracted it, or the character decided it doesn't care.
-- Returns whether it was still queued.
function Stimulants:Drop(id: number): boolean
	return self:_remove(id) ~= nil
end

-- What is still queued, optionally only of one name, most urgent first. A copy, so it can be iterated while consuming.
function Stimulants:GetStimulants(name: string?): { StimulantEvent }
	self:_prune()

	local list = {}
	for _, stimulant in self.Queue do
		if name == nil or stimulant.Name == name then
			table.insert(list, stimulant)
		end
	end

	table.sort(list, isMoreUrgent)
	return list
end

-- The most urgent stimulant still queued, optionally only of one name. Stays queued until consumed.
function Stimulants:Peek(name: string?): StimulantEvent?
	self:_prune()

	local mostUrgent: StimulantEvent? = nil
	for _, stimulant in self.Queue do
		if (name == nil or stimulant.Name == name) and (not mostUrgent or isMoreUrgent(stimulant, mostUrgent)) then
			mostUrgent = stimulant
		end
	end

	return mostUrgent
end

-- Takes a stimulant off the queue because the character is acting on it. Returns it, or nil if it already expired or was
-- retracted (so whoever reacts finds out the stimulant is no longer true).
function Stimulants:Consume(id: number): StimulantEvent?
	self:_prune()
	return self:_remove(id)
end

function Stimulants:Clear()
	self.Queue = {}
	self.BySource = {}
	self.Count = 0
end

-- One reaction tick: what is left after pruning goes out for the character to decide on
function Stimulants:_think()
	if self.Count == 0 then
		return
	end

	local pending = self:GetStimulants()
	if #pending == 0 then
		return
	end

	self.Base.Events:Dispatch(StimulantEvents.Pending, pending)
end

function Stimulants:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end
	self.Subscriptions = {}
	self:Clear()
	self.Base = nil
end

return Stimulants
