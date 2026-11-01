--!nocheck
-- Flags, the commit bus, autosave and the configuration file (v1 format, byte-compatible).
-- One configuration per library load, owned by the most recent CreateWindow (D9); the tables
-- below are cleared in place so references held by scripts stay valid.

local Signal = require("core/Signal")
local Util = require("core/Util")
local Env = require("core/Env")
local FS = require("persist/FS")
local Codec = require("persist/Codec")

local Store = {}
Store.flags = {}
Store.pending = {}
Store.listeners = {}
Store.flagChanged = Signal.new("Store.flagChanged")
Store.saved = Signal.new("Store.saved")
Store.config = nil
Store.ready = false
Store.generation = 0
Store.loading = false
Store.destroyed = false
Store.saveToken = 0
Store.state = "idle"
Store.info = {}
Store.profile = nil -- nil = the default file

-- Hooks set by the facade.
Store.exportPrefs = function() return nil end
Store.applyPrefs = function(_) end
Store.windows = function() return {} end

-- The 13 v1 library-settings flags, now read and written through Prefs.
Store.virtualFlags = {
	ArgonUIWindowTitle = "Title", ArgonUIWindowSubtitle = "Subtitle", ArgonUITheme = "Theme",
	ArgonUIFont = "Font", ArgonUIPlayerList = "PlayerListEnabled", ArgonUIKeybindList = "KeybindListEnabled",
	ArgonUIOverlaysAlwaysVisible = "OverlaysAlwaysVisible", ArgonUIPlayerListKey = "PlayerListKey",
	ArgonUIKeybindListKey = "KeybindListKey", ArgonUISmoothTransitions = "SmoothTransitions",
	ArgonUIOverlayOpacity = "OverlayTransparency", ArgonUIOverlayScale = "OverlayScale",
	ArgonUICustomLogo = "Logo",
}
Store.prefsGet = function(_) return nil end
Store.prefsSet = function(_, _) end

function Store.configure(config)
	Store.config = type(config) == "table" and config or { Enabled = false }
end

-- Folder/File.ext for the default profile, or Folder/Base.profiles/Name.ext.
function Store.path(profile)
	local config = Store.config
	if not config or not config.Enabled then return nil end
	local folder = tostring(config.FolderName or "ArgonUI")
	local file = tostring(config.FileName or "Argon")
	local extension = config.FileExtension or ".rfld"
	if not file:match("%.[%w_%-]+$") then file = file .. extension end
	if profile and profile ~= "Default" then
		local base, ext = file:match("^(.*)(%.[%w_%-]+)$")
		return folder .. "/" .. (base or file) .. ".profiles/" .. profile .. (ext or extension), folder
	end
	return folder .. "/" .. file, folder
end

local function payload(element)
	if element._payload then return element:_payload() end
	return element.CurrentValue
end

function Store.valueOf(element)
	if element.Type == "Dropdown" then return Util.copy(element.CurrentOption) end
	if element.Type == "Keybind" then return element.CurrentKeybind end
	return element.CurrentValue
end

function Store.encode(element)
	if element._encode then return element:_encode() end
	if element.Type == "Dropdown" then return Util.copy(element.CurrentOption) end
	if element.Type == "Keybind" then return Util.keyName(element.CurrentKeybind or element.CurrentValue) end
	return Util.copy(element.CurrentValue)
end

-- Fires the flag listeners and the internal flagChanged signal.
function Store.notify(element)
	if not element or not element.Flag then return end
	local value = Store.valueOf(element)
	for _, listener in ipairs(table.clone(Store.listeners)) do
		local ok, err = pcall(listener, element.Flag, value, element)
		if not ok then warn("[Argon UI] Flag listener error for " .. tostring(element.Flag) .. ": " .. tostring(err)) end
	end
	Store.flagChanged:Fire(element.Flag, value, element)
end

function Store.scheduleSave()
	if not Store.ready or Store.loading or Store.destroyed or not Store.path(Store.profile) then return end
	Store.saveToken += 1
	local token = Store.saveToken
	Store.state = "pending"
	task.delay(0.35, function()
		if token ~= Store.saveToken or not Store.ready or Store.loading or Store.destroyed then return end
		local ok, err = Store.save(Store.profile)
		Store.info.lastAutosaveError = ok and nil or tostring(err)
		if not ok then warn("[Argon UI] Configuration autosave failed: " .. tostring(err)) end
	end)
end

function Store.commit(element)
	Store.notify(element)
	Store.scheduleSave()
end

-- Silent set, then the restore callback exactly once, then the listeners (v1 contract).
function Store.applyValue(element, raw)
	if not element or not element.Set then return false, "element is not settable" end
	local value, alpha = Codec.normalize(element.Type, raw)
	if alpha ~= nil then value = { Color = value, Alpha = alpha } end
	local setOk, setError = pcall(function() element:Set(value, true) end)
	if not setOk then return false, setError end
	local ok, err = true, nil
	if element._restoreCallback then
		ok, err = element:_restoreCallback()
	elseif type(element._callback) == "function" then
		ok, err = Util.xcall(element._callback, "restore of " .. tostring(element.Flag), element, payload(element))
	end
	Store.notify(element)
	if ok == false then return false, err end
	return true
end

function Store.register(flag, element)
	if flag == nil or flag == "" then return end
	element.Flag = flag
	local existing = Store.flags[flag]
	if existing and existing ~= element then
		warn("[Argon UI] Duplicate configuration flag replaced: " .. tostring(flag))
	end
	Store.flags[flag] = element
	local pending = Store.pending[flag]
	if pending ~= nil then
		local wasLoading = Store.loading
		Store.loading = true
		local ok, err = Store.applyValue(element, pending)
		Store.loading = wasLoading
		if ok then
			Store.pending[flag] = nil
		else
			warn("[Argon UI] Deferred configuration value failed for " .. tostring(flag) .. ": " .. tostring(err))
		end
	end
end

-- D8: a destroyed control leaves the registry; its last value is kept for the next save.
function Store.unregister(element)
	local flag = element.Flag
	if flag and Store.flags[flag] == element then
		Store.flags[flag] = nil
		Store.pending[flag] = Store.encode(element)
	end
end

function Store.get(flag)
	local virtual = Store.virtualFlags[flag]
	if virtual and Store.flags[flag] == nil then return Store.prefsGet(virtual) end
	local element = Store.flags[flag]
	if not element then return Store.pending[flag] end
	return Store.valueOf(element)
end

function Store.set(flag, value)
	local virtual = Store.virtualFlags[flag]
	if virtual and Store.flags[flag] == nil then
		Store.prefsSet(virtual, value)
		return true
	end
	local element = Store.flags[flag]
	if not element then
		Store.pending[flag] = Util.copy(value)
		Store.scheduleSave()
		return false, "flag is not registered yet; value stored"
	end
	local ok, err = Store.applyValue(element, value)
	if ok then Store.scheduleSave() end
	return ok, err
end

function Store.snapshot()
	local values = {}
	for flag in pairs(Store.flags) do values[flag] = Store.get(flag) end
	for flag, value in pairs(Store.pending) do
		if values[flag] == nil then values[flag] = Util.copy(value) end
	end
	return values
end

function Store.onFlagChanged(fn)
	assert(type(fn) == "function", "OnFlagChanged expects a function")
	table.insert(Store.listeners, fn)
	return function()
		local list = Store.listeners
		for index = #list, 1, -1 do
			if list[index] == fn then
				table.remove(list, index)
				break
			end
		end
	end
end

function Store.setReady(value, saveNow)
	Store.ready = value == true
	Store.saveToken += 1
	if Store.ready and saveNow == true then return Store.save(Store.profile) end
	return true
end

function Store.data()
	local data = {}
	for flag, value in pairs(Store.pending) do
		if flag ~= "__argon" and Store.flags[flag] == nil then data[flag] = Util.copy(value) end
	end
	for flag, element in pairs(Store.flags) do
		if flag ~= "__argon" then data[flag] = Store.encode(element) end
	end
	return data
end

function Store.save(profile)
	local path = Store.path(profile)
	if not path then return false, "configuration saving is disabled" end
	if not Env.has("writefile") then return false, "writefile is unavailable" end
	Store.state = "saving"
	local data = Store.data()
	local prefs = Store.exportPrefs()
	if prefs then data.__argon = prefs end
	local okEncode, encoded = pcall(FS.encode, data)
	if not okEncode then
		Store.info.lastError = "JSON encode failed: " .. tostring(encoded)
		Store.state = "failed"
		return false, Store.info.lastError
	end
	local ok, err = FS.write(path, encoded)
	if not ok then
		Store.info.lastError = err
		Store.state = "failed"
		return false, err
	end
	local count = 0
	for _ in pairs(data) do count += 1 end
	Store.info.lastError = nil
	Store.info.lastAutosaveError = nil
	Store.info.lastPath = path
	Store.info.lastSaveAt = os.clock()
	Store.info.savedAt = os.time()
	Store.info.count = count
	Store.state = "idle"
	if Store.afterSave then pcall(Store.afterSave) end
	Store.saved:Fire(profile or "Default", path, count)
	return true, path
end

local function findLoader()
	local loader
	for _, window in ipairs(Store.windows()) do
		if window._loading and window.SetLoadingProgress then loader = window end
	end
	return loader
end

function Store.load(profile)
	local path = Store.path(profile)
	if not path then return false, "configuration saving is disabled" end
	if not Env.has("readfile") then return false, "readfile is unavailable" end
	if not FS.exists(path) then
		-- Nothing to restore: allow autosave so the first change creates the file (D10).
		Store.ready = true
		return true, "no saved configuration: " .. path
	end
	local encoded, readError = FS.read(path)
	if not encoded then return false, "could not read " .. path .. ": " .. tostring(readError) end
	local data = FS.decode(encoded)
	if type(data) ~= "table" then return false, "invalid configuration JSON" end
	Store.loading = true
	Store.saveToken += 1
	local failures, missing, slowest = {}, {}, {}
	local applied, total = 0, 0
	local okApply, applyError = xpcall(function()
		if type(data.__argon) == "table" then
			local ok, err = pcall(Store.applyPrefs, Util.copy(data.__argon))
			if not ok then failures[#failures + 1] = "UI preferences: " .. tostring(err) end
		end
		local flags = {}
		for flag, value in pairs(data) do
			if flag ~= "__argon" then
				local virtual = Store.virtualFlags[flag]
				if virtual and Store.flags[flag] == nil then
					pcall(Store.prefsSet, virtual, value)
				else
					flags[#flags + 1] = flag
				end
			end
		end
		total = #flags
		table.sort(flags, function(left, right)
			local lb, rb = type(data[left]) == "boolean", type(data[right]) == "boolean"
			if lb ~= rb then return not lb end
			return tostring(left) < tostring(right)
		end)
		local loader = findLoader()
		local base = loader and math.clamp(loader._loadingProgress or 0.8, 0, 0.99) or 0
		local span = math.max(0.995 - base, 0)
		local every = math.max(1, math.floor(#flags / 40))
		local canYield = coroutine.isyieldable()
		local sliceStart = os.clock()
		for index, flag in ipairs(flags) do
			if loader and (index % every == 0 or index == #flags) then
				loader:SetLoadingProgress(base + span * (index / #flags),
					("Restoring settings · %d of %d"):format(index, #flags), "restore")
			end
			if canYield and os.clock() - sliceStart > 0.008 then
				task.wait()
				sliceStart = os.clock()
			end
			local started = os.clock()
			local element = Store.flags[flag]
			if element and element.Set then
				Store.pending[flag] = nil
				local ok, err = Store.applyValue(element, data[flag])
				if ok then applied += 1 else failures[#failures + 1] = tostring(flag) .. ": " .. tostring(err) end
			else
				Store.pending[flag] = Util.copy(data[flag])
				missing[#missing + 1] = tostring(flag)
			end
			local cost = (os.clock() - started) * 1000
			if cost >= 25 then slowest[#slowest + 1] = { flag = tostring(flag), ms = cost } end
		end
	end, function(err) return debug.traceback(tostring(err), 2) end)
	table.sort(slowest, function(a, b) return a.ms > b.ms end)
	local report = {}
	for position = 1, math.min(#slowest, 8) do
		report[position] = ("%s %.0fms"):format(slowest[position].flag, slowest[position].ms)
	end
	local slow = #report > 0 and table.concat(report, ", ") or nil
	Store.loading = false
	Store.info.lastStats = { path = path, total = total, applied = applied, missing = #missing, failed = #failures, slowest = slow }
	if slow then warn("[Argon UI] Slowest restore callbacks: " .. slow) end
	Store.ready = true
	Store.saveToken += 1
	Store.profile = profile
	if not okApply then
		Store.info.lastError = tostring(applyError)
		return false, "configuration apply failed: " .. tostring(applyError)
	end
	local warnings = {}
	if #failures > 0 then
		warnings[#warnings + 1] = ("%d value(s) failed: %s"):format(#failures, table.concat(failures, " | ", 1, math.min(#failures, 8)))
	end
	if #missing > 0 then
		warnings[#warnings + 1] = ("%d unknown/retired flag(s): %s"):format(#missing, table.concat(missing, ", ", 1, math.min(#missing, 12)))
	end
	local warning = #warnings > 0 and table.concat(warnings, " | ") or nil
	if warning then warn("[Argon UI] Configuration loaded with warnings: " .. warning) end
	Store.info.lastError = nil
	Store.info.lastPath = path
	Store.info.lastLoadAt = os.clock()
	if total > 0 and applied == 0 then
		-- D10: the values are parked and hydrate when their controls are built
		return true, ("%d value(s) waiting for controls"):format(total)
	end
	return true, warning
end

function Store.delete(profile)
	local path = Store.path(profile)
	if not path then return false, "configuration saving is disabled" end
	local ok, err = FS.delete(path)
	if not ok then return false, err end
	return true, path
end

function Store.reset()
	Store.loading = true
	Store.saveToken += 1
	table.clear(Store.pending)
	local ok, err = Store.delete(Store.profile)
	Store.loading = false
	Store.info.lastStats = nil
	return ok, err
end

function Store.stats()
	local path = Store.path(Store.profile)
	local pending, registered = 0, 0
	for _ in pairs(Store.pending) do pending += 1 end
	for _ in pairs(Store.flags) do registered += 1 end
	return {
		Path = path, Enabled = path ~= nil, Ready = Store.ready == true, Loading = Store.loading == true,
		RegisteredFlags = registered, PendingFlags = pending, LastError = Store.info.lastError,
		LastAutosaveError = Store.info.lastAutosaveError, LastSaveAt = Store.info.lastSaveAt,
		LastLoadAt = Store.info.lastLoadAt, LastLoad = Store.info.lastStats,
		Profile = Store.profile or "Default", SaveState = Store.state, SavedAt = Store.info.savedAt,
	}
end

-- Resets the per-window state (CreateWindow, D9: clear in place).
function Store.resetForWindow(config)
	table.clear(Store.flags)
	table.clear(Store.pending)
	-- Timers armed for an earlier window compare this before touching the new window's state.
	Store.generation = (Store.generation or 0) + 1
	Store.ready = false
	Store.loading = false
	Store.destroyed = false
	Store.saveToken += 1
	Store.profile = nil
	Store.configure(config)
end

return Store
