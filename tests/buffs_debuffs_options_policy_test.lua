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
local harmfulDescriptorCapability = false

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
    BLIZZARD_DEBUFF_STYLE_BACKEND = "blizzardDebuffStyle",
    SECURE_AURA_HEADER_BACKEND = "secureAuraHeader",
    CUSTOM_AURA_CONTAINER_BACKEND = "customAuraContainer",
    config = {
        buffs = {
            enabled = false,
            separateOwn = 0,
        },
        debuffs = {
            enabled = false,
            separateOwn = 0,
            customHarmfulEnabled = false,
        },
    },
}

function BD.GetAuraBackend(which)
    return backendByPane[which]
end

function BD.GetCustomAuraContainerState(which)
    return stateByPane[which]
end

function BD.HasCustomHarmfulAuraDescriptorCapability()
    return true
end

function BD.IsBuffsDebuffsUpdatePending(which)
    return dispatchPendingByPane[which] == true
end

function BD.HasCustomHarmfulAuraDescriptorCapability()
    return harmfulDescriptorCapability
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
    harmfulDescriptorCapability = false
    backendByPane.buffs = BD.SECURE_AURA_HEADER_BACKEND
    backendByPane.debuffs = BD.SECURE_AURA_HEADER_BACKEND
    stateByPane.buffs = nil
    stateByPane.debuffs = nil
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.separateOwn = 0
    BD.config.buffs.enabled = false
    BD.config.debuffs.separateOwn = 0
    BD.config.debuffs.enabled = false
    BD.config.debuffs.customHarmfulEnabled = false
end

local function SetCustomBuffsBackend()
    harmfulDescriptorCapability = true
    backendByPane.buffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    backendByPane.debuffs = BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    stateByPane.buffs = {}
    stateByPane.debuffs = nil
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.separateOwn = 0
    BD.config.buffs.enabled = true
    BD.config.debuffs.separateOwn = 0
    BD.config.debuffs.enabled = false
    BD.config.debuffs.customHarmfulEnabled = false
end

local function SetCustomDebuffsBackend(backend)
    backendByPane.buffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    backendByPane.debuffs = backend
    stateByPane.buffs = {}
    stateByPane.debuffs = {active = backend
        == BD.CUSTOM_AURA_CONTAINER_BACKEND}
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.debuffs.enabled = true
    BD.config.debuffs.separateOwn = 0
    BD.config.debuffs.customHarmfulEnabled = true
end

local function SetCustomHarmfulBackend()
    harmfulDescriptorCapability = true
    backendByPane.buffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    backendByPane.debuffs = BD.CUSTOM_AURA_CONTAINER_BACKEND
    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
    }
    stateByPane.debuffs = {active = true}
    dispatchPendingByPane.buffs = nil
    dispatchPendingByPane.debuffs = nil
    BD.config.buffs.enabled = true
    BD.config.debuffs.enabled = true
    BD.config.debuffs.customHarmfulEnabled = true
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
        "ordinary Debuffs style is available")
    assertTrue(debuffsPolicy.blizzardDebuffStyle,
        "Debuffs use the static Blizzard style adapter")
    assertEqual(debuffsPolicy.label, "Debuffs (appearance only)",
        "Debuffs appearance-only label")
    assertFalse(debuffsPolicy.layoutControls,
        "Blizzard owns Debuffs layout")
    assertEqual(debuffsPolicy.maximumIconSize, 30,
        "Debuffs size is capped to the fixed native cell")
    assertFalse(debuffsPolicy.durationAppearanceControls,
        "Blizzard owns Debuffs duration appearance")
    assertTrue(debuffsPolicy.durationEnabledControl,
        "Debuffs duration visibility remains editable")
    assertTrue(debuffsPolicy.stackAppearanceControls,
        "ordinary Debuffs stack text remains editable")
    assertNil(buffsPolicy.separateOwnItems[1].disabled,
        "custom Disabled choice remains selectable")
    assertTrue(buffsPolicy.separateOwnItems[2].disabled,
        "custom Before choice disabled")
    assertTrue(buffsPolicy.separateOwnItems[3].disabled,
        "custom After choice disabled")
    assertTrue(buffsPolicy.constructionOwnedStyle,
        "custom button styling is construction-owned")
    assertTrue(buffsPolicy.durationColorModes,
        "one duration color mode control is declared")
    assertFalse(buffsPolicy.arrangementControls,
        "custom Buffs arrangement control is display-only")
    assertEqual(buffsPolicy.fixedArrangement,
        "right_to_left_then_up", "custom Buffs fixed arrangement")
    assertFalse(debuffsPolicy.arrangementControls,
        "Blizzard-owned Debuffs arrangement is disabled")
    assertTrue(buffsPolicy.sourceDisclosure:find("PublicAndPrivate", 1, true)
            ~= nil,
        "custom policy discloses the native combined source list")
end

SetCustomDebuffsBackend(BD.CUSTOM_AURA_CONTAINER_BACKEND)
do
    local policy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    assertTrue(policy.custom, "custom harmful policy")
    assertTrue(policy.harmfulOptInAvailable,
        "stable harmful opt-in remains available")
    assertTrue(policy.harmfulOptInRequested,
        "saved harmful opt-in is exposed")
    assertEqual(policy.label, "Debuffs (Public + Private)",
        "custom harmful label")
    assertTrue(policy.sourceDisclosure:find("displace", 1, true) ~= nil,
        "harmful policy discloses finite cap displacement")

    stateByPane.debuffs = {
        active = true,
        pending = true,
        operationPending = true,
        harmfulReassertPending = true,
        diagnostic = "NATIVE_HARMFUL_REASSERT_FAILED",
    }
    local status = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(status.code, "HARMFUL_ACTIVE_RECOVERY_FAILED",
        "active harmful reassert failure has a distinct degraded status")
    assertNil(status.action,
        "active harmful recovery exposes no unsafe action")
end

SetCustomDebuffsBackend(BD.BLIZZARD_DEBUFF_STYLE_BACKEND)
do
    local policy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    assertFalse(policy.custom, "transient harmful fallback is not custom")
    assertTrue(policy.harmfulOptInAvailable,
        "transient runtime failure does not remove opt-in control")
    assertTrue(policy.harmfulOptInRequested,
        "transient runtime failure preserves saved check")
    assertEqual(
        BD.GetBuffsDebuffsOptionsStatus("debuffs").code,
        "HARMFUL_NATIVE_FALLBACK",
        "opted-in runtime failure exposes explicit fallback"
    )
end

BD.config.debuffs.customHarmfulEnabled = false
SetCustomBuffsBackend()

SetCustomHarmfulBackend()
do
    local debuffsPolicy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    assertTrue(debuffsPolicy.available,
        "custom harmful options are available")
    assertTrue(debuffsPolicy.custom, "custom harmful policy")
    assertTrue(debuffsPolicy.harmfulOptInAvailable,
        "stable descriptor registration exposes opt-in")
    assertTrue(debuffsPolicy.harmfulOptInRequested,
        "saved harmful opt-in is reflected in policy")
    assertEqual(debuffsPolicy.label, "Debuffs (Public + Private)",
        "custom harmful tab names both source classes")
    assertEqual(debuffsPolicy.fixedArrangement,
        "right_to_left_then_down",
        "custom harmful row exposes its fixed downward flow")
    assertTrue(debuffsPolicy.layoutControls,
        "custom harmful layout controls are available")
    assertEqual(debuffsPolicy.maximumIconSize, 100,
        "custom harmful icon geometry is not Blizzard-cell clamped")
    assertTrue(debuffsPolicy.sourceDisclosure:find(
        "finite icon cap", 1, true
    ) ~= nil, "custom harmful policy discloses finite cap")
    assertTrue(debuffsPolicy.sourceDisclosure:find(
        "Deadly Debuffs remain Blizzard controlled", 1, true
    ) ~= nil, "custom harmful policy discloses deadly ownership")
    assertEqual(
        BD.GetBuffsDebuffsOptionsStatus("debuffs").code,
        "BFI_SHARED_AURA_MOVER",
        "healthy custom harmful row exposes shared mover status"
    )
end

do
    backendByPane.debuffs = BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    stateByPane.debuffs = {active = false}
    local policy = BD.GetBuffsDebuffsOptionsPolicy("debuffs")
    assertTrue(policy.harmfulOptInAvailable,
        "transient runtime fallback keeps opt-in available")
    assertTrue(policy.harmfulOptInRequested,
        "transient runtime fallback retains saved request")
    local status = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(status.code, "HARMFUL_NATIVE_FALLBACK",
        "runtime fallback is reported distinctly")

    dispatchPendingByPane.debuffs = true
    status = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(status.code, "PENDING_SAFE_UPDATE",
        "dispatcher pending outranks harmful fallback")
    dispatchPendingByPane.debuffs = nil
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
        "ready custom backend exposes its shared BFI mover")
    local debuffStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffStatus.code, "BFI_SHARED_AURA_MOVER",
        "linked Debuffs expose the same shared BFI mover")
    dispatchPendingByPane.debuffs = true
    debuffStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffStatus.code, "PENDING_SAFE_UPDATE",
        "Debuffs combat queue outranks ownership status")
    dispatchPendingByPane.debuffs = nil

    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
        pending = true,
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "PENDING_SAFE_UPDATE",
        "pending safe update outranks ready mover guidance")

    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
        diagnostic = "NATIVE_FOLLOWER_REFRESH_FAILED",
        pending = true,
    }
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "NATIVE_FOLLOWER_REFRESH_FAILED",
        "follower retry pending retains its truthful distinct status")
    debuffStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffStatus.code, "NATIVE_FOLLOWER_REFRESH_FAILED",
        "linked Debuffs expose the active follower refresh failure")

    stateByPane.buffs.operationPending = true
    status = BD.GetBuffsDebuffsOptionsStatus("buffs")
    assertEqual(status.code, "PENDING_SAFE_UPDATE",
        "queued config operation outranks follower refresh guidance")
    debuffStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffStatus.code, "PENDING_SAFE_UPDATE",
        "linked Debuffs expose the queued config operation first")

    BD.config.buffs.enabled = false
    stateByPane.buffs = {
        active = true,
        nativeFollowerActive = true,
    }
    assertNil(BD.GetBuffsDebuffsOptionsStatus("buffs"),
        "disabled Buffs do not claim a shared mover")
    debuffStatus = BD.GetBuffsDebuffsOptionsStatus("debuffs")
    assertEqual(debuffStatus.code, "BLIZZARD_DEBUFF_STYLE",
        "disabled Buffs leave Debuffs ownership with Blizzard")
    BD.config.buffs.enabled = true
end

local function NewOptionsUIHarness(customBackend, afVersion, harmfulBackendActive)
    local records = {
        callbacks = {},
        checkButtonsByLabel = {},
        colorPickersByLabel = {},
        dropdownsByLabel = {},
        editBoxesByLabel = {},
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
            local color = {...}
            if #color == 1 and type(color[1]) == "table" then
                color = {
                    color[1][1],
                    color[1][2],
                    color[1][3],
                    color[1][4],
                }
            end
            self.color = color
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
        function widget:SetConfirmButton(callback)
            self.confirmValue = callback
        end
        function widget:SetOnEditFocusLost(callback)
            self.onEditFocusLost = callback
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
                    seconds = {
                        enabled = true,
                        value = 0.5,
                        rgb = {1, 0, 0, 1},
                    },
                    percent = {
                        enabled = false,
                        value = 0.955,
                        rgb = {1, 1, 0, 1},
                    },
                },
            },
        }
    end

    local uiEnvironment = setmetatable({}, {__index = _G})
    uiEnvironment._G = uiEnvironment
    uiEnvironment.ReloadUI = function()
        records.reloadCalls = (records.reloadCalls or 0) + 1
    end
    uiEnvironment.InCombatLockdown = function()
        return records.combat == true
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
    function uiAF.CreateCheckButton(_, label)
        local checkButton = NewWidget("checkButton", label)
        if label then records.checkButtonsByLabel[label] = checkButton end
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
    function uiAF.CreateEditBox(_, label, _, _, mode)
        local editBox = NewWidget("editBox", label)
        editBox.mode = mode
        records.editBoxesByLabel[label] = editBox
        return editBox
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
    function uiAF.ShowMovers()
        records.moverActionCalls = records.moverActionCalls or {}
        records.moverActionCalls[#records.moverActionCalls + 1] = "ShowMovers"
    end

    uiEnvironment.BFIOptionsFrame_ContentPane = NewWidget("content")
    uiEnvironment.BFIOptionsFrame = NewWidget("optionsFrame")
    records.optionsFrame = uiEnvironment.BFIOptionsFrame
    function uiEnvironment.BFIOptionsFrame:Hide()
        self.shown = false
        records.moverActionCalls = records.moverActionCalls or {}
        records.moverActionCalls[#records.moverActionCalls + 1] = "Hide"
    end

    local uiBD = {
        BLIZZARD_DEBUFF_STYLE_BACKEND = "blizzardDebuffStyle",
        SECURE_AURA_HEADER_BACKEND = "secureAuraHeader",
        CUSTOM_AURA_CONTAINER_BACKEND = "customAuraContainer",
        config = {
            buffs = NewPaneConfig(),
            debuffs = NewPaneConfig(),
        },
    }
    records.BD = uiBD
    records.harmfulDescriptorCapability = customBackend == true
    records.harmfulBackendActive = harmfulBackendActive == true
    records.controllerState = customBackend and {
        active = true,
        nativeFollowerActive = true,
    } or {}

    function uiBD.GetAuraBackend(which)
        records.backendCalls = (records.backendCalls or 0) + 1
        if customBackend then
            if which == "buffs" then
                return uiBD.CUSTOM_AURA_CONTAINER_BACKEND
            elseif which == "debuffs" then
                return records.harmfulBackendActive
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
    function uiBD.HasCustomHarmfulAuraDescriptorCapability()
        return records.harmfulDescriptorCapability
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
            PrepareEditModePositions = function()
                records.moverActionCalls = records.moverActionCalls or {}
                records.moverActionCalls[
                    #records.moverActionCalls + 1
                ] = "PrepareEditModePositions"
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
    records.durationMode = records.dropdownsByLabel[
        "Low-Time Text Color"
    ]
    records.secondsValue = records.editBoxesByLabel.Seconds
    records.percentValue = records.editBoxesByLabel.Percent
    records.lowTimeColor = records.colorPickersByLabel["Low-Time Color"]
    records.textEnabled = records.checkButtonsByLabel.Enabled
    records.harmfulOptIn = records.checkButtonsByLabel[
        "Use combined native Debuffs row"
    ]
    return records
end

do
    local custom = NewOptionsUIHarness(true, 42)
    local config = custom.BD.config.buffs

    assertEqual(#custom.events, 0,
        "custom programmatic option load fires no update")
    assertEqual(custom.backendCalls, 3,
        "initial panel load performs one backend probe per policy load")
    assertEqual(#custom.topSwitch.labels, 2, "custom has two tabs")
    assertEqual(custom.topSwitch.labels[1].text,
        "Buffs (Public + Private)",
        "custom Buffs tab visibly discloses combined source classes")
    assertEqual(custom.topSwitch.buttons[1].tooltip,
        "WoW 12.1's PublicAndPrivate source list combines public and private authorized Buffs in this native row; the sources cannot be separated.",
        "custom Buffs tab tooltip names the exact native source list")
    assertEqual(custom.topSwitch.labels[2].text,
        "Debuffs (appearance only)", "Debuffs appearance-only label")
    assertTrue(custom.topSwitch.buttons[2].enabled,
        "Debuffs appearance tab enabled")
    assertTrue(custom.separateOwn.items[2].disabled,
        "custom Before item disabled")
    assertFalse(custom.harmfulOptIn.shown,
        "harmful opt-in is hidden on the Buffs tab")
    assertEqual(custom.harmfulOptIn.tooltip,
        "This opt-in replaces Blizzard's ordinary and private Debuffs with one PublicAndPrivate native row. Its finite icon cap is shared; at the cap, either source can displace auras from the other. Deadly Debuffs remain Blizzard controlled.",
        "harmful opt-in tooltip discloses cap and ownership")
    assertTrue(custom.separateOwn.items[3].disabled,
        "custom After item disabled")
    assertEqual(custom.titledPanesByTitle.Icons.height, 260,
        "icons retain the known fitting pane height")
    assertEqual(custom.titledPanesByTitle.Texts.height, 235,
        "texts retain the known fitting pane height")
    assertTrue(
        custom.titledPanesByTitle.Icons.height
            + 5
            + custom.titledPanesByTitle.Texts.height
            <= 500,
        "stacked panes fit the available normal pane height"
    )
    assertEqual(custom.statusButton.width, 165,
        "status action has bounded width")
    assertEqual(custom.statusText.width, 350,
        "status action text does not run under button")
    assertFalse(custom.dropdownsByLabel.Arrangement.enabled,
        "custom Buffs arrangement is fixed and display-only")
    assertEqual(custom.dropdownsByLabel.Arrangement.selected,
        "right_to_left_then_up", "fixed custom arrangement is visible")
    assertEqual(config.orientation, "right_to_left_then_down",
        "fixed arrangement display preserves saved orientation")
    custom.events = {}
    custom.dropdownsByLabel.Arrangement.onSelect("left_to_right_then_down")
    assertEqual(config.orientation, "right_to_left_then_down",
        "fixed arrangement callback preserves dormant saved data")
    assertEqual(#custom.events, 0,
        "fixed arrangement callback emits no update")
    assertTrue(custom.dropdownsByLabel["Sort Method"].enabled,
        "custom Buff sorting remains editable")
    assertEqual(custom.statusText.textValue,
        "The BFI Buff Frame mover positions the combined Buffs row and Blizzard's DebuffFrame root together. Movement is unavailable in combat.",
        "custom Buffs expose shared-mover guidance")
    assertEqual(custom.statusButton.textValue, "Open BFI Edit Mode",
        "custom Buffs expose the BFI Edit Mode action")
    assertTrue(custom.statusButton.shown,
        "shared-mover guidance action is visible")

    custom.combat = true
    custom.statusButton.onClick()
    assertNil(custom.moverActionCalls,
        "combat-blocked mover action performs zero calls")
    assertTrue(custom.optionsFrame.shown,
        "combat-blocked mover action leaves options visible")
    custom.combat = false
    custom.statusButton.onClick()
    assertEqual(custom.moverActionCalls[1], "Hide",
        "mover action hides options first")
    assertEqual(custom.moverActionCalls[2], "PrepareEditModePositions",
        "mover action prepares saved positions second")
    assertEqual(custom.moverActionCalls[3], "ShowMovers",
        "mover action publishes movers last")
    assertFalse(custom.optionsFrame.shown,
        "successful mover action closes the options frame")

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
    assertEqual(config.stack.color[4], 1,
        "custom normal RGB confirmation preserves alpha")
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

    local backendCallsBeforeTextSelection = custom.backendCalls
    custom.textSwitch:SetSelectedValue("duration")
    assertEqual(custom.backendCalls, backendCallsBeforeTextSelection,
        "text selection reuses the loaded backend policy")
    assertEqual(custom.durationMode.tooltip,
        "Durations abbreviate automatically to seconds, minutes, hours, and days.",
        "duration abbreviation guidance moves to a non-flow tooltip")
    assertEqual(custom.durationMode.items[1].value, "seconds",
        "mode selector lists Seconds first")
    assertEqual(custom.durationMode.items[2].value, "percent",
        "mode selector lists Percent second")
    assertEqual(custom.durationMode.items[3].value, "off",
        "mode selector lists Off third")
    assertEqual(custom.durationMode.selected, "seconds",
        "saved seconds mode loads into the single selector")
    assertTrue(custom.secondsValue.shown,
        "seconds value control is shown in seconds mode")
    assertFalse(custom.percentValue.shown,
        "percent value control is hidden in seconds mode")
    assertEqual(custom.secondsValue.textValue, 0.5,
        "non-grid seconds value loads exactly without an update")
    assertEqual(custom.percentValue.textValue, 95.5,
        "arbitrary imported percent displays exactly as a percentage")
    assertEqual(custom.secondsValue.mode, "decimal",
        "fractional seconds input uses decimal mode")
    assertEqual(custom.percentValue.mode, "decimal",
        "fractional percent input uses decimal mode")

    local secondsValue = config.duration.color.seconds.value
    local secondsColor = config.duration.color.seconds.rgb
    local percentValue = config.duration.color.percent.value
    local percentColor = config.duration.color.percent.rgb
    custom.events = {}
    local backendCallsBeforeDurationCallback = custom.backendCalls
    custom.durationMode.onSelect("percent")
    assertEqual(custom.backendCalls, backendCallsBeforeDurationCallback,
        "duration callbacks do not re-run native capability preflight")
    assertFalse(config.duration.color.seconds.enabled,
        "percent mode disables seconds")
    assertTrue(config.duration.color.percent.enabled,
        "percent mode enables percent")
    assertEqual(config.duration.color.seconds.value, secondsValue,
        "mode change preserves inactive seconds payload")
    assertEqual(config.duration.color.seconds.rgb, secondsColor,
        "mode change preserves inactive seconds color identity")
    assertEqual(config.duration.color.percent.value, percentValue,
        "mode change preserves percent payload")
    assertEqual(config.duration.color.percent.rgb, percentColor,
        "mode change preserves percent color identity")
    assertEqual(#custom.events, 1,
        "mode change commits exactly one construction update")
    assertTrue(custom.percentValue.shown,
        "percent value control is shown in percent mode")
    assertFalse(custom.secondsValue.shown,
        "seconds value control hides in percent mode")
    assertEqual(custom.lowTimeColor.color[1], percentColor[1],
        "switching to Percent displays the saved percent color")
    assertEqual(custom.lowTimeColor.color[2], percentColor[2],
        "Percent display retains the saved percent RGB")

    custom.durationMode.onSelect("seconds")
    assertEqual(custom.lowTimeColor.color[1], secondsColor[1],
        "switching back to Seconds restores saved seconds color")
    assertEqual(custom.lowTimeColor.color[2], secondsColor[2],
        "Seconds display retains the saved seconds RGB")
    assertEqual(config.duration.color.seconds.value, secondsValue,
        "mode round-trip preserves seconds value")
    assertEqual(config.duration.color.percent.value, percentValue,
        "mode round-trip preserves percent value")
    assertEqual(config.duration.color.seconds.rgb, secondsColor,
        "mode round-trip preserves seconds color identity")
    assertEqual(config.duration.color.percent.rgb, percentColor,
        "mode round-trip preserves percent color identity")
    custom.durationMode.onSelect("percent")
    assertEqual(custom.lowTimeColor.color[1], percentColor[1],
        "returning to Percent restores its saved color")
    assertEqual(#custom.events, 3,
        "each mode selection commits exactly one update")

    custom.events = {}
    custom.percentValue.confirmValue(42.5)
    custom.percentValue.textValue = 42.5
    custom.percentValue.onEditFocusLost(custom.percentValue)
    assertEqual(config.duration.color.percent.value, 0.425,
        "custom percent value commits its exact confirmed value")
    assertEqual(#custom.events, 1,
        "custom percent confirmation commits once")
    custom.events = {}
    custom.percentValue.confirmValue(100)
    custom.percentValue.textValue = 100
    custom.percentValue.onEditFocusLost(custom.percentValue)
    assertEqual(config.duration.color.percent.value, 0.425,
        "invalid percent confirmation preserves saved value")
    assertEqual(custom.percentValue.textValue, 42.5,
        "invalid percent confirmation restores exact display")
    assertEqual(#custom.events, 0,
        "invalid percent confirmation emits no update")

    custom.events = {}
    custom.secondsValue.confirmValue(0)
    custom.secondsValue.textValue = 0
    custom.secondsValue.onEditFocusLost(custom.secondsValue)
    assertEqual(config.duration.color.seconds.value, 0.5,
        "invalid seconds confirmation preserves saved value")
    assertEqual(custom.secondsValue.textValue, 0.5,
        "invalid seconds confirmation restores exact display")
    assertEqual(#custom.events, 0,
        "invalid seconds confirmation emits no update")

    custom.events = {}
    custom.lowTimeColor.onChange(0.2, 0.4, 0.6)
    assertEqual(config.duration.color.percent.rgb[1], 1,
        "custom low-time color preview is configuration-neutral")
    assertEqual(#custom.events, 0,
        "custom low-time color preview emits no update")
    custom.lowTimeColor.onConfirm(0.2, 0.4, 0.6)
    assertEqual(config.duration.color.percent.rgb[1], 0.2,
        "custom low-time color commits on confirmation")
    assertEqual(#custom.events, 1,
        "custom low-time color confirmation commits once")
    assertEqual(config.duration.color.percent.rgb[4], percentColor[4],
        "low-time RGB confirmation preserves saved alpha")

    custom.events = {}
    custom.durationMode.onSelect("off")
    assertFalse(config.duration.color.seconds.enabled,
        "Off keeps seconds disabled")
    assertFalse(config.duration.color.percent.enabled,
        "Off disables percent")
    assertEqual(config.duration.color.seconds.value, secondsValue,
        "Off preserves seconds payload")
    assertEqual(config.duration.color.percent.value, 0.425,
        "Off preserves percent payload")
    assertFalse(custom.secondsValue.shown,
        "Off hides seconds value")
    assertFalse(custom.percentValue.shown,
        "Off hides percent value")
    assertFalse(custom.lowTimeColor.shown,
        "Off hides low-time color")
    assertEqual(#custom.events, 1,
        "Off mode commits exactly once")

    custom.topSwitch:SetSelectedValue("debuffs")
    local debuffsConfig = custom.BD.config.debuffs
    assertTrue(custom.harmfulOptIn.shown,
        "runtime-capable Debuffs tab shows harmful opt-in")
    assertTrue(custom.harmfulOptIn.enabled,
        "runtime fallback does not disable stable harmful opt-in")
    assertFalse(custom.harmfulOptIn.checked,
        "harmful opt-in defaults unchecked")
    assertEqual(custom.harmfulOptIn.points[1][1], "TOPRIGHT",
        "harmful opt-in anchors to the upper-right of Icons")
    assertEqual(custom.harmfulOptIn.points[1][2], -10,
        "harmful opt-in X inset")
    assertEqual(custom.harmfulOptIn.points[1][3], -42,
        "harmful opt-in Y inset avoids the left arrangement control")

    custom.events = {}
    custom.harmfulOptIn.onCheck(true)
    assertTrue(debuffsConfig.customHarmfulEnabled,
        "harmful checkbox commits explicit opt-in")
    assertEqual(#custom.events, 1,
        "harmful opt-in emits one Debuffs update")
    assertEqual(custom.events[1].which, "debuffs",
        "harmful opt-in targets Debuffs only")
    assertTrue(custom.harmfulOptIn.checked,
        "saved harmful opt-in remains checked under runtime fallback")
    assertEqual(custom.statusText.textValue,
        "The combined Debuffs row is opted in, but its native private-aura boundary is not currently available. Blizzard Debuffs remain active.",
        "runtime failure explains Blizzard fallback")
    assertTrue(custom.statusText.wordWrap,
        "harmful runtime fallback status wraps")
    assertFalse(custom.statusButton.shown,
        "harmful runtime fallback exposes no unsafe action")

    custom.events = {}
    custom.harmfulOptIn.onCheck(false)
    assertFalse(debuffsConfig.customHarmfulEnabled,
        "runtime fallback checkbox can opt back out")
    assertEqual(#custom.events, 1,
        "harmful opt-out emits one Debuffs update")
    assertFalse(custom.harmfulOptIn.checked,
        "harmful opt-out refreshes checked state")

    debuffsConfig.width = 45
    debuffsConfig.height = 37
    local savedSecondsEnabled =
        debuffsConfig.duration.color.seconds.enabled
    local savedPercentEnabled =
        debuffsConfig.duration.color.percent.enabled
    local savedSecondsValue = debuffsConfig.duration.color.seconds.value
    local savedPercentValue = debuffsConfig.duration.color.percent.value
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(debuffsConfig.width, 45,
        "imported Debuffs width remains saved")
    assertEqual(debuffsConfig.height, 37,
        "imported Debuffs height remains saved")
    assertEqual(custom.slidersByLabel.Width.value, 30,
        "imported Debuffs width is display-clamped")
    assertEqual(custom.slidersByLabel.Height.value, 30,
        "imported Debuffs height is display-clamped")
    assertEqual(custom.slidersByLabel.Width.minimum, 10,
        "Debuffs width minimum")
    assertEqual(custom.slidersByLabel.Width.maximum, 30,
        "Debuffs width maximum")
    assertFalse(custom.dropdownsByLabel.Arrangement.enabled,
        "Debuffs arrangement remains Blizzard-owned")
    assertFalse(custom.dropdownsByLabel["Sort Method"].enabled,
        "Debuffs sorting remains Blizzard-owned")
    assertFalse(custom.dropdownsByLabel["Sort Direction"].enabled,
        "Debuffs sort direction remains Blizzard-owned")
    assertFalse(custom.separateOwn.enabled,
        "Debuffs Separate Own remains Blizzard-owned")
    assertFalse(custom.slidersByLabel["X Spacing"].enabled,
        "Debuffs horizontal spacing remains Blizzard-owned")
    assertFalse(custom.slidersByLabel["Aura Lines"].enabled,
        "Debuffs line count remains Blizzard-owned")
    assertEqual(custom.statusText.textValue,
        "The BFI Buff Frame mover positions the combined Buffs row and Blizzard's DebuffFrame root together. Movement is unavailable in combat.",
        "Debuffs shared-mover status")
    assertTrue(custom.statusText.shown,
        "Debuffs ownership status visible")
    assertTrue(custom.statusText.wordWrap,
        "Debuffs ownership status wraps within the fitting status row")

    custom.textSwitch:SetSelectedValue("stack")
    assertTrue(custom.dropdownsByLabel.Font.enabled,
        "Debuffs stack font remains editable")
    assertTrue(custom.dropdownsByLabel.Outline.enabled,
        "Debuffs stack outline remains editable")
    assertTrue(custom.colorPickersByLabel.Normal.enabled,
        "Debuffs stack colour remains editable")

    custom.textSwitch:SetSelectedValue("duration")
    assertTrue(custom.textEnabled.enabled,
        "Debuffs duration Enabled remains editable")
    assertFalse(custom.dropdownsByLabel.Font.enabled,
        "Debuffs duration font remains Blizzard-owned")
    assertFalse(custom.dropdownsByLabel.Outline.enabled,
        "Debuffs duration outline remains Blizzard-owned")
    assertFalse(custom.colorPickersByLabel.Normal.enabled,
        "Debuffs duration normal colour remains Blizzard-owned")
    assertFalse(custom.durationMode.enabled,
        "Debuffs duration mode remains visible but disabled")
    assertFalse(custom.secondsValue.enabled,
        "Debuffs seconds value remains visible but disabled")
    assertFalse(custom.lowTimeColor.enabled,
        "Debuffs low-time colour remains visible but disabled")
    assertEqual(custom.durationMode.tooltip,
        "Blizzard supplies and abbreviates Debuff durations. BFInfinite can only show or hide this text.",
        "Debuffs duration ownership tooltip")

    custom.events = {}
    custom.durationMode.onSelect("percent")
    custom.secondsValue.confirmValue(9.5)
    custom.lowTimeColor.onConfirm(0.3, 0.4, 0.5)
    assertEqual(debuffsConfig.duration.color.seconds.enabled,
        savedSecondsEnabled,
        "disabled mode control preserves seconds flag")
    assertEqual(debuffsConfig.duration.color.percent.enabled,
        savedPercentEnabled,
        "disabled mode control preserves percent flag")
    assertEqual(debuffsConfig.duration.color.seconds.value,
        savedSecondsValue,
        "disabled seconds editor preserves payload")
    assertEqual(debuffsConfig.duration.color.percent.value,
        savedPercentValue,
        "disabled percent payload remains exact")
    assertEqual(#custom.events, 0,
        "disabled duration appearance callbacks are neutral")

    custom.dispatchPending = true
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(custom.statusText.textValue,
        "Debuffs styling is waiting for combat to end.",
        "selected Debuffs tab shows pending status")
    custom.dispatchPending = false
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(custom.statusText.textValue,
        "The BFI Buff Frame mover positions the combined Buffs row and Blizzard's DebuffFrame root together. Movement is unavailable in combat.",
        "Debuffs shared-mover status returns after pending clears")

    custom.controllerState.pending = true
    custom.controllerState.operationPending = false
    custom.controllerState.diagnostic = nil
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(custom.statusText.textValue,
        "Debuffs styling is waiting for combat to end.",
        "lifecycle-only pending state outranks mover information")

    custom.controllerState.diagnostic =
        "NATIVE_FOLLOWER_REFRESH_FAILED"
    custom.controllerState.pending = true
    custom.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(custom.statusText.textValue,
        "The shared DebuffFrame attachment could not be refreshed. The current safe layout remains in place while native frame access recovers.",
        "active refresh failure does not claim Blizzard Buffs are active")
    assertFalse(custom.statusButton.shown,
        "active refresh failure has no unsafe action")
end

do
    local harmful = NewOptionsUIHarness(true, 42, true)
    local debuffsConfig = harmful.BD.config.debuffs
    debuffsConfig.customHarmfulEnabled = true
    harmful.topSwitch:SetSelectedValue("debuffs")
    harmful.events = {}
    harmful.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")

    assertEqual(#harmful.events, 0,
        "successful custom harmful programmatic load emits no update")
    assertEqual(harmful.topSwitch.labels[2].text,
        "Debuffs (Public + Private)",
        "successful harmful tab discloses both sources")
    assertEqual(harmful.topSwitch.buttons[2].tooltip,
        "This opt-in replaces Blizzard's ordinary and private Debuffs with one PublicAndPrivate native row. Its finite icon cap is shared; at the cap, either source can displace auras from the other. Deadly Debuffs remain Blizzard controlled.",
        "successful harmful tab carries source/cap disclosure")
    assertTrue(harmful.harmfulOptIn.shown,
        "successful harmful tab shows opt-in")
    assertTrue(harmful.harmfulOptIn.checked,
        "successful custom harmful load retains checked opt-in")
    assertEqual(harmful.dropdownsByLabel.Arrangement.selected,
        "right_to_left_then_down",
        "successful harmful row shows fixed downward flow")
    assertEqual(harmful.slidersByLabel.Width.maximum, 100,
        "successful harmful width uses custom geometry range")
    assertEqual(harmful.slidersByLabel.Height.maximum, 100,
        "successful harmful height uses custom geometry range")
    assertTrue(harmful.dropdownsByLabel["Sort Method"].enabled,
        "successful harmful sort method is editable")
    assertTrue(harmful.slidersByLabel["X Spacing"].enabled,
        "successful harmful spacing is editable")

    harmful.controllerState.active = true
    harmful.controllerState.pending = true
    harmful.controllerState.operationPending = true
    harmful.controllerState.harmfulReassertPending = true
    harmful.controllerState.diagnostic =
        "NATIVE_HARMFUL_REASSERT_FAILED"
    harmful.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(harmful.statusText.textValue,
        "The combined Debuffs row remains active while native suppression recovery is pending.",
        "active harmful recovery status preserves custom ownership")
    assertNil(harmful.statusText.textValue:find(
        "Blizzard Debuffs remain active",
        1,
        true
    ), "active harmful recovery never claims Blizzard ownership")
    assertTrue(harmful.statusText.wordWrap,
        "active harmful recovery copy wraps in the status row")
    assertFalse(harmful.statusButton.shown,
        "active harmful recovery exposes no unsafe action")

    harmful.controllerState.pending = nil
    harmful.controllerState.operationPending = nil
    harmful.controllerState.harmfulReassertPending = nil
    harmful.controllerState.diagnostic = nil
    debuffsConfig.separateOwn = 1
    harmful.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(
        harmful.BD.GetBuffsDebuffsOptionsStatus("debuffs").code,
        "UNSUPPORTED_SEPARATE_OWN",
        "Debuffs Separate Own exposes its recovery status"
    )
    assertEqual(harmful.statusText.textValue,
        "Separate Own is unavailable in 12.1. Blizzard Debuffs remain active.",
        "Debuffs Separate Own status names the Debuffs fallback")
    assertNil(harmful.statusText.textValue:find(
        "Blizzard Buffs remain active",
        1,
        true
    ), "Debuffs Separate Own status never names the Buffs fallback")
    assertTrue(harmful.statusButton.shown,
        "Debuffs Separate Own status exposes supported recovery")

    debuffsConfig.separateOwn = 0
    harmful.controllerState.diagnostic =
        "CONSTRUCTION_CHANGE_REQUIRES_RELOAD"
    harmful.controllerState.reloadRequired = true
    harmful.controllerState.pending = true
    harmful.callbacks.BFI_RefreshOptions(nil, "buffsDebuffs")
    assertEqual(
        harmful.BD.GetBuffsDebuffsOptionsStatus("debuffs").code,
        "RELOAD_REQUIRED",
        "Debuffs construction change exposes reload status"
    )
    assertEqual(harmful.statusText.textValue,
        "Reload UI to apply Debuffs styling. Blizzard Debuffs remain active.",
        "Debuffs reload status names Debuffs styling and fallback")
    assertNil(harmful.statusText.textValue:find(
        "Reload UI to apply Buffs styling",
        1,
        true
    ), "Debuffs reload status never names Buffs styling")
    assertNil(harmful.statusText.textValue:find(
        "Blizzard Buffs remain active",
        1,
        true
    ), "Debuffs reload status never names the Buffs fallback")
    assertTrue(harmful.statusButton.shown,
        "Debuffs reload status exposes the reload action")
    assertEqual(harmful.statusButton.textValue, "Reload UI",
        "Debuffs reload status uses the reload action label")
end

do
    local legacy = NewOptionsUIHarness(false, 42)
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
    assertEqual(legacy.durationMode.tooltip,
        "Durations abbreviate automatically to seconds, minutes, hours, and days.",
        "legacy backend receives the same non-flow duration guidance")
    assertEqual(legacy.topSwitch.labels[1].text, "Buffs",
        "legacy Buffs tab does not claim combined custom sources")
    assertNil(rawget(legacy.topSwitch.buttons[1], "tooltip"),
        "legacy Buffs tab has no custom-source tooltip")

    legacy.events = {}
    legacy.durationMode.onSelect("percent")
    assertEqual(#legacy.events, 1,
        "legacy duration mode remains a live one-event change")
    legacy.events = {}
    legacy.percentValue.confirmValue(44.4)
    legacy.percentValue.textValue = 44.4
    legacy.percentValue.onEditFocusLost(legacy.percentValue)
    assertEqual(config.duration.color.percent.value, 0.444,
        "legacy percent value remains an exact confirmed update")
    assertEqual(#legacy.events, 1,
        "legacy percent confirmation fires one update")
end

do
    local file = assert(io.open("Options/BuffsDebuffs.lua", "r"))
    local source = file:read("*a")
    file:close()

    assertNil(source:find("CreatePrivatePane", 1, true),
        "Private Auras pane construction retired")
    assertNil(source:find("Show Seconds Unit", 1, true),
        "seconds-unit control retired")
    assertTrue(source:find("Low-Time Text Color", 1, true) ~= nil,
        "one Seconds/Percent/Off mode selector is present")
    assertTrue(source:find("color.percent", 1, true) ~= nil,
        "percent threshold controls are retained")
    assertTrue(source:find("color.seconds", 1, true) ~= nil,
        "seconds threshold controls are retained")
    assertTrue(source:find("PublicAndPrivate", 1, true) ~= nil,
        "visible source disclosure names the native source list")
    assertNil(source:find("local sourceDisclosure", 1, true),
        "source disclosure does not consume icon-pane vertical flow")
    assertTrue(source:find("SetAfterValueChanged", 1, true) ~= nil,
        "custom construction sliders commit after interaction")
    assertTrue(source:find("SetOnConfirm", 1, true) ~= nil,
        "custom construction colors commit on confirmation")
end

print("buffs/debuffs options policy tests passed")
