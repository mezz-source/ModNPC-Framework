local TypeDisposition = {}

-- How the character feels about the fight right now, on each axis from 0 to 1. See Disposition.
export type Axis = "Aggression" | "Evasiveness" | "Guard" | "Tempo" | "Commitment"

-- What the disposition is made of: each factor measures one thing about the fight and leans the axes by it
export type Factor = "Injury" | "FailedAttacks" | "Pressure" | "Momentum" | "Stalemate" | "Opening" | "Stamina" | "TargetWeak" | "Exhaustion"
	| "Threatened" | "TargetOpen" | "TargetTired" | "Charged"

export type Axes = { [Axis]: number }

-- How strongly each axis leans when a factor is at full strength, from -1 to 1. An axis a factor doesn't mention isn't moved.
export type Effects = { [Axis]: number }

TypeDisposition.Axes = table.freeze({
	-- How up front the character is. Decides how close it holds itself to its target.
	Aggression = "Aggression",
	-- How much it moves about instead of standing its ground (strafing)
	Evasiveness = "Evasiveness",
	-- How readily it defends itself (blocking)
	Guard = "Guard",
	-- How soon it follows up, how short its pauses are
	Tempo = "Tempo",
	-- Whether it is willing to lock itself into an attack. Low favors attacks that allow moving and interrupts.
	Commitment = "Commitment",
})

TypeDisposition.Factors = table.freeze({
	-- How hurt we are
	Injury = "Injury",
	-- Attacks of ours that were defended or missed lately
	FailedAttacks = "FailedAttacks",
	-- How much we were hurt in the last few seconds, however healthy we still are
	Pressure = "Pressure",
	-- Attacks of ours that landed lately
	Momentum = "Momentum",
	-- How long we have been in each other's face without anything being exchanged
	Stalemate = "Stalemate",
	-- The moment after we dodged or blocked a hit, when the attacker is open
	Opening = "Opening",
	-- How much of our stamina is gone
	Stamina = "Stamina",
	-- How badly hurt the character we are fighting is
	TargetWeak = "TargetWeak",
	-- Whether we are out of breath (the ExhaustionState). All or nothing, and a big one: it slows a character down in
	-- everything it does.
	Exhaustion = "Exhaustion",

	-- Stimulant factors: what other characters told us they are doing (see TypeStimulant.Names). Each is a pulse that is at
	-- full strength as the stimulant is perceived and fades over a hold of its own (STIMULANT_FACTORS in Disposition), so
	-- the character's mood follows what it just saw without being stuck on it.
	-- A hit is on its way to us (IncomingAttack). Defending against it is Defense's; this is the wariness it leaves.
	Threatened = "Threatened",
	-- We broke the guard of the one we hit (BlockBroken): it is wide open for a moment
	TargetOpen = "TargetOpen",
	-- The one fighting us just ran out of breath (Exhausted), as much as its efficiency fell
	TargetTired = "TargetTired",
	-- Someone is sprinting at us (SprintingTowards), stronger the closer they started
	Charged = "Charged",
})

-- The settings of a factor's folder in the character's Config/Disposition. Besides Importance a factor's folder can
-- hold a value named after an axis (Aggression, ...) to replace how strongly that factor leans the axis.
TypeDisposition.Settings = table.freeze({
	-- Multiplies everything the factor does. 0 turns it off, negative turns it around. 1 when the folder doesn't say.
	Importance = "Importance",
})

-- Where the Config/Disposition folder keeps the axes' resting values (before any factor leans them). Aggression and
-- Evasiveness keep theirs in Config/ThoughtProcess, where they were before the disposition existed.
TypeDisposition.BaselineFolder = "Baseline"
TypeDisposition.Folder = "Disposition"

return TypeDisposition
