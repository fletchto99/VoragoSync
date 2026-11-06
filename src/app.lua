local Timer = require("src/timer")
local HealthProbe = require("src/health_probe")
local Detector = require("src/detector")
local Encounter = require("src/encounter")
local Build = require("src/build")

local App = {}

function App.start()
    assert(type(Build.isDevBuild) == "boolean", "VoragoSync: build.isDevBuild must be a boolean")
    assert(type(prettyui) == "table" and type(prettyui.Window) == "table"
        and type(prettyui.Window.new) == "function" and type(prettyui.Window.AddText) == "function"
        and type(prettyui.SimpleView) == "table" and type(prettyui.SimpleView.new) == "function"
        and type(prettyui.SimpleView.AddCheckboxButton) == "function",
        "VoragoSync requires PrettyUI (mod.io 6398181); install it and refresh plugin.json dependencies")

    local settingOptions = {
        { key = "smoothCountdown", label = "Smooth countdown" },
        { key = "removeBarSections", label = "Remove bar sections" },
        { key = "onlyInArena", label = "Only show in Vorago arena" },
    }
    if Build.isDevBuild then
        settingOptions[#settingOptions + 1] = { key = "debugMode", label = "Debug mode" }
    end
    local preferences, allowedSettings = { debugMode = false }, {}
    for _, option in ipairs(settingOptions) do
        allowedSettings[option.key] = true
        preferences[option.key] = PersistentDB:GetBool(option.key) == true
    end

    local state = Timer.new()
    local detector = Detector.new()
    local sinceSample = Detector.pollInterval
    local latestReading = nil
    local latestEncounter, encounterIdentity = nil, nil
    local lastMonitorError = nil
    local visibilityGraceRemaining, visibilityWasActive = 0, false
    local visibilityGraceSeconds = 5
    local fadeSeconds = 1
    local view, settingsView = nil, nil
    local inGame, waitingForUI = true, false
    local notice = ""
    local eventRef = "VoragoSync"
    local contentWidth, compactHeight, debugHeight = 500, 72, 150

    local function report(message)
        notice = message
        print("[VoragoSync] " .. message)
    end

    local function resetDetection()
        Detector.reset(detector)
        sinceSample = Detector.pollInterval
        latestReading, lastMonitorError = nil, nil
        latestEncounter, encounterIdentity = nil, nil
        visibilityGraceRemaining, visibilityWasActive = 0, false
    end

    local function startCountdown(reason)
        if state.phase ~= "idle" then return end
        Detector.reset(detector)
        Timer.start(state)
        print("[VoragoSync] " .. reason .. ": started 24-second countdown.")
    end

    local function monitor(deltaSeconds)
        sinceSample = sinceSample + deltaSeconds
        if sinceSample < Detector.pollInterval then return end
        local gap = sinceSample
        sinceSample = 0
        latestEncounter = Encounter.read()
        latestReading = HealthProbe.read()
        local failed = latestEncounter.error and latestEncounter or (latestReading.error and latestReading or nil)
        if failed then
            local source = latestEncounter.error and "Encounter" or "Activity"
            local message = source .. " monitoring error: " .. failed.status .. (failed.detail and (": " .. failed.detail) or "")
            if message ~= lastMonitorError then
                print("[VoragoSync] " .. message)
                lastMonitorError = message
            end
        else
            lastMonitorError = nil
        end
        if not latestEncounter.valid then
            Detector.reset(detector)
            encounterIdentity = nil
            return
        end
        if encounterIdentity ~= latestEncounter.identity then
            Detector.reset(detector)
            encounterIdentity = latestEncounter.identity
        end
        local busy = state.phase ~= "idle"
        local hpEdge = Detector.observe(detector, latestReading, busy, gap)
        local scopEdge = Detector.observeScop(detector, latestEncounter, busy, gap)
        if hpEdge or scopEdge then
            local reason = hpEdge and "Vorago positive HP -> 0" or "Scopulus presence -> absence (heuristic)"
            if hpEdge and scopEdge then reason = reason .. " + Scopulus absence" end
            startCountdown(reason)
        end
    end

    local function own(widget)
        local root = widget.root
        return {
            widget = widget,
            interfaceID = root.interfaceID, staticID = root.staticID,
            categoryID = root.categoryID, dynamicID = root.dynamicID,
        }
    end

    local function liveRoot(owner)
        if owner == nil then return nil end
        return ui.Interfaces:GetComponent(owner.interfaceID, owner.staticID, owner.categoryID, owner.dynamicID)
    end

    local function destroyView()
        local old = view
        view = nil
        if old then old.widget:Destroy() end
    end

    local function destroySettings()
        local old = settingsView
        settingsView = nil
        if old then old.widget:Destroy() end
    end

    local function checkContentHost(widget)
        -- PrettyUI 1.2.0 has no NewComponent/auto allocator. Raw bars need category 0.
        if widget.content.categoryID ~= 0 then
            widget:Destroy()
            error("VoragoSync requires a category-zero PrettyUI content host (verified with 1.2.0)")
        end
    end

    local function text(widget, value, x, y, width, height, colour)
        return widget:AddText({
            text = value, x = x, y = y, width = width, height = height,
            alignHorizontal = ui.AlignMode.CENTRE, maxLines = 1, colour = colour,
        })
    end

    local function rectangle(parent, x, y, width, colour)
        local component = ui.Rectangle.new(parent)
        component:SetPos(x, y)
        component:SetSize(width, 28)
        component.colour, component.fill = colour, true
        return component
    end

    local function createView(parent)
        local height = preferences.debugMode and debugHeight or compactHeight
        local widget = prettyui.Window.new(parent, {
            x = -258, y = 0, xAnchor = 0.5, yAnchor = 0.35,
            width = contentWidth + 16, height = height + 16, minHeight = 60,
            scrollable = false, resizable = false, contentHeight = height, layout = { padding = 0 },
        })
        checkContentHost(widget)
        -- 1.2.0 creates this even without a title; it has no hideCloseButton option.
        if widget.closeButton == nil then
            widget:Destroy()
            error("VoragoSync requires PrettyUI's closeButton handle to disable closing the timer")
        end
        widget.closeButton.hidden, widget.closeButton.enabled, widget.closeButton.clickthrough = true, false, true
        view = own(widget)
        view.opacity, widget.root.alpha = 0, 0
        view.sections = {}
        view.countdown = text(widget, "0.0s", 10, 10, 70, 28)
        local background = Vector4.new(0.06, 0.05, 0.03, 1)
        local accent = Vector4.new(0.83, 0.60, 0.10, 1)
        local widths, x = { 160, 54, 116, 54 }, 88
        for i, section in ipairs(Timer.sections) do
            view.sections[i] = {
                background = rectangle(widget.content, x, 10, widths[i], background),
                fill = rectangle(widget.content, x, 10, 0, accent),
                label = text(widget, section.label, x, 10, widths[i], 28, 0xFFFFFFFF),
                width = widths[i],
            }
            x = x + widths[i] + 6
        end
        view.barWidth = x - 88 - 6
        view.uniformBackground = rectangle(widget.content, 88, 10, view.barWidth, background)
        view.uniformFill = rectangle(widget.content, 88, 10, 0, accent)
        view.error = text(widget, "", 10, 44, 480, 24, 0xFFB0A8FF)
        view.activity = text(widget, "", 10, 74, 480, 22)
        view.hp = text(widget, "", 10, 98, 480, 22)
        view.armed = text(widget, "", 10, 122, 480, 22)
    end

    local function showSettings(event)
        destroySettings()
        local parent = event.component
        local widget = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
        checkContentHost(widget)
        local owner = own(widget)
        settingsView = owner
        widget:AddTitle("VoragoSync display")
        local choices = {}
        for _, option in ipairs(settingOptions) do
            choices[#choices + 1] = { text = option.label, value = option.key, selected = preferences[option.key] }
        end
        widget:AddCheckboxButton(choices, {
            onChange = function(_, _, key, selected)
                if settingsView ~= owner then return end
                if not allowedSettings[key] or type(selected) ~= "boolean" then
                    report("Invalid display setting.")
                    return
                end
                preferences[key] = selected
                if not PersistentDB:SetBool(key, selected) then
                    report("Display setting was not saved.")
                    owner.message.content = "The change applies for this session, but could not be saved."
                else
                    notice = ""
                    owner.message.content = ""
                end
            end,
        })
        owner.message = widget:AddText({ text = "", height = 48, maxLines = 2 })
    end

    local function displayNumber(value)
        if value == nil then return "--" end
        return (string.format("%.0f", value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end

    local function armedStatus()
        if state.phase ~= "idle" then return "Armed: no - countdown/hold active" end
        if latestEncounter and not latestEncounter.valid then return "Armed: no - " .. latestEncounter.status end
        if detector.scop then
            return "Armed: " .. (detector.positive and "HP + " or "") .. "Scopulus (" .. latestEncounter.scopCount .. " present)"
        end
        if detector.positive then return "Armed: Vorago HP" end
        return "Armed: no - waiting for a fresh observation"
    end

    local function render(deltaSeconds)
        local active = state.phase ~= "idle"
            or (latestReading ~= nil and latestReading.valid and latestReading.name:lower() == "vorago")
        -- Start a full grace period when inactivity is observed, including after a long frame.
        if active or visibilityWasActive then
            visibilityGraceRemaining = visibilityGraceSeconds
        else
            visibilityGraceRemaining = math.max(0, visibilityGraceRemaining - deltaSeconds)
        end
        visibilityWasActive = active
        local targetHidden = preferences.onlyInArena and visibilityGraceRemaining == 0
        if view.targetHidden ~= targetHidden then
            view.targetHidden = targetHidden
        else
            local direction = targetHidden and -1 or 1
            local opacity = math.max(0, math.min(1, view.opacity + direction * deltaSeconds / fadeSeconds))
            if view.opacity ~= opacity then
                view.widget.root.alpha, view.opacity = opacity, opacity
            end
        end
        local hidden = targetHidden and view.opacity == 0
        if view.hidden ~= hidden then
            view.widget.root.hidden, view.hidden = hidden, hidden
        end
        if view.debugMode ~= preferences.debugMode then
            view.debugMode = preferences.debugMode
            view.activity.hidden, view.hp.hidden, view.armed.hidden = not view.debugMode, not view.debugMode, not view.debugMode
            view.widget:SetSize(contentWidth + 16, (view.debugMode and debugHeight or compactHeight) + 16)
        end
        if view.removeSections ~= preferences.removeBarSections then
            view.removeSections = preferences.removeBarSections
            for _, section in ipairs(view.sections) do
                section.background.hidden, section.fill.hidden, section.label.hidden = view.removeSections, view.removeSections, view.removeSections
            end
            view.uniformBackground.hidden, view.uniformFill.hidden = not view.removeSections, not view.removeSections
        end

        local remaining, percentages = Timer.display(state, preferences.smoothCountdown)
        local countdown = string.format("%.1fs", remaining)
        if countdown ~= view.lastText then
            view.countdown.content, view.lastText = countdown, countdown
        end
        for i, section in ipairs(view.sections) do
            local width = math.floor(section.width * percentages[i] / 100 + 0.5)
            if section.lastWidth ~= width then
                section.fill:SetWidth(width)
                section.lastWidth = width
            end
        end
        local uniformWidth = state.phase == "idle" and 0
            or math.floor(view.barWidth * math.min(1, state.elapsed / Timer.totalTime) + 0.5)
        if uniformWidth ~= view.lastUniformWidth then
            view.uniformFill:SetWidth(uniformWidth)
            view.lastUniformWidth = uniformWidth
        end
        if view.debugMode then
            local activity = "Activity: " .. (latestReading and latestReading.name or "--")
            local hp = "Current HP: " .. displayNumber(latestReading and latestReading.current)
            local armed = armedStatus()
            if activity ~= view.lastActivity then view.activity.content, view.lastActivity = activity, activity end
            if hp ~= view.lastHP then view.hp.content, view.lastHP = hp, hp end
            if armed ~= view.lastArmed then view.armed.content, view.lastArmed = armed, armed end
        end
        local failed = latestEncounter and latestEncounter.error and latestEncounter
            or (latestReading and latestReading.error and latestReading or nil)
        local message = notice ~= "" and notice or (failed and ("Monitor: " .. failed.status) or "")
        if message ~= view.lastError then
            view.error.content, view.lastError = message, message
            view.error.hidden = message == ""
        end
    end

    Event.SettingsLayerReady.Subscribe(eventRef, showSettings)
    Event.Draw.Subscribe(eventRef, function(event)
        if settingsView and liveRoot(settingsView) == nil then destroySettings() end
        if not inGame then return end
        if view and liveRoot(view) == nil then
            if state.phase == "running" then print("[VoragoSync] Countdown cancelled: plugin UI unloaded.") end
            Timer.reset(state)
            resetDetection()
            destroyView()
        end
        if view == nil then
            local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
            if parent == nil then
                if not waitingForUI then
                    print("[VoragoSync] Waiting for the in-game plugin UI layer.")
                    waitingForUI = true
                end
                return
            end
            createView(parent)
            waitingForUI = false
        end
        Timer.update(state, event.timeDeltaSecs)
        monitor(event.timeDeltaSecs)
        render(event.timeDeltaSecs)
    end)

    Event.GameStateChanged.Subscribe(eventRef, function(event)
        inGame = event.newState == GameState.GAME
        if not inGame then
            if state.phase == "running" then
                print("[VoragoSync] Countdown cancelled: left active game state (" .. tostring(event.newState) .. ").")
            end
            Timer.reset(state)
            resetDetection()
            destroyView()
            destroySettings()
        end
    end)

    local function shutdown()
        Event.Draw.Unsubscribe(eventRef)
        Event.GameStateChanged.Unsubscribe(eventRef)
        Event.SettingsLayerReady.Unsubscribe(eventRef)
        Timer.reset(state)
        resetDetection()
        destroyView()
        destroySettings()
    end

    print("[VoragoSync] PrettyUI " .. tostring(prettyui.version) .. " loaded.")
    return shutdown
end

return App
