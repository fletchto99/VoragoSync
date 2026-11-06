local Timer = require("src/timer")
local HealthProbe = require("src/health_probe")
local Detector = require("src/detector")
local Encounter = require("src/encounter")
local Build = require("src/build")

local App = {}

function App.start()
    assert(type(Build.isDevBuild) == "boolean", "VoragoSync: build.isDevBuild must be a boolean")
    assert(type(prettyui) == "table" and type(prettyui.Panel) == "table"
        and type(prettyui.Panel.new) == "function" and type(prettyui.Panel.AddText) == "function"
        and type(prettyui.SimpleView) == "table" and type(prettyui.SimpleView.new) == "function"
        and type(prettyui.SimpleView.AddCheckboxButton) == "function"
        and type(prettyui.SimpleView.AddSimpleButton) == "function",
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
    local interfaceLocked, lastInterfaceLockError = true, nil
    local visibilityGraceRemaining, visibilityWasActive = 0, false
    local visibilityGraceSeconds = 5
    local reappearCooldown, visibilityNeedsSample = 0, false
    local reappearCooldownSeconds = 10
    local fadeSeconds = 1
    local view, settingsView = nil, nil
    local position = nil
    local preferredWidth, preferredHeight = nil, nil
    local inGame, waitingForUI = true, false
    local notice = ""
    local eventRef = "VoragoSync"
    local contentWidth, compactHeight, debugHeight = 492, 40, 116
    local border = 4
    local frameSize = border * 2
    local padding, countdownX, countdownWidth = 6, 4, 56
    local barStart = countdownX + countdownWidth + padding
    local sectionWeights, sectionGap = { 160, 54, 116, 54 }, 6
    local totalSectionWeight = 0
    for _, weight in ipairs(sectionWeights) do totalSectionWeight = totalSectionWeight + weight end
    local totalSectionGaps = sectionGap * (#sectionWeights - 1)
    local minimumWidth, handleHeight, resizeInset = 340, 12, 5
    local resizeEdges = {
        { key = "n", north = true, cursor = "TOPLEVEL_V2_SCALE_VERT" },
        { key = "s", south = true, cursor = "TOPLEVEL_V2_SCALE_VERT" },
        { key = "e", east = true, cursor = "TOPLEVEL_V2_SCALE_HORZ" },
        { key = "w", west = true, cursor = "TOPLEVEL_V2_SCALE_HORZ" },
        { key = "nw", north = true, west = true, cursor = "TOPLEVEL_V2_SCALE_DIAG_1" },
        { key = "ne", north = true, east = true, cursor = "TOPLEVEL_V2_SCALE_DIAG_2" },
        { key = "sw", south = true, west = true, cursor = "TOPLEVEL_V2_SCALE_DIAG_2" },
        { key = "se", south = true, east = true, cursor = "TOPLEVEL_V2_SCALE_DIAG_1" },
    }

    local function report(message)
        notice = message
        print("[VoragoSync] " .. message)
    end

    local function finite(value)
        return type(value) == "number" and value > -math.huge and value < math.huge
    end

    local function readInterfaceLock()
        local ok, value = pcall(function()
            local lock = var and var.VarPlayer and var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK
            return lock and lock.value
        end)
        if ok and (value == 0 or value == 1) then
            interfaceLocked, lastInterfaceLockError = value == 1, nil
        else
            interfaceLocked = true
            local message = "Interface lock state unavailable; dragging disabled."
            if not ok then message = message .. " " .. tostring(value) end
            if message ~= lastInterfaceLockError then print("[VoragoSync] " .. message) end
            lastInterfaceLockError = message
        end
    end

    local savedPosition = PersistentDB:GetStructuredData("overlayPosition")
    if savedPosition ~= nil then
        if type(savedPosition) == "table" and finite(savedPosition.x) and finite(savedPosition.y)
            and savedPosition.x >= 0 and savedPosition.y >= 0
            and savedPosition.x % 1 == 0 and savedPosition.y % 1 == 0 then
            position = { x = savedPosition.x, y = savedPosition.y }
            local width, height = savedPosition.width, savedPosition.height
            if (width == nil or (finite(width) and width % 1 == 0 and width >= minimumWidth))
                and (height == nil or (finite(height) and height % 1 == 0 and height >= compactHeight + frameSize)) then
                preferredWidth = width and math.floor(width) or nil
                preferredHeight = height and math.floor(height) or nil
            else
                report("Saved overlay size is invalid; using the default size.")
            end
        else
            report("Saved overlay position is invalid; using the default location.")
        end
    end

    local function resetDetection()
        Detector.reset(detector)
        sinceSample = Detector.pollInterval
        latestReading, lastMonitorError = nil, nil
        latestEncounter, encounterIdentity = nil, nil
        visibilityGraceRemaining, visibilityWasActive = 0, false
        interfaceLocked = true
    end

    local function startVisibilityCooldown()
        reappearCooldown, visibilityNeedsSample = reappearCooldownSeconds, true
        visibilityGraceRemaining, visibilityWasActive = 0, false
    end

    local function startCountdown()
        if state.phase ~= "idle" then return end
        Detector.reset(detector)
        Timer.start(state)
        print("[VoragoSync] Vorago positive HP -> 0: started 24-second countdown.")
    end

    local function monitor(deltaSeconds)
        sinceSample = sinceSample + deltaSeconds
        if sinceSample < Detector.pollInterval then return false end
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
            return true
        end
        if encounterIdentity ~= latestEncounter.identity then
            Detector.reset(detector)
            encounterIdentity = latestEncounter.identity
        end
        local busy = state.phase ~= "idle"
        if Detector.observe(detector, latestReading, busy, gap) then
            startCountdown()
        end
        return true
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
        if old then
            if old.wasVisible and old.locked == true and preferences.onlyInArena then startVisibilityCooldown() end
            old.drag = nil
            for _, surface in ipairs(old.inputSurfaces or {}) do
                if liveRoot(surface.owner) then surface.component:Destroy() end
            end
            if liveRoot(old.dragHandleOwner) then old.dragHandle:Destroy() end
            old.widget:Destroy()
        end
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

    local function fadeComponent(component)
        view.fadeComponents[#view.fadeComponents + 1] = { component = component, alpha = component.alpha }
        component.alpha, component.clickthrough = 0, true
        return component
    end

    local function text(widget, value, x, y, width, height, colour)
        return fadeComponent(widget:AddText({
            text = value, x = x, y = y, width = width, height = height,
            alignHorizontal = ui.AlignMode.CENTRE, alignVertical = ui.AlignMode.CENTRE, maxLines = 1, colour = colour,
        }))
    end

    local function rectangle(parent, x, y, width, colour)
        local component = ui.Rectangle.new(parent)
        component:SetPos(x, y)
        component:SetSize(width, 28)
        component.colour, component.fill = colour, true
        return fadeComponent(component)
    end

    local function placeAt(owner, x, y)
        local root, parent = owner.widget.root, owner.parent
        local top = interfaceLocked and 0 or handleHeight
        x = math.floor(math.max(0, math.min(math.max(0, parent.width - root.width), x)) + 0.5)
        y = math.floor(math.max(top, math.min(math.max(top, parent.height - root.height), y)) + 0.5)
        if root.x ~= x or root.y ~= y then root:SetPos(x, y) end
    end

    local function fitInputSurfaces(owner)
        local root = owner.widget.root
        owner.locked = interfaceLocked
        local top = root.y - (interfaceLocked and 0 or handleHeight)
        local height = root.height + root.y - top
        owner.dragHandle:SetPos(root.x, root.y - handleHeight)
        owner.dragHandle:SetSize(root.width, handleHeight)
        owner.dragHandle.hidden = interfaceLocked
        owner.headerFill:SetWidth(root.width - frameSize)
        owner.headerTop:SetWidth(root.width - frameSize)
        owner.headerRight:SetPos(root.width - border, border)
        owner.headerTopRight:SetPos(root.width - border, 0)
        for _, surface in ipairs(owner.inputSurfaces) do
            local component, edge = surface.component, surface.edge
            local active = owner.drag and owner.drag.surface == surface
            local enabled = not interfaceLocked and (not owner.drag or active)
            component.hidden, component.enabled, component.clickthrough = not enabled, enabled, not enabled
            if active then
                component:SetPos(0, 0)
                component:SetSize(owner.parent.width, owner.parent.height)
            elseif edge then
                component:SetPos(edge.west and root.x - resizeInset or edge.east and root.x + root.width - resizeInset or root.x + resizeInset,
                    edge.north and top - resizeInset or edge.south and top + height - resizeInset or top + resizeInset)
                component:SetSize((edge.west or edge.east) and resizeInset * 2 or root.width - resizeInset * 2,
                    (edge.north or edge.south) and resizeInset * 2 or height - resizeInset * 2)
            else
                component:SetPos(root.x + resizeInset, root.y - handleHeight + resizeInset)
                component:SetSize(root.width - resizeInset * 2, handleHeight - resizeInset)
            end
        end
    end

    local function readMouse()
        local mouse = Mouse and type(Mouse.GetPosition) == "function" and Mouse.GetPosition() or nil
        if mouse == nil or not finite(mouse.x) or not finite(mouse.y) then
            report("Mouse position is unavailable.")
            return nil
        end
        return mouse
    end

    local function finishDrag(owner, save)
        local drag = owner.drag
        owner.drag = nil
        if view ~= owner or liveRoot(owner) == nil then return false end
        if drag and save and drag.moved then
            local root = owner.widget.root
            placeAt(owner, root.x, root.y)
            position = { x = root.x, y = root.y }
            if drag.surface.edge then
                local edge = drag.surface.edge
                if edge.west or edge.east then preferredWidth = root.width end
                if edge.north or edge.south then preferredHeight = root.height end
            end
            local layout = { x = position.x, y = position.y, width = preferredWidth, height = preferredHeight }
            if not PersistentDB:SetStructuredData("overlayPosition", layout) then
                report("Overlay layout was not saved.")
                if settingsView and liveRoot(settingsView) then
                    settingsView.message.content = "The layout applies for this session, but could not be saved."
                end
            elseif notice == "Overlay layout was not saved." then
                notice = ""
                if settingsView and liveRoot(settingsView)
                    and settingsView.message.content == "The layout applies for this session, but could not be saved." then
                    settingsView.message.content = ""
                end
            end
        end
        fitInputSurfaces(owner)
        return false
    end

    local function updatePlacement()
        local root, parent = view.widget.root, view.parent
        local resized = view.parentWidth ~= parent.width or view.parentHeight ~= parent.height
            or view.windowWidth ~= root.width or view.windowHeight ~= root.height
        local lockChanged = view.locked ~= interfaceLocked
        if not view.drag then
            placeAt(view, position and position.x or (parent.width - root.width) / 2,
                position and position.y or parent.height * 0.35)
        end
        if resized or view.dragHandle.x ~= root.x or view.dragHandle.y ~= root.y - handleHeight
            or lockChanged then
            fitInputSurfaces(view)
        end
        view.parentWidth, view.parentHeight = parent.width, parent.height
        view.windowWidth, view.windowHeight = root.width, root.height
        if lockChanged and not view.locked then
            view.dragHandle:MoveToFront()
            for _, surface in ipairs(view.inputSurfaces) do surface.component:MoveToFront() end
        end
    end

    local function resizeAxis(start, size, delta, leading, trailing, extent, minimum)
        if leading then
            local far = math.max(minimum, math.min(start + size, extent))
            local near = math.max(0, math.min(far - minimum, start + delta))
            return near, far - near
        elseif trailing then
            local near = math.max(0, math.min(start, math.max(0, extent - minimum)))
            return near, math.max(minimum, math.min(size + delta, math.max(minimum, extent - near)))
        end
        return start, size
    end

    local function createInputSurface(owner, edge)
        local component = ui.Layer.new(owner.parent)
        local surface = { component = component, owner = own({ root = component }), edge = edge }
        owner.inputSurfaces[#owner.inputSurfaces + 1] = surface
        component.hidden, component.enabled, component.clickthrough = true, false, true
        local cursorName = edge and edge.cursor or "TOPLEVEL_V2_MOVE"
        local ok, cursorID = pcall(function() return config.Cursor[cursorName].id end)
        if ok and finite(cursorID) and cursorID >= 0 and cursorID % 1 == 0 then
            component.cursorConfig.mouseOverCursor = cursorID
            component.opConfig:SetOpCursor(0, cursorID)
        else
            report("RuneScape cursor unavailable: " .. cursorName)
        end
        component:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
            if view ~= owner or liveRoot(owner) == nil or owner.drag then return false end
            readInterfaceLock()
            if interfaceLocked then return false end
            local mouse = readMouse()
            if mouse == nil then return false end
            local origin = component.xyGlobal
            if not finite(x) or not finite(y) or origin == nil or not finite(origin.x) or not finite(origin.y) then
                report("Drag coordinates are unavailable.")
                return false
            end
            -- Calibrate before expanding capture changes the native hook coordinate origin.
            local uiX, uiY = origin.x + x, origin.y + y
            local useX = math.abs(uiX) >= math.abs(uiY)
            local coordinate, pixels = useX and uiX or uiY, useX and mouse.x or mouse.y
            if coordinate == 0 then
                report("Drag scale is unavailable; grab the overlay away from the screen's top-left corner.")
                return false
            end
            local scale = pixels / coordinate
            if not finite(scale) or scale <= 0 then
                report("Drag scale is unavailable.")
                return false
            end
            local root = owner.widget.root
            owner.drag = {
                x = root.x, y = root.y, width = root.width, height = root.height,
                pointerX = mouse.x, pointerY = mouse.y, scale = scale, surface = surface,
            }
            fitInputSurfaces(owner)
            root:MoveToFront()
            owner.dragHandle:MoveToFront()
            component:MoveToFront()
            return false
        end)
        component:Subscribe(ui.Hook.ONHOLD, function()
            if view ~= owner or liveRoot(owner) == nil or not owner.drag or owner.drag.surface ~= surface then return false end
            readInterfaceLock()
            if interfaceLocked then return finishDrag(owner, lastInterfaceLockError == nil) end
            local mouse = readMouse()
            if mouse == nil then return finishDrag(owner, false) end
            local drag, root = owner.drag, owner.widget.root
            local dx = math.floor((mouse.x - drag.pointerX) / drag.scale + 0.5)
            local dy = math.floor((mouse.y - drag.pointerY) / drag.scale + 0.5)
            if edge then
                local x, width = resizeAxis(drag.x, drag.width, dx, edge.west, edge.east, owner.parent.width, minimumWidth)
                local y, height = resizeAxis(drag.y - handleHeight, drag.height, dy, edge.north, edge.south,
                    owner.parent.height - handleHeight, owner.minimumHeight)
                owner.widget:SetSize(width, height)
                placeAt(owner, x, y + handleHeight)
            else
                placeAt(owner, drag.x + dx, drag.y + dy)
            end
            drag.moved = root.x ~= drag.x or root.y ~= drag.y
                or (edge ~= nil and (root.width ~= drag.width or root.height ~= drag.height))
            fitInputSurfaces(owner)
            return false
        end)
        local function release()
            if view ~= owner or liveRoot(owner) == nil or not owner.drag or owner.drag.surface ~= surface then return false end
            readInterfaceLock()
            return finishDrag(owner, lastInterfaceLockError == nil)
        end
        component:Subscribe(ui.Hook.ONRELEASE, release)
        component:Subscribe(ui.Hook.ONDRAGCOMPLETE, release)
    end

    local function layoutView()
        local root, parent = view.widget.root, view.parent
        local errorHeight = view.showError and 30 or 0
        local detailHeight = (view.debugMode and debugHeight - compactHeight or 0) + errorHeight
        local minimumHeight = (view.debugMode and debugHeight or compactHeight) + errorHeight + frameSize
        view.minimumHeight, view.widget.minHeight = minimumHeight, minimumHeight
        local width = view.drag and root.width or (preferredWidth or contentWidth + frameSize)
        local height = view.drag and root.height or (preferredHeight or minimumHeight)
        width = math.max(minimumWidth, math.min(width, parent.width))
        height = math.max(minimumHeight, math.min(height, parent.height - (interfaceLocked and 0 or handleHeight)))
        if root.width ~= width or root.height ~= height then view.widget:SetSize(width, height) end
        local innerWidth, innerHeight = width - frameSize, height - frameSize
        if view.layoutWidth ~= innerWidth or view.layoutHeight ~= innerHeight or view.layoutDetailHeight ~= detailHeight then
            view.layoutWidth, view.layoutHeight, view.layoutDetailHeight = innerWidth, innerHeight, detailHeight
            view.widget.dock.scroll:SetContentHeight(innerHeight)
            view.widget.overlay.scroll:SetContentHeight(innerHeight)
            local barHeight = innerHeight - padding * 2 - detailHeight
            local detailY = barHeight + padding * 2
            view.countdown:SetSize(countdownWidth, barHeight)
            local previous, total, x = 0, 0, barStart
            view.barWidth = innerWidth - barStart - padding
            for i, section in ipairs(view.sections) do
                total = total + sectionWeights[i]
                local edge = math.floor((view.barWidth - totalSectionGaps) * total / totalSectionWeight + 0.5)
                section.width = edge - previous
                section.background:SetPos(x, padding)
                section.background:SetSize(section.width, barHeight)
                section.fill:SetPos(x, padding)
                section.fill:SetHeight(barHeight)
                section.label:SetPos(x, padding)
                section.label:SetSize(section.width, barHeight)
                section.lastWidth = nil
                x, previous = x + section.width + sectionGap, edge
            end
            view.uniformBackground:SetSize(view.barWidth, barHeight)
            view.uniformFill:SetHeight(barHeight)
            view.lastUniformWidth = nil
            view.error:SetPos(padding, detailY)
            view.error:SetWidth(innerWidth - padding * 2)
            view.activity:SetPos(padding, detailY + errorHeight)
            view.hp:SetPos(padding, detailY + 24 + errorHeight)
            view.armed:SetPos(padding, detailY + 48 + errorHeight)
            view.activity:SetWidth(innerWidth - padding * 2)
            view.hp:SetWidth(innerWidth - padding * 2)
            view.armed:SetWidth(innerWidth - padding * 2)
        end
    end

    local function createView(parent)
        local height = preferences.debugMode and debugHeight or compactHeight
        -- flowManaged disables Panel's implicit Alt-drag; native lock controls our input surfaces.
        local widget = prettyui.Panel.new(parent, {
            x = 0, y = 0,
            width = contentWidth + frameSize, height = height + frameSize, minWidth = minimumWidth, minHeight = compactHeight + frameSize,
            scrollable = false, resizable = false, popout = false, contentHeight = height, layout = { padding = 0 },
        }, true)
        checkContentHost(widget)
        for _, name in ipairs({ "dock", "overlay" }) do
            local surface = widget[name]
            if type(surface) ~= "table" or surface.container == nil or type(surface.scroll) ~= "table"
                or type(surface.scroll.SetClickthrough) ~= "function" or type(surface.scroll.SetContentHeight) ~= "function" then
                widget:Destroy()
                error("VoragoSync requires PrettyUI's panel scroll controller APIs (verified with 1.2.0)")
            end
            surface.root.clickthrough, surface.container.clickthrough, surface.container.enabled = true, true, false
            surface.scroll:SetClickthrough(true)
        end
        view = own(widget)
        view.parent = parent
        view.opacity, view.wasVisible, view.fadeComponents = 0, false, {}
        -- Layer alpha does not fade its children; include PrettyUI's visible frame sprites.
        for _, name in ipairs({
            "background", "left", "right", "bottom", "bottomLeft",
            "bottomRight", "top", "topLeft", "topRight",
        }) do
            if widget.dock[name] == nil then
                destroyView()
                error("VoragoSync requires PrettyUI's " .. name .. " handle to fade the HUD frame")
            end
            fadeComponent(widget.dock[name])
        end
        view.sections = {}
        view.countdown = text(widget, "0.0s", countdownX, padding, countdownWidth, 28)
        local background = Vector4.new(0.06, 0.05, 0.03, 1)
        local accent = Vector4.new(0.83, 0.60, 0.10, 1)
        local x = barStart
        for i, section in ipairs(Timer.sections) do
            local width = sectionWeights[i]
            view.sections[i] = {
                background = rectangle(widget.content, x, padding, width, background),
                fill = rectangle(widget.content, x, padding, 0, accent),
                label = text(widget, section.label, x, padding, width, 28, 0xFFFFFFFF),
                width = width,
            }
            x = x + width + sectionGap
        end
        view.barWidth = x - barStart - sectionGap
        view.uniformBackground = rectangle(widget.content, barStart, padding, view.barWidth, background)
        view.uniformFill = rectangle(widget.content, barStart, padding, 0, accent)
        view.error = text(widget, "", padding, 40, 480, 24, 0xFFB0A8FF)
        view.activity = text(widget, "", padding, 70, 480, 22)
        view.hp = text(widget, "", padding, 94, 480, 22)
        view.armed = text(widget, "", padding, 118, 480, 22)
        local sprites = prettyui.Sprites and prettyui.Sprites.HUD_WINDOW
        for _, name in ipairs({ "top", "side", "cornerTop" }) do
            if type(sprites) ~= "table" or type(sprites[name]) ~= "number" then
                destroyView()
                error("VoragoSync requires PrettyUI's HUD frame sprites for its drag handle")
            end
        end
        view.dragHandle = ui.Layer.new(parent)
        view.dragHandleOwner = own({ root = view.dragHandle })
        view.dragHandle.clickthrough, view.dragHandle.hidden = true, true
        view.headerFill = ui.Rectangle.new(view.dragHandle)
        view.headerFill:SetPos(border, border)
        view.headerFill:SetSize(widget.root.width - frameSize, handleHeight - border)
        view.headerFill.colour, view.headerFill.fill, view.headerFill.clickthrough = Vector4.new(49 / 255, 31 / 255, 18 / 255, 1), true, true
        local function headerSprite(spriteID, x, y, width, height, flipped)
            local component = ui.Sprite.new(view.dragHandle)
            component.spriteID, component.clickthrough, component.isTiling = spriteID, true, true
            component.isFlippedHorizontally = flipped == true
            component:SetPos(x, y)
            component:SetSize(width, height)
            return component
        end
        -- Share the panel's top border as the separator instead of doubling the gold trim.
        view.headerTop = headerSprite(sprites.top, border, 0, widget.root.width - frameSize, border)
        headerSprite(sprites.cornerTop, 0, 0, border, border)
        view.headerTopRight = headerSprite(sprites.cornerTop, widget.root.width - border, 0, border, border, true)
        headerSprite(sprites.side, 0, border, border, handleHeight - border)
        view.headerRight = headerSprite(sprites.side, widget.root.width - border, border, border, handleHeight - border, true)
        view.inputSurfaces = {}
        createInputSurface(view)
        for _, edge in ipairs(resizeEdges) do createInputSurface(view, edge) end
        fitInputSurfaces(view)
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
        owner.checkbox = widget:AddCheckboxButton(choices, {
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
                elseif notice ~= "Overlay layout was not saved." then
                    notice = ""
                    owner.message.content = ""
                end
            end,
        })
        owner.resetButton = widget:AddSimpleButton("Reset to defaults", function()
            if settingsView ~= owner then return end
            if view and view.drag then finishDrag(view, false) end
            position, preferredWidth, preferredHeight = nil, nil, nil
            preferences.debugMode = false
            for _, option in ipairs(settingOptions) do
                preferences[option.key] = false
                owner.checkbox:SetSelected(option.key, false, false)
            end
            notice = ""
            if not PersistentDB:Clear() then
                report("Default settings could not be saved.")
                owner.message.content = "Defaults apply for this session, but could not be saved."
            else
                owner.message.content = ""
            end
        end, { width = 160 })
        owner.message = widget:AddText({ text = notice, height = 48, maxLines = 2 })
    end

    local function displayNumber(value)
        if value == nil then return "--" end
        return (string.format("%.0f", value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end

    local function armedStatus()
        if state.phase ~= "idle" then return "Armed: no - countdown/hold active" end
        if latestEncounter and not latestEncounter.valid then return "Armed: no - " .. latestEncounter.status end
        if detector.positive then return "Armed: Vorago HP" end
        return "Armed: no - waiting for a fresh observation"
    end

    local function render(deltaSeconds, sampled)
        if view.drag and (interfaceLocked or view.parentWidth ~= view.parent.width or view.parentHeight ~= view.parent.height) then
            finishDrag(view, lastInterfaceLockError == nil)
        end
        local active = state.phase ~= "idle"
            or (latestReading ~= nil and latestReading.valid and latestReading.name:lower() == "vorago"
                and latestReading.current > 0)
        -- Start a full grace period when inactivity is observed, including after a long frame.
        local suppressed = reappearCooldown > 0 or (visibilityNeedsSample and not sampled)
        if suppressed then
            visibilityGraceRemaining, visibilityWasActive = 0, false
        elseif active or visibilityWasActive then
            visibilityGraceRemaining = visibilityGraceSeconds
        else
            visibilityGraceRemaining = math.max(0, visibilityGraceRemaining - deltaSeconds)
        end
        if not suppressed then
            visibilityNeedsSample, visibilityWasActive = false, active
        end
        local unlocked = not interfaceLocked
        local targetHidden = not unlocked and preferences.onlyInArena and (suppressed or visibilityGraceRemaining == 0)
        local opacity = view.opacity
        if unlocked then
            view.targetHidden, opacity = false, 1
        elseif view.targetHidden ~= targetHidden then
            view.targetHidden = targetHidden
        else
            local direction = targetHidden and -1 or 1
            opacity = math.max(0, math.min(1, view.opacity + direction * deltaSeconds / fadeSeconds))
        end
        if view.opacity ~= opacity then
            for _, target in ipairs(view.fadeComponents) do
                target.component.alpha = target.alpha * opacity
            end
            view.opacity = opacity
        end
        local hidden = targetHidden and view.opacity == 0
        if not hidden and view.opacity > 0 then view.wasVisible = true end
        if view.hidden ~= hidden then
            if hidden and view.wasVisible and preferences.onlyInArena and interfaceLocked then startVisibilityCooldown() end
            if hidden then view.wasVisible = false end
            view.widget.root.hidden, view.hidden = hidden, hidden
        end
        if view.debugMode ~= preferences.debugMode then
            view.debugMode = preferences.debugMode
            view.activity.hidden, view.hp.hidden, view.armed.hidden = not view.debugMode, not view.debugMode, not view.debugMode
        end
        if view.removeSections ~= preferences.removeBarSections then
            view.removeSections = preferences.removeBarSections
            for _, section in ipairs(view.sections) do
                section.background.hidden, section.fill.hidden, section.label.hidden = view.removeSections, view.removeSections, view.removeSections
            end
            view.uniformBackground.hidden, view.uniformFill.hidden = not view.removeSections, not view.removeSections
        end

        local failed = latestEncounter and latestEncounter.error and latestEncounter
            or (latestReading and latestReading.error and latestReading or nil)
        local message = notice ~= "" and notice or lastInterfaceLockError or (failed and ("Monitor: " .. failed.status) or "")
        if message ~= view.lastError then
            view.error.content, view.lastError = message, message
        end
        local showError = view.debugMode and message ~= ""
        if view.showError ~= showError then
            view.error.hidden, view.showError = not showError, showError
        end
        layoutView()

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
        updatePlacement()
    end

    Event.SettingsLayerReady.Subscribe(eventRef, showSettings)
    Event.Draw.Subscribe(eventRef, function(event)
        if reappearCooldown > 0 then
            assert(finite(event.timeDeltaSecs) and event.timeDeltaSecs >= 0,
                "VoragoSync: frame delta must be a finite non-negative number")
            reappearCooldown = math.max(0, reappearCooldown - event.timeDeltaSecs)
        end
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
        readInterfaceLock()
        Timer.update(state, event.timeDeltaSecs)
        local sampled = monitor(event.timeDeltaSecs)
        render(event.timeDeltaSecs, sampled)
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
