local TypeSound = {}

-- Loaded sounds keyed by name
export type SoundList = { [string]: Sound }

export type SoundLoadResult = {
	-- Sounds created under the root part, keyed by name
	Loaded: { [string]: Sound },
	-- Names of requested sounds that were not loaded (name conflict or invalid data)
	Skipped: { string },
}

return TypeSound
