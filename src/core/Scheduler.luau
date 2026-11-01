--!nocheck
-- Frame-budgeted job queue. Mounting, background tabs and idle warm-ups run here in slices so
-- no frame carries more than a few milliseconds of library work. Heartbeat is connected only
-- while the queue has work, so an idle library costs nothing per frame.

local Env = require("core/Env")
local Signal = require("core/Signal")

local Scheduler = {}
Scheduler.drained = Signal.new("Scheduler.drained")

local BUDGET = { loading = 0.008, interactive = 0.004, paused = 0.004 }
local mode = "interactive"
local queue = {}
local byKey = {}
local heartbeat = nil
local foreground = 0
local running = false
local stats = { slices = 0, lastSliceMs = 0, maxSliceMs = 0 }

local function sortQueue()
	table.sort(queue, function(a, b)
		if a.priority ~= b.priority then return a.priority < b.priority end
		return a._seq < b._seq
	end)
end

local seq = 0
local step

local function connect()
	if heartbeat then return end
	local run = Env.services.RunService
	if run and run.Heartbeat then
		heartbeat = run.Heartbeat:Connect(function() step() end)
	end
end

local function disconnect()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function removeJob(job)
	for index = #queue, 1, -1 do
		if queue[index] == job then
			table.remove(queue, index)
			break
		end
	end
	if job.key ~= nil and byKey[job.key] == job then byKey[job.key] = nil end
end

-- Runs one job; returns true when it finished.
local function runJob(job, deadline)
	local ok, done = pcall(job.run, deadline)
	if not ok then
		warn("[Argon UI] background job " .. tostring(job.label or job.key) .. " failed: " .. tostring(done))
		return true
	end
	return done == true
end

function step()
	if running then return end
	if #queue == 0 then
		disconnect()
		return
	end
	running = true
	local budget = BUDGET[mode] or 0.004
	budget = math.max(0.001, budget - foreground)
	foreground = 0
	local start = Env.clock()
	local deadline = start + budget
	Env.profileBegin("Argon/slice")
	while #queue > 0 do
		local job = queue[1]
		if mode == "paused" and job.priority > 1 then break end
		local finished = runJob(job, deadline)
		if finished then
			removeJob(job)
		end
		if Env.clock() >= deadline then break end
		if not finished then break end
	end
	Env.profileEnd()
	local spent = (Env.clock() - start) * 1000
	stats.slices += 1
	stats.lastSliceMs = spent
	if spent > stats.maxSliceMs then stats.maxSliceMs = spent end
	running = false
	if #queue == 0 then
		disconnect()
		Scheduler.drained:Fire()
	end
end
Scheduler.step = step

-- Adds a job {key?, priority, run(deadline) -> done, label?}. A job with an existing key is
-- re-prioritised instead of queued twice.
function Scheduler.enqueue(job)
	if job.key ~= nil then
		local existing = byKey[job.key]
		if existing then
			if job.priority < existing.priority then
				existing.priority = job.priority
				sortQueue()
			end
			return existing
		end
		byKey[job.key] = job
	end
	seq += 1
	job._seq = seq
	queue[#queue + 1] = job
	sortQueue()
	connect()
	return job
end

function Scheduler.bump(key, priority)
	local job = byKey[key]
	if job and priority < job.priority then
		job.priority = priority
		sortQueue()
	end
end

function Scheduler.cancel(key)
	local job = byKey[key]
	if job then removeJob(job) end
	if #queue == 0 then disconnect() end
end

function Scheduler.has(key)
	return byKey[key] ~= nil
end

-- Runs the matching job (or every job) to completion now, ignoring the budget.
function Scheduler.flush(key)
	local function drain(job)
		local guard = 0
		while guard < 100000 do
			guard += 1
			if runJob(job, math.huge) then break end
		end
		removeJob(job)
	end
	if key ~= nil then
		local job = byKey[key]
		if job then drain(job) end
	else
		while #queue > 0 do drain(queue[1]) end
	end
	if #queue == 0 then disconnect() end
end

function Scheduler.setMode(newMode)
	mode = newMode
end

function Scheduler.mode()
	return mode
end

-- Library work done outside a slice this frame (Create*, setters); the next slice shrinks.
function Scheduler.noteForeground(seconds)
	foreground += seconds
end

function Scheduler.idle()
	return #queue == 0
end

function Scheduler.clear()
	table.clear(queue)
	table.clear(byKey)
	disconnect()
end

function Scheduler.stats()
	return {
		pending = #queue,
		lastSliceMs = stats.lastSliceMs,
		maxSliceMs = stats.maxSliceMs,
		slices = stats.slices,
		mode = mode,
		connected = heartbeat ~= nil,
	}
end

return Scheduler
