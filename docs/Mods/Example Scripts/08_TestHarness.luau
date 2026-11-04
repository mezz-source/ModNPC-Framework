-- 08_TestHarness: a throwaway mod that tests a live character from the inside.
--
-- A mod runs in the character's real Base, so it can call anything the game can. Nothing outside the server can reach
-- a Base, and a Studio command bar require() gets its own copy of module state. So the test goes in the character, and
-- the results come out as attributes on the model, which the Explorer or the Studio MCP can read from outside.
--
-- The pattern:
--   1. init returns at once; the test runs in a task.spawn so it never blocks startup
--   2. wait for the character to settle
--   3. put it in a known state with the functions the game uses
--   4. check, recording a line per check
--   5. pcall the whole thing and ALWAYS set the done flag, so a crash still reports
--
-- Read the results: <Character>:GetAttribute("TestLog") once <Character>:GetAttribute("TestDone") is true.
-- Remove the mod afterwards; it would run on every playtest otherwise.

local ServerScriptService = game:GetService("ServerScriptService")
local TypeBehavior = require(ServerScriptService.ModNPCServer.Types.v1.TypeBehavior)

type Base = TypeBehavior.Base

local FunctionEnum = TypeBehavior.FunctionEnum

local SETTLE_TIME = 8

local module = {}

function module.init(base: Base)
	local F = base.Functions
	local lines: { string } = {}
	local failures = 0

	local function check(label: string, passed: boolean, detail: string?)
		if not passed then
			failures += 1
		end
		table.insert(lines, string.format("%s  %s%s", if passed then "PASS" else "FAIL", label, if detail then " (" .. detail .. ")" else ""))
		base.Character:SetAttribute("TestLog", table.concat(lines, "\n")) -- publish as we go
	end

	task.spawn(function()
		task.wait(SETTLE_TIME)

		local ok, runError = pcall(function()
			-- Stamina: drain it, then top it up, through the functions the game uses
			F:CallFunction(FunctionEnum.RestoreStamina, 1000, "test")
			local current, max = F:CallFunction(FunctionEnum.GetStamina)
			check("stamina is full after a restore", current == max, string.format("%.0f/%.0f", current, max))

			F:CallFunction(FunctionEnum.BreakStamina, "test")
			check("breaking stamina exhausts the character", F:CallFunction(FunctionEnum.IsExhausted) == true)

			-- Hooks: a First hook sees the call, and unsubscribing stops it
			local seen = 0
			local hook = base:SubscribeFunction(FunctionEnum.RestoreStamina, function()
				seen += 1
			end, "First")
			F:CallFunction(FunctionEnum.RestoreStamina, 1, "test")
			check("a First hook runs on the call", seen == 1, "seen=" .. seen)
			if hook then
				hook:Unsubscribe()
			end
			F:CallFunction(FunctionEnum.RestoreStamina, 1, "test")
			check("an unsubscribed hook stays quiet", seen == 1, "seen=" .. seen)

			-- Skills: a probabilistic rule becomes a number with a big sample
			F:CallFunction(FunctionEnum.RestoreStamina, 1000, "test")
			local wins = 0
			for _ = 1, 2000 do
				if F:CallFunction(FunctionEnum.RollSkill, "Agility").Success then
					wins += 1
				end
			end
			check("Agility succeeds sometimes but not always", wins > 0 and wins < 2000, "rate=" .. wins / 2000)
		end)

		if not ok then
			check("test run finished without an error", false, tostring(runError))
		end
		table.insert(lines, string.format("%d failure(s)", failures))
		base.Character:SetAttribute("TestLog", table.concat(lines, "\n"))
		base.Character:SetAttribute("TestDone", true)
	end)
end

return module
