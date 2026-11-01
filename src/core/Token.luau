--!nocheck
-- Tokens are sentinels, not values. A property written with a token is resolved now and
-- recorded in the owning scope's paint list, so a theme, font or density change re-applies
-- it without ever guessing which palette entry a raw Color3 came from.
--
--   Token.T.Surface   colour role          Token.F.Label   font role
--   Token.TS.Label    text size role       Token.M.Frame   material transparency

local Token = {}

local sentinels = {}

local function family(kind)
	return setmetatable({}, {
		__index = function(set, name)
			local sentinel = table.freeze({ kind = kind, name = name })
			sentinels[sentinel] = true
			rawset(set, name, sentinel)
			return sentinel
		end,
	})
end

Token.T = family("color")
Token.F = family("font")
Token.TS = family("size")
Token.M = family("material")

-- A gradient colour sequence over colour tokens: Token.seq("AccentHi", "Accent") or three stops
-- (0, 0.55, 1) for the slider fill.
local seqCache = {}
function Token.seq(...)
	local name = table.concat({ ... }, "|")
	local cached = seqCache[name]
	if cached then return cached end
	local sentinel = table.freeze({ kind = "seq", name = name })
	sentinels[sentinel] = true
	seqCache[name] = sentinel
	return sentinel
end

local resolvers = {}

function Token.setResolvers(map)
	for kind, fn in pairs(map) do resolvers[kind] = fn end
end

function Token.isToken(value)
	return sentinels[value] == true
end

function Token.resolve(value)
	if sentinels[value] then
		return resolvers[value.kind](value.name)
	end
	return value
end

return Token
