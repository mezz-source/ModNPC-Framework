--[[
	Places the cells of a parsed line on wrapped lines, one glyph per visible character, the way a font renderer moves a pen:
	every glyph sits where the pen is after the text before it, and the pen positions come from measuring that text.

		local layout = Layout.build(Markup.parse(text), {
			Font = Font.fromEnum(Enum.Font.GothamMedium),
			TextSize = 22,
			MaxWidth = 480,
		})

	A glyph's X is width(text up to and including it) - width(it alone). Measuring the whole prefix keeps the kerning between
	letters, and ending on the glyph itself means the measured text never ends in a space (a measurement can drop trailing
	whitespace). Whitespace and "\n" get no glyph; they only move the pen.

	Lines break greedily at spaces, after hyphens and at "\n". A word wider than a whole line breaks between its letters. The
	spaces where a line wraps are dropped, so no line starts with one.

	Bold and italic are the only styles that change width, so each line is measured in runs of the same weight and slant, one
	after another. The kerning between the last letter of one run and the first of the next is lost, which is too small to see.

	Measuring yields (TextService:GetTextBoundsAsync), so build before showing anything. Every measurement is cached in the
	measurer: reuse one with Layout.newMeasurer for every line spoken in the same font.
]]

local TextService = game:GetService("TextService")

local TypeDialogue = require(script.Parent.TypeDialogue)

type Cell = TypeDialogue.Cell
type Parsed = TypeDialogue.Parsed
type Glyph = TypeDialogue.Glyph
type Line = TypeDialogue.Line
type Layout = TypeDialogue.Layout
type LayoutSettings = TypeDialogue.LayoutSettings
type Measure = TypeDialogue.Measure

local Layout = {}

-- Wide enough that a measurement never wraps
local MEASURE_WIDTH = 100000
-- Added to text that ends in whitespace before measuring it, then its own width taken off again
local SENTINEL = "|"
local DEFAULT_LINE_HEIGHT_SCALE = 1.25

local ALIGNMENT_FACTOR: { [Enum.TextXAlignment]: number } = {
	[Enum.TextXAlignment.Left] = 0,
	[Enum.TextXAlignment.Center] = 0.5,
	[Enum.TextXAlignment.Right] = 1,
}

local TokenKinds = {
	Word = "Word",
	Space = "Space",
	Newline = "Newline",
}

type Token = { Kind: string, Indexes: { number } }

local function isWhitespace(char: string): boolean
	return string.find(char, "^%s+$") ~= nil
end

-- The font a glyph is drawn and measured in. Italic keeps the family and weight of the regular or bold font.
function Layout.fontFor(settings: LayoutSettings, bold: boolean, italic: boolean): Font
	local font = settings.Font
	if bold then
		font = settings.BoldFont or Font.new(font.Family, Enum.FontWeight.Bold, font.Style)
	end

	if italic then
		return Font.new(font.Family, font.Weight, Enum.FontStyle.Italic)
	end

	return font
end

-- Measures with TextService, caching every result. Safe to share between coroutines.
function Layout.newMeasurer(settings: LayoutSettings): Measure
	local fonts = {
		regular = Layout.fontFor(settings, false, false),
		bold = Layout.fontFor(settings, true, false),
		italic = Layout.fontFor(settings, false, true),
		boldItalic = Layout.fontFor(settings, true, true),
	}
	local cache: { [string]: number } = {}

	return function(text: string, bold: boolean, italic: boolean): number
		if text == "" then
			return 0
		end

		local variant = if bold then (if italic then "boldItalic" else "bold") else (if italic then "italic" else "regular")
		local key = variant .. "|" .. text
		local cached = cache[key]
		if cached then
			return cached
		end

		-- A params object per call, since GetTextBoundsAsync yields and another call could change a shared one meanwhile
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = fonts[variant]
		params.Size = settings.TextSize
		params.Width = MEASURE_WIDTH

		local width = TextService:GetTextBoundsAsync(params).X
		params:Destroy()

		cache[key] = width
		return width
	end
end

-- The width of text that may end in whitespace
local function textWidth(measure: Measure, text: string, bold: boolean, italic: boolean): number
	if string.find(text, "%s$") then
		return measure(text .. SENTINEL, bold, italic) - measure(SENTINEL, bold, italic)
	end

	return measure(text, bold, italic)
end

-- The width of some cells side by side, measured in runs of the same weight and slant
local function cellsWidth(measure: Measure, cells: { Cell }, indexes: { number }): number
	local width = 0
	local runText = ""
	local runBold = false
	local runItalic = false

	for _, index in ipairs(indexes) do
		local cell = cells[index]
		if (cell.Style.Bold ~= runBold or cell.Style.Italic ~= runItalic) and runText ~= "" then
			width += textWidth(measure, runText, runBold, runItalic)
			runText = ""
		end

		runBold = cell.Style.Bold
		runItalic = cell.Style.Italic
		runText ..= cell.Char
	end

	return width + textWidth(measure, runText, runBold, runItalic)
end

local function tokenize(cells: { Cell }): { Token }
	local tokens: { Token } = {}
	local word: { number }? = nil

	for index, cell in ipairs(cells) do
		if cell.Char == "\n" or isWhitespace(cell.Char) then
			word = nil
			table.insert(tokens, {
				Kind = if cell.Char == "\n" then TokenKinds.Newline else TokenKinds.Space,
				Indexes = { index },
			})
			continue
		end

		if not word then
			word = {}
			table.insert(tokens, { Kind = TokenKinds.Word, Indexes = word :: { number } })
		end
		table.insert(word :: { number }, index)

		-- A line can break right after a hyphen, so it ends the word
		if cell.Char == "-" then
			word = nil
		end
	end

	return tokens
end

local function concat(...: { number }): { number }
	local joined = {}
	for _, list in { ... } do
		table.move(list, 1, #list, #joined + 1, joined)
	end
	return joined
end

-- Splits the cells into lines of cell indexes
local function breakLines(measure: Measure, cells: { Cell }, maxWidth: number): { { number } }
	local lines: { { number } } = { {} }
	local pendingSpaces: { number } = {}

	local function fits(indexes: { number }): boolean
		return cellsWidth(measure, cells, indexes) <= maxWidth
	end

	local function newLine()
		table.insert(lines, {})
		pendingSpaces = {}
	end

	for _, token in ipairs(tokenize(cells)) do
		if token.Kind == TokenKinds.Newline then
			newLine()
			continue
		elseif token.Kind == TokenKinds.Space then
			table.insert(pendingSpaces, token.Indexes[1])
			continue
		end

		local current = lines[#lines]
		local candidate = concat(current, pendingSpaces, token.Indexes)

		if not fits(candidate) and #current > 0 then
			newLine()
			current = lines[#lines]
			candidate = table.clone(token.Indexes)
		end
		pendingSpaces = {}

		if fits(candidate) then
			lines[#lines] = candidate
			continue
		end

		-- Too wide even on a line of its own (the line is empty here): break it between letters
		for _, index in ipairs(candidate) do
			current = lines[#lines]
			if #current > 0 and not fits(concat(current, { index })) then
				newLine()
				current = lines[#lines]
			end
			table.insert(current, index)
		end
	end

	return lines
end

-- Places the glyphs of one line, starting at X = 0, and returns them with the line's width
local function placeLine(
	measure: Measure,
	cells: { Cell },
	indexes: { number },
	lineNumber: number
): ({ Glyph }, number)
	local glyphs: { Glyph } = {}
	local runX = 0
	local runText = ""
	local runBold = false
	local runItalic = false

	for _, index in ipairs(indexes) do
		local cell = cells[index]
		if (cell.Style.Bold ~= runBold or cell.Style.Italic ~= runItalic) and runText ~= "" then
			runX += textWidth(measure, runText, runBold, runItalic)
			runText = ""
		end

		runBold = cell.Style.Bold
		runItalic = cell.Style.Italic
		runText ..= cell.Char

		if isWhitespace(cell.Char) then
			continue
		end

		local width = measure(cell.Char, runBold, runItalic)
		table.insert(glyphs, {
			Char = cell.Char,
			Index = index,
			Line = lineNumber,
			X = runX + measure(runText, runBold, runItalic) - width,
			Width = width,
			Style = cell.Style,
		})
	end

	-- The line's width ends at its last glyph, so trailing whitespace doesn't push a centered line off center
	local last = glyphs[#glyphs]
	local lineWidth = if last then last.X + last.Width else 0

	return glyphs, lineWidth
end

function Layout.build(parsed: Parsed, settings: LayoutSettings, measure: Measure?): Layout
	local measureText = measure or Layout.newMeasurer(settings)
	local cells = parsed.Cells
	local lineHeight = settings.LineHeight or settings.TextSize * DEFAULT_LINE_HEIGHT_SCALE
	local alignment = ALIGNMENT_FACTOR[settings.Alignment or Enum.TextXAlignment.Left] or 0

	local lines: { Line } = {}
	local byIndex: { [number]: Glyph } = {}
	local glyphCount = 0

	for lineNumber, indexes in ipairs(breakLines(measureText, cells, settings.MaxWidth)) do
		local glyphs, lineWidth = placeLine(measureText, cells, indexes, lineNumber)
		local offset = (settings.MaxWidth - lineWidth) * alignment

		for _, glyph in ipairs(glyphs) do
			glyph.X += offset
			table.freeze(glyph)
			byIndex[glyph.Index] = glyph
		end

		glyphCount += #glyphs
		table.insert(lines, table.freeze({
			Glyphs = table.freeze(glyphs),
			Width = lineWidth,
		}))
	end

	return table.freeze({
		Lines = table.freeze(lines),
		ByIndex = table.freeze(byIndex),
		GlyphCount = glyphCount,
		CellCount = #cells,
		LineHeight = lineHeight,
		Height = #lines * lineHeight,
	})
end

return Layout
