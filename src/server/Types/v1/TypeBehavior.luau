local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)

local TypeBehavior = {}

export type FunctionName = keyof<typeof(TypeCharacterFunctions.FunctionEnum)>
export type SubscribePosition = "First" | "Last" | "Replace"

export type FunctionCallbacks = {
	GetTargets: (...any) -> ...any,
	Wander: (...any) -> ...any,
	Move: (direction: TypeMovement.MovementDirection) -> ...any,
	MeleeAttack: (...any) -> ...any,
	RangedAttack: (...any) -> ...any,
	StartSprinting: () -> ...any,
	StopSprinting: () -> ...any,
	Jump: () -> ...any,
	MoveLeft: () -> ...any,
	MoveRight: () -> ...any,
	MoveForward: () -> ...any,
	MoveBackward: () -> ...any,
	MoveTo: (position: Vector3) -> ...any,
	SetFocusTarget: (target: Instance) -> ...any,
	RemoveFocusTarget: () -> ...any,
	DodgeLeft: () -> ...any,
	DodgeRight: () -> ...any,
	DodgeForward: () -> ...any,
	DodgeBackward: () -> ...any,
	Dodge: (direction: TypeMovement.MovementDirection) -> ...any,
	ApplyImpulse: (velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (angularVelocityChange: Vector3) -> ...any,
}

export type CharacterTasks = {
	JumpTask: {
		new: TypeTask.TaskConstructor,
	},
	SearchForTargets: {
		new: TypeTask.TaskConstructor,
	},
	ChaseTargets: {
		new: TypeTask.TaskConstructor,
	},
}

export type Subscription = {
	Callback: (...any) -> ...any,
	Active: boolean,
	Unsubscribe: (self: Subscription) -> boolean,
}

export type Movement = {
	StartSprinting: (self: Movement) -> ...any,
	StopSprinting: (self: Movement) -> ...any,
	SetSprinting: (self: Movement, isSprinting: boolean) -> ...any,
	Jump: (self: Movement) -> ...any,
	MoveLeft: (self: Movement) -> ...any,
	MoveRight: (self: Movement) -> ...any,
	MoveForward: (self: Movement) -> ...any,
	MoveBackward: (self: Movement) -> ...any,
	Move: (self: Movement, direction: TypeMovement.MovementDirection) -> ...any,
	MoveTo: (self: Movement, position: Vector3) -> ...any,
	StopMoving: (self: Movement) -> ...any,
	SetFocusTarget: (self: Movement, target: Instance) -> ...any,
	RemoveFocusTarget: (self: Movement) -> ...any,
	ApplyImpulse: (self: Movement, velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (self: Movement, angularVelocityChange: Vector3) -> ...any,
	DodgeLeft: (self: Movement) -> ...any,
	DodgeRight: (self: Movement) -> ...any,
	DodgeForward: (self: Movement) -> ...any,
	DodgeBackward: (self: Movement) -> ...any,
	Dodge: (self: Movement, direction: TypeMovement.MovementDirection) -> ...any,
	CanBeEvasive: (self: Movement) -> boolean,
}

export type Configuration = {
	Unwatch: (self: Configuration) -> (),
	Observe: (self: Configuration, key: string | { string }, callback: (any, any) -> ()) -> any,
	GetData: (self: Configuration) -> { [string]: any },
	GetEntry: (self: Configuration, key: string | { string }) -> any,
	Get: (self: Configuration, key: string | { string }) -> any,
	GetDamageSetting: (self: Configuration, settingName: string) -> any,
	GetThoughtSetting: (self: Configuration, settingName: string) -> any,
	GetRange: (self: Configuration, settingName: string) -> any,
	GetLevelSetting: (self: Configuration, settingName: string) -> any,
	GetMovementSetting: (self: Configuration, settingName: string) -> any,
}

export type CharacterAPI = {
	GetModScripts: (self: CharacterAPI) -> { ModScript },
	Jump: (self: CharacterAPI) -> ...any,
	SetWalkSpeed: (self: CharacterAPI, speed: number) -> ...any,
	MoveTo: (self: CharacterAPI, position: Vector3) -> ...any,
	MoveInDirection: (self: CharacterAPI, direction: TypeMovement.MovementDirection) -> ...any,
	StopMoving: (self: CharacterAPI) -> ...any,
	LockCharacter: (self: CharacterAPI) -> ...any,
	UnlockCharacter: (self: CharacterAPI) -> ...any,
	LockRotation: (self: CharacterAPI) -> ...any,
	UnlockRotation: (self: CharacterAPI) -> ...any,
	SetFocusTarget: (self: CharacterAPI, target: Instance) -> ...any,
	RemoveFocusTarget: (self: CharacterAPI) -> ...any,
	ApplyImpulse: (self: CharacterAPI, velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (self: CharacterAPI, angularVelocityChange: Vector3) -> ...any,
	ValidateCharacter: (self: CharacterAPI) -> boolean,
	GetAllTargets: (self: CharacterAPI) -> { TypeTargetting.TargettingContext },
	GetTargetsOfType: (self: CharacterAPI, characterType: string) -> { TypeTargetting.TargettingContext },
	GetTeam: (self: CharacterAPI) -> string?,
	GetDistanceBetween: (self: CharacterAPI, from: Model, to: Model) -> number?,
	GetDistanceTo: (self: CharacterAPI, target: Model) -> number?,
	GetHealth: (self: CharacterAPI, character: Model?) -> number?,
	GetMaxHealth: (self: CharacterAPI, character: Model?) -> number?,
	GetHealthInfo: (self: CharacterAPI, character: Model?) -> TypeTargetting.HealthInfo?,
	GetTargetsOnTeams: (self: CharacterAPI, teams: { string }) -> { TypeTargetting.TargettingContext },
	GetTargetsExcludingTeams: (self: CharacterAPI, teams: { string }) -> { TypeTargetting.TargettingContext },
	GetOpposingTargets: (self: CharacterAPI) -> { TypeTargetting.TargettingContext },
	GetSameTeamTargets: (self: CharacterAPI) -> { TypeTargetting.TargettingContext },
}

export type Events = {
	Subscribe: (
		self: Events,
		eventName: string,
		callback: (any?) -> (),
		once: boolean?,
		position: string?
	) -> any,
	Unsubscribe: (self: Events, eventName: string, subscriptionOrCallback: any) -> boolean,
	Dispatch: (self: Events, eventName: string, arguments: any?) -> boolean,
}

export type Assets = {
	GetData: (self: Assets) -> any,
	GetSoundCategory: (self: Assets, categoryName: string) -> any,
	GetSound: (self: Assets, soundName: string) -> any,
	GetSoundGroup: (self: Assets, groupName: string) -> any,
	GetAnimationCategory: (self: Assets, categoryName: string) -> any,
	GetAnimation: (self: Assets, animationKey: string) -> any,
	GetRandomAnimationFromCategory: (self: Assets, categoryName: string) -> any,
	GetVFX: (self: Assets, folderName: string) -> any,
}

export type Dialogue = {
	GetData: (self: Dialogue) -> any,
	GetLines: (self: Dialogue, categoryName: string) -> any,
	GetConversation: (self: Dialogue, categoryName: string, conversationName: string) -> any,
}

export type Animation = {
	LoadAnimation: (
		self: Animation,
		animationAsset: { AnimationId: string },
		animationName: string,
		priority: Enum.AnimationPriority?,
		loop: boolean?
	) -> any,
	Play: (
		self: Animation,
		animName: string,
		fadeTime: number,
		priority: Enum.AnimationPriority?,
		loop: boolean?
	) -> any,
	PlayAnimation: (
		self: Animation,
		animName: string,
		fadeTime: number,
		priority: Enum.AnimationPriority?,
		loop: boolean?
	) -> any,
	StopAnimation: (self: Animation, animName: string, fadeTime: number) -> any,
	AdjustSpeed: (self: Animation, animName: string, speed: number) -> any,
	GetAnimationHandle: (self: Animation, animName: string) -> any,
	GetAnimation: (self: Animation, animName: string) -> any,
	GetAnimationCategory: (self: Animation, categoryName: string) -> any,
	GetAnimationId: (self: Animation, animName: string) -> string?,
	UnloadAllAnimations: (self: Animation, fadeTime: number) -> any,
}

export type Router = {
	Request: (self: Router, request: any) -> any,
}

export type FunctionSystem = {
	CallFunction: (self: FunctionSystem, functionName: FunctionName, ...any) -> ...any,
	SubscribeFunction: <Function>(
		self: FunctionSystem,
		functionName: Function,
		callback: () -> any,
		position: SubscribePosition?
	) -> (Subscription?, string?),
}

export type Humanoid = {}

export type TargetSelector = {
	IsValidPreference: (self: TargetSelector, preference: string?) -> boolean,
	SelectBest: (
		self: TargetSelector,
		targets: { TypeTargetting.TargettingContext },
		preference: TypeTargetting.TargettingPreference
	) -> TypeTargetting.TargettingContext?,
}

export type ModScript = {
	init: (base: Base) -> (),
}

export type Base = {
	Character: Model,
	Router: Router,
	Events: Events,
	CharacterAPI: CharacterAPI,
	Configuration: Configuration,
	Assets: Assets,
	Dialogue: Dialogue,
	Animation: Animation,
	Humanoid: Humanoid,
	Movement: Movement,
	TargetSelector: TargetSelector,
	Tasks: TypeTask.Scheduler,
	Scheduler: TypeTask.Scheduler,
	CharacterTasks: CharacterTasks,
	Functions: FunctionSystem,
	FunctionEnum: typeof(TypeCharacterFunctions.FunctionEnum),
	SubscribeEnum: {
		First: "First",
		Last: "Last",
		Replace: "Replace",
	},
	SubscribeFunction: <Function>(
		self: FunctionSystem,
		functionName: Function,
		callback: () -> any,
		position: SubscribePosition?
	) -> (Subscription?, string?),
}

TypeBehavior.FunctionEnum = TypeCharacterFunctions.FunctionEnum
TypeBehavior.SubscribeEnum = table.freeze({
	First = "First",
	Last = "Last",
	Replace = "Replace",
})

return TypeBehavior
