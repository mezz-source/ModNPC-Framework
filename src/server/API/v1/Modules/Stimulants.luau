local ServerScriptService = game:GetService("ServerScriptService")
local CharacterDiscovery = require(script.Parent.CharacterDiscovery)
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

-- Routes stimulants from the character that causes them to the characters they are for. The API decides who hears a
-- stimulant, so a receiver only ever gets what concerns it. Receivers queue what they get and their thought process
-- consumes it later; this module only delivers, and remembers which stimulants are still true so it can tell their
-- receivers by id once one isn't (retract).
local Stimulants = {}

type ModuleResponse = TypeModuleResponse.ModuleResponse
type Recipient = TypeStimulant.Recipient
type StimulantSpec = TypeStimulant.StimulantSpec

-- One character that can be told about stimulants. Deliver is how it is told: a ModNPC's fires its CharacterStimulant
-- bind, an adapter for another NPC system would bring its own.
type Receiver = {
	Character: Model,
	Deliver: (messageType: TypeStimulant.MessageType, payload: any) -> (),
}

-- A stimulant that has been delivered and hasn't expired or been retracted yet
type ActiveStimulant = {
	Id: number,
	Emitter: Model?,
	Recipients: { Model },
	ExpiresAt: number,
}

local RecipientTypes = TypeStimulant.RecipientTypes
local MessageTypes = TypeStimulant.MessageTypes
local StatusCode = TypeRequests.Enums.StatusCode

local receivers: { [Model]: Receiver } = {}
local active: { [number]: ActiveStimulant } = {}
-- emitter -> the ids of its active stimulants, so its stimulants can be retracted once it is gone
local byEmitter: { [Model]: { [number]: true } } = {}
local nextId = 0

local function response(
	success: boolean,
	passResponse: boolean,
	statusCode: number?,
	message: string?,
	data: any?
): ModuleResponse
	return {
		Success = success,
		PassResponse = passResponse,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

-- The one place a discovered character becomes something stimulants can reach. Only ModNPCs for now; adapters for other
-- NPC systems slot in here.
local function buildReceiver(character: Model, characterType: string): Receiver?
	if characterType ~= CharacterUtility.Type.ModNPC then
		return nil
	end

	local bind = CharacterUtility._getStimulantBind(character)
	if not bind then
		return nil
	end

	return {
		Character = character,
		Deliver = function(messageType, payload)
			bind:Fire(messageType, payload)
		end,
	}
end

-- An unloaded NPC isn't thinking, so its mail would only pile up. Checked on delivery, as it can load or unload at any time.
local function isListening(receiver: Receiver): boolean
	return receiver.Character:FindFirstChild("_UNLOADED") == nil
end

local function forget(id: number)
	local record = active[id]
	if not record then
		return
	end

	active[id] = nil
	local emitter = record.Emitter
	local emitterIds = emitter and byEmitter[emitter]
	if emitter and emitterIds then
		emitterIds[id] = nil
		if next(emitterIds) == nil then
			byEmitter[emitter] = nil
		end
	end
end

-- Lazy: expired stimulants are only dropped when the module is next used, their receivers already know when they expire
local function pruneExpired(now: number)
	for id, record in active do
		if record.ExpiresAt <= now then
			forget(id)
		end
	end
end

-- Tells every receiver of a stimulant that is still around that it is no longer true, and forgets it
local function retractRecord(record: ActiveStimulant)
	for _, character in record.Recipients do
		local receiver = receivers[character]
		if receiver then
			receiver.Deliver(MessageTypes.Retract, record.Id)
		end
	end

	forget(record.Id)
end

local function validateRecipient(recipient: any): string?
	if type(recipient) ~= "table" or RecipientTypes[recipient.Type] == nil then
		return "Recipient must be a table with a Type of Individual, Group or All"
	end

	if recipient.Type == RecipientTypes.Individual then
		if typeof(recipient.Target) ~= "Instance" or not recipient.Target:IsA("Model") then
			return "An Individual recipient needs a Target model"
		end
	elseif recipient.Type == RecipientTypes.Group then
		if type(recipient.Targets) ~= "table" then
			return "A Group recipient needs a list of Targets"
		end
	end

	return nil
end

local function validateSpec(spec: any, now: number): string?
	if type(spec) ~= "table" then
		return "Stimulant spec must be a table"
	end

	if type(spec.Name) ~= "string" or spec.Name == "" then
		return "Stimulant needs a name"
	end

	if spec.Priority ~= nil and TypeStimulant.PriorityRank[spec.Priority] == nil then
		return "Unknown stimulant priority: " .. tostring(spec.Priority)
	end

	-- written this way round so NaN fails too
	if type(spec.ExpiresAt) ~= "number" or not (spec.ExpiresAt > now) then
		return "Stimulant ExpiresAt must be an os.clock() time in the future"
	end

	if spec.Position ~= nil and typeof(spec.Position) ~= "Vector3" then
		return "Stimulant Position must be a Vector3"
	end

	return nil
end

-- The receivers a recipient resolves to, never the emitter itself, each once
local function resolveRecipients(emitter: Model?, recipient: Recipient): { Receiver }
	local resolved = {}

	local function consider(character: any)
		if character == emitter then
			return
		end

		local receiver = receivers[character]
		if receiver and isListening(receiver) then
			table.insert(resolved, receiver)
		end
	end

	if recipient.Type == RecipientTypes.Individual then
		consider(recipient.Target)
	elseif recipient.Type == RecipientTypes.Group then
		local seen = {}
		for _, character in recipient.Targets :: { Model } do
			if not seen[character] then
				seen[character] = true
				consider(character)
			end
		end
	else
		for character in receivers do
			consider(character)
		end
	end

	return resolved
end

-- Sends a stimulant from emitter to whoever recipient resolves to. Data is an EmitResult: the stimulant's id (to retract it
-- by) and how many receivers it reached. A stimulant that reached no one is not remembered.
function Stimulants.emit(emitter: Model?, recipient: Recipient, spec: StimulantSpec): ModuleResponse
	local now = os.clock()
	pruneExpired(now)

	if emitter ~= nil and (typeof(emitter) ~= "Instance" or not emitter:IsA("Model")) then
		return response(false, true, StatusCode.Conflict, "Stimulant emitter must be a model")
	end

	local recipientError = validateRecipient(recipient)
	if recipientError then
		return response(false, true, StatusCode.Conflict, recipientError)
	end

	local specError = validateSpec(spec, now)
	if specError then
		return response(false, true, StatusCode.Conflict, specError)
	end

	nextId += 1
	local id = nextId
	local stimulant = CharacterUtility.createStimulant(id, emitter, spec)

	local delivered = {}
	for _, receiver in resolveRecipients(emitter, recipient) do
		receiver.Deliver(MessageTypes.Stimulant, stimulant)
		table.insert(delivered, receiver.Character)
	end

	if #delivered > 0 then
		active[id] = {
			Id = id,
			Emitter = emitter,
			Recipients = delivered,
			ExpiresAt = stimulant.ExpiresAt,
		}

		if emitter then
			local emitterIds = byEmitter[emitter]
			if not emitterIds then
				emitterIds = {}
				byEmitter[emitter] = emitterIds
			end
			emitterIds[id] = true
		end
	end

	return response(
		true,
		true,
		StatusCode.Success,
		"Stimulant delivered to " .. #delivered .. " receivers",
		{ Id = id, Delivered = #delivered } :: TypeStimulant.EmitResult
	)
end

-- Tells the receivers of a stimulant that it is no longer true (the attack was interrupted, the hit already resolved...).
-- Only its emitter may. Data is whether there was anything to retract: an unknown, expired or already retracted id is
-- still a success, so cleanup paths can call this without checking first.
function Stimulants.retract(emitter: Model?, id: number): ModuleResponse
	pruneExpired(os.clock())

	if type(id) ~= "number" then
		return response(false, true, StatusCode.Conflict, "Stimulant id must be a number")
	end

	local record = active[id]
	if not record then
		return response(true, true, StatusCode.Success, "Stimulant was already gone", false)
	end

	if record.Emitter ~= emitter then
		return response(false, true, StatusCode.Conflict, "Only a stimulant's emitter may retract it")
	end

	retractRecord(record)
	return response(true, true, StatusCode.Success, "Stimulant retracted", true)
end

local function characterAdded(character: Model, characterType: string)
	local receiver = buildReceiver(character, characterType)
	if receiver then
		receivers[character] = receiver
	end
end

local function characterRemoved(character: Model)
	receivers[character] = nil

	-- whatever it was about to do won't happen anymore
	local emitterIds = byEmitter[character]
	if emitterIds then
		for id in table.clone(emitterIds) do
			local record = active[id]
			if record then
				retractRecord(record)
			end
		end
		byEmitter[character] = nil
	end
end

function Stimulants.init(_)
	CharacterDiscovery._observe(characterAdded, characterRemoved)
	print("V1 Stimulants initialized")
end

return Stimulants
