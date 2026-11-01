--!nocheck
-- Sizes, radii, spacing, density and the window and interface-scale rules (DESIGN_V2 2.7-2.8, 3.2).

local Token = require("core/Token")

local Metrics = {}
Metrics.density = "Default"
Metrics.version = 0

local DENSITY = {
	Compact = { padV = 8, padH = 14, row = 36, rowDesc = 48, control = 28, switchW = 40, switchH = 22, knob = 16, sliderHit = 24, thumb = 14, hit = 28, nav = 32, sectionGap = 20, header = 28, listRow = 32 },
	Default = { padV = 10, padH = 16, row = 44, rowDesc = 56, control = 32, switchW = 44, switchH = 24, knob = 18, sliderHit = 28, thumb = 16, hit = 32, nav = 36, sectionGap = 24, header = 32, listRow = 36 },
	Touch = { padV = 12, padH = 16, row = 52, rowDesc = 64, control = 40, switchW = 52, switchH = 30, knob = 24, sliderHit = 40, thumb = 22, hit = 44, nav = 44, sectionGap = 24, header = 36, listRow = 52 },
	Gamepad = { padV = 12, padH = 16, row = 48, rowDesc = 60, control = 36, switchW = 48, switchH = 28, knob = 22, sliderHit = 32, thumb = 18, hit = 44, nav = 44, sectionGap = 24, header = 36, listRow = 44 },
}
Metrics.DENSITY = DENSITY

-- role = { compact/default size, touch/gamepad size }
local TEXT = {
	Page = { 22, 22 }, Dialog = { 18, 18 }, Section = { 14, 14 }, Brand = { 15, 15 }, LoaderTitle = { 16, 16 },
	Label = { 14, 15 }, Button = { 14, 14 }, Nav = { 14, 15 }, NavSelected = { 14, 15 }, Body = { 13, 14 },
	Caption = { 12, 12 }, Status = { 13, 13 }, Value = { 13, 14 }, Stat = { 26, 26 }, Key = { 12, 12 },
	Strong = { 13, 14 }, Input = { 14, 14 }, Small = { 12, 12 },
}

Metrics.radius = {
	window = 20, phone = 24, sheet = 14, platter = 14, hover = 10, card = 20, dialog = 18, popover = 14,
	control = 10, control28 = 8, segment = 8, keycap = 6, chip = 6, checkbox = 6, swatch = 6, nav = 10,
}

Metrics.SIDEBAR, Metrics.RAIL, Metrics.TOPBAR, Metrics.INSET = 232, 64, 52, 6
Metrics.MIN_W, Metrics.MIN_H = 560, 400

function Metrics.get(key)
	return (DENSITY[Metrics.density] or DENSITY.Default)[key]
end

function Metrics.textSize(role)
	local spec = TEXT[role] or TEXT.Body
	local large = Metrics.density == "Touch" or Metrics.density == "Gamepad"
	return large and spec[2] or spec[1]
end

function Metrics.setDensity(name)
	if not DENSITY[name] or Metrics.density == name then return false end
	Metrics.density = name
	Metrics.version += 1
	return true
end

-- Row height for a label-only row ("row") or a row with a description ("rowDesc").
function Metrics.rowHeight(kind)
	return Metrics.get(kind == "tall" and "rowDesc" or "row")
end

-- DESIGN_V2 section 3.2.
function Metrics.windowDefault(gui)
	local width = math.max(math.min(gui.X - 160, 1080), math.min(720, gui.X - 16))
	local height = math.max(math.min(gui.Y - 110, 700), math.min(440, gui.Y - 16))
	return Vector2.new(math.floor(width), math.floor(height))
end

-- v1 SetSize clamps.
function Metrics.clampSize(gui, width, height)
	local maxW, maxH = math.max(360, math.min(1200, gui.X - 20)), math.max(340, math.min(820, gui.Y - 20))
	local minW, minH = math.max(360, math.min(560, gui.X - 20)), math.max(340, math.min(400, gui.Y - 20))
	return Vector2.new(math.clamp(width, math.min(minW, maxW), maxW), math.clamp(height, math.min(minH, maxH), maxH))
end

-- "auto" interface scale: 1 on ordinary screens, growing on tall (4K) GUIs, capped at 1.5.
function Metrics.autoScale(gui)
	if gui.Y < 1300 then return 1 end
	return math.floor(math.clamp(gui.Y / 1080, 1, 1.5) * 20 + 0.5) / 20
end

Token.setResolvers({
	size = function(role) return Metrics.textSize(role) end,
})

return Metrics
