local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)
local CharacterDiscovery = require(script.Parent.CharacterDiscovery)
local CharacterUtility = require(script.Parent.CharacterUtility)
local Adapters = require(script.Adapters)
local Handle = require(script.Handle)

-- One record per character, made when discovery tracks it, and the read-only handle that goes with it. Whoever wants to read
-- a character gets that same handle (see TypeCharacterHandle): nothing is made on demand, so a character discovery never
-- tracked has no handle. Everything a handle reads that isn't a live Roblox property is written here and only here.
local CharacterHandles = {}

type Entry = TypeCharacterHandle.Entry
type ModuleResponse = TypeModuleResponse.ModuleResponse

local StatusCode = TypeRequests.Enums.StatusCode
local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

-- A removed character stays in here until it is destroyed: its handle keeps answering, and it picks up where it left off if
-- discovery tracks it again.
local entries: { [Model]: Entry } = {}

local function response(success: boolean, statusCode: number, message: string?, data: any?): ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

local function findEntry(character: Model): Entry?
	return entries[character]
end

-- The removal sequence, in one step. The character is still around at this point, so its team can be read one last time.
local function characterRemoved(character: Model)
	local entry = entries[character]
	if not entry or entry.Removed then
		return
	end

	entry.LastTeam = entry.Adapter.GetTeam(entry)
	table.clear(entry.Holds)
	entry.Removed = true
end

local function characterAdded(character: Model, characterType: string)
	local adapter = Adapters.select(character, characterType)

	local entry = entries[character]
	if entry then
		entry.Kind = characterType
		entry.Adapter = adapter
		entry.AdapterState = {}
		entry.Humanoid = nil
		entry.LastTeam = nil
		entry.Removed = false
		return
	end

	local newEntry: Entry = {
		Character = character,
		Kind = characterType,
		Adapter = adapter,
		Holds = {},
		Handle = nil :: any,
		Removed = false,
		LastTeam = nil,
		Humanoid = nil,
		AdapterState = {},
	}
	newEntry.Handle = Handle.new(newEntry, findEntry)
	entries[character] = newEntry

	character.Destroying:Once(function()
		-- Connection order isn't guaranteed, so this can come before discovery's removal
		characterRemoved(character)
		entries[character] = nil
	end)
end

local function isModel(character: any): boolean
	return typeof(character) == "Instance" and character:IsA("Model")
end

-- The handle of a character. Data is nil if discovery never tracked it, which isn't a failure: the character just isn't
-- anything we can read.
function CharacterHandles.getHandle(character: Model): ModuleResponse
	if not isModel(character) then
		return response(false, StatusCode.MalformedRequest, "Character must be a Model")
	end

	local entry = entries[character]
	if not entry then
		return response(true, StatusCode.Success, character.Name .. " is not tracked")
	end

	return response(true, StatusCode.Success, "Handle retrieved", entry.Handle)
end

-- The handles of a list of characters in one request. Data lines up with the list, with false where there is no handle
-- (a nil would leave a hole, which doesn't survive the trip back).
function CharacterHandles.getHandles(characters: { Model }): ModuleResponse
	if type(characters) ~= "table" then
		return response(false, StatusCode.MalformedRequest, "Characters must be a list of models")
	end

	local handles = {}
	for index, character in characters do
		local entry = if isModel(character) then entries[character] else nil
		handles[index] = if entry then entry.Handle else false
	end

	return response(true, StatusCode.Success, "Handles retrieved", handles)
end

local function validateHoldRequest(character: Model, reason: string): (Entry?, ModuleResponse?)
	if not isModel(character) then
		return nil, response(false, StatusCode.MalformedRequest, "Character must be a Model")
	end
	if type(reason) ~= "string" or reason == "" then
		return nil, response(false, StatusCode.MalformedRequest, "Reason must be a non-empty string")
	end

	local entry = entries[character]
	if not entry or entry.Removed then
		return nil, response(false, StatusCode.Conflict, character.Name .. " is not tracked")
	end

	return entry, nil
end

-- A character takes itself off the target list for a reason: it stays off until every reason it gave is released, so two
-- systems can't undo each other. Holds are its own to make, which is why there is no target to name. Data is whether this
-- changed anything, so a cleanup path can call it without checking first.
function CharacterHandles.holdUntargetable(character: Model, reason: string): ModuleResponse
	local entry, problem = validateHoldRequest(character, reason)
	if not entry then
		return problem :: ModuleResponse
	end

	local changed = entry.Holds[reason] == nil
	entry.Holds[reason] = true
	return response(true, StatusCode.Success, "Character is held off the target list", changed)
end

-- Gives up one reason. The character is back on the target list once it has none left. Data is whether this changed anything.
function CharacterHandles.releaseUntargetable(character: Model, reason: string): ModuleResponse
	local entry, problem = validateHoldRequest(character, reason)
	if not entry then
		return problem :: ModuleResponse
	end

	local changed = entry.Holds[reason] ~= nil
	entry.Holds[reason] = nil
	return response(true, StatusCode.Success, "Hold released", changed)
end

-- The team of a character, for other API modules. One discovery hasn't reached (or never will) has none yet.
function CharacterHandles._getTeam(character: Model): string
	local entry = entries[character]
	return if entry then Handle.readTeam(entry) else NEUTRAL_TEAM
end

-- What getCharacterType answers, from what discovery already decided instead of validating the whole ModNPC folder again.
-- Nil for anything that can't take part right now: dead, or missing its body. A ModNPC that was never started has nothing
-- behind its binds, so it counts as Generic until it is.
function CharacterHandles._getCharacterType(character: Model): string?
	local entry = entries[character]
	if not entry or entry.Removed then
		return CharacterUtility.getCharacterType(character).Data
	end

	local handle = entry.Handle
	if not handle:IsAlive() or not handle:GetRootPart() then
		return nil
	end

	if entry.Kind == CharacterUtility.Type.ModNPC and character:FindFirstChild("_UNLOADED") then
		return CharacterUtility.Type.Generic
	end

	return entry.Kind
end

function CharacterHandles.init(_)
	CharacterDiscovery._observe(characterAdded, characterRemoved)
	print("V1 CharacterHandles initialized")
end

return CharacterHandles
