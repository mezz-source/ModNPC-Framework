local TypeDefense = {}

-- How a character met a hit it saw coming (an IncomingAttack stimulant). See Defense.
export type Reaction = "Dodge" | "Block" | "Guarded" | "None"

TypeDefense.Reactions = table.freeze({
	-- Dodged it: an Agility roll was made in time, and the dodge goes off just before the hit so its active span covers it
	Dodge = "Dodge",
	-- Raised a guard for it at the last moment: the dodge was out of time or its roll failed, and a block could still go up
	Block = "Block",
	-- Kept the guard that was already up, which can pay for a hit this heavy
	Guarded = "Guarded",
	-- Could do nothing about it, the hit is taken
	None = "None",
})

-- The settings of a character's Config/Defense folder. The folder and every setting are optional (not in the schema): a
-- setting it doesn't have is its default in Defense.
TypeDefense.Settings = table.freeze({
	-- Seconds a dodge needs before the hit to still be got off. A hit seen with less left can only be blocked.
	DodgeReactionTime = "DodgeReactionTime",
	-- Seconds a guard needs before the hit to still go up in time
	BlockReactionTime = "BlockReactionTime",
	-- Seconds before the hit from which a last moment guard is sure to go up (at a Guard of 0.5). Between the
	-- BlockReactionTime and this it is a gamble, likelier the more time is left.
	BlockSureTime = "BlockSureTime",
	-- Added to the Agility roll's odds of a dodge (-1..1, as a share of the d20), for a character that is better or worse at
	-- reading hits than its level says
	DodgeBonus = "DodgeBonus",
})

TypeDefense.Folder = "Defense"

-- What the Combat.DefenseReaction event carries
export type DefenseReaction = {
	-- Who the hit comes from, if anyone we know of
	Attacker: Model?,
	Reaction: Reaction,
	-- Seconds the hit was still away when the character decided
	TimeLeft: number,
	-- Why it went the way it did ("Too late", "Roll failed", ...), for whoever is watching
	Reason: string?,
}

return TypeDefense
