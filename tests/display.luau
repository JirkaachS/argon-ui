--!nocheck
-- Display controls (Label, Paragraph, TelemetryCard and Stat, Divider, Space, ProgressBar, List,
-- Callout, Image) under the Lune sandbox: the v1 contract (api.md section 7), the v2 additions,
-- the instance budget, and that nothing warns.
--   lune run tests/display.luau [path/to/argon-ui.luau]

local process = require("@lune/process")
local fs = require("@lune/fs")
local sandbox = require("./sandbox")

local bundle
for _, arg in ipairs(process.args) do
	if arg:match("%.luau$") then bundle = arg end
end
bundle = bundle or (fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau")

local env = sandbox.environment
local Enum, Color3 = env.Enum, env.Color3

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then
		passed += 1
		print(("  PASS  %s"):format(name))
	else
		failed += 1
		print(("  FAIL  %s%s"):format(name, detail ~= nil and (" (" .. tostring(detail) .. ")") or ""))
	end
end
local function section(title)
	print("\n== " .. title .. " ==")
end
local function try(fn)
	local ok, result = pcall(fn)
	if not ok then print("        error: " .. tostring(result)) end
	return ok and result
end

local function find(root, test)
	for _, child in ipairs(root:GetDescendants()) do
		if test(child) then return child end
	end
	return nil
end
local function findAll(root, test)
	local out = {}
	for _, child in ipairs(root:GetDescendants()) do
		if test(child) then out[#out + 1] = child end
	end
	return out
end
local function named(root, name, class)
	return find(root, function(child) return child.Name == name and (class == nil or child.ClassName == class) end)
end
local function same(a, b)
	return a ~= nil and b ~= nil and math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
end

section("load")
local ok, Argon = pcall(sandbox.load, bundle)
check("bundle loads", ok, not ok and Argon or nil)
if not ok then process.exit(1) end
local Window = Argon:CreateWindow({
	Name = "Display Suite", GuiName = "DisplaySuite",
	ConfigurationSaving = { Enabled = true, FolderName = "DisplaySuite", FileName = "cfg" },
})
local Tab = Window:CreateTab("Display", "layout")
Tab:CreateSection("Controls")
local warm = Tab:CreateToggle({ Name = "Warm-up" })
local _ = warm.Root -- the tab skeleton and section exist before anything is measured
Window:FinishLoading()
sandbox.advance(1) -- the loader's own loops are gone, so running loops are ours
local palette = Argon.Themes
local function themed(token) return palette[Argon.CurrentTheme or "Argon"][token] end

-- ---------------------------------------------------------------- Label
section("Label")
do
	local label = Tab:CreateLabel("hello")
	check("CreateLabel(text) builds a Label", label.Type == "Label" and label.CurrentValue == "hello" and label.Name == "hello")
	local root = label.Root
	check("the root is a Frame sized to its text", root.ClassName == "Frame" and root.AutomaticSize == Enum.AutomaticSize.Y)
	local text = named(root, "Text", "TextLabel")
	check("the text wraps and grows", text and text.TextWrapped and text.AutomaticSize == Enum.AutomaticSize.Y)
	check("text is Body 13 in Text2 with row padding", text and text.TextSize == 13 and same(text.TextColor3, themed("Text2"))
		and text.Position.X.Offset == 16 and text.Position.Y.Offset >= 10)
	check("no icon unless asked", named(root, "Icon") == nil)
	check("Set returns self and updates Name and CurrentValue", label:Set("short") == label and label.CurrentValue == "short"
		and label.Name == "short" and text.Text == "short")
	check("SetContent is an alias", label:SetContent("alias") == label and label.CurrentValue == "alias")
	check("display rows are not focusable", (function()
		for _, element in ipairs(Window._focus:_items()) do
			if element == label then return false end
		end
		return true
	end)())

	local red = Color3.fromRGB(240, 80, 80)
	local rayfield = Tab:CreateLabel("Rayfield", "info", red, false)
	local icon = named(rayfield.Root, "Icon", "ImageLabel")
	check("CreateLabel(text, icon, color) shows the icon", icon ~= nil and icon.Visible and icon.Image ~= "")
	check("the colour tints icon and text", icon and same(icon.ImageColor3, red) and same(named(rayfield.Root, "Text").TextColor3, red))
	check("the text moves right of the icon", named(rayfield.Root, "Text").Position.X.Offset == 40)
	local blue = Color3.fromRGB(80, 120, 240)
	rayfield:Set("Again", nil, blue)
	check("Set(text, nil, color) keeps the icon and recolours", rayfield.CurrentValue == "Again" and icon.Visible and same(icon.ImageColor3, blue))
	rayfield:Set("No icon", "")
	check("Set(text, \"\") drops the icon", not icon.Visible and named(rayfield.Root, "Text").Position.X.Offset == 16)

	local tableForm = Tab:CreateLabel({ Text = "Table form", Style = "danger", Icon = "info" })
	check("CreateLabel{Text} takes its text from the table", tableForm.CurrentValue == "Table form" and tableForm.Name == "Table form")
	check("Style danger tints icon and text", same(named(tableForm.Root, "Icon").ImageColor3, themed("Danger"))
		and same(named(tableForm.Root, "Text").TextColor3, themed("Danger")))
	local warning = Tab:CreateLabel({ Title = "Heads up", Style = "warning" })
	local warnIcon = named(warning.Root, "Icon")
	check("a status Style without an icon gets its glyph", warnIcon ~= nil and warnIcon.Visible and same(warnIcon.ImageColor3, themed("Warning")))
	check("Style tints only the icon (not danger)", same(named(warning.Root, "Text").TextColor3, themed("Text2")))
	local muted = Tab:CreateLabel({ Name = "Muted", Style = "muted" })
	check("muted Style alone adds no icon", named(muted.Root, "Icon") == nil)

	local described = Tab:CreateLabel({ Text = "With a note", Description = "Second line", Tooltip = "More" })
	local note = named(described.Root, "Description", "TextLabel")
	check("Description is honoured (D15)", note ~= nil and note.Visible and note.Text == "Second line" and note.TextWrapped)
	check("Tooltip is honoured (D15)", described.HasTooltip == true and described._tooltipText == "More")
	described:SetDesc("")
	check("SetDesc(\"\") hides the note and keeps the label auto-sized", not note.Visible and described.Root.AutomaticSize == Enum.AutomaticSize.Y)
	described:SetDesc("Back")
	check("SetDesc shows it again", note.Visible and note.Text == "Back")
	check("SetTitle retitles the label", described:SetTitle("Renamed") == described and described.CurrentValue == "Renamed"
		and named(described.Root, "Text").Text == "Renamed")
	local lazy = Tab:CreateLabel("lazy")
	lazy:Set("set before mount")
	check("Set before mount is kept for the mount", rawget(lazy, "_mounted") ~= true and named(lazy.Root, "Text").Text == "set before mount")
end

-- ---------------------------------------------------------------- Paragraph
section("Paragraph")
do
	local para = Tab:CreateParagraph({ Title = "How targeting works", Content = "Nearest uses straight-line distance." })
	local root = para.Root
	check("CreateParagraph{Title, Content}", para.Type == "Paragraph" and para.Name == "How targeting works"
		and para.CurrentValue == "Nearest uses straight-line distance.")
	local body = named(root, "Body", "TextLabel")
	check("title on the band, body under it", para._view.Title.Text == "How targeting works" and body and body.Position.Y.Offset == 36)
	check("root and body grow with the text", root.AutomaticSize == Enum.AutomaticSize.Y and body.TextWrapped and body.AutomaticSize == Enum.AutomaticSize.Y)
	check("no mandatory info chip", named(root, "Icon") == nil)
	check("Set(text) replaces the content", para:Set("New body") == para and para.CurrentValue == "New body" and body.Text == "New body")
	check("Set{Title, Content} updates both (D4)", para:Set({ Title = "New title", Content = "Both" }) == para
		and para.Name == "New title" and para._view.Title.Text == "New title" and para.CurrentValue == "Both")
	check("Set{Title} alone keeps the content", para:Set({ Title = "Only title" }) == para and para.CurrentValue == "Both")
	check("SetContent is an alias", para:SetContent("via alias") == para and body.Text == "via alias")
	local stringForm = Tab:CreateParagraph("just content")
	check("a string is the content, the title defaults", stringForm.Name == "Information" and stringForm.CurrentValue == "just content")
	local aliased = Tab:CreateParagraph({ Name = "Alias", Description = "described" })
	check("Description is the content alias (D15)", aliased.CurrentValue == "described" and named(aliased.Root, "Description") == nil)
	local withIcon = Tab:CreateParagraph({ Title = "Icon", Content = "x", Icon = "info" })
	local glyph = named(withIcon.Root, "Icon", "ImageLabel")
	check("Icon is optional and shifts title and body", glyph ~= nil and withIcon._view.Title.Position.X.Offset == 40
		and named(withIcon.Root, "Body").Position.X.Offset == 40)
end

-- ---------------------------------------------------------------- TelemetryCard
section("TelemetryCard")
do
	local card = Tab:CreateTelemetryCard("Session")
	local _ = card.Root
	check("a string is the title; content defaults", card.Type == "TelemetryCard" and card.Name == "Session"
		and card.CurrentValue == "Waiting for data...")
	check("the title is not upper-cased", card._view.Title.Text == "Session")
	local status = card.Status
	check("Status is a pill: TextLabel, AutomaticSize X, UIStroke", status and status.ClassName == "TextLabel"
		and status.AutomaticSize == Enum.AutomaticSize.X and status:FindFirstChildOfClass("UIStroke") ~= nil)
	check("no pill unless Status is given", status.Visible == false and card.Rail.Visible == false)
	check("Icon defaults to a glyph; Rail is a frame", card.Icon and card.Icon.ClassName == "ImageLabel" and card.Icon.Image ~= ""
		and card.Rail.ClassName == "Frame")
	local green = Color3.fromRGB(99, 223, 160)
	card:SetStatus("Ready", green)
	local outline = status:FindFirstChildOfClass("UIStroke")
	check("SetStatus sets text as given and colours pill, outline and rail", status.Visible and status.Text == "Ready"
		and status.TextColor3 == green and outline.Color == green and card.Rail.Visible and card.Rail.BackgroundColor3 == green)
	check("SetStatus returns self", card:SetStatus("Ready") == card and status.TextColor3 == green)
	check("Set and SetContent update CurrentValue", card:Set("Uptime 4m") == card and card.CurrentValue == "Uptime 4m"
		and card:SetContent("128 items") == card and named(card.Root, "Body").Text == "128 items")
	card:SetStatus("Stale", "Warning")
	check("a token colour resolves now", same(status.TextColor3, palette.Argon.Warning))
	Argon:SetTheme("Emerald")
	check("a token colour follows the theme (CB-08)", same(status.TextColor3, palette.Emerald.Warning) and same(outline.Color, palette.Emerald.Warning))
	card:SetStatus("Fixed", green)
	Argon:SetTheme("Argon")
	check("a Color3 survives a theme change", status.TextColor3 == green)
	card:SetStatus("")
	check("an empty status hides the pill and rail", not status.Visible and not card.Rail.Visible)

	local live = Tab:CreateTelemetryCard({ Title = "Live", Content = "x", Status = "Live", Icon = "radio-tower", Accent = "Success" })
	check("Status from the config shows", live.Status.Visible and live.Status.Text == "Live")
	check("Accent tints the icon", same(live.Icon.ImageColor3, themed("Success")))
	check("Description is the content alias", Tab:CreateTelemetryCard({ Description = "d" }).CurrentValue == "d")

	local offTab = Window:CreateTab("Cards", "activity")
	offTab:CreateSection("Lazy")
	local lazy = offTab:CreateTelemetryCard({ Title = "Lazy" })
	check("an unmounted card has no instances", rawget(lazy, "_mounted") ~= true)
	check("reading Status mounts it lazily", lazy.Status ~= nil and lazy.Status.ClassName == "TextLabel" and rawget(lazy, "_mounted") == true)

	section("Stat")
	local stat = Tab:CreateStat({ Label = "Ping", Value = 42, Unit = "ms", Delta = "-3%", Status = "Stable", Icon = "wifi", Spark = { 3, 5, 4, 6, 9 } })
	local root = stat.Root
	check("CreateStat builds the stat variant", stat.Type == "TelemetryCard" and stat.Name == "Ping" and stat.CurrentValue == 42)
	local value = named(root, "Value", "TextLabel")
	check("the value uses the Stat role (mono 26)", value and value.Text == "42" and value.TextSize == 26)
	check("the label is 12 Text2", stat._view.Title.TextSize == 12 and same(stat._view.Title.TextColor3, themed("Text2")))
	local unit = named(root, "Unit", "TextLabel")
	check("the unit follows the value", unit and unit.Text == "ms" and unit.Position.X.Offset > value.Position.X.Offset)
	local delta = named(root, "Delta", "TextLabel")
	check("a negative delta is a DangerSoft pill", delta and delta.Text == "-3%" and same(delta.BackgroundColor3, themed("DangerSoft"))
		and same(delta.TextColor3, themed("Danger")))
	check("the status pill sits after the delta", stat.Status.Visible and stat.Status.Text == "Stable" and stat.Status.Position.X.Offset > delta.Position.X.Offset)
	local bars = findAll(root, function(item) return item.Name == "Spark" and item.Visible end)
	check("spark bars: one per value, 3 px wide", #bars == 5 and bars[1].Size.X.Offset == 3)
	check("the last bar is Accent, the rest Track", same(bars[5].BackgroundColor3, themed("Accent")) and same(bars[1].BackgroundColor3, themed("Track")))
	check("bars are right-aligned with 2 px gaps", bars[5].Position.X.Scale == 1 and bars[5].Position.X.Offset - bars[4].Position.X.Offset == 5)
	check("SetValue updates value and unit", stat:SetValue(128, "ms avg") == stat and stat.CurrentValue == 128 and value.Text == "128" and unit.Text == "ms avg")
	stat:SetDelta(12)
	check("SetDelta(number) shows a signed SuccessSoft pill", delta.Text == "+12" and same(delta.BackgroundColor3, themed("SuccessSoft")))
	stat:SetSpark({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 })
	check("SetSpark keeps at most 12 bars", #findAll(root, function(item) return item.Name == "Spark" and item.Visible end) == 12)
	stat:SetSpark({ 1, 2 }):Push(3)
	check("Push appends a sample", #findAll(root, function(item) return item.Name == "Spark" and item.Visible end) == 3)
	check("Set on a stat sets the value", stat:Set(7) == stat and stat.CurrentValue == 7 and value.Text == "7")
	local plain = Tab:CreateTelemetryCard({ Variant = "stat", Label = "Bare", Value = "1" })
	check("Variant = \"stat\" works without the builder; no meta row", plain.Root.Size.Y.Offset < stat.Root.Size.Y.Offset)
end

-- ---------------------------------------------------------------- Divider and Space
section("Divider and Space")
do
	local divider = Tab:CreateDivider("Advanced")
	local root = divider.Root
	local caption = named(root, "Caption", "TextLabel")
	check("CreateDivider(text) shows a 12 Text2 caption", divider.Type == "Divider" and caption and caption.Text == "Advanced"
		and caption.TextSize == 12 and caption.Position.X.Offset == 16)
	local rule = find(root, function(item) return item.ClassName == "Frame" and item.Size.Y.Offset == 1 end)
	check("the rule runs on after the caption to the edge", rule and rule.Visible and rule.Position.X.Offset > 16
		and rule.Size.X.Scale == 1 and same(rule.BackgroundColor3, themed("BorderSoft")))
	check("the section no longer hides the rule", divider._view.Divider == nil)
	local plain = Tab:CreateDivider()
	local plainRule = find(plain.Root, function(item) return item.ClassName == "Frame" and item.Size.Y.Offset == 1 end)
	check("an uncaptioned rule spans the platter, not inset", plainRule and plainRule.Position.X.Offset == 0 and plainRule.Size.X.Offset == 0
		and named(plain.Root, "Caption") == nil)
	check("{Title} and {Name} tables work", Tab:CreateDivider({ Title = "T" }).CurrentValue == "T" and Tab:CreateDivider({ Name = "N" }).CurrentValue == "N")
	check("Set(false) hides and returns self (Rayfield)", divider:Set(false) == divider and root.Visible == false)
	check("Set(true) shows", divider:Set(true) == divider and root.Visible == true)
	divider:Set("Renamed")
	check("Set(text) recaptions", caption.Text == "Renamed" and divider.Name == "Renamed")

	local space = Tab:CreateSpace(12)
	check("CreateSpace(px) is px tall and draws nothing", space.Type == "Space" and space.Root.Size.Y.Offset == 12 and #space.Root:GetChildren() == 0)
	check("px is clamped to 4-80 (v1)", Tab:CreateSpace(500).Root.Size.Y.Offset == 80 and Tab:CreateSpace(1).Root.Size.Y.Offset == 4)
	check("the default is 10", Tab:CreateSpace().Root.Size.Y.Offset == 10)
	check("Set(px) resizes", space:Set(30) == space and space.Root.Size.Y.Offset == 30)
end

-- ---------------------------------------------------------------- ProgressBar
section("ProgressBar")
do
	local fired = {}
	local bar = Tab:CreateProgressBar({ Name = "Export", Maximum = 200, Flag = "D_Progress", Callback = function(value) fired[#fired + 1] = value end })
	check("defaults: Minimum 0, value = Minimum", bar.Type == "ProgressBar" and bar.CurrentValue == 0 and bar.Minimum == 0 and bar.Maximum == 200)
	check("Set returns self", bar:Set(50) == bar and bar.CurrentValue == 50)
	check("Increment(25)", bar:Increment(25) == bar and bar.CurrentValue == 75)
	check("Increment() defaults to 1", bar:Increment().CurrentValue == 76)
	check("Set clamps to Maximum", bar:Set(9999).CurrentValue == 200)
	check("Set clamps to Minimum", bar:Set(-5).CurrentValue == 0)
	check("SetRange keeps a value still in range", bar:Set(200):SetRange(0, 400) == bar and bar.CurrentValue == 200)
	local count = #fired
	bar:SetRange(0, 100)
	check("SetRange re-clamps silently", bar.CurrentValue == 100 and #fired == count)
	check("the callback fired with numbers", fired[1] == 50 and fired[2] == 75)
	bar:Set(10, true)
	check("Set(v, true) is silent", bar.CurrentValue == 10 and #fired == count)
	check("garbage is ignored", bar:Set("nope").CurrentValue == 10 and bar:Set(0 / 0).CurrentValue == 10)
	check("never flaggable", bar.Flag == nil and Argon.Flags.D_Progress == nil)
	local saveOk = Argon:SaveConfiguration()
	local saved = saveOk and sandbox.decodeJson(sandbox.files["DisplaySuite/cfg.rfld"] or "{}") or {}
	check("never persisted", saveOk and saved.D_Progress == nil)

	local root = bar.Root
	local value, track = named(root, "Value", "TextLabel"), named(root, "Track", "Frame")
	local fill = named(root, "Fill", "Frame")
	bar:Set(25)
	check("readout defaults to a percentage, mono", value.Text == "25%" and value.TextSize == 13)
	check("6 px track under the title band", track.Size.Y.Offset == 6 and track.Position.Y.Offset > 20 and root.Size.Y.Offset > track.Position.Y.Offset + 6)
	check("fill width is the ratio", math.abs(fill.Size.X.Scale - 0.25) < 1e-6)
	local gradient = fill:FindFirstChildOfClass("UIGradient")
	check("the default fill is the Accent -> AccentAlt gradient", gradient and gradient.Enabled and same(fill.BackgroundColor3, Color3.new(1, 1, 1)))
	local red = Color3.fromRGB(255, 0, 0)
	bar:SetColor(red)
	Argon:SetTheme("Emerald")
	check("SetColor(Color3) stays fixed across themes", fill.BackgroundColor3 == red and not gradient.Enabled)
	bar:SetColor("Warning")
	check("SetColor(token) follows the theme", same(fill.BackgroundColor3, palette.Emerald.Warning))
	Argon:SetTheme("Argon")
	check("...and the next theme", same(fill.BackgroundColor3, palette.Argon.Warning))
	check("SetColor(nil) restores the gradient", bar:SetColor(nil) == bar and gradient.Enabled)

	local thresholds = Tab:CreateProgressBar({ Name = "Memory", CurrentValue = 50, Thresholds = { { 0.9, "Danger" }, { 0.7, "Warning" } } })
	local tfill = named(thresholds.Root, "Fill")
	check("below every threshold: gradient", tfill:FindFirstChildOfClass("UIGradient").Enabled)
	thresholds:Set(75)
	check("past 0.7: Warning, solid", same(tfill.BackgroundColor3, themed("Warning")) and not tfill:FindFirstChildOfClass("UIGradient").Enabled)
	thresholds:Set(95)
	check("past 0.9: Danger", same(tfill.BackgroundColor3, themed("Danger")))

	local formatted = Tab:CreateProgressBar({ Name = "Files", Maximum = 500, CurrentValue = 120,
		Format = function(v, max, ratio) return ("%d / %d (%.2f)"):format(v, max, ratio) end })
	check("Format(value, max, ratio) drives the readout", named(formatted.Root, "Value").Text == "120 / 500 (0.24)")
	local shown = Tab:CreateProgressBar({ Name = "Items", CurrentValue = 42, ShowValue = true, Suffix = "items" })
	check("ShowValue + Suffix", named(shown.Root, "Value").Text == "42 items")
	local percent = Tab:CreateProgressBar({ Name = "Pct", CurrentValue = 12.5, ShowValue = true, Suffix = "%" })
	check("short suffixes stay attached; decimals trimmed", named(percent.Root, "Value").Text == "12.5%")
	local swapped = Tab:CreateProgressBar({ Name = "Swap", Minimum = 10, Maximum = 0, CurrentValue = 50 })
	check("a reversed range is swapped and the value clamped", swapped.Minimum == 0 and swapped.Maximum == 10 and swapped.CurrentValue == 10)

	local steps = Tab:CreateProgressBar({ Name = "Steps", Steps = 5, CurrentValue = 60 })
	local segments = findAll(steps.Root, function(item) return item.Name == "Step" end)
	local lit = 0
	for _, segment in ipairs(segments) do
		if same(segment.BackgroundColor3, themed("Accent")) then lit += 1 end
	end
	check("Steps = 5 draws 5 segments, 3 of them lit at 60 %", #segments == 5 and lit == 3)
	check("segments have 3 px gaps", math.abs(segments[2].Position.X.Offset - 3 / 5) < 1e-6 and math.abs(segments[1].Size.X.Offset + 12 / 5) < 1e-6)

	local before = sandbox.runningLoops()
	local spinner = Tab:CreateProgressBar({ Name = "Waiting", Indeterminate = true })
	local _ = spinner.Root
	sandbox.advance(0.1)
	check("Indeterminate: a sweep runs while on screen", sandbox.runningLoops() == before + 1)
	check("Indeterminate: no readout, a 30 % segment", named(spinner.Root, "Value").Text == "" and math.abs(named(spinner.Root, "Fill").Size.X.Scale - 0.3) < 1e-6)
	Window:SetVisibility(false)
	sandbox.advance(0.6)
	check("the sweep stops while the window is hidden", sandbox.runningLoops() == before)
	Window:SetVisibility(true)
	sandbox.advance(0.6)
	check("and resumes when it shows again", sandbox.runningLoops() == before + 1)
	local other = Window:CreateTab("Elsewhere", "zap")
	Window:SelectTab(other)
	sandbox.advance(0.6)
	check("it stops on another tab", sandbox.runningLoops() == before)
	Window:SelectTab(Tab)
	sandbox.advance(0.6)
	check("and resumes on its tab", sandbox.runningLoops() == before + 1)
	spinner:SetIndeterminate(false):Set(40)
	check("SetIndeterminate(false) stops it and shows the value", sandbox.runningLoops() == before and named(spinner.Root, "Value").Text == "40%")
	spinner:SetIndeterminate(true)
	sandbox.advance(0.1)
	spinner:Destroy()
	sandbox.advance(0.6)
	check("Destroy stops the sweep", sandbox.runningLoops() == before)

	local described = Tab:CreateProgressBar({ Name = "Described", Description = "Fetching assets" })
	local _ = described.Root
	local desc = described._view.Description
	check("a description sits under the track", desc and desc.Visible and desc.Position.Y.Offset > named(described.Root, "Track").Position.Y.Offset)
	described:SetDesc("")
	check("clearing it restores the row height", described.Root.Size.Y.Offset == described._view.band + 10)
end

-- ---------------------------------------------------------------- List
section("List")
do
	local clicked
	local list = Tab:CreateList({ Name = "Items", EmptyText = "empty", Callback = function(record, item) clicked = { record, item } end })
	check("SetItems returns self and normalises strings", list:SetItems({ "One", { Title = "Two", Description = "second", Action = "Load" } }) == list
		and #list.Items == 2 and list.Items[1].Title == "One")
	check("AddItem and Clear return self", list:AddItem({ Title = "Three" }) == list and #list.Items == 3 and list:Clear() == list and #list.Items == 0)
	check("CurrentValue is the Items table", list.CurrentValue == list.Items)

	local fired = {}
	local function log(tag) return function(record, item) fired[#fired + 1] = tag .. ":" .. record.Title .. ":" .. tostring(item == record) end end
	local actions = Tab:CreateList({ Name = "Profiles", Items = {
		{ Title = "Mining", Description = "snapshot", Actions = {
			{ Label = "Load", Callback = log("load") },
			{ Label = "Rename", Style = "warning", Callback = log("rename") },
			{ Label = "Delete", Style = "danger", Callback = log("delete") },
		} },
	} })
	local rows = findAll(actions.Root, function(item) return item:IsA("Frame") and item.Size.Y.Offset == 44 end)
	check("a described row is a 44 px Frame", #rows == 1)
	local buttons = {}
	for _, item in ipairs(rows[1]:GetChildren()) do
		if item:IsA("TextButton") then buttons[#buttons + 1] = item end
	end
	table.sort(buttons, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	check("three inline actions, in build order", #buttons == 3 and buttons[1].Text == "Load" and buttons[3].Text == "Delete")
	check("right-aligned without overlap", buttons[1].Position.X.Offset + buttons[1].Size.X.Offset <= buttons[2].Position.X.Offset
		and buttons[2].Position.X.Offset + buttons[2].Size.X.Offset <= buttons[3].Position.X.Offset and buttons[3].Position.X.Scale == 1)
	check("danger and warning are tinted", same(buttons[3].TextColor3, themed("Danger")) and same(buttons[2].TextColor3, themed("Warning"))
		and buttons[3].BackgroundColor3 ~= buttons[1].BackgroundColor3)
	check("12 px labels", buttons[1].TextSize == 12)
	for _, button in ipairs(buttons) do button.MouseButton1Click:Fire() end
	check("each action gets (record, item) with the same table", fired[1] == "load:Mining:true" and fired[3] == "delete:Mining:true", table.concat(fired, ","))

	local hit
	local legacy = Tab:CreateList({ Name = "Legacy", Items = { { Title = "One", Action = "Go", Callback = function(record) hit = record.Title end } } })
	local go = find(legacy.Root, function(item) return item:IsA("TextButton") and item.Text == "Go" end)
	if go then go.MouseButton1Click:Fire() end
	check("a single Action string uses record.Callback", hit == "One")
	check("rows without descriptions are 36 px", find(legacy.Root, function(item) return item.Name == "Row" end).Size.Y.Offset == 36
		and find(Tab:CreateList({ Items = { "a" } }).Root, function(item) return item.Name == "Row" end).Size.Y.Offset == 36)

	-- overflow menu
	local overflowFired
	local overflow = Tab:CreateList({ Name = "Overflow", InlineActions = 1, Items = { { Title = "Row", Actions = {
		{ Label = "First", Callback = function() end },
		{ Label = "Second", Callback = function() end },
		{ Label = "Remove", Style = "danger", Callback = function(record) overflowFired = record.Title end },
	} } } })
	local orow = find(overflow.Root, function(item) return item.Name == "Row" end)
	local inline = findAll(orow, function(item) return item:IsA("TextButton") and item.Visible end)
	local more = named(orow, "More", "ImageButton")
	check("InlineActions = 1: one inline button and an ellipsis", #inline == 1 and inline[1].Text == "First" and more and more.Visible)
	if more then more.MouseButton1Click:Fire() end
	sandbox.advance(0.3)
	local menuRow = find(Window.ScreenGui, function(item)
		return item.Name == "MenuItem" and item.Visible and item:FindFirstChild("Label") and item:FindFirstChild("Label").Text == "Remove"
	end)
	check("the rest open in a context menu", menuRow ~= nil)
	if menuRow then menuRow.MouseButton1Click:Fire() end
	check("a menu item fires its action", overflowFired == "Row")

	-- ConfirmDelete routes danger actions through Window:Confirm
	local deleted, asked
	local confirmList = Tab:CreateList({ Name = "Confirm", ConfirmDelete = true, Items = { { Title = "Profile", Actions = {
		{ Label = "Delete", Style = "danger", Callback = function(r) deleted = r.Title end },
	} } } })
	Window.Confirm = function(_, config) asked = config end
	local deleteButton = find(confirmList.Root, function(item) return item:IsA("TextButton") and item.Text == "Delete" end)
	if deleteButton then deleteButton.MouseButton1Click:Fire() end
	Window.Confirm = nil
	check("ConfirmDelete asks before a danger action", deleted == nil and asked ~= nil and asked.Title == "Delete Profile?" and asked.ConfirmText == "Delete")
	if asked then asked.OnConfirm() end
	check("confirming runs it", deleted == "Profile")

	-- whole-row click, selection and identity
	local record = { Title = "Kept", Id = "k" }
	local plain = Tab:CreateList({ Name = "Plain", Items = { "Alpha", record }, Callback = function(r, item) clicked = { r, item } end })
	local function rowFor(control, title)
		return find(control.Root, function(item)
			return item.Name == "Row" and item.Visible and item:FindFirstChild("Title") and item:FindFirstChild("Title").Text == title
		end)
	end
	rowFor(plain, "Alpha"):FindFirstChild("Hit").MouseButton1Click:Fire()
	check("with no actions the whole row calls back (record, item)", clicked and clicked[1].Title == "Alpha" and clicked[2] == "Alpha")
	local alpha = rowFor(plain, "Alpha")
	check("the clicked row is selected: Active fill and an Accent bar", plain.Selected == plain.Items[1] and alpha.BackgroundTransparency == 0
		and same(alpha.BackgroundColor3, themed("Active")) and named(alpha, "Selected") and named(alpha, "Selected").Visible)
	rowFor(plain, "Kept"):FindFirstChild("Hit").MouseButton1Click:Fire()
	check("record identity is kept: the callback gets your table", clicked[1] == record and clicked[2] == record)
	local alphaRecord = plain.Items[1]
	plain:SetItems({ "Alpha", { Title = "Kept", Id = "k" }, "Gamma" })
	check("SetItems keeps the record of an unchanged string", plain.Items[1] == alphaRecord and #plain.Items == 3)
	check("the selection follows its key", plain.Selected == plain.Items[2] and plain.Selected ~= record)
	check("RemoveItem(id) returns self", plain:RemoveItem("k") == plain and #plain.Items == 2 and plain.Selected == nil)
	check("RemoveItem(title) and RemoveItem(index)", plain:RemoveItem("Gamma"):RemoveItem(1) and #plain.Items == 0)
	plain:SetItems({ "a", "b", { Title = "c", Id = 7 } })
	check("UpdateItem patches the record and its row", plain:UpdateItem(7, { Title = "Charlie", Description = "patched" }) == plain
		and plain.Items[3].Title == "Charlie" and rowFor(plain, "Charlie") ~= nil and rowFor(plain, "Charlie").Size.Y.Offset == 44)
	check("UpdateItem(index)", plain:UpdateItem(1, { Title = "Alpha" }).Items[1].Title == "Alpha")
	check("Select and GetSelected", plain:Select("b") == plain and plain:GetSelected() == plain.Items[2] and plain:Select(nil):GetSelected() == nil)

	-- virtualisation
	local many = {}
	for index = 1, 500 do many[index] = "Item " .. index end
	local big = Tab:CreateList({ Name = "Big", Items = many })
	local liveRows = #findAll(big.Root, function(item) return item.Name == "Row" end)
	check("500 items build only the visible rows", liveRows > 0 and liveRows <= 8, liveRows)
	local scroller = named(big.Root, "Rows", "ScrollingFrame")
	scroller.CanvasPosition = env.Vector2.new(0, 36 * 200)
	check("scrolling rebinds rows to later items", rowFor(big, "Item 201") ~= nil and #findAll(big.Root, function(item) return item.Name == "Row" end) == liveRows)
	check("the counter reads the item count", named(big.Root, "Count").Text == "500 items")
	check("Height is clamped to 80-420", Tab:CreateList({ Height = 2000 }).Root:FindFirstChild("Rows").Size.Y.Offset == 420)
	local auto = Tab:CreateList({ Name = "Auto", MaxHeight = 200, Items = { "a", "b" } })
	check("MaxHeight sizes to the rows", auto.Root:FindFirstChild("Rows").Size.Y.Offset == 72)
	auto:SetItems(many)
	check("...up to MaxHeight", auto.Root:FindFirstChild("Rows").Size.Y.Offset == 200)

	-- empty state
	local added
	local empty = Tab:CreateList({ Name = "Empty", EmptyText = "No waypoints", EmptyAction = { Text = "Add current position", Callback = function() added = true end } })
	local emptyView = named(empty.Root, "Empty", "Frame")
	check("empty state shows EmptyText", emptyView and emptyView.Visible and named(emptyView, "Text").Text == "No waypoints")
	local emptyButton = named(emptyView, "Action", "TextButton")
	if emptyButton then emptyButton.MouseButton1Click:Fire() end
	check("EmptyAction is a button that calls back", emptyButton and emptyButton.Text == "Add current position" and added == true)
	empty:AddItem("x")
	check("the empty state hides once there are items", not emptyView.Visible)

	-- filter
	local filtered = Tab:CreateList({ Name = "Filtered", Filter = true, Items = many })
	local box = named(filtered.Root, "Filter", "TextBox")
	check("Filter adds a box above 8 rows", box and box.Visible)
	box.Text = "item 49"
	check("typing filters the rows", #filtered._data == 11 and named(filtered.Root, "Count").Text == "11 of 500", #filtered._data)
	box.Text = ""
	check("clearing shows everything", #filtered._data == 500)
	check("no filter box for short lists", named(Tab:CreateList({ Filter = true, Items = { "a" } }).Root, "Filter") == nil)

	-- icons, avatars, colour
	local people = Tab:CreateList({ Name = "People", Items = { { Title = "Builderman", Avatar = 156 }, { Title = "Pin", Icon = "map-pin", Color = Color3.fromRGB(1, 2, 3) } } })
	local avatar = find(rowFor(people, "Builderman"), function(item) return item.Name == "Icon" end)
	check("Avatar draws a round rbxthumb", avatar and avatar.Image:match("^rbxthumb://") and avatar:FindFirstChildOfClass("UICorner").CornerRadius.Scale == 1)
	local pinRow = rowFor(people, "Pin")
	check("Icon draws a glyph and Color tints the title", named(pinRow, "Icon").Image ~= "" and pinRow:FindFirstChild("Title").TextColor3 == Color3.fromRGB(1, 2, 3))

	-- rename in place
	local renamed
	local editable = Tab:CreateList({ Name = "Editable", Rename = true, Items = { "Old" },
		OnRename = function(r, new, old) renamed = old .. ">" .. new .. ":" .. r.Title end })
	local hitButton = rowFor(editable, "Old"):FindFirstChild("Hit")
	hitButton.MouseButton1Click:Fire()
	hitButton.MouseButton1Click:Fire()
	local renameBox = named(editable.Root, "Rename", "TextBox")
	check("a double-click opens the rename box", renameBox ~= nil and renameBox.Text == "Old")
	if renameBox then sandbox.input.typeText(renameBox, "New", true) end
	check("Enter commits the rename", editable.Items[1].Title == "New" and renamed == "Old>New:New" and rowFor(editable, "New") ~= nil)
	hitButton.MouseButton1Click:Fire()
	hitButton.MouseButton1Click:Fire()
	renameBox = named(editable.Root, "Rename", "TextBox")
	if renameBox then sandbox.input.typeText(renameBox, "Discarded", false) end
	check("leaving without Enter reverts", editable.Items[1].Title == "New")

	-- keyboard, lock, focus
	local keyed
	local keys = Tab:CreateList({ Name = "Keys", Items = { "a", "b", "c" }, Callback = function(r) keyed = r.Title end })
	local _ = keys.Root
	local focus = keys._spec.focus
	focus.adjust(keys, 1)
	focus.adjust(keys, 1)
	check("arrow keys move the selection", keys.Selected == keys.Items[2])
	focus.activate(keys)
	check("Enter activates the selected row", keyed == "b")
	focus.adjust(keys, math.huge)
	check("End jumps to the last row", keys.Selected == keys.Items[3])
	check("the list is focusable", (function()
		for _, element in ipairs(Window._focus:_items()) do
			if element == keys then return true end
		end
		return false
	end)())
	keyed = nil
	keys:Lock("Premium")
	rowFor(keys, "a"):FindFirstChild("Hit").MouseButton1Click:Fire()
	check("a locked list ignores clicks", keyed == nil)
	keys:Unlock()
	check("but programmatic edits still work", keys:AddItem("d") == keys and #keys.Items == 4)

	local described = Tab:CreateList({ Name = "Described", Description = "Saved per game", Items = { "a" } })
	local _ = described.Root
	local desc = described._view.Description
	local rowsFrame = named(described.Root, "Rows")
	check("a description sits under the list", desc and desc.Visible and desc.Position.Y.Offset >= rowsFrame.Position.Y.Offset + rowsFrame.Size.Y.Offset)
end

-- ---------------------------------------------------------------- Callout
section("Callout")
do
	local acted, dismissed
	local callout = Tab:CreateCallout({ Title = "Heads up", Content = "Auto farm pauses when the game moves you.", Type = "warning",
		Action = { Text = "Learn more", Callback = function() acted = true end }, Dismissible = true, OnDismiss = function() dismissed = true end })
	local root = callout.Root
	local box = named(root, "Box", "Frame")
	check("a <Type>Soft box inset 8 with r 10", box and same(box.BackgroundColor3, themed("WarningSoft")) and box.Position.X.Offset == 8
		and box:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 10)
	check("icon 18 in the status colour", same(named(root, "Icon").ImageColor3, themed("Warning")) and named(root, "Icon").Size.X.Offset == 18)
	check("title and wrapped body", named(root, "Title").Text == "Heads up" and named(root, "Body").Text:find("Auto farm") ~= nil
		and named(root, "Body").TextWrapped and root.AutomaticSize == Enum.AutomaticSize.Y)
	local action = named(root, "Action", "TextButton")
	check("the action is an AccentText button under the body", action and action.Text == "Learn more" and same(action.TextColor3, themed("AccentText"))
		and action.Position.Y.Offset > named(root, "Body").Position.Y.Offset)
	if action then action.MouseButton1Click:Fire() end
	check("the action calls back", acted == true)
	check("Set{Title, Content} returns self", callout:Set({ Title = "Changed", Content = "New body" }) == callout
		and named(root, "Title").Text == "Changed" and callout.CurrentValue == "New body")
	callout:Set({ Type = "danger" })
	check("Set{Type} retints", same(box.BackgroundColor3, themed("DangerSoft")))
	Argon:SetTheme("Emerald")
	check("the tint follows the theme", same(box.BackgroundColor3, palette.Emerald.DangerSoft))
	Argon:SetTheme("Argon")
	local close = named(root, "Dismiss", "ImageButton")
	if close then close.MouseButton1Click:Fire() end
	check("dismiss hides it and calls OnDismiss", close and root.Visible == false and dismissed == true)
	local info = Tab:CreateCallout("Just a note")
	check("a string is the content; Type defaults to info", info.CurrentValue == "Just a note"
		and same(named(info.Root, "Box").BackgroundColor3, themed("InfoSoft")) and named(info.Root, "Title") == nil)
end

-- ---------------------------------------------------------------- Image
section("Image")
do
	local image = Tab:CreateImage({ Image = 123, Height = 80, Caption = "A caption" })
	local root = image.Root
	local picture = named(root, "Image", "ImageLabel")
	check("an asset id becomes rbxassetid", picture and picture.Image == "rbxassetid://123" and picture.Size.Y.Offset == 80)
	check("Fit and r 10 by default", picture.ScaleType == Enum.ScaleType.Fit and picture:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 10)
	check("a 12 Muted caption under it", named(root, "Caption").Text == "A caption" and named(root, "Caption").TextSize == 12
		and named(root, "Caption").Position.Y.Offset > picture.Position.Y.Offset + 80)
	local tall = root.Size.Y.Offset
	check("Set(image) swaps the image and returns self", image:Set("rbxassetid://5") == image and picture.Image == "rbxassetid://5")
	image:Set({ Caption = "" })
	check("removing the caption shrinks the row", root.Size.Y.Offset < tall and not named(root, "Caption").Visible)
	local square = Tab:CreateImage({ Image = "rbxassetid://9", Corner = 0, ScaleType = "Crop", Height = 9999 })
	local squarePicture = named(square.Root, "Image")
	check("Corner = 0, ScaleType and Height clamp", squarePicture:FindFirstChildOfClass("UICorner") == nil
		and squarePicture.ScaleType == Enum.ScaleType.Crop and squarePicture.Size.Y.Offset == 600)
end

-- ---------------------------------------------------------------- budget and hygiene
section("instance budget (mounted, default density)")
do
	local function cost(make)
		local before = sandbox.metrics()
		local element = make()
		local _ = element.Root
		local after = sandbox.metrics()
		return after.live - before.live
	end
	-- Each budget counts Root, Title (when there is one) and the row divider.
	local budgets = {
		{ "Label", 4, function() return Tab:CreateLabel("x") end },
		{ "Label with icon", 5, function() return Tab:CreateLabel("x", "info") end },
		{ "Paragraph", 5, function() return Tab:CreateParagraph({ Title = "t", Content = "c" }) end },
		{ "TelemetryCard", 11, function() return Tab:CreateTelemetryCard({ Title = "t" }) end },
		{ "Stat (value, unit, status)", 12, function() return Tab:CreateStat({ Label = "l", Value = 1, Unit = "u" }) end },
		{ "Divider with caption", 3, function() return Tab:CreateDivider("x") end },
		{ "Space", 1, function() return Tab:CreateSpace(8) end },
		{ "ProgressBar", 9, function() return Tab:CreateProgressBar({ Name = "p" }) end },
		{ "List, one plain row", 10, function() return Tab:CreateList({ Items = { "a" } }) end },
		{ "Callout", 9, function() return Tab:CreateCallout({ Title = "t", Content = "c" }) end },
		{ "Image", 4, function() return Tab:CreateImage({ Image = 1 }) end },
	}
	for _, entry in ipairs(budgets) do
		local count = cost(entry[3])
		check(("%s: %d instances (budget %d)"):format(entry[1], count, entry[2]), count <= entry[2])
	end
	local strokes = sandbox.metrics().byClass.UIStroke or 0
	check("UIStrokes only on status pills", strokes < 40, strokes)
end

section("hygiene")
do
	local before = sandbox.metrics().handlers
	local label = Tab:CreateLabel("handlers")
	local list = Tab:CreateList({ Items = { "a" } })
	local bar = Tab:CreateProgressBar({ Name = "h" })
	local _ = label.Root, list.Root, bar.Root
	local after = sandbox.metrics().handlers
	check("no global input handlers at rest", after.InputBegan == before.InputBegan and after.InputChanged == before.InputChanged
		and after.InputEnded == before.InputEnded)
	local destroyOk = try(function()
		label:Destroy()
		list:Destroy()
		bar:Destroy()
		return true
	end)
	check("Destroy works", destroyOk)
	local densityOk = try(function()
		Window:SetDensity("compact")
		local compact = Tab:CreateList({ Items = { "a" } })
		local row = find(compact.Root, function(item) return item.Name == "Row" end)
		local progress = Tab:CreateProgressBar({ Name = "c" })
		local card = Tab:CreateTelemetryCard({ Title = "c" })
		local ok1 = row.Size.Y.Offset == 32 and progress.Root.Size.Y.Offset == 44 and card.Status ~= nil
		Window:SetDensity("auto")
		return ok1 and card.Status ~= nil and card.Root.Parent ~= nil
	end)
	check("a density change remounts every display control", densityOk)
	sandbox.advance(1)
	check("nothing warned", #sandbox.warnings == 0, table.concat(sandbox.warnings, " | "))
	check("no signal errors", #sandbox.signalErrors == 0, table.concat(sandbox.signalErrors, " | "))
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then process.exit(1) end
