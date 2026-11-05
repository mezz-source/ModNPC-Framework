local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeVFX = require(ServerScriptService.ModNPCServer.Types.v1.TypeVFX)

local VFX = {}
VFX.__index = VFX

type ContentSource = TypeCDN.ContentSource

function VFX.new(Base: any, character: Model)
	local self = setmetatable({}, VFX)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI

	return self
end

-- Effects stay in the Assets folder they were indexed from and are cloned when played, so unlike sounds nothing is
-- loaded per source. Lookups search like assets do: the NPC first, then weapons in the order they were equipped, and a
-- source passed in is searched first.

-- The destination is a part, or a model to play the effect at its PrimaryPart. A character uses its root part and a weapon
-- the part of its WeaponModel.

-- Plays the individual effect at the destination. Returns false if it is not there or could not be played.
function VFX:Play(vfxName: string, destination: BasePart | Model, source: ContentSource?): boolean
	local effect = self.Base.Assets:GetVFX(vfxName, source)
	if not effect then
		warn("VFX is not available:", vfxName, "for character:", self.Character.Name)
		return false
	end

	return self.CharacterAPI:PlayVFX({ effect }, destination) ~= nil
end

-- Plays every effect of the group at the destination. Returns false if the group is not there or nothing played.
function VFX:PlayGroup(groupName: string, destination: BasePart | Model, source: ContentSource?): boolean
	local effects = self.Base.Assets:GetVFXGroup(groupName, source)
	if not effects then
		warn("VFX group is not available:", groupName, "for character:", self.Character.Name)
		return false
	end

	return self.CharacterAPI:PlayVFX(effects, destination) ~= nil
end

-- Makes a particle from the individual effect, which stays at the location until destroyed. Unlike a played effect nothing
-- cleans it up for the caller, so whoever makes one keeps the object it returns. Nil if it is not there or could not be made.
function VFX:CreateParticle(
	vfxName: string,
	location: TypeVFX.ParticleLocation,
	source: ContentSource?
): TypeVFX.Particle?
	local effect = self.Base.Assets:GetVFX(vfxName, source)
	if not effect then
		warn("VFX is not available:", vfxName, "for character:", self.Character.Name)
		return nil
	end

	return self.CharacterAPI:CreateParticle(effect, location)
end

return VFX
