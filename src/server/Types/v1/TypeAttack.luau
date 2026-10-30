local TypeCDN = require(script.Parent.TypeCDN)
local TypeDamage = require(script.Parent.TypeDamage)
local TypeStamina = require(script.Parent.TypeStamina)

local TypeAttack = {}

export type AttackType = "Generic" | "Melee" | "Ranged"

-- How heavy a hit is, which is what it costs in stamina to make (see WeightCosts)
export type AttackWeight = "Light" | "Medium" | "Heavy"

-- The types an attack folder can declare. Generic is only what attacks without data fall back to.
export type DataAttackType = "Melee" | "Ranged"

-- Which part of the body an attack uses, for the attack tasks to claim as resources.
-- All is the arms and the legs together.
export type AttackLimbs = "Arms" | "Legs" | "All"

-- One hit of an attack, read from an AttackN folder.
export type AttackHit = {
	-- folder name, Attack1, Attack2, ...
	Name: string,
	BaseDamage: number,
	DamageType: TypeDamage.DamageType,
	-- what the hit costs in stamina to make: the character has to afford and pay it for the hit to happen
	AttackWeight: AttackWeight,
	-- impulse that throws the attacker forward as the hit lands. 0 for none.
	LungeForce: number,
	-- impulse that throws the target away from the attacker when the hit does damage. 0 for none.
	KnockbackForce: number,
	-- sound to play as the hit lands, empty to play nothing
	HitSoundName: string,
	-- individual VFX played at the target's root part when the hit lands, empty to play nothing
	HitVFXName: string,
	-- extended damage effect (a TypeDamage.DamageSpecial: stagger, ...). Empty when the hit has none.
	Special: string,
	-- longest the Stagger special holds the target (seconds). Only matters for a Stagger, 0 when the hit has none.
	MaxStaggerTime: number,
	-- the animation event that lands this hit
	AnimationEventName: string,
}

-- An attack as it is stored in an Attacks directory (ModNPC and ModWeapon alike).
export type AttackData = {
	-- folder name. Variants of the same attack are just separate folders (Punch1, Punch2)
	Name: string,
	Type: DataAttackType,
	Limbs: AttackLimbs,
	-- Studs from the target the attack is made from. Further than this the character closes in first, and the attack
	-- is only made once the target is within it.
	DesiredRange: number,
	-- combos read every AttackN folder in order, everything else only ever reads Attack1
	IsCombo: boolean,
	Debounce: number,
	AllowMoving: boolean,
	AllowInterrupts: boolean,
	-- sound to play once as the attack starts, a combo included. Empty to play nothing.
	SwingSoundName: string,
	-- ordered, always at least one
	Hits: { AttackHit },
}

-- How the character carries on from an attack it is making, decided as the attack begins (see Disposition:GetAttackPace)
export type AttackPace = {
	-- The attack is committed to a follow-up: the character stays where it is to make the next one right after, instead of
	-- backing off to rest
	PressOn: boolean,
	-- Seconds the character rests out of reach once the exchange is over. Only matters when it doesn't press on.
	Rest: number,
}

-- Every attack of one source keyed by attack name
export type AttackIndex = { [string]: AttackData }

-- A stored attack that fits a request, with the source it came from
export type AttackCandidate = {
	Attack: AttackData,
	Source: TypeCDN.ContentSource,
}

-- What a single attack is made of. Every attack function builds one of these and funnels it into Attacks:Attack.
export type AttackContext = {
	-- What was asked for, which is not always what was found (a Generic request gets a Melee or Ranged attack)
	Type: AttackType,
	-- Where Attack came from, so the sounds and animations of its hits are looked up in that source first
	Source: TypeCDN.ContentSource,
	-- The character being attacked
	Target: Model,
	-- The stored attack being performed. The damage comes from its hits' BaseDamage.
	Attack: AttackData,
	-- The name of the attack's preloaded animation track (see Attacks:GetAnimationName)
	AnimationName: string,
}

-- One hit of the attack being performed, as the attack task tracks it. The task waits for EventName on the animation,
-- and then the hit lands.
export type HitContext = {
	Name: string,
	EventName: string,
	BaseDamage: number,
	DamageType: TypeDamage.DamageType,
	AttackWeight: AttackWeight,
	LungeForce: number,
	KnockbackForce: number,
	HitSoundName: string,
	HitVFXName: string,
	Special: string,
	MaxStaggerTime: number,
}

-- What a target is told about a hit coming its way (the IncomingAttack stimulant's Data): only what matters for deciding
-- how to meet it, none of the cosmetics (sounds, VFX, forces)
export type HitStimulantContext = {
	AttackWeight: AttackWeight,
	BaseDamage: number,
	DamageType: TypeDamage.DamageType,
	-- empty when the hit has no special
	Special: string,
	MaxStaggerTime: number,
}

TypeAttack.AttackWeights = table.freeze({
	Light = "Light",
	Medium = "Medium",
	Heavy = "Heavy",
})

-- The stamina cost each weight is bought as (the prices are in the character's Config/Stamina)
TypeAttack.WeightCosts = table.freeze({
	[TypeAttack.AttackWeights.Light] = TypeStamina.Costs.LightAttack,
	[TypeAttack.AttackWeights.Medium] = TypeStamina.Costs.MediumAttack,
	[TypeAttack.AttackWeights.Heavy] = TypeStamina.Costs.HeavyAttack,
})

TypeAttack.AttackTypes = table.freeze({
	Generic = "Generic",
	Melee = "Melee",
	Ranged = "Ranged",
})

TypeAttack.DataAttackTypes = table.freeze({
	Melee = "Melee",
	Ranged = "Ranged",
})

TypeAttack.Limbs = table.freeze({
	Arms = "Arms",
	Legs = "Legs",
	All = "All",
})

return TypeAttack
