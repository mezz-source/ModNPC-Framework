local ServerScriptService = game:GetService("ServerScriptService")
local ConfigurationNetwork = {}

local InstanceSearch = require(ServerScriptService.ModNPCServer.Util.InstanceSearch)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)

type ConfigurationIndex = TypeCDN.ConfigurationIndex
type ConfigurationValue = TypeCDN.ConfigurationValue
type ModuleResponse = TypeModuleResponse.ModuleResponse

local contentDeliveryNetwork
local baseConfiguration: Folder?
local baseConfigurationIndex: ConfigurationIndex?
local configurationIndexes: { [Model]: ConfigurationIndex } = {}

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

local function validateSchemaFolder(configurationFolder: Folder, schemaFolder: Folder, path: string): (boolean, string)
	for _, schemaChild in ipairs(schemaFolder:GetChildren()) do
		local pathName = path .. "/" .. schemaChild.Name
		local configurationChild = configurationFolder:FindFirstChild(schemaChild.Name)
		if not configurationChild then
			return false, "Missing configuration value: " .. pathName
		end

		if schemaChild:IsA("Folder") then
			if not configurationChild:IsA("Folder") then
				return false, "Expected configuration folder: " .. pathName
			end

			local valid, message = validateSchemaFolder(configurationChild, schemaChild, pathName)
			if not valid then
				return false, message
			end
		elseif schemaChild:IsA("ValueBase") then
			if not configurationChild:IsA(schemaChild.ClassName) then
				return false, "Invalid configuration value type: " .. pathName
			end
		end
	end

	return true, ""
end

function ConfigurationNetwork.init(network)
	contentDeliveryNetwork = network
	local candidate = ServerScriptService:WaitForChild("_v1_BASE_CONFIG")
	baseConfiguration = if candidate then candidate else nil
	baseConfigurationIndex = if baseConfiguration then buildIndex(baseConfiguration) else nil
end

function ConfigurationNetwork.validateConfigurationFolder(configurationFolder: Folder): (boolean, string)
	if not baseConfiguration then
		return false, "ServerScriptService._v1_BASE_CONFIG is missing or invalid"
	end

	return validateSchemaFolder(configurationFolder, baseConfiguration, "Config")
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
	if not baseConfigurationIndex then
		return response(false, "Base configuration schema not found")
	end

	return response(true, "Configuration schema retrieved", baseConfigurationIndex)
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

	(setting :: any).Value = value
	configurationIndexes[character] = nil

	local eventResponse = CharacterUtility.sendEvent(character, TypeCharacterEvents.Names.ConfigurationUpdated, {
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

function ConfigurationNetwork.invalidate(character: Model): ModuleResponse
	configurationIndexes[character] = nil
	return response(true, "Configuration index invalidated")
end

return ConfigurationNetwork
