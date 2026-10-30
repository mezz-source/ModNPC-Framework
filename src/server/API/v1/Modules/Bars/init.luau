local ServerScriptService = game:GetService("ServerScriptService")
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.CharacterUtility)
local BarClass = require(script.Bar)
local Bars = {}

type Bar = TypeBars.Bar
type BarOptions = TypeBars.BarOptions

local GUI_NAME = TypeBars.GuiName
-- the frame in the gui that lays its bars out, and the hidden bar inside it that every bar is cloned from
local CONTAINER_NAME = "BarRef"
local TEMPLATE_NAME = "BAR_REF"
-- Raises the gui off the head's center when the asset leaves its own offset at zero
local DEFAULT_HEAD_OFFSET = Vector3.new(0, 2, 0)

-- Bars by character, then by name. Weak so a character that is gone takes its bars with it.
local barsByCharacter: { [Model]: { [string]: Bar } } = setmetatable({}, { __mode = "k" }) :: any

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

local function isNumberOrNil(value: any): boolean
	return value == nil or (typeof(value) == "number" and value == value)
end

local function validateOptions(options: any): string?
	if options == nil then
		return nil
	end

	if typeof(options) ~= "table" then
		return "options must be a table"
	end

	if not isNumberOrNil(options.Fill) then
		return "Fill must be a number"
	end

	if not isNumberOrNil(options.SecondaryFill) then
		return "SecondaryFill must be a number"
	end

	if options.Size ~= nil and not BarClass.isValidSize(options.Size) then
		return "Size must be a number above 0 and at most 1"
	end

	if options.LayoutOrder ~= nil and not BarClass.isValidLayoutOrder(options.LayoutOrder) then
		return "LayoutOrder must be an integer"
	end

	for _, colorKey in { "FillColor", "SecondaryFillColor", "ChangeFillColor" } do
		if options[colorKey] ~= nil and typeof(options[colorKey]) ~= "Color3" then
			return colorKey .. " must be a Color3"
		end
	end

	return nil
end

-- The billboard sits on the head, or on the root part when the character has none
local function getAdornee(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return CharacterUtility._getRootPart(character)
end

-- The character's BaseBars gui, cloned out of ModAssets the first time a bar is made. Returns the gui, or nil and why not.
local function ensureGui(character: Model): (BillboardGui?, string?)
	local existing = character:FindFirstChild(GUI_NAME)
	if existing then
		if existing:IsA("BillboardGui") then
			return existing
		end

		return nil, "Character already has a " .. existing.ClassName .. " named " .. GUI_NAME
	end

	local adornee = getAdornee(character)
	if not adornee then
		return nil, "Character has no head or root part to attach bars to"
	end

	local modAssets = ServerScriptService:FindFirstChild("ModAssets")
	local template = modAssets and modAssets:FindFirstChild(GUI_NAME)
	if not template or not template:IsA("BillboardGui") then
		return nil, "ServerScriptService.ModAssets." .. GUI_NAME .. " is missing or not a BillboardGui"
	end

	local gui = template:Clone()
	gui.Name = GUI_NAME
	gui.Adornee = adornee
	if gui.StudsOffsetWorldSpace == Vector3.zero and gui.StudsOffset == Vector3.zero then
		gui.StudsOffsetWorldSpace = DEFAULT_HEAD_OFFSET
	end
	gui.Parent = character

	return gui
end

local function getBar(character: Model, barName: string): Bar?
	local bars = barsByCharacter[character]
	return bars and bars[barName]
end

-- Makes a bar above the character's head, inside its BaseBars gui (which is added to the character if it has none).
-- Data is the bar: a table of methods that drives the bar directly, so nothing needs to be requested to change it.
-- A bar destroys itself when its instance is removed; RemoveBar removes one by name.
-- A name that is already used by one of the character's bars is a conflict, never replaced.
function Bars.createBar(character: Model, barName: string, options: BarOptions?): TypeModuleResponse.ModuleResponse
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end

	if typeof(barName) ~= "string" or barName == "" then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Bar name must be a non-empty string")
	end

	local invalidReason = validateOptions(options)
	if invalidReason then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Invalid bar options: " .. invalidReason)
	end

	if getBar(character, barName) then
		return response(
			false,
			TypeRequests.Enums.StatusCode.Conflict,
			character.Name .. " already has a bar named " .. barName
		)
	end

	local gui, guiProblem = ensureGui(character)
	if not gui then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, guiProblem)
	end

	local container = gui:FindFirstChild(CONTAINER_NAME)
	local template = container and container:FindFirstChild(TEMPLATE_NAME)
	if not container or not template then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			GUI_NAME .. " has no " .. CONTAINER_NAME .. "." .. TEMPLATE_NAME .. " to make bars from"
		)
	end

	-- a name taken by anything else in the container (the template, its layout) would be confused with the bar
	if container:FindFirstChild(barName) then
		return response(
			false,
			TypeRequests.Enums.StatusCode.Conflict,
			barName .. " is already used in " .. GUI_NAME .. " and cannot be a bar name"
		)
	end

	local badTemplateReason = BarClass.validateFrame(template)
	if badTemplateReason then
		return response(false, TypeRequests.Enums.StatusCode.InternalServerError, badTemplateReason)
	end

	local frame = template:Clone() :: Frame
	frame.Name = barName
	frame.Visible = true
	frame.Parent = container

	local bars = barsByCharacter[character]
	if not bars then
		bars = {}
		barsByCharacter[character] = bars
	end

	local bar: Bar
	bar = BarClass.new(frame, barName, options or {}, function()
		-- the name may have been taken by a newer bar since this one was dropped from the registry
		if bars[barName] == bar then
			bars[barName] = nil
		end

		if next(bars) == nil and barsByCharacter[character] == bars then
			barsByCharacter[character] = nil
		end
	end)
	bars[barName] = bar

	return response(true, TypeRequests.Enums.StatusCode.Success, "Bar created", bar)
end

-- Data is the character's bar of that name
function Bars.getBar(character: Model, barName: string): TypeModuleResponse.ModuleResponse
	local bar = getBar(character, barName)
	if not bar then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			tostring(character) .. " has no bar named " .. tostring(barName)
		)
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Bar found", bar)
end

function Bars.removeBar(character: Model, barName: string): TypeModuleResponse.ModuleResponse
	local bar = getBar(character, barName)
	if not bar then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			tostring(character) .. " has no bar named " .. tostring(barName)
		)
	end

	bar:Destroy()
	return response(true, TypeRequests.Enums.StatusCode.Success, "Bar removed")
end

function Bars.init(_)
	print("V1 Bars initialized")
end

return Bars
