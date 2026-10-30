local TypeSkills = {}

-- The names of the NumberValues in a ModNPC's Config/Levels folder
export type Skill = "Agility" | "Intellect" | "Strength" | "Vitality"

TypeSkills.Skills = table.freeze({
	Agility = "Agility",
	Intellect = "Intellect",
	Strength = "Strength",
	-- Doesn't keep a hit from landing like the others, it softens the stagger or launch that comes with it
	Vitality = "Vitality",
})

-- The most a level (and the scale a roll is made on) can be
TypeSkills.MaxLevel = 100

-- Everything about one roll, so callers can look at more than pass/fail (e.g. how badly it was missed)
export type RollResult = {
	Success: boolean,
	-- the d20 as rolled, 1 to 20
	Natural: number,
	-- the d20 scaled to the 0-100 level scale (Natural * 5)
	Roll: number,
	-- the level of the skills rolled for, 0-100 (combined skills are averaged)
	Level: number,
	-- the number the roll has to be at or under, 0-100. Comes from Level through the success curve, times the Efficiency.
	Target: number,
	-- the character's stamina efficiency when it rolled: 1 when rested, less when exhausted
	Efficiency: number,
	Skills: { Skill },
}

return TypeSkills
