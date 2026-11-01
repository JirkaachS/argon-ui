--!nocheck
-- ProgressBar (DESIGN_V2 6.17): title, a mono readout at the right, and a 6 px track under the
-- band with an Accent -> AccentAlt fill. Thresholds recolour the fill solid, SetColor takes a
-- Color3 (fixed) or a token (follows themes), Steps draws segments, and Indeterminate sweeps a
-- 30 % segment inside the track only while it is on screen. Never flagged or persisted (v1).

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Util = require("core/Util")
local Element = require("component/Element")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")

local T, F, TS = Token.T, Token.F, Token.TS
local Base = Element.Base

local function tone(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "string" then return Theme.get(value) end
	return nil
end

local function ratio(self)
	local low, high = self.Minimum, self.Maximum
	if high <= low then return self.CurrentValue >= high and 1 or 0 end
	return math.clamp((self.CurrentValue - low) / (high - low), 0, 1)
end

local function number(value)
	if value == math.floor(value) and math.abs(value) < 1e15 then return ("%d"):format(value) end
	return (("%.2f"):format(value):gsub("%.?0+$", ""))
end

local function readout(self)
	if self._indeterminate then return "" end
	local share = ratio(self)
	local format = self._cfg.Format
	if type(format) == "function" then
		local ok, text = Util.xcall(format, self:_context() .. " Format", self, self.CurrentValue, self.Maximum, share)
		if ok and text ~= nil then return tostring(text) end
	end
	if self._cfg.ShowValue then
		local suffix = self._cfg.Suffix ~= nil and tostring(self._cfg.Suffix) or ""
		if suffix:match("^%a") and #suffix > 2 then suffix = " " .. suffix end
		return number(self.CurrentValue) .. suffix
	end
	return math.floor(share * 100 + 0.5) .. "%"
end

-- The solid colour for the current state, or nil for the default gradient.
local function solid(self)
	if self:_inactive() then return Theme.get("Disabled") end
	local share, hit = ratio(self), nil
	for _, entry in ipairs(self._thresholds) do
		if share + 1e-9 >= entry[1] then hit = entry[2] end
	end
	return tone(hit) or tone(self._color)
end

-- Starts or stops the sweep to match "indeterminate and on screen"; re-checks twice a second.
local function sweep(self)
	local fill = self._fill
	if not fill then return end
	local want = self._indeterminate and self:_onScreen()
	if want and not self._loop then
		fill.Position = UDim2.new()
		fill.Size = UDim2.fromScale(0.3, 1)
		self._loop = Motion.loop(fill, "indeterminate", { Position = UDim2.fromScale(0.7, 0) })
	elseif not want and self._loop then
		self._loop.stop()
		self._loop = nil
		fill.Position = UDim2.new()
	end
	if self._indeterminate and not self._watch then
		self._watch = self._scope:delay(0.5, function()
			self._watch = nil
			sweep(self)
		end)
	end
end

local function stop(self)
	if self._loop then
		self._loop.stop()
		if self._fill then self._fill.Position = UDim2.new() end
	end
	self._loop = nil
	if self._watch then self._watch.cancel() end
	self._watch = nil
end

-- The description goes under the track; the row grows with it.
local function place(self)
	local view = self._view
	if not view then return end
	local desc = view.Description
	if desc and desc.Visible then
		desc.Position = UDim2.fromOffset(view.padH, view.band + 6)
		desc.Size = UDim2.new(1, -view.padH * 2, 0, 0)
	else
		view.Root.Size = UDim2.new(1, 0, 0, view.band + Metrics.get("padV"))
	end
end

return Element.define({
	Type = "ProgressBar",
	defaultName = "Progress",
	display = true,
	counts = false,

	init = function(self, config)
		local low, high = tonumber(config.Minimum) or 0, tonumber(config.Maximum) or 100
		if low > high then low, high = high, low end
		self.Minimum, self.Maximum = low, high
		self.CurrentValue = math.clamp(tonumber(config.CurrentValue) or low, low, high)
		self._color = config.Color
		self._indeterminate = config.Indeterminate == true
		self._steps = tonumber(config.Steps) and math.clamp(math.floor(config.Steps), 2, 24) or nil
		local list = {}
		for _, entry in ipairs(type(config.Thresholds) == "table" and config.Thresholds or {}) do
			if type(entry) == "table" and tonumber(entry[1] or entry.At) then
				list[#list + 1] = { tonumber(entry[1] or entry.At), entry[2] or entry.Color }
			end
		end
		table.sort(list, function(a, b) return a[1] < b[1] end)
		self._thresholds = list
	end,

	reserve = function()
		return 96
	end,

	build = function(self, view, scope)
		local padH, band = view.padH, view.band
		self._value = Factory.text(scope, "TextLabel", {
			Name = "Value", FontFace = F.Value, TextSize = TS.Value, TextColor3 = T.Text2,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -padH, 0, 0), Size = UDim2.fromOffset(96, band),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, view.Root)
		local track = Factory.new(scope, "Frame", {
			Name = "Track", BackgroundColor3 = T.Track, Position = UDim2.fromOffset(padH, band - 6),
			Size = UDim2.new(1, -padH * 2, 0, 6), BackgroundTransparency = self._steps and 1 or 0,
		}, view.Root)
		self._track = track
		local steps = self._steps
		if steps then
			self._segments = {}
			for index = 1, steps do
				local segment = Factory.new(scope, "Frame", {
					Name = "Step", Position = UDim2.new((index - 1) / steps, (index - 1) * 3 / steps, 0, 0),
					Size = UDim2.new(1 / steps, -3 * (steps - 1) / steps, 1, 0),
				}, track)
				Factory.corner(scope, segment, 3)
				self._segments[index] = segment
			end
		else
			Factory.corner(scope, track, 3)
			local fill = Factory.new(scope, "Frame", {
				Name = "Fill", BackgroundColor3 = T.White, Size = UDim2.fromScale(ratio(self), 1),
			}, track)
			Factory.corner(scope, fill, 3)
			self._gradient = Factory.new(scope, "UIGradient", { Color = Token.seq("Accent", "AccentAlt") }, fill)
			self._fill = fill
		end
		place(self)
	end,

	render = function(self, animated)
		local value = self._value
		if not value then return end
		value.Text = readout(self)
		local color = solid(self)
		local share = ratio(self)
		local segments = self._segments
		if segments then
			local filled = math.floor(share * #segments + 1e-6)
			for index, segment in ipairs(segments) do
				segment.BackgroundColor3 = index <= filled and (color or Theme.get("Accent")) or Theme.get("Track")
			end
		else
			local fill = self._fill
			fill.BackgroundColor3 = color or Theme.get("White")
			self._gradient.Enabled = color == nil
			if not self._indeterminate then
				Motion.tween(fill, "progress", { Size = UDim2.fromScale(share, 1) }, { animated = animated == true })
			end
			sweep(self)
		end
		if not animated then place(self) end
	end,

	destroy = stop,

	unmount = function(self)
		stop(self)
		self._value, self._track, self._fill, self._gradient, self._segments = nil, nil, nil, nil, nil
	end,

	methods = {
		Set = function(self, value, silent)
			value = tonumber(value)
			if value == nil or value ~= value then return self end
			value = math.clamp(value, self.Minimum, self.Maximum)
			if value == self.CurrentValue then return self end
			self.CurrentValue = value
			self:_render(self:_onScreen())
			if not silent then
				Util.xcall(self._callback, self:_context(), self, value)
				self:_fireCommit("api")
			end
			return self
		end,

		Increment = function(self, amount)
			return self:Set(self.CurrentValue + (tonumber(amount) or 1))
		end,

		-- New bounds; the value is re-clamped silently (kept when it is still in range).
		SetRange = function(self, low, high)
			low, high = tonumber(low) or self.Minimum, tonumber(high) or self.Maximum
			if low > high then low, high = high, low end
			self.Minimum, self.Maximum = low, high
			self.CurrentValue = math.clamp(self.CurrentValue, low, high)
			self:_render(false)
			return self
		end,

		-- A Color3 stays as given; a token name ("Warning") follows themes; nil restores the gradient.
		SetColor = function(self, color)
			self._color = color
			self:_render(false)
			return self
		end,

		SetIndeterminate = function(self, on)
			self._indeterminate = on == true
			if not self._indeterminate then stop(self) end
			self:_render(false)
			return self
		end,

		SetDesc = function(self, text)
			Base.SetDesc(self, text)
			place(self)
			return self
		end,
	},
})
