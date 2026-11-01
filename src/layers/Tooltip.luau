--!nocheck
-- One tooltip per window, built on first show. Hover opens after 0.40 s (0 s when moving from
-- another tip within 0.30 s), focus after 0.60 s. It sits above its anchor and flips below.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Theme = require("theme/Theme")

local T, F, TS = Token.T, Token.F, Token.TS
local Tooltip = {}
Tooltip.__index = Tooltip

local DELAY = { hover = 0.40, focus = 0.60, press = 0 }

function Tooltip.attach(window)
	return setmetatable({ window = window, layers = window._layers, scope = window._scope:child("tooltip"),
		lastHidden = -1, token = 0 }, Tooltip)
end

function Tooltip:_ensure()
	if self.frame then return end
	local layer = self.layers:get("Tooltip")
	local frame = Factory.new(self.scope, "Frame", {
		Name = "Tooltip",
		BackgroundColor3 = T.Raised,
		AutomaticSize = Enum.AutomaticSize.XY,
		Active = false,
		Visible = false,
		ZIndex = 10,
	}, layer)
	Factory.corner(self.scope, frame, 10)
	Factory.padding(self.scope, frame, 10, 10, 8, 8)
	Factory.new(self.scope, "UISizeConstraint", { MaxSize = Vector2.new(260, 400) }, frame)
	self.label = Factory.text(self.scope, "TextLabel", {
		Name = "Text",
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = true,
		FontFace = F.Body,
		TextSize = TS.Caption,
		TextColor3 = T.Text,
		ZIndex = 11,
	}, frame)
	Factory.new(self.scope, "UISizeConstraint", { MaxSize = Vector2.new(240, 400) }, self.label)
	self.frame = frame
end

-- Shows text for anchor after the delay for how ("hover" | "focus" | "press").
function Tooltip:schedule(anchor, text, how)
	self.token += 1
	local token = self.token
	if text == nil or text == "" then
		self:hide()
		return
	end
	local delay = DELAY[how or "hover"] or 0.4
	if how == "hover" and Env.clock() - self.lastHidden < 0.3 then delay = 0 end
	if delay <= 0 then
		self:show(anchor, text)
	else
		task.delay(delay, function()
			if token == self.token and anchor.Parent then self:show(anchor, text) end
		end)
	end
end

function Tooltip:show(anchor, text)
	self:_ensure()
	local frame, label = self.frame, self.label
	local light = Theme.isLight()
	frame.BackgroundColor3 = Theme.get(light and "Text" or "Raised")
	label.TextColor3 = Theme.get(light and "Sheet" or "Text")
	label.Text = text
	local layers = self.layers
	local position, size = layers:rectOf(anchor)
	local area = layers:localSize()
	local textService = Env.services.TextService
	local width, height = 240, 32
	pcall(function()
		local bounds = textService:GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(240, 1000))
		width = math.min(240, bounds.X) + 20
		height = bounds.Y + 16
	end)
	local x = math.clamp(position.X, 8, math.max(8, area.X - width - 8))
	local y = position.Y - height - 6
	if y < 8 then y = position.Y + size.Y + 6 end
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	frame.Visible = true
	self.anchor = anchor
	self.window._tooltip = frame
end

function Tooltip:hide(anchor)
	if anchor and self.anchor ~= anchor and self.window._tooltip == nil then
		self.token += 1
		return
	end
	self.token += 1
	if self.frame and self.frame.Visible then
		self.frame.Visible = false
		self.lastHidden = Env.clock()
	end
	self.anchor = nil
	self.window._tooltip = nil
end

return Tooltip
