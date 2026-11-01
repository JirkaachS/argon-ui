--!nocheck
-- The shared row anatomy (DESIGN_V2 section 5): Root (the hit target), an inset divider, the
-- title, and on demand the changed dot, tooltip marker, lock chip and description. Rows have
-- no fill, stroke or corner of their own; the section platter owns one pooled hover frame.

local Env = require("core/Env")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")

local T, F, TS = Token.T, Token.F, Token.TS
local RowView = {}

local function textWidth(text, size)
	local service = Env.services.TextService
	local ok, bounds = pcall(function()
		return service:GetTextSize(text, size, Env.enum("Font", "Roboto", "Gotham"), Vector2.new(2000, 100))
	end)
	if ok and bounds then return math.ceil(bounds.X * 1.04) end
	return #text * size * 0.55
end
RowView.textWidth = textWidth

-- opts: { display = bool (Frame root, no hover/press), title = false?, reserve = px, height = px? }
function RowView.build(el, scope, opts)
	local band = opts.height or Metrics.get("row")
	local padH = Metrics.get("padH")
	local root = Factory.new(scope, opts.display and "Frame" or "TextButton", {
		Name = "Control",
		BackgroundColor3 = T.Hover,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, band),
		LayoutOrder = el._order or 0,
		ClipsDescendants = false,
	})
	if not opts.display then Env.try(root, "Selectable", false) end
	local view = { Root = root, band = band, padH = padH, reserve = opts.reserve or 0, opts = opts }
	if el._inRow == nil then
		view.Divider = Factory.new(scope, "Frame", {
			Name = "Divider",
			BackgroundColor3 = T.BorderSoft,
			Size = UDim2.new(1, -padH * 2, 0, 1),
			Position = UDim2.fromOffset(padH, 0),
			Visible = false,
		}, root)
	end
	if opts.title ~= false then
		view.Title = Factory.text(scope, "TextLabel", {
			Name = "Title",
			Text = el.Name,
			FontFace = F.Label,
			TextSize = TS.Label,
			TextColor3 = T.Text,
			Position = UDim2.fromOffset(padH, 0),
			Size = UDim2.new(1, -RowView.titleInset(view), 0, band),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, root)
	end
	el.Root = root
	el._title = view.Title
	el._view = view
	return view
end

function RowView.titleInset(view)
	local reserve = view.reserve or 0
	return view.padH * 2 + (reserve > 0 and reserve + 16 or 0)
end

-- Top offset that vertically centres an object of height h on the title band.
function RowView.bandY(view, h)
	return math.floor((view.band - h) / 2)
end

-- Places a control part in the right-aligned control column.
function RowView.control(view, inst, width, height, rightInset)
	inst.AnchorPoint = Vector2.new(1, 0)
	inst.Position = UDim2.new(1, -(view.padH + (rightInset or 0)), 0, RowView.bandY(view, height))
	inst.Size = UDim2.fromOffset(width, height)
	return inst
end

function RowView.setReserve(el, reserve)
	local view = el._view
	if not view then return end
	view.reserve = reserve
	if view.Title then view.Title.Size = UDim2.new(1, -RowView.titleInset(view), 0, view.band) end
	if view.Description then view.Description.Size = UDim2.new(1, -RowView.titleInset(view), 0, 0) end
	RowView.layoutMarkers(el)
end

-- Positions the changed dot, tooltip marker and lock chip right after the title text.
function RowView.layoutMarkers(el)
	local view = el._view
	if not view then return end
	if not view.Title then
		-- title-less rows (labels, callouts, images): the lock sits at the right edge
		local lock = el._lock
		if lock and lock.Icon then
			local mid = math.floor(view.band / 2)
			lock.Icon.AnchorPoint = Vector2.new(1, 0)
			lock.Icon.Position = UDim2.new(1, -view.padH, 0, mid - 7)
			lock.Badge.AnchorPoint = Vector2.new(1, 0)
			lock.Badge.Position = UDim2.new(1, -(view.padH + 20), 0, mid - 10)
		end
		return
	end
	local x = view.padH + math.min(textWidth(view.Title.Text, Metrics.textSize("Label")),
		math.max(0, view.Root.AbsoluteSize.X - RowView.titleInset(view))) + 6
	local mid = math.floor(view.band / 2)
	if view.Changed and view.Changed.Visible then
		view.Changed.Position = UDim2.fromOffset(x, mid - 3)
		x += 12
	end
	if view.TipMarker and view.TipMarker.Visible then
		view.TipMarker.Position = UDim2.fromOffset(x, mid - 7)
		x += 20
	end
	if el._lock and el._lock.Icon then
		el._lock.Icon.Position = UDim2.fromOffset(x, mid - 7)
		el._lock.Badge.Position = UDim2.fromOffset(x + 18, mid - 10)
	end
end

function RowView.setDescription(el, text)
	local view = el._view
	if not view then return end
	local root = view.Root
	if text and text ~= "" then
		local scope = el._scope
		if not view.Description then
			view.Description = Factory.text(scope, "TextLabel", {
				Name = "Description",
				FontFace = F.Body,
				TextSize = TS.Body,
				TextColor3 = T.Muted,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				TextYAlignment = Enum.TextYAlignment.Top,
			}, root)
			view.DescPad = Factory.new(scope, "UIPadding", { PaddingBottom = UDim.new(0, Metrics.get("padV")) }, root)
		end
		local desc = view.Description
		desc.Visible = true
		desc.Text = text
		desc.Position = UDim2.fromOffset(view.padH, view.band - 12)
		desc.Size = UDim2.new(1, -RowView.titleInset(view), 0, 0)
		view.DescPad.PaddingBottom = UDim.new(0, Metrics.get("padV"))
		root.Size = UDim2.new(1, 0, 0, view.band + 12)
		if view.autoBefore == nil then view.autoBefore = root.AutomaticSize or Enum.AutomaticSize.None end
		root.AutomaticSize = Enum.AutomaticSize.Y
		el._description = desc
	else
		if view.Description then
			view.Description.Visible = false
			view.DescPad.PaddingBottom = UDim.new(0, 0)
		end
		-- undo only what the description changed: a self-sizing row keeps its AutomaticSize
		if view.autoBefore ~= nil then
			root.AutomaticSize = view.autoBefore
			view.autoBefore = nil
		end
		if root.AutomaticSize == nil or root.AutomaticSize == Enum.AutomaticSize.None then
			root.Size = UDim2.new(1, 0, 0, view.band)
		end
		el._description = nil
	end
end

function RowView.setTooltip(el, text)
	local view = el._view
	if not view or not view.Title then return end
	if text and text ~= "" then
		if not view.TipMarker then
			view.TipMarker = Factory.new(el._scope, "ImageButton", {
				Name = "TipMarker",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(14, 14),
				ImageColor3 = T.Text2,
			}, view.Root)
			Icons.apply(view.TipMarker, "info", el._scope, T.Text2)
			el._scope:connect(view.TipMarker.MouseButton1Click, function()
				local window = el._window
				if window and window._tooltipHost and el._tooltipText then
					window._tooltipHost:schedule(view.Title, el._tooltipText, "press")
				end
			end)
		end
		view.TipMarker.Visible = true
		el._tipMarker = view.TipMarker
	elseif view.TipMarker then
		view.TipMarker.Visible = false
		el._tipMarker = view.TipMarker
	end
	RowView.layoutMarkers(el)
end

function RowView.setChanged(el, changed)
	local view = el._view
	if not view or not view.Title then return end
	if changed and not view.Changed then
		view.Changed = Factory.new(el._scope, "TextButton", {
			Name = "Changed",
			BackgroundColor3 = T.AccentText,
			Size = UDim2.fromOffset(6, 6),
			Visible = false,
		}, view.Root)
		Factory.corner(el._scope, view.Changed, "full")
		el._scope:connect(view.Changed.MouseButton1Click, function() el:_resetWithUndo() end)
	end
	if view.Changed then
		view.Changed.Visible = changed == true
		RowView.layoutMarkers(el)
	end
end

-- Lock chip (icon + reason) and the scrim over the control column (DESIGN_V2 section 5).
function RowView.setLock(el)
	local view = el._view
	if not view then return end
	local lock = el._lock
	if el.Locked then
		local scope = el._scope
		if not lock then
			local scrim = Factory.new(scope, "TextButton", {
				Name = "LockScrim",
				BackgroundColor3 = T.Surface,
				BackgroundTransparency = 0.35,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, math.max(view.reserve + view.padH + 8, 64), 0, view.band),
				ZIndex = 20,
			}, view.Root)
			local icon = Factory.new(scope, "ImageLabel", {
				Name = "LockIcon",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(14, 14),
				ZIndex = 21,
			}, view.Root)
			Icons.apply(icon, "lock", scope, T.Text2)
			local badge = Factory.new(scope, "Frame", {
				Name = "LockReason",
				BackgroundColor3 = T.Active,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 20),
				ZIndex = 21,
			}, view.Root)
			Factory.corner(scope, badge, 6)
			Factory.padding(scope, badge, 6, 6, 0, 0)
			Factory.new(scope, "UISizeConstraint", { MinSize = Vector2.new(0, 20), MaxSize = Vector2.new(220, 20) }, badge)
			local label = Factory.text(scope, "TextLabel", {
				Name = "Label",
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromScale(0, 1),
				FontFace = F.Caption,
				TextSize = TS.Caption,
				TextColor3 = T.Text2,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 22,
			}, badge)
			lock = { Root = scrim, Badge = badge, Label = label, Icon = icon }
			el._lock = lock
			scope:connect(scrim.MouseButton1Click, function() el:_lockedPoke() end)
		end
		local reason = el.LockReason
		lock.Badge.Visible = reason ~= nil and reason ~= ""
		lock.Label.Text = reason or ""
		if view.Title then view.Title.TextColor3 = Token.resolve(T.Text2) end
		RowView.layoutMarkers(el)
	elseif lock then
		lock.Root:Destroy()
		lock.Badge:Destroy()
		lock.Icon:Destroy()
		el._lock = nil
		if view.Title then view.Title.TextColor3 = Token.resolve(el._disabled and T.Disabled or T.Text) end
	end
end

return RowView
