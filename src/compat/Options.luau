--!nocheck
-- CreateWindow option normalisation: Rayfield names and v1 aliases (ARCHITECTURE_V2 14.3).

local Options = {}

function Options.normalize(options)
	local out = {}
	if type(options) == "table" then
		for key, value in pairs(options) do out[key] = value end
	end
	-- Rayfield window icon -> logo (a number is an asset id)
	if out.Logo == nil and out.Icon ~= nil then out.Logo = out.Icon end
	if type(out.Logo) == "number" then out.Logo = "rbxassetid://" .. tostring(out.Logo) end
	-- Rayfield loading title/subtitle -> LoadingScreen
	if out.LoadingScreen == nil and (out.LoadingTitle or out.LoadingSubtitle) then
		out.LoadingScreen = { Title = out.LoadingTitle, Subtitle = out.LoadingSubtitle }
	end
	-- v2: overlays are off unless the host enables them
	if out.PlayerList == nil then out.PlayerList = false end
	if out.KeybindList == nil then out.KeybindList = false end
	if out.ConfigurationSaving == nil then out.ConfigurationSaving = { Enabled = false } end
	return out
end

return Options
