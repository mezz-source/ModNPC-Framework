local TypeParry = {}

-- The category of a weapon's assets the parry animations live in (Animations/Damage)
TypeParry.AnimationCategory = "Damage"

-- The animations of a parry, by name. Parry is the attempt, ParryHit takes its place when a hit was parried.
TypeParry.Animations = table.freeze({
	Parry = "Parry",
	Hit = "ParryHit",
})

-- How each parry animation is loaded. Both sit with the hit reactions, above attacks and a guard.
TypeParry.AnimationSettings = table.freeze({
	[TypeParry.Animations.Parry] = table.freeze({ Priority = Enum.AnimationPriority.Action2, Loop = false }),
	[TypeParry.Animations.Hit] = table.freeze({ Priority = Enum.AnimationPriority.Action2, Loop = false }),
}) :: { [string]: { Priority: Enum.AnimationPriority, Loop: boolean } }

-- The individual sounds of a parry. Weapon assets: looked up in the equipped weapon's source.
TypeParry.Sounds = table.freeze({
	Start = "ParryStart",
	Hit = "ParryHit",
})

-- The marker of the Parry animation where the parry stops taking hits. The rest of the animation is its recovery.
TypeParry.EndMarker = "ParryEnd"

-- The reason a Parry task is stopped with when it parried a hit, which is what makes it end with ParryHit
TypeParry.HitReason = "Hit"

-- What a parry that took a hit gets back, as a share of what it paid: all of it and a fifth on top
TypeParry.HitRefundMultiplier = 1.2

-- The share of the damage a parried hit would have done that goes back to whoever made it
TypeParry.ReflectShare = 0.5

-- The force the one who was parried is pushed away with, on top of what the hit itself does to them. A kick's knockback.
TypeParry.ReflectKnockback = 800

return TypeParry
