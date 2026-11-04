local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Signal = require(ServerScriptService.ModNPCServer.Util.Signal)

-- The one RunService.Heartbeat connection of a character. Base owns it and everything else that updates every frame (the
-- scheduler, the thought process, stamina, mod scripts...) listens here instead of connecting to RunService itself, so there
-- is a single place to start, pause or stop the character's frame updates.
--
-- The thought process is the other source of updates: its reaction ticks are the Thought.ReactionUpdate event. Heartbeat is
-- the frame clock, ReactionUpdate is the character's own pace.
local Heartbeat = {}
Heartbeat.__index = Heartbeat

function Heartbeat.new()
	local self = setmetatable({}, Heartbeat)
	self.Signal = Signal.new()
	-- Paused frames are skipped, not saved up: listeners hear nothing meanwhile and pick up with the next frame's deltaTime
	self.paused = false
	self.connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.paused then
			self.Signal:Fire(deltaTime)
		end
	end) :: RBXScriptConnection?

	return self
end

-- Holds back (or lets through again) every frame update. Base pauses it while Permissions/CanThink is off.
function Heartbeat:SetPaused(paused: boolean)
	self.paused = paused
end

function Heartbeat:IsPaused(): boolean
	return self.paused
end

-- Calls callback(deltaTime) every frame until the returned connection is disconnected (or the character is done with
-- its frame updates, see Destroy). Handlers run isolated from each other: one that errors doesn't stop the rest.
function Heartbeat:Connect(callback: (deltaTime: number) -> ())
	return self.Signal:Connect(callback)
end

-- Ends the frame updates for good: nothing connected here is called again. Connections held by listeners stay safe to
-- disconnect.
function Heartbeat:Destroy()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	self.Signal:DisconnectAll()
end

return Heartbeat
