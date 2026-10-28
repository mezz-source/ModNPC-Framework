local TypeTargetting = {}

export type TargettingContext = {
	Character: Model,
	Type: string,
	Team: string,
}

export type HealthInfo = {
	Health: number,
	MaxHealth: number,
	-- Health / MaxHealth, clamped to 0..1 (0 if MaxHealth is not positive)
	Fraction: number,
}

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
