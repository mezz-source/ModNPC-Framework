local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)

local Movement = {
	FocusTargets = {},
}

local function response(
	success: boolean,
	message: string?,
	statusCode: number?,
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

local function getCharacterParts(character: Model): (Humanoid?, BasePart?, AlignOrientation?)
	local humanoid = CharacterUtility.getHumanoid(character).Data
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local focusAlignment = rootPart and rootPart:IsA("BasePart") and rootPart:FindFirstChild("FocusAlignment")
	return humanoid, rootPart :: BasePart?, focusAlignment :: AlignOrientation?
end

local function getTargetCFrame(target: Instance): CFrame?
	if target:IsA("BasePart") then
		return target.CFrame
	elseif target:IsA("Attachment") then
		return target.WorldCFrame
	elseif target:IsA("Model") and target.PrimaryPart then
		return target.PrimaryPart.CFrame
	end
	return nil
end

local function validateCharacter(character: Model): (Humanoid?, BasePart?, AlignOrientation?, string?)
	if not character or not character:IsA("Model") then
		return nil, nil, nil, "Invalid character"
	end

	local humanoid, rootPart, focusAlignment = getCharacterParts(character)
	if not humanoid or not rootPart or not focusAlignment or not focusAlignment:IsA("AlignOrientation") then
		return nil, nil, nil, "Character is missing a Humanoid, HumanoidRootPart, or FocusAlignment"
	end
	return humanoid, rootPart, focusAlignment, nil
end

local function getHumanoid(character: Model): (Humanoid?, string?)
	local humanoid = CharacterUtility.getHumanoid(character).Data
	if not humanoid then
		return nil, "Character is missing a Humanoid"
	end
	return humanoid, nil
end

function Movement.jump(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid = getHumanoid(character)
	if not humanoid then
		return response(false, "Character is missing a Humanoid", TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid.Jump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	return response(true, "Character jumped", TypeRequests.Enums.StatusCode.Success)
end

function Movement.setWalkSpeed(character: Model, speed: number): TypeModuleResponse.ModuleResponse
	local humanoid = getHumanoid(character)
	if not humanoid then
		return response(false, "Character is missing a Humanoid", TypeRequests.Enums.StatusCode.Conflict)
	end
	if typeof(speed) ~= "number" or speed < 0 then
		return response(false, "Speed must be a non-negative number", TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid.WalkSpeed = speed
	return response(true, "Character walk speed set", TypeRequests.Enums.StatusCode.Success)
end

function Movement.moveTo(character: Model, position: Vector3): TypeModuleResponse.ModuleResponse
	local humanoid, _, _, errorMessage = validateCharacter(character)
	if not humanoid or typeof(position) ~= "Vector3" then
		return response(false, errorMessage or "Position must be a Vector3", TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid:MoveTo(position)
	return response(true, "Character moving to position", TypeRequests.Enums.StatusCode.Success)
end

Movement.walkTo = Movement.moveTo

function Movement.lockCharacter(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid, _, _, errorMessage = validateCharacter(character)
	if not humanoid then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid.AutoRotate = false
	return response(true, "Character AutoRotate disabled", TypeRequests.Enums.StatusCode.Success)
end

function Movement.unlockCharacter(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid, _, _, errorMessage = validateCharacter(character)
	if not humanoid then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid.AutoRotate = true
	return response(true, "Character AutoRotate enabled", TypeRequests.Enums.StatusCode.Success)
end

function Movement.lockRotation(character: Model): TypeModuleResponse.ModuleResponse
	local result = Movement.lockCharacter(character)
	if not result.Success then
		return result
	end
	local _, _, focusAlignment = getCharacterParts(character)
	focusAlignment.Enabled = true
	return response(true, "Character rotation locked", TypeRequests.Enums.StatusCode.Success)
end

function Movement.unlockRotation(character: Model): TypeModuleResponse.ModuleResponse
	local result = Movement.unlockCharacter(character)
	if not result.Success then
		return result
	end
	local _, _, focusAlignment = getCharacterParts(character)
	focusAlignment.Enabled = false
	return response(true, "Character rotation unlocked", TypeRequests.Enums.StatusCode.Success)
end

function Movement.setFocusTarget(character: Model, target: Instance): TypeModuleResponse.ModuleResponse
	local _, _, focusAlignment, errorMessage = validateCharacter(character)
	if not focusAlignment then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	if not target or not target:IsDescendantOf(game) or not getTargetCFrame(target) then
		return response(
			false,
			"Focus target must be a BasePart, Attachment, or Model with a PrimaryPart",
			TypeRequests.Enums.StatusCode.Conflict
		)
	end
	Movement.FocusTargets[character] = target
	focusAlignment.CFrame = getTargetCFrame(target)
	return response(true, "Focus target set", TypeRequests.Enums.StatusCode.Success)
end

function Movement.removeFocusTarget(character: Model): TypeModuleResponse.ModuleResponse
	local _, _, focusAlignment, errorMessage = validateCharacter(character)
	if not focusAlignment then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	Movement.FocusTargets[character] = nil
	return response(true, "Focus target removed", TypeRequests.Enums.StatusCode.Success)
end

local function applyMassScaledImpulse(
	character: Model,
	impulse: Vector3,
	apply: (BasePart, Vector3) -> ()
): TypeModuleResponse.ModuleResponse
	local _, rootPart, _, errorMessage = validateCharacter(character)
	if not rootPart then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	if typeof(impulse) ~= "Vector3" then
		return response(false, "Impulse must be a Vector3", TypeRequests.Enums.StatusCode.Conflict)
	end

	apply(rootPart, impulse * rootPart.AssemblyMass)
	return response(true, "Impulse applied", TypeRequests.Enums.StatusCode.Success)
end

function Movement.applyImpulse(character: Model, velocityChange: Vector3): TypeModuleResponse.ModuleResponse
	return applyMassScaledImpulse(character, velocityChange, function(rootPart, impulse)
		rootPart:ApplyImpulse(impulse)
	end)
end

function Movement.applyAngularImpulse(
	character: Model,
	angularVelocityChange: Vector3
): TypeModuleResponse.ModuleResponse
	return applyMassScaledImpulse(character, angularVelocityChange, function(rootPart, impulse)
		rootPart:ApplyAngularImpulse(impulse)
	end)
end

function Movement.init(_)
	RunService.Heartbeat:Connect(function()
		for character, target in pairs(Movement.FocusTargets) do
			local _, refPart, focusAlignment = validateCharacter(character)
			local targetCFrame = target.Parent and getTargetCFrame(target)
			if not character.Parent or not focusAlignment or not targetCFrame then
				Movement.FocusTargets[character] = nil
			else
				-- This squashes it down so the character doesn't trip
				local adjustedPosition =
					CFrame.new(targetCFrame.Position.X, refPart.Position.Y, targetCFrame.Position.Z)
				focusAlignment.CFrame = adjustedPosition
			end
		end
	end)
	print("V1 Movement initialized")
end

return Movement
