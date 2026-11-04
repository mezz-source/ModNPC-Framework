-- 01_Skeleton: the smallest useful mod script, with the bookkeeping every mod should have.
--
-- Put it (as a ModuleScript) anywhere under <Character>/ModNPC/Mods. It runs once per character, when that
-- character's Base is built.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local SubscribeEnum = TypeBehavior.SubscribeEnum
local Events = TypeCharacterEvents.Names

-- The module must return a PLAIN table with `init` set directly on it. It crosses a BindableFunction on its way to
-- the character, which copies tables and strips metatables, so an `init` inherited through setmetatable is lost.
local module = {}

function module.init(base: Base)
	print("[Skeleton] attached to", base.Character.Name)

	-- Per-character state lives in locals of init (or a table created here), not at module level: the module is
	-- required once per ModuleScript, so module level state is shared by every character that uses this script.
	local subscriptions: { { Unsubscribe: (any) -> boolean } } = {}

	-- A function hook. Last runs after the action, with the same arguments. Its return value is ignored.
	local jumpHook = base:SubscribeFunction(FunctionEnum.Jump, function()
		print("[Skeleton]", base.Character.Name, "jumped")
	end, SubscribeEnum.Last)
	if jumpHook then
		table.insert(subscriptions, jumpHook)
	end

	-- An event listener. Listeners are pcalled, so an error here is only a warning.
	table.insert(
		subscriptions,
		base.Events:Subscribe(Events.Combat.DamageTaken, function(payload)
			local attacker = if payload.Attacker then payload.Attacker.Name else "something"
			print(string.format("[Skeleton] took %.1f damage from %s", payload.Amount, attacker))
		end)
	)

	-- Let go of everything when the character dies. (Function and event subscriptions are not removed for you.)
	base.Events:Subscribe(Events.Humanoid.Died, function()
		for _, subscription in subscriptions do
			subscription:Unsubscribe()
		end
		table.clear(subscriptions)
	end, true) -- once = true: this listener removes itself after firing
end

return module
