local ServerScriptService = game:GetService("ServerScriptService")
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local Preferences = TypeTargetting.Preferences

type TargettingContext = TypeTargetting.TargettingContext

-- Each preference reads one number off a target, and says whether the lowest or highest wins.
-- A measure is given the selector, which holds the CharacterAPI and Distance to read from.
-- Measured fresh on every selection: distance depends on where we are, health changes over time.
local Measures: { [string]: { PreferLowest: boolean, Measure: (any, TargettingContext) -> number? } } = {
	[Preferences.ShortestDistance] = {
		PreferLowest = true,
		Measure = function(selector, target)
			return selector.Distance:GetDistanceTo(target.Character)
		end,
	},
	[Preferences.LongestDistance] = {
		PreferLowest = false,
		Measure = function(selector, target)
			return selector.Distance:GetDistanceTo(target.Character)
		end,
	},
	[Preferences.HighestHealth] = {
		PreferLowest = false,
		Measure = function(selector, target)
			return selector.CharacterAPI:GetHealth(target.Character)
		end,
	},
	[Preferences.LowestHealth] = {
		PreferLowest = true,
		Measure = function(selector, target)
			return selector.CharacterAPI:GetHealth(target.Character)
		end,
	},
	[Preferences.HighestMaxHealth] = {
		PreferLowest = false,
		Measure = function(selector, target)
			return selector.CharacterAPI:GetMaxHealth(target.Character)
		end,
	},
	[Preferences.LowestMaxHealth] = {
		PreferLowest = true,
		Measure = function(selector, target)
			return selector.CharacterAPI:GetMaxHealth(target.Character)
		end,
	},
}

local TargetSelector = {}
TargetSelector.__index = TargetSelector

function TargetSelector.new(base)
	local self = setmetatable({}, TargetSelector)
	self.CharacterAPI = base.CharacterAPI
	self.Distance = base.Distance
	return self
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

	local best: TargettingContext? = nil
	local bestValue: number? = nil

	for _, target in targets do
		local value = measure.Measure(self, target)
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
