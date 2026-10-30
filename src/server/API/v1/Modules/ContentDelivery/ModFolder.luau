local ServerScriptService = game:GetService("ServerScriptService")
local ModFolder = {}

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)

type ModFolderKind = TypeCDN.ModFolderKind
type ModFolderValidator = TypeCDN.ModFolderValidator

ModFolder.Kinds = table.freeze({
	ModNPC = "ModNPC",
	ModWeapon = "ModWeapon",
})

local ModAssets = ServerScriptService:WaitForChild("ModAssets")

local kinds: { [string]: ModFolderKind } = {}

local function validateSchemaFolder(folder: Instance, schemaFolder: Instance, path: string): (boolean, string)
	for _, schemaChild in ipairs(schemaFolder:GetChildren()) do
		local pathName = path .. "/" .. schemaChild.Name
		local child = folder:FindFirstChild(schemaChild.Name)
		if not child then
			return false, "Missing configuration value: " .. pathName
		end

		if schemaChild:IsA("Folder") then
			if not child:IsA("Folder") then
				return false, "Expected configuration folder: " .. pathName
			end

			local valid, message = validateSchemaFolder(child, schemaChild, pathName)
			if not valid then
				return false, message
			end
		elseif schemaChild:IsA("ValueBase") then
			if not child:IsA(schemaChild.ClassName) then
				return false, "Invalid configuration value type: " .. pathName
			end
		end
	end

	return true, ""
end

function ModFolder.register(kind: ModFolderKind)
	if kinds[kind.Name] then
		warn("ModFolder kind registered twice, replacing:", kind.Name)
	end

	kinds[kind.Name] = kind
end

function ModFolder.getKind(kindName: string): ModFolderKind?
	return kinds[kindName]
end

-- The sample configuration a kind's Config directory has to match.
-- Looked up on every call (it is a plain child lookup) so a schema edited in Studio is picked up.
function ModFolder.getSchema(kindName: string): Instance?
	local kind = kinds[kindName]
	if not kind or not kind.SchemaName then
		return nil
	end

	return ModAssets:FindFirstChild(kind.SchemaName)
end

-- Checks that `folder` contains everything the kind's sample configuration contains, with matching value types.
function ModFolder.validateSchema(kindName: string, folder: Instance): (boolean, string)
	local kind = kinds[kindName]
	if not kind or not kind.SchemaName then
		return false, kindName .. " has no configuration schema"
	end

	local schema = ModFolder.getSchema(kindName)
	if not schema then
		return false, "ServerScriptService.ModAssets." .. kind.SchemaName .. " is missing or invalid"
	end

	return validateSchemaFolder(folder, schema, folder.Name)
end

-- A directory validator for Config directories of the given kind.
function ModFolder.schemaValidator(kindName: string): ModFolderValidator
	return function(folder: Folder): (boolean, string)
		return ModFolder.validateSchema(kindName, folder)
	end
end

-- Finds the kind's root folder inside a container (a character, a tool, ...).
function ModFolder.find(container: Instance, kindName: string): Folder?
	local kind = kinds[kindName]
	if not kind then
		return nil
	end

	local root = container:FindFirstChild(kind.RootName)
	if not root then
		return nil
	end

	return root :: Folder
end

-- Finds a directory (Assets, Attacks, ...) of whichever mod folder `container` carries: a character's ModNPC folder
-- or a weapon's ModWeapon folder. Nil when the container carries neither or the directory is missing.
function ModFolder.findDirectory(container: Instance, directoryName: string): Folder?
	for _, kindName in ipairs({ ModFolder.Kinds.ModNPC, ModFolder.Kinds.ModWeapon }) do
		local root = ModFolder.find(container, kindName)
		if root then
			-- directories are not necessarily Folders (their ClassName can be an Explorer icon), so no class check
			return root:FindFirstChild(directoryName) :: Folder?
		end
	end

	return nil
end

-- Every directory the kind requires has to be present and pass its own validator.
-- Directories are checked in the order the kind declares them.
function ModFolder.validate(kindName: string, root: Instance): (boolean, string)
	local kind = kinds[kindName]
	if not kind then
		return false, kindName .. " is not a registered mod folder kind"
	end

	for _, directory in ipairs(kind.Directories) do
		local folder = root:FindFirstChild(directory.Name)
		if not folder then
			return false, kind.Name .. " is missing the " .. directory.Name .. " folder"
		end

		local valid, message = directory.Validator(folder :: Folder)
		if not valid then
			return false, directory.Name .. " folder validation failed: " .. message
		end
	end

	return true, ""
end

return ModFolder
