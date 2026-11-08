local ServerScriptService = game:GetService("ServerScriptService")
local CharacterDiscovery = require(script.Parent.CharacterDiscovery)
local CharacterHandles = require(script.Parent.CharacterHandles)
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local Claims = require(ServerScriptService.ModNPCServer.Util.Claims)
local Targetting = {}

-- Every character CharacterDiscovery tracks, as a target
local targets: { [Model]: TypeTargetting.TargettingContext } = {}

-- Target claims are short lived: always on a timeout, the given one capped
local DEFAULT_CLAIM_DURATION = 5
local MAX_CLAIM_DURATION = 30

type TargetClaims = Claims.SingleClaims<Model, Model>

-- One claim system per team, made on first use, so each team has its own first responder. Keyed by target, held by the
-- claimer.
local teamClaims: { [string]: TargetClaims } = {}

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
		Team = CharacterHandles._getTeam(character),
	}
end

local function invalidateTarget(character: Model)
	targets[character] = nil

	-- Gone as a target, its claims are over; gone as a claimer, it can't follow up on what it claimed
	for _, claims in teamClaims do
		claims.clear(character)
		claims.releaseHolder(character)
	end
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function validateClaimPair(character: any, target: any): TypeModuleResponse.ModuleResponse?
	if not isModel(character) then
		return response(false, true, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end
	if not isModel(target) or target == character then
		return response(false, true, TypeRequests.Enums.StatusCode.MalformedRequest, "Target must be another Model")
	end
	return nil
end

-- A holder that has changed team since claiming no longer speaks for this one, so its claim is dropped. Released through
-- its own token, so if reading the team ever yields, a newer claim made meanwhile is left alone.
local function dropStaleHolder(claims: TargetClaims, team: string, target: Model)
	local claim = claims.get(target)
	local holder = claims.getHolder(target)
	if claim and holder and CharacterHandles._getTeam(holder) ~= team then
		claims.release(target, claim)
	end
end

local function collect(predicate: (TypeTargetting.TargettingContext) -> boolean): { TypeTargetting.TargettingContext }
	local result = {}
	for character, context in targets do
		-- teams change, so what a context says is only as old as this read
		context.Team = CharacterHandles._getTeam(character)
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

-- Claims the target for the claimer's team, for the given seconds (default 5, at most 30). Data is a TargetClaimAttempt:
-- whether this call took it and, either way, who holds it now. Taking and reading happen in the one call, so two
-- teammates spotting a target at once can't both come away first.
function Targetting.claimTarget(claimer: Model, target: Model, duration: number?): TypeModuleResponse.ModuleResponse
	local problem = validateClaimPair(claimer, target)
	if problem then
		return problem
	end
	if duration ~= nil and (type(duration) ~= "number" or duration ~= duration or duration <= 0) then
		return response(false, true, TypeRequests.Enums.StatusCode.MalformedRequest, "Duration must be a positive number")
	end

	local team = CharacterHandles._getTeam(claimer)
	local claims = teamClaims[team]
	if not claims then
		claims = Claims.newSingle() :: TargetClaims
		teamClaims[team] = claims
	end

	dropStaleHolder(claims, team, target)

	-- Nothing yields from the claim to the read, so the holder read is the one that beat this call
	local claimed = claims.claim(target, claimer, math.min(duration or DEFAULT_CLAIM_DURATION, MAX_CLAIM_DURATION)) ~= nil
	local attempt: TypeTargetting.TargetClaimAttempt = {
		Claimed = claimed,
		Holder = claims.getHolder(target),
	}

	local message = if claimed then "Target claimed" else "Target already claimed"
	return response(true, true, TypeRequests.Enums.StatusCode.Success, message, attempt)
end

-- Who on the asker's team holds the target. Data is a TargetClaim.
function Targetting.getTargetClaim(asker: Model, target: Model): TypeModuleResponse.ModuleResponse
	local problem = validateClaimPair(asker, target)
	if problem then
		return problem
	end

	local team = CharacterHandles._getTeam(asker)
	local claims = teamClaims[team]
	if claims then
		dropStaleHolder(claims, team, target)
	end

	local claim: TypeTargetting.TargetClaim = {
		Holder = if claims then claims.getHolder(target) else nil,
	}
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Target claim retrieved", claim)
end

-- Ends the claimer's claim on the target early. Only the holder can. Data is whether a claim was released.
function Targetting.releaseTargetClaim(claimer: Model, target: Model): TypeModuleResponse.ModuleResponse
	local problem = validateClaimPair(claimer, target)
	if problem then
		return problem
	end

	-- Every team, since the claimer may have changed team since it claimed
	local released = false
	for _, claims in teamClaims do
		local claim = claims.get(target)
		if claim and claims.getHolder(target) == claimer then
			released = claims.release(target, claim) or released
		end
	end

	local message = if released then "Target claim released" else "Claimer did not hold the target"
	return response(true, true, TypeRequests.Enums.StatusCode.Success, message, released)
end

function Targetting.init(_)
	CharacterDiscovery._observe(registerTarget, invalidateTarget)
end

return Targetting
