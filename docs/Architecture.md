# ModNPC Framework: Architecture Walkthrough

This is a high-level walkthrough of how the ModNPC framework is put together: the goals it was built around, where the main pieces live, and how to extend or test a character without editing the framework itself. Each section has short code samples. For the details of a single subsystem (stamina, defense, disposition, stimulants...) read the module itself; this document explains how the pieces fit together.

```
src/server/
  init.server.luau          bootstrap: Core.init(), then API.startCharacter() for each "modnpc" model
  API/v1/                   the API layer: the only code that changes the world
    API.luau                request handler behind the Request BindableFunction
    Core.luau               loads every API module and hands them to API.init
    Modules/                Movement, Damage, Animation, Sound, VFX, Bars, Highlights, Stimulants,
                            ContentDelivery (config, assets, attacks, lines, mods), ...
  Behavior/v1/Base/         the behavior layer: one Base object per character
    init.luau               Base.new(character): builds every module, loads mods, starts tasks
    CharacterAPI.luau       the behavior layer's only door into the API
    Router.luau             sends a request over the bindable
    Functions.luau          named, hookable behavior functions (CallFunction)
    Events.luau             character-scoped events (Subscribe / Dispatch)
    ThoughtProcess.luau     the reaction tick
    Scheduler.luau, Task.luau, CharacterTasks/
    Stamina, Skills, Damage, Defense, Disposition, Attacks, Weapons, ...
  Types/v1/                 shared enums and types (FunctionEnum, event names, task enums, ...)
```

---

## 1. The goal

The framework aims for NPCs whose behavior is **data driven, hookable, and isolated**.

- **Data driven.** A character is a model that carries a `ModNPC` folder. That folder holds everything that makes the character itself and not some other NPC:

  ```
  <Character Model>
    ModNPC/
      Config/      values checked against the schema (ModAssets._v1_MODNPC_CONFIG): health, thought,
                   ranges, skills, stamina costs, disposition weights, StartTasks, ...
      Assets/      animations, sounds, VFX
      Attacks/     attack definitions
      Lines/       dialogue
      Mods/        ModuleScripts that hook or extend this character (section 5)
  ```

  The behavior code is the same for every character. Two NPCs fight differently because their `Config` differs: their reaction speed, their Agility, how aggressive their disposition weights make them, and which tasks they start with. Config is also live. `Configuration:Observe` lets a module react when a value changes in Studio while the game runs.

- **Hookable.** Every meaningful action a character takes (move, dodge, block, roll a skill, spend stamina, pick an attack, react to an incoming hit) is a *named function* that other code can run before, run after, or replace. Every notable occurrence (took damage, stamina exhausted, target spotted) is an *event* that anyone can listen to. That makes the mod system in section 5 possible.

- **Isolated.** All behavior code reaches the world through a single request channel, a `BindableFunction`. It never changes instances directly. The next section explains why this matters.

---

## 2. Communication: bindables, functions and events

The framework has three communication systems, and one way to read without communicating at all. Each does a different job.

| System | Scope | Returns a value? | Use it for |
|---|---|---|---|
| **API request** (`CharacterAPI` → `Router` → `ModFunctions.Request` bindable → `API`) | Behavior → API | Yes (`APIResponse`), unless fire-and-forget | Anything that touches the world |
| **Character handle** (`CharacterAPI:GetHandle`, `context.Handle`) | Behavior reading any character | Yes | Reading a character without a request: health, position, team, whether it can be targeted. Handles never change anything. See [Handles/Design.md](Handles/Design.md). |
| **Functions** (`base.Functions:CallFunction`) | Inside one character | Yes | Actions and queries that mods should be able to intercept |
| **Events** (`base.Events:Dispatch` / `Subscribe`) | Inside one character | No | Notifications that fan out to any number of listeners |

### API requests over the bindable

`CharacterAPI` wraps every primitive operation in a request table and sends it through `Router` to the `Request` BindableFunction in `ServerScriptService.ModFunctions`. On the other side, `API.luau` validates the request's shape, looks up the module and function, runs it under `pcall`, and checks that it returned a `ModuleResponse`.

```luau
-- Behavior side (CharacterAPI.luau). The behavior never touches the Humanoid itself.
function CharacterAPI:MoveTo(position: Vector3)
	self:RequestAPI(Modules.Movement, MovementFunctions.MoveTo, { self.Character, position }, true)
end

-- What actually crosses the bindable
{
	ModuleName = "Movement",
	Function = "MoveTo",
	Arguments = { character, position },
	NoResponse = true, -- fire and forget: the API defers the work and returns nothing immediately
}
```

Requests that need an answer (`RequestAPIData`) block until the API returns. Fire-and-forget requests (movement, most sounds) set `NoResponse`, and the API runs them with `task.defer`, which keeps them in order without blocking the caller.

**Bindables copy tables.** Tables that cross a BindableFunction are copied and lose their metatables. That's why API objects that a behavior holds onto (a `Bar`, a `Highlight`, an `AnimationHandle`) are built as **closure tables**. Their methods are plain functions that capture their state, so they still work after the copy. Don't return a metatable-based object from an API module.

### Functions

`Functions.luau` keeps a table of *main functions*, each bound to a Base module method (`Stamina.Spend`, `Damage.BeginBlock`, `Defense.ReactToIncomingAttack`, ...), keyed by `FunctionEnum`. `CallFunction` runs any subscriptions around the main function:

```
First subscribers  ->  Replace subscriber (if any) OR main function  ->  Last subscribers
```

- `First` and `Last` receive the same arguments and can't change the result.
- Only one `Replace` is allowed per function. If one exists, the main function doesn't run and the replacement's return value is used.
- The main functions are registered in `Base.new` *before* mod scripts load, so mods can subscribe to anything.

```luau
local FE = base.FunctionEnum

-- Ask how tired we are, through the function so a mod could intercept it
local efficiency = base.Functions:CallFunction(FE.GetStaminaEfficiency)

-- Pay for a dodge; false if we can't afford it
local paid = base.Functions:CallFunction(FE.PurchaseStamina, cost)
```

**Rule of thumb:** a Base module, task, or mod that needs another module's behavior goes through `CallFunction`. It doesn't call `base.Movement:Dodge()` directly. A direct call skips every hook, so a mod that replaced `Dodge` would never see it.

### Events

`Events.luau` is a character-scoped pub/sub. Dispatch is fire-and-forget. Each listener runs under `pcall`, so one failing listener can't break the others. A listener can be `once`, and can ask to run `First`.

```luau
local Names = require(STS.TypeCharacterEvents).Names

local subscription = base.Events:Subscribe(Names.Stamina.ExhaustionStarted, function(payload)
	print("out of breath at", payload.Stamina)
end)

-- later
subscription.Unsubscribe()
```

Event names live in `TypeCharacterEvents.Names` (Humanoid, Thought, Stimulant, Stamina, Combat, Targetting, ...), each with a comment describing its payload.

---

## 3. The API / behavior boundary

```
                     ┌──────────────────────────────────────────┐
  Behavior layer     │ Base (one per character)                 │
  (decides)          │  Tasks, ThoughtProcess, Stamina, Defense │
                     │  Functions / Events                      │
                     └───────────────┬──────────────────────────┘
                                     │ CharacterAPI:RequestAPI(...)
                                     ▼
                     ModFunctions.Request  (BindableFunction)
                                     │
                     ┌───────────────▼──────────────────────────┐
  API layer          │ API.luau → Modules/*                     │
  (does)             │  Movement, Damage, Animation, Sound, VFX │
                     │  Bars, Highlights, Stimulants, CDN, ...  │
                     └──────────────────────────────────────────┘
                                     │
                                  Workspace
```

**The behavior layer decides. The API layer acts.** Base gets a reference to the raw Humanoid only to *read* it and listen to its signals. The comment in `Base.new` says it: changing props directly "defeats the whole purpose of the character api."

Why this matters:

1. **One place validates and enforces.** The API checks the character is valid (and not `_UNLOADED`), the arguments are correct, and the operation is allowed. A bug in a task or a mod can't leave a Humanoid half-configured, because the task never had write access.
2. **Damage stays honest.** `Damage` tells *registered* damage (through the API) apart from health that changed for other reasons. That's how a block can absorb a hit, or a stagger can be applied. If behavior code set `Humanoid.Health` directly, that bookkeeping would break.
3. **Characters talk to each other through the API.** An attacker never reaches into its target's Base. It asks the API to deal damage, or to emit a stimulant, and the API delivers the result through the target's own binds (`ModNPC/_internal/_binds/CharacterFunction`, `CharacterEvent`, `CharacterStimulant`). Every character stays a sealed unit. Reading is the one exception to going through a request: the API hands out a read-only **handle** for each character it tracks, which answers without a round trip and without saying what kind of character is behind it. A handle reads and never writes, so changes still go through the API.
4. **The behavior is swappable.** Everything is versioned (`API/v1`, `Behavior/v1`, `Types/v1`), and the API only knows a character by its model and folder format. A different behavior implementation (or an adapter for some other NPC system later) can drive the same API without changes on the API side. Keep that boundary clean: no ModNPC-specific shortcuts in generic API modules.
5. **Errors are contained.** A failing API module returns an error response instead of crashing the caller. A failing task is stopped by the scheduler. A failing mod `init` logs a warning and the character still starts.

### Adding an API operation (sketch)

```luau
-- API/v1/Modules/Movement.luau: does the work, returns a ModuleResponse
function Movement.SetWalkSpeed(character: Model, speed: number): ModuleResponse
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return { Success = false, PassResponse = true, Message = "No humanoid" }
	end
	humanoid.WalkSpeed = speed
	return { Success = true, PassResponse = true }
end

-- Behavior/v1/Base/CharacterAPI.luau: the typed wrapper behavior code calls
function CharacterAPI:SetWalkSpeed(speed: number)
	self:RequestAPI(Modules.Movement, MovementFunctions.SetWalkSpeed, { self.Character, speed }, true)
end
```

Register the function name in `TypeAPIFunctions` too, so both sides agree on the string.

---

## 4. Where thinking lives

**There's no main loop.** No `while true do think() end` runs anywhere, and no central brain decides what the character does each frame. The thinking is spread across three things:

### 4.1 The reaction tick (`ThoughtProcess`)

A character has two update sources. `base.Heartbeat` is the frame clock: `Base` owns the character's only `RunService.Heartbeat` connection, and the scheduler, the thought process, stamina and mod scripts all listen there (`base.Heartbeat:Connect(function(deltaTime) ... end)`) instead of connecting to `RunService` themselves. It is destroyed when the character dies, and paused while `Config/Permissions/CanThink` is off, which freezes the character without dropping its tasks. The reaction tick below is the other source, the character's own pace. It runs off Heartbeat time, so it pauses too.

`ThoughtProcess` accumulates Heartbeat time. When the time passes the character's reaction speed, it dispatches one event:

```luau
-- ThoughtProcess:Update
if self.elapsedThoughtDt < self.currentReactionSpeed then
	return
end
local elapsed = self.elapsedThoughtDt
self.elapsedThoughtDt = 0
-- the next tick lands at ReactionSpeed + random(0, ReactionDeviation)
self.currentReactionSpeed = self.baseReactionSpeed + math.random() * self.reactionDeviation
self.Base.Events:Dispatch(ThoughtEvents.ReactionUpdate, elapsed)
```

`ReactionSpeed` and `ReactionDeviation` come from `Config/ThoughtProcess`. A slow, sluggish NPC and a sharp duelist run the same code with different numbers. Thinking happens at a human-like, jittered pace, not every frame.

`ReactionUpdate` is the "heartbeat of thought." Whatever needs to make a decision subscribes to it:

| Subscriber | What it decides on each reaction tick |
|---|---|
| `Stimulants` | Expires old stimulants and dispatches `StimulantsPending` with what's still queued |
| `Defense` | Consumes `IncomingAttack` stimulants and calls `ReactToIncomingAttack` (dodge, guard, or take it) |
| `Disposition` | Re-weighs the axes (Aggression, Guard, Evasiveness...) from factors like injury and stamina |
| `SearchForTargets` task | Looks for targets |
| `Engage` task | Raises or lowers the guard and picks strafes, retreats and sprints from the disposition |
| `AttackTargets` task | Decides whether to attack |

### 4.2 Perception (stimulants)

Characters don't read each other's state. When something happens that another character could react to (an attack winding up, a sprint toward someone, a guard breaking), the actor emits a **stimulant** through the API. Recipients queue it, and their own reaction tick decides whether and how to respond. This is how an NPC "sees an attack coming" without knowing anything about the attacker's internals.

### 4.3 Tasks

Ongoing behavior over time (chasing, holding spacing, attacking, blocking, being staggered) runs as tasks, covered next. Tasks are where most decisions about *what to do now* live. They make those decisions on reaction ticks and carry them out on Heartbeat updates in between.

The result: **thinking is reactive and decentralized.** Each piece listens for the signals it cares about, makes its own small decision, and acts through Functions. To change how a character thinks, you change or replace one of these pieces (often from a mod), not a giant decision function.

---

## 5. Why tasks matter

A task is a unit of behavior with a lifetime. `Task.new` takes:

- **Category**: what kind of task it is (`Movement`, `Attack`, `Engage`, `Block`, `Stagger`, ...).
- **Resources**: the abstract body parts or capabilities it occupies (`Movement`, `Arms`, `Legs`, `Neck`, `Weapon`, `Targetting`).
- **Policy**: what happens to running tasks when this one starts:
  - `Parallel`: runs next to whatever's running.
  - `Replace`: stops every running task that shares a resource with it.
  - `Exclusive`: stops everything.
- **Dependencies**: the Base modules it needs. They're checked at construction, so a task that can't work returns `nil, err` instead of failing halfway through.

The `Scheduler` (one per character) updates running tasks on Heartbeat, wraps each `Update` in `pcall` (a task that errors is stopped, the character keeps going), and destroys every task when the character dies.

Why this structure is important:

1. **Conflicts resolve themselves.** `Block` takes `Arms` with `Replace`. Raising the guard cuts off anything else using the arms, and an attack that needs the arms cancels the guard. No module has to know about every other module to avoid a two-handed collision.
2. **Interruptibility.** A stagger or launch is a task too. Starting it takes over the resources, so the character visibly loses control, then gets it back when the task ends.
3. **Guaranteed cleanup.** Termination is cooperative and signaled **once**, through `Terminated`. A task connects its cleanup there (give back state, stop animations), and that cleanup runs however the task ends: completed, replaced, broken, or killed by death.
4. **Composition.** Tasks start other tasks. `Engage` holds spacing by running its own `Walk` tasks for driving and strafing, and raises a `Block` task when its Guard axis calls for it. Small tasks combine into rich behavior.
5. **Data-driven startup.** `Config` lists `StartTasks`. `Base.new` constructs and starts them by name. Every `ModuleScript` in `CharacterTasks/` (except `_`-prefixed templates) gets a constructor at `base.CharacterTasks.<Name>`.

### A minimal task

```luau
-- CharacterTasks/Taunt.luau
local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum

local TauntTask = {}
TauntTask.__index = TauntTask
setmetatable(TauntTask, Task)

function TauntTask.new(base, duration: number?)
	local task, errorMessage = Task.new(base, {
		Category = TypeTask.CategoriesEnum.Movement,
		Resources = { TypeTask.ResourcesEnum.Arms },
		Dependencies = { TypeTask.Dependencies.Functions },
		Policy = TypeTask.Policy.Replace,
	})
	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, TauntTask)
	self.Functions = base.Functions
	self.remaining = duration or 2
	return self
end

function TauntTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- runs however we end: completed, replaced, or the character died
	self.Terminated:Connect(function()
		self.Functions:CallFunction(FunctionEnum.StopAnimation, "Taunt", 0.1)
	end)

	self.Functions:CallFunction(FunctionEnum.PlayAnimation, "Taunt", 0.1, nil, false)
	return true
end

function TauntTask:Update(deltaTime: number)
	if not self:IsRunning() then
		return
	end

	self.remaining -= deltaTime
	if self.remaining <= 0 then
		self:Complete()
	end
end

return TauntTask
```

```luau
-- Starting it from anywhere that has Base
local taunt, createError = base.CharacterTasks.Taunt.new(1.5)
if taunt then
	local started, startError = base.Scheduler:Start(taunt)
end
```

---

## 6. The mod system

Mods are how you **change a character's behavior without touching the framework.** They're also the most convenient way to **test** it.

### How mods load

1. `CharacterAPI:GetModScripts()` asks the ContentDelivery API module for the character's `ModNPC/Mods` folder.
2. Every `ModuleScript` under that folder (at any depth) is `require`d. Each one that returns a table with an `init` function is a mod script.
3. In `Base.new`, **after** every Base module is built and the main functions are registered, each mod's `init(base)` runs under `pcall`.

Load order is chosen so mods have the most reach:

```
build every Base module
  -> register main functions        (mods can now subscribe to any FunctionEnum)
  -> mod init(base)                 <-- your code runs here
  -> Attacks:Init, Defense:Init, Weapons:Init, Movement:InitDodges
                                    (so a mod can hook EquipWeapon before the first weapon goes on)
  -> start Config.StartTasks
```

A mod gets the full `base` object. It can subscribe to functions and events, start tasks, read state and config, and emit stimulants. It still goes through the same API boundary as everything else. Put mods in the character's own folder, so each NPC carries its own amendments.

### Amending behavior

**Run something before or after an action (`First` / `Last`):**

```luau
-- ModNPC/Mods/LoudDodges.luau
return {
	init = function(base)
		local FE = base.FunctionEnum
		base:SubscribeFunction(FE.Dodge, function(...)
			base.Functions:CallFunction(FE.PlaySoundCategory, "Grunt")
		end, base.SubscribeEnum.First)
	end,
}
```

**Replace an action outright (`Replace`):** this example is `examples/ExampleMod.luau`, which steals `MoveTo`:

```luau
local module = {}

function module.init(base)
	base:SubscribeFunction(base.FunctionEnum.MoveTo, function(position: Vector3)
		warn("Stole position", position)
	end, base.SubscribeEnum.Replace)
end

return module
```

**Replace a decision:** decisions are functions too, so a mod can give a character a whole new temperament. For example, a character that never dodges and always tanks hits:

```luau
return {
	init = function(base)
		base:SubscribeFunction(base.FunctionEnum.ReactToIncomingAttack, function(stimulant)
			return "None", "This one takes it on the chin"
		end, base.SubscribeEnum.Replace)
	end,
}
```

**React to events:** for example, flash red and enrage once badly hurt:

```luau
return {
	init = function(base)
		local Names = require(game.ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents).Names
		local enraged = false

		base.Events:Subscribe(Names.Combat.DamageTaken, function()
			if enraged or base.Humanoid.Health > base.Humanoid.MaxHealth * 0.3 then
				return
			end
			enraged = true
			base.CharacterAPI:FlashHighlight({ FillColor = Color3.new(1, 0, 0) })
			base.Functions:CallFunction(base.FunctionEnum.StartSprinting)
		end)
	end,
}
```

Things to keep in mind:

- Only **one** `Replace` per function. A second one is refused with a warning, and `SubscribeFunction` returns `nil, reason`.
- Function callbacks are **not** `pcall`ed by `CallFunction`, so an error in your hook surfaces in the caller. Event callbacks are `pcall`ed.
- Every subscription returns a handle. Call `Unsubscribe()` on it when your mod is done.
- A Replace must return what callers of the original expect. See the `FunctionCallbacks` types in `TypeBehavior` / `TypeCharacterFunctions`.

### Mods as test scripts

A mod runs **inside** the live character, with its real Base. That makes it the best way to test behavior end to end. (A Studio command bar `require()` gets a separate copy of module state and can't call the closure objects that crossed the bindable.) Drop a test mod into the character's `Mods` folder, play, and read the results back.

The pattern:

1. **Wait for the character to settle** (`task.wait` in a `task.spawn`, so `init` returns right away and startup isn't blocked).
2. **Put the character into a known state** using the same functions the game uses (`BreakStamina`, `RestoreStamina`, ...).
3. **Measure** through Functions, directly through a Base module, or by setting up a scene (a dummy target).
4. **Report** by writing results to an attribute on the model. Attributes can be read from outside the play session (from the Studio MCP or the Explorer), unlike a `print` buried in the output.
5. **Wrap the whole run in `pcall`** and always set a "done" flag, so a failed test still reports.

Here's an abridged version of a real test that checked how stamina exhaustion affects skill rolls, blocking, and attacks:

```luau
-- ModNPC/Mods/EfficiencyTest.luau  (temporary: remove after testing)
return { init = function(base)
	local STS = game.ServerScriptService.ModNPCServer.Types.v1
	local FE = require(STS.TypeCharacterFunctions).FunctionEnum
	local F = base.Functions

	-- results are collected as lines and published as an attribute
	local log = {}
	local function say(...) table.insert(log, string.format(...)) end
	local function flush() base.Character:SetAttribute("EffLog", table.concat(log, "\n")) end

	-- known states, reached through the same functions the game uses
	local function setStamina(n)
		-- Break leaves us at the exhaustion threshold (20); restore up from there
		F:CallFunction(FE.BreakStamina, "t")
		F:CallFunction(FE.RestoreStamina, n - 20, "t")
	end
	local function rested() F:CallFunction(FE.RestoreStamina, 1000, "t") end

	task.spawn(function()
		task.wait(10) -- let startup, weapons and start tasks settle

		pcall(function()
			-- SKILLS: single rolls, then a statistical success rate
			rested()
			local roll = F:CallFunction(FE.RollSkill, "Agility")
			say("SKILL rested target=%.2f eff=%.3f", roll.Target, roll.Efficiency)

			local function rate(n)
				local wins = 0
				for _ = 1, n do
					if F:CallFunction(FE.RollSkill, "Agility").Success then wins += 1 end
				end
				return wins / n
			end
			setStamina(65); local exhausted = rate(4000)
			rested(); local fresh = rate(4000)
			say("SKILL success over 4000: rested=%.3f exhausted(65)=%.3f", fresh, exhausted)
			flush()

			-- BLOCK: feed a synthetic hit straight into Damage while the guard is up
			local function blockTest(tag)
				F:CallFunction(FE.BeginBlock)
				local out = base.Damage:Receive({
					Attacker = nil, Receiver = base.Character, Amount = 20,
					DamageType = "Physical", Registered = true,
				})
				F:CallFunction(FE.EndBlock)
				say("BLOCK %s hit=20 -> through=%.2f", tag, out.Amount)
			end
			base.Humanoid.MaxHealth = 100000; base.Humanoid.Health = 100000 -- test-only shortcut
			rested(); blockTest("rested")
			setStamina(25); blockTest("exhausted(25)")
			flush()

			-- ATTACK: build a dummy in front of us and swing at it
			local dummy = Instance.new("Model"); dummy.Name = "TempDummy"
			local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Anchored = true
			local hum = Instance.new("Humanoid"); hum.MaxHealth = 100000; hum.Health = 100000
			hrp.Parent = dummy; hum.Parent = dummy; dummy.PrimaryPart = hrp
			hrp.CFrame = base.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -3)
			dummy.Parent = workspace

			rested()
			local before = hum.Health
			local ok, err = base.Attacks:Attack("Melee", dummy)
			task.wait(2)
			say("ATTACK rested started=%s %s dmg=%.2f", tostring(ok), tostring(err), before - hum.Health)
			dummy:Destroy()
		end)

		flush()
		base.Character:SetAttribute("EffDone", true)
	end)
end }
```

Run it, wait for `EffDone`, and read `EffLog`. Its shape looks like this (values depend on the character's config):

```
SKILL rested target=<n> eff=<n>
SKILL success over 4000: rested=<rate> exhausted(65)=<rate>
BLOCK rested hit=20 -> through=<n>
BLOCK exhausted(25) hit=20 -> through=<n>
ATTACK rested started=true nil dmg=<n>
```

Notes on writing test mods:

- **Prefer `CallFunction` for setup**, so you exercise the same path the game uses, hooks included. Reaching into a module directly (`base.Damage:Receive`, `base.Attacks:Attack`) is fine in a test when you deliberately want to bypass the decision layer and drive one subsystem.
- **Large sample counts** (thousands of `RollSkill` calls) turn a probabilistic rule into a number you can check.
- **Setting Humanoid props directly** (the `MaxHealth` line above) breaks the API boundary. That's acceptable in a throwaway test and never acceptable in a real mod.
- **Clean up.** Destroy dummies you create, and remove the test mod from `Mods` when you're done, or it runs on every playtest.
- Only workspace models whose name contains `modnpc` are started automatically by `init.server.luau`. A test that needs an opponent has to start one with `API.startCharacter(model)`.

---

## 7. Summary

- **Characters are data.** The `ModNPC` folder (Config, Assets, Attacks, Lines, Mods) defines a character. Behavior code is shared.
- **Behavior decides, the API acts.** The only path to the world is a request over the `Request` BindableFunction. That keeps validation in one place, damage accounting honest, characters sealed from one another, and the behavior layer swappable.
- **Functions are the hook points; events are the notifications.** Route cross-module calls through `CallFunction` so mods see them.
- **There's no main loop.** Thinking happens on jittered reaction ticks (`ReactionUpdate`), driven by stimulants from other characters, inside tasks and reactive modules.
- **Tasks own the body.** Categories, resources and policies resolve conflicts. `Terminated` guarantees cleanup. Tasks compose into larger behavior, and `StartTasks` in Config decides what a character does on startup.
- **Mods amend anything and test everything.** A ModuleScript with `init(base)` in `ModNPC/Mods` can prepend to, append to, or replace any behavior function, listen to any event, and drive the live character as a test harness.

---

## 8. Project statistics

A snapshot taken on 2026-10-30 at commit `3c160c6`. It counts tracked files plus untracked files that aren't ignored. The `.rbxlx` place file and `sourcemap.json` are not included. The construct counts come from grep, so treat them as approximate.

### Luau source

| Metric | Count |
|---|---|
| Files | 97 (no plain `.lua` files) |
| Total lines | 19,819 |
| Code lines | 14,947 (75%) |
| Comment lines | 1,879 (9.5%) |
| Blank lines | 2,993 (15%) |
| Average lines per file | ~204 |

### By area

| Folder | Files | Lines |
|---|---|---|
| `src/server/Behavior` | 44 | 10,752 |
| `src/server/API` | 23 | 6,252 |
| `src/server/Types` | 26 | 2,472 |
| `src/server/Util` | 2 | 298 |
| `src/server` (root) | 1 | 19 |
| `examples` | 1 | 26 |

The Behavior layer includes 12 CharacterTasks and 4 Animation modules.

### Largest files

| File | Lines |
|---|---|
| [Damage.luau](src/server/Behavior/v1/Base/Damage.luau) | 874 |
| [Disposition.luau](src/server/Behavior/v1/Base/Disposition.luau) | 760 |
| [TypeBehavior.luau](src/server/Types/v1/TypeBehavior.luau) | 710 |
| [CharacterAPI.luau](src/server/Behavior/v1/Base/CharacterAPI.luau) | 698 |
| [CharacterUtility.luau](src/server/API/v1/Modules/CharacterUtility.luau) | 658 |
| [Engage.luau](src/server/Behavior/v1/Base/CharacterTasks/Engage.luau) | 610 |
| [ConfigurationNetwork.luau](src/server/API/v1/Modules/ContentDelivery/ConfigurationNetwork.luau) | 555 |
| [Stamina.luau](src/server/Behavior/v1/Base/Stamina.luau) | 536 |

The smallest file is [TypeTeams.luau](src/server/Types/v1/TypeTeams.luau) at 7 lines.

### Code constructs

| Construct | Count |
|---|---|
| `function` keywords | 1,272 |
| Type declarations | 224 (149 `export type`) |
| `require(` calls | 318 |
| `CallFunction` uses | 137 |
| TODO/FIXME markers | 4 |
| `--!strict` / `--!nonstrict` directives | 0 |

### Other files

- **Markdown:** 18 files, 2,318 lines, about 17.2k words
- **Config:** 3 JSON files and 1 TOML file

### Git history

- 3 commits between 2026-10-03 and 2026-10-30
- 22,394 lines added and 681 deleted
