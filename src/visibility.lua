local Visibility = {}

local graceSeconds, cooldownSeconds, fadeSeconds = 5, 10, 1

function Visibility.new()
    return {
        graceRemaining = 0, wasActive = false, cooldown = 0, needsSample = false,
        opacity = 0, wasVisible = false,
    }
end

local function resetActivity(state)
    state.graceRemaining, state.wasActive = 0, false
end

local function startCooldown(state)
    state.cooldown, state.needsSample = cooldownSeconds, true
    resetActivity(state)
end

function Visibility.unmount(state, autoHide, locked)
    resetActivity(state)
    if state.wasVisible and locked and autoHide then startCooldown(state) end
    state.opacity, state.wasVisible = 0, false
    state.hidden, state.targetHidden = nil, nil
end

function Visibility.advance(state, deltaSeconds)
    assert(type(deltaSeconds) == "number" and deltaSeconds >= 0 and deltaSeconds < math.huge,
        "VoragoSync: frame delta must be a finite non-negative number")
    state.cooldown = math.max(0, state.cooldown - deltaSeconds)
end

function Visibility.update(state, deltaSeconds, active, sampled, autoHide, locked)
    local suppressed = state.cooldown > 0 or (state.needsSample and not sampled)
    -- Observe inactivity before spending its new grace period, even after a long frame.
    if suppressed then
        resetActivity(state)
    elseif active or state.wasActive then
        state.graceRemaining = graceSeconds
    else
        state.graceRemaining = math.max(0, state.graceRemaining - deltaSeconds)
    end
    if not suppressed then state.needsSample, state.wasActive = false, active end

    local targetHidden = locked and autoHide and (suppressed or state.graceRemaining == 0)
    if not locked then
        state.targetHidden, state.opacity = false, 1
    elseif state.targetHidden ~= targetHidden then
        state.targetHidden = targetHidden
    else
        local direction = targetHidden and -1 or 1
        state.opacity = math.max(0, math.min(1, state.opacity + direction * deltaSeconds / fadeSeconds))
    end
    local hidden = targetHidden and state.opacity == 0
    if not hidden and state.opacity > 0 then state.wasVisible = true end
    if state.hidden ~= hidden then
        if hidden and state.wasVisible and autoHide and locked then startCooldown(state) end
        if hidden then state.wasVisible = false end
        state.hidden = hidden
    end
end

return Visibility
