--!nocheck
-- The Appearance popover behind the topbar palette button (DESIGN_V2 7.8): theme cards drawn
-- in each theme's real colours with a live preview on hover (window-local, no Theme.changed),
-- the accent override, material, interface scale, density, state labels and reduced motion.
-- Built once per window. v1 seam kept: Window.ThemePicker.ThemeOptions.<ThemeName>.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Theme = require("theme/Theme")
local Color = require("theme/Color")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Prefs = require("persist/Prefs")

local T, F, TS = Token.T, Token.F, Token.TS
local ThemePicker = {}

local ACCENTS = { "9970FF", "58A6FF", "38BDD0", "34D399", "F7BE4F", "FF8A4C", "F472B6", "FF657C" }
local ORDER = { "Argon", "Amethyst", "Midnight", "Emerald", "Rose", "Slate", "Ember", "Nord", "Mono", "Ocean", "Daylight", "HighContrast" }
local WIDTH = 380

local function orderedThemes()
	local seen, out = {}, {}
	for _, name in ipairs(ORDER) do
		if Theme.themes[name] then out[#out + 1] = name seen[name] = true end
	end
	for _, name in ipairs(Theme.list()) do
		if not seen[name] then out[#out + 1] = name end
	end
	return out
end

-- A mini window in the theme's real colours (not painted: previews never follow the live theme).
local function themeCard(scope, parent, name, index)
	local palette = Theme.themes[name]
	local card = Factory.new(scope, "TextButton", { Name = name, BackgroundColor3 = palette.Frame, LayoutOrder = index })
	Factory.corner(scope, card, 10)
	local stroke = Factory.new(scope, "UIStroke", { Thickness = 2, Color = palette.Accent, Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local sheet = Factory.new(scope, "Frame", { Name = "Sheet", BackgroundColor3 = palette.Sheet, Position = UDim2.fromOffset(16, 4),
		Size = UDim2.new(1, -20, 0, 44) }, card)
	Factory.corner(scope, sheet, 6)
	for row = 0, 1 do
		local bar = Factory.new(scope, "Frame", { Name = "Surface", BackgroundColor3 = palette.Surface, Position = UDim2.fromOffset(6, 6 + row * 16),
			Size = UDim2.new(1, -12, 0, 12) }, sheet)
		Factory.corner(scope, bar, 3)
		Factory.new(scope, "Frame", { Name = "Text", BackgroundColor3 = palette.Text2, Position = UDim2.fromOffset(4, 5),
			Size = UDim2.new(0.45, 0, 0, 2) }, bar)
	end
	local accent = Factory.new(scope, "Frame", { Name = "Accent", BackgroundColor3 = palette.Accent, Position = UDim2.new(1, -26, 1, -12),
		Size = UDim2.fromOffset(18, 6) }, card)
	Factory.corner(scope, accent, "full")
	local label = Factory.text(scope, "TextLabel", { Name = "ThemeName", Text = name == "HighContrast" and "High contrast" or name,
		FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2, Position = UDim2.new(0, 0, 1, 4), Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, card)
	return { card = card, stroke = stroke, label = label }
end

local function segmented(scope, parent, label, options, current, onPick, order)
	local row = Factory.new(scope, "Frame", { Name = label, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order }, parent)
	Factory.text(scope, "TextLabel", { Text = label, FontFace = F.Label, TextSize = TS.Body, Size = UDim2.new(0.4, 0, 1, 0) }, row)
	local track = Factory.new(scope, "Frame", { Name = "Track", BackgroundColor3 = T.Well, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.6, 0, 0, 30) }, row)
	Factory.corner(scope, track, Metrics.radius.control)
	Factory.padding(scope, track, 3, 3, 3, 3)
	Factory.list(scope, track, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2) })
	local buttons = {}
	local function render(value)
		for option, button in pairs(buttons) do
			local on = option == value
			button.BackgroundTransparency = on and 0 or 1
			button.TextColor3 = Theme.get(on and "AccentText" or "Text2")
		end
	end
	for index, option in ipairs(options) do
		local button = Factory.text(scope, "TextButton", { Text = option, FontFace = F.Button, TextSize = TS.Caption, TextColor3 = T.Text2,
			BackgroundColor3 = T.AccentSoft, BackgroundTransparency = 1, Size = UDim2.new(1 / #options, -2, 1, 0), LayoutOrder = index,
			TextXAlignment = Enum.TextXAlignment.Center }, track)
		Factory.corner(scope, button, Metrics.radius.segment)
		buttons[option] = button
		scope:connect(button.MouseButton1Click, function()
			onPick(option)
			render(option)
		end)
	end
	render(current)
	return { row = row, render = render, buttons = buttons }
end

local function build(window, frame, scope)
	local layout = Factory.list(scope, frame, { Padding = UDim.new(0, 10) })
	Factory.padding(scope, frame, 16, 16, 14, 14)
	Factory.text(scope, "TextLabel", { Name = "Heading", Text = "Appearance", FontFace = F.Section, TextSize = TS.Section,
		Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0 }, frame)
	local options = Factory.new(scope, "Frame", { Name = "ThemeOptions", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, frame)
	Factory.new(scope, "UIGridLayout", { CellSize = UDim2.fromOffset(80, 52), CellPadding = UDim2.fromOffset(9, 26),
		SortOrder = Enum.SortOrder.LayoutOrder }, options)
	Factory.padding(scope, options, 0, 0, 0, 22)
	local state = { cards = {}, scope = scope, options = options }
	window._themePickerContent = state

	local function hover(name, on)
		state.hoverToken = (state.hoverToken or 0) + 1
		local token = state.hoverToken
		if on then
			task.delay(0.08, function()
				if state.hoverToken ~= token or not window._popover:isOpen("theme") then return end
				local palette = Theme.themes[name]
				if not palette then return end
				Theme.withPalette(palette, function() window:_previewRepaint() end)
			end)
		else
			task.delay(0.08, function()
				if state.hoverToken ~= token then return end
				window:_previewRepaint()
			end)
		end
	end

	function state.rebuild()
		if state.cardScope then state.cardScope:destroy() end
		local cardScope = scope:child("cards")
		state.cardScope = cardScope
		state.cards = {}
		for index, name in ipairs(orderedThemes()) do
			local entry = themeCard(cardScope, options, name, index)
			entry.card.Parent = options
			cardScope:connect(entry.card.MouseButton1Click, function()
				state.hoverToken = (state.hoverToken or 0) + 1
				window:SetTheme(name)
			end)
			cardScope:connect(entry.card.MouseEnter, function() hover(name, true) end)
			cardScope:connect(entry.card.MouseLeave, function() hover(name, false) end)
			state.cards[name] = entry
		end
		ThemePicker.restyle(window)
	end
	state.rebuild()
	scope:connect(Theme.listChanged, function() state.rebuild() end)

	-- accent row
	local accentRow = Factory.new(scope, "Frame", { Name = "Accent", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 2 }, frame)
	Factory.list(scope, accentRow, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center })
	local function swatch(color, text, onPick, order)
		local button = Factory.text(scope, "TextButton", { Text = text or "", FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Text,
			BackgroundColor3 = color or T.Active, Size = UDim2.fromOffset(22, 22), LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Center }, accentRow)
		Factory.corner(scope, button, Metrics.radius.swatch)
		scope:connect(button.MouseButton1Click, onPick)
		return button
	end
	swatch(T.Accent, "A", function() window.Argon:SetAccent(nil) end, 0)
	for index, hex in ipairs(ACCENTS) do
		swatch(Color.hex(hex), nil, function() window.Argon:SetAccent(Color.hex(hex)) end, index)
	end
	swatch(nil, "+", function()
		window:Prompt({ Title = "Custom accent", Content = "A hex colour such as #9970FF.", Placeholder = "#9970FF",
			Validate = function(text) return Color.hex(text) ~= nil, "Use six hex digits" end,
			OnSubmit = function(text) window.Argon:SetAccent(Color.hex(text)) end })
	end, 20)

	state.material = segmented(scope, frame, "Material", { "Solid", "Tinted", "Clear" }, Theme.materialFor(), function(value)
		window:SetMaterial(value)
	end, 3)
	local scalePct = math.floor((window:GetScale() or 1) * 100 + 0.5)
	state.scale = segmented(scope, frame, "Scale", { "90%", "100%", "115%", "130%" }, scalePct .. "%", function(value)
		window:SetScale(tonumber(value:match("%d+")) / 100)
	end, 4)
	state.density = segmented(scope, frame, "Density", { "Auto", "Compact", "Touch" }, Prefs.get("Density") or "Auto", function(value)
		window:SetDensity(value:lower())
	end, 5)
	state.labels = segmented(scope, frame, "State labels", { "Auto", "Always", "Off" }, Prefs.get("StateLabels") or "Auto", function(value)
		Prefs.set("StateLabels", value)
		for _, tab in ipairs(window.Tabs) do tab:_repaint() end
	end, 6)
	state.motion = segmented(scope, frame, "Reduce motion", { "Off", "On" }, Motion.reduced and "On" or "Off", function(value)
		window:SetReducedMotion(value == "On")
	end, 7)
	local more = Factory.text(scope, "TextButton", { Name = "More", Text = "More in Settings ›", FontFace = F.Caption, TextSize = TS.Caption,
		TextColor3 = T.AccentText, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 8, TextXAlignment = Enum.TextXAlignment.Right }, frame)
	scope:connect(more.MouseButton1Click, function()
		window._popover:close("settings")
		require("feature/Settings").open(window)
	end)
	local _ = layout
	return Vector2.new(WIDTH, 0)
end

local function contentHeight(window)
	local count = #orderedThemes()
	local rows = math.ceil(count / 4)
	return 14 + 20 + 10 + rows * 78 + 10 + 26 + 10 + 5 * 42 + 20 + 14
end

function ThemePicker.prebuild(window)
	if window._themePickerFrame then return window._themePickerFrame end
	local content = window._popover:prebuild({
		reuse = "theme",
		name = "ThemePicker",
		build = function(frame, scope) return build(window, frame, scope) end,
	})
	window._themePickerFrame = content.frame
	window.ThemePicker = content.frame
	return content.frame
end

function ThemePicker.toggle(window)
	if window._themePickerEnabled == false then return false end
	window:_ensureShell()
	local button = window._themeButton
	if not button or not button.Visible then return false end
	local host = window._popover
	if host:isOpen("theme") then
		host:close("toggle")
		return false
	end
	ThemePicker.prebuild(window)
	host:open({
		owner = "theme", anchor = button, reuse = "theme", name = "ThemePicker", width = WIDTH, maxHeight = 640, sheetOnPhone = true,
		bind = function()
			ThemePicker.restyle(window)
			return Vector2.new(WIDTH, contentHeight(window))
		end,
		onClose = function()
			window:_previewRepaint()
		end,
	})
	return true
end

function ThemePicker.setVisible(window, visible)
	window._themePickerEnabled = visible ~= false
	window:_ensureShell()
	if window._themeButton then
		window._themeButton.Visible = window._themePickerEnabled
	end
	if not window._themePickerEnabled and window._popover:isOpen("theme") then window._popover:close("hidden") end
	return window._themePickerEnabled
end

function ThemePicker.restyle(window)
	local state = window._themePickerContent
	if not state then return end
	for name, entry in pairs(state.cards) do
		local active = name == Theme.name
		local palette = Theme.themes[name]
		entry.stroke.Color = palette and palette.Accent or Theme.get("Accent")
		entry.stroke.Transparency = active and 0 or 1
		entry.label.TextColor3 = Theme.get(active and "Text" or "Text2")
	end
	if state.material then state.material.render(Theme.materialFor()) end
end

return ThemePicker
