--!nocheck
-- Controls A (Button, ButtonGroup, Slider, Stepper, Segmented, Keybind) under the sandbox:
-- v1 semantics from audit/api.md section 7, the v2 additions, instance budgets and hygiene.
--   lune run tests/controls_a.luau [bundle path]   (default: argon-ui.luau)

local process = require("@lune/process")
local fs = require("@lune/fs")
local sandbox = require("./sandbox")
local env = sandbox.environment
local Enum, Vector2, Vector3 = env.Enum, env.Vector2, env.Vector3
local UIS = sandbox.UserInputService

local BUNDLE = process.args[1] or (fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau")

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

local ok, Argon = pcall(sandbox.load, BUNDLE)
check("bundle loads", ok, not ok and Argon or nil)
if not ok then process.exit(1) end

local Window = Argon:CreateWindow({ Name = "Controls A", GuiName = "ControlsA", Theme = "Argon",
	ConfigurationSaving = { Enabled = true, FolderName = "CA", FileName = "cfg" } })
Window:FinishLoading()
sandbox.advance(1)
local Tab = Window:CreateTab("Main", "zap")
Tab:CreateSection("Controls")
sandbox.advance(0.2)
local baseline = sandbox.metrics().handlers
local consumers = Window._router.stats().consumers
local Themes = Argon.Themes

-- ---------- helpers ----------
local function count(element)
	return 1 + #element.Root:GetDescendants()
end
-- Instances in a row as mounted: Root + descendants, plus the inset row Divider every section row
-- owns (DESIGN_V2 6.21 counts it), whether or not the shared row view created it.
local function budget(element)
	local divider = element.Root:FindFirstChild("Divider") and 0 or 1
	return count(element) + divider
end
local function find(root, name)
	for _, child in ipairs(root:GetDescendants()) do
		if child.Name == name then return child end
	end
	return nil
end
local function findAll(root, name)
	local out = {}
	for _, child in ipairs(root:GetDescendants()) do
		if child.Name == name then out[#out + 1] = child end
	end
	return out
end
local function mouse(kind, position)
	return { UserInputType = Enum.UserInputType[kind], KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(position and position.X or 0, position and position.Y or 0, 0),
		UserInputState = Enum.UserInputState.Begin, Delta = Vector3.new(0, 0, 0) }
end
local function at(gui, fx, fy)
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize
	return Vector2.new(position.X + size.X * (fx or 0.5), position.Y + size.Y * (fy or 0.5))
end
local function plain(text)
	return (tostring(text):gsub("<[^>]+>", ""))
end
local function mounted(...)
	sandbox.advance(0.2)
	for _, element in ipairs({ ... }) do local _ = element.Root end
end
local function sameColor(a, b)
	return a and b and math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end
local focus = Window._focus

-- =====================================================================================
section("slider: v1 values")
local sliderCalls, sliderLast = 0, nil
local slider = Tab:CreateSlider({ Flag = "CA_Slider", Name = "Slider", Range = { 0, 100 }, Increment = 5, CurrentValue = 10,
	Callback = function(value) sliderCalls += 1 sliderLast = value end })
check("slider starts at its CurrentValue", slider.CurrentValue == 10, slider.CurrentValue)
check("Set returns self (D14)", slider:Set(43) == slider)
check("slider rounds to the increment (v1 L80)", slider.CurrentValue == 45, slider.CurrentValue)
check("slider clamps high (v1 L83)", (function() slider:Set(1e6) return slider.CurrentValue end)() == 100, slider.CurrentValue)
check("slider fires its callback with a number", sliderLast == 100 and type(sliderLast) == "number", tostring(sliderLast))
slider:Set("speed 70 studs")
check("Set takes the first numeric run of a string", slider.CurrentValue == 70, slider.CurrentValue)
slider:Set("abc")
check("a string without a number is ignored", slider.CurrentValue == 70, slider.CurrentValue)
local before = sliderCalls
slider:Set(20, true)
check("Set(v, true) is silent", slider.CurrentValue == 20 and sliderCalls == before, sliderCalls)
slider:Set(20)
check("an unchanged value fires nothing", sliderCalls == before)
check("the default is the CurrentValue at creation", slider.Default == 10, tostring(slider.Default))
check("slider defaults to the minimum", Tab:CreateSlider({ Name = "Min", Range = { 5, 50 } }).CurrentValue == 5)

local reversed = Tab:CreateSlider({ Name = "Reversed", Range = { 100, 0 }, Increment = 10, CurrentValue = 30 })
check("a reversed Range is swapped", reversed.CurrentValue == 30 and reversed._min == 0 and reversed._max == 100)
reversed:Set(-50)
check("a reversed Range clamps low", reversed.CurrentValue == 0, reversed.CurrentValue)
local continuous = Tab:CreateSlider({ Name = "Continuous", Range = { 0, 1 }, Increment = 0, CurrentValue = 0.5 })
continuous:Set(0.33333)
check("Increment 0 is continuous with 2 decimals", continuous.CurrentValue == 0.33, continuous.CurrentValue)
local negative = Tab:CreateSlider({ Name = "Negative step", Range = { 0, 10 }, Increment = -1, CurrentValue = 2.567 })
check("a negative Increment is continuous, not NaN", negative.CurrentValue == 2.57, negative.CurrentValue)
local uneven = Tab:CreateSlider({ Name = "Uneven", Range = { 0, 10 }, Increment = 3, CurrentValue = 10 })
check("the maximum is reachable with an uneven step", uneven.CurrentValue == 10, uneven.CurrentValue)
uneven:Set(9.4)
check("a value nearer the last step keeps v1 rounding", uneven.CurrentValue == 9, uneven.CurrentValue)
uneven:Set(9.6)
check("a value nearer the maximum snaps to it", uneven.CurrentValue == 10, uneven.CurrentValue)

section("slider: view")
local bananas = Tab:CreateSlider({ Name = "Bananas", Range = { 0, 20 }, Increment = 1, CurrentValue = 10, Suffix = "Bananas" })
local percent = Tab:CreateSlider({ Name = "Percent", Range = { 0, 100 }, Increment = 1, CurrentValue = 50, Suffix = "%" })
local ms = Tab:CreateSlider({ Name = "Latency", Range = { 0, 10 }, Increment = 1, CurrentValue = 3, Suffix = "ms" })
local formatted = Tab:CreateSlider({ Name = "Formatted", Range = { 0, 1 }, Increment = 0.1, CurrentValue = 0.5,
	Format = function(v) return math.floor(v * 100) .. " pct" end })
mounted(bananas, percent, ms, formatted, slider)
check("a word suffix gets a space", plain(bananas._valueBox.Text) == "10 Bananas", plain(bananas._valueBox.Text))
check("a % suffix stays attached", plain(percent._valueBox.Text) == "50%", plain(percent._valueBox.Text))
check("a short suffix stays attached", plain(ms._valueBox.Text) == "3ms", plain(ms._valueBox.Text))
check("the suffix is drawn Muted (rich text)", bananas._valueBox.RichText == true and bananas._valueBox.Text:find("<font", 1, true) ~= nil)
check("Format shapes the shown value", plain(formatted._valueBox.Text) == "50 pct", plain(formatted._valueBox.Text))
local hit = slider.Root:FindFirstChild("Hit")
check("the drag band is a child of Root named Hit", hit ~= nil and hit.ClassName == "TextButton" and hit.BackgroundTransparency == 1)
check("the Hit band is sliderHit tall (28 at default density)", hit and hit.Size.Y.Offset == 28, hit and hit.Size.Y.Offset)
check("the value pill is a mono TextBox", slider._valueBox.ClassName == "TextBox"
	and tostring(slider._valueBox.FontFace.Family):find("RobotoMono", 1, true) ~= nil)
check("the thumb has a thin stroke", (function()
	local stroke = slider._thumb:FindFirstChildOfClass("UIStroke")
	return stroke ~= nil and stroke.Thickness == 1 and stroke.Transparency == 0.75
end)())
check("the groove gradient carries the fill up to the value", (function()
	local points = find(slider.Root, "Groove"):FindFirstChildOfClass("UIGradient").Color.Keypoints
	return #points == 5 and math.abs(points[3].Time - 0.2) < 1e-6 and sameColor(points[2].Value, Themes.Argon.Accent)
		and sameColor(points[5].Value, Themes.Argon.Track)
end)())
check("the thumb sits at the value", math.abs(slider._thumb.Position.X.Scale - 0.2) < 1e-6, slider._thumb.Position.X.Scale)
check("12 or fewer steps draw ticks", #findAll(Tab:CreateSlider({ Name = "Ticks", Range = { 0, 10 }, Increment = 1 }).Root, "Tick") == 11)
check("an uneven step also ticks the maximum", #findAll(uneven.Root, "Tick") == 5)
check("more than 12 steps draw no ticks", #findAll(slider.Root, "Tick") == 0)
check("Ticks = false draws none", #findAll(Tab:CreateSlider({ Name = "No ticks", Range = { 0, 10 }, Ticks = false }).Root, "Tick") == 0)

section("slider: drag")
local released, releaseValue = 0, nil
local drag = Tab:CreateSlider({ Flag = "CA_Drag", Name = "Drag", Range = { 0, 100 }, Increment = 1, CurrentValue = 0,
	Callback = function() sliderCalls += 1 end, OnRelease = function(value) released += 1 releaseValue = value end })
mounted(drag)
local band = drag._hit
local page = Tab.Page
sliderCalls = 0
local session = mouse("MouseButton1", at(band, 0.25))
band.InputBegan:Fire(session)
check("press jumps to the pointer", drag.CurrentValue == 25, drag.CurrentValue)
check("the page does not scroll during a drag", page.ScrollingEnabled == false)
check("the thumb grows while dragging", drag._thumb.Size.X.Offset == 20, drag._thumb.Size.X.Offset)
check("the pill turns AccentText while dragging", sameColor(drag._valueBox.TextColor3, Themes.Argon.AccentText))
for step = 1, 4 do
	UIS.InputChanged:Fire(mouse("MouseMovement", at(band, 0.25 + step * 0.1)), false)
	sandbox.step(1)
end
check("the callback fires live once per frame", sliderCalls == 5, sliderCalls)
check("the value follows the pointer", drag.CurrentValue == 65, drag.CurrentValue)
check("no release before the pointer is up", released == 0)
local callsBeforeRelease = sliderCalls
UIS.InputEnded:Fire(mouse("MouseButton1", at(band, 0.65)), false)
check("release fires OnRelease once with the value", released == 1 and releaseValue == 65, releaseValue)
check("release does not fire the callback again", sliderCalls == callsBeforeRelease, sliderCalls)
check("the page scrolls again after the drag", page.ScrollingEnabled == true)
check("the thumb shrinks back", drag._thumb.Size.X.Offset == 16, drag._thumb.Size.X.Offset)
sandbox.input.drag(band, at(band, 0.9), at(band, 2), 3)
check("a drag past the end clamps to the maximum", drag.CurrentValue == 100, drag.CurrentValue)
local touch = mouse("Touch", at(band, 0.5))
band.InputBegan:Fire(touch)
touch.Position = Vector3.new(touch.Position.X + 1, touch.Position.Y + 20, 0)
UIS.InputChanged:Fire(touch, false)
UIS.InputEnded:Fire(touch, false)
check("a vertical touch swipe does not move the slider", drag.CurrentValue == 100, drag.CurrentValue)
touch = mouse("Touch", at(band, 0.5))
band.InputBegan:Fire(touch)
check("touch waits for horizontal intent", drag.CurrentValue == 100)
touch.Position = Vector3.new(at(band, 0.3).X, touch.Position.Y, 0)
UIS.InputChanged:Fire(touch, false)
sandbox.step(1)
UIS.InputEnded:Fire(touch, false)
check("a horizontal touch drag moves it", drag.CurrentValue == 30, drag.CurrentValue)
drag:Lock("Premium")
sandbox.input.drag(band, at(band, 0.1), at(band, 0.1), 1)
check("a locked slider ignores drags", drag.CurrentValue == 30, drag.CurrentValue)
drag:Set(40)
check("programmatic Set still works while locked", drag.CurrentValue == 40)
drag:Unlock()

section("slider: keyboard and typing")
local keyed = Tab:CreateSlider({ Name = "Keyed", Range = { 0, 100 }, Increment = 2, CurrentValue = 50 })
mounted(keyed)
focus:focus(keyed, { visible = true })
sandbox.input.key("Right")
check("Right steps by Increment", keyed.CurrentValue == 52, keyed.CurrentValue)
sandbox.input.key("LeftShift")
sandbox.input.key("Left")
sandbox.input.keyUp("LeftShift")
check("Shift steps by 10 increments", keyed.CurrentValue == 32, keyed.CurrentValue)
sandbox.input.key("End")
check("End goes to the maximum", keyed.CurrentValue == 100, keyed.CurrentValue)
sandbox.input.key("Home")
check("Home goes to the minimum", keyed.CurrentValue == 0, keyed.CurrentValue)
sandbox.input.key("Return")
check("Enter starts typing in the pill", keyed._valueBox:IsFocused() and keyed._valueBox.Text == "0", keyed._valueBox.Text)
sandbox.input.key("Up")
check("Up steps while typing", keyed.CurrentValue == 2 and keyed._valueBox.Text == "2", keyed._valueBox.Text)
keyed._valueBox:ReleaseFocus(true)
focus:leave()
local box = keyed._valueBox
sandbox.input.typeText(box, "37", true)
check("a typed value commits (rounded)", keyed.CurrentValue == 38, keyed.CurrentValue)
check("the pill shows the value again", plain(box.Text) == "38", box.Text)
sandbox.input.typeText(box, "500", true)
local message = keyed.Root:FindFirstChild("Message")
check("out of range clamps", keyed.CurrentValue == 100, keyed.CurrentValue)
check("out of range states the range under the row", message and message.Visible and find(message, "Text").Text == "Must be between 0 and 100",
	message and find(message, "Text").Text)
check("the message is Danger", message and sameColor(find(message, "Text").TextColor3, Themes.Argon.Danger))
check("the row grows while the message shows", keyed.Root.Size.Y.Offset > 44, keyed.Root.Size.Y.Offset)
sandbox.advance(2.2)
check("the message hides after 2 s", message.Visible == false and keyed.Root.Size.Y.Offset == 44, keyed.Root.Size.Y.Offset)
sandbox.input.typeText(box, "abc", true)
check("a non-number keeps the value", keyed.CurrentValue == 100)
check("a non-number says so", message.Visible and find(message, "Text").Text == "Enter a number")
sandbox.advance(2.2)

section("slider: description, rows, theme, persistence")
local plainSlider = Tab:CreateSlider({ Name = "Plain", Range = { 0, 100 }, Increment = 1, CurrentValue = 50 })
local described = Tab:CreateSlider({ Name = "Described", Range = { 0, 100 }, Increment = 1, CurrentValue = 50,
	Description = "A deliberately long description so the wrap is real and the row has to grow to fit it." })
mounted(plainSlider, described)
check("a description grows the row", described.Root.Size.Y.Offset > plainSlider.Root.Size.Y.Offset,
	described.Root.Size.Y.Offset .. " vs " .. plainSlider.Root.Size.Y.Offset)
check("the description is el._description", described._description ~= nil and described._description.Name == "Description")
check("the description stays in the text column, clear of the slider", (function()
	local desc, band2 = described._description, described._hit
	return desc.AbsolutePosition.X + desc.AbsoluteSize.X <= band2.AbsolutePosition.X
		and desc.Position.Y.Offset >= band2.Position.Y.Offset + band2.Size.Y.Offset - 12
end)())
check("the slider stays on the title band", described._hit.Position.Y.Offset == plainSlider._hit.Position.Y.Offset)
local row = Tab:CreateRow({ Columns = 2 })
local fired
local inRow = row:CreateSlider({ Name = "InRow", Range = { 0, 10 }, Increment = 1, CurrentValue = 0, Callback = function(v) fired = v end })
inRow:Set(7)
check("row controls still work (v1 L190)", inRow.CurrentValue == 7 and fired == 7)
check("a row slider mounts into its column", inRow.Root.Parent == row.Columns[1].Holder)
Argon:SetTheme("Ocean")
check("the fill follows a theme switch", (function()
	local points = find(slider.Root, "Groove"):FindFirstChildOfClass("UIGradient").Color.Keypoints
	return sameColor(points[2].Value, Themes.Ocean.Accent) and sameColor(points[5].Value, Themes.Ocean.Track)
end)())
Argon:SetTheme("Argon")
slider:Set(35)
Argon:SaveConfiguration()
local saved = sandbox.decodeJson(sandbox.files["CA/cfg.rfld"])
check("a slider persists as a number", saved.CA_Slider == 35, tostring(saved.CA_Slider))
slider:Set(80)
sliderLast = nil
Argon:LoadConfiguration()
check("load restores the slider and fires its callback", slider.CurrentValue == 35 and sliderLast == 35, tostring(sliderLast))

-- =====================================================================================
section("stepper")
local stepCalls, stepLast = 0, nil
local stepper = Tab:CreateStepper({ Flag = "CA_Stepper", Name = "Stepper", Range = { 0, 2 }, Increment = 0.05, CurrentValue = 0.45,
	Callback = function(value) stepCalls += 1 stepLast = value end })
check("stepper initial value (v1 L128)", math.abs(stepper.CurrentValue - 0.45) < 1e-9, stepper.CurrentValue)
check("stepper Set returns self", stepper:Set(1.23) == stepper)
check("stepper rounds to the increment (v1 L130)", math.abs(stepper.CurrentValue - 1.25) < 1e-9, stepper.CurrentValue)
stepper:Set(-5)
check("stepper clamps to the minimum (v1 L132)", stepper.CurrentValue == 0, stepper.CurrentValue)
check("stepper fires its callback (v1 L133)", stepLast == 0, stepLast)
check("a reversed stepper Range is swapped", Tab:CreateStepper({ Name = "Rev", Range = { 10, 0 }, CurrentValue = 4 }).CurrentValue == 4)
mounted(stepper)
local well = stepper._group
check("minus dims at the minimum", sameColor(find(stepper.Root, "Minus").ImageColor3, Themes.Argon.Disabled)
	and sameColor(find(stepper.Root, "Plus").ImageColor3, Themes.Argon.Text2))
local right = mouse("MouseButton1", Vector2.new(well.AbsolutePosition.X + well.AbsoluteSize.X - 6, well.AbsolutePosition.Y + 6))
stepCalls = 0
well.InputBegan:Fire(right)
check("plus steps once on press", math.abs(stepper.CurrentValue - 0.05) < 1e-9 and stepCalls == 1, stepper.CurrentValue)
UIS.InputEnded:Fire(right, false)
sandbox.advance(0.6)
check("a short press does not repeat", math.abs(stepper.CurrentValue - 0.05) < 1e-9, stepper.CurrentValue)
well.InputBegan:Fire(right)
sandbox.advance(0.3)
check("hold waits 350 ms before repeating", math.abs(stepper.CurrentValue - 0.1) < 1e-9, stepper.CurrentValue)
sandbox.advance(0.7)
local held = stepper.CurrentValue
check("hold repeats (every 80 ms)", held >= 0.5 and held <= 0.6, held)
sandbox.advance(0.5)
check("repeats speed up after about 1 s", stepper.CurrentValue - held >= 0.5, stepper.CurrentValue - held)
UIS.InputEnded:Fire(right, false)
local stopped = stepper.CurrentValue
sandbox.advance(0.5)
check("release stops the repeat", stepper.CurrentValue == stopped, stepper.CurrentValue)
stepper:Set(1.95)
well.InputBegan:Fire(right)
sandbox.advance(1)
UIS.InputEnded:Fire(right, false)
check("hold stops at the maximum", stepper.CurrentValue == 2, stepper.CurrentValue)
check("plus dims at the maximum", sameColor(find(stepper.Root, "Plus").ImageColor3, Themes.Argon.Disabled))
well.MouseMoved:Fire(well.AbsolutePosition.X + 4, well.AbsolutePosition.Y + 6)
local hoverFill = find(stepper.Root, "HoverFill")
check("hover fills the inner minus button", hoverFill and hoverFill.Visible and hoverFill.Position == find(stepper.Root, "Minus").Position)
well.MouseMoved:Fire(well.AbsolutePosition.X + well.AbsoluteSize.X - 4, well.AbsolutePosition.Y + 6)
check("no hover fill on a sign at its limit", not hoverFill.Visible)
well.MouseLeave:Fire()
local left = mouse("MouseButton1", Vector2.new(well.AbsolutePosition.X + 4, well.AbsolutePosition.Y + 6))
well.InputBegan:Fire(left)
UIS.InputEnded:Fire(left, false)
check("minus steps down", math.abs(stepper.CurrentValue - 1.95) < 1e-9, stepper.CurrentValue)
sandbox.input.typeText(stepper._valueBox, "9", true)
check("typing clamps with the range stated", stepper.CurrentValue == 2
	and find(stepper.Root, "Message").Visible and find(find(stepper.Root, "Message"), "Text").Text == "Must be between 0 and 2")
sandbox.advance(2.2)
focus:focus(stepper, { visible = true })
sandbox.input.key("Left")
check("Left steps the stepper down", math.abs(stepper.CurrentValue - 1.95) < 1e-9, stepper.CurrentValue)
focus:leave()
stepper:Lock()
well.InputBegan:Fire(left)
UIS.InputEnded:Fire(left, false)
check("a locked stepper ignores presses", math.abs(stepper.CurrentValue - 1.95) < 1e-9, stepper.CurrentValue)
stepper:Unlock()
check("the stepper value shows its suffix", (function()
	local s = Tab:CreateStepper({ Name = "Delay", Range = { 0, 5 }, Increment = 0.5, CurrentValue = 1.5, Suffix = "s" })
	return plain(s._valueBox.Text) == "1.5s"
end)())

-- =====================================================================================
section("segmented")
local segCalls, segLast = 0, nil
local segmented = Tab:CreateSegmented({ Flag = "CA_Seg", Name = "Mode", Options = { "Safe", "Balanced", "Fast" }, CurrentOption = "Balanced",
	Callback = function(value) segCalls += 1 segLast = value end })
check("segmented initial value (v1 L136)", segmented.CurrentValue == "Balanced", segmented.CurrentValue)
check("segmented Set returns self", segmented:Set("Fast") == segmented)
check("segmented selects (v1 L138)", segmented.CurrentValue == "Fast" and segmented.CurrentOption == "Fast")
check("segmented callback is a string (v1 L139)", segLast == "Fast" and type(segLast) == "string")
segmented:Set("Nope")
check("segmented rejects unknown values (v1 L141)", segmented.CurrentValue == "Fast")
check("a flagged unknown value is parked in pending", Argon._pendingFlags.CA_Seg == "Nope", tostring(Argon._pendingFlags.CA_Seg))
segCalls = 0
segmented:Refresh({ "Safe", "Fast" })
check("Refresh keeps a valid value (v1 L143)", segmented.CurrentValue == "Fast")
segmented:Refresh({ "One", "Two" })
check("Refresh resets an invalid value (v1 L145)", segmented.CurrentValue == "One")
check("Refresh fires no callback", segCalls == 0, segCalls)
segmented:Refresh({ "One", "Nope" })
check("Refresh keeps a valid value over a parked one", segmented.CurrentValue == "One")
segmented:Refresh({ "Nope", "Other" })
check("Refresh applies a parked value when the current one goes", segmented.CurrentValue == "Nope" and Argon._pendingFlags.CA_Seg == nil)
check("Refresh with keepCurrent = false resets to the first option", segmented:Refresh({ "Other", "Nope" }, false).CurrentValue == "Other")
segmented:Refresh({ "Safe", "Balanced", "Fast" })
segmented:Set({ "Balanced" })
check("Set accepts a table (first entry)", segmented.CurrentValue == "Balanced")
local numbers = Tab:CreateSegmented({ Name = "Numbers", Options = { 1, 2, 3 }, CurrentValue = { 2 }, Callback = function(v) segLast = v end })
check("options are stringified and CurrentValue takes a table", numbers.CurrentValue == "2" and numbers.Options[3] == "3")
numbers:Set(3)
check("the callback gets the string", segLast == "3", tostring(segLast))
check("no options gives {'None'}", Tab:CreateSegmented({ Name = "Empty" }).CurrentValue == "None")
check("an unknown CurrentOption falls back to the first option", Tab:CreateSegmented({ Name = "Bad", Options = { "A", "B" }, CurrentOption = "Z" }).CurrentValue == "A")
mounted(segmented)
local labels = findAll(segmented.Root, "Option")
local indicator = find(segmented.Root, "Indicator")
check("one label per option", #labels == 3, #labels)
check("the indicator sits on the selected label", indicator and indicator.Position == labels[2].Position and indicator.Size == labels[2].Size)
check("the indicator is AccentSoft with an Accent stroke at 0.5", sameColor(indicator.BackgroundColor3, Themes.Argon.AccentSoft)
	and indicator:FindFirstChildOfClass("UIStroke").Transparency == 0.5)
check("the selected label is AccentText, the rest Text2", sameColor(labels[2].TextColor3, Themes.Argon.AccentText)
	and sameColor(labels[1].TextColor3, Themes.Argon.Text2))
segCalls = 0
sandbox.input.click(labels[3])
check("clicking a label selects it", segmented.CurrentValue == "Fast" and segLast == "Fast" and segCalls == 1)
check("the indicator springs toward it", indicator.Position ~= labels[3].Position)
sandbox.advance(0.6)
check("the indicator settles on it", indicator.Position == labels[3].Position and indicator.Size == labels[3].Size)
focus:focus(segmented, { visible = true })
sandbox.input.key("Left")
check("Left selects the previous option", segmented.CurrentValue == "Balanced")
sandbox.input.key("Left")
sandbox.input.key("Left")
check("Left stops at the first option", segmented.CurrentValue == "Safe")
focus:leave()
local many = Tab:CreateSegmented({ Name = "Quality", Options = { "Low", "Medium", "High", "Ultra", "Max" }, CurrentOption = "High",
	Callback = function(v) segLast = v end })
mounted(many)
check("more than 4 options render as a field", find(many.Root, "Field") ~= nil and find(many.Root, "Indicator") == nil)
check("the field shows the value", find(many.Root, "Value").Text == "High")
sandbox.input.click(many.Root)
check("clicking the field opens the list", Window._popover:isOpen(many))
local menuRows = {}
for _, child in ipairs(Window._popover.contents.segmented.frame:GetDescendants()) do
	if child.Name == "Option" and child.Visible then menuRows[#menuRows + 1] = child end
end
check("the list has a row per option", #menuRows == 5, #menuRows)
sandbox.input.click(menuRows[5])
check("picking a row selects it and closes the list", many.CurrentValue == "Max" and segLast == "Max" and not Window._popover:isOpen(many))
check("the field follows", find(many.Root, "Value").Text == "Max")
local wide = Tab:CreateSegmented({ Name = "Wide", Options = { "Alpha option", "Beta option", "Gamma option", "Delta option" } })
mounted(wide)
check("a strip too wide for its row also renders as a field", find(wide.Root, "Field") ~= nil)
check("an untitled strip spans the row (v1)", (function()
	local bare = Tab:CreateSegmented({ Options = { "Left", "Right" } })
	local track = find(bare.Root, "Track")
	return bare._title.Visible == false and track.Size.X.Scale == 1 and track.Position.X.Offset == 16
end)())
many:Refresh({ "On", "Off" })
check("Refresh to 2 options turns the field into a strip", find(many.Root, "Indicator") ~= nil and #findAll(many.Root, "Option") == 2)
check("SetOptions is an alias of Refresh", many.SetOptions == many.Refresh)
segmented:Set("Balanced")
Argon:SaveConfiguration()
check("segmented persists as a string", sandbox.decodeJson(sandbox.files["CA/cfg.rfld"]).CA_Seg == "Balanced")
local late = Tab:CreateSegmented({ Flag = "CA_Late", Name = "Late options", Callback = function(v) segLast = v end })
sandbox.files["CA/cfg.rfld"] = sandbox.encodeJson({ CA_Late = "Fast" })
Argon:LoadConfiguration()
check("a restored value waits for its option", late.CurrentValue == "None" and Argon._pendingFlags.CA_Late == "Fast")
late:Refresh({ "Safe", "Fast" })
check("it applies when Refresh brings the option", late.CurrentValue == "Fast")

-- =====================================================================================
section("button")
local pressedCount, args = 0, nil
local button = Tab:CreateButton({ Name = "Button", Callback = function(...) pressedCount += 1 args = select("#", ...) end })
check("button created (v1 L104)", button.Type == "Button")
mounted(button)
sandbox.input.click(button.Root)
check("a click runs the callback with no arguments", pressedCount == 1 and args == 0, args)
check("Set(name) renames it (Rayfield)", button:Set("Renamed") == button and button.Name == "Renamed" and button._title.Text == "Renamed")
check("an action row shows a chevron", find(button.Root, "Chevron") ~= nil)
check("buttons get a Roboto FontFace (v1 L1174)", (function()
	local faced = Tab:CreateButton({ Name = "Faced" })
	local face
	for _, child in ipairs(faced.Root:GetDescendants()) do
		if child.ClassName == "TextLabel" and child.FontFace then face = child.FontFace end
	end
	return face ~= nil and tostring(face.Family):find("Roboto", 1, true) ~= nil, face and tostring(face.Family)
end)())
button:SetLoading(true)
check("SetLoading returns self and shows a spinner", find(button.Root, "Chevron").Rotation == 0 and sandbox.runningLoops() >= 1)
sandbox.input.click(button.Root)
check("a busy button ignores presses", pressedCount == 1)
button:SetLoading(false)
check("the spinner stops", sandbox.runningLoops() == 0, sandbox.runningLoops())
sandbox.input.click(button.Root)
check("presses work again", pressedCount == 2)
button:Lock("Premium")
sandbox.input.click(button.Root)
check("a locked button ignores clicks", pressedCount == 2)
check("_press is blocked while locked", button:_press() == false)
button:Unlock()
check("_press presses (pins, palette)", button:_press() == true and pressedCount == 3)
focus:focus(button, { visible = true })
sandbox.input.key("Return")
check("Enter presses the focused button", pressedCount == 4)
focus:leave()

local thread, asyncRuns = nil, 0
local async = Tab:CreateButton({ Name = "Async", Async = true, Callback = function()
	asyncRuns += 1
	thread = coroutine.running()
	coroutine.yield()
	return true
end })
mounted(async)
sandbox.input.click(async.Root)
check("Async runs the callback off the caller", asyncRuns == 1 and async._loading == true)
sandbox.input.click(async.Root)
check("Async blocks re-entry while it runs", asyncRuns == 1)
coroutine.resume(thread)
check("the spinner ends when the callback returns", async._loading == false and sandbox.runningLoops() == 0)
check("returning true flashes a check", async._ok ~= nil and find(async.Root, "Chevron").Visible)
sandbox.advance(1.3)
check("the check clears after 1.2 s", async._ok == nil)

local holdRuns = 0
local hold = Tab:CreateButton({ Name = "Delete all", Variant = "Danger", HoldToConfirm = true, Callback = function() holdRuns += 1 end })
mounted(hold)
sandbox.input.click(hold.Root)
check("a click does not run a hold-to-confirm button", holdRuns == 0)
hold.Root.InputBegan:Fire(mouse("MouseButton1"))
check("holding sweeps a fill", find(hold.Root, "HoldFill") ~= nil and find(hold.Root, "HoldFill").Visible)
sandbox.advance(0.5)
hold.Root.InputEnded:Fire(mouse("MouseButton1"))
sandbox.advance(0.6)
check("releasing early cancels", holdRuns == 0 and not find(hold.Root, "HoldFill").Visible)
hold.Root.InputBegan:Fire(mouse("MouseButton1"))
sandbox.advance(0.9)
check("holding 0.8 s confirms", holdRuns == 1)
hold.Root.InputEnded:Fire(mouse("MouseButton1"))
focus:focus(hold, { visible = true })
sandbox.input.key("Return")
sandbox.input.keyUp("Return")
sandbox.advance(1)
check("a released Enter cancels the hold", holdRuns == 1)
sandbox.input.key("Return")
sandbox.advance(0.9)
sandbox.input.keyUp("Return")
check("a held Enter confirms", holdRuns == 2)
focus:leave()

local primary = Tab:CreateButton({ Name = "Save", Variant = "Primary" })
local danger = Tab:CreateButton({ Name = "Remove", Variant = "Danger" })
local soft = Tab:CreateButton({ Name = "Reset", Variant = "DangerSoft" })
local ghost = Tab:CreateButton({ Name = "Docs", Variant = "Ghost", Icon = "book" })
mounted(primary, danger, soft, ghost)
local pill = find(primary.Root, "Pill")
check("a pill is 36 tall inside 8 x 12 padding", pill and pill.AbsoluteSize.Y == 36 and primary.Root.Size.Y.Offset == 52
	and math.abs(pill.AbsolutePosition.X - primary.Root.AbsolutePosition.X - 12) < 1e-6
	and math.abs(pill.AbsolutePosition.Y - primary.Root.AbsolutePosition.Y - 8) < 1e-6
	and math.abs(pill.AbsoluteSize.X - (primary.Root.AbsoluteSize.X - 24)) < 1e-6)
check("a pill is centre-anchored so the press scale stays in place", pill.AnchorPoint == Vector2.new(0.5, 0.5))
check("Primary uses the AccentHi -> Accent gradient and OnAccent ink", pill:FindFirstChildOfClass("UIGradient") ~= nil
	and sameColor(primary._title.TextColor3, Themes.Argon.OnAccent))
check("the pill label is centred in the pill", primary._title.Parent == pill and primary._title.TextXAlignment == Enum.TextXAlignment.Center)
check("Danger is a Danger fill with OnStatus ink", sameColor(find(danger.Root, "Pill").BackgroundColor3, Themes.Argon.Danger)
	and sameColor(danger._title.TextColor3, Themes.Argon.OnStatus))
check("DangerSoft is a DangerSoft fill with Danger ink", sameColor(find(soft.Root, "Pill").BackgroundColor3, Themes.Argon.DangerSoft)
	and sameColor(soft._title.TextColor3, Themes.Argon.Danger))
check("Ghost has no fill and AccentText ink", find(ghost.Root, "Pill").BackgroundTransparency == 1
	and sameColor(ghost._title.TextColor3, Themes.Argon.AccentText) and find(ghost.Root, "Icon") ~= nil)
primary.Root.InputBegan:Fire(mouse("MouseButton1"))
local scale = pill:FindFirstChildOfClass("UIScale")
check("press shrinks a pill to 0.97", scale and scale.Scale == 0.97)
check("press swaps the gradient to Accent -> AccentDeep", sameColor(pill:FindFirstChildOfClass("UIGradient").Color.Keypoints[1].Value, Themes.Argon.Accent))
primary.Root.InputEnded:Fire(mouse("MouseButton1"))
check("release restores the pill", scale.Scale == 1)
button.Root.InputBegan:Fire(mouse("MouseButton1"))
check("action rows never scale", button.Root:FindFirstChildOfClass("UIScale") == nil and find(button.Root, "UIScale") == nil)
button.Root.InputEnded:Fire(mouse("MouseButton1"))
primary:SetDisabled(true)
check("a disabled pill draws Disabled ink", sameColor(primary._title.TextColor3, Themes.Argon.Disabled))
primary:SetDisabled(false)
primary:SetDesc("Writes the profile to disk.")
check("a pill's description sits under the pill", primary._description.Position.Y.Offset >= 8 + pill.Size.Y.Offset
	and primary.Root.Size.Y.Offset > 52, primary._description.Position.Y.Offset)
check("so does a group's", (function()
	local g = Tab:CreateButtonGroup({ Description = "Both write to disk.", Buttons = { { Name = "A" }, { Name = "B" } } })
	return g._description.Position.Y.Offset >= 8 + find(g.Root, "Button").Size.Y.Offset, g._description.Position.Y.Offset
end)())

local keyRuns = 0
local hotkey = Tab:CreateButton({ Name = "Hotkey", Keybind = "Y", Callback = function() keyRuns += 1 end })
sandbox.input.press("Y")
check("Keybind = 'Y' presses it (even before it mounts)", keyRuns == 1)
mounted(hotkey)
check("the bound key shows as a keycap", find(hotkey.Root, "Keycap") and find(hotkey.Root, "Keycap").Text == "Y")
hotkey:Lock()
sandbox.input.press("Y")
check("a locked button's key does nothing", keyRuns == 1)
hotkey:Destroy()
sandbox.input.press("Y")
check("a destroyed button's key does nothing", keyRuns == 1)
check("Shortcut shows a keycap", (function()
	local b = Tab:CreateButton({ Name = "Copy", Shortcut = "Ctrl C" })
	return find(b.Root, "Keycap").Text == "Ctrl C" and find(b.Root, "Chevron") == nil
end)())

-- =====================================================================================
section("button group")
local hits = {}
local groupEl = Tab:CreateButtonGroup({ Buttons = {
	{ Name = "Copy", Icon = "copy", Callback = function() hits.copy = (hits.copy or 0) + 1 end },
	{ Name = "Save", Variant = "Primary", Callback = function() hits.save = (hits.save or 0) + 1 end },
	{ Name = "Delete", Variant = "Danger", Callback = function() hits.delete = (hits.delete or 0) + 1 end },
} })
mounted(groupEl)
check("ButtonGroup type and handles", groupEl.Type == "ButtonGroup" and #groupEl.Buttons == 3 and groupEl.Buttons[2].Name == "Save")
local pills = findAll(groupEl.Root, "Button")
check("one pill per button, side by side", #pills == 3 and pills[2].Position.X.Scale > pills[1].Position.X.Scale and pills[1].Size.Y.Offset == 36)
check("pills share the row inside 8 x 12 padding with 8 px gaps", (function()
	local root = groupEl.Root
	local x0, width = root.AbsolutePosition.X, root.AbsoluteSize.X
	local left = pills[1].AbsolutePosition.X - x0
	local right = x0 + width - (pills[3].AbsolutePosition.X + pills[3].AbsoluteSize.X)
	local gap = pills[2].AbsolutePosition.X - (pills[1].AbsolutePosition.X + pills[1].AbsoluteSize.X)
	local top = pills[1].AbsolutePosition.Y - root.AbsolutePosition.Y
	return math.abs(left - 12) < 1e-6 and math.abs(right - 12) < 1e-6 and math.abs(gap - 8) < 1e-6 and math.abs(top - 8) < 1e-6,
		("left %s right %s gap %s top %s"):format(left, right, gap, top)
end)())
sandbox.input.click(pills[2])
check("each pill runs its own callback", hits.save == 1 and hits.copy == nil)
groupEl.Buttons[1]:SetLoading(true)
sandbox.input.click(pills[1])
check("a busy handle ignores presses", hits.copy == nil and sandbox.runningLoops() >= 1)
check("SetLoading on a handle returns the handle", groupEl.Buttons[1]:SetLoading(false) == groupEl.Buttons[1] and sandbox.runningLoops() == 0)
sandbox.input.click(pills[1])
check("it presses again", hits.copy == 1)
check("a Primary handle has the gradient", pills[2]:FindFirstChildOfClass("UIGradient") ~= nil and pills[1]:FindFirstChildOfClass("UIGradient") == nil)
groupEl.Buttons[3]:Set("Erase")
check("Set renames a handle", pills[3].Text == "Erase" and groupEl.Buttons[3].Name == "Erase")
focus:focus(groupEl, { visible = true })
sandbox.input.key("Right")
sandbox.input.key("Right")
sandbox.input.key("Return")
check("Right picks a button and Enter presses it", hits.delete == 1)
focus:leave()

-- =====================================================================================
section("keybind: v1 and Rayfield semantics")
local kbCalls, kbArgs, kbChanged = 0, nil, nil
local keybind = Tab:CreateKeybind({ Flag = "CA_Key", Name = "Keybind", CurrentKeybind = "P",
	Callback = function(...) kbCalls += 1 kbArgs = table.pack(...) end })
check("keybind keeps a string key", keybind.CurrentKeybind == "P" and keybind.CurrentValue == "P")
check("keybind Set returns self", keybind:Set("K") == keybind)
check("keybind stores the key (v1 L97)", keybind.CurrentKeybind == "K" and keybind.CurrentValue == "K")
check("a Rayfield rebind does not run the press callback", kbCalls == 0)
keybind:OnChanged(function(value) kbChanged = value end)
keybind:Set("L")
check("a rebind fires OnChanged(key)", kbChanged == "L", tostring(kbChanged))
sandbox.input.press("L")
check("Rayfield mode: Callback() fires on press with no arguments", kbCalls == 1 and kbArgs.n == 0)
sandbox.input.press("K")
check("the old key no longer fires", kbCalls == 1)
check("an EnumItem key is stored as its name", Tab:CreateKeybind({ Name = "Enum", CurrentKeybind = Enum.KeyCode.Q }).CurrentKeybind == "Q")
check("a lowercase letter is accepted", keybind:Set("m").CurrentKeybind == "M")
keybind:Set("Nope")
check("an unknown key name is ignored", keybind.CurrentKeybind == "M")
keybind:Set(nil)
check("nil unbinds to None", keybind.CurrentKeybind == "None")
keybind:Set("L")

local holdStates = {}
local holdKey = Tab:CreateKeybind({ Name = "Hold", CurrentKeybind = "H", HoldToInteract = true,
	Callback = function(state) holdStates[#holdStates + 1] = state end })
sandbox.input.key("H")
check("HoldToInteract: Callback(true) on press", holdStates[1] == true and holdKey._active == true and holdKey._mode == "Hold")
sandbox.input.keyUp("H")
check("HoldToInteract: Callback(false) on release", holdStates[2] == false and holdKey._active == false)

local v1Calls, v1Pressed = {}, {}
local v1 = Tab:CreateKeybind({ Flag = "CA_V1", Name = "V1", CurrentKeybind = "J", Toggle = true,
	Callback = function(key2) v1Calls[#v1Calls + 1] = key2 end,
	OnPressed = function(key2, active) v1Pressed[#v1Pressed + 1] = { key2, active } end })
sandbox.input.press("J")
check("v1 mode: OnPressed(key, active) on press", v1Pressed[1] and v1Pressed[1][1] == "J" and v1Pressed[1][2] == true)
check("v1 mode: the press does not run Callback", #v1Calls == 0)
sandbox.input.press("J")
check("Toggle latches active", v1Pressed[2][2] == false and v1._active == false and v1._mode == "Toggle")
v1:Set("U")
check("v1 mode: Callback(key) fires on rebind", v1Calls[1] == "U")
local pulse = Tab:CreateKeybind({ Name = "Pulse", CurrentKeybind = "Z", OnPressed = function() end })
sandbox.input.press("Z")
check("a press without Toggle is a short pulse", pulse._active == true)
sandbox.advance(0.25)
check("the pulse ends after 0.18 s", pulse._active == false)

local changeCalls = {}
local change = Tab:CreateKeybind({ Flag = "CA_Change", Name = "Change", CurrentKeybind = "N", CallOnChange = true,
	Callback = function(key2) changeCalls[#changeCalls + 1] = key2 end })
sandbox.input.press("N")
check("CallOnChange: a press does not run Callback", #changeCalls == 0)
change:Set("B")
check("CallOnChange: Callback(key) fires on rebind", changeCalls[1] == "B")

section("keybind: restore and persistence")
Argon:SaveConfiguration()
local savedKeys = sandbox.decodeJson(sandbox.files["CA/cfg.rfld"])
check("keybinds persist as key names", savedKeys.CA_Key == "L" and savedKeys.CA_V1 == "U" and savedKeys.CA_Change == "B")
check("_encode returns the key name", keybind:_encode() == "L")
sandbox.files["CA/cfg.rfld"] = sandbox.encodeJson({ CA_Key = "G", CA_V1 = "I", CA_Change = "O" })
kbCalls = 0
local v1Before, changeBefore = #v1Calls, #changeCalls
Argon:LoadConfiguration()
check("restore applies the keys", keybind.CurrentKeybind == "G" and v1.CurrentKeybind == "I" and change.CurrentKeybind == "O")
check("Rayfield mode: a restore fires nothing", kbCalls == 0, kbCalls)
check("v1 mode: a restore runs Callback(key)", #v1Calls == v1Before + 1 and v1Calls[#v1Calls] == "I")
check("CallOnChange: a restore fires nothing", #changeCalls == changeBefore)
sandbox.input.press("G")
check("the restored key fires", kbCalls == 1)

section("keybind: capture")
mounted(keybind)
local cap = find(keybind.Root, "Cap")
check("the cap shows the key in Key mono", cap.Text == "G" and tostring(cap.FontFace.Family):find("RobotoMono", 1, true) ~= nil)
sandbox.input.click(keybind.Root)
check("a click starts capture", keybind._capturing == true and cap.Text == "Press a key…")
check("listening draws AccentSoft with the hint", sameColor(cap.BackgroundColor3, Themes.Argon.AccentSoft)
	and find(find(keybind.Root, "Message"), "Text").Text == "Mouse buttons work · Backspace clears")
check("a drain bar runs under the cap", find(keybind.Root, "Drain") ~= nil and find(keybind.Root, "Drain").Visible)
kbCalls = 0
sandbox.input.press("T")
check("any key sets it", keybind.CurrentKeybind == "T" and not keybind._capturing and kbCalls == 0)
check("the hint hides after capture", not find(keybind.Root, "Message").Visible)
sandbox.input.click(keybind.Root)
sandbox.input.press("Escape")
check("Escape cancels and keeps the key", keybind.CurrentKeybind == "T" and not keybind._capturing)
sandbox.input.click(keybind.Root)
sandbox.input.press("Backspace")
check("Backspace sets None", keybind.CurrentKeybind == "None")
check("None is drawn Dim", sameColor(cap.TextColor3, Themes.Argon.Dim))
sandbox.input.click(keybind.Root)
UIS.InputBegan:Fire(mouse("MouseButton2"), false)
check("MouseButton2 can be bound", keybind.CurrentKeybind == "MouseButton2" and cap.Text == "RMB")
kbCalls = 0
UIS.InputBegan:Fire(mouse("MouseButton2"), false)
check("a mouse-button bind fires", kbCalls == 1)
sandbox.input.click(keybind.Root)
sandbox.input.pad("ButtonX")
check("a pad button can be bound", keybind.CurrentKeybind == "ButtonX")
sandbox.input.click(keybind.Root)
sandbox.advance(5.2)
check("capture times out after 5 s and keeps the key", not keybind._capturing and keybind.CurrentKeybind == "ButtonX")
sandbox.input.click(keybind.Root)
UIS.InputBegan:Fire(mouse("MouseButton1", Vector2.new(-500, -500)), false)
check("a click outside cancels", not keybind._capturing and keybind.CurrentKeybind == "ButtonX")
sandbox.input.click(keybind.Root)
sandbox.input.click(keybind.Root)
check("a second click on the row cancels", not keybind._capturing)
local other = 0
local otherKey = Tab:CreateKeybind({ Name = "Fly", CurrentKeybind = "R", Callback = function() other += 1 end })
sandbox.input.click(keybind.Root)
sandbox.input.press("R")
check("the captured key does not fire other binds", other == 0 and keybind.CurrentKeybind == "R")
local warning = find(keybind.Root, "Message")
check("a conflict warns under the row", warning.Visible and find(warning, "Text").Text == "Also used by Fly. Both will fire."
	and sameColor(find(warning, "Text").TextColor3, Themes.Argon.Warning))
local actionButtons = {}
for _, child in ipairs(warning:GetChildren()) do
	if child.Name == "Action" and child.Visible then actionButtons[child.Text] = child end
end
check("the warning offers Swap and Keep", actionButtons.Swap ~= nil and actionButtons.Keep ~= nil)
sandbox.input.press("R")
check("both fire until resolved", other == 1)
sandbox.input.click(actionButtons.Swap)
check("Swap moves the other bind to the old key", otherKey.CurrentKeybind == "ButtonX" and keybind.CurrentKeybind == "R" and not warning.Visible)
local menuKey = Tab:CreateKeybind({ Name = "Menu key", CurrentKeybind = "Insert", CallOnChange = true,
	Callback = function(name) Window:SetToggleKey(name) end })
mounted(menuKey)
sandbox.input.click(menuKey.Root)
sandbox.input.press("F6")
check("a callback that moves another bind onto the key is no conflict", Window._toggleKey == Enum.KeyCode.F6
	and not (find(menuKey.Root, "Message") and find(menuKey.Root, "Message").Visible))
sandbox.input.click(menuKey.Root)
sandbox.input.press("Insert")
focus:focus(keybind, { visible = true })
sandbox.input.key("Return")
check("Enter starts capture", keybind._capturing == true)
sandbox.input.press("V")
check("the next key binds", keybind.CurrentKeybind == "V")
focus:leave()
check("capture leaves no input layer behind", Window._router.stats().consumers == consumers,
	Window._router.stats().consumers .. " vs " .. consumers)

section("keybind: lock, destroy, overlay")
sandbox.advance(0.3)
local list = Window._keybinds
check("keybinds are listed for the overlay", type(list) == "table" and table.find(list, keybind) ~= nil)
check("overlay fields exist", keybind._mode == "Press" and keybind._active == false and keybind.DisplayInKeybindList == true)
check("SetActive and SetOverlayVisible return self", keybind:SetActive(true) == keybind and keybind:SetOverlayVisible(false) == keybind
	and keybind._active == true and keybind.DisplayInKeybindList == false)
check("an active bind draws its key AccentText", sameColor(cap.TextColor3, Themes.Argon.AccentText))
keybind:SetActive(false)
local refreshes = 0
local overlays = Window._overlays
local previousRefresh = overlays.refreshKeybinds
overlays.refreshKeybinds = function(self2, ...)
	refreshes += 1
	return previousRefresh(self2, ...)
end
keybind:Set("Q")
check("a key change refreshes the overlay", refreshes >= 1)
overlays.refreshKeybinds = previousRefresh
kbCalls = 0
keybind:Lock()
sandbox.input.press("Q")
check("a locked bind never fires", kbCalls == 0)
sandbox.input.click(keybind.Root)
check("a locked bind does not capture", not keybind._capturing)
keybind:Unlock()
keybind:SetDisabled(true)
sandbox.input.press("Q")
check("a disabled bind never fires", kbCalls == 0)
keybind:SetDisabled(false)
sandbox.input.press("Q")
check("it fires again when enabled", kbCalls == 1)
keybind:Destroy()
sandbox.input.press("Q")
check("a destroyed bind never fires", kbCalls == 1)
check("a destroyed bind leaves the overlay list", table.find(Window._keybinds, keybind) == nil)
check("Hold mode shows its mode", (function()
	local hk = Tab:CreateKeybind({ Name = "Sprint", CurrentKeybind = "LeftShift", HoldToInteract = true })
	local mode = find(hk.Root, "ModeText")
	return mode ~= nil and mode.Text == "Hold" and find(hk.Root, "Cap").Text == "LShift"
end)())

-- =====================================================================================
section("density change remounts cleanly")
local touchPill = Tab:CreateButton({ Name = "Touch pill", Variant = "Primary", Icon = "save" })
local touchSlider = Tab:CreateSlider({ Name = "Touch slider", Range = { 0, 10 }, Increment = 1, CurrentValue = 4 })
local touchStep = Tab:CreateStepper({ Name = "Touch stepper", Range = { 0, 10 }, CurrentValue = 4 })
local touchSeg = Tab:CreateSegmented({ Name = "Touch seg", Options = { "A", "B" } })
local touchKey = Tab:CreateKeybind({ Name = "Touch key", CurrentKeybind = "F9" })
local touchGroup = Tab:CreateButtonGroup({ Buttons = { { Name = "One" }, { Name = "Two", Icon = "copy" } } })
mounted(touchPill, touchSlider, touchStep, touchSeg, touchKey, touchGroup)
sandbox.input.click(touchKey.Root)
touchSlider._valueBox:CaptureFocus()
sandbox.setPreferredInput("touch")
sandbox.focusedTextBox = nil -- the engine drops focus with the destroyed box; the sandbox does not
sandbox.advance(0.3)
check("a density change ends a capture and its input layer", not touchKey._capturing
	and Window._router.stats().consumers == consumers, Window._router.stats().consumers)
check("a density change ends typing", not touchSlider._editing)
check("controls remount at touch sizes", find(touchPill.Root, "Pill").Size.Y.Offset == 44
	and touchSlider.Root:FindFirstChild("Hit").Size.Y.Offset == 40 and touchStep._group.Size.Y.Offset == 40
	and find(touchGroup.Root, "Button").Size.Y.Offset == 44)
check("values survive the remount", touchSlider.CurrentValue == 4 and touchKey.CurrentKeybind == "F9"
	and plain(touchSlider._valueBox.Text) == "4" and find(touchKey.Root, "Cap").Text == "F9")
touchSeg:Set("B")
sandbox.advance(0.5)
check("a remounted strip still tracks its value", find(touchSeg.Root, "Indicator").Position == findAll(touchSeg.Root, "Option")[2].Position)
sandbox.setPreferredInput("mouse")
sandbox.advance(0.3)
check("and back to mouse sizes", find(touchPill.Root, "Pill").Size.Y.Offset == 36 and touchSlider.Root:FindFirstChild("Hit").Size.Y.Offset == 28)
sandbox.input.click(touchKey.Root)
check("the listening glow works after its row was rebuilt", #sandbox.signalErrors == 0 and Window._glow.slots[3].image.Visible,
	table.concat(sandbox.signalErrors, " | "))
sandbox.input.press("Escape")
check("a released glow is taken out of the row", Window._glow.slots[3].image.Parent == nil)
touchPill.Root.MouseEnter:Fire()
check("a Primary pill glows on hover", Window._glow.slots[3].image.Parent == touchPill._pill.Parent)
touchPill.Root.MouseLeave:Fire()
check("and lets the glow go on leave", Window._glow.slots[3].image.Parent == nil)

-- =====================================================================================
section("instance budget (DESIGN_V2 6.21; mounted, untouched, Divider counted)")
local fresh = {
	{ "Button action row", 4, Tab:CreateButton({ Name = "Budget row" }) },
	{ "Button pill (Primary)", 6, Tab:CreateButton({ Name = "Budget pill", Variant = "Primary" }) },
	{ "Button pill (Danger)", 6, Tab:CreateButton({ Name = "Budget danger", Variant = "Danger" }) },
	{ "ButtonGroup (3 Secondary)", 8, Tab:CreateButtonGroup({ Buttons = { { Name = "A" }, { Name = "B" }, { Name = "C" } } }) },
	-- the slider is over DESIGN's 10: the anatomy it lists (Hit, groove, gradient fill, stroked thumb,
	-- value pill, each with its corner) cannot fit 10; the fill shares the groove frame to save 3
	{ "Slider", 12, Tab:CreateSlider({ Name = "Budget slider", Range = { 0, 100 }, Increment = 1 }) },
	{ "Stepper", 8, Tab:CreateStepper({ Name = "Budget stepper", Range = { 0, 10 } }) },
	{ "Segmented (3)", 11, Tab:CreateSegmented({ Name = "Budget seg", Options = { "A", "B", "C" } }) },
	{ "Keybind", 6, Tab:CreateKeybind({ Name = "Budget key", CurrentKeybind = "F8" }) },
}
sandbox.advance(0.3)
for _, entry in ipairs(fresh) do
	local n = budget(entry[3])
	print(("    %-28s %d instances"):format(entry[1], n))
	check(entry[1] .. " within " .. entry[2], n <= entry[2], n)
end

-- =====================================================================================
section("hygiene")
for _, element in ipairs(Tab._elements) do local _ = element.Root end
sandbox.advance(3)
local handlers = sandbox.metrics().handlers
check("no input handlers left behind", handlers.InputChanged == baseline.InputChanged and handlers.InputEnded == baseline.InputEnded,
	("changed %d/%d ended %d/%d"):format(handlers.InputChanged, baseline.InputChanged, handlers.InputEnded, baseline.InputEnded))
check("no loops running at rest", sandbox.runningLoops() == 0, sandbox.runningLoops())
check("no warnings", #sandbox.warnings == 0, table.concat(sandbox.warnings, " | "))
check("no errors in signal handlers", #sandbox.signalErrors == 0, table.concat(sandbox.signalErrors, " | "))

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	print("\nFailures:")
	for _, line in ipairs(failures) do print("  - " .. line) end
	process.exit(1)
end
