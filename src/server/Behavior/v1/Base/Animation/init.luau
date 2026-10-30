local ServerScriptService = game:GetService("ServerScriptService")
local Animation = {}
Animation.__index = Animation
local AnimationHandleModule = require(script.AnimationHandle)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local AnimationEvents = TypeCharacterEvents.Names.Animation
local ContentEvents = TypeCharacterEvents.Names.Content

local TypeAnimation = require(game:GetService("ServerScriptService").ModNPCServer.Types.v1.TypeAnimation)
local TypeCDN = require(game:GetService("ServerScriptService").ModNPCServer.Types.v1.TypeCDN)
local TypeDamage = require(game:GetService("ServerScriptService").ModNPCServer.Types.v1.TypeDamage)
type AnimationHandle = TypeAnimation.AnimationHandle

local DAMAGE_CATEGORIES = TypeDamage.AnimationCategories

-- Hit reactions sit above attacks (Action) and below death (Action4). Stagger and Launch are held states, so they sit
-- above a plain flinch.
local DAMAGE_REACTIONS: { { Category: string, Priority: Enum.AnimationPriority } } = {
	{ Category = DAMAGE_CATEGORIES.Light, Priority = Enum.AnimationPriority.Action2 },
	{ Category = DAMAGE_CATEGORIES.Medium, Priority = Enum.AnimationPriority.Action2 },
	{ Category = DAMAGE_CATEGORIES.Heavy, Priority = Enum.AnimationPriority.Action2 },
	{ Category = DAMAGE_CATEGORIES.StaggerBackwards, Priority = Enum.AnimationPriority.Action2 },
	{ Category = DAMAGE_CATEGORIES.Stagger, Priority = Enum.AnimationPriority.Action3 },
	{ Category = DAMAGE_CATEGORIES.Launch, Priority = Enum.AnimationPriority.Action3 },
}

local DEFAULT_FADE_TIME = 0.25
local STUD_FACTOR = 0.8

local STEP_MARKER = "Step"
local MIN_FOOTSTEP_SPEED = 0.5
local MAX_FOOTSTEP_SPEED = 1.4
local DEFAULT_FOOTSTEP = "FOOTSTEP_PLASTIC"
-- Floor materials that don't sound like plastic; anything not listed here uses DEFAULT_FOOTSTEP
local FOOTSTEP_BY_MATERIAL: { [Enum.Material]: string } = {
	[Enum.Material.Grass] = "FOOTSTEP_GRASS",
	[Enum.Material.LeafyGrass] = "FOOTSTEP_GRASS",
	[Enum.Material.Ground] = "FOOTSTEP_GRASS",
	[Enum.Material.Metal] = "FOOTSTEP_METAL",
	[Enum.Material.DiamondPlate] = "FOOTSTEP_METAL",
	[Enum.Material.CorrodedMetal] = "FOOTSTEP_METAL",
}

function Animation.new(Base: {}, character: Model)
	local self = setmetatable({}, Animation)
	self.Base = Base
	self.Character = character
	self.Humanoid = self.Base.Humanoid
	self.CharacterAPI = self.Base.CharacterAPI
	self.Data = {}
	for categoryName, animations in pairs(self.Base.Assets:GetData().Animations) do
		for _, animation in ipairs(animations) do
			self.Data[categoryName .. "/" .. animation.Name] = animation
			if not self.Data[animation.Name] then
				self.Data[animation.Name] = animation
			end
		end
	end
	self.loadedTracks = {}
	self.handles = {}
	-- Which content source each loaded track came from, for the tracks that came from one other than the NPC
	self.trackSources = {}
	-- Current speed relative to the configured WalkSpeed, used to scale footsteps (1 = at walk speed)
	self.speedRatio = 1
	self.EventSubscriptions = {
		self.Base.Events:Subscribe(HumanoidEvents.Running, function(speed: number)
			self:_running(speed)
		end),
		self.Base.Events:Subscribe(HumanoidEvents.MoveEnded, function()
			self:_stoppedMoving()
		end),
		self.Base.Events:Subscribe(HumanoidEvents.StateChanged, function(payload)
			self:_stateChanged(payload.OldState, payload.NewState)
		end),
		self.Base.Events:Subscribe(HumanoidEvents.Landed, function()
			self:_landed()
		end),
		self.Base.Events:Subscribe(HumanoidEvents.Died, function()
			self:_died()
		end),
		self.Base.Events:Subscribe(HumanoidEvents.Jumped, function()
			self:_jumped()
		end),
		-- Tracks loaded from a weapon must not outlive its equip
		self.Base.Events:Subscribe(ContentEvents.SourceRemoved, function(payload: TypeCharacterEvents.ContentSourceRemoved)
			self:_unloadSource(payload.Source)
		end),
	}

	self.sprintSpeedScale = self.Base.Configuration:GetMovementSetting("SprintSpeed")
	self.walkSpeedScale = self.Base.Configuration:GetMovementSetting("WalkSpeed")
	table.insert(self.EventSubscriptions, self.Base.Configuration:Observe({ "Movement", "SprintSpeed" }, function(value)
		self.sprintSpeedScale = value
	end))
	table.insert(self.EventSubscriptions, self.Base.Configuration:Observe({ "Movement", "WalkSpeed" }, function(value)
		self.walkSpeedScale = value
	end))

	self:_loadBaseAnimations()

	return self
end

function Animation:_jumped()
	self:PlayAnimation("Jump", DEFAULT_FADE_TIME, nil, false)
end

function Animation:_died()
	self:UnloadAllAnimations(0)

	local deathAnim = self.Base.Assets:GetRandomAnimationFromCategory("Death")
	if not deathAnim then
		warn("Couldn't find death animation")
		return
	end

	self:LoadAnimation(deathAnim, "Death", Enum.AnimationPriority.Action, false)
	local handle = self:PlayAnimation("Death", 0, Enum.AnimationPriority.Action4, false)
	if handle then
		handle.Stopped:Connect(function()
			self.Base.Events:Dispatch(AnimationEvents.DeathFinished)
		end)
	end
end

-- We already know its above 0.1
function Animation:_running(speed: number)
	if speed >= self.sprintSpeedScale * STUD_FACTOR then
		self:PlayAnimation("Sprint", DEFAULT_FADE_TIME, nil, true)
		self:StopAnimation("Walk", DEFAULT_FADE_TIME)
		self:AdjustSpeed("Sprint", speed / self.sprintSpeedScale)
	else
		self:PlayAnimation("Walk", DEFAULT_FADE_TIME, nil, true)
		self:StopAnimation("Sprint", DEFAULT_FADE_TIME)
		self:AdjustSpeed("Walk", speed / self.walkSpeedScale)
	end
	self.speedRatio = speed / self.walkSpeedScale
end

-- Falls under 0.1
function Animation:_stoppedMoving()
	self:StopAnimation("Walk", DEFAULT_FADE_TIME)
	self:StopAnimation("Sprint", DEFAULT_FADE_TIME)
end

function Animation:_stateChanged(oldState: Enum.HumanoidStateType, newState: Enum.HumanoidStateType)
	if newState == Enum.HumanoidStateType.Freefall then
		self:PlayAnimation("Fall", DEFAULT_FADE_TIME, nil, true)
	end
end

function Animation:_landed()
	self:StopAnimation("Fall", DEFAULT_FADE_TIME)
	self:StopAnimation("Jump", DEFAULT_FADE_TIME)
end

-- TODO: config/asset loading
function Animation:_loadBaseAnimations()
	local IdleAnim = self.Base.Assets:GetAnimation("Core/Idle")
	local FallAnim = self.Base.Assets:GetAnimation("Core/Fall")
	local JumpAnim = self.Base.Assets:GetAnimation("Core/Jump")
	local WalkAnim = self.Base.Assets:GetAnimation("Core/Walk")
	local SprintAnim = self.Base.Assets:GetAnimation("Core/Sprint")

	-- note; out of any of these, the idle animation will ALWAYS be playing
	if IdleAnim then
		self:LoadAnimation(IdleAnim, "Idle", Enum.AnimationPriority.Core, true)
	end

	if FallAnim then
		self:LoadAnimation(FallAnim, "Fall", Enum.AnimationPriority.Idle, true)
	end

	if JumpAnim then
		self:LoadAnimation(JumpAnim, "Jump", Enum.AnimationPriority.Idle, false)
	end

	if WalkAnim then
		self:_listenForSteps(self:LoadAnimation(WalkAnim, "Walk", Enum.AnimationPriority.Idle, true))
	end

	if SprintAnim then
		self:_listenForSteps(self:LoadAnimation(SprintAnim, "Sprint", Enum.AnimationPriority.Idle, true))
	end

	self:PlayAnimation("Idle")
	self:_loadDamageAnimations()
end

-- Every animation of the damage categories is loaded under its own name (DamageLight1, StaggerLoop, ...); Damage picks
-- which one to play. Only the NPC's own animations are loaded, a category it doesn't have is skipped.
function Animation:_loadDamageAnimations()
	for _, reaction in ipairs(DAMAGE_REACTIONS) do
		local animations = self.Base.Assets:GetAnimationCategory(reaction.Category, self.Base.Assets.BaseSource)
		if not animations then
			continue
		end

		for _, animation in ipairs(animations) do
			-- The held part of a stagger/launch is the only one that loops
			local loop = string.find(animation.Name, "Loop$") ~= nil
			self:LoadAnimation(animation, animation.Name, reaction.Priority, loop)
		end
	end
end

-- The handle's signals are destroyed with it, so there's nothing to disconnect on unload
function Animation:_listenForSteps(handle: AnimationHandle?)
	if not handle then
		return
	end

	handle:GetMarkerReachedSignal(STEP_MARKER):Connect(function()
		self:_footstep()
	end)
end

function Animation:_footstep()
	local floorMaterial = self.Humanoid.FloorMaterial
	-- A step marker can still fire while walking off a ledge
	if floorMaterial == Enum.Material.Air then
		return
	end

	local footstep = FOOTSTEP_BY_MATERIAL[floorMaterial] or DEFAULT_FOOTSTEP
	self.Base.Functions:CallFunction(
		FunctionEnum.PlaySoundCategory,
		footstep,
		math.clamp(self.speedRatio, MIN_FOOTSTEP_SPEED, MAX_FOOTSTEP_SPEED)
	)
end

-- source is the content source the animation came from (the second value of Assets:GetAnimation). A track loaded from
-- a weapon is unloaded when the weapon is unequipped; tracks from the NPC itself stay.
function Animation:LoadAnimation(
	animationAsset: { AnimationId: string },
	animationName: string,
	priority: Enum.AnimationPriority?,
	loop: boolean?,
	source: TypeCDN.ContentSource?
): AnimationHandle?
	local animationTrack = self.CharacterAPI:LoadAnimation(animationAsset, animationName, priority, loop)
	if not animationTrack then
		warn("Failed to load animation:", animationName, "for character:", self.Character.Name)
		return nil
	end

	self.loadedTracks[animationName] = animationTrack
	self.trackSources[animationName] = if source ~= self.Base.Assets.BaseSource then source else nil
	local handle = AnimationHandleModule.new(animationTrack)
	self.handles[animationName] = handle
	return handle
end

function Animation:Play(
	animName: string,
	fadeTime: number?,
	priority: Enum.AnimationPriority?,
	loop: boolean?,
	weight: number?
): AnimationHandle?
	local loadedTrack = self.loadedTracks[animName]
	local requestedLoop = if loop == nil and loadedTrack then loadedTrack.Looped else loop
	local requestPriority = if priority == nil and loadedTrack then loadedTrack.Priority else priority
	local animationTrack = self.CharacterAPI:PlayAnimation(
		animName,
		self.loadedTracks,
		fadeTime or 0.1,
		requestPriority,
		requestedLoop,
		weight or 1
	)
	if not animationTrack then
		return nil
	end

	local handle = self.handles[animName]
	if handle and handle._track == animationTrack then
		return handle
	end
	if handle then
		handle:Destroy()
	end

	handle = AnimationHandleModule.new(animationTrack)
	self.handles[animName] = handle
	self.Base.Events:Dispatch(AnimationEvents.AnimationPlayed, {
		AnimationName = animName,
		AnimationTrack = animationTrack,
		AnimationHandle = handle,
	})

	return handle
end

function Animation:PlayAnimation(
	animName: string,
	fadeTime: number?,
	priority: Enum.AnimationPriority?,
	loop: boolean?,
	weight: number?
): AnimationHandle?
	return self:Play(animName, fadeTime, priority, loop, weight)
end

function Animation:StopAnimation(animName: string, fadeTime: number)
	self.Base.Events:Dispatch(AnimationEvents.AnimationStopped, {
		AnimationName = animName,
	})

	self.CharacterAPI:StopAnimation(animName, self.loadedTracks, fadeTime)
end

function Animation:AdjustSpeed(animName: string, speed: number)
	return self.CharacterAPI:AdjustAnimationSpeed(animName, self.loadedTracks, speed)
end

function Animation:GetAnimationHandle(animName: string): AnimationHandle?
	return self.handles[animName]
end

function Animation:GetAnimation(animName: string)
	return self.Base.Assets:GetAnimation(animName)
end

function Animation:GetAnimationCategory(categoryName: string)
	return self.Base.Assets:GetAnimationCategory(categoryName)
end

function Animation:GetAnimationId(animName: string): string?
	local animation = self:GetAnimation(animName)
	return animation and animation.AnimationId or nil
end

function Animation:UnloadAllAnimations(fadeTime: number)
	self.CharacterAPI:UnloadAllAnimations(self.loadedTracks, fadeTime)
	for animationName, handle in pairs(self.handles) do
		handle:Destroy()
		self.handles[animationName] = nil
	end
	self.loadedTracks = {}
	self.trackSources = {}
end

-- Unloads the tracks that were loaded from one content source, instantly: a weapon that is gone cannot fade out
function Animation:_unloadSource(source: TypeCDN.ContentSource)
	local tracks = {}
	for animationName, trackSource in pairs(self.trackSources) do
		if trackSource == source then
			tracks[animationName] = self.loadedTracks[animationName]
		end
	end

	if next(tracks) == nil then
		return
	end

	self.CharacterAPI:UnloadAllAnimations(tracks, 0)
	for animationName in pairs(tracks) do
		local handle = self.handles[animationName]
		if handle then
			handle:Destroy()
			self.handles[animationName] = nil
		end

		self.loadedTracks[animationName] = nil
		self.trackSources[animationName] = nil
	end
end

function Animation:Destroy()
	self:UnloadAllAnimations(0)
	self.Data = {}
end

return Animation
