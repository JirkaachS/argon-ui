--!nocheck
-- Font sets and roles (DESIGN_V2 section 2.9). Text is registered with a role, not a face.
-- The default set needs two CDN faces (Roboto 500, Montserrat 600); until they resolve their
-- roles render with engine-local stand-ins, then one repaint swaps them in.

local Env = require("core/Env")
local Factory = require("core/Factory")
local Signal = require("core/Signal")
local Token = require("core/Token")

local Fonts = {}
Fonts.current = "Roboto"
Fonts.version = 0
Fonts.changed = Signal.new("Fonts.changed")

local FAMILY = "rbxasset://fonts/families/%s.json"
local SETS = {
	Roboto = { body = "Roboto", display = "Montserrat", mono = "RobotoMono", label = "Roboto + Montserrat" },
	BuilderSans = { body = "BuilderSans", display = "BuilderSans", mono = "BuilderMono", label = "BuilderSans" },
	Ubuntu = { body = "Ubuntu", display = "Ubuntu", mono = "RobotoMono", label = "Ubuntu" },
	Condensed = { body = "RobotoCondensed", display = "Oswald", mono = "RobotoMono", label = "RobotoCondensed + Oswald" },
	Technical = { body = "Sarpanch", display = "Sarpanch", mono = "RobotoMono", label = "Sarpanch" },
	Gotham = { body = "GothamSSm", display = "GothamSSm", mono = "RobotoMono", label = "GothamSSm (legacy)" },
}
local ORDER = { "Roboto", "BuilderSans", "Ubuntu", "Condensed", "Technical", "Gotham" }

-- role = { family slot, weight }
local ROLES = {
	Page = { "display", "SemiBold" }, Dialog = { "display", "SemiBold" }, Section = { "display", "SemiBold" },
	Brand = { "display", "SemiBold" }, LoaderTitle = { "display", "Bold" },
	Label = { "body", "Medium" }, Button = { "body", "Medium" }, NavSelected = { "body", "Medium" },
	Nav = { "body", "Regular" }, Body = { "body", "Regular" }, Caption = { "body", "Regular" },
	Status = { "body", "Regular" }, Strong = { "body", "Bold" },
	Value = { "mono", "Regular" }, Stat = { "mono", "Regular" }, Key = { "mono", "Regular" },
}

-- Faces fetched from the CDN in the default set, and their local stand-ins.
local CDN = { ["Roboto/Medium"] = "Regular", ["Montserrat/SemiBold"] = "Bold" }
local resolved = {}

local cache = {}
local function makeFace(family, weight)
	local key = family .. "/" .. weight
	local cached = cache[key]
	if cached then return cached end
	local ok, face = pcall(function()
		return Font.new(FAMILY:format(family), Env.enum("FontWeight", weight, "Regular"), Env.enum("FontStyle", "Normal"))
	end)
	if not ok then
		ok, face = pcall(function() return Font.new(FAMILY:format("GothamSSm")) end)
	end
	cache[key] = ok and face or nil
	return cache[key]
end

function Fonts.face(role)
	local spec = ROLES[role] or ROLES.Body
	local set = SETS[Fonts.current] or SETS.Roboto
	local family = set[spec[1]]
	local weight = spec[2]
	local key = family .. "/" .. weight
	if CDN[key] and not resolved[key] then weight = CDN[key] end
	return makeFace(family, weight)
end

function Fonts.set(name)
	name = tostring(name)
	if not SETS[name] then return false end
	if Fonts.current == name then return true end
	Fonts.current = name
	Fonts.version += 1
	Fonts.changed:Fire(name)
	return true
end

function Fonts.list()
	return table.clone(ORDER)
end

function Fonts.label(name)
	local set = SETS[name or Fonts.current]
	return set and set.label or nil
end

-- Starts loading the CDN faces off the caller's thread. Calls onResolved once per face.
local started = false
function Fonts.preload(onResolved)
	if started then return end
	started = true
	local text = Env.services.TextService
	for key in pairs(CDN) do
		task.spawn(function()
			local family, weight = key:match("^(.-)/(.+)$")
			local face = makeFace(family, weight)
			pcall(function()
				local query = Factory.object("GetTextBoundsParams")
				query.Text = "Ag"
				query.Font = face
				query.Size = 14
				query.Width = 100
				text:GetTextBoundsAsync(query)
			end)
			resolved[key] = true
			Fonts.version += 1
			if onResolved then pcall(onResolved, key) end
			Fonts.changed:Fire(Fonts.current)
		end)
	end
end

function Fonts.resolved()
	for key in pairs(CDN) do
		if not resolved[key] then return false end
	end
	return true
end

Token.setResolvers({
	font = function(role) return Fonts.face(role) end,
})

return Fonts
