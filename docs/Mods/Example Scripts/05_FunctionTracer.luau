-- 05_FunctionTracer: a debugging tool. Prints every call to the behavior functions you list, with its arguments.
--
-- Shows that every behavior function can be hooked by name, and that a First hook sees a call before anything else
-- does. Leave out the chatty ones (GetStimulants, CanMove, ...) or the output drowns. Remove the mod when done.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local SubscribeEnum = TypeBehavior.SubscribeEnum

-- Names from FunctionEnum (any key of TypeCharacterFunctions.FunctionEnum)
local TRACED = {
	"Dodge",
	"BeginBlock",
	"EndBlock",
	"BreakBlock",
	"BeginStagger",
	"AttackCurrentTarget",
	"PickDesiredAttack",
	"ReactToIncomingAttack",
	"PurchaseStamina",
	"BreakStamina",
}

local function describe(...): string
	local parts = {}
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		parts[index] = if typeof(value) == "table" then "{table}" else tostring(value)
	end
	return table.concat(parts, ", ")
end

local module = {}

function module.init(base: Base)
	for _, name in TRACED do
		-- FunctionEnum maps names to themselves, and an unknown name is an error, so a typo shows up at once
		local functionName = (FunctionEnum :: any)[name]
		if not functionName then
			warn("[Tracer] not a behavior function:", name)
			continue
		end

		base:SubscribeFunction(functionName, function(...)
			print(string.format("[Tracer] %s.%s(%s)", base.Character.Name, name, describe(...)))
		end, SubscribeEnum.First)
	end
end

return module
