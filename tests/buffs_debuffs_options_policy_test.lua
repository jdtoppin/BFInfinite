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
    BLIZZARD_DEBUFF_STYLE_BACKEND = "blizzardDebuffStyle",
    config = {
        buffs = {
            enabled = true,
            separateOwn = 0,
        },
        debuffs = {
            enabled = true,
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
    funcs = {
        isValueNonSecret = function(value)
            return type(value) == "boolean"
        end,
    },
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
    backendByPane.debuffs = BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    stateByPane.buffs = {}
    stateByPane.debuffs = nil
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.separateOwn = 0
    BD.config.debuffs.separateOwn = 0
end

local function SetCustomBothBackend()
    backendByPane.buffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    backendByPane.debuffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
    }
    stateByPane.debuffs = {
        active = true,
    }
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
    assertTrue(debuffsPolicy.available,
        "ordinary Debuffs styling is available")
    assertTrue(debuffsPolicy.blizzardDebuffStyle,
        "Debuffs use the Blizzard styling adapter")
    assertEqual(debuffsPolicy.label, "Debuffs (appearance only)",
        "Debuffs styling label")
    assertFalse(debuffsPolicy.layoutControls,
        "Blizzard retains Debuffs layout")
    assertTrue(debuffsPolicy.iconSizeControls,
        "ordinary Debuff icon sizing remains available")
    assertEqual(debuffsPolicy.maximumIconSize, 30,
        "ordinary icon size is capped to the native cell")
    assertFalse(debuffsPolicy.durationAppearanceControls,
        "Blizzard retains Debuff duration presentation")
    assertNil(buffsPolicy.separateOwnItems[1].disabled,
        "custom Disabled choice remains selectable")
    assertTrue(buffsPolicy.separateOwnItems[2].disabled,
        "custom Before choice disabled")
    assertTrue(buffsPolicy.separateOwnItems[3].disabled,
        "custom After choice disabled")
    assertTrue(buffsPolicy.constructionOwnedStyle,
        "custom button styling is construction-owned")
    assertTrue(buffsPolicy.positionOwnedByBFI,
        "BFI owns the shared Buff and Debuff location")
    assertFalse(buffsPolicy.arrangementControls,
        "follower arrangement is fixed")
    assertEqual(buffsPolicy.fixedArrangement,
        "right_to_left_then_up", "follower arrangement value")
    assertTrue(buffsPolicy.layoutControls,
        "remaining custom layout controls stay available")
    assertTrue(buffsPolicy.retiredDurationControls,
        "retired duration controls are declared")
end

SetCustomBothBackend()
do
    local policy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    assertTrue(policy.available, "custom Debuffs available")
    assertTrue(policy.custom, "custom Debuffs policy")
    assertFalse(policy.blizzardDebuffStyle,
        "custom Debuffs do not use legacy styling")
    assertEqual(policy.label, "Debuffs", "custom Debuffs label")
    assertTrue(policy.constructionOwnedStyle,
        "custom Debuff button styling is construction-owned")
    assertTrue(policy.positionOwnedByBFI,
        "custom Debuffs use the shared root seam")
    assertEqual(policy.fixedArrangement, "right_to_left_then_down",
        "custom Debuffs fixed arrangement")
    assertFalse(policy.arrangementControls,
        "custom Debuff arrangement follows the shared seam")
    assertTrue(policy.layoutControls,
        "custom Debuff spacing and wrapping stay available")
    assertEqual(policy.maximumIconSize, 100,
        "custom Debuff icons are not capped to Blizzard cells")
    assertTrue(policy.durationAppearanceControls,
        "custom Debuff duration appearance is available")
    assertTrue(policy.separateOwnItems[2].disabled,
        "custom Debuffs disable Separate Own")

    local status = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(status.code, "BFI_SHARED_AURA_MOVER",
        "active Buff follower shares the BFI mover")
    stateByPane.buffs.nativeFollowerActive = false
    status = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(status.code, "BLIZZARD_DEBUFF_POSITION",
        "custom Debuffs follow Blizzard position without Buff follower")
end

SetCustomBuffsBackend()

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
    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "BFI_SHARED_AURA_MOVER",
        "ready custom backend explains its shared BFI mover")
    stateByPane.buffs.nativeFollowerActive = false
    local debuffsStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffsStatus.code, "BLIZZARD_DEBUFF_STYLE",
        "inactive custom Buffs do not claim linked movement")
    stateByPane.buffs.nativeFollowerActive = true
    debuffsStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffsStatus.code, "BFI_SHARED_AURA_MOVER",
        "active native follower exposes the shared BFI mover")
    dispatchPendingByPane.debuffs = true
    debuffsStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffsStatus.code, "PENDING_SAFE_UPDATE",
        "Debuffs safe-update deferral is visible")
    dispatchPendingByPane.debuffs = nil
end

local function NewOptionsUIHarness(
    customBackend,
    afVersion,
    customDebuffsBackend
)
    local records = {
        callbacks = {},
        checkButtonsByLabel = {},
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
        function widget:SetMinMaxValues(minimum, maximum)
            self.minimum = minimum
            self.maximum = maximum
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
    uiEnvironment.InCombatLockdown = function()
        return false
    end
    uiEnvironment.ShowUIPanel = function(frame)
        records.shownUIPanel = frame
    end
    uiEnvironment.ReloadUI = function()
        records.reloadCalls = (records.reloadCalls or 0) + 1
    end
    uiEnvironment.EditModeManagerFrame = {
        CanEnterEditMode = function()
            return true
        end,
    }
    records.editModeManagerFrame = uiEnvironment.EditModeManagerFrame

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
    function uiAF.CreateCheckButton(_, label)
        local checkButton = NewWidget("checkButton", label)
        if label then
            records.checkButtonsByLabel[label] = checkButton
        end
        return checkButton
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
    function uiAF.ApplyCombatProtectionToWidget() end
    function uiAF.ClearPoints() end
    function uiAF.ShowMovers()
        records.showMoversCalls = (records.showMoversCalls or 0) + 1
    end

    uiEnvironment.BFIOptionsFrame_ContentPane = NewWidget("content")
    uiEnvironment.BFIOptionsFrame = NewWidget("optionsFrame")

    local uiBD = {
        SECURE_AURA_HEADER_BACKEND = "secureAuraHeader",
        CUSTOM_AURA_CONTAINER_BACKEND = "customAuraContainer",
        BLIZZARD_DEBUFF_STYLE_BACKEND = "blizzardDebuffStyle",
        config = {
            buffs = NewPaneConfig(),
            debuffs = NewPaneConfig(),
        },
    }
    records.BD = uiBD
    records.controllerState = customBackend and {
        active = true,
        nativeFollowerActive = true,
    } or {}

    function uiBD.GetAuraBackend(which)
        if customBackend then
            if which == "buffs" then
                return uiBD.CUSTOM_AURA_CONTAINER_BACKEND
            elseif which == "debuffs" then
                return customDebuffsBackend
                    and uiBD.CUSTOM_AURA_CONTAINER_BACKEND
                    or uiBD.BLIZZARD_DEBUFF_STYLE_BACKEND
            end
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
        funcs = {
            isValueNonSecret = function(value)
                return type(value) == "boolean"
            end,
            PrepareEditModePositions = function()
                records.prepareEditModeCalls =
                    (records.prepareEditModeCalls or 0) + 1
            end,
        },
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
    local custom = NewOptionsUIHarness(true, 33)
    local config = custom.BD.config.buffs

    assertEqual(#custom.events, 0,
        "custom programmatic option load fires no update")
    assertEqual(#custom.topSwitch.labels, 2, "custom has two tabs")
    assertEqual(custom.topSwitch.labels[2].text,
        "Debuffs (appearance only)", "custom Debuffs label")
    assertTrue(custom.topSwitch.buttons[2].enabled,
        "ordinary Debuffs styling tab enabled")
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
    assertTrue(custom.statusText.wordWrap,
        "status explanations wrap inside their row")
    assertFalse(custom.dropdownsByLabel.Arrangement.enabled,
        "custom Buff arrangement is fixed for the shared mover")
    assertEqual(custom.dropdownsByLabel.Arrangement.selected,
        "right_to_left_then_up", "fixed shared arrangement is visible")
    assertTrue(custom.dropdownsByLabel["Sort Method"].enabled,
        "custom Buff sorting remains editable")
    assertEqual(custom.statusText.textValue,
        "Both rows move together with the BFI Buff Frame mover. Movement is unavailable in combat.",
        "custom shared-mover guidance")
    assertEqual(custom.statusButton.textValue,
        "Open BFI Edit Mode", "custom Buff mover action")
    custom.statusButton.onClick()
    assertEqual(custom.prepareEditModeCalls, 1,
        "BFI positions are prepared before showing movers")
    assertEqual(custom.showMoversCalls, 1,
        "BFI Edit Mode action shows BFI movers")
    assertFalse(custom.shownUIPanel == custom.editModeManagerFrame,
        "shared mover action does not open Blizzard Edit Mode")

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
    assertTrue(custom.statusButton.shown,
        "recovery refresh restores shared-mover guidance")
    assertEqual(custom.statusButton.textValue, "Open BFI Edit Mode",
        "recovery refresh restores the BFI mover action")
    assertEqual(#custom.events, 1,
        "recovery fires one module update")

    custom.textSwitch:SetSelectedValue("duration")
    assertTrue(custom.durationHint.shown,
        "AF r33 shows abbreviation hint")
    assertEqual(custom.durationHint.width, 160,
        "duration hint is bounded to its column")
    assertTrue(custom.durationHint.wordWrap,
        "duration hint wraps inside the pane")

    custom.controllerState.active = true
    custom.controllerState.nativeFollowerActive = true
    custom.topSwitch:SetSelectedValue("debuffs")
    local debuffsConfig = custom.BD.config.debuffs
    assertFalse(custom.dropdownsByLabel.Arrangement.enabled,
        "Debuffs arrangement remains Blizzard-owned")
    assertFalse(custom.dropdownsByLabel["Sort Method"].enabled,
        "Debuffs sorting remains Blizzard-owned")
    assertFalse(custom.separateOwn.enabled,
        "Debuffs Separate Own remains Blizzard-owned")
    assertTrue(custom.slidersByLabel.Width.enabled,
        "ordinary Debuff icon width is editable")
    assertTrue(custom.slidersByLabel.Height.enabled,
        "ordinary Debuff icon height is editable")
    assertEqual(custom.slidersByLabel.Width.maximum, 30,
        "Debuff icon width uses the native-cell ceiling")
    assertEqual(custom.slidersByLabel.Height.maximum, 30,
        "Debuff icon height uses the native-cell ceiling")
    assertEqual(custom.statusText.textValue,
        "Both rows move together with the BFI Buff Frame mover. Movement is unavailable in combat.",
        "Debuffs shared-mover explanation")
    assertEqual(custom.statusButton.textValue,
        "Open BFI Edit Mode", "Debuffs shared-mover action")
    assertTrue(custom.statusText.shown,
        "Debuffs ownership explanation is visible")
    assertEqual(custom.durationHint.textValue,
        "Blizzard supplies and abbreviates Debuff durations. BFInfinite can only show or hide this text.",
        "native duration explanation")
    assertFalse(custom.dropdownsByLabel.Font.enabled,
        "native duration font remains Blizzard-owned")
    assertTrue(custom.checkButtonsByLabel.Enabled.enabled,
        "native duration visibility remains editable")

    custom.textSwitch:SetSelectedValue("stack")
    assertTrue(custom.dropdownsByLabel.Font.enabled,
        "ordinary stack font remains editable")
    assertTrue(custom.colorPickersByLabel.Normal.enabled,
        "ordinary stack colour remains editable")

    custom.events = {}
    custom.slidersByLabel.Width.onValueChanged(28)
    assertEqual(debuffsConfig.width, 28,
        "Debuffs icon width updates live")
    assertEqual(#custom.events, 1,
        "Debuffs icon width queues one safe update")
end

do
    local custom = NewOptionsUIHarness(true, 39, true)
    custom.topSwitch:SetSelectedValue("debuffs")

    assertEqual(custom.topSwitch.labels[2].text, "Debuffs",
        "native Debuffs use the full settings label")
    assertTrue(custom.dropdownsByLabel["Sort Method"].enabled,
        "native Debuff sorting is editable")
    assertEqual(custom.dropdownsByLabel.Arrangement.selected,
        "right_to_left_then_down", "native Debuff arrangement is fixed")
    assertEqual(custom.slidersByLabel.Width.maximum, 100,
        "native Debuff size is not limited by Blizzard's legacy cell")
    assertEqual(custom.slidersByLabel["Icons Per Line"].tooltip,
        "Ordinary and private Debuffs share this native row and icon limit.",
        "native Debuff cap explains its combined source")
    assertEqual(custom.slidersByLabel["Aura Lines"].tooltip,
        "Ordinary and private Debuffs share this native row and icon limit.",
        "native Debuff line count explains its combined source")
    assertEqual(custom.statusText.textValue,
        "Both rows share the BFI mover. Ordinary and private Debuffs share one native icon limit. Movement is unavailable in combat.",
        "native Debuff status explains movement and the shared cap")
end

do
    local legacy = NewOptionsUIHarness(false, 32)
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
        "AF r32 does not promise abbreviation support")
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
