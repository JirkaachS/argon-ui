--!nocheck
-- ButtonGroup (DESIGN_V2 6.7, new): 2-3 pill buttons side by side in one row, inside the
-- platter padding 8 x 12. .Buttons holds a small handle per button (SetLoading, Set/SetTitle,
-- SetCallback). Looks, busy state and Async come from Button.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Button = require("controls/Button")

local F, TS = Token.F, Token.TS
local paint, run, glyph = Button.paint, Button.run, Button.glyph

local function isPress(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

-- The icon (or the busy spinner) sits left of the label; with an icon the label is padded right.
local function place(handle)
	local width = RowView.textWidth(handle.Name, Metrics.textSize("Button"))
	handle._glyph.Position = UDim2.new(0.5, -math.floor(width / 2) - 16, 0.5, 0)
end

local function icon(scope, handle)
	handle._glyph = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, handle._pill)
	place(handle)
	return handle._glyph
end

local Handle = {}
Handle.__index = Handle

function Handle:_render()
	local pill, group = self._pill, self._group
	if not pill or not rawget(group, "_mounted") then return end
	local focus = group._window._focus
	local cursor = group._cursor == self._index and focus and focus.active and focus.current == group
	paint(pill, pill, self._gradient, self.Variant, group:_inactive() and "inactive"
		or (self._pressed and "pressed" or ((self._hover or cursor) and "hover" or "rest")))
	if (self._loading or self._ok) and not self._glyph and group._scope then icon(group._scope, self) end
	glyph(self, self._glyph, self.Icon, pill.TextColor3, pill.TextColor3)
end

function Handle:SetLoading(on)
	on = on == true
	if (self._loading == true) == on then return self end
	self._loading = on
	self:_render()
	return self
end

function Handle:SetTitle(name)
	self.Name = tostring(name)
	if self._pill and self._pill.Parent then
		self._pill.Text = self.Name
		if self._glyph then place(self) end
	end
	return self
end
Handle.Set = Handle.SetTitle

function Handle:SetCallback(fn)
	self._callback = fn
	return self
end

function Handle:_press()
	return run(self, self._group)
end

local function pressed(handle, on)
	handle._pressed = on
	local scale = handle._scale
	if not scale or not scale.Parent then
		scale = Factory.new(handle._group._scope, "UIScale", { Scale = 1 }, handle._pill)
		handle._scale = scale
	end
	Motion.tween(scale, "press", { Scale = on and 0.97 or 1 })
	handle:_render()
end

local function stop(self)
	for _, handle in ipairs(self.Buttons) do
		if handle._spin then handle._spin.stop() end
		handle._spin = nil
	end
end

local ButtonGroup = Element.define({
	Type = "ButtonGroup",
	defaultName = "Buttons",
	title = false,

	init = function(self, config)
		self.Buttons = {}
		self._cursor = 1
		for _, entry in ipairs(type(config.Buttons) == "table" and config.Buttons or {}) do
			if type(entry) == "table" then
				local variant = tostring(entry.Variant or "Secondary")
				local index = #self.Buttons + 1
				self.Buttons[index] = setmetatable({
					Name = tostring(entry.Name or entry.Title or "Button"),
					Variant = Button.LOOK[variant] and variant or "Secondary",
					Icon = entry.Icon,
					_callback = entry.Callback,
					_async = entry.Async == true,
					_group = self,
					_index = index,
				}, Handle)
			end
		end
	end,

	height = function() return Metrics.get("control") + 20 end,

	-- Equal pills with 8 px gaps inside 12 px side padding, centre-anchored for the press UIScale.
	build = function(self, view, scope)
		local count = math.max(1, #self.Buttons)
		local share = (24 + 8 * (count - 1)) / count
		local height = Metrics.get("control") + 4
		for index, handle in ipairs(self.Buttons) do
			local pill = Factory.text(scope, "TextButton", { Name = "Button", Text = handle.Name, FontFace = F.Button, TextSize = TS.Button,
				TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new((2 * index - 1) / (2 * count), 12 + (index - 1) * (8 - share) - share / 2, 0, 8 + height / 2),
				Size = UDim2.new(1 / count, -share, 0, height) }, view.Root)
			Factory.corner(scope, pill, Metrics.radius.control)
			handle._pill, handle._glyph, handle._spin, handle._scale = pill, nil, nil, nil
			handle._gradient = handle.Variant == "Primary" and Factory.new(scope, "UIGradient", { Rotation = 90 }, pill) or nil
			if handle.Icon then
				Factory.padding(scope, pill, 24, 0, 0, 0)
				icon(scope, handle)
			end
			scope:connect(pill.MouseButton1Click, function() handle:_press() end)
			scope:connect(pill.MouseEnter, function()
				handle._hover = true
				handle:_render()
			end)
			scope:connect(pill.MouseLeave, function()
				handle._hover = false
				if handle._pressed then pressed(handle, false) else handle:_render() end
			end)
			scope:connect(pill.InputBegan, function(input)
				if isPress(input) and not self:_inactive() and not handle._loading then pressed(handle, true) end
			end)
			scope:connect(pill.InputEnded, function(input)
				if isPress(input) and handle._pressed then pressed(handle, false) end
			end)
		end
	end,

	render = function(self)
		Button.underPill(self)
		for _, handle in ipairs(self.Buttons) do handle:_render() end
	end,

	-- Pills draw their own hover, so the section's pooled row hover stays hidden under them.
	hover = function(self)
		local fill = self.Section and rawget(self.Section, "_hover")
		if fill then fill.Visible = false end
	end,

	-- Left and Right pick a button (drawn in its hover state); Enter, Space or A presses it.
	focus = {
		activate = function(self)
			local handle = self.Buttons[self._cursor]
			if handle then handle:_press() end
		end,
		adjust = function(self, steps)
			local count = #self.Buttons
			if count == 0 then return end
			self._cursor = steps == math.huge and count or steps == -math.huge and 1
				or math.clamp(self._cursor + (steps > 0 and 1 or -1), 1, count)
			self:_render(false)
		end,
	},

	methods = {
		_searchOptions = function(self)
			local names = {}
			for index, handle in ipairs(self.Buttons) do names[index] = handle.Name end
			return names
		end,

		SetDesc = function(self, text)
			Element.Base.SetDesc(self, text)
			Button.underPill(self)
			return self
		end,
	},

	destroy = stop,
	unmount = stop,
})

return ButtonGroup
