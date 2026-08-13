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

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetText(text)
        self.text = text
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
    }
    local L = setmetatable({}, {
        __index = function(_, key) return key end,
    })
    local AF = {
        player = {class = "PRIEST"},
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
        state.enabledCheckButton = checkButton
        return checkButton
    end

    function AF.CreateDropdown(parent, width)
        local dropdown = newWidget("dropdown", parent)
        dropdown.width = width
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

    function AF.RegisterCallback(event, callback)
        state.callbacks[event] = callback
    end

    function AF.SetPoint(widget, ...)
        widget.points[#widget.points + 1] = {...}
    end

    function AF.WrapTextInColor(text)
        return text
    end

    local config = {
        enabled = true,
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
harness:FireCallback("BFI_ShowOptionsPanel", "clickCastings")
assertEqual(#harness.combatProtected, 1,
    "settings panel receives combat protection")
assertEqual(#harness.list.widgets, 5, "initial binding rows")

local firstRow = harness.list.widgets[1]
firstRow.action.onSelect("custom")
assertEqual(harness.config.bindings[1][2], "custom",
    "action switch updates action type")
assertEqual(harness.config.bindings[1][3], "",
    "action switch clears the prior spell payload")
firstRow.action.onSelect("target")
assertEqual(harness.config.bindings[1][3], nil,
    "payload-free action clears the custom payload slot")

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
harness:FireCallback("BFI_UpdateProfile")
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

print("click_casting_options_test: ok")
