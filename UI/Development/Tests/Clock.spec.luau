return function(Clock)
local now=0
local clock=Clock.new(function() return now end)
clock:StartTimer(10)
now=3;assert(clock:Remaining()==7)
clock:ToggleTimer();now=30;assert(clock:Remaining()==7)
clock:ToggleTimer();now=37;assert(clock:Tick());assert(not clock:Tick())
assert(clock:Remaining()==0)
clock:CancelTimer();assert(clock.timer==nil)
for _,value in ipairs({0,-1,86401,math.huge,0/0}) do assert(not pcall(function() clock:StartTimer(value) end)) end
now=0;clock:ToggleWatch();now=2;assert(clock:Lap());now=5;assert(clock:Lap())
assert(clock.watch.laps[1].seconds==2 and clock.watch.laps[2].seconds==3)
clock:ToggleWatch();now=40;assert(clock:Elapsed()==5)
clock:ToggleWatch();now=45;assert(clock:Elapsed()==10)
for _=1,40 do now+=1;clock:Lap() end
assert(#clock.watch.laps==30 and clock.watch.lapCount==42)
clock:ResetWatch();assert(clock:Elapsed()==0 and not clock.watch.active)
assert(Clock.Format(3661)=='1:01:01' and Clock.Format(9.01,false,true)=='00:10')
assert(Clock.Format(9.999999999,true)=='00:09.99')
print('Clock: countdown, pause/resume, expiry, laps, bounds and formatting passed')

end
