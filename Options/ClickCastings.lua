---@type BFI
local BFI = select(2, ...)
local L = BFI.L
---@class ClickCastings
local CC = BFI.modules.ClickCastings
---@type AbstractFramework
local AF = _G.AbstractFramework

local panel
local list
local enabled
local conflictText
local rows = {}
local macroEditor
local macroEditorBinding
local GetCursorInfo = _G.GetCursorInfo
local ClearCursor = _G.ClearCursor
local UpdateConflictNotice

local actionItems = {
    {text = L["Target"], value = "target"},
    {text = L["Menu"], value = "togglemenu"},
    {text = L["Focus"], value = "focus"},
    {text = L["Assist"], value = "assist"},
    {text = L["Spell"], value = "spell"},
    {text = L["Saved Macro"], value = "macro"},
    {text = L["Custom Macro"], value = "custom"},
    {text = L["Item or Equipment Slot"], value = "item"},
}

local payloadActions = {
    spell = true,
    macro = true,
    custom = true,
    item = true,
}

local function GetConfig()
    return CC.activeConfig
end

local function RefreshRuntime()
    AF.Fire("BFI_UpdateModule", "clickCastings")
end

local function MoveBinding(from, to)
    local bindings = GetConfig().bindings
    if from == to or not bindings[from] then return end
    local binding = tremove(bindings, from)
    tinsert(bindings, to, binding)
    list.Load()
    RefreshRuntime()
end

local function DeleteBinding(index)
    tremove(GetConfig().bindings, index)
    list.Load()
    RefreshRuntime()
    UpdateConflictNotice()
end

UpdateConflictNotice = function()
    local conflicts = CC.GetNativeConflicts()
    if #conflicts > 0 then
        conflictText:SetText((
            L["%d overlapping Blizzard click binding(s) may override or remap BFI actions. Open Blizzard Click Casting to review them."]
        ):format(#conflicts))
        conflictText:SetColor("firebrick")
    else
        conflictText:SetText(
            L["Blizzard Click Casting continues to run first. Non-overlapping BFI bindings coexist with it."]
        )
        conflictText:SetColor("tip")
    end
end

local function SetPayload(row, value)
    local binding = GetConfig().bindings[row.index]
    if not binding then return end
    if value == "" then
        binding[3] = ""
        RefreshRuntime()
        UpdateConflictNotice()
        return
    end
    if binding[2] == "spell" then
        value = tonumber(value)
        if not value or value <= 0 then
            row.payload:SetText(tostring(binding[3] or ""))
            return
        end
    elseif binding[2] == "macro" or binding[2] == "item" then
        value = tonumber(value) or value
    end
    binding[3] = value
    RefreshRuntime()
    UpdateConflictNotice()
end

-- Cursor tuple positions are pinned to Retail 12.1.0.68914 and Blizzard UI
-- source d3915c78aba77a7a9be76acbfa35c674bbb6abe9. This mirrors the public
-- spell/macro cursor contract without importing Cell's curated spell data.
local function SetPayloadFromCursor(row)
    if not GetCursorInfo then return end
    local cursorType, cursorInfo1, _, cursorInfo3 = GetCursorInfo()
    local actionType, payload
    if cursorType == "spell" and cursorInfo3 then
        actionType, payload = "spell", cursorInfo3
    elseif cursorType == "macro" and cursorInfo1 then
        actionType, payload = "macro", cursorInfo1
    elseif cursorType == "item" and cursorInfo1 then
        actionType, payload = "item", "item:" .. cursorInfo1
    else
        return
    end

    local binding = GetConfig().bindings[row.index]
    if not binding then return end
    binding[2], binding[3] = actionType, payload
    if ClearCursor then ClearCursor() end
    list.Load()
    RefreshRuntime()
    UpdateConflictNotice()
end

local function ShowMacroEditor(row)
    local binding = GetConfig().bindings[row.index]
    if not binding or binding[2] ~= "custom" then return end

    if not macroEditor then
        macroEditor = AF.CreateFrame(panel, nil, nil, 190)
        local box = AF.CreateScrollEditBox(
            macroEditor,
            nil,
            L["Macro Text"],
            nil,
            190
        )
        macroEditor.box = box
        box:SetPoint("TOPLEFT")
        box:SetPoint("BOTTOMRIGHT")
    end

    macroEditorBinding = binding
    macroEditor.box:SetText(binding[3] or "")
    local dialog = AF.GetDialog(
        panel,
        AF.WrapTextInColor(L["Custom Macro"], "BFI"),
        500
    )
    dialog:SetToOkayCancel()
    dialog:SetContent(macroEditor, 190)
    AF.SetPoint(dialog, "CENTER", panel)
    dialog:SetOnConfirm(function()
        if macroEditorBinding[2] ~= "custom" then return end
        local isActive
        for _, current in ipairs(GetConfig().bindings) do
            if current == macroEditorBinding then isActive = true break end
        end
        if not isActive then return end
        macroEditorBinding[3] = macroEditor.box:GetText()
        list.Load()
        RefreshRuntime()
        UpdateConflictNotice()
    end)
end

local function CreateRow(index)
    local row = AF.CreateFrame(list, nil, nil, 26)
    row.index = index

    local order = AF.CreateFontString(row)
    row.order = order
    AF.SetPoint(order, "LEFT", 3, 0)
    order:SetWidth(20)
    order:SetJustifyH("CENTER")

    local capture = AF.CreateBindingCapture(
        row,
        145,
        22,
        L["Set Binding"],
        L["Press a key or mouse button"]
    )
    row.capture = capture
    AF.SetPoint(capture, "LEFT", order, "RIGHT", 5, 0)
    capture:SetOnBindingChanged(function(binding)
        local current = GetConfig().bindings[row.index]
        if not current then return end
        if not binding then
            DeleteBinding(row.index)
            return
        end
        local attribute = CC.EncodeBinding(binding)
        if not attribute then return end
        for i, other in ipairs(GetConfig().bindings) do
            if i ~= row.index and other[1] == attribute then
                capture:SetBinding(CC.DecodeBinding(current[1]))
                return
            end
        end
        current[1] = attribute
        RefreshRuntime()
        UpdateConflictNotice()
    end)

    local action = AF.CreateDropdown(row, 125)
    row.action = action
    AF.SetPoint(action, "LEFT", capture, "RIGHT", 7, 0)
    action:SetItems(actionItems)
    action:SetOnSelect(function(value)
        local binding = GetConfig().bindings[row.index]
        if not binding then return end
        if binding[2] == value then return end
        binding[2] = value
        -- Payloads are action-specific. Carrying a spell ID into a custom
        -- macro (or vice versa) can create invalid persisted rows.
        binding[3] = payloadActions[value] and "" or nil
        list.Load()
        RefreshRuntime()
        UpdateConflictNotice()
    end)

    local payload = AF.CreateEditBox(row, nil, 190, 22, "trim")
    row.payload = payload
    AF.SetPoint(payload, "LEFT", action, "RIGHT", 7, 0)
    payload:SetScript("OnReceiveDrag", function()
        SetPayloadFromCursor(row)
    end)
    payload:SetConfirmButton(function(value)
        SetPayload(row, value)
        -- AF's confirm wrapper records the submitted text after this callback.
        -- Restore the persisted canonical value on the next frame so rejected
        -- spell IDs cannot become the widget's hidden saved value.
        local submittedBinding = GetConfig().bindings[row.index]
        C_Timer.After(0, function()
            local isActive
            for _, current in ipairs(GetConfig().bindings) do
                if current == submittedBinding then isActive = true break end
            end
            if isActive then
                payload:SetText(tostring(submittedBinding[3] or ""))
                payload.value = payload:GetValue()
            end
        end)
    end)
    payload:SetOnEnterPressed(function(value)
        SetPayload(row, value)
        payload.value = payload:GetValue()
        payload.confirmBtn:Hide()
    end)

    local editPayload = AF.CreateButton(
        row,
        L["Edit"],
        "BFI_hover",
        42,
        22
    )
    row.editPayload = editPayload
    AF.SetPoint(editPayload, "LEFT", payload, "RIGHT", 7, 0)
    editPayload:SetOnClick(function() ShowMacroEditor(row) end)

    local up = AF.CreateButton(row, "↑", "BFI_hover", 22, 22)
    row.up = up
    AF.SetPoint(up, "LEFT", editPayload, "RIGHT", 7, 0)
    up:SetOnClick(function()
        if row.index > 1 then MoveBinding(row.index, row.index - 1) end
    end)

    local down = AF.CreateButton(row, "↓", "BFI_hover", 22, 22)
    row.down = down
    AF.SetPoint(down, "LEFT", up, "RIGHT", 3, 0)
    down:SetOnClick(function()
        if row.index < #GetConfig().bindings then
            MoveBinding(row.index, row.index + 1)
        end
    end)

    local delete = AF.CreateButton(row, "×", "red_hover", 22, 22)
    row.delete = delete
    AF.SetPoint(delete, "LEFT", down, "RIGHT", 3, 0)
    delete:SetOnClick(function() DeleteBinding(row.index) end)

    rows[index] = row
    return row
end

local function LoadRow(row, index, binding)
    row.index = index
    row.order:SetText(index)
    row.capture:SetBinding(CC.DecodeBinding(binding[1]))
    row.action:SetSelectedValue(binding[2])

    local hasPayload = payloadActions[binding[2]]
    row.editPayload:SetEnabled(binding[2] == "custom")
    row.payload:SetEnabled(hasPayload)
    row.payload:SetNotUserChangable(binding[2] == "custom")
    if hasPayload then
        local displayValue = binding[3] or ""
        if binding[2] == "custom" then
            displayValue = tostring(displayValue):gsub("[\r\n]+", "  /  ")
        end
        row.payload:SetText(displayValue)
        if binding[2] == "spell" then
            row.payload:SetLabel(L["Spell ID"])
        elseif binding[2] == "macro" then
            row.payload:SetLabel(L["Macro Name or Index"])
        elseif binding[2] == "custom" then
            row.payload:SetLabel(L["Macro Text"])
        else
            row.payload:SetLabel(L["Item or Slot"])
        end
    else
        row.payload:SetText("")
        row.payload:SetLabel("")
    end
    row.up:SetEnabled(index > 1)
    row.down:SetEnabled(index < #GetConfig().bindings)
    row:Show()
end

local function CreatePanel()
    panel = AF.CreateFrame(
        BFIOptionsFrame_ContentPane,
        "BFIOptionsFrame_ClickCastingsPanel"
    )
    panel:SetAllPoints()
    AF.ApplyCombatProtectionToFrame(panel)

    local title = AF.CreateFontString(
        panel,
        AF.GetGradientText(L["Click Casting"], "BFI", "white")
    )
    AF.SetPoint(title, "TOPLEFT", 15, -15)

    local profile = AF.CreateFontString(panel)
    panel.profile = profile
    AF.SetPoint(profile, "TOPRIGHT", -15, -18)
    profile:SetColor("tip")

    local description = AF.CreateFontString(
        panel,
        L["Click Casting bindings apply to every BFI unit frame. They use the active BFI profile; class-specific binding sets remain separate inside profiles shared by multiple classes. Drop a spell, macro, or item onto the Value field to add its ID."]
    )
    AF.SetPoint(description, "TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    AF.SetPoint(description, "TOPRIGHT", -15, -38)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetWordWrap(true)
    description:SetColor("tip")

    enabled = AF.CreateCheckButton(panel, L["Enable BFI Click Casting"])
    AF.SetPoint(enabled, "TOPLEFT", description, "BOTTOMLEFT", 0, -15)
    enabled:SetOnCheck(function(checked)
        GetConfig().enabled = checked
        list.Load()
        RefreshRuntime()
        UpdateConflictNotice()
    end)

    local add = AF.CreateButton(panel, L["Add Binding"], "BFI_hover", 110, 22)
    AF.SetPoint(add, "TOPRIGHT", description, "BOTTOMRIGHT", 0, -12)
    add:SetOnClick(function()
        GetConfig().bindings[#GetConfig().bindings + 1] = {
            "notBound",
            "target",
        }
        list.Load()
        UpdateConflictNotice()
    end)

    local openBlizzard = AF.CreateButton(
        panel,
        L["Blizzard Click Casting"],
        "BFI_hover",
        150,
        22
    )
    AF.SetPoint(openBlizzard, "RIGHT", add, "LEFT", -7, 0)
    openBlizzard:SetOnClick(function()
        panel:GetParent():GetParent():Hide()
        if _G.ToggleClickBindingFrame then
            _G.ToggleClickBindingFrame()
        end
    end)

    local bindingHeader = AF.CreateFontString(panel, L["Binding"], "gray")
    AF.SetPoint(bindingHeader, "TOPLEFT", enabled, "BOTTOMLEFT", 30, -17)
    local actionHeader = AF.CreateFontString(panel, L["Action"], "gray")
    AF.SetPoint(actionHeader, "LEFT", bindingHeader, 152, 0)
    local valueHeader = AF.CreateFontString(panel, L["Value"], "gray")
    AF.SetPoint(valueHeader, "LEFT", actionHeader, 132, 0)

    list = AF.CreateScrollList(panel, nil, 3, 3, 13, 26, 4)
    AF.SetPoint(list, "TOPLEFT", bindingHeader, "BOTTOMLEFT", -30, -5)
    AF.SetPoint(list, "TOPRIGHT", -15, -122)
    AF.SetPoint(list, "BOTTOM", 0, 55)

    function list.Load()
        local config = GetConfig()
        enabled:SetChecked(config.enabled)
        local widgets = {}
        for index, binding in ipairs(config.bindings) do
            local row = rows[index] or CreateRow(index)
            LoadRow(row, index, binding)
            widgets[#widgets + 1] = row
        end
        for index = #widgets + 1, #rows do rows[index]:Hide() end
        list:SetWidgets(widgets)
        add:SetEnabled(true)
        for _, row in ipairs(widgets) do
            row.capture:SetEnabled(true)
            row.action:SetEnabled(true)
            row.payload:SetEnabled(payloadActions[
                config.bindings[row.index][2]
            ])
            row.editPayload:SetEnabled(
                config.bindings[row.index][2] == "custom"
            )
            row.up:SetEnabled(row.index > 1)
            row.down:SetEnabled(
                row.index < #config.bindings
            )
            row.delete:SetEnabled(true)
        end
    end

    conflictText = AF.CreateFontString(panel)
    AF.SetPoint(conflictText, "BOTTOMLEFT", 15, 17)
    AF.SetPoint(conflictText, "BOTTOMRIGHT", -15, 17)
    conflictText:SetJustifyH("LEFT")
    conflictText:SetWordWrap(true)

    panel:SetOnHide(function()
        for _, row in ipairs(rows) do row.capture:CancelCapture() end
    end)
end

local function LoadPanel()
    panel.profile:SetText(
        L["Profile: %s  •  Class: %s"]:format(
            BFI.vars.profileName == "default"
                and L["Default"] or BFI.vars.profileName,
            AF.GetLocalizedClassName(AF.player.class)
        )
    )
    list.Load()
    UpdateConflictNotice()
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which == "clickCastings" and panel then LoadPanel() end
end)

AF.RegisterCallback("BFI_UpdateProfile", function()
    if panel and panel:IsShown() then LoadPanel() end
end, "low")

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "clickCastings" then
        if not panel then CreatePanel() end
        LoadPanel()
        panel:Show()
    elseif panel then
        panel:Hide()
    end
end)
