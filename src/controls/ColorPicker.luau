--!nocheck
-- ColorPicker (DESIGN_V2 6.16): a Well trigger with a swatch and the hex. The panel is the window's
-- pooled popover ("color"): SV square, hue strip, optional alpha strip, Hex/RGB entry, 8 presets
-- and up to 6 recents shared by every picker. HSV lives in state so the hue survives a grey pick.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Color = require("theme/Color")
local Assets = require("theme/Assets")
local Router = require("input/Router")
local Drag = require("input/Drag")
local Prefs = require("persist/Prefs")
local Codec = require("persist/Codec")
local Field = require("controls/Input").Field

local T, F, TS = Token.T, Token.F, Token.TS
local W, PAD = 232, 12
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local PRESETS = { "Accent", "AccentHi", "AccentDeep", "AccentAlt", "Success", "Warning", "Danger", "Info" }
local panels = setmetatable({}, { __mode = "k" })

-- ---------- values ----------
-- Color3, "#RGB", "#RRGGBB", "#RRGGBBAA", "r, g, b", {__argonColor..}, {R,G,B} (0-255) or {Color, Alpha}.
local function parse(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "string" then
		local text = value:gsub("%s", "")
		if text:find(",") then
			local r, g, b = text:match("^%D*(%d+%.?%d*),(%d+%.?%d*),(%d+%.?%d*)%D*$")
			if not r then return nil end
			return Color3.fromRGB(math.min(tonumber(r), 255), math.min(tonumber(g), 255), math.min(tonumber(b), 255))
		end
		local hex = text:gsub("^#", "")
		if not hex:match("^%x+$") then return nil end
		if #hex == 3 or #hex == 4 then hex = hex:gsub(".", "%0%0") end
		if #hex ~= 6 and #hex ~= 8 then return nil end
		local color = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
		return color, #hex == 8 and tonumber(hex:sub(7, 8), 16) / 255 or nil
	end
	if type(value) == "table" then
		if value.Color ~= nil and value.__argonColor == nil then
			local color = parse(value.Color)
			return color, tonumber(value.Alpha or value.A)
		end
		local color, alpha = Codec.toColor(value)
		if typeof(color) == "Color3" then return color, alpha end
	end
	return nil
end

local function same(a, b)
	return typeof(a) == "Color3" and typeof(b) == "Color3" and math.abs(a.R - b.R) < 1e-5
		and math.abs(a.G - b.G) < 1e-5 and math.abs(a.B - b.B) < 1e-5
end

-- A copy-safe value record (Default, undo, paste): Util.copy keeps it intact, and A is always
-- present for Alpha pickers so an undo restores an opaque alpha too.
local function record(self, color, alpha)
	color = color or self.CurrentValue
	return { __argonColor = true, R = color.R, G = color.G, B = color.B, A = self._alphaMode and (alpha or self._alpha) or nil }
end

local function hexOf(color, alpha)
	local text = "#" .. Color.toHex(color)
	if alpha and alpha < 1 then text ..= ("%02X"):format(math.floor(alpha * 255 + 0.5)) end
	return text
end

-- HSV from the value; hue survives grey (s = 0) and black (v = 0), saturation survives black.
local function syncHSV(self)
	local h, s, v = self.CurrentValue:ToHSV()
	if v > 1e-4 then
		if s > 1e-4 then self._h = h end
		self._s = s
	end
	self._v = v
end

-- The one way a colour (and alpha) changes: an alpha change forces the commit.
local function apply(self, color, alpha, opts)
	if alpha and self._alphaMode then
		alpha = math.clamp(alpha, 0, 1)
		if math.abs(alpha - self._alpha) > 1e-4 then
			self._alpha = alpha
			opts.force = true
		end
	end
	return self:_setValue(color, opts)
end

-- Recent colours (hex strings), shared by every picker and kept in UI preferences.
local function recents()
	local list = Prefs.get("ColorRecents")
	return type(list) == "table" and list or {}
end

local function remember(color)
	local hex = "#" .. Color.toHex(color)
	local list = { hex }
	for _, entry in ipairs(recents()) do
		if #list >= 6 then break end
		if type(entry) == "string" and entry ~= hex then list[#list + 1] = entry end
	end
	Prefs.set("ColorRecents", list)
end

-- ---------- pieces ----------
local function ramp(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- The transparency backdrop: the checker asset when shipped, otherwise light diagonal stripes.
local function checker(scope, parent, props)
	if Assets.checker then
		props.Image, props.ScaleType, props.TileSize, props.BackgroundTransparency = Assets.checker, Enum.ScaleType.Tile, UDim2.fromOffset(8, 8), 1
		return Factory.new(scope, "ImageLabel", props, parent)
	end
	props.BackgroundColor3 = WHITE
	local frame = Factory.new(scope, "Frame", props, parent)
	local keys, light, dark = {}, Color3.fromRGB(236, 236, 236), Color3.fromRGB(188, 188, 188)
	for index = 0, 7 do
		local shade = index % 2 == 0 and light or dark
		keys[#keys + 1] = ColorSequenceKeypoint.new(index / 8, shade)
		keys[#keys + 1] = ColorSequenceKeypoint.new(index == 7 and 1 or (index + 1) / 8 - 0.001, shade)
	end
	Factory.new(scope, "UIGradient", { Color = ColorSequence.new(keys), Rotation = 45 }, frame)
	return frame
end

-- A 14 px thumb with a 2 px white ring; the SV thumb is hollow with a dark outer ring (T 0.6).
local function thumb(scope, parent, hollow)
	local knob = Factory.new(scope, "Frame", { Name = "Thumb", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = hollow and 1 or 0, ZIndex = 8 }, parent)
	Factory.corner(scope, knob, "full")
	Factory.new(scope, "UIStroke", { Color = WHITE, Thickness = 2 }, knob)
	if hollow then
		local outer = Factory.new(scope, "Frame", { Name = "Outer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18), ZIndex = 8 }, knob)
		Factory.corner(scope, outer, "full")
		Factory.new(scope, "UIStroke", { Color = BLACK, Transparency = 0.6, Thickness = 1 }, outer)
	end
	return knob
end

-- A 22 px hit band holding a 10 px rounded bar and a thumb.
local function strip(scope, parent, name)
	local hit = Factory.new(scope, "TextButton", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(W, 22), ZIndex = 5 }, parent)
	local bar = Factory.new(scope, "Frame", { Name = "Bar", BackgroundColor3 = WHITE, Position = UDim2.new(0, 0, 0.5, -5), Size = UDim2.new(1, 0, 0, 10), ZIndex = 5 }, hit)
	Factory.corner(scope, bar, "full")
	return hit, bar, thumb(scope, hit)
end

-- ---------- panel ----------
local function paintPanel(self)
	local p = self._panel
	if not p or p.owner ~= self then return end
	local color, h = self.CurrentValue, self._h
	p.sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
	p.svThumb.Position = UDim2.fromScale(self._s, 1 - self._v)
	p.hueThumb.Position = UDim2.new(0, 7 + h * (W - 14), 0.5, 0)
	p.hueThumb.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
	if p.alpha and self._alphaMode then
		p.alphaBar.BackgroundColor3 = color
		p.alphaThumb.Position = UDim2.new(0, 7 + self._alpha * (W - 14), 0.5, 0)
		p.alphaThumb.BackgroundColor3 = color
	end
	if not p.hexBox:IsFocused() then p.hexBox.Text = hexOf(color, self._alphaMode and self._alpha or nil) end
	for index, box in ipairs(p.rgb or {}) do
		if not box:IsFocused() then box.Text = tostring(math.floor(({ color.R, color.G, color.B })[index] * 255 + 0.5)) end
	end
	local want, match = Color.toHex(color), nil
	for index, swatchColor in ipairs(p.colors or {}) do
		if Color.toHex(swatchColor) == want then
			match = index
			break
		end
	end
	p.ring.Visible = match ~= nil
	if match then
		local position = p.swatches[match].Position
		p.ring.Position = UDim2.fromOffset(position.X.Offset + 11, position.Y.Offset + 11)
	end
end

-- Drags and arrow keys set HSV directly (the hue must not be re-derived from a grey colour).
local function slide(self, h, s, v, alpha, source)
	if h then self._h, self._s, self._v = h, s, v end
	local before, beforeAlpha = self.CurrentValue, self._alpha
	self._dragging = true
	apply(self, Color3.fromHSV(self._h, self._s, self._v), alpha, { source = source or "drag" })
	self._dragging = false
	if source == nil and (not same(self.CurrentValue, before) or self._alpha ~= beforeAlpha) then self._dragged = true end
	paintPanel(self)
end

local function begin(p, kind, input)
	local owner = p.owner
	local name = input.UserInputType and input.UserInputType.Name
	if not owner or owner:_inactive() or (name ~= "MouseButton1" and name ~= "Touch") then return end
	local target = kind == "sv" and p.sv or (kind == "hue" and p.hueBar or p.alphaBar)
	local function at(pos)
		if p.owner ~= owner or owner._destroyed then return end
		local origin, size = target.AbsolutePosition, target.AbsoluteSize
		if kind == "sv" then
			local s = math.clamp((pos.X - origin.X) / math.max(size.X, 1), 0, 1)
			slide(owner, owner._h, s, 1 - math.clamp((pos.Y - origin.Y) / math.max(size.Y, 1), 0, 1))
		else
			local t = math.clamp((pos.X - origin.X - 7) / math.max(size.X - 14, 1), 0, 1)
			if kind == "hue" then slide(owner, t, owner._s, owner._v) else slide(owner, nil, nil, nil, t) end
		end
	end
	at(Vector2.new(input.Position.X, input.Position.Y))
	Drag.begin(input, {
		onMove = at,
		onEnd = function()
			if owner._dragged then
				owner._dragged = false
				owner:_endDrag()
			end
		end,
	})
end

-- Entry commits only edited text: re-parsing the shown (rounded) value would be a fake change.
local function typedHex(p)
	local owner = p.owner
	if not owner then return end
	if p.hexBox.Text == hexOf(owner.CurrentValue, owner._alphaMode and owner._alpha or nil) then
		Field.paint(p.hexStroke, "rest")
		return
	end
	local color, alpha = parse(p.hexBox.Text)
	Field.paint(p.hexStroke, color and "rest" or "error")
	if not color or owner:_inactive() then return end
	apply(owner, color, alpha, { source = "user" })
	paintPanel(owner)
end

local function typedRGB(p)
	local owner = p.owner
	if not owner then return end
	local values, current, edited = {}, owner.CurrentValue, false
	for index, box in ipairs(p.rgb) do
		local n = tonumber(box.Text)
		if not n then
			Field.paint(p.rgbStroke, "error")
			return
		end
		values[index] = math.clamp(math.floor(n + 0.5), 0, 255)
		edited = edited or values[index] ~= math.floor(({ current.R, current.G, current.B })[index] * 255 + 0.5)
	end
	Field.paint(p.rgbStroke, "rest")
	if not edited or owner:_inactive() then return end
	apply(owner, Color3.fromRGB(values[1], values[2], values[3]), nil, { source = "user" })
	paintPanel(owner)
end

-- The Hex / RGB tabs and the entry field for the current tab.
local function entry(p)
	local y = p.entryY
	for index, mode in ipairs({ "hex", "rgb" }) do
		local tab, on = p.tabs[mode], p.mode == mode
		tab.Position = UDim2.fromOffset(PAD + (index - 1) * 46, y)
		tab.BackgroundTransparency = on and 0 or 1
		tab.TextColor3 = Theme.get(on and "AccentText" or "Text2")
	end
	if p.mode == "rgb" and not p.rgbWell then
		local scope = p.scope
		p.rgbWell, p.rgbStroke = Field.well(scope, p.frame, "Frame", { Name = "RGBField", Size = UDim2.fromOffset(W - 96, 28), ZIndex = 5 }, 8)
		p.rgb = {}
		for index, key in ipairs({ "R", "G", "B" }) do
			local box = Field.box(scope, p.rgbWell, { Name = key, PlaceholderText = key, FontFace = F.Value, TextSize = TS.Value,
				TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromScale((index - 1) / 3, 0), Size = UDim2.fromScale(1 / 3, 1), ZIndex = 6 })
			scope:connect(box.FocusLost, function() typedRGB(p) end)
			p.rgb[index] = box
		end
	end
	p.hexWell.Position = UDim2.fromOffset(PAD + 96, y)
	p.hexWell.Visible = p.mode == "hex"
	if p.rgbWell then
		p.rgbWell.Position = UDim2.fromOffset(PAD + 96, y)
		p.rgbWell.Visible = p.mode == "rgb"
	end
	if p.owner then paintPanel(p.owner) end
end

local function buildPanel(frame, scope)
	local p = { frame = frame, scope = scope, mode = "hex", swatches = {} }
	local sv = Factory.new(scope, "TextButton", { Name = "SV", Position = UDim2.fromOffset(PAD, PAD), Size = UDim2.fromOffset(W, 140), ZIndex = 5 }, frame)
	Factory.corner(scope, sv, Metrics.radius.control)
	local white = Factory.new(scope, "Frame", { Name = "White", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, sv)
	Factory.corner(scope, white, Metrics.radius.control)
	Factory.new(scope, "UIGradient", { Rotation = 0, Transparency = ramp(0, 1) }, white)
	local black = Factory.new(scope, "Frame", { Name = "Black", BackgroundColor3 = BLACK, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, sv)
	Factory.corner(scope, black, Metrics.radius.control)
	Factory.new(scope, "UIGradient", { Rotation = 90, Transparency = ramp(1, 0) }, black)
	p.sv, p.svThumb = sv, thumb(scope, sv, true)
	p.hue, p.hueBar, p.hueThumb = strip(scope, frame, "Hue")
	p.hue.Position = UDim2.fromOffset(PAD, PAD + 144)
	local keys = {}
	for index = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(index / 6, Color3.fromHSV((index % 6) / 6, 1, 1)) end
	Factory.new(scope, "UIGradient", { Color = ColorSequence.new(keys) }, p.hueBar)
	p.tabs = {}
	for _, mode in ipairs({ "hex", "rgb" }) do
		local tab = Factory.text(scope, "TextButton", { Name = mode == "hex" and "Hex" or "RGB", Text = mode == "hex" and "Hex" or "RGB", FontFace = F.Button,
			TextSize = TS.Caption, TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = T.AccentSoft, Size = UDim2.fromOffset(44, 28), ZIndex = 5 }, frame)
		Factory.corner(scope, tab, Metrics.radius.segment)
		scope:connect(tab.MouseButton1Click, function()
			p.mode = mode
			entry(p)
		end)
		p.tabs[mode] = tab
	end
	p.hexWell, p.hexStroke = Field.well(scope, frame, "Frame", { Name = "HexField", Size = UDim2.fromOffset(W - 96, 28), ZIndex = 5 }, 8)
	p.hexBox = Field.box(scope, p.hexWell, { Name = "Hex", FontFace = F.Value, TextSize = TS.Value, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 6 })
	p.ring = Factory.new(scope, "Frame", { Name = "Ring", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28), Visible = false, ZIndex = 7 }, frame)
	Factory.corner(scope, p.ring, Metrics.radius.swatch + 3)
	Factory.stroke(scope, p.ring, T.Focus, 0, 2)
	scope:connect(sv.InputBegan, function(input) begin(p, "sv", input) end)
	scope:connect(p.hue.InputBegan, function(input) begin(p, "hue", input) end)
	scope:connect(p.hexBox.Focused, function() Field.paint(p.hexStroke, "focus") end)
	scope:connect(p.hexBox.FocusLost, function() typedHex(p) end)
	panels[frame] = p
	return Vector2.new(256, 300)
end

local function swatch(p, index)
	local button = p.swatches[index]
	if button then return button end
	button = Factory.new(p.scope, "TextButton", { Name = "Swatch", Size = UDim2.fromOffset(22, 22), ZIndex = 6 }, p.frame)
	Factory.corner(p.scope, button, Metrics.radius.swatch)
	p.scope:connect(button.MouseButton1Click, function()
		local owner, color = p.owner, p.colors and p.colors[index]
		if not owner or not color or owner:_inactive() then return end
		apply(owner, color, nil, { source = "user" })
		paintPanel(owner)
	end)
	p.swatches[index] = button
	return button
end

local function bindPanel(p, self)
	p.owner = self
	local scope = p.scope
	if self._alphaMode and not p.alpha then
		p.alpha, p.alphaBar, p.alphaThumb = strip(scope, p.frame, "Alpha")
		local back = checker(scope, p.alpha, { Name = "Checker", Position = p.alphaBar.Position, Size = p.alphaBar.Size, ZIndex = 4 })
		Factory.corner(scope, back, "full")
		Factory.new(scope, "UIGradient", { Transparency = ramp(1, 0) }, p.alphaBar)
		scope:connect(p.alpha.InputBegan, function(input) begin(p, "alpha", input) end)
	end
	local y = PAD + 144 + 26
	if p.alpha then
		p.alpha.Visible = self._alphaMode
		p.alpha.Position = UDim2.fromOffset(PAD, y)
		if self._alphaMode then y += 26 end
	end
	p.entryY = y + 2
	y += 40
	local colors, presets = {}, self._cfg.Presets
	for index, token in ipairs(PRESETS) do
		colors[index] = (type(presets) == "table" and parse(presets[index])) or Theme.get(token)
	end
	for _, hex in ipairs(recents()) do
		local color = type(hex) == "string" and parse(hex)
		if color and #colors < #PRESETS + 6 then colors[#colors + 1] = color end
	end
	p.colors = colors
	for index, color in ipairs(colors) do
		local button = swatch(p, index)
		button.Visible = true
		button.BackgroundColor3 = color
		button.Position = UDim2.fromOffset(PAD + ((index - 1) % 8) * 30, y + (index > 8 and 30 or 0))
	end
	for index = #colors + 1, #p.swatches do p.swatches[index].Visible = false end
	y += (#colors > 8 and 60 or 30) + 6
	p.mode = "hex"
	Field.paint(p.hexStroke, "rest")
	if p.rgbStroke then Field.paint(p.rgbStroke, "rest") end
	entry(p)
	return Vector2.new(256, y)
end

-- ---------- open and close ----------
local function key(self, input)
	local name = input.KeyCode and input.KeyCode.Name or ""
	local step = (Router.isDown(Enum.KeyCode.LeftShift) or Router.isDown(Enum.KeyCode.RightShift)) and 0.1 or 0.01
	local h, s, v = self._h, self._s, self._v
	if name == "Left" or name == "DPadLeft" then s -= step
	elseif name == "Right" or name == "DPadRight" then s += step
	elseif name == "Up" or name == "DPadUp" then v += step
	elseif name == "Down" or name == "DPadDown" then v -= step
	elseif name == "ButtonL1" then h = (h - step) % 1
	elseif name == "ButtonR1" then h = (h + step) % 1
	else return false end
	if not self:_inactive() then slide(self, h, math.clamp(s, 0, 1), math.clamp(v, 0, 1), nil, "user") end
	return true
end

local function closed(self)
	if self._key then
		self._key.remove()
		self._key = nil
	end
	local p = self._panel
	if p and p.owner == self then
		if p.hexBox:IsFocused() then p.hexBox:ReleaseFocus() end
		for _, box in ipairs(p.rgb or {}) do
			if box:IsFocused() then box:ReleaseFocus() end
		end
		p.owner = nil
	end
	self._panel = nil
	if self._openedWith and (not same(self._openedWith, self.CurrentValue) or self._openedAlpha ~= self._alpha) then
		remember(self.CurrentValue)
	end
	self._openedWith = nil
end

local function toggle(self)
	local window = self._window
	local host = window and window._popover
	if not host or not self._field or self:_inactive() then return end
	if host:isOpen(self) then
		host:close("toggle")
		return
	end
	self._openedWith, self._openedAlpha = self.CurrentValue, self._alpha
	host:open({
		owner = self, anchor = self._field, reuse = "color", name = "ColorPicker", width = 256, maxHeight = 420, sheetOnPhone = true,
		build = buildPanel,
		bind = function(frame)
			local p = panels[frame]
			self._panel = p
			return bindPanel(p, self)
		end,
		onClose = function() closed(self) end,
	})
	self._key = Router.layerKey(function(input) return key(self, input) end, 90)
end

local ColorPicker = Element.define({
	Type = "ColorPicker",
	defaultName = "Color picker",
	flaggable = true,

	init = function(self, config)
		self._alphaMode = config.Alpha == true
		local raw = config.Color
		if raw == nil then raw = config.CurrentValue end
		local color, alpha = parse(raw)
		color = color or Theme.get("Accent")
		local transparency = tonumber(config.Transparency)
		self._alpha = self._alphaMode and math.clamp(alpha or (transparency and 1 - transparency) or 1, 0, 1) or 1
		self.CurrentValue, self.Color, self.Alpha = color, color, self._alpha
		self._h, self._s, self._v = color:ToHSV()
		self.Default = record(self, color)
	end,

	reserve = function(self)
		return self._alphaMode and 160 or 124
	end,

	build = function(self, view, scope)
		local h = Metrics.get("control")
		local field = Factory.text(scope, "TextLabel", { Name = "Field", BackgroundColor3 = T.Well, BackgroundTransparency = 0, FontFace = F.Value,
			TextSize = TS.Value, RichText = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 }, view.Root)
		RowView.control(view, field, view.reserve, h)
		Factory.corner(scope, field, Field.radius(h))
		local swatch = Factory.new(scope, "Frame", { Name = "Swatch", Position = UDim2.new(0, 6, 0.5, -10), Size = UDim2.fromOffset(20, 20), ZIndex = 4 }, field)
		Factory.corner(scope, swatch, Metrics.radius.swatch)
		self._field, self._swatch = field, swatch
		scope:connect(view.Root.MouseButton1Click, function() toggle(self) end)
	end,

	render = function(self)
		local field = self._field
		if not field then return end
		local inactive = self:_inactive()
		local color, alpha = self.CurrentValue, self._alpha
		self._swatch.BackgroundColor3 = color
		self._swatch.BackgroundTransparency = inactive and 0.5 or 1 - alpha
		if alpha < 1 and not self._check then
			self._check = checker(self._scope, field, { Name = "Checker", Position = self._swatch.Position, Size = UDim2.fromOffset(20, 20), ZIndex = 3 })
			Factory.corner(self._scope, self._check, Metrics.radius.swatch)
		end
		if self._check then self._check.Visible = alpha < 1 end
		local text = "#" .. Color.toHex(color)
		if self._alphaMode then
			text ..= ('  <font color="#%s">%d%%</font>'):format(Color.toHex(Theme.get(inactive and "Disabled" or "Text2")), math.floor(alpha * 100 + 0.5))
		end
		field.Text = text
		field.TextColor3 = Theme.get(inactive and "Disabled" or "Text")
		paintPanel(self)
	end,

	normalize = function(_, raw)
		return (parse(raw))
	end,

	equals = function(a, b)
		return same(a, b)
	end,

	mirror = function(self)
		self.Color, self.Alpha = self.CurrentValue, self._alpha
		if not self._dragging then syncHSV(self) end
	end,

	payload = function(self)
		if self._alphaMode then return self.CurrentValue, self._alpha end
		return self.CurrentValue
	end,

	encodeValue = function(self, value)
		local color, alpha = parse(value)
		if not color then return value end
		if typeof(value) == "Color3" then alpha = self._alpha end
		local function round(x) return math.floor(x * 1000 + 0.5) / 1000 end
		return { round(color.R), round(color.G), round(color.B), self._alphaMode and round(alpha or 1) or nil }
	end,

	describe = function(self, value)
		local color, alpha = parse(value)
		if not color then return "custom" end
		return hexOf(color, self._alphaMode and alpha or nil)
	end,

	focus = {
		activate = function(self) toggle(self) end,
	},

	unmount = function(self)
		local host = self._window and self._window._popover
		if host and host:isOpen(self) then host:close("unmount") end
		self._field, self._swatch, self._check = nil, nil, nil
	end,

	methods = {
		Set = function(self, value, silent)
			local color, alpha = parse(value)
			if not color then return self end
			return apply(self, color, alpha, { silent = silent == true, source = "api" })
		end,
		SetAlpha = function(self, alpha, silent)
			return apply(self, self.CurrentValue, tonumber(alpha), { silent = silent == true, source = "api" })
		end,
		GetHex = function(self)
			return hexOf(self.CurrentValue, self._alphaMode and self._alpha or nil)
		end,
		GetDefault = function(self)
			local color, alpha = parse(self.Default)
			if self._alphaMode then return color, alpha or 1 end
			return color
		end,
		_encode = function(self)
			return Codec.fromColor(self.CurrentValue, self._alphaMode and self._alpha or nil)
		end,
		_rawValue = function(self)
			return record(self)
		end,
		_copyText = function(self)
			return hexOf(self.CurrentValue, self._alphaMode and self._alpha or nil)
		end,
	},
})

return ColorPicker
