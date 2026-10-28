local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)

local Scheduler = {}
Scheduler.__index = Scheduler

local function resourcesOverlap(firstResources, secondResources)
	local resources = {}
	for _, resource in ipairs(firstResources) do
		resources[resource] = true
	end

	for _, resource in ipairs(secondResources) do
		if resources[resource] then
			return true
		end
	end

	return false
end

function Scheduler.new(base)
	local self = setmetatable({
		Base = base,
		Tasks = {},
		UpdateConnection = nil,
		Destroyed = false,
	}, Scheduler)

	self.UpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:_update(deltaTime)
	end)

	return self
end

function Scheduler:_removeTerminatedTasks()
	for index = #self.Tasks, 1, -1 do
		if not self.Tasks[index]:IsRunning() then
			table.remove(self.Tasks, index)
		end
	end
end

function Scheduler:_stopConflictingTasks(task)
	if task.Policy == TypeTask.Policy.Exclusive then
		for _, currentTask in ipairs(table.clone(self.Tasks)) do
			currentTask:Stop("Replaced by exclusive task")
		end
	elseif task.Policy == TypeTask.Policy.Replace then
		for _, currentTask in ipairs(table.clone(self.Tasks)) do
			if resourcesOverlap(currentTask.Resources, task.Resources) then
				currentTask:Stop("Replaced by resource-conflicting task")
			end
		end
	end
end

function Scheduler:Start(task)
	if self.Destroyed then
		return nil, "Scheduler has been destroyed"
	end
	if
		type(task) ~= "table"
		or type(task.Start) ~= "function"
		or type(task.Update) ~= "function"
		or type(task.Stop) ~= "function"
		or type(task.IsRunning) ~= "function"
	then
		return nil, "Invalid task"
	end
	if
		type(task.Category) ~= "string"
		or task.Category == ""
		or type(task.Resources) ~= "table"
		or type(task.Policy) ~= "string"
	then
		return nil, "Task is missing category or resources"
	end

	self:_removeTerminatedTasks()
	self:_stopConflictingTasks(task)

	local started, errorMessage = task:Start()
	if not started then
		return nil, errorMessage
	end

	table.insert(self.Tasks, task)
	return task
end

function Scheduler:Stop(task, reason: string?): boolean
	for _, currentTask in ipairs(self.Tasks) do
		if currentTask == task then
			local stopped = currentTask:Stop(reason)
			self:_removeTerminatedTasks()
			return stopped
		end
	end

	return false
end

function Scheduler:_update(deltaTime: number)
	if self.Destroyed then
		return
	end

	for _, task in ipairs(table.clone(self.Tasks)) do
		if task:IsRunning() then
			local success, errorMessage = pcall(task.Update, task, deltaTime)
			if not success then
				warn("Task update failed:", errorMessage)
				task:Stop("Update failed")
			end
		end
	end

	self:_removeTerminatedTasks()
end

function Scheduler:GetTasks(category: string?): { TypeTask.Task }
	local tasks = {}
	for _, task in ipairs(self.Tasks) do
		if not category or task.Category == category then
			table.insert(tasks, task)
		end
	end
	return tasks
end

function Scheduler:GetTask(category: string): TypeTask.Task?
	for _, task in ipairs(self.Tasks) do
		if task.Category == category then
			return task
		end
	end
	return nil
end

function Scheduler:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	for _, task in ipairs(table.clone(self.Tasks)) do
		task:Stop("Scheduler destroyed")
	end
	table.clear(self.Tasks)
	self.Base = nil
end

return Scheduler
