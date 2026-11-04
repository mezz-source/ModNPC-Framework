--[[
	Works out when every cell of a parsed line is typed and when every event fires, in seconds from the start of typing.

		local timeline = Timeline.build(Markup.parse("Wait.<pause=1><sfx=Gasp> What?"), 30)

	A running clock starts at 0 and walks the cells in order:

		a cell              is typed at the clock, then the clock moves on 1 / (charsPerSecond * its Speed)
		<pause=S>           fires at the clock, then the clock moves on S
		any other event     fires at the clock and takes no time

	Events fire before the cell they are attached to, in the order they were written, and events at the very end fire
	after the last cell and count toward Duration. Every cell takes time, whitespace and "\n" included, and punctuation
	adds no delay of its own: a beat after a comma is a <pause>, so the timing is exactly what the markup says.

	Needs nothing from Roblox, so a presenter only has to compare its clock against these times each frame.
]]

local TypeDialogue = require(script.Parent.TypeDialogue)

type Parsed = TypeDialogue.Parsed
type Timeline = TypeDialogue.Timeline
type TimedEvent = TypeDialogue.TimedEvent

local Events = TypeDialogue.Events

local Timeline = {}

function Timeline.build(parsed: Parsed, charsPerSecond: number): Timeline
	assert(charsPerSecond > 0, "charsPerSecond must be above 0")

	local cells = parsed.Cells
	local reveal: { number } = {}
	local events: { TimedEvent } = {}
	local clock = 0
	local lastReveal = 0

	for index = 1, #cells + 1 do
		local cellEvents = parsed.Events[index]
		if cellEvents then
			for _, event in ipairs(cellEvents) do
				table.insert(events, table.freeze({ Time = clock, Index = index, Event = event }))
				if event.Kind == Events.Pause then
					clock += math.max(event.Number or 0, 0)
				end
			end
		end

		local cell = cells[index]
		if cell then
			reveal[index] = clock
			lastReveal = clock
			clock += 1 / (charsPerSecond * cell.Style.Speed)
		end
	end

	return table.freeze({
		Reveal = table.freeze(reveal),
		Events = table.freeze(events),
		LastReveal = lastReveal,
		Duration = clock,
	})
end

return Timeline
