local ServerScriptService = game:GetService("ServerScriptService")
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)

local Dialogue = {}
Dialogue.__index = Dialogue

local Modules = TypeAPIFunctions.Modules
local Functions = TypeAPIFunctions.Functions.ContentDelivery

function Dialogue.new(Base: any, character: Model)
	local self = setmetatable({}, Dialogue)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Data = self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.GetLinesIndex, { character }) or {}

	print("Dialogue data loaded for character:", character.Name, "Data:", self.Data)

	return self
end

function Dialogue:GetData()
	return self.Data
end

function Dialogue:GetLines(categoryName: string)
	local category = self.Data[categoryName]
	if categoryName == "Conversations" then
		return nil
	end

	return category
end

function Dialogue:GetConversation(categoryName: string, conversationName: string)
	local category = self.Data[categoryName]
	return categoryName == "Conversations" and category and category[conversationName] or nil
end

function Dialogue:Destroy()
	self.Data = {}
	self.CharacterAPI = nil
	self.Base = nil
end

return Dialogue
