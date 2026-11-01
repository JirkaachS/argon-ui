--!nocheck
-- UI preferences: one store for theme, font, scale, window geometry, keys and so on. Read
-- synchronously at CreateWindow, before the first instance, and written to a small meta file
-- next to the configuration (or ArgonUI/<GuiName>.meta.json when saving is off).

local Signal = require("core/Signal")
local Util = require("core/Util")
local FS = require("persist/FS")
local Store = require("persist/Store")

local Prefs = {}
Prefs.table = {}
Prefs.changed = Signal.new("Prefs.changed")
Prefs.path = nil
Prefs.meta = { v = 2 }

-- v1 keys that live in the __argon block of the configuration file.
Prefs.V1 = {
	"Theme", "Font", "Title", "Subtitle", "Logo", "PlayerListEnabled", "KeybindListEnabled",
	"OverlaysAlwaysVisible", "OverlayTransparency", "OverlayScale", "SmoothTransitions", "OverlayPositions",
}

local function metaPath(config, guiName)
	if config and config.Enabled then
		local folder = tostring(config.FolderName or "ArgonUI")
		local file = tostring(config.FileName or "Argon"):gsub("%.[%w_%-]+$", "")
		return folder .. "/" .. file .. ".meta.json"
	end
	return "ArgonUI/" .. tostring(guiName or "ArgonUI") .. ".meta.json"
end

-- Reads the meta file (or migrates the configuration file's __argon block), then merges the
-- host's pre-assigned preference table over it. Synchronous; no yields.
function Prefs.loadForWindow(config, guiName, assigned)
	local prefs = {}
	Prefs.path = metaPath(config, guiName)
	Prefs.meta = { v = 2 }
	local text = FS.read(Prefs.path)
	local meta = text and FS.decode(text)
	if type(meta) == "table" and type(meta.Prefs) == "table" then
		Prefs.meta = meta
		for key, value in pairs(meta.Prefs) do prefs[key] = value end
	elseif config and config.Enabled then
		local path = Store.path()
		local legacy = path and FS.read(path)
		local data = legacy and FS.decode(legacy)
		if type(data) == "table" and type(data.__argon) == "table" then
			for key, value in pairs(data.__argon) do prefs[key] = value end
		end
	end
	if type(assigned) == "table" then
		for key, value in pairs(assigned) do prefs[key] = value end
	end
	Prefs.table = prefs
	return prefs
end

function Prefs.get(key)
	return Prefs.table[key]
end

local saveToken = 0
function Prefs.scheduleSave()
	if not Prefs.path or not FS.available() then return end
	saveToken += 1
	local token = saveToken
	task.delay(0.35, function()
		if token ~= saveToken then return end
		Prefs.saveNow()
	end)
end

function Prefs.saveNow()
	if not Prefs.path or not FS.available() then return false end
	Prefs.meta.v = 2
	Prefs.meta.Prefs = Prefs.table
	local ok, encoded = pcall(FS.encode, Prefs.meta)
	if not ok then return false end
	return FS.write(Prefs.path, encoded)
end

-- An explicit configuration save writes the preferences file too.
Store.afterSave = function() Prefs.saveNow() end

-- Sets a preference, fires Prefs.changed and schedules a meta save.
function Prefs.set(key, value, silent)
	if Util.jsonEqual(Prefs.table[key], value) then return end
	Prefs.table[key] = value
	if not silent then Prefs.changed:Fire(key, value) end
	Prefs.scheduleSave()
	Store.scheduleSave()
end

-- Per-profile preference (pins, hide hint).
function Prefs.getProfile(key)
	local byProfile = Prefs.table[key .. "ByProfile"]
	if type(byProfile) ~= "table" then return nil end
	return byProfile[Store.profile or "Default"]
end

function Prefs.setProfile(key, value)
	local byProfile = Util.copy(Prefs.table[key .. "ByProfile"] or {})
	byProfile[Store.profile or "Default"] = value
	Prefs.set(key .. "ByProfile", byProfile)
end

-- The __argon block written into configuration files (v1 keys plus v2 keys).
function Prefs.export()
	return Util.copy(Prefs.table)
end

function Prefs.metaField(key, value)
	if value == nil then return Prefs.meta[key] end
	Prefs.meta[key] = value
	Prefs.scheduleSave()
end

return Prefs
