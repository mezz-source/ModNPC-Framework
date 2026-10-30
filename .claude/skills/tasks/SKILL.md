---
name: tasks
description: Use when creating, modifying, or scheduling ModNPC runtime tasks (Task.luau, Scheduler.luau, CharacterTasks/*), including categories, resources, dependencies, policies, lifecycle, and starting tasks from Base. Use this whenever the user mentions tasks, the scheduler, CharacterTasks, TypeTask enums, or wants a new character behavior that runs over time (searching, chasing, attacking, wandering), even if they don't say "task".
---

# ModNPC tasks

A task is a per-character object that runs on the character's `Scheduler`
(`base.Scheduler`, aliased as `base.Tasks`). The scheduler ticks every running
task each Heartbeat and uses the task's **Policy** and **Resources** to decide
which tasks get stopped when a new one starts.

Sources of truth: `Behavior/v1/Base/Task.luau` (base class),
`Behavior/v1/Base/Scheduler.luau`, `Types/v1/TypeTask.luau` (enums and types),
and `Behavior/v1/Base/CharacterTasks/_EXAMPLE_TASK.luau` (template).

## Creating a task

1. Copy `CharacterTasks/_EXAMPLE_TASK.luau` to `CharacterTasks/<Name>.luau`.
   `CharacterTasks/init.luau` auto-registers every module there under its
   module name (skipping `_`-prefixed templates), so no registration edit is
   needed. The module must return a class with `new(base, ...)`.
2. Fill in the configuration using the `TypeTask` enums, never string literals
   (see below).
3. Implement `Start`, `Update`, and any helpers.
4. Add the task to `CharacterTasks` in `Types/v1/TypeBehavior.luau` so it
   type-checks (`MyTask: { new: TypeTask.TaskConstructor }`); see the
   `type-syncing` skill.

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local MyTask = {}
MyTask.__index = MyTask
setmetatable(MyTask, Task)

function MyTask.new(base, ...)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Movement,
		Resources = { ResourceEnum.Movement },
		Dependencies = { Dependencies.Configuration, Dependencies.Functions },
		Policy = TypeTask.Policy.Replace,
	})
	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, MyTask)
	self.Functions = base.Functions -- cache only what you declared
	return self
end
```

## Dependencies: declare every Base module you touch

A task must state, in `Dependencies`, every Base module it reads
(`base.Humanoid`, `base.Configuration`, ...). This is enforced, not stylistic:
`Task.new` checks each name exists on `base` and returns `nil, errorMessage` if
not, so a mod or reordered Base fails at construction instead of mid-`Update`
with a nil index. Rules:

- Use the `TypeTask.Dependencies` enum. Declared names must match actual
  access: if the code (including delayed/spawned callbacks) touches
  `base.Configuration`, `Configuration` is listed; if nothing touches it, remove
  it. Audit this whenever you edit a task.
- Tasks never touch behavior modules (`base.Movement`, `base.TargetSelector`,
  `base.Sound`, ...) directly. They declare `Dependencies.Functions` and call
  `self.Functions:CallFunction(FunctionEnum.X, ...)`; see the `functions` skill.
  Core handlers (`Configuration`, `Events`, `Scheduler`, `State`, `Assets`) and
  `CharacterAPI` are fine to use directly.
- `CharacterAPI` exists implicitly on every Base and is **not** declared.
- Duplicates and empty names are errors.
- Construction order matters. Dependencies are checked against `base` at
  `new` time, and Base builds `ThoughtProcess` after the scheduler and
  `CharacterTasks`. Tasks created from `Configuration:GetStartTasks()` run
  before `ThoughtProcess` is assigned, so a start-task depending on
  `ThoughtProcess` will fail to construct. Tasks created later (from events or
  thought logic) are fine.
- If a needed module is missing from `TypeTask.Dependencies`, add it to the
  enum (see "Extending the enums").

## Category, Resources, Policy: how scheduling works

**Category** (`TypeTask.CategoriesEnum`): what kind of task this is. Used only
for lookup: `Scheduler:GetTasks(category)` and `Scheduler:GetTask(category)`
(first match). It does not cause conflicts. Pick the group other code would
query by ("is something already Targetting?").

**Resources** (`TypeTask.ResourcesEnum`): the abstract things the task
consumes: body parts (`Arms`, `Legs`, `Neck`) or critical functions
(`Movement`, `Targetting`, `Weapon`). Resources are what the scheduler compares
for conflicts. Declare everything the task actually occupies, nothing more:
over-claiming makes unrelated tasks evict each other, under-claiming lets two
tasks fight over the same thing. A task may claim several resources, and
`Resources` may be empty for tasks that occupy nothing.

**Policy** (`TypeTask.Policy`): what happens to *other running tasks* when this
one starts (evaluated in `Scheduler:Start`, before `Task:Start`):

| Policy | Effect on already-running tasks |
| --- | --- |
| `Parallel` | Nothing stopped; coexists, even on shared resources. |
| `Replace` | Stops every running task whose `Resources` overlap this task's. |
| `Exclusive` | Stops **every** running task for this character. |

Stopped tasks get a reason string and fire `Terminated`. Policy is only
checked when the new task starts; a `Parallel` task never yields to a later
one, and two `Parallel` tasks sharing a resource will both run. Choose
`Replace` for anything that owns a resource (chasing, searching, attacking),
`Parallel` for passive/observer tasks, and `Exclusive` sparingly (stunned,
dying, cutscene-style states).

## Extending the enums

Prefer extending the enums over reusing a near-miss or typing a literal. Enums
in `TypeTask.luau` are the shared vocabulary that mods, the scheduler, and
queries rely on, and a literal `"Movment"` typo silently creates a new,
non-conflicting category or resource.

- New kind of task that others would query separately: add to
  `CategoriesEnum` (e.g. `Dodge = "Dodge"`).
- New thing a task can monopolize that no existing resource represents: add to
  `ResourcesEnum` (e.g. `Eyes = "Eyes"`). Don't reuse `Movement` for something
  that shouldn't conflict with movement.
- New Base module tasks may rely on: add to `Dependencies` only if it is
  really a field on `Base`; the value must equal the field name.
- Keys and values are identical strings, entries stay inside the
  `table.freeze({ ... })`, and add a one-line comment if the meaning is not
  obvious. Check for an existing entry first so there are no near-duplicates.
- Mention the enum addition when reporting your change; it is a shared API.

## Lifecycle

- `Start` calls `Task.Start(self)` first and returns its `false, error` if it
  fails; then does setup. A task can only start once.
- `Update(deltaTime)` begins with `if not self:IsRunning() then return end`.
  The scheduler pcalls it and stops the task with `"Update failed"` on error.
- `self:Complete(reason)` for natural completion, `self:Stop(reason)` for
  interruption/cleanup. Both are idempotent; do not fire `Terminated`
  yourself. Subscribe to `task.Terminated` to clean up connections.
- After any wait/yield, re-check `self.Running` before continuing.
- Do not keep references to `Base` or the character past termination; the
  scheduler clears its own `Base` on `Destroy`.
- Don't block or yield in `Update`; accumulate `deltaTime` for intervals (see
  `SearchForTargets`).

## Running a task

Constructors are Base-bound, so call them without `base`:

```luau
local task, createError = base.CharacterTasks.SearchForTargets.new()
if not task then
	warn("Task creation failed:", createError)
	return
end

local started, startError = base.Scheduler:Start(task)
if not started then
	warn("Task start failed:", startError)
end
-- later: base.Scheduler:Stop(task, "Interrupted")
```

Both `new` and `Scheduler:Start` return `nil, errorMessage` on failure, so
check each. Tasks that should begin with the NPC are named in the
configuration's start tasks (`Configuration:GetStartTasks()`), which Base
constructs and starts by name.

## Checklist before finishing

- Category, Resources, Dependencies use enum members; any new members were
  added to `TypeTask.luau`.
- Every `base.X` the task touches (except `CharacterAPI`) is in `Dependencies`,
  and nothing extra is listed.
- Policy matches intent and the resources are accurate.
- `Update` guards on `IsRunning`; completion/stop paths are covered.
- `TypeBehavior.CharacterTasks` includes the new task.
