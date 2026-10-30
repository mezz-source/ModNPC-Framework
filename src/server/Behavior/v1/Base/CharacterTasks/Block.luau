local ServerScriptService = game:GetService("ServerScriptService")
local TypeBlock = require(ServerScriptService.ModNPCServer.Types.v1.TypeBlock)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDamage = require(ServerScriptService.ModNPCServer.Types.v1.TypeDamage)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTask = require(ServerScriptService.ModNPCServer.Types.v1.TypeTask)
local Task = require(script.Parent.Parent.Task)

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local Animations = TypeBlock.Animations

local CategoryEnum = TypeTask.CategoriesEnum
local Dependencies = TypeTask.Dependencies
local ResourceEnum = TypeTask.ResourcesEnum

local FADE_TIME = 0.1
-- Seconds the one who broke the guard is told it is open (BlockBroken), when the break animation can't say
local BREAK_OPENING_FALLBACK = 0.5

-- How each block animation is loaded. The loop holds the guard up and sits under the rest, which play over it for a moment:
-- the start as the guard goes up, the end as it comes down, and the hit as it takes a blow. A break is the loudest of them.
local ANIMATION_SETTINGS: { [string]: { Priority: Enum.AnimationPriority, Loop: boolean } } = {
	[Animations.Loop] = { Priority = Enum.AnimationPriority.Action, Loop = true },
	[Animations.Start] = { Priority = Enum.AnimationPriority.Action2, Loop = false },
	[Animations.End] = { Priority = Enum.AnimationPriority.Action2, Loop = false },
	[Animations.Hit] = { Priority = Enum.AnimationPriority.Action2, Loop = false },
	[Animations.Break] = { Priority = Enum.AnimationPriority.Action3, Loop = false },
}

-- The characters whose block animations are loaded already. Loading them again would put a second set of tracks next to
-- the first, so a character that blocks many times only loads them the first.
local loadedFor: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A character guarding itself with its arms. While it lasts the character is Blocking (see Damage:BeginBlock), and every hit
-- that comes in is absorbed: Damage tells us how heavy it was (Absorb), and we pay for it in stamina. A character that
-- can't pay has its guard broken instead, which ends the block. The hit is absorbed either way.
--   Start   plays the loop and the start animation together, and keeps the loop up until the block ends
--   End     as it ends the loop is put away and the end animation plays, or the break animation if it was broken
-- The block lasts until something stops it (a stop of the scheduler, a task that needs the arms, a break). Nothing here
-- decides when to raise or lower the guard. A guard broken by someone's hit tells them (a BlockBroken stimulant) for as long
-- as the break animation leaves the character open.
-- Replace on purpose: raising the guard takes the arms, which cuts short whatever else is using them.
local BlockTask = {}
BlockTask.__index = BlockTask
setmetatable(BlockTask, Task)

function BlockTask.new(base, _: number?)
	local task, errorMessage = Task.new(base, {
		Category = CategoryEnum.Block,
		Resources = { ResourceEnum.Arms },
		Dependencies = {
			Dependencies.Assets,
			Dependencies.Functions,
		},
		Policy = TypeTask.Policy.Replace,
	})

	if not task then
		return nil, errorMessage
	end

	local self = setmetatable(task, BlockTask)
	self.Assets = base.Assets
	self.Functions = base.Functions

	-- Whether we hold the block state, so one we never took is never given back
	self.HoldsState = false
	-- Set when the guard is broken. A task that ended any other way ended normally.
	self.Broken = false
	-- Whose hit broke the guard, if anyone's we know of
	self.BrokenBy = nil :: Model?
	-- Set when something else took over (an attack): the guard just goes, without an ending of its own
	self.Cancelled = false
	-- Who raised the guard and so puts it down ("Defense" for a last moment guard, "Engage" once it holds it). Only a label
	-- the two agree on; nothing here reads it.
	self.Holder = nil :: string?

	self:_loadAnimations()

	return self
end

-- Loads the block animations of the character's assets (Animations/Blocks), the first time it blocks. An animation the
-- character doesn't have is just not shown.
function BlockTask:_loadAnimations()
	if loadedFor[self.Base] then
		return
	end

	local animations = self.Assets:GetAnimationCategory(TypeBlock.AnimationCategory, self.Assets.BaseSource)
	if not animations then
		return
	end
	loadedFor[self.Base] = true

	for _, animation in ipairs(animations) do
		local settings = ANIMATION_SETTINGS[animation.Name]
		if settings then
			self.Functions:CallFunction(
				FunctionEnum.LoadAnimation,
				animation,
				animation.Name,
				settings.Priority,
				settings.Loop,
				self.Assets.BaseSource
			)
		end
	end
end

function BlockTask:_playSound(soundName: string)
	if soundName == "" then
		return
	end

	self.Functions:CallFunction(FunctionEnum.PlaySound, soundName)
end

function BlockTask:Start()
	local started, errorMessage = Task.Start(self)
	if not started then
		return false, errorMessage
	end

	-- however we end (stopped, replaced, broken, death), let go of everything we took
	self.Terminated:Connect(function()
		self:_cleanup()
	end)

	local began, reason = self.Functions:CallFunction(FunctionEnum.BeginBlock)
	if not began then
		local failure = reason or "Cannot block"
		self:Stop(failure)
		return false, failure
	end

	self.HoldsState = true
	self.Functions:CallFunction(FunctionEnum.PlayAnimation, Animations.Loop, FADE_TIME, nil, true)
	self.Functions:CallFunction(FunctionEnum.PlayAnimation, Animations.Start, FADE_TIME, nil, false)

	return true
end

-- Takes a hit of the given weight (see Damage:GetHitCategory) from attacker, if known. The block pays for it in stamina and
-- shows the hit, or if it can't pay the guard is broken. Returns whether the guard held.
function BlockTask:Absorb(category: string, attacker: Model?): boolean
	if not self:IsRunning() then
		return false
	end

	-- a weight we don't know is taken for the heaviest
	local cost = TypeBlock.HitCosts[category] or TypeBlock.HitCosts.Heavy
	local paid = self.Functions:CallFunction(FunctionEnum.PurchaseStamina, cost)
	if not paid then
		self.BrokenBy = attacker
		self:Break("Guard broken by a " .. tostring(category) .. " hit")
		self:_playSound(TypeDamage.BlockBreakSound)
		return false
	end

	self.Functions:CallFunction(FunctionEnum.PlayAnimation, Animations.Hit, FADE_TIME, nil, false)
	self:_playSound(TypeDamage.BlockSound)

	return true
end

-- Ends the block by force: the guard is broken, and the break animation plays instead of the end. The character is left
-- with a broken guard (BreakBlock: exhausted, and unable to block until that is over).
function BlockTask:Break(reason: string?): boolean
	if not self:IsRunning() then
		return false
	end
	self.Broken = true
	local breakReason = reason or "Guard broken"

	-- Before the stop, which yields on the animations: the guard can't go up again from the moment it is broken
	self.Functions:CallFunction(FunctionEnum.BreakBlock, breakReason)

	return self:Stop(breakReason)
end

-- Ends the block because something else takes the character over. The guard is put away without an ending animation, as
-- whatever cancelled it (an attack) shows its own and the ending would play over it.
function BlockTask:Cancel(reason: string?): boolean
	self.Cancelled = true

	return self:Stop(reason or "Block cancelled")
end

function BlockTask:_cleanup()
	if not self.HoldsState then
		return
	end
	self.HoldsState = false

	-- The state goes first. The animation requests below can yield, and until the state is given back a new block is refused
	-- and hits are still taken as blocked.
	self.Functions:CallFunction(FunctionEnum.EndBlock)

	-- A dead character has no tracks left to play or stop
	if self.Base:IsAlive() then
		for _, animationName in ipairs({ Animations.Loop, Animations.Start, Animations.Hit }) do
			self.Functions:CallFunction(FunctionEnum.StopAnimation, animationName, FADE_TIME)
		end

		if not self.Cancelled then
			local ending = if self.Broken then Animations.Break else Animations.End
			local handle = self.Functions:CallFunction(FunctionEnum.PlayAnimation, ending, FADE_TIME, nil, false)
			if self.Broken then
				self:_announceBreak(handle)
			end
		end
	end
end

-- Tells whoever broke the guard that we are open, for as long as the break animation lasts
function BlockTask:_announceBreak(breakHandle: any)
	local attacker = self.BrokenBy
	if not attacker then
		return
	end

	local opening = if breakHandle then breakHandle:GetTimeRemaining() else nil
	if not opening or opening <= 0 then
		opening = BREAK_OPENING_FALLBACK
	end

	self.Base
		:NewStimulant(TypeStimulant.Names.BlockBroken)
		:To(attacker)
		:WithPriority(TypeStimulant.Priorities.High)
		:Lasting(opening + 2)
		:Send()
end

return BlockTask
