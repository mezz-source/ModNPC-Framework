local TypeDamage = require(script.Parent.TypeDamage)
local TypeStamina = require(script.Parent.TypeStamina)

local TypeBlock = {}

-- The category of the character's assets the block animations live in (Animations/Blocks)
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

-- What holding the block against a hit costs in stamina, by how heavy the hit is. The prices themselves are the stamina's.
TypeBlock.HitCosts = table.freeze({
	[TypeDamage.HitCategories.Light] = TypeStamina.Costs.BlockLight,
	[TypeDamage.HitCategories.Medium] = TypeStamina.Costs.BlockMedium,
	[TypeDamage.HitCategories.Heavy] = TypeStamina.Costs.BlockHeavy,
})

return TypeBlock
