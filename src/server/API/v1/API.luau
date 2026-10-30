local API = {}

local ServerScriptService = game:GetService("ServerScriptService")
local Base = require(ServerScriptService.ModNPCServer.Behavior.v1.Base)
local TypeModuleResponse = require(ServerScriptService.ModNPCServer.Types.v1.TypeModuleResponse)
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)

-- local ModEvents = ServerScriptService:WaitForChild("ModEvents")
local ModFunctions = ServerScriptService:WaitForChild("ModFunctions")
local RequestBind: BindableFunction = ModFunctions:WaitForChild("Request")

type APIRequest = TypeRequests.APIRequest
type APIResponse = TypeRequests.APIResponse

local ResponseEnums = TypeRequests.Enums.StatusCode

local isReady = false
local modules: { [string]: {} } = {}

local function yieldUntilReady()
	repeat
		task.wait()
	until isReady
end

local function getModule(moduleName: string): any?
	if not modules[moduleName] then
		return nil
	end
	return modules[moduleName]
end

local function validateRequestFormat(request: APIRequest): { ["ok"]: boolean, ["error"]: string? }
	if typeof(request) ~= "table" then
		return { ok = false, error = "Request is not a table" }
	end

	if not request.ModuleName then
		return { ok = false, error = "ModuleName is missing from request" }
	end

	if not request.Function then
		return { ok = false, error = "Function is missing from request" }
	end

	if typeof(request.ModuleName) ~= "string" then
		return { ok = false, error = "Module name is not a string" }
	end

	if typeof(request.Function) ~= "string" then
		return { ok = false, error = "Function is not a string" }
	end

	if request.Arguments and typeof(request.Arguments) ~= "table" then
		return { ok = false, error = "Arguments is not a table" }
	end

	return { ok = true, error = nil }
end

local function successResponse(message: string?, statusCode: number?, data: any?): APIResponse
	return {
		Success = true,
		Message = message,
		StatusCode = statusCode,
		Data = data,
	}
end

local function errorResponse(message: string?, statusCode: number?, data: any?): APIResponse
	return {
		Success = false,
		Message = message,
		StatusCode = statusCode,
		Data = data,
	}
end

local function handleRequest(request: APIRequest): APIResponse
	local validateResponse = validateRequestFormat(request)
	if not validateResponse.ok then
		return errorResponse(
			"Malformed request: " .. validateResponse.error,
			ResponseEnums.MalformedRequest,
			{ Request = request }
		)
	end

	local module = getModule(request.ModuleName)
	if not module then
		return errorResponse("Module not found", ResponseEnums.NotFound, { Request = request })
	end

	if not module[request.Function] or typeof(module[request.Function]) ~= "function" then
		warn(request.Function, request)
		return errorResponse(
			"Function not found in module",
			ResponseEnums.NotFound,
			{ Request = request, Module = module }
		)
	end

	-- passing the function straight to pcall avoids a closure allocation on every request
	local success, result = pcall(module[request.Function], unpack(request.Arguments or {}))

	if not success then
		return errorResponse(
			"Error occurred while executing function: " .. tostring(result),
			ResponseEnums.InternalServerError
		)
	end

	if typeof(result) ~= "table" or result.PassResponse == nil or result.Success == nil then
		return errorResponse(
			"Module function must return a ModuleResponse",
			ResponseEnums.InternalServerError,
			{ Result = result }
		)
	end

	-- this allows for modules to report issues (like conflicts/missing stuff) without it being lost in the api
	local response = result :: TypeModuleResponse.ModuleResponse
	if response.PassResponse then
		if response.Success then
			return successResponse(response.Message, response.StatusCode, response.Data)
		else
			return errorResponse(response.Message, response.StatusCode, response.Data)
		end
	else
		return successResponse("Request processed successfully", ResponseEnums.Success, nil)
	end
end

local function requestRecieved(request: APIRequest): APIResponse?
	-- the caller is blocked on the bindable until we return, so defer the work and hand back nothing
	if typeof(request) == "table" and request.NoResponse == true then
		task.defer(function()
			if not isReady then
				yieldUntilReady()
			end
			local response = handleRequest(request)
			if not response.Success then
				warn("API request failed (no response requested):", response.Message)
			end
		end)
		return nil
	end

	if not isReady then
		yieldUntilReady()
	end
	local response = handleRequest(request)
	return response
end

function API.startCharacter(character: Model)
	print("Starting character: " .. character.Name)
	return Base.new(character)
end

function API._internalRequest(request: APIRequest): APIResponse?
	return requestRecieved(request)
end

function API.init(coreModules: {})
	RequestBind.OnInvoke = function(request: APIRequest): APIResponse?
		return requestRecieved(request)
	end

	print("V1 API initialized")
	modules = coreModules
	isReady = true
end

return API
