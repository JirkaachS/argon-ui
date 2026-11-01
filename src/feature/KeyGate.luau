--!nocheck
-- Key gate (Rayfield KeySystem / KeySettings, DESIGN_V2 4.8). Opt-in. The card is painted
-- before anything waits; with Blocking (default) CreateWindow then waits for a valid key, which
-- is the one documented yield in CreateWindow. GrabKeyFromSite fetches in its own thread.

local Env = require("core/Env")
local Util = require("core/Util")
local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Metrics = require("theme/Metrics")
local FS = require("persist/FS")
local Popover = require("layers/Popover")

local T, F, TS = Token.T, Token.F, Token.TS
local KeyGate = {}

function KeyGate.run(window, options)
	local settings = type(options.KeySettings) == "table" and options.KeySettings or {}
	local validKeys = {}
	local function addKeys(value)
		if type(value) == "table" then
			for _, key in ipairs(value) do validKeys[#validKeys + 1] = Util.trim(tostring(key)) end
		elseif value ~= nil then
			validKeys[#validKeys + 1] = Util.trim(tostring(value))
		end
	end
	if not settings.GrabKeyFromSite then addKeys(settings.Key) end
	local validate = options.Validate or settings.Validate
	local function check(text)
		text = Util.trim(tostring(text or ""))
		if text == "" then return false, "Enter a key" end
		if type(validate) == "function" then
			local ok, result, message = pcall(validate, text)
			if not ok then return false, tostring(result) end
			return result == true, message
		end
		for _, key in ipairs(validKeys) do
			if key == text then return true end
		end
		return false, "That key didn't work"
	end
	local config = options.ConfigurationSaving
	local folder = type(config) == "table" and config.FolderName or "ArgonUI"
	local path = tostring(folder) .. "/" .. tostring(settings.FileName or "Key") .. ".key"
	if settings.SaveKey and not settings.GrabKeyFromSite then
		local saved = FS.read(path)
		if saved and check(saved) then return true end
	end

	local accepted = false
	local wasManual = window._loadingManual
	window._loadingManual = true
	local scope = window._scope:child("keygate")
	local layer = window._layers:get("Boot")
	local card = Factory.new(scope, "Frame", { Name = "KeyGate", BackgroundColor3 = T.Raised, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 0), AutomaticSize = Enum.AutomaticSize.Y, Active = true, ZIndex = 20 }, layer)
	Factory.corner(scope, card, Metrics.radius.card)
	Popover.litEdge(scope, card, 0.86)
	Factory.padding(scope, card, 24, 24, 22, 22)
	Factory.list(scope, card, { Padding = UDim.new(0, 10) })
	Factory.text(scope, "TextLabel", { Text = tostring(settings.Title or window._title), FontFace = F.LoaderTitle, TextSize = TS.LoaderTitle,
		Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, ZIndex = 21 }, card)
	Factory.text(scope, "TextLabel", { Text = tostring(settings.Subtitle or "Enter your key to continue"), FontFace = F.Body, TextSize = TS.Body,
		TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, ZIndex = 21 }, card)
	local field = Factory.text(scope, "TextBox", { Name = "Key", Text = "", PlaceholderText = "Key", FontFace = F.Value, TextSize = TS.Value,
		BackgroundColor3 = T.Well, BackgroundTransparency = 0, ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, ZIndex = 21 }, card)
	Factory.corner(scope, field, Metrics.radius.control)
	Factory.padding(scope, field, 12, 12, 0, 0)
	local stroke = Factory.stroke(scope, field, T.Border, 0, 1)
	local message = Factory.text(scope, "TextLabel", { Name = "Message", Text = "", FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Danger,
		Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4, Visible = false, ZIndex = 21 }, card)
	local remember = settings.SaveKey == true
	local rememberButton = Factory.text(scope, "TextButton", { Name = "Remember", Text = "", FontFace = F.Body, TextSize = TS.Body,
		Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 5, ZIndex = 21 }, card)
	local function renderRemember()
		rememberButton.Text = (remember and "☑  " or "☐  ") .. "Remember this key on this device"
	end
	renderRemember()
	scope:connect(rememberButton.MouseButton1Click, function()
		remember = not remember
		renderRemember()
	end)
	if settings.Note then
		Factory.text(scope, "TextLabel", { Text = tostring(settings.Note), FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted,
			TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 6, ZIndex = 21 }, card)
	end
	local row = Factory.new(scope, "Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 7, ZIndex = 21 }, card)
	Factory.list(scope, row, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8) })
	local function button(text, primary, order)
		local b = Factory.text(scope, "TextButton", { Text = text, FontFace = F.Button, TextSize = TS.Button, TextColor3 = primary and T.OnAccent or T.Text,
			BackgroundColor3 = primary and T.Accent or T.Active, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
			TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = order, ZIndex = 22 }, row)
		Factory.corner(scope, b, Metrics.radius.control)
		Factory.padding(scope, b, 16, 16, 0, 0)
		return b
	end
	local link = options.GetKeyLink or settings.GetKeyLink
	if link then
		local get = button("Get key", false, 1)
		scope:connect(get.MouseButton1Click, function()
			if Env.setClipboard(tostring(link)) then
				get.Text = "Link copied"
				task.delay(1.5, function() if get.Parent then get.Text = "Get key" end end)
			else
				window._toastHost:copySheet(tostring(link))
			end
		end)
	end
	local continue = button("Continue", true, 2)
	local busy = false

	local function finish()
		accepted = true
		if remember and FS.available() then FS.write(path, Util.trim(field.Text)) end
		scope:destroy()
		window._loadingManual = wasManual
		if window._loader then
			window._loader:progressed()
			window._loader:evaluate()
		end
	end
	local function submit()
		if busy or accepted then return end
		busy = true
		continue.Text = "Checking…"
		task.spawn(function()
			local ok, why = check(field.Text)
			busy = false
			if ok then
				finish()
				return
			end
			continue.Text = "Continue"
			stroke.Color = Token.resolve(T.Danger)
			message.Text = why or "That key didn't work"
			message.Visible = true
			if not Motion.reduced then
				local base = card.Position
				for index, dx in ipairs({ 6, -6, 6, -6, 0 }) do
					task.delay(index * 0.06, function()
						if card.Parent then card.Position = base + UDim2.fromOffset(dx, 0) end
					end)
				end
			end
		end)
	end
	scope:connect(continue.MouseButton1Click, submit)
	scope:connect(field.FocusLost, function(enter) if enter then submit() end end)

	if settings.GrabKeyFromSite and type(settings.Key) == "string" then
		task.spawn(function()
			local ok, body = pcall(function() return game:HttpGet(settings.Key) end)
			if ok and type(body) == "string" then addKeys(body) end
		end)
	end
	window._keyGate = { card = card, field = field, submit = submit, accepted = function() return accepted end }

	if options.Blocking ~= false and settings.Blocking ~= false and coroutine.isyieldable() then
		while not accepted and not window._destroyed do task.wait(0.1) end
	end
	return accepted
end

return KeyGate
