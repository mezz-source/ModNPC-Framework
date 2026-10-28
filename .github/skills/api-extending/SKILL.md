# Extending the character and API layers

Use this skill when adding or changing a low-level operation exposed through a
character's API. The API layer is for primitive, reusable operations such as
movement, impulses, animation, validation, and direct damage. Do not put
high-level behavior such as attacking or wandering here; those belong in the
function system.

## Request flow

`CharacterAPI` is the character-facing adapter. Its methods build a request
containing:

```luau
{
    ModuleName = "Movement",
    Function = "applyImpulse",
    Arguments = { characterModel, velocityChange },
}
```

`CharacterAPI:RequestAPI` sends that request to `Base.Router:Request`.
`Router` invokes the shared `ModFunctions.Request` bindable, which reaches
`API._internalRequest`/`API.requestRecieved`. The API validates the request,
finds the registered module, calls the named function with `unpack(Arguments)`,
and converts its `ModuleResponse` into an `APIResponse`. Use
`RequestAPIData` when the caller needs `response.Data`; use `RequestAPI` when
the complete response matters.

Errors are not silently ignored: the API returns `Success = false`, and
`CharacterAPI:RequestAPI` warns when a request fails. Preserve this behavior.

## Adding a low-level operation

1. Add or reuse a module under `src/server/API/v1/Modules`. A module function
   should validate its inputs and return a `TypeModuleResponse.ModuleResponse`
   with `Success` and `PassResponse`. Set `PassResponse = true` when the
   module's status/data must be exposed to the caller; otherwise the API
   reports that the request was processed.
2. Add the module name and function string to
   `src/server/Types/v1/TypeAPIFunctions.luau`. Keep the string exactly equal
   to the exported module function name. Add a new union member in `Module`,
   the matching `Modules` entry, and the typed `Functions` table entry.
3. Add a typed wrapper to `CharacterAPI.luau`. Select the module/function from
   `TypeAPIFunctions`, pass `self.Character` first when the module expects a
   character, and choose `RequestAPI` versus `RequestAPIData` deliberately.
   This is where base controls such as `ApplyImpulse` and
   `ApplyAngularImpulse` are stored and forwarded to the API module.
4. If the operation is also a behavior function, wire it separately through
   `Functions.luau` and `TypeBehavior.luau`; adding an API endpoint alone does
   not make it callable through `Base.Functions`.
5. Update directly related types and callers, then check both the success and
   failure response paths.

## Adding a module

`API/v1/Core.luau` iterates the direct children of `API/v1/Modules`, requires
each module, calls its optional `init(API)`, and passes the resulting map to
`API.init`. Therefore a new top-level module is normally one ModuleScript in
that directory. A folder must expose an `init.luau` entry point, as
`ContentDelivery` does; do not assume nested scripts are automatically
registered.

Keep module functions stateless with respect to a particular character unless
the existing module pattern explicitly requires state. Use
`TypeRequests.Enums.StatusCode` and the repository's response helper pattern.
Do not call another module by reaching into its implementation when a request
or existing helper is the intended boundary.

## Impact zones

- Changing a module name or function string affects
  `TypeAPIFunctions`, every `CharacterAPI` wrapper, and any direct API callers.
- Changing argument order or return data affects the module implementation,
  wrapper, `TypeModuleResponse`, `TypeRequests`, and all callers that consume
  `Data`.
- Changing `CharacterAPI` signatures affects `TypeBehavior.CharacterAPI`,
  `Base`, mod scripts, and behavior modules.
- Adding a high-level action here instead of to `Functions` bypasses
  subscriptions and makes module-to-module orchestration harder to replace.