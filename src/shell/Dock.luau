--!nocheck
-- What stays on screen while the window is hidden (DESIGN_V2 3.7): the dock pill (keyboard and
-- mouse, on request), the reopen orb (touch), and the quick dock of pinned controls next to them.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Util = require("core/Util")
local Metrics = require("theme/Metrics")
local Drag = require("input/Drag")
local Platform = require("input/Platform")
local Popover = require("layers/Popover")
local Prefs = require("persist/Prefs")
local Shell = require("shell/Shell")

local T, F, TS, M = Token.T, Token.F, Token.TS, Token.M
local Dock = {}
Dock.__index = Dock

function Dock.attach(window)
	return setmetatable({ window = window, scope = window._scope:child("dock"), chips = {} }, Dock)
end

function Dock:_wanted()
	local window = self.window
	if window._visible or window._loading or window._destroyed then return nil end
	local mode = window._openButton or "auto"
	if mode == false or mode == "off" then return nil end
	if Platform.preferred() == "touch" then return "orb" end
	if mode == true or mode == "always" then return "pill" end
	if not window._toggleKey then return "pill" end
	return nil
end

function Dock:_build(kind)
	if self.kind == kind and self.root then return end
	if self.root then
		self.root:Destroy()
		self.root = nil
	end
	local scope = self.scope
	local window = self.window
	local layer = window._layers:get("Base")
	local orb = kind == "orb"
	local root = Factory.new(scope, "TextButton", {
		Name = orb and "ReopenOrb" or "DockPill",
		BackgroundColor3 = T.Frame,
		BackgroundTransparency = M.Dock,
		Size = orb and UDim2.fromOffset(56, 56) or UDim2.fromOffset(0, 44),
		AutomaticSize = orb and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		Active = true,
		ZIndex = 40,
		Visible = false,
	}, layer)
	Factory.corner(scope, root, "full")
	Popover.litEdge(scope, root, 0.86)
	local logo = Shell.logo(scope, root, window, orb and 28 or 24)
	if orb then
		logo.AnchorPoint = Vector2.new(0.5, 0.5)
		logo.Position = UDim2.fromScale(0.5, 0.5)
	else
		Factory.padding(scope, root, 10, 14, 0, 0)
		Factory.list(scope, root, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center })
		Factory.text(scope, "TextLabel", { Text = Util.truncate(window._title, 18), FontFace = F.Label, TextSize = TS.Label,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2, ZIndex = 41 }, root)
		if window._toggleKey then
			local cap = Factory.text(scope, "TextLabel", { Text = Util.keyName(window._toggleKey), FontFace = F.Key, TextSize = TS.Key,
				BackgroundColor3 = T.Raised, BackgroundTransparency = 0, AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22), TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3, ZIndex = 41 }, root)
			Factory.corner(scope, cap, 6)
			Factory.padding(scope, cap, 6, 6, 0, 0)
		end
	end
	scope:connect(root.InputBegan, function(input)
		local inputKind = input.UserInputType and input.UserInputType.Name
		if inputKind ~= "MouseButton1" and inputKind ~= "Touch" then return end
		local start = root.Position
		local origin = Vector2.new(input.Position.X, input.Position.Y)
		local moved = false
		Drag.begin(input, {
			threshold = 6,
			onMove = function(position)
				moved = true
				local delta = (position - origin) / window._layers.scale
				root.Position = UDim2.fromOffset(start.X.Offset + delta.X, start.Y.Offset + delta.Y)
				self:_placeChips()
			end,
			onEnd = function() if moved then self:_snap() end end,
		})
	end)
	scope:connect(root.MouseButton1Click, function() window:SetVisibility(true) end)
	self.root = root
	self.kind = kind
end

function Dock:_defaultPosition()
	local area = self.window._layers:localSize()
	return UDim2.fromOffset(12, math.floor(area.Y * 0.3))
end

function Dock:_snap()
	local area = self.window._layers:localSize()
	local root = self.root
	local width = root.AbsoluteSize.X / self.window._layers.scale
	local x = root.Position.X.Offset
	local y = math.clamp(root.Position.Y.Offset, 8, area.Y - 64)
	local target = x + width / 2 < area.X / 2 and 12 or (area.X - width - 12)
	Motion.spring(root, "Position", UDim2.fromOffset(target, y), "dock", nil, function() self:_placeChips() end)
	Prefs.set("DockPosition", { X = target, Y = y, Right = target > area.X / 2 })
end

function Dock:refresh()
	local kind = self:_wanted()
	if not kind then
		if self.root then self.root.Visible = false end
		for _, chip in ipairs(self.chips) do chip.Visible = false end
		return
	end
	self:_build(kind)
	local saved = Prefs.get("DockPosition")
	if type(saved) == "table" and tonumber(saved.Y) then
		local area = self.window._layers:localSize()
		local x = saved.Right and (area.X - 160) or 12
		self.root.Position = UDim2.fromOffset(x, math.clamp(saved.Y, 8, math.max(8, area.Y - 64)))
	else
		self.root.Position = self:_defaultPosition()
	end
	self.root.Visible = true
	self:_renderChips()
end

-- Labelled chips for pinned controls, stacked next to the pill or orb.
function Dock:_renderChips()
	local window = self.window
	local pins = window._pins and window._pins:list() or {}
	local limit = Platform.preferred() == "touch" and 4 or 6
	local scope = self.scope
	for index = 1, math.max(#pins, #self.chips) do
		local element = pins[index]
		local chip = self.chips[index]
		if element and index <= limit then
			if not chip then
				chip = Factory.text(scope, "TextButton", {
					Name = "QuickChip", FontFace = F.Body, TextSize = TS.Body, BackgroundColor3 = T.Frame,
					BackgroundTransparency = M.Dock, Size = UDim2.fromOffset(150, 40), Active = true, ZIndex = 40,
				}, window._layers:get("Base"))
				Factory.corner(scope, chip, 12)
				Factory.padding(scope, chip, 12, 12, 0, 0)
				self.chips[index] = chip
				scope:connect(chip.MouseButton1Click, function()
					local current = window._pins and window._pins:list()[index]
					if current then
						window._pins:activate(current)
						self:_renderChips()
					end
				end)
			end
			local label = Util.truncate(element.Name, 14)
			if element.Type == "Toggle" then label = (element.CurrentValue and "● " or "○ ") .. label end
			chip.Text = label
			chip.Visible = true
		elseif chip then
			chip.Visible = false
		end
	end
	self:_placeChips()
end

function Dock:_placeChips()
	if not self.root then return end
	local area = self.window._layers:localSize()
	local base = self.root.Position
	local right = base.X.Offset > area.X / 2
	for index, chip in ipairs(self.chips) do
		local x = right and (base.X.Offset - 158) or (base.X.Offset + 64)
		chip.Position = UDim2.fromOffset(x, base.Y.Offset + (index - 1) * 46)
	end
end

function Dock:destroy()
	self.scope:destroy()
end

return Dock
