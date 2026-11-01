--!nocheck
-- Controls B suite (Argon UI v2): Input, TextArea, Dropdown and ColorPicker under the Lune sandbox.
--   lune run tests/controls_b.luau [-- <bundle path>]      (default: ARGON_BUNDLE or argon-ui.luau)

local process = require("@lune/process")
local fs = require("@lune/fs")
local sandbox = require("./sandbox")
local env = sandbox.environment
local Color3, Vector2, Enum = env.Color3, env.Vector2, sandbox.Enum
local task = env.task

local BUNDLE = process.args[1] or process.env.ARGON_BUNDLE or (fs.isFile("argon-ui.luau") and "argon-ui.luau" or "../argon-ui.luau")

local passed, failed, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		passed += 1
		print(("  PASS  %s"):format(name))
	else
		failed += 1
		failures[#failures + 1] = name .. (detail ~= nil and (" -- " .. tostring(detail)) or "")
		print(("  FAIL  %s%s"):format(name, detail ~= nil and (" -- " .. tostring(detail)) or ""))
	end
end
local function section(title) print("\n== " .. title .. " ==") end

local function find(root, predicate)
	for _, child in ipairs(root:GetDescendants()) do
		if predicate(child) then return child end
	end
	return nil
end
local function named(root, name, class)
	return find(root, function(child) return child.Name == name and (class == nil or child.ClassName == class) end)
end
local function count(root) return #root:GetDescendants() + 1 end
local function created() return sandbox.metrics().created end
local function hex(color)
	return ("%02X%02X%02X"):format(math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end
local function near(a, b) return math.abs(a - b) < 1e-3 end
-- Instances a fresh row mounts, without on-demand parts; the row Divider counts when RowView adds it.
local function budget(el)
	return count(el.Root)
end
-- The last input kind the Router saw (touch / mouse), without switching the density.
local function lastInput(kind)
	local inputType = kind == "touch" and Enum.UserInputType.Touch or (kind == "keyboard" and Enum.UserInputType.Keyboard or Enum.UserInputType.MouseButton1)
	sandbox.UserInputService.InputBegan:Fire({ UserInputType = inputType, KeyCode = Enum.KeyCode.Unknown,
		Position = env.Vector3.new(0, 0, 0), UserInputState = Enum.UserInputState.Begin, Delta = env.Vector3.new(0, 0, 0) }, true)
end

section("load")
local ok, Argon = pcall(sandbox.load, BUNDLE)
check("bundle loads", ok, not ok and Argon or nil)
if not ok then process.exit(1) end

local Window = Argon:CreateWindow({ Name = "Controls B", GuiName = "ControlsB", ConfigurationSaving = { Enabled = true, FolderName = "CB", FileName = "cfg" } })
local Tab = Window:CreateTab("Main", "zap")
Tab:CreateSection("Fields")
Window:FinishLoading()
sandbox.advance(1.5)
local host = Window._popover

-- ======================================================================================
section("Input: v1 contract")
local calls = {}
local input = Tab:CreateInput({ Flag = "CB_Input", Name = "Input", Callback = function(v) calls[#calls + 1] = v end })
check("type and default name", input.Type == "Input" and input.Name == "Input")
check("CurrentValue defaults to empty", input.CurrentValue == "")
check("Set returns self", input:Set("hello") == input)
check("Set stores and fires once", input.CurrentValue == "hello" and #calls == 1 and calls[1] == "hello", #calls)
input:Set("hello")
check("an unchanged Set does not fire", #calls == 1, #calls)
input:Set("quiet", true)
check("a silent Set stores without firing", input.CurrentValue == "quiet" and #calls == 1)
local box = input._box or (input.Root and input._box)
check("mounting gives a TextBox in a Field", box ~= nil and box.ClassName == "TextBox" and box.Parent.Name == "Field")
check("placeholder is the v1 default", box.PlaceholderText == "Enter value...", box.PlaceholderText)
check("Input instance budget <= 7 (Root, Divider, Title, Field, corner, stroke, TextBox)", budget(Tab:CreateInput({ Name = "Budget" })) <= 7,
	budget(Tab:CreateInput({ Name = "Budget2" })))
local field = input._field
local stroke = field:FindFirstChildOfClass("UIStroke")
check("the field is a Well with a 1 px Border stroke", field.BackgroundColor3 == Argon.Palette.Well and stroke ~= nil and stroke.Thickness == 1
	and stroke.Color == Argon.Palette.Border)
check("the field is 32 tall at default density", field.Size.Y.Offset == 32, field.Size.Y.Offset)

calls = {}
sandbox.input.typeText(box, "typed", false)
check("blur commits a changed text", input.CurrentValue == "typed" and #calls == 1 and calls[1] == "typed", #calls)
sandbox.input.typeText(box, "typed", false)
check("blur without a change does not fire", #calls == 1, #calls)
sandbox.input.typeText(box, "typed", true)
check("Enter fires even when unchanged", #calls == 2 and calls[2] == "typed", #calls)
check("focus shows the real text", (function()
	box:CaptureFocus()
	local text = box.Text
	box:ReleaseFocus(false)
	return text == "typed", text
end)())

section("Input: RemoveTextAfterFocusLost (D13)")
local cmdCalls = {}
local cmd = Tab:CreateInput({ Flag = "CB_Cmd", Name = "Command", RemoveTextAfterFocusLost = true, Callback = function(v) cmdCalls[#cmdCalls + 1] = v end })
local cmdBox = cmd.Root and cmd._box
sandbox.input.typeText(cmdBox, "fly", true)
check("the callback fires once with the text", #cmdCalls == 1 and cmdCalls[1] == "fly", #cmdCalls)
check("CurrentValue keeps the submitted text", cmd.CurrentValue == "fly", cmd.CurrentValue)
check("the box is cleared", cmdBox.Text == "", cmdBox.Text)
sandbox.input.typeText(cmdBox, "", false)
check("an empty blur fires nothing", #cmdCalls == 1, #cmdCalls)
sandbox.input.typeText(cmdBox, "fly", false)
check("the same command again fires again", #cmdCalls == 2 and cmdCalls[2] == "fly" and cmdBox.Text == "", #cmdCalls)
Argon:SaveConfiguration()
local savedCfg = sandbox.decodeJson(sandbox.files["CB/cfg.rfld"])
check("the submitted text is what persists", savedCfg.CB_Cmd == "fly", tostring(savedCfg.CB_Cmd))
check("Input persists as a string", savedCfg.CB_Input == "typed", tostring(savedCfg.CB_Input))

section("Input: elision while unfocused")
local longUrl = "https://discord.com/api/webhooks/1523331338155982949/RvztQ8kLmNoPqRsTuVwXyZ0123456789abcdef"
local url = Tab:CreateInput({ Flag = "CB_Url", Name = "Webhook", CurrentValue = longUrl })
local urlBox = find(url.Root, function(child) return child.ClassName == "TextBox" end)
check("elided: first 24 + ellipsis + last 10, no scheme", urlBox.Text == "discord.com/api/webhooks\u{2026}6789abcdef", urlBox.Text)
urlBox.Focused:Fire()
check("Focused restores the full text", urlBox.Text == longUrl)
urlBox.Text = "https://example.com/a/very/long/path/that/should/also/be/elided/for/display"
urlBox.FocusLost:Fire(true)
check("FocusLost commits and re-elides", url.CurrentValue:sub(1, 19) == "https://example.com" and urlBox.Text ~= url.CurrentValue, urlBox.Text)
url:Set("https://a.co")
check("a short value drops only the scheme", urlBox.Text == "a.co", urlBox.Text)
url:Set(("x"):rep(38))
check("38 characters are shown in full", urlBox.Text == ("x"):rep(38))
url:Set("quiet", true)
check("Set(silent) updates the display", urlBox.Text == "quiet")
local wide = Tab:CreateInput({ Name = "Wide", CurrentValue = ("\u{0161}"):rep(45) })
check("elision counts characters, not bytes", wide.Root and utf8.len(wide._box.Text) == 35, wide._box.Text)

section("Input: Numeric, MaxLength, Validate")
local numCalls = {}
local num = Tab:CreateInput({ Name = "FOV", Numeric = true, Min = 16, Max = 120, CurrentValue = 70, Callback = function(v) numCalls[#numCalls + 1] = v end })
local numBox = num.Root and num._box
check("numeric CurrentValue is a string", num.CurrentValue == "70")
numBox:CaptureFocus()
numBox.Text = "12"
numBox.Text = "12a"
check("non-numeric keystrokes are rejected", numBox.Text == "12", numBox.Text)
numBox:ReleaseFocus(true)
check("commit clamps to Min", num.CurrentValue == "16" and numCalls[#numCalls] == "16", num.CurrentValue)
local message = num._msg
check("the range message shows", message ~= nil and message.Visible and message.Text == "Must be between 16 and 120", message and message.Text)
check("the row grows for the message", num.Root.Size.Y.Offset == 44 + 14, num.Root.Size.Y.Offset)
sandbox.advance(2.2)
check("the hint clears after 2 s", not message.Visible and num.Root.Size.Y.Offset == 44)
sandbox.input.typeText(numBox, "500", true)
check("commit clamps to Max", num.CurrentValue == "120", num.CurrentValue)
num:Set("abc")
check("Set rejects non-numbers", num.CurrentValue == "120")
num:Set(5)
check("Set clamps numbers", num.CurrentValue == "16")
sandbox.input.typeText(numBox, "-", true)
check("an incomplete number reverts with a hint", num.CurrentValue == "16" and num._msg.Text == "Enter a number" and numBox.Text == "16", num._msg.Text)

local short = Tab:CreateInput({ Name = "Tag", MaxLength = 5 })
local shortBox = short.Root and short._box
shortBox:CaptureFocus()
shortBox.Text = "abcdefgh"
check("MaxLength truncates while typing", shortBox.Text == "abcde", shortBox.Text)
local counter = short._counter
check("the counter shows n/max in mono and Warning at 90 %", counter and counter.Visible and counter.Text == "5/5"
	and counter.TextColor3 == Argon.Palette.Warning, counter and counter.Text)
shortBox:ReleaseFocus(true)
check("MaxLength commit", short.CurrentValue == "abcde")
short:Set("123456789")
check("Set truncates to MaxLength", short.CurrentValue == "12345")

local validCalls = 0
local hook = Tab:CreateInput({ Name = "Hook", Validate = function(text)
	if text:sub(1, 8) ~= "https://" then return false, "Must start with https://" end
	return true
end, Callback = function() validCalls += 1 end })
local hookBox = hook.Root and hook._box
sandbox.input.typeText(hookBox, "http://x", true)
check("an invalid value is not committed", hook.CurrentValue == "" and validCalls == 0)
check("invalid: Danger stroke and the message line", hook._stroke.Color == Argon.Palette.Danger and hook._msg.Visible
	and hook._msg.Text == "Must start with https://" and hook._msg.TextColor3 == Argon.Palette.Danger)
check("the invalid text stays (shown elided while unfocused)", hook._bad == "http://x" and hookBox.Text == "x", hookBox.Text)
hookBox:CaptureFocus()
check("refocusing gives back the invalid text to fix", hookBox.Text == "http://x", hookBox.Text)
hookBox.Text = "https://x"
check("editing clears the error", not hook._msg.Visible)
hookBox:ReleaseFocus(true)
check("a valid value commits", hook.CurrentValue == "https://x" and validCalls == 1)

section("Input: Live, ClearButton, Icon, Masked, ReadOnly")
local live = Tab:CreateInput({ Name = "Search", Live = true })
local liveSeen = {}
live:OnChanged(function(value, source) liveSeen[#liveSeen + 1] = { value, source } end)
local liveBox = live.Root and live._box
liveBox:CaptureFocus()
liveBox.Text = "a"
sandbox.advance(0.1)
liveBox.Text = "ab"
sandbox.advance(0.1)
check("Live is debounced (nothing within 0.2 s)", #liveSeen == 0, #liveSeen)
sandbox.advance(0.15)
check("Live fires OnChanged once with the draft", #liveSeen == 1 and liveSeen[1][1] == "ab" and liveSeen[1][2] == "live", #liveSeen)
check("Live does not commit", live.CurrentValue == "")
liveBox:ReleaseFocus(false)
check("blur commits after Live", live.CurrentValue == "ab")

local clearCalls = {}
local clearable = Tab:CreateInput({ Name = "Clearable", CurrentValue = "abc", Callback = function(v) clearCalls[#clearCalls + 1] = v end })
local clearButton = clearable.Root and named(clearable.Root, "Clear")
check("the clear button shows when there is text", clearButton ~= nil and clearButton.Visible)
sandbox.input.click(clearButton)
check("clear runs Set(\"\") as a change", clearable.CurrentValue == "" and clearCalls[1] == "" and not clearButton.Visible)
local noClear = Tab:CreateInput({ Name = "No clear", CurrentValue = "abc", ClearButton = false })
check("ClearButton = false has no button", noClear.Root and named(noClear.Root, "Clear") == nil)

local iconInput = Tab:CreateInput({ Name = "With icon", Icon = "search" })
check("Icon adds a leading 16 px icon and shifts the box", iconInput.Root and named(iconInput.Root, "Icon", "ImageLabel") ~= nil
	and iconInput._box.Position.X.Offset == 32)

local maskedCalls = {}
local masked = Tab:CreateInput({ Name = "Password", Masked = true, CurrentValue = "secret", Callback = function(v) maskedCalls[#maskedCalls + 1] = v end })
local maskedBox = masked.Root and masked._box
check("Masked shows bullets while unfocused", maskedBox.Text == ("\u{2022}"):rep(6), maskedBox.Text)
maskedBox:CaptureFocus()
check("Masked keeps bullets while focused", maskedBox.Text == ("\u{2022}"):rep(6))
maskedBox.CursorPosition = #maskedBox.Text + 1
maskedBox.Text = ("\u{2022}"):rep(6) .. "X"
check("typing appends to the real text", masked._draft == "secretX" and maskedBox.Text == ("\u{2022}"):rep(7), masked._draft)
maskedBox.CursorPosition = 3 * 3 + 1
maskedBox.Text = ("\u{2022}"):rep(6)
check("backspace in the middle removes the character before the caret", masked._draft == "secetX", masked._draft)
maskedBox:ReleaseFocus(true)
check("the masked commit carries the real text", maskedCalls[1] == masked.CurrentValue and masked.CurrentValue ~= maskedBox.Text)

local ro = Tab:CreateInput({ Name = "Id", ReadOnly = true, CurrentValue = "12345" })
check("ReadOnly: not editable, copy instead of clear, BorderSoft stroke", ro.Root and ro._box.TextEditable == false
	and named(ro.Root, "Copy") ~= nil and named(ro.Root, "Clear") == nil and ro._stroke.Color == Argon.Palette.BorderSoft)
sandbox.input.click(named(ro.Root, "Copy"))
check("copy puts the value on the clipboard", sandbox.clipboard == "12345", tostring(sandbox.clipboard))

section("Input: focus, touch and lock")
local focusInput = Tab:CreateInput({ Name = "Focusable" })
local focusBox = focusInput.Root and focusInput._box
focusInput._spec.focus.activate(focusInput)
check("keyboard activation focuses the box", sandbox.focusedTextBox == focusBox)
focusBox:ReleaseFocus(false)
lastInput("touch")
focusInput._spec.focus.activate(focusInput)
sandbox.input.click(focusInput.Root)
check("touch never auto-focuses", sandbox.focusedTextBox == nil)
lastInput("mouse")
sandbox.input.click(focusInput.Root)
check("a mouse click on the row focuses the box", sandbox.focusedTextBox == focusBox)
focusBox:ReleaseFocus(false)
focusInput:Lock("Premium")
focusBox:CaptureFocus()
focusBox.Text = "nope"
focusBox:ReleaseFocus(true)
check("a locked input ignores typing", focusInput.CurrentValue == "" and focusBox.TextEditable == false)
focusInput:Set("api")
check("programmatic Set still works while locked", focusInput.CurrentValue == "api" and focusBox.Text == "api")
focusInput:Unlock()
focusInput.Root.MouseEnter:Fire()
check("hover: Track stroke", focusInput._stroke.Color == Argon.Palette.Track)
focusInput.Root.MouseLeave:Fire()
check("rest: Border stroke", focusInput._stroke.Color == Argon.Palette.Border)
focusBox:CaptureFocus()
check("focus: Focus stroke and the title tints AccentText", focusInput._stroke.Color == Argon.Palette.Focus
	and focusInput._view.Title.TextColor3 == Argon.Palette.AccentText)
check("focus: the soft glow (slot 1) is on the field", Window._glow.slots[1] and Window._glow.slots[1].owner == focusInput
	and Window._glow.slots[1].image.Visible)
check("no enter cap while clean", named(focusInput.Root, "EnterCap") == nil or not named(focusInput.Root, "EnterCap").Visible)
focusBox.Text = "dirty"
check("the enter cap shows while dirty", named(focusInput.Root, "EnterCap") ~= nil and named(focusInput.Root, "EnterCap").Visible)
focusBox:ReleaseFocus(false)
check("blur: the cap hides and the title returns to Text", not named(focusInput.Root, "EnterCap").Visible
	and focusInput._view.Title.TextColor3 == Argon.Palette.Text)
check("blur releases the glow", Window._glow.slots[1].owner == nil and not Window._glow.slots[1].image.Visible)
check("change tracking: IsChanged and Reset", (function()
	local changed = focusInput:IsChanged()
	focusInput:Reset()
	return changed and focusInput.CurrentValue == "" and not focusInput:IsChanged()
end)())
focusBox:CaptureFocus()
focusBox.Text = "mid-edit"
focusInput:SetDisabled(true)
focusBox:ReleaseFocus(true)
check("disabling mid-edit discards the draft", focusInput.CurrentValue == "" and focusBox.Text == "")
focusInput:SetDisabled(false)
check("describe for the menu header", focusInput._spec.describe(focusInput, "") == "empty" and masked._spec.describe(masked, "x") == "hidden")
local plain = Tab:CreateInput({ Name = "Plain", Elide = false, CurrentValue = longUrl })
check("Elide = false shows the whole value", plain.Root and plain._box.Text == longUrl)

-- ======================================================================================
section("TextArea")
local areaCalls = {}
local area = Tab:CreateTextArea({ Flag = "CB_Area", Callback = function(v) areaCalls[#areaCalls + 1] = v end })
check("default name Notes, empty value", area.Name == "Notes" and area.CurrentValue == "" and area.Type == "TextArea")
check("Set returns self", area:Set("alpha\nbeta\n\ngamma") == area)
local lines = area:GetLines()
check("GetLines skips blank lines (v1)", #lines == 3 and lines[1] == "alpha" and lines[3] == "gamma", #lines)
check("GetLines(true) keeps them", #area:GetLines(true) == 4)
area:Set("a\r\n  \nb")
check("GetLines drops \\r and whitespace-only lines", (function()
	local list = area:GetLines()
	return #list == 2 and list[1] == "a" and list[2] == "b"
end)())
local areaBox = area.Root and area._box
check("a multi-line TextBox inside a Well ScrollingFrame", areaBox.MultiLine == true and areaBox.Parent.ClassName == "ScrollingFrame"
	and areaBox.Parent.Name == "Field" and areaBox.Parent.BackgroundColor3 == Argon.Palette.Well)
check("placeholder default", areaBox.PlaceholderText == "Enter text...")
check("TextArea instance budget <= 8", budget(Tab:CreateTextArea({ Name = "Budget area" })) <= 8)
local band = area._view.band
check("it stacks under its label", area._field.Position.Y.Offset == band and area._field.Size.X.Scale == 1)
check("default field height 104", area._field.Size.Y.Offset == 104, area._field.Size.Y.Offset)
check("Height is clamped to 72-320", (function()
	local lo = Tab:CreateTextArea({ Name = "Lo", Height = 10 })
	local hi = Tab:CreateTextArea({ Name = "Hi", Height = 1000 })
	return lo.Root and lo._field.Size.Y.Offset == 72 and hi.Root and hi._field.Size.Y.Offset == 320
end)())
areaCalls = {}
sandbox.input.typeText(areaBox, "one\ntwo", false)
check("commits on focus loss", area.CurrentValue == "one\ntwo" and #areaCalls == 1 and areaCalls[1] == "one\ntwo", #areaCalls)
areaBox:CaptureFocus()
areaBox.Text = "typing"
check("no commit while typing", area.CurrentValue == "one\ntwo")
area:Set("from script")
check("a Set while typing keeps the user's draft", areaBox.Text == "typing" and area.CurrentValue == "from script")
areaBox:ReleaseFocus(false)
check("the draft commits on blur", area.CurrentValue == "typing")
local grow = Tab:CreateTextArea({ Name = "Grow", AutoGrow = true })
check("AutoGrow starts at MinHeight 80", grow.Root and grow._field.Size.Y.Offset == 80, grow._field.Size.Y.Offset)
grow:Set(("line\n"):rep(5))
local mid = grow._field.Size.Y.Offset
check("AutoGrow grows with the text", mid > 80 and mid < 240, mid)
grow:Set(("line\n"):rep(40))
check("AutoGrow stops at MaxHeight 240", grow._field.Size.Y.Offset == 240)
check("the row grows with the field", grow.Root.Size.Y.Offset == grow._view.band + 240 + 10, grow.Root.Size.Y.Offset)
local mono = Tab:CreateTextArea({ Name = "Script", Monospace = true })
check("Monospace uses the mono face", mono.Root and tostring(mono._box.FontFace.Family):find("Mono") ~= nil, tostring(mono._box.FontFace.Family))
check("the body face otherwise (no mono body)", tostring(areaBox.FontFace.Family):find("Mono") == nil)
local capped = Tab:CreateTextArea({ Name = "Capped", MaxLength = 10 })
local cappedBox = capped.Root and capped._box
cappedBox:CaptureFocus()
cappedBox.Text = "0123456789abc"
check("MaxLength truncates while typing", cappedBox.Text == "0123456789")
check("the counter sits in the label band", capped._counter and capped._counter.Text == "10/10" and capped._counter.Parent == capped.Root)
cappedBox:ReleaseFocus(false)
area:SetDesc("Shown under the field")
check("the description sits under the field", area._view.Description.Position.Y.Offset >= band + area._field.Size.Y.Offset)
local liveArea = Tab:CreateTextArea({ Name = "Live notes", Live = true })
local liveAreaSeen = {}
liveArea:OnChanged(function(value, source) liveAreaSeen[#liveAreaSeen + 1] = source end)
local liveAreaBox = liveArea.Root and liveArea._box
liveAreaBox:CaptureFocus()
liveAreaBox.Text = "x"
sandbox.advance(0.25)
check("TextArea Live fires OnChanged (debounced) without committing", #liveAreaSeen == 1 and liveAreaSeen[1] == "live" and liveArea.CurrentValue == "")
liveAreaBox:ReleaseFocus(false)
area:Lock()
areaBox:CaptureFocus()
check("a locked TextArea refuses focus", sandbox.focusedTextBox ~= areaBox and areaBox.TextEditable == false)
area:Unlock()
Argon:SaveConfiguration()
check("TextArea persists as a string", sandbox.decodeJson(sandbox.files["CB/cfg.rfld"]).CB_Area == "typing")

-- ======================================================================================
section("Dropdown: v1 contract and D12")
local ddCalls = {}
local dd = Tab:CreateDropdown({ Flag = "CB_DD", Name = "Mode", Options = { "A", "B", "C" }, CurrentOption = { "A" },
	Callback = function(v) ddCalls[#ddCalls + 1] = v end })
check("CurrentValue is the same table as CurrentOption", rawequal(dd.CurrentValue, dd.CurrentOption) and dd.CurrentOption[1] == "A")
check("Options is kept", #dd.Options == 3)
check("Set returns self", dd:Set({ "B" }) == dd)
check("Set selects and the callback gets a copy", dd.CurrentOption[1] == "B" and #ddCalls == 1 and ddCalls[1][1] == "B"
	and not rawequal(ddCalls[1], dd.CurrentOption))
check("CurrentValue stays the same table as CurrentOption", rawequal(dd.CurrentValue, dd.CurrentOption))
dd:Set("C")
check("a string Set works", dd.CurrentOption[1] == "C" and #dd.CurrentOption == 1)
dd:Set({ "A", "B" })
check("single select keeps the first match", #dd.CurrentOption == 1 and dd.CurrentOption[1] == "A")
local before = #ddCalls
dd:Set({ "Z" })
check("Set(unknown) keeps the selection and fires nothing", dd.CurrentOption[1] == "A" and #ddCalls == before)
check("the request is remembered as _desiredOption", dd._desiredOption[1] == "Z")
check("a flagged unmatched request is parked as pending", type(Argon._pendingFlags.CB_DD) == "table" and Argon._pendingFlags.CB_DD[1] == "Z")
dd:Set({ "B" }, true)
check("a silent Set fires nothing", dd.CurrentOption[1] == "B" and #ddCalls == before)
check("GetSelected returns a copy", (function()
	local copy = dd:GetSelected()
	return copy[1] == "B" and not rawequal(copy, dd.CurrentOption)
end)())
local flagSeen = {}
local unbind = Argon:OnFlagChanged(function(flag, value) if flag == "CB_DD" then flagSeen[#flagSeen + 1] = value end end)
before = #ddCalls
check("Refresh returns self", dd:Refresh({ "B", "D" }) == dd)
check("Refresh keeps a surviving selection silently", dd.CurrentOption[1] == "B" and #ddCalls == before and #flagSeen == 0)
dd:Set({ "D" })
dd:Refresh({ "X", "Y" })
check("a dropped selection fires nothing", #dd.CurrentOption == 0 and #ddCalls == before + 1 and #flagSeen == 1, #flagSeen)
dd:Refresh({ "D", "X" })
check("the remembered selection comes back with its option", dd.CurrentOption[1] == "D")
check("...through the commit path: callback and listener once", #ddCalls == before + 2 and #flagSeen == 2, #flagSeen)
check("SetOptions is an alias of Refresh", dd.SetOptions == dd.Refresh)
dd:SetOptions({ "D", "E" }, false)
check("Refresh(..., false) drops the selection", #dd.CurrentOption == 0)
unbind()
dd._spec.focus.adjust(dd, 1)
check("Right on the closed trigger steps the option", dd.CurrentOption[1] == "D")
dd._spec.focus.adjust(dd, math.huge)
check("End picks the last option", dd.CurrentOption[1] == "E")

local dynamicValue
local dynamic = Tab:CreateDropdown({ Flag = "CB_Dynamic", Name = "Dynamic", Options = {}, Callback = function(s) dynamicValue = s[1] end })
dynamic:Set({ "Later" })
check("selection deferred while the option is missing (v1)", dynamic.CurrentOption[1] == nil and Argon._pendingFlags.CB_Dynamic ~= nil)
dynamic:Refresh({ "Later", "Other" })
check("selection applied after Refresh and the callback fired (v1)", dynamic.CurrentOption[1] == "Later" and dynamicValue == "Later")
check("the parked request is cleared once applied", Argon._pendingFlags.CB_Dynamic == nil)

section("Dropdown: multi select and trigger")
local multiCalls = {}
local multi = Tab:CreateDropdown({ Flag = "CB_Multi", Name = "Targets", Options = { "A", "B", "C", "D" }, MultipleOptions = true,
	CurrentOption = { "A", "Z", "C" }, Callback = function(v) multiCalls[#multiCalls + 1] = v end })
check("multi keeps every known value", #multi.CurrentOption == 2 and multi.CurrentOption[1] == "A" and multi.CurrentOption[2] == "C")
multi:Set({ "B", "B", "D" })
check("multi Set drops duplicates", #multi.CurrentOption == 2 and multi.CurrentOption[2] == "D")
Argon:SaveConfiguration()
local savedMulti = sandbox.decodeJson(sandbox.files["CB/cfg.rfld"]).CB_Multi
check("Dropdown persists as a JSON array", type(savedMulti) == "table" and savedMulti[1] == "B" and savedMulti[2] == "D")
multi:Set({ "A", "B", "C", "D" })
local multiField = multi.Root and multi._field
local chipCount, firstChip = 0, nil
for _, child in ipairs(multiField:GetChildren()) do
	if child.Name == "Chip" and child.Visible then
		chipCount += 1
		firstChip = firstChip or child
	end
end
local more = named(multiField, "More")
check("multi shows MaxVisibleChips (2) chips plus +N", chipCount == 2 and more and more.Visible and more.Text == "+2", chipCount)
sandbox.input.click(named(firstChip, "Remove"))
check("a chip's x removes that option", #multi.CurrentOption == 3 and multi.CurrentOption[1] == "B" and #multiCalls >= 1)
local single = Tab:CreateDropdown({ Name = "Single", Options = { "A", "B" }, CurrentOption = "B" })
check("the trigger shows the value in Text", single.Root and single._value.Text == "B" and single._value.TextColor3 == Argon.Palette.Text)
local emptyDD = Tab:CreateDropdown({ Name = "Empty", Options = { "A" } })
check("an empty trigger shows Select… in Dim", emptyDD.Root and emptyDD._value.Text == "Select\u{2026}" and emptyDD._value.TextColor3 == Argon.Palette.Dim)
check("the trigger has a chevrons-up-down chevron", named(emptyDD.Root, "Chevron", "ImageLabel") ~= nil)
check("Dropdown instance budget <= 8 (closed)", budget(emptyDD) <= 8, budget(emptyDD))
local rich = Tab:CreateDropdown({ Name = "Rich", Options = { { Text = "Fly", Description = "Move freely", Icon = "zap" }, { Divider = true },
	{ Text = "Walk" }, { Text = "Off", Disabled = true } } })
rich:Set({ Text = "Walk" })
check("rich options: CurrentOption holds text", rich.CurrentOption[1] == "Walk")
check("_searchOptions returns the option texts", table.concat(rich:_searchOptions(), ",") == "Fly,Walk,Off")

section("Dropdown: panel")
local opts = {}
for index = 1, 10 do opts[index] = "Option " .. index end
local pickCalls = {}
local list = Tab:CreateDropdown({ Name = "List", Options = opts, Callback = function(v) pickCalls[#pickCalls + 1] = v[1] end })
local listField = list.Root and list._field
local c0 = created()
sandbox.input.click(list.Root)
local firstCost = created() - c0
check("a click opens the pooled popover", host:isOpen(list) and list:IsOpen())
check("first open in the window creates <= 60 instances", firstCost <= 60, firstCost)
local p = list._panel
check("searchable automatically above 8 options", p.searchable and p.search.Visible)
check("the search box is focused on mouse", sandbox.focusedTextBox == p.box)
check("the search placeholder counts options", p.box.PlaceholderText == "Filter 10 options", p.box.PlaceholderText)
check("panel width is max(trigger, 240)", host.panel.Size.X.Offset == math.max(listField.AbsoluteSize.X, 240), host.panel.Size.X.Offset)
check("panel height at most 360", host.panel.Size.Y.Offset <= 360, host.panel.Size.Y.Offset)
check("open: Focus stroke and Text chevron", list._stroke.Color == Argon.Palette.Focus and list._chevron.ImageColor3 == Argon.Palette.Text)
check("rows are 32 px", p.list.rows[1].Root.Size.Y.Offset == 32)
check("the pool holds visible + 2 rows at most", p.list:liveRows() <= 12, p.list:liveRows())
p.box.Text = "Option 1"
check("typing filters", #p.shown == 2, #p.shown)
p.box.Text = "flyy"
check("empty filter state with Clear filter", #p.shown == 0 and p.empty.Visible and p.empty.Text == "No options match 'flyy'" and p.emptyClear.Visible)
sandbox.input.click(p.emptyClear)
check("Clear filter restores the list", p.box.Text == "" and #p.shown == 10 and not p.empty.Visible)
sandbox.input.press("Down")
sandbox.input.press("Down")
check("Down moves the highlight while typing in search", p.hi == 3, p.hi)
check("the keyboard highlight uses Active", p.hiFrame.Visible and p.hiFrame.BackgroundColor3 == Argon.Palette.Active)
p.box:ReleaseFocus(true)
check("Enter in search picks the highlighted option and closes (single)", list.CurrentOption[1] == "Option 3" and pickCalls[1] == "Option 3"
	and not host:isOpen(list) and not list:IsOpen())
check("closed: the stroke and chevron are back", list._stroke.Color == Argon.Palette.Border and list._chevron.ImageColor3 == Argon.Palette.Text2)
local c1 = created()
sandbox.input.click(list.Root)
check("reopen creates 0 instances", created() - c1 == 0, created() - c1)
check("reopen highlights the selected option", p.hi == 3 and p.selected["Option 3"])
p.box:ReleaseFocus(false)
check("the panel stays open on a plain blur", host:isOpen(list))
sandbox.input.press("End")
check("End goes to the last option", p.hi == 10)
sandbox.input.press("Home")
check("Home goes to the first option", p.hi == 1)
sandbox.input.press("Down")
sandbox.input.press("Return")
check("Enter selects (keyboard, not typing)", list.CurrentOption[1] == "Option 2" and not host:isOpen(list))
sandbox.input.click(list.Root)
sandbox.input.press("Backspace")
check("Backspace with an empty filter closes", not host:isOpen(list))
sandbox.input.click(list.Root)
p.box:ReleaseFocus(false)
sandbox.input.press("Backspace")
check("the close key closes the panel", not host:isOpen(list))
sandbox.input.click(list.Root)
sandbox.input.click(host.catcher)
check("an outside click closes the panel", not host:isOpen(list))
sandbox.input.click(list.Root)
sandbox.input.click(list.Root)
check("a click on the trigger toggles it closed", not host:isOpen(list))
sandbox.input.click(list.Root)
sandbox.input.click(p.list:rowFor(5).Root)
check("clicking an option selects it and closes", list.CurrentOption[1] == "Option 5" and not host:isOpen(list))

local manyCalls = {}
local many = Tab:CreateDropdown({ Name = "Many", Options = { "A", "B", "C" }, MultipleOptions = true, Callback = function(v) manyCalls[#manyCalls + 1] = v end })
sandbox.input.click(many.Root)
check("multi panel header counts the selection", p.count.Visible and p.count.Text == "0 of 3 selected" and p.all.Visible and p.clear.Visible)
check("3 options: no search box", not p.search.Visible and sandbox.focusedTextBox == nil)
local squareIcon = Argon:GetIcon("square")
check("multi rows draw a checkbox", p.list:rowFor(1).check.Visible and p.list:rowFor(1).check.ImageRectOffset == squareIcon.ImageRectOffset)
sandbox.input.click(p.list:rowFor(2).Root)
check("clicking toggles and stays open (multi)", many.CurrentOption[1] == "B" and host:isOpen(many) and p.count.Text == "1 of 3 selected")
check("the checked row shows square-check in Accent", p.list:rowFor(2).check.ImageRectOffset == Argon:GetIcon("square-check").ImageRectOffset
	and p.list:rowFor(2).check.ImageColor3 == Argon.Palette.Accent)
sandbox.input.click(p.all)
check("Select all", #many.CurrentOption == 3 and p.count.Text == "3 of 3 selected")
sandbox.input.click(p.clear)
check("Clear", #many.CurrentOption == 0)
sandbox.input.press("Home")
sandbox.input.press("Down")
sandbox.input.press("Space")
check("Space toggles the highlighted option (multi)", many.CurrentOption[1] == "B", tostring(many.CurrentOption[1]))
sandbox.input.press("Space")
check("Space again untoggles it", #many.CurrentOption == 0)
host:close("test")

sandbox.input.click(rich.Root)
local fly = p.list:rowFor(1)
check("rich rows: description and icon, rows grow to 48", fly.desc and fly.desc.Visible and fly.desc.Text == "Move freely" and fly.icon
	and fly.icon.Visible and fly.Root.Size.Y.Offset == 48)
check("a Divider entry draws a rule above the next option", p.list:rowFor(2).rule and p.list:rowFor(2).rule.Visible)
local offRow = p.list:rowFor(3)
check("a disabled option is drawn Disabled", offRow.label.TextColor3 == Argon.Palette.Disabled)
sandbox.input.click(offRow.Root)
check("a disabled option cannot be picked", rich.CurrentOption[1] == "Walk")
host:close("test")

lastInput("touch")
sandbox.input.click(list.Root)
check("touch: the search is never auto-focused", sandbox.focusedTextBox == nil and p.search.Visible)
check("touch: rows are 44 px", p.list.rows[1].Root.Size.Y.Offset == 44)
host:close("test")
lastInput("mouse")

sandbox.addPlayer(2001, "Alice")
local players = Tab:CreateDropdown({ Name = "Player", Source = "Players" })
check("Source = Players lists the players", table.find(players:_searchOptions(), "Alice") ~= nil and table.find(players:_searchOptions(), "TestPlayer") ~= nil)
sandbox.addPlayer(2002, "Bob")
sandbox.input.click(players.Root)
check("Source refreshes on open", table.find(players:_searchOptions(), "Bob") ~= nil and #p.shown == #players:_searchOptions())
host:close("test")

local resume
local async = Tab:CreateDropdown({ Name = "Async", CurrentOption = "Two", Options = function()
	resume = coroutine.running()
	coroutine.yield()
	return { "One", "Two" }
end })
check("Options = function keeps the requested selection until it runs", async.CurrentOption[1] == "Two")
sandbox.input.click(async.Root)
check("a spinner row shows while the options resolve", p.spin and p.spin.Visible and async._loading)
coroutine.resume(resume)
check("the options arrive and the spinner hides", not async._loading and not p.spin.Visible and #p.shown == 2 and async.CurrentOption[1] == "Two")
host:close("test")

local twenty = {}
for index = 1, 20 do twenty[index] = "Item " .. index end
local noSearch = Tab:CreateDropdown({ Name = "No search", Options = twenty, Searchable = false })
sandbox.input.click(noSearch.Root)
check("Searchable = false hides the search even above 8 options", not p.search.Visible)
sandbox.input.press("I")
sandbox.input.press("I")
check("without search, typing jumps to the next match", p.hi == 3, p.hi)
host:close("test")
local search = Tab:CreateDropdown({ Name = "Forced search", Options = { "A", "B" }, Searchable = true })
sandbox.input.click(search.Root)
check("Searchable = true shows it for 2 options", p.search.Visible)
search:Refresh({ "A", "B", "C" })
check("Refresh while open rebinds the rows and resizes", #p.shown == 3 and p.list:rowFor(3) ~= nil and p.list:rowFor(3).label.Text == "C")
host:close("test")
local teams = Tab:CreateDropdown({ Name = "Team", Source = "Teams" })
sandbox.input.click(teams.Root)
check("Source = Teams opens without a Teams service (empty list)", host:isOpen(teams) and #p.shown == 0 and p.empty.Visible and p.empty.Text == "No options")
host:close("test")
check("describe lists the selection", dd._spec.describe(dd, { "A", "B" }) == "A, B" and dd._spec.describe(dd, {}) == "none")
check("Reset restores the default selection", (function()
	local resettable = Tab:CreateDropdown({ Name = "Resettable", Options = { "A", "B" }, CurrentOption = "A" })
	resettable:Set("B")
	resettable:Reset()
	return resettable.CurrentOption[1] == "A" and not resettable:IsChanged()
end)())

local lockable = Tab:CreateDropdown({ Name = "Lockable", Options = { "A", "B" } })
sandbox.input.click(lockable.Root)
lockable:Lock("Premium")
check("Lock closes the panel", not host:isOpen(lockable))
sandbox.input.click(lockable.Root)
check("a locked dropdown does not open", not host:isOpen(lockable))
lockable:Set("B")
check("Set still works while locked", lockable.CurrentOption[1] == "B")
lockable:Unlock()
sandbox.input.click(lockable.Root)
lockable:Destroy()
check("Destroy closes its open panel", not host:isOpen(lockable) and host:openCount() == 0)

-- ======================================================================================
section("ColorPicker: v1 contract")
local colorCalls = {}
local picker = Tab:CreateColorPicker({ Flag = "CB_Color", Name = "Color", Color = Color3.fromRGB(10, 20, 30),
	Callback = function(color, alpha) colorCalls[#colorCalls + 1] = { color, alpha } end })
check("type and value", picker.Type == "ColorPicker" and hex(picker.CurrentValue) == "0A141E")
check(".Color mirrors CurrentValue (Rayfield)", picker.Color == picker.CurrentValue)
check("Set returns self", picker:Set("#5DE1EB") == picker)
check("Set parses hex (v1)", math.floor(picker.CurrentValue.R * 255 + 0.5) == 93)
check(".Color follows Set", picker.Color == picker.CurrentValue)
check("the callback gets the Color3 only", #colorCalls == 1 and env.typeof(colorCalls[1][1]) == "Color3" and colorCalls[1][2] == nil)
picker:Set("FF0000")
check("hex without #", hex(picker.CurrentValue) == "FF0000")
picker:Set("#0F0")
check("3-digit hex", hex(picker.CurrentValue) == "00FF00")
picker:Set(Color3.fromRGB(1, 2, 3))
check("a Color3", hex(picker.CurrentValue) == "010203")
picker:Set("not a colour")
check("garbage is ignored", hex(picker.CurrentValue) == "010203")
picker:Set("12, 34, 56")
check("r, g, b text", hex(picker.CurrentValue) == "0C2238")
picker:Set({ __argonColor = true, R = 1, G = 0, B = 0 })
check("an Argon colour record", hex(picker.CurrentValue) == "FF0000")
picker:Set({ R = 0, G = 0, B = 255 })
check("a Rayfield 0-255 table (D25)", hex(picker.CurrentValue) == "0000FF")
local count0 = #colorCalls
picker:Set("#0000FF")
check("an unchanged Set does not fire", #colorCalls == count0)
picker:Set("#123456", true)
check("a silent Set does not fire", #colorCalls == count0 and hex(picker.CurrentValue) == "123456")
local defaultPicker = Tab:CreateColorPicker({ Name = nil })
check("default name and colour (theme Accent)", defaultPicker.Name == "Color picker" and defaultPicker.CurrentValue == Argon.Palette.Accent)
check("the user's colour survives a theme switch (v1)", (function()
	local chosen = Color3.fromRGB(244, 114, 182)
	local mine = Tab:CreateColorPicker({ Name = "Mine", Color = chosen })
	local themes = Argon:GetThemes()
	Argon:SetTheme(themes[#themes])
	local okTheme = mine.CurrentValue == chosen
	Argon:SetTheme("Argon")
	return okTheme
end)())
local trigger = picker.Root and picker._field
check("the trigger shows the hex in mono", trigger.Text == "#123456" and tostring(trigger.FontFace.Family):find("Mono") ~= nil, trigger.Text)
check("the swatch shows the colour", hex(picker._swatch.BackgroundColor3) == "123456")
check("ColorPicker instance budget <= 7 (closed)", budget(defaultPicker) <= 7, budget(defaultPicker))
Argon:SaveConfiguration()
local savedColor = sandbox.decodeJson(sandbox.files["CB/cfg.rfld"]).CB_Color
check("persisted as {__argonColor, R, G, B} without A", savedColor.__argonColor == true and near(savedColor.B, 0x56 / 255) and savedColor.A == nil)

section("ColorPicker: alpha")
local alphaCalls = {}
local tint = Tab:CreateColorPicker({ Flag = "CB_Alpha", Name = "Tint", Alpha = true, Color = "#FF000080",
	Callback = function(color, alpha) alphaCalls[#alphaCalls + 1] = { color, alpha } end })
check("8-digit hex gives the alpha", near(tint.Alpha, 128 / 255))
tint:Set("#00FF00")
check("the callback gets (Color3, alpha)", alphaCalls[1] and near(alphaCalls[1][2], 128 / 255) and hex(alphaCalls[1][1]) == "00FF00")
tint:SetAlpha(0.25)
check("an alpha-only change commits", near(tint.Alpha, 0.25) and #alphaCalls == 2)
check("the trigger shows the alpha percent", tint.Root and tint._field.Text:find("25%%") ~= nil, tint._field.Text)
local tintChecker = named(tint._field, "Checker")
check("a checker sits under a translucent swatch", tintChecker ~= nil and tintChecker.Visible and near(tint._swatch.BackgroundTransparency, 0.75))
Argon:SaveConfiguration()
local savedTint = sandbox.decodeJson(sandbox.files["CB/cfg.rfld"]).CB_Alpha
check("persisted with A", savedTint.__argonColor == true and near(savedTint.A, 0.25) and near(savedTint.G, 1))
tint:Set({ Color = Color3.fromRGB(0, 0, 255), Alpha = 0.5 })
check("Set({Color, Alpha})", hex(tint.CurrentValue) == "0000FF" and near(tint.Alpha, 0.5))
tint:Reset()
check("Reset restores colour and alpha", hex(tint.CurrentValue) == "FF0000" and near(tint.Alpha, 128 / 255))

section("ColorPicker: panel")
sandbox.input.click(picker.Root)
check("a click opens the color popover", host:isOpen(picker))
local cp = picker._panel
local white, black = named(cp.sv, "White"), named(cp.sv, "Black")
check("SV square: hue frame with White and Black UIGradient children", white and white:FindFirstChildOfClass("UIGradient")
	and black and black:FindFirstChildOfClass("UIGradient") ~= nil)
check("the SV frame carries the hue", hex(cp.sv.BackgroundColor3) == hex(Color3.fromHSV(picker._h, 1, 1)))
check("panel width 256", host.panel.Size.X.Offset == 256, host.panel.Size.X.Offset)
check("8 presets drawn", #cp.colors >= 8 and cp.swatches[8].Visible)
check("the hex field shows the value", cp.hexBox.Text == "#123456", cp.hexBox.Text)
host:close("test")
local c2 = created()
sandbox.input.click(picker.Root)
check("reopen creates 0 instances", created() - c2 == 0, created() - c2)
local commits = {}
picker:OnChanged(function(_, source) commits[#commits + 1] = source end)
colorCalls = {}
local svAt, svSize = cp.sv.AbsolutePosition, cp.sv.AbsoluteSize
sandbox.input.drag(cp.sv, Vector2.new(svAt.X + 10, svAt.Y + 10), Vector2.new(svAt.X + svSize.X + 40, svAt.Y + 5), 4)
check("an SV drag fires the callback live, once per frame", #colorCalls >= 4, #colorCalls)
check("...and commits once on release", #commits == 1 and commits[1] == "commit", table.concat(commits, ","))
check("the drag clamps to the square", near(picker._s, 1))
check("the SV thumb follows", near(cp.svThumb.Position.X.Scale, 1))
picker:Set(Color3.fromHSV(0.6, 1, 1))
check("hue from the colour", near(picker._h, 0.6))
picker:Set("#808080")
check("a grey keeps the hue", near(picker._h, 0.6) and near(picker._s, 0))
picker:Set("#000000")
check("black keeps the hue", near(picker._h, 0.6))
local hueAt, hueSize = cp.hueBar.AbsolutePosition, cp.hueBar.AbsoluteSize
sandbox.input.drag(cp.hue, Vector2.new(hueAt.X + 1, hueAt.Y + 5), Vector2.new(hueAt.X - 30, hueAt.Y + 5), 2)
check("hue thumb stays inside [7, width - 7] (start)", cp.hueThumb.Position.X.Offset == 7, cp.hueThumb.Position.X.Offset)
sandbox.input.drag(cp.hue, Vector2.new(hueAt.X + hueSize.X - 1, hueAt.Y + 5), Vector2.new(hueAt.X + hueSize.X + 30, hueAt.Y + 5), 2)
check("hue thumb stays inside [7, width - 7] (end)", cp.hueThumb.Position.X.Offset == 232 - 7, cp.hueThumb.Position.X.Offset)
picker:Set("#FF0000")
cp.hexBox:CaptureFocus()
cp.hexBox.Text = "#00FF00"
cp.hexBox:ReleaseFocus(true)
check("hex entry applies", hex(picker.CurrentValue) == "00FF00")
cp.hexBox:CaptureFocus()
cp.hexBox.Text = "zz"
cp.hexBox:ReleaseFocus(true)
check("invalid hex: Danger stroke, value kept", hex(picker.CurrentValue) == "00FF00" and cp.hexStroke.Color == Argon.Palette.Danger)
colorCalls = {}
cp.hexBox:CaptureFocus()
cp.hexBox.Text = "#00FF00"
cp.hexBox:ReleaseFocus(false)
check("a blur without an edit commits nothing", #colorCalls == 0 and cp.hexStroke.Color == Argon.Palette.Border)
sandbox.input.click(cp.tabs.rgb)
check("the RGB tab shows 3 number fields", cp.rgb and #cp.rgb == 3 and cp.rgbWell.Visible and not cp.hexWell.Visible and cp.rgb[2].Text == "255")
cp.rgb[1].Text = "255"
cp.rgb[3].Text = "128"
cp.rgb[3].FocusLost:Fire(true)
check("RGB entry applies", hex(picker.CurrentValue) == "FFFF80", hex(picker.CurrentValue))
sandbox.input.click(cp.tabs.hex)
sandbox.input.click(cp.swatches[1])
check("a preset swatch applies and gets the ring", picker.CurrentValue == Argon.Palette.Accent and cp.ring.Visible)
local s0 = picker._s
sandbox.input.press("Left")
check("arrows move the SV thumb by 1 %", near(picker._s, math.max(0, s0 - 0.01)))
host:close("test")
check("closing with a new colour records a recent", (function()
	sandbox.input.click(defaultPicker.Root)
	local recent = cp.colors[9]
	host:close("test")
	return recent ~= nil and hex(recent) == hex(picker.CurrentValue)
end)())

section("ColorPicker: 50 opens leak nothing")
sandbox.input.click(tint.Root)
check("the alpha strip shows for Alpha pickers", cp.alpha and cp.alpha.Visible)
local alphaAt = cp.alphaBar.AbsolutePosition
sandbox.input.drag(cp.alpha, Vector2.new(alphaAt.X, alphaAt.Y + 5), Vector2.new(alphaAt.X - 50, alphaAt.Y + 5), 2)
check("alpha thumb stays inside [7, width - 7]", cp.alphaThumb.Position.X.Offset == 7 and near(tint.Alpha, 0), cp.alphaThumb.Position.X.Offset)
host:close("test")
sandbox.input.click(picker.Root)
check("the alpha strip hides for plain pickers", not cp.alpha.Visible)
host:close("test")
local handlersBefore = sandbox.metrics().handlers
local svHandlers = sandbox.handlerCount(cp.sv.InputBegan)
local consumers = Argon:GetPerfStats().globalHandlers
local c3 = created()
for _ = 1, 50 do
	sandbox.input.click(picker.Root)
	sandbox.input.click(picker.Root)
end
local handlersAfter = sandbox.metrics().handlers
check("50 opens create no instances", created() - c3 == 0, created() - c3)
check("50 opens add no UserInputService or Heartbeat handlers", handlersAfter.InputBegan == handlersBefore.InputBegan
	and handlersAfter.InputChanged == handlersBefore.InputChanged and handlersAfter.InputEnded == handlersBefore.InputEnded
	and handlersAfter.Heartbeat == handlersBefore.Heartbeat)
check("50 opens add no pooled-part connections", sandbox.handlerCount(cp.sv.InputBegan) == svHandlers)
check("no drag sessions left", Argon:GetPerfStats().dragSessions == 0 and consumers.InputChanged == 0)
check("copy and paste between pickers", (function()
	local target = Tab:CreateColorPicker({ Name = "Target", Color = "#000000" })
	Window:_copy(picker:_copyText(), picker)
	target:_paste()
	return hex(target.CurrentValue) == hex(picker.CurrentValue) and picker:_copyText() == "#" .. hex(picker.CurrentValue)
end)())
check("alpha survives copy and paste", (function()
	local other = Tab:CreateColorPicker({ Name = "Other", Alpha = true, Color = "#000000" })
	Window:_copy(tint:_copyText(), tint)
	other:_paste()
	return near(other.Alpha, tint.Alpha) and hex(other.CurrentValue) == hex(tint.CurrentValue)
end)())
picker:Lock("Premium")
sandbox.input.click(picker.Root)
check("a locked picker does not open", not host:isOpen(picker))
picker:Set("#010101")
check("Set works while locked", hex(picker.CurrentValue) == "010101")
picker:Unlock()
sandbox.input.click(picker.Root)
picker:Destroy()
check("Destroy closes its open panel", host:openCount() == 0)

-- ======================================================================================
-- Fresh windows (CreateWindow resets the flag store, so these run last).
section("Dropdown: cost does not grow with the option count")
local function firstOpen(n, name)
	local window = Argon:CreateWindow({ Name = name, GuiName = name })
	local tab = window:CreateTab("Main", "zap")
	tab:CreateSection("S")
	window:FinishLoading()
	sandbox.advance(1.5)
	local options = table.create(n)
	for index = 1, n do options[index] = "Option " .. index end
	local started = os.clock()
	local dropdown = tab:CreateDropdown({ Name = "D", Options = options })
	local createMs = (os.clock() - started) * 1000
	local _ = dropdown.Root
	local before0 = created()
	sandbox.input.click(dropdown.Root)
	local cost = created() - before0
	local panel = dropdown._panel
	panel.list.scroller.CanvasPosition = Vector2.new(0, 32 * math.floor(n / 2))
	local scrolled = created() - before0 - cost
	window._popover:close("test")
	local before1 = created()
	sandbox.input.click(dropdown.Root)
	local reopen = created() - before1
	window._popover:close("test")
	return cost, reopen, scrolled, createMs, panel.list:liveRows()
end
local cost10, reopen10, _, _, rows10 = firstOpen(10, "CB10")
local cost10k, reopen10k, scrolled10k, ms10k, rows10k = firstOpen(10000, "CB10k")
print(("  info  first open: 10 options %d instances (%d rows); 10,000 options %d instances (%d rows); create %.1f ms")
	:format(cost10, rows10, cost10k, rows10k, ms10k))
check("first open of 10 options <= 60 instances", cost10 <= 60, cost10)
check("first open of 10,000 options <= 60 instances", cost10k <= 60, cost10k)
check("10,000 options cost what 10 do (same pool, within the 2-row overscan)", cost10k - cost10 <= 6 and rows10k - rows10 <= 2,
	("%d vs %d instances, %d vs %d rows"):format(cost10k, cost10, rows10k, rows10))
check("scrolling 10,000 options creates nothing", scrolled10k == 0, scrolled10k)
check("reopen creates 0 instances", reopen10 == 0 and reopen10k == 0, reopen10 .. " " .. reopen10k)
check("CreateDropdown with 10,000 options stays cheap (< 50 ms)", ms10k < 50, ("%.1f ms"):format(ms10k))
check("the color panel's first open is bounded and its reopen is free", (function()
	local window = Argon:CreateWindow({ Name = "CBColor", GuiName = "CBColor" })
	local tab = window:CreateTab("Main", "zap")
	tab:CreateSection("S")
	window:FinishLoading()
	sandbox.advance(1.5)
	local colour = tab:CreateColorPicker({ Name = "C" })
	local _ = colour.Root
	local before0 = created()
	sandbox.input.click(colour.Root)
	local first = created() - before0
	window._popover:close("test")
	local before1 = created()
	sandbox.input.click(colour.Root)
	local again = created() - before1
	window._popover:close("test")
	print(("  info  color panel first open: %d instances (incl. the shared popover base); reopen %d"):format(first, again))
	return first <= 80 and again == 0, first .. " / " .. again
end)())

section("v1 assertions (tests/run.luau lines assigned to these controls)")
local v1Window = Argon:CreateWindow({ Name = "V1", GuiName = "CBV1", ConfigurationSaving = { Enabled = true, FolderName = "CBV1", FileName = "config" } })
local v1Tab = v1Window:CreateTab("Main", "zap")
v1Tab:CreateSection("Controls")
local v1Calls = {}
local function record(name) return function(value) v1Calls[name] = value end end
local v1Input = v1Tab:CreateInput({ Flag = "T_Input", Name = "Input", Callback = record("input") })
v1Input:Set("hello")
check("L87 input stores text", v1Input.CurrentValue == "hello")
local v1Dropdown = v1Tab:CreateDropdown({ Flag = "T_Dropdown", Name = "Dropdown", Options = { "A", "B" }, CurrentOption = { "A" }, Callback = record("dropdown") })
v1Dropdown:Set({ "B" })
check("L91 dropdown selects option", v1Dropdown.CurrentOption[1] == "B")
v1Dropdown:Set({ "Z" })
check("L93 dropdown ignores unknown option", v1Dropdown.CurrentOption[1] == nil or v1Dropdown.CurrentOption[1] == "B")
local v1Picker = v1Tab:CreateColorPicker({ Flag = "T_Color", Name = "Color", Color = Color3.fromRGB(10, 20, 30), Callback = record("color") })
v1Picker:Set("#5DE1EB")
check("L101 colorpicker parses hex", math.floor(v1Picker.CurrentValue.R * 255 + 0.5) == 93)
local v1Area = v1Tab:CreateTextArea({ Flag = "T_TextArea", Name = "Notes", Callback = record("area") })
v1Area:Set("alpha\nbeta\n\ngamma")
check("L149 textarea stores text", v1Area.CurrentValue == "alpha\nbeta\n\ngamma")
local v1Lines = v1Area:GetLines()
check("L151 textarea GetLines skips blanks", #v1Lines == 3 and v1Lines[3] == "gamma")
check("L345-351 a colour picker keeps the user's colour through a theme switch", (function()
	local chosen = Color3.fromRGB(244, 114, 182)
	local mine = v1Tab:CreateColorPicker({ Name = "Mine", Color = chosen })
	Argon:SetTheme("Ocean")
	task.wait()
	local same = mine.CurrentValue == chosen
	Argon:SetTheme("Argon")
	return same
end)())
local dynamicV1
local v1Dynamic = v1Tab:CreateDropdown({ Flag = "T_Dynamic", Name = "Dynamic", Options = {}, Callback = function(selection) dynamicV1 = selection[1] end })
v1Dynamic:Set({ "Later" })
check("L731 selection deferred while option missing", v1Dynamic.CurrentOption[1] == nil)
v1Dynamic:Refresh({ "Later", "Other" })
check("L733 selection applied after Refresh", v1Dynamic.CurrentOption[1] == "Later")
check("L734 refresh fired callback", dynamicV1 == "Later")
Argon:SaveConfiguration()
local v1Saved = sandbox.decodeJson(sandbox.files["CBV1/config.rfld"])
check("L682 saved textarea value", v1Saved.T_TextArea ~= nil)
local urlTab = v1Window:CreateTab("Urls", "server")
urlTab:CreateSection("Fields")
local v1Url = urlTab:CreateInput({ Flag = "U_Url", Name = "Webhook", CurrentValue = longUrl })
local v1Box
for _, child in ipairs(v1Url.Root:GetDescendants()) do
	if child.ClassName == "TextBox" then v1Box = child end
end
check("L1045 the stored value is the full text", v1Url.CurrentValue == longUrl)
check("L1046 the field shows an elided form", v1Box ~= nil and v1Box.Text ~= longUrl and #v1Box.Text < #longUrl)
check("L1048 the elided form keeps the head and the tail", v1Box.Text:find("discord.com", 1, true) ~= nil and v1Box.Text:sub(-6) == longUrl:sub(-6))
check("L1051 the scheme is dropped for display only", v1Box.Text:sub(1, 4) ~= "http" and v1Url.CurrentValue:sub(1, 5) == "https")
check("L1052 focusing restores the real text", (function()
	v1Box.Focused:Fire()
	return v1Box.Text == longUrl
end)())
check("L1056 blurring commits and re-elides", (function()
	v1Box.Text = "https://example.com/a/very/long/path/that/should/also/be/elided/for/display"
	v1Box.FocusLost:Fire(true)
	return v1Url.CurrentValue == "https://example.com/a/very/long/path/that/should/also/be/elided/for/display" and v1Box.Text ~= v1Url.CurrentValue
end)())
check("L1062 a short value is shown in full", (function()
	v1Url:Set("hello")
	return v1Box.Text == "hello"
end)())
check("L1066 Set(silent) still updates the display", (function()
	v1Url:Set("quiet", true)
	return v1Url.CurrentValue == "quiet" and v1Box.Text == "quiet"
end)())

section("density switch and phone sheet")
local phoneWindow = Argon:CreateWindow({ Name = "Phone", GuiName = "CBPhone" })
local phoneTab = phoneWindow:CreateTab("Main", "zap")
phoneTab:CreateSection("S")
phoneWindow:FinishLoading()
sandbox.advance(1.5)
local pInput = phoneTab:CreateInput({ Name = "Name", CurrentValue = "kept" })
local pArea = phoneTab:CreateTextArea({ Name = "Notes", CurrentValue = "a\nb" })
local pDrop = phoneTab:CreateDropdown({ Name = "Pick", Options = { "A", "B", "C" }, CurrentOption = "B" })
local pColor = phoneTab:CreateColorPicker({ Name = "Paint", Color = "#336699" })
local _ = pInput.Root, pArea.Root, pDrop.Root, pColor.Root
local oldField = pInput._field
sandbox.setViewport(390, 844)
sandbox.setPreferredInput("touch")
sandbox.advance(0.1)
-- Metrics is global: only the first window's density handler remounts, so do what it does here.
phoneTab:_unmount()
check("unmount drops the instances", oldField.Parent == nil and rawget(pInput, "_box") == nil)
local _ = pInput.Root, pArea.Root, pDrop.Root, pColor.Root
check("after a density switch the controls remount with their values", pInput._box.Text == "kept" and pArea._box.Text == "a\nb"
	and pDrop._value.Text == "B" and pColor._field.Text == "#336699")
check("touch density: 40 px wells", pInput._field.Size.Y.Offset == 40 and pDrop._field.Size.Y.Offset == 40, pInput._field.Size.Y.Offset)
local phoneHost = phoneWindow._popover
sandbox.input.click(pDrop.Root)
local sheetPanel = pDrop._panel
check("on a phone the dropdown opens as a bottom sheet with 52 px rows", phoneHost:isOpen(pDrop) and sheetPanel.sheet
	and sheetPanel.list.rows[1].Root.Size.Y.Offset == 52 and sheetPanel.head and sheetPanel.head.title.Text == "Pick")
check("the sheet spans the screen width", phoneHost.panel.Size.X.Offset >= 380, phoneHost.panel.Size.X.Offset)
sandbox.input.click(sheetPanel.head.close)
check("the sheet's x closes it", not phoneHost:isOpen(pDrop))
sandbox.input.click(pColor.Root)
check("the color picker opens on a phone too", phoneHost:isOpen(pColor))
phoneHost:close("test")
sandbox.setPreferredInput("mouse")
sandbox.setViewport(1920, 1080)
sandbox.advance(0.1)

sandbox.advance(1)
check("no warnings", #sandbox.warnings == 0, table.concat(sandbox.warnings, " | "))
check("no signal errors", #sandbox.signalErrors == 0, table.concat(sandbox.signalErrors, " | "))
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	print("\nFailures:")
	for _, line in ipairs(failures) do print("  - " .. line) end
	process.exit(1)
end
