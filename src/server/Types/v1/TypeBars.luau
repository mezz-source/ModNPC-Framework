local TypeBars = {}

-- Name of the BillboardGui under ServerScriptService.ModAssets, and of the copy placed in each character
TypeBars.GuiName = "BaseBars"

-- Fills are fractions from 0 to 1 of the bar's width
export type BarOptions = {
	Fill: number?,
	SecondaryFill: number?,
	FillColor: Color3?,
	SecondaryFillColor: Color3?,
	ChangeFillColor: Color3?,
	-- Height as a fraction of the gui's height, above 0 and at most 1 (0.25 by default, so about four bars fit)
	Size: number?,
	-- An integer. Bars stack top to bottom by LayoutOrder; bars with the same order stack in the order they were created
	LayoutOrder: number?,
}

-- A bar is a plain table of closures rather than a metatable class: the API hands it back through a BindableFunction,
-- which copies tables and strips metatables. Methods are still called with a colon, and every copy of a bar drives the
-- same bar. Once the bar is destroyed every method is a no-op.
export type Bar = {
	Name: string,
	SetFill: (self: Bar, fraction: number) -> (),
	SetSecondaryFill: (self: Bar, fraction: number) -> (),
	GetFill: (self: Bar) -> number,
	GetSecondaryFill: (self: Bar) -> number,
	-- While a fill flash runs this changes the color the fill returns to
	SetFillColor: (self: Bar, color: Color3) -> (),
	-- Flashes the fill from its current color to `color` and back, repeating until StopFillFlash. `period` is seconds per
	-- full flash (0.5 by default). Starting again while flashing changes the flash but keeps the original color.
	StartFillFlash: (self: Bar, color: Color3, period: number?) -> (),
	-- Stops the flash and puts the fill back to the color it had before the flash
	StopFillFlash: (self: Bar) -> (),
	IsFillFlashing: (self: Bar) -> boolean,
	SetSecondaryFillColor: (self: Bar, color: Color3) -> (),
	-- The trail that shows what the fill just lost
	SetChangeFillColor: (self: Bar, color: Color3) -> (),
	SetSize: (self: Bar, height: number) -> (),
	GetSize: (self: Bar) -> number,
	SetLayoutOrder: (self: Bar, order: number) -> (),
	GetLayoutOrder: (self: Bar) -> number,
	IsDestroyed: (self: Bar) -> boolean,
	Destroy: (self: Bar) -> (),
}

return TypeBars
