local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeFriends = require(ServerScriptService.ModNPCServer.Types.v1.TypeFriends)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local Outcomes = TypeFriends.Outcomes

local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

local Friends = {}
Friends.__index = Friends

-- The characters on our side, and the ones we've connected with. The API treats every character as a possible target, and
-- the search task only announces the ones we'd fight, so this keeps the rest: after each search it reads who shares our
-- team and announces the differences. That ties it to the search's pace and its CanSearchTargets permission, and means a
-- character without the SearchForTargets task has no teammates.
--
-- A teammate is someone on our team within our provoke range, so it comes and goes as characters move. A friend is someone
-- we connected with, which takes a teammate and happens once: whoever spots the other first asks (RequestFriend) and the
-- other answers (ReceiveFriendRequest). A friend out of range is remembered, just not usable (GetNearbyFriends). It is only
-- forgotten once it leaves the target registry or stops sharing our team.
--
-- Reached through Functions (GetTeammates, IsTeammate, GetTeammateDistance, GetFriends, GetNearbyFriends, IsFriend,
-- RequestFriend, ReceiveFriendRequest).
function Friends.new(Base: any, _: Model)
	local self = setmetatable({}, Friends)
	self.CharacterAPI = Base.CharacterAPI
	self.Distance = Base.Distance
	self.Events = Base.Events
	self.Functions = Base.Functions

	-- Keyed by character
	self.Members = {} :: { [Model]: TypeTargetting.TargettingContext }
	self.Friends = {} :: { [Model]: TypeFriends.FriendContext }

	self.Subscriptions = {
		Base.Events:Subscribe(TargettingEvents.SearchCompleted, function()
			self:_sync()
		end),
		Base.Events:Subscribe(HumanoidEvents.Died, function()
			table.clear(self.Members)
			table.clear(self.Friends)
		end),
	}

	return self
end

-- Everyone on our team, at any distance. Neutral is nobody's side: the search treats other neutrals as targets, so they
-- can't be teammates as well.
function Friends:_getSameTeam(): { TypeTargetting.TargettingContext }
	if self.CharacterAPI:GetTeam() == NEUTRAL_TEAM then
		return {}
	end
	return self.CharacterAPI:GetSameTeamTargets()
end

function Friends:_withinProvokeRange(contexts: { TypeTargetting.TargettingContext }): { TypeTargetting.TargettingContext }
	local provokeRange = self.Distance:GetProvokeRange()
	if not provokeRange then
		return contexts
	end

	local inRange = {}
	for _, context in contexts do
		if self.Distance:IsWithin(context.Character, provokeRange) then
			table.insert(inRange, context)
		end
	end
	return inRange
end

function Friends:_forgetInvalidFriends(sameTeam: { TypeTargetting.TargettingContext })
	local valid: { [Model]: boolean } = {}
	for _, context in sameTeam do
		valid[context.Character] = true
	end

	for character, friend in self.Friends do
		if not valid[character] then
			self.Friends[character] = nil
			self.Events:Dispatch(TargettingEvents.FriendLost, friend)
		end
	end
end

-- Sync what we know with the API's, firing spotted/lost for the differences. A new teammate we haven't connected with
-- gets asked. Only as it is spotted: one that declined is on its way to no longer being a candidate, so it isn't chased.
function Friends:_sync()
	local sameTeam = self:_getSameTeam()
	self:_forgetInvalidFriends(sameTeam)

	local found: { [Model]: TypeTargetting.TargettingContext } = {}
	for _, context in self:_withinProvokeRange(sameTeam) do
		found[context.Character] = context
	end

	for character, context in found do
		if not self.Members[character] then
			self.Members[character] = context
			self.Events:Dispatch(TargettingEvents.TeammateSpotted, context)
			if not self.Friends[character] then
				self.Functions:CallFunction(FunctionEnum.RequestFriend, character)
			end
		end
	end

	for character, context in self.Members do
		if not found[character] then
			self.Members[character] = nil
			self.Events:Dispatch(TargettingEvents.TeammateLost, context)
		end
	end
end

function Friends:_isLiving(character: Model?): boolean
	local health = self.CharacterAPI:GetHealth(character)
	return health ~= nil and health > 0
end

function Friends:_addFriend(character: Model, team: string, initiated: boolean)
	if self.Friends[character] then
		return
	end

	local friend: TypeFriends.FriendContext = {
		Character = character,
		Team = team,
		Initiated = initiated,
	}
	self.Friends[character] = friend
	self.Events:Dispatch(TargettingEvents.FriendAdded, friend)
end

function Friends:GetTeammates(): { TypeTargetting.TargettingContext }
	local teammates = {}
	for _, context in self.Members do
		table.insert(teammates, context)
	end
	return teammates
end

function Friends:IsTeammate(character: Model): boolean
	return self.Members[character] ~= nil
end

-- Studs to a teammate, measured now. Nil if the character isn't one of ours or the distance can't be measured.
function Friends:GetTeammateDistance(character: Model): number?
	if not self.Members[character] then
		return nil
	end
	return self.Distance:GetDistanceTo(character)
end

function Friends:GetFriends(): { TypeFriends.FriendContext }
	local friends = {}
	for _, friend in self.Friends do
		table.insert(friends, friend)
	end
	return friends
end

-- The friends within our provoke range: the ones we can talk to or go to
function Friends:GetNearbyFriends(): { TypeFriends.FriendContext }
	local friends = {}
	for character, friend in self.Friends do
		if self.Members[character] then
			table.insert(friends, friend)
		end
	end
	return friends
end

function Friends:IsFriend(character: Model): boolean
	return self.Friends[character] ~= nil
end

-- Asks the character to connect, and takes it on as a friend if it accepts
function Friends:RequestFriend(character: Model): TypeFriends.FriendOutcome
	local outcome = self.CharacterAPI:RequestFriend(character)
	if outcome == Outcomes.Accepted and self:_isLiving() then
		self:_addFriend(character, self.CharacterAPI:GetTeam() :: string, true)
	end
	return outcome
end

-- Another character asked us to connect (the API calls it). Accepted regardless of whether we've spotted them: being asked
-- is enough. We only decline if something changed in the moment the request took to get here. Sender first: a dead
-- character's team reads as Neutral, which would pass for a team change.
function Friends:ReceiveFriendRequest(request: TypeFriends.FriendRequest): TypeFriends.FriendOutcome
	if not self:_isLiving() then
		return Outcomes.ReceiverDead
	end
	if not self:_isLiving(request.Sender) then
		return Outcomes.SenderDead
	end

	local team = self.CharacterAPI:GetTeam()
	if team == NEUTRAL_TEAM or team ~= request.Team then
		return Outcomes.TeamMismatch
	end

	self:_addFriend(request.Sender, request.Team, false)
	return Outcomes.Accepted
end

return Friends
