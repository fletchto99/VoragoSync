local Timer = require("src/timer")
local UI = require("src/ui_helpers")

local Overlay = {}

function Overlay.new(preferences, savedPosition, report, saveLayout)
    local interfaceLocked, lastInterfaceLockError = true, nil
    local view = nil
    local position = nil
    local preferredWidth, preferredHeight = nil, nil
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
                report("layout", "Saved overlay size is invalid; using the default size.")
            end
        else
            report("layout", "Saved overlay position is invalid; using the default location.")
        end
    end

    local function destroyView()
        local old = view
        view, interfaceLocked = nil, true
        if old then
            old.drag = nil
            for _, surface in ipairs(old.inputSurfaces or {}) do
                if UI.liveRoot(surface.owner) then surface.component:Destroy() end
            end
            if UI.liveRoot(old.dragHandleOwner) then old.dragHandle:Destroy() end
            old.widget:Destroy()
            -- Visibility teardown needs the surface's lock state before the lifecycle reset.
            return old.locked == true
        end
        return false
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
            report("input", "Mouse position is unavailable.")
            return nil
        end
        return mouse
    end

    local function finishDrag(owner, save)
        local drag = owner.drag
        owner.drag = nil
        if view ~= owner or UI.liveRoot(owner) == nil then return false end
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
            saveLayout(layout)
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
        local surface = { component = component, owner = UI.own({ root = component }), edge = edge }
        owner.inputSurfaces[#owner.inputSurfaces + 1] = surface
        component.hidden, component.enabled, component.clickthrough = true, false, true
        local cursorName = edge and edge.cursor or "TOPLEVEL_V2_MOVE"
        local ok, cursorID = pcall(function() return config.Cursor[cursorName].id end)
        if ok and finite(cursorID) and cursorID >= 0 and cursorID % 1 == 0 then
            component.cursorConfig.mouseOverCursor = cursorID
            component.opConfig:SetOpCursor(0, cursorID)
        else
            report("cursor", "RuneScape cursor unavailable: " .. cursorName)
        end
        component:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
            if view ~= owner or UI.liveRoot(owner) == nil or owner.drag then return false end
            readInterfaceLock()
            if interfaceLocked then return false end
            local mouse = readMouse()
            if mouse == nil then return false end
            local origin = component.xyGlobal
            if not finite(x) or not finite(y) or origin == nil or not finite(origin.x) or not finite(origin.y) then
                report("input", "Drag coordinates are unavailable.")
                return false
            end
            -- Calibrate before expanding capture changes the native hook coordinate origin.
            local uiX, uiY = origin.x + x, origin.y + y
            local useX = math.abs(uiX) >= math.abs(uiY)
            local coordinate, pixels = useX and uiX or uiY, useX and mouse.x or mouse.y
            if coordinate == 0 then
                report("input", "Drag scale is unavailable; grab the overlay away from the screen's top-left corner.")
                return false
            end
            local scale = pixels / coordinate
            if not finite(scale) or scale <= 0 then
                report("input", "Drag scale is unavailable.")
                return false
            end
            local root = owner.widget.root
            owner.drag = {
                x = root.x, y = root.y, width = root.width, height = root.height,
                pointerX = mouse.x, pointerY = mouse.y, scale = scale, surface = surface,
            }
            report("input", nil)
            fitInputSurfaces(owner)
            root:MoveToFront()
            owner.dragHandle:MoveToFront()
            component:MoveToFront()
            return false
        end)
        component:Subscribe(ui.Hook.ONHOLD, function()
            if view ~= owner or UI.liveRoot(owner) == nil or not owner.drag or owner.drag.surface ~= surface then return false end
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
            if view ~= owner or UI.liveRoot(owner) == nil or not owner.drag or owner.drag.surface ~= surface then return false end
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
        report("cursor", nil)
        local height = preferences.debugMode and debugHeight or compactHeight
        -- flowManaged disables Panel's implicit Alt-drag; native lock controls our input surfaces.
        local widget = prettyui.Panel.new(parent, {
            x = 0, y = 0,
            width = contentWidth + frameSize, height = height + frameSize, minWidth = minimumWidth, minHeight = compactHeight + frameSize,
            scrollable = false, resizable = false, popout = false, contentHeight = height, layout = { padding = 0 },
        }, true)
        UI.checkContentHost(widget)
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
        view = UI.own(widget)
        view.parent = parent
        view.opacity, view.fadeComponents = 0, {}
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
        view.dragHandleOwner = UI.own({ root = view.dragHandle })
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

    local function displayNumber(value)
        if value == nil then return "--" end
        return (string.format("%.0f", value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end

    local function render(model)
        local state, latestReading = model.timer, model.reading
        local opacity, hidden = model.visibility.opacity, model.visibility.hidden
        if view.opacity ~= opacity then
            for _, target in ipairs(view.fadeComponents) do
                target.component.alpha = target.alpha * opacity
            end
            view.opacity = opacity
        end
        if view.hidden ~= hidden then
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

        local message = model.error
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
            local armed = model.armed
            if activity ~= view.lastActivity then view.activity.content, view.lastActivity = activity, activity end
            if hp ~= view.lastHP then view.hp.content, view.lastHP = hp, hp end
            if armed ~= view.lastArmed then view.armed.content, view.lastArmed = armed, armed end
        end
        updatePlacement()
    end

    return {
        create = createView,
        destroy = destroyView,
        render = render,
        hasView = function() return view ~= nil end,
        isLive = function() return UI.liveRoot(view) ~= nil end,
        getLock = function() return interfaceLocked, lastInterfaceLockError end,
        prepare = function()
            readInterfaceLock()
            if view.drag and (interfaceLocked or view.parentWidth ~= view.parent.width or view.parentHeight ~= view.parent.height) then
                finishDrag(view, lastInterfaceLockError == nil)
            end
        end,
        resetLayout = function()
            if view and view.drag then finishDrag(view, false) end
            position, preferredWidth, preferredHeight = nil, nil, nil
        end,
    }
end

return Overlay
