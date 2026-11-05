local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)
local Generic = require(script.Generic)
local Jeff = require(script.Jeff)
local MainScript = require(script.MainScript)
local ModNPC = require(script.ModNPC)
local StandardV1 = require(script.StandardV1)
local StandardV2 = require(script.StandardV2)

type Adapter = TypeCharacterHandle.Adapter

local Adapters = {}

-- Other NPC systems, tried in order on whatever isn't a ModNPC. All stubs for now: none of them claims a character yet.
local OTHER_SYSTEMS: { Adapter } = { Jeff, MainScript, StandardV1, StandardV2 }

-- The adapter for a character, from the type discovery decided on
function Adapters.select(character: Model, characterType: string): Adapter
	if characterType == CharacterUtility.Type.ModNPC then
		return ModNPC
	end

	for _, adapter in OTHER_SYSTEMS do
		if adapter.Detect(character) then
			return adapter
		end
	end

	return Generic
end

return Adapters
