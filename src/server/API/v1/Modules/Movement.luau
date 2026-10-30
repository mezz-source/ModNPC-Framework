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
-- Combined directions shorter than this are treated as cancelling out
local CANCEL_EPSILON = 0.01
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
-- Several directions are summed into one heading, so a character can advance and strafe in a single move.
-- Directions that cancel out (Left + Right) leave nowhere to go, which stops the character.
function Movement.moveInDirection(
	character: Model,
	directions: TypeMovement.MovementDirections
): TypeModuleResponse.ModuleResponse
	local humanoid = CharacterUtility._getHumanoid(character)
	local rootPart = CharacterUtility._getRootPart(character)
	if not humanoid or not rootPart then
		return response(
			false,
			"Character is missing a Humanoid or root part",
			TypeRequests.Enums.StatusCode.Conflict
		)
	end

	local list = if type(directions) == "table" then directions else { directions }
	local transform = rootPart.CFrame
	local offset = Vector3.zero
	for _, direction in list do
		if direction == MovementEnum.Left then
			offset -= transform.RightVector
		elseif direction == MovementEnum.Right then
			offset += transform.RightVector
		elseif direction == MovementEnum.Forward then
			offset += transform.LookVector
		elseif direction == MovementEnum.Backward then
			offset -= transform.LookVector
		else
			return response(false, "Invalid movement direction", TypeRequests.Enums.StatusCode.Conflict)
		end
	end

	if offset.Magnitude < CANCEL_EPSILON then
		humanoid:MoveTo(transform.Position)
		return response(true, "Movement directions cancelled out", TypeRequests.Enums.StatusCode.Success)
	end

	humanoid:MoveTo(transform.Position + offset.Unit * MOVE_LEAD)
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

-- A burst of `velocityChange` studs/s along directions relative to where the character faces (summed like
-- moveInDirection, so Forward + Left is a diagonal), flattened to horizontal. Scaled by mass, like applyImpulse.
function Movement.applyImpulseInDirection(
	character: Model,
	directions: TypeMovement.MovementDirections,
	velocityChange: number
): TypeModuleResponse.ModuleResponse
	local rootPart = if typeof(character) == "Instance" and character:IsA("Model")
		then CharacterUtility._getRootPart(character)
		else nil
	if not rootPart then
		return response(false, "Character is missing a root part", TypeRequests.Enums.StatusCode.Conflict)
	end
	if typeof(velocityChange) ~= "number" or velocityChange ~= velocityChange then
		return response(false, "Velocity change must be a number", TypeRequests.Enums.StatusCode.Conflict)
	end

	local list = if type(directions) == "table" then directions else { directions }
	local transform = rootPart.CFrame
	local offset = Vector3.zero
	for _, direction in list do
		if direction == MovementEnum.Left then
			offset -= transform.RightVector
		elseif direction == MovementEnum.Right then
			offset += transform.RightVector
		elseif direction == MovementEnum.Forward then
			offset += transform.LookVector
		elseif direction == MovementEnum.Backward then
			offset -= transform.LookVector
		else
			return response(false, "Invalid movement direction", TypeRequests.Enums.StatusCode.Conflict)
		end
	end

	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < CANCEL_EPSILON then
		return response(false, "Movement directions cancelled out", TypeRequests.Enums.StatusCode.Conflict)
	end

	rootPart:ApplyImpulse(flat.Unit * velocityChange * rootPart.AssemblyMass)
	return response(true, "Impulse applied", TypeRequests.Enums.StatusCode.Success)
end

-- Unlike applyImpulse these take a force, applied as it is: the same force moves a light character further than a heavy one.
-- Only the root part is needed, so any character can be pushed (players and plain rigs included), but ownership of a
-- client-owned character is up to the caller.
local function applyHorizontalForce(
	character: Model,
	direction: Vector3,
	force: number
): TypeModuleResponse.ModuleResponse
	local rootPart = if typeof(character) == "Instance" and character:IsA("Model")
		then CharacterUtility._getRootPart(character)
		else nil
	if not rootPart then
		return response(false, "Character is missing a root part", TypeRequests.Enums.StatusCode.Conflict)
	end
	if typeof(force) ~= "number" or force ~= force or force < 0 then
		return response(false, "Force must be a non-negative number", TypeRequests.Enums.StatusCode.Conflict)
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < CANCEL_EPSILON then
		return response(false, "There is no horizontal direction to push in", TypeRequests.Enums.StatusCode.Conflict)
	end

	rootPart:ApplyImpulse(flat.Unit * force)
	return response(true, "Force applied", TypeRequests.Enums.StatusCode.Success)
end

-- Throws the character the way it faces
function Movement.applyForwardImpulse(character: Model, force: number): TypeModuleResponse.ModuleResponse
	local rootPart = if typeof(character) == "Instance" and character:IsA("Model")
		then CharacterUtility._getRootPart(character)
		else nil
	if not rootPart then
		return response(false, "Character is missing a root part", TypeRequests.Enums.StatusCode.Conflict)
	end

	return applyHorizontalForce(character, rootPart.CFrame.LookVector, force)
end

-- Throws the character away from another one (knockback)
function Movement.applyImpulseAwayFrom(
	character: Model,
	origin: Model,
	force: number
): TypeModuleResponse.ModuleResponse
	local rootPart = if typeof(character) == "Instance" and character:IsA("Model")
		then CharacterUtility._getRootPart(character)
		else nil
	local originRoot = if typeof(origin) == "Instance" and origin:IsA("Model")
		then CharacterUtility._getRootPart(origin)
		else nil
	if not rootPart or not originRoot then
		return response(false, "Character and origin both need a root part", TypeRequests.Enums.StatusCode.Conflict)
	end

	return applyHorizontalForce(character, rootPart.Position - originRoot.Position, force)
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
