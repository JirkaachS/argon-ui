--!nocheck
-- Input (DESIGN_V2 6.12): a Well field holding a TextBox. The callback fires when the text changed
-- or Enter was pressed; long values are elided while unfocused (v1). v2 adds Numeric, Min, Max,
-- MaxLength, Validate, Live, ClearButton, Icon, Masked and ReadOnly. Input.Field holds the well
-- helpers that TextArea, Dropdown and ColorPicker share.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Util = require("core/Util")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local Router = require("input/Router")
local Platform = require("input/Platform")

local T, F, TS = Token.T, Token.F, Token.TS
local DOT = "\u{2022}"

-- ---------- shared well helpers ----------
local Field = {}

-- Touch never auto-focuses a text field (DESIGN_V2 6.12).
function Field.touch()
	return Router.lastInputKind == "touch" or Platform.preferred() == "touch"
end

-- The control column: 40 % of the row, clamped (DESIGN_V2 2.8).
function Field.width(el, lo, hi)
	local ok, holder = pcall(function() return el._owner:_container() end)
	local w = ok and holder and holder.AbsoluteSize.X or 0
	if w < 100 then w = 560 end
	return math.clamp(math.floor(w * 0.4), lo or 160, hi or 260)
end

function Field.radius(h)
	return h >= 32 and Metrics.radius.control or Metrics.radius.control28
end

-- A Well with a corner and a 1 px stroke; the stroke colour is state (Field.paint).
function Field.well(scope, parent, className, props, radius)
	props.BackgroundColor3 = T.Well
	local well = Factory.new(scope, className or "Frame", props, parent)
	Factory.corner(scope, well, radius or Metrics.radius.control)
	local stroke = Factory.new(scope, "UIStroke", {
		Color = Theme.get("Border"), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, well)
	return well, stroke
end

local STROKE = { rest = "Border", hover = "Track", focus = "Focus", error = "Danger", readonly = "BorderSoft" }
function Field.paint(stroke, state, animated)
	if not stroke then return end
	stroke.Transparency = state == "disabled" and 1 or 0
	if state == "disabled" then return end
	local color = Theme.get(STROKE[state] or "Border")
	if animated then Motion.tween(stroke, "state", { Color = color }) else stroke.Color = color end
end

function Field.box(scope, parent, props)
	props.FontFace = props.FontFace or F.Body
	props.TextSize = props.TextSize or TS.Input
	props.PlaceholderColor3 = T.Dim
	props.ClearTextOnFocus = false
	props.ClipsDescendants = true
	return Factory.text(scope, "TextBox", props, parent)
end

-- Follows the row width: one property signal on the row's own root, no global handler.
function Field.track(el, view, scope, lo, hi, apply)
	scope:connect(view.Root:GetPropertyChangedSignal("AbsoluteSize"), function()
		local w = Field.width(el, lo, hi)
		if w ~= view.reserve then
			RowView.setReserve(el, w)
			apply(w)
		end
	end)
end

-- Writes a box's text without treating it as typing.
function Field.set(el, box, text)
	if not box or box.Text == text then return end
	el._writing = true
	box.Text = text
	el._writing = false
end

-- The focused field's soft glow (slot 1).
function Field.glow(el, on)
	local glow = el._window and el._window._glow
	if not glow then return end
	if on and el._field then
		glow:acquire(1, el, el._field, { transparency = 0.82, spread = 6 })
	else
		glow:release(1, el)
	end
end

-- The mono 12 MaxLength counter colour: Dim, Warning from 90 %.
function Field.count(label, n, max)
	label.Text = n .. "/" .. max
	label.TextColor3 = Theme.get(n >= max * 0.9 and "Warning" or "Dim")
	label.Size = UDim2.fromOffset(math.ceil(#label.Text * 7.2) + 2, 16)
end

-- ---------- text helpers ----------
local function chars(text)
	local out = {}
	if not pcall(function()
		for _, code in utf8.codes(text) do out[#out + 1] = utf8.char(code) end
	end) then
		out = {}
		for index = 1, #text do out[index] = text:sub(index, index) end
	end
	return out
end

local function dots(text, cap)
	local n = Util.utf8len(text)
	return string.rep(DOT, cap and math.min(n, cap) or n)
end

-- Rebuilds the real text of a masked box after an edit: bullets map to the old text's head and
-- tail, anything else was typed or pasted. Returns the text and the caret (in characters).
local function unmask(old, shown, cursor)
	local was, now = chars(old), chars(shown)
	local first, last
	for index, char in ipairs(now) do
		if char ~= DOT then
			first = first or index
			last = index
		end
	end
	local head, tail, typed
	if first then
		head, tail = first - 1, #now - last
		typed = table.concat(now, "", first, last)
	else
		head = #now
		if cursor and cursor > 0 then
			local bytes = 0
			head = 0
			for index, char in ipairs(now) do
				bytes += #char
				if bytes > cursor - 1 then break end
				head = index
			end
		end
		tail, typed = #now - head, ""
	end
	head = math.min(head, #was)
	tail = math.min(tail, #was - head)
	return table.concat(was, "", 1, head) .. typed .. table.concat(was, "", #was - tail + 1, #was), head + Util.utf8len(typed)
end

-- v1 elision: drop the scheme; over 38 characters keep the first 24 and the last 10.
local function elide(text)
	local rest = text:gsub("^https?://", "")
	if Util.utf8len(rest) <= 38 then return rest end
	return Util.utf8sub(rest, 1, 24) .. "\u{2026}" .. Util.utf8sub(rest, -10)
end

local function fmt(n)
	if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
	return tostring(n)
end

local function rangeText(lo, hi)
	if lo and hi then return ("Must be between %s and %s"):format(fmt(lo), fmt(hi)) end
	if lo then return "Must be at least " .. fmt(lo) end
	return "Must be at most " .. fmt(hi)
end

local function normalize(self, raw)
	local text = raw == nil and "" or tostring(raw)
	if self._maxLength then text = Util.truncate(text, self._maxLength) end
	if self._numeric and text ~= "" then
		local n = tonumber(text)
		if not n then return nil end
		if self._min and n < self._min then n = self._min end
		if self._max and n > self._max then n = self._max end
		text = fmt(n)
	end
	return text
end

-- What the box shows while unfocused.
local function shown(self)
	if self._cleared then return "" end
	local text = self._bad or self.CurrentValue or ""
	if self._masked then return dots(text, 24) end
	if self._cfg.Elide == false then return text end
	return elide(text)
end

local function baseline(self)
	return self._cleared and "" or self.CurrentValue
end

-- ---------- layout ----------
-- [icon] box [counter] [enter cap] [clear or copy]
local function layout(self)
	local box = self._box
	if not box then return end
	local right = 8
	for _, part in ipairs({ self._act, self._cap, self._counter }) do
		if part and part.Visible then
			part.Position = UDim2.new(1, -right, 0.5, 0)
			right += part.Size.X.Offset + 4
		end
	end
	local left = self._icon and 32 or 10
	box.Position = UDim2.fromOffset(left, 0)
	box.Size = UDim2.new(1, -(left + right), 1, 0)
end

-- The row grows by the message line when there is no description to auto-size it.
local function placeRoot(self)
	local view = self._view
	if not view or not view.Root then return end
	local desc = view.Description and view.Description.Visible
	if not desc then
		local on = self._msg and self._msg.Visible
		view.Root.Size = UDim2.new(1, 0, 0, view.band + (on and 14 or 0))
	end
end

-- Validation or hint line under the field (DESIGN_V2 5 "Message"). kind: "error" | "hint".
local function message(self, text, kind, seconds)
	self._msgText, self._msgKind = text, text and kind or nil
	self._msgToken = nil
	local view = self._view
	if not view or not view.Root then return end
	local msg = self._msg
	if text and not msg then
		local scope = self._scope
		msg = Factory.text(scope, "TextLabel", {
			Name = "Message", FontFace = F.Caption, TextSize = TS.Caption, AnchorPoint = Vector2.new(1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
		}, view.Root)
		self._msgIcon = Factory.new(scope, "ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, -16, 0.5, -6),
		}, msg)
		self._msg = msg
	end
	if msg then
		msg.Visible = text ~= nil
		if text then
			local color = Theme.get(kind == "error" and "Danger" or "Muted")
			msg.Text = text
			msg.TextColor3 = color
			Icons.apply(self._msgIcon, kind == "error" and "circle-alert" or "info", nil, color)
			msg.Position = UDim2.new(1, -view.padH, 0, view.band - 4)
			msg.Size = UDim2.fromOffset(math.max(view.reserve - 16, 80), 16)
		end
	end
	placeRoot(self)
	if text and seconds then
		local token = {}
		self._msgToken = token
		task.delay(seconds, function()
			if self._msgToken == token and not self._destroyed then message(self, nil) end
		end)
	end
end

-- Clear (x), copy (read-only), the enter cap while dirty and the counter, all on demand.
local function extras(self)
	local box = self._box
	if not box then return end
	local scope = self._scope
	local inactive = self:_inactive()
	local text = self._focused and (self._draft or "") or (self._cleared and "" or (self._bad or self.CurrentValue))
	local want = not inactive and text ~= "" and (self._readOnly or self._clearButton)
	if want and not self._act then
		local act = Factory.new(scope, "ImageButton", {
			Name = self._readOnly and "Copy" or "Clear", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(14, 14), ZIndex = 3,
		}, self._field)
		Icons.apply(act, self._readOnly and "copy" or "x", scope, T.Text2)
		scope:connect(act.MouseButton1Click, function() self:_fieldAction() end)
		self._act = act
	end
	if self._act then self._act.Visible = want == true end
	local dirty = self._focused and not inactive and text ~= baseline(self)
	if dirty and not self._cap then
		local cap = Factory.new(scope, "ImageLabel", {
			Name = "EnterCap", BackgroundColor3 = T.Raised, AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(18, 18), ZIndex = 3,
		}, self._field)
		Factory.corner(scope, cap, Metrics.radius.keycap)
		Icons.apply(cap, "corner-down-left", scope, T.Text2)
		self._cap = cap
	end
	if self._cap then self._cap.Visible = dirty == true end
	local max = self._maxLength
	if max then
		local n = Util.utf8len(text)
		local show = self._focused or n >= max * 0.9
		if show and not self._counter then
			self._counter = Factory.text(scope, "TextLabel", {
				Name = "Counter", FontFace = F.Key, TextSize = TS.Key, AnchorPoint = Vector2.new(1, 0.5),
				TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
			}, self._field)
		end
		if self._counter then
			self._counter.Visible = show
			Field.count(self._counter, n, max)
		end
	end
	layout(self)
end

-- ---------- editing ----------
local function edited(self)
	local box = self._box
	local text = box.Text
	local draft, caret = text, nil
	if self._masked then draft, caret = unmask(self._draft or "", text, box.CursorPosition) end
	if self._numeric and draft ~= "" and not draft:match("^%-?%d*%.?%d*$") then
		draft, caret = self._draft or "", nil
	end
	if self._maxLength and Util.utf8len(draft) > self._maxLength then
		draft = Util.truncate(draft, self._maxLength)
		caret = caret and math.min(caret, self._maxLength)
	end
	self._draft = draft
	local want = self._masked and dots(draft) or draft
	if want ~= text then
		local cursor = box.CursorPosition
		Field.set(self, box, want)
		Env.try(box, "CursorPosition", caret and (caret * #DOT + 1) or math.min(cursor, #want + 1))
	end
	if self._bad then
		self._bad = nil
		if self._msgKind == "error" then message(self, nil) end
		Field.paint(self._stroke, "focus", false)
	end
	extras(self)
	if self._live then
		local token = {}
		self._liveToken = token
		task.delay(0.2, function()
			if self._liveToken ~= token or self._destroyed then return end
			self._liveToken = nil
			local signal = rawget(self, "_changed")
			if signal then signal:Fire(self._draft or self.CurrentValue, "live") end
		end)
	end
end

-- Focus loss: numeric clamp, Validate, then the commit (changed or Enter).
local function commit(self, enter)
	local text = self._draft or ""
	self._draft = nil
	if self._msgKind == "error" then message(self, nil) end
	self._bad = nil
	if self:_inactive() then
		self:_render(false)
		return
	end
	if self._numeric and text ~= "" then
		local n = tonumber(text)
		if not n then
			message(self, "Enter a number", "hint", 2)
			self:_render(false)
			return
		end
		local clamped = n
		if self._min and clamped < self._min then clamped = self._min end
		if self._max and clamped > self._max then clamped = self._max end
		if clamped ~= n then message(self, rangeText(self._min, self._max), "hint", 2) end
		text = fmt(clamped)
	end
	if self._validate then
		local ok, valid, why = Util.xcall(self._validate, self:_context() .. " Validate", self, text)
		if ok and valid == false then
			self._bad = text
			message(self, why ~= nil and tostring(why) or "Invalid value", "error")
			self:_render(true)
			return
		end
	end
	local cleared = self._cleared
	if text ~= baseline(self) or enter then
		self._cleared = false
		self:_setValue(text, { source = "user", force = enter or cleared })
		if self._removeAfter then self._cleared = true end
	end
	self:_render(false)
end

local Input = Element.define({
	Type = "Input",
	defaultName = "Input",
	flaggable = true,

	init = function(self, config)
		self._placeholder = tostring(config.PlaceholderText or config.Placeholder or "Enter value...")
		self._removeAfter = config.RemoveTextAfterFocusLost == true
		self._numeric = config.Numeric == true
		self._min, self._max = tonumber(config.Min), tonumber(config.Max)
		if self._min and self._max and self._min > self._max then self._min, self._max = self._max, self._min end
		local max = tonumber(config.MaxLength)
		self._maxLength = max and max >= 1 and math.floor(max) or nil
		self._validate = type(config.Validate) == "function" and config.Validate or nil
		self._live = config.Live == true
		self._clearButton = config.ClearButton ~= false
		self._masked = config.Masked == true
		self._readOnly = config.ReadOnly == true
		local value = config.CurrentValue
		value = value == nil and "" or tostring(value)
		self.CurrentValue = normalize(self, value) or value
	end,

	reserve = function(self)
		return Field.width(self, 160, 260)
	end,

	build = function(self, view, scope)
		local h = Metrics.get("control")
		local field, stroke = Field.well(scope, view.Root, "Frame", { Name = "Field", ZIndex = 2 }, Field.radius(h))
		RowView.control(view, field, view.reserve, h)
		self._field, self._stroke = field, stroke
		local icon = self._cfg.Icon
		if icon ~= nil and icon ~= "" then
			self._icon = Factory.new(scope, "ImageLabel", {
				Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 10, 0.5, -8), ZIndex = 3,
			}, field)
			Icons.apply(self._icon, icon, scope, T.Text2)
		end
		local box = Field.box(scope, field, { Name = "TextBox", PlaceholderText = self._placeholder, ZIndex = 3 })
		self._box = box
		scope:connect(box.Focused, function()
			if self:_inactive() or self._readOnly then
				box:ReleaseFocus()
				return
			end
			self._focused = true
			local text = self._bad or baseline(self)
			self._draft = text
			Field.set(self, box, self._masked and dots(text) or text)
			Env.try(box, "CursorPosition", #box.Text + 1)
			Field.glow(self, true)
			self:_render(true)
		end)
		scope:connect(box.FocusLost, function(enter)
			if not self._focused then return end
			self._focused = false
			Field.glow(self, false)
			commit(self, enter == true)
		end)
		scope:connect(box:GetPropertyChangedSignal("Text"), function()
			if self._writing or not self._focused then return end
			edited(self)
		end)
		scope:connect(view.Root.MouseButton1Click, function()
			if not self:_inactive() and not self._readOnly and not Field.touch() then box:CaptureFocus() end
		end)
		Field.track(self, view, scope, 160, 260, function(w)
			field.Size = UDim2.fromOffset(w, h)
			if self._msgText then message(self, self._msgText, self._msgKind) end
		end)
		if self._msgText then message(self, self._msgText, self._msgKind) end
	end,

	render = function(self, animated)
		local box = self._box
		if not box then return end
		local inactive = self:_inactive()
		box.TextEditable = not inactive and not self._readOnly
		box.TextColor3 = Theme.get(inactive and "Disabled" or "Text")
		box.PlaceholderText = self._placeholder
		if not self._focused then Field.set(self, box, shown(self)) end
		local state = inactive and "disabled" or (self._bad and "error") or (self._focused and "focus")
			or (self._readOnly and "readonly") or (self._hovering and "hover") or "rest"
		Field.paint(self._stroke, state, animated)
		local title = self._view and self._view.Title
		if title and self._focused and not inactive then title.TextColor3 = Theme.get("AccentText") end
		if self._icon then self._icon.ImageColor3 = Theme.get(inactive and "Disabled" or "Text2") end
		extras(self)
	end,

	hover = function(self, on)
		self._hovering = on
		if self._stroke and not self._focused and not self._bad and not self:_inactive() then
			Field.paint(self._stroke, on and "hover" or (self._readOnly and "readonly" or "rest"), true)
		end
	end,

	normalize = normalize,

	describe = function(self, value)
		if value == nil or value == "" then return "empty" end
		if self._masked then return "hidden" end
		return (elide(value):gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
	end,

	focus = {
		activate = function(self)
			if self._box and not self._readOnly and not Field.touch() then self._box:CaptureFocus() end
		end,
	},

	unmount = function(self)
		Field.glow(self, false)
		self._field, self._stroke, self._box, self._icon, self._act, self._cap, self._counter = nil, nil, nil, nil, nil, nil, nil
		self._msg, self._msgIcon, self._focused, self._draft = nil, nil, false, nil
	end,

	destroy = function(self)
		Field.glow(self, false)
	end,

	methods = {
		Set = function(self, value, silent)
			self._cleared = false
			if self._bad then
				self._bad = nil
				if self._msgKind == "error" then message(self, nil) end
			end
			self:_setValue(value, { silent = silent == true, source = "api" })
			self:_render(false)
			return self
		end,
		SetDesc = function(self, text)
			Element.Base.SetDesc(self, text)
			placeRoot(self)
			return self
		end,
		-- The field's trailing button: clear (runs Set("") as a user change) or copy when read-only.
		_fieldAction = function(self)
			if self:_inactive() then return end
			if self._readOnly then
				self._window:_copy(self.CurrentValue, self)
				return
			end
			self._bad, self._cleared = nil, false
			if self._msgKind == "error" then message(self, nil) end
			if self._focused then
				self._draft = ""
				Field.set(self, self._box, "")
			end
			self:_setValue("", { source = "user" })
			self:_render(false)
		end,
	},
})

Input.Field = Field
Input.elide = elide
return Input
