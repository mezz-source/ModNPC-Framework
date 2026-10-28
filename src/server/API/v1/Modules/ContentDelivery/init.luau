local ServerScriptService = game:GetService("ServerScriptService")
local ContentDeliveryNetwork = {}

local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local AssetsNetwork = require(script.AssetsNetwork)
local ConfigurationNetwork = require(script.ConfigurationNetwork)
local LinesNetwork = require(script.LinesNetwork)
local ModsNetwork = require(script.ModsNetwork)
local CharacterUtility = require(script.Parent.CharacterUtility)
local CoreNames = CharacterUtility.CoreFolderNames

type ModuleResponse = TypeModuleResponse.ModuleResponse

local function response(
	success: boolean,
	passResponse: boolean,
	statusCode: number?,
	message: string?,
	data: any?
): ModuleResponse
	return {
		Success = success,
		PassResponse = passResponse,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

local function getRootFolder(character: Model): Folder?
	local root = character:FindFirstChild(CoreNames.Root)
	if not root then
		return nil
	end

	return root
end

local function getChildFolder(parent: Folder, name: string): Folder?
	local child = parent:FindFirstChild(name)
	if not child then
		return nil
	end

	return child
end

local function getModsFolder(character: Model): Folder?
	local modsFolder = getRootFolder(character)
	if not modsFolder then
		return nil
	end

	return getChildFolder(modsFolder, CoreNames.Mods)
end

local function getConfigurationFolder(character: Model): Folder?
	local configFolder = getRootFolder(character)
	if not configFolder then
		return nil
	end

	return getChildFolder(configFolder, CoreNames.Configuration)
end

local function getLinesFolder(character: Model): Folder?
	local linesFolder = getRootFolder(character)
	if not linesFolder then
		return nil
	end

	return getChildFolder(linesFolder, CoreNames.Lines)
end

local function getAssetsFolder(character: Model): Folder?
	local assetsFolder = getRootFolder(character)
	if not assetsFolder then
		return nil
	end

	return getChildFolder(assetsFolder, CoreNames.Assets)
end

local function validateAssetsFolder(folder: Folder): (boolean, string)
	return AssetsNetwork.validateAssetsFolder(folder)
end
local function validateModsFolder(folder: Folder): (boolean, string)
	return ModsNetwork.validateModsFolder(folder)
end

local function validateLinesFolder(folder: Folder): (boolean, string)
	return LinesNetwork.validateLinesFolder(folder)
end

local function validateConfigurationFolder(folder: Folder): (boolean, string)
	return ConfigurationNetwork.validateConfigurationFolder(folder)
end

function ContentDeliveryNetwork.getRootFolder(character: Model): ModuleResponse
	local folder = getRootFolder(character)
	if not folder then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Root folder not found")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Root folder found", folder)
end

function ContentDeliveryNetwork.getModsFolder(character: Model): ModuleResponse
	local folder = getModsFolder(character)
	if not folder then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Mods folder not found")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Mods folder found", folder)
end

function ContentDeliveryNetwork.getConfigurationFolder(character: Model): ModuleResponse
	local folder = getConfigurationFolder(character)
	if not folder then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Configuration folder not found")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Configuration folder found", folder)
end

function ContentDeliveryNetwork.getLinesFolder(character: Model): ModuleResponse
	local folder = getLinesFolder(character)
	if not folder then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Lines folder not found")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Lines folder found", folder)
end

function ContentDeliveryNetwork.getAssetsFolder(character: Model): ModuleResponse
	local folder = getAssetsFolder(character)
	if not folder then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Assets folder not found")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Assets folder found", folder)
end

function ContentDeliveryNetwork.validContentFormat(character: Model): ModuleResponse
	if not character:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Provided character is not a Model")
	end

	local linesFolder = getLinesFolder(character)
	local assetsFolder = getAssetsFolder(character)
	local configurationFolder = getConfigurationFolder(character)
	local modsFolder = getModsFolder(character)

	-- generally speaking this doesn't get here, as validation passes through the CharacterUtility module
	-- never hurts though as this function is supposed to survive!
	if not linesFolder or not assetsFolder or not configurationFolder or not modsFolder then
		return response(
			false,
			true,
			TypeRequests.Enums.StatusCode.Conflict,
			"Character is missing one or more required folders"
		)
	end

	local function validate(name: string, folder: Folder, func: (Folder) -> (boolean, string)): nil | string
		local isValid, errorMessage = func(folder)
		if not isValid then
			return name .. " folder validation failed: " .. errorMessage
		end

		return nil
	end

	local validationFunctions = {
		{ Name = "Lines", Folder = linesFolder, Func = validateLinesFolder },
		{ Name = "Assets", Folder = assetsFolder, Func = validateAssetsFolder },
		{ Name = "Configuration", Folder = configurationFolder, Func = validateConfigurationFolder },
		{ Name = "Mods", Folder = modsFolder, Func = validateModsFolder },
	}

	for _, validation in ipairs(validationFunctions) do
		local errorMessage = validate(validation.Name, validation.Folder, validation.Func)
		if errorMessage then
			return response(false, true, TypeRequests.Enums.StatusCode.Conflict, errorMessage)
		end
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character content format is valid")
end

function ContentDeliveryNetwork.init(_)
	-- Initalize the core networks
	-- This exposes public functtions of submodules to the API
	-- (otherwise we'd spend a lot of time just copying public names)
	-- (and we have enough goofy enum behavior already)
	local modules = {
		AssetsNetwork,
		ConfigurationNetwork,
		LinesNetwork,
		ModsNetwork,
	}

	local importedFunctions = {}

	-- iterate through each module and import its public functions into the ContentDeliveryNetwork
	for _, module in ipairs(modules) do
		-- bootstrap that bad boy
		module.init(ContentDeliveryNetwork)

		-- lets see its insides
		for key, value in pairs(module) do
			if key == "init" then
				continue
			end

			if typeof(value) == "function" then
				if not importedFunctions[key] then
					importedFunctions[key] = value
				else
					warn("Function name conflict detected in ContentDeliveryNetwork.init():", key)
				end
			end
		end
	end

	for key, value in pairs(importedFunctions) do
		ContentDeliveryNetwork[key] = value
	end

	-- we're going to assign us as the content formatters
	CharacterUtility.setContentValidator(ContentDeliveryNetwork.validContentFormat)

	-- aint she a pretty thing
	print("V1 ContentDeliveryNetwork initialized")
end

return ContentDeliveryNetwork
