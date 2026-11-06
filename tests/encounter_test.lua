local Encounter = require("encounter")
local bosses, scops = {}, {}
local scopQueries, lifeReads = 0, 0
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
    if pattern == failQuery then error("lookup failure") end
    if pattern == "Vorago" then return bosses end
    assert(pattern == "*Scopul*", "no broad or unrelated NPC query")
    scopQueries = scopQueries + 1
    return scops
end }
local function npc(name, uid)
    return { isValid = true, displayName = name, uid = uid }
end
local invalid = setmetatable({ isValid = false }, {
    __index = function() error("invalid NPC properties must not be accessed") end,
})

allowLifeRead = false
local sample = Encounter.read()
assert(not sample.valid and not sample.error and not sample.voragoPresent)
assert(scopQueries == 0 and lifeReads == 0, "Vorago absence must short-circuit before Scop disappearance")
bosses = { invalid }
sample = Encounter.read()
assert(not sample.valid and scopQueries == 0)
bosses = { npc("Vorago", 9), npc("VORAGO", 3), npc("Vorago", 9) }
allowLifeRead = true
scops = { npc("Scopulus", 4), npc("Scopuli", 5), npc("Scopulus", 4), invalid }
sample = Encounter.read()
assert(sample.valid and sample.voragoPresent and sample.playerAlive)
assert(sample.scopCount == 2 and sample.identity == "3,9")
scops = { invalid }
sample = Encounter.read()
assert(sample.valid and sample.scopCount == 0, "isValid=false counts as absence, not a proven kill")
scops = {}
sample = Encounter.read()
assert(sample.valid and sample.scopCount == 0)

local queriesBeforeDeath = scopQueries
lifeValue = 0
sample = Encounter.read()
assert(not sample.valid and not sample.playerAlive and not sample.error)
assert(sample.scopCount == nil and scopQueries == queriesBeforeDeath)
assert(sample.status:find("life points zero", 1, true))
for _, value in ipairs({ -1, "0", 0.5, math.huge, 0 / 0 }) do
    lifeValue = value
    sample = Encounter.read()
    assert(not sample.valid and sample.error and sample.scopCount == nil)
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
assert(scopQueries == queriesBeforeDeath)

failQuery = "Vorago"
sample = Encounter.read()
assert(sample.error and not sample.valid and sample.scopCount == nil)
failQuery = "*Scopul*"
sample = Encounter.read()
assert(sample.error and not sample.valid)
failQuery = nil
scops = nil
assert(Encounter.read().error, "failed observation is not an empty list")
scops = { {} }
assert(Encounter.read().error, "unknown validity is not absence")
scops = { { isValid = true, displayName = "Scopulus" } }
assert(Encounter.read().error, "unknown UID is not absence")
scops = { npc("Unrelated", 99) }
assert(Encounter.read().scopCount == 0)
bosses = { npc("Unrelated", 99) }
local beforeExit = scopQueries
sample = Encounter.read()
assert(not sample.valid and scopQueries == beforeExit)
print("encounter_test.lua: passed")
