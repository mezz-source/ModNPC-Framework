local ThoughtProcess = {}
ThoughtProcess.__index = ThoughtProcess

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local ThoughtEvents = TypeCharacterEvents.Names.Thought

function ThoughtProcess.new(Base, Character)
	local self = setmetatable({}, ThoughtProcess)
	self.Base = Base
	self.Character = Character
	self.updateConnection = nil
	self.Subscriptions = {
		self.Base.Events:Subscribe(HumanoidEvents.Died, function()
			self:_died()
		end),
	}

	self.baseReactionSpeed = self.Base.Configuration:GetThoughtSetting("ReactionSpeed") -- 0.3s~
	self.currentReactionSpeed = self.baseReactionSpeed

	self.reactionDeviation = self.Base.Configuration:GetThoughtSetting("ReactionDeviation") -- 0.3 range
	self.elapsedThoughtDt = 0

	table.insert(self.Subscriptions, self.Base.Configuration:Observe({ "ThoughtProcess", "ReactionSpeed" }, function(value)
		self.baseReactionSpeed = value
	end))
	table.insert(self.Subscriptions, self.Base.Configuration:Observe({ "ThoughtProcess", "ReactionDeviation" }, function(value)
		self.reactionDeviation = value
	end))

	return self
end

function ThoughtProcess:Update(deltaTime: number)
	if not self.Base:IsAlive() then
		return
	end

	self.elapsedThoughtDt += deltaTime

	if self.elapsedThoughtDt < self.currentReactionSpeed then
		return
	end

	-- Hand listeners the time since the last reaction tick, not the frame time.
	-- State is reset first so a listener that errors or re-enters can't wedge the timer.
	local elapsed = self.elapsedThoughtDt
	self.elapsedThoughtDt = 0
	self.currentReactionSpeed = self.baseReactionSpeed + math.random() * self.reactionDeviation

	self.Base.Events:Dispatch(ThoughtEvents.ReactionUpdate, elapsed)
end

function ThoughtProcess:_died()
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end
end

function ThoughtProcess:Init()
	self.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:Update(deltaTime)
	end)
end

return ThoughtProcess
