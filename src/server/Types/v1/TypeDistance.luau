local TypeDistance = {}

-- Where a distance sits against a range we want to hold: past it, inside it, or closer than it allows
export type RangeState = "TooFar" | "InRange" | "TooClose"

TypeDistance.RangeStates = table.freeze({
	TooFar = "TooFar",
	InRange = "InRange",
	TooClose = "TooClose",
})

return TypeDistance
