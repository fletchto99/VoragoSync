-- Contract double for the documented host APIs, not an in-game UI test.
local components, subscriptions, messages = {}, {}, {}
local nextID, queryCount, activityQueries = 0, 0, 0
local rootAvailable, activityUIAvailable = false, true
local storedPreferences, preferenceReads, writes = {}, {}, {}
local saveOK = true
local storedPosition, positionSaveOK, positionWrites = nil, true, {}
local clearOK, clearCalls = true, 0
PersistentDB = {
    GetBool = function(_, key)
        assert(key == "debugMode" or key == "smoothCountdown" or key == "removeBarSections" or key == "onlyInArena")
        preferenceReads[key] = (preferenceReads[key] or 0) + 1
        if type(storedPreferences[key]) == "boolean" then return storedPreferences[key] end
        return nil
    end,
    SetBool = function(_, key, value)
        assert(key ~= "lockLocation", "the plugin must not persist RuneScape's interface-lock state")
        assert(type(value) == "boolean")
        writes[#writes + 1] = { key = key, value = value }
        if saveOK then storedPreferences[key] = value end
        return saveOK
    end,
    GetStructuredData = function(_, key)
        assert(key == "overlayPosition")
        if storedPosition then
            return { x = storedPosition.x, y = storedPosition.y, width = storedPosition.width, height = storedPosition.height }
        end
        return nil
    end,
    SetStructuredData = function(_, key, value)
        assert(key == "overlayPosition" and math.type(value.x) == "integer" and math.type(value.y) == "integer")
        assert(value.x >= 0 and value.y >= 0)
        if value.width then assert(math.type(value.width) == "integer" and value.width >= 340) end
        if value.height then assert(math.type(value.height) == "integer" and value.height >= 48) end
        positionWrites[#positionWrites + 1] = { x = value.x, y = value.y, width = value.width, height = value.height }
        if positionSaveOK then
            storedPosition = { x = value.x, y = value.y, width = value.width, height = value.height }
        end
        return positionSaveOK
    end,
    Clear = function()
        clearCalls = clearCalls + 1
        if clearOK then
            for key in pairs(storedPreferences) do storedPreferences[key] = nil end
            storedPosition = nil
        end
        return clearOK
    end,
}
local bossNPC = { isValid = true, displayName = "Vorago", uid = 1, configID = 1, isMultiNPC = false }
local npcs = { bossNPC }
local originalPrint = print
print = function(message) messages[#messages + 1] = message end

local Timer = require("src/timer")
local originalStart = Timer.start
local Detector = require("src/detector")
local originalNewDetector, detectorState = Detector.new, nil
Detector.new = function()
    detectorState = originalNewDetector()
    return detectorState
end
local starts, lastTimerState = 0, nil
Timer.start = function(state)
    assert(detectorState.positive == nil, "start must clear HP history")
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
local mousePosition = { x = 0, y = 0 }
Mouse = { GetPosition = function() return mousePosition end }
config = { Cursor = {
    TOPLEVEL_V2_MOVE = { id = 50 }, TOPLEVEL_V2_SCALE_VERT = { id = 51 },
    TOPLEVEL_V2_SCALE_HORZ = { id = 52 }, TOPLEVEL_V2_SCALE_DIAG_1 = { id = 53 },
    TOPLEVEL_V2_SCALE_DIAG_2 = { id = 54 },
} }
GameState = { GAME = 30, LOBBY = 20, RECONNECTING = 35, LOADING = 40 }
ValueType = { INTEGER = 0, STRING = 36 }
var = {
    VarPlayer = {
        TOPLEVEL_V2_CUSTOMIZATION_LOCK = { typeName = "VarPlayer", valueType = 0, value = 1 },
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
    assert(name == "Vorago", "only Vorago presence should be queried")
    queryCount = queryCount + 1
    return npcs
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
        hidden = false, enabled = true, clickthrough = false, alpha = 1, baseAlpha = 1,
        cursorConfig = { mouseOverCursor = -1 }, opConfig = { cursors = {} },
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
    function component:SetHeight(height)
        assert(self.alive and math.type(height) == "integer")
        self.height = height
    end
    function component:SetHeaderLayout() assert(self.alive) end
    function component:AlignTo() assert(self.alive) end
    function component:MoveToFront() assert(self.alive) end
    function component.opConfig:SetOpCursor(index, cursorID) self.cursors[index] = cursorID end
    function component:Subscribe(hook, callback) self.hooks[hook] = callback end
    function component:Destroy()
        assert(self.alive, "must not destroy stale components")
        self.alive = false
        for _, child in ipairs(components) do
            if child.parent == self and child.alive then child:Destroy() end
        end
    end
    setmetatable(component, { __index = function(self, key)
        if key == "xyGlobal" then
            local x, y, parent = 0, 0, self
            while parent do
                x, y = x + (parent.x or 0), y + (parent.y or 0)
                parent = parent.parent
            end
            return { x = x, y = y }
        end
    end })
    components[#components + 1] = component
    return component
end

ui = {
    Hook = { ONBUTTONPRESSED = 1, ONCLICK = 2, ONHOLD = 3, ONRELEASE = 4, ONDRAGCOMPLETE = 5 },
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
for _, kind in ipairs({ "GroupBox", "Text", "Rectangle", "Button", "Layer", "Sprite" }) do
    ui[kind] = { new = function(parent) return newComponent(kind, parent) end }
end

-- Only the installed 1.2.0 API is mocked: no NewComponent, auto IDs, or hideCloseButton option.
local widgets, timerWidget, settingsWidget = {}, nil, nil
local forceContentCategory = nil
local forceMissingFrame = nil
local forceMissingScrollClickthrough = false
local Widget = {}
function Widget:AddText(value)
    if self.kind == "Panel" then
        local dock = Widget.AddText({ content = self.dock.content, nextY = self.nextY }, value)
        local overlay = Widget.AddText({ content = self.overlay.content, nextY = self.nextY }, value)
        return setmetatable({ dock = dock, overlay = overlay }, {
            __index = function(_, key)
                if type(dock[key]) ~= "function" then return dock[key] end
                return function(_, ...)
                    local result = dock[key](dock, ...)
                    overlay[key](overlay, ...)
                    return result
                end
            end,
            __newindex = function(_, key, data) dock[key], overlay[key] = data, data end,
        })
    end
    local options = type(value) == "table" and value or { text = value }
    local label = newComponent("Text", self.content)
    local height = options.height or 24
    label:SetPos(options.x or 0, options.y or self.nextY)
    label:SetSize(options.width or self.content.width, height)
    label.content, label.maxLines = options.text or "", options.maxLines
    label.alignVertical = options.alignVertical or ui.AlignMode.CENTRE
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
    function control:SetSelected(key, selected, notify)
        if self.selected[key] == nil then return false end
        if self.selected[key] == selected then return true end
        self.selected[key] = selected
        if notify ~= false then self.options.onChange(self, {}, key, selected) end
        return true
    end
    self.checkbox = control
    self.nextY = self.nextY + #choices * 28
    return control
end
function Widget:AddSimpleButton(label, action, options)
    local button = newComponent("Button", self.content)
    button.label = label
    button:SetPos(0, self.nextY)
    button:SetSize(options.width, 28)
    button.hooks[ui.Hook.ONCLICK] = function() action(button) end
    self.nextY = self.nextY + 32
    self.resetButton = button
    return button
end
function Widget:SetSize(width, height)
    width, height = math.max(self.minWidth or 0, width), math.max(self.minHeight or 0, height)
    self.root:SetSize(width, height)
    self.width, self.height = width, height
    if self.kind == "Panel" then
        for _, surface in ipairs({ self.dock, self.overlay }) do
            surface.root:SetSize(width, height)
            surface.container:SetSize(width - 8, height - 8)
            surface.scroll:Refresh()
            for _, name in ipairs({ "background", "top", "bottom", "left", "right", "topLeft", "topRight", "bottomLeft", "bottomRight" }) do
                local part = surface[name]
                if part then
                    local left, right = name:find("Left"), name:find("Right")
                    local top, bottom = name:find("top"), name:find("bottom")
                    part:SetPos((right or name == "right") and width - 4 or (left or name == "left") and 0 or 4,
                        top and 0 or bottom and height - 4 or 4)
                    part:SetSize((left or right or name == "left" or name == "right") and 4 or width - 8,
                        (top or bottom) and 4 or height - 8)
                end
            end
        end
    else
        self.content:SetSize(width, height)
    end
end
function Widget:Destroy()
    self.destroyCalls = self.destroyCalls + 1
    assert(self.destroyCalls == 1, "destroy each PrettyUI wrapper exactly once")
    if self.root.alive then self.root:Destroy() end
    if self.overlay and self.overlay.root.alive then self.overlay.root:Destroy() end
end
local function widget(kind, parent, options, flowManaged)
    assert(options.categoryID == nil and options.hideCloseButton == nil, "do not assume newer PrettyUI APIs")
    local result = setmetatable({
        kind = kind, root = newComponent("Layer", parent), nextY = 0, titleCalls = 0, destroyCalls = 0,
        requestedContentHeight = options.contentHeight,
        minWidth = options.minWidth, minHeight = options.minHeight,
    }, { __index = Widget })
    local function content(surface, parent)
        local scrollRoot = newComponent("Layer", parent)
        surface.viewport = newComponent("Layer", scrollRoot)
        surface.content = newComponent("Layer", surface.viewport)
        surface.scroll = { root = scrollRoot, viewport = surface.viewport, content = surface.content,
            requestedContentHeight = options.contentHeight or 0 }
        if not forceMissingScrollClickthrough then
            function surface.scroll:SetClickthrough(value)
                self.root.clickthrough = value
                self.viewport.clickthrough, self.content.clickthrough = value, value
                self.viewport.enabled, self.content.enabled = not value, not value
            end
        end
        function surface.scroll:Refresh()
            self.content:SetSize(parent.width, math.max(self.requestedContentHeight, parent.height))
        end
        function surface.scroll:SetContentHeight(height)
            assert(math.type(height) == "integer")
            self.requestedContentHeight = height
            self:Refresh()
        end
    end
    if kind == "Panel" then
        assert(options.scrollable == false and options.resizable == false and options.popout == false and flowManaged == true,
            "disable Panel's implicit Alt-drag, popout, and resizing")
        result.dock, result.overlay = { root = result.root }, { root = newComponent("Layer", parent) }
        for _, surface in ipairs({ result.dock, result.overlay }) do
            surface.root:SetPos(options.x or 0, options.y or 0)
            surface.container = newComponent("Layer", surface.root)
            surface.container:SetPos(4, 4)
            for name, key in pairs({
                background = "content", top = "top", bottom = "bottom", left = "side", right = "side",
                topLeft = "cornerTop", topRight = "cornerTop", bottomLeft = "cornerBottom", bottomRight = "cornerBottom",
            }) do
                local frame = newComponent("Sprite", surface.root)
                frame.spriteID = prettyui.Sprites.HUD_WINDOW[key]
                frame.alpha = name == "background" and 0.6 or (name == "topLeft" and 0 or 1)
                frame.baseAlpha, frame.clickthrough = frame.alpha, true
                surface[name] = frame
            end
            content(surface, surface.container)
        end
        result.overlay.root.hidden = true
        result.content, result.viewport = result.dock.content, result.dock.viewport
        timerWidget = result
    else
        assert(parent == settingsParent)
        content(result, result.root)
        result._scroll = result.scroll
        settingsWidget = result
    end
    if forceContentCategory then result.content.categoryID = forceContentCategory end
    result:SetSize(options.width, options.height)
    result.root:SetPos(options.x or 0, options.y or 0)
    if forceMissingFrame and result.dock then result.dock[forceMissingFrame] = nil end
    widgets[#widgets + 1] = result
    return result
end
prettyui = {
    version = "1.2.0",
    Sprites = { HUD_WINDOW = { content = 900, top = 901, bottom = 902, side = 903, cornerTop = 904, cornerBottom = 905 } },
    Panel = {
        new = function(parent, options, flowManaged) return widget("Panel", parent, options, flowManaged) end,
        AddText = Widget.AddText,
    },
    SimpleView = {
        new = function(parent, options) return widget("SimpleView", parent, options) end,
        AddCheckboxButton = Widget.AddCheckboxButton,
        AddSimpleButton = Widget.AddSimpleButton,
    },
}
assert(prettyui.Panel.SetClickthrough == nil and prettyui.Panel.SetContentHeight == nil,
    "PrettyUI 1.2.0 exposes these through each panel surface's scroll controller, not Panel")

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
        if component.alive and component.kind == "Text" and component.parent == timerWidget.content
            and component.prettyOptions.y == y then
            return component
        end
    end
    error("debug label missing at " .. y)
end
local function rectangles()
    local result = {}
    for _, component in ipairs(components) do
        if component.alive and component.kind == "Rectangle" and component.parent == timerWidget.content
            and component.fill ~= false then
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
local function checkContentFit()
    local bottom = 0
    for _, component in ipairs(components) do
        if component.alive and component.parent == timerWidget.content and not component.hidden
            and component.fill ~= false then
            bottom = math.max(bottom, component.y + component.height)
        end
    end
    assert(timerWidget.content.height == bottom + 6, "resizing fills the available height with six pixels of bottom padding")
    assert(timerWidget.root.height == timerWidget.content.height + 8, "fit the thin HUD frame to its content")
    assert(timerWidget.dock.container.x == 4 and timerWidget.dock.container.y == 4)
    assert(timerWidget.dock.top.height == 4 and timerWidget.dock.left.width == 4)
    assert(timerWidget.dock.topLeft.width == 4 and timerWidget.dock.topLeft.height == 4)
    assert(timerWidget.overlay.root.hidden, "the unused popout surface must never appear")
    if not debugLabel(70).hidden then
        local firstY = debugLabel(6).height + 12 + (debugLabel(40).hidden and 0 or 30)
        assert(debugLabel(70).y == firstY, "debug rows must not reserve an empty error row")
        assert(debugLabel(94).y == firstY + 24 and debugLabel(118).y == firstY + 48)
    end
end
local function checkLayout(expectedCountdown, emptyBars)
    checkContentFit()
    local countdown = find("Text", expectedCountdown or "0.0s")
    local firstBar = find("Text", "pre-ult")
    local lastBar = find("Text", "tc")
    assert(countdown.y == firstBar.y and countdown.height == firstBar.height)
    assert(countdown.x + countdown.width < firstBar.x, "countdown must be left of the bar")
    assert(lastBar.x + lastBar.width == timerWidget.content.width - 6, "bar must fit the panel")
    assert(countdown.x == 4 and countdown.width == 56 and countdown.y == 6 and timerWidget.titleCalls == 0,
        "use a narrower countdown with four units on the left and six before the bars")
    assert(firstBar.x == countdown.x + countdown.width + 6)
    assert(timerWidget.closeButton == nil, "the HUD panel has no modal close button")
    assert(timerWidget.content.categoryID == 0)
    for _, component in ipairs(components) do
        if component.alive and component.kind == "Button" and component.parent == timerWidget.content then
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
    npcs = { bossNPC }
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
local function overlayOpacity()
    local opacity = debugLabel(6).alpha
    local count = 0
    for _, component in ipairs(components) do
        if component.alive and (component.parent == timerWidget.root or component.parent == timerWidget.content)
            and (component.kind == "Text" or component.kind == "Rectangle" or component.kind == "Sprite")
            and component.fill ~= false then
            close(component.alpha, component.baseAlpha * opacity)
            count = count + 1
        end
    end
    assert(count == 28, "check all nine frame sprites, ten rectangles, and nine labels")
    assert(timerWidget.root.alpha == 1, "container alpha must not substitute for drawable opacity")
    return opacity
end
local function dragHandle()
    for _, component in ipairs(components) do
        if component.alive and component.parent == pluginRoot
            and component.kind == "Layer" and component.height == 12 and not component.hooks[ui.Hook.ONCLICK] then
            return component
        end
    end
    error("missing native drag handle")
end
local function checkDragHeader()
    local handle, root = dragHandle(), timerWidget.root
    assert(handle.x == root.x and handle.width == root.width and handle.height == 12)
    assert(handle.y + handle.height == root.y, "the header must sit entirely above the gold frame")
    assert(handle.clickthrough, "the header is visual, not an input surface")
    local parts = 0
    for _, part in ipairs(components) do
        if part.alive and part.parent == handle then
            parts = parts + 1
            assert(part.clickthrough and part.x >= 0 and part.y >= 0)
            assert(part.x + part.width <= handle.width and part.y + part.height <= handle.height)
            if part.kind == "Sprite" then
                assert(part.spriteID == prettyui.Sprites.HUD_WINDOW.top or part.spriteID == prettyui.Sprites.HUD_WINDOW.side
                    or part.spriteID == prettyui.Sprites.HUD_WINDOW.cornerTop, "use HUD trim, never modal title artwork")
                assert(part.width == 4 or part.height == 4, "header borders must match the four-unit HUD frame")
            else
                assert(part.kind == "Rectangle" and part.y == 4 and part.height == 8,
                    "the brown fill reaches the panel border without an extra bottom separator")
                close(part.colour[1], 49 / 255)
                close(part.colour[2], 31 / 255)
                close(part.colour[3], 18 / 255)
            end
        end
    end
    assert(parts == 6, "a brown fill and five HUD border pieces share the panel's top edge")
    if not handle.hidden then assert(handle.y >= 0, "keep the unlocked header reachable at the screen edge") end
end
local function countMessages(part)
    local count = 0
    for _, message in ipairs(messages) do
        if message:find(part, 1, true) then count = count + 1 end
    end
    return count
end

local App = require("src/app")
assert(type(App.start) == "function")
assert(#widgets == 0 and next(preferenceReads) == nil, "importing the app must not start it")
for _, callbacks in pairs(subscriptions) do assert(next(callbacks) == nil) end
assert(PluginShutdown == nil, "the root entrypoint must own the shutdown hook")

local library = prettyui
prettyui = nil
local loaded, missingDependency = pcall(dofile, "main.lua")
assert(not loaded and tostring(missingDependency):find("PrettyUI", 1, true))
assert(#widgets == 0 and next(preferenceReads) == nil, "missing dependency must fail before setup")
prettyui = library
dofile("main.lua")
assert(type(PluginShutdown) == "function")
for _, callbacks in pairs(subscriptions) do assert(callbacks.VoragoSync ~= nil) end
assert(hasMessage("[VoragoSync] PrettyUI 1.2.0 loaded."))
draw(0.02)
assert(hasMessage("Waiting for the in-game"))
rootAvailable = true
draw(0.02)
checkLayout()
assert(queryCount == 1 and activityQueries == 3, "encounter monitoring is automatic")
assert(timerWidget.root.height == 48)
assert(debugLabel(70).hidden and debugLabel(94).hidden and debugLabel(118).hidden)
assert(preferenceReads.debugMode == 1)
assert(overlayOpacity() == 0, "the first visible draw starts transparent")
draw(0)
assert(overlayOpacity() == 0, "zero elapsed time must not advance the fade")
draw(0.125)
close(overlayOpacity(), 0.125)
draw(0.375)
close(overlayOpacity(), 0.5)
draw(0.25)
close(overlayOpacity(), 0.75)
draw(0.25)
assert(overlayOpacity() == 1, "the fade reaches full opacity after one second")
for _ = 1, 20 do draw(0.05) end
assert(overlayOpacity() == 1, "continuous visibility must not restart the fade")
assert(starts == 0, "enabling at zero must not start")
openSettings()
assert(#settingsWidget.checkbox.choices == 4)
assert(not settingsWidget.checkbox.selected.debugMode)
assert(not settingsWidget.checkbox.selected.onlyInArena and preferenceReads.onlyInArena == 1)
assert(settingsWidget.checkbox.selected.lockLocation == nil and preferenceReads.lockLocation == nil)
assert(not settingsWidget.checkbox:SetSelected("lockLocation", false))
setting("debugMode", true)
assert(storedPreferences.debugMode and timerWidget.root.height == 124)
checkContentFit()
find("Text", "Activity: Vorago")
find("Text", "Current HP: 0")
assert(not debugLabel(70).hidden)
local beforeSharedRead = activityQueries
draw(0.1)
assert(activityQueries == beforeSharedRead + 3, "passive debug must not add polling")
assert(starts == 0)
draw(46)
assert(not debugLabel(70).hidden, "debug readouts have no 45-second timeout")

observe(250000)
find("Text", "Armed: Vorago HP")
observe(0)
assert(starts == 1 and lastTimerState.phase == "running")
assert(hasMessage("Vorago positive HP -> 0: started 24-second countdown."))
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
assert(not timerWidget.root.hidden, "arena visibility is opt-in")
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
assert(find("Text", "Monitor: Type error: current value").hidden, "monitoring errors stay off the compact overlay")
assert(debugLabel(70).hidden)
assert(timerWidget.root.height == 48, "errors must not add empty space with debug disabled")
checkContentFit()
setting("debugMode", true)
assert(not find("Text", "Monitor: Type error: current value").hidden, "debug mode reveals an existing error")
assert(timerWidget.root.height == 154)
checkContentFit()
setting("debugMode", false)
assert(debugLabel(40).hidden and timerWidget.root.height == 48, "turning debug off hides an unchanged error")
checkContentFit()
setting("debugMode", true)
assert(not debugLabel(40).hidden and timerWidget.root.height == 154)
assert(countMessages(errorPrefix) == errorCount + 1, "display toggles do not duplicate monitoring logs")
currentVar.valueType = ValueType.INTEGER
draw(0.05)
assert(timerWidget.root.height == 124, "clearing an error collapses the row in debug mode")
checkContentFit()
setting("debugMode", false)
assert(timerWidget.root.height == 48, "turning debug off restores a single compact row")
checkContentFit()
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

-- Encounter and player-health guards still apply to the shared HP trigger.
for _, invalidate in ipairs({
    function() npcs = {} end,
    function() npcs = nil end,
    function() bossNPC.isValid = false end,
    function() lifeVar.value = 0 end,
    function() lifeVar.valueType = ValueType.STRING end,
}) do
    reenter()
    baseline = starts
    observe(100)
    invalidate()
    observe(0)
    assert(starts == baseline and detectorState.positive == nil,
        "encounter loss/error/death must discard HP history")
    defaults()
    draw(0.05)
    assert(starts == baseline, "returning at zero must not retain an old HP edge")
    observe(100)
    observe(0)
    assert(starts == baseline + 1, "a fresh HP edge must rearm after recovery")
end

reenter()
baseline = starts
observe(100)
bossNPC.uid = 2
observe(0)
assert(starts == baseline and detectorState.positive == nil, "encounter identity change must discard HP history")
reenter()
observe(100)
emit("GameStateChanged", { newState = GameState.LOADING })
currentVar.value = 0
draw(1)
emit("GameStateChanged", { newState = GameState.GAME })
draw(0.05)
assert(starts == baseline and detectorState.positive == nil, "loading cannot carry HP history")
reenter()
baseline = starts

-- Positive named boss HP or an active timer keeps the overlay visible, with five seconds of grace.
setting("onlyInArena", true)
local arenaWindow, arenaSettings = timerWidget, settingsWidget
assert(arenaWindow.root.hidden and overlayOpacity() == 0, "startup at zero must not show an idle overlay")
draw(6)
assert(arenaWindow.root.hidden and starts == baseline, "sustained zero HP does not refresh visibility")
observe(100)
assert(storedPreferences.onlyInArena and not arenaWindow.root.hidden)
hideVar.value = 1
local queriesBeforeHide, activityBeforeHide = queryCount, activityQueries
draw(0.05)
assert(not arenaWindow.root.hidden, "boss-bar loss starts the buffer rather than hiding immediately")
assert(queryCount == queriesBeforeHide + 1 and activityQueries == activityBeforeHide + 3,
    "visibility reuses the regular monitoring samples")
draw(4.99)
assert(not arenaWindow.root.hidden, "keep the overlay visible for the full five-second buffer")
draw(0.01)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1, "begin fading only after the five-second buffer")
draw(0)
assert(overlayOpacity() == 1, "zero elapsed time must not advance the fade-out")
draw(0.5)
close(overlayOpacity(), 0.5)
assert(not arenaWindow.root.hidden, "keep the root visible until the fade-out finishes")
draw(0.25)
close(overlayOpacity(), 0.25)
assert(not arenaWindow.root.hidden)
draw(0.25)
assert(arenaWindow.root.hidden and overlayOpacity() == 0, "hide after the one-second fade-out")
assert(timerWidget == arenaWindow and arenaWindow.destroyCalls == 0, "hide rather than destroy the window")
assert(arenaSettings.destroyCalls == 0 and not arenaSettings.root.hidden, "Settings remains accessible outside the arena")
assert(arenaSettings.root.alpha == 1, "the timer animation does not fade Settings")
setting("onlyInArena", false)
assert(not arenaWindow.root.hidden, "disabling the setting shows the overlay immediately")
assert(overlayOpacity() == 0, "revealing via Settings starts a fresh fade")
draw(0.5)
close(overlayOpacity(), 0.5)
setting("onlyInArena", true)
assert(not arenaWindow.root.hidden, "hiding mid-fade must not abruptly hide the root")
close(overlayOpacity(), 0.5)
draw(0.25)
close(overlayOpacity(), 0.25)
setting("onlyInArena", false)
close(overlayOpacity(), 0.25)
draw(0.25)
close(overlayOpacity(), 0.5)
setting("onlyInArena", true)
draw(0.5)
assert(arenaWindow.root.hidden and overlayOpacity() == 0,
    "setting changes reverse the fade from its current opacity without restarting the buffer")

local hiddenQueries = queryCount
draw(0.05)
assert(queryCount == hiddenQueries + 1 and starts == baseline, "monitoring continues while hidden")
hideVar.value, nameVar.value = 0, "Other activity"
draw(0.05)
assert(arenaWindow.root.hidden, "unrelated activity bars do not show the overlay")
assert(overlayOpacity() == 0, "hidden draw time must not advance the fade")
nameVar.value, npcs = " <col=ffffff>VoRaGo</col> ", {}
draw(0.05)
assert(arenaWindow.root.hidden, "a fresh boss bar cannot bypass the post-hide cooldown")
draw(10)
assert(not arenaWindow.root.hidden, "a valid normalized Vorago bar shows immediately without an NPC")
assert(overlayOpacity() == 0, "time spent hidden must not skip the reveal animation")
draw(0.5)
close(overlayOpacity(), 0.5)
setting("removeBarSections", true)
setting("debugMode", true)
close(overlayOpacity(), 0.5)
assert(not rectangles()[10].hidden and not debugLabel(70).hidden,
    "newly revealed bar styles and debug labels retain the current fade opacity")
checkContentFit()
setting("removeBarSections", false)
draw(6)
assert(not arenaWindow.root.hidden, "an active bar keeps refreshing the buffer")
assert(overlayOpacity() == 1, "long frames clamp the fade to full opacity")

npcs = nil
local lookupErrorCount = countMessages("Encounter monitoring error: NPC list unavailable: Vorago")
draw(0.05)
draw(0.05)
assert(not arenaWindow.root.hidden, "NPC lookup errors do not override a confirmed boss bar")
assert(countMessages("Encounter monitoring error: NPC list unavailable: Vorago") == lookupErrorCount + 1)
defaults()
currentVar.valueType = ValueType.STRING
local visibilityErrorCount = countMessages(errorPrefix)
draw(0.05)
assert(not arenaWindow.root.hidden, "an invalid boss-bar read gets the same grace as bar loss")
draw(5)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1)
draw(1)
assert(arenaWindow.root.hidden and countMessages(errorPrefix) == visibilityErrorCount + 1)
draw(10)
defaults()
currentVar.value = 100
draw(0.05)
assert(not arenaWindow.root.hidden, "visibility recovers immediately after a valid read")
bossRoot.visibleGlobal = false
draw(0.05)
draw(5)
draw(1)
assert(arenaWindow.root.hidden, "hidden activity containers are not active boss bars")
draw(10)

defaults()
currentVar.value = 100
draw(0.05)
hideVar.value = 1
draw(0.05)
draw(4)
assert(overlayOpacity() == 1)
hideVar.value = 0
draw(0.05)
assert(overlayOpacity() == 1, "activity returning within the buffer does not restart the fade")
hideVar.value = 1
draw(0.05)
draw(4.99)
assert(not arenaWindow.root.hidden, "returning activity resets the full buffer")
draw(0.01)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1)
draw(0.5)
close(overlayOpacity(), 0.5)
hideVar.value = 0
draw(0.05)
close(overlayOpacity(), 0.5)
draw(0.5)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1,
    "a returning boss bar reverses fade-out without flashing or hiding")
hideVar.value = 1
draw(0.05)
draw(5)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1)
draw(2)
assert(arenaWindow.root.hidden and overlayOpacity() == 0, "long frames clamp fade-out to zero opacity")
draw(10)

defaults()
observe(100)
observe(0)
assert(starts == baseline + 1, "monitoring must still detect the next encounter")
hideVar.value, npcs = 1, {}
draw(6)
assert(not arenaWindow.root.hidden and lastTimerState.phase == "running",
    "a running countdown stays visible beyond five seconds with neither Vorago nor his bar present")
close(lastTimerState.elapsed, 6)
setting("onlyInArena", false)
setting("onlyInArena", true)
assert(not arenaWindow.root.hidden)
close(lastTimerState.elapsed, 6)
draw(18)
assert(not arenaWindow.root.hidden and lastTimerState.phase == "complete", "the full-bar hold remains visible")
draw(1)
assert(lastTimerState.phase == "idle" and not arenaWindow.root.hidden, "the buffer starts after the hold ends")
hideVar.value = 0
draw(2)
assert(not arenaWindow.root.hidden, "a late zero-HP bar does not interrupt the remaining buffer")
draw(2.99)
assert(not arenaWindow.root.hidden)
draw(0.01)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1, "the countdown hold and buffer precede fade-out")
draw(1)
assert(arenaWindow.root.hidden and starts == baseline + 1, "fade out after the buffer without queued starts")
draw(5)
assert(arenaWindow.root.hidden and overlayOpacity() == 0 and starts == baseline + 1,
    "stale zero-HP bars cannot make an idle overlay reappear after a fight")
hideVar.value = 1
draw(0.05)
hideVar.value = 0
draw(0.05)
assert(arenaWindow.root.hidden, "a fresh zero-HP bar sample still must not restart visibility")
draw(10)

-- An HP countdown starts during fade-in and stays visible after the boss bar disappears.
defaults()
observe(100)
assert(not arenaWindow.root.hidden and overlayOpacity() == 0 and detectorState.positive ~= nil)
observe(0)
assert(not arenaWindow.root.hidden and starts == baseline + 2)
close(overlayOpacity(), 0.05)
assert(lastTimerState.elapsed == 0)
draw(0.5)
close(overlayOpacity(), 0.55)
close(lastTimerState.elapsed, 0.5)
hideVar.value, npcs = 1, {}
draw(23.5)
assert(lastTimerState.phase == "complete" and not arenaWindow.root.hidden)
assert(overlayOpacity() == 1, "fading must not pause or stretch a countdown")
draw(6)
assert(lastTimerState.phase == "idle" and not arenaWindow.root.hidden,
    "a long frame ending the timer must not consume the new five-second buffer")
draw(4.99)
assert(not arenaWindow.root.hidden)
draw(0.01)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1)
draw(1)
assert(arenaWindow.root.hidden)
draw(10)

-- A returning bar and HP edge reverse fade-out without resetting time or opacity.
defaults()
currentVar.value = 100
draw(0.05)
draw(1)
hideVar.value = 1
draw(0.05)
draw(5)
draw(0.5)
close(overlayOpacity(), 0.5)
hideVar.value = 0
observe(100)
close(overlayOpacity(), 0.5)
observe(0)
assert(lastTimerState.phase == "running" and lastTimerState.elapsed == 0)
close(overlayOpacity(), 0.55)
draw(0.45)
assert(not arenaWindow.root.hidden and overlayOpacity() == 1)
close(lastTimerState.elapsed, 0.45)
reenter()
draw(10)

-- UI loss, reconnect, and shutdown discard the visibility grace as well as the timer.
defaults()
observe(100)
observe(0)
hideVar.value, npcs = 1, {}
draw(0.05)
assert(not timerWidget.root.hidden and lastTimerState.phase == "running")
local unloadedWindow = timerWidget
unloadedWindow.root:Destroy()
draw(0.05)
assert(unloadedWindow.destroyCalls == 1 and timerWidget ~= unloadedWindow)
assert(timerWidget.root.hidden and lastTimerState.phase == "idle", "UI loss discards the timer and visibility grace")
assert(overlayOpacity() == 0, "a recreated hidden window must not inherit fade progress")
draw(10)
defaults()
currentVar.value = 100
draw(0.05)
assert(overlayOpacity() == 0)
draw(0.5)
close(overlayOpacity(), 0.5)
hideVar.value = 1
draw(0.05)
assert(not timerWidget.root.hidden)
local hiddenWindow = timerWidget
emit("GameStateChanged", { newState = GameState.RECONNECTING })
assert(hiddenWindow.destroyCalls == 1)
local queriesInReconnect = queryCount
draw(1)
assert(queryCount == queriesInReconnect)
emit("GameStateChanged", { newState = GameState.GAME })
draw(0.05)
assert(timerWidget.root.hidden, "reconnect without a boss bar must not restore stale visibility grace")
assert(overlayOpacity() == 0, "reconnect discards an interrupted fade")
setting("onlyInArena", false)
reenter()
draw(10)
baseline = starts

-- All display settings can change mid-run without touching time or detector state.
observe(100)
observe(0)
draw(1.25)
baseline = starts
local runningWindow, elapsedBeforeSettings = timerWidget, lastTimerState.elapsed
local armedHP = detectorState.positive
openSettings()
for _, onlyInArena in ipairs({ false, true }) do
    setting("onlyInArena", onlyInArena)
    for _, debugMode in ipairs({ false, true }) do
        for _, smooth in ipairs({ false, true }) do
            for _, uniform in ipairs({ false, true }) do
                setting("debugMode", debugMode)
                setting("smoothCountdown", smooth)
                setting("removeBarSections", uniform)
                assert(starts == baseline and lastTimerState.elapsed == elapsedBeforeSettings)
                assert(detectorState.positive == armedHP)
                assert(timerWidget == runningWindow and runningWindow.destroyCalls == 0)
                assert(not timerWidget.root.hidden, "display styles do not hide a present encounter")
                assert(timerWidget.root.height == (debugMode and 124 or 48))
                assert(debugLabel(70).hidden == not debugMode)
                checkLayout(smooth and "22.7s" or "22.2s", false)
                local bars = rectangles()
                assert(#bars == 10)
                for i = 1, 8 do assert(bars[i].hidden == uniform) end
                for _, name in ipairs({ "pre-ult", "ult", "post-ult", "tc" }) do
                    assert(find("Text", name).hidden == uniform)
                end
                assert(bars[9].hidden == not uniform and bars[10].hidden == not uniform)
                assert(bars[9].x == 66 and bars[9].width == 420)
                assert(bars[10].x == 66 and bars[10].width == math.floor(420 * elapsedBeforeSettings / 24 + 0.5))
                assert(bars[10].colour[1] == 0.83, "uniform mode keeps the existing accent")
            end
        end
    end
end
draw(10.75)
assert(rectangles()[10].width == 210, "uniform progress spans the full 24 seconds")
draw(12)
assert(lastTimerState.phase == "complete" and rectangles()[10].width == 420)
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
assert(debugLabel(70).hidden)
assert(find("Text", "Display setting was not saved.").hidden)
assert(not find("Text", "The change applies for this session, but could not be saved.").hidden)
assert(timerWidget.root.height == 48 and lastTimerState.elapsed == elapsedBeforeRemount)
checkContentFit()
setting("debugMode", true)
assert(not find("Text", "Display setting was not saved.").hidden and timerWidget.root.height == 154)
checkContentFit()
setting("debugMode", false)
assert(debugLabel(40).hidden and timerWidget.root.height == 48 and lastTimerState.elapsed == elapsedBeforeRemount)
checkContentFit()
saveOK = true
setting("smoothCountdown", false)
assert(debugLabel(40).hidden, "a successful save clears the preference error")
assert(timerWidget.root.height == 48 and lastTimerState.elapsed == elapsedBeforeRemount)
checkContentFit()

setting("debugMode", true)
setting("smoothCountdown", true)
setting("removeBarSections", true)
setting("onlyInArena", true)
hideVar.value = 1
draw(0.05)
assert(not timerWidget.root.hidden, "the active timer stays visible before shutdown")
PluginShutdown()
for _, callbacks in pairs(subscriptions) do assert(next(callbacks) == nil) end
for _, component in ipairs(components) do assert(not component.alive) end
dofile("main.lua")
draw(0.05)
assert(starts == baseline, "reload at zero must not restart")
assert(timerWidget.root.height == 124 and not debugLabel(70).hidden)
checkContentFit()
assert(not rectangles()[10].hidden, "ordinary preferences are restored")
assert(timerWidget.root.hidden, "reload applies the saved setting without stale activity or visibility grace")
openSettings()
assert(settingsWidget.checkbox.selected.smoothCountdown and settingsWidget.checkbox.selected.removeBarSections)
assert(settingsWidget.checkbox.selected.onlyInArena and not settingsWidget.root.hidden)
setting("onlyInArena", false)
assert(not timerWidget.root.hidden)
setting("onlyInArena", true)
PluginShutdown()

-- A release build still exposes the ordinary settings, never Debug mode.
local Build = require("src/build")
Build.isDevBuild = false
local previousDebugReads = preferenceReads.debugMode
dofile("main.lua")
draw(0.05)
assert(preferenceReads.debugMode == previousDebugReads, "release mode must ignore a saved true debug preference")
assert(timerWidget.root.height == 48 and debugLabel(70).hidden and debugLabel(94).hidden and debugLabel(118).hidden)
openSettings()
assert(#settingsWidget.checkbox.choices == 3 and settingsWidget.checkbox.selected.debugMode == nil)
assert(settingsWidget.checkbox.selected.onlyInArena and timerWidget.root.hidden)
assert(not settingsWidget.checkbox:SetSelected("debugMode", true))
setting("smoothCountdown", false)
setting("removeBarSections", false)
setting("onlyInArena", false)
assert(not timerWidget.root.hidden)
checkLayout()
PluginShutdown()
Build.isDevBuild = true

-- Placement mode converts stable mouse coordinates into interface units.
do
    local mouseScale, pointerStart = 1, nil
    local lockVar = var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK
    local function setInterfaceLocked(locked)
        local preferenceWrites = #writes
        lockVar.value = locked and 1 or 0
        draw(0)
        assert(#writes == preferenceWrites, "native lock changes must not write plugin preferences")
    end
    local function capture()
        for _, component in ipairs(components) do
            if component.alive and component.parent == pluginRoot and component.hooks[ui.Hook.ONCLICK] then
                return component
            end
        end
        error("missing drag surface")
    end
    local handle = dragHandle
    local function pointer(hook, x, y)
        local surface = capture()
        if hook == ui.Hook.ONCLICK then
            local origin = surface.xyGlobal
            mousePosition = { x = (origin.x + x) * mouseScale, y = (origin.y + y) * mouseScale }
            pointerStart = { x = mousePosition.x, y = mousePosition.y }
        end
        assert(surface.hooks[hook](surface, x, y) == false)
    end
    local function movePointer(x, y)
        mousePosition = { x = pointerStart.x + x * mouseScale, y = pointerStart.y + y * mouseScale }
    end
    local function dragBy(x, y)
        pointer(ui.Hook.ONCLICK, 10, 5)
        pointer(ui.Hook.ONHOLD, 10, 10)
        movePointer(x, y)
        pointer(ui.Hook.ONHOLD, 100 + x, 50 + y)
    end
    local function checkClickthrough()
        for _, component in ipairs(components) do
            local parent = component
            while parent and parent ~= timerWidget.root do parent = parent.parent end
            if component.alive and parent == timerWidget.root then
                assert(component.clickthrough, "every window layer and drawable must let game clicks through")
            end
        end
    end

    defaults()
    hideVar.value, npcs = 1, {}
    storedPreferences.debugMode, storedPreferences.onlyInArena = false, true
    storedPreferences.lockLocation, storedPosition = false, nil
    dofile("main.lua")
    draw(0.05)
    openSettings()
    assert(settingsWidget.checkbox.selected.lockLocation == nil, "there is no plugin-specific location lock")
    assert(preferenceReads.lockLocation == nil, "ignore the obsolete saved location-lock preference")
    assert(timerWidget.root.hidden and handle().hidden)
    assert(capture().hidden and not capture().enabled and capture().clickthrough)
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378, "keep the centered default")
    checkClickthrough()
    dragBy(120, 80)
    pointer(ui.Hook.ONRELEASE)
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378 and #positionWrites == 0,
        "locked callbacks must not move or save the window")

    setInterfaceLocked(false)
    assert(not timerWidget.root.hidden and overlayOpacity() == 1)
    assert(not handle().hidden and not capture().hidden and capture().enabled and not capture().clickthrough)
    assert(capture().cursorConfig.mouseOverCursor == config.Cursor.TOPLEVEL_V2_MOVE.id)
    assert(capture().opConfig.cursors[0] == config.Cursor.TOPLEVEL_V2_MOVE.id)
    checkDragHeader()
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378 and timerWidget.root.height == 48,
        "unlocking adds only an external header, not padding or a position change")
    assert(capture().x == timerWidget.root.x + 5 and capture().y == timerWidget.root.y - 7)
    for _, component in ipairs(components) do
        if component.alive and component.parent == pluginRoot and component.hooks[ui.Hook.ONCLICK] and component ~= capture() then
            local input = capture()
            assert(component.x + component.width <= input.x or component.x >= input.x + input.width
                or component.y + component.height <= input.y or component.y >= input.y + input.height,
                "the drag bar's input must not overlap any resize edge or corner")
        end
    end
    assert(not settingsWidget.root.clickthrough, "placement must not change Settings input handling")
    draw(10)
    assert(not timerWidget.root.hidden and overlayOpacity() == 1, "unlocked placement overrides arena hiding")
    checkContentFit()
    checkClickthrough()

    pointer(ui.Hook.ONCLICK, 10, 5)
    assert(capture().x == 0 and capture().y == 0 and capture().width == 1920 and capture().height == 1080)
    pointer(ui.Hook.ONHOLD, 10, 10)
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378, "a stationary pointer must not move the window")
    pointer(ui.Hook.ONHOLD, 712, 388)
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378,
        "switching from local to parent-relative hold coordinates must not jump the window")
    movePointer(120, 80)
    pointer(ui.Hook.ONHOLD, 832, 468)
    assert(timerWidget.root.x == 830 and timerWidget.root.y == 458, "drag deltas use interface units")
    checkDragHeader()
    draw(0)
    assert(timerWidget.root.x == 830 and timerWidget.root.y == 458 and #positionWrites == 0)
    pointer(ui.Hook.ONRELEASE)
    assert(#positionWrites == 1 and storedPosition.x == 830 and storedPosition.y == 458)
    assert(capture().x == 835 and capture().y == 451 and capture().width == 490 and capture().height == 7)
    pointer(ui.Hook.ONDRAGCOMPLETE)
    pointer(ui.Hook.ONCLICK, 10, 5)
    pointer(ui.Hook.ONRELEASE)
    assert(#positionWrites == 1, "duplicate release and clicks without movement must not write the DB")

    lockVar.value = 1
    pointer(ui.Hook.ONCLICK, 10, 5)
    assert(capture().width == timerWidget.root.width - 10, "a native lock change blocks clicks before the next draw")
    setInterfaceLocked(false)
    pointer(ui.Hook.ONCLICK, 10, 5)
    lockVar.value = 1
    movePointer(50, 50)
    pointer(ui.Hook.ONHOLD, 500, 500)
    assert(timerWidget.root.x == 830 and timerWidget.root.y == 458 and #positionWrites == 1,
        "holds must recheck the native lock before moving")
    assert(capture().width == timerWidget.root.width - 10, "locking releases full-screen capture immediately")
    setInterfaceLocked(false)
    assert(capture().enabled and not capture().hidden, "unlocking after an input-time lock change restores the handles")

    for _, hook in ipairs({ ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE }) do
        for _, failure in ipairs({ "missing", "invalid", "throwing" }) do
            dragBy(25, 25)
            local beforeRelease = #positionWrites
            lockVar.value = failure == "invalid" and "unknown" or nil
            if failure == "throwing" then
                setmetatable(lockVar, { __index = function(_, key)
                    if key == "value" then error("native lock release read failed") end
                end })
            end
            pointer(hook)
            assert(#positionWrites == beforeRelease, "release must recheck the lock and never save an unreadable state")
            assert(capture().hidden and not capture().enabled and capture().clickthrough)
            setmetatable(lockVar, nil)
            setInterfaceLocked(false)
            assert(timerWidget.root.x == 830 and timerWidget.root.y == 458)
            assert(capture().enabled and not capture().hidden, "recovery before the next draw must restore input")
            pointer(hook)
            assert(#positionWrites == beforeRelease, "duplicate completion must not save a cancelled gesture")
        end
        pointer(ui.Hook.ONCLICK, 10, 5)
        lockVar.value = 1
        pointer(hook)
        assert(capture().hidden and not capture().enabled, "release must observe locking before the next draw")
        setInterfaceLocked(false)
        assert(capture().enabled and not capture().hidden)
    end

    dragBy(25, 25)
    local lockErrors = countMessages("Interface lock state unavailable")
    lockVar.value = nil
    draw(0)
    assert(timerWidget.root.x == 830 and timerWidget.root.y == 458 and #positionWrites == 1,
        "an unreadable native lock cancels an unfinished drag without saving it")
    assert(capture().hidden and not capture().enabled and capture().clickthrough and handle().hidden)
    for _, invalid in ipairs({ false, "0", 2, -1, 0.5, 0 / 0 }) do
        lockVar.value = invalid
        draw(0.05)
        assert(capture().hidden and not capture().enabled)
    end
    assert(countMessages("Interface lock state unavailable") == lockErrors + 1, "persistent lock errors log once")
    setting("debugMode", true)
    assert(not debugLabel(40).hidden and timerWidget.root.height == 154)
    checkContentFit()
    setInterfaceLocked(false)
    assert(not capture().hidden and capture().enabled and overlayOpacity() == 1)
    assert(debugLabel(40).hidden and timerWidget.root.height == 124, "native lock recovery clears its error")
    setting("debugMode", false)
    checkContentFit()

    var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK = nil
    setmetatable(var.VarPlayer, { __index = function(_, key)
        if key == "TOPLEVEL_V2_CUSTOMIZATION_LOCK" then error("native lock lookup failed") end
    end })
    draw(0)
    assert(capture().hidden and hasMessage("native lock lookup failed"), "lookup exceptions must not unlock dragging")
    setmetatable(var.VarPlayer, nil)
    var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK = lockVar
    setInterfaceLocked(false)
    assert(not capture().hidden and #positionWrites == 1)

    for _, scale in ipairs({ 1, 1.25, 1.5, 2 }) do
        mouseScale = scale
        pluginRoot.x, pluginRoot.y = 40, 30
        local startX, startY = timerWidget.root.x, timerWidget.root.y
        pointer(ui.Hook.ONCLICK, 120, 5)
        movePointer(40, 25)
        pointer(ui.Hook.ONHOLD, 120, 20)
        assert(timerWidget.root.x == startX + 40 and timerWidget.root.y == startY + 25,
            "the first real movement preserves the grab point at every UI/display scale")
        pointer(ui.Hook.ONHOLD, 10000, 10000)
        assert(timerWidget.root.x == startX + 40 and timerWidget.root.y == startY + 25,
            "hold-hook coordinate changes cannot move a stationary cursor")
        movePointer(0, 0)
        pointer(ui.Hook.ONHOLD, 0, 0)
        pointer(ui.Hook.ONRELEASE)
        assert(timerWidget.root.x == startX and timerWidget.root.y == startY and #positionWrites == 1)
    end
    mouseScale, pluginRoot.x, pluginRoot.y = 1, 0, 0

    pointer(ui.Hook.ONCLICK, 10, 5)
    pointer(ui.Hook.ONHOLD, 0, 0)
    movePointer(-10000, -10000)
    pointer(ui.Hook.ONHOLD, -10000, -10000)
    assert(timerWidget.root.x == 0 and timerWidget.root.y == 12)
    checkDragHeader()
    movePointer(10000, 10000)
    pointer(ui.Hook.ONHOLD, 10000, 10000)
    assert(timerWidget.root.x == 1420 and timerWidget.root.y == 1032, "clamp all four screen edges")
    pointer(ui.Hook.ONRELEASE)
    assert(#positionWrites == 2 and storedPosition.x == 1420 and storedPosition.y == 1032)
    pluginRoot.width, pluginRoot.height = 800, 600
    draw(0)
    assert(timerWidget.root.x == 300 and timerWidget.root.y == 552)
    assert(capture().x == 305 and capture().y == 545)
    checkDragHeader()
    pluginRoot.width, pluginRoot.height = 1920, 1080
    draw(0)
    assert(timerWidget.root.x == 1420 and timerWidget.root.y == 1032 and #positionWrites == 2,
        "resizing clamps without overwriting the preferred position")
    setting("debugMode", true)
    assert(timerWidget.root.y == 956 and capture().height == 7 and handle().height == 12)
    setting("debugMode", false)
    assert(timerWidget.root.y == 1032 and capture().height == 7 and handle().height == 12)
    checkContentFit()

    dragBy(-100, -100)
    setInterfaceLocked(true)
    assert(#positionWrites == 3 and storedPosition.x == 1320 and storedPosition.y == 932,
        "locking ends a drag and saves its final position")
    assert(capture().hidden and capture().clickthrough and not capture().enabled and handle().hidden)
    draw(0.5)
    close(overlayOpacity(), 0.5)
    setInterfaceLocked(false)
    assert(overlayOpacity() == 1, "unlocking a fading window makes placement fully opaque")
    setInterfaceLocked(true)
    draw(1)
    assert(timerWidget.root.hidden, "locking restores the already-expired arena visibility buffer")
    setInterfaceLocked(false)

    defaults()
    observe(100)
    observe(0)
    draw(0.3)
    local startsBeforeDrag = starts
    dragBy(-20, -20)
    pointer(ui.Hook.ONRELEASE)
    assert(lastTimerState.phase == "running" and starts == startsBeforeDrag)
    close(lastTimerState.elapsed, 0.3)
    setInterfaceLocked(true)
    setInterfaceLocked(false)
    close(lastTimerState.elapsed, 0.3)

    local savedX, savedY = storedPosition.x, storedPosition.y
    positionSaveOK = false
    dragBy(-50, -20)
    pointer(ui.Hook.ONRELEASE)
    assert(timerWidget.root.x == savedX - 50 and timerWidget.root.y == savedY - 20)
    assert(storedPosition.x == savedX and storedPosition.y == savedY)
    assert(hasMessage("Overlay layout was not saved."))
    local positionWarning = find("Text", "The layout applies for this session, but could not be saved.")
    assert(not positionWarning.hidden)
    setInterfaceLocked(true)
    setInterfaceLocked(false)
    assert(positionWarning.content == "The layout applies for this session, but could not be saved.",
        "native lock changes must not conceal a failed position save")
    positionSaveOK = true
    dragBy(-10, 0)
    pointer(ui.Hook.ONRELEASE)
    assert(storedPosition.x == savedX - 60 and storedPosition.y == savedY - 20)
    assert(positionWarning.content == "", "a later successful position save clears its warning")
    local savedWriteCount = #positionWrites
    hideVar.value, npcs = 1, {}
    storedPreferences.lockLocation = true
    PluginShutdown()
    dofile("main.lua")
    draw(0.05)
    openSettings()
    assert(settingsWidget.checkbox.selected.lockLocation == nil and preferenceReads.lockLocation == nil)
    assert(timerWidget.root.x == storedPosition.x and timerWidget.root.y == storedPosition.y)
    assert(not timerWidget.root.hidden and overlayOpacity() == 1 and #positionWrites == savedWriteCount)

    local oldSurface, oldHandle = capture(), handle()
    dragBy(25, -25)
    timerWidget.root:Destroy()
    draw(0)
    assert(not oldSurface.alive and not oldHandle.alive and #positionWrites == savedWriteCount,
        "UI loss cancels an unfinished drag and destroys its sibling header")
    assert(timerWidget.root.x == storedPosition.x and timerWidget.root.y == storedPosition.y)
    oldSurface.hooks[ui.Hook.ONCLICK](oldSurface, 0, 0)
    oldSurface.hooks[ui.Hook.ONHOLD](oldSurface, 100, 100)
    oldSurface.hooks[ui.Hook.ONRELEASE](oldSurface)
    assert(#positionWrites == savedWriteCount and capture() ~= oldSurface, "stale drag callbacks do nothing")
    dragBy(5, 5)
    local reconnectSurface, reconnectHandle = capture(), handle()
    emit("GameStateChanged", { newState = GameState.RECONNECTING })
    assert(not reconnectSurface.alive and not reconnectHandle.alive and #positionWrites == savedWriteCount)
    emit("GameStateChanged", { newState = GameState.GAME })
    draw(0.05)
    assert(timerWidget.root.x == storedPosition.x and timerWidget.root.y == storedPosition.y)
    pointer(ui.Hook.ONCLICK, 0, 0)
    pointer(ui.Hook.ONHOLD, 0, 0)
    mousePosition = nil
    pointer(ui.Hook.ONHOLD, "invalid", 0)
    mousePosition = pointerStart
    draw(0)
    assert(hasMessage("Mouse position is unavailable.") and #positionWrites == savedWriteCount)
    assert(capture().width == timerWidget.root.width - 10 and capture().height == 7,
        "invalid drag input must release full-screen capture")
    local shutdownSurface, shutdownHandle = capture(), handle()
    dragBy(5, 5)
    PluginShutdown()
    assert(not shutdownSurface.alive and not shutdownHandle.alive and #positionWrites == savedWriteCount)

    lockVar.value = 1
    for _, invalid in ipairs({
        { x = "bad", y = 10 }, { x = -1, y = 0 }, { x = 0.5, y = 0 },
        { x = math.huge, y = 0 }, { x = 0 / 0, y = 0 }, { x = 0 },
    }) do
        storedPosition = invalid
        local previousErrors = countMessages("Saved overlay position is invalid")
        dofile("main.lua")
        draw(0.05)
        assert(timerWidget.root.x == 710 and timerWidget.root.y == 378)
        assert(countMessages("Saved overlay position is invalid") == previousErrors + 1)
        PluginShutdown()
    end
    storedPosition = { x = 5000, y = 5000 }
    dofile("main.lua")
    draw(0.05)
    assert(timerWidget.root.x == 1420 and timerWidget.root.y == 1032, "restore old positions within current bounds")
    pluginRoot.width, pluginRoot.height = 300, 40
    draw(0)
    assert(timerWidget.root.x == 0 and timerWidget.root.y == 0, "tiny viewports never produce negative placement")
    setInterfaceLocked(false)
    assert(timerWidget.root.y == 12)
    checkDragHeader()
    pointer(ui.Hook.ONCLICK, 0, 0)
    pointer(ui.Hook.ONHOLD, 0, 0)
    pointer(ui.Hook.ONRELEASE)
    assert(capture().width == timerWidget.root.width - 10 and #positionWrites == savedWriteCount,
        "grabbing the handle's corner without movement must not save a bad position")
    local mouseAPI = Mouse
    local missingMouseErrors = countMessages("Mouse position is unavailable.")
    Mouse = nil
    pointer(ui.Hook.ONCLICK, 10, 5)
    Mouse = mouseAPI
    assert(countMessages("Mouse position is unavailable.") == missingMouseErrors + 1)
    assert(capture().width == timerWidget.root.width - 10)
    mousePosition = { x = 0, y = 0 }
    local surface = capture()
    surface.hooks[ui.Hook.ONCLICK](surface, 10, 10)
    assert(hasMessage("Drag scale is unavailable.") and surface.width == timerWidget.root.width - 10)
    mousePosition = { x = 10, y = 10 }
    surface.hooks[ui.Hook.ONCLICK](surface, "invalid", 10)
    assert(hasMessage("Drag coordinates are unavailable.") and #positionWrites == savedWriteCount)
    setInterfaceLocked(true)
    pluginRoot.width, pluginRoot.height = 1920, 1080
    draw(0)
    assert(timerWidget.root.x == 1420 and timerWidget.root.y == 1032)
    PluginShutdown()
    storedPosition = nil
    var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK = nil
    dofile("main.lua")
    draw(0.05)
    assert(capture().hidden and not capture().enabled, "an unavailable native lock must not prevent plugin startup")
    local queriesWithMissingLock = queryCount
    draw(0.05)
    assert(queryCount == queriesWithMissingLock + 1, "encounter monitoring continues if lock state is unavailable")
    var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK = lockVar
    setInterfaceLocked(false)
    assert(not capture().hidden and overlayOpacity() == 1, "native lock availability recovers without reloading")
    PluginShutdown()
    lockVar.value = 1

    storedPosition = { x = 300, y = 0, width = 620, height = 1080 }
    dofile("main.lua")
    draw(0.05)
    local beforeUnlock = #positionWrites
    assert(timerWidget.root.y == 0 and timerWidget.root.height == 1080 and handle().hidden)
    setInterfaceLocked(false)
    assert(timerWidget.root.y == 12 and timerWidget.root.height == 1068)
    checkDragHeader()
    setInterfaceLocked(true)
    assert(timerWidget.root.y == 0 and timerWidget.root.height == 1080 and handle().hidden,
        "locking removes the extra header and restores the saved body geometry")
    assert(#positionWrites == beforeUnlock and storedPosition.y == 0 and storedPosition.height == 1080,
        "lock-only clamping must never rewrite the preferred layout")
    PluginShutdown()

    storedPosition = { x = 200, y = 100, width = 508, height = 56 }
    dofile("main.lua")
    draw(0.05)
    assert(timerWidget.root.x == 200 and timerWidget.root.y == 100)
    assert(timerWidget.root.width == 508 and timerWidget.root.height == 56,
        "existing modal-window dimensions must survive the HUD frame change")
    assert(timerWidget.content.width == 500 and timerWidget.content.height == 48)
    assert(#positionWrites == beforeUnlock, "restyling must not rewrite saved geometry")
    PluginShutdown()

    for _, invalidSize in ipairs({
        { x = 300, y = 250, width = 339 }, { x = 300, y = 250, height = 47 },
        { x = 300, y = 250, width = "wide" }, { x = 300, y = 250, height = math.huge },
    }) do
        storedPosition = invalidSize
        local previousErrors = countMessages("Saved overlay size is invalid")
        dofile("main.lua")
        draw(0.05)
        assert(timerWidget.root.x == 300 and timerWidget.root.y == 250)
        assert(timerWidget.root.width == 500 and timerWidget.root.height == 48)
        assert(countMessages("Saved overlay size is invalid") == previousErrors + 1)
        PluginShutdown()
    end
    storedPosition = { x = 300.0, y = 250.0, width = 620.0, height = 160.0 }
    dofile("main.lua")
    draw(0.05)
    assert(timerWidget.root.x == 300 and timerWidget.root.y == 250)
    assert(timerWidget.root.width == 620 and timerWidget.root.height == 160)
    assert(math.type(timerWidget.root.width) == "integer" and math.type(timerWidget.root.height) == "integer")
    PluginShutdown()
    storedPosition = nil
end

-- Each native edge/corner resizes the same window, with responsive content and atomic layout saves.
do
    local lockVar = var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK
    local cases = {
        { key = "n", dx = 0, dy = -30, x = 300, y = 220, width = 500, height = 78, cursor = 51 },
        { key = "s", dx = 0, dy = 30, x = 300, y = 250, width = 500, height = 78, cursor = 51 },
        { key = "e", dx = 40, dy = 0, x = 300, y = 250, width = 540, height = 48, cursor = 52 },
        { key = "w", dx = -40, dy = 0, x = 260, y = 250, width = 540, height = 48, cursor = 52 },
        { key = "nw", dx = -40, dy = -30, x = 260, y = 220, width = 540, height = 78, cursor = 53 },
        { key = "ne", dx = 40, dy = -30, x = 300, y = 220, width = 540, height = 78, cursor = 54 },
        { key = "sw", dx = -40, dy = 30, x = 260, y = 250, width = 540, height = 78, cursor = 54 },
        { key = "se", dx = 40, dy = 30, x = 300, y = 250, width = 540, height = 78, cursor = 53 },
    }
    local function surface(key)
        local root = timerWidget.root
        local top = root.y - (lockVar.value == 0 and 12 or 0)
        local west, east = key:find("w", 1, true), key:find("e", 1, true)
        local north, south = key:find("n", 1, true), key:find("s", 1, true)
        local x = west and root.x - 5 or east and root.x + root.width - 5 or root.x + 5
        local y = north and top - 5 or south and root.y + root.height - 5 or top + 5
        for _, component in ipairs(components) do
            if component.alive and component.parent == pluginRoot and component.hooks[ui.Hook.ONCLICK]
                and component.x == x and component.y == y then return component end
        end
        error("missing resize surface: " .. key)
    end
    local function resize(key, dx, dy)
        local target = surface(key)
        local origin = target.xyGlobal
        local x, y = math.floor(target.width / 2), math.floor(target.height / 2)
        mousePosition = { x = (origin.x + x) * 1.25, y = (origin.y + y) * 1.25 }
        target.hooks[ui.Hook.ONCLICK](target, x, y)
        mousePosition = { x = mousePosition.x + dx * 1.25, y = mousePosition.y + dy * 1.25 }
        target.hooks[ui.Hook.ONHOLD](target, -10000, 10000)
        checkDragHeader()
        draw(0)
        return target
    end
    local function checkBars()
        local bars, previous = rectangles(), nil
        local countdown = debugLabel(6)
        local detailHeight = debugLabel(70).hidden and 0 or 76 + (debugLabel(40).hidden and 0 or 30)
        local expectedHeight = timerWidget.content.height - 12 - detailHeight
        assert(countdown.height == expectedHeight and countdown.y == 6 and countdown.alignVertical == ui.AlignMode.CENTRE)
        for _, name in ipairs({ "pre-ult", "ult", "post-ult", "tc" }) do
            local label = find("Text", name)
            assert(label.height == expectedHeight and label.y == countdown.y and label.alignVertical == ui.AlignMode.CENTRE,
                "labels and countdown must be centered inside the full resized bar height")
            if previous then assert(label.x == previous.x + previous.width + 6) end
            previous = label
        end
        assert(previous.x + previous.width == timerWidget.content.width - 6)
        assert(bars[9].width == timerWidget.content.width - 72)
        for _, bar in ipairs(bars) do
            assert(bar.height == expectedHeight and bar.y == 6, "all segmented/uniform backgrounds and fills stretch vertically")
        end
        for i = 1, 8, 2 do assert(bars[i + 1].width <= bars[i].width) end
        checkContentFit()
        checkDragHeader()
    end
    local function clickReset()
        settingsWidget.resetButton.hooks[ui.Hook.ONCLICK]()
        draw(0)
    end

    for _, case in ipairs(cases) do
        defaults()
        hideVar.value = 1
        lockVar.value = 0
        storedPreferences.debugMode, storedPreferences.onlyInArena = false, true
        storedPosition = { x = 300, y = 250 }
        dofile("main.lua")
        draw(0.05)
        local before = #positionWrites
        local handle = surface(case.key)
        assert(handle.enabled and not handle.hidden and handle.cursorConfig.mouseOverCursor == case.cursor)
        local target = resize(case.key, case.dx, case.dy)
        local root = timerWidget.root
        assert(root.x == case.x and root.y == case.y and root.width == case.width and root.height == case.height,
            "resize geometry mismatch: " .. case.key)
        assert(#positionWrites == before, "do not write layout while resizing")
        checkBars()
        target.hooks[ui.Hook.ONRELEASE](target)
        assert(#positionWrites == before + 1 and storedPosition.x == root.x and storedPosition.y == root.y)
        assert(storedPosition.width == (case.dx ~= 0 and root.width or nil))
        assert(storedPosition.height == (case.dy ~= 0 and root.height or nil))
        PluginShutdown()
        dofile("main.lua")
        draw(0.05)
        assert(timerWidget.root.width == case.width and timerWidget.root.height == case.height, "restore saved dimensions")
        lockVar.value = 1
        draw(0)
        for _, edge in ipairs(cases) do
            local locked = surface(edge.key)
            assert(locked.hidden and not locked.enabled and locked.clickthrough)
        end
        local locked = surface(case.key)
        locked.hooks[ui.Hook.ONCLICK](locked, 5, 5)
        locked.hooks[ui.Hook.ONHOLD](locked, 9999, 9999)
        assert(timerWidget.root.width == case.width and #positionWrites == before + 1)
        PluginShutdown()
    end

    defaults()
    lockVar.value = 0
    storedPreferences.debugMode, storedPreferences.removeBarSections = false, false
    storedPosition = { x = 300, y = 250, width = 500, height = 201 }
    dofile("main.lua")
    draw(0.05)
    openSettings()
    observe(100)
    observe(0)
    draw(1.25)
    local resizeElapsed, resizeStarts = lastTimerState.elapsed, starts
    assert(rectangles()[1].height == 181, "saved extra height must grow the bar, including odd heights")
    checkBars()
    setting("debugMode", true)
    assert(timerWidget.root.height == 201 and rectangles()[1].height == 105,
        "debug rows redistribute a fixed saved height without waiting for a window resize")
    checkBars()
    positionSaveOK = false
    local errorResize = resize("e", 10, 0)
    errorResize.hooks[ui.Hook.ONRELEASE](errorResize)
    draw(0)
    assert(not debugLabel(40).hidden and rectangles()[1].height == 75 and timerWidget.root.height == 201)
    checkBars()
    setting("removeBarSections", true)
    checkBars()
    positionSaveOK = true
    errorResize = resize("e", -10, 0)
    errorResize.hooks[ui.Hook.ONRELEASE](errorResize)
    draw(0)
    assert(debugLabel(40).hidden and rectangles()[9].height == 105, "clearing an error returns height to the timer row")
    checkBars()
    setting("debugMode", false)
    assert(rectangles()[9].height == 181 and timerWidget.root.height == 201)
    checkBars()
    setting("removeBarSections", false)
    local shrink = resize("s", 0, -152)
    shrink.hooks[ui.Hook.ONRELEASE](shrink)
    assert(timerWidget.root.height == 49 and rectangles()[1].height == 29)
    checkBars()
    assert(lastTimerState.elapsed == resizeElapsed and starts == resizeStarts, "resizing and centering must not affect progress")
    PluginShutdown()
    dofile("main.lua")
    draw(0.05)
    assert(timerWidget.root.height == 49 and rectangles()[1].height == 29, "restore resized bars, not just the outer frame")
    checkBars()
    PluginShutdown()

    defaults()
    lockVar.value = 0
    storedPosition = { x = 300, y = 250 }
    dofile("main.lua")
    draw(0.05)
    openSettings()
    local bottom = timerWidget.root.y + timerWidget.root.height
    local target = resize("nw", -10000, -10000)
    assert(timerWidget.root.x == 0 and timerWidget.root.y == 12 and dragHandle().y == 0,
        "north/west resizing must leave the external header on screen")
    assert(timerWidget.root.y + timerWidget.root.height == bottom, "north resizing keeps the opposite body edge fixed")
    target.hooks[ui.Hook.ONRELEASE](target)
    target = resize("se", -10000, -10000)
    assert(timerWidget.root.width == 340 and timerWidget.root.height == 48, "enforce compact readable minimum dimensions")
    target.hooks[ui.Hook.ONRELEASE](target)
    checkBars()
    target = resize("se", 10000, 10000)
    assert(timerWidget.root.x + timerWidget.root.width == pluginRoot.width)
    assert(timerWidget.root.y + timerWidget.root.height == pluginRoot.height)
    assert(timerWidget.root.height == pluginRoot.height - 12 and dragHandle().y == 0,
        "maximum unlocked height includes room for the external header")
    target.hooks[ui.Hook.ONRELEASE](target)
    checkBars()

    setting("smoothCountdown", true)
    setting("removeBarSections", true)
    setting("debugMode", true)
    observe(100)
    observe(0)
    draw(0.5)
    local elapsed, startCount, boolWrites = lastTimerState.elapsed, starts, #writes
    local priorClears = clearCalls
    clickReset()
    assert(clearCalls == priorClears + 1 and next(storedPreferences) == nil and storedPosition == nil)
    assert(#writes == boolWrites, "reset updates checkbox UI without repeated preference callbacks")
    assert(lockVar.value == 0, "reset must not alter RuneScape's interface lock")
    assert(timerWidget.root.x == 710 and timerWidget.root.y == 378)
    assert(timerWidget.root.width == 500 and timerWidget.root.height == 48)
    assert(starts == startCount and lastTimerState.elapsed == elapsed and lastTimerState.phase == "running")
    for _, option in ipairs(settingsWidget.checkbox.choices) do assert(not settingsWidget.checkbox.selected[option.value]) end
    checkContentFit()

    local beforeResetResize = #positionWrites
    target = resize("se", 150, 60)
    clickReset()
    target.hooks[ui.Hook.ONRELEASE](target)
    assert(#positionWrites == beforeResetResize and timerWidget.root.width == 500 and timerWidget.root.height == 48,
        "reset cancels a resize without saving its intermediate dimensions")
    assert(lastTimerState.elapsed == elapsed and starts == startCount)

    target = resize("e", 100, 0)
    positionSaveOK = false
    target.hooks[ui.Hook.ONRELEASE](target)
    assert(timerWidget.root.width == 600 and storedPosition == nil)
    assert(hasMessage("Overlay layout was not saved."))
    assert(not find("Text", "The layout applies for this session, but could not be saved.").hidden)
    positionSaveOK = true
    target = resize("e", 20, 0)
    target.hooks[ui.Hook.ONRELEASE](target)
    assert(storedPosition.width == 620)

    setting("smoothCountdown", true)
    clearOK = false
    local savedLayout = storedPosition
    clickReset()
    assert(storedPosition == savedLayout and storedPreferences.smoothCountdown)
    assert(not settingsWidget.checkbox.selected.smoothCountdown and timerWidget.root.width == 500)
    assert(not find("Text", "Defaults apply for this session, but could not be saved.").hidden)
    assert(lastTimerState.elapsed == elapsed and starts == startCount)
    clearOK = true
    clickReset()
    assert(storedPosition == nil and next(storedPreferences) == nil)
    local oldReset = settingsWidget.resetButton.hooks[ui.Hook.ONCLICK]
    openSettings()
    local clearsBeforeStale = clearCalls
    oldReset()
    assert(clearCalls == clearsBeforeStale, "stale Reset callbacks must not erase newer settings")
    PluginShutdown()
    lockVar.value = 1
end

-- Post-hide cooldown rejects the brief full-HP bar shown after the end-of-fight cutscene.
do
    local lockVar = var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK
    local function startVisible()
        defaults()
        npcs, currentVar.value = {}, 100
        lockVar.value = 1
        storedPosition = nil
        storedPreferences.onlyInArena, storedPreferences.debugMode = true, false
        dofile("main.lua")
        draw(0.05)
        draw(1)
        assert(not timerWidget.root.hidden and overlayOpacity() == 1)
    end
    local function hideOverlay()
        hideVar.value = 1
        draw(0.05)
        draw(5)
        draw(1)
        assert(timerWidget.root.hidden and overlayOpacity() == 0)
    end

    startVisible()
    hideOverlay()
    currentVar.value, hideVar.value = 250000, 0
    draw(1)
    assert(timerWidget.root.hidden, "full-HP pulses must not bypass the ten-second cooldown")
    hideVar.value = 1
    draw(8.99)
    assert(timerWidget.root.hidden)
    draw(0.01)
    draw(0.05)
    assert(timerWidget.root.hidden, "activity during cooldown must not queue a five-second reappearance")
    hideVar.value = 0
    draw(0.05)
    assert(not timerWidget.root.hidden and overlayOpacity() == 0, "fresh activity can reveal the overlay after cooldown")
    draw(1)

    hideOverlay()
    hideVar.value = 0
    draw(9.99)
    assert(timerWidget.root.hidden, "never reactivate before ten full seconds")
    hideVar.value = 1
    draw(0.01)
    assert(timerWidget.root.hidden, "a cached pre-expiry HP sample must not reactivate the overlay")
    draw(0.05)
    assert(timerWidget.root.hidden)
    hideVar.value = 0
    draw(0.05)
    draw(1)
    hideOverlay()
    hideVar.value = 0
    draw(9.5)
    draw(0.49)
    assert(timerWidget.root.hidden)
    draw(0.01)
    draw(0.05)
    assert(not timerWidget.root.hidden, "resume on the first fresh sample after the cooldown")
    draw(1)

    emit("GameStateChanged", { newState = GameState.LOADING })
    local queriesDuringCutscene = activityQueries
    draw(5)
    assert(activityQueries == queriesDuringCutscene, "cooldown time advances without monitoring inactive game state")
    emit("GameStateChanged", { newState = GameState.GAME })
    draw(0.05)
    assert(timerWidget.root.hidden, "unloading a visible overlay starts cooldown across the cutscene")
    draw(4.94)
    assert(timerWidget.root.hidden)
    hideVar.value = 1
    draw(0.01)
    draw(0.05)
    assert(timerWidget.root.hidden, "a cutscene HP pulse must not leave pending visibility")
    hideVar.value = 0
    draw(0.05)
    draw(1)
    hideOverlay()
    lockVar.value = 0
    draw(0)
    assert(not timerWidget.root.hidden and overlayOpacity() == 1, "editing bypasses the automatic cooldown")
    lockVar.value = 1
    draw(0)
    draw(1)
    setting("onlyInArena", false)
    draw(1)
    assert(not timerWidget.root.hidden and overlayOpacity() == 1, "always-visible mode bypasses cooldown")
    PluginShutdown()

    startVisible()
    hideOverlay()
    local startsBeforeCooldown = starts
    defaults()
    observe(100)
    observe(0)
    draw(5)
    assert(timerWidget.root.hidden and starts == startsBeforeCooldown + 1)
    close(lastTimerState.elapsed, 5)
    draw(5)
    assert(not timerWidget.root.hidden and lastTimerState.phase == "running")
    close(lastTimerState.elapsed, 10)
    PluginShutdown()
end

forceMissingFrame = "topRight"
dofile("main.lua")
local frameOK, frameError = pcall(draw, 0.05)
assert(not frameOK and tostring(frameError):find("topRight", 1, true))
assert(timerWidget.destroyCalls == 1, "an unsupported frame must not leak its wrapper")
PluginShutdown()
forceMissingFrame = nil

forceMissingScrollClickthrough = true
dofile("main.lua")
local scrollOK, scrollError = pcall(draw, 0.05)
assert(not scrollOK and tostring(scrollError):find("scroll controller", 1, true))
assert(timerWidget.destroyCalls == 1, "an unsupported scroll controller must not leak its wrapper")
PluginShutdown()
forceMissingScrollClickthrough = false

-- Refuse unsafe custom bar allocation instead of using newer, absent library APIs.
forceContentCategory = 7
dofile("main.lua")
local ok, categoryError = pcall(draw, 0.05)
assert(not ok and tostring(categoryError):find("category-zero", 1, true))
assert(timerWidget.destroyCalls == 1)
PluginShutdown()
for _, widget in ipairs(widgets) do assert(widget.destroyCalls == 1) end
for _, component in ipairs(components) do assert(not component.alive, "release hidden popout surfaces and header children too") end
Timer.start = originalStart
Detector.new = originalNewDetector
print = originalPrint
print("main_test.lua: passed")
