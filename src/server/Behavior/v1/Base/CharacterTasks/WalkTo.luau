local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

-- How close (studs, on the ground plane) counts as having reached the position. A humanoid rarely stops exactly on its
-- MoveTo point, and the position's height is only a guess.
local ARRIVE_DISTANCE = 3
-- A move that hasn't arrived by now (blocked, can't move, fell off) is given up on
local DEFAULT_TIMEOUT = 12
-- The move is re-issued this often (seconds): Humanoid:MoveTo gives up by itself after a while, and a walk hold from
-- another task would otherwise leave us standing wherever it dropped the character
local REFRESH_INTERVAL = 0.5

-- Walks to a position and completes once it gets there (or stops, with a reason, if it can't in time). Parallel like Walk:
-- whatever else is moving the character is Movement's to combine, and a chase that takes over simply overrides us.
local WalkToTask = {}
WalkToTask.__index = WalkToTask
setmetatable(WalkToTask, Task)

function WalkToTask.new(base, position: Vector3, timeout: number?)
	if typeof(position) ~= "Vector3" then
		return nil, "WalkTo position must be a Vector3"
	end
	if timeout ~= nil and (type(timeout) ~= "number" or timeout <= 0) then
		return nil, "WalkTo timeout must be a positive number"
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

	local self = setmetatable(task, WalkToTask)
	self.Character = base.Character
	self.Functions = base.Functions

	self.Position = position
	self.Timeout = timeout or DEFAULT_TIMEOUT
	self.Elapsed = 0
	self.sinceIssued = 0

	return self
end

-- Distance to the position along the ground, nil if the character has no body to measure from
function WalkToTask:GetDistance(): number?
	local rootPart = self.Character.PrimaryPart
	if not rootPart then
		return nil
	end

	local offset = self.Position - rootPart.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

function WalkToTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end, don't leave the character walking to a place nobody wants it at any more
	self.Terminated:Connect(function()
		self.Functions:CallFunction(FunctionEnum.StopMoving)
	end)

	self.Functions:CallFunction(FunctionEnum.MoveTo, self.Position)

	return true
end

function WalkToTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.Elapsed += deltaTime
	local distance = self:GetDistance()
	if not distance then
		self:Stop("Character has no root part")
		return
	end

	if distance <= ARRIVE_DISTANCE then
		self:Complete("Arrived")
		return
	end

	if self.Elapsed >= self.Timeout then
		self:Stop("Timed out")
		return
	end

	self.sinceIssued += deltaTime
	if self.sinceIssued >= REFRESH_INTERVAL then
		self.sinceIssued = 0
		self.Functions:CallFunction(FunctionEnum.MoveTo, self.Position)
	end
end

return WalkToTask
