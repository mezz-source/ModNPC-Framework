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

	self.UpdateConnection = base.Heartbeat:Connect(function(deltaTime)
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

local function matchesSelector(task, selector: TypeTask.StopSelector?): boolean
	if not selector or (not selector.Categories and not selector.Resources) then
		return true
	end

	if selector.Categories and table.find(selector.Categories, task.Category) then
		return true
	end

	return selector.Resources ~= nil and resourcesOverlap(task.Resources, selector.Resources)
end

-- The one place tasks are closed in bulk. Essential tasks are left alone unless the caller passes CancelEssentials.
-- `cancel` ends the tasks with their Cancel (a taken-over ending); otherwise with a plain Stop (an eviction).
function Scheduler:_stopMatching(
	selector: TypeTask.StopSelector?,
	reason: string?,
	options: TypeTask.StopOptions?,
	cancel: boolean
): number
	local cancelEssentials = options ~= nil and options.CancelEssentials == true
	local cancelData = if options then options.CancelData else nil

	local stopped = 0
	for _, task in ipairs(table.clone(self.Tasks)) do
		-- a task can end another one while it ends (Terminated cleanup), so the list is not trusted to still be running
		if not task:IsRunning() or (task.Essential and not cancelEssentials) or not matchesSelector(task, selector) then
			continue
		end

		local ended
		if cancel and type(task.Cancel) == "function" then
			ended = task:Cancel(reason, cancelData)
		else
			ended = task:Stop(reason)
		end

		if ended then
			stopped += 1
		end
	end

	self:_removeTerminatedTasks()
	return stopped
end

-- Starting a task evicts what its policy says. Exclusive leaves the essential tasks running. Replace is a resource
-- conflict, which two tasks can't both win, so it ends the essential holder as well.
function Scheduler:_stopConflictingTasks(task)
	if task.Policy == TypeTask.Policy.Exclusive then
		self:_stopMatching(nil, "Replaced by exclusive task", nil, false)
	elseif task.Policy == TypeTask.Policy.Replace then
		self:_stopMatching(
			{ Resources = task.Resources },
			"Replaced by resource-conflicting task",
			{ CancelEssentials = true },
			false
		)
	end
end

-- Ends the running tasks the selector matches, with each task's Cancel. Returns how many ended.
function Scheduler:StopTasks(selector: TypeTask.StopSelector?, reason: string?, options: TypeTask.StopOptions?): number
	return self:_stopMatching(selector, reason, options, true)
end

function Scheduler:StopCategory(category: string, reason: string?, options: TypeTask.StopOptions?): number
	return self:_stopMatching({ Categories = { category } }, reason, options, true)
end

-- Ends the tasks holding the resource
function Scheduler:StopResource(resource: string, reason: string?, options: TypeTask.StopOptions?): number
	return self:_stopMatching({ Resources = { resource } }, reason, options, true)
end

function Scheduler:StopAll(reason: string?, options: TypeTask.StopOptions?): number
	return self:_stopMatching(nil, reason, options, true)
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

	-- The character is gone, so nothing is essential any more
	self:_stopMatching(nil, "Scheduler destroyed", { CancelEssentials = true }, false)
	table.clear(self.Tasks)
	self.Base = nil
end

return Scheduler
