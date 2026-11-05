local ServerScriptService = game:GetService("ServerScriptService")
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)
local TypeParry = require(ServerScriptService.ModNPCServer.Types.v1.TypeParry)
local TypeStamina = require(ServerScriptService.ModNPCServer.Types.v1.TypeStamina)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Animations = TypeParry.Animations
local Sounds = TypeParry.Sounds

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local FADE_TIME = 0.1

local HIGHLIGHT_NAME = "Parry"
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 140, 0)
-- Seconds the highlight takes from fully filled to just its outline as the parry starts. Under the 0.3s of the ParryEnd
-- marker, so the outline is what fades.
local START_FLASH_TIME = 0.25
-- Seconds the outline takes to fade once the parry is over
local END_FADE_TIME = 0.2
-- Seconds the highlight takes from fully filled to nothing when a hit is parried
local HIT_FLASH_TIME = 0.35

-- A character trying to parry, which needs a weapon: it holds the animations, the sounds and the price (the Parry cost). One
-- that can't pay doesn't parry, and what it paid is spent unless a hit is parried.
--   Start      pays, plays Parry and takes the parry state (see Damage:BeginParry). Hits that come in are parried, the
--              character is held still and can't block or act.
--   ParryEnd   the marker ends the parry state: hits land again, the highlight fades. The character stays held
--              (ParryState is Recovering) until the animation ends, which ends the task.
--   Hit        Damage stops the task with this reason (TypeParry.HitReason) when a hit was parried. What was paid comes back
--              with a surplus (TypeParry.HitRefundMultiplier). Parry makes way for ParryHit and the character is free at once,
--              while ParryHit plays out by itself.
-- Any other stop (a stagger in the recovery, a weapon going) lets go of everything without showing a hit.
-- Every ending hands the highlight over to a flash highlight, which removes itself, so nothing outlives the task and the
-- next parry finds the name free.
-- Parallel on purpose: a policy evicts before Start gets to refuse, and a parry that was refused (no weapon) must not cost
-- the character what it was doing. Start clears the arms itself once it knows the parry is happening.
local ParryTask = {}
ParryTask.__index = ParryTask
setmetatable(ParryTask, Task)

function ParryTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Parry,
		Resources = { ResourceEnum.Arms },
		Dependencies = {
			Dependencies.Functions,
			Dependencies.Scheduler,
		},
		Policy = TypeTask.Policy.Parallel,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, ParryTask)
	self.Functions = base.Functions
	self.CharacterAPI = base.CharacterAPI

	-- Whether we hold the parry state, so one we never took is never given back
	self.HoldsState = false
	-- Whether we are holding the character still
	self.MovementHeld = false
	-- Whether the animation got to the ParryEnd marker
	self.MarkerReached = false
	-- What this parry paid, which is what a parried hit gives back
	self.Paid = 0
	-- Set when the weapon holding the parry animations went: its tracks are unloaded already
	self.AnimationsGone = false
	self.Highlight = nil :: TypeHighlights.Highlight?
	self.MarkerConnection = nil :: any
	self.StoppedConnection = nil :: any

	return self
end

-- The parry sounds are the equipped weapon's, like its animations
function ParryTask:_playSound(soundName: string)
	local weapon = self.Functions:CallFunction(FunctionEnum.GetEquippedWeapon)
	if not weapon then
		return
	end

	self.Functions:CallFunction(FunctionEnum.PlaySound, soundName, weapon)
end

-- Cancels pending tasks, doesnt lock movement
function ParryTask:_holdStill()
	self.Base.Scheduler:StopCategory(CategoryEnum.Movement, "Parry does not allow moving")
end

function ParryTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (animation over, parried a hit, cut short, death), let go of everything we took
	self.Terminated:Connect(function(reason: string)
		self:_cleanup(reason)
	end)

	-- Asked before anything is touched, and paid only once the parry is allowed: refused it costs nothing, and unaffordable
	-- it never takes the state
	local affordable, declined = self.Functions:CallFunction(FunctionEnum.CanAffordStamina, TypeStamina.Costs.Parry)
	if not affordable then
		local failure = declined or "Cannot afford to parry"
		self:Stop(failure)
		return false, failure
	end

	-- Refused without a weapon
	local began, refusal = self.Functions:CallFunction(FunctionEnum.BeginParry)
	if not began then
		local failure = refusal or "Cannot parry"
		self:Stop(failure)
		return false, failure
	end
	self.HoldsState = true

	local price = self.Functions:CallFunction(FunctionEnum.GetStaminaCost, TypeStamina.Costs.Parry)
	local paid, declinedPurchase = self.Functions:CallFunction(FunctionEnum.PurchaseStamina, TypeStamina.Costs.Parry)
	if not paid then
		local failure = declinedPurchase or "Cannot afford to parry"
		self:Stop(failure)
		return false, failure
	end
	self.Paid = price or 0

	-- The arms are ours from here
	self.Base.Scheduler:StopResource(ResourceEnum.Arms, "Parrying")

	local handle = self.Functions:CallFunction(FunctionEnum.PlayAnimation, Animations.Parry, FADE_TIME, nil, false)
	if not handle then
		local failure = "Parry animation could not be played"
		self:Stop(failure)
		return false, failure
	end

	self.MovementHeld = true

	-- Kills pending movement tasks
	self:_holdStill()

	self.Highlight = self.CharacterAPI:CreateHighlight(HIGHLIGHT_NAME, {
		FillColor = HIGHLIGHT_COLOR,
		OutlineColor = HIGHLIGHT_COLOR,
		FillTransparency = 1,
		OutlineTransparency = 0,
	})
	if self.Highlight then
		self.Highlight:TweenFillTransparency(1, START_FLASH_TIME)
	end

	self:_playSound(Sounds.Start)

	self.MarkerConnection = handle:GetMarkerReachedSignal(TypeParry.EndMarker):Connect(function()
		self:_parryEnded()
	end)
	-- Stopped fires when the animation ends as well as when it is stopped. Without the marker this is what ends the parry.
	self.StoppedConnection = handle.Stopped:Connect(function()
		-- A parry started right after a parried hit plays the same track, and hears of that earlier stop late
		local remaining = handle:GetTimeRemaining()
		if remaining and remaining > 0 then
			return
		end

		if self.HoldsState and not self.MarkerReached then
			warn("Parry animation ended without the", TypeParry.EndMarker, "marker, so it parried for all of its length")
		end
		self:Complete("Parry finished")
	end)

	return true
end

-- The ParryEnd marker: hits land again, and the rest of the animation is the recovery
function ParryTask:_parryEnded()
	if not self:IsRunning() then
		return
	end
	self.MarkerReached = true
	self.Functions:CallFunction(FunctionEnum.CloseParry)
	self:_endHighlight(1, END_FADE_TIME)
end

-- Ends the task because something else takes the character over. With `animationsGone` (the weapon that held them was
-- unequipped) there are no tracks left to put away.
function ParryTask:Cancel(reason: string?, animationsGone: boolean?): boolean
	self.AnimationsGone = animationsGone == true
	return self:Stop(reason or "Parry cancelled")
end

-- Hands the highlight over to a flash starting from this fill, which fades out and removes itself. The flash first, so
-- there is no frame without either.
function ParryTask:_endHighlight(fillTransparency: number, fadeTime: number)
	local highlight = self.Highlight
	if not highlight then
		return
	end
	self.Highlight = nil

	if self.Base:IsAlive() then
		self.CharacterAPI:FlashHighlight({
			FillColor = HIGHLIGHT_COLOR,
			OutlineColor = HIGHLIGHT_COLOR,
			FillTransparency = fillTransparency,
			OutlineTransparency = 0,
			FadeTime = fadeTime,
		})
	end

	highlight:Destroy()
end

function ParryTask:_disconnect()
	if self.MarkerConnection then
		self.MarkerConnection:Disconnect()
		self.MarkerConnection = nil
	end
	if self.StoppedConnection then
		self.StoppedConnection:Disconnect()
		self.StoppedConnection = nil
	end
end

function ParryTask:_cleanup(reason: string)
	self:_disconnect()

	if not self.HoldsState then
		return
	end
	self.HoldsState = false

	-- The state goes first. The requests below can yield, and until it is given back hits are still taken as parried.
	self.Functions:CallFunction(FunctionEnum.EndParry)

	if self.MovementHeld then
		self.MovementHeld = false
		self.Functions:CallFunction(FunctionEnum.UnlockMovement, self)
	end

	local parriedHit = reason == TypeParry.HitReason
	if parriedHit and self.Paid > 0 then
		local refund = self.Paid * TypeParry.HitRefundMultiplier
		self.Functions:CallFunction(FunctionEnum.RestoreStamina, refund, "ParryRefund")
	end

	self:_endHighlight(if parriedHit then 0 else 1, if parriedHit then HIT_FLASH_TIME else END_FADE_TIME)

	-- A dead character has no tracks left to play or stop, and neither does one whose weapon went
	if not self.Base:IsAlive() or self.AnimationsGone then
		return
	end

	self.Functions:CallFunction(FunctionEnum.StopAnimation, Animations.Parry, FADE_TIME)

	if parriedHit then
		self.Functions:CallFunction(FunctionEnum.PlayAnimation, Animations.Hit, FADE_TIME, nil, false)
		self.Base.Functions:CallFunction(FunctionEnum.PlayVFX, TypeDamage.ParryVFX, self.Base.Character)
		self:_playSound(Sounds.Hit)
	end
end

return ParryTask
