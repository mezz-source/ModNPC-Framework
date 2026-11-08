local ServerScriptService = game:GetService("ServerScriptService")
local TypeDialogue = require(ServerScriptService.ModNPCServer.API.v1.Modules.Dialogue.TypeDialogue)
local TypeAPIFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeAPIFunctions)
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)
local TypeCharacterEvents = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterEvents)
local TypeCharacterFunctions = require(ServerScriptService.ModNPCServer.Types.v1.TypeCharacterFunctions)
local TypeDialogueFrame = require(ServerScriptService.ModNPCServer.Types.v1.TypeDialogueFrame)
local TypeStimulant = require(ServerScriptService.ModNPCServer.Types.v1.TypeStimulant)
local TypeTeams = require(ServerScriptService.ModNPCServer.Types.v1.TypeTeams)

local Dialogue = {}
Dialogue.__index = Dialogue

type Priority = TypeDialogueFrame.Priority
type SayData = TypeDialogueFrame.SayData
type LineOptions = TypeDialogueFrame.LineOptions
type LineData = TypeCDN.LineData

local DialogueEventEnums = TypeDialogue.Events
local FunctionEnum = TypeCharacterFunctions.FunctionEnum

-- Lines played together under one priority: one line for a category, several for a conversation. It is running while the
-- frame's current line is one of its own.
type Sequence = {
	Priority: Priority,
	Ids: { [number]: boolean },
	LastId: number,
}

local Modules = TypeAPIFunctions.Modules
local Functions = TypeAPIFunctions.Functions.ContentDelivery
local Priorities = TypeDialogueFrame.Priorities
local PriorityRanks = TypeDialogueFrame.PriorityRanks

local CONVERSATIONS = TypeDialogueFrame.ConversationsCategory

local TALK_SPEED_PATH = { TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.TalkSpeedSetting }
local TEXT_COLOR_PATH = { TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.TextColorSetting }
local CHATTINESS_PATH = { TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.ChattinessSetting }
local PLACEHOLDER = "%%s"
local BANTER_START = "CombatBanterStart"
local BANTER_RESPOND = "CombatBanterRespond"
local FRIEND_START = "SpotFriendStart"
local FRIEND_RESPOND = "SpotFriendResponse"
local SPOT_ENEMY_INDIVIDUAL = "SpotEnemyIndividual"
local SPOT_ENEMY_TEAMED = "SpotEnemyTeamed"
local NEUTRAL_TEAM = TypeTeams.CoreTeams.Neutral
-- How long teammates have to answer a callout
local CALLOUT_LASTING = 3

local function isTalkSpeed(value: any): boolean
	return typeof(value) == "number" and value > 0 and value < math.huge
end

local function placeholderCount(text: string): number
	local _, count = string.gsub(text, PLACEHOLDER, "")
	return count
end

-- A name is plain text dropped into markup, so its "<" and "\" are escaped (see Markup) and can't open a tag
local function escapeMarkup(text: string): string
	return (string.gsub(text, "[\\<]", function(char)
		return "\\" .. char
	end))
end

-- Fills the %s holders in order. Holders past the last name are left empty.
local function fillNames(text: string, names: { string }): string
	local index = 0
	return (string.gsub(text, PLACEHOLDER, function()
		index += 1
		return escapeMarkup(tostring(names[index] or ""))
	end))
end

-- Loads the character's lines and makes its dialogue frame, which stays until the character is destroyed: the TalkBlip sound
-- of its assets is what it types with, and Config/Dialogue/TalkSpeed is how fast. A failure to make the frame (no head, no
-- DialogueUI asset) is warned about by the API and leaves the character mute, which changes nothing else.
--
-- Lines are said by category (SayLine, through Functions), at the priority Config/Dialogue/Priorities gives that category.
function Dialogue.new(Base: any, character: Model)
	local self = setmetatable({}, Dialogue)
	self.Base = Base
	self.Character = character
	self.CharacterAPI = Base.CharacterAPI
	self.Configuration = Base.Configuration
	self.Data = self.CharacterAPI:RequestAPIData(Modules.ContentDelivery, Functions.GetLinesIndex, { character }) or {}
	self.Frame = nil :: TypeDialogueFrame.Frame?
	self.Subscriptions = {}
	-- What is playing, nil once it has finished or been cancelled (see _getActiveSequence)
	self.sequence = nil :: Sequence?
	-- The line last said from each category, so the same one isn't picked twice in a row
	self.lastPicked = {} :: { [string]: string }
	-- When a line of each category was last said (os.clock), for its cooldown
	self.lastSaid = {} :: { [string]: number }
	-- Lines waiting out their random delay (Config/Dialogue/MaxRandomDelay); CancelAll drops them
	self.pendingLines = {} :: { [thread]: boolean }
	self.warnedCategories = {} :: { [string]: boolean }

	local talkSound = Base.Assets:GetSound(TypeDialogueFrame.TalkSoundName)
	local talkSpeed = self.Configuration:Get(TALK_SPEED_PATH)
	if not talkSound then
		warn(character.Name, "has no", TypeDialogueFrame.TalkSoundName, "sound (Assets/Sounds/Individual), so it talks silently")
	end

	local textColor = self.Configuration:Get(TEXT_COLOR_PATH)

	local options = {
		Color = if typeof(textColor) == "Color3" then textColor else nil,
		TalkSound = talkSound,
		TalkSpeed = if isTalkSpeed(talkSpeed) then talkSpeed else nil,
		OnEvent = function(event) 
			self.Base.Functions:CallFunction(FunctionEnum.OnDialogueEvent, event)
		end
	}

	self.Frame = self.CharacterAPI:CreateDialogueFrame(options)

	self:_checkPriorities()

	table.insert(
		self.Subscriptions,
		self.Configuration:Observe(TEXT_COLOR_PATH, function(newColor)
			local frame = self.Frame
			if frame and typeof(newColor) == "Color3" then
				frame:SetColor(newColor)
			end
		end)
	)
	table.insert(
		self.Subscriptions,
		self.Configuration:Observe(TALK_SPEED_PATH, function(newSpeed)
			local frame = self.Frame
			if frame and isTalkSpeed(newSpeed) then
				frame:SetTalkSpeed(newSpeed)
			end
		end)
	)
	-- Whatever we were saying stops when we die. Subscribed before any task, so a death line (the DialogueBark task barks
	-- one) comes after this, not before.
	table.insert(
		self.Subscriptions,
		Base.Events:Subscribe(TypeCharacterEvents.Names.Humanoid.Died, function()
			self:CancelAll()
		end)
	)

	-- print("Dialogue data loaded for character:", character.Name, "Data:", self.Data)
	return self
end

function Dialogue:OnEvent(event: TypeDialogue.Event)
	if event.Kind == DialogueEventEnums.Sfx then
		self.Base.Functions:CallFunction(FunctionEnum.PlaySound, event.Arg)
	elseif event.Kind == DialogueEventEnums.PlayAnimation then
		self.Base.Functions:CallFunction(FunctionEnum.PlayAnimation, event.Arg)
	elseif event.Kind == DialogueEventEnums.StopAnimation then
		self.Base.Functions:CallFunction(FunctionEnum.StopAnimation, event.Arg)
	end

	-- NOTE: event not included above as it'll automatically be dispatched below

	local eventName = TypeDialogue.EventDispatchNames[event.Kind]
	if not eventName then 
		warn("Kind", event.Kind, "dialogue event is not a known kind, cannot dispatch base event")
		return
	end

	-- emit to listeners
	self.Base.Events:Dispatch(eventName, event.Kind, event.Arg)
end

-- Points out categories and priorities that don't match up (most likely a typo in one of the two names)
function Dialogue:_checkPriorities()
	local priorities = self.Configuration:GetEntry({ TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.PrioritiesFolder })
	if type(priorities) ~= "table" then
		warn(self.Character.Name, "has no Config/Dialogue/Priorities; every line plays at", TypeDialogueFrame.DefaultPriority)
		return
	end

	for category in pairs(self.Data) do
		if category ~= CONVERSATIONS and priorities[category] == nil then
			warn(self.Character.Name, "line category", category, "has no priority; it plays at", TypeDialogueFrame.DefaultPriority)
			self.warnedCategories[category] = true
		end
	end
	for category in pairs(priorities) do
		if self.Data[category] == nil then
			warn(self.Character.Name, "has a dialogue priority for", category, "but no line category of that name")
		end
	end
end

function Dialogue:GetData()
	return self.Data
end

function Dialogue:GetLines(categoryName: string)
	local category = self.Data[categoryName]
	if categoryName == CONVERSATIONS then
		return nil
	end

	return category
end

function Dialogue:GetConversation(categoryName: string, conversationName: string)
	local category = self.Data[categoryName]
	return categoryName == CONVERSATIONS and category and category[conversationName] or nil
end

function Dialogue:GetFrame(): TypeDialogueFrame.Frame?
	return self.Frame
end

-- The priority of a line category, read from the config each time so a change applies at once. A missing or unknown value
-- is the default priority.
function Dialogue:GetPriority(category: string): Priority
	local value = self.Configuration:Get({ TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.PrioritiesFolder, category })
	if type(value) == "string" and PriorityRanks[value] then
		return value :: Priority
	end

	if value ~= nil and not self.warnedCategories[category] then
		self.warnedCategories[category] = true
		warn(self.Character.Name, "dialogue priority of", category, "is not a priority:", value)
	end
	return TypeDialogueFrame.DefaultPriority
end

-- Seconds a category waits after one of its lines is said, from Config/Dialogue/Cooldown (read each time so a change
-- applies at once). Missing or not a number: DefaultCooldown. Below 0 counts as 0.
function Dialogue:GetCooldown(category: string): number
	local value: any = self.Configuration:Get({ TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.CooldownFolder, category })
	if typeof(value) ~= "number" or value ~= value then
		return TypeDialogueFrame.DefaultCooldown
	end

	return math.max(value :: number, 0)
end

-- Seconds until the category can be said again, 0 when it can be now
function Dialogue:GetCooldownRemaining(category: string): number
	local lastSaid = self.lastSaid[category]
	if not lastSaid then
		return 0
	end

	return math.max(lastSaid + self:GetCooldown(category) - os.clock(), 0)
end

function Dialogue:IsOnCooldown(category: string): boolean
	return self:GetCooldownRemaining(category) > 0
end

-- Config/Dialogue/Chattiness, clamped to 0..1 and read each time so a change applies at once. A character without one (or
-- with one that isn't a number) always talks.
function Dialogue:GetChattiness(): number
	local value: any = self.Configuration:Get(CHATTINESS_PATH)
	if typeof(value) ~= "number" or value ~= value then
		return 1
	end

	return math.clamp(value :: number, 0, 1)
end

-- True with a chance of the chattiness: 0 never passes, 1 always does
function Dialogue:RollChattiness(): boolean
	return math.random() < self:GetChattiness()
end

-- The sequence that is playing. Once the frame has moved past its lines (finished, cancelled, or replaced by lines queued
-- straight onto the frame) there is none.
function Dialogue:_getActiveSequence(): Sequence?
	local sequence = self.sequence
	local frame = self.Frame
	if not sequence or not frame then
		return nil
	end

	local current = frame:GetCurrentLine()
	if current == nil or not sequence.Ids[current] then
		self.sequence = nil
		return nil
	end

	return sequence
end

-- Whether lines of this priority may play now. Exclusive always may. Anything else may when nothing is playing, when it
-- outranks what is (unless that is Exclusive), or when what is playing is on its last line and has finished typing it.
function Dialogue:CanPlay(priority: Priority): boolean
	if priority == Priorities.Exclusive then
		return true
	end

	local active = self:_getActiveSequence()
	if not active then
		return true
	end
	if active.Priority == Priorities.Exclusive then
		return false
	end
	if PriorityRanks[priority] > PriorityRanks[active.Priority] then
		return true
	end

	local frame = self.Frame :: TypeDialogueFrame.Frame
	return frame:GetCurrentLine() == active.LastId and not frame:IsTyping()
end

-- Plays lines one after the other as one sequence, replacing whatever was playing, if the priority allows it (CanPlay).
-- Returns whether they are playing. This is what SayLine and conversations build on.
function Dialogue:Play(texts: { string }, priority: Priority, options: LineOptions?): boolean
	local frame = self.Frame
	if not frame or frame:IsDestroyed() or #texts == 0 then
		return false
	end
	if not PriorityRanks[priority] then
		warn("Dialogue: unknown priority", priority)
		return false
	end
	if not self:CanPlay(priority) then
		return false
	end

	frame:CancelAll()
	local sequence: Sequence = { Priority = priority, Ids = {}, LastId = 0 }
	for _, text in ipairs(texts) do
		local id = frame:Queue(text, options)
		if id ~= 0 then
			sequence.Ids[id] = true
			sequence.LastId = id
		end
	end

	if sequence.LastId == 0 then
		self.sequence = nil
		return false
	end

	self.sequence = sequence
	return true
end

-- A random line of the category that can be filled with the names given: one with no more %s holders than there are names.
-- The line said last from the category is skipped when there is another to pick.
function Dialogue:_pickLine(category: string, nameCount: number): LineData?
	local candidates = {}
	for _, line in ipairs(self.Data[category]) do
		if type(line.Text) == "string" and line.Text ~= "" and placeholderCount(line.Text) <= nameCount then
			table.insert(candidates, line)
		end
	end

	if #candidates > 1 then
		local last = self.lastPicked[category]
		for index, line in ipairs(candidates) do
			if line.Name == last then
				table.remove(candidates, index)
				break
			end
		end
	end

	local line = candidates[math.random(1, math.max(#candidates, 1))]
	if line then
		self.lastPicked[category] = line.Name
	end
	return line
end

-- Says a random line of the category at the category's priority (Config/Dialogue/Priorities). data.Names fill the line's %s
-- holders in order; with data.RollChattiness it is only said if a Config/Dialogue/Chattiness roll passes. Returns whether
-- the line is playing: false for an unknown category, one with no line that fits the names, Conversations (they go through
-- the conversation system), a category still cooling down (Config/Dialogue/Cooldown; data.IgnoreCooldown skips this), a
-- failed chattiness roll, or a line that something more important is in the way of.
-- A category with a Config/Dialogue/MaxRandomDelay waits a random moment (up to it) before the line is said; true then means
-- it is lined up, and it is still dropped if something more important has started by the time it comes.
-- Reached through Functions (SayLine), so mod scripts can hook or replace what a character says.
function Dialogue:SayLine(category: string, data: SayData?): boolean
	return self:_sayCategory(category, data, nil)
end

-- SayLine, with onPlayed told the sequence once the line actually plays (at once, or after its random delay). Never called
-- for a line that is refused or dropped.
function Dialogue:_sayCategory(category: string, data: SayData?, onPlayed: ((Sequence) -> ())?): boolean
	if type(category) ~= "string" then
		warn("SayLine: category must be a string, got", category)
		return false
	end
	if category == CONVERSATIONS then
		warn("SayLine: Conversations can't be said as a line category")
		return false
	end
	if type(self.Data[category]) ~= "table" then
		warn(self.Character.Name, "has no line category", category)
		return false
	end

	if not (data and data.IgnoreCooldown == true) and self:IsOnCooldown(category) then
		return false
	end
	if data and data.RollChattiness == true and not self:RollChattiness() then
		return false
	end

	local names = if data and type(data.Names) == "table" then data.Names else {}
	local priority = self:GetPriority(category)
	-- Checked before picking, so a refused line doesn't count as the last one said
	if not self:CanPlay(priority) then
		return false
	end

	local delay = self:RollDelay(category)
	if delay <= 0 then
		return self:_say(category, names, priority, data, onPlayed)
	end

	-- Said a moment from now. The cooldown is taken at once, so the category can't be lined up twice meanwhile; if the line
	-- can't be said when its moment comes (something more important started), the cooldown is given back.
	local previousSaid = self.lastSaid[category]
	self.lastSaid[category] = os.clock()

	local thread: thread
	thread = task.delay(delay, function()
		self.pendingLines[thread] = nil
		if not self.Frame then
			return
		end

		if not self:CanPlay(priority) or not self:_say(category, names, priority, data, onPlayed) then
			self.lastSaid[category] = previousSaid
		end
	end)
	self.pendingLines[thread] = true

	return true
end

-- Picks a line that fits the names and plays it. Only a line that is actually said starts the cooldown.
function Dialogue:_say(
	category: string,
	names: { string },
	priority: Priority,
	data: SayData?,
	onPlayed: ((Sequence) -> ())?
): boolean
	local line = self:_pickLine(category, #names)
	if not line then
		return false
	end

	local said = self:Play({ fillNames(line.Text, names) }, priority, data and data.Options)
	if said then
		self.lastSaid[category] = os.clock()
		local sequence = self.sequence
		if onPlayed and sequence then
			onPlayed(sequence)
		end
	end
	return said
end

-- Calls back once the sequence's last line has been typed out (true), or as soon as it stops being what is playing before
-- that, cut short or replaced (false). Checked every frame; never yields the caller.
function Dialogue:_whenTyped(sequence: Sequence, callback: (typed: boolean) -> ())
	local frame = self.Frame
	if not frame then
		callback(false)
		return
	end

	task.spawn(function()
		while true do
			if frame:IsDestroyed() or frame:GetCurrentLine() ~= sequence.LastId then
				-- an earlier line of the sequence is still on: keep waiting; anything else means it is over
				if not frame:IsDestroyed() and sequence.Ids[frame:GetCurrentLine() :: any] then
					task.wait()
					continue
				end
				callback(false)
				return
			end
			if not frame:IsTyping() then
				callback(true)
				return
			end
			task.wait()
		end
	end)
end

-- Starts a bit of banter at the target after one of our attacks: rolls for chattiness, says a CombatBanterStart line, and once
-- it has been typed out asks the target (through the API) to answer with one of its own (BanterRespond). The target may well
-- not answer (not a ModNPC, cooling down, busy with something more important), which is fine. Returns whether our line is
-- playing (or lined up). Reached through Functions (StartBanter).
function Dialogue:StartBanter(target: Model?): boolean
	return self:_startExchange(BANTER_START, { RollChattiness = true }, target, function(api, other)
		api:RequestBanterResponse(other)
	end)
end

-- Says a line of the start category, and once it has been typed out lets request ask the target to answer. The shape of
-- every "say X, then let someone answer" exchange. Returns whether our line is playing (or lined up).
function Dialogue:_startExchange(
	startCategory: string,
	data: SayData?,
	target: Model?,
	request: (api: any, target: Model) -> ()
): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target == self.Character then
		return false
	end

	return self:_sayCategory(startCategory, data, function(sequence)
		self:_whenTyped(sequence, function(typed)
			if typed and self.CharacterAPI and target.Parent then
				request(self.CharacterAPI, target)
			end
		end)
	end)
end

-- We just made a friend (we asked, they accepted; Friends dispatches FriendAdded with Initiated): greets them with a
-- SpotFriendStart line (their name fills a %s), and once it has been typed out asks them to answer with a SpotFriendResponse
-- of their own. No chattiness roll: meeting a new friend is worth a word. The friend may well not answer (not a ModNPC,
-- cooling down, busy with something more important), which is fine. Returns whether our line is playing (or lined up).
-- Reached through Functions (StartFriendGreeting).
function Dialogue:StartFriendGreeting(friend: Model?): boolean
	local names = if typeof(friend) == "Instance" then { friend.Name } else nil
	return self:_startExchange(FRIEND_START, { Names = names }, friend, function(api, other)
		api:RequestFriendResponse(other)
	end)
end

-- A new friend greeted us (StartFriendGreeting, through the API): answer with a SpotFriendResponse line, under the usual
-- rules, so a reply on cooldown or under something more important just doesn't happen. starter fills a %s.
-- Reached through Functions (FriendRespond), which is what the API calls on us.
function Dialogue:FriendRespond(starter: Model?): boolean
	local names = if typeof(starter) == "Instance" then { starter.Name } else nil
	return self:SayLine(FRIEND_RESPOND, { Names = names })
end

-- We are the first of our team to spot the target, or on our own: a line under the usual rules. SpotEnemyTeamed when we
-- are on a team with a teammate in range to hear it; SpotEnemyIndividual otherwise (no team, or nobody around). After a
-- teamed line has been typed out, an EnemySpottedByAlly stimulant tells those teammates, so one who sees it too can
-- answer. Returns whether our line is playing (or lined up). Reached through Functions (CallOutTarget).
function Dialogue:CallOutTarget(target: Model?): boolean
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target == self.Character then
		return false
	end

	local team = self.CharacterAPI:GetTeam()
	local teamed = team ~= nil and team ~= NEUTRAL_TEAM and #self:_getTeammateCharacters() > 0
	if not teamed then
		return self:_sayCategory(SPOT_ENEMY_INDIVIDUAL, nil, nil)
	end

	return self:_sayCategory(SPOT_ENEMY_TEAMED, nil, function(sequence)
		self:_whenTyped(sequence, function(typed)
			if typed and target.Parent then
				self:_tellTeammates(target)
			end
		end)
	end)
end

-- Our teammates in range (Friends, through Functions), as characters
function Dialogue:_getTeammateCharacters(): { Model }
	local teammates = self.Base.Functions:CallFunction(FunctionEnum.GetTeammates)
	local characters = {}
	if type(teammates) == "table" then
		for _, context in teammates do
			table.insert(characters, context.Character)
		end
	end
	return characters
end

-- Sends EnemySpottedByAlly about the target to our teammates in range, if any are still around once our line is typed
function Dialogue:_tellTeammates(target: Model)
	local recipients = self:_getTeammateCharacters()
	if #recipients == 0 then
		return
	end

	local data: TypeStimulant.EnemySpottedByAllyData = {
		Spotter = self.Character,
		Target = target,
	}
	self.Base
		:NewStimulant(TypeStimulant.Names.EnemySpottedByAlly)
		:ToGroup(recipients)
		:Lasting(CALLOUT_LASTING)
		:WithData(data)
		:Send()
end

-- Another character started banter with us (StartBanter, through the API): answer with a CombatBanterRespond line, under
-- the usual rules, so a reply on cooldown or under something more important just doesn't happen. starter fills a %s.
-- Reached through Functions (BanterRespond), which is what the API calls on us.
function Dialogue:BanterRespond(starter: Model?): boolean
	local names = if typeof(starter) == "Instance" then { starter.Name } else nil
	return self:SayLine(BANTER_RESPOND, { Names = names })
end

-- The longest a line of the category may wait before it is said (Config/Dialogue/MaxRandomDelay, read each time). Missing,
-- not a number or not finite: 0. Below 0 counts as 0.
function Dialogue:GetMaxRandomDelay(category: string): number
	local value: any =
		self.Configuration:Get({ TypeDialogueFrame.ConfigFolder, TypeDialogueFrame.MaxRandomDelayFolder, category })
	if typeof(value) ~= "number" or value ~= value or value >= math.huge then
		return 0
	end

	return math.max(value :: number, 0)
end

-- Seconds to wait before saying a line of the category: somewhere between 0 and its MaxRandomDelay
function Dialogue:RollDelay(category: string): number
	local maxDelay = self:GetMaxRandomDelay(category)
	return if maxDelay > 0 then math.random() * maxDelay else 0
end

-- Drops the lines that are waiting out their delay
function Dialogue:_cancelPending()
	for thread in self.pendingLines do
		task.cancel(thread)
	end
	table.clear(self.pendingLines)
end

-- Queues a line straight onto the frame, behind what is waiting, with no priority. Returns its number, which cancels it.
-- 0 when the line was refused or the character has no frame. Prefer SayLine, which respects priorities.
function Dialogue:Queue(text: string, options: LineOptions?): number
	local frame = self.Frame
	if not frame or frame:IsDestroyed() then
		return 0
	end

	return frame:Queue(text, options)
end

-- Cancels the queued or running line with this number; false if there is none
function Dialogue:Cancel(id: number): boolean
	local frame = self.Frame
	return frame ~= nil and frame:Cancel(id)
end

-- Cancels the running line, so the next queued one starts
function Dialogue:CancelCurrent(): boolean
	local frame = self.Frame
	return frame ~= nil and frame:CancelCurrent()
end

-- Cancels the running line, everything queued, and the lines still waiting out their delay
function Dialogue:CancelAll()
	self:_cancelPending()
	self.sequence = nil
	local frame = self.Frame
	if frame then
		frame:CancelAll()
	end
end

function Dialogue:IsSpeaking(): boolean
	local frame = self.Frame
	return frame ~= nil and frame:IsSpeaking()
end

function Dialogue:Destroy()
	for _, subscription in ipairs(self.Subscriptions) do
		subscription.Unsubscribe()
	end
	self.Subscriptions = {}

	self:_cancelPending()

	-- (the gui goes with the character anyway, this is for a module that is destroyed while the character lives)
	local frame = self.Frame
	self.Frame = nil
	self.sequence = nil
	if frame and not frame:IsDestroyed() then
		frame:Destroy()
	end

	self.Data = {}
	self.Configuration = nil
	self.CharacterAPI = nil
	self.Base = nil
end

return Dialogue
