local TypeAPI = {}

export type Module =
	"CharacterUtility"
	| "Configuration"
	| "Damage"
	| "Targetting"
	| "Animation"
	| "Bars"
	| "Highlights"
	| "ContentDelivery"
	| "Movement"
	| "Sound"
	| "VFX"
	| "Weapon"
	| "Stimulants"

TypeAPI.Modules = table.freeze({
	CharacterUtility = "CharacterUtility",
	Configuration = "Configuration",
	Damage = "Damage",
	Targetting = "Targetting",
	Animation = "Animation",
	Bars = "Bars",
	Highlights = "Highlights",
	ContentDelivery = "ContentDelivery",
	Movement = "Movement",
	Sound = "Sound",
	VFX = "VFX",
	Weapon = "Weapon",
	Stimulants = "Stimulants",
})

TypeAPI.Functions = table.freeze({
	CharacterUtility = {
		GetHumanoid = "getHumanoid",
		GetHealth = "getHealth",
		GetMaxHealth = "getMaxHealth",
		GetHealthInfo = "getHealthInfo",
		GetRootPart = "getRootPart",
		GetStaminaInfo = "getStaminaInfo",
		IsExhausted = "isExhausted",
		IsStaggered = "isStaggered",
		IsValidCharacter = "isValidCharacter",
		IsValidModNPC = "isValidModNPC",
		GetCharacterInfo = "getCharacterInfo",
		GetTeam = "getTeam",
	},
	Damage = {
		TakeDamage = "takeDamage",
		TakeHumanoidDamage = "takeHumanoidDamage",
		RestoreHumanoidHealth = "restoreHumanoidHealth",
	},
	Animation = {
		LoadBaseAnimations = "loadBaseAnimations",
		LoadAnimation = "loadAnimation",
		PlayAnimation = "playAnimation",
		AdjustSpeed = "adjustSpeed",
		StopAnimation = "stopAnimation",
		UnloadAllAnimations = "unloadAllAnimations",
	},
	Bars = {
		CreateBar = "createBar",
		GetBar = "getBar",
		RemoveBar = "removeBar",
	},
	Highlights = {
		CreateHighlight = "createHighlight",
		FlashHighlight = "flashHighlight",
		GetHighlight = "getHighlight",
		RemoveHighlight = "removeHighlight",
	},
	ContentDelivery = {
		GetSoundCategory = "getSoundCategory",
		GetSound = "getSound",
		GetSoundGroup = "getSoundGroup",
		GetAnimationCategory = "getAnimationCategory",
		GetVFX = "getVFX",
		GetVFXGroup = "getVFXGroup",
		GetAssetsIndex = "getAssetsIndex",
		GetAttacksIndex = "getAttacksIndex",
		GetDispositionValues = "getDispositionValues",
		GetConfigurationIndex = "getConfigurationIndex",
		GetConfigurationSchema = "getConfigurationSchema",
		GetSetting = "getSetting",
		GetDamageSetting = "getDamageSetting",
		GetLevelSetting = "getLevelSetting",
		GetMovementSetting = "getMovementSetting",
		SetSetting = "setSetting",
		SetDamageSetting = "setDamageSetting",
		SetLevelSetting = "setLevelSetting",
		SetMovementSetting = "setMovementSetting",
		InvalidateConfiguration = "invalidate",
		WatchConfiguration = "watchConfiguration",
		UnwatchConfiguration = "unwatchConfiguration",
		GetLines = "getLines",
		GetConversation = "getConversation",
		GetLinesIndex = "getLinesIndex",
		GetModules = "getModules",
		GetModScripts = "getModScripts",
		GetRange = "getRange",
		GetThoughtSetting = "getThoughtSetting",
		SetRange = "setRange",
		SetThoughtSetting = "setThoughtSetting",
		SetDispositionValue = "setDispositionValue"
	},
	Movement = {
		MoveTo = "moveTo",
		WalkTo = "walkTo",
		MoveInDirection = "moveInDirection",
		StopMoving = "stopMoving",
		LockCharacter = "lockCharacter",
		UnlockCharacter = "unlockCharacter",
		LockRotation = "lockRotation",
		UnlockRotation = "unlockRotation",
		SetFocusTarget = "setFocusTarget",
		RemoveFocusTarget = "removeFocusTarget",
		ApplyImpulse = "applyImpulse",
		ApplyAngularImpulse = "applyAngularImpulse",
		ApplyImpulseInDirection = "applyImpulseInDirection",
		ApplyForwardImpulse = "applyForwardImpulse",
		ApplyImpulseAwayFrom = "applyImpulseAwayFrom",
		SetWalkSpeed = "setWalkSpeed",
		Jump = "jump",
	},
	Targetting = {
		GetTargets = "getTargets",
		GetTargetsOfType = "getTargetsOfType",
		GetTargetsWithTeamFilter = "getTargetsWithTeamFilter",
		GetDistance = "getDistance",
		GetDistanceToPosition = "getDistanceToPosition",
	},
	Sound = {
		LoadSounds = "loadSounds",
		PlaySound = "playSound",
		PlaySoundGroup = "playSoundGroup",
		PlaySoundCategory = "playSoundCategory",
		StopSound = "stopSound",
		StopSoundsByPrefix = "stopSoundsByPrefix",
		UnloadAllSounds = "unloadAllSounds",
	},
	VFX = {
		PlayVFX = "playVFX",
	},
	Weapon = {
		IsValidWeapon = "isValidWeapon",
		IsEquipped = "isEquipped",
		EquipWeapon = "equipWeapon",
		UnequipWeapon = "unequipWeapon",
		DropWeapon = "dropWeapon",
		GetWeaponSetting = "getWeaponSetting",
		GetWeapons = "getWeapons",
		GetEquippedWeapon = "getEquippedWeapon",
	},
	Stimulants = {
		Emit = "emit",
		Retract = "retract",
	},
})

return TypeAPI
