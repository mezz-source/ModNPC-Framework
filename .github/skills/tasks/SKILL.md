---
name: tasks
description: Use when creating or modifying ModNPC runtime tasks, including dependencies, resources, policies, lifecycle, and predefined character task constructors.
---

# ModNPC tasks

Tasks are per-character runtime objects managed by the character's scheduler.
They must declare the Base modules they require, the scheduler resources they
claim, a category, and a scheduling policy.

## Required task structure

Create predefined tasks under
`src/server/Behavior/v1/Base/CharacterTasks/`. Derive from the base task class
and pass a complete configuration:

```luau
local taskObject, errorMessage = Task.new(base, {
	Category = "Movement",
	Resources = { "Movement" },
	Dependencies = { "Humanoid", "Movement" },
	Policy = TypeTask.Policy.Replace,
})
if not taskObject then
	return nil, errorMessage
end

local self = setmetatable(taskObject, MyTask)
```

`Dependencies` are names looked up directly on `Base`. Task construction must
fail with `nil, errorMessage` when a dependency is absent; do not defer this
check until `Start` or `Update`. This keeps modding failures close to the task
definition and prevents partially valid tasks from entering the scheduler.

## Lifecycle rules

- `Start` should call `Task.Start(self)` before doing work.
- `Update(deltaTime)` must return immediately when `self:IsRunning()` is false.
- Use `self:Complete(reason)` for natural completion.
- Use `self:Stop(reason)` for interruption and cleanup.
- Do not fire termination signals directly; the base class makes termination
  idempotent.
- Long-running work must observe `self.Running` after waits/yields and stop
  cleanly when cancellation is requested.
- Avoid retaining character or Base references after scheduler destruction.

## Resources and policies

- Resources describe scheduler conflicts, such as `"Movement"` or `"Attack"`.
- `Parallel` permits coexistence.
- `Replace` stops active tasks with overlapping resources.
- `Exclusive` stops every active task for that character.
- Category is metadata and lookup grouping; it is not a replacement for
  resource declarations.

## Constructor and usage

Expose tasks from `CharacterTasks/init.luau` with a Base-bound constructor:

```luau
local taskObject, errorMessage = base.CharacterTasks.JumpTask.new()
if taskObject then
	base.Tasks:Start(taskObject)
else
	warn("Task creation failed:", errorMessage)
end
```

Keep task dependencies synchronized with actual Base access. If a task reads
`base.Humanoid` or `base.Movement`, both names belong in `Dependencies`, even
when the access occurs inside a spawned or delayed callback.
