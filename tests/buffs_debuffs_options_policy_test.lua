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
    assertEqual(value == true, true, message)
end

local function assertFalse(value, message)
    assertEqual(value == false, true, message)
end

local function assertNil(value, message)
    assertEqual(value, nil, message)
end

local backendByPane = {}
local stateByPane = {}
local dispatchPendingByPane = {}
local callbacks = {}

local environment = setmetatable({}, {__index = _G})
environment._G = environment

local AF = {}
function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end
environment.AbstractFramework = AF

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

local BD = {
    SECURE_AURA_HEADER_BACKEND = "secureAuraHeader",
    CUSTOM_AURA_CONTAINER_BACKEND = "customAuraContainer",
    config = {
        buffs = {
            separateOwn = 0,
        },
        debuffs = {
            separateOwn = 0,
        },
    },
}

function BD.GetAuraBackend(which)
    return backendByPane[which]
end

function BD.GetCustomAuraContainerState(which)
    return stateByPane[which]
end

function BD.IsBuffsDebuffsUpdatePending(which)
    return dispatchPendingByPane[which] == true
end

local BFI = {
    L = L,
    modules = {
        BuffsDebuffs = BD,
    },
}

local chunk = assert(loadfile("Options/BuffsDebuffs.lua"))
setfenv(chunk, environment)
chunk("BFInfinite", BFI)

assertTrue(type(callbacks.BFI_RefreshOptions) == "function",
    "refresh callback registered")
assertTrue(type(callbacks.BFI_ShowOptionsPanel) == "function",
    "show callback registered")

local function SetLegacyBackend()
    backendByPane.buffs = BD.SECURE_AURA_HEADER_BACKEND
    backendByPane.debuffs = BD.SECURE_AURA_HEADER_BACKEND
    stateByPane.buffs = nil
    stateByPane.debuffs = nil
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.separateOwn = 0
    BD.config.debuffs.separateOwn = 0
end

local function SetCustomBuffsBackend()
    backendByPane.buffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    backendByPane.debuffs = nil
    stateByPane.buffs = {}
    stateByPane.debuffs = nil
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.separateOwn = 0
    BD.config.debuffs.separateOwn = 0
end

SetLegacyBackend()
do
    local buffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("buffs")
    local debuffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")

    assertTrue(buffsPolicy.available, "legacy Buffs available")
    assertTrue(debuffsPolicy.available, "legacy Debuffs available")
    assertFalse(buffsPolicy.custom, "legacy Buffs not custom")
    assertEqual(debuffsPolicy.label, "Debuffs", "legacy Debuffs label")
    assertNil(buffsPolicy.separateOwnItems[1].disabled,
        "legacy Disabled choice enabled")
    assertFalse(buffsPolicy.separateOwnItems[2].disabled,
        "legacy Before choice enabled")
    assertFalse(buffsPolicy.separateOwnItems[3].disabled,
        "legacy After choice enabled")
    assertFalse(buffsPolicy.constructionOwnedStyle,
        "legacy styling remains live")
    assertNil(BD.GetBuffsDebuffsOptionsStatus("buffs"),
        "legacy backend has no custom status")
end

SetCustomBuffsBackend()
do
    local buffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("buffs")
    local debuffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")

    assertTrue(buffsPolicy.available, "custom Buffs available")
    assertTrue(buffsPolicy.custom, "custom Buffs policy")
    assertFalse(debuffsPolicy.available,
        "custom backend leaves Debuffs unavailable")
    assertEqual(debuffsPolicy.label, "Debuffs (Blizzard controlled)",
        "custom Debuffs ownership label")
    assertNil(buffsPolicy.separateOwnItems[1].disabled,
        "custom Disabled choice remains selectable")
    assertTrue(buffsPolicy.separateOwnItems[2].disabled,
        "custom Before choice disabled")
    assertTrue(buffsPolicy.separateOwnItems[3].disabled,
        "custom After choice disabled")
    assertTrue(buffsPolicy.constructionOwnedStyle,
        "custom button styling is construction-owned")
    assertTrue(buffsPolicy.retiredDurationControls,
        "retired duration controls are declared")
end

do
    BD.config.buffs.separateOwn = 1
    stateByPane.buffs = {
        diagnostic = "NATIVE_SUPPRESSION_FAILED",
        reloadRequired = true,
        pending = true,
    }
    local status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "UNSUPPORTED_SEPARATE_OWN",
        "saved Before value gets recovery priority")
    assertEqual(status.action, "RECOVER_SEPARATE_OWN",
        "saved Before value exposes narrow recovery")

    BD.config.buffs.separateOwn = -1
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "UNSUPPORTED_SEPARATE_OWN",
        "saved After value gets recovery")

    BD.config.buffs.separateOwn = 0
    stateByPane.buffs = {
        diagnostic = "UNSUPPORTED_SEPARATE_OWN",
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "UNSUPPORTED_SEPARATE_OWN",
        "compiler diagnostic gets recovery")
end

do
    stateByPane.buffs = {
        diagnostic = "NATIVE_SUPPRESSION_FAILED",
        reloadRequired = true,
        pending = true,
    }
    local status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "NATIVE_FALLBACK",
        "native failure outranks reload and pending")
    assertNil(status.action, "native failure has no unsafe action")

    stateByPane.buffs = {
        diagnostic = "CONSTRUCTION_CHANGE_REQUIRES_RELOAD",
        reloadRequired = true,
        pending = true,
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "RELOAD_REQUIRED",
        "reload outranks pending")
    assertEqual(status.action, "RELOAD_UI", "reload action")

    stateByPane.buffs = {
        pending = true,
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "PENDING_SAFE_UPDATE", "pending status")
    assertNil(status.action, "pending status has no action")

    stateByPane.buffs = {}
    dispatchPendingByPane.buffs = true
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "PENDING_SAFE_UPDATE",
        "outer combat dispatcher pending status")

    dispatchPendingByPane.buffs = nil
    stateByPane.buffs = {}
    assertNil(BD.GetBuffsDebuffsOptionsStatus("buffs"),
        "ready custom backend has no status")
    assertNil(BD.GetBuffsDebuffsOptionsStatus("debuffs"),
        "Blizzard-owned Debuffs have no custom status")
end

local function NewOptionsUIHarness(customBackend, afVersion)
    local records = {
        callbacks = {},
        colorPickersByLabel = {},
        dropdownsByLabel = {},
        events = {},
        fontStringsByText = {},
        slidersByLabel = {},
        switches = {},
        titledPanesByTitle = {},
    }

    local function NewLeaf()
        local leaf = {}
        function leaf:SetColorTexture() end
        function leaf:SetTextColor() end
        return leaf
    end

    local function NewWidget(kind, text)
        local widget = {
            enabled = true,
            kind = kind,
            shown = true,
            textValue = text,
            checkedTexture = NewLeaf(),
            highlightTexture = NewLeaf(),
            line = NewLeaf(),
            text = NewLeaf(),
        }

        function widget:Hide()
            self.shown = false
        end
        function widget:Show()
            self.shown = true
        end
        function widget:SetShown(shown)
            self.shown = shown == true
        end
        function widget:IsShown()
            return self.shown == true
        end
        function widget:IsVisible()
            return self.shown == true
        end
        function widget:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        function widget:IsEnabled()
            return self.enabled == true
        end
        function widget:SetText(value)
            self.textValue = value
        end
        function widget:GetText()
            return self.textValue
        end
        function widget:SetChecked(value)
            self.checked = value == true
        end
        function widget:SetValue(value)
            self.value = value
        end
        function widget:SetColor(...)
            self.color = {...}
        end
        function widget:SetItems(items)
            self.items = items
        end
        function widget:SetSelectedValue(value)
            self.selected = value
        end
        function widget:GetSelectedValue()
            return rawget(self, "selected")
        end
        function widget:SetLabel(value)
            self.label = value
            if self.kind == "dropdown" then
                records.dropdownsByLabel[value] = self
            end
        end
        function widget:SetTooltip(value)
            self.tooltip = value
        end
        function widget:SetWordWrap(value)
            self.wordWrap = value == true
        end
        function widget:SetOnSelect(callback)
            self.onSelect = callback
        end
        function widget:SetOnCheck(callback)
            self.onCheck = callback
        end
        function widget:SetOnClick(callback)
            self.onClick = callback
        end
        function widget:SetOnValueChanged(callback)
            self.onValueChanged = callback
        end
        function widget:SetAfterValueChanged(callback)
            self.afterValueChanged = callback
        end
        function widget:SetOnChange(callback)
            self.onChange = callback
        end
        function widget:SetOnConfirm(callback)
            self.onConfirm = callback
        end

        setmetatable(widget, {
            __index = function(target, key)
                local noop = function() end
                rawset(target, key, noop)
                return noop
            end,
        })
        return widget
    end

    local function NewSwitch()
        local switch = NewWidget("switch")
        switch.buttons = {}
        records.switches[#records.switches + 1] = switch

        function switch:SetLabels(labels)
            self.labels = labels
            self.buttons = {}
            for index, label in ipairs(labels) do
                local button = NewWidget("switchButton", label.text)
                button.value = label.value
                button.enabled = not label.disabled
                self.buttons[index] = button
            end
        end

        function switch:SetSelectedValue(value, force)
            for index, button in ipairs(self.buttons) do
                if button.value == value and button.enabled then
                    if self.selected == value and not force then return end
                    self.selected = value
                    for otherIndex, other in ipairs(self.buttons) do
                        other.isSelected = otherIndex == index
                    end
                    local label = self.labels[index]
                    local callback = label.onClick
                        or label.callback
                        or self.onSelect
                    if callback then callback(value, label) end
                    return
                end
            end
        end

        function switch:GetSelectedButton()
            for _, button in ipairs(self.buttons) do
                if button.isSelected then return button end
            end
        end
        return switch
    end

    local function NewPaneConfig()
        return {
            enabled = true,
            orientation = "right_to_left_then_down",
            sortMethod = "TIME",
            sortDirection = "-",
            separateOwn = 0,
            width = 26,
            height = 26,
            spacingX = 4,
            spacingY = 6,
            maxWraps = 1,
            wrapAfter = 25,
            stack = {
                enabled = true,
                font = {"Expressway", 11, "outline", false},
                position = {"TOPRIGHT", "TOPRIGHT", 0, 3},
                color = {1, 1, 1, 1},
            },
            duration = {
                enabled = true,
                font = {"Expressway", 10, "outline", false},
                position = {"BOTTOM", "BOTTOM", 1, -3},
                color = {
                    normal = {1, 1, 1, 1},
                },
            },
        }
    end

    local uiEnvironment = setmetatable({}, {__index = _G})
    uiEnvironment._G = uiEnvironment
    uiEnvironment.ReloadUI = function()
        records.reloadCalls = (records.reloadCalls or 0) + 1
    end

    local uiAF = {
        versionNum = afVersion,
    }
    uiEnvironment.AbstractFramework = uiAF

    function uiAF.RegisterCallback(event, callback)
        records.callbacks[event] = callback
    end
    function uiAF.CreateFrame()
        return NewWidget("frame")
    end
    function uiAF.CreateSwitch()
        return NewSwitch()
    end
    function uiAF.CreateCheckButton()
        return NewWidget("checkButton")
    end
    function uiAF.CreateIconButton()
        return NewWidget("iconButton")
    end
    function uiAF.CreateDropdown()
        return NewWidget("dropdown")
    end
    function uiAF.CreateSlider(_, label)
        local slider = NewWidget("slider", label)
        records.slidersByLabel[label] = slider
        return slider
    end
    function uiAF.CreateTitledPane(_, title, _, height)
        local pane = NewWidget("titledPane", title)
        pane.height = height
        records.titledPanesByTitle[title] = pane
        return pane
    end
    function uiAF.CreateFontString(_, text)
        local fontString = NewWidget("fontString", text)
        if text then
            records.fontStringsByText[text] = fontString
        else
            records.statusText = fontString
        end
        return fontString
    end
    function uiAF.CreateButton(_, text, _, width, height)
        local button = NewWidget("button", text)
        button.width = width
        button.height = height
        records.statusButton = button
        return button
    end
    function uiAF.CreateColorPicker(_, label)
        local picker = NewWidget("colorPicker", label)
        records.colorPickersByLabel[label] = picker
        return picker
    end
    function uiAF.SetPoint(widget, ...)
        local points = rawget(widget, "points") or {}
        rawset(widget, "points", points)
        points[#points + 1] = {...}
    end
    function uiAF.SetWidth(widget, width)
        widget.width = width
    end
    function uiAF.SetEnabled(enabled, ...)
        for index = 1, select("#", ...) do
            select(index, ...):SetEnabled(enabled)
        end
    end
    function uiAF.Fire(event, module, which)
        records.events[#records.events + 1] = {
            event = event,
            module = module,
            which = which,
        }
    end
    function uiAF.GetColorRGB()
        return 1, 1, 1
    end
    function uiAF.GetIcon()
        return "icon"
    end
    function uiAF.WrapTextInColor(value)
        return value
    end
    function uiAF.GetDropdownItems_Arrangement_Complex()
        return {}
    end
    function uiAF.GetDropdownItems_AnchorPoint()
        return {}
    end
    function uiAF.LSM_GetFontDropdownItems()
        return {}
    end
    function uiAF.LSM_GetFontOutlineDropdownItems()
        return {}
    end
    function uiAF.SetFrameLevel() end
    function uiAF.ApplyCombatProtectionToFrame() end
    function uiAF.ClearPoints() end

    uiEnvironment.BFIOptionsFrame_ContentPane = NewWidget("content")

    local uiBD = {
        SECURE_AURA_HEADER_BACKEND = "secureAuraHeader",
        CUSTOM_AURA_CONTAINER_BACKEND = "customAuraContainer",
        config = {
            buffs = NewPaneConfig(),
            debuffs = NewPaneConfig(),
        },
    }
    records.BD = uiBD
    records.controllerState = {}

    function uiBD.GetAuraBackend(which)
        if customBackend then
            return which == "buffs"
                and uiBD.CUSTOM_AURA_CONTAINER_BACKEND
                or nil
        end
        if which == "buffs" or which == "debuffs" then
            return uiBD.SECURE_AURA_HEADER_BACKEND
        end
    end
    function uiBD.HasAuraBackend(which)
        return uiBD.GetAuraBackend(which) ~= nil
    end
    function uiBD.GetCustomAuraContainerState()
        return records.controllerState
    end
    function uiBD.IsBuffsDebuffsUpdatePending()
        return records.dispatchPending == true
    end
    function uiBD.ResetToDefaults() end

    local uiL = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local uiBFI = {
        L = uiL,
        modules = {
            BuffsDebuffs = uiBD,
        },
    }

    local uiChunk = assert(loadfile("Options/BuffsDebuffs.lua"))
    setfenv(uiChunk, uiEnvironment)
    uiChunk("BFInfinite", uiBFI)
    records.callbacks.BFI_ShowOptionsPanel(nil, "buffsDebuffs")

    records.topSwitch = records.switches[1]
    records.textSwitch = records.switches[2]
    records.separateOwn =
        records.dropdownsByLabel["Separate Own"]
    records.durationHint = records.fontStringsByText[
        "Durations abbreviate automatically to seconds, minutes, hours, and days."
    ]
    return records
end

do
    local custom = NewOptionsUIHarness(true, 25)
    local config = custom.BD.config.buffs

    assertEqual(#custom.events, 0,
        "custom programmatic option load fires no update")
    assertEqual(#custom.topSwitch.labels, 2, "custom has two tabs")
    assertEqual(custom.topSwitch.labels[2].text,
        "Debuffs (Blizzard controlled)", "custom Debuffs label")
    assertFalse(custom.topSwitch.buttons[2].enabled,
        "custom Debuffs tab disabled")
    assertTrue(custom.separateOwn.items[2].disabled,
        "custom Before item disabled")
    assertTrue(custom.separateOwn.items[3].disabled,
        "custom After item disabled")
    assertEqual(custom.titledPanesByTitle.Icons.height, 260,
        "status row reserves pane height")
    assertEqual(custom.statusButton.width, 165,
        "status action has bounded width")
    assertEqual(custom.statusText.width, 350,
        "status action text does not run under button")

    local width = custom.slidersByLabel.Width
    width.onValueChanged(40)
    assertEqual(config.width, 26,
        "custom width drag does not mutate configuration")
    assertEqual(#custom.events, 0,
        "custom width drag fires no update")
    width.afterValueChanged(40)
    assertEqual(config.width, 40,
        "custom width commits after interaction")
    assertEqual(#custom.events, 1,
        "custom width commit fires one update")

    custom.events = {}
    local color = custom.colorPickersByLabel.Normal
    color.onChange(0.2, 0.3, 0.4)
    assertEqual(config.stack.color[1], 1,
        "custom color preview does not mutate configuration")
    assertEqual(#custom.events, 0,
        "custom color preview fires no update")
    color.onConfirm(0.2, 0.3, 0.4)
    assertEqual(config.stack.color[1], 0.2,
        "custom color commits on confirmation")
    assertEqual(#custom.events, 1,
        "custom color confirmation fires one update")

    custom.events = {}
    config.separateOwn = 1
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(custom.separateOwn.selected, 1,
        "saved disabled Separate Own value remains visible")
    assertTrue(custom.statusButton.shown,
        "saved Separate Own value shows recovery")
    custom.statusButton.onClick()
    assertEqual(config.separateOwn, 0,
        "recovery changes only Separate Own")
    assertEqual(custom.separateOwn.selected, 0,
        "recovery refreshes dropdown selection")
    assertFalse(custom.statusButton.shown,
        "recovery refresh clears stale status")
    assertEqual(#custom.events, 1,
        "recovery fires one module update")

    custom.textSwitch:SetSelectedValue("duration")
    assertTrue(custom.durationHint.shown,
        "AF r25 shows abbreviation hint")
    assertEqual(custom.durationHint.width, 160,
        "duration hint is bounded to its column")
    assertTrue(custom.durationHint.wordWrap,
        "duration hint wraps inside the pane")
end

do
    local legacy = NewOptionsUIHarness(false, 24)
    local config = legacy.BD.config.buffs

    assertEqual(#legacy.events, 0,
        "legacy programmatic option load fires no update")
    assertTrue(legacy.topSwitch.buttons[2].enabled,
        "legacy Debuffs tab enabled")
    assertFalse(legacy.separateOwn.items[2].disabled,
        "legacy Before item enabled")
    assertFalse(legacy.separateOwn.items[3].disabled,
        "legacy After item enabled")

    local width = legacy.slidersByLabel.Width
    width.onValueChanged(35)
    assertEqual(config.width, 35, "legacy width remains live")
    assertEqual(#legacy.events, 1,
        "legacy width change fires one update")
    width.afterValueChanged(45)
    assertEqual(config.width, 35,
        "legacy after-change path does not double-commit")
    assertEqual(#legacy.events, 1,
        "legacy after-change path fires no second update")

    legacy.events = {}
    local color = legacy.colorPickersByLabel.Normal
    color.onChange(0.4, 0.5, 0.6)
    assertEqual(config.stack.color[1], 0.4,
        "legacy color preview remains live")
    assertEqual(#legacy.events, 1,
        "legacy color change fires one update")
    color.onConfirm(0.7, 0.8, 0.9)
    assertEqual(config.stack.color[1], 0.4,
        "legacy confirm path does not double-commit")
    assertEqual(#legacy.events, 1,
        "legacy confirm path fires no second update")

    legacy.textSwitch:SetSelectedValue("duration")
    assertFalse(legacy.durationHint.shown,
        "AF r24 does not promise abbreviation support")
end

do
    local file = assert(io.open("Options/BuffsDebuffs.lua", "r"))
    local source = file:read("*a")
    file:close()

    assertNil(source:find("CreatePrivatePane", 1, true),
        "Private Auras pane construction retired")
    assertNil(source:find("Show Seconds Unit", 1, true),
        "seconds-unit control retired")
    assertNil(source:find("color.percent", 1, true),
        "percent threshold controls retired")
    assertNil(source:find("color.seconds", 1, true),
        "seconds threshold controls retired")
    assertTrue(source:find("SetAfterValueChanged", 1, true) ~= nil,
        "custom construction sliders commit after interaction")
    assertTrue(source:find("SetOnConfirm", 1, true) ~= nil,
        "custom construction colors commit on confirmation")
end

print("buffs/debuffs options policy tests passed")
