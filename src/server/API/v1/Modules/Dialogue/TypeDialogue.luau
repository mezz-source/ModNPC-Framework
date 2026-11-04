local TypeDialogue = {}

-- How one character of a line looks. Styles are frozen and shared: consecutive characters under the same tags hold the same
-- table, so a change of style between two characters is just `a.Style ~= b.Style`.
export type Style = {
	-- Text color, nil for the presenter's default
	Color: Color3?,
	-- Per letter animations by name (see TypeDialogue.Effects), each with its intensity (1 unless the tag gave one)
	Effects: { [string]: number },
	-- Bold and Italic are the only settings that change how wide a character is, so the only ones Layout reads
	Bold: boolean,
	Italic: boolean,
	-- Multiplies the typing speed while these characters are typed
	Speed: number,
}

-- One character of the text, with the tags around it already applied. Whitespace and "\n" are cells too: they take up
-- room (or break the line) but get no glyph.
export type Cell = {
	Char: string,
	Style: Style,
}

-- Something that happens once, right before the cell it is attached to is typed
export type Event = {
	Kind: string,
	-- The raw text after "=" in the tag ("0.5" in <pause=0.5>), and the same as a number when it is one
	Arg: string?,
	Number: number?,
}

export type Parsed = {
	Cells: { Cell },
	-- Keyed by the index of the cell the event fires before. An event at the very end of the text is keyed #Cells + 1.
	Events: { [number]: { Event } },
}

-- A visible character placed on its line. X is the left edge in pixels from the left of the line, already aligned.
export type Glyph = {
	Char: string,
	-- The index of its cell in Parsed.Cells, which is also where its Events are and the order it is typed in
	Index: number,
	Line: number,
	X: number,
	Width: number,
	Style: Style,
}

export type Line = {
	Glyphs: { Glyph },
	-- From X = 0 to the right edge of its last glyph, so trailing whitespace doesn't count
	Width: number,
}

export type Layout = {
	Lines: { Line },
	-- Every glyph by its cell index; whitespace cells have none
	ByIndex: { [number]: Glyph },
	GlyphCount: number,
	-- #Parsed.Cells, so a presenter can walk every cell (and its events) in order
	CellCount: number,
	LineHeight: number,
	-- #Lines * LineHeight
	Height: number,
}

export type LayoutSettings = {
	Font: Font,
	-- Defaults to Font at Enum.FontWeight.Bold
	BoldFont: Font?,
	TextSize: number,
	-- Lines wrap at this many pixels
	MaxWidth: number,
	-- Defaults to TextSize * 1.25
	LineHeight: number?,
	-- Left, Center or Right. Defaults to Left.
	Alignment: Enum.TextXAlignment?,
}

-- Width in pixels of text on one line, in the regular, bold, italic or bold italic font
export type Measure = (text: string, bold: boolean, italic: boolean) -> number

export type BoardOptions = {
	-- Defaults to the letter ref's FontFace
	Font: Font?,
	BoldFont: Font?,
	-- Only the resolution text is measured at; the board scales with the gui, so this doesn't change how big letters look.
	-- Defaults to 32.
	TextSize: number?,
	-- Defaults to Center
	Alignment: Enum.TextXAlignment?,
}

-- Lines and letters cloned into a dialogue BillboardGui from its _LINE_REF and _LETTER_REF
export type Board = {
	-- Fitted to the gui's line shape; pass to Layout.build (Build does)
	Settings: LayoutSettings,
	-- How many lines fit; adding one more removes the oldest
	MaxLines: number,
	-- Parses and lays out the text for this board
	Build: (text: string) -> (Layout, Parsed),
	-- Clones a line onto the bottom (removing the oldest when the board is full) and returns its Holder, where its
	-- letters go. Lines are numbered as Layout numbers them, so line 12 stays line 12 after line 1 is removed.
	AddLine: () -> Frame,
	GetLine: (line: number) -> Frame?,
	-- Removes the oldest line and its letters
	RemoveOldestLine: () -> (),
	-- Clones a letter for the glyph onto its line (adding lines up to it), replacing any letter already at its index.
	-- The glyph's line must not have been removed.
	AddLetter: (glyph: Glyph) -> TextLabel,
	GetLetter: (index: number) -> TextLabel?,
	RemoveLetter: (index: number) -> (),
	-- Where a glyph's letter sits at rest, in scale of its line's Holder
	RestPosition: (glyph: Glyph) -> UDim2,
	-- A Layout pixel offset in scale of a line's Holder, to add to a rest position
	ScaleOffset: (dx: number, dy: number) -> UDim2,
	-- Clears the board, then adds a letter for every glyph
	ShowAll: (layout: Layout) -> (),
	-- Removes every line and letter
	Clear: () -> (),
	Destroy: () -> (),
}

-- An event with the time it fires, in seconds from the start of typing
export type TimedEvent = {
	Time: number,
	-- The cell it fires before (#Cells + 1 for one at the very end)
	Index: number,
	Event: Event,
}

-- When everything in a parsed line happens, in seconds from the start of typing
export type Timeline = {
	-- The time each cell is typed, by cell index. Always goes up (or stays), so a cell is typed once all before it are.
	Reveal: { number },
	-- In the order they fire
	Events: { TimedEvent },
	-- When the last cell is typed, 0 when there are none
	LastReveal: number,
	-- When typing is over: after the last cell's own time and any events at the end
	Duration: number,
}

export type PresenterOptions = {
	-- Base typing speed, before <speed>. Defaults to 30.
	CharsPerSecond: number?,
	-- Seconds the finished text stays before fading out. Defaults to 5.
	HoldTime: number?,
	-- Seconds the fade out takes. Defaults to 0.5.
	FadeOutTime: number?,
	-- Every event but <pause> (which only moves the timing) as it fires. Runs in its own thread, so it may yield.
	OnEvent: ((event: Event) -> ())?,
	-- A letter or digit was typed, at most once a frame. Runs in its own thread, so it may yield.
	OnBlip: ((glyph: Glyph) -> ())?,
}

-- Types text onto a Board and keeps it there until it is finished (then holds and fades out), cancelled, or replaced
export type Presenter = {
	-- Shows the text in full, replacing anything presented before. Yields while the text is measured.
	Present: (text: string) -> (),
	-- Clears the board straight away
	Cancel: () -> (),
	-- True from Present until the text has faded out or been cancelled
	IsPresenting: () -> boolean,
	-- Cancels and stops presenting for good. The board is left to its owner.
	Destroy: () -> (),
}

-- Span tags style what's between <tag> and </tag>; instant tags are a single <tag=arg> that becomes an Event
TypeDialogue.TagKinds = table.freeze({
	Span = "Span",
	Instant = "Instant",
})

-- Effect names, as they appear in Style.Effects and as tags (<shake>, <wave=2>)
TypeDialogue.Effects = table.freeze({
	Shake = "shake",
	Wave = "wave",
})

-- Event kinds, as they appear in Event.Kind and as tags (<pause=0.5>, <sfx=Blip>, <event=DoorOpens>, <anim=Wave>, <stopanim=Wave>)
TypeDialogue.Events = table.freeze({
	-- Seconds to wait before typing on
	Pause = "pause",
	-- A sound to play, by name
	Sfx = "sfx",
	-- A named dialogue event for scripts to react to, fired mid line (Event.Arg is the name)
	Event = "event",
	-- Start the character's animation of this name (Event.Arg)
	PlayAnimation = "anim",
	-- Stop the character's animation of this name (Event.Arg)
	StopAnimation = "stopanim",
})

return TypeDialogue
