local Encounter = require("src/encounter")
local bosses = {}
local lifeReads = 0
local lifeValue, allowLifeRead = 10000, true
ValueType = { INTEGER = 0, STRING = 36 }
local life = setmetatable({ typeName = "VarPlayer", valueType = ValueType.INTEGER }, {
    __index = function(_, field)
        assert(field == "value" and allowLifeRead)
        lifeReads = lifeReads + 1
        return lifeValue
    end,
})
var = { VarPlayer = { LIFEPOINTS = life } }
local failQuery = nil
NPCList = { ByName = function(pattern)
    assert(pattern == "Vorago", "only Vorago presence should be queried")
    if pattern == failQuery then error("lookup failure") end
    return bosses
end }
local function npc(name, uid)
    return { isValid = true, displayName = name, uid = uid }
end
local invalid = setmetatable({ isValid = false }, {
    __index = function() error("invalid NPC properties must not be accessed") end,
})

allowLifeRead = false
local sample = Encounter.read()
assert(not sample.valid and not sample.error and sample.identity == nil)
assert(sample.status == "Vorago not present - detection disarmed")
assert(lifeReads == 0, "Vorago absence must short-circuit before life-point reads")
bosses = { invalid }
sample = Encounter.read()
assert(not sample.valid and lifeReads == 0)
bosses = { npc("Vorago", 9), npc("VORAGO", 3), npc("Vorago", 9), invalid }
allowLifeRead = true
sample = Encounter.read()
assert(sample.valid and not sample.error)
assert(sample.status == "Vorago present; player alive")
assert(sample.identity == "3,9")

lifeValue = 0
sample = Encounter.read()
assert(not sample.valid and not sample.error)
assert(sample.status:find("life points zero", 1, true))
for _, value in ipairs({ -1, "0", 0.5, math.huge, 0 / 0 }) do
    lifeValue = value
    sample = Encounter.read()
    assert(not sample.valid and sample.error)
end
lifeValue = nil
assert(Encounter.read().error)
lifeValue = 10000
life.valueType, allowLifeRead = ValueType.STRING, false
assert(Encounter.read().error)
life.valueType, allowLifeRead = ValueType.INTEGER, true
var.VarPlayer.LIFEPOINTS = nil
assert(Encounter.read().error)
var.VarPlayer.LIFEPOINTS = life

failQuery = "Vorago"
sample = Encounter.read()
assert(sample.error and not sample.valid)
failQuery = nil
bosses = nil
assert(Encounter.read().error, "failed observation is not an empty list")
bosses = { {} }
assert(Encounter.read().error, "unknown validity is not absence")
bosses = { { isValid = true, displayName = "Vorago" } }
assert(Encounter.read().error, "unknown UID is not absence")
bosses = { npc("Unrelated", 99) }
local beforeExit = lifeReads
sample = Encounter.read()
assert(not sample.valid and lifeReads == beforeExit)
print("encounter_test.lua: passed")
