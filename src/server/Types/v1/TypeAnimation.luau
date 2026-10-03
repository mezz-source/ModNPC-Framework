local TypeAnimation = {}

export type AnimationInfo = {
	Priority: Enum.AnimationPriority?,
	Loop: boolean?,
	FadeTime: number?,
	Weight: number?,
}

export type TrackList = { [string]: AnimationTrack }

export type AnimationHandle = {
	Stopped: any,
	Ended: any,
	DidLoop: any,
	Looped: any,
	KeyframeReached: any,
	GetMarkerReachedSignal: (self: AnimationHandle, markerName: string) -> any,
	WaitForMarker: (self: AnimationHandle, markerName: string) -> any,
	Stop: (self: AnimationHandle, fadeTime: number?) -> (),
	AdjustSpeed: (self: AnimationHandle, speed: number) -> (),
	Destroy: (self: AnimationHandle) -> (),
}

return TypeAnimation
