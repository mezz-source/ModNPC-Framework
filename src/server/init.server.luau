local Core = require(script.API.v1.Core)
local API = require(script.API.v1.API)
local TypeRequests = require(script.Types.v1.TypeRequests)

-- local Request =
-- 	game:GetService("ServerScriptService"):WaitForChild("ModFunctions"):WaitForChild("Request") :: BindableFunction

type Response = TypeRequests.APIResponse

--bootstrap
Core.init()

-- register manually
for _, Character1 in ipairs(workspace:GetChildren()) do
	if string.find(Character1.Name, "modnpc") then
		API.startCharacter(Character1)
	end
end

