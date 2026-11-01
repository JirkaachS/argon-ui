--!nocheck
-- v2 behaviour suite: lazy mounting, the scheduler, idle cost, the loader, the input router,
-- persistence and profiles, change tracking, search, notifications and dialogs.
-- Run from the repository root: lune run tests/v2_core.luau [-- path/to/argon-ui.luau]

local process = require("@lune/process")
local sandbox = require("./sandbox")
local PATH = process.args[1] or "argon-ui.luau"
local task = sandbox.environment.task
local Color3 = sandbox.environment.Color3

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
local function section(title) print("\n== " .. title .. " ==") end

local function luminance(c)
	local function lin(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * lin(c.R) + 0.7152 * lin(c.G) + 0.0722 * lin(c.B)
end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

section("loading does nothing slow")
sandbox.forbidNetwork = true
local before = sandbox.metrics()
local ok, Argon = pcall(sandbox.load, PATH)
check("the bundle loads", ok, not ok and Argon or nil)
if not ok then process.exit(1) end
local after = sandbox.metrics()
check("loading creates no instances", after.created == before.created, after.created - before.created)
check("loading starts no timers", after.delaysPending == before.delaysPending)
check("loading connects nothing", after.handlers.InputBegan == 0 and after.handlers.Heartbeat == 0)
check("loading makes no network calls", sandbox.network.httpGets == 0 and sandbox.network.thumbnails == 0)

section("notifications before any window (D19)")
local early = Argon:Notify({ Title = "Hello", Content = "before the window", Duration = 2 })
check("Notify works before CreateWindow", early ~= nil and early.Instance ~= nil)

section("CreateWindow is cheap and never waits")
local created0, yields0 = sandbox.metrics().created, sandbox.yields
local window = Argon:CreateWindow({ Name = "Core", GuiName = "CoreTest",
	ConfigurationSaving = { Enabled = true, FolderName = "Core", FileName = "core" } })
local created1 = sandbox.metrics().created
local params = sandbox.metrics().byClass.GetTextBoundsParams or 0
check("CreateWindow builds at most 34 GUI instances", created1 - created0 - params <= 34, created1 - created0 - params)
check("CreateWindow does not yield on the caller", sandbox.yields == yields0, sandbox.yields - yields0)
check("font preload never runs on the caller", (sandbox.network.textBoundsOnMain or 0) == 0)
check("no network on the critical path", sandbox.network.httpGets == 0 and sandbox.network.thumbnails == 0)
check("one InputBegan handler for the library", sandbox.metrics().handlers.InputBegan == 1, sandbox.metrics().handlers.InputBegan)
check("the window starts loading", window:IsLoading())

section("controls are state until shown")
local main = window:CreateTab("Main", "zap")
main:CreateSection("Movement")
local createdBefore = sandbox.metrics().created
local toggles = {}
for index = 1, 60 do
	toggles[index] = main:CreateToggle({ Name = "Toggle " .. index, Flag = "M" .. index, CurrentValue = false })
end
check("60 Create* calls make no instances", sandbox.metrics().created == createdBefore, sandbox.metrics().created - createdBefore)
toggles[1]:Set(true)
check("Set works before mount", toggles[1].CurrentValue == true)
check("controls are registered as flags", Argon.Flags.M1 == toggles[1])
local other = window:CreateTab("Other", "settings")
other:CreateSection("Later")
local hidden = other:CreateToggle({ Name = "Infinite jump", Flag = "Jump", CurrentValue = false, Keywords = { "fly" } })
-- the scheduler's budget is real time, so a busy machine fits fewer mounts in a frame; 12 frames
-- (0.2 s) is still inside the loading phase
for _ = 1, 12 do
	if rawget(toggles[60], "_mounted") then break end
	sandbox.step(1)
end
check("the scheduler mounts the active tab over frames", rawget(toggles[60], "_mounted") == true)
check("the other tab is not mounted while loading", rawget(hidden, "_mounted") ~= true)
check("reading Root mounts that control on demand", hidden.Root ~= nil and rawget(hidden, "_mounted") == true)
check("an inactive page is detached", other.PageGroup.Parent == nil)
check("the active page is attached", main.PageGroup.Parent ~= nil)

section("the loader opens the window when the host is quiet")
sandbox.advance(1)
check("a built window opens without FinishLoading", window:IsLoading() == false)
check("the window is visible after the hand-over", window.Main.Visible == true)
sandbox.advance(3)
local metrics = sandbox.metrics()
check("idle: no Heartbeat work left", metrics.handlers.Heartbeat == 0, metrics.handlers.Heartbeat)
check("idle: one InputBegan, no InputChanged or InputEnded", metrics.handlers.InputBegan == 1
	and metrics.handlers.InputChanged == 0 and metrics.handlers.InputEnded == 0,
	("%d/%d/%d"):format(metrics.handlers.InputBegan, metrics.handlers.InputChanged, metrics.handlers.InputEnded))
check("idle: no looping tweens", metrics.runningLoops == 0, metrics.runningLoops)

section("themes")
for _, name in ipairs(Argon:GetThemes()) do
	local p = Argon.Themes[name]
	if p and p.Surface and p.Text2 then
		local okText = contrast(p.Text, p.Surface) >= 10 - 1e-6
		local okText2 = contrast(p.Text2, p.Surface) >= 9 - 1e-6
		local okAccent = contrast(p.OnAccent, p.Accent) >= 4.5 - 1e-6
		check(name .. " meets the contrast targets", okText and okText2 and okAccent,
			("%.2f %.2f %.2f"):format(contrast(p.Text, p.Surface), contrast(p.Text2, p.Surface), contrast(p.OnAccent, p.Accent)))
	end
end
check("v1 key aliases still read", Argon.Themes.Argon.Window == Argon.Themes.Argon.Sheet and Argon.Themes.Argon.Input == Argon.Themes.Argon.Well)
local custom = Argon:AddTheme("Lime", { Accent = Color3.fromRGB(132, 204, 22) })
check("AddTheme derives the missing tokens", custom.AccentHi ~= nil and custom.OnAccent ~= nil and custom.Focus ~= nil)
check("a derived theme keeps ink readable on its accent", contrast(custom.OnAccent, custom.Accent) >= 4.5)
local generated = Argon:CreateTheme({ Accent = Color3.fromRGB(255, 80, 120), Mode = "light", Name = "Coral" })
check("CreateTheme makes a light theme", luminance(generated.Sheet) > 0.5 and table.find(Argon:GetThemes(), "Coral") ~= nil)
check("CreateTheme options ignore case", luminance(Argon:CreateTheme({ Mode = "Light" }).Sheet) > 0.5)
local onTrack = toggles[1]._track
Argon:SetTheme("Ember")
check("a theme switch repaints the visible tab at once", onTrack.BackgroundColor3 == Argon.Themes.Ember.Accent)
check("a hidden mounted tab is caught up later", (function()
	sandbox.step(10)
	return hidden._track.BackgroundColor3 == Argon.Themes.Ember.Track
end)(), tostring(hidden._track.BackgroundColor3))
check("a Rayfield theme name resolves", (Argon:SetTheme("DarkBlue")) == true)
check("an unknown theme is refused", (Argon:SetTheme("NoSuchTheme")) == false)
Argon:SetTheme("Argon")
Argon:SetAccent(Color3.fromRGB(56, 189, 208))
check("SetAccent overrides the accent", Argon:GetColor("Accent") == Color3.fromRGB(56, 189, 208))
Argon:SetAccent(nil)
check("SetAccent(nil) restores the theme's accent", Argon:GetColor("Accent") == Argon.Themes.Argon.Accent)

section("input")
check("the default menu key is Insert", window._toggleKey == sandbox.environment.Enum.KeyCode.Insert)
sandbox.input.press("Insert")
check("Insert hides the window", window:IsVisible() == false)
sandbox.input.press("Insert")
check("Insert shows it again", window:IsVisible() == true)
local bound = 0
local fly = main:CreateToggle({ Name = "Fly", Keybind = "F", Callback = function() bound += 1 end })
sandbox.input.press("F")
check("a toggle's Keybind flips it", fly.CurrentValue == true and bound == 1)
fly:Lock("Needs a vehicle")
sandbox.input.press("F")
check("a locked toggle ignores its keybind (D26)", fly.CurrentValue == true and bound == 1)
fly:Unlock()
fly:Destroy()
sandbox.input.press("F")
check("a destroyed toggle's keybind is released (D8)", bound == 1)
check("Escape is not bound", (function()
	sandbox.input.press("Escape")
	return window:IsVisible() == true
end)())

section("context menu and the close key")
local target = toggles[2]
sandbox.input.click(target.Root, 2)
check("right-click opens the row menu", window._popover:isOpen() == true)
sandbox.input.press("Backspace")
check("Backspace closes it", window._popover:isOpen() == false)
check("Backspace never hides the window", window:IsVisible() == true)
sandbox.input.click(target.Root, 2)
check("the row menu opens a second time (pooled view)", window._popover:isOpen() == true)
sandbox.input.press("Backspace")
local explained = 0
target:AddMenuItem({ Name = "Explain", Icon = "info", Callback = function(element) if element == target then explained += 1 end end })
sandbox.input.click(target.Root, 2)
local function menuRow(text)
	for _, item in ipairs(window._layers:get("Popover"):GetDescendants()) do
		if item.Name == "MenuItem" and item.Visible and item:FindFirstChild("Label") and item.Label.Text == text then return item end
	end
end
check("a custom item appears in the row menu", menuRow("Explain") ~= nil)
sandbox.input.press("Down")
local copyRow = menuRow("Copy value")
check("Down highlights the first enabled row", copyRow ~= nil and copyRow.BackgroundTransparency == 0)
sandbox.input.click(menuRow("Explain"), 1)
check("a custom item runs with its element", explained == 1)
check("picking an item closes the menu", window._popover:isOpen() == false)

section("change tracking, reset and undo")
local tracked = toggles[3]
tracked:Set(true)
check("a changed control reports it", tracked:IsChanged() == true)
check("the tab counts it", main:GetChangedCount() >= 2, main:GetChangedCount())
main:Reset()
check("Reset tab puts values back", tracked.CurrentValue == false and toggles[1].CurrentValue == false)
check("an undo is offered", window._changes:canUndo())
window._changes:runUndo()
check("Undo brings the values back", tracked.CurrentValue == true and toggles[1].CurrentValue == true)

section("search finds controls in tabs that were never opened")
local results = window._registry:search("infinite jump", 5)
check("palette search finds an unopened tab's control", results[1] and results[1].el == hidden)
local byKeyword = window._registry:search("fly", 5)
check("Keywords are indexed", (function()
	for _, result in ipairs(byKeyword) do
		if result.el == hidden then return true end
	end
	return false
end)())
check("weak subsequence matches are hidden behind strong ones", (function()
	local esp = window._registry:search("tog", 50)
	for _, result in ipairs(esp) do
		if result.score < 25 then return false end
	end
	return #esp > 0
end)())
window:OpenPalette("jump")
check("the palette opens and lists results", window._palette ~= nil and window._palette.root.Visible == true and #window._palette.items > 0)
sandbox.input.press("Backspace")
window._palette.box.Text = ""
sandbox.input.press("Backspace")
check("Backspace on an empty query closes the palette", window._palette.root.Visible == false)

section("VisibleWhen")
local master = main:CreateToggle({ Name = "Master", Flag = "Master", CurrentValue = false })
local dependent = main:CreateToggle({ Name = "Dependent", VisibleWhen = { Flag = "Master", Equals = true } })
check("hidden while the condition fails", dependent:_isVisible() == false)
master:Set(true)
check("shown when it holds", dependent:_isVisible() == true)

section("persistence and profiles")
local okSave, path = Argon:SaveConfiguration()
check("SaveConfiguration writes the v1 path", okSave and path == "Core/core.rfld", path)
local data = sandbox.decodeJson(sandbox.files["Core/core.rfld"])
check("values are saved in the v1 format", data.M1 == true and data.Jump == false)
check("the meta file holds the preferences", sandbox.files["Core/core.meta.json"] ~= nil)
check("a profile can be saved", (Argon:SaveConfiguration("PvP")) == true and sandbox.files["Core/core.profiles/PvP.rfld"] ~= nil)
toggles[5]:Set(true)
-- "Save as" makes the new profile the active one; save the default file explicitly
Argon:SaveConfiguration("Default")
check("profiles are listed", (function()
	local names = {}
	for _, profile in ipairs(Argon:ListConfigurations()) do names[profile.Name] = true end
	return names.Default and names.PvP
end)())
Argon:LoadConfiguration("PvP")
check("loading a profile restores its values", toggles[5].CurrentValue == false)
check("rename works", (Argon:RenameConfiguration("PvP", "Arena")) == true and sandbox.files["Core/core.profiles/Arena.rfld"] ~= nil)
Argon:SetAutoloadConfiguration("Arena")
check("autoload is remembered", Argon:GetAutoloadConfiguration() == "Arena")
local code = Argon:ExportConfiguration()
check("export produces an ARGON2 code", type(code) == "string" and code:sub(1, 7) == "ARGON2:")
toggles[6]:Set(true)
local okImport, summary = Argon:ImportConfiguration(code)
check("import applies the code", okImport and toggles[6].CurrentValue == false, summary and summary.changed)
check("delete works", (Argon:DeleteConfiguration("Arena")) == true and sandbox.files["Core/core.profiles/Arena.rfld"] == nil)
sandbox.files["Core/core.rfld"] = nil
local okMissing, info = Argon:LoadConfiguration()
check("a missing file is not a failure (D10)", okMissing == true, info)
local seen = {}
local u1 = Argon:OnFlagChanged(function(flag) seen[#seen + 1] = "a:" .. flag end)
local u2 = Argon:OnFlagChanged(function(flag) seen[#seen + 1] = "b:" .. flag end)
u1()
u2()
toggles[7]:Set(true)
check("flag listeners unbind by identity (D6)", #seen == 0, table.concat(seen, ","))
check("a v1 library-settings flag reads the preference", Argon:GetFlagValue("ArgonUIWindowTitle") == "Core")

section("restores keep everything")
local tint = main:CreateColorPicker({ Name = "Tint", Flag = "Tint", Color = Color3.fromRGB(10, 20, 30), Alpha = true })
tint:SetAlpha(0.4)
Argon:SaveConfiguration()
tint:SetAlpha(1)
Argon:LoadConfiguration()
check("a restored colour keeps its alpha", tint.Alpha ~= nil and math.abs(tint.Alpha - 0.4) < 0.01, tint.Alpha)

section("notifications")
local toast = Argon:Notify({ Title = "Saved", Content = "All good", Id = "save" })
check("Notify returns a handle with the card", toast ~= nil and toast.Instance ~= nil and toast.AutomaticSize ~= nil)
local again = Argon:Notify({ Title = "Saved again", Content = "Updated", Id = "save" })
check("the same Id updates in place", again == toast)
toast:Update({ Content = "Changed" })
check("Update changes the card", toast.Instance:FindFirstChild("Body").Text == "Changed")
toast:Dismiss()
local coalesced = Argon:Notify({ Title = "Ping", Content = "x" })
local second = Argon:Notify({ Title = "Ping", Content = "x" })
check("identical toasts coalesce", coalesced == second)
for index = 1, 8 do Argon:Notify({ Title = "Spam " .. index, Content = tostring(index) }) end
sandbox.advance(0.3)
local visible = 0
for _, child in ipairs(window.Notifications:GetChildren()) do
	if child.Name == "Toast" then visible += 1 end
end
check("at most four cards are on screen", visible <= 4, visible)
check("older toasts go to the inbox", #window._toastHost.inbox >= 8)

section("dialogs")
local cancelled = 0
local confirmDialog = window:Confirm({ Content = "Delete it?", OnConfirm = function() end, OnCancel = function() cancelled += 1 end })
sandbox.input.press("Backspace")
check("the close key cancels a confirm and calls OnCancel (D18)", cancelled == 1 and confirmDialog.Visible == false)
local outside = window:Confirm({ Content = "?", OnCancel = function() cancelled += 1 end })
outside.Root:FindFirstChild("Scrim").MouseButton1Click:Fire()
check("an outside click cancels too", cancelled == 2)
local submitted
local prompt = window:Prompt({ Title = "Name", Validate = function(text) return #text >= 3, "Use at least 3 letters" end,
	OnSubmit = function(text) submitted = text end })
prompt.Field.Text = "ab"
prompt._buttons[2].activate()
check("Prompt refuses an invalid value", submitted == nil and prompt.Visible == true)
prompt.Field.Text = "abc"
prompt._buttons[2].activate()
check("Prompt submits a valid value", submitted == "abc")
local rejected
local strict = window:Prompt({ Title = "Code", Validate = function(text) if #text < 4 then return "Too short" end end,
	OnSubmit = function(text) rejected = text end })
strict.Field.Text = "abc"
strict._buttons[2].activate()
check("a Validate that returns a message rejects the value", rejected == nil and strict.Visible == true)
strict.Field.Text = "abcd"
strict._buttons[2].activate()
check("a Validate that returns nothing accepts it", rejected == "abcd")

section("shared pieces survive their owners")
local glowTab = window:CreateTab("Glow", "zap")
glowTab:CreateSection("Glow")
local glowA = glowTab:CreateToggle({ Name = "Glow A" })
check("a section control is not mistaken for a row control", rawget(glowA, "Row") == nil and glowA._inRow == nil)
check("a section control gets its row divider", glowA.Root:FindFirstChild("Divider") ~= nil)
window._glow:acquire(3, glowA, glowA._track, {})
glowA:Destroy()
local glowB = glowTab:CreateToggle({ Name = "Glow B" })
local _ = glowB.Root
check("the glow pool survives a row destroyed while it glowed", (pcall(function()
	window._glow:acquire(3, glowB, glowB._track, {})
end)))
window._glow:release(3, glowB)
check("a released glow leaves its owner's row", (function()
	for _, child in ipairs(glowB._track.Parent:GetChildren()) do
		if child.Name == "Glow" then return false end
	end
	return true
end)())

section("phone portrait: bottom tab bar")
for index = 1, 4 do window:CreateTab("Extra " .. index, "star") end
sandbox.setPreferredInput("touch")
sandbox.setViewport(390, 844)
sandbox.step(2)
check("portrait hides the sidebar", window._layoutName == "portrait" and window.Sidebar.Visible == false, window._layoutName)
check("portrait shows the bottom tab bar", window._tabBar ~= nil and window._tabBar.Visible == true)
local slots = 0
for _, slot in ipairs(window._tabBarSlots or {}) do
	if slot.Root.Visible then slots += 1 end
end
check("six tabs make four tab slots plus More", slots == 5 and window._tabBarSlots[5].tab == nil and window._tabBarSlots[5].Label.Text == "More", slots)
window._tabBarSlots[2].Root.MouseButton1Click:Fire()
check("a tab slot selects its tab", window.ActiveTab == window.Tabs[2])
window._tabBarSlots[5].Root.MouseButton1Click:Fire()
check("More opens the tab sheet", window._popover:isOpen("tabsheet") == true)
sandbox.input.press("Backspace")
window:SelectTab(window.Tabs[6])
check("a tab behind More marks More as selected", window._tabBarPill.Visible == true and window._tabBarSlots[5].Label.TextColor3 == Argon:GetColor("Text"))
sandbox.setPreferredInput("mouse")
sandbox.setViewport(1280, 800)
sandbox.step(2)
check("back on a desktop the tab bar hides", window._tabBar.Visible == false and window.Sidebar.Visible == true)
window:SelectTab(main)

section("density applies to every window")
local second = Argon:CreateWindow({ Name = "Second", GuiName = "SecondDensity" })
second:CreateTab("Main", "zap"):CreateToggle({ Name = "Row" })
second:FinishLoading()
sandbox.step(2)
window:SetDensity("Touch")
check("both windows rebuild at the new density", window._density == "Touch" and second._density == "Touch",
	tostring(window._density) .. "/" .. tostring(second._density))
window:SetDensity("Auto")
second:Destroy()

section("re-execution and teardown")
local keyed = Argon:CreateWindow({ Name = "Keyed", GuiName = "KeyedTest", ToggleUIKeybind = "K" })
keyed:FinishLoading()
sandbox.input.press("K")
check("a string ToggleUIKeybind works (D1)", keyed:IsVisible() == false)
sandbox.input.press("K")
keyed:Destroy()
local first = Argon:CreateWindow({ Name = "Twice", GuiName = "TwiceTest" })
local firstGui = first.ScreenGui
Argon:CreateWindow({ Name = "Twice", GuiName = "TwiceTest" })
check("a second window with the same GuiName replaces the first", firstGui.Parent == nil)
Argon:Destroy()
check("Destroy clears the windows", #Argon._windows == 0)
local revived = Argon:CreateWindow({ Name = "After", GuiName = "AfterTest" })
check("CreateWindow works again after Destroy", revived ~= nil and revived.ScreenGui ~= nil)

section("no executor functions at all")
sandbox.setExecutor("none")
local bare = Argon:CreateWindow({ Name = "Bare", GuiName = "BareTest", ConfigurationSaving = { Enabled = true, FolderName = "Bare" } })
bare:CreateTab("Main", "zap"):CreateToggle({ Name = "A", Flag = "BareA" })
bare:FinishLoading()
local okBare = Argon:SaveConfiguration()
check("saving reports failure without a filesystem", okBare == false)
sandbox.setExecutor("full")

section("hygiene")
local unexpected = {}
for _, message in ipairs(sandbox.warnings) do
	if not message:find("Duplicate configuration flag") and not message:find("unknown/retired flag") then unexpected[#unexpected + 1] = message end
end
check("no unexpected warnings", #unexpected == 0, table.concat(unexpected, " | "))
check("no handler errors", #sandbox.signalErrors == 0, table.concat(sandbox.signalErrors, " | "))

print(("\n================ %d passed, %d failed ================"):format(passed, failed))
if failed > 0 then
	print("\nFailures:")
	for _, name in ipairs(failures) do print("  - " .. name) end
	process.exit(1)
end
process.exit(0)
