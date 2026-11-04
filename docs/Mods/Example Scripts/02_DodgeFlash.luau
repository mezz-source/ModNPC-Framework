-- 02_DodgeFlash: run something after a behavior function (a Last hook), and use the character API to show it.
--
-- A Last hook gets the arguments of the call but NOT its result, and it runs even when the call failed (the dodge was
-- refused, or the character was too tired). To know whether the dodge really began, ask the character's state.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeState = require(ServerScriptService.ModNPCServer.Types.v1.TypeState)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local SubscribeEnum = TypeBehavior.SubscribeEnum

local DODGE_COLOR = Color3.fromRGB(80, 170, 255)

local module = {}

function module.init(base: Base)
	base:SubscribeFunction(FunctionEnum.Dodge, function(_direction)
		if not base.State:Is(TypeState.Keys.DodgeState, TypeState.DodgeStateEnum.Active) then
			return -- the dodge was refused
		end

		-- Everything that touches the world goes through CharacterAPI. This asks the Highlights API module to flash
		-- the character: it holds its color for 0.1s, then fades out over 0.4s and destroys itself.
		base.CharacterAPI:FlashHighlight({
			FillColor = DODGE_COLOR,
			OutlineColor = DODGE_COLOR,
			Hold = 0.1,
			FadeTime = 0.4,
		})
	end, SubscribeEnum.Last)
end

return module
