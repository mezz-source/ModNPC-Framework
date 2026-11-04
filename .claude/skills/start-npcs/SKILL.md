---
name: start-npcs
description: Use when a playtest needs ModNPC characters running - registering/starting NPCs with API.startCharacter(model), spawning one or two test NPCs for a fight, or when NPCs sit inert in play mode (still have `_UNLOADED`, no bars, no AI). Use this whenever the user says "start the npc", "register the npc", "spawn a modnpc to test", or a test needs live Base state, even if they don't mention startCharacter.
---

# Starting ModNPCs for testing

Any NPCs named 'modnpc' in workspace at time of playtest will automatically be started. There are usually 1 or 2 NPCs you made see preinitialized. `src/server/init.server.luau` runs `Core.init()`
and the auto-start loop over `workspace`.
To get a live character, a server Script has to call:

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

## The test NPC: `ServerStorage.CLAUDE_MODNPC`

There is always a sample ModNPC at `ServerStorage.CLAUDE_MODNPC`, kept in the
place for testing. It's a valid, unstarted ModNPC (it still has `_UNLOADED`).
Use it as the default test character instead of whatever is in `workspace`:

- **Clone it, never start or edit the original.** Clone into `workspace`, give
  each clone a distinct name (`CLAUDE_MODNPC_A`, `CLAUDE_MODNPC_B`, ...), and
  start the clones. Starting a clone changes it (removes `_UNLOADED`, adds bars
  and so on), so the original has to stay pristine.
- Clone as many as the test needs: one for a solo check, two for a fight.
  `PivotTo` each clone so they don't stack on top of each other.
- Cloning **inside the temp Script at play time** (the default below) means the
  clones are thrown away when play stops. There's nothing to clean up except the
  Script.
- Per-test config tweaks go on the clone's config values, not the original's.
  Clones made at play time are fresh copies, so change their values in the temp
  Script before calling `startCharacter`, or live during play.
- Models already in `workspace` (e.g. the user's own `modnpc`) are the user's.
  Only start them if the user asks.

## Steps (Roblox Studio MCP)

1. **Edit mode** (`get_studio_state`; stop play first if needed). Instances made
   during play are thrown away when play stops, and the Script has to exist
   before play starts.
2. Check `ServerStorage.CLAUDE_MODNPC` exists (`execute_luau`, Edit datamodel).
   If it's missing, tell the user rather than building a substitute.
3. Insert the starter Script with `execute_luau` (Edit datamodel). It clones
   the sample, places the clones, and starts them:

   ```lua
   local s = Instance.new("Script")
   s.Name = "_TEMP_StartNPCs"
   s.Source = [[
   local ServerStorage = game:GetService("ServerStorage")
   local API = require(game:GetService("ServerScriptService"):WaitForChild("ModNPCServer"):WaitForChild("API"):WaitForChild("v1"):WaitForChild("API"))

   local TEMPLATE = ServerStorage:WaitForChild("CLAUDE_MODNPC")

   -- one entry per clone: name and where to put it
   local SPAWNS = {
   	{ name = "CLAUDE_MODNPC_A", cf = CFrame.new(0, 5, 0) },
   	{ name = "CLAUDE_MODNPC_B", cf = CFrame.new(0, 5, 20) * CFrame.Angles(0, math.pi, 0) },
   }

   _G.T = _G.T or { Bases = {} }

   for _, spawn in SPAWNS do
   	local model = TEMPLATE:Clone()
   	model.Name = spawn.name
   	model:PivotTo(spawn.cf)
   	model.Parent = workspace
   	local ok, res = pcall(API.startCharacter, model)
   	if ok then
   		_G.T.Bases[spawn.name] = res
   	else
   		warn("[StartNPCs] failed:", spawn.name, res)
   	end
   end
   ]]
   s.Parent = game:GetService("ServerScriptService")
   ```

   Drop the second `SPAWNS` entry for a solo test. To start a model that's
   already in `workspace` (only when the user asks), call
   `API.startCharacter(workspace:WaitForChild(name, 10))` instead of cloning.
4. Start play (`start_stop_play`). Wait about 8s before measuring anything;
   startup Heartbeats hitch.
5. Check it started. The console shows `Starting character: <name>` and no
   `[StartNPCs]` warnings. Also, `workspace.<name>._UNLOADED` should be gone
   (`execute_luau`, Server datamodel).
6. **Clean up.** Stop play, then in Edit mode destroy `ServerScriptService._TEMP_StartNPCs`.
   Play-time clones are already gone. If you cloned anything in Edit mode,
   destroy it too. Never leave the temp Script in the place, and never modify or
   remove `ServerStorage.CLAUDE_MODNPC`.

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
