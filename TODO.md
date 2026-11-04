# TODO

## Core Systems

### 1. Integrate dialogue system

- [ ] Dialogue priority enum / base handler
- [ ] Dialogue API / class
- [ ] Relevant text effects

#### 1b. Conversation system

- [ ] When an NPC has a conversation, they become invalid targets and go through each other's lines
- [ ] NPCs in dialogue enter a frozen thinking state and cancel their current actions
- [ ] Ensure dialogue markup events are hookable via mod scripts

### 2. Attack bouncing

Two opposing enemies who attack each other with an attack of the same type (e.g. "sharp v. sharp") play a bounce-off animation and trade a small amount of damage.

### 3. Attack parrying

Roll for intellect to trigger a react reaction to an incoming attack stimulus.

### 4. Ranged bullets / ranged attack systems

We have targeting params for it, but there's no framework for bullets or magical attacks.

- [ ] Decide on an approach: FastCast, or just HitScan?
- [ ] Integrate bullet firing/relavant classes (likely an API function)

### 5. Attack validation

- [ ] Add config validation for attacks (attack context/hit context enforcement)

---

## Cosmetics

### 1. Better death system

- [ ] Better death animations
- [ ] Maintain upright pose but keep unanchored
- [ ] Ragdoll on death (?)

### 2. Attack trails

- [ ] ModWeapons with `TrailEnabled` will have a trail instance enabled/disabled on attack

### 3. Better VFX system

- [ ] Allow for more targeted VFX (e.g. creating a temp VFX part to spawn a swipe, etc.)

### 4. Bounce particles

- [ ] Particles for attack bouncing (see [Attack bouncing](#2-attack-bouncing))

---

## Adapter Systems

### 1. Document common NPC types

- [ ] Cover things like Jeff, MainScripts, Standard v1, Standard v2

### 2. Integrate API support

- [ ] Team grabbing, attack context translation

### 3. Character Handles

- [ ] Create a character cross-talk abstraction called `CharacterHandle`, which can eventually translate capabilities (e.g. conversations, damage events) without knowing specific NPC types.

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
- [ ] Build Standard v1 behavior set