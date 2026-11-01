--!nocheck
-- The honest loader (DESIGN_V2 section 4, RECONCILIATION R10). Nothing is shown for 150 ms;
-- the card appears only while real work is pending, says what is happening, stays at least
-- LoadingMinimum once shown, and hands over to the already-built window with an empty ghost.
-- All timing is done with task.delay tokens, never fixed reveal timers.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Metrics = require("theme/Metrics")
local Fonts = require("theme/Fonts")
local Assets = require("theme/Assets")
local Popover = require("layers/Popover")
local Platform = require("input/Platform")

local T, F, TS = Token.T, Token.F, Token.TS
local Loader = {}
Loader.__index = Loader

local CARD_W, CARD_H = 380, 104

function Loader.create(window, options)
	local screen = options.LoadingScreen
	local config = type(screen) == "table" and screen or {}
	local mode = type(screen) == "string" and screen:lower() or "auto"
	local self = setmetatable({
		window = window,
		scope = window._scope:child("loader"),
		mode = mode,
		title = tostring(config.Title or options.LoadingTitle or window._title),
		subtitle = config.Subtitle or options.LoadingSubtitle,
		tips = type(config.Tips) == "table" and config.Tips or nil,
		minimum = tonumber(options.LoadingMinimum) or 0.25,
		shown = false,
		minimumElapsed = false,
		quiet = false,
		activityToken = 0,
		progressToken = 0,
		fontTimeout = false,
		log = {},
		status = "Starting",
	}, Loader)
	self:_build()
	return self
end

function Loader:_build()
	local scope = self.scope
	local layer = self.window._layers:get("Boot")
	local width = CARD_W
	local card = Factory.new(scope, "Frame", {
		Name = "Loader",
		BackgroundColor3 = T.Raised,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, CARD_H),
		Active = true,
		Visible = false,
		ZIndex = 2,
	})
	Factory.corner(scope, card, Metrics.radius.card)
	self.edge = Popover.litEdge(scope, card, 1)
	self.uiscale = Factory.new(scope, "UIScale", { Scale = 0.94 }, card)
	self.shadow = Popover.shadow(scope, layer, 1, 1)
	local orb = Factory.new(scope, "Frame", { Name = "Orb", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 22), Size = UDim2.fromOffset(60, 60), ZIndex = 3 }, card)
	self.bloom = Factory.new(scope, "ImageLabel", {
		Name = "Bloom", BackgroundTransparency = 1, Image = Assets.glow.Image, ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Assets.glow.SliceCenter, ImageColor3 = T.Accent, ImageTransparency = 1,
		Position = UDim2.fromOffset(-10, -10), Size = UDim2.fromOffset(80, 80), ZIndex = 3,
	}, orb)
	local track = Factory.new(scope, "Frame", { Name = "RingTrack", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(52, 52), ZIndex = 4 }, orb)
	Factory.corner(scope, track, "full")
	self.trackStroke = Factory.stroke(scope, track, T.Track, 1, 3)
	local ring = Factory.new(scope, "Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(52, 52), ZIndex = 5 }, orb)
	Factory.corner(scope, ring, "full")
	self.ringStroke = Factory.stroke(scope, ring, T.White, 1, 3)
	self.ringGradient = Factory.new(scope, "UIGradient", {
		Color = Token.seq("AccentHi", "Accent", "AccentAlt"),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.52, 1), NumberSequenceKeypoint.new(1, 1),
		}),
	}, self.ringStroke)
	local plate = Factory.new(scope, "Frame", { Name = "Plate", BackgroundColor3 = T.White, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(40, 40), ZIndex = 6 }, orb)
	Factory.corner(scope, plate, "full")
	Factory.new(scope, "UIGradient", { Rotation = 135, Color = Token.seq("AccentHi", "Accent") }, plate)
	self.letter = Factory.text(scope, "TextLabel", {
		Name = "Letter", Text = (self.title:match("[%w]") or "A"):upper(), FontFace = F.LoaderTitle, TextSize = 18,
		TextColor3 = T.OnAccent, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1), ZIndex = 7,
	}, plate)
	self.plate = plate
	self.titleLabel = Factory.text(scope, "TextLabel", {
		Name = "Title", Text = self.title, FontFace = F.LoaderTitle, TextSize = TS.LoaderTitle, TextTransparency = 1,
		Position = UDim2.fromOffset(96, 22), Size = UDim2.new(1, -116, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
	}, card)
	self.statusLabel = Factory.text(scope, "TextLabel", {
		Name = "Status", Text = "Starting", FontFace = F.Status, TextSize = TS.Status, TextColor3 = T.Muted, TextTransparency = 1,
		RichText = true, Position = UDim2.fromOffset(96, 46), Size = UDim2.new(1, -170, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
	}, card)
	self.percent = Factory.text(scope, "TextLabel", {
		Name = "Percent", Text = "", FontFace = F.Value, TextSize = TS.Value, TextColor3 = T.Text2, TextTransparency = 1,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 46), Size = UDim2.fromOffset(60, 18),
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
	}, card)
	local bar = Factory.new(scope, "Frame", { Name = "Bar", BackgroundColor3 = T.Track, BackgroundTransparency = 1,
		Position = UDim2.new(0, 96, 1, -24), Size = UDim2.new(1, -116, 0, 3), ZIndex = 3 }, card)
	Factory.corner(scope, bar, "full")
	local fill = Factory.new(scope, "Frame", { Name = "Fill", BackgroundColor3 = T.White, BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.3, 1), ZIndex = 4 }, bar)
	Factory.corner(scope, fill, "full")
	Factory.new(scope, "UIGradient", { Color = Token.seq("Accent", "AccentAlt") }, fill)
	self.bar, self.fill = bar, fill
	self.tip = Factory.text(scope, "TextLabel", {
		Name = "Tip", Text = "", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Text2, TextTransparency = 1, Visible = false,
		Position = UDim2.new(0, 96, 1, -18), Size = UDim2.new(1, -116, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
	}, card)
	self.Card = card
	self.fadeTargets = {
		{ card, "BackgroundTransparency", 0 }, { self.titleLabel, "TextTransparency", 0 }, { self.statusLabel, "TextTransparency", 0 },
		{ self.percent, "TextTransparency", 0 }, { bar, "BackgroundTransparency", 0 }, { fill, "BackgroundTransparency", 0 },
		{ plate, "BackgroundTransparency", 0 }, { self.letter, "TextTransparency", 0 }, { self.trackStroke, "Transparency", 0 },
		{ self.ringStroke, "Transparency", 0 },
	}
	card.Parent = layer
	self:_layout()
	self.scope:connect(self.window._layers.resized, function() self:_layout() end)
end

function Loader:_layout()
	local area = self.window._layers:localSize()
	local width = math.min(CARD_W, area.X - 32)
	self.Card.Size = UDim2.fromOffset(width, CARD_H)
	Popover.placeShadow(self.shadow, Vector2.new(area.X / 2 - width / 2, area.Y / 2 - CARD_H / 2), Vector2.new(width, CARD_H), 20, 10)
end

-- ---------- lifecycle ----------
function Loader:start()
	local window = self.window
	self:activity()
	task.delay(0.8, function() self.fontTimeout = true self:evaluate() end)
	if self.mode == "always" then
		self:show()
	elseif self.mode ~= "never" then
		task.delay(0.15, function()
			if window._loading and not self.handingOver and self:_workPending() then self:show() end
		end)
	end
	self:_poll()
	self:_armStall()
end

function Loader:_poll()
	if not self.window._loading or self.handingOver then return end
	task.delay(0.05, function()
		self:evaluate()
		self:_poll()
	end)
end

function Loader:_workPending()
	local window = self.window
	if #window.Tabs == 0 then return true end
	if not window._shellMounted then return true end
	local tab = window.ActiveTab
	if tab and not tab:_fullyMounted() then return true end
	if window._restoring then return true end
	return not self:_released()
end

-- Library activity (Create*, progress, restore) resets the 250 ms quiet rule. One timer at a
-- time: it re-arms itself for whatever is left of the quiet period.
function Loader:activity()
	self.quiet = false
	self.lastActivity = Env.now()
	if self.quietArmed then return end
	self.quietArmed = true
	local function check()
		if not self.window._loading or self.handingOver then
			self.quietArmed = false
			return
		end
		local idle = Env.now() - self.lastActivity
		if idle >= 0.25 - 1e-6 then
			self.quietArmed = false
			self.quiet = true
			self:evaluate()
		else
			task.delay(0.25 - idle, check)
		end
	end
	task.delay(0.25, check)
end

-- Stall footer at 8 s and the watchdog at 30 s, both counted from the last progress (D11).
function Loader:_armStall()
	self.lastProgress = Env.now()
	if self.stallArmed then return end
	self.stallArmed = true
	local function check()
		local window = self.window
		if not window._loading or self.handingOver or self.destroyed then
			self.stallArmed = false
			return
		end
		local idle = Env.now() - self.lastProgress
		if idle >= 30 - 1e-6 then
			self.stallArmed = false
			window:FinishLoading()
			return
		end
		if idle >= 8 - 1e-6 and not self.stallFooter then self:_stalled() end
		task.delay(idle < 8 and (8 - idle) or (30 - idle), check)
	end
	task.delay(8, check)
end

function Loader:progressed()
	self:activity()
	self:_armStall()
	if self.stallFooter and not self.errored then
		self.stallFooter:Destroy()
		self.stallFooter = nil
		self.Card.Size = UDim2.fromOffset(self.Card.Size.X.Offset, CARD_H)
	end
end

function Loader:_hostDead()
	local thread = self.window._hostThread
	if type(thread) ~= "thread" then return false end
	local ok, status = pcall(coroutine.status, thread)
	return ok and status == "dead"
end

function Loader:_released()
	local window = self.window
	if self.finishRequested then return true end
	if window._loadingManual then return false end
	if self:_hostDead() then return true end
	return #window.Tabs > 0 and self.quiet
end

-- Opens the window once everything that must be on screen is built and the host is done.
function Loader:evaluate()
	local window = self.window
	if not window._loading or self.handingOver or window._destroyed then return end
	if self.finishRequested then
		self:handover()
		return
	end
	if not window._shellMounted then return end
	local tab = window.ActiveTab
	if tab and not tab:_fullyMounted() then return end
	if not (Fonts.resolved() or self.fontTimeout) then return end
	if not self:_released() then
		self:_updateStatus()
		return
	end
	if self.shown and not self.minimumElapsed then
		self.pendingRelease = true
		return
	end
	self:handover()
end

function Loader:_updateStatus()
	local window = self.window
	if window._loadingHostStatus then return end
	if #window.Tabs == 0 and self.quiet then
		self:setStatus("Waiting for script")
	elseif window._restoring then
		return
	elseif window.ActiveTab then
		local tab = window.ActiveTab
		local total = #tab._elements
		self:setStatus(("Building %s · <font face=\"RobotoMono\">%d</font> of <font face=\"RobotoMono\">%d</font>"):format(tab.Name, math.min(tab._mountedCount, total), total), true)
		if total > 0 then self:setProgress(0.85 * tab._mountedCount / total, true) end
	end
end

-- ---------- card ----------
function Loader:show()
	if self.shown or self.handingOver or self.mode == "never" then return end
	self.shown = true
	local card = self.Card
	card.Visible = true
	self.shadow.Visible = true
	self.shadow.ImageTransparency = 0.45
	for _, target in ipairs(self.fadeTargets) do
		local inst, prop, value = target[1], target[2], target[3]
		Motion.tween(inst, "veil", { [prop] = value })
	end
	Motion.spring(self.uiscale, "Scale", 1, "gentle")
	self.edge.Transparency = 0.86
	self.bloomLoop = Motion.loop(self.bloom, "bloom", { ImageTransparency = 0.85 })
	self.bloom.ImageTransparency = 0.7
	self.ringLoop = Motion.loop(self.ringGradient, "ring", { Rotation = 360 })
	self:_indeterminate(true)
	task.delay(self.minimum, function()
		self.minimumElapsed = true
		if self.pendingRelease then self:handover() end
	end)
	task.delay(2, function()
		if self.handingOver or not self.Card.Parent then return end
		local tip = self.tips and self.tips[1] or (Platform.preferred() == "mouse" and "Tip: press Ctrl K to search every setting" or nil)
		if tip then
			self.tip.Text = tip
			self.tip.Visible = true
			Motion.tween(self.tip, "veil", { TextTransparency = 0 })
		end
	end)
end

function Loader:_indeterminate(on)
	if on and not self.sweep then
		self.fill.Size = UDim2.fromScale(0.3, 1)
		self.fill.Position = UDim2.fromScale(0, 0)
		self.sweep = Motion.loop(self.fill, "indeterminate", { Position = UDim2.fromScale(0.7, 0) })
		self.percent.Text = ""
	elseif not on and self.sweep then
		self.sweep.stop()
		self.sweep = nil
		self.fill.Position = UDim2.fromScale(0, 0)
	end
end

function Loader:setStatus(text, rich)
	text = tostring(text)
	if self.status == text then return end
	self.status = text
	self.log[#self.log + 1] = ("%.2f %s"):format(os.clock(), text:gsub("<[^>]+>", ""))
	if #self.log > 20 then table.remove(self.log, 1) end
	local label = self.statusLabel
	label.Text = text
	if self.shown and not Motion.reduced then
		label.TextTransparency = 0.6
		Motion.tween(label, "tooltip", { TextTransparency = 0 })
	end
end

-- Determinate progress (0-1). Never moves backwards.
function Loader:setProgress(fraction, determinate)
	fraction = math.clamp(fraction, 0, 1)
	if determinate then
		self:_indeterminate(false)
		self.shownProgress = math.max(self.shownProgress or 0, fraction)
		Motion.tween(self.fill, "progress", { Size = UDim2.fromScale(math.max(0.04, self.shownProgress), 1) })
		self.percent.Text = ("%d%%"):format(math.floor(self.shownProgress * 100 + 0.5))
	end
end

function Loader:_stalled()
	if self.stallFooter or not self.shown then
		if not self.shown and self.window._loading then self:show() end
	end
	self:setStatus("No progress for 8 s")
	if self.stallFooter then return end
	local scope = self.scope
	local footer = Factory.new(scope, "Frame", { Name = "Footer", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, CARD_H),
		Size = UDim2.new(1, -40, 0, 48), ZIndex = 3 }, self.Card)
	Factory.list(scope, footer, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right })
	local function button(text, primary, callback)
		local b = Factory.text(scope, "TextButton", {
			Text = text, FontFace = F.Button, TextSize = TS.Button, TextColor3 = primary and T.OnAccent or T.Text,
			BackgroundColor3 = primary and T.Accent or T.Active, Size = UDim2.fromOffset(110, 36),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
		}, footer)
		Factory.corner(scope, b, 10)
		scope:connect(b.MouseButton1Click, callback)
		return b
	end
	button("Copy log", false, function() self.window:_copy(table.concat(self.log, "\n")) end)
	button("Open now", true, function() self.window:FinishLoading() end)
	self.stallFooter = footer
	self.Card.Size = UDim2.fromOffset(self.Card.Size.X.Offset, CARD_H + 52)
end

function Loader:error(message)
	self:show()
	self.errored = true
	self:setStatus("Build failed")
	self.ringStroke.Color = Token.resolve(T.Danger)
	if self.ringLoop then self.ringLoop.stop() end
	self:_indeterminate(false)
	self.fill.BackgroundColor3 = Token.resolve(T.Danger)
	local scope = self.scope
	local box = Factory.text(scope, "TextLabel", {
		Name = "Error", Text = tostring(message), FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Danger,
		BackgroundColor3 = T.DangerSoft, BackgroundTransparency = 0, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(20, CARD_H), Size = UDim2.new(1, -40, 0, 64), ZIndex = 3,
	}, self.Card)
	Factory.corner(scope, box, 10)
	Factory.padding(scope, box, 8, 8, 6, 6)
	self.Card.Size = UDim2.fromOffset(self.Card.Size.X.Offset, CARD_H + 76)
	self.progressToken += 1
	if not self.stallFooter then
		self:_stalled()
		self:setStatus("Build failed")
		self.Card.Size = UDim2.fromOffset(self.Card.Size.X.Offset, CARD_H + 76 + 52)
		self.stallFooter.Position = UDim2.fromOffset(20, CARD_H + 76)
	end
end

-- ---------- hand-over ----------
function Loader:handover()
	if self.handingOver then return end
	self.handingOver = true
	local window = self.window
	window._loading = false
	if self.sweep then self.sweep.stop() end
	if self.bloomLoop then self.bloomLoop.stop() end
	if self.ringLoop then self.ringLoop.stop() end
	window:_revealShell(self.shown)
	if self.shown and not Motion.reduced then
		for _, target in ipairs(self.fadeTargets) do
			if target[1] ~= self.Card then Motion.tween(target[1], "veil", { [target[2]] = 1 }) end
		end
		local card = self.Card
		local layers = window._layers
		local from = card.AbsolutePosition
		local ghost = Factory.new(self.scope, "Frame", {
			Name = "Ghost", BackgroundColor3 = T.Frame, BackgroundTransparency = Token.M.Frame,
			Position = UDim2.fromOffset(layers:toLocal(from).X, layers:toLocal(from).Y), Size = card.Size, ZIndex = 1,
		}, layers:get("Boot"))
		Factory.corner(self.scope, ghost, Metrics.radius.window)
		card.Visible = false
		self.shadow.Visible = false
		local main = window.Main
		Motion.tween(ghost, "ghost", { Position = main.Position, Size = main.Size })
		task.delay(0.26, function() self:destroy() end)
	else
		self:destroy()
	end
end

function Loader:destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.scope:destroy()
	if self.window._loader == self then self.window._loader = nil end
end

return Loader
