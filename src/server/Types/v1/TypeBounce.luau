local TypeBounce = {}

-- The category of a weapon's assets the bounce animations live in (Animations/AttackBounce). One of them is picked at random.
TypeBounce.AnimationCategory = "AttackBounce"

-- With the hit reactions and the parry animations
TypeBounce.AnimationPriority = Enum.AnimationPriority.Action2

-- The individual sound of a bounce. A weapon asset: looked up in the equipped weapon's source.
TypeBounce.Sound = "Bounce"

-- The individual VFX of a bounce. A weapon asset as well, played on the weapon's model.
TypeBounce.VFX = "BounceEffect"

-- The velocity change that throws a character back as its attack bounces. A StaggerBackwards' worth.
TypeBounce.BackwardImpulse = 70

-- Seconds a bounce waits for its animation to end before it lets go of the character anyway
TypeBounce.Timeout = 5

return TypeBounce
