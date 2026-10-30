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
	GetLength: (self: AnimationHandle) -> number,
	-- animation seconds; nil until the marker times have been read (see Animation/MarkerTimes)
	GetMarkerTime: (self: AnimationHandle, markerName: string) -> number?,
	-- the ones below are real seconds from now at the current playback speed, nil when the point won't be reached
	GetTimeUntil: (self: AnimationHandle, animationTime: number) -> number?,
	GetTimeUntilMarker: (self: AnimationHandle, markerName: string) -> number?,
	GetTimeRemaining: (self: AnimationHandle) -> number?,
	Destroy: (self: AnimationHandle) -> (),
}

return TypeAnimation
