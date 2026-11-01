--!nocheck
-- The live palette, derivation of missing tokens, validation, the theme generator, the accent
-- override, materials and the switch protocol (ARCHITECTURE_V2 section 5.2-5.3).

local Signal = require("core/Signal")
local Token = require("core/Token")
local Color = require("theme/Color")
local Palettes = require("theme/Palettes")

local Theme = {}

Theme.palette = {}
Theme.name = "Argon"
Theme.version = 0
Theme.themes = {}
Theme.changed = Signal.new("Theme.changed")
Theme.listChanged = Signal.new("Theme.listChanged")
Theme.accent = nil
Theme.materialName = nil -- nil = default for the theme

local ORDER = Palettes.ORDER
local ALIASES = Palettes.ALIASES
local KNOWN = Palettes.KNOWN
local WHITE, BLACK = Color.WHITE, Color.BLACK
local contrast, mix, stepUntil = Color.contrast, Color.mix, Color.stepUntil

for _, name in ipairs(Palettes.NAMES) do
	Theme.themes[name] = Palettes.decode(name)
end

local function copyInto(target, source)
	for _, token in ipairs(ORDER) do target[token] = source[token] end
	Palettes.withAliases(target)
	return target
end
copyInto(Theme.palette, Theme.themes.Argon)

function Theme.isLight(p)
	return Color.isLight((p or Theme.palette).Sheet)
end

-- ---------- derivation ----------
local function deriveAccent(p, given, light)
	if not given.AccentHi then p.AccentHi = mix(p.Accent, light and BLACK or WHITE, 0.35) end
	if not given.AccentDeep then p.AccentDeep = mix(p.Accent, light and WHITE or BLACK, 0.35) end
	if light and not given.AccentHi then p.AccentHi = mix(p.Accent, BLACK, 0.12) end
	if not given.AccentText then
		p.AccentText = stepUntil(p.Accent, light and BLACK or WHITE, p.Surface, 6)
	end
	if not given.OnAccent then
		local ink = mix(p.Frame, BLACK, 0.4)
		local function worst(c) return math.min(contrast(c, p.Accent), contrast(c, p.AccentHi)) end
		local best = worst(ink) >= worst(WHITE) and ink or WHITE
		p.OnAccent = best
		local guard = 0
		while worst(best) < 4.5 and guard < 30 and not given.AccentHi do
			p.AccentHi = mix(p.AccentHi, p.Accent, 0.1)
			guard += 1
		end
	end
	if not given.AccentSoft then p.AccentSoft = mix(p.Surface, p.Accent, 0.16) end
	if not given.Focus then
		p.Focus = stepUntil(light and p.AccentDeep or p.AccentHi, light and BLACK or WHITE, p.Sheet, 3)
	end
end

-- Fills every token the partial palette leaves out (DESIGN_V2 section 2.5). Host-given tokens
-- are never adjusted. Tokens derived from a host-given source are recomputed.
function Theme.derive(partial, baseName)
	local base = Theme.themes[baseName or "Argon"] or Theme.themes.Argon
	local given = {}
	for key, value in pairs(partial or {}) do
		if typeof(value) == "Color3" then
			local token = ALIASES[key] or key
			if KNOWN[token] then
				-- Background outranks Sidebar for Frame (both alias it)
				if not (key == "Sidebar" and partial.Background) then given[token] = value end
			end
		end
	end
	local p = {}
	for _, token in ipairs(ORDER) do p[token] = given[token] or base[token] end
	if partial and typeof(partial.Window) == "Color3" and not given.Frame and not partial.Background and not partial.Sidebar then
		p.Frame = Color.shiftL(partial.Window, -0.25)
	end
	local light = Color.isLight(p.Sheet)
	local dirty = table.clone(given)
	local function needs(token, ...)
		if given[token] then return false end
		for index = 1, select("#", ...) do
			if dirty[select(index, ...)] then dirty[token] = true return true end
		end
		return false
	end
	if needs("Surface", "Sheet") then p.Surface = stepUntil(p.Sheet, light and BLACK or WHITE, p.Sheet, 1.15) end
	if needs("Hover", "Surface") then p.Hover = stepUntil(p.Surface, light and BLACK or WHITE, p.Surface, 1.12) end
	if needs("Active", "Surface") then p.Active = stepUntil(p.Surface, light and BLACK or WHITE, p.Surface, 1.26) end
	if needs("Raised", "Sheet") then p.Raised = stepUntil(p.Sheet, light and BLACK or WHITE, p.Sheet, 1.22) end
	if needs("Well", "Frame") then p.Well = mix(p.Frame, BLACK, 0.25) end
	if needs("Track", "Surface", "Text") then p.Track = stepUntil(mix(p.Surface, p.Text, 0.2), p.Text, p.Surface, 1.6) end
	if needs("Border", "Surface") then p.Border = stepUntil(p.Surface, light and BLACK or WHITE, p.Surface, 1.4) end
	if needs("BorderSoft", "Surface") then p.BorderSoft = stepUntil(p.Surface, light and BLACK or WHITE, p.Surface, 1.18) end
	if needs("Text2", "Text", "Surface") then p.Text2 = stepUntil(mix(p.Text, p.Surface, 0.22), p.Text, p.Surface, 9) end
	if needs("Muted", "Surface", "Text") then p.Muted = stepUntil(p.Muted, p.Text, p.Surface, 4.8) end
	if needs("Dim", "Surface", "Text", "Well") then
		p.Dim = stepUntil(stepUntil(p.Dim, p.Text, p.Surface, 3.5), p.Text, p.Well, 4.5)
	end
	if needs("Disabled", "Surface", "Muted") then p.Disabled = mix(p.Surface, p.Muted, 0.42) end
	for _, status in ipairs({ "Success", "Warning", "Danger", "Info" }) do
		if needs(status, "Surface") then p[status] = stepUntil(p[status], light and BLACK or WHITE, p.Surface, 4.5) end
		if needs(status .. "Soft", status, "Surface") then p[status .. "Soft"] = mix(p.Surface, p[status], 0.15) end
	end
	if needs("AccentAlt", "Info") then p.AccentAlt = p.Info end
	if needs("OnStatus", "Frame", "Sheet") then p.OnStatus = light and WHITE or mix(p.Frame, BLACK, 0.4) end
	local accentDirty = dirty.Accent or dirty.Surface or dirty.Sheet or dirty.Frame or dirty.AccentHi or dirty.AccentDeep
	if accentDirty then deriveAccent(p, given, light) end
	return Palettes.withAliases(p)
end

-- ---------- validation ----------
local TARGETS = {
	{ "Text", "Surface", 10 }, { "Text2", "Surface", 9 }, { "Muted", "Surface", 4.8 },
	{ "Muted", "Hover", 4.5 }, { "Muted", "Raised", 4.5 }, { "Dim", "Surface", 3.5 }, { "Dim", "Well", 4.5 },
	{ "AccentText", "Surface", 4.6 }, { "OnAccent", "Accent", 4.5 }, { "OnAccent", "AccentHi", 4.5 },
	{ "Success", "Surface", 4.5 }, { "Warning", "Surface", 4.5 }, { "Danger", "Surface", 4.5 }, { "Info", "Surface", 4.5 },
	{ "Focus", "Sheet", 3 }, { "Focus", "Surface", 3 }, { "Track", "Surface", 1.6 }, { "Border", "Surface", 1.4 },
	{ "Surface", "Sheet", 1.08 }, { "Hover", "Surface", 1.06 },
}
Theme.TARGETS = TARGETS

function Theme.validate(p)
	local issues = {}
	for _, check in ipairs(TARGETS) do
		local a, b = p[check[1]], p[check[2]]
		if a and b then
			local ratio = contrast(a, b)
			if ratio + 1e-6 < check[3] then
				issues[#issues + 1] = { token = check[1], against = check[2], ratio = ratio, target = check[3] }
			end
		end
	end
	return { ok = #issues == 0, issues = issues }
end

function Theme.contrast(a, b)
	return contrast(a, b)
end

-- ---------- registry ----------
function Theme.list()
	local names = {}
	for name in pairs(Theme.themes) do
		if name ~= "Custom" then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

function Theme.add(name, partial)
	assert(type(name) == "string" and name ~= "", "AddTheme expects a theme name")
	assert(type(partial) == "table", "AddTheme expects a palette table")
	local palette = Theme.derive(partial)
	Theme.themes[name] = palette
	Theme.listChanged:Fire()
	return palette
end

local NEUTRALS = {
	cool = Color3.fromRGB(70, 90, 140),
	warm = Color3.fromRGB(140, 95, 70),
	neutral = Color3.fromRGB(110, 110, 110),
}

-- Generates a complete palette from an accent (Theme generator, DESIGN section 8.9).
function Theme.create(spec)
	spec = spec or {}
	local mode = string.lower(tostring(spec.Mode or "dark"))
	local contrast = string.lower(tostring(spec.Contrast or ""))
	local baseName = mode == "light" and "Daylight" or (contrast == "high" and "HighContrast" or "Argon")
	local base = Theme.themes[baseName]
	local tint = NEUTRALS[string.lower(tostring(spec.Neutral or "cool"))] or NEUTRALS.cool
	local partial = {}
	if baseName == "Argon" then
		for _, token in ipairs({ "Frame", "Sheet", "Surface", "Hover", "Active", "Raised", "Well", "Track", "Border", "BorderSoft" }) do
			partial[token] = mix(base[token], tint, 0.05)
		end
	end
	partial.Accent = typeof(spec.Accent) == "Color3" and spec.Accent or base.Accent
	local palette = Theme.derive(partial, baseName)
	if spec.Name then
		Theme.themes[tostring(spec.Name)] = palette
		Theme.listChanged:Fire()
	end
	return palette
end

local function resolveName(name)
	name = Palettes.RENAMES[name] or name
	local palette = Theme.themes[name]
	if palette then return palette, name end
	local rayfield = Palettes.RAYFIELD[name]
	if rayfield then
		palette = Theme.create(rayfield)
		Theme.themes[name] = palette
		return palette, name
	end
	return nil, name
end

local function applyAccent(p)
	if not Theme.accent then return end
	p.Accent = Theme.accent
	deriveAccent(p, {}, Color.isLight(p.Sheet))
	Palettes.withAliases(p)
end

local function publish()
	Theme.version += 1
	Theme.changed:Fire(Theme.palette, Theme.name)
end

-- Switches the live palette. A table is derived and registered as "Custom".
function Theme.set(value)
	local palette, name
	if type(value) == "table" then
		palette = Theme.derive(value)
		name = "Custom"
		Theme.themes.Custom = palette
	else
		palette, name = resolveName(tostring(value))
		if not palette then return false, "Unknown theme: " .. tostring(value) end
	end
	Theme.name = name
	copyInto(Theme.palette, palette)
	applyAccent(Theme.palette)
	publish()
	return true
end

-- Overrides the accent on top of any theme; nil returns to the theme's own accent.
function Theme.setAccent(color)
	Theme.accent = typeof(color) == "Color3" and color or nil
	local base = Theme.themes[Theme.name] or Theme.themes.Argon
	copyInto(Theme.palette, base)
	applyAccent(Theme.palette)
	publish()
end

local MATERIALS = {
	Solid = { Frame = 0, Sheet = 0, Dock = 0, HUD = 0 },
	Tinted = { Frame = 0.14, Sheet = 0, Dock = 0.06, HUD = 0.10 },
	Clear = { Frame = 0.25, Sheet = 0.06, Dock = 0.12, HUD = 0.18 },
}

function Theme.materialFor(p)
	if Theme.name == "HighContrast" then return "Solid" end
	local chosen = Theme.materialName
	if chosen and MATERIALS[chosen] then return chosen end
	return Color.isLight((p or Theme.palette).Sheet) and "Solid" or "Tinted"
end

function Theme.setMaterial(name)
	if not MATERIALS[name] then return false end
	Theme.materialName = name
	publish()
	return true
end

-- Background transparency of a material layer under the current material.
Theme.hudOverride = nil
function Theme.material(layer)
	local value = MATERIALS[Theme.materialFor()][layer] or 0
	if layer == "HUD" and Theme.hudOverride then return Theme.hudOverride end
	return value
end

-- ---------- token resolution and window-local preview ----------
local preview = nil
local SPECIAL = {
	White = WHITE,
	Black = BLACK,
}

function Theme.get(name)
	local p = preview or Theme.palette
	local value = p[name]
	if value then return value end
	local token = ALIASES[name]
	if token then return p[token] end
	if name == "Scrim" then return Color.shiftL(p.Frame, -0.4) end
	if name == "Shadow" then return BLACK end
	return SPECIAL[name]
end

-- Runs fn with token resolution bound to palette p (theme picker hover preview).
function Theme.withPalette(p, fn)
	local previous = preview
	preview = p
	local ok, err = pcall(fn)
	preview = previous
	if not ok then warn("[Argon UI] theme preview failed: " .. tostring(err)) end
end

Token.setResolvers({
	color = function(name)
		return Theme.get(name) or (preview or Theme.palette).Text
	end,
	material = function(layer)
		return Theme.material(layer)
	end,
	seq = function(names)
		local colors = {}
		for name in names:gmatch("[^|]+") do colors[#colors + 1] = Theme.get(name) or WHITE end
		if #colors == 1 then colors[2] = colors[1] end
		local points = {}
		for index, color in ipairs(colors) do
			local t = #colors == 3 and ({ 0, 0.55, 1 })[index] or (index - 1) / (#colors - 1)
			points[index] = ColorSequenceKeypoint.new(t, color)
		end
		return ColorSequence.new(points)
	end,
})

return Theme
