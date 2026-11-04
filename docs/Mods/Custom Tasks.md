# Custom Tasks

A task is a piece of behavior with a lifetime: chasing a target, holding spacing, swinging an attack, being staggered, taunting. Anything that runs over time, takes over part of the character's body while it runs, and has to give it back cleanly is a task.

This guide shows how to write one in a mod script, register it, start it, and use the core systems from inside it. Read [Mod Scripts](Mod%20Scripts.md) first for how mods load and what `base` offers. [Architecture](../Architecture.md) explains why tasks exist. The examples are files in [Example Scripts](Example%20Scripts/) that have been run on live characters:

- [06_TauntTask](Example%20Scripts/06_TauntTask.luau): occupies the body, locks movement, owns a state, starts from an event and from `StartTasks`
- [07_IntimidateTask](Example%20Scripts/07_IntimidateTask.luau): occupies nothing, notices it should stop, affects another character with a stimulant

- [Do you need a task?](#do-you-need-a-task)
- [Anatomy](#anatomy)
- [Category, resources, policy](#category-resources-policy)
- [Dependencies](#dependencies)
- [Lifecycle](#lifecycle)
- [Registering and starting a task](#registering-and-starting-a-task)
- [Using core systems from a task](#using-core-systems-from-a-task)
- [Deciding and acting](#deciding-and-acting)
- [Composing tasks](#composing-tasks)
- [Pitfalls](#pitfalls)

---

## Do you need a task?

Use the lightest tool that does the job.

| You want to... | Use |
|---|---|
| Run code before or after an action, or change what an action does | A function hook (`First` / `Last` / `Replace`) in a [mod script](Mod%20Scripts.md#hooking-behavior-functions) |
| React once to something that happened | An [event](Mod%20Scripts.md#listening-to-events) listener |
| Do something that lasts, holds part of the body, must be interrupted by other behavior, or needs guaranteed cleanup | **A task** |

A task is worth the ceremony when two behaviors must not run at once (a taunt and a chase both want the legs), or when something must be undone however it ends (a lock released, an animation stopped, a state reset).

---

## Anatomy

A task is a class that inherits from `base.Task`. A mod builds it from `base.Task` and `base.TaskEnums` so it never has to require framework paths. Because those come from the character's `base`, the class is built inside a function that receives it:

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

type Base = TypeBehavior.Base

local function createMyTaskClass(base: Base)
	local Enums = base.TaskEnums
	local ParentTask: any = base.Task

	local MyTask: any = {}
	MyTask.__index = MyTask
	setmetatable(MyTask, ParentTask)

	-- The first parameter is always the character's Base, then whatever your task needs
	function MyTask.new(taskBase: Base, duration: number?)
		local task, errorMessage = ParentTask.new(taskBase, {
			Category = Enums.CategoriesEnum.Movement,
			Resources = { Enums.ResourcesEnum.Movement },
			Dependencies = { Enums.Dependencies.Functions },
			Policy = Enums.Policy.Replace,
		})
		if not task then
			return nil, errorMessage          -- constructors fail with nil, reason
		end

		local self = setmetatable(task, MyTask)
		self.Functions = taskBase.Functions   -- cache only what you declared as a dependency
		self.Duration = duration or 2
		self.Elapsed = 0
		return self
	end

	function MyTask:Start()
		local started, errorMessage = ParentTask.Start(self)   -- always first
		if not started then
			return false, errorMessage
		end

		-- cleanup that must happen however the task ends
		self.Terminated:Connect(function(reason)
			-- give back whatever Start took
		end)

		-- take over whatever the task needs
		return true
	end

	function MyTask:Update(deltaTime: number)
		if not self:IsRunning() then
			return
		end

		self.Elapsed += deltaTime
		if self.Elapsed >= self.Duration then
			self:Complete("Done")
		end
	end

	return MyTask
end
```

This is the same shape as the built-in tasks in `src/server/Behavior/v1/Base/CharacterTasks/` (`_EXAMPLE_TASK.luau` is the template, `Walk.luau` is a small real one). The only difference is how the parent class is reached: built-in tasks `require` it by path, mods use `base.Task`.

What the parent class gives you:

| Member | Meaning |
|---|---|
| `self.Base` | The character's Base. |
| `self.Running` / `self:IsRunning()` | True between a successful `Start` and `Stop` / `Complete`. |
| `self.Completed` | True once it has ended (by any path). A task runs once and can't be restarted. |
| `self.Terminated` | A signal fired **once** with the reason string when the task ends. Connect cleanup here. |
| `self:Stop(reason?)` | End it early (interrupted, cancelled). Fires `Terminated`. |
| `self:Complete(reason?)` | End it because it finished (`Stop` with the reason `"Completed"` by default). |
| `self.Category`, `self.Resources`, `self.Policy`, `self.Dependencies` | What the constructor was given. |
| `self:Cancel(reason?, data?)` | End it because something takes the character over. Defaults to `Stop`; override it if being taken over needs a different ending. The scheduler's bulk stops call this. |
| `self.Essential` | True for a task that runs a must-keep-going part of the logic (see below). |

Both `Stop` and `Complete` are safe to call more than once. Never fire `Terminated` yourself.

---

## Category, resources, policy

These three are how tasks coexist.

**Category** is the kind of task. It is only used for lookup (`base.Scheduler:GetTask(category)` and `GetTasks(category)`), never for conflicts. Pick the group other code would ask about.

**Resources** are the abstract parts of the character the task occupies: the body parts `Arms`, `Legs`, `Neck`, and the capabilities `Movement`, `Weapon`, `Targetting`. Only these decide conflicts. Declare everything the task really occupies and nothing more: too much and unrelated tasks evict each other, too little and two tasks fight for the same thing. An empty list is valid.

**Policy** decides what happens to the tasks that are *already running* when this one starts:

| Policy | Effect |
|---|---|
| `Parallel` | Nothing is stopped. Coexists even on shared resources. |
| `Replace` | Every running task whose resources overlap this one's is stopped (reason `"Replaced by resource-conflicting task"`). |
| `Exclusive` | Every running task is stopped. Use sparingly (stunned, dying, cutscenes). |

The policy is checked **once, when the task starts.** A `Parallel` task never yields to a later one, and two `Parallel` tasks that share a resource both run. A `Replace` task evicts the others but isn't protected from being evicted itself by a later `Replace`.

### Essential tasks and stopping tasks in bulk

Give the constructor `Essential = true` for a task that runs an essential part of the character's logic (the built-in target search, chase and attack drivers are). It is optional and defaults to `false`.

To end every task of a category or resource, ask the scheduler instead of looping over `GetTasks` yourself:

```luau
base.Scheduler:StopCategory(Enums.CategoriesEnum.Movement, "Why")
base.Scheduler:StopResource(Enums.ResourcesEnum.Arms, "Why")
base.Scheduler:StopTasks({ Categories = { "Taunt", "Block" }, Resources = { "Legs" } }, "Why")
base.Scheduler:StopAll("Why")
```

Each returns how many tasks ended and calls the tasks' `Cancel`. **Essential tasks are skipped.** To end them too, pass `{ CancelEssentials = true }` as the last argument; do that only to take the whole character down. `{ CancelData = x }` is handed to each `Cancel` as its second argument. Stopping one task you hold is still `Scheduler:Stop(task, reason)`.

Among the policies, `Exclusive` also leaves essential tasks running, while `Replace` still ends a resource-conflicting task even if it is essential.

The values come from `base.TaskEnums`:

```luau
Enums.CategoriesEnum   -- Targetting, Movement, Attack, Engage, Block, Stagger
Enums.ResourcesEnum    -- Movement, Arms, Legs, Neck, Weapon, Targetting
Enums.Policy           -- Parallel, Replace, Exclusive
Enums.Dependencies     -- see below
```

These tables are frozen, so a mod can't add to them. The constructor checks only that a category and each resource is a non-empty string, so a mod may use its own (`Category = "Taunt"`). Two things to keep in mind. Conflicts match strings exactly, so a typo creates a resource nothing else uses. And to conflict with built-in behavior you must use the built-in resource names, which is why the enums are better when one fits. [06_TauntTask](Example%20Scripts/06_TauntTask.luau) takes `Movement` and `Arms` with `Replace`: starting a taunt cuts off a walk, chase or guard, and a later attack that needs the arms cuts off the taunt.

---

## Dependencies

`Dependencies` lists the Base modules the task touches directly. The constructor checks that each exists on `base` and returns `nil, "Task dependency is missing from Base: X"` if not, so a task that can't work fails at construction and not halfway through an `Update`.

Rules:

- Declare **every** `base.X` the task reads (including inside delayed callbacks), and nothing it doesn't. Use the `Enums.Dependencies` members.
- `CharacterAPI` exists on every Base and is never declared.
- Names must be non-empty and unique.
- Reach behavior modules (`Movement`, `Sound`, `Animation`, `Stamina`, `TargetSelector`, ...) through `Dependencies.Functions` and `CallFunction`, not by declaring the module. A direct call skips every mod's hooks. The core handlers are fine to use directly: `Configuration`, `Events`, `State`, `Scheduler`, `CharacterTasks`, `Assets`.

---

## Lifecycle

```
CharacterTasks.X.new(...)            construct, dependencies checked          returns task, or nil + reason
Scheduler:Start(task)                evicts conflicting tasks per Policy,
                                     then calls task:Start()                  returns task, or nil + reason
  task:Update(dt)                    every Heartbeat while running
  ... Complete(reason) / Stop(reason) / evicted / character died
Terminated fires once                your cleanup runs
```

- **`Start`** calls `ParentTask.Start(self)` first and returns its `false, reason` if it refuses. Then it takes what the task needs and connects its cleanup to `Terminated`. If you skip the parent call the task never becomes `Running`, and the scheduler silently drops it on its next update.
- **`Update(deltaTime)`** begins with `if not self:IsRunning() then return end`. The scheduler calls it inside a `pcall`: if it errors, the scheduler warns `Task update failed:` and stops the task with the reason `"Update failed"`. Never yield in `Update`; accumulate `deltaTime` for timers.
- **Ending.** `Complete` is for finishing, `Stop` for interrupting. Either way `Terminated` fires with the reason. The scheduler also stops a task that is evicted, and every task when the character dies (`"Scheduler destroyed"`).
- **Cleanup belongs in `Terminated`.** It runs for every way the task can end, including ones you didn't write code for. The `Terminated` handler in the taunt releases the movement lock, resets its state and removes its glow. Whatever `Start` took, `Terminated` gives back.
- After any wait or yield inside a task's own callbacks, check `self.Running` before continuing.

---

## Registering and starting a task

Mod scripts can't add files to the `CharacterTasks` folder, so they register the class from `init`:

```luau
function module.init(base: Base)
	local registered, errorMessage = base:RegisterTask("Taunt", createTauntClass(base))
	if not registered then
		warn("could not register Taunt:", errorMessage)   -- the name is taken, or the class has no `new`
		return
	end
end
```

`RegisterTask` makes the task available as `base.CharacterTasks.Taunt`, with the `base` argument filled in for you, so callers pass only the rest:

```luau
local taunt, createError = base.CharacterTasks.Taunt.new(2)      -- duration = 2
if not taunt then
	warn("could not create:", createError)
	return
end

local started, startError = base.Scheduler:Start(taunt)
if not started then
	warn("could not start:", startError)
end

-- later, if you need to end it
base.Scheduler:Stop(taunt, "Interrupted")
```

Both `new` and `Scheduler:Start` return `nil, reason` on failure, so check each. `Scheduler:Start` evicts conflicting tasks *before* it calls the new task's `Start`. A task whose `Start` then refuses has still cleared the way.

Built-in task names can't be shadowed: registering a name that exists returns `false, "A task is already registered as X"`.

### Starting automatically

`Config/StartTasks` lists the tasks a character begins with. Each child's **name** is the task name (the `StringValue`'s value is unused). Mod `init` runs before start tasks are created, so a mod task can be listed there like a built-in one. Add a child named `Taunt` to one character's `StartTasks` and it starts at spawn.

Start tasks are constructed with **no arguments**, so the constructor needs defaults for everything (the taunt's `duration or 2`). A task that needs arguments is started from code instead.

### Starting from code

The usual triggers are:

- **An event.** The taunt starts when a target is first spotted, with a cooldown (`Events.Targetting.TargetSpotted`). The intimidate starts when one of the character's hits lands (`Events.Combat.AttackLanded`).
- **A reaction tick.** A decision made in `Thought.ReactionUpdate` (see [Deciding and acting](#deciding-and-acting)).
- **Another task.** See [Composing tasks](#composing-tasks).

Check `base:IsAlive()` and whatever else should gate the start before you create the task, and use a cooldown for anything an event can fire repeatedly.

---

## Using core systems from a task

Everything below is used by the example tasks. Cache each declared module in `new` (`self.Events = taskBase.Events`, `self.State = taskBase.State`, ...) as the examples do.

**Functions: the main channel.** Declare `Dependencies.Functions` and call `self.Functions:CallFunction(FunctionEnum.X, ...)`. [06_TauntTask](Example%20Scripts/06_TauntTask.luau) calls `StopMoving`, `LockMovement` and `UnlockMovement`. [07_IntimidateTask](Example%20Scripts/07_IntimidateTask.luau) asks `IsStaggered`. `LockMovement` and `SetWalkDirection` take a *source*: pass the task itself (`self`), and release with the same source in `Terminated`.

**State.** Declare `Dependencies.State`. Register a state of your own in `init` (once, not per task), then `Set` it in `Start` and back in `Terminated`. Other mods can read it and listen to `State.Changed`. Reading built-in states (`StaggerState`, `BlockState`, ...) is also fine.

**Events.** Declare `Dependencies.Events`. A subscription made in `Start` must be undone in `Terminated`, or it outlives the task:

```luau
function MyTask:Start()
	...
	local subscription = self.Events:Subscribe(Names.Combat.DamageTaken, function(payload)
		self:Stop("Hurt")
	end)
	self.Terminated:Connect(function()
		subscription.Unsubscribe()
	end)
	return true
end
```

**Configuration.** Declare `Dependencies.Configuration`. `self.Configuration:Get("Section/Key")` for a value, `Observe` to follow edits. Read live values each time they are needed instead of caching them in `new`, so Studio edits apply.

**CharacterAPI.** Implicit. Bars, highlights, sounds, stimulants, health and targets. The taunt creates a highlight in `Start` and removes it in `Terminated`. Remember that a bar or highlight is a table of closures and keeps working after it crosses the bindable.

**Stimulants.** Describe and send with `self.Base:NewStimulant(name):To(...):Lasting(...):Send()`. The intimidate task sends one after its windup. The receiver side is an event listener in the mod (`Stimulant.Pending`), not part of the task.

**Other tasks.** `self.Scheduler:GetTask(category)` and `GetTasks(category)` answer "is something already attacking?" (declare `Dependencies.Scheduler`). Use them to guard a start: a taunt that starts only if no `Attack` task is running.

---

## Deciding and acting

A task works at two speeds.

- **`Update(deltaTime)`** runs every Heartbeat. Use it for timers, smooth movement, and checks that must be responsive. Keep it cheap.
- **The reaction tick** (`Names.Thought.ReactionUpdate`) fires at the character's jittered reaction speed (`Config/ThoughtProcess`, around 0.3 seconds by default). Use it for *decisions*: whether to attack, retreat, change plans. Making decisions every frame would give inhumanly perfect reactions and costs far more.

The pattern the built-in tasks use is to decide on the tick and carry it out in `Update`:

```luau
function MyTask:Start()
	...
	local subscription = self.Events:Subscribe(Names.Thought.ReactionUpdate, function()
		if not self:IsRunning() then
			return
		end
		self.WantsToRetreat = self:_shouldRetreat()    -- the decision
	end)
	self.Terminated:Connect(function()
		subscription.Unsubscribe()
	end)
	return true
end

function MyTask:Update(deltaTime)
	if not self:IsRunning() then
		return
	end
	if self.WantsToRetreat then                         -- the action, every frame
		self.Functions:CallFunction(FunctionEnum.MoveBackward)
	end
end
```

For decisions that depend on the character's mood, ask `GetDisposition`, `GetEngageDistance` and friends through `CallFunction`.

---

## Composing tasks

A task can run other tasks. `Engage` drives and strafes by starting `Walk` tasks, and raises a `Block` task when it wants a guard. To do the same, declare `Dependencies.CharacterTasks` and `Dependencies.Scheduler`:

```luau
function MyTask:Start()
	...
	local walk = self.CharacterTasks.Walk.new("Left", 0.5)     -- direction, seconds
	if walk then
		self.SubTask = self.Scheduler:Start(walk)
	end
	self.Terminated:Connect(function()
		if self.SubTask then
			self.Scheduler:Stop(self.SubTask, "Parent ended")
		end
	end)
	return true
end
```

Stop anything you started from `Terminated`, or it outlives you. Built-in constructors and their arguments are listed in `TypeBehavior.CharacterTasks`.

---

## Pitfalls

| Symptom | Cause |
|---|---|
| The task starts but does nothing, then vanishes | `Start` didn't call `ParentTask.Start(self)`, so `Running` never became true. |
| `Task dependency is missing from Base: X` | A dependency name that isn't a field on `base`. Use the `Enums.Dependencies` members. |
| `A task is already registered as X` | The name is taken by a built-in task or another mod. |
| `Auto start fail: unknown task X` | The name in `StartTasks` was never registered (a typo, or the mod isn't on that character). |
| `Auto start fail: could not create X` | The constructor needs arguments, but start tasks are created with none. |
| `Task update failed: ...` | `Update` errored. The scheduler stopped the task. Fix the error. |
| A lock, state or animation stays on after the task | The cleanup is in `Update` or `Complete` instead of `Terminated`. Only `Terminated` runs for every way a task can end. |
| A listener keeps firing after the task ended | A subscription made in `Start` wasn't unsubscribed in `Terminated`. |
| The character freezes mid-fight | The task's `LockMovement` was never released, or its `Terminated` handler errored before reaching the unlock. Put the unlock first. |
| Tasks keep evicting each other | Resources over-claimed, or `Replace` used where `Parallel` fits. |
| Two tasks fight over the legs | Resources under-claimed. |
| `Update` stalls the whole character | It yielded (`task.wait`). Accumulate `deltaTime` instead. |
| The task ignores a Studio config edit | The value was cached in `new`. Read it when needed or use `Configuration:Observe`. |
| `CharacterTasks.X.new(base, ...)` misbehaves | The registered constructor already supplies `base`. Call `new` with only the task's own arguments. |

---

## Checklist

- `Category`, `Resources`, `Policy` come from the enums, and the resources are exactly what the task occupies.
- Every `base.X` the task touches (except `CharacterAPI`) is in `Dependencies`, and nothing extra is.
- Behavior goes through `CallFunction`.
- `Start` calls the parent's `Start` first and connects cleanup to `Terminated`.
- `Update` guards on `IsRunning`, never yields, and has a path to `Complete`.
- Everything `Start` took (locks, states, highlights, subscriptions, subtasks) is given back in `Terminated`.
- The constructor works with no arguments if the task will be listed in `StartTasks`.
