local ServerScriptService = game:GetService("ServerScriptService")
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local HighlightClass = require(script.Highlight)
local Highlights = {}

type HighlightObject = TypeHighlights.Highlight
type HighlightOptions = TypeHighlights.HighlightOptions
type FlashHighlightOptions = TypeHighlights.FlashHighlightOptions

local FOLDER_NAME = TypeHighlights.FolderName

-- Short lived highlights, when their options leave these out
local FLASH_DEFAULT_COLOR = Color3.new(1, 1, 1)
local FLASH_DEFAULT_FILL_TRANSPARENCY = 0.5
local FLASH_DEFAULT_OUTLINE_TRANSPARENCY = 0
local FLASH_DEFAULT_HOLD = 0
local FLASH_DEFAULT_FADE_TIME = 0.4
local FLASH_FADE_STYLE = Enum.EasingStyle.Quad
local FLASH_FADE_DIRECTION = Enum.EasingDirection.Out
-- Short lived highlights are not named by the caller; this makes their instance names unique
local FLASH_NAME_PREFIX = "_Flash"
local flashCount = 0

-- Named highlights by character, then by name. Weak so a character that is gone takes its highlights with it.
-- Short lived highlights are never in here.
local highlightsByCharacter: { [Model]: { [string]: HighlightObject } } = setmetatable({}, { __mode = "k" }) :: any

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

local function validateColors(options: any, keys: { string }): string?
	for _, key in keys do
		if options[key] ~= nil and typeof(options[key]) ~= "Color3" then
			return key .. " must be a Color3"
		end
	end

	return nil
end

local function validateTransparencies(options: any): string?
	for _, key in { "FillTransparency", "OutlineTransparency" } do
		if options[key] ~= nil and not HighlightClass.isValidTransparency(options[key]) then
			return key .. " must be a number from 0 to 1"
		end
	end

	return nil
end

local function validateOptions(options: any): string?
	if options == nil then
		return nil
	end

	if typeof(options) ~= "table" then
		return "options must be a table"
	end

	if options.Enabled ~= nil and typeof(options.Enabled) ~= "boolean" then
		return "Enabled must be a boolean"
	end

	if options.DepthMode ~= nil then
		return "DepthMode cannot be set; highlights always occlude"
	end

	return validateColors(options, { "FillColor", "OutlineColor" }) or validateTransparencies(options)
end

local function validateFlashOptions(options: any): string?
	if options == nil then
		return nil
	end

	if typeof(options) ~= "table" then
		return "options must be a table"
	end

	for _, key in { "Hold", "FadeTime" } do
		if options[key] ~= nil and not HighlightClass.isValidDuration(options[key]) then
			return key .. " must be a number of seconds, 0 or more"
		end
	end

	return validateColors(options, { "FillColor", "OutlineColor" }) or validateTransparencies(options)
end

local function validateCharacter(character: any): TypeModuleResponse.ModuleResponse?
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end

	return nil
end

-- The character's highlight folder, made the first time a highlight is. Returns the folder, or nil and why not.
local function ensureFolder(character: Model): (Folder?, string?)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end

		return nil, "Character already has a " .. existing.ClassName .. " named " .. FOLDER_NAME
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character
	return folder
end

-- A new Highlight instance on the character, inside its highlight folder. Returns the instance, or the failure response.
local function makeInstance(character: Model, instanceName: string): (Highlight?, TypeModuleResponse.ModuleResponse?)
	local folder, folderProblem = ensureFolder(character)
	if not folder then
		return nil, response(false, TypeRequests.Enums.StatusCode.Conflict, folderProblem)
	end

	local instance = Instance.new("Highlight")
	instance.Name = instanceName
	instance.Adornee = character
	instance.DepthMode = Enum.HighlightDepthMode.Occluded
	instance.Parent = folder
	return instance, nil
end

local function getHighlight(character: Model, highlightName: string): HighlightObject?
	local highlights = highlightsByCharacter[character]
	return highlights and highlights[highlightName]
end

-- Makes a highlight on the character, inside its ModHighlights folder (added to the character if it has none).
-- Data is the highlight: a table of methods that drives it directly, so nothing needs to be requested to change it.
-- A highlight destroys itself when its instance is removed; RemoveHighlight removes one by name.
-- A name that is already used by one of the character's highlights is a conflict, never replaced.
function Highlights.createHighlight(
	character: Model,
	highlightName: string,
	options: HighlightOptions?
): TypeModuleResponse.ModuleResponse
	local badCharacter = validateCharacter(character)
	if badCharacter then
		return badCharacter
	end

	if typeof(highlightName) ~= "string" or highlightName == "" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Highlight name must be a non-empty string")
	end

	if string.sub(highlightName, 1, #FLASH_NAME_PREFIX) == FLASH_NAME_PREFIX then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Highlight names starting with " .. FLASH_NAME_PREFIX .. " are reserved for short lived highlights"
		)
	end

	local invalidReason = validateOptions(options)
	if invalidReason then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Invalid highlight options: " .. invalidReason
		)
	end

	if getHighlight(character, highlightName) then
		return response(
			false,
			TypeRequests.Enums.StatusCode.Conflict,
			character.Name .. " already has a highlight named " .. highlightName
		)
	end

	local instance, failure = makeInstance(character, highlightName)
	if not instance then
		return failure :: TypeModuleResponse.ModuleResponse
	end

	local highlights = highlightsByCharacter[character]
	if not highlights then
		highlights = {}
		highlightsByCharacter[character] = highlights
	end

	local highlight: HighlightObject
	highlight = HighlightClass.new(instance, highlightName, options or {}, function()
		-- the name may have been taken by a newer highlight since this one was dropped from the registry
		if highlights[highlightName] == highlight then
			highlights[highlightName] = nil
		end

		if next(highlights) == nil and highlightsByCharacter[character] == highlights then
			highlightsByCharacter[character] = nil
		end
	end)
	highlights[highlightName] = highlight

	return response(true, TypeRequests.Enums.StatusCode.Success, "Highlight created", highlight)
end

-- A short lived highlight on the character: it shows its colors at once, holds them for Hold seconds, fades both
-- transparencies to 1 over FadeTime seconds, then destroys itself. It has no name to look it up by and never conflicts
-- with anything. Data is the highlight, for a caller that wants to change or end it early (most don't need it).
function Highlights.flashHighlight(character: Model, options: FlashHighlightOptions?): TypeModuleResponse.ModuleResponse
	local badCharacter = validateCharacter(character)
	if badCharacter then
		return badCharacter
	end

	local invalidReason = validateFlashOptions(options)
	if invalidReason then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Invalid flash highlight options: " .. invalidReason
		)
	end

	local flashOptions: FlashHighlightOptions = options or {}
	flashCount += 1
	local instanceName = FLASH_NAME_PREFIX .. flashCount

	local instance, failure = makeInstance(character, instanceName)
	if not instance then
		return failure :: TypeModuleResponse.ModuleResponse
	end

	local fillColor = flashOptions.FillColor or FLASH_DEFAULT_COLOR
	local highlight = HighlightClass.new(instance, instanceName, {
		FillColor = fillColor,
		OutlineColor = flashOptions.OutlineColor or fillColor,
		FillTransparency = flashOptions.FillTransparency or FLASH_DEFAULT_FILL_TRANSPARENCY,
		OutlineTransparency = flashOptions.OutlineTransparency or FLASH_DEFAULT_OUTLINE_TRANSPARENCY,
	}, function() end)

	local hold = flashOptions.Hold or FLASH_DEFAULT_HOLD
	local fadeTime = flashOptions.FadeTime or FLASH_DEFAULT_FADE_TIME
	task.delay(hold, function()
		if highlight:IsDestroyed() then
			return
		end

		local fade = TweenInfo.new(fadeTime, FLASH_FADE_STYLE, FLASH_FADE_DIRECTION)
		highlight:TweenFillTransparency(1, fade)
		highlight:TweenOutlineTransparency(1, fade)
		task.delay(fadeTime, function()
			highlight:Destroy()
		end)
	end)

	return response(true, TypeRequests.Enums.StatusCode.Success, "Flash highlight created", highlight)
end

-- Data is the character's highlight of that name
function Highlights.getHighlight(character: Model, highlightName: string): TypeModuleResponse.ModuleResponse
	local highlight = getHighlight(character, highlightName)
	if not highlight then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			tostring(character) .. " has no highlight named " .. tostring(highlightName)
		)
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Highlight found", highlight)
end

function Highlights.removeHighlight(character: Model, highlightName: string): TypeModuleResponse.ModuleResponse
	local highlight = getHighlight(character, highlightName)
	if not highlight then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			tostring(character) .. " has no highlight named " .. tostring(highlightName)
		)
	end

	highlight:Destroy()
	return response(true, TypeRequests.Enums.StatusCode.Success, "Highlight removed")
end

function Highlights.init(_)
	print("V1 Highlights initialized")
end

return Highlights
