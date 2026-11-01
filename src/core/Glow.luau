--!nocheck
-- Three glow images per window (DESIGN_V2 2.6): slot 1 focus/drag, slot 2 the selected nav
-- indicator (the only persistent glow), slot 3 short flashes. A new owner takes a slot over.

local Token = require("core/Token")
local Factory = require("core/Factory")
local Motion = require("core/Motion")
local Assets = require("theme/Assets")
local Theme = require("theme/Theme")

local Glow = {}
Glow.__index = Glow

function Glow.attach(window)
	return setmetatable({ window = window, scope = window._scope:child("glow"), slots = {} }, Glow)
end

local function centred(target, spread)
	local anchor, position, size = target.AnchorPoint, target.Position, target.Size
	local cx = UDim.new(position.X.Scale + (0.5 - anchor.X) * size.X.Scale, position.X.Offset + (0.5 - anchor.X) * size.X.Offset)
	local cy = UDim.new(position.Y.Scale + (0.5 - anchor.Y) * size.Y.Scale, position.Y.Offset + (0.5 - anchor.Y) * size.Y.Offset)
	return UDim2.new(cx, cy), UDim2.new(size.X.Scale, size.X.Offset + spread * 2, size.Y.Scale, size.Y.Offset + spread * 2)
end

-- opts: { transparency?, duration?, spread? }. Returns a handle { alive }.
function Glow:acquire(slot, owner, target, opts)
	opts = opts or {}
	local handle = { alive = false }
	if Theme.name == "HighContrast" or not target or not target.Parent then return handle end
	if slot == 3 and Motion.reduced then return handle end
	local state = self.slots[slot]
	if not state then
		state = {}
		self.slots[slot] = state
	end
	-- The image lives next to its current target, so a destroyed row can take it down with it;
	-- a dead image (Parent locked) is replaced instead of reused.
	if not state.image or not pcall(function() state.image.Parent = nil end) then
		state.image = Factory.new(self.scope, "ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Image = Assets.glow.Image,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Assets.glow.SliceCenter,
			ImageColor3 = Token.T.Accent,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
		})
	end
	if state.handle then state.handle.alive = false end
	state.owner = owner
	state.handle = handle
	handle.alive = true
	local image = state.image
	local spread = opts.spread or 10
	local position, size = centred(target, spread)
	image.Position = position
	image.Size = size
	image.ZIndex = math.max(1, target.ZIndex - 1)
	image.ImageTransparency = opts.transparency or 0.55
	image.Parent = target.Parent
	image.Visible = true
	state.target = target
	state.spread = spread
	if opts.duration then
		task.delay(opts.duration, function()
			if state.handle == handle then self:release(slot, owner) end
		end)
	end
	return handle
end

function Glow:release(slot, owner)
	local state = self.slots[slot]
	if not state or state.owner ~= owner then return end
	state.owner = nil
	if state.handle then state.handle.alive = false end
	state.handle = nil
	state.image.Visible = false
	-- out of the owner's tree, so destroying that row cannot destroy the pooled image
	pcall(function() state.image.Parent = nil end)
end

-- Re-reads the target's rect after the owner moved it.
function Glow:sync(slot)
	local state = self.slots[slot]
	if not state or not state.handle or not state.target then return end
	local position, size = centred(state.target, state.spread)
	state.image.Position = position
	state.image.Size = size
end

function Glow:live()
	local count = 0
	for _, state in pairs(self.slots) do
		if state.handle and state.image.Visible then count += 1 end
	end
	return count
end

return Glow
