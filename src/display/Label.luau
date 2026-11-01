--!nocheck
-- Label: a plain text row (DESIGN_V2 6.3). Optional 16 px icon and wrapped Body text in Text2,
-- padded like a row and sized to its text. Style tints the icon (and the text for danger); a
-- Color tints both. Rayfield shape: CreateLabel(text, icon, color, ignoreTheme).

local Token = require("core/Token")
local Factory = require("core/Factory")
local Element = require("component/Element")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")

local T = Token.T
local STYLE = { muted = "Muted", info = "Info", success = "Success", warning = "Warning", danger = "Danger" }
local GLYPH = { info = "info", success = "circle-check", warning = "triangle-alert", danger = "circle-alert" }

-- Top and bottom padding: 12 at the default density, following the rows' padding.
local function pad()
	return Metrics.get("padV") + 2
end

local function style(value)
	value = value ~= nil and tostring(value):lower() or nil
	return STYLE[value] and value or nil
end

local function tint(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "string" then return Theme.get(value) end
	return nil
end

-- The note (description) sits under the wrapped text, wherever that ends.
local function placeNote(self)
	local text, note = self._text, self._note
	if not text or not note then return end
	local layers = self._window._layers
	local height = math.floor(text.AbsoluteSize.Y / (layers and layers.scale or 1) + 0.5)
	note.Position = UDim2.fromOffset(text.Position.X.Offset, pad() + height + 2)
end

local function layout(self)
	local text = self._text
	if not text or not rawget(self, "_mounted") then return end
	local view, scope = self._view, self._scope
	local glyph = self._icon or GLYPH[self._style]
	local icon = self._glyph
	if glyph and not icon then
		icon = Factory.new(scope, "ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(view.padH, pad() + 1),
		}, view.Root)
		self._glyph = icon
	end
	if icon then
		icon.Visible = glyph ~= nil
		if glyph then Icons.apply(icon, glyph) end
	end
	local x = view.padH + (glyph and 24 or 0)
	text.Position = UDim2.fromOffset(x, pad())
	text.Size = UDim2.new(1, -(x + view.padH), 0, 0)
	local noteText = self._noteText
	if noteText and not self._note then
		self._note = Factory.text(scope, "TextLabel", {
			Name = "Description", TextColor3 = T.Muted, TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y, TextYAlignment = Enum.TextYAlignment.Top,
		}, view.Root)
		scope:connect(text:GetPropertyChangedSignal("AbsoluteSize"), function() placeNote(self) end)
	end
	local note = self._note
	if note then
		note.Visible = noteText ~= nil
		note.Text = noteText or ""
		note.Size = UDim2.new(1, -(x + view.padH), 0, 0)
		placeNote(self)
	end
end

local Label = Element.define({
	Type = "Label",
	defaultName = "Label",
	display = true,
	title = false,
	counts = false,
	descriptionIsContent = true,

	fromArgs = function(config, icon, color)
		if type(config) == "table" then
			config = table.clone(config)
			config.Name = config.Text or config.Title or config.Name or config.Content
		else
			config = { Name = config }
		end
		if config.Icon == nil then config.Icon = icon end
		if config.Color == nil then config.Color = color end
		return config
	end,

	init = function(self, config)
		self.CurrentValue = self.Name
		self._icon = config.Icon ~= "" and config.Icon or nil
		self._color = config.Color
		self._style = style(config.Style)
		local note = config.Description or config.Desc
		self._noteText = note ~= nil and note ~= "" and tostring(note) or nil
	end,

	build = function(self, view, scope)
		local root = view.Root
		root.Size = UDim2.new(1, 0, 0, 0)
		root.AutomaticSize = Enum.AutomaticSize.Y
		Factory.padding(scope, root, 0, 0, 0, pad())
		self._text = Factory.text(scope, "TextLabel", {
			Name = "Text", Text = tostring(self.CurrentValue), TextColor3 = Theme.get("Text2"), TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y, TextYAlignment = Enum.TextYAlignment.Top,
		}, root)
		layout(self)
	end,

	render = function(self)
		local text = self._text
		if not text then return end
		local custom = tint(self._color)
		local status = self._style and Theme.get(STYLE[self._style])
		text.TextColor3 = (self._disabled or self._whenDisabled) and Theme.get("Disabled") or custom
			or (self._style == "danger" and status) or Theme.get("Text2")
		if self._glyph then self._glyph.ImageColor3 = custom or status or Theme.get("Text2") end
	end,

	titleChanged = function(self)
		self:Set(self.Name)
	end,

	iconChanged = function(self)
		self._icon = self._cfg.Icon ~= "" and self._cfg.Icon or nil
		layout(self)
		self:_render(false)
	end,

	unmount = function(self)
		self._text, self._glyph, self._note = nil, nil, nil
	end,

	methods = {
		-- Set(text, icon?, color?) (Rayfield), or Set{Text, Icon, Color, Style}; nil keeps a part.
		Set = function(self, text, icon, color)
			local restyle = icon ~= nil or color ~= nil
			if type(text) == "table" then
				icon = icon or text.Icon
				color = color or text.Color
				if text.Style ~= nil then self._style = style(text.Style) end
				restyle = restyle or text.Icon ~= nil or text.Color ~= nil or text.Style ~= nil
				text = text.Text or text.Title or text.Name or text.Content
			end
			text = text ~= nil and tostring(text) or ""
			self.CurrentValue = text
			self.Name = text
			self._searchIndex = nil
			if icon ~= nil then self._icon = icon ~= "" and icon or nil end
			if color ~= nil then self._color = color end
			if self._text and rawget(self, "_mounted") then
				self._text.Text = text
				if restyle then
					layout(self)
					self:_render(false)
				end
			end
			return self
		end,

		SetDesc = function(self, text)
			text = text ~= nil and tostring(text) or nil
			self._noteText = text ~= "" and text or nil
			self._searchIndex = nil
			layout(self)
			return self
		end,

		_searchOptions = function(self)
			return { self._noteText }
		end,
	},
	aliases = { SetContent = "Set", SetText = "Set" },
})

return Label
