--!nocheck
-- The window object: CreateWindow's sequence (no yields, no network, a few instances), the v1
-- window API and seams, tab switching, visibility, preferences, and the theme/font repaint
-- that touches only what is on screen (other tabs catch up in the background).

local Env = require("core/Env")
local Signal = require("core/Signal")
local Util = require("core/Util")
local Token = require("core/Token")
local Scope = require("core/Scope")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Glow = require("core/Glow")
local Theme = require("theme/Theme")
local Fonts = require("theme/Fonts")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Router = require("input/Router")
local Platform = require("input/Platform")
local Focus = require("input/Focus")
local Layers = require("layers/Layers")
local Popover = require("layers/Popover")
local Tooltip = require("layers/Tooltip")
local ContextMenu = require("layers/ContextMenu")
local Store = require("persist/Store")
local Prefs = require("persist/Prefs")
local Changes = require("component/Changes")
local Registry = require("container/Registry")
local Tab = require("container/Tab")
local Color = require("theme/Color")
require("container/Builders")
local Shell = require("shell/Shell")
local Loader = require("shell/Loader")
local Dock = require("shell/Dock")
local Cursor = require("shell/Cursor")
local Pins = require("feature/Pins")
local Toast = require("feature/Toast")
local Dialog = require("feature/Dialog")
local Palette = require("feature/Palette")
local Overlays = require("feature/Overlays")
local Settings = require("feature/Settings")
local ThemePicker = require("feature/ThemePicker")
local KeyGate = require("feature/KeyGate")

local T = Token.T
local Window = {}

-- Instance fields served on first read (they force the part they belong to).
local LAZY = {
	Main = "_ensureShell", Shadow = "_ensureShell", Sidebar = "_ensureShell", Content = "_ensureShell",
	TabList = "_ensureShell", PageHost = "_ensureShell", TopBar = "_ensureShell",
	Notifications = "_ensureToasts", PlayerListOverlay = "_ensureOverlays", KeybindListOverlay = "_ensureOverlays",
	CursorGui = "_ensureCursorGui", ThemePicker = "_ensureThemePicker",
}
Window._meta = {
	__index = function(self, key)
		local method = Window[key]
		if method ~= nil then return method end
		local loader = LAZY[key]
		if loader and not rawget(self, "_destroyed") then
			Window[loader](self)
			return rawget(self, key)
		end
		return nil
	end,
}

-- ---------- creation ----------
function Window.create(Argon, options)
	local started = Env.clock()
	local guiName = tostring(options.GuiName or options.ScreenGuiName or "ArgonUI")
	local registry = Env.genv().__ArgonUI
	if type(registry) ~= "table" then
		registry = { windows = {} }
		pcall(function() Env.genv().__ArgonUI = registry end)
	end
	local previous = registry.windows[guiName]
	if previous and previous.Destroy then pcall(previous.Destroy, previous) end

	Store.resetForWindow(options.ConfigurationSaving)
	local prefs = Prefs.loadForWindow(Store.config, guiName, Argon._uiPreferences)
	Argon._uiPreferences = prefs

	if options.Theme ~= nil then Theme.set(options.Theme) end
	if prefs.CustomTheme and prefs.Theme == "Custom" then
		local custom = {}
		for key, value in pairs(prefs.CustomTheme) do
			local color = type(value) == "string" and Color.hex(value) or nil
			if color then custom[key] = color end
		end
		Theme.set(custom)
	elseif prefs.Theme and Theme.themes[prefs.Theme] then
		Theme.set(prefs.Theme)
	end
	if options.Font then Fonts.set(options.Font) end
	if prefs.Font then Fonts.set(prefs.Font) end
	if type(prefs.Accent) == "string" then Theme.setAccent(Color.hex(prefs.Accent)) end
	if prefs.Material then Theme.materialName = prefs.Material end
	Platform.override = prefs.Density or options.Density
	Metrics.setDensity(Platform.density())
	Motion.setReduced(prefs.ReducedMotion == true or options.ReducedMotion == true or prefs.SmoothTransitions == false)
	if prefs.OverlayTransparency then
		Theme.hudOverride = Overlays.mapTransparency(prefs.OverlayTransparency)
	end

	local self = setmetatable({
		Argon = Argon,
		Tabs = {},
		ActiveTab = nil,
		_guiName = guiName,
		_options = options,
		_visible = true,
		_loading = true,
		_loadingProgress = nil,
		_loadingManual = options.Loading == "manual" or options.ManualLoading == true,
		_defaultTitle = tostring(options.Name or "Argon UI"),
		_defaultSubtitle = tostring(options.Subtitle or "Control Center"),
		_logos = {},
		_groupCaptions = {},
		_navOrder = 0,
		_styleVersion = 0,
		_prewarm = options.Prewarm,
		_themePickerEnabled = options.ThemePicker ~= false,
		_openButton = prefs.OpenButton or options.OpenButton or "auto",
		_mouseUnlock = prefs.MouseUnlock ~= false and options.MouseUnlock ~= false,
		_smoothTransitions = prefs.SmoothTransitions ~= false,
		_loaded = Signal.new("OnLoaded"),
		_density = Metrics.density,
		_clipboard = nil,
	}, Window._meta)
	self._title = tostring(prefs.Title or self._defaultTitle)
	self._subtitle = tostring(prefs.Subtitle or self._defaultSubtitle)
	self._logo = prefs.Logo or options.Logo or options.Icon
	self._scope = Scope.new("window " .. guiName)
	self._shellScope = self._scope:child("shell")
	self._shellScope.isShell = true

	local toggle = Util.keyCode(prefs.MenuKey or options.ToggleUIKeybind)
	if (prefs.MenuKey or options.ToggleUIKeybind) == "None" then toggle = nil
	elseif not toggle then toggle = Enum.KeyCode.Insert end
	self._toggleKey = toggle

	self._layers = Layers.create(self._scope, guiName, options.DisplayOrder)
	self.ScreenGui = self._layers.gui
	local scale = prefs.Scale or options.Scale
	self._scaleSetting = scale or "auto"
	self._loader = Loader.create(self, options)
	self._layers:mount()
	self._layers:setScale(self:_resolveScale())

	self._changes = Changes.attach(self)
	self._registry = Registry.new(self)
	self._glow = Glow.attach(self)
	self._popover = Popover.attach(self)
	self._tooltipHost = Tooltip.attach(self)
	self._pins = Pins.attach(self)
	self._dock = Dock.attach(self)
	self._cursor = Cursor.attach(self, options.Cursor)
	self._cursorMode = options.Cursor == nil and "auto" or options.Cursor
	self._overlays = Overlays.attach(self, prefs, options)
	self._toastHost = Toast.attach(self)
	self._router = Router
	Router.attach()
	self._focus = Focus.attach(self)
	Platform.watch()
	self:_bindKeys()
	self:_listen()

	table.insert(Argon._windows, self)
	registry.windows[guiName] = self
	self._registryRef = registry

	self._relayout = function() self:_layout() return self end
	self._setJumpRailFiltered = function(filtered)
		self._jumpFiltered = filtered and true or false
		Shell.refreshRail(self)
	end

	-- the shell is built off the caller's frame, in the scheduler
	Scheduler.setMode("loading")
	Scheduler.enqueue({ key = self._shellScope, priority = 0, label = "shell", run = function()
		self:_ensureShell()
		return true
	end })
	self._hostThread = coroutine.running()
	-- autosave opens on its own 4 s after CreateWindow when the host never restores (v1), unless
	-- a newer window has taken over the store since
	local generation = Store.generation
	task.delay(4, function()
		if not self._destroyed and Store.generation == generation and not Store.ready and not Store.loading then Store.ready = true end
	end)
	Fonts.preload()
	if options.KeySystem then
		KeyGate.run(self, options)
	end
	self._loader:start()
	Scheduler.noteForeground(Env.clock() - started)
	return self
end

function Window:_resolveScale()
	local value = self._scaleSetting
	if value == "auto" or value == nil then return Metrics.autoScale(self._layers:guiSize()) end
	return math.clamp(tonumber(value) or 1, 0.75, 1.5)
end

-- ---------- listeners ----------
function Window:_listen()
	local scope = self._scope
	scope:connect(Theme.changed, function() self:_restyle() end)
	scope:connect(Fonts.changed, function() self:_restyle() end)
	scope:connect(Platform.changed, function() self:_densityChanged() end)
	scope:connect(self._layers.resized, function() self:_layout() end)
	scope:connect(Store.flagChanged, function(flag)
		for _, element in ipairs(self._registry:dependents(flag)) do
			if not element._destroyed then element:_evaluateConditions() end
		end
	end)
	scope:connect(self._changes.updated, function(element)
		if element.Section and element.Section._refreshReset then element.Section:_refreshReset() end
		self:_renderChangedChip(element._tab)
	end)
	scope:connect(self._pins.changed, function()
		self:_renderPinned()
		if self._dock then self._dock:refresh() end
	end)
	scope:connect(Router.inputKindChanged, function(kind)
		if self._hintBar then
			local pad = kind == "gamepad"
			if self._hintBar.Visible ~= pad then
				self._hintBar.Visible = pad
				Shell.layoutContent(self)
			end
		end
	end)
end

function Window:_bindKeys()
	local window = self
	self._toggleBind = Router.bind({
		key = self._toggleKey,
		owner = self,
		mode = "Press",
		priority = 100,
		enabled = function() return not window._destroyed end,
		onPress = function() window:ToggleVisibility() end,
	})
	self._keyConsumer = Router.layerKey(function(input, processed)
		return window:_onKey(input, processed)
	end, 50)
end

local DIGITS = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8, Nine = 9 }

function Window:_onKey(input, processed)
	if self._destroyed then return false end
	local key = input.KeyCode and input.KeyCode.Name or ""
	if key == "Backspace" or key == "ButtonB" then
		if self._layers:top() then
			self._layers:closeTop("closekey")
			return true
		end
		return false
	end
	if not self._visible or self._loading then return false end
	local ctrl = Router.isDown(Enum.KeyCode.LeftControl) or Router.isDown(Enum.KeyCode.RightControl)
	local near = self._pointerInside or (self._focus and self._focus.active)
	if key == "K" and ctrl then
		self:OpenPalette()
		return true
	end
	if key == "Slash" and near and not processed then
		self:OpenPalette()
		return true
	end
	if ctrl and near and DIGITS[key] then
		local tab = self.Tabs[DIGITS[key]]
		if tab then self:SelectTab(tab) end
		return true
	end
	if ctrl and near and (key == "LeftBracket" or key == "RightBracket") then
		self:_cycleTab(key == "RightBracket" and 1 or -1)
		return true
	end
	if key == "ButtonL1" or key == "ButtonR1" then
		if Router.lastInputKind == "gamepad" then
			self:_cycleTab(key == "ButtonR1" and 1 or -1)
			return true
		end
	end
	if key == "ButtonY" and Router.lastInputKind == "gamepad" then
		self:OpenPalette()
		return true
	end
	if key == "Z" and ctrl and self._changes:canUndo() and self._toastHost:undoAlive() then
		self._changes:runUndo()
		self._toastHost:dismissUndo()
		return true
	end
	return false
end

function Window:_cycleTab(step)
	local index = table.find(self.Tabs, self.ActiveTab) or 1
	local nextTab = self.Tabs[((index - 1 + step) % math.max(1, #self.Tabs)) + 1]
	if nextTab then self:SelectTab(nextTab) end
end

-- ---------- shell ----------
function Window:_ensureShell()
	if self._shellBuilt or self._destroyed then return end
	self._shellBuilt = true
	Scheduler.cancel(self._shellScope)
	Shell.build(self)
	local main = self.Main
	self:_applyGeometry()
	main.Parent = self._layers:get("Base")
	self._mouseUnlockButton = Factory.new(self._shellScope, "TextButton", {
		Name = "MouseUnlock", BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1), Modal = false,
	}, self._layers:get("Base"))
	self._shellMounted = true
	Shell.layout(self)
	Shell.restyle(self)
	if self.ActiveTab then self:_showActive(false) end
	if not self._loading then self:_applyVisible(false) end
	if self._loader then self._loader:evaluate() end
end

function Window:_applyGeometry()
	local main = rawget(self, "Main")
	if not main then return end
	local area = self._layers:localSize()
	local saved = Prefs.get("WindowSize")
	local size
	if type(saved) == "table" and tonumber(saved.X) then
		size = Metrics.clampSize(area, saved.X, saved.Y)
		self._userSized = true
	else
		size = Metrics.windowDefault(area)
	end
	main.Size = UDim2.fromOffset(size.X, size.Y)
	local position = Prefs.get("WindowPosition")
	if type(position) == "table" and tonumber(position.X) then
		self:_moveTo(UDim2.fromOffset(position.X, position.Y))
	else
		self:_moveTo(UDim2.fromOffset(math.floor((area.X - size.X) / 2), math.floor((area.Y - size.Y) / 2)))
	end
end

function Window:_moveTo(position)
	local main = rawget(self, "Main")
	if not main then return end
	local area = self._layers:localSize()
	local width = main.Size.X.Offset
	local x = math.clamp(position.X.Offset, 64 - width, math.max(64 - width, area.X - 64))
	local y = math.clamp(position.Y.Offset, 0, math.max(0, area.Y - Metrics.TOPBAR))
	main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	Popover.placeShadow(self.Shadow, Vector2.new(x, y), Vector2.new(width, main.Size.Y.Offset), 28, 14)
end

function Window:_rememberGeometry()
	local main = rawget(self, "Main")
	if not main then return end
	Prefs.set("WindowPosition", { X = main.Position.X.Offset, Y = main.Position.Y.Offset })
	if self._userSized then Prefs.set("WindowSize", { X = main.Size.X.Offset, Y = main.Size.Y.Offset }) end
end

function Window:_layout()
	if self._destroyed then return end
	local s = self:_resolveScale()
	if math.abs(s - self._layers.scale) > 0.001 then
		self._layers:setScale(s)
		return
	end
	local main = rawget(self, "Main")
	if main then
		local area = self._layers:localSize()
		if not self._userSized then
			local size = Metrics.windowDefault(area)
			main.Size = UDim2.fromOffset(size.X, size.Y)
			self:_moveTo(UDim2.fromOffset(math.floor((area.X - size.X) / 2), math.floor((area.Y - size.Y) / 2)))
		else
			local size = Metrics.clampSize(area, main.Size.X.Offset, main.Size.Y.Offset)
			main.Size = UDim2.fromOffset(size.X, size.Y)
			self:_moveTo(main.Position)
		end
		Shell.layout(self)
	end
	if self._loader then self._loader:_layout() end
	if self._overlays then self._overlays:clamp() end
end

function Window:_ensureNav(tab)
	self:_ensureShell()
	Shell.navItem(self, tab)
end

function Window:_pageBuilt(tab)
	if self.ActiveTab == tab and self._shellBuilt then tab:_show(self.PageHost) end
end

-- ---------- theme, font, density ----------
function Window:_restyle()
	if self._destroyed then return end
	self._styleVersion += 1
	Env.profileBegin("Argon/theme")
	local scope = self._scope
	for index = 1, #scope.paints, 3 do
		scope.paints[index][scope.paints[index + 1]] = Token.resolve(scope.paints[index + 2])
	end
	for _, child in ipairs(scope._children) do
		if not child.isTab then child:repaint() end
	end
	Shell.restyle(self)
	for _, tab in ipairs(self.Tabs) do
		if tab == self.ActiveTab then
			tab:_repaint()
		elseif tab._skeleton then
			tab._stale = true
			Scheduler.enqueue({ key = "repaint:" .. tostring(tab), priority = 3, label = "repaint", run = function()
				if tab._stale then tab:_repaint() end
				return true
			end })
		end
	end
	if self._overlays then self._overlays:restyle() end
	if self._themePickerContent then ThemePicker.restyle(self) end
	if self._loader then
		self._loader.letter.Text = self._loader.letter.Text
	end
	Env.profileEnd()
end

-- Theme picker hover: repaint what is on screen under the current resolution (the caller wraps
-- this in Theme.withPalette), with no version bump and no stale stamps on hidden tabs.
function Window:_previewRepaint()
	if self._destroyed then return end
	local scope = self._scope
	for index = 1, #scope.paints, 3 do
		scope.paints[index][scope.paints[index + 1]] = Token.resolve(scope.paints[index + 2])
	end
	for _, child in ipairs(scope._children) do
		if not child.isTab then child:repaint() end
	end
	Shell.restyle(self)
	if self.ActiveTab then self.ActiveTab:_repaint() end
end

function Window:_densityChanged()
	Metrics.setDensity(Platform.density())
	-- Metrics is shared, so compare with what this window was built at, not setDensity's result
	if self._density ~= Metrics.density then
		self._density = Metrics.density
		for _, tab in ipairs(self.Tabs) do tab:_unmount() end
		if self._shellBuilt then
			for _, tab in ipairs(self.Tabs) do
				local button = rawget(tab, "TabButton")
				if button then button.Size = UDim2.new(1, 0, 0, Metrics.get("nav")) end
			end
			Shell.layout(self)
		end
		if self.ActiveTab then self:_showActive(false) end
	end
	self:_layout()
end

-- ---------- tabs ----------
function Window:CreateTab(name, icon, options)
	local tab = Tab.create(self, name, icon, options)
	self.Tabs[#self.Tabs + 1] = tab
	if self._shellBuilt then
		Shell.navItem(self, tab)
		if self._layoutName then Shell.refreshRail(self) end
	end
	if not self.ActiveTab then self:_select(tab) end
	if self._loader then self._loader:activity() end
	return tab
end

function Window:_showActive(animated)
	local tab = self.ActiveTab
	if not tab or not self._shellBuilt then return end
	if not tab:_fullyMounted() then tab:_mountNow(15) end
	tab:_show(self.PageHost)
	if animated and not Motion.reduced then
		local veil = self._pageVeil
		veil.Visible = true
		veil.BackgroundTransparency = 0
		Motion.tween(veil, "veil", { BackgroundTransparency = 1 })
		local group = tab.PageGroup
		group.Position = UDim2.fromOffset(0, 6)
		Motion.tween(group, "rise", { Position = UDim2.fromOffset(0, 0) })
	else
		tab.PageGroup.Position = UDim2.fromOffset(0, 0)
	end
	Shell.renderTopbar(self)
	Shell.refreshRail(self)
	Shell.moveIndicator(self, animated)
	self:_renderChangedChip(tab)
end

function Window:_select(tab)
	if self.ActiveTab == tab or not tab then return end
	local old = self.ActiveTab
	self._layers:closeAll("tab")
	if old then old:_hide() end
	self.ActiveTab = tab
	if self._shellBuilt then
		if old then Shell.renderNav(self, old) end
		Shell.renderNav(self, tab)
	end
	tab:_filter("")
	if self._revealed then Prefs.set("LastTab", tab.Name) end
	if self._loading then
		tab:_enqueue(1)
		if self._shellBuilt then self:_showActive(false) end
	else
		self:_showActive(self._revealed == true)
	end
end

function Window:SelectTab(target)
	local tab = target
	if type(target) == "number" then tab = self.Tabs[target]
	elseif type(target) == "string" then
		for _, candidate in ipairs(self.Tabs) do
			if candidate.Name == target then tab = candidate break end
		end
	end
	if type(tab) == "table" then self:_select(tab) end
	return self
end

function Window:GetActiveTab()
	return self.ActiveTab
end

function Window:_tabMounted(tab)
	if tab == self.ActiveTab and self._loader then self._loader:evaluate() end
end

function Window:_loaderProgress(tab)
	local loader = self._loader
	if loader and tab == self.ActiveTab and self._loading then loader:_updateStatus() end
end

function Window:_refreshSectionMenu()
	if self._shellBuilt then Shell.refreshRail(self) end
	return self
end

function Window:_scrollToSection(section)
	local tab = section.Tab
	local root = rawget(section, "Root")
	if not root or not tab.Page then return end
	local page = tab.Page
	local scale = self._layers.scale
	local offset = (root.AbsolutePosition.Y - page.AbsolutePosition.Y) / scale + page.CanvasPosition.Y
	local target = Vector2.new(0, math.max(0, offset - 8))
	if Motion.reduced then
		page.CanvasPosition = target
	else
		Motion.tween(page, "scroll", { CanvasPosition = target })
	end
end

function Window:_pageScrolled(tab)
	if tab == self.ActiveTab then Shell.scrollSpy(self) end
end

function Window:_renderBadge(tab)
	Shell.renderBadge(self, tab)
end

function Window:_renderNav(tab)
	Shell.renderNav(self, tab)
end

function Window:_setCollapsedPref(section, collapsed)
	local map = Util.copy(Prefs.get("CollapsedSections") or {})
	map[section.Tab.Name .. "/" .. section.Name] = collapsed or nil
	Prefs.set("CollapsedSections", map)
end

-- "9 changed · Reset tab" in the page header.
function Window:_renderChangedChip(tab)
	if not tab or not tab._pageHeader then return end
	local count = self._changes:count(tab)
	local chip = tab._changedChip
	if count > 0 and not chip then
		local scope = tab._pageScope
		chip = Factory.text(scope, "TextButton", {
			Name = "ChangedChip", FontFace = Token.F.Caption, TextSize = Token.TS.Caption, TextColor3 = T.Text2,
			BackgroundColor3 = T.Active, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center,
		}, tab._pageHeader)
		Factory.corner(scope, chip, "full")
		Factory.padding(scope, chip, 12, 12, 0, 0)
		scope:connect(chip.MouseButton1Click, function() self:_resetTabFromUI(tab) end)
		tab._changedChip = chip
	end
	if chip then
		chip.Visible = count > 0
		chip.Text = ("%d changed · Reset tab"):format(count)
	end
end

function Window:_resetTabFromUI(tab)
	local count = self._changes:count(tab)
	if count > 3 then
		self:Confirm({ Title = "Reset " .. tab.Name .. "?", Content = ("%d settings go back to their defaults."):format(count),
			ConfirmText = "Reset", OnConfirm = function() tab:Reset() end })
	else
		tab:Reset()
	end
end

function Window:ResetAll()
	local all = {}
	for _, tab in ipairs(self.Tabs) do
		for _, element in ipairs(tab._elements) do all[#all + 1] = element end
	end
	local count = self._changes:resetAll(all)
	if count > 0 then self:_undoPill(("Reset %d setting%s"):format(count, count == 1 and "" or "s")) end
	return self
end

-- ---------- visibility ----------
function Window:_isShowing()
	return self._visible and not self._destroyed
end

function Window:_applyVisible(animated)
	local main = rawget(self, "Main")
	if main then
		main.Visible = self._visible and not self._loading
		self.Shadow.Visible = main.Visible
		if main.Visible and animated and not Motion.reduced then
			self._mainScale.Scale = 0.97
			Motion.spring(self._mainScale, "Scale", 1, "gentle")
		end
		local unlock = self._mouseUnlockButton
		if unlock then unlock.Modal = main.Visible and self._mouseUnlock end
	end
	if self._overlays then self._overlays:refresh() end
	if self._dock then self._dock:refresh() end
	if self._cursor then self._cursor:refresh() end
	if self._pins then self:_renderPinned() end
end

function Window:SetVisibility(value)
	local visible = value ~= false
	if self._visible == visible then
		self:_applyVisible(false)
		return self
	end
	self._visible = visible
	if not visible then
		self._layers:closeAll("hide")
		if self._focus then self._focus:leave() end
		self._tooltipHost:hide()
	end
	self:_applyVisible(visible)
	if not visible and not self._loading and not Prefs.getProfile("SeenHideHint") then
		Prefs.setProfile("SeenHideHint", true)
		local key = self._toggleKey and Util.keyName(self._toggleKey)
		local text = Platform.preferred() == "touch" and ("Tap the " .. self._title .. " button to reopen")
			or (key and ("%s is hidden. Press %s to reopen"):format(self._title, key)) or (self._title .. " is hidden")
		self:_toast(text, "info")
	end
	return self
end

function Window:ToggleVisibility()
	return self:SetVisibility(not self._visible)
end
function Window:Toggle() return self:ToggleVisibility() end
function Window:Open() return self:SetVisibility(true) end
function Window:Close() return self:SetVisibility(false) end
function Window:IsVisible() return self._visible == true end

function Window:SetToggleKey(value)
	if value == nil or value == "None" or value == "" then
		self._toggleKey = nil
		self._toggleBind:rebind(nil)
		Prefs.set("MenuKey", "None")
		return self
	end
	local code = Util.keyCode(value)
	if not code then return self end
	self._toggleKey = code
	self._toggleBind:rebind(code)
	Prefs.set("MenuKey", Util.keyName(code))
	return self
end

-- ---------- identity ----------
function Window:SetTitle(value)
	local wanted = Util.trim(value)
	self._title = wanted ~= "" and Util.truncate(wanted, 40) or self._defaultTitle
	if self._brandName then self._brandName.Text = self._title end
	if self._loader and self._loader.titleLabel then self._loader.titleLabel.Text = self._title end
	for _, entry in ipairs(self._logos) do Shell.renderLogo(self, entry) end
	Prefs.set("Title", self._title ~= self._defaultTitle and self._title or nil)
	return self
end

function Window:SetSubtitle(value)
	local wanted = Util.trim(value)
	self._subtitle = wanted ~= "" and Util.truncate(wanted, 40) or self._defaultSubtitle
	if self._brandSub then self._brandSub.Text = self._subtitle end
	Prefs.set("Subtitle", self._subtitle ~= self._defaultSubtitle and self._subtitle or nil)
	return self
end

function Window:GetTitle() return self._title end
function Window:GetSubtitle() return self._subtitle end

function Window:SetLogo(value)
	self._logo = value ~= nil and tostring(value) or nil
	for _, entry in ipairs(self._logos) do Shell.renderLogo(self, entry) end
	Prefs.set("Logo", self._logo)
	return self
end

function Window:SetFont(value)
	local before = Fonts.current
	Fonts.set(value)
	if Fonts.current ~= before then Prefs.set("Font", Fonts.current) end
	return self
end
function Window:GetFonts() return Fonts.list() end

function Window:SetTheme(value)
	local ok, err = Theme.set(value)
	if ok then
		Prefs.set("Theme", Theme.name)
		if type(value) == "table" then
			local custom = {}
			for key, color in pairs(Theme.themes.Custom or {}) do
				if typeof(color) == "Color3" then custom[key] = Color.toHex(color) end
			end
			Prefs.set("CustomTheme", custom)
		end
	end
	return ok, err
end
function Window:GetThemes() return Theme.list() end

function Window:SetMaterial(material)
	if Theme.setMaterial(tostring(material)) then Prefs.set("Material", tostring(material)) end
	return self
end

function Window:SetSize(value)
	local width, height
	if typeof(value) == "Vector2" then
		width, height = value.X, value.Y
	elseif type(value) == "table" then
		width, height = value[1] or value.X, value[2] or value.Y
	end
	self:_ensureShell()
	local main = self.Main
	local area = self._layers:localSize()
	local size = Metrics.clampSize(area, tonumber(width) or main.Size.X.Offset, tonumber(height) or main.Size.Y.Offset)
	self._userSized = true
	main.Size = UDim2.fromOffset(size.X, size.Y)
	self:_moveTo(main.Position)
	Shell.layout(self)
	return self
end

function Window:SetScale(value)
	self._scaleSetting = value == "auto" and "auto" or math.clamp(tonumber(value) or 1, 0.75, 1.5)
	Prefs.set("Scale", value ~= "auto" and self._scaleSetting or nil)
	self._layers:setScale(self:_resolveScale())
	return self
end
function Window:GetScale() return self._layers.scale end

function Window:SetDensity(value)
	local map = { auto = "Auto", compact = "Compact", touch = "Touch" }
	local density = map[tostring(value):lower()] or "Auto"
	Platform.override = density
	Prefs.set("Density", density)
	-- the density is shared, so every open window rebuilds at it
	for _, window in ipairs(self.Argon._windows) do
		if not window._destroyed then window:_densityChanged() end
	end
	return self
end

function Window:SetReducedMotion(on)
	Motion.setReduced(on == true)
	Prefs.set("ReducedMotion", on == true)
	return self
end

function Window:SetSmoothTransitions(on)
	self._smoothTransitions = on ~= false
	Motion.setReduced(not self._smoothTransitions or Prefs.get("ReducedMotion") == true)
	Prefs.set("SmoothTransitions", self._smoothTransitions)
	return self
end

function Window:SetStatus(text, tone)
	self:_ensureShell()
	Shell.setStatus(self, text, tone)
	return self
end

function Window:SetOpenButton(mode)
	if type(mode) == "table" then mode = mode.Mode end
	self._openButton = mode
	Prefs.set("OpenButton", mode)
	self._dock:refresh()
	return self
end

function Window:SetMouseUnlock(on)
	self._mouseUnlock = on ~= false
	Prefs.set("MouseUnlock", self._mouseUnlock)
	self:_applyVisible(false)
	return self
end

function Window:SetCursorVisible(value)
	self._cursorMode = value == nil and "auto" or value
	self._cursor:setMode(value)
	return self
end
function Window:IsCursorDrawn() return self._cursor:drawn() end

function Window:_ensureCursorGui()
	self.CursorGui = self._cursor:gui()
end

-- ---------- loader ----------
function Window:SetLoadingProgress(fraction, status, internal)
	if internal ~= "restore" then self._loadingManual = true end
	if not self._loading then return self end
	local value = math.clamp(tonumber(fraction) or 0, 0, 1)
	self._loadingProgress = math.max(self._loadingProgress or 0.08, value)
	local loader = self._loader
	if loader then
		if internal == "restore" then
			loader:setProgress(0.85 + 0.15 * math.clamp((value - 0.8) / 0.2, 0, 1), true)
		else
			loader:setProgress(self._loadingProgress * 0.85, true)
			self._loadingHostStatus = status ~= nil and status ~= ""
		end
		if status ~= nil and status ~= "" then loader:setStatus(tostring(status)) end
		loader:progressed()
	end
	return self
end

function Window:SetLoadingStatus(text)
	if self._loader and self._loading then
		self._loadingHostStatus = true
		self._loader:setStatus(tostring(text))
		self._loader:progressed()
	end
	return self
end

function Window:FinishLoading()
	if not self._loading then return self end
	self:_ensureShell()
	local tab = self.ActiveTab
	-- the first screenful mounts now; the rest of the tab continues in the next frames
	if tab and not tab:_fullyMounted() then tab:_mountNow(15) end
	if self._loader then
		self._loader.finishRequested = true
		self._loader:evaluate()
	else
		self._loading = false
	end
	return self
end

function Window:IsLoading()
	return self._loading == true
end

function Window:OnLoaded(fn)
	if not self._loading and self._revealed then
		task.spawn(fn, self)
		return { Connected = false, Disconnect = function() end }
	end
	return self._loaded:Connect(fn)
end

-- Runs fn(window) under xpcall; an error is shown on the loader with its actions.
function Window:Build(fn)
	local ok, err = xpcall(fn, debug.traceback, self)
	if not ok and self._loader then
		self._loader:error(tostring(err):gsub("\n.*", ""))
		self._loadingManual = true
	end
	return self
end

-- Called by the loader when the window is handed over.
function Window:_revealShell(withCard)
	self:_ensureShell()
	local last = Prefs.get("LastTab")
	if last and not self._revealed then
		for _, tab in ipairs(self.Tabs) do
			if tab.Name == last and tab ~= self.ActiveTab then self:_select(tab) break end
		end
	end
	if self.ActiveTab then self:_showActive(false) end
	self._revealed = true
	local main = self.Main
	main.Visible = self._visible
	self.Shadow.Visible = self._visible
	local veil = self._veil
	if not Motion.reduced then
		veil.Visible = true
		veil.BackgroundTransparency = 0
		Motion.tween(veil, "veil", { BackgroundTransparency = 1 }, { delay = withCard and 0.2 or 0 })
		if not withCard then
			self._mainScale.Scale = 0.97
			Motion.spring(self._mainScale, "Scale", 1, "gentle")
		end
	end
	Scheduler.setMode("interactive")
	if self._prewarm ~= false then
		for _, tab in ipairs(self.Tabs) do
			if tab ~= self.ActiveTab then tab:_enqueue(3) end
		end
	end
	Scheduler.enqueue({ key = "icons", priority = 4, label = "icons", run = function() Icons.decode() return true end })
	self:_applyVisible(false)
	self._toastHost:flushQueued()
	self._loaded:Fire(self)
	if Platform.preferred() == "gamepad" and self._focus then self._focus:enter("open") end
end

-- ---------- feature hooks ----------
function Window:_ensureToasts()
	self.Notifications = self._toastHost:layer()
end

function Window:_ensureOverlays()
	self._overlays:ensure()
end

function Window:_ensureThemePicker()
	ThemePicker.prebuild(self)
end

function Window:_toast(text, kind, action)
	return self._toastHost:pill(text, kind, action)
end

function Window:_undoPill(text)
	self._toastHost:undo(text, function() self._changes:runUndo() end)
end

function Window:_openInbox(anchor)
	self._toastHost:openInbox(anchor)
end

-- Copies text to the clipboard; without setclipboard the text is shown in a copy sheet.
function Window:_copy(text, element)
	if element then self._clipboard = { type = element.Type, value = Util.copy(element:_rawValue()) } end
	if Env.setClipboard(text) then
		self:_toast("Copied", "success")
	else
		self._toastHost:copySheet(text)
	end
end

function Window:_openAccountMenu(anchor)
	local key = self._toggleKey and Util.keyName(self._toggleKey) or nil
	ContextMenu.open(self, anchor, {
		{ Text = "Settings", Icon = "settings", Callback = function() Settings.open(self) end },
		{ Text = "Profiles", Icon = "folder", Callback = function() Settings.open(self, "Profiles") end },
		{ Text = "Search", Icon = "search", Shortcut = "Ctrl K", Callback = function() self:OpenPalette() end },
		"divider",
		{ Text = "Hide UI", Icon = "eye-off", Shortcut = key, Callback = function() self:SetVisibility(false) end },
		{ Text = "Unload", Icon = "x", Danger = true, Callback = function()
			self:Confirm({ Title = "Unload " .. self._title .. "?", Content = "The window closes and its keybinds stop.",
				ConfirmText = "Unload", OnConfirm = function() self:Destroy() end })
		end },
	}, { Title = self._title, Subtitle = self._subtitle })
end

function Window:_renderPinned()
	-- the Pinned sidebar group mirrors the pins (DESIGN_V2 3.3)
	if not self._shellBuilt then return end
	local scope = self._pinScope
	if scope then scope:destroy() end
	scope = self._shellScope:child("pins")
	self._pinScope = scope
	local pins = self._pins:list()
	if #pins == 0 or self._layoutName == "rail" then return end
	self._navOrder += 0
	local caption = Factory.text(scope, "TextLabel", { Name = "Pinned", Text = "Pinned", FontFace = Token.F.Caption,
		TextSize = Token.TS.Caption, TextColor3 = T.Text2, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 100000,
		TextYAlignment = Enum.TextYAlignment.Bottom }, self.TabList)
	for index, element in ipairs(pins) do
		local row = Factory.text(scope, "TextButton", { Name = "Pin", Text = element.Name, FontFace = Token.F.Body,
			TextSize = Token.TS.Body, TextColor3 = T.Text2, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 100000 + index,
			TextTruncate = Enum.TextTruncate.AtEnd }, self.TabList)
		Factory.padding(scope, row, 10, 44, 0, 0)
		local state = Factory.text(scope, "TextLabel", { Text = "", FontFace = Token.F.Caption, TextSize = Token.TS.Caption,
			TextColor3 = T.Text2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 40, 0, 0), Size = UDim2.new(0, 36, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right }, row)
		local function render()
			if element.Type == "Toggle" then state.Text = element.CurrentValue and "On" or "Off" else state.Text = "Run" end
		end
		render()
		scope:add(element:OnChanged(render))
		scope:connect(row.MouseButton1Click, function() self._pins:activate(element) end)
	end
	local _ = caption
end

function Window:OpenPalette(query)
	return Palette.open(self, query)
end

function Window:RegisterCommand(command)
	return self._registry:addCommand(command)
end

function Window:Prompt(config)
	return Dialog.prompt(self, config)
end

function Window:Dialog(config)
	return Dialog.dialog(self, config)
end
Window.Popup = Window.Dialog

function Window:Confirm(config)
	return Dialog.confirm(self, config)
end

function Window:CreateLibrarySettings(tab)
	return Settings.library(self, tab)
end

function Window:CreateConfigManager(tab)
	return Settings.configManager(self, tab)
end

function Window:SetThemePickerVisible(visible)
	return ThemePicker.setVisible(self, visible)
end

function Window:ToggleThemePicker()
	return ThemePicker.toggle(self)
end

-- ---------- overlays (v1) ----------
function Window:SetPlayerListVisible(value) self._overlays:setEnabled("Players", value ~= false) return self end
function Window:SetKeybindListVisible(value) self._overlays:setEnabled("Keybinds", value ~= false) return self end
function Window:TogglePlayerList() return self:SetPlayerListVisible(not self._overlays.enabled.Players) end
function Window:ToggleKeybindList() return self:SetKeybindListVisible(not self._overlays.enabled.Keybinds) end
function Window:SetOverlaysAlwaysVisible(value) self._overlays:setPinned(value == true) return self end
Window.SetOverlaysPinned = Window.SetOverlaysAlwaysVisible
function Window:ToggleOverlaysAlwaysVisible() return self:SetOverlaysAlwaysVisible(not self._overlays.pinned) end
function Window:AreOverlaysAlwaysVisible() return self._overlays.pinned == true end
function Window:SetOverlayTransparency(value) self._overlays:setTransparency(value) return self end
function Window:SetOverlayScale(value) self._overlays:setScale(value) return self end
function Window:ResetOverlayPositions() self._overlays:resetPositions() return self end
function Window:SetWatermarkVisible(value) self._overlays:setEnabled("Watermark", value ~= false) return self end
function Window:_refreshOverlayVisibility() self._overlays:refresh() return self end
function Window:_refreshKeybindOverlay() self._overlays:refreshKeybinds() return self end

-- ---------- preferences (v1 seams) ----------
function Window:_exportUIPreferences()
	local out = Prefs.export()
	out.Theme = Theme.name
	out.Font = Fonts.current
	out.Title = self._title
	out.Subtitle = self._subtitle
	out.Logo = self._logo
	for key, value in pairs(self._overlays:export()) do out[key] = value end
	out.SmoothTransitions = self._smoothTransitions
	return out
end

function Window:_applyUIPreferences(preferences)
	preferences = preferences or {}
	if preferences.Theme and Theme.themes[preferences.Theme] then Theme.set(preferences.Theme) end
	if preferences.Font then Fonts.set(preferences.Font) end
	if preferences.Title ~= nil then self:SetTitle(preferences.Title) end
	if preferences.Subtitle ~= nil then self:SetSubtitle(preferences.Subtitle) end
	if preferences.Logo ~= nil then self:SetLogo(preferences.Logo) end
	if preferences.SmoothTransitions ~= nil then self._smoothTransitions = preferences.SmoothTransitions ~= false end
	self._overlays:apply(preferences)
	return self
end

-- ---------- teardown ----------
function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self._loading = false
	if self._toggleBind then self._toggleBind:unbind() end
	if self._keyConsumer then self._keyConsumer.remove() end
	if self._focus then self._focus:destroy() end
	self._layers:closeAll("hide")
	for _, tab in ipairs(self.Tabs) do
		Scheduler.cancel(tab)
		for _, element in ipairs(table.clone(tab._elements)) do
			for _, bind in ipairs(rawget(element, "_binds") or {}) do bind:unbind() end
		end
	end
	Scheduler.cancel(self._shellScope)
	if self._cursor then self._cursor:destroy() end
	self._scope:destroy()
	Router.detach()
	local list = self.Argon._windows
	for index = #list, 1, -1 do
		if list[index] == self then table.remove(list, index) end
	end
	local registry = self._registryRef
	if registry and registry.windows[self._guiName] == self then registry.windows[self._guiName] = nil end
end

return Window
