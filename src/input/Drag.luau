--!nocheck
-- Drag sessions. InputChanged/InputEnded are connected per session and released at the end.
-- Touch drags follow only the InputObject that started them, so a thumbstick finger never
-- moves a window. Moves are coalesced to one callback per frame.

local Env = require("core/Env")

local Drag = {}
local open = 0

-- handlers: { onStart(pos, input)?, onMove(pos, delta, input), onEnd(pos, cancelled)?,
--             intent = "any"|"horizontal"|"vertical"?, threshold = number?, lockScroll = ScrollingFrame? }
function Drag.begin(input, handlers)
	local uis = Env.services.UserInputService
	local run = Env.services.RunService
	local startInput = input
	local isTouch = input.UserInputType == Enum.UserInputType.Touch
	local startPos = Vector2.new(input.Position.X, input.Position.Y)
	local threshold = handlers.threshold or (isTouch and handlers.intent and handlers.intent ~= "any" and 6) or 0
	local started = threshold <= 0
	local latest, lastSent = startPos, startPos
	local pendingMove = false
	local session = { active = true }
	local connections = {}
	local scroller = handlers.lockScroll
	local scrollWas = nil
	open += 1

	local function finish(cancelled)
		if not session.active then return end
		session.active = false
		open -= 1
		for _, connection in ipairs(connections) do connection:Disconnect() end
		if scroller and scrollWas ~= nil then pcall(function() scroller.ScrollingEnabled = scrollWas end) end
		if started and handlers.onEnd then
			local ok, err = pcall(handlers.onEnd, latest, cancelled == true)
			if not ok then warn("[Argon UI] drag end error: " .. tostring(err)) end
		end
	end
	session.cancel = function() finish(true) end

	local function flush()
		pendingMove = false
		if not session.active or not started then return end
		local delta = latest - lastSent
		lastSent = latest
		local ok, err = pcall(handlers.onMove, latest, delta, startInput)
		if not ok then warn("[Argon UI] drag move error: " .. tostring(err)) end
	end

	local function begin()
		started = true
		if scroller then
			pcall(function()
				scrollWas = scroller.ScrollingEnabled
				scroller.ScrollingEnabled = false
			end)
		end
		if handlers.onStart then pcall(handlers.onStart, startPos, startInput) end
	end
	if started then begin() end

	connections[#connections + 1] = uis.InputChanged:Connect(function(changed)
		if isTouch then
			if changed ~= startInput then return end
		elseif changed.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		latest = Vector2.new(changed.Position.X, changed.Position.Y)
		if not started then
			local moved = latest - startPos
			local intent = handlers.intent
			local ok = moved.Magnitude >= threshold
			if ok and intent == "horizontal" then ok = math.abs(moved.X) > math.abs(moved.Y) end
			if ok and intent == "vertical" then ok = math.abs(moved.Y) > math.abs(moved.X) end
			if not ok then
				if intent and intent ~= "any" and moved.Magnitude >= threshold then finish(true) end
				return
			end
			begin()
		end
		if not pendingMove then
			pendingMove = true
			if run and run.Heartbeat then
				local once
				once = run.Heartbeat:Connect(function()
					once:Disconnect()
					flush()
				end)
			else
				flush()
			end
		end
	end)
	connections[#connections + 1] = uis.InputEnded:Connect(function(ended)
		if isTouch then
			if ended ~= startInput then return end
		elseif ended.UserInputType ~= Enum.UserInputType.MouseButton1 and ended.UserInputType ~= startInput.UserInputType then
			return
		end
		if pendingMove then flush() end
		finish(false)
	end)
	return session
end

function Drag.active()
	return open
end

return Drag
