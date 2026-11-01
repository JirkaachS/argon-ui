--!nocheck
-- Load and performance bench, public API only, so the same workload runs against v1 and v2.
-- Usage, from the repository root:
--   lune run bench/compare.luau -- <bundle.luau> [tabs] [controlsPerTab]        the main workload
--   lune run bench/compare.luau -- <bundle.luau> [tabs] [controlsPerTab] flow   the usual flow
-- Each run is its own process (the sandbox is stateful). Times are Lune milliseconds on this
-- machine: compare runs made one after the other, not across machines. Network round trips
-- cannot be timed here, so calls to HttpGet, thumbnails and loadstring are counted instead.

local process = require("@lune/process")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local sandbox = require("../tests/sandbox")

local path = process.args[1] or "argon-ui.luau"
local TABS = tonumber(process.args[2]) or 10
local PER_TAB = tonumber(process.args[3]) or 40
local SCENARIO = process.args[4] or "main"
local env = sandbox.environment
local Color3 = env.Color3

-- v1 fetches the Lucide index with loadstring; give it a working one so its path is measured.
env.loadstring = function(source, name)
	sandbox.network.loadstrings = (sandbox.network.loadstrings or 0) + 1
	local ok, fn = pcall(luau.load, source, { debugName = name or "loadstring", environment = env })
	if ok then return fn end
	return nil, fn
end

local results = {}
local function record(name, value, unit)
	results[#results + 1] = { name = name, value = value, unit = unit or "" }
end
local function ms(seconds) return math.floor(seconds * 100000 + 0.5) / 100 end
local clock = os.clock

local function report(Argon)
	print(("# %s (%s, %s, %d tabs x %d controls)"):format(path, Argon.Version, SCENARIO, TABS, PER_TAB))
	for _, result in ipairs(results) do
		print(("%-66s %s %s"):format(result.name, tostring(result.value), result.unit))
	end
	local unexpected = 0
	for _, message in ipairs(sandbox.warnings) do
		if not message:find("Duplicate configuration flag") then unexpected += 1 end
	end
	print(("warnings %d, handler errors %d"):format(unexpected, #sandbox.signalErrors))
end

-- ---------- the mixed workload ----------
local options = {}
for index = 1, 30 do options[index] = "Option " .. index end
local function buildTab(tabIndex, target)
	local tab = target:CreateTab("Tab " .. tabIndex, "zap")
	local made = 0
	local section = 0
	while made < PER_TAB do
		if made % 10 == 0 then
			section += 1
			tab:CreateSection("Section " .. section)
		end
		local id = ("%d_%d"):format(tabIndex, made)
		local slot = made % 10
		if slot == 0 then tab:CreateToggle({ Name = "Toggle " .. id, Flag = "T" .. id, CurrentValue = false, Callback = function() end })
		elseif slot == 1 then tab:CreateSlider({ Name = "Slider " .. id, Flag = "S" .. id, Range = { 0, 100 }, Increment = 1, CurrentValue = 50, Callback = function() end })
		elseif slot == 2 then tab:CreateDropdown({ Name = "Dropdown " .. id, Flag = "D" .. id, Options = options, CurrentOption = { "Option 1" }, Callback = function() end })
		elseif slot == 3 then tab:CreateButton({ Name = "Button " .. id, Callback = function() end })
		elseif slot == 4 then tab:CreateInput({ Name = "Input " .. id, Flag = "I" .. id, PlaceholderText = "Type", Callback = function() end })
		elseif slot == 5 then tab:CreateKeybind({ Name = "Keybind " .. id, Flag = "K" .. id, CurrentKeybind = "None", Callback = function() end })
		elseif slot == 6 then tab:CreateColorPicker({ Name = "Color " .. id, Flag = "C" .. id, Color = Color3.fromRGB(120, 80, 255), Callback = function() end })
		elseif slot == 7 then tab:CreateLabel("Label " .. id)
		elseif slot == 8 then tab:CreateToggle({ Name = "Toggle B " .. id, Flag = "TB" .. id, CurrentValue = true, Description = "A short description", Callback = function() end })
		else tab:CreateParagraph({ Title = "Paragraph " .. id, Content = "Some explanatory text for this row." }) end
		made += 1
	end
	return tab
end

-- ---------- load ----------
local source = fs.readFile(path)
record("bundle size", #source, "bytes")
local compileTimes = {}
for run = 1, 5 do
	local start = clock()
	luau.compile(source)
	compileTimes[run] = clock() - start
end
table.sort(compileTimes)
record("compile (median of 5)", ms(compileTimes[3]), "ms")

local m0 = sandbox.metrics()
local filesBefore = 0
for _ in pairs(sandbox.files) do filesBefore += 1 end
local start = clock()
local Argon = sandbox.load(path)
local loadTime = clock() - start
record("load (compile + top level)", ms(loadTime), "ms")
local m1 = sandbox.metrics()
local filesAfter = 0
for _ in pairs(sandbox.files) do filesAfter += 1 end
record("instances created at load", m1.created - m0.created)
record("files written at load", filesAfter - filesBefore)
record("timers queued at load", m1.delaysPending - m0.delaysPending)

-- ---------- the usual flow, in a fresh process: build, restore, let the library open ----------
-- No Loading option and no FinishLoading call, as in the README quick start. 1.x opens on a
-- fixed 0.93 s timer that starts at CreateWindow (in Roblox its build time counts towards it);
-- 2.0 opens once the script has gone quiet. Frames are 1/60 s.
if SCENARIO == "flow" then
	start = clock()
	local flow = Argon:CreateWindow({ Name = "Flow", GuiName = "BenchFlow",
		ConfigurationSaving = { Enabled = true, FolderName = "Bench", FileName = "flow" } })
	for tabIndex = 1, TABS do buildTab(tabIndex, flow) end
	Argon:LoadConfiguration()
	local flowCpu = clock() - start
	local flowFrames = 0
	local worst = 0
	while flow:IsLoading() and flowFrames < 3600 do
		local frameStart = clock()
		sandbox.step(1)
		worst = math.max(worst, clock() - frameStart)
		flowFrames += 1
	end
	record("usual flow: script time from CreateWindow to the end of the script", ms(flowCpu), "ms")
	record("usual flow: frames after the script until the window is open", flowFrames)
	record("usual flow: the same in seconds at 60 fps", math.floor(flowFrames / 60 * 100 + 0.5) / 100, "s")
	record("usual flow: worst frame until the window is open", ms(worst), "ms")
	report(Argon)
	return
end

-- ---------- CreateWindow ----------
local net0 = { http = sandbox.network.httpGets, thumbs = sandbox.network.thumbnails, ls = sandbox.network.loadstrings or 0 }
start = clock()
local window = Argon:CreateWindow({ Name = "Bench", GuiName = "BenchGui", Loading = "manual",
	ConfigurationSaving = { Enabled = true, FolderName = "Bench", FileName = "bench" } })
record("CreateWindow", ms(clock() - start), "ms")
local m2 = sandbox.metrics()
record("instances after CreateWindow", m2.created - m1.created)
record("HttpGet calls during CreateWindow", sandbox.network.httpGets - net0.http)
record("thumbnail calls during CreateWindow", sandbox.network.thumbnails - net0.thumbs)
record("loadstring calls during CreateWindow", (sandbox.network.loadstrings or 0) - net0.ls)

-- ---------- build ----------
local perTab = {}
start = clock()
for tabIndex = 1, TABS do
	local tabStart = clock()
	buildTab(tabIndex, window)
	perTab[tabIndex] = clock() - tabStart
end
local buildTime = clock() - start
local m3 = sandbox.metrics()
record(("Create* for %d controls (%d tabs x %d), host thread"):format(TABS * PER_TAB, TABS, PER_TAB), ms(buildTime), "ms")
record("instances created by the Create* calls", m3.created - m2.created)
record("first tab build", ms(perTab[1]), "ms")
record("last tab build", ms(perTab[TABS]), "ms")
record("last tab / first tab", math.floor(perTab[TABS] / math.max(perTab[1], 1e-9) * 100 + 0.5) / 100, "x")

-- ---------- restore a configuration ----------
Argon:SaveConfiguration()
start = clock()
Argon:LoadConfiguration()
record(("LoadConfiguration (%d flags)"):format(TABS * PER_TAB * 0.7), ms(clock() - start), "ms")

-- ---------- reveal: what the frames after the build cost ----------
local frameTimes = {}
local framesUntilReady = 0
start = clock()
window:FinishLoading()
local revealCost = clock() - start
for frame = 1, 600 do
	local frameStart = clock()
	sandbox.step(1)
	frameTimes[frame] = clock() - frameStart
	if not window:IsLoading() and framesUntilReady == 0 then framesUntilReady = frame end
end
local maxFrame, totalFrames = 0, 0
for _, t in ipairs(frameTimes) do
	totalFrames += t
	if t > maxFrame then maxFrame = t end
end
record("FinishLoading call", ms(revealCost), "ms")
record("frames until the window is open after FinishLoading", framesUntilReady)
record("library work in the 600 frames after (background mounting)", ms(totalFrames), "ms")
record("worst single frame after FinishLoading", ms(maxFrame), "ms")
local m4 = sandbox.metrics()
record("instances once every tab is built", m4.created - m2.created)
record("instances per control (everything mounted, structure included)", math.floor((m4.created - m2.created) / (TABS * PER_TAB) * 100 + 0.5) / 100)

-- ---------- theme switch, everything built ----------
start = clock()
Argon:SetTheme("Ocean")
record("SetTheme with everything built (synchronous part)", ms(clock() - start), "ms")
start = clock()
sandbox.step(30)
record("theme catch-up over the next 30 frames", ms(clock() - start), "ms")

-- ---------- notifications ----------
local before = sandbox.metrics().created
start = clock()
for index = 1, 20 do Argon:Notify({ Title = "Bench " .. index, Content = "Body text", Duration = 0.1 }) end
record("20 notifications", ms(clock() - start), "ms")
record("instances created by 20 notifications", sandbox.metrics().created - before)

-- ---------- idle ----------
sandbox.advance(5)
local idle = sandbox.metrics()
record("idle: UserInputService.InputBegan handlers", idle.handlers.InputBegan)
record("idle: UserInputService.InputChanged handlers", idle.handlers.InputChanged)
record("idle: UserInputService.InputEnded handlers", idle.handlers.InputEnded)
record("idle: Heartbeat + RenderStepped handlers", idle.handlers.Heartbeat + idle.handlers.RenderStepped)
record("idle: endless tweens running", idle.runningLoops)
local pending = 0
for _, entry in ipairs(sandbox.scheduled) do if not entry.cancelled then pending += 1 end end
record("idle: timers pending", pending)

report(Argon)
