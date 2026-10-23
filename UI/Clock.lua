-- Monotonic timer/stopwatch model. No rendering, yields, or Roblox dependencies.
local Clock = {}
Clock.__index = Clock

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Clock.new(now)
	return setmetatable({now = now or os.clock, timer = nil,
		watch = {elapsed = 0, started = nil, laps = {}, splitAt = 0, active = false}, revision = 0}, Clock)
end

function Clock:StartTimer(seconds)
	assert(finite(seconds) and seconds >= 1 and seconds <= 86400, "Timer must be between 1 second and 24 hours")
	self.timer = {remaining = seconds, started = self.now(), duration = seconds, finished = false}
	self.revision += 1
end

function Clock:Remaining()
	local timer = self.timer
	if not timer then return 0 end
	return math.max(0, timer.remaining - (timer.started and math.max(0, self.now() - timer.started) or 0))
end

function Clock:ToggleTimer()
	local timer = self.timer
	if not timer or timer.finished then return end
	if timer.started then timer.remaining = self:Remaining(); timer.started = nil
	else timer.started = self.now() end
	self.revision += 1
end

function Clock:CancelTimer()
	self.timer = nil
	self.revision += 1
end

function Clock:Elapsed()
	local watch = self.watch
	return watch.elapsed + (watch.started and math.max(0, self.now() - watch.started) or 0)
end

function Clock:ToggleWatch()
	local watch = self.watch
	watch.active = true
	if watch.started then watch.elapsed = self:Elapsed(); watch.started = nil
	else watch.started = self.now() end
	self.revision += 1
end

function Clock:Lap()
	local watch = self.watch
	if not watch.started then return false end
	local elapsed = self:Elapsed()
	watch.laps[#watch.laps + 1] = {number = (watch.lapCount or 0) + 1, seconds = elapsed - watch.splitAt}
	watch.lapCount = (watch.lapCount or 0) + 1
	watch.splitAt = elapsed
	if #watch.laps > 30 then table.remove(watch.laps, 1) end
	self.revision += 1
	return true
end

function Clock:ResetWatch()
	self.watch = {elapsed = 0, started = nil, laps = {}, splitAt = 0, active = false, lapCount = 0}
	self.revision += 1
end

function Clock:Tick()
	local timer = self.timer
	if timer and not timer.finished and self:Remaining() <= 0 then
		timer.remaining, timer.started, timer.finished = 0, nil, true
		self.revision += 1
		return true -- Edge-triggered: exactly one completion per timer.
	end
	return false
end

function Clock.Format(seconds, hundredths, roundUp)
	seconds = finite(seconds) and math.max(0, seconds) or 0
	local whole = roundUp and math.ceil(seconds) or math.floor(seconds)
	local hours, minutes, remainder = math.floor(whole / 3600), math.floor(whole / 60) % 60, whole % 60
	local result = hours > 0 and string.format("%d:%02d:%02d", hours, minutes, remainder)
		or string.format("%02d:%02d", math.floor(whole / 60), remainder)
	if hundredths then result ..= string.format(".%02d", math.min(99,math.floor((seconds % 1) * 100 + 0.000001))) end
	return result
end

return Clock
