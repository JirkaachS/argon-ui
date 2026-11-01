--!nocheck
-- Keybind (DESIGN_V2 6.14): a keycap row with one Router entry (locked, disabled or destroyed
-- binds never fire), capture with a 5 s drain bar, conflict hints with Swap/Keep, and the
-- callback modes of ARCHITECTURE_V2 14.3 (D3): Rayfield, v1 (OnPressed) and CallOnChange.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Util = require("core/Util")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Router = require("input/Router")
local Store = require("persist/Store")
local Num = require("controls/Slider").Num

local T, F, TS = Token.T, Token.F, Token.TS
local LISTEN = "Press a key…"

-- Short labels for long key names (the stored value stays the KeyCode name).
local SHORT = {
	LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift", LeftAlt = "LAlt",
	RightAlt = "RAlt", Return = "Enter", Backspace = "Bksp", MouseButton2 = "RMB", MouseButton3 = "MMB",
	CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn", Backquote = "`",
}
local function label(name)
	return SHORT[name] or name:gsub("^Keypad", "Num ")
end

local function keyName(raw)
	if raw == nil or raw == "" or raw == "None" then return "None" end
	local code = Util.keyCode(raw)
	if not code and type(raw) == "string" and #raw == 1 then code = Util.keyCode(raw:upper()) end
	return code and code.Name or nil
end

local function overlay(self)
	local overlays = self._window._overlays
	if overlays and overlays.refreshKeybinds then overlays:refreshKeybinds() end
end

local function setActive(self, on)
	on = on == true
	if self._active == on then return end
	self._active = on
	self:_render(false)
	overlay(self)
end

local function call(self, fn, label2, ...)
	if type(fn) == "function" then Util.xcall(fn, self:_context() .. label2, self, ...) end
end

-- ---------- presses ----------
-- Rayfield mode: Callback() on press, or Callback(true) / Callback(false) with HoldToInteract.
-- v1 mode: OnPressed(key, active); Toggle latches active, Press is a 0.18 s pulse.
local function press(self)
	local mode = self._mode
	local active = mode ~= "Toggle" or not self._active
	setActive(self, active)
	if mode == "Press" then
		local token = {}
		self._pulse = token
		task.delay(0.18, function() if self._pulse == token then setActive(self, false) end end)
	end
	if self._compat == "rayfield" then
		if mode == "Hold" then call(self, self._callback, "", true) else call(self, self._callback, "") end
	elseif self._onPressed then
		call(self, self._onPressed, " OnPressed", self.CurrentValue, active)
	end
end

local function release(self)
	setActive(self, false)
	if self._destroyed then return end
	if self._compat == "rayfield" then
		call(self, self._callback, "", false)
	elseif self._onPressed then
		call(self, self._onPressed, " OnPressed", self.CurrentValue, false)
	end
end

-- ---------- capture ----------
-- Click, Enter or A starts it. Any key, MouseButton2/3 or pad button sets it; Backspace, Delete
-- or B set None; a click outside, Escape or the 5 s timeout keep the old key.
local function inside(gui, position)
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
end

local function stopCapture(self)
	if not self._capturing then return end
	self._capturing = false
	if self._layer then self._layer.remove() end
	self._layer = nil
	Num.unglow(self, 3)
	if self._drain and self._drain.Parent then self._drain.Visible = false end
	Num.message(self, nil)
	self:_render(false)
end

local function conflict(self, name)
	local code = Util.keyCode(name)
	if not code then return nil end
	for _, entry in ipairs(Router.lookup(code)) do
		if entry ~= self._bind.entry and entry.owner ~= self then return entry end
	end
	return nil
end

-- A user rebind: commits, then warns when another binding already used the key. The check runs
-- first, so a callback that moves a binding onto the new key (the menu key row) is no conflict.
local function assign(self, name)
	local old = self.CurrentValue
	local entry = name ~= "None" and name ~= old and conflict(self, name)
	self:_setValue(name, { source = "user" })
	if not entry then return end
	local owner = entry.owner
	local window = owner and rawget(owner, "_toggleBind") and owner._toggleBind.entry == entry and owner
	local other = owner and owner.Type == "Keybind" and owner.Set and owner
	local actions = { { "Keep", function() Num.message(self, nil) end } }
	if other or window then
		table.insert(actions, 1, { "Swap", function()
			Num.message(self, nil)
			if other then other:Set(old) else window:SetToggleKey(old) end
		end })
	end
	local who = window and "Show or hide UI" or tostring(owner and (rawget(owner, "Name") or owner.Name) or "another action")
	Num.message(self, ("Also used by %s. Both will fire."):format(who), "Warning", nil, actions)
end

local function onInput(self, input)
	if self._destroyed or self._window._destroyed then
		stopCapture(self)
		return false
	end
	local kind = input.UserInputType and input.UserInputType.Name or ""
	local key = input.KeyCode and input.KeyCode.Name or "Unknown"
	if kind == "MouseButton1" or kind == "Touch" then
		-- a click outside cancels; a click on the row reaches the row, which toggles capture
		if not (self.Root and inside(self.Root, input.Position)) then stopCapture(self) end
		return false
	end
	local name
	if kind == "MouseButton2" or kind == "MouseButton3" then
		name = kind
	elseif kind == "Keyboard" or kind:sub(1, 7) == "Gamepad" then
		if key == "Unknown" or key:sub(1, 10) == "Thumbstick" then return false end
		if key == "Escape" then
			stopCapture(self)
			return true
		end
		name = (key == "Backspace" or key == "Delete" or key == "ButtonB") and "None" or key
	else
		return false
	end
	stopCapture(self)
	assign(self, name)
	return true
end

local function startCapture(self)
	if self._capturing or self:_inactive() or not rawget(self, "_mounted") then return end
	self._capturing = true
	self._captureToken = (self._captureToken or 0) + 1
	local token = self._captureToken
	self._layer = Router.layerKey(function(input) return onInput(self, input) end, 200)
	Num.message(self, Router.lastInputKind == "gamepad" and "Mouse buttons work · B clears" or "Mouse buttons work · Backspace clears", "Muted")
	self:_render(false)
	local cap = self._cap
	local glow = self._window._glow
	if glow then glow:acquire(3, self, cap, { spread = 8 }) end
	local drain = self._drain
	if not drain or not drain.Parent then
		drain = Factory.new(self._scope, "Frame", { Name = "Drain", BackgroundColor3 = T.Accent, ZIndex = 3 }, self.Root)
		Factory.corner(self._scope, drain, "full")
		self._drain = drain
	end
	local width = cap.Size.X.Offset
	drain.Position = UDim2.new(1, -(self._view.padH + width - 4), 0, cap.Position.Y.Offset + cap.Size.Y.Offset + 3)
	drain.Size = UDim2.fromOffset(width - 8, 2)
	drain.Visible = true
	Motion.tween(drain, "drain", { Size = UDim2.fromOffset(0, 2) })
	self._scope:delay(5, function()
		if self._captureToken == token then stopCapture(self) end
	end)
end

local function forget(self)
	stopCapture(self)
	self._pulse = nil
end

local Keybind = Element.define({
	Type = "Keybind",
	defaultName = "Keybind",
	flaggable = true,
	viewFields = { "_cap" },

	init = function(self, config)
		local key = keyName(config.CurrentKeybind) or "None"
		self.CurrentValue, self.CurrentKeybind = key, key
		local pressed = config.OnPressed or config.Pressed
		self._onPressed = type(pressed) == "function" and pressed or nil
		self._compat = self._onPressed and "v1" or (config.CallOnChange == true and "change" or "rayfield")
		local mode = config.Mode
		self._mode = (mode == "Press" or mode == "Toggle" or mode == "Hold") and mode
			or (config.HoldToInteract == true and "Hold") or (config.Toggle == true and "Toggle") or "Press"
		self._active = config.Active == true
		self.DisplayInKeybindList = config.DisplayInKeybindList ~= false
		self._bind = Router.bind({
			key = Util.keyCode(key), owner = self, mode = self._mode == "Hold" and "Hold" or "Press", priority = 50,
			enabled = function() return not self._destroyed and not self._capturing and not self:_inactive() end,
			onPress = function() press(self) end,
			onRelease = function() release(self) end,
		})
		self._binds = { self._bind }
		local window = self._window
		window._keybinds = window._keybinds or {}
		table.insert(window._keybinds, self)
		overlay(self)
	end,

	reserve = function(self)
		local text = self._capturing and LISTEN or label(self.CurrentValue)
		self._capW = math.max(32, RowView.textWidth(text, Metrics.textSize("Key")) + 16)
		self._modeW = self._mode ~= "Press" and RowView.textWidth(self._mode, Metrics.textSize("Caption")) or 0
		return self._capW + (self._modeW > 0 and self._modeW + 8 or 0)
	end,

	build = function(self, view, scope)
		local cap = RowView.control(view, Factory.text(scope, "TextLabel", { Name = "Cap", BackgroundColor3 = T.Raised, BackgroundTransparency = 0,
			FontFace = F.Key, TextSize = TS.Key, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 2 }, view.Root), self._capW, 24)
		Factory.corner(scope, cap, Metrics.radius.keycap)
		self._capStroke = Factory.stroke(scope, cap, T.Border, 0, 1)
		self._cap, self._drain, self._modeText, self._capText = cap, nil, nil, nil
		if self._modeW > 0 then
			self._modeText = RowView.control(view, Factory.text(scope, "TextLabel", { Name = "ModeText", Text = self._mode, FontFace = F.Caption,
				TextSize = TS.Caption, TextColor3 = T.Text2, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2 }, view.Root),
				self._modeW, 24, self._capW + 8)
		end
		scope:connect(view.Root.MouseButton1Click, function()
			if self._capturing then stopCapture(self) else startCapture(self) end
		end)
	end,

	render = function(self)
		local cap = self._cap
		if not cap then return end
		local inactive, listening, key = self:_inactive(), self._capturing, self.CurrentValue
		if listening and inactive then return stopCapture(self) end
		local text = listening and LISTEN or label(key)
		cap.Text = text
		cap.FontFace = Token.resolve(listening and F.Caption or F.Key)
		cap.BackgroundColor3 = Theme.get(listening and "AccentSoft" or "Raised")
		cap.TextColor3 = Theme.get(inactive and "Disabled" or ((listening or self._active) and "AccentText" or (key == "None" and "Dim" or "Text")))
		self._capStroke.Color = Theme.get(listening and "Accent" or "Border")
		self._capStroke.Transparency = listening and 0.5 or 0
		-- the cap sizes to its text; the title column follows
		if text == self._capText then return end
		self._capText = text
		local width = math.max(32, RowView.textWidth(text, Metrics.textSize("Key")) + 16)
		if width ~= self._capW then
			self._capW = width
			cap.Size = UDim2.fromOffset(width, 24)
			if self._modeText then self._modeText.Position = UDim2.new(1, -(self._view.padH + width + 8), 0, cap.Position.Y.Offset) end
			RowView.setReserve(self, width + (self._modeW > 0 and self._modeW + 8 or 0))
		end
	end,

	normalize = function(_, raw) return keyName(raw) end,

	mirror = function(self)
		self.CurrentKeybind = self.CurrentValue
		self._bind:rebind(Util.keyCode(self.CurrentValue))
		overlay(self)
	end,

	focus = {
		activate = startCapture,
	},

	titleChanged = overlay,

	methods = {
		-- Accepts a KeyCode, a mouse or pad EnumItem, or its name; "None" (or nil) unbinds.
		Set = function(self, key, silent)
			return self:_setValue(key == nil and "None" or key, { silent = silent == true, source = "api" })
		end,

		SetActive = function(self, on)
			setActive(self, on)
			return self
		end,

		SetOverlayVisible = function(self, visible)
			self.DisplayInKeybindList = visible ~= false
			overlay(self)
			return self
		end,

		IsActive = function(self) return self._active == true end,

		-- The commit path for a rebind (D3): listeners and autosave always; Callback(key) only in
		-- v1 and CallOnChange modes; OnChanged(key) always.
		_commit = function(self, source)
			Store.commit(self)
			self:_flash()
			if self._compat ~= "rayfield" then call(self, self._callback, "", self.CurrentValue) end
			call(self, self._cfg.OnChanged, " OnChanged", self.CurrentValue)
			self:_fireCommit(source)
		end,

		-- What LoadConfiguration fires: Callback(key) in v1 mode only.
		_restoreCallback = function(self)
			if self._compat ~= "v1" or type(self._callback) ~= "function" then return true end
			return Util.xcall(self._callback, "restore of " .. tostring(self.Flag), self, self.CurrentValue)
		end,

		_encode = function(self) return self.CurrentValue end,
	},

	destroy = function(self)
		forget(self)
		local list = self._window._keybinds
		local index = list and table.find(list, self)
		if index then table.remove(list, index) end
		overlay(self)
	end,

	unmount = function(self)
		forget(self)
		self._cap = nil
	end,
})

return Keybind
