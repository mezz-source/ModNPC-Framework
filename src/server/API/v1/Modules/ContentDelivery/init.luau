local ServerScriptService = game:GetService("ServerScriptService")
local ContentDeliveryNetwork = {}

local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local AssetsNetwork = require(script.AssetsNetwork)
local AttacksNetwork = require(script.AttacksNetwork)
local ConfigurationNetwork = require(script.ConfigurationNetwork)
local LinesNetwork = require(script.LinesNetwork)
local ModFolder = require(script.ModFolder)
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

local function validateAttacksFolder(folder: Folder): (boolean, string)
	return AttacksNetwork.validateAttacksFolder(folder)
end

local function validateLinesFolder(folder: Folder): (boolean, string)
	return LinesNetwork.validateLinesFolder(folder)
end

local function validateConfigurationFolder(folder: Folder): (boolean, string)
	return ConfigurationNetwork.validateConfigurationFolder(folder)
end

-- Mod folder kinds. Each one lists the directories it requires, in the order they are validated.
-- Config directories are checked against the kind's sample configuration under ServerScriptService.ModAssets.
ModFolder.register({
	Name = ModFolder.Kinds.ModNPC,
	RootName = CoreNames.Root,
	SchemaName = "_v1_MODNPC_CONFIG",
	Directories = {
		{ Name = CoreNames.Lines, Validator = validateLinesFolder },
		{ Name = CoreNames.Assets, Validator = validateAssetsFolder },
		{ Name = CoreNames.Configuration, Validator = validateConfigurationFolder },
		{ Name = CoreNames.Mods, Validator = validateModsFolder },
		{ Name = CoreNames.Attacks, Validator = validateAttacksFolder },
	},
})

ModFolder.register({
	Name = ModFolder.Kinds.ModWeapon,
	RootName = "ModWeapon",
	SchemaName = "_v1_MODWEAPON_CONFIG",
	Directories = {
		{ Name = CoreNames.Assets, Validator = validateAssetsFolder },
		{ Name = CoreNames.Configuration, Validator = ModFolder.schemaValidator(ModFolder.Kinds.ModWeapon) },
		{ Name = CoreNames.Attacks, Validator = validateAttacksFolder },
	},
})

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

-- Validates the mod folder of the given kind (ModFolder.Kinds) found inside `container`: a character, a tool, ...
-- Each kind is held to its own directories and its own sample configuration.
function ContentDeliveryNetwork.validModFolder(kindName: string, container: Instance): ModuleResponse
	local root = ModFolder.find(container, kindName)
	if not root then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, kindName .. " folder not found")
	end

	local isValid, errorMessage = ModFolder.validate(kindName, root)
	if not isValid then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, errorMessage)
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, kindName .. " content format is valid")
end

-- The CharacterUtility content validator: a character is a ModNPC when its ModNPC folder is valid.
function ContentDeliveryNetwork.validContentFormat(character: Model): ModuleResponse
	if not character:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Provided character is not a Model")
	end

	return ContentDeliveryNetwork.validModFolder(ModFolder.Kinds.ModNPC, character)
end

function ContentDeliveryNetwork.init(_)
	-- Initalize the core networks
	-- This exposes public functtions of submodules to the API
	-- (otherwise we'd spend a lot of time just copying public names)
	-- (and we have enough goofy enum behavior already)
	local modules = {
		AssetsNetwork,
		AttacksNetwork,
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
