local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterHandle = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterHandle)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)
local CharacterUtility = require(script.Parent.Parent.Parent.CharacterUtility)

type Entry = TypeCharacterHandle.Entry
type Question = TypeCharacterHandle.Question

local CoreNames = CharacterUtility.CoreFolderNames
local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral
local TEAM_FOLDER_NAME = "Team"
local TEAM_NAME_SETTING = "TeamName"

-- The character's team setting, nil if its Config doesn't have one
local function findTeamValue(character: Model): StringValue?
	local root = character:FindFirstChild(CoreNames.Root)
	local configuration = root and root:FindFirstChild(CoreNames.Configuration)
	local teamFolder = configuration and configuration:FindFirstChild(TEAM_FOLDER_NAME)
	local teamValue = teamFolder and teamFolder:FindFirstChild(TEAM_NAME_SETTING)
	return if teamValue and teamValue:IsA("StringValue") then teamValue else nil
end

local ModNPC: TypeCharacterHandle.Adapter = {
	Name = "ModNPC",

	-- Discovery has already validated a ModNPC, nothing is left to detect
	Detect = function(_character: Model): boolean
		return false
	end,

	-- The value itself is kept and read each time, so a team changed by anything (a mod, Studio, a setting request) shows on
	-- the next read. It still answers once the character is gone: destroying the value doesn't take its Value with it.
	GetTeam = function(entry: Entry): string
		local teamValue = entry.AdapterState.TeamValue
		if not teamValue or teamValue.Parent == nil then
			teamValue = findTeamValue(entry.Character) or teamValue
			entry.AdapterState.TeamValue = teamValue
		end

		return if teamValue then teamValue.Value else NEUTRAL_TEAM
	end,

	-- Only the character's own engine knows. CharacterUtility refuses a character that was never started, which would
	-- otherwise hang on a bind nobody answers, and turns anything else that goes wrong into a plain no.
	Ask = function(entry: Entry, question: Question): boolean
		local answer = if question == "IsStaggered"
			then CharacterUtility.isStaggered(entry.Character)
			else CharacterUtility.isExhausted(entry.Character)
		return answer.Data == true
	end,
}

return ModNPC
