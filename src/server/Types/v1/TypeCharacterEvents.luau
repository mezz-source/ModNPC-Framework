local TypeCharacterEvents = {}

local TypeCDN = require(script.Parent.TypeCDN)

type PrimitiveValue = TypeCDN.PrimitiveValue

export type ConfigurationUpdated = {
	Path: { string },
	Previous: PrimitiveValue,
	Value: PrimitiveValue,
	Type: string,
}

export type Event = {
	Name: string,
	Args: any,
}

export type HealthChanged = {
	Health: number,
	MaxHealth: number,
}

export type StateChanged = {
	OldState: Enum.HumanoidStateType,
	NewState: Enum.HumanoidStateType,
}

TypeCharacterEvents.Names = table.freeze({
	Configuration = {
		ConfigurationUpdated = "ConfigurationUpdated",
		ConfigurationInvalidated = "ConfigurationInvalidated",
	},
	Humanoid = {
		MoveBegan = "HumanoidMoveBegan",
		MoveEnded = "HumanoidMoveEnded",
		Died = "HumanoidDied",
		Running = "HumanoidRunning",
		HealthChanged = "HumanoidHealthChanged",
		StateChanged = "HumanoidStateChanged",
		Jumped = "HumanoidJumped",
		Landed = "HumanoidLanded",
	},
	Animation = {
		AnimationPlayed = "AnimationPlayed",
		AnimationStopped = "AnimationStopped",
		DeathFinished = "AnimationDeathFinished",
	},
})

return TypeCharacterEvents
