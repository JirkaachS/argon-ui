--!nocheck
-- List (DESIGN_V2 6.19): a titled list virtualised by layers/VirtualList, so only visible rows
-- exist. Rows are 36 px (44 when any item has a Description): icon or avatar, title, description,
-- up to InlineActions inline actions and the rest behind an ellipsis menu. Records keep their
-- identity, so callbacks always receive the same table (CB-15). Filter, empty state, Rename.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Util = require("core/Util")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local VirtualList = require("layers/VirtualList")
local ContextMenu = require("layers/ContextMenu")

local T, F, TS = Token.T, Token.F, Token.TS
local Base = Element.Base
local GAP, FILTER_AT = 4, 8

local function str(value)
	return value ~= nil and tostring(value) or ""
end

local function actionsOf(record)
	local list = record.Actions
	if type(list) == "table" and #list > 0 then return list end
	if record.Action ~= nil then return { record.Action } end
	return nil
end

local function labelOf(entry)
	if type(entry) == "table" then return str(entry.Label or entry.Title or entry.Text or entry.Name) end
	return str(entry)
end

-- A table item is its own record; a string becomes { Title = item } (reused across SetItems).
local function adopt(self, item, previous)
	if type(item) == "table" then
		if item.Title == nil and item.Name ~= nil then item.Title = item.Name end
		return item
	end
	local title = str(item)
	local record = previous and previous[title]
	if record then
		previous[title] = nil
	else
		record = { Title = title }
	end
	self._raw[record] = item
	return record
end

-- Index of a record by identity, Id, Title, or (for a number) position.
local function find(self, target)
	for index, record in ipairs(self.Items) do
		if record == target or (target ~= nil and (record.Id == target or (record.Id == nil and record.Title == target))) then
			return index
		end
	end
	if type(target) == "number" and self.Items[target] then return target end
	return nil
end

-- Runs an action (or the row) with (record, item). A danger action asks first when the list has
-- ConfirmDelete (or the action has Confirm).
local function fire(self, record, entry, confirmed)
	if self:_inactive() then return end
	if not confirmed and type(entry) == "table" and entry.Style == "danger" and (self._cfg.ConfirmDelete or entry.Confirm) then
		local label = labelOf(entry)
		self._window:Confirm({ Title = label .. " " .. str(record.Title) .. "?", ConfirmText = label,
			OnConfirm = function() fire(self, record, entry, true) end })
		return
	end
	local fn = type(entry) == "table" and entry.Callback or record.Callback or self._callback
	Util.xcall(fn, self:_context(), self, record, self._raw[record] or record)
end

-- Row fill: Active plus a 2 px Accent bar when selected, Hover under the pointer.
local function paint(self, row)
	local frame, record = row.Root, row.record
	local selected = record ~= nil and record == self.Selected
	frame.BackgroundColor3 = Theme.get(selected and "Active" or "Hover")
	frame.BackgroundTransparency = (selected or row.hover) and 0 or 1
	local bar = self._bar
	if selected then
		if not bar then
			bar = Factory.new(self._scope, "Frame", { Name = "Selected", BackgroundColor3 = T.Accent, Position = UDim2.new(0, 3, 0, 10), ZIndex = 2 })
			Factory.corner(self._scope, bar, "full")
			self._bar = bar
		end
		bar.Size = UDim2.new(0, 2, 1, -20)
		bar.Parent = frame
		bar.Visible = true
	elseif bar and bar.Parent == frame then
		bar.Visible = false
	end
end

local function repaint(self)
	local vl = self._vl
	if not vl then return end
	for _, row in ipairs(vl.rows) do
		if row.index then paint(self, row) end
	end
end

local function choose(self, record)
	if self.Selected == record then return end
	self.Selected = record
	repaint(self)
end

local refresh -- defined below; renames and the filter box re-run it

local function commitRename(self, enter)
	local row, box = self._renaming, self._renameBox
	if not row then return end
	self._renaming = nil
	box.Parent = nil
	local record, text = row.record, Util.trim(box.Text)
	if not enter or not record or text == "" or text == record.Title then return end
	local old = record.Title
	record.Title = text
	local cfg = self._cfg
	local ok, accepted = Util.xcall(type(cfg.Rename) == "function" and cfg.Rename or cfg.OnRename, self:_context() .. " Rename", self, record, text, old)
	if ok and accepted == false then record.Title = old end
	refresh(self)
end

-- Rename in place: the title becomes a TextBox; Enter commits, anything else reverts.
local function rename(self, row)
	if not row.record or self:_inactive() then return end
	local box = self._renameBox
	if not box then
		box = Factory.text(self._scope, "TextBox", {
			Name = "Rename", FontFace = F.Label, TextSize = TS.Label, BackgroundTransparency = 0,
			BackgroundColor3 = T.Well, ClearTextOnFocus = false, ZIndex = 4,
		})
		Factory.corner(self._scope, box, 6)
		self._scope:connect(box.FocusLost, function(enter) commitRename(self, enter) end)
		self._renameBox = box
	end
	self._renaming = row
	box.Text = str(row.record.Title)
	box.Size = UDim2.new(1, row.title.Size.X.Offset + 8, 0, 24)
	box.Position = UDim2.fromOffset(row.title.Position.X.Offset - 4, math.floor((self._rowH - 24) / 2))
	box.Parent = row.Root
	box:CaptureFocus()
end

local function openMore(self, row)
	local record = row.record
	if not record or self:_inactive() then return end
	local items = {}
	local list = actionsOf(record) or {}
	for index = self._inline + 1, #list do
		local entry = list[index]
		local spec = type(entry) == "table" and entry or {}
		items[#items + 1] = { Text = labelOf(entry), Icon = spec.Icon, Danger = spec.Style == "danger",
			Callback = function() fire(self, record, entry) end }
	end
	if self._cfg.Rename then
		items[#items + 1] = { Text = "Rename", Icon = "pencil", Callback = function() rename(self, row) end }
	end
	ContextMenu.open(self._window, row.more, items)
end

local function click(self, row)
	local record = row.record
	if not record or self:_inactive() then return end
	local now = os.clock()
	if self._cfg.Rename and row.last and now - row.last < 0.4 then
		row.last = nil
		return rename(self, row)
	end
	row.last = now
	choose(self, record)
	if not actionsOf(record) then fire(self, record, nil) end
end

local function makeRow(self, scope, parent)
	local frame = Factory.new(scope, "Frame", {
		Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, self._rowH),
	}, parent)
	Factory.corner(scope, frame, 8)
	local hit = Factory.new(scope, "ImageButton", {
		Name = "Hit", BackgroundTransparency = 1, ImageTransparency = 1, Size = UDim2.fromScale(1, 1),
	}, frame)
	local row = { Root = frame, hit = hit, buttons = {}, icons = {} }
	row.title = Factory.text(scope, "TextLabel", {
		Name = "Title", FontFace = F.Label, TextSize = TS.Label, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
	}, frame)
	scope:connect(hit.MouseButton1Click, function() click(self, row) end)
	local function hover(on)
		if on and self._window._router.lastInputKind == "touch" then return end
		row.hover = on
		paint(self, row)
	end
	scope:connect(hit.MouseEnter, function() hover(true) end)
	scope:connect(hit.MouseLeave, function() hover(false) end)
	return row
end

local function makeButton(self, row, index)
	local scope = self._scope
	local button = Factory.text(scope, "TextButton", {
		Name = "Action", FontFace = F.Button, TextSize = TS.Caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
	}, row.Root)
	Factory.corner(scope, button, 8)
	scope:connect(button.MouseButton1Click, function()
		local record = row.record
		local list = record and actionsOf(record)
		if list and list[index] ~= nil then fire(self, record, list[index]) end
	end)
	scope:connect(button.MouseEnter, function() button.BackgroundTransparency = 0 end)
	scope:connect(button.MouseLeave, function() button.BackgroundTransparency = 1 end)
	return button
end

local function bind(self, row, record)
	if row.record == record and row.stamp == self._stamp then return end -- a scroll within the same rows
	if self._renaming == row and row.record ~= record then self._renameBox:ReleaseFocus(false) end
	row.record, row.stamp = record, self._stamp
	local scope, h, frame = self._scope, self._rowH, row.Root
	frame.Size = UDim2.new(1, 0, 0, h)
	local inactive = self._disabled or self._whenDisabled
	-- leading icon (16) or avatar (24, round)
	local avatar = record.Avatar
	local lead = avatar ~= nil and ("rbxthumb://type=AvatarHeadShot&id=" .. str(avatar) .. "&w=48&h=48") or record.Icon
	if lead ~= nil and not row.lead then
		row.lead = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, ZIndex = 2 }, frame)
		row.leadCorner = Factory.corner(scope, row.lead, 0)
	end
	local x = 10
	if row.lead then
		row.lead.Visible = lead ~= nil
		if lead ~= nil then
			local size = avatar ~= nil and 24 or 16
			row.lead.Size = UDim2.fromOffset(size, size)
			row.lead.Position = UDim2.fromOffset(avatar ~= nil and 10 or 14, math.floor((h - size) / 2))
			row.leadCorner.CornerRadius = UDim.new(avatar ~= nil and 1 or 0, 0)
			Icons.apply(row.lead, lead)
			row.lead.ImageColor3 = avatar ~= nil and Theme.get("White") or (typeof(record.Color) == "Color3" and record.Color or Theme.get("Text2"))
			x = 42
		end
	end
	-- actions, laid out from the right edge
	local list = actionsOf(record)
	local count = list and #list or 0
	local inline = math.min(count, self._inline)
	local right = 8
	local more = count > inline or (self._cfg.Rename and true or false)
	if more and not row.more then
		row.more = Factory.new(scope, "ImageButton", { Name = "More", BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), ZIndex = 3 }, frame)
		Icons.apply(row.more, "ellipsis")
		scope:connect(row.more.MouseButton1Click, function() openMore(self, row) end)
	end
	if row.more then
		row.more.Visible = more
		row.more.ImageColor3 = Theme.get("Text2")
		row.more.Position = UDim2.new(1, -(right + 28), 0, math.floor((h - 28) / 2))
		if more then right += 28 + GAP end
	end
	for index = 1, inline do
		row.buttons[index] = row.buttons[index] or makeButton(self, row, index)
	end
	for index = inline, 1, -1 do
		local entry, button = list[index], row.buttons[index]
		local spec = type(entry) == "table" and entry or {}
		local text = labelOf(entry)
		local width = spec.Icon and 28 or (RowView.textWidth(text, 12) + 20)
		local tone = spec.Style == "danger" and "Danger" or spec.Style == "warning" and "Warning" or nil
		local ink = inactive and Theme.get("Disabled") or typeof(spec.Color) == "Color3" and spec.Color or Theme.get(tone or "AccentText")
		button.Visible = true
		button.Text = spec.Icon and "" or text
		button.TextColor3 = ink
		button.BackgroundColor3 = Theme.get(tone and tone .. "Soft" or "Hover")
		button.BackgroundTransparency = 1
		button.Size = UDim2.fromOffset(width, 28)
		button.Position = UDim2.new(1, -(right + width), 0, math.floor((h - 28) / 2))
		right += width + GAP
		local icon = row.icons[index]
		if spec.Icon and not icon then
			icon = Factory.new(scope, "ImageLabel", {
				Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 4,
			}, button)
			row.icons[index] = icon
		end
		if icon then
			icon.Visible = spec.Icon ~= nil
			if spec.Icon then
				Icons.apply(icon, spec.Icon)
				icon.ImageColor3 = ink
			end
		end
	end
	for index = inline + 1, #row.buttons do
		row.buttons[index].Visible = false
	end
	-- title and description
	local desc = record.Description
	local hasDesc = desc ~= nil and desc ~= ""
	if hasDesc and not row.desc then
		row.desc = Factory.text(scope, "TextLabel", {
			Name = "Description", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2,
		}, frame)
	end
	local top = math.floor((h - 34) / 2)
	row.title.Text = str(record.Title)
	row.title.TextColor3 = inactive and Theme.get("Disabled") or typeof(record.Color) == "Color3" and record.Color or Theme.get("Text")
	row.title.Position = UDim2.fromOffset(x, hasDesc and top or 0)
	row.title.Size = UDim2.new(1, -(x + right + 4), 0, hasDesc and 18 or h)
	if row.desc then
		row.desc.Visible = hasDesc
		row.desc.Text = str(desc)
		row.desc.Position = UDim2.fromOffset(x, top + 18)
		row.desc.Size = UDim2.new(1, -(x + right + 4), 0, 16)
	end
	paint(self, row)
end

local function makeEmpty(self, scope, parent)
	local frame = Factory.new(scope, "Frame", { Name = "Empty", BackgroundTransparency = 1 }, parent)
	local action = self._cfg.EmptyAction
	local block = type(action) == "table" and 88 or 50
	local icon = Factory.new(scope, "ImageLabel", {
		Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0.5, -12, 0.5, -block / 2),
	}, frame)
	Icons.apply(icon, "inbox", scope, T.Text2)
	self._emptyText = Factory.text(scope, "TextLabel", {
		Name = "Text", Text = self._emptyCopy, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 16, 0.5, -block / 2 + 32), Size = UDim2.new(1, -32, 0, 18),
	}, frame)
	if type(action) == "table" then
		local button = Factory.text(scope, "TextButton", {
			Name = "Action", Text = str(action.Text or action.Title or action.Name), FontFace = F.Button, TextSize = TS.Button,
			BackgroundColor3 = T.Active, BackgroundTransparency = 0, AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -block / 2 + 60), Size = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
		}, frame)
		Factory.corner(scope, button, "full")
		Factory.padding(scope, button, 14, 14, 0, 0)
		scope:connect(button.MouseButton1Click, function()
			if not self:_inactive() then Util.xcall(action.Callback, self:_context() .. " EmptyAction", self) end
		end)
	end
	return frame
end

-- State -> view: row height, filter, data, sizes and the counter; visible rows rebind.
function refresh(self)
	self._stamp = (self._stamp or 0) + 1
	local described = false
	for _, record in ipairs(self.Items) do
		if record.Description ~= nil and record.Description ~= "" then
			described = true
			break
		end
	end
	self._rowH = Metrics.get("listRow") + (described and 8 or 0)
	local vl = self._vl
	if not vl then
		self._data = self.Items
		return
	end
	local view, scope = self._view, self._scope
	local filterOn = self._cfg.Filter and #self.Items > FILTER_AT
	local box = self._filterBox
	if filterOn and not box then
		box = Factory.text(scope, "TextBox", {
			Name = "Filter", PlaceholderColor3 = T.Dim, BackgroundColor3 = T.Well, BackgroundTransparency = 0,
			ClearTextOnFocus = false, Position = UDim2.fromOffset(view.padH, view.band), Size = UDim2.new(1, -view.padH * 2, 0, 28),
		}, view.Root)
		Factory.corner(scope, box, 8)
		Factory.padding(scope, box, 10, 10, 0, 0)
		scope:connect(box:GetPropertyChangedSignal("Text"), function()
			self._query = box.Text:lower()
			refresh(self)
		end)
		self._filterBox = box
	end
	if box then
		box.Visible = filterOn and true or false
		box.PlaceholderText = ("Filter %d items"):format(#self.Items)
		if not filterOn and box.Text ~= "" then box.Text = "" end
	end
	local data, query = self.Items, filterOn and self._query or ""
	if query ~= "" then
		data = {}
		for _, record in ipairs(self.Items) do
			if (str(record.Title) .. " " .. str(record.Description)):lower():find(query, 1, true) then data[#data + 1] = record end
		end
	end
	self._data = data
	vl.spec.rowHeight = self._rowH
	vl.spec.minHeight = #data == 0 and 104 or nil
	local height = vl:setData(data)
	local top = view.band + (filterOn and 36 or 0)
	vl.scroller.Position = UDim2.fromOffset(0, top)
	if vl.empty then
		vl.empty.Position = UDim2.fromOffset(0, top)
		vl.empty.Size = UDim2.new(1, 0, 0, height)
		self._emptyText.Text = query ~= "" and "No items match" or self._emptyCopy
	end
	local total = top + height + 8
	view.Root.Size = UDim2.new(1, 0, 0, total)
	local desc = view.Description
	if desc and desc.Visible then
		desc.Position = UDim2.fromOffset(view.padH, total - 2)
		desc.Size = UDim2.new(1, -view.padH * 2, 0, 0)
	end
	local n = #self.Items
	self._count.Text = query ~= "" and ("%d of %d"):format(#data, n) or (n == 1 and "1 item" or n .. " items")
end

-- After SetItems the selection follows its key (Id, else Title) to the new record.
local function reselect(self)
	local selected = self.Selected
	if selected == nil or table.find(self.Items, selected) then return end
	self.Selected = nil
	for _, record in ipairs(self.Items) do
		if record.Id == selected.Id and (selected.Id ~= nil or record.Title == selected.Title) then
			self.Selected = record
			break
		end
	end
end

-- Drops the view references (unmount for a density change, or Destroy).
local function forget(self)
	self._vl, self._count, self._filterBox, self._bar, self._renameBox, self._renaming, self._emptyText = nil, nil, nil, nil, nil, nil, nil
end

return Element.define({
	Type = "List",
	defaultName = "List",

	init = function(self, config)
		self._height = math.clamp(math.floor(tonumber(config.Height) or 156), 80, 420)
		self._max = tonumber(config.MaxHeight) and math.clamp(math.floor(config.MaxHeight), 80, 800) or nil
		self._emptyCopy = str(config.EmptyText ~= nil and config.EmptyText or "No items")
		self._inline = math.clamp(math.floor(tonumber(config.InlineActions) or 3), 0, 6)
		self._raw = setmetatable({}, { __mode = "k" })
		self._query = ""
		self.Items = {}
		self.CurrentValue = self.Items
		for index, item in ipairs(type(config.Items) == "table" and config.Items or {}) do
			self.Items[index] = adopt(self, item)
		end
		refresh(self)
	end,

	reserve = function()
		return 80
	end,

	build = function(self, view, scope)
		self._count = Factory.text(scope, "TextLabel", {
			Name = "Count", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -view.padH, 0, 0), Size = UDim2.fromOffset(80, view.band),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, view.Root)
		local vl = VirtualList.new(scope, {
			parent = view.Root, name = "Rows", rowHeight = self._rowH, overscan = 1,
			height = not self._max and self._height or nil, maxHeight = self._max,
			createRow = function(rowScope, parent) return makeRow(self, rowScope, parent) end,
			bindRow = function(row, record) bind(self, row, record) end,
			emptyView = function(emptyScope, parent) return makeEmpty(self, emptyScope, parent) end,
		})
		Factory.padding(scope, vl.scroller, 8, 8, 0, 0)
		self._vl = vl
	end,

	-- After mount, theme changes and lock/disable: re-lay out and rebind the visible rows.
	render = function(self)
		local vl = self._vl
		if not vl then return end
		vl.scroller.ScrollBarImageColor3 = Theme.get("Track")
		refresh(self)
	end,

	focus = {
		activate = function(self)
			local record = self.Selected or self._data[1]
			if not record then return end
			choose(self, record)
			local list = actionsOf(record)
			fire(self, record, list and list[1] or nil)
		end,
		adjust = function(self, step)
			local data = self._data
			if #data == 0 then return end
			local index = table.find(data, self.Selected) or 0
			index = math.abs(step) == math.huge and (step > 0 and #data or 1) or math.clamp(index + step, 1, #data)
			choose(self, data[index])
			if self._vl then self._vl:scrollTo(index) end
		end,
	},

	unmount = forget,
	destroy = forget,

	methods = {
		SetItems = function(self, items)
			local previous = {}
			for _, record in ipairs(self.Items) do
				if self._raw[record] ~= nil then previous[str(record.Title)] = record end
			end
			local records = {}
			for index, item in ipairs(type(items) == "table" and items or {}) do
				records[index] = adopt(self, item, previous)
			end
			table.clear(self.Items)
			table.move(records, 1, #records, 1, self.Items)
			reselect(self)
			refresh(self)
			return self
		end,

		AddItem = function(self, item)
			self.Items[#self.Items + 1] = adopt(self, item)
			refresh(self)
			return self
		end,

		RemoveItem = function(self, target)
			local index = find(self, target)
			if index then
				local record = table.remove(self.Items, index)
				if self.Selected == record then self.Selected = nil end
				refresh(self)
			end
			return self
		end,

		UpdateItem = function(self, target, patch)
			local index = find(self, target)
			if index and type(patch) == "table" then
				local record = self.Items[index]
				for key, value in pairs(patch) do record[key] = value end
				refresh(self)
			end
			return self
		end,

		Clear = function(self)
			table.clear(self.Items)
			self.Selected = nil
			refresh(self)
			return self
		end,

		-- Selects a record (no callback); nil clears the selection.
		Select = function(self, target)
			local index = target ~= nil and find(self, target) or nil
			choose(self, index and self.Items[index] or nil)
			if index and self._vl then
				local at = table.find(self._data, self.Items[index])
				if at then self._vl:scrollTo(at) end
			end
			return self
		end,

		GetSelected = function(self)
			return self.Selected
		end,

		SetDesc = function(self, text)
			Base.SetDesc(self, text)
			refresh(self)
			return self
		end,

		_searchOptions = function(self)
			local out = {}
			for index = 1, math.min(#self.Items, 50) do out[index] = str(self.Items[index].Title) end
			return out
		end,
	},
	aliases = { Set = "SetItems" },
})
