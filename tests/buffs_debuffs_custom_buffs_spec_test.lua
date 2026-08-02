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

local function NewHarness(capability)
    local state = {
        registrations = {},
    }
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.HUD_EDIT_MODE_BUFF_FRAME_LABEL = "Buff Frame"
    environment.AnchorUtil = {
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
    }
    environment.AuraContainerSortMethod = {
        AuraInstanceIDOnly = "AURA_INSTANCE",
        NameOnly = "NAME",
        ExpirationOnly = "EXPIRATION",
    }
    environment.AuraContainerSortDirection = {
        Normal = "NORMAL",
        Reverse = "REVERSE",
    }
    environment.AuraContainerItemEnchantmentSlot = {
        MainHand = "MAIN_HAND",
        OffHand = "OFF_HAND",
        Ranged = "RANGED",
    }
    environment.AuraContainerItemEnchantmentSortMethod = {
        Slot = "SLOT",
    }
    environment.CustomAuraContainerAuraProcessingPolicy = {
        None = "NONE",
    }
    environment.CustomAuraContainerItemEnchantmentPlacement = {
        BeforeAuraGroups = "BEFORE",
    }
    if not capability then
        environment.AnchorUtil = false
        environment.AuraContainerSortMethod = false
        environment.AuraContainerSortDirection = false
        environment.AuraContainerItemEnchantmentSlot = false
        environment.AuraContainerItemEnchantmentSortMethod = false
        environment.CustomAuraContainerAuraProcessingPolicy = false
        environment.CustomAuraContainerItemEnchantmentPlacement = false
    end

    local BD = {}
    function BD.HasCustomAuraContainerCapability()
        return capability == true
    end
    function BD.RegisterCustomAuraContainerPane(which, compiler)
        state.registrations[#state.registrations + 1] = {
            which = which,
            compiler = compiler,
        }
    end
    function BD.GetDefaults()
        assert(capability, "unsupported client must not inspect 12.1 defaults")
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
    local unavailable = NewHarness(false)
    assertEqual(
        #unavailable.state.registrations,
        0,
        "unsupported client registers no custom pane"
    )
end

local harness = NewHarness(true)
assertEqual(#harness.state.registrations, 1, "one pane registration")
assertEqual(
    harness.state.registrations[1].which,
    "buffs",
    "only Buffs registers"
)
local compile = harness.state.registrations[1].compiler

local orientationCases = {
    "left_to_right_then_down",
    "left_to_right_then_up",
    "right_to_left_then_down",
    "right_to_left_then_up",
    "top_to_bottom_then_left",
    "top_to_bottom_then_right",
    "bottom_to_top_then_left",
    "bottom_to_top_then_right",
}

for _, savedOrientation in ipairs(orientationCases) do
    local config = NewConfig()
    config.enabled = true
    config.orientation = savedOrientation
    config.width = 20
    config.height = 30
    config.spacingX = 2
    config.spacingY = 3
    config.wrapAfter = 4
    config.maxWraps = 2

    local descriptor = assert(compile(config))
    local flow = descriptor.flowLayout
    assertEqual(flow.axis, "HORIZONTAL", savedOrientation .. " fixed axis")
    assertEqual(
        flow.anchorPoint,
        "BOTTOMRIGHT",
        savedOrientation .. " fixed flow anchor"
    )
    assertEqual(
        flow.horizontalGrowthDirection,
        "LEFT",
        savedOrientation .. " fixed horizontal growth"
    )
    assertEqual(
        flow.verticalGrowthDirection,
        "UP",
        savedOrientation .. " fixed vertical growth"
    )
    assertEqual(
        descriptor.containerPoint.point,
        "BOTTOMRIGHT",
        savedOrientation .. " fixed container point"
    )
    assertEqual(
        descriptor.containerPoint.relativePoint,
        "BOTTOMRIGHT",
        savedOrientation .. " fixed container relative point"
    )

    assertEqual(
        flow.maximumLineSize,
        86,
        savedOrientation .. " maximum line"
    )
    assertEqual(
        descriptor.holder.width,
        86,
        savedOrientation .. " holder width"
    )
    assertEqual(
        descriptor.holder.height,
        30,
        savedOrientation .. " one-row holder height"
    )

    local groupLayout = descriptor.groups[1].layout
    assertEqual(
        groupLayout.elementSpacing,
        2,
        savedOrientation .. " primary spacing"
    )
    assertEqual(
        groupLayout.lineSpacing,
        3,
        savedOrientation .. " cross spacing"
    )
    assertEqual(groupLayout.groupSpacing, 0,
        savedOrientation .. " group spacing")
    assertEqual(
        groupLayout.groupLineSpacing,
        3,
        savedOrientation .. " group line spacing"
    )
    assertEqual(groupLayout.elementWidth, 20,
        savedOrientation .. " element width")
    assertEqual(groupLayout.elementHeight, 30,
        savedOrientation .. " element height")
    assertTablesEqual(
        descriptor.itemEnchantmentLayout,
        {
            elementSpacing = 2,
            lineSpacing = 3,
            groupSpacing = 0,
            groupLineSpacing = 3,
            forceNewLine = false,
            elementWidth = 20,
            elementHeight = 30,
            placement = "BEFORE",
        },
        savedOrientation .. " enchantment layout"
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
    config.width = 20
    config.height = 30
    config.wrapAfter = 1
    config.maxWraps = 2
    config.position = {"TOPRIGHT", "TOPRIGHT", -12, -16}
    config.duration.showSecondsUnit = false
    config.duration.color.percent.enabled = true
    config.duration.color.seconds.value = 99

    local descriptor = assert(compile(config))
    assertTablesEqual(
        descriptor.position,
        config.position,
        "saved BFI position remains the holder location"
    )
    assertEqual(type(descriptor.positionSave), "function",
        "mover uses a profile position save callback")
    descriptor.positionSave("BOTTOMLEFT", 14, 18)
    assertTablesEqual(
        config.position,
        {"BOTTOMLEFT", 14, 18},
        "mover callback canonicalizes the profile position"
    )
    assertNil(config.position[4],
        "mover callback removes a stale legacy relative anchor field")
    assertEqual(descriptor.moverText, "Buff Frame", "BFI mover label")
    assertEqual(descriptor.holderRolesets, "buffs", "Buff roleset")
    assertTablesEqual(
        descriptor.nativeFollower,
        {
            globalName = "DebuffFrame",
            point = "TOPRIGHT",
            relativePoint = "BOTTOMRIGHT",
            x = 0,
            y = -5,
        },
        "native DebuffFrame follows the BFI holder seam"
    )
    assertNil(descriptor.holderAnchor, "holder is not owned by DebuffFrame")
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
        "retired seconds-unit field is omitted"
    )
    assertNil(
        style.durationText.color.percent,
        "retired percent color is omitted"
    )
    assertNil(
        style.durationText.color.seconds,
        "retired seconds color is omitted"
    )
    assertEqual(
        countKeys(style.durationText.color),
        1,
        "duration projects normal color only"
    )
    assertEqual(
        descriptor.itemEnchantments[1].buttonStyle,
        style,
        "group and enchantment share initializer style"
    )
    assertEqual(
        countKeys(descriptor.constructionKey),
        2,
        "construction key contains schema and style only"
    )
    assertNil(descriptor.constructionKey.orientation,
        "dormant saved orientation is not construction input")
    assertNil(descriptor.constructionKey.position,
        "dormant saved position is not construction input")
    assertNil(descriptor.constructionKey.wrapAfter,
        "wrapping remains live")

    -- The mover owns only the first-row seam. Extra Buff and enchantment rows
    -- grow upward outside it so Debuffs remain immediately below the mover.
    assertEqual(descriptor.holder.width, 20,
        "single-column holder width")
    assertEqual(descriptor.holder.height, 30,
        "holder reserves exactly one icon row")
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
    liveConfig.duration.color.seconds.value = 45
    local live = assert(compile(liveConfig))
    assertTablesEqual(
        live.constructionKey,
        baseline.constructionKey,
        "live and retired settings do not change construction key"
    )

    local sizeConfig = NewConfig()
    sizeConfig.width = sizeConfig.width + 1
    assertTrue(
        not tablesEqual(
            assert(compile(sizeConfig)).constructionKey,
            baseline.constructionKey
        ),
        "button dimensions are construction-only"
    )

    local textConfig = NewConfig()
    textConfig.duration.font[2] = textConfig.duration.font[2] + 1
    assertTrue(
        not tablesEqual(
            assert(compile(textConfig)).constructionKey,
            baseline.constructionKey
        ),
        "initializer text styling is construction-only"
    )
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
    assertEqual(descriptor.flowLayout.anchorPoint, "BOTTOMRIGHT",
        "invalid orientation uses fixed follower flow")
    assertEqual(descriptor.groups[1].buttonStyle.width, 26,
        "invalid width falls back")
    assertEqual(descriptor.groups[1].buttonStyle.height, 10,
        "height clamps")
    assertEqual(descriptor.groups[1].layout.elementSpacing, 4,
        "infinite spacing falls back")
    assertEqual(descriptor.groups[1].layout.lineSpacing, -1,
        "negative spacing clamps")
end

do
    local file = assert(io.open(
        "Modules/BuffsDebuffs/CustomBuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()
    local forbidden = {
        "C_UnitAuras",
        "C_Secrets",
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
end

print("buffs/debuffs custom Buffs compiler tests passed")
