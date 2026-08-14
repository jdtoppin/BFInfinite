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
        message or ("expected text to contain " .. expected)
    )
end

local function makeWidget(kind, harness, label)
    local widget = {
        kind = kind,
        label = label,
        shown = true,
    }

    function widget:SetAfterValueChanged(callback)
        self.afterValueChanged = callback
    end

    function widget:SetColor(...)
        self.color = {...}
    end

    function widget:SetItems(items)
        self.items = items
    end

    function widget:SetJustifyH(value)
        self.justifyH = value
    end

    function widget:SetLabel(value)
        self.label = value
    end

    function widget:SetMinMaxValues(minimum, maximum)
        self.minimum = minimum
        self.maximum = maximum
    end

    function widget:SetOnConfirm(callback)
        self.onConfirm = callback
    end

    function widget:SetOnSelect(callback)
        self.onSelect = callback
    end

    function widget:SetSelectedValue(value)
        self.selectedValue = value
    end

    function widget:SetShown(value)
        self.shown = value
    end

    function widget:SetText(value)
        self.text = value
    end

    function widget:SetTooltip(title, body)
        self.tooltipTitle = title
        self.tooltipBody = body
    end

    function widget:SetValue(value)
        self.value = value
    end

    harness.widgets[#harness.widgets + 1] = widget
    return widget
end

local function findWidget(harness, kind, label)
    for _, widget in ipairs(harness.widgets) do
        if widget.kind == kind and widget.label == label then
            return widget
        end
    end
end

local function hasItem(dropdown, value, text)
    for _, item in ipairs(dropdown.items or {}) do
        if item.value == value and (text == nil or item.text == text) then
            return true
        end
    end
    return false
end

local function makeHarness()
    local harness = {
        builders = {},
        fires = {},
        widgets = {},
    }
    local UF = {
        MAX_CHILD_BUFF_DISPLAY_INITIAL_RESERVATIONS = 40,
    }
    local AF = {}
    local F = {}
    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })

    function F.RegisterUnitFrameOptionBuilder(name, builder)
        harness.builders[name] = builder
    end

    function AF.CreateBorderedFrame(_, name, _, height)
        local pane = {
            height = height,
            name = name,
        }

        function pane:SetHeight(value)
            self.height = value
        end

        return pane
    end

    function AF.ClearPoints()
    end

    function AF.CreateColorPicker(_, label)
        return makeWidget("colorPicker", harness, label)
    end

    function AF.CreateDropdown()
        return makeWidget("dropdown", harness)
    end

    function AF.CreateFontString()
        return makeWidget("fontString", harness)
    end

    function AF.CreateSlider(_, label)
        return makeWidget("slider", harness, label)
    end

    function AF.FillColorTable(color, r, g, b, a)
        color[1] = r
        color[2] = g
        color[3] = b
        color[4] = a
    end

    function AF.Fire(...)
        harness.fires[#harness.fires + 1] = {...}
    end

    function AF.SetPoint()
    end

    function UF.GetActiveBuffDisplayReservationPlan(collection)
        return collection.reserved or {}, collection.overflow or {},
            collection.metrics
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
        error = error,
        ipairs = ipairs,
        math = math,
        select = select,
        setmetatable = setmetatable,
        string = string,
        table = table,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected Buff Display options global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local chunk, loadError =
        loadfile("Options/UnitFrameBuffDisplays.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.UF = UF
    return harness
end

local function newInfo()
    local config = {
        durationBar = {
            backgroundColor = {0, 0, 0, 0.75},
            color = {1, 1, 1, 1},
            gap = 1,
            height = 3,
            inset = 0,
        },
        frameHighlight = {},
        height = 4,
        enabled = true,
        mode = "whitelist",
        presentation = "bar",
        sortMode = "spell_list_priority",
        whitelist = {17, 139, 774},
        width = 18,
    }
    local collection = {
        displays = {
            custom_1 = config,
        },
        metrics = {
            buttonCapacityLimit = 40,
            buttonCapacityUsed = 30,
            buttonCapacityCosts = {
                custom_1 = 30,
            },
            capacityCosts = {
                custom_1 = 20,
            },
            initialReservationLimit = 40,
            initialReservations = 10,
            reservationCosts = {
                custom_1 = 10,
            },
        },
        overflow = {},
        reserved = {config},
    }
    config.id = "custom_1"
    return {
        cfg = config,
        displayID = "custom_1",
        id = "buffs",
        owner = "party",
        runtimeCfg = collection,
    }
end

local function testPresentationAndPriorityOptions()
    local harness = makeHarness()
    local pane = assert(harness.builders.buffDisplayPresentation)({})
    local presentation = findWidget(harness, "dropdown", "Presentation")
    local sortMethod = findWidget(harness, "dropdown", "Sort Method")
    assertTrue(presentation, "presentation dropdown")
    assertTrue(sortMethod, "sort dropdown")
    assertTrue(hasItem(presentation, "bar", "Bar"),
        "standalone Bar choice")
    assertTrue(hasItem(
        sortMethod,
        "blizzard",
        "Blizzard Sort (Efficient)"
    ), "efficient sort choice")
    assertTrue(hasItem(
        sortMethod,
        "spell_list_priority",
        "Spell List Priority (Higher Resource Use)"
    ), "priority sort choice")

    local info = newInfo()
    pane.Load(info)
    assertEqual(pane.height, 238, "whitelist pane height")
    assertEqual(presentation.selectedValue, "bar", "Bar loaded")
    assertEqual(sortMethod.shown, true, "whitelist sort shown")
    assertEqual(sortMethod.selectedValue, "spell_list_priority",
        "priority sort loaded")
    assertContains(sortMethod.tooltipBody, "top-to-bottom order",
        "priority tooltip explains list order")
    assertContains(sortMethod.tooltipBody, "first positions",
        "priority tooltip explains compaction")

    info.cfg.presentation = "icons"
    info.cfg.width = 12
    info.cfg.height = 12
    info.cfg.durationBar.inset = 3
    presentation.onSelect("bar")
    assertEqual(info.cfg.presentation, "bar", "Bar selection saved")
    assertEqual(info.cfg.width, 18, "Bar receives a thin default width")
    assertEqual(info.cfg.height, 4, "icon-like height becomes thin Bar")
    assertEqual(info.cfg.durationBar.inset, 1,
        "Bar transition clamps a latent underbar inset")
    info.cfg.width = 24
    info.cfg.height = 6
    presentation.onSelect("icons")
    assertEqual(info.cfg.width, 24,
        "leaving Bar preserves an appropriate width")
    assertEqual(info.cfg.height, 12,
        "leaving Bar restores an icon-appropriate height")
    info.cfg.presentation = "bar"
    info.cfg.height = 14
    presentation.onSelect("icon_duration_bar")
    assertEqual(info.cfg.height, 14,
        "leaving Bar preserves an already appropriate height")
    info.cfg.presentation = "bar"

    local capacity
    for _, widget in ipairs(harness.widgets) do
        if widget.kind == "fontString"
            and type(widget.text) == "string"
            and widget.text:find("Priority list", 1, true)
        then
            capacity = widget
            break
        end
    end
    assertTrue(capacity, "priority capacity readout")
    assertContains(capacity.text, "Priority list: 3 spells",
        "priority list length is visible")
    assertContains(capacity.text, "This display: 30 managed aura buttons",
        "priority cost uses the complete whitelist")
    assertContains(capacity.text, "Enabled child displays: 30 of 40",
        "combined enabled-child capacity prefers core button metrics")
    assertContains(capacity.text, "tooltips are disabled",
        "priority tooltip live-QA warning")

    harness.fires = {}
    sortMethod.onSelect("blizzard")
    assertEqual(info.cfg.sortMode, "blizzard",
        "efficient sort saved")
    assertContains(sortMethod.tooltipBody, "whitelist order is ignored",
        "efficient sort tooltip")
    assertEqual(harness.fires[1][1], "BFI_UpdateModule",
        "sort applies the child display")
    assertEqual(harness.fires[2][1], "BFI_RefreshOptions",
        "sort refreshes priority-dependent panes")

    sortMethod.onSelect("spell_list_priority")
    assertEqual(info.cfg.sortMode, "spell_list_priority",
        "priority sort saved")

    info.cfg.mode = "blacklist"
    pane.Load(info)
    assertEqual(sortMethod.shown, false,
        "sort hidden outside whitelist mode")
    assertEqual(pane.height, 112, "non-whitelist compact pane")
    assertEqual(capacity.shown, true,
        "capacity remains visible outside whitelist mode")
    assertContains(capacity.text, "managed aura buttons",
        "category display keeps a concrete capacity readout")
    assertEqual(info.cfg.sortMode, "spell_list_priority",
        "hidden priority preference is preserved")
end

local function testCapacityFallbackAndOverflow()
    local harness = makeHarness()
    local pane = assert(harness.builders.buffDisplayPresentation)({})
    local info = newInfo()
    info.cfg.whitelist[4] = 53563
    info.cfg.whitelist[5] = 194384
    info.runtimeCfg.overflow = {info.cfg}
    info.runtimeCfg.metrics.buttonCapacityCosts.custom_1 = 50
    info.runtimeCfg.metrics.reservationCosts.custom_1 = 50
    pane.Load(info)

    local overflowText
    for _, widget in ipairs(harness.widgets) do
        if type(widget.text) == "string"
            and widget.text:find("Over Budget", 1, true)
        then
            overflowText = widget.text
            break
        end
    end
    assertContains(overflowText, "Priority list: 5 spells",
        "over-budget priority list count")
    assertContains(overflowText, "This display: 50 managed aura buttons",
        "over-budget priority cost")

    harness.UF.GetActiveBuffDisplayReservationPlan = nil
    info.cfg.sortMode = "blizzard"
    info.cfg.enabled = false
    pane.Load(info)
    local fallbackText
    for _, widget in ipairs(harness.widgets) do
        if type(widget.text) == "string"
            and widget.text:find("would use approximately", 1, true)
        then
            fallbackText = widget.text
            break
        end
    end
    assertContains(fallbackText, "approximately 10 managed aura buttons",
        "graceful reservation fallback")
end

local function testCoreConfigurationErrorIsActionable()
    local harness = makeHarness()
    harness.UF.GetBuffDisplayReservationMetrics = function()
        return {
            buttonCapacityCost = 41,
            buttonCapacityLimit = 40,
            buttonCapacityExceeded = true,
            errorCode =
                "SPELL_LIST_PRIORITY_REQUIRES_UNIQUE_WHITELIST",
        }
    end
    local pane = assert(harness.builders.buffDisplayPresentation)({})
    local info = newInfo()
    info.cfg.whitelist[3] = info.cfg.whitelist[1]
    pane.Load(info)

    local errorText
    for _, widget in ipairs(harness.widgets) do
        if type(widget.text) == "string"
            and widget.text:find("Configuration Error", 1, true)
        then
            errorText = widget.text
            break
        end
    end
    assertContains(errorText, "Remove duplicate entries",
        "core priority error has corrective guidance")
    assertContains(errorText, "This display: 41 managed aura buttons",
        "preferred button-capacity metrics are retained")
    assertContains(errorText, "Enabled child displays: 30 of 40",
        "combined capacity remains distinct from display cost")
    assertTrue(
        not errorText:find("cannot be activated", 1, true),
        "configuration error is not replaced by generic over-budget text"
    )
end

local function testStandaloneBarStyleControls()
    local harness = makeHarness()
    local pane = assert(
        harness.builders.buffDisplayPresentationStyle
    )({})
    local info = newInfo()
    pane.Load(info)

    local color = findWidget(
        harness,
        "colorPicker",
        "Duration Bar Color"
    )
    local background = findWidget(
        harness,
        "colorPicker",
        "Duration Bar Background"
    )
    local height = findWidget(
        harness,
        "slider",
        "Duration Bar Height"
    )
    local gap = findWidget(
        harness,
        "slider",
        "Duration Bar Gap"
    )
    local inset = findWidget(harness, "slider", "Display Inset")
    assertTrue(color and background and height and gap and inset,
        "duration widgets")
    assertEqual(color.shown, true, "Bar fill color shown")
    assertEqual(background.shown, true, "Bar background shown")
    assertEqual(inset.shown, true, "Bar inset shown")
    assertEqual(height.shown, false,
        "under-icon bar height hidden for standalone Bar")
    assertEqual(gap.shown, false,
        "icon gap hidden for standalone Bar")
    assertEqual(findWidget(harness, "slider", "Bar Width"), nil,
        "Bar size is not duplicated in style controls")
    assertEqual(findWidget(harness, "slider", "Bar Height"), nil,
        "Bar height is owned by Arrangement")

    inset.afterValueChanged(1)
    assertEqual(info.cfg.durationBar.inset, 1, "Bar inset saved")
    color.onConfirm(0.2, 0.3, 0.4, 0.5)
    assertEqual(info.cfg.durationBar.color[1], 0.2,
        "Bar fill color saved")

    info.cfg.presentation = "icon_duration_bar"
    info.cfg.height = 12
    pane.Load(info)
    assertEqual(height.shown, true,
        "underbar height shown for Icon + Duration Bar")
    assertEqual(gap.shown, true,
        "underbar gap shown for Icon + Duration Bar")

    info.cfg.presentation = "frame_highlight"
    pane.Load(info)
    assertEqual(color.shown, false,
        "bar colors hidden for Frame Highlight")
    local highlight = findWidget(
        harness,
        "colorPicker",
        "Highlight Color"
    )
    assertEqual(highlight.shown, true,
        "highlight controls restored")
end

testPresentationAndPriorityOptions()
testCapacityFallbackAndOverflow()
testCoreConfigurationErrorIsActionable()
testStandaloneBarStyleControls()

print("unit_frame_buff_display_presentation_options_test.lua: ok")
