--!nocheck
-- Space: an empty gap of px pixels inside the platter, clamped to 4-80 (v1). It draws nothing,
-- not even the row divider. CreateSpace(px = 10); Set(px) resizes it.

local Element = require("component/Element")

local function px(value)
	return math.clamp(math.floor(tonumber(value) or 10), 4, 80)
end

return Element.define({
	Type = "Space",
	defaultName = "Space",
	display = true,
	title = false,
	counts = false,
	noMenu = true,
	descriptionIsContent = true,

	fromArgs = function(config)
		if type(config) == "table" then return config end
		return { Height = config }
	end,

	init = function(self, config)
		self.CurrentValue = px(config.Height or config.Size or config.Value)
	end,

	height = function(self)
		return self.CurrentValue
	end,

	build = function(_, view)
		if view.Divider then
			view.Divider:Destroy()
			view.Divider = nil
		end
	end,

	methods = {
		Set = function(self, value)
			self.CurrentValue = px(value)
			if rawget(self, "_mounted") and self._view then
				self._view.band = self.CurrentValue
				self._view.Root.Size = UDim2.new(1, 0, 0, self.CurrentValue)
			end
			return self
		end,

		SetDesc = function(self)
			return self
		end,
	},
})
