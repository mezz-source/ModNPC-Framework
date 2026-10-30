local ServerScriptService = game:GetService("ServerScriptService")
local CharacterDiscovery = require(script.Parent.CharacterDiscovery)
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local Targetting = {}

-- Every character CharacterDiscovery tracks, as a target
local targets: { [Model]: TypeTargetting.TargettingContext } = {}

local function response(
	success: boolean,
	passResponse: boolean,
	statusCode: number?,
	message: string?,
	data: any?
): TypeModuleResponse.ModuleResponse
	return {
		Success = success,
		PassResponse = passResponse,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

local function registerTarget(character: Model, characterType: string)
	targets[character] = {
		Character = character,
		Type = characterType,
		Team = CharacterUtility.getTeam(character).Data,
	}
end

local function invalidateTarget(character: Model)
	targets[character] = nil
end

local function collect(predicate: (TypeTargetting.TargettingContext) -> boolean): { TypeTargetting.TargettingContext }
	local result = {}
	for _, context in targets do
		if predicate(context) then
			table.insert(result, context)
		end
	end
	return result
end

function Targetting.getTargets(): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Targets retrieved successfully",
		collect(function()
			return true
		end)
	)
end

function Targetting.getTargetsOfType(characterType: string): TypeModuleResponse.ModuleResponse
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Targets retrieved successfully",
		collect(function(context)
			return context.Type == characterType
		end)
	)
end

-- Include: only targets on one of the given teams. Exclude: every target not on one of the given teams.
function Targetting.getTargetsWithTeamFilter(
	filterType: TypeTargetting.FilterType,
	teams: { string }
): TypeModuleResponse.ModuleResponse
	if filterType ~= TypeTargetting.FilterTypes.Include and filterType ~= TypeTargetting.FilterTypes.Exclude then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Invalid team filter type")
	end

	if type(teams) ~= "table" then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Teams must be a list of team names")
	end

	local teamSet = {}
	for _, team in teams do
		teamSet[team] = true
	end

	local include = filterType == TypeTargetting.FilterTypes.Include
	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Targets retrieved successfully",
		collect(function(context)
			return (teamSet[context.Team] == true) == include
		end)
	)
end

-- Distance in studs between the root parts of two characters
function Targetting.getDistance(from: Model, to: Model): TypeModuleResponse.ModuleResponse
	local fromRoot = CharacterUtility._getRootPart(from)
	local toRoot = CharacterUtility._getRootPart(to)
	if not fromRoot or not toRoot then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character does not have a root part")
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Distance retrieved successfully",
		(fromRoot.Position - toRoot.Position).Magnitude
	)
end

-- Distance in studs from the root part of a character to a point in the world
function Targetting.getDistanceToPosition(from: Model, position: Vector3): TypeModuleResponse.ModuleResponse
	if typeof(position) ~= "Vector3" then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Position must be a Vector3")
	end

	local fromRoot = CharacterUtility._getRootPart(from)
	if not fromRoot then
		return response(false, true, TypeRequests.Enums.StatusCode.Conflict, "Character does not have a root part")
	end

	return response(
		true,
		true,
		TypeRequests.Enums.StatusCode.Success,
		"Distance retrieved successfully",
		(fromRoot.Position - position).Magnitude
	)
end

function Targetting.init(_)
	CharacterDiscovery._observe(registerTarget, invalidateTarget)
end

return Targetting
