# Character Handles: Cross-Character Use Cases in Base

Companion to [Design.md](Design.md). This document inventories every place the behavior layer (Base) interacts with a character other than itself, sorts each interaction by what kind of information or effect it is, and says how a read-only `CharacterHandle` would relate to it.

Snapshot: commit `90aafce`, the code as it was before handles. Line numbers drift, names do not; search by function name if a line is off. The handle work this document planned is now built, and Design.md section 14 has the measured numbers.

---

## 1. How to read this document

Every interaction with another character falls into exactly one class. The class decides whether a handle is involved.

| Class | Meaning | Handle? |
|---|---|---|
| **Identity** | Only the `Model` is used, as a key or in a comparison. | No. `Model` stays the key everywhere. |
| **Live read** | State Roblox owns: health, position, root part. | Yes. A direct read, no request. |
| **Derived read** | State the API computes or holds in its own registry: team, targetable. | Yes. Read from the API's per-character entry. |
| **Ask** | State the target's own Base owns: staggered, exhausted. Needs the target's bind. | Yes, but it is the expensive tier: a cross-script invoke that can yield. |
| **Act** | Changes another character, or starts a protocol with it. | No. Always an API request. Handles never write. |

The rule behind the table (decided in the design discussion): **handles receive changes, they never make them.** Base asks the API to do things and is not owed an outcome; reading is the only thing a handle does.

Base already follows this rule for its own body. [init.luau:87](../../src/server/Behavior/v1/Base/init.luau#L87) hands every module the raw `Humanoid` with the note "READ/SIGNAL ONLY. do not change props". A handle extends that same contract to other characters.

---

## 2. What a read costs today

Every query about another character is a full request:

```
Base module -> CharacterAPI:Method -> Router:Request -> BindableFunction (Request)
  -> API.handleRequest (shape check, module lookup, pcall, ModuleResponse check)
  -> module function -> ModuleResponse -> response table, deep-copied back across the bindable
```

Counted from the code (not measured), one search tick of one character with `N` viable candidates, `K` known targets and `M` teammates in range:

| Step | Site | Requests |
|---|---|---|
| Own team | `SearchTask:GetViableTargets` | 1 |
| Opposing set | `CharacterAPI:GetOpposingTargets` (team again, then the filter) | 2 |
| Provoke-range check per candidate | `Distance:IsWithin` | N |
| Focus selection per known target (distance or health) | `TargetSelector:SelectBest` | K |
| Own team, again | `Friends:_getSameTeam` | 1 |
| Same-team set | `CharacterAPI:GetSameTeamTargets` (team again, then the filter) | 2 |
| Provoke-range check per teammate | `Friends:_withinProvokeRange` | M |
| **Total** | | **about 6 + N + K + M** |

On top of that, every task that tracks a focus target measures distance on its own tick (see 3.2), and `Disposition` can make up to three sequential requests per evaluation about its target (3.6).

With handles the same tick is two requests for the registered set (one for the search, one for `Friends`) plus a batch mint for characters never seen before. Everything else is a local read.

---

## 3. Inventory by system

Notation: **Today** is the current call chain; **With handles** is the intended relation. "Act" rows are listed so nothing is lost, but they do not change.

### 3.1 Target discovery and selection

| Site | Needs from the other character | Class | Today | With handles |
|---|---|---|---|---|
| `SearchTask:GetViableTargets` ([SearchForTargets.luau:105](../../src/server/Behavior/v1/Base/CharacterTasks/SearchForTargets.luau#L105)) | Its team, vs ours. The Neutral rule (neutral self takes everyone, otherwise only non-matching teams) lives here, line 108. | Derived | `GetTeam` + `GetOpposingTargets`, or `GetAllTargets` for neutral. | One `GetAllTargets`, then `IsHostile(other)` per candidate. Neutral rule moves to one place in the API. |
| Same function, provoke-range filter (line 126) | Distance to it. | Live | `Distance:IsWithin` per candidate, a request each. | Local math between two root parts. |
| Same function, new: untargetable filter | Whether it asked to be left out of target lists (conversation, mod-requested). | Derived (published) | Does not exist. TODO 1b needs it. | `IsTargetable()` per candidate. |
| `SearchTask:UpdateFocusTarget` -> `TargetSelector:SelectBest` ([TargetSelector.luau:11-48](../../src/server/Behavior/v1/Base/TargetSelector.luau#L11)) | Distance, health or max health, depending on `TargettingPreference`. | Live | One request per known target per search. | Local reads. |
| `SearchTask:UpdateTargets` | Identity (`[Model]` keys, spotted/lost diffing). | Identity | unchanged | unchanged |
| Events `TargetSpotted`, `TargetLost`, `NewFocusTarget`, `FocusedTargetChanged`, `AllTargetsLost` | Payloads are `TargettingContext`. | Identity (+ handle) | Context is `{Character, Type, Team}`. Base never reads `Type` or `Team` off a context (checked: only `request.Team` in `Friends` is read). | Context gains a handle so every subscriber, mods included, can read without minting. |
| `Wander` `knownTargets` ([Wander.luau:165](../../src/server/Behavior/v1/Base/CharacterTasks/Wander.luau#L165)) | Identity. | Identity | unchanged | unchanged |

### 3.2 Pursuit, engagement and range checks

All of these funnel into [Distance.luau:125-138](../../src/server/Behavior/v1/Base/Distance.luau#L125), which calls `CharacterAPI:GetDistanceTo` -> `Targetting.getDistance`. That makes `Distance` the single biggest read and the cheapest thing to migrate.

| Site | Frequency | Class | With handles |
|---|---|---|---|
| `ChaseTargetsTask` ([ChaseTargets.luau:132](../../src/server/Behavior/v1/Base/CharacterTasks/ChaseTargets.luau#L132), [:253](../../src/server/Behavior/v1/Base/CharacterTasks/ChaseTargets.luau#L253)) | Every update while chasing | Live | `Distance` reads two root parts locally. |
| `EngageTask` ([Engage.luau:480](../../src/server/Behavior/v1/Base/CharacterTasks/Engage.luau#L480)) | Every update while engaged | Live | same |
| `AttackTargetsTask` ([AttackTargets.luau:171](../../src/server/Behavior/v1/Base/CharacterTasks/AttackTargets.luau#L171)) | Every update with a target | Live | same |
| `Attacks` ([Attacks.luau:272](../../src/server/Behavior/v1/Base/Attacks.luau#L272)) | Attack choice | Live | same |
| `Attack` task start gate ([Attack.luau:134](../../src/server/Behavior/v1/Base/CharacterTasks/Attack.luau#L134)) and hit range check ([:393](../../src/server/Behavior/v1/Base/CharacterTasks/Attack.luau#L393)) | Per attack / per hit | Live | same |
| `Friends:GetTeammateDistance` ([Friends.luau:153](../../src/server/Behavior/v1/Base/Friends.luau#L153)) | On demand | Live | same |
| `ChaseTargets:SetFocusTarget` -> `Functions.SetFocusTarget` ([ChaseTargets.luau:205](../../src/server/Behavior/v1/Base/CharacterTasks/ChaseTargets.luau#L205)) | On focus change | Act (on self, takes the target `Instance`) | unchanged |

Because every site goes through `Distance`, no task needs to learn about handles for this win. `CharacterAPI:GetDistanceBetween`, which `Distance` calls, reads the two handles.

### 3.3 Attacking another character

| Site | Needs | Class | With handles |
|---|---|---|---|
| `Attack` task `_hitReached` ([Attack.luau:393-413](../../src/server/Behavior/v1/Base/CharacterTasks/Attack.luau#L393)) | Range (3.2). Then deals damage and pushes. | Live, then **Act** | Range read local. `DealDamage` and `PushAway` stay requests. |
| `Attack` task `IncomingAttack` stimulant ([Attack.luau:311](../../src/server/Behavior/v1/Base/CharacterTasks/Attack.luau#L311)) | Targets it by `Model`. | **Act** | unchanged (`StimulantBuilder:To` keeps taking a `Model`) |
| `ChaseTargets` `SprintingTowards` stimulant ([ChaseTargets.luau:134](../../src/server/Behavior/v1/Base/CharacterTasks/ChaseTargets.luau#L134)) | Distance read, then a stimulant to the target. | Live, then **Act** | Read local, emit unchanged. |

The outcome of a hit (`OutgoingDamageContext.RecieveType`) comes back from the receiver's own Damage layer. Nothing about the receiver needs to be read beforehand: the defender decides.

### 3.4 Taking hits (the defender's view of the attacker)

| Site | Needs | Class | With handles |
|---|---|---|---|
| `Damage:Receive` -> `WouldBounce` ([Damage.luau:365](../../src/server/Behavior/v1/Base/Damage.luau#L365), [Attacks.luau:463](../../src/server/Behavior/v1/Base/Attacks.luau#L463)) | Compares `attackTask.Context.Target ~= attacker`. | Identity | unchanged |
| `BounceAttack(opponent)` | Passes the opponent through to an event. | Identity | unchanged |
| `Damage._punishParried` ([Damage.luau:475](../../src/server/Behavior/v1/Base/Damage.luau#L475)) | Sends damage and a push back to the attacker. | **Act** | unchanged |
| `Damage` `lastAttacker`, `fatalHit` | Keeps the attacker `Model`. | Identity | unchanged |
| `Defense` ([Defense.luau:199](../../src/server/Behavior/v1/Base/Defense.luau#L199), [:388](../../src/server/Behavior/v1/Base/Defense.luau#L388)) | `stimulant.Source` as attacker identity; matched later by `==`. | Identity | unchanged |

This is the largest group of cross-character code and none of it needs a handle. The defender side is deliberately blind to the attacker's internals.

### 3.5 Teams and friends

| Site | Needs | Class | With handles |
|---|---|---|---|
| `Friends:_getSameTeam` ([Friends.luau:56](../../src/server/Behavior/v1/Base/Friends.luau#L56)) | Own team, then everyone on it. Neutral means nobody. | Derived | `IsAlly(other)` per registered character. |
| `Friends:_withinProvokeRange` (:63) | Distance. | Live | local |
| `Friends:_sync` (:94) | Diffs members; new teammate triggers `RequestFriend`. | Identity + **Act** | Diff unchanged; ask still a request. |
| `Friends:_isLiving` (:121) | Whether a character is alive. Today a `GetHealth` request, `nil` or `<= 0` is dead. | Live | `IsAlive()` |
| `Friends:RequestFriend` (:184), `ReceiveFriendRequest` (:195) | Team compare against `request.Team`, a snapshot taken by the API as the request leaves. Sender liveness checked first because a dead character's team reads `Neutral` (see comment at :192). | Derived + Live; the protocol itself is **Act** | Claim-and-request protocol unchanged (API-owned). Team check becomes `IsAlly(sender)`, liveness `IsAlive()`. A dead sender keeps its last-known team (Design.md D7), so the liveness check still goes first. |
| API `Friends.requestFriend` ([Friends.luau:94](../../src/server/API/v1/Modules/Friends.luau#L94)) | Sender's team via `CharacterUtility.getTeam`. | Derived | API-internal, uses the entry directly. |

### 3.6 Disposition (how the target's condition shapes our temperament)

`Disposition:_measureTargetWeakness` ([Disposition.luau:456](../../src/server/Behavior/v1/Base/Disposition.luau#L456)):

| Read | Class | Today | With handles |
|---|---|---|---|
| Health fraction | Live | `GetHealthInfo(target)`, a request | `GetHealthInfo()`, local |
| Staggered | **Ask** | `IsStaggered(target)`, a request that calls into the target's `Damage` | Stays an ask. Exposed as a handle method so Base needs no knowledge of whether the target can answer; unsupported kinds answer `false`. |
| Exhausted | **Ask** | `IsExhausted(target)`, a request that calls into the target's `Stamina` | same |

The existing code already orders these cheapest-first and skips each ask when the weakness so far already beats it. That ordering is kept; a handle just removes the first request.

### 3.7 Dialogue

| Site | Needs | Class | With handles |
|---|---|---|---|
| `Dialogue:StartBanter` ([Dialogue.luau:457](../../src/server/Behavior/v1/Base/Dialogue.luau#L457)) -> `RequestBanterResponse` | Starts a protocol with the target's `BanterRespond`. Non-ModNPCs just do not answer. | **Act** | unchanged |
| `DialogueBark` victory check ([DialogueBark.luau:105](../../src/server/Behavior/v1/Base/CharacterTasks/DialogueBark.luau#L105)) | `stimulant.Source` equals `lastFocus`. | Identity | unchanged |
| `DialogueBark` `NewFocusTarget` listener | Context payload only. | Identity | unchanged |

Known gap that handles do not fix by themselves: the `Died` stimulant is only emitted by ModNPCs ([Damage.luau:226](../../src/server/Behavior/v1/Base/Damage.luau#L226)), so beating a player or generic rig never plays the victory bark. That is an API-side broadcast question (TODO 6), not a handle one.

### 3.8 Stimulants

| Emitter | Recipient | Class |
|---|---|---|
| `IncomingAttack` ([Attack.luau:311](../../src/server/Behavior/v1/Base/CharacterTasks/Attack.luau#L311)) | `:To(target)` | **Act** |
| `SprintingTowards` ([ChaseTargets.luau:134](../../src/server/Behavior/v1/Base/CharacterTasks/ChaseTargets.luau#L134)) | `:To(target)` | **Act** |
| `BlockBroken` ([Block.luau:196](../../src/server/Behavior/v1/Base/CharacterTasks/Block.luau#L196)) | attacker | **Act** |
| `Exhausted` ([Stamina.luau:263](../../src/server/Behavior/v1/Base/Stamina.luau#L263)) | group / all | **Act** |
| `Died` ([Damage.luau:226](../../src/server/Behavior/v1/Base/Damage.luau#L226)) | `:ToAll()`, lingering | **Act** |

Emission is the API's job and stays a request; `StimulantBuilder` continues to take `Model`s. On the API side, `Stimulants.buildReceiver` ([Stimulants.luau:61](../../src/server/API/v1/Modules/Stimulants.luau#L61)) is already a small handle (`{Character, Deliver}`) with a comment that adapters slot in there. It is the model for how a per-kind capability is bound to a character.

### 3.9 The API's own cross-character code

Not Base, but the same fork repeated, and the reason the handle is an API abstraction first:

| Site | Fork |
|---|---|
| `CharacterUtility.getCharacterTeam` ([:307](../../src/server/API/v1/Modules/CharacterUtility.luau#L307)) | ModNPC reads config through an injected getter; everything else is `Neutral`. |
| `CharacterUtility.askCharacter` ([:430](../../src/server/API/v1/Modules/CharacterUtility.luau#L430)) | Non-ModNPC answers `false`. |
| `Damage.takeDamage` ([:75](../../src/server/API/v1/Modules/Damage.luau#L75)) | Re-validates the whole ModNPC folder per hit (line 97), then branches. |
| `Stimulants.buildReceiver` ([:61](../../src/server/API/v1/Modules/Stimulants.luau#L61)) | ModNPC gets a receiver; everything else is skipped. |
| `Targetting.registerTarget` ([:28](../../src/server/API/v1/Modules/Targetting.luau#L28)) | Snapshots team once at discovery; never refreshed. |
| `Friends.requestFriend`, `Dialogue.requestBanterResponse` | `sendFunction` fails for non-ModNPCs, mapped to a soft "no". |

### 3.10 Mods

Mods already read other characters through `CharacterAPI`. The documented surface ([Mod Scripts.md:265-275](../Mods/Mod%20Scripts.md)): `GetHealthInfo(model?)`, `GetHealth`, `GetMaxHealth`, `GetOpposingTargets`, `GetSameTeamTargets`, `GetAllTargets`, `GetTargetsOfType`, `GetDistanceTo`, `GetTeam`, `IsExhausted(model?)`, `IsStaggered(model?)`. All of these stay, reimplemented over handles so nothing a mod wrote breaks.

---

## 4. What the handle needs, by consumer count

Counted from the sites above. Methods nobody reads are not proposed.

| Read | Consumers in Base | Class |
|---|---|---|
| Root part / position / distance | `Distance` (about 15 call sites), `TargetSelector`, `Friends`, `SearchTask` | Live |
| Health, max health, health info | `TargetSelector`, `Disposition`, mods | Live |
| Alive | `Friends._isLiving` | Live |
| Team | `SearchTask`, `Friends`, mods | Derived |
| Hostile / ally relation | `SearchTask`, `Friends` (the Neutral rule is duplicated) | Derived |
| Targetable | none yet; TODO 1b conversation system will be the first | Derived (published) |
| Staggered, exhausted | `Disposition`, mods | Ask |

Not needed (no consumer): stamina values (`CharacterUtility.getStaminaInfo` has no caller), `getCharacterInfo` (no caller), kind or type (Base must not branch on it), armor (no system yet), blocking or parrying state (defenders decide, attackers never ask).

---

## 5. What stays a request

Everything in the **Act** class, unchanged: `DealDamage`, `PushAway`, `RequestFriend`, `RequestBanterResponse`, `EmitStimulant` / `SendStimulant`, `SetFocusTarget`, and the new requests the design adds to *change* published state (see Design.md section 6).

---

## 6. Observations that shaped the design

1. **Distance is the hot read and it already has one door.** Migrating `Distance` alone removes the per-tick requests from Chase, Engage, AttackTargets, Attacks and the attack range gates.
2. **Most cross-character code needs no handle.** The defender side (3.4), dialogue (3.7) and stimulants (3.8) are identity or Act. Only three groups read: discovery and selection, relationships, and disposition.
3. **The Neutral policy is written three times** (`SearchForTargets.luau:108`, `Friends.luau:57`, `Friends.luau:204`) and says one thing: Neutral is never an ally, and neutrals are hostile to everyone. That is a policy about teams. It moves into the handle as `IsAlly` / `IsHostile` (Design.md D6) and is deleted from Base.
4. **Dead currently means Neutral.** `getCharacterType` returns `nil` for a dead character, so `getTeam` falls through to `"Neutral"`. `Friends:ReceiveFriendRequest` relies on checking liveness first because of it. A handle separates "who are you" from "are you alive": a removed character keeps its last-known team (Design.md D7).
5. **`TargettingContext.Team` is never read by Base** and is stale after any team change. It can stay for compatibility, but the handle is the truth.
6. **Reads about ModNPC-only state already degrade softly** (`askCharacter` answers `false`). Handles formalize that so Base never needs to validate a call.
7. **The one thing Base cannot do today at all** is skip an untargetable character during a search. That is the first genuinely new capability, and it is what the published-state tier is for.
