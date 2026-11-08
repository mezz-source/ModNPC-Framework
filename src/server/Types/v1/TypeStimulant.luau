local TypeStimulant = {}

-- Who a stimulant is for. Individual and Group are cheap lookups, All reaches every receiver the API knows of.
export type RecipientType = "Individual" | "Group" | "All"

export type Recipient = {
	Type: RecipientType,
	-- Individual only
	Target: Model?,
	-- Group only
	Targets: { Model }?,
}

-- How much a stimulant asks for the character's attention. A Low one can expire quietly while the character is busy with
-- something higher.
export type Priority = "Low" | "Normal" | "High" | "Critical"

-- What the CharacterStimulant bind carries: a new stimulant, or the id of one that is no longer true
export type MessageType = "Stimulant" | "Retract"

-- Something in the world a character may react to, queued by the receiver and consumed later by its thought process
export type StimulantEvent = {
	-- Given by the API, the handle a stimulant is retracted by
	Id: number,
	Name: string,
	-- Who or what caused it, if anyone
	Source: Model?,
	-- Where it happened, if it has a place
	Position: Vector3?,
	Priority: Priority,
	-- os.clock() time it stops being true, absolute so it means the same whenever it is read
	ExpiresAt: number,
	Data: any?,
}

-- What an emitter hands the API. The API fills in the Id and the Source.
export type StimulantSpec = {
	Name: string,
	-- Normal when left out
	Priority: Priority?,
	ExpiresAt: number,
	Position: Vector3?,
	Data: any?,
	-- Stays true after its emitter is gone. Normally everything an emitter has in flight is retracted when it dies or is
	-- destroyed; a stimulant that announces that very thing (Died) has to outlive it.
	Lingers: boolean?,
}

-- A whole stimulant on its way out: what it is and who it is for. Made with StimulantBuilder and handed to
-- CharacterAPI:SendStimulant / EmitStimulant. A plain table, so it crosses the API's bindable intact.
export type OutgoingStimulant = {
	Recipient: Recipient,
	Name: string,
	Priority: Priority?,
	ExpiresAt: number,
	Position: Vector3?,
	Data: any?,
	Lingers: boolean?,
}

-- What a builder sends through: a character's CharacterAPI
export type StimulantSender = {
	SendStimulant: (self: any, stimulant: OutgoingStimulant) -> (),
	EmitStimulant: (self: any, stimulant: OutgoingStimulant) -> EmitResult?,
}

-- Chained to describe a stimulant, then Build() gives the OutgoingStimulant (or why it can't be one yet), or Send() /
-- Emit() build and send it in one go
export type StimulantBuilder = {
	To: (self: StimulantBuilder, target: Model) -> StimulantBuilder,
	ToGroup: (self: StimulantBuilder, targets: { Model }) -> StimulantBuilder,
	ToAll: (self: StimulantBuilder) -> StimulantBuilder,
	WithPriority: (self: StimulantBuilder, priority: Priority) -> StimulantBuilder,
	Lasting: (self: StimulantBuilder, seconds: number) -> StimulantBuilder,
	ExpiringAt: (self: StimulantBuilder, expiresAt: number) -> StimulantBuilder,
	At: (self: StimulantBuilder, position: Vector3) -> StimulantBuilder,
	WithData: (self: StimulantBuilder, data: any) -> StimulantBuilder,
	Lingering: (self: StimulantBuilder) -> StimulantBuilder,
	Build: (self: StimulantBuilder) -> (OutgoingStimulant?, string?),
	Send: (self: StimulantBuilder) -> (boolean, string?),
	Emit: (self: StimulantBuilder) -> (EmitResult?, string?),
}

-- What emit answers with
export type EmitResult = {
	Id: number,
	-- How many receivers it reached
	Delivered: number,
}

-- The stimulants Base sends, so senders and the characters reacting to them spell them the same
TypeStimulant.Names = table.freeze({
	-- A hit of an attack is on its way to the receiver. Data: TypeAttack.HitStimulantContext. Expires as the hit lands,
	-- retracted early if the attack is cut short. A combo sends one per hit, the next as the previous lands.
	IncomingAttack = "IncomingAttack",
	-- The sender started sprinting at the receiver (its chase target). Data: SprintingTowardsData. Low and short lived.
	SprintingTowards = "SprintingTowards",
	-- The sender's guard was just broken by the receiver's hit: it is open until its break animation is over. No data.
	BlockBroken = "BlockBroken",
	-- The sender just became exhausted (see Stamina) while the receiver is its target: it is slower and weaker for a while.
	-- Data: ExhaustedData. Normal, a couple of seconds.
	Exhausted = "Exhausted",
	-- The sender just died. Broadcast to every receiver, Normal, a few seconds, and it outlives its sender (Lingers).
	-- Positioned where the sender fell. Data: DiedData.
	Died = "Died",
	-- The sender was the first of its team to spot a target (it holds the team's claim on it) and has just called it out.
	-- Sent to its teammates in range once its SpotEnemyTeamed line is typed out, so one who sees the same target can
	-- answer. Data: EnemySpottedByAllyData. Normal, a few seconds.
	EnemySpottedByAlly = "EnemySpottedByAlly",
})

export type EnemySpottedByAllyData = {
	-- The first responder, who called the target out
	Spotter: Model,
	-- Who it called out
	Target: Model,
}

-- The killing hit, when it came through the damage register (Damage:ReceiveRegistered), so it is known in full
export type DiedDamage = {
	-- Who dealt it, nil for damage with no attacker
	Attacker: Model?,
	-- What the sender took from it, after blocking and its multipliers
	Amount: number,
	DamageType: string?,
	-- The special it landed with, if any
	Special: string?,
}

export type DiedData = {
	-- Whether the death came through the damage register. False for damage that bypassed it (a script setting the humanoid's
	-- health, a fall...), in which case nothing is known of the killing blow and Damage is missing.
	Registered: boolean,
	-- The killing hit. Only when Registered.
	Damage: DiedDamage?,
	-- The last character that hit the sender through the damage register (a blocked hit counts), whether or not it was the
	-- killing blow. Missing if nobody did, or if it is gone since.
	LastAttacker: Model?,
}

export type ExhaustedData = {
	-- How well the sender does things now (Stamina:GetEfficiency), below 1
	Efficiency: number,
}

export type SprintingTowardsData = {
	-- Studs between the two as the sprint began
	Distance: number,
}

TypeStimulant.RecipientTypes = table.freeze({
	Individual = "Individual",
	Group = "Group",
	All = "All",
})

TypeStimulant.Priorities = table.freeze({
	Low = "Low",
	Normal = "Normal",
	High = "High",
	Critical = "Critical",
})

-- For comparing priorities, higher is more urgent
TypeStimulant.PriorityRank = table.freeze({
	[TypeStimulant.Priorities.Low] = 1,
	[TypeStimulant.Priorities.Normal] = 2,
	[TypeStimulant.Priorities.High] = 3,
	[TypeStimulant.Priorities.Critical] = 4,
})

TypeStimulant.MessageTypes = table.freeze({
	Stimulant = "Stimulant",
	Retract = "Retract",
})

return TypeStimulant
