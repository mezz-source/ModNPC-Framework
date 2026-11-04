local TypeDamage = require(script.Parent.TypeDamage)
local TypeStamina = require(script.Parent.TypeStamina)

local TypeBlock = {}

-- The category of a weapon's assets the block animations live in (Animations/Blocks)
TypeBlock.AnimationCategory = "Blocks"

-- The animations of a block, by name. Start and Loop play together as the block is raised, and the block ends with End, or
-- with Break when it was broken. Hit plays over the loop for each hit the block takes.
TypeBlock.Animations = table.freeze({
	Start = "BlockStart",
	Loop = "BlockLoop",
	End = "BlockEnd",
	Break = "BlockBreak",
	Hit = "BlockHit",
})

-- How each block animation is loaded. The loop holds the guard up and sits under the rest, which play over it for a moment:
-- the start as the guard goes up, the end as it comes down, and the hit as it takes a blow. A break is the loudest of them.
TypeBlock.AnimationSettings = table.freeze({
	[TypeBlock.Animations.Loop] = table.freeze({ Priority = Enum.AnimationPriority.Action, Loop = true }),
	[TypeBlock.Animations.Start] = table.freeze({ Priority = Enum.AnimationPriority.Action2, Loop = false }),
	[TypeBlock.Animations.End] = table.freeze({ Priority = Enum.AnimationPriority.Action2, Loop = false }),
	[TypeBlock.Animations.Hit] = table.freeze({ Priority = Enum.AnimationPriority.Action2, Loop = false }),
	[TypeBlock.Animations.Break] = table.freeze({ Priority = Enum.AnimationPriority.Action3, Loop = false }),
}) :: { [string]: { Priority: Enum.AnimationPriority, Loop: boolean } }

-- What holding the block against a hit costs in stamina, by how heavy the hit is. The prices themselves are the stamina's.
TypeBlock.HitCosts = table.freeze({
	[TypeDamage.HitCategories.Light] = TypeStamina.Costs.BlockLight,
	[TypeDamage.HitCategories.Medium] = TypeStamina.Costs.BlockMedium,
	[TypeDamage.HitCategories.Heavy] = TypeStamina.Costs.BlockHeavy,
})

return TypeBlock
