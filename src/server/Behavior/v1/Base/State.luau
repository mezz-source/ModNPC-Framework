local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

local State = {}
State.__index = State

local StateEvents = TypeCharacterEvents.Names.State

type StateEnum = TypeState.StateEnum

-- Returns the set of values in `enum`, or nil if it isn't a usable enum (empty, or holds non-string values)
local function enumValues(enum: any): { [string]: boolean }?
	if type(enum) ~= "table" or next(enum) == nil then
		return nil
	end

	local values = {}
	for _, value in pairs(enum) do
		if type(value) ~= "string" then
			return nil
		end
		values[value] = true
	end

	return values
end

-- Nothing is registered here; every state is registered by the module that owns it
function State.new(Base: any)
	local self = setmetatable({}, State)
	self.Base = Base
	self.Character = Base.Character
	-- [key] = { Values = set of valid values, Value = current value }
	self.States = {}

	return self
end

-- `initial` is the starting value; when left out the enum's `None` is used, so an enum without one must pass it.
-- Returns false if the key is taken or the enum/initial value is invalid.
function State:Register(key: string, enum: StateEnum, initial: string?): boolean
	if type(key) ~= "string" then
		warn("State key must be a string for character:", self.Character.Name)
		return false
	end

	if self.States[key] then
		warn("State is already registered:", key, "for character:", self.Character.Name)
		return false
	end

	local values = enumValues(enum)
	if not values then
		warn("Invalid enum for state:", key, "for character:", self.Character.Name)
		return false
	end

	local startValue = initial or enum.None
	if not startValue or not values[startValue] then
		warn("Invalid initial value for state:", key, startValue, "for character:", self.Character.Name)
		return false
	end

	self.States[key] = {
		Values = values,
		Value = startValue,
	}

	return true
end

function State:IsRegistered(key: string): boolean
	return self.States[key] ~= nil
end

-- Nil if the state was never registered (a mod's state may not exist on every character)
function State:Get(key: string): string?
	local entry = self.States[key]
	return entry and entry.Value
end

function State:Is(key: string, value: string): boolean
	local entry = self.States[key]
	return entry ~= nil and entry.Value == value
end

-- Dispatches CharacterStateChanged when the value actually changes. Returns false if the state isn't registered or
-- the value isn't in its enum.
function State:Set(key: string, value: string): boolean
	local entry = self.States[key]
	if not entry then
		warn("State is not registered:", key, "for character:", self.Character.Name)
		return false
	end

	if not entry.Values[value] then
		warn("Invalid value for state:", key, value, "for character:", self.Character.Name)
		return false
	end

	local previous = entry.Value
	if previous == value then
		return true
	end

	entry.Value = value
	self.Base.Events:Dispatch(StateEvents.Changed, { Key = key, Old = previous, New = value })

	-- TODO: debug only, remove once states are verified
	local snapshot = {}
	for stateKey, stateEntry in pairs(self.States) do
		snapshot[stateKey] = stateEntry.Value
	end

	return true
end

function State:Destroy()
	self.States = {}
	self.Base = nil
end

return State
