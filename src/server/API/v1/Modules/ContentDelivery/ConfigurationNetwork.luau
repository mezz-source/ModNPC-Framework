local ServerScriptService = game:GetService("ServerScriptService")
local ConfigurationNetwork = {}

local InstanceSearch = require(ServerScriptService.ModNPCServer.Util.InstanceSearch)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)
local ModFolder = require(script.Parent.ModFolder)

type ConfigurationIndex = TypeCDN.ConfigurationIndex
type ConfigurationValue = TypeCDN.ConfigurationValue
type ModuleResponse = TypeModuleResponse.ModuleResponse

local contentDeliveryNetwork
local configurationIndexes: { [Model]: ConfigurationIndex } = {}

-- Per-character listeners for changes made outside of this module (e.g. a studio script editing a ValueBase).
-- Known holds the last value we announced for each setting, which is how our own writes (setSetting)
-- are told apart from external ones so an update event is never sent twice.
type Watcher = {
	Folder: Folder,
	Known: { [Instance]: any },
	ValueConnections: { [Instance]: RBXScriptConnection },
	Connections: { RBXScriptConnection },
}
local watchers: { [Model]: Watcher } = {}

local ConfigEvents = TypeCharacterEvents.Names.Configuration

local function response(success: boolean, message: string, data: any?): ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = success and TypeRequests.Enums.StatusCode.Success or TypeRequests.Enums.StatusCode.Conflict,
		Message = message,
		Data = data,
	}
end

local function getConfigurationFolder(character: Model): Folder?
	local configurationResponse = contentDeliveryNetwork.getConfigurationFolder(character)
	if not configurationResponse.Success or not configurationResponse.Data then
		return nil
	end

	return configurationResponse.Data
end

local function normalizeValue(instance: Instance): ConfigurationValue?
	local success, value = InstanceSearch.getPrimitiveValue(instance)
	if not success then
		return nil
	end

	return {
		Name = instance.Name,
		Type = instance.ClassName,
		Value = value,
	}
end

local function buildIndex(folder: Folder): ConfigurationIndex
	local index: ConfigurationIndex = {}

	for _, child in ipairs(folder:GetChildren()) do
		local value = normalizeValue(child)
		if value then
			index[child.Name] = value
		elseif child:IsA("Folder") then
			index[child.Name] = buildIndex(child)
		end
	end

	return index
end

local function getIndexedValue(index: ConfigurationIndex, path: { string }): ConfigurationValue?
	local current: ConfigurationIndex | ConfigurationValue = index

	for position, name in ipairs(path) do
		local value = current[name]
		if not value then
			return nil
		end

		if position == #path then
			if value.Value == nil then
				return nil
			end
			return value :: ConfigurationValue
		end

		current = value :: ConfigurationIndex
	end

	return nil
end

local function getRecursiveValue(folder: Folder, settingName: string): (ConfigurationValue?, string?)
	local result = InstanceSearch.find(folder, settingName, "ValueBase")
	if result.Status ~= "Found" or not result.Instance then
		return nil, result.Status
	end

	return normalizeValue(result.Instance), nil
end

local function getValue(character: Model, path: { string }): (ConfigurationValue?, string?)
	local configurationFolder = getConfigurationFolder(character)
	if not configurationFolder then
		return nil, "NotFound"
	end

	local index = configurationIndexes[character]
	if not index then
		index = buildIndex(configurationFolder)
		configurationIndexes[character] = index
	end

	local indexedValue = getIndexedValue(index, path)
	if indexedValue then
		return indexedValue, nil
	end

	local parentFolder = configurationFolder
	for position = 1, #path - 1 do
		local child = parentFolder:FindFirstChild(path[position])
		if not child or not child:IsA("Folder") then
			parentFolder = configurationFolder
			break
		end
		parentFolder = child
	end

	local fallbackValue, fallbackStatus = getRecursiveValue(parentFolder, path[#path])
	if fallbackValue then
		return fallbackValue, nil
	end

	return nil, fallbackStatus
end

local function getStartTasks(character: Model): (boolean, {string})
	local configurationFolder = getConfigurationFolder(character)
	if not configurationFolder then
		warn("Missing configuration folder")
		return false, {}
	end	

	local StartTasks = configurationFolder:FindFirstChild("StartTasks")
	if not StartTasks then
		warn("Missing StartTasks folder")
		return false, {}
	end

	local startTasks: {string} = {}

	for _, child in ipairs(StartTasks:GetChildren()) do
		if not child:IsA("ValueBase") then
			warn(child, "in start tasks is not a usable value")
			continue
		end

		table.insert(startTasks, child.Name)
	end

	return true, startTasks
end

local function getDispositionValues(character: Model, dispositionName: string): ({ [string]: number }?, string)
	local configurationFolder = getConfigurationFolder(character)
	if not configurationFolder then
		warn("Missing configuration folder")
		return nil, "Missing config folder"
	end

	local Disposition = configurationFolder:FindFirstChild("Disposition")
	if not Disposition then
		warn("Disposition folder is missing")
		return nil, "Missing Disposition folder"
	end

	local folderValue = Disposition:FindFirstChild(dispositionName)
	if not folderValue then
		warn("No disposition value called", dispositionName, "in config folder")
		return nil, "Couldn't find disposition value for " .. dispositionName
	end

	local values: {[string]: number} = {}
	for _, value in ipairs(folderValue:GetChildren()) do
		if not value:IsA("NumberValue") then
			warn(value.Name, "is not a number value inside the", folderValue.Name, "disposition folder")
			continue
		end

		values[value.Name] = value.Value
	end

	return values, "Values found"
end

local function getRelativePath(folder: Folder, instance: Instance): { string }?
	local path = {}
	local current: Instance? = instance
	while current and current ~= folder do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	if not current then
		return nil
	end

	return path
end

local function announce(character: Model, eventName: string, payload: any?)
	local eventResponse = CharacterUtility.sendEvent(character, eventName, payload)
	if not eventResponse.Success then
		warn("Configuration event", eventName, "was not delivered to", character.Name, "-", eventResponse.Message)
	end
end

local function connectValue(character: Model, watcher: Watcher, instance: Instance)
	if watcher.ValueConnections[instance] then
		return
	end

	local success, value = InstanceSearch.getPrimitiveValue(instance)
	if not success then
		return
	end

	watcher.Known[instance] = value
	watcher.ValueConnections[instance] = (instance :: ValueBase).Changed:Connect(function()
		local valid, newValue = InstanceSearch.getPrimitiveValue(instance)
		local previous = watcher.Known[instance]
		if not valid or newValue == previous then
			-- unreadable, or a write we already announced (setSetting records it before writing)
			return
		end

		local path = getRelativePath(watcher.Folder, instance)
		if not path then
			print("couldn't find path")
			return
		end

		watcher.Known[instance] = newValue
		configurationIndexes[character] = nil

		announce(character, ConfigEvents.ConfigurationUpdated, {
			Path = path,
			Previous = previous,
			Value = newValue,
			Type = instance.ClassName,
		})
	end)
end

local function disconnectValue(watcher: Watcher, instance: Instance)
	local connection = watcher.ValueConnections[instance]
	if connection then
		connection:Disconnect()
	end
	watcher.ValueConnections[instance] = nil
	watcher.Known[instance] = nil
end

local function unwatch(character: Model)
	local watcher = watchers[character]
	if not watcher then
		return
	end

	watchers[character] = nil
	configurationIndexes[character] = nil

	for _, connection in ipairs(watcher.Connections) do
		connection:Disconnect()
	end
	for _, connection in pairs(watcher.ValueConnections) do
		connection:Disconnect()
	end
end

local function watch(character: Model): boolean
	if watchers[character] then
		return true
	end

	local folder = getConfigurationFolder(character)
	if not folder then
		return false
	end

	local watcher: Watcher = {
		Folder = folder,
		Known = {},
		ValueConnections = {},
		Connections = {},
	}
	watchers[character] = watcher

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("ValueBase") then
			connectValue(character, watcher, descendant)
		end
	end

	-- the structure changed, so cached indexes (ours and the character's) are stale
	local function structureChanged()
		configurationIndexes[character] = nil
		announce(character, ConfigEvents.ConfigurationInvalidated)
	end

	table.insert(
		watcher.Connections,
		folder.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ValueBase") then
				connectValue(character, watcher, descendant)
			end
			structureChanged()
		end)
	)
	table.insert(
		watcher.Connections,
		folder.DescendantRemoving:Connect(function(descendant)
			disconnectValue(watcher, descendant)
			structureChanged()
		end)
	)

	-- the connection ends with the character
	table.insert(
		watcher.Connections,
		character.Destroying:Connect(function()
			unwatch(character)
		end)
	)

	return true
end

function ConfigurationNetwork.init(network)
	contentDeliveryNetwork = network

	-- This is a bit of a nasty depend chain, but configuration knows the game here
	-- FIX-ME: there's gotta be a better way of doing this
	CharacterUtility.setTeamGetter(function(character: Model): TypeModuleResponse.ModuleResponse
		return ConfigurationNetwork.getTeamSetting(character, "TeamName")
	end)

end

-- This module serves ModNPC characters, so its Config directory is held to the ModNPC schema.
-- Other mod folder kinds validate their own Config directories through ModFolder.
function ConfigurationNetwork.validateConfigurationFolder(configurationFolder: Folder): (boolean, string)
	return ModFolder.validateSchema(ModFolder.Kinds.ModNPC, configurationFolder)
end

function ConfigurationNetwork.getConfigurationIndex(character: Model): ModuleResponse
	local configurationFolder = getConfigurationFolder(character)
	if not configurationFolder then
		return response(false, "Configuration folder not found")
	end

	local index = buildIndex(configurationFolder)
	configurationIndexes[character] = index
	return response(true, "Configuration index generated", index)
end

function ConfigurationNetwork.getConfigurationSchema(): ModuleResponse
	local schema = ModFolder.getSchema(ModFolder.Kinds.ModNPC)
	if not schema then
		return response(false, "Base configuration schema not found")
	end

	return response(true, "Configuration schema retrieved", buildIndex(schema :: Folder))
end

function ConfigurationNetwork.getSetting(character: Model, path: { string }): ModuleResponse
	local value, status = getValue(character, path)
	if not value then
		return response(
			false,
			"Configuration setting " .. table.concat(path, "/") .. " " .. string.lower(status or "not found")
		)
	end

	return response(true, "Configuration setting retrieved", value)
end

function ConfigurationNetwork.getDamageSetting(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "Damage", settingName })
end

function ConfigurationNetwork.getLevelSetting(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "Levels", settingName })
end

function ConfigurationNetwork.getMovementSetting(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "Movement", settingName })
end

function ConfigurationNetwork.getThoughtSetting(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "ThoughtProcess", settingName })
end

function ConfigurationNetwork.getTeamSetting(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "Team", settingName })
end

function ConfigurationNetwork.getStartTasks(character: Model, settingName: string): ModuleResponse
	local success, taskResponse = getStartTasks(character)
	if not success then
		return response(false, "Failure retrieving start tasks")
	end

	return response(true, "Start tasks retrieved", taskResponse)
end

function ConfigurationNetwork.getDispositionValues(character: Model, dispositionName: string): ModuleResponse
	local values, message = getDispositionValues(character, dispositionName)
	if not values then
		return response(false, message)
	end

	return response(true, "Retrieved disposition values", values)
end

function ConfigurationNetwork.getRange(character: Model, settingName: string): ModuleResponse
	return ConfigurationNetwork.getSetting(character, { "Ranges", settingName })
end

function ConfigurationNetwork.setSetting(
	character: Model,
	path: { string },
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	local configurationFolder = getConfigurationFolder(character)
	if not configurationFolder then
		return response(false, "Configuration folder not found")
	end

	local setting = InstanceSearch.findPath(configurationFolder, path, "ValueBase")
	if not setting then
		return response(false, "Configuration setting not found or invalid")
	end

	local validPrevious, previousValue = InstanceSearch.getPrimitiveValue(setting)
	if not validPrevious then
		return response(false, "Configuration setting does not contain a supported primitive")
	end

	if typeof(previousValue) ~= typeof(value) then
		return response(false, "Configuration value type does not match the existing setting")
	end

	-- record the value first so the watcher treats the resulting Changed signal as already announced
	local watcher = watchers[character]
	if watcher and watcher.ValueConnections[setting] then
		watcher.Known[setting] = value
	end

	(setting :: any).Value = value
	configurationIndexes[character] = nil

	local eventResponse = CharacterUtility.sendEvent(character, ConfigEvents.ConfigurationUpdated, {
		Path = path,
		Previous = previousValue,
		Value = value,
		Type = setting.ClassName,
	})
	if not eventResponse.Success then
		return response(false, "Configuration changed but update event could not be sent")
	end

	return response(true, "Configuration setting updated", value)
end

function ConfigurationNetwork.setDamageSetting(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "Damage", settingName }, value)
end

function ConfigurationNetwork.setLevelSetting(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "Levels", settingName }, value)
end

function ConfigurationNetwork.setMovementSetting(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "Movement", settingName }, value)
end

function ConfigurationNetwork.setThoughtSetting(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "ThoughtProcess", settingName }, value)
end

function ConfigurationNetwork.setTeamSetting(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "Team", settingName }, value)
end

function ConfigurationNetwork.setRange(
	character: Model,
	settingName: string,
	value: TypeCDN.PrimitiveValue
): ModuleResponse
	return ConfigurationNetwork.setSetting(character, { "Ranges", settingName }, value)
end

function ConfigurationNetwork.setDispositionValue(character: Model, dispositionName: string, dispositionWeight: string, dispositionValue: number): ModuleResponse
	return ConfigurationNetwork.setSetting(character, {"Disposition", dispositionName, dispositionWeight}, dispositionValue)
end

function ConfigurationNetwork.invalidate(character: Model): ModuleResponse
	configurationIndexes[character] = nil
	return response(true, "Configuration index invalidated")
end

-- Starts announcing configuration changes made outside of setSetting. Safe to call repeatedly.
function ConfigurationNetwork.watchConfiguration(character: Model): ModuleResponse
	if not watch(character) then
		return response(false, "Configuration folder not found")
	end

	return response(true, "Configuration is being watched")
end

function ConfigurationNetwork.unwatchConfiguration(character: Model): ModuleResponse
	unwatch(character)
	return response(true, "Configuration is no longer being watched")
end

return ConfigurationNetwork
