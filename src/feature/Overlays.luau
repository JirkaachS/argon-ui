--!nocheck
-- HUD overlays (DESIGN_V2 7.7): the player list, the keybind list and the watermark. All are
-- off unless the host or the user enables them. Player rows use rbxthumb avatars (no API
-- calls) and Players events are connected only while the player list is on; the watermark
-- ticks only while it is visible. v1's setters, fields and saved positions are kept.

local Env = require("core/Env")
local Util = require("core/Util")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Theme = require("theme/Theme")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Drag = require("input/Drag")
local Platform = require("input/Platform")
local Popover = require("layers/Popover")
local Prefs = require("persist/Prefs")

local T, F, TS, M = Token.T, Token.F, Token.TS, Token.M
local Overlays = {}
local Host = {}
Host.__index = Host

local WIDTH = 240

-- v1 transparency (0.12-0.8) onto the HUD material range 0-0.18 (RECONCILIATION R16).
function Overlays.mapTransparency(value)
	local v = math.clamp(tonumber(value) or 0.38, 0.12, 0.8)
	return (v - 0.12) / (0.8 - 0.12) * 0.18
end

local function encodePosition(position)
	return { XS = position.X.Scale, XO = position.X.Offset, YS = position.Y.Scale, YO = position.Y.Offset }
end
local function decodePosition(value, fallback)
	if type(value) ~= "table" then return fallback end
	return UDim2.new(tonumber(value.XS) or 0, tonumber(value.XO) or 0, tonumber(value.YS) or 0, tonumber(value.YO) or 0)
end

function Overlays.attach(window, prefs, options)
	local host = setmetatable({
		window = window,
		scope = window._scope:child("overlays"),
		enabled = {
			Players = prefs.PlayerListEnabled ~= nil and prefs.PlayerListEnabled == true or options.PlayerList == true,
			Keybinds = prefs.KeybindListEnabled ~= nil and prefs.KeybindListEnabled == true or options.KeybindList == true,
			Watermark = prefs.Watermark == true or options.Watermark == true,
		},
		pinned = prefs.OverlaysAlwaysVisible ~= nil and prefs.OverlaysAlwaysVisible == true or options.OverlaysAlwaysVisible == true,
		transparency = tonumber(prefs.OverlayTransparency) or 0.38,
		scale = math.clamp(tonumber(prefs.OverlayScale) or 1, 0.75, 1.4),
		positions = type(prefs.OverlayPositions) == "table" and prefs.OverlayPositions or {},
		cards = {},
		rows = {},
	}, Host)
	return host
end

-- ---------- cards ----------
function Host:_card(name, title, iconName, defaultPosition)
	local scope = self.scope
	local layer = self.window._layers:get("Overlay")
	local card = Factory.new(scope, "Frame", {
		Name = name, BackgroundColor3 = T.Frame, BackgroundTransparency = M.HUD, AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y, Active = true, Visible = false,
	}, layer)
	Factory.corner(scope, card, Metrics.radius.popover)
	Popover.litEdge(scope, card, 0.86)
	local uiscale = Factory.new(scope, "UIScale", { Scale = self.scale }, card)
	Factory.padding(scope, card, 12, 12, 8, 10)
	Factory.list(scope, card, { Padding = UDim.new(0, 4) })
	local header = Factory.new(scope, "TextButton", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0 }, card)
	local icon = Factory.new(scope, "ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(0, 5) }, header)
	Icons.apply(icon, iconName, scope, T.Text2)
	Factory.text(scope, "TextLabel", { Name = "Title", Text = title, FontFace = F.Label, TextSize = TS.Body, Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -60, 1, 0) }, header)
	local meta = Factory.text(scope, "TextLabel", { Name = "Meta", Text = "", FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Dim,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 60, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, header)
	local body = Factory.new(scope, "Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, card)
	Factory.list(scope, body, { Padding = UDim.new(0, 2) })
	local entry = { card = card, body = body, meta = meta, scale = uiscale, default = defaultPosition, key = name == "PlayerOverlay" and "Players" or "Keybinds" }
	card.Position = decodePosition(self.positions[entry.key], defaultPosition)
	scope:connect(header.InputBegan, function(input)
		local kind = input.UserInputType and input.UserInputType.Name
		if kind ~= "MouseButton1" and kind ~= "Touch" then return end
		local start = card.Position
		local origin = Vector2.new(input.Position.X, input.Position.Y)
		Drag.begin(input, {
			threshold = 4,
			onMove = function(position)
				local delta = (position - origin) / self.window._layers.scale
				card.Position = UDim2.new(start.X.Scale, start.X.Offset + delta.X, start.Y.Scale, start.Y.Offset + delta.Y)
			end,
			onEnd = function() self:_savePositions() end,
		})
	end)
	self.cards[entry.key] = entry
	return entry
end

function Host:ensure()
	if self.built then return end
	self.built = true
	local players = self:_card("PlayerOverlay", "Players", "users", UDim2.new(1, -16, 0, 72))
	local keybinds = self:_card("KeybindOverlay", "Keybinds", "keyboard", UDim2.new(1, -16, 0, 360))
	self.window.PlayerListOverlay = players.card
	self.window.KeybindListOverlay = keybinds.card
	self:refreshKeybinds()
end

function Host:_savePositions()
	local positions = {}
	for key, entry in pairs(self.cards) do positions[key] = encodePosition(entry.card.Position) end
	self.positions = positions
	Prefs.set("OverlayPositions", positions)
end

-- ---------- players ----------
function Host:_watchPlayers(on)
	local players = Env.services.Players
	if on and not self.playerScope then
		local scope = self.scope:child("players")
		self.playerScope = scope
		scope:connect(players.PlayerAdded, function() self:refreshPlayers() end)
		scope:connect(players.PlayerRemoving, function(player) self:refreshPlayers(player) end)
		self:refreshPlayers()
	elseif not on and self.playerScope then
		self.playerScope:destroy()
		self.playerScope = nil
	end
end

function Host:refreshPlayers(leaving)
	local entry = self.cards.Players
	if not entry then return end
	local players = Env.services.Players
	local list = {}
	for _, player in ipairs(players:GetPlayers()) do
		if player ~= leaving then list[#list + 1] = player end
	end
	local me = Env.localPlayer()
	table.sort(list, function(a, b)
		if a == me then return true elseif b == me then return false end
		return tostring(a.DisplayName):lower() < tostring(b.DisplayName):lower()
	end)
	entry.meta.Text = tostring(#list)
	local scope = self.scope
	local seen = {}
	for index, player in ipairs(list) do
		local id = tonumber(player.UserId) or index
		seen[id] = true
		local row = self.rows[id]
		if not row then
			local frame = Factory.new(scope, "Frame", { Name = "Player", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32) }, entry.body)
			local avatar = Factory.new(scope, "ImageLabel", { BackgroundColor3 = T.Active, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(0, 4),
				Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(id) }, frame)
			Factory.corner(scope, avatar, "full")
			local name = Factory.text(scope, "TextLabel", { Text = tostring(player.DisplayName), FontFace = F.Body, TextSize = TS.Body, TextColor3 = T.Text2,
				Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -32, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, frame)
			row = { frame = frame, name = name }
			self.rows[id] = row
		end
		row.frame.LayoutOrder = index
	end
	for id, row in pairs(self.rows) do
		if not seen[id] then
			row.frame:Destroy()
			self.rows[id] = nil
		end
	end
end

-- ---------- keybinds ----------
function Host:refreshKeybinds()
	local entry = self.cards.Keybinds
	if not entry then return end
	if self.keyScope then self.keyScope:destroy() end
	local scope = self.scope:child("keys")
	self.keyScope = scope
	local shown = 0
	for _, element in ipairs(self.window._keybinds or {}) do
		if not element._destroyed and element.DisplayInKeybindList ~= false then
			shown += 1
			local active = element._active == true
			local row = Factory.new(scope, "Frame", { Name = "Bind", BackgroundColor3 = T.AccentSoft, BackgroundTransparency = active and 0 or 1,
				Size = UDim2.new(1, 0, 0, 28), LayoutOrder = shown }, entry.body)
			Factory.corner(scope, row, 8)
			if active then
				local dot = Factory.new(scope, "Frame", { BackgroundColor3 = T.Accent, Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 6, 0.5, -3) }, row)
				Factory.corner(scope, dot, "full")
			end
			Factory.text(scope, "TextLabel", { Text = tostring(element.Name), FontFace = F.Body, TextSize = TS.Body, TextColor3 = active and T.Text or T.Text2,
				Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -110, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, row)
			Factory.text(scope, "TextLabel", { Text = tostring(element._mode or "Press"), FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Dim,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 0), Size = UDim2.new(0, 40, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
			local cap = Factory.text(scope, "TextLabel", { Text = Util.keyName(element.CurrentKeybind), FontFace = F.Key, TextSize = TS.Key,
				BackgroundColor3 = T.Raised, BackgroundTransparency = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.fromOffset(44, 20), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, row)
			Factory.corner(scope, cap, 6)
		end
	end
	entry.meta.Text = tostring(shown)
	self.keyCount = shown
	self:refresh()
end

-- ---------- watermark ----------
function Host:_watermark(on)
	if on and not self.mark then
		local scope = self.scope:child("watermark")
		local layer = self.window._layers:get("Overlay")
		local pill = Factory.new(scope, "Frame", { Name = "Watermark", BackgroundColor3 = T.Frame, BackgroundTransparency = M.HUD,
			Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X }, layer)
		Factory.corner(scope, pill, "full")
		Factory.padding(scope, pill, 12, 12, 0, 0)
		local label = Factory.text(scope, "TextLabel", { Text = "", FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Text2,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1) }, pill)
		self.mark = { scope = scope, pill = pill, label = label, frames = 0, last = os.clock() }
		local run = Env.services.RunService
		scope:connect(run.Heartbeat, function() self.mark.frames += 1 end)
		local function tick()
			local mark = self.mark
			if not mark then return end
			local now = os.clock()
			local fps = math.floor(mark.frames / math.max(0.001, now - mark.last) + 0.5)
			mark.frames, mark.last = 0, now
			local ping = 0
			pcall(function() ping = math.floor((Env.localPlayer():GetNetworkPing() or 0) * 1000) end)
			label.Text = ("%s  ·  %d fps  ·  %d ms  ·  %s"):format(self.window._title, fps, ping, os.date("%H:%M"))
			scope:delay(0.5, tick)
		end
		tick()
	elseif not on and self.mark then
		self.mark.scope:destroy()
		self.mark = nil
	end
end

-- ---------- visibility ----------
function Host:refresh()
	local window = self.window
	local shellVisible = (window._visible or self.pinned) and not window._loading and not window._destroyed
	local phone = Platform.isPhone(window._layers:guiSize())
	local wantPlayers = shellVisible and self.enabled.Players and not phone
	local wantKeys = shellVisible and self.enabled.Keybinds and not phone and (self.keyCount or 0) > 0
	if wantPlayers or wantKeys or self.enabled.Players or self.enabled.Keybinds then self:ensure() end
	if self.cards.Players then self.cards.Players.card.Visible = wantPlayers end
	if self.cards.Keybinds then self.cards.Keybinds.card.Visible = wantKeys end
	self:_watchPlayers(wantPlayers)
	self:_watermark(shellVisible and self.enabled.Watermark and not phone)
	window._playerOverlayVisible = wantPlayers or nil
end

function Host:setEnabled(kind, on)
	self.enabled[kind] = on == true
	local key = kind == "Players" and "PlayerListEnabled" or (kind == "Keybinds" and "KeybindListEnabled" or "Watermark")
	Prefs.set(key, on == true)
	self:refresh()
end

function Host:setPinned(on)
	self.pinned = on == true
	Prefs.set("OverlaysAlwaysVisible", self.pinned)
	self:refresh()
end

function Host:setTransparency(value)
	self.transparency = math.clamp(tonumber(value) or 0.38, 0.12, 0.8)
	Theme.hudOverride = Overlays.mapTransparency(self.transparency)
	Prefs.set("OverlayTransparency", self.transparency)
	self:restyle()
end

function Host:setScale(value)
	self.scale = math.clamp(tonumber(value) or 1, 0.75, 1.4)
	for _, entry in pairs(self.cards) do entry.scale.Scale = self.scale end
	Prefs.set("OverlayScale", self.scale)
end

function Host:resetPositions()
	for _, entry in pairs(self.cards) do entry.card.Position = entry.default end
	self.positions = {}
	Prefs.set("OverlayPositions", nil)
end

function Host:restyle()
	self.scope:repaint()
end

-- Keeps overlays on screen after a resize.
function Host:clamp()
	local area = self.window._layers:localSize()
	for _, entry in pairs(self.cards) do
		local position = entry.card.Position
		local x = math.clamp(position.X.Scale * area.X + position.X.Offset, WIDTH, area.X)
		local y = math.clamp(position.Y.Scale * area.Y + position.Y.Offset, 0, math.max(0, area.Y - 40))
		entry.card.Position = UDim2.fromOffset(x, y)
	end
end

function Host:export()
	return {
		PlayerListEnabled = self.enabled.Players,
		KeybindListEnabled = self.enabled.Keybinds,
		OverlaysAlwaysVisible = self.pinned,
		OverlayTransparency = self.transparency,
		OverlayScale = self.scale,
		OverlayPositions = self.positions,
		Watermark = self.enabled.Watermark,
	}
end

function Host:apply(prefs)
	if prefs.PlayerListEnabled ~= nil then self.enabled.Players = prefs.PlayerListEnabled == true end
	if prefs.KeybindListEnabled ~= nil then self.enabled.Keybinds = prefs.KeybindListEnabled == true end
	if prefs.OverlaysAlwaysVisible ~= nil then self.pinned = prefs.OverlaysAlwaysVisible == true end
	if prefs.OverlayTransparency ~= nil then self:setTransparency(prefs.OverlayTransparency) end
	if prefs.OverlayScale ~= nil then self:setScale(prefs.OverlayScale) end
	if type(prefs.OverlayPositions) == "table" then
		self.positions = prefs.OverlayPositions
		for key, entry in pairs(self.cards) do entry.card.Position = decodePosition(self.positions[key], entry.default) end
	end
	self:refresh()
end

return Overlays
