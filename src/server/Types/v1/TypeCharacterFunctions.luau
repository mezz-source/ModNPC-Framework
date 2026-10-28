local CharacterFunctions = {}

CharacterFunctions.FunctionEnum = table.freeze({
	GetTargets = "GetTargets",
	Wander = "Wander",
	Move = "Move",
	MeleeAttack = "MeleeAttack",
	RangedAttack = "RangedAttack",
	StartSprinting = "StartSprinting",
	StopSprinting = "StopSprinting",
	Jump = "Jump",
	MoveLeft = "MoveLeft",
	MoveRight = "MoveRight",
	MoveForward = "MoveForward",
	MoveBackward = "MoveBackward",
	MoveTo = "MoveTo",
	SetFocusTarget = "SetFocusTarget",
	RemoveFocusTarget = "RemoveFocusTarget",
	DodgeLeft = "DodgeLeft",
	DodgeRight = "DodgeRight",
	DodgeForward = "DodgeForward",
	DodgeBackward = "DodgeBackward",
	Dodge = "Dodge",
	ApplyImpulse = "ApplyImpulse",
	ApplyAngularImpulse = "ApplyAngularImpulse",
})

CharacterFunctions.Functions = table.freeze({
	StartSprinting = "startSprinting",
	StopSprinting = "stopSprinting",
	Jump = "jump",
	MoveLeft = "moveLeft",
	MoveRight = "moveRight",
	MoveForward = "moveForward",
	MoveBackward = "moveBackward",
	MoveTo = "moveTo",
	SetFocusTarget = "setFocusTarget",
	RemoveFocusTarget = "removeFocusTarget",
	DodgeLeft = "dodgeLeft",
	DodgeRight = "dodgeRight",
	DodgeForward = "dodgeForward",
	DodgeBackward = "dodgeBackward",
	Dodge = "dodge",
	ApplyImpulse = "applyImpulse",
	ApplyAngularImpulse = "applyAngularImpulse",
})

return CharacterFunctions
