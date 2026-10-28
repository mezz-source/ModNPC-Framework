local ServerScriptService = game:GetService("ServerScriptService")
local CharacterAPI = require(script.CharacterAPI)
local Router = require(script.Router)
local Events = require(script.Events)
local Configuration = require(script.Configuration)
local Assets = require(script.Assets)
local Dialogue = require(script.Dialogue)
local Animation = require(script.Animation)
local Humanoid = require(script.Humanoid)
local Movement = require(script.Movement)
local Functions = require(script.Functions)
local ThoughtProcess = require(script.ThoughtProcess)
local Scheduler = require(script.Scheduler)
local TargetSelector = require(script.TargetSelector)
local CharacterTasks = require(script.CharacterTasks)
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local Base = {}
Base.__index = Base
Base.FunctionEnum = Functions.FunctionEnum
Base.SubscribeEnum = Functions.SubscribeEnum

type FunctionName = TypeBehavior.FunctionName
type SubscribePosition = TypeBehavior.SubscribePosition
type FunctionCallbacks = TypeBehavior.FunctionCallbacks

function Base.new(character: Model)
	local self = setmetatable({}, Base)
	self.Character = character
	self.Router = Router.new()
	self.CharacterAPI = CharacterAPI.new(self, character)

	-- The API won't skip validation of this character anymore
	local UnloadedIndicator = self.Character:FindFirstChild("_UNLOADED")
	if UnloadedIndicator then
		UnloadedIndicator:Destroy()
	end

	if not self:_validateCharacter() then
		error("Invalid character provided to Base (invalid, or not a ModNPC)")
	else
		print("Base initialized with valid character:", character)
	end

	-- we know its safe to initialize our character dependencies now
	self.CharacterAPI:_init()
	self.Events = Events.new(self)
	self.Functions = Functions.new(self)

	-- NOTE: READ/SIGNAL ONLY. do not change props!
	--       defeats the whole purpose of the character api if you do
	self.Humanoid = character:FindFirstChildOfClass("Humanoid")
	self:_initHumanoid()

	-- this is for our old npcs who dont understand our alien technology
	self.processingDamage = false

	self.Configuration = Configuration.new(self, character)
	self.Assets = Assets.new(self, character)
	self.Dialogue = Dialogue.new(self, character)
	self.Animation = Animation.new(self, character)
	self.Humanoid = Humanoid.new(self, character)
	self.Movement = Movement.new(self, character)
	self.TargetSelector = TargetSelector.new(self)
	self.Tasks = Scheduler.new(self)
	self.Scheduler = self.Tasks
	self.CharacterTasks = CharacterTasks.new(self)

	self.ThoughtProcess = ThoughtProcess.new(self, character)
	self.Movement:Init()
	self.ThoughtProcess:Init()
	self.alive = true

	self:_registerMainFunctions()
	self:_registerModScripts()

	-- TODO; mod tasks integrate here as well
	-- Once we've registered our valid tasks, then we look at this npc's start tasks and spawn them.
	-- Tasks must be constructed (with Base) before the scheduler can start them.
	local startTasks = self.Configuration:GetStartTasks()
	for _, taskName in ipairs(startTasks) do
		local taskConstructor = self.CharacterTasks[taskName]
		if not taskConstructor then
			warn("Auto start fail: unknown task", taskName)
			continue
		end

		local taskObject, createError = taskConstructor.new()
		if not taskObject then
			warn("Auto start fail: could not create", taskName, createError)
			continue
		end

		local started, startError = self.Scheduler:Start(taskObject)
		if not started then
			warn("Auto start fail:", taskName, startError)
		end
	end

	self.Subscriptions = {
		self.Events:Subscribe(TypeCharacterEvents.Names.Humanoid.Died, function()
			self.alive = false
			self.Tasks:Destroy()
			self.Configuration:Unwatch()
		end)
	}


	return self
end

function Base:IsAlive()
	return self.alive
end

function Base:_registerModScripts()
	local modScripts = self.CharacterAPI:GetModScripts()
	print(modScripts)
	for _, modScript in ipairs(modScripts) do
		local success, errorMessage = pcall(modScript.init, self)
		if not success then
			warn("Failed to initialize mod script:", errorMessage)
		end
	end
end

function Base:_registerMainFunctions()
	self.Functions:RegisterMainFunctions()
end

function Base.SubscribeFunction<FunctionNameType>(
	self,
	functionName: FunctionNameType,
	callback: FunctionCallbacks,
	position: SubscribePosition
)
	return self.Functions:SubscribeFunction(functionName, callback, position)
end

function Base:_isProcessingDamage()
	return self.processingDamage == true
end

function Base:_initHumanoid()
	-- TODO: move to damage module later
	self.healthChangedConnection = self.Humanoid.HealthChanged:Connect(function(newHealth)
		if self:_isProcessingDamage() then
			-- once we read the health change, we can safely set processingDamage to false
			-- only set to true when we called for it
			self.processingDamage = false
			return
		end

		warn("Humanoid health unexpectedly changed for character:", self.Character.Name, "New health:", newHealth)
	end)
end

function Base:_validateCharacter()
	return self.CharacterAPI:ValidateCharacter()
end

return Base
