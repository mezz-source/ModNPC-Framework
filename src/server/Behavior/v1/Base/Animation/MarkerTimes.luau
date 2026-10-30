local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

-- When each marker (animation event) of an animation happens, in animation seconds. AnimationTrack:GetTimeOfKeyframe only
-- knows named keyframes, not markers, so the times come from the animation's KeyframeSequence instead. Fetching one
-- yields, so it happens once per animation, in the background as its track is loaded; asking before it arrives (or for an
-- animation whose sequence can't be read) gives nil, and the caller falls back to something rougher.
-- Shared by every character, the same animation id always has the same markers.
local MarkerTimes = {}

-- animation id -> marker name -> its earliest time. false when the sequence could not be read, so it isn't retried.
local cache: { [string]: { [string]: number } | false } = {}
local fetching: { [string]: boolean } = {}

local function fetch(animationId: string)
	local success, sequence = pcall(KeyframeSequenceProvider.GetKeyframeSequenceAsync, KeyframeSequenceProvider, animationId)
	if not success or not sequence then
		warn("Marker times unavailable for", animationId, sequence)
		cache[animationId] = false
		return
	end

	local times = {}
	for _, keyframe in (sequence :: KeyframeSequence):GetKeyframes() do
		for _, marker in (keyframe :: Keyframe):GetMarkers() do
			local current = times[marker.Name]
			if current == nil or keyframe.Time < current then
				times[marker.Name] = (keyframe :: Keyframe).Time
			end
		end
	end

	sequence:Destroy()
	cache[animationId] = times
end

-- Starts reading an animation's marker times if nobody has yet. Never yields.
function MarkerTimes.Preload(animationId: string)
	if animationId == "" or cache[animationId] ~= nil or fetching[animationId] then
		return
	end

	fetching[animationId] = true
	task.spawn(function()
		fetch(animationId)
		fetching[animationId] = nil
	end)
end

-- The animation time of the marker, or nil while the times are still being read, can't be read, or it has no such marker.
-- Never yields.
function MarkerTimes.Get(animationId: string, markerName: string): number?
	local times = cache[animationId]
	if times == nil then
		MarkerTimes.Preload(animationId)
		return nil
	end

	if times == false then
		return nil
	end

	return times[markerName]
end

return MarkerTimes
