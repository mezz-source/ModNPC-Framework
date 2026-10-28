local ServerScriptService = game:GetService("ServerScriptService")
local Targetting = require(ServerScriptService.ModNPCServer.API.v1.Modules.Targetting)
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
		GetHealthInfo = "getHealthInfo",
		GetRootPart = "getRootPart",
		IsValidCharacter = "isValidCharacter",
		IsValidModNPC = "isValidModNPC",
		GetCharacterInfo = "getCharacterInfo",
		GetTeam = "getTeam",
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
		SetWalkSpeed = "setWalkSpeed",
		Jump = "jump",
	},
	Targetting = {
		GetTargets = "getTargets",
		GetTargetsOfType = "getTargetsOfType",
		GetTargetsWithTeamFilter = "getTargetsWithTeamFilter",
		GetDistance = "getDistance",
	}
})

return TypeAPI
