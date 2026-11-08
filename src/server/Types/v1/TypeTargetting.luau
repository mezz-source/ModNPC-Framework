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

-- Everyone the API tracks right now, each with its handle (whoever has none is left out). One of these is shared by every
-- character in the world and frozen, so nothing in it can be changed by whoever is reading: copy what you need to keep.
export type TargetSnapshot = {
	-- os.clock() when the list was taken
	Taken: number,
	Targets: { TargettingContext },
}

export type HealthInfo = TypeCharacterHandle.HealthInfo

-- A short lived claim on a target, one per team: the first of a team to claim a target holds it until it is released or
-- runs out. Data of Targetting.getTargetClaim
export type TargetClaim = {
	-- Who on the asker's team holds the target, nil if nobody (can be the asker itself)
	Holder: Model?,
}

-- Data of Targetting.claimTarget
export type TargetClaimAttempt = {
	-- True if this call took the claim
	Claimed: boolean,
	-- Who holds the target now: the claimer if Claimed, otherwise whoever got there first (can be the claimer itself if it
	-- already held it)
	Holder: Model?,
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
