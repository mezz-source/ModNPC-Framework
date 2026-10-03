local ServerScriptService = game:GetService("ServerScriptService")
local AssetsNetwork = {}

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)

type AnimationData = TypeCDN.AnimationData
type AssetIndex = TypeCDN.AssetIndex
type ModuleResponse = TypeModuleResponse.ModuleResponse
type SoundData = TypeCDN.SoundData
type VFXData = TypeCDN.VFXData

local contentDeliveryNetwork

local function response(success: boolean, message: string, data: any?): ModuleResponse
	return {
		Success = success,
		PassResponse = true,
		StatusCode = success and TypeRequests.Enums.StatusCode.Success or TypeRequests.Enums.StatusCode.Conflict,
		Message = message,
		Data = data,
	}
end

local function getFolder(parent: Instance, name: string): Folder?
	local child = parent:FindFirstChild(name)
	if not child then
		return nil
	end

	return child
end

local function normalizeSound(sound: Instance): SoundData?
	if not sound:IsA("Sound") then
		return nil
	end

	return {
		Name = sound.Name,
		SoundId = sound.SoundId,
		Volume = sound.Volume,
		PlaybackSpeed = sound.PlaybackSpeed,
		Looped = sound.Looped,
	}
end

local function normalizeAnimation(animation: Instance): AnimationData?
	if not animation:IsA("Animation") then
		return nil
	end

	return {
		Name = animation.Name,
		AnimationId = animation.AnimationId,
	}
end

local function normalizeVFX(effect: Instance): VFXData?
	if effect:IsA("ParticleEmitter") then
		return { Name = effect.Name, Type = "ParticleEmitter" }
	end

	if effect:IsA("PointLight") then
		return { Name = effect.Name, Type = "PointLight" }
	end

	return nil
end

local function getAssetFolder(character: Model): Folder?
	local assetsResponse = contentDeliveryNetwork.getAssetsFolder(character)
	if not assetsResponse.Success or not assetsResponse.Data then
		return nil
	end

	return assetsResponse.Data
end

local function getSoundRoot(assetsFolder: Folder, rootName: string): Folder?
	local sounds = getFolder(assetsFolder, "Sounds")
	return sounds and getFolder(sounds, rootName) or nil
end

local function getNamedFolder(root: Folder, name: string): Folder?
	local folder = root:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	return folder
end

local function getSoundCategory(assetsFolder: Folder, categoryName: string): { SoundData }?
	local categories = getSoundRoot(assetsFolder, "Categories")
	local category = categories and getNamedFolder(categories, categoryName)
	if not category then
		return nil
	end

	local sounds = {}
	for _, child in ipairs(category:GetChildren()) do
		local sound = normalizeSound(child)
		if not sound then
			return nil
		end
		table.insert(sounds, sound)
	end

	return sounds
end

local function getSoundByName(assetsFolder: Folder, soundName: string): SoundData?
	local individual = getSoundRoot(assetsFolder, "Individual")
	local sound = individual and individual:FindFirstChild(soundName)
	return sound and normalizeSound(sound) or nil
end

local function getSoundGroup(assetsFolder: Folder, groupName: string): { SoundData }?
	local groups = getSoundRoot(assetsFolder, "Groups")
	local group = groups and getNamedFolder(groups, groupName)
	if not group then
		return nil
	end

	local sounds = {}
	for _, child in ipairs(group:GetChildren()) do
		local sound = normalizeSound(child)
		if not sound then
			return nil
		end
		table.insert(sounds, sound)
	end

	return sounds
end

local function getAnimationCategory(assetsFolder: Folder, categoryName: string): { AnimationData }?
	local animations = getFolder(assetsFolder, "Animations")
	local category = animations and getNamedFolder(animations, categoryName)
	if not category then
		return nil
	end

	local result = {}
	for _, child in ipairs(category:GetChildren()) do
		local animation = normalizeAnimation(child)
		if not animation then
			return nil
		end
		table.insert(result, animation)
	end

	return result
end

local function getVFXFolder(assetsFolder: Folder, folderName: string): { VFXData }?
	local vfx = getFolder(assetsFolder, "VFX")
	local folder = vfx and getNamedFolder(vfx, folderName)
	if not folder then
		return nil
	end

	local result = {}
	for _, descendant in ipairs(folder:GetDescendants()) do
		local effect = normalizeVFX(descendant)
		if effect then
			table.insert(result, effect)
		end
	end

	return result
end

local function getAssetsIndex(assetsFolder: Folder): AssetIndex
	local index: AssetIndex = {
		Sounds = { Categories = {}, Individual = {}, Groups = {} },
		Animations = {},
		VFX = {},
	}
	local sounds = getFolder(assetsFolder, "Sounds")
	local categories = sounds and getFolder(sounds, "Categories")
	local individual = sounds and getFolder(sounds, "Individual")
	local groups = sounds and getFolder(sounds, "Groups")
	local animations = getFolder(assetsFolder, "Animations")
	local vfx = getFolder(assetsFolder, "VFX")

	if categories then
		for _, category in ipairs(categories:GetChildren()) do
			if category:IsA("Folder") then
				local data = getSoundCategory(assetsFolder, category.Name)
				if data then
					index.Sounds.Categories[category.Name] = data
				end
			end
		end
	end

	if individual then
		for _, sound in ipairs(individual:GetChildren()) do
			local data = normalizeSound(sound)
			if data then
				index.Sounds.Individual[sound.Name] = data
			end
		end
	end

	if groups then
		for _, group in ipairs(groups:GetChildren()) do
			if group:IsA("Folder") then
				local data = getSoundGroup(assetsFolder, group.Name)
				if data then
					index.Sounds.Groups[group.Name] = data
				end
			end
		end
	end

	if animations then
		for _, category in ipairs(animations:GetChildren()) do
			if category:IsA("Folder") then
				local data = getAnimationCategory(assetsFolder, category.Name)
				if data then
					index.Animations[category.Name] = data
				end
			end
		end
	end

	if vfx then
		for _, folder in ipairs(vfx:GetChildren()) do
			if folder:IsA("Folder") then
				local data = getVFXFolder(assetsFolder, folder.Name)
				if data then
					index.VFX[folder.Name] = data
				end
			end
		end
	end

	return index
end

function AssetsNetwork.init(network)
	contentDeliveryNetwork = network
end

function AssetsNetwork.validateAssetsFolder(assetsFolder: Folder): (boolean, string)
	for _, requiredFolderName in ipairs({ "Sounds", "Animations", "VFX" }) do
		if not getFolder(assetsFolder, requiredFolderName) then
			return false, requiredFolderName .. " folder is missing or invalid"
		end
	end

	local sounds = getFolder(assetsFolder, "Sounds")
	for _, requiredSoundFolder in ipairs({ "Categories", "Individual", "Groups" }) do
		if not sounds or not getFolder(sounds, requiredSoundFolder) then
			return false, "Sounds/" .. requiredSoundFolder .. " folder is missing or invalid"
		end
	end

	return true, ""
end

function AssetsNetwork.getSoundCategory(character: Model, categoryName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local sounds = assetsFolder and getSoundCategory(assetsFolder, categoryName)
	if not sounds then
		return response(false, "Sound category not found or malformed")
	end

	return response(true, "Sound category retrieved", sounds)
end

function AssetsNetwork.getSound(character: Model, soundName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local sound = assetsFolder and getSoundByName(assetsFolder, soundName)
	if not sound then
		return response(false, "Sound not found or malformed")
	end

	return response(true, "Sound retrieved", sound)
end

function AssetsNetwork.getSoundGroup(character: Model, groupName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local sounds = assetsFolder and getSoundGroup(assetsFolder, groupName)
	if not sounds then
		return response(false, "Sound group not found or malformed")
	end

	return response(true, "Sound group retrieved", sounds)
end

function AssetsNetwork.getAnimationCategory(character: Model, categoryName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local animations = assetsFolder and getAnimationCategory(assetsFolder, categoryName)
	if not animations then
		return response(false, "Animation category not found or malformed")
	end

	return response(true, "Animation category retrieved", animations)
end

function AssetsNetwork.getVFX(character: Model, folderName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local effects = assetsFolder and getVFXFolder(assetsFolder, folderName)
	if not effects then
		return response(false, "VFX folder not found or malformed")
	end

	return response(true, "VFX retrieved", effects)
end

function AssetsNetwork.getAssetsIndex(character: Model): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	if not assetsFolder then
		return response(false, "Assets folder not found")
	end

	return response(true, "Asset index generated", getAssetsIndex(assetsFolder))
end

return AssetsNetwork
