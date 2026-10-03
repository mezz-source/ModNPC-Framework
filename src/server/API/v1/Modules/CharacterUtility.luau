local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFormat = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFormat)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = {}
CharacterUtility.API = {}

type CharacterType = "Generic" | "ModNPC"

CharacterUtility.CoreFolderNames = TypeCharacterFormat.CoreFolderNames
local ROOT_FOLDER_NAME = CharacterUtility.CoreFolderNames.Root
local INTERNAL_FOLDER_NAME = CharacterUtility.CoreFolderNames.Internal
local BINDS_FOLDER_NAME = CharacterUtility.CoreFolderNames.Binds
local CHARACTER_FUNCTION_BIND_NAME = CharacterUtility.CoreFolderNames.CharacterFunction
local CHARACTER_EVENT_BIND_NAME = CharacterUtility.CoreFolderNames.CharacterEvent

CharacterUtility.Type = {
	Generic = "Generic",
	ModNPC = "ModNPC",
}

local function response(success: boolean, passResponse: boolean, statusCode: number?, message: string?, data: any?)
	return {
		Success = success,
		PassResponse = passResponse,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

local function getCharacterFunctionBind(character: Model)
	local ModNPCFolder = character:FindFirstChild(ROOT_FOLDER_NAME)
	if not ModNPCFolder then
		return nil
	end

	local InternalFolder = ModNPCFolder:FindFirstChild(INTERNAL_FOLDER_NAME)
	if not InternalFolder then
		return nil
	end

	local BindsFolder = InternalFolder:FindFirstChild(BINDS_FOLDER_NAME)
	if not BindsFolder then
		return nil
	end
	local CharacterFunctionBindable = BindsFolder:FindFirstChild(CHARACTER_FUNCTION_BIND_NAME)
	if not CharacterFunctionBindable or not CharacterFunctionBindable:IsA("BindableFunction") then
		return nil
	end
	return CharacterFunctionBindable
end

local function getForceField(character: Model): ForceField?
	if not character or not character:IsA("Model") then
		return nil
	end

	return character:FindFirstChildOfClass("ForceField")
end

local function getHumanoid(character: Model): Humanoid?
	if not character or not character:IsA("Model") then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function ensureFocusAlignment(character: Model): AlignOrientation?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	local focusAlignment = rootPart:FindFirstChild("FocusAlignment")
	if focusAlignment and not focusAlignment:IsA("AlignOrientation") then
		warn(character.Name, "has a non-AlignOrientation FocusAlignment; replacing it")
		focusAlignment:Destroy()
		focusAlignment = nil
	end

	if not focusAlignment then
		focusAlignment = Instance.new("AlignOrientation")
		focusAlignment.Name = "FocusAlignment"
		focusAlignment.Parent = rootPart
	end

	local focusAttachment = rootPart:FindFirstChild("FocusAttachment")
	if focusAttachment and not focusAttachment:IsA("Attachment") then
		warn(character.Name, "has a non-Attachment FocusAttachment; replacing it")
		focusAttachment:Destroy()
		focusAttachment = nil
	end

	if not focusAttachment then
		focusAttachment = Instance.new("Attachment")
		focusAttachment.Name = "FocusAttachment"
		focusAttachment.Parent = rootPart
	end

	focusAttachment.Orientation = Vector3.new(0, 90, 0)
	focusAlignment.Mode = Enum.OrientationAlignmentMode.OneAttachment
	focusAlignment.AlignType = Enum.AlignType.PrimaryAxisLookAt
	focusAlignment.Responsiveness = 25
	focusAlignment.Attachment0 = focusAttachment
	focusAlignment.Enabled = false

	return focusAlignment
end

local function getRootPart(character: Model): BasePart?
	if not character or not character:IsA("Model") then
		return nil
	end

	if character.PrimaryPart then
		return character.PrimaryPart
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	return rootPart
end

local function isValidCharacter(character: Model): boolean
	local humanoid = getHumanoid(character)
	local root = getRootPart(character)
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function getCharacterEventBind(character: Model)
	local ModNPCFolder = character:FindFirstChild(ROOT_FOLDER_NAME)
	if not ModNPCFolder or not ModNPCFolder:IsA("Folder") then
		return nil
	end

	local InternalFolder = ModNPCFolder:FindFirstChild(INTERNAL_FOLDER_NAME)
	if not InternalFolder or not InternalFolder:IsA("Folder") then
		return nil
	end

	local BindsFolder = InternalFolder:FindFirstChild(BINDS_FOLDER_NAME)
	if not BindsFolder or not BindsFolder:IsA("Folder") then
		return nil
	end
	local CharacterEventBindable = BindsFolder:FindFirstChild(CHARACTER_EVENT_BIND_NAME)
	if not CharacterEventBindable or not CharacterEventBindable:IsA("BindableEvent") then
		return nil
	end
	return CharacterEventBindable
end

local function validateModNPC(ModNPCFolder: Folder, character: Model): CharacterType
	-- Verify folder has the required assets
	local UnloadedIndicator = character:FindFirstChild("_UNLOADED")
	if UnloadedIndicator then
		warn(character.Name, "ModNPC is unloaded, skipping validation")
		return CharacterUtility.Type.Generic
	end

	local ModsFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Mods)
	local AssetsFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Assets)
	local ConfigurationFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Configuration)
	local LinesFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Lines)
	local InternalFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Internal)

	local BASE_MESSAGE = character.Name .. " appears to be a ModNPC, but has a malformed setup"

	-- these warn as they point to more complex issues regarding mod NPCS
	if not ModsFolder then
		warn(character.Name, BASE_MESSAGE .. " (mod folder invalid)")
		return CharacterUtility.Type.Generic
	end

	if not AssetsFolder then
		warn(character.Name, BASE_MESSAGE .. " (assets folder invalid)")
		return CharacterUtility.Type.Generic
	end

	if not ConfigurationFolder then
		warn(character.Name, BASE_MESSAGE .. " (configuration folder invalid)")
		return CharacterUtility.Type.Generic
	end

	if not LinesFolder then
		warn(character.Name, BASE_MESSAGE .. " (lines folder invalid)")
		return CharacterUtility.Type.Generic
	end

	if not InternalFolder then
		warn(character.Name, BASE_MESSAGE .. " (internal folder invalid)")
		return CharacterUtility.Type.Generic
	end

	if not ensureFocusAlignment(character) then
		warn(character.Name, BASE_MESSAGE .. " (HumanoidRootPart invalid)")
		return CharacterUtility.Type.Generic
	end

	local BindsFolder = InternalFolder:FindFirstChild("_binds")

	if not BindsFolder then
		warn(character.Name, BASE_MESSAGE .. " (binds folder invalid)")
		return CharacterUtility.Type.Generic
	end

	local CharacterFunctionBindable = BindsFolder:FindFirstChild(CHARACTER_FUNCTION_BIND_NAME)
	if not CharacterFunctionBindable or not CharacterFunctionBindable:IsA("BindableFunction") then
		warn(character.Name, BASE_MESSAGE .. " (CharacterFunction bindable invalid)")
		return CharacterUtility.Type.Generic
	end

	local CharacterEventBindable = BindsFolder:FindFirstChild(CHARACTER_EVENT_BIND_NAME)
	if not CharacterEventBindable or not CharacterEventBindable:IsA("BindableEvent") then
		warn(character.Name, BASE_MESSAGE .. " (CharacterEvent bindable invalid)")
		return CharacterUtility.Type.Generic
	end

	-- Last walk validation--the most expensive
	-- we cant aquire directly as the character due to cyclic :(
	-- FIX-ME: maybe move validation here?
	if CharacterUtility.API then
		local request = {
			ModuleName = "ContentDelivery",
			Function = "validContentFormat",
			Arguments = { character },
		}

		local response = CharacterUtility.API._internalRequest(request)
		if not response.Success then
			warn(character.Name, BASE_MESSAGE .. " (content format invalid): " .. (response.Message or "unknown error"))
			return CharacterUtility.Type.Generic
		end
	else
		warn(character.Name, BASE_MESSAGE .. " (content format validation skipped): API not initialized")
	end

	return CharacterUtility.Type.ModNPC
end

local function getCharacterType(character: Model): CharacterType?
	if not isValidCharacter(character) then
		return nil
	end

	local ModNPCFolder = character:FindFirstChild(ROOT_FOLDER_NAME)
	if ModNPCFolder then
		return validateModNPC(ModNPCFolder, character)
	end

	return CharacterUtility.Type.Generic
end

function CharacterUtility.getCharacterType(character: Model): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Character type retrieved successfully",
		getCharacterType(character)
	)
end

function CharacterUtility.getForceField(character: Model): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Force field retrieved successfully",
		getForceField(character)
	)
end

function CharacterUtility.getHumanoid(character: Model): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Humanoid retrieved successfully",
		getHumanoid(character)
	)
end

function CharacterUtility.getHealth(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid = getHumanoid(character)
	if not humanoid then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character does not have a humanoid")
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Health retrieved successfully", humanoid.Health)
end

function CharacterUtility.getMaxHealth(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid = getHumanoid(character)
	if not humanoid then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character does not have a humanoid")
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Maximum health retrieved successfully",
		humanoid.MaxHealth
	)
end

function CharacterUtility.getRootPart(character: Model): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Root part retrieved successfully",
		getRootPart(character)
	)
end

function CharacterUtility.isValidCharacter(character: Model): TypeModuleResponse.ModuleResponse
	if not character or not character:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid character", false)
	end

	local valid = isValidCharacter(character)
	return response(valid, true, TypeRequests.Enums.StatusCode.Success, "Character validation completed", valid)
end

function CharacterUtility.isValidModNPC(character: Model): TypeModuleResponse.ModuleResponse
	local now = os.clock()
	local valid = getCharacterType(character) == CharacterUtility.Type.ModNPC
	local stop = os.clock()
	print(" -- ModNPC validation took " .. tostring(stop - now) .. " seconds")
	return response(valid, true, TypeRequests.Enums.StatusCode.Success, "ModNPC validation completed", valid)
end

function CharacterUtility.getCharacterInfo(character: Model): TypeModuleResponse.ModuleResponse
	if not isValidCharacter(character) then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid character", character)
	end

	local characterType = getCharacterType(character)
	local humanoid = getHumanoid(character)
	local curHealth, maxHealth = humanoid.Health, humanoid.MaxHealth

	return response(
		true,
		true,
		nil,
		"Character info retrieved successfully",
		{ Character = character, Type = characterType, CurrentHealth = curHealth, MaxHealth = maxHealth }
	)
end

function CharacterUtility.sendFunction(
	character: Model,
	functionName: string,
	arguments: { any }?
): TypeModuleResponse.ModuleResponse
	local characterFunction = getCharacterFunctionBind(character)
	if not characterFunction then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterFunction bindable not found")
	end

	local success, result = pcall(function()
		return characterFunction:Invoke(functionName, arguments)
	end)

	if not success then
		warn("CharacterUtility.sendFunction: Error invoking function:", result)
		return response(false, true, TypeRequests.Enums.StatusCode.InternalServerError, tostring(result))
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Character function invoked successfully",
		result
	)
end

function CharacterUtility.sendEvent(
	character: Model,
	eventName: string,
	arguments: { any }?
): TypeModuleResponse.ModuleResponse
	local characterEvent = getCharacterEventBind(character)
	if not characterEvent then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterEvent bindable not found")
	end

	characterEvent:Fire(eventName, arguments)
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character event sent successfully")
end

function CharacterUtility.init(api: {}?)
	print("V1 CharacterUtility initialized")
	CharacterUtility.API = api
end

return CharacterUtility
