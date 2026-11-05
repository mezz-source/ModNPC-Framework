local TypeCharacterHandle = {}

-- A read-only view of one character, minted by the API when it tracks that character. It answers questions and nothing
-- else: every change goes through an API request. Whoever holds one never needs to know what kind of character is behind it,
-- and never has to guard a call: no method throws, and each one answers with its default when it can't answer.
--
-- Crosses the API as a plain table of closures, so two copies of one handle are not equal. Compare GetModel(), never handles.
--
-- How each read gets its answer, cheapest first:
--   Live: straight off the Roblox instances, always current
--   Derived: from what the API knows of the character (its team, its standing with another character)
--   Published: from what the character asked the API to publish (HoldUntargetable, ReleaseUntargetable)
--   Ask: from the character's own engine, through its bind. A call into another script that can yield, so keep it conditional.
export type CharacterHandle = {
	-- Live. The character this handle reads.
	GetModel: (self: CharacterHandle) -> Model,
	-- Live. Whether the character is still tracked: false once it died or left the world.
	IsValid: (self: CharacterHandle) -> boolean,
	-- Live
	IsAlive: (self: CharacterHandle) -> boolean,
	-- Live
	GetRootPart: (self: CharacterHandle) -> BasePart?,
	-- Live
	GetPosition: (self: CharacterHandle) -> Vector3?,
	-- Live. Studs between root parts, nil if either has none.
	GetDistanceTo: (self: CharacterHandle, other: Other) -> number?,
	-- Live
	GetHealth: (self: CharacterHandle) -> number?,
	-- Live
	GetMaxHealth: (self: CharacterHandle) -> number?,
	-- Live
	GetHealthInfo: (self: CharacterHandle) -> HealthInfo?,
	-- Derived. A character that was removed answers with the team it last had.
	GetTeam: (self: CharacterHandle) -> string,
	-- Derived. Same team, and not Neutral: Neutral is nobody's side. False if either side is invalid, and for itself.
	IsAlly: (self: CharacterHandle, other: Other) -> boolean,
	-- Derived. Not an ally. False if either side is invalid, and for itself.
	IsHostile: (self: CharacterHandle, other: Other) -> boolean,
	-- Published. Whether the character may be picked as a target. Not an immunity: hits still land on it.
	IsTargetable: (self: CharacterHandle) -> boolean,
	-- Ask. False for anything that can't be staggered or can't answer.
	IsStaggered: (self: CharacterHandle) -> boolean,
	-- Ask. False for anything without stamina or that can't answer.
	IsExhausted: (self: CharacterHandle) -> boolean,
}

-- What a handle compares itself to: another handle, or the character's model
export type Other = CharacterHandle | Model

export type HealthInfo = {
	Health: number,
	MaxHealth: number,
	-- Health / MaxHealth, clamped to 0..1 (0 if MaxHealth is not positive)
	Fraction: number,
}

export type Question = "IsStaggered" | "IsExhausted"

-- The few things that differ between kinds of character. The method set of a handle is what every adapter signs up for, so a
-- new one needs a reader that can't know the kind, and at least two kinds that can answer it honestly.
export type Adapter = {
	Name: string,
	-- Whether this adapter is the one for a character discovery could not call a ModNPC
	Detect: (character: Model) -> boolean,
	GetTeam: (entry: Entry) -> string,
	Ask: (entry: Entry, question: Question) -> boolean,
}

-- The API's record of one character. The API is the only writer, which is what keeps a handle from disagreeing with it.
export type Entry = {
	Character: Model,
	-- The character type discovery decided on (CharacterUtility.Type)
	Kind: string,
	Adapter: Adapter,
	-- Why the character is off the target list right now, by reason. Empty means it is targetable.
	Holds: { [string]: true },
	Handle: CharacterHandle,
	-- Set once discovery stops tracking the character
	Removed: boolean,
	LastTeam: string?,
	Humanoid: Humanoid?,
	-- Whatever the adapter wants to remember about this character
	AdapterState: { [string]: any },
}

return TypeCharacterHandle
