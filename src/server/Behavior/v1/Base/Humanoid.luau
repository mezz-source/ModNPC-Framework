local ServerScriptService = game:GetService("ServerScriptService")
local Humanoid = {}
Humanoid.__index = Humanoid

local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local AnimationEvents = TypeCharacterEvents.Names.Animation

local MOVEMENT_THRESHOLD = 0.1

function Humanoid.new(Base: {}, character: Model)
	local self = setmetatable({}, Humanoid)
	self.Base = Base
	self.Character = character
	self.Humanoid = self.Base.Humanoid
	self.CharacterAPI = self.Base.CharacterAPI
	self.AnimationHandler = self.Base.AnimationHandler
	self.DialogueHandler = self.Base.DialogueHandler
	self.Assets = self.Base.Assets
	self.wasRunning = false
	self.died = false
	self.connections = {}
	self.EventSubscriptions = {
		self.Base.Events:Subscribe(HumanoidEvents.StateChanged, function(payload)
			self:_processStateChange(payload.OldState, payload.NewState)
		end),
		self.Base.Events:Subscribe(HumanoidEvents.Died, function()
			self:_died()
		end),
		-- TODO: move to damage module
		self.Base.Events:Subscribe(AnimationEvents.DeathFinished, function()
			self:_breakApart()
		end, true),
	}

	self:_buildEventDispatchers()

	return self
end

function Humanoid:IsGrounded()
	return self.Humanoid.FloorMaterial ~= Enum.Material.Air
end

function Humanoid:_cleanConnections()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

function Humanoid:_breakApart()
	for _, instance in ipairs(self.Character:GetDescendants()) do
		if instance:IsA("Motor6D") or instance:IsA("Weld") or instance:IsA("Attachment") then
			instance:Destroy()
		end
	end
end

function Humanoid:_handleRunningConnection(speed: number)
	if speed > MOVEMENT_THRESHOLD then
		self.Base.Events:Dispatch(HumanoidEvents.Running, speed)
		if not self.wasRunning then
			self.wasRunning = true
			self.Base.Events:Dispatch(HumanoidEvents.MoveBegan, speed)
		end
	elseif speed <= MOVEMENT_THRESHOLD then
		if self.wasRunning then
			self.wasRunning = false
			self.Base.Events:Dispatch(HumanoidEvents.MoveEnded)
		end
	end
end

function Humanoid:_died()
	if self.died then
		return
	end
	self.died = true -- sometimes roblox can fire this a few times

	self:_cleanConnections()
end

function Humanoid:Destroy()
	self:_cleanConnections()

	for _, subscription in ipairs(self.EventSubscriptions) do
		subscription.Unsubscribe()
	end
	self.EventSubscriptions = {}
end

function Humanoid:_buildEventDispatchers()
	local Humanoid = self.Humanoid :: Humanoid
	self:_cleanConnections()

	-- these are the ez pz one off events
	self.connections = {
		-- this is a little more complex so we're extracting it
		Humanoid.Running:Connect(function(speed: number)
			self:_handleRunningConnection(speed)
		end),

		Humanoid.Jumping:Connect(function()
			self.Base.Events:Dispatch(HumanoidEvents.Jumped)
		end),

		Humanoid.StateChanged:Connect(function(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
			self.Base.Events:Dispatch(HumanoidEvents.StateChanged, { OldState = oldState, NewState = newState })
		end),

		Humanoid.Died:Connect(function()
			self.Base.Events:Dispatch(HumanoidEvents.Died)
		end),
	}
end

-- the event upstairs will eventually find its place here
function Humanoid:_processStateChange(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
	-- Stopped falling (landed, sensitive/assuming the last state was airtime at all)
	if oldState == Enum.HumanoidStateType.Freefall then
		self.Base.Events:Dispatch(HumanoidEvents.Landed, {})
	end
end

return Humanoid
