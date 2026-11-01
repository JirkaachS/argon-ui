--!nocheck
-- Scope: owns everything a component creates (instances, connections, tweens, timers, child
-- scopes) plus a flat paint list of themed properties. Destroying a scope releases all of it
-- in O(its own size). There is no global registry anywhere in the library.

local Scope = {}
Scope.__index = Scope
Scope.live = 0

local Token -- set by Scope.bind (avoids a require cycle with core/Token users)
local Motion

function Scope.bind(token, motion)
	Token = token
	Motion = motion
end

function Scope.new(label, parent)
	local self = setmetatable({
		label = label,
		dead = false,
		paints = {},
		_items = {},
		_children = {},
		_owned = setmetatable({}, { __mode = "k" }),
	}, Scope)
	Scope.live += 1
	if parent then
		parent._children[#parent._children + 1] = self
		self._parent = parent
	end
	return self
end

function Scope:child(label)
	return Scope.new(label, self)
end

-- Tracks anything destroyable: Instance, connection, tween, function or Scope.
function Scope:add(item)
	if self.dead then
		Scope._release(item)
		return item
	end
	self._items[#self._items + 1] = item
	return item
end

function Scope:instance(inst)
	self._owned[inst] = true
	local parent = inst.Parent
	if parent == nil or not self._owned[parent] then
		self._items[#self._items + 1] = inst
	end
	return inst
end

function Scope:owns(inst)
	return self._owned[inst] == true
end

function Scope:connect(signal, fn)
	local connection = signal:Connect(fn)
	self._items[#self._items + 1] = connection
	return connection
end

-- task.delay that is cancelled with the scope. Returns a handle with :cancel().
function Scope:delay(seconds, fn)
	local handle = { cancelled = false }
	function handle.cancel() handle.cancelled = true end
	task.delay(seconds, function()
		if handle.cancelled or self.dead then return end
		handle.cancelled = true
		fn()
	end)
	self._items[#self._items + 1] = handle
	return handle
end

function Scope:tween(inst, token, props, opts)
	local tween = Motion.tween(inst, token, props, opts)
	if tween then self._items[#self._items + 1] = tween end
	return tween
end

-- Records a themed property so a theme, font or density change can re-apply it.
function Scope:paint(inst, prop, token)
	local paints = self.paints
	local n = #paints
	paints[n + 1] = inst
	paints[n + 2] = prop
	paints[n + 3] = token
end

-- Re-applies every recorded token in this scope and its children.
function Scope:repaint()
	local paints = self.paints
	local resolve = Token.resolve
	for index = 1, #paints, 3 do
		local inst = paints[index]
		local value = resolve(paints[index + 2])
		if value ~= nil then
			inst[paints[index + 1]] = value
		end
	end
	for _, child in ipairs(self._children) do
		if not child.dead then child:repaint() end
	end
end

-- Drops the paint entries for one instance (it changed to a state-driven colour).
function Scope:unpaint(inst, prop)
	local paints = self.paints
	local index = 1
	while index <= #paints do
		if paints[index] == inst and (prop == nil or paints[index + 1] == prop) then
			table.remove(paints, index)
			table.remove(paints, index)
			table.remove(paints, index)
		else
			index += 3
		end
	end
end

function Scope._release(item)
	local kind = typeof(item)
	if kind == "Instance" then
		if item.ClassName == "Tween" then
			pcall(item.Cancel, item)
		else
			pcall(item.Destroy, item)
		end
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		pcall(item)
	elseif kind == "table" then
		if getmetatable(item) == Scope then
			item:destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Cancel) == "function" then
			pcall(item.Cancel, item)
		elseif type(item.cancel) == "function" then
			item.cancel()
		elseif type(item.stop) == "function" then
			item.stop()
		elseif type(item.Destroy) == "function" then
			pcall(item.Destroy, item)
		end
	elseif kind == "Tween" then
		pcall(item.Cancel, item)
	end
end

-- Releases the contents and keeps the scope usable.
function Scope:clear()
	local children = self._children
	for index = #children, 1, -1 do
		children[index]:destroy()
	end
	table.clear(children)
	local items = self._items
	self._items = {}
	-- connections, tweens and timers first, then instances (roots go last so nothing fires
	-- into a half-destroyed tree)
	for index = 1, #items do
		local item = items[index]
		if typeof(item) ~= "Instance" then Scope._release(item) end
	end
	for index = #items, 1, -1 do
		local item = items[index]
		if typeof(item) == "Instance" then Scope._release(item) end
	end
	table.clear(self.paints)
	self._owned = setmetatable({}, { __mode = "k" })
end

function Scope:destroy()
	if self.dead then return end
	self:clear()
	self.dead = true
	Scope.live -= 1
	local parent = self._parent
	if parent and not parent.dead then
		local list = parent._children
		for index = #list, 1, -1 do
			if list[index] == self then
				table.remove(list, index)
				break
			end
		end
	end
end

return Scope
