--!nocheck
-- A section is a header plus one grouped platter (DESIGN_V2 3.5, 6.1). Rows stack inside the
-- platter with inset dividers; one pooled hover frame per platter draws row hover.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Component = require("component/Component")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")

local T, F, TS = Token.T, Token.F, Token.TS
local Section = Component.extend({ ClassName = "Section", viewFields = { "Root", "Body", "Layout", "Header" } })

function Section.create(tab, config)
	if type(config) ~= "table" then config = { Title = config } end
	local name = tostring(config.Title or config.Name or "Section")
	local section = Section.new({
		Name = name,
		Tab = tab,
		Elements = {},
		Rows = {},
		_children = {},
		_icon = config.Icon,
		_desc = config.Description,
		_collapsible = config.Collapsible == true,
		_collapsed = config.Collapsed == true and config.Collapsible == true,
		_hidden = false,
	})
	section.Section = section
	tab._orderCounter += 1
	section._order = tab._orderCounter
	tab._sections[#tab._sections + 1] = section
	if tab._skeleton then section:_mountSkeleton() end
	tab:_sectionsChanged()
	return section
end

function Section:_ensureMounted()
	self.Tab:_ensureSkeleton()
end

-- Children (elements and rows) in creation order; returns the child's layout order.
function Section:_addChild(child)
	self.Tab._orderCounter += 1
	self._children[#self._children + 1] = child
	if child.Type ~= "Row" then self.Elements[#self.Elements + 1] = child end
	return self.Tab._orderCounter
end

function Section:_removeChild(child)
	for _, list in ipairs({ self._children, self.Elements, self.Rows }) do
		for index = #list, 1, -1 do
			if list[index] == child then table.remove(list, index) end
		end
	end
	self:_childVisibility()
end

function Section:_container()
	self.Tab:_ensureSkeleton()
	return rawget(self, "Body")
end

function Section:_mountSkeleton()
	if rawget(self, "Root") then return end
	local tab = self.Tab
	local scope = tab._pageScope:child("section")
	self._scope = scope
	local root = Factory.new(scope, "Frame", {
		Name = "Section",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._order,
	})
	Factory.list(scope, root, { Padding = UDim.new(0, 8) })
	local header = Factory.new(scope, "Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Metrics.get("header")),
		LayoutOrder = 1,
	}, root)
	local x = 4
	if self._icon then
		local icon = Factory.new(scope, "ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0, 4, 0.5, -8),
		}, header)
		Icons.apply(icon, self._icon, scope, T.Text2)
		x = 28
	end
	self._titleLabel = Factory.text(scope, "TextLabel", {
		Name = "Title",
		Text = self.Name,
		FontFace = F.Section,
		TextSize = TS.Section,
		TextColor3 = T.Text,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.new(1, -(x + 120), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, header)
	local platter = Factory.new(scope, "Frame", {
		Name = "Platter",
		BackgroundColor3 = T.Surface,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		ClipsDescendants = self._collapsed,
	}, root)
	Factory.corner(scope, platter, Metrics.radius.platter)
	self._edge = Factory.new(scope, "UIStroke", { Color = T.White, Transparency = 0.93, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, platter)
	self._edgeGradient = Factory.new(scope, "UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.75), NumberSequenceKeypoint.new(1, 1) }),
	}, self._edge)
	self._hover = Factory.new(scope, "Frame", {
		Name = "HoverFill",
		BackgroundColor3 = T.Hover,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
	}, platter)
	Factory.corner(scope, self._hover, Metrics.radius.hover)
	local body = Factory.new(scope, "Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Visible = not self._collapsed,
	}, platter)
	self.Layout = Factory.list(scope, body, { Padding = UDim.new(0, 0) })
	Factory.padding(scope, body, 0, 0, 4, 4)
	self.Root = root
	self.Header = header
	self.Body = body
	self._platter = platter
	if self._collapsible then self:_buildChevron() end
	self:_style()
	self:_childVisibility()
	root.Parent = tab._column
end

function Section:_buildChevron()
	local scope = self._scope
	local chevron = Factory.new(scope, "ImageButton", {
		Name = "Collapse", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(20, 20),
		Rotation = self._collapsed and -90 or 0,
	}, self.Header)
	Icons.apply(chevron, "chevron-down", scope, T.Text2)
	scope:connect(chevron.MouseButton1Click, function() self:ToggleCollapsed() end)
	self._chevron = chevron
end

-- Light themes get a Border stroke on platters; dark themes the lit edge.
function Section:_style()
	local edge = self._edge
	if not edge then return end
	local light = Theme.isLight()
	edge.Color = Theme.get(light and "Border" or "White")
	edge.Transparency = light and 0 or 0.93
	self._edgeGradient.Enabled = not light
end

function Section:_applyTheme()
	if self._scope then
		self._scope:repaint()
		self:_style()
	end
end

-- Recounts visible children: hides an empty platter and the divider above the first row.
function Section:_childVisibility()
	local any = false
	local first = true
	local afterRule = false
	for _, child in ipairs(self._children) do
		local visible = child:_isVisible()
		if visible then any = true end
		local view = rawget(child, "_view")
		if view and view.Divider then
			view.Divider.Visible = visible and not first and not afterRule
		end
		if visible then
			first = false
			afterRule = child.Type == "Divider" or child.Type == "Space"
		end
	end
	self._anyVisible = any
	local root = rawget(self, "Root")
	if root then
		root.Visible = any and not self._hidden
		self._platter.Visible = any
	end
	if self._resetButton then self:_refreshReset() end
end

function Section:_isVisible()
	return self._anyVisible ~= false and not self._hidden
end

function Section:_hoverRow(element, on)
	local fill = self._hover
	if not fill or not element.Root then return end
	if on then
		if element.Row then return end
		local root = element.Root
		local y = root.AbsolutePosition.Y - self._platter.AbsolutePosition.Y
		local scale = self.Tab.Window._layers and self.Tab.Window._layers.scale or 1
		fill.Position = UDim2.fromOffset(4, math.floor(y / scale) + 2)
		fill.Size = UDim2.new(1, -8, 0, math.floor(root.AbsoluteSize.Y / scale) - 4)
		fill.Visible = true
		self._hovered = element
		Motion.tween(fill, "hover", { BackgroundTransparency = 0 })
	elseif self._hovered == element then
		self._hovered = nil
		Motion.tween(fill, "hover", { BackgroundTransparency = 1 })
	end
end

-- ---------- public ----------
function Section:Set(name)
	self.Name = tostring(name)
	if self._titleLabel then self._titleLabel.Text = self.Name end
	self.Tab:_sectionsChanged()
	return self
end

function Section:SetVisible(visible)
	self._hidden = visible == false
	self:_childVisibility()
	return self
end

function Section:SetCollapsed(collapsed)
	if not self._collapsible then
		self._collapsible = true
		if self._scope then self:_buildChevron() end
	end
	self._collapsed = collapsed == true
	local body = rawget(self, "Body")
	if body then
		body.Visible = not self._collapsed
		self._platter.ClipsDescendants = self._collapsed
		if self._chevron then Motion.tween(self._chevron, "state", { Rotation = self._collapsed and -90 or 0 }) end
	end
	local window = self.Tab.Window
	if window._setCollapsedPref then window:_setCollapsedPref(self, self._collapsed) end
	return self
end

function Section:Collapse() return self:SetCollapsed(true) end
function Section:Expand() return self:SetCollapsed(false) end
function Section:ToggleCollapsed() return self:SetCollapsed(not self._collapsed) end
function Section:IsCollapsed() return self._collapsed == true end

function Section:Reset()
	local window = self.Tab.Window
	local count = window._changes:resetAll(self.Elements)
	if count > 0 and window._undoPill then window:_undoPill(("Reset %d setting%s"):format(count, count == 1 and "" or "s")) end
	return self
end

function Section:GetChangedCount()
	return self.Tab.Window._changes:count(self)
end

-- "Reset section" appears in the header while the section has changes.
function Section:_refreshReset()
	local count = self.Tab.Window._changes:count(self)
	if count > 0 and not self._resetButton and self._scope then
		local button = Factory.text(self._scope, "TextButton", {
			Name = "ResetSection", Text = "Reset section", FontFace = F.Caption, TextSize = TS.Caption,
			TextColor3 = T.Text2, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, self._chevron and -30 or -4, 0.5, 0),
			Size = UDim2.fromOffset(90, 24), TextXAlignment = Enum.TextXAlignment.Right,
		}, self.Header)
		self._scope:connect(button.MouseButton1Click, function() self:Reset() end)
		self._resetButton = button
	end
	if self._resetButton then self._resetButton.Visible = count > 0 end
end

return Section
