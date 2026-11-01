--!nocheck
-- A small synchronous signal. Handlers run in connection order on the firing thread; an error
-- in one handler is warned and does not stop the others. No threads, no BindableEvents.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then return end
	self.Connected = false
	local list = self._signal._handlers
	for index = #list, 1, -1 do
		if list[index] == self then
			table.remove(list, index)
			break
		end
	end
end
Connection.Destroy = Connection.Disconnect

function Signal.new(label)
	return setmetatable({ _handlers = {}, _label = label }, Signal)
end

function Signal:Connect(fn)
	local connection = setmetatable({ Connected = true, _fn = fn, _signal = self }, Connection)
	local list = self._handlers
	list[#list + 1] = connection
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	local list = self._handlers
	local count = #list
	if count == 0 then return end
	if count == 1 then
		local only = list[1]
		local ok, err = pcall(only._fn, ...)
		if not ok then warn("[Argon UI] " .. (self._label or "signal") .. " handler error: " .. tostring(err)) end
		return
	end
	local snapshot = table.clone(list)
	for index = 1, count do
		local connection = snapshot[index]
		if connection.Connected then
			local ok, err = pcall(connection._fn, ...)
			if not ok then warn("[Argon UI] " .. (self._label or "signal") .. " handler error: " .. tostring(err)) end
		end
	end
end

function Signal:DisconnectAll()
	for _, connection in ipairs(self._handlers) do connection.Connected = false end
	table.clear(self._handlers)
end

function Signal:Count()
	return #self._handlers
end

return Signal
