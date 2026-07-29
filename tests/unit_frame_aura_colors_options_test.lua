local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ))
    end
end

local function assertTrue(value, message)
    if not value then
        fail(message or "expected a truthy value")
    end
end

local function assertColor(actual, expected, message)
    assertEqual(type(actual), "table", message .. " type")
    for index = 1, 4 do
        assertEqual(
            actual[index],
            expected[index],
            message .. " component " .. index
        )
    end
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function assertDeepEqual(actual, expected, message)
    if type(actual) ~= type(expected) then
        fail(message .. ": type mismatch")
    end
    if type(actual) ~= "table" then
        if type(actual) == "number"
            and actual ~= actual
            and expected ~= expected
        then
            return
        end
        assertEqual(actual, expected, message)
        return
    end
    for key, value in pairs(expected) do
        assertDeepEqual(actual[key], value, message .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            fail(message .. ": unexpected key " .. tostring(key))
        end
    end
end

local callbacks = {}
local updateEvents = {}
local createdButtons = {}
local createdColorPickers = {}
local editBoxes = {}
local activeColorPicker
local activePickerCancelCount = 0
local lastDialog
local capturedScrollGrid

local function newWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        shown = true,
        enterHooks = {},
        leaveHooks = {},
        points = {},
    }

    function widget:SetAllPoints(...)
        self.allPoints = {...}
    end

    function widget:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:SetOnHide(callback)
        self.onHide = callback
    end

    function widget:Show()
        self.shown = true
    end

    function widget:Hide()
        local wasShown = self.shown
        self.shown = false
        if wasShown and self.onHide then
            self.onHide(self)
        end
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:IsVisible()
        return self.shown
            and (not self.parent or self.parent:IsVisible())
    end

    function widget:SetOnClick(callback)
        self.onClick = callback
    end

    function widget:Click(mouseButton)
        assertTrue(self.onClick, self.kind .. " click callback")
        self.onClick(self, mouseButton)
    end

    function widget:EnablePushEffect(value)
        self.pushEffect = value
    end

    function widget:RegisterForClicks(...)
        self.registeredClicks = {...}
    end

    function widget:SetTexture(...)
        self.textureValue = {...}
    end

    function widget:SetText(value)
        self.text = value == nil and "" or tostring(value)
        if self.onTextChanged then
            self.onTextChanged(self:GetValue(), false, self)
        end
    end

    function widget:GetValue()
        if self.mode == "number" then
            return tonumber(self.text)
        end
        return self.text or ""
    end

    function widget:UserText(value)
        self.text = tostring(value)
        if self.onTextChanged then
            self.onTextChanged(self:GetValue(), true, self)
        end
    end

    function widget:Clear()
        self:SetText("")
    end

    function widget:SetOnTextChanged(callback)
        self.onTextChanged = callback
    end

    function widget:SetOnEnterPressed(callback)
        self.onEnterPressed = callback
    end

    function widget:SetOnEscapePressed(callback)
        self.onEscapePressed = callback
    end

    function widget:Enter(value)
        if value ~= nil then
            self:UserText(value)
        end
        local callback = self.onEnterPressed
        if callback then
            callback(self:GetValue(), self)
        end
        self:Hide()
    end

    function widget:Escape()
        local callback = self.onEscapePressed
        if callback then
            callback(self)
        end
        self:Hide()
    end

    function widget:SetBorderColor(...)
        self.borderColor = {...}
    end

    function widget:SetOnConfirm(callback)
        self.onConfirm = callback
    end

    function widget:Open()
        activeColorPicker = self
    end

    function widget:Confirm(r, g, b, a)
        if activeColorPicker ~= self then return false end
        activeColorPicker = nil
        if self.onConfirm then
            self.onConfirm(r, g, b, a)
        end
        return true
    end

    function widget:HookOnEnter(callback)
        self.enterHooks[#self.enterHooks + 1] = callback
    end

    function widget:HookOnLeave(callback)
        self.leaveHooks[#self.leaveHooks + 1] = callback
    end

    function widget:GetOnEnter()
        return function()
            self:EnterMouse()
        end
    end

    function widget:GetOnLeave()
        return function()
            self:LeaveMouse()
        end
    end

    function widget:EnterMouse()
        if self.onEnter then self.onEnter(self) end
        for _, callback in ipairs(self.enterHooks) do
            callback(self)
        end
    end

    function widget:LeaveMouse()
        if self.onLeave then self.onLeave(self) end
        for _, callback in ipairs(self.leaveHooks) do
            callback(self)
        end
    end

    function widget:SetWidth(value)
        self.width = value
    end

    function widget:SetJustifyH(value)
        self.justifyH = value
    end

    function widget:SetJustifyV(value)
        self.justifyV = value
    end

    function widget:SetWordWrap(value)
        self.wordWrap = value
    end

    function widget:SetColor(value)
        if self.kind == "colorPicker" then
            self.color = {
                value[1],
                value[2],
                value[3],
                value[4],
            }
        else
            self.fontColor = value
        end
    end

    return widget
end

local tooltip = {
    hideCount = 0,
    spellCalls = {},
}

function tooltip:Hide()
    self.hideCount = self.hideCount + 1
end

function tooltip:Show()
    self.shown = true
end

function tooltip:SetOwner(owner)
    self.owner = owner
end

function tooltip:SetSpellByID(spellID)
    assertTrue(
        type(spellID) == "number"
            and spellID > 0
            and spellID == math.floor(spellID),
        "tooltip received malformed spell ID"
    )
    self.spellCalls[#self.spellCalls + 1] = spellID
end

function tooltip:SetPoint(...)
    self.point = {...}
end

local AF = {
    isRetail = true,
    Tooltip2 = tooltip,
}

function AF.CreateFrame(parent, name)
    local frame = newWidget("frame", parent)
    frame.name = name
    return frame
end

function AF.CreateFontString(parent, text)
    local fontString = newWidget("fontString", parent)
    fontString:SetText(text or "")
    return fontString
end

function AF.CreateButton(parent, text)
    local button = newWidget("button", parent)
    button.text = text
    button.texture = newWidget("texture", button)
    createdButtons[#createdButtons + 1] = button
    return button
end

function AF.CreateColorPicker(parent)
    local picker = newWidget("colorPicker", parent)
    createdColorPickers[#createdColorPickers + 1] = picker
    return picker
end

function AF.CreateEditBox(parent, label, _, _, mode)
    local editBox = newWidget("editBox", parent)
    editBox.label = label
    editBox.mode = mode
    editBox.text = ""
    editBoxes[#editBoxes + 1] = editBox
    return editBox
end

function AF.GetEditBox(parent, label, _, _, mode)
    local editBox = AF.CreateEditBox(parent, label, nil, nil, mode)
    editBox.transient = true
    return editBox
end

function AF.CreateScrollGrid(
    parent,
    name,
    verticalMargin,
    horizontalMargin,
    slotColumn,
    slotRow,
    slotWidth,
    slotHeight,
    slotSpacing
)
    local scroll = newWidget("scrollGrid", parent)
    capturedScrollGrid = {
        name = name,
        verticalMargin = verticalMargin,
        horizontalMargin = horizontalMargin,
        slotColumn = slotColumn,
        slotRow = slotRow,
        slotWidth = slotWidth,
        slotHeight = slotHeight,
        slotSpacing = slotSpacing,
        widget = scroll,
    }
    function scroll:SetWidgets(widgets)
        self.widgets = widgets
        for _, widget in ipairs(widgets) do
            widget:Show()
        end
    end
    return scroll
end

function AF.CreateObjectPool(creation, reset)
    local pool = {
        active = {},
        inactive = {},
    }

    function pool:Acquire()
        local object = table.remove(self.inactive)
        if not object then
            object = creation(self)
        end
        self.active[#self.active + 1] = object
        object:Show()
        return object
    end

    function pool:ReleaseAll()
        for index = #self.active, 1, -1 do
            local object = self.active[index]
            reset(self, object)
            self.active[index] = nil
            self.inactive[#self.inactive + 1] = object
        end
    end

    return pool
end

function AF.CancelColorPicker(owner)
    if not activeColorPicker
        or (owner and owner ~= activeColorPicker)
    then
        return false
    end
    activePickerCancelCount = activePickerCancelCount + 1
    activeColorPicker = nil
    return true
end

function AF.GetDialog(parent, text)
    local dialog = newWidget("dialog", parent)
    dialog.text = text
    dialog.active = true

    function dialog:SetOnConfirm(callback)
        self.onConfirm = callback
    end

    function dialog:Confirm()
        local callback = self.onConfirm
        if callback then callback() end
        self:Hide()
    end

    function dialog:Cancel()
        self:Hide()
    end

    local inheritedHide = dialog.Hide
    function dialog:Hide()
        self.active = false
        inheritedHide(self)
    end

    lastDialog = dialog
    return dialog
end

function AF.IsDialogActive(dialog)
    return dialog and dialog.active == true
end

function AF.RegisterCallback(event, callback)
    callbacks[event] = callbacks[event] or {}
    callbacks[event][#callbacks[event] + 1] = callback
end

function AF.Fire(event, ...)
    if event == "BFI_UpdateConfig" then
        updateEvents[#updateEvents + 1] = {...}
    end
    for _, callback in ipairs(callbacks[event] or {}) do
        callback(nil, ...)
    end
end

function AF.GetGradientText(text)
    return text
end

function AF.GetColorTable()
    return {0.9, 0.4, 0.1, 1}
end

function AF.GetIcon(name)
    return "icon:" .. name
end

function AF.GetIconString(name)
    return "[" .. name .. "]"
end

function AF.IsBlank(value)
    return value == nil or value == ""
end

function AF.Merge(target, source)
    for key, value in pairs(source) do
        target[key] = copy(value)
    end
end

function AF.SetPoint(widget, ...)
    widget:SetPoint(...)
end

function AF.Sort(items, firstKey, firstOrder, secondKey, secondOrder)
    assertEqual(firstOrder, "ascending", "first sort order")
    assertEqual(secondOrder, "ascending", "second sort order")
    table.sort(items, function(left, right)
        if left[firstKey] ~= right[firstKey] then
            return left[firstKey] < right[firstKey]
        end
        return left[secondKey] < right[secondKey]
    end)
end

function AF.SpellExists(spellID)
    return spellID == 101
        or spellID == 202
        or spellID == 303
        or spellID == 404
        or spellID == 505
        or spellID == 999
end

function AF.GetSpellInfo(spellID)
    assertTrue(
        type(spellID) == "number"
            and spellID > 0
            and spellID == math.floor(spellID),
        "spell lookup received malformed ID"
    )
    if AF.SpellExists(spellID) then
        return "Spell " .. spellID, "spell-icon:" .. spellID
    end
end

function AF.WrapTextInColor(text)
    return text
end

local blacklist = {
    [777] = true,
}
local priorities = {
    [888] = 9,
}
local defaultColors = {
    [999] = {0.7, 0.6, 0.5, 0.4},
}
local A = {
    config = {
        blacklist = blacklist,
        priorities = priorities,
        colors = {
            [101] = {0.1, 0.2, 0.3, 0.4},
            [202] = {0.2, 0.3, 0.4, 0.5},
            [303] = {0 / 0, 0.2, 0.3, 1},
            legacy = "red",
            [false] = {0.8, 0.7, 0.6, 0.5},
        },
    },
}

function A.GetDefaults(which)
    assertEqual(which, "colors", "defaults surface")
    return copy(defaultColors)
end

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local BFI = {
    L = L,
    modules = {
        Auras = A,
        UnitFrames = {
            HasNativeAuraContainerBackend = function()
                return true
            end,
        },
    },
}

local rootContentPane = newWidget("rootContentPane")
local environment = {
    _G = false,
    AbstractFramework = AF,
    BFIOptionsFrame_ContentPane = rootContentPane,
    RESET = "Reset",
    SEARCH = "Search",
    assert = assert,
    error = error,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    wipe = function(value)
        for key in pairs(value) do
            value[key] = nil
        end
    end,
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error("unexpected Colors options global: " .. tostring(key), 2)
    end,
})

local chunk, loadError = loadfile("Options/Auras.lua")
assertTrue(chunk, loadError)
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

local function countUpdates()
    return #updateEvents
end

local function findRow(spellID)
    for _, widget in ipairs(capturedScrollGrid.widget.widgets or {}) do
        if widget.spell == spellID then
            return widget
        end
    end
end

local function assertOnlyRow(spellID, message)
    local widgets = capturedScrollGrid.widget.widgets
    assertEqual(#widgets, 2, message .. " count")
    assertEqual(widgets[2].spell, spellID, message .. " spell")
end

AF.Fire("BFI_ShowOptionsPanel", "auras")

local panel = capturedScrollGrid.widget.parent.parent
assertTrue(panel, "Auras panel")
assertEqual(capturedScrollGrid.slotColumn, 2, "grid columns")
assertEqual(capturedScrollGrid.slotRow, 13, "wrapped-description grid rows")
assertEqual(capturedScrollGrid.slotHeight, 20, "grid row height")
assertEqual(capturedScrollGrid.slotSpacing, 5, "grid spacing")
assertEqual(panel.description.wordWrap, true, "description wrapping")
assertTrue(
    panel.description.text:find(
        "exactly the same color share one family",
        1,
        true
    ) ~= nil,
    "exact-color-family explanation"
)
assertTrue(
    panel.description.text:find(
        "whole colored row is hidden",
        1,
        true
    ) ~= nil,
    "reaction fail-closed explanation"
)
assertEqual(findRow(777), nil, "blacklist leaked into Colors panel")
assertEqual(findRow(888), nil, "priorities leaked into Colors panel")

local malformedColorRow = assert(findRow(303))
assertColor(
    malformedColorRow.colorPicker.color,
    {0.5, 0.5, 0.5, 1},
    "non-finite saved color fallback"
)
local legacyRow = assert(findRow("legacy"))
assertColor(
    legacyRow.colorPicker.color,
    {0.5, 0.5, 0.5, 1},
    "malformed saved color fallback"
)
local falseIDRow = assert(findRow(false))
local tooltipCallsBefore = #tooltip.spellCalls
legacyRow:EnterMouse()
falseIDRow:EnterMouse()
assertEqual(
    #tooltip.spellCalls,
    tooltipCallsBefore,
    "malformed IDs reached tooltip"
)
local updatesBefore = countUpdates()
falseIDRow:Click("RightButton")
assertEqual(A.config.colors[false], nil, "false ID removal")
assertEqual(countUpdates(), updatesBefore + 1, "false ID removal update")
updatesBefore = countUpdates()
assert(findRow("legacy")):Click("RightButton")
assertEqual(A.config.colors.legacy, nil, "string ID removal")
assertEqual(countUpdates(), updatesBefore + 1, "string ID removal update")

local row101 = assert(findRow(101))
row101:EnterMouse()
assertEqual(
    tooltip.spellCalls[#tooltip.spellCalls],
    101,
    "valid spell tooltip"
)

row101:Click("LeftButton")
local escapedInput = editBoxes[#editBoxes]
escapedInput:Escape()
-- Simulate AF immediately lending the released transient editor elsewhere.
-- The Auras panel must no longer treat that visible pooled widget as its own.
escapedInput:Show()
tooltipCallsBefore = #tooltip.spellCalls
assert(findRow(101)):EnterMouse()
assertEqual(
    #tooltip.spellCalls,
    tooltipCallsBefore + 1,
    "escaped pooled editor retained ownership"
)
escapedInput:Hide()

row101.colorPicker:Open()
local cancelBefore = activePickerCancelCount
capturedScrollGrid.widget.parent.search:UserText("202")
assertEqual(
    activePickerCancelCount,
    cancelBefore + 1,
    "list rebuild picker cancellation"
)
assertEqual(activeColorPicker, nil, "rebound picker session")
assertOnlyRow(202, "search-triggered rebind")
assertEqual(
    row101.colorPicker:Confirm(1, 1, 1, 1),
    false,
    "stale picker confirmation"
)
assertColor(
    A.config.colors[101],
    {0.1, 0.2, 0.3, 0.4},
    "stale picker changed source color"
)
capturedScrollGrid.widget.parent.search:UserText("")

row101 = assert(findRow(101))
row101.colorPicker:Open()
row101.colorPicker:Confirm(0.4, 0.5, 0.6, 0.7)
assertColor(
    A.config.colors[101],
    {0.4, 0.5, 0.6, 0.7},
    "color confirmation"
)
updatesBefore = countUpdates()
row101.colorPicker:Open()
AF.CancelColorPicker(row101.colorPicker)
assertEqual(countUpdates(), updatesBefore, "color cancellation update")
assertColor(
    A.config.colors[101],
    {0.4, 0.5, 0.6, 0.7},
    "color cancellation mutation"
)

local addButton = capturedScrollGrid.widget.widgets[1]
updatesBefore = countUpdates()
addButton:Click("LeftButton")
local addInput = editBoxes[#editBoxes]
addInput:Enter(404)
assertColor(
    A.config.colors[404],
    {0.9, 0.4, 0.1, 1},
    "new spell default color"
)
assertEqual(countUpdates(), updatesBefore + 1, "add update")
updatesBefore = countUpdates()
capturedScrollGrid.widget.widgets[1]:Click("LeftButton")
local noOpInput = editBoxes[#editBoxes]
noOpInput:Enter(202)
assertEqual(countUpdates(), updatesBefore, "add-existing no-op update")
noOpInput:Show()
tooltipCallsBefore = #tooltip.spellCalls
assert(findRow(202)):EnterMouse()
assertEqual(
    #tooltip.spellCalls,
    tooltipCallsBefore + 1,
    "confirmed pooled editor retained ownership"
)
noOpInput:Hide()

updatesBefore = countUpdates()
assert(findRow(101)):Click("LeftButton")
editBoxes[#editBoxes]:Enter(505)
assertEqual(A.config.colors[101], nil, "edit retained old ID")
assertColor(
    A.config.colors[505],
    {0.4, 0.5, 0.6, 0.7},
    "edit moved color"
)
assertEqual(countUpdates(), updatesBefore + 1, "edit update")

updatesBefore = countUpdates()
assert(findRow(505)):Click("LeftButton")
editBoxes[#editBoxes]:Enter(505)
assertEqual(countUpdates(), updatesBefore, "same-ID edit update")
assertColor(
    A.config.colors[505],
    {0.4, 0.5, 0.6, 0.7},
    "same-ID edit mutation"
)

local color202 = copy(A.config.colors[202])
updatesBefore = countUpdates()
assert(findRow(505)):Click("LeftButton")
editBoxes[#editBoxes]:Enter(202)
assertEqual(countUpdates(), updatesBefore, "collision edit update")
assertColor(A.config.colors[202], color202, "collision target color")
assertColor(
    A.config.colors[505],
    {0.4, 0.5, 0.6, 0.7},
    "collision source color"
)

local search = capturedScrollGrid.widget.parent.search
search:UserText("spell 505")
assertOnlyRow(505, "name search")
search:UserText("202")
assertOnlyRow(202, "ID search")
search:UserText("")

updatesBefore = countUpdates()
assert(findRow(202)):Click("RightButton")
assertEqual(A.config.colors[202], nil, "valid delete")
assertEqual(countUpdates(), updatesBefore + 1, "valid delete update")

local reset = capturedScrollGrid.widget.parent.reset
local beforeResetCancel = copy(A.config.colors)
updatesBefore = countUpdates()
reset:Click("LeftButton")
assertTrue(lastDialog and lastDialog.active, "reset dialog")
lastDialog:Cancel()
assertDeepEqual(A.config.colors, beforeResetCancel, "reset cancellation")
assertEqual(countUpdates(), updatesBefore, "reset cancellation update")

reset:Click("LeftButton")
lastDialog:Confirm()
assertDeepEqual(A.config.colors, defaultColors, "reset confirmation")
assertEqual(countUpdates(), updatesBefore + 1, "reset confirmation update")
assertEqual(A.config.blacklist, blacklist, "reset replaced blacklist")
assertEqual(A.config.priorities, priorities, "reset replaced priorities")
assertEqual(blacklist[777], true, "reset mutated blacklist")
assertEqual(priorities[888], 9, "reset mutated priorities")

local defaultRow = assert(findRow(999))
defaultRow.colorPicker:Open()
capturedScrollGrid.widget.widgets[1]:Click("LeftButton")
local openInput = editBoxes[#editBoxes]
openInput:UserText(999)
cancelBefore = activePickerCancelCount
local tooltipHidesBefore = tooltip.hideCount
AF.Fire("BFI_ShowOptionsPanel", "unitFrames")
assertEqual(
    activePickerCancelCount,
    cancelBefore + 1,
    "panel hide picker cancellation"
)
assertEqual(openInput:IsShown(), false, "panel hide input")
assertTrue(
    tooltip.hideCount > tooltipHidesBefore,
    "panel hide tooltip cleanup"
)
assertEqual(panel:IsShown(), false, "panel hide state")

print("unit_frame_aura_colors_options_test.lua: ok")
