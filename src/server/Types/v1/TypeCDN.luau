local TypeCDN = {}

export type SearchStatus = "Found" | "NotFound" | "Ambiguous" | "InvalidClass"

export type SearchResult = {
	Status: SearchStatus,
	Instance: Instance?,
	Matches: { Instance }?,
	Message: string?,
}

export type PrimitiveValue = boolean | number | string

export type ConfigurationValue = {
	Name: string,
	Type: string,
	Value: PrimitiveValue,
}

export type ConfigurationIndex = {
	[string]: ConfigurationValue | ConfigurationIndex,
}

export type SoundData = {
	Name: string,
	SoundId: string,
	Volume: number,
	PlaybackSpeed: number,
	Looped: boolean,
}

export type AnimationData = {
	Name: string,
	AnimationId: string,
}

-- VFX data points at the effect inside the Assets folder (Template): playing it clones the template onto the
-- destination, so everything the data does not name is kept. The attributes are read when the folder is indexed.
export type ParticleEmitterData = {
	Name: string,
	Type: "ParticleEmitter",
	Template: ParticleEmitter,
	-- particles emitted when played (EmitCount attribute, 1 when absent)
	EmitCount: number,
	-- seconds it is enabled for after playing (EnableTime attribute); nil never enables it
	EnableTime: number?,
}

-- A light has nothing to emit, so it only shows while enabled and needs an EnableTime
export type PointLightData = {
	Name: string,
	Type: "PointLight",
	Template: PointLight,
	EnableTime: number,
}

export type VFXData = ParticleEmitterData | PointLightData

export type SoundIndex = {
	Categories: { [string]: { SoundData } },
	Individual: { [string]: SoundData },
	Groups: { [string]: { SoundData } },
}

export type AnimationIndex = {
	[string]: { AnimationData },
}

export type VFXIndex = {
	-- every effect of a group folder, played together
	Groups: { [string]: { VFXData } },
	Individual: { [string]: VFXData },
}

export type AssetIndex = {
	Sounds: SoundIndex,
	Animations: AnimationIndex,
	VFX: VFXIndex,
}

-- Where a set of content (assets, attacks) comes from: the NPC's own folder ("Base") or an equipped weapon.
-- Sources only live as long as their weapon is equipped.
export type ContentSource = Instance | string

export type LineData = {
	Name: string,
	Text: string,
}

export type ConversationChoice = { string }

export type ConversationData = { ConversationChoice }

export type LinesIndex = {
	[string]: { LineData } | { [string]: ConversationData },
}

export type ModData = {
	Name: string,
	Path: string,
}

-- A ModFolder is a root folder holding named, readable data directories (Config, Lines, ...).
-- A kind (ModNPC, ModWeapon, ...) declares which directories it requires and how each one is validated.
export type ModFolderValidator = (Folder) -> (boolean, string)

export type ModFolderDirectory = {
	Name: string,
	Validator: ModFolderValidator,
}

export type ModFolderKind = {
	Name: string,
	-- name of the root folder inside whatever carries it (character, tool, ...)
	RootName: string,
	-- name of the sample configuration under ServerScriptService.ModAssets that Config directories must match
	SchemaName: string?,
	Directories: { ModFolderDirectory },
}

export type ContentDeliveryNetwork = {}

return TypeCDN
