--!nocheck
-- Small helpers shared by every module.

local Util = {}

function Util.copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in pairs(value) do out[key] = Util.copy(item) end
	return out
end

function Util.shallow(value)
	if type(value) ~= "table" then return value end
	return table.clone(value)
end

function Util.clamp(x, a, b)
	if a > b then a, b = b, a end
	if x < a then return a end
	if x > b then return b end
	return x
end

-- Number of decimal places in a step such as 0.05.
function Util.decimals(step)
	local text = tostring(step)
	local fraction = text:match("%.(%d+)$")
	if text:find("e%-") then
		return tonumber(text:match("e%-(%d+)")) or 0
	end
	return fraction and #fraction or 0
end

-- v1 rounding: floor((x-min)/step+.5)*step+min, then rounded to the step's decimals.
function Util.roundToStep(x, min, step)
	if not step or step <= 0 then
		return math.floor(x * 100 + 0.5) / 100
	end
	local value = math.floor((x - min) / step + 0.5) * step + min
	local places = Util.decimals(step)
	local factor = 10 ^ places
	return math.floor(value * factor + 0.5) / factor
end

-- "Enum.KeyCode.K", EnumItem or "K" -> "K"; empty or unknown -> "None".
function Util.keyName(value)
	if value == nil then return "None" end
	if typeof(value) == "EnumItem" then return value.Name end
	local text = tostring(value):gsub("^Enum%.KeyCode%.", ""):gsub("^Enum%.UserInputType%.", "")
	if text == "" or text == "Unknown" then return "None" end
	return text
end

-- A KeyCode (or mouse/gamepad UserInputType) from an EnumItem or a name; nil when unknown.
function Util.keyCode(value)
	if value == nil then return nil end
	if typeof(value) == "EnumItem" then
		if value.Name == "Unknown" then return nil end
		return value
	end
	local name = Util.keyName(value)
	if name == "None" then return nil end
	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	if ok and code then return code end
	if name == "MouseButton2" or name == "MouseButton3" or name == "MouseButton1" then
		local okInput, inputType = pcall(function() return Enum.UserInputType[name] end)
		if okInput and inputType then return inputType end
	end
	return nil
end

function Util.trim(text)
	return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

function Util.utf8len(text)
	local ok, length = pcall(utf8.len, text)
	return (ok and length) or #text
end

function Util.utf8sub(text, i, j)
	local length = Util.utf8len(text)
	j = j or length
	if i < 0 then i = length + i + 1 end
	if j < 0 then j = length + j + 1 end
	if i < 1 then i = 1 end
	if j > length then j = length end
	if i > j then return "" end
	local ok, startByte = pcall(utf8.offset, text, i)
	local ok2, endByte = pcall(utf8.offset, text, j + 1)
	if not ok or not ok2 or not startByte then return text:sub(i, j) end
	return text:sub(startByte, (endByte or #text + 1) - 1)
end

function Util.truncate(text, limit)
	text = tostring(text or "")
	if Util.utf8len(text) <= limit then return text end
	return Util.utf8sub(text, 1, limit)
end

-- Structural equality for values that came from JSON-like data.
function Util.jsonEqual(a, b)
	if a == b then return true end
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then return false end
	if ta ~= "table" then return false end
	for key, value in pairs(a) do
		if not Util.jsonEqual(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

local warned = {}
function Util.warnOnce(key, message)
	if warned[key] then return end
	warned[key] = true
	warn(message)
end

-- Called with (context, message, retry) when a host callback errors. feature/Toast sets it.
Util.onError = nil
local reported = setmetatable({}, { __mode = "k" })

-- Runs a host callback under xpcall. Errors are warned once per element and message, and
-- passed to Util.onError. Returns ok plus the callback's results.
function Util.xcall(fn, context, owner, ...)
	if type(fn) ~= "function" then return true end
	local results = table.pack(xpcall(fn, debug.traceback, ...))
	if results[1] then
		return table.unpack(results, 1, results.n)
	end
	local message = tostring(results[2]):gsub("\n.*$", "")
	local key = owner or Util
	local seen = reported[key]
	if not seen then
		seen = {}
		reported[key] = seen
	end
	if not seen[message] then
		seen[message] = true
		warn("[Argon UI] " .. tostring(context) .. " callback error: " .. message)
	end
	local hook = Util.onError
	if hook then
		local args = table.pack(...)
		pcall(hook, context, message, function()
			return Util.xcall(fn, context, owner, table.unpack(args, 1, args.n))
		end, owner)
	end
	return false, message
end

-- A short human time like "2 s ago".
function Util.ago(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then return seconds .. " s ago" end
	if seconds < 3600 then return math.floor(seconds / 60) .. " m ago" end
	return math.floor(seconds / 3600) .. " h ago"
end

return Util
