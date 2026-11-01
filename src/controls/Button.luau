--!nocheck
-- Button (DESIGN_V2 6.7). Secondary (default) is an action row with a chevron or keycap; Primary,
-- Ghost, Danger and DangerSoft are pills. Busy (SetLoading, Async) spins and blocks re-entry;
-- HoldToConfirm sweeps a fill for 0.8 s. Button.paint/run/glyph are shared with ButtonGroup.

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
local unglow = require("controls/Slider").Num.unglow

local T, F, TS = Token.T, Token.F, Token.TS
local HOLD = 0.8

-- variant = { fill token (nil: none until hover), label token }
local LOOK = {
	Primary = { "White", "OnAccent" }, Secondary = { "Active", "Text" }, Ghost = { nil, "AccentText" },
	Danger = { "Danger", "OnStatus" }, DangerSoft = { "DangerSoft", "Danger" },
}

-- Paints a pill for its variant and state ("rest" | "hover" | "pressed" | "inactive").
local function paint(pill, label, gradient, variant, state)
	local look = LOOK[variant] or LOOK.Secondary
	local inactive = state == "inactive"
	local ghost = variant == "Ghost"
	pill.BackgroundColor3 = Theme.get(inactive and "Active" or (ghost and "Hover" or look[1]))
	pill.BackgroundTransparency = ghost and (inactive or state == "rest") and 1 or 0
	label.TextColor3 = Theme.get(inactive and "Disabled" or look[2])
	if gradient then
		gradient.Enabled = not inactive
		gradient.Color = Token.resolve(state == "pressed" and Token.seq("Accent", "AccentDeep") or Token.seq("AccentHi", "Accent"))
	end
end

-- The busy spinner, the success check or the resting icon on one glyph image.
local function glyph(owner, image, rest, color, okColor)
	if not image then return end
	if owner._loading then
		if not owner._spin then
			Icons.apply(image, "loader-circle", nil)
			image.Rotation = 0
			owner._spin = Motion.loop(image, "spinner", { Rotation = 360 })
		end
		image.ImageColor3 = color
		image.Visible = true
		return
	end
	if owner._spin then
		owner._spin.stop()
		owner._spin = nil
		image.Rotation = 0
	end
	local icon = owner._ok and "check" or rest
	image.Visible = icon ~= nil
	if icon then
		Icons.apply(image, icon, nil)
		image.ImageColor3 = owner._ok and okColor or color
	end
end

local function success(owner)
	local token = {}
	owner._ok = token
	owner:_render()
	task.delay(1.2, function()
		if owner._ok == token then
			owner._ok = nil
			owner:_render()
		end
	end)
end

-- Runs the callback once. Blocked while busy; Async runs it in task.spawn with the spinner and
-- shows a check for 1.2 s when it returns true. owner: the Button or a ButtonGroup handle.
local function run(owner, element)
	if owner._loading or element._destroyed or element:_inactive() then return false end
	if not owner._async then
		Util.xcall(owner._callback, element:_context(), element)
		return true
	end
	owner:SetLoading(true)
	task.spawn(function()
		local ok, result = Util.xcall(owner._callback, element:_context(), element)
		if element._destroyed then return end
		owner:SetLoading(false)
		if ok and result == true then success(owner) end
	end)
	return true
end

-- ---------- hold to confirm ----------
local function cancelHold(self)
	if not self._holding then return end
	self._holding = nil
	if self._holdTween then pcall(self._holdTween.Cancel, self._holdTween) end
	self._holdTween = nil
	if self._holdEnd then self._holdEnd:Disconnect() end
	self._holdEnd = nil
	local sweep = self._sweep
	if sweep and sweep.Parent then
		sweep.Visible = false
		sweep.Size = UDim2.new(0, 0, 1, self._pill and 0 or -4)
	end
end

-- keys: started from Enter/Space/A, so releasing one of those cancels.
local function startHold(self, keys)
	if self._holding or self._loading or self:_inactive() then return end
	local token = {}
	self._holding = token
	local pill = self._pill
	local sweep = self._sweep
	if (not sweep or not sweep.Parent) and self._scope and rawget(self, "_mounted") then
		sweep = Factory.new(self._scope, "Frame", { Name = "HoldFill", BackgroundColor3 = pill and T.Shadow or T.Active,
			BackgroundTransparency = pill and 0.75 or 0, Position = UDim2.fromOffset(pill and 0 or 4, pill and 0 or 2),
			ZIndex = pill and 2 or 0 }, pill or self.Root)
		Factory.corner(self._scope, sweep, Metrics.radius.control)
		self._sweep = sweep
	end
	if sweep and sweep.Parent then
		sweep.Size = UDim2.new(0, 0, 1, pill and 0 or -4)
		sweep.Visible = true
		pcall(function()
			self._holdTween = Env.services.TweenService:Create(sweep, TweenInfo.new(HOLD, Enum.EasingStyle.Linear),
				{ Size = UDim2.new(1, pill and 0 or -8, 1, pill and 0 or -4) })
			self._holdTween:Play()
		end)
	end
	if keys then
		self._holdEnd = Env.services.UserInputService.InputEnded:Connect(function(input)
			local name = input.KeyCode and input.KeyCode.Name
			if name == "Return" or name == "Space" or name == "ButtonA" then cancelHold(self) end
		end)
	end
	task.delay(HOLD, function()
		if self._holding ~= token then return end
		cancelHold(self)
		self:_press()
	end)
end

-- Press feedback: UIScale 0.97 on pills; the row's pooled fill turns Active on action rows.
local function pressed(self, on)
	self._pressed = on
	local pill = self._pill
	if pill then
		local scale = self._pressScale
		if not scale or not scale.Parent then
			scale = Factory.new(self._scope, "UIScale", { Scale = 1 }, pill)
			self._pressScale = scale
		end
		Motion.tween(scale, "press", { Scale = on and 0.97 or 1 })
	elseif type(self.Row) ~= "table" then
		local section = self.Section
		local fill = section and rawget(section, "_hover")
		if fill then
			if on then section:_hoverRow(self, true) end
			fill.BackgroundColor3 = Theme.get(on and "Active" or "Hover")
			if not on and not self._hover then section:_hoverRow(self, false) end
		end
	end
	self:_render(false)
end

-- Pills draw their own hover, so the section's pooled row hover stays hidden under them.
local function hideRowHover(self)
	local fill = self.Section and rawget(self.Section, "_hover")
	if fill then fill.Visible = false end
end

-- A pill's icon sits left of the centred label; the label shifts right to centre the pair.
local function placeIcon(self)
	local image, title = self._glyph, self._view and self._view.Title
	if not image or not title or not self._pill then return end
	local width = RowView.textWidth(self.Name, Metrics.textSize("Label"))
	image.Position = UDim2.new(0.5, -math.floor(width / 2) - 4 - (self._cfg.Icon and 0 or 12), 0.5, 0)
	title.Position = UDim2.fromOffset(self._cfg.Icon and 12 or 0, 0)
end

local function input(kind)
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

-- A pill row's description goes under the pill, not over it (RowView puts it at band - 12).
local function underPill(self)
	local view = self._view
	local desc = view and view.Description
	if desc and (self._pill or self.Buttons) then desc.Position = UDim2.fromOffset(view.padH, Metrics.get("control") + 16) end
end

-- Destroy and unmount: no hold, spinner or glow outlives the view.
local function stopAll(self)
	cancelHold(self)
	if self._spin then self._spin.stop() end
	self._spin = nil
	if self._variant == "Primary" then unglow(self, 3) end
end

local Button
Button = Element.define({
	Type = "Button",
	defaultName = "Button",

	init = function(self, config)
		local variant = tostring(config.Variant or "Secondary")
		self._variant = LOOK[variant] and variant or "Secondary"
		self._async = config.Async == true
		self._hold = config.HoldToConfirm == true
		self._cap = config.Shortcut ~= nil and tostring(config.Shortcut) or nil
		local code = config.Keybind and config.Keybind ~= "None" and Util.keyCode(config.Keybind)
		if code then
			self._cap = self._cap or Util.keyName(code)
			self._binds = { Router.bind({
				key = code, owner = self, mode = self._hold and "Hold" or "Press", priority = 50,
				enabled = function() return not self._destroyed and not self:_inactive() end,
				onPress = function() if self._hold then startHold(self) else self:_press() end end,
				onRelease = function() cancelHold(self) end,
			}) }
		end
	end,

	reserve = function(self)
		if self._variant ~= "Secondary" then return 0 end
		return self._cap and math.max(28, RowView.textWidth(self._cap, Metrics.textSize("Key")) + 16) or 16
	end,

	height = function(self)
		if self._variant ~= "Secondary" then return Metrics.get("control") + 20 end
		return nil
	end,

	build = function(self, view, scope)
		local root, title = view.Root, view.Title
		local icon = self._cfg.Icon
		self._glyph, self._chevron, self._icon, self._sweep, self._pressScale, self._spin = nil, nil, nil, nil, nil, nil
		if self._variant ~= "Secondary" then
			-- centre-anchored, so the press UIScale shrinks it in place
			local height = Metrics.get("control") + 4
			local pill = Factory.new(scope, "Frame", { Name = "Pill", AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 8 + height / 2), Size = UDim2.new(1, -24, 0, height), ZIndex = 2 }, root)
			Factory.corner(scope, pill, Metrics.radius.control)
			self._gradient = self._variant == "Primary" and Factory.new(scope, "UIGradient", { Rotation = 90 }, pill) or nil
			title.Parent = pill
			title.Position = UDim2.new()
			title.Size = UDim2.fromScale(1, 1)
			title.TextXAlignment = Enum.TextXAlignment.Center
			title.ZIndex = 3
			self._pill = pill
			if icon then
				self._glyph = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, pill)
				placeIcon(self)
			end
		else
			if self._cap then
				local cap = RowView.control(view, Factory.text(scope, "TextLabel", { Name = "Keycap", Text = self._cap, FontFace = F.Key,
					TextSize = TS.Key, BackgroundColor3 = T.Raised, BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 2 }, root), view.reserve, 22)
				Factory.corner(scope, cap, Metrics.radius.keycap)
			else
				self._chevron = RowView.control(view, Factory.new(scope, "ImageLabel", { Name = "Chevron", BackgroundTransparency = 1, ZIndex = 2 }, root), 16, 16)
				self._glyph = self._chevron
			end
			if icon then
				self._icon = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Position = UDim2.fromOffset(view.padH, RowView.bandY(view, 16)),
					Size = UDim2.fromOffset(16, 16), ZIndex = 2 }, root)
				Icons.apply(self._icon, icon, nil)
				self._glyph = self._glyph or self._icon
				-- the title, its markers and the description start after the icon
				view.padH += 24
				title.Position = UDim2.fromOffset(view.padH, 0)
				title.Size = UDim2.new(1, -(RowView.titleInset(view) - 24), 0, view.band)
			end
		end
		scope:connect(root.MouseButton1Click, function()
			if not self._hold then self:_press() end
		end)
		scope:connect(root.InputBegan, function(event)
			if not input(event.UserInputType) or self:_inactive() or self._loading then return end
			pressed(self, true)
			if self._hold then
				startHold(self)
				-- a hold is not a long-press for the row menu
				task.defer(function() self._pressToken = nil end)
			end
		end)
		scope:connect(root.InputEnded, function(event)
			if not input(event.UserInputType) then return end
			if self._pressed then pressed(self, false) end
			cancelHold(self)
		end)
	end,

	render = function(self)
		local view = self._view
		if not view then return end
		local inactive = self:_inactive()
		if self._pill then
			underPill(self)
			paint(self._pill, view.Title, self._gradient, self._variant,
				inactive and "inactive" or (self._pressed and "pressed" or (self._hover and "hover" or "rest")))
			if (self._loading or self._ok) and not self._glyph and self._scope then
				self._glyph = Factory.new(self._scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, self._pill)
				placeIcon(self)
			end
			glyph(self, self._glyph, self._cfg.Icon, view.Title.TextColor3, view.Title.TextColor3)
			return
		end
		local color = Theme.get(inactive and "Disabled" or "Text2")
		if self._icon then self._icon.ImageColor3 = color end
		if (self._loading or self._ok) and not self._glyph and self._scope then
			-- a keycap row without an icon: the spinner goes left of the keycap
			self._glyph = RowView.control(view, Factory.new(self._scope, "ImageLabel", { Name = "Status", BackgroundTransparency = 1, ZIndex = 2 }, view.Root),
				16, 16, view.reserve + 8)
		end
		local rest = self._glyph == self._chevron and "chevron-right" or (self._glyph == self._icon and self._cfg.Icon or nil)
		glyph(self, self._glyph, rest, color, Theme.get("Success"))
	end,

	hover = function(self, on)
		if self._pill then
			hideRowHover(self)
			local glow = self._window._glow
			if on and glow and self._variant == "Primary" and not self:_inactive() then
				glow:acquire(3, self, self._pill, { duration = 0.45, spread = 8 })
			end
		end
		if not on then
			if self._variant == "Primary" then unglow(self, 3) end
			cancelHold(self)
			if self._pressed then pressed(self, false) return end
		end
		self:_render(false)
	end,

	titleChanged = placeIcon,

	focus = {
		activate = function(self)
			if self._hold then startHold(self, true) else self:_press() end
		end,
	},

	methods = {
		-- Pins, the command palette and keybinds press through here.
		_press = function(self) return run(self, self) end,

		SetLoading = function(self, on)
			on = on == true
			if (self._loading == true) == on then return self end
			self._loading = on
			if on then cancelHold(self) end
			self:_render(false)
			return self
		end,

		SetDesc = function(self, text)
			Element.Base.SetDesc(self, text)
			underPill(self)
			return self
		end,
	},
	aliases = { Set = "SetTitle" },

	destroy = stopAll,
	unmount = stopAll,
})

Button.paint, Button.run, Button.glyph, Button.LOOK, Button.underPill = paint, run, glyph, LOOK, underPill
return Button
