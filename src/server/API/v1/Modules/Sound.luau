local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local TypeSound = require(ServerScriptService.ModNPCServer.Types.v1.TypeSound)
local CharacterUtility = require(script.Parent.CharacterUtility)
local Sound = {}

type SoundData = TypeCDN.SoundData
type SoundList = TypeSound.SoundList

local function response(
	success: boolean,
	statusCode: number,
	message: string?,
	data: any?
): TypeModuleResponse.ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = statusCode,
		Message = message,
		Data = data,
	}
end

-- Name and SoundId are required, the rest fall back to the Sound defaults when omitted
local function validateSoundData(soundData: any): string?
	if typeof(soundData) ~= "table" then
		return "sound data is not a table"
	end

	if typeof(soundData.Name) ~= "string" or soundData.Name == "" then
		return "Name must be a non-empty string"
	end

	if typeof(soundData.SoundId) ~= "string" then
		return "SoundId must be a string"
	end

	if soundData.Volume ~= nil and typeof(soundData.Volume) ~= "number" then
		return "Volume must be a number"
	end

	if soundData.PlaybackSpeed ~= nil and typeof(soundData.PlaybackSpeed) ~= "number" then
		return "PlaybackSpeed must be a number"
	end

	if soundData.Looped ~= nil and typeof(soundData.Looped) ~= "boolean" then
		return "Looped must be a boolean"
	end

	return nil
end

-- Loads each sound into the character's root part. A sound whose name is already taken under the root part
-- (by an existing child or by an earlier sound in the same list) is warned about and skipped, never replaced.
function Sound.loadSounds(character: Model, sounds: { SoundData }): TypeModuleResponse.ModuleResponse
	if typeof(sounds) ~= "table" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Sounds must be a list of sound data")
	end

	local rootPart = CharacterUtility._getRootPart(character)
	if not rootPart then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, "Character has no root part")
	end

	local result: TypeSound.SoundLoadResult = { Loaded = {}, Skipped = {} }
	for _, soundData in ipairs(sounds) do
		local invalidReason = validateSoundData(soundData)
		if invalidReason then
			warn(character.Name, "skipping invalid sound:", invalidReason)
			local skippedName = if typeof(soundData) == "table" and soundData.Name then tostring(soundData.Name) else "?"
			table.insert(result.Skipped, skippedName)
			continue
		end

		if rootPart:FindFirstChild(soundData.Name) then
			warn(character.Name, "already has an instance named", soundData.Name, "under its root part; skipping sound")
			table.insert(result.Skipped, soundData.Name)
			continue
		end

		local sound = Instance.new("Sound")
		sound.Name = soundData.Name
		sound.SoundId = soundData.SoundId
		if soundData.Volume ~= nil then
			sound.Volume = soundData.Volume
		end
		if soundData.PlaybackSpeed ~= nil then
			sound.PlaybackSpeed = soundData.PlaybackSpeed
		end
		if soundData.Looped ~= nil then
			sound.Looped = soundData.Looped
		end
		sound.Parent = rootPart

		result.Loaded[soundData.Name] = sound
	end

	local message = if #result.Skipped > 0
		then "Sounds loaded, " .. #result.Skipped .. " skipped"
		else "Sounds loaded"
	return response(true, TypeRequests.Enums.StatusCode.Success, message, result)
end

local function isLoadedSound(sound: any): boolean
	return typeof(sound) == "Instance" and sound:IsA("Sound") and sound.Parent ~= nil
end

local function getLoadedSound(soundName: string, sounds: SoundList): Sound?
	if typeof(soundName) ~= "string" or typeof(sounds) ~= "table" then
		return nil
	end

	local sound = sounds[soundName]
	if not isLoadedSound(sound) then
		return nil
	end

	return sound
end

-- "groupSound_2" -> "groupSound", "Stagger2" -> "Stagger" (the underscore is optional); a name without a numeric suffix
-- is its own prefix. Keep in step with the behavior layer's soundPrefix.
local function getSoundPrefix(soundName: string): string
	return string.match(soundName, "^(.+)_%d+$") or string.match(soundName, "^(.+%D)%d+$") or soundName
end

-- Every loaded sound sharing the prefix, in name order so the result is stable
local function getSoundsByPrefix(prefix: string, sounds: SoundList): { Sound }
	local matches = {}
	if typeof(prefix) ~= "string" or typeof(sounds) ~= "table" then
		return matches
	end

	local names = {}
	for soundName, sound in pairs(sounds) do
		if isLoadedSound(sound) and getSoundPrefix(soundName) == prefix then
			table.insert(names, soundName)
		end
	end
	table.sort(names)

	for _, soundName in ipairs(names) do
		table.insert(matches, sounds[soundName])
	end

	return matches
end

-- A looping sound that is already playing is left alone; any other sound is restarted so repeated one-shots are heard
local function startSound(sound: Sound)
	if sound.IsPlaying then
		if sound.Looped then
			return
		end
		sound.TimePosition = 0
	end

	sound:Play()
end

local function noSoundsResponse(prefix: string): TypeModuleResponse.ModuleResponse
	return response(false, TypeRequests.Enums.StatusCode.NotFound, "No sounds loaded with prefix: " .. tostring(prefix))
end

function Sound.playSound(_character: Model, soundName: string, sounds: SoundList): TypeModuleResponse.ModuleResponse
	local sound = getLoadedSound(soundName, sounds)
	if not sound then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, "Sound is not loaded: " .. tostring(soundName))
	end

	startSound(sound)
	return response(true, TypeRequests.Enums.StatusCode.Success, "Sound playing", sound)
end

-- Plays every sound of the group that shares the prefix. Data is the list of sounds started.
function Sound.playSoundGroup(_character: Model, prefix: string, sounds: SoundList): TypeModuleResponse.ModuleResponse
	local matches = getSoundsByPrefix(prefix, sounds)
	if #matches == 0 then
		return noSoundsResponse(prefix)
	end

	for _, sound in ipairs(matches) do
		startSound(sound)
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Sound group playing", matches)
end

-- Plays one random sound out of the category that shares the prefix. Data is the sound started.
-- playbackSpeed is optional; when given it is applied to the sound before it plays.
function Sound.playSoundCategory(
	_character: Model,
	prefix: string,
	sounds: SoundList,
	playbackSpeed: number?
): TypeModuleResponse.ModuleResponse
	if playbackSpeed ~= nil and (typeof(playbackSpeed) ~= "number" or playbackSpeed <= 0) then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Playback speed must be a positive number")
	end

	local matches = getSoundsByPrefix(prefix, sounds)
	if #matches == 0 then
		return noSoundsResponse(prefix)
	end

	local sound = matches[math.random(1, #matches)]
	if playbackSpeed then
		sound.PlaybackSpeed = playbackSpeed
	end
	startSound(sound)
	return response(true, TypeRequests.Enums.StatusCode.Success, "Sound category playing", sound)
end

function Sound.stopSound(_character: Model, soundName: string, sounds: SoundList): TypeModuleResponse.ModuleResponse
	local sound = getLoadedSound(soundName, sounds)
	if not sound then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, "Sound is not loaded: " .. tostring(soundName))
	end

	sound:Stop()
	return response(true, TypeRequests.Enums.StatusCode.Success, "Sound stopped", sound)
end

-- Stops every sound sharing the prefix, whether it came from a group or a category
function Sound.stopSoundsByPrefix(
	_character: Model,
	prefix: string,
	sounds: SoundList
): TypeModuleResponse.ModuleResponse
	local matches = getSoundsByPrefix(prefix, sounds)
	if #matches == 0 then
		return noSoundsResponse(prefix)
	end

	for _, sound in ipairs(matches) do
		sound:Stop()
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Sounds stopped", matches)
end

function Sound.unloadAllSounds(_character: Model, sounds: SoundList): TypeModuleResponse.ModuleResponse
	if typeof(sounds) ~= "table" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Sounds must be a table of loaded sounds")
	end

	for _, sound in pairs(sounds) do
		if typeof(sound) == "Instance" then
			sound:Destroy()
		end
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Sounds unloaded")
end

function Sound.init(_)
	print("V1 Sound initialized")
end

return Sound
