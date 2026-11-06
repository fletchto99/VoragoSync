local Probe = require("health_probe")
local valueReads, uiReads = 0, 0
ValueType = { INTEGER = 0, STRING = 36 }

local function config(domain, valueType, value)
    return setmetatable({ typeName = domain, valueType = valueType, current = value, allowRead = true }, {
        __index = function(self, field)
            assert(field == "value", "do not access raw packed fields or unrelated metadata")
            assert(self.allowRead, "inactive/restricted/type-invalid values must not be read")
            valueReads = valueReads + 1
            return rawget(self, "current")
        end,
    })
end
local hide = config("VarPlayer", ValueType.INTEGER, 0)
local maximum = config("VarPlayer", ValueType.INTEGER, 250000)
local current = config("VarPlayer", ValueType.INTEGER, 250000)
local name = config("VarClient", ValueType.STRING, "Vorago")
local allowedPlayer = {
    ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS = true,
    ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS = true,
    ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = true,
}
var = {
    VarPlayer = setmetatable({
        ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS = hide,
        ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS = maximum,
        ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = current,
    }, { __index = function(_, key) assert(allowedPlayer[key], "unexpected player variable") end }),
    VarClient = setmetatable({
        ACTIVITY_PROGRESS_BAR_ACTIVE_NAME = name,
    }, { __index = function(_, key) assert(key == "ACTIVITY_PROGRESS_BAR_ACTIVE_NAME") end }),
}
id = { Component = {
    ACTIVITY_PROGRESS_BAR__CONTAINER = 76742679,
    ACTIVITY_PROGRESS_BAR__PROGRESS_BAR = 76742671,
    ACTIVITY_PROGRESS_BAR__ACTIVITY_NAME_TEXT = 76742682,
} }
local function component(componentType)
    return setmetatable({ type = componentType, visibleGlobal = true, isRestricted = false }, {
        __index = function() error("the reader must not read UI contents or traverse") end,
    })
end
local container, progress, label = component(20), component(20), component(7)
local components = { [76742679] = container, [76742671] = progress, [76742682] = label }
ui = { Interfaces = { GetComponent = function(_, combinedID)
    assert(combinedID == 76742679 or combinedID == 76742671 or combinedID == 76742682)
    uiReads = uiReads + 1
    return components[combinedID]
end } }
local function allowValues(allowed)
    hide.allowRead, maximum.allowRead, current.allowRead, name.allowRead = allowed, allowed, allowed, allowed
end

assert(uiReads == 0 and valueReads == 0, "requiring the module must not read data")
local sample = Probe.read()
assert(uiReads == 3 and valueReads == 4)
assert(sample.valid and not sample.error)
assert(sample.name == "Vorago" and sample.current == 250000 and sample.maximum == 250000)
current.current = 0
assert(Probe.read().current == 0, "real zero must remain zero")
allowValues(false)
container.visibleGlobal = false
sample = Probe.read()
assert(sample.status == "Inactive: UI hidden" and not sample.valid and not sample.error)
container.visibleGlobal = true
progress.isRestricted = true
assert(Probe.read().status == "Restricted UI")
progress.isRestricted = false
label.type = "wrong"
assert(Probe.read().status == "Invalid UI metadata")
label.type = 7
allowValues(true)

components = {}
sample = Probe.read()
assert(sample.valid and sample.status == "Active activity - UI not fully exposed")
components = { [76742679] = container, [76742671] = progress, [76742682] = label }
local identity = Probe.read().uiIdentity
label.visibleGlobal = false
sample = Probe.read()
assert(sample.valid and sample.uiIdentity == identity, "optional label visibility is not encounter identity")
label.visibleGlobal = true

hide.current = 1
maximum.allowRead, current.allowRead, name.allowRead = false, false, false
sample = Probe.read()
assert(sample.status == "Inactive: progress hidden" and not sample.valid and sample.current == nil)
hide.current = 2
assert(Probe.read().status == "Invalid hide flag")
hide.current, maximum.allowRead, maximum.current = 0, true, 0
assert(Probe.read().status == "Inactive: maximum is zero")
maximum.current = -1
assert(Probe.read().status == "Invalid maximum")
maximum.current, current.allowRead, name.allowRead = 250000, true, true

current.valueType, current.allowRead = ValueType.STRING, false
sample = Probe.read()
assert(sample.status == "Type error: current value" and sample.error and not sample.valid)
current.valueType, current.typeName = ValueType.INTEGER, "VarClient"
assert(Probe.read().status == "Type error: current value")
current.typeName, current.allowRead = "VarPlayer", true
current.current = nil
assert(Probe.read().status == "Unavailable current value")
for _, invalid in ipairs({ "0", 0.5, math.huge, 0 / 0 }) do
    current.current = invalid
    assert(Probe.read().status == "Invalid integer: current value")
end
for _, invalid in ipairs({ -1, 250001 }) do
    current.current = invalid
    assert(Probe.read().status == "Invalid current/max range")
end
current.current = 1234
name.current = ""
assert(Probe.read().status == "Inactive: no active name")
name.current = string.rep("x", 161)
assert(Probe.read().status == "Activity name too long")
name.current = 123
assert(Probe.read().status == "Invalid text: activity name")
name.current = "<col=ffffff>Vorago</col>\n"
assert(Probe.read().name == "Vorago")

var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = nil
assert(Probe.read().status == "Missing current value")
var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = current
var.VarClient.ACTIVITY_PROGRESS_BAR_ACTIVE_NAME = nil
assert(Probe.read().status == "Missing activity name")
var.VarClient.ACTIVITY_PROGRESS_BAR_ACTIVE_NAME = name
ValueType = nil
assert(Probe.read().status == "Value-type API unavailable")
print("health_probe_test.lua: passed")
