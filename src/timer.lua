local Timer = {}

-- Default math is checked against the frozen tests/reference/timer.ts oracle.
Timer.sections = {
    { label = "pre-ult", duration = 14.4, step = 0.6 },
    { label = "ult", duration = 0.6, step = 0.1 },
    { label = "post-ult", duration = 8.4, step = 0.6 },
    { label = "tc", duration = 0.6, step = 0.1 },
}

Timer.totalTime = 0
for _, section in ipairs(Timer.sections) do
    Timer.totalTime = Timer.totalTime + section.duration
end
Timer.resetDelay = 1

function Timer.sanitisePercentage(value)
    return math.min(100, math.max(0, value))
end

function Timer.activeSection(remaining)
    local accumulated = 0
    for i = #Timer.sections, 1, -1 do
        accumulated = accumulated + Timer.sections[i].duration
        if remaining <= accumulated then
            return Timer.sections[i]
        end
    end
    return Timer.sections[1]
end

function Timer.snapRemainingSeconds(rawSeconds, smoothCountdown)
    local seconds = math.max(0, rawSeconds)
    local section = seconds <= 0 and Timer.sections[1] or Timer.activeSection(seconds)
    local step = smoothCountdown == true and 0.1 or section.step
    return math.floor(seconds / step + 1e-9) * step
end

function Timer.sectionPercentages(seconds)
    local elapsed = Timer.totalTime - seconds
    local sectionStart = 0
    local percentages = {}
    for i, section in ipairs(Timer.sections) do
        percentages[i] = Timer.sanitisePercentage((elapsed - sectionStart) / section.duration * 100)
        sectionStart = sectionStart + section.duration
    end
    return percentages
end

function Timer.new()
    return { phase = "idle", elapsed = 0 }
end

function Timer.start(state)
    state.phase = "running"
    state.elapsed = 0
end

function Timer.reset(state)
    state.phase = "idle"
    state.elapsed = 0
end

-- Delta time, not frame/tick counts: a slow draw must not stretch the timer.
function Timer.update(state, deltaSeconds)
    assert(type(deltaSeconds) == "number" and deltaSeconds >= 0 and deltaSeconds < math.huge,
        "VoragoSync: frame delta must be a finite non-negative number")
    if state.phase == "idle" then
        return
    end

    state.elapsed = state.elapsed + deltaSeconds
    if state.phase == "running" then
        if state.elapsed >= Timer.totalTime then
            state.phase = "complete"
            -- As in Alt1, show full bars for a second after completion is observed.
            state.elapsed = Timer.totalTime
        end
    elseif state.elapsed >= Timer.totalTime + Timer.resetDelay then
        Timer.reset(state)
    end
end

function Timer.display(state, smoothCountdown)
    if state.phase == "idle" then
        return 0, { 0, 0, 0, 0 }
    end
    local remaining = Timer.snapRemainingSeconds(Timer.totalTime - state.elapsed, smoothCountdown)
    return remaining, Timer.sectionPercentages(remaining)
end

return Timer
