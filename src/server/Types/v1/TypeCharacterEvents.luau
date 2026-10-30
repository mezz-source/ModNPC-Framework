local TypeCharacterEvents = {}

local TypeCDN = require(script.Parent.TypeCDN)
local TypeDamage = require(script.Parent.TypeDamage)

type PrimitiveValue = TypeCDN.PrimitiveValue

export type ConfigurationUpdated = {
	Path: { string },
	Previous: PrimitiveValue,
	Value: PrimitiveValue,
	Type: string,
}

export type Event = {
	Name: string,
	Args: any,
}
export type HealthChanged = {
	Health: number,
	MaxHealth: number,
}

export type StateChanged = {
	OldState: Enum.HumanoidStateType,
	NewState: Enum.HumanoidStateType,
}

-- Key is the state's registered key; Old/New are values of that state's enum
export type CharacterStateChanged = {
	Key: string,
	Old: string,
	New: string,
}

export type WeaponChanged = {
	Weapon: Instance,
}

export type ContentSourceAdded = {
	Source: TypeCDN.ContentSource,
	Index: TypeCDN.AssetIndex,
}

export type ContentSourceRemoved = {
	Source: TypeCDN.ContentSource,
}

-- A hit that landed on this character and took health off it
export type DamageTaken = {
	Attacker: Model?,
	-- The health that came off
	Amount: number,
	-- The health we had at most, so listeners can tell a scratch from a beating without asking
	MaxHealth: number,
	DamageType: TypeDamage.DamageType?,
	-- The special the hit landed with, if any
	Special: TypeDamage.DamageSpecial?,
}

-- A hit that was meant for this character and didn't land
export type DefenseSucceeded = {
	Attacker: Model?,
	-- Blocked or Dodged
	RecieveType: TypeDamage.RecieveType,
}

-- The character's stamina or its maximum changed
export type StaminaChanged = {
	Previous: number,
	Current: number,
	Max: number,
	-- What caused it: the cost that was bought (Dodge, ...), or Spend, Restore, MaxChanged, SprintDrain (the cost of
	-- staying in a sprint), Regeneration
	Reason: string?,
}

-- The character became exhausted or recovered from it
export type StaminaExhaustion = {
	Current: number,
	Max: number,
	-- How well the character can do things now (see Stamina:GetEfficiency): below 1 when it just became exhausted, 1 when it
	-- recovered
	Efficiency: number,
}

-- How one hit of an attack of this character turned out for it. The same shape for all three outcomes.
export type AttackOutcome = {
	Target: Model,
	AttackName: string,
	HitName: string,
	-- The damage that went through, 0 unless the hit landed
	Amount: number,
	-- What the target made of the hit. Missing for a hit that whiffed, as there was no one to receive it.
	RecieveType: TypeDamage.RecieveType?,
}

TypeCharacterEvents.Names = table.freeze({
	Weapon = {
		-- Payload: WeaponChanged. Dispatched by CharacterAPI once the weapon is welded and flagged
		Equipped = "WeaponEquipped",
		Unequipped = "WeaponUnequipped",
		-- Payload: WeaponChanged. Dispatched by Weapons when the equipped weapon is armed (drawn) or disarmed
		Armed = "WeaponArmed",
		Disarmed = "WeaponDisarmed",
	},
	Content = {
		-- Payload: ContentSourceAdded. A weapon's source exists from its equip until its unequip
		SourceAdded = "ContentSourceAdded",
		-- Payload: ContentSourceRemoved. Dispatched while the source's data can still be read
		SourceRemoved = "ContentSourceRemoved",
	},
	Configuration = {
		ConfigurationUpdated = "ConfigurationUpdated",
		ConfigurationInvalidated = "ConfigurationInvalidated",
	},
	Humanoid = {
		MoveBegan = "HumanoidMoveBegan",
		MoveEnded = "HumanoidMoveEnded",
		Died = "HumanoidDied",
		Running = "HumanoidRunning",
		HealthChanged = "HumanoidHealthChanged",
		StateChanged = "HumanoidStateChanged",
		Jumped = "HumanoidJumped",
		Landed = "HumanoidLanded",
	},
	Animation = {
		AnimationPlayed = "AnimationPlayed",
		AnimationStopped = "AnimationStopped",
		DeathFinished = "AnimationDeathFinished",
	},
	State = {
		Changed = "CharacterStateChanged",
	},
	Thought = {
		-- Payload: number, seconds elapsed since the previous ReactionUpdate
		ReactionUpdate = "ThoughtReactionUpdate",
	},
	Stimulant = {
		-- Payload: { TypeStimulant.StimulantEvent }, most urgent first. Dispatched by Stimulants on each reaction tick while
		-- anything is still queued. Consume (ConsumeStimulant) whatever you act on; the rest stays until it expires.
		Pending = "StimulantsPending",
	},
	Stamina = {
		-- Payload: StaminaChanged. Dispatched by Stamina whenever the amount or the maximum actually changes
		Changed = "StaminaChanged",
		-- Payload: StaminaExhaustion. Dispatched by Stamina when the character becomes exhausted, after the ExhaustionState is set
		ExhaustionStarted = "StaminaExhaustionStarted",
		-- Payload: StaminaExhaustion. Dispatched by Stamina when the character has recovered from it
		ExhaustionEnded = "StaminaExhaustionEnded",
	},
	-- How fights turn out for this character. What the disposition (see Disposition) reads its moods from, and open to
	-- anything else that wants to know how it is going.
	Combat = {
		-- Payload: DamageTaken. Dispatched by Damage once health came off, whether the hit came through the API or not
		DamageTaken = "CombatDamageTaken",
		-- Payload: DefenseSucceeded. Dispatched by Damage for a hit that was dodged or blocked, and by Defense for a hit a dodge
		-- took us out of the reach of (it never got to Damage, the attacker found us out of range)
		DefenseSucceeded = "CombatDefenseSucceeded",
		-- Payload: TypeDefense.DefenseReaction. Dispatched by Defense as it decides how to meet a hit it saw coming (an
		-- IncomingAttack), before the hit lands. How the hit actually went is still DefenseSucceeded / DamageTaken.
		DefenseReaction = "CombatDefenseReaction",
		-- Payload: AttackOutcome. Dispatched by the Attack task, for each hit of an attack of this character
		AttackLanded = "CombatAttackLanded",
		-- The target dodged or blocked it
		AttackDefended = "CombatAttackDefended",
		-- It found the target out of range, or gone
		AttackMissed = "CombatAttackMissed",
	},
	Targetting = {
		FocusedTargetChanged = "FocusedTargetChanged",
		NewFocusTarget = "NewFocusTarget",
		LostFocusTarget = "LostFocusTarget",
		TargetLost = "TargetLost",
		-- No payload. Dispatched when the last known target is lost, after that target's TargetLost
		AllTargetsLost = "AllTargetsLost",
		TargetSpotted = "TargetSpotted"
	}
})

return TypeCharacterEvents
