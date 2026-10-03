local ServerScriptService = game:GetService("ServerScriptService")
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)

local Assets = {}
Assets.__index = Assets

local Modules = TypeAPIFunctions.Modules
local Functions = TypeAPIFunctions.Functions.ContentDelivery

function Assets.new(Base: any, character: Model)
	local self = setmetatable({}, Assets)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Data = self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.GetAssetsIndex, { character })
		or {
			Sounds = { Categories = {}, Individual = {}, Groups = {} },
			Animations = {},
			VFX = {},
		}

	print("Assets loaded", self.Data)

	return self
end

function Assets:GetData()
	return self.Data
end

function Assets:GetSoundCategory(categoryName: string)
	return self.Data.Sounds.Categories[categoryName]
end

function Assets:GetSound(soundName: string)
	return self.Data.Sounds.Individual[soundName]
end

function Assets:GetSoundGroup(groupName: string)
	return self.Data.Sounds.Groups[groupName]
end

function Assets:GetAnimationCategory(categoryName: string)
	return self.Data.Animations[categoryName]
end

function Assets:GetAnimation(animationKey: string)
	local parts = string.split(animationKey, "/")
	if #parts == 2 then
		for _, animation in ipairs(self:GetAnimationCategory(parts[1]) or {}) do
			if animation.Name == parts[2] then
				return animation
			end
		end
		return nil
	end

	for _, category in pairs(self.Data.Animations) do
		for _, animation in ipairs(category) do
			if animation.Name == animationKey then
				return animation
			end
		end
	end

	return nil
end

function Assets:GetRandomAnimationFromCategory(categoryName: string)
	local category = self:GetAnimationCategory(categoryName)
	if not category or #category == 0 then
		return nil
	end

	local randomIndex = math.random(1, #category)
	return category[randomIndex]
end

function Assets:GetVFX(folderName: string)
	return self.Data.VFX[folderName]
end

function Assets:Destroy()
	self.Data = {}
	self.CharacterAPI = nil
	self.Base = nil
end

return Assets
