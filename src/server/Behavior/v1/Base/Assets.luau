local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

local Assets = {}
Assets.__index = Assets

type AssetIndex = TypeCDN.AssetIndex
type ContentSource = TypeCDN.ContentSource

local WeaponEvents = TypeCharacterEvents.Names.Weapon
local ContentEvents = TypeCharacterEvents.Names.Content

-- The NPC's own content. It is always the first source, so it wins over everything a weapon brings.
Assets.BaseSource = "Base"

local function emptyIndex(): AssetIndex
	return {
		Sounds = { Categories = {}, Individual = {}, Groups = {} },
		Animations = {},
		VFX = { Groups = {}, Individual = {} },
	}
end

-- The NPC's assets, plus those of every source added to it (an equipped weapon, ...). A source lives from AddSource
-- to RemoveSource: ContentSourceAdded / ContentSourceRemoved tell the modules holding loaded content to load and
-- unload their part of it.
--
-- Lookups search the sources in the order they were added, the NPC first, and the first one that has the asset
-- wins. A lookup that names a source searches that source first and then the NPC only, so an asset can be asked for
-- in the context it belongs to. Every lookup returns the asset and the source it was found in.
function Assets.new(Base: any, character: Model)
	local self = setmetatable({}, Assets)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Sources = { [Assets.BaseSource] = self.CharacterAPI:GetAssetsIndex() or emptyIndex() }
	self.Order = { Assets.BaseSource }
	self.DestroyingConnections = {}

	-- print("Assets loaded", self.Sources[Assets.BaseSource])

	self.Subscriptions = {
		Base.Events:Subscribe(WeaponEvents.Equipped, function(payload: TypeCharacterEvents.WeaponChanged)
			self:_weaponEquipped(payload.Weapon)
		end),
		Base.Events:Subscribe(WeaponEvents.Unequipped, function(payload: TypeCharacterEvents.WeaponChanged)
			self:RemoveSource(payload.Weapon)
		end),
	}

	return self
end

function Assets:_weaponEquipped(weapon: Instance)
	if self.Sources[weapon] then
		return
	end

	local index = self.CharacterAPI:GetAssetsIndex(weapon)
	if not index then
		warn("Could not read the assets of weapon:", weapon:GetFullName())
		return
	end

	self:AddSource(weapon, index)
end

function Assets:AddSource(source: ContentSource, index: AssetIndex): boolean
	if self.Sources[source] then
		warn("Assets source already added:", source)
		return false
	end

	self.Sources[source] = index
	table.insert(self.Order, source)

	-- A weapon destroyed while equipped never gets a WeaponUnequipped
	if typeof(source) == "Instance" then
		self.DestroyingConnections[source] = source.Destroying:Connect(function()
			self:RemoveSource(source)
		end)
	end

	self.Base.Events:Dispatch(ContentEvents.SourceAdded, {
		Source = source,
		Index = index,
	} :: TypeCharacterEvents.ContentSourceAdded)
	return true
end

-- The listeners see the source's data one last time, then it is gone. The NPC's own source cannot be removed.
function Assets:RemoveSource(source: ContentSource): boolean
	if source == Assets.BaseSource or not self.Sources[source] then
		return false
	end

	self.Base.Events:Dispatch(ContentEvents.SourceRemoved, { Source = source } :: TypeCharacterEvents.ContentSourceRemoved)

	local connection = self.DestroyingConnections[source]
	if connection then
		connection:Disconnect()
		self.DestroyingConnections[source] = nil
	end

	self.Sources[source] = nil
	table.remove(self.Order, table.find(self.Order, source))
	return true
end

function Assets:HasSource(source: ContentSource): boolean
	return self.Sources[source] ~= nil
end

-- Every live source in lookup order, the NPC first
function Assets:GetSources(): { ContentSource }
	return table.clone(self.Order)
end

-- The index of one source, the NPC's by default
function Assets:GetData(source: ContentSource?): AssetIndex
	return self.Sources[source or Assets.BaseSource] or emptyIndex()
end

-- The sources a lookup searches, in order. Modules that keep content loaded per source search it the same way.
function Assets:GetSearchOrder(source: ContentSource?): { ContentSource }
	if source == nil then
		return table.clone(self.Order)
	end

	if source ~= Assets.BaseSource and self.Sources[source] then
		return { source, Assets.BaseSource }
	end

	return { Assets.BaseSource }
end

function Assets:_find(source: ContentSource?, lookup: (AssetIndex) -> any): (any, ContentSource?)
	for _, candidate in ipairs(self:GetSearchOrder(source)) do
		local found = lookup(self.Sources[candidate])
		if found ~= nil then
			return found, candidate
		end
	end

	return nil, nil
end

function Assets:GetSoundCategory(categoryName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.Sounds.Categories[categoryName]
	end)
end

function Assets:GetSound(soundName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.Sounds.Individual[soundName]
	end)
end

function Assets:GetSoundGroup(groupName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.Sounds.Groups[groupName]
	end)
end

function Assets:GetAnimationCategory(categoryName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.Animations[categoryName]
	end)
end

-- "Category/Name" looks in that category only, a bare name in every category of every searched source
function Assets:GetAnimation(animationKey: string, source: ContentSource?)
	local parts = string.split(animationKey, "/")

	return self:_find(source, function(index)
		if #parts == 2 then
			for _, animation in ipairs(index.Animations[parts[1]] or {}) do
				if animation.Name == parts[2] then
					return animation
				end
			end

			return nil
		end

		for _, category in pairs(index.Animations) do
			for _, animation in ipairs(category) do
				if animation.Name == animationKey then
					return animation
				end
			end
		end

		return nil
	end)
end

-- Picks from the first searched source that has any animation in the category
function Assets:GetRandomAnimationFromCategory(categoryName: string, source: ContentSource?)
	return self:_find(source, function(index)
		local category = index.Animations[categoryName]
		if not category or #category == 0 then
			return nil
		end

		return category[math.random(1, #category)]
	end)
end

function Assets:GetVFX(vfxName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.VFX.Individual[vfxName]
	end)
end

function Assets:GetVFXGroup(groupName: string, source: ContentSource?)
	return self:_find(source, function(index)
		return index.VFX.Groups[groupName]
	end)
end

function Assets:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end
	for _, connection in pairs(self.DestroyingConnections) do
		connection:Disconnect()
	end

	self.Subscriptions = {}
	self.DestroyingConnections = {}
	self.Sources = {}
	self.Order = {}
	self.CharacterAPI = nil
	self.Base = nil
end

return Assets
