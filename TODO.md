# TODO

## Core Systems

### 1. Integrate dialogue system

- [x] Dialogue priority enum / base handler (`Config/Dialogue/Priorities`, `SayLine` function, Death line on death)
- [x] `DialogueBark` essential start task (listens for events, barks through `SayLine`)
- [x] Basic barks: CombatDealCrit, CombatLaunched, CombatRecieveCrit (+ block breaks), CombatRecover, CombatDodged, Death, Idle, SpotEnemyIndividual
- [x] `Config/Dialogue/MaxRandomDelay` per-category random delay before a line is said
- [x] SpotFriendStart/Response: friend greeting exchange (`FriendAdded` Initiated -> `StartFriendGreeting` -> `RequestFriendResponse` -> `FriendRespond`), same route as banter
- [x] Barks that need broadcasts/coordination: (Friendly)TeamChanged (SpotEnemyTeamed / SpotEnemyTeamedResponse are done, see Friend system)
- [x] Dialogue API / class (per-character dialogue frame: queue, cancel, destroy; `CharacterAPI:CreateDialogueFrame`, `base.Dialogue:Queue/Cancel/CancelAll`)
- [X] Wire the frame's `OnEvent` (`<sfx>`, `<anim>`, `<event>`)
- [x] Relevant text effects

#### 1b. Conversation system

- [ ] When an NPC has a conversation, they become invalid targets and go through each other's lines (invalid targets: `HoldUntargetable` is built; the API should claim the pair the way friend requests do, and each side holds itself)
- [ ] NPCs in dialogue enter a frozen thinking state and cancel their current actions
- [ ] Ensure dialogue markup events are hookable via mod scripts

### 2. Attack bouncing

- [x] Two characters attacking each other with hits of the same damage type and weight bounce: both attacks are cancelled, nobody takes damage or a special, each is thrown back, plays the weapon's `Bounce` sound and a random `AttackBounce` animation, and can't attack until it ends (`Attacks:BounceAttack`, `Bounce` task, `BounceState`)

### 3. Attack parrying

- [x] `Parry` task + `ParryState` (window until the `ParryEnd` marker, then held until the animation ends; a hit in the window is `Parried`: no damage, `ParryHit` plays)
- [x] Roll for intellect to trigger a parry as a reaction to an incoming attack stimulus (`Defense:_tryParry`, first thing `_decide` does; timed to start 0.15s before the hit)
- [x] Parries cost the weapon's `Config/Stamina/ParryConsumption`; a parried hit refunds 120% of it
- [x] A parried hit sends 50% of the damage back from Base (`Damage:_punishParried`): light attack = StaggerBackwards, heavier = Launch; the attacker's attacks are cancelled
- [x] `Damage/Parry` asset carries the `ParryEnd` marker (0.30s of 0.55s)

### 4. Ranged bullets / ranged attack systems

We have targeting params for it, but there's no framework for bullets or magical attacks.

- [ ] Decide on an approach: FastCast, or just HitScan?
- [ ] Integrate bullet firing/relavant classes (likely an API function)

### 5. Attack validation

- [ ] Add config validation for attacks (attack context/hit context enforcement)

### 6. Friend system
We have a targetting system, we just need to build some broadcasts and a base behavior module

- [x] Build a base friend module with various utilities (like getting nearest friends) (`Friends` has `GetTeammates`/`IsTeammate`/`GetTeammateDistance`/`GetTeammateDistances`/`GetClosestTeammate`/`GetClosestFriend`, all on the bulk `Distance` measures)
- [x] Bulk distance measures and shared target ticks: `Distance:Measure`/`FilterWithin`/`Nearest`/`Furthest` read our position once and reuse a reading for 0.05s; `CharacterAPI:GetTargetSnapshot` is one frozen target list shared by every character for 0.25s, used by the search and Friends (live test: 21 `getTargets` requests over 59 searches, 2 per search before)
- [x] Maybe: cache "no handle" answers in `CharacterAPI:GetHandle` (an untracked character is asked about on every call), and decide whether to remove the API-side `Targetting.getDistance*` fallbacks
- [x] Spot targets with matching teams and add them to a friends list (`Friends`, synced after each search, limited to the provoke range)
- [x] Friend connection handshake: API `Friends` module locks the pair and carries the request, Base `Friends` asks and answers (`RequestFriend`/`ReceiveFriendRequest`), once per pair; friends are remembered out of range
- [x] Listen for events indicating they change teams (the search and `Friends` already pick a team change up on their next pass; this is for reacting to it the moment it happens)
- [x] Listen for events where a friendly dies
- [ ] Add a wander preference for patrolling around a friend instead of randomly
- [x] Target spotting can play a different line depending on if a friend spotted them first or not (Individual/Teamed switch)
  - [x] API side: `Util/Claims` (`newPair`/`newSingle`, optional timeouts) and Targetting target claims, one per team (`claimTarget` returns `{ Claimed, Holder }`, `getTargetClaim`, `releaseTargetClaim`; 5s default, 30s cap), live-tested through the request bindable
  - [x] Base side: CharacterAPI `ClaimTarget`/`GetTargetClaimHolder`/`ReleaseTargetClaim`. `FunctionEnum.ClaimTarget` (TargetSelector) is gated on having a team and a teammate and runs before `NewFocusTarget`, which carries `alreadyClaimed`. The bark task skips the line when the target is already claimed, otherwise it calls `CallOutTarget` (SpotEnemyTeamed on a team with a teammate in range, SpotEnemyIndividual otherwise, then waits for the line to finish typing). Live-tested.
  - [x] Callout stimulant `EnemySpottedByAlly` (Spotter, Target) sent to teammates in range once the line is typed. The bark answers with `SpotEnemyTeamedResponse` once the target is its own focus. Live-tested, including a teammate who focused the target after the callout arrived.

---

## Cosmetics

### 1. Better death system

- [ ] Better death animations
- [ ] Maintain upright pose but keep unanchored
- [ ] Ragdoll on death (?)

### 2. Attack trails

- [x] ModWeapons with `UseTrail` have their `WeaponTrail` enabled for the length of the attack task (`CharacterAPI:SetWeaponTrail`)

### 3. Better VFX system

- [ ] Allow for more targeted VFX (e.g. creating a temp VFX part to spawn a swipe, etc.)
- [x] Persistent particles: `CharacterAPI:CreateParticle` from VFX data at a part, model or world position (Emit, Enable, Disable, Destroy)

### 4. Bounce particles

- [x] Particles for attack bouncing (see [Attack bouncing](#2-attack-bouncing))

### 5. Performance
This should be the last swipe as base systems become finalized

- [ ] Profile high usage and expensive functions
- [ ] Integrate fixes
- [ ] Test large sums of NPCs and performance

### 6. Tool Holding
- [x] Add an additional 'WeaponHold' animation runs at all times so that hold animations are consistent across rigs (Motor6D displcements)


---

## Adapter Systems

### 1. Document common NPC types

- [ ] Cover things like Jeff, MainScripts, Standard v1, Standard v2

### 2. Integrate API support

- [ ] Team grabbing, attack context translation

### 3. Character Handles

- [x] Create a character cross-talk abstraction called `CharacterHandle`: read-only, minted by the API as it tracks a character, reachable through `CharacterAPI:GetHandle` and `context.Handle` (see [docs/Handles/Design.md](docs/Handles/Design.md))
- [x] ModNPC and Generic adapters
- [x] Published targetability (`HoldUntargetable` / `ReleaseUntargetable`), ready for the conversation system
- [ ] Fill in the stub adapters (`Jeff`, `MainScript`, `StandardV1`, `StandardV2` in `CharacterHandles/Adapters`): needs how to recognize each one, where it keeps its team, and what can be asked of it
- [ ] Move the acts that still fork on ModNPC (`Damage.takeDamage`, `Stimulants.buildReceiver`) into adapters

- [ ] Allow conversating with Standard v1 and MainScript NPCs (because funny)

---

## Future Rollout (stretch goals)

### 1. Conversion agent
- [ ] Build an agent for importing existing frameworks and analyze dependencies/unique behaviors (this plays into [Document common NPC types](#1-document-common-npc-types))
    - [ ] Jeff/MainScript imports
    - [ ] Standard v1 imports
    - [ ] Standard v2 imports    
- [ ] Create a producable step-by-step process transforming old frameworks into the ModNPC framework
- [ ] Convert one of each type to a behavior set (see [Create behavior sets](#2-behavior-sets))
- [ ] Automate the process

### 2. Behavior Sets
- [ ] Build a lightweight skeleton behavior set with bare `BaseBehavior` essentials (animation, damage, events and functions, mods)
- [ ] Build Jeff/Mainscript behavior set
- [ ] Build Standard v1 behavior set
- [ ] Build Standard v2 behavior set