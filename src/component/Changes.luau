--!nocheck
-- Change tracking per window: which controls differ from their default, counts per tab and
-- section, and one level of undo for the last reset or paste batch (DESIGN_V2 3.5, 8.3).

local Signal = require("core/Signal")
local Util = require("core/Util")

local Changes = {}
Changes.__index = Changes

function Changes.attach(window)
	return setmetatable({ window = window, changed = {}, counts = setmetatable({}, { __mode = "k" }),
		updated = Signal.new("Changes.updated"), undo = nil }, Changes)
end

local function bump(counts, key, delta)
	if key then counts[key] = math.max(0, (counts[key] or 0) + delta) end
end

-- Re-evaluates one element after a committed change.
function Changes:note(element)
	if element.Default == nil or element._noTrack then return false end
	local isChanged = not Util.jsonEqual(element:_encodeValue(), element:_encodeValue(element.Default))
	local was = self.changed[element] == true
	if isChanged == was then return isChanged end
	local delta = isChanged and 1 or -1
	self.changed[element] = isChanged or nil
	bump(self.counts, element._tab, delta)
	bump(self.counts, element.Section, delta)
	self.updated:Fire(element, isChanged)
	return isChanged
end

function Changes:forget(element)
	if self.changed[element] then
		self.changed[element] = nil
		bump(self.counts, element._tab, -1)
		bump(self.counts, element.Section, -1)
		self.updated:Fire(element, false)
	end
end

function Changes:isChanged(element)
	return self.changed[element] == true
end

function Changes:count(container)
	return self.counts[container] or 0
end

-- Snapshots elements, resets them, and keeps one undo batch. Returns how many changed.
function Changes:resetAll(elements)
	local batch = {}
	for _, element in ipairs(elements) do
		if self.changed[element] and not element._destroyed then
			batch[#batch + 1] = { element = element, value = Util.copy(element:_rawValue()) }
		end
	end
	for _, entry in ipairs(batch) do entry.element:Reset() end
	if #batch > 0 then self.undo = batch end
	return #batch
end

-- Records a batch made elsewhere (paste) so Undo can revert it.
function Changes:remember(element, previous)
	self.undo = { { element = element, value = Util.copy(previous) } }
end

function Changes:canUndo()
	return self.undo ~= nil
end

function Changes:runUndo()
	local batch = self.undo
	if not batch then return false end
	self.undo = nil
	for _, entry in ipairs(batch) do
		if not entry.element._destroyed then entry.element:Set(entry.value) end
	end
	return true
end

return Changes
