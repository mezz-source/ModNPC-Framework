local ServerScriptService = game:GetService("ServerScriptService")
local AttacksNetwork = {}

local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)
local ModFolder = require(script.Parent.ModFolder)

type AttackData = TypeAttack.AttackData

local HIT_PREFIX = "Attack"

-- A value instance an attack folder has to hold. Problem names what is wrong with a value, nothing when it is fine.
type Field = {
	Name: string,
	ClassName: string,
	Problem: ((value: any) -> string?)?,
	-- A field with a default may be left out of the folder, and reads as the default then
	Default: any?,
}

local function notNegative(value: number): string?
	-- written this way round so NaN fails too
	if not (value >= 0) then
		return "must not be negative"
	end

	return nil
end

local function notEmpty(value: string): string?
	if value == "" then
		return "must not be empty"
	end

	return nil
end

local function positive(value: number): string?
	-- written this way round so NaN fails too
	if not (value > 0) then
		return "must be greater than zero"
	end

	return nil
end

local function oneOf(options: { [string]: string }): (string) -> string?
	local names = {}
	for name in pairs(options) do
		table.insert(names, name)
	end
	table.sort(names)
	local message = "must be one of " .. table.concat(names, ", ")

	return function(value: string): string?
		if options[value] == nil then
			return message
		end

		return nil
	end
end

-- For a field that may be left empty: empty passes, anything else has to pass `problem`
local function emptyOr(problem: (value: string) -> string?): (string) -> string?
	return function(value: string): string?
		if value == "" then
			return nil
		end

		return problem(value)
	end
end

local ATTACK_FIELDS: { Field } = {
	{ Name = "Type", ClassName = "StringValue", Problem = oneOf(TypeAttack.DataAttackTypes) },
	{ Name = "Limbs", ClassName = "StringValue", Problem = oneOf(TypeAttack.Limbs) },
	{ Name = "DesiredRange", ClassName = "IntValue", Problem = positive },
	{ Name = "IsCombo", ClassName = "BoolValue" },
	{ Name = "Debounce", ClassName = "NumberValue", Problem = notNegative },
	{ Name = "AllowMoving", ClassName = "BoolValue" },
	{ Name = "AllowInterrupts", ClassName = "BoolValue" },
	{ Name = "SwingSoundName", ClassName = "StringValue" },
}

-- Sounds may be empty for a silent hit (SwingSoundName, which is on the attack itself, included), and so may HitVFXName
-- and Special (a hit with no special effect). Whether a sound or VFX exists is up to the Assets directory.
local HIT_FIELDS: { Field } = {
	{ Name = "BaseDamage", ClassName = "NumberValue", Problem = notNegative },
	{ Name = "DamageType", ClassName = "StringValue", Problem = oneOf(TypeDamage.DamageTypes) },
	{ Name = "AttackWeight", ClassName = "StringValue", Problem = oneOf(TypeAttack.AttackWeights) },
	{ Name = "LungeForce", ClassName = "NumberValue", Problem = notNegative },
	{ Name = "KnockbackForce", ClassName = "NumberValue", Problem = notNegative },
	{ Name = "HitSoundName", ClassName = "StringValue" },
	{ Name = "HitVFXName", ClassName = "StringValue" },
	{ Name = "Special", ClassName = "StringValue", Problem = emptyOr(oneOf(TypeDamage.Specials)) },
	-- Only a Stagger reads it, so a hit with any other special (or none) can leave it out
	{ Name = "MaxStaggerTime", ClassName = "NumberValue", Problem = notNegative, Default = 0 },
	{ Name = "AnimationEventName", ClassName = "StringValue", Problem = notEmpty },
}

local function readFields(parent: Instance, fields: { Field }, path: string): ({ [string]: any }?, string?)
	local values = {}

	for _, field in ipairs(fields) do
		local fieldPath = path .. "/" .. field.Name
		local child = parent:FindFirstChild(field.Name)
		if not child and field.Default ~= nil then
			values[field.Name] = field.Default
			continue
		end
		if not child then
			return nil, "Missing attack value: " .. fieldPath
		end

		if not child:IsA(field.ClassName) then
			return nil, "Invalid attack value type, expected " .. field.ClassName .. ": " .. fieldPath
		end

		local value = (child :: any).Value
		local problem = if field.Problem then field.Problem(value) else nil
		if problem then
			return nil, "Invalid attack value, " .. fieldPath .. " " .. problem
		end

		values[field.Name] = value
	end

	return values, nil
end

local function readHit(attackFolder: Folder, hitName: string, path: string): (TypeAttack.AttackHit?, string?)
	local hitPath = path .. "/" .. hitName
	local hitFolder = attackFolder:FindFirstChild(hitName)
	if not hitFolder then
		return nil, "Missing attack hit: " .. hitPath
	end

	if not hitFolder:IsA("Folder") then
		return nil, "Expected attack hit folder: " .. hitPath
	end

	local values, problem = readFields(hitFolder, HIT_FIELDS, hitPath)
	if not values then
		return nil, problem
	end

	values.Name = hitName
	return values :: any, nil
end

-- Reads one attack folder into its data, or says why it can't be. Shared by validation and (later) loading,
-- so what passes validation is exactly what gets read.
local function readAttack(attackFolder: Folder): (AttackData?, string?)
	local path = attackFolder.Name
	local values, problem = readFields(attackFolder, ATTACK_FIELDS, path)
	if not values then
		return nil, problem
	end

	-- A combo reads Attack1, Attack2, ... until the numbering stops. Everything else reads Attack1 and ignores the rest.
	local hits: { TypeAttack.AttackHit } = {}
	local hitLimit = if values.IsCombo then math.huge else 1
	while #hits < hitLimit do
		local hitName = HIT_PREFIX .. (#hits + 1)
		if #hits > 0 and not attackFolder:FindFirstChild(hitName) then
			break
		end

		local hit, hitProblem = readHit(attackFolder, hitName, path)
		if not hit then
			return nil, hitProblem
		end

		table.insert(hits, hit)
	end

	if values.IsCombo then
		-- a hit past a gap would be skipped silently, so it is an error instead
		for _, child in ipairs(attackFolder:GetChildren()) do
			local number = tonumber(string.match(child.Name, "^" .. tostring(HIT_PREFIX) .. "(%d+)$"))
			if number and number > #hits then
				return nil,
					"Combo hits must be numbered without gaps: "
						.. path
						.. "/"
						.. child.Name
						.. " follows missing "
						.. HIT_PREFIX
						.. (#hits + 1)
			end
		end
	end

	return {
		Name = attackFolder.Name,
		Type = values.Type,
		Limbs = values.Limbs,
		DesiredRange = values.DesiredRange,
		IsCombo = values.IsCombo,
		Debounce = values.Debounce,
		AllowMoving = values.AllowMoving,
		AllowInterrupts = values.AllowInterrupts,
		SwingSoundName = values.SwingSoundName,
		Hits = hits,
	},
		nil
end

function AttacksNetwork.init(_) end

-- Every child of the Attacks directory is an attack folder. An empty directory is fine (no attacks).
function AttacksNetwork.validateAttacksFolder(attacksFolder: Folder): (boolean, string)
	local seen: { [string]: boolean } = {}

	for _, child in ipairs(attacksFolder:GetChildren()) do
		if not child:IsA("Folder") then
			return false, "Expected attack folder: " .. child.Name
		end

		if seen[child.Name] then
			return false, "Duplicate attack: " .. child.Name
		end
		seen[child.Name] = true

		local attack, problem = readAttack(child)
		if not attack then
			return false, problem or "Invalid attack: " .. child.Name
		end
	end

	return true, ""
end

-- Reads every attack of a character (its ModNPC folder) or a weapon (its ModWeapon folder), keyed by attack name.
-- Reads exactly what validation accepts, so an attack that fails here fails the whole index.
function AttacksNetwork.getAttacksIndex(container: Instance): TypeModuleResponse.ModuleResponse
	local function response(success: boolean, message: string, data: any?): TypeModuleResponse.ModuleResponse
		return {
			Success = success,
			PassResponse = true,
			StatusCode = if success then TypeRequests.Enums.StatusCode.Success else TypeRequests.Enums.StatusCode.Conflict,
			Message = message,
			Data = data,
		}
	end

	if typeof(container) ~= "Instance" then
		return response(false, "Container must be an Instance")
	end

	local attacksFolder = ModFolder.findDirectory(container, CharacterUtility.CoreFolderNames.Attacks)
	if not attacksFolder then
		return response(false, "Attacks folder not found")
	end

	local index: TypeAttack.AttackIndex = {}
	for _, child in ipairs(attacksFolder:GetChildren()) do
		if not child:IsA("Folder") then
			return response(false, "Expected attack folder: " .. child.Name)
		end

		local attack, problem = readAttack(child)
		if not attack then
			return response(false, problem or "Invalid attack: " .. child.Name)
		end

		index[attack.Name] = attack
	end

	return response(true, "Attack index generated", index)
end

return AttacksNetwork
