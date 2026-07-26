--!nocheck
-- Minimal Roblox API sandbox so argon-ui.luau can run outside Roblox.
-- Only what the library touches is implemented; enough to exercise real control
-- logic, callbacks, and configuration persistence.

local sandbox = {}

-- ---------- datatypes ----------
local function class(name, fields)
	local meta = {}
	meta.__index = meta
	meta.__tostring = function() return name end
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

local UDim2 = class("UDim2", { "X", "Y" })
local function newUDim2(xs, xo, ys, yo)
	return setmetatable({ X = newUDim(xs, xo), Y = newUDim(ys, yo) }, UDim2)
end

local Vector2 = class("Vector2", { "X", "Y" })
local function newVector2(x, y)
	x, y = x or 0, y or 0
	local self = setmetatable({ X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }, Vector2)
	self.Unit = self.Magnitude > 0 and setmetatable({ X = x / self.Magnitude, Y = y / self.Magnitude, Magnitude = 1 }, Vector2) or self
	return self
end
Vector2.__add = function(a, b) return newVector2(a.X + b.X, a.Y + b.Y) end
Vector2.__sub = function(a, b) return newVector2(a.X - b.X, a.Y - b.Y) end

local Vector3 = class("Vector3", { "X", "Y", "Z" })
local function newVector3(x, y, z)
	x, y, z = x or 0, y or 0, z or 0
	return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, Vector3)
end

local Color3 = class("Color3", { "R", "G", "B" })
local function newColor3(r, g, b)
	local self = setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
	return self
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

local Rect = class("Rect", { "Min", "Max" })
local NumberSequence = class("NumberSequence", { "Keypoints" })
local ColorSequence = class("ColorSequence", { "Keypoints" })

-- ---------- Enum ----------
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
			return byName[key]
		end,
	})
end

local Enum = {
	Font = buildEnum("Font", { "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "SourceSans" }),
	TextXAlignment = buildEnum("TextXAlignment", { "Left", "Center", "Right" }),
	TextYAlignment = buildEnum("TextYAlignment", { "Top", "Center", "Bottom" }),
	TextTruncate = buildEnum("TextTruncate", { "None", "AtEnd" }),
	AutomaticSize = buildEnum("AutomaticSize", { "None", "X", "Y", "XY" }),
	SortOrder = buildEnum("SortOrder", { "Name", "Custom", "LayoutOrder" }),
	FillDirection = buildEnum("FillDirection", { "Horizontal", "Vertical" }),
	ZIndexBehavior = buildEnum("ZIndexBehavior", { "Global", "Sibling" }),
	EasingStyle = buildEnum("EasingStyle", { "Linear", "Sine", "Back", "Quad", "Quint", "Exponential" }),
	EasingDirection = buildEnum("EasingDirection", { "In", "Out", "InOut" }),
	ScaleType = buildEnum("ScaleType", { "Stretch", "Slice", "Tile", "Fit", "Crop" }),
	ResamplerMode = buildEnum("ResamplerMode", { "Default", "Pixelated" }),
	UserInputType = buildEnum("UserInputType", { "MouseButton1", "MouseButton2", "MouseButton3", "MouseMovement", "MouseWheel", "Keyboard", "Touch", "Focus", "Gamepad1" }),
	UserInputState = buildEnum("UserInputState", { "Begin", "Change", "End", "Cancel", "None" }),
	AnimationPriority = buildEnum("AnimationPriority", { "Core", "Idle", "Movement", "Action" }),
	ApplyStrokeMode = buildEnum("ApplyStrokeMode", { "Contextual", "Border" }),
	SwipeDirection = buildEnum("SwipeDirection", { "Right", "Left", "Up", "Down", "None" }),
	KeyCode = buildEnum("KeyCode", {
		"Unknown", "Insert", "Escape", "Backspace", "Return", "Space", "Slash", "LeftShift", "RightShift",
		"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
		"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
		"F1", "F2", "F3", "F4", "RightControl", "LeftControl", "Delete", "End", "Home",
	}),
	HorizontalAlignment = buildEnum("HorizontalAlignment", { "Center", "Left", "Right" }),
	VerticalAlignment = buildEnum("VerticalAlignment", { "Center", "Top", "Bottom" }),
	ContextActionResult = buildEnum("ContextActionResult", { "Pass", "Sink" }),
	ContextActionPriority = buildEnum("ContextActionPriority", { "Low", "Medium", "High" }),
	ThumbnailType = buildEnum("ThumbnailType", { "HeadShot", "AvatarBust" }),
	ThumbnailSize = buildEnum("ThumbnailSize", { "Size48x48", "Size100x100", "Size420x420" }),
}
-- ContextActionPriority values are read numerically by some hosts.
Enum.ContextActionPriority.High.Value = 3000

-- ---------- signals ----------
local Signal = {}
Signal.__index = Signal
local function newSignal()
	return setmetatable({ _handlers = {} }, Signal)
end
function Signal:Connect(handler)
	local connection = { Connected = true, _handler = handler }
	function connection:Disconnect()
		self.Connected = false
		for index, entry in ipairs(self._signal._handlers) do
			if entry == self then table.remove(self._signal._handlers, index) break end
		end
	end
	connection.Destroy = connection.Disconnect
	connection._signal = self
	table.insert(self._handlers, connection)
	return connection
end
Signal.ConnectParallel = Signal.Connect
Signal.Once = Signal.Connect
function Signal:Fire(...)
	for _, connection in ipairs(table.clone(self._handlers)) do
		if connection.Connected then
			local ok, err = pcall(connection._handler, ...)
			if not ok then sandbox.signalErrors[#sandbox.signalErrors + 1] = tostring(err) end
		end
	end
end
function Signal:Wait() return nil end
sandbox.signalErrors = {}

-- ---------- instances ----------
local instanceCount = 0
local Instance = {}

local function newInstance(className)
	instanceCount += 1
	local children = {}
	local signals = {}
	local attributes = {}
	local properties = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Visible = true,
		Text = "",
		Size = newUDim2(0, 0, 0, 0),
		Position = newUDim2(0, 0, 0, 0),
		AbsoluteSize = newVector2(980, 660),
		AbsolutePosition = newVector2(0, 0),
		BackgroundTransparency = 0,
		TextTransparency = 0,
		Transparency = 0,
		Rotation = 0,
		CanvasSize = newUDim2(0, 0, 0, 0),
		AbsoluteContentSize = newVector2(0, 0),
		BackgroundColor3 = newColor3(0, 0, 0),
		TextColor3 = newColor3(1, 1, 1),
		Color = newColor3(1, 1, 1),
		ImageColor3 = newColor3(1, 1, 1),
		Image = "",
		Length = 1,
		TimePosition = 0,
		IsPlaying = false,
		Speed = 1,
	}

	local self
	local function getSignal(name)
		if not signals[name] then signals[name] = newSignal() end
		return signals[name]
	end

	self = setmetatable({}, {
		__tostring = function() return properties.Name end,
		__index = function(_, key)
			if key == "GetChildren" then return function() return table.clone(children) end end
			if key == "GetDescendants" then
				return function()
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
			end
			if key == "FindFirstChild" then
				return function(_, name)
					for _, child in ipairs(children) do if child.Name == name then return child end end
					return nil
				end
			end
			if key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
				return function(_, className2)
					for _, child in ipairs(children) do if child.ClassName == className2 then return child end end
					return nil
				end
			end
			if key == "WaitForChild" then
				return function(_, name) return self:FindFirstChild(name) end
			end
			if key == "IsA" then
				return function(_, query)
					if query == properties.ClassName then return true end
					local guiObjects = {
						Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiObject",
						TextBox = "GuiObject", ImageLabel = "GuiObject", ImageButton = "GuiObject",
						ScrollingFrame = "GuiObject", CanvasGroup = "GuiObject",
					}
					if query == "GuiObject" then return guiObjects[properties.ClassName] ~= nil end
					if query == "GuiBase2d" then return guiObjects[properties.ClassName] ~= nil end
					return false
				end
			end
			if key == "Destroy" then
				return function()
					if properties.Parent then
						local siblings = properties.Parent:GetChildren()
						for index, child in ipairs(siblings) do
							if child == self then table.remove(siblings, index) break end
						end
						properties.Parent._removeChild(self)
					end
					getSignal("Destroying"):Fire()
					properties.Parent = nil
				end
			end
			if key == "ClearAllChildren" then
				return function() for _, child in ipairs(table.clone(children)) do child:Destroy() end end
			end
			if key == "SetAttribute" then return function(_, name, value) attributes[name] = value end end
			if key == "GetAttribute" then return function(_, name) return attributes[name] end end
			if key == "GetPropertyChangedSignal" then return function(_, name) return getSignal("prop:" .. name) end end
			if key == "GetMarkerReachedSignal" then return function(_, name) return getSignal("marker:" .. name) end end
			if key == "TweenSize" or key == "TweenPosition" then return function() return true end end
			if key == "Play" or key == "Stop" or key == "AdjustSpeed" or key == "Destroy2" then
				return function() return nil end
			end
			if key == "_addChild" then
				return function(child) table.insert(children, child) end
			end
			if key == "_removeChild" then
				return function(child)
					for index, entry in ipairs(children) do
						if entry == child then table.remove(children, index) break end
					end
				end
			end
			-- event-like properties resolve to signals on demand
			local eventNames = {
				MouseButton1Click = true, MouseButton1Down = true, MouseButton2Click = true,
				MouseEnter = true, MouseLeave = true, InputBegan = true, InputChanged = true,
				InputEnded = true, Activated = true, Focused = true, FocusLost = true,
				Changed = true, ChildAdded = true, ChildRemoved = true, Destroying = true,
				AncestryChanged = true, Stopped = true, Died = true, Equipped = true, Unequipped = true,
			}
			if eventNames[key] then return getSignal(key) end
			if properties[key] ~= nil then return properties[key] end
			-- Roblox resolves unknown keys to a child with that name (status.UIStroke).
			for _, child in ipairs(children) do
				if child.Name == key then return child end
			end
			return nil
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				if properties.Parent then properties.Parent._removeChild(self) end
				properties.Parent = value
				if value then value._addChild(self) end
				return
			end
			properties[key] = value
			if signals["prop:" .. key] then signals["prop:" .. key]:Fire() end
		end,
	})
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

local TweenService = makeService("TweenService")

local Players = makeService("Players")
local localPlayer = newInstance("Player")
localPlayer.Name = "TestPlayer"
localPlayer.DisplayName = "Test Player"
localPlayer.UserId = 1234
Players.LocalPlayer = localPlayer
Players.PlayerAdded = newSignal()
Players.PlayerRemoving = newSignal()

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
			pieces[#pieces + 1] = (node % 1 == 0) and ("%d"):format(node) or tostring(node)
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
				position += 1 -- colon
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
		instanceCount += 1
		local id = ("%08x-guid-%d"):format(math.random(0, 0xffffff), instanceCount)
		return wrap == false and id or "{" .. id .. "}"
	end,
}

-- ---------- game ----------
local services = {
	RunService = RunService,
	UserInputService = UserInputService,
	TweenService = TweenService,
	Players = Players,
	HttpService = HttpService,
	CoreGui = makeService("CoreGui"),
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
}

local serviceMethodMap = {
	[RunService] = runServiceMethods,
	[HttpService] = httpMethods,
	[UserInputService] = {
		GetMouseLocation = function() return mouseLocation end,
		GetMouseDelta = function() return newVector2(0, 0) end,
		IsKeyDown = function() return false end,
		GetFocusedTextBox = function() return nil end,
	},
	[TweenService] = {
		Create = function(_, target, _, goals)
			return {
				Play = function()
					for key, value in pairs(goals) do
						pcall(function() target[key] = value end)
					end
				end,
				Cancel = function() end,
				Completed = newSignal(),
			}
		end,
	},
	[services.ContextActionService] = {
		BindAction = function() end,
		BindActionAtPriority = function() end,
		UnbindAction = function() end,
		SetPosition = function() end,
		SetTitle = function() end,
		SetImage = function() end,
	},
	[Players] = {
		GetPlayers = function() return { localPlayer } end,
		GetPlayerFromCharacter = function() return nil end,
		GetUserThumbnailAsync = function() return "rbxassetid://0", true end,
	},
	[services.GuiService] = { GetGuiInset = function() return newVector2(0, 36), newVector2(0, 0) end },
	[services.Workspace] = { Raycast = function() return nil end },
	[services.TextService] = { GetTextSize = function() return newVector2(120, 16) end },
	[services.StarterGui] = { SetCore = function() end },
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
		if key == "HttpGet" then return function(_, url) return sandbox.httpGet(url) end end
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
	NumberSequence = { new = function(keypoints) return setmetatable({ Keypoints = keypoints }, NumberSequence) end },
	NumberSequenceKeypoint = { new = function(time, value) return { Time = time, Value = value } end },
	ColorSequence = { new = function(keypoints) return setmetatable({ Keypoints = keypoints }, ColorSequence) end },
	ColorSequenceKeypoint = { new = function(time, value) return { Time = time, Value = value } end },
	TweenInfo = { new = function(...) return { ... } end },
	CFrame = { new = function() return {} end, Angles = function() return {} end, lookAt = function() return {} end },
	tick = os.clock,
	task = nil, -- assigned below
	typeof = function(value)
		local meta = getmetatable(value)
		if meta == Color3 then return "Color3" end
		if meta == UDim2 then return "UDim2" end
		if meta == UDim then return "UDim" end
		if meta == Vector2 then return "Vector2" end
		if meta == Vector3 then return "Vector3" end
		if meta == Rect then return "Rect" end
		if type(value) == "table" and value.ClassName then return "Instance" end
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
	listfiles = function()
		local out = {}
		for path in pairs(files) do out[#out + 1] = path end
		return out
	end,
}
sandbox.warnings = {}

-- Deterministic task scheduler: delayed work is queued so tests control time.
local scheduled = {}
sandbox.scheduled = scheduled
sandbox.clock = 0

local function runSafely(callback, ...)
	local ok, err = pcall(callback, ...)
	if not ok then sandbox.signalErrors[#sandbox.signalErrors + 1] = tostring(err) end
end

environment.task = {
	spawn = function(callback, ...)
		runSafely(callback, ...)
		return {}
	end,
	defer = function(callback, ...)
		runSafely(callback, ...)
		return {}
	end,
	delay = function(seconds, callback, ...)
		scheduled[#scheduled + 1] = { at = sandbox.clock + (tonumber(seconds) or 0), callback = callback, args = { ... } }
		return {}
	end,
	wait = function(seconds) return tonumber(seconds) or 0 end,
	cancel = function() end,
	synchronize = function() end,
	desynchronize = function() end,
}

-- Runs every callback whose delay has elapsed.
function sandbox.advance(seconds)
	sandbox.clock += tonumber(seconds) or 0
	local due, remaining = {}, {}
	for _, entry in ipairs(scheduled) do
		if entry.at <= sandbox.clock then due[#due + 1] = entry else remaining[#remaining + 1] = entry end
	end
	table.clear(scheduled)
	for _, entry in ipairs(remaining) do scheduled[#scheduled + 1] = entry end
	for _, entry in ipairs(due) do runSafely(entry.callback, table.unpack(entry.args)) end
	return #due
end

environment.wait = environment.task.wait
environment.spawn = environment.task.spawn
environment.delay = function(seconds, callback) return environment.task.delay(seconds, callback) end

environment.getgenv = function() return environment end
sandbox.httpGet = function() return "" end
sandbox.environment = environment
sandbox.services = services
sandbox.Signal = { new = newSignal }
sandbox.UserInputService = UserInputService
sandbox.RunService = RunService
sandbox.Players = Players

function sandbox.load(sourcePath)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local source = fs.readFile(sourcePath)
	setmetatable(environment, { __index = _G })
	local chunk = luau.load(source, { debugName = sourcePath, environment = environment, injectGlobals = true })
	return chunk()
end

return sandbox
