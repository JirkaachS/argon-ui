--!nocheck
-- A recycled-row list: only the visible rows (plus overscan) exist, so 10,000 items cost the
-- same as 10. Rows are built by spec.createRow and rebound by spec.bindRow on scroll.

local Factory = require("core/Factory")

local VirtualList = {}
VirtualList.__index = VirtualList

-- spec: { parent, rowHeight, overscan?, createRow(scope, parent, list) -> row, bindRow(row, item, index),
--         maxHeight?, height?, emptyView?(scope, parent) -> GuiObject, name? }
function VirtualList.new(scope, spec)
	local self = setmetatable({ scope = scope, spec = spec, items = {}, rows = {}, first = 1 }, VirtualList)
	local scroller = Factory.new(scope, "ScrollingFrame", {
		Name = spec.name or "VirtualList",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, spec.height or 0),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarImageTransparency = 0.5,
		ZIndex = spec.zindex or 1,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
	}, spec.parent)
	self.scroller = scroller
	scope:connect(scroller:GetPropertyChangedSignal("CanvasPosition"), function() self:_render() end)
	return self
end

function VirtualList:_viewport()
	return self.height or self.spec.height or self.spec.maxHeight or 300
end

function VirtualList:_render()
	local spec = self.spec
	local rowHeight = spec.rowHeight
	local count = #self.items
	local viewport = self:_viewport()
	local offset = self.scroller.CanvasPosition.Y
	local overscan = spec.overscan or 2
	local first = math.max(1, math.floor(offset / rowHeight) + 1 - overscan)
	local visible = math.ceil(viewport / rowHeight) + overscan * 2
	local last = math.min(count, first + visible - 1)
	self.first = first
	local needed = math.max(0, last - first + 1)
	while #self.rows < needed do
		self.rows[#self.rows + 1] = spec.createRow(self.scope, self.scroller, self)
	end
	for slot, row in ipairs(self.rows) do
		local index = first + slot - 1
		local frame = row.Root or row
		if index <= last then
			frame.Visible = true
			frame.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
			row.index = index
			spec.bindRow(row, self.items[index], index)
		else
			frame.Visible = false
			row.index = nil
		end
	end
	if self.empty then self.empty.Visible = count == 0 end
end

-- Replaces the items and re-renders the visible window.
function VirtualList:setData(items)
	self.items = items
	local spec = self.spec
	local total = #items * spec.rowHeight
	local height = spec.maxHeight and math.min(total, spec.maxHeight) or (spec.height or total)
	if spec.minHeight then height = math.max(height, spec.minHeight) end
	self.height = height
	self.scroller.Size = UDim2.new(1, 0, 0, height)
	self.scroller.CanvasSize = UDim2.fromOffset(0, total)
	if #items == 0 and spec.emptyView and not self.empty then
		self.empty = spec.emptyView(self.scope, self.scroller.Parent)
	end
	self:_render()
	return height
end

function VirtualList:refreshVisible()
	self:_render()
end

function VirtualList:rowFor(index)
	for _, row in ipairs(self.rows) do
		if row.index == index then return row end
	end
	return nil
end

function VirtualList:scrollTo(index)
	local rowHeight = self.spec.rowHeight
	local top = (index - 1) * rowHeight
	local viewport = self:_viewport()
	local current = self.scroller.CanvasPosition.Y
	if top < current then
		self.scroller.CanvasPosition = Vector2.new(0, top)
	elseif top + rowHeight > current + viewport then
		self.scroller.CanvasPosition = Vector2.new(0, top + rowHeight - viewport)
	end
	self:_render()
end

function VirtualList:count()
	return #self.items
end

function VirtualList:liveRows()
	return #self.rows
end

return VirtualList
