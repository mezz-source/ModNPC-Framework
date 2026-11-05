# Character Handles: Design

Status: **built (phases 0 to 4).** Measured results are in section 14. Companion to [Use Cases.md](Use%20Cases.md), which inventories every cross-character interaction this design touches.

Written against commit `90aafce`, then updated to match what was built. Where building showed a better way, this document says what was built.

---

## 1. Summary

A `CharacterHandle` is a small, **read-only** view of one character, minted by the API and handed to Base. It answers questions about a character (is it alive, where is it, what team, how much health, can I target it) without Base knowing whether that character is a ModNPC, a player, or another framework's NPC.

Three things make it worth building:

1. **It removes round trips.** About `6 + N + K + M` requests per search tick (Use Cases section 2) become two requests for the set plus local reads. Per-tick distance checks in chase, engage and attack stop being requests at all. Measured, requests other than animation fell by about 60% (section 14).
2. **It makes Base type-blind.** Base stops asking "is this a ModNPC?" and stops validating every response. The fork lives in one place, behind the handle.
3. **It gives the API one place for per-character policy:** liveness, team, the Neutral rule, targetability. Today these are scattered across `CharacterUtility`, `Targetting`, `Friends`, `Damage` and `Stimulants`.

The handle never writes. Every change and every cross-character protocol stays an API request.

---

## 2. Decisions (settled)

These came out of the design discussion and are the constraints everything below follows.

| # | Decision |
|---|---|
| D1 | **Reads are handles, acts are requests.** Handles receive changes; they never make them. Base *asks* the API and is not owed an outcome. A handle method never negotiates a new value. |
| D2 | **Targetable is published state.** A character (or adapter) asks the API to take it off the target list ("take me off the menu") and later to put it back. The handle reads the result. **Staggered and exhausted are asks**, not published state, because they depend on the target's own engine. |
| D3 | **No events, no revision stamps.** Staleness is handled by the existing channels (binds, stimulants, events). When a cross-interaction happens, the API is the sole administrator. |
| D4 | **Mods may use handles.** `CharacterAPI:GetHandle(model)` is available to them. Usage is steered through objects that already flow everywhere (target contexts) so handles are not minted over and over. |
| D5 | **Asks stay flat on the handle.** `handle:IsStaggered()` and `handle:IsExhausted()`, not grouped. The tier is called out in the type annotations. |
| D6 | **Team relations live on the handle and nowhere else.** `IsAlly(other)` and `IsHostile(other)` carry the Neutral rule. Base keeps no Neutral rule of its own. |
| D7 | **A removed character keeps its last-known team.** Death or removal invalidates the handle as part of the removal sequence; there is no separate cleanup pass. |
| D8 | **The API creates and mints at track time.** The entry and its handle are made when `CharacterDiscovery` tracks the character. Every `CharacterAPI` handle call is directed to that already-created copy. There is no on-demand creation. |
| D9 | **No new Base layer.** Hydration stays in `SearchTask` and `Friends`; the cache stays in `CharacterAPI`. A targets layer that only forwards `CharacterAPI` reads adds a hop and no behavior. |
| D10 | **Handshakes are API-owned.** Pairings are claimed and administered by the API (section 6.1). The `FunctionEnum` wrapper for the hold requests is decided by its first caller. |
| D11 | **Set queries stay on `CharacterAPI`.** No `GetAllies()` / `GetEnemies()` on the handle; no current interaction needs them. |

Derived rules:

- **R1.** The API is the only writer of anything a handle reads that is not a live Roblox property. Base cannot make a handle disagree with the API.
- **R2.** Handle methods are **total**: they never throw, never need a `pcall` at the call site, and answer with a documented default when the question cannot be answered. Base does not validate handle results beyond reading a documented `nil`.
- **R3.** Acts (damage, push, friend requests, banter, stimulants, state changes) never appear on a handle.
- **R4.** Anything that needs **two** characters to agree (a friend request, banter, the future conversation pairing) is a handshake. The API claims and administers it under the pair-claim rules in section 6.1. A handle never takes part in one.

---

## 3. Non-goals

- Handle events, signals or revision counters (D3).
- Exposing a character's kind (`ModNPC` / `Generic`) to Base. Base must not branch on it.
- Replacing `Model` as the key in registries, claims, frames or focus tables. Handles are views; `Model` stays the identity.
- Making targetability an immunity. `DealDamage` still lands on an untargetable character; that is `Permissions/CanBeDamaged`'s job.
- Team support for players or other NPC frameworks. Non-ModNPCs stay `Neutral` until the adapter work in the TODO (Adapter Systems #2). The design only makes that work possible in one place.
- Anything about a ModNPC's *own* body (Movement, Animation, Sound, VFX, Bars, Highlights, Dialogue frame, Weapons, ContentDelivery). Those keep taking a `Model`.
- Handshakes and pairings (R4). They stay API requests with API-held claims.

---

## 4. Vocabulary

| Term | Meaning |
|---|---|
| **Handle** | The closure table Base holds. Read-only. A copy of it crosses the bindable, which is why it has no metatable and is not compared by identity (section 8). |
| **Entry** | The API's per-character record: the character, its adapter, its untargetable holds, its memoized handle. Created when discovery tracks the character, invalidated when it is removed. The single source for everything derived. |
| **Adapter** | The per-kind implementation of the few things that differ between kinds (team lookup, asks). ModNPC and Generic work. Jeff, MainScript, Standard v1 and Standard v2 are stubs that answer like Generic and never claim a character (section 7.2). |
| **Tier** | How a read gets its answer: **Live**, **Derived**, **Published**, **Ask** (section 5). |

---

## 5. The contract

The method set *is* the adapter contract: every method added is a burden on every future adapter. A method is admitted only if (a) Base logic needs it without knowing the kind, **and** (b) at least two kinds can answer it meaningfully, or the default for the rest is honest.

| Tier | Source | Cost | Fresh? |
|---|---|---|---|
| **Live** | Roblox instances (Humanoid, root part) | Property read | Always |
| **Derived** | The entry / adapter (team, hostility) | Table or property read | Always: the API is the sole writer and the ModNPC adapter reads the live config value |
| **Published** | The entry's hold set | Table read | Always; changed only by API requests (section 6) |
| **Ask** | The target's own Base, through its bind | Cross-script invoke; **can yield** | Always, but expensive |

### 5.1 v1 methods

All are called with a colon (`handle:IsAlive()`); the closures take an ignored `_self` like `Bar` and `Highlight` do.

| Method | Tier | Returns | Unsupported / failure default |
|---|---|---|---|
| `GetModel()` | Live | `Model` | always valid |
| `IsValid()` | Live | `boolean`: the character is still tracked (its entry has not been removed) | `false` |
| `IsAlive()` | Live | `boolean`: humanoid `Health > 0` | `false` |
| `GetRootPart()` | Live | `BasePart?`: `PrimaryPart`, else `HumanoidRootPart` (same rule as `CharacterUtility._getRootPart`) | `nil` |
| `GetPosition()` | Live | `Vector3?` | `nil` |
| `GetDistanceTo(other)` | Live | `number?`, studs between root parts. `other` is a handle or a `Model`. | `nil` if either side has no root part |
| `GetHealth()` / `GetMaxHealth()` | Live | `number?` | `nil` |
| `GetHealthInfo()` | Live | `{Health, MaxHealth, Fraction}?` | `nil` |
| `GetTeam()` | Derived | `string`. ModNPC: the live `Config/Team/TeamName` value. Others: `"Neutral"`. After removal: the last-known team (D7). | `"Neutral"` |
| `IsAlly(other)` | Derived | `boolean`: same team and the team is not Neutral. `other` is a handle or a `Model`. | `false` if either side is invalid, and for itself |
| `IsHostile(other)` | Derived | `boolean`: not allies. `other` is a handle or a `Model`. | `false` if either side is invalid, and for itself |
| `IsTargetable()` | Published | `boolean`: no untargetable holds | `true` |
| `IsStaggered()` | Ask | `boolean` | `false` |
| `IsExhausted()` | Ask | `boolean` | `false` |

`IsAlly` / `IsHostile` replaced the Neutral rule that was written in three places in Base (`SearchForTargets`, and twice in `Friends`). They encode what that code did: Neutral is nobody's ally and every neutral is hostile to everyone else. **Base now contains no Neutral rule and no `NEUTRAL_TEAM` constant** (D6). The relations are `false` when either side is invalid, so a removed character is neither ally nor enemy even though `GetTeam()` still answers. They are also `false` for the character itself, which is what lets the search drop its own "not me" check.

### 5.2 Semantics that must be written down

- **`nil` means unknown, not zero.** Numeric reads return `nil` when they cannot answer. Booleans never return `nil`.
- **Ask-tier methods fail safe.** Any failure (not a ModNPC, not started, `_UNLOADED`, bind missing, target mid-teardown) answers `false`. The existing guards in `CharacterUtility.sendFunction` and `askCharacter` already do this.
- **Asks can yield.** A mod hook on the target may yield, so an ask must not be made from inside a function that is itself answering an ask. Same caveat as the friend request protocol today.
- **Handles do not snapshot.** `handle:GetHealth()` reads *now*. A Base module that caches the result across ticks has chosen to accept staleness; the handle will not warn it.
- **No kind.** There is deliberately no `GetKind()` / `IsModNPC()`. If a future Base module believes it needs one, that is a missing capability, not a missing getter.

### 5.3 Deliberately not on the handle

| Not included | Why |
|---|---|
| `TakeDamage`, `PushAway`, `Heal`, `SetTeam`, `RequestFriend`, `RequestBanter`, `Deliver` | Acts (D1, R3). |
| `GetStamina`, `GetArmor`, `IsBlocking`, `IsParrying`, `GetKind` | No Base consumer (Use Cases section 4); armor has no system yet. Add when a consumer exists, under the admission rule above. |
| `GetAllies()`, `GetEnemies()` | Set queries enumerate N characters, and every handle returned is a deep-copied closure table. They stay `CharacterAPI` requests (`GetSameTeamTargets`, `GetOpposingTargets`) returning contexts. Per-character *predicates* live on the handle. Decided (D11). |

---

## 6. Changing published state

Reads are on the handle. The only **new write** the design introduces is targetability, and it is a request, never a handle method.

```luau
-- Behavior side
CharacterAPI:HoldUntargetable(reason: string)    -- "take me off the menu, I'm doing <reason>"
CharacterAPI:ReleaseUntargetable(reason: string) -- "okay, put me back in, coach"
```

API side, in the `CharacterHandles` module: `holdUntargetable(character, reason)` and `releaseUntargetable(character, reason)`.

| Rule | Detail |
|---|---|
| **Reason-keyed holds** | The entry keeps `Holds: { [string]: true }`. `IsTargetable()` is `next(Holds) == nil`. Two systems (a conversation, a mod) cannot stomp each other: releasing one reason leaves the other. |
| **Self only** | The requests name one character, the one asking, so there is no target to pass. Cross-character holds are not part of v1. |
| **Idempotent** | Holding an existing reason or releasing an absent one succeeds with `Data = false`, so cleanup paths can call it without checking. |
| **Cleared on removal** | When `CharacterDiscovery.Removed` fires, the holds are cleared. A dead character is not stuck untargetable, and one that returns starts clean. |
| **Works for any kind** | The hold set lives in the API's entry, not on the character, so it works for players and other NPCs too. |
| **Scope** | Honoured by the target search (`SearchTask`) and by any mod that checks `IsTargetable()`. **Not** honoured by `GetSameTeamTargets` / `Friends` (a talking friend is still a friend), `DealDamage`, or stimulants. |
| **Mod hook** | The `FunctionEnum` wrapper that lets mods intercept the hold, and the Base module that owns it, are decided by the **first caller** (the TODO 1b conversation system) (D10). Phase 2 ships only `CharacterAPI:HoldUntargetable` and `ReleaseUntargetable`. |

Data in the entry is changed only by these requests and by CharacterDiscovery's lifecycle. That is what makes R1 true.

### 6.1 Handshakes stay API-owned

Targetability is the only thing the design lets a character change about itself. Anything that needs **two** characters to agree is a handshake, and handshakes are administered by the API, never negotiated through handles (D10, R4). Today that is the friend request ([API Friends.luau:14-89](../../src/server/API/v1/Modules/Friends.luau#L14)) and the banter request; the TODO 1b conversation pairing is next. The pairing rules already in place, which any new handshake reuses:

- The API holds one **claim per pair**, stored under both characters so either side finds the same claim. Whoever claims first decides; the other side gets `Busy` and is never delivered.
- A claim has its **own identity**, so a stale claim from an earlier attempt cannot release a newer one.
- Claiming never yields. The request itself may (a mod hook on the target), which is why the claim is held across it.
- A character leaving (`Removed`) **releases all of its claims**, so a pair is never stuck behind a gone character.
- Anything that goes wrong midway is an **outcome**, not an error. Only a malformed request fails.

What this means for handles: the protocols (`RequestFriend`, `RequestBanterResponse`) stay requests. `IsAlly` / `IsHostile` help a module decide whether to *start* one but never replace the claim. And a conversation will not make its partner untargetable by holding it from outside (holds are self-only): the API pairs the two under a claim, and each side then holds *itself* with its own reason. That last point is guidance for TODO 1b, not built here.

---

## 7. Architecture

### 7.1 Layers

```
 Base (per character)                          API (shared, v1)
 ───────────────────                           ──────────────────────────────────────
 CharacterAPI                                  CharacterHandles  (new module)
   GetHandle(model)  ─ request, once ───────►    getHandle / getHandles
   GetHandles({m})   ─ one batch request ───►    holdUntargetable / releaseUntargetable
   GetHandle() (self)                            Entry  { Character, Adapter, Holds, Handle }
                                                   made on Added, invalidated on Removed
   cache: Model -> Handle                        Adapters/ModNPC   Adapters/Generic
   reads (GetHealth, GetDistanceTo, ...)         Adapters/Jeff, MainScript, StandardV1, StandardV2 (stubs)
     go through the handle, no request               ▲
 SearchTask, Friends                                 │ observes
   attach handles to contexts                  CharacterDiscovery (Added / Removed, _ensureTracked)
```

- `CharacterHandles` is a new API module, loaded by `Core.init` like the others. As a folder with an `init.luau` (the Bars precedent) it can hold `Adapters/` and `Handle.luau`.
- It builds an entry per tracked character through `CharacterDiscovery._observe`, the same pattern `Targetting`, `Friends` and `Stimulants` already use. Core inits modules in no particular order, which `_observe` already handles. The entry and its handle are made **when discovery tracks the character** (`Added`) and invalidated when it is removed (`Removed`); there is no on-demand creation (D8). Discovery's own validation, including its wait of up to 5 seconds for a newly added humanoid, is the only gate.
- The handle for a character is **memoized in its entry**: one canonical closure table per character, shared by every requester. A request returns it; the bindable copies the table structure while the closures keep sharing the entry's state.

### 7.2 Entry and adapter (API-internal)

```luau
type Entry = {
	Character: Model,
	Kind: string,                      -- the character type discovery decided on
	Adapter: Adapter,                  -- chosen from that type as the character is tracked
	Holds: { [string]: true },         -- untargetable holds
	Handle: CharacterHandle,           -- the memoized closure table
	Removed: boolean,                  -- set on CharacterDiscovery.Removed
	LastTeam: string?,                 -- read once, in the removal sequence (D7)
	Humanoid: Humanoid?,               -- looked up once and kept
	AdapterState: { [string]: any },   -- whatever the adapter wants to remember
}

type Adapter = {
	Name: string,
	Detect: (character: Model) -> boolean,
	GetTeam: (entry: Entry) -> string,
	Ask: (entry: Entry, question: "IsStaggered" | "IsExhausted") -> boolean,
}
```

Live reads are done by the core `Handle` (every kind has a Humanoid and a root part), so adapters are tiny. Handle closures capture the **entry**, never the adapter, so the API can change an entry's adapter underneath live handles. `_UNLOADED` handling stays where it was, evaluated at call time inside `askCharacter` and `sendFunction`: discovery tracks unloaded ModNPCs as ModNPCs on purpose, so the adapter does not change when one starts.

- **ModNPC adapter, `GetTeam`:** resolves the `Config/Team/TeamName` `StringValue` once, holds the instance (re-resolving if it was reparented), and returns `.Value`. A team change from anything is visible on the very next read. It does not go through `ConfigurationNetwork`, whose cached index can lag behind a value edited outside it, so the injected getter and its FIX-ME are gone.
- **ModNPC adapter, `Ask`:** `CharacterUtility.isStaggered` / `isExhausted`, which already refuse a missing bind and an `_UNLOADED` character, so the answer is `false` rather than a hang.
- **Generic adapter:** `GetTeam` is `"Neutral"`; `Ask` is `false`.
- **Stubs (`Jeff`, `MainScript`, `StandardV1`, `StandardV2`):** clones of Generic, tried in order by `Adapters.select` on anything that isn't a ModNPC. Their `Detect` is `false`, so none claims a character yet. Each file lists what is needed to build it: how to recognize that kind of NPC, where it keeps its team, and whether it has anything to ask.

**Removal sequence (D7).** The entry's `Removed` handler runs as part of discovery's own removal (death, destruction, or the sweep). In one step it reads the team into `LastTeam` (the model still exists at that moment), clears the holds and sets `Removed`. Pair claims are released by the API `Friends` module, which observes the same removal. The handle keeps working as an inert object: `IsValid()` and `IsAlive()` are `false`, `GetTeam()` returns `LastTeam`, the relations are `false`, `IsTargetable()` is `true` (no holds remain).

The entry stays in the registry until the model is destroyed. A dead character is still served to whoever asks, and a character that leaves the world and returns is revived in place, so every handle already held works again. Nothing sweeps later.

### 7.3 Base side

`CharacterAPI` gains:

| Addition | Behavior |
|---|---|
| `CharacterAPI:GetHandle(model: Model?)` | Cache hit returns immediately. Miss: one `getHandle` request, which returns the copy the API **already minted** when it tracked that character. Kept in a plain table keyed by model. Whenever a new character turns up, handles of destroyed characters are dropped, so the table can only outgrow the living by what died since the last new one. `nil` model means this character. Returns `nil` if the character is not tracked; a `nil` is never cached, so the next call asks again. |
| `CharacterAPI:GetHandles(models)` | One batch request for models not yet cached. Untracked models are left out of the result. Used wherever a list of unseen characters arrives at once. |
| `HoldUntargetable` / `ReleaseUntargetable` | The two requests in section 6. Each returns whether it changed anything. |
| Reimplemented, signatures unchanged | `GetTeam`, `GetHealth`, `GetMaxHealth`, `GetHealthInfo`, `IsExhausted`, `IsStaggered`, `GetDistanceTo`, `GetDistanceBetween`, `GetDistanceToPosition` read the handle, and fall back to the old request for a character that was never tracked. `GetTeam` has no fallback. Mods that already call them keep working. |

### 7.4 Where handles are first seen: contexts

Handles must not be minted per read. Use Cases section 3.1 shows that every target a Base module ever sees arrives through a `TargettingContext` that **`SearchTask` or `Friends` creates**, and every other task reads those contexts. So:

- `TargettingContext` gains an optional `Handle`.
- `SearchTask:UpdateTargets` and `Friends:_sync` call `GetHandles` once for the characters they have not seen before and attach `context.Handle` **before dispatching** `TargetSpotted` / `TeammateSpotted`. Every subscriber (tasks, `DialogueBark`, mods) then receives a context with a ready handle, with zero extra requests.
- `Distance`, `TargetSelector` and `Disposition` read through `CharacterAPI`, so reimplementing those reads moved them to handles without changing them. The per-Base cache resolves the handle without a request.
- Contexts returned straight from API set queries (`GetOpposingTargets`, ...) do **not** carry a handle. Embedding handle tables in every returned context would deep-copy N closure tables per call.

Decided (D9): no new Base module and no thin targets layer. Hydration happens in the two modules that create contexts (`SearchTask`, `Friends`), and the cache lives in `CharacterAPI`, which is already where every Base read of the API goes. A layer that only forwarded `CharacterAPI` reads would add a hop and no behavior.

### 7.5 What a search tick looks like

**Before** (about `6 + N + K + M` requests):

```
GetTeam -> GetTeam -> GetTargetsWithTeamFilter -> [GetDistance x N] -> [GetHealth/GetDistance x K]
-> GetTeam -> GetTeam -> GetTargetsWithTeamFilter -> [GetDistance x M] -> RequestFriend (acts)
```

**After:**

```
GetAllTargets            (1 request: who exists)
GetHandles(unseen)       (0 requests once every character has been seen)
for each candidate h: me:IsHostile(h) and h:IsTargetable() and me:GetDistanceTo(h) <= range   (local; me = CharacterAPI:GetHandle())
SelectBest               (local reads)
Friends: GetAllTargets (1 request), me:IsAlly(h), distance (local); RequestFriend unchanged (act, API-claimed)
```

`CharacterAPI:GetDistanceBetween` now reads two handles, so all ~15 range checks in Use Cases section 3.2 stopped being requests without `Distance` or any task changing. Base no longer calls `GetOpposingTargets` / `GetSameTeamTargets`; they remain for mods.

---

## 8. Failure model and subtleties

| Concern | Handling |
|---|---|
| **Handle copies are not equal.** The table is deep-copied at the bindable, so two copies of one handle are `~=`. | Never compare handles. Compare `handle:GetModel()` or keep using `Model` keys. Documented prominently. |
| **Closures run in the creating script's context, state in upvalues.** | Same property the existing `Bar`/`Highlight` objects rely on (API objects cross the Request bindable as closure tables because tables are deep-copied and metatables stripped). The handle holds an entry, not Instances, where possible. |
| **Character destroyed or dies while a handle is held.** | Methods keep answering with defaults; `IsValid()` is `false`, `IsAlive()` is `false`. No method throws. |
| **Mod stashes a handle forever.** | The entry leaves the registry when the model is destroyed, and the handle goes inert. The closures keep the entry, and so the destroyed model, in memory for as long as the mod holds them. |
| **Ask yields in a reaction tick.** | Same behavior as the request it replaces. Keep asks conditional, cheapest first (`Disposition` already does this). |
| **Tracked Generic later gains a ModNPC folder.** | Not handled, as today: the kind is decided once at discovery. Recorded as a known limitation. |
| **Dead and removed characters.** | Liveness and kind are separate. `IsAlive()` answers liveness; `GetTeam()` answers identity. On removal the entry invalidates itself in discovery's own removal sequence (section 7.2) and the handle becomes inert but keeps its last-known team (D7). |
| **Startup order.** | Entries exist only for tracked characters (D8), and discovery validates humanoids asynchronously, so a ModNPC could have asked for its own handle first. `API.startCharacter` removes the race: it calls `CharacterDiscovery._ensureTracked` before `Base.new`. Discovery still decides, under the same rules, and `Added` runs its listeners synchronously, so the handle exists before the character's first line. |
| **A model that was never tracked.** | `getHandle` answers `nil` with a reason; Base treats it as unknown. |

---

## 9. Impact zones

Legend: **New**, **Change**, **Reimplement** (same API, new internals), **None**.

### 9.1 API (`src/server/API/v1`)

| File | Impact | What changes |
|---|---|---|
| `Modules/CharacterHandles/` (`init`, `Handle`, `Adapters/`) | **New** | Entries, adapters and stubs, memoized handles, `getHandle`, `getHandles`, `holdUntargetable`, `releaseUntargetable`. |
| `API.luau` | Change | `startCharacter` tracks the character before `Base.new`. |
| `Modules/CharacterUtility.luau` | Change | `getTeam`, `setTeamGetter` and the team getter are gone. **Cycle caution:** `CharacterHandles` requires `CharacterUtility`, so `CharacterUtility` must never require `CharacterHandles`. |
| `Modules/ContentDelivery/ConfigurationNetwork.luau` | Change | The `setTeamGetter` injection and its FIX-ME are gone. |
| `Modules/Damage.luau` | Change | `takeDamage` asks `CharacterHandles._getCharacterType`, which answers from the entry instead of re-validating the whole ModNPC folder on every hit. It falls back to `getCharacterType` when there is no entry, and an unstarted ModNPC still counts as Generic. |
| `Modules/Targetting.luau` | Change | Contexts stay the same shape, but `Team` is refreshed on every read, so the team filters are always current. |
| `Modules/Friends.luau` | Change | Sender's team from the entry. Protocol unchanged. |
| `Modules/Stimulants.luau` | None (deferred) | `buildReceiver` is already shaped like an adapter capability; folding it in is a follow-up, not part of this work. |
| `Modules/CharacterDiscovery.luau` | Change | `_ensureTracked` for a character being started; `track` ignores a character already tracked. |
| `Modules/Movement`, `Animation`, `Sound`, `VFX`, `Bars`, `Highlights`, `Dialogue`, `Weapon`, `ContentDelivery/*` | None | Own-body or ModNPC-only (Non-goals). |

### 9.2 Types (`src/server/Types/v1`)

| File | Impact |
|---|---|
| `TypeCharacterHandle.luau` | **New**: the handle type and the `Entry`/`Adapter` types (API-internal). |
| `TypeAPIFunctions.luau` | Add module `CharacterHandles` and its function names; remove `GetTeam`. |
| `TypeBehavior.luau` | Add `GetHandle`, `GetHandles`, `HoldUntargetable`, `ReleaseUntargetable` to the `CharacterAPI` type. Keep every existing signature. Follow the type-syncing skill. |
| `TypeTargetting.luau` | `TargettingContext` gains optional `Handle`; `HealthInfo` now comes from `TypeCharacterHandle`. |
| `TypeFriends.luau` | `FriendContext` gains optional `Handle` (no behavior change). |

### 9.3 Behavior (`src/server/Behavior/v1/Base`)

| File | Impact | What changes |
|---|---|---|
| `CharacterAPI.luau` | **Change / Reimplement** | New methods (section 7.3); existing read methods become handle reads. |
| `CharacterTasks/SearchForTargets.luau` | **Change** | `GetViableTargets` rewritten (section 7.5): one `GetAllTargets`, then `IsHostile`, `IsTargetable` and range per candidate; hydrates `context.Handle`. The neutral branch and `NEUTRAL_TEAM` are deleted. |
| `Friends.luau` | Change | `_getSameTeam` becomes `IsAlly`; `_withinProvokeRange` and `_isLiving` use handles; hydrates handles. `ReceiveFriendRequest` asks `IsAlly(sender)` (the sender's handle is a cache hit once spotted, otherwise one mint). `NEUTRAL_TEAM` is deleted. The claim-and-request protocol is untouched (R4). |
| `init.luau` | Minor | One more `self :: any` cast: the larger `CharacterAPI` pushed `Skills.new` over the type solver's limit, the same limit the file already casts around. |
| `Distance`, `TargetSelector`, `Disposition` | **None** | They read through `CharacterAPI`, so they moved to handles unchanged. |
| `CharacterTasks/ChaseTargets`, `Engage`, `AttackTargets`, `Attack`, `Wander`, `Attacks`, `Damage`, `Defense`, `Dialogue`, `DialogueBark`, `Stamina`, `Block`, `Parry`, `Bounce` | **None** | Identity, Acts, or range checks that already go through `Distance` (Use Cases sections 3.2 to 3.8). |

### 9.4 Mods and docs

| Item | Impact |
|---|---|
| [docs/Architecture.md](../Architecture.md) section 2 | Add a fourth channel row: **Handles**, the read-only view, beside API requests, Functions and Events. |
| [docs/Mods/Mod Scripts.md](../Mods/Mod%20Scripts.md) ("Doing things to the world") | Document `GetHandle`, `context.Handle`, the tiers, "never compare handles", and that reads are not hookable. |
| `docs/Mods/Example Scripts/` | Add `09_HandleReads.luau` (reads a target through `context.Handle`; asks `IsStaggered`). The eight existing examples read no context fields and are unaffected. |
| [TODO.md](../../TODO.md) | Adapter Systems #3's first bullet is ticked and the stubs are listed. The Friend system "team changed" items depend on the API watching the same config value the ModNPC adapter reads. |
| Custom mod tasks | No break: `Model` keys and existing `CharacterAPI` signatures are unchanged. |

### 9.5 Behavior changes a user could notice

1. **Dead characters keep their team.** Today `getTeam` of a dead character is `"Neutral"` (because the type lookup returns `nil`). With entries it is the last-known team (D7). `Friends:ReceiveFriendRequest` already checks liveness first, so its outcomes do not change.
2. **Untargetable characters are skipped by the search.** New capability, only active once something holds.
3. **Reads are same-frame.** No `isReady` wait and no deferral, because there is no request. Anything that implicitly relied on a read being "a beat late" would notice; none was found.
4. **Distance uses the shared root-part rule** (`PrimaryPart`, else `HumanoidRootPart`), identical to `Targetting.getDistance` today. It must stay identical; a different rule would shift engage ranges.
5. **The Neutral rule exists once.** The three Base sites (`SearchForTargets.luau:108`, `Friends.luau:57`, `Friends.luau:204`) ask `IsHostile` / `IsAlly` instead. Outcomes are unchanged: a neutral character targets everyone, a non-neutral one targets every other team (neutrals included), and neutrals have no teammates.
6. **Team changes now reach everything.** The old registry snapshot was never refreshed, so a changed team went unnoticed. Now the search and `Friends` see it on their next pass: a former teammate becomes a target and a friend is lost (`FriendLost`).
7. **Friend requests judge the team live.** `ReceiveFriendRequest` asks `IsAlly(sender)` instead of comparing against the team snapshot taken as the request left, so a sender that changed team mid-request is declined (`TeamMismatch`). The snapshot stays in `FriendRequest` to fill `FriendContext.Team`.

---

## 10. Phased plan

All five phases are done. Each left the game working and was tested before the next.

| Phase | Scope | Exit check |
|---|---|---|
| **0. Baseline** | Count `Router:Request` calls per second by `Module.Function` on a fight, using a temporary Script that patches `Router.Request`. No framework change. | A recorded baseline to compare against. |
| **1. API-internal** | Build `CharacterHandles` with entries, adapters and handles. Move `Damage.takeDamage`, `Targetting`, API `Friends` onto entries. Nothing in Base changes. | Same fight behaves identically; `takeDamage` no longer re-validates per hit. |
| **2. Expose** | `CharacterAPI:GetHandle(s)` and its cache, the two hold requests, `TypeCharacterHandle`, `TypeBehavior`. Existing `CharacterAPI` reads reimplemented over handles. | Mod scripts and examples unchanged; handle reads from a mod script work; a ModNPC's own handle is available before its first search tick (section 8). |
| **3. Hot paths** | `SearchForTargets` (+ hydration, + targetable filter) and `Friends`. The Neutral rule and `NEUTRAL_TEAM` are deleted from Base. | Request count per search tick down to the target in section 7.5; friend outcomes as expected; fight patterns match the old reads (section 14). |
| **4. Cleanup and docs** | Remove `setTeamGetter` and `CharacterUtility.getTeam`; docs, example `09`, TODO. | Docs match code; no dead surface. |

---

## 11. Verification plan

Use the Studio MCP. Handle closures cannot be called from `execute_luau` (separate Lua VM), so drive tests from a temporary script in `ServerScriptService` or a mod script, and read the console.

1. **Baseline vs after:** requests per `Module.Function` over 30 seconds of a fight between two teams, plus one plain humanoid rig as a Generic target.
2. **Generic target:** reads work (`IsAlive`, `GetHealthInfo`, `GetTeam == "Neutral"`, distance); asks answer `false`; the fight against it is unchanged.
3. **Team change:** change `Config/Team/TeamName` in Studio during play; the next `GetTeam()` reflects it with no event.
4. **Targetable:** `HoldUntargetable("test")` removes the character from the other NPC's targets on its next search; a second reason keeps it hidden after the first is released; `Release` of the last returns it; death clears holds.
5. **Death and destruction:** a held handle answers defaults without throwing; `IsValid()` flips.
6. **Cache:** repeated reads of one target make one `getHandle` request; a destroyed model frees its cache entry.
7. **Mod compat:** the example mods type-check unchanged; `09_HandleReads` works on a live character.
8. **Asks:** `IsStaggered` / `IsExhausted` on a staggered, exhausted and normal ModNPC; on an `_UNLOADED` one (must be `false`, not a hang).
9. **Relations:** `IsAlly` / `IsHostile` over every pair of {Neutral, TeamA, TeamB}: Neutral vs Neutral hostile, same non-neutral allied, different teams hostile, and `false` for both when either side is removed.
10. **Removal sequence:** kill a character that holds itself untargetable. `IsValid()` and `IsAlive()` flip, `GetTeam()` returns the pre-death team, the holds are gone, and its pair claims are released.
11. **Startup:** start a ModNPC at game start; confirm its own handle is available before its first search tick and count any reads that degraded.

Acceptance: behavior identical to baseline apart from section 9.5, and the request count in step 1 within the target in section 7.5. Results are in section 14.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| **Contract growth.** Every added method burdens every adapter. | The admission rule in section 5. Add methods only with a Base consumer. |
| **Deep-copy cost of minting** (a handle is a table of about a dozen closures). | Memoize per entry, cache per Base, batch with `GetHandles`, and keep handles out of API list results. After a character's first search there are no mint requests left in the fight. |
| **Two ways to read another character** (handle vs raw instance). | Handles are the sanctioned path. Base reading `FindFirstChildOfClass("Humanoid")` on someone else's model is a review failure, the same way writing to `Base.Humanoid` is. |
| **Reads are not mod-hookable.** | Unchanged from today: `CharacterAPI` reads were never `CallFunction`s. Acts remain hookable where they already are. |
| **Reentrant asks.** | Rule in 5.2: no asks from inside an ask-answering function. |
| **Late kind change** (Generic gains a ModNPC folder). | Known limitation, same as today. |

---

## 13. Resolved questions

| # | Question | Decision |
|---|---|---|
| Q1 | Asks flat on the handle, or grouped? | **Flat** (D5). |
| Q2 | Team relations on the handle? | **Yes: `IsAlly` / `IsHostile`.** The Neutral rule is eliminated from Base (D6). |
| Q3 | Team of a dead or removed character? | **Last-known.** Removal invalidates the entry in discovery's own sequence (D7, section 7.2). |
| Q4 | Create entries on demand? | **No.** The API creates and mints at track time; `CharacterAPI` calls are directed to that copy (D8). `API.startCharacter` tracks first, so a character always has its handle (section 8). |
| Q5 | A dedicated `Targets` module for hydration and the cache? | **No.** Hydration in `SearchTask` / `Friends`, cache in `CharacterAPI` (D9). |
| Q6 | Wrap the hold requests in a `FunctionEnum`, and who owns it? | **First caller decides.** Handshakes are API-owned under the existing pair-claim rules (D10, R4, section 6.1). |
| Q7 | `GetAllies()` / `GetEnemies()` on the handle? | **No.** Set queries stay on `CharacterAPI` (D11). |

### Still to do

1. **`FriendRequest.Team` snapshot.** It now only fills `FriendContext.Team`. It could be read from the handle instead; left alone so the request protocol stays untouched.
2. **Hold wrapper.** When the TODO 1b conversation system lands, pick the Base module and `FunctionEnum` names for the hold requests and add the pairing to the API claim set.
3. **Stub adapters.** Jeff, MainScript, Standard v1 and Standard v2 need integration information before they can claim a character.
4. **Acts through adapters.** `Damage.takeDamage` and `Stimulants.buildReceiver` still fork on the ModNPC kind themselves. Moving those forks into adapters is the next step for other NPC systems to take hits and hear stimulants.

---

## 14. Results

Measured in Studio on `Router.Request`: two ModNPCs on one team, one on another, and a plain rig as a Generic target, all with 1,000,000 health. 8 seconds to settle, then a 30 second window.

### Requests the handle replaced

| Request | Before (per second) | After | Before (ms in window) | After |
|---|---|---|---|---|
| `Targetting.getDistance` | 55.7 | 0 | 44.1 | 0 |
| `CharacterUtility.getHealthInfo` | 16.7 | 0 | 23.0 | 0 |
| `CharacterUtility.isStaggered` | 16.7 | 0 (now a direct ask) | 25.2 | not counted |
| `CharacterUtility.isExhausted` | 14.0 | 0 (now a direct ask) | 12.1 | not counted |
| `CharacterUtility.getTeam` | 10.8 | 0 | 160.3 | 0 |
| `Targetting.getTargetsWithTeamFilter` | 5.4 | 0 | 5.0 | 0 |
| `Targetting.getTargets` | 0 | 5.4 | 0 | 6.3 |
| **Total** | **119.3** | **5.4** | **269.7** | **6.3** |

`Damage.takeDamage` also fell from about 1250µs per call to between 400µs and 800µs, because it no longer validates the whole folder on every hit.

Two limits on these numbers. Asks still happen, about 33 per second: they call the target's bind directly, skipping the API, so `Router.Request` no longer sees them. And handle reads run in the caller, so their small cost isn't in this table either.

### Whole fight

| Run | Reads | Fight pattern | Animation per second | Everything else per second |
|---|---|---|---|---|
| Baseline, commit `90aafce` | old | not recorded | 213 | 187 |
| Phase 1 | old | not recorded | 219 | 194 |
| A/B run 1 | old, patched back in | A and B, C on the rig | 170 | 179 |
| A/B run 2 | old, patched back in | gang on B | 195 | 184 |
| A/B run 3 | handles | gang on B | 278 | 77 |
| A/B run 4 | handles | A and B, C on the rig | 146 | 69 |
| Final | handles | A and B, C on the rig | 320 | 74 |

Only the last column is comparable between runs. Requests other than animation fell from about 186 to about 73 per second, a 61% cut.

Animation swung between 146 and 320 per second with how much the NPCs moved, because `Animation:_running` made three requests on every `Humanoid.Running`. Both fight patterns showed up with old reads and with handles, so the swing was not caused by this work.

### Follow-up: the costs handles did not fix

The measurements above showed the biggest costs were outside this design, so both were fixed afterwards:

- **Gait memory in `Animation`.** `_running` remembers which of Walk or Sprint is playing and only swaps on a change. It sets the track speed only when the speed moved by `GAIT_SPEED_STEP` (1 stud per second) or more. `StopAnimation` clears the gait, so a track stopped by anything else comes back on the next speed change.
- **`Weapon.getWeaponSetting` no longer validates.** It uses `ModFolder.find` and looks the setting up. A weapon broken mid-play keeps answering reads, which is an accepted trade-off. Equipping still validates.

| | After handles | After the follow-up (2 runs) |
|---|---|---|
| Animation requests per second | 146 to 320 | 47 and 77 |
| All requests per second | 215 to 394 | 121 and 150 |
| Time in requests, per 30 second window | 628 to 1015 ms | 256 and 317 ms |
| `Weapon.getWeaponSetting` per call | about 390µs | about 40µs |
| `Weapon.getWeaponSetting` per window | 219 to 311 ms | 27 and 29 ms |

The original baseline was 400 requests per second and 1070ms per window. Calling `getWeaponSetting` directly now takes 1.6µs, so almost all of its 40µs is the cost of being a request.

`readWeapon` still validates fully in equip, unequip, drop, `isEquipped`, `getWeapons` and `_getPart`. None of them showed up as a cost in these fights.

### Verification

153 of 153 checks passed on a live server, reaching handles through the real `Request` bindable. They covered every item in section 11, plus a character leaving the world and returning, and a natural fight to the death with an ally left behind. Type checking reports no errors in `src/server` or the example mods.

Not verified:

- **Player characters.** The Generic path was only tested with a plain rig.
- **Example mods 01 to 08.** They type-check, but only `09_HandleReads` was run live.
- **One unexplained warning.** `Humanoid health unexpectedly changed` appeared once, on the 20 health fighter in the natural death test. Handles can't write health and `Damage:_onHealthChanged` was not touched, but that test did not exist before this work, so there is no old result to compare it to.
