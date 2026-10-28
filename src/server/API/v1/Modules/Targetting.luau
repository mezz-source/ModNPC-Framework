local ServerScriptService = game:GetService("ServerScriptService")
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local Targetting = {}

-- how long to wait for a newly added humanoid's character to pass validation
local VALIDATION_TIMEOUT = 5
local VALIDATION_INTERVAL = 0.1

local targets: { [Model]: TypeTargetting.TargettingContext } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}
local pending: { [Model]: boolean } = {}

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

local function invalidateTarget(character: Model)
	local characterConnections = connections[character]
	if characterConnections then
		for _, connection in characterConnections do
			connection:Disconnect()
		end
	end

	connections[character] = nil
	targets[character] = nil
end

local function registerTarget(character: Model, humanoid: Humanoid)
	-- We allow unloaded targets so that instanced ModNPCs don't get incorrectly marked as generics
	-- due to the unload flag deeper in type checks
	local allowUnloadedTargets = true
	local characterType = CharacterUtility.getCharacterType(character, allowUnloadedTargets).Data
	if not characterType then
		return
	end

	targets[character] = {
		Character = character,
		Type = characterType,
		Team = CharacterUtility.getTeam(character).Data,
	}

	connections[character] = {
		character.Destroying:Once(function()
			invalidateTarget(character)
		end),
		humanoid.Died:Once(function()
			invalidateTarget(character)
		end),
	}
end

local function considerHumanoid(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") or targets[character] or pending[character] then
		return
	end
	pending[character] = true

	task.spawn(function()
		local deadline = os.clock() + VALIDATION_TIMEOUT
		while humanoid.Parent == character and character:IsDescendantOf(workspace) do
			if CharacterUtility.isValidCharacter(character).Data then
				registerTarget(character, humanoid)
				break
			end

			if humanoid.Health <= 0 or os.clock() >= deadline then
				break
			end

			task.wait(VALIDATION_INTERVAL)
		end

		pending[character] = nil
	end)
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

function Targetting.init(_)
	task.defer(function()
		if not CharacterUtility._validationReady() then
			print("Awaiting character utility validation readiness before initalizing")
			repeat task.wait() until CharacterUtility._validationReady()
		end

		workspace.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Humanoid") then
				considerHumanoid(descendant)
			end
		end)

		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("Humanoid") then
				considerHumanoid(descendant)
			end
		end
	end)
end

return Targetting
