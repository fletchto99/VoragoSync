local Timer = require("src/timer")
local HealthProbe = require("src/health_probe")
local Detector = require("src/detector")
local Encounter = require("src/encounter")
local Build = require("src/build")
local Overlay = require("src/overlay")
local Visibility = require("src/visibility")
local UI = require("src/ui_helpers")

local App = {}

function App.start()
    assert(type(Build.isDevBuild) == "boolean", "VoragoSync: build.isDevBuild must be a boolean")
    UI.requirePrettyUI()

    local settingOptions = {
        { key = "smoothCountdown", label = "Smooth countdown" },
        { key = "removeBarSections", label = "Single-bar display" },
        { key = "onlyInArena", label = "Auto-hide when inactive" },
    }
    if Build.isDevBuild then
        settingOptions[#settingOptions + 1] = { key = "debugMode", label = "Debug mode" }
    end
    local preferences, allowedSettings = { debugMode = false }, {}
    for _, option in ipairs(settingOptions) do
        allowedSettings[option.key] = true
        preferences[option.key] = PersistentDB:GetBool(option.key) == true
    end

    local state, detector, visibility = Timer.new(), Detector.new(), Visibility.new()
    local sinceSample = Detector.pollInterval
    local latestReading, latestEncounter, encounterIdentity, lastMonitorError = nil, nil, nil, nil
    local overlay, settingsView = nil, nil
    local inGame, waitingForUI = true, false
    local eventRef = "VoragoSync"
    local notices = {}
    local noticeOrder = { "defaults", "layout", "settings", "smoothCountdown", "removeBarSections", "onlyInArena", "debugMode", "input", "cursor" }

    local function currentNotice()
        for _, key in ipairs(noticeOrder) do
            if notices[key] then return notices[key] end
        end
    end

    local function refreshSettingsMessage()
        if settingsView and settingsView.message and UI.liveRoot(settingsView) then
            local notice = currentNotice()
            local _, lockError = nil, nil
            if overlay then _, lockError = overlay.getLock() end
            local message = notice and (notice.detail or notice.message) or lockError or ""
            if message ~= settingsView.lastMessage then
                settingsView.message.content, settingsView.lastMessage = message, message
            end
        end
    end

    local function report(key, message, detail)
        notices[key] = message and { message = message, detail = detail } or nil
        if message then print("[VoragoSync] " .. message) end
        refreshSettingsMessage()
    end

    local function saveLayout(layout)
        if PersistentDB:SetStructuredData("overlayPosition", layout) then
            report("layout", nil)
        else
            report("layout", "Overlay layout was not saved.", "The layout applies for this session, but could not be saved.")
        end
    end

    overlay = Overlay.new(preferences, PersistentDB:GetStructuredData("overlayPosition"), report, saveLayout)

    local function resetDetection()
        Detector.reset(detector)
        sinceSample = Detector.pollInterval
        latestReading, latestEncounter, encounterIdentity, lastMonitorError = nil, nil, nil, nil
    end

    local function monitorFailure()
        if latestEncounter and latestEncounter.error then return latestEncounter, "Encounter" end
        if latestReading and latestReading.error then return latestReading, "Activity" end
    end

    local function monitor(deltaSeconds)
        sinceSample = sinceSample + deltaSeconds
        if sinceSample < Detector.pollInterval then return false end
        local gap = sinceSample
        sinceSample = 0
        latestEncounter, latestReading = Encounter.read(), HealthProbe.read()
        local failed, source = monitorFailure()
        if failed then
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
            return true
        end
        if encounterIdentity ~= latestEncounter.identity then
            Detector.reset(detector)
            encounterIdentity = latestEncounter.identity
        end
        if Detector.observe(detector, latestReading, state.phase ~= "idle", gap) then
            Detector.reset(detector)
            Timer.start(state)
            print("[VoragoSync] Vorago positive HP -> 0: started 24-second countdown.")
        end
        return true
    end

    local function monitoringStatus()
        if not inGame then return "Waiting for active game" end
        if not overlay.isLive() then return "Waiting for in-game UI" end
        local failed = monitorFailure()
        if failed then return "Monitoring unavailable: " .. failed.status end
        if state.phase == "running" then return "Countdown running" end
        if state.phase == "complete" then return "Countdown complete" end
        if latestEncounter and not latestEncounter.valid then
            return latestEncounter.identity == nil and "Waiting for Vorago" or ("Waiting: " .. latestEncounter.status)
        end
        if detector.positive then return "Monitoring: Vorago HP" end
        if latestReading and latestReading.valid and latestReading.name:lower() == "vorago" then
            return "Monitoring: waiting for positive Vorago HP"
        end
        return "Waiting for Vorago activity"
    end

    local function refreshSettings()
        if settingsView and UI.liveRoot(settingsView) then
            local status = "Status: " .. monitoringStatus()
            if status ~= settingsView.lastStatus then
                settingsView.status.content, settingsView.lastStatus = status, status
            end
            refreshSettingsMessage()
        end
    end

    local function destroySettings()
        local old = settingsView
        settingsView = nil
        if old then old.widget:Destroy() end
    end

    local function showSettings(event)
        destroySettings()
        local parent = event.component
        local widget = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
        UI.checkContentHost(widget)
        local owner = UI.own(widget)
        settingsView = owner
        widget:AddTitle("VoragoSync display")
        owner.status = widget:AddText({ text = "", height = 48, maxLines = 2 })
        local choices = {}
        for _, option in ipairs(settingOptions) do
            choices[#choices + 1] = { text = option.label, value = option.key, selected = preferences[option.key] }
        end
        owner.checkbox = widget:AddCheckboxButton(choices, {
            onChange = function(_, _, key, selected)
                if settingsView ~= owner or not UI.liveRoot(owner) then return end
                if not allowedSettings[key] or type(selected) ~= "boolean" then
                    report("settings", "Invalid display setting.")
                    return
                end
                preferences[key] = selected
                report("settings", nil)
                if PersistentDB:SetBool(key, selected) then
                    report(key, nil)
                else
                    report(key, "Display setting was not saved.", "The change applies for this session, but could not be saved.")
                end
            end,
        })
        widget:AddText({
            text = "Auto-hide follows boss activity, not location.\n5s hide buffer; 10s reappearance cooldown.",
            height = 48, maxLines = 2,
        })
        owner.resetLayoutButton = widget:AddSimpleButton("Reset layout", function()
            if settingsView ~= owner or not UI.liveRoot(owner) then return end
            overlay.resetLayout()
            if PersistentDB:CheckExists("overlayPosition") and not PersistentDB:Delete("overlayPosition") then
                report("layout", "Default layout could not be saved.", "The default layout applies for this session, but could not be saved.")
            else
                report("layout", nil)
            end
        end, { width = 160 })
        owner.resetButton = widget:AddSimpleButton("Reset all settings", function()
            if settingsView ~= owner or not UI.liveRoot(owner) then return end
            overlay.resetLayout()
            preferences.debugMode = false
            for _, option in ipairs(settingOptions) do
                preferences[option.key] = false
                owner.checkbox:SetSelected(option.key, false, false)
            end
            notices = {}
            if PersistentDB:Clear() then
                refreshSettingsMessage()
            else
                report("defaults", "Default settings could not be saved.", "Defaults apply for this session, but could not be saved.")
            end
        end, { width = 160 })
        owner.message = widget:AddText({ text = "", height = 48, maxLines = 2 })
        refreshSettings()
    end

    local function armedStatus()
        if state.phase ~= "idle" then return "Armed: no - countdown/hold active" end
        if latestEncounter and not latestEncounter.valid then return "Armed: no - " .. latestEncounter.status end
        if detector.positive then return "Armed: Vorago HP" end
        return "Armed: no - waiting for a fresh observation"
    end

    local function destroyOverlay()
        local locked = overlay.destroy()
        Visibility.unmount(visibility, preferences.onlyInArena, locked)
    end

    Event.SettingsLayerReady.Subscribe(eventRef, showSettings)
    Event.Draw.Subscribe(eventRef, function(event)
        local delta = event.timeDeltaSecs
        Visibility.advance(visibility, delta)
        if settingsView and UI.liveRoot(settingsView) == nil then destroySettings() end
        if not inGame then refreshSettings(); return end
        if overlay.hasView() and not overlay.isLive() then
            if state.phase == "running" then print("[VoragoSync] Countdown cancelled: plugin UI unloaded.") end
            Timer.reset(state)
            resetDetection()
            destroyOverlay()
        end
        if not overlay.hasView() then
            local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
            if parent == nil then
                if not waitingForUI then
                    print("[VoragoSync] Waiting for the in-game plugin UI layer.")
                    waitingForUI = true
                end
                refreshSettings()
                return
            end
            overlay.create(parent)
            waitingForUI = false
        end
        overlay.prepare()
        Timer.update(state, delta)
        local sampled = monitor(delta)
        local locked, lockError = overlay.getLock()
        local active = state.phase ~= "idle"
            or (latestReading ~= nil and latestReading.valid and latestReading.name:lower() == "vorago" and latestReading.current > 0)
        Visibility.update(visibility, delta, active, sampled, preferences.onlyInArena, locked)
        local notice, failed = currentNotice(), monitorFailure()
        overlay.render({
            timer = state, reading = latestReading, armed = armedStatus(), visibility = visibility,
            error = notice and notice.message or lockError or (failed and ("Monitor: " .. failed.status) or ""),
        })
        refreshSettings()
    end)

    Event.GameStateChanged.Subscribe(eventRef, function(event)
        inGame = event.newState == GameState.GAME
        if not inGame then
            if state.phase == "running" then
                print("[VoragoSync] Countdown cancelled: left active game state (" .. tostring(event.newState) .. ").")
            end
            Timer.reset(state)
            resetDetection()
            destroyOverlay()
            destroySettings()
        end
    end)

    local function shutdown()
        Event.Draw.Unsubscribe(eventRef)
        Event.GameStateChanged.Unsubscribe(eventRef)
        Event.SettingsLayerReady.Unsubscribe(eventRef)
        Timer.reset(state)
        resetDetection()
        destroyOverlay()
        destroySettings()
    end

    print("[VoragoSync] PrettyUI " .. tostring(prettyui.version) .. " loaded.")
    return shutdown
end

return App
