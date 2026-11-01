--!nocheck
-- Keyboard and gamepad focus (DESIGN_V2 3.8). Focus mode starts on an arrow key, Tab or any
-- gamepad input while the pointer is over the window (never on a mouse click). While it is on,
-- navigation keys are sunk so the character does not move. One ring frame travels with focus.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Router = require("input/Router")

local T = Token.T
local Focus = {}
Focus.__index = Focus

local SINK = {
	"Up", "Down", "Left", "Right", "Return", "Space", "Tab", "Home", "End", "PageUp", "PageDown",
	"DPadUp", "DPadDown", "DPadLeft", "DPadRight", "ButtonA", "ButtonB", "ButtonX", "ButtonY", "ButtonL1", "ButtonR1",
}

function Focus.attach(window)
	local self = setmetatable({ window = window, active = false, current = nil }, Focus)
	self.consumer = Router.layerKey(function(input, processed) return self:_key(input, processed) end, 80)
	return self
end

function Focus:_items()
	local window = self.window
	local tab = window.ActiveTab
	local out = {}
	if not tab then return out end
	for _, element in ipairs(tab._elements) do
		if not element._destroyed and element:_isVisible() and not element._disabled and not element._whenDisabled
			and element._spec and element._spec.focus ~= false and not element._spec.display then
			out[#out + 1] = element
		end
	end
	return out
end

function Focus:_ring()
	if self.ring then return self.ring end
	local scope = self.window._scope:child("focus")
	self.scope = scope
	self.ring = Factory.new(scope, "Frame", {
		Name = "FocusRing", BackgroundTransparency = 1, Visible = false, ZIndex = 60,
	})
	self.ringCorner = Factory.corner(scope, self.ring, 13)
	Factory.stroke(scope, self.ring, T.Focus, 0, 2)
	return self.ring
end

function Focus:enter(reason)
	if self.active then return end
	local window = self.window
	if not window._visible or window._loading then return end
	self.active = true
	local codes = {}
	for _, name in ipairs(SINK) do
		local code = Env.enum("KeyCode", name)
		if code then codes[#codes + 1] = code end
	end
	Router.sink("ArgonFocus" .. window._guiName, true, codes)
	if not self.current then
		local items = self:_items()
		if items[1] then self:focus(items[1], { visible = true, scroll = true }) end
	else
		self:_place(true)
	end
	self:_hints()
end

function Focus:leave()
	if not self.active then return end
	self.active = false
	Router.sink("ArgonFocus" .. self.window._guiName, false)
	if self.ring then self.ring.Visible = false end
	if self.window._glow then self.window._glow:release(1, self) end
	self:_hints()
end

function Focus:focus(element, opts)
	self.current = element
	if not element then return end
	if element._ensureMounted then element:_ensureMounted() end
	if opts and opts.scroll then self:_scrollIntoView(element) end
	if self.active or (opts and opts.visible) then
		if not self.active then self:enter("api") end
		self:_place(false)
	end
	self:_hints()
	local window = self.window
	if element._tooltipText and window._tooltipHost then
		window._tooltipHost:schedule(element._view and element._view.Title or element.Root, element._tooltipText, "focus")
	end
end

function Focus:_place(snap)
	local element = self.current
	local root = element and rawget(element, "Root")
	if not root or not root.Parent then return end
	local ring = self:_ring()
	ring.Parent = root
	ring.Position = UDim2.fromOffset(-3, -3)
	ring.Size = UDim2.new(1, 6, 1, 6)
	ring.Visible = Router.lastInputKind == "keyboard" or Router.lastInputKind == "gamepad"
	if not snap and not Motion.reduced then
		ring.Size = UDim2.new(1, 12, 1, 12)
		ring.Position = UDim2.fromOffset(-6, -6)
		Motion.spring(ring, "Size", UDim2.new(1, 6, 1, 6), "snappy")
		Motion.spring(ring, "Position", UDim2.fromOffset(-3, -3), "snappy")
	end
end

function Focus:_scrollIntoView(element)
	local tab = element._tab
	local root = rawget(element, "Root")
	if not tab or not root or not tab._skeleton then return end
	local page = tab.Page
	local scale = self.window._layers.scale
	local top = (root.AbsolutePosition.Y - page.AbsolutePosition.Y) / scale
	local bottom = top + root.AbsoluteSize.Y / scale
	local height = page.AbsoluteSize.Y / scale
	if top < 24 then
		page.CanvasPosition = Vector2.new(0, math.max(0, page.CanvasPosition.Y + top - 24))
	elseif bottom > height - 24 then
		page.CanvasPosition = Vector2.new(0, page.CanvasPosition.Y + bottom - height + 24)
	end
end

function Focus:move(direction)
	local items = self:_items()
	if #items == 0 then return end
	local index = table.find(items, self.current) or 0
	if direction == "next" then index = math.min(#items, index + 1)
	elseif direction == "prev" then index = math.max(1, index - 1)
	elseif direction == "first" then index = 1
	else index = #items end
	local element = items[index]
	if element and element.Locked then
		self:_hints("Locked: " .. tostring(element.LockReason or "Locked"))
	end
	self:focus(element, { visible = true, scroll = true })
end

-- Pulses the ring on an element (palette "go to").
function Focus:pulse(element)
	self:focus(element, { visible = true, scroll = true })
	if self.ring and not Motion.reduced then
		self.ring.Visible = true
	end
end

function Focus:_key(input, processed)
	local window = self.window
	if not window._visible or window._loading or window._destroyed then return false end
	local key = input.KeyCode and input.KeyCode.Name or ""
	local kind = Router.classify(input.UserInputType)
	local nav = key == "Up" or key == "Down" or key == "Tab" or key == "DPadUp" or key == "DPadDown"
	if not self.active then
		if (nav or key == "Left" or key == "Right") and window._pointerInside and not processed then
			self:enter("keys")
			return true
		end
		if kind == "gamepad" and (nav or key == "DPadLeft" or key == "DPadRight" or key == "ButtonA") then
			self:enter("gamepad")
			return true
		end
		return false
	end
	if window._layers:top() then return false end
	local element = self.current
	local spec = element and element._spec and element._spec.focus or {}
	local shift = Router.isDown(Enum.KeyCode.LeftShift) or Router.isDown(Enum.KeyCode.RightShift)
	if key == "Down" or key == "DPadDown" or (key == "Tab" and not shift) then
		self:move("next")
	elseif key == "Up" or key == "DPadUp" or (key == "Tab" and shift) then
		self:move("prev")
	elseif key == "Left" or key == "DPadLeft" or key == "Right" or key == "DPadRight" then
		local step = (key == "Left" or key == "DPadLeft") and -1 or 1
		if shift then step *= 10 end
		if element and not element:_inactive() and spec.adjust then spec.adjust(element, step) end
	elseif key == "Home" or key == "End" then
		if element and not element:_inactive() and spec.adjust then spec.adjust(element, key == "Home" and -math.huge or math.huge) end
	elseif key == "Return" or key == "Space" or key == "ButtonA" then
		if element and element.Locked then
			element:_lockedPoke()
		elseif element and not element:_inactive() and spec.activate then
			spec.activate(element)
		end
	elseif key == "ButtonX" or (key == "F10" and shift) then
		if element then element:_openMenu(nil) end
	elseif key == "ButtonB" or key == "Backspace" then
		self:leave()
	else
		return false
	end
	return true
end

function Focus:_hints(override)
	local window = self.window
	local label = window._hintText
	if not label then return end
	if override then
		label.Text = override
		return
	end
	local element = self.current
	local kind = element and element.Type
	local text = "A Select · B Back · X Options · Y Search"
	if kind == "Toggle" then text = "A Toggle · X Options · B Back · Y Search"
	elseif kind == "Slider" or kind == "Stepper" then text = "← → Adjust · A Type value · X Options"
	elseif kind == "Dropdown" then text = "A Open · X Options · B Back" end
	label.Text = text
end

function Focus:destroy()
	self:leave()
	if self.consumer then self.consumer.remove() end
end

return Focus
