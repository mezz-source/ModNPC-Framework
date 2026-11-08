local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypePermissions = require(ServerScriptService.ModNPCServer.Types.v1.TypePermissions)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Permissions = TypePermissions.Names
local TargettingEvents = TypeCharacterEvents.Names.Targetting

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local SearchTask = {}
SearchTask.__index = SearchTask
setmetatable(SearchTask, Task)

function SearchTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Targetting,
		Resources = { ResourceEnum.Targetting },
		Dependencies = {
				Dependencies.Configuration,
				Dependencies.Distance,
				Dependencies.Events,
				Dependencies.Functions,
			},
		Policy = TypeTask.Policy.Parallel,
		Essential = true,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, SearchTask)
	self.CharacterAPI = base.CharacterAPI
	self.Configuration = base.Configuration
	self.Distance = base.Distance
	self.Events = base.Events
	self.Functions = base.Functions

	-- Check how often we should look for targets
	self.searchInterval = self.Configuration:GetThoughtSetting("TargettingInterval") :: number
	self.targettingPreference = self.Configuration:GetThoughtSetting("TargettingPreference") :: TypeTargetting.TargettingPreference
	-- Start full so the first update searches immediately
	self.curInterval = self.searchInterval

	-- Viable targets we currently know about, keyed by character
	self.Targets = {} :: { [Model]: TypeTargetting.TargettingContext }
	-- The target the selector currently prefers, if any
	self.FocusTarget = nil :: TypeTargetting.TargettingContext?

	return self
end

-- we do this in case this changes later
function SearchTask:UpdateTargettingInterval()
	self.searchInterval = self.Configuration:GetThoughtSetting("TargettingInterval") :: number
end

function SearchTask:UpdateTargettingPreference()
	self.targettingPreference = self.Configuration:GetThoughtSetting("TargettingPreference") :: TypeTargetting.TargettingPreference
end

-- Ask the selector for the best of our known targets. Distance and health are relative and shift
-- over time, so this is re-evaluated every search rather than only when the target list changes.
-- NewFocusTarget: none -> target, with whether a teammate already claimed it (see ClaimTarget). LostFocusTarget: target ->
-- none. FocusedTargetChanged: target -> a different target, as { Previous, Current }.
function SearchTask:UpdateFocusTarget()
	local best: TypeTargetting.TargettingContext? = nil
	if self.Functions:CallFunction(FunctionEnum.IsValidTargetPreference, self.targettingPreference) then
		best = self.Functions:CallFunction(FunctionEnum.SelectBestTarget, self:GetTargets(), self.targettingPreference)
	end
	
	local previous = self.FocusTarget
	local previousCharacter = if previous then previous.Character else nil
	local bestCharacter = if best then best.Character else nil
	if previousCharacter == bestCharacter then
		-- same target (or still nothing), keep the context fresh without announcing anything
		self.FocusTarget = best
		return
	end

	self.FocusTarget = best

	if previous and best then
		self.Events:Dispatch(TargettingEvents.FocusedTargetChanged, { Previous = previous, Current = best })
	elseif best then
		-- Claimed before it is announced, so whoever hears about it knows if a teammate saw it first
		local alreadyClaimed = self.Functions:CallFunction(FunctionEnum.ClaimTarget, best.Character) == true
		if not self:IsRunning() or self.FocusTarget ~= best then
			return
		end
		self.Events:Dispatch(TargettingEvents.NewFocusTarget, best, alreadyClaimed)
	elseif previous then
		self.Events:Dispatch(TargettingEvents.LostFocusTarget, previous)
	end
end

-- Targets we are allowed to consider: whoever we are hostile to that hasn't taken itself off the target list, and only those
-- within the provoke range. This runs every search, so a target that walks out of range drops out of our known targets (and
-- our focus) instead of being chased forever. Each one comes with its handle, for whoever hears about it next.
--
-- The list of everyone comes from the snapshot every character shares, so a crowd of searches costs one request between them.
-- The cheap handle checks go first and the range is measured once, in bulk, for whoever is left. The snapshot can be a
-- moment old, so a target that has died since is checked for here.
function SearchTask:GetViableTargets(): { TypeTargetting.TargettingContext }
	local us = self.CharacterAPI:GetHandle()
	if not us then
		return {}
	end

	local candidates = {}
	for _, context in self.CharacterAPI:GetTargetSnapshot().Targets do
		local handle = context.Handle
		if handle and handle:IsAlive() and us:IsHostile(handle) and handle:IsTargetable() then
			table.insert(candidates, context)
		end
	end

	local provokeRange = self.Distance:GetProvokeRange()
	if not provokeRange then
		return candidates
	end

	return self.Distance:FilterWithin(candidates, provokeRange)
end

-- Sync our known targets with the latest search, firing spotted/lost for the differences.
-- AllTargetsLost fires once the search leaves us with no targets after we had some.
function SearchTask:UpdateTargets()
	local hadTargets = next(self.Targets) ~= nil
	local found: { [Model]: TypeTargetting.TargettingContext } = {}
	for _, context in self:GetViableTargets() do
		found[context.Character] = context
	end

	-- Dispatch can run arbitrary listeners, so make sure we're still going after each one
	for character, context in found do
		if not self.Targets[character] then
			self.Targets[character] = context
			self.Events:Dispatch(TargettingEvents.TargetSpotted, context)
			if not self:IsRunning() then
				return
			end
		end
	end

	for character, context in self.Targets do
		if not found[character] then
			self.Targets[character] = nil
			self.Events:Dispatch(TargettingEvents.TargetLost, context)
			if not self:IsRunning() then
				return
			end
		end
	end

	self:UpdateFocusTarget()

	if hadTargets and next(self.Targets) == nil and self:IsRunning() then
		self.Events:Dispatch(TargettingEvents.AllTargetsLost)
	end
end

function SearchTask:GetTargets(): { TypeTargetting.TargettingContext }
	local targets = {}
	for _, context in self.Targets do
		table.insert(targets, context)
	end
	return targets
end

-- Driven by the thought process's reaction tick rather than the scheduler's Update,
-- so targetting can never run faster than the character can "think"
function SearchTask:OnReactionUpdate(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.curInterval += deltaTime

	if self.curInterval < self.searchInterval then
		return
	end

	-- Not allowed to search: what we know stays as it is. The interval stays full, so we search as soon as we may again.
	if not self.Configuration:IsPermitted(Permissions.CanSearchTargets) then
		return
	end

	self.curInterval = 0
	self:UpdateTargets()

	if self:IsRunning() then
		self.Events:Dispatch(TargettingEvents.SearchCompleted)
	end
end

function SearchTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	local subscription = self.Events:Subscribe(TypeCharacterEvents.Names.Thought.ReactionUpdate, function(deltaTime)
		self:OnReactionUpdate(deltaTime)
	end)

	-- pick up configuration edits while running instead of keeping the values read at construction
	local intervalSubscription = self.Configuration:Observe({ "ThoughtProcess", "TargettingInterval" }, function()
		self:UpdateTargettingInterval()
	end)
	local preferenceSubscription = self.Configuration:Observe({ "ThoughtProcess", "TargettingPreference" }, function()
		self:UpdateTargettingPreference()
	end)

	self.Terminated:Connect(function()
		subscription:Unsubscribe()
		intervalSubscription:Unsubscribe()
		preferenceSubscription:Unsubscribe()
		table.clear(self.Targets)
		self.FocusTarget = nil
	end)

	return true
end

return SearchTask
