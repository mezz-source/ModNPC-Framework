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

local function createSubscription(owner, functionName, position, callback)
	local subscription = {
		Callback = callback,
		Active = true,
	}

	-- A function's subscriptions are bucketed by position, so the bucket has to be searched, not the whole entry
	function subscription:Unsubscribe()
		if not self.Active then
			return false
		end

		local subscriptions = owner.Subscriptions[functionName]
		local bucket = if subscriptions then subscriptions[position] else nil
		local index = if bucket then table.find(bucket, self) else nil
		if not bucket or not index then
			return false
		end

		self.Active = false
		table.remove(bucket, index)
		if #subscriptions.First + #subscriptions.Last + #subscriptions.Replace == 0 then
			owner.Subscriptions[functionName] = nil
		end
		return true
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
		[Functions.FunctionEnum.DodgeRandomly] = bind("DodgeRandomDirection"),
		[Functions.FunctionEnum.Dodge] = bind("Dodge"),
		[Functions.FunctionEnum.ApplyImpulse] = bind("ApplyImpulse"),
		[Functions.FunctionEnum.ApplyAngularImpulse] = bind("ApplyAngularImpulse"),
		[Functions.FunctionEnum.Move] = bind("Move"),
		[Functions.FunctionEnum.StopMoving] = bind("StopMoving"),
		[Functions.FunctionEnum.SetWalkDirection] = bind("SetWalkDirection"),
		[Functions.FunctionEnum.ClearWalkDirection] = bind("ClearWalkDirection"),
		[Functions.FunctionEnum.LockMovement] = bind("LockMovement"),
		[Functions.FunctionEnum.UnlockMovement] = bind("UnlockMovement"),
	}

	local function bindIfAvailable(moduleName, methodName, functionName)
		local module = self.Base[moduleName]
		if module and type(module[methodName]) == "function" then
			self.MainFunctions[functionName] = function(...)
				return module[methodName](module, ...)
			end
		end
	end

	bindIfAvailable("TargetSelector", "IsValidPreference", Functions.FunctionEnum.IsValidTargetPreference)
	bindIfAvailable("TargetSelector", "SelectBest", Functions.FunctionEnum.SelectBestTarget)
	bindIfAvailable("Sound", "Play", Functions.FunctionEnum.PlaySound)
	bindIfAvailable("Sound", "PlayCategory", Functions.FunctionEnum.PlaySoundCategory)
	bindIfAvailable("VFX", "Play", Functions.FunctionEnum.PlayVFX)
	bindIfAvailable("VFX", "PlayGroup", Functions.FunctionEnum.PlayVFXGroup)
	bindIfAvailable("Animation", "LoadAnimation", Functions.FunctionEnum.LoadAnimation)
	bindIfAvailable("Animation", "PlayAnimation", Functions.FunctionEnum.PlayAnimation)
	bindIfAvailable("Animation", "StopAnimation", Functions.FunctionEnum.StopAnimation)
	bindIfAvailable("Weapons", "EquipWeapon", Functions.FunctionEnum.EquipWeapon)
	bindIfAvailable("Weapons", "UnequipWeapon", Functions.FunctionEnum.UnequipWeapon)
	bindIfAvailable("Weapons", "ArmWeapon", Functions.FunctionEnum.ArmWeapon)
	bindIfAvailable("Weapons", "DisarmWeapon", Functions.FunctionEnum.DisarmWeapon)
	bindIfAvailable("Targetting", "GetTargets", Functions.FunctionEnum.GetTargets)
	bindIfAvailable("Movement", "Wander", Functions.FunctionEnum.Wander)
	bindIfAvailable("Damage", "IsStaggered", Functions.FunctionEnum.IsStaggered)
	bindIfAvailable("Damage", "IsLaunched", Functions.FunctionEnum.IsLaunched)
	bindIfAvailable("Damage", "BeginStagger", Functions.FunctionEnum.BeginStagger)
	bindIfAvailable("Damage", "EndStagger", Functions.FunctionEnum.EndStagger)
	bindIfAvailable("Damage", "BeginLaunch", Functions.FunctionEnum.BeginLaunch)
	bindIfAvailable("Damage", "EndLaunch", Functions.FunctionEnum.EndLaunch)
	bindIfAvailable("Abilities", "CanMove", Functions.FunctionEnum.CanMove)
	bindIfAvailable("Abilities", "CanAttack", Functions.FunctionEnum.CanAttack)
	bindIfAvailable("Abilities", "CanDodge", Functions.FunctionEnum.CanDodge)
	bindIfAvailable("Abilities", "CanBeEvasive", Functions.FunctionEnum.CanBeEvasive)
	bindIfAvailable("Abilities", "CanBlock", Functions.FunctionEnum.CanBlock)
	bindIfAvailable("Damage", "IsBlocking", Functions.FunctionEnum.IsBlocking)
	bindIfAvailable("Damage", "BeginBlock", Functions.FunctionEnum.BeginBlock)
	bindIfAvailable("Damage", "EndBlock", Functions.FunctionEnum.EndBlock)
	bindIfAvailable("Damage", "BreakBlock", Functions.FunctionEnum.BreakBlock)
	bindIfAvailable("Damage", "IsBlockBroken", Functions.FunctionEnum.IsBlockBroken)
	bindIfAvailable("Damage", "GetHitCategory", Functions.FunctionEnum.GetHitCategory)
	bindIfAvailable("Defense", "ReactToIncomingAttack", Functions.FunctionEnum.ReactToIncomingAttack)
	bindIfAvailable("Skills", "GetSkillLevel", Functions.FunctionEnum.GetSkillLevel)
	bindIfAvailable("Skills", "GetSkillChance", Functions.FunctionEnum.GetSkillChance)
	bindIfAvailable("Skills", "RollSkill", Functions.FunctionEnum.RollSkill)
	bindIfAvailable("Skills", "RollSkills", Functions.FunctionEnum.RollSkills)
	bindIfAvailable("Stamina", "GetStamina", Functions.FunctionEnum.GetStamina)
	bindIfAvailable("Stamina", "GetCost", Functions.FunctionEnum.GetStaminaCost)
	bindIfAvailable("Stamina", "GetEfficiency", Functions.FunctionEnum.GetStaminaEfficiency)
	bindIfAvailable("Stamina", "IsExhausted", Functions.FunctionEnum.IsExhausted)
	bindIfAvailable("Stamina", "CanAfford",Functions.FunctionEnum.CanAffordStamina)
	bindIfAvailable("Stamina", "Purchase", Functions.FunctionEnum.PurchaseStamina)
	bindIfAvailable("Stamina", "Spend", Functions.FunctionEnum.SpendStamina)
	bindIfAvailable("Stamina", "Restore", Functions.FunctionEnum.RestoreStamina)
	bindIfAvailable("Stamina", "Break", Functions.FunctionEnum.BreakStamina)
	bindIfAvailable("Disposition", "GetDisposition", Functions.FunctionEnum.GetDisposition)
	bindIfAvailable("Disposition", "GetEngageDistance", Functions.FunctionEnum.GetEngageDistance)
	bindIfAvailable("Disposition", "GetHoldDistance", Functions.FunctionEnum.GetHoldDistance)
	bindIfAvailable("Disposition", "GetAttackStandoff", Functions.FunctionEnum.GetAttackStandoff)
	bindIfAvailable("Disposition", "GetAttackFit", Functions.FunctionEnum.GetAttackFit)
	bindIfAvailable("Disposition", "GetAttackPace", Functions.FunctionEnum.GetAttackPace)
	bindIfAvailable("Attacks", "PickDesiredAttack",Functions.FunctionEnum.PickDesiredAttack)
	bindIfAvailable("Attacks", "GetDesiredAttack", Functions.FunctionEnum.GetDesiredAttack)
	bindIfAvailable("Attacks", "ClearDesiredAttack", Functions.FunctionEnum.ClearDesiredAttack)
	bindIfAvailable("Attacks", "CanAffordAttack", Functions.FunctionEnum.CanAffordAttack)
	bindIfAvailable("Attacks", "IsReadyToAttack", Functions.FunctionEnum.IsReadyToAttack)
	bindIfAvailable("Attacks", "IsPressingOn", Functions.FunctionEnum.IsPressingOn)
	bindIfAvailable("Attacks", "CancelCurrentAttack",Functions.FunctionEnum.CancelCurrentAttack)
	bindIfAvailable("Attacks", "AttackCurrentTarget",Functions.FunctionEnum.AttackCurrentTarget)
	bindIfAvailable("Attacks", "MeleeAttackCurrentTarget", Functions.FunctionEnum.MeleeAttackCurrentTarget)
	bindIfAvailable("Attacks", "RangeAttackCurrentTarget", Functions.FunctionEnum.RangeAttackCurrentTarget)
	bindIfAvailable("Stimulants", "Receive", Functions.FunctionEnum.ReceiveStimulant)
	bindIfAvailable("Stimulants", "Drop", Functions.FunctionEnum.DropStimulant)
	bindIfAvailable("Stimulants", "GetStimulants", Functions.FunctionEnum.GetStimulants)
	bindIfAvailable("Stimulants", "Peek", Functions.FunctionEnum.PeekStimulant)
	bindIfAvailable("Stimulants", "Consume", Functions.FunctionEnum.ConsumeStimulant)
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

	local subscription = createSubscription(self, functionName, position, callback)
	table.insert(subscriptions[position], subscription)
	return subscription
end

function Functions:UnbindAllFunctions()
	-- Holders of a subscription shouldn't see it as live once its function is gone
	for _, buckets in self.Subscriptions do
		for _, bucket in buckets do
			for _, subscription in bucket do
				subscription.Active = false
			end
		end
	end

	self.MainFunctions = {}
	self.Subscriptions = {}
end

function Functions:Destroy()
	self:UnbindAllFunctions()
	self.Base = nil
	self.CharacterAPI = nil
end

return Functions
