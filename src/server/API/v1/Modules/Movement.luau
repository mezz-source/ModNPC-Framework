local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)

local MovementEnum = TypeMovement.MovementEnum

-- Everything the facing loop needs each frame, looked up once when the focus is set
type FocusEntry = {
	Target: Instance,
	Root: BasePart,
	Alignment: AlignOrientation,
	-- The last point written to the alignment, so an unchanged target doesn't rewrite (and replicate) it
	LastPoint: Vector3?,
}

-- How far ahead of the root a directional move aims. Far enough that a caller re-issuing the move every
-- tenth of a second or so never has the humanoid arrive and stall between calls.
local MOVE_LEAD = 4
-- A focus point that moved less than this (studs) isn't worth rewriting the alignment for
local FACE_EPSILON = 0.1

local Movement = {
	FocusTargets = {} :: { [Model]: FocusEntry },
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
	local humanoid = CharacterUtility._getHumanoid(character)
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

-- The alignment looks at the position of its CFrame, so moving it to the target makes the root face the target.
-- It is squashed down to our own height so the character doesn't trip.
-- The alignment is only written when the point moved, since every write is a constraint update that replicates.
local function faceTarget(focus: FocusEntry, targetCFrame: CFrame)
	local targetPosition = targetCFrame.Position
	local point = Vector3.new(targetPosition.X, focus.Root.Position.Y, targetPosition.Z)

	local lastPoint = focus.LastPoint
	if lastPoint and (point - lastPoint).Magnitude < FACE_EPSILON then
		return
	end

	focus.LastPoint = point
	focus.Alignment.CFrame = CFrame.new(point)
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
	local humanoid = CharacterUtility._getHumanoid(character)
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

-- Only needs the humanoid, so it skips the full validateCharacter (focus alignment lookups etc.)
function Movement.moveTo(character: Model, position: Vector3): TypeModuleResponse.ModuleResponse
	local humanoid, errorMessage = getHumanoid(character)
	if not humanoid or typeof(position) ~= "Vector3" then
		return response(false, errorMessage or "Position must be a Vector3", TypeRequests.Enums.StatusCode.Conflict)
	end
	humanoid:MoveTo(position)
	return response(true, "Character moving to position", TypeRequests.Enums.StatusCode.Success)
end

Movement.walkTo = Movement.moveTo

-- Walk in a direction relative to where the character is facing. The caller never has to read the character's
-- transform, and it costs one request instead of a read plus a MoveTo.
function Movement.moveInDirection(character: Model, direction: TypeMovement.MovementDirection): TypeModuleResponse.ModuleResponse
	local humanoid = CharacterUtility._getHumanoid(character)
	local rootPart = CharacterUtility._getRootPart(character)
	if not humanoid or not rootPart then
		return response(
			false,
			"Character is missing a Humanoid or root part",
			TypeRequests.Enums.StatusCode.Conflict
		)
	end

	local transform = rootPart.CFrame
	local offset
	if direction == MovementEnum.Left then
		offset = -transform.RightVector
	elseif direction == MovementEnum.Right then
		offset = transform.RightVector
	elseif direction == MovementEnum.Forward then
		offset = transform.LookVector
	elseif direction == MovementEnum.Backward then
		offset = -transform.LookVector
	else
		return response(false, "Invalid movement direction", TypeRequests.Enums.StatusCode.Conflict)
	end

	humanoid:MoveTo(transform.Position + offset * MOVE_LEAD)
	return response(true, "Character moving in direction", TypeRequests.Enums.StatusCode.Success)
end

-- Cancel any move in progress by walking to where we already are
function Movement.stopMoving(character: Model): TypeModuleResponse.ModuleResponse
	local humanoid = CharacterUtility._getHumanoid(character)
	local rootPart = CharacterUtility._getRootPart(character)
	if not humanoid or not rootPart then
		return response(
			false,
			"Character is missing a Humanoid or root part",
			TypeRequests.Enums.StatusCode.Conflict
		)
	end

	humanoid:MoveTo(rootPart.Position)
	return response(true, "Character stopped moving", TypeRequests.Enums.StatusCode.Success)
end

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
	local _, rootPart, focusAlignment, errorMessage = validateCharacter(character)
	if not focusAlignment or not rootPart then
		return response(false, errorMessage, TypeRequests.Enums.StatusCode.Conflict)
	end
	local targetCFrame = target and target:IsDescendantOf(game) and getTargetCFrame(target)
	if not targetCFrame then
		return response(
			false,
			"Focus target must be a BasePart, Attachment, or Model with a PrimaryPart",
			TypeRequests.Enums.StatusCode.Conflict
		)
	end
	local focus: FocusEntry = { Target = target, Root = rootPart, Alignment = focusAlignment, LastPoint = nil }
	Movement.FocusTargets[character] = focus
	faceTarget(focus, targetCFrame)
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
		for character, focus in pairs(Movement.FocusTargets) do
			if not character.Parent then
				Movement.FocusTargets[character] = nil
				continue
			end

			-- the parts were looked up when the focus was set, so only look again if one was swapped out
			if focus.Root.Parent ~= character or focus.Alignment.Parent ~= focus.Root then
				local _, refPart, focusAlignment = validateCharacter(character)
				if not refPart or not focusAlignment then
					Movement.FocusTargets[character] = nil
					continue
				end
				focus.Root, focus.Alignment, focus.LastPoint = refPart, focusAlignment, nil
			end

			local target = focus.Target
			local targetCFrame = target.Parent and getTargetCFrame(target)
			if not targetCFrame then
				Movement.FocusTargets[character] = nil
			else
				faceTarget(focus, targetCFrame)
			end
		end
	end)
	print("V1 Movement initialized")
end

return Movement
