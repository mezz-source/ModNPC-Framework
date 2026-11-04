--[[
	Types a dialogue payload onto a Board, letter by letter, and keeps it there.

		local presenter = Presenter.new(Board.new(gui), {
			OnEvent = function(event) ... end,   -- <sfx>, <event>, <anim>, <stopanim>
			OnBlip = function(glyph) ... end,     -- a letter was typed
		})
		presenter.Present("You almost had me!<pause=0.5>\nWell,<pause=0.3> not really.")

	A payload is one string with its markup; "\n" and wrapping split it into lines. Nothing is hidden while it runs. Its
	lines leave the board only when the oldest scrolls off the top of a full board, when it is cancelled, or when a new
	payload replaces it. Once it has been fully typed it stays for HoldTime, fades out over FadeOutTime and is cleared.

	The text is laid out and timed once, up front, so a letter's spot is fixed before typing starts and text never jumps.
	After that one Heartbeat loop reads the clock each frame, and everything on the board is worked out from that time:
	which letters are typed, how far they have faded in, where their effects put them. Nothing builds up frame to frame,
	so a slow frame just shows the payload further along. The only things that move forward on their own are two cursors
	(the next cell to type and the next event to fire), which catch up on everything that came due since the last frame,
	so nothing is skipped and nothing fires twice.
]]

local RunService = game:GetService("RunService")

local TypeDialogue = require(script.Parent.TypeDialogue)
local Timeline = require(script.Parent.Timeline)
local Effects = require(script.Parent.Effects)

type Board = TypeDialogue.Board
type Glyph = TypeDialogue.Glyph
type Presenter = TypeDialogue.Presenter
type PresenterOptions = TypeDialogue.PresenterOptions

local Events = TypeDialogue.Events

local Presenter = {}

local DEFAULT_CHARS_PER_SECOND = 30
local DEFAULT_HOLD_TIME = 5
local DEFAULT_FADE_OUT_TIME = 0.5

-- A typed letter and how it looked when it was cloned, so fades scale its own transparencies
type Shown = {
	Glyph: Glyph,
	Label: TextLabel,
	Rest: UDim2,
	Transparency: number,
	StrokeTransparency: number,
}

-- Letters and digits blip; spaces and punctuation don't. Any multi-byte character counts as a letter.
local function isBlipLetter(char: string): boolean
	return string.find(char, "^[%w\128-\255]") ~= nil
end

local function opaque(transparency: number, opacity: number): number
	return 1 - (1 - transparency) * opacity
end

function Presenter.new(board: Board, options: PresenterOptions?): Presenter
	local opts: PresenterOptions = options or {}
	local charsPerSecond = opts.CharsPerSecond or DEFAULT_CHARS_PER_SECOND
	local holdTime = opts.HoldTime or DEFAULT_HOLD_TIME
	local fadeOutTime = opts.FadeOutTime or DEFAULT_FADE_OUT_TIME
	local onEvent = opts.OnEvent
	local onBlip = opts.OnBlip
	local textSize = board.Settings.TextSize

	-- Goes up on every stop, so a Present still measuring when it is replaced knows to give up
	local generation = 0
	local connection: RBXScriptConnection? = nil
	local presenting = false
	local destroyed = false

	local function stop()
		generation += 1
		if connection then
			connection:Disconnect()
			connection = nil
		end
		presenting = false
		board.Clear()
	end

	local presenter = {} :: Presenter

	function presenter.Present(text: string)
		assert(not destroyed, "Presenter is destroyed")
		stop()
		presenting = true
		local thisGeneration = generation

		local layout, parsed = board.Build(text)
		if generation ~= thisGeneration then
			return
		end

		local timeline = Timeline.build(parsed, charsPerSecond)
		local typedAt = math.max(timeline.Duration, timeline.LastReveal + Effects.FadeInTime)
		local fadeOutAt = typedAt + holdTime

		local shown: { Shown } = {}
		local nextCell = 1
		local nextEvent = 1
		local startTime = os.clock()

		connection = RunService.Heartbeat:Connect(function()
			local time = os.clock() - startTime

			while nextEvent <= #timeline.Events and timeline.Events[nextEvent].Time <= time do
				local event = timeline.Events[nextEvent].Event
				nextEvent += 1
				if onEvent and event.Kind ~= Events.Pause then
					task.spawn(onEvent, event)
				end
			end

			local blip: Glyph? = nil
			while nextCell <= layout.CellCount and timeline.Reveal[nextCell] <= time do
				local glyph = layout.ByIndex[nextCell]
				nextCell += 1
				if not glyph then
					continue
				end

				local label = board.AddLetter(glyph)
				table.insert(shown, {
					Glyph = glyph,
					Label = label,
					Rest = label.Position,
					Transparency = label.TextTransparency,
					StrokeTransparency = label.TextStrokeTransparency,
				})
				if isBlipLetter(glyph.Char) then
					blip = glyph
				end
			end

			if blip and onBlip then
				task.spawn(onBlip, blip)
			end

			local fade = 1
			if time >= fadeOutAt then
				fade = if fadeOutTime > 0 then 1 - (time - fadeOutAt) / fadeOutTime else 0
				if fade <= 0 then
					stop()
					return
				end
			end

			for index = #shown, 1, -1 do
				local letter = shown[index]
				-- Its line scrolled off the top of the board
				if letter.Label.Parent == nil then
					table.remove(shown, index)
					continue
				end

				local glyph = letter.Glyph
				local opacity, rise = Effects.reveal(time - timeline.Reveal[glyph.Index], textSize)
				local dx, dy = Effects.offset(glyph, time, textSize)
				opacity *= fade

				letter.Label.Position = letter.Rest + board.ScaleOffset(dx, dy + rise)
				letter.Label.TextTransparency = opaque(letter.Transparency, opacity)
				letter.Label.TextStrokeTransparency = opaque(letter.StrokeTransparency, opacity)
			end
		end)
	end

	function presenter.Cancel()
		stop()
	end

	function presenter.IsPresenting(): boolean
		return presenting
	end

	function presenter.Destroy()
		if destroyed then
			return
		end
		stop()
		destroyed = true
	end

	return presenter
end

return Presenter
