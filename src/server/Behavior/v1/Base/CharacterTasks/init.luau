local CharacterTasks = {}

-- Adds a Base-bound constructor for taskClass under name. Shared by the modules in this folder and the tasks mod
-- scripts register (Base:RegisterTask), so both end up as base.CharacterTasks.<Name> and can be start tasks.
function CharacterTasks.register(tasks, base, name: string, taskClass): (boolean, string?)
	if type(name) ~= "string" or name == "" then
		return false, "Task name must be a non-empty string"
	end
	if type(taskClass) ~= "table" or type(taskClass.new) ~= "function" then
		return false, "Task " .. name .. " must be a table with a new(base, ...) function"
	end
	if tasks[name] then
		return false, "A task is already registered as " .. name
	end

	tasks[name] = {
		new = function(...)
			return taskClass.new(base, ...)
		end,
	}

	return true
end

-- Every task module in this folder gets a Base-bound constructor, keyed by module name.
-- Modules prefixed with "_" (like _EXAMPLE_TASK) are templates and are skipped.
function CharacterTasks.new(base)
	local tasks = {}

	for _, taskModule in ipairs(script:GetChildren()) do
		if not taskModule:IsA("ModuleScript") or string.sub(taskModule.Name, 1, 1) == "_" then
			continue
		end

		local success, taskClass = pcall(require, taskModule)
		if not success then
			warn("Could not load character task:", taskModule.Name, taskClass)
			continue
		end

		local registered, registerError = CharacterTasks.register(tasks, base, taskModule.Name, taskClass)
		if not registered then
			warn("Could not load character task:", registerError)
		end
	end

	return tasks
end

return CharacterTasks
