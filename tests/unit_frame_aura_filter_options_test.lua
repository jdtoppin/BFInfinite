local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local function assertContains(value, expected, message)
    assertTrue(
        type(value) == "string"
            and value:find(expected, 1, true) ~= nil,
        message
    )
end

local function assertNotContains(value, expected, message)
    assertTrue(
        type(value) ~= "string"
            or value:find(expected, 1, true) == nil,
        message
    )
end

local CANONICAL_FIELDS = {
    "all",
    "player",
    "notPlayer",
    "raidInCombat",
    "raidPlayerDispellable",
    "bigDefensive",
    "externalDefensive",
    "important",
    "anyDispellable",
}

local LEGACY_FIELDS = {
    "castByMe",
    "castByOthers",
    "castByUnit",
    "castByNPC",
    "isBossAura",
    "dispellable",
    "canBeDispelled",
}

local function updateMockStringHeight(widget)
    if widget.kind ~= "fontString" then return end

    local length = #tostring(widget.text or "")
    if not widget.wordWrap or length <= 60 then
        widget.stringHeight = 12
    elseif length <= 120 then
        widget.stringHeight = 24
    else
        widget.stringHeight = 36
    end
end

local function makeWidget(kind, harness, parent, text)
    local widget = {
        enabled = true,
        initialText = text,
        kind = kind,
        parent = parent,
        shown = true,
        text = text,
    }

    function widget:EnablePushEffect()
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:GetLineHeight()
        return 12
    end

    function widget:GetStringHeight()
        return self.stringHeight or 12
    end

    function widget:Hide()
        self.shown = false
    end

    function widget:HookOnEnter(callback)
        self.onEnter = callback
    end

    function widget:HookOnLeave(callback)
        self.onLeave = callback
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:RegisterForClicks()
    end

    function widget:SetAllPoints()
    end

    function widget:SetBorderColor()
    end

    function widget:SetChecked(value)
        self.checked = value
    end

    function widget:SetColor(...)
        self.color = {...}
    end

    function widget:SetEnabled(value)
        self.enabled = value
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetJustifyH(value)
        self.justifyH = value
    end

    function widget:SetJustifyV(value)
        self.justifyV = value
    end

    function widget:SetLabel(value)
        self.label = value
    end

    function widget:SetOnCheck(callback)
        self.onCheck = callback
    end

    function widget:SetOnChange(callback)
        self.onChange = callback
    end

    function widget:SetOnClick(callback)
        self.onClick = callback
    end

    function widget:SetOnEnterPressed(callback)
        self.onEnterPressed = callback
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetOnTextChanged(callback)
        self.onTextChanged = callback
    end

    function widget:SetOnValueChanged(callback)
        self.onValueChanged = callback
    end

    function widget:SetConfirmButton(callback)
        self.onConfirm = callback
    end

    function widget:SetMaxLetters(value)
        self.maxLetters = value
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetSpacing()
    end

    function widget:SetText(value)
        self.text = value
        updateMockStringHeight(self)
    end

    function widget:SetTextJustifyH()
    end

    function widget:SetTexture()
    end

    function widget:SetTooltip(title, body)
        self.tooltipTitle = title
        self.tooltipBody = body
    end

    function widget:SetValue(value)
        self.value = value
    end

    function widget:SetWordWrap(value)
        self.wordWrap = value
        updateMockStringHeight(self)
    end

    function widget:Show()
        self.shown = true
    end

    harness.widgets[#harness.widgets + 1] = widget
    if parent and parent.widgets then
        parent.widgets[#parent.widgets + 1] = widget
    end
    updateMockStringHeight(widget)
    return widget
end

local function makeParent()
    local parent = {
        _contentHeights = {},
    }

    function parent:GetParent()
        return self
    end

    return parent
end

local function findWidget(pane, kind, field, value)
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == kind and widget[field] == value then
            return widget
        end
    end
end

local function findWidgets(pane, kind, field, value)
    local matches = {}
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == kind and widget[field] == value then
            matches[#matches + 1] = widget
        end
    end
    return matches
end

local function hasPoint(widget, point, relativeTo, relativePoint)
    for _, values in ipairs(widget.points or {}) do
        if values[1] == point
            and (relativeTo == nil or values[2] == relativeTo)
            and (
                relativePoint == nil
                or values[3] == relativePoint
            )
        then
            return true
        end
    end
    return false
end

local function makeHarness(
    isRetail,
    hasNativeBackend,
    auraFilters,
    runtime
)
    runtime = runtime or {}
    if auraFilters == nil then
        auraFilters = hasNativeBackend and {
            Important = "IMPORTANT",
            Dispellable = "DISPELLABLE",
        } or {}
    end
    local harness = {
        configLoads = {},
        panes = {},
        setCalls = {},
        groupBuffCalls = 0,
        spellExistsCalls = 0,
        widgets = {},
        resizeCalls = 0,
    }
    local UF = {}
    local AF = {
        isRetail = isRetail,
    }
    local F = {}
    local paneIndex = 0
    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })

    function AF.ClearPoints(widget)
        widget.points = {}
    end

    function AF.ClearTooltip(widget)
        widget.tooltipTitle = nil
        widget.tooltipBody = nil
    end

    function AF.CreateBorderedFrame(
        parent,
        name,
        _,
        height
    )
        paneIndex = paneIndex + 1
        local pane = {
            height = height or 0,
            index = paneIndex,
            name = name,
            parent = parent,
            widgets = {},
        }

        function pane:GetHeight()
            return self.height
        end

        function pane:SetHeight(value)
            self.height = value
        end

        function pane:SetOnHide(callback)
            self.onHide = callback
        end

        harness.panes[#harness.panes + 1] = pane
        return pane
    end

    function AF.CreateButton(parent, text)
        return makeWidget("button", harness, parent, text)
    end

    function AF.CreateCheckButton(parent, text)
        return makeWidget(
            "checkButton",
            harness,
            parent,
            text
        )
    end

    function AF.CreateColorPicker(parent, text)
        local picker = makeWidget(
            "colorPicker",
            harness,
            parent,
            text
        )
        picker.label = makeWidget(
            "colorPickerLabel",
            harness,
            parent,
            text
        )
        return picker
    end

    function AF.CreateDropdown(parent, width)
        local dropdown = makeWidget("dropdown", harness, parent)
        dropdown.width = width
        return dropdown
    end

    function AF.CreateEditBox(parent, text)
        return makeWidget("editBox", harness, parent, text)
    end

    function AF.CreateFontString(parent, text)
        return makeWidget(
            "fontString",
            harness,
            parent,
            text
        )
    end

    function AF.CreateObjectPool(factory, release)
        local pool = {
            active = {},
        }

        function pool:Acquire()
            local object = factory()
            self.active[#self.active + 1] = object
            return object
        end

        function pool:ReleaseAll()
            for _, object in ipairs(self.active) do
                release(self, object)
            end
            self.active = {}
        end

        return pool
    end

    function AF.CreateSlider(parent, text)
        local slider =
            makeWidget("slider", harness, parent, text)
        slider.label = text
        return slider
    end

    function AF.Debug()
    end

    function AF.FillColorTable(color, r, g, b, a)
        color[1] = r
        color[2] = g
        color[3] = b
        if a ~= nil then color[4] = a end
    end

    function AF.GetColorStr()
        return ""
    end

    function AF.GetDropdownItems_Arrangement_Simple()
        return {
            {text = "Left to Right", value = "left_to_right"},
        }
    end

    function AF.GetDropdownItems_AnchorPoint()
        return {}
    end

    function AF.GetEditBox(parent)
        return makeWidget("editBox", harness, parent)
    end

    function AF.GetGradientText(text)
        return "<gradient>" .. text .. "</gradient>"
    end

    function AF.LSM_GetFontDropdownItems()
        return {}
    end

    function AF.LSM_GetFontOutlineDropdownItems()
        return {}
    end

    function AF.GetIcon(name)
        return name
    end

    function AF.GetIconString(name)
        return "<" .. name .. ">"
    end

    function AF.HideColorPicker()
    end

    function AF.GetSpellInfo(spell)
        return "Spell " .. tostring(spell), "Icon " .. tostring(spell)
    end

    function AF.ReSize()
        harness.resizeCalls = harness.resizeCalls + 1
    end

    function AF.Remove(values, expected)
        for index, value in ipairs(values) do
            if value == expected then
                table.remove(values, index)
                return
            end
        end
    end

    function AF.RegisterCallback()
    end

    function AF.SetEnabled(enabled, ...)
        for index = 1, select("#", ...) do
            select(index, ...):SetEnabled(enabled)
        end
    end

    function AF.SetListHeight(
        pane,
        itemNum,
        itemHeight,
        itemSpacing,
        topPadding,
        bottomPadding
    )
        pane.listTopPadding = topPadding
        pane.height = itemNum * itemHeight
            + (itemNum - 1) * itemSpacing
            + topPadding
            + bottomPadding
    end

    function AF.SetPoint(widget, ...)
        widget.points = widget.points or {}
        widget.points[#widget.points + 1] = {...}
    end

    function AF.SpellExists()
        harness.spellExistsCalls =
            harness.spellExistsCalls + 1
        return true
    end

    function AF.WrapTextInColor(text)
        return text
    end

    AF.Tooltip2 = {
        Hide = function()
        end,
        SetOwner = function()
        end,
        SetPoint = function()
        end,
        SetSpellByID = function()
        end,
        Show = function()
        end,
    }

    function UF.HasNativeAuraContainerBackend()
        return hasNativeBackend
    end

    function UF.LoadIndicatorConfig(frame, id, config)
        harness.configLoads[#harness.configLoads + 1] = {
            config = config,
            frame = frame,
            id = id,
        }
    end

    function UF.LoadIndicatorPosition()
    end

    local BFI = {
        funcs = F,
        L = L,
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        AuraUtil = {
            AuraFilters = auraFilters,
        },
        BFIOptionsFrame_UnitFramesPanel = {},
        NONE = "None",
        ceil = math.ceil,
        error = error,
        GetCVar = function()
            return "0"
        end,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        rawget = rawget,
        select = select,
        string = string,
        table = table,
        tinsert = table.insert,
        tostring = tostring,
        type = type,
        RunNextFrame = function(callback)
            callback()
        end,
        wipe = function(value)
            for key in pairs(value) do
                value[key] = nil
            end
        end,
    }
    if runtime.specializationRole
        or runtime.specializationNamespaceAvailable
    then
        environment.C_SpecializationInfo = {}
        if not runtime.omitGetSpecialization then
            environment.C_SpecializationInfo.GetSpecialization =
                function()
                    return runtime.specialization or 1
                end
        end
        if not runtime.omitGetSpecializationInfo then
            environment.C_SpecializationInfo.GetSpecializationInfo =
                function(specialization)
                    if specialization == nil then return end
                    return 0, nil, nil, nil,
                        runtime.specializationRole
                end
        end
    end
    if runtime.groupBuffAPIAvailable then
        environment.bit = {
            band = function(value, flag)
                if flag ~= 1 then
                    error("unexpected group-buff flag")
                end
                return value % 2
            end,
        }
        environment.C_CooldownViewer = {
            GetGroupBuffItems = function()
                harness.groupBuffCalls =
                    harness.groupBuffCalls + 1
                return runtime.groupBuffItems or {}
            end,
        }
        environment.Enum = {
            GroupBuffItemFlags = {
                HideByDefault = 1,
            },
        }
    end
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected aura filter option global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local utilsChunk, utilsLoadError = loadfile("Utils.lua")
    assertTrue(utilsChunk, utilsLoadError)
    setfenv(utilsChunk, environment)
    utilsChunk("BFInfinite", BFI)

    local setAuraFilter = F.SetUnitFrameAuraFilter
    function F.SetUnitFrameAuraFilter(baseFilter, config, field, value)
        local changed = setAuraFilter(baseFilter, config, field, value)
        if changed then
            harness.setCalls[#harness.setCalls + 1] = {
                baseFilter = baseFilter,
                field = field,
                value = value,
            }
        end
        return changed
    end

    local chunk, loadError =
        loadfile("Options/UnitFrames_Options.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local builders
    local index = 1
    while true do
        local name, value =
            debug.getupvalue(F.GetUnitFrameOptions, index)
        if not name then break end
        if name == "builder" then
            builders = value
            break
        end
        index = index + 1
    end
    assertTrue(builders, "options builder registry")

    harness.AF = AF
    harness.builders = builders
    harness.F = F
    harness.UF = UF

    function harness:ClearLoads()
        self.configLoads = {}
    end

    return harness
end

local function newFrame(id, runtimeKind)
    local frame = {
        indicators = {
            buffs = {},
            debuffs = {},
        },
    }
    if runtimeKind then
        local indicator = {
            LoadConfig = function()
            end,
        }
        if runtimeKind == "native" then
            indicator.GetNativeAuraState = function()
                return {}
            end
        end
        frame.indicators[id] = indicator
    end
    return frame
end

local function newInfo(id, owner, filters, runtimeKind)
    owner = owner or "target"
    local target
    if owner == "party" or owner == "raid" then
        local count = owner == "party" and 5 or 40
        target = {
            header = {},
        }
        for index = 1, count do
            target.header[index] = newFrame(id, runtimeKind)
        end
    elseif owner == "boss" then
        target = {}
        for index = 1, 8 do
            target[index] = newFrame(id, runtimeKind)
        end
    else
        target = newFrame(id, runtimeKind)
    end

    return {
        cfg = {
            auraTypeColor = {
                castByMe = true,
                debuffType = true,
                dispellable = true,
            },
            blacklist = {12345},
            cooldownStyle = "clock_with_leading_edge",
            durationText = {
                enabled = true,
                font = {"BFI", 10, "outline", false},
                position = {"TOP", "TOP", 1, 1},
                color = {
                    normal = {1, 1, 1, 1},
                    percent = {
                        enabled = true,
                        value = 0.5,
                        rgb = {1, 0.8, 0, 1},
                    },
                    seconds = {
                        enabled = true,
                        value = 5,
                        rgb = {1, 0, 0, 1},
                    },
                },
            },
            filters = filters or {},
            height = 19,
            mode = "blacklist",
            numPerLine = 11,
            numTotal = 22,
            orientation = "left_to_right",
            spacingX = 1,
            spacingY = 1,
            subFrame = {
                desaturated = true,
                enabled = true,
                filter = "notCastByMe",
                height = 17,
                width = 17,
            },
            whitelist = {},
            width = 19,
        },
        id = id,
        owner = owner,
        target = target,
    }
end

local function assertItemValues(widget, expected, message)
    assertEqual(#widget.items, #expected, message .. " count")
    for index, value in ipairs(expected) do
        assertEqual(
            widget.items[index].value,
            value,
            message .. " item " .. index
        )
    end
end

local function assertValues(actual, expected, message)
    assertEqual(#actual, #expected, message .. " count")
    for index, value in ipairs(expected) do
        assertEqual(
            actual[index],
            value,
            message .. " item " .. index
        )
    end
end

local function assertFanout(harness, info, expected, message)
    assertEqual(#harness.configLoads, expected, message .. " count")
    for _, call in ipairs(harness.configLoads) do
        assertEqual(call.id, info.id, message .. " indicator")
        assertEqual(call.config, info.cfg, message .. " config")
    end
end

local function assertCanonical(config, expected, message)
    for _, field in ipairs(CANONICAL_FIELDS) do
        assertEqual(
            config[field],
            expected[field],
            message .. " " .. field
        )
        assertEqual(
            type(config[field]),
            "boolean",
            message .. " " .. field .. " type"
        )
    end
    for _, field in ipairs(LEGACY_FIELDS) do
        assertEqual(
            config[field],
            nil,
            message .. " retired " .. field
        )
    end
end

local function testRetailCanonicalFilters(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)
    local parent = makeParent()
    local pane =
        harness.builders.auraBaseFilters(parent)
    local info = newInfo("buffs", "boss", {
        castByMe = true,
        castByOthers = false,
        castByUnit = true,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    }, "legacy")

    pane.Load(info)
    local allAuras = findWidget(
        pane,
        "checkButton",
        "text",
        "All Auras"
    )
    local player = findWidget(
        pane,
        "checkButton",
        "text",
        "Player, Pet, or Vehicle"
    )
    local notPlayer = findWidget(
        pane,
        "checkButton",
        "text",
        "Not Player, Pet, or Vehicle"
    )
    local bigDefensive = findWidget(
        pane,
        "checkButton",
        "text",
        "Big Defensive"
    )
    local externalDefensive = findWidget(
        pane,
        "checkButton",
        "text",
        "External Defensive"
    )
    local raidInCombat = findWidget(
        pane,
        "checkButton",
        "text",
        "Raid In Combat"
    )
    local raidDispellable = findWidget(
        pane,
        "checkButton",
        "text",
        "Raid Player-Dispellable"
    )
    local anyDispellable = findWidget(
        pane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    local important = findWidget(
        pane,
        "checkButton",
        "initialText",
        "Important Enemy Buffs"
    )
    local tip = findWidget(
        pane,
        "fontString",
        "initialText",
        "The aura will show if any enabled filter is met"
    )

    assertTrue(allAuras and player and notPlayer,
        version .. " base and source-partition controls")
    assertTrue(bigDefensive and externalDefensive,
        version .. " defensive category controls")
    assertTrue(raidInCombat,
        version .. " raid-in-combat category control")
    assertTrue(raidDispellable,
        version .. " raid-dispellable category control")
    assertContains(
        tip.text,
        "All Auras overrides",
        version .. " category explanation"
    )
    assertEqual(tip.wordWrap, true,
        version .. " category explanation word wrap")
    assertEqual(tip.justifyH, "LEFT",
        version .. " category explanation horizontal alignment")
    assertEqual(tip.justifyV, "TOP",
        version .. " category explanation vertical alignment")
    assertTrue(
        hasPoint(tip, "TOPLEFT")
            and hasPoint(tip, "TOPRIGHT"),
        version .. " category explanation width bounds"
    )
    assertTrue(
        hasPoint(
            allAuras,
            "TOPLEFT",
            tip,
            "BOTTOMLEFT"
        ),
        version .. " category controls follow explanation"
    )
    assertTrue(
        pane.height > 117,
        version .. " category pane wrapped height"
    )
    assertEqual(
        parent._contentHeights[pane.index],
        tostring(pane.height),
        version .. " category scroll height"
    )
    assertTrue(
        harness.resizeCalls > 0,
        version .. " category scroll recalculation"
    )
    assertEqual(anyDispellable.shown, hasNativeBackend,
        version .. " any-dispellable capability visibility")
    assertEqual(important.shown, hasNativeBackend,
        version .. " important capability visibility")
    assertEqual(anyDispellable.text, "Any Dispel Type",
        version .. " any-dispellable label")
    assertEqual(important.text, "Important Enemy Buffs",
        version .. " important label")
    if hasNativeBackend then
        assertContains(
            raidDispellable.tooltipBody,
            "someone in your raid can dispel",
            version .. " raid-dispellable raid capability"
        )
        assertContains(
            raidDispellable.tooltipBody,
            "including helpful enrages on enemies",
            version .. " raid-dispellable enemy-enrage scope"
        )
    else
        assertContains(
            raidDispellable.tooltipBody,
            "your character can dispel",
            version .. " raid-dispellable player capability"
        )
        assertNotContains(
            raidDispellable.tooltipBody,
            "someone in your raid",
            version .. " raid-dispellable PTR semantics"
        )
    end
    if hasNativeBackend then
        assertEqual(anyDispellable.enabled, false,
            version .. " legacy-row any-dispellable enabled state")
        assertEqual(important.enabled, false,
            version .. " legacy-row important enabled state")
        assertEqual(
            anyDispellable.tooltipTitle,
            "Native Aura Container Required",
            version .. " legacy-row any-dispellable explanation"
        )
        assertContains(
            anyDispellable.tooltipBody,
            "widens the selection to all auras of this type",
            version .. " legacy-row any-dispellable behavior"
        )
        assertEqual(
            important.tooltipTitle,
            "Native Aura Container Required",
            version .. " legacy-row important explanation"
        )
        assertContains(
            important.tooltipBody,
            "widens the selection to all auras of this type",
            version .. " legacy-row important behavior"
        )
    end
    assertEqual(allAuras.checked, true,
        version .. " migrated all state")
    assertEqual(player.checked, false,
        version .. " migrated player state")
    assertEqual(notPlayer.checked, false,
        version .. " migrated not-player state")
    assertEqual(bigDefensive.checked, false,
        version .. " migrated big defensive state")
    assertEqual(externalDefensive.checked, false,
        version .. " migrated external defensive state")
    assertEqual(raidInCombat.checked, false,
        version .. " migrated raid-in-combat state")
    assertEqual(raidDispellable.checked, false,
        version .. " migrated raid-dispellable state")
    assertEqual(anyDispellable.checked, false,
        version .. " migrated any-dispellable state")
    assertEqual(important.checked, false,
        version .. " migrated important state")
    assertEqual(
        allAuras.tooltipTitle,
        "Conservative Legacy Migration",
        version .. " widened source migration warning"
    )
    assertContains(
        allAuras.tooltipBody,
        "not silently lost",
        version .. " widened source migration explanation"
    )

    harness:ClearLoads()
    local actions = {
        {widget = allAuras, field = "all", value = false},
        {widget = player, field = "player", value = true},
        {
            widget = notPlayer,
            field = "notPlayer",
            value = true,
        },
        {widget = allAuras, field = "all", value = false},
        {
            widget = bigDefensive,
            field = "bigDefensive",
            value = true,
        },
        {
            widget = externalDefensive,
            field = "externalDefensive",
            value = true,
        },
        {
            widget = raidInCombat,
            field = "raidInCombat",
            value = true,
        },
        {
            widget = raidDispellable,
            field = "raidPlayerDispellable",
            value = true,
        },
    }
    for index, action in ipairs(actions) do
        action.widget.onCheck(action.value)
        assertEqual(
            harness.setCalls[index].field,
            action.field,
            version .. " callback field " .. index
        )
        assertEqual(
            harness.setCalls[index].baseFilter,
            "HELPFUL",
            version .. " callback base filter " .. index
        )
        assertEqual(
            #harness.configLoads,
            index * 8,
            version .. " callback fan-out " .. index
        )
    end
    assertFanout(
        harness,
        info,
        64,
        version .. " canonical callback fan-out"
    )
    assertCanonical(info.cfg.filters, {
        all = false,
        player = false,
        notPlayer = false,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
        important = false,
        anyDispellable = false,
    }, version .. " canonical materialization")

    local harmful = newInfo("debuffs", "focus", {
        player = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
        important = true,
        anyDispellable = true,
    })
    pane.Load(harmful)
    assertEqual(bigDefensive.checked, false,
        version .. " harmful big defensive state")
    assertEqual(externalDefensive.checked, false,
        version .. " harmful external defensive state")
    assertEqual(bigDefensive.enabled, false,
        version .. " harmful big defensive enabled state")
    assertEqual(externalDefensive.enabled, false,
        version .. " harmful external defensive enabled state")
    assertEqual(raidDispellable.enabled, true,
        version .. " hostile raid-dispellable enabled state")
    assertEqual(anyDispellable.enabled, hasNativeBackend,
        version .. " harmful any-dispellable enabled state")
    assertEqual(important.enabled, false,
        version .. " harmful important enabled state")
    assertEqual(allAuras.enabled, true,
        version .. " harmful all enabled state")
    assertEqual(notPlayer.enabled, true,
        version .. " harmful not-player enabled state")

    local friendly = newInfo("buffs", "player", {
        player = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
        important = true,
        anyDispellable = true,
    })
    pane.Load(friendly)
    assertEqual(raidDispellable.enabled, false,
        version .. " friendly raid-dispellable enabled state")
    assertEqual(anyDispellable.enabled, hasNativeBackend,
        version .. " friendly any-dispellable enabled state")
    assertEqual(important.enabled, false,
        version .. " friendly important enabled state")

    if hasNativeBackend then
        local hostileHelpful = newInfo(
            "buffs",
            "target",
            {
                player = true,
                important = false,
                anyDispellable = false,
            },
            "native"
        )
        pane.Load(hostileHelpful)
        assertEqual(important.enabled, true,
            version .. " hostile helpful important enabled state")
        assertEqual(anyDispellable.enabled, true,
            version .. " hostile helpful any-dispellable enabled state")
        assertContains(
            important.tooltipBody,
            "Blizzard flags as important",
            version .. " important category explanation"
        )
        assertContains(
            anyDispellable.tooltipBody,
            "whether or not anyone in your raid",
            version .. " any-dispellable explanation"
        )

        local firstSetCall = #harness.setCalls + 1
        harness:ClearLoads()
        important.onCheck(true)
        anyDispellable.onCheck(true)
        assertEqual(
            harness.setCalls[firstSetCall].field,
            "important",
            version .. " important callback field"
        )
        assertEqual(
            harness.setCalls[firstSetCall + 1].field,
            "anyDispellable",
            version .. " any-dispellable callback field"
        )
        assertEqual(
            hostileHelpful.cfg.filters.important,
            true,
            version .. " important callback state"
        )
        assertEqual(
            hostileHelpful.cfg.filters.anyDispellable,
            true,
            version .. " any-dispellable callback state"
        )
        assertFanout(
            harness,
            hostileHelpful,
            2,
            version .. " PTR 7 category callback fan-out"
        )
    end

    local sourceOnly = newInfo("debuffs", "target", {
        castByMe = false,
        castByOthers = true,
        castByUnit = false,
        castByNPC = false,
        isBossAura = false,
        dispellable = false,
    })
    pane.Load(sourceOnly)
    assertEqual(allAuras.checked, false,
        version .. " source-only all state")
    assertEqual(notPlayer.checked, true,
        version .. " source-only not-player state")

    local bossOnly = newInfo("debuffs", "target", {
        castByMe = false,
        castByOthers = false,
        castByUnit = false,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    })
    pane.Load(bossOnly)
    assertEqual(raidInCombat.checked, true,
        version .. " legacy boss curated state")
    assertEqual(
        raidInCombat.tooltipTitle,
        "Conservative Legacy Migration",
        version .. " legacy boss approximation warning"
    )

    local migratedDispellable = newInfo(
        "debuffs",
        "target",
        {
            castByMe = false,
            castByOthers = false,
            castByUnit = false,
            castByNPC = false,
            isBossAura = false,
            dispellable = true,
        },
        "legacy"
    )
    pane.Load(migratedDispellable)
    assertEqual(
        raidDispellable.checked,
        true,
        version .. " legacy dispellable migrated state"
    )
    assertEqual(
        raidDispellable.tooltipTitle,
        "Conservative Legacy Migration",
        version .. " legacy dispellable migration warning"
    )
    assertContains(
        raidDispellable.tooltipBody,
        "Legacy Dispellable now uses Blizzard's RAID_PLAYER_DISPELLABLE category",
        version .. " legacy dispellable category mapping"
    )
    assertContains(
        raidDispellable.tooltipBody,
        "on 12.1 this means someone in your raid can dispel the aura",
        version .. " legacy dispellable PTR semantic warning"
    )

    if not hasNativeBackend then
        local importedPtr7 = newInfo(
            "buffs",
            "target",
            {
                all = false,
                player = false,
                notPlayer = false,
                raidInCombat = false,
                raidPlayerDispellable = false,
                bigDefensive = false,
                externalDefensive = false,
                important = true,
                anyDispellable = true,
            },
            "legacy"
        )
        pane.Load(importedPtr7)
        assertEqual(
            allAuras.checked,
            true,
            version .. " imported PTR 7 effective all state"
        )
        assertEqual(
            player.checked,
            false,
            version .. " imported PTR 7 narrower state"
        )
        assertEqual(
            important.shown,
            false,
            version .. " imported unsupported IMPORTANT visibility"
        )
        assertEqual(
            anyDispellable.shown,
            false,
            version .. " imported unsupported DISPELLABLE visibility"
        )
        assertContains(
            tip.text,
            "profile selects a 12.1 aura category unavailable",
            version .. " imported PTR 7 visible warning"
        )
        assertContains(
            tip.text,
            "widens the row to All Auras",
            version .. " imported PTR 7 effective behavior"
        )
        assertEqual(
            allAuras.tooltipTitle,
            "Newer Aura Category Fallback",
            version .. " imported PTR 7 tooltip title"
        )

        harness:ClearLoads()
        player.onCheck(true)
        assertEqual(
            importedPtr7.cfg.filters.important,
            false,
            version .. " supported edit retires IMPORTANT"
        )
        assertEqual(
            importedPtr7.cfg.filters.anyDispellable,
            false,
            version .. " supported edit retires DISPELLABLE"
        )
        assertEqual(
            importedPtr7.cfg.filters.player,
            true,
            version .. " supported edit applies selected category"
        )
        assertFanout(
            harness,
            importedPtr7,
            1,
            version .. " imported PTR 7 retirement fan-out"
        )

        pane.Load(importedPtr7)
        assertEqual(
            allAuras.checked,
            false,
            version .. " retired PTR 7 effective all state"
        )
        assertEqual(
            player.checked,
            true,
            version .. " retired PTR 7 player state"
        )
        assertNotContains(
            tip.text,
            "profile selects a 12.1 aura category unavailable",
            version .. " retired PTR 7 warning"
        )
    end
end

local function testRetailSpellLists(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)
    local parent = makeParent()
    local pane = harness.builders.auraBlackListWhitelist(parent)
    local info = newInfo(
        hasNativeBackend and "debuffs" or "buffs",
        hasNativeBackend and "focus" or "target"
    )

    pane.Load(info)
    local mode = findWidget(pane, "dropdown", "kind", "dropdown")
    local tip = findWidget(pane, "fontString", "kind", "fontString")
    local addButton
    local spellButton
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == "button" and widget.spell == 12345 then
            spellButton = widget
        elseif widget.kind == "button" and not widget.spell then
            addButton = addButton or widget
        end
    end

    assertEqual(mode.enabled, hasNativeBackend,
        version .. " spell-list mode enabled state")
    assertEqual(addButton.enabled, hasNativeBackend,
        version .. " spell-list add enabled state")
    assertEqual(spellButton.enabled, hasNativeBackend,
        version .. " spell-list entry enabled state")
    assertEqual(tip.wordWrap, true,
        version .. " spell-list explanation word wrap")
    assertEqual(tip.justifyH, "LEFT",
        version .. " spell-list explanation horizontal alignment")
    assertEqual(tip.justifyV, "TOP",
        version .. " spell-list explanation vertical alignment")
    assertTrue(
        hasPoint(tip, "TOPLEFT")
            and hasPoint(tip, "TOPRIGHT"),
        version .. " spell-list explanation width bounds"
    )
    assertTrue(
        hasPoint(
            spellButton,
            "TOPLEFT",
            tip,
            "BOTTOMLEFT"
        ),
        version .. " spell-list controls follow explanation"
    )
    assertTrue(
        pane.listTopPadding > 36,
        version .. " spell-list wrapped top padding"
    )
    assertEqual(
        parent._contentHeights[pane.index],
        tostring(pane.height),
        version .. " spell-list scroll height"
    )
    assertTrue(
        harness.resizeCalls > 0,
        version .. " spell-list scroll recalculation"
    )
    assertEqual(mode.items[1].text,
        "Hide Listed Spells",
        version .. " blacklist label")
    assertEqual(mode.items[2].text,
        "Show Only Listed Spells",
        version .. " whitelist label")
    assertEqual(mode.width, 220,
        version .. " spell-list dropdown width")
    assertItemValues(
        mode,
        {"blacklist", "whitelist"},
        version .. " spell-list modes"
    )
    if hasNativeBackend then
        assertContains(
            tip.text,
            "buffs on units you can help and debuffs on units you cannot help",
            version .. " spell-list warning"
        )
        assertContains(
            tip.text,
            "protected auras may bypass the list",
            version .. " spell-list limitation warning"
        )
        assertContains(
            tip.text,
            "Auras Blizzard keeps available can still be filtered",
            version .. " spell-list exception warning"
        )
        assertContains(
            tip.text,
            "BFI hides that aura row",
            version .. " spell-list conservative holder behavior"
        )
        assertContains(
            tip.text,
            "<MouseLeftClick>Edit",
            version .. " spell-list edit hint"
        )
        assertContains(
            tip.text,
            "<MouseRightClick>Delete",
            version .. " spell-list delete hint"
        )
    else
        assertContains(
            tip.text,
            "require WoW 12.1",
            version .. " spell-list backend warning"
        )
        assertContains(
            tip.text,
            "saved list is kept",
            version .. " spell-list read-only warning"
        )
        assertNotContains(
            tip.text,
            "<MouseLeftClick>Edit",
            version .. " inactive edit hint"
        )
        assertNotContains(
            tip.text,
            "<MouseRightClick>Delete",
            version .. " inactive delete hint"
        )
    end
end

local function testHealerSpellImporterGatingAndLayout()
    local runtime = {
        groupBuffAPIAvailable = true,
        groupBuffItems = {
            {spellID = 400, flags = 0, isKnown = true},
        },
        specializationRole = "HEALER",
    }
    local harness = makeHarness(true, true, nil, runtime)
    local pane = harness.builders.auraBlackListWhitelist(
        makeParent()
    )
    local info = newInfo("buffs", "focus", nil, "native")
    info.cfg.mode = "whitelist"
    info.cfg.whitelist = {12345}

    pane.Load(info)
    local importButton = findWidget(
        pane,
        "button",
        "initialText",
        "Import Healer Spells"
    )
    local addButton = findWidget(
        pane,
        "button",
        "initialText",
        nil
    )
    assertTrue(importButton, "healer importer button")
    assertEqual(importButton.text, "Import Healer Spells",
        "healer importer label")
    assertEqual(importButton.shown, true,
        "native helpful whitelist healer importer visibility")
    assertEqual(importButton.enabled, true,
        "native helpful whitelist healer importer enabled state")
    assertContains(
        importButton.tooltipBody,
        "current healing specialization",
        "healer importer tooltip"
    )
    assertTrue(
        hasPoint(
            importButton,
            "TOPLEFT",
            addButton,
            "TOPRIGHT"
        ),
        "healer importer sits next to add"
    )
    assertEqual(harness.groupBuffCalls, 1,
        "healer importer validates Blizzard catalog on load")

    info.cfg.mode = "blacklist"
    pane.Load(info)
    assertEqual(importButton.shown, false,
        "healer importer hidden for blacklist")
    assertEqual(importButton.enabled, false,
        "healer importer disabled for blacklist")

    local debuffs = newInfo("debuffs", "focus", nil, "native")
    debuffs.cfg.mode = "whitelist"
    pane.Load(debuffs)
    assertEqual(importButton.shown, false,
        "healer importer hidden for harmful auras")
    assertEqual(importButton.enabled, false,
        "healer importer disabled for harmful auras")

    local legacy = newInfo("buffs", "focus", nil, "legacy")
    legacy.cfg.mode = "whitelist"
    pane.Load(legacy)
    assertEqual(importButton.shown, false,
        "healer importer hidden for legacy aura row")
    assertEqual(importButton.enabled, false,
        "healer importer disabled for legacy aura row")

    runtime.specializationRole = "DAMAGER"
    info.cfg.mode = "whitelist"
    pane.Load(info)
    assertEqual(importButton.shown, false,
        "healer importer hidden outside healing specialization")
    assertEqual(importButton.enabled, false,
        "healer importer disabled outside healing specialization")
    assertEqual(
        harness.groupBuffCalls,
        1,
        "ineligible rows do not read Blizzard group buffs"
    )

    local function assertSpecializationGateFailsClosed(
        gateRuntime,
        label
    )
        gateRuntime.groupBuffAPIAvailable = true
        gateRuntime.groupBuffItems = {
            {spellID = 400, flags = 0, isKnown = true},
        }
        local gateHarness = makeHarness(
            true,
            true,
            nil,
            gateRuntime
        )
        local gatePane =
            gateHarness.builders.auraBlackListWhitelist(
                makeParent()
            )
        local gateInfo =
            newInfo("buffs", "focus", nil, "native")
        gateInfo.cfg.mode = "whitelist"
        gatePane.Load(gateInfo)
        local gateButton = findWidget(
            gatePane,
            "button",
            "initialText",
            "Import Healer Spells"
        )
        assertEqual(
            gateButton.shown,
            false,
            label .. " importer visibility"
        )
        assertEqual(
            gateButton.enabled,
            false,
            label .. " importer enabled state"
        )
        assertEqual(
            gateHarness.groupBuffCalls,
            0,
            label .. " catalog reads"
        )
    end

    assertSpecializationGateFailsClosed(
        {},
        "missing specialization namespace"
    )
    assertSpecializationGateFailsClosed(
        {
            specializationNamespaceAvailable = true,
            omitGetSpecialization = true,
        },
        "missing GetSpecialization"
    )
    assertSpecializationGateFailsClosed(
        {
            specializationNamespaceAvailable = true,
            omitGetSpecializationInfo = true,
        },
        "missing GetSpecializationInfo"
    )
end

local function testHealerSpellImporterUnavailableAndEmpty()
    local unavailableHarness = makeHarness(
        true,
        true,
        nil,
        {specializationRole = "HEALER"}
    )
    local unavailablePane =
        unavailableHarness.builders.auraBlackListWhitelist(
            makeParent()
        )
    local unavailableInfo =
        newInfo("buffs", "focus", nil, "native")
    unavailableInfo.cfg.mode = "whitelist"
    unavailableInfo.cfg.whitelist = {12345}
    unavailablePane.Load(unavailableInfo)
    local unavailableButton = findWidget(
        unavailablePane,
        "button",
        "initialText",
        "Import Healer Spells"
    )
    assertEqual(unavailableButton.shown, true,
        "unavailable healer importer remains discoverable")
    assertEqual(unavailableButton.enabled, false,
        "unavailable healer importer disabled")
    unavailableButton.onClick()
    assertValues(
        unavailableInfo.cfg.whitelist,
        {12345},
        "unavailable healer importer preserves list"
    )
    assertFanout(
        unavailableHarness,
        unavailableInfo,
        0,
        "unavailable healer importer update"
    )

    local runtime = {
        groupBuffAPIAvailable = true,
        groupBuffItems = {},
        specializationRole = "HEALER",
    }
    local emptyHarness = makeHarness(true, true, nil, runtime)
    local emptyPane =
        emptyHarness.builders.auraBlackListWhitelist(
            makeParent()
        )
    local emptyInfo = newInfo("buffs", "focus", nil, "native")
    emptyInfo.cfg.mode = "whitelist"
    emptyInfo.cfg.whitelist = {12345}
    emptyPane.Load(emptyInfo)
    local emptyButton = findWidget(
        emptyPane,
        "button",
        "initialText",
        "Import Healer Spells"
    )
    assertEqual(emptyButton.shown, true,
        "empty healer importer remains discoverable")
    assertEqual(emptyButton.enabled, false,
        "empty healer importer disabled")
    emptyButton.onClick()
    assertValues(
        emptyInfo.cfg.whitelist,
        {12345},
        "empty healer importer preserves list"
    )
    assertEqual(emptyHarness.groupBuffCalls, 2,
        "empty healer importer rechecks on click")
    assertFanout(
        emptyHarness,
        emptyInfo,
        0,
        "empty healer importer update"
    )

    runtime.groupBuffItems = {
        {spellID = 333, flags = 1, isKnown = true},
    }
    emptyPane.Load(emptyInfo)
    assertEqual(emptyButton.enabled, false,
        "HideByDefault-only healer importer disabled")
    assertEqual(emptyHarness.groupBuffCalls, 3,
        "HideByDefault-only healer importer catalog check")
end

local function testHealerSpellImporterMergeAndIdempotence()
    local runtime = {
        groupBuffAPIAvailable = true,
        groupBuffItems = {
            {spellID = 200, flags = 0, isKnown = true},
            {spellID = 300, flags = 1, isKnown = true},
            {spellID = 400, flags = 0, isKnown = false},
            {spellID = 500, flags = 0, isKnown = true},
            {spellID = 400, flags = 0, isKnown = false},
            {spellID = 600, flags = 3, isKnown = true},
        },
        specializationRole = "HEALER",
    }
    local harness = makeHarness(true, true, nil, runtime)
    local pane = harness.builders.auraBlackListWhitelist(
        makeParent()
    )
    local info = newInfo("buffs", "focus", nil, "native")
    info.cfg.mode = "whitelist"
    info.cfg.whitelist = {900, 200, 900, 700}
    local originalList = info.cfg.whitelist

    pane.Load(info)
    local importButton = findWidget(
        pane,
        "button",
        "initialText",
        "Import Healer Spells"
    )
    local addButton = findWidget(
        pane,
        "button",
        "initialText",
        nil
    )
    local spellButtons = {}
    for _, widget in ipairs(pane.widgets) do
        if widget.kind == "button" and widget.spell then
            spellButtons[#spellButtons + 1] = widget
        end
    end
    assertTrue(
        hasPoint(
            addButton,
            "TOPLEFT",
            spellButtons[3],
            "BOTTOMLEFT"
        ),
        "add row follows the final spell row"
    )
    assertTrue(
        hasPoint(
            importButton,
            "TOPLEFT",
            addButton,
            "TOPRIGHT"
        ),
        "importer shares the add row"
    )

    local paneReloads = 0
    local originalLoad = pane.Load
    pane.Load = function(t)
        paneReloads = paneReloads + 1
        return originalLoad(t)
    end
    harness:ClearLoads()
    importButton.onClick()

    assertEqual(info.cfg.whitelist, originalList,
        "healer importer preserves SavedVariables table")
    assertValues(
        info.cfg.whitelist,
        {900, 200, 900, 700, 400, 500},
        "healer importer merge order"
    )
    assertEqual(paneReloads, 1,
        "healer importer pane reload count")
    assertFanout(
        harness,
        info,
        1,
        "healer importer config fan-out"
    )
    assertEqual(harness.spellExistsCalls, 0,
        "healer importer skips legacy spell existence lookup")
    assertEqual(harness.groupBuffCalls, 3,
        "healer importer reads catalog for enable, click, and reload")

    harness:ClearLoads()
    importButton.onClick()
    assertValues(
        info.cfg.whitelist,
        {900, 200, 900, 700, 400, 500},
        "healer importer second-click list"
    )
    assertEqual(paneReloads, 1,
        "healer importer second-click reload count")
    assertFanout(
        harness,
        info,
        0,
        "healer importer second-click fan-out"
    )
    assertEqual(harness.groupBuffCalls, 4,
        "healer importer second-click catalog snapshot")
end

local NATIVE_AURA_OWNERS = {
    "boss",
    "focus",
    "focustarget",
    "player",
    "pet",
    "pettarget",
    "targettarget",
}

local LEGACY_AURA_OWNERS = {
    "party",
    "raid",
    "target",
}

local function testRetailIndicatorAwareNativeWording()
    local harness = makeHarness(true, true)
    local spellParent = makeParent()
    local spellPane =
        harness.builders.auraBlackListWhitelist(spellParent)
    local arrangementPane =
        harness.builders.auraArrangement(makeParent())
    local cooldownPane =
        harness.builders.cooldownStyle(makeParent())
    local mode = findWidget(
        spellPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    local tip = findWidget(
        spellPane,
        "fontString",
        "kind",
        "fontString"
    )
    local maximum = findWidget(
        arrangementPane,
        "slider",
        "initialText",
        "Max Displayed"
    )
    local cooldown = findWidget(
        cooldownPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    local nativeTopPadding

    local function assertNativePresentation(
        id,
        owner,
        runtimeKind
    )
        local label = owner .. " " .. id
        local info = newInfo(id, owner, nil, runtimeKind)

        spellPane.Load(info)
        assertEqual(
            mode.items[1].text,
            "Hide Listed Spells",
            label .. " native spell-list label"
        )
        assertEqual(
            mode.enabled,
            true,
            label .. " native spell-list editability"
        )
        assertContains(
            tip.text,
            "Works for buffs on units you can help and debuffs on units you cannot help",
            label .. " native spell-list message"
        )
        assertContains(
            tip.text,
            "protected auras may bypass the list",
            label .. " native limitation message"
        )
        assertContains(
            tip.text,
            "Auras Blizzard keeps available can still be filtered",
            label .. " native exception message"
        )
        assertContains(
            tip.text,
            "BFI hides that aura row",
            label .. " native holder behavior"
        )
        assertContains(
            tip.text,
            "<MouseLeftClick>Edit",
            label .. " native edit hint"
        )
        assertContains(
            tip.text,
            "<MouseRightClick>Delete",
            label .. " native delete hint"
        )
        assertNotContains(
            tip.text,
            "not applied here",
            label .. " inactive spell-list message"
        )
        if nativeTopPadding then
            assertEqual(
                spellPane.listTopPadding,
                nativeTopPadding,
                label .. " repeated native wrapped height"
            )
        else
            nativeTopPadding = spellPane.listTopPadding
        end
        assertEqual(
            spellParent._contentHeights[spellPane.index],
            tostring(spellPane.height),
            label .. " native scroll height"
        )

        arrangementPane.Load(info)
        assertEqual(
            maximum.label,
            "Max Per Aura Group",
            label .. " native maximum label"
        )
        assertContains(
            maximum.tooltipBody,
            "applies to each group",
            label .. " native maximum warning"
        )
        assertContains(
            maximum.tooltipBody,
            "more auras overall",
            label .. " native independent group totals"
        )
        assertContains(
            maximum.tooltipBody,
            "sort separately",
            label .. " native independent group sorting"
        )

        cooldownPane.Load(info)
        assertContains(
            cooldown.tooltipBody,
            "opaque aura duration",
            label .. " native cooldown duration source"
        )
        assertContains(
            cooldown.tooltipBody,
            "spell colors configured in Auras",
            label .. " native spell-color location"
        )
        assertContains(
            cooldown.tooltipBody,
            "unlisted spells use gray",
            label .. " native unlisted spell fallback"
        )
        assertNotContains(
            cooldown.tooltipBody,
            "not applied by this older aura system",
            label .. " stale legacy cooldown explanation"
        )
    end

    local function assertLegacyPresentation(id, owner, runtimeKind)
        local label = owner .. " " .. id
        local info = newInfo(
            id,
            owner,
            nil,
            runtimeKind
        )

        spellPane.Load(info)
        assertEqual(
            mode.items[1].text,
            "Hide Listed Spells",
            label .. " inactive blacklist label"
        )
        assertEqual(
            mode.items[2].text,
            "Show Only Listed Spells",
            label .. " inactive whitelist label"
        )
        assertEqual(
            mode.enabled,
            false,
            label .. " inactive spell-list editability"
        )
        assertContains(
            tip.text,
            "older aura system",
            label .. " legacy implementation message"
        )
        assertContains(
            tip.text,
            "not used or editable here",
            label .. " inactive spell-list message"
        )
        assertNotContains(
            tip.text,
            "<MouseLeftClick>Edit",
            label .. " inactive edit hint"
        )
        assertNotContains(
            tip.text,
            "<MouseRightClick>Delete",
            label .. " inactive delete hint"
        )
        assertTrue(
            spellPane.listTopPadding < nativeTopPadding,
            label .. " inactive wrapped height shrinks"
        )
        assertEqual(
            spellParent._contentHeights[spellPane.index],
            tostring(spellPane.height),
            label .. " inactive scroll height"
        )

        arrangementPane.Load(info)
        assertEqual(
            maximum.label,
            "Max Displayed",
            label .. " legacy maximum label"
        )
        assertEqual(
            maximum.tooltipTitle,
            nil,
            label .. " stale native maximum tooltip"
        )
        assertEqual(
            maximum.tooltipBody,
            nil,
            label .. " stale native maximum warning"
        )

        cooldownPane.Load(info)
        assertContains(
            cooldown.tooltipBody,
            "opaque aura duration",
            label .. " legacy cooldown duration source"
        )
        assertContains(
            cooldown.tooltipBody,
            "saved for WoW 12.1",
            label .. " legacy saved spell colors"
        )
        assertContains(
            cooldown.tooltipBody,
            "not applied by this older aura system",
            label .. " legacy spell-color behavior"
        )
        assertNotContains(
            cooldown.tooltipBody,
            "spell colors configured in Auras",
            label .. " stale native cooldown explanation"
        )
    end

    for _, owner in ipairs(NATIVE_AURA_OWNERS) do
        assertNativePresentation("buffs", owner)
        assertNativePresentation("debuffs", owner)
    end
    for _, owner in ipairs(LEGACY_AURA_OWNERS) do
        assertLegacyPresentation("buffs", owner)
        assertLegacyPresentation("debuffs", owner)
    end
    -- An instantiated runtime is authoritative over the fallback integration
    -- map. This keeps the wording honest while branches are tested alone or
    -- if a later integration changes which aura factory owns a row.
    assertLegacyPresentation("buffs", "player", "legacy")
    assertLegacyPresentation("debuffs", "player", "legacy")
    assertNativePresentation("buffs", "target", "native")
    assertNativePresentation("debuffs", "target", "native")
end

local COOLDOWN_STYLES = {
    "none",
    "vertical",
    "block_vertical",
    "clock",
    "block_clock",
    "clock_with_leading_edge",
    "block_clock_with_leading_edge",
}

local function testRetailPresentation(hasNativeBackend)
    local version = hasNativeBackend and "12.1" or "12.0.7"
    local harness = makeHarness(true, hasNativeBackend)

    local colorPane =
        harness.builders.auraTypeColor(makeParent())
    local debuffs = newInfo("debuffs", "target")
    colorPane.Load(debuffs)
    local sourceColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Cast By Me"
    )
    local dispelColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    local debuffColor = findWidget(
        colorPane,
        "checkButton",
        "initialText",
        "Debuff Type"
    )
    assertEqual(colorPane.IsApplicable(debuffs), true,
        version .. " debuff color applicability")
    assertEqual(
        colorPane.IsApplicable(newInfo("buffs", "target")),
        false,
        version .. " buff color applicability"
    )
    assertEqual(sourceColor.shown, false,
        version .. " source-color visibility")
    assertEqual(dispelColor.shown, false,
        version .. " dispel-color visibility")
    assertEqual(debuffColor.shown, true,
        version .. " debuff-color visibility")
    assertEqual(debuffColor.enabled, true,
        version .. " debuff-color enabled state")

    local partitionPane =
        harness.builders.auraSubFrame(makeParent())
    partitionPane.Load(debuffs)
    local partition = findWidget(
        partitionPane,
        "checkButton",
        "initialText",
        "Enable Sub Frame"
    )
    local partitionFilter = findWidget(
        partitionPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertEqual(
        partition.text,
        "Separate Auras Not from Player, Pet, or Vehicle",
        version .. " target partition label"
    )
    assertContains(
        partition.tooltipBody,
        "For target units, this separates the complement of Blizzard's PLAYER category",
        version .. " target partition explanation"
    )
    assertEqual(partitionFilter.shown, false,
        version .. " target partition filter visibility")
    assertEqual(
        partitionFilter.selectedValue,
        "notCastByMe",
        version .. " target partition fixed filter"
    )
    assertEqual(partitionPane.IsApplicable(debuffs), true,
        version .. " target partition applicability")
    assertEqual(
        partitionPane.IsApplicable(newInfo("debuffs", "party")),
        false,
        version .. " non-target partition applicability"
    )

    harness:ClearLoads()
    partition.onCheck(false)
    assertEqual(debuffs.cfg.subFrame.enabled, false,
        version .. " target partition toggle")
    assertFanout(
        harness,
        debuffs,
        1,
        version .. " target partition callback"
    )

    local arrangementPane =
        harness.builders.auraArrangement(makeParent())
    if hasNativeBackend then
        debuffs = newInfo("debuffs", "focus")
    end
    arrangementPane.Load(debuffs)
    local maximum = findWidget(
        arrangementPane,
        "slider",
        "initialText",
        "Max Displayed"
    )
    if hasNativeBackend then
        assertEqual(maximum.label, "Max Per Aura Group",
            version .. " native maximum label")
        assertContains(
            maximum.tooltipBody,
            "each group",
            version .. " native maximum warning"
        )
        assertContains(
            maximum.tooltipBody,
            "more auras overall",
            version .. " native independent group totals"
        )
        assertContains(
            maximum.tooltipBody,
            "sort separately",
            version .. " native independent group sorting"
        )
    else
        assertEqual(maximum.label, "Max Displayed",
            version .. " legacy maximum label")
    end

    local cooldownPane =
        harness.builders.cooldownStyle(makeParent())
    cooldownPane.Load(debuffs)
    local cooldown = findWidget(
        cooldownPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertItemValues(
        cooldown,
        COOLDOWN_STYLES,
        version .. " cooldown styles"
    )
    assertEqual(
        cooldown.tooltipTitle,
        "Cooldown Style",
        version .. " cooldown tooltip title"
    )
    assertContains(
        cooldown.tooltipBody,
        "opaque aura duration",
        version .. " cooldown duration source"
    )
    if hasNativeBackend then
        assertContains(
            cooldown.tooltipBody,
            "spell colors configured in Auras",
            version .. " native spell-color location"
        )
        assertContains(
            cooldown.tooltipBody,
            "when WoW can match them safely",
            version .. " native spell-color safety"
        )
        assertContains(
            cooldown.tooltipBody,
            "unlisted spells use gray",
            version .. " native unlisted spell fallback"
        )
    else
        assertContains(
            cooldown.tooltipBody,
            "saved for WoW 12.1",
            version .. " saved spell-color compatibility"
        )
        assertContains(
            cooldown.tooltipBody,
            "not applied by this older aura system",
            version .. " legacy spell-color behavior"
        )
    end
    harness:ClearLoads()
    for _, style in ipairs(COOLDOWN_STYLES) do
        cooldown.onSelect(style)
        assertEqual(
            debuffs.cfg.cooldownStyle,
            style,
            version .. " cooldown callback " .. style
        )
    end
    assertFanout(
        harness,
        debuffs,
        #COOLDOWN_STYLES,
        version .. " cooldown callback fan-out"
    )
end

local function testPtr7FilterTokenCapabilities()
    local cases = {
        {
            label = "mismatched PTR 7",
            tokens = {
                Important = "IMPORTANT_OLD",
                Dispellable = "DISPELLABLE_OLD",
            },
            importantShown = false,
            anyDispellableShown = false,
        },
        {
            label = "IMPORTANT-only PTR",
            tokens = {
                Important = "IMPORTANT",
            },
            importantShown = true,
            anyDispellableShown = false,
        },
        {
            label = "DISPELLABLE-only PTR",
            tokens = {
                Dispellable = "DISPELLABLE",
            },
            importantShown = false,
            anyDispellableShown = true,
        },
    }

    for _, case in ipairs(cases) do
        local harness = makeHarness(
            true,
            true,
            case.tokens
        )
        local pane =
            harness.builders.auraBaseFilters(makeParent())
        pane.Load(newInfo("debuffs", "target"))

        local important = findWidget(
            pane,
            "checkButton",
            "initialText",
            "Important Enemy Buffs"
        )
        local anyDispellable = findWidget(
            pane,
            "checkButton",
            "initialText",
            "Dispellable"
        )
        assertEqual(
            important.shown,
            case.importantShown,
            case.label .. " IMPORTANT visibility"
        )
        assertEqual(
            anyDispellable.shown,
            case.anyDispellableShown,
            case.label .. " DISPELLABLE visibility"
        )
        assertEqual(
            important.text,
            "Important Enemy Buffs",
            case.label .. " IMPORTANT label"
        )
        assertEqual(
            anyDispellable.text,
            "Any Dispel Type",
            case.label .. " DISPELLABLE label"
        )
        assertEqual(
            pane.height < 142,
            true,
            case.label .. " compact layout"
        )
    end
end

local function testNonRetailSemantics()
    local harness = makeHarness(false, true)
    local parent = makeParent()
    local info = newInfo("buffs", "boss", {
        castByMe = true,
        castByOthers = false,
        castByUnit = true,
        castByNPC = false,
        isBossAura = true,
        dispellable = false,
    })

    local filterPane =
        harness.builders.auraBaseFilters(parent)
    filterPane.Load(info)
    local castByMe = findWidget(
        filterPane,
        "checkButton",
        "initialText",
        "Cast By Me"
    )
    local dispellable = findWidget(
        filterPane,
        "checkButton",
        "initialText",
        "Dispellable"
    )
    assertEqual(castByMe.text, "Cast By Me",
        "non-Retail source filter label")
    assertEqual(dispellable.shown, true,
        "non-Retail dispellable visibility")
    harness:ClearLoads()
    castByMe.onCheck(false)
    assertEqual(info.cfg.filters.castByMe, false,
        "non-Retail legacy filter callback")
    assertEqual(info.cfg.filters.player, nil,
        "non-Retail canonical materialization")
    assertFanout(
        harness,
        info,
        8,
        "non-Retail filter callback fan-out"
    )

    local spellPane =
        harness.builders.auraBlackListWhitelist(parent)
    spellPane.Load(info)
    local mode = findWidget(
        spellPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertEqual(mode.enabled, true,
        "non-Retail spell-list mode enabled state")
    assertEqual(mode.items[1].text, "Blacklist",
        "non-Retail blacklist label")
    assertEqual(mode.items[2].text, "Whitelist",
        "non-Retail whitelist label")
    for _, widget in ipairs(spellPane.widgets) do
        if widget.kind == "button" and widget.shown then
            assertEqual(widget.enabled, true,
                "non-Retail spell-list button enabled state")
        end
    end

    local colorPane =
        harness.builders.auraTypeColor(parent)
    colorPane.Load(info)
    assertEqual(colorPane.IsApplicable(info), true,
        "non-Retail buff color applicability")
    assertEqual(
        findWidget(
            colorPane,
            "checkButton",
            "initialText",
            "Cast By Me"
        ).shown,
        true,
        "non-Retail source-color visibility"
    )

    local partitionPane =
        harness.builders.auraSubFrame(parent)
    local target = newInfo("debuffs", "target")
    partitionPane.Load(target)
    assertEqual(
        findWidget(
            partitionPane,
            "dropdown",
            "kind",
            "dropdown"
        ).shown,
        true,
        "non-Retail partition filter visibility"
    )
    assertEqual(
        findWidget(
            partitionPane,
            "checkButton",
            "initialText",
            "Enable Sub Frame"
        ).text,
        "Enable Sub Frame",
        "non-Retail partition label"
    )

    local arrangementPane =
        harness.builders.auraArrangement(parent)
    arrangementPane.Load(target)
    assertEqual(
        findWidget(
            arrangementPane,
            "slider",
            "initialText",
            "Max Displayed"
        ).label,
        "Max Displayed",
        "non-Retail maximum label"
    )

    local cooldownPane =
        harness.builders.cooldownStyle(parent)
    cooldownPane.Load(target)
    local cooldown = findWidget(
        cooldownPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertItemValues(
        cooldown,
        COOLDOWN_STYLES,
        "non-Retail cooldown styles"
    )
    assertContains(
        cooldown.tooltipBody,
        "Block type",
        "non-Retail cooldown explanation"
    )
end

local function testDurationTextThresholdMode()
    local harness = makeHarness(true, true)
    local pane = harness.builders.durationText(makeParent())
    local info = newInfo("debuffs", "target")
    local colors = info.cfg.durationText.color

    pane.Load(info)

    local mode = findWidget(
        pane,
        "dropdown",
        "label",
        "Low-Time Color"
    )
    assertTrue(mode ~= nil, "duration threshold mode dropdown")
    assertItemValues(mode, {
        "off",
        "seconds",
        "percent",
    }, "duration threshold modes")
    assertContains(
        mode.tooltipBody,
        "seconds left or percent left",
        "duration threshold explanation"
    )
    assertEqual(
        colors.seconds.enabled,
        true,
        "legacy seconds threshold retained"
    )
    assertEqual(
        colors.percent.enabled,
        false,
        "legacy both-enabled threshold normalizes to seconds"
    )
    assertEqual(mode.selectedValue, "seconds", "normalized threshold mode")
    assertEqual(#harness.configLoads, 0, "threshold load has no fan-out")

    local thresholdPickers = findWidgets(
        pane,
        "colorPicker",
        "initialText",
        "Remaining Time <"
    )
    assertEqual(#thresholdPickers, 2, "threshold color picker count")
    local percentColorPicker = thresholdPickers[1]
    local secondsColorPicker = thresholdPickers[2]
    local percentDropdown = findWidget(
        pane,
        "dropdown",
        "width",
        50
    )
    local secondsEditBox = findWidget(
        pane,
        "editBox",
        "kind",
        "editBox"
    )
    local sec = findWidget(
        pane,
        "fontString",
        "initialText",
        "sec"
    )
    assertEqual(percentColorPicker.shown, false,
        "percent controls hidden for seconds mode")
    assertEqual(percentDropdown.shown, false,
        "percent value hidden for seconds mode")
    assertEqual(secondsColorPicker.shown, true,
        "seconds color shown for seconds mode")
    assertEqual(secondsEditBox.shown, true,
        "seconds value shown for seconds mode")
    assertEqual(sec.shown, true, "seconds unit shown for seconds mode")

    harness:ClearLoads()
    mode.onSelect("percent")
    assertEqual(colors.seconds.enabled, false,
        "percent mode disables seconds")
    assertEqual(colors.percent.enabled, true,
        "percent mode enabled")
    assertEqual(percentColorPicker.shown, true,
        "percent controls shown for percent mode")
    assertEqual(percentDropdown.shown, true,
        "percent value shown for percent mode")
    assertEqual(secondsColorPicker.shown, false,
        "seconds color hidden for percent mode")
    assertEqual(secondsEditBox.shown, false,
        "seconds value hidden for percent mode")
    assertFanout(harness, info, 1, "percent threshold mode")

    harness:ClearLoads()
    percentColorPicker.onChange(0.2, 0.3, 0.4)
    assertEqual(colors.percent.rgb[1], 0.2,
        "percent threshold red")
    assertEqual(colors.percent.rgb[2], 0.3,
        "percent threshold green")
    assertEqual(colors.percent.rgb[3], 0.4,
        "percent threshold blue")
    assertFanout(harness, info, 1, "percent threshold color")

    harness:ClearLoads()
    mode.onSelect("off")
    assertEqual(colors.seconds.enabled, false,
        "off mode disables seconds")
    assertEqual(colors.percent.enabled, false,
        "off mode disables percent")
    assertEqual(percentColorPicker.shown, false,
        "percent controls hidden for off mode")
    assertEqual(secondsColorPicker.shown, false,
        "seconds controls hidden for off mode")
    assertFanout(harness, info, 1, "off threshold mode")

    colors.seconds.value = 0
    harness:ClearLoads()
    mode.onSelect("seconds")
    assertEqual(colors.seconds.enabled, true,
        "seconds mode enabled")
    assertEqual(colors.percent.enabled, false,
        "seconds mode disables percent")
    assertEqual(colors.seconds.value, 5,
        "invalid dormant seconds threshold repaired")
    assertEqual(secondsEditBox.text, 5,
        "repaired seconds threshold displayed")
    assertFanout(harness, info, 1, "seconds threshold mode")

    harness:ClearLoads()
    secondsEditBox.onConfirm(0)
    assertEqual(colors.seconds.value, 5,
        "invalid seconds edit rejected")
    assertEqual(secondsEditBox.text, 5,
        "invalid seconds edit reverted")
    assertEqual(#harness.configLoads, 0,
        "invalid seconds edit has no fan-out")

    secondsEditBox.onConfirm(9)
    assertEqual(colors.seconds.value, 9,
        "valid seconds edit accepted")
    assertFanout(harness, info, 1, "seconds threshold value")
end

local function testPlainAuraControlLabels()
    local harness = makeHarness(true, true)
    assertContains(
        harness.AF.GetGradientText("probe"),
        "<gradient>",
        "gradient sentinel"
    )

    local stackPane = harness.builders.stackText(makeParent())
    assertTrue(
        findWidget(
            stackPane,
            "checkButton",
            "initialText",
            "Stack Text"
        ) ~= nil,
        "Stack Text uses a plain label"
    )

    local durationPane =
        harness.builders.durationText(makeParent())
    assertTrue(
        findWidget(
            durationPane,
            "checkButton",
            "initialText",
            "Duration Text"
        ) ~= nil,
        "Duration Text uses a plain label"
    )

    local info = newInfo("debuffs", "target")
    local colorPane =
        harness.builders.auraTypeColor(makeParent())
    colorPane.Load(info)
    local colorLabel = findWidget(
        colorPane,
        "fontString",
        "kind",
        "fontString"
    )
    assertContains(
        colorLabel.text,
        "Border Color",
        "Border Color label"
    )
    assertNotContains(
        colorLabel.text,
        "<gradient>",
        "Border Color uses a plain label"
    )

    local partitionPane =
        harness.builders.auraSubFrame(makeParent())
    partitionPane.Load(info)
    local partitionLabel = findWidget(
        partitionPane,
        "checkButton",
        "initialText",
        "Enable Sub Frame"
    )
    assertEqual(
        partitionLabel.text,
        "Separate Auras Not from Player, Pet, or Vehicle",
        "target partition uses a plain label"
    )

    local arrangementPane =
        harness.builders.auraArrangement(makeParent())
    local arrangement = findWidget(
        arrangementPane,
        "dropdown",
        "kind",
        "dropdown"
    )
    assertEqual(
        arrangement.label,
        "Arrangement",
        "aura Arrangement uses a plain label"
    )
end

for _, hasNativeBackend in ipairs({false, true}) do
    testRetailCanonicalFilters(hasNativeBackend)
    testRetailSpellLists(hasNativeBackend)
    testRetailPresentation(hasNativeBackend)
end
testRetailIndicatorAwareNativeWording()
testPtr7FilterTokenCapabilities()
testHealerSpellImporterGatingAndLayout()
testHealerSpellImporterUnavailableAndEmpty()
testHealerSpellImporterMergeAndIdempotence()
testNonRetailSemantics()
testDurationTextThresholdMode()
testPlainAuraControlLabels()

print("unit_frame_aura_filter_options_test.lua: ok")
