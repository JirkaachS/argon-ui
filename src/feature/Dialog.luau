--!nocheck
-- Dialog / Popup, Confirm and Prompt (DESIGN_V2 7.3). The scrim covers the window area only,
-- Enter activates the focused button (its keycap shows which), a destructive confirm focuses
-- Cancel first, and every way of dismissing (close key, outside click, x) calls OnCancel (D18).

local Util = require("core/Util")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Metrics = require("theme/Metrics")
local Icons = require("icons/Icons")
local Router = require("input/Router")
local Popover = require("layers/Popover")

local T, F, TS = Token.T, Token.F, Token.TS
local Dialog = {}

local VARIANTS = {
	Primary = { fill = "Accent", ink = "OnAccent" },
	Danger = { fill = "Danger", ink = "OnStatus" },
	Secondary = { fill = "Active", ink = "Text" },
	Ghost = { fill = nil, ink = "AccentText" },
}

function Dialog.dialog(window, config)
	config = type(config) == "table" and config or { Content = tostring(config or "") }
	local layers = window._layers
	local layer = layers:get("Modal")
	local scope = window._scope:child("dialog")
	local area = layers:localSize()
	local root = Factory.new(scope, "Frame", { Name = "Dialog", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1 })
	local scrim = Factory.new(scope, "TextButton", { Name = "Scrim", BackgroundColor3 = T.Scrim, BackgroundTransparency = 1, ZIndex = 1 }, root)
	local main = rawget(window, "Main")
	if main and main.Visible then
		scrim.Position = main.Position
		scrim.Size = main.Size
		Factory.corner(scope, scrim, Metrics.radius.window)
	else
		scrim.Size = UDim2.fromScale(1, 1)
	end
	local width = math.min(400, area.X - 32)
	local panel = Factory.new(scope, "Frame", {
		Name = "Panel", BackgroundColor3 = T.Raised, AnchorPoint = Vector2.new(0.5, 0.5), Active = true,
		Size = UDim2.fromOffset(width, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2,
	}, root)
	if main and main.Visible then
		panel.Position = UDim2.fromOffset(main.Position.X.Offset + main.Size.X.Offset / 2, main.Position.Y.Offset + main.Size.Y.Offset / 2)
	else
		panel.Position = UDim2.fromScale(0.5, 0.5)
	end
	Factory.corner(scope, panel, Metrics.radius.dialog)
	Popover.litEdge(scope, panel, 0.86)
	local uiscale = Factory.new(scope, "UIScale", { Scale = 1 }, panel)
	Factory.padding(scope, panel, 20, 20, 20, 20)
	Factory.list(scope, panel, { Padding = UDim.new(0, 8) })
	local title = Factory.text(scope, "TextLabel", { Name = "Title", Text = tostring(config.Title or "Confirm action"), FontFace = F.Dialog,
		TextSize = TS.Dialog, Size = UDim2.new(1, -28, 0, 24), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 3 }, panel)
	local body = Factory.text(scope, "TextLabel", { Name = "Body", Text = tostring(config.Content or config.Description or ""), FontFace = F.Body,
		TextSize = TS.Label, TextColor3 = T.Text2, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, ZIndex = 3 }, panel)
	body.Visible = body.Text ~= ""
	local close = Factory.new(scope, "ImageButton", { Name = "Close", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 14), Size = UDim2.fromOffset(20, 20), ZIndex = 5 }, panel)
	Icons.apply(close, "x", scope, T.Text2)
	local extra = Factory.new(scope, "Frame", { Name = "Extra", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 3 }, panel)
	if config.CopyText then
		local box = Factory.text(scope, "TextBox", { Name = "CopyBox", Text = tostring(config.CopyText), FontFace = F.Key, TextSize = TS.Key,
			BackgroundColor3 = T.Well, BackgroundTransparency = 0, ClearTextOnFocus = false, TextEditable = false, TextWrapped = true,
			MultiLine = true, Size = UDim2.new(1, 0, 0, 96), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4 }, extra)
		Factory.corner(scope, box, 10)
		Factory.padding(scope, box, 8, 8, 6, 6)
	end
	local row = Factory.new(scope, "Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 4, ZIndex = 3 }, panel)
	Factory.list(scope, row, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8) })

	local dialog = { Root = root, Panel = panel, Title = title, Body = body, Extra = extra, Visible = false, _buttons = {}, _focus = 1, _scope = scope }
	local entry = { kind = "dialog", id = "dialog" }
	local consumer
	local closing = false

	local function renderFocus()
		for index, button in ipairs(dialog._buttons) do
			if button.cap then button.cap.Visible = index == dialog._focus end
		end
	end

	function dialog:Close(reason)
		if not self.Visible or closing then return end
		closing = true
		self.Visible = false
		layers:pop(entry)
		if consumer then consumer.remove() consumer = nil end
		if reason ~= "button" and type(config._onDismiss) == "function" then config._onDismiss(reason) end
		Motion.tween(scrim, "dialogOut", { BackgroundTransparency = 1 })
		Motion.tween(uiscale, "dialogOut", { Scale = 0.96 })
		task.delay(0.2, function()
			closing = false
			if not root.Parent then return end
			root.Visible = false
			if config.Transient ~= false then scope:destroy() end
		end)
	end

	function dialog:Show()
		if not root.Parent or self.Visible then return end
		self.Visible = true
		root.Visible = true
		scrim.BackgroundTransparency = 1
		Motion.tween(scrim, "scrim", { BackgroundTransparency = 0.45 })
		if not Motion.reduced then
			uiscale.Scale = 0.95
			Motion.tween(uiscale, "dialogIn", { Scale = 1 })
		end
		entry.close = function(reason) dialog:Close(reason) end
		layers:push(entry)
		consumer = Router.layerKey(function(input)
			if layers:top() ~= entry then return false end
			local key = input.KeyCode and input.KeyCode.Name
			if key == "Return" or key == "ButtonA" then
				local button = dialog._buttons[dialog._focus]
				if button then button.activate() end
				return true
			elseif key == "Tab" or key == "Left" or key == "Right" or key == "DPadLeft" or key == "DPadRight" then
				local step = (key == "Left" or key == "DPadLeft") and -1 or 1
				dialog._focus = ((dialog._focus - 1 + step) % math.max(1, #dialog._buttons)) + 1
				renderFocus()
				return true
			end
			return false
		end, 85)
	end

	function dialog:Destroy()
		layers:pop(entry)
		if consumer then consumer.remove() end
		scope:destroy()
	end

	local buttons = config.Buttons or { { Title = "Okay", Variant = "Primary" } }
	for index, spec in ipairs(buttons) do
		local variant = tostring(spec.Variant or "")
		if spec.Primary then variant = "Primary" end
		if spec.Danger then variant = "Danger" end
		local style = VARIANTS[variant] or VARIANTS.Secondary
		local button = Factory.text(scope, "TextButton", {
			Text = tostring(spec.Title or spec.Name or "Button"), FontFace = F.Button, TextSize = TS.Button,
			TextColor3 = T[style.ink], BackgroundColor3 = style.fill and T[style.fill] or T.Raised,
			BackgroundTransparency = style.fill and 0 or 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
			TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = index, ZIndex = 4,
		}, row)
		Factory.corner(scope, button, Metrics.radius.control)
		Factory.padding(scope, button, 16, 16, 0, 0)
		local cap = Factory.text(scope, "TextLabel", { Name = "EnterCap", Text = "↵", FontFace = F.Key, TextSize = TS.Key,
			TextColor3 = T[style.ink], AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 12, 0.5, 0),
			Size = UDim2.fromOffset(12, 16), Visible = false, ZIndex = 5 }, button)
		local fired = false
		local function activate()
			if fired and spec.AutoClose ~= false then return end
			fired = true
			Util.xcall(spec.Callback, "Dialog button", nil, dialog)
			if spec.AutoClose ~= false then dialog:Close("button") else fired = false end
		end
		scope:connect(button.MouseButton1Click, activate)
		dialog._buttons[index] = { button = button, cap = cap, activate = activate }
		if spec.Focus then dialog._focus = index end
	end
	if config.FocusButton then dialog._focus = config.FocusButton end
	if not config.FocusButton and #dialog._buttons > 0 and not config._cancelFirst then dialog._focus = #dialog._buttons end
	renderFocus()

	scope:connect(close.MouseButton1Click, function() dialog:Close("close") end)
	if config.DismissOnOutside ~= false then
		scope:connect(scrim.MouseButton1Click, function() dialog:Close("outside") end)
	end
	root.Parent = layer
	if config.Show ~= false then dialog:Show() end
	return dialog
end

function Dialog.confirm(window, config)
	config = type(config) == "table" and config or { Content = tostring(config or "Are you sure?") }
	local confirmed = false
	local cancelled = false
	local function cancel()
		if confirmed or cancelled then return end
		cancelled = true
		Util.xcall(config.OnCancel, "Confirm OnCancel", nil)
	end
	local variant = config.Variant or "Danger"
	return Dialog.dialog(window, {
		Title = config.Title or "Confirm",
		Content = config.Content or config.Description or "This cannot be undone.",
		Transient = config.Transient,
		DismissOnOutside = config.DismissOnOutside,
		_cancelFirst = variant == "Danger",
		FocusButton = variant == "Danger" and 1 or 2,
		_onDismiss = cancel,
		Buttons = {
			{ Title = config.CancelText or "Cancel", Callback = cancel },
			{ Title = config.ConfirmText or "Confirm", Variant = variant, Callback = function()
				if confirmed or cancelled then return end
				confirmed = true
				Util.xcall(config.OnConfirm or config.Callback, "Confirm", nil)
			end },
		},
	})
end

-- A dialog with a text field and live validation (DESIGN_V2 7.3).
function Dialog.prompt(window, config)
	config = type(config) == "table" and config or {}
	local submitted, cancelled = false, false
	local box, message, dialog
	local function value() return box and box.Text or "" end
	local function check()
		if type(config.Validate) ~= "function" then return true end
		-- Validate returns true or nothing to accept; false (plus a message) or a message string rejects
		local ok, result, why = pcall(config.Validate, value())
		if not ok then return false, tostring(result) end
		if type(result) == "string" then return false, result end
		return result ~= false, why
	end
	local function cancel()
		if submitted or cancelled then return end
		cancelled = true
		Util.xcall(config.OnCancel, "Prompt OnCancel", nil)
	end
	dialog = Dialog.dialog(window, {
		Title = config.Title or "Enter a value",
		Content = config.Content or config.Description,
		_onDismiss = cancel,
		Show = false,
		Buttons = {
			{ Title = config.CancelText or "Cancel", Callback = cancel },
			{ Title = config.SubmitText or "Save", Variant = "Primary", AutoClose = false, Callback = function()
				local ok, why = check()
				if not ok then
					message.Text = why or "That value is not valid"
					message.Visible = true
					return
				end
				submitted = true
				dialog:Close("button")
				Util.xcall(config.OnSubmit or config.Callback, "Prompt", nil, value())
			end },
		},
	})
	local scope = dialog._scope:child("prompt")
	box = Factory.text(scope, "TextBox", { Name = "Field", Text = tostring(config.Default or ""), PlaceholderText = tostring(config.Placeholder or ""),
		FontFace = F.Body, TextSize = TS.Label, BackgroundColor3 = T.Well, BackgroundTransparency = 0, ClearTextOnFocus = false,
		PlaceholderColor3 = Token.resolve(T.Dim), Size = UDim2.new(1, 0, 0, 36), ZIndex = 4 }, dialog.Extra)
	Factory.corner(scope, box, Metrics.radius.control)
	Factory.padding(scope, box, 12, 12, 0, 0)
	local stroke = Factory.stroke(scope, box, T.Border, 0, 1)
	message = Factory.text(scope, "TextLabel", { Name = "Message", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Danger,
		Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 16), Visible = false, ZIndex = 4 }, dialog.Extra)
	scope:connect(box:GetPropertyChangedSignal("Text"), function()
		local ok, why = check()
		stroke.Color = Token.resolve(ok and T.Border or T.Danger)
		message.Visible = not ok and why ~= nil
		message.Text = why or ""
	end)
	scope:connect(box.FocusLost, function(enter)
		if enter then dialog._buttons[2].activate() end
	end)
	dialog.Field = box
	dialog:Show()
	return dialog
end

return Dialog
