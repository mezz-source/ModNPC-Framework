local TypeCharacterHandle = require(script.Parent.TypeCharacterHandle)

local TypeFriends = {}

-- What the API carries from the character asking to the character asked. The Team is read as the request goes out, so the
-- character asked can check it against its own.
export type FriendRequest = {
	Sender: Model,
	Team: string,
}

-- A character we are connected to, remembered until it leaves the target registry or the team
export type FriendContext = {
	Character: Model,
	Team: string,
	-- Whether we were the one who asked
	Initiated: boolean,
	-- Read the friend through this
	Handle: TypeCharacterHandle.CharacterHandle?,
}

-- A friend that left our team while we stayed on it
export type FriendBetrayal = {
	Character: Model,
	-- The team we shared, and still have
	Team: string,
	-- The team the friend is on now
	NewTeam: string,
	Handle: TypeCharacterHandle.CharacterHandle?,
}

export type FriendOutcome = "Accepted" | "TeamMismatch" | "SenderDead" | "ReceiverDead" | "Busy" | "Failed"

TypeFriends.Outcomes = table.freeze({
	Accepted = "Accepted",
	-- Declined: the two no longer share a team
	TeamMismatch = "TeamMismatch",
	-- Declined: the character asking died on the way
	SenderDead = "SenderDead",
	-- Declined: the character asked has died
	ReceiverDead = "ReceiverDead",
	-- The pair is already mid request, from either side. That one decides it, this one was never delivered.
	Busy = "Busy",
	-- The character asked gave no usable answer (not a started ModNPC, no ReceiveFriendRequest function, ...)
	Failed = "Failed",
})

return TypeFriends
