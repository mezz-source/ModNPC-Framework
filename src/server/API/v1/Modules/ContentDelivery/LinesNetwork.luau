local ServerScriptService = game:GetService("ServerScriptService")
local LinesNetwork = {}

local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)

type ConversationData = TypeCDN.ConversationData
type ConversationChoice = TypeCDN.ConversationChoice
type LineData = TypeCDN.LineData
type LinesIndex = TypeCDN.LinesIndex
type ModuleResponse = TypeModuleResponse.ModuleResponse

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
	if not child or not child:IsA("Folder") then
		return nil
	end

	return child
end

local function getLinesFolder(character: Model): Folder?
	local linesResponse = contentDeliveryNetwork.getLinesFolder(character)
	if not linesResponse.Success or not linesResponse.Data then
		return nil
	end

	return linesResponse.Data
end

local function normalizeDialog(dialog: Instance): LineData?
	if not dialog:IsA("Dialog") then
		return nil
	end

	return {
		Name = dialog.Name,
		Text = dialog.InitialPrompt,
	}
end

local function getCategory(linesFolder: Folder, categoryName: string): Folder?
	return getFolder(linesFolder, categoryName)
end

local function getCategoryLines(linesFolder: Folder, categoryName: string): { LineData }?
	local category = getCategory(linesFolder, categoryName)
	if not category then
		return nil
	end

	local lines = {}
	for _, child in ipairs(category:GetChildren()) do
		local line = normalizeDialog(child)
		if not line then
			return nil
		end
		table.insert(lines, line)
	end

	return lines
end

local function getConversation(linesFolder: Folder, categoryName: string, conversationName: string): ConversationData?
	local category = getCategory(linesFolder, categoryName)
	local conversation = category and category:FindFirstChild(conversationName)
	if not conversation or not conversation:IsA("Dialog") then
		return nil
	end

	local children = conversation:GetChildren()
	for _, child in ipairs(children) do
		if not child:IsA("DialogChoice") or not tonumber(child.Name) or tonumber(child.Name) % 1 ~= 0 then
			return nil
		end
	end

	table.sort(children, function(left: Instance, right: Instance)
		return tonumber(left.Name) < tonumber(right.Name)
	end)

	local choices = {}
	for _, child in ipairs(children) do
		table.insert(choices, { child.UserDialog, child.ResponseDialog })
	end

	return choices
end

local function getLinesIndex(linesFolder: Folder): LinesIndex
	local index: LinesIndex = {}

	for _, category in ipairs(linesFolder:GetChildren()) do
		if category:IsA("Folder") then
			local children = category:GetChildren()
			if category.Name == "Conversations" then
				local conversations = {}
				for _, conversation in ipairs(children) do
					if conversation:IsA("Dialog") then
						local data = getConversation(linesFolder, category.Name, conversation.Name)
						if data then
							conversations[conversation.Name] = data
						end
					end
				end
				index[category.Name] = conversations
			elseif #children > 0 and children[1]:IsA("Dialog") then
				local lines = getCategoryLines(linesFolder, category.Name)
				if lines then
					index[category.Name] = lines
				end
			end
		end
	end

	return index
end

local function validateConversation(conversation: Folder, path: string): (boolean, string)
	for _, child in ipairs(conversation:GetChildren()) do
		if not child:IsA("DialogChoice") then
			return false, path .. " contains a non-DialogChoice child"
		end

		if not tonumber(child.Name) or (tonumber(child.Name) or 1) % 1 ~= 0 then
			return false, path .. " contains a non-numeric DialogChoice"
		end
	end

	return true, ""
end

function LinesNetwork.init(network)
	contentDeliveryNetwork = network
end

function LinesNetwork.validateLinesFolder(linesFolder: Folder): (boolean, string)
	for _, category in ipairs(linesFolder:GetChildren()) do
		if not category:IsA("Folder") then
			return false, "Lines contains a non-folder category"
		end

		local children = category:GetChildren()
		if #children == 0 then
			return false, category.Name .. " is empty"
		end

		if category.Name == "Conversations" then
			for _, child in ipairs(children) do
				if not child:IsA("Dialog") then
					return false, category.Name .. " contains a non-Dialog conversation"
				end

				local valid, message = validateConversation(child, category.Name .. "/" .. child.Name)
				if not valid then
					return false, message
				end
			end
		elseif children[1]:IsA("Dialog") then
			for _, child in ipairs(children) do
				if not child:IsA("Dialog") then
					return false, category.Name .. " mixes Dialog and conversation content"
				end
			end
		else
			for _, child in ipairs(children) do
				local valid, message = validateConversation(child, category.Name .. "/" .. child.Name)
				if not valid then
					return false, message
				end
			end
		end
	end

	return true, ""
end

function LinesNetwork.getLines(character: Model, categoryName: string): ModuleResponse
	local linesFolder = getLinesFolder(character)
	local lines = linesFolder and getCategoryLines(linesFolder, categoryName)
	if not lines then
		return response(false, "Line category not found or malformed")
	end

	return response(true, "Line category retrieved", lines)
end

function LinesNetwork.getConversation(character: Model, categoryName: string, conversationName: string): ModuleResponse
	local linesFolder = getLinesFolder(character)
	local conversation = linesFolder and getConversation(linesFolder, categoryName, conversationName)
	if not conversation then
		return response(false, "Conversation not found or malformed")
	end

	return response(true, "Conversation retrieved", conversation)
end

function LinesNetwork.getLinesIndex(character: Model): ModuleResponse
	local linesFolder = getLinesFolder(character)
	if not linesFolder then
		return response(false, "Lines folder not found")
	end

	return response(true, "Lines index generated", getLinesIndex(linesFolder))
end

return LinesNetwork
