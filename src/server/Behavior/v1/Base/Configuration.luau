local ServerScriptService = game:GetService("ServerScriptService")
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

local Configuration = {}
Configuration.__index = Configuration

local Modules = TypeAPIFunctions.Modules
local Functions = TypeAPIFunctions.Functions.ContentDelivery
local ConfigEvents = TypeCharacterEvents.Names.Configuration

local function getPath(key: string | { string }): { string }
	if type(key) == "table" then
		return key
	end

	return string.split(string.gsub(key, "%.", "/"), "/")
end

local function findValue(index: any, path: { string }): any
	local current = index
	for _, name in ipairs(path) do
		if type(current) ~= "table" then
			return nil
		end
		current = current[name]
	end

	return current
end

function Configuration.new(Base, character: Model)
	local self = setmetatable({}, Configuration)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.EventSubscriptions = {
		Base.Events:Subscribe(ConfigEvents.ConfigurationUpdated, function(payload)
			self:_update(payload)
		end),
		Base.Events:Subscribe(ConfigEvents.ConfigurationInvalidated, function()
			self:_refresh()
		end),
	}
	-- listen before reading the index so no external change slips between the two
	self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.WatchConfiguration, { character })
	self.Data = self.CharacterAPI:RequestAPIData(
		Modules.ContentDelivery,
		Functions.GetConfigurationIndex,
		{ character }
	) or {}

	print("Configuration data loaded:", self.Data)

	return self
end

function Configuration:Destroy()
	for _, subscription in ipairs(self.EventSubscriptions) do
		subscription.Unsubscribe()
	end
	self.EventSubscriptions = {}
	if self.CharacterAPI and self.Character then
		self:Unwatch()
	end
	self.Base = nil
	self.Character = nil
	self.CharacterAPI = nil
end

-- Stops listening for external configuration changes (called when the character dies)
function Configuration:Unwatch()
	self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.UnwatchConfiguration, { self.Character })
end

-- Calls callback(newValue, previousValue) whenever the setting at key changes (set through the API or externally).
-- Our own update subscription is registered first, so Get already returns the new value inside the callback.
function Configuration:Observe(key: string | { string }, callback: (any, any) -> ())
	local path = getPath(key)
	return self.Base.Events:Subscribe(ConfigEvents.ConfigurationUpdated, function(payload)
		if type(payload) ~= "table" or type(payload.Path) ~= "table" or #payload.Path ~= #path then
			return
		end

		for position, name in ipairs(path) do
			if payload.Path[position] ~= name then
				return
			end
		end
		callback(payload.Value, payload.Previous)
	end)
end

function Configuration:GetData()
	return self.Data
end

function Configuration:GetFolderValues(key: string)

end

function Configuration:GetEntry(key: string | { string })
	return findValue(self.Data, getPath(key))
end

function Configuration:Get(key: string | { string }): any
	local entry = self:GetEntry(key)
	return entry and entry.Value or nil
end

function Configuration:GetDamageSetting(settingName: string): any
	return self:Get({ "Damage", settingName })
end

function Configuration:GetThoughtSetting(settingName: string): any
	return self:Get({ "ThoughtProcess", settingName })
end

function Configuration:GetStartTasks(): {string}
	local startTasks = self.Data.StartTasks
	local tasks = {}
	
	for name, _ in pairs(startTasks) do
		table.insert(tasks, name)
	end

	return tasks
end

function Configuration:GetRange(settingName: string): any
	return self:Get({ "Ranges", settingName })
end

function Configuration:GetLevelSetting(settingName: string): any
	return self:Get({ "Levels", settingName })
end

function Configuration:GetMovementSetting(settingName: string): any
	return self:Get({ "Movement", settingName })
end

function Configuration:_update(payload)
	if type(payload) ~= "table" or type(payload.Path) ~= "table" then
		return
	end

	local path = payload.Path
	local parent = self.Data
	for position = 1, #path - 1 do
		local name = path[position]
		if type(parent[name]) ~= "table" then
			parent[name] = {}
		end
		parent = parent[name]
	end

	local settingName = path[#path]
	parent[settingName] = {
		Name = settingName,
		Type = payload.Type,
		Value = payload.Value,
	}
end

function Configuration:_refresh()
	self.Data = self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.GetConfigurationIndex, {
		self.Character,
	}) or {}
end

return Configuration
