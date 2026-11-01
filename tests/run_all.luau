--!nocheck
-- Runs every suite, each in its own process (the sandbox is stateful), and prints one line per
-- suite. Run from the repository root:
--   lune run tests/run_all.luau                       checks argon-ui.luau is current, then tests it
--   lune run tests/run_all.luau -- path/to/bundle     tests another bundle (skips the build check)

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local SUITES = { "run", "v2_core", "controls_a", "controls_b", "display", "readme" }

local bundle = process.args[1]
local run = process.exec or process.spawn

local function lune(args)
	local result = run("lune", args)
	return result.ok, (result.stdout or "") .. (result.stderr or "")
end

local failed = 0
if not bundle then
	local ok, output = lune({ "run", "build.luau", "--", "--check" })
	print((ok and "  ok    " or "  FAIL  ") .. "build check: " .. (output:match("check [%w ]+:[^\n]*") or output:sub(1, 200)))
	if not ok then failed += 1 end
end

local totalPassed, totalFailed = 0, 0
for _, suite in ipairs(SUITES) do
	local args = { "run", "tests/" .. suite .. ".luau" }
	if bundle then
		table.insert(args, "--")
		table.insert(args, bundle)
	end
	local ok, output = lune(args)
	local passed, failures = output:match("(%d+) passed, (%d+) failed")
	passed, failures = tonumber(passed), tonumber(failures)
	if passed then
		totalPassed += passed
		totalFailed += failures
	end
	local summary = passed and ("%d passed, %d failed"):format(passed, failures) or "did not finish"
	print(("%s%-12s %s"):format(ok and "  ok    " or "  FAIL  ", suite, summary))
	if not ok then
		failed += 1
		for line in output:gmatch("[^\n]+") do
			if line:find("FAIL") or line:find("%]:%d+:") or line:find("error") then
				print("          " .. line)
			end
		end
	end
end

print(("\n%d passed, %d failed across %d suites"):format(totalPassed, totalFailed, #SUITES))
if failed > 0 then
	stdio.ewrite(("%d suite(s) failed\n"):format(failed))
	process.exit(1)
end
process.exit(0)
