local ServerScriptService = game:GetService("ServerScriptService")
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local Damage = {}

local function response(
	success: boolean,
	passResponse: boolean,
	statusCode: number?,
	message: string?,
	data: any?
): TypeModuleResponse.ModuleResponse
	return {
		Success = success,
		PassResponse = passResponse,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

function Damage.takeHumanoidDamage(character: Model, amount: number): TypeModuleResponse.ModuleResponse
	if not character or not character:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid character for takeHumanoidDamage")
	end

	local humanoid = CharacterUtility.getHumanoid(character).Data
	local forceField = CharacterUtility.getForceField(character).Data
	if humanoid and not forceField and humanoid.Health < math.huge then
		humanoid:TakeDamage(amount)
		return response(
			true,
			true,
			TypeRequests.Enums.StatusCode.Success,
			"Humanoid damage applied successfully",
			{ Amount = amount, DidHit = true, RecieveType = TypeDamage.RecieveTypes.Hit }
		)
	else
		return response(
			false,
			true,
			TypeRequests.Enums.StatusCode.Conflict,
			"Character does not have a humanoid for damage, or is immortal"
		)
	end
end

-- Gives health back, up to the max. Refuses a dead humanoid: health can't bring it back to life.
function Damage.restoreHumanoidHealth(character: Model, amount: number): TypeModuleResponse.ModuleResponse
	if not character or not character:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid character for restoreHumanoidHealth")
	end

	-- written this way round so NaN fails too
	if type(amount) ~= "number" or not (amount > 0) then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Health to restore must be more than zero")
	end

	local humanoid = CharacterUtility.getHumanoid(character).Data
	if not humanoid or humanoid.Health <= 0 then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character has no living humanoid to restore")
	end

	local restored = math.min(humanoid.Health + amount, humanoid.MaxHealth)
	if restored <= humanoid.Health then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Humanoid is already at max health")
	end

	humanoid.Health = restored
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Humanoid health restored successfully", restored)
end

function Damage.takeDamage(
	attacker: Model?,
	receiver: Model,
	amount: number,
	damageType: TypeDamage.DamageType?,
	special: TypeDamage.DamageSpecial?,
	maxStaggerTime: number?
): TypeModuleResponse.ModuleResponse
	if not receiver or not receiver:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid receiver for takeDamage")
	end

	if special ~= nil and TypeDamage.Specials[special] == nil then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Unknown damage special: " .. tostring(special))
	end

	-- written this way round so NaN fails too
	if maxStaggerTime ~= nil and (type(maxStaggerTime) ~= "number" or not (maxStaggerTime >= 0)) then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Max stagger time must be zero or more seconds")
	end

	local characterType = CharacterUtility.getCharacterType(receiver).Data
	if not characterType then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Receiver is not a valid character")
	end

	local incomingDamageContext: TypeDamage.IncomingDamageContext = {
		Attacker = attacker,
		Receiver = receiver,
		Amount = amount,
		DamageType = damageType,
		Special = special,
		MaxStaggerTime = maxStaggerTime,
	}

	if characterType == CharacterUtility.Type.ModNPC then
		-- Send the incoming damage context to the character
		local functionResponse = CharacterUtility.sendFunction(receiver, "Damage", incomingDamageContext)
		local responseData = functionResponse.Data
		if not functionResponse.Success or not responseData or responseData.Amount == nil then
			return response(
				false,
				true,
				TypeRequests.Enums.StatusCode.Conflict,
				"ModNPC did not return a correct damage response",
				responseData
			)
		end

		local outgoingDamageContext: TypeDamage.OutgoingDamageContext = {
			Attacker = attacker,
			Receiver = receiver,
			Amount = responseData.Amount,
			DamageType = damageType,
			DidHit = responseData.DidHit,
			RecieveType = responseData.RecieveType,
			Special = responseData.Special,
			StaggerDuration = responseData.StaggerDuration,
			Resisted = responseData.Resisted,
		}

		return response(
			true,
			true,
			TypeRequests.Enums.StatusCode.Success,
			"Damage applied successfully",
			outgoingDamageContext
		)
	else
		local Humanoid = CharacterUtility.getHumanoid(receiver).Data
		if not Humanoid then
			return response(
				false,
				true,
				TypeRequests.Enums.StatusCode.Conflict,
				"Receiver does not have a humanoid for damage"
			)
		end

		Humanoid:TakeDamage(amount)

		local outgoingDamageContext: TypeDamage.OutgoingDamageContext = {
			Attacker = attacker,
			Receiver = receiver,
			Amount = amount,
			DamageType = damageType,
			DidHit = amount > 0,
			RecieveType = TypeDamage.RecieveTypes.Hit,
		}

		return response(
			true,
			true,
			TypeRequests.Enums.StatusCode.Success,
			"Damage applied successfully",
			outgoingDamageContext
		)
	end
end

function Damage.init(_)
	print("V1 Damage initialized")
end

return Damage
