---
name: highlights
description: Use when adding, changing, or using Highlight effects on ModNPC characters - the Highlights API module and Highlight class, CreateHighlight/FlashHighlight/GetHighlight/RemoveHighlight on CharacterAPI, fill/outline colors and transparencies, color/transparency tweens, looping flashes, or short lived hit flashes. Use this whenever the user mentions highlights, glows, outlines, hit flashes, or tinting a character, even if they don't say "Highlight".
---

# Character highlights

Highlights tint/outline a whole character. Like bars, the API layer owns all
instance logic; behavior code asks for a highlight once, gets a **highlight
object** back, and drives it directly. There are no per-change API requests.

## Pieces

| Piece | Where |
| --- | --- |
| API module | `src/server/API/v1/Modules/Highlights/init.luau` (`createHighlight`, `flashHighlight`, `getHighlight`, `removeHighlight`) |
| Highlight class | `src/server/API/v1/Modules/Highlights/Highlight.luau` (all property/tween/flash logic) |
| Types | `src/server/Types/v1/TypeHighlights.luau` (`HighlightOptions`, `FlashHighlightOptions`, `HighlightTween`, `Highlight`) |
| Wrappers | `CharacterAPI:CreateHighlight / FlashHighlight / GetHighlight / RemoveHighlight`, typed in `TypeBehavior.CharacterAPI` |
| Names | `TypeAPIFunctions.Modules.Highlights`, `Functions.Highlights.*` |

No asset template: each highlight is a new `Highlight` instance (Adornee = the
character) inside a `ModHighlights` Folder in the character.

## Using highlights

```luau
local glow = self.CharacterAPI:CreateHighlight("Enraged", {
    FillColor = Color3.new(1, 0, 0), OutlineColor = Color3.new(1, 1, 1),
    FillTransparency = 0.5, OutlineTransparency = 0, Enabled = true, -- all optional, Roblox defaults otherwise
})
if not glow then return end   -- name taken / bad options; the API already warned

glow:SetFillColor(c)  glow:SetOutlineColor(c)
glow:SetFillTransparency(t)  glow:SetOutlineTransparency(t)      -- 0..1
glow:TweenFillColor(c, 0.3)  glow:TweenOutlineColor(c, tweenInfo) -- seconds (Quad Out) or a TweenInfo; 0 = instant
glow:TweenFillTransparency(1, 0.5)  glow:TweenOutlineTransparency(1, 0.5)
glow:StartFlash(Color3.new(1, 1, 1), nil, 0.4) -- fill and/or outline color (nil = that part doesn't flash), period
glow:StopFlash()               -- both colors back to their originals; IsFlashing()
glow:SetEnabled(false)  glow:IsEnabled()
glow:GetFillColor() -- GetOutlineColor, GetFillTransparency, GetOutlineTransparency, IsDestroyed
glow:Destroy()                 -- or self.CharacterAPI:RemoveHighlight("Enraged")

-- short lived: shows at once, holds, fades both transparencies to 1, destroys itself
self.CharacterAPI:FlashHighlight({ FillColor = Color3.new(1, 0, 0), Hold = 0.05, FadeTime = 0.3 })
```

- **DepthMode is always `Occluded`.** It is not an option (passing one is a 422)
  and anything that changes it on the instance is put back.
- **Each property has its own tween slot.** A set or tween cuts short only that
  property's running tween. Getters return the resting/target value.
- **Flash remembers the originals.** `StartFlash` while flashing changes the flash
  but keeps the original colors; a part left nil on the restart stops flashing.
  `Set*Color` during a flash changes what it returns to (flash restarts from it);
  `Tween*Color` stops that color's flash first.
- **Flash highlights** default to white fill, outline = fill color, 0.5 / 0
  transparency, Hold 0, FadeTime 0.4. They are unnamed (`_Flash<n>`, a reserved
  prefix), never registered, never conflict. The returned object can end/alter it early.
- Names are per character; a live name is a 409 conflict. Highlights die with
  their instance, folder or character. `RemoveHighlight` is synchronous.
- Roblox renders at most 31 highlights at once across the game, so prefer
  short lived flashes and remove persistent ones when done.

## Closure tables

Same rule as bars: the object crosses a BindableFunction, so `Highlight.new`
returns a plain table of closures with state in upvalues. No metatables, no
mutable fields on the object.

## Testing

Type-check per the global notes. Playtest with a temporary Script in
ServerScriptService (execute_luau can't call the closures) driving
`ModFunctions.Request:Invoke({ ModuleName = "Highlights", Function = ..., Arguments = { model, ... } })`.
Any Model works as a target (a dummy with one Part is enough); it need not be a ModNPC.
