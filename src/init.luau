--!nocheck
-- The Argon facade: the table `loadstring(game:HttpGet(url))()` returns. Every v1 member is
-- kept (ARCHITECTURE_V2 14.1); v2 adds profiles, CreateTheme, SetAccent, Toast, GetPerfStats.
-- Loading this file creates no instances, does no IO and starts no timers.

local Meta = require("meta")
local Env = require("core/Env")
local Util = require("core/Util")
local Scope = require("core/Scope")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Scheduler = require("core/Scheduler")
local Theme = require("theme/Theme")
local Fonts = require("theme/Fonts")
local Icons = require("icons/Icons")
local Store = require("persist/Store")
local Prefs = require("persist/Prefs")
local Profiles = require("persist/Profiles")
local Options = require("compat/Options")
local Router = require("input/Router")
local Drag = require("input/Drag")

Scope.bind(require("core/Token"), Motion)

local Argon = {
	Version = Meta.Version,
	Flags = Store.flags,
	DefaultFolder = "ArgonUI",
	AssetFolder = "ArgonUI",
	Themes = Theme.themes,
	Palette = Theme.palette,
	Debug = false,
	_windows = {},
	_pendingFlags = Store.pending,
	_uiPreferences = {},
	-- v1 registries that no longer exist; kept as empty tables for scripts that read them
	_themeBindings = {},
	_connections = {},
	_themeRenderers = {},
}

local LIVE = {
	CurrentTheme = function() return Theme.name end,
	CurrentFont = function() return Fonts.current end,
	_lastConfigStats = function() return Store.info.lastStats end,
	_persistenceReady = function() return Store.ready end,
	_loadingConfig = function() return Store.loading end,
	_destroyed = function() return Store.destroyed end,
}
setmetatable(Argon, {
	__index = function(_, key)
		local getter = LIVE[key]
		if getter then return getter() end
		return nil
	end,
})

local Window -- shell/Window, loaded by the first CreateWindow
local Toast

local function lastWindow()
	local list = Argon._windows
	return list[#list]
end

-- Store hooks: the configuration file mirrors the last window's preferences.
Store.windows = function() return Argon._windows end
Store.exportPrefs = function()
	local window = lastWindow()
	if window and window._exportUIPreferences then return window:_exportUIPreferences() end
	return nil
end
Store.applyPrefs = function(prefs)
	Argon._uiPreferences = prefs
	for _, window in ipairs(Argon._windows) do
		if window._applyUIPreferences then window:_applyUIPreferences(prefs) end
	end
end
local VIRTUAL_SETTERS = {
	Title = "SetTitle", Subtitle = "SetSubtitle", Theme = "SetTheme", Font = "SetFont", Logo = "SetLogo",
	PlayerListEnabled = "SetPlayerListVisible", KeybindListEnabled = "SetKeybindListVisible",
	OverlaysAlwaysVisible = "SetOverlaysAlwaysVisible", SmoothTransitions = "SetSmoothTransitions",
}
Store.prefsGet = function(key)
	local window = lastWindow()
	if window then
		local prefs = window:_exportUIPreferences()
		if prefs[key] ~= nil then return prefs[key] end
	end
	return Prefs.get(key)
end
Store.prefsSet = function(key, value)
	local window = lastWindow()
	local setter = VIRTUAL_SETTERS[key]
	if window and setter then
		if type(value) == "table" and #value == 1 then value = value[1] end
		window[setter](window, value)
	elseif key == "OverlayTransparency" and window then
		window:SetOverlayTransparency(1 - (tonumber(value) or 62) / 100)
	elseif key == "OverlayScale" and window then
		window:SetOverlayScale((tonumber(value) or 100) / 100)
	else
		Prefs.set(key, value)
	end
end

-- ---------- windows ----------
function Argon:CreateWindow(options)
	Window = Window or require("shell/Window")
	Store.destroyed = false
	local window = Window.create(self, Options.normalize(options))
	if Toast then Toast.adopt(window) end
	return window
end

function Argon:SetVisibility(visible)
	local window = lastWindow()
	if window then window:SetVisibility(visible) end
	return self
end

function Argon:IsVisible()
	local window = lastWindow()
	return window ~= nil and window:IsVisible()
end

-- ---------- notifications ----------
function Argon:Notify(options)
	Toast = Toast or require("feature/Toast")
	return Toast.notify(lastWindow(), options)
end

function Argon:Toast(text, kind, action)
	Toast = Toast or require("feature/Toast")
	return Toast.toast(lastWindow(), text, kind, action)
end

-- ---------- configuration ----------
local function withRestore(fn)
	local loader
	for _, window in ipairs(Argon._windows) do
		if window._loading then loader = window end
	end
	if loader then loader._restoring = true end
	local results = table.pack(pcall(fn))
	if loader then loader._restoring = false end
	if not results[1] then return false, tostring(results[2]) end
	return table.unpack(results, 2, results.n)
end

function Argon:LoadConfiguration(name)
	return withRestore(function()
		if name ~= nil then return Profiles.load(name) end
		local autoload = Profiles.getAutoload()
		if autoload and autoload ~= "Default" then return Profiles.load(autoload) end
		return Store.load(nil)
	end)
end

function Argon:SaveConfiguration(name)
	if name ~= nil then return Profiles.save(name) end
	return Store.save(Store.profile)
end

function Argon:SetPersistenceReady(value, saveNow) return Store.setReady(value, saveNow) end
function Argon:GetFlagValue(flag) return Store.get(flag) end
function Argon:SetFlagValue(flag, value) return Store.set(flag, value) end
function Argon:GetFlags() return Store.snapshot() end
function Argon:OnFlagChanged(fn) return Store.onFlagChanged(fn) end
function Argon:GetConfigurationStats() return Store.stats() end

function Argon:DeleteConfiguration(name)
	if name ~= nil then return Profiles.delete(name) end
	return Store.delete(Store.profile)
end

function Argon:ResetConfiguration() return Store.reset() end
function Argon:ListConfigurations() return Profiles.list() end
function Argon:RenameConfiguration(old, new) return Profiles.rename(old, new) end
function Argon:SetAutoloadConfiguration(name) Profiles.setAutoload(name) return self end
function Argon:GetAutoloadConfiguration() return Profiles.getAutoload() end
function Argon:ExportConfiguration(name) return Profiles.export(name) end
function Argon:ImportConfiguration(text, opts) return Profiles.import(text, opts or { apply = true }) end

-- ---------- themes and fonts ----------
function Argon:AddTheme(name, palette) return Theme.add(name, palette) end
function Argon:GetThemes() return Theme.list() end
function Argon:SetTheme(value) return Theme.set(value) end
function Argon:CreateTheme(spec) return Theme.create(spec) end
function Argon:SetAccent(color)
	Theme.setAccent(color)
	Prefs.set("Accent", typeof(color) == "Color3" and require("theme/Color").toHex(color) or nil)
	return self
end

function Argon:GetColor(key, fallback)
	return Theme.get(tostring(key)) or fallback or Theme.palette.Text
end

function Argon:GetPalette()
	return table.clone(Theme.palette)
end

function Argon:OnThemeChanged(fn)
	if type(fn) ~= "function" then return function() end end
	local connection = Theme.changed:Connect(function(palette, name) fn(palette, name) end)
	return function() connection:Disconnect() end
end

function Argon:_fireThemeListeners()
	Theme.changed:Fire(Theme.palette, Theme.name)
end

function Argon:SetFont(name)
	Fonts.set(name)
	return self
end
function Argon:GetFonts() return Fonts.list() end
function Argon:GetFontLabel(name) return Fonts.label(name) end

function Argon:SetReducedMotion(on)
	Motion.setReduced(on == true)
	return self
end

-- ---------- icons ----------
function Argon:GetIcon(name) return Icons.get(name) end
function Argon:HasIcon(name) return Icons.has(name) end

-- Nothing is registered globally any more, so there is nothing to prune.
function Argon:PruneRegistries()
	local stats = { bindings = 0, renderers = 0, fonts = 0, connections = 0 }
	self._lastPruneStats = stats
	return stats
end

-- ---------- diagnostics ----------
function Argon:GetPerfStats()
	local mounted, pending, elements, popovers = 0, 0, 0, 0
	for _, window in ipairs(self._windows) do
		for _, tab in ipairs(window.Tabs) do
			for _, element in ipairs(tab._elements) do
				elements += 1
				if rawget(element, "_mounted") then mounted += 1 else pending += 1 end
			end
		end
		if window._popover then popovers += window._popover:openCount() end
	end
	local router = Router.stats()
	return {
		liveScopes = Scope.live,
		instancesCreated = Factory.created,
		mountedElements = mounted,
		pendingElements = pending,
		elements = elements,
		globalHandlers = { InputBegan = router.handlers, InputChanged = Drag.active(), InputEnded = router.holdActive and 1 or 0 },
		springsAndLoops = Motion.active(),
		dragSessions = Drag.active(),
		popoversOpen = popovers,
		scheduler = Scheduler.stats(),
		iconsDecoded = Icons.decoded(),
		bundleVersion = Meta.Version,
	}
end

-- ---------- teardown ----------
function Argon:Destroy()
	if Store.destroyed then return end
	pcall(function() Store.save(Store.profile) end)
	Store.destroyed = true
	for _, window in ipairs(table.clone(self._windows)) do
		pcall(window.Destroy, window)
	end
	table.clear(self._windows)
	table.clear(Store.flags)
	table.clear(Store.pending)
	table.clear(Store.listeners)
	Scheduler.clear()
	if Toast then Toast.destroyStandalone() end
	pcall(function()
		local registry = Env.genv().__ArgonUI
		if type(registry) == "table" then registry.library = nil end
	end)
end

Util.onError = nil
return Argon
