--!nocheck
-- Named configuration profiles, autoload, and the ARGON2 export/import format.

local Util = require("core/Util")
local FS = require("persist/FS")
local Codec = require("persist/Codec")
local Store = require("persist/Store")
local Prefs = require("persist/Prefs")

local Profiles = {}

local function sanitize(name)
	name = Util.trim(tostring(name or "")):gsub("[^%w _%-]", "")
	return Util.truncate(name, 40)
end
Profiles.sanitize = sanitize

local function folderAndExt()
	local path = Store.path("_probe")
	if not path then return nil end
	local folder, ext = path:match("^(.*)/_probe(%.[%w_%-]+)$")
	return folder, ext
end

local function info(name)
	local all = Prefs.metaField("Profiles") or {}
	return all[name] or {}
end

local function setInfo(name, data)
	local all = Util.copy(Prefs.metaField("Profiles") or {})
	all[name] = data
	Prefs.metaField("Profiles", all)
end

function Profiles.list()
	local out = {}
	local autoload = Profiles.getAutoload()
	local defaultPath = Store.path()
	if defaultPath then
		local meta = info("Default")
		out[1] = { Name = "Default", Path = defaultPath, Autoload = autoload == nil or autoload == "Default",
			Count = meta.count, SavedAt = meta.savedAt, Active = (Store.profile or "Default") == "Default" }
	end
	local folder, ext = folderAndExt()
	if folder then
		for _, name in ipairs(FS.list(folder, ext)) do
			if name ~= "Default" then
				local meta = info(name)
				out[#out + 1] = { Name = name, Path = Store.path(name), Autoload = autoload == name,
					Count = meta.count, SavedAt = meta.savedAt, Active = Store.profile == name }
			end
		end
	end
	return out
end

local function record(name)
	local count = 0
	for _ in pairs(Store.data()) do count += 1 end
	setInfo(name, { count = count, savedAt = os.time() })
end

function Profiles.save(name)
	name = sanitize(name)
	if name == "" then return false, "a profile needs a name" end
	local ok, err = Store.save(name)
	if ok then
		Store.profile = name ~= "Default" and name or nil
		record(name)
		Prefs.metaField("LastProfile", name)
	end
	return ok, err
end

function Profiles.load(name)
	name = sanitize(name)
	local ok, result = Store.load(name ~= "Default" and name or nil)
	if ok then Prefs.metaField("LastProfile", name) end
	return ok, result
end

function Profiles.delete(name)
	name = sanitize(name)
	if name == "Default" then return Store.reset() end
	local ok, err = Store.delete(name)
	if ok then
		setInfo(name, nil)
		if Profiles.getAutoload() == name then Profiles.setAutoload(nil) end
		if Store.profile == name then Store.profile = nil end
	end
	return ok, err
end

function Profiles.rename(old, new)
	old, new = sanitize(old), sanitize(new)
	if old == "Default" or new == "" or new == "Default" then return false, "that profile cannot be renamed" end
	local text = FS.read(Store.path(old) or "")
	if not text then return false, "profile not found: " .. old end
	local ok, err = FS.write(Store.path(new), text)
	if not ok then return false, err end
	FS.delete(Store.path(old))
	setInfo(new, info(old))
	setInfo(old, nil)
	if Profiles.getAutoload() == old then Profiles.setAutoload(new) end
	if Store.profile == old then Store.profile = new end
	return true
end

function Profiles.duplicate(name, newName)
	name, newName = sanitize(name), sanitize(newName)
	if newName == "" then return false, "a profile needs a name" end
	local text = FS.read(Store.path(name ~= "Default" and name or nil) or "")
	if not text then return false, "profile not found: " .. name end
	local ok, err = FS.write(Store.path(newName), text)
	if ok then setInfo(newName, info(name)) end
	return ok, err
end

function Profiles.setAutoload(name)
	Prefs.metaField("Autoload", name and sanitize(name) or false)
end

function Profiles.getAutoload()
	local value = Prefs.metaField("Autoload")
	if type(value) == "string" and value ~= "" then return value end
	return nil
end

-- "ARGON2:" .. base64(JSON {v, profile, flags}).
function Profiles.export(name)
	local flags = Store.data()
	if name and sanitize(name) ~= (Store.profile or "Default") then
		local text = FS.read(Store.path(sanitize(name) ~= "Default" and sanitize(name) or nil) or "")
		local data = text and FS.decode(text)
		if type(data) == "table" then
			data.__argon = nil
			flags = data
		end
	end
	local ok, encoded = pcall(FS.encode, { v = 2, profile = name or Store.profile or "Default", flags = flags })
	if not ok then return nil end
	return "ARGON2:" .. Codec.base64(encoded)
end

-- Accepts an ARGON2 string or a raw JSON object (v1 / Rayfield file). opts.apply applies the
-- values through Store.set (callbacks fire); opts.saveAs writes them as a profile.
function Profiles.import(text, opts)
	opts = opts or {}
	text = Util.trim(tostring(text or ""))
	local flags
	if text:sub(1, 7) == "ARGON2:" then
		local decoded = FS.decode(Codec.unbase64(text:sub(8)))
		flags = type(decoded) == "table" and decoded.flags
	else
		local decoded = FS.decode(text)
		flags = type(decoded) == "table" and decoded
	end
	if type(flags) ~= "table" then return false, { changed = 0, unknown = 0, invalid = 1 } end
	flags.__argon = nil
	local summary = { changed = 0, unknown = 0, invalid = 0 }
	for flag, value in pairs(flags) do
		local element = Store.flags[flag]
		if not element then
			summary.unknown += 1
		elseif not Util.jsonEqual(Store.encode(element), value) then
			summary.changed += 1
		end
	end
	if opts.apply then
		for flag, value in pairs(flags) do
			local ok = Store.set(flag, value)
			if not ok and Store.flags[flag] then summary.invalid += 1 end
		end
	end
	if opts.saveAs then
		local ok, encoded = pcall(FS.encode, flags)
		if ok then FS.write(Store.path(sanitize(opts.saveAs)), encoded) end
	end
	return true, summary
end

return Profiles
