local TypeCharacterHandle = require(script.Parent.TypeCharacterHandle)

local TypeTargetting = {}

export type TargettingContext = {
	Character: Model,
	Type: string,
	-- As of the read that made this context. The handle always has the current one.
	Team: string,
	-- Read the target through this. Set on the contexts the search and Friends hand out, not on what the API returns.
	Handle: TypeCharacterHandle.CharacterHandle?,
}

export type HealthInfo = TypeCharacterHandle.HealthInfo

export type TargettingPreference = 
"ShortestDistance" |
"LongestDistance" |
"HighestHealth" |
"LowestHealth" |
"HighestMaxHealth" |
"LowestMaxHealth"

-- Which engage distance (Ranges.CloseEngage / Ranges.LongEngage) a character tries to hold from its focus target
export type TargettingRange = "Close" | "Long"

export type FilterType = "Include" | "Exclude"

TypeTargetting.Ranges = table.freeze({
	Close = "Close",
	Long = "Long",
})

TypeTargetting.Preferences = table.freeze({
	ShortestDistance = "ShortestDistance",
	LongestDistance = "LongestDistance",
	HighestHealth = "HighestHealth",
	LowestHealth = "LowestHealth",
	HighestMaxHealth = "HighestMaxHealth",
	LowestMaxHealth = "LowestMaxHealth",
})

TypeTargetting.FilterTypes = table.freeze({
	Include = "Include",
	Exclude = "Exclude",
})

return TypeTargetting
