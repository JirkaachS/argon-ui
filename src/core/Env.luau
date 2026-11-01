--!nocheck
-- Environment probes: services, executor globals, GUI parenting, clipboard, clock and enums.
-- Every executor function is optional and looked up through here, so plain Studio and any
-- executor that lacks a function behave the same way: the feature is skipped, nothing errors.

local Env = {}

local serviceCache = {}
Env.services = setmetatable({}, {
	__index = function(_, name)
		local cached = serviceCache[name]
		if cached ~= nil then return cached or nil end
		local ok, service = pcall(game.GetService, game, name)
		serviceCache[name] = ok and service or false
		return ok and service or nil
	end,
})

function Env.localPlayer()
	local players = Env.services.Players
	return players and players.LocalPlayer
end

-- The executor's global table when there is one, else shared, else _G.
function Env.genv()
	local ok, env = pcall(function() return getgenv and getgenv() end)
	if ok and type(env) == "table" then return env end
	if type(shared) == "table" then return shared end
	return _G
end

local SYN = { readfile = true, writefile = true, isfile = true, isfolder = true, makefolder = true, delfile = true, listfiles = true }

-- An executor function by name, or nil. Checks the global, the executor table and syn.*.
function Env.fn(name)
	local ok, value = pcall(function()
		local direct = _G[name]
		if type(direct) == "function" then return direct end
		local env = Env.genv()
		local found = env[name]
		if type(found) == "function" then return found end
		if SYN[name] then
			local syn = env.syn or _G.syn
			if type(syn) == "table" and type(syn[name]) == "function" then return syn[name] end
		end
		return nil
	end)
	return ok and value or nil
end

function Env.has(name)
	return Env.fn(name) ~= nil
end

-- Calls an executor function under pcall; returns ok, result.
function Env.call(name, ...)
	local fn = Env.fn(name)
	if not fn then return false, name .. " is unavailable" end
	return pcall(fn, ...)
end

-- Parents a ScreenGui to the safest place available: gethui(), then CoreGui, then PlayerGui.
function Env.parentGui(gui)
	local hui = Env.fn("gethui")
	if hui then
		local ok, container = pcall(hui)
		if ok and typeof(container) == "Instance" and pcall(function() gui.Parent = container end) and gui.Parent == container then
			return container
		end
	end
	local core = Env.services.CoreGui
	if core and pcall(function() gui.Parent = core end) and gui.Parent == core then
		return core
	end
	local player = Env.localPlayer()
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		pcall(function() gui.Parent = playerGui end)
		return playerGui
	end
	return gui.Parent
end

function Env.protectGui(gui)
	pcall(function()
		local env = Env.genv()
		local syn = env.syn or _G.syn
		if type(syn) == "table" and type(syn.protect_gui) == "function" then
			syn.protect_gui(gui)
		elseif type(env.protectgui) == "function" then
			env.protectgui(gui)
		end
	end)
end

-- Copies text to the system clipboard. False when the executor has no clipboard.
function Env.setClipboard(text)
	local fn = Env.fn("setclipboard") or Env.fn("toclipboard")
	if not fn then return false end
	return (pcall(fn, tostring(text)))
end

-- Reads the system clipboard where the executor allows it. nil otherwise.
function Env.getClipboard()
	local fn = Env.fn("getclipboard")
	if not fn then return nil end
	local ok, value = pcall(fn)
	if ok and type(value) == "string" then return value end
	return nil
end

-- Overridable for tests.
Env._clock = nil
function Env.clock()
	local override = Env._clock
	if override then return override() end
	return os.clock()
end

-- Time that advances with frames and timers (time() in Roblox); os.clock elsewhere.
function Env.now()
	local ok, value = pcall(function() return time() end)
	if ok and type(value) == "number" then return value end
	return os.clock()
end

local enumCache = {}
-- An enum item by name, or the fallback item, or nil. Never errors.
function Env.enum(enumName, item, fallback)
	local key = enumName .. "." .. item
	local cached = enumCache[key]
	if cached ~= nil then return cached or nil end
	local ok, value = pcall(function() return Enum[enumName][item] end)
	if not ok or value == nil then
		if fallback then
			ok, value = pcall(function() return Enum[enumName][fallback] end)
		end
	end
	enumCache[key] = (ok and value) or false
	return (ok and value) or nil
end

-- Sets a property that might not exist on older clients; returns whether it stuck.
function Env.try(inst, prop, value)
	return (pcall(function() inst[prop] = value end))
end

function Env.isStudio()
	local run = Env.services.RunService
	local ok, studio = pcall(function() return run:IsStudio() end)
	return ok and studio == true
end

local canProfile = nil
function Env.profileBegin(label)
	if canProfile == nil then
		canProfile = type(debug) == "table" and type(debug.profilebegin) == "function"
	end
	if canProfile then debug.profilebegin(label) end
end
function Env.profileEnd()
	if canProfile then debug.profileend() end
end

return Env
