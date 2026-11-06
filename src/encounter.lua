local Encounter = {}

local function integer(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value % 1 == 0
end

local function voragoIDs()
    local ok, npcs = pcall(NPCList.ByName, "Vorago")
    if not ok then return nil, "NPC lookup failed: Vorago", tostring(npcs) end
    if type(npcs) ~= "table" then return nil, "NPC list unavailable: Vorago" end
    local seen, ids = {}, {}
    for _, npc in ipairs(npcs) do
        if type(npc.isValid) ~= "boolean" then return nil, "NPC validity unavailable: Vorago" end
        if npc.isValid then
            if type(npc.displayName) ~= "string" then return nil, "NPC name unavailable: Vorago" end
            if npc.displayName:lower() == "vorago" then
                local uid = npc.uid
                if not integer(uid) then return nil, "NPC UID unavailable: Vorago" end
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
    local result = { valid = false, error = false }
    local bosses, status, detail = voragoIDs()
    if status then return failure(result, status, detail) end
    if #bosses == 0 then
        result.status = "Vorago not present - detection disarmed"
        return result
    end
    result.identity = table.concat(bosses, ",")

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
    result.valid, result.status = true, "Vorago present; player alive"
    return result
end

return Encounter
