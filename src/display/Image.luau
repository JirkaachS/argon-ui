--!nocheck
-- Image (DESIGN_V2 6.20): an image inside the platter padding with rounded corners (Corner,
-- default 10) and an optional 12 Muted caption. Image takes an asset id, a content URL or a
-- Lucide name. Set(image) or Set{Image, Caption}.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Env = require("core/Env")
local Element = require("component/Element")
local Icons = require("icons/Icons")

local T, F, TS = Token.T, Token.F, Token.TS
local PAD = 12

local function size(self)
	return PAD * 2 + self._height + (self._caption and 22 or 0)
end

local function place(self)
	local view = self._view
	if not view or not self._image or not rawget(self, "_mounted") then return end
	local caption = self._caption
	if caption and not self._captionLabel then
		self._captionLabel = Factory.text(self._scope, "TextLabel", {
			Name = "Caption", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(view.padH, PAD + self._height + 6), Size = UDim2.new(1, -view.padH * 2, 0, 16),
		}, view.Root)
	end
	if self._captionLabel then
		self._captionLabel.Visible = caption ~= nil
		self._captionLabel.Text = caption or ""
	end
	Icons.apply(self._image, self.CurrentValue)
	view.band = size(self)
	view.Root.Size = UDim2.new(1, 0, 0, view.band)
end

return Element.define({
	Type = "Image",
	defaultName = "Image",
	display = true,
	title = false,
	counts = false,
	descriptionIsContent = true,

	fromArgs = function(config)
		if type(config) ~= "table" then return { Image = config } end
		return config
	end,

	init = function(self, config)
		self.CurrentValue = config.Image or config.Value
		self._height = math.clamp(math.floor(tonumber(config.Height) or 120), 24, 600)
		local caption = config.Caption or config.Description
		self._caption = caption ~= nil and caption ~= "" and tostring(caption) or nil
	end,

	height = size,

	build = function(self, view, scope)
		local cfg = self._cfg
		self._image = Factory.new(scope, "ImageLabel", {
			Name = "Image", BackgroundTransparency = 1, Position = UDim2.fromOffset(view.padH, PAD),
			Size = UDim2.new(1, -view.padH * 2, 0, self._height),
			ScaleType = Env.enum("ScaleType", tostring(cfg.ScaleType or "Fit"), "Fit"),
		}, view.Root)
		local corner = tonumber(cfg.Corner) or 10
		if corner > 0 then Factory.corner(scope, self._image, corner) end
		place(self)
	end,

	unmount = function(self)
		self._image, self._captionLabel = nil, nil
	end,

	methods = {
		Set = function(self, value)
			if type(value) == "table" then
				if value.Caption ~= nil then self._caption = value.Caption ~= "" and tostring(value.Caption) or nil end
				value = value.Image
			end
			if value ~= nil then self.CurrentValue = value end
			place(self)
			return self
		end,

		SetDesc = function(self, text)
			return self:Set({ Caption = text ~= nil and text or "" })
		end,
	},
})
