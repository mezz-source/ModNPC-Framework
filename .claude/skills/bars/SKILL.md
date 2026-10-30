---
name: bars
description: Use when adding, changing, or using overhead UI bars (health, stamina, armor, poise...) on ModNPC characters - the Bars API module and Bar class, BaseBars/BAR_REF, CreateBar/GetBar/RemoveBar on CharacterAPI, bar fill/secondary fill/change-fill/size/layout order, or when a Base behavior module, task, or event needs to show or update a bar above a character's head. Use this whenever the user mentions bars, billboard bars, health bars, or the BaseBars gui.
---

# Overhead bars

Bars are billboard UI above a character's head. The API layer owns all UI logic;
behavior code asks for a bar once, gets a **bar object** back, and drives it
directly (`bar:SetFill(0.5)`). There are no per-change API requests.

## Pieces

| Piece | Where |
| --- | --- |
| Gui template | Studio only: `ServerScriptService.ModAssets.BaseBars` (a BillboardGui, not on disk) |
| API module | `src/server/API/v1/Modules/Bars/init.luau` (`createBar`, `getBar`, `removeBar`) |
| Bar class | `src/server/API/v1/Modules/Bars/Bar.luau` (all UI/tween logic) |
| Types | `src/server/Types/v1/TypeBars.luau` (`BarOptions`, `Bar`) |
| Wrappers | `CharacterAPI:CreateBar / GetBar / RemoveBar`, typed in `TypeBehavior.CharacterAPI` |
| Names | `TypeAPIFunctions.Modules.Bars`, `Functions.Bars.{CreateBar, GetBar, RemoveBar}` |

Template layout (crawl it in Studio before changing anything that depends on it):

```
BaseBars [BillboardGui]            5 x 1.3 studs, ClipsDescendants
  BarRef [Frame]                   invisible container + UIListLayout (vertical, bottom aligned, sorted by LayoutOrder)
    BAR_REF [Frame]                invisible template, 1 x 0.25 of the gui; cloned once per bar
      MainBar [Frame]              inset track
        Fill, ChangeFill, SecondaryFill   (ZIndex 2, 1, 3)
```

`createBar` clones `BaseBars` into the character (once; adornee is the Head, else
the root part), then clones `BAR_REF` into `BarRef`, names it the bar name, makes
it visible and wraps it. It validates the template has `MainBar` with `Fill`,
`ChangeFill` and `SecondaryFill`; if you rename or restructure the asset, update
`BarClass.validateFrame` and the lookups in `Bar.new` together.

## Using bars (the common case)

```luau
local bar = self.CharacterAPI:CreateBar("Health", {
    Fill = 1,                 -- fractions 0..1 of the bar's width
    SecondaryFill = 0,        -- overlay above everything, for armor/extensions
    FillColor = Color3.fromRGB(85, 255, 0),
    SecondaryFillColor = Color3.fromRGB(0, 0, 255),
    ChangeFillColor = Color3.fromRGB(255, 0, 4),
    Size = 0.25,              -- height as a fraction of the gui, > 0 and <= 1 (default 0.25; a stamina bar might be 0.1)
    LayoutOrder = 0,          -- integer; top to bottom, ties in creation order
})
if not bar then return end    -- failed (name taken, no head/root, template missing); the API already warned

bar:SetFill(health / maxHealth)
bar:SetSecondaryFill(armor / maxArmor)
bar:SetFillColor(color)       -- also SetSecondaryFillColor, SetChangeFillColor
bar:StartFillFlash(Color3.new(1, 1, 1), 0.4) -- flash the fill to a color and back until stopped; period = seconds per flash (default 0.5)
bar:StopFillFlash()           -- stops and restores the fill's original color; IsFillFlashing() reports state
bar:SetSize(0.1)
bar:SetLayoutOrder(2)
bar:GetFill() -- GetSecondaryFill, GetSize, GetLayoutOrder, IsDestroyed
bar:Destroy()                 -- or self.CharacterAPI:RemoveBar("Health")
```

- **Change fill is automatic.** A drop leaves the trail (`ChangeFill`) behind
  the fill, holds it 0.4s (each extra hit before it catches up adds 0.15s, capped
  at 1.5s past the latest hit), then tweens it down to the fill. A rise above the
  trail snaps the trail level. Never touch `ChangeFill` from behavior code. The
  constants live at the top of `Bar.luau`.
- **Fill flash remembers the original color.** `StartFillFlash` records the fill's
  color when the flash begins; `StopFillFlash` puts it back. Starting again while
  flashing changes the flash color/period but keeps the original. `SetFillColor`
  during a flash changes the color the fill returns to (the flash restarts from
  it). Invalid color/period is ignored with a warning. Flash only touches `Fill`,
  never the change fill or secondary fill.
- **Bars clean themselves up.** Destroying or unparenting the bar's frame, its
  gui, or the character destroys the bar; every method is then a no-op. A destroyed
  bar frees its name. `RemoveBar` is synchronous (not fire-and-forget) so a
  remove-then-recreate of the same name works.
- A name already used by a live bar is a **conflict** (never replaced); use
  `GetBar(name)` to fetch the existing one. `BAR_REF` and `UIListLayout` are
  reserved names. Invalid options fail the create with a 422 naming the option.
- Setters ignore invalid values with a warning (non-numbers, NaN, bad size,
  non-integer layout order); fills are clamped.
- About four 0.25-high bars fit; more are clipped. Smaller `Size`s fit more.
- If the asset leaves `StudsOffset`/`StudsOffsetWorldSpace` at zero, `createBar`
  lifts the gui by `DEFAULT_HEAD_OFFSET` (0, 2, 0). Author an offset on the asset
  to override.

## Bar objects are closure tables, not classes

API `Data` crosses a BindableFunction, which deep-copies tables and strips
metatables. So `Bar.new` returns a plain table of closures with all state in
upvalues; methods take an ignored `_self` so `bar:Method()` works. Every copy
drives the same bar, but `bar == otherCopy` is false and `getmetatable(bar)` is
nil. Keep this property when changing the class: no metatables, no mutable table
fields on the public object, no state read back from the table. The canonical
instance stays in the registry in `Bars/init.luau` (weak-keyed by character).

## Making a bar from base behavior

There is no `Base.Bars` module yet. To show health/stamina/armor from behavior:

1. **Call `CharacterAPI` only.** `CharacterAPI` is exempt from the
   functions rule, so any Base module may call `self.CharacterAPI:CreateBar(...)`.
   Do not require the `Bars` API module or reach for the template.
2. **Own the handles in one module.** Create a behavior module
   `Base/Bars.luau` (colon-method `new(Base, character)` / `Destroy()` like
   `Sound.luau`), construct it in `Base.new` after `Humanoid`/`Damage` and before
   `_registerMainFunctions`, hold `self.bars[name] = bar`, and expose methods
   such as `Show`, `SetFill`, `Remove`. Do not create bars in module
   constructors that run before `CharacterAPI:_init()`.
3. **Route cross-module access through Functions** (see the `functions` skill):
   add the names to `TypeCharacterFunctions.FunctionEnum`, their signatures to
   `TypeBehavior.FunctionCallbacks`, bind them in `RegisterMainFunctions`, and have
   tasks/other modules use `Functions:CallFunction(FunctionEnum.X, ...)`. Mod
   scripts can then hook or replace how a bar is shown. A module may call its own
   methods and its own bars directly. Add the module to `TypeBehavior.Base` too
   (see the `type-syncing` skill).
4. **Drive it from events, not polling.** Subscribe to the character events
   (see the `events` skill), for example damage or humanoid health changes, and
   call `bar:SetFill(health / maxHealth)` in the handler; unsubscribe in
   `Destroy()`. The change-fill trail needs no help from the caller.
5. **Don't clean up manually on death/removal.** The bars die with the character;
   a `Destroy()` that calls `bar:Destroy()` on its handles is only needed when the
   bar should disappear while the character lives (for example a weapon's bar
   when it is unequipped). Drop dead handles by checking `bar:IsDestroyed()`.

Colors, sizes and orders can come from the character's configuration if the
mod format needs them. The config schema is Studio-only, so adding keys makes
them mandatory for every NPC (see the `modnpc-config-schema-location` memory).

## Adding to the API layer

- New bar behavior goes in `Bar.luau`, with its signature in `TypeBars.Bar`. Option
  validation goes in `Bars/init.luau` (`validateOptions`) and the option is applied
  in `Bar.new`; shared validators are exported from `BarClass`.
- A new API endpoint follows the `api-extending` skill: function in
  `Bars/init.luau` returning a `ModuleResponse`, string in `TypeAPIFunctions`,
  wrapper in `CharacterAPI`, entry in `TypeBehavior.CharacterAPI`. Use
  `RequestAPI(..., true)` (fire and forget) only where ordering does not matter.
- Keep per-bar state out of the module except the registry.

## Testing

- Type-check per the global notes (rojo sourcemap + `luau-lsp analyze`).
- Playtest through the Studio MCP. `execute_luau` runs in the plugin Lua VM and
  **cannot call bar closures** ("Attempt to load a function from a different Lua
  VM"), so test with a temporary Script: add `_BarTest` to ServerScriptService in
  Edit mode (`Script.Source` set from `execute_luau`), start play, drive the API with
  `ServerScriptService.ModFunctions.Request:Invoke({ ModuleName = "Bars",
  Function = "createBar", Arguments = { npc, "Health", opts } })`, `print` results
  prefixed `[BARTEST]`, read them with `get_console_output`, then stop play and
  destroy the script. `task.wait(2)` first so the API is ready. The workspace
  model `modnpc` is a ready target.
- Useful checks: duplicate name (409), invalid options (422), clamping, the hold
  then tween on a stream of drops (sample `ChangeFill.Size.X.Scale`), heal over
  trail, remove then recreate, destroying the frame / the gui, and `Size`/`LayoutOrder`.
