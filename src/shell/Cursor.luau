--!nocheck
-- Draws a pointer above the window when the game hides the engine cursor (v1 semantics:
-- Cursor = nil|"auto"|true|false). RenderStepped is connected only while the pointer is drawn.

local Env = require("core/Env")
local Factory = require("core/Factory")
local Assets = require("theme/Assets")

local Cursor = {}
Cursor.__index = Cursor

function Cursor.attach(window, mode)
	local self = setmetatable({ window = window, scope = window._scope:child("cursor"), mode = mode == nil and "auto" or mode }, Cursor)
	if mode ~= false then self:_watch() end
	return self
end

function Cursor:gui()
	if self.screen then return self.screen end
	local scope = self.scope
	local screen = Factory.new(scope, "ScreenGui", {
		Name = self.window._guiName .. "Cursor",
		DisplayOrder = 2147483647,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	screen:SetAttribute("ArgonUI", true)
	self.icon = Factory.new(scope, "ImageLabel", {
		Name = "Pointer", BackgroundTransparency = 1, Image = Assets.cursor, Size = UDim2.fromOffset(20, 20), Visible = false, ZIndex = 10,
	}, screen)
	Env.protectGui(screen)
	pcall(function() screen.Parent = self.window.ScreenGui.Parent end)
	self.screen = screen
	return screen
end

function Cursor:_wanted()
	local window = self.window
	if self.mode == false or not window._visible or window._destroyed then return false end
	if self.mode == true then return true end
	local uis = Env.services.UserInputService
	local ok, enabled = pcall(function() return uis.MouseIconEnabled end)
	return ok and enabled == false
end

function Cursor:_watch()
	if self.watching then return end
	local uis = Env.services.UserInputService
	pcall(function()
		self.watching = self.scope:connect(uis:GetPropertyChangedSignal("MouseIconEnabled"), function() self:refresh() end)
	end)
end

function Cursor:refresh()
	local wanted = self:_wanted()
	if wanted then
		self:gui()
		if not self.driver then
			local run = Env.services.RunService
			local uis = Env.services.UserInputService
			self.driver = run.RenderStepped:Connect(function()
				local ok, location = pcall(function() return uis:GetMouseLocation() end)
				if ok and location then
					self.icon.Position = UDim2.fromOffset(location.X, location.Y)
					self.icon.Visible = true
				end
			end)
		end
	else
		if self.driver then
			self.driver:Disconnect()
			self.driver = nil
		end
		if self.icon then self.icon.Visible = false end
	end
end

function Cursor:setMode(mode)
	self.mode = mode == nil and "auto" or mode
	if self.mode ~= false then self:_watch() end
	self:refresh()
end

function Cursor:drawn()
	return self.icon ~= nil and self.icon.Visible == true
end

function Cursor:destroy()
	if self.driver then self.driver:Disconnect() end
	self.driver = nil
	self.scope:destroy()
end

return Cursor
