local Timer = require("src/timer")

local function close(actual, expected)
    assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

local function percentages(seconds, expected)
    local actual = Timer.sectionPercentages(seconds)
    for i = 1, #expected do
        close(actual[i], expected[i])
    end
end

close(Timer.totalTime, 24)
for i, label in ipairs({ "pre-ult", "ult", "post-ult", "tc" }) do
    assert(Timer.sections[i].label == label)
end

for _, pair in ipairs({ { -10, 0 }, { 0, 0 }, { 42.5, 42.5 }, { 100, 100 }, { 150, 100 } }) do
    close(Timer.sanitisePercentage(pair[1]), pair[2])
end

for _, pair in ipairs({
    { 30, "pre-ult" }, { 24, "pre-ult" }, { 20, "pre-ult" },
    { 9.6001, "pre-ult" }, { 9.6, "ult" }, { 9.3, "ult" },
    { 9.0001, "ult" }, { 9, "post-ult" }, { 5, "post-ult" },
    { 0.6001, "post-ult" }, { 0.6, "tc" }, { 0.3, "tc" }, { 0, "tc" },
}) do
    assert(Timer.activeSection(pair[1]).label == pair[2], "section at " .. pair[1])
end

for _, pair in ipairs({
    { 24, 24 }, { 15, 15 }, { 14.5, 14.4 }, { 5, 4.8 },
    { 9.6, 9.6 }, { 9.55, 9.5 }, { 9, 9 }, { 8.9, 8.4 },
    { 0.65, 0.6 }, { 0.6, 0.6 }, { 0.55, 0.5 }, { 0.15, 0.1 },
    { 0.01, 0 }, { 0, 0 }, { -5, 0 },
}) do
    close(Timer.snapRemainingSeconds(pair[1]), pair[2])
end

for _, pair in ipairs({
    { 24, 24 }, { 23.95, 23.9 }, { 14.5, 14.5 }, { 5.09, 5.0 },
    { 9.6, 9.6 }, { 9.55, 9.5 }, { 8.9, 8.9 }, { 0.65, 0.6 },
    { 0.6, 0.6 }, { 0.15, 0.1 }, { 0, 0 }, { -1, 0 },
}) do
    close(Timer.snapRemainingSeconds(pair[1], true), pair[2])
end

percentages(24, { 0, 0, 0, 0 })
percentages(30, { 0, 0, 0, 0 })
percentages(0, { 100, 100, 100, 100 })
percentages(-1, { 100, 100, 100, 100 })
percentages(16.8, { 50, 0, 0, 0 })
percentages(9.6, { 100, 0, 0, 0 })
percentages(9, { 100, 100, 0, 0 })
percentages(6, { 100, 100, 3 / 8.4 * 100, 0 })
percentages(0.6, { 100, 100, 100, 0 })
percentages(0.3, { 100, 100, 100, 50 })

local state = Timer.new()
Timer.update(state, 100)
assert(state.phase == "idle")
local seconds, bars = Timer.display(state)
close(seconds, 0)
for _, value in ipairs(bars) do close(value, 0) end

Timer.start(state)
close(Timer.display(state), 24)
Timer.update(state, 1.25)
local elapsed = state.elapsed
close(Timer.display(state), 22.2)
close(Timer.display(state, true), 22.7)
close(state.elapsed, elapsed)
assert(state.phase == "running", "display options must not reset the timer")
Timer.start(state)
Timer.update(state, 23.399)
assert(state.phase == "running")
Timer.update(state, 0.601)
assert(state.phase == "complete")
local _, completeBars = Timer.display(state)
for _, value in ipairs(completeBars) do close(value, 100) end
Timer.update(state, 0.999)
assert(state.phase == "complete")
Timer.update(state, 0.002)
assert(state.phase == "idle")

Timer.start(state)
Timer.update(state, 23.5)
assert(state.phase == "running")
Timer.start(state)
close(Timer.display(state), 24)
Timer.update(state, 30)
assert(state.phase == "complete")
Timer.start(state)
Timer.update(state, 0.5)
assert(state.phase == "running", "restart cancels the completed-bar reset")
Timer.reset(state)
assert(state.phase == "idle")
Timer.update(state, 30)
assert(state.phase == "idle")

for _, delta in ipairs({ -1, math.huge, 0 / 0 }) do
    assert(not pcall(Timer.update, state, delta), "invalid delta must be reported")
end

-- Different render rates must reach the same completion boundary.
for _, fps in ipairs({ 10, 50, 60, 144 }) do
    Timer.start(state)
    for _ = 1, fps * 24 + 1 do
        Timer.update(state, 1 / fps)
    end
    assert(state.phase == "complete")
end

print("timer_test.lua: passed")
