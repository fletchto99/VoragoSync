local UI = {}

function UI.requirePrettyUI()
    assert(type(prettyui) == "table" and type(prettyui.Panel) == "table"
        and type(prettyui.Panel.new) == "function" and type(prettyui.Panel.AddText) == "function"
        and type(prettyui.SimpleView) == "table" and type(prettyui.SimpleView.new) == "function"
        and type(prettyui.SimpleView.AddCheckboxButton) == "function"
        and type(prettyui.SimpleView.AddSimpleButton) == "function",
        "VoragoSync requires PrettyUI (mod.io 6398181); install it and refresh plugin.json dependencies")
end

function UI.own(widget)
    local root = widget.root
    return {
        widget = widget,
        interfaceID = root.interfaceID, staticID = root.staticID,
        categoryID = root.categoryID, dynamicID = root.dynamicID,
    }
end

function UI.liveRoot(owner)
    if owner == nil then return nil end
    return ui.Interfaces:GetComponent(owner.interfaceID, owner.staticID, owner.categoryID, owner.dynamicID)
end

function UI.checkContentHost(widget)
    -- PrettyUI 1.2.0 has no NewComponent/auto allocator. Raw bars need category 0.
    if widget.content.categoryID ~= 0 then
        widget:Destroy()
        error("VoragoSync requires a category-zero PrettyUI content host (verified with 1.2.0)")
    end
end

return UI
