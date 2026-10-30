local TypeTask = {}

export type Policy = "Exclusive" | "Replace" | "Parallel"

-- These are the groups tasks are defined by
-- This is what is directly impacted by the policy
TypeTask.CategoriesEnum = table.freeze({
	Targetting = "Targetting",
	Movement = "Movement",
	Attack = "Attack",
	-- Holds the spacing to the target once we are close enough to it (ChaseTargets takes us there)
	Engage = "Engage",
	-- Guarding with the arms, absorbing the hits that come in until it ends or breaks
	Block = "Block",
	-- Staggered, the character has no control of itself until it ends
	Stagger = "Stagger",
})

-- These are abstract resources a task need to operate
-- They can be body groups or critical functions like movement and targetting
TypeTask.ResourcesEnum = table.freeze({
	Movement = "Movement",
	Arms = "Arms",
	Legs = "Legs",
	Neck = "Neck",
	Weapon = "Weapon",
	Targetting = "Targetting"
})

-- These are various base modules a task might need to function
-- CharacterAPI implicitly exists and does not need to be declared
-- Tasks reach behavior modules (Movement, TargetSelector, Sound, Animation, ...) through Functions, so declare
-- Functions rather than the module itself.
TypeTask.Dependencies = table.freeze({
	Configuration = "Configuration",
	Dialogue = "Dialogue",
	Distance = "Distance",
	Humanoid = "Humanoid",
	Movement = "Movement",
	ThoughtProcess = "ThoughtProcess",
	Assets = "Assets",
	CharacterTasks = "CharacterTasks",
	Events = "Events",
	Functions = "Functions",
	Router = "Router",
	Scheduler = "Scheduler",
	State = "State",
	TargetSelector = "TargetSelector",
	Task = "Task"
})

export type Task = {
	Resources: { string },
	Dependencies: { string },
	Category: string,
	Policy: Policy,
	Running: boolean,
	Completed: boolean,
	Terminated: any,
	Start: (self: Task) -> (boolean, string?),
	Update: (self: Task, deltaTime: number) -> (),
	Stop: (self: Task, reason: string?) -> boolean,
	IsRunning: (self: Task) -> boolean,
}

export type Scheduler = {
	Start: (self: Scheduler, task: Task) -> (Task?, string?),
	Stop: (self: Scheduler, task: Task, reason: string?) -> boolean,
	GetTasks: (self: Scheduler, category: string?) -> { Task },
	GetTask: (self: Scheduler, category: string) -> Task?,
	Destroy: (self: Scheduler) -> (),
}

export type TaskConstructor = (duration: number?) -> (Task?, string?)

TypeTask.Policy = table.freeze({
	Exclusive = "Exclusive",
	Replace = "Replace",
	Parallel = "Parallel",
})

return TypeTask
