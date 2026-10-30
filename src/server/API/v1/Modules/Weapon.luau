local ServerScriptService = game:GetService("ServerScriptService")
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local InstanceSearch = require(ServerScriptService.ModNPCServer.Util.InstanceSearch)
local CharacterUtility = require(script.Parent.CharacterUtility)
local ModFolder = require(script.Parent.ContentDelivery.ModFolder)
local Weapon = {}

-- A dropped weapon lands this far in front of the character, onto ground found this far below that point
local DROP_DISTANCE = 3
local DROP_GROUND_RANGE = 50

local MODWEAPON_KIND = ModFolder.Kinds.ModWeapon
local WEAPON_MODEL_NAME = "WeaponModel"
local EQUIPPED_NAME = "_EQUIPPED"
local WELD_NAME = "WeaponWeld"
local WELD_SETTINGS_NAME = "WeldSettings"
local CHARACTER_PART_SETTING = "CharacterPartName0"
local TOOL_PART_SETTING = "ToolPartName1"

local function response(
	success: boolean,
	statusCode: number,
	message: string?,
	data: any?
): TypeModuleResponse.ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

-- A weapon is a ModWeapon folder, a WeaponModel and an _EQUIPPED flag side by side inside a container (usually a Model
-- parented to the character that carries it). Returns the parts of it that equip/unequip work with, or why it is invalid.
local function readWeapon(weapon: Instance): (any?, string?)
	if typeof(weapon) ~= "Instance" then
		return nil, "Weapon is not an Instance"
	end

	local modWeapon = ModFolder.find(weapon, MODWEAPON_KIND)
	if not modWeapon then
		return nil, "Weapon has no " .. MODWEAPON_KIND .. " folder"
	end

	local isValid, message = ModFolder.validate(MODWEAPON_KIND, modWeapon)
	if not isValid then
		return nil, message
	end

	local weaponModel = weapon:FindFirstChild(WEAPON_MODEL_NAME)
	if not weaponModel or not weaponModel:IsA("Model") then
		return nil, "Weapon is missing its " .. WEAPON_MODEL_NAME .. " model"
	end

	local equipped = weapon:FindFirstChild(EQUIPPED_NAME)
	if not equipped or not equipped:IsA("BoolValue") then
		return nil, "Weapon is missing its " .. EQUIPPED_NAME .. " BoolValue"
	end

	-- the schema already guarantees WeldSettings and its two values exist with the right value type
	local weldSettings = modWeapon[CharacterUtility.CoreFolderNames.Configuration][WELD_SETTINGS_NAME]
	local characterPartName = weldSettings[CHARACTER_PART_SETTING].Value :: string
	local toolPartName = weldSettings[TOOL_PART_SETTING].Value :: string

	local toolPart = weaponModel:FindFirstChild(toolPartName, true)
	if not toolPart or not toolPart:IsA("BasePart") then
		return nil, "Weapon model has no part named " .. toolPartName .. " (" .. TOOL_PART_SETTING .. ")"
	end

	return {
		Weapon = weapon,
		WeaponModel = weaponModel,
		Equipped = equipped,
		CharacterPartName = characterPartName,
		ToolPart = toolPart,
		-- the part whose collision is toggled; models without a PrimaryPart fall back to the welded tool part
		CollisionPart = weaponModel.PrimaryPart or toolPart,
	},
		nil
end

-- A weapon belongs to the character it is parented under
local function ownedBy(weapon: Instance, character: Model): boolean
	return typeof(character) == "Instance" and weapon:IsDescendantOf(character)
end

function Weapon.isValidWeapon(weapon: Instance): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	return response(
		info ~= nil,
		TypeRequests.Enums.StatusCode.Success,
		if info then "Weapon is valid" else message,
		info ~= nil
	)
end

function Weapon.isEquipped(weapon: Instance): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	if not info then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, message)
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon equip state retrieved", info.Equipped.Value)
end

-- Welds the weapon to the character part named in its WeldSettings and flags it as equipped. Data is the WeaponWeld.
function Weapon.equipWeapon(character: Model, weapon: Instance): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	if not info then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, message)
	end

	if not ownedBy(weapon, character) then
		return response(false, TypeRequests.Enums.StatusCode.Conflict, "Weapon does not belong to the character")
	end

	if info.Equipped.Value then
		return response(false, TypeRequests.Enums.StatusCode.Conflict, "Weapon is already equipped")
	end

	local characterPart = character:FindFirstChild(info.CharacterPartName)
	if not characterPart or not characterPart:IsA("BasePart") then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			"Character has no part named " .. info.CharacterPartName .. " (" .. CHARACTER_PART_SETTING .. ")"
		)
	end

	-- Never stack welds: a leftover one (a hand-edited weapon, a failed unequip) is replaced
	local oldWeld = info.ToolPart:FindFirstChild(WELD_NAME)
	if oldWeld then
		oldWeld:Destroy()
	end

	-- An anchored (resting) tool part would stay put and the weld couldn't move it
	info.ToolPart.Anchored = false

	-- A held weapon must not collide with the character carrying it or with anything else
	info.CollisionPart.CanCollide = false

	local weld = Instance.new("Motor6D")
	weld.Name = WELD_NAME
	weld.Part0 = characterPart
	weld.Part1 = info.ToolPart
	weld.C0 = CFrame.identity
	weld.C1 = CFrame.identity
	weld.Parent = info.ToolPart

	info.Equipped.Value = true
	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon equipped", weld)
end

-- Takes an equipped weapon out of the hand: no weld, flagged unequipped, at rest where it is
local function release(info: any)
	local weld = info.ToolPart:FindFirstChild(WELD_NAME)
	if weld then
		weld:Destroy()
	end

	-- Nothing holds an unequipped weapon, so it is anchored where it was dropped instead of falling out of the world
	-- (a weapon that falls past FallenPartsDestroyHeight takes its whole model with it)
	info.ToolPart.Anchored = true

	-- Collision comes back once the weapon is no longer held
	info.CollisionPart.CanCollide = true

	info.Equipped.Value = false
end

-- Removes the WeaponWeld and flags the weapon as no longer equipped
function Weapon.unequipWeapon(character: Model, weapon: Instance): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	if not info then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, message)
	end

	if not ownedBy(weapon, character) then
		return response(false, TypeRequests.Enums.StatusCode.Conflict, "Weapon does not belong to the character")
	end

	if not info.Equipped.Value then
		return response(false, TypeRequests.Enums.StatusCode.Conflict, "Weapon is not equipped")
	end

	release(info)
	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon unequipped")
end

-- Lets go of the weapon for good: unequips it if it is held, then puts it into the workspace resting on the ground in
-- front of the character. It no longer belongs to the character afterwards. Data is whether the weapon was equipped.
function Weapon.dropWeapon(character: Model, weapon: Instance): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	if not info then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, message)
	end

	if not ownedBy(weapon, character) then
		return response(false, TypeRequests.Enums.StatusCode.Conflict, "Weapon does not belong to the character")
	end

	local wasEquipped = info.Equipped.Value
	if wasEquipped then
		release(info)
	end

	local rootPart = CharacterUtility._getRootPart(character)
	if rootPart then
		local model: Model = info.WeaponModel
		local dropPoint = (rootPart.CFrame * CFrame.new(0, 0, -DROP_DISTANCE)).Position
		model:PivotTo(model:GetPivot().Rotation + dropPoint)

		-- Rest the model on whatever is underneath, so it does not hang in the air at waist height
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character, weapon }
		local ground = workspace:Raycast(dropPoint, Vector3.new(0, -DROP_GROUND_RANGE, 0), params)
		if ground then
			local boundsCFrame, boundsSize = model:GetBoundingBox()
			local lowest = boundsCFrame.Position.Y - boundsSize.Y / 2
			model:PivotTo(model:GetPivot() + Vector3.new(0, ground.Position.Y - lowest, 0))
		end
	end

	weapon.Parent = workspace
	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon dropped", wasEquipped)
end

-- Reads one setting out of the weapon's Config directory, e.g. { "WeaponSettings", "AlwaysArmed" }. Data is its value.
function Weapon.getWeaponSetting(weapon: Instance, path: { string }): TypeModuleResponse.ModuleResponse
	local info, message = readWeapon(weapon)
	if not info then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, message)
	end

	if typeof(path) ~= "table" or #path == 0 then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Setting path must be a list of names")
	end

	local modWeapon = ModFolder.find(weapon, MODWEAPON_KIND) :: Folder
	local configuration = modWeapon[CharacterUtility.CoreFolderNames.Configuration]
	local setting = InstanceSearch.findPath(configuration, path, "ValueBase")
	if not setting then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			"Weapon has no setting " .. table.concat(path, "/")
		)
	end

	local valid, value = InstanceSearch.getPrimitiveValue(setting)
	if not valid then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Weapon setting " .. table.concat(path, "/") .. " does not contain a supported primitive"
		)
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon setting retrieved", value)
end

-- Every valid weapon carried by the character (direct children), invalid ones are skipped silently
function Weapon.getWeapons(character: Model): TypeModuleResponse.ModuleResponse
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end

	local weapons = {}
	for _, child in ipairs(character:GetChildren()) do
		if ModFolder.find(child, MODWEAPON_KIND) and readWeapon(child) then
			table.insert(weapons, child)
		end
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapons retrieved", weapons)
end

-- The weapon currently flagged as equipped, nil when the hands are empty
function Weapon.getEquippedWeapon(character: Model): TypeModuleResponse.ModuleResponse
	local weapons = Weapon.getWeapons(character)
	if not weapons.Success then
		return weapons
	end

	for _, weapon in ipairs(weapons.Data) do
		if weapon:FindFirstChild(EQUIPPED_NAME).Value then
			return response(true, TypeRequests.Enums.StatusCode.Success, "Equipped weapon retrieved", weapon)
		end
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "No weapon equipped")
end

function Weapon.init(_)
	print("V1 Weapon initialized")
end

return Weapon
