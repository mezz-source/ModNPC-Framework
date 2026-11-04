-- 07_IntimidateTask: a task that affects ANOTHER character, through a stimulant.
--
-- Characters never reach into each other. To influence someone, you emit a stimulant: a named fact with a recipient,
-- a priority and an expiry. The receiver queues it and its own reaction tick decides what to do about it.
--
-- This single mod gives a character both halves:
--   * the Intimidate task (sender): a short roar, then an "Intimidated" stimulant to the character it just hit
--   * a listener (receiver): when an "Intimidated" stimulant is pending, consume it, lose some stamina, flinch
-- So it only does anything when both fighters carry the mod.
--
-- Shows:  a Parallel task with no resources, a task that checks it should still be running, base:NewStimulant,
--         StimulantsPending + ConsumeStimulant, SpendStamina through Functions, custom stimulant names.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local Events = TypeCharacterEvents.Names

-- Built-in stimulant names live in TypeStimulant.Names. Ours is private to this mod, so it is just a string.
local STIMULANT_NAME = "Intimidated"
local WINDUP = 0.6
local STAMINA_DAMAGE = 25
local COOLDOWN = 8

local function createIntimidateClass(base: Base)
	local Enums = base.TaskEnums
	local ParentTask: any = base.Task

	local IntimidateTask: any = {}
	IntimidateTask.__index = IntimidateTask
	setmetatable(IntimidateTask, ParentTask)

	function IntimidateTask.new(taskBase: Base, victim: Model)
		if typeof(victim) ~= "Instance" or not victim:IsA("Model") then
			return nil, "Intimidate needs a victim Model"
		end

		local task, errorMessage = ParentTask.new(taskBase, {
			Category = Enums.CategoriesEnum.Attack,
			-- Occupies nothing, so it never evicts or gets evicted by resource conflicts
			Resources = {},
			Dependencies = { Enums.Dependencies.Functions },
			Policy = Enums.Policy.Parallel,
		})
		if not task then
			return nil, errorMessage
		end

		local self = setmetatable(task, IntimidateTask)
		self.Functions = taskBase.Functions
		self.Victim = victim
		self.Elapsed = 0
		return self
	end

	function IntimidateTask:Update(deltaTime: number)
		if not self:IsRunning() then
			return
		end

		-- Losing our footing ruins the roar
		if self.Functions:CallFunction(FunctionEnum.IsStaggered) then
			self:Stop("Staggered")
			return
		end

		self.Elapsed += deltaTime
		if self.Elapsed < WINDUP then
			return
		end

		-- Build the stimulant step by step, then send it. The API fills in who it came from.
		local sent, sendError = self.Base
			:NewStimulant(STIMULANT_NAME)
			:To(self.Victim)
			:WithPriority("Normal")
			:Lasting(3)
			:WithData({ Power = STAMINA_DAMAGE })
			:Send()
		if not sent then
			warn("[Intimidate] could not send:", sendError)
		end
		self:Complete("Roared")
	end

	return IntimidateTask
end

local module = {}

function module.init(base: Base)
	local registered, registerError = base:RegisterTask("Intimidate", createIntimidateClass(base))
	if not registered then
		warn("[Intimidate] could not register the task:", registerError)
		return
	end

	-- Sender: roar at whoever our hit landed on
	local readyAt = 0
	base.Events:Subscribe(Events.Combat.AttackLanded, function(outcome)
		if not base:IsAlive() or os.clock() < readyAt then
			return
		end

		local task = base.CharacterTasks.Intimidate.new(outcome.Target)
		if task and base.Scheduler:Start(task) then
			readyAt = os.clock() + COOLDOWN
		end
	end)

	-- Receiver: StimulantsPending fires on each reaction tick with everything still queued, most urgent first
	base.Events:Subscribe(Events.Stimulant.Pending, function(pending)
		for _, stimulant in pending do
			if stimulant.Name ~= STIMULANT_NAME then
				continue
			end

			-- Consume what we act on, or it stays queued (and fires again) until it expires
			if not base.Functions:CallFunction(FunctionEnum.ConsumeStimulant, stimulant.Id) then
				continue
			end

			local power = if type(stimulant.Data) == "table" then stimulant.Data.Power else nil
			base.Functions:CallFunction(FunctionEnum.SpendStamina, power or STAMINA_DAMAGE, "Intimidated")
			base.CharacterAPI:FlashHighlight({ FillColor = Color3.fromRGB(255, 220, 80), FadeTime = 0.5 })
		end
	end)
end

return module
