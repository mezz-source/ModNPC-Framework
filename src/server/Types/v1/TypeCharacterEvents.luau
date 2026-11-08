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
	-- Blocked, Parried or Dodged
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
	-- The special the target says was applied (Vitality may have turned it into another). Missing when the hit had none, or
	-- did not land.
	Special: TypeDamage.DamageSpecial?,
}

-- This character's attack bounced off another: neither did anything, and the attack was cancelled
export type AttackBounced = {
	-- Whoever made the other attack
	Opponent: Model?,
}

-- One of this character's attacks is over (it got to swing at all)
export type AttackEnded = {
	Target: Model,
	AttackName: string,
	-- Every hit was played out. False when it was cut short (staggered, out of stamina for the next hit of a combo...).
	Finished: boolean,
}

-- This character's guard was broken
export type BlockBroken = {
	-- Why, as the Block task gave it
	Reason: string?,
}

-- A launch this character was in has ended
export type LaunchEnded = {
	-- It ran its course and the character got back up. False when it was cut short (death, the state taken away).
	Recovered: boolean,
}

-- This character's own team setting (Config/Team/TeamName) changed
export type TeamChanged = {
	-- The team it was on, nil if it had none set
	Previous: string?,
	Current: string,
}

-- The Wander task picked a spot and is walking to it
export type NewWanderPosition = {
	Position: Vector3,
}

-- An Investigate task started sprinting to a spot
export type InvestigationStarted = {
	Position: Vector3,
}

-- An Investigate task ended, however it ended
export type InvestigationEnded = {
	Position: Vector3,
	-- Whether it ended because a focus target was acquired (what investigating is for)
	FoundTarget: boolean,
	-- The focus target acquired, when FoundTarget
	Target: Model?,
	-- Why it ended: "Focus target acquired", "Arrived", "Timed out", or whatever stopped it ("Chase ended", a Movement
	-- task taking over...)
	Reason: string,
}

TypeCharacterEvents.Names = table.freeze({
	Dialogue = {
		Event = "DialogueEvent",
		SfxEvent = "DialogueSoundEffect",
		DialogueSoundEvent = "DialogueSoundEvent",
		PlayAnimationEvent = "DialoguePlayAnimation",
		StopAnimationEvent = "DialogueStopAnimation",
	},
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
		-- Payload: AttackBounced. Dispatched by Attacks on both sides of a bounce, in place of the outcomes above and of
		-- DefenseSucceeded: nobody landed or defended anything
		AttackBounced = "CombatAttackBounced",
		-- Payload: AttackEnded. Dispatched by the Attack task as an attack that swung ends, however it ends
		AttackEnded = "CombatAttackEnded",
		-- Payload: BlockBroken. Dispatched by Damage once the character's guard is broken (BlockBreakState is Active)
		BlockBroken = "CombatBlockBroken",
		-- No payload. Dispatched by Damage as the character takes the launched state (it is being thrown)
		Launched = "CombatLaunched",
		-- Payload: LaunchEnded. Dispatched by Damage as the character gives the launched state back
		LaunchEnded = "CombatLaunchEnded",
		-- Payload: Reason. Dispatched when an attack interrupts our current action (like attack).
		DamageInterrupt = "DamageInterrupt",
	},
	Wander = {
		-- Payload: NewWanderPosition. Dispatched by the Wander task once a walk to a new spot has started
		NewPosition = "NewWanderPosition",
	},
	Investigate = {
		-- Payload: InvestigationStarted. Dispatched by the Investigate task once it has taken movement over and set off
		Started = "InvestigationStarted",
		-- Payload: InvestigationEnded. Dispatched by the Investigate task as it ends, after its InvestigateState is back
		-- to None
		Ended = "InvestigationEnded",
	},
	Targetting = {
		FocusedTargetChanged = "FocusedTargetChanged",
		-- Payload: TargettingContext, then alreadyClaimed: boolean. Dispatched by the search task when we go from no focus to a
		-- target. alreadyClaimed is true only if a teammate claimed the target before us (ClaimTarget); false otherwise,
		-- including when nobody tried (no team, no teammates around, or the request failed).
		NewFocusTarget = "NewFocusTarget",
		LostFocusTarget = "LostFocusTarget",
		TargetLost = "TargetLost",
		-- No payload. Dispatched when the last known target is lost, after that target's TargetLost
		AllTargetsLost = "AllTargetsLost",
		TargetSpotted = "TargetSpotted",
		-- No payload. Dispatched by the search task after every search, once its target events have gone out
		SearchCompleted = "TargetSearchCompleted",
		-- Payload: TargettingContext. Dispatched by Friends when a character on our team comes within our provoke range
		TeammateSpotted = "TeammateSpotted",
		-- Payload: TargettingContext. Dispatched by Friends when a teammate is gone (left our provoke range, died, was
		-- removed, or we changed teams)
		TeammateLost = "TeammateLost",
		-- Payload: FriendContext. Dispatched by Friends when a connection is made, on both sides
		FriendAdded = "FriendAdded",
		-- Payload: FriendContext. Dispatched by Friends when a friend left the target registry or stopped sharing our team
		FriendLost = "FriendLost",
		-- Payload: TeamChanged. Dispatched by Friends when this character's own team setting changes. Its friends and
		-- teammates are dropped on the next search, so FriendLost / TeammateLost follow.
		TeamChanged = "TeamChanged",
		-- Payload: FriendBetrayal. Dispatched by Friends, right after that friend's FriendLost, when a friend is on another
		-- team than the one we shared while we are still on it (the friend turned on us, living or not).
		FriendBetrayed = "FriendBetrayed",
	}
})

return TypeCharacterEvents
