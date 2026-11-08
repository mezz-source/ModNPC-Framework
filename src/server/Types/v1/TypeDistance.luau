local TypeCharacterHandle = require(script.Parent.TypeCharacterHandle)

local TypeDistance = {}

-- Anything the bulk measures can take: a TargettingContext, a FriendContext, or just { Character = model }. When it carries
-- a Handle that is what gets read; without one the handle is looked up, all the missing ones in a single request.
export type Measurable = {
	Character: Model,
	Handle: TypeCharacterHandle.CharacterHandle?,
}

-- Studs from us, keyed by character. A character that couldn't be measured is left out.
export type Distances = { [Model]: number }

-- Where a distance sits against a range we want to hold: past it, inside it, or closer than it allows
export type RangeState = "TooFar" | "InRange" | "TooClose"

TypeDistance.RangeStates = table.freeze({
	TooFar = "TooFar",
	InRange = "InRange",
	TooClose = "TooClose",
})

return TypeDistance
