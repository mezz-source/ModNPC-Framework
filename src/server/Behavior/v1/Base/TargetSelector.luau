local ServerScriptService = game:GetService("ServerScriptService")
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)

local Preferences = TypeTargetting.Preferences
local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

type TargettingContext = TypeTargetting.TargettingContext
type Reader = (TargettingContext) -> number?

-- Each preference reads one number off a target, and says whether the lowest or highest wins.
-- Prepare is given the selector (which holds the CharacterAPI and Distance to read from) and all the targets being
-- weighed, and answers with the reader for one target. That lets a preference gather what it needs for everyone at once,
-- as the distances do, instead of once per target.
-- Measured on every selection, not remembered between them: distance depends on where we are, health changes over time.
-- (Distance only reuses a reading made a few frames ago, which is how the search's own range filter feeds the selection.)
local Measures: { [string]: { PreferLowest: boolean, Prepare: (any, { TargettingContext }) -> Reader } } = {}

-- Distances come from the bulk measure, which is the same one the search used moments ago to filter by range
local function prepareDistance(selector: any, targets: { TargettingContext }): Reader
	local distances = selector.Distance:Measure(targets)
	return function(target)
		return distances[target.Character]
	end
end

-- A target comes with its handle when the search or Friends handed it out, and is asked for otherwise
local function prepareHandleRead(read: (any) -> number?, fallback: (any, Model) -> number?): (any, { TargettingContext }) -> Reader
	return function(selector)
		return function(target)
			if target.Handle then
				return read(target.Handle)
			end
			return fallback(selector.CharacterAPI, target.Character)
		end
	end
end

Measures[Preferences.ShortestDistance] = { PreferLowest = true, Prepare = prepareDistance }
Measures[Preferences.LongestDistance] = { PreferLowest = false, Prepare = prepareDistance }

local prepareHealth = prepareHandleRead(function(handle)
	return handle:GetHealth()
end, function(characterAPI, character)
	return characterAPI:GetHealth(character)
end)
Measures[Preferences.HighestHealth] = { PreferLowest = false, Prepare = prepareHealth }
Measures[Preferences.LowestHealth] = { PreferLowest = true, Prepare = prepareHealth }

local prepareMaxHealth = prepareHandleRead(function(handle)
	return handle:GetMaxHealth()
end, function(characterAPI, character)
	return characterAPI:GetMaxHealth(character)
end)
Measures[Preferences.HighestMaxHealth] = { PreferLowest = false, Prepare = prepareMaxHealth }
Measures[Preferences.LowestMaxHealth] = { PreferLowest = true, Prepare = prepareMaxHealth }

local TargetSelector = {}
TargetSelector.__index = TargetSelector

function TargetSelector.new(base)
	local self = setmetatable({}, TargetSelector)
	self.CharacterAPI = base.CharacterAPI
	self.Distance = base.Distance
	self.Functions = base.Functions
	return self
end

-- Claims a target we just focused for our team, so the first of a team to see it can be told apart from the ones who see it
-- after. True only if a teammate already holds it: we got there second.
--
-- Only bothers the API when a claim could mean something, cheapest checks first: we have to be on a team (Neutral has no
-- teammates), with at least one teammate around to hear us. Otherwise, or if the request fails, nobody holds it: false.
-- Reached through Functions (ClaimTarget), so mod scripts can hook or replace it.
function TargetSelector:ClaimTarget(target: Model): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return false
	end

	local team = self.CharacterAPI:GetTeam()
	if not team or team == NEUTRAL_TEAM then
		return false
	end

	local teammates = self.Functions:CallFunction(FunctionEnum.GetTeammates)
	if type(teammates) ~= "table" or #teammates == 0 then
		return false
	end

	-- One request both claims and says who beat us, so two teammates focusing at once can't both come away first
	local attempt = self.CharacterAPI:ClaimTarget(target)
	if not attempt or attempt.Claimed then
		return false
	end

	-- Held by us already (we focused it again before our own claim ran out) is not someone else's
	return attempt.Holder ~= nil and attempt.Holder ~= self.CharacterAPI.Character
end

function TargetSelector:IsValidPreference(preference: string?): boolean
	return preference ~= nil and Measures[preference] ~= nil
end

-- Picks the best target in the list for the preference, or nil if the list is empty,
-- the preference is unknown, or no target could be measured (e.g. all died mid-search).
-- Ties go to the earlier target in the list.
function TargetSelector:SelectBest(
	targets: { TargettingContext },
	preference: TypeTargetting.TargettingPreference
): TargettingContext?
	local measure = Measures[preference]
	if not measure then
		warn("TargetSelector: unknown targetting preference", preference)
		return nil
	end

	if #targets == 0 then
		return nil
	end

	local read = measure.Prepare(self, targets)
	local best: TargettingContext? = nil
	local bestValue: number? = nil

	for _, target in targets do
		local value = read(target)
		if value == nil then
			continue
		end

		if
			bestValue == nil
			or (measure.PreferLowest and value < bestValue)
			or (not measure.PreferLowest and value > bestValue)
		then
			best = target
			bestValue = value
		end
	end

	return best
end

return TargetSelector
