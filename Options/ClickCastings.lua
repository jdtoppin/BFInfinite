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
local smartResurrection
local preferMassResurrection
local conflictText
local rows = {}
local macroEditor
local macroEditorBinding
local GetCursorInfo = _G.GetCursorInfo
local ClearCursor = _G.ClearCursor
local UpdateConflictNotice
local optionsStage = "not started"

-- AF.Fire intentionally isolates callback failures. Options construction is
-- non-secret UI work, so retain and forward its traceback here instead of
-- leaving users with a silently cached, partially constructed blank panel.
local function CaptureOptionsError(message)
    local trace = type(_G.debugstack) == "function"
        and _G.debugstack(2, 20, 20) or ""
    return ("Click Casting options failed during %s: %s\n%s"):format(
        optionsStage,
        tostring(message),
        trace
    )
end

local function ReportOptionsError(message)
    BFI.vars.clickCastingOptionsError = message
    AF.Print(message)
    if type(_G.geterrorhandler) == "function" then
        local handler = _G.geterrorhandler()
        if type(handler) == "function" then handler(message) end
    end
end

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

local function CancelBindingCaptures()
    for _, row in ipairs(rows) do
        if row.capture then row.capture:CancelCapture() end
    end
end

local function ReleaseKeyboardInput()
    CancelBindingCaptures()
    for _, row in ipairs(rows) do
        if row.payload then row.payload:ClearFocus() end
    end
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

local function UpdateEnabledState(checked)
    enabled.label:SetTextColor(
        AF.GetColorRGB(checked and "softlime" or "firebrick")
    )
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

local spellCategoryLabels = {
    class = "Class Spells",
    spec = "Specialization Spells",
    pet = "Pet Spells",
    talent = "Talents",
    hero = "Hero Talents",
    pvp = "PvP Talents",
    resurrection = "Resurrection",
}

local function SetSuggestedSpell(binding, spellID)
    local isActive
    for _, current in ipairs(GetConfig().bindings) do
        if current == binding then isActive = true break end
    end
    if not isActive then return end

    binding[2], binding[3] = "spell", spellID
    list.Load()
    RefreshRuntime()
    UpdateConflictNotice()
end

local function ShowSpellPicker(row)
    local binding = GetConfig().bindings[row.index]
    if not binding or binding[2] ~= "spell" then return end

    local groups = {}
    local groupOrder = {}
    for _, spell in ipairs(CC.GetSuggestedSpells()) do
        local category = spell.category or "talent"
        if not groups[category] then
            groups[category] = {}
            groupOrder[#groupOrder + 1] = category
        end
        groups[category][#groups[category] + 1] = {
            text = spell.name,
            icon = spell.iconID,
            value = spell.spellID,
            callback = function()
                SetSuggestedSpell(binding, spell.spellID)
            end,
        }
    end

    local items = {}
    for _, category in ipairs(groupOrder) do
        items[#items + 1] = {
            text = L[spellCategoryLabels[category] or "Talents"],
            notClickable = true,
            children = groups[category],
        }
    end
    if #items == 0 then
        items[1] = {
            text = L["No suggested spells available"],
            disabled = true,
        }
    end
    AF.ShowCascadingMenu(row.payload, items, 15)
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
    optionsStage = "binding row " .. index .. " frame"
    local row = AF.CreateFrame(list, nil, nil, 26)
    row.index = index

    local order = AF.CreateFontString(row)
    row.order = order
    AF.SetPoint(order, "LEFT", 3, 0)
    order:SetWidth(20)
    order:SetJustifyH("CENTER")

    optionsStage = "binding row " .. index .. " capture"
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

    optionsStage = "binding row " .. index .. " action"
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

    optionsStage = "binding row " .. index .. " value"
    local payload = AF.CreateEditBox(row, nil, 190, 22, "trim")
    row.payload = payload
    AF.SetPoint(payload, "LEFT", action, "RIGHT", 7, 0)
    payload:SetScript("OnReceiveDrag", function()
        SetPayloadFromCursor(row)
    end)
    payload:SetOnEditFocusGained(CancelBindingCaptures)
    payload:SetScript("OnMouseDown", function(_, button)
        CancelBindingCaptures()
        payload:SetFocus()
        local binding = GetConfig().bindings[row.index]
        if button == "LeftButton"
            and binding
            and binding[2] == "spell"
        then
            ShowSpellPicker(row)
        end
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

    optionsStage = "binding row " .. index .. " controls"
    local editPayload = AF.CreateButton(
        row,
        L["Edit"],
        "BFI_hover",
        42,
        22
    )
    row.editPayload = editPayload
    AF.SetPoint(editPayload, "LEFT", payload, "RIGHT", 7, 0)
    editPayload:SetOnClick(function()
        local binding = GetConfig().bindings[row.index]
        if not binding then return end
        if binding[2] == "custom" then
            ShowMacroEditor(row)
        end
    end)

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
    optionsStage = "binding row " .. index .. " data"
    row.index = index
    row.order:SetText(index)
    row.capture:SetBinding(CC.DecodeBinding(binding[1]))
    row.action:SetSelectedValue(binding[2])

    local hasPayload = payloadActions[binding[2]]
    local hasCustomEditor = binding[2] == "custom"
    row.editPayload:SetEnabled(hasCustomEditor)
    row.editPayload:SetShown(hasCustomEditor)
    row.editPayload:SetText(L["Edit"])
    row.payload:SetWidth(hasCustomEditor and 190 or 239)
    AF.ClearPoints(row.up)
    AF.SetPoint(
        row.up,
        "LEFT",
        hasCustomEditor and row.editPayload or row.payload,
        "RIGHT",
        7,
        0
    )
    row.payload:SetEnabled(hasPayload)
    row.payload:SetNotUserChangable(binding[2] == "custom")
    if hasPayload then
        local displayValue = binding[3] or ""
        if binding[2] == "custom" then
            displayValue = tostring(displayValue):gsub("[\r\n]+", "  /  ")
        end
        row.payload:SetText(tostring(displayValue))
        if binding[2] == "spell" then
            row.payload:SetLabel(L["Spell ID or click to pick"])
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
    optionsStage = "panel frame"
    panel = AF.CreateFrame(
        BFIOptionsFrame_ContentPane,
        "BFIOptionsFrame_ClickCastingsPanel"
    )
    panel:SetAllPoints()
    AF.ApplyCombatProtectionToFrame(panel)

    optionsStage = "panel header"
    local header = AF.CreateTitledPane(
        panel,
        AF.GetGradientText(L["Click Casting"], "BFI", "white"),
        nil,
        18,
        "BFI"
    )
    panel.header = header
    AF.SetPoint(header, "TOPLEFT", 15, -15)
    AF.SetPoint(header, "TOPRIGHT", -15, -15)
    header:SetTips(
        L["Click Casting"],
        L["Click Casting bindings apply to every BFI unit frame. They use the active BFI profile; class-specific binding sets remain separate inside profiles shared by multiple classes. Drop a spell, macro, or item onto the Value field to add its ID."]
    )

    local profile = AF.CreateFontString(header)
    panel.profile = profile
    AF.SetPoint(profile, "BOTTOMRIGHT", header.tips, "BOTTOMLEFT", -5, 2)
    profile:SetColor("tip")

    optionsStage = "panel controls"
    enabled = AF.CreateCheckButton(header, L["Enable"])
    AF.SetPoint(enabled, "LEFT", header.title, "RIGHT", 15, 0)
    enabled:SetOnCheck(function(checked)
        GetConfig().enabled = checked
        list.Load()
        RefreshRuntime()
        UpdateConflictNotice()
    end)

    smartResurrection = AF.CreateDropdown(panel, 180)
    AF.SetPoint(
        smartResurrection,
        "TOPLEFT",
        header,
        "BOTTOMLEFT",
        0,
        -30
    )
    smartResurrection:SetLabel(L["Smart Resurrection"], "gray")
    smartResurrection:SetOnSelect(function(value)
        GetConfig().smartResurrection = value
        list.Load()
        RefreshRuntime()
    end)
    smartResurrection:SetTooltip(
        L["Smart Resurrection"],
        L["On a dead unit, ordinary Spell bindings cast an available resurrection instead. The original spell still casts on living units."]
    )

    preferMassResurrection = AF.CreateCheckButton(
        panel,
        L["Prefer Mass Resurrection"]
    )
    AF.SetPoint(
        preferMassResurrection,
        "LEFT",
        smartResurrection,
        "RIGHT",
        15,
        0
    )
    preferMassResurrection:SetOnCheck(function(checked)
        GetConfig().preferMassResurrection = checked
        RefreshRuntime()
    end)
    AF.SetTooltip(
        preferMassResurrection,
        "TOPLEFT",
        0,
        2,
        L["Prefer Mass Resurrection"],
        L["When the active specialization knows both versions, use its mass resurrection on dead units. Otherwise use the normal single-target spell."]
    )

    local add = AF.CreateButton(panel, L["Add Binding"], "BFI_hover", 110, 22)
    AF.SetPoint(add, "TOPRIGHT", header, "BOTTOMRIGHT", 0, -30)
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

    optionsStage = "binding list"
    local bindingHeader = AF.CreateFontString(panel, L["Binding"], "gray")
    AF.SetPoint(
        bindingHeader,
        "TOPLEFT",
        smartResurrection,
        "BOTTOMLEFT",
        30,
        -16
    )
    local actionHeader = AF.CreateFontString(panel, L["Action"], "gray")
    AF.SetPoint(actionHeader, "LEFT", bindingHeader, 152, 0)
    local valueHeader = AF.CreateFontString(panel, L["Value"], "gray")
    AF.SetPoint(valueHeader, "LEFT", actionHeader, 132, 0)

    list = AF.CreateScrollList(panel, nil, 3, 3, 13, 26, 4)
    AF.SetPoint(list, "TOPLEFT", bindingHeader, "BOTTOMLEFT", -30, -5)
    AF.SetPoint(list, "BOTTOMRIGHT", -15, 55)

    function list.Load()
        local config = GetConfig()
        local capabilities = type(
            CC.GetSmartResurrectionCapabilities
        ) == "function"
            and CC.GetSmartResurrectionCapabilities()
            or {normal = true, mass = true, combat = true}
        enabled:SetChecked(config.enabled)
        UpdateEnabledState(config.enabled)
        smartResurrection:SetItems({
            {text = L["Disabled"], value = "disabled"},
            {
                text = L["Normal Resurrection"],
                value = "normal",
                disabled = not capabilities.normal,
            },
            {
                text = L["Normal + Combat Resurrection"],
                value = "normal+combat",
                disabled = not capabilities.normal
                    and not capabilities.combat,
            },
        })
        smartResurrection:SetEnabled(
            capabilities.normal or capabilities.combat
        )
        smartResurrection:SetSelectedValue(config.smartResurrection)
        preferMassResurrection:SetChecked(config.preferMassResurrection)
        preferMassResurrection:SetEnabled(
            config.smartResurrection ~= "disabled"
                and capabilities.mass
        )
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

    optionsStage = "panel footer"
    conflictText = AF.CreateFontString(panel)
    AF.SetPoint(conflictText, "BOTTOMLEFT", 15, 17)
    AF.SetPoint(conflictText, "BOTTOMRIGHT", -15, 17)
    conflictText:SetJustifyH("LEFT")
    conflictText:SetWordWrap(true)

    panel:SetOnHide(function()
        ReleaseKeyboardInput()
        AF.CloseCascadingMenu()
    end)
end

local function LoadPanel()
    optionsStage = "profile metadata"
    local localizedClass = AF.GetLocalizedClassName(AF.player.class)
    local classText = AF.WrapTextInColor(localizedClass, AF.player.class)
    panel.profile:SetText(
        L["Profile: %s  •  Class: %s  •  Spec: %s"]:format(
            BFI.vars.profileName == "default"
                and L["Default"] or BFI.vars.profileName,
            classText,
            AF.player.localizedSpec or L["Unknown"]
        )
    )
    optionsStage = "binding list data"
    list.Load()
    optionsStage = "native binding conflicts"
    UpdateConflictNotice()
end

AF.RegisterCallback("BFI_RefreshOptions", function(_, which)
    if which == "clickCastings" and panel then LoadPanel() end
end)

AF.RegisterCallback("BFI_UpdateProfile", function()
    if panel and panel:IsShown() then
        AF.CloseCascadingMenu()
        LoadPanel()
    end
end, "low")

AF.RegisterCallback("AF_PLAYER_SPEC_UPDATE", function()
    if panel and panel:IsShown() then
        AF.CloseCascadingMenu()
        LoadPanel()
    end
end, "low")

AF.RegisterCallback("AF_COMBAT_ENTER", function()
    if panel and panel:IsShown() then
        ReleaseKeyboardInput()
        AF.CloseCascadingMenu()
    end
end)

AF.RegisterCallback("BFI_ShowOptionsPanel", function(_, id)
    if id == "clickCastings" then
        local success, message = _G.xpcall(function()
            if not panel then CreatePanel() end
            LoadPanel()
            optionsStage = "panel show"
            panel:Show()
        end, CaptureOptionsError)
        if success then
            BFI.vars.clickCastingOptionsError = nil
        else
            ReportOptionsError(message)
        end
    elseif panel then
        panel:Hide()
    end
end)
