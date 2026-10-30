local ServerScriptService = game:GetService("ServerScriptService")
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeSound = require(ServerScriptService.ModNPCServer.Types.v1.TypeSound)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
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
local WeaponEvents = TypeCharacterEvents.Names.Weapon
local FunctionEnum = TypeCharacterFunctions.FunctionEnum

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

-- Callers should go through Base.Damage so the resulting health change isn't read as unregistered damage
function CharacterAPI:DealSelfHumanoidDamage(amount: number): TypeRequests.CharacterResponse
	local response = self:RequestAPI(Modules.Damage, DamageFunctions.TakeHumanoidDamage, { self.Character, amount })
	return response
end

-- Callers should go through Base.Damage for the same reason as DealSelfHumanoidDamage
function CharacterAPI:RestoreSelfHumanoidHealth(amount: number): TypeRequests.CharacterResponse
	return self:RequestAPI(Modules.Damage, DamageFunctions.RestoreHumanoidHealth, { self.Character, amount })
end

-- Damage another character, with this character as the attacker. Callers should go through an attack so it is a
-- task the character can be interrupted from.
function CharacterAPI:DealDamage(
	receiver: Model,
	amount: number,
	damageType: TypeDamage.DamageType?,
	special: TypeDamage.DamageSpecial?,
	maxStaggerTime: number?
): TypeRequests.CharacterResponse
	return self:RequestAPI(
		Modules.Damage,
		DamageFunctions.TakeDamage,
		{ self.Character, receiver, amount, damageType, special, maxStaggerTime }
	)
end

-- Movement (fire and forget: nothing here depends on a response, so ordering is preserved by deferral)

function CharacterAPI:Jump()
	self:RequestAPI(Modules.Movement, MovementFunctions.Jump, { self.Character }, true)
end

function CharacterAPI:SetWalkSpeed(speed: number)
	self:RequestAPI(Modules.Movement, MovementFunctions.SetWalkSpeed, { self.Character, speed }, true)
end

function CharacterAPI:MoveTo(position: Vector3)
	self:RequestAPI(Modules.Movement, MovementFunctions.MoveTo, { self.Character, position }, true)
end

-- Walk relative to the way the character is facing, without the caller needing the character's transform
function CharacterAPI:MoveInDirection(directions: TypeMovement.MovementDirections)
	self:RequestAPI(Modules.Movement, MovementFunctions.MoveInDirection, { self.Character, directions }, true)
end

function CharacterAPI:StopMoving()
	self:RequestAPI(Modules.Movement, MovementFunctions.StopMoving, { self.Character }, true)
end

function CharacterAPI:LockCharacter()
	self:RequestAPI(Modules.Movement, MovementFunctions.LockCharacter, { self.Character }, true)
end

function CharacterAPI:UnlockCharacter()
	self:RequestAPI(Modules.Movement, MovementFunctions.UnlockCharacter, { self.Character }, true)
end

function CharacterAPI:LockRotation()
	self:RequestAPI(Modules.Movement, MovementFunctions.LockRotation, { self.Character }, true)
end

function CharacterAPI:UnlockRotation()
	self:RequestAPI(Modules.Movement, MovementFunctions.UnlockRotation, { self.Character }, true)
end

function CharacterAPI:SetFocusTarget(target: Instance)
	self:RequestAPI(Modules.Movement, MovementFunctions.SetFocusTarget, { self.Character, target }, true)
end

function CharacterAPI:RemoveFocusTarget()
	self:RequestAPI(Modules.Movement, MovementFunctions.RemoveFocusTarget, { self.Character }, true)
end

function CharacterAPI:ApplyImpulse(velocityChange: Vector3)
	self:RequestAPI(Modules.Movement, MovementFunctions.ApplyImpulse, { self.Character, velocityChange }, true)
end

-- A velocity change (studs/s) along directions relative to the way the character faces, flattened to horizontal, so the
-- caller never has to read the character's transform. Scaled by mass like ApplyImpulse.
function CharacterAPI:ApplyImpulseInDirection(directions: TypeMovement.MovementDirections, velocityChange: number)
	self:RequestAPI(
		Modules.Movement,
		MovementFunctions.ApplyImpulseInDirection,
		{ self.Character, directions, velocityChange },
		true
	)
end

-- A force, not a velocity change: it is not scaled by mass (see the API's applyForwardImpulse)
function CharacterAPI:ApplyForwardImpulse(force: number)
	self:RequestAPI(Modules.Movement, MovementFunctions.ApplyForwardImpulse, { self.Character, force }, true)
end

-- Throws another character away from this one
function CharacterAPI:PushAway(target: Model, force: number)
	self:RequestAPI(Modules.Movement, MovementFunctions.ApplyImpulseAwayFrom, { target, self.Character, force }, true)
end

function CharacterAPI:ApplyAngularImpulse(angularVelocityChange: Vector3)
	self:RequestAPI(
		Modules.Movement,
		MovementFunctions.ApplyAngularImpulse,
		{ self.Character, angularVelocityChange },
		true
	)
end

-- Sound

-- Loads the sounds into this character's root part; sounds whose name is already taken there are skipped with a warning
function CharacterAPI:LoadSounds(sounds: { TypeCDN.SoundData }): TypeSound.SoundLoadResult?
	return self:RequestAPIData(Modules.Sound, Functions.Sound.LoadSounds, { self.Character, sounds })
end

-- Fire and forget, like movement: failures (e.g. an unloaded sound) are warned by the API
function CharacterAPI:PlaySound(soundName: string, soundList: TypeSound.SoundList)
	self:RequestAPI(Modules.Sound, Functions.Sound.PlaySound, { self.Character, soundName, soundList }, true)
end

function CharacterAPI:StopSound(soundName: string, soundList: TypeSound.SoundList)
	self:RequestAPI(Modules.Sound, Functions.Sound.StopSound, { self.Character, soundName, soundList }, true)
end

-- Plays every sound in the list named prefix_<number>; returns the sounds started, nil if none matched
function CharacterAPI:PlaySoundGroup(prefix: string, soundList: TypeSound.SoundList): { Sound }?
	return self:RequestAPIData(Modules.Sound, Functions.Sound.PlaySoundGroup, { self.Character, prefix, soundList })
end

-- Plays one random sound in the list named prefix_<number>; returns it, nil if none matched
function CharacterAPI:PlaySoundCategory(prefix: string, soundList: TypeSound.SoundList, playbackSpeed: number?): Sound?
	return self:RequestAPIData(
		Modules.Sound,
		Functions.Sound.PlaySoundCategory,
		{ self.Character, prefix, soundList, playbackSpeed }
	)
end

-- Stops every sound in the list named prefix_<number>
function CharacterAPI:StopSoundsByPrefix(prefix: string, soundList: TypeSound.SoundList)
	self:RequestAPI(Modules.Sound, Functions.Sound.StopSoundsByPrefix, { self.Character, prefix, soundList }, true)
end

function CharacterAPI:UnloadAllSounds(soundList: TypeSound.SoundList)
	self:RequestAPI(Modules.Sound, Functions.Sound.UnloadAllSounds, { self.Character, soundList }, true)
end

-- VFX

-- Plays the effects at the destination, a part or a character (its root part is found by the API); returns the clones
-- created (they clean themselves up), nil if none played
function CharacterAPI:PlayVFX(effects: { TypeCDN.VFXData }, destination: BasePart | Model): { Instance }?
	return self:RequestAPIData(Modules.VFX, Functions.VFX.PlayVFX, { self.Character, effects, destination })
end

-- Bars

-- Makes a bar above this character's head. The bar drives its own UI (SetFill, SetSecondaryFill, colors...) and
-- destroys itself when its instance is removed, so it is kept by the caller; nil if it could not be made (for example
-- the name is already taken).
function CharacterAPI:CreateBar(barName: string, options: TypeBars.BarOptions?): TypeBars.Bar?
	return self:RequestAPIData(Modules.Bars, Functions.Bars.CreateBar, { self.Character, barName, options })
end

-- This character's bar of that name, nil if it has none
function CharacterAPI:GetBar(barName: string): TypeBars.Bar?
	return self:RequestAPIData(Modules.Bars, Functions.Bars.GetBar, { self.Character, barName })
end

-- Destroys this character's bar of that name; returns whether there was one. Not fire and forget, so the name is free
-- again as soon as this returns.
function CharacterAPI:RemoveBar(barName: string): boolean
	local response = self:RequestAPI(Modules.Bars, Functions.Bars.RemoveBar, { self.Character, barName })
	return response ~= nil and response.Success
end

-- Highlights

-- Makes a highlight on this character. The highlight drives its own instance (colors, transparencies, tweens, flashes;
-- its depth mode is always Occlude) and destroys itself when its instance is removed, so it is kept by the caller; nil
-- if it could not be made (for example the name is already taken).
function CharacterAPI:CreateHighlight(
	highlightName: string,
	options: TypeHighlights.HighlightOptions?
): TypeHighlights.Highlight?
	return self:RequestAPIData(
		Modules.Highlights,
		Functions.Highlights.CreateHighlight,
		{ self.Character, highlightName, options }
	)
end

-- A short lived, unnamed highlight on this character: shows its colors, fades out and destroys itself. Returns it for a
-- caller that wants to end or change it early, nil if it could not be made.
function CharacterAPI:FlashHighlight(options: TypeHighlights.FlashHighlightOptions?): TypeHighlights.Highlight?
	return self:RequestAPIData(Modules.Highlights, Functions.Highlights.FlashHighlight, { self.Character, options })
end

-- This character's highlight of that name, nil if it has none
function CharacterAPI:GetHighlight(highlightName: string): TypeHighlights.Highlight?
	return self:RequestAPIData(Modules.Highlights, Functions.Highlights.GetHighlight, { self.Character, highlightName })
end

-- Destroys this character's highlight of that name; returns whether there was one. Not fire and forget, so the name is
-- free again as soon as this returns.
function CharacterAPI:RemoveHighlight(highlightName: string): boolean
	local response =
		self:RequestAPI(Modules.Highlights, Functions.Highlights.RemoveHighlight, { self.Character, highlightName })
	return response ~= nil and response.Success
end

-- Stimulants

-- Sends a stimulant (see StimulantBuilder) from this character to whoever its recipient resolves to (never this character
-- itself) and forgets about it: nothing is waited for, and a refused one is only warned by the API. For stimulants that
-- simply run out; one that may need retracting goes through EmitStimulant.
function CharacterAPI:SendStimulant(stimulant: TypeStimulant.OutgoingStimulant)
	self:RequestAPI(Modules.Stimulants, Functions.Stimulants.Emit, { self.Character, stimulant.Recipient, stimulant }, true)
end

-- Like SendStimulant, but waits for the API: keep the id to retract the stimulant by. Nil if it was refused.
function CharacterAPI:EmitStimulant(stimulant: TypeStimulant.OutgoingStimulant): TypeStimulant.EmitResult?
	return self:RequestAPIData(
		Modules.Stimulants,
		Functions.Stimulants.Emit,
		{ self.Character, stimulant.Recipient, stimulant }
	)
end

-- Tells the receivers of a stimulant this character emitted that it is no longer true. Whether there was anything to
-- retract; safe to call for one that already expired.
function CharacterAPI:RetractStimulant(id: number): boolean
	return self:RequestAPIData(Modules.Stimulants, Functions.Stimulants.Retract, { self.Character, id }) == true
end

-- Weapon

function CharacterAPI:IsValidWeapon(weapon: Instance): boolean
	return self:RequestAPIData(Modules.Weapon, Functions.Weapon.IsValidWeapon, { weapon }) == true
end

function CharacterAPI:IsWeaponEquipped(weapon: Instance): boolean
	return self:RequestAPIData(Modules.Weapon, Functions.Weapon.IsEquipped, { weapon }) == true
end

-- Welds the weapon to this character (WeaponWeld) and flags it _EQUIPPED; returns the weld, nil on failure.
-- Dispatches WeaponEquipped on success, which is what brings the weapon's content sources in.
function CharacterAPI:EquipWeapon(weapon: Instance): Motor6D?
	local weld = self:RequestAPIData(Modules.Weapon, Functions.Weapon.EquipWeapon, { self.Character, weapon })
	if weld then
		self.Base.Events:Dispatch(WeaponEvents.Equipped, { Weapon = weapon } :: TypeCharacterEvents.WeaponChanged)
	end

	return weld
end

-- Removes the weapon's WeaponWeld and clears _EQUIPPED; returns whether the weapon was unequipped.
-- Dispatches WeaponUnequipped on success, which is what unloads the weapon's content sources.
function CharacterAPI:UnequipWeapon(weapon: Instance): boolean
	local response = self:RequestAPI(Modules.Weapon, Functions.Weapon.UnequipWeapon, { self.Character, weapon })
	local unequipped = response ~= nil and response.Success
	if unequipped then
		self.Base.Events:Dispatch(WeaponEvents.Unequipped, { Weapon = weapon } :: TypeCharacterEvents.WeaponChanged)
	end

	return unequipped
end

-- Unequips the weapon if it is held and puts it into the workspace in front of this character; it is no longer one of
-- this character's weapons afterwards. Dispatches WeaponUnequipped when it was held. Returns whether it was dropped.
function CharacterAPI:DropWeapon(weapon: Instance): boolean
	local response = self:RequestAPI(Modules.Weapon, Functions.Weapon.DropWeapon, { self.Character, weapon })
	if not response or not response.Success then
		return false
	end

	if response.Data == true then
		self.Base.Events:Dispatch(WeaponEvents.Unequipped, { Weapon = weapon } :: TypeCharacterEvents.WeaponChanged)
	end

	return true
end

-- A value out of the weapon's Config directory, e.g. { "WeaponSettings", "AlwaysArmed" }; nil when it is not there
function CharacterAPI:GetWeaponSetting(weapon: Instance, path: { string }): any
	return self:RequestAPIData(Modules.Weapon, Functions.Weapon.GetWeaponSetting, { weapon, path })
end

-- Every valid mod weapon this character carries
function CharacterAPI:GetWeapons(): { Instance }
	return self:RequestAPIData(Modules.Weapon, Functions.Weapon.GetWeapons, { self.Character }) or {}
end

function CharacterAPI:GetEquippedWeapon(): Instance?
	return self:RequestAPIData(Modules.Weapon, Functions.Weapon.GetEquippedWeapon, { self.Character })
end

-- Content

-- The asset index of a character or weapon (anything carrying a ModNPC/ModWeapon folder); this character by default
function CharacterAPI:GetAssetsIndex(container: Instance?): TypeCDN.AssetIndex?
	return self:RequestAPIData(
		Modules.ContentDelivery,
		Functions.ContentDelivery.GetAssetsIndex,
		{ container or self.Character }
	)
end

-- The attack index of a character or weapon (anything carrying a ModNPC/ModWeapon folder); this character by default
function CharacterAPI:GetAttacksIndex(container: Instance?): TypeAttack.AttackIndex?
	return self:RequestAPIData(
		Modules.ContentDelivery,
		Functions.ContentDelivery.GetAttacksIndex,
		{ container or self.Character }
	)
end

-- Validation

-- Whether the character is a valid ModNPC; when it is not, the second value is exactly what failed
function CharacterAPI:ValidateCharacter(): (boolean, string?)
	if not self.Character or not self.Character:IsA("Model") then
		error("Invalid character provided to CharacterAPI (no character/not a Model)")
	end

	local response = self:RequestAPI(Modules.CharacterUtility, CharacterFunctions.IsValidModNPC, { self.Character })
	if response and response.Data == true then
		return true, nil
	end

	return false, if response then response.Message else "Validation request returned no response"
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

-- Distance from this character's root part to a point in the world, nil if it has no root
function CharacterAPI:GetDistanceToPosition(position: Vector3): number?
	return self:RequestAPIData(Modules.Targetting, Functions.Targetting.GetDistanceToPosition, { self.Character, position })
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

-- Whether a character is exhausted right now (this character when none is given). Anything without stamina is not.
function CharacterAPI:IsExhausted(character: Model?): boolean
	return self:RequestAPIData(
		Modules.CharacterUtility,
		CharacterFunctions.IsExhausted,
		{ character or self.Character }
	) == true
end

-- Whether a character is staggered right now (this character when none is given). Anything that can't be is not.
function CharacterAPI:IsStaggered(character: Model?): boolean
	return self:RequestAPIData(
		Modules.CharacterUtility,
		CharacterFunctions.IsStaggered,
		{ character or self.Character }
	) == true
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

-- noResponse skips building/returning a response table; returns nil and failures are only warned by the API
function CharacterAPI:RequestAPI(
	moduleName: Module,
	functionName: string,
	arguments: { any }?,
	noResponse: boolean?
): TypeRequests.APIResponse?
	local request = {
		ModuleName = moduleName,
		Function = functionName,
		Arguments = arguments or {},
		NoResponse = noResponse,
	}

	local response = self.Base.Router:Request(request)
	if noResponse then
		return nil
	end

	if not response.Success then
		warn("API request failed:", response.Message)
	end

	return response
end

function CharacterAPI:RequestAPIData(moduleName: Module, functionName: string, arguments: { any }?)
	local response = self:RequestAPI(moduleName, functionName, arguments)
	return response and response.Data
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
	return self.Base.Damage:ReceiveRegistered(damageContext)
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

-- Everything answered here is a CharacterResponse, so the API side can tell a failure from a result.
-- Damage takes its context as the arguments; any other name goes straight to the Functions module
-- (FunctionEnum names, arguments as a list), which means mod subscriptions apply to it as well.
-- A function returning several values answers with them as a list.
function CharacterAPI:_functionRecieved(functionName, arguments)
	if functionName == "Damage" then
		return response(true, nil, self:_handleDamage(arguments))
	end

	local functions = self.Base.Functions
	if not functions or not functions.MainFunctions[functionName] then
		return response(false, "Unknown function: " .. tostring(functionName))
	end

	local results = table.pack(pcall(functions.CallFunction, functions, functionName, table.unpack(arguments or {})))
	if not results[1] then
		return response(false, "Function " .. functionName .. " failed: " .. tostring(results[2]))
	end

	local count = results.n - 1
	if count <= 1 then
		return response(true, nil, results[2])
	end

	return response(true, nil, { table.unpack(results, 2, results.n) })
end

function CharacterAPI:_eventRecieved(eventName, arguments)
	if not eventName then
		warn("Event received with no name:", arguments)
		return
	end

	return self.Base.Events:Dispatch(eventName, arguments)
end

-- Stimulants only queue here (through Functions, so mods can filter or replace intake); nothing reacts as they arrive.
-- Until the functions are registered the character isn't listening yet, and what arrives is dropped.
function CharacterAPI:_stimulantRecieved(messageType: TypeStimulant.MessageType, payload: any)
	local functions = self.Base.Functions
	if not functions then
		return
	end

	local functionName = if messageType == TypeStimulant.MessageTypes.Stimulant
		then FunctionEnum.ReceiveStimulant
		elseif messageType == TypeStimulant.MessageTypes.Retract then FunctionEnum.DropStimulant
		else nil
	if not functionName then
		warn("Stimulant message of unknown type received:", messageType)
		return
	end

	if not functions.MainFunctions[functionName] then
		return
	end

	local success, errorMessage = pcall(functions.CallFunction, functions, functionName, payload)
	if not success then
		warn("Stimulant", messageType, "failed:", errorMessage)
	end
end

function CharacterAPI:_init()
	self.Folder = self.Character:WaitForChild("ModNPC")
	self.Internal = self.Folder:WaitForChild("_internal")
	self.Binds = self.Internal:WaitForChild("_binds")
	self.CharacterFunction = self.Binds:WaitForChild("CharacterFunction") :: BindableFunction
	self.CharacterEvent = self.Binds:WaitForChild("CharacterEvent") :: BindableEvent
	self.CharacterStimulant = self.Binds:WaitForChild("CharacterStimulant") :: BindableEvent

	self.CharacterFunction.OnInvoke = function(functionName: string, arguments: any?)
		return self:_functionRecieved(functionName, arguments)
	end

	self.CharacterEvent.Event:Connect(function(eventName: string, arguments: any?)
		return self:_eventRecieved(eventName, arguments)
	end)

	self.CharacterStimulant.Event:Connect(function(messageType: TypeStimulant.MessageType, payload: any)
		self:_stimulantRecieved(messageType, payload)
	end)

	-- print("CharacterAPI initialized for character:", self.Character.Name)
end

return CharacterAPI
