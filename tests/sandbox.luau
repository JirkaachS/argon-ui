--!nocheck
-- Roblox API sandbox so argon-ui.luau can run outside Roblox under Lune.
-- Only what the library touches is implemented, but enough of it behaves like the engine
-- (frame stepping, computed AbsoluteSize/AbsolutePosition, a class hierarchy, recursive
-- Destroy, the full enums the library reads) that layout, the scheduler, the loader, timers
-- and the input router can be exercised for real.

local sandbox = {}

-- ---------- datatypes ----------
local function class(name, fields)
	local meta = {}
	meta.__index = meta
	meta.__tostring = function(self)
		local parts = {}
		for _, key in ipairs(fields) do parts[#parts + 1] = tostring(self[key]) end
		return name .. "(" .. table.concat(parts, ", ") .. ")"
	end
	meta.__eq = function(a, b)
		for _, key in ipairs(fields) do
			if a[key] ~= b[key] then return false end
		end
		return true
	end
	return meta
end

local UDim = class("UDim", { "Scale", "Offset" })
local function newUDim(scale, offset)
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDim)
end
UDim.new = newUDim
UDim.__add = function(a, b) return newUDim(a.Scale + b.Scale, a.Offset + b.Offset) end

local UDim2 = class("UDim2", { "X", "Y" })
local function newUDim2(xs, xo, ys, yo)
	if type(xs) == "table" and getmetatable(xs) == UDim then
		return setmetatable({ X = xs, Y = xo }, UDim2)
	end
	return setmetatable({ X = newUDim(xs, xo), Y = newUDim(ys, yo) }, UDim2)
end
UDim2.__add = function(a, b) return newUDim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2.__sub = function(a, b) return newUDim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end

local Vector2 = class("Vector2", { "X", "Y" })
local newVector2
function newVector2(x, y)
	x, y = x or 0, y or 0
	local self = setmetatable({ X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }, Vector2)
	return self
end
Vector2.__index = function(self, key)
	if key == "Unit" then
		local m = rawget(self, "Magnitude")
		if m > 0 then return newVector2(self.X / m, self.Y / m) end
		return self
	end
	return rawget(Vector2, key)
end
Vector2.__add = function(a, b) return newVector2(a.X + b.X, a.Y + b.Y) end
Vector2.__sub = function(a, b) return newVector2(a.X - b.X, a.Y - b.Y) end
Vector2.__mul = function(a, b)
	if type(a) == "number" then return newVector2(b.X * a, b.Y * a) end
	if type(b) == "number" then return newVector2(a.X * b, a.Y * b) end
	return newVector2(a.X * b.X, a.Y * b.Y)
end
Vector2.__div = function(a, b)
	if type(b) == "number" then return newVector2(a.X / b, a.Y / b) end
	return newVector2(a.X / b.X, a.Y / b.Y)
end
Vector2.__unm = function(a) return newVector2(-a.X, -a.Y) end

local Vector3 = class("Vector3", { "X", "Y", "Z" })
local function newVector3(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, Vector3)
end

local Color3 = class("Color3", { "R", "G", "B" })
local function newColor3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta > 0 then
		if max == r then h = ((g - b) / delta) % 6
		elseif max == g then h = (b - r) / delta + 2
		else h = (r - g) / delta + 4 end
		h /= 6
	end
	return h, max == 0 and 0 or delta / max, max
end
function Color3:Lerp(other, t)
	return newColor3(self.R + (other.R - self.R) * t, self.G + (other.G - self.G) * t, self.B + (other.B - self.B) * t)
end
function Color3:ToHex()
	local function byte(v) return math.clamp(math.floor(v * 255 + 0.5), 0, 255) end
	return ("%02x%02x%02x"):format(byte(self.R), byte(self.G), byte(self.B))
end

local Rect = class("Rect", { "Min", "Max" })
local NumberSequence = class("NumberSequence", { "Keypoints" })
local ColorSequence = class("ColorSequence", { "Keypoints" })

-- ---------- Enum ----------
sandbox.strictEnums = false
local function enumItem(enumName, name, value)
	return setmetatable({ Name = name, Value = value, EnumType = enumName }, {
		__tostring = function() return ("Enum.%s.%s"):format(enumName, name) end,
	})
end

local function buildEnum(enumName, names)
	local items, byName = {}, {}
	for index, name in ipairs(names) do
		local item = enumItem(enumName, name, index - 1)
		byName[name] = item
		items[index] = item
	end
	return setmetatable({}, {
		__index = function(_, key)
			if key == "GetEnumItems" then
				return function() return items end
			end
			local item = byName[key]
			if item == nil and sandbox.strictEnums then
				error(("%s is not a valid member of Enum.%s"):format(tostring(key), enumName), 2)
			end
			return item
		end,
	})
end

local KEYS = {
	"Unknown", "Backspace", "Tab", "Clear", "Return", "Pause", "Escape", "Space", "QuotedDouble", "Hash", "Dollar",
	"Percent", "Ampersand", "Quote", "LeftParenthesis", "RightParenthesis", "Asterisk", "Plus", "Comma", "Minus",
	"Period", "Slash", "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Colon",
	"Semicolon", "LessThan", "Equals", "GreaterThan", "Question", "At", "LeftBracket", "BackSlash", "RightBracket",
	"Caret", "Underscore", "Backquote", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
	"P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "LeftCurly", "Pipe", "RightCurly", "Tilde", "Delete",
	"KeypadZero", "KeypadOne", "KeypadTwo", "Up", "Down", "Right", "Left", "Insert", "Home", "End", "PageUp",
	"PageDown", "LeftShift", "RightShift", "LeftMeta", "RightMeta", "LeftAlt", "RightAlt", "LeftControl",
	"RightControl", "CapsLock", "NumLock", "ScrollLock", "LeftSuper", "RightSuper", "Mode", "Compose", "Help",
	"Print", "SysReq", "Break", "Menu", "Power", "Euro", "Undo",
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
	"ButtonX", "ButtonY", "ButtonA", "ButtonB", "ButtonR1", "ButtonL1", "ButtonR2", "ButtonL2", "ButtonR3",
	"ButtonL3", "ButtonStart", "ButtonSelect", "DPadLeft", "DPadRight", "DPadUp", "DPadDown", "Thumbstick1", "Thumbstick2",
}

local Enum = {
	Font = buildEnum("Font", { "Legacy", "Arial", "SourceSans", "SourceSansBold", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "Roboto", "RobotoMono", "RobotoCondensed", "Ubuntu", "Oswald", "Sarpanch", "BuilderSans", "Montserrat" }),
	TextXAlignment = buildEnum("TextXAlignment", { "Left", "Center", "Right" }),
	TextYAlignment = buildEnum("TextYAlignment", { "Top", "Center", "Bottom" }),
	TextTruncate = buildEnum("TextTruncate", { "None", "AtEnd", "SplitWord" }),
	AutomaticSize = buildEnum("AutomaticSize", { "None", "X", "Y", "XY" }),
	SortOrder = buildEnum("SortOrder", { "Name", "Custom", "LayoutOrder" }),
	FillDirection = buildEnum("FillDirection", { "Horizontal", "Vertical" }),
	ScrollingDirection = buildEnum("ScrollingDirection", { "X", "Y", "XY" }),
	ZIndexBehavior = buildEnum("ZIndexBehavior", { "Global", "Sibling" }),
	EasingStyle = buildEnum("EasingStyle", { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" }),
	EasingDirection = buildEnum("EasingDirection", { "In", "Out", "InOut" }),
	ScaleType = buildEnum("ScaleType", { "Stretch", "Slice", "Tile", "Fit", "Crop" }),
	ResamplerMode = buildEnum("ResamplerMode", { "Default", "Pixelated" }),
	UserInputType = buildEnum("UserInputType", { "MouseButton1", "MouseButton2", "MouseButton3", "MouseWheel", "MouseMovement", "Touch", "Keyboard", "Focus", "Accelerometer", "Gyro", "Gamepad1", "Gamepad2", "TextInput", "InputMethod", "None" }),
	UserInputState = buildEnum("UserInputState", { "Begin", "Change", "End", "Cancel", "None" }),
	AnimationPriority = buildEnum("AnimationPriority", { "Core", "Idle", "Movement", "Action" }),
	ApplyStrokeMode = buildEnum("ApplyStrokeMode", { "Contextual", "Border" }),
	SwipeDirection = buildEnum("SwipeDirection", { "Right", "Left", "Up", "Down", "None" }),
	KeyCode = buildEnum("KeyCode", KEYS),
	FontWeight = buildEnum("FontWeight", { "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" }),
	FontStyle = buildEnum("FontStyle", { "Normal", "Italic" }),
	HorizontalAlignment = buildEnum("HorizontalAlignment", { "Center", "Left", "Right" }),
	VerticalAlignment = buildEnum("VerticalAlignment", { "Center", "Top", "Bottom" }),
	ContextActionResult = buildEnum("ContextActionResult", { "Pass", "Sink" }),
	ContextActionPriority = buildEnum("ContextActionPriority", { "Low", "Medium", "High" }),
	ThumbnailType = buildEnum("ThumbnailType", { "HeadShot", "AvatarBust", "AvatarThumbnail" }),
	ThumbnailSize = buildEnum("ThumbnailSize", { "Size48x48", "Size100x100", "Size420x420" }),
	ScreenInsets = buildEnum("ScreenInsets", { "None", "DeviceSafeInsets", "CoreUISafeInsets", "TopbarSafeInsets" }),
	PreferredInput = buildEnum("PreferredInput", { "KeyboardAndMouse", "Touch", "Gamepad" }),
	UIFlexMode = buildEnum("UIFlexMode", { "None", "Grow", "Shrink", "Fill", "Custom" }),
	UIFlexAlignment = buildEnum("UIFlexAlignment", { "None", "Fill", "SpaceAround", "SpaceBetween", "SpaceEvenly" }),
	ElasticBehavior = buildEnum("ElasticBehavior", { "WhenScrollable", "Always", "Never" }),
	TextDirection = buildEnum("TextDirection", { "Auto", "LeftToRight", "RightToLeft" }),
}
Enum.ContextActionPriority.High.Value = 3000
Enum.ContextActionPriority.Medium.Value = 2000
Enum.ContextActionPriority.Low.Value = 1000

-- ---------- signals ----------
local Signal = {}
Signal.__index = Signal
local function newSignal()
	return setmetatable({ _handlers = {} }, Signal)
end
local function disconnect(connection)
	if not connection.Connected then return end
	connection.Connected = false
	local list = connection._signal._handlers
	for index, entry in ipairs(list) do
		if entry == connection then table.remove(list, index) break end
	end
end
function Signal:Connect(handler)
	local connection = { Connected = true, _handler = handler, _signal = self }
	connection.Disconnect = disconnect
	connection.Destroy = disconnect
	table.insert(self._handlers, connection)
	return connection
end
Signal.ConnectParallel = Signal.Connect
function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		disconnect(connection)
		handler(...)
	end)
	return connection
end
function Signal:Fire(...)
	for _, connection in ipairs(table.clone(self._handlers)) do
		if connection.Connected then
			local ok, err = pcall(connection._handler, ...)
			if not ok then sandbox.signalErrors[#sandbox.signalErrors + 1] = tostring(err) end
		end
	end
end
function Signal:Wait()
	sandbox.yields += 1
	return nil
end
function Signal:DisconnectAll()
	for _, connection in ipairs(table.clone(self._handlers)) do disconnect(connection) end
end
sandbox.signalErrors = {}
sandbox.yields = 0
function sandbox.handlerCount(signal)
	return #signal._handlers
end

-- ---------- class hierarchy ----------
local PARENTS = {
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", TextBox = "GuiObject",
	ImageLabel = "GuiObject", ImageButton = "GuiButton", ScrollingFrame = "GuiObject", CanvasGroup = "GuiObject",
	ViewportFrame = "GuiObject", GuiButton = "GuiObject", GuiObject = "GuiBase2d", GuiBase2d = "Instance",
	ScreenGui = "LayerCollector", LayerCollector = "GuiBase2d",
	UICorner = "UIComponent", UIStroke = "UIComponent", UIGradient = "UIComponent", UIPadding = "UIComponent",
	UIScale = "UIComponent", UIListLayout = "UIGridStyleLayout", UIGridStyleLayout = "UILayout", UILayout = "UIComponent",
	UISizeConstraint = "UIConstraint", UIConstraint = "UIComponent", UIFlexItem = "UIComponent", UIComponent = "Instance",
}
local function isA(className, query)
	local current = className
	while current do
		if current == query then return true end
		current = PARENTS[current]
	end
	return query == "Instance"
end
local GUI_OBJECT = {}
for name in pairs(PARENTS) do
	if isA(name, "GuiObject") then GUI_OBJECT[name] = true end
end

-- ---------- instances ----------
local metrics = { created = 0, live = 0, byClass = {}, propertyWrites = 0, colorWrites = 0, tweens = 0, loopTweens = 0 }
sandbox.metricsTable = metrics
local screenGuis = setmetatable({}, { __mode = "k" })
local camera -- set below
local Instance = {}

local function defaultProps(className)
	local props = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Archivable = true,
	}
	if GUI_OBJECT[className] or className == "ScreenGui" then
		props.Visible = true
		props.Size = newUDim2(0, 0, 0, 0)
		props.Position = newUDim2(0, 0, 0, 0)
		props.AnchorPoint = newVector2(0, 0)
		props.BackgroundTransparency = 0
		props.BackgroundColor3 = newColor3(0.64, 0.64, 0.64)
		props.BorderSizePixel = 1
		props.Rotation = 0
		props.ZIndex = 1
		props.LayoutOrder = 0
		props.Active = false
		props.ClipsDescendants = false
		props.AutomaticSize = Enum.AutomaticSize.None
		props.Selectable = false
		props.Interactable = true
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		props.Text = className == "TextButton" and "Button" or (className == "TextBox" and "" or "Label")
		props.TextTransparency = 0
		props.TextColor3 = newColor3(0, 0, 0)
		props.TextSize = 14
		props.TextWrapped = false
		props.RichText = false
		props.TextXAlignment = Enum.TextXAlignment.Center
		props.TextYAlignment = Enum.TextYAlignment.Center
		props.TextTruncate = Enum.TextTruncate.None
		props.TextBounds = newVector2(0, 0)
	end
	if className == "TextBox" then
		props.PlaceholderText = ""
		props.ClearTextOnFocus = true
		props.CursorPosition = 1
		props.MultiLine = false
		props.TextEditable = true
	end
	if className == "TextButton" or className == "ImageButton" then
		props.AutoButtonColor = true
		props.Modal = false
	end
	if className == "ImageLabel" or className == "ImageButton" then
		props.Image = ""
		props.ImageColor3 = newColor3(1, 1, 1)
		props.ImageTransparency = 0
		props.ImageRectOffset = newVector2(0, 0)
		props.ImageRectSize = newVector2(0, 0)
		props.ScaleType = Enum.ScaleType.Stretch
	end
	if className == "ScrollingFrame" then
		props.CanvasSize = newUDim2(0, 0, 2, 0)
		props.CanvasPosition = newVector2(0, 0)
		props.ScrollingEnabled = true
		props.ScrollBarThickness = 12
		props.ScrollingDirection = Enum.ScrollingDirection.XY
		props.AutomaticCanvasSize = Enum.AutomaticSize.None
	end
	if className == "ScreenGui" then
		props.Enabled = true
		props.DisplayOrder = 0
		props.IgnoreGuiInset = false
		props.ResetOnSpawn = true
		props.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		props.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end
	if className == "UIStroke" then
		props.Color = newColor3(0, 0, 0)
		props.Transparency = 0
		props.Thickness = 1
		props.Enabled = true
	end
	if className == "UIGradient" then
		props.Color = setmetatable({ Keypoints = {} }, ColorSequence)
		props.Rotation = 0
		props.Enabled = true
		props.Offset = newVector2(0, 0)
	end
	if className == "UIScale" then props.Scale = 1 end
	if className == "UICorner" then props.CornerRadius = newUDim(0, 8) end
	if className == "UIListLayout" then
		props.Padding = newUDim(0, 0)
		props.AbsoluteContentSize = newVector2(0, 0)
	end
	return props
end

local function computeAbsoluteSize(self, properties)
	local className = properties.ClassName
	if className == "ScreenGui" then
		local viewport = camera and camera.ViewportSize or newVector2(1920, 1080)
		local inset = 36
		if properties.IgnoreGuiInset == true then inset = 0 end
		local insets = properties.ScreenInsets
		if insets and insets.Name == "None" then inset = 0 end
		return newVector2(viewport.X, viewport.Y - inset)
	end
	local size = properties.Size
	if not size or not size.X then return newVector2(0, 0) end
	local parent = properties.Parent
	if parent and (GUI_OBJECT[parent.ClassName] or parent.ClassName == "ScreenGui") then
		local parentSize = parent.AbsoluteSize
		return newVector2(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
	end
	if size.X.Scale == 0 and size.Y.Scale == 0 then
		return newVector2(size.X.Offset, size.Y.Offset)
	end
	return newVector2(980, 660)
end

local function computeAbsolutePosition(self, properties)
	if properties.ClassName == "ScreenGui" then return newVector2(0, 0) end
	local parent = properties.Parent
	local position = properties.Position
	if not position or not position.X then return newVector2(0, 0) end
	local origin, parentSize = newVector2(0, 0), newVector2(0, 0)
	if parent and (GUI_OBJECT[parent.ClassName] or parent.ClassName == "ScreenGui") then
		origin = parent.AbsolutePosition
		parentSize = parent.AbsoluteSize
	end
	local size = self.AbsoluteSize
	local anchor = properties.AnchorPoint or newVector2(0, 0)
	return newVector2(
		origin.X + parentSize.X * position.X.Scale + position.X.Offset - anchor.X * size.X,
		origin.Y + parentSize.Y * position.Y.Scale + position.Y.Offset - anchor.Y * size.Y
	)
end

local EVENTS = {
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton2Click = true,
	MouseButton2Down = true, MouseEnter = true, MouseLeave = true, MouseMoved = true, InputBegan = true,
	InputChanged = true, InputEnded = true, Activated = true, Focused = true, FocusLost = true, Changed = true,
	ChildAdded = true, ChildRemoved = true, Destroying = true, AncestryChanged = true, Stopped = true, Died = true,
	Equipped = true, Unequipped = true, Completed = true, ReturnPressedFromOnScreenKeyboard = true,
}

local function newInstance(className)
	metrics.created += 1
	metrics.live += 1
	metrics.byClass[className] = (metrics.byClass[className] or 0) + 1
	local children = {}
	local signals = {}
	local attributes = {}
	local properties = defaultProps(className)
	local destroyed = false

	local self
	local function getSignal(name)
		if not signals[name] then signals[name] = newSignal() end
		return signals[name]
	end

	local methods = {}
	function methods.GetChildren() return table.clone(children) end
	function methods.GetDescendants()
		local out = {}
		local function walk(node)
			for _, child in ipairs(node:GetChildren()) do
				out[#out + 1] = child
				walk(child)
			end
		end
		walk(self)
		return out
	end
	function methods.FindFirstChild(_, name, recursive)
		for _, child in ipairs(children) do
			if child.Name == name then return child end
		end
		if recursive then
			for _, child in ipairs(children) do
				local found = child:FindFirstChild(name, true)
				if found then return found end
			end
		end
		return nil
	end
	function methods.FindFirstChildOfClass(_, query)
		for _, child in ipairs(children) do
			if child.ClassName == query then return child end
		end
		return nil
	end
	function methods.FindFirstChildWhichIsA(_, query)
		for _, child in ipairs(children) do
			if child:IsA(query) then return child end
		end
		return nil
	end
	function methods.FindFirstAncestorOfClass(_, query)
		local node = properties.Parent
		while node do
			if node.ClassName == query then return node end
			node = node.Parent
		end
		return nil
	end
	function methods.IsDescendantOf(_, ancestor)
		local node = properties.Parent
		while node do
			if node == ancestor then return true end
			node = node.Parent
		end
		return false
	end
	function methods.WaitForChild(_, name)
		sandbox.yields += 1
		return self:FindFirstChild(name)
	end
	function methods.IsA(_, query) return isA(properties.ClassName, query) end
	function methods.Destroy()
		if destroyed then return end
		destroyed = true
		metrics.live -= 1
		for _, child in ipairs(table.clone(children)) do child:Destroy() end
		if properties.Parent then
			properties.Parent._removeChild(self)
			properties.Parent = nil
		end
		getSignal("Destroying"):Fire()
		for _, signal in pairs(signals) do signal:DisconnectAll() end
	end
	function methods.ClearAllChildren()
		for _, child in ipairs(table.clone(children)) do child:Destroy() end
	end
	function methods.SetAttribute(_, name, value) attributes[name] = value end
	function methods.GetAttribute(_, name) return attributes[name] end
	function methods.GetAttributes() return table.clone(attributes) end
	function methods.GetPropertyChangedSignal(_, name) return getSignal("prop:" .. name) end
	function methods.GetMarkerReachedSignal(_, name) return getSignal("marker:" .. name) end
	function methods.TweenSize() return true end
	function methods.TweenPosition() return true end
	function methods.CaptureFocus()
		sandbox.focusedTextBox = self
		getSignal("Focused"):Fire()
	end
	function methods.ReleaseFocus(_, enter)
		if sandbox.focusedTextBox == self then sandbox.focusedTextBox = nil end
		getSignal("FocusLost"):Fire(enter == true)
	end
	function methods.IsFocused() return sandbox.focusedTextBox == self end
	function methods._addChild(child) table.insert(children, child) end
	function methods._removeChild(child)
		for index, entry in ipairs(children) do
			if entry == child then table.remove(children, index) break end
		end
	end
	function methods._isDestroyed() return destroyed end

	self = setmetatable({}, {
		__tostring = function() return properties.Name end,
		__index = function(_, key)
			if key == "AbsoluteSize" then return computeAbsoluteSize(self, properties) end
			if key == "AbsolutePosition" then return computeAbsolutePosition(self, properties) end
			local method = methods[key]
			if method then return method end
			if EVENTS[key] then return getSignal(key) end
			local value = properties[key]
			if value ~= nil then return value end
			for _, child in ipairs(children) do
				if child.Name == key then return child end
			end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				if destroyed then
					error("The Parent property of " .. tostring(properties.Name) .. " is locked", 2)
				end
				if properties.Parent then properties.Parent._removeChild(self) end
				properties.Parent = value
				if value then value._addChild(self) end
				getSignal("AncestryChanged"):Fire(self, value)
				return
			end
			if key == "AbsoluteSize" or key == "AbsolutePosition" then return end
			metrics.propertyWrites += 1
			if getmetatable(value) == Color3 then metrics.colorWrites += 1 end
			properties[key] = value
			if key == "Text" and (className == "TextLabel" or className == "TextButton" or className == "TextBox") then
				properties.TextBounds = newVector2(#tostring(value) * (properties.TextSize or 14) * 0.5, properties.TextSize or 14)
			end
			if signals["prop:" .. key] then signals["prop:" .. key]:Fire() end
		end,
	})
	if className == "ScreenGui" then screenGuis[self] = true end
	return self
end

Instance.new = function(className, parent)
	local created = newInstance(className)
	if parent then created.Parent = parent end
	return created
end

-- ---------- services ----------
local function makeService(className, extra)
	local service = newInstance(className)
	for key, value in pairs(extra or {}) do service[key] = value end
	return service
end

local mouseLocation = newVector2(640, 360)

local RunService = makeService("RunService")
RunService.RenderStepped = newSignal()
RunService.Heartbeat = newSignal()
RunService.Stepped = newSignal()
local runServiceMethods = {
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
	IsStudio = function() return false end,
	IsClient = function() return true end,
}

local UserInputService = makeService("UserInputService")
UserInputService.InputBegan = newSignal()
UserInputService.InputChanged = newSignal()
UserInputService.InputEnded = newSignal()
UserInputService.TouchSwipe = newSignal()
UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
UserInputService.GamepadEnabled = false
UserInputService.MouseIconEnabled = true
UserInputService.PreferredInput = Enum.PreferredInput.KeyboardAndMouse

local TweenService = makeService("TweenService")

local Players = makeService("Players")
local localPlayer = newInstance("Player")
localPlayer.Name = "TestPlayer"
localPlayer.DisplayName = "Test Player"
localPlayer.UserId = 1234
Players.LocalPlayer = localPlayer
Players.PlayerAdded = newSignal()
Players.PlayerRemoving = newSignal()
local playerList = { localPlayer }
function sandbox.addPlayer(id, name)
	local player = newInstance("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = id
	playerList[#playerList + 1] = player
	Players.PlayerAdded:Fire(player)
	return player
end
function sandbox.removePlayer(player)
	for index, entry in ipairs(playerList) do
		if entry == player then table.remove(playerList, index) break end
	end
	Players.PlayerRemoving:Fire(player)
end

local HttpService = makeService("HttpService")

-- ---------- JSON ----------
local function encodeJson(value)
	local pieces = {}
	local function escape(text)
		return (text:gsub('[%c"\\]', function(char)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[char] or ("\\u%04x"):format(char:byte())
		end))
	end
	local function write(node)
		local kind = type(node)
		if node == nil then pieces[#pieces + 1] = "null"
		elseif kind == "boolean" then pieces[#pieces + 1] = tostring(node)
		elseif kind == "number" then
			pieces[#pieces + 1] = (node % 1 == 0 and math.abs(node) < 2 ^ 53) and ("%d"):format(node) or tostring(node)
		elseif kind == "string" then pieces[#pieces + 1] = '"' .. escape(node) .. '"'
		elseif kind == "table" then
			local isArray = #node > 0
			local keyCount = 0
			for _ in pairs(node) do keyCount += 1 end
			if isArray and keyCount == #node then
				pieces[#pieces + 1] = "["
				for index, item in ipairs(node) do
					if index > 1 then pieces[#pieces + 1] = "," end
					write(item)
				end
				pieces[#pieces + 1] = "]"
			else
				pieces[#pieces + 1] = "{"
				local first = true
				local keys = {}
				for key in pairs(node) do keys[#keys + 1] = tostring(key) end
				table.sort(keys)
				for _, key in ipairs(keys) do
					local item = node[key]
					if item == nil then item = node[tonumber(key)] end
					if type(item) ~= "function" then
						if not first then pieces[#pieces + 1] = "," end
						first = false
						pieces[#pieces + 1] = '"' .. escape(key) .. '":'
						write(item)
					end
				end
				pieces[#pieces + 1] = "}"
			end
		else
			pieces[#pieces + 1] = "null"
		end
	end
	write(value)
	return table.concat(pieces)
end

local function decodeJson(text)
	local position = 1
	local function skip()
		while position <= #text and text:sub(position, position):match("%s") do position += 1 end
	end
	local parseValue
	local function parseString()
		position += 1
		local out = {}
		while true do
			local char = text:sub(position, position)
			if char == "" then error("unterminated string") end
			if char == '"' then position += 1 break end
			if char == "\\" then
				local nextChar = text:sub(position + 1, position + 1)
				local map = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if map[nextChar] then out[#out + 1] = map[nextChar] position += 2
				elseif nextChar == "u" then
					out[#out + 1] = utf8.char(tonumber(text:sub(position + 2, position + 5), 16) or 63)
					position += 6
				else out[#out + 1] = nextChar position += 2 end
			else
				out[#out + 1] = char
				position += 1
			end
		end
		return table.concat(out)
	end
	function parseValue()
		skip()
		local char = text:sub(position, position)
		if char == "{" then
			position += 1
			local object = {}
			skip()
			if text:sub(position, position) == "}" then position += 1 return object end
			while true do
				skip()
				local key = parseString()
				skip()
				position += 1
				object[key] = parseValue()
				skip()
				local delimiter = text:sub(position, position)
				position += 1
				if delimiter == "}" then break end
			end
			return object
		elseif char == "[" then
			position += 1
			local array = {}
			skip()
			if text:sub(position, position) == "]" then position += 1 return array end
			while true do
				array[#array + 1] = parseValue()
				skip()
				local delimiter = text:sub(position, position)
				position += 1
				if delimiter == "]" then break end
			end
			return array
		elseif char == '"' then
			return parseString()
		elseif text:sub(position, position + 3) == "true" then position += 4 return true
		elseif text:sub(position, position + 4) == "false" then position += 5 return false
		elseif text:sub(position, position + 3) == "null" then position += 4 return nil
		else
			local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
			if not number then error("invalid json at " .. position) end
			position += #number
			return tonumber(number)
		end
	end
	return parseValue()
end

sandbox.encodeJson = encodeJson
sandbox.decodeJson = decodeJson

local httpMethods = {
	JSONEncode = function(_, value) return encodeJson(value) end,
	JSONDecode = function(_, value) return decodeJson(value) end,
	GenerateGUID = function(_, wrap)
		local id = ("%08x-guid-%d"):format(math.random(0, 0xffffff), metrics.created)
		return wrap == false and id or "{" .. id .. "}"
	end,
}

-- ---------- tweens ----------
sandbox.tweens = {}
local function tweenCreate(_, target, info, goals)
	metrics.tweens += 1
	local repeating = type(info) == "table" and info[4] == -1
	if repeating then metrics.loopTweens += 1 end
	local tween = { ClassName = "TweenTable", Completed = newSignal(), PlaybackState = "Begin" }
	function tween.Play()
		if repeating then
			sandbox.tweens[tween] = true
			return
		end
		for key, value in pairs(goals) do
			pcall(function() target[key] = value end)
		end
		tween.Completed:Fire()
	end
	function tween.Cancel()
		sandbox.tweens[tween] = nil
	end
	tween.Pause = tween.Cancel
	return tween
end
function sandbox.runningLoops()
	local count = 0
	for _ in pairs(sandbox.tweens) do count += 1 end
	return count
end

-- ---------- game ----------
local CoreGui = makeService("CoreGui")
local services = {
	RunService = RunService,
	UserInputService = UserInputService,
	TweenService = TweenService,
	Players = Players,
	HttpService = HttpService,
	CoreGui = CoreGui,
	TextService = makeService("TextService"),
	ContextActionService = makeService("ContextActionService"),
	StarterGui = makeService("StarterGui"),
	Lighting = makeService("Lighting"),
	Workspace = makeService("Workspace"),
	ReplicatedStorage = makeService("ReplicatedStorage"),
	GuiService = makeService("GuiService"),
	Debris = makeService("Debris"),
	MarketplaceService = makeService("MarketplaceService"),
	SoundService = makeService("SoundService"),
	ContentProvider = makeService("ContentProvider"),
}

sandbox.cas = { bound = {} }
sandbox.clipboard = nil
sandbox.network = { httpGets = 0, thumbnails = 0 }
sandbox.forbidNetwork = false

local serviceMethodMap = {
	[RunService] = runServiceMethods,
	[HttpService] = httpMethods,
	[UserInputService] = {
		GetMouseLocation = function() return mouseLocation end,
		GetMouseDelta = function() return newVector2(0, 0) end,
		IsKeyDown = function(_, code) return sandbox.keysDown[code] == true end,
		GetFocusedTextBox = function() return sandbox.focusedTextBox end,
		GetImageForKeyCode = function() return "" end,
		GetStringForKeyCode = function(_, code) return code and code.Name or "" end,
	},
	[TweenService] = { Create = tweenCreate },
	[services.ContextActionService] = {
		BindAction = function(_, name) sandbox.cas.bound[name] = true end,
		BindActionAtPriority = function(_, name) sandbox.cas.bound[name] = true end,
		UnbindAction = function(_, name) sandbox.cas.bound[name] = nil end,
		SetPosition = function() end,
		SetTitle = function() end,
		SetImage = function() end,
	},
	[Players] = {
		GetPlayers = function() return table.clone(playerList) end,
		GetPlayerFromCharacter = function() return nil end,
		GetUserThumbnailAsync = function()
			sandbox.network.thumbnails += 1
			if sandbox.forbidNetwork then error("GetUserThumbnailAsync on a forbidden path") end
			return "rbxassetid://0", true
		end,
	},
	[services.GuiService] = { GetGuiInset = function() return newVector2(0, 36), newVector2(0, 0) end },
	[services.Workspace] = { Raycast = function() return nil end },
	[services.TextService] = {
		GetTextSize = function(_, text, size)
			return newVector2(math.min(#tostring(text) * (size or 14) * 0.5, 2000), size or 16)
		end,
		GetTextBoundsAsync = function()
			-- a yield in a real client; counted apart so tests can check it never runs on the caller
			sandbox.network.textBounds = (sandbox.network.textBounds or 0) + 1
			sandbox.network.textBoundsOnMain = (sandbox.network.textBoundsOnMain or 0)
				+ (coroutine.running() == sandbox.mainThread and 1 or 0)
			return newVector2(120, 16)
		end,
	},
	[services.StarterGui] = { SetCore = function() end },
	[services.ContentProvider] = { PreloadAsync = function() sandbox.yields += 1 end },
}

for instanceObject, methods in pairs(serviceMethodMap) do
	local existing = getmetatable(instanceObject).__index
	getmetatable(instanceObject).__index = function(self, key)
		if methods[key] then return methods[key] end
		return existing(self, key)
	end
end

local game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				if not services[name] then services[name] = makeService(name) end
				return services[name]
			end
		end
		if key == "IsLoaded" then return function() return true end end
		if key == "Loaded" then return newSignal() end
		if key == "PlaceId" then return 1 end
		if key == "JobId" then return "test-job" end
		if key == "Workspace" then return services.Workspace end
		if key == "HttpGet" or key == "HttpGetAsync" then
			return function(_, url)
				sandbox.network.httpGets += 1
				if sandbox.forbidNetwork then error("HttpGet on a forbidden path: " .. tostring(url)) end
				return sandbox.httpGet(url)
			end
		end
		return services[key]
	end,
})

-- ---------- executor filesystem ----------
local files, folders = {}, { [""] = true }
sandbox.files = files
sandbox.folders = folders

local environment = {
	game = game,
	workspace = services.Workspace,
	Instance = Instance,
	Enum = Enum,
	UDim = UDim,
	UDim2 = setmetatable({
		new = newUDim2,
		fromScale = function(x, y) return newUDim2(x, 0, y, 0) end,
		fromOffset = function(x, y) return newUDim2(0, x, 0, y) end,
	}, { __index = UDim2 }),
	Vector2 = setmetatable({ new = newVector2, zero = newVector2(0, 0), one = newVector2(1, 1) }, { __index = Vector2 }),
	Vector3 = setmetatable({
		new = newVector3, zero = newVector3(0, 0, 0), yAxis = newVector3(0, 1, 0), zAxis = newVector3(0, 0, 1),
	}, { __index = Vector3 }),
	Color3 = setmetatable({
		new = newColor3,
		fromRGB = function(r, g, b) return newColor3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
		fromHex = function(hex)
			hex = tostring(hex):gsub("#", "")
			return newColor3(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
		end,
		fromHSV = function(h, s, v)
			local index = math.floor(h * 6)
			local f = h * 6 - index
			local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
			local lookup = {
				[0] = { v, t, p }, [1] = { q, v, p }, [2] = { p, v, t },
				[3] = { p, q, v }, [4] = { t, p, v }, [5] = { v, p, q },
			}
			local rgb = lookup[index % 6]
			return newColor3(rgb[1], rgb[2], rgb[3])
		end,
	}, { __index = Color3 }),
	Rect = { new = function(a, b, c, d)
		if type(a) == "number" then return setmetatable({ Min = newVector2(a, b), Max = newVector2(c, d) }, Rect) end
		return setmetatable({ Min = a, Max = b }, Rect)
	end },
	NumberSequence = { new = function(keypoints)
		if type(keypoints) == "number" then keypoints = { { Time = 0, Value = keypoints }, { Time = 1, Value = keypoints } } end
		return setmetatable({ Keypoints = keypoints }, NumberSequence)
	end },
	NumberSequenceKeypoint = { new = function(time, value) return { Time = time, Value = value } end },
	ColorSequence = { new = function(keypoints, second)
		if getmetatable(keypoints) == Color3 then
			keypoints = { { Time = 0, Value = keypoints }, { Time = 1, Value = second or keypoints } }
		end
		return setmetatable({ Keypoints = keypoints }, ColorSequence)
	end },
	ColorSequenceKeypoint = { new = function(time, value) return { Time = time, Value = value } end },
	TweenInfo = { new = function(...) return { ... } end },
	Font = {
		new = function(family, weight, style)
			return { Family = family, Weight = weight, Style = style, __fontFace = true }
		end,
		fromEnum = function(enumItem) return { Family = tostring(enumItem), __fontFace = true } end,
		fromName = function(name) return { Family = "rbxasset://fonts/families/" .. tostring(name) .. ".json", __fontFace = true } end,
	},
	CFrame = { new = function() return {} end, Angles = function() return {} end, lookAt = function() return {} end },
	tick = os.clock,
	time = function() return sandbox.clock end,
	task = nil, -- assigned below
	typeof = function(value)
		local meta = getmetatable(value)
		if meta == Color3 then return "Color3" end
		if meta == UDim2 then return "UDim2" end
		if meta == UDim then return "UDim" end
		if meta == Vector2 then return "Vector2" end
		if meta == Vector3 then return "Vector3" end
		if meta == Rect then return "Rect" end
		if meta == ColorSequence then return "ColorSequence" end
		if meta == NumberSequence then return "NumberSequence" end
		if type(value) == "table" and value.ClassName == "TweenTable" then return "table" end
		if type(value) == "table" and rawget(value, "ClassName") == nil and value.ClassName ~= nil then return "Instance" end
		if type(value) == "table" and value.EnumType then return "EnumItem" end
		return type(value)
	end,
	warn = function(...)
		local parts = {}
		for _, value in ipairs({ ... }) do parts[#parts + 1] = tostring(value) end
		sandbox.warnings[#sandbox.warnings + 1] = table.concat(parts, " ")
	end,
	print = print,
	-- executor filesystem
	writefile = function(path, contents) files[path] = tostring(contents) end,
	readfile = function(path)
		if files[path] == nil then error("file not found: " .. tostring(path)) end
		return files[path]
	end,
	isfile = function(path) return files[path] ~= nil end,
	isfolder = function(path) return folders[path] == true end,
	makefolder = function(path) folders[path] = true end,
	delfile = function(path) files[path] = nil end,
	listfiles = function(folder)
		local out = {}
		for path in pairs(files) do
			if not folder or path:sub(1, #folder + 1) == folder .. "/" then out[#out + 1] = path end
		end
		return out
	end,
	setclipboard = function(text) sandbox.clipboard = tostring(text) end,
	loadstring = function()
		sandbox.network.loadstrings = (sandbox.network.loadstrings or 0) + 1
		if sandbox.forbidNetwork then error("loadstring on a forbidden path") end
		return nil, "loadstring is not available in the sandbox"
	end,
}
sandbox.warnings = {}

-- Executor profiles: "full" (default), "none" (no executor functions, CoreGui refuses),
-- "nofs" (no filesystem), "noclipboard".
local EXECUTOR_KEYS = { "writefile", "readfile", "isfile", "isfolder", "makefolder", "delfile", "listfiles", "setclipboard", "getgenv" }
local saved = {}
for _, key in ipairs(EXECUTOR_KEYS) do saved[key] = true end
function sandbox.setExecutor(profile)
	sandbox.executor = profile
	local removed = {}
	if profile == "none" then
		for _, key in ipairs(EXECUTOR_KEYS) do removed[key] = true end
	elseif profile == "nofs" then
		for _, key in ipairs({ "writefile", "readfile", "isfile", "isfolder", "makefolder", "delfile", "listfiles" }) do removed[key] = true end
	elseif profile == "noclipboard" then
		removed.setclipboard = true
	end
	for _, key in ipairs(EXECUTOR_KEYS) do
		if removed[key] then
			if rawget(environment, key) ~= nil then saved[key] = rawget(environment, key) end
			rawset(environment, key, nil)
		elseif type(saved[key]) == "function" then
			rawset(environment, key, saved[key])
		end
	end
end

-- ---------- time: frames, delays and the task library ----------
local scheduled = {}
sandbox.scheduled = scheduled
sandbox.clock = 0
sandbox.frame = 0
sandbox.keysDown = {}
local FRAME = 1 / 60

local function runSafely(callback, ...)
	local ok, err = pcall(callback, ...)
	if not ok then sandbox.signalErrors[#sandbox.signalErrors + 1] = tostring(err) end
end

local function runDue()
	local ran = 0
	while true do
		local dueIndex
		for index, entry in ipairs(scheduled) do
			if entry.at <= sandbox.clock + 1e-9 and (not dueIndex or entry.at < scheduled[dueIndex].at) then dueIndex = index end
		end
		if not dueIndex then break end
		local entry = table.remove(scheduled, dueIndex)
		if not entry.cancelled then
			ran += 1
			runSafely(entry.callback, table.unpack(entry.args, 1, entry.args.n))
		end
		if ran > 10000 then break end
	end
	return ran
end

-- Steps n frames of dt: RenderStepped, Stepped and Heartbeat fire, the clock advances and due
-- delays run.
function sandbox.step(frames, dt)
	frames = frames or 1
	dt = dt or FRAME
	local ran = 0
	for _ = 1, frames do
		sandbox.clock += dt
		sandbox.frame += 1
		RunService.RenderStepped:Fire(dt)
		RunService.Stepped:Fire(sandbox.clock, dt)
		RunService.Heartbeat:Fire(dt)
		ran += runDue()
	end
	return ran
end

-- Advances the clock by seconds, stepping frames (capped at 600 per call) and running delays.
function sandbox.advance(seconds)
	seconds = tonumber(seconds) or 0
	local frames = math.min(600, math.max(1, math.ceil(seconds / FRAME - 1e-6)))
	local dt = seconds > 0 and seconds / frames or 0
	if seconds <= 0 then return runDue() end
	return sandbox.step(frames, dt)
end

local function newThreadHandle(callback, ...)
	local thread = coroutine.create(callback)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then sandbox.signalErrors[#sandbox.signalErrors + 1] = tostring(err) end
	return thread
end

environment.task = {
	spawn = function(callback, ...)
		if type(callback) == "thread" then
			coroutine.resume(callback, ...)
			return callback
		end
		return newThreadHandle(callback, ...)
	end,
	defer = function(callback, ...)
		runSafely(callback, ...)
		return {}
	end,
	delay = function(seconds, callback, ...)
		local entry = { at = sandbox.clock + (tonumber(seconds) or 0), callback = callback, args = table.pack(...) }
		scheduled[#scheduled + 1] = entry
		return entry
	end,
	wait = function(seconds)
		sandbox.yields += 1
		local frames = math.max(1, math.ceil((tonumber(seconds) or 0) / FRAME - 1e-6))
		sandbox.step(math.min(frames, 600))
		return (tonumber(seconds) or FRAME)
	end,
	cancel = function(entry)
		if type(entry) == "table" then entry.cancelled = true end
	end,
	synchronize = function() end,
	desynchronize = function() end,
}

environment.wait = environment.task.wait
environment.spawn = environment.task.spawn
environment.delay = function(seconds, callback) return environment.task.delay(seconds, callback) end

environment.getgenv = function() return environment end
sandbox.httpGet = function() return "" end
sandbox.environment = environment
sandbox.mainThread = coroutine.running()
sandbox.services = services
sandbox.Signal = { new = newSignal }
sandbox.UserInputService = UserInputService
sandbox.RunService = RunService
sandbox.Players = Players
sandbox.CoreGui = CoreGui
sandbox.Enum = Enum

camera = newInstance("Camera")
camera.ViewportSize = newVector2(1920, 1080)
camera.Parent = services.Workspace
services.Workspace.CurrentCamera = camera
sandbox.Camera = camera

-- Resizes the viewport the way a real client does: every ScreenGui reports a new size.
function sandbox.setViewport(width, height)
	camera.ViewportSize = newVector2(width, height)
	for gui in pairs(screenGuis) do
		pcall(function() gui:GetPropertyChangedSignal("AbsoluteSize"):Fire() end)
	end
	return camera.ViewportSize
end

-- ---------- input simulation ----------
local function inputObject(inputType, keyCode, position, state)
	return {
		UserInputType = inputType,
		KeyCode = keyCode or Enum.KeyCode.Unknown,
		Position = position or newVector3(mouseLocation.X, mouseLocation.Y, 0),
		UserInputState = state or Enum.UserInputState.Begin,
		Delta = newVector3(0, 0, 0),
	}
end
sandbox.input = {}
function sandbox.input.key(name, gameProcessed)
	local code = Enum.KeyCode[name]
	local input = inputObject(Enum.UserInputType.Keyboard, code)
	sandbox.keysDown[code] = true
	UserInputService.InputBegan:Fire(input, gameProcessed == true)
	return input
end
function sandbox.input.keyUp(name)
	local code = Enum.KeyCode[name]
	sandbox.keysDown[code] = nil
	local input = inputObject(Enum.UserInputType.Keyboard, code, nil, Enum.UserInputState.End)
	UserInputService.InputEnded:Fire(input, false)
	return input
end
function sandbox.input.press(name, gameProcessed)
	local input = sandbox.input.key(name, gameProcessed)
	sandbox.input.keyUp(name)
	return input
end
function sandbox.input.pad(name)
	local code = Enum.KeyCode[name]
	local input = inputObject(Enum.UserInputType.Gamepad1, code)
	UserInputService.InputBegan:Fire(input, false)
	UserInputService.InputEnded:Fire(inputObject(Enum.UserInputType.Gamepad1, code, nil, Enum.UserInputState.End), false)
	return input
end
function sandbox.input.click(button, which)
	if which == 2 then
		local input = inputObject(Enum.UserInputType.MouseButton2)
		button.InputBegan:Fire(input)
		button.MouseButton2Click:Fire()
		return
	end
	button.MouseButton1Down:Fire()
	button.MouseButton1Click:Fire()
	button.Activated:Fire()
end
-- Drags from a GuiObject: InputBegan on it, InputChanged moves, InputEnded.
function sandbox.input.drag(gui, from, to, steps, kind)
	steps = steps or 5
	local inputType = kind == "Touch" and Enum.UserInputType.Touch or Enum.UserInputType.MouseButton1
	local start = inputObject(inputType, nil, newVector3(from.X, from.Y, 0))
	gui.InputBegan:Fire(start)
	for index = 1, steps do
		local t = index / steps
		local position = newVector3(from.X + (to.X - from.X) * t, from.Y + (to.Y - from.Y) * t, 0)
		if inputType == Enum.UserInputType.Touch then
			start.Position = position
			UserInputService.InputChanged:Fire(start, false)
		else
			UserInputService.InputChanged:Fire(inputObject(Enum.UserInputType.MouseMovement, nil, position), false)
		end
		sandbox.step(1)
	end
	start.UserInputState = Enum.UserInputState.End
	UserInputService.InputEnded:Fire(inputType == Enum.UserInputType.Touch and start or inputObject(inputType, nil, newVector3(to.X, to.Y, 0)), false)
	sandbox.step(1)
end
function sandbox.input.typeText(box, text, enter)
	box:CaptureFocus()
	box.Text = text
	box:ReleaseFocus(enter ~= false)
end
function sandbox.setPreferredInput(kind)
	local map = { mouse = "KeyboardAndMouse", touch = "Touch", gamepad = "Gamepad" }
	UserInputService.PreferredInput = Enum.PreferredInput[map[kind] or kind]
	UserInputService.TouchEnabled = kind == "touch"
end

-- ---------- metrics ----------
function sandbox.metrics()
	return {
		created = metrics.created,
		live = metrics.live,
		byClass = table.clone(metrics.byClass),
		propertyWrites = metrics.propertyWrites,
		colorWrites = metrics.colorWrites,
		tweens = metrics.tweens,
		loopTweens = metrics.loopTweens,
		runningLoops = sandbox.runningLoops(),
		delaysPending = #scheduled,
		handlers = {
			InputBegan = #UserInputService.InputBegan._handlers,
			InputChanged = #UserInputService.InputChanged._handlers,
			InputEnded = #UserInputService.InputEnded._handlers,
			Heartbeat = #RunService.Heartbeat._handlers,
			RenderStepped = #RunService.RenderStepped._handlers,
			Stepped = #RunService.Stepped._handlers,
		},
	}
end

function sandbox.load(sourcePath)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local source = fs.readFile(sourcePath)
	setmetatable(environment, { __index = _G })
	local chunk = luau.load(source, { debugName = sourcePath, environment = environment, injectGlobals = true })
	return chunk()
end

return sandbox
