local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeSound = require(ServerScriptService.ModNPCServer.Types.v1.TypeSound)

local Sound = {}
Sound.__index = Sound

type ContentSource = TypeCDN.ContentSource
type SoundData = TypeCDN.SoundData
type SoundList = TypeSound.SoundList

-- What one source has loaded
type SourceSounds = {
	Individual: SoundList,
	Categories: SoundList,
	Groups: SoundList,
}

local ContentEvents = TypeCharacterEvents.Names.Content

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Categories and groups are folders of prefix_<number> (or prefix<number>) sounds; flattened in folder name order so which sound
-- keeps a contested name is stable
local function flatten(folders: { [string]: { SoundData } }): { SoundData }
	local sounds = {}
	for _, folderName in ipairs(sortedKeys(folders)) do
		for _, soundData in ipairs(folders[folderName]) do
			table.insert(sounds, soundData)
		end
	end
	return sounds
end

local function individualSounds(individual: { [string]: SoundData }): { SoundData }
	local sounds = {}
	for _, name in ipairs(sortedKeys(individual)) do
		table.insert(sounds, individual[name])
	end
	return sounds
end

-- "groupSound_2" -> "groupSound", "Stagger2" -> "Stagger" (the underscore is optional); a name without a numeric suffix
-- is its own prefix. Keep in step with the API's getSoundPrefix.
local function soundPrefix(soundName: string): string
	return string.match(soundName, "^(.+)_%d+$") or string.match(soundName, "^(.+%D)%d+$") or soundName
end

local function hasPrefix(soundList: SoundList, prefix: string): boolean
	for soundName in pairs(soundList) do
		if soundPrefix(soundName) == prefix then
			return true
		end
	end

	return false
end

function Sound:_load(sounds: { SoundData }): SoundList
	local result = self.CharacterAPI:LoadSounds(sounds)
	if not result then
		warn("Failed to load sounds for character:", self.Character.Name)
		return {}
	end

	return result.Loaded
end

-- Individual sounds load first, then categories, then groups; a name already taken by an earlier sound is skipped.
-- That includes a name another source loaded first, so the earlier source keeps the sound.
function Sound:_loadSource(source: ContentSource, soundIndex: TypeCDN.SoundIndex)
	self.sources[source] = {
		Individual = self:_load(individualSounds(soundIndex.Individual)),
		Categories = self:_load(flatten(soundIndex.Categories)),
		Groups = self:_load(flatten(soundIndex.Groups)),
	}
end

function Sound:_unloadSource(source: ContentSource)
	local loaded = self.sources[source]
	if not loaded then
		return
	end

	for _, soundList in pairs(loaded) do
		self.CharacterAPI:UnloadAllSounds(soundList)
	end

	self.sources[source] = nil
end

function Sound.new(Base: any, character: Model)
	local self = setmetatable({}, Sound)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.sources = {} :: { [ContentSource]: SourceSounds }

	self:_loadSource(Base.Assets.BaseSource, Base.Assets:GetData().Sounds)

	-- A weapon's sounds are only loaded while the weapon is equipped
	self.Subscriptions = {
		Base.Events:Subscribe(ContentEvents.SourceAdded, function(payload: TypeCharacterEvents.ContentSourceAdded)
			self:_loadSource(payload.Source, payload.Index.Sounds)
		end),
		Base.Events:Subscribe(ContentEvents.SourceRemoved, function(payload: TypeCharacterEvents.ContentSourceRemoved)
			self:_unloadSource(payload.Source)
		end),
	}

	return self
end

-- The loaded sources a lookup searches, in order (see Assets:GetSearchOrder)
function Sound:_searchOrder(source: ContentSource?): { SourceSounds }
	local order = {}
	for _, candidate in ipairs(self.Base.Assets:GetSearchOrder(source)) do
		local loaded = self.sources[candidate]
		if loaded then
			table.insert(order, loaded)
		end
	end

	return order
end

-- The list of the first searched source that has the individual sound
function Sound:_findIndividual(soundName: string, source: ContentSource?): SoundList?
	for _, loaded in ipairs(self:_searchOrder(source)) do
		if loaded.Individual[soundName] ~= nil then
			return loaded.Individual
		end
	end

	return nil
end

-- The list of the first searched source that has a sound with the prefix
function Sound:_findPrefix(listName: "Categories" | "Groups", prefix: string, source: ContentSource?): SoundList?
	for _, loaded in ipairs(self:_searchOrder(source)) do
		if hasPrefix(loaded[listName], prefix) then
			return loaded[listName]
		end
	end

	return nil
end

-- Sounds are searched like assets: the NPC first, then weapons in the order they were equipped. A source passed in
-- is searched first, and then the NPC.
function Sound:IsLoaded(soundName: string, source: ContentSource?): boolean
	return self:_findIndividual(soundName, source) ~= nil
end

-- Individual sounds are played and stopped by their exact name. Returns false if it was never loaded
-- (e.g. skipped for a name conflict).
function Sound:Play(soundName: string, source: ContentSource?): boolean
	local soundList = self:_findIndividual(soundName, source)
	if not soundList then
		warn("Sound is not loaded:", soundName, "for character:", self.Character.Name)
		return false
	end

	self.CharacterAPI:PlaySound(soundName, soundList)
	return true
end

function Sound:Stop(soundName: string, source: ContentSource?): boolean
	local soundList = self:_findIndividual(soundName, source)
	if not soundList then
		warn("Sound is not loaded:", soundName, "for character:", self.Character.Name)
		return false
	end

	self.CharacterAPI:StopSound(soundName, soundList)
	return true
end

-- Plays every group sound named prefix_<number> of the first source that has any. Returns false if no sound matched.
function Sound:PlayGroup(prefix: string, source: ContentSource?): boolean
	local soundList = self:_findPrefix("Groups", prefix, source)
	if not soundList then
		return false
	end

	local played = self.CharacterAPI:PlaySoundGroup(prefix, soundList)
	return played ~= nil and #played > 0
end

-- Plays one random category sound named prefix_<number> of the first source that has any, optionally at a playback
-- speed. Returns false if no sound matched.
function Sound:PlayCategory(prefix: string, playbackSpeed: number?, source: ContentSource?): boolean
	local soundList = self:_findPrefix("Categories", prefix, source)
	if not soundList then
		return false
	end

	return self.CharacterAPI:PlaySoundCategory(prefix, soundList, playbackSpeed) ~= nil
end

-- Stopping covers every searched source, since a prefix can be playing in more than one
function Sound:StopGroup(prefix: string, source: ContentSource?)
	for _, loaded in ipairs(self:_searchOrder(source)) do
		if hasPrefix(loaded.Groups, prefix) then
			self.CharacterAPI:StopSoundsByPrefix(prefix, loaded.Groups)
		end
	end
end

function Sound:StopCategory(prefix: string, source: ContentSource?)
	for _, loaded in ipairs(self:_searchOrder(source)) do
		if hasPrefix(loaded.Categories, prefix) then
			self.CharacterAPI:StopSoundsByPrefix(prefix, loaded.Categories)
		end
	end
end

function Sound:StopAll()
	for _, loaded in pairs(self.sources) do
		for _, soundList in pairs(loaded) do
			for soundName in pairs(soundList) do
				self.CharacterAPI:StopSound(soundName, soundList)
			end
		end
	end
end

function Sound:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end
	self.Subscriptions = {}

	for source in pairs(table.clone(self.sources)) do
		self:_unloadSource(source)
	end
end

return Sound
