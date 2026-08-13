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

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function tablesEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not tablesEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function assertTablesEqual(actual, expected, message)
    assertTrue(tablesEqual(actual, expected), message)
end

local function LoadProductionDefaults()
    local productionBD = {}
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.AbstractFramework = {
        Copy = deepCopy,
        GetColorTable = function(name)
            if name == "aura_seconds" then return {1, 0, 0, 1} end
            if name == "aura_percent" then return {1, 0.5, 0, 1} end
            return {1, 1, 1, 1}
        end,
        RegisterCallback = function() end,
    }

    local BFI = {
        modules = {
            BuffsDebuffs = productionBD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/Defaults.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    return productionBD.GetDefaults()
end

local defaults = LoadProductionDefaults()

local function NewHarness(capability)
    local state = {
        defaultsReads = 0,
        registrations = 0,
        suppressionCalls = 0,
    }
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
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
    environment.CustomAuraContainerAuraProcessingPolicy = {
        None = "NONE",
    }
    environment.CreateFrame = function()
        error("descriptor registration must not construct frames", 2)
    end

    local BD = {}
    function BD.HasCustomHarmfulAuraDescriptorCapability()
        return capability == true
    end
    function BD.GetDefaults()
        state.defaultsReads = state.defaultsReads + 1
        return deepCopy(defaults)
    end
    function BD.RegisterCustomAuraContainerPane(which, compiler)
        state.registrations = state.registrations + 1
        state.registeredPane = which
        state.compiler = compiler
    end
    function BD.SetNativePublicAurasSuppressed()
        state.suppressionCalls = state.suppressionCalls + 1
    end

    local BFI = {
        modules = {
            BuffsDebuffs = BD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/CustomDebuffs.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    state.BD = BD
    return state
end

do
    local liveSuppressionAvailable = false
    local state = {
        registrations = 0,
    }
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
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
    environment.CustomAuraContainerAuraProcessingPolicy = {None = "NONE"}

    local BD = {}
    function BD.HasCustomHarmfulAuraDescriptorCapability()
        return true
    end
    function BD.HasCustomHarmfulAuraContainerCapability()
        return liveSuppressionAvailable
    end
    function BD.GetDefaults()
        return deepCopy(defaults)
    end
    function BD.RegisterCustomAuraContainerPane(which, compiler)
        state.registrations = state.registrations + 1
        state.which = which
        state.compiler = compiler
    end

    local BFI = {
        modules = {
            BuffsDebuffs = BD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/CustomDebuffs.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    assertEqual(state.registrations, 1,
        "stable descriptor capability registers during transient outage")
    assertEqual(state.which, "debuffs",
        "transient suppression outage retains Debuffs registration")
    assertEqual(type(state.compiler), "function",
        "transient suppression outage retains descriptor compiler")
    liveSuppressionAvailable = true
    local config = deepCopy(defaults.debuffs)
    config.enabled = true
    config.customHarmfulEnabled = true
    assertTrue(state.compiler(config).enabled,
        "recovered live capability needs no descriptor reload")
end

do
    local unavailable = NewHarness(false)
    assertNil(
        unavailable.compiler,
        "unavailable capability exposes no compiler"
    )
    assertEqual(unavailable.defaultsReads, 0,
        "unavailable capability does not inspect defaults")
    assertEqual(unavailable.registrations, 0,
        "unavailable capability registers no controller")
    assertEqual(unavailable.suppressionCalls, 0,
        "unavailable capability performs no suppression")
end

local state = NewHarness(true)
local compile = state.compiler
assertEqual(type(compile), "function", "active compiler registered")
assertEqual(state.defaultsReads, 1, "available compiler reads defaults once")
assertEqual(state.registrations, 1, "Debuffs registers one controller")
assertEqual(state.registeredPane, "debuffs", "Debuffs registration pane")
assertEqual(state.suppressionCalls, 0, "registration performs no suppression")

do
    local config = deepCopy(defaults.debuffs)
    config.enabled = true
    config.customHarmfulEnabled = true
    config.duration.showSecondsUnit = false
    config.duration.color.percent.enabled = true
    config.duration.color.seconds.value = 99
    config.duration.color.seconds.rgb = {0.9, 0.2, 0.1, 0.8}
    local savedConfig = deepCopy(config)
    local descriptor = assert(compile(config))

    assertTablesEqual(config, savedConfig,
        "compiler does not mutate saved Debuffs configuration")
    assertEqual(descriptor.enabled, true,
        "both explicit toggles activate custom harmful presentation")
    assertEqual(descriptor.holder.width, 746, "default row width")
    assertEqual(descriptor.holder.height, 26, "default row height")
    assertEqual(descriptor.holderRolesets, "buffs", "holder roleset")
    assertEqual(descriptor.holderAnchor.globalName, "DebuffFrame",
        "active placement follows the Blizzard Debuff root")
    assertEqual(descriptor.holderAnchor.point, "TOPRIGHT",
        "holder anchor point")
    assertEqual(descriptor.holderAnchor.relativePoint, "TOPRIGHT",
        "holder relative anchor point")
    assertEqual(descriptor.holderAnchor.x, 0, "holder X offset")
    assertEqual(descriptor.holderAnchor.y, 0, "holder Y offset")
    assertEqual(descriptor.nativeSuppression, "harmful",
        "descriptor requests full harmful suppression")
    assertNil(descriptor.position, "draft creates no independent mover")
    assertNil(descriptor.positionSave, "draft saves no position")
    assertNil(descriptor.nativeFollower,
        "draft does not mutate the #127 follower contract")

    assertEqual(descriptor.flowLayout.axis, "HORIZONTAL", "flow axis")
    assertEqual(descriptor.flowLayout.anchorPoint, "TOPRIGHT",
        "flow anchor")
    assertEqual(descriptor.flowLayout.horizontalGrowthDirection, "LEFT",
        "right-aligned growth")
    assertEqual(descriptor.flowLayout.verticalGrowthDirection, "DOWN",
        "Debuff rows grow downward")

    assertEqual(#descriptor.groups, 1, "one native harmful group")
    local group = descriptor.groups[1]
    assertEqual(group.key, "harmful", "harmful group key")
    assertEqual(group.filterString, "HARMFUL", "native harmful filter")
    assertEqual(group.maxFrameCount, 25, "finite combined cap")
    assertEqual(countKeys(group.candidateFilters), 0,
        "no Lua-side candidate classification")
    assertEqual(group.layout.elementSpacing, 4, "default X spacing")
    assertEqual(group.layout.lineSpacing, 6, "default Y spacing")
    assertEqual(group.layout.elementWidth, 26, "default width")
    assertEqual(group.layout.elementHeight, 26, "default height")

    local style = group.buttonStyle
    assertEqual(style.width, 26, "button width")
    assertEqual(style.height, 26, "button height")
    assertEqual(style.nativeDispelColor, true,
        "AF r42 native square dispel-colour contract")
    assertNil(style.cancelAuraButtons, "harmful auras are not cancellable")
    assertNil(style.dispelColor, "no caller-provided dispel colour")
    assertEqual(style.tooltip.enabled, true, "native tooltip enabled")
    assertEqual(style.tooltip.hideInCombat, false,
        "native combat tooltip remains enabled")
    assertNil(style.durationText.showSecondsUnit,
        "legacy seconds-unit field does not enter AF style")
    assertNil(style.durationText.color.seconds,
        "raw seconds rule does not enter AF style")
    assertNil(style.durationText.color.percent,
        "raw percent rule does not enter AF style")
    assertTablesEqual(style.durationText.color.threshold, {
        mode = "seconds",
        value = 99,
        rgb = {0.9, 0.2, 0.1, 0.8},
    }, "seconds wins when both saved rules are enabled")
    assertEqual(countKeys(style.durationText.color), 2,
        "duration style contains normal plus one active threshold")
    assertEqual(countKeys(style.durationText.color.threshold), 3,
        "threshold exposes only normalized AF fields")
    assertTrue(
        style.durationText.color.normal ~= config.duration.color.normal,
        "normal duration colour is copied"
    )
    assertTrue(
        style.durationText.color.threshold.rgb
            ~= config.duration.color.seconds.rgb,
        "threshold duration colour is copied"
    )
    assertEqual(
        descriptor.constructionKey.buttonStyle.durationText.color.threshold,
        style.durationText.color.threshold,
        "active threshold belongs to construction identity"
    )
    assertEqual(#descriptor.itemEnchantments, 0,
        "Debuffs have no item enchantments")

    config.duration.color.normal[1] = 0.1
    config.duration.color.seconds.rgb[1] = 0.1
    assertEqual(style.durationText.color.normal[1], savedConfig.duration.color.normal[1],
        "later saved normal-colour edits do not alias the descriptor")
    assertEqual(style.durationText.color.threshold.rgb[1], 0.9,
        "later saved threshold-colour edits do not alias the descriptor")
    style.durationText.color.threshold.rgb[2] = 0.7
    assertEqual(config.duration.color.seconds.rgb[2], 0.2,
        "descriptor threshold edits do not alias saved configuration")

    assertEqual(state.registrations, 1,
        "compilation does not re-register the controller")
    assertEqual(state.suppressionCalls, 0,
        "compilation still performs no suppression")
end

do
    local config = deepCopy(defaults.debuffs)
    config.enabled = false
    config.customHarmfulEnabled = true
    config.width = 20
    config.height = 30
    config.spacingX = 2
    config.spacingY = 3
    config.wrapAfter = 4
    config.maxWraps = 2
    config.sortMethod = "INDEX"
    config.sortDirection = "+"
    local descriptor = assert(compile(config))
    local group = descriptor.groups[1]

    assertEqual(descriptor.enabled, false, "appearance toggle disables row")
    assertEqual(descriptor.holder.width, 86, "custom row width")
    assertEqual(descriptor.holder.height, 30, "custom row height")
    assertEqual(group.maxFrameCount, 8, "custom combined cap")
    assertEqual(group.sortMethod, "AURA_INSTANCE", "native sort method")
    assertEqual(group.sortDirection, "NORMAL", "native sort direction")
end

do
    local config = deepCopy(defaults.debuffs)
    config.enabled = true
    config.customHarmfulEnabled = false
    assertEqual(assert(compile(config)).enabled, false,
        "appearance enable alone does not opt into replacement")

    config.enabled = false
    config.customHarmfulEnabled = true
    assertEqual(assert(compile(config)).enabled, false,
        "replacement opt-in does not override pane disable")

    config.enabled = true
    config.customHarmfulEnabled = "true"
    assertEqual(assert(compile(config)).enabled, false,
        "malformed replacement opt-in fails closed")
end

do
    local secondsConfig = deepCopy(defaults.debuffs)
    local secondsDescriptor = assert(compile(secondsConfig))
    local secondsKey = secondsDescriptor.constructionKey
    assertTablesEqual(
        secondsDescriptor.groups[1].buttonStyle.durationText.color.threshold,
        {
            mode = "seconds",
            value = 5,
            rgb = {1, 0, 0, 1},
        },
        "shipped seconds threshold"
    )

    local changedSeconds = deepCopy(secondsConfig)
    changedSeconds.duration.color.seconds.value = 9
    assertTrue(
        not tablesEqual(
            assert(compile(changedSeconds)).constructionKey,
            secondsKey
        ),
        "active seconds threshold changes construction identity"
    )

    local inactivePercent = deepCopy(secondsConfig)
    inactivePercent.duration.color.percent.enabled = true
    inactivePercent.duration.color.percent.value = 0.25
    inactivePercent.duration.color.percent.rgb = {0.2, 0.3, 0.4, 0.5}
    assertTablesEqual(
        assert(compile(inactivePercent)).constructionKey,
        secondsKey,
        "inactive percent rule normalizes out while seconds wins"
    )

    local percentConfig = deepCopy(secondsConfig)
    percentConfig.duration.color.seconds.enabled = false
    percentConfig.duration.color.percent.enabled = true
    local percentDescriptor = assert(compile(percentConfig))
    assertTablesEqual(
        percentDescriptor.groups[1].buttonStyle.durationText.color.threshold,
        {
            mode = "percent",
            value = 0.5,
            rgb = {1, 0.5, 0, 1},
        },
        "percent threshold is selected only when seconds is disabled"
    )
    assertTrue(
        not tablesEqual(percentDescriptor.constructionKey, secondsKey),
        "threshold mode changes construction identity"
    )

    local changedPercent = deepCopy(percentConfig)
    changedPercent.duration.color.percent.value = 0.25
    assertTrue(
        not tablesEqual(
            assert(compile(changedPercent)).constructionKey,
            percentDescriptor.constructionKey
        ),
        "active percent threshold changes construction identity"
    )

    for _, descriptor in ipairs({secondsDescriptor, percentDescriptor}) do
        assertEqual(descriptor.enabled, false,
            "default-off replacement ignores duration colour changes")
        assertEqual(descriptor.groups[1].filterString, "HARMFUL",
            "duration colour changes never affect selection")
        assertEqual(countKeys(descriptor.groups[1].candidateFilters), 0,
            "duration colour changes never add visibility filters")
    end
end

do
    local config = deepCopy(defaults.debuffs)
    config.separateOwn = 1
    local descriptor, diagnostic = compile(config)
    assertNil(descriptor, "Separate Own fails closed")
    assertEqual(diagnostic, "UNSUPPORTED_SEPARATE_OWN",
        "Separate Own diagnostic")
end

do
    local config = deepCopy(defaults.debuffs)
    config.width = {}
    config.height = -100
    config.spacingX = math.huge
    config.spacingY = -50
    config.wrapAfter = 0
    config.maxWraps = 500
    config.sortMethod = "invalid"
    config.sortDirection = "invalid"
    config.stack = {
        font = {false, math.huge, false, "yes"},
        position = {"INVALID", "INVALID", math.huge, {}},
        color = {2, -1, "bad", math.huge},
    }

    local ok, descriptor = pcall(compile, config)
    assertTrue(ok, "malformed config normalizes without assertion")
    assertEqual(descriptor.enabled, false,
        "malformed config remains default-off")
    local group = descriptor.groups[1]
    assertEqual(group.buttonStyle.width, 26, "invalid width fallback")
    assertEqual(group.buttonStyle.height, 10, "height clamp")
    assertEqual(group.layout.elementSpacing, 4,
        "infinite spacing fallback")
    assertEqual(group.layout.lineSpacing, -1,
        "negative spacing clamp")
    assertEqual(group.maxFrameCount, 50, "normalized combined cap")
    assertEqual(group.sortMethod, "EXPIRATION", "sort fallback")
    assertEqual(group.sortDirection, "REVERSE", "direction fallback")
end

do
    local file = assert(io.open(
        "Modules/BuffsDebuffs/CustomDebuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()
    for _, pattern in ipairs({
        "C_UnitAuras",
        "C_Secrets",
        "UNIT_AURA",
        ":IsShown",
        ":GetPoint",
        ":GetSize",
        "buttonInfo",
        "auraData",
        "spellId",
        ":SetParent",
        "SecureAuraHeaderTemplate",
        "BD.SetNativePublicAurasSuppressed(",
        "PrivateAuraAnchors",
        "privateAuraAnchor",
    }) do
        assertNil(source:find(pattern, 1, true),
            "forbidden direct dependency: " .. pattern)
    end
    assertTrue(
        source:find(
            "BD.RegisterCustomAuraContainerPane(\"debuffs\"",
            1,
            true
        ) ~= nil,
        "active Debuffs descriptor is registered"
    )
    for _, dormantPattern in ipairs({
        "CompileCustomDebuffsDraftDescriptor",
        "activationBlocked",
        "proposedHolderAnchor",
    }) do
        assertNil(source:find(dormantPattern, 1, true),
            "dormant scaffold removed: " .. dormantPattern)
    end
end

print("buffs/debuffs custom Debuffs descriptor tests passed")
