local TypeState = {}

-- A state enum is a table of name -> value strings; State only ever stores and compares the values
export type StateEnum = { [string]: string }

export type HealthStatus = "Stable" | "Injured" | "Critical" | "Dead"
export type MoveState = "None" | "Walking" | "Sprinting"
export type AirState = "Grounded" | "Falling"
export type AttackState = "None" | "Swinging"
export type StaggerState = "None" | "Staggered" | "Launched"
export type DodgeState = "None" | "Active"
export type EngageState = "Pursuing" | "Engaged"
export type ExhaustionState = "None" | "Exhausted"
export type BlockState = "None" | "Blocking"
export type BlockBreakState = "Inactive" | "Active"
export type DefenseState = "None" | "Reacting"

-- State registers nothing itself; each state is registered by the module that owns it (HealthStatus: Damage)
TypeState.Keys = table.freeze({
	AirState = "AirState",
	MoveState = "MoveState",
	HealthStatus = "HealthStatus",
	AttackState = "AttackState",
	StaggerState = "StaggerState",
	DodgeState = "DodgeState",
	EngageState = "EngageState",
	ExhaustionState = "ExhaustionState",
	BlockState = "BlockState",
	BlockBreakState = "BlockBreakState",
	DefenseState = "DefenseState",
})

TypeState.HealthStatusEnum = table.freeze({
	Stable = "Stable",
	Injured = "Injured",
	Critical = "Critical",
	Dead = "Dead",
})

TypeState.MoveStateEnum = table.freeze({
	None = "None",
	Walking = "Walking",
	Sprinting = "Sprinting",
})

TypeState.AirStateEnum = table.freeze({
	Grounded = "Grounded",
	Falling = "Falling",
})

TypeState.AttackStateEnum = table.freeze({
	None = "None",
	Swinging = "Swinging",
})

TypeState.StaggerStateEnum = table.freeze({
	None = "None",
	Staggered = "Staggered",
	Launched = "Launched",
})

-- Active for the span of a dodge, during which the character is evasive
TypeState.DodgeStateEnum = table.freeze({
	None = "None",
	Active = "Active",
})

-- Whose job the way to the focus target is (registered by Distance, no None). Pursuing is ChaseTargets' while the target
-- is outside the engage distance, Engaged is Engage's from the moment it is reached until the target gets well past it.
TypeState.EngageStateEnum = table.freeze({
	Pursuing = "Pursuing",
	Engaged = "Engaged",
})

-- Registered by Stamina. Exhausted from the moment the stamina falls to the ExhaustionThreshold until it is back at the
-- RecoverThreshold, during which the character regenerates faster but can't pay for what asks for rested stamina.
TypeState.ExhaustionStateEnum = table.freeze({
	None = "None",
	Exhausted = "Exhausted",
})

-- Registered by Damage. Blocking for as long as a Block task holds it: hits that come in meanwhile are absorbed.
TypeState.BlockStateEnum = table.freeze({
	None = "None",
	Blocking = "Blocking",
})

-- Registered by Damage. Active from the moment a guard is broken (see Damage:BreakBlock) until the exhaustion it forces is
-- over, during which the character can't raise its guard again (see Abilities.CanBlock).
TypeState.BlockBreakStateEnum = table.freeze({
	Inactive = "Inactive",
	Active = "Active",
})

-- Registered by Defense. Reacting from the moment the character decides how to meet a hit it saw coming (a dodge timed to
-- it, or a guard raised for it) until that is done with, during which it doesn't start an attack of its own (see
-- Abilities.CanAttack), as the swing would take the dodge or the guard away from it.
TypeState.DefenseStateEnum = table.freeze({
	None = "None",
	Reacting = "Reacting",
})

return TypeState
