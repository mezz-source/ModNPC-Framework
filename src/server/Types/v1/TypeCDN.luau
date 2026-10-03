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

export type ParticleEmitterData = {
	Name: string,
	Type: "ParticleEmitter",
}

export type PointLightData = {
	Name: string,
	Type: "PointLight",
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
	[string]: { VFXData },
}

export type AssetIndex = {
	Sounds: SoundIndex,
	Animations: AnimationIndex,
	VFX: VFXIndex,
}

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

export type ContentDeliveryNetwork = {}

return TypeCDN
