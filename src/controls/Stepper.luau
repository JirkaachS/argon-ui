--!nocheck
-- Stepper (DESIGN_V2 6.10): minus, an editable value and plus in one Well. Press and hold
-- repeats (350 ms, then every 80 ms, every 40 ms after about 1 s); a sign dims at its limit.
-- Numbers follow the Slider model (Slider.Num): Range, Increment, Suffix, typing, validation.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local Drag = require("input/Drag")
local Num = require("controls/Slider").Num

local T, F, TS = Token.T, Token.F, Token.TS

-- One step now, then repeats while the press lasts (a Drag session tracks the release).
local function hold(self, input, dir)
	local token = {}
	self._hold = token
	local count = 0
	local function step()
		local before = self.CurrentValue
		Num.adjust(self, dir)
		if self.CurrentValue == before then self._hold = nil end
	end
	local function again(delay)
		local scope = self._scope
		if not scope then return end
		scope:delay(delay, function()
			if self._hold ~= token or self:_inactive() then return end
			step()
			count += 1
			if self._hold == token then again(count >= 8 and 0.04 or 0.08) end
		end)
	end
	step()
	again(0.35)
	Drag.begin(input, {
		onMove = function() end,
		onEnd = function() if self._hold == token then self._hold = nil end end,
	})
end

local function stop(self)
	self._hold = nil
	self._editing = false
	Num.unwire(self)
end

local Stepper = Element.define({
	Type = "Stepper",
	defaultName = "Stepper",
	flaggable = true,
	viewFields = { "_group", "_valueBox" },

	init = Num.init,

	reserve = function(self)
		self._groupW = Num.width(self, 2 * Metrics.get("control") + 4, 108, 200)
		return self._groupW
	end,

	build = function(self, view, scope)
		local height = Metrics.get("control")
		local inset = height - 2 -- one sign's hit area: the inner 28 px button plus its 2 px gap
		local group = RowView.control(view, Factory.new(scope, "TextButton", { Name = "Group", BackgroundColor3 = T.Well, ZIndex = 2 }, view.Root),
			self._groupW, height)
		Factory.corner(scope, group, Metrics.radius.control)
		local function sign(name, x)
			local image = Factory.new(scope, "ImageLabel", { Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(x, x == 0 and inset / 2 + 1 or -(inset / 2 + 1), 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 3 }, group)
			Icons.apply(image, name == "Minus" and "minus" or "plus", nil)
			return image
		end
		self._minus, self._plus = sign("Minus", 0), sign("Plus", 1)
		local box = Factory.text(scope, "TextBox", { Name = "Value", FontFace = F.Value, TextSize = TS.Value, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Center, RichText = true, Position = UDim2.fromOffset(inset, 0),
			Size = UDim2.new(1, -2 * inset, 1, 0), ZIndex = 3 }, group)
		self._group, self._valueBox, self._hoverFill, self._hoverSide = group, box, nil, 0
		-- -1 over minus, 1 over plus, 0 over the value (screen x)
		local function side(x)
			local width = group.AbsoluteSize.X
			local edge, at = inset * width / self._groupW, x - group.AbsolutePosition.X
			return at <= edge and -1 or (at >= width - edge and 1 or 0)
		end
		scope:connect(group.InputBegan, function(input)
			local kind = input.UserInputType
			if (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) or self:_inactive() then return end
			local dir = side(input.Position.X)
			if dir ~= 0 then hold(self, input, dir) end
		end)
		-- hover fills the inner button under the pointer (built on first hover)
		scope:connect(group.MouseMoved, function(x)
			local now = side(x)
			if now ~= self._hoverSide then
				self._hoverSide = now
				self:_render(false)
			end
		end)
		scope:connect(group.MouseLeave, function()
			self._hoverSide = 0
			self:_render(false)
		end)
		Num.wire(self, scope, box)
	end,

	render = function(self)
		local box = self._valueBox
		if not box then return end
		local inactive, value = self:_inactive(), self.CurrentValue
		local atMin, atMax = inactive or value <= self._min, inactive or value >= self._max
		self._minus.ImageColor3 = Theme.get(atMin and "Disabled" or "Text2")
		self._plus.ImageColor3 = Theme.get(atMax and "Disabled" or "Text2")
		local hovered = self._hoverSide or 0
		if hovered ~= 0 and not (hovered < 0 and atMin or hovered > 0 and atMax) then
			local fill = self._hoverFill
			if not fill then
				local size = Metrics.get("control") - 4
				fill = Factory.new(self._scope, "Frame", { Name = "HoverFill", BackgroundColor3 = T.Hover, AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(size, size), ZIndex = 2 }, self._group)
				Factory.corner(self._scope, fill, Metrics.radius.control28)
				self._hoverFill = fill
			end
			fill.Position = (hovered < 0 and self._minus or self._plus).Position
			fill.Visible = true
		elseif self._hoverFill then
			self._hoverFill.Visible = false
		end
		if not self._editing then
			box.RichText = true
			box.Text = Num.rich(self)
		end
		box.TextColor3 = Theme.get(inactive and "Disabled" or "Text")
		box.TextEditable = not inactive
	end,

	normalize = Num.normalize,
	describe = Num.describe,

	focus = {
		activate = function(self) if self._valueBox then self._valueBox:CaptureFocus() end end,
		adjust = Num.adjust,
	},

	methods = { Set = Num.Set },
	destroy = stop,
	unmount = function(self)
		stop(self)
		self._group, self._valueBox = nil, nil
	end,
})

return Stepper
