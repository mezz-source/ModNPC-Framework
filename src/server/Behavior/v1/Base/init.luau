local ServerScriptService = game:GetService("ServerScriptService")
local CharacterAPI = require(script.CharacterAPI)
local Router = require(script.Router)
local Events = require(script.Events)
local State = require(script.State)
local Configuration = require(script.Configuration)
local Assets = require(script.Assets)
local Dialogue = require(script.Dialogue)
local Animation = require(script.Animation)
local Sound = require(script.Sound)
local VFX = require(script.VFX)
local Humanoid = require(script.Humanoid)
local Damage = require(script.Damage)
local Abilities = require(script.Abilities)
local Distance = require(script.Distance)
local Skills = require(script.Skills)
local Disposition = require(script.Disposition)
local Stamina = require(script.Stamina)
local Attacks = require(script.Attacks)
local Weapons = require(script.Weapons)
local Movement = require(script.Movement)
local Functions = require(script.Functions)
local ThoughtProcess = require(script.ThoughtProcess)
local Stimulants = require(script.Stimulants)
local Defense = require(script.Defense)
local StimulantBuilder = require(script.StimulantBuilder)
local Scheduler = require(script.Scheduler)
local TargetSelector = require(script.TargetSelector)
local CharacterTasks = require(script.CharacterTasks)
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local Base = {}
Base.__index = Base
Base.FunctionEnum = Functions.FunctionEnum
Base.SubscribeEnum = Functions.SubscribeEnum
-- For tasks, modules and mod scripts to describe the stimulants they send (CharacterAPI:SendStimulant)
Base.StimulantBuilder = StimulantBuilder

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

	local isValid, invalidReason = self:_validateCharacter()
	if not isValid then
		error(
			"Invalid character provided to Base ("
				.. character.Name
				.. " is invalid, or not a ModNPC): "
				.. tostring(invalidReason)
		)
	-- else
	-- 	print("Base initialized with valid character:", character)
	end

	-- we know its safe to initialize our character dependencies now
	self.CharacterAPI:_init()
	self.Events = Events.new(self)
	-- Must exist before any module that registers or sets a state
	self.State = State.new(self)
	self.Functions = Functions.new(self)

	-- NOTE: READ/SIGNAL ONLY. do not change props!
	--       defeats the whole purpose of the character api if you do
	self.Humanoid = character:FindFirstChildOfClass("Humanoid")

	-- Takes damage both from the API and from our old npcs who dont understand our alien technology.
	-- Reads the raw humanoid above, so it has to be built before self.Humanoid is replaced by its module.
	self.Damage = Damage.new(self, character)

	self.Configuration = Configuration.new(self, character)
	self.Assets = Assets.new(self, character)
	self.Distance = Distance.new(self, character)
	self.Skills = Skills.new(self, character)
	-- (cast for the same reason as Abilities below)
	self.Stamina = Stamina.new(self :: any, character)
	-- Reads the raw humanoid above like Damage does, so it has to be built before self.Humanoid is replaced by its module
	self.Disposition = Disposition.new(self, character)
	self.Dialogue = Dialogue.new(self, character)
	-- (cast for the same reason as Abilities below)
	self.Sound = Sound.new(self :: any, character)
	self.VFX = VFX.new(self, character)
	self.Animation = Animation.new(self, character)
	self.Humanoid = Humanoid.new(self, character)
	self.Movement = Movement.new(self, character)
	self.TargetSelector = TargetSelector.new(self)
	self.Tasks = Scheduler.new(self)
	self.Scheduler = self.Tasks
	-- (the casts from here on are for the same reason as Abilities below)
	self.CharacterTasks = CharacterTasks.new(self :: any)
	self.Attacks = Attacks.new(self :: any, character)
	self.Weapons = Weapons.new(self :: any, character)
	-- Only reads states, which every module above has registered by now
	-- (the cast keeps the type solver from inferring everything `self` has collected so far, which got too big for it)
	self.Abilities = Abilities.new(self :: any)

	self.ThoughtProcess = ThoughtProcess.new(self, character)
	-- What other characters made us aware of, consumed on the thought process's reaction ticks
	self.Stimulants = Stimulants.new(self, character)
	-- How we meet the hits the stimulants warn us of. Registers the DefenseState, which Abilities reads.
	self.Defense = Defense.new(self :: any, character)
	self.Movement:Init()
	self.Damage:Init()
	self.Stamina:Init()
	self.Disposition:Init()
	self.Stimulants:Init()
	self.ThoughtProcess:Init()
	self.alive = true

	self:_registerMainFunctions()
	self:_registerModScripts()

	-- After the mod scripts, so they can hook EquipWeapon before the first weapon goes on. Equipping runs functions,
	-- which are only registered now.
	self.Attacks:Init()
	-- Hooks DropStimulant, so only once the functions are registered
	self.Defense:Init()
	self.Weapons:Init()
	self.Movement:InitDodges()

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

-- A stimulant sent from this character, described by chaining (To, WithPriority, Lasting...) and ended with Send or Emit
function Base:NewStimulant(name: string)
	return StimulantBuilder.new(name, self.CharacterAPI)
end

function Base:_registerModScripts()
	local modScripts = self.CharacterAPI:GetModScripts()
	-- print(modScripts)
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

function Base:_validateCharacter(): (boolean, string?)
	return self.CharacterAPI:ValidateCharacter()
end

return Base
