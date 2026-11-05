local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local Generic = require(script.Parent.Generic)

-- STUB. Not integrated: this answers exactly like Generic and never claims a character.
-- To build it, we need to know:
--   Detect: what marks a model as a Standard v2 NPC
--   GetTeam: where a Standard v2 NPC keeps its team
--   Ask: whether it has anything like stagger or stamina to read
local StandardV2: TypeCharacterHandle.Adapter = table.clone(Generic)
StandardV2.Name = "StandardV2"

return StandardV2
