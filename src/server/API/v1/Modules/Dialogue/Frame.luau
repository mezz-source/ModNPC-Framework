--[[
	A character's dialogue frame: its DialogueUI gui with a Board and a Presenter, kept for as long as the character is,
	and a queue of lines in front of them.

		local frame = FrameClass.new(gui, adornee, { Color = ..., TalkSound = ..., TalkSpeed = 0.15 }, onDestroyed)
		local id = frame:Queue("Hello there!<pause=0.5> Who are you?")
		frame:Cancel(id)

	Lines run one at a time in the order they were queued. A line is typed, held and faded out by the Presenter, and when
	it has finished the next one starts. Cancelling a line that is running clears the board and starts the next straight
	away; cancelling one that is queued just takes it out.

	The frame is a table of closures with all its state in upvalues (see TypeDialogueFrame.Frame), so it survives the
	API's BindableFunction. It ends itself when its gui is destroyed or removed (which includes the character going).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeDialogueFrame = require(ServerScriptService.ModNPCServer.Types.v1.TypeDialogueFrame)
local Board = require(script.Parent.Board)
local Presenter = require(script.Parent.Presenter)

local FrameClass = {}

type Frame = TypeDialogueFrame.Frame
type FrameOptions = TypeDialogueFrame.FrameOptions
type LineOptions = TypeDialogueFrame.LineOptions
type SoundData = TypeCDN.SoundData

type Entry = {
	Id: number,
	Text: string,
	Options: LineOptions,
}

-- What the presenter types at when nothing says otherwise: 30 letters a second
local DEFAULT_TALK_SPEED = 1 / 30
local SOUND_NAME = "DialogueTalk"
-- Each typing blip is pitched within +/- this fraction of the talk sound's base speed (0.06 = 6%)
local BLIP_SPEED_VARIATION = 0.06

-- Seconds per letter
function FrameClass.isValidTalkSpeed(value: any): boolean
	return typeof(value) == "number" and value > 0 and value < math.huge
end

-- Same rule as the Sound API: the id is all a sound needs, the rest are optional
function FrameClass.isValidTalkSound(value: any): boolean
	if typeof(value) ~= "table" or typeof(value.SoundId) ~= "string" then
		return false
	end

	return (value.Volume == nil or typeof(value.Volume) == "number")
		and (value.PlaybackSpeed == nil or typeof(value.PlaybackSpeed) == "number")
end

-- The reason the options are no good, nil when they are fine
function FrameClass.validateLineOptions(options: any): string?
	if options == nil then
		return nil
	end
	if typeof(options) ~= "table" then
		return "options must be a table"
	end
	if options.Color ~= nil and typeof(options.Color) ~= "Color3" then
		return "Color must be a Color3"
	end
	if options.TalkSpeed ~= nil and not FrameClass.isValidTalkSpeed(options.TalkSpeed) then
		return "TalkSpeed must be a number above 0"
	end
	if options.HoldTime ~= nil and not (typeof(options.HoldTime) == "number" and options.HoldTime >= 0) then
		return "HoldTime must be a number, 0 or more"
	end

	return nil
end

-- Wraps a dialogue gui (the Board asserts it has the pieces) in the frame. The talk sound plays from the adornee.
-- onDestroyed runs once when the frame goes away, however that happens.
function FrameClass.new(gui: BillboardGui, adornee: BasePart, options: FrameOptions, onDestroyed: () -> ()): Frame
	local board = Board.new(gui)
	local letterRef = gui:FindFirstChild("_LETTER_REF") :: TextLabel

	local destroyed = false
	local color = options.Color or letterRef.TextColor3
	local talkSpeed = options.TalkSpeed or DEFAULT_TALK_SPEED
	local sound: Sound? = nil
	local baseBlipSpeed = 1
	local connections: { RBXScriptConnection } = {}

	-- The running line, and the ones waiting for it
	local current: Entry? = nil
	local queue: { Entry } = {}
	local lastId = 0

	local startNext: () -> ()

	local function setSound(talkSound: SoundData?)
		if sound then
			sound:Destroy()
			sound = nil
		end
		if not talkSound then
			return
		end

		local newSound = Instance.new("Sound")
		newSound.Name = SOUND_NAME
		newSound.SoundId = talkSound.SoundId
		newSound.RollOffMaxDistance = 50
		if talkSound.Volume ~= nil then
			newSound.Volume = talkSound.Volume
		end
		if talkSound.PlaybackSpeed ~= nil then
			newSound.PlaybackSpeed = talkSound.PlaybackSpeed
		end
		baseBlipSpeed = newSound.PlaybackSpeed
		newSound.Parent = adornee
		sound = newSound
	end

	-- Typing faster than the sound is long restarts it, so every letter is heard. Each blip is pitched slightly
	-- differently around the base speed so a line doesn't sound like a repeated sample.
	local function blip()
		local talkSound = sound
		if destroyed or not talkSound then
			return
		end
		talkSound.PlaybackSpeed = baseBlipSpeed * (1 + (math.random() * 2 - 1) * BLIP_SPEED_VARIATION)
		if talkSound.IsPlaying then
			talkSound.TimePosition = 0
		end
		talkSound:Play()
	end

	local presenter = Presenter.new(board, {
		OnEvent = options.OnEvent,
		OnBlip = blip,
		OnFinished = function()
			if destroyed then
				return
			end
			current = nil
			startNext()
		end,
	})

	-- Presenting yields while the text is measured, so it runs in a thread of its own and Queue never waits for it
	local function run(entry: Entry)
		local lineOptions = entry.Options
		local presented, problem = pcall(presenter.Present, entry.Text, {
			CharsPerSecond = 1 / (lineOptions.TalkSpeed or talkSpeed),
			HoldTime = lineOptions.HoldTime,
			Color = lineOptions.Color or color,
		})
		-- A line that can't be shown must not hold up the ones behind it
		if not presented then
			warn("Dialogue line", entry.Id, "failed:", problem)
			if current == entry and not destroyed then
				current = nil
				startNext()
			end
		end
	end

	startNext = function()
		local entry = table.remove(queue, 1)
		current = entry
		if entry then
			task.spawn(run, entry)
		end
	end

	-- A cancelled line never reports finishing, so the next one is started here. A Present still measuring when it is
	-- cancelled gives up by itself.
	local function cancelCurrent(): boolean
		if not current then
			return false
		end

		current = nil
		presenter.Cancel()
		startNext()
		return true
	end

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true

		table.clear(queue)
		current = nil
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)

		presenter.Destroy()
		board.Destroy()
		setSound(nil)
		gui:Destroy()
		onDestroyed()
	end

	local frame: Frame = {
		Queue = function(_self: Frame, text: string, lineOptions: LineOptions?): number
			if destroyed then
				return 0
			end
			if typeof(text) ~= "string" or text == "" then
				warn("Dialogue frame ignoring line that is not a non-empty string:", text)
				return 0
			end
			local invalidReason = FrameClass.validateLineOptions(lineOptions)
			if invalidReason then
				warn("Dialogue frame ignoring line with invalid options:", invalidReason)
				return 0
			end

			lastId += 1
			local entry: Entry = {
				Id = lastId,
				Text = text,
				Options = if lineOptions then table.clone(lineOptions) else {},
			}
			table.insert(queue, entry)
			if current == nil then
				startNext()
			end

			return entry.Id
		end,

		Cancel = function(_self: Frame, id: number): boolean
			if destroyed or typeof(id) ~= "number" then
				return false
			end
			if current and current.Id == id then
				return cancelCurrent()
			end

			for index, entry in queue do
				if entry.Id == id then
					table.remove(queue, index)
					return true
				end
			end

			return false
		end,

		CancelCurrent = function(_self: Frame): boolean
			if destroyed then
				return false
			end

			return cancelCurrent()
		end,

		CancelAll = function(_self: Frame)
			if destroyed then
				return
			end

			table.clear(queue)
			current = nil
			presenter.Cancel()
		end,

		IsSpeaking = function(_self: Frame): boolean
			return current ~= nil
		end,

		IsTyping = function(_self: Frame): boolean
			return current ~= nil and presenter.IsTyping()
		end,

		GetCurrentLine = function(_self: Frame): number?
			return if current then current.Id else nil
		end,

		GetQueueLength = function(_self: Frame): number
			return #queue
		end,

		SetColor = function(_self: Frame, newColor: Color3)
			if destroyed then
				return
			end
			if typeof(newColor) ~= "Color3" then
				warn("Dialogue frame ignoring invalid color:", newColor)
				return
			end

			color = newColor
		end,

		GetColor = function(_self: Frame): Color3
			return color
		end,

		SetTalkSpeed = function(_self: Frame, secondsPerLetter: number)
			if destroyed then
				return
			end
			if not FrameClass.isValidTalkSpeed(secondsPerLetter) then
				warn("Dialogue frame ignoring invalid talk speed (must be above 0):", secondsPerLetter)
				return
			end

			talkSpeed = secondsPerLetter
		end,

		GetTalkSpeed = function(_self: Frame): number
			return talkSpeed
		end,

		SetTalkSound = function(_self: Frame, talkSound: SoundData?)
			if destroyed then
				return
			end
			if talkSound ~= nil and not FrameClass.isValidTalkSound(talkSound) then
				warn("Dialogue frame ignoring invalid talk sound (needs a SoundId):", talkSound)
				return
			end

			setSound(talkSound)
		end,

		IsDestroyed = function(_self: Frame): boolean
			return destroyed
		end,

		Destroy = function(_self: Frame)
			destroy()
		end,
	}

	-- the gui being destroyed (it or its character) or taken out of its parent ends the frame
	table.insert(connections, gui.Destroying:Connect(destroy))
	table.insert(
		connections,
		gui.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				destroy()
			end
		end)
	)

	setSound(options.TalkSound)

	return frame
end

return FrameClass
