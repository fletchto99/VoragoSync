local Detector = {}
Detector.pollInterval = 0.05
-- Do not manufacture a late edge across more than a nominal game tick.
Detector.maxObservationGap = 0.6

function Detector.new()
    return {}
end

function Detector.reset(state)
    state.positive = nil
end

local function integer(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value % 1 == 0
end

function Detector.observe(state, reading, busy, elapsedSinceSample)
    local previous = state.positive
    state.positive = nil
    if type(elapsedSinceSample) ~= "number" or elapsedSinceSample < 0
        or elapsedSinceSample >= math.huge or elapsedSinceSample ~= elapsedSinceSample then
        return false
    end
    if elapsedSinceSample > Detector.maxObservationGap then previous = nil end
    if reading == nil or reading.valid ~= true or reading.error
        or type(reading.name) ~= "string" or type(reading.uiIdentity) ~= "string"
        or not integer(reading.current) or not integer(reading.maximum)
        or reading.maximum <= 0 or reading.current < 0 or reading.current > reading.maximum then
        return false
    end
    local name = reading.name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if name ~= "vorago" then return false end

    if reading.current > 0 then
        -- Optional fill/name components can change visibility at zero HP.
        state.positive = { maximum = reading.maximum, uiIdentity = reading.uiIdentity }
        return false
    end

    -- A zero consumes the edge even during a run; it is never queued for later.
    return not busy and previous ~= nil
        and previous.maximum == reading.maximum and previous.uiIdentity == reading.uiIdentity
end

return Detector
