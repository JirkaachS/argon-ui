--!nocheck
-- Per-window registry of elements and commands: the search index for the command palette
-- (it works on state, so controls in tabs that were never opened are found), and the
-- dependency index for VisibleWhen / EnabledWhen.

local Registry = {}
Registry.__index = Registry

function Registry.new(window)
	return setmetatable({ window = window, elements = {}, order = 0, deps = {}, commands = {}, recent = {} }, Registry)
end

function Registry:add(element)
	self.order += 1
	element._regOrder = self.order
	self.elements[element] = true
end

function Registry:remove(element)
	self.elements[element] = nil
	for _, list in pairs(self.deps) do
		for index = #list, 1, -1 do
			if list[index] == element then table.remove(list, index) end
		end
	end
end

function Registry:all()
	local out = {}
	for element in pairs(self.elements) do out[#out + 1] = element end
	table.sort(out, function(a, b) return a._regOrder < b._regOrder end)
	return out
end

-- ---------- VisibleWhen / EnabledWhen ----------
local function collectFlags(condition, out)
	if type(condition) ~= "table" then return end
	if condition.Flag then out[#out + 1] = condition.Flag end
	for _, key in ipairs({ "All", "Any" }) do
		if type(condition[key]) == "table" then
			for _, inner in ipairs(condition[key]) do collectFlags(inner, out) end
		end
	end
	if type(condition.Flags) == "table" then
		for _, flag in ipairs(condition.Flags) do out[#out + 1] = flag end
	end
end

function Registry:watch(element, condition)
	local flags = {}
	collectFlags(condition, flags)
	for _, flag in ipairs(flags) do
		local list = self.deps[flag]
		if not list then
			list = {}
			self.deps[flag] = list
		end
		list[#list + 1] = element
	end
end

function Registry:dependents(flag)
	return self.deps[flag] or {}
end

-- Evaluates a condition table or function against the current flag values.
function Registry.evaluate(condition, getValue)
	if type(condition) == "function" then
		local ok, result = pcall(condition, setmetatable({}, { __index = function(_, flag) return getValue(flag) end }))
		return not ok or result ~= false
	end
	if type(condition) ~= "table" then return true end
	if condition.All then
		for _, inner in ipairs(condition.All) do
			if not Registry.evaluate(inner, getValue) then return false end
		end
		return true
	end
	if condition.Any then
		for _, inner in ipairs(condition.Any) do
			if Registry.evaluate(inner, getValue) then return true end
		end
		return false
	end
	if type(condition.Condition) == "function" then return Registry.evaluate(condition.Condition, getValue) end
	local value = getValue(condition.Flag)
	if type(value) == "table" and #value == 1 then value = value[1] end
	if condition.Equals ~= nil then return value == condition.Equals end
	if condition.NotEquals ~= nil then return value ~= condition.NotEquals end
	if type(condition.In) == "table" then
		for _, candidate in ipairs(condition.In) do
			if candidate == value then return true end
		end
		return false
	end
	return value ~= nil and value ~= false
end

-- ---------- search ----------
local function lower(text) return string.lower(tostring(text or "")) end

local function words(text)
	local out = {}
	for word in text:gmatch("[%w]+") do out[#out + 1] = word end
	return out
end

-- Score of one query token against one field (DESIGN_V2 7.5): word prefix 100, substring 60,
-- short subsequence up to 30.
local function scoreField(token, field)
	if field == "" then return 0, nil end
	local start = 1
	for word in field:gmatch("[%w]+") do
		local at = field:find(word, start, true)
		if word:sub(1, #token) == token then return 100, at end
		start = (at or start) + #word
	end
	local at = field:find(token, 1, true)
	if at then return 60, at end
	if #token < 3 then return 0, nil end
	local position, gaps, last, first = 1, 0, nil, nil
	for index = 1, #token do
		local found = field:find(token:sub(index, index), position, true)
		if not found then return 0, nil end
		if last and found > last + 1 then gaps += 1 end
		if gaps > 2 then return 0, nil end
		first = first or found
		last = found
		position = found + 1
	end
	local span = field:sub(first, last)
	local _, spaces = span:gsub(" ", "")
	if spaces > 1 then return 0, nil end
	return 30 - gaps * 5, first
end

function Registry.index(element)
	local cached = element._searchIndex
	if cached then return cached end
	local cfg = element._cfg or {}
	local keywords = {}
	if type(cfg.Keywords) == "table" then
		for _, keyword in ipairs(cfg.Keywords) do keywords[#keywords + 1] = lower(keyword) end
	end
	local options = {}
	if element._searchOptions then
		for _, option in ipairs(element:_searchOptions()) do options[#options + 1] = lower(option) end
	end
	cached = {
		name = lower(element.Name),
		keywords = table.concat(keywords, " "),
		options = table.concat(options, " "),
		extra = lower((element._descText or "") .. " " .. (element._tooltipText or "")),
		section = lower(element.Section and element.Section.Name or ""),
		tab = lower(element._tab and element._tab.Name or ""),
	}
	element._searchIndex = cached
	return cached
end

local WEIGHTS = { { "name", 1 }, { "keywords", 0.8 }, { "options", 0.7 }, { "extra", 0.5 }, { "section", 0.5 }, { "tab", 0.4 } }

function Registry:score(element, tokens)
	local index = Registry.index(element)
	local total, firstHit = 0, nil
	for _, token in ipairs(tokens) do
		local best = 0
		for _, entry in ipairs(WEIGHTS) do
			local value, at = scoreField(token, index[entry[1]])
			value *= entry[2]
			if value > best then
				best = value
				if entry[1] == "name" then firstHit = at end
			end
		end
		if best <= 0 then return 0 end
		total += best
	end
	total /= #tokens
	if self.recent[element] then total += 15 end
	return total, firstHit
end

-- Ranked matches for the palette: { {el, score, at} }.
function Registry:search(query, limit, filter)
	local tokens = words(lower(query))
	local results = {}
	if #tokens == 0 then return results end
	local best = 0
	for element in pairs(self.elements) do
		if not element._destroyed and (not filter or filter(element)) then
			local value, at = self:score(element, tokens)
			if value > 0 then
				results[#results + 1] = { el = element, score = value, at = at }
				if value > best then best = value end
			end
		end
	end
	if best >= 60 then
		for index = #results, 1, -1 do
			if results[index].score < 25 then table.remove(results, index) end
		end
	end
	table.sort(results, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.el._regOrder < b.el._regOrder
	end)
	if limit and #results > limit then
		for index = #results, limit + 1, -1 do results[index] = nil end
	end
	return results
end

function Registry:touch(element)
	self.recent[element] = os.clock()
end

-- ---------- commands ----------
function Registry:addCommand(command)
	self.commands[#self.commands + 1] = command
	return {
		Remove = function()
			for index = #self.commands, 1, -1 do
				if self.commands[index] == command then table.remove(self.commands, index) end
			end
		end,
	}
end

function Registry:searchCommands(query)
	local tokens = words(lower(query))
	local out = {}
	for _, command in ipairs(self.commands) do
		local text = lower(command.Name .. " " .. (command.Description or "") .. " " .. table.concat(command.Keywords or {}, " "))
		local total = 0
		for _, token in ipairs(tokens) do
			local value = scoreField(token, text)
			if value <= 0 then
				total = 0
				break
			end
			total += value
		end
		if #tokens == 0 then total = 1 end
		if total > 0 then out[#out + 1] = { command = command, score = total } end
	end
	table.sort(out, function(a, b) return a.score > b.score end)
	return out
end

return Registry
