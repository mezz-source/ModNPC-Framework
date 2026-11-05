local ServerScriptService = game:GetService("ServerScriptService")
local TypeCDN = require(ServerScriptService.ModNPCServer.Types.v1.TypeCDN)

local TypeDialogueFrame = {}

-- Name of the BillboardGui under ServerScriptService.ModAssets, and of the copy placed in each character
TypeDialogueFrame.GuiName = "DialogueUI"

-- Where a character's TalkBlip sound is found in its assets (Assets/Sounds/Individual) and where its default talk speed
-- is in its config (Config/Dialogue/TalkSpeed)
TypeDialogueFrame.TalkSoundName = "TalkBlip"
TypeDialogueFrame.ConfigFolder = "Dialogue"
TypeDialogueFrame.TalkSpeedSetting = "TalkSpeed"
-- Config/Dialogue/TextColor (a Color3Value): the default letter color of the character's frame
TypeDialogueFrame.TextColorSetting = "TextColor"
-- Config/Dialogue/Priorities: one StringValue per line category, named after it, holding a Priority
TypeDialogueFrame.PrioritiesFolder = "Priorities"
-- Config/Dialogue/Cooldown: one NumberValue per line category, named after it: the seconds after a line of the category is
-- said before another can be. A category without one waits DefaultCooldown.
TypeDialogueFrame.CooldownFolder = "Cooldown"
TypeDialogueFrame.DefaultCooldown = 3
-- Config/Dialogue/MaxRandomDelay: one NumberValue per line category: a line of it waits a random 0 to this many seconds before
-- it is said, so characters don't all speak on the exact frame something happens. A category without one (or 0) waits none.
TypeDialogueFrame.MaxRandomDelayFolder = "MaxRandomDelay"
-- Config/Dialogue/Chattiness: the chance (0 to 1) that a line said with RollChattiness is said at all
TypeDialogueFrame.ChattinessSetting = "Chattiness"
-- The category of Lines that holds conversations, which are played by the conversation system, never by SayLine
TypeDialogueFrame.ConversationsCategory = "Conversations"

export type Priority = "Low" | "Medium" | "High" | "VeryHigh" | "Exclusive"

-- How important a line is. A line only cuts in on one that is still typing if it is strictly more important; once the
-- running line has finished typing (and nothing more of its sequence is queued) anything but an Exclusive one may replace
-- it. Exclusive is above everything: it cancels whatever is playing, another Exclusive included, and nothing but another
-- Exclusive can cut in on it.
TypeDialogueFrame.Priorities = table.freeze({
	Low = "Low" :: "Low",
	Medium = "Medium" :: "Medium",
	High = "High" :: "High",
	VeryHigh = "VeryHigh" :: "VeryHigh",
	Exclusive = "Exclusive" :: "Exclusive",
})

TypeDialogueFrame.PriorityRanks = table.freeze({
	Low = 1,
	Medium = 2,
	High = 3,
	VeryHigh = 4,
	Exclusive = 5,
} :: { [string]: number })

-- What a category with no (or no valid) priority in the config plays at
TypeDialogueFrame.DefaultPriority = "Low" :: Priority

-- What SayLine can be given along with the category
export type SayData = {
	-- Fill the line's %s holders, in order (a target's name...). With none given, only lines without %s are picked.
	Names: { string }?,
	-- Overrides for the line (color, talk speed, hold time)
	Options: LineOptions?,
	-- Rolls against Config/Dialogue/Chattiness first, and says nothing if the roll fails. For lines that don't matter (banter,
	-- idle chatter). Off by default, so a line is never skipped unless asked.
	RollChattiness: boolean?,
	-- Says the line even while its category is cooling down (the cooldown still restarts once it is said)
	IgnoreCooldown: boolean?,
}

-- What a frame starts with. Everything can be changed later with the frame's setters.
export type FrameOptions = {
	-- The color of letters whose markup names none. Defaults to the color of the gui's letter template.
	Color: Color3?,
	-- Played (restarted) as letters are typed. Nothing is played when nil.
	TalkSound: TypeCDN.SoundData?,
	-- Seconds each letter takes to type, before <speed> tags (Config/Dialogue/TalkSpeed). Defaults to 1/30.
	TalkSpeed: number?,
	-- Every markup event but <pause> (<sfx>, <event>, <anim>, <stopanim>) as it fires. Runs in its own thread.
	OnEvent: ((event: { Kind: string, Arg: string?, Number: number? }) -> ())?,
}

-- Overrides for one line; anything left out takes the frame's setting
export type LineOptions = {
	Color: Color3?,
	-- Seconds per letter
	TalkSpeed: number?,
	-- Seconds the finished line stays before it fades out (5 by default)
	HoldTime: number?,
}

-- A frame is a plain table of closures rather than a metatable class: the API hands it back through a BindableFunction,
-- which copies tables and strips metatables. Methods are still called with a colon, and every copy drives the same frame.
-- Once the frame is destroyed every method is a no-op.
--
-- Lines run one at a time, in the order they were queued. A line is typed, held, faded out, and only then does the next one
-- start. Lines are numbered, and the number is how a queued or running line is cancelled.
export type Frame = {
	-- Adds the text (one string with its markup) to the end of the queue and returns its number, 0 if it was refused.
	-- Starts at once when nothing else is running.
	Queue: (self: Frame, text: string, options: LineOptions?) -> number,
	-- Cancels a queued line, or the running one (which clears the board and starts the next). False if there is no such line.
	Cancel: (self: Frame, id: number) -> boolean,
	-- Cancels the running line only, so the next queued one starts. False if nothing was running.
	CancelCurrent: (self: Frame) -> boolean,
	-- Cancels the running line and everything queued
	CancelAll: (self: Frame) -> (),
	-- True while a line is running, from the moment it starts until it has faded out or been cancelled
	IsSpeaking: (self: Frame) -> boolean,
	-- True while the running line still has letters to type; false once it is only holding or fading out
	IsTyping: (self: Frame) -> boolean,
	-- The number of the running line
	GetCurrentLine: (self: Frame) -> number?,
	-- Lines waiting behind the running one
	GetQueueLength: (self: Frame) -> number,
	SetColor: (self: Frame, color: Color3) -> (),
	GetColor: (self: Frame) -> Color3,
	SetTalkSpeed: (self: Frame, secondsPerLetter: number) -> (),
	GetTalkSpeed: (self: Frame) -> number,
	-- nil goes silent
	SetTalkSound: (self: Frame, talkSound: TypeCDN.SoundData?) -> (),
	IsDestroyed: (self: Frame) -> boolean,
	-- Cancels everything and removes the gui
	Destroy: (self: Frame) -> (),
}

return TypeDialogueFrame
