local ServerScriptService = game:GetService("ServerScriptService")
local CharacterDiscovery = require(script.Parent.CharacterDiscovery)
local CharacterHandles = require(script.Parent.CharacterHandles)
local CharacterUtility = require(script.Parent.CharacterUtility)
local TypeFriends = require(ServerScriptService.ModNPCServer.Types.v1.TypeFriends)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local Claims = require(ServerScriptService.ModNPCServer.Util.Claims)

local Friends = {}

local Outcomes = TypeFriends.Outcomes
-- The target's function that answers a request (TypeCharacterFunctions.FunctionEnum.ReceiveFriendRequest)
local RECEIVE_FUNCTION = "ReceiveFriendRequest"

-- The pairs mid request. This is the one place both sides share, so it decides who got there first. The request itself
-- can yield (a mod hook on the target), which is why the claim is held across it.
local claims = Claims.newPair() :: Claims.PairClaims<Model>

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

-- Claims the pair and carries the sender's request to the target's ReceiveFriendRequest function. Data is a FriendOutcome,
-- and only Accepted means the target took the sender on: anything that goes wrong along the way is an outcome, not an
-- error. Only a malformed request fails.
function Friends.requestFriend(sender: Model, target: Model): TypeModuleResponse.ModuleResponse
	if typeof(sender) ~= "Instance" or not sender:IsA("Model") then
		return response(false, true, TypeRequests.Enums.StatusCode.MalformedRequest, "Sender must be a Model")
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target == sender then
		return response(false, true, TypeRequests.Enums.StatusCode.MalformedRequest, "Target must be another Model")
	end

	local request: TypeFriends.FriendRequest = {
		Sender = sender,
		Team = CharacterHandles._getTeam(sender),
	}

	local claim = claims.claim(sender, target)
	if not claim then
		return response(true, true, TypeRequests.Enums.StatusCode.Success, "Pair is already mid request", Outcomes.Busy)
	end

	local answer = CharacterUtility.sendFunction(target, RECEIVE_FUNCTION, { request })
	claims.release(sender, target, claim)

	local outcome = if answer.Success and Outcomes[answer.Data] then answer.Data else Outcomes.Failed
	return response(true, true, TypeRequests.Enums.StatusCode.Success, "Friend request answered", outcome)
end

function Friends.init(_)
	-- A character that is gone can't finish what it started, so its pairs open up
	CharacterDiscovery._observe(function() end, claims.releaseAll)
end

return Friends
