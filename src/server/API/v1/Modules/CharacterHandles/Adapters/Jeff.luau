local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local Generic = require(script.Parent.Generic)

-- STUB. Not integrated: this answers exactly like Generic and never claims a character.
-- To build it, we need to know:
--   Detect: what marks a model as a Jeff NPC
--   GetTeam: where a Jeff NPC keeps its team
--   Ask: whether it has anything like stagger or stamina to read
local Jeff: TypeCharacterHandle.Adapter = table.clone(Generic)
Jeff.Name = "Jeff"

return Jeff
