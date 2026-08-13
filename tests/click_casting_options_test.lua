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
    end

    function widget:GetParent()
        return self.parent
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

    function widget:SetAllPoints()
        self.allPoints = true
    end

    function widget:SetBinding(binding)
        self.binding = binding
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

    function widget:SetTextColor(color)
        self.textColor = color
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
        fires = {},
        namedFrames = {},
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
        return button
    end

    function AF.CreateCheckButton(parent, text)
        local checkButton = newWidget("checkButton", parent)
        checkButton.text = text
        if text == L["Enabled"] then
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

    function AF.CreateEditBox(parent, _, width, height)
        local editBox = newWidget("editBox", parent)
        editBox.width = width
        editBox.height = height
        editBox.confirmBtn = newWidget("confirmButton", editBox)
        function editBox:SetConfirmButton(callback)
            self.onConfirmValue = callback
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

    function AF.CreateTitledPane(parent, title, _, _, color)
        local pane = newWidget("titledPane", parent)
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

    function AF.GetLocalizedClassName(class)
        return class
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
    CC.activeConfig = config
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
        C_Timer = {
            After = function(_, callback) callback() end,
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
assertEqual(harness.enabledCheckButton.text, "Enabled",
    "enabled click casting uses concise state text")
assertEqual(harness.enabledCheckButton.textColor, "softlime",
    "enabled click casting uses the standard green state color")
assertTrue(harness.headerPane ~= nil,
    "viewport heading uses the standard titled-pane treatment")
assertEqual(harness.headerPane.points[1][1], "TOPLEFT",
    "viewport heading begins at the left content margin")
assertEqual(harness.headerPane.points[2][1], "TOPRIGHT",
    "viewport heading line spans the full content width")
assertEqual(harness.headerPane.color, "BFI",
    "viewport heading uses the BFI signature accent")
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
assertEqual(harness.enabledCheckButton.points[1][2], harness.headerPane.line,
    "controls reflow directly beneath the accent line")
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
assertEqual(firstRow.payload.width, 239,
    "spell field uses the space released by the picker button")
assertEqual(firstRow.payload.label, "Spell ID or click to pick",
    "spell field has an in-field picker prompt")
assertEqual(firstRow.payload:GetText(), "2061",
    "saved spell ID is displayed as text")
firstRow.payload.scripts.OnMouseDown(firstRow.payload, "LeftButton")
assertEqual(harness.cascadingMenu.owner, firstRow.payload,
    "spell picker opens from and anchors to the value field")
assertEqual(harness.cascadingMenu.items[1].text, "Class Spells",
    "spell picker groups class spells")
assertEqual(harness.cascadingMenu.items[2].text, "Specialization Spells",
    "spell picker groups current-spec spells")
harness.cascadingMenu.items[2].children[1].callback()
assertEqual(harness.config.bindings[1][3], 47540,
    "suggested spell selection persists its spell ID")
assertEqual(firstRow.payload:GetText(), "47540",
    "suggested spell selection immediately populates the value field")

local closeCalls = harness.cascadingMenuCloseCalls or 0
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "specialization changes close the visible panel's stale picker")
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("AF_COMBAT_ENTER")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "combat entry closes the picker outside the panel combat mask")

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
assertEqual(firstRow.payload.width, 190,
    "custom macro field leaves room for its editor button")
firstRow.action.onSelect("target")
assertEqual(harness.config.bindings[1][3], nil,
    "payload-free action clears the custom payload slot")
assertTrue(not firstRow.editPayload.shown,
    "payload-free actions hide the editor button")
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
assertEqual(harness.clearCursorCalls, 3,
    "accepted cursor drops clear the cursor")

local oldConfig = harness.config
local oldCustomBinding = oldConfig.bindings[4]
local customRow = harness.list.widgets[4]
customRow.editPayload.onClick()
local dialog = harness.dialogs[#harness.dialogs]
dialog.content.box:SetText("/say stale confirmation")

local newConfig = {
    enabled = true,
    bindings = {
        {"type4", "custom", "/say new profile"},
    },
}
harness.CC.activeConfig = newConfig
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("BFI_UpdateProfile")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls + 1,
    "profile changes close the visible panel's stale picker")
dialog.onConfirm()
assertEqual(newConfig.bindings[1][3], "/say new profile",
    "stale modal cannot mutate the newly active profile")
assertEqual(oldCustomBinding[3], "/say old",
    "stale modal confirmation does not mutate its old profile")

harness.CC.activeConfig = oldConfig
harness:FireCallback("BFI_UpdateProfile")
local deleteRow = harness.list.widgets[5]
local deleteOkay, deleteError = pcall(deleteRow.delete.onClick)
assertTrue(deleteOkay,
    "delete updates its local conflict notice: " .. tostring(deleteError))
assertEqual(#oldConfig.bindings, 4, "delete removes one binding")

harness.enabledCheckButton.onCheck(false)
assertEqual(oldConfig.enabled, false, "module disabled")
assertEqual(harness.enabledCheckButton.text, "Disabled",
    "disabled click casting updates its state text")
assertEqual(harness.enabledCheckButton.textColor, "firebrick",
    "disabled click casting uses the standard red state color")
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

harness:FireCallback("BFI_ShowOptionsPanel", "profiles")
closeCalls = harness.cascadingMenuCloseCalls
harness:FireCallback("BFI_UpdateProfile")
harness:FireCallback("AF_PLAYER_SPEC_UPDATE")
harness:FireCallback("AF_COMBAT_ENTER")
assertEqual(harness.cascadingMenuCloseCalls, closeCalls,
    "hidden Click Casting panel does not close unrelated cascading menus")

print("click_casting_options_test: ok")
