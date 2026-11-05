local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)

type Entry = TypeCharacterHandle.Entry
type Question = TypeCharacterHandle.Question

local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

-- Anything with a humanoid that nothing else claimed: a player, a plain rig. It has no team and no engine to ask. What it
-- does have, health and a position, the handle reads by itself.
local Generic: TypeCharacterHandle.Adapter = {
	Name = "Generic",

	-- The fallback, it is never looked for
	Detect = function(_character: Model): boolean
		return false
	end,

	GetTeam = function(_entry: Entry): string
		return NEUTRAL_TEAM
	end,

	Ask = function(_entry: Entry, _question: Question): boolean
		return false
	end,
}

return Generic
