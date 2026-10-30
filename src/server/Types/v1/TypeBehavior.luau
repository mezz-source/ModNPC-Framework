local ServerScriptService = game:GetService("ServerScriptService")
local TypeAttack = require(ServerScriptService.ModNPCServer.Types.v1.TypeAttack)
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeDefense = require(ServerScriptService.ModNPCServer.Types.v1.TypeDefense)
local TypeDisposition = require(ServerScriptService.ModNPCServer.Types.v1.TypeDisposition)
local TypeDistance = require(ServerScriptService.ModNPCServer.Types.v1.TypeDistance)
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)
local TypeMovement = require(ServerScriptService.ModNPCServer.Types.v1.TypeMovement)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeSkills = require(ServerScriptService.ModNPCServer.Types.v1.TypeSkills)
local TypeSound = require(ServerScriptService.ModNPCServer.Types.v1.TypeSound)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)

local TypeBehavior = {}

export type FunctionName = keyof<typeof(TypeCharacterFunctions.FunctionEnum)>
export type SubscribePosition = "First" | "Last" | "Replace"

export type FunctionCallbacks = {
	GetTargets: (...any) -> ...any,
	Wander: (...any) -> ...any,
	Move: (direction: TypeMovement.MovementDirection) -> ...any,
	AttackCurrentTarget: () -> (boolean, string?),
	MeleeAttackCurrentTarget: () -> (boolean, string?),
	RangeAttackCurrentTarget: () -> (boolean, string?),
	PickDesiredAttack: (attackType: TypeAttack.AttackType) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	GetDesiredAttack: () -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	ClearDesiredAttack: () -> (),
	CanAffordAttack: (attack: TypeAttack.AttackData) -> (boolean, string?),
	IsReadyToAttack: () -> boolean,
	IsPressingOn: () -> boolean,
	CancelCurrentAttack: (force: boolean?) -> (boolean, string?),
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
	DodgeLeft: () -> (boolean, string?),
	DodgeRight: () -> (boolean, string?),
	DodgeForward: () -> (boolean, string?),
	DodgeBackward: () -> (boolean, string?),
	Dodge: (direction: TypeMovement.MovementDirection) -> (boolean, string?),
	DodgeRandomly: () -> (boolean, string?),
	CanMove: () -> (boolean, string?),
	CanAttack: () -> (boolean, string?),
	CanDodge: (direction: TypeMovement.MovementDirection?) -> (boolean, string?),
	ApplyImpulse: (velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (angularVelocityChange: Vector3) -> ...any,
	StopMoving: () -> ...any,
	SetWalkDirection: (source: any, direction: TypeMovement.MovementDirection) -> ...any,
	ClearWalkDirection: (source: any) -> ...any,
	LockMovement: (source: any) -> ...any,
	UnlockMovement: (source: any) -> ...any,
	CanBeEvasive: () -> (boolean, string?),
	IsValidTargetPreference: (preference: string?) -> boolean,
	SelectBestTarget: (
		targets: { TypeTargetting.TargettingContext },
		preference: TypeTargetting.TargettingPreference
	) -> TypeTargetting.TargettingContext?,
	PlaySound: (soundName: string, source: TypeCDN.ContentSource?) -> boolean,
	PlaySoundCategory: (prefix: string, playbackSpeed: number?) -> boolean,
	PlayVFX: (vfxName: string, destination: BasePart | Model, source: TypeCDN.ContentSource?) -> boolean,
	PlayVFXGroup: (groupName: string, destination: BasePart | Model, source: TypeCDN.ContentSource?) -> boolean,
	LoadAnimation: (
		animationAsset: { AnimationId: string },
		animationName: string,
		priority: Enum.AnimationPriority?,
		loop: boolean?,
		source: TypeCDN.ContentSource?
	) -> any,
	PlayAnimation: (
		animName: string,
		fadeTime: number?,
		priority: Enum.AnimationPriority?,
		loop: boolean?,
		weight: number?
	) -> any,
	StopAnimation: (animName: string, fadeTime: number) -> ...any,
	EquipWeapon: (weaponName: string) -> (boolean, string?),
	UnequipWeapon: () -> (boolean, string?),
	ArmWeapon: () -> (boolean, string?),
	DisarmWeapon: () -> (boolean, string?),
	IsStaggered: () -> boolean,
	IsLaunched: () -> boolean,
	BeginStagger: () -> (boolean, string?),
	EndStagger: () -> (),
	BeginLaunch: () -> (boolean, string?),
	EndLaunch: () -> (),
	GetSkillLevel: (skill: TypeSkills.Skill) -> number,
	GetSkillChance: (skills: { TypeSkills.Skill }) -> number,
	RollSkill: (skill: TypeSkills.Skill) -> TypeSkills.RollResult,
	RollSkills: (skills: { TypeSkills.Skill }) -> TypeSkills.RollResult,
	GetDisposition: (axis: TypeDisposition.Axis) -> number,
	GetEngageDistance: (targettingRange: TypeTargetting.TargettingRange) -> number?,
	GetHoldDistance: (targettingRange: TypeTargetting.TargettingRange) -> number?,
	GetAttackStandoff: (attack: TypeAttack.AttackData) -> number,
	GetAttackFit: (attack: TypeAttack.AttackData, distance: number?) -> number,
	GetAttackPace: (chain: number) -> TypeAttack.AttackPace,
	CanBlock: () -> (boolean, string?),
	IsBlocking: () -> boolean,
	BeginBlock: () -> (boolean, string?),
	EndBlock: () -> (),
	BreakBlock: (reason: string?) -> (),
	IsBlockBroken: () -> boolean,
	GetHitCategory: (amount: number) -> TypeDamage.HitCategory,
	ReactToIncomingAttack: (stimulant: TypeStimulant.StimulantEvent) -> (TypeDefense.Reaction, string?),
	GetStamina: () -> (number, number),
	GetStaminaCost: (cost: TypeStamina.Cost) -> number?,
	GetStaminaEfficiency: () -> number,
	IsExhausted: () -> boolean,
	CanAffordStamina: (cost: TypeStamina.Cost, requireRested: boolean?) -> (boolean, string?),
	PurchaseStamina: (cost: TypeStamina.Cost, requireRested: boolean?) -> (boolean, string?),
	SpendStamina: (amount: number, reason: string?, requireRested: boolean?) -> (boolean, string?),
	RestoreStamina: (amount: number, reason: string?) -> (boolean, string?),
	BreakStamina: (reason: string?) -> (boolean, string?),
	ReceiveStimulant: (stimulant: TypeStimulant.StimulantEvent) -> boolean,
	DropStimulant: (id: number) -> boolean,
	GetStimulants: (name: string?) -> { TypeStimulant.StimulantEvent },
	PeekStimulant: (name: string?) -> TypeStimulant.StimulantEvent?,
	ConsumeStimulant: (id: number) -> TypeStimulant.StimulantEvent?,
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
	AttackTargets: {
		new: TypeTask.TaskConstructor,
	},
	Engage: {
		new: TypeTask.TaskConstructor,
	},
	Walk: {
		new: (direction: TypeMovement.MovementDirection, duration: number?) -> (TypeTask.Task?, string?),
	},
	Attack: {
		new: (context: TypeAttack.AttackContext) -> (TypeTask.Task?, string?),
	},
	Stagger: {
		new: (duration: number) -> (TypeTask.Task?, string?),
	},
	Launch: {
		new: (upwardImpulse: number, backwardImpulse: number) -> (TypeTask.Task?, string?),
	},
	Block: {
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
	SetWalkDirection: (self: Movement, source: any, direction: TypeMovement.MovementDirection) -> ...any,
	ClearWalkDirection: (self: Movement, source: any) -> ...any,
	LockMovement: (self: Movement, source: any) -> ...any,
	UnlockMovement: (self: Movement, source: any) -> ...any,
	SetFocusTarget: (self: Movement, target: Instance) -> ...any,
	RemoveFocusTarget: (self: Movement) -> ...any,
	ApplyImpulse: (self: Movement, velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (self: Movement, angularVelocityChange: Vector3) -> ...any,
	DodgeLeft: (self: Movement) -> (boolean, string?),
	DodgeRight: (self: Movement) -> (boolean, string?),
	DodgeForward: (self: Movement) -> (boolean, string?),
	DodgeBackward: (self: Movement) -> (boolean, string?),
	Dodge: (self: Movement, direction: TypeMovement.MovementDirection) -> (boolean, string?),
	DodgeRandomDirection: (self: Movement) -> (boolean, string?),
	InitDodges: (self: Movement) -> (),
}

export type Configuration = {
	Unwatch: (self: Configuration) -> (),
	Observe: (self: Configuration, key: string | { string }, callback: (any, any) -> ()) -> any,
	GetData: (self: Configuration) -> { [string]: any },
	GetEntry: (self: Configuration, key: string | { string }) -> any,
	Get: (self: Configuration, key: string | { string }) -> any,
	GetDamageSetting: (self: Configuration, settingName: string) -> any,
	GetHealthSetting: (self: Configuration, settingName: string) -> any,
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
	MoveInDirection: (self: CharacterAPI, directions: TypeMovement.MovementDirections) -> ...any,
	StopMoving: (self: CharacterAPI) -> ...any,
	LockCharacter: (self: CharacterAPI) -> ...any,
	UnlockCharacter: (self: CharacterAPI) -> ...any,
	LockRotation: (self: CharacterAPI) -> ...any,
	UnlockRotation: (self: CharacterAPI) -> ...any,
	SetFocusTarget: (self: CharacterAPI, target: Instance) -> ...any,
	RemoveFocusTarget: (self: CharacterAPI) -> ...any,
	ApplyImpulse: (self: CharacterAPI, velocityChange: Vector3) -> ...any,
	ApplyAngularImpulse: (self: CharacterAPI, angularVelocityChange: Vector3) -> ...any,
	ApplyImpulseInDirection: (
		self: CharacterAPI,
		directions: TypeMovement.MovementDirections,
		velocityChange: number
	) -> ...any,
	ApplyForwardImpulse: (self: CharacterAPI, force: number) -> ...any,
	PushAway: (self: CharacterAPI, target: Model, force: number) -> ...any,
	DealDamage: (
		self: CharacterAPI,
		receiver: Model,
		amount: number,
		damageType: TypeDamage.DamageType?,
		special: TypeDamage.DamageSpecial?,
		maxStaggerTime: number?
	) -> TypeRequests.CharacterResponse,
	LoadSounds: (self: CharacterAPI, sounds: { TypeCDN.SoundData }) -> TypeSound.SoundLoadResult?,
	PlaySound: (self: CharacterAPI, soundName: string, soundList: TypeSound.SoundList) -> (),
	StopSound: (self: CharacterAPI, soundName: string, soundList: TypeSound.SoundList) -> (),
	PlaySoundGroup: (self: CharacterAPI, prefix: string, soundList: TypeSound.SoundList) -> { Sound }?,
	PlaySoundCategory: (
		self: CharacterAPI,
		prefix: string,
		soundList: TypeSound.SoundList,
		playbackSpeed: number?
	) -> Sound?,
	StopSoundsByPrefix: (self: CharacterAPI, prefix: string, soundList: TypeSound.SoundList) -> (),
	UnloadAllSounds: (self: CharacterAPI, soundList: TypeSound.SoundList) -> (),
	PlayVFX: (self: CharacterAPI, effects: { TypeCDN.VFXData }, destination: BasePart | Model) -> { Instance }?,
	CreateBar: (self: CharacterAPI, barName: string, options: TypeBars.BarOptions?) -> TypeBars.Bar?,
	GetBar: (self: CharacterAPI, barName: string) -> TypeBars.Bar?,
	RemoveBar: (self: CharacterAPI, barName: string) -> boolean,
	CreateHighlight: (
		self: CharacterAPI,
		highlightName: string,
		options: TypeHighlights.HighlightOptions?
	) -> TypeHighlights.Highlight?,
	FlashHighlight: (self: CharacterAPI, options: TypeHighlights.FlashHighlightOptions?) -> TypeHighlights.Highlight?,
	GetHighlight: (self: CharacterAPI, highlightName: string) -> TypeHighlights.Highlight?,
	RemoveHighlight: (self: CharacterAPI, highlightName: string) -> boolean,
	SendStimulant: (self: CharacterAPI, stimulant: TypeStimulant.OutgoingStimulant) -> (),
	EmitStimulant: (self: CharacterAPI, stimulant: TypeStimulant.OutgoingStimulant) -> TypeStimulant.EmitResult?,
	RetractStimulant: (self: CharacterAPI, id: number) -> boolean,
	IsValidWeapon: (self: CharacterAPI, weapon: Instance) -> boolean,
	IsWeaponEquipped: (self: CharacterAPI, weapon: Instance) -> boolean,
	EquipWeapon: (self: CharacterAPI, weapon: Instance) -> Motor6D?,
	UnequipWeapon: (self: CharacterAPI, weapon: Instance) -> boolean,
	DropWeapon: (self: CharacterAPI, weapon: Instance) -> boolean,
	GetWeaponSetting: (self: CharacterAPI, weapon: Instance, path: { string }) -> any,
	GetAssetsIndex: (self: CharacterAPI, container: Instance?) -> TypeCDN.AssetIndex?,
	GetAttacksIndex: (self: CharacterAPI, container: Instance?) -> TypeAttack.AttackIndex?,
	GetWeapons: (self: CharacterAPI) -> { Instance },
	GetEquippedWeapon: (self: CharacterAPI) -> Instance?,
	ValidateCharacter: (self: CharacterAPI) -> (boolean, string?),
	GetAllTargets: (self: CharacterAPI) -> { TypeTargetting.TargettingContext },
	GetTargetsOfType: (self: CharacterAPI, characterType: string) -> { TypeTargetting.TargettingContext },
	GetTeam: (self: CharacterAPI) -> string?,
	GetDistanceBetween: (self: CharacterAPI, from: Model, to: Model) -> number?,
	GetDistanceTo: (self: CharacterAPI, target: Model) -> number?,
	GetDistanceToPosition: (self: CharacterAPI, position: Vector3) -> number?,
	GetHealth: (self: CharacterAPI, character: Model?) -> number?,
	GetMaxHealth: (self: CharacterAPI, character: Model?) -> number?,
	GetHealthInfo: (self: CharacterAPI, character: Model?) -> TypeTargetting.HealthInfo?,
	IsExhausted: (self: CharacterAPI, character: Model?) -> boolean,
	IsStaggered: (self: CharacterAPI, character: Model?) -> boolean,
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

export type State = {
	Register: (self: State, key: string, enum: TypeState.StateEnum, initial: string?) -> boolean,
	IsRegistered: (self: State, key: string) -> boolean,
	Get: (self: State, key: string) -> string?,
	Is: (self: State, key: string, value: string) -> boolean,
	Set: (self: State, key: string, value: string) -> boolean,
}

-- Every lookup returns the asset and the source it was found in. Sources are searched NPC first, then in the order
-- they were added; a source passed in is searched first, then the NPC.
export type Assets = {
	BaseSource: string,
	AddSource: (self: Assets, source: TypeCDN.ContentSource, index: TypeCDN.AssetIndex) -> boolean,
	RemoveSource: (self: Assets, source: TypeCDN.ContentSource) -> boolean,
	HasSource: (self: Assets, source: TypeCDN.ContentSource) -> boolean,
	GetSources: (self: Assets) -> { TypeCDN.ContentSource },
	GetSearchOrder: (self: Assets, source: TypeCDN.ContentSource?) -> { TypeCDN.ContentSource },
	GetData: (self: Assets, source: TypeCDN.ContentSource?) -> TypeCDN.AssetIndex,
	GetSoundCategory: (
		self: Assets,
		categoryName: string,
		source: TypeCDN.ContentSource?
	) -> ({ TypeCDN.SoundData }?, TypeCDN.ContentSource?),
	GetSound: (
		self: Assets,
		soundName: string,
		source: TypeCDN.ContentSource?
	) -> (TypeCDN.SoundData?, TypeCDN.ContentSource?),
	GetSoundGroup: (
		self: Assets,
		groupName: string,
		source: TypeCDN.ContentSource?
	) -> ({ TypeCDN.SoundData }?, TypeCDN.ContentSource?),
	GetAnimationCategory: (
		self: Assets,
		categoryName: string,
		source: TypeCDN.ContentSource?
	) -> ({ TypeCDN.AnimationData }?, TypeCDN.ContentSource?),
	GetAnimation: (
		self: Assets,
		animationKey: string,
		source: TypeCDN.ContentSource?
	) -> (TypeCDN.AnimationData?, TypeCDN.ContentSource?),
	GetRandomAnimationFromCategory: (
		self: Assets,
		categoryName: string,
		source: TypeCDN.ContentSource?
	) -> (TypeCDN.AnimationData?, TypeCDN.ContentSource?),
	GetVFX: (
		self: Assets,
		vfxName: string,
		source: TypeCDN.ContentSource?
	) -> (TypeCDN.VFXData?, TypeCDN.ContentSource?),
	GetVFXGroup: (
		self: Assets,
		groupName: string,
		source: TypeCDN.ContentSource?
	) -> ({ TypeCDN.VFXData }?, TypeCDN.ContentSource?),
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
		loop: boolean?,
		source: TypeCDN.ContentSource?
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

export type Sound = {
	IsLoaded: (self: Sound, soundName: string, source: TypeCDN.ContentSource?) -> boolean,
	Play: (self: Sound, soundName: string, source: TypeCDN.ContentSource?) -> boolean,
	PlayGroup: (self: Sound, prefix: string, source: TypeCDN.ContentSource?) -> boolean,
	PlayCategory: (
		self: Sound,
		prefix: string,
		playbackSpeed: number?,
		source: TypeCDN.ContentSource?
	) -> boolean,
	Stop: (self: Sound, soundName: string, source: TypeCDN.ContentSource?) -> boolean,
	StopGroup: (self: Sound, prefix: string, source: TypeCDN.ContentSource?) -> (),
	StopCategory: (self: Sound, prefix: string, source: TypeCDN.ContentSource?) -> (),
	StopAll: (self: Sound) -> (),
}

-- VFX are played at a destination (a part, or a character's root part) and clean themselves up; nothing stays loaded,
-- so there is nothing to stop. Searched like assets: the NPC first, then weapons in the order they were equipped.
export type VFX = {
	Play: (self: VFX, vfxName: string, destination: BasePart | Model, source: TypeCDN.ContentSource?) -> boolean,
	PlayGroup: (
		self: VFX,
		groupName: string,
		destination: BasePart | Model,
		source: TypeCDN.ContentSource?
	) -> boolean,
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

-- Group checks for whole kinds of activity, answered from the character's states. Each returns whether the activity is
-- allowed and, when it isn't, what is in the way (e.g. "StaggerState is Launched").
export type Abilities = {
	CanMove: (self: Abilities) -> (boolean, string?),
	CanAttack: (self: Abilities) -> (boolean, string?),
	CanDodge: (self: Abilities, direction: TypeMovement.MovementDirection?) -> (boolean, string?),
	CanBeEvasive: (self: Abilities) -> (boolean, string?),
	CanBlock: (self: Abilities) -> (boolean, string?),
}

export type Damage = {
	Init: (self: Damage) -> (),
	Receive: (self: Damage, context: TypeDamage.ReceivedDamageContext) -> TypeDamage.OutgoingDamageContext,
	ReceiveRegistered: (
		self: Damage,
		incoming: TypeDamage.IncomingDamageContext
	) -> TypeDamage.OutgoingDamageContext,
	ReceiveUnregistered: (self: Damage, amount: number) -> TypeDamage.OutgoingDamageContext,
	Post: (self: Damage, outgoing: TypeDamage.OutgoingDamageContext) -> (),
	DealSelfDamage: (self: Damage, amount: number) -> TypeRequests.CharacterResponse,
	IsProcessingDamage: (self: Damage) -> boolean,
	IsStaggered: (self: Damage) -> boolean,
	IsLaunched: (self: Damage) -> boolean,
	BeginStagger: (self: Damage) -> (boolean, string?),
	EndStagger: (self: Damage) -> (),
	BeginLaunch: (self: Damage) -> (boolean, string?),
	EndLaunch: (self: Damage) -> (),
	GetHitCategory: (self: Damage, amount: number) -> TypeDamage.HitCategory,
	IsBlocking: (self: Damage) -> boolean,
	BeginBlock: (self: Damage) -> (boolean, string?),
	EndBlock: (self: Damage) -> (),
	BreakBlock: (self: Damage, reason: string?) -> (),
	IsBlockBroken: (self: Damage) -> boolean,
}

-- Rolls a d20 scaled to 100 against the character's Config/Levels. Several skills are rolled for at their average level.
export type Skills = {
	GetSkillLevel: (self: Skills, skill: TypeSkills.Skill) -> number,
	GetCombinedLevel: (self: Skills, skills: { TypeSkills.Skill }) -> number,
	GetSkillChance: (self: Skills, skills: { TypeSkills.Skill }) -> number,
	RollSkill: (self: Skills, skill: TypeSkills.Skill) -> TypeSkills.RollResult,
	RollSkills: (self: Skills, skills: { TypeSkills.Skill }) -> TypeSkills.RollResult,
}

export type Attacks = {
	Init: (self: Attacks) -> (),
	GetAnimationName: (self: Attacks, attackName: string, source: TypeCDN.ContentSource?) -> string,
	GetCurrentTarget: (self: Attacks) -> Model?,
	PickDesiredAttack: (
		self: Attacks,
		attackType: TypeAttack.AttackType
	) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	GetDesiredAttack: (self: Attacks) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	ClearDesiredAttack: (self: Attacks) -> (),
	CanAffordAttack: (self: Attacks, attack: TypeAttack.AttackData) -> (boolean, string?),
	IsReadyToAttack: (self: Attacks) -> boolean,
	IsPressingOn: (self: Attacks) -> boolean,
	CancelCurrentAttack: (self: Attacks, force: boolean?) -> (boolean, string?),
	Attack: (
		self: Attacks,
		attackType: TypeAttack.AttackType,
		target: Model,
		source: TypeCDN.ContentSource?
	) -> (boolean, string?),
	GetAttack: (
		self: Attacks,
		attackName: string,
		source: TypeCDN.ContentSource?
	) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	GetAttackIndex: (self: Attacks, source: TypeCDN.ContentSource?) -> TypeAttack.AttackIndex,
	GetAttackCandidates: (
		self: Attacks,
		attackType: TypeAttack.AttackType,
		source: TypeCDN.ContentSource?
	) -> { TypeAttack.AttackCandidate },
	FindAttack: (
		self: Attacks,
		attackType: TypeAttack.AttackType,
		source: TypeCDN.ContentSource?
	) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	FindMeleeAttack: (self: Attacks, source: TypeCDN.ContentSource?) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	FindRangedAttack: (
		self: Attacks,
		source: TypeCDN.ContentSource?
	) -> (TypeAttack.AttackData?, TypeCDN.ContentSource?),
	AttackCurrentTarget: (self: Attacks) -> (boolean, string?),
	MeleeAttackCurrentTarget: (self: Attacks) -> (boolean, string?),
	RangeAttackCurrentTarget: (self: Attacks) -> (boolean, string?),
}

-- One weapon is in hand at a time (equipping another drops the one held). It is armed (drawn) and disarmed on top of that.
export type Weapons = {
	Init: (self: Weapons) -> (),
	GetEquippedWeapon: (self: Weapons) -> Instance?,
	IsArmed: (self: Weapons) -> boolean,
	EquipWeapon: (self: Weapons, weaponName: string) -> (boolean, string?),
	UnequipWeapon: (self: Weapons) -> (boolean, string?),
	ArmWeapon: (self: Weapons) -> (boolean, string?),
	DisarmWeapon: (self: Weapons) -> (boolean, string?),
}

export type TargetSelector = {
	IsValidPreference: (self: TargetSelector, preference: string?) -> boolean,
	SelectBest: (
		self: TargetSelector,
		targets: { TypeTargetting.TargettingContext },
		preference: TypeTargetting.TargettingPreference
	) -> TypeTargetting.TargettingContext?,
}

-- Shared range logic for the tasks. Core like Configuration and Assets, so tasks use it directly.
export type Distance = {
	-- these compare numbers only, so they work on the module without a character (Distance.Classify)
	Classify: (distance: number, ideal: number, tooCloseDiff: number?) -> TypeDistance.RangeState,
	IsFarPast: (distance: number, ideal: number, farDiff: number) -> boolean,
	GetEngageDistance: (self: Distance, targettingRange: TypeTargetting.TargettingRange) -> number?,
	GetTooCloseDiff: (self: Distance) -> number,
	GetDistanceTo: (self: Distance, target: Model) -> number?,
	GetDistanceToPosition: (self: Distance, position: Vector3) -> number?,
	IsWithin: (self: Distance, target: Model, range: number) -> boolean,
	GetRangeState: (
		self: Distance,
		target: Model,
		ideal: number,
		tooCloseDiff: number?
	) -> TypeDistance.RangeState?,
	IsInRange: (self: Distance, target: Model, ideal: number, tooCloseDiff: number?) -> boolean,
	GetEngagement: (self: Distance) -> TypeState.EngageState,
	IsPursuing: (self: Distance) -> boolean,
	IsEngaged: (self: Distance) -> boolean,
	UpdateEngagement: (self: Distance, distance: number, ideal: number) -> TypeState.EngageState,
	ResetEngagement: (self: Distance) -> (),
}

-- How the character feels about the fight, as axes that decide how it behaves in one. A behavior module: others reach it
-- through Functions (GetDisposition, GetEngageDistance, GetHoldDistance, GetAttackStandoff, GetAttackFit, GetAttackPace).
export type Disposition = {
	Init: (self: Disposition) -> (),
	Update: (self: Disposition, deltaTime: number) -> (),
	GetDisposition: (self: Disposition, axis: TypeDisposition.Axis) -> number,
	GetAxes: (self: Disposition) -> { [string]: number },
	GetSignals: (self: Disposition) -> { [string]: number },
	GetEngageDistance: (self: Disposition, targettingRange: TypeTargetting.TargettingRange) -> number?,
	GetHoldDistance: (self: Disposition, targettingRange: TypeTargetting.TargettingRange) -> number?,
	GetAttackStandoff: (self: Disposition, attack: TypeAttack.AttackData) -> number,
	GetAttackFit: (self: Disposition, attack: TypeAttack.AttackData, distance: number?) -> number,
	GetAttackPace: (self: Disposition, chain: number) -> TypeAttack.AttackPace,
	Destroy: (self: Disposition) -> (),
}

-- The character's stamina and the vendor that everything costing it goes through. A behavior module: others reach it through
-- Functions (GetStamina, GetStaminaCost, GetStaminaEfficiency, CanAffordStamina, PurchaseStamina, SpendStamina, RestoreStamina).
export type Stamina = {
	Init: (self: Stamina) -> (),
	GetStamina: (self: Stamina) -> (number, number),
	GetFraction: (self: Stamina) -> number,
	GetCost: (self: Stamina, cost: TypeStamina.Cost) -> number?,
	IsExhausted: (self: Stamina) -> boolean,
	-- 1 when rested; while exhausted from 0.5 (nothing left) rising with the stamina. Modules apply it themselves.
	GetEfficiency: (self: Stamina) -> number,
	CanRegenerate: (self: Stamina) -> boolean,
	-- `requireRested` declines the purchase of an exhausted character even if it has enough
	CanAfford: (self: Stamina, cost: TypeStamina.Cost, requireRested: boolean?) -> (boolean, string?),
	Spend: (self: Stamina, amount: number, reason: string?, requireRested: boolean?) -> (boolean, string?),
	Purchase: (self: Stamina, cost: TypeStamina.Cost, requireRested: boolean?) -> (boolean, string?),
	Restore: (self: Stamina, amount: number, reason: string?) -> (boolean, string?),
	Break: (self: Stamina, reason: string?) -> (boolean, string?),
	Destroy: (self: Stamina) -> (),
}

-- The stimulants other characters made this one aware of, queued until consumed or expired. A behavior module: others
-- reach it through Functions (ReceiveStimulant, DropStimulant, GetStimulants, PeekStimulant, ConsumeStimulant), and it
-- offers what is pending on every reaction tick as Names.Stimulant.Pending.
export type Stimulants = {
	Init: (self: Stimulants) -> (),
	Receive: (self: Stimulants, stimulant: TypeStimulant.StimulantEvent) -> boolean,
	Drop: (self: Stimulants, id: number) -> boolean,
	GetStimulants: (self: Stimulants, name: string?) -> { TypeStimulant.StimulantEvent },
	Peek: (self: Stimulants, name: string?) -> TypeStimulant.StimulantEvent?,
	Consume: (self: Stimulants, id: number) -> TypeStimulant.StimulantEvent?,
	Clear: (self: Stimulants) -> (),
	Destroy: (self: Stimulants) -> (),
}

-- How the character meets the hits it sees coming: it reads each IncomingAttack stimulant on the reaction tick and dodges
-- (an Agility roll, timed to the hit) or raises a last moment guard. A behavior module: others reach it through Functions
-- (ReactToIncomingAttack), and it announces each decision as Names.Combat.DefenseReaction.
export type Defense = {
	Init: (self: Defense) -> (),
	ReactToIncomingAttack: (self: Defense, stimulant: TypeStimulant.StimulantEvent) -> (TypeDefense.Reaction, string?),
	IsReacting: (self: Defense) -> boolean,
	Destroy: (self: Defense) -> (),
}

export type ModScript = {
	init: (base: Base) -> (),
}

export type Base = {
	Character: Model,
	Router: Router,
	Events: Events,
	State: State,
	CharacterAPI: CharacterAPI,
	Configuration: Configuration,
	Assets: Assets,
	Dialogue: Dialogue,
	Animation: Animation,
	Sound: Sound,
	VFX: VFX,
	Humanoid: Humanoid,
	Damage: Damage,
	Abilities: Abilities,
	Distance: Distance,
	Skills: Skills,
	Disposition: Disposition,
	Stamina: Stamina,
	Stimulants: Stimulants,
	Defense: Defense,
	Attacks: Attacks,
	Weapons: Weapons,
	Movement: Movement,
	TargetSelector: TargetSelector,
	Tasks: TypeTask.Scheduler,
	Scheduler: TypeTask.Scheduler,
	CharacterTasks: CharacterTasks,
	Functions: FunctionSystem,
	FunctionEnum: typeof(TypeCharacterFunctions.FunctionEnum),
	-- Makes the stimulants CharacterAPI:SendStimulant / EmitStimulant send. NewStimulant is the usual way in, bound to
	-- this character so the builder can Send / Emit itself.
	StimulantBuilder: {
		new: (name: string, sender: TypeStimulant.StimulantSender?) -> TypeStimulant.StimulantBuilder,
	},
	NewStimulant: (self: Base, name: string) -> TypeStimulant.StimulantBuilder,
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
