-- 09_HandleReads: read other characters through their handles, and ask the API for what a handle can't do.
--
--   context.Handle   every target the search or Friends hands out comes with its handle, so reading it costs no request
--   Handle reads     team, health and standing, without knowing what kind of character is behind it
--   Handle asks      IsExhausted and IsStaggered call into the target's own engine, so keep them conditional
--   CharacterAPI     a handle only reads: HoldUntargetable asks the API to take this character off the target list
--
-- GetHandle reaches any character, for when a context isn't around.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeTargetting = require(ServerScriptService.ModNPCServer.Types.v1.TypeTargetting)

type Base = TypeBehavior.Base

local Events = TypeCharacterEvents.Names

local LOW_HEALTH = 0.3
local VANISH_TIME = 3
-- Prefixed so it can't collide with a hold of another mod: holds are kept by reason
local VANISH_REASON = "HandleReads_Vanish"
local FLASH_COLOR = Color3.fromRGB(255, 200, 60)

local module = {}

function module.init(base: Base)
	base.Events:Subscribe(Events.Targetting.NewFocusTarget, function(context: TypeTargetting.TargettingContext)
		local handle = context.Handle
		local us = base.CharacterAPI:GetHandle()
		if not handle or not us then
			return
		end

		-- Nothing here needs guarding: a read that can't answer gives its default, and nil for a number it doesn't know
		local health = handle:GetHealthInfo()
		base.Character:SetAttribute(
			"LastTarget",
			string.format(
				"%s team=%s health=%.2f hostile=%s",
				handle:GetModel().Name,
				handle:GetTeam(),
				if health then health.Fraction else 1,
				tostring(us:IsHostile(handle))
			)
		)

		-- An ask: only a character with an engine can say yes, and anything else simply says no
		if handle:IsExhausted() then
			base.CharacterAPI:FlashHighlight({ FillColor = FLASH_COLOR, FadeTime = 0.6 })
		end
	end)

	-- Hurt badly: ask to be left alone for a moment. Hits still land, this only keeps others from picking us as a target.
	local vanishing = false
	base.Events:Subscribe(Events.Combat.DamageTaken, function()
		local health = base.CharacterAPI:GetHealthInfo()
		if vanishing or not base:IsAlive() or not health or health.Fraction > LOW_HEALTH then
			return
		end

		vanishing = true
		base.CharacterAPI:HoldUntargetable(VANISH_REASON)
		task.delay(VANISH_TIME, function()
			base.CharacterAPI:ReleaseUntargetable(VANISH_REASON)
			vanishing = false
		end)
	end)
end

return module
