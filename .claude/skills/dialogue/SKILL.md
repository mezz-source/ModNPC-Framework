---
name: dialogue
description: Use when adding or changing ModNPC barks and dialogue - the DialogueBark task and its BARKS table, SayLine, line categories (Lines/<Category>), Config/Dialogue (Priorities, Cooldown, MaxRandomDelay, Chattiness, TalkSpeed, TextColor), the dialogue frame (Queue/Cancel/CancelAll), priorities and Exclusive lines, or when a character should say something in reaction to an event. Use this whenever the user mentions barks, lines, dialogue categories, hooking an event to a line, or making an NPC talk, even if they don't say "bark".
---

# Dialogue and barks

A **bark** is a line an NPC says in reaction to a character event. The pipeline:

```
character event -> DialogueBark task (BARKS table) -> Functions SayLine -> Dialogue:SayLine -> frame (queue, typing)
```

| Piece | Where |
| --- | --- |
| Bark task (events -> categories) | `Behavior/v1/Base/CharacterTasks/DialogueBark.luau` (`BARKS` table) |
| Base module (priority, cooldown, chattiness, delay, picking) | `Behavior/v1/Base/Dialogue.luau` |
| Function bridge | `FunctionEnum.SayLine` -> `Dialogue:SayLine(category, SayData?)` |
| Frame API (gui, queue, cancel) | `API/v1/Modules/Dialogue/` (`init`, `Frame`, `Presenter`, `Board`), types in `Types/v1/TypeDialogueFrame.luau` |
| Config/line constants | `TypeDialogueFrame` (folder names, `Priorities`, `PriorityRanks`, defaults) |

The bark task is an essential start task (`StartTasks/DialogueBark`, category `Dialogue`, no resources). It dies with the
character (`CancelEssentials`).

## Adding a bark

1. **Find (or add) the event.** The bark listens to a character event (`TypeCharacterEvents.Names`). If nothing dispatches what
   you need, add it: payload type + name in `TypeCharacterEvents`, a `Dispatch` where the thing happens (see the `events`
   skill). Dispatch *after* the state is applied, so listeners see the new state. Existing ones used by barks: `Combat.*`
   (AttackLanded, Launched, LaunchEnded, DamageTaken, DefenseSucceeded, BlockBroken), `Stamina.ExhaustionStarted/Ended`,
   `Wander.NewPosition`, `Humanoid.Died`, `Targetting.NewFocusTarget`, `Stimulant.Pending` (Died -> CombatEndVictory).
2. **Add the entry to `BARKS`.** Key is the event name; the handler gets `(self, payload)` and returns
   `category, SayData?`, or `nil` to stay quiet:

   ```luau
   [EventNames.Stamina.ExhaustionStarted] = function()
   	return "StaminaExhausted", nil
   end,
   [EventNames.Wander.NewPosition] = function()
   	return "Idle", { RollChattiness = true }
   end,
   ```

   Filter inside the handler (return `nil, nil`) when only some payloads should bark: e.g. only `Dodged` defenses, only
   `Recovered` launches.

   **Reacting to other characters (stimulants).** Hook `EventNames.Stimulant.Pending` (payload: the queued stimulants, most
   urgent first). Pending is re-dispatched on *every* reaction tick while a stimulant is queued, so remember the ids you
   handled (`self:_isNewDeath` keeps them until `ExpiresAt`) or the bark repeats. Only read them: never `ConsumeStimulant`
   from a bark, other systems react to the same stimulant. Example: `Died` (broadcast to everyone) whose `Source` is
   `self.lastFocus` barks `CombatEndVictory`. `lastFocus` is tracked by the task itself (`_trackFocus`) and kept after the
   focus is lost, because a dead target is usually dropped from targetting before its Died stimulant is read. Anything that isn't one event -> one category can use `self:Listen(eventName, fn)` and
   `self:Bark(category, data)` from a task method instead.
3. **Make sure the category is in the config** (below). Then type-check and playtest.

Never call `Dialogue` directly from another module or task: use `Functions:CallFunction(FunctionEnum.SayLine, category, data)`
so mods can hook or replace it (see the `functions` skill). The bark task does this for you through `self:Bark`.

## Banter (a line that asks another character to answer)

After any of our attacks that swung (`Combat.AttackEnded`), the bark task calls `FunctionEnum.StartBanter(target)` ->
`Dialogue:StartBanter`: a `CombatBanterStart` line with `RollChattiness`, and once **that exact line has been typed out**
(`_whenTyped` follows its line id; it gives up if the line is cut short or replaced) it calls
`CharacterAPI:RequestBanterResponse(target)`. The API endpoint `Dialogue.requestBanterResponse(starter, target)` calls the
target's `BanterRespond` function through its bind (`CharacterUtility.sendFunction`), which says a `CombatBanterRespond` line
under the target's own rules (cooldown, priority; no chattiness roll). A refusal, a non-ModNPC or a gone target is a
**successful request with Data = false**, never a warning: banter is optional. Only malformed requests fail.

The pattern for any "say X, then let someone answer" exchange: `_sayCategory(category, data, onPlayed)` reports the sequence
when the line actually plays (after its random delay), and `_whenTyped(sequence, callback)` tells you when it was typed. Keep
cross-character calls in a narrow API endpoint like `requestBanterResponse`, not a generic "call any function on any NPC".

## SayData (second argument of SayLine)

| Field | Meaning |
| --- | --- |
| `Names = { "Bob" }` | Fills the line's `%s` holders in order. Names are escaped so they can't open markup tags. With no names, only lines without `%s` are picked. |
| `Options = { Color?, TalkSpeed?, HoldTime? }` | Per-line overrides (talk speed is seconds per letter) |
| `RollChattiness = true` | Opt-in: rolls against `Config/Dialogue/Chattiness` first. Use for nonessential lines (idle chatter, banter). Off by default. |
| `IgnoreCooldown = true` | Says the line even while its category cools down (still restarts the cooldown). Death uses it. |

`SayLine` returns whether the line is playing. Never `Conversations` (refused: conversations are their own system), and
unknown categories warn and return false. For a category with a `MaxRandomDelay`, `true` means the line is *lined up*.

## Order of checks (cheap and deterministic first)

1. category exists, isn't `Conversations`
2. cooldown (`Config/Dialogue/Cooldown/<Category>`, skipped by `IgnoreCooldown`)
3. chattiness roll (only with `RollChattiness`)
4. priority (`CanPlay`)
5. a random line that fits the names (no immediate repeat)
6. random delay (`MaxRandomDelay`): the cooldown is reserved at once, priority is re-checked when the delay ends, and the
   cooldown is given back if the line is dropped
7. `Play`: cancels what was playing and queues the line as one sequence

A refused line never starts a cooldown or counts as "last said". `CancelAll` (also on death) drops lines waiting out their
delay.

## Priorities

`Config/Dialogue/Priorities/<Category>` is a StringValue: `Low`, `Medium`, `High`, `VeryHigh`, `Exclusive` (missing or
invalid -> `Low`, with a warning at load).

- Anything but Exclusive plays if nothing is playing, if it **strictly outranks** what is playing, or if the running sequence is
  on its last line and has **finished typing** (it is only holding/fading, so there's room to squeeze in).
- Equal priority does not interrupt a line that is still typing.
- **Exclusive** always plays, cancelling everything including another Exclusive; nothing but Exclusive can cut into it
  (not even after it finishes typing). Used for Death and Conversations.

## Config every category needs

Every category folder under the character's `Lines` needs an entry in **each** of these folders of `Config/Dialogue`
(the config schema `ServerScriptService.ModAssets._v1_MODNPC_CONFIG` is Studio-only, and a character missing an entry the
schema lists fails validation at start):

| Folder | Value | Notes |
| --- | --- | --- |
| `Priorities` | StringValue | see above |
| `Cooldown` | NumberValue | seconds before the category can be said again (3 if a category isn't listed) |
| `MaxRandomDelay` | NumberValue | up to this many seconds are rolled and waited before the line is said (0 = none) |

Plus single values: `TalkSpeed` (NumberValue, seconds per letter), `Chattiness` (0..1, a character without it always
talks), `TextColor` (Color3Value, default letter color). All of these are read live, so edits apply immediately.
Lines themselves are `Dialog` instances (`InitialPrompt` is the text) in `Lines/<Category>/`, one string with markup
(`docs/Dialogue Markup.md`), `%s` for a name. Add new categories to the schema, the template NPC and the user's NPCs; ask the
user before editing their NPCs' folders, and never edit `ServerStorage.CLAUDE_MODNPC` (clone it).

## The frame (when you need to talk without a category)

`base.Dialogue` wraps the frame (`CharacterAPI:CreateDialogueFrame`; the gui lives in the Head, or in the model without one).
`Dialogue:Queue(text, options)` adds a line with no priority and returns its id; `Cancel(id)`, `CancelCurrent()`,
`CancelAll()`, `IsSpeaking()`. `Dialogue:Play(texts, priority, options)` plays several lines as one sequence at a priority
(this is what a conversation system should use at `Exclusive`). Lines run one at a time: typed, held (5s), faded, then the
next. The frame ends itself with its gui; `Dialogue:Destroy()` removes it.

## Testing

Use a temp Script (see the `start-npcs` skill), clone `CLAUDE_MODNPC`, and since the template lacks newer config, copy
`Config/Dialogue` and `Lines` from `workspace.modnpc.ModNPC` onto the clone before `API.startCharacter`. Wrap
`base.Dialogue.SayLine` to log `category + (ok and "+" or "-")`, trigger the events (or dispatch them with
`base.Events:Dispatch(name, payload)`), and read the log from the console. To exercise real triggers use two clones that fight,
`DealDamage(target, 1, "Blunt", "Launch")` for specials, `Humanoid.Health = 0` for death. Remember cooldowns: set the
category's Cooldown value to 0 when you need repeated lines. Stop play and delete the temp Script afterwards.

Quirks seen: a Launch special on a character with Vitality becomes StaggerBackwards (it barks CombatRecieveCrit, not
CombatLaunched); sounds with a bad asset id log "Asset type does not match requested type" and are harmless to tests.
