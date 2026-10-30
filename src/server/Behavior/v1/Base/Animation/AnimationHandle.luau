local ServerScriptService = game:GetService("ServerScriptService")
local Signal = require(ServerScriptService.ModNPCServer.Util.Signal)
local MarkerTimes = require(script.Parent.MarkerTimes)
local MarkerTranslator = require(script.Parent.MarkerTranslator)

local AnimationHandle = {}
AnimationHandle.__index = AnimationHandle

local function forwardSignal(trackSignal: RBXScriptSignal, signal)
	return trackSignal:Connect(function(...)
		signal:Fire(...)
	end)
end

function AnimationHandle.new(track: AnimationTrack)
	local self = setmetatable({
		_track = track,
		_connections = {},
		_markerSignals = {},
		Stopped = Signal.new(),
		Ended = Signal.new(),
		DidLoop = Signal.new(),
		Looped = nil,
		KeyframeReached = Signal.new(),
	}, AnimationHandle)
	self.Looped = self.DidLoop

	table.insert(self._connections, forwardSignal(track.Stopped, self.Stopped))
	table.insert(self._connections, forwardSignal(track.Ended, self.Ended))
	table.insert(self._connections, forwardSignal(track.DidLoop, self.DidLoop))
	table.insert(self._connections, forwardSignal(track.KeyframeReached, self.KeyframeReached))

	-- so the marker times are known by the time anyone asks (see GetTimeUntilMarker)
	MarkerTimes.Preload(track.Animation.AnimationId)

	return self
end

-- Seconds the animation lasts at normal speed, 0 until it has loaded
function AnimationHandle:GetLength(): number
	return self._track.Length
end

-- When the marker happens, in animation seconds (at normal speed from the start). Nil while that isn't known yet, see
-- MarkerTimes.
function AnimationHandle:GetMarkerTime(markerName: string): number?
	return MarkerTimes.Get(self._track.Animation.AnimationId, MarkerTranslator.ToEventName(markerName))
end

-- Real seconds from now until the playhead reaches a point in the animation, at the speed it is playing at. Nil when it
-- isn't moving towards it (stopped, paused, or already past).
function AnimationHandle:GetTimeUntil(animationTime: number): number?
	local track = self._track
	local speed = track.Speed
	if not track.IsPlaying or speed <= 0 then
		return nil
	end

	local remaining = animationTime - track.TimePosition
	if remaining < 0 then
		return nil
	end

	return remaining / speed
end

-- Real seconds from now until the marker is reached. Nil if its time isn't known or it won't be reached.
function AnimationHandle:GetTimeUntilMarker(markerName: string): number?
	local markerTime = self:GetMarkerTime(markerName)
	if not markerTime then
		return nil
	end

	return self:GetTimeUntil(markerTime)
end

-- Real seconds from now until the animation reaches its end at the speed it is playing at, nil when it won't
function AnimationHandle:GetTimeRemaining(): number?
	return self:GetTimeUntil(self._track.Length)
end

function AnimationHandle:GetMarkerReachedSignal(markerName: string)
	local eventName = MarkerTranslator.ToEventName(markerName)
	local signal = self._markerSignals[eventName]
	if signal then
		return signal
	end

	signal = Signal.new()
	self._markerSignals[eventName] = signal
	table.insert(self._connections, forwardSignal(self._track:GetMarkerReachedSignal(eventName), signal))
	return signal
end

function AnimationHandle:WaitForMarker(markerName: string)
	return self:GetMarkerReachedSignal(markerName):Wait()
end

function AnimationHandle:Stop(fadeTime: number?)
	self._track:Stop(fadeTime or 0)
end

function AnimationHandle:AdjustSpeed(speed: number)
	self._track:AdjustSpeed(speed)
end

function AnimationHandle:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	self.Stopped:Destroy()
	self.Ended:Destroy()
	self.DidLoop:Destroy()
	self.KeyframeReached:Destroy()
	for _, signal in pairs(self._markerSignals) do
		signal:Destroy()
	end
	self._markerSignals = {}
	self._track = nil
end

return AnimationHandle
