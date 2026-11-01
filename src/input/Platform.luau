--!nocheck
-- Input kind and density (DESIGN_V2 section 2.8).

local Env = require("core/Env")
local Signal = require("core/Signal")

local Platform = {}
Platform.changed = Signal.new("Platform.changed")
Platform.override = nil -- "Auto" | "Compact" | "Touch" (Prefs.Density)

local watching = nil

function Platform.preferred()
	local uis = Env.services.UserInputService
	if not uis then return "mouse" end
	local ok, preferred = pcall(function() return uis.PreferredInput end)
	if ok and preferred ~= nil then
		local name = typeof(preferred) == "EnumItem" and preferred.Name or tostring(preferred)
		if name:find("Touch") then return "touch" end
		if name:find("Gamepad") then return "gamepad" end
		return "mouse"
	end
	local touch = uis.TouchEnabled == true
	local keyboard = uis.KeyboardEnabled == true
	if touch and not keyboard then return "touch" end
	return "mouse"
end

-- "Compact" | "Default" | "Touch" | "Gamepad"
function Platform.density()
	local override = Platform.override
	if override == "Compact" then return "Compact" end
	if override == "Touch" then return "Touch" end
	local preferred = Platform.preferred()
	if preferred == "touch" then return "Touch" end
	if preferred == "gamepad" then return "Gamepad" end
	return "Default"
end

function Platform.isTouch()
	return Platform.preferred() == "touch"
end

function Platform.isPhone(gui)
	if Platform.preferred() ~= "touch" then return false end
	return math.min(gui.X, gui.Y) < 500 or gui.X < 600
end

function Platform.watch()
	if watching then return end
	local uis = Env.services.UserInputService
	if not uis then return end
	pcall(function()
		watching = uis:GetPropertyChangedSignal("PreferredInput"):Connect(function()
			Platform.changed:Fire(Platform.preferred())
		end)
	end)
end

function Platform.unwatch()
	if watching then
		watching:Disconnect()
		watching = nil
	end
end

return Platform
