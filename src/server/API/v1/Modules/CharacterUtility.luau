local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFormat = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFormat)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local CharacterUtility = {}
CharacterUtility.API = {}

type CharacterType = "Generic" | "ModNPC"

CharacterUtility.CoreFolderNames = TypeCharacterFormat.CoreFolderNames
local ROOT_FOLDER_NAME = CharacterUtility.CoreFolderNames.Root
local INTERNAL_FOLDER_NAME = CharacterUtility.CoreFolderNames.Internal
local BINDS_FOLDER_NAME = CharacterUtility.CoreFolderNames.Binds
local CHARACTER_FUNCTION_BIND_NAME = CharacterUtility.CoreFolderNames.CharacterFunction
local CHARACTER_EVENT_BIND_NAME = CharacterUtility.CoreFolderNames.CharacterEvent
local CHARACTER_STIMULANT_BIND_NAME = CharacterUtility.CoreFolderNames.CharacterStimulant

type StimulantEvent = TypeStimulant.StimulantEvent
type StimulantSpec = TypeStimulant.StimulantSpec
type ModuleResponse = TypeModuleResponse.ModuleResponse

local contentValidationFunction: (Model) -> ModuleResponse = nil
local teamGetterFunction: (Model) -> ModuleResponse = nil

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

	-- This runs on every character validation (team lookups, target searches, ...), not just once.
	-- Enabled belongs to Movement.lockRotation/unlockRotation, so it is only defaulted when we create the alignment,
	-- otherwise the next validation would switch an active focus alignment back off.
	local created = false
	if not focusAlignment then
		focusAlignment = Instance.new("AlignOrientation")
		focusAlignment.Name = "FocusAlignment"
		focusAlignment.Parent = rootPart
		created = true
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
	if created then
		focusAlignment.Enabled = false
	end

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
	local CharacterEventBindable = BindsFolder:FindFirstChild(CHARACTER_EVENT_BIND_NAME)
	if not CharacterEventBindable or not CharacterEventBindable:IsA("BindableEvent") then
		return nil
	end
	return CharacterEventBindable
end

local function getCharacterStimulantBind(character: Model): BindableEvent?
	local ModNPCFolder = character:FindFirstChild(ROOT_FOLDER_NAME)
	local InternalFolder = ModNPCFolder and ModNPCFolder:FindFirstChild(INTERNAL_FOLDER_NAME)
	local BindsFolder = InternalFolder and InternalFolder:FindFirstChild(BINDS_FOLDER_NAME)
	local CharacterStimulantBindable = BindsFolder and BindsFolder:FindFirstChild(CHARACTER_STIMULANT_BIND_NAME)
	if not CharacterStimulantBindable or not CharacterStimulantBindable:IsA("BindableEvent") then
		return nil
	end
	return CharacterStimulantBindable
end

-- Why a character is not valid, or nil when it is; mirrors isValidCharacter
local function getInvalidCharacterReason(character: Model): string?
	if not character or not character:IsA("Model") then
		return "not a Model"
	end

	if not getHumanoid(character) then
		return "has no Humanoid"
	end

	if not getRootPart(character) then
		return "has no root part (PrimaryPart or HumanoidRootPart)"
	end

	if getHumanoid(character).Health <= 0 then
		return "is dead (Humanoid.Health <= 0)"
	end

	return nil
end

-- Returns the character type and, when that is not ModNPC, the reason the character was not accepted as one
local function validateModNPC(
	ModNPCFolder: Folder,
	character: Model,
	skipUnloadedCheck: boolean?
): (CharacterType, string?)
	-- Verify folder has the required assets
	local UnloadedIndicator = character:FindFirstChild("_UNLOADED")
	if UnloadedIndicator and not skipUnloadedCheck then
		warn(character.Name, "ModNPC is unloaded, skipping validation")
		return CharacterUtility.Type.Generic, "ModNPC is unloaded (_UNLOADED indicator is present)"
	end

	local ModsFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Mods)
	local AssetsFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Assets)
	local ConfigurationFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Configuration)
	local LinesFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Lines)
	local InternalFolder = ModNPCFolder:FindFirstChild(CharacterUtility.CoreFolderNames.Internal)

	local BASE_MESSAGE = character.Name .. " appears to be a ModNPC, but has a malformed setup"

	-- these warn as they point to more complex issues regarding mod NPCS
	local function malformed(detail: string): (CharacterType, string?)
		local message = BASE_MESSAGE .. " (" .. detail .. ")"
		warn(character.Name, message)
		return CharacterUtility.Type.Generic, message
	end

	if not ModsFolder then
		return malformed("mod folder invalid")
	end

	if not AssetsFolder then
		return malformed("assets folder invalid")
	end

	if not ConfigurationFolder then
		return malformed("configuration folder invalid")
	end

	if not LinesFolder then
		return malformed("lines folder invalid")
	end

	if not InternalFolder then
		return malformed("internal folder invalid")
	end

	if not ensureFocusAlignment(character) then
		return malformed("HumanoidRootPart invalid")
	end

	local BindsFolder = InternalFolder:FindFirstChild("_binds")

	if not BindsFolder then
		return malformed("binds folder invalid")
	end

	local CharacterFunctionBindable = BindsFolder:FindFirstChild(CHARACTER_FUNCTION_BIND_NAME)
	if not CharacterFunctionBindable or not CharacterFunctionBindable:IsA("BindableFunction") then
		return malformed("CharacterFunction bindable invalid")
	end

	local CharacterEventBindable = BindsFolder:FindFirstChild(CHARACTER_EVENT_BIND_NAME)
	if not CharacterEventBindable or not CharacterEventBindable:IsA("BindableEvent") then
		return malformed("CharacterEvent bindable invalid")
	end

	local CharacterStimulantBindable = BindsFolder:FindFirstChild(CHARACTER_STIMULANT_BIND_NAME)
	if not CharacterStimulantBindable or not CharacterStimulantBindable:IsA("BindableEvent") then
		return malformed("CharacterStimulant bindable invalid")
	end

	-- Check with out CDN whether or not they got their ModNPC format in order
	-- It's not mission critical without it, as it's only nil really early in load
	-- NPCs can't hit the nil case
	if contentValidationFunction then
		local result = contentValidationFunction(character)
		if not result or not result.Success then
			local detail = if result and result.Message then result.Message else "content validation returned no result"
			return CharacterUtility.Type.Generic, "Content format invalid: " .. detail
		end
	end

	return CharacterUtility.Type.ModNPC, nil
end

-- The reason is only given when the character did not come back as a ModNPC
local function getCharacterType(character: Model, allowUnloaded: boolean?): (CharacterType?, string?)
	local invalidReason = getInvalidCharacterReason(character)
	if invalidReason then
		return nil, "Invalid character: " .. invalidReason
	end

	local ModNPCFolder = character:FindFirstChild(ROOT_FOLDER_NAME)
	if ModNPCFolder then
		return validateModNPC(ModNPCFolder, character, allowUnloaded)
	end

	return CharacterUtility.Type.Generic, "Character has no " .. ROOT_FOLDER_NAME .. " folder"
end

local function getCharacterTeam(character: Model): string
	local allowUnloaded = true
	local characterType = getCharacterType(character, allowUnloaded)
	if characterType == CharacterUtility.Type.ModNPC then
		local returnData = teamGetterFunction(character).Data -- {"Name": "xyz", "Value": "teamname"}
		return returnData.Value :: string
	else
		-- We're going to do broad checks to see if we can pick up legacy values/indicators
		-- warn("No team integration for non-mods yet", characterType, teamGetterFunction)
	end

	return "Neutral"
end

-- This will allow the content delivery network passthrough
function CharacterUtility.setContentValidator(fn: (Model) -> ModuleResponse)
	contentValidationFunction = fn
end

function CharacterUtility.setTeamGetter(fn: (Model) -> ModuleResponse)
	teamGetterFunction = fn
end

function CharacterUtility.getCharacterType(character: Model, allowUnloaded: boolean?): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Character type retrieved successfully",
		(getCharacterType(character, allowUnloaded))
	)
end

function CharacterUtility.getTeam(character: Model): TypeModuleResponse.ModuleResponse
	local teamName = getCharacterTeam(character)
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Team retrieved successfully", teamName)
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

-- Health, max health, and the 0..1 fraction in one request, for comparing targets
function CharacterUtility.getHealthInfo(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid = getHumanoid(character)
	if not humanoid then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character does not have a humanoid")
	end

	local health, maxHealth = humanoid.Health, humanoid.MaxHealth
	local fraction = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Health info retrieved successfully",
		{ Health = health, MaxHealth = maxHealth, Fraction = fraction }
	)
end

-- Attempts to get the stamina of a given NPC if available
function CharacterUtility.getStaminaInfo(character: Model): TypeModuleResponse.ModuleResponse
	local staminaResponse = CharacterUtility.sendFunction(character, "GetStamina", nil)
	local data = staminaResponse.Data
	if not staminaResponse.Success or typeof(data) ~= "table" then
		return staminaResponse
	end

	local current, max = data[1], data[2]
	local fraction = if max > 0 then math.clamp(current / max, 0, 1) else 0

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Stamina info retrieved successfully",
		{ Stamina = current, MaxStamina = max, Fraction = fraction }
	)
end

-- Asks the character a yes/no question through one of its functions. Only a ModNPC has these states: anyone else (a
-- player, a plain humanoid) is a plain "no" and not an error, so asking about a target never fails for being a different kind.
local function askCharacter(character: Model, functionName: string, message: string): TypeModuleResponse.ModuleResponse
	if not getCharacterFunctionBind(character) then
		return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character is not a ModNPC", false)
	end
	-- a ModNPC that was never started has nothing behind its bind, and isn't anything yet
	if character:FindFirstChild("_UNLOADED") then
		return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character is not started", false)
	end

	local answer = CharacterUtility.sendFunction(character, functionName, nil)
	if not answer.Success then
		return answer
	end

	return response(true, true, TypeRequests.Enums.StatusCode.Success, message, answer.Data == true)
end

-- Whether the character is exhausted right now (its Stamina decides, see IsExhausted)
function CharacterUtility.isExhausted(character: Model): TypeModuleResponse.ModuleResponse
	return askCharacter(character, "IsExhausted", "Exhaustion retrieved successfully")
end

-- Whether the character is staggered right now (its Damage decides, see IsStaggered)
function CharacterUtility.isStaggered(character: Model): TypeModuleResponse.ModuleResponse
	return askCharacter(character, "IsStaggered", "Stagger retrieved successfully")
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
	local characterType, reason = getCharacterType(character)
	local valid = characterType == CharacterUtility.Type.ModNPC
	local stop = os.clock()
	print(" -- ModNPC validation took " .. tostring(stop - now) .. " seconds")
	-- Callers (and the API's failed-request warning) see exactly what failed, not just that validation ran
	local message = if valid then "ModNPC validation completed" else (reason or "Character is not a ModNPC")
	return response(valid, true, TypeRequests.Enums.StatusCode.Success, message, valid)
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

-- Calls a function on the character through its CharacterFunction bind (answered by CharacterAPI:_functionRecieved).
-- arguments is the list of arguments for a FunctionEnum name, or the context table itself for "Damage".
function CharacterUtility.sendFunction(
	character: Model,
	functionName: string,
	arguments: any?
): TypeModuleResponse.ModuleResponse
	local characterFunction = getCharacterFunctionBind(character)
	if not characterFunction then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterFunction bindable not found")
	end
	-- A ModNPC that was never started (still _UNLOADED) has no Base answering its bind, and invoking a BindableFunction
	-- nobody answers yields forever: the caller (a reaction tick asking about its target, say) would never come back
	if character:FindFirstChild("_UNLOADED") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character is not started")
	end

	local success, result = pcall(function()
		return characterFunction:Invoke(functionName, arguments)
	end)

	if not success then
		warn("CharacterUtility.sendFunction: Error invoking function:", result)
		return response(false, true, TypeRequests.Enums.StatusCode.InternalServerError, tostring(result))
	end

	-- the character answers with its own success/failure; pass it up instead of calling every delivery a success
	if typeof(result) ~= "table" or typeof(result.Success) ~= "boolean" then
		return response(
			false,
			true,
			TypeRequests.Enums.StatusCode.InternalServerError,
			"Character function returned a malformed response"
		)
	end

	if not result.Success then
		return response(
			false,
			true,
			TypeRequests.Enums.StatusCode.Conflict,
			result.Message or "Character function failed",
			result.Data
		)
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		result.Message or "Character function invoked successfully",
		result.Data
	)
end

-- arguments is the event payload (usually a dictionary, see TypeCharacterEvents)
function CharacterUtility.sendEvent(
	character: Model,
	eventName: string,
	arguments: any?
): TypeModuleResponse.ModuleResponse
	local characterEvent = getCharacterEventBind(character)
	if not characterEvent then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterEvent bindable not found")
	end

	characterEvent:Fire(eventName, arguments)
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character event sent successfully")
end

-- Builds a StimulantEvent from what an emitter asked for. The id is the Stimulants module's to give; an unset
-- priority is Normal.
function CharacterUtility.createStimulant(id: number, source: Model?, spec: StimulantSpec): StimulantEvent
	return {
		Id = id,
		Name = spec.Name,
		Source = source,
		Position = spec.Position,
		Priority = spec.Priority or TypeStimulant.Priorities.Normal,
		ExpiresAt = spec.ExpiresAt,
		Data = spec.Data,
	}
end

-- Delivers a stimulant to one character through its CharacterStimulant bind. Nothing listens yet (skeleton).
function CharacterUtility.sendStimulant(character: Model, stimulant: StimulantEvent): TypeModuleResponse.ModuleResponse
	local characterStimulant = getCharacterStimulantBind(character)
	if not characterStimulant then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterStimulant bindable not found")
	end

	characterStimulant:Fire(TypeStimulant.MessageTypes.Stimulant, stimulant)
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character stimulant sent successfully")
end

-- Tells one character that the stimulant with this id is no longer true, so it can drop it from its queue
function CharacterUtility.sendStimulantRetraction(character: Model, id: number): TypeModuleResponse.ModuleResponse
	local characterStimulant = getCharacterStimulantBind(character)
	if not characterStimulant then
		return response(false, true, TypeRequests.Enums.StatusCode.NotFound, "CharacterStimulant bindable not found")
	end

	characterStimulant:Fire(TypeStimulant.MessageTypes.Retract, id)
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Character stimulant retraction sent successfully")
end

-- Delivers the same stimulant to every character in the list; characters without the bind are skipped.
-- Data is how many were reached.
function CharacterUtility.sendStimulantToMany(
	characters: { Model },
	stimulant: StimulantEvent
): TypeModuleResponse.ModuleResponse
	local delivered = 0
	for _, character in characters do
		if CharacterUtility.sendStimulant(character, stimulant).Success then
			delivered += 1
		end
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Character stimulant sent to " .. delivered .. " of " .. #characters .. " characters",
		delivered
	)
end

-- Plain lookups for other API modules on hot paths (per-frame requests), where building a ModuleResponse
-- for every humanoid/root part lookup is wasted garbage. Not reachable as useful requests, hence the underscore.
function CharacterUtility._getHumanoid(character: Model): Humanoid?
	return getHumanoid(character)
end

function CharacterUtility._getRootPart(character: Model): BasePart?
	return getRootPart(character)
end

-- For the Stimulants registry to cache, so a delivery doesn't walk the ModNPC folder every time
function CharacterUtility._getStimulantBind(character: Model): BindableEvent?
	return getCharacterStimulantBind(character)
end

function CharacterUtility._validationReady(): boolean
	local isReady = teamGetterFunction and contentValidationFunction
	return isReady
end

function CharacterUtility.init(api: {}?)
	print("V1 CharacterUtility initialized")
	CharacterUtility.API = api
end

return CharacterUtility
