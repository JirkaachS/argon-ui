--!nocheck
-- Toggle: a switch (default) or a checkbox (DESIGN_V2 6.8). State is never shown by colour
-- alone: the knob carries a check glyph, and On/Off labels appear on touch, gamepad and High
-- contrast. The colour change is a tween of one "On" overlay; the knob moves on a spring.

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
local Prefs = require("persist/Prefs")

local T, F, TS = Token.T, Token.F, Token.TS

local function stateLabels()
	local mode = Prefs.get("StateLabels") or "Auto"
	if mode == "Always" then return true end
	if mode == "Off" then return false end
	return Metrics.density == "Touch" or Metrics.density == "Gamepad" or Theme.name == "HighContrast"
end

local function sizes(self)
	if self._style == "Checkbox" then return 20, 20, 14 end
	return Metrics.get("switchW"), Metrics.get("switchH"), Metrics.get("knob")
end

local Toggle
Toggle = Element.define({
	Type = "Toggle",
	defaultName = "Toggle",
	flaggable = true,
	viewFields = { "_track", "_knob" },

	init = function(self, config)
		self.CurrentValue = config.CurrentValue == true
		self._style = config.Style == "Checkbox" and "Checkbox" or "Switch"
		if config.Keybind and config.Keybind ~= "None" then
			local code = Util.keyCode(config.Keybind)
			if code then
				self._bindKey = code
				self._binds = { Router.bind({
					key = code, owner = self, mode = "Press", priority = 50,
					enabled = function() return not self._destroyed and not self:_inactive() end,
					onPress = function() self:_setValue(not self.CurrentValue, { source = "user" }) end,
				}) }
			end
		end
	end,

	reserve = function(self)
		local width = sizes(self)
		if self._bindKey then width += 36 end
		if stateLabels() then width += 32 end
		return width
	end,

	build = function(self, view, scope)
		local width, height, knobSize = sizes(self)
		local checkbox = self._style == "Checkbox"
		local track = RowView.control(view, Factory.new(scope, "Frame", {
			Name = "Track",
			BackgroundColor3 = T.Track,
			ZIndex = 2,
		}, view.Root), width, height)
		Factory.corner(scope, track, checkbox and Metrics.radius.checkbox or "full")
		self._trackStroke = checkbox and Factory.stroke(scope, track, T.Border, 0, 1) or nil
		local on = Factory.new(scope, "Frame", {
			Name = "On",
			BackgroundColor3 = T.White,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, track)
		Factory.corner(scope, on, checkbox and Metrics.radius.checkbox or "full")
		Factory.new(scope, "UIGradient", { Rotation = 135, Color = Token.seq("AccentHi", "Accent") }, on)
		local knob, check
		if checkbox then
			check = Factory.new(scope, "ImageLabel", {
				Name = "Check", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), ZIndex = 5,
			}, track)
			Icons.apply(check, "check", nil)
		else
			knob = Factory.new(scope, "Frame", {
				Name = "Knob",
				BackgroundColor3 = T.White,
				Size = UDim2.fromOffset(knobSize, knobSize),
				Position = UDim2.fromOffset(3, math.floor((height - knobSize) / 2)),
				ZIndex = 4,
			}, track)
			Factory.corner(scope, knob, "full")
			check = Factory.new(scope, "ImageLabel", {
				Name = "Check", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 5,
			}, knob)
			Icons.apply(check, "check", nil)
		end
		self._track, self._knob, self._on, self._check = track, knob, on, check
		local x = view.padH + width + 8
		if stateLabels() then
			self._stateText = Factory.text(scope, "TextLabel", {
				Name = "StateText", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -x, 0, RowView.bandY(view, 20)),
				Size = UDim2.fromOffset(28, 20), TextXAlignment = Enum.TextXAlignment.Right,
			}, view.Root)
			x += 32
		end
		if self._bindKey then
			local cap = Factory.text(scope, "TextLabel", {
				Name = "Keycap", Text = Util.keyName(self._bindKey), FontFace = F.Key, TextSize = TS.Key,
				BackgroundColor3 = T.Raised, BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -x, 0, RowView.bandY(view, 22)), Size = UDim2.fromOffset(28, 22),
			}, view.Root)
			Factory.corner(scope, cap, Metrics.radius.keycap)
		end
		scope:connect(view.Root.MouseButton1Click, function()
			if self:_inactive() then return end
			self:_setValue(not self.CurrentValue, { source = "user" })
		end)
	end,

	render = function(self, animated)
		local track = self._track
		if not track then return end
		local value = self.CurrentValue == true
		local inactive = self:_inactive()
		local checkbox = self._style == "Checkbox"
		local width, height, knobSize = sizes(self)
		if inactive then
			track.BackgroundColor3 = Theme.get("Disabled")
			track.BackgroundTransparency = 0.5
		else
			track.BackgroundColor3 = Theme.get(value and "Accent" or (checkbox and "Well" or "Track"))
			track.BackgroundTransparency = 0
		end
		if self._trackStroke then self._trackStroke.Transparency = value and 1 or 0 end
		local onTarget = (value and not inactive) and 0 or 1
		if animated then
			Motion.tween(self._on, "state", { BackgroundTransparency = onTarget })
		else
			self._on.BackgroundTransparency = onTarget
		end
		local check = self._check
		check.ImageColor3 = Theme.get(checkbox and "OnAccent" or "AccentDeep")
		check.ImageTransparency = value and 0 or 1
		local knob = self._knob
		if knob then
			knob.BackgroundColor3 = Theme.get(inactive and "Disabled" or "White")
			knob.BackgroundTransparency = (not value and not inactive) and 0.12 or 0
			local y = math.floor((height - knobSize) / 2)
			local target = UDim2.fromOffset(value and (width - knobSize - 3) or 3, y)
			Motion.spring(knob, "Position", target, "snappy", animated)
		end
		if self._stateText then
			self._stateText.Text = value and "On" or "Off"
			self._stateText.TextColor3 = Theme.get(value and "Text" or "Text2")
		end
		if animated and value and self._window._glow then
			self._window._glow:acquire(3, self, track, { duration = 0.45, spread = 8 })
		end
	end,

	hover = function(self, on)
		local track = self._track
		if track and not self.CurrentValue and not self:_inactive() then
			track.BackgroundColor3 = Theme.get(on and "Active" or (self._style == "Checkbox" and "Well" or "Track"))
		end
	end,

	normalize = function(_, value)
		return value == true
	end,

	describe = function(_, value)
		return value and "On" or "Off"
	end,

	focus = {
		activate = function(self) self:_setValue(not self.CurrentValue, { source = "user" }) end,
		adjust = function(self, step) self:_setValue(step > 0, { source = "user" }) end,
	},

	menu = function(self, items)
		if self._window._pins then
			-- pinning is offered by the base menu; nothing extra here
		end
	end,

	methods = {
		Set = function(self, value, silent)
			return self:_setValue(value, { silent = silent == true, source = "api" })
		end,
	},
})

return Toggle
