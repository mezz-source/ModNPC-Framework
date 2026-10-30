---
name: functions
description: Use when adding, renaming, or changing named ModNPC behavior functions (Functions.luau, FunctionSystem, CallFunction, First/Replace/Last subscriptions, RegisterMainFunctions, FunctionEnum) or high-level behavior like attacking, wandering, sprinting, or dodging that mod scripts should be able to hook or replace. Also use whenever one Base module, task, or behavior calls another module directly (base.Movement, base.Sound, base.TargetSelector, ...) so the call can be routed through CallFunction instead.
---

# Character function system

Use this skill for named, callable character behavior and for bridging one
behavior module to another.

`Functions.luau` owns the per-character `FunctionSystem`. It stores one
`MainFunctions` callback per name, then `CallFunction` executes subscribers in
this order:

1. `First` subscribers;
2. one optional `Replace` subscriber instead of the main function;
3. the main function when it was not replaced;
4. `Last` subscribers.

Subscriptions are snapshotted before iteration, can be unsubscribed
(`subscription:Unsubscribe()` searches the bucket for its own position), and
receive the same arguments as the call. Use `Base.Functions:CallFunction` (or
`Base:SubscribeFunction`) rather than calling a registered behavior method
directly when hooks or replacements must work.

## The rule: cross-module talk goes through Functions

When one Base module needs another module's behavior, it calls
`base.Functions:CallFunction(FunctionEnum.X, ...)`. It never reaches into the
other module (`base.Movement:MoveForward()`, `self.Base.Sound:PlayCategory()`,
`base.TargetSelector:SelectBest()`). Mod scripts can only hook or replace what
goes through `CallFunction`, so a direct call is a hole in the mod surface.

**Exempt, may be used directly:**

- `CharacterAPI`: the only distributor of API requests. Every module may use it.
- Core handlers that must not be overridden: `Scheduler`/`Tasks`,
  `CharacterTasks`, `Configuration`, `State`, `Assets`, `Distance` (pure range
  maths shared by tasks, nothing a mod would replace). Plus `Events` (the
  notification bus) and `Functions` itself.
- The raw `Base.Humanoid` instance, read-only, before `Humanoid.new` replaces it.
- `Functions:RegisterMainFunctions`: the one place that binds names to module
  methods, so it reaches modules directly by design.
- A module using its own methods and fields.

**Everything else is a behavior module** (Movement, TargetSelector, Sound,
Animation, Humanoid, Damage, Dialogue, ThoughtProcess, and future Attacks or
Targetting): other modules, tasks, and mod-facing code reach them only via
`CallFunction`.

### Cleaning up violations

Whenever you notice a direct cross-module call while working in this repo, fix
it in the same change (or flag it if the fix is large):

1. Find it: grep for `base.<Module>` / `self.Base.<Module>` where `<Module>` is a
   behavior module and the file is not that module itself, `Functions.luau`, or
   `CharacterAPI.luau`. Also check for cached fields (`self.Movement = base.Movement`).
2. If no enum entry exists for the method, add one (see "Adding a base function"),
   binding it to the owning module in `RegisterMainFunctions`.
3. Replace the call with `self.Functions:CallFunction(FunctionEnum.X, ...)`
   (`FunctionEnum` from `TypeCharacterFunctions`). Return values pass through.
4. In tasks: swap the module name in `Dependencies` for `Dependencies.Functions`
   and drop the cached module field.
5. Delete dead cross-module fields (e.g. a `self.Base.AnimationHandler` that
   does not exist).

Caveats: `CallFunction` raises on an unregistered name, and main functions are
registered late in `Base.new`, so module constructors must not call functions
during construction. Only call from runtime paths (events, marker callbacks,
task `Start`/`Update`).

## The API-to-character boundary

The API layer reaches a character through the `CharacterFunction` BindableFunction
(`CharacterUtility.sendFunction(character, name, arguments)`), answered by
`CharacterAPI:_functionRecieved`. That handler is a direct link to this module:

- `"Damage"` is the one special case (arguments is the damage context table).
- Any other `name` is a `FunctionEnum` value, `arguments` is the list of
  arguments, and the call goes through `Functions:CallFunction`, so `First` /
  `Replace` / `Last` subscriptions apply exactly as they do inside Base.
- The character always answers with a `CharacterResponse` (`Success`, `Message`,
  `Data`). `sendFunction` unwraps it: a character-side failure (unknown name,
  error inside the function, name not bound because its module is missing)
  comes back as `Success = false`, status 409, with the character's message.
- A function returning several values answers with them as a list in `Data`
  (`GetStamina` gives `{ current, max }`). Shape it in the API module, like
  `CharacterUtility.getStaminaInfo` does, so callers get named fields.
- `Data` crosses a BindableFunction: tables are deep-copied and metatables
  stripped (Instances and closures survive), so don't return class instances.

So exposing a new behavior function to the API needs no handler change: bind it
in `RegisterMainFunctions`, then call `sendFunction` with its enum name. Add a
small wrapper in the API module (and a `TypeAPIFunctions` entry) only when
callers want a shaped result. Note this makes every enum function, mutating
ones included, reachable from the API side.

## Adding a base function

1. Add the canonical name to `TypeCharacterFunctions.FunctionEnum`.
2. Add its callback signature to `TypeBehavior.FunctionCallbacks` and update
   any related public function types.
3. In `Functions:RegisterMainFunctions`, bind the name to the owning module
   method. Use the local `bind` helper for required `Movement` methods and
   `bindIfAvailable` for optional modules such as `Targetting` or `Attacks`.
4. Implement the module method with the normal colon-method `self`
   convention, then verify `Base.new` constructs that module before function
   registration.
5. Call it through `CallFunction` and test missing-module, replacement, and
   normal execution paths.

Functions should primarily bridge module-to-module interactions: a high-level
action can obtain targets, choose an attack, move, play animation, and emit
events while remaining replaceable by a mod script. High-level behavior such
as attacking, wandering, sprinting, or dodging belongs here.

Keep low-level API behavior out of this layer. Operations such as applying an
impulse, applying angular impulse, or dealing direct humanoid damage should
remain in `CharacterAPI` and the API modules. A function may orchestrate those
operations as part of a high-level action, but it should not duplicate their
request construction or move primitive implementation into the function
system.

## Impact zones

Adding a function affects the canonical enum, `TypeBehavior`, registration,
the owning module, and callers/mod scripts. Removing or renaming one can make
`CallFunction` raise `Unknown behavior function` or make subscriptions fail.
Changing a function's arguments affects all `First`, `Replace`, `Last`
callbacks, so update the type and every subscriber together.