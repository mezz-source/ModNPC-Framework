---
name: functions
description: Use when adding, renaming, or changing named ModNPC behavior functions (Functions.luau, FunctionSystem, CallFunction, First/Replace/Last subscriptions, RegisterMainFunctions, FunctionEnum) or high-level behavior like attacking, wandering, sprinting, or dodging that mod scripts should be able to hook or replace.
---

# Character function system

Use this skill for named, callable character behavior and for bridging one
behavior module to another.

`Functions.luau` owns the per-character `FunctionSystem`. It stores one
`MainFunctions` callback per name, then `CallFunction` executes subscribers in
this order:

1. `First` subscribers;
2. one optional `Replace` subscriber instead of the main function;
3. the main function when it was not replaced;
4. `Last` subscribers.

Subscriptions are snapshotted before iteration, can be unsubscribed, and
receive the same arguments as the call. Use `Base.Functions:CallFunction` (or
`Base:SubscribeFunction`) rather than calling a registered behavior method
directly when hooks or replacements must work.

## Adding a base function

1. Add the canonical name to `TypeCharacterFunctions.FunctionEnum`.
2. Add its callback signature to `TypeBehavior.FunctionCallbacks` and update
   any related public function types.
3. In `Functions:RegisterMainFunctions`, bind the name to the owning module
   method. Use the local `bind` helper for required `Movement` methods and
   `bindIfAvailable` for optional modules such as `Targetting` or `Attacks`.
4. Implement the module method with the normal colon-method `self`
   convention, then verify `Base.new` constructs that module before function
   registration.
5. Call it through `CallFunction` and test missing-module, replacement, and
   normal execution paths.

Functions should primarily bridge module-to-module interactions: a high-level
action can obtain targets, choose an attack, move, play animation, and emit
events while remaining replaceable by a mod script. High-level behavior such
as attacking, wandering, sprinting, or dodging belongs here.

Keep low-level API behavior out of this layer. Operations such as applying an
impulse, applying angular impulse, or dealing direct humanoid damage should
remain in `CharacterAPI` and the API modules. A function may orchestrate those
operations as part of a high-level action, but it should not duplicate their
request construction or move primitive implementation into the function
system.

## Impact zones

Adding a function affects the canonical enum, `TypeBehavior`, registration,
the owning module, and callers/mod scripts. Removing or renaming one can make
`CallFunction` raise `Unknown behavior function` or make subscriptions fail.
Changing a function's arguments affects all `First`, `Replace`, `Last`
callbacks, so update the type and every subscriber together.