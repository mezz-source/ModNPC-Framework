local ServerScriptService = game:GetService("ServerScriptService")
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

-- Describes a stimulant one step at a time, then sends it from the character it was made for:
--
--   base:NewStimulant("IncomingAttack")
--       :To(target)
--       :WithPriority("High")
--       :Lasting(0.6)
--       :Send()
--
-- A name, a recipient (To / ToGroup / ToAll) and how long it stays true (Lasting / ExpiringAt) are required; priority
-- is Normal when left out. Send forgets about it once it is gone; Emit waits for the id, for a stimulant that may have to
-- be retracted (CharacterAPI:RetractStimulant). Build only gives the stimulant, for whoever wants to send it themselves.
-- The builder itself never crosses the API, only the plain stimulant Build makes does.
local StimulantBuilder = {}
StimulantBuilder.__index = StimulantBuilder

type StimulantBuilder = TypeStimulant.StimulantBuilder
type OutgoingStimulant = TypeStimulant.OutgoingStimulant

local RecipientTypes = TypeStimulant.RecipientTypes

-- sender is the CharacterAPI Send and Emit go through (base:NewStimulant passes its own). Without one, only Build works.
function StimulantBuilder.new(name: string, sender: TypeStimulant.StimulantSender?): StimulantBuilder
	local self = setmetatable({}, StimulantBuilder)
	self._sender = sender
	self._name = name
	self._recipient = nil :: TypeStimulant.Recipient?
	self._priority = nil :: TypeStimulant.Priority?
	-- One of the two, whichever was set last. A duration is turned into a time on Build, so a builder kept around
	-- and built later still lasts as long as it says.
	self._lasting = nil :: number?
	self._expiresAt = nil :: number?
	self._position = nil :: Vector3?
	self._data = nil :: any

	return (self :: any) :: StimulantBuilder
end

-- For one character
function StimulantBuilder:To(target: Model): StimulantBuilder
	self._recipient = { Type = RecipientTypes.Individual, Target = target }
	return self
end

-- For each of these characters
function StimulantBuilder:ToGroup(targets: { Model }): StimulantBuilder
	self._recipient = { Type = RecipientTypes.Group, Targets = table.clone(targets) }
	return self
end

-- For every character that can hear stimulants (never the one sending it)
function StimulantBuilder:ToAll(): StimulantBuilder
	self._recipient = { Type = RecipientTypes.All }
	return self
end

function StimulantBuilder:WithPriority(priority: TypeStimulant.Priority): StimulantBuilder
	self._priority = priority
	return self
end

-- Stays true for this many seconds from when it is built
function StimulantBuilder:Lasting(seconds: number): StimulantBuilder
	self._lasting = seconds
	self._expiresAt = nil
	return self
end

-- Stays true until this os.clock() time
function StimulantBuilder:ExpiringAt(expiresAt: number): StimulantBuilder
	self._expiresAt = expiresAt
	self._lasting = nil
	return self
end

-- Where it happened
function StimulantBuilder:At(position: Vector3): StimulantBuilder
	self._position = position
	return self
end

-- Anything else the receiver should know. Crosses a bindable, so keep it to plain data and instances.
function StimulantBuilder:WithData(data: any): StimulantBuilder
	self._data = data
	return self
end

-- The stimulant, or nil and why it can't be one yet. The API checks it again when it is sent.
function StimulantBuilder:Build(): (OutgoingStimulant?, string?)
	if type(self._name) ~= "string" or self._name == "" then
		return nil, "Stimulant needs a name"
	end

	if not self._recipient then
		return nil, "Stimulant " .. self._name .. " has no recipient (To, ToGroup or ToAll)"
	end

	if self._priority ~= nil and TypeStimulant.PriorityRank[self._priority] == nil then
		return nil, "Stimulant " .. self._name .. " has an unknown priority: " .. tostring(self._priority)
	end

	local expiresAt = self._expiresAt
	if self._lasting then
		-- written this way round so NaN fails too
		if not (self._lasting > 0) then
			return nil, "Stimulant " .. self._name .. " must last more than 0 seconds"
		end
		expiresAt = os.clock() + self._lasting
	end

	if not expiresAt then
		return nil, "Stimulant " .. self._name .. " never says when it stops being true (Lasting or ExpiringAt)"
	end

	return {
		Recipient = self._recipient,
		Name = self._name,
		Priority = self._priority,
		ExpiresAt = expiresAt,
		Position = self._position,
		Data = self._data,
	}, nil
end

-- Builds the stimulant and sends it, without waiting for the API. Whether it was built and sent (the API may still refuse
-- it, which it only warns about), and why not.
function StimulantBuilder:Send(): (boolean, string?)
	local sender = self._sender
	if not sender then
		return false, "Stimulant " .. tostring(self._name) .. " has no character to send it (use base:NewStimulant)"
	end

	local stimulant, buildError = self:Build()
	if not stimulant then
		return false, buildError
	end

	sender:SendStimulant(stimulant)
	return true, nil
end

-- Builds the stimulant and sends it, waiting for the API: the id to retract it by and how many received it, or nil and why
function StimulantBuilder:Emit(): (TypeStimulant.EmitResult?, string?)
	local sender = self._sender
	if not sender then
		return nil, "Stimulant " .. tostring(self._name) .. " has no character to send it (use base:NewStimulant)"
	end

	local stimulant, buildError = self:Build()
	if not stimulant then
		return nil, buildError
	end

	local result = sender:EmitStimulant(stimulant)
	if not result then
		return nil, "The API refused stimulant " .. stimulant.Name
	end
	return result, nil
end

return StimulantBuilder
