local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

type Base = TypeBehavior.Base
type MoveToCallback = TypeBehavior.FunctionCallbacks["MoveTo"]

local module = {}

local BaseBehavior: Base?

function module.init(base: Base)
	print("I'VE BEEN ACQUIRED!")
	BaseBehavior = base

	BaseBehavior:SubscribeFunction(
		TypeBehavior.FunctionEnum.MoveTo,
		module.MoveTo :: MoveToCallback,
		TypeBehavior.SubscribeEnum.Replace
	)
end

function module.MoveTo(position: Vector3)
	warn("Stole position", position)
end

return module
