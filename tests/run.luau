--!nocheck
-- Functional test for argon-ui.luau running under Lune with a Roblox API sandbox.
-- Exercises real library code: window/tab/section creation, all 18 controls, the new
-- components, and the configuration save/load round-trip.

local process = require("@lune/process")
local fs = require("@lune/fs")
-- Resolve the library whether the suite is run from the repo root or from tests/.
local ARGON_PATH = fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau"
local sandbox = require("./sandbox")

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
	if condition then
		passed += 1
		print(("  PASS  %s"):format(name))
	else
		failed += 1
		failures[#failures + 1] = name .. (detail and (" — " .. tostring(detail)) or "")
		print(("  FAIL  %s%s"):format(name, detail and (" — " .. tostring(detail)) or ""))
	end
end

local function section(title)
	print("\n== " .. title .. " ==")
end

section("load library")
local ok, Argon = pcall(sandbox.load, ARGON_PATH)
check("library loads without error", ok, not ok and Argon or nil)
if not ok then
	print("\nFATAL: cannot continue")
	process.exit(1)
end
check("version is 1.10.0", Argon.Version == "1.10.0", Argon.Version)
check("Flags table exists", type(Argon.Flags) == "table")
check("default folder is neutral", Argon.DefaultFolder == "ArgonUI", Argon.DefaultFolder)

section("create window")
local windowOk, Window = pcall(function()
	return Argon:CreateWindow({
		Name = "Test Hub",
		Theme = "Argon",
		GuiName = "ArgonUITest",
		ConfigurationSaving = { Enabled = true, FolderName = "TestHub", FileName = "config" },
	})
end)
check("CreateWindow succeeds", windowOk, not windowOk and Window or nil)
if not windowOk then
	print("\nFATAL: cannot continue")
	process.exit(1)
end
check("ScreenGui uses custom GuiName", Window.ScreenGui.Name == "ArgonUITest", Window.ScreenGui.Name)

local tabOk, Tab = pcall(function() return Window:CreateTab("Main", "zap") end)
check("CreateTab succeeds", tabOk, not tabOk and Tab or nil)
local sectionOk = pcall(function() Tab:CreateSection("Controls") end)
check("CreateSection succeeds", sectionOk)

section("existing controls")
local calls = {}
local function record(name)
	return function(value) calls[name] = value end
end

local toggle = Tab:CreateToggle({ Flag = "T_Toggle", Name = "Toggle", CurrentValue = false, Callback = record("toggle") })
toggle:Set(true)
check("toggle stores value", toggle.CurrentValue == true)
check("toggle fires callback", calls.toggle == true)

local slider = Tab:CreateSlider({ Flag = "T_Slider", Name = "Slider", Range = { 0, 100 }, Increment = 5, CurrentValue = 10, Callback = record("slider") })
slider:Set(43)
check("slider rounds to increment", slider.CurrentValue == 45, slider.CurrentValue)
check("slider clamps high", (function() slider:Set(1e6) return slider.CurrentValue end)() == 100, slider.CurrentValue)

local input = Tab:CreateInput({ Flag = "T_Input", Name = "Input", Callback = record("input") })
input:Set("hello")
check("input stores text", input.CurrentValue == "hello")

local dropdown = Tab:CreateDropdown({ Flag = "T_Dropdown", Name = "Dropdown", Options = { "A", "B" }, CurrentOption = { "A" }, Callback = record("dropdown") })
dropdown:Set({ "B" })
check("dropdown selects option", dropdown.CurrentOption[1] == "B", dropdown.CurrentOption[1])
dropdown:Set({ "Z" })
check("dropdown ignores unknown option", dropdown.CurrentOption[1] == nil or dropdown.CurrentOption[1] == "B")

local keybind = Tab:CreateKeybind({ Flag = "T_Keybind", Name = "Keybind", CurrentKeybind = "P", Callback = record("keybind") })
keybind:Set("K")
check("keybind stores key", keybind.CurrentKeybind == "K", keybind.CurrentKeybind)

local picker = Tab:CreateColorPicker({ Flag = "T_Color", Name = "Color", Color = sandbox.environment.Color3.fromRGB(10, 20, 30), Callback = record("color") })
picker:Set("#5DE1EB")
check("colorpicker parses hex", math.floor(picker.CurrentValue.R * 255 + 0.5) == 93, picker.CurrentValue.R)

local buttonRan = false
local button = Tab:CreateButton({ Name = "Button", Callback = function() buttonRan = true end })
check("button created", button ~= nil and button.Type == "Button")

check("label created", (Tab:CreateLabel("hello")).Type == "Label")
check("paragraph created", (Tab:CreateParagraph({ Title = "T", Content = "C" })).Type == "Paragraph")
check("divider created", (Tab:CreateDivider("Advanced")).Type == "Divider")
check("space created", (Tab:CreateSpace(12)).Type == "Space")
local telemetry = Tab:CreateTelemetryCard({ Title = "Live", Content = "x" })
telemetry:SetContent("updated")
check("telemetry updates content", telemetry.CurrentValue == "updated")

section("new components")
local progress = Tab:CreateProgressBar({ Name = "Progress", Maximum = 200, Callback = record("progress") })
progress:Set(50)
check("progressbar stores value", progress.CurrentValue == 50, progress.CurrentValue)
progress:Increment(25)
check("progressbar increments", progress.CurrentValue == 75, progress.CurrentValue)
progress:Set(9999)
check("progressbar clamps to maximum", progress.CurrentValue == 200, progress.CurrentValue)
progress:SetRange(0, 400)
check("progressbar setrange keeps value", progress.CurrentValue == 200, progress.CurrentValue)
check("progressbar setcolor works", (pcall(function() progress:SetColor(sandbox.environment.Color3.fromRGB(0, 255, 0)) end)))

local stepper = Tab:CreateStepper({ Flag = "T_Stepper", Name = "Stepper", Range = { 0, 2 }, Increment = 0.05, CurrentValue = 0.45, Callback = record("stepper") })
check("stepper initial value", math.abs(stepper.CurrentValue - 0.45) < 1e-9, stepper.CurrentValue)
stepper:Set(1.23)
check("stepper rounds to increment", math.abs(stepper.CurrentValue - 1.25) < 1e-9, stepper.CurrentValue)
stepper:Set(-5)
check("stepper clamps to minimum", stepper.CurrentValue == 0, stepper.CurrentValue)
check("stepper fires callback", calls.stepper == 0, calls.stepper)

local segmented = Tab:CreateSegmented({ Flag = "T_Segmented", Name = "Mode", Options = { "Safe", "Balanced", "Fast" }, CurrentOption = "Balanced", Callback = record("segmented") })
check("segmented initial value", segmented.CurrentValue == "Balanced", segmented.CurrentValue)
segmented:Set("Fast")
check("segmented selects value", segmented.CurrentValue == "Fast", segmented.CurrentValue)
check("segmented callback is a string", calls.segmented == "Fast", tostring(calls.segmented))
segmented:Set("Nope")
check("segmented rejects unknown value", segmented.CurrentValue == "Fast", segmented.CurrentValue)
segmented:Refresh({ "Safe", "Fast" })
check("segmented refresh keeps valid value", segmented.CurrentValue == "Fast", segmented.CurrentValue)
segmented:Refresh({ "One", "Two" })
check("segmented refresh resets invalid value", segmented.CurrentValue == "One", segmented.CurrentValue)

local area = Tab:CreateTextArea({ Flag = "T_TextArea", Name = "Notes", Callback = record("area") })
area:Set("alpha\nbeta\n\ngamma")
check("textarea stores text", area.CurrentValue == "alpha\nbeta\n\ngamma")
local lines = area:GetLines()
check("textarea GetLines skips blanks", #lines == 3 and lines[3] == "gamma", #lines .. " lines")

local clicked
local list = Tab:CreateList({ Name = "Items", EmptyText = "empty", Callback = function(record2) clicked = record2.Title end })
list:SetItems({ "One", { Title = "Two", Description = "second", Action = "Load" } })
check("list stores items", #list.Items == 2, #list.Items)
check("list normalizes strings", list.Items[1].Title == "One", list.Items[1].Title)
list:AddItem({ Title = "Three" })
check("list AddItem appends", #list.Items == 3, #list.Items)
list:Clear()
check("list Clear empties", #list.Items == 0, #list.Items)

section("section builders expose new components")
local built = Tab:Section({ Title = "Via section" })
for _, method in ipairs({ "ProgressBar", "Stepper", "Segmented", "TextArea", "List", "Label", "TelemetryCard", "Toggle" }) do
	check("section:" .. method .. " exists", type(built[method]) == "function")
end
local sectionToggleOk = pcall(function() built:Toggle({ Name = "From section" }) end)
check("section builder creates control", sectionToggleOk)

section("element helpers")
local locked = Tab:CreateToggle({ Name = "Lockable" })
check("SetDesc works", (pcall(function() locked:SetDesc("desc") end)))
check("SetTooltip works", (pcall(function() locked:SetTooltip("tip") end)))
check("Lock works", (pcall(function() locked:Lock("Premium") end)) and locked.Locked == true)
check("Unlock works", (pcall(function() locked:Unlock() end)) and locked.Locked == false)
check("SetVisible works", (pcall(function() locked:SetVisible(false) end)))
check("Destroy works", (pcall(function() locked:Destroy() end)))

section("configuration round-trip")
local saveOk, savePath = Argon:SaveConfiguration()
check("SaveConfiguration succeeds", saveOk, savePath)
check("config file written", sandbox.files["TestHub/config.rfld"] ~= nil,
	"paths: " .. table.concat((function() local out = {} for path in pairs(sandbox.files) do out[#out + 1] = path end return out end)(), ", "))

local saved = sandbox.decodeJson(sandbox.files["TestHub/config.rfld"])
check("saved toggle value", saved.T_Toggle == true, tostring(saved.T_Toggle))
check("saved stepper value", saved.T_Stepper == 0, tostring(saved.T_Stepper))
check("saved segmented value", saved.T_Segmented == "One", tostring(saved.T_Segmented))
check("saved textarea value", saved.T_TextArea ~= nil)
check("progressbar is not persisted", saved.Progress == nil)

-- mutate everything away from the saved state, then reload
toggle:Set(false)
stepper:Set(2)
segmented:Set("Two")
area:Set("")
slider:Set(0)
calls = {}

local loadOk, loadInfo = Argon:LoadConfiguration()
check("LoadConfiguration succeeds", loadOk, loadInfo)
check("toggle restored", toggle.CurrentValue == true, tostring(toggle.CurrentValue))
check("stepper restored", stepper.CurrentValue == 0, tostring(stepper.CurrentValue))
check("segmented restored", segmented.CurrentValue == "One", tostring(segmented.CurrentValue))
check("slider restored", slider.CurrentValue == 100, tostring(slider.CurrentValue))
check("restore fired toggle callback", calls.toggle == true, tostring(calls.toggle))
check("restore fired stepper callback", calls.stepper == 0, tostring(calls.stepper))
check("restore fired segmented callback", calls.segmented == "One", tostring(calls.segmented))

section("callback runs even when value equals default")
local applied = nil
local defaulted = Tab:CreateToggle({ Flag = "T_Default", Name = "Default true", CurrentValue = true, Callback = function(value) applied = value end })
sandbox.files["TestHub/config.rfld"] = sandbox.encodeJson({ T_Default = true })
applied = nil
Argon:LoadConfiguration()
check("callback fires for unchanged value", applied == true, tostring(applied))
check("control keeps value", defaulted.CurrentValue == true)

section("pending flags for controls built later")
sandbox.files["TestHub/config.rfld"] = sandbox.encodeJson({ T_Toggle = true, NotBuiltYet = 77 })
Argon:LoadConfiguration()
check("unknown flag retained", Argon:GetFlagValue("NotBuiltYet") == 77, tostring(Argon:GetFlagValue("NotBuiltYet")))
local lateValue
local late = Tab:CreateSlider({ Flag = "NotBuiltYet", Name = "Late", Range = { 0, 100 }, Increment = 1, CurrentValue = 0, Callback = function(value) lateValue = value end })
check("late control hydrates from pending value", late.CurrentValue == 77, tostring(late.CurrentValue))
check("late control callback fired", lateValue == 77, tostring(lateValue))

sandbox.files["TestHub/config.rfld"] = sandbox.encodeJson({ Orphan = "keep-me" })
Argon:LoadConfiguration()
Argon:SaveConfiguration()
local resaved = sandbox.decodeJson(sandbox.files["TestHub/config.rfld"])
check("orphan flag preserved on save", resaved.Orphan == "keep-me", tostring(resaved.Orphan))

section("dropdown restores selection once options appear")
local dynamicValue
local dynamic = Tab:CreateDropdown({ Flag = "T_Dynamic", Name = "Dynamic", Options = {}, Callback = function(selection) dynamicValue = selection[1] end })
dynamic:Set({ "Later" })
check("selection deferred while option missing", dynamic.CurrentOption[1] == nil)
dynamic:Refresh({ "Later", "Other" })
check("selection applied after Refresh", dynamic.CurrentOption[1] == "Later", tostring(dynamic.CurrentOption[1]))
check("refresh fired callback", dynamicValue == "Later", tostring(dynamicValue))

section("flag helpers and diagnostics")
local seen = {}
local unbind = Argon:OnFlagChanged(function(flag, value) seen[flag] = value end)
toggle:Set(false)
check("OnFlagChanged observes changes", seen.T_Toggle == false, tostring(seen.T_Toggle))
unbind()
seen = {}
toggle:Set(true)
check("unbind stops listener", seen.T_Toggle == nil)

check("SetFlagValue applies", (function()
	Argon:SetFlagValue("T_Slider", 25)
	return slider.CurrentValue == 25
end)(), slider.CurrentValue)
check("GetFlags returns snapshot", type(Argon:GetFlags()) == "table" and Argon:GetFlags().T_Toggle == true)

local stats = Argon:GetConfigurationStats()
check("stats report path", stats.Path == "TestHub/config.rfld", tostring(stats.Path))
check("stats report ready", stats.Ready == true)
check("stats count flags", stats.RegisteredFlags >= 8, stats.RegisteredFlags)

section("reset and delete")
Argon:SaveConfiguration()
check("file exists before delete", sandbox.files["TestHub/config.rfld"] ~= nil)
local resetOk = Argon:ResetConfiguration()
check("ResetConfiguration succeeds", resetOk)
check("file removed", sandbox.files["TestHub/config.rfld"] == nil)
check("pending cleared", next(Argon._pendingFlags) == nil)

section("custom file extension is respected")
local jsonWindow = Argon:CreateWindow({
	Name = "Json Hub",
	GuiName = "ArgonUIJson",
	ConfigurationSaving = { Enabled = true, FolderName = "JsonHub", FileName = "settings.json" },
})
local jsonTab = jsonWindow:CreateTab("Main", "zap")
jsonTab:CreateToggle({ Flag = "J_Toggle", Name = "Toggle", CurrentValue = true })
Argon:SaveConfiguration()
check("extension not double-appended", sandbox.files["JsonHub/settings.json"] ~= nil,
	table.concat((function() local out = {} for path in pairs(sandbox.files) do out[#out + 1] = path end return out end)(), ", "))

section("themes, notifications, dialog")
check("GetThemes lists all built-ins", #Argon:GetThemes() == 10, #Argon:GetThemes())
check("Amethyst is not a copy of Argon", (function()
	local argon, amethyst = Argon.Themes.Argon, Argon.Themes.Amethyst
	for key, value in pairs(argon) do
		if amethyst[key] ~= value then return true end
	end
	return false
end)())
check("SetTheme applies", (Argon:SetTheme("Midnight")))
check("AddTheme + SetTheme custom", (function()
	Argon:AddTheme("TestTheme", { Accent = sandbox.environment.Color3.fromRGB(1, 2, 3) })
	return (Argon:SetTheme("TestTheme"))
end)())
check("GetColor reads the live palette", (function()
	Argon:SetTheme("Ember")
	local ember = Argon.Themes.Ember
	return Argon:GetColor("Accent") == ember.Accent and Argon:GetColor("Hover") == ember.Hover
end)())
check("GetColor falls back for unknown keys", Argon:GetColor("NotAKey") ~= nil)
check("GetPalette snapshot is detached", (function()
	local snapshot = Argon:GetPalette()
	local before = snapshot.Accent
	Argon:SetTheme("Ocean")
	return snapshot.Accent == before and Argon:GetColor("Accent") == Argon.Themes.Ocean.Accent
end)())
check("OnThemeChanged fires with the new palette", (function()
	local seenTheme, seenAccent
	local unbind = Argon:OnThemeChanged(function(palette, themeName)
		seenTheme, seenAccent = themeName, palette.Accent
	end)
	Argon:SetTheme("Emerald")
	unbind()
	local wasCalled = seenTheme == "Emerald" and seenAccent == Argon.Themes.Emerald.Accent
	seenTheme = nil
	Argon:SetTheme("Rose")
	return wasCalled and seenTheme == nil
end)())
check("a recoloured control still follows the next theme", (function()
	-- Regression: SetTheme only repainted a bound property when it still equalled the OLD
	-- palette entry, so anything a hover/press had recoloured stayed on the previous theme.
	Argon:SetTheme("Midnight")
	local toggle = jsonTab:CreateToggle({ Name = "ThemeRepaint", CurrentValue = false })
	toggle.Root.BackgroundColor3 = sandbox.environment.Color3.fromRGB(123, 45, 67)
	Argon:SetTheme("Ember")
	for _ = 1, 40 do
		if toggle.Root.BackgroundColor3 == Argon.Themes.Ember.Surface then return true end
		task.wait()
	end
	return false, tostring(toggle.Root.BackgroundColor3)
end)())
check("Notify runs", (pcall(function() Argon:Notify({ Title = "Test", Content = "hello", Duration = 1 }) end)))
check("Dialog runs", (pcall(function()
	jsonWindow:Dialog({ Title = "Confirm", Content = "ok?", Buttons = { { Title = "Cancel" }, { Title = "Ok" } } })
end)))
local settingsOk, settingsError = pcall(function()
	local settingsTab = jsonWindow:CreateTab("Settings", "settings")
	jsonWindow:CreateLibrarySettings(settingsTab)
end)
check("CreateLibrarySettings runs", settingsOk, settingsError)

section("window controls")
check("Close/Open work", (pcall(function() jsonWindow:Close() jsonWindow:Open() end)))
check("SetTitle/SetLogo work", (pcall(function() jsonWindow:SetTitle("Renamed") jsonWindow:SetLogo("rbxassetid://1") end)))
check("overlay toggles work", (pcall(function()
	jsonWindow:SetPlayerListVisible(false)
	jsonWindow:TogglePlayerList()
	jsonWindow:SetOverlayTransparency(0.5)
	jsonWindow:SetOverlayScale(1.2)
	jsonWindow:ResetOverlayPositions()
end)))
check("SetSize works", (pcall(function() jsonWindow:SetSize({ 900, 600 }) end)))

section("autosave enables itself without LoadConfiguration")
-- A freshly created window keeps writes gated until hydration would have finished.
check("persistence starts gated for a new window", Argon:GetConfigurationStats().Ready == false)
sandbox.files["JsonHub/settings.json"] = nil -- clear the earlier explicit save
local jsonToggle = Argon.Flags.J_Toggle
jsonToggle:Set(false)
sandbox.advance(0.4)
check("gated window does not write", sandbox.files["JsonHub/settings.json"] == nil)
sandbox.advance(5)
check("persistence self-enables after CreateWindow", Argon:GetConfigurationStats().Ready == true)

section("debounced autosave")
sandbox.files["JsonHub/settings.json"] = nil
jsonToggle:Set(true)
check("autosave is debounced, not immediate", sandbox.files["JsonHub/settings.json"] == nil)
sandbox.advance(0.4)
check("autosave writes after the delay", sandbox.files["JsonHub/settings.json"] ~= nil)
local autosaved = sandbox.decodeJson(sandbox.files["JsonHub/settings.json"] or "{}")
check("autosaved value is current", autosaved.J_Toggle == true, tostring(autosaved.J_Toggle))

section("overlays can stay on screen while the window is hidden")
local overlayWindow = Argon:CreateWindow({ Name = "Overlays", GuiName = "ArgonUIOverlays" })
overlayWindow:CreateTab("Main", "zap")
overlayWindow:SetPlayerListVisible(true)
overlayWindow:SetKeybindListVisible(true)
check("overlays visible while window is open", overlayWindow.PlayerListOverlay.Visible == true)
overlayWindow:SetOverlaysAlwaysVisible(false)
overlayWindow:Close()
check("overlays hide with the window by default", overlayWindow.PlayerListOverlay.Visible == false)
overlayWindow:SetOverlaysAlwaysVisible(true)
check("pinned overlays stay visible while hidden", overlayWindow.PlayerListOverlay.Visible == true)
check("pinned keybind overlay stays visible", overlayWindow.KeybindListOverlay.Visible == true)
check("AreOverlaysAlwaysVisible reports state", overlayWindow:AreOverlaysAlwaysVisible() == true)
overlayWindow:TogglePlayerList()
check("player list can be toggled off while hidden", overlayWindow.PlayerListOverlay.Visible == false)
overlayWindow:TogglePlayerList()
check("player list can be toggled back on while hidden", overlayWindow.PlayerListOverlay.Visible == true)
overlayWindow:Open()
check("reopening keeps overlays visible", overlayWindow.PlayerListOverlay.Visible == true)
overlayWindow:ToggleOverlaysAlwaysVisible()
check("ToggleOverlaysAlwaysVisible flips the preference", overlayWindow:AreOverlaysAlwaysVisible() == false)
local exported = overlayWindow:_exportUIPreferences()
check("preference is exported for persistence", exported.OverlaysAlwaysVisible == false)
overlayWindow:_applyUIPreferences({ OverlaysAlwaysVisible = true, PlayerListEnabled = true, KeybindListEnabled = true })
check("preference is restored", overlayWindow:AreOverlaysAlwaysVisible() == true)

section("no unexpected runtime warnings")
local unexpected = {}
for _, message in ipairs(sandbox.warnings) do
	if not message:find("unknown/retired flag") and not message:find("Duplicate configuration flag") then
		unexpected[#unexpected + 1] = message
	end
end
check("library produced no unexpected warnings", #unexpected == 0, table.concat(unexpected, " | "))
check("no signal handler errors", #sandbox.signalErrors == 0, table.concat(sandbox.signalErrors, " | "))

print(("\n================ %d passed, %d failed ================"):format(passed, failed))
if failed > 0 then
	print("\nFailures:")
	for _, name in ipairs(failures) do print("  - " .. name) end
	process.exit(1)
end
process.exit(0)
