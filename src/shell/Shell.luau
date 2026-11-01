--!nocheck
-- The window's instance tree (DESIGN_V2 section 3): a glass frame with the sidebar, an opaque
-- sheet inset into it with the topbar, the section chip rail, the page host and the table of
-- contents, plus the responsive layouts. Built once, unparented, at its final size.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Metrics = require("theme/Metrics")
local Theme = require("theme/Theme")
local Icons = require("icons/Icons")
local Drag = require("input/Drag")
local Platform = require("input/Platform")
local Popover = require("layers/Popover")

local T, F, TS, M = Token.T, Token.F, Token.TS, Token.M
local Shell = {}

local TABBAR = 64
local tabSheets = setmetatable({}, { __mode = "k" })

local function icon(scope, parent, name, size, color, props)
	local image = Factory.new(scope, "ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	if props then Factory.apply(scope, image, props) end
	Icons.apply(image, name, scope, color or T.Text2)
	return image
end
Shell.icon = icon

local function iconButton(scope, parent, name, iconName, size)
	local button = Factory.new(scope, "ImageButton", {
		Name = name,
		BackgroundColor3 = T.Text,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size or 32, size or 32),
	}, parent)
	Factory.corner(scope, button, 8)
	local glyph = icon(scope, button, iconName, 18, T.Text2, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Name = "Glyph",
	})
	scope:connect(button.MouseEnter, function() button.BackgroundTransparency = 0.94 end)
	scope:connect(button.MouseLeave, function() button.BackgroundTransparency = 1 end)
	return button, glyph
end
Shell.iconButton = iconButton

-- The default logo: the window name's first letter on an accent plate (no library branding).
function Shell.logo(scope, parent, window, size)
	local plate = Factory.new(scope, "Frame", {
		Name = "Logo",
		BackgroundColor3 = T.Accent,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	Factory.corner(scope, plate, math.floor(size * 0.28))
	local image = Factory.new(scope, "ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, plate)
	Factory.corner(scope, image, math.floor(size * 0.28))
	local letter = Factory.text(scope, "TextLabel", {
		Name = "Letter",
		FontFace = F.LoaderTitle,
		TextSize = math.floor(size * 0.5),
		TextColor3 = T.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, plate)
	local entry = { plate = plate, image = image, letter = letter }
	window._logos[#window._logos + 1] = entry
	Shell.renderLogo(window, entry)
	return plate
end

function Shell.renderLogo(window, entry)
	local value = window._logo
	local text = tostring(value or "")
	local raw = (type(value) == "number") or text:match("^rbxassetid://") or text:match("^rbxthumb://") or text:match("^rbxasset://") or text:match("^%d+$")
	if raw then
		entry.image.Image = text:match("^%d+$") and ("rbxassetid://" .. text) or text
		entry.image.Visible = true
		entry.letter.Visible = false
		entry.plate.BackgroundTransparency = 1
	else
		entry.image.Visible = false
		entry.letter.Visible = true
		entry.plate.BackgroundTransparency = 0
		local name = tostring(window._title or "A")
		entry.letter.Text = (name:match("[%w]") or "A"):upper()
	end
end

-- ---------- build ----------
function Shell.build(window)
	local scope = window._shellScope
	local layers = window._layers
	local base = layers:get("Base")
	window.Shadow = Popover.shadow(scope, base, 1, 0.35)
	window.Shadow.Name = "Shadow"
	local main = Factory.new(scope, "Frame", {
		Name = "ArgonWindow",
		BackgroundColor3 = T.Frame,
		BackgroundTransparency = M.Frame,
		Active = true,
		Visible = false,
		ZIndex = 2,
	})
	window._mainCorner = Factory.corner(scope, main, Metrics.radius.window)
	Factory.new(scope, "UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.94, 0.94, 0.94)),
	}, main)
	window._mainEdge = Popover.litEdge(scope, main, 0.84)
	window._mainScale = Factory.new(scope, "UIScale", { Scale = 1 }, main)
	window.Main = main

	-- sidebar (glass: Text and Text2 only)
	local sidebar = Factory.new(scope, "Frame", {
		Name = "Sidebar",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, Metrics.SIDEBAR, 1, 0),
		ZIndex = 2,
	}, main)
	Factory.corner(scope, sidebar, Metrics.radius.window)
	Factory.new(scope, "Frame", {
		Name = "SquareEdge",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 16, 1, 0),
	}, sidebar)
	window.Sidebar = sidebar

	local brand = Factory.new(scope, "TextButton", {
		Name = "Brand",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 40),
	}, sidebar)
	local logo = Shell.logo(scope, brand, window, 28)
	logo.Position = UDim2.fromOffset(4, 6)
	window._brandName = Factory.text(scope, "TextLabel", {
		Name = "Title",
		Text = window._title,
		FontFace = F.Brand,
		TextSize = TS.Brand,
		Position = UDim2.fromOffset(42, 3),
		Size = UDim2.new(1, -48, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, brand)
	window._brandSub = Factory.text(scope, "TextLabel", {
		Name = "Subtitle",
		Text = window._subtitle,
		FontFace = F.Caption,
		TextSize = TS.Caption,
		TextColor3 = T.Text2,
		Position = UDim2.fromOffset(42, 22),
		Size = UDim2.new(1, -48, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, brand)
	window._brand = brand
	scope:connect(brand.MouseButton1Click, function() window:_openAccountMenu(brand) end)

	local search = Factory.new(scope, "TextButton", {
		Name = "SearchTrigger",
		BackgroundColor3 = T.Text,
		BackgroundTransparency = 0.94,
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 0, 36),
	}, sidebar)
	Factory.corner(scope, search, Metrics.radius.nav)
	window._searchIcon = icon(scope, search, "search", 16, T.Text2, { Position = UDim2.fromOffset(10, 10) })
	window._searchLabel = Factory.text(scope, "TextLabel", {
		Text = "Search",
		FontFace = F.Body,
		TextSize = TS.Body,
		TextColor3 = T.Text2,
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -90, 1, 0),
	}, search)
	window._searchKeys = Factory.text(scope, "TextLabel", {
		Text = "Ctrl K",
		FontFace = F.Key,
		TextSize = TS.Key,
		TextColor3 = T.Text2,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 50, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, search)
	scope:connect(search.MouseButton1Click, function() window:OpenPalette() end)
	scope:connect(search.MouseEnter, function() search.BackgroundTransparency = 0.92 end)
	scope:connect(search.MouseLeave, function() search.BackgroundTransparency = 0.94 end)
	window._searchTrigger = search

	local nav = Factory.new(scope, "ScrollingFrame", {
		Name = "Nav",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 106),
		Size = UDim2.new(1, -24, 1, -170),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = T.Track,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, sidebar)
	window._navLayout = Factory.list(scope, nav, { Padding = UDim.new(0, 2) })
	window.TabList = nav

	-- the one shared selection indicator
	local indicator = Factory.new(scope, "Frame", {
		Name = "Indicator",
		BackgroundColor3 = T.Text,
		BackgroundTransparency = 0.9,
		Size = UDim2.new(1, 0, 0, Metrics.get("nav")),
		Visible = false,
		ZIndex = 1,
	}, nav)
	Env.try(indicator, "LayoutOrder", -1)
	Factory.corner(scope, indicator, Metrics.radius.nav)
	local bar = Factory.new(scope, "Frame", {
		Name = "Bar",
		BackgroundColor3 = T.White,
		Size = UDim2.fromOffset(3, 16),
		Position = UDim2.new(0, 0, 0.5, -8),
		ZIndex = 2,
	}, indicator)
	Factory.corner(scope, bar, 2)
	Factory.new(scope, "UIGradient", { Rotation = 90, Color = Token.seq("AccentHi", "Accent") }, bar)
	window._indicator = indicator
	window._indicatorBar = bar

	local profile = Factory.new(scope, "TextButton", {
		Name = "Profile",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(1, -24, 0, 40),
	}, sidebar)
	local avatar = Factory.new(scope, "ImageLabel", {
		Name = "Avatar",
		BackgroundColor3 = T.Active,
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.fromOffset(28, 28),
	}, profile)
	Factory.corner(scope, avatar, "full")
	local player = Env.localPlayer()
	if player then
		-- rbxthumb loads asynchronously in the engine; nothing yields here.
		avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(tonumber(player.UserId) or 0)
	end
	window._profileName = Factory.text(scope, "TextLabel", {
		Text = player and tostring(player.DisplayName or player.Name) or "Player",
		FontFace = F.Body, TextSize = TS.Body, Position = UDim2.fromOffset(42, 4), Size = UDim2.new(1, -48, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, profile)
	window._profileHandle = Factory.text(scope, "TextLabel", {
		Text = player and ("@" .. tostring(player.Name)) or "",
		FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2, Position = UDim2.fromOffset(42, 21), Size = UDim2.new(1, -48, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, profile)
	scope:connect(profile.MouseButton1Click, function() window:_openAccountMenu(profile) end)
	window._profile = profile

	-- the opaque sheet
	local content = Factory.new(scope, "Frame", {
		Name = "Content",
		BackgroundColor3 = T.Sheet,
		BackgroundTransparency = M.Sheet,
		Active = true,
		ZIndex = 3,
	}, main)
	Factory.corner(scope, content, Metrics.radius.sheet)
	window._sheetEdge = Popover.litEdge(scope, content, 0.9)
	window.Content = content

	local topbar = Factory.new(scope, "Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Metrics.TOPBAR),
		ZIndex = 4,
		Active = true,
	}, content)
	window.TopBar = topbar
	window._crumbGroup = Factory.text(scope, "TextLabel", {
		Name = "Group", Text = "", FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Text2,
		Position = UDim2.fromOffset(20, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5, Visible = false,
	}, topbar)
	window._crumbTitle = Factory.text(scope, "TextLabel", {
		Name = "Title", Text = "", FontFace = F.Label, TextSize = TS.Label,
		Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -220, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5,
	}, topbar)
	local actions = Factory.new(scope, "Frame", {
		Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5,
	}, topbar)
	Factory.list(scope, actions, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center })
	local status = Factory.new(scope, "Frame", {
		Name = "Status", BackgroundColor3 = T.InfoSoft, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1, Visible = false,
	}, actions)
	Factory.corner(scope, status, "full")
	Factory.padding(scope, status, 10, 10, 0, 0)
	window._statusDot = Factory.new(scope, "Frame", { BackgroundColor3 = T.Info, Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 0, 0.5, -3) }, status)
	Factory.corner(scope, window._statusDot, "full")
	window._statusText = Factory.text(scope, "TextLabel", {
		Text = "", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2, Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
	}, status)
	window._statusChip = status
	local bell, bellGlyph = iconButton(scope, actions, "Bell", "bell")
	bell.LayoutOrder = 2
	window._bellDot = Factory.new(scope, "Frame", { Name = "Unread", BackgroundColor3 = T.Danger, Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(20, 6), Visible = false, ZIndex = 6 }, bell)
	Factory.corner(scope, window._bellDot, "full")
	scope:connect(bell.MouseButton1Click, function() window:_openInbox(bell) end)
	window._bell = bell
	local themeButton = iconButton(scope, actions, "ThemeButton", "palette")
	themeButton.LayoutOrder = 3
	scope:connect(themeButton.MouseButton1Click, function() window:ToggleThemePicker() end)
	window._themeButton = themeButton
	local minimise = iconButton(scope, actions, "Minimise", "minus")
	minimise.LayoutOrder = 4
	scope:connect(minimise.MouseButton1Click, function() window:SetVisibility(false) end)
	window._minimise = minimise
	window._topRule = Factory.new(scope, "Frame", { Name = "Rule", BackgroundColor3 = T.BorderSoft, Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1), Visible = false, ZIndex = 5 }, topbar)

	-- section chip rail (every layout; the TOC is extra on wide windows)
	local rail = Factory.new(scope, "Frame", {
		Name = "JumpRail", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, Metrics.TOPBAR),
		Size = UDim2.new(1, 0, 0, 40), Visible = false, ZIndex = 4,
	}, content)
	local strip = Factory.new(scope, "ScrollingFrame", {
		Name = "Chips", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 4), Size = UDim2.new(1, -40, 0, 32),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X, ZIndex = 4,
	}, rail)
	Factory.list(scope, strip, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center })
	window._jumpRail = rail
	window._jumpStrip = strip

	local pageHost = Factory.new(scope, "Frame", {
		Name = "PageHost", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, Metrics.TOPBAR),
		Size = UDim2.new(1, 0, 1, -Metrics.TOPBAR), ClipsDescendants = true, ZIndex = 3,
	}, content)
	window.PageHost = pageHost
	window._pageVeil = Factory.new(scope, "Frame", {
		Name = "PageVeil", BackgroundColor3 = T.Sheet, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Visible = false,
	}, pageHost)

	local toc = Factory.new(scope, "Frame", {
		Name = "TOC", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, Metrics.TOPBAR + 24),
		Size = UDim2.new(0, 160, 1, -(Metrics.TOPBAR + 40)), Visible = false, ZIndex = 4,
	}, content)
	Factory.list(scope, toc, { Padding = UDim.new(0, 2) })
	Factory.text(scope, "TextLabel", { Name = "Caption", Text = "On this page", FontFace = F.Caption, TextSize = TS.Caption,
		TextColor3 = T.Text2, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0 }, toc)
	window._toc = toc

	local hint = Factory.new(scope, "Frame", { Name = "HintBar", BackgroundColor3 = T.Sheet, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 40), Visible = false, ZIndex = 8 }, content)
	window._hintText = Factory.text(scope, "TextLabel", { Text = "", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
		Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 9 }, hint)
	window._hintBar = hint

	local grip = Factory.new(scope, "TextButton", {
		Name = "ResizeGrip", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(16, 16), ZIndex = 20,
	}, main)
	window._grip = grip
	window._veil = Factory.new(scope, "Frame", {
		Name = "Veil", BackgroundColor3 = T.Frame, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Visible = false,
	}, main)
	Factory.corner(scope, window._veil, Metrics.radius.window)

	Shell.wireDrag(window, topbar, brand, grip)
	scope:connect(main.MouseEnter, function() window._pointerInside = true end)
	scope:connect(main.MouseLeave, function() window._pointerInside = false end)
	for _, tab in ipairs(window.Tabs) do Shell.navItem(window, tab) end
end

-- ---------- drag and resize ----------
function Shell.wireDrag(window, topbar, brand, grip)
	local scope = window._shellScope
	local function startMove(input)
		local kind = input.UserInputType and input.UserInputType.Name
		if kind ~= "MouseButton1" and kind ~= "Touch" then return end
		local start = window.Main.Position
		local origin = Vector2.new(input.Position.X, input.Position.Y)
		local scale = window._layers.scale
		Drag.begin(input, {
			threshold = 6,
			onMove = function(position)
				local delta = (position - origin) / scale
				window:_moveTo(UDim2.new(start.X.Scale, start.X.Offset + delta.X, start.Y.Scale, start.Y.Offset + delta.Y))
			end,
			onEnd = function() window:_rememberGeometry() end,
		})
	end
	scope:connect(topbar.InputBegan, startMove)
	scope:connect(brand.InputBegan, startMove)
	scope:connect(grip.InputBegan, function(input)
		local kind = input.UserInputType and input.UserInputType.Name
		if kind ~= "MouseButton1" and kind ~= "Touch" then return end
		local startSize = window.Main.Size
		local origin = Vector2.new(input.Position.X, input.Position.Y)
		local scale = window._layers.scale
		Drag.begin(input, {
			onMove = function(position)
				local delta = (position - origin) / scale
				window:SetSize(Vector2.new(startSize.X.Offset + delta.X, startSize.Y.Offset + delta.Y))
			end,
			onEnd = function() window:_rememberGeometry() end,
		})
	end)
end

-- ---------- nav ----------
function Shell.navItem(window, tab)
	if rawget(tab, "TabButton") then return end
	local scope = window._shellScope
	local nav = window.TabList
	if tab.Group and not window._groupCaptions[tab.Group] then
		window._navOrder += 1
		window._groupCaptions[tab.Group] = Factory.text(scope, "TextLabel", {
			Name = "Group", Text = tostring(tab.Group), FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2,
			Size = UDim2.new(1, 0, 0, 24), LayoutOrder = window._navOrder, TextYAlignment = Enum.TextYAlignment.Bottom,
		}, nav)
	end
	window._navOrder += 1
	local height = Metrics.get("nav")
	local button = Factory.new(scope, "TextButton", {
		Name = "Tab",
		BackgroundColor3 = T.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = window._navOrder,
		ZIndex = 2,
	}, nav)
	Factory.corner(scope, button, Metrics.radius.nav)
	local box = Factory.new(scope, "Frame", { Name = "IconBox", BackgroundColor3 = T.Active, BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0.5, -9), Size = UDim2.fromOffset(18, 18), ZIndex = 3 }, button)
	local glyph = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, box)
	Icons.apply(glyph, tab.IconName, nil)
	local title = Factory.text(scope, "TextLabel", {
		Name = "Title", Text = tab.Name, FontFace = F.Nav, TextSize = TS.Nav, TextColor3 = T.Text2,
		Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -72, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
	}, button)
	tab.TabButton = button
	tab.IconBox = box
	tab.Icon = glyph
	tab.ButtonTitle = title
	tab.Accent = window._indicatorBar
	scope:connect(button.MouseButton1Click, function() window:SelectTab(tab) end)
	scope:connect(button.MouseEnter, function()
		if window.ActiveTab ~= tab then button.BackgroundTransparency = 0.94 end
		tab:_enqueue(2)
	end)
	scope:connect(button.MouseLeave, function() button.BackgroundTransparency = 1 end)
	Shell.renderNav(window, tab)
	Shell.renderBadge(window, tab)
	Shell.renderTabBar(window, false)
end

function Shell.renderNav(window, tab)
	local title = rawget(tab, "ButtonTitle")
	if not title then return end
	local active = window.ActiveTab == tab
	title.Text = tab.Name
	title.TextColor3 = Theme.get(active and "Text" or "Text2")
	title.FontFace = Token.resolve(active and F.NavSelected or F.Nav)
	tab.Icon.ImageColor3 = Theme.get(active and "Text" or "Text2")
end

function Shell.renderBadge(window, tab)
	local button = rawget(tab, "TabButton")
	if not button then return end
	local value = tab._badge
	local badge = rawget(tab, "Count")
	if value == nil or value == false then
		if badge then badge.Visible = false end
		return
	end
	if not badge then
		local scope = window._shellScope
		badge = Factory.text(scope, "TextLabel", {
			Name = "Badge", FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.AccentText, BackgroundColor3 = T.AccentSoft,
			BackgroundTransparency = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(20, 18), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
		}, button)
		Factory.corner(scope, badge, "full")
		Factory.padding(scope, badge, 6, 6, 0, 0)
		tab.Count = badge
	end
	badge.Visible = true
	if value == true then
		badge.Text = ""
		badge.Size = UDim2.fromOffset(6, 6)
		badge.BackgroundColor3 = Theme.get("Accent")
	else
		badge.Text = tostring(value)
		badge.Size = UDim2.fromOffset(20, 18)
		badge.BackgroundColor3 = Theme.get("AccentSoft")
	end
end

-- Moves the shared indicator to the selected item.
function Shell.moveIndicator(window, animated)
	Shell.renderTabBar(window, animated)
	local tab = window.ActiveTab
	local indicator = window._indicator
	local button = tab and rawget(tab, "TabButton")
	if not indicator or not button then return end
	indicator.Visible = true
	local nav = window.TabList
	local scale = window._layers.scale
	local y = (button.AbsolutePosition.Y - nav.AbsolutePosition.Y) / scale + nav.CanvasPosition.Y
	local target = UDim2.new(0, 0, 0, math.floor(y))
	indicator.Size = UDim2.new(1, 0, 0, button.Size.Y.Offset)
	Motion.spring(indicator, "Position", target, "snappy", animated)
	if window._glow then
		window._glow:acquire(2, "nav", window._indicatorBar, { transparency = 0.6, spread = 6 })
	end
end

-- ---------- section chips and the table of contents ----------
function Shell.refreshRail(window)
	local strip = window._jumpStrip
	if not strip then return end
	local scope = window._railScope
	if scope then scope:destroy() end
	scope = window._shellScope:child("rail")
	window._railScope = scope
	local tab = window.ActiveTab
	local sections = tab and tab._sections or {}
	local show = #sections >= 3 and not window._jumpFiltered
	window._jumpRail.Visible = show
	strip.CanvasPosition = Vector2.new(0, 0)
	Shell.layoutContent(window)
	window._chips = {}
	window._tocItems = {}
	for _, child in ipairs(window._toc:GetChildren()) do
		if child.Name == "Item" then child:Destroy() end
	end
	if not tab then return end
	for index, section in ipairs(sections) do
		if show then
			local chip = Factory.text(scope, "TextButton", {
				Name = "Chip", Text = section.Name, FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Text2,
				BackgroundColor3 = T.Active, BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 28), LayoutOrder = index, TextXAlignment = Enum.TextXAlignment.Center,
			}, strip)
			Factory.corner(scope, chip, "full")
			Factory.padding(scope, chip, 12, 12, 0, 0)
			scope:connect(chip.MouseButton1Click, function() window:_scrollToSection(section) end)
			window._chips[index] = chip
		end
		if window._layoutName == "wide" and #sections >= 2 then
			local item = Factory.text(scope, "TextButton", {
				Name = "Item", Text = section.Name, FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Text2,
				Size = UDim2.new(1, 0, 0, 28), LayoutOrder = index, TextTruncate = Enum.TextTruncate.AtEnd,
			}, window._toc)
			Factory.padding(scope, item, 10, 0, 0, 0)
			scope:connect(item.MouseButton1Click, function() window:_scrollToSection(section) end)
			window._tocItems[index] = item
		end
	end
	window._toc.Visible = window._layoutName == "wide" and #sections >= 2
	Shell.scrollSpy(window)
end

-- Marks the section at the top of the page in the chips and the TOC.
function Shell.scrollSpy(window)
	local tab = window.ActiveTab
	if not tab or not tab._skeleton then return end
	local page = tab.Page
	local current = 1
	for index, section in ipairs(tab._sections) do
		local root = rawget(section, "Root")
		if root and root.AbsolutePosition.Y - page.AbsolutePosition.Y <= 40 then current = index end
	end
	for index, chip in pairs(window._chips or {}) do
		local on = index == current
		chip.BackgroundTransparency = on and 0 or 1
		chip.TextColor3 = Theme.get(on and "Text" or "Text2")
	end
	for index, item in pairs(window._tocItems or {}) do
		item.TextColor3 = Theme.get(index == current and "Text" or "Text2")
	end
	window._topRule.Visible = page.CanvasPosition.Y > 4
end

-- ---------- layout ----------
-- Decides the layout from the window and GUI size (DESIGN_V2 3.6) and sizes the parts.
function Shell.layout(window)
	local main = rawget(window, "Main")
	if not main then return end
	local gui = window._layers:localSize()
	local width = main.Size.X.Offset
	local phone = Platform.isPhone(window._layers:guiSize())
	local layout
	if phone and gui.X < 600 then
		layout = "portrait"
	elseif phone then
		layout = "landscape"
	elseif width < 760 or window._sidebarCollapsed then
		layout = "rail"
	elseif width >= 1080 then
		layout = "wide"
	else
		layout = "standard"
	end
	local changed = window._layoutName ~= layout
	window._layoutName = layout
	local rail = layout == "rail" or layout == "landscape"
	local portrait = layout == "portrait"
	local side = portrait and 0 or (rail and Metrics.RAIL or Metrics.SIDEBAR)
	window.Sidebar.Visible = not portrait
	window.Sidebar.Size = UDim2.new(0, side, 1, 0)
	window._brandName.Visible = not rail
	window._brandSub.Visible = not rail
	window._searchLabel.Visible = not rail
	window._searchKeys.Visible = not rail
	window._searchTrigger.Size = rail and UDim2.fromOffset(40, 40) or UDim2.new(1, -24, 0, 36)
	window._profileName.Visible = not rail
	window._profileHandle.Visible = not rail
	window.TabList.Position = UDim2.fromOffset(rail and 10 or 12, 106)
	window.TabList.Size = UDim2.new(1, rail and -20 or -24, 1, -170)
	for _, tab in ipairs(window.Tabs) do
		local title = rawget(tab, "ButtonTitle")
		if title then title.Visible = not rail end
	end
	local inset = portrait and 0 or Metrics.INSET
	if portrait then Shell.ensureTabBar(window) end
	if window._tabBar then window._tabBar.Visible = portrait end
	window.Content.Position = UDim2.fromOffset(side, inset)
	window.Content.Size = UDim2.new(1, -(side + inset), 1, -inset * 2 - (portrait and TABBAR or 0))
	window._mainCorner.CornerRadius = UDim.new(0, portrait and Metrics.radius.phone or Metrics.radius.window)
	local inner = width - side - inset
	window._themeButton.Visible = window._themePickerEnabled ~= false and inner >= 300
	window._statusChip.Visible = window._statusText.Text ~= "" and inner >= 560
	Shell.layoutContent(window)
	if changed then Shell.refreshRail(window) end
	Shell.moveIndicator(window, false)
end

-- Page host below the topbar (and the chip rail), with room for the TOC on wide windows.
function Shell.layoutContent(window)
	local railVisible = window._jumpRail and window._jumpRail.Visible
	local top = Metrics.TOPBAR + (railVisible and 40 or 0)
	local wide = window._layoutName == "wide"
	local tocVisible = wide and window.ActiveTab and #window.ActiveTab._sections >= 2
	local hint = window._hintBar and window._hintBar.Visible and 40 or 0
	window.PageHost.Position = UDim2.fromOffset(0, top)
	window.PageHost.Size = UDim2.new(1, tocVisible and -184 or 0, 1, -(top + hint))
	for _, tab in ipairs(window.Tabs) do
		if tab._columnLimit then tab._columnLimit.MaxSize = Vector2.new(tocVisible and 600 or 680, math.huge) end
	end
end

local function captionWidth(text)
	local service = Env.services.TextService
	local ok, bounds = pcall(function() return service:GetTextSize(text, 13, Enum.Font.Gotham, Vector2.new(400, 30)) end)
	return ok and bounds.X or #text * 7
end

-- Topbar breadcrumb and status chip.
function Shell.renderTopbar(window)
	local tab = window.ActiveTab
	local group = tab and tab.Group
	window._crumbGroup.Visible = group ~= nil
	window._crumbGroup.Text = group and (tostring(group) .. "  ›") or ""
	window._crumbTitle.Text = tab and tab.Name or ""
	window._crumbTitle.Position = UDim2.fromOffset(group and (28 + captionWidth(window._crumbGroup.Text)) or 20, 0)
end

local TONES = { success = { "SuccessSoft", "Success" }, warning = { "WarningSoft", "Warning" }, danger = { "DangerSoft", "Danger" },
	info = { "InfoSoft", "Info" }, neutral = { "Active", "Text2" } }

function Shell.setStatus(window, text, tone)
	local chip = window._statusChip
	if not chip then return end
	local colors = TONES[tostring(tone or "info"):lower()] or TONES.info
	window._statusText.Text = text and tostring(text) or ""
	chip.BackgroundColor3 = Theme.get(colors[1])
	window._statusDot.BackgroundColor3 = Theme.get(colors[2])
	window._statusTone = colors
	chip.Visible = text ~= nil and text ~= ""
end

function Shell.restyle(window)
	if not rawget(window, "Main") then return end
	local light = Theme.isLight()
	local hc = Theme.name == "HighContrast"
	for _, edge in ipairs({ window._mainEdge, window._sheetEdge }) do
		edge.Color = Theme.get(hc and "White" or (light and "Border" or "White"))
		local gradient = edge:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Enabled = not light and not hc end
	end
	window._mainEdge.Transparency = hc and 0 or (light and 0.4 or 0.84)
	window._sheetEdge.Transparency = hc and 0 or (light and 0.6 or 0.9)
	if window._statusTone then
		window._statusChip.BackgroundColor3 = Theme.get(window._statusTone[1])
		window._statusDot.BackgroundColor3 = Theme.get(window._statusTone[2])
	end
	for _, tab in ipairs(window.Tabs) do
		Shell.renderNav(window, tab)
		Shell.renderBadge(window, tab)
	end
	for _, entry in ipairs(window._logos) do Shell.renderLogo(window, entry) end
	Shell.renderTabBar(window, false)
	Shell.scrollSpy(window)
end

-- ---------- phone portrait: bottom tab bar (DESIGN_V2 3.6) ----------
-- Up to five tabs, or four plus More, which lists every tab on a bottom sheet. Built only the
-- first time the window is laid out in portrait.
function Shell.ensureTabBar(window)
	if window._tabBar then return window._tabBar end
	local scope = window._shellScope
	local bar = Factory.new(scope, "Frame", {
		Name = "TabBar", BackgroundColor3 = T.Frame, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, TABBAR), Visible = false, ZIndex = 8,
	}, window.Main)
	Factory.corner(scope, bar, Metrics.radius.phone)
	Factory.new(scope, "Frame", { Name = "SquareEdge", BackgroundColor3 = T.Frame, Size = UDim2.new(1, 0, 0, Metrics.radius.phone), ZIndex = 8 }, bar)
	Factory.new(scope, "Frame", { Name = "Edge", BackgroundColor3 = T.Border, Size = UDim2.new(1, 0, 0, 1), ZIndex = 9 }, bar)
	local pill = Factory.new(scope, "Frame", { Name = "Pill", BackgroundColor3 = T.AccentSoft, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 0, 0, 8), Size = UDim2.fromOffset(56, 28), Visible = false, ZIndex = 9 }, bar)
	Factory.corner(scope, pill, "full")
	window._tabBar = bar
	window._tabBarPill = pill
	window._tabBarSlots = {}
	return bar
end

local function tabBarSlot(window, index)
	local slots = window._tabBarSlots
	if slots[index] then return slots[index] end
	local scope = window._shellScope
	local button = Factory.new(scope, "TextButton", { Name = "Slot", BackgroundTransparency = 1, Size = UDim2.new(0.2, 0, 1, 0), ZIndex = 10 }, window._tabBar)
	local glyph = Factory.new(scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(24, 24), ZIndex = 11 }, button)
	local label = Factory.text(scope, "TextLabel", { Name = "Label", FontFace = F.Caption, TextSize = 12, TextColor3 = T.Text2,
		Position = UDim2.fromOffset(2, 40), Size = UDim2.new(1, -4, 0, 16), TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 }, button)
	local slot = { Root = button, Icon = glyph, Label = label }
	scope:connect(button.MouseButton1Click, function()
		if slot.tab then window:SelectTab(slot.tab) else Shell.openTabSheet(window, button) end
	end)
	slots[index] = slot
	return slot
end

function Shell.renderTabBar(window, animated)
	local bar = window._tabBar
	if not bar or not bar.Visible then return end
	local tabs = window.Tabs
	local more = #tabs > 5
	local shown = more and 4 or #tabs
	local total = shown + (more and 1 or 0)
	local activeIndex = window.ActiveTab and table.find(tabs, window.ActiveTab)
	local selected = activeIndex and (activeIndex <= shown and activeIndex or (more and total)) or nil
	for index = 1, total do
		local slot = tabBarSlot(window, index)
		local tab = index <= shown and tabs[index] or nil
		slot.tab = tab
		slot.Root.Visible = true
		slot.Root.Size = UDim2.new(1 / total, 0, 1, 0)
		slot.Root.Position = UDim2.fromScale((index - 1) / total, 0)
		Icons.apply(slot.Icon, tab and tab.IconName or "ellipsis", nil)
		slot.Icon.ImageColor3 = Theme.get(index == selected and "AccentText" or "Text2")
		slot.Label.Text = tab and tab.Name or "More"
		slot.Label.TextColor3 = Theme.get(index == selected and "Text" or "Text2")
	end
	for index = total + 1, #window._tabBarSlots do window._tabBarSlots[index].Root.Visible = false end
	local pill = window._tabBarPill
	pill.Visible = selected ~= nil
	if selected then
		Motion.spring(pill, "Position", UDim2.new((selected - 0.5) / total, 0, 0, 8), "snappy", animated)
	end
end

-- The More sheet: every tab, the selected one filled.
function Shell.openTabSheet(window, anchor)
	local host = window._popover
	if host:isOpen("tabsheet") then
		host:close("toggle")
		return
	end
	host:open({
		owner = "tabsheet", anchor = anchor, reuse = "tabsheet", name = "TabSheet", width = 320, maxHeight = 480, sheetOnPhone = true,
		build = function(frame, scope)
			local list = Factory.new(scope, "ScrollingFrame", { Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ZIndex = 5 }, frame)
			Factory.list(scope, list, { Padding = UDim.new(0, 2) })
			Factory.padding(scope, list, 6, 6, 6, 6)
			tabSheets[frame] = { scope = scope, list = list, rows = {} }
			return Vector2.new(320, 200)
		end,
		bind = function(frame)
			local sheet = tabSheets[frame]
			for index, tab in ipairs(window.Tabs) do
				local row = sheet.rows[index]
				if not row then
					local button = Factory.new(sheet.scope, "TextButton", { Name = "Tab", BackgroundColor3 = T.Hover, BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 48), LayoutOrder = index, ZIndex = 6 }, sheet.list)
					Factory.corner(sheet.scope, button, Metrics.radius.hover)
					local glyph = Factory.new(sheet.scope, "ImageLabel", { Name = "Icon", BackgroundTransparency = 1,
						Position = UDim2.new(0, 12, 0.5, -10), Size = UDim2.fromOffset(20, 20), ZIndex = 7 }, button)
					local label = Factory.text(sheet.scope, "TextLabel", { Name = "Title", FontFace = F.Nav, TextSize = TS.Nav,
						Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -52, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 7 }, button)
					row = { Root = button, Icon = glyph, Label = label }
					sheet.rows[index] = row
					sheet.scope:connect(button.MouseButton1Click, function()
						host:close("pick")
						if row.tab then window:SelectTab(row.tab) end
					end)
				end
				row.tab = tab
				row.Root.Visible = true
				local active = tab == window.ActiveTab
				Icons.apply(row.Icon, tab.IconName, nil)
				row.Icon.ImageColor3 = Theme.get(active and "AccentText" or "Text2")
				row.Label.Text = tab.Name
				row.Root.BackgroundTransparency = active and 0 or 1
			end
			for index = #window.Tabs + 1, #sheet.rows do sheet.rows[index].Root.Visible = false end
			return Vector2.new(320, math.min(480, #window.Tabs * 50 + 12))
		end,
	})
end

return Shell
