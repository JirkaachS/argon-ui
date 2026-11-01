--!nocheck
-- The single input entry point: one UserInputService.InputBegan connection per library,
-- O(1) key dispatch, hold tracking (InputEnded only while a hold is down), layer consumers
-- for the close key and focus navigation, and ContextActionService sinks.

local Env = require("core/Env")
local Signal = require("core/Signal")

local Router = {}
Router.lastInputKind = "mouse"
Router.inputKindChanged = Signal.new("Router.inputKindChanged")

local map = {}
local consumers = {}
local holds = {}
local holdCount = 0
local began, ended = nil, nil
local refs = 0
local sinks = {}

local function classify(inputType)
	local name = inputType and inputType.Name or ""
	if name == "Keyboard" then return "keyboard" end
	if name == "Touch" then return "touch" end
	if name:sub(1, 7) == "Gamepad" then return "gamepad" end
	if name:sub(1, 5) == "Mouse" then return "mouse" end
	return nil
end
Router.classify = classify

local function keyOf(input)
	local inputType = input.UserInputType
	local name = inputType and inputType.Name or ""
	if name == "Keyboard" or name:sub(1, 7) == "Gamepad" then return input.KeyCode end
	return inputType
end

local function typing()
	local uis = Env.services.UserInputService
	local ok, box = pcall(function() return uis:GetFocusedTextBox() end)
	return ok and box ~= nil
end
Router.typing = typing

local function disconnectEnded()
	if ended then
		ended:Disconnect()
		ended = nil
	end
end

local function onEnded(input)
	local key = keyOf(input)
	local list = holds[key]
	if not list then return end
	holds[key] = nil
	holdCount -= 1
	for _, entry in ipairs(list) do
		if entry.onRelease then
			local ok, err = pcall(entry.onRelease, input)
			if not ok then warn("[Argon UI] key release handler error: " .. tostring(err)) end
		end
	end
	if holdCount <= 0 then
		holdCount = 0
		disconnectEnded()
	end
end

local function trackHold(entry, key)
	local list = holds[key]
	if not list then
		list = {}
		holds[key] = list
		holdCount += 1
	end
	list[#list + 1] = entry
	if not ended then
		local uis = Env.services.UserInputService
		ended = uis.InputEnded:Connect(onEnded)
	end
end

function Router.dispatch(input, gameProcessed)
	local kind = classify(input.UserInputType)
	if kind and kind ~= Router.lastInputKind then
		Router.lastInputKind = kind
		Router.inputKindChanged:Fire(kind)
	end
	local isTyping = typing()
	for index = #consumers, 1, -1 do
		local consumer = consumers[index]
		if not isTyping or consumer.allowTyping then
			local ok, consumed = pcall(consumer.fn, input, gameProcessed, isTyping)
			if not ok then
				warn("[Argon UI] input consumer error: " .. tostring(consumed))
			elseif consumed then
				return
			end
		end
	end
	local key = keyOf(input)
	local list = key and map[key]
	if not list then return end
	for _, entry in ipairs(table.clone(list)) do
		if (not isTyping or entry.allowWhileTyping) and (not gameProcessed or entry.allowProcessed)
			and (not entry.enabled or entry.enabled()) then
			if entry.onPress then
				local ok, err = pcall(entry.onPress, input)
				if not ok then warn("[Argon UI] key handler error: " .. tostring(err)) end
			end
			if entry.mode == "Hold" then trackHold(entry, key) end
		end
	end
end

function Router.attach()
	refs += 1
	if began then return end
	local uis = Env.services.UserInputService
	if uis then
		began = uis.InputBegan:Connect(Router.dispatch)
	end
end

function Router.detach()
	refs -= 1
	if refs > 0 then return end
	refs = 0
	if began then
		began:Disconnect()
		began = nil
	end
	disconnectEnded()
	table.clear(holds)
	holdCount = 0
end

local function sortList(list)
	table.sort(list, function(a, b) return (a.priority or 50) > (b.priority or 50) end)
end

-- Binds entry {key, owner, mode, onPress, onRelease, enabled, allowWhileTyping, priority}.
-- Returns a handle with :rebind(key) and :unbind().
function Router.bind(entry)
	local handle = { entry = entry, bound = false }
	local function add()
		local key = entry.key
		if not key then return end
		local list = map[key]
		if not list then
			list = {}
			map[key] = list
		end
		list[#list + 1] = entry
		sortList(list)
		handle.bound = true
	end
	local function remove()
		local key = entry.key
		local list = key and map[key]
		if list then
			for index = #list, 1, -1 do
				if list[index] == entry then table.remove(list, index) end
			end
			if #list == 0 then map[key] = nil end
		end
		handle.bound = false
	end
	function handle:rebind(key)
		remove()
		entry.key = key
		add()
		return handle
	end
	function handle:unbind()
		remove()
	end
	add()
	return handle
end

-- Every binding on a key (for conflict checks).
function Router.lookup(key)
	return table.clone(map[key] or {})
end

-- Adds a consumer that sees every non-typing input first; return true to consume it.
function Router.layerKey(fn, priority, allowTyping)
	local consumer = { fn = fn, priority = priority or 0, allowTyping = allowTyping == true }
	consumers[#consumers + 1] = consumer
	table.sort(consumers, function(a, b) return a.priority < b.priority end)
	return {
		remove = function()
			for index = #consumers, 1, -1 do
				if consumers[index] == consumer then table.remove(consumers, index) end
			end
		end,
	}
end

-- Sinks keys through ContextActionService so the game does not act on them (for example
-- Backspace dropping a tool while a popover is open, or arrows moving the character in focus mode).
function Router.sink(name, on, keys)
	local cas = Env.services.ContextActionService
	if not cas then return end
	if on and not sinks[name] then
		sinks[name] = true
		pcall(function()
			local sinkResult = Env.enum("ContextActionResult", "Sink")
			local priority = (Enum.ContextActionPriority.High.Value or 3000) + 1
			cas:BindActionAtPriority(name, function() return sinkResult end, false, priority, table.unpack(keys))
		end)
	elseif not on and sinks[name] then
		sinks[name] = nil
		pcall(function() cas:UnbindAction(name) end)
	end
end

function Router.isDown(keyCode)
	local uis = Env.services.UserInputService
	local ok, down = pcall(function() return uis:IsKeyDown(keyCode) end)
	return ok and down == true
end

function Router.stats()
	local entries = 0
	for _, list in pairs(map) do entries += #list end
	return { handlers = began and 1 or 0, holdActive = ended ~= nil, entries = entries, consumers = #consumers }
end

return Router
