--!nocheck
-- One ScreenGui per window with full-screen layer frames in a fixed order (DESIGN_V2 3.1):
--   Base < Overlay < Toast < Modal < Popover < Tooltip < Boot
-- Layers are created on first use. Every layer has the same UIScale s and is sized 1/s, so a
-- placement in layer-local units is (absolute - origin) / s (layers:toLocal).

local Env = require("core/Env")
local Signal = require("core/Signal")
local Factory = require("core/Factory")
local Router = require("input/Router")

local Layers = {}
Layers.__index = Layers

local ORDER = { Base = 1, Overlay = 2, Toast = 3, Notifications = 3, Modal = 4, Popover = 5, Tooltip = 6, Boot = 7 }
Layers.ORDER = ORDER

function Layers.create(scope, guiName, displayOrder)
	local self = setmetatable({
		scope = scope,
		frames = {},
		scales = {},
		scale = 1,
		resized = Signal.new("Layers.resized"),
		stack = {},
		_sinking = false,
	}, Layers)
	local gui = Factory.new(scope, "ScreenGui", {
		Name = guiName,
		DisplayOrder = displayOrder or 100,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	if not Env.try(gui, "ScreenInsets", Env.enum("ScreenInsets", "CoreUISafeInsets")) then
		Env.try(gui, "IgnoreGuiInset", false)
	end
	gui:SetAttribute("ArgonUI", true)
	self.gui = gui
	self:get("Base")
	self:get("Boot")
	return self
end

-- Parents the ScreenGui (gethui, CoreGui or PlayerGui) and starts watching its size.
function Layers:mount()
	Env.protectGui(self.gui)
	Env.parentGui(self.gui)
	self.scope:connect(self.gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		self.resized:Fire(self:guiSize())
	end)
end

function Layers:get(name)
	local frame = self.frames[name]
	if frame then return frame end
	local s = self.scale
	frame = Factory.new(self.scope, "Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1 / s, 1 / s),
		ZIndex = ORDER[name] or 1,
		Active = false,
	}, self.gui)
	self.scales[name] = Factory.new(self.scope, "UIScale", { Scale = s }, frame)
	self.frames[name] = frame
	return frame
end

function Layers:has(name)
	return self.frames[name] ~= nil
end

function Layers:setScale(s)
	s = math.clamp(tonumber(s) or 1, 0.5, 2)
	self.scale = s
	for name, frame in pairs(self.frames) do
		frame.Size = UDim2.fromScale(1 / s, 1 / s)
		self.scales[name].Scale = s
	end
	self.resized:Fire(self:guiSize())
end

function Layers:guiSize()
	local size = self.gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		local camera = workspace and workspace.CurrentCamera
		if camera then return camera.ViewportSize end
		return Vector2.new(1280, 720)
	end
	return size
end

-- Layer-local size (what Offset positions inside a layer are measured against).
function Layers:localSize()
	local size = self:guiSize()
	return Vector2.new(size.X / self.scale, size.Y / self.scale)
end

function Layers:toLocal(absolute)
	local origin = self.gui.AbsolutePosition
	return Vector2.new((absolute.X - origin.X) / self.scale, (absolute.Y - origin.Y) / self.scale)
end

-- A GuiObject's rect in layer-local units: position, size.
function Layers:rectOf(gui)
	local position = self:toLocal(gui.AbsolutePosition)
	local size = gui.AbsoluteSize
	return position, Vector2.new(size.X / self.scale, size.Y / self.scale)
end

-- ---------- dismiss stack ----------
local CLOSE_KEYS = { "Backspace", "ButtonB" }

function Layers:_updateSink()
	local want = #self.stack > 0
	if want == self._sinking then return end
	self._sinking = want
	local keys = {}
	for _, name in ipairs(CLOSE_KEYS) do
		local code = Env.enum("KeyCode", name)
		if code then keys[#keys + 1] = code end
	end
	Router.sink("ArgonClose" .. tostring(self.gui.Name), want, keys)
end

-- entry: { id, kind, close(reason) }. Returns the entry.
function Layers:push(entry)
	self:pop(entry)
	self.stack[#self.stack + 1] = entry
	self:_updateSink()
	return entry
end

function Layers:pop(entry)
	for index = #self.stack, 1, -1 do
		if self.stack[index] == entry then table.remove(self.stack, index) end
	end
	self:_updateSink()
end

function Layers:top()
	return self.stack[#self.stack]
end

function Layers:closeTop(reason)
	local entry = self.stack[#self.stack]
	if not entry then return false end
	table.remove(self.stack, #self.stack)
	self:_updateSink()
	local ok, err = pcall(entry.close, reason)
	if not ok then warn("[Argon UI] layer close failed: " .. tostring(err)) end
	return true
end

-- Closes popovers, menus and tooltips ("tab"), or everything ("hide").
function Layers:closeAll(reason)
	for index = #self.stack, 1, -1 do
		local entry = self.stack[index]
		if entry and (reason ~= "tab" or entry.kind == "popover" or entry.kind == "menu" or entry.kind == "tooltip") then
			table.remove(self.stack, index)
			pcall(entry.close, reason)
		end
	end
	self:_updateSink()
end

return Layers
