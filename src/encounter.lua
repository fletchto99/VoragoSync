local Encounter = {}

local function integer(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value % 1 == 0
end

local function npcIDs(pattern, matches)
    local ok, npcs = pcall(NPCList.ByName, pattern)
    if not ok then return nil, "NPC lookup failed: " .. pattern, tostring(npcs) end
    if type(npcs) ~= "table" then return nil, "NPC list unavailable: " .. pattern end
    local seen, ids = {}, {}
    for _, npc in ipairs(npcs) do
        if type(npc.isValid) ~= "boolean" then return nil, "NPC validity unavailable: " .. pattern end
        if npc.isValid then
            if type(npc.displayName) ~= "string" then return nil, "NPC name unavailable: " .. pattern end
            if matches(npc.displayName:lower()) then
                local uid = npc.uid
                if not integer(uid) then return nil, "NPC UID unavailable: " .. pattern end
                if not seen[uid] then
                    seen[uid] = true
                    ids[#ids + 1] = uid
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

local function failure(result, status, detail)
    result.error, result.status, result.detail = true, status, detail
    return result
end

function Encounter.read()
    local result = { valid = false, error = false, voragoPresent = false, playerAlive = false }
    local bosses, status, detail = npcIDs("Vorago", function(name) return name == "vorago" end)
    if status then return failure(result, status, detail) end
    if #bosses == 0 then
        result.status = "Vorago not present - detection disarmed"
        return result
    end
    result.voragoPresent, result.identity = true, table.concat(bosses, ",")

    local life = var and var.VarPlayer and var.VarPlayer.LIFEPOINTS
    if life == nil then return failure(result, "Own life points unavailable") end
    if ValueType == nil or ValueType.INTEGER == nil
        or life.typeName ~= "VarPlayer" or life.valueType ~= ValueType.INTEGER then
        return failure(result, "Own life points have unexpected type")
    end
    local value = life.value
    if not integer(value) or value < 0 then return failure(result, "Own life points invalid/unavailable") end
    if value == 0 then
        result.status = "Own life points zero - detection disarmed"
        return result
    end
    result.playerAlive = true

    result.valid, result.status = true, "Vorago present; player alive"
    return result
end

return Encounter
