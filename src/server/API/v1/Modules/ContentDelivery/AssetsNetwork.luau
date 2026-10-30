local ServerScriptService = game:GetService("ServerScriptService")
local AssetsNetwork = {}

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.Parent.CharacterUtility)
local ModFolder = require(script.Parent.ModFolder)

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

-- Why an instance cannot be a VFX, nil when it can. Validation fails the folder with this; indexing skips the effect.
local function getVFXProblem(effect: Instance): string?
	if not effect:IsA("ParticleEmitter") and not effect:IsA("PointLight") then
		return effect.ClassName .. " is not a supported VFX (ParticleEmitter or PointLight)"
	end

	local emitCount = effect:GetAttribute("EmitCount")
	if emitCount ~= nil and (typeof(emitCount) ~= "number" or emitCount < 0) then
		return "EmitCount attribute must be a number of 0 or more"
	end

	local enableTime = effect:GetAttribute("EnableTime")
	if enableTime ~= nil and (typeof(enableTime) ~= "number" or enableTime <= 0) then
		return "EnableTime attribute must be a number above 0"
	end

	if effect:IsA("PointLight") and enableTime == nil then
		return "a PointLight needs an EnableTime attribute, otherwise it is never enabled"
	end

	return nil
end

local function normalizeVFX(effect: Instance): VFXData?
	if getVFXProblem(effect) then
		return nil
	end

	local enableTime = effect:GetAttribute("EnableTime")
	if effect:IsA("ParticleEmitter") then
		return {
			Name = effect.Name,
			Type = "ParticleEmitter",
			Template = effect,
			EmitCount = effect:GetAttribute("EmitCount") or 1,
			EnableTime = enableTime,
		}
	end

	if effect:IsA("PointLight") then
		return { Name = effect.Name, Type = "PointLight", Template = effect, EnableTime = enableTime }
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

local function getVFXRoot(assetsFolder: Folder, rootName: string): Folder?
	local vfx = getFolder(assetsFolder, "VFX")
	return vfx and getNamedFolder(vfx, rootName) or nil
end

-- Every effect under a group folder (nested folders are only for organising), nil plus the reason if one is unusable
local function readVFXGroup(group: Folder): ({ VFXData }?, string?)
	local effects = {}
	for _, descendant in ipairs(group:GetDescendants()) do
		if descendant:IsA("Folder") then
			continue
		end

		local problem = getVFXProblem(descendant)
		if problem then
			return nil, descendant:GetFullName() .. ": " .. problem
		end

		local effect = normalizeVFX(descendant)
		if effect then
			table.insert(effects, effect)
		end
	end

	return effects, nil
end

local function getVFXGroup(assetsFolder: Folder, groupName: string): { VFXData }?
	local groups = getVFXRoot(assetsFolder, "Groups")
	local group = groups and getNamedFolder(groups, groupName)
	if not group then
		return nil
	end

	local effects = readVFXGroup(group)
	if not effects or #effects == 0 then
		return nil
	end

	return effects
end

local function getVFXByName(assetsFolder: Folder, vfxName: string): VFXData?
	local individual = getVFXRoot(assetsFolder, "Individual")
	local effect = individual and individual:FindFirstChild(vfxName)
	return effect and normalizeVFX(effect) or nil
end

local function getAssetsIndex(assetsFolder: Folder): AssetIndex
	local index: AssetIndex = {
		Sounds = { Categories = {}, Individual = {}, Groups = {} },
		Animations = {},
		VFX = { Groups = {}, Individual = {} },
	}
	local sounds = getFolder(assetsFolder, "Sounds")
	local categories = sounds and getFolder(sounds, "Categories")
	local individual = sounds and getFolder(sounds, "Individual")
	local groups = sounds and getFolder(sounds, "Groups")
	local animations = getFolder(assetsFolder, "Animations")
	local vfxGroups = getVFXRoot(assetsFolder, "Groups")
	local vfxIndividual = getVFXRoot(assetsFolder, "Individual")

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

	if vfxGroups then
		for _, group in ipairs(vfxGroups:GetChildren()) do
			if group:IsA("Folder") then
				local data = getVFXGroup(assetsFolder, group.Name)
				if data then
					index.VFX.Groups[group.Name] = data
				end
			end
		end
	end

	if vfxIndividual then
		for _, effect in ipairs(vfxIndividual:GetChildren()) do
			local data = normalizeVFX(effect)
			if data then
				index.VFX.Individual[effect.Name] = data
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

	local vfx = getFolder(assetsFolder, "VFX")
	for _, requiredVFXFolder in ipairs({ "Groups", "Individual" }) do
		if not vfx or not getVFXRoot(assetsFolder, requiredVFXFolder) then
			return false, "VFX/" .. requiredVFXFolder .. " folder is missing or invalid"
		end
	end

	-- A VFX that cannot be played fails the assets rather than silently never showing
	local vfxGroups = getVFXRoot(assetsFolder, "Groups")
	for _, group in ipairs(vfxGroups and vfxGroups:GetChildren() or {}) do
		if not group:IsA("Folder") then
			return false, group:GetFullName() .. ": a VFX group must be a Folder"
		end

		local _, problem = readVFXGroup(group)
		if problem then
			return false, problem
		end
	end

	local vfxIndividual = getVFXRoot(assetsFolder, "Individual")
	for _, effect in ipairs(vfxIndividual and vfxIndividual:GetChildren() or {}) do
		local problem = getVFXProblem(effect)
		if problem then
			return false, effect:GetFullName() .. ": " .. problem
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

function AssetsNetwork.getVFX(character: Model, vfxName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local effect = assetsFolder and getVFXByName(assetsFolder, vfxName)
	if not effect then
		return response(false, "VFX not found or malformed")
	end

	return response(true, "VFX retrieved", effect)
end

function AssetsNetwork.getVFXGroup(character: Model, groupName: string): ModuleResponse
	local assetsFolder = getAssetFolder(character)
	local effects = assetsFolder and getVFXGroup(assetsFolder, groupName)
	if not effects then
		return response(false, "VFX group not found, empty or malformed")
	end

	return response(true, "VFX group retrieved", effects)
end

-- The container is a character (its ModNPC folder) or a weapon (its ModWeapon folder); both are indexed the same way
function AssetsNetwork.getAssetsIndex(container: Instance): ModuleResponse
	if typeof(container) ~= "Instance" then
		return response(false, "Container must be an Instance")
	end

	local assetsFolder = ModFolder.findDirectory(container, CharacterUtility.CoreFolderNames.Assets)
	if not assetsFolder then
		return response(false, "Assets folder not found")
	end

	return response(true, "Asset index generated", getAssetsIndex(assetsFolder))
end

return AssetsNetwork
