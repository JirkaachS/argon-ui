--!nocheck
-- Functional test for argon-ui.luau running under Lune with a Roblox API sandbox.
-- Exercises real library code: window/tab/section creation, all 18 controls, the new
-- components, and the configuration save/load round-trip.

local process = require("@lune/process")
local fs = require("@lune/fs")
-- Resolve the library whether the suite is run from the repo root or from tests/.
local ARGON_PATH = fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau"
local sandbox = require("./sandbox")
-- The sandbox's task is what the library schedules against, so yielding through it is what
-- actually lets a deferred relayout or a theme repaint run.
local task = sandbox.environment.task or require("@lune/task")
local UDim2 = sandbox.environment.UDim2

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
check("version is 1.14.0", Argon.Version == "1.14.0", Argon.Version)
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

section("rows put several controls on one line")
local rowTab = Window:CreateTab("Rows", "zap")
rowTab:CreateSection("Row Tests")
local twoUp = rowTab:CreateRow({ Columns = 2 })
local rowLeft = twoUp:CreateToggle({ Flag = "R_Left", Name = "Left", CurrentValue = false })
local rowRight = twoUp:CreateToggle({ Flag = "R_Right", Name = "Right", CurrentValue = true })
check("CreateRow returns a builder", type(twoUp) == "table" and #twoUp.Columns == 2)
check("row exposes the same shorthands as a section", type(twoUp.Slider) == "function"
	and type(twoUp.Dropdown) == "function" and type(twoUp.ColorPicker) == "function")
check("controls are handed out round-robin", (function()
	return rowLeft.Root.Parent ~= rowRight.Root.Parent
		and rowLeft.Root.Parent.Parent == twoUp.Root
		and rowRight.Root.Parent.Parent == twoUp.Root
end)())
check("column order follows build order", rowLeft.Root.Parent.LayoutOrder == 1 and rowRight.Root.Parent.LayoutOrder == 2)
check("a third control wraps back to the first column", (function()
	local third = twoUp:CreateToggle({ Name = "Third", CurrentValue = false })
	return third.Root.Parent == rowLeft.Root.Parent
end)())
check("row controls still work", (function()
	local fired
	local slider = twoUp:CreateSlider({ Name = "InRow", Range = { 0, 10 }, Increment = 1,
		CurrentValue = 0, Callback = function(v) fired = v end })
	slider:Set(7)
	return slider.CurrentValue == 7 and fired == 7
end)())
check("row controls register their flags", Argon.Flags.R_Left == rowLeft and Argon.Flags.R_Right == rowRight)
check("row controls join the owning section, so search sees them", (function()
	for _, element in ipairs(rowTab._sections[1].Elements) do
		if element == rowLeft then return true end
	end
	return false
end)())
check("row controls count toward the tab total", rowTab._controlCount >= 4, rowTab._controlCount)
check("Columns is clamped to a sane range", (function()
	local tooMany = rowTab:CreateRow({ Columns = 99 })
	local tooFew = rowTab:CreateRow({ Columns = 0 })
	return #tooMany.Columns == 4 and #tooFew.Columns == 1
end)())
check("Use targets a specific column", (function()
	local row = rowTab:CreateRow({ Columns = 3 })
	row:CreateToggle({ Name = "First", CurrentValue = false })
	local pinned = row:Use(3):CreateToggle({ Name = "Pinned", CurrentValue = false })
	return pinned.Root.Parent == row.Columns[3].Holder
end)())
check("a plain number is accepted as the column count", #rowTab:CreateRow(3).Columns == 3)
check("sections expose Row too", (function()
	local sec = rowTab:CreateSection("Via Section")
	local row = sec:Row({ Columns = 2 })
	local made = row:CreateToggle({ Name = "SectionRow", CurrentValue = false })
	return type(row) == "table" and made.Root.Parent.Parent == row.Root
end)())
check("filtering hides a row with no surviving controls", (function()
	rowTab:_filter("zzz-nothing-matches")
	return twoUp.Root.Visible == false
end)())
check("filtering keeps a row that still has a match", (function()
	rowTab:_filter("Right")
	return twoUp.Root.Visible == true and rowRight.Root.Visible == true and rowLeft.Root.Visible == false
end)())
check("clearing the filter restores the row", (function()
	rowTab:_filter("")
	return twoUp.Root.Visible == true and rowLeft.Root.Visible == true
end)())
check("controls on the same line are grown to the tallest", (function()
	-- A toggle is 54 tall and a titled segmented strip is 76; left alone they made a ragged
	-- line. They are padded to match, and the pad is tracked so repeated passes are stable.
	local heightRow = rowTab:CreateRow({ Columns = 2 })
	local short = heightRow:CreateToggle({ Name = "Short", CurrentValue = false })
	local tall = heightRow:CreateSegmented({ Name = "Tall", Options = { "A", "B" }, CurrentOption = "A" })
	task.wait(0.15)
	if heightRow._balance then heightRow._balance() end
	return short.Root.Size.Y.Offset == tall.Root.Size.Y.Offset,
		("%d vs %d"):format(short.Root.Size.Y.Offset, tall.Root.Size.Y.Offset)
end)())
check("balancing is idempotent", (function()
	local heightRow = rowTab:CreateRow({ Columns = 2 })
	local a = heightRow:CreateToggle({ Name = "A", CurrentValue = false })
	local b = heightRow:CreateSlider({ Name = "B", Range = { 0, 10 }, Increment = 1, CurrentValue = 5 })
	task.wait(0.1)
	for _ = 1, 4 do heightRow._balance() end
	local first = a.Root.Size.Y.Offset
	heightRow._balance()
	return a.Root.Size.Y.Offset == first and a.Root.Size.Y.Offset == b.Root.Size.Y.Offset,
		("%d vs %d"):format(a.Root.Size.Y.Offset, b.Root.Size.Y.Offset)
end)())
check("a lone control on a line is not stretched", (function()
	local oddRow = rowTab:CreateRow({ Columns = 2 })
	local one = oddRow:CreateToggle({ Name = "One", CurrentValue = false })
	local two = oddRow:CreateToggle({ Name = "Two", CurrentValue = false })
	local three = oddRow:CreateToggle({ Name = "Three", CurrentValue = false })
	task.wait(0.1)
	oddRow._balance()
	-- Line 2 holds only "Three", so its natural height must survive untouched.
	return three.Root.Size.Y.Offset == 54, three.Root.Size.Y.Offset
end)())
check("row controls follow a theme switch", (function()
	Argon:SetTheme("Ocean")
	for _ = 1, 40 do
		if rowLeft.Root.BackgroundColor3 == Argon.Themes.Ocean.Surface then return true end
		task.wait()
	end
	return false, tostring(rowLeft.Root.BackgroundColor3)
end)())

section("state-driven colours survive a theme switch")
-- Regression: bindings only know the colour an object was BUILT with, so repainting a toggle
-- track from its binding forced an ON toggle back to the off colour. The switch kept its
-- position and lost its highlight, which looked like the value had not been restored.
local colourTab = Window:CreateTab("Colour", "eye")
colourTab:CreateSection("State")
Argon:SetTheme("Argon")
local onToggle = colourTab:CreateToggle({ Name = "Already On", CurrentValue = true })
local offToggle = colourTab:CreateToggle({ Name = "Still Off", CurrentValue = false })
local function trackOf(toggle)
	for _, child in ipairs(toggle.Root:GetChildren()) do
		if child:IsA("Frame") and child.Size == UDim2.fromOffset(44, 24) then return child end
	end
	return nil
end
check("an on toggle starts on the accent", trackOf(onToggle).BackgroundColor3 == Argon.Themes.Argon.Accent,
	tostring(trackOf(onToggle).BackgroundColor3))
check("an on toggle keeps its accent after a theme switch", (function()
	Argon:SetTheme("Emerald")
	for _ = 1, 40 do
		if trackOf(onToggle).BackgroundColor3 == Argon.Themes.Emerald.Accent then return true end
		task.wait()
	end
	return false, tostring(trackOf(onToggle).BackgroundColor3)
end)())
check("an off toggle keeps the off colour after a theme switch",
	trackOf(offToggle).BackgroundColor3 == Argon.Themes.Emerald.Input,
	tostring(trackOf(offToggle).BackgroundColor3))
check("a toggle restored by config keeps its highlight", (function()
	-- Exactly what autoload does: set silently, then the theme is applied from the config.
	offToggle:Set(true, true)
	Argon:SetTheme("Rose")
	for _ = 1, 40 do
		if trackOf(offToggle).BackgroundColor3 == Argon.Themes.Rose.Accent then return true end
		task.wait()
	end
	return false, tostring(trackOf(offToggle).BackgroundColor3)
end)())
check("a colour picker keeps the user's colour through a theme switch", (function()
	local chosen = sandbox.environment.Color3.fromRGB(244, 114, 182) -- Rose's accent
	local picker = colourTab:CreateColorPicker({ Name = "Mine", Color = chosen })
	Argon:SetTheme("Ocean")
	task.wait()
	return picker.CurrentValue == chosen
end)())

section("descriptions sit below a control, not through it")
local descTab = Window:CreateTab("Desc", "settings")
descTab:CreateSection("Descriptions")
local longText = "A deliberately long description so the wrap is real and the row has to grow to fit it rather than clipping the tail off the end."
local descSlider = descTab:CreateSlider({ Name = "With Desc", Range = { 0, 100 }, Increment = 1,
	CurrentValue = 50, Description = longText })
local descToggle = descTab:CreateToggle({ Name = "Toggle Desc", CurrentValue = false, Description = longText })
task.wait(0.2)
local function descriptionOf(element) return element._description end
check("the slider grew past its natural height", descSlider.Root.Size.Y.Offset > 72, descSlider.Root.Size.Y.Offset)
check("the description starts below the slider track", (function()
	local desc = descriptionOf(descSlider)
	local bar
	for _, child in ipairs(descSlider.Root:GetChildren()) do
		if child:IsA("Frame") and child.Active and child.Size.Y.Offset == 8 then bar = child end
	end
	return desc and bar and desc.Position.Y.Offset >= bar.Position.Y.Offset + bar.Size.Y.Offset
end)())
check("the description fits inside the grown row", (function()
	local desc = descriptionOf(descSlider)
	return desc.Position.Y.Offset + desc.AbsoluteSize.Y <= descSlider.Root.Size.Y.Offset + 1
end)(), descSlider.Root.Size.Y.Offset)
check("a centred control is pinned into its own band", (function()
	-- The toggle track used to stay at 50% of the row, so it drifted down into the
	-- description as the row grew.
	--
	-- Re-applied on purpose: this sandbox runs task.defer eagerly, so the description that
	-- base() defers lands before the constructor has added the track. Roblox defers properly
	-- and the first pass already sees it; calling SetDesc again is the same code path the
	-- library takes when a host updates the text later.
	descToggle:SetDesc(longText)
	local track
	for _, child in ipairs(descToggle.Root:GetChildren()) do
		if child:IsA("Frame") and child.Size == UDim2.fromOffset(44, 24) then track = child end
	end
	local desc = descriptionOf(descToggle)
	if not track then return false, "no track found" end
	return track.Position.Y.Scale == 0
		and track.Position.Y.Offset + track.Size.Y.Offset <= desc.Position.Y.Offset + 2,
		("track y=%s+%s h=%s desc y=%s"):format(track.Position.Y.Scale, track.Position.Y.Offset,
			track.Size.Y.Offset, desc.Position.Y.Offset)
end)())
check("clearing a description shrinks the row back", (function()
	local before = descToggle.Root.Size.Y.Offset
	descToggle:SetDesc("")
	task.wait(0.15)
	return descToggle.Root.Size.Y.Offset < before
end)())

section("list rows can carry several actions")
local listTab = Window:CreateTab("Lists", "server")
listTab:CreateSection("Actions")
local fired = {}
local actionList = listTab:CreateList({ Name = "Profiles", Items = {
	{ Title = "Mining", Description = "snapshot", Actions = {
		{ Label = "Load", Callback = function(row) fired[#fired + 1] = "load:" .. row.Title end },
		{ Label = "Rename", Callback = function(row) fired[#fired + 1] = "rename:" .. row.Title end },
		{ Label = "Delete", Style = "danger", Callback = function(row) fired[#fired + 1] = "delete:" .. row.Title end },
	} },
} })
local function actionButtons(index)
	local found = {}
	local rows = {}
	for _, child in ipairs(actionList.Root:GetDescendants()) do
		if child:IsA("Frame") and child.Size.Y.Offset == 44 then table.insert(rows, child) end
	end
	for _, child in ipairs((rows[index] or actionList.Root):GetChildren()) do
		if child:IsA("TextButton") then table.insert(found, child) end
	end
	table.sort(found, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	return found
end
check("three buttons are drawn on the row", #actionButtons(1) == 3, #actionButtons(1))
check("labels are in build order", (function()
	local buttons = actionButtons(1)
	return buttons[1].Text == "Load" and buttons[2].Text == "Rename" and buttons[3].Text == "Delete"
end)())
check("buttons do not overlap", (function()
	local buttons = actionButtons(1)
	for index = 1, #buttons - 1 do
		if buttons[index].Position.X.Offset + buttons[index].Size.X.Offset > buttons[index + 1].Position.X.Offset then
			return false
		end
	end
	return true
end)())
check("a danger action is tinted differently", actionButtons(1)[3].BackgroundColor3 ~= actionButtons(1)[1].BackgroundColor3)
check("each button calls its own callback", (function()
	for _, button in ipairs(actionButtons(1)) do button.MouseButton1Click:Fire() end
	return #fired == 3 and fired[1] == "load:Mining" and fired[3] == "delete:Mining"
end)(), table.concat(fired, ","))
check("a single Action string still works", (function()
	local hit
	local legacy = listTab:CreateList({ Name = "Legacy", Items = {
		{ Title = "One", Action = "Go", Callback = function(row) hit = row.Title end },
	} })
	for _, child in ipairs(legacy.Root:GetDescendants()) do
		if child:IsA("TextButton") and child.Text == "Go" then child.MouseButton1Click:Fire() end
	end
	return hit == "One"
end)())

section("tooltips replace descriptions without costing row height")
local tipTab = Window:CreateTab("Tips", "eye")
tipTab:CreateSection("Tooltips")
local tipText = "Explanatory text that used to live in a Description and would otherwise spend three lines of row height on it."
local tipped = tipTab:CreateToggle({ Name = "Tipped", CurrentValue = false, Tooltip = tipText })
local plain = tipTab:CreateToggle({ Name = "Plain", CurrentValue = false })
task.wait(0.15)
check("Tooltip is accepted from the control config", tipped._tooltipText == tipText, tipped._tooltipText)
check("a tooltip costs no row height", tipped.Root.Size.Y.Offset == plain.Root.Size.Y.Offset,
	("%d vs %d"):format(tipped.Root.Size.Y.Offset, plain.Root.Size.Y.Offset))
check("a tooltip creates no description label", tipped._description == nil)
check("Tip is accepted as an alias", (function()
	local aliased = tipTab:CreateToggle({ Name = "Aliased", CurrentValue = false, Tip = "short" })
	task.wait(0.1)
	return aliased._tooltipText == "short"
end)())
check("SetTooltip can be called directly and updated", (function()
	plain:SetTooltip("first")
	plain:SetTooltip("second")
	return plain._tooltipText == "second"
end)())
check("hovering does not open instantly", (function()
	-- A short delay keeps a tooltip from strobing as the pointer sweeps down a column.
	tipped.Root.MouseEnter:Fire()
	return Window._tooltip == nil
end)())
check("hovering opens a wrapped, self-sizing tooltip", (function()
	sandbox.advance(0.35)
	local tip = Window._tooltip
	if not tip then return false, "no tooltip shown" end
	local label
	for _, child in ipairs(tip:GetChildren()) do
		if child.ClassName == "TextLabel" then label = child end
	end
	return label ~= nil and label.TextWrapped == true and label.Text == tipText
end)())
check("the tooltip is positioned in absolute offsets", (function()
	-- Where it lands relative to the row cannot be asserted here: this sandbox reports the
	-- window's own rect for every AbsolutePosition, so there is no layout to measure against.
	-- The anchoring itself is verified against a real client. What is checkable here is that
	-- placement ran and produced an offset position rather than leaving it at a scale default.
	local tip = Window._tooltip
	if not tip then return false, "no tooltip" end
	return tip.Position.X.Scale == 0 and tip.Position.Y.Scale == 0
end)())
check("the tooltip is not click-through blocking the row", (function()
	local tip = Window._tooltip
	return tip ~= nil and tip.Active == false
end)())
check("the tooltip does not follow the pointer", (function()
	local tip = Window._tooltip
	if not tip then return false, "no tooltip" end
	local before = tip.Position
	sandbox.advance(0.2)
	return tip.Position == before
end)())
check("leaving removes it", (function()
	tipped.Root.MouseLeave:Fire()
	return Window._tooltip == nil
end)())
check("an empty tooltip shows nothing", (function()
	plain:SetTooltip("")
	plain.Root.MouseEnter:Fire()
	sandbox.advance(0.35)
	local shown = Window._tooltip ~= nil
	plain.Root.MouseLeave:Fire()
	return not shown
end)())
check("leaving before the delay cancels it", (function()
	tipped.Root.MouseEnter:Fire()
	tipped.Root.MouseLeave:Fire()
	sandbox.advance(0.35)
	return Window._tooltip == nil
end)())

section("a tooltip is visibly marked on its control")
check("a marked control gets a question mark", (function()
	local marker = tipped._tipMarker
	return marker ~= nil and marker.Text == "?" and marker.Visible == true
end)())
check("HasTooltip reports it", tipped.HasTooltip == true)
check("a control without a tooltip gets no marker", (function()
	local bare = tipTab:CreateToggle({ Name = "Bare", CurrentValue = false })
	task.wait(0.05)
	return bare._tipMarker == nil and bare.HasTooltip ~= true
end)())
check("the marker is parented to the control row", tipped._tipMarker.Parent == tipped.Root)
check("the marker stays inside the title's own space", (function()
	local marker = tipped._tipMarker
	local label = tipped._title
	if not label then return true end -- no title to sit beside
	local allotted = label.AbsoluteSize.X
	if allotted <= 0 then return true end
	local left = label.Position.X.Offset
	return marker.Position.X.Offset >= left
		and marker.Position.X.Offset + marker.Size.X.Offset <= left + allotted + 1,
		("marker x %d w %d, title x %d w %d"):format(marker.Position.X.Offset, marker.Size.X.Offset, left, allotted)
end)())
check("clearing the tooltip hides the marker", (function()
	tipped:SetTooltip("")
	local hidden = tipped._tipMarker.Visible == false and tipped.HasTooltip == false
	tipped:SetTooltip(tipText)
	return hidden and tipped._tipMarker.Visible == true
end)())

section("locks state a precondition instead of failing after the click")
local lockTab = Window:CreateTab("Locks", "settings")
lockTab:CreateSection("Locks")
local lockable = lockTab:CreateToggle({ Name = "Needs a container", CurrentValue = false })
check("Lock marks the element and states a reason", (function()
	lockable:Lock("enter a container ID")
	-- LockReason is the authoritative value. The badge collapses to "LOCKED" or to the
	-- padlock alone when the row is too narrow to show the reason AND the title, and this
	-- sandbox reports the window's rect for every AbsoluteSize, so the rendered text is not
	-- something to assert on here.
	return lockable.Locked == true and lockable.LockReason == "enter a container ID"
		and lockable._lock ~= nil and lockable._lock.Badge ~= nil and lockable._lock.Icon ~= nil
end)())
check("locking again only updates the reason", (function()
	local overlay = lockable._lock.Root
	lockable:Lock("Conquest Auto-Hop is on")
	return lockable._lock.Root == overlay and lockable.LockReason == "Conquest Auto-Hop is on"
end)())
check("the badge is never wider than the row allows", (function()
	local cap
	for _, child in ipairs(lockable._lock.Badge:GetChildren()) do
		if child.ClassName == "UISizeConstraint" then cap = child end
	end
	return cap ~= nil and cap.MaxSize.X >= cap.MinSize.X, cap and ("min %d max %d"):format(cap.MinSize.X, cap.MaxSize.X)
end)())
check("the scrim dims the row it covers", lockable._lock.Root.BackgroundTransparency < 1)
check("Unlock clears everything", (function()
	lockable:Unlock()
	return lockable.Locked == false and lockable.LockReason == nil and lockable._lock == nil
end)())
check("SetLocked expresses the rule in one call", (function()
	lockable:SetLocked(true, "because")
	local locked = lockable.Locked
	lockable:SetLocked(false)
	return locked and lockable.Locked == false
end)())

section("confirmation dialogs")
check("Confirm builds a two-button dialog", (function()
	local dialog = Window:Confirm({ Title = "Delete?", Content = "Gone for good.", OnConfirm = function() end })
	local found = {}
	for _, child in ipairs(dialog.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text ~= "" and child.Text ~= "×" then
			table.insert(found, child.Text)
		end
	end
	dialog:Close()
	return #found == 2 and found[1] == "Cancel" and found[2] == "Confirm", table.concat(found, ",")
end)())
check("the confirm button runs the action and cancel does not", (function()
	local ran = 0
	local dialog = Window:Confirm({ Content = "?", OnConfirm = function() ran += 1 end })
	for _, child in ipairs(dialog.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text == "Cancel" then child.MouseButton1Click:Fire() end
	end
	local afterCancel = ran
	local second = Window:Confirm({ Content = "?", OnConfirm = function() ran += 1 end })
	for _, child in ipairs(second.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text == "Confirm" then child.MouseButton1Click:Fire() end
	end
	return afterCancel == 0 and ran == 1, ran
end)())
check("the action fires only once even on a double click", (function()
	local ran = 0
	local dialog = Window:Confirm({ Content = "?", OnConfirm = function() ran += 1 end })
	for _, child in ipairs(dialog.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text == "Confirm" then
			child.MouseButton1Click:Fire()
			child.MouseButton1Click:Fire()
		end
	end
	return ran == 1, ran
end)())
check("custom button text is honoured", (function()
	local dialog = Window:Confirm({ Content = "?", ConfirmText = "Empty it", CancelText = "Keep it" })
	local labels = {}
	for _, child in ipairs(dialog.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text ~= "" and child.Text ~= "×" then table.insert(labels, child.Text) end
	end
	dialog:Close()
	return table.concat(labels, ",") == "Keep it,Empty it", table.concat(labels, ",")
end)())
check("a transient dialog does not linger in the tree", (function()
	-- The teardown runs on a delay so the close animation can finish; advance the sandbox
	-- clock rather than sleeping, the same way the autosave debounce is tested.
	local before = #Window.ScreenGui:GetChildren()
	local dialog = Window:Confirm({ Content = "?" })
	dialog:Close()
	sandbox.advance(0.4)
	return #Window.ScreenGui:GetChildren() <= before,
		("%d children, expected %d"):format(#Window.ScreenGui:GetChildren(), before)
end)())
check("a danger button is tinted apart from the cancel", (function()
	local dialog = Window:Confirm({ Content = "?" })
	local cancel, confirm
	for _, child in ipairs(dialog.Panel:GetDescendants()) do
		if child.ClassName == "TextButton" and child.Text == "Cancel" then cancel = child end
		if child.ClassName == "TextButton" and child.Text == "Confirm" then confirm = child end
	end
	dialog:Close()
	return cancel and confirm and confirm.BackgroundColor3 ~= cancel.BackgroundColor3
end)())

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
