--!nocheck
-- TextArea (DESIGN_V2 6.13): a multi-line field that always stacks under its label. A Well
-- ScrollingFrame holds the TextBox; AutoGrow sizes it between MinHeight and MaxHeight, the caret
-- is kept in view, and it commits on focus loss. GetLines returns the non-empty lines.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Util = require("core/Util")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Field = require("controls/Input").Field

local T, F, TS = Token.T, Token.F, Token.TS

local function fieldHeight(self)
	if not self._grow then return self._fixed end
	local box = self._box
	local content = 0
	if box then
		local _, breaks = (box.Text or ""):gsub("\n", "")
		content = math.max(box.TextBounds.Y, (breaks + 1) * (box.TextSize + 3))
	end
	return math.clamp(math.ceil(content) + 16, self._minH, self._maxH)
end

-- Label band, then the field, then the description (if any) under the field.
local function layout(self)
	local view, field, box = self._view, self._field, self._box
	if not view or not field then return end
	local h = fieldHeight(self)
	field.Size = UDim2.new(1, -view.padH * 2, 0, h)
	box.Size = UDim2.new(1, 0, 0, math.max(h - 16, 0))
	local bottom = view.band + h + Metrics.get("padV")
	local desc = view.Description
	if desc and desc.Visible then desc.Position = UDim2.fromOffset(view.padH, bottom - 4) end
	view.Root.Size = UDim2.new(1, 0, 0, bottom)
end

-- Scrolls the caret's line into view (the engine does not scroll a TextBox in a ScrollingFrame).
local function reveal(self)
	local field, box = self._field, self._box
	local text, cursor = box.Text, box.CursorPosition
	local y = box.TextBounds.Y
	if cursor and cursor > 0 and cursor <= #text then
		local ok, size = pcall(function()
			return Env.services.TextService:GetTextSize(text:sub(1, cursor - 1), box.TextSize,
				Env.enum("Font", "Roboto", "SourceSans"), Vector2.new(math.max(box.AbsoluteSize.X, 1), 100000))
		end)
		if ok and size then y = size.Y end
	end
	local view = field.AbsoluteSize.Y - 16
	local top = field.CanvasPosition.Y
	if y + 8 > top + view then
		field.CanvasPosition = Vector2.new(0, y + 8 - view)
	elseif y - box.TextSize - 8 < top then
		field.CanvasPosition = Vector2.new(0, math.max(0, y - box.TextSize - 8))
	end
end

local function counter(self, text)
	if self._counter then Field.count(self._counter, Util.utf8len(text), self._maxLength) end
end

local TextArea = Element.define({
	Type = "TextArea",
	defaultName = "Notes",
	flaggable = true,

	init = function(self, config)
		self._placeholder = tostring(config.PlaceholderText or config.Placeholder or "Enter text...")
		self._fixed = math.clamp(math.floor(tonumber(config.Height) or 104), 72, 320)
		self._grow = config.AutoGrow == true
		self._minH = math.max(40, tonumber(config.MinHeight) or 80)
		self._maxH = math.max(self._minH, tonumber(config.MaxHeight) or 240)
		self._mono = config.Monospace == true
		self._live = config.Live == true
		local max = tonumber(config.MaxLength)
		self._maxLength = max and max >= 1 and math.floor(max) or nil
		local value = config.CurrentValue
		value = value == nil and "" or tostring(value)
		self.CurrentValue = self._maxLength and Util.truncate(value, self._maxLength) or value
	end,

	height = function()
		return Metrics.get("row") - 8
	end,

	reserve = function(self)
		return self._maxLength and 64 or 0
	end,

	build = function(self, view, scope)
		local field, stroke = Field.well(scope, view.Root, "ScrollingFrame", {
			Name = "Field", Position = UDim2.fromOffset(view.padH, view.band), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3, ScrollBarImageColor3 = T.Track, ZIndex = 2,
		})
		Factory.padding(scope, field, 10, 10, 8, 8)
		local box = Field.box(scope, field, {
			Name = "TextBox", MultiLine = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y, PlaceholderText = self._placeholder, ZIndex = 3,
			FontFace = self._mono and F.Value or F.Body, TextSize = self._mono and TS.Value or TS.Input,
		})
		self._field, self._stroke, self._box = field, stroke, box
		if self._maxLength then
			self._counter = Factory.text(scope, "TextLabel", {
				Name = "Counter", FontFace = F.Key, TextSize = TS.Key, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -view.padH, 0, RowView.bandY(view, 16)), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2,
			}, view.Root)
		end
		scope:connect(box.Focused, function()
			if self:_inactive() then
				box:ReleaseFocus()
				return
			end
			self._focused = true
			self._draft = box.Text
			Field.glow(self, true)
			self:_render(true)
		end)
		scope:connect(box.FocusLost, function()
			if not self._focused then return end
			self._focused = false
			Field.glow(self, false)
			local text = self._draft or box.Text
			self._draft = nil
			if text ~= self.CurrentValue and not self:_inactive() then self:_setValue(text, { source = "user" }) end
			self:_render(false)
		end)
		scope:connect(box:GetPropertyChangedSignal("Text"), function()
			if self._writing or not self._focused then return end
			local text = box.Text
			if self._maxLength and Util.utf8len(text) > self._maxLength then
				text = Util.truncate(text, self._maxLength)
				Field.set(self, box, text)
			end
			self._draft = text
			counter(self, text)
			if self._grow then layout(self) end
			reveal(self)
			if self._live then
				local token = {}
				self._liveToken = token
				task.delay(0.2, function()
					if self._liveToken ~= token or self._destroyed then return end
					local signal = rawget(self, "_changed")
					if signal then signal:Fire(self._draft or self.CurrentValue, "live") end
				end)
			end
		end)
		local function grab()
			if not self:_inactive() and not Field.touch() then box:CaptureFocus() end
		end
		scope:connect(view.Root.MouseButton1Click, grab)
		scope:connect(field.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not self._focused then grab() end
		end)
	end,

	render = function(self, animated)
		local box = self._box
		if not box then return end
		local inactive = self:_inactive()
		box.TextEditable = not inactive
		box.TextColor3 = Theme.get(inactive and "Disabled" or "Text")
		if not self._focused then Field.set(self, box, self.CurrentValue) end
		Field.paint(self._stroke, inactive and "disabled" or (self._focused and "focus") or (self._hovering and "hover") or "rest", animated)
		local title = self._view.Title
		if title and self._focused and not inactive then title.TextColor3 = Theme.get("AccentText") end
		counter(self, self._focused and (self._draft or "") or self.CurrentValue)
		layout(self)
	end,

	hover = function(self, on)
		self._hovering = on
		if self._stroke and not self._focused and not self:_inactive() then Field.paint(self._stroke, on and "hover" or "rest", true) end
	end,

	normalize = function(self, raw)
		local text = raw == nil and "" or tostring(raw)
		return self._maxLength and Util.truncate(text, self._maxLength) or text
	end,

	describe = function(_, value)
		if value == nil or value == "" then return "empty" end
		local line = value:match("^[^\n]*")
		return (Util.truncate(line, 40):gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
	end,

	focus = {
		activate = function(self)
			if self._box and not Field.touch() then self._box:CaptureFocus() end
		end,
	},

	unmount = function(self)
		Field.glow(self, false)
		self._field, self._stroke, self._box, self._counter, self._focused, self._draft = nil, nil, nil, nil, false, nil
	end,

	destroy = function(self)
		Field.glow(self, false)
	end,

	methods = {
		Set = function(self, value, silent)
			return self:_setValue(value, { silent = silent == true, source = "api" })
		end,
		-- Non-empty lines (whitespace-only lines are skipped unless keepEmpty), without "\r".
		GetLines = function(self, keepEmpty)
			local out = {}
			for line in (tostring(self.CurrentValue or "") .. "\n"):gmatch("(.-)\n") do
				line = line:gsub("\r$", "")
				if keepEmpty or line:match("%S") then out[#out + 1] = line end
			end
			return out
		end,
		SetDesc = function(self, text)
			Element.Base.SetDesc(self, text)
			layout(self)
			return self
		end,
	},
})

return TextArea
