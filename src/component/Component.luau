--!nocheck
-- Base class for everything that can exist as state before it has instances. Reading a
-- declared view field (Root, _title, ...) on an unmounted object mounts it synchronously, so
-- scripts that touch instances keep working and only pay for what they touch.

local Component = {}

local function lookup(class, key)
	local value = class[key]
	if value ~= nil then return value end
	local base = rawget(class, "_base")
	while base do
		value = base[key]
		if value ~= nil then return value end
		base = rawget(base, "_base")
	end
	return nil
end

-- Creates a class. spec: { ClassName, viewFields = {..}, base = parentClass? }.
function Component.extend(spec)
	local class = {}
	class.ClassName = spec.ClassName
	class._base = spec.base
	local fields = {}
	if spec.base and spec.base._viewFields then
		for key in pairs(spec.base._viewFields) do fields[key] = true end
	end
	for _, key in ipairs(spec.viewFields or {}) do fields[key] = true end
	class._viewFields = fields
	class._meta = {
		__index = function(self, key)
			local method = lookup(class, key)
			if method ~= nil then return method end
			if fields[key] and not rawget(self, "_mounted") and not rawget(self, "_destroyed") then
				local ensure = lookup(class, "_ensureMounted")
				if ensure then ensure(self) end
				return rawget(self, key)
			end
			return nil
		end,
		__tostring = function(self)
			return (spec.ClassName or "Component") .. " " .. tostring(rawget(self, "Name") or "")
		end,
	}
	function class.new(fields0)
		return setmetatable(fields0 or {}, class._meta)
	end
	return class
end

function Component.isA(object, class)
	local meta = getmetatable(object)
	return type(meta) == "table" and meta == class._meta
end

return Component
