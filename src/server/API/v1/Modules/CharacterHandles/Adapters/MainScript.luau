local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local Generic = require(script.Parent.Generic)

-- STUB. Not integrated: this answers exactly like Generic and never claims a character.
-- To build it, we need to know:
--   Detect: what marks a model as a MainScript NPC
--   GetTeam: where a MainScript NPC keeps its team
--   Ask: whether it has anything like stagger or stamina to read
local MainScript: TypeCharacterHandle.Adapter = table.clone(Generic)
MainScript.Name = "MainScript"

return MainScript
