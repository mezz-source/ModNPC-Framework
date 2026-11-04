-- 04_Enrage: react to an event, and use several core systems from one mod.
--
--   Events         DamageTaken tells us a hit landed
--   CharacterAPI   GetHealthInfo reads health, CreateHighlight / FlashHighlight show the change
--   Functions      RestoreStamina and StartSprinting act through the hookable behavior functions
--   Attributes     the threshold can be tuned per character in Studio without touching the config schema
--
-- Reading health goes through CharacterAPI. Do not use base.Humanoid for that: after startup it is the Humanoid
-- behavior module, not the Roblox Humanoid instance.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum
local Events = TypeCharacterEvents.Names

local DEFAULT_THRESHOLD = 0.3
local ENRAGE_COLOR = Color3.fromRGB(255, 40, 40)

local module = {}

function module.init(base: Base)
	local enraged = false

	local damageListener
	damageListener = base.Events:Subscribe(Events.Combat.DamageTaken, function()
		if enraged or not base:IsAlive() then
			return
		end

		local health = base.CharacterAPI:GetHealthInfo()
		local threshold = base.Character:GetAttribute("EnrageThreshold") or DEFAULT_THRESHOLD
		if not health or health.Fraction > threshold then
			return
		end

		enraged = true
		damageListener.Unsubscribe() -- one shot: nothing left to listen for

		-- A persistent glow that lives as long as the character, and a flash to announce it
		local glow = base.CharacterAPI:CreateHighlight("Enraged", {
			FillColor = ENRAGE_COLOR,
			OutlineColor = ENRAGE_COLOR,
			FillTransparency = 0.8,
		})
		if glow then
			glow:StartFlash(ENRAGE_COLOR, nil, 1)
		end
		base.CharacterAPI:FlashHighlight({ FillColor = Color3.new(1, 1, 1), FadeTime = 0.6 })

		-- A second wind, through the same functions the game uses so other mods' hooks see it too
		base.Functions:CallFunction(FunctionEnum.RestoreStamina, 1000, "Enrage")
		base.Functions:CallFunction(FunctionEnum.StartSprinting)
	end)
end

return module
