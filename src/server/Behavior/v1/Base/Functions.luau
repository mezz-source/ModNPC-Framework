local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

local Functions = {}
Functions.__index = Functions

type FunctionName = TypeBehavior.FunctionName
type SubscribePosition = TypeBehavior.SubscribePosition
type FunctionCallbacks = TypeBehavior.FunctionCallbacks

Functions.FunctionEnum = TypeCharacterFunctions.FunctionEnum
Functions.SubscribeEnum = table.freeze({
	First = "First",
	Last = "Last",
	Replace = "Replace",
})

local function createSubscription(owner, functionName, callback)
	local subscription = {
		Callback = callback,
		Active = true,
	}

	function subscription:Unsubscribe()
		if not self.Active then
			return false
		end

		local subscriptions = owner.Subscriptions[functionName]
		if not subscriptions then
			return false
		end

		for index, current in ipairs(subscriptions) do
			if current == self then
				self.Active = false
				table.remove(subscriptions, index)
				if #subscriptions == 0 then
					owner.Subscriptions[functionName] = nil
				end
				return true
			end
		end

		return false
	end

	return subscription
end

function Functions.new(base)
	local self = setmetatable({}, Functions)
	self.Base = base
	self.CharacterAPI = base.CharacterAPI
	self.MainFunctions = {}
	self.Subscriptions = {}

	return self
end

function Functions:CallFunction(functionName: FunctionName, ...)
	local mainFunction = self.MainFunctions[functionName]
	if not mainFunction then
		error("Unknown behavior function: " .. tostring(functionName))
	end

	local arguments = table.pack(...)
	local subscriptions = self.Subscriptions[functionName]
	local replacementResult

	if subscriptions then
		for _, subscription in ipairs(table.clone(subscriptions.First)) do
			if subscription.Active then
				subscription.Callback(table.unpack(arguments, 1, arguments.n))
			end
		end
	end

	if subscriptions then
		for _, subscription in ipairs(table.clone(subscriptions.Replace)) do
			if subscription.Active then
				replacementResult = table.pack(subscription.Callback(table.unpack(arguments, 1, arguments.n)))
			end
		end
	end

	local result
	if subscriptions and #subscriptions.Replace > 0 then
		result = replacementResult
	else
		result = table.pack(mainFunction(table.unpack(arguments, 1, arguments.n)))
	end

	if subscriptions then
		for _, subscription in ipairs(table.clone(subscriptions.Last)) do
			if subscription.Active then
				subscription.Callback(table.unpack(arguments, 1, arguments.n))
			end
		end
	end

	if not result then
		return
	end
	return table.unpack(result, 1, result.n)
end

function Functions:RegisterMainFunctions()
	local movement = self.Base.Movement
	local function bind(methodName)
		return function(...)
			return movement[methodName](movement, ...)
		end
	end

	self.MainFunctions = {
		[Functions.FunctionEnum.StartSprinting] = bind("StartSprinting"),
		[Functions.FunctionEnum.StopSprinting] = bind("StopSprinting"),
		[Functions.FunctionEnum.Jump] = bind("Jump"),
		[Functions.FunctionEnum.MoveLeft] = bind("MoveLeft"),
		[Functions.FunctionEnum.MoveRight] = bind("MoveRight"),
		[Functions.FunctionEnum.MoveForward] = bind("MoveForward"),
		[Functions.FunctionEnum.MoveBackward] = bind("MoveBackward"),
		[Functions.FunctionEnum.MoveTo] = bind("MoveTo"),
		[Functions.FunctionEnum.SetFocusTarget] = bind("SetFocusTarget"),
		[Functions.FunctionEnum.RemoveFocusTarget] = bind("RemoveFocusTarget"),
		[Functions.FunctionEnum.DodgeLeft] = bind("DodgeLeft"),
		[Functions.FunctionEnum.DodgeRight] = bind("DodgeRight"),
		[Functions.FunctionEnum.DodgeForward] = bind("DodgeForward"),
		[Functions.FunctionEnum.DodgeBackward] = bind("DodgeBackward"),
		[Functions.FunctionEnum.Dodge] = bind("Dodge"),
		[Functions.FunctionEnum.ApplyImpulse] = bind("ApplyImpulse"),
		[Functions.FunctionEnum.ApplyAngularImpulse] = bind("ApplyAngularImpulse"),
		[Functions.FunctionEnum.Move] = bind("Move"),
	}

	local function bindIfAvailable(moduleName, methodName, functionName)
		local module = self.Base[moduleName]
		if module and type(module[methodName]) == "function" then
			self.MainFunctions[functionName] = function(...)
				return module[methodName](module, ...)
			end
		end
	end

	bindIfAvailable("Targetting", "GetTargets", Functions.FunctionEnum.GetTargets)
	bindIfAvailable("Movement", "Wander", Functions.FunctionEnum.Wander)
	bindIfAvailable("Attacks", "MeleeAttack", Functions.FunctionEnum.MeleeAttack)
	bindIfAvailable("Attacks", "RangedAttack", Functions.FunctionEnum.RangedAttack)
end

function Functions.SubscribeFunction<FunctionNameType>(
	self,
	functionName: FunctionNameType,
	callback: FunctionCallbacks,
	position: SubscribePosition?
)
	if not self.MainFunctions[functionName] then
		error("Cannot subscribe to unknown behavior function: " .. tostring(functionName))
	end
	if type(callback) ~= "function" then
		error("Function subscription callback must be a function")
	end

	position = position or Functions.SubscribeEnum.Last
	if
		position ~= Functions.SubscribeEnum.First
		and position ~= Functions.SubscribeEnum.Last
		and position ~= Functions.SubscribeEnum.Replace
	then
		error("Unknown function subscription position: " .. tostring(position))
	end

	local subscriptions = self.Subscriptions[functionName]
	if not subscriptions then
		subscriptions = {
			First = {},
			Last = {},
			Replace = {},
		}
		self.Subscriptions[functionName] = subscriptions
	end

	if position == Functions.SubscribeEnum.Replace and #subscriptions.Replace > 0 then
		warn("Function already has a replacement:", functionName)
		return nil, "Function already has a replacement"
	end

	local subscription = createSubscription(self, functionName, callback)
	table.insert(subscriptions[position], subscription)
	return subscription
end

function Functions:UnbindAllFunctions()
	self.MainFunctions = {}
	self.Subscriptions = {}
end

function Functions:Destroy()
	self:UnbindAllFunctions()
	self.Base = nil
	self.CharacterAPI = nil
end

return Functions
