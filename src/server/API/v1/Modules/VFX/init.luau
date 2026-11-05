local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeVFX = require(ServerScriptService.ModNPCServer.Types.v1.TypeVFX)
local CharacterUtility = require(script.Parent.CharacterUtility)
local Weapon = require(script.Parent.Weapon)
local ParticleClass = require(script.Particle)
local VFX = {}

type VFXData = TypeCDN.VFXData
type ParticleEmitterData = TypeCDN.ParticleEmitterData

-- Cleanup waits this long past the last moment an effect can still be seen, so its final particles aren't cut off
local CLEANUP_PADDING = 0.25

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

-- The template has to still be in the Assets folder it was indexed from (a weapon's may have been destroyed since)
local function validateVFXData(effect: any): string?
	if typeof(effect) ~= "table" then
		return "VFX data is not a table"
	end

	local template = effect.Template
	if typeof(template) ~= "Instance" or template.Parent == nil then
		return "Template is missing or destroyed"
	end

	if effect.Type == "ParticleEmitter" then
		if not template:IsA("ParticleEmitter") then
			return "Template is not a ParticleEmitter"
		end
		if typeof(effect.EmitCount) ~= "number" or effect.EmitCount < 0 then
			return "EmitCount must be a number of 0 or more"
		end
	elseif effect.Type == "PointLight" then
		if not template:IsA("PointLight") then
			return "Template is not a PointLight"
		end
	else
		return "Unsupported VFX type: " .. tostring(effect.Type)
	end

	if effect.EnableTime ~= nil and (typeof(effect.EnableTime) ~= "number" or effect.EnableTime <= 0) then
		return "EnableTime must be a number above 0"
	end

	return nil
end

-- Clones the effect onto the destination and schedules its cleanup. The effect always starts disabled so a template
-- left enabled doesn't emit on its own; only an EnableTime turns it on.
local function spawnVFX(effect: VFXData, destination: BasePart): Instance
	local clone = effect.Template:Clone()
	clone.Enabled = false
	clone.Parent = destination

	-- how long the effect can still be seen
	local visibleFor = 0

	if effect.Type == "ParticleEmitter" then
		clone:Emit(effect.EmitCount)
		-- particles outlive the emitter
		visibleFor += clone.Lifetime.Max
	end

	if effect.EnableTime then
		clone.Enabled = true
		visibleFor += effect.EnableTime

		task.delay(effect.EnableTime, function()
			if clone.Parent then
				clone.Enabled = false
			end
		end)
	end

	-- The destination taking the clone with it when it is destroyed is fine; Debris only has to catch the rest
	Debris:AddItem(clone, visibleFor + CLEANUP_PADDING)
	return clone
end

-- A part is used as it is. A model resolves to its PrimaryPart (a character's root part), and a weapon, whose container
-- has none, to the part of its WeaponModel. Callers just pass what they hold, without a request of their own to find it.
local function resolveDestination(destination: any): BasePart?
	if typeof(destination) ~= "Instance" then
		return nil
	end

	local part = if destination:IsA("Model")
		then CharacterUtility._getRootPart(destination) or Weapon._getPart(destination)
		else destination
	if not part or not part:IsA("BasePart") or part.Parent == nil then
		return nil
	end

	return part
end

-- Plays every effect at the destination: each is cloned onto it, emitted (EmitCount, 1 by default) and, when it has
-- an EnableTime, enabled for that many seconds. The clones clean themselves up once they are done.
-- The destination is a part in the world, or a model (a character, a weapon) that resolves to its part.
-- Data is the list of clones created. An effect that cannot be played is warned about and skipped.
function VFX.playVFX(
	character: Model,
	effects: { VFXData },
	destination: BasePart | Model
): TypeModuleResponse.ModuleResponse
	if typeof(effects) ~= "table" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "VFX must be a list of VFX data")
	end

	local part = resolveDestination(destination)
	if not part then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Destination must be a BasePart in the world, or a model with a PrimaryPart, or a weapon"
		)
	end

	local spawned = {}
	for _, effect in ipairs(effects) do
		local invalidReason = validateVFXData(effect)
		if invalidReason then
			local effectName = if typeof(effect) == "table" and effect.Name then tostring(effect.Name) else "?"
			warn(character.Name, "skipping VFX", effectName .. ":", invalidReason)
			continue
		end

		table.insert(spawned, spawnVFX(effect, part))
	end

	if #spawned == 0 then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, "No VFX could be played")
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "VFX playing", spawned)
end

-- A fixed spot in the world has no part to hold the emitter, so it gets an attachment on Terrain, which sits at the world
-- origin: the attachment's CFrame is its world CFrame. Nil for anything that isn't a spot in the world.
local function makeWorldAnchor(location: any, effectName: string): Attachment?
	local locationType = typeof(location)
	if locationType ~= "Vector3" and locationType ~= "CFrame" then
		return nil
	end

	local anchor = Instance.new("Attachment")
	anchor.Name = effectName .. "Anchor"
	anchor.CFrame = if locationType == "Vector3" then CFrame.new(location) else location
	anchor.Parent = workspace.Terrain
	return anchor
end

-- Makes a particle that stays at the location until it is destroyed. Unlike playVFX nothing happens on its own: it starts
-- disabled with nothing emitted, and EnableTime is not used. Data is the particle: a table of methods that drives it
-- directly, so nothing needs to be requested to emit, enable or disable it.
-- The location is a part, a model that resolves to its part, or a Vector3/CFrame in the world. The particle ends with the
-- part it is on or the character that made it, so one left at a spot in the world can't outlive its character.
function VFX.createParticle(
	character: Model,
	effect: ParticleEmitterData,
	location: TypeVFX.ParticleLocation
): TypeModuleResponse.ModuleResponse
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end

	local invalidReason = validateVFXData(effect)
	if invalidReason then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Invalid VFX data: " .. invalidReason)
	end

	if effect.Type ~= "ParticleEmitter" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "A particle needs a ParticleEmitter effect")
	end

	local anchor = makeWorldAnchor(location, effect.Name)
	local parent = anchor or resolveDestination(location)
	if not parent then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Location must be a Vector3, a CFrame, a BasePart in the world, a model with a PrimaryPart, or a weapon"
		)
	end

	local emitter = effect.Template:Clone()
	emitter.Enabled = false
	emitter.Parent = parent

	return response(
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Particle created",
		ParticleClass.new(emitter, effect.EmitCount, character, anchor)
	)
end

-- Turns the weapon's trail on or off. A weapon that doesn't use one is left alone and that is still a success, so callers
-- don't have to know which weapons do. The weapon isn't checked against a character: one dropped mid swing is nobody's
-- anymore, and its trail still has to go off.
function VFX.setWeaponTrail(weapon: Instance, enabled: boolean): TypeModuleResponse.ModuleResponse
	if typeof(enabled) ~= "boolean" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Enabled must be a boolean")
	end

	local trail, problem = Weapon._getTrail(weapon)
	if problem then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, problem)
	end

	if trail then
		trail.Enabled = enabled
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Weapon trail set")
end

function VFX.init(_)
	print("V1 VFX initialized")
end

return VFX
