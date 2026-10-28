---
name: type-syncing
description: Use when changing the character's internal API, behavior functions, subscriptions, or anything exposed through Base, so TypeBehavior, TypeCharacterFunctions, and TypeAPIFunctions stay in sync with the runtime. Use this whenever a public method, callback signature, or function enum changes, or when fixing Luau type mismatches in the Behavior layer.
---

# Synchronizing behavior types

Use this skill when changing the character's internal API, behavior functions,
subscriptions, or another object exposed through `Base`.

`TypeBehavior.luau` is the synchronization contract for the runtime behavior
objects. It imports the canonical function enum from
`TypeCharacterFunctions.luau`, exports `FunctionName`, and describes the
callbacks and methods available on `Movement`, `CharacterAPI`, `Events`,
`FunctionSystem`, and `Base`. Runtime modules use these types while `Base` and
`Functions` construct the objects, so a change is incomplete until both sides
agree.

## Safe synchronization workflow

1. Identify the canonical name source. Behavior function names come from
   `TypeCharacterFunctions.FunctionEnum`; API module/function names come from
   `TypeAPIFunctions`. Do not invent a second enum or string spelling.
2. Change the runtime implementation and its public type together. For a new
   behavior function, update the enum, `TypeBehavior.FunctionCallbacks`, the
   runtime registration in `Functions:RegisterMainFunctions`, and any module
   method that is bridged.
3. For a new character API method, update `CharacterAPI.luau` and
   `TypeBehavior.CharacterAPI`. Keep `self` in the type signature and match
   optional parameters and return values.
4. For a subscription change, update `SubscribePosition`, `Subscription`,
   `FunctionSystem`, and `Base.SubscribeFunction` as applicable. The runtime
   currently supports `First`, `Last`, and one `Replace` subscriber.
5. Check every public object assembled in `Base.new`. A type that is exported
   but never assigned in `Base`, or a runtime method missing from its type, is
   a synchronization bug.

## Rerouting and bridging

`Functions` is the behavior router. Its main functions usually bind to a
method on `Base.Movement`, `Base.Targetting`, or `Base.Attacks`; subscribers
run before, instead of, or after the main function according to their
position. If a behavior should route to another module, add the bridge in
`RegisterMainFunctions` (or `bindIfAvailable`) and add the callback signature
to `TypeBehavior.FunctionCallbacks`. Do not bypass `CallFunction`, because
that loses subscriptions and replacement behavior.

When a public method moves between modules, update the runtime bridge, the
type contract, and all callers as one change. Preserve the `self` convention
for colon methods and use explicit guards for optional modules.

## Impact zones

- `TypeCharacterFunctions` changes affect `TypeBehavior.FunctionName`,
  `Functions.FunctionEnum`, registrations, subscriptions, and mod scripts.
- `TypeBehavior.FunctionCallbacks` changes affect callback type checking but
  not runtime dispatch by themselves; verify the corresponding runtime path.
- `CharacterAPI` changes affect `TypeAPIFunctions`, API request wiring, and
  `TypeBehavior.CharacterAPI`.
- `Events` changes affect `TypeBehavior.Events`, event producers, and every
  subscriber's callback shape.
- `Movement` changes affect `TypeBehavior.Movement`, `Functions` bridges,
  `CharacterAPI` wrappers, and any module calling movement.
- `Base` changes affect all mod scripts because `Base` is their integration
  surface.

Prefer extending an existing contract over broad casts or `any`. If a type
cannot describe the runtime behavior, fix the contract and implementation
together.