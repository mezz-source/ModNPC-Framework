local ServerScriptService = game:GetService("ServerScriptService")
local TypeRequests = require(ServerScriptService.ModNPCServer.Types.v1.TypeRequests)
local Router = {}
Router.__index = Router

local RequestBind: BindableFunction = ServerScriptService:WaitForChild("ModFunctions"):WaitForChild("Request")

function Router.new()
	local self = setmetatable({}, Router)
	return self
end

function Router:Request(apiRequest: TypeRequests.APIRequest)
	local response = RequestBind:Invoke(apiRequest)
	return response
end

return Router
