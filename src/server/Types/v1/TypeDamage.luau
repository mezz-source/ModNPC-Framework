local TypeDamage = {}

export type RecieveType = "Hit" | "Blocked" | "Nullified"

export type IncomingDamageContext = {
	Attacker: Model?,
	Receiver: Model,
	Amount: number,
}

export type OutgoingDamageContext = {
	Attacker: Model?,
	Receiver: Model,
	Amount: number,
	DidHit: boolean,
	RecieveType: RecieveType,
}

TypeDamage.RecieveTypes = table.freeze({
	Hit = "Hit",
	Blocked = "Blocked",
	Nullified = "Nullified",
})

return TypeDamage