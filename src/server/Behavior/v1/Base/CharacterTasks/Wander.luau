local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypePermissions = require(ServerScriptService.ModNPCServer.Types.v1.TypePermissions)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Permissions = TypePermissions.Names
local TargettingEvents = TypeCharacterEvents.Names.Targetting
local WanderEvents = TypeCharacterEvents.Names.Wander
local INVESTIGATE_STATE_KEY = TypeState.Keys.InvestigateState
local InvestigateStateEnum = TypeState.InvestigateStateEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies

-- A wander destination is a random x and z within this many studs of where the character stands (the height is kept), and
-- never closer than the minimum, so a wander is always worth walking
local WANDER_RADIUS = 30
local WANDER_MIN_DISTANCE = 8
-- How long (seconds) the character stands around between wanders
local REST_MIN = 1
local REST_MAX = 4

-- Aimless walking for a character with nothing to do: while it knows of no target it picks a spot nearby, walks (never
-- sprints) to it with a WalkTo task, rests a moment and picks another. The moment a target shows up the walk we started is
-- ended, and we stay put until every target has been lost.
-- Essential and in its own category, so a dodge (which ends the Movement tasks) or a stagger doesn't end wandering for good;
-- a walk that gets cut short just makes the next one come after a rest.
local WanderTask = {}
WanderTask.__index = WanderTask
setmetatable(WanderTask, Task)

function WanderTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Wander,
		Resources = {},
		Dependencies = {
			Dependencies.CharacterTasks,
			Dependencies.Configuration,
			Dependencies.Events,
			Dependencies.Functions,
			Dependencies.Scheduler,
			Dependencies.State,
		},
		Policy = TypeTask.Policy.Parallel,
		Essential = true,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, WanderTask)
	self.Character = base.Character
	self.CharacterTasks = base.CharacterTasks
	self.Configuration = base.Configuration
	self.Events = base.Events
	self.Functions = base.Functions
	self.Scheduler = base.Scheduler
	self.State = base.State

	-- The targets we know of, by character, and whether one is being focused. Wandering waits for both to be empty.
	self.knownTargets = {} :: { [Model]: boolean }
	self.hasFocus = false
	-- The walk we started and are waiting on. It clears this on itself when it ends, however it ends.
	self.walk = nil :: TypeTask.Task?
	-- Seconds left to stand around before the next wander
	self.restLeft = 0

	return self
end

function WanderTask:HasActiveTarget(): boolean
	return self.hasFocus or next(self.knownTargets) ~= nil
end

function WanderTask:_rest()
	self.restLeft = REST_MIN + math.random() * (REST_MAX - REST_MIN)
end

-- Ends the walk we started, if it's still going
function WanderTask:StopWalk(reason: string)
	local walk = self.walk
	self.walk = nil
	if walk then
		walk:Stop(reason)
	end
end

-- A random x and z around the character, at the character's own height
function WanderTask:PickPosition(): Vector3?
	local rootPart = self.Character.PrimaryPart
	if not rootPart then
		return nil
	end

	local offset = Vector3.new(
		(math.random() * 2 - 1) * WANDER_RADIUS,
		0,
		(math.random() * 2 - 1) * WANDER_RADIUS
	)
	if offset.Magnitude < WANDER_MIN_DISTANCE then
		-- push it out to the minimum; a dead center roll has no direction, so any one will do
		local direction = if offset.Magnitude > 0 then offset.Unit else Vector3.xAxis
		offset = direction * WANDER_MIN_DISTANCE
	end

	return rootPart.Position + offset
end

function WanderTask:StartWalk()
	-- Permissions/CanWander off: no new walks. Rest instead, so the permission is asked again after a moment, not every frame.
	if not self.Configuration:IsPermitted(Permissions.CanWander) then
		self:_rest()
		return
	end

	local position = self:PickPosition()
	if not position then
		self:_rest()
		return
	end

	-- Wandering is a stroll. Asking is free when we already walk.
	self.Functions:CallFunction(FunctionEnum.StopSprinting)

	local walk, createError = self.CharacterTasks.WalkTo.new(position)
	if not walk then
		warn("Wander could not create walk:", createError)
		self:_rest()
		return
	end

	local started, startError = self.Scheduler:Start(walk)
	if not started then
		warn("Wander could not start walk:", startError)
		self:_rest()
		return
	end

	self.walk = walk
	walk.Terminated:Connect(function()
		if self.walk == walk then
			self.walk = nil
			self:_rest()
		end
	end)

	self.Events:Dispatch(WanderEvents.NewPosition, { Position = position } :: TypeCharacterEvents.NewWanderPosition)
end

-- A target in sight ends whatever wandering is under way
function WanderTask:_onTargetFound()
	self:StopWalk("Target found")
	self:_rest()
end

function WanderTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	local subscriptions = {
		self.Events:Subscribe(TargettingEvents.TargetSpotted, function(context: TypeTargetting.TargettingContext)
			self.knownTargets[context.Character] = true
			self:_onTargetFound()
		end),
		self.Events:Subscribe(TargettingEvents.NewFocusTarget, function()
			self.hasFocus = true
			self:_onTargetFound()
		end),
		self.Events:Subscribe(TargettingEvents.FocusedTargetChanged, function()
			self.hasFocus = true
		end),
		self.Events:Subscribe(TargettingEvents.LostFocusTarget, function()
			self.hasFocus = false
		end),
		self.Events:Subscribe(TargettingEvents.TargetLost, function(context: TypeTargetting.TargettingContext)
			self.knownTargets[context.Character] = nil
		end),
		-- Every target gone is when wandering may begin again, after a moment of standing there
		self.Events:Subscribe(TargettingEvents.AllTargetsLost, function()
			table.clear(self.knownTargets)
			self.hasFocus = false
			self:_rest()
		end),
	}

	self.Terminated:Connect(function()
		for _, subscription in subscriptions do
			subscription:Unsubscribe()
		end

		self:StopWalk("Wander ended")
		table.clear(self.knownTargets)
	end)

	-- We may have started after targets were already found, so catch up instead of waiting for an event
	self:SyncTargets()
	self:_rest()

	return true
end

-- The events are how we normally hear about targets. This reads what the targetting task knows straight from it, so a
-- target found before we started can't leave us wandering around it.
function WanderTask:SyncTargets()
	for _, targettingTask in self.Scheduler:GetTasks(CategoryEnum.Targetting) :: { any } do
		if type(targettingTask.Targets) == "table" then
			for character in targettingTask.Targets do
				self.knownTargets[character] = true
			end
		end
		if targettingTask.FocusTarget then
			self.hasFocus = true
		end
	end
end

function WanderTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	-- Nothing to do while there is someone to deal with, and while a walk of ours is going (it tells us when it ends)
	if self:HasActiveTarget() or self.walk then
		return
	end

	-- An Investigate task owns where we go until it ends (the walk we had going was ended when it started). Rest is
	-- held, not run down, so the first wander after it comes a moment later rather than straight away.
	if self.State:Is(INVESTIGATE_STATE_KEY, InvestigateStateEnum.Investigating) then
		return
	end

	self.restLeft -= deltaTime
	if self.restLeft > 0 then
		return
	end

	self:StartWalk()
end

return WanderTask
