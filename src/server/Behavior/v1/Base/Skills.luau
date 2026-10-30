local ServerScriptService = game:GetService("ServerScriptService")
local TypeSkills = require(ServerScriptService.ModNPCServer.Types.v1.TypeSkills)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)

local Skills = {}
Skills.__index = Skills

local FunctionEnum = TypeCharacterFunctions.FunctionEnum

local SkillNames = TypeSkills.Skills
local MAX_LEVEL = TypeSkills.MaxLevel

-- A d20 scaled to the level scale: every face is worth DIE_SCALE points, so a 20 is a 100
local DIE_SIDES = 20
local DIE_SCALE = MAX_LEVEL / DIE_SIDES

-- Level -> the number a roll has to be at or under, interpolated between the points. A level of 100 blocks everything
-- (the highest roll is 100) and 50 is still good, but the curve is steepest between 20 and 50: around 20 success is
-- already rare and below it there is almost nothing.
local SUCCESS_CURVE = {
	{ 0, 0 },
	{ 10, 3 },
	{ 20, 15 },
	{ 30, 35 },
	{ 50, 70 },
	{ 75, 92 },
	{ 100, 100 },
}

local function targetFor(level: number): number
	local previous = SUCCESS_CURVE[1]
	for index = 2, #SUCCESS_CURVE do
		local point = SUCCESS_CURVE[index]
		if level <= point[1] then
			local progress = (level - previous[1]) / (point[1] - previous[1])
			return previous[2] + (point[2] - previous[2]) * progress
		end
		previous = point
	end

	return previous[2]
end

-- Skills that don't exist on the character count as level 0, and anything outside 0-100 is held to it
local function clampLevel(level: any): number
	if type(level) ~= "number" or level ~= level then
		return 0
	end

	return math.clamp(level, 0, MAX_LEVEL)
end

-- Rolls are made against the character's skill levels (Config/Levels). A d20 is rolled and scaled to 0-100, and it
-- succeeds when it lands at or under the target the level gives, times the character's stamina efficiency.
--
-- Rolling for several skills at once (Agility + Strength) averages their levels, so the result stays on the 0-100
-- scale instead of a pair of 50s being a guaranteed success.
function Skills.new(Base: any, character: Model)
	local self = setmetatable({}, Skills)
	self.Base = Base
	self.Character = character
	self.Configuration = Base.Configuration

	return self
end

-- The level (0-100) of a skill. 0 when the character doesn't have it.
function Skills:GetSkillLevel(skill: TypeSkills.Skill): number
	if not SkillNames[skill] then
		warn("Unknown skill:", skill)
		return 0
	end

	return clampLevel(self.Configuration:GetLevelSetting(skill))
end

-- The combined level of the skills: their average
function Skills:GetCombinedLevel(skills: { TypeSkills.Skill }): number
	if #skills == 0 then
		return 0
	end

	local total = 0
	for _, skill in ipairs(skills) do
		total += self:GetSkillLevel(skill)
	end

	return total / #skills
end

-- How well the character does things right now (1 rested, less when exhausted, see Stamina). It scales the target a roll has
-- to reach, so a half as efficient character that would have made it with a target of 45 against a roll of 40 now has 22.5
-- and misses. Runs from rolls, which are a runtime path, so going through CallFunction is safe.
function Skills:_getEfficiency(): number
	local efficiency = self.Base.Functions:CallFunction(FunctionEnum.GetStaminaEfficiency)

	return if type(efficiency) == "number" and efficiency >= 0 then efficiency else 1
end

-- The odds (0-1) of succeeding a roll for the skills. Exact for the d20: the share of its faces at or under the target.
function Skills:GetSkillChance(skills: { TypeSkills.Skill }): number
	local target = targetFor(self:GetCombinedLevel(skills)) * self:_getEfficiency()
	return math.floor(target / DIE_SCALE) / DIE_SIDES
end

function Skills:RollSkills(skills: { TypeSkills.Skill }): TypeSkills.RollResult
	local level = self:GetCombinedLevel(skills)
	local efficiency = self:_getEfficiency()
	local target = targetFor(level) * efficiency
	local natural = math.random(1, DIE_SIDES)
	local roll = natural * DIE_SCALE

	return {
		Success = roll <= target,
		Natural = natural,
		Roll = roll,
		Level = level,
		Target = target,
		Efficiency = efficiency,
		Skills = table.clone(skills),
	}
end

function Skills:RollSkill(skill: TypeSkills.Skill): TypeSkills.RollResult
	return self:RollSkills({ skill })
end

function Skills:Destroy()
	self.Configuration = nil
	self.Base = nil
end

return Skills
