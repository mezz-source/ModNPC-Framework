---
name: events
description: Use when creating, dispatching, subscribing to, or changing character-scoped events in ModNPC (Base.Events, Subscribe/Dispatch, CharacterEvent, once/First semantics, TypeBehavior.Events). Use this for any notification that fans out to listeners without returning a result.
---

# Character event architecture

Use this skill for notifications that should fan out to character-local
listeners without returning a behavior result.

Each `Base` owns one `Events` instance. `Events.new(Base)` creates a
per-character subscription table keyed by an arbitrary event name. Subscribe
with:

```luau
local subscription = base.Events:Subscribe("TargetChanged", function(data)
    -- data is the value passed to Dispatch
end, true, base.Events.SubscribeEnum.First)
```

Callbacks receive one argument, the value passed to `Dispatch`. `once = true`
unsubscribes the subscription before its callback runs. `First` inserts at the
front; all other positions append. The returned subscription has
`Unsubscribe()`. A callback can also be removed by passing the original
callback to `Unsubscribe`.

## Creating and dispatching an event

1. Choose a stable, character-scoped event name and document its payload shape
   near the producer or in the related type.
2. Add the producer at the point where the state transition is known. Call
   `base.Events:Dispatch("EventName", payload)`.
3. Subscribe in the owning behavior/mod script and retain the subscription when
   it may need to be removed.
4. Add or update `TypeBehavior.Events` if the public method or callback shape
   changes.

`Dispatch` returns `false` when there are no listeners and `true` when at least
one active subscription ran. It snapshots the listener list, safely handles
unsubscribe-during-dispatch, and warns when a callback raises. Do not swallow
producer errors or use events as a replacement for a function that needs a
return value.

Character-bound events can also arrive from `CharacterAPI`: the internal
`CharacterEvent` bindable calls `_eventRecieved`, which forwards the event name
and arguments to `Base.Events:Dispatch`. Keep external event names and payloads
compatible with local subscribers.

Call `Events:Destroy()` during character teardown so subscriptions and the
`Base` reference are released. Avoid dispatching after destruction.

## Impact zones

Changing an event name affects every producer and subscriber. Changing a
payload affects callback code and any external `CharacterEvent` sender.
Changing ordering or once semantics affects gameplay timing, so prefer a new
event or explicit subscription position over silently changing existing
behavior.