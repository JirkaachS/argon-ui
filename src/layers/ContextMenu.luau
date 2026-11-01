--!nocheck
-- The row context menu (DESIGN_V2 7.4), on the shared popover with reuse = "menu". Rows are
-- pooled; a reopen only rebinds them.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Router = require("input/Router")
local Icons = require("icons/Icons")

local T, F, TS = Token.T, Token.F, Token.TS
local ContextMenu = {}

local ROW, WIDTH = 32, 248
-- The pooled view of the shared "menu" content frame: build runs once per window, every later
-- open only rebinds, so the view is looked up by frame instead of living in one open's locals.
local views = setmetatable({}, { __mode = "k" })

local function buildRow(scope, parent)
	local row = Factory.new(scope, "TextButton", {
		Name = "MenuItem",
		BackgroundColor3 = T.Hover,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW),
		ZIndex = 6,
	}, parent)
	Factory.corner(scope, row, 8)
	local icon = Factory.new(scope, "ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(10, 8),
		ImageColor3 = T.Text2,
		ZIndex = 7,
	}, row)
	local label = Factory.text(scope, "TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.new(1, -96, 1, 0),
		FontFace = F.Body,
		TextSize = TS.Body,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7,
	}, row)
	local hint = Factory.text(scope, "TextLabel", {
		Name = "Shortcut",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 60, 1, 0),
		FontFace = F.Key,
		TextSize = TS.Key,
		TextColor3 = T.Dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
	}, row)
	local divider = Factory.new(scope, "Frame", {
		Name = "Divider",
		BackgroundColor3 = T.BorderSoft,
		Size = UDim2.new(1, -12, 0, 1),
		Position = UDim2.fromOffset(6, 0),
		Visible = false,
		ZIndex = 6,
	}, parent)
	return { Root = row, icon = icon, label = label, hint = hint, divider = divider }
end

-- Opens a menu at anchor (GuiObject) or point (Vector2). items: { {Text, Icon, Shortcut, Danger,
-- Disabled, Reason, Callback} | "divider" }, header: { Title, Subtitle }?
function ContextMenu.open(window, at, items, header)
	local host = window._popover
	local state = { items = items, highlight = 0 }
	local menu
	local consumer
	local function close() host:close("menu") end
	-- Keyboard and pad highlight; the pointer's hover uses the same fill.
	local function paintHighlight()
		if not menu or not menu.byIndex then return end
		for index, row in pairs(menu.byIndex) do
			row.Root.BackgroundTransparency = index == state.highlight and 0 or 1
		end
	end
	local function activate(index)
		local item = state.items[index]
		if type(item) ~= "table" or item.Disabled then return end
		close()
		if item.Callback then
			local ok, err = pcall(item.Callback)
			if not ok then warn("[Argon UI] menu item error: " .. tostring(err)) end
		end
	end
	local spec = {
		owner = state,
		kind = "menu",
		reuse = "menu",
		width = WIDTH,
		maxHeight = 420,
		build = function(frame, scope)
			Factory.padding(scope, frame, 6, 6, 6, 6)
			local head = Factory.new(scope, "Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), ZIndex = 5 }, frame)
			local title = Factory.text(scope, "TextLabel", { Name = "Flag", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 16),
				FontFace = F.Key, TextSize = TS.Key, TextColor3 = T.Text2, ZIndex = 6 }, head)
			local subtitle = Factory.text(scope, "TextLabel", { Name = "Default", Position = UDim2.fromOffset(10, 20), Size = UDim2.new(1, -20, 0, 16),
				FontFace = F.Caption, TextSize = TS.Caption, TextColor3 = T.Muted, RichText = true, ZIndex = 6 }, head)
			views[frame] = { scope = scope, frame = frame, head = head, title = title, subtitle = subtitle, rows = {} }
			return Vector2.new(WIDTH, 200)
		end,
		bind = function(frame, scope)
			menu = views[frame]
			menu.byIndex = {}
			local y = 0
			if header then
				menu.head.Visible = true
				menu.title.Text = header.Title or ""
				menu.subtitle.Text = header.Subtitle or ""
				y = 44
			else
				menu.head.Visible = false
			end
			local rowIndex = 0
			for _, row in ipairs(menu.rows) do
				row.Root.Visible = false
				row.divider.Visible = false
			end
			for index, item in ipairs(items) do
				if item == "divider" then
					rowIndex += 1
					local row = menu.rows[rowIndex] or buildRow(scope, frame)
					menu.rows[rowIndex] = row
					row.divider.Visible = true
					row.divider.Position = UDim2.fromOffset(6, y + 4)
					y += 9
				else
					rowIndex += 1
					local row = menu.rows[rowIndex] or buildRow(scope, frame)
					menu.rows[rowIndex] = row
					row.Root.Visible = true
					row.Root.Position = UDim2.fromOffset(0, y)
					menu.byIndex[index] = row
					local text = tostring(item.Text or item.Name or item.Title or "")
					row.label.Text = item.Disabled and item.Reason and (text .. " · " .. tostring(item.Reason)) or text
					row.label.TextColor3 = Token.resolve(item.Disabled and T.Disabled or (item.Danger and T.Danger or T.Text))
					row.hint.Text = item.Shortcut or ""
					Icons.apply(row.icon, item.Icon or "circle", nil)
					row.icon.ImageColor3 = Token.resolve(item.Danger and T.Danger or T.Text2)
					row.icon.Visible = item.Icon ~= nil
					row.Root.BackgroundTransparency = 1
					if row.conn then row.conn:Disconnect() end
					if row.hover then row.hover:Disconnect() end
					if row.leave then row.leave:Disconnect() end
					row.conn = row.Root.MouseButton1Click:Connect(function() activate(index) end)
					row.hover = row.Root.MouseEnter:Connect(function()
						state.highlight = item.Disabled and 0 or index
						paintHighlight()
					end)
					row.leave = row.Root.MouseLeave:Connect(function()
						if state.highlight == index then state.highlight = 0 end
						paintHighlight()
					end)
					y += ROW
				end
			end
			return Vector2.new(WIDTH, y + 12)
		end,
		onClose = function()
			if consumer then consumer.remove() end
		end,
	}
	if typeof(at) == "Instance" then spec.anchor = at else spec.point = at end
	local handle = host:open(spec)
	consumer = Router.layerKey(function(input)
		local key = input.KeyCode and input.KeyCode.Name
		if key == "Down" or key == "Up" or key == "DPadDown" or key == "DPadUp" then
			local step = (key == "Down" or key == "DPadDown") and 1 or -1
			for _ = 1, #items do
				state.highlight = ((state.highlight - 1 + step) % #items) + 1
				if type(items[state.highlight]) == "table" and not items[state.highlight].Disabled then break end
			end
			paintHighlight()
			return true
		elseif (key == "Return" or key == "ButtonA") and state.highlight > 0 then
			activate(state.highlight)
			return true
		end
		return false
	end, 90)
	return handle
end

return ContextMenu
