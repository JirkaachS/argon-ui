--!nocheck
-- Pinned controls (DESIGN_V2 8.4): one list shown as the sidebar's Pinned group and as the quick
-- dock while the window is hidden. Both are views on the element's own state, so they never
-- disagree with the control. Stored per profile as flag names.

local Signal = require("core/Signal")
local Prefs = require("persist/Prefs")
local Platform = require("input/Platform")

local Pins = {}
Pins.__index = Pins

function Pins.attach(window)
	local self = setmetatable({ window = window, items = {}, changed = Signal.new("Pins.changed") }, Pins)
	self.saved = {}
	for _, flag in ipairs(Prefs.getProfile("Pins") or {}) do self.saved[flag] = true end
	return self
end

function Pins:limit()
	return Platform.preferred() == "touch" and 4 or 6
end

function Pins:has(element)
	return table.find(self.items, element) ~= nil
end

function Pins:list()
	return self.items
end

function Pins:_persist()
	local flags = {}
	for _, element in ipairs(self.items) do
		if element.Flag then flags[#flags + 1] = element.Flag end
	end
	Prefs.setProfile("Pins", flags)
end

-- Pins an element. fromHost pins without the limit message (Pinned = true in the config).
function Pins:add(element, fromHost)
	if self:has(element) then return true end
	if #self.items >= self:limit() then
		if not fromHost and self.window._toast then self.window:_toast("Unpin one first", "warning") end
		return false
	end
	self.items[#self.items + 1] = element
	if not fromHost then self:_persist() end
	self.changed:Fire()
	return true
end

function Pins:remove(element)
	local index = table.find(self.items, element)
	if index then
		table.remove(self.items, index)
		self:_persist()
		self.changed:Fire()
	end
end

function Pins:forget(element)
	local index = table.find(self.items, element)
	if index then
		table.remove(self.items, index)
		self.changed:Fire()
	end
end

function Pins:toggle(element)
	if self:has(element) then self:remove(element) else self:add(element) end
end

-- Restores a saved pin when its control is created.
function Pins:noteElement(element)
	if element.Flag and self.saved[element.Flag] and not self:has(element) then
		self.items[#self.items + 1] = element
		self.changed:Fire()
	end
end

-- Runs a pinned control: flips a switch, presses a button.
function Pins:activate(element)
	if element._inactive and element:_inactive() then return end
	if element.Type == "Toggle" then
		element:Set(not element.CurrentValue)
	elseif element.Type == "Button" and element._press then
		element:_press()
	end
end

return Pins
