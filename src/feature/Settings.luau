--!nocheck
-- The end-user Settings tab (DESIGN_V2 9) and the profiles manager (8.5). Every row is a view
-- over the window's preferences, not a configuration flag (the v1 ArgonUI* flag names still
-- resolve through GetFlagValue/SetFlagValue). The account menu and the palette can always
-- open settings: without a host tab, a Settings tab is added on first use.

local Util = require("core/Util")
local Theme = require("theme/Theme")
local Fonts = require("theme/Fonts")
local Motion = require("core/Motion")
local Prefs = require("persist/Prefs")
local Store = require("persist/Store")
local Profiles = require("persist/Profiles")
local Meta = require("meta")
local Icons = require("icons/Icons")

local Settings = {}

local function themeOptions()
	return Theme.list()
end

function Settings.library(window, tab)
	if not tab or window._librarySettingsCreated then return tab end
	window._librarySettingsCreated = true
	window._settingsTab = tab
	local Argon = window.Argon
	local sections = {}

	sections.Appearance = tab:CreateSection({ Title = "Appearance", Icon = "palette" })
	local themeDropdown = tab:CreateDropdown({ Name = "Theme", Options = themeOptions(), CurrentOption = { Theme.name },
		Keywords = { "colour", "color", "dark", "light" },
		Callback = function(value)
			local name = type(value) == "table" and value[1] or value
			if name and name ~= Theme.name then window:SetTheme(name) end
		end })
	tab:CreateSegmented({ Name = "Material", Options = { "Solid", "Tinted", "Clear" }, CurrentOption = Theme.materialFor(),
		Description = Theme.name == "HighContrast" and "High contrast uses Solid" or nil,
		Callback = function(value) window:SetMaterial(value) end })
	tab:CreateStepper({ Name = "Interface scale", Range = { 90, 130 }, Increment = 5, Suffix = "%",
		CurrentValue = math.floor(window:GetScale() * 100 + 0.5),
		Callback = function(value) window:SetScale(value / 100) end })
	tab:CreateSegmented({ Name = "Density", Options = { "Auto", "Compact", "Touch" }, CurrentOption = Prefs.get("Density") or "Auto",
		Callback = function(value) window:SetDensity(string.lower(value)) end })
	tab:CreateSegmented({ Name = "State labels", Options = { "Auto", "Always", "Off" }, CurrentOption = Prefs.get("StateLabels") or "Auto",
		Description = "On/Off text next to switches",
		Callback = function(value)
			Prefs.set("StateLabels", value)
			for _, other in ipairs(window.Tabs) do other:_unmount() end
			window:_showActive(false)
		end })
	tab:CreateToggle({ Name = "Reduce motion", CurrentValue = Motion.reduced,
		Callback = function(value) window:SetReducedMotion(value) end })
	local fontDropdown = tab:CreateDropdown({ Name = "Typeface", Options = Fonts.list(), CurrentOption = { Fonts.current },
		Callback = function(value)
			local name = type(value) == "table" and value[1] or value
			if name then window:SetFont(name) end
		end })

	sections.Window = tab:CreateSection({ Title = "Window", Icon = "panel-left" })
	tab:CreateInput({ Name = "Menu name", PlaceholderText = window._defaultTitle, CurrentValue = window._title,
		Description = "Shown in the sidebar and on the loader. Clear it to restore the default.",
		Callback = function(value) window:SetTitle(value) end })
	tab:CreateInput({ Name = "Menu subtitle", PlaceholderText = window._defaultSubtitle, CurrentValue = window._subtitle,
		Callback = function(value) window:SetSubtitle(value) end })
	tab:CreateInput({ Name = "Custom logo", PlaceholderText = "rbxassetid://… or an asset id", CurrentValue = tostring(window._logo or ""),
		Callback = function(value) window:SetLogo(value ~= "" and value or nil) end })

	sections.Controls = tab:CreateSection({ Title = "Controls", Icon = "keyboard" })
	tab:CreateKeybind({ Name = "Menu key", CurrentKeybind = window._toggleKey and Util.keyName(window._toggleKey) or "None",
		DisplayInKeybindList = false, CallOnChange = true,
		Callback = function(key) window:SetToggleKey(key) end })
	tab:CreateSegmented({ Name = "Reopen button", Options = { "Auto", "Always", "Off" },
		CurrentOption = ({ auto = "Auto", always = "Always", off = "Off" })[tostring(window._openButton):lower()] or "Auto",
		Description = "The pill or orb that brings a hidden window back",
		Callback = function(value) window:SetOpenButton(string.lower(value)) end })
	tab:CreateToggle({ Name = "Mouse unlock", CurrentValue = window._mouseUnlock ~= false,
		Description = "Frees the cursor in first-person games while the window is open",
		Callback = function(value) window:SetMouseUnlock(value) end })

	sections.Notifications = tab:CreateSection({ Title = "Notifications", Icon = "bell" })
	tab:CreateToggle({ Name = "Show callback errors", CurrentValue = Prefs.get("ShowCallbackErrors") ~= false,
		Callback = function(value) Prefs.set("ShowCallbackErrors", value) end })
	tab:CreateButton({ Name = "Clear inbox", Icon = "trash-2", Callback = function()
		table.clear(window._toastHost.inbox)
		window:_toast("Inbox cleared", "success")
	end })

	sections.Overlays = tab:CreateSection({ Title = "Overlays", Icon = "activity" })
	local overlays = window._overlays
	tab:CreateToggle({ Name = "Keybind list", CurrentValue = overlays.enabled.Keybinds == true,
		Callback = function(value) window:SetKeybindListVisible(value) end })
	tab:CreateToggle({ Name = "Player list", CurrentValue = overlays.enabled.Players == true,
		Callback = function(value) window:SetPlayerListVisible(value) end })
	tab:CreateToggle({ Name = "Watermark", CurrentValue = overlays.enabled.Watermark == true,
		Callback = function(value) window:SetWatermarkVisible(value) end })
	tab:CreateToggle({ Name = "Keep overlays on screen", CurrentValue = overlays.pinned == true,
		Description = "Overlays stay visible after hiding the window",
		Callback = function(value) window:SetOverlaysAlwaysVisible(value) end })
	tab:CreateSlider({ Name = "Overlay opacity", Range = { 20, 88 }, Increment = 1, Suffix = "%",
		CurrentValue = math.floor((1 - overlays.transparency) * 100 + 0.5),
		Callback = function(value) window:SetOverlayTransparency(1 - value / 100) end })
	tab:CreateSlider({ Name = "Overlay scale", Range = { 75, 140 }, Increment = 5, Suffix = "%",
		CurrentValue = math.floor(overlays.scale * 100 + 0.5),
		Callback = function(value) window:SetOverlayScale(value / 100) end })
	tab:CreateKeybind({ Name = "Player list key", CurrentKeybind = Prefs.get("PlayerListKey") or "None", DisplayInKeybindList = false,
		OnPressed = function() window:TogglePlayerList() end,
		Callback = function(key) Prefs.set("PlayerListKey", key) end })
	tab:CreateKeybind({ Name = "Keybind list key", CurrentKeybind = Prefs.get("KeybindListKey") or "None", DisplayInKeybindList = false,
		OnPressed = function() window:ToggleKeybindList() end,
		Callback = function(key) Prefs.set("KeybindListKey", key) end })
	tab:CreateButton({ Name = "Reset overlay positions", Icon = "rotate-ccw", Callback = function() window:ResetOverlayPositions() end })

	sections.Profiles = tab:CreateSection({ Title = "Profiles", Icon = "folder" })
	Settings.configManager(window, tab, true)

	sections.About = tab:CreateSection({ Title = "About", Icon = "info" })
	tab:CreateLabel(("Argon UI %s · %d icons"):format(Meta.Version, Icons.count or 0))
	tab:CreateButton({ Name = "Copy diagnostics", Icon = "copy", Callback = function()
		local stats = Argon:GetPerfStats()
		local ok, text = pcall(function() return game:GetService("HttpService"):JSONEncode(stats) end)
		window:_copy(ok and text or tostring(stats))
	end })
	tab:CreateButton({ Name = "Unload", Variant = "DangerSoft", Icon = "x", Callback = function()
		window:Confirm({ Title = "Unload " .. window._title .. "?", Content = "The window closes and its keybinds stop.",
			ConfirmText = "Unload", OnConfirm = function() window:Destroy() end })
	end })

	window._settingsSections = sections
	-- keep the views in step with changes made elsewhere (topbar picker, API)
	window._scope:connect(Theme.changed, function()
		pcall(function() themeDropdown:Set({ Theme.name }, true) end)
	end)
	window._scope:connect(Theme.listChanged, function()
		pcall(function() themeDropdown:Refresh(themeOptions(), true) end)
	end)
	window._scope:connect(Fonts.changed, function()
		pcall(function() fontDropdown:Set({ Fonts.current }, true) end)
	end)
	return tab
end

-- ---------- profiles ----------
local function profileRows()
	local items = {}
	for _, profile in ipairs(Profiles.list()) do
		local meta = {}
		if profile.Count then meta[#meta + 1] = profile.Count .. " settings" end
		if profile.SavedAt then meta[#meta + 1] = "edited " .. Util.ago(os.time() - profile.SavedAt) end
		if profile.Active then meta[#meta + 1] = "active" end
		if profile.Autoload then meta[#meta + 1] = "loads on start" end
		items[#items + 1] = { Id = profile.Name, Title = profile.Name, Description = table.concat(meta, " · "), Icon = profile.Autoload and "star" or nil }
	end
	return items
end

function Settings.configManager(window, tab, inline)
	if not tab then return tab end
	local Argon = window.Argon
	if not inline then tab:CreateSection({ Title = "Profiles", Icon = "folder" }) end
	local stats = Store.stats()
	local status = tab:CreateLabel({ Text = stats.Enabled and ("Saved to " .. tostring(stats.Path)) or "Saving is off for this script",
		Style = stats.Enabled and "muted" or "warning" })
	local list
	local function refresh()
		if list then list:SetItems(profileRows()) end
		local now = Store.stats()
		if now.SaveState == "failed" then
			status:Set("Save failed: " .. tostring(now.LastError))
		elseif now.SavedAt then
			status:Set(("Saved · %s · %s"):format(Util.ago(os.time() - now.SavedAt), tostring(now.Path)))
		end
	end
	list = tab:CreateList({ Name = "Profiles", EmptyText = "No profiles yet", Items = profileRows(), Height = 200,
		Actions = nil,
		Callback = function(record) end })
	local function actionsFor(record)
		local name = record.Title
		return {
			{ Label = "Load", Callback = function()
				Argon:LoadConfiguration(name)
				refresh()
			end },
			{ Label = "Rename", Callback = function()
				window:Prompt({ Title = "Rename profile", Default = name, Validate = function(text)
					local clean = Profiles.sanitize(text)
					return clean ~= "" and clean ~= "Default", "Use letters, numbers, spaces, - or _"
				end, OnSubmit = function(text)
					local ok, err = Profiles.rename(name, text)
					if not ok then window:_toast(tostring(err), "error") end
					refresh()
				end })
			end },
			{ Label = "Delete", Style = "danger", Callback = function()
				window:Confirm({ Title = "Delete " .. name .. "?", ConfirmText = "Delete", OnConfirm = function()
					Profiles.delete(name)
					refresh()
				end })
			end },
		}
	end
	local setItems = list.SetItems
	function list:SetItems(items)
		for _, record in ipairs(items) do
			if type(record) == "table" then record.Actions = actionsFor(record) end
		end
		return setItems(self, items)
	end
	list:SetItems(profileRows())
	tab:CreateButton({ Name = "Save current as…", Icon = "download", Callback = function()
		window:Prompt({ Title = "Save profile", Placeholder = "Profile name", Validate = function(text)
			return Profiles.sanitize(text) ~= "", "Give the profile a name"
		end, OnSubmit = function(text)
			local ok, err = Profiles.save(text)
			window:_toast(ok and ("Saved " .. Profiles.sanitize(text)) or tostring(err), ok and "success" or "error")
			refresh()
		end })
	end })
	tab:CreateButton({ Name = "Import…", Icon = "upload", Callback = function()
		window:Prompt({ Title = "Import settings", Content = "Paste an ARGON2 code or a configuration file's text.", Placeholder = "ARGON2:…",
			OnSubmit = function(text)
				local ok, summary = Profiles.import(text, { apply = false })
				if not ok then
					window:_toast("That is not a settings code", "error")
					return
				end
				window:Confirm({ Title = "Apply these settings?", Variant = "Primary", ConfirmText = "Apply",
					Content = ("%d setting%s will change, %d unknown ignored."):format(summary.changed, summary.changed == 1 and "" or "s", summary.unknown),
					OnConfirm = function()
						Profiles.import(text, { apply = true })
						refresh()
					end })
			end })
	end })
	tab:CreateButton({ Name = "Copy current as code", Icon = "copy", Callback = function()
		window:_copy(Profiles.export() or "")
	end })
	tab:CreateButton({ Name = "Reset all…", Variant = "DangerSoft", Icon = "rotate-ccw", Callback = function()
		window:Confirm({ Title = "Reset every setting?", Content = "All controls go back to their defaults.", ConfirmText = "Reset",
			OnConfirm = function() window:ResetAll() end })
	end })
	window._scope:connect(Store.saved, function() refresh() end)
	return tab
end

-- Opens the settings: the host's tab when there is one, otherwise a built-in Settings tab.
function Settings.open(window, section)
	local tab = window._settingsTab
	if not tab then
		tab = window:CreateTab("Settings", "settings", { Group = nil })
		Settings.library(window, tab)
	end
	window:SelectTab(tab)
	window:SetVisibility(true)
	local target = section and window._settingsSections and window._settingsSections[section]
	if target then
		task.defer(function() window:_scrollToSection(target) end)
	end
end

return Settings
