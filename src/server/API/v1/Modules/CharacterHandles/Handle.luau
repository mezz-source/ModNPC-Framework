local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)

type CharacterHandle = TypeCharacterHandle.CharacterHandle
type Entry = TypeCharacterHandle.Entry
type HealthInfo = TypeCharacterHandle.HealthInfo
type Other = TypeCharacterHandle.Other

local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

local HandleClass = {}

-- The humanoid is looked up once and kept, a character doesn't swap it often and these are read many times a frame
local function getHumanoid(entry: Entry): Humanoid?
	local humanoid = entry.Humanoid
	if humanoid and humanoid.Parent == entry.Character then
		return humanoid
	end

	humanoid = CharacterUtility._getHumanoid(entry.Character)
	entry.Humanoid = humanoid
	return humanoid
end

local function getPosition(entry: Entry): Vector3?
	local rootPart = CharacterUtility._getRootPart(entry.Character)
	return if rootPart then rootPart.Position else nil
end

-- Where something a handle was compared to is, whichever form it came in
local function getOtherPosition(other: any): Vector3?
	if typeof(other) == "Instance" then
		local rootPart = CharacterUtility._getRootPart(other :: Model)
		return if rootPart then rootPart.Position else nil
	end

	if type(other) == "table" and type(other.GetPosition) == "function" then
		return other:GetPosition()
	end

	return nil
end

-- The character behind something a handle was compared to, whichever form it came in
local function getOtherModel(other: any): Model?
	if typeof(other) == "Instance" then
		return other :: Model
	end

	if type(other) == "table" and type(other.GetModel) == "function" then
		return other:GetModel()
	end

	return nil
end

function HandleClass.readTeam(entry: Entry): string
	if entry.Removed then
		return entry.LastTeam or NEUTRAL_TEAM
	end

	return entry.Adapter.GetTeam(entry)
end

-- Who a character stands with. Both sides have to be tracked and they can't be the same character.
local function getRelation(entry: Entry, other: Entry?): boolean?
	if not other or other == entry or entry.Removed or other.Removed then
		return nil
	end

	local team = HandleClass.readTeam(entry)
	return team ~= NEUTRAL_TEAM and team == HandleClass.readTeam(other)
end

-- Builds the handle of an entry. A table of closures, as it crosses the API's bindable: tables are copied and lose their
-- metatable there, but every copy's closures keep reading this entry. findEntry looks up the entry of another character.
function HandleClass.new(entry: Entry, findEntry: (Model) -> Entry?): CharacterHandle
	local function relationTo(other: Other): boolean?
		local model = getOtherModel(other)
		return getRelation(entry, if model then findEntry(model) else nil)
	end

	return {
		GetModel = function(_self: CharacterHandle): Model
			return entry.Character
		end,

		IsValid = function(_self: CharacterHandle): boolean
			return not entry.Removed
		end,

		IsAlive = function(_self: CharacterHandle): boolean
			local humanoid = getHumanoid(entry)
			return not entry.Removed and humanoid ~= nil and humanoid.Health > 0
		end,

		GetRootPart = function(_self: CharacterHandle): BasePart?
			return CharacterUtility._getRootPart(entry.Character)
		end,

		GetPosition = function(_self: CharacterHandle): Vector3?
			return getPosition(entry)
		end,

		GetDistanceTo = function(_self: CharacterHandle, other: Other): number?
			local here = getPosition(entry)
			local there = getOtherPosition(other)
			return if here and there then (here - there).Magnitude else nil
		end,

		GetHealth = function(_self: CharacterHandle): number?
			local humanoid = getHumanoid(entry)
			return if humanoid then humanoid.Health else nil
		end,

		GetMaxHealth = function(_self: CharacterHandle): number?
			local humanoid = getHumanoid(entry)
			return if humanoid then humanoid.MaxHealth else nil
		end,

		GetHealthInfo = function(_self: CharacterHandle): HealthInfo?
			local humanoid = getHumanoid(entry)
			if not humanoid then
				return nil
			end

			local health, maxHealth = humanoid.Health, humanoid.MaxHealth
			return {
				Health = health,
				MaxHealth = maxHealth,
				Fraction = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0,
			}
		end,

		GetTeam = function(_self: CharacterHandle): string
			return HandleClass.readTeam(entry)
		end,

		IsAlly = function(_self: CharacterHandle, other: Other): boolean
			return relationTo(other) == true
		end,

		IsHostile = function(_self: CharacterHandle, other: Other): boolean
			return relationTo(other) == false
		end,

		IsTargetable = function(_self: CharacterHandle): boolean
			return next(entry.Holds) == nil
		end,

		IsStaggered = function(_self: CharacterHandle): boolean
			return not entry.Removed and entry.Adapter.Ask(entry, "IsStaggered")
		end,

		IsExhausted = function(_self: CharacterHandle): boolean
			return not entry.Removed and entry.Adapter.Ask(entry, "IsExhausted")
		end,
	}
end

return HandleClass
