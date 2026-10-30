local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local ExampleTask = {}
ExampleTask.__index = ExampleTask
setmetatable(ExampleTask, Task)

function ExampleTask.new(base, duration: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Movement,
		Resources = { ResourceEnum.Movement },
		Dependencies = { Dependencies.Configuration, Dependencies.Functions },
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, ExampleTask)
	return self
end

function ExampleTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	return true
end

function ExampleTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

end

return ExampleTask
