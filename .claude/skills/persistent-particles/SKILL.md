---
name: persistent-particles
description: Use when adding, changing, or using persistent particles on ModNPC characters - particles that stay until destroyed rather than playing once - the CreateParticle function, VFX:CreateParticle, CharacterAPI:CreateParticle, the Particle object (Emit, Enable, Disable, Destroy), TypeVFX, or particles at a world position. Use this whenever the user mentions a persistent particle, a held or looping effect, or wants a module such as Stamina to show a particle it can switch on and off (sweat, an aura, a charge-up), even if they don't say "persistent".
---

# Persistent particles

`PlayVFX` is fire-and-forget: the effect plays and cleans itself up. A persistent
particle is the opposite: a caller makes one, gets a **particle object** back and
drives it for as long as it wants. There are no per-change API requests.

## Pieces

| Piece | Where |
| --- | --- |
| Behavior function | `FunctionEnum.CreateParticle`, bound to `VFX:CreateParticle` in `Functions:RegisterMainFunctions`, typed in `TypeBehavior.FunctionCallbacks` |
| Base module | `src/server/Behavior/v1/Base/VFX.luau` (`CreateParticle`: effect name to VFX data, via `Assets:GetVFX`) |
| Wrapper | `CharacterAPI:CreateParticle(effect, location)` takes VFX data, not a name |
| API module | `src/server/API/v1/Modules/VFX/init.luau` (`createParticle`) |
| Particle class | `src/server/API/v1/Modules/VFX/Particle.luau` |
| Types | `src/server/Types/v1/TypeVFX.luau` (`ParticleLocation`, `Particle`) |

## Using a particle

Other Base modules, tasks and mods go through `CallFunction`, so mods can hook it
(see the `functions` skill). Only `Base/VFX` itself calls `CharacterAPI:CreateParticle`.

```luau
local particle = self.Base.Functions:CallFunction(FunctionEnum.CreateParticle, "SweatParticle", self.Character)
if not particle then return end   -- effect not found or location invalid; already warned

particle:Emit(20)      -- a burst; no number uses the effect's EmitCount attribute
particle:Enable()      -- continuous, at the template's Rate
particle:Disable()     -- particles already out live out their lifetime
particle:IsEnabled()   particle:IsDestroyed()
particle:Destroy()     -- removes the emitter and any particles still out, at once
```

Arguments are `(vfxName, location, source?)`. The effect comes from `VFX/Individual`,
searched like every asset: the NPC first, then weapons in equip order, and a `source`
passed in first. Groups are not supported, and PointLight effects are rejected.

**Location** is one of:

- a `BasePart`, or a `Model` that resolves to its part (a character's root part, a
  weapon's part). The particle follows it and emits across the part's volume.
- a `Vector3` or `CFrame`: a fixed spot in the world, held by an Attachment on
  `workspace.Terrain`, emitting from a point. A CFrame also aims the emitter.

## Rules

- **It starts disabled with nothing emitted.** `EnableTime` is ignored here; it is
  only for `PlayVFX`.
- **Keep the object and destroy it yourself.** Make it once and hold it on the
  module, like `Damage.blockBreakHighlight`. Calling `CreateParticle` every time an
  effect should show stacks new emitters.
- **Death does not end a particle.** It ends with `Destroy`, the part it is on being
  destroyed or unparented, or the model of the character that made it being
  destroyed or unparented. A corpse stays in the world, so a module holding a particle
  destroys it in its own death cleanup.
- **To fade out**, call `Disable`, then `Destroy` after the template's `Lifetime.Max`.
  `Destroy` alone cuts live particles off.
- **After it ends every method is a no-op**, so a held object is safe to call. Check
  `IsDestroyed` before relying on it being visible, and make a new one if it matters.
- **The caller owns particles it makes on other characters.** A particle on someone
  else's part ends when that part or its maker goes, whichever comes first.

## Closure tables

Same rule as bars and highlights: the object crosses a BindableFunction, so
`Particle.new` returns a plain table of closures with state in upvalues. No
metatables, no mutable fields on the object.

## Testing

Type-check per the global notes. `luau-lsp` does not catch bad require paths, so
confirm `V1 VFX initialized` in the console. Playtest with a temporary Script in
ServerScriptService (execute_luau can't call the closures), starting a clone per the
`start-npcs` skill and calling through `base.Functions:CallFunction`. To see a
world particle, point `screen_capture` at it with `camera_position` and
`look_at_position` while a loop calls `Emit`.
