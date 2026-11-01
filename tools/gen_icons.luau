--!nocheck
-- Writes src/icons/IconData.luau from latte-soft/lucide-roblox's lib/Icons.luau.
-- Usage, from the repository root:
--   lune run tools/gen_icons.luau --source <path/to/Icons.luau>
--   lune run tools/gen_icons.luau --fetch <commit-sha>
-- The input is pattern-scanned and never executed. Every icon becomes three base-36 digits
-- (sheet, x index, y index) after its name, and the sorted names are front-coded, so all
-- 1,573 icons cost about 18 KB in the bundle and decode in a couple of milliseconds.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

-- Every glyph the library itself draws. These resolve without decoding the packed list.
local CORE = {
	"activity", "arrow-down", "arrow-up", "bell", "check", "chevron-down", "chevron-left", "chevron-right",
	"chevron-up", "chevrons-up-down", "circle", "circle-alert", "circle-check", "circle-dashed", "circle-help",
	"circle-x", "clipboard-paste", "clock", "command", "copy", "corner-down-left", "download", "ellipsis",
	"external-link", "eye", "eye-off", "file", "folder", "gamepad-2", "grip-vertical", "hand", "info",
	"keyboard", "link", "list-filter", "loader-circle", "lock", "maximize-2", "menu", "minimize-2", "minus",
	"monitor", "moon", "mouse-pointer-2", "palette", "panel-left", "pencil", "pin", "pin-off", "play", "plus",
	"rotate-ccw", "search", "search-x", "settings", "sliders-horizontal", "star", "sun",
	"trash-2", "trending-down", "trending-up", "triangle-alert", "upload", "user", "users", "x", "zap",
}

-- v1 names and common pre-rename Lucide names, mapped to the names in the current set.
local ALIASES = {
	["user-search"] = "user-round-search",
	["loader"] = "loader-circle",
	["alert-triangle"] = "triangle-alert",
	["alert-circle"] = "circle-alert",
	["help-circle"] = "circle-help",
	["check-circle"] = "circle-check",
	["check-circle-2"] = "circle-check",
	["x-circle"] = "circle-x",
	["more-horizontal"] = "ellipsis",
	["more-vertical"] = "ellipsis-vertical",
	["edit"] = "pencil",
	["edit-2"] = "pencil",
	["trash"] = "trash-2",
	["sliders"] = "sliders-horizontal",
	["gamepad"] = "gamepad-2",
	["filter"] = "list-filter",
}

local args = process.args
local source, origin
for index = 1, #args do
	if args[index] == "--source" then
		source = fs.readFile(args[index + 1])
		origin = "local file " .. args[index + 1]:match("[^/\\]+$")
	elseif args[index] == "--fetch" then
		local net = require("@lune/net")
		local sha = args[index + 1]
		assert(sha and #sha >= 7, "--fetch needs a pinned commit sha")
		local response = net.request("https://raw.githubusercontent.com/latte-soft/lucide-roblox/" .. sha .. "/lib/Icons.luau")
		assert(response.ok, "fetch failed: " .. tostring(response.statusCode))
		source = response.body
		origin = "latte-soft/lucide-roblox@" .. sha
	end
end
assert(source, "usage: lune run tools/gen_icons.luau --source <Icons.luau> | --fetch <commit-sha>")
local inputHash = serde.hash("sha256", source)

local body = source:match('%["48px"%]=(%b{})')
assert(body, "no 48px set in the input")
local entries, sheetSeen, sheets, xSeen, ySeen = {}, {}, {}, {}, {}
for name, id, w, h, x, y in body:gmatch('%[?"?([%w%-]+)"?%]?=%{(%d+),%{(%d+),(%d+)%},%{(%d+),(%d+)%}%}') do
	assert(w == "48" and h == "48", "cell is not 48x48 for " .. name)
	entries[#entries + 1] = { name = name, id = tonumber(id), x = tonumber(x), y = tonumber(y) }
	if not sheetSeen[id] then sheetSeen[id] = true sheets[#sheets + 1] = tonumber(id) end
	xSeen[tonumber(x)] = true
	ySeen[tonumber(y)] = true
end
assert(#entries > 1000, "suspiciously few icons: " .. #entries)
table.sort(sheets)
local function sortedKeys(set)
	local out = {}
	for key in pairs(set) do out[#out + 1] = key end
	table.sort(out)
	return out
end
local xs, ys = sortedKeys(xSeen), sortedKeys(ySeen)
assert(#sheets <= 36 and #xs <= 36 and #ys <= 36, "an axis needs more than one base-36 digit; bump the format")
local sheetIndex, xIndex, yIndex = {}, {}, {}
for index, value in ipairs(sheets) do sheetIndex[value] = index - 1 end
for index, value in ipairs(xs) do xIndex[value] = index - 1 end
for index, value in ipairs(ys) do yIndex[value] = index - 1 end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function digit(n) return B36:sub(n + 1, n + 1) end
table.sort(entries, function(a, b) return a.name < b.name end)
local byName, lines, previous = {}, {}, ""
for _, entry in ipairs(entries) do
	local code = digit(sheetIndex[entry.id]) .. digit(xIndex[entry.x]) .. digit(yIndex[entry.y])
	byName[entry.name] = code
	local shared = 0
	while shared < #previous and shared < #entry.name and shared < 35
		and previous:sub(shared + 1, shared + 1) == entry.name:sub(shared + 1, shared + 1) do
		shared += 1
	end
	lines[#lines + 1] = digit(shared) .. entry.name:sub(shared + 1) .. code
	previous = entry.name
end
local packed = table.concat(lines, "\n")
assert(not packed:find("]==]", 1, true), "packed data contains the long-string terminator")

local coreLines = {}
for _, name in ipairs(CORE) do
	local code = byName[name]
	assert(code, "core icon missing from the set: " .. name)
	coreLines[#coreLines + 1] = ('\t\t["%s"] = "%s",'):format(name, code)
end
local aliasNames = sortedKeys(ALIASES)
local aliasLines = {}
for _, from in ipairs(aliasNames) do
	local to = ALIASES[from]
	assert(byName[to], "alias target missing: " .. from .. " -> " .. to)
	aliasLines[#aliasLines + 1] = ('\t\t["%s"] = "%s",'):format(from, to)
end
local sheetText, xText, yText = {}, {}, {}
for _, value in ipairs(sheets) do sheetText[#sheetText + 1] = tostring(value) end
for _, value in ipairs(xs) do xText[#xText + 1] = tostring(value) end
for _, value in ipairs(ys) do yText[#yText + 1] = tostring(value) end

local out = table.concat({
	("-- GENERATED by tools/gen_icons.luau from %s (sha256 %s, %d icons). Do not edit."):format(origin, inputHash, #entries),
	"-- Lucide icons (ISC license, https://lucide.dev) via latte-soft/lucide-roblox spritesheets.",
	"return {",
	"\tformat = 1,",
	"\tcell = 48,",
	("\tcount = %d,"):format(#entries),
	"\tsheets = { " .. table.concat(sheetText, ", ") .. " },",
	"\txs = { " .. table.concat(xText, ", ") .. " },",
	"\tys = { " .. table.concat(yText, ", ") .. " },",
	"\tcore = {",
	table.concat(coreLines, "\n"),
	"\t},",
	"\taliases = {",
	table.concat(aliasLines, "\n"),
	"\t},",
	"\tpacked = [==[",
	packed .. "]==],",
	"}",
	"",
}, "\n")
fs.writeFile("src/icons/IconData.luau", out)

-- Self-test: decode what was written and compare every entry with the parsed input.
local luau = require("@lune/luau")
local data = luau.load(out)()
local decoded, last = {}, ""
for line in data.packed:gmatch("[^\n]+") do
	local name = last:sub(1, tonumber(line:sub(1, 1), 36)) .. line:sub(2, -4)
	decoded[name] = line:sub(-3)
	last = name
end
local mismatches = 0
for _, entry in ipairs(entries) do
	local code = decoded[entry.name]
	if not code
		or data.sheets[tonumber(code:sub(1, 1), 36) + 1] ~= entry.id
		or data.xs[tonumber(code:sub(2, 2), 36) + 1] ~= entry.x
		or data.ys[tonumber(code:sub(3, 3), 36) + 1] ~= entry.y then
		mismatches += 1
	end
end
assert(mismatches == 0, mismatches .. " icons failed the round trip")
print(("wrote src/icons/IconData.luau: %d icons, %d sheets, packed %d bytes, file %d bytes; self-test ok")
	:format(#entries, #sheets, #packed, #out))
