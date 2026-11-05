local ServerScriptService = game:GetService("ServerScriptService")
local TypeVFX = require(ServerScriptService.ModNPCServer.Types.v1.TypeVFX)
local ParticleClass = {}

type ParticleObject = TypeVFX.Particle

local function isValidEmitCount(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge
end

-- Wraps an emitter in the particle. The particle ends once, however that happens: Destroy, the emitter being destroyed or
-- removed from its parent (which includes the part it is on going), or the owner going. An anchor is an instance made
-- only to hold the emitter, and is destroyed with it.
function ParticleClass.new(
	emitter: ParticleEmitter,
	defaultEmitCount: number,
	owner: Model,
	anchor: Instance?
): ParticleObject
	local name = emitter.Name
	local destroyed = false
	local connections: { RBXScriptConnection } = {}

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true

		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)

		emitter:Destroy()
		if anchor then
			anchor:Destroy()
		end
	end

	local function destroyWith(instance: Instance)
		table.insert(connections, instance.Destroying:Connect(destroy))
		table.insert(
			connections,
			instance.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					destroy()
				end
			end)
		)
	end

	destroyWith(emitter)
	destroyWith(owner)

	local object: ParticleObject = {
		Name = name,

		Emit = function(_self: ParticleObject, count: number?)
			if destroyed then
				return
			end

			local emitCount = if count == nil then defaultEmitCount else count
			if not isValidEmitCount(emitCount) then
				warn("Particle", name, "ignoring invalid emit count (must be 0 or more):", emitCount)
				return
			end

			emitter:Emit(emitCount)
		end,

		Enable = function(_self: ParticleObject)
			if not destroyed then
				emitter.Enabled = true
			end
		end,

		Disable = function(_self: ParticleObject)
			if not destroyed then
				emitter.Enabled = false
			end
		end,

		IsEnabled = function(_self: ParticleObject): boolean
			return not destroyed and emitter.Enabled
		end,

		IsDestroyed = function(_self: ParticleObject): boolean
			return destroyed
		end,

		Destroy = function(_self: ParticleObject)
			destroy()
		end,
	}

	return object
end

return ParticleClass
