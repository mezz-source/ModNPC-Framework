local TypeStamina = {}

-- The things stamina is spent on. Each has a price in the character's Config/Stamina (see CostSettings).
export type Cost =
	"Dodge"
	| "LightAttack"
	| "MediumAttack"
	| "HeavyAttack"
	| "Sprint"
	| "BlockLight"
	| "BlockMedium"
	| "BlockHeavy"

TypeStamina.Costs = table.freeze({
	Dodge = "Dodge",
	Stagger = "Stagger",
	LightAttack = "LightAttack",
	MediumAttack = "MediumAttack",
	HeavyAttack = "HeavyAttack",
	-- Priced per second of sprinting, so whoever charges it multiplies by the time
	Sprint = "Sprint",
	-- What it takes to hold a block against a hit of that weight (see Block)
	BlockLight = "BlockLight",
	BlockMedium = "BlockMedium",
	BlockHeavy = "BlockHeavy",
})

-- The settings of a character's Config/Stamina folder that the Stamina module reads. A setting the folder doesn't have falls
-- back to the default in Stamina.
TypeStamina.Settings = table.freeze({
	-- The most stamina the character can have, and what it starts with
	MaxStamina = "MaxStamina",
	-- Multiplies every price, so a character that tires easily has more than 1 and one that doesn't has less
	ConsumptionMultiplier = "ConsumptionMultiplier",
	-- Stamina gained per second while the character is allowed to regenerate (not attacking, staggered or sprinting)
	RegenerationRate = "RegenerationRate",
	-- Multiplies the RegenerationRate, so a character that recovers quickly has more than 1 and one that doesn't has less
	RegenerationMultiplier = "RegenerationMultiplier",
	-- The character is exhausted once its stamina is at or below this (an amount of stamina, like the prices)
	ExhaustionThreshold = "ExhaustionThreshold",
	-- ...and stays exhausted until its stamina is back at or above this
	RecoverThreshold = "RecoverThreshold",
})

-- Which setting of Config/Stamina holds the price of each cost, before the ConsumptionMultiplier. A cost whose setting the
-- folder doesn't have is free.
TypeStamina.CostSettings = table.freeze({
	[TypeStamina.Costs.Dodge] = "DodgeConsumption",
	[TypeStamina.Costs.LightAttack] = "LightAttackConsumption",
	[TypeStamina.Costs.MediumAttack] = "MediumAttackConsumption",
	[TypeStamina.Costs.HeavyAttack] = "HeavyAttackConsumption",
	[TypeStamina.Costs.Sprint] = "SprintConsumption",
	[TypeStamina.Costs.Stagger] = "StaggerConsumption",
	[TypeStamina.Costs.BlockLight] = "BlockLightConsumption",
	[TypeStamina.Costs.BlockMedium] = "BlockMediumConsumption",
	[TypeStamina.Costs.BlockHeavy] = "BlockHeavyConsumption",
})

TypeStamina.Folder = "Stamina"

-- The overhead bar the character's stamina is shown on
TypeStamina.Bar = table.freeze({
	Name = "Stamina",
	-- A slim bar under the health bar
	Size = 0.15,
	LayoutOrder = 1,
	FillColor = Color3.fromRGB(55, 108, 255),
	FlashColor = Color3.fromRGB(29, 18, 88),
	-- The trail behind the fill that shows what was just spent
	ChangeFillColor = Color3.fromRGB(14, 3, 180),
})

return TypeStamina
