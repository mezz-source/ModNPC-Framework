local ServerScriptService = game:GetService("ServerScriptService")
local Signal = require(ServerScriptService.ModNPCServer.Util.Signal)
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

	return self
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
