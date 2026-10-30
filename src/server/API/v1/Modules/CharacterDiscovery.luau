local ServerScriptService = game:GetService("ServerScriptService")
local CharacterUtility = require(script.Parent.CharacterUtility)
local Signal = require(ServerScriptService.ModNPCServer.Util.Signal)

-- The one source of truth for which characters exist. It only decides when a character is added (tracked) and when it
-- is removed; Targetting, Stimulants and whoever else needs the list listen to it instead of looking for themselves,
-- so changing how characters are found only ever happens here.
local CharacterDiscovery = {}

-- how long to wait for a newly added humanoid's character to pass validation
local VALIDATION_TIMEOUT = 5
local VALIDATION_INTERVAL = 0.1
-- how often tracked characters are re-checked for a missing model/humanoid or zero health
local SWEEP_INTERVAL = 1

-- character -> its type (CharacterUtility.Type), decided once as it is added
local tracked: { [Model]: string } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}
local pending: { [Model]: boolean } = {}

-- (character: Model, characterType: string)
CharacterDiscovery.Added = Signal.new()
-- (character: Model). Fired once it is no longer tracked, so it never shows up in _getTracked from a handler.
CharacterDiscovery.Removed = Signal.new()

local function untrack(character: Model)
	local characterConnections = connections[character]
	if characterConnections then
		for _, connection in characterConnections do
			connection:Disconnect()
		end
	end

	connections[character] = nil
	if tracked[character] == nil then
		return
	end

	tracked[character] = nil
	CharacterDiscovery.Removed:Fire(character)
end

local function track(character: Model, humanoid: Humanoid)
	-- We allow unloaded characters so that instanced ModNPCs don't get incorrectly marked as generics
	-- due to the unload flag deeper in type checks
	local allowUnloaded = true
	local characterType = CharacterUtility.getCharacterType(character, allowUnloaded).Data
	if not characterType then
		return
	end

	tracked[character] = characterType
	connections[character] = {
		character.Destroying:Once(function()
			untrack(character)
		end),
		humanoid.Died:Once(function()
			untrack(character)
		end),
	}

	CharacterDiscovery.Added:Fire(character, characterType)
end

-- Safety net for the Destroying/Died connections: catches characters whose humanoid was removed or replaced,
-- that were reparented out of the workspace, or that otherwise lost their health without firing Died.
-- Deliberately lighter than isValidCharacter: no root part lookup, no response tables.
local function isAlive(character: Model): boolean
	if not character:IsDescendantOf(workspace) then
		return false
	end

	local humanoid = CharacterUtility._getHumanoid(character)
	return humanoid ~= nil and humanoid.Health > 0
end

local function sweep()
	for character in tracked do
		if not isAlive(character) then
			untrack(character)
		end
	end
end

local function considerHumanoid(humanoid: Humanoid)
	local character = humanoid.Parent
	if not character or not character:IsA("Model") or tracked[character] or pending[character] then
		return
	end
	pending[character] = true

	task.spawn(function()
		local deadline = os.clock() + VALIDATION_TIMEOUT
		while humanoid.Parent == character and character:IsDescendantOf(workspace) do
			if CharacterUtility.isValidCharacter(character).Data then
				track(character, humanoid)
				break
			end

			if humanoid.Health <= 0 or os.clock() >= deadline then
				break
			end

			task.wait(VALIDATION_INTERVAL)
		end

		pending[character] = nil
	end)
end

-- Hands every character tracked so far to onAdded, then keeps both callbacks connected. Core inits the API modules in
-- no particular order, so a listener can't count on connecting before discovery has started.
-- Not a request (no ModuleResponse), hence the underscore.
function CharacterDiscovery._observe(
	onAdded: (character: Model, characterType: string) -> (),
	onRemoved: (character: Model) -> ()
)
	for character, characterType in tracked do
		task.spawn(onAdded, character, characterType)
	end

	return {
		CharacterDiscovery.Added:Connect(onAdded),
		CharacterDiscovery.Removed:Connect(onRemoved),
	}
end

function CharacterDiscovery._isTracked(character: Model): boolean
	return tracked[character] ~= nil
end

-- character -> its type, a copy
function CharacterDiscovery._getTracked(): { [Model]: string }
	return table.clone(tracked)
end

function CharacterDiscovery.init(_)
	task.defer(function()
		if not CharacterUtility._validationReady() then
			print("Awaiting character utility validation readiness before initalizing")
			repeat
				task.wait()
			until CharacterUtility._validationReady()
		end

		workspace.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Humanoid") then
				considerHumanoid(descendant)
			end
		end)

		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("Humanoid") then
				considerHumanoid(descendant)
			end
		end

		while true do
			task.wait(SWEEP_INTERVAL)
			sweep()
		end
	end)

	print("V1 CharacterDiscovery initialized")
end

return CharacterDiscovery
