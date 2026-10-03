local ServerScriptService = game:GetService("ServerScriptService")
local Animation = {}
Animation.__index = Animation
local AnimationHandleModule = require(script.AnimationHandle)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local HumanoidEvents = TypeCharacterEvents.Names.Humanoid
local AnimationEvents = TypeCharacterEvents.Names.Animation

local TypeAnimation = require(game:GetService("ServerScriptService").ModNPCServer.Types.v1.TypeAnimation)
type AnimationHandle = TypeAnimation.AnimationHandle

local DEFAULT_FADE_TIME = 0.25
local STUD_FACTOR = 0.8

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
	}

	self.sprintSpeedScale = self.Base.Configuration:GetMovementSetting("SprintSpeed")
	self.walkSpeedScale = self.Base.Configuration:GetMovementSetting("WalkSpeed")

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
	local ClimbAnim = self.Base.Assets:GetAnimation("Core/Climb")

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
		self:LoadAnimation(WalkAnim, "Walk", Enum.AnimationPriority.Idle, true)
	end

	if SprintAnim then
		self:LoadAnimation(SprintAnim, "Sprint", Enum.AnimationPriority.Idle, true)
	end

	if ClimbAnim then
		self:LoadAnimation(ClimbAnim, "Climb", Enum.AnimationPriority.Idle, true)
	end

	self:PlayAnimation("Idle")
end

function Animation:LoadAnimation(
	animationAsset: { AnimationId: string },
	animationName: string,
	priority: Enum.AnimationPriority?,
	loop: boolean?
): AnimationHandle?
	local animationTrack = self.CharacterAPI:LoadAnimation(animationAsset, animationName, priority, loop)
	if not animationTrack then
		warn("Failed to load animation:", animationName, "for character:", self.Character.Name)
		return nil
	end

	self.loadedTracks[animationName] = animationTrack
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
end

function Animation:Destroy()
	self:UnloadAllAnimations(0)
	self.Data = {}
end

return Animation
