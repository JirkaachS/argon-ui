--!nocheck
-- Executor filesystem wrappers. Every call is optional and pcall'd; without a filesystem the
-- library still works, it just cannot persist.

local Env = require("core/Env")

local FS = {}

function FS.available()
	return Env.has("writefile") and Env.has("readfile")
end

function FS.exists(path)
	local check = Env.fn("isfile")
	if check then
		local ok, value = pcall(check, path)
		return ok and value == true
	end
	local reader = Env.fn("readfile")
	if reader then return (pcall(reader, path)) end
	return false
end

function FS.read(path)
	local reader = Env.fn("readfile")
	if not reader then return nil, "readfile is unavailable" end
	if not FS.exists(path) then return nil, "missing" end
	local ok, value = pcall(reader, path)
	if not ok then return nil, tostring(value) end
	return value
end

function FS.ensureFolder(path)
	if not path or path == "" then return true end
	local check, create = Env.fn("isfolder"), Env.fn("makefolder")
	if check then
		local ok, value = pcall(check, path)
		if ok and value == true then return true end
	end
	if not create then return false, "makefolder is unavailable" end
	local ok, err = pcall(create, path)
	if ok then return true end
	if check then
		local checkOk, value = pcall(check, path)
		if checkOk and value == true then return true end
	end
	return false, tostring(err)
end

-- Writes and verifies (read back when possible). Returns ok, err.
function FS.write(path, contents)
	local writer = Env.fn("writefile")
	if not writer then return false, "writefile is unavailable" end
	local folder = path:match("^(.*)/[^/]*$")
	if folder then
		-- nested folders (Folder/Base.profiles) are created one level at a time
		local built = ""
		for part in folder:gmatch("[^/]+") do
			built = built == "" and part or (built .. "/" .. part)
			local ok, err = FS.ensureFolder(built)
			if not ok then return false, "could not create folder " .. built .. ": " .. tostring(err) end
		end
	end
	local ok, err = pcall(writer, path, contents)
	if not ok then return false, "could not write " .. path .. ": " .. tostring(err) end
	local reader = Env.fn("readfile")
	if reader then
		local verifyOk, written = pcall(reader, path)
		if not verifyOk or written ~= contents then
			return false, "write verification failed for " .. path .. (verifyOk and " (content mismatch)" or (": " .. tostring(written)))
		end
	elseif not FS.exists(path) then
		return false, "write could not be verified for " .. path
	end
	return true
end

function FS.delete(path)
	local remove = Env.fn("delfile")
	if not remove then return false, "delfile is unavailable" end
	if not FS.exists(path) then return true end
	local ok, err = pcall(remove, path)
	if not ok then return false, tostring(err) end
	return true
end

-- Base names (no folder, no extension) of the files in a folder.
function FS.list(folder, extension)
	local lister = Env.fn("listfiles")
	if not lister then return {} end
	local ok, entries = pcall(lister, folder)
	if not ok or type(entries) ~= "table" then return {} end
	local out = {}
	for _, entry in ipairs(entries) do
		local text = tostring(entry):gsub("\\", "/")
		local inFolder = text:sub(1, #folder + 1) == folder .. "/" or not text:find("/")
		local base = text:match("([^/]+)$")
		if inFolder and base and (not extension or base:sub(-#extension) == extension) then
			out[#out + 1] = extension and base:sub(1, -#extension - 1) or base:gsub("%.[^%.]+$", "")
		end
	end
	table.sort(out)
	return out
end

function FS.encode(value)
	return Env.services.HttpService:JSONEncode(value)
end

function FS.decode(text)
	local ok, value = pcall(function() return Env.services.HttpService:JSONDecode(text) end)
	if ok then return value end
	return nil
end

return FS
