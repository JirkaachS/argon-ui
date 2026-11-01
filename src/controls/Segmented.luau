--!nocheck
-- Segmented (DESIGN_V2 6.11): options in a Well with an AccentSoft indicator that springs to the
-- selected label. More than 4 options, or a strip too wide for its row, renders as a field that
-- opens a list popover (same API). Without a Name the strip spans the row (v1).

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local Store = require("persist/Store")

local T, F, TS = Token.T, Token.F, Token.TS
local panels = setmetatable({}, { __mode = "k" }) -- popover content frame -> its pooled rows

local function list(raw)
	local out = {}
	if type(raw) == "table" then
		for _, item in ipairs(raw) do out[#out + 1] = tostring(item) end
	end
	if #out == 0 then out[1] = "None" end
	return out
end

local function first(raw)
	if type(raw) == "table" then raw = raw[1] end
	return raw ~= nil and tostring(raw) or nil
end

-- Segment widths (text + 24). A menu replaces a strip over 4 options, or one wider than 60 % of
-- the row (320 px at most; the whole row when there is no title).
local function measure(self)
	local size, total = Metrics.textSize("Body"), 6
	self._widths = {}
	for index, option in ipairs(self.Options) do
		self._widths[index] = RowView.textWidth(option, size) + 24
		total += self._widths[index]
	end
	local row = 0
	pcall(function() row = self._owner:_container().AbsoluteSize.X / (self._window._layers.scale or 1) end)
	if row <= 0 then row = 600 end
	self._menu = #self.Options > 4 or total > (self._bare and row - 32 or math.min(320, row * 0.6))
	if self._bare then return 0 end
	return self._menu and math.clamp(math.max(table.unpack(self._widths)) + 28, 160, 240) or total
end

-- ---------- the list popover (reuse "segmented": built once per window, rebound per open) ----------
local function row(panel, index)
	local scope = panel.scope
	local root = Factory.new(scope, "TextButton", { Name = "Option", BackgroundColor3 = T.Hover, BackgroundTransparency = 1, ZIndex = 6 }, panel.list)
	Factory.corner(scope, root, 8)
	local check = Factory.new(scope, "ImageLabel", { Name = "Check", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(14, 14), ZIndex = 7 }, root)
	Icons.apply(check, "check", scope, T.AccentText)
	local label = Factory.text(scope, "TextLabel", { Name = "Label", Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -40, 1, 0),
		FontFace = F.Label, TextSize = TS.Label, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, root)
	scope:connect(root.MouseEnter, function() root.BackgroundTransparency = 0 end)
	scope:connect(root.MouseLeave, function() root.BackgroundTransparency = 1 end)
	scope:connect(root.MouseButton1Click, function()
		local owner = panel.owner
		if not owner or owner._destroyed then return end
		owner._window._popover:close("pick")
		if not owner:_inactive() then owner:_setValue(owner.Options[index], { source = "user" }) end
	end)
	panel.rows[index] = { Root = root, Label = label, Check = check }
	return panel.rows[index]
end

local function openMenu(self)
	local host = self._window._popover
	if not host or self:_inactive() then return end
	if host:isOpen(self) then
		host:close("toggle")
		return
	end
	local height = Metrics.get("listRow")
	host:open({
		owner = self,
		anchor = self._track,
		reuse = "segmented",
		sheetOnPhone = true,
		maxHeight = 320,
		build = function(frame, scope)
			local scroller = Factory.new(scope, "ScrollingFrame", { Name = "List", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.new(), ZIndex = 5 }, frame)
			panels[frame] = { scope = scope, list = scroller, rows = {} }
			return Vector2.new(220, 200)
		end,
		bind = function(frame)
			local panel = panels[frame]
			panel.owner = self
			local options = self.Options
			for index, option in ipairs(options) do
				local item = panel.rows[index] or row(panel, index)
				item.Root.Visible = true
				item.Root.BackgroundTransparency = 1
				item.Root.Position = UDim2.fromOffset(6, 6 + (index - 1) * height)
				item.Root.Size = UDim2.new(1, -12, 0, height)
				item.Label.Text = option
				item.Check.Visible = option == self.CurrentValue
			end
			for index = #options + 1, #panel.rows do panel.rows[index].Root.Visible = false end
			panel.list.CanvasSize = UDim2.fromOffset(0, #options * height + 12)
			return Vector2.new(math.max(220, self._track.AbsoluteSize.X / (self._window._layers.scale or 1)), #options * height + 12)
		end,
	})
end

-- ---------- the strip or the field (rebuilt by Refresh) ----------
local function buildParts(self, view)
	if self._parts then self._parts:destroy() end
	local scope = self._scope:child("parts")
	self._parts = scope
	local height = Metrics.get("control")
	local frame = Factory.new(scope, "Frame", { Name = self._menu and "Field" or "Track", BackgroundColor3 = T.Well, ZIndex = 2 }, view.Root)
	if self._bare then
		frame.Position = UDim2.fromOffset(view.padH, RowView.bandY(view, height))
		frame.Size = UDim2.new(1, -2 * view.padH, 0, height)
	else
		RowView.control(view, frame, view.reserve, height)
	end
	Factory.corner(scope, frame, Metrics.radius.control)
	self._track = frame
	if self._menu then
		Factory.stroke(scope, frame, T.Border, 0, 1)
		self._value = Factory.text(scope, "TextLabel", { Name = "Value", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -40, 1, 0),
			FontFace = F.Body, TextSize = TS.Label, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, frame)
		local chevron = Factory.new(scope, "ImageLabel", { Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, frame)
		Icons.apply(chevron, "chevrons-up-down", scope, T.Text2)
		self._labels = nil
		return
	end
	self._indicator = Factory.new(scope, "Frame", { Name = "Indicator", BackgroundColor3 = T.AccentSoft, ZIndex = 3 }, frame)
	Factory.corner(scope, self._indicator, Metrics.radius.segment)
	self._ring = Factory.stroke(scope, self._indicator, T.Accent, 0.5, 1)
	local labels, x, count = {}, 3, #self.Options
	for index, option in ipairs(self.Options) do
		local width = self._widths[index]
		local label = Factory.text(scope, "TextButton", { Name = "Option", Text = option, FontFace = F.Button, TextSize = TS.Body,
			TextColor3 = T.Text2, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4,
			Position = self._bare and UDim2.new((index - 1) / count, 3 - 6 * (index - 1) / count, 0, 3) or UDim2.fromOffset(x, 3),
			Size = self._bare and UDim2.new(1 / count, -6 / count, 1, -6) or UDim2.new(0, width, 1, -6) }, frame)
		scope:connect(label.MouseButton1Click, function()
			if not self:_inactive() then self:_setValue(option, { source = "user" }) end
		end)
		labels[index] = label
		x += width
	end
	self._labels = labels
end

local function step(self, steps)
	local options = self.Options
	local index = table.find(options, self.CurrentValue) or 1
	local target = steps == math.huge and #options or steps == -math.huge and 1 or math.clamp(index + (steps > 0 and 1 or -1), 1, #options)
	self:_setValue(options[target], { source = "user" })
end

local Segmented = Element.define({
	Type = "Segmented",
	defaultName = "Segmented",
	flaggable = true,
	viewFields = { "_track" },

	init = function(self, config)
		self.Options = list(config.Options)
		self._bare = config.Name == nil and config.Title == nil
		local current = first(config.CurrentOption) or first(config.CurrentValue)
		self.CurrentValue = table.find(self.Options, current) and current or self.Options[1]
		self.CurrentOption = self.CurrentValue
	end,

	reserve = measure,

	build = function(self, view, scope)
		if self._bare and view.Title then view.Title.Visible = false end
		self._parts = nil
		buildParts(self, view)
		scope:connect(view.Root.MouseButton1Click, function()
			if self._menu then openMenu(self) end
		end)
	end,

	render = function(self, animated)
		local track = self._track
		if not track then return end
		local inactive, current = self:_inactive(), self.CurrentValue
		if self._menu then
			self._value.Text = current
			self._value.TextColor3 = Theme.get(inactive and "Disabled" or "Text")
			return
		end
		local selected = table.find(self.Options, current) or 1
		for index, label in ipairs(self._labels) do
			label.TextColor3 = Theme.get(inactive and "Disabled" or (index == selected and "AccentText" or "Text2"))
		end
		local target = self._labels[selected]
		Motion.spring(self._indicator, "Position", target.Position, "snappy", animated)
		Motion.spring(self._indicator, "Size", target.Size, "snappy", animated)
		self._indicator.BackgroundColor3 = Theme.get(inactive and "Active" or "AccentSoft")
		self._ring.Transparency = inactive and 1 or 0.5
	end,

	-- Unknown values are rejected; a flagged control parks them in the store's pending table (v1).
	normalize = function(self, raw)
		local value = first(raw)
		if value == nil then return nil end
		if table.find(self.Options, value) then return value end
		if self.Flag then Store.pending[self.Flag] = value end
		return nil
	end,

	mirror = function(self) self.CurrentOption = self.CurrentValue end,

	focus = {
		activate = function(self) if self._menu then openMenu(self) end end,
		adjust = step,
	},

	methods = {
		Set = function(self, value, silent)
			return self:_setValue(value, { silent = silent == true, source = "api" })
		end,

		-- New options: keeps a valid value, otherwise applies a value parked by Set or a restore
		-- once it exists, otherwise the first option. Fires no callback (v1).
		Refresh = function(self, options, keepCurrent)
			self.Options = list(options)
			local parked = self.Flag and Store.pending[self.Flag]
			parked = parked ~= nil and table.find(self.Options, tostring(parked)) and tostring(parked) or nil
			local value = self.Options[1]
			if keepCurrent ~= false and table.find(self.Options, self.CurrentValue) then
				value = self.CurrentValue
			elseif parked then
				value = parked
				Store.pending[self.Flag] = nil
			end
			self.CurrentValue, self.CurrentOption = value, value
			local host = self._window._popover
			if host and host:isOpen(self) then host:close("refresh") end
			if rawget(self, "_mounted") and self._view then
				RowView.setReserve(self, measure(self))
				buildParts(self, self._view)
				self:_render(false)
			end
			self:_noteChange()
			return self
		end,

		_searchOptions = function(self) return table.clone(self.Options) end,
	},
	aliases = { SetOptions = "Refresh" },

	unmount = function(self)
		local host = self._window._popover
		if host and host:isOpen(self) then host:close("unmount") end
		self._parts, self._track = nil, nil
	end,
})

return Segmented
