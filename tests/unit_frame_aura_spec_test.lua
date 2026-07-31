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

local function assertDeepEqual(actual, expected, message, seen)
    message = message or "tables differ"
    if type(actual) ~= type(expected) then
        error(("%s: type mismatch (%s ~= %s)"):format(
            message,
            type(actual),
            type(expected)
        ), 2)
    end
    if type(actual) ~= "table" then
        assertEqual(actual, expected, message)
        return
    end

    seen = seen or {}
    if seen[actual] == expected then return end
    seen[actual] = expected

    for key, expectedValue in pairs(expected) do
        assertDeepEqual(
            actual[key],
            expectedValue,
            ("%s.%s"):format(message, tostring(key)),
            seen
        )
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(("%s: unexpected key %s"):format(message, tostring(key)), 2)
        end
    end
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local FLOW_AXIS = {
    Horizontal = 101,
    Vertical = 102,
}
local FLOW_DIRECTION = {
    Left = 201,
    Right = 202,
    Up = 203,
    Down = 204,
}
local SORT_METHOD = {
    Default = 301,
}
local SORT_DIRECTION = {
    Normal = 401,
}
local PROCESSING_POLICY = {
    None = 501,
}

local function makeHarness(withNativeSchema)
    local forbiddenCalls = {}
    local function forbidden(name)
        return function()
            forbiddenCalls[#forbiddenCalls + 1] = name
            error("forbidden aura-spec dependency: " .. name, 2)
        end
    end
    local function forbiddenTable(name)
        return setmetatable({}, {
            __index = function(_, key)
                forbiddenCalls[#forbiddenCalls + 1] = name .. "." .. tostring(key)
                error("forbidden aura-spec dependency: " .. name, 2)
            end,
        })
    end

    local UF = {}
    local AF = {
        Copy = copy,
    }
    setmetatable(AF, {
        __index = function(_, key)
            error("unexpected AbstractFramework dependency: " .. tostring(key), 2)
        end,
    })

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        funcs = {
            isValueNonSecret = forbidden("F.isValueNonSecret"),
        },
        modules = {
            UnitFrames = UF,
        },
    }

    local environment = {
        assert = assert,
        error = error,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        rawget = rawget,
        select = select,
        string = string,
        table = table,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        AbstractFramework = AF,
        GetCVar = function()
            return "0"
        end,
        CreateFrame = forbidden("CreateFrame"),
        InCombatLockdown = forbidden("InCombatLockdown"),
        C_Timer = forbiddenTable("C_Timer"),
        UnitCanAssist = forbidden("UnitCanAssist"),
        UnitCanAttack = forbidden("UnitCanAttack"),
        UnitExists = forbidden("UnitExists"),
        UnitIsVisible = forbidden("UnitIsVisible"),
        C_UnitAuras = forbiddenTable("C_UnitAuras"),
        C_Secrets = forbiddenTable("C_Secrets"),
        AuraData = forbiddenTable("AuraData"),
        AuraUtil = {
            AuraFilters = withNativeSchema
                and {
                    Important = "IMPORTANT",
                    Dispellable = "DISPELLABLE",
                }
                or {},
        },
    }
    environment["is" .. "secretvalue"] = forbidden("secret-value API")
    environment._G = environment

    if withNativeSchema then
        environment.AnchorUtil = {
            FlowLayoutAxis = FLOW_AXIS,
            FlowDirection = FLOW_DIRECTION,
        }
        environment.AuraContainerSortMethod = SORT_METHOD
        environment.AuraContainerSortDirection = SORT_DIRECTION
        environment.CustomAuraContainerAuraProcessingPolicy = PROCESSING_POLICY
    end

    local absentNativeGlobals = {
        AnchorUtil = true,
        AuraContainerSortMethod = true,
        AuraContainerSortDirection = true,
        CustomAuraContainerAuraProcessingPolicy = true,
    }
    setmetatable(environment, {
        __index = function(_, key)
            if not withNativeSchema and absentNativeGlobals[key] then
                return nil
            end
            error("unexpected aura-spec global: " .. tostring(key), 2)
        end,
    })

    for _, path in ipairs({
        "Utils.lua",
        "Modules/UnitFrames/AuraPolicy.lua",
        "Modules/UnitFrames/AuraSpec.lua",
    }) do
        local chunk, loadError = loadfile(path)
        assertTrue(chunk, loadError)
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end

    return {
        BFI = BFI,
        UF = UF,
        forbiddenCalls = forbiddenCalls,
    }
end

local function baseConfig()
    return {
        enabled = true,
        position = {"TOPRIGHT", "BOTTOMRIGHT", 5, -6},
        anchorTo = "root",
        frameLevel = 7,
        orientation = "left_to_right",
        cooldownStyle = "clock_with_leading_edge",
        width = 10,
        height = 6,
        spacingX = 2,
        spacingY = 3,
        numPerLine = 4,
        numTotal = 4,
        tooltip = {
            enabled = true,
            anchorTo = "self",
            position = {"TOPLEFT", "BOTTOMRIGHT", 1, -1},
        },
        durationText = {
            enabled = true,
            font = {"BFI", 10, "outline", false},
            position = {"TOP", "TOP", 1, 1},
            color = {
                normal = {0.1, 0.2, 0.3, 0.4},
                percent = {
                    enabled = true,
                    value = 0.5,
                    rgb = {0.5, 0.6, 0.7, 0.8},
                },
                seconds = {
                    enabled = true,
                    value = 5,
                    rgb = {0.9, 0.8, 0.7, 0.6},
                },
            },
        },
        stackText = {
            enabled = true,
            font = {"Visitor", 9, "monochrome_outline", false},
            position = {"BOTTOMRIGHT", "BOTTOMRIGHT", 3, -1},
            color = {0.9, 0.8, 0.7, 0.6},
        },
        filters = {
            castByMe = true,
            castByOthers = false,
            castByUnit = false,
            castByNPC = false,
            isBossAura = true,
            dispellable = false,
        },
        mode = "blacklist",
        blacklist = {},
        whitelist = {},
        auraTypeColor = {
            castByMe = false,
            dispellable = true,
            debuffType = true,
        },
    }
end

local harness = makeHarness(true)
assertEqual(
    type(harness.UF.CompileNativeAuraSpec),
    "function",
    "aura spec compiler export"
)

local function compile(unit, baseFilter, config)
    local descriptor, errorCode = harness.UF.CompileNativeAuraSpec(
        unit,
        baseFilter,
        config
    )
    assertTrue(descriptor, errorCode)
    assertEqual(errorCode, nil, "successful compile error")
    return descriptor
end

local function assertCompileError(unit, baseFilter, config, expectedError, message)
    local descriptor, errorCode = harness.UF.CompileNativeAuraSpec(
        unit,
        baseFilter,
        config
    )
    assertEqual(descriptor, nil, (message or expectedError) .. " descriptor")
    assertEqual(errorCode, expectedError, (message or expectedError) .. " code")
end

local function expectedDurationText()
    return {
        enabled = true,
        font = {"BFI", 10, "outline", false},
        position = {"TOP", "TOP", 1, 1},
        color = {
            normal = {0.1, 0.2, 0.3, 0.4},
        },
    }
end

local function expectedStackText()
    return {
        enabled = true,
        font = {"Visitor", 9, "monochrome_outline", false},
        position = {"BOTTOMRIGHT", "BOTTOMRIGHT", 3, -1},
        color = {0.9, 0.8, 0.7, 0.6},
    }
end

local function expectedButtonStyle(dispelColor)
    return {
        noBorder = true,
        width = 10,
        height = 6,
        desaturated = false,
        cooldownStyle = "clock_with_leading_edge",
        durationText = expectedDurationText(),
        stackText = expectedStackText(),
        dispelColor = dispelColor,
        tooltip = {
            enabled = true,
            anchorPoint = "ANCHOR_BOTTOMRIGHT",
            offsetX = 1,
            offsetY = -1,
            hideInCombat = false,
        },
    }
end

local function assertGroup(
    group,
    key,
    filterString,
    layoutIndex,
    elementSpacing,
    lineSpacing,
    dispelColor,
    message
)
    message = message or key
    assertEqual(group.key, key, message .. " key")
    assertEqual(group.filterString, filterString, message .. " filter")
    assertEqual(group.maxFrameCount, 4, message .. " maximum")
    assertEqual(group.candidateFilters, nil, message .. " candidates")
    assertEqual(group.sortMethod, SORT_METHOD.Default, message .. " sort")
    assertEqual(
        group.sortDirection,
        SORT_DIRECTION.Normal,
        message .. " direction"
    )
    assertDeepEqual(group.layout, {
        elementSpacing = elementSpacing,
        lineSpacing = lineSpacing,
        groupSpacing = 0,
        groupLineSpacing = lineSpacing,
        forceNewLine = false,
        elementWidth = 10,
        elementHeight = 6,
        layoutIndex = layoutIndex,
    }, message .. " layout")
    assertDeepEqual(
        group.buttonStyle,
        expectedButtonStyle(dispelColor),
        message .. " style"
    )
end

local function testLegacyLoadAndSchemaGate()
    local legacy = makeHarness(false)
    assertEqual(
        type(legacy.UF.CompileNativeAuraSpec),
        "function",
        "12.0.7 compiler export"
    )

    local descriptor, errorCode = legacy.UF.CompileNativeAuraSpec(
        "target",
        "HARMFUL",
        baseConfig()
    )
    assertEqual(descriptor, nil, "12.0.7 descriptor")
    assertEqual(
        errorCode,
        "NATIVE_AURA_SCHEMA_UNAVAILABLE",
        "12.0.7 schema error"
    )
    assertEqual(#legacy.forbiddenCalls, 0, "12.0.7 forbidden calls")
end

local function testCompleteSpecContract()
    local descriptor = compile("target", "HARMFUL", baseConfig())
    local complete = descriptor.completeSpec
    local tuning = descriptor.tuningSpec

    assertEqual(descriptor.empty, false, "descriptor empty")
    assertEqual(descriptor.migrationReady, true, "descriptor readiness")
    assertEqual(complete.unit, "target", "complete unit")
    assertEqual(complete.enabled, true, "complete enabled")
    assertEqual(complete.shown, false, "complete shown")
    assertDeepEqual(complete.holder, {
        width = 46,
        height = 15,
    }, "complete holder")
    assertDeepEqual(complete.containerPoint, {
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 0,
        y = 0,
    }, "complete container point")
    assertDeepEqual(complete.flowLayout, {
        axis = FLOW_AXIS.Horizontal,
        anchorPoint = "TOPLEFT",
        horizontalGrowthDirection = FLOW_DIRECTION.Right,
        verticalGrowthDirection = FLOW_DIRECTION.Down,
        paddingLeft = 0,
        paddingRight = 0,
        paddingTop = 0,
        paddingBottom = 0,
        maximumLineSize = 46,
    }, "complete flow")
    assertDeepEqual(complete.processing, {
        policy = PROCESSING_POLICY.None,
    }, "complete processing")
    assertEqual(#complete.groups, 2, "complete group count")
    assertEqual(#complete.slots, 0, "complete slot count")

    assertGroup(
        complete.groups[1],
        "player",
        "HARMFUL|PLAYER",
        1,
        2,
        3,
        true,
        "complete player"
    )
    assertGroup(
        complete.groups[2],
        "raidInCombat",
        "HARMFUL|RAID_IN_COMBAT|!PLAYER",
        2,
        2,
        3,
        true,
        "complete raid"
    )

    assertEqual(tuning.unit, nil, "tuning unit")
    assertEqual(tuning.enabled, nil, "tuning enabled")
    assertEqual(tuning.shown, nil, "tuning shown")
    assertDeepEqual(tuning.holder, complete.holder, "tuning holder")
    assertDeepEqual(
        tuning.containerPoint,
        complete.containerPoint,
        "tuning point"
    )
    assertDeepEqual(tuning.flowLayout, complete.flowLayout, "tuning flow")
    assertDeepEqual(tuning.processing, complete.processing, "tuning processing")
    assertEqual(#tuning.groups, 2, "tuning group count")
    assertEqual(#tuning.slots, 0, "tuning slot count")
    for index, group in ipairs(tuning.groups) do
        assertEqual(group.buttonStyle, nil, "tuning style " .. index)
        local expected = copy(complete.groups[index])
        expected.buttonStyle = nil
        assertDeepEqual(group, expected, "tuning group " .. index)
    end

    assertDeepEqual(descriptor.placement, {
        position = {"TOPRIGHT", "BOTTOMRIGHT", 5, -6},
        anchorTo = "root",
        frameLevel = 7,
    }, "placement")
    assertDeepEqual(descriptor.visibility, {
        requiresVisible = false,
        requiresAssist = false,
        spellIDFilterRequiresPublicAssist = false,
        spellIDFilterRequiresPublicNonAssist = false,
    }, "visibility")
    assertEqual(descriptor.partition, nil, "partition")

    assertDeepEqual(descriptor.metrics, {
        groupCount = 2,
        legacyMaxFrameCount = 4,
        nativeVisibleCapacity = 8,
        nativeBatchSize = 10,
        initialRestrictedButtonCount = 20,
        freshContainerRestrictedButtonCountCeiling = 20,
    }, "base metrics")
    assertDeepEqual(descriptor.diagnostics, {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
    }, "base diagnostics")
    assertDeepEqual(descriptor.degradations, {
        perGroupLimit = true,
        perGroupSort = true,
        privateAuraSourceUnseparable = true,
        bossAuraUsesCuratedRaidInCombat = true,
        legacySourceFilterUsesSuperset = false,
        legacyDispellableUsesRaidPlayerDispellable = false,
        unsupportedPtr7CategoryUsesBaseFilter = false,
        defaultSortPriority = true,
        fixedHolderExtent = true,
        spellIDListsIgnored = false,
        spellIDFiltersRestrictedByUnitReaction = false,
        auraTypeColorSourceRulesIgnored = true,
        tooltipPlacementApproximate = false,
        partitionDeferred = false,
    }, "base degradations")

    assertEqual(#descriptor.constructionKey.groups, 2, "construction groups")
    assertEqual(#descriptor.constructionKey.slots, 0, "construction slots")
    for index, constructionGroup in ipairs(descriptor.constructionKey.groups) do
        assertEqual(
            constructionGroup.key,
            complete.groups[index].key,
            "construction key " .. index
        )
        assertDeepEqual(
            constructionGroup.buttonStyle,
            complete.groups[index].buttonStyle,
            "construction style " .. index
        )
    end
end

local function testOrientationAndGeometry()
    local cases = {
        {
            orientation = "left_to_right",
            anchor = "BOTTOM",
            axis = FLOW_AXIS.Horizontal,
            horizontal = FLOW_DIRECTION.Right,
            vertical = FLOW_DIRECTION.Up,
            point = "BOTTOMLEFT",
            maximum = 46,
            width = 46,
            height = 15,
        },
        {
            orientation = "left_to_right",
            anchor = "CENTER",
            axis = FLOW_AXIS.Horizontal,
            horizontal = FLOW_DIRECTION.Right,
            vertical = FLOW_DIRECTION.Down,
            point = "TOPLEFT",
            maximum = 46,
            width = 46,
            height = 15,
        },
        {
            orientation = "right_to_left",
            anchor = "BOTTOMLEFT",
            axis = FLOW_AXIS.Horizontal,
            horizontal = FLOW_DIRECTION.Left,
            vertical = FLOW_DIRECTION.Up,
            point = "BOTTOMRIGHT",
            maximum = 46,
            width = 46,
            height = 15,
        },
        {
            orientation = "right_to_left",
            anchor = "TOPLEFT",
            axis = FLOW_AXIS.Horizontal,
            horizontal = FLOW_DIRECTION.Left,
            vertical = FLOW_DIRECTION.Down,
            point = "TOPRIGHT",
            maximum = 46,
            width = 46,
            height = 15,
        },
        {
            orientation = "top_to_bottom",
            anchor = "RIGHT",
            axis = FLOW_AXIS.Vertical,
            horizontal = FLOW_DIRECTION.Left,
            vertical = FLOW_DIRECTION.Down,
            point = "TOPRIGHT",
            maximum = 33,
            width = 22,
            height = 33,
        },
        {
            orientation = "top_to_bottom",
            anchor = "BOTTOMLEFT",
            axis = FLOW_AXIS.Vertical,
            horizontal = FLOW_DIRECTION.Right,
            vertical = FLOW_DIRECTION.Down,
            point = "TOPLEFT",
            maximum = 33,
            width = 22,
            height = 33,
        },
        {
            orientation = "bottom_to_top",
            anchor = "BOTTOMRIGHT",
            axis = FLOW_AXIS.Vertical,
            horizontal = FLOW_DIRECTION.Left,
            vertical = FLOW_DIRECTION.Up,
            point = "BOTTOMRIGHT",
            maximum = 33,
            width = 22,
            height = 33,
        },
        {
            orientation = "bottom_to_top",
            anchor = "TOP",
            axis = FLOW_AXIS.Vertical,
            horizontal = FLOW_DIRECTION.Right,
            vertical = FLOW_DIRECTION.Up,
            point = "BOTTOMLEFT",
            maximum = 33,
            width = 22,
            height = 33,
        },
    }

    for index, case in ipairs(cases) do
        local config = baseConfig()
        config.orientation = case.orientation
        config.position[1] = case.anchor
        local descriptor = compile("target", "HARMFUL", config)
        local complete = descriptor.completeSpec
        local flow = complete.flowLayout
        local message = "orientation case " .. index

        assertEqual(flow.axis, case.axis, message .. " axis")
        assertEqual(
            flow.horizontalGrowthDirection,
            case.horizontal,
            message .. " horizontal"
        )
        assertEqual(
            flow.verticalGrowthDirection,
            case.vertical,
            message .. " vertical"
        )
        assertEqual(flow.anchorPoint, case.point, message .. " flow point")
        assertEqual(
            flow.maximumLineSize,
            case.maximum,
            message .. " maximum"
        )
        assertDeepEqual(complete.containerPoint, {
            point = case.point,
            relativePoint = case.point,
            x = 0,
            y = 0,
        }, message .. " container point")
        assertDeepEqual(complete.holder, {
            width = case.width,
            height = case.height,
        }, message .. " holder")

        local firstLayout = complete.groups[1].layout
        if case.axis == FLOW_AXIS.Horizontal then
            assertEqual(firstLayout.elementSpacing, 2, message .. " spacing")
            assertEqual(firstLayout.lineSpacing, 3, message .. " line spacing")
        else
            assertEqual(firstLayout.elementSpacing, 3, message .. " spacing")
            assertEqual(firstLayout.lineSpacing, 2, message .. " line spacing")
        end
        assertEqual(firstLayout.groupSpacing, 0, message .. " group spacing")
    end

    local clamped = baseConfig()
    clamped.numPerLine = 5
    clamped.numTotal = 3
    local clampedDescriptor = compile("target", "HARMFUL", clamped)
    assertEqual(
        clampedDescriptor.completeSpec.flowLayout.maximumLineSize,
        34,
        "clamped maximum"
    )
    assertDeepEqual(clampedDescriptor.completeSpec.holder, {
        width = 34,
        height = 15,
    }, "clamped holder")

    local negative = baseConfig()
    negative.spacingX = -1
    negative.numPerLine = 3
    negative.numTotal = 3
    negative.filters.isBossAura = false
    local negativeDescriptor = compile("target", "HARMFUL", negative)
    assertEqual(
        negativeDescriptor.completeSpec.flowLayout.maximumLineSize,
        28,
        "negative-spacing maximum"
    )
    assertDeepEqual(negativeDescriptor.completeSpec.holder, {
        width = 28,
        height = 6,
    }, "negative-spacing holder")

    -- d3915c78's flow cursor already retains elementSpacing after the prior
    -- group's last element. A non-zero groupSpacing would double the 2px gap
    -- and can wrap the next group early.
    local boundary = compile("target", "HARMFUL", baseConfig())
    for index, group in ipairs(boundary.completeSpec.groups) do
        assertEqual(group.layout.elementSpacing, 2, "boundary spacing " .. index)
        assertEqual(group.layout.groupSpacing, 0, "boundary group gap " .. index)
        assertEqual(
            group.layout.groupLineSpacing,
            3,
            "boundary group line gap " .. index
        )
    end
end

local function testStyleProjection()
    local cooldownStyles = {
        "none",
        "vertical",
        "block_vertical",
        "clock",
        "block_clock",
        "clock_with_leading_edge",
        "block_clock_with_leading_edge",
    }
    for _, cooldownStyle in ipairs(cooldownStyles) do
        local config = baseConfig()
        config.cooldownStyle = cooldownStyle
        config.filters.isBossAura = false
        local descriptor = compile("target", "HARMFUL", config)
        assertEqual(
            descriptor.completeSpec.groups[1].buttonStyle.cooldownStyle,
            cooldownStyle,
            "cooldown style " .. cooldownStyle
        )
    end

    local disabledText = baseConfig()
    disabledText.filters.isBossAura = false
    disabledText.durationText.enabled = false
    disabledText.stackText.enabled = false
    local disabledDescriptor = compile("target", "HARMFUL", disabledText)
    local disabledStyle = disabledDescriptor.completeSpec.groups[1].buttonStyle
    assertEqual(disabledStyle.durationText.enabled, false, "duration disabled")
    assertEqual(disabledStyle.stackText.enabled, false, "stack disabled")

    assertEqual(
        disabledStyle.durationText.color.percent,
        nil,
        "duration percent color omitted"
    )
    assertEqual(
        disabledStyle.durationText.color.seconds,
        nil,
        "duration seconds color omitted"
    )

    local helpful = baseConfig()
    helpful.filters.isBossAura = false
    local helpfulDescriptor = compile("target", "HELPFUL", helpful)
    assertEqual(
        helpfulDescriptor.completeSpec.groups[1].buttonStyle.dispelColor,
        false,
        "helpful dispel color"
    )

    local harmfulNoColor = baseConfig()
    harmfulNoColor.filters.isBossAura = false
    harmfulNoColor.auraTypeColor.debuffType = false
    local noColorDescriptor = compile("target", "HARMFUL", harmfulNoColor)
    assertEqual(
        noColorDescriptor.completeSpec.groups[1].buttonStyle.dispelColor,
        false,
        "disabled harmful dispel color"
    )

    harmfulNoColor.auraTypeColor.debuffType = true
    harmfulNoColor.auraTypeColor.castByMe = true
    harmfulNoColor.auraTypeColor.dispellable = false
    local colorDescriptor = compile("target", "HARMFUL", harmfulNoColor)
    assertEqual(
        colorDescriptor.completeSpec.groups[1].buttonStyle.dispelColor,
        true,
        "harmful dispel color"
    )

    local noSourceRules = baseConfig()
    noSourceRules.filters.isBossAura = false
    noSourceRules.auraTypeColor.castByMe = false
    noSourceRules.auraTypeColor.dispellable = false
    local noSourceDescriptor = compile("target", "HARMFUL", noSourceRules)
    assertDeepEqual(noSourceDescriptor.diagnostics, {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
    }, "no source-color diagnostics")
    assertEqual(
        noSourceDescriptor.degradations.auraTypeColorSourceRulesIgnored,
        false,
        "no source-color degradation"
    )

    noSourceRules.auraTypeColor = nil
    local noAuraColorDescriptor = compile("target", "HARMFUL", noSourceRules)
    assertEqual(
        noAuraColorDescriptor.completeSpec.groups[1].buttonStyle.dispelColor,
        false,
        "missing aura color config"
    )

    local fractional = baseConfig()
    fractional.filters.isBossAura = false
    fractional.width = 10.5
    fractional.height = 6.25
    fractional.spacingX = 1.5
    fractional.spacingY = -0.25
    local fractionalDescriptor = compile("target", "HARMFUL", fractional)
    local fractionalStyle =
        fractionalDescriptor.completeSpec.groups[1].buttonStyle
    assertEqual(fractionalStyle.width, 10.5, "fractional width")
    assertEqual(fractionalStyle.height, 6.25, "fractional height")
end

local function testTooltipProjection()
    local mappings = {
        {{"TOPLEFT", "BOTTOMRIGHT"}, "ANCHOR_BOTTOMRIGHT"},
        {{"TOPRIGHT", "BOTTOMLEFT"}, "ANCHOR_BOTTOMLEFT"},
        {{"BOTTOMLEFT", "TOPRIGHT"}, "ANCHOR_TOPRIGHT"},
        {{"BOTTOMRIGHT", "TOPLEFT"}, "ANCHOR_TOPLEFT"},
        {{"TOP", "BOTTOM"}, "ANCHOR_BOTTOM"},
        {{"BOTTOM", "TOP"}, "ANCHOR_TOP"},
        {{"LEFT", "RIGHT"}, "ANCHOR_RIGHT"},
        {{"RIGHT", "LEFT"}, "ANCHOR_LEFT"},
    }

    for index, mapping in ipairs(mappings) do
        local config = baseConfig()
        config.filters.isBossAura = false
        config.tooltip.position = {
            mapping[1][1],
            mapping[1][2],
            13,
            -17,
        }
        local descriptor = compile("target", "HARMFUL", config)
        local tooltip =
            descriptor.completeSpec.groups[1].buttonStyle.tooltip
        assertDeepEqual(tooltip, {
            enabled = true,
            anchorPoint = mapping[2],
            offsetX = 13,
            offsetY = -17,
            hideInCombat = false,
        }, "tooltip mapping " .. index)
    end

    for _, anchorTo in ipairs({"root", "self_adaptive", "parent", "default"}) do
        local config = baseConfig()
        config.filters.isBossAura = false
        config.tooltip.anchorTo = anchorTo
        local descriptor = compile("target", "HARMFUL", config)
        local tooltip =
            descriptor.completeSpec.groups[1].buttonStyle.tooltip
        assertEqual(tooltip.enabled, true, anchorTo .. " tooltip enabled")
        assertEqual(tooltip.anchorPoint, nil, anchorTo .. " tooltip anchor")
        assertEqual(tooltip.offsetX, nil, anchorTo .. " tooltip x")
        assertEqual(tooltip.offsetY, nil, anchorTo .. " tooltip y")
        assertEqual(
            tooltip.hideInCombat,
            false,
            anchorTo .. " tooltip combat"
        )
        assertDeepEqual(descriptor.diagnostics, {
            "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
            "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
            "TOOLTIP_PLACEMENT_APPROXIMATED",
        }, anchorTo .. " approximation diagnostics")
        assertEqual(
            descriptor.degradations.tooltipPlacementApproximate,
            true,
            anchorTo .. " approximation degradation"
        )
    end

    local disabled = baseConfig()
    disabled.filters.isBossAura = false
    disabled.tooltip.enabled = false
    local disabledDescriptor = compile("target", "HARMFUL", disabled)
    assertEqual(
        disabledDescriptor.completeSpec.groups[1].buttonStyle.tooltip.enabled,
        false,
        "disabled tooltip"
    )

    disabled.tooltip.anchorTo = "default"
    local disabledDefault = compile("target", "HARMFUL", disabled)
    assertEqual(
        disabledDefault.degradations.tooltipPlacementApproximate,
        false,
        "disabled default tooltip approximation"
    )
    assertDeepEqual(
        disabledDefault.completeSpec.groups[1].buttonStyle.tooltip,
        {
            enabled = false,
            hideInCombat = false,
        },
        "disabled tooltip effective style"
    )

    disabled.tooltip.anchorTo = "dormant-invalid-mode"
    disabled.tooltip.position = nil
    local disabledDormant = compile("target", "HARMFUL", disabled)
    assertDeepEqual(
        disabledDormant.constructionKey,
        disabledDefault.constructionKey,
        "disabled tooltip ignores dormant placement"
    )

    local approximateSelf = baseConfig()
    approximateSelf.filters.isBossAura = false
    approximateSelf.tooltip.position = {"TOPLEFT", "TOPLEFT", 7, -9}
    local approximateSelfDescriptor =
        compile("target", "HARMFUL", approximateSelf)
    local approximateSelfTooltip =
        approximateSelfDescriptor.completeSpec.groups[1].buttonStyle.tooltip
    assertDeepEqual(approximateSelfTooltip, {
        enabled = true,
        anchorPoint = "ANCHOR_TOPLEFT",
        offsetX = 7,
        offsetY = -9,
        hideInCombat = false,
    }, "approximate self tooltip")
    assertEqual(
        approximateSelfDescriptor.degradations.tooltipPlacementApproximate,
        true,
        "approximate self degradation"
    )

    local centerSelf = baseConfig()
    centerSelf.filters.isBossAura = false
    centerSelf.tooltip.position = {"CENTER", "CENTER", 7, -9}
    local centerSelfDescriptor = compile("target", "HARMFUL", centerSelf)
    assertDeepEqual(
        centerSelfDescriptor.completeSpec.groups[1].buttonStyle.tooltip,
        {
            enabled = true,
            hideInCombat = false,
        },
        "center self fallback"
    )
    assertEqual(
        centerSelfDescriptor.degradations.tooltipPlacementApproximate,
        true,
        "center self degradation"
    )

    local invalid = baseConfig()
    invalid.tooltip.anchorTo = "mystery"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_TOOLTIP",
        "unknown tooltip mode"
    )
end

local function testEmptyPolicies()
    local config = baseConfig()
    config.filters = {}
    local empty = compile("target", "HARMFUL", config)
    assertEqual(empty.empty, true, "empty state")
    assertEqual(empty.completeSpec, nil, "empty complete spec")
    assertEqual(empty.tuningSpec, nil, "empty tuning spec")
    assertEqual(empty.migrationReady, false, "empty readiness")
    assertDeepEqual(empty.metrics, {
        groupCount = 0,
        legacyMaxFrameCount = 0,
        nativeVisibleCapacity = 0,
        nativeBatchSize = 0,
        initialRestrictedButtonCount = 0,
        freshContainerRestrictedButtonCountCeiling = 0,
    }, "empty metrics")
    assertDeepEqual(empty.diagnostics, {}, "empty diagnostics")
    assertDeepEqual(empty.degradations, {
        perGroupLimit = false,
        perGroupSort = false,
        privateAuraSourceUnseparable = false,
        bossAuraUsesCuratedRaidInCombat = false,
        legacySourceFilterUsesSuperset = false,
        legacyDispellableUsesRaidPlayerDispellable = false,
        unsupportedPtr7CategoryUsesBaseFilter = false,
        defaultSortPriority = false,
        fixedHolderExtent = false,
        spellIDListsIgnored = false,
        spellIDFiltersRestrictedByUnitReaction = false,
        auraTypeColorSourceRulesIgnored = false,
        tooltipPlacementApproximate = false,
        partitionDeferred = false,
    }, "empty degradations")
    assertEqual(#empty.constructionKey.groups, 0, "empty construction groups")
    assertEqual(#empty.constructionKey.slots, 0, "empty construction slots")

    config.subFrame = {
        enabled = true,
        desaturated = true,
        filter = "notCastByMe",
        width = 8,
        height = 7,
    }
    local emptyPartition = compile("target", "HARMFUL", config)
    assertEqual(
        emptyPartition.degradations.partitionDeferred,
        false,
        "empty partition degradation"
    )
    assertEqual(
        emptyPartition.migrationReady,
        false,
        "empty partition readiness"
    )
    assertDeepEqual(emptyPartition.diagnostics, {}, "empty partition diagnostics")

    config.filters = {
        castByOthers = true,
        castByUnit = true,
    }
    local widened = compile("target", "HARMFUL", config)
    assertEqual(widened.empty, false, "widened harmful state")
    assertEqual(
        widened.completeSpec.groups[1].key,
        "all",
        "cast-by-unit all group"
    )
    assertEqual(
        widened.completeSpec.groups[1].filterString,
        "HARMFUL",
        "cast-by-unit base filter"
    )
    assertEqual(
        widened.degradations.legacySourceFilterUsesSuperset,
        true,
        "cast-by-unit widening metadata"
    )

    config.filters = {
        castByOthers = true,
    }
    local notPlayer = compile("target", "HARMFUL", config)
    assertEqual(notPlayer.empty, false, "source-only harmful state")
    assertEqual(
        notPlayer.completeSpec.groups[1].key,
        "notPlayer",
        "source-only not-player group"
    )
    assertEqual(
        notPlayer.completeSpec.groups[1].filterString,
        "HARMFUL|!PLAYER",
        "source-only not-player filter"
    )
    assertDeepEqual(notPlayer.visibility, {
        requiresVisible = true,
        requiresAssist = false,
        spellIDFilterRequiresPublicAssist = false,
        spellIDFilterRequiresPublicNonAssist = false,
    }, "source-only visibility")

    config = baseConfig()
    config.enabled = false
    config.filters.isBossAura = false
    local disabled = compile("target", "HARMFUL", config)
    assertEqual(disabled.empty, false, "disabled nonempty state")
    assertEqual(disabled.completeSpec.enabled, false, "disabled spec enabled")
    assertEqual(disabled.completeSpec.shown, false, "disabled spec shown")
end

local function testPartitionMetadata()
    local config = baseConfig()
    config.subFrame = {
        enabled = true,
        desaturated = true,
        filter = "notCastByMe",
        width = 8,
        height = 7,
    }
    local descriptor = compile("target", "HARMFUL", config)
    assertEqual(descriptor.migrationReady, false, "partition readiness")
    assertTrue(type(descriptor.partition) == "table", "partition metadata")
    assertEqual(
        descriptor.partition.filter,
        "notCastByMe",
        "partition filter"
    )
    assertEqual(
        descriptor.partition.desaturated,
        true,
        "partition desaturated"
    )
    assertEqual(descriptor.partition.width, 8, "partition width")
    assertEqual(descriptor.partition.height, 7, "partition height")
    assertDeepEqual(descriptor.diagnostics, {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
        "TARGET_PARTITION_DEFERRED",
    }, "partition diagnostics")
    assertEqual(
        descriptor.degradations.partitionDeferred,
        true,
        "partition degradation"
    )

    config.subFrame.enabled = false
    local disabled = compile("target", "HARMFUL", config)
    assertEqual(disabled.migrationReady, true, "disabled partition readiness")
end

local function testCapacityMetrics()
    local single = baseConfig()
    single.numPerLine = 2
    single.numTotal = 1
    single.filters.isBossAura = false
    local singleDescriptor = compile("target", "HARMFUL", single)
    assertDeepEqual(singleDescriptor.metrics, {
        groupCount = 1,
        legacyMaxFrameCount = 1,
        nativeVisibleCapacity = 1,
        nativeBatchSize = 10,
        initialRestrictedButtonCount = 10,
        freshContainerRestrictedButtonCountCeiling = 10,
    }, "single-group metrics")
    assertEqual(
        singleDescriptor.degradations.perGroupLimit,
        false,
        "single-group limit degradation"
    )
    assertEqual(
        singleDescriptor.degradations.perGroupSort,
        false,
        "single-group sort degradation"
    )

    local legacyAll = baseConfig()
    legacyAll.numPerLine = 11
    legacyAll.numTotal = 22
    legacyAll.filters = {
        castByMe = true,
        castByOthers = true,
        castByUnit = true,
        castByNPC = true,
        isBossAura = true,
        dispellable = true,
    }
    local allDescriptor =
        compile("target", "HELPFUL", legacyAll)
    assertEqual(
        allDescriptor.completeSpec.groups[1].filterString,
        "HELPFUL",
        "legacy all base filter"
    )
    assertDeepEqual(allDescriptor.metrics, {
        groupCount = 1,
        legacyMaxFrameCount = 22,
        nativeVisibleCapacity = 22,
        nativeBatchSize = 10,
        initialRestrictedButtonCount = 10,
        freshContainerRestrictedButtonCountCeiling = 30,
    }, "legacy all metrics")
    assertEqual(
        allDescriptor.degradations.perGroupLimit,
        false,
        "legacy all limit degradation"
    )
    assertEqual(
        allDescriptor.degradations.perGroupSort,
        false,
        "legacy all sort degradation"
    )
    assertDeepEqual(allDescriptor.visibility, {
        requiresVisible = false,
        requiresAssist = false,
        spellIDFilterRequiresPublicAssist = false,
        spellIDFilterRequiresPublicNonAssist = false,
    }, "legacy all visibility")

    local canonicalAll = copy(legacyAll)
    canonicalAll.filters = {
        all = true,
    }
    local canonicalAllDescriptor =
        compile("target", "HELPFUL", canonicalAll)
    assertDeepEqual(
        canonicalAllDescriptor.completeSpec.groups,
        allDescriptor.completeSpec.groups,
        "legacy and canonical all groups"
    )
    assertDeepEqual(
        canonicalAllDescriptor.constructionKey,
        allDescriptor.constructionKey,
        "legacy and canonical all construction keys"
    )

    local seven = baseConfig()
    seven.numPerLine = 11
    seven.numTotal = 22
    seven.filters = {
        player = true,
        notPlayer = false,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
        important = true,
        anyDispellable = true,
    }
    local sevenDescriptor =
        compile("target", "HELPFUL", seven)
    assertDeepEqual(sevenDescriptor.metrics, {
        groupCount = 7,
        legacyMaxFrameCount = 22,
        nativeVisibleCapacity = 154,
        nativeBatchSize = 10,
        initialRestrictedButtonCount = 70,
        freshContainerRestrictedButtonCountCeiling = 210,
    }, "seven-category metrics")
    assertEqual(
        sevenDescriptor.degradations.perGroupLimit,
        true,
        "seven-category limit degradation"
    )
    assertEqual(
        sevenDescriptor.degradations.perGroupSort,
        true,
        "seven-category sort degradation"
    )
    assertEqual(
        sevenDescriptor.completeSpec.groups[6].key,
        "important",
        "important spec group order"
    )
    assertEqual(
        sevenDescriptor.completeSpec.groups[6].filterString,
        "HELPFUL|IMPORTANT|!PLAYER|!RAID_IN_COMBAT"
            .. "|!RAID_PLAYER_DISPELLABLE|!BIG_DEFENSIVE"
            .. "|!EXTERNAL_DEFENSIVE",
        "important spec filter"
    )
    assertEqual(
        sevenDescriptor.completeSpec.groups[7].key,
        "anyDispellable",
        "any-dispellable spec group order"
    )
    assertEqual(
        sevenDescriptor.completeSpec.groups[7].filterString,
        "HELPFUL|DISPELLABLE|!PLAYER|!RAID_IN_COMBAT"
            .. "|!RAID_PLAYER_DISPELLABLE|!BIG_DEFENSIVE"
            .. "|!EXTERNAL_DEFENSIVE|!IMPORTANT",
        "any-dispellable spec filter"
    )
    assertEqual(
        sevenDescriptor.visibility.spellIDFilterRequiresPublicAssist,
        false,
        "category-only helpful policy has no spell-ID assist gate"
    )
    assertEqual(
        sevenDescriptor.visibility.spellIDFilterRequiresPublicNonAssist,
        false,
        "category-only helpful policy has no spell-ID non-assist gate"
    )

    local splitDefensive = baseConfig()
    splitDefensive.filters = {
        player = false,
        raidInCombat = false,
        raidPlayerDispellable = false,
        bigDefensive = true,
        externalDefensive = false,
    }
    local splitDescriptor =
        compile("target", "HELPFUL", splitDefensive)
    assertEqual(
        #splitDescriptor.completeSpec.groups,
        1,
        "split defensive group count"
    )
    assertEqual(
        splitDescriptor.completeSpec.groups[1].filterString,
        "HELPFUL|BIG_DEFENSIVE",
        "split defensive filter"
    )
    assertDeepEqual(splitDescriptor.metrics, {
        groupCount = 1,
        legacyMaxFrameCount = 4,
        nativeVisibleCapacity = 4,
        nativeBatchSize = 10,
        initialRestrictedButtonCount = 10,
        freshContainerRestrictedButtonCountCeiling = 10,
    }, "split defensive metrics")

    local spellFilter = baseConfig()
    spellFilter.blacklist = {12345}
    spellFilter.whitelist = {67890}
    local spellDescriptor = compile("target", "HARMFUL", spellFilter)
    assertDeepEqual(spellDescriptor.diagnostics, {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "SPELL_ID_FILTERS_RESTRICTED_BY_UNIT_REACTION",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
    }, "spell-filter diagnostics")
    assertEqual(
        spellDescriptor.degradations.spellIDListsIgnored,
        false,
        "spell IDs are not ignored"
    )
    assertEqual(
        spellDescriptor.degradations
            .spellIDFiltersRestrictedByUnitReaction,
        true,
        "spell-filter reaction degradation"
    )
    assertEqual(
        spellDescriptor.visibility.spellIDFilterRequiresPublicAssist,
        false,
        "harmful spell filter does not require assist"
    )
    assertEqual(
        spellDescriptor.visibility.spellIDFilterRequiresPublicNonAssist,
        true,
        "harmful spell filter requires a public non-assist reaction"
    )
end

local function testSpellIDCandidateFilters()
    local whitelist = baseConfig()
    whitelist.mode = "whitelist"
    whitelist.whitelist = {101, 202}
    whitelist.blacklist = "inactive blacklist is ignored"
    local whitelistSnapshot = copy(whitelist)
    local whitelistDescriptor = compile("target", "HELPFUL", whitelist)
    local completeGroups = whitelistDescriptor.completeSpec.groups
    local tuningGroups = whitelistDescriptor.tuningSpec.groups

    assertEqual(#completeGroups, 2, "whitelist complete group count")
    assertEqual(#tuningGroups, 2, "whitelist tuning group count")
    local projectedGroups = {
        completeGroups[1],
        completeGroups[2],
        tuningGroups[1],
        tuningGroups[2],
    }
    for index, group in ipairs(projectedGroups) do
        assertDeepEqual(group.candidateFilters, {
            includeSpellIDs = {
                [101] = true,
                [202] = true,
            },
        }, "whitelist candidate map " .. index)
        for earlier = 1, index - 1 do
            assertTrue(
                group.candidateFilters
                    ~= projectedGroups[earlier].candidateFilters,
                "whitelist candidate tables are shared"
            )
            assertTrue(
                group.candidateFilters.includeSpellIDs
                    ~= projectedGroups[earlier].candidateFilters
                        .includeSpellIDs,
                "whitelist spell-ID maps are shared"
            )
        end
    end
    assertEqual(
        whitelistDescriptor.visibility.requiresAssist,
        true,
        "helpful identity filter assist gate"
    )
    assertEqual(
        whitelistDescriptor.visibility
            .spellIDFilterRequiresPublicAssist,
        true,
        "helpful identity filter requires a public assist reaction"
    )
    assertEqual(
        whitelistDescriptor.visibility
            .spellIDFilterRequiresPublicNonAssist,
        false,
        "helpful identity filter does not require non-assist"
    )
    assertEqual(
        whitelistDescriptor.degradations.spellIDListsIgnored,
        false,
        "whitelist is not ignored"
    )
    assertEqual(
        whitelistDescriptor.degradations
            .spellIDFiltersRestrictedByUnitReaction,
        true,
        "whitelist reaction degradation"
    )
    assertDeepEqual(whitelistDescriptor.diagnostics, {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "SPELL_ID_FILTERS_RESTRICTED_BY_UNIT_REACTION",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
    }, "whitelist diagnostics")
    assertDeepEqual(whitelist, whitelistSnapshot, "whitelist input mutation")

    completeGroups[1].candidateFilters.includeSpellIDs[101] = nil
    assertEqual(
        completeGroups[2].candidateFilters.includeSpellIDs[101],
        true,
        "complete whitelist map isolation"
    )
    assertEqual(
        tuningGroups[1].candidateFilters.includeSpellIDs[101],
        true,
        "complete/tuning whitelist map isolation"
    )

    local emptyWhitelist = baseConfig()
    emptyWhitelist.mode = "whitelist"
    emptyWhitelist.whitelist = {}
    emptyWhitelist.blacklist = false
    local emptyWhitelistDescriptor =
        compile("focus", "HELPFUL", emptyWhitelist)
    for index, group in ipairs(emptyWhitelistDescriptor.completeSpec.groups) do
        assertTrue(
            type(group.candidateFilters) == "table",
            "empty whitelist candidates " .. index
        )
        assertTrue(
            type(group.candidateFilters.includeSpellIDs) == "table",
            "empty whitelist include map " .. index
        )
        assertEqual(
            next(group.candidateFilters.includeSpellIDs),
            nil,
            "empty whitelist remains active " .. index
        )
    end
    assertEqual(
        emptyWhitelistDescriptor.visibility.requiresAssist,
        true,
        "empty helpful whitelist assist gate"
    )
    assertEqual(
        emptyWhitelistDescriptor.visibility
            .spellIDFilterRequiresPublicAssist,
        true,
        "empty helpful whitelist remains an active assist gate"
    )
    assertEqual(
        emptyWhitelistDescriptor.visibility
            .spellIDFilterRequiresPublicNonAssist,
        false,
        "empty helpful whitelist does not require non-assist"
    )
    assertEqual(
        emptyWhitelistDescriptor.degradations
            .spellIDFiltersRestrictedByUnitReaction,
        true,
        "empty whitelist reaction degradation"
    )

    local blacklist = baseConfig()
    blacklist.blacklist = {303, 404, 303}
    blacklist.whitelist = "inactive whitelist is ignored"
    local blacklistDescriptor = compile("target", "HARMFUL", blacklist)
    for index, group in ipairs(blacklistDescriptor.completeSpec.groups) do
        assertDeepEqual(group.candidateFilters, {
            excludeSpellIDs = {
                [303] = true,
                [404] = true,
            },
        }, "blacklist candidate map " .. index)
    end
    assertEqual(
        blacklistDescriptor.visibility.requiresAssist,
        false,
        "harmful identity filter assist gate"
    )
    assertEqual(
        blacklistDescriptor.visibility
            .spellIDFilterRequiresPublicAssist,
        false,
        "harmful identity filter does not require assist"
    )
    assertEqual(
        blacklistDescriptor.visibility
            .spellIDFilterRequiresPublicNonAssist,
        true,
        "harmful identity filter requires a public non-assist reaction"
    )

    local importantWhitelist = baseConfig()
    importantWhitelist.filters = {
        important = true,
    }
    importantWhitelist.mode = "whitelist"
    importantWhitelist.whitelist = {505}
    local importantWhitelistDescriptor =
        compile("focus", "HELPFUL", importantWhitelist)
    assertEqual(
        importantWhitelistDescriptor.completeSpec.groups[1].key,
        "important",
        "important category remains selected with a spell-ID whitelist"
    )
    assertEqual(
        importantWhitelistDescriptor.visibility
            .spellIDFilterRequiresPublicAssist,
        true,
        "important whitelist retains the strict assist gate"
    )
    assertEqual(
        importantWhitelistDescriptor.visibility
            .spellIDFilterRequiresPublicNonAssist,
        false,
        "important whitelist does not add a non-assist gate"
    )

    local emptyBlacklist = baseConfig()
    emptyBlacklist.blacklist = {}
    emptyBlacklist.whitelist = {
        [2] = "inactive malformed whitelist",
    }
    local emptyBlacklistDescriptor =
        compile("target", "HARMFUL", emptyBlacklist)
    for index, group in ipairs(emptyBlacklistDescriptor.completeSpec.groups) do
        assertEqual(
            group.candidateFilters,
            nil,
            "empty blacklist candidates " .. index
        )
    end
    assertEqual(
        emptyBlacklistDescriptor.degradations
            .spellIDFiltersRestrictedByUnitReaction,
        false,
        "empty blacklist reaction degradation"
    )
    assertEqual(
        emptyBlacklistDescriptor.visibility
            .spellIDFilterRequiresPublicAssist,
        false,
        "empty blacklist has no strict assist gate"
    )
    assertEqual(
        emptyBlacklistDescriptor.visibility
            .spellIDFilterRequiresPublicNonAssist,
        false,
        "empty blacklist has no strict non-assist gate"
    )
    assertEqual(
        #emptyBlacklistDescriptor.diagnostics,
        3,
        "empty blacklist ignores inactive list"
    )

    local constructionBaseline =
        compile("target", "HELPFUL", baseConfig())
    assertDeepEqual(
        whitelistDescriptor.constructionKey,
        constructionBaseline.constructionKey,
        "spell candidate filters stay out of construction key"
    )
end

local function testInvalidInputs()
    local config = baseConfig()
    assertCompileError(nil, "HARMFUL", config, "INVALID_UNIT")
    assertCompileError("", "HARMFUL", config, "INVALID_UNIT")
    assertCompileError("target", "PLAYER", config, "INVALID_BASE_FILTER")
    assertCompileError("target", "HARMFUL", nil, "INVALID_AURA_CONFIG")

    local invalid = baseConfig()
    invalid.enabled = 1
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_AURA_CONFIG",
        "invalid enabled"
    )

    for _, position in ipairs({
        {},
        {"NOT_A_POINT", "TOPLEFT", 0, 0},
        {"TOPLEFT", "", 0, 0},
        {"TOPLEFT", "TOPLEFT", "x", 0},
    }) do
        invalid = baseConfig()
        invalid.position = position
        assertCompileError(
            "target",
            "HARMFUL",
            invalid,
            "INVALID_PLACEMENT"
        )
    end

    invalid = baseConfig()
    invalid.anchorTo = ""
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_PLACEMENT"
    )

    invalid = baseConfig()
    invalid.frameLevel = 1.5
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_FRAME_LEVEL"
    )

    invalid = baseConfig()
    invalid.orientation = "diagonal"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_ORIENTATION"
    )

    for _, mutation in ipairs({
        function(value) value.width = 0 end,
        function(value) value.width = math.huge end,
        function(value) value.height = 0 / 0 end,
        function(value) value.spacingX = "2" end,
        function(value)
            value.width = 1
            value.spacingX = -1
        end,
        function(value)
            value.height = 1
            value.spacingY = -1
        end,
    }) do
        invalid = baseConfig()
        mutation(invalid)
        assertCompileError(
            "target",
            "HARMFUL",
            invalid,
            "INVALID_GEOMETRY"
        )
    end

    for _, mutation in ipairs({
        function(value) value.numPerLine = 0 end,
        function(value) value.numPerLine = 2.5 end,
        function(value) value.numTotal = 0 end,
        function(value) value.numTotal = 3.5 end,
    }) do
        invalid = baseConfig()
        mutation(invalid)
        assertCompileError(
            "target",
            "HARMFUL",
            invalid,
            "INVALID_COUNTS"
        )
    end

    invalid = baseConfig()
    invalid.cooldownStyle = "spiral"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_COOLDOWN_STYLE"
    )

    invalid = baseConfig()
    invalid.durationText = nil
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_DURATION_TEXT"
    )

    invalid = baseConfig()
    invalid.durationText.color.normal = "white"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_DURATION_TEXT"
    )

    invalid = baseConfig()
    invalid.stackText = nil
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_STACK_TEXT"
    )

    invalid = baseConfig()
    invalid.stackText.font = "font"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_STACK_TEXT"
    )

    invalid = baseConfig()
    invalid.auraTypeColor = "colors"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_AURA_TYPE_COLOR"
    )

    invalid = baseConfig()
    invalid.filters.castByMe = 1
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_FILTER_SCHEMA"
    )

    invalid = baseConfig()
    invalid.mode = nil
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_SPELL_ID_FILTER_MODE",
        "missing spell-ID filter mode"
    )

    for _, mode in ipairs({"allowlist", "BLACKLIST", true, 0 / 0, {}}) do
        invalid = baseConfig()
        invalid.mode = mode
        assertCompileError(
            "target",
            "HARMFUL",
            invalid,
            "INVALID_SPELL_ID_FILTER_MODE",
            "invalid spell-ID filter mode"
        )
    end

    local invalidSpellIDLists = {
        "not a list",
        {
            [1] = 101,
            [3] = 303,
        },
        {
            [0] = 101,
        },
        {
            [1.5] = 101,
        },
        {
            label = 101,
        },
        {0},
        {-1},
        {1.5},
        {math.huge},
        {0 / 0},
        {"101"},
    }
    for _, mode in ipairs({"blacklist", "whitelist"}) do
        local expectedError = mode == "blacklist"
            and "INVALID_SPELL_ID_BLACKLIST"
            or "INVALID_SPELL_ID_WHITELIST"
        for index, list in ipairs(invalidSpellIDLists) do
            invalid = baseConfig()
            invalid.mode = mode
            invalid[mode] = list
            assertCompileError(
                "target",
                "HARMFUL",
                invalid,
                expectedError,
                ("invalid %s list %d"):format(mode, index)
            )
        end
    end

    invalid = baseConfig()
    invalid.subFrame = "partition"
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_SUBFRAME"
    )

    invalid = baseConfig()
    invalid.subFrame = {
        enabled = true,
        desaturated = true,
        filter = "unknown",
        width = 8,
        height = 8,
    }
    local inactivePartition = compile("target", "HARMFUL", invalid)
    assertEqual(inactivePartition.partition, nil, "unknown inactive partition")
    assertEqual(
        inactivePartition.migrationReady,
        true,
        "unknown inactive partition readiness"
    )

    invalid = baseConfig()
    invalid.subFrame = {
        enabled = true,
        desaturated = "yes",
        filter = "notCastByMe",
        width = 8,
        height = 8,
    }
    assertCompileError(
        "target",
        "HARMFUL",
        invalid,
        "INVALID_SUBFRAME"
    )
end

local function testConstructionBoundary()
    local original = baseConfig()
    local originalDescriptor = compile("target", "HARMFUL", original)
    local originalKey = originalDescriptor.constructionKey

    local tuningMutations = {
        function(config) config.enabled = false end,
        function(config) config.position = {"BOTTOM", "TOP", 20, 30} end,
        function(config) config.anchorTo = "parent" end,
        function(config) config.frameLevel = 12 end,
        function(config) config.orientation = "right_to_left" end,
        function(config) config.spacingX = 4 end,
        function(config) config.spacingY = 5 end,
        function(config) config.numPerLine = 2 end,
        function(config) config.numTotal = 7 end,
    }
    for index, mutate in ipairs(tuningMutations) do
        local config = baseConfig()
        mutate(config)
        local descriptor = compile("focus", "HARMFUL", config)
        assertDeepEqual(
            descriptor.constructionKey,
            originalKey,
            "tuning construction key " .. index
        )
    end

    local constructionMutations = {
        function(config) config.width = 11 end,
        function(config) config.height = 7 end,
        function(config) config.cooldownStyle = "none" end,
        function(config) config.durationText.enabled = false end,
        function(config) config.durationText.font[2] = 12 end,
        function(config) config.stackText.color[1] = 0.25 end,
        function(config) config.tooltip.enabled = false end,
        function(config) config.auraTypeColor.debuffType = false end,
        function(config) config.filters.isBossAura = false end,
    }
    for index, mutate in ipairs(constructionMutations) do
        local config = baseConfig()
        mutate(config)
        local descriptor = compile("target", "HARMFUL", config)
        local same = pcall(
            assertDeepEqual,
            descriptor.constructionKey,
            originalKey,
            "construction change " .. index
        )
        assertEqual(same, false, "construction key changed " .. index)
    end

    local ignored = baseConfig()
    ignored.futureField = {
        shouldNotMatter = true,
    }
    ignored.durationText.color.percent.value = 0.1
    ignored.durationText.color.seconds.value = 9
    local ignoredDescriptor = compile("target", "HARMFUL", ignored)
    assertDeepEqual(
        ignoredDescriptor.constructionKey,
        originalKey,
        "ignored construction fields"
    )

    local approximate = baseConfig()
    approximate.tooltip.anchorTo = "root"
    local approximateDescriptor = compile("target", "HARMFUL", approximate)
    approximate.tooltip.position[3] = 400
    approximate.tooltip.position[4] = -500
    local movedApproximate = compile("target", "HARMFUL", approximate)
    assertDeepEqual(
        movedApproximate.constructionKey,
        approximateDescriptor.constructionKey,
        "inactive native tooltip offsets"
    )
end

local function testFreshDeterministicOutput()
    local config = baseConfig()
    local snapshot = copy(config)
    local first = compile("target", "HARMFUL", config)
    local second = compile("target", "HARMFUL", config)

    assertDeepEqual(config, snapshot, "input mutation")
    assertDeepEqual(first, second, "deterministic output")
    assertTrue(first ~= second, "descriptor tables are shared")
    assertTrue(
        first.completeSpec ~= second.completeSpec,
        "complete specs are shared"
    )
    assertTrue(
        first.completeSpec.groups ~= second.completeSpec.groups,
        "complete group lists are shared"
    )
    assertTrue(
        first.completeSpec.groups[1].layout
            ~= first.tuningSpec.groups[1].layout,
        "complete and tuning layouts are shared"
    )
    assertTrue(
        first.completeSpec.groups[1].buttonStyle
            ~= first.completeSpec.groups[2].buttonStyle,
        "complete group styles are shared"
    )
    assertTrue(
        first.completeSpec.groups[1].buttonStyle
            ~= first.constructionKey.groups[1].buttonStyle,
        "complete and construction styles are shared"
    )
    assertTrue(
        first.completeSpec.groups[1].buttonStyle.durationText.font
            ~= first.constructionKey.groups[1].buttonStyle.durationText.font,
        "construction fonts are shared"
    )
    assertTrue(first.placement.position ~= config.position, "placement alias")
    assertTrue(
        first.completeSpec.groups[1].buttonStyle.durationText.font
            ~= config.durationText.font,
        "duration font alias"
    )
    assertTrue(
        first.completeSpec.groups[1].buttonStyle.stackText.color
            ~= config.stackText.color,
        "stack color alias"
    )

    first.completeSpec.groups[1].filterString = "BROKEN"
    first.completeSpec.groups[1].layout.elementSpacing = 999
    first.completeSpec.groups[1].buttonStyle.durationText.font[1] = "BROKEN"
    first.tuningSpec.groups[1].layout.lineSpacing = 999
    first.constructionKey.groups[1].buttonStyle.tooltip.enabled = false
    first.placement.position[1] = "CENTER"
    first.visibility.requiresVisible = false
    first.metrics.groupCount = 99
    first.degradations.perGroupLimit = false
    first.diagnostics[1] = "BROKEN"

    local third = compile("target", "HARMFUL", config)
    assertDeepEqual(third, second, "fresh output after mutation")

    local reordered = {}
    local topKeys = {
        "auraTypeColor",
        "whitelist",
        "blacklist",
        "mode",
        "filters",
        "stackText",
        "durationText",
        "tooltip",
        "numTotal",
        "numPerLine",
        "spacingY",
        "spacingX",
        "height",
        "width",
        "cooldownStyle",
        "orientation",
        "frameLevel",
        "anchorTo",
        "position",
        "enabled",
    }
    for _, key in ipairs(topKeys) do
        reordered[key] = copy(config[key])
    end
    local reorderedFilters = {}
    for _, key in ipairs({
        "dispellable",
        "isBossAura",
        "castByNPC",
        "castByUnit",
        "castByOthers",
        "castByMe",
    }) do
        reorderedFilters[key] = config.filters[key]
    end
    reordered.filters = reorderedFilters
    local reorderedDescriptor = compile("target", "HARMFUL", reordered)
    assertDeepEqual(reorderedDescriptor, second, "insertion-order output")
end

testLegacyLoadAndSchemaGate()
testCompleteSpecContract()
testOrientationAndGeometry()
testStyleProjection()
testTooltipProjection()
testEmptyPolicies()
testPartitionMetadata()
testCapacityMetrics()
testSpellIDCandidateFilters()
testInvalidInputs()
testConstructionBoundary()
testFreshDeterministicOutput()

assertEqual(#harness.forbiddenCalls, 0, "forbidden dependency calls")
print("unit_frame_aura_spec_test.lua: ok")
