local CharacterAPI = require(script.CharacterAPI)
local Router = require(script.Router)
local Events = require(script.Events)
local Configuration = require(script.Configuration)
local Assets = require(script.Assets)
local Dialogue = require(script.Dialogue)
local Animation = require(script.Animation)
local Humanoid = require(script.Humanoid)
local Movement = require(script.Movement)
local Base = {}
Base.__index = Base

function Base.new(character: Model)
	local self = setmetatable({}, Base)
	self.Character = character
	self.Router = Router.new()
	self.Events = Events.new(self)
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
	self.Movement:Init()

	return self
end

function Base:_isProcessingDamage()
	return self.processingDamage == true
end

function Base:_initHumanoid()
	self.deathConnection = self.Humanoid.Died:Connect(function()
		print("We died!")
	end)

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
