---
name: defense
description: Use when changing how ModNPC characters meet hits they see coming - Defense.luau, the IncomingAttack reaction (dodge timed to the hit, Agility roll, last moment guard), ReactToIncomingAttack, DefenseState/Reacting, Config/Defense (DodgeReactionTime, BlockReactionTime, BlockSureTime, DodgeBonus), the Combat.DefenseReaction event, or why a character dodged, blocked or took a hit. Also use when tuning dodge/block rates or testing defense with attacker/defender clones, even if the user just says "dodging" or "reacting to attacks".
---

# Defense (meeting the hits a character sees coming)

`Behavior/v1/Base/Defense.luau`, types in `Types/v1/TypeDefense.luau`. A behavior
module; others reach it through `FunctionEnum.ReactToIncomingAttack` (mods can
replace how a character defends itself).

Damage no longer rolls a passive dodge when a hit lands. A hit is defended only by
what the character was already doing (an active dodge or a raised guard), and the
attacker's warning (`IncomingAttack`, see the `stimulants` skill) is what lets it
prepare. **A hit nobody warned about (a player, a legacy script) meets whatever the
character happens to be doing**; give such attackers an IncomingAttack if they should be
dodgeable.

## The decision (once per hit)

On the reaction tick whose `Stimulant.Pending` holds an `IncomingAttack`, Defense
consumes it and calls `ReactToIncomingAttack(stimulant)`. `timeLeft = ExpiresAt - now`
(the hit lands at ExpiresAt).

1. `timeLeft <= 0` → **None** ("Too late").
2. Guard already up (`IsBlocking`) and it can pay this hit's block cost (weight from
   `GetHitCategory(Data.BaseDamage)` → `TypeBlock.HitCosts`) → **Guarded**. The guard
   is held for it if Defense raised it.
3. Dodge, if `timeLeft >= DodgeReactionTime`, `CanDodge`, the rested Dodge cost is
   affordable, and `RollSkills({ Agility })` passes (`Roll <= Target + DodgeBonus*100`;
   exhaustion is already in Skills' target) → **Dodge**. The dodge goes off
   `DODGE_LEAD` (0.12s) before the hit, or at once if less is left, so Movement's 0.3s
   active span covers the landing. Direction: side with odds 0.3 + 0.6 * Aggression,
   else back. A dodge refused when it fires falls back to step 4.
4. Last moment guard, if `timeLeft >= BlockReactionTime`, `CanBlock`, BlockLight is
   affordable, and a roll passes: odds ramp from 0 at BlockReactionTime to 1 at
   BlockSureTime, times `1 + (Guard - 0.5)` → **Block** (reason = why the dodge didn't
   happen). The guard is a Block task with `Holder = "Defense"`, held until
   `ExpiresAt + GUARD_HOLD` (0.35s, so a combo's next hit finds it up), then stopped
   unless Engage adopted it (`Holder = "Engage"`).
5. Otherwise → **None** with both reasons ("Too late to dodge, Guard too slow").

Every decision dispatches `Combat.DefenseReaction` `{ Attacker, Reaction, TimeLeft,
Reason }` before the hit lands. How the hit actually went is still `DefenseSucceeded` /
`DamageTaken`.

**DefenseState** (`Reacting`) holds from the decision until the dodge fires / the held
guard's time is up; `Abilities.CanAttack` forbids attacking while Reacting so the
character doesn't swing into a hit it chose to dodge or block (Attacks cancels guards).

**A dodge that takes the character out of reach** makes the attacker's range check fail
(`AttackMissed`), so Damage never sees the hit. Defense announces it as
`DefenseSucceeded { RecieveType = Dodged }` once `ExpiresAt + 0.2s` passes without Damage
reporting an outcome from that attacker, so the Opening factor still fires. Retraction
can't be used for this: a resolved hit's retraction never reaches the receiver (see the
`stimulants` skill). A retraction that does arrive means the attack was cut short:
pending dodges are cancelled and a guard raised for it drops after GUARD_HOLD.

## Config/Defense (optional, not in the schema)

| Setting | Default | balanced / defensive / aggressive |
| --- | --- | --- |
| DodgeReactionTime | 0.15 | 0.15 / 0.15 / 0.12 |
| BlockReactionTime | 0.05 | 0.05 / 0.03 / 0.08 |
| BlockSureTime | 0.3 | 0.3 / 0.22 / 0.35 |
| DodgeBonus | 0 | 0 / 0 / 0.05 |

Values must exist before play starts: `Configuration` caches entries, so a NumberValue
added during play isn't seen (edits to existing ones are).

## Measured (Punch1, 2026-10-30)

- Warning time at arrival: median 0.21-0.31s, min 0.08s. Decisions land 0-0.33s before
  the hit, so **reaction speed is the main dodge limiter** (roughly a third of hits are
  "Too late to dodge" at ReactionSpeed 0.1 + 0.15 deviation).
- Isolated defender, Agility 35: ~10% dodge, ~40% block, ~50% hit. Agility 100 with
  0.05s reactions: ~45% dodge. Every Dodge decision avoided its hit; every Block/Guarded
  ended Blocked.
- 60s template fights: guard uptime 22-52%, exhaustion 0-43%, damage 90-380 per side.

## Testing recipe

- The temp start Script can expose Bases: `_G.T = { Bases = { [name] = API.startCharacter(model) } }`.
  Scripts created during play (Server datamodel, `Instance.new("Script")`) share `_G` and
  the module cache, so they can drive `_G.T.Bases[...]` directly. Results go in a
  workspace attribute (JSON) read by `execute_luau`. Don't `Destroy` a probe script
  before it finishes: that kills its thread.
- Isolated rounds: clone a template as `modnpc DEFENDER` / `modnpc ATTACKER` (high
  MaxHealth), stop both schedulers' tasks, `PivotTo` them 0.6 x DesiredRange apart facing
  each other, `RestoreStamina(1000)` both, `A.Attacks:Attack("Melee", defender)`, wait for
  `A.Attacks.CurrentAttackTask == nil`, count `DefenseReaction` / `DefenseSucceeded` /
  `AttackLanded` / `AttackMissed`. Wait between rounds until the defender isn't
  staggered, Reacting or blocking.
- `SpendStamina(1000)` is *declined* when it can't be paid in full; drain with
  `SpendStamina(current - leave)`. A guard-break test needs
  `Config/Stamina/RegenerationMultiplier = 0`, or the stamina regrows past BlockLight
  during the windup.
- Full fights: clone two templates from ServerStorage into workspace ~25 studs apart and
  >150 studs from any other model, start both, sample axes/uptimes every 0.25s for 60s.
- Clean up: stop play, delete temp scripts and clones, clear workspace attributes.
