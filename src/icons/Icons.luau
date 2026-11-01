--!nocheck
-- Lucide icon resolver over the embedded IconData map. No network. Core glyphs resolve
-- without decoding; the full set is decoded on the first non-core lookup (or by an idle job).

local Token = require("core/Token")
local IconData = require("icons/IconData")

local Icons = {}
Icons.fallback = "circle-dashed"
Icons.missing = {}
Icons.count = IconData.count

local full = nil
local specs = {}
local B36 = 36

function Icons.decode()
	if full then return full end
	local index, previous = {}, ""
	for line in IconData.packed:gmatch("[^\n]+") do
		local name = previous:sub(1, tonumber(line:sub(1, 1), B36)) .. line:sub(2, -4)
		index[name] = line:sub(-3)
		previous = name
	end
	full = index
	return full
end

function Icons.decoded()
	return full ~= nil
end

local function codeFor(name)
	name = IconData.aliases[name] or name
	local code = IconData.core[name]
	if code then return code end
	return Icons.decode()[name]
end

local function specFor(code)
	local cached = specs[code]
	if cached then return cached end
	local cell = IconData.cell
	local spec = {
		Image = "rbxassetid://" .. IconData.sheets[tonumber(code:sub(1, 1), B36) + 1],
		ImageRectOffset = Vector2.new(IconData.xs[tonumber(code:sub(2, 2), B36) + 1], IconData.ys[tonumber(code:sub(3, 3), B36) + 1]),
		ImageRectSize = Vector2.new(cell, cell),
	}
	specs[code] = spec
	return spec
end

local function isRaw(value)
	if type(value) == "number" then return true end
	if type(value) ~= "string" then return false end
	return value:match("^rbxassetid://") or value:match("^rbxthumb://") or value:match("^rbxasset://")
		or value:match("^https?://") or value:match("^%d+$")
end

local function rawSpec(value)
	local text = tostring(value)
	if text:match("^%d+$") then text = "rbxassetid://" .. text end
	return { Image = text, ImageRectOffset = Vector2.zero, ImageRectSize = Vector2.zero }
end

-- (spec, known). Unknown names give the fallback glyph and known = false.
function Icons.resolve(value)
	if value == nil or value == "" then return nil, false end
	if isRaw(value) then return rawSpec(value), true end
	local code = codeFor(tostring(value))
	if code then return specFor(code), true end
	Icons.missing[tostring(value)] = true
	return specFor(codeFor(Icons.fallback)), false
end

-- Argon:GetIcon semantics: nil for unknown names, never the fallback.
function Icons.get(name)
	if name == nil then return nil end
	if isRaw(name) then return rawSpec(name) end
	local code = codeFor(tostring(name))
	if not code then return nil end
	local spec = specFor(code)
	return { Image = spec.Image, ImageRectOffset = spec.ImageRectOffset, ImageRectSize = spec.ImageRectSize }
end

function Icons.has(name)
	return Icons.get(name) ~= nil
end

-- Points an ImageLabel/ImageButton at an icon. Returns whether the icon was known.
function Icons.apply(image, value, scope, colorToken)
	local spec, known = Icons.resolve(value)
	if not spec then
		image.Image = ""
		return false
	end
	image.Image = spec.Image
	image.ImageRectOffset = spec.ImageRectOffset
	image.ImageRectSize = spec.ImageRectSize
	if colorToken then
		if scope and Token.isToken(colorToken) then
			image.ImageColor3 = Token.resolve(colorToken)
			scope:paint(image, "ImageColor3", colorToken)
		else
			image.ImageColor3 = colorToken
		end
	end
	return known
end

return Icons
