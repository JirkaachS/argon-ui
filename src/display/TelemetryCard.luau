--!nocheck
-- TelemetryCard (DESIGN_V2 6.18). The card: icon + title on the band, a status pill at the
-- right, wrapped content under it, and a rail at the left edge while a status shows. The stat
-- tile (Variant "stat", or CreateStat): label + icon, a mono value with its unit, then a delta
-- pill, the status pill and spark bars. Status, Icon and Rail are view fields (v1).

local Token = require("core/Token")
local Factory = require("core/Factory")
local Env = require("core/Env")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local Paragraph = require("display/Paragraph")

local T, F, TS = Token.T, Token.F, Token.TS
local META_Y, SPARK_H = 74, 22

local function color(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "string" then return Theme.get(value) end
	return nil
end

local function str(value)
	return value ~= nil and tostring(value) or ""
end

local function shown(text)
	return text ~= nil and text ~= ""
end

local function monoWidth(text, size)
	local ok, bounds = pcall(function()
		return Env.services.TextService:GetTextSize(text, size, Env.enum("Font", "RobotoMono", "Code"), Vector2.new(2000, 100))
	end)
	return ok and bounds and math.ceil(bounds.X) or math.ceil(#text * size * 0.6)
end

local function isDown(delta)
	if type(delta) == "number" then return delta < 0 end
	local text = str(delta)
	return text:find("^%s*%-") ~= nil or text:find("^%s*\226\136\146") ~= nil
end

-- A pill with an outline: the v1 Status field (TextLabel, AutomaticSize X, UIStroke child).
local function pill(self, scope, parent)
	local status = Factory.text(scope, "TextLabel", {
		Name = "Status", FontFace = F.Caption, TextSize = TS.Caption, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20), TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
	}, parent)
	Factory.corner(scope, status, "full")
	Factory.padding(scope, status, 8, 8, 0, 0)
	self._outline = Factory.new(scope, "UIStroke", {
		Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, status)
	self.Status = status
end

-- ---------- the stat tile ----------
local function layoutStat(self)
	local view = self._view
	local root, scope, padH = view.Root, self._scope, Metrics.get("padH")
	local value = str(self.CurrentValue)
	self._value.Text = value
	local unit = self._unit
	if shown(unit) and not self._unitLabel then
		self._unitLabel = Factory.text(scope, "TextLabel", {
			Name = "Unit", TextColor3 = T.Muted, TextYAlignment = Enum.TextYAlignment.Bottom, Size = UDim2.fromOffset(120, 28),
		}, root)
	end
	if self._unitLabel then
		self._unitLabel.Visible = shown(unit)
		self._unitLabel.Text = str(unit)
		self._unitLabel.Position = UDim2.fromOffset(padH + monoWidth(value, Metrics.textSize("Stat")) + 4, 36)
	end
	local x, delta = padH, self._delta
	if shown(delta) and not self._deltaPill then
		local chip = Factory.text(scope, "TextLabel", {
			Name = "Delta", FontFace = F.Key, TextSize = TS.Key, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20), BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
		}, root)
		Factory.corner(scope, chip, "full")
		Factory.padding(scope, chip, 22, 8, 0, 0)
		self._deltaIcon = Factory.new(scope, "ImageLabel", {
			Name = "Trend", BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, -16, 0.5, -6),
		}, chip)
		self._deltaPill = chip
	end
	if self._deltaPill then
		local text = type(delta) == "number" and ("%+g"):format(delta) or str(delta)
		self._deltaPill.Visible = shown(delta)
		self._deltaPill.Text = text
		self._deltaPill.Position = UDim2.fromOffset(x, META_Y + 1)
		if shown(delta) then x += monoWidth(text, 12) + 36 end
	end
	self.Status.Position = UDim2.fromOffset(x, META_Y + 1)
	local spark = self._spark or {}
	local count = math.min(#spark, 12)
	local bars = self._bars
	local low, high = 0, 0
	for index = #spark - count + 1, #spark do
		local v = tonumber(spark[index]) or 0
		low, high = math.min(low, v), math.max(high, v)
	end
	for index = 1, math.max(count, #bars) do
		local bar = bars[index]
		if index <= count then
			if not bar then
				bar = Factory.new(scope, "Frame", { Name = "Spark" }, root)
				bars[index] = bar
			end
			local v = tonumber(spark[#spark - count + index]) or 0
			local h = high > low and math.max(2, math.floor((v - low) / (high - low) * SPARK_H + 0.5)) or 2
			bar.Visible = true
			bar.Size = UDim2.fromOffset(3, h)
			bar.Position = UDim2.new(1, -(padH + (count - index) * 5 + 3), 0, META_Y + SPARK_H - h)
		elseif bar then
			bar.Visible = false
		end
	end
	self._sparkCount = count
	local meta = shown(delta) or shown(self._status) or count > 0
	root.Size = UDim2.new(1, 0, 0, meta and 110 or 82)
end

local function renderStat(self, disabled)
	self._view.Title.TextColor3 = Theme.get(disabled and "Disabled" or "Text2")
	self._value.TextColor3 = Theme.get(disabled and "Disabled" or "Text")
	if self._deltaPill then
		local tone = isDown(self._delta) and "Danger" or "Success"
		self._deltaPill.BackgroundColor3 = Theme.get(tone .. "Soft")
		self._deltaPill.TextColor3 = Theme.get(tone)
		Icons.apply(self._deltaIcon, tone == "Danger" and "trending-down" or "trending-up")
		self._deltaIcon.ImageColor3 = Theme.get(tone)
	end
	for index, bar in ipairs(self._bars) do
		bar.BackgroundColor3 = Theme.get(index == self._sparkCount and "Accent" or "Track")
	end
end

-- ---------- shared ----------
local function layout(self)
	if self._stat then return layoutStat(self) end
	local text = self._status
	Paragraph._place(self, shown(text) and RowView.textWidth(text, 12) + 24 or 0)
	self.Icon = self._glyph
end

local function paintStatus(self)
	local status = rawget(self, "Status")
	if not status then return end
	local text = self._status
	local tone = color(self._statusColor) or color(self._accent) or Theme.get("Accent")
	status.Visible = shown(text)
	status.Text = str(text)
	status.TextColor3 = tone
	self._outline.Color = tone
	local rail = rawget(self, "Rail")
	if rail then
		rail.Visible = shown(text)
		rail.BackgroundColor3 = tone
	end
end

return Element.define({
	Type = "TelemetryCard",
	defaultName = "Telemetry",
	display = true,
	counts = false,
	descriptionIsContent = true,
	viewFields = { "Status", "Icon", "Rail" },

	fromArgs = function(config)
		if type(config) ~= "table" then return { Title = config } end
		return config
	end,

	init = function(self, config)
		local stat = type(config.Variant) == "string" and config.Variant:lower() == "stat"
		self._stat = stat
		if stat then
			self.Name = tostring(config.Label or config.Name or config.Title or "Stat")
			self.CurrentValue = config.Value ~= nil and config.Value or ""
			self._unit = config.Unit
			self._delta = config.Delta
			self._spark = type(config.Spark) == "table" and table.clone(config.Spark) or nil
			self._iconName = config.Icon ~= "" and config.Icon or nil
		else
			self.Name = tostring(config.Title or config.Name or "Telemetry")
			local content = config.Content
			if content == nil then content = config.Description end
			self.CurrentValue = content ~= nil and tostring(content) or "Waiting for data..."
			if config.Icon == nil then
				self._iconName = "activity"
			elseif config.Icon ~= false and config.Icon ~= "" then
				self._iconName = config.Icon
			end
		end
		self._status = config.Status ~= nil and tostring(config.Status) or nil
		self._statusColor = config.StatusColor
		self._accent = config.Accent
	end,

	build = function(self, view, scope)
		if not self._stat then
			Paragraph._frame(self, view, scope)
			self.Rail = Factory.new(scope, "Frame", {
				Name = "Rail", Position = UDim2.fromOffset(6, RowView.bandY(view, 16)), Size = UDim2.fromOffset(2, 16), Visible = false,
			}, view.Root)
			pill(self, scope, view.Root)
			self.Status.AnchorPoint = Vector2.new(1, 0)
			self.Status.Position = UDim2.new(1, -Metrics.get("padH"), 0, RowView.bandY(view, 20))
			return layout(self)
		end
		local root, title, padH = view.Root, view.Title, Metrics.get("padH")
		scope:unpaint(title)
		Factory.apply(scope, title, { FontFace = F.Caption, TextSize = TS.Caption })
		if self._iconName then
			self._glyph = Factory.new(scope, "ImageLabel", {
				Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(padH, 15),
			}, root)
			Icons.apply(self._glyph, self._iconName)
			self.Icon = self._glyph
		end
		local x = padH + (self._glyph and 20 or 0)
		view.padH = x
		title.Position = UDim2.fromOffset(x, 14)
		title.Size = UDim2.new(1, -(x + padH), 0, 16)
		self._value = Factory.text(scope, "TextLabel", {
			Name = "Value", FontFace = F.Stat, TextSize = TS.Stat, Position = UDim2.fromOffset(padH, 36),
			Size = UDim2.new(1, -padH * 2, 0, 32), TextTruncate = Enum.TextTruncate.AtEnd,
		}, root)
		self._bars = {}
		pill(self, scope, root)
		layout(self)
	end,

	render = function(self)
		if not self._view then return end
		local disabled = self._disabled or self._whenDisabled
		if self._stat then
			renderStat(self, disabled)
		else
			self._body.TextColor3 = Theme.get(disabled and "Disabled" or "Text2")
		end
		if self._glyph then self._glyph.ImageColor3 = color(self._accent) or Theme.get("Text2") end
		paintStatus(self)
	end,

	iconChanged = function(self)
		local icon = self._cfg.Icon
		self._iconName = icon ~= "" and icon ~= false and icon or nil
		if rawget(self, "_mounted") and not self._stat then
			layout(self)
			self:_render(false)
		end
	end,

	unmount = function(self)
		self.Status, self.Icon, self.Rail = nil, nil, nil
		self._body, self._glyph, self._value, self._unitLabel, self._deltaPill, self._deltaIcon, self._bars = nil, nil, nil, nil, nil, nil, nil
	end,

	methods = {
		-- The card's content, or the stat's value.
		Set = function(self, value)
			if self._stat then return self:SetValue(value) end
			self.CurrentValue = str(value)
			self._searchIndex = nil
			if rawget(self, "_mounted") and self._body then self._body.Text = self.CurrentValue end
			return self
		end,

		SetDesc = function(self, value)
			if self._stat then return self end
			return self:Set(value)
		end,

		-- SetStatus(text, Color3 | token name): kept across themes; a token follows them.
		SetStatus = function(self, text, tone)
			self._status = text ~= nil and tostring(text) or nil
			if tone ~= nil then self._statusColor = tone end
			if rawget(self, "_mounted") and self._view then
				layout(self)
				paintStatus(self)
			end
			return self
		end,

		SetValue = function(self, value, unit)
			if not self._stat then return self:Set(value) end
			self.CurrentValue = value ~= nil and value or ""
			if unit ~= nil then self._unit = unit end
			self._searchIndex = nil
			if rawget(self, "_mounted") and self._value then layoutStat(self) end
			return self
		end,

		SetDelta = function(self, delta)
			self._delta = delta
			if rawget(self, "_mounted") and self._value then
				layoutStat(self)
				self:_render(false)
			end
			return self
		end,

		SetSpark = function(self, values)
			self._spark = type(values) == "table" and table.clone(values) or nil
			if rawget(self, "_mounted") and self._value then
				layoutStat(self)
				self:_render(false)
			end
			return self
		end,

		-- Appends one sample to the spark (the last 12 are kept).
		Push = function(self, sample)
			local spark = self._spark or {}
			spark[#spark + 1] = tonumber(sample) or 0
			while #spark > 12 do table.remove(spark, 1) end
			return self:SetSpark(spark)
		end,

		_searchOptions = function(self)
			return { str(self.CurrentValue) }
		end,
	},
	aliases = { SetContent = "Set" },
})
