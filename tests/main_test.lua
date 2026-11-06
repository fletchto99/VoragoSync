-- Contract double for the documented host APIs, not an in-game UI test.
local components, subscriptions, messages = {}, {}, {}
local nextID, queryCount, activityQueries, scopQueries = 0, 0, 0, 0
local rootAvailable, activityUIAvailable = false, true
local storedPreferences, preferenceReads, writes = {}, {}, {}
local saveOK = true
PersistentDB = {
    GetBool = function(_, key)
        assert(key == "debugMode" or key == "smoothCountdown" or key == "removeBarSections")
        preferenceReads[key] = (preferenceReads[key] or 0) + 1
        return type(storedPreferences[key]) == "boolean" and storedPreferences[key] or nil
    end,
    SetBool = function(_, key, value)
        assert(type(value) == "boolean")
        writes[#writes + 1] = { key = key, value = value }
        if saveOK then storedPreferences[key] = value end
        return saveOK
    end,
}
local bossNPC = { isValid = true, displayName = "Vorago", uid = 1, configID = 1, isMultiNPC = false }
local npcs, scopNpcs = { bossNPC }, {}
local originalPrint = print
print = function(message) messages[#messages + 1] = message end

local Timer = require("timer")
local originalStart = Timer.start
local Detector = require("detector")
local originalNewDetector, detectorState = Detector.new, nil
Detector.new = function()
    detectorState = originalNewDetector()
    return detectorState
end
local starts, lastTimerState = 0, nil
Timer.start = function(state)
    assert(detectorState.scop == nil and detectorState.positive == nil, "shared start must clear both latches")
    starts, lastTimerState = starts + 1, state
    originalStart(state)
end

local function hasMessage(part)
    for _, message in ipairs(messages) do
        if message:find(part, 1, true) then return true end
    end
    return false
end

id = {
    Component = {
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 100,
        ACTIVITY_PROGRESS_BAR__CONTAINER = 76742679,
        ACTIVITY_PROGRESS_BAR__PROGRESS_BAR = 76742671,
        ACTIVITY_PROGRESS_BAR__ACTIVITY_NAME_TEXT = 76742682,
    },
    StyleSheet = { DEFAULT = 1, BUTTON_DEFAULT = 2 },
    Font = { MUSEO_SANS_15PT_REGULAR = 3 },
}
Vector4 = { new = function(...) return { ... } end }
GameState = { GAME = 30, LOBBY = 20, RECONNECTING = 35, LOADING = 40 }
ValueType = { INTEGER = 0, STRING = 36 }
var = {
    VarPlayer = {
        LIFEPOINTS = { typeName = "VarPlayer", valueType = 0, value = 10000 },
        ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS = { typeName = "VarPlayer", valueType = 0, value = 0 },
        ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS = { typeName = "VarPlayer", valueType = 0, value = 250000 },
        ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = { typeName = "VarPlayer", valueType = 0, value = 0 },
    },
    VarClient = {
        ACTIVITY_PROGRESS_BAR_ACTIVE_NAME = { typeName = "VarClient", valueType = 36, value = "Vorago" },
    },
}
NPCList = { ByName = function(name)
    if name == "Vorago" then
        queryCount = queryCount + 1
        return npcs
    end
    assert(name == "*Scopul*")
    scopQueries = scopQueries + 1
    return scopNpcs
end }

Event = {}
for _, name in ipairs({ "Draw", "GameStateChanged", "SettingsLayerReady" }) do
    subscriptions[name] = {}
    Event[name] = {
        Subscribe = function(ref, callback) subscriptions[name][ref] = callback end,
        Unsubscribe = function(ref) subscriptions[name][ref] = nil end,
    }
end
local function emit(name, payload)
    for _, callback in pairs(subscriptions[name]) do callback(payload) end
end
local function draw(delta)
    emit("Draw", { timeDeltaSecs = delta })
end

local pluginRoot = {
    type = 20, interfaceID = 1, staticID = 2, categoryID = -1, dynamicID = -1,
    visibleGlobal = true, alpha = 1, isRestricted = false, width = 1920, height = 1080,
}
local settingsParent = {
    interfaceID = 1, staticID = 3, categoryID = -1, dynamicID = -1, width = 480, height = 320,
}
local bossRoot = {
    type = 20, interfaceID = 99, staticID = 1, categoryID = -1, dynamicID = -1,
    visibleGlobal = true, alpha = 1, isRestricted = false,
}
local hp = {
    type = 7, interfaceID = 99, staticID = 2, categoryID = -1, dynamicID = -1,
    visibleGlobal = true, alpha = 1, isRestricted = false, isMouseOver = true,
    parent = bossRoot, content = "123",
}

local function newComponent(kind, parent)
    assert(parent ~= nil)
    nextID = nextID + 1
    local component = {
        kind = kind, parent = parent, alive = true, hooks = {},
        interfaceID = parent.interfaceID, staticID = parent.staticID,
        categoryID = parent.categoryID >= 0 and parent.categoryID or 0, dynamicID = nextID,
        hidden = false, enabled = true,
    }
    function component:SetPos(x, y)
        assert(self.alive and math.type(x) == "integer" and math.type(y) == "integer")
        self.x, self.y = x, y
    end
    function component:SetSize(width, height)
        assert(self.alive and math.type(width) == "integer" and math.type(height) == "integer")
        self.width, self.height = width, height
    end
    function component:SetWidth(width)
        assert(self.alive and math.type(width) == "integer")
        self.width = width
    end
    function component:SetHeaderLayout() assert(self.alive) end
    function component:AlignTo() assert(self.alive) end
    function component:Subscribe(hook, callback) self.hooks[hook] = callback end
    function component:Destroy()
        assert(self.alive, "must not destroy stale components")
        self.alive = false
        for _, child in ipairs(components) do
            if child.parent == self and child.alive then child:Destroy() end
        end
    end
    components[#components + 1] = component
    return component
end

ui = {
    Hook = { ONBUTTONPRESSED = 1 },
    AlignMode = { CENTRE = 1 },
    ComponentType = {
        LAYER = 20, PANEL = 2, GRID = 3, PAGED_LAYER = 4, PAGED_CAROUSEL = 5,
        GROUP_BOX = 6, LABEL = 7, RECTANGLE = 8, SPRITE = 9, INPUTFIELD = 10, CUTSCENE_LAYER = 11,
    },
    Interfaces = { GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
        if staticID == nil then
            if interfaceID == id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP then
                return rootAvailable and pluginRoot or nil
            end
            assert(interfaceID == 76742679 or interfaceID == 76742671 or interfaceID == 76742682)
            activityQueries = activityQueries + 1
            return activityUIAvailable and (interfaceID == 76742682 and hp or bossRoot) or nil
        end
        local component = components[dynamicID]
        if component then
            assert(interfaceID == component.interfaceID and staticID == component.staticID and categoryID == component.categoryID)
        end
        return component and component.alive and component or nil
    end, GetInterface = function(_, interfaceID)
        assert(interfaceID == 1)
        return rootAvailable and {} or nil
    end },
}
for _, kind in ipairs({ "GroupBox", "Text", "Rectangle", "Button" }) do
    ui[kind] = { new = function(parent) return newComponent(kind, parent) end }
end

-- Only the installed 1.2.0 API is mocked: no NewComponent, auto IDs, or hideCloseButton option.
local widgets, timerWidget, settingsWidget = {}, nil, nil
local forceContentCategory = nil
local Widget = {}
function Widget:AddText(value)
    local options = type(value) == "table" and value or { text = value }
    local label = newComponent("Text", self.content)
    local height = options.height or 24
    label:SetPos(options.x or 0, options.y or self.nextY)
    label:SetSize(options.width or self.content.width, height)
    label.content, label.maxLines = options.text or "", options.maxLines
    label.prettyOptions = options
    if options.y == nil then self.nextY = self.nextY + height + 4 end
    return label
end
function Widget:AddTitle(value)
    assert(value == "VoragoSync display")
    self.titleCalls = self.titleCalls + 1
    return self:AddText(value)
end
function Widget:AddCheckboxButton(choices, options)
    local control = { choices = choices, options = options, selected = {} }
    for _, choice in ipairs(choices) do control.selected[choice.value] = choice.selected end
    function control:SetSelected(key, selected)
        if self.selected[key] == nil then return false end
        if self.selected[key] == selected then return true end
        self.selected[key] = selected
        self.options.onChange(self, {}, key, selected)
        return true
    end
    self.checkbox = control
    self.nextY = self.nextY + #choices * 28
    return control
end
function Widget:SetSize(width, height)
    self.root:SetSize(width, height)
    local inset = self.kind == "Window" and 16 or 0
    self.content:SetSize(width - inset, height - inset)
end
function Widget:Destroy()
    self.destroyCalls = self.destroyCalls + 1
    assert(self.destroyCalls == 1, "destroy each PrettyUI wrapper exactly once")
    if self.root.alive then self.root:Destroy() end
end
local function widget(kind, parent, options)
    assert(options.categoryID == nil and options.hideCloseButton == nil, "do not assume newer PrettyUI APIs")
    local result = setmetatable({
        kind = kind, root = newComponent("Layer", parent), nextY = 0, titleCalls = 0, destroyCalls = 0,
    }, { __index = Widget })
    result.content = newComponent("Layer", result.root)
    if forceContentCategory then result.content.categoryID = forceContentCategory end
    result:SetSize(options.width, options.height)
    result.root:SetPos(options.x or 0, options.y or 0)
    if kind == "Window" then
        assert(options.title == nil and options.scrollable == false and options.resizable == false)
        result.closeButton = newComponent("CloseControl", result.root)
        timerWidget = result
    else
        assert(parent == settingsParent)
        settingsWidget = result
    end
    widgets[#widgets + 1] = result
    return result
end
prettyui = {
    version = "1.2.0",
    Window = { new = function(parent, options) return widget("Window", parent, options) end, AddText = Widget.AddText },
    SimpleView = {
        new = function(parent, options) return widget("SimpleView", parent, options) end,
        AddCheckboxButton = Widget.AddCheckboxButton,
    },
}

local function find(kind, value)
    for _, component in ipairs(components) do
        if component.alive and component.kind == kind
            and (component.label == value or component.content == value) then
            return component
        end
    end
    error("missing " .. kind .. ": " .. value)
end
local function debugLabel(y)
    for _, component in ipairs(components) do
        if component.alive and component.kind == "Text" and component.parent == timerWidget.content and component.y == y then
            return component
        end
    end
    error("debug label missing at " .. y)
end
local function rectangles()
    local result = {}
    for _, component in ipairs(components) do
        if component.alive and component.kind == "Rectangle" and component.parent == timerWidget.content then
            result[#result + 1] = component
        end
    end
    return result
end
local function openSettings()
    emit("SettingsLayerReady", { component = settingsParent })
    return settingsWidget
end
local function setting(key, value)
    if not settingsWidget or settingsWidget.destroyCalls > 0 then openSettings() end
    assert(settingsWidget.checkbox:SetSelected(key, value))
    draw(0)
end
local function checkLayout(expectedCountdown, emptyBars)
    local countdown = find("Text", expectedCountdown or "0.0s")
    local firstBar = find("Text", "pre-ult")
    local lastBar = find("Text", "tc")
    assert(countdown.y == firstBar.y and countdown.height == firstBar.height)
    assert(countdown.x + countdown.width < firstBar.x, "countdown must be left of the bar")
    assert(lastBar.x + lastBar.width == 490, "bar must fit the panel")
    assert(countdown.y == 10 and timerWidget.titleCalls == 0, "no overlay heading above the timer row")
    assert(timerWidget.closeButton.hidden and not timerWidget.closeButton.enabled)
    assert(timerWidget.content.categoryID == 0)
    for _, component in ipairs(components) do
        if component.alive and component.kind == "Button" then
            error("diagnostic/manual buttons must not exist")
        end
        if emptyBars ~= false and component.alive and component.kind == "Rectangle" and component.colour[1] == 0.83 then
            assert(component.width == 0)
        end
    end
end

local currentVar = var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS
local maxVar = var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS
local hideVar = var.VarPlayer.ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS
local nameVar = var.VarClient.ACTIVITY_PROGRESS_BAR_ACTIVE_NAME
local lifeVar = var.VarPlayer.LIFEPOINTS
local function defaults()
    var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = currentVar
    currentVar.value, currentVar.valueType, currentVar.typeName = 0, ValueType.INTEGER, "VarPlayer"
    maxVar.value, hideVar.value, nameVar.value = 250000, 0, "Vorago"
    activityUIAvailable, bossRoot.visibleGlobal, hp.visibleGlobal = true, true, true
    bossRoot.isRestricted, hp.isRestricted, hp.type = false, false, 7
    lifeVar.value, lifeVar.valueType = 10000, ValueType.INTEGER
    bossNPC.uid, bossNPC.isValid = 1, true
    npcs, scopNpcs = { bossNPC }, {}
end
local function reenter()
    defaults()
    emit("GameStateChanged", { newState = GameState.LOBBY })
    emit("GameStateChanged", { newState = GameState.GAME })
    draw(0.05)
end
local function observe(value)
    currentVar.value = value
    draw(0.05)
end
local function close(actual, expected)
    assert(math.abs(actual - expected) < 1e-8, tostring(actual) .. " ~= " .. expected)
end
local function countMessages(part)
    local count = 0
    for _, message in ipairs(messages) do
        if message:find(part, 1, true) then count = count + 1 end
    end
    return count
end

local library = prettyui
prettyui = nil
local loaded, missingDependency = pcall(dofile, "main.lua")
assert(not loaded and tostring(missingDependency):find("PrettyUI", 1, true))
assert(#widgets == 0 and next(preferenceReads) == nil, "missing dependency must fail before setup")
prettyui = library
dofile("main.lua")
for _, callbacks in pairs(subscriptions) do assert(callbacks.VoragoSync ~= nil) end
assert(hasMessage("[VoragoSync] PrettyUI 1.2.0 loaded."))
draw(0.02)
assert(hasMessage("Waiting for the in-game"))
rootAvailable = true
draw(0.02)
checkLayout()
assert(queryCount == 1 and scopQueries == 1 and activityQueries == 3, "encounter monitoring is automatic")
assert(timerWidget.root.height == 88)
assert(debugLabel(74).hidden and debugLabel(98).hidden and debugLabel(122).hidden)
assert(preferenceReads.debugMode == 1)
for _ = 1, 20 do draw(0.05) end
assert(starts == 0, "enabling at zero must not start")
openSettings()
assert(#settingsWidget.checkbox.choices == 3)
assert(not settingsWidget.checkbox.selected.debugMode)
setting("debugMode", true)
assert(storedPreferences.debugMode and timerWidget.root.height == 166)
find("Text", "Activity: Vorago")
find("Text", "Current HP: 0")
assert(not debugLabel(74).hidden)
local beforeSharedRead = activityQueries
draw(0.1)
assert(activityQueries == beforeSharedRead + 3, "passive debug must not add polling")
assert(starts == 0)
draw(46)
assert(not debugLabel(74).hidden, "debug readouts have no 45-second timeout")

observe(250000)
find("Text", "Armed: Vorago HP")
observe(0)
assert(starts == 1 and lastTimerState.phase == "running")
close(lastTimerState.elapsed, 0)
checkLayout("24.0s", false)
draw(0.5)
assert(starts == 1)
draw(9.5)
close(lastTimerState.elapsed, 10)
bossRoot.visibleGlobal = false
draw(2)
assert(lastTimerState.phase == "running", "boss-bar disappearance must NOT cancel the timer")
assert(not hasMessage("Countdown cancelled"), "ordinary bar loss is not a lifecycle cancellation")
close(lastTimerState.elapsed, 12)
find("Text", "12.0s")
activityUIAvailable, hideVar.value = false, 1
npcs = {}
draw(5)
assert(lastTimerState.phase == "running")
draw(7)
assert(lastTimerState.phase == "complete" and starts == 1)
draw(1.01)
assert(lastTimerState.phase == "idle")
defaults()
draw(0.05)
checkLayout()
assert(starts == 1, "bar returning at zero must not restart")

observe(200000)
observe(0)
assert(starts == 2)
observe(1000)
observe(0)
assert(starts == 2, "a zero during the active run is consumed, not restarted or queued")
draw(24)
draw(1.01)
assert(starts == 2 and lastTimerState.phase == "idle")
observe(25)
observe(0)
assert(starts == 3)
draw(24)
assert(lastTimerState.phase == "complete")
observe(25)
observe(0)
assert(starts == 3, "an edge during the completed-bar hold must be consumed, not started")
draw(0.95)
assert(lastTimerState.phase == "idle" and starts == 3, "no queued edge after the hold")
observe(25)
observe(0)
assert(starts == 4)
draw(0.95)
assert(lastTimerState.phase == "running")
close(lastTimerState.elapsed, 0.95)

reenter()
local baseline = starts
setting("debugMode", false)
draw(46)
checkLayout()
local readsAfterStop = activityQueries
draw(0.05)
assert(activityQueries > readsAfterStop, "monitoring continues with debug disabled")
observe(20)
observe(0)
assert(starts == baseline + 1)
local elapsedBeforeDebug = lastTimerState.elapsed
setting("debugMode", true)
assert(starts == baseline + 1 and lastTimerState.elapsed == elapsedBeforeDebug)

-- Invalid/lost/changed observations break the edge; none is interpreted as zero.
local invalidCases = {
    function() var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS = nil end,
    function() currentVar.value = nil end,
    function() currentVar.valueType = ValueType.STRING end,
    function() currentVar.value = "0" end,
    function() currentVar.value = -1 end,
    function() currentVar.value = 250001 end,
    function() hideVar.value = 1 end,
    function() maxVar.value = 0 end,
    function() nameVar.value = "" end,
    function() nameVar.value = "Other activity" end,
    function() bossRoot.visibleGlobal = false end,
    function() bossRoot.isRestricted = true end,
    function() activityUIAvailable = false end,
}
for _, invalidate in ipairs(invalidCases) do
    reenter()
    baseline = starts
    observe(100)
    invalidate()
    draw(0.05)
    defaults()
    draw(0.05)
    assert(starts == baseline, "uncertain history must not create a zero edge")
    observe(100)
    observe(0)
    assert(starts == baseline + 1, "fresh valid positive/zero must rearm")
end
reenter()
observe(100)
baseline = starts
hp.visibleGlobal, currentVar.value = false, 0
draw(0.05)
assert(starts == baseline + 1, "optional child visibility at zero must not suppress the confirmed variable edge")
reenter()
observe(100)
baseline = starts
maxVar.value, currentVar.value = 100000, 0
draw(0.05)
assert(starts == baseline, "maximum changing on the zero sample must not trigger")
reenter()
observe(100)
currentVar.value = 0
draw(1)
assert(starts == baseline, "a long observation gap must not generate a late edge")
observe(100)
observe(0)
assert(starts == baseline + 1)

reenter()
observe(100)
local errorPrefix = "Activity monitoring error: Type error: current value"
local errorCount = countMessages(errorPrefix)
currentVar.valueType = ValueType.STRING
setting("debugMode", false)
for _ = 1, 20 do draw(0.05) end
assert(countMessages(errorPrefix) == errorCount + 1, "persistent API errors should log once")
assert(not find("Text", "Monitor: Type error: current value").hidden, "operational errors stay visible with debug off")
assert(debugLabel(74).hidden)
setting("debugMode", true)

reenter()
observe(100)
baseline = starts
emit("GameStateChanged", { newState = GameState.RECONNECTING })
currentVar.value = 0
for _, component in ipairs(components) do assert(not component.alive) end
local readsInLobby = activityQueries
draw(30)
assert(activityQueries == readsInLobby)
emit("GameStateChanged", { newState = GameState.GAME })
draw(0.05)
assert(starts == baseline, "reconnect must discard armed history")
checkLayout()
observe(100)
observe(0)
assert(starts == baseline + 1)
emit("GameStateChanged", { newState = GameState.LOBBY })
assert(lastTimerState.phase == "idle", "leaving the game still cancels a running timer")
emit("GameStateChanged", { newState = GameState.GAME })
draw(0.05)
assert(starts == baseline + 1)

observe(100)
observe(0)
baseline = starts
for _, component in ipairs(components) do component.alive = false end
rootAvailable = false
draw(0.5)
assert(lastTimerState.phase == "idle", "plugin panel loss is a lifecycle reset, unlike boss-bar loss")
rootAvailable = true
draw(0.05)
assert(starts == baseline)
checkLayout()

-- Scop presence is encounter-scoped, has no fixed count, and shares the start path.
local scopA = { isValid = true, displayName = "Scopulus", uid = 10 }
local scopB = { isValid = true, displayName = "Scopulus", uid = 11 }
reenter()
baseline = starts
observe(250000)
scopNpcs = { scopA, scopB }
draw(0.05)
assert(detectorState.scop ~= nil)
find("Text", "Armed: HP + Scopulus (2 present)")
scopNpcs = { scopB }
draw(0.05)
find("Text", "Armed: HP + Scopulus (1 present)")
assert(starts == baseline)
scopNpcs = {}
draw(0.05)
assert(starts == baseline + 1 and detectorState.scop == nil)
assert(hasMessage("Scopulus presence -> absence (heuristic)"))
close(lastTimerState.elapsed, 0)
scopNpcs, currentVar.value = { scopA, scopB }, 100
draw(0.05)
scopNpcs, currentVar.value = {}, 0
draw(0.05)
assert(starts == baseline + 1 and detectorState.scop == nil, "active-run edges cannot restart or queue")
draw(24)
draw(1.01)
assert(starts == baseline + 1 and lastTimerState.phase == "idle")
scopNpcs, currentVar.value = { scopA, scopB }, 100
draw(0.05)
scopNpcs, currentVar.value = {}, 0
draw(0.05)
assert(starts == baseline + 2, "simultaneous HP and Scop edges start only one timer")
assert(detectorState.scop == nil)

reenter()
baseline = starts
scopNpcs = { scopA, scopB }
draw(0.05)
local beforeBothGone = scopQueries
npcs, scopNpcs = {}, {}
draw(0.05)
assert(scopQueries == beforeBothGone, "Vorago absence is checked before querying Scop disappearance")
assert(starts == baseline and detectorState.scop == nil)
npcs = { bossNPC }
draw(0.05)
assert(starts == baseline, "returning to an empty encounter is not a completion")

scopNpcs = { scopA, scopB }
draw(0.05)
lifeVar.value, scopNpcs = 0, {}
local beforeDeath = scopQueries
draw(0.05)
assert(scopQueries == beforeDeath and starts == baseline and detectorState.scop == nil,
    "death camera with Vorago still loaded must disarm before Scop absence")
lifeVar.value = 10000
draw(0.05)
assert(starts == baseline)
scopNpcs = { scopA, scopB }
draw(0.05)
lifeVar.valueType, scopNpcs = ValueType.STRING, {}
draw(0.05)
assert(starts == baseline and detectorState.scop == nil)
lifeVar.valueType = ValueType.INTEGER
draw(0.05)
assert(starts == baseline, "unavailable player health must not preserve arming")
scopNpcs = { scopA, scopB }
draw(0.05)
scopNpcs = nil
draw(0.05)
assert(starts == baseline and detectorState.scop == nil)
scopNpcs = {}
draw(0.05)
assert(starts == baseline, "failed query is not zero minions")

scopNpcs = { scopA, scopB }
currentVar.value = 100
draw(0.05)
bossNPC.uid, scopNpcs, currentVar.value = 2, {}, 0
draw(0.05)
assert(starts == baseline and detectorState.scop == nil, "encounter identity change must discard the flag")
reenter()
scopNpcs = { scopA, scopB }
draw(0.05)
emit("GameStateChanged", { newState = GameState.LOADING })
scopNpcs = {}
draw(1)
emit("GameStateChanged", { newState = GameState.GAME })
draw(0.05)
assert(starts == baseline and detectorState.scop == nil, "loading cannot carry an armed flag")

-- Accepted residual limitation: out-of-range Scops with Vorago still loaded
-- are indistinguishable from defeated Scops under the user-selected proxy.
scopNpcs = { scopA, scopB }
draw(0.05)
scopNpcs = {}
draw(0.05)
assert(starts == baseline + 1)
draw(24)
assert(lastTimerState.phase == "complete")
scopNpcs = { scopA, scopB }
draw(0.05)
scopNpcs = {}
draw(0.05)
assert(starts == baseline + 1 and detectorState.scop == nil, "full-hold edges are consumed")
draw(1)
assert(starts == baseline + 1 and lastTimerState.phase == "idle")
scopNpcs = { scopA, scopB }
draw(0.05)
scopNpcs = {}
draw(0.05)
assert(starts == baseline + 2, "a fresh observation rearms after the hold")
draw(12)
npcs = {}
draw(5)
assert(lastTimerState.phase == "running", "Vorago loss must not cancel a Scop-started timer")
close(lastTimerState.elapsed, 17)
draw(7)
draw(1.01)
assert(lastTimerState.phase == "idle")
reenter()
baseline = starts

scopNpcs, currentVar.value = { scopA, scopB }, 100
draw(0.05)
assert(detectorState.scop ~= nil)
observe(0)
assert(starts == baseline + 1 and detectorState.scop == nil,
    "an HP-only start must also clear the Scop latch while minions are still present")
reenter()
baseline = starts

-- All display settings can change mid-run without touching time or detector state.
observe(100)
observe(0)
draw(1.25)
baseline = starts
local runningWindow, elapsedBeforeSettings = timerWidget, lastTimerState.elapsed
local armedHP, armedScop = detectorState.positive, detectorState.scop
openSettings()
for _, debugMode in ipairs({ false, true }) do
    for _, smooth in ipairs({ false, true }) do
        for _, uniform in ipairs({ false, true }) do
            setting("debugMode", debugMode)
            setting("smoothCountdown", smooth)
            setting("removeBarSections", uniform)
            assert(starts == baseline and lastTimerState.elapsed == elapsedBeforeSettings)
            assert(detectorState.positive == armedHP and detectorState.scop == armedScop)
            assert(timerWidget == runningWindow and runningWindow.destroyCalls == 0)
            assert(timerWidget.root.height == (debugMode and 166 or 88))
            assert(debugLabel(74).hidden == not debugMode)
            checkLayout(smooth and "22.7s" or "22.2s", false)
            local bars = rectangles()
            assert(#bars == 10)
            for i = 1, 8 do assert(bars[i].hidden == uniform) end
            for _, name in ipairs({ "pre-ult", "ult", "post-ult", "tc" }) do
                assert(find("Text", name).hidden == uniform)
            end
            assert(bars[9].hidden == not uniform and bars[10].hidden == not uniform)
            assert(bars[9].x == 88 and bars[9].width == 402)
            assert(bars[10].x == 88 and bars[10].width == math.floor(402 * elapsedBeforeSettings / 24 + 0.5))
            assert(bars[10].colour[1] == 0.83, "uniform mode keeps the existing accent")
        end
    end
end
draw(10.75)
assert(rectangles()[10].width == 201, "uniform progress spans the full 24 seconds")
draw(12)
assert(lastTimerState.phase == "complete" and rectangles()[10].width == 402)
setting("removeBarSections", false)
assert(lastTimerState.phase == "complete" and starts == baseline)
draw(1.01)
assert(lastTimerState.phase == "idle")
checkLayout()

-- Settings remount/closure must clean the old wrapper without affecting the timer.
observe(100)
observe(0)
draw(0.3)
baseline = starts
local elapsedBeforeRemount = lastTimerState.elapsed
local oldSettings = settingsWidget
local oldCallback = oldSettings.checkbox.options.onChange
oldSettings.root:Destroy()
openSettings()
assert(oldSettings.destroyCalls == 1)
assert(lastTimerState.phase == "running" and lastTimerState.elapsed == elapsedBeforeRemount and starts == baseline)
local writeCount = #writes
oldCallback(nil, {}, "debugMode", false)
assert(#writes == writeCount, "stale settings callbacks must be ignored")
local currentSettings = settingsWidget
currentSettings.root:Destroy()
draw(0)
assert(currentSettings.destroyCalls == 1 and timerWidget.destroyCalls == 0)
assert(lastTimerState.phase == "running" and lastTimerState.elapsed == elapsedBeforeRemount)

openSettings()
saveOK = false
setting("debugMode", false)
assert(debugLabel(74).hidden)
assert(not find("Text", "Display setting was not saved.").hidden)
assert(not find("Text", "The change applies for this session, but could not be saved.").hidden)
saveOK = true
setting("smoothCountdown", false)
assert(debugLabel(44).hidden, "a successful save clears the preference error")

setting("debugMode", true)
setting("smoothCountdown", true)
setting("removeBarSections", true)
PluginShutdown()
for _, callbacks in pairs(subscriptions) do assert(next(callbacks) == nil) end
for _, component in ipairs(components) do assert(not component.alive) end
dofile("main.lua")
draw(0.05)
assert(starts == baseline, "reload at zero must not restart")
assert(timerWidget.root.height == 166 and not debugLabel(74).hidden)
assert(not rectangles()[10].hidden, "ordinary preferences are restored")
openSettings()
assert(settingsWidget.checkbox.selected.smoothCountdown and settingsWidget.checkbox.selected.removeBarSections)
PluginShutdown()

-- A release build still exposes the two ordinary settings, never Debug mode.
local Build = require("build")
Build.isDevBuild = false
local previousDebugReads = preferenceReads.debugMode
dofile("main.lua")
draw(0.05)
assert(preferenceReads.debugMode == previousDebugReads, "release mode must ignore a saved true debug preference")
assert(timerWidget.root.height == 88 and debugLabel(74).hidden and debugLabel(98).hidden and debugLabel(122).hidden)
openSettings()
assert(#settingsWidget.checkbox.choices == 2 and settingsWidget.checkbox.selected.debugMode == nil)
assert(not settingsWidget.checkbox:SetSelected("debugMode", true))
setting("smoothCountdown", false)
setting("removeBarSections", false)
checkLayout()
PluginShutdown()
Build.isDevBuild = true

-- Refuse unsafe custom bar allocation instead of using newer, absent library APIs.
forceContentCategory = 7
dofile("main.lua")
local ok, categoryError = pcall(draw, 0.05)
assert(not ok and tostring(categoryError):find("category-zero", 1, true))
assert(timerWidget.destroyCalls == 1)
PluginShutdown()
for _, widget in ipairs(widgets) do assert(widget.destroyCalls == 1) end
Timer.start = originalStart
Detector.new = originalNewDetector
print = originalPrint
print("main_test.lua: passed")
