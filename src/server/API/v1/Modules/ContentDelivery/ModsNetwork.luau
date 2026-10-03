local ServerScriptService = game:GetService("ServerScriptService")
local ModsNetwork = {}

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)

type ModData = TypeCDN.ModData
type ModuleResponse = TypeModuleResponse.ModuleResponse

local contentDeliveryNetwork

local function response(success: boolean, message: string, data: any?): ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = success and TypeRequests.Enums.StatusCode.Success or TypeRequests.Enums.StatusCode.Conflict,
		Message = message,
		Data = data,
	}
end

local function getModsFolder(character: Model): Folder?
	local modsResponse = contentDeliveryNetwork.getModsFolder(character)
	if not modsResponse.Success or not modsResponse.Data then
		return nil
	end

	return modsResponse.Data
end

local function getPath(root: Instance, instance: Instance): string
	local fullName = instance:GetFullName()
	local rootName = root:GetFullName() .. "."
	return string.sub(fullName, #rootName + 1)
end

local function hasAPIInit(moduleScript: ModuleScript): boolean
	local success, module = pcall(require, moduleScript)
	if not success or typeof(module) ~= "table" then
		return false
	end

	return typeof(module.apiInit) == "function"
end

local function discoverModules(modsFolder: Folder): { ModData }
	local modules = {}
	for _, descendant in ipairs(modsFolder:GetDescendants()) do
		if descendant:IsA("ModuleScript") and hasAPIInit(descendant) then
			table.insert(modules, {
				Name = descendant.Name,
				Path = getPath(modsFolder, descendant),
			})
		end
	end

	table.sort(modules, function(left: ModData, right: ModData)
		return left.Path < right.Path
	end)

	return modules
end

function ModsNetwork.init(network)
	contentDeliveryNetwork = network
end

function ModsNetwork.validateModsFolder(modsFolder: Folder): (boolean, string)
	return true, ""
end

function ModsNetwork.getModules(character: Model): ModuleResponse
	local modsFolder = getModsFolder(character)
	if not modsFolder then
		return response(false, "Mods folder not found")
	end

	return response(true, "Mod modules discovered", discoverModules(modsFolder))
end

return ModsNetwork
