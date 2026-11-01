--!nocheck
-- Colour maths: hex, WCAG contrast, mixing and OKLab lightness.

local Color = {}

function Color.hex(text)
	text = tostring(text):gsub("#", "")
	if #text == 3 then text = text:gsub(".", "%0%0") end
	if not text:match("^%x%x%x%x%x%x") then return nil end
	return Color3.fromRGB(tonumber(text:sub(1, 2), 16), tonumber(text:sub(3, 4), 16), tonumber(text:sub(5, 6), 16))
end

function Color.toHex(c)
	local function byte(v) return math.clamp(math.floor(v * 255 + 0.5), 0, 255) end
	return ("%02X%02X%02X"):format(byte(c.R), byte(c.G), byte(c.B))
end

local function linear(v)
	if v <= 0.04045 then return v / 12.92 end
	return ((v + 0.055) / 1.055) ^ 2.4
end
local function gamma(v)
	v = math.clamp(v, 0, 1)
	if v <= 0.0031308 then return v * 12.92 end
	return 1.055 * v ^ (1 / 2.4) - 0.055
end

function Color.luminance(c)
	return 0.2126 * linear(c.R) + 0.7152 * linear(c.G) + 0.0722 * linear(c.B)
end

function Color.contrast(a, b)
	local la, lb = Color.luminance(a), Color.luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

function Color.mix(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
Color.WHITE, Color.BLACK = WHITE, BLACK

function Color.isLight(c)
	return Color.luminance(c) > 0.5
end

-- Moves c toward `toward` in small steps until contrast(c, against) >= target (or 40 steps).
function Color.stepUntil(c, toward, against, target)
	local current = c
	for _ = 1, 40 do
		if Color.contrast(current, against) >= target then return current end
		current = Color.mix(current, toward, 0.06)
	end
	return current
end

-- OKLab lightness change (amount in [-1, 1] of L).
function Color.shiftL(c, amount)
	local r, g, b = linear(c.R), linear(c.G), linear(c.B)
	local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
	local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
	local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
	local L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	local A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	local B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	L = math.clamp(L * (1 + amount), 0, 1)
	local l2 = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
	local m2 = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
	local s2 = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
	return Color3.new(
		gamma(4.0767416621 * l2 - 3.3077115913 * m2 + 0.2309699292 * s2),
		gamma(-1.2684380046 * l2 + 2.6097574011 * m2 - 0.3413193965 * s2),
		gamma(-0.0041960863 * l2 - 0.7034186147 * m2 + 1.7076147010 * s2)
	)
end

return Color
