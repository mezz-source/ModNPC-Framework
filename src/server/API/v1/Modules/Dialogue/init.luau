-- Dialogue text: Markup parses a line, Layout places its glyphs, Timeline times them, Board puts them on a DialogueUI
-- and Presenter types them out with Effects. Frame keeps a character's DialogueUI, with a queue of lines in front of it,
-- and is what the API hands out (createFrame, getFrame, removeFrame).
local ServerScriptService = game:GetService("ServerScriptService")
local TypeDialogueFrame = require(ServerScriptService.ModNPCServer.Types.v1.TypeDialogueFrame)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local CharacterUtility = require(script.Parent.CharacterUtility)

local Dialogue = {}

Dialogue.Markup = require(script.Markup)
Dialogue.Layout = require(script.Layout)
Dialogue.Timeline = require(script.Timeline)
Dialogue.Effects = require(script.Effects)
Dialogue.Board = require(script.Board)
Dialogue.Presenter = require(script.Presenter)
Dialogue.Frame = require(script.Frame)

type Frame = TypeDialogueFrame.Frame
type FrameOptions = TypeDialogueFrame.FrameOptions

local GUI_NAME = TypeDialogueFrame.GuiName
-- The target's function that answers banter (TypeCharacterFunctions.FunctionEnum.BanterRespond)
local BANTER_RESPOND_FUNCTION = "BanterRespond"

-- Frames by character. Weak so a character that is gone takes its frame with it.
local framesByCharacter: { [Model]: Frame } = setmetatable({}, { __mode = "k" }) :: any

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

local function validateOptions(options: any): string?
	if options == nil then
		return nil
	end
	if typeof(options) ~= "table" then
		return "options must be a table"
	end
	if options.Color ~= nil and typeof(options.Color) ~= "Color3" then
		return "Color must be a Color3"
	end
	if options.TalkSound ~= nil and not Dialogue.Frame.isValidTalkSound(options.TalkSound) then
		return "TalkSound must be sound data with a SoundId"
	end
	if options.TalkSpeed ~= nil and not Dialogue.Frame.isValidTalkSpeed(options.TalkSpeed) then
		return "TalkSpeed must be a number above 0"
	end
	if options.OnEvent ~= nil and typeof(options.OnEvent) ~= "function" then
		return "OnEvent must be a function"
	end

	return nil
end

-- The gui sits on the head, or on the root part when the character has none
local function getAdornee(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return CharacterUtility._getRootPart(character)
end

-- Makes the character's dialogue frame out of ModAssets.DialogueUI. Data is the frame: a table of closures that drives it
-- directly (Queue, Cancel...), so nothing needs to be requested to use it. A character has one frame, for as long as it
-- lives; it ends itself when its gui is removed (the gui is kept in the head, or in the character when it has none, so
-- losing the head ends it too), and removeFrame removes it. A second frame is a conflict, never a replacement.
function Dialogue.createFrame(character: Model, options: FrameOptions?): TypeModuleResponse.ModuleResponse
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Character must be a Model")
	end

	local invalidReason = validateOptions(options)
	if invalidReason then
		return response(
			false,
			TypeRequests.Enums.StatusCode.MalformedRequest,
			"Invalid dialogue frame options: " .. invalidReason
		)
	end

	local adornee = getAdornee(character)
	if not adornee then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			"Character has no head or root part to attach dialogue to"
		)
	end

	-- The gui is kept in the head when there is one (it is what the gui sits on), and in the character itself otherwise
	local host: Instance = if adornee.Name == "Head" then adornee else character

	-- (an old gui that is left over without a frame counts too: it would be confused with the new one)
	if framesByCharacter[character] or host:FindFirstChild(GUI_NAME) or character:FindFirstChild(GUI_NAME) then
		return response(
			false,
			TypeRequests.Enums.StatusCode.Conflict,
			character.Name .. " already has a " .. GUI_NAME
		)
	end

	local modAssets = ServerScriptService:FindFirstChild("ModAssets")
	local template = modAssets and modAssets:FindFirstChild(GUI_NAME)
	if not template or not template:IsA("BillboardGui") then
		return response(
			false,
			TypeRequests.Enums.StatusCode.NotFound,
			"ServerScriptService.ModAssets." .. GUI_NAME .. " is missing or not a BillboardGui"
		)
	end

	local gui = template:Clone()
	gui.Name = GUI_NAME
	gui.Adornee = adornee
	gui.Parent = host

	local frame: Frame
	local built, result = pcall(function()
		return Dialogue.Frame.new(gui, adornee, options or {}, function()
			if framesByCharacter[character] == frame then
				framesByCharacter[character] = nil
			end
		end)
	end)
	if not built then
		gui:Destroy()
		return response(
			false,
			TypeRequests.Enums.StatusCode.InternalServerError,
			"Could not build the dialogue frame: " .. tostring(result)
		)
	end

	frame = result
	framesByCharacter[character] = frame

	return response(true, TypeRequests.Enums.StatusCode.Success, "Dialogue frame created", frame)
end

-- Data is the character's frame
function Dialogue.getFrame(character: Model): TypeModuleResponse.ModuleResponse
	local frame = framesByCharacter[character]
	if not frame then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, tostring(character) .. " has no dialogue frame")
	end

	return response(true, TypeRequests.Enums.StatusCode.Success, "Dialogue frame found", frame)
end

function Dialogue.removeFrame(character: Model): TypeModuleResponse.ModuleResponse
	local frame = framesByCharacter[character]
	if not frame then
		return response(false, TypeRequests.Enums.StatusCode.NotFound, tostring(character) .. " has no dialogue frame")
	end

	frame:Destroy()
	return response(true, TypeRequests.Enums.StatusCode.Success, "Dialogue frame removed")
end

-- Asks the target to answer the starter's banter: calls the target's BanterRespond function (Dialogue:BanterRespond) through
-- its bind, with the starter. Data is whether it answers. A target that can't (not a started ModNPC, gone) or won't
-- (cooling down, busy with something more important) is a successful request with Data = false, never an error: banter is
-- optional by nature. Only a malformed request fails.
function Dialogue.requestBanterResponse(starter: Model, target: Model): TypeModuleResponse.ModuleResponse
	if typeof(starter) ~= "Instance" or not starter:IsA("Model") then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Starter must be a Model")
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target == starter then
		return response(false, TypeRequests.Enums.StatusCode.MalformedRequest, "Target must be another Model")
	end

	if not target.Parent then
		return response(true, TypeRequests.Enums.StatusCode.Success, "Target is gone", false)
	end

	-- sendFunction itself refuses a character with no bind (not a ModNPC) or one that was never started
	local answer = CharacterUtility.sendFunction(target, BANTER_RESPOND_FUNCTION, { starter })
	local answered = answer.Success and answer.Data == true
	return response(
		true,
		TypeRequests.Enums.StatusCode.Success,
		if answered then "Target answered" else "Target did not answer",
		answered
	)
end

function Dialogue.init(_api: any) end

return Dialogue
