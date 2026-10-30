local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

local Abilities = {}
Abilities.__index = Abilities

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Keys = TypeState.Keys
local HealthStatusEnum = TypeState.HealthStatusEnum
local AirStateEnum = TypeState.AirStateEnum
local AttackStateEnum = TypeState.AttackStateEnum
local StaggerStateEnum = TypeState.StaggerStateEnum
local BlockStateEnum = TypeState.BlockStateEnum
local DefenseStateEnum = TypeState.DefenseStateEnum
local BlockBreakStateEnum = TypeState.BlockBreakStateEnum

-- A rule is a list of conditions on states, all of which have to hold:
--   Require   the state has to be one of these values
--   Forbid    the state must not be any of these values
-- A state that isn't registered on this character puts no condition on it (a mod's state may not exist everywhere).
type Rule = {
	Require: { [string]: { string } }?,
	Forbid: { [string]: { string } }?,
}

local function merge(...: { [string]: { string } }): { [string]: { string } }
	local merged = {}
	for _, conditions in { ... } do
		for key, values in conditions do
			merged[key] = values
		end
	end

	return merged
end

-- Nobody does anything once dead
local NOT_DEAD = { [Keys.HealthStatus] = { HealthStatusEnum.Dead } }
local NOT_STAGGERED = { [Keys.StaggerState] = { StaggerStateEnum.Staggered, StaggerStateEnum.Launched } }
local NOT_ATTACKING = { [Keys.AttackState] = { AttackStateEnum.Swinging } }
local NOT_BLOCKING = { [Keys.BlockState] = { BlockStateEnum.Blocking } }
-- A broken guard stays down until the character has recovered from the exhaustion the break left it in
local NOT_BLOCK_BROKEN = { [Keys.BlockBreakState] = { BlockBreakStateEnum.Active } }
-- A character dealing with a hit it saw coming (a dodge timed to it, a guard raised for it) doesn't swing into it
local NOT_REACTING = { [Keys.DefenseState] = { DefenseStateEnum.Reacting } }
local GROUNDED = { [Keys.AirState] = { AirStateEnum.Grounded } }

-- The activities with a rule of their own. CanBeEvasive is built from these instead, see below.
local RULES: { [string]: Rule } = {
	-- Moving needs the ground under us, and a character that is staggered or launched is not in control of itself
	[FunctionEnum.CanMove] = {
		Require = GROUNDED,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED),
	},
	-- Attacking is moving's rule, and one attack at a time (which includes its debounce). Not while defending against a hit
	-- either: the swing would take the arms from a guard raised for it, or the dodge waiting for it.
	[FunctionEnum.CanAttack] = {
		Require = GROUNDED,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_REACTING),
	},
	-- A dodge can happen in the air, but not in the middle of an attack or while staggered
	[FunctionEnum.CanDodge] = {
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING),
	},
	-- A block raises the arms, which an attack in progress is using, and one block at a time. Not with a broken guard either.
	[FunctionEnum.CanBlock] = {
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_BLOCKING, NOT_BLOCK_BROKEN),
	},
}

function Abilities.new(base: any)
	local self = setmetatable({}, Abilities)
	self.Base = base
	self.State = base.State

	return self
end

-- The first condition of `rule` that fails, as a short reason, or nil if all of them hold
function Abilities:_findBlock(rule: Rule): string?
	for key, allowed in rule.Require or {} do
		local value = self.State:Get(key)
		if value ~= nil and not table.find(allowed, value) then
			return key .. " is " .. value
		end
	end

	for key, forbidden in rule.Forbid or {} do
		local value = self.State:Get(key)
		if value ~= nil and table.find(forbidden, value) then
			return key .. " is " .. value
		end
	end

	return nil
end

-- Returns whether the activity is allowed and, if it isn't, what is in the way
function Abilities:_check(activity: string): (boolean, string?)
	local reason = self:_findBlock(RULES[activity])
	return reason == nil, reason
end

function Abilities:CanMove(): (boolean, string?)
	return self:_check(FunctionEnum.CanMove)
end

function Abilities:CanAttack(): (boolean, string?)
	return self:_check(FunctionEnum.CanAttack)
end

function Abilities:CanBlock(): (boolean, string?)
	return self:_check(FunctionEnum.CanBlock)
end

-- Rules don't look at the direction, but a mod hooking the function can
function Abilities:CanDodge(_direction: string?): (boolean, string?)
	return self:_check(FunctionEnum.CanDodge)
end

-- Being evasive (strafing, dodging) takes being able to move and to dodge. Asked through the functions so a mod that
-- changes either one changes this too.
function Abilities:CanBeEvasive(): (boolean, string?)
	local functions = self.Base.Functions

	local canMove, moveReason = functions:CallFunction(FunctionEnum.CanMove)
	if not canMove then
		return false, moveReason
	end

	local canDodge, dodgeReason = functions:CallFunction(FunctionEnum.CanDodge)
	if not canDodge then
		return false, dodgeReason
	end

	return true
end

function Abilities:Destroy()
	self.Base = nil
	self.State = nil
end

return Abilities
