--!nocheck
-- Notifications (DESIGN_V2 7.6): typed, pooled, updatable cards with actions and a timer that
-- pauses on hover, at most 4 on screen (older ones go to the inbox), the same Id updating in
-- place, identical text coalescing to "x2", plus the Undo pill, callback-error toasts and the
-- copy sheet used when the executor has no clipboard. A toast shown before any window exists
-- lands on a small standalone ScreenGui (D19).

local Env = require("core/Env")
local Util = require("core/Util")
local Token = require("core/Token")
local Scope = require("core/Scope")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Theme = require("theme/Theme")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Prefs = require("persist/Prefs")
local Platform = require("input/Platform")
local Popover = require("layers/Popover")

local T, F, TS = Token.T, Token.F, Token.TS
local Toast = {}
local Host = {}
Host.__index = Host

local WIDTH, MAX_VISIBLE, POOL = 340, 4, 5
local TYPES = {
	info = { icon = "info", color = "Info", soft = "InfoSoft" },
	success = { icon = "circle-check", color = "Success", soft = "SuccessSoft" },
	warning = { icon = "triangle-alert", color = "Warning", soft = "WarningSoft" },
	error = { icon = "circle-x", color = "Danger", soft = "DangerSoft" },
	loading = { icon = "loader-circle", color = "Accent", soft = "AccentSoft" },
}
local ALIASES = { danger = "error", fail = "error", failed = "error", warn = "warning", ok = "success", done = "success" }

-- v1 title guess, by whole words, with a guard for "no errors" style titles.
local function guessType(title)
	local text = " " .. string.lower(tostring(title or "")):gsub("[^%w]+", " ") .. " "
	if text:find(" no errors? ") or text:find(" without errors? ") then return "success" end
	if text:find(" errors? ") or text:find(" failed ") or text:find(" failure ") then return "error" end
	if text:find(" warn") or text:find(" wait ") or text:find(" waiting ") then return "warning" end
	if text:find(" success") or text:find(" complete") or text:find(" saved ") or text:find(" done ") then return "success" end
	return "info"
end
Toast.guessType = guessType

local function autoDuration(options, kind, text)
	local duration = options.Duration
	if duration == false or duration == math.huge or kind == "loading" then return math.huge end
	if type(duration) ~= "number" or duration <= 0 then
		duration = math.clamp(2.5 + 0.06 * #text, 3, 9)
		if kind == "error" then duration *= 1.5 end
	end
	if type(options.Actions) == "table" and #options.Actions > 0 then duration = math.max(duration, 8) end
	return duration
end

-- ---------- hosts ----------
function Toast.attach(window)
	local host = setmetatable({
		window = window,
		scope = window._scope:child("toasts"),
		cards = {},
		pool = {},
		inbox = {},
		byId = {},
		unread = false,
	}, Host)
	Toast._installErrorHook()
	return host
end

local standalone = nil
local function standaloneHost()
	if standalone then return standalone end
	local scope = Scope.new("toasts")
	local gui = Factory.new(scope, "ScreenGui", { Name = "ArgonUINotify", DisplayOrder = 110, ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	gui:SetAttribute("ArgonUI", true)
	Env.protectGui(gui)
	Env.parentGui(gui)
	local frame = Factory.new(scope, "Frame", { Name = "Notifications", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	standalone = setmetatable({ scope = scope, cards = {}, pool = {}, inbox = {}, byId = {}, gui = gui, frame = frame }, Host)
	return standalone
end

function Toast.adopt(window)
	-- a standalone host's live cards stay where they are until they expire; new toasts use the window
	local _ = window
end

function Toast.destroyStandalone()
	if standalone then
		standalone.scope:destroy()
		standalone = nil
	end
end

-- The Notifications frame: a direct child of the ScreenGui that stays visible when the window hides.
function Host:layer()
	if self.frame then return self.frame end
	local window = self.window
	local frame = window._layers:get("Notifications")
	self.frame = frame
	self.layout = Factory.list(self.scope, frame, {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 8),
	})
	self.padding = Factory.padding(self.scope, frame, 0, 12, 12, 12)
	window.Notifications = frame
	return frame
end

function Host:_frame()
	if self.window then return self:layer() end
	if not self.layout then
		self.layout = Factory.list(self.scope, self.frame, { HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 8) })
		Factory.padding(self.scope, self.frame, 0, 12, 12, 12)
	end
	return self.frame
end

-- Keeps the stack clear of the window's topbar when it overlaps it horizontally.
function Host:_clearTopbar()
	local window = self.window
	if not window or not self.padding then return end
	local main = rawget(window, "Main")
	local top = 12
	if main and main.Visible then
		local area = window._layers:localSize()
		local x, width = main.Position.X.Offset, main.Size.X.Offset
		if x + width > area.X - WIDTH - 24 then top = main.Position.Y.Offset + Metrics.TOPBAR + 8 end
	end
	self.padding.PaddingTop = UDim.new(0, math.max(12, top))
end

-- ---------- cards ----------
function Host:_build()
	local scope = self.scope:child("card")
	local card = Factory.new(scope, "Frame", {
		Name = "Toast", BackgroundColor3 = T.Raised, Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Active = true,
	})
	Factory.corner(scope, card, Metrics.radius.popover)
	Popover.litEdge(scope, card, 0.86)
	Factory.padding(scope, card, 14, 14, 12, 14)
	local plate = Factory.new(scope, "Frame", { Name = "Plate", Size = UDim2.fromOffset(28, 28), BackgroundColor3 = T.InfoSoft }, card)
	Factory.corner(scope, plate, 8)
	local icon = Factory.new(scope, "ImageLabel", { Name = "TypeIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16) }, plate)
	local title = Factory.text(scope, "TextLabel", { Name = "Title", FontFace = F.Label, TextSize = TS.Label,
		Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -88, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd }, card)
	local time = Factory.text(scope, "TextLabel", { Name = "Time", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Dim,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 2), Size = UDim2.fromOffset(40, 16),
		TextXAlignment = Enum.TextXAlignment.Right }, card)
	local body = Factory.text(scope, "TextLabel", { Name = "Body", FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Muted,
		TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(40, 22), Size = UDim2.new(1, -40, 0, 0),
		TextYAlignment = Enum.TextYAlignment.Top }, card)
	local close = Factory.new(scope, "ImageButton", { Name = "Dismiss", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, 0), Size = UDim2.fromOffset(18, 18), ImageTransparency = 0.4 }, card)
	Icons.apply(close, "x", scope, T.Text2)
	local timer = Factory.new(scope, "Frame", { Name = "Timer", BackgroundColor3 = T.Accent, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 10), Size = UDim2.new(1, 0, 0, 2) }, card)
	Factory.corner(scope, timer, "full")
	local veil = Factory.new(scope, "Frame", { Name = "Veil", BackgroundColor3 = T.Raised, BackgroundTransparency = 1,
		Size = UDim2.new(1, 28, 1, 26), Position = UDim2.fromOffset(-14, -12), ZIndex = 20, Visible = false }, card)
	Factory.corner(scope, veil, Metrics.radius.popover)
	local entry = { scope = scope, card = card, plate = plate, icon = icon, title = title, time = time, body = body,
		close = close, timer = timer, veil = veil }
	scope:connect(close.MouseButton1Click, function() if entry.handle then entry.handle.Dismiss() end end)
	scope:connect(card.MouseEnter, function() entry.paused = true end)
	scope:connect(card.MouseLeave, function()
		entry.paused = false
		if entry.handle then self:_arm(entry) end
	end)
	return entry
end

function Host:_actions(entry, actions)
	if entry.actionFrame then entry.actionFrame:Destroy() entry.actionFrame = nil end
	if type(actions) ~= "table" or #actions == 0 then return end
	local scope = entry.scope
	local row = Factory.new(scope, "Frame", { Name = "Actions", BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -40, 0, 28), LayoutOrder = 3 }, entry.card)
	Factory.list(scope, row, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) })
	for index = 1, math.min(2, #actions) do
		local action = actions[index]
		local button = Factory.text(scope, "TextButton", {
			Text = tostring(action.Text or action.Title or "OK"), FontFace = F.Button, TextSize = TS.Caption,
			TextColor3 = index == 1 and T.Text or T.AccentText, BackgroundColor3 = T.Active, BackgroundTransparency = index == 1 and 0 or 1,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = index,
		}, row)
		Factory.corner(scope, button, 8)
		Factory.padding(scope, button, 12, 12, 0, 0)
		scope:connect(button.MouseButton1Click, function()
			Util.xcall(action.Callback, "Notification action", nil, entry.handle)
			if action.Keep ~= true and entry.handle then entry.handle.Dismiss() end
		end)
	end
	entry.actionFrame = row
	-- the action row sits under the body: give the card room through a bottom inset
	row.Position = UDim2.new(0, 40, 0, 26 + math.max(18, entry.body.AbsoluteSize.Y))
	entry.card:FindFirstChildOfClass("UIPadding").PaddingBottom = UDim.new(0, 48)
end

function Host:_render(entry, options)
	local text = tostring(options.Content or options.Description or "")
	local title = tostring(options.Title or "Notification")
	local kind = options.Type and (ALIASES[string.lower(tostring(options.Type))] or string.lower(tostring(options.Type))) or guessType(title)
	if not TYPES[kind] then kind = "info" end
	local style = TYPES[kind]
	entry.kind = kind
	entry.title.Text = title
	entry.body.Text = text
	entry.body.Visible = text ~= ""
	entry.time.Text = "now"
	entry.plate.BackgroundColor3 = Theme.get(style.soft)
	local iconName = options.Icon or options.Image
	if iconName == nil or iconName == "" then iconName = style.icon end
	Icons.apply(entry.icon, iconName, nil)
	entry.icon.ImageColor3 = Theme.get(style.color)
	entry.timer.BackgroundColor3 = Theme.get(kind == "error" and "Danger" or "Accent")
	entry.duration = autoDuration(options, kind, title .. text)
	entry.timer.Visible = entry.duration ~= math.huge
	entry.callback = options.Callback
	self:_actions(entry, options.Actions)
end

-- Starts (or restarts after a hover) the dismissal timer.
function Host:_arm(entry)
	entry.token = (entry.token or 0) + 1
	local token = entry.token
	if entry.duration == math.huge then return end
	local remaining = entry.remaining or entry.duration
	entry.startedAt = os.clock()
	entry.timer.Size = UDim2.new(remaining / entry.duration, 0, 0, 2)
	if not Motion.reduced then
		local service = Env.services.TweenService
		pcall(function()
			service:Create(entry.timer, TweenInfo.new(remaining, Env.enum("EasingStyle", "Linear")), { Size = UDim2.new(0, 0, 0, 2) }):Play()
		end)
	end
	task.delay(remaining, function()
		if entry.token ~= token or entry.dismissed then return end
		if entry.paused then
			entry.remaining = 1
			return
		end
		entry.handle.Dismiss()
	end)
end

function Host:_relayoutStack()
	local visible = {}
	for _, entry in ipairs(self.cards) do
		if not entry.dismissed then visible[#visible + 1] = entry end
	end
	local overflow = #visible - MAX_VISIBLE
	for index, entry in ipairs(visible) do
		entry.card.LayoutOrder = -index
		if index <= overflow then
			entry.handle.Dismiss(true)
		end
	end
	local hidden = math.max(0, overflow)
	if hidden > 0 then
		if not self.more then
			self.more = Factory.text(self.scope, "TextButton", { Name = "MoreChip", FontFace = F.Caption, TextSize = TS.Caption,
				TextColor3 = T.Text2, BackgroundColor3 = T.Raised, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28),
				TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1000 })
			Factory.corner(self.scope, self.more, "full")
			Factory.padding(self.scope, self.more, 12, 12, 0, 0)
			self.scope:connect(self.more.MouseButton1Click, function() self:openInbox(self.window and self.window._bell) end)
		end
		self.moreCount = (self.moreCount or 0) + hidden
		self.more.Text = ("+%d more in inbox"):format(self.moreCount)
		self.more.Parent = self:_frame()
	end
end

function Host:notify(options)
	options = type(options) == "table" and options or { Title = tostring(options) }
	local frame = self:_frame()
	self:_clearTopbar()
	local id = options.Id
	if id ~= nil and self.byId[id] and not self.byId[id].dismissed then
		local entry = self.byId[id]
		self:_render(entry, options)
		entry.remaining = nil
		self:_arm(entry)
		return entry.handle
	end
	local title = tostring(options.Title or "")
	local body = tostring(options.Content or options.Description or "")
	for _, entry in ipairs(self.cards) do
		if not entry.dismissed and entry.title.Text == title and entry.body.Text == body and os.clock() - (entry.at or 0) < 2 then
			entry.count = (entry.count or 1) + 1
			entry.title.Text = ("%s  x%d"):format(title, entry.count)
			entry.remaining = nil
			self:_arm(entry)
			return entry.handle
		end
	end
	local entry = table.remove(self.pool) or self:_build()
	entry.dismissed = false
	entry.count = 1
	entry.remaining = nil
	entry.paused = false
	entry.at = os.clock()
	self:_render(entry, options)
	local card = entry.card
	card.Size = UDim2.fromOffset(Platform.isPhone(self.window and self.window._layers:guiSize() or Vector2.new(1280, 720)) and 300 or WIDTH, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = frame
	if not Motion.reduced then
		entry.veil.Visible = true
		entry.veil.BackgroundTransparency = 0
		Motion.tween(entry.veil, "veil", { BackgroundTransparency = 1 })
	end
	local handle = { Instance = card }
	function handle.Update(_, patch)
		if type(_) == "table" and patch == nil and _ ~= handle then patch = _ end
		if entry.dismissed or type(patch) ~= "table" then return handle end
		local merged = { Title = entry.title.Text, Content = entry.body.Text, Type = entry.kind }
		for key, value in pairs(patch) do merged[key] = value end
		self:_render(entry, merged)
		entry.remaining = nil
		self:_arm(entry)
		return handle
	end
	function handle.SetProgress(_, fraction)
		if type(_) == "number" then fraction = _ end
		entry.timer.Visible = true
		entry.timer.Size = UDim2.new(math.clamp(tonumber(fraction) or 0, 0, 1), 0, 0, 2)
		return handle
	end
	function handle.Dismiss(quiet)
		if entry.dismissed then return end
		entry.dismissed = true
		entry.token = (entry.token or 0) + 1
		if id ~= nil and self.byId[id] == entry then self.byId[id] = nil end
		local function finish()
			card.Parent = nil
			entry.handle = nil
			for index = #self.cards, 1, -1 do
				if self.cards[index] == entry then table.remove(self.cards, index) end
			end
			if #self.pool < POOL then
				self.pool[#self.pool + 1] = entry
			else
				entry.scope:destroy()
			end
		end
		if quiet == true or Motion.reduced then
			finish()
		else
			entry.veil.Visible = true
			Motion.tween(entry.veil, "toastOut", { BackgroundTransparency = 0 })
			task.delay(Motion.duration("toastOut"), finish)
		end
	end
	setmetatable(handle, {
		__index = function(_, key)
			local value = card[key]
			if type(value) == "function" then
				return function(_, ...) return value(card, ...) end
			end
			return value
		end,
	})
	entry.handle = handle
	if id ~= nil then self.byId[id] = entry end
	self.cards[#self.cards + 1] = entry
	self:_record(options, entry.kind)
	self:_arm(entry)
	self:_relayoutStack()
	return handle
end

-- ---------- inbox ----------
function Host:_record(options, kind)
	table.insert(self.inbox, 1, { Title = tostring(options.Title or "Notification"), Body = tostring(options.Content or options.Description or ""),
		Type = kind, At = os.time() })
	while #self.inbox > 30 do table.remove(self.inbox) end
	self.unread = true
	local window = self.window
	if window and window._bellDot then window._bellDot.Visible = true end
end

function Host:openInbox(anchor)
	local window = self.window
	if not window then return end
	self.unread = false
	if window._bellDot then window._bellDot.Visible = false end
	self.moreCount = 0
	if self.more then self.more.Parent = nil end
	local host = self
	window._popover:open({
		owner = host, anchor = anchor, reuse = "inbox", name = "Inbox", width = 340, maxHeight = 420, sheetOnPhone = true,
		build = function(frame, scope)
			Factory.padding(scope, frame, 12, 12, 10, 10)
			Factory.text(scope, "TextLabel", { Name = "Heading", Text = "Notifications", FontFace = F.Label, TextSize = TS.Label,
				Size = UDim2.new(1, -80, 0, 24) }, frame)
			local clear = Factory.text(scope, "TextButton", { Name = "Clear", Text = "Clear all", FontFace = F.Caption, TextSize = TS.Caption,
				TextColor3 = T.AccentText, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(70, 24),
				TextXAlignment = Enum.TextXAlignment.Right }, frame)
			local list = Factory.new(scope, "ScrollingFrame", { Name = "Items", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30),
				Size = UDim2.new(1, 0, 1, -30), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3 }, frame)
			Factory.list(scope, list, { Padding = UDim.new(0, 4) })
			host.inboxList = list
			scope:connect(clear.MouseButton1Click, function()
				table.clear(host.inbox)
				host:_renderInbox()
			end)
			return Vector2.new(340, 200)
		end,
		bind = function()
			return host:_renderInbox()
		end,
	})
end

function Host:_renderInbox()
	local list = self.inboxList
	if not list then return Vector2.new(340, 120) end
	if self.inboxScope then self.inboxScope:destroy() end
	local scope = self.scope:child("inbox")
	self.inboxScope = scope
	if #self.inbox == 0 then
		Factory.text(scope, "TextLabel", { Text = "You're all caught up", FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Muted,
			Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center }, list)
		return Vector2.new(340, 100)
	end
	for index, item in ipairs(self.inbox) do
		local style = TYPES[item.Type] or TYPES.info
		local row = Factory.new(scope, "Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = index }, list)
		local icon = Factory.new(scope, "ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(4, 6) }, row)
		Icons.apply(icon, style.icon, nil)
		icon.ImageColor3 = Theme.get(style.color)
		Factory.text(scope, "TextLabel", { Text = item.Title, FontFace = F.Label, TextSize = TS.Body, Position = UDim2.fromOffset(28, 2),
			Size = UDim2.new(1, -80, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, row)
		Factory.text(scope, "TextLabel", { Text = item.Body, FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted,
			Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -32, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd }, row)
		Factory.text(scope, "TextLabel", { Text = Util.ago(os.time() - item.At), FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Dim,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(52, 16), TextXAlignment = Enum.TextXAlignment.Right }, row)
	end
	return Vector2.new(340, math.min(420, 52 + #self.inbox * 48))
end

-- ---------- pills: small toasts, Undo ----------
function Host:pill(text, kind, action)
	local options = { Title = tostring(text), Type = kind or "info", Duration = 3.5 }
	if type(action) == "table" then options.Actions = { action } end
	return self:notify(options)
end

-- One Undo pill at the bottom centre of the window for 6 s; a new one replaces it.
function Host:undo(text, callback)
	local window = self.window
	if not window then return end
	local layer = window._layers:get("Toast")
	local scope = self.scope
	local pill = self.undoPill
	if not pill then
		pill = Factory.new(scope, "Frame", { Name = "UndoPill", BackgroundColor3 = T.Raised, AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Active = true, Visible = false }, layer)
		Factory.corner(scope, pill, "full")
		Popover.litEdge(scope, pill, 0.86)
		Factory.padding(scope, pill, 16, 12, 0, 0)
		Factory.list(scope, pill, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
			VerticalAlignment = Enum.VerticalAlignment.Center })
		self.undoText = Factory.text(scope, "TextLabel", { Text = "", FontFace = F.Body, TextSize = TS.Body, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1), LayoutOrder = 1 }, pill)
		local button = Factory.text(scope, "TextButton", { Name = "Undo", Text = "Undo", FontFace = F.Button, TextSize = TS.Body,
			TextColor3 = T.AccentText, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), LayoutOrder = 2 }, pill)
		local cap = Factory.text(scope, "TextLabel", { Text = "Ctrl Z", FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Text2,
			BackgroundColor3 = T.Active, BackgroundTransparency = 0, Size = UDim2.fromOffset(48, 22), LayoutOrder = 3,
			TextXAlignment = Enum.TextXAlignment.Center }, pill)
		Factory.corner(scope, cap, 6)
		scope:connect(button.MouseButton1Click, function()
			if self.undoCallback then
				local fn = self.undoCallback
				self:dismissUndo()
				fn()
			end
		end)
		self.undoPill = pill
	end
	self.undoText.Text = tostring(text)
	self.undoCallback = callback
	local main = rawget(window, "Main")
	if main then
		pill.Position = UDim2.fromOffset(main.Position.X.Offset + main.Size.X.Offset / 2, main.Position.Y.Offset + main.Size.Y.Offset - 16)
	else
		local area = window._layers:localSize()
		pill.Position = UDim2.fromOffset(area.X / 2, area.Y - 24)
	end
	pill.Visible = true
	self.undoToken = (self.undoToken or 0) + 1
	local token = self.undoToken
	task.delay(6, function()
		if self.undoToken == token then self:dismissUndo() end
	end)
end

function Host:undoAlive()
	return self.undoPill ~= nil and self.undoPill.Visible == true
end

function Host:dismissUndo()
	self.undoToken = (self.undoToken or 0) + 1
	self.undoCallback = nil
	if self.undoPill then self.undoPill.Visible = false end
end

-- Shows text in a read-only box so it can be copied by hand (no setclipboard available).
function Host:copySheet(text)
	local window = self.window
	if not window then return end
	window:Dialog({ Title = "Copy this text", Content = "Select the text and press Ctrl C.", CopyText = tostring(text),
		Buttons = { { Title = "Close", Variant = "Primary" } } })
end

function Host:flushQueued() end

-- ---------- module API ----------
function Toast.notify(window, options)
	local host = window and window._toastHost or standaloneHost()
	return host:notify(options)
end

function Toast.toast(window, text, kind, action)
	local host = window and window._toastHost or standaloneHost()
	return host:pill(text, kind, action)
end

-- Callback errors anywhere in the library become an error toast with Copy error and Retry.
local recent = {}
function Toast._installErrorHook()
	if Util.onError then return end
	Util.onError = function(context, message, retry, owner)
		if Prefs.get("ShowCallbackErrors") == false then return end
		local key = tostring(context) .. message
		if recent[key] and os.clock() - recent[key] < 10 then return end
		recent[key] = os.clock()
		local window = owner and owner._window
		if not window then return end
		window._toastHost:notify({
			Title = "Callback error", Content = tostring(context) .. ": " .. message, Type = "error",
			Actions = {
				{ Text = "Copy error", Callback = function() window:_copy(tostring(context) .. ": " .. message) end },
				{ Text = "Retry", Callback = function() retry() end },
			},
		})
	end
end

return Toast
