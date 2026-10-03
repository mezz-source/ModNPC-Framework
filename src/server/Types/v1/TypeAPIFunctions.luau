local TypeAPI = {}

export type Module =
	"CharacterUtility"
	| "Configuration"
	| "Damage"
	| "Targetting"
	| "Animation"
	| "ContentDelivery"
	| "Movement"

TypeAPI.Modules = table.freeze({
	CharacterUtility = "CharacterUtility",
	Configuration = "Configuration",
	Damage = "Damage",
	Targetting = "Targetting",
	Animation = "Animation",
	ContentDelivery = "ContentDelivery",
	Movement = "Movement",
})

TypeAPI.Functions = table.freeze({
	CharacterUtility = {
		GetHumanoid = "getHumanoid",
		GetHealth = "getHealth",
		GetMaxHealth = "getMaxHealth",
		GetRootPart = "getRootPart",
		IsValidCharacter = "isValidCharacter",
		IsValidModNPC = "isValidModNPC",
		GetCharacterInfo = "getCharacterInfo",
	},
	Damage = {
		TakeDamage = "takeDamage",
		TakeHumanoidDamage = "takeHumanoidDamage",
	},
	Animation = {
		LoadBaseAnimations = "loadBaseAnimations",
		LoadAnimation = "loadAnimation",
		PlayAnimation = "playAnimation",
		AdjustSpeed = "adjustSpeed",
		StopAnimation = "stopAnimation",
		UnloadAllAnimations = "unloadAllAnimations",
	},
	ContentDelivery = {
		GetSoundCategory = "getSoundCategory",
		GetSound = "getSound",
		GetSoundGroup = "getSoundGroup",
		GetAnimationCategory = "getAnimationCategory",
		GetVFX = "getVFX",
		GetAssetsIndex = "getAssetsIndex",
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
		GetLines = "getLines",
		GetConversation = "getConversation",
		GetLinesIndex = "getLinesIndex",
		GetModules = "getModules",
	},
	Movement = {
		MoveTo = "moveTo",
		WalkTo = "walkTo",
		LockCharacter = "lockCharacter",
		UnlockCharacter = "unlockCharacter",
		LockRotation = "lockRotation",
		UnlockRotation = "unlockRotation",
		SetFocusTarget = "setFocusTarget",
		RemoveFocusTarget = "removeFocusTarget",
		ApplyImpulse = "applyImpulse",
		ApplyAngularImpulse = "applyAngularImpulse",
		SetWalkSpeed = "setWalkSpeed",
		Jump = "jump",
	},
})

return TypeAPI
