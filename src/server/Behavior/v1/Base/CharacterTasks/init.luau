local CharacterTasks = {}

-- Every task module in this folder gets a Base-bound constructor, keyed by module name.
-- Modules prefixed with "_" (like _EXAMPLE_TASK) are templates and are skipped.
function CharacterTasks.new(base)
	local tasks = {}

	for _, taskModule in ipairs(script:GetChildren()) do
		if not taskModule:IsA("ModuleScript") or string.sub(taskModule.Name, 1, 1) == "_" then
			continue
		end

		local success, taskClass = pcall(require, taskModule)
		if not success or type(taskClass) ~= "table" or type(taskClass.new) ~= "function" then
			warn("Could not load character task:", taskModule.Name, taskClass)
			continue
		end

		tasks[taskModule.Name] = {
			new = function(...)
				return taskClass.new(base, ...)
			end,
		}
	end

	return tasks
end

return CharacterTasks
