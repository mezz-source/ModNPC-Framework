local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Signal = require(ServerScriptService.ModNPCServer.Util.Signal)

local Task = {}
Task.__index = Task

local function copyResources(resources)
	local result = {}
	local seen = {}

	for _, resource in ipairs(resources or {}) do
		if type(resource) ~= "string" or resource == "" then
			error("Task resources must be non-empty strings")
		end
		if seen[resource] then
			error("Task resources cannot contain duplicates: " .. resource)
		end

		seen[resource] = true
		table.insert(result, resource)
	end

	return result
end

local function validateDependencies(base, dependencies)
	local result = {}
	local seen = {}

	for _, dependency in ipairs(dependencies or {}) do
		if type(dependency) ~= "string" or dependency == "" then
			return nil, "Task dependencies must be non-empty strings"
		end
		if seen[dependency] then
			return nil, "Task dependencies cannot contain duplicates: " .. dependency
		end
		if not base or base[dependency] == nil then
			return nil, "Task dependency is missing from Base: " .. dependency
		end

		seen[dependency] = true
		table.insert(result, dependency)
	end

	return result
end

function Task.new(base, configuration)
	configuration = configuration or {}

	local policy = configuration.Policy or TypeTask.Policy.Parallel
	if
		policy ~= TypeTask.Policy.Exclusive
		and policy ~= TypeTask.Policy.Replace
		and policy ~= TypeTask.Policy.Parallel
	then
		error("Unknown task policy: " .. tostring(policy))
	end

	local category = configuration.Category
	if type(category) ~= "string" or category == "" then
		error("Task category must be a non-empty string")
	end

	local dependencies, dependencyError = validateDependencies(base, configuration.Dependencies)
	if not dependencies then
		return nil, dependencyError
	end

	local self = setmetatable({
		Base = base,
		Resources = copyResources(configuration.Resources),
		Dependencies = dependencies,
		Category = category,
		Policy = policy,
		Running = false,
		Completed = false,
		Terminated = Signal.new(),
	}, Task)

	return self
end

function Task:Start()
	if self.Running or self.Completed then
		return false, "Task has already started or terminated"
	end

	self.Running = true
	return true
end

function Task:Update(_deltaTime: number)
	if not self.Running then
		return
	end
end

function Task:Stop(reason: string?): boolean
	if not self.Running and self.Completed then
		return false
	end

	self.Running = false
	self.Completed = true
	self.Terminated:Fire(reason or "Stopped")
	return true
end

function Task:IsRunning(): boolean
	return self.Running
end

function Task:Complete(reason: string?)
	return self:Stop(reason or "Completed")
end

return Task
