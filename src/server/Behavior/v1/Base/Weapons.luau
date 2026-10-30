local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)

local Weapons = {}
Weapons.__index = Weapons

local FunctionEnum = TypeCharacterFunctions.FunctionEnum
local WeaponEvents = TypeCharacterEvents.Names.Weapon
local ContentEvents = TypeCharacterEvents.Names.Content
local TargettingEvents = TypeCharacterEvents.Names.Targetting

-- The core tool animations. Every weapon brings its own in the Core category of its Assets/Animations (the NPC's own
-- Core animations are the fallback when it does not). They are tracks named like the animation, loaded as that
-- weapon's content so they go when it does.
local ARMED = "ToolArmed"
local DISARM = "ToolDisarm"
local ARM_LOOP = "ToolArmLoop"
local ANIMATION_CATEGORY = "Core"

local FADE_TIME = 0.2

-- AlwaysArmed in the weapon's Config
local ALWAYS_ARMED_SETTING = { "WeaponSettings", "AlwaysArmed" }

-- The transitions are one-shots over everything else. The loop only holds the weapon pose, so it sits above the walk
-- and sprint cycles (Idle) to keep the arms where they are while the legs still walk.
local ANIMATION_PRIORITIES = {
	[ARMED] = Enum.AnimationPriority.Action,
	[DISARM] = Enum.AnimationPriority.Action,
	[ARM_LOOP] = Enum.AnimationPriority.Movement,
}
local ANIMATION_LOOPS = {
	[ARMED] = false,
	[DISARM] = false,
	[ARM_LOOP] = true,
}

-- One weapon is in hand at a time: equipping another drops the one held. A weapon is equipped by the name of a model
-- inside the character. Its content (assets, attacks) is a source for as long as it is equipped, and while it is,
-- it can be armed (drawn) and disarmed. A weapon with AlwaysArmed is armed as soon as it is equipped and stays so.
function Weapons.new(Base: any, character: Model)
	local self = setmetatable({}, Weapons)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Functions = Base.Functions

	self.Weapon = nil :: Instance?
	self.Armed = false
	self.AlwaysArmed = false
	-- which core animations the current weapon has loaded
	self.Loaded = {} :: { [string]: boolean }
	-- changes whenever the arm state does, so an arm animation that finishes late can tell it is out of date
	self.ArmToken = 0
	self.ArmConnection = nil
	-- Characters targetting has spotted and not lost yet, so a weapon equipped mid-fight is drawn straight away
	self.Targets = {} :: { [Model]: boolean }

	-- A source is the weapon's content and exists exactly as long as the weapon is equipped, however it got equipped
	-- or unequipped (or destroyed). Subscribed after Assets, Sound, Animation and Attacks, so they have loaded the
	-- source by the time it is announced here and still have it when it goes.
	self.Subscriptions = {
		Base.Events:Subscribe(ContentEvents.SourceAdded, function(payload: TypeCharacterEvents.ContentSourceAdded)
			if typeof(payload.Source) == "Instance" then
				self:_equipped(payload.Source)
			end
		end),
		Base.Events:Subscribe(ContentEvents.SourceRemoved, function(payload: TypeCharacterEvents.ContentSourceRemoved)
			self:_unequipped(payload.Source)
		end),
		-- Draw when somebody is spotted, put away when nobody is left
		Base.Events:Subscribe(TargettingEvents.TargetSpotted, function(context)
			self.Targets[context.Character] = true
			self:_callForArms()
		end),
		Base.Events:Subscribe(TargettingEvents.TargetLost, function(context)
			self.Targets[context.Character] = nil
		end),
		Base.Events:Subscribe(TargettingEvents.AllTargetsLost, function()
			table.clear(self.Targets)
			if self.Armed then
				self.Functions:CallFunction(FunctionEnum.DisarmWeapon)
			end
		end),
	}

	return self
end

-- Puts on the weapon the character comes with. Runs once the character is built and its functions are registered,
-- because equipping is a function.
function Weapons:Init()
	local weapons = self.CharacterAPI:GetWeapons()
	if #weapons == 0 then
		return
	end

	table.sort(weapons, function(a, b)
		return a.Name < b.Name
	end)

	-- A weapon already flagged as equipped (saved that way) has no source and may not be welded. Start it over.
	local target
	for _, weapon in ipairs(weapons) do
		if self.CharacterAPI:IsWeaponEquipped(weapon) then
			target = target or weapon
			self.CharacterAPI:UnequipWeapon(weapon)
		end
	end

	target = target or weapons[1]
	local equipped, reason = self.Functions:CallFunction(FunctionEnum.EquipWeapon, target.Name)
	if not equipped then
		warn("Could not equip", target.Name, "for character:", self.Character.Name, "-", reason)
	end
end

function Weapons:GetEquippedWeapon(): Instance?
	return self.Weapon
end

function Weapons:IsArmed(): boolean
	return self.Armed
end

-- Equips the weapon model with this name inside the character. The weapon held until now is dropped into the
-- workspace. Its content becomes a source and its core animations load; it is armed on the spot if it is always armed.
function Weapons:EquipWeapon(weaponName: string): (boolean, string?)
	local weapon = self.Character:FindFirstChild(weaponName)
	if not weapon then
		return false, "Character has no weapon named " .. tostring(weaponName)
	end

	if weapon == self.Weapon then
		return false, "Weapon is already equipped"
	end

	if not self.CharacterAPI:IsValidWeapon(weapon) then
		return false, tostring(weaponName) .. " is not a valid weapon"
	end

	local held = self.Weapon or self.CharacterAPI:GetEquippedWeapon()
	if held and not self.CharacterAPI:DropWeapon(held) then
		return false, "Could not drop " .. held.Name
	end

	if not self.CharacterAPI:EquipWeapon(weapon) then
		return false, "Could not equip " .. weapon.Name
	end

	return true
end

-- Takes the weapon out of hand but keeps it in the character
function Weapons:UnequipWeapon(): (boolean, string?)
	if not self.Weapon then
		return false, "No weapon equipped"
	end

	if not self.CharacterAPI:UnequipWeapon(self.Weapon) then
		return false, "Could not unequip " .. self.Weapon.Name
	end

	return true
end

-- Plays the arm animation, which carries over into the loop that holds the pose for as long as the weapon is armed
function Weapons:ArmWeapon(): (boolean, string?)
	if not self.Weapon then
		return false, "No weapon equipped"
	end

	if self.Armed then
		return false, "Weapon is already armed"
	end

	self.Armed = true
	self:_newArmToken()
	local token = self.ArmToken

	local armHandle = if self.Loaded[ARMED] then self:_play(ARMED) else nil
	if armHandle then
		-- Stopped fires when the animation ends as well as when it is stopped; a stop (disarm) changed the token
		self.ArmConnection = armHandle.Stopped:Connect(function()
			self:_disconnectArm()
			self:_startArmLoop(token)
		end)
	else
		self:_startArmLoop(token)
	end

	self.Base.Events:Dispatch(WeaponEvents.Armed, { Weapon = self.Weapon } :: TypeCharacterEvents.WeaponChanged)
	return true
end

-- Plays the disarm animation in place of the arm pose. A weapon that is always armed cannot be disarmed.
function Weapons:DisarmWeapon(): (boolean, string?)
	if not self.Weapon then
		return false, "No weapon equipped"
	end

	if self.AlwaysArmed then
		return false, "Weapon is always armed"
	end

	if not self.Armed then
		return false, "Weapon is not armed"
	end

	self.Armed = false
	self:_newArmToken()
	for _, animationName in ipairs({ ARM_LOOP, ARMED }) do
		if self.Loaded[animationName] then
			self.Functions:CallFunction(FunctionEnum.StopAnimation, animationName, FADE_TIME)
		end
	end

	if self.Loaded[DISARM] then
		self:_play(DISARM)
	end

	self.Base.Events:Dispatch(WeaponEvents.Disarmed, { Weapon = self.Weapon } :: TypeCharacterEvents.WeaponChanged)
	return true
end

function Weapons:_play(animationName: string)
	return self.Functions:CallFunction(
		FunctionEnum.PlayAnimation,
		animationName,
		FADE_TIME,
		ANIMATION_PRIORITIES[animationName],
		ANIMATION_LOOPS[animationName]
	)
end

function Weapons:_startArmLoop(token: number)
	if token ~= self.ArmToken or not self.Armed or not self.Loaded[ARM_LOOP] then
		return
	end

	self:_play(ARM_LOOP)
end

function Weapons:_disconnectArm()
	if self.ArmConnection then
		self.ArmConnection:Disconnect()
		self.ArmConnection = nil
	end
end

function Weapons:_newArmToken()
	self:_disconnectArm()
	self.ArmToken += 1
end

-- The weapon's core animations come from its own assets. They are loaded as the weapon's content (the source), which
-- is what unloads the tracks when it is unequipped.
function Weapons:_loadAnimations(weapon: Instance)
	for _, animationName in ipairs({ ARMED, DISARM, ARM_LOOP }) do
		local animation = self.Base.Assets:GetAnimation(ANIMATION_CATEGORY .. "/" .. animationName, weapon)
		if not animation then
			warn("Weapon", weapon.Name, "has no", ANIMATION_CATEGORY .. "/" .. animationName, "animation")
			continue
		end

		local handle = self.Functions:CallFunction(
			FunctionEnum.LoadAnimation,
			animation,
			animationName,
			ANIMATION_PRIORITIES[animationName],
			ANIMATION_LOOPS[animationName],
			weapon
		)
		self.Loaded[animationName] = handle ~= nil
	end
end

function Weapons:_equipped(weapon: Instance)
	-- a weapon equipped around this module (straight through the CharacterAPI) while another was held
	if self.Weapon and self.Weapon ~= weapon then
		self:_unequipped(self.Weapon)
	end

	self.Weapon = weapon
	self.AlwaysArmed = self.CharacterAPI:GetWeaponSetting(weapon, ALWAYS_ARMED_SETTING) == true
	self:_loadAnimations(weapon)

	if self.AlwaysArmed or next(self.Targets) ~= nil then
		self:_callForArms()
	end
end

-- Asks for the weapon to be drawn, through the function so a mod script can hook or replace it. Does nothing without
-- a weapon or when it is already drawn.
function Weapons:_callForArms()
	if self.Weapon and not self.Armed then
		self.Functions:CallFunction(FunctionEnum.ArmWeapon)
	end
end

function Weapons:_unequipped(source: TypeCDN.ContentSource)
	if not self.Weapon or source ~= self.Weapon then
		return
	end

	local weapon = self.Weapon
	local wasArmed = self.Armed

	-- Animation unloads the weapon's tracks when its source is removed, so nothing is left to stop here
	self:_newArmToken()
	self.Weapon = nil
	self.Armed = false
	self.AlwaysArmed = false
	self.Loaded = {}

	if wasArmed then
		self.Base.Events:Dispatch(WeaponEvents.Disarmed, { Weapon = weapon } :: TypeCharacterEvents.WeaponChanged)
	end
end

function Weapons:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription:Unsubscribe()
	end

	self.Subscriptions = {}
	self:_newArmToken()
	self.Weapon = nil
	self.Loaded = {}
end

return Weapons
