local ServerScriptService = game:GetService("ServerScriptService")
local TypeDistance = require(ServerScriptService.ModNPCServer.Types.v1.TypeDistance)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

local Distance = {}
Distance.__index = Distance

local RangeStates = TypeDistance.RangeStates
local TargettingRanges = TypeTargetting.Ranges
local ENGAGE_STATE_KEY = TypeState.Keys.EngageState
local EngageStateEnum = TypeState.EngageStateEnum

-- How far past the engage distance the target can get before the engagement is over. Reaching the engage distance starts
-- it, so without some room here a target that sits right at the edge (or a strafe that drifts out a little) would hand
-- control back and forth every other tick.
local ENGAGE_EXIT_MARGIN = 4

-- Which Ranges configuration value to hold for each TargettingRange thought setting
local RANGE_SETTINGS = {
	[TargettingRanges.Close] = "CloseEngage",
	[TargettingRanges.Long] = "LongEngage",
}

-- Shared range logic for the tasks. It measures distances through the CharacterAPI and decides where a distance sits
-- against a range we want to hold, so tasks agree on what "in range" means instead of each keeping their own maths.
--
-- A range is an ideal distance and how much closer than that is still fine: [ideal - tooCloseDiff, ideal].
function Distance.new(Base: any, character: Model)
	local self = setmetatable({}, Distance)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Configuration = Base.Configuration

	-- No None in this enum: we start out pursuing, as nothing has been reached yet
	Base.State:Register(ENGAGE_STATE_KEY, EngageStateEnum, EngageStateEnum.Pursuing)

	return self
end

-- Whose job the way to the focus target is. ChaseTargets acts only while Pursuing and Engage only while Engaged, and
-- the one that has control is the one that hands it over (see UpdateEngagement), so they can never both be moving us.
function Distance:GetEngagement(): TypeState.EngageState
	return self.Base.State:Get(ENGAGE_STATE_KEY) :: TypeState.EngageState
end

function Distance:IsPursuing(): boolean
	return self.Base.State:Is(ENGAGE_STATE_KEY, EngageStateEnum.Pursuing)
end

function Distance:IsEngaged(): boolean
	return self.Base.State:Is(ENGAGE_STATE_KEY, EngageStateEnum.Engaged)
end

-- Works out the engagement for a distance from the target (and the engage distance we hold) and sets it. Pursuing
-- becomes Engaged once the distance is no more than the ideal; Engaged becomes Pursuing once it is further past the ideal
-- than the exit margin. Returns the engagement that is now in effect.
function Distance:UpdateEngagement(distance: number, ideal: number): TypeState.EngageState
	local engagement = self:GetEngagement()
	if engagement == EngageStateEnum.Pursuing and distance <= ideal then
		engagement = EngageStateEnum.Engaged
	elseif engagement == EngageStateEnum.Engaged and distance > ideal + ENGAGE_EXIT_MARGIN then
		engagement = EngageStateEnum.Pursuing
	end

	self.Base.State:Set(ENGAGE_STATE_KEY, engagement)

	return engagement
end

-- Back to pursuing, for when there is no one to engage any more
function Distance:ResetEngagement()
	-- an Engage task going down with the character can get here after we are gone
	if not self.Base then
		return
	end

	self.Base.State:Set(ENGAGE_STATE_KEY, EngageStateEnum.Pursuing)
end

-- Where a distance sits against the range. Static: it only compares numbers, so it costs no request.
-- The limits are inclusive, a distance exactly on one is still in range.
function Distance.Classify(distance: number, ideal: number, tooCloseDiff: number?): TypeDistance.RangeState
	if distance > ideal then
		return RangeStates.TooFar
	end

	if distance < ideal - math.max(tooCloseDiff or 0, 0) then
		return RangeStates.TooClose
	end

	return RangeStates.InRange
end

-- Whether a distance is more than farDiff past the ideal, e.g. far enough out that it is worth sprinting
function Distance.IsFarPast(distance: number, ideal: number, farDiff: number): boolean
	return distance - ideal > math.max(farDiff, 0)
end

-- The distance we want to hold from a target for a targetting range (Close or Long), nil if it isn't configured
function Distance:GetEngageDistance(targettingRange: TypeTargetting.TargettingRange): number?
	local rangeSetting = RANGE_SETTINGS[targettingRange]
	if not rangeSetting then
		return nil
	end

	local distance = self.Configuration:GetRange(rangeSetting)
	return if type(distance) == "number" then distance else nil
end

-- How much closer than the engage distance still counts as in range (TooCloseDiff), 0 if unconfigured
function Distance:GetTooCloseDiff(): number
	local diff = self.Configuration:GetRange("TooCloseDiff")
	return if type(diff) == "number" then math.max(diff :: number, 0) else 0
end

-- Studs between us and a character, nil if either has no root part
function Distance:GetDistanceTo(target: Model): number?
	return self.CharacterAPI:GetDistanceTo(target)
end

-- Studs between us and a point in the world, nil if we have no root part
function Distance:GetDistanceToPosition(position: Vector3): number?
	return self.CharacterAPI:GetDistanceToPosition(position)
end

-- Whether the target is no further than `range` studs. False when the distance can't be measured.
function Distance:IsWithin(target: Model, range: number): boolean
	local distance = self:GetDistanceTo(target)
	return distance ~= nil and distance <= range
end

-- Where the target sits against the range, nil when the distance can't be measured
function Distance:GetRangeState(target: Model, ideal: number, tooCloseDiff: number?): TypeDistance.RangeState?
	local distance = self:GetDistanceTo(target)
	if not distance then
		return nil
	end

	return Distance.Classify(distance, ideal, tooCloseDiff)
end

-- Whether the target is inside the range: no further than ideal, and no closer than tooCloseDiff under it.
-- False when the distance can't be measured.
function Distance:IsInRange(target: Model, ideal: number, tooCloseDiff: number?): boolean
	return self:GetRangeState(target, ideal, tooCloseDiff) == RangeStates.InRange
end

function Distance:Destroy()
	self.CharacterAPI = nil
	self.Configuration = nil
	self.Base = nil
end

return Distance
