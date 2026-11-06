local Detector = require("detector")
local function reading(current, changes)
    local result = { valid = true, error = false, name = "Vorago", current = current, maximum = 250000, uiIdentity = "stable" }
    for key, value in pairs(changes or {}) do result[key] = value end
    return result
end
local state = Detector.new()
local function observe(value, busy, gap)
    return Detector.observe(state, value, busy or false, gap or Detector.pollInterval)
end

assert(not observe(reading(0)), "startup zero is not an edge")
assert(not observe(reading(0)), "sustained startup zero is not an edge")
assert(not observe(reading(250000)))
assert(state.positive ~= nil)
assert(observe(reading(0)))
assert(state.positive == nil)
for _ = 1, 20 do assert(not observe(reading(0)), "sustained zero must not restart") end
assert(not observe(reading(1)))
assert(observe(reading(0)), "a fresh positive observation rearms")

for _, invalid in ipairs({
    { valid = false, status = "Inactive: progress hidden" },
    { valid = false, error = true, status = "Missing current value" },
    reading(0, { error = true }),
    reading("0"), reading(-1), reading(250001), reading(0.5),
    reading(0 / 0), reading(math.huge), reading(0, { maximum = 0 }),
    reading(0, { maximum = -1 }), reading(0, { maximum = "250000" }),
    reading(0, { name = "Other activity" }), reading(0, { name = "Vorago clone" }),
    reading(0, { uiIdentity = false }),
}) do
    observe(reading(250000))
    assert(not observe(invalid))
    assert(state.positive == nil)
    assert(not observe(reading(0)), "uncertain/lost data must not retain a positive edge")
end
observe(reading(250000))
assert(not observe(nil))
assert(not observe(reading(0)))

observe(reading(250000))
assert(not observe(reading(0, { maximum = 100000 })), "changed maximum is a new identity")
assert(not observe(reading(0)))
observe(reading(250000))
assert(not observe(reading(0, { uiIdentity = "UI disappeared" })), "changed container availability invalidates the edge")
assert(not observe(reading(0)))
observe(reading(10, { uiIdentity = "not exposed from the outset" }))
assert(observe(reading(0, { uiIdentity = "not exposed from the outset" })),
    "confirmed variables need not depend on optional UI exposure")
observe(reading(10, { ui = "all components visible" }))
assert(observe(reading(0, { ui = "fill component hidden" })),
    "optional fill visibility must not suppress a real zero")

observe(reading(100), true)
assert(not observe(reading(0), true), "do not restart an active countdown")
assert(not observe(reading(0)), "do not queue a zero observed during a countdown")
observe(reading(100), true)
assert(observe(reading(0)), "a new positive can be observed before the prior timer ends")

observe(reading(100))
Detector.reset(state)
assert(not observe(reading(0)), "lifecycle reset must discard history")
observe(reading(100))
assert(not observe(reading(0), false, Detector.maxObservationGap + 0.01), "stale edge must be discarded")
observe(reading(100), false, 10)
assert(observe(reading(0)), "a fresh positive after a stall can rearm")
for _, gap in ipairs({ -1, math.huge, 0 / 0 }) do
    observe(reading(100))
    assert(not observe(reading(0), false, gap))
    assert(state.positive == nil)
end
observe(reading(100, { name = "  VORAGO  " }))
assert(observe(reading(0, { name = "vorago" })))

local function encounter(count, changes)
    local value = { valid = true, error = false, voragoPresent = true, playerAlive = true, identity = "boss-1", scopCount = count }
    for key, change in pairs(changes or {}) do value[key] = change end
    return value
end
local function scop(value, busy, gap)
    return Detector.observeScop(state, value, busy or false, gap or Detector.pollInterval)
end
Detector.reset(state)
assert(not scop(encounter(0)), "startup absence must not trigger")
assert(not scop(encounter(2)))
assert(state.scop ~= nil)
assert(not scop(encounter(1)), "one remaining minion must not trigger")
assert(scop(encounter(0)))
assert(state.scop == nil)
assert(not scop(encounter(0)), "continued absence must not trigger")
scop(encounter(5))
assert(scop(encounter(0)), "no hardcoded minion count")
for _, loss in ipairs({
    encounter(0, { valid = false }), encounter(0, { error = true }),
    encounter(0, { voragoPresent = false }), encounter(0, { playerAlive = false }),
    encounter(0, { identity = "different-boss" }), encounter("0"), encounter(-1),
}) do
    scop(encounter(2))
    assert(not scop(loss))
    assert(state.scop == nil)
    assert(not scop(encounter(0)), "loss/error/death must discard the armed flag")
end
scop(encounter(2))
assert(not scop(nil))
assert(not scop(encounter(0)))
scop(encounter(2))
assert(not scop(encounter(0), true), "active/full-hold edges are consumed")
assert(not scop(encounter(0)), "do not queue an active-run edge")
scop(encounter(2))
assert(not scop(encounter(0), false, Detector.maxObservationGap + 0.1))
observe(reading(100))
scop(encounter(2))
Detector.reset(state)
assert(state.scop == nil and state.positive == nil, "shared start reset clears both latches")
assert(not scop(encounter(0)))
print("detector_test.lua: passed")
