--!nocheck
-- The command palette (DESIGN_V2 7.5): Ctrl+K, "/", the sidebar search or gamepad Y. It
-- searches the registry, so controls in tabs that were never opened are found. Enter goes to
-- the control, Ctrl+Enter runs it in place, Left/Right adjust it in place. Built once per window.

local Env = require("core/Env")
local Util = require("core/Util")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Theme = require("theme/Theme")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Router = require("input/Router")
local Platform = require("input/Platform")
local VirtualList = require("layers/VirtualList")
local Popover = require("layers/Popover")

local T, F, TS = Token.T, Token.F, Token.TS
local Palette = {}

local ROW = 44
local ICONS = { Toggle = "zap", Button = "play", Slider = "sliders-horizontal", Stepper = "plus", Dropdown = "chevrons-up-down",
	Keybind = "keyboard", Input = "pencil", TextArea = "pencil", ColorPicker = "palette", Segmented = "menu", List = "menu" }

-- The value chip shown on a result.
local function valueText(element)
	local value = element.CurrentValue
	local kind = element.Type
	if kind == "Toggle" then return value and "On" or "Off" end
	if kind == "Dropdown" then
		local selection = element.CurrentOption or {}
		if #selection == 0 then return "None" end
		if #selection == 1 then return tostring(selection[1]) end
		return #selection .. " selected"
	end
	if kind == "Keybind" then return Util.keyName(element.CurrentKeybind) end
	if kind == "ColorPicker" and typeof(value) == "Color3" then
		return "#" .. string.format("%02X%02X%02X", math.floor(value.R * 255 + 0.5), math.floor(value.G * 255 + 0.5), math.floor(value.B * 255 + 0.5))
	end
	if kind == "Button" then return "" end
	if value == nil or type(value) == "table" then return "" end
	return Util.truncate(tostring(value), 14)
end

local function highlight(name, at, length)
	local escaped = function(text) return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
	if not at then return escaped(name) end
	return escaped(name:sub(1, at - 1)) .. "<b>" .. escaped(name:sub(at, at + length - 1)) .. "</b>" .. escaped(name:sub(at + length))
end

local function builtins(window)
	local Argon = window.Argon
	return {
		{ Name = "Switch theme…", Icon = "palette", Keywords = { "theme", "colour", "color", "dark", "light" }, Callback = function() window:ToggleThemePicker() end },
		{ Name = "Toggle material", Icon = "palette", Keywords = { "glass", "solid", "tinted", "clear" }, Callback = function()
			local order = { Solid = "Tinted", Tinted = "Clear", Clear = "Solid" }
			window:SetMaterial(order[Theme.materialFor()] or "Tinted")
		end },
		{ Name = "Reduce motion", Icon = "eye-off", Keywords = { "animation", "motion" }, Callback = function() window:SetReducedMotion(not Motion.reduced) end },
		{ Name = "Show keybind list", Icon = "keyboard", Keywords = { "overlay", "binds" }, Callback = function() window:ToggleKeybindList() end },
		{ Name = "Toggle watermark", Icon = "activity", Keywords = { "fps", "ping" }, Callback = function()
			window:SetWatermarkVisible(not window._overlays.enabled.Watermark)
		end },
		{ Name = "Save profile as…", Icon = "download", Keywords = { "config", "profile" }, Callback = function()
			window:Prompt({ Title = "Save profile", Placeholder = "Profile name", OnSubmit = function(name) Argon:SaveConfiguration(name) end })
		end },
		{ Name = "Open settings", Icon = "settings", Keywords = { "preferences", "options" }, Callback = function() require("feature/Settings").open(window) end },
		{ Name = "Hide UI", Icon = "eye-off", Keywords = { "close", "minimise" }, Callback = function() window:SetVisibility(false) end },
		{ Name = "Unload", Icon = "x", Keywords = { "destroy", "quit" }, Callback = function()
			window:Confirm({ Title = "Unload " .. window._title .. "?", ConfirmText = "Unload", OnConfirm = function() window:Destroy() end })
		end },
	}
end

local function build(window)
	local layers = window._layers
	local layer = layers:get("Modal")
	local scope = window._scope:child("palette")
	local state = { scope = scope, results = {}, highlight = 1, query = "", scoped = false, recent = {} }
	local root = Factory.new(scope, "Frame", { Name = "Palette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 }, layer)
	local scrim = Factory.new(scope, "TextButton", { Name = "Scrim", BackgroundColor3 = T.Scrim, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 10 }, root)
	local panel = Factory.new(scope, "Frame", { Name = "Panel", BackgroundColor3 = T.Raised, AnchorPoint = Vector2.new(0.5, 0), Active = true,
		Position = UDim2.new(0.5, 0, 0.18, 0), Size = UDim2.fromOffset(600, 400), ClipsDescendants = true, ZIndex = 11 }, root)
	Factory.corner(scope, panel, Metrics.radius.dialog)
	Popover.litEdge(scope, panel, 0.86)
	local uiscale = Factory.new(scope, "UIScale", { Scale = 1 }, panel)
	local searchIcon = Factory.new(scope, "ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(18, 17), ZIndex = 12 }, panel)
	Icons.apply(searchIcon, "search", scope, T.Text2)
	local box = Factory.text(scope, "TextBox", { Name = "Query", PlaceholderText = "Search settings and commands", FontFace = F.Body,
		TextSize = 15, ClearTextOnFocus = false, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -150, 0, 52), ZIndex = 12,
		PlaceholderColor3 = Theme.get("Dim") }, panel)
	local chip = Factory.text(scope, "TextButton", { Name = "Scope", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
		BackgroundColor3 = T.Active, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0, 26), Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 12, TextXAlignment = Enum.TextXAlignment.Center }, panel)
	Factory.corner(scope, chip, "full")
	Factory.padding(scope, chip, 10, 10, 0, 0)
	Factory.new(scope, "Frame", { BackgroundColor3 = T.BorderSoft, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 1), ZIndex = 12 }, panel)
	local listHost = Factory.new(scope, "Frame", { Name = "Results", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 58),
		Size = UDim2.new(1, -16, 1, -98), ZIndex = 12 }, panel)
	local empty = Factory.new(scope, "Frame", { Name = "Empty", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 90), Visible = false, ZIndex = 12 }, panel)
	local emptyIcon = Factory.new(scope, "ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0.5, -12, 0, 0), ZIndex = 12 }, empty)
	Icons.apply(emptyIcon, "search-x", scope, T.Text2)
	local emptyTitle = Factory.text(scope, "TextLabel", { Text = "", FontFace = F.Label, TextSize = TS.Label, Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 }, empty)
	Factory.text(scope, "TextLabel", { Text = "Try fewer letters, or search a tab name", FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Muted,
		Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 }, empty)
	local footer = Factory.text(scope, "TextLabel", { Name = "Footer", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Dim,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -8), Size = UDim2.new(1, -32, 0, 24), ZIndex = 12 }, panel)

	local function activate(index, mode) Palette._activate(window, state, index, mode) end
	local list = VirtualList.new(scope, {
		parent = listHost, rowHeight = ROW, overscan = 2, maxHeight = 320, zindex = 12,
		createRow = function(rowScope, parent)
			local row = Factory.new(rowScope, "TextButton", { Name = "Result", BackgroundColor3 = T.Hover, BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, ROW), ZIndex = 13 }, parent)
			Factory.corner(rowScope, row, 10)
			local plate = Factory.new(rowScope, "Frame", { BackgroundColor3 = T.Active, Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(12, 8), ZIndex = 14 }, row)
			Factory.corner(rowScope, plate, 8)
			local icon = Factory.new(rowScope, "ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(16, 16), ZIndex = 15 }, plate)
			local title = Factory.text(rowScope, "TextLabel", { FontFace = F.Body, TextSize = TS.Label, RichText = true, Position = UDim2.fromOffset(52, 4),
				Size = UDim2.new(1, -150, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14 }, row)
			local crumb = Factory.text(rowScope, "TextLabel", { FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted, Position = UDim2.fromOffset(52, 23),
				Size = UDim2.new(1, -150, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14 }, row)
			local value = Factory.text(rowScope, "TextLabel", { FontFace = F.Key, TextSize = TS.Key, BackgroundColor3 = T.Active, BackgroundTransparency = 0,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
				TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 14 }, row)
			Factory.corner(rowScope, value, 6)
			Factory.padding(rowScope, value, 8, 8, 0, 0)
			local entry = { Root = row, plate = plate, icon = icon, title = title, crumb = crumb, value = value }
			rowScope:connect(row.MouseButton1Click, function() if entry.index then activate(entry.index, "go") end end)
			rowScope:connect(row.MouseEnter, function()
				if entry.index then
					state.highlight = entry.index
					state.list:refreshVisible()
				end
			end)
			return entry
		end,
		bindRow = function(row, item, index)
			local on = index == state.highlight
			row.Root.BackgroundTransparency = on and 0 or 1
			row.plate.BackgroundColor3 = Theme.get(on and "AccentSoft" or "Active")
			if item.caption then
				row.title.Text = "<font size=\"12\">" .. item.caption .. "</font>"
				row.crumb.Text = ""
				row.value.Visible = false
				row.plate.Visible = false
				return
			end
			row.plate.Visible = true
			local element = item.el
			if element then
				Icons.apply(row.icon, element._cfg.Icon or ICONS[element.Type] or "circle", nil)
				row.title.Text = highlight(element.Name, item.at, #state.query)
				local section = element.Section and element.Section.Name or ""
				row.crumb.Text = (element._tab and element._tab.Name or "") .. (section ~= "" and (" › " .. section) or "")
				local text = valueText(element)
				row.value.Text = text
				row.value.Visible = text ~= ""
			else
				local command = item.command
				Icons.apply(row.icon, command.Icon or "command", nil)
				row.title.Text = highlight(command.Name, nil)
				row.crumb.Text = command.Description or "Command"
				row.value.Text = command.Shortcut or ""
				row.value.Visible = command.Shortcut ~= nil
			end
			row.icon.ImageColor3 = Theme.get(on and "AccentText" or "Text2")
		end,
	})
	state.list = list
	state.root, state.panel, state.box, state.chip, state.empty, state.emptyTitle, state.footer, state.uiscale = root, panel, box, chip, empty, emptyTitle, footer, uiscale
	scope:connect(scrim.MouseButton1Click, function() Palette.close(window) end)
	scope:connect(chip.MouseButton1Click, function()
		state.scoped = false
		Palette._search(window, state)
	end)
	scope:connect(box:GetPropertyChangedSignal("Text"), function()
		state.query = box.Text
		state.highlight = 1
		Palette._search(window, state)
	end)
	scope:connect(box.FocusLost, function(enter)
		if enter and root.Visible then
			local ctrl = Router.isDown(Enum.KeyCode.LeftControl) or Router.isDown(Enum.KeyCode.RightControl)
			activate(state.highlight, ctrl and "run" or "go")
		end
	end)
	return state
end

function Palette._search(window, state)
	local query = Util.trim(state.query)
	local items = {}
	local registry = window._registry
	local filter = nil
	if state.scoped and window.ActiveTab then
		local tab = window.ActiveTab
		filter = function(element) return element._tab == tab end
		state.chip.Text = "in " .. tab.Name .. "  ×"
	end
	state.chip.Visible = state.scoped == true
	if query == "" then
		if #state.recent > 0 then
			items[#items + 1] = { caption = "Recent" }
			for _, element in ipairs(state.recent) do
				if not element._destroyed then items[#items + 1] = { el = element } end
			end
		end
		items[#items + 1] = { caption = "Commands" }
		for _, command in ipairs(registry.commands) do items[#items + 1] = { command = command } end
		for _, command in ipairs(state.builtins) do items[#items + 1] = { command = command } end
	else
		local results = registry:search(query, 40, filter)
		if #results > 0 then
			if #results > 1 and results[1].score >= (results[2].score + 20) then
				items[#items + 1] = { caption = "Best match" }
				items[#items + 1] = results[1]
				table.remove(results, 1)
			end
			if #results > 0 then
				items[#items + 1] = { caption = "Settings" }
				for _, result in ipairs(results) do items[#items + 1] = result end
			end
		end
		local commands = registry:searchCommands(query)
		local extra = {}
		for _, command in ipairs(state.builtins) do extra[#extra + 1] = command end
		local saved = registry.commands
		registry.commands = extra
		local builtinHits = registry:searchCommands(query)
		registry.commands = saved
		if #commands + #builtinHits > 0 then
			items[#items + 1] = { caption = "Commands" }
			for _, hit in ipairs(commands) do items[#items + 1] = { command = hit.command } end
			for _, hit in ipairs(builtinHits) do items[#items + 1] = { command = hit.command } end
		end
	end
	state.items = items
	if items[state.highlight] and items[state.highlight].caption then state.highlight = math.min(#items, state.highlight + 1) end
	local empty = #items == 0
	state.empty.Visible = empty
	state.emptyTitle.Text = ("No matches for '%s'"):format(query)
	local height = state.list:setData(items)
	local panelHeight = 52 + 8 + math.max(empty and 110 or 0, height) + 40
	local area = window._layers:localSize()
	state.panel.Size = UDim2.fromOffset(math.min(600, area.X - 48), math.min(panelHeight, math.min(460, area.Y * 0.7)))
	local kind = Router.lastInputKind
	state.footer.Text = kind == "gamepad" and "A Go  ·  X Run  ·  ← → Adjust  ·  B Close"
		or (kind == "touch" and "Tap a result to jump to it  ·  Hold to run it in place"
		or "↵ Go  ·  Ctrl ↵ Run  ·  ← → Adjust  ·  Bksp Close")
end

local function selectable(items, index, step)
	local count = #items
	for _ = 1, count do
		index = ((index - 1 + step) % count) + 1
		if not items[index].caption then return index end
	end
	return index
end

function Palette._activate(window, state, index, mode)
	local item = state.items and state.items[index]
	if not item or item.caption then return end
	if item.command then
		Palette.close(window)
		Util.xcall(item.command.Callback, "Command " .. tostring(item.command.Name), nil)
		return
	end
	local element = item.el
	if not element or element._destroyed then return end
	window._registry:touch(element)
	table.insert(state.recent, 1, element)
	for i = #state.recent, 2, -1 do
		if state.recent[i] == element then table.remove(state.recent, i) end
	end
	while #state.recent > 5 do table.remove(state.recent) end
	if mode == "run" then
		if not element:_inactive() then
			if element.Type == "Toggle" then element:Set(not element.CurrentValue)
			elseif element._press then element:_press()
			elseif element._spec.focus and element._spec.focus.activate then element._spec.focus.activate(element) end
		end
		state.list:refreshVisible()
		return
	end
	Palette.close(window)
	window:SelectTab(element._tab)
	element:_ensureMounted()
	if window._focus then window._focus:pulse(element) end
	local section = element.Section
	if section and section._hoverRow then
		section:_hoverRow(element, true)
		task.delay(0.6, function() section:_hoverRow(element, false) end)
	end
end

function Palette.open(window, query)
	if window._options.Palette == false or window._destroyed then return end
	local state = window._palette
	if not state then
		state = build(window)
		state.builtins = builtins(window)
		window._palette = state
	end
	if state.root.Visible then
		if query then state.box.Text = tostring(query) end
		return state
	end
	window._layers:closeAll("tab")
	state.root.Visible = true
	state.box.Text = query and tostring(query) or ""
	state.query = state.box.Text
	state.highlight = 1
	Palette._search(window, state)
	if not Motion.reduced then
		state.uiscale.Scale = 0.96
		Motion.tween(state.uiscale, "dialogIn", { Scale = 1 })
	end
	if Platform.preferred() ~= "touch" then pcall(function() state.box:CaptureFocus() end) end
	state.entry = { kind = "palette", id = "palette", close = function() Palette.close(window, true) end }
	window._layers:push(state.entry)
	state.consumer = Router.layerKey(function(input)
		local key = input.KeyCode and input.KeyCode.Name
		local items = state.items or {}
		if key == "Down" or key == "DPadDown" then
			state.highlight = selectable(items, state.highlight, 1)
			state.list:scrollTo(state.highlight)
			return true
		elseif key == "Up" or key == "DPadUp" then
			state.highlight = selectable(items, state.highlight, -1)
			state.list:scrollTo(state.highlight)
			return true
		elseif key == "Left" or key == "Right" or key == "DPadLeft" or key == "DPadRight" then
			local item = items[state.highlight]
			local element = item and item.el
			if element and element._spec.focus and element._spec.focus.adjust and not element:_inactive() then
				local shift = Router.isDown(Enum.KeyCode.LeftShift)
				local step = (key == "Left" or key == "DPadLeft") and -1 or 1
				element._spec.focus.adjust(element, shift and step * 10 or step)
				state.list:refreshVisible()
				return true
			end
			return false
		elseif key == "Tab" then
			state.scoped = not state.scoped
			Palette._search(window, state)
			return true
		elseif key == "ButtonA" then
			Palette._activate(window, state, state.highlight, "go")
			return true
		elseif key == "ButtonX" then
			Palette._activate(window, state, state.highlight, "run")
			return true
		elseif key == "Backspace" and state.box.Text == "" then
			Palette.close(window)
			return true
		end
		return false
	end, 95, true)
	return state
end

function Palette.close(window, fromStack)
	local state = window._palette
	if not state or not state.root.Visible then return end
	state.root.Visible = false
	if not fromStack then window._layers:pop(state.entry) end
	if state.consumer then state.consumer.remove() state.consumer = nil end
	pcall(function() state.box:ReleaseFocus() end)
end

return Palette
