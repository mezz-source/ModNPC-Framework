-- 06_TauntTask: a custom task, registered from a mod and started from an event.
--
-- A taunt is a short beat where the character plants its feet and shows off. It occupies the Movement and Arms
-- resources with the Replace policy, so starting one cuts off any walk, chase, guard or attack that was using them.
-- Whatever way the taunt ends (it runs out, something replaces it, the character dies), the Terminated handler gives
-- everything back.
--
-- Shows:  a task class built from base.Task / base.TaskEnums, base:RegisterTask, a mod-owned State,
--         core functions called through base.Functions, cleanup in Terminated, starting a task from an event.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local Events = TypeCharacterEvents.Names

local STATE_KEY = "TauntState"
local TauntStateEnum = table.freeze({ None = "None", Taunting = "Taunting" })

local TAUNT_COLOR = Color3.fromRGB(255, 200, 60)
local PULSE_EVERY = 0.4
local COOLDOWN = 10

-- The class is built inside a function because it needs the character's Base for the parent class and the enums.
local function createTauntClass(base: Base)
	local Enums = base.TaskEnums
	local ParentTask: any = base.Task

	local TauntTask: any = {}
	TauntTask.__index = TauntTask
	setmetatable(TauntTask, ParentTask)

	-- Constructors always receive the character's Base first. base.CharacterTasks.Taunt.new(...) supplies it for you.
	function TauntTask.new(taskBase: Base, duration: number?)
		local task, errorMessage = ParentTask.new(taskBase, {
			Category = Enums.CategoriesEnum.Movement,
			Resources = { Enums.ResourcesEnum.Movement, Enums.ResourcesEnum.Arms },
			-- every Base module the task touches directly (CharacterAPI is implicit)
			Dependencies = { Enums.Dependencies.Functions, Enums.Dependencies.State },
			Policy = Enums.Policy.Replace,
		})
		if not task then
			return nil, errorMessage
		end

		local self = setmetatable(task, TauntTask)
		self.Functions = taskBase.Functions
		self.State = taskBase.State
		self.CharacterAPI = taskBase.CharacterAPI
		self.Duration = duration or 2
		self.Elapsed = 0
		self.SincePulse = PULSE_EVERY -- pulse straight away
		return self
	end

	function TauntTask:Start()
		local started, errorMessage = ParentTask.Start(self)
		if not started then
			return false, errorMessage
		end

		-- Registered once, so it runs however the task ends
		self.Terminated:Connect(function(_reason)
			self.State:Set(STATE_KEY, TauntStateEnum.None)
			self.Functions:CallFunction(FunctionEnum.UnlockMovement, self)
			self.CharacterAPI:RemoveHighlight("Taunt")
		end)

		self.State:Set(STATE_KEY, TauntStateEnum.Taunting)
		self.Functions:CallFunction(FunctionEnum.StopMoving)
		self.Functions:CallFunction(FunctionEnum.LockMovement, self) -- the source is the task itself
		self.CharacterAPI:CreateHighlight("Taunt", { FillColor = TAUNT_COLOR, FillTransparency = 1 })
		return true
	end

	function TauntTask:Update(deltaTime: number)
		if not self:IsRunning() then
			return
		end

		self.Elapsed += deltaTime
		if self.Elapsed >= self.Duration then
			self:Complete("Taunt finished")
			return
		end

		self.SincePulse += deltaTime
		if self.SincePulse >= PULSE_EVERY then
			self.SincePulse = 0
			local glow = self.CharacterAPI:GetHighlight("Taunt")
			if glow then
				glow:SetFillTransparency(0.3)
				glow:TweenFillTransparency(1, PULSE_EVERY)
			end
		end
	end

	return TauntTask
end

local module = {}

function module.init(base: Base)
	base.State:Register(STATE_KEY, TauntStateEnum, TauntStateEnum.None)

	-- Mod init runs before start tasks are spawned, so "Taunt" could also be listed in the config's StartTasks.
	local registered, registerError = base:RegisterTask("Taunt", createTauntClass(base))
	if not registered then
		warn("[Taunt] could not register the task:", registerError)
		return
	end

	-- Taunt the first time we spot a target, then at most every COOLDOWN seconds
	local readyAt = 0
	base.Events:Subscribe(Events.Targetting.TargetSpotted, function()
		if not base:IsAlive() or os.clock() < readyAt then
			return
		end
		if not base.Functions:CallFunction(FunctionEnum.CanMove) then
			return
		end

		local taunt, createError = base.CharacterTasks.Taunt.new(2)
		if not taunt then
			warn("[Taunt] could not create the task:", createError)
			return
		end

		local started, startError = base.Scheduler:Start(taunt)
		if started then
			readyAt = os.clock() + COOLDOWN
		else
			warn("[Taunt] could not start the task:", startError)
		end
	end)
end

return module
