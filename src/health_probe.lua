local HealthProbe = {}

local uiNames = {
    { role = "container", name = "ACTIVITY_PROGRESS_BAR__CONTAINER" },
    { role = "progress", name = "ACTIVITY_PROGRESS_BAR__PROGRESS_BAR" },
    { role = "name", name = "ACTIVITY_PROGRESS_BAR__ACTIVITY_NAME_TEXT" },
}

local function integer(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value % 1 == 0
end

local function readVariable(domain, name, expectedType, label)
    local variables = var and var[domain]
    local config = variables and variables[name]
    local path = "var." .. domain .. "." .. name
    if config == nil then return nil, "Missing " .. label, path end
    if config.typeName ~= domain or config.valueType ~= expectedType then
        return nil, "Type error: " .. label, path
    end
    local value = config.value
    if value == nil then return nil, "Unavailable " .. label, path end
    if expectedType == ValueType.INTEGER and not integer(value) then
        return nil, "Invalid integer: " .. label, path
    end
    if expectedType == ValueType.STRING and type(value) ~= "string" then
        return nil, "Invalid text: " .. label, path
    end
    return value
end

local function inspectUI()
    local metadata = {}
    local state = "visible"
    local blocked = nil
    local identity = "container=unavailable"
    for _, item in ipairs(uiNames) do
        local combinedID = id.Component[item.name]
        local component = type(combinedID) == "number" and ui.Interfaces:GetComponent(combinedID) or nil
        if component == nil then
            state = "not fully exposed"
            metadata[#metadata + 1] = item.role .. "=unavailable"
        elseif not integer(component.type) or type(component.visibleGlobal) ~= "boolean"
            or type(component.isRestricted) ~= "boolean" then
            blocked = "Invalid UI metadata"
            metadata[#metadata + 1] = item.role .. "=invalid-metadata"
        else
            if item.role == "container" then
                identity = string.format("container(type=%d,visible=%s)",
                    component.type, tostring(component.visibleGlobal))
            end
            metadata[#metadata + 1] = string.format("%s(type=%d,visible=%s,restricted=%s)",
                item.role, component.type, tostring(component.visibleGlobal), tostring(component.isRestricted))
            if component.isRestricted then
                blocked = "Restricted UI"
            elseif not component.visibleGlobal then
                state = "partially hidden"
                if item.role == "container" then blocked = "Inactive: UI hidden" end
            end
        end
    end
    return state, table.concat(metadata, " "), blocked, identity
end

local function failure(result, status, detail)
    result.status, result.detail, result.error = status, detail, true
    return result
end

function HealthProbe.read()
    local uiState, uiMetadata, blocked, uiIdentity = inspectUI()
    local result = { status = blocked, ui = uiMetadata, uiIdentity = uiIdentity, valid = false, error = false }
    if blocked then
        result.error = blocked ~= "Inactive: UI hidden"
        return result
    end
    if ValueType == nil or ValueType.INTEGER == nil or ValueType.STRING == nil then
        return failure(result, "Value-type API unavailable")
    end

    local hidden, status, detail = readVariable("VarPlayer", "ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS",
        ValueType.INTEGER, "hide flag")
    if status then return failure(result, status, detail) end
    if hidden == 1 then result.status = "Inactive: progress hidden"; return result end
    if hidden ~= 0 then return failure(result, "Invalid hide flag") end

    local maximum
    maximum, status, detail = readVariable("VarPlayer", "ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS",
        ValueType.INTEGER, "maximum")
    if status then return failure(result, status, detail) end
    if maximum == 0 then result.status = "Inactive: maximum is zero"; return result end
    if maximum < 0 then return failure(result, "Invalid maximum") end

    local current
    current, status, detail = readVariable("VarPlayer", "ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS",
        ValueType.INTEGER, "current value")
    if status then return failure(result, status, detail) end
    if current < 0 or current > maximum then return failure(result, "Invalid current/max range") end

    local name
    name, status, detail = readVariable("VarClient", "ACTIVITY_PROGRESS_BAR_ACTIVE_NAME",
        ValueType.STRING, "activity name")
    if status then return failure(result, status, detail) end
    if #name > 160 then return failure(result, "Activity name too long") end
    name = name:gsub("<[^>]*>", ""):gsub("[<>]", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then result.status = "Inactive: no active name"; return result end

    result.name, result.current, result.maximum = name, current, maximum
    result.valid = true
    result.status = "Active activity - UI " .. uiState
    return result
end

return HealthProbe
