local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message, 2) end
end

local function newWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        shown = true,
        enabled = true,
        points = {},
        scripts = {},
    }

    function widget:CancelCapture()
        self.captureCancelled = true
        self.capturing = false
    end

    function widget:ClearFocus()
        local hadFocus = self.focused
        self.focused = false
        if hadFocus and self.onEditFocusLost then
            self.onEditFocusLost(self)
        end
    end

    function widget:EnableMouse(enabled)
        self.mouseEnabled = enabled and true or false
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:HasFocus()
        return self.focused and true or false
    end

    function widget:GetText()
        return self.text or ""
    end

    function widget:GetValue()
        return self.text or ""
    end

    function widget:Hide()
        self.shown = false
        if self.onHide then self.onHide() end
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:IsVisible()
        return self.shown
            and (not self.parent
                or not self.parent.IsVisible
                or self.parent:IsVisible())
    end

    function widget:IsEnabled()
        return self.enabled
    end

    function widget:SetAllPoints()
        self.allPoints = true
    end

    function widget:SetBinding(binding)
        self.binding = binding
    end

    function widget:SetFocus()
        self.focused = true
        if self.onEditFocusGained then
            self.onEditFocusGained(self)
        end
    end

    function widget:StartCapture()
        self.capturing = true
    end

    function widget:SetChecked(checked)
        self.checked = checked and true or false
    end

    function widget:SetColor(color)
        self.color = color
    end

    function widget:SetContent(content, height)
        self.content = content
        self.contentHeight = height
    end

    function widget:SetEnabled(enabled)
        self.enabled = enabled and true or false
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetJustifyH(justify)
        self.justifyH = justify
    end

    function widget:SetJustifyV(justify)
        self.justifyV = justify
    end

    function widget:SetLabel(label)
        self.label = label
    end

    function widget:SetNotUserChangable(readOnly)
        self.readOnly = readOnly and true or false
    end

    function widget:SetOnBindingChanged(callback)
        self.onBindingChanged = callback
    end

    function widget:SetOnCheck(callback)
        self.onCheck = callback
    end

    function widget:SetOnClick(callback)
        self.onClick = callback
    end

    function widget:SetOnConfirm(callback)
        self.onConfirm = callback
    end

    function widget:SetOnEnterPressed(callback)
        self.onEnterPressed = callback
    end

    function widget:SetOnEditFocusGained(callback)
        self.onEditFocusGained = callback
    end

    function widget:SetOnEditFocusLost(callback)
        self.onEditFocusLost = callback
    end

    function widget:SetOnHide(callback)
        self.onHide = callback
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function widget:SetScript(script, callback)
        self.scripts[script] = callback
    end

    function widget:SetShown(shown)
        self.shown = shown and true or false
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetText(text)
        self.text = text
    end

    function widget:SetTexture(texture)
        self.texture = texture
    end

    function widget:SetTexCoord(...)
        self.texCoord = {...}
    end

    function widget:SetTextColor(...)
        self.textColor = {...}
    end

    function widget:SetTooltip(...)
        self.tooltip = {...}
    end

    function widget:SetToOkayCancel()
        self.okayCancel = true
    end

    function widget:SetWidth(width)
        self.width = width
    end

    function widget:SetWordWrap(wrap)
        self.wordWrap = wrap
    end

    function widget:Show()
        self.shown = true
    end

    return widget
end

local function createHarness()
    local state = {
        callbacks = {},
        clearCursorCalls = 0,
        combatProtected = {},
        cursor = {},
        dialogs = {},
        events = {},
        fires = {},
        namedFrames = {},
        spellDataRequests = {},
        spellOverrides = {},
        timers = {},
        wrapColorCalls = {},
    }
    local L = setmetatable({}, {
        __index = function(_, key) return key end,
    })
    local AF = {
        player = {
            class = "PRIEST",
            localizedSpec = "Discipline",
        },
    }
    local CC = {}
    local root = newWidget("root")
    local rootParent = newWidget("rootParent")
    root.parent = rootParent
    rootParent.parent = newWidget("rootGrandparent")

    function AF.ApplyCombatProtectionToFrame(frame)
        state.combatProtected[#state.combatProtected + 1] = frame
    end

    function AF.CreateBindingCapture(parent, width, height)
        local capture = newWidget("bindingCapture", parent)
        capture.width = width
        capture.height = height
        return capture
    end

    function AF.CreateButton(parent, text, _, width, height)
        local button = newWidget("button", parent)
        button.text = text
        button.width = width
        button.height = height
        if text == L["Add Binding"] then state.addButton = button end
        if text == L["Blizzard Click Casting"] then
            state.openBlizzardButton = button
        end
        return button
    end

    function AF.CreateCheckButton(parent, text)
        local checkButton = newWidget("checkButton", parent)
        -- Checkbox text is owned by its FontString in AbstractFramework.
        -- Keep the harness honest so a widget-level SetTextColor call cannot
        -- conceal a live-client API mismatch.
        checkButton.SetTextColor = nil
        checkButton.label = newWidget("fontString", checkButton)
        checkButton.text = text
        if text == L["Enable"] then
            state.enabledCheckButton = checkButton
        elseif text == L["Prefer Mass Resurrection"] then
            state.preferMassResurrection = checkButton
        end
        return checkButton
    end

    function AF.CreateDropdown(parent, width)
        local dropdown = newWidget("dropdown", parent)
        dropdown.width = width
        if width == 180 then state.smartResurrection = dropdown end
        return dropdown
    end

    function AF.CreateEditBox(parent, _, width, height, mode)
        local editBox = newWidget("editBox", parent)
        editBox.width = width
        editBox.height = height
        editBox.mode = mode
        editBox.confirmBtn = newWidget("confirmButton", editBox)
        function editBox:GetValue()
            if self.mode == "number" then
                return tonumber(self:GetText())
            end
            return (self:GetText():gsub("^%s+", ""):gsub("%s+$", ""))
        end
        function editBox:SetText(text)
            self.text = tostring(text or "")
            -- AF treats script-driven SetText as canonical widget state;
            -- user edits leave this saved value untouched until confirmation.
            self.value = self:GetValue()
        end
        function editBox:SetMode(newMode)
            self.mode = newMode
        end
        function editBox:SetNumeric(numeric)
            self.numeric = numeric and true or false
        end
        function editBox:SetConfirmButton(callback)
            self.onConfirmValue = callback
        end
        function editBox:Confirm()
            local value = self:GetValue()
            self.onConfirmValue(value)
            self.value = value
            self.confirmBtn:Hide()
            self:ClearFocus()
        end
        function editBox:SimulateUserText(text)
            if self.numeric and text:find("[^%d]", 1) then
                return
            end
            self.text = text
        end
        function editBox:SimulateBackspace()
            self.text = self:GetText():sub(1, -2)
        end
        return editBox
    end

    function AF.CreateFontString(parent, text)
        local fontString = newWidget("fontString", parent)
        fontString.text = text
        return fontString
    end

    function AF.CreateFrame(parent, name, width, height)
        local frame = newWidget("frame", parent)
        frame.width = width
        frame.height = height
        if name then state.namedFrames[name] = frame end
        return frame
    end

    function AF.CreateTexture(parent, texture)
        local region = newWidget("texture", parent)
        region.texture = texture
        return region
    end

    function AF.CreateTitledPane(parent, title, _, height, color)
        if state.failTitledPane then error("injected titled-pane failure") end
        local pane = newWidget("titledPane", parent)
        pane.height = height
        pane.color = color
        pane.title = newWidget("fontString", pane)
        pane.title.text = title
        pane.line = newWidget("texture", pane)
        function pane:SetTips(...)
            self.tips = newWidget("tipsButton", self)
            self.tips.tips = {...}
            self.tips:SetPoint("BOTTOMRIGHT", self.line, "TOPRIGHT")
        end
        state.headerPane = pane
        return pane
    end

    function AF.CreateScrollEditBox(parent)
        return newWidget("scrollEditBox", parent)
    end

    function AF.CreateScrollList(parent)
        local scrollList = newWidget("scrollList", parent)
        function scrollList:SetWidgets(widgets)
            self.setWidgetsCalls = (self.setWidgetsCalls or 0) + 1
            self.widgets = widgets
        end
        state.list = scrollList
        return scrollList
    end

    function AF.Fire(...)
        state.fires[#state.fires + 1] = {...}
    end

    function AF.GetDialog(parent, text, width)
        local dialog = newWidget("dialog", parent)
        dialog.text = text
        dialog.width = width
        state.dialogs[#state.dialogs + 1] = dialog
        return dialog
    end

    function AF.GetGradientText(text)
        return text
    end

    function AF.GetColorRGB(color)
        return color
    end

    function AF.GetLocalizedClassName(class)
        return class
    end

    function AF.GetSpellInfo(spellID)
        local spell = state.spellInfo[tonumber(spellID)]
        if not spell then return end
        return spell.name, spell.iconID
    end

    function AF.SpellExists(spellID)
        return state.spellExists[tonumber(spellID)] and true or false
    end

    function AF.CloseCascadingMenu()
        state.cascadingMenuCloseCalls =
            (state.cascadingMenuCloseCalls or 0) + 1
    end

    function AF.ClearPoints(widget)
        widget.points = {}
    end

    function AF.ShowCascadingMenu(owner, items)
        state.cascadingMenu = {owner = owner, items = items}
    end

    function AF.RegisterCallback(event, callback)
        state.callbacks[event] = callback
    end

    function AF.SetPoint(widget, ...)
        widget.points[#widget.points + 1] = {...}
    end

    function AF.SetTooltip(widget, ...)
        widget.tooltip = {...}
    end

    function AF.WrapTextInColor(text, color)
        state.wrapColorCalls[#state.wrapColorCalls + 1] = {
            text = text,
            color = color,
        }
        return text
    end

    function AF.Print(message)
        state.printedError = message
    end

    local config = {
        enabled = true,
        smartResurrection = "disabled",
        preferMassResurrection = true,
        bindings = {
            {"type1", "spell", 2061},
            {"type2", "macro", "NamedMacro"},
            {"type3", "target"},
            {"type4", "custom", "/say old"},
            {"type5", "item", "item:19019"},
        },
    }
    state.spellInfo = {
        [2061] = {name = "Flash Heal", iconID = 135907},
        [47540] = {name = "Penance", iconID = 237545},
        [20484] = {name = "Rebirth", iconID = 136080},
    }
    state.spellExists = {
        [2061] = true,
        [47540] = true,
        [20484] = true,
        [999999] = true,
    }
    CC.activeConfig = config
    function CC:RegisterEvent(event, callback)
        state.events[event] = callback
    end
    function CC.GetNativeConflicts()
        return state.nativeConflicts or {}
    end
    function CC.GetSuggestedSpells()
        return {
            {
                spellID = 2061,
                name = "Flash Heal",
                iconID = 135907,
                category = "class",
            },
            {
                spellID = 47540,
                name = "Penance",
                iconID = 237545,
                category = "spec",
            },
        }
    end
    function CC.GetSmartResurrectionCapabilities()
        return state.resurrectionCapabilities
            or {normal = true, mass = true, combat = false}
    end

    local BFI = {
        L = L,
        modules = {ClickCastings = CC},
        vars = {profileName = "test-profile"},
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        BFIOptionsFrame_ContentPane = root,
        C_Spell = {
            GetOverrideSpell = function(spellID)
                return state.spellOverrides[spellID] or spellID
            end,
            RequestLoadSpellData = function(spellID)
                state.spellDataRequests[#state.spellDataRequests + 1] =
                    spellID
            end,
        },
        C_Timer = {
            After = function(_, callback)
                state.timers[#state.timers + 1] = callback
            end,
        },
        ClearCursor = function()
            state.clearCursorCalls = state.clearCursorCalls + 1
        end,
        GetCursorInfo = function()
            return state.cursor[1], state.cursor[2], state.cursor[3],
                state.cursor[4]
        end,
        ipairs = ipairs,
        pairs = pairs,
        select = select,
        string = string,
        table = table,
        tinsert = table.insert,
        tremove = table.remove,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        xpcall = xpcall,
        debugstack = function() return "injected stack" end,
        geterrorhandler = function()
            return function(message)
                state.errorHandlerMessage = message
            end
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected ClickCastings options global: "
                .. tostring(key), 2)
        end,
    })

    local codec, codecError =
        loadfile("Modules/ClickCastings/BindingCodec.lua")
    assertTrue(codec, codecError)
    setfenv(codec, environment)
    codec("BFInfinite", BFI)

    local options, optionsError = loadfile("Options/ClickCastings.lua")
    assertTrue(options, optionsError)
    setfenv(options, environment)
    options("BFInfinite", BFI)

    function state:FireCallback(event, ...)
        local callback = self.callbacks[event]
        assertTrue(callback, "missing callback: " .. event)
        callback(event, ...)
    end

    function state:FireEvent(event, ...)
        local callback = self.events[event]
        assertTrue(callback, "missing event handler: " .. event)
        callback(self.CC, event, ...)
    end

    function state:RunTimers()
        local timers = self.timers
        self.timers = {}
        for _, callback in ipairs(timers) do callback() end
    end

    state.AF = AF
    state.BFI = BFI
    state.CC = CC
    state.config = config
    state.environment = environment
    state.L = L
    return state
end

local function compiledContains(compiled, sourceAttribute)
    for _, action in ipairs(compiled.actions) do
        if action.sourceAttribute == sourceAttribute then return true end
    end
    return false
end

local harness = createHarness()
harness:FireCallback("BFI_UpdateProfile")
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
harness:FireCallback("AF_COMBAT_ENTER")
assertEqual(harness.cascadingMenuCloseCalls or 0, 0,
    "profile, spec, and combat callbacks leave unrelated menus alone before panel creation")

harness:FireCallback("BFI_ShowOptionsPanel", "clickCastings")
assertEqual(#harness.combatProtected, 1,
    "settings panel receives combat protection")
assertTrue(harness.headerPane ~= nil,
    "viewport heading uses the standard titled-pane treatment")
assertEqual(harness.headerPane.points[1][1], "TOPLEFT",
    "viewport heading begins at the left content margin")
assertEqual(harness.headerPane.points[2][1], "TOPRIGHT",
    "viewport heading line spans the full content width")
assertEqual(harness.headerPane.color, "BFI",
    "viewport heading uses the BFI signature accent")
assertEqual(harness.headerPane.height, 18,
    "viewport heading has resolvable vertical geometry")
assertEqual(harness.headerPane.tips.tips[1], "Click Casting",
    "header information tooltip has a title")
assertEqual(
    harness.headerPane.tips.tips[2],
    "Click Casting bindings apply to every BFI unit frame. They use the active BFI profile; class-specific binding sets remain separate inside profiles shared by multiple classes. Drop a spell, macro, or item onto the Value field to add its ID.",
    "header information tooltip contains the former description"
)
local clickPanel = harness.namedFrames.BFIOptionsFrame_ClickCastingsPanel
assertEqual(clickPanel.profile.points[1][2], harness.headerPane.tips,
    "profile, class, and spec metadata sits beside the info button")
assertEqual(harness.enabledCheckButton.text, "Enable",
    "title-row toggle uses concise enable text")
assertEqual(harness.enabledCheckButton.parent, harness.headerPane,
    "enable toggle belongs to the title row")
assertEqual(harness.enabledCheckButton.points[1][1], "LEFT",
    "enable toggle aligns horizontally with the title")
assertEqual(harness.enabledCheckButton.points[1][2], harness.headerPane.title,
    "enable toggle follows the Click Casting title")
assertEqual(harness.enabledCheckButton.points[1][3], "RIGHT",
    "enable toggle appears after the Click Casting title")
assertEqual(harness.enabledCheckButton.label.textColor[1], "softlime",
    "enabled Click Casting uses the standard green label color")
assertEqual(harness.smartResurrection.points[1][2], harness.headerPane,
    "Smart Resurrection anchors below the resolved heading frame")
assertEqual(harness.addButton.points[1][2], harness.headerPane,
    "Add Binding anchors below the resolved heading frame")
assertEqual(
    harness.smartResurrection.points[1][5],
    harness.addButton.points[1][5],
    "Smart Resurrection shares the Blizzard/Add Binding action row"
)
assertEqual(harness.openBlizzardButton.points[1][2], harness.addButton,
    "Blizzard Click Casting shares the Add Binding action row")
assertEqual(harness.openBlizzardButton.points[1][5], 0,
    "Blizzard Click Casting has no vertical offset from Add Binding")
local classColorCall
for _, call in ipairs(harness.wrapColorCalls) do
    if call.text == "PRIEST" and call.color == "PRIEST" then
        classColorCall = call
        break
    end
end
assertTrue(classColorCall ~= nil,
    "the localized class value uses the player's class color")
assertEqual(#harness.list.widgets, 5, "initial binding rows")
assertEqual(#harness.list.points, 2,
    "binding list uses one top-left and one bottom-right anchor")
assertEqual(harness.list.points[1][1], "TOPLEFT",
    "binding list top follows the binding header")
assertEqual(harness.list.points[2][1], "BOTTOMRIGHT",
    "binding list bottom and right share the panel anchor")

local firstRow = harness.list.widgets[1]
assertTrue(not firstRow.editPayload.shown,
    "spell rows do not show a separate picker button")
assertEqual(firstRow.delete.points[1][1], "RIGHT",
    "binding row controls terminate at the viewport's right edge")
assertEqual(firstRow.delete.points[1][2], firstRow,
    "binding row controls use the full scroll-list row width")
assertEqual(firstRow.down.points[1][1], "RIGHT",
    "move-down control aligns inward from the row edge")
assertEqual(firstRow.down.points[1][2], firstRow.delete,
    "move-down control precedes delete in the right-aligned controls")
assertEqual(firstRow.down.points[1][3], "LEFT",
    "move-down control uses delete's near edge")
assertEqual(firstRow.up.points[1][1], "RIGHT",
    "move-up control aligns inward from move-down")
assertEqual(firstRow.up.points[1][2], firstRow.down,
    "move controls form a stable right-aligned group")
assertEqual(firstRow.up.points[1][3], "LEFT",
    "move-up control uses move-down's near edge")
assertEqual(firstRow.payload.points[1][1], "LEFT",
    "spell field begins after the fixed action column")
assertEqual(firstRow.payload.points[1][2], firstRow.action,
    "spell field follows the action selector")
assertEqual(firstRow.payload.points[1][3], "RIGHT",
    "spell field begins at the action selector's far edge")
assertEqual(firstRow.payload.points[2][1], "RIGHT",
    "spell field stretches across the available row width")
assertEqual(firstRow.payload.points[2][2], firstRow.up,
    "spell field ends before the right-aligned row controls")
assertEqual(firstRow.payload.points[2][3], "LEFT",
    "spell field uses the controls' near edge")
assertEqual(firstRow.payload.label, "Spell ID or click to pick",
    "spell field has an in-field picker prompt")
assertEqual(firstRow.payload:GetText(), "2061",
    "verified spell display preserves the underlying numeric spell ID")
assertTrue(firstRow.spellDisplay ~= nil,
    "spell rows create a separate verified-spell display")
assertEqual(firstRow.spellDisplay.parent, firstRow.payload,
    "verified-spell display is contained inside the value field")
assertTrue(not firstRow.spellDisplay.mouseEnabled,
    "verified-spell display leaves the value field mouse-interactive")
assertTrue(firstRow.spellDisplay.shown,
    "verified saved spells use the friendly display while unfocused")
assertEqual(firstRow.spellDisplay.icon.texture, 135907,
    "verified spell display uses the resolved spell icon")
assertEqual(firstRow.spellDisplay.name:GetText(), "Flash Heal",
    "verified spell display uses the resolved spell name")
assertTrue(firstRow.payload.numeric,
    "spell payload enables native numeric input filtering")
assertEqual(firstRow.payload.mode, "trim",
    "spell payload retains empty-string confirmation semantics")

firstRow.payload:SetFocus()
assertTrue(not firstRow.spellDisplay.shown,
    "focusing a verified spell reveals its numeric editor")
assertEqual(firstRow.payload:GetText(), "2061",
    "focused spell editing starts from the canonical numeric ID")
firstRow.payload:ClearFocus()
assertTrue(firstRow.spellDisplay.shown,
    "focus loss restores the verified spell display")

firstRow.payload:SetFocus()
firstRow.payload:SimulateUserText("2061x")
assertEqual(firstRow.payload:GetText(), "2061",
    "spell payload rejects non-numeric typing")
firstRow.payload:SimulateUserText("20610")
firstRow.payload:SimulateBackspace()
assertEqual(firstRow.payload:GetText(), "2061",
    "spell payload permits ordinary character deletion")

firstRow.payload:SimulateUserText("02061")
firstRow.payload:ClearFocus()
assertTrue(not firstRow.spellDisplay.shown,
    "an unconfirmed leading-zero edit remains visibly numeric")
assertEqual(firstRow.payload:GetText(), "02061",
    "an unconfirmed leading-zero edit is not hidden as canonical")
firstRow.payload:SetFocus()

firstRow.payload:SimulateUserText("47540")
firstRow.payload:Confirm()
assertEqual(harness.config.bindings[1][3], 47540,
    "confirming a verified spell persists its numeric ID")
assertTrue(firstRow.spellDisplay.shown,
    "confirming a verified spell returns to the friendly display")
assertEqual(firstRow.spellDisplay.icon.texture, 237545,
    "confirmed spell display refreshes its icon")
assertEqual(firstRow.spellDisplay.name:GetText(), "Penance",
    "confirmed spell display refreshes its name")
firstRow.down.onClick()
local reboundValue = firstRow.payload:GetText()
harness:RunTimers()
assertEqual(firstRow.payload:GetText(), reboundValue,
    "deferred confirmation cannot repaint a row rebound by reordering")
harness.list.widgets[2].up.onClick()
assertEqual(harness.config.bindings[1][3], 47540,
    "binding order is restored after deferred-confirmation coverage")

firstRow.payload:SetFocus()
firstRow.payload:SimulateUserText("999999")
firstRow.payload.onEnterPressed("999999")
firstRow.payload:ClearFocus()
assertEqual(harness.config.bindings[1][3], 999999,
    "an unavailable positive spell ID remains persisted for editing")
assertEqual(firstRow.payload:GetText(), "999999",
    "an unavailable spell ID remains visible as numeric text")
assertTrue(not firstRow.spellDisplay.shown,
    "an unavailable spell ID does not claim a verified display")
assertTrue(firstRow.payload.numeric and not firstRow.payload.readOnly,
    "an unavailable spell ID remains a numeric editable field")
assertEqual(
    harness.spellDataRequests[#harness.spellDataRequests],
    999999,
    "an unavailable spell ID requests asynchronous spell data"
)
harness.spellInfo[999999] = {
    name = "Newly Loaded Spell",
    iconID = 987654,
}
harness:FireEvent("SPELL_DATA_LOAD_RESULT", 999999, true)
assertTrue(firstRow.spellDisplay.shown,
    "loaded spell data refreshes an unfocused matching value field")
assertEqual(firstRow.spellDisplay.icon.texture, 987654,
    "asynchronously loaded spell data refreshes the icon")
assertEqual(firstRow.spellDisplay.name:GetText(), "Newly Loaded Spell",
    "asynchronously loaded spell data refreshes the name")
assertEqual(firstRow.payload:GetText(), "999999",
    "asynchronous display refresh preserves the numeric editor value")

firstRow.payload:SetFocus()
local requestCount = #harness.spellDataRequests
firstRow.payload:SimulateUserText("888888")
firstRow.payload.onEnterPressed("888888")
firstRow.payload:ClearFocus()
assertTrue(not firstRow.spellDisplay.shown,
    "a nonexistent spell ID remains visibly numeric")
assertEqual(#harness.spellDataRequests, requestCount,
    "a nonexistent spell ID does not start an async load")

firstRow.payload:SetFocus()
firstRow.payload:SimulateUserText("")
firstRow.payload.onEnterPressed("")
firstRow.payload:ClearFocus()
assertEqual(harness.config.bindings[1][3], "",
    "spell payload can be cleared after numeric input filtering")
assertTrue(not firstRow.spellDisplay.shown,
    "an empty spell ID does not show stale verified spell details")
local otherRowCapture = harness.list.widgets[2].capture
otherRowCapture:StartCapture()
assertTrue(otherRowCapture.capturing,
    "binding capture is active before entering the value field")
firstRow.payload.scripts.OnMouseDown(firstRow.payload, "LeftButton")
assertTrue(firstRow.payload:HasFocus(),
    "clicking the spell picker field retains text-entry focus")
assertEqual(harness.cascadingMenu.owner, firstRow.payload,
    "spell picker opens from and anchors to the value field")
assertTrue(otherRowCapture.captureCancelled,
    "opening a value field cancels its active binding capture")
otherRowCapture.captureCancelled = false
otherRowCapture:StartCapture()
firstRow.payload.onEditFocusGained(firstRow.payload)
assertTrue(otherRowCapture.captureCancelled,
    "value focus gained independently cancels active binding capture")
assertEqual(harness.cascadingMenu.items[1].text, "Class Spells",
    "spell picker groups class spells")
assertEqual(harness.cascadingMenu.items[2].text, "Specialization Spells",
    "spell picker groups current-spec spells")
local setWidgetsCalls = harness.list.setWidgetsCalls
local stalePickerCallback = harness.cascadingMenu.items[2].children[1].callback
stalePickerCallback()
assertEqual(harness.config.bindings[1][3], 47540,
    "suggested spell selection persists its spell ID")
assertEqual(harness.list.setWidgetsCalls, setWidgetsCalls,
    "spell picker refreshes its row without rebuilding the list")
assertEqual(firstRow.payload:GetText(), "47540",
    "suggested spell selection preserves the underlying numeric ID")
assertEqual(firstRow.payload.value, "47540",
    "suggested spell selection immediately updates AF's saved widget value")
assertTrue(not firstRow.payload:HasFocus(),
    "spell picker selection returns the field to verified display mode")
assertTrue(firstRow.spellDisplay.shown,
    "spell picker selection immediately shows verified spell details")
assertEqual(firstRow.spellDisplay.icon.texture, 237545,
    "spell picker selection immediately shows the chosen spell icon")
assertEqual(firstRow.spellDisplay.name:GetText(), "Penance",
    "spell picker selection immediately shows the chosen spell name")

harness.spellOverrides[47540] = 111111
harness:FireEvent("SPELLS_CHANGED")
assertTrue(not firstRow.spellDisplay.shown,
    "an uncached current override does not show stale base-spell details")
assertEqual(
    harness.spellDataRequests[#harness.spellDataRequests],
    111111,
    "an uncached current override requests its own spell data"
)
assertEqual(firstRow.payload:GetText(), "47540",
    "override display loading preserves the configured base spell ID")
firstRow.payload:SetFocus()
harness.spellInfo[111111] = {
    name = "Overridden Penance",
    iconID = 111222,
}
harness:FireEvent("SPELL_DATA_LOAD_RESULT", 111111, true)
assertTrue(not firstRow.spellDisplay.shown,
    "spell data completion does not cover a focused numeric editor")
firstRow.payload:ClearFocus()
assertTrue(firstRow.spellDisplay.shown,
    "loaded override details appear after numeric editing ends")
assertEqual(firstRow.spellDisplay.icon.texture, 111222,
    "loaded override details use the effective spell icon")
assertEqual(firstRow.spellDisplay.name:GetText(), "Overridden Penance",
    "loaded override details use the effective spell name")
harness.spellOverrides[47540] = nil
harness:FireEvent("SPELLS_CHANGED")
assertEqual(firstRow.spellDisplay.name:GetText(), "Penance",
    "same-spec spell changes repaint the current effective spell")

local closeCalls = harness.cascadingMenuCloseCalls or 0
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "specialization changes close the visible panel's stale picker")
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("AF_COMBAT_ENTER")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "combat entry closes the picker outside the panel combat mask")
assertTrue(not firstRow.payload:HasFocus(),
    "combat entry releases value-field keyboard focus")

harness.resurrectionCapabilities = {
    normal = false,
    mass = false,
    combat = false,
}
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
assertTrue(not harness.smartResurrection.enabled,
    "classes without resurrection disable Smart Resurrection")
assertTrue(harness.smartResurrection.items[2].disabled,
    "classes without normal resurrection disable the normal mode")
assertTrue(harness.smartResurrection.items[3].disabled,
    "classes without any resurrection disable the combined mode")
assertTrue(not harness.preferMassResurrection.enabled,
    "classes without mass resurrection disable the mass preference")

harness.resurrectionCapabilities = {
    normal = false,
    mass = false,
    combat = true,
}
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
assertTrue(harness.smartResurrection.enabled,
    "combat-only resurrection classes retain Smart Resurrection")
assertTrue(harness.smartResurrection.items[2].disabled,
    "combat-only resurrection classes cannot select normal-only mode")
assertTrue(not harness.smartResurrection.items[3].disabled,
    "combat-only resurrection classes can select combined mode")
assertTrue(not harness.preferMassResurrection.enabled,
    "combat-only resurrection classes keep mass preference disabled")

harness.resurrectionCapabilities = {
    normal = true,
    mass = false,
    combat = false,
}
harness.config.smartResurrection = "normal"
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
assertTrue(harness.smartResurrection.enabled,
    "normal resurrection classes retain Smart Resurrection")
assertTrue(not harness.preferMassResurrection.enabled,
    "specs without mass resurrection disable the mass preference")

harness.resurrectionCapabilities = nil
harness.config.smartResurrection = "disabled"
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")

firstRow.action.onSelect("custom")
assertEqual(harness.config.bindings[1][2], "custom",
    "action switch updates action type")
assertEqual(harness.config.bindings[1][3], "",
    "action switch clears the prior spell payload")
assertTrue(firstRow.editPayload.shown,
    "custom macros retain their separate editor button")
assertEqual(firstRow.editPayload.points[1][1], "RIGHT",
    "custom editor joins the right-aligned row controls")
assertEqual(firstRow.editPayload.points[1][2], firstRow.up,
    "custom editor sits immediately before the move controls")
assertEqual(firstRow.editPayload.points[1][3], "LEFT",
    "custom editor avoids a circular anchor with the flexible value field")
assertEqual(firstRow.payload.points[2][2], firstRow.editPayload,
    "custom macro field flexes up to its visible editor button")
assertEqual(firstRow.payload.points[2][3], "LEFT",
    "custom macro editor remains inside the full-width row")
firstRow.action.onSelect("target")
assertEqual(harness.config.bindings[1][3], nil,
    "payload-free action clears the custom payload slot")
assertTrue(not firstRow.editPayload.shown,
    "payload-free actions hide the editor button")
assertEqual(firstRow.payload.points[2][2], firstRow.up,
    "rows without an editor restore the full flexible value column")
harness.cascadingMenu = nil
firstRow.payload.scripts.OnMouseDown(firstRow.payload, "LeftButton")
assertEqual(harness.cascadingMenu, nil,
    "non-spell fields do not open the spell picker")

harness.smartResurrection.onSelect("normal+combat")
assertEqual(harness.config.smartResurrection, "normal+combat",
    "smart resurrection mode is stored in the active class config")
assertTrue(harness.preferMassResurrection.enabled,
    "mass resurrection preference enables with smart resurrection")
harness.preferMassResurrection.onCheck(false)
assertEqual(harness.config.preferMassResurrection, false,
    "mass resurrection preference is profile-owned")

local macroRow = harness.list.widgets[2]
assertEqual(macroRow.payload.mode, "trim",
    "saved macro payload retains trimmed text mode")
assertTrue(not macroRow.payload.numeric,
    "saved macro payload disables numeric input filtering")
macroRow.payload:SimulateUserText("NamedMacroTwo")
assertEqual(macroRow.payload:GetText(), "NamedMacroTwo",
    "saved macro payload accepts non-numeric text")
macroRow.payload.onEnterPressed("7")
assertEqual(harness.config.bindings[2][3], 7,
    "numeric macro indices are stored as numbers")
assertEqual(type(harness.config.bindings[2][3]), "number",
    "numeric macro index type")
macroRow.payload.onEnterPressed("")
assertEqual(harness.config.bindings[2][3], "",
    "empty macro payload remains visibly empty")
assertTrue(not compiledContains(
    harness.CC.Compile(harness.config),
    "type2"
), "an empty payload disables the runtime binding")

local cursorRow = harness.list.widgets[3]
harness.cursor = {"spell", 4, "spell", 20484}
cursorRow.payload.scripts.OnReceiveDrag()
assertEqual(harness.config.bindings[3][2], "spell",
    "spell cursor switches the action")
assertEqual(harness.config.bindings[3][3], 20484,
    "spell cursor stores its spell ID")

harness.cursor = {"macro", 11}
cursorRow.payload.scripts.OnReceiveDrag()
assertEqual(harness.config.bindings[3][2], "macro",
    "macro cursor switches the action")
assertEqual(harness.config.bindings[3][3], 11,
    "macro cursor stores its macro index")

harness.cursor = {"item", 19019}
cursorRow.payload.scripts.OnReceiveDrag()
assertEqual(harness.config.bindings[3][2], "item",
    "item cursor switches the action")
assertEqual(harness.config.bindings[3][3], "item:19019",
    "item cursor stores a secure item token")
assertEqual(cursorRow.payload.mode, "trim",
    "item payload retains trimmed text mode")
assertTrue(not cursorRow.payload.numeric,
    "item payload disables numeric input filtering")
assertEqual(harness.clearCursorCalls, 3,
    "accepted cursor drops clear the cursor")

local oldConfig = harness.config
local oldCustomBinding = oldConfig.bindings[4]
local customRow = harness.list.widgets[4]
customRow.editPayload.onClick()
local dialog = harness.dialogs[#harness.dialogs]
dialog.content.box:SetText("/say stale confirmation")

local newConfig = {
    enabled = false,
    bindings = {
        {"type4", "custom", "/say new profile"},
    },
}
harness.CC.activeConfig = newConfig
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("BFI_UpdateProfile")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "profile changes close the visible panel's stale picker")
assertEqual(harness.enabledCheckButton.label.textColor[1], "firebrick",
    "visible profile changes refresh the disabled title-row color")
stalePickerCallback()
assertEqual(newConfig.bindings[1][3], "/say new profile",
    "a stale spell picker cannot mutate the newly active profile")
dialog.onConfirm()
assertEqual(newConfig.bindings[1][3], "/say new profile",
    "stale modal cannot mutate the newly active profile")
assertEqual(oldCustomBinding[3], "/say old",
    "stale modal confirmation does not mutate its old profile")

harness.CC.activeConfig = oldConfig
harness:FireCallback("BFI_UpdateProfile")
assertEqual(harness.enabledCheckButton.label.textColor[1], "softlime",
    "returning to an enabled profile refreshes the title-row color")
local deleteRow = harness.list.widgets[5]
deleteRow.delete.onClick()
assertEqual(#oldConfig.bindings, 5,
    "first delete click leaves the binding in place")
local deleteOkay, deleteError = pcall(deleteRow.confirmDelete.onClick)
assertTrue(deleteOkay,
    "confirmed delete updates its local conflict notice: " .. tostring(deleteError))
assertEqual(#oldConfig.bindings, 4, "confirmed delete removes one binding")

harness.enabledCheckButton.onCheck(false)
assertEqual(oldConfig.enabled, false, "module disabled")
assertEqual(harness.enabledCheckButton.label.textColor[1], "firebrick",
    "live disable switches the title-row label to red")
assertEqual(harness.fires[#harness.fires][1], "BFI_UpdateModule",
    "live enable state changes notify module consumers")
assertEqual(harness.fires[#harness.fires][2], "clickCastings",
    "live enable state notification identifies Click Casting")
assertTrue(harness.addButton.enabled,
    "disabled module still permits adding bindings")
for index, row in ipairs(harness.list.widgets) do
    assertTrue(row.capture.enabled,
        "disabled module keeps capture editable " .. index)
    assertTrue(row.action.enabled,
        "disabled module keeps action editable " .. index)
    assertTrue(row.delete.enabled,
        "disabled module keeps deletion editable " .. index)
end

local resetConfig = {
    enabled = true,
    smartResurrection = "disabled",
    preferMassResurrection = true,
    bindings = {
        {"type1", "target"},
        {"type2", "togglemenu"},
    },
}
harness.CC.activeConfig = resetConfig
harness:FireCallback("BFI_RefreshOptions", "clickCastings")
assertEqual(harness.enabledCheckButton.label.textColor[1], "softlime",
    "module reset refreshes the restored enabled color")

harness:FireCallback("BFI_ShowOptionsPanel", "profiles")
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("BFI_UpdateProfile")
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
harness:FireCallback("AF_COMBAT_ENTER")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls,
    "hidden Click Casting panel does not close unrelated cascading menus")

local function CreateVisibleDeleteHarness()
    local deleteHarness = createHarness()
    deleteHarness:FireCallback("BFI_ShowOptionsPanel", "clickCastings")
    return deleteHarness
end

local cancelHarness = CreateVisibleDeleteHarness()
local cancelBindings = cancelHarness.config.bindings
local cancelRow = cancelHarness.list.widgets[2]
local cancelBinding = cancelBindings[2]
cancelRow.delete.onClick()
assertEqual(#cancelBindings, 5,
    "requesting inline deletion does not mutate bindings")
assertEqual(cancelBindings[2], cancelBinding,
    "requesting inline deletion preserves the exact row binding")
assertEqual(cancelRow.pendingDeleteBinding, cancelBinding,
    "pending deletion records the exact binding identity")
assertEqual(cancelRow.pendingDeleteConfig, cancelHarness.config,
    "pending deletion records the exact config identity")
assertTrue(not cancelRow.up.shown and not cancelRow.down.shown
    and not cancelRow.delete.shown,
    "pending deletion hides the ordinary row controls")
assertTrue(cancelRow.cancelDelete.shown and cancelRow.confirmDelete.shown,
    "pending deletion shows inline Cancel and confirmation controls")
assertEqual(cancelRow.cancelDelete.width, 72,
    "inline Cancel has a deliberate double-click-safe target width")
assertEqual(cancelRow.confirmDelete.width, 72,
    "inline Delete has a balanced confirmation target width")
assertEqual(cancelRow.cancelDelete.points[1][1], "RIGHT",
    "inline Cancel is right-aligned")
assertEqual(cancelRow.cancelDelete.points[1][2], cancelRow,
    "inline Cancel occupies the original row-edge delete target")
assertEqual(cancelRow.cancelDelete.points[1][3], "RIGHT",
    "inline Cancel keeps the original delete target's anchor edge")
assertEqual(cancelRow.cancelDelete.points[1][4], -3,
    "inline Cancel keeps the original delete target's inset")
assertEqual(cancelRow.confirmDelete.points[1][1], "RIGHT",
    "inline Delete aligns immediately before Cancel")
assertEqual(cancelRow.confirmDelete.points[1][2], cancelRow.cancelDelete,
    "inline Delete does not occupy the original delete target")
assertEqual(cancelRow.confirmDelete.points[1][3], "LEFT",
    "inline Delete uses Cancel's safe near edge")
assertEqual(cancelRow.payload.points[2][2], cancelRow.confirmDelete,
    "pending rows end their value field before both inline controls")
cancelRow.cancelDelete.onClick()
assertEqual(#cancelBindings, 5,
    "cancelling inline deletion leaves bindings unchanged")
assertEqual(cancelBindings[2], cancelBinding,
    "cancelling inline deletion preserves the requested binding")
assertEqual(cancelRow.pendingDeleteBinding, nil,
    "cancelling inline deletion clears the pending identity")
assertEqual(cancelRow.pendingDeleteConfig, nil,
    "cancelling inline deletion clears the pending config identity")
assertTrue(cancelRow.up.shown and cancelRow.down.shown
    and cancelRow.delete.shown,
    "cancelling inline deletion restores the ordinary row controls")
assertTrue(not cancelRow.cancelDelete.shown
    and not cancelRow.confirmDelete.shown,
    "cancelling inline deletion hides its confirmation controls")
assertEqual(cancelHarness.CC.EncodeBinding(cancelRow.capture.binding),
    cancelBinding[1],
    "cancelling inline deletion preserves the displayed binding")

local confirmHarness = CreateVisibleDeleteHarness()
local confirmBindings = confirmHarness.config.bindings
local firstBinding = confirmBindings[1]
local confirmedBinding = confirmBindings[2]
local thirdBinding = confirmBindings[3]
local fourthBinding = confirmBindings[4]
local fifthBinding = confirmBindings[5]
local confirmRow = confirmHarness.list.widgets[2]
confirmRow.delete.onClick()
confirmRow.confirmDelete.onClick()
assertEqual(#confirmBindings, 4,
    "inline confirmation deletes exactly one binding")
assertEqual(confirmBindings[1], firstBinding,
    "inline confirmation preserves the binding before its row")
assertEqual(confirmBindings[2], thirdBinding,
    "inline confirmation closes the deleted row's exact gap")
assertEqual(confirmBindings[3], fourthBinding,
    "inline confirmation preserves later binding identity")
assertEqual(confirmBindings[4], fifthBinding,
    "inline confirmation preserves the final binding identity")
for _, binding in ipairs(confirmBindings) do
    assertTrue(binding ~= confirmedBinding,
        "inline confirmation removes the requested binding identity")
end

local singlePendingHarness = CreateVisibleDeleteHarness()
local singlePendingBindings = singlePendingHarness.config.bindings
local firstPendingRow = singlePendingHarness.list.widgets[1]
local secondPendingRow = singlePendingHarness.list.widgets[2]
local firstPendingBinding = singlePendingBindings[1]
local secondPendingBinding = singlePendingBindings[2]
firstPendingRow.delete.onClick()
local supersededConfirm = firstPendingRow.confirmDelete.onClick
secondPendingRow.delete.onClick()
assertEqual(#singlePendingBindings, 5,
    "arming another row does not delete the first pending binding")
assertEqual(firstPendingRow.pendingDeleteBinding, nil,
    "arming another row cancels the first pending identity")
assertEqual(firstPendingRow.pendingDeleteConfig, nil,
    "arming another row clears the first pending config identity")
assertTrue(firstPendingRow.delete.shown
    and not firstPendingRow.cancelDelete.shown
    and not firstPendingRow.confirmDelete.shown,
    "arming another row restores the first row's controls")
assertEqual(secondPendingRow.pendingDeleteBinding, secondPendingBinding,
    "only the newly requested row remains pending")
assertEqual(secondPendingRow.pendingDeleteConfig,
    singlePendingHarness.config,
    "the newly requested row owns the sole pending config identity")
supersededConfirm()
assertEqual(#singlePendingBindings, 5,
    "a superseded confirmation cannot delete a binding")
assertEqual(singlePendingBindings[1], firstPendingBinding,
    "a superseded confirmation preserves its original binding")
assertEqual(singlePendingBindings[2], secondPendingBinding,
    "a superseded confirmation preserves the active pending binding")
assertEqual(secondPendingRow.pendingDeleteBinding, secondPendingBinding,
    "a superseded confirmation leaves the active row pending")

local refreshHarness = CreateVisibleDeleteHarness()
local refreshBindings = refreshHarness.config.bindings
local refreshRow = refreshHarness.list.widgets[3]
local refreshBinding = refreshBindings[3]
refreshRow.delete.onClick()
local staleRefreshConfirm = refreshRow.confirmDelete.onClick
refreshHarness:FireCallback("BFI_RefreshOptions", "clickCastings")
assertEqual(refreshRow.pendingDeleteBinding, nil,
    "options refresh cancels pending row deletion")
assertEqual(refreshRow.pendingDeleteConfig, nil,
    "options refresh clears the pending config identity")
assertTrue(refreshRow.delete.shown
    and not refreshRow.cancelDelete.shown
    and not refreshRow.confirmDelete.shown,
    "options refresh restores ordinary row controls")
staleRefreshConfirm()
assertEqual(#refreshBindings, 5,
    "confirmation captured before refresh cannot delete a binding")
assertEqual(refreshBindings[3], refreshBinding,
    "refresh-stale confirmation preserves the exact row binding")

local profileHarness = CreateVisibleDeleteHarness()
local oldProfileBindings = profileHarness.config.bindings
local oldProfileRow = profileHarness.list.widgets[2]
local oldProfileBinding = oldProfileBindings[2]
oldProfileRow.delete.onClick()
local staleProfileConfirm = oldProfileRow.confirmDelete.onClick
local replacementProfile = {
    enabled = true,
    smartResurrection = "disabled",
    preferMassResurrection = true,
    bindings = {
        {"type4", "focus"},
        {"type5", "assist"},
    },
}
local replacementFirstBinding = replacementProfile.bindings[1]
profileHarness.CC.activeConfig = replacementProfile
profileHarness:FireCallback("BFI_UpdateProfile")
assertEqual(oldProfileRow.pendingDeleteBinding, nil,
    "profile replacement cancels pending row deletion")
assertEqual(oldProfileRow.pendingDeleteConfig, nil,
    "profile replacement clears the pending config identity")
staleProfileConfirm()
assertEqual(#oldProfileBindings, 5,
    "profile-stale confirmation cannot mutate the old profile")
assertEqual(oldProfileBindings[2], oldProfileBinding,
    "profile-stale confirmation preserves its old binding")
assertEqual(#replacementProfile.bindings, 2,
    "profile-stale confirmation cannot mutate the active profile")
assertEqual(replacementProfile.bindings[1], replacementFirstBinding,
    "profile-stale confirmation preserves the rebound row identity")

local configIdentityHarness = CreateVisibleDeleteHarness()
local originalConfig = configIdentityHarness.config
local originalConfigBindings = originalConfig.bindings
local configIdentityRow = configIdentityHarness.list.widgets[2]
local sharedConfigBinding = originalConfigBindings[2]
configIdentityRow.delete.onClick()
local replacementConfig = {
    enabled = true,
    smartResurrection = "disabled",
    preferMassResurrection = true,
    bindings = {
        {"type1", "target"},
        sharedConfigBinding,
        {"type3", "focus"},
    },
}
configIdentityHarness.CC.activeConfig = replacementConfig
configIdentityRow.confirmDelete.onClick()
assertEqual(#originalConfigBindings, 5,
    "confirmation cannot mutate the config that originally requested it")
assertEqual(originalConfigBindings[2], sharedConfigBinding,
    "stale-config confirmation preserves the original binding identity")
assertEqual(#replacementConfig.bindings, 3,
    "confirmation cannot cross into a replacement config")
assertEqual(replacementConfig.bindings[2], sharedConfigBinding,
    "config identity guard holds even when both configs share a binding")
assertEqual(configIdentityRow.pendingDeleteBinding, nil,
    "stale-config confirmation clears its pending binding identity")
assertEqual(configIdentityRow.pendingDeleteConfig, nil,
    "stale-config confirmation clears its pending config identity")

local reorderHarness = CreateVisibleDeleteHarness()
local reorderBindings = reorderHarness.config.bindings
local reorderFirst = reorderBindings[1]
local reorderPending = reorderBindings[2]
local reorderThird = reorderBindings[3]
local reorderPendingRow = reorderHarness.list.widgets[2]
local reorderMovingRow = reorderHarness.list.widgets[3]
reorderPendingRow.delete.onClick()
local staleReorderConfirm = reorderPendingRow.confirmDelete.onClick
reorderMovingRow.up.onClick()
assertEqual(reorderPendingRow.pendingDeleteBinding, nil,
    "reordering cancels pending row deletion")
assertEqual(reorderPendingRow.pendingDeleteConfig, nil,
    "reordering clears the pending config identity")
assertEqual(reorderBindings[1], reorderFirst,
    "reordering preserves the leading binding")
assertEqual(reorderBindings[2], reorderThird,
    "reordering moves the requested binding into place")
assertEqual(reorderBindings[3], reorderPending,
    "reordering moves the formerly pending binding without deleting it")
staleReorderConfirm()
assertEqual(#reorderBindings, 5,
    "confirmation captured before reorder cannot delete a rebound row")
assertEqual(reorderBindings[2], reorderThird,
    "reorder-stale confirmation preserves the row's new binding")
assertEqual(reorderBindings[3], reorderPending,
    "reorder-stale confirmation preserves its original binding")

local captureDeleteHarness = CreateVisibleDeleteHarness()
local captureDeleteBindings = captureDeleteHarness.config.bindings
local captureDeleteRow = captureDeleteHarness.list.widgets[3]
local captureDeleteBinding = captureDeleteBindings[3]
captureDeleteRow.capture.onBindingChanged(nil)
assertEqual(#captureDeleteBindings, 5,
    "clearing a binding capture requests confirmation without deleting")
assertEqual(captureDeleteBindings[3], captureDeleteBinding,
    "clearing a binding capture preserves the exact binding identity")
assertEqual(
    captureDeleteHarness.CC.EncodeBinding(captureDeleteRow.capture.binding),
    captureDeleteBinding[1],
    "clearing a binding capture immediately restores its display")
assertEqual(captureDeleteRow.pendingDeleteBinding, captureDeleteBinding,
    "clearing a binding capture uses the inline deletion confirmation")
assertEqual(captureDeleteRow.pendingDeleteConfig, captureDeleteHarness.config,
    "capture deletion records the active config identity")
assertTrue(captureDeleteRow.cancelDelete.shown
    and captureDeleteRow.confirmDelete.shown,
    "clearing a binding capture exposes the inline confirmation controls")

do
    local case = {}
    case.harness = CreateVisibleDeleteHarness()
    case.oldConfig = case.harness.config
    case.oldBindings = case.oldConfig.bindings
    case.oldBinding = case.oldBindings[5]
    case.row = case.harness.list.widgets[5]
    case.row.delete.onClick()
    case.staleConfirm = case.row.confirmDelete.onClick
    case.row:SetOnHide(function()
        case.pendingBindingAtHide = case.row.pendingDeleteBinding
        case.pendingConfigAtHide = case.row.pendingDeleteConfig
    end)
    case.newConfig = {
        enabled = true,
        smartResurrection = "disabled",
        preferMassResurrection = true,
        bindings = {
            {"type1", "focus"},
            {"type2", "assist"},
        },
    }
    case.harness.CC.activeConfig = case.newConfig
    case.harness:FireCallback("BFI_UpdateProfile")
    assertTrue(not case.row.shown,
        "profile shrink hides a pending row outside the new binding count")
    assertEqual(case.pendingBindingAtHide, nil,
        "profile shrink clears pending binding identity before row Hide")
    assertEqual(case.pendingConfigAtHide, nil,
        "profile shrink clears pending config identity before row Hide")
    assertEqual(case.row.pendingDeleteBinding, nil,
        "profile shrink leaves the hidden row without pending binding state")
    assertEqual(case.row.pendingDeleteConfig, nil,
        "profile shrink leaves the hidden row without pending config state")
    assertEqual(#case.oldBindings, 5,
        "profile shrink does not mutate the old profile")
    assertEqual(case.oldBindings[5], case.oldBinding,
        "profile shrink preserves the old pending binding")

    case.newConfig.bindings[3] = {"type3", "target"}
    case.newConfig.bindings[4] = {"type4", "togglemenu"}
    case.newConfig.bindings[5] = {"type5", "focus"}
    case.reusedBinding = case.newConfig.bindings[5]
    case.harness:FireCallback("BFI_RefreshOptions", "clickCastings")
    assertEqual(case.harness.list.widgets[5], case.row,
        "profile expansion reuses the previously hidden row")
    assertTrue(case.row.shown,
        "profile expansion shows the reused row")
    assertTrue(case.row.delete.shown
        and not case.row.cancelDelete.shown
        and not case.row.confirmDelete.shown,
        "reused row starts with ordinary controls and no stale confirmation")
    case.staleConfirm()
    assertEqual(#case.oldBindings, 5,
        "shrink-stale confirmation cannot mutate the old profile")
    assertEqual(case.oldBindings[5], case.oldBinding,
        "shrink-stale confirmation preserves its original binding")
    assertEqual(#case.newConfig.bindings, 5,
        "shrink-stale confirmation cannot delete from a reused row")
    assertEqual(case.newConfig.bindings[5], case.reusedBinding,
        "shrink-stale confirmation preserves the reused binding identity")
end

do
    local case = {}
    case.harness = CreateVisibleDeleteHarness()
    case.bindings = case.harness.config.bindings
    case.binding = case.bindings[4]
    case.row = case.harness.list.widgets[4]
    case.panel = case.harness.namedFrames.BFIOptionsFrame_ClickCastingsPanel
    case.row.delete.onClick()
    case.staleConfirm = case.row.confirmDelete.onClick
    assertTrue(case.panel.shown,
        "Click Casting panel is visible before combat entry")
    case.harness:FireCallback("AF_COMBAT_ENTER")
    assertTrue(case.panel.shown,
        "combat entry keeps the protected Click Casting panel visible")
    assertEqual(case.row.pendingDeleteBinding, nil,
        "visible combat entry clears pending binding identity")
    assertEqual(case.row.pendingDeleteConfig, nil,
        "visible combat entry clears pending config identity")
    assertTrue(case.row.delete.shown
        and not case.row.cancelDelete.shown
        and not case.row.confirmDelete.shown,
        "visible combat entry restores ordinary row controls")
    case.staleConfirm()
    assertEqual(#case.bindings, 5,
        "combat-stale confirmation cannot delete a binding")
    assertEqual(case.bindings[4], case.binding,
        "combat-stale confirmation preserves the exact binding")
end

do
    local case = {}
    case.harness = CreateVisibleDeleteHarness()
    case.bindings = case.harness.config.bindings
    case.binding = case.bindings[4]
    case.row = case.harness.list.widgets[4]
    case.panel = case.harness.namedFrames.BFIOptionsFrame_ClickCastingsPanel
    case.row.delete.onClick()
    case.staleConfirm = case.row.confirmDelete.onClick
    case.harness:FireCallback("BFI_ShowOptionsPanel", "profiles")
    assertTrue(not case.panel.shown,
        "switching panels hides Click Casting")
    assertEqual(case.row.pendingDeleteBinding, nil,
        "panel hide clears pending binding identity")
    assertEqual(case.row.pendingDeleteConfig, nil,
        "panel hide clears pending config identity")
    assertTrue(case.row.delete.shown
        and not case.row.cancelDelete.shown
        and not case.row.confirmDelete.shown,
        "panel hide restores ordinary row controls")
    case.staleConfirm()
    assertEqual(#case.bindings, 5,
        "panel-hide-stale confirmation cannot delete a binding")
    assertEqual(case.bindings[4], case.binding,
        "panel-hide-stale confirmation preserves the exact binding")
end

local failingHarness = createHarness()
failingHarness.failTitledPane = true
failingHarness:FireCallback("BFI_ShowOptionsPanel", "clickCastings")
local optionsError = failingHarness.BFI.vars.clickCastingOptionsError
assertTrue(type(optionsError) == "string"
    and optionsError:find("during panel header", 1, true),
    "panel construction failures retain their exact stage")
assertEqual(failingHarness.printedError, optionsError,
    "panel construction failures are printed despite AF callback isolation")
assertEqual(failingHarness.errorHandlerMessage, optionsError,
    "panel construction failures reach the configured Lua error handler")

print("click_casting_options_test: ok")
