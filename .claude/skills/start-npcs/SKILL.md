---
name: start-npcs
description: Use when a playtest needs ModNPC characters running - registering/starting NPCs with API.startCharacter(model), spawning one or two test NPCs for a fight, or when NPCs sit inert in play mode (still have `_UNLOADED`, no bars, no AI). Use this whenever the user says "start the npc", "register the npc", "spawn a modnpc to test", or a test needs live Base state, even if they don't mention startCharacter.
---

# Starting ModNPCs for testing

Nothing starts NPCs automatically. `src/server/init.server.luau` runs `Core.init()`
and the auto-start loop over `workspace` is commented out on purpose. Leave it
that way. To get a live character, a server Script has to call:

```lua
API.startCharacter(model)  -- returns the Base; errors if the model isn't a valid ModNPC
```

`startCharacter` is just `Base.new(model)`. It removes `_UNLOADED`, validates the
model (`CharacterAPI:ValidateCharacter`), then builds every Base module (config,
bars, tasks, AI). A model that fails validation throws
`Invalid character provided to Base (...)`. Read the reason in the console.

## Where to call it from (this matters)

| Caller | Works? |
| --- | --- |
| A temporary **Script** in `ServerScriptService` | Yes. Server Scripts share the module cache, so it gets the same `API` that `Core.init()` set up. |
| `execute_luau` (MCP / command bar) | **No.** `require()` there has its own module state, so you get a second, uninitialised API and Base that isn't wired to the running game. |
| Editing `init.server.luau` | Avoid. It's the real entry point and the user disabled the loop deliberately. |

The API module lives at `ServerScriptService.ModNPCServer.API.v1.API` (Rojo maps
`src/server` to `ModNPCServer`).

## Steps (Roblox Studio MCP)

1. **Edit mode** (`get_studio_state`; stop play first if needed). Instances made
   during play are thrown away when play stops, and the Script has to exist
   before play starts.
2. Make sure the models exist in `workspace`. If a fight needs a second NPC,
   clone the existing one in Edit mode and give it a distinct name (e.g.
   `modnpc TEMPTEST`). Any model you don't start stays an inert dummy, and attacks
   on it take the plain-Humanoid damage path.
3. Insert the starter Script with `execute_luau` (Edit datamodel). Name the
   models you want explicitly:

   ```lua
   local s = Instance.new("Script")
   s.Name = "_TEMP_StartNPCs"
   s.Source = [[
   local API = require(game:GetService("ServerScriptService"):WaitForChild("ModNPCServer"):WaitForChild("API"):WaitForChild("v1"):WaitForChild("API"))

   local NAMES = { "modnpc" } -- models in workspace to start

   for _, name in NAMES do
   	local model = workspace:WaitForChild(name, 10)
   	if not model then
   		warn("[StartNPCs] not found:", name)
   		continue
   	end
   	local ok, err = pcall(API.startCharacter, model)
   	if not ok then
   		warn("[StartNPCs] failed:", name, err)
   	end
   end
   ]]
   s.Parent = game:GetService("ServerScriptService")
   ```

   To start everything that looks like an NPC instead, loop over
   `workspace:GetChildren()` and start each model whose name contains `modnpc`.
   That's what the old boot loop did.
4. Start play (`start_stop_play`). Wait about 8s before measuring anything;
   startup Heartbeats hitch.
5. Check it started. The console shows `Starting character: <name>` and no
   `[StartNPCs]` warnings. Also, `workspace.<name>._UNLOADED` should be gone
   (`execute_luau`, Server datamodel).
6. **Clean up.** Stop play, then in Edit mode destroy `ServerScriptService._TEMP_StartNPCs`
   and any cloned test models. Never leave the temp Script in the place.

## Notes

- Hold on to the returned Base only inside the temp Script. Nothing outside the
  server VM can reach it. To drive a live Base (call functions, read State), use
  a temporary mod: a ModuleScript under `<model>.ModNPC.Mods` that returns
  `{ init = function(base) ... end }`. Write results to an attribute on the model
  and read the attribute with `execute_luau`.
- Starting the same model twice builds two Bases on one character. Don't.
- If behaviour looks stale, check that Rojo is still syncing (compare the Studio
  Source against the disk) before blaming the code.
- `get_console_output` is huge. The useful lines are at the tail.
