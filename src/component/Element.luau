--!nocheck
-- The control base (ARCHITECTURE_V2 section 8). Create* builds only state (about a microsecond);
-- instances are mounted later by the tab's scheduler job, or immediately when a script reads
-- an instance field such as Root. Every value change goes through one commit path.

local Env = require("core/Env")
local Signal = require("core/Signal")
local Util = require("core/Util")
local Token = require("core/Token")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Component = require("component/Component")
local RowView = require("component/RowView")
local Store = require("persist/Store")
local Registry = require("container/Registry")
local Factory = require("core/Factory")
local ContextMenu = require("layers/ContextMenu")

local T = Token.T
local Element = {}

local Base = Component.extend({
	ClassName = "Element",
	viewFields = { "Root", "_title", "_description", "_tipMarker", "_lock", "_stroke" },
})
Element.Base = Base

-- ---------- lifecycle ----------
function Base:_ensureMounted()
	if rawget(self, "_mounted") or rawget(self, "_destroyed") or rawget(self, "_mounting") then return end
	self:_mount()
end

function Base:_mount()
	if rawget(self, "_mounted") or self._destroyed then return end
	self._mounting = true
	local tab = self._tab
	tab:_ensureSkeleton()
	local parent = self._owner:_container()
	local scope = tab._pageScope:child(self.Type)
	self._scope = scope
	local spec = self._spec
	self._mounted = true
	self._mounting = nil
	local view = RowView.build(self, scope, {
		display = spec.display,
		title = spec.title,
		reserve = spec.reserve and spec.reserve(self) or 0,
		height = spec.height and spec.height(self) or nil,
	})
	if spec.build then spec.build(self, view, scope) end
	if self._descText then RowView.setDescription(self, self._descText) end
	if self._tooltipText then RowView.setTooltip(self, self._tooltipText) end
	if self.Locked then RowView.setLock(self) end
	local window = self._window
	if window._changes:isChanged(self) then RowView.setChanged(self, true) end
	self:_wire(view, scope)
	self:_render(false)
	self._styleVersion = window._styleVersion
	view.Root.Visible = self:_isVisible()
	view.Root.Parent = parent
	tab:_noteMounted(self)
	self._owner:_childVisibility()
end

-- Hover, press, right-click and long-press on the row root.
function Base:_wire(view, scope)
	local root = view.Root
	local window = self._window
	local fill = not self._spec.display and self._spec.rowHover ~= false
	scope:connect(root.MouseEnter, function()
		self._hover = true
		local section = self.Section
		if fill and section and section._hoverRow and window._router.lastInputKind ~= "touch" then section:_hoverRow(self, true) end
		if self._tooltipText and self._tooltipText ~= "" then
			window._tooltipHost:schedule(view.Title or root, self._tooltipText, "hover")
		end
		if self._spec.hover then self._spec.hover(self, true) end
	end)
	scope:connect(root.MouseLeave, function()
		self._hover = false
		local section = self.Section
		if section and section._hoverRow then section:_hoverRow(self, false) end
		window._tooltipHost:hide(view.Title or root)
		if self._spec.hover then self._spec.hover(self, false) end
	end)
	scope:connect(root.InputBegan, function(input)
		local kind = input.UserInputType and input.UserInputType.Name
		if kind == "MouseButton2" then
			self:_openMenu(Vector2.new(input.Position.X, input.Position.Y))
		elseif kind == "Touch" then
			local token = {}
			self._pressToken = token
			task.delay(0.45, function()
				if self._pressToken == token and self._hover ~= false then
					self._pressToken = nil
					if self._tooltipText and self._tooltipText ~= "" and not self._spec.noMenu then
						window._tooltipHost:schedule(view.Title or root, self._tooltipText, "press")
					end
					self:_openMenu(nil)
				end
			end)
		end
	end)
	scope:connect(root.InputEnded, function(input)
		if input.UserInputType and input.UserInputType.Name == "Touch" then self._pressToken = nil end
	end)
end

function Base:_onScreen()
	if not rawget(self, "_mounted") or self._destroyed then return false end
	local window = self._window
	return window:_isShowing() and window.ActiveTab == self._tab and self:_isVisible()
end

function Base:_render(animated)
	if not rawget(self, "_mounted") then return end
	local view = self._view
	if view and view.Title then
		local color = (self._disabled or self._whenDisabled) and T.Disabled or (self.Locked and T.Text2 or T.Text)
		view.Title.TextColor3 = Token.resolve(color)
	end
	local render = self._spec.render
	if render then render(self, animated == true) end
end

function Base:_applyTheme()
	if not rawget(self, "_mounted") then return end
	self._scope:repaint()
	self:_render(false)
	self._styleVersion = self._window._styleVersion
end

function Base:_isVisible()
	return not (self._hidden or self._filtered or self._whenHidden)
end

function Base:_applyVisibility()
	if rawget(self, "_mounted") and self.Root then
		self.Root.Visible = self:_isVisible()
	end
	if self._owner and self._owner._childVisibility then self._owner:_childVisibility() end
	if self._tab and self._tab._visibilityChanged then self._tab:_visibilityChanged() end
end

function Base:_inactive()
	return self.Locked or self._disabled or self._whenDisabled
end

-- ---------- values ----------
local function defaultEquals(a, b)
	if type(a) == "table" or type(b) == "table" then return Util.jsonEqual(a, b) end
	return a == b
end

function Base:_rawValue()
	return self.CurrentValue
end

-- Comparable form of a value for change tracking (defaults to the persisted form).
function Base:_encodeValue(value)
	if value == nil then value = self.CurrentValue end
	local encode = self._spec.encodeValue
	if encode then return encode(self, value) end
	if typeof(value) == "Color3" then return { value.R, value.G, value.B } end
	if typeof(value) == "EnumItem" then return value.Name end
	return value
end

function Base:_payload()
	local payload = self._spec.payload
	if payload then return payload(self) end
	return self.CurrentValue
end

function Base:_context()
	local text = ("%s \"%s\""):format(self.Type, tostring(self.Name))
	if self.Flag then text ..= " (flag " .. self.Flag .. ")" end
	return text
end

-- The single commit path (ARCHITECTURE_V2 8.6). opts: { silent, source, force }
function Base:_setValue(raw, opts)
	opts = opts or {}
	local spec = self._spec
	local value = raw
	if spec.normalize then
		value = spec.normalize(self, raw)
		if value == nil then return self end
	end
	local same = (spec.equals or defaultEquals)(value, self.CurrentValue)
	if same and not opts.force then
		if opts.source == "commit" then self:_fireCommit(opts.source) end
		return self
	end
	self.CurrentValue = value
	if spec.mirror then spec.mirror(self) end
	self:_render(self:_onScreen())
	self:_noteChange()
	if opts.silent then return self end
	if opts.source == "drag" then
		Store.notify(self)
		Util.xcall(self._callback, self:_context(), self, self:_payload())
		return self
	end
	self:_commit(opts.source or "api")
	return self
end

-- End of a drag (slider, colour picker): the value was already set live with source "drag";
-- this runs the rest of the commit once (listeners, autosave, flash, OnChanged, OnRelease)
-- without firing the callback a second time.
function Base:_endDrag()
	Store.commit(self)
	self:_flash()
	self:_noteChange()
	self:_fireCommit("commit")
end

function Base:_noteChange()
	local window = self._window
	if not window or not window._changes then return end
	local changed = window._changes:note(self)
	if rawget(self, "_mounted") and self._view then
		RowView.setChanged(self, changed)
	end
end

function Base:_commit(source)
	Store.commit(self)
	self:_flash()
	Util.xcall(self._callback, self:_context(), self, self:_payload())
	self:_fireCommit(source)
end

function Base:_fireCommit(source)
	local signal = rawget(self, "_changed")
	if signal then signal:Fire(self:_payload(), source) end
	if source == "commit" and type(self._cfg.OnRelease) == "function" then
		Util.xcall(self._cfg.OnRelease, self:_context() .. " OnRelease", self, self:_payload())
	end
end

-- A short accent sweep on the row's left edge (no tween objects at rest).
function Base:_flash()
	if not self:_onScreen() or Motion.reduced then return end
	local view = self._view
	if not view or not view.Root then return end
	local bar = view.Flash
	if not bar then
		bar = Factory.new(self._scope, "Frame", {
			Name = "Flash",
			BackgroundColor3 = T.Accent,
			Size = UDim2.new(0, 2, 1, -12),
			Position = UDim2.fromOffset(2, 6),
			BackgroundTransparency = 1,
		}, view.Root)
		view.Flash = bar
	end
	bar.BackgroundTransparency = 0.2
	Motion.tween(bar, "state", { BackgroundTransparency = 1 }, { delay = 0.2 })
end

-- ---------- public API (v1 names) ----------
function Base:Get()
	return self.CurrentValue
end

function Base:GetDefault()
	return Util.copy(self.Default)
end

function Base:IsChanged()
	return self._window._changes:isChanged(self)
end

function Base:Reset()
	if self.Default ~= nil and self.Set then self:Set(Util.copy(self.Default)) end
	return self
end

function Base:_resetWithUndo()
	local window = self._window
	local count = window._changes:resetAll({ self })
	if count > 0 and window._undoPill then window:_undoPill(("Reset %s"):format(self.Name)) end
end

function Base:OnChanged(fn)
	local signal = rawget(self, "_changed")
	if not signal then
		signal = Signal.new("OnChanged")
		self._changed = signal
	end
	return signal:Connect(fn)
end

function Base:SetCallback(fn)
	self._callback = fn
	self._cfg.Callback = fn
	return self
end

function Base:SetVisible(visible)
	self._hidden = visible == false
	self:_applyVisibility()
	return self
end

function Base:SetTitle(text)
	self.Name = tostring(text)
	self._searchIndex = nil
	if rawget(self, "_mounted") and self._view and self._view.Title then
		self._view.Title.Text = self.Name
		RowView.layoutMarkers(self)
	end
	if self._spec.titleChanged then self._spec.titleChanged(self) end
	return self
end

function Base:SetDesc(text)
	text = text ~= nil and tostring(text) or nil
	if text == "" then text = nil end
	self._descText = text
	self._searchIndex = nil
	if rawget(self, "_mounted") then RowView.setDescription(self, text) end
	return self
end

function Base:SetTooltip(text)
	text = text ~= nil and tostring(text) or ""
	self._tooltipText = text ~= "" and text or nil
	self.HasTooltip = text ~= ""
	self._searchIndex = nil
	if rawget(self, "_mounted") then RowView.setTooltip(self, text) end
	if text == "" and self._window and self._window._tooltipHost then self._window._tooltipHost:hide() end
	return self
end
Base.Tooltip = Base.SetTooltip

function Base:Lock(reason)
	if type(reason) == "table" then reason = reason.Reason or reason.Text end
	self.Locked = true
	self.LockReason = reason ~= nil and tostring(reason) or nil
	if rawget(self, "_mounted") then
		RowView.setLock(self)
		self:_render(false)
	end
	local window = self._window
	if window and window._popover and window._popover:isOpen(self) then window._popover:close("lock") end
	return self
end

function Base:Unlock()
	self.Locked = false
	self.LockReason = nil
	if rawget(self, "_mounted") then
		RowView.setLock(self)
		self:_render(false)
	end
	return self
end

function Base:SetLocked(locked, reason)
	if locked then return self:Lock(reason) end
	return self:Unlock()
end

function Base:SetDisabled(disabled)
	self._disabled = disabled == true
	if rawget(self, "_mounted") then
		Env.try(self.Root, "Interactable", not self._disabled)
		self:_render(false)
	end
	return self
end

function Base:IsDisabled()
	return self._disabled == true or self._whenDisabled == true
end

function Base:_lockedPoke()
	local lock = self._lock
	if not lock or not lock.Badge then return end
	local window = self._window
	window._tooltipHost:schedule(lock.Badge, self.LockReason or "Locked", "press")
	local start = lock.Badge.Position
	if not Motion.reduced then
		lock.Badge.Position = start + UDim2.fromOffset(3, 0)
		task.delay(0.08, function() if lock.Badge.Parent then lock.Badge.Position = start end end)
	end
end

function Base:Focus()
	local window = self._window
	if window and window._focus then window._focus:focus(self, { visible = true, scroll = true }) end
	return self
end

function Base:Flash()
	self:_flash()
	return self
end

-- item: { Text (or Name), Icon, Shortcut, Danger, Disabled, Reason, Callback(element) }
function Base:AddMenuItem(item)
	if type(item) ~= "table" then return self end
	local items = rawget(self, "_menuItems") or {}
	local callback = item.Callback
	items[#items + 1] = {
		Text = tostring(item.Text or item.Name or item.Title or "Item"), Icon = item.Icon, Shortcut = item.Shortcut,
		Danger = item.Danger, Disabled = item.Disabled, Reason = item.Reason,
		Callback = callback and function() Util.xcall(callback, "Menu item", self, self) end,
	}
	self._menuItems = items
	return self
end

function Base:SetIcon(icon)
	self._cfg.Icon = icon
	if self._spec.iconChanged then self._spec.iconChanged(self) end
	return self
end

function Base:SetLoading(on)
	self._loading = on == true
	self:_render(false)
	return self
end

function Base:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	Store.unregister(self)
	local window = self._window
	if window then
		window._changes:forget(self)
		window._registry:remove(self)
		if window._popover and window._popover:isOpen(self) then window._popover:close("destroy") end
		if window._pins then window._pins:forget(self) end
	end
	for _, bind in ipairs(rawget(self, "_binds") or {}) do bind:unbind() end
	local signal = rawget(self, "_changed")
	if signal then signal:DisconnectAll() end
	if self._spec.destroy then pcall(self._spec.destroy, self) end
	if self._owner and self._owner._removeChild then self._owner:_removeChild(self) end
	if self._tab then self._tab:_removeElement(self) end
	if self._scope then self._scope:destroy() end
	self._scope = nil
	self._mounted = false
	self.Root = nil
end

-- ---------- context menu ----------
function Base:_menuItemsList()
	local window = self._window
	local items = {}
	local hasValue = self.Default ~= nil and self.Set ~= nil
	if hasValue then
		local changed = window._changes:isChanged(self)
		items[#items + 1] = { Text = "Reset to default", Icon = "rotate-ccw", Disabled = not changed, Callback = function() self:_resetWithUndo() end }
		items[#items + 1] = { Text = "Copy value", Icon = "copy", Shortcut = "Ctrl C", Callback = function() window:_copy(self:_copyText(), self) end }
		local clip = window._clipboard
		local pasteOk, reason = false, "Clipboard is empty"
		if clip and clip.type == self.Type then pasteOk = true
		elseif clip then reason = "Clipboard holds a different kind of value" end
		items[#items + 1] = { Text = "Paste value", Icon = "clipboard-paste", Shortcut = "Ctrl V", Disabled = not pasteOk, Reason = not pasteOk and reason or nil,
			Callback = function() self:_paste() end }
	end
	if self.Flag then
		items[#items + 1] = { Text = "Copy flag name", Icon = "copy", Callback = function() window:_copy(self.Flag) end }
	end
	if window._pins and (self.Type == "Toggle" or self.Type == "Button") then
		local pinned = window._pins:has(self)
		items[#items + 1] = { Text = pinned and "Unpin" or "Pin to quick dock", Icon = pinned and "pin-off" or "pin",
			Callback = function() window._pins:toggle(self) end }
	end
	items[#items + 1] = { Text = "Show in palette", Icon = "search", Callback = function() window:OpenPalette(self.Name) end }
	if self._spec.menu then self._spec.menu(self, items) end
	local extra = rawget(self, "_menuItems")
	if extra and #extra > 0 then
		items[#items + 1] = "divider"
		for _, item in ipairs(extra) do items[#items + 1] = item end
	end
	return items
end

function Base:_copyText()
	local value = self:_encodeValue()
	if type(value) == "table" then
		local ok, text = pcall(function() return Env.services.HttpService:JSONEncode(value) end)
		return ok and text or tostring(value)
	end
	return tostring(value)
end

function Base:_paste()
	local window = self._window
	local clip = window._clipboard
	if not clip or clip.type ~= self.Type or not self.Set then return end
	local previous = Util.copy(self:_rawValue())
	self:Set(Util.copy(clip.value))
	window._changes:remember(self, previous)
	if window._undoPill then window:_undoPill("Pasted into " .. self.Name) end
end

function Base:_openMenu(point)
	local window = self._window
	if self._cfg.ContextMenu == false or self._spec.noMenu or self._destroyed then return end
	local header = { Title = self.Flag or "No flag" }
	if self.Default ~= nil then
		local text
		if self._spec.describe then
			text = self._spec.describe(self, self.Default)
		else
			local value = self:_encodeValue(self.Default)
			text = type(value) == "table" and "custom" or tostring(value)
		end
		header.Subtitle = "Default: <b>" .. text .. "</b>"
	end
	local items = self:_menuItemsList()
	local anchor = point or (self._view and self._view.Root)
	ContextMenu.open(window, anchor, items, header)
end

-- ---------- define ----------
-- spec: { Type, flaggable, counts, display, title, reserve(self), height(self), init(self, cfg),
--   build(self, view, scope), render(self, animated), normalize, equals, payload, encodeValue,
--   mirror, describe, menu, hover, focus = { kind, activate, adjust }, methods, aliases, destroy }
function Element.define(spec)
	local class = Component.extend({ ClassName = spec.Type, base = Base, viewFields = spec.viewFields })
	class._spec = spec
	for name, fn in pairs(spec.methods or {}) do class[name] = fn end
	for alias, target in pairs(spec.aliases or {}) do
		class[alias] = class[target] or Base[target]
	end
	function class.create(owner, config, ...)
		local started = Env.clock()
		if spec.fromArgs then config = spec.fromArgs(config, ...) end
		config = type(config) == "table" and config or {}
		local section = owner.Section or owner
		local tab = section.Tab
		local window = tab.Window
		local element = class.new({
			Type = spec.Type,
			Name = tostring(config.Name or config.Title or spec.defaultName or "Control"),
			_cfg = config,
			_callback = config.Callback,
			_owner = owner,
			_tab = tab,
			_window = window,
			Section = section,
			-- rawget: a Section owner has a Row *builder method*; only a Column carries a row
			Row = rawget(owner, "Row"),
			_inRow = rawget(owner, "Row") and true or nil,
			Locked = false,
			HasTooltip = false,
		})
		if spec.init then spec.init(element, config) end
		if element.Default == nil and element.CurrentValue ~= nil and spec.flaggable then
			element.Default = Util.copy(element.CurrentValue)
		end
		element._order = owner:_addChild(element)
		tab:_addElement(element, spec.counts ~= false)
		window._registry:add(element)
		local tip = config.Tooltip or config.Tip
		if tip ~= nil and tip ~= "" then
			element._tooltipText = tostring(tip)
			element.HasTooltip = true
		end
		local desc = config.Description or config.Desc
		if desc ~= nil and desc ~= "" and not spec.descriptionIsContent then element._descText = tostring(desc) end
		if spec.flaggable and config.Flag ~= nil and config.Flag ~= "" then
			Store.register(config.Flag, element)
		end
		if config.VisibleWhen then
			window._registry:watch(element, config.VisibleWhen)
			element._visibleWhen = config.VisibleWhen
		end
		if config.EnabledWhen then
			window._registry:watch(element, config.EnabledWhen)
			element._enabledWhen = config.EnabledWhen
		end
		if config.VisibleWhen or config.EnabledWhen then element:_evaluateConditions() end
		if config.Pinned and window._pins then window._pins:add(element, true) end
		tab:_noteElement(element)
		Scheduler.noteForeground(Env.clock() - started)
		return element
	end
	return class
end

function Base:_evaluateConditions()
	local get = function(flag) return Store.get(flag) end
	if self._visibleWhen then
		local hidden = not Registry.evaluate(self._visibleWhen, get)
		if hidden ~= (self._whenHidden == true) then
			self._whenHidden = hidden
			self:_applyVisibility()
		end
	end
	if self._enabledWhen then
		local disabled = not Registry.evaluate(self._enabledWhen, get)
		if disabled ~= (self._whenDisabled == true) then
			self._whenDisabled = disabled
			self:_render(false)
		end
	end
end

return Element
