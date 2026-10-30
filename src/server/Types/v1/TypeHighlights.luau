local TypeHighlights = {}

-- Name of the Folder each character's highlights are kept in
TypeHighlights.FolderName = "ModHighlights"

-- Anything left out takes Roblox's Highlight default. Transparencies are 0 (solid) to 1 (invisible).
-- DepthMode is not an option: highlights always occlude.
export type HighlightOptions = {
	FillColor: Color3?,
	OutlineColor: Color3?,
	FillTransparency: number?,
	OutlineTransparency: number?,
	-- true by default
	Enabled: boolean?,
}

-- A short lived highlight: shows its colors at once, holds them, fades both transparencies to 1, then destroys itself
export type FlashHighlightOptions = {
	-- white by default
	FillColor: Color3?,
	-- the fill color by default
	OutlineColor: Color3?,
	-- what the fade starts from (0.5 and 0 by default)
	FillTransparency: number?,
	OutlineTransparency: number?,
	-- seconds at full color before the fade starts (0 by default)
	Hold: number?,
	-- seconds the fade takes (0.4 by default)
	FadeTime: number?,
}

-- Seconds (Quad Out), or a TweenInfo for full control. 0 seconds sets the value at once.
export type HighlightTween = number | TweenInfo

-- A highlight is a plain table of closures rather than a metatable class: the API hands it back through a
-- BindableFunction, which copies tables and strips metatables. Methods are still called with a colon, and every copy
-- drives the same highlight. Once the highlight is destroyed every method is a no-op.
-- Each property has its own tween: setting or tweening a property cuts its running tween short, never another's.
export type Highlight = {
	Name: string,
	-- While that color is flashing, a set changes the color the flash returns to
	SetFillColor: (self: Highlight, color: Color3) -> (),
	SetOutlineColor: (self: Highlight, color: Color3) -> (),
	SetFillTransparency: (self: Highlight, transparency: number) -> (),
	SetOutlineTransparency: (self: Highlight, transparency: number) -> (),
	-- Tweening a color that is flashing stops its flash first (back to the original color, then tweened from there)
	TweenFillColor: (self: Highlight, color: Color3, tween: HighlightTween) -> (),
	TweenOutlineColor: (self: Highlight, color: Color3, tween: HighlightTween) -> (),
	TweenFillTransparency: (self: Highlight, transparency: number, tween: HighlightTween) -> (),
	TweenOutlineTransparency: (self: Highlight, transparency: number, tween: HighlightTween) -> (),
	-- Colors are the ones the highlight rests at (or is tweening to), not a flash's current color; transparencies are the
	-- ones set or tweened to
	GetFillColor: (self: Highlight) -> Color3,
	GetOutlineColor: (self: Highlight) -> Color3,
	GetFillTransparency: (self: Highlight) -> number,
	GetOutlineTransparency: (self: Highlight) -> number,
	-- Flashes the fill and/or outline (a nil color leaves that part alone) to the color and back, repeating until StopFlash.
	-- `period` is seconds per full flash (0.5 by default). Starting again while flashing changes the flash but keeps the
	-- original colors; a part the new call leaves nil stops flashing.
	StartFlash: (self: Highlight, fillColor: Color3?, outlineColor: Color3?, period: number?) -> (),
	-- Stops the flash and puts both colors back to what they were before it
	StopFlash: (self: Highlight) -> (),
	IsFlashing: (self: Highlight) -> boolean,
	SetEnabled: (self: Highlight, enabled: boolean) -> (),
	IsEnabled: (self: Highlight) -> boolean,
	IsDestroyed: (self: Highlight) -> boolean,
	Destroy: (self: Highlight) -> (),
}

return TypeHighlights
