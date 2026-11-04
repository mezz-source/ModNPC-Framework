--[[
	Puts a Layout on a dialogue BillboardGui, one TextLabel per glyph. The gui holds:

		DialogueUI (BillboardGui, sized in studs)
			Lines (Frame) + UIGridLayout, one line per row, new lines on the bottom
			_LINE_REF (Frame, hidden) > Holder > UIScale
			_LETTER_REF (TextLabel, hidden, TextScaled, anchored at its center)

	The gui is sized in studs, so its pixel size changes with distance and every letter is placed in scale of its line's
	Holder: Layout's pixels are divided by Settings.MaxWidth across and Settings.LineHeight down. MaxWidth is fitted to
	the line's shape (a 30 x 1 stud line is 30 line heights wide), so a glyph's measured width and height keep their ratio.

	A letter's box is TextSize tall and a TextSize wider than its glyph, centered on it. TextScaled then sizes every letter
	by the box height alone, so they all come out the same size, and a letter can pop or spin around its own center.
	Roblox caps TextScaled at 100px, so very close up the letters stop growing while their spacing still does.

	Lines keep the numbers Layout gave them. When the board is full, adding a line removes the oldest one, so the newest
	MaxLines lines stay on screen and the rest scroll off the top.
]]

local TypeDialogue = require(script.Parent.TypeDialogue)
local Markup = require(script.Parent.Markup)
local Layout = require(script.Parent.Layout)
local Board = {}

type Board = TypeDialogue.Board
type BoardOptions = TypeDialogue.BoardOptions
type Glyph = TypeDialogue.Glyph
type Layout = TypeDialogue.Layout
type LayoutSettings = TypeDialogue.LayoutSettings
type Parsed = TypeDialogue.Parsed

local LINES_NAME = "Lines"
local LINE_REF_NAME = "_LINE_REF"
local LETTER_REF_NAME = "_LETTER_REF"
local HOLDER_NAME = "Holder"

local DEFAULT_TEXT_SIZE = 32
local LINE_HEIGHT_SCALE = 1.25

function Board.new(gui: BillboardGui, options: BoardOptions?): Board
	local opts: BoardOptions = options or {}

	local linesFrame = gui:FindFirstChild(LINES_NAME) :: Frame?
	local lineRef = gui:FindFirstChild(LINE_REF_NAME) :: Frame?
	local letterRef = gui:FindFirstChild(LETTER_REF_NAME) :: TextLabel?
	assert(linesFrame and linesFrame:IsA("Frame"), `{gui:GetFullName()} has no {LINES_NAME} frame`)
	assert(lineRef and lineRef:IsA("Frame"), `{gui:GetFullName()} has no {LINE_REF_NAME} frame`)
	assert(letterRef and letterRef:IsA("TextLabel"), `{gui:GetFullName()} has no {LETTER_REF_NAME} label`)
	assert(lineRef:FindFirstChild(HOLDER_NAME), `{LINE_REF_NAME} has no {HOLDER_NAME}`)

	local grid = linesFrame:FindFirstChildOfClass("UIGridLayout")
	assert(grid, `{LINES_NAME} has no UIGridLayout`)

	-- One line's shape in studs, all from scale sizes
	local lineWidth = gui.Size.X.Scale * linesFrame.Size.X.Scale * grid.CellSize.X.Scale
	local lineHeight = gui.Size.Y.Scale * linesFrame.Size.Y.Scale * grid.CellSize.Y.Scale
	assert(lineWidth > 0 and lineHeight > 0, `{gui:GetFullName()} lines must be sized in scale`)

	local textSize = opts.TextSize or DEFAULT_TEXT_SIZE
	local pixelLineHeight = textSize * LINE_HEIGHT_SCALE
	local settings: LayoutSettings = table.freeze({
		Font = opts.Font or letterRef.FontFace,
		BoldFont = opts.BoldFont,
		TextSize = textSize,
		MaxWidth = pixelLineHeight * lineWidth / lineHeight,
		LineHeight = pixelLineHeight,
		Alignment = opts.Alignment or Enum.TextXAlignment.Center,
	})
	local measure = Layout.newMeasurer(settings)

	-- By line number. Lines firstLine to lastLine are on the board.
	local lines: { [number]: Frame } = {}
	local holders: { [number]: Frame } = {}
	local firstLine = 1
	local lastLine = 0
	local letters: { [number]: TextLabel } = {}
	local letterLines: { [number]: number } = {}
	local destroyed = false

	local board = {} :: Board
	board.Settings = settings
	board.MaxLines = math.floor(1 / grid.CellSize.Y.Scale + 1e-6)

	function board.Build(text: string): (Layout, Parsed)
		local parsed = Markup.parse(text)
		return Layout.build(parsed, settings, measure), parsed
	end

	function board.AddLine(): Frame
		assert(not destroyed, "Board is destroyed")
		if lastLine - firstLine + 1 >= board.MaxLines then
			board.RemoveOldestLine()
		end

		lastLine += 1
		local number = lastLine
		local line = lineRef:Clone()
		line.Name = `Line{number}`
		line.LayoutOrder = number
		line.Visible = true
		line.Parent = linesFrame

		local holder = line:FindFirstChild(HOLDER_NAME) :: Frame
		lines[number] = line
		holders[number] = holder
		return holder
	end

	function board.GetLine(line: number): Frame?
		return holders[line]
	end

	function board.RemoveOldestLine()
		if lastLine < firstLine then
			return
		end

		local number = firstLine
		firstLine += 1
		for index, letterLine in letterLines do
			if letterLine == number then
				letters[index] = nil
				letterLines[index] = nil
			end
		end

		holders[number] = nil
		local line = lines[number]
		lines[number] = nil
		line:Destroy()
	end

	function board.RestPosition(glyph: Glyph): UDim2
		return UDim2.fromScale((glyph.X + glyph.Width / 2) / settings.MaxWidth, 0.5)
	end

	function board.ScaleOffset(dx: number, dy: number): UDim2
		return UDim2.fromScale(dx / settings.MaxWidth, dy / pixelLineHeight)
	end

	function board.AddLetter(glyph: Glyph): TextLabel
		assert(not destroyed, "Board is destroyed")
		while lastLine < glyph.Line do
			board.AddLine()
		end
		local holder = holders[glyph.Line]
		assert(holder, `Line {glyph.Line} has been removed from the board`)
		board.RemoveLetter(glyph.Index)

		local letter = letterRef:Clone()
		letter.Name = `Letter{glyph.Index}`
		letter.LayoutOrder = glyph.Index
		letter.Text = glyph.Char
		letter.FontFace = Layout.fontFor(settings, glyph.Style.Bold, glyph.Style.Italic)
		letter.TextColor3 = glyph.Style.Color or letterRef.TextColor3
		letter.Position = board.RestPosition(glyph)
		letter.Size = UDim2.fromScale((glyph.Width + textSize) / settings.MaxWidth, textSize / pixelLineHeight)
		letter.Visible = true
		letter.Parent = holder

		letters[glyph.Index] = letter
		letterLines[glyph.Index] = glyph.Line
		return letter
	end

	function board.GetLetter(index: number): TextLabel?
		return letters[index]
	end

	function board.RemoveLetter(index: number)
		local letter = letters[index]
		if letter then
			letters[index] = nil
			letterLines[index] = nil
			letter:Destroy()
		end
	end

	function board.ShowAll(layout: Layout)
		board.Clear()
		for _, line in ipairs(layout.Lines) do
			for _, glyph in ipairs(line.Glyphs) do
				board.AddLetter(glyph)
			end
		end
	end

	function board.Clear()
		for _, line in lines do
			line:Destroy()
		end
		table.clear(lines)
		table.clear(holders)
		table.clear(letters)
		table.clear(letterLines)
		firstLine = 1
		lastLine = 0
	end

	function board.Destroy()
		if destroyed then
			return
		end
		board.Clear()
		destroyed = true
	end

	return board
end

return Board
