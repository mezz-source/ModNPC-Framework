local TypeDamage = {}

export type RecieveType = "Hit" | "Blocked" | "Dodged" | "Nullified"

-- What kind of damage a hit does, for the receiver to react to (resist, ...). Generic is damage we know nothing about
-- (a legacy script took health off the humanoid behind our back).
export type DamageType = "Blunt" | "Generic"

-- An extended effect a hit can carry on top of its damage. The receiver decides the details (how long a stagger lasts)
-- and only applies it if the hit lands.
export type DamageSpecial = "Stagger" | "StaggerBackwards" | "Launch"

export type IncomingDamageContext = {
	Attacker: Model?,
	Receiver: Model,
	Amount: number,
	-- Missing when the damage has no type (a legacy script, a direct API call)
	DamageType: DamageType?,
	-- Missing when the hit has no special effect
	Special: DamageSpecial?,
	-- Longest a Stagger special can hold the receiver (seconds); it rolls somewhere between none and this. Only read for
	-- Stagger, and a Stagger without it has no loop at all.
	MaxStaggerTime: number?,
}

-- What the character's Damage module processes. Registered damage still has to be applied to the humanoid;
-- unregistered damage (humanoid changed behind our back) already has been. Unregistered damage is normally reverted and
-- received again as registered Generic damage, so only damage that killed the character stays unregistered.
export type ReceivedDamageContext = {
	Attacker: Model?,
	Receiver: Model,
	Amount: number,
	DamageType: DamageType?,
	Special: DamageSpecial?,
	MaxStaggerTime: number?,
	Registered: boolean,
}

export type OutgoingDamageContext = {
	Attacker: Model?,
	Receiver: Model,
	Amount: number,
	DamageType: DamageType?,
	-- Whether the hit connected. A blocked hit did (it knocks back and sounds like a hit) but its Amount is 0, or only part of
	-- the damage if the blocker was exhausted (the share its stamina efficiency doesn't absorb); a dodged one didn't connect at all.
	DidHit: boolean,
	RecieveType: RecieveType,
	-- The special that was applied. Missing when the hit had none, or did not land (a blocked hit applies nothing). It can
	-- differ from the one the hit carried: Vitality turns a Stagger or Launch into a StaggerBackwards.
	Special: DamageSpecial?,
	-- Seconds the receiver rolled for a Stagger special (already cut short if Vitality resisted it). Missing for every
	-- other special.
	StaggerDuration: number?,
	-- Whether Vitality saved the receiver from the full effect of the special, by changing it or cutting it short
	Resisted: boolean?,
}

TypeDamage.DamageTypes = table.freeze({
	Blunt = "Blunt",
	Generic = "Generic",
})

-- The settings of a character's Config/Damage folder that Damage reads. A setting the folder doesn't have falls back to
-- the default in Damage.
TypeDamage.Settings = table.freeze({
	-- Multiplies the damage a hit does to this character, after defenses. 0 takes no damage at all.
	RecieveMultiplier = "RecieveMultiplier",
	-- Damage up to and including this plays a light hit reaction, up to MediumThreshold a medium one, anything above is heavy
	LightThreshold = "LightThreshold",
	MediumThreshold = "MediumThreshold",
	-- Damage below this is too little to react to
	MinReactionThreshold = "MinReactionThreshold",
	-- The velocity change (studs/s) a StaggerBackwards throws the character back with
	StaggerBackwardImpulse = "StaggerBackwardImpulse",
	-- The velocity changes (studs/s) a Launch throws the character up and back with
	LaunchUpwardImpulse = "LaunchUpwardImpulse",
	LaunchBackwardImpulse = "LaunchBackwardImpulse",
	-- What a Stagger's time is multiplied by when Vitality resists it
	ResistedStaggerMultiplier = "ResistedStaggerMultiplier",
})

-- The individual sound played when Vitality resists a special
TypeDamage.ResistSound = "Resist"
TypeDamage.BlockSound = "Blocked"
TypeDamage.BlockBreakSound = "BlockBreak"
-- The individual VFX a character emits on itself when its guard is broken
TypeDamage.BlockBreakVFX = "BlockBreakEffect"

-- The settings of a character's Config/Health folder that Damage reads (the health status follows from them). The same
-- default rule applies as for Settings.
TypeDamage.HealthSettings = table.freeze({
	-- Percent of max health a character has to be at or above to be Stable, and to be Injured (below that is Critical)
	StablePercent = "StablePercent",
	InjuredPercent = "InjuredPercent",
})

TypeDamage.Specials = table.freeze({
	Stagger = "Stagger",
	StaggerBackwards = "StaggerBackwards",
	Launch = "Launch",
})

-- The animations of a Stagger, by name (they live in the Stagger category of a character's assets)
TypeDamage.StaggerAnimations = table.freeze({
	Start = "StaggerStart",
	Loop = "StaggerLoop",
	End = "StaggerEnd",
})

-- The animations of a Launch, by name (the Launch category of a character's assets)
TypeDamage.LaunchAnimations = table.freeze({
	Start = "LaunchStart",
	Loop = "LaunchLoop",
	End = "LaunchEnd",
})

-- The individual sounds of a Launch, by name: one as it goes up, one as the end animation begins on landing
TypeDamage.LaunchSounds = table.freeze({
	Start = "LaunchStart",
	Land = "LaunchLand",
})

-- Animation categories of a character's assets. The damage ones hold variants, one of which is picked at random per
-- hit. Stagger and Launch hold a Start, a Loop and an End animation.
TypeDamage.AnimationCategories = table.freeze({
	Light = "DamageLight",
	Medium = "DamageMedium",
	Heavy = "DamageHeavy",
	StaggerBackwards = "StaggerBackwards",
	Stagger = "Stagger",
	Launch = "Launch",
})

-- How heavy a hit is, by the damage it comes with (see Damage:GetHitCategory). The same split the hit reactions go by.
export type HitCategory = "Light" | "Medium" | "Heavy"

TypeDamage.HitCategories = table.freeze({
	Light = "Light",
	Medium = "Medium",
	Heavy = "Heavy",
})

TypeDamage.RecieveTypes = table.freeze({
	Hit = "Hit",
	Blocked = "Blocked",
	Dodged = "Dodged",
	Nullified = "Nullified",
})

return TypeDamage