local ServerScriptService = game:GetService("ServerScriptService")
local Humanoid = {}
Humanoid.__index = Humanoid

local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local AirStateEnum = TypeState.AirStateEnum
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local AnimationEvents = TypeCharacterEvents.Names.Animation

local MOVEMENT_THRESHOLD = 0.1
local AIR_STATE_KEY = TypeState.Keys.AirState

local HEALTH_BAR_NAME = "Health"
local HEALTH_BAR_FILL_COLOR = Color3.fromRGB(85, 255, 0)
local HEALTH_BAR_CHANGE_COLOR = Color3.fromRGB(255, 90, 30)

function Humanoid.new(Base: {}, character: Model)
	local self = setmetatable({}, Humanoid)
	self.Base = Base
	self.Character = character
	self.Humanoid = self.Base.Humanoid
	self.healthBar = nil :: TypeBars.Bar?
	self.CharacterAPI = self.Base.CharacterAPI
	self.Assets = self.Base.Assets
	self.wasRunning = false
	self.died = false
	self.connections = {}
	self.Base.State:Register(AIR_STATE_KEY, AirStateEnum, AirStateEnum.Grounded)
	self.EventSubscriptions = {
		self.Base.Events:Subscribe(HumanoidEvents.StateChanged, function(payload)
			self:_processStateChange(payload.OldState, payload.NewState)
		end),
		self.Base.Events:Subscribe(HumanoidEvents.Died, function()
			self:_died()
		end),
		self.Base.Events:Subscribe(HumanoidEvents.HealthChanged, function(payload)
			self:_updateHealthBar(payload.Health, payload.MaxHealth)
		end),
		-- TODO: move to damage module
		self.Base.Events:Subscribe(AnimationEvents.DeathFinished, function()
			self:_breakApart()
		end, true),
	}

	self:_buildEventDispatchers()
	self:_createHealthBar()

	return self
end

-- No secondary fill for now. The bar clears itself with the character, so there is no cleanup for it
function Humanoid:_createHealthBar()
	local humanoid = self.Humanoid :: Humanoid
	self.healthBar = self.CharacterAPI:CreateBar(HEALTH_BAR_NAME, {
		Fill = self:_getHealthFraction(humanoid.Health, humanoid.MaxHealth),
		FillColor = HEALTH_BAR_FILL_COLOR,
		ChangeFillColor = HEALTH_BAR_CHANGE_COLOR,
		LayoutOrder = 0,
	})
end

function Humanoid:_getHealthFraction(health: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end
	return math.clamp(health / maxHealth, 0, 1)
end

function Humanoid:_updateHealthBar(health: number, maxHealth: number)
	local bar = self.healthBar
	if bar then
		bar:SetFill(self:_getHealthFraction(health, maxHealth))
	end
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

		Humanoid.HealthChanged:Connect(function(health: number)
			self.Base.Events:Dispatch(HumanoidEvents.HealthChanged, { Health = health, MaxHealth = Humanoid.MaxHealth })
		end),

		-- the percentage depends on max health too, so a change there has to refresh the bar
		Humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			self.Base.Events:Dispatch(HumanoidEvents.HealthChanged, { Health = Humanoid.Health, MaxHealth = Humanoid.MaxHealth })
		end),
	}
end

-- the event upstairs will eventually find its place here
function Humanoid:_processStateChange(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
	if newState == Enum.HumanoidStateType.Freefall then
		self.Base.State:Set(AIR_STATE_KEY, AirStateEnum.Falling)
	end

	-- Stopped falling (landed, sensitive/assuming the last state was airtime at all)
	if oldState == Enum.HumanoidStateType.Freefall then
		self.Base.State:Set(AIR_STATE_KEY, AirStateEnum.Grounded)
		self.Base.Events:Dispatch(HumanoidEvents.Landed, {})
	end
end

return Humanoid
