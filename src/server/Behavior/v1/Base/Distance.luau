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

-- How long a bulk reading is reused. The passes of one search tick (who is in range, who is the nearest, which friend is
-- closest) run within a frame of each other, so they share what the first one read; at a walking pace this is well under a
-- stud of drift. Pass a maxAge of 0 to a bulk measure for a reading that can't be reused.
local MEASURE_LIFETIME = 0.05

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

	-- The bulk readings of the moment: where we were, and how far each character measured was. Replaced as a whole once
	-- it is older than the lifetime, so it never holds on to characters that left.
	self.Measurements = nil :: { Taken: number, Origin: Vector3?, Distances: TypeDistance.Distances }?

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

-- The farthest a character can be and still be noticed (Ranges.Provoke), nil if unconfigured (no limit)
function Distance:GetProvokeRange(): number?
	local range = self.Configuration:GetRange("Provoke")
	return if type(range) == "number" then range else nil
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

-- The measurements to add to: the current ones while they are young enough, new ones (with our position read again) if not
function Distance:_getMeasurements(maxAge: number?)
	local now = os.clock()
	local measurements = self.Measurements
	if measurements and now - measurements.Taken <= (maxAge or MEASURE_LIFETIME) then
		return measurements
	end

	local handle = self.CharacterAPI:GetHandle()
	measurements = {
		Taken = now,
		Origin = if handle then handle:GetPosition() else nil,
		Distances = {},
	}
	self.Measurements = measurements
	return measurements
end

-- Studs between us and every one of the targets, keyed by character; those that can't be measured (no root part) are left
-- out. Our position is read once and each target's once, off its Handle when it has one; the ones without a handle are
-- looked up together in a single request. Targets measured within maxAge seconds are not read again.
function Distance:Measure(targets: { TypeDistance.Measurable }, maxAge: number?): TypeDistance.Distances
	local measurements = self:_getMeasurements(maxAge)
	local origin = measurements.Origin
	local measured = measurements.Distances
	local result: TypeDistance.Distances = {}
	if not origin then
		return result
	end

	local function measureFrom(character: Model, handle: any)
		local position = handle:GetPosition()
		if position then
			local distance = (origin - position).Magnitude
			measured[character] = distance
			result[character] = distance
		end
	end

	local unhandled: { Model } = {}
	for _, target in targets do
		local character = target.Character
		local known = measured[character]
		if known then
			result[character] = known
		elseif target.Handle then
			measureFrom(character, target.Handle)
		else
			table.insert(unhandled, character)
		end
	end

	if #unhandled > 0 then
		for character, handle in self.CharacterAPI:GetHandles(unhandled) do
			measureFrom(character, handle)
		end
	end

	return result
end

-- The targets no further than `range` studs, in the order they were given
function Distance:FilterWithin(targets: { any }, range: number, maxAge: number?): { any }
	local distances = self:Measure(targets, maxAge)
	local within = {}
	for _, target in targets do
		local distance = distances[target.Character]
		if distance and distance <= range then
			table.insert(within, target)
		end
	end
	return within
end

-- The target with the lowest (or highest) distance and that distance. Ties go to the earlier target.
local function pickByDistance(self: any, targets: { any }, maxAge: number?, preferLowest: boolean): (any?, number?)
	local distances = self:Measure(targets, maxAge)
	local best: any? = nil
	local bestDistance: number? = nil
	for _, target in targets do
		local distance = distances[target.Character]
		if distance and (bestDistance == nil or (if preferLowest then distance < bestDistance else distance > bestDistance)) then
			best = target
			bestDistance = distance
		end
	end
	return best, bestDistance
end

function Distance:Nearest(targets: { any }, maxAge: number?): (any?, number?)
	return pickByDistance(self, targets, maxAge, true)
end

function Distance:Furthest(targets: { any }, maxAge: number?): (any?, number?)
	return pickByDistance(self, targets, maxAge, false)
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
	self.Measurements = nil
	self.CharacterAPI = nil
	self.Configuration = nil
	self.Base = nil
end

return Distance
