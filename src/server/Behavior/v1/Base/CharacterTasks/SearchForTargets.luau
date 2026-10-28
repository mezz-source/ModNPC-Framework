local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)

local TargettingEvents = TypeCharacterEvents.Names.Targetting

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral

local SearchTask = {}
SearchTask.__index = SearchTask
setmetatable(SearchTask, Task)

function SearchTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Targetting,
		Resources = { ResourceEnum.Targetting },
		Dependencies = { Dependencies.Configuration, Dependencies.Events, Dependencies.TargetSelector },
		Policy = TypeTask.Policy.Replace,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, SearchTask)
	self.CharacterAPI = base.CharacterAPI
	self.Configuration = base.Configuration
	self.Events = base.Events
	self.TargetSelector = base.TargetSelector

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
-- NewFocusTarget: none -> target. LostFocusTarget: target -> none.
-- FocusedTargetChanged: target -> a different target, as { Previous, Current }.
function SearchTask:UpdateFocusTarget()
	local best: TypeTargetting.TargettingContext? = nil
	if self.TargetSelector:IsValidPreference(self.targettingPreference) then
		best = self.TargetSelector:SelectBest(self:GetTargets(), self.targettingPreference)
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
		self.Events:Dispatch(TargettingEvents.NewFocusTarget, best)
	elseif previous then
		self.Events:Dispatch(TargettingEvents.LostFocusTarget, previous)
	end
end

-- Targets we are allowed to consider: everyone if neutral, otherwise only non-matching teams
function SearchTask:GetViableTargets(): { TypeTargetting.TargettingContext }
	local team = self.CharacterAPI:GetTeam()
	if team and team ~= NEUTRAL_TEAM then
		return self.CharacterAPI:GetOpposingTargets()
	end

	local viable = {}
	for _, context in self.CharacterAPI:GetAllTargets() do
		if context.Character ~= self.CharacterAPI.Character then
			table.insert(viable, context)
		end
	end
	return viable
end

-- Sync our known targets with the latest search, firing spotted/lost for the differences
function SearchTask:UpdateTargets()
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

	if self.curInterval >= self.searchInterval then
		self.curInterval = 0
		self:UpdateTargets()
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
