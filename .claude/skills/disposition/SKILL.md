---
name: disposition
description: Use when adding, changing, tuning, or consuming the ModNPC disposition and its weights - Disposition.luau, axes (Aggression, Evasiveness, Guard, Tempo, Commitment), factors (Injury, Stamina, Exhaustion, TargetWeak, ...), Importance, Config/Disposition, the combat events that feed it, or anything that should behave differently depending on how aggressive, guarded or tired a character feels (engage distance, strafing, raising the guard, attack choice). Use this whenever the user talks about weights, temperament, aggression, or "how the NPC decides to fight", even if they don't say "disposition".
---

# Disposition (the weights system)

A character's disposition is a few **axes** (0-1) describing how it feels about the
fight, leaned by **factors** that each measure one thing about the fight. Behavior
code never decides "if hurt then back off"; it reads an axis, and what a character
*values* is only configuration.

Sources of truth: `Behavior/v1/Base/Disposition.luau` (the module),
`Types/v1/TypeDisposition.luau` (axis/factor/settings names), the combat events in
`Types/v1/TypeCharacterEvents.luau` (`Names.Combat`, `Names.Stamina`), and the
character's `Config/Disposition` folder.

## The model

```
lean(axis)   = sum over factors of  Importance * signal * effect(factor, axis)
target(axis) = saturate(baseline(axis), lean)    -- baseline + room * (1 - e^(-|lean| / room)) toward 0 or 1
axis         = axis eased toward target every reaction tick (AXIS_SMOOTH_TIME 0.75s)
```

`saturate` (room = 1 - baseline when leaning up, baseline when leaning down) moves the
axis by about the lean when it is small and less and less as it grows, so it nears 0
or 1 without pinning there. It replaced a hard clamp, under which a couple of agreeing
factors pinned an axis and a factor leaning the other way had no effect at all (a
defensive template averaged Aggression 0.81 against a 0.2 baseline). A character with
a baseline of 0.9 still lives near 1, that is its configuration, not the curve.

- **Axes** (what consumers read): `Aggression`, `Evasiveness`, `Guard`, `Tempo`,
  `Commitment`. Few on purpose; add one only when something will read it.
- **Factor signal** (0-1): how strong the factor is right now. Three kinds:
  - *state*, read each tick from something that already exists (Injury from the
    humanoid, Stamina through `GetStamina`, Exhaustion from `ExhaustionState`,
    TargetWeak from `CharacterAPI:GetHealthInfo` of the focus target);
  - *decaying count*, fed by events and halved every half life (FailedAttacks,
    Momentum, Pressure) so a bad fight is forgotten;
  - *pulse / timer* (Opening lasts 2.5s after a successful defense; Stalemate builds
    only while `EngageState` is Engaged and nothing has been exchanged for 4s);
  - *stimulant pulse*: what other characters tell us (see the `stimulants` skill).
    `STIMULANT_FACTORS` maps a stimulant name to a factor, a hold and a strength
    function. `_perceive` (on `Stimulant.Pending`) starts the pulse at the stimulant's
    strength the first tick it is seen (each id counts once, a stronger repeat
    restarts it) and it fades linearly over its hold. Disposition **never consumes**
    stimulants: a mood is no reason to take one from whoever acts on it (Defense
    consumes IncomingAttack in the same Pending dispatch).
- **Effect** (-1..1): how hard the factor leans an axis at full strength. Code
  defaults live in `DEFAULT_EFFECTS`; a character overrides one with a NumberValue
  named after the axis inside its factor folder.
- **Importance**: multiplies everything a factor does (default 1, 0 turns it off,
  negative reverses it, above 1 makes it dominate). This is the per-NPC knob.
- **Baseline**: where an axis rests. Aggression and Evasiveness reuse
  `Config/ThoughtProcess/AggressionScale` and `Evasiveness`; Guard, Tempo and
  Commitment live in `Config/Disposition/Baseline/`. Mapped in `AXIS_BASELINES`.

Curves matter: injury-like signals are the missing fraction **squared** (a scratch
barely counts, nearly dead counts almost fully). Do the same for new "how much is
gone" signals unless there is a reason not to.

## Current factors

| Factor | Signal | Leans (default effect at full strength) |
| --- | --- | --- |
| Injury | missing own health, squared | Aggression -0.8, Evasiveness +0.6, Guard +0.7, Tempo +0.3, Commitment -0.5 |
| FailedAttacks | count of defended/missed attacks | Aggression +0.5, Evasiveness -0.4, Tempo +0.3, Commitment -0.5 |
| Pressure | damage taken lately / 25% max health | Aggression -0.4, Evasiveness +0.3, Guard +0.8 |
| Momentum | count of landed attacks | Aggression +0.6, Evasiveness -0.2, Tempo +0.4, Commitment +0.5 |
| Stalemate | time engaged with no exchange | Aggression +0.7, Guard -0.3, Tempo +0.3 |
| Opening | pulse after a dodge/block | Aggression +0.8, Evasiveness -0.3, Guard -0.5, Tempo +0.6 |
| Stamina | missing stamina, squared | Aggression -0.3, Guard +0.6, Tempo -0.7, Commitment -0.3 |
| TargetWeak | the most of: focus target's missing health squared, 0.6 while the target is exhausted (`EXHAUSTED_TARGET_WEAKNESS`; was 1, which with template Importances of 2-3 made every NPC all-out aggressive for the third of a fight its opponent spends exhausted), or 1 while staggered (`STAGGERED_TARGET_WEAKNESS`, it can't defend at all; a short burst) | Aggression +0.5, Evasiveness -0.2, Guard -0.4, Tempo +0.5, Commitment +0.4 |
| Exhaustion | 1 while `ExhaustionState` is Exhausted | Aggression -1, Evasiveness +0.5, Guard +0.4, Tempo -1, Commitment -0.8. Guard was +1: an exhausted guard pays full price per hit and lets half through, so holding it kept the character exhausted (47% of a fight); now it circles and keeps away instead |
| Threatened | stimulant pulse: `IncomingAttack`, 0.6/0.8/1 by Light/Medium/Heavy, 1.5s | Aggression -0.2, Evasiveness +0.3, Guard +0.5, Commitment -0.2 |
| TargetOpen | stimulant pulse: `BlockBroken` (we broke their guard), 1, 2s | Aggression +0.8, Evasiveness -0.3, Guard -0.6, Tempo +0.8, Commitment +0.6 |
| TargetTired | stimulant pulse: `Exhausted` from the one fighting us, (1 - Efficiency) / 0.5, 3s | Aggression +0.6, Guard -0.3, Tempo +0.5, Commitment +0.4 |
| Charged | stimulant pulse: `SprintingTowards`, 1 at 10 studs down to 0.3 at 40+, 1.5s | Evasiveness +0.4, Guard +0.6, Commitment -0.3 |

Template Importances for the stimulant factors (balanced / defensive / aggressive):
Threatened 1 / 1.5 / 0.5, TargetOpen 1 / 0.6 / 2, TargetTired 1 / 0.7 / 1.5,
Charged 1 / 1.5 / 0.5. All four are in the schema (default 1).

Not built yet: **Outnumbered** (needs a nearby-hostiles count).

## Reading the disposition (consumers)

Disposition is a behavior module, so everything outside it goes through Functions
(see the `functions` skill): `FunctionEnum.GetDisposition(axis)`,
`GetEngageDistance(targettingRange)`, `GetHoldDistance(targettingRange)`,
`GetAttackStandoff(attack)` and `GetAttackFit(attack, distance)`. Never reach into
`base.Disposition`. Read it on the reaction tick or at the decision point, not every
frame.

What reads each axis today:

- **Aggression** moves the held engage distance by up to 40% either way
  (`ENGAGE_DISTANCE_SPREAD`), via `GetEngageDistance`. It also sets how close to an
  attack's `DesiredRange` the attack is made from (`GetAttackStandoff`: 90% of the
  range when wary, 75% when aggressive, never under 2.5 studs).
- **What `ChaseTargets` and `Engage` hold is `GetHoldDistance`**, not
  `GetEngageDistance`; both ask this one function so they agree on where the handoff
  happens, keep it that way. It is `min(engage distance, standoff of the desired
  attack)`: the attack only pulls the character closer than it likes, never keeps it
  further out. When `CanAttack` is false (swinging, debounce, staggered) or the
  character is resting (see below) the attack is ignored and the character holds its
  own engage distance, which backs it off; the one exception is an attack that
  presses on (`IsPressingOn`), which keeps the standoff through its swing.
  `AttackTargets` makes the attack once the target is within the standoff (the
  decision lives there, not in the movement tasks, and may fire mid-approach).
- **The rhythm of a fight (Tempo + Commitment)**: attacks come in *exchanges*,
  with a rest out of reach between them. `Attacks` listens to `AttackState`: as each
  attack begins it asks `GetAttackPace(chain)` (chain = attacks in the exchange so
  far). `PressOn` has odds `(Commitment * PRESS_ON_SHARE 0.8) ^ chain`; if it does
  not press on, the exchange ends with the attack and `Rest` seconds follow, from
  `REST_SLOWEST 4s` to `REST_FASTEST 1s` by Tempo, x0.5..1.5 by Guard, +-25% jitter.
  `IsReadyToAttack` is false while resting and `AttackTargets` will not launch.
  Without this the character attacks on every reaction tick and nothing else (strafe,
  guard) ever gets a turn.
- **Attack choice** weighs candidates by `GetAttackFit(attack, distance)` in
  `Attacks:PickDesiredAttack`: the reach fit (1 for an attack makeable from where
  the character would settle, halving per 4 studs it would have to walk further in;
  the distance is measured once by the picker, it is a request) times the
  commitment fit (how many of not-AllowMoving, not-AllowInterrupts, IsCombo an
  attack has, as a third each, against Commitment).
- **Evasiveness** is `Engage`'s strafe *rate*: `STRAFE_RATE` 1.5 strafes a second at
  1.0, as odds over the elapsed reaction time. Allowed unless too far (it combines
  with backing off); it was once only inside the band, which starved it.
- **Guard** raises and lowers the Block task in `Engage:UpdateGuard` (raise at
  >= 0.7, lower at <= 0.5, hysteresis; while resting 0.5 / 0.35; only while engaged;
  only if `CanBlock` and `CanAffordStamina(BlockLight)` pass, because starting a
  block takes the arms). While resting `Engage` also only tolerates 40% of
  `TooCloseDiff` (`REST_BAND_SHARE`), so the character backs out of reach.
  The thresholds were 0.6/0.4 and 0.35/0.2 before Defense existed; with hits now met
  as they come (see the `defense` skill) that held guards up ~55% of a fight and
  almost nothing landed. A guard Defense raised at the last moment is adopted by
  Engage (`AdoptGuard`, `BlockTask.Holder = "Engage"`) when its own Guard calls for
  one, instead of a second block being started.
  Guard also leans the odds of Defense's last moment guard (x0.5 at 0, x1.5 at 1).
- **Aggression** also picks a dodge's direction in Defense (side 30% at 0 to 90% at
  1, otherwise back). Sprints to close in (Aggression rate) are skipped below 40% stamina
  (`SPRINT_MIN_STAMINA` in Engage).

A new consumer should take a threshold with hysteresis (two numbers) when the axis
drives an on/off thing, so it does not flap, and should be decided on the reaction
tick (`ThoughtEvents.ReactionUpdate`) so behavior follows the character's reaction
speed.

## Configuration and the schema

```
Config/Disposition/
  Baseline/   Guard, Tempo, Commitment                 (NumberValues, required)
  <Factor>/   Importance                               (NumberValue, required)
              <Axis name>  e.g. Guard = -0.6           (optional override of one effect)
```

- The ModNPC config schema is the Studio instance
  `ServerScriptService.ModAssets._v1_MODNPC_CONFIG`. It is **not** in `src/`
  (Rojo does not sync it), only the sample structure and value *types* are checked,
  and **everything in it is mandatory for every ModNPC** ("Missing configuration
  value: ..." and the character fails to load). So a new factor's `Importance` has to
  be added to the schema and to `workspace.modnpc.ModNPC.Config` together, and only
  with the user's permission (they gave it for disposition weights; ask again for
  anything else). Per-axis effect overrides stay out of the schema; code falls back
  to `DEFAULT_EFFECTS`.
- Reads are live: `Configuration:Get` sees edits made in play mode, so tuning does not
  need a restart.
- Saving the place is the user's job; Studio edits made over MCP only persist if
  they save.

## Adding a factor

1. `TypeDisposition`: add to `Factors` (with a one-line comment) and to the `Factor`
   union type.
2. `Disposition.luau`: add its row to `DEFAULT_EFFECTS` (a comment on why it leans
   what it leans), and its signal in `_measureSignals` (0-1). If it is an
   accumulator or timer, add the fields in `new`, feed them in `Init` from events,
   decay them in `Update`, and put the half life / saturation in the constants block.
3. Anything outside the module that the signal needs comes through Functions or the
   core handlers (`State`, `Configuration`, `Distance`, `CharacterAPI`, `Events`
   are fine). Another character's data comes from `CharacterAPI`, not from its Base.
4. Schema + modnpc: `Config/Disposition/<Factor>/Importance` (see above). Pick the
   modnpc Importance deliberately ("a big weight" = 1.5, not a bigger default effect
   than 1).
5. Event factors need the event first. Producers belong where the outcome is known
   (Damage for what happens to us, the Attack task for what our attacks do); add the
   name and payload type to `TypeCharacterEvents` (see the `events` skill) and
   validate the payload where Disposition reads it, since events can arrive from
   outside the character.
6. Type-check (global notes), then test (below). Update this skill's table.

## Adding an axis

`TypeDisposition.Axes` + `Axis` type, an `AXIS_BASELINES` entry (path + default), a
`Baseline/<Axis>` NumberValue in the schema and modnpc, effects in the rows of the
factors that should lean it, and **a consumer in the same change**. Update the
`TypeBehavior.FunctionCallbacks.GetDisposition` signature (it takes `TypeDisposition.Axis`).

## Testing

You cannot reach `Base` from `execute_luau`, so drive it from a temporary mod script:

1. In Edit mode add a ModuleScript under `workspace.modnpc.ModNPC.Mods` returning
   `{ init = function(base) task.spawn(function() ... end) end }` (it runs inside
   `Base.new` with the live Base). `task.wait(3)` first.
2. Read `base.Disposition:GetAxes()` / `:GetSignals()`, drive inputs with the real
   functions (`SpendStamina`, `BreakStamina`, `base.Damage:ReceiveRegistered`, firing
   `ModNPC/_internal/_binds/CharacterEvent` with an event name and payload to fake
   attack outcomes), write the report to `npc:SetAttribute("T_Result", ...)`, and read
   it with `execute_luau` (`datamodel_type = "Server"`) in a poll loop.
3. Isolate what you test: set the Importance of confounding factors to 0 through the
   live config (Stalemate in particular drifts Aggression up after 4s of nothing
   happening, Stamina/Exhaustion move Guard and Tempo), and set
   `Config/Stamina/RegenerationMultiplier` to 0 when exact stamina matters. These
   edits are discarded when the playtest stops.
4. Teleport the NPC next to `workspace.dummy` (about 14 studs) instead of waiting out
   the chase: it can spawn ~200 studs away and sprinting drains its stamina.
5. A fight needs a real defender: clone `workspace.modnpc` in Edit mode as
   `modnpc TEMPTEST` (only names containing `modnpc` start as NPCs), **after** the
   test mod is final, because the clone keeps its own copy of it. Stop the AI tasks of
   both (`Scheduler:GetTasks()` then `:Stop`) so Engage's spacing does not walk them
   apart, set the clone's Agility to 0 to remove dodges (Defense still raises last moment
   guards; see the `defense` skill), and delete the clone and the mod afterwards. The
   dummy now lives in `ServerStorage.dummy`, and the templates are `workspace["balanced
   modnpc"]` and `ServerStorage["defensive modnpc"/"aggressive modnpc"]`.
6. Always finish with: stop the playtest, delete the temporary scripts/clones, confirm
   Studio's workspace holds only `modnpc` and `dummy`, and check `LogService` for
   errors/warnings rather than dumping the console.

## Gotchas

- **An unstarted ModNPC used to hang the reaction tick.** A model that is a ModNPC
  but was never started (still `_UNLOADED`, e.g. a template left in `workspace`) can be
  a focus target; TargetWeak's `IsStaggered`/`IsExhausted` invoked its
  `CharacterFunction` bind, which nothing answers, so the call yielded forever and
  every later `ReactionUpdate` subscriber (Stimulants, Defense) stopped. Now
  `CharacterUtility.sendFunction` refuses `_UNLOADED` characters and `askCharacter`
  answers false. If a character's moods or reactions freeze, time each
  `ReactionUpdate` subscriber (spawn each callback and see which never returns).

- **Rojo can silently stop.** If a playtest ignores new code, compare Studio's
  `Source` with disk (`Source:find("<new identifier>")`) and check that a `rojo`
  process is running before debugging logic.
- `Base.new` is at the type solver's complexity limit. A new module field can push
  it over ("Code is too complex to typecheck"); cast `self :: any` on the constructor
  calls from the failing line onward, as the existing comments there do.
- `Disposition.new` reads the raw `Base.Humanoid`, so it must stay built before
  `Humanoid.new` replaces it. It must also come after `Stamina` and `Configuration`.
- `Scheduler:GetTasks` still lists a task that just stopped; filter with
  `:IsRunning()` before acting on one.
- Match animation tracks by `track.Name` in tests, not by asset id (assets get
  replaced).
- `GetHealthInfo`, `IsStaggered` and `IsExhausted` (TargetWeak) are up to three API
  requests per reaction tick while a target exists; do not add more per-tick requests
  casually. Each state check is skipped once the weakness so far already reaches what
  it would give, and is a plain `false` (no warning) for anything that isn't a ModNPC.
  Asking another character a yes/no question is `CharacterUtility`'s `askCharacter`
  (see the `functions` skill, API-to-character boundary).
- **Axes used to saturate in a real fight** (0.8-1.0 averages under a hard clamp). With
  `saturate` and the retunes above, 60s template fights (defensive vs aggressive,
  balanced vs aggressive) show axis means of 0.4-0.75 with sd 0.15-0.35, except the
  aggressive template's Aggression (~0.97, from its 0.9 baseline and large positive
  Importances). Measure with a fight recorder (see the `defense` skill) before and
  after any retune.

## Impact zones

Changing an effect or saturation shifts how every NPC fights (retune and re-test the
playtest numbers above). Changing `GetEngageDistance` or `GetHoldDistance` affects both `ChaseTargets` and
`Engage`; changing `GetAttackStandoff` also moves where `AttackTargets` launches. Renaming a factor or axis is a schema change (mandatory config keys for all
NPCs) plus every override a character already has. Changing a combat event payload
affects Disposition, Damage, the Attack task and any external `CharacterEvent` sender.
