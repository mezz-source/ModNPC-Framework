local Core = require(script.API.v1.Core)
local API = require(script.API.v1.API)
local TypeRequests = require(script.Types.v1.TypeRequests)

local Request =
	game:GetService("ServerScriptService"):WaitForChild("ModFunctions"):WaitForChild("Request") :: BindableFunction

type Response = TypeRequests.APIResponse

--bootstrap
Core.init()

task.wait(1)

-- lets test this goober
local Character1 = workspace:WaitForChild("modnpc1")
API.startCharacter(Character1)

-- local Character2 = workspace:WaitForChild("modnpc2")
-- API.startCharacter(Character2)

-- while task.wait(1) do
-- 	local response = Request:Invoke({
-- 		ModuleName = "Damage",
-- 		Function = "takeDamage",
-- 		Arguments = { Character2, Character1, 10 },
-- 	})

-- 	if not response.Success then
-- 		warn("API request failed:", response)
-- 	else
-- 		print("API request succeeded:", response)
-- 		if response.Data.DidHit then
-- 			print("Character1 took damage:", response.Data.Amount)
-- 		else
-- 			print("Character1 did not take damage because it was:", response.Data.RecieveType)
-- 		end
-- 	end
-- end
