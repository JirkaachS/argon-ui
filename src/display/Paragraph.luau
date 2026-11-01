--!nocheck
-- Paragraph: a title over wrapped body copy (DESIGN_V2 6.4), padded like rows and sized to its
-- text. Description stays an alias for the content (v1, D15); the icon is optional (D4: Set
-- takes a string or {Title, Content}). _place is shared with TelemetryCard.

local Factory = require("core/Factory")
local Element = require("component/Element")
local RowView = require("component/RowView")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")

local function str(value)
	return value ~= nil and tostring(value) or ""
end

local Paragraph
Paragraph = Element.define({
	Type = "Paragraph",
	defaultName = "Information",
	display = true,
	counts = false,
	descriptionIsContent = true,

	fromArgs = function(config)
		if type(config) ~= "table" then return { Content = config } end
		return config
	end,

	init = function(self, config)
		self.Name = tostring(config.Title or config.Name or "Information")
		local content = config.Content
		if content == nil then content = config.Description end
		self.CurrentValue = str(content)
		self._iconName = config.Icon ~= "" and config.Icon or nil
	end,

	build = function(self, view, scope)
		Paragraph._frame(self, view, scope)
		Paragraph._place(self)
	end,

	render = function(self)
		local body = self._body
		if not body then return end
		body.TextColor3 = Theme.get((self._disabled or self._whenDisabled) and "Disabled" or "Text2")
		if self._glyph then self._glyph.ImageColor3 = Theme.get("Text2") end
	end,

	iconChanged = function(self)
		self._iconName = self._cfg.Icon ~= "" and self._cfg.Icon or nil
		if self._body then
			Paragraph._place(self)
			self:_render(false)
		end
	end,

	unmount = function(self)
		self._body, self._glyph = nil, nil
	end,

	methods = {
		Set = function(self, value)
			if type(value) == "table" then
				local title = value.Title or value.Name
				if title ~= nil then self:SetTitle(title) end
				local content = value.Content
				if content == nil then content = value.Description or value.Text end
				if content == nil then return self end
				value = content
			end
			self.CurrentValue = str(value)
			self._searchIndex = nil
			if self._body and rawget(self, "_mounted") then self._body.Text = self.CurrentValue end
			return self
		end,

		_searchOptions = function(self)
			return { self.CurrentValue }
		end,
	},
	aliases = { SetContent = "Set", SetDesc = "Set" },
})

-- The auto-sized frame: root grows with the body, bottom padding mirrors the title's top.
function Paragraph._frame(self, view, scope)
	local root = view.Root
	root.Size = UDim2.new(1, 0, 0, view.band)
	root.AutomaticSize = Enum.AutomaticSize.Y
	Factory.padding(scope, root, 0, 0, 0, math.floor((view.band - 20) / 2))
	self._body = Factory.text(scope, "TextLabel", {
		Name = "Body", Text = str(self.CurrentValue), TextColor3 = Theme.get("Text2"), TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, TextYAlignment = Enum.TextYAlignment.Top,
	}, root)
end

-- Icon 16 + title on the band, body under it; `right` keeps the title clear of a pill.
function Paragraph._place(self, right)
	local view = self._view
	if not view or not rawget(self, "_mounted") then return end
	local padH = Metrics.get("padH")
	local name = self._iconName
	local icon = self._glyph
	if name and not icon then
		icon = Factory.new(self._scope, "ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(padH, RowView.bandY(view, 16)), ImageColor3 = Theme.get("Text2"),
		}, view.Root)
		self._glyph = icon
	end
	if icon then
		icon.Visible = name ~= nil
		if name then Icons.apply(icon, name) end
	end
	local x = padH + (name and 24 or 0)
	view.padH = x
	view.Title.Position = UDim2.fromOffset(x, 0)
	view.Title.Size = UDim2.new(1, -(RowView.titleInset(view) + (right or 0)), 0, view.band)
	self._body.Position = UDim2.fromOffset(x, view.band - 8)
	self._body.Size = UDim2.new(1, -(x + padH), 0, 0)
	RowView.layoutMarkers(self)
end

return Paragraph
