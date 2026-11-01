--!nocheck
-- Dropdown (DESIGN_V2 6.15, D12): single or multi select over string or rich options. The trigger
-- is a Well showing the value or chips; the panel is the window's pooled popover ("dropdown") with
-- search, a multi-select header and a VirtualList, so 10,000 options cost what 10 do.

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
local Store = require("persist/Store")
local VirtualList = require("layers/VirtualList")
local Field = require("controls/Input").Field

local T, F, TS = Token.T, Token.F, Token.TS
local panels = setmetatable({}, { __mode = "k" })

-- ---------- options ----------
local function textOf(item)
	return type(item) == "table" and item.text or item
end

local function optionText(value)
	if type(value) == "table" then value = value.Text or value.Name or value.Title end
	return value ~= nil and tostring(value) or nil
end

local function off(item)
	return type(item) == "table" and item.disabled
end

-- A list of plain strings needs only clones and a set; rich entries become records.
local function setOptions(self, list)
	list = type(list) == "table" and list or {}
	local set, plain = {}, true
	self._descs, self._icons, self._lower = false, false, nil
	for _, entry in ipairs(list) do
		if type(entry) ~= "string" then
			plain = false
			break
		end
		set[entry] = true
	end
	if plain then
		self.Options, self._items, self._set = table.clone(list), table.clone(list), set
		self._searchIndex = nil
		return
	end
	self.Options = Util.copy(list)
	local items, rule = {}, false
	set = {}
	for _, entry in ipairs(list) do
		local text = optionText(entry)
		if type(entry) == "table" and text then
			local desc = entry.Description ~= nil and tostring(entry.Description) or nil
			items[#items + 1] = { text = text, desc = desc, icon = entry.Icon, disabled = entry.Disabled == true, rule = rule or entry.Divider == true }
			self._descs = self._descs or desc ~= nil
			self._icons = self._icons or entry.Icon ~= nil
		elseif type(entry) == "table" then
			rule = rule or entry.Divider ~= nil
		elseif text then
			items[#items + 1] = rule and { text = text, rule = true } or text
		end
		if text then
			set[text] = true
			rule = false
		end
	end
	self._items, self._set = items, set
	self._searchIndex = nil
end

local function asList(value)
	if type(value) == "table" then
		if value.Text ~= nil or value.Name ~= nil then return { value } end
		return value
	end
	return value == nil and {} or { value }
end

-- The requested values that exist, deduplicated; single select keeps the first match.
local function pick(self, wanted)
	local out, seen = {}, {}
	for _, value in ipairs(wanted) do
		local text = optionText(value)
		if text and self._set[text] and not seen[text] then
			seen[text] = true
			out[#out + 1] = text
			if not self._multi then break end
		end
	end
	return out
end

local function texts(wanted, multi)
	local out, seen = {}, {}
	for _, value in ipairs(wanted) do
		local text = optionText(value)
		if text and not seen[text] then
			seen[text] = true
			out[#out + 1] = text
			if not multi then break end
		end
	end
	return out
end

local function sourceList(kind)
	local out = {}
	pcall(function()
		if kind == "Players" then
			for _, player in ipairs(Env.services.Players:GetPlayers()) do
				local name, display = player.Name, player.DisplayName
				out[#out + 1] = (display and display ~= name) and { Text = name, Description = display } or name
			end
		else
			for _, team in ipairs(Env.services.Teams:GetTeams()) do out[#out + 1] = team.Name end
		end
	end)
	return out
end

-- A user change: remembered as the desired selection, committed with source "user".
local function choose(self, list)
	self._desiredOption = Util.copy(list)
	return self:_setValue(list, { source = "user" })
end

-- ---------- pooled panel (one per window, rebound on every open) ----------
local Panel = {}
Panel.__index = Panel

function Panel:row(scope, parent)
	local root = Factory.new(scope, "TextButton", { Name = "Option", BackgroundTransparency = 1, ZIndex = 6 }, parent)
	local row = {
		Root = root,
		check = Factory.new(scope, "ImageLabel", { Name = "Check", BackgroundTransparency = 1, ZIndex = 7 }, root),
		label = Factory.text(scope, "TextLabel", { Name = "Label", TextSize = TS.Input, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, root),
	}
	scope:connect(root.MouseButton1Click, function() if row.index then self:activate(row.index) end end)
	scope:connect(root.MouseEnter, function() if row.index then self:highlight(row.index, "hover") end end)
	return row
end

function Panel:bindRow(row, item, index)
	local owner = self.owner
	if not owner then return end
	local rh, scope = self.rh, self.scope
	local text, rich = textOf(item), type(item) == "table" and item or nil
	local disabled = rich and rich.disabled
	local selected = self.selected[text] == true
	row.Root.Size = UDim2.new(1, 0, 0, rh)
	local check = row.check
	local size = owner._multi and 16 or 14
	check.Visible = owner._multi or selected
	if check.Visible then
		Icons.apply(check, owner._multi and (selected and "square-check" or "square") or "check", nil)
		check.ImageColor3 = Theme.get(disabled and "Disabled" or (selected and (owner._multi and "Accent" or "AccentText") or "Text2"))
		check.Size = UDim2.fromOffset(size, size)
		check.Position = UDim2.fromOffset(12 + (16 - size) / 2, math.floor((rh - size) / 2))
	end
	local x = 36
	local icon = rich and rich.icon
	if icon and not row.icon then
		row.icon = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), ZIndex = 7 }, row.Root)
	end
	if row.icon then
		row.icon.Visible = icon ~= nil
		if icon then
			Icons.apply(row.icon, icon, nil)
			row.icon.ImageColor3 = Theme.get(disabled and "Disabled" or "Text2")
			row.icon.Position = UDim2.fromOffset(x, math.floor((rh - 16) / 2))
		end
	end
	if owner._icons then x += 24 end
	local desc = rich and rich.desc
	if desc and not row.desc then
		row.desc = Factory.text(scope, "TextLabel", { Name = "Description", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, row.Root)
	end
	if row.desc then
		row.desc.Visible = desc ~= nil
		if desc then
			row.desc.Text = desc
			row.desc.Position = UDim2.fromOffset(x, math.floor(rh / 2))
			row.desc.Size = UDim2.new(1, -(x + 12), 0, 16)
		end
	end
	local label = row.label
	label.Text = text
	label.TextColor3 = Theme.get(disabled and "Disabled" or "Text")
	label.Position = UDim2.fromOffset(x, desc and math.floor(rh / 2) - 18 or 0)
	label.Size = UDim2.new(1, -(x + 12), 0, desc and 18 or rh)
	local ruled = rich and rich.rule and index > 1
	if ruled and not row.rule then
		row.rule = Factory.new(scope, "Frame", { Name = "Rule", BackgroundColor3 = T.BorderSoft, Size = UDim2.new(1, -16, 0, 1), Position = UDim2.fromOffset(8, 0), ZIndex = 7 }, row.Root)
	end
	if row.rule then row.rule.Visible = ruled == true end
end

function Panel:highlight(index, how)
	self.hi, self.how = index, how
	local frame, item = self.hiFrame, self.shown and self.shown[index]
	if not item or off(item) then
		frame.Visible = false
		return
	end
	frame.Visible = true
	frame.Position = UDim2.fromOffset(4, (index - 1) * self.rh + 1)
	frame.Size = UDim2.new(1, -8, 0, self.rh - 2)
	frame.BackgroundColor3 = Theme.get(how == "key" and "Active" or "Hover")
end

function Panel:move(step)
	local shown = self.shown
	local n = #shown
	if n == 0 then return end
	local index = self.hi
	if step == -math.huge then index, step = 0, 1 elseif step == math.huge then index, step = n + 1, -1 end
	for _ = 1, n do
		local nextIndex = index + step
		if nextIndex < 1 or nextIndex > n then break end
		index = nextIndex
		if not off(shown[index]) then break end
	end
	if index < 1 or index > n or off(shown[index]) then return end
	self:highlight(index, "key")
	self.list:scrollTo(index)
end

-- Type-ahead without a search box: jump to the next option starting with the letter.
function Panel:jump(letter)
	local shown, n = self.shown, #self.shown
	for step = 1, n do
		local index = (self.hi + step - 1) % n + 1
		local item = shown[index]
		if not off(item) and textOf(item):sub(1, 1):lower() == letter then
			self:highlight(index, "key")
			self.list:scrollTo(index)
			return
		end
	end
end

function Panel:activate(index)
	local owner = self.owner
	local item = self.shown and self.shown[index]
	if not owner or not item or off(item) or owner:_inactive() then return end
	local text = textOf(item)
	self.hi = index
	if owner._multi then
		local list = Util.copy(owner.CurrentValue)
		local at = table.find(list, text)
		if at then table.remove(list, at) else list[#list + 1] = text end
		choose(owner, list)
	else
		choose(owner, { text })
		owner._window._popover:close("pick")
	end
end

-- Selected set, header count and the visible rows after a value change.
function Panel:sync()
	local owner = self.owner
	local selected = {}
	for _, text in ipairs(owner.CurrentValue) do selected[text] = true end
	self.selected = selected
	self.count.Text = ("%d of %d selected"):format(#owner.CurrentValue, #owner._items)
	self.list:refreshVisible()
end

function Panel:filter(query, keep)
	local owner = self.owner
	self.query = query or ""
	local items = owner._items
	local shown = items
	if self.query ~= "" then
		local lower = owner._lower
		if not lower then
			lower = table.create(#items)
			for index, item in ipairs(items) do lower[index] = string.lower(textOf(item)) end
			owner._lower = lower
		end
		local needle = string.lower(self.query)
		shown = {}
		for index, item in ipairs(items) do
			if string.find(lower[index], needle, 1, true) then shown[#shown + 1] = item end
		end
	end
	self.shown = shown
	if not keep or not shown[self.hi] then
		self.hi = 0
		for index, item in ipairs(shown) do
			if not off(item) and (self.selected[textOf(item)] or self.hi == 0) then
				self.hi = index
				if self.selected[textOf(item)] then break end
			end
		end
	end
	self:layout()
end

-- On-demand parts of the panel (spinner, empty state, hint, phone sheet header).
function Panel:part(key, make)
	local part = self[key]
	if not part then
		part = make(self.scope, self.frame)
		self[key] = part
	end
	return part
end

local function caption(scope, frame, name, color)
	return Factory.text(scope, "TextLabel", { Name = name, FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = color or T.Text2, ZIndex = 6 }, frame)
end

function Panel:layout()
	local owner = self.owner
	local width, rh = self.width, self.rh
	local y = 8
	if self.sheet then
		local head = self:part("head", function(scope, frame)
			local grab = Factory.new(scope, "Frame", { Name = "Grab", BackgroundColor3 = T.Border, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(40, 5), ZIndex = 6 }, frame)
			Factory.corner(scope, grab, "full")
			local title = Factory.text(scope, "TextLabel", { Name = "SheetTitle", FontFace = F.Label, TextSize = TS.Label, Size = UDim2.new(1, -64, 0, 32), Position = UDim2.fromOffset(16, 18), ZIndex = 6 }, frame)
			local close = Factory.new(scope, "ImageButton", { Name = "Close", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 20), Size = UDim2.fromOffset(28, 28), ZIndex = 6 }, frame)
			Icons.apply(close, "x", scope, T.Text2)
			scope:connect(close.MouseButton1Click, function() if self.owner then self.host:close("close") end end)
			return { grab = grab, title = title, close = close }
		end)
		head.grab.Position = UDim2.new(0.5, 0, 0, 6)
		head.title.Text = owner.Name
		y = 56
	end
	if self.head then
		for _, part in pairs(self.head) do part.Visible = self.sheet == true end
	end
	self.search.Visible = self.searchable
	if self.searchable then
		self.search.Position = UDim2.fromOffset(8, y)
		self.box.PlaceholderText = ("Filter %d options"):format(#owner._items)
		y += 44
	end
	local multi = owner._multi
	self.count.Visible, self.all.Visible, self.clear.Visible = multi, multi, multi
	if multi then
		self.count.Position = UDim2.fromOffset(14, y)
		self.all.Position = UDim2.new(1, -60, 0, y)
		self.clear.Position = UDim2.new(1, -12, 0, y)
		y += 28
	end
	local hint = not self.sheet and (Router.lastInputKind == "keyboard" or Router.lastInputKind == "gamepad")
	local room = math.max(rh * 3, math.floor((self.maxHeight - y - 8 - (hint and 24 or 0)) / rh) * rh)
	self.list.spec.maxHeight = room
	self.list.spec.rowHeight = rh
	self.list.scroller.Position = UDim2.fromOffset(0, y)
	local height = self.list:setData(self.shown)
	local loading = owner._loading == true
	if self.spin then self.spin.Visible = loading end
	if loading then
		local spin = self:part("spin", function(scope, frame)
			local label = caption(scope, frame, "Loading", T.Muted)
			label.Text = "Loading options\u{2026}"
			local icon = Factory.new(scope, "ImageLabel", { Name = "Spinner", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, -22, 0.5, -8), ZIndex = 6 }, label)
			Icons.apply(icon, "loader-circle", scope, T.Text2)
			self.spinIcon = icon
			return label
		end)
		spin.Position = UDim2.fromOffset(40, y + height)
		spin.Size = UDim2.new(1, -52, 0, rh)
		if not self.loop then self.loop = Motion.loop(self.spinIcon, "spinner", { Rotation = 360 }) end
		height += rh
	elseif self.loop then
		self.loop.stop()
		self.loop = nil
	end
	local empty = #self.shown == 0 and not loading
	if self.empty then
		self.empty.Visible = empty
		self.emptyClear.Visible = empty and self.query ~= ""
	end
	if empty then
		local label = self:part("empty", function(scope, frame)
			local text = caption(scope, frame, "Empty", T.Muted)
			text.TextXAlignment = Enum.TextXAlignment.Center
			text.TextTruncate = Enum.TextTruncate.AtEnd
			local clear = Factory.text(scope, "TextButton", { Name = "ClearFilter", Text = "Clear filter", FontFace = F.Caption, TextSize = TS.Caption,
				TextColor3 = T.AccentText, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(90, 24), ZIndex = 6 }, frame)
			scope:connect(clear.MouseButton1Click, function() if self.owner then self.box.Text = "" end end)
			self.emptyClear = clear
			return text
		end)
		label.Text = self.query ~= "" and ("No options match '" .. self.query .. "'") or "No options"
		label.Position = UDim2.fromOffset(12, y + 6)
		label.Size = UDim2.new(1, -24, 0, 24)
		self.emptyClear.Position = UDim2.new(0.5, 0, 0, y + 30)
		self.emptyClear.Visible = self.query ~= ""
		height = self.query ~= "" and 60 or 36
	end
	y += height + 8
	self.hint.Visible = hint
	if hint then
		self.hint.Text = Router.lastInputKind == "gamepad" and "A Select \u{00B7} B Close" or "\u{2191} \u{2193} Move \u{00B7} Enter Select"
		self.hint.Position = UDim2.fromOffset(14, y - 4)
		y += 20
	end
	self.size = Vector2.new(width, y)
	self:highlight(self.hi, self.how)
	return self.size
end

local function buildPanel(frame, scope, host)
	local p = setmetatable({ frame = frame, scope = scope, host = host, hi = 0, rh = 32, selected = {}, shown = {}, query = "" }, Panel)
	local search = Factory.new(scope, "Frame", { Name = "Search", BackgroundColor3 = T.Well, Size = UDim2.new(1, -16, 0, 36), ZIndex = 5 }, frame)
	Factory.corner(scope, search, Metrics.radius.control)
	local icon = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 10, 0.5, -8), ZIndex = 6 }, search)
	Icons.apply(icon, "search", scope, T.Text2)
	p.search = search
	p.box = Field.box(scope, search, { Name = "Filter", Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -42, 1, 0), ZIndex = 6 })
	p.count = caption(scope, frame, "Count")
	p.count.Size = UDim2.new(1, -150, 0, 24)
	local function link(name, text, width)
		local button = Factory.text(scope, "TextButton", { Name = name, Text = text, FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.AccentText,
			AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(width, 24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, frame)
		scope:connect(button.MouseButton1Click, function() if p.owner then p.owner:_bulk(name == "SelectAll") end end)
		return button
	end
	p.all, p.clear = link("SelectAll", "Select all", 64), link("Clear", "Clear", 40)
	p.hint = caption(scope, frame, "Hint", T.Dim)
	p.hint.Size = UDim2.new(1, -28, 0, 20)
	p.list = VirtualList.new(scope, {
		parent = frame, rowHeight = 32, overscan = 1, maxHeight = 288, name = "Options", zindex = 5,
		createRow = function(rowScope, parent) return p:row(rowScope, parent) end,
		bindRow = function(row, item, index) p:bindRow(row, item, index) end,
	})
	p.hiFrame = Factory.new(scope, "Frame", { Name = "Highlight", BackgroundColor3 = T.Hover, Visible = false, ZIndex = 5 }, p.list.scroller)
	Factory.corner(scope, p.hiFrame, 8)
	scope:connect(p.list.scroller.MouseLeave, function() if p.how == "hover" then p.hiFrame.Visible = false end end)
	scope:connect(p.box:GetPropertyChangedSignal("Text"), function()
		if p.owner and not p.binding then
			p:filter(p.box.Text)
			if p.owner._handle then p.owner._handle.resize(p.size) end
		end
	end)
	scope:connect(p.box.FocusLost, function(enter) if enter and p.owner then p:activate(p.hi) end end)
	panels[frame] = p
	return Vector2.new(240, 200)
end

-- Rebinds the pooled panel to a dropdown; returns the panel size.
function Panel:attach(owner, width, maxHeight, sheet)
	self.owner, self.width, self.maxHeight, self.sheet = owner, width, maxHeight, sheet
	self.rh = sheet and 52 or (Field.touch() and 44 or (owner._descs and 48 or 32))
	self.searchable = owner:_searchable()
	self.how = nil
	self.binding = true
	self.box.Text = ""
	self.binding = false
	self.list.scroller.CanvasPosition = Vector2.zero
	local selected = {}
	for _, text in ipairs(owner.CurrentValue) do selected[text] = true end
	self.selected = selected
	self.count.Text = ("%d of %d selected"):format(#owner.CurrentValue, #owner._items)
	self:filter("", false)
	if self.hi > 0 then self.list:scrollTo(self.hi) end
	return self.size
end

function Panel:detach(owner)
	if self.owner ~= owner then return end
	if self.box:IsFocused() then self.box:ReleaseFocus() end
	if self.loop then
		self.loop.stop()
		self.loop = nil
	end
	self.owner = nil
end

-- ---------- open and close ----------
local function keyFor(self, p, input)
	local key = input.KeyCode and input.KeyCode.Name or ""
	if key == "Down" or key == "DPadDown" then p:move(1)
	elseif key == "Up" or key == "DPadUp" then p:move(-1)
	elseif key == "Home" then p:move(-math.huge)
	elseif key == "End" then p:move(math.huge)
	elseif key == "Return" or key == "ButtonA" or key == "Space" then p:activate(p.hi)
	elseif #key == 1 and not p.searchable then p:jump(key:lower())
	else return false end
	return true
end

local function closed(self)
	for _, handle in ipairs(self._keys or {}) do
		if handle.remove then handle.remove() else handle:unbind() end
	end
	self._keys = nil
	if self._panel then self._panel:detach(self) end
	self._panel, self._handle, self._open = nil, nil, false
	if not self._destroyed then self:_render(true) end
end

local function load(self)
	if self._loading then return end
	self._loading = true
	task.spawn(function()
		local ok, result = Util.xcall(self._loader, self:_context() .. " Options", self)
		self._loading = false
		if self._destroyed then return end
		if ok and type(result) == "table" then
			self:Refresh(result)
		elseif self._panel then
			self._panel:filter(self._panel.query, true)
			if self._handle then self._handle.resize(self._panel.size) end
		end
	end)
end

local function toggle(self)
	local window = self._window
	local host = window and window._popover
	if not host or not self._field or self:_inactive() then return end
	if host:isOpen(self) then
		host:close("toggle")
		return
	end
	if self._source then self:Refresh(sourceList(self._source)) end
	if self._loader then load(self) end
	local layers = window._layers
	local width = math.max(math.floor(self._field.AbsoluteSize.X / (layers.scale or 1)), 240)
	local sheet = Platform.isPhone(layers:guiSize())
	local maxHeight = sheet and math.max(200, math.floor(layers:localSize().Y * 0.8) - 28) or 360
	self._open = true
	self:_render(true)
	local handle = host:open({
		owner = self, anchor = self._field, reuse = "dropdown", name = "Dropdown", width = width, maxHeight = maxHeight, sheetOnPhone = true,
		build = buildPanel,
		bind = function(frame) return panels[frame]:attach(self, width, maxHeight, sheet) end,
		onClose = function() closed(self) end,
	})
	local p = panels[handle.content]
	self._handle, self._panel = handle, p
	local function typing(code, fn)
		return Router.bind({ key = Env.enum("KeyCode", code), mode = "Press", priority = 90, allowWhileTyping = true, allowProcessed = true, onPress = fn })
	end
	self._keys = {
		Router.layerKey(function(input) return keyFor(self, p, input) end, 90),
		typing("Down", function() if Router.typing() then p:move(1) end end),
		typing("Up", function() if Router.typing() then p:move(-1) end end),
		typing("Backspace", function() if Router.typing() and p.box:IsFocused() and p.box.Text == "" then host:close("closekey") end end),
	}
	if p.searchable and not Field.touch() and Router.lastInputKind ~= "gamepad" then p.box:CaptureFocus() end
end

-- ---------- trigger ----------
local function chip(self, index)
	local scope, list = self._scope, self._chipViews
	local view = list[index]
	if view then return view end
	local root = Factory.new(scope, "Frame", { Name = "Chip", BackgroundColor3 = T.Raised, ZIndex = 3 }, self._field)
	Factory.corner(scope, root, Metrics.radius.chip)
	local label = Factory.text(scope, "TextLabel", { Name = "Label", FontFace = F.Caption, TextSize = TS.Caption, Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -26, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 }, root)
	local remove = Factory.new(scope, "ImageButton", { Name = "Remove", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(12, 12), ZIndex = 4 }, root)
	Icons.apply(remove, "x", scope, T.Text2)
	view = { Root = root, label = label }
	scope:connect(remove.MouseButton1Click, function()
		if self:_inactive() or not view.text then return end
		local rest = Util.copy(self.CurrentValue)
		local at = table.find(rest, view.text)
		if at then
			table.remove(rest, at)
			choose(self, rest)
		end
	end)
	list[index] = view
	return view
end

-- Up to MaxVisibleChips chips plus "+N"; false when the field shows text instead.
local function chips(self)
	local field, selection = self._field, self.CurrentValue
	local width = field.Size.X.Offset
	local h = field.Size.Y.Offset
	local use = self._multi and #selection > 0 and width >= 160 and self._chips > 0
	self._chipViews = self._chipViews or {}
	local x, count = 6, 0
	if use then
		for index = 1, math.min(#selection, self._chips) do
			local text = selection[index]
			local w = math.min(RowView.textWidth(text, 12) + 30, 120)
			if x + w > width - 36 - (index < #selection and 34 or 0) then break end
			local view = chip(self, index)
			view.text = text
			view.Root.Visible = true
			view.Root.Position = UDim2.fromOffset(x, math.floor((h - 22) / 2))
			view.Root.Size = UDim2.fromOffset(w, 22)
			view.label.Text = text
			view.label.TextColor3 = Theme.get(self:_inactive() and "Disabled" or "Text")
			x += w + 4
			count = index
		end
	end
	for index, view in pairs(self._chipViews) do
		if index > count then view.Root.Visible = false end
	end
	local rest = count > 0 and #selection - count or 0
	if rest > 0 and not self._plus then
		self._plus = Factory.text(self._scope, "TextLabel", { Name = "More", BackgroundColor3 = T.Raised, BackgroundTransparency = 0, FontFace = F.Caption,
			TextSize = TS.Caption, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, field)
		Factory.corner(self._scope, self._plus, Metrics.radius.chip)
	end
	if self._plus then
		self._plus.Visible = rest > 0
		self._plus.Text = "+" .. rest
		self._plus.Position = UDim2.fromOffset(x, math.floor((h - 22) / 2))
		self._plus.Size = UDim2.fromOffset(30, 22)
	end
	return count > 0
end

local Dropdown = Element.define({
	Type = "Dropdown",
	defaultName = "Dropdown",
	flaggable = true,

	init = function(self, config)
		self._multi = config.MultipleOptions == true
		self._placeholder = tostring(config.Placeholder or "Select\u{2026}")
		self._chips = math.max(0, math.floor(tonumber(config.MaxVisibleChips) or 2))
		self._source = (config.Source == "Players" or config.Source == "Teams") and config.Source or nil
		self._loader = type(config.Options) == "function" and config.Options or nil
		setOptions(self, type(config.Options) == "table" and config.Options or (self._source and sourceList(self._source)) or {})
		local wanted = config.CurrentOption
		if wanted == nil then wanted = config.CurrentValue end
		wanted = asList(wanted)
		self._desiredOption = texts(wanted, true)
		-- options from a function are unknown until it runs: keep the requested selection as given
		local selection = self._loader and texts(wanted, self._multi) or pick(self, wanted)
		self.CurrentValue = selection
		self.CurrentOption = selection
	end,

	reserve = function(self)
		return Field.width(self, 160, 260)
	end,

	build = function(self, view, scope)
		local h = Metrics.get("control")
		local field, stroke = Field.well(scope, view.Root, "Frame", { Name = "Field", ZIndex = 2 }, Field.radius(h))
		RowView.control(view, field, view.reserve, h)
		self._value = Factory.text(scope, "TextLabel", { Name = "Value", TextSize = TS.Input, Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -40, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, field)
		self._chevron = Factory.new(scope, "ImageLabel", { Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, field)
		Icons.apply(self._chevron, "chevrons-up-down", nil)
		self._field, self._stroke, self._chipViews, self._plus = field, stroke, {}, nil
		scope:connect(view.Root.MouseButton1Click, function() toggle(self) end)
		Field.track(self, view, scope, 160, 260, function(w)
			field.Size = UDim2.fromOffset(w, h)
			self:_render(false)
		end)
	end,

	render = function(self, animated)
		local field = self._field
		if not field then return end
		local inactive = self:_inactive()
		Field.paint(self._stroke, inactive and "disabled" or (self._open and "focus") or (self._hovering and "hover") or "rest", animated)
		self._chevron.ImageColor3 = Theme.get(inactive and "Disabled" or (self._open and "Text" or "Text2"))
		local selection = self.CurrentValue
		local hasChips = chips(self)
		self._value.Visible = not hasChips
		if not hasChips then
			local empty = #selection == 0
			self._value.Text = empty and self._placeholder or ((not self._multi or #selection == 1) and selection[1] or (#selection .. " selected"))
			self._value.TextColor3 = Theme.get(inactive and "Disabled" or (empty and "Dim" or "Text"))
		end
		local p = self._panel
		if p and p.owner == self then p:sync() end
	end,

	hover = function(self, on)
		self._hovering = on
		if self._stroke and not self._open and not self:_inactive() then Field.paint(self._stroke, on and "hover" or "rest", true) end
	end,

	normalize = function(self, raw)
		return pick(self, asList(raw))
	end,

	mirror = function(self)
		self.CurrentOption = self.CurrentValue
	end,

	payload = function(self)
		return Util.copy(self.CurrentValue)
	end,

	describe = function(_, value)
		if type(value) ~= "table" or #value == 0 then return "none" end
		return (table.concat(value, ", "):gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
	end,

	focus = {
		activate = function(self) toggle(self) end,
		-- Left and Right on the closed trigger step through the options (single select).
		adjust = function(self, step)
			if self._multi then return end
			local choices = {}
			for _, item in ipairs(self._items) do
				if not off(item) then choices[#choices + 1] = textOf(item) end
			end
			if #choices == 0 then return end
			local at = table.find(choices, self.CurrentValue[1]) or 0
			local target = step == -math.huge and 1 or (step == math.huge and #choices or math.clamp(at + (step > 0 and 1 or -1), 1, #choices))
			choose(self, { choices[target] })
		end,
	},

	unmount = function(self)
		local host = self._window and self._window._popover
		if host and host:isOpen(self) then host:close("unmount") end
		self._field, self._stroke, self._value, self._chevron, self._chipViews, self._plus = nil, nil, nil, nil, nil, nil
	end,

	methods = {
		-- Unknown values are ignored (the selection stays); the request is remembered and, for a
		-- flagged control with no match, parked as a pending flag value.
		Set = function(self, value, silent)
			local wanted = asList(value)
			self._desiredOption = texts(wanted, true)
			local picked = pick(self, wanted)
			if #picked == 0 and #wanted > 0 then
				if self.Flag then Store.pending[self.Flag] = Util.copy(self._desiredOption) end
				return self
			end
			return self:_setValue(picked, { silent = silent == true, source = "api" })
		end,
		-- New options; surviving selections stay. When none survive and the remembered request is
		-- now present it is applied through the commit path (callback, listeners, autosave once);
		-- a dropped selection fires nothing.
		Refresh = function(self, options, keepCurrent)
			if options == nil then
				if self._loader then
					load(self)
					return self
				end
				options = self._source and sourceList(self._source) or self.Options
			end
			setOptions(self, options)
			local current, kept = self.CurrentValue, {}
			if keepCurrent ~= false then
				for _, text in ipairs(current) do
					if self._set[text] then kept[#kept + 1] = text end
				end
			end
			local applied = false
			if #kept == 0 and keepCurrent ~= false and self._desiredOption then
				local picked = pick(self, self._desiredOption)
				if #picked > 0 and not Util.jsonEqual(picked, current) then
					if self.Flag and Store.pending[self.Flag] ~= nil then Store.pending[self.Flag] = nil end
					self:_setValue(picked, { source = "api" })
					applied = true
				end
			end
			if not applied and not Util.jsonEqual(kept, current) then self:_setValue(kept, { silent = true }) end
			self:_render(false)
			local p = self._panel
			if p and p.owner == self then
				p.searchable = self:_searchable()
				p:filter(p.query, true)
				if self._handle then self._handle.resize(p.size) end
			end
			return self
		end,
		GetSelected = function(self)
			return Util.copy(self.CurrentValue)
		end,
		Open = function(self)
			if not (self._window._popover and self._window._popover:isOpen(self)) then toggle(self) end
			return self
		end,
		Close = function(self)
			local host = self._window._popover
			if host and host:isOpen(self) then host:close("api") end
			return self
		end,
		IsOpen = function(self)
			return self._open == true
		end,
		_searchable = function(self)
			local searchable = self._cfg.Searchable
			if searchable ~= nil then return searchable == true end
			return #self._items > 8
		end,
		_bulk = function(self, all)
			if self:_inactive() then return end
			local list = {}
			if all then
				local p = self._panel
				for _, item in ipairs(p and p.owner == self and p.shown or self._items) do
					if not off(item) then list[#list + 1] = textOf(item) end
				end
				if p and p.query ~= "" then
					for _, text in ipairs(self.CurrentValue) do
						if not table.find(list, text) then list[#list + 1] = text end
					end
				end
			end
			choose(self, list)
		end,
		_searchOptions = function(self)
			local out = {}
			for index, item in ipairs(self._items) do out[index] = textOf(item) end
			return out
		end,
	},
	aliases = { SetOptions = "Refresh" },
})

return Dropdown
