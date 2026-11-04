# Mod Scripts

A mod script changes how one character behaves without touching the framework. It can run code before or after any behavior function, replace a function outright, listen to anything that happens to the character, register new tasks, and send stimulants to other characters. It does all of this through the same hooks and API boundary the built-in behavior uses.

This guide covers writing mod scripts and using the core systems from them. [Custom Tasks](Custom%20Tasks.md) covers tasks in depth. [Architecture](../Architecture.md) explains why the framework is built this way. Every example here is a file in [Example Scripts](Example%20Scripts/) that has been run on live characters.

- [The basics](#the-basics)
- [The `base` object](#the-base-object)
- [Hooking behavior functions](#hooking-behavior-functions)
- [Listening to events](#listening-to-events)
- [Doing things to the world](#doing-things-to-the-world)
- [Configuration and state](#configuration-and-state)
- [Talking to other characters](#talking-to-other-characters)
- [Lifetime and cleanup](#lifetime-and-cleanup)
- [Testing a mod](#testing-a-mod)
- [Pitfalls](#pitfalls)
- [Example index](#example-index)

---

## The basics

A mod script is a `ModuleScript` that returns a table with an `init` function. Put it anywhere under the character's `ModNPC/Mods` folder (nested folders are fine):

```
<Character Model>
  ModNPC/
    Mods/
      Enrage          <- ModuleScript
      Fun/
        Taunt         <- ModuleScript
```

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

type Base = TypeBehavior.Base

local module = {}

function module.init(base: Base)
	print("attached to", base.Character.Name)
end

return module
```

When the character starts, every `ModuleScript` under `Mods` is `require`d. Each one that returns a table with an `init` function gets `init(base)` called, inside a `pcall`. A mod that errors during `init` logs `Failed to initialize mod script:` and the character still starts, just without that mod. A `ModuleScript` without an `init` is loaded and then ignored, so the folder can also hold shared helper modules.

The framework types (`TypeBehavior`, `TypeCharacterEvents`, `TypeTask`, ...) live in `ServerScriptService.ModNPCServer.Types.v1`. Requiring them gives you the enums and the `Base` type for autocomplete.

> **Return a plain table.** The module crosses a `BindableFunction` on its way to the character, and tables that cross one are copied with their metatables stripped. `init` must sit directly on the returned table. A class whose `init` comes from `setmetatable(..., Parent)` loses it. Functions inside the table survive the trip, so closures work normally.

### When `init` runs

```
build every Base module
  -> register the behavior functions     mods can subscribe to any of them
  -> mod init(base)                      <- your code runs here
  -> Attacks, Defense, Weapons, dodges initialize (first weapon equips)
  -> start tasks are created from Config/StartTasks
```

Consequences:

- Every Base module exists and every function is registered. Hook anything.
- Your hooks are in place before the first weapon is equipped and before any start task runs. A mod can hook `EquipWeapon`, and a task registered in `init` can be named in `StartTasks`.
- `init` runs inside character startup, so **do not yield in it**. For anything that waits, use `task.spawn` or `task.delay`.
- Keep per-character state in locals inside `init`. The module itself is required once per `ModuleScript` instance, so a module-level variable is shared by every character that uses that same script.

[01_Skeleton](Example%20Scripts/01_Skeleton.luau) shows the smallest complete mod, including cleanup.

### Installing a mod

Create a `ModuleScript` under the character's `ModNPC/Mods` folder in Studio and paste the source in. The files in `docs/` are not part of the Rojo project, so they are not synced anywhere on their own. To keep a mod in source control, put it in a folder the project file maps and clone it into the character's `Mods` folder at build time or from a setup script.

---

## The `base` object

`init` receives the character's `Base`. These are the parts mods use:

| Field | What it is |
|---|---|
| `base.Character` | The character `Model`. |
| `base:IsAlive()` | `false` once the character has died. Check it in any delayed code. |
| `base.Functions` | The function system: `CallFunction`. See [Hooking behavior functions](#hooking-behavior-functions). |
| `base:SubscribeFunction(name, callback, position)` | Hook a behavior function (`First`, `Last`, `Replace`). Also `base.Functions:SubscribeFunction`. |
| `base.FunctionEnum` | Every function name. `TypeBehavior.FunctionEnum` is the same table. |
| `base.SubscribeEnum` | `First`, `Last`, `Replace`. |
| `base.Events` | Character events: `Subscribe`, `Unsubscribe`, `Dispatch`. |
| `base.CharacterAPI` | The door to the world: bars, highlights, sounds, stimulants, health, targets, damage. |
| `base.Configuration` | This character's config: `Get`, `Observe`, `IsPermitted`, `ObservePermission`. |
| `base.Heartbeat` | The character's frame clock: `Connect(function(deltaTime) ... end)`. Use it instead of `RunService.Heartbeat`, so the update freezes with the character (see [Permissions](#permissions)). |
| `base.State` | Named character states: `Register`, `Get`, `Is`, `Set`. |
| `base.Scheduler` (`base.Tasks`) | Runs tasks: `Start`, `Stop`, `GetTask`, `GetTasks`, and the bulk stops `StopCategory`, `StopResource`, `StopTasks`, `StopAll` (these skip `Essential` tasks unless given `{ CancelEssentials = true }`). |
| `base.CharacterTasks` | Task constructors by name (`base.CharacterTasks.Walk.new(...)`), including any you register. |
| `base:RegisterTask(name, class)` | Make your own task available by name. |
| `base.Task`, `base.TaskEnums` | The task base class and the `Category` / `Resources` / `Dependencies` / `Policy` enums. |
| `base:NewStimulant(name)` | Start describing a stimulant to send. |

Two things to know:

- **`base.Humanoid` is not the Roblox `Humanoid`.** After startup it is the Humanoid behavior module (health bar, landing, death). Read health with `base.CharacterAPI:GetHealthInfo()`. `base.Character:FindFirstChildOfClass("Humanoid")` is available for reading or listening to signals, but never write to it.
- **Other Base modules** (`base.Stamina`, `base.Damage`, `base.Movement`, ...) are reachable, but going through them skips every other mod's hooks. Use `base.Functions:CallFunction` instead. The exceptions are the core handlers listed above (`Events`, `Configuration`, `State`, `Scheduler`, `CharacterAPI`).

---

## Hooking behavior functions

Every meaningful action is a named function: `Dodge`, `BeginBlock`, `PurchaseStamina`, `PickDesiredAttack`, `ReactToIncomingAttack`, and about a hundred others. `base.Functions:CallFunction(name, ...)` runs a function and everything hooked to it:

```
First hooks  ->  the Replace hook if there is one, otherwise the original  ->  Last hooks
```

| Position | Runs | Arguments | Return value |
|---|---|---|---|
| `First` | before the action, even when it will be refused | the call's arguments | ignored |
| `Last` | after the action, even when it failed | the call's arguments | ignored |
| `Replace` | instead of the action | the call's arguments | **becomes the call's result** |

```luau
local FE = base.FunctionEnum
local SE = base.SubscribeEnum

-- Subscribe returns a handle. Keep it if you want to unhook later.
local hook = base:SubscribeFunction(FE.Dodge, function(direction)
	print("dodging", direction)
end, SE.First)

hook:Unsubscribe()
```

`position` defaults to `Last`. An unknown function name raises an error, so a typo shows up at once.

### Replace

[03_TankMode](Example%20Scripts/03_TankMode.luau) replaces the decision a character makes when it sees a hit coming, so it never dodges or blocks:

```luau
base:SubscribeFunction(FE.ReactToIncomingAttack, function(stimulant)
	return "None", "This one takes it on the chin"
end, SE.Replace)
```

Rules:

- **One `Replace` per function.** A second is refused with a warning, and `SubscribeFunction` returns `nil, reason`.
- **Return what the caller expects.** The original's return shape is in `TypeBehavior.FunctionCallbacks`. A `Replace` that returns nothing gives the caller nothing, and the caller may index it.
- **There is no "call the original".** If you want to add to an action, use `First` or `Last`. Reserve `Replace` for changing the outcome entirely.
- Replacing a gate is the cheap way to change what a character can do. `CanDodge`, `CanBlock`, `CanAttack`, `CanMove` and `CanBeEvasive` return `(allowed, reason?)`.

### First and Last

`First` and `Last` can't see or change the result. To act on what happened, check the character afterwards. [02_DodgeFlash](Example%20Scripts/02_DodgeFlash.luau) flashes the character when a dodge begins. A refused dodge still runs its `Last` hook, so it asks `base.State` whether the dodge state is `Active` first.

### Calling functions

Use `CallFunction` for everything you would otherwise do by reaching into a module:

```luau
local current, max = base.Functions:CallFunction(FE.GetStamina)
local paid = base.Functions:CallFunction(FE.PurchaseStamina, "Dodge")   -- false if it can't be afforded
base.Functions:CallFunction(FE.PlayAnimation, "Taunt", 0.1, nil, false)
```

Function callbacks are **not** wrapped in `pcall`. An error in your hook surfaces in whoever called the function, which may be a task, so keep hooks small and defensive.

### What can be hooked

`FunctionEnum` is the full list. By area:

| Area | Functions |
|---|---|
| Movement | `StartSprinting`, `StopSprinting`, `Jump`, `Move`, `MoveLeft/Right/Forward/Backward`, `MoveTo`, `StopMoving`, `SetWalkDirection`, `ClearWalkDirection`, `LockMovement`, `UnlockMovement`, `SetFocusTarget`, `RemoveFocusTarget`, `ApplyImpulse`, `ApplyAngularImpulse`, `Wander` |
| Dodging | `Dodge`, `DodgeLeft/Right/Forward/Backward`, `DodgeRandomly` |
| Ability gates | `CanMove`, `CanAttack`, `CanDodge`, `CanBlock`, `CanBeEvasive` |
| Attacks | `AttackCurrentTarget`, `MeleeAttackCurrentTarget`, `RangeAttackCurrentTarget`, `PickDesiredAttack`, `GetDesiredAttack`, `ClearDesiredAttack`, `CanAffordAttack`, `IsReadyToAttack`, `IsPressingOn`, `CancelCurrentAttack` |
| Defense and damage | `ReactToIncomingAttack`, `BeginBlock`, `EndBlock`, `BreakBlock`, `IsBlocking`, `IsBlockBroken`, `GetHitCategory`, `IsStaggered`, `IsLaunched`, `BeginStagger`, `EndStagger`, `BeginLaunch`, `EndLaunch` |
| Stamina | `GetStamina`, `GetStaminaCost`, `GetStaminaEfficiency`, `IsExhausted`, `CanAffordStamina`, `PurchaseStamina`, `SpendStamina`, `RestoreStamina`, `BreakStamina` |
| Skills | `GetSkillLevel`, `GetSkillChance`, `RollSkill`, `RollSkills` |
| Disposition | `GetDisposition`, `GetEngageDistance`, `GetHoldDistance`, `GetAttackStandoff`, `GetAttackFit`, `GetAttackPace` |
| Targeting | `GetTargets`, `IsValidTargetPreference`, `SelectBestTarget` |
| Presentation | `PlaySound`, `PlaySoundCategory`, `PlayVFX`, `PlayVFXGroup`, `LoadAnimation`, `PlayAnimation`, `StopAnimation` |
| Weapons | `EquipWeapon`, `UnequipWeapon`, `ArmWeapon`, `DisarmWeapon` |
| Stimulants | `ReceiveStimulant`, `DropStimulant`, `GetStimulants`, `PeekStimulant`, `ConsumeStimulant` |

Signatures are in `TypeBehavior.FunctionCallbacks`. When you are not sure which function something goes through, [05_FunctionTracer](Example%20Scripts/05_FunctionTracer.luau) prints every call to the functions you list, with arguments.

---

## Listening to events

Functions are for things that can be changed. Events are notifications: something happened, tell whoever cares.

```luau
local Events = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents).Names

local subscription = base.Events:Subscribe(Events.Combat.DamageTaken, function(payload)
	print(payload.Amount, payload.MaxHealth)
end)

subscription.Unsubscribe()   -- an event subscription's Unsubscribe works with . or :
```

(A *function* hook's handle, from `SubscribeFunction`, needs the colon: `hook:Unsubscribe()`.)

`Subscribe(name, callback, once?, position?)`:

- `once = true` removes the listener after its first call.
- `position = "First"` runs it before the other listeners (default is after them).
- Listeners are wrapped in `pcall`, so one failing listener can't break the others. An error becomes a `Character event failed:` warning.
- The payload is a single value, usually a table. Each name's payload type is documented beside it in `TypeCharacterEvents`.

The names mods use most:

| Event | Payload | When |
|---|---|---|
| `Combat.DamageTaken` | `Amount`, `MaxHealth`, `Attacker?`, `DamageType?`, `Special?` | Health came off the character |
| `Combat.DefenseSucceeded` | `Attacker?`, `RecieveType` | A hit was dodged or blocked |
| `Combat.DefenseReaction` | `TypeDefense.DefenseReaction` | The character decided how to meet an incoming hit |
| `Combat.AttackLanded` / `AttackDefended` / `AttackMissed` | `Target`, `AttackName`, `HitName`, `Amount`, `RecieveType?` | How one hit of this character's attack turned out |
| `Humanoid.Died` | none | The character died |
| `Humanoid.HealthChanged` | `Health`, `MaxHealth` | Any health change |
| `Stamina.Changed` | `Previous`, `Current`, `Max`, `Reason?` | Stamina or its maximum changed |
| `Stamina.ExhaustionStarted` / `ExhaustionEnded` | `Current`, `Max`, `Efficiency` | Exhaustion began or ended |
| `Targetting.TargetSpotted` / `NewFocusTarget` / `TargetLost` / `AllTargetsLost` | | Target discovery and loss |
| `Weapon.Equipped` / `Unequipped` / `Armed` / `Disarmed` | `Weapon` | Weapon changes |
| `Thought.ReactionUpdate` | seconds since the last tick | The character's reaction tick. See [Custom Tasks](Custom%20Tasks.md#deciding-and-acting). |
| `Stimulant.Pending` | the queued stimulants, most urgent first | Each reaction tick while any are queued |
| `State.Changed` | `Key`, `Old`, `New` | A registered state changed |
| `Configuration.ConfigurationUpdated` | `Path`, `Previous`, `Value`, `Type` | A config value changed. Prefer `Configuration:Observe`. |

[04_Enrage](Example%20Scripts/04_Enrage.luau) listens for `DamageTaken` and checks health once hurt. A payload's `Attacker` is a `Model`, so don't `print` it whole (it dumps the whole instance tree). Print its `Name`.

You can dispatch your own events with `base.Events:Dispatch("MyMod_Something", payload)` and let other mods on the same character subscribe. Prefix the name so it can't collide with a built-in.

---

## Doing things to the world

Mods never change instances through the Humanoid or the model. They ask the API, through `base.CharacterAPI`, or call a behavior function. The most useful `CharacterAPI` methods:

| Need | Call |
|---|---|
| Read health | `GetHealthInfo()` returns `{ Health, MaxHealth, Fraction }` for this character, or pass a model. Also `GetHealth()`, `GetMaxHealth()`. |
| Flash the character | `FlashHighlight({ FillColor, OutlineColor, Hold, FadeTime })` |
| A lasting glow | `CreateHighlight(name, options)` returns a `Highlight` with `SetFillColor`, `TweenFillTransparency`, `StartFlash`, `Destroy`. Also `GetHighlight`, `RemoveHighlight`. |
| An overhead bar | `CreateBar(name, options)` returns a `Bar` with `SetFill`, `StartFillFlash`, `Destroy`. Also `GetBar`, `RemoveBar`. |
| Find targets | `GetOpposingTargets()`, `GetSameTeamTargets()`, `GetAllTargets()`, `GetTargetsOfType(type)` |
| Distances | `GetDistanceTo(model)`, `GetDistanceToPosition(position)` |
| Team, status | `GetTeam()`, `IsExhausted(model?)`, `IsStaggered(model?)` |
| Hurt another character | `DealDamage(receiver, amount, damageType?, special?, maxStaggerTime?)`. Normally an attack does this. |
| Push | `ApplyImpulse`, `PushAway(target, force)` |

Bars and highlights come back as plain tables of closures (the same bindable-copy rule as mods), so call their methods with a colon and don't rely on a metatable.

For *behavior*, such as moving, dodging, blocking, spending stamina and playing animations, call the matching function through `base.Functions:CallFunction` so every other mod's hooks see it.

---

## Configuration and state

### Configuration

`base.Configuration` reads the values in the character's `ModNPC/Config` folder.

```luau
local reaction = base.Configuration:Get({ "ThoughtProcess", "ReactionSpeed" })   -- or "ThoughtProcess/ReactionSpeed"

-- Called with (newValue, previousValue) whenever it changes, including edits made in Studio while the game runs
local observer = base.Configuration:Observe("ThoughtProcess/ReactionSpeed", function(value, previous)
	print("reaction speed changed", previous, "->", value)
end)
```

`Get` returns `nil` for a value that doesn't exist, so a mod that depends on an optional value should provide a default. A `BoolValue` set to `false` comes back as `false`, not `nil`, so test for `== nil` when you mean "missing".

### Permissions

`Config/Permissions` is a folder of `BoolValue`s that switch core activities on and off. Use them to take an ability away from a character without hooking the function behind it. From a mod, change them with `base.Configuration:SetPermission(name, isPermitted)`. It goes through the API like every other change to the world, refuses names that aren't permissions, and returns `(set, reason)`. Editing the value in Studio while the game runs works too. `base.CharacterAPI` also has `GetPermission`, `GetPermissions` and `SetPermission`, which read and write the folder through the API without the cached read.

| Permission | Off means |
|---|---|
| `CanMove` | No walking or jumping (`CanMove` says no). Impulses such as knockback, launches and dodges still move the character. |
| `CanAttack` | No new attacks (`CanAttack` says no). The character still chases and holds its usual engage distance. |
| `CanSearchTargets` | No target searches. The targets already known, and the focus target, are kept as they are. |
| `CanThink` | The character is frozen. No task is dropped, but nothing on `base.Heartbeat` (the scheduler, the thought process, stamina, mods) is updated, and no reaction ticks come, until it is back on. |
| `CanDodge` | No dodging (`CanDodge` says no), which also rules out being evasive (strafing, `CanBeEvasive`). |
| `CanBlock` | No new guard (`CanBlock` says no). |
| `CanSprint` | `StartSprinting` is declined, and nothing is paid for it. |
| `CanBeStaggered` | Hits don't stagger the character (`Stagger` and `StaggerBackwards` are dropped from the hit). |
| `CanBeLaunched` | Hits don't launch the character. |
| `CanBeDamaged` | Hits take no health. They still land, are blocked or dodged, and are announced as usual. |
| `CanPerceive` | Stimulants from other characters are not taken in, so nothing is seen coming. |
| `CanReactToAttacks` | Incoming attack warnings are not acted on (no timed dodge or last moment guard). They are left to run out. |
| `CanFaceTarget` | `SetFocusTarget` doesn't turn the character toward anyone. `RemoveFocusTarget` still works. |
| `CanRegenerateStamina` | Stamina doesn't come back. |
| `CanSpeak` | Reserved. Dialogue has nothing that speaks yet. |

The names are in `TypePermissions.Names`. Some rules apply to every permission:

- **Only an explicit `false` forbids.** A permission the folder doesn't have, or one that isn't a `BoolValue`, allows its activity. A character made before a permission existed keeps behaving as it did.
- **They are read when an activity starts.** Turning one off never cuts short something already under way: a swing in progress finishes, and a guard that is up stays up. It only stops the next one.
- **A `Replace` hook outranks them.** The ability checks (`CanMove`, `CanAttack`, `CanDodge`, `CanBlock`) read the permission inside the original function, so a mod that replaces one of those functions decides for itself.

```luau
local TypePermissions = require(ServerScriptService.ModNPCServer.Types.v1.TypePermissions)
local Permissions = TypePermissions.Names

if base.Configuration:IsPermitted(Permissions.CanAttack) then ... end

-- Take the attacks away for five seconds. SetPermission goes through the API, and IsPermitted sees the change at once.
local set, reason = base.Configuration:SetPermission(Permissions.CanAttack, false)
if not set then
	warn("couldn't take the attacks away:", reason)
end
task.delay(5, function()
	base.Configuration:SetPermission(Permissions.CanAttack, true)
end)

-- Called with (isPermitted, wasPermitted) when it changes
base.Configuration:ObservePermission(Permissions.CanThink, function(isPermitted)
	print("thinking", isPermitted)
end)
```

The config **schema** is a sample in Studio (`ServerScriptService.ModAssets._v1_MODNPC_CONFIG`) that every character's config must match. Don't add a mod's settings to it, because that would make them mandatory for every NPC. Settings of a single mod can live as extra values in one character's own config, as attributes on the model (see [04_Enrage](Example%20Scripts/04_Enrage.luau), which reads `EnrageThreshold`), or as constants in the mod.

### Start tasks

`Config/StartTasks` lists the tasks a character begins with. Each child's **name** is a task name (the value is unused). A task registered by a mod can be listed there exactly like a built-in one. Mod `init` runs before start tasks are created, and start tasks are constructed with no arguments. See [Custom Tasks](Custom%20Tasks.md#registering-and-starting-a-task).

### State

`base.State` holds small named enums that describe what a character is doing (`MoveState`, `BlockState`, `StaggerState`, ...). Built-in keys and enums are in `TypeState`. A mod can read them and register its own:

```luau
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

if base.State:Is(TypeState.Keys.StaggerState, TypeState.StaggerStateEnum.Staggered) then ... end

-- A state of your own. The enum needs a None value, or pass the initial value explicitly.
local TauntEnum = table.freeze({ None = "None", Taunting = "Taunting" })
base.State:Register("TauntState", TauntEnum, TauntEnum.None)
base.State:Set("TauntState", TauntEnum.Taunting)   -- dispatches State.Changed when the value changes
```

`State:Get` returns `nil` for a key that isn't registered, so check before relying on another mod's state.

---

## Talking to other characters

Characters never read each other's state. If a mod wants another character to *know* something, it sends a **stimulant**: a named fact with a recipient, a priority and an expiry. The recipient queues it and decides on its own reaction tick what to do about it.

```luau
base:NewStimulant("Intimidated")
	:To(victim)                       -- or :ToGroup({ a, b }) / :ToAll()
	:WithPriority("Normal")           -- Low | Normal | High | Critical
	:Lasting(3)                       -- seconds it stays true
	:WithData({ Power = 25 })         -- plain data and instances only
	:Send()                           -- or :Emit() to get an id back, to retract it with CharacterAPI:RetractStimulant
```

On the receiving side, listen to `Stimulant.Pending` and consume what you act on:

```luau
base.Events:Subscribe(Events.Stimulant.Pending, function(pending)
	for _, stimulant in pending do
		if stimulant.Name == "Intimidated" then
			base.Functions:CallFunction(FE.ConsumeStimulant, stimulant.Id)
			-- react
		end
	end
end)
```

A stimulant that isn't consumed stays queued (and is announced again) until it expires. The built-in names (`IncomingAttack`, `SprintingTowards`, `BlockBroken`, `Exhausted`) are in `TypeStimulant.Names`. A mod's own stimulant has meaning only to characters whose mods react to it, so a feature like this needs the mod on both sides. [07_IntimidateTask](Example%20Scripts/07_IntimidateTask.luau) does both halves in one script.

---

## Lifetime and cleanup

- When the character dies, Base stops its scheduler (every running task is stopped) and stops watching the configuration. That is all. Your function and event subscriptions stay, and so do your own `task.delay` callbacks and any connections to outside signals (`RunService`, `workspace` events). Call `Unsubscribe` and disconnect on `Humanoid.Died` (see [01_Skeleton](Example%20Scripts/01_Skeleton.luau)), and check `base:IsAlive()` at the top of delayed code.
- Tasks stop automatically on death. Put per-task cleanup in the task's `Terminated` handler.
- A mod that is only needed for a moment can `Unsubscribe` its own hooks when it is done.

---

## Testing a mod

A mod runs inside the live character, so it can also be the test. Nothing outside the server can reach a `Base`, and a Studio command bar `require()` has its own module state. So the test goes in as a mod and the results come out as **attributes on the model**.

[08_TestHarness](Example%20Scripts/08_TestHarness.luau) is a template: wait for the character to settle, put it in a known state with the same functions the game uses, record a PASS/FAIL line per check, wrap everything in `pcall`, and always set the done flag. Read `TestLog` and `TestDone` from the model in the Explorer or from Studio MCP.

Practical notes:

- Use the sample NPC at `ServerStorage.CLAUDE_MODNPC` as the subject: clone it, add your mod to the clone's `ModNPC/Mods`, and start the clone with `API.startCharacter(clone)` from a server Script. Start two to see them interact. Never start or edit the original.
- Waiting 8 to 10 seconds before measuring lets startup, weapons and start tasks settle.
- Prefer `CallFunction` for setup so a test goes through the same path the game does. Reaching into `base.Damage` or `base.Attacks` is acceptable in a throwaway test when you want to drive one subsystem on purpose.
- Setting the Humanoid's `Health` directly is a test-only shortcut. It is treated as damage from "old NPC systems" and still dispatches `DamageTaken`, which makes it a quick way to put a character at low health. `Damage:DealSelfDamage` is a silent internal change and dispatches nothing.
- Remove test mods afterwards or they run on every playtest.

### Type-checking

From the project root (Git Bash), regenerate the sourcemap and analyze. This works on files outside `src/` too:

```
G="$APPDATA/Code/User/globalStorage/johnnymorganz.luau-lsp"
rojo sourcemap default.project.json --output "<somewhere outside the repo>/sourcemap.json"
luau-lsp analyze --definitions="$G/globalTypes.PluginSecurity.d.luau" --sourcemap="<somewhere outside the repo>/sourcemap.json" --flag:LuauSolverV2=true "docs/Mods/Example Scripts"
```

---

## Pitfalls

| Symptom | Cause |
|---|---|
| The mod's `init` never runs | The module returned a class or a table with a metatable, or `init` isn't directly on the returned table. Or it errored while being `require`d (look for `Failed to load mod script:`). |
| `Failed to initialize mod script:` | `init` errored. The rest of the character is fine. |
| `Function already has a replacement` | Two mods replace the same function. Only one `Replace` is allowed per function. |
| `Cannot subscribe to unknown behavior function` | A name that isn't in `FunctionEnum`. |
| A `Last` hook acts on a dodge that never happened | `First` and `Last` run even when the action is refused, and don't see the result. Check the state or the character instead. |
| An error appears in an unrelated task | A function hook errored, and function callbacks aren't `pcall`ed. |
| Nothing happens when a hook is added to `Dodge` etc. | The caller reached the module directly instead of through `CallFunction`. That is a framework bug. Report or fix it, don't work around it. |
| `attempt to index nil` reading `base.Humanoid.Health` | `base.Humanoid` is the Humanoid module. Use `base.CharacterAPI:GetHealthInfo()`. |
| The console floods with an instance dump | A payload field such as `Attacker` is a `Model`. Print its `Name`. |
| A mod reacts to a stimulant forever | The stimulant wasn't consumed (`ConsumeStimulant`). It is re-announced until it expires. |
| A task named in `StartTasks` doesn't start | The name wasn't registered by `base:RegisterTask` during `init`, or its constructor needs arguments. Start tasks are built with none. Look for `Auto start fail:`. |

---

## Example index

All in [Example Scripts](Example%20Scripts/). Each is a complete mod script.

| File | Shows |
|---|---|
| [01_Skeleton](Example%20Scripts/01_Skeleton.luau) | The minimum mod, subscribing to a function and an event, and cleaning up on death |
| [02_DodgeFlash](Example%20Scripts/02_DodgeFlash.luau) | A `Last` hook, checking state, `FlashHighlight` |
| [03_TankMode](Example%20Scripts/03_TankMode.luau) | A `Replace` hook that changes a decision |
| [04_Enrage](Example%20Scripts/04_Enrage.luau) | Events, health through `CharacterAPI`, highlights, functions, per-character tuning with an attribute |
| [05_FunctionTracer](Example%20Scripts/05_FunctionTracer.luau) | A debugging tool that hooks a list of functions |
| [06_TauntTask](Example%20Scripts/06_TauntTask.luau) | A custom task, a mod-owned state, starting a task from an event |
| [07_IntimidateTask](Example%20Scripts/07_IntimidateTask.luau) | A task that sends a stimulant, and the receiving side |
| [08_TestHarness](Example%20Scripts/08_TestHarness.luau) | A test that runs inside the live character and reports through attributes |
