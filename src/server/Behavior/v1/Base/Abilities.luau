local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypePermissions = require(ServerScriptService.ModNPCServer.Types.v1.TypePermissions)

local Abilities = {}
Abilities.__index = Abilities

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Permissions = TypePermissions.Names
local Keys = TypeState.Keys
local HealthStatusEnum = TypeState.HealthStatusEnum
local AirStateEnum = TypeState.AirStateEnum
local AttackStateEnum = TypeState.AttackStateEnum
local StaggerStateEnum = TypeState.StaggerStateEnum
local BlockStateEnum = TypeState.BlockStateEnum
local DefenseStateEnum = TypeState.DefenseStateEnum
local BlockBreakStateEnum = TypeState.BlockBreakStateEnum
local ParryStateEnum = TypeState.ParryStateEnum
local BounceStateEnum = TypeState.BounceStateEnum
local WeaponStateEnum = TypeState.WeaponStateEnum

-- A rule is a list of conditions on states, all of which have to hold:
--   Permission  the permission of Config/Permissions that has to allow the activity (see TypePermissions)
--   Require     the state has to be one of these values
--   Forbid      the state must not be any of these values
-- A state that isn't registered on this character puts no condition on it (a mod's state may not exist everywhere).
type Rule = {
	Permission: string?,
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
-- A parry holds the character from the moment it starts until its animation is over, or a hit is parried
local NOT_PARRYING = { [Keys.ParryState] = { ParryStateEnum.Parrying, ParryStateEnum.Recovering } }
-- An attack that bounced leaves the character unable to attack until the bounce animation is over
local NOT_BOUNCING = { [Keys.BounceState] = { BounceStateEnum.Bouncing } }
-- A character dealing with a hit it saw coming (a dodge timed to it, a guard raised for it) doesn't swing into it
local NOT_REACTING = { [Keys.DefenseState] = { DefenseStateEnum.Reacting } }
local GROUNDED = { [Keys.AirState] = { AirStateEnum.Grounded } }
local HAS_WEAPON = { [Keys.WeaponState] = { WeaponStateEnum.Equipped } }

-- The activities with a rule of their own. CanBeEvasive is built from these instead, see below.
local RULES: { [string]: Rule } = {
	-- Moving needs the ground under us, and a character that is staggered or launched is not in control of itself
	[FunctionEnum.CanMove] = {
		Permission = Permissions.CanMove,
		Require = GROUNDED,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_PARRYING),
	},
	-- Attacking is moving's rule, and one attack at a time (which includes its debounce). Not while defending against a hit
	-- either: the swing would take the arms from a guard raised for it, or the dodge waiting for it. Nor until a bounce is over.
	[FunctionEnum.CanAttack] = {
		Permission = Permissions.CanAttack,
		Require = GROUNDED,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_REACTING, NOT_PARRYING, NOT_BOUNCING),
	},
	-- A dodge can happen in the air, but not in the middle of an attack or while staggered
	[FunctionEnum.CanDodge] = {
		Permission = Permissions.CanDodge,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_PARRYING),
	},
	-- A block needs a weapon in hand (it holds the block animations, armed or not). It raises the arms, which an attack in
	-- progress is using, and one block at a time. Not with a broken guard either.
	[FunctionEnum.CanBlock] = {
		Permission = Permissions.CanBlock,
		Require = HAS_WEAPON,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_BLOCKING, NOT_BLOCK_BROKEN, NOT_PARRYING),
	},
	-- A parry needs a weapon in hand too (it holds the parry animations and sounds), and the arms an attack is using. One at
	-- a time. It is the risky choice: a character with its guard up relies on that instead.
	[FunctionEnum.CanParry] = {
		Permission = Permissions.CanParry,
		Require = HAS_WEAPON,
		Forbid = merge(NOT_DEAD, NOT_STAGGERED, NOT_ATTACKING, NOT_BLOCKING, NOT_PARRYING),
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
	if rule.Permission and not self.Base.Configuration:IsPermitted(rule.Permission) then
		return TypePermissions.Folder .. "/" .. rule.Permission .. " is off"
	end

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

function Abilities:CanParry(): (boolean, string?)
	return self:_check(FunctionEnum.CanParry)
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
