--!nocheck
-- Motion tokens (DESIGN_V2 section 2.11): the only durations, easings and springs in the
-- library. One shared Heartbeat steps every spring and disconnects when nothing moves.

local Env = require("core/Env")

local Motion = {}
Motion.reduced = false

-- name = { seconds, easing style, direction }
local TWEENS = {
	hover = { 0.10, "Quad", "Out" },
	press = { 0.06, "Quad", "Out" },
	state = { 0.14, "Quart", "Out" },
	popIn = { 0.16, "Quint", "Out" },
	popOut = { 0.10, "Quad", "In" },
	veil = { 0.14, "Quad", "Out" },
	rise = { 0.18, "Quint", "Out" },
	dialogIn = { 0.22, "Quint", "Out" },
	dialogOut = { 0.14, "Quad", "In" },
	scrim = { 0.18, "Quad", "Out" },
	toastOut = { 0.14, "Quad", "In" },
	collapse = { 0.18, "Quad", "Out" },
	tooltip = { 0.12, "Quad", "Out" },
	ghost = { 0.26, "Quint", "Out" },
	window = { 0.24, "Quint", "Out" },
	progress = { 0.18, "Quad", "Out" },
	scroll = { 0.30, "Quint", "Out" },
	drain = { 5, "Linear", "In" },
}

-- name = { damping ratio, angular frequency }
local SPRINGS = {
	snappy = { 0.75, 24 },
	gentle = { 0.85, 18 },
	dock = { 0.62, 18 },
}

-- name = { seconds, easing, direction, reverses }
local LOOPS = {
	spinner = { 0.8, "Linear", "In", false },
	ring = { 0.9, "Linear", "In", false },
	bloom = { 1.6, "Sine", "InOut", true },
	skeleton = { 1.2, "Linear", "In", false },
	indeterminate = { 1.1, "Sine", "InOut", true },
}

local infoCache = {}
local function info(name, seconds, style, direction, repeatCount, reverses)
	local key = name .. (repeatCount and "*" or "") .. tostring(seconds)
	local cached = infoCache[key]
	if cached then return cached end
	local created = TweenInfo.new(
		seconds,
		Env.enum("EasingStyle", style, "Quad"),
		Env.enum("EasingDirection", direction, "Out"),
		repeatCount or 0,
		reverses or false
	)
	infoCache[key] = created
	return created
end

function Motion.duration(name)
	local spec = TWEENS[name]
	if not spec then return 0 end
	if Motion.reduced then return math.min(spec[1], 0.10) end
	return spec[1]
end

function Motion.setReduced(on)
	Motion.reduced = on == true
end

local function setAll(inst, props)
	for prop, value in pairs(props) do
		pcall(function() inst[prop] = value end)
	end
end

-- Tweens props on inst with a named token. opts.animated == false sets them directly.
function Motion.tween(inst, name, props, opts)
	if opts and opts.animated == false then
		setAll(inst, props)
		return nil
	end
	local spec = TWEENS[name] or TWEENS.state
	local seconds = spec[1]
	if Motion.reduced then
		if name == "rise" or name == "ghost" then
			setAll(inst, props)
			return nil
		end
		seconds = math.min(seconds, 0.10)
	end
	local service = Env.services.TweenService
	local ok, tween = pcall(function()
		local created = service:Create(inst, info(name, seconds, spec[2], spec[3]), props)
		if opts and opts.delay then
			task.delay(opts.delay, function() created:Play() end)
		else
			created:Play()
		end
		return created
	end)
	if not ok then
		setAll(inst, props)
		return nil
	end
	return tween
end

-- ---------- springs ----------
local active = {}       -- list of spring states
local byTarget = setmetatable({}, { __mode = "k" }) -- inst -> { prop -> state }
local stepper = nil

local function pack(kind, x)
	if kind == "number" then return x[1] end
	if kind == "Vector2" then return Vector2.new(x[1], x[2]) end
	return UDim2.new(x[1], x[2], x[3], x[4])
end

local function unpackValue(value)
	local kind = typeof(value)
	if kind == "number" then return "number", { value } end
	if kind == "Vector2" then return "Vector2", { value.X, value.Y } end
	return "UDim2", { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
end

local function stepSprings(dt)
	dt = math.min(dt, 1 / 30)
	for index = #active, 1, -1 do
		local s = active[index]
		local settled = true
		local x, v, t = s.x, s.v, s.t
		local w, z = s.omega, s.zeta
		for i = 1, #x do
			local accel = -w * w * (x[i] - t[i]) - 2 * z * w * v[i]
			v[i] += accel * dt
			x[i] += v[i] * dt
			local scale = (i % 2 == 1 and s.kind == "UDim2") and 0.001 or 0.05
			if math.abs(x[i] - t[i]) > scale or math.abs(v[i]) > scale * 4 then settled = false end
		end
		if settled then
			for i = 1, #x do x[i] = t[i] v[i] = 0 end
		end
		local ok = pcall(function() s.inst[s.prop] = pack(s.kind, x) end)
		if settled or not ok then
			table.remove(active, index)
			local map = byTarget[s.inst]
			if map then map[s.prop] = nil end
			if s.done then pcall(s.done) end
		end
	end
	if #active == 0 and stepper then
		stepper:Disconnect()
		stepper = nil
	end
end
Motion._stepSprings = stepSprings

-- Springs inst[prop] toward target. animated == false snaps.
function Motion.spring(inst, prop, target, name, animated, done)
	if animated == false or Motion.reduced then
		local map = byTarget[inst]
		local existing = map and map[prop]
		if existing then
			existing.t = select(2, unpackValue(target))
			existing.x = table.clone(existing.t)
			existing.v = table.create(#existing.x, 0)
		end
		pcall(function() inst[prop] = target end)
		if done then done() end
		return
	end
	local params = SPRINGS[name] or SPRINGS.snappy
	local map = byTarget[inst]
	if not map then
		map = {}
		byTarget[inst] = map
	end
	local kind, goal = unpackValue(target)
	local state = map[prop]
	if state then
		state.t = goal
		state.zeta, state.omega = params[1], params[2]
		state.done = done
	else
		local ok, current = pcall(function() return inst[prop] end)
		if not ok or current == nil then
			pcall(function() inst[prop] = target end)
			return
		end
		local _, x = unpackValue(current)
		state = { inst = inst, prop = prop, kind = kind, x = x, v = table.create(#x, 0), t = goal,
			zeta = params[1], omega = params[2], done = done }
		map[prop] = state
		active[#active + 1] = state
	end
	if not stepper then
		local run = Env.services.RunService
		if run and run.Heartbeat then
			stepper = run.Heartbeat:Connect(stepSprings)
		end
	end
end

-- ---------- loops ----------
local loops = 0

-- An endless tween for a running indicator. handle:stop() ends it. No-op in reduced motion.
function Motion.loop(inst, name, props)
	local handle = { stopped = false }
	if Motion.reduced then
		function handle.stop() end
		return handle
	end
	local spec = LOOPS[name] or LOOPS.spinner
	local service = Env.services.TweenService
	local ok, tween = pcall(function()
		local created = service:Create(inst, info("loop" .. name, spec[1], spec[2], spec[3], -1, spec[4]), props)
		created:Play()
		return created
	end)
	if ok then loops += 1 end
	function handle.stop()
		if handle.stopped then return end
		handle.stopped = true
		if ok then
			loops -= 1
			pcall(tween.Cancel, tween)
		end
	end
	return handle
end

function Motion.active()
	return #active + loops
end

return Motion
