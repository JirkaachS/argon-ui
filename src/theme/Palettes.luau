--!nocheck
-- The 12 built-in palettes, decoded from the generated PaletteData, plus the v1 key aliases.

local PaletteData = require("theme/PaletteData")
local Color = require("theme/Color")

local Palettes = {}

Palettes.ORDER = PaletteData.order
Palettes.NAMES = PaletteData.names

-- v1 key -> v2 token. Every palette carries both, so v1 reads keep working.
Palettes.ALIASES = {
	Background = "Frame",
	Sidebar = "Frame",
	Window = "Sheet",
	Input = "Well",
	AccentLight = "AccentHi",
	AccentDark = "AccentDeep",
}

Palettes.KNOWN = {}
for _, token in ipairs(PaletteData.order) do Palettes.KNOWN[token] = true end

function Palettes.withAliases(palette)
	for alias, token in pairs(Palettes.ALIASES) do palette[alias] = palette[token] end
	return palette
end

function Palettes.decode(name)
	local packed = PaletteData.themes[name]
	if not packed then return nil end
	local palette = {}
	local index = 0
	for hex in packed:gmatch("%x+") do
		index += 1
		palette[PaletteData.order[index]] = Color.hex(hex)
	end
	return Palettes.withAliases(palette)
end

-- Rayfield theme names that Argon has no palette for, generated on first use.
Palettes.RAYFIELD = {
	Default = { Accent = Color3.fromRGB(0, 146, 214), Neutral = "cool" },
	AmberGlow = { Accent = Color3.fromRGB(255, 172, 66), Neutral = "warm" },
	Bloom = { Accent = Color3.fromRGB(244, 114, 182), Neutral = "warm" },
	DarkBlue = { Accent = Color3.fromRGB(70, 130, 255), Neutral = "cool" },
	Green = { Accent = Color3.fromRGB(52, 211, 120), Neutral = "neutral" },
	Serenity = { Accent = Color3.fromRGB(125, 168, 255), Neutral = "cool" },
}
Palettes.RENAMES = { Light = "Daylight", ["High contrast"] = "HighContrast", ["High Contrast"] = "HighContrast" }

return Palettes
