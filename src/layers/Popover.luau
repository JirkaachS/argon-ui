--!nocheck
-- One pooled popover host per window. Content for each reuse key ("dropdown", "color",
-- "theme", "menu", ...) is built on its first open and rebound afterwards, so reopening a
-- picker creates no instances. On phones a popover can render as a bottom sheet.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Assets = require("theme/Assets")
local Metrics = require("theme/Metrics")
local Platform = require("input/Platform")

local T = Token.T
local Popover = {}
Popover.__index = Popover

function Popover.attach(window)
	return setmetatable({
		window = window,
		layers = window._layers,
		scope = window._scope:child("popover"),
		contents = {},
		current = nil,
		counter = 0,
	}, Popover)
end

-- Adds the lit edge: a white UIStroke fading down the object (DESIGN_V2 2.6).
function Popover.litEdge(scope, parent, transparency)
	local stroke = Factory.new(scope, "UIStroke", {
		Color = T.White,
		Transparency = transparency or 0.86,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
	Factory.new(scope, "UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, stroke)
	return stroke
end

-- A shadow image sized around a target rect (sibling, drawn below it).
function Popover.shadow(scope, parent, zindex, transparency)
	return Factory.new(scope, "ImageLabel", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = Assets.shadow.Image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.shadow.SliceCenter,
		ImageColor3 = T.Shadow,
		ImageTransparency = transparency or 0.45,
		ZIndex = zindex or 1,
		Visible = false,
	}, parent)
end

function Popover.placeShadow(shadow, position, size, spread, drop)
	spread = spread or 24
	shadow.Position = UDim2.fromOffset(position.X - spread, position.Y - spread + (drop or 8))
	shadow.Size = UDim2.fromOffset(size.X + spread * 2, size.Y + spread * 2)
end

function Popover:_ensure()
	if self.panel then return end
	local scope = self.scope
	local layer = self.layers:get("Popover")
	self.catcher = Factory.new(scope, "TextButton", {
		Name = "Catcher",
		BackgroundColor3 = T.Scrim,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Visible = false,
		Modal = false,
	}, layer)
	scope:connect(self.catcher.MouseButton1Down, function() self:close("outside") end)
	self.shadow = Popover.shadow(scope, layer, 2)
	local panel = Factory.new(scope, "Frame", {
		Name = "Popover",
		BackgroundColor3 = T.Raised,
		Active = true,
		ClipsDescendants = true,
		ZIndex = 3,
		Visible = false,
	}, layer)
	self.corner = Factory.corner(scope, panel, Metrics.radius.popover)
	Popover.litEdge(scope, panel)
	self.uiscale = Factory.new(scope, "UIScale", { Scale = 1 }, panel)
	self.body = Factory.new(scope, "Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, panel)
	self.veil = Factory.new(scope, "Frame", {
		Name = "Veil",
		BackgroundColor3 = T.Raised,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Visible = false,
	}, panel)
	self.panel = panel
end

-- Builds a reuse key's content without opening it (test seams such as Window.ThemePicker).
function Popover:prebuild(spec)
	self:_ensure()
	local content = self.contents[spec.reuse]
	if content then return content end
	local frameScope = self.scope:child(spec.reuse)
	local frame = Factory.new(frameScope, "Frame", {
		Name = spec.name or spec.reuse,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
	}, self.body)
	content = { frame = frame, scope = frameScope, key = spec.reuse }
	content.size = spec.build and spec.build(frame, frameScope, self) or nil
	self.contents[spec.reuse] = content
	return content
end

function Popover:isOpen(owner)
	if not self.current then return false end
	return owner == nil or self.current.spec.owner == owner
end

-- spec: { owner, anchor (GuiObject) | point (Vector2), reuse, build(frame, scope, host) -> Vector2?,
--         bind(frame, scope, host) -> Vector2?, width, maxHeight, side, sheetOnPhone, onClose, title }
function Popover:open(spec)
	if self.current then self:close("replace") end
	self:_ensure()
	local key = spec.reuse
	if not key then
		self.counter += 1
		key = "once" .. self.counter
	end
	local content = self.contents[key]
	if not content then
		local frameScope = self.scope:child(key)
		local frame = Factory.new(frameScope, "Frame", {
			Name = spec.name or (key:sub(1, 4) == "once" and "Content" or key),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Visible = false,
		}, self.body)
		content = { frame = frame, scope = frameScope, key = key }
		content.size = spec.build and spec.build(frame, frameScope, self) or nil
		if spec.reuse then self.contents[key] = content end
	end
	for _, other in pairs(self.contents) do other.frame.Visible = other == content end
	content.frame.Visible = true
	local size = (spec.bind and spec.bind(content.frame, content.scope, self)) or content.size or Vector2.new(240, 200)
	local openScope = self.scope:child("open")
	local entry = { kind = spec.kind or "popover", id = key }
	self.current = { spec = spec, content = content, scope = openScope, size = size, entry = entry }
	entry.close = function(reason) self:close(reason, true) end
	self.layers:push(entry)
	self:reposition()
	self.panel.Visible = true
	self.catcher.Visible = true
	self.shadow.Visible = true
	local animated = not Motion.reduced
	if animated then
		self.uiscale.Scale = 0.96
		Motion.tween(self.uiscale, "popIn", { Scale = 1 })
		self.veil.Visible = true
		self.veil.BackgroundTransparency = 0
		Motion.tween(self.veil, "veil", { BackgroundTransparency = 1 }, { delay = 0.04 })
	end
	local anchor = spec.anchor
	if typeof(anchor) == "Instance" then
		openScope:connect(anchor:GetPropertyChangedSignal("AbsolutePosition"), function() self:reposition() end)
	end
	openScope:connect(self.layers.resized, function() self:reposition() end)
	return {
		panel = self.panel,
		content = content.frame,
		close = function(reason) if self.current and self.current.content == content then self:close(reason) end end,
		resize = function(newSize)
			if self.current and self.current.content == content then
				self.current.size = newSize
				self:reposition()
			end
		end,
	}
end

function Popover:reposition()
	local current = self.current
	if not current then return end
	local spec = current.spec
	local layers = self.layers
	local area = layers:localSize()
	local size = current.size
	local phone = spec.sheetOnPhone and Platform.isPhone(layers:guiSize())
	local width, height, x, y
	if phone then
		width = area.X >= 600 and math.min(560, area.X) or area.X
		height = math.min(size.Y + 28, math.floor(area.Y * 0.8))
		x = math.floor((area.X - width) / 2)
		y = area.Y - height + 28
		self.corner.CornerRadius = UDim.new(0, Metrics.radius.phone)
		self.catcher.BackgroundTransparency = 0.45
		height += 28
	else
		self.corner.CornerRadius = UDim.new(0, Metrics.radius.popover)
		self.catcher.BackgroundTransparency = 1
		local anchorPos, anchorSize
		if typeof(spec.anchor) == "Instance" then
			anchorPos, anchorSize = layers:rectOf(spec.anchor)
		elseif typeof(spec.point) == "Vector2" then
			anchorPos, anchorSize = layers:toLocal(spec.point), Vector2.zero
		else
			anchorPos, anchorSize = Vector2.new(area.X / 2, area.Y / 2), Vector2.zero
		end
		width = spec.width == "anchor" and math.max(anchorSize.X, 220) or (spec.width or math.max(anchorSize.X, size.X, 220))
		width = math.min(width, area.X - 16)
		height = math.min(size.Y, spec.maxHeight or 360, area.Y - 16)
		x = spec.point and anchorPos.X or (anchorPos.X + anchorSize.X - width)
		if spec.alignLeft then x = anchorPos.X end
		local below = anchorPos.Y + anchorSize.Y + 6
		local above = anchorPos.Y - 6 - height
		y = below
		if spec.side == "above" or (spec.side ~= "below" and below + height > area.Y - 8 and above >= 8) then y = above end
		x = math.clamp(x, 8, math.max(8, area.X - width - 8))
		y = math.clamp(y, 8, math.max(8, area.Y - height - 8))
	end
	local panel = self.panel
	panel.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	panel.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	Popover.placeShadow(self.shadow, Vector2.new(x, y), Vector2.new(width, height), 20, 8)
	current.placed = { x = x, y = y, width = width, height = height }
end

-- Closes the open popover. fromStack is true when the dismiss stack already removed it.
function Popover:close(reason, fromStack)
	local current = self.current
	if not current then return end
	self.current = nil
	if not fromStack then self.layers:pop(current.entry) end
	current.scope:destroy()
	if self.panel then
		self.panel.Visible = false
		self.catcher.Visible = false
		self.shadow.Visible = false
		self.veil.Visible = false
	end
	current.content.frame.Visible = false
	if not current.spec.reuse then
		current.content.scope:destroy()
	end
	if current.spec.onClose then
		local ok, err = pcall(current.spec.onClose, reason or "close")
		if not ok then warn("[Argon UI] popover close handler error: " .. tostring(err)) end
	end
end

function Popover:openCount()
	return self.current and 1 or 0
end

return Popover
