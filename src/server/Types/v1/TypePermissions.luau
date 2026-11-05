local TypePermissions = {}

-- The bools of a character's Config/Permissions folder. Each one switches a core activity on or off, so a mod script (or an
-- edit to the config, live in Studio too) can take an ability away without hooking the functions behind it. The behavior
-- only reads them: they are checked when an activity is about to start, so turning one off never cuts short what is already
-- under way (a swing in progress, a guard already up), it only stops the next one.
--
-- Only an explicit false forbids. A permission the folder doesn't have, or one that isn't a bool, allows its activity, so a
-- character made before a permission existed behaves as it always did. See Configuration:IsPermitted.
TypePermissions.Names = table.freeze({
	-- Walking and jumping (the CanMove ability). Impulses (knockback, launches, dodges) are not movement.
	CanMove = "CanMove",
	-- Starting an attack (the CanAttack ability)
	CanAttack = "CanAttack",
	-- Looking for targets. Off, the targets already known (and the focus target) are kept as they are.
	CanSearchTargets = "CanSearchTargets",
	-- The character's frame updates and reaction ticks. Off, the character is frozen: its tasks keep running but none of them
	-- (nor the thought process, stamina or anything on base.Heartbeat) is updated until it is back on.
	CanThink = "CanThink",
	-- Dodging (the CanDodge ability), which also takes being evasive (strafing) with it
	CanDodge = "CanDodge",
	-- Raising a guard (the CanBlock ability)
	CanBlock = "CanBlock",
	-- Trying to parry (the CanParry ability)
	CanParry = "CanParry",
	-- Starting a sprint
	CanSprint = "CanSprint",
	-- Starting an aimless walk while there is no target (the Wander task). Off, the character stands where it is.
	CanWander = "CanWander",
	-- Being staggered by a hit (Stagger and StaggerBackwards specials)
	CanBeStaggered = "CanBeStaggered",
	-- Being launched by a hit
	CanBeLaunched = "CanBeLaunched",
	-- Losing health to hits. The hit still lands (it is blocked, dodged and announced as usual), it just does no damage.
	CanBeDamaged = "CanBeDamaged",
	-- Taking in stimulants other characters send (seeing attacks coming, hearing a sprint at us...)
	CanPerceive = "CanPerceive",
	-- Meeting a hit we were warned of with a timed dodge or a last moment guard (see Defense)
	CanReactToAttacks = "CanReactToAttacks",
	-- Turning to face the focus target
	CanFaceTarget = "CanFaceTarget",
	-- Getting stamina back
	CanRegenerateStamina = "CanRegenerateStamina",
	-- Speaking lines. Reserved: dialogue has nothing that speaks yet.
	CanSpeak = "CanSpeak",
})

export type Permission = keyof<typeof(TypePermissions.Names)>

TypePermissions.Folder = "Permissions"

-- Whether a permission's value (nil when the folder doesn't have it) allows its activity. The one place the rule lives, so
-- the API and the behavior read permissions the same way.
function TypePermissions.isPermitted(value: any): boolean
	return value ~= false
end

-- Whether name is one of the permissions above
function TypePermissions.isPermission(name: any): boolean
	return type(name) == "string" and TypePermissions.Names[name] == name
end

return TypePermissions
