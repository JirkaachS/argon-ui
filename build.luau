--!nocheck
-- Bundles src/ into the single distributed file argon-ui.luau.
--
--   lune run build.luau                 write argon-ui.luau
--   lune run build.luau -- --check      exit 1 when argon-ui.luau is not what src/ builds to
--   lune run build.luau -- --out <path> write the bundle somewhere else (tests, benches)
--   lune run build.luau -- --where <n>  print which module and line bundle line <n> is in
--
-- Each module becomes one function in a table, loaded lazily through a local require shim.
-- Comments and indentation are stripped but every newline is kept, so a line number in a
-- module is easy to map back with --where. The output is deterministic: sorted modules,
-- LF endings and no timestamps.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local SIZE_WARN, SIZE_FAIL = 640 * 1024, 768 * 1024
local REPO_URL = "https://github.com/JirkaachS/argon-ui"

local args = process.args
local function flag(name)
	for index, value in ipairs(args) do
		if value == name then return true, args[index + 1] end
	end
	return false, nil
end
local checkOnly = flag("--check")
local _, outPath = flag("--out")
local _, whereLine = flag("--where")
outPath = outPath or "argon-ui.luau"

-- ---------- collect ----------
local modules = {}
local function walk(dir, prefix)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path, prefix .. entry .. "/")
		elseif entry:match("%.luau$") then
			-- CRLF checkouts (core.autocrlf) must build the same bundle as LF ones
			local source = fs.readFile(path):gsub("\r\n", "\n")
			modules[#modules + 1] = { name = prefix .. entry:gsub("%.luau$", ""), path = path, source = source }
		end
	end
end
walk("src", "")
table.sort(modules, function(a, b) return a.name < b.name end)
local byName = {}
for _, module in ipairs(modules) do byName[module.name] = module end
assert(byName.init, "src/init.luau is missing")

-- ---------- lex: strip comments and indentation, find requires and identifiers ----------
local function longBracketLevel(source, index)
	local level = source:match("^%[(=*)%[", index)
	return level and #level or nil
end

local function lex(source, label)
	local out, requires, words, strings = {}, {}, {}, {}
	local index, length = 1, #source
	local atLineStart = true
	local lineNo = 1
	-- Whitespace inside a line is kept only where removing it would merge two tokens:
	-- between word characters, between operator characters ("- -" is not a comment), and
	-- between a digit and a dot ("1 .." is not a malformed number).
	local pending, last = false, "\n"
	local OPS = "[%-=<>~%.%[%]:%+%*/%%%^#]"
	local function needsSpace(a, b)
		if a == "\n" or a == "" then return false end
		if a:match("[%w_]") and b:match("[%w_]") then return true end
		if a:match(OPS) and b:match(OPS) then return true end
		if (a:match("%d") and b == ".") or (a == "." and b:match("%d")) then return true end
		return false
	end
	local function emit(text)
		if text:sub(1, 1) == "\n" then
			pending = false
		elseif pending then
			if needsSpace(last, text:sub(1, 1)) then out[#out + 1] = " " end
			pending = false
		end
		out[#out + 1] = text
		last = text:sub(-1)
	end
	while index <= length do
		local char = source:sub(index, index)
		if atLineStart and (char == " " or char == "\t") then
			index += 1
		elseif char == "\n" then
			emit("\n")
			lineNo += 1
			atLineStart = true
			index += 1
		elseif char == "\r" then
			index += 1
		elseif source:sub(index, index + 1) == "--" then
			local level = longBracketLevel(source, index + 2)
			local finish
			if level then
				local closer = "]" .. string.rep("=", level) .. "]"
				local stop = source:find(closer, index + 2, true)
				assert(stop, label .. ":" .. lineNo .. ": unterminated long comment")
				finish = stop + #closer - 1
			else
				finish = (source:find("\n", index, true) or length + 1) - 1
			end
			local body = source:sub(index, finish)
			local _, newlines = body:gsub("\n", "")
			if newlines > 0 then
				emit(string.rep("\n", newlines))
				lineNo += newlines
				atLineStart = true
			end
			index = finish + 1
		elseif char == "\"" or char == "'" then
			local stop = index + 1
			while true do
				local c = source:sub(stop, stop)
				assert(c ~= "" and c ~= "\n", label .. ":" .. lineNo .. ": unterminated string")
				if c == "\\" then stop += 2
				elseif c == char then break
				else stop += 1 end
			end
			local literal = source:sub(index, stop)
			strings[#strings + 1] = { text = literal:sub(2, -2), line = lineNo }
			emit(literal)
			atLineStart = false
			index = stop + 1
		elseif char == "`" then
			error(label .. ":" .. lineNo .. ": interpolated strings are not used in src/ (keep the lexer simple)")
		elseif char == "[" and longBracketLevel(source, index) then
			local level = longBracketLevel(source, index)
			local closer = "]" .. string.rep("=", level) .. "]"
			local stop = source:find(closer, index, true)
			assert(stop, label .. ":" .. lineNo .. ": unterminated long string")
			local literal = source:sub(index, stop + #closer - 1)
			local _, newlines = literal:gsub("\n", "")
			lineNo += newlines
			emit(literal)
			atLineStart = false
			index = stop + #closer
		elseif char:match("[%a_]") then
			local word = source:match("^[%w_]+", index)
			local before = source:sub(index - 1, index - 1)
			local called = source:match("^%s*%(", index + #word) ~= nil
			local constructs = word == "Instance" and source:match("^%s*%.%s*new", index + #word) ~= nil
			words[#words + 1] = { word = word, line = lineNo, member = before == "." or before == ":", called = called, constructs = constructs }
			if word == "require" and before ~= "." and before ~= ":" then
				local target, rest = source:match("^require%s*%(%s*\"([^\"]+)\"%s*%)()", index)
				assert(target, label .. ":" .. lineNo .. ": require must take a string literal")
				requires[#requires + 1] = { name = target, line = lineNo }
			end
			emit(word)
			atLineStart = false
			index += #word
		elseif char == " " or char == "\t" then
			pending = true
			index += 1
		else
			emit(char)
			atLineStart = false
			index += 1
		end
	end
	return table.concat(out), requires, words, strings
end

-- ---------- lint ----------
local problems = {}
local function problem(module, line, message)
	problems[#problems + 1] = ("src/%s.luau:%d: %s"):format(module.name, line, message)
end
-- Calls that would yield or touch the network on the caller's thread. Only the listed modules
-- may use them, and only where ARCHITECTURE_V2 section 15.4 and RECONCILIATION R11 allow.
local YIELDING = {
	WaitForChild = true, HttpGet = true, HttpGetAsync = true, PreloadAsync = true,
	GetUserThumbnailAsync = true, GetTextBoundsAsync = true,
}
local ALLOW = {
	["persist/Store"] = { wait = true },
	["feature/KeyGate"] = { wait = true, HttpGet = true, HttpGetAsync = true, Wait = true },
	["theme/Fonts"] = { GetTextBoundsAsync = true },
}
for _, module in ipairs(modules) do
	local stripped, requires, words, strings = lex(module.source, "src/" .. module.name .. ".luau")
	module.stripped = stripped
	module.requires = requires
	local allow = ALLOW[module.name] or {}
	for _, item in ipairs(words) do
		local w = item.word
		if not item.member and (w == "loadstring" or w == "getfenv" or w == "setfenv") then
			problem(module, item.line, w .. " is not allowed")
		end
		if not item.member and item.called and (w == "wait" or w == "delay" or w == "spawn") then
			-- a bare legacy global call; task.wait etc. are members and pass
			problem(module, item.line, "legacy global " .. w .. " (use task." .. w .. ")")
		end
		if item.member and item.called and w == "wait" and not allow.wait then
			problem(module, item.line, "task.wait on a non-allowlisted module")
		end
		if item.member and item.called and w == "Wait" and not allow.Wait then
			problem(module, item.line, ":Wait() on a non-allowlisted module")
		end
		if item.member and item.called and YIELDING[w] and not allow[w] then
			problem(module, item.line, w .. " on a non-allowlisted module")
		end
		if item.constructs and module.name ~= "core/Factory" then
			problem(module, item.line, "instances are created through core/Factory only")
		end
	end
	for _, item in ipairs(strings) do
		if item.text == "CanvasGroup" then problem(module, item.line, "CanvasGroup is not used in v2") end
	end
	for _, req in ipairs(module.requires) do
		if not byName[req.name] then problem(module, req.line, "requires a missing module: " .. req.name) end
	end
	local _, topVarargs = module.stripped:gsub("\n%.%.%.", "")
	if topVarargs > 0 then problem(module, 1, "top-level varargs") end
end

-- cycles
local state = {}
local function visit(module, path)
	if state[module.name] == "done" then return end
	if state[module.name] == "active" then
		problems[#problems + 1] = "require cycle: " .. table.concat(path, " -> ") .. " -> " .. module.name
		return
	end
	state[module.name] = "active"
	path[#path + 1] = module.name
	for _, req in ipairs(module.requires) do
		if byName[req.name] then visit(byName[req.name], path) end
	end
	path[#path] = nil
	state[module.name] = "done"
end
for _, module in ipairs(modules) do visit(module, {}) end

if #problems > 0 then
	print("build failed:")
	for _, message in ipairs(problems) do print("  " .. message) end
	process.exit(1)
end

-- ---------- emit ----------
local meta = byName.meta and byName.meta.source or ""
local version = meta:match("Version%s*=%s*\"([^\"]+)\"") or "0.0.0"
local hashInput = {}
for _, module in ipairs(modules) do hashInput[#hashInput + 1] = module.name .. "\0" .. module.source end
local sourceHash = serde.hash("sha256", table.concat(hashInput, "\0"))

local header = {
	"--!nocheck",
	"--!optimize 2",
	("-- Argon UI %s | generated by build.luau from src/ (sha256 %s) | do not edit"):format(version, sourceHash),
	("-- %s | MIT"):format(REPO_URL),
	"", -- @map line, filled below
	"local __M, __C, __L = {}, {}, {}",
	"local function __require(name)",
	"\tlocal cached = __C[name]",
	"\tif cached ~= nil then return cached end",
	"\tlocal loader = __M[name]",
	"\tif loader == nil then error(\"[Argon UI] internal module missing: \" .. tostring(name), 2) end",
	"\tif __L[name] then error(\"[Argon UI] circular require: \" .. name, 2) end",
	"\t__L[name] = true",
	"\tlocal value = loader(__require)",
	"\t__L[name] = nil",
	"\tif value == nil then value = true end",
	"\t__C[name] = value",
	"\treturn value",
	"end",
}
local body = {}
local line = #header + 1
local map = {}
for _, module in ipairs(modules) do
	body[#body + 1] = ("__M[%q] = function(require)"):format(module.name)
	line += 1
	module.firstLine = line
	map[#map + 1] = module.name .. "=" .. line
	local text = module.stripped:gsub("\n+$", "")
	body[#body + 1] = text
	local _, newlines = text:gsub("\n", "")
	line += newlines + 1
	body[#body + 1] = "end"
	line += 1
end
body[#body + 1] = "return __require(\"init\")"
header[5] = "-- @map " .. table.concat(map, " ")
local bundle = table.concat(header, "\n") .. "\n" .. table.concat(body, "\n") .. "\n"

if whereLine then
	local target = tonumber(whereLine)
	local best
	for _, module in ipairs(modules) do
		if module.firstLine <= target then best = module end
	end
	if best then
		print(("bundle line %d = src/%s.luau:%d"):format(target, best.name, target - best.firstLine + 1))
	else
		print("bundle line " .. tostring(target) .. " is in the header")
	end
	process.exit(0)
end

-- ---------- verify ----------
local okCompile, compileError = pcall(luau.compile, bundle)
if not okCompile then
	print("build failed: the bundle does not compile: " .. tostring(compileError))
	process.exit(1)
end
local times = {}
for run = 1, 5 do
	local start = os.clock()
	luau.compile(bundle)
	times[run] = (os.clock() - start) * 1000
end
table.sort(times)
local size = #bundle
local iconBytes = byName["icons/IconData"] and #byName["icons/IconData"].stripped or 0

if checkOnly then
	local current = fs.isFile(outPath) and fs.readFile(outPath):gsub("\r\n", "\n") or ""
	if current ~= bundle then
		print(("check failed: %s is not what src/ builds to (run lune run build.luau)"):format(outPath))
		process.exit(1)
	end
	print(("check ok: %s matches src/ (%d modules, %d bytes)"):format(outPath, #modules, size))
	process.exit(0)
end

fs.writeFile(outPath, bundle)
print(("Argon UI %s: %d modules -> %s, %d bytes (%.1f KB; icon data %.1f KB), compile %.2f ms (median of 5)")
	:format(version, #modules, outPath, size, size / 1024, iconBytes / 1024, times[3]))
if size > SIZE_FAIL then
	print(("build failed: bundle is over the %d KB gate"):format(SIZE_FAIL // 1024))
	process.exit(1)
elseif size > SIZE_WARN then
	print(("warning: bundle is over %d KB"):format(SIZE_WARN // 1024))
end
