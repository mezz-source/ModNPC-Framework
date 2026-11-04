-- 03_TankMode: replace a decision (a Replace hook).
--
-- ReactToIncomingAttack is how a character decides to meet a hit it sees coming: dodge, block, last moment guard, or
-- nothing. Replacing it gives the character a different temperament. This one never reacts and always takes the hit.
--
-- Rules for Replace:
--   * Only one Replace per function. A second one is refused (SubscribeFunction returns nil and a reason).
--   * The original does not run, and your return value is what the caller gets, so return what the caller expects.
--     Here that is (Reaction, reason?), see FunctionCallbacks.ReactToIncomingAttack in TypeBehavior.
--   * There is no "call the original" from inside a Replace. If you only want to add to an action, use First / Last.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeDefense = require(ServerScriptService.ModNPCServer.Types.v1.TypeDefense)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local SubscribeEnum = TypeBehavior.SubscribeEnum

local module = {}

function module.init(base: Base)
	local function react(_stimulant: TypeStimulant.StimulantEvent): (TypeDefense.Reaction, string?)
		return TypeDefense.Reactions.None, "This one takes it on the chin"
	end

	local subscription, refusal = base:SubscribeFunction(FunctionEnum.ReactToIncomingAttack, react, SubscribeEnum.Replace)
	if not subscription then
		warn("[TankMode] could not take over ReactToIncomingAttack:", refusal)
	end
end

return module
