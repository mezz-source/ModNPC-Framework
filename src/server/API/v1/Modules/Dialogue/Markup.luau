--[[
	Turns a dialogue line with tags into the characters to show, each with its style, and the events to fire while typing.

		Markup.parse("I <shake>can't</shake> believe<pause=0.5> it.")

	Span tags, closed by </tag>:
		<shake> <shake=2>    per letter shake, with an optional intensity
		<wave> <wave=2>      per letter wave, with an optional intensity
		<color=#ff4040>      text color, as hex
		<color=default>      back to the character's own text color, inside another <color>
		<b>                  bold
		<i>                  italic
		<speed=2>            types this part 2x as fast (0.5 for half speed)

	Instant tags, no closing tag:
		<pause=0.5>          wait 0.5 seconds before typing on
		<sfx=Name>           play a sound by name
		<event=Name>         fire a named dialogue event for scripts to react to
		<anim=Name>          play an animation of the character by name
		<stopanim=Name>      stop an animation of the character by name

	"\<" types a literal "<" and "\\" a literal "\". Anything that isn't a tag the parser can apply (an unknown name, a bad
	argument, a </tag> with nothing open) is kept as plain text, so a broken tag shows up on screen instead of vanishing.
	Tags that close out of order are fine (<b><shake></b></shake>), and anything still open at the end runs to the end.
]]

local TypeDialogue = require(script.Parent.TypeDialogue)

type Style = TypeDialogue.Style
type Cell = TypeDialogue.Cell
type Event = TypeDialogue.Event
type Parsed = TypeDialogue.Parsed

local Effects = TypeDialogue.Effects
local Events = TypeDialogue.Events

local Markup = {}

-- A style while it is being built from the open tags, before it is frozen
type Draft = {
	Color: Color3?,
	Effects: { [string]: number },
	Bold: boolean,
	Italic: boolean,
	Speed: number,
}
type Apply = (draft: Draft) -> ()
type OpenTag = { Name: string, Apply: Apply }

local DEFAULT_COLOR_ARG = "default"

local DEFAULT_STYLE: Style = table.freeze({
	Color = nil,
	Effects = table.freeze({}),
	Bold = false,
	Italic = false,
	Speed = 1,
})

local function effectTag(name: string): (arg: string) -> Apply?
	return function(arg: string): Apply?
		local intensity = if arg == "" then 1 else tonumber(arg)
		if not intensity then
			return nil
		end

		return function(draft: Draft)
			draft.Effects[name] = intensity
		end
	end
end

-- Each takes the tag's argument ("" when there is none) and returns how it changes the style, or nil when the argument is bad
local SPAN_TAGS: { [string]: (arg: string) -> Apply? } = {
	[Effects.Shake] = effectTag(Effects.Shake),
	[Effects.Wave] = effectTag(Effects.Wave),

	color = function(arg: string): Apply?
		-- Clears any color set by a tag opened before it, so the text falls back to the presenter's default
		if string.lower(arg) == DEFAULT_COLOR_ARG then
			return function(draft: Draft)
				draft.Color = nil
			end
		end

		local ok, color = pcall(Color3.fromHex, arg)
		if arg == "" or not ok then
			return nil
		end

		return function(draft: Draft)
			draft.Color = color
		end
	end,

	b = function(arg: string): Apply?
		if arg ~= "" then
			return nil
		end

		return function(draft: Draft)
			draft.Bold = true
		end
	end,

	i = function(arg: string): Apply?
		if arg ~= "" then
			return nil
		end

		return function(draft: Draft)
			draft.Italic = true
		end
	end,

	speed = function(arg: string): Apply?
		local speed = tonumber(arg)
		if not speed or speed <= 0 then
			return nil
		end

		return function(draft: Draft)
			draft.Speed = speed
		end
	end,
}

-- Each says whether the argument is one the event can use
local INSTANT_TAGS: { [string]: (arg: string) -> boolean } = {
	[Events.Pause] = function(arg: string): boolean
		local seconds = tonumber(arg)
		return seconds ~= nil and seconds >= 0
	end,

	[Events.Sfx] = function(arg: string): boolean
		return arg ~= ""
	end,

	[Events.Event] = function(arg: string): boolean
		return arg ~= ""
	end,

	[Events.PlayAnimation] = function(arg: string): boolean
		return arg ~= ""
	end,

	[Events.StopAnimation] = function(arg: string): boolean
		return arg ~= ""
	end,
}

-- Applies the open tags in the order they were opened, so a later tag wins over an earlier one of the same kind
local function buildStyle(openTags: { OpenTag }): Style
	if #openTags == 0 then
		return DEFAULT_STYLE
	end

	local draft: Draft = {
		Color = nil,
		Effects = {},
		Bold = false,
		Italic = false,
		Speed = 1,
	}

	for _, openTag in ipairs(openTags) do
		openTag.Apply(draft)
	end

	table.freeze(draft.Effects)
	return table.freeze(draft) :: Style
end

-- The last byte of the grapheme that starts at `first`, so "é" or an emoji stays one cell instead of splitting into bytes
local function graphemeEnd(source: string, first: number): number
	for _, last in utf8.graphemes(source, first) do
		return last
	end

	return first
end

function Markup.parse(source: string): Parsed
	local cells: { Cell } = {}
	local events: { [number]: { Event } } = {}
	local openTags: { OpenTag } = {}
	local style = DEFAULT_STYLE

	local function addCell(char: string)
		table.insert(cells, table.freeze({ Char = char, Style = style }))
	end

	-- Returns whether the tag was applied; when it wasn't, its text is typed as is
	local function applyTag(closing: boolean, name: string, arg: string, hasArg: boolean): boolean
		if closing then
			if hasArg then
				return false
			end

			for index = #openTags, 1, -1 do
				if openTags[index].Name == name then
					table.remove(openTags, index)
					style = buildStyle(openTags)
					return true
				end
			end

			return false
		end

		local isValidEvent = INSTANT_TAGS[name]
		if isValidEvent then
			if not isValidEvent(arg) then
				return false
			end

			local cellIndex = #cells + 1
			local cellEvents = events[cellIndex]
			if not cellEvents then
				cellEvents = {}
				events[cellIndex] = cellEvents
			end

			table.insert(cellEvents, table.freeze({
				Kind = name,
				Arg = if arg ~= "" then arg else nil,
				Number = tonumber(arg),
			}))
			return true
		end

		local parseSpan = SPAN_TAGS[name]
		local apply = parseSpan and parseSpan(arg)
		if not apply then
			return false
		end

		table.insert(openTags, { Name = name, Apply = apply })
		style = buildStyle(openTags)
		return true
	end

	local i = 1
	while i <= #source do
		local byte = string.sub(source, i, i)

		if byte == "\\" then
			local escaped = string.sub(source, i + 1, i + 1)
			if escaped == "<" or escaped == "\\" then
				addCell(escaped)
				i += 2
				continue
			end
		elseif byte == "<" then
			local closing, name, after = string.match(source, "^<(/?)(%a+)>()", i)
			local arg = ""
			local hasArg = false
			if not name then
				closing, name, arg, after = string.match(source, "^<(/?)(%a+)=([^<>]*)>()", i)
				hasArg = true
			end

			if name and applyTag(closing == "/", string.lower(name), arg, hasArg) then
				i = after
				continue
			end
		elseif byte == "\r" then
			i += 1
			continue
		end

		local last = graphemeEnd(source, i)
		addCell(string.sub(source, i, last))
		i = last + 1
	end

	for _, cellEvents in events do
		table.freeze(cellEvents)
	end

	return table.freeze({
		Cells = table.freeze(cells),
		Events = table.freeze(events),
	})
end

return Markup
