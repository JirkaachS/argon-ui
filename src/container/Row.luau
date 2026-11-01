--!nocheck
-- A multi-column row inside a section (v1 contract): Columns[i] = {Holder, Layout, Section},
-- round-robin placement and Use(i). Columns wrap into a stack through engine flex layout,
-- so a row costs no Lua size listeners.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Env = require("core/Env")
local Component = require("component/Component")

local T = Token.T
local Row = Component.extend({ ClassName = "Row", viewFields = { "Root", "Layout" } })

local Column = {}
-- Columns[i].Holder and .Layout are built on first read, like an element's Root.
local COLUMN_VIEW = { Holder = true, Layout = true }
Column.__index = function(column, key)
	local method = Column[key]
	if method ~= nil then return method end
	if COLUMN_VIEW[key] then
		rawget(column, "_row"):_ensureMounted()
		return rawget(column, key)
	end
	return nil
end

function Row.create(section, config)
	if type(config) ~= "table" then config = { Columns = tonumber(config) } end
	local count = math.clamp(math.floor(tonumber(config.Columns) or 2), 1, 4)
	local row = Row.new({
		Type = "Row",
		Name = tostring(config.Name or section.Name),
		Owner = section,
		Section = section,
		Elements = {},
		Columns = {},
		_spacing = math.clamp(tonumber(config.Spacing) or 7, 0, 24),
		_minWidth = math.clamp(tonumber(config.MinColumnWidth) or 200, 80, 400),
		_next = 1,
		_tab = section.Tab,
	})
	for index = 1, count do
		row.Columns[index] = setmetatable({ index = index, Row = row, Section = section, _row = row, _children = {} }, Column)
	end
	row._order = section:_addChild(row)
	section.Rows[#section.Rows + 1] = row
	-- v1 seams, called with dot syntax by scripts and tests; layout is engine flex now.
	row._balance = function() return row end
	row._relayout = function() return row end
	return row
end

function Row:_ensureMounted()
	if rawget(self, "_mounted") then return end
	local body = self.Section:_container()
	local scope = self.Section.Tab._pageScope:child("row")
	self._scope = scope
	self._mounted = true
	local root = Factory.new(scope, "Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._order,
	})
	local layout = Factory.list(scope, root, {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, self._spacing),
	})
	Env.try(layout, "Wraps", true)
	Env.try(layout, "HorizontalFlex", Env.enum("UIFlexAlignment", "Fill"))
	for index, column in ipairs(self.Columns) do
		local holder = Factory.new(scope, "Frame", {
			Name = "Column",
			BackgroundTransparency = 1,
			Size = UDim2.new(1 / #self.Columns, -self._spacing, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
		}, root)
		local columnLayout = Factory.list(scope, holder, {})
		pcall(function()
			Factory.new(scope, "UIFlexItem", { FlexMode = Env.enum("UIFlexMode", "Fill") }, holder)
		end)
		Factory.new(scope, "UISizeConstraint", { MinSize = Vector2.new(self._minWidth, 0) }, holder)
		if index > 1 then
			Factory.new(scope, "Frame", {
				Name = "Rule", BackgroundColor3 = T.BorderSoft, Size = UDim2.new(0, 1, 1, -24),
				Position = UDim2.new(0, -math.ceil(self._spacing / 2), 0, 12),
			}, holder)
		end
		column.Holder = holder
		column.Layout = columnLayout
	end
	self.Root = root
	self.Layout = layout
	self:_childVisibility()
	root.Parent = body
end

-- Rows count as visible when any of their controls is.
function Row:_isVisible()
	for _, element in ipairs(self.Elements) do
		if element:_isVisible() then return true end
	end
	return #self.Elements == 0
end

function Row:_childVisibility()
	local root = rawget(self, "Root")
	if root then root.Visible = self:_isVisible() end
	self.Section:_childVisibility()
end

-- Sends the next control to column i.
function Row:Use(index)
	self._next = math.clamp(math.floor(tonumber(index) or 1), 1, #self.Columns)
	return self
end

function Row:_column()
	local column = self.Columns[self._next]
	self._next = self._next % #self.Columns + 1
	return column
end

-- ---------- column (the owner of controls inside a row) ----------
function Column:_addChild(element)
	local row = self._row
	self._children[#self._children + 1] = element
	row.Elements[#row.Elements + 1] = element
	local section = row.Section
	section.Elements[#section.Elements + 1] = element
	section.Tab._orderCounter += 1
	return section.Tab._orderCounter
end

function Column:_removeChild(element)
	for _, list in ipairs({ self._children, self._row.Elements, self._row.Section.Elements }) do
		for index = #list, 1, -1 do
			if list[index] == element then table.remove(list, index) end
		end
	end
	self._row:_childVisibility()
end

function Column:_container()
	self._row:_ensureMounted()
	return self.Holder
end

function Column:_childVisibility()
	self._row:_childVisibility()
end

return Row
