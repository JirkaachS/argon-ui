--!nocheck
-- The only place instances are created. Token props are resolved and recorded in the scope's
-- paint list; plain values are written as given. Parent is applied last, so a subtree is
-- assembled detached and parented into the live tree once.

local Token = require("core/Token")

local Factory = {}
Factory.created = 0
Factory.byClass = {}

local isToken = Token.isToken
local resolve = Token.resolve

local GUI = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
	ImageButton = true, ScrollingFrame = true, ViewportFrame = true,
}

local function apply(scope, inst, props)
	for prop, value in pairs(props) do
		if prop ~= "Parent" then
			if isToken(value) then
				inst[prop] = resolve(value)
				scope:paint(inst, prop, value)
			else
				inst[prop] = value
			end
		end
	end
end
Factory.apply = apply

-- Creates className with props under parent (or detached), owned by scope.
function Factory.new(scope, className, props, parent)
	local inst = Instance.new(className)
	Factory.created += 1
	Factory.byClass[className] = (Factory.byClass[className] or 0) + 1
	if GUI[className] then
		inst.BorderSizePixel = 0
		if className == "TextButton" or className == "ImageButton" then
			inst.AutoButtonColor = false
			if className == "TextButton" then inst.Text = "" end
		end
	end
	if props then apply(scope, inst, props) end
	parent = parent or (props and props.Parent)
	if parent then inst.Parent = parent end
	scope:instance(inst)
	return inst
end

local TEXT_DEFAULTS = {
	Text = "",
	BackgroundTransparency = 1,
	FontFace = Token.F.Body,
	TextSize = Token.TS.Body,
	TextColor3 = Token.T.Text,
}

-- A text object with the body defaults (font role, size role, Text colour, left aligned).
function Factory.text(scope, className, props, parent)
	local merged = table.clone(TEXT_DEFAULTS)
	if props then
		for key, value in pairs(props) do merged[key] = value end
	end
	local inst = Factory.new(scope, className, merged, parent)
	if merged.TextXAlignment == nil then inst.TextXAlignment = Enum.TextXAlignment.Left end
	return inst
end

local FULL = UDim.new(1, 0)
function Factory.corner(scope, parent, radius)
	return Factory.new(scope, "UICorner", {
		CornerRadius = radius == "full" and FULL or UDim.new(0, radius or 10),
	}, parent)
end

function Factory.stroke(scope, parent, color, transparency, thickness)
	return Factory.new(scope, "UIStroke", {
		Color = color or Token.T.Border,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Factory.padding(scope, parent, left, right, top, bottom)
	return Factory.new(scope, "UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
	}, parent)
end

function Factory.list(scope, parent, props)
	local merged = { SortOrder = Enum.SortOrder.LayoutOrder }
	if props then
		for key, value in pairs(props) do merged[key] = value end
	end
	return Factory.new(scope, "UIListLayout", merged, parent)
end

-- A plain object that no scope owns (GetTextBoundsParams and the like).
function Factory.object(className)
	return Instance.new(className)
end

function Factory.stats()
	return { created = Factory.created, byClass = table.clone(Factory.byClass) }
end

return Factory
