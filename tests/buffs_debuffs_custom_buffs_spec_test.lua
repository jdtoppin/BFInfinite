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

local function assertNil(value, message)
    assertEqual(value, nil, message)
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

local function tablesEqual(left, right)
    if left == right then return true end
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return false end
    for key, value in pairs(left) do
        if not tablesEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function assertTablesEqual(actual, expected, message)
    assertTrue(tablesEqual(actual, expected), message)
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local defaults = {
    buffs = {
        enabled = false,
        position = {"TOPRIGHT", -4, -4},
        width = 26,
        height = 26,
        orientation = "right_to_left_then_down",
        spacingX = 4,
        spacingY = 6,
        separateOwn = 0,
        sortMethod = "TIME",
        sortDirection = "-",
        maxWraps = 1,
        wrapAfter = 25,
        stack = {
            enabled = true,
            position = {"TOPRIGHT", "TOPRIGHT", 0, 3},
            font = {"Expressway", 11, "outline", false},
            color = {1, 1, 1, 1},
        },
        duration = {
            enabled = true,
            position = {"BOTTOM", "BOTTOM", 1, -3},
            font = {"Expressway", 10, "outline", false},
            color = {
                normal = {1, 1, 1, 1},
                percent = {
                    enabled = false,
                    value = 0.5,
                    rgb = {1, 1, 0, 1},
                },
                seconds = {
                    enabled = true,
                    value = 5,
                    rgb = {1, 0, 0, 1},
                },
            },
            showSecondsUnit = true,
        },
    },
}

local function NewHarness(options)
    options = options or {}
    local state = {
        registrations = {},
        capabilityReads = 0,
        defaultReads = 0,
        schemaReads = 0,
    }
    local schema = {
        HUD_EDIT_MODE_BUFF_FRAME_LABEL = "Buff Frame",
        AnchorUtil = {
            FlowLayoutAxis = {
                Horizontal = "HORIZONTAL",
                Vertical = "VERTICAL",
            },
            FlowDirection = {
                Left = "LEFT",
                Right = "RIGHT",
                Up = "UP",
                Down = "DOWN",
            },
        },
        AuraContainerSortMethod = {
            AuraInstanceIDOnly = "AURA_INSTANCE",
            NameOnly = "NAME",
            ExpirationOnly = "EXPIRATION",
        },
        AuraContainerSortDirection = {
            Normal = "NORMAL",
            Reverse = "REVERSE",
        },
        AuraContainerItemEnchantmentSlot = {
            MainHand = "MAIN_HAND",
            OffHand = "OFF_HAND",
            Ranged = "RANGED",
        },
        AuraContainerItemEnchantmentSortMethod = {
            Slot = "SLOT",
        },
        CustomAuraContainerAuraProcessingPolicy = {
            None = "NONE",
        },
        CustomAuraContainerItemEnchantmentPlacement = {
            BeforeAuraGroups = "BEFORE",
        },
    }
    local environment = setmetatable({}, {
        __index = function(_, key)
            if schema[key] ~= nil then
                state.schemaReads = state.schemaReads + 1
                if options.forbidSchemaReads then
                    error("version-gated client inspected native schema", 2)
                end
                return schema[key]
            end
            return _G[key]
        end,
    })
    environment._G = environment
    if not options.omitFramework then
        environment.AbstractFramework = {}
        if not options.omitVersion then
            environment.AbstractFramework.versionNum =
                options.version == nil and 42 or options.version
        end
    end

    local BD = {}
    if not options.omitCapability then
        function BD.HasCustomAuraContainerCapability()
            state.capabilityReads = state.capabilityReads + 1
            if options.forbidCapabilityReads then
                error("version-gated client inspected capability", 2)
            end
            return options.capability ~= false
        end
    end
    if not options.omitRegistration then
        function BD.RegisterCustomAuraContainerPane(which, compiler)
            state.registrations[#state.registrations + 1] = {
                which = which,
                compiler = compiler,
            }
        end
    end
    function BD.GetDefaults()
        state.defaultReads = state.defaultReads + 1
        if options.forbidDefaultReads then
            error("gated client inspected 12.1 defaults", 2)
        end
        return deepCopy(defaults)
    end

    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = L,
        modules = {
            BuffsDebuffs = BD,
        },
    }

    local chunk = assert(loadfile("Modules/BuffsDebuffs/CustomBuffs.lua"))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return {
        environment = environment,
        state = state,
    }
end

local function NewConfig()
    return deepCopy(defaults.buffs)
end

do
    local gatedCases = {
        {label = "r36", version = 36},
        {label = "r39", version = 39},
        {label = "string r40", version = "40"},
        {label = "NaN", version = 0 / 0},
        {label = "infinite", version = math.huge},
        {label = "missing version", omitVersion = true},
        {label = "missing framework", omitFramework = true},
    }
    for _, options in ipairs(gatedCases) do
        options.forbidCapabilityReads = true
        options.forbidDefaultReads = true
        options.forbidSchemaReads = true
        local gated = NewHarness(options)
        assertEqual(#gated.state.registrations, 0,
            options.label .. " registers no custom pane")
        assertEqual(gated.state.capabilityReads, 0,
            options.label .. " performs no capability read")
        assertEqual(gated.state.defaultReads, 0,
            options.label .. " performs no default read")
        assertEqual(gated.state.schemaReads, 0,
            options.label .. " performs no schema read")
    end

    for _, options in ipairs({
        {label = "false capability", version = 40, capability = false},
        {label = "missing capability", version = 40, omitCapability = true},
        {label = "missing registration", version = 40, omitRegistration = true},
    }) do
        options.forbidDefaultReads = true
        options.forbidSchemaReads = true
        local unavailable = NewHarness(options)
        assertEqual(#unavailable.state.registrations, 0,
            options.label .. " registers no custom pane")
        assertEqual(unavailable.state.defaultReads, 0,
            options.label .. " performs no default read")
        assertEqual(unavailable.state.schemaReads, 0,
            options.label .. " performs no schema read")
    end

    for _, version in ipairs({40, 42}) do
        local supported = NewHarness({version = version})
        assertEqual(#supported.state.registrations, 1,
            "r" .. version .. " registers Buffs")
        assertEqual(supported.state.capabilityReads, 1,
            "r" .. version .. " checks capability once")
        assertEqual(supported.state.defaultReads, 1,
            "r" .. version .. " reads defaults once")
        assertTrue(supported.state.schemaReads > 0,
            "r" .. version .. " reads native schema")
    end
end

local harness = NewHarness()
assertEqual(#harness.state.registrations, 1, "one pane registration")
assertEqual(
    harness.state.registrations[1].which,
    "buffs",
    "only Buffs registers"
)
local compile = harness.state.registrations[1].compiler

local orientationCases = {
    {
        key = "left_to_right_then_down",
        axis = "HORIZONTAL",
        anchor = "TOPLEFT",
        horizontal = "RIGHT",
        vertical = "DOWN",
    },
    {
        key = "left_to_right_then_up",
        axis = "HORIZONTAL",
        anchor = "BOTTOMLEFT",
        horizontal = "RIGHT",
        vertical = "UP",
    },
    {
        key = "right_to_left_then_down",
        axis = "HORIZONTAL",
        anchor = "TOPRIGHT",
        horizontal = "LEFT",
        vertical = "DOWN",
    },
    {
        key = "right_to_left_then_up",
        axis = "HORIZONTAL",
        anchor = "BOTTOMRIGHT",
        horizontal = "LEFT",
        vertical = "UP",
    },
    {
        key = "top_to_bottom_then_left",
        axis = "VERTICAL",
        anchor = "TOPRIGHT",
        horizontal = "LEFT",
        vertical = "DOWN",
    },
    {
        key = "top_to_bottom_then_right",
        axis = "VERTICAL",
        anchor = "TOPLEFT",
        horizontal = "RIGHT",
        vertical = "DOWN",
    },
    {
        key = "bottom_to_top_then_left",
        axis = "VERTICAL",
        anchor = "BOTTOMRIGHT",
        horizontal = "LEFT",
        vertical = "UP",
    },
    {
        key = "bottom_to_top_then_right",
        axis = "VERTICAL",
        anchor = "BOTTOMLEFT",
        horizontal = "RIGHT",
        vertical = "UP",
    },
}

for _, expected in ipairs(orientationCases) do
    local config = NewConfig()
    config.enabled = true
    config.orientation = expected.key
    config.width = 20
    config.height = 30
    config.spacingX = 2
    config.spacingY = 3
    config.wrapAfter = 4
    config.maxWraps = 2

    local descriptor = assert(compile(config))
    local flow = descriptor.flowLayout
    assertEqual(flow.axis, expected.axis, expected.key .. " axis")
    assertEqual(
        flow.anchorPoint,
        expected.anchor,
        expected.key .. " flow anchor"
    )
    assertEqual(
        flow.horizontalGrowthDirection,
        expected.horizontal,
        expected.key .. " horizontal growth"
    )
    assertEqual(
        flow.verticalGrowthDirection,
        expected.vertical,
        expected.key .. " vertical growth"
    )
    assertEqual(
        descriptor.containerPoint.point,
        expected.anchor,
        expected.key .. " container point"
    )
    assertEqual(
        descriptor.containerPoint.relativePoint,
        expected.anchor,
        expected.key .. " container relative point"
    )

    local horizontal = expected.axis == "HORIZONTAL"
    assertEqual(
        flow.maximumLineSize,
        horizontal and 86 or 129,
        expected.key .. " maximum line"
    )
    assertEqual(
        descriptor.holder.width,
        horizontal and 86 or 64,
        expected.key .. " holder width"
    )
    assertEqual(
        descriptor.holder.height,
        horizontal and 96 or 129,
        expected.key .. " holder height"
    )

    local groupLayout = descriptor.groups[1].layout
    assertEqual(
        groupLayout.elementSpacing,
        horizontal and 2 or 3,
        expected.key .. " primary spacing"
    )
    assertEqual(
        groupLayout.lineSpacing,
        horizontal and 3 or 2,
        expected.key .. " cross spacing"
    )
    assertEqual(groupLayout.groupSpacing, 0,
        expected.key .. " group spacing")
    assertEqual(
        groupLayout.groupLineSpacing,
        horizontal and 3 or 2,
        expected.key .. " group line spacing"
    )
    assertEqual(groupLayout.elementWidth, 20,
        expected.key .. " element width")
    assertEqual(groupLayout.elementHeight, 30,
        expected.key .. " element height")
    assertTablesEqual(
        descriptor.itemEnchantmentLayout,
        {
            elementSpacing = horizontal and 2 or 3,
            lineSpacing = horizontal and 3 or 2,
            groupSpacing = 0,
            groupLineSpacing = horizontal and 3 or 2,
            forceNewLine = false,
            elementWidth = 20,
            elementHeight = 30,
            placement = "BEFORE",
        },
        expected.key .. " enchantment layout"
    )
end

do
    local sortCases = {
        INDEX = "AURA_INSTANCE",
        NAME = "NAME",
        TIME = "EXPIRATION",
    }
    for saved, native in pairs(sortCases) do
        local config = NewConfig()
        config.sortMethod = saved
        assertEqual(
            assert(compile(config)).groups[1].sortMethod,
            native,
            saved .. " sort mapping"
        )
    end

    local config = NewConfig()
    config.sortDirection = "+"
    assertEqual(
        assert(compile(config)).groups[1].sortDirection,
        "NORMAL",
        "ascending sort mapping"
    )
    config.sortDirection = "-"
    assertEqual(
        assert(compile(config)).groups[1].sortDirection,
        "REVERSE",
        "descending sort mapping"
    )
end

do
    for _, value in ipairs({1, -1, "1"}) do
        local config = NewConfig()
        config.separateOwn = value
        local descriptor, diagnostic = compile(config)
        assertNil(descriptor, "Separate Own fails closed")
        assertEqual(
            diagnostic,
            "UNSUPPORTED_SEPARATE_OWN",
            "Separate Own diagnostic"
        )
    end
    local config = NewConfig()
    config.separateOwn = nil
    assertTrue(compile(config) ~= nil, "nil Separate Own is supported")
end

do
    local config = NewConfig()
    local profilePosition = config.position
    config.width = 20
    config.height = 30
    config.wrapAfter = 1
    config.maxWraps = 2
    config.duration.showSecondsUnit = false
    config.duration.color.percent.enabled = true
    config.duration.color.seconds.value = 99
    local savedConfig = deepCopy(config)

    local descriptor = assert(compile(config))
    assertTablesEqual(config, savedConfig,
        "compiler does not mutate saved Buffs configuration")
    assertEqual(descriptor.enabled, false,
        "shipped Buffs pane remains dormant by default")
    assertEqual(descriptor.positionSave, profilePosition,
        "mover save keeps profile identity")
    assertEqual(descriptor.moverText, "Buff Frame", "native mover label")
    assertEqual(descriptor.processing.policy, "NONE", "processing policy")
    assertNil(descriptor.processing.options, "None policy has no options")

    assertEqual(#descriptor.groups, 1, "one aura group")
    local group = descriptor.groups[1]
    assertEqual(group.key, "helpful", "group key")
    assertEqual(group.filterString, "HELPFUL", "group filter")
    assertEqual(group.maxFrameCount, 2, "aura-only cap")
    assertEqual(countKeys(group.candidateFilters), 0,
        "no candidate predicates")

    assertEqual(#descriptor.itemEnchantments, 2, "two enchantments")
    assertEqual(
        descriptor.itemEnchantments[1].slot,
        "MAIN_HAND",
        "main-hand enchantment"
    )
    assertEqual(
        descriptor.itemEnchantments[2].slot,
        "OFF_HAND",
        "off-hand enchantment"
    )
    assertTrue(
        descriptor.itemEnchantments[1].slot ~= "RANGED"
            and descriptor.itemEnchantments[2].slot ~= "RANGED",
        "no ranged enchantment"
    )
    assertEqual(
        descriptor.itemEnchantmentSort.method,
        "SLOT",
        "enchantment slot sort"
    )
    assertEqual(
        descriptor.itemEnchantmentSort.direction,
        "NORMAL",
        "enchantment normal direction"
    )
    assertEqual(
        descriptor.itemEnchantments[1].options.hidePermanent,
        false,
        "permanent main-hand enchantments remain visible"
    )
    assertEqual(
        descriptor.itemEnchantments[2].options.hidePermanent,
        false,
        "permanent off-hand enchantments remain visible"
    )
    assertEqual(
        descriptor.itemEnchantmentLayout.placement,
        "BEFORE",
        "item enchantments precede HELPFUL group"
    )

    local style = group.buttonStyle
    assertEqual(style.noBorder, false, "border enabled")
    assertEqual(style.width, 20, "button width")
    assertEqual(style.height, 30, "button height")
    assertEqual(style.iconInset, 1, "icon inset")
    assertEqual(style.cooldownStyle, "clock", "clock swipe")
    assertEqual(
        style.cancelAuraButtons,
        "RightButtonUp",
        "right-click cancellation"
    )
    assertEqual(style.tooltip.enabled, true, "tooltip mouse enabled")
    assertEqual(
        style.tooltip.anchorPoint,
        "ANCHOR_BOTTOMLEFT",
        "tooltip anchor"
    )
    assertEqual(
        style.tooltip.hideInCombat,
        false,
        "combat tooltips remain native-enabled"
    )
    assertNil(style.dispelColor, "buffs have no dispel overlay")
    assertNil(
        style.durationText.showSecondsUnit,
        "legacy seconds-unit field is omitted"
    )
    assertNil(
        style.durationText.color.percent,
        "legacy percent rule is omitted"
    )
    assertNil(
        style.durationText.color.seconds,
        "legacy seconds rule is omitted"
    )
    assertTablesEqual(
        style.durationText.color.threshold,
        {
            mode = "seconds",
            value = 99,
            rgb = {1, 0, 0, 1},
        },
        "both enabled rules project seconds first"
    )
    assertEqual(
        countKeys(style.durationText.color),
        2,
        "duration projects normal and one threshold only"
    )
    assertTrue(
        style.durationText.color.normal
            ~= config.duration.color.normal,
        "normal duration color is copied"
    )
    assertTrue(
        style.durationText.color.threshold.rgb
            ~= config.duration.color.seconds.rgb,
        "threshold duration color is copied"
    )
    assertEqual(
        descriptor.itemEnchantments[1].buttonStyle,
        style,
        "group and enchantment share initializer style"
    )
    assertEqual(
        descriptor.itemEnchantments[2].buttonStyle,
        style,
        "off-hand enchantment shares initializer style"
    )
    assertEqual(
        countKeys(descriptor.constructionKey),
        2,
        "construction key contains schema and style only"
    )
    assertEqual(
        descriptor.constructionKey.buttonStyle.durationText.color.threshold,
        style.durationText.color.threshold,
        "threshold belongs to initializer construction style"
    )
    assertNil(descriptor.constructionKey.orientation,
        "orientation remains live")
    assertNil(descriptor.constructionKey.position,
        "position remains live")
    assertNil(descriptor.constructionKey.wrapAfter,
        "wrapping remains live")

    -- Two aura slots plus two enchantments at one icon per line need four
    -- lines; this proves holder sizing does not mistake maxFrameCount for a
    -- strict global cap.
    assertEqual(descriptor.holder.width, 20,
        "single-column holder width")
    assertEqual(descriptor.holder.height, 138,
        "holder includes two enchantment lines")
end

do
    local defaultConfig = NewConfig()
    local defaultThreshold = assert(compile(defaultConfig))
        .groups[1].buttonStyle.durationText.color.threshold
    assertTablesEqual(defaultThreshold, {
        mode = "seconds",
        value = 5,
        rgb = {1, 0, 0, 1},
    }, "default seconds threshold")

    local percentConfig = NewConfig()
    percentConfig.duration.color.seconds.enabled = false
    percentConfig.duration.color.percent.enabled = true
    local percentThreshold = assert(compile(percentConfig))
        .groups[1].buttonStyle.durationText.color.threshold
    assertTablesEqual(percentThreshold, {
        mode = "percent",
        value = 0.5,
        rgb = {1, 1, 0, 1},
    }, "percent threshold when seconds is disabled")

    local offConfig = NewConfig()
    offConfig.duration.color.seconds.enabled = false
    offConfig.duration.color.percent.enabled = false
    assertNil(
        assert(compile(offConfig))
            .groups[1].buttonStyle.durationText.color.threshold,
        "both disabled rules emit no threshold"
    )

    local invalidSeconds = {
        0,
        -1,
        math.huge,
        -math.huge,
        0 / 0,
        {},
    }
    for index, invalid in ipairs(invalidSeconds) do
        local config = NewConfig()
        config.duration.color.seconds.value = invalid
        local threshold = assert(compile(config))
            .groups[1].buttonStyle.durationText.color.threshold
        assertEqual(threshold.mode, "seconds",
            "invalid seconds retains default mode " .. index)
        assertEqual(threshold.value, 5,
            "invalid seconds falls back to default " .. index)
    end

    local invalidPercents = {
        0,
        1,
        -1,
        math.huge,
        -math.huge,
        0 / 0,
        {},
    }
    for index, invalid in ipairs(invalidPercents) do
        local config = NewConfig()
        config.duration.color.seconds.enabled = false
        config.duration.color.percent.enabled = true
        config.duration.color.percent.value = invalid
        local threshold = assert(compile(config))
            .groups[1].buttonStyle.durationText.color.threshold
        assertEqual(threshold.mode, "percent",
            "invalid percent retains selected mode " .. index)
        assertEqual(threshold.value, 0.5,
            "invalid percent falls back to default " .. index)
    end

    local malformed = NewConfig()
    malformed.duration.color.seconds.enabled = "yes"
    malformed.duration.color.seconds.rgb = "red"
    malformed.duration.color.percent.enabled = true
    local malformedThreshold = assert(compile(malformed))
        .groups[1].buttonStyle.durationText.color.threshold
    assertTablesEqual(malformedThreshold, {
        mode = "seconds",
        value = 5,
        rgb = {1, 0, 0, 1},
    }, "malformed seconds rule falls back to defaults and keeps priority")

    local missing = NewConfig()
    missing.duration = nil
    local missingThreshold = assert(compile(missing))
        .groups[1].buttonStyle.durationText.color.threshold
    assertTablesEqual(missingThreshold, {
        mode = "seconds",
        value = 5,
        rgb = {1, 0, 0, 1},
    }, "missing duration config falls back to default threshold")
end

do
    local baselineConfig = NewConfig()
    local baseline = assert(compile(baselineConfig))

    local liveConfig = NewConfig()
    liveConfig.enabled = true
    liveConfig.orientation = "left_to_right_then_up"
    liveConfig.spacingX = 10
    liveConfig.spacingY = 11
    liveConfig.wrapAfter = 3
    liveConfig.maxWraps = 4
    liveConfig.sortMethod = "NAME"
    liveConfig.sortDirection = "+"
    liveConfig.position = {"BOTTOMLEFT", 45, 67}
    liveConfig.duration.showSecondsUnit = false
    liveConfig.duration.color.percent.enabled = true
    liveConfig.duration.color.percent.value = 0.25
    liveConfig.duration.color.percent.rgb = {0.2, 0.3, 0.4, 0.5}
    local live = assert(compile(liveConfig))
    assertTablesEqual(
        live.constructionKey,
        baseline.constructionKey,
        "live and inactive duration settings do not change construction key"
    )

    local constructionMutations = {
        {
            label = "button dimensions",
            apply = function(config) config.width = config.width + 1 end,
        },
        {
            label = "duration font",
            apply = function(config)
                config.duration.font[2] = config.duration.font[2] + 1
            end,
        },
        {
            label = "normal duration color",
            apply = function(config)
                config.duration.color.normal[1] = 0.25
            end,
        },
        {
            label = "active seconds value",
            apply = function(config)
                config.duration.color.seconds.value = 9
            end,
        },
        {
            label = "active seconds color",
            apply = function(config)
                config.duration.color.seconds.rgb[2] = 0.25
            end,
        },
        {
            label = "active seconds disabled",
            apply = function(config)
                config.duration.color.seconds.enabled = false
            end,
        },
    }
    for _, mutation in ipairs(constructionMutations) do
        local config = NewConfig()
        mutation.apply(config)
        assertTrue(
            not tablesEqual(
                assert(compile(config)).constructionKey,
                baseline.constructionKey
            ),
            mutation.label .. " changes construction key"
        )
    end

    local percentBaseConfig = NewConfig()
    percentBaseConfig.duration.color.seconds.enabled = false
    percentBaseConfig.duration.color.percent.enabled = true
    local percentBaseKey =
        assert(compile(percentBaseConfig)).constructionKey
    for _, mutation in ipairs({
        function(config) config.duration.color.percent.value = 0.25 end,
        function(config) config.duration.color.percent.rgb[3] = 0.25 end,
    }) do
        local config = deepCopy(percentBaseConfig)
        mutation(config)
        assertTrue(
            not tablesEqual(
                assert(compile(config)).constructionKey,
                percentBaseKey
            ),
            "active percent rule changes construction key"
        )
    end

    local inactiveSeconds = deepCopy(percentBaseConfig)
    inactiveSeconds.duration.color.seconds.value = 12
    inactiveSeconds.duration.color.seconds.rgb = {0.1, 0.2, 0.3, 0.4}
    assertTablesEqual(
        assert(compile(inactiveSeconds)).constructionKey,
        percentBaseKey,
        "inactive seconds edits do not change percent construction key"
    )

    local offBaseConfig = NewConfig()
    offBaseConfig.duration.color.seconds.enabled = false
    offBaseConfig.duration.color.percent.enabled = false
    local offBaseKey = assert(compile(offBaseConfig)).constructionKey
    local inactiveRules = deepCopy(offBaseConfig)
    inactiveRules.duration.showSecondsUnit = false
    inactiveRules.duration.color.seconds.value = 45
    inactiveRules.duration.color.seconds.rgb = {0.1, 0.2, 0.3, 0.4}
    inactiveRules.duration.color.percent.value = 0.25
    inactiveRules.duration.color.percent.rgb = {0.4, 0.3, 0.2, 0.1}
    assertTablesEqual(
        assert(compile(inactiveRules)).constructionKey,
        offBaseKey,
        "disabled rule and seconds-unit edits normalize out of key"
    )

    local modeConfig = NewConfig()
    modeConfig.duration.color.percent.enabled = true
    modeConfig.duration.color.seconds.value = 0.5
    modeConfig.duration.color.seconds.rgb =
        deepCopy(modeConfig.duration.color.percent.rgb)
    local secondsModeKey = assert(compile(modeConfig)).constructionKey
    modeConfig.duration.color.seconds.enabled = false
    local percentModeKey = assert(compile(modeConfig)).constructionKey
    assertTrue(not tablesEqual(secondsModeKey, percentModeKey),
        "threshold mode alone changes construction key")
end

do
    local malformed = NewConfig()
    malformed.width = {}
    malformed.height = -100
    malformed.spacingX = math.huge
    malformed.spacingY = -50
    malformed.wrapAfter = 0
    malformed.maxWraps = 500
    malformed.orientation = "not_an_orientation"
    malformed.sortMethod = "not_a_sort"
    malformed.sortDirection = "not_a_direction"
    malformed.position = {"INVALID", math.huge, {}}
    malformed.stack = {
        enabled = "yes",
        font = {false, math.huge, false, "yes"},
        position = {"INVALID", "INVALID", math.huge, {}},
        color = {2, -1, "bad", math.huge},
    }
    malformed.duration = {
        color = {
            normal = {2, -1, "bad", math.huge},
        },
    }

    local ok, descriptor = pcall(compile, malformed)
    assertTrue(ok, "malformed saved config normalizes without assertion")
    assertEqual(descriptor.groups[1].maxFrameCount, 50,
        "normalized integer cap")
    assertEqual(descriptor.groups[1].sortMethod, "EXPIRATION",
        "invalid sort falls back")
    assertEqual(descriptor.flowLayout.anchorPoint, "TOPRIGHT",
        "invalid orientation falls back")
    assertEqual(descriptor.groups[1].buttonStyle.width, 26,
        "invalid width falls back")
    assertEqual(descriptor.groups[1].buttonStyle.height, 10,
        "height clamps")
    assertEqual(descriptor.groups[1].layout.elementSpacing, 4,
        "infinite spacing falls back")
    assertEqual(descriptor.groups[1].layout.lineSpacing, -1,
        "negative spacing clamps")
    assertTablesEqual(
        descriptor.groups[1].buttonStyle.durationText.color.threshold,
        {
            mode = "seconds",
            value = 5,
            rgb = {1, 0, 0, 1},
        },
        "malformed duration falls back to shipped seconds threshold"
    )
end

do
    local file = assert(io.open(
        "Modules/BuffsDebuffs/CustomBuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()
    local forbidden = {
        "C_AuraContainerUtil",
        "C_UnitAuras",
        "C_Secrets",
        "C_TooltipInfo",
        "AuraData",
        "auraData",
        ".AuraButtons",
        "GetAuraButton",
        "GetAuraGroupFrame",
        "GetAuraGroupFrameCount",
        "EnumerateAura",
        "GetChildren",
        "GetAlpha",
        "GetMouseFocus",
        "IsMouseOver",
        "IsShown",
        "HookScript",
        ":SetScript",
        ":SetParent",
        "SecureAuraHeaderTemplate",
        "UpdateAllAuras",
    }
    for _, pattern in ipairs(forbidden) do
        assertNil(
            source:find(pattern, 1, true),
            "forbidden direct dependency: " .. pattern
        )
    end

    assertTrue(source:find("PublicAndPrivate", 1, true) ~= nil,
        "source documents the combined native source list")
    assertTrue(source:find("combined ordinary/private", 1, true) ~= nil,
        "source discloses inseparable authorized Buffs")
    assertNil(source:find("public Buffs replacement", 1, true),
        "source does not claim public-only Buffs")

    local versionGate = assert(source:find(
        "if type(afVersion) ~= \"number\"",
        1,
        true
    ))
    local capabilityGate = assert(source:find(
        "BD.HasCustomAuraContainerCapability() ~= true",
        versionGate,
        true
    ))
    local schemaRead = assert(source:find(
        "local flowAxis = _G.AnchorUtil.FlowLayoutAxis",
        capabilityGate,
        true
    ))
    local defaultRead = assert(source:find(
        "local defaults = BD.GetDefaults().buffs",
        schemaRead,
        true
    ))
    assertTrue(versionGate < capabilityGate,
        "AF r40 gate precedes capability read")
    assertTrue(capabilityGate < schemaRead,
        "capability gate precedes native schema reads")
    assertTrue(schemaRead < defaultRead,
        "gates precede defaults read")

    local loadFile = assert(io.open("Modules/BuffsDebuffs/Load.xml", "r"))
    local loadSource = loadFile:read("*a")
    loadFile:close()
    local orderedScripts = {
        "Defaults.lua",
        "BFIAuraButtonTemplate.xml",
        "NativeAuraFrames.lua",
        "BuffsDebuffs.lua",
        "CustomAuraContainer.lua",
        "CustomBuffs.lua",
    }
    local previous = 0
    for _, script in ipairs(orderedScripts) do
        local position = assert(loadSource:find(script, previous + 1, true))
        assertTrue(position > previous, "load order for " .. script)
        previous = position
    end
end

print("buffs/debuffs custom Buffs compiler tests passed")
