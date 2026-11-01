--!nocheck
-- A tab is state until it is shown: CreateTab costs microseconds, its page skeleton is built
-- detached, and its controls are mounted by a scheduler job (active tab first, the others in
-- the background after the window opens). Inactive pages are detached from the tree.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Scheduler = require("core/Scheduler")
local Component = require("component/Component")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Section = require("container/Section")
local Row = require("container/Row")

local T, F, TS = Token.T, Token.F, Token.TS
local Tab = Component.extend({
	ClassName = "Tab",
	viewFields = { "TabButton", "Accent", "IconBox", "Icon", "ButtonTitle", "Count", "Page", "PageGroup" },
})

function Tab.create(window, name, icon, options)
	if type(icon) == "table" and options == nil then
		options, icon = icon, icon.Icon
	end
	options = type(options) == "table" and options or {}
	local tab = Tab.new({
		Name = tostring(name or "Tab"),
		IconName = icon ~= nil and tostring(icon) or "activity",
		Window = window,
		Group = options.Group,
		Description = options.Description,
		_sections = {},
		_elements = {},
		_controlCount = 0,
		_orderCounter = 0,
		_mountIndex = 1,
		_mountedCount = 0,
		_skeleton = false,
	})
	tab._pageScope = window._scope:child("tab:" .. tab.Name)
	tab._pageScope.isTab = true
	return tab
end

-- ---------- builders ----------
function Tab:CreateSection(config)
	local section = Section.create(self, config)
	self._currentSection = section
	return section
end
Tab.Section = Tab.CreateSection

function Tab:_currentOrDefault()
	local section = self._currentSection
	if not section then
		section = Section.create(self, "General")
		self._currentSection = section
	end
	return section
end

function Tab:CreateRow(config)
	return Row.create(self:_currentOrDefault(), config)
end
Tab.Row = Tab.CreateRow

function Tab:_addElement(element, counts)
	self._elements[#self._elements + 1] = element
	self._controlCount += 1
	if counts and self._countChanged then self:_countChanged() end
end

function Tab:_removeElement(element)
	for index = #self._elements, 1, -1 do
		if self._elements[index] == element then
			table.remove(self._elements, index)
			if index < self._mountIndex then self._mountIndex -= 1 end
		end
	end
	self._controlCount = math.max(0, self._controlCount - 1)
	if element._mountedCounted then self._mountedCount -= 1 end
end

-- ---------- mounting ----------
function Tab:_ensureMounted()
	if rawget(self, "_mounted") then return end
	self._mounted = true
	self.Window:_ensureNav(self)
	self:_ensureSkeleton()
end

function Tab:_ensureSkeleton()
	if self._skeleton then return end
	self._skeleton = true
	local scope = self._pageScope
	local group = Factory.new(scope, "Frame", {
		Name = "PageGroup",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	local page = Factory.new(scope, "ScrollingFrame", {
		Name = "Page",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = T.Track,
		ElasticBehavior = Enum.ElasticBehavior and Enum.ElasticBehavior.WhenScrollable or nil,
	}, group)
	Factory.list(scope, page, { HorizontalAlignment = Enum.HorizontalAlignment.Center })
	Factory.padding(scope, page, 28, 28, 24, 40)
	local column = Factory.new(scope, "Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, page)
	self._columnLimit = Factory.new(scope, "UISizeConstraint", { MaxSize = Vector2.new(680, math.huge) }, column)
	self._columnLayout = Factory.list(scope, column, { Padding = UDim.new(0, Metrics.get("sectionGap")) })
	local header = Factory.new(scope, "Frame", {
		Name = "PageHeader",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 0,
	}, column)
	self._pageTitle = Factory.text(scope, "TextLabel", {
		Name = "Title",
		Text = self.Name,
		FontFace = F.Page,
		TextSize = TS.Page,
		Size = UDim2.new(1, -180, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, header)
	if self.Description and self.Description ~= "" then
		Factory.text(scope, "TextLabel", {
			Name = "Description",
			Text = tostring(self.Description),
			FontFace = F.Body,
			TextSize = TS.Body,
			TextColor3 = T.Muted,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, -180, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, header)
	end
	self._pageHeader = header
	self.PageGroup = group
	self.Page = page
	self._column = column
	for _, section in ipairs(self._sections) do section:_mountSkeleton() end
	scope:connect(page:GetPropertyChangedSignal("CanvasPosition"), function()
		if self.Window._pageScrolled then self.Window:_pageScrolled(self) end
	end)
	self:_refreshEmpty()
	self.Window:_pageBuilt(self)
end

function Tab:_noteMounted(element)
	if not element._mountedCounted then
		element._mountedCounted = true
		self._mountedCount += 1
	end
	if self.Window._loaderProgress then self.Window:_loaderProgress(self) end
end

-- Mounts this tab's controls in creation order within the scheduler's deadline.
function Tab:_runMount(deadline)
	self:_ensureSkeleton()
	local list = self._elements
	while self._mountIndex <= #list do
		local element = list[self._mountIndex]
		self._mountIndex += 1
		if not element._destroyed and not rawget(element, "_mounted") then
			element:_mount()
		end
		if deadline and Env.clock() >= deadline then
			return self._mountIndex > #list
		end
	end
	return true
end

function Tab:_fullyMounted()
	return self._skeleton and self._mountIndex > #self._elements
end

function Tab:_enqueue(priority)
	if self:_fullyMounted() then return end
	Scheduler.enqueue({
		key = self,
		priority = priority,
		label = "mount " .. self.Name,
		run = function(deadline)
			Env.profileBegin("Argon/mount")
			local done = self:_runMount(deadline)
			Env.profileEnd()
			if done then self.Window:_tabMounted(self) end
			return done
		end,
	})
end

-- Called for every Create* on this tab.
function Tab:_noteElement(element)
	local window = self.Window
	if window._destroyed then return end
	if window._loading and window._loader then window._loader:activity() end
	if window.ActiveTab == self then
		self:_enqueue(1)
	elseif window._revealed and window._prewarm ~= false then
		self:_enqueue(3)
	end
	if self._skeleton then self:_refreshEmpty() end
end

-- Mounts everything now (a cold tab switch flushes up to the viewport synchronously).
function Tab:_mountNow(limit)
	self:_ensureSkeleton()
	if limit then
		local target = math.min(#self._elements, self._mountIndex + limit - 1)
		while self._mountIndex <= target do
			local element = self._elements[self._mountIndex]
			self._mountIndex += 1
			if not element._destroyed and not rawget(element, "_mounted") then element:_mount() end
		end
		if not self:_fullyMounted() then self:_enqueue(1) end
	else
		Scheduler.cancel(self)
		self:_runMount(nil)
	end
end

function Tab:_sectionsChanged()
	local window = self.Window
	if window.ActiveTab == self and window._refreshSectionMenu then window:_refreshSectionMenu() end
end

function Tab:_visibilityChanged()
	-- reserved for the empty state and badges
end

function Tab:_refreshEmpty()
	local column = self._column
	if not column then return end
	local empty = #self._elements == 0
	if empty and not self._empty then
		local scope = self._pageScope
		local frame = Factory.new(scope, "Frame", {
			Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), LayoutOrder = 100000,
		}, column)
		local icon = Factory.new(scope, "ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24),
			Position = UDim2.new(0.5, -12, 0, 24) }, frame)
		Icons.apply(icon, "circle-dashed", scope, T.Text2)
		Factory.text(scope, "TextLabel", { Name = "Title", Text = "Nothing here yet", FontFace = F.Label, TextSize = TS.Label,
			TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 20) }, frame)
		self._empty = frame
	end
	if self._empty then self._empty.Visible = empty end
end

-- Drops every mounted instance (density change); state is kept and remounted on demand.
function Tab:_unmount()
	if not self._skeleton then return end
	Scheduler.cancel(self)
	self:_hide()
	self._pageScope:clear()
	self._skeleton = false
	self._mounted = false
	self._mountIndex = 1
	self._mountedCount = 0
	self._empty = nil
	self._changedChip = nil
	for _, key in ipairs({ "PageGroup", "Page", "_column", "_columnLimit", "_columnLayout", "_pageHeader", "_pageTitle" }) do
		self[key] = nil
	end
	for _, section in ipairs(self._sections) do
		for _, key in ipairs({ "Root", "Body", "Layout", "Header", "_platter", "_hover", "_edge", "_edgeGradient", "_titleLabel", "_chevron", "_resetButton", "_scope" }) do
			section[key] = nil
		end
		for _, row in ipairs(section.Rows) do
			row._mounted = false
			row.Root, row.Layout, row._scope = nil, nil, nil
			for _, column in ipairs(row.Columns) do column.Holder, column.Layout = nil, nil end
		end
	end
	for _, element in ipairs(self._elements) do
		element._mountedCounted = nil
		if rawget(element, "_mounted") then
			element._mounted = false
			element._scope = nil
			element._view = nil
			for _, key in ipairs({ "Root", "_title", "_description", "_tipMarker", "_lock" }) do element[key] = nil end
			if element._spec.unmount then element._spec.unmount(element) end
		end
	end
end

-- ---------- visibility ----------
function Tab:_show(host)
	self:_ensureSkeleton()
	if self._stale then self:_repaint() end
	self.PageGroup.Parent = host
end

function Tab:_hide()
	local group = rawget(self, "PageGroup")
	if group then group.Parent = nil end
end

-- Re-applies the theme and state to every mounted part of this tab.
function Tab:_repaint()
	self._stale = false
	if not self._skeleton then return end
	Env.profileBegin("Argon/theme")
	self._pageScope:repaint()
	for _, section in ipairs(self._sections) do section:_style() end
	for _, element in ipairs(self._elements) do
		if rawget(element, "_mounted") then
			element:_render(false)
			element._styleVersion = self.Window._styleVersion
		end
	end
	Env.profileEnd()
end

-- ---------- quick filter (v1 seam) ----------
function Tab:_filter(query)
	query = string.lower(tostring(query or ""))
	local filtering = query ~= ""
	for _, element in ipairs(self._elements) do
		local section = element.Section
		local match = not filtering
			or string.find(string.lower(tostring(element.Name)), query, 1, true) ~= nil
			or (section and string.find(string.lower(tostring(section.Name)), query, 1, true) ~= nil)
		local filtered = not match
		if (element._filtered == true) ~= filtered then
			element._filtered = filtered
			if filtered and not rawget(element, "_mounted") then
				-- nothing to hide yet
			end
			element:_applyVisibility()
		end
	end
	local window = self.Window
	if window._setJumpRailFiltered then window._setJumpRailFiltered(filtering) end
end

-- ---------- v2 API ----------
function Tab:Select()
	self.Window:SelectTab(self)
	return self
end

function Tab:SetBadge(value)
	self._badge = value
	if self.Window._renderBadge then self.Window:_renderBadge(self) end
	return self
end

function Tab:GetChangedCount()
	return self.Window._changes:count(self)
end

function Tab:Reset()
	local window = self.Window
	local count = window._changes:resetAll(self._elements)
	if count > 0 and window._undoPill then window:_undoPill(("Reset %d setting%s"):format(count, count == 1 and "" or "s")) end
	return self
end

function Tab:SetTitle(name)
	self.Name = tostring(name)
	if self._pageTitle then self._pageTitle.Text = self.Name end
	if self.Window._renderNav then self.Window:_renderNav(self) end
	return self
end

return Tab
