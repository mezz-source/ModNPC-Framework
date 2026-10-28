local ServerScriptService = game:GetService("ServerScriptService")
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local CharacterAPI = {}
CharacterAPI.__index = CharacterAPI

type Module = TypeAPIFunctions.Module

local Modules = TypeAPIFunctions.Modules
local Functions = TypeAPIFunctions.Functions
local CharacterFunctions = Functions.CharacterUtility
local DamageFunctions = Functions.Damage
local MovementFunctions = Functions.Movement

local function response(success: boolean, message: string?, data: any?): TypeRequests.CharacterResponse
	return {
		Success = success,
		Message = message,
		Data = data,
	}
end

--[[
	API FUNCTIONS
]]

-- Animation

function CharacterAPI:LoadBaseAnimations() end

function CharacterAPI:LoadAnimation(
	animationAsset: { AnimationId: string },
	animationName: string,
	priority: Enum.AnimationPriority?,
	loop: boolean?
): AnimationTrack?
	return self:RequestAPIData(Modules.Animation, Functions.Animation.LoadAnimation, {
		self.Character,
		animationAsset,
		animationName,
		{ Priority = priority, Loop = loop },
	}) :: AnimationTrack?
end

function CharacterAPI:PlayAnimation(
	animName: string,
	trackList: { [string]: AnimationTrack },
	fadeTime: number,
	priority: Enum.AnimationPriority,
	loop: boolean?,
	weight: number
): AnimationTrack?
	return self:RequestAPIData(Modules.Animation, Functions.Animation.PlayAnimation, {
		self.Character,
		animName,
		trackList,
		{ Priority = priority, Loop = loop, FadeTime = fadeTime, Weight = weight },
	})
end

function CharacterAPI:StopAnimation(animName: string, trackList: { [string]: AnimationTrack }, fadeTime: number)
	self:RequestAPI(
		Modules.Animation,
		Functions.Animation.StopAnimation,
		{ self.Character, animName, trackList, fadeTime }
	)
end

function CharacterAPI:AdjustAnimationSpeed(
	animName: string,
	trackList: { [string]: AnimationTrack },
	speed: number
): AnimationTrack?
	return self:RequestAPIData(Modules.Animation, Functions.Animation.AdjustSpeed, {
		self.Character,
		animName,
		trackList,
		speed,
	})
end

function CharacterAPI:UnloadAllAnimations(trackList: { [string]: AnimationTrack }, fadeTime: number)
	self:RequestAPI(Modules.Animation, Functions.Animation.UnloadAllAnimations, { self.Character, trackList, fadeTime })
end

-- Damage

function CharacterAPI:DealSelfHumanoidDamage(amount: number): TypeRequests.CharacterResponse
	self.Base.processingDamage = true
	local response = self:RequestAPI(Modules.Damage, DamageFunctions.TakeHumanoidDamage, { self.Character, amount })
	return response
end

-- Moveement

function CharacterAPI:Jump()
	return self:RequestAPI(Modules.Movement, MovementFunctions.Jump, { self.Character })
end

function CharacterAPI:SetWalkSpeed(speed: number)
	return self:RequestAPI(Modules.Movement, MovementFunctions.SetWalkSpeed, { self.Character, speed })
end

function CharacterAPI:MoveTo(position: Vector3)
	return self:RequestAPI(Modules.Movement, MovementFunctions.MoveTo, { self.Character, position })
end

-- Walk relative to the way the character is facing, without the caller needing the character's transform
function CharacterAPI:MoveInDirection(direction: TypeMovement.MovementDirection)
	return self:RequestAPI(Modules.Movement, MovementFunctions.MoveInDirection, { self.Character, direction })
end

function CharacterAPI:StopMoving()
	return self:RequestAPI(Modules.Movement, MovementFunctions.StopMoving, { self.Character })
end

function CharacterAPI:LockCharacter()
	return self:RequestAPI(Modules.Movement, MovementFunctions.LockCharacter, { self.Character })
end

function CharacterAPI:UnlockCharacter()
	return self:RequestAPI(Modules.Movement, MovementFunctions.UnlockCharacter, { self.Character })
end

function CharacterAPI:LockRotation()
	return self:RequestAPI(Modules.Movement, MovementFunctions.LockRotation, { self.Character })
end

function CharacterAPI:UnlockRotation()
	return self:RequestAPI(Modules.Movement, MovementFunctions.UnlockRotation, { self.Character })
end

function CharacterAPI:SetFocusTarget(target: Instance)
	return self:RequestAPI(Modules.Movement, MovementFunctions.SetFocusTarget, { self.Character, target })
end

function CharacterAPI:RemoveFocusTarget()
	return self:RequestAPI(Modules.Movement, MovementFunctions.RemoveFocusTarget, { self.Character })
end

function CharacterAPI:ApplyImpulse(velocityChange: Vector3)
	return self:RequestAPI(Modules.Movement, MovementFunctions.ApplyImpulse, { self.Character, velocityChange })
end

function CharacterAPI:ApplyAngularImpulse(angularVelocityChange: Vector3)
	return self:RequestAPI(
		Modules.Movement,
		MovementFunctions.ApplyAngularImpulse,
		{ self.Character, angularVelocityChange }
	)
end

-- Validation

function CharacterAPI:ValidateCharacter()
	if not self.Character or not self.Character:IsA("Model") then
		error("Invalid character provided to CharacterAPI (no character/not a Model)")
	end

	return self:RequestAPIData(Modules.CharacterUtility, CharacterFunctions.IsValidModNPC, { self.Character }) == true
end

function CharacterAPI:GetModScripts(): { {} }
	if self.ModScripts then
		return self.ModScripts
	end

	self.ModScripts = self:RequestAPIData(
		Modules.ContentDelivery,
		Functions.ContentDelivery.GetModScripts,
		{ self.Character }
	) or {}

	return self.ModScripts
end

-- Targetting

function CharacterAPI:GetAllTargets(): { TypeTargetting.TargettingContext }
	return self:RequestAPIData(Modules.Targetting, Functions.Targetting.GetTargets, nil) or {}
end

function CharacterAPI:GetTargetsOfType(characterType: string): { TypeTargetting.TargettingContext }
	return self:RequestAPIData(Modules.Targetting, Functions.Targetting.GetTargetsOfType, { characterType }) or {}
end

function CharacterAPI:GetTeam(): string?
	return self:RequestAPIData(Modules.CharacterUtility, CharacterFunctions.GetTeam, { self.Character })
end

-- Root part to root part distance in studs between two characters, nil if either has no root
function CharacterAPI:GetDistanceBetween(from: Model, to: Model): number?
	return self:RequestAPIData(Modules.Targetting, Functions.Targetting.GetDistance, { from, to })
end

-- Distance from this character to the target
function CharacterAPI:GetDistanceTo(target: Model): number?
	return self:GetDistanceBetween(self.Character, target)
end

-- Health queries default to this character when no character is given
function CharacterAPI:GetHealth(character: Model?): number?
	return self:RequestAPIData(Modules.CharacterUtility, CharacterFunctions.GetHealth, { character or self.Character })
end

function CharacterAPI:GetMaxHealth(character: Model?): number?
	return self:RequestAPIData(
		Modules.CharacterUtility,
		CharacterFunctions.GetMaxHealth,
		{ character or self.Character }
	)
end

function CharacterAPI:GetHealthInfo(character: Model?): TypeTargetting.HealthInfo?
	return self:RequestAPIData(
		Modules.CharacterUtility,
		CharacterFunctions.GetHealthInfo,
		{ character or self.Character }
	)
end

-- Only targets on one of the given teams
function CharacterAPI:GetTargetsOnTeams(teams: { string }): { TypeTargetting.TargettingContext }
	return self:RequestAPIData(
		Modules.Targetting,
		Functions.Targetting.GetTargetsWithTeamFilter,
		{ TypeTargetting.FilterTypes.Include, teams }
	) or {}
end

-- Every target not on one of the given teams
function CharacterAPI:GetTargetsExcludingTeams(teams: { string }): { TypeTargetting.TargettingContext }
	return self:RequestAPIData(
		Modules.Targetting,
		Functions.Targetting.GetTargetsWithTeamFilter,
		{ TypeTargetting.FilterTypes.Exclude, teams }
	) or {}
end

-- Targets on a different team than this character; excludes the character itself
function CharacterAPI:GetOpposingTargets(): { TypeTargetting.TargettingContext }
	local team = self:GetTeam()
	local targets = if team then self:GetTargetsExcludingTeams({ team }) else self:GetAllTargets()
	return self:_withoutSelf(targets)
end

-- Targets on the same team as this character; excludes the character itself
function CharacterAPI:GetSameTeamTargets(): { TypeTargetting.TargettingContext }
	local team = self:GetTeam()
	if not team then
		return {}
	end

	return self:_withoutSelf(self:GetTargetsOnTeams({ team }))
end

-- Requests

function CharacterAPI:RequestAPI(moduleName: Module, functionName: string, arguments: { any }?)
	local request = {
		ModuleName = moduleName,
		Function = functionName,
		Arguments = arguments or {},
	}

	local response = self.Base.Router:Request(request)
	if not response.Success then
		warn("API request failed:", response.Message)
	end

	return response
end

function CharacterAPI:RequestAPIData(moduleName: Module, functionName: string, arguments: { any }?)
	local response = self:RequestAPI(moduleName, functionName, arguments)
	return response.Data
end

--[[
	INTERNAL
]]

function CharacterAPI:_withoutSelf(targets: { TypeTargetting.TargettingContext }): { TypeTargetting.TargettingContext }
	local filtered = {}
	for _, context in targets do
		if context.Character ~= self.Character then
			table.insert(filtered, context)
		end
	end
	return filtered
end

function CharacterAPI:_handleDamage(damageContext: TypeDamage.IncomingDamageContext): TypeDamage.OutgoingDamageContext
	local didHit = math.random(1, 2) == 1
	local context = {
		Attacker = damageContext.Attacker,
		Receiver = self.Character,
		Amount = didHit and damageContext.Amount or 0,
		DidHit = didHit,
		RecieveType = didHit and TypeDamage.RecieveTypes.Hit or TypeDamage.RecieveTypes.Blocked,
	}

	-- this safely changes the health prop without triggering an event pickup
	if context.Amount > 0 then
		self:DealSelfHumanoidDamage(context.Amount)
	end

	return context
end

function CharacterAPI.new(Base: {}, character: Model)
	local self = setmetatable({}, CharacterAPI)
	self.Character = character
	self.Base = Base
	self.FunctionConnection = nil
	self.EventConnection = nil
	self.ModScripts = nil
	return self
end

function CharacterAPI:_functionRecieved(functionName, arguments)
	print("Function received:", functionName, arguments)
	-- TODO: make module similar to api functions cuz i dont wanna deal with this junk
	if functionName == "Damage" then
		return self:_handleDamage(arguments)
	else
		return response(false, "Unknown function: " .. functionName)
	end
end

function CharacterAPI:_eventRecieved(eventName, arguments)
	if not eventName then
		warn("Event received with no name:", arguments)
		return
	end

	return self.Base.Events:Dispatch(eventName, arguments)
end

function CharacterAPI:_init()
	self.Folder = self.Character:WaitForChild("ModNPC")
	self.Internal = self.Folder:WaitForChild("_internal")
	self.Binds = self.Internal:WaitForChild("_binds")
	self.CharacterFunction = self.Binds:WaitForChild("CharacterFunction") :: BindableFunction
	self.CharacterEvent = self.Binds:WaitForChild("CharacterEvent") :: BindableEvent

	self.CharacterFunction.OnInvoke = function(functionName: string, arguments: { any }?)
		return self:_functionRecieved(functionName, arguments)
	end

	self.CharacterEvent.Event:Connect(function(eventName: string, arguments: { any }?)
		return self:_eventRecieved(eventName, arguments)
	end)

	print("CharacterAPI initialized for character:", self.Character.Name)
end

return CharacterAPI
