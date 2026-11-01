--!nocheck
-- Divider: a 1 px BorderSoft rule across the platter, not inset (DESIGN_V2 6.6). An optional
-- caption sits at the left in 12 Text2 and the rule runs on 12 px after it. The row's own
-- divider frame is reused as the rule. Set(visible) (Rayfield), or Set(text) to recaption.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Element = require("component/Element")
local RowView = require("component/RowView")

local T, F, TS = Token.T, Token.F, Token.TS

local function height(self)
	return self.CurrentValue ~= "" and 32 or 13
end

local function place(self)
	local line = self._line
	if not line or not rawget(self, "_mounted") then return end
	local view = self._view
	local text = self.CurrentValue
	local h = height(self)
	view.band = h
	view.Root.Size = UDim2.new(1, 0, 0, h)
	local caption = self._caption
	if text ~= "" and not caption then
		caption = Factory.text(self._scope, "TextLabel", {
			Name = "Caption", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
			TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(view.padH, 0),
		}, view.Root)
		self._caption = caption
	end
	local x = 0
	if caption then
		caption.Visible = text ~= ""
		caption.Text = text
		local width = math.min(RowView.textWidth(text, 12), 400)
		caption.Size = UDim2.fromOffset(width, h)
		if text ~= "" then x = view.padH + width + 12 end
	end
	line.Position = UDim2.fromOffset(x, math.floor(h / 2))
	line.Size = UDim2.new(1, -x, 0, 1)
end

return Element.define({
	Type = "Divider",
	defaultName = "Divider",
	display = true,
	title = false,
	counts = false,
	noMenu = true,
	descriptionIsContent = true,

	fromArgs = function(config)
		if type(config) == "table" then return config end
		return { Title = config }
	end,

	init = function(self, config)
		local text = config.Title or config.Name or config.Text
		self.CurrentValue = text ~= nil and tostring(text) or ""
	end,

	height = height,

	build = function(self, view, scope)
		local line = view.Divider or Factory.new(scope, "Frame", { Name = "Divider", BackgroundColor3 = T.BorderSoft }, view.Root)
		view.Divider = nil -- the section no longer hides it: this rule is the control
		line.Visible = true
		self._line = line
	end,

	render = place, -- after mount, theme and font changes: the caption width may change

	unmount = function(self)
		self._line, self._caption = nil, nil
	end,

	methods = {
		-- Set(visible) as in Rayfield; a string recaptions the rule.
		Set = function(self, value)
			if type(value) == "boolean" then return self:SetVisible(value) end
			self.CurrentValue = value ~= nil and tostring(value) or ""
			self.Name = self.CurrentValue ~= "" and self.CurrentValue or "Divider"
			self._searchIndex = nil
			place(self)
			return self
		end,

		SetDesc = function(self)
			return self
		end,
	},
})
