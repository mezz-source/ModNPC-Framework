local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local Generic = require(script.Parent.Generic)

-- STUB. Not integrated: this answers exactly like Generic and never claims a character.
-- To build it, we need to know:
--   Detect: what marks a model as a Standard v1 NPC
--   GetTeam: where a Standard v1 NPC keeps its team
--   Ask: whether it has anything like stagger or stamina to read
local StandardV1: TypeCharacterHandle.Adapter = table.clone(Generic)
StandardV1.Name = "StandardV1"

return StandardV1
