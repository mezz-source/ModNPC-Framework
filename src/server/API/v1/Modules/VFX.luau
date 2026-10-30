local Debris = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.CharacterUtility)
local VFX = {}

type VFXData = TypeCDN.VFXData

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

-- A part is used as it is. A character resolves to its root part here, so callers playing an effect on a character
-- don't need a request of their own to find it.
local function resolveDestination(destination: any): BasePart?
	if typeof(destination) ~= "Instance" then
		return nil
	end

	local part = if destination:IsA("Model") then CharacterUtility._getRootPart(destination) else destination
	if not part or not part:IsA("BasePart") or part.Parent == nil then
		return nil
	end

	return part
end

-- Plays every effect at the destination: each is cloned onto it, emitted (EmitCount, 1 by default) and, when it has
-- an EnableTime, enabled for that many seconds. The clones clean themselves up once they are done.
-- The destination is a part in the world, or a character, whose root part is used.
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
			"Destination must be a BasePart in the world, or a character with a root part"
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

function VFX.init(_)
	print("V1 VFX initialized")
end

return VFX
