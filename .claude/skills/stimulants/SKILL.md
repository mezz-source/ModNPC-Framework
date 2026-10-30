---
name: stimulants
description: Use when sending, receiving, consuming, or adding ModNPC stimulants - things one character does that other characters may react to (IncomingAttack, SprintingTowards, BlockBroken...). Covers CharacterDiscovery, the Stimulants API module (emit/retract, recipient types, priorities), base:NewStimulant / StimulantBuilder, the character-side queue (Base.Stimulants, StimulantsPending, Get/Peek/ConsumeStimulant), and AnimationHandle marker timing used for expiries. Use this whenever the user mentions stimulants, stims, perception, "letting the target know", or wants an NPC to react to what another NPC is doing, even if they don't say "stimulant".
---

# Stimulants

A stimulant is something one character does that another character may react to:
a windup coming at it, someone sprinting at it, its attacker's guard breaking.
Unlike events and functions, a stimulant is **not handled when it arrives**. The
receiver queues it, and its thought process decides on its reaction ticks what to do
with whatever is still pending. Stimulants expire (absolute `os.clock()` time), can
be retracted by their sender, and are consumed by whoever acts on them.

The API decides who hears a stimulant (targeted delivery), so a character never
sorts through noise that isn't about it.

## Pipeline

```
sender (task/module)                          API                                   receiver
base:NewStimulant(...)          Stimulants.emit / retract               CharacterStimulant bind
  :To(..):Lasting(..)   ──►     resolves the recipient       ──►       CharacterAPI:_stimulantRecieved
  :Send() / :Emit()             against its receiver registry            ──► Functions ReceiveStimulant / DropStimulant
                                (fed by CharacterDiscovery)              ──► Base.Stimulants queue
                                                                         ──► each ReactionUpdate: Stimulant.Pending
                                                                         ──► a consumer: ConsumeStimulant(id)
```

| Piece | Where |
| --- | --- |
| Discovery (which characters exist) | `API/v1/Modules/CharacterDiscovery.luau` |
| Routing, registry, active ids | `API/v1/Modules/Stimulants.luau` (`emit`, `retract`) |
| Low-level bind senders | `CharacterUtility.sendStimulant`, `sendStimulantRetraction`, `createStimulant`, `_getStimulantBind` |
| Types, names, enums | `Types/v1/TypeStimulant.luau` |
| Builder | `Behavior/v1/Base/StimulantBuilder.luau`, reached as `base:NewStimulant(name)` |
| Sending wrappers | `CharacterAPI:SendStimulant / EmitStimulant / RetractStimulant` |
| Receiving queue | `Behavior/v1/Base/Stimulants.luau` (`Base.Stimulants`) |
| Marker timing | `Base/Animation/MarkerTimes.luau` + `AnimationHandle:GetTimeUntilMarker` etc. |

## Sending one (the common case)

```luau
-- fire and forget: for stimulants that just run out
self.Base:NewStimulant(TypeStimulant.Names.SprintingTowards)
    :To(target)                          -- or :ToGroup({ a, b }) / :ToAll()
    :WithPriority(TypeStimulant.Priorities.Low)  -- Low | Normal (default) | High | Critical
    :Lasting(1)                          -- seconds from Build; or :ExpiringAt(os.clock() + 1)
    :At(position)                        -- optional
    :WithData({ Distance = distance })   -- optional, plain data + instances only
    :Send()                              -- (ok, err)

-- retractable: when it may stop being true early (an interruptible windup)
local result = self.Base:NewStimulant(...):To(target):Lasting(t):Emit()  -- (EmitResult?, err)
self.StimulantId = if result and result.Delivered > 0 then result.Id else nil
-- later, when it resolves or is cut short:
self.CharacterAPI:RetractStimulant(id)   -- safe on an expired/unknown id (returns false, no warn)
```

- A name, a recipient and an expiry are required. `Build`/`Send`/`Emit` never throw:
  they return the reason. The API validates again on emit.
- **Send vs Emit.** `Send` uses a NoResponse request (nothing waited for, the API only
  warns on refusal). `Emit` waits and gives `{ Id, Delivered }`. Use Emit only when
  you'll retract. Skip storing the id when `Delivered == 0` (the target was a player
  or a plain humanoid), since there is nothing to retract.
- **Retract whenever the thing stops being true**: the hit resolved, the attack was
  cancelled, the task cleaned up. Do it in the task's `_cleanup` as well, so every exit
  path is covered. The API also auto-retracts everything an emitter had active once it
  is removed (dies or is destroyed).
- The sender is never a recipient. Unloaded NPCs (`_UNLOADED`) and dead ones are
  skipped. Only ModNPCs receive for now, through `buildReceiver` in the API module,
  which is also where adapters for other NPC systems will plug in.
- Tasks have `self.Base`, so `self.Base:NewStimulant` works from any task. Mod scripts
  get `base` in `init`.

### Timing an expiry to an animation

Hits land on **animation markers**. `AnimationTrack:GetTimeOfKeyframe` does NOT find
markers (only named keyframes, and errors "Could not find a keyframe by that name").
Marker times come from `KeyframeSequenceProvider:GetKeyframeSequenceAsync`, read once
per animation in the background (`MarkerTimes.Preload`, called by `AnimationHandle.new`)
and cached server-wide. Ask the handle after the animation is playing and its speed
is set:

```luau
local lasting = handle:GetTimeUntilMarker(hit.EventName)  -- real seconds at the current speed
    or handle:GetTimeRemaining()                          -- fallback: the rest of the animation
```

`GetMarkerTime` (animation seconds), `GetTimeUntil(time)`, `GetLength` are there too.
All are non-yielding, and nil means "not known / won't be reached". Always have a fallback.

## Adding a new stimulant

1. Add its name to `TypeStimulant.Names` with a comment: who sends it, to whom, how
   long it lasts, what `Data` holds. Add a `...Data` export type if it carries data
   (`SprintingTowardsData`; attack hits use `TypeAttack.HitStimulantContext`).
2. Send it from the module or task that knows it is happening, with `base:NewStimulant`.
   Keep data to what a receiver needs to **decide**, not cosmetics (sounds, VFX, forces).
3. Pick the priority by how much it should win attention. Low ones may expire unread.
4. If it can stop being true early, use `Emit` and retract it, with cleanup on every path.

Existing ones:

| Name | Sender | To | Priority | Lasts | Data |
| --- | --- | --- | --- | --- | --- |
| `IncomingAttack` | Attack task, per hit (first once paid, the next as the previous lands) | the target | High | until the hit's marker; retracted if the attack is cut short | `HitStimulantContext` |
| `SprintingTowards` | ChaseTargets, when a sprint starts | the focus target | Low | 1s | `SprintingTowardsData` |
| `BlockBroken` | Block task, when a hit breaks the guard | the attacker | High | the break animation (0.5s fallback) | none |
| `Exhausted` | Stamina, as the character becomes exhausted | the focus target of its targetting task | Normal | 2s | `ExhaustedData` (Efficiency) |

"Our target" is the focus target of the task in the Targetting category
(`Scheduler:GetTask(Targetting).FocusTarget.Character`), the same one
`Attacks:GetCurrentTarget` reads. The Scheduler is exempt from the Functions rule, so any
module may read it this way.

## Receiving and consuming

`Base.Stimulants` holds the queue. Other modules reach it only through Functions
(see the `functions` skill):

- `ReceiveStimulant(stimulant)` / `DropStimulant(id)` are what the bind calls. Mods
  can `Replace`/`First` them to filter what a character perceives.
- `GetStimulants(name?)` returns a copy, most urgent first (priority rank, then the
  soonest expiry). `PeekStimulant(name?)` returns the most urgent one, still queued.
- `ConsumeStimulant(id)` removes it and returns it, or nil if it already expired or was
  retracted, which tells you not to act.
- Event `TypeCharacterEvents.Names.Stimulant.Pending` (payload: the sorted list) is
  dispatched on every thought `ReactionUpdate` while anything is queued. That is the
  intended place to react: subscribe, pick what you act on, consume it, ignore the rest.

Consumers today:

| Who | What | How |
| --- | --- | --- |
| `Defense` (see the `defense` skill) | `IncomingAttack` | consumes it and decides a dodge / last moment guard |
| `Disposition` | `IncomingAttack`, `BlockBroken`, `Exhausted`, `SprintingTowards` | perceives without consuming: a pulse factor per stimulant (Threatened, TargetOpen, TargetTired, Charged) |

Several subscribers get the same Pending list; whoever subscribed first (Disposition is
built before Defense) sees it first. A consumer that only *reads* must not consume, or it
takes the stimulant from the one that acts on it.

**A receiver never hears a stimulant retracted after it expired.** `Stimulants.retract`
prunes expired records first, and an `IncomingAttack` expires exactly as its hit lands,
so a resolved hit's retraction is a no-op ("already gone") and only a hit cut short early
reaches the receiver as `DropStimulant`. Don't treat retraction as "it resolved"; use the
expiry (Defense waits `ExpiresAt` + 0.2s for Damage's outcome).

Queue rules: the same `Source` + `Name` replaces the older entry (dedupe/refresh). At
most 32 entries; past that the least urgent goes (lowest priority, then the latest
expiry). Malformed or already-expired arrivals are rejected. Pruning is lazy (on
reads). Death clears the queue and stops intake. Nothing reacts on arrival, by design.

## Discovery

`CharacterDiscovery` is the single source of truth for which characters exist
(humanoid scan, validation retry, `Destroying`/`Died`, 1s sweep). It fires
`Added(character, characterType)` / `Removed(character)`. Use
`CharacterDiscovery._observe(onAdded, onRemoved)`, which replays already-tracked
characters, because `Core` inits API modules in arbitrary order. Targetting and
Stimulants both consume it. Change how characters are found **only** here.

## Gotchas

- The bind carries `(messageType, payload)`: `("Stimulant", StimulantEvent)` or
  `("Retract", id)`. A BindableEvent copies the table, so `Source` and other instances
  survive but metatables don't.
- **BindableEvent delivery is deferred.** In tests, `task.wait()` before reading a
  queue right after emitting, or you'll see it empty.
- `os.clock()` is the clock for every expiry. Never send durations across the API.
- Adding a bind to the ModNPC format makes it mandatory: `validateModNPC` checks
  `_internal/_binds/CharacterStimulant`. The template is Studio-only.

## Testing

- Type-check per the global notes.
- Base objects aren't reachable from `execute_luau`. Read a character's queue through its
  `CharacterFunction` bind: `bind:Invoke("GetStimulants", {})` (also `PeekStimulant`,
  `ConsumeStimulant`). Emit through `ServerScriptService.ModFunctions.Request:Invoke(
  { ModuleName = "Stimulants", Function = "emit", Arguments = { emitter, recipient, spec } })`.
- To use `base` (the builder, the Pending event, starting an Attack task on demand), insert
  a temporary ModuleScript `return { init = function(base) task.delay(6, ...) end }` under an
  NPC's `ModNPC.Mods` in Edit mode, write results to an attribute, read it from the Server
  datamodel, then delete the module and the attribute.
- The test NPCs are all Neutral and idle. To exercise an attack, teleport the attacker in
  range (`PivotTo`) and start `base.CharacterTasks.Attack.new(context)` via
  `base.Scheduler:Start`. Use `base.Attacks:GetAttack(name)` and `GetAnimationName`.
- Execute calls are seconds apart: give test stimulants long lifetimes (30s), or do the
  whole test in one script.
