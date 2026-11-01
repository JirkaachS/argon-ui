--!nocheck
-- Every Create<Control> builder and its short alias, generated from one table and installed on
-- tabs, sections and row columns. A control module is loaded the first time it is used.

local Tab = require("container/Tab")
local Section = require("container/Section")
local Row = require("container/Row")

local Builders = {}

local LOADERS = {
	Label = function() return require("display/Label") end,
	Button = function() return require("controls/Button") end,
	ButtonGroup = function() return require("controls/ButtonGroup") end,
	Toggle = function() return require("controls/Toggle") end,
	Slider = function() return require("controls/Slider") end,
	Input = function() return require("controls/Input") end,
	Keybind = function() return require("controls/Keybind") end,
	Dropdown = function() return require("controls/Dropdown") end,
	Paragraph = function() return require("display/Paragraph") end,
	TelemetryCard = function() return require("display/TelemetryCard") end,
	Divider = function() return require("display/Divider") end,
	Space = function() return require("display/Space") end,
	ProgressBar = function() return require("display/ProgressBar") end,
	Stepper = function() return require("controls/Stepper") end,
	Segmented = function() return require("controls/Segmented") end,
	TextArea = function() return require("controls/TextArea") end,
	List = function() return require("display/List") end,
	ColorPicker = function() return require("controls/ColorPicker") end,
	Callout = function() return require("display/Callout") end,
	Image = function() return require("display/Image") end,
}

-- name = { control, config transform? }
local KINDS = {
	Label = { "Label" }, Button = { "Button" }, ButtonGroup = { "ButtonGroup" }, Toggle = { "Toggle" },
	Slider = { "Slider" }, Input = { "Input" }, Keybind = { "Keybind" }, Dropdown = { "Dropdown" },
	Paragraph = { "Paragraph" }, TelemetryCard = { "TelemetryCard" }, Divider = { "Divider" }, Space = { "Space" },
	ProgressBar = { "ProgressBar" }, Stepper = { "Stepper" }, Segmented = { "Segmented" }, TextArea = { "TextArea" },
	List = { "List" }, ColorPicker = { "ColorPicker" }, Colorpicker = { "ColorPicker" }, Callout = { "Callout" },
	Image = { "Image" },
	Checkbox = { "Toggle", function(config)
		config = type(config) == "table" and table.clone(config) or { Name = config }
		config.Style = "Checkbox"
		return config
	end },
	Stat = { "TelemetryCard", function(config)
		config = type(config) == "table" and table.clone(config) or { Label = config }
		config.Variant = "stat"
		return config
	end },
}
Builders.KINDS = KINDS

local function make(kind, ownerOf)
	local spec = KINDS[kind]
	local loader = LOADERS[spec[1]]
	local transform = spec[2]
	return function(self, config, ...)
		local class = loader()
		if transform then config = transform(config) end
		return class.create(ownerOf(self), config, ...)
	end
end

local function install(target, ownerOf, skip)
	for kind in pairs(KINDS) do
		if not (skip and skip[kind]) then
			local builder = make(kind, ownerOf)
			target["Create" .. kind] = builder
			target[kind] = builder
		end
	end
end

install(Tab, function(tab) return tab:_currentOrDefault() end)
install(Section, function(section) return section end)
install(Row, function(row) return row:_column() end)

function Section:CreateRow(config)
	return Row.create(self, config)
end
Section.Row = Section.CreateRow

-- v1: a section builder runs with the section as the tab's current section for its duration.
function Section:_build(method, ...)
	local tab = self.Tab
	local previous = tab._currentSection
	tab._currentSection = self
	local results = table.pack(pcall(tab[method], tab, ...))
	tab._currentSection = previous
	if not results[1] then error(results[2], 2) end
	return table.unpack(results, 2, results.n)
end

return Builders
