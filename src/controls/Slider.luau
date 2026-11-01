--!nocheck
-- Slider (DESIGN_V2 6.9): a Hit band over a 4 px groove whose gradient carries the fill (a hard
-- stop at the value), a white thumb and an editable value pill; drags fire the callback live and
-- commit on release. Slider.Num is the numeric model and row message line Stepper/Keybind share.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Util = require("core/Util")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Color = require("theme/Color")
local Icons = require("icons/Icons")
local Drag = require("input/Drag")
local Router = require("input/Router")

local T, F, TS = Token.T, Token.F, Token.TS
local Num = {}

-- ---------- numeric model ----------
-- A reversed Range is swapped; Increment <= 0 means continuous with 2 decimals (step 0).
function Num.init(self, config)
	local range = type(config.Range) == "table" and config.Range or {}
	local a, b = tonumber(range[1]) or 0, tonumber(range[2]) or 100
	if a > b then a, b = b, a end
	local step = tonumber(config.Increment) or 1
	if step ~= step or step <= 0 then step = 0 end
	self._min, self._max, self._step = a, b, step
	self._suffix = config.Suffix ~= nil and tostring(config.Suffix) or ""
	self.CurrentValue = Num.snap(self, Num.parse(config.CurrentValue) or a)
end

-- A number, or the first numeric run of a string ("12.5 studs" -> 12.5).
function Num.parse(raw)
	local n = type(raw) == "number" and raw or nil
	if type(raw) == "string" then n = tonumber(raw) or tonumber(raw:match("%-?%d*%.?%d+")) end
	if n and n == n and math.abs(n) ~= math.huge then return n end
	return nil
end

-- v1 rounding (Util.roundToStep) then clamp; the maximum is always reachable.
function Num.snap(self, x)
	local min, max = self._min, self._max
	local v = Util.roundToStep(x, min, self._step)
	if v > max or (self._step > 0 and max - x < math.abs(v - x)) then v = max end
	return v < min and min or v
end

-- The number as typed text: trimmed to the step's decimals.
function Num.plain(self, v)
	local places = self._step > 0 and math.min(Util.decimals(self._step), 6) or 2
	local text = ("%." .. places .. "f"):format(v)
	if places > 0 then text = text:gsub("%.?0+$", "") end
	return text == "-0" and "0" or text
end

-- The number as shown: config.Format(v) when given.
function Num.text(self, v)
	local format = self._cfg.Format
	if type(format) == "function" then
		local ok, text = pcall(format, v)
		if ok and text ~= nil then return tostring(text) end
	end
	return Num.plain(self, v)
end

-- Suffix spacing (ARCHITECTURE_V2 11): attached unless it starts with a letter and is longer than
-- 2 characters, so "10 Bananas" but "50%" and "3ms".
function Num.suffix(self)
	local s = self._suffix
	return (s:match("^%a") and #s > 2) and " " .. s or s
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- The value in Text and the suffix in Muted (rich text).
function Num.rich(self)
	local value, suffix = escape(Num.text(self, self.CurrentValue)), Num.suffix(self)
	if suffix == "" then return value end
	return value .. '<font color="#' .. Color.toHex(Theme.get("Muted")) .. '">' .. escape(suffix) .. "</font>"
end

-- Width of a value pill or field: the widest value plus the suffix in mono.
function Num.width(self, extra, min, max)
	local chars = math.max(#Num.text(self, self._min), #Num.text(self, self._max)) + #Num.suffix(self)
	return math.clamp(math.ceil(chars * Metrics.textSize("Value") * 0.62) + extra, min, max)
end

function Num.unit(self)
	return self._step > 0 and self._step or (self._max - self._min) / 100
end

-- Keyboard and pad steps: ±1, ±10 (Shift) and ±math.huge (Home/End).
function Num.adjust(self, steps)
	local v = steps == math.huge and self._max or steps == -math.huge and self._min
		or Num.snap(self, self.CurrentValue + steps * Num.unit(self))
	return self:_setValue(v, { source = "user" })
end

-- Typed text: a non-number keeps the value; out of range clamps and states the range.
function Num.commit(self, text)
	local n = Num.parse(text)
	if not n then
		Num.message(self, "Enter a number", "Danger", 2)
	else
		if n < self._min or n > self._max then
			Num.message(self, ("Must be between %s and %s"):format(Num.text(self, self._min), Num.text(self, self._max)), "Danger", 2)
		end
		self:_setValue(Num.snap(self, n), { source = "user" })
	end
	self:_render(false)
end

-- An editable value box: focus shows the plain number, Up/Down step while typing, Enter or
-- focus loss commits.
function Num.wire(self, scope, box)
	scope:connect(box.Focused, function()
		if self:_inactive() then box:ReleaseFocus() return end
		self._editing = true
		box.RichText = false
		box.Text = Num.plain(self, self.CurrentValue)
		pcall(function() box.SelectionStart, box.CursorPosition = 1, #box.Text + 1 end)
		local function step(dir)
			local v = Num.snap(self, (Num.parse(box.Text) or self.CurrentValue) + dir * Num.unit(self))
			self:_setValue(v, { source = "user" })
			box.Text = Num.plain(self, v)
		end
		local function typing() return box:IsFocused() end
		Num.unwire(self)
		self._editBinds = {
			Router.bind({ key = Enum.KeyCode.Up, owner = self, priority = 200, allowWhileTyping = true, enabled = typing, onPress = function() step(1) end }),
			Router.bind({ key = Enum.KeyCode.Down, owner = self, priority = 200, allowWhileTyping = true, enabled = typing, onPress = function() step(-1) end }),
		}
		self:_render(false)
	end)
	scope:connect(box.FocusLost, function()
		Num.unwire(self)
		if self._editing and not self._destroyed then
			self._editing = false
			Num.commit(self, box.Text)
		end
	end)
end

function Num.unwire(self)
	for _, bind in ipairs(self._editBinds or {}) do bind:unbind() end
	self._editBinds = nil
end

-- Releases a glow slot and takes the pooled image out of this row: core/Glow leaves a released
-- image parented where it was, so destroying the row would destroy the window's shared image.
-- An image that is already gone is dropped, and Glow builds a new one on the next acquire.
function Num.unglow(self, slot)
	local glow = self._window._glow
	if not glow then return end
	glow:release(slot, self)
	local state = glow.slots and glow.slots[slot]
	if state and state.owner == nil and not pcall(function() state.image.Parent = nil end) then
		glow.slots[slot] = nil
	end
end

-- ---------- the row message line (DESIGN_V2 5) ----------
local GLYPH = { Danger = "circle-alert", Warning = "triangle-alert", Muted = "info" }

-- Shows text under the description (or the title band) in a status colour (kind: "Danger",
-- "Warning" or "Muted"), with optional text buttons (actions = {{text, fn}}). seconds hides it
-- again; nil keeps it. Num.message(self, nil) hides it. Built on first use.
function Num.message(self, text, kind, seconds, actions)
	local view = self._view
	if not view or not rawget(self, "_mounted") then return end
	local scope = self._scope
	local msg = view.Message
	if not msg then
		if not text then return end
		msg = Factory.new(scope, "Frame", { Name = "Message", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16), ZIndex = 2 }, view.Root)
		Factory.list(scope, msg, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center })
		view.MessageIcon = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12),
			LayoutOrder = 1, ZIndex = 2 }, msg)
		view.MessageText = Factory.text(scope, "TextLabel", { Name = "Text", FontFace = F.Caption, TextSize = TS.Caption,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), LayoutOrder = 2, ZIndex = 2 }, msg)
		view.MessageButtons = {}
		view.Message = msg
	end
	self._msgToken = (self._msgToken or 0) + 1
	local token = self._msgToken
	msg.Visible = text ~= nil
	view.MessageActions = actions
	if text then
		Icons.apply(view.MessageIcon, GLYPH[kind] or "info", nil)
		view.MessageIcon.ImageColor3 = Theme.get(kind)
		view.MessageText.Text = text
		view.MessageText.TextColor3 = Theme.get(kind)
		for index, button in ipairs(view.MessageButtons) do button.Visible = actions ~= nil and actions[index] ~= nil end
		for index, action in ipairs(actions or {}) do
			local button = view.MessageButtons[index]
			if not button then
				button = Factory.text(scope, "TextButton", { Name = "Action", FontFace = F.Button, TextSize = TS.Caption, TextColor3 = T.AccentText,
					AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), LayoutOrder = 2 + index, ZIndex = 2 }, msg)
				scope:connect(button.MouseButton1Click, function()
					local current = view.MessageActions and view.MessageActions[index]
					if current then current[2]() end
				end)
				view.MessageButtons[index] = button
			end
			button.Text = action[1]
			button.Visible = true
		end
	end
	local desc = view.Description
	local below = desc and desc.Visible
	local scale = self._window._layers and self._window._layers.scale or 1
	msg.Position = UDim2.fromOffset(view.padH, below and desc.Position.Y.Offset + math.floor(desc.AbsoluteSize.Y / scale) + 2 or view.band - 8)
	if not below then view.Root.Size = UDim2.new(1, 0, 0, view.band + (text and 14 or 0)) end
	if text and seconds then
		scope:delay(seconds, function()
			if self._msgToken == token then Num.message(self, nil) end
		end)
	end
end

-- ---------- slider ----------
local function key(t, color) return ColorSequenceKeypoint.new(t, color) end

-- The groove gradient: AccentDeep -> Accent -> AccentHi over 0..p, then Track (DESIGN_V2 2.6).
local function fill(p, inactive)
	local track = Theme.get("Track")
	local a, b, c = Theme.get("AccentDeep"), Theme.get("Accent"), Theme.get("AccentHi")
	if inactive then
		a = Theme.get("Disabled")
		b, c = a, a
	end
	if p <= 0 then return ColorSequence.new(track) end
	if p >= 0.999 then return ColorSequence.new({ key(0, a), key(0.55, b), key(1, c) }) end
	return ColorSequence.new({ key(0, a), key(p * 0.55, b), key(p, c), key(p + 0.001, track), key(1, track) })
end

local function fromX(self, x)
	local hit = self._hit
	local width = hit and hit.AbsoluteSize.X or 0
	if width <= 0 then return end
	local p = math.clamp((x - hit.AbsolutePosition.X) / width, 0, 1)
	self:_setValue(Num.snap(self, self._min + p * (self._max - self._min)), { source = "drag" })
end

-- Press anywhere on the band to jump and drag; touch needs horizontal intent and the page
-- does not scroll meanwhile. The callback fires live; release commits once.
local function beginDrag(self, input)
	local kind = input.UserInputType
	if (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) or self:_inactive() then return end
	if self._drag and self._drag.active then return end
	local glow = self._window._glow
	self._drag = Drag.begin(input, {
		intent = kind == Enum.UserInputType.Touch and "horizontal" or nil,
		lockScroll = rawget(self._tab, "Page"),
		onStart = function(pos)
			self._dragging = true
			fromX(self, pos.X)
			self:_render(false)
			if glow and self._thumb then glow:acquire(1, self, self._thumb, { spread = 8 }) end
		end,
		onMove = function(pos) fromX(self, pos.X) end,
		onEnd = function(_, cancelled)
			self._dragging = false
			Num.unglow(self, 1)
			if self._destroyed then return end
			self:_render(false)
			if not cancelled then self:_endDrag() end
		end,
	})
end

local function stop(self)
	Num.unwire(self)
	self._editing = false
	if self._drag then self._drag.cancel() end
	Num.unglow(self, 1)
end

-- Shared spec parts (Stepper uses them too).
Num.normalize = function(self, raw)
	local n = Num.parse(raw)
	return n and Num.snap(self, n) or nil
end
Num.describe = function(self, value) return Num.text(self, value) .. Num.suffix(self) end
Num.Set = function(self, value, silent) return self:_setValue(value, { silent = silent == true, source = "api" }) end

local Slider = Element.define({
	Type = "Slider",
	defaultName = "Slider",
	flaggable = true,
	viewFields = { "_hit", "_thumb", "_valueBox" },

	init = Num.init,

	-- The control column: 40 % of the row, clamped to 180-300 (DESIGN_V2 2.8).
	reserve = function(self)
		local width = 0
		pcall(function() width = self._owner:_container().AbsoluteSize.X / (self._window._layers.scale or 1) end)
		self._pillW = Num.width(self, 16, 56, 104)
		self._ctlW = math.clamp(math.floor((width > 0 and width or 600) * 0.4), 180, 300)
		return self._ctlW
	end,

	build = function(self, view, scope)
		local pillW = self._pillW
		local box = RowView.control(view, Factory.text(scope, "TextBox", {
			Name = "Value", BackgroundColor3 = T.Well, BackgroundTransparency = 0, FontFace = F.Value, TextSize = TS.Value,
			TextXAlignment = Enum.TextXAlignment.Center, ClearTextOnFocus = false, RichText = true, ZIndex = 2,
		}, view.Root), pillW, Metrics.get("control") - 4)
		Factory.corner(scope, box, Metrics.radius.control28)
		local hit = RowView.control(view, Factory.new(scope, "TextButton", { Name = "Hit", BackgroundTransparency = 1, ZIndex = 2 }, view.Root),
			self._ctlW - pillW - 12, Metrics.get("sliderHit"), pillW + 12)
		local groove = Factory.new(scope, "Frame", { Name = "Groove", BackgroundColor3 = T.White, AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 4), ZIndex = 2 }, hit)
		Factory.corner(scope, groove, "full")
		self._fill = Factory.new(scope, "UIGradient", nil, groove)
		local thumb = Factory.new(scope, "Frame", { Name = "Thumb", BackgroundColor3 = T.White, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 4 }, hit)
		Factory.corner(scope, thumb, "full")
		Factory.stroke(scope, thumb, T.Shadow, 0.75, 1)
		self._hit, self._thumb, self._valueBox = hit, thumb, box
		-- ticks: 2 px dots at each step when there are 12 or fewer (Ticks = true: up to 50)
		local span, step, ticks = self._max - self._min, self._step, self._cfg.Ticks
		local steps = (step > 0 and span > 0) and span / step or math.huge
		if ticks ~= false and steps <= (ticks == true and 50 or 12) then
			local count = math.floor(steps + 1e-6)
			for index = 0, count + (count * step < span - 1e-9 and 1 or 0) do
				Factory.new(scope, "Frame", { Name = "Tick", BackgroundColor3 = T.Text2, BackgroundTransparency = 0.5,
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(math.min(1, index * step / span), 0.5),
					Size = UDim2.fromOffset(2, 2), ZIndex = 3 }, hit)
			end
		end
		scope:connect(hit.InputBegan, function(input) beginDrag(self, input) end)
		Num.wire(self, scope, box)
	end,

	render = function(self, animated)
		local thumb = self._thumb
		if not thumb then return end
		local span = self._max - self._min
		local p = span > 0 and (self.CurrentValue - self._min) / span or 1
		local inactive, dragging = self:_inactive(), self._dragging
		self._fill.Color = fill(p, inactive)
		local size = dragging and 20 or (self._hover and not inactive and 18 or 16)
		thumb.Size = UDim2.fromOffset(size, size)
		thumb.BackgroundColor3 = Theme.get(inactive and "Disabled" or "White")
		Motion.spring(thumb, "Position", UDim2.fromScale(p, 0.5), "snappy", animated and not dragging)
		if dragging and self._window._glow then self._window._glow:sync(1) end
		local box = self._valueBox
		if not self._editing then
			box.RichText = true
			box.Text = Num.rich(self)
		end
		box.TextColor3 = Theme.get(inactive and "Disabled" or (dragging and "AccentText" or "Text"))
		box.TextEditable = not inactive
	end,

	hover = function(self, on)
		local thumb = self._thumb
		if thumb and not self._dragging and not self:_inactive() then
			thumb.Size = UDim2.fromOffset(on and 18 or 16, on and 18 or 16)
		end
	end,

	normalize = Num.normalize,
	describe = Num.describe,

	focus = {
		activate = function(self) if self._valueBox then self._valueBox:CaptureFocus() end end,
		adjust = Num.adjust,
	},

	methods = { Set = Num.Set },
	destroy = stop,
	unmount = function(self)
		stop(self)
		self._hit, self._thumb, self._valueBox = nil, nil, nil
	end,
})

Slider.Num = Num
return Slider
