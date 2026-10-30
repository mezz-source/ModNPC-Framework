local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local MovementEnum = TypeMovement.MovementEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- Walks in one direction (relative to the way the character faces) until it is stopped, or until its duration
-- runs out. Parallel on purpose: walk tasks in different directions are combined by Movement, so a character
-- can advance and strafe at once by running one task for each.
local WalkTask = {}
WalkTask.__index = WalkTask
setmetatable(WalkTask, Task)

function WalkTask.new(base, direction: TypeMovement.MovementDirection, duration: number?)
	if MovementEnum[direction] == nil then
		return nil, "Invalid walk direction: " .. tostring(direction)
	end
	if duration ~= nil and (type(duration) ~= "number" or duration <= 0) then
		return nil, "Walk duration must be a positive number"
	end

	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Movement,
		Resources = { ResourceEnum.Movement },
		Dependencies = { Dependencies.Functions },
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, WalkTask)
	self.Functions = base.Functions

	self.Direction = direction
	-- nil walks until stopped
	self.Duration = duration
	self.Elapsed = 0

	return self
end

function WalkTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (duration, stopped, replaced, death), let go of our direction so the character doesn't
	-- keep walking it
	self.Terminated:Connect(function()
		self.Functions:CallFunction(FunctionEnum.ClearWalkDirection, self)
	end)

	self.Functions:CallFunction(FunctionEnum.SetWalkDirection, self, self.Direction)

	return true
end

function WalkTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	if self.Duration then
		self.Elapsed += deltaTime
		if self.Elapsed >= self.Duration then
			self:Complete("Duration elapsed")
			return
		end
	end

	-- Movement decides whether this needs a new request, we just keep our hold alive
	self.Functions:CallFunction(FunctionEnum.SetWalkDirection, self, self.Direction)
end

return WalkTask
