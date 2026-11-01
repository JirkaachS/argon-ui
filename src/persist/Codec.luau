--!nocheck
-- Value formats: unwrapping values written by other libraries, colour interop and the
-- ARGON2 export envelope.

local Codec = {}

-- Unwraps v1/Rayfield wrappers ({CurrentValue}, {Color}, ...) and decodes colours.
-- D25: a colour table without __argonColor is read as 0-255 (Rayfield's packing).
function Codec.normalize(kind, value)
	if type(value) == "table" then
		if value.CurrentValue ~= nil then value = value.CurrentValue
		elseif kind == "Dropdown" and value.CurrentOption ~= nil then value = value.CurrentOption
		elseif kind == "Keybind" and value.CurrentKeybind ~= nil then value = value.CurrentKeybind
		elseif kind == "Keybind" and value.Keybind ~= nil then value = value.Keybind
		elseif kind == "ColorPicker" and value.Object ~= nil then value = value.Object
		elseif kind == "ColorPicker" and value.Color ~= nil then value = value.Color
		elseif value.Value ~= nil then value = value.Value end
	end
	if kind == "ColorPicker" then
		return Codec.toColor(value)
	end
	return value
end

-- A Color3 (plus alpha) from a Color3, an Argon colour record, an RGB table or a hex string.
function Codec.toColor(value)
	if typeof(value) == "Color3" then return value end
	if type(value) == "table" then
		if value.__argonColor then
			return Color3.new(tonumber(value.R) or 0, tonumber(value.G) or 0, tonumber(value.B) or 0), tonumber(value.A)
		end
		local r = tonumber(value.R or value.r or value[1])
		local g = tonumber(value.G or value.g or value[2])
		local b = tonumber(value.B or value.b or value[3])
		if r and g and b then
			return Color3.fromRGB(r, g, b)
		end
	elseif type(value) == "string" then
		local hex = value:gsub("#", "")
		if hex:match("^%x%x%x%x%x%x") then
			local alpha = #hex >= 8 and tonumber(hex:sub(7, 8), 16) / 255 or nil
			return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)), alpha
		end
	end
	return value
end

function Codec.fromColor(color, alpha)
	local record = { __argonColor = true, R = color.R, G = color.G, B = color.B }
	if alpha and alpha < 1 then record.A = alpha end
	return record
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Codec.base64(text)
	local out = {}
	for index = 1, #text, 3 do
		local a, b, c = text:byte(index, index + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local chars = {}
		for shift = 3, 0, -1 do
			local digit = math.floor(n / 64 ^ shift) % 64
			chars[#chars + 1] = ALPHABET:sub(digit + 1, digit + 1)
		end
		if not b then chars[3], chars[4] = "=", "=" elseif not c then chars[4] = "=" end
		out[#out + 1] = table.concat(chars)
	end
	return table.concat(out)
end

function Codec.unbase64(text)
	text = text:gsub("[^%w%+/=]", "")
	local out = {}
	for index = 1, #text, 4 do
		local n, pad = 0, 0
		for offset = 0, 3 do
			local char = text:sub(index + offset, index + offset)
			local value = ALPHABET:find(char, 1, true)
			if char == "=" or not value then
				pad += 1
				value = 1
			end
			n = n * 64 + (value - 1)
		end
		local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
		out[#out + 1] = string.char(a)
		if pad < 2 then out[#out + 1] = string.char(b) end
		if pad < 1 then out[#out + 1] = string.char(c) end
	end
	return table.concat(out)
end

return Codec
