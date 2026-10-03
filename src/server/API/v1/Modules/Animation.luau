local ServerScriptService = game:GetService("ServerScriptService")
local TypeAnimation = require(ServerScriptService.ModNPCServer.Types.v1.TypeAnimation)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.CharacterUtility)
local Animation = {}

type AnimationInfo = TypeAnimation.AnimationInfo
type TrackList = TypeAnimation.TrackList

local function response(success: boolean, message: string?, data: any?): TypeModuleResponse.ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = success and TypeRequests.Enums.StatusCode.Success or TypeRequests.Enums.StatusCode.Conflict,
		Message = message,
		Data = data,
	}
end

local function _getAnimator(character: Model)
	local Humanoid = CharacterUtility.getHumanoid(character).Data
	if not Humanoid then
		return nil
	end
	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		local newAnimator = Instance.new("Animator")
		Animator = newAnimator
		newAnimator.Parent = Humanoid
	end
	return Animator
end

local function _getAnimTrackFromList(animName: string, tracks: TrackList): AnimationTrack?
	if not animName or not tracks then
		return nil
	end
	return tracks[animName]
end

function Animation.loadAnimation(
	character: Model,
	animationAsset: { AnimationId: string },
	animName: string,
	animInfo: AnimationInfo
): TypeModuleResponse.ModuleResponse
	local animator = _getAnimator(character)
	if not animator or typeof(animationAsset) ~= "table" or typeof(animationAsset.AnimationId) ~= "string" then
		return response(false, "Invalid character or animation asset")
	end

	local animation = Instance.new("Animation")
	animation.Name = animName
	animation.AnimationId = animationAsset.AnimationId
	local success, track: AnimationTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not success or not track then
		return response(false, "Failed to load animation: " .. animName)
	end

	track.Priority = animInfo.Priority or Enum.AnimationPriority.Action
	track.Looped = animInfo.Loop == true

	return response(true, "Animation loaded", track)
end

function Animation.loadBaseAnimations(_character: Model): TypeModuleResponse.ModuleResponse
	return response(true, "Base animations are loaded by the behavior layer")
end

function Animation.playAnimation(
	character: Model,
	animName: string,
	tracks: TrackList,
	animInfo: AnimationInfo
): TypeModuleResponse.ModuleResponse
	local track = _getAnimTrackFromList(animName, tracks)
	if not track then
		return response(false, "Animation is not loaded: " .. animName)
	end

	track.Priority = animInfo.Priority or track.Priority
	if animInfo.Loop ~= nil then
		track.Looped = animInfo.Loop
	end
	track:Play(animInfo.FadeTime or 0.1, animInfo.Weight or 1, 1)
	return response(true, "Animation playing", track)
end

function Animation.stopAnimation(
	character: Model,
	animName: string,
	tracks: TrackList,
	fadeTime: number
): TypeModuleResponse.ModuleResponse
	local track = _getAnimTrackFromList(animName, tracks)
	if not track then
		return response(false, "Animation is not loaded: " .. animName)
	end

	track:Stop(fadeTime or 0.1)
	return response(true, "Animation stopped")
end

function Animation.adjustSpeed(
	_character: Model,
	animName: string,
	tracks: TrackList,
	speed: number
): TypeModuleResponse.ModuleResponse
	local track = _getAnimTrackFromList(animName, tracks)
	if not track then
		return response(false, "Animation is not loaded: " .. animName)
	end
	if typeof(speed) ~= "number" then
		return response(false, "Animation speed must be a number")
	end

	track:AdjustSpeed(speed)
	return response(true, "Animation speed adjusted", track)
end

function Animation.unloadAllAnimations(
	_character: Model,
	tracks: TrackList,
	fadeTime: number
): TypeModuleResponse.ModuleResponse
	for _, track in pairs(tracks) do
		track:Stop(fadeTime or 0)
		track:Destroy()
	end

	return response(true, "Animations unloaded")
end

function Animation.init(_)
	print("V1 Animation initialized")
end

return Animation
