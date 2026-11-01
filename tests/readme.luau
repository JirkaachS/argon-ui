--!nocheck
-- Runs every ```luau example in README.md against the bundle, in order, so the documentation
-- cannot drift from the API. An example passes when it runs without an error, a warning or a
-- handler error. Names the examples assume (Window, Tab, toggle, element, ...) are provided.
-- Run from the repository root: lune run tests/readme.luau [-- path/to/argon-ui.luau]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local sandbox = require("./sandbox")

local PATH = process.args[1] or "argon-ui.luau"
local env = sandbox.environment
local Argon = sandbox.load(PATH)

local passed, failed, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		passed += 1
		print(("  PASS  %s"):format(name))
	else
		failed += 1
		failures[#failures + 1] = name .. (detail ~= nil and (" — " .. tostring(detail)) or "")
		print(("  FAIL  %s%s"):format(name, detail ~= nil and (" — " .. tostring(detail)) or ""))
	end
end

-- The fixture the examples talk about: a window with a tab, a toggle and a lockable control.
local fixture = {}
local function ensureFixture()
	if fixture.Window and not fixture.Window._destroyed then return end
	fixture.Window = Argon:CreateWindow({ Name = "Docs", GuiName = "DocsGui",
		ConfigurationSaving = { Enabled = true, FolderName = "Docs", FileName = "docs" } })
	fixture.Tab = fixture.Window:CreateTab("Docs", "book-open")
	fixture.toggle = fixture.Tab:CreateToggle({ Name = "Docs toggle", Flag = "DocsToggle", CurrentValue = false })
	fixture.element = fixture.Tab:CreateButton({ Name = "Docs button", Callback = function() end })
	fixture.Window:FinishLoading()
end

local readme = fs.readFile("README.md"):gsub("\r\n", "\n")
local examples = {}
local position = 1
local currentHeading = "top"
while true do
	local start, finish, code = readme:find("```luau\n(.-)\n```", position)
	if not start then break end
	for heading in readme:sub(position, start):gmatch("\n## ([^\n]+)") do currentHeading = heading end
	examples[#examples + 1] = { heading = currentHeading, code = code }
	position = finish + 1
end
check("README has examples", #examples >= 10, #examples)

for index, example in ipairs(examples) do
	ensureFixture()
	local warningsBefore, errorsBefore = #sandbox.warnings, #sandbox.signalErrors
	local globals = setmetatable({
		loadstring = function() return function() return Argon end end,
		print = function() end,
		Window = fixture.Window, Tab = fixture.Tab, toggle = fixture.toggle, element = fixture.element,
		myFrame = env.Instance.new("Frame"),
		rejoin = function() end, emptyContainer = function() end, cancelDownload = function() end,
		load = function() end, rename = function() end, remove = function() end,
		tabsToBuild = { { Name = "Combat" }, { Name = "Visuals" } }, buildTab = function() end,
		conquestIsOn = true, Argon = Argon,
	}, { __index = env })
	-- luau.load copies the environment table, so copy the sandbox globals in explicitly
	for key, value in pairs(env) do
		if rawget(globals, key) == nil then globals[key] = value end
	end
	local ok, err = pcall(function()
		local chunk = luau.load(example.code, { debugName = "README example " .. index, environment = globals, injectGlobals = true })
		chunk()
		sandbox.step(5)
	end)
	local newWarnings = {}
	for at = warningsBefore + 1, #sandbox.warnings do newWarnings[#newWarnings + 1] = sandbox.warnings[at] end
	for at = errorsBefore + 1, #sandbox.signalErrors do newWarnings[#newWarnings + 1] = sandbox.signalErrors[at] end
	check(("example %d (%s) runs cleanly"):format(index, example.heading), ok and #newWarnings == 0,
		not ok and err or table.concat(newWarnings, " | "))
end

print(("\n================ %d passed, %d failed ================"):format(passed, failed))
if failed > 0 then
	print("\nFailures:")
	for _, name in ipairs(failures) do print("  - " .. name) end
	process.exit(1)
end
process.exit(0)
