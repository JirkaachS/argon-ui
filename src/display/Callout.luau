--!nocheck
-- Callout (DESIGN_V2 6.5): a box inset 8 inside the platter, r 10, tinted <Type>Soft. Icon 18
-- in the status colour, Title 14 Medium, wrapped Body 13 Text2, an optional AccentText action
-- under the body and an optional dismiss x. The box and the row both size to the text.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Util = require("core/Util")
local Element = require("component/Element")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")

local T, F, TS = Token.T, Token.F, Token.TS
local KINDS = { info = "Info", success = "Success", warning = "Warning", danger = "Danger", error = "Danger" }
local GLYPH = { Info = "info", Success = "circle-check", Warning = "triangle-alert", Danger = "circle-alert" }
local X = 42 -- text column inside the box: padding 14 + icon 18 + gap 10

local function kind(value)
	return KINDS[tostring(value or "info"):lower()] or "Info"
end

local function str(value)
	return value ~= nil and tostring(value) or ""
end

-- The action sits under the body, wherever the wrapped body ends.
local function placeAction(self)
	local action, body = self._action, self._body
	if not action or not body then return end
	local layers = self._window._layers
	local height = math.floor(body.AbsoluteSize.Y / (layers and layers.scale or 1) + 0.5)
	action.Position = UDim2.fromOffset(X, body.Position.Y.Offset + height + 6)
end

local function layout(self)
	local body, box = self._body, self._box
	if not body or not rawget(self, "_mounted") then return end
	local scope, head = self._scope, self._head
	if head and not self._headLabel then
		self._headLabel = Factory.text(scope, "TextLabel", {
			Name = "Title", FontFace = F.Label, TextSize = TS.Label, TextColor3 = T.Text,
			TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(X, 12),
		}, box)
	end
	local right = self._dismissible and 36 or 12
	if self._headLabel then
		self._headLabel.Visible = head ~= nil
		self._headLabel.Text = str(head)
		self._headLabel.Size = UDim2.new(1, -(X + right), 0, 20)
	end
	body.Position = UDim2.fromOffset(X, head and 34 or 12)
	body.Size = UDim2.new(1, -(X + right), 0, 0)
	local action = self._actionSpec
	if type(action) == "table" and not self._action then
		self._action = Factory.text(scope, "TextButton", {
			Name = "Action", FontFace = F.Button, TextSize = TS.Caption, TextColor3 = T.AccentText,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20),
		}, box)
		scope:connect(self._action.MouseButton1Click, function()
			local spec = self._actionSpec
			if type(spec) == "table" and not self:_inactive() then
				Util.xcall(spec.Callback, self:_context() .. " Action", self)
			end
		end)
		scope:connect(body:GetPropertyChangedSignal("AbsoluteSize"), function() placeAction(self) end)
	end
	if self._action then
		self._action.Visible = type(action) == "table"
		self._action.Text = type(action) == "table" and str(action.Text or action.Title or action.Name) or ""
		placeAction(self)
	end
end

local Callout = Element.define({
	Type = "Callout",
	defaultName = "Callout",
	display = true,
	title = false,
	counts = false,
	descriptionIsContent = true,

	fromArgs = function(config)
		if type(config) ~= "table" then return { Content = config } end
		return config
	end,

	init = function(self, config)
		self._head = config.Title ~= nil and tostring(config.Title) or nil
		self.Name = self._head or tostring(config.Name or "Callout")
		local content = config.Content
		if content == nil then content = config.Description or config.Text end
		self.CurrentValue = str(content)
		self._kind = kind(config.Type)
		self._iconName = config.Icon ~= "" and config.Icon or nil
		self._actionSpec = config.Action
		self._dismissible = config.Dismissible == true or type(config.Dismissible) == "function"
	end,

	build = function(self, view, scope)
		local root = view.Root
		root.Size = UDim2.new(1, 0, 0, 0)
		root.AutomaticSize = Enum.AutomaticSize.Y
		Factory.padding(scope, root, 0, 0, 0, 8)
		local box = Factory.new(scope, "Frame", {
			Name = "Box", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		}, root)
		Factory.corner(scope, box, 10)
		Factory.padding(scope, box, 0, 0, 0, 12)
		self._box = box
		self._glyph = Factory.new(scope, "ImageLabel", {
			Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(14, 13),
		}, box)
		self._body = Factory.text(scope, "TextLabel", {
			Name = "Body", TextColor3 = T.Text2, TextWrapped = true, Text = str(self.CurrentValue),
			AutomaticSize = Enum.AutomaticSize.Y, TextYAlignment = Enum.TextYAlignment.Top,
		}, box)
		if self._dismissible then
			local close = Factory.new(scope, "ImageButton", {
				Name = "Dismiss", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 14), Size = UDim2.fromOffset(16, 16),
			}, box)
			Icons.apply(close, "x", scope, T.Text2)
			scope:connect(close.MouseButton1Click, function()
				if not self:_inactive() then self:Dismiss() end
			end)
		end
		layout(self)
	end,

	render = function(self)
		local box = self._box
		if not box then return end
		local disabled = self._disabled or self._whenDisabled
		box.BackgroundColor3 = Theme.get(self._kind .. "Soft")
		Icons.apply(self._glyph, self._iconName or GLYPH[self._kind])
		self._glyph.ImageColor3 = Theme.get(disabled and "Disabled" or self._kind)
		self._body.TextColor3 = Theme.get(disabled and "Disabled" or "Text2")
	end,

	iconChanged = function(self)
		self._iconName = self._cfg.Icon ~= "" and self._cfg.Icon or nil
		self:_render(false)
	end,

	titleChanged = function(self)
		self._head = self.Name
		layout(self)
	end,

	unmount = function(self)
		self._box, self._glyph, self._body, self._headLabel, self._action = nil, nil, nil, nil, nil
	end,

	methods = {
		-- Set(text) or Set{Title, Content, Type, Icon, Action}.
		Set = function(self, value)
			if type(value) == "table" then
				if value.Title ~= nil then
					self._head = tostring(value.Title)
					self.Name = self._head
				end
				if value.Type ~= nil then self._kind = kind(value.Type) end
				if value.Icon ~= nil then self._iconName = value.Icon ~= "" and value.Icon or nil end
				if value.Action ~= nil then self._actionSpec = value.Action end
				value = value.Content or value.Description or value.Text
			end
			if value ~= nil then self.CurrentValue = str(value) end
			self._searchIndex = nil
			if self._body and rawget(self, "_mounted") then
				self._body.Text = self.CurrentValue
				layout(self)
				self:_render(false)
			end
			return self
		end,

		-- Hides the callout and fires OnDismiss (or Dismissible when it is a function).
		Dismiss = function(self)
			self:SetVisible(false)
			local cfg = self._cfg
			Util.xcall(type(cfg.Dismissible) == "function" and cfg.Dismissible or cfg.OnDismiss, self:_context() .. " OnDismiss", self)
			return self
		end,

		_searchOptions = function(self)
			return { str(self._head), str(self.CurrentValue) }
		end,
	},
	aliases = { SetContent = "Set", SetDesc = "Set" },
})

return Callout
