--!nocheck
-- Functional test for argon-ui.luau running under Lune with a Roblox API sandbox.
-- Exercises real library code: window/tab/section creation, all 18 controls, the new
-- components, and the configuration save/load round-trip.

local process = require("@lune/process")
local fs = require("@lune/fs")
-- Resolve the library whether the suite is run from the repo root or from tests/.
local ARGON_PATH = process.args[1] or (fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau")
local sandbox = require("./sandbox")
-- The sandbox's task is what the library schedules against, so yielding through it is what
-- actually lets a deferred relayout or a theme repaint run.
local task = sandbox.environment.task or require("@lune/task")
local UDim2 = sandbox.environment.UDim2
-- The suite runs as a normal Lune script, not inside the sandbox, so the Roblox globals the
-- library sees are not in scope here unless they are bound explicitly.
local Enum = sandbox.environment.Enum

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
check("version is 2.0.0", Argon.Version == "2.0.0", Argon.Version)
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
-- v2: an unknown value is ignored and the selection is kept (v1 cleared it).
check("dropdown ignores unknown option", dropdown.CurrentOption[1] == "B", tostring(dropdown.CurrentOption[1]))

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
-- v2: rows lay out with engine flex (UIFlexItem + wrapping), so there is no Lua balancing pass.
-- _balance and _relayout stay as callable no-op seams.
check("_balance is a no-op seam that returns the row", (function()
	local heightRow = rowTab:CreateRow({ Columns = 2 })
	heightRow:CreateToggle({ Name = "Short", CurrentValue = false })
	heightRow:CreateSegmented({ Name = "Tall", Options = { "A", "B" }, CurrentOption = "A" })
	return heightRow._balance() == heightRow and heightRow._relayout() == heightRow
end)())
check("columns flex instead of being resized from Lua", (function()
	local row = rowTab:CreateRow({ Columns = 2 })
	row:CreateToggle({ Name = "Flex", CurrentValue = false })
	local holder = row.Columns[1].Holder
	return holder:FindFirstChildOfClass("UIFlexItem") ~= nil and holder:FindFirstChildOfClass("UISizeConstraint") ~= nil
end)())
check("a lone control on a line keeps its own row height", (function()
	local oddRow = rowTab:CreateRow({ Columns = 2 })
	oddRow:CreateToggle({ Name = "One", CurrentValue = false })
	oddRow:CreateToggle({ Name = "Two", CurrentValue = false })
	local three = oddRow:CreateToggle({ Name = "Three", CurrentValue = false })
	return three.Root.Size.Y.Offset == 44, three.Root.Size.Y.Offset
end)())
check("relayout cannot re-enter itself", (function()
	-- Regression: relayout writes row.Root.Size and was also connected to that frame's
	-- AbsoluteSize, so every write re-entered the handler until Roblox bailed out with
	-- "Maximum event re-entrancy depth exceeded for Object.AbsoluteSizeChanged" — 212 of
	-- them in one live session. Re-entering must be a no-op, not a chain.
	local row = rowTab:CreateRow({ Columns = 2 })
	row:CreateToggle({ Name = "Reentry", CurrentValue = false })
	row:CreateSlider({ Name = "ReentryB", Range = { 0, 10 }, Increment = 1, CurrentValue = 3 })
	task.wait(0.1)
	local depth, deepest, entered = 0, 0, 0
	local connection = row.Root:GetPropertyChangedSignal("Size"):Connect(function()
		entered += 1
		depth += 1
		if depth > deepest then deepest = depth end
		row._relayout() -- exactly what the AbsoluteSize listener used to do
		depth -= 1
	end)
	row.Root.Size = UDim2.new(1, 0, 0, 999)
	connection:Disconnect()
	return entered > 0 and deepest <= 2, ("entered %d, deepest %d"):format(entered, deepest)
end)())
check("repeated relayout passes settle on one size", (function()
	local row = rowTab:CreateRow({ Columns = 2 })
	row:CreateToggle({ Name = "Settle", CurrentValue = false })
	row:CreateSlider({ Name = "SettleB", Range = { 0, 10 }, Increment = 1, CurrentValue = 3 })
	task.wait(0.1)
	row._relayout()
	local settled = row.Root.Size
	for _ = 1, 6 do row._relayout() end
	return row.Root.Size == settled, tostring(row.Root.Size)
end)())
check("row controls follow a theme switch", (function()
	Argon:SetTheme("Ocean")
	for _ = 1, 40 do
		-- v2: rows have no fill of their own; the root carries the Hover token (the pooled hover fill)
		if rowLeft.Root.BackgroundColor3 == Argon.Themes.Ocean.Hover then return true end
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
-- v2: the off track uses the Track token (1.6:1 over the platter), not the Input well colour.
check("an off toggle keeps the off colour after a theme switch",
	trackOf(offToggle).BackgroundColor3 == Argon.Themes.Emerald.Track,
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
-- v2: the row is 44 tall without a description and grows (and auto-sizes) with one.
check("the slider grew past its natural height", descSlider.Root.Size.Y.Offset > 44, descSlider.Root.Size.Y.Offset)
-- v2: descriptions sit in the text column, left of the control, instead of under it.
check("the description sits in the text column, clear of the slider", (function()
	local desc = descriptionOf(descSlider)
	local hit = descSlider.Root:FindFirstChild("Hit")
	if not desc or not hit then return false, "description or Hit band missing" end
	return desc.AbsolutePosition.X + desc.AbsoluteSize.X <= hit.AbsolutePosition.X + 1,
		("desc right %d, hit left %d"):format(desc.AbsolutePosition.X + desc.AbsoluteSize.X, hit.AbsolutePosition.X)
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
-- v2: the hover delay is 0.40 s (DESIGN_V2 motion token "tooltip").
check("hovering opens a wrapped, self-sizing tooltip", (function()
	sandbox.advance(0.45)
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
	sandbox.advance(0.45)
	local shown = Window._tooltip ~= nil
	plain.Root.MouseLeave:Fire()
	return not shown
end)())
check("leaving before the delay cancels it", (function()
	tipped.Root.MouseEnter:Fire()
	tipped.Root.MouseLeave:Fire()
	sandbox.advance(0.45)
	return Window._tooltip == nil
end)())

section("a tooltip is visibly marked on its control")
-- v2: the marker is an info glyph (an ImageButton named TipMarker), not a "?" text glyph.
check("a marked control gets a tooltip marker", (function()
	local marker = tipped._tipMarker
	return marker ~= nil and marker.Name == "TipMarker" and marker.Visible == true
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
-- Open it: the topbar controls are hidden while the loader holds the window at pill width, which
-- the harness can now actually measure.
jsonWindow:FinishLoading()
sandbox.advance(1.5)
local jsonTab = jsonWindow:CreateTab("Main", "zap")
jsonTab:CreateToggle({ Flag = "J_Toggle", Name = "Toggle", CurrentValue = true })
Argon:SaveConfiguration()
check("extension not double-appended", sandbox.files["JsonHub/settings.json"] ~= nil,
	table.concat((function() local out = {} for path in pairs(sandbox.files) do out[#out + 1] = path end return out end)(), ", "))

section("themes, notifications, dialog")
-- v2 adds Daylight and HighContrast to the ten v1 themes.
check("GetThemes lists all built-ins", (function()
	local names = {}
	for _, name in ipairs(Argon:GetThemes()) do names[name] = true end
	for _, name in ipairs({ "Argon", "Amethyst", "Midnight", "Emerald", "Rose", "Slate", "Ember", "Nord", "Mono", "Ocean", "Daylight", "HighContrast" }) do
		if not names[name] then return false, "missing " .. name end
	end
	return true
end)())
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
		if toggle.Root.BackgroundColor3 == Argon.Themes.Ember.Hover then return true end
		task.wait()
	end
	return false, tostring(toggle.Root.BackgroundColor3)
end)())
section("the topbar theme picker")
-- v2: the picker lives in the popover layer; Window.ThemePicker is its content frame.
local themePicker = jsonWindow.ThemePicker
local themeOptions = themePicker and themePicker:FindFirstChild("ThemeOptions")
check("the picker panel exists and starts closed", themePicker ~= nil and themePicker.Visible == false)
check("ToggleThemePicker opens it", (function()
	Argon:SetTheme("Argon")
	return jsonWindow:ToggleThemePicker() == true and themePicker.Visible == true
end)())
check("it builds one swatch per registered theme", (function()
	local built = 0
	for _, child in ipairs(themeOptions:GetChildren()) do
		if child:IsA("TextButton") then built += 1 end
	end
	return built == #Argon:GetThemes(), built .. " of " .. #Argon:GetThemes()
end)())
check("each swatch previews its own palette, not the active one", (function()
	-- Regression guard: a theme binding on these dots would repaint every swatch to the
	-- live palette, making all ten options look identical.
	local ocean = themeOptions:FindFirstChild("Ocean")
	if not ocean then return false, "no Ocean swatch" end
	for _, dot in ipairs(ocean:GetChildren()) do
		if dot:IsA("Frame") and dot.BackgroundColor3 == Argon.Themes.Ocean.Accent then return true end
	end
	return false, "no dot carried Ocean's accent"
end)())
check("picking a swatch switches the theme", (function()
	themeOptions.Emerald.MouseButton1Click:Fire()
	task.wait()
	return Argon.CurrentTheme == "Emerald" and Argon:GetColor("Accent") == Argon.Themes.Emerald.Accent
end)())
check("the active swatch is outlined with the accent", (function()
	local outline = themeOptions.Emerald:FindFirstChildOfClass("UIStroke")
	return outline ~= nil and outline.Color == Argon.Themes.Emerald.Accent, outline and tostring(outline.Color)
end)())
check("a theme switch from elsewhere restyles the picker", (function()
	Argon:SetTheme("Rose")
	task.wait()
	local emerald = themeOptions.Emerald:FindFirstChildOfClass("UIStroke")
	local rose = themeOptions.Rose:FindFirstChildOfClass("UIStroke")
	return rose.Color == Argon.Themes.Rose.Accent and emerald.Color ~= Argon.Themes.Rose.Accent
end)())
check("ToggleThemePicker closes it again", (function()
	return jsonWindow:ToggleThemePicker() == false and themePicker.Visible == false
end)())
-- v2: the button sits in the topbar's Actions group, so it is found recursively.
check("SetThemePickerVisible(false) hides the button and panel", (function()
	jsonWindow:ToggleThemePicker()
	jsonWindow:SetThemePickerVisible(false)
	local button = jsonWindow.Content.TopBar:FindFirstChild("ThemeButton", true)
	return themePicker.Visible == false and button ~= nil and button.Visible == false
end)())
check("SetThemePickerVisible(true) brings it back", (function()
	jsonWindow:SetThemePickerVisible(true)
	local button = jsonWindow.Content.TopBar:FindFirstChild("ThemeButton", true)
	return button.Visible == true and jsonWindow:ToggleThemePicker() == true
end)())
Argon:SetTheme("Argon")

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
-- Overlays are deliberately held back while the loading cover is up, so this window has to
-- finish loading before its overlay visibility means anything.
overlayWindow:FinishLoading()
-- v2: the keybind list sizes to its content and hides when there are no binds, so give it one.
overlayWindow:CreateTab("Main", "zap"):CreateKeybind({ Name = "Dash", CurrentKeybind = "Q", OnPressed = function() end })
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

section("the selected tab follows a theme switch")
-- v2: one shared indicator (a glass pill plus a 3 px bar with the accent gradient) marks the
-- selected tab; its title and icon use Text, inactive ones Text2 (Muted is not used on glass).
local function barAccent()
	local bar = Window.ActiveTab.Accent
	local gradient = bar and bar:FindFirstChildOfClass("UIGradient")
	local points = gradient and gradient.Color.Keypoints
	return points and points[#points].Value
end
check("the active tab starts on the accent", (function()
	Argon:SetTheme("Argon")
	task.wait()
	local active = Window.ActiveTab
	return active ~= nil and barAccent() == Argon.Themes.Argon.Accent, tostring(barAccent())
end)())
check("the active tab repaints to the new accent", (function()
	Argon:SetTheme("Emerald")
	for _ = 1, 40 do
		if barAccent() == Argon.Themes.Emerald.Accent then return true end
		task.wait()
	end
	return false, tostring(barAccent())
end)())
check("the active tab's title repaints too", Window.ActiveTab.ButtonTitle.TextColor3 == Argon.Themes.Emerald.Text,
	tostring(Window.ActiveTab.ButtonTitle.TextColor3))
check("an inactive tab stays on the secondary text colour", (function()
	local inactive
	for _, candidate in ipairs(Window.Tabs) do
		if candidate ~= Window.ActiveTab then inactive = candidate break end
	end
	if not inactive then return true end
	return inactive.ButtonTitle.TextColor3 == Argon.Themes.Emerald.Text2,
		tostring(inactive.ButtonTitle.TextColor3)
end)())
Argon:SetTheme("Argon")

section("text controls grow with their text")
local growTab = Window:CreateTab("Grow", "server")
growTab:CreateSection("Growth")
local longCopy = "A deliberately long body so the control has to grow to fit it. These three used to be fixed-height rows with a fixed-height text slot on a root that clips, so anything past two short lines was simply cut off and a short value left dead space behind."
local grownLabel = growTab:CreateLabel(longCopy)
local grownParagraph = growTab:CreateParagraph({ Title = "Wrapped", Content = longCopy })
local grownCard = growTab:CreateTelemetryCard({ Title = "Card", Content = longCopy })
local function wrappedBody(element)
	for _, child in ipairs(element.Root:GetDescendants()) do
		if child.ClassName == "TextLabel" and child.TextWrapped and child.AutomaticSize == Enum.AutomaticSize.Y then
			return child
		end
	end
	return nil
end
for _, entry in ipairs({
	{ "Label", grownLabel }, { "Paragraph", grownParagraph }, { "TelemetryCard", grownCard },
}) do
	local name, element = entry[1], entry[2]
	local root = type(element) == "table" and element.Root or nil
	check(name .. " sizes itself to its content", root ~= nil and root.AutomaticSize == Enum.AutomaticSize.Y,
		root and tostring(root.AutomaticSize) or ("no root, got " .. type(element)))
	check(name .. " wraps its body instead of clipping it", root ~= nil and wrappedBody(element) ~= nil)
end
check("Label:Set replaces the copy", (function()
	grownLabel:Set("short")
	return grownLabel.CurrentValue == "short"
end)())
check("the telemetry status pill sizes to its own text", grownCard.Status.AutomaticSize == Enum.AutomaticSize.X,
	tostring(grownCard.Status.AutomaticSize))
check("SetStatus recolours the pill and its outline", (function()
	local green = sandbox.environment.Color3.fromRGB(99, 223, 160)
	grownCard:SetStatus("READY", green)
	local outline
	for _, child in ipairs(grownCard.Status:GetChildren()) do
		if child.ClassName == "UIStroke" then outline = child end
	end
	return grownCard.Status.Text == "READY" and grownCard.Status.TextColor3 == green
		and outline ~= nil and outline.Color == green
end)())

section("long input values are elided until focused")
local urlTab = Window:CreateTab("Urls", "server")
urlTab:CreateSection("Fields")
local longUrl = "https://discord.com/api/webhooks/1523331338155982949/RvztQ8kLmNoPqRsTuVwXyZ0123456789abcdef"
local urlInput = urlTab:CreateInput({ Flag = "U_Url", Name = "Webhook", CurrentValue = longUrl })
local urlBox
for _, child in ipairs(urlInput.Root:GetDescendants()) do
	if child.ClassName == "TextBox" then urlBox = child end
end
check("the stored value is the full text", urlInput.CurrentValue == longUrl)
check("the field shows an elided form, not the whole line", urlBox ~= nil and urlBox.Text ~= longUrl and #urlBox.Text < #longUrl,
	urlBox and urlBox.Text)
check("the elided form keeps the head and the tail", (function()
	return urlBox.Text:find("discord.com", 1, true) ~= nil and urlBox.Text:sub(-6) == longUrl:sub(-6), urlBox.Text
end)())
check("the scheme is dropped for display only", urlBox.Text:sub(1, 4) ~= "http" and urlInput.CurrentValue:sub(1, 5) == "https")
check("focusing restores the real text for editing", (function()
	urlBox.Focused:Fire()
	return urlBox.Text == longUrl, urlBox.Text
end)())
check("blurring commits and re-elides", (function()
	urlBox.Text = "https://example.com/a/very/long/path/that/should/also/be/elided/for/display"
	urlBox.FocusLost:Fire(true)
	return urlInput.CurrentValue == "https://example.com/a/very/long/path/that/should/also/be/elided/for/display"
		and urlBox.Text ~= urlInput.CurrentValue, urlBox.Text
end)())
check("a short value is shown in full", (function()
	urlInput:Set("hello")
	return urlBox.Text == "hello", urlBox.Text
end)())
check("Set(silent) still updates the display", (function()
	urlInput:Set("quiet", true)
	return urlInput.CurrentValue == "quiet" and urlBox.Text == "quiet"
end)())

section("notifications outlive the window being hidden")
-- Notify targets the most recently created window, and this suite has built several, so assert
-- against that one rather than against the first.
local notifyWindow = Argon._windows[#Argon._windows]
check("the toast layer is not parented to the window frame", (function()
	return notifyWindow.Notifications.Parent == notifyWindow.ScreenGui
end)())
check("hiding the window leaves the toast layer visible", (function()
	notifyWindow:SetVisibility(false)
	local shown = notifyWindow.Notifications.Visible
	notifyWindow:SetVisibility(true)
	return shown == true
end)())
local function liveToasts()
	local count = 0
	for _, child in ipairs(notifyWindow.Notifications:GetChildren()) do
		-- v2: toast cards are plain Frames named Toast (no CanvasGroups)
		if child.Name == "Toast" then count += 1 end
	end
	return count
end
check("a toast is built while the window is hidden", (function()
	notifyWindow:SetVisibility(false)
	local before = liveToasts()
	Argon:Notify({ Title = "Background", Content = "Fired with the menu closed.", Duration = 9 })
	local after = liveToasts()
	notifyWindow:SetVisibility(true)
	return after > before, ("%d -> %d"):format(before, after)
end)())
check("a toast sizes itself to its body", (function()
	local toast = Argon:Notify({ Title = "Long", Content = string.rep("wrapped body text ", 20), Duration = 3 })
	return toast ~= nil and toast.AutomaticSize == Enum.AutomaticSize.Y, toast and tostring(toast.AutomaticSize)
end)())
check("the severity is taken from the title", (function()
	local failed = Argon:Notify({ Title = "Save failed", Content = "x", Duration = 2 })
	local ok = Argon:Notify({ Title = "Configuration saved", Content = "x", Duration = 2 })
	-- v2: the type icon (on a 28 px Soft plate) carries the status colour
	local function tint(toast)
		for _, child in ipairs(toast:GetDescendants()) do
			if child.Name == "TypeIcon" then return child.ImageColor3 end
		end
		return nil
	end
	return tint(failed) == Argon:GetColor("Danger") and tint(ok) == Argon:GetColor("Success"),
		tostring(tint(failed)) .. " / " .. tostring(tint(ok))
end)())
check("the stack is capped", (function()
	for index = 1, 9 do Argon:Notify({ Title = "Spam " .. index, Content = "x", Duration = 9 }) end
	return liveToasts() <= 5, liveToasts()
end)())

section("section navigation is a chip rail, not a popover")
local railTab = Window:CreateTab("Rail", "server")
railTab:CreateSection("One")
local jumpRail = Window.Content:FindFirstChild("JumpRail")
check("the rail exists under the topbar", jumpRail ~= nil)
check("a single section shows no rail", (function()
	Window:_select(railTab)
	task.wait()
	return jumpRail.Visible == false
end)())
check("more sections bring the rail in", (function()
	railTab:CreateSection("Two")
	railTab:CreateSection("Three")
	Window:_refreshSectionMenu()
	return jumpRail.Visible == true
end)())
check("one chip per section, in order", (function()
	local strip
	for _, child in ipairs(jumpRail:GetChildren()) do
		if child.ClassName == "ScrollingFrame" then strip = child end
	end
	local chips = {}
	for _, child in ipairs(strip:GetChildren()) do
		if child.ClassName == "TextButton" then table.insert(chips, child) end
	end
	table.sort(chips, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	return #chips == 3 and chips[1].Text == "One" and chips[3].Text == "Three",
		#chips .. " chips"
end)())
check("the strip scrolls horizontally when it overflows", (function()
	local strip
	for _, child in ipairs(jumpRail:GetChildren()) do
		if child.ClassName == "ScrollingFrame" then strip = child end
	end
	return strip.ScrollingDirection == Enum.ScrollingDirection.X, tostring(strip.ScrollingDirection)
end)())
check("filtering hides the rail, clearing brings it back", (function()
	railTab:_filter("zzz")
	local hidden = jumpRail.Visible == false
	railTab:_filter("")
	return hidden and jumpRail.Visible == true
end)())
check("the SECTIONS button is gone from the topbar", (function()
	for _, child in ipairs(Window.Content.TopBar:GetChildren()) do
		if child.ClassName == "TextButton" and child.Text == "SECTIONS" then return false end
	end
	return true
end)())
Window:_select(Window.Tabs[1])

section("typography is a body face and a display face, and both can be switched")
check("labels get a FontFace, not just a legacy Font", (function()
	local label = Window.Tabs[1].ButtonTitle
	return label.FontFace ~= nil and tostring(label.FontFace.Family):find("Roboto", 1, true) ~= nil,
		label.FontFace and tostring(label.FontFace.Family)
end)())
check("buttons built outside the text helper get it too", (function()
	-- TextButtons and TextBoxes set only .Font before, so half the interface rendered with the
	-- legacy raster face while labels used the modern one.
	local button = urlTab:CreateButton({ Name = "Faced" })
	local face
	for _, child in ipairs(button.Root:GetDescendants()) do
		if child.ClassName == "TextLabel" and child.FontFace then face = child.FontFace end
	end
	return face ~= nil and tostring(face.Family):find("Roboto", 1, true) ~= nil, face and tostring(face.Family)
end)())
check("headings use the display face, not the body face", (function()
	-- Section headers, the page title and the sidebar brand are the display slot. Every family
	-- offered was checked in a live client; Inter, Rubik, Poppins, Manrope, PlusJakartaSans and
	-- DarkerGrotesque all fail to load and silently fall back, so none of them is on the list.
	local headingTab = Argon:CreateWindow({ Name = "Heading", GuiName = "ArgonHeadingTest" })
	headingTab:FinishLoading()
	local built = headingTab:CreateTab("Main", "zap")
	built:CreateSection("Look and feel")
	local heading
	for _, child in ipairs(built.Page:GetDescendants()) do
		-- v2: sentence case everywhere (no ALL CAPS chrome)
		if child.ClassName == "TextLabel" and child.Text == "Look and feel" then heading = child end
	end
	return heading ~= nil and tostring(heading.FontFace.Family):find("Montserrat", 1, true) ~= nil,
		heading and tostring(heading.FontFace.Family)
end)())
check("SetFont repaints the live interface", (function()
	local label = Window.Tabs[1].ButtonTitle
	Argon:SetFont("Ubuntu")
	local switched = tostring(label.FontFace.Family)
	Argon:SetFont("Roboto")
	return switched:find("Ubuntu", 1, true) ~= nil and tostring(label.FontFace.Family):find("Roboto", 1, true) ~= nil,
		switched .. " -> " .. tostring(label.FontFace.Family)
end)())
check("an unknown family is refused rather than applied", (function()
	Argon:SetFont("Comic Sans")
	return Argon.CurrentFont == "Roboto", Argon.CurrentFont
end)())
check("GetFonts lists only families that load", (function()
	local offered = table.concat(Argon:GetFonts(), ",")
	return offered:find("Roboto", 1, true) ~= nil and offered:find("Inter", 1, true) == nil, offered
end)())

section("the loader waits for the host instead of a timer")
-- v2 has no fixed timers. A card appears only while real work is still pending after 150 ms,
-- and the window opens when the host is done: its thread ended, it called FinishLoading, or it
-- built a tab and then went quiet for 250 ms.
local loadWindow = Argon:CreateWindow({ Name = "Loader", GuiName = "ArgonLoaderTest" })
check("a new window starts covered", loadWindow:IsLoading() == true)
check("SetLoadingProgress keeps it covered past the old timer", (function()
	loadWindow:SetLoadingProgress(0.2, "Building combat")
	sandbox.advance(2)
	return loadWindow:IsLoading() == true
end)())
check("progress never runs backwards", (function()
	loadWindow:SetLoadingProgress(0.8, "Building visuals")
	loadWindow:SetLoadingProgress(0.3, "Late stage")
	return loadWindow._loadingProgress >= 0.8, loadWindow._loadingProgress
end)())
check("FinishLoading uncovers it", (function()
	loadWindow:FinishLoading()
	return loadWindow:IsLoading() == false
end)())
check("FinishLoading twice is harmless", (pcall(function() loadWindow:FinishLoading() end)))
check("a host whose script has finished opens on its own", (function()
	local silent
	task.spawn(function()
		silent = Argon:CreateWindow({ Name = "Silent", GuiName = "ArgonSilentTest" })
	end)
	sandbox.advance(0.5)
	return silent ~= nil and silent:IsLoading() == false
end)())
check("a host that builds a tab and goes quiet opens after the quiet period", (function()
	local quiet = Argon:CreateWindow({ Name = "Quiet", GuiName = "ArgonQuietTest" })
	quiet:CreateTab("Main", "zap"):CreateToggle({ Name = "Fly", CurrentValue = false })
	sandbox.advance(1)
	return quiet:IsLoading() == false
end)())
check("Loading = manual survives with no progress reported at all", (function()
	local manual = Argon:CreateWindow({ Name = "Manual", GuiName = "ArgonManualTest", Loading = "manual" })
	sandbox.advance(3)
	local held = manual:IsLoading()
	manual:FinishLoading()
	return held == true and manual:IsLoading() == false, "held=" .. tostring(held)
end)())
check("the loader is a compact card, not the window shrunk to a pill", (function()
	local pill = Argon:CreateWindow({ Name = "Pill", GuiName = "ArgonPillTest", Loading = "manual" })
	pill:SetLoadingProgress(0.5, "Building")
	local card = pill._loader and pill._loader.Card
	local width = card and card.Size.X.Offset or 0
	pill:FinishLoading()
	return card ~= nil and width < 400, width
end)())
check("overlays stay behind the cover until loading finishes", (function()
	local held = Argon:CreateWindow({ Name = "Held", GuiName = "ArgonHeldTest", Loading = "manual" })
	held:SetPlayerListVisible(true)
	held:SetKeybindListVisible(true)
	-- v2: reads the overlays themselves (the v1 test looked for names nothing had, so it could not fail)
	local hidden = held.PlayerListOverlay.Visible == false and held.KeybindListOverlay.Visible == false
	held:FinishLoading()
	local shown = held.PlayerListOverlay.Visible == true
	return hidden and shown, ("hidden=%s shown=%s"):format(tostring(hidden), tostring(shown))
end)())
check("the window is built at full size behind the card and revealed whole", (function()
	local sized = Argon:CreateWindow({ Name = "Sized", GuiName = "ArgonSizedTest", Loading = "manual" })
	sized:CreateTab("Main", "zap")
	local widthWhileLoading = sized.Main.Size.X.Offset
	local hiddenWhileLoading = sized.Main.Visible == false
	sized:FinishLoading()
	sandbox.advance(1.5)
	return widthWhileLoading > 400 and hiddenWhileLoading and sized.Main.Visible == true and sized._loader == nil,
		("width %d hidden %s visible %s"):format(widthWhileLoading, tostring(hiddenWhileLoading), tostring(sized.Main.Visible))
end)())
check("a viewport change while loading does not stretch the card", (function()
	local resized = Argon:CreateWindow({ Name = "Resized", GuiName = "ArgonResizedTest", Loading = "manual" })
	resized:CreateTab("Main", "zap")
	sandbox.setViewport(1600, 900)
	local cardWidth = resized._loader.Card.Size.X.Offset
	resized:FinishLoading()
	sandbox.advance(1.5)
	local afterLoad = resized.Main.Size.X.Offset
	sandbox.setViewport(1920, 1080)
	return cardWidth <= 380 and afterLoad > 400, ("card %d -> window %d"):format(cardWidth, afterLoad)
end)())
check("the window takes the size of the viewport it ended up with", (function()
	local grown = Argon:CreateWindow({ Name = "Grown", GuiName = "ArgonGrownTest", Loading = "manual" })
	grown:CreateTab("Main", "zap")
	sandbox.setViewport(800, 600)
	grown:FinishLoading()
	sandbox.advance(1.5)
	local width = grown.Main.Size.X.Offset
	sandbox.setViewport(1920, 1080)
	-- v2 default width (DESIGN_V2 3.2): max(min(gui - 160, 1080), min(720, gui - 16)) = 720 at 800
	return width == 720, width
end)())

section("restoring a configuration reports its own progress")
-- Restoring is where a big host spends most of its startup and it used to report nothing: one
-- status line before the call, the next only after it returned. Measured in isolation the library
-- costs 0.08ms per flag, so the time is all in host callbacks -- the loader has to say so.
check("the loader is stepped through the restore, not left on one line", (function()
	Argon._uiPreferences = {}
	local restoreWindow = Argon:CreateWindow({
		Name = "Restore",
		GuiName = "ArgonRestoreTest",
		Loading = "manual",
		ConfigurationSaving = { Enabled = true, FolderName = "RestoreBench", FileName = "restore.json" },
	})
	local restoreTab = restoreWindow:CreateTab("Main", "zap")
	for index = 1, 12 do
		restoreTab:CreateToggle({ Flag = "R_" .. index, Name = "Toggle " .. index, CurrentValue = index % 2 == 0 })
	end
	Argon:SaveConfiguration()
	restoreWindow:SetLoadingProgress(0.74, "RESTORING CONFIGURATION")
	local reports = {}
	local realSet = restoreWindow.SetLoadingProgress
	restoreWindow.SetLoadingProgress = function(self, fraction, status)
		reports[#reports + 1] = status
		return realSet(self, fraction, status)
	end
	Argon:LoadConfiguration()
	restoreWindow.SetLoadingProgress = realSet
	local counted = 0
	for _, status in ipairs(reports) do
		-- v2: sentence case, counts as "n of m"
		if tostring(status):find("Restoring settings · %d+ of %d+") then counted += 1 end
	end
	return counted >= 12, counted .. " of " .. #reports
end)())
check("progress ends just short of complete, so FinishLoading owns the last step", (function()
	local restoreWindow = Argon._windows[#Argon._windows]
	return restoreWindow._loadingProgress > 0.98 and restoreWindow._loadingProgress < 1,
		tostring(restoreWindow._loadingProgress)
end)())
check("a restore with no loader on screen still applies every flag", (function()
	local stats = Argon._lastConfigStats or {}
	return stats.applied == stats.total and stats.failed == 0,
		("applied %s of %s, failed %s"):format(tostring(stats.applied), tostring(stats.total), tostring(stats.failed))
end)())

section("a composited group is never tinted by its own gradient")
-- A UIGradient does not replace the colour under it, it multiplies it -- and on a CanvasGroup it
-- multiplies the whole composited group rather than just the background. One on the window frame
-- painted every child and all the text; one on the loader cover did the same to the logo, title,
-- status line and progress bar, so on a dark palette like Mono the loader rendered fully black.
local tintWindow = Argon:CreateWindow({ Name = "Tint", GuiName = "ArgonTintTest", Loading = "manual" })
tintWindow:CreateTab("Main", "zap")
check("no CanvasGroup carries a UIGradient of its own", (function()
	local offenders = {}
	for _, child in ipairs(tintWindow.ScreenGui:GetDescendants()) do
		if child.ClassName == "CanvasGroup" then
			for _, inner in ipairs(child:GetChildren()) do
				if inner.ClassName == "UIGradient" then table.insert(offenders, child.Name) end
			end
		end
	end
	return #offenders == 0, table.concat(offenders, ", ")
end)())
check("the window frame is a plain Frame, so resizing cannot blur its text", (function()
	-- A CanvasGroup rasterises its children into a buffer sized when the group is created and
	-- rescales that buffer when the group is resized instead of redrawing it. Measured live,
	-- dragging the window from 980px to 680px left every label visibly soft.
	return tintWindow.Main.ClassName == "Frame", tintWindow.Main.ClassName
end)())
check("the window frame carries its own shade gradient", (function()
	return tintWindow.Main:FindFirstChildOfClass("UIGradient") ~= nil
end)())
check("pages are plain Frames too", (function()
	return tintWindow.Tabs[1].PageGroup.ClassName == "Frame", tintWindow.Tabs[1].PageGroup.ClassName
end)())
check("the loader cover is a plain Frame, because it is resized as it opens", (function()
	local cover
	for _, child in ipairs(tintWindow.ScreenGui:GetDescendants()) do
		if child.Name == "Loader" then cover = child end
	end
	return cover ~= nil and cover.ClassName == "Frame", cover and cover.ClassName
end)())
check("the sidebar rounds its own corners and squares off its right edge", (function()
	-- The window clips to a rectangle, not to its UICorner, so a square-cornered sidebar painted
	-- straight over the window's rounded left edge.
	local rounded = tintWindow.Sidebar:FindFirstChildOfClass("UICorner") ~= nil
	local patch = tintWindow.Sidebar:FindFirstChild("SquareEdge")
	return rounded and patch ~= nil and patch.Size == UDim2.new(0, 16, 1, 0)
end)())
check("resizing by hand re-runs the layout, so the compact sidebar engages", (function()
	-- Only viewport changes used to trigger the layout pass, so dragging the window narrow left
	-- the full 232px sidebar and the search field in place well past the point they fit.
	local sizedWindow = Argon:CreateWindow({ Name = "Handle", GuiName = "ArgonHandleTest" })
	sizedWindow:FinishLoading()
	sandbox.advance(1.5)
	local wide = sizedWindow.Sidebar.Size.X.Offset
	sizedWindow:SetSize({ 620, 460 })
	local narrow = sizedWindow.Sidebar.Size.X.Offset
	sizedWindow:SetSize({ 980, 660 })
	-- v2: the narrow layout is a 64 px icon rail
	return wide == 232 and narrow == 64 and sizedWindow.Sidebar.Size.X.Offset == 232,
		("%d -> %d -> %d"):format(wide, narrow, sizedWindow.Sidebar.Size.X.Offset)
end)())
-- v2 uses no CanvasGroup at all (glows are pooled images, fades use one veil frame).
check("no composited groups anywhere", (function()
	local groups = {}
	for _, child in ipairs(tintWindow.ScreenGui:GetDescendants()) do
		if child.ClassName == "CanvasGroup" then groups[#groups + 1] = child.Name end
	end
	return #groups == 0, table.concat(groups, ", ")
end)())
check("the loader keeps its contents legible on a dark palette", (function()
	-- Mono's Window is rgb(16,16,18). Multiplied by the old Surface/Window gradient pair the
	-- cover's white title came out at about rgb(22,22,24), which is what "fully black" was.
	local previous = Argon.CurrentTheme
	Argon:SetTheme("Mono")
	local dark = Argon:CreateWindow({ Name = "Dark", GuiName = "ArgonDarkTest", Loading = "manual" })
	dark:CreateTab("Main", "zap")
	local tinted = false
	for _, child in ipairs(dark.ScreenGui:GetDescendants()) do
		if child.ClassName == "CanvasGroup" and child:FindFirstChildOfClass("UIGradient") then tinted = true end
	end
	dark:FinishLoading()
	Argon:SetTheme(previous)
	return not tinted
end)())

section("the window can be renamed, and the rename sticks")
-- Earlier suites have already saved preferences, and a saved rename deliberately outranks the
-- host's option, so start from a clean preference table.
Argon._uiPreferences = {}
local namedWindow = Argon:CreateWindow({ Name = "Host Name", Subtitle = "Host Sub", GuiName = "ArgonNameTest" })
namedWindow:FinishLoading()
check("the host's name and subtitle are used when nothing is saved", (function()
	return namedWindow:GetTitle() == "Host Name" and namedWindow:GetSubtitle() == "Host Sub",
		namedWindow:GetTitle() .. " / " .. namedWindow:GetSubtitle()
end)())
check("SetTitle renames the sidebar", (function()
	namedWindow:SetTitle("  Nightfall  ")
	return namedWindow:GetTitle() == "Nightfall", namedWindow:GetTitle()
end)())
check("SetSubtitle renames the line under it", (function()
	namedWindow:SetSubtitle("private build")
	return namedWindow:GetSubtitle() == "private build", namedWindow:GetSubtitle()
end)())
-- v2: the subtitle is shown as given (sentence case; no upper-casing)
check("the subtitle is drawn as given", (function()
	local shown
	for _, child in ipairs(namedWindow.Sidebar:GetDescendants()) do
		if child.ClassName == "TextLabel" and child.Text == "private build" then shown = child.Text end
	end
	return shown == "private build" and namedWindow:GetSubtitle() == "private build"
end)())
check("clearing a field restores the host's value rather than blanking it", (function()
	namedWindow:SetTitle("")
	namedWindow:SetSubtitle("   ")
	return namedWindow:GetTitle() == "Host Name" and namedWindow:GetSubtitle() == "Host Sub",
		namedWindow:GetTitle() .. " / " .. namedWindow:GetSubtitle()
end)())
check("the rename and the typeface are exported for persistence", (function()
	namedWindow:SetTitle("Nightfall")
	Argon:SetFont("Ubuntu")
	local exported = namedWindow:_exportUIPreferences()
	Argon:SetFont("Roboto")
	return exported.Title == "Nightfall" and exported.Font == "Ubuntu",
		tostring(exported.Title) .. " / " .. tostring(exported.Font)
end)())
check("a saved rename is applied before anything is drawn, so the loader shows it", (function()
	-- The loader is built before any configuration is restored, so the name has to come from the
	-- preference table at construction time or the first second of every launch shows the old one.
	Argon._uiPreferences = { Title = "Nightfall", Subtitle = "Private Build", Font = "Ubuntu" }
	local restored = Argon:CreateWindow({ Name = "Host Name", GuiName = "ArgonRestoredTest", Loading = "manual" })
	local onCover
	for _, child in ipairs(restored.ScreenGui:GetDescendants()) do
		if child.ClassName == "TextLabel" and child.Text == "Nightfall" then onCover = child end
	end
	restored:FinishLoading()
	local font = Argon.CurrentFont
	Argon._uiPreferences = {}
	Argon:SetFont("Roboto")
	return onCover ~= nil and restored:GetSubtitle() == "Private Build" and font == "Ubuntu",
		tostring(restored:GetTitle()) .. " / " .. font
end)())
check("the library settings panel exposes both rename fields", (function()
	local panelWindow = Argon:CreateWindow({ Name = "Panel", GuiName = "ArgonPanelTest" })
	panelWindow:FinishLoading()
	local settingsTab = panelWindow:CreateTab("Settings", "settings")
	panelWindow:CreateLibrarySettings(settingsTab)
	-- v2: the settings rows are views over the window's preferences, not flags; the v1 flag
	-- names still read and write those preferences.
	return Argon:GetFlagValue("ArgonUIWindowTitle") == panelWindow:GetTitle()
		and Argon:GetFlagValue("ArgonUIWindowSubtitle") == panelWindow:GetSubtitle()
		and Argon:GetFlagValue("ArgonUIFont") == Argon.CurrentFont
		and Argon.Flags.ArgonUIWindowTitle == nil
end)())

section("the window draws its own cursor when the game hides the engine one")
-- Games that draw their own pointer set MouseIconEnabled false and render it in PlayerGui, which
-- sits under CoreGui: the pointer vanishes behind the menu and you click blind.
local cursorWindow = Argon:CreateWindow({ Name = "Cursor", GuiName = "ArgonCursorTest" })
cursorWindow:FinishLoading()
check("the cursor lives on its own ScreenGui", cursorWindow.CursorGui ~= nil
	and cursorWindow.CursorGui ~= cursorWindow.ScreenGui)
check("it sits above every layer we own", (function()
	return cursorWindow.CursorGui.DisplayOrder > cursorWindow.ScreenGui.DisplayOrder,
		cursorWindow.CursorGui.DisplayOrder .. " vs " .. cursorWindow.ScreenGui.DisplayOrder
end)())
check("it ignores the GUI inset so it can track the real pointer", cursorWindow.CursorGui.IgnoreGuiInset == true)
check("Cursor = false opts out", (function()
	local bare = Argon:CreateWindow({ Name = "NoCursor", GuiName = "ArgonNoCursorTest", Cursor = false })
	bare:FinishLoading()
	return bare:IsCursorDrawn() == false
end)())
check("SetCursorVisible(false) turns it off at runtime", (function()
	cursorWindow:SetCursorVisible(false)
	return cursorWindow:IsCursorDrawn() == false and cursorWindow._cursorMode == false
end)())
check("SetCursorVisible() restores automatic detection", (function()
	cursorWindow:SetCursorVisible()
	return cursorWindow._cursorMode == "auto"
end)())

section("a window can opt out of the theme picker")
-- Last, on purpose: CreateWindow resets Argon.Flags and re-gates persistence, so building a
-- throwaway window earlier would pull the rug out from under the configuration sections.
check("ThemePicker = false hides the button and refuses to open the panel", (function()
	local opted = Argon:CreateWindow({ Name = "NoPicker", GuiName = "ArgonNoPicker", ThemePicker = false })
	local button = opted.Content.TopBar:FindFirstChild("ThemeButton", true) -- v2: inside the Actions group
	local hidden = button ~= nil and button.Visible == false
	local refused = opted:ToggleThemePicker() == false
	return hidden and refused, ("hidden=%s refused=%s"):format(tostring(hidden), tostring(refused))
end)())

section("transient UI leaves nothing behind")
-- v2 has no global registries to prune: every component owns a scope that releases its
-- instances, connections and timers when it goes away.
check("PruneRegistries is kept and has nothing to drop", (function()
	local stats = Argon:PruneRegistries()
	return stats.bindings == 0 and stats.connections == 0 and #Argon._themeBindings == 0
end)())
check("dismissed toasts give their instances back", (function()
	sandbox.advance(12)
	-- a small pool of cards is kept for reuse: fill it once, then a second burst must not grow
	for index = 1, 12 do Argon:Notify({ Title = "Warm " .. index, Content = "x", Duration = 0.05 }) end
	sandbox.advance(2)
	local before = sandbox.metrics().live
	for index = 1, 12 do Argon:Notify({ Title = "Leak " .. index, Content = "x", Duration = 0.05 }) end
	sandbox.advance(2)
	local after = sandbox.metrics().live
	return after <= before + 4, ("%d -> %d live instances"):format(before, after)
end)())
check("no periodic timers keep running", (function()
	sandbox.advance(40)
	local pending = 0
	for _, entry in ipairs(sandbox.scheduled) do
		if not entry.cancelled then pending += 1 end
	end
	return pending == 0, pending .. " timers pending"
end)())
check("a theme switch still repaints the window", (function()
	Argon:SetTheme("Ocean")
	sandbox.advance(1)
	local color = Window.Tabs[1].ButtonTitle.TextColor3
	local repainted = color == Argon.Themes.Ocean.Text2 or color == Argon.Themes.Ocean.Text
	Argon:SetTheme("Argon")
	sandbox.advance(1)
	return repainted, tostring(color)
end)())

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
