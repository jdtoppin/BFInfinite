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
        error(message .. ": type mismatch", 2)
    end
    if type(actual) ~= "table" then
        assertEqual(actual, expected, message)
        return
    end

    seen = seen or {}
    if seen[actual] == expected then return end
    seen[actual] = expected
    for key, value in pairs(expected) do
        assertDeepEqual(
            actual[key],
            value,
            message .. "." .. tostring(key),
            seen
        )
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error(message .. ": unexpected key " .. tostring(key), 2)
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

local function countKeys(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function resolveFilters(baseFilter, filters)
    if type(filters) ~= "table" then return nil end
    local all = filters.all == true
    local player = filters.player == true
    local notPlayer = filters.notPlayer == true
    if player and notPlayer then all = true end

    return {
        all = all,
        player = not all and player,
        notPlayer = not all and notPlayer,
        raidInCombat = not all and filters.raidInCombat == true,
        raidPlayerDispellable = not all
            and filters.raidPlayerDispellable == true,
        bigDefensive = not all
            and baseFilter == "HELPFUL"
            and filters.bigDefensive == true,
        externalDefensive = not all
            and baseFilter == "HELPFUL"
            and filters.externalDefensive == true,
        important = not all
            and baseFilter == "HELPFUL"
            and filters.important == true,
        anyDispellable = not all
            and filters.anyDispellable == true,
    }, {
        bossAuraUsesCuratedRaidInCombat = false,
        legacySourceFilterUsesSuperset = false,
        legacyDispellableUsesRaidPlayerDispellable = false,
    }
end

local UF = {}
local firedEvents = {}
local AF = {
    Copy = copy,
    Fire = function(event)
        firedEvents[#firedEvents + 1] = event
    end,
    GetTexture = function(texture)
        return "AF/" .. texture
    end,
}
local BFI = {
    funcs = {
        ResolveUnitFrameAuraFilters = resolveFilters,
    },
    modules = {
        UnitFrames = UF,
    },
}

local function newFrame()
    return {
        Hide = function(self) self.hidden = true end,
        SetAllPoints = function() end,
    }
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    AnchorUtil = {
        FlowLayoutAxis = {
            Horizontal = 101,
            Vertical = 102,
        },
        FlowDirection = {
            Left = 201,
            Right = 202,
            Up = 203,
            Down = 204,
        },
    },
    AuraContainerSortMethod = {Default = 301},
    AuraContainerSortDirection = {Normal = 401},
    CustomAuraContainerAuraProcessingPolicy = {None = 501},
    AuraUtil = {
        AuraFilters = {
            Important = "IMPORTANT",
            Dispellable = "DISPELLABLE",
        },
    },
    CreateFrame = function() return newFrame() end,
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
}
environment._G = environment
setmetatable(environment, {
    __index = function(_, key)
        error("unexpected priority-test global: " .. tostring(key), 2)
    end,
})

for _, path in ipairs({
    "Modules/UnitFrames/AuraPolicy.lua",
    "Modules/UnitFrames/AuraSpec.lua",
    "Modules/UnitFrames/BuffDisplays.lua",
}) do
    local chunk, loadError = loadfile(path)
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
end

local function baseConfig()
    return {
        enabled = true,
        presentation = "icons",
        sortMode = "blizzard",
        position = {"TOPLEFT", "TOPLEFT", 0, 0},
        anchorTo = "root",
        frameLevel = 1,
        orientation = "left_to_right",
        cooldownStyle = "clock",
        width = 20,
        height = 4,
        spacingX = 1,
        spacingY = 0,
        numPerLine = 1,
        numTotal = 2,
        tooltip = {
            enabled = true,
            anchorTo = "self",
            position = {"TOP", "BOTTOM", 0, -1},
        },
        durationText = {
            enabled = false,
            font = {"font", 10, "", false},
            position = {"CENTER", "CENTER", 0, 0},
            color = {
                normal = {1, 1, 1, 1},
                percent = {enabled = false},
                seconds = {enabled = false},
            },
        },
        stackText = {
            enabled = false,
            font = {"font", 10, "", false},
            position = {"CENTER", "CENTER", 0, 0},
            color = {1, 1, 1, 1},
        },
        filters = {all = true},
        mode = "blacklist",
        blacklist = {},
        whitelist = {},
        auraTypeColor = {},
    }
end

local function compile(config, baseFilter)
    local descriptor, errorCode = UF.CompileNativeAuraSpec(
        "party1",
        baseFilter or "HELPFUL",
        config
    )
    assertTrue(descriptor, errorCode)
    assertEqual(errorCode, nil, "successful priority compile")
    return descriptor
end

local function assertCompileError(config, expected, baseFilter)
    local descriptor, errorCode = UF.CompileNativeAuraSpec(
        "party1",
        baseFilter or "HELPFUL",
        config
    )
    assertEqual(descriptor, nil, expected .. " descriptor")
    assertEqual(errorCode, expected, expected .. " error")
end

local function priorityBarConfig()
    local config = baseConfig()
    config.presentation = "bar"
    config.cooldownStyle = nil
    config.sortMode = "spell_list_priority"
    config.mode = "whitelist"
    config.whitelist = {101, 202, 303, 404}
    config.spacingY = -1
    config.durationBar = {
        height = 3,
        gap = 1,
        inset = 0,
        color = {0.8, 0.8, 0.8, 1},
        backgroundColor = {0.1, 0.1, 0.1, 0.75},
    }
    config.spellColors = {
        [101] = {1, 0, 0, 1},
        [303] = {0, 0, 1, 1},
    }
    return config
end

local function testPriorityGroupsAndStandaloneBar()
    local descriptor = compile(priorityBarConfig())
    local spec = descriptor.completeSpec

    assertEqual(#spec.groups, 4, "one group per priority spell")
    assertEqual(spec.clipToHolder, true, "complete spec clips")
    assertEqual(descriptor.tuningSpec.clipToHolder, true,
        "tuning spec clips")
    assertEqual(descriptor.clipToHolder, true,
        "descriptor advertises clipping")
    assertEqual(descriptor.constructionKey.sortMode,
        "spell_list_priority", "priority construction mode")
    assertEqual(descriptor.constructionKey.clipToHolder, true,
        "priority clipping is structural")
    assertEqual(descriptor.constructionKey.maxDisplayed, nil,
        "Max Displayed remains tuning-only")

    for index, spellID in ipairs({101, 202, 303, 404}) do
        local group = spec.groups[index]
        assertEqual(group.key, "all_priority_" .. index,
            "stable position group key")
        assertEqual(group.maxFrameCount, 1,
            "priority group owns one aura")
        assertEqual(group.layout.layoutIndex, index,
            "priority group layout order")
        assertEqual(countKeys(group.candidateFilters.includeSpellIDs), 1,
            "exact group candidate count")
        assertEqual(group.candidateFilters.includeSpellIDs[spellID], true,
            "exact group spell identity")
        assertEqual(group.buttonStyle.cooldownStyle, "duration_bar",
            "standalone bar native style")
        assertEqual(group.buttonStyle.durationText, nil,
            "standalone bar omits duration text")
        assertEqual(group.buttonStyle.stackText, nil,
            "standalone bar omits stack text")
        assertEqual(group.buttonStyle.tooltip.enabled, false,
            "priority native tooltip disabled")
        assertEqual(group.buttonStyle.durationBar.height, nil,
            "standalone bar omits underbar height")
        assertEqual(group.buttonStyle.durationBar.gap, nil,
            "standalone bar omits underbar gap")
    end

    assertDeepEqual(
        spec.groups[1].buttonStyle.durationBar.color,
        {1, 0, 0, 1},
        "static priority spell color becomes bar fill"
    )
    assertDeepEqual(
        spec.groups[2].buttonStyle.durationBar.color,
        {0.8, 0.8, 0.8, 1},
        "uncolored priority spell uses bar color"
    )

    assertEqual(spec.flowLayout.maximumLineSize, 41,
        "native priority flow wraps after Max Displayed")
    assertEqual(spec.holder.width, 41,
        "holder spans only Max Displayed")
    assertEqual(spec.holder.height, 4,
        "holder is one priority line")
    assertEqual(spec.groups[1].layout.lineSpacing, 0,
        "negative cross spacing cannot leak overflow")
    assertEqual(descriptor.metrics.nativeVisibleCapacity, 2,
        "global visible priority capacity")
    assertEqual(descriptor.metrics.nativeRegisteredCapacity, 4,
        "all priority groups remain registered")
    assertEqual(descriptor.metrics.initialRestrictedButtonCount, 40,
        "one initial batch per exact group")
    assertEqual(
        descriptor.metrics.freshContainerRestrictedButtonCountCeiling,
        40,
        "exact priority worst-case capacity"
    )
end

local function testMaxDisplayedTunesWithoutConstructionChange()
    local firstConfig = priorityBarConfig()
    local first = compile(firstConfig)
    local secondConfig = priorityBarConfig()
    secondConfig.numTotal = 1
    local second = compile(secondConfig)

    assertDeepEqual(
        first.constructionKey,
        second.constructionKey,
        "Max Displayed does not change priority construction"
    )
    assertEqual(second.completeSpec.flowLayout.maximumLineSize, 20,
        "tuned priority line length")
    assertEqual(second.completeSpec.holder.width, 20,
        "tuned priority viewport extent")
    assertEqual(second.metrics.nativeVisibleCapacity, 1,
        "tuned global visible capacity")
    assertEqual(second.metrics.nativeRegisteredCapacity, 4,
        "tuning retains every exact group")
end

local function testPriorityValidationAndLatentPreference()
    local latent = priorityBarConfig()
    latent.mode = "blacklist"
    latent.blacklist = {}
    latent.spellColors = {}
    local descriptor = compile(latent)
    assertEqual(descriptor.clipToHolder, nil,
        "priority preference is latent in blacklist mode")
    assertEqual(#descriptor.completeSpec.groups, 1,
        "latent preference uses Blizzard group topology")
    assertEqual(descriptor.completeSpec.groups[1].maxFrameCount, 2,
        "latent preference uses ordinary group limit")

    local harmful = priorityBarConfig()
    assertCompileError(
        harmful,
        "SPELL_LIST_PRIORITY_REQUIRES_HELPFUL_FILTER",
        "HARMFUL"
    )

    local multiplePolicyGroups = priorityBarConfig()
    multiplePolicyGroups.filters = {
        player = true,
        raidInCombat = true,
    }
    assertCompileError(
        multiplePolicyGroups,
        "SPELL_LIST_PRIORITY_REQUIRES_SINGLE_FILTER_GROUP"
    )

    local duplicate = priorityBarConfig()
    duplicate.whitelist = {101, 202, 101}
    assertCompileError(
        duplicate,
        "SPELL_LIST_PRIORITY_REQUIRES_UNIQUE_WHITELIST"
    )

    local partition = priorityBarConfig()
    partition.subFrame = {
        enabled = true,
        filter = "notCastByMe",
        desaturated = true,
        width = 10,
        height = 4,
    }
    assertCompileError(
        partition,
        "SPELL_LIST_PRIORITY_UNSUPPORTED_PARTITION"
    )

    local highlight = priorityBarConfig()
    highlight.presentation = "frame_highlight"
    assertCompileError(
        highlight,
        "SPELL_LIST_PRIORITY_UNSUPPORTED_PRESENTATION"
    )

    local invalid = priorityBarConfig()
    invalid.sortMode = "custom_comparator"
    assertCompileError(invalid, "INVALID_AURA_SORT_MODE")
end

local function newCollection()
    local collection = baseConfig()
    assert(UF.NormalizeBuffDisplayCollection(collection))
    return collection
end

local function addEnabledDisplay(collection, name, template)
    local display = assert(UF.CreateBuffDisplay(
        collection,
        name,
        template
    ))
    display.enabled = true
    return display
end

local function testHardButtonCapacityAndMetrics()
    local normalCollection = newCollection()
    local normal = baseConfig()
    normal.numTotal = 22
    local normalDisplay = addEnabledDisplay(
        normalCollection,
        "Normal",
        normal
    )
    local normalPlan, normalOverflow, normalMetrics =
        UF.GetActiveBuffDisplayReservationPlan(normalCollection)
    assertEqual(#normalPlan, 1, "normal display admitted")
    assertEqual(#normalOverflow, 0, "normal display not overflowed")
    assertEqual(normalMetrics.buttonCapacityCosts[normalDisplay.id], 30,
        "normal group reserves worst-case provider growth")
    assertEqual(normalMetrics.reservationCosts[normalDisplay.id], 30,
        "old cost field remains compatible")
    assertEqual(normalMetrics.buttonCapacityLimit, 40,
        "hard child capacity")

    local priorityCollection = newCollection()
    local priority = priorityBarConfig()
    priority.numTotal = 2
    local four = addEnabledDisplay(
        priorityCollection,
        "Four Priority Spells",
        priority
    )
    local plan, overflow, metrics =
        UF.GetActiveBuffDisplayReservationPlan(priorityCollection)
    assertEqual(#plan, 1, "four exact groups fit hard capacity")
    assertEqual(#overflow, 0, "four exact groups do not overflow")
    local fourMetrics = metrics.displayMetrics[four.id]
    assertEqual(fourMetrics.buttonCapacityCost, 40,
        "priority exact-group capacity")
    assertEqual(fourMetrics.buttonCapacityExceeded, false,
        "capacity flag uses button terminology")
    assertEqual(fourMetrics.effectiveSortMode,
        "spell_list_priority", "effective priority mode")
    assertEqual(fourMetrics.prioritySpellCount, 4,
        "priority spell metric")

    local fiveCollection = newCollection()
    local fiveConfig = priorityBarConfig()
    fiveConfig.whitelist[5] = 505
    local five = addEnabledDisplay(
        fiveCollection,
        "Five Priority Spells",
        fiveConfig
    )
    local fivePlan, fiveOverflow, fiveMetrics =
        UF.GetActiveBuffDisplayReservationPlan(fiveCollection)
    assertEqual(#fivePlan, 0, "fifth exact group exceeds hard capacity")
    assertEqual(fiveOverflow[1], five, "over-capacity display reported")
    assertEqual(fiveMetrics.buttonCapacityCosts[five.id], 50,
        "over-capacity cost remains observable")
    assertEqual(
        fiveMetrics.displayMetrics[five.id].buttonCapacityExceeded,
        true,
        "over-capacity metric"
    )

    local latentCollection = newCollection()
    local latentConfig = priorityBarConfig()
    latentConfig.mode = "blacklist"
    latentConfig.numTotal = 22
    local latent = addEnabledDisplay(
        latentCollection,
        "Latent Priority",
        latentConfig
    )
    local latentPlan, latentOverflow, latentMetrics =
        UF.GetActiveBuffDisplayReservationPlan(latentCollection)
    assertEqual(#latentPlan, 1, "latent preference uses normal capacity")
    assertEqual(#latentOverflow, 0, "latent preference is not rejected")
    local latentDisplayMetrics = latentMetrics.displayMetrics[latent.id]
    assertEqual(latentDisplayMetrics.sortMode,
        "spell_list_priority", "stored priority preference preserved")
    assertEqual(latentDisplayMetrics.effectiveSortMode, "blizzard",
        "blacklist disables priority effectively")
    assertEqual(latentDisplayMetrics.priorityPreferenceLatent, true,
        "latent preference exposed to UX")
    assertEqual(latentDisplayMetrics.buttonCapacityCost, 30,
        "latent preference uses normal worst-case capacity")

    local displayCapCollection = newCollection()
    for index = 1, 5 do
        local highlight = baseConfig()
        highlight.presentation = "frame_highlight"
        addEnabledDisplay(
            displayCapCollection,
            "Highlight " .. index,
            highlight
        )
    end
    local displayPlan, displayOverflow =
        UF.GetActiveBuffDisplayReservationPlan(displayCapCollection)
    assertEqual(#displayPlan, 4, "four-display cap retained")
    assertEqual(#displayOverflow, 1,
        "fifth display overflows below button capacity")
end

local function fakeNativeRuntime()
    local runtime = {
        enabled = false,
        active = false,
    }
    function runtime:LoadConfig(config)
        self._config = copy(config)
    end
    function runtime:Enable() self.active = true end
    function runtime:Disable() self.active = false end
    function runtime:Update() end
    function runtime:SetUnit() end
    function runtime:RefreshVisibility() end
    function runtime:EnableConfigMode() end
    function runtime:DisableConfigMode() end
    function runtime:RequiresReloadForConfig() return false end
    function runtime:GetNativeAuraState()
        return {
            state = "READY",
            active = self.active,
            built = true,
            pending = false,
            configMode = false,
            reloadRequired = false,
        }
    end
    function runtime:Destroy() end
    return runtime
end

local function testCompositeRuntimeExposesCapacityMetrics()
    UF.HasNativeAuraContainerBackend = function() return true end
    UF.CreateNativeGroupAuraIndicator = function()
        return fakeNativeRuntime()
    end

    local chunk, loadError =
        loadfile("Modules/UnitFrames/BuffDisplayRuntime.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local collection = newCollection()
    local display = addEnabledDisplay(
        collection,
        "Priority Runtime",
        priorityBarConfig()
    )
    local parent = {
        enabled = true,
        _nativeAuraContainers = {
            buffs = {},
            buffDisplays = {
                [display.id] = {},
            },
        },
        _nativeAuraBuffDisplayReservationCosts = {
            [display.id] = 40,
        },
    }
    local manager = UF.CreateGroupBuffDisplays(
        parent,
        "PriorityRuntime",
        "HELPFUL",
        "buffs"
    )
    manager:LoadConfig(collection)
    local state = manager:GetNativeAuraState()
    local child = state.displays[display.id]
    assertEqual(child.buttonCapacityCost, 40,
        "runtime exposes per-display button cost")
    assertEqual(child.buttonCapacityLimit, 40,
        "runtime exposes per-display button limit")
    assertEqual(child.effectiveSortMode,
        "spell_list_priority", "runtime exposes effective priority")
    assertEqual(state.reservationMetrics.buttonCapacityUsed, 40,
        "runtime exposes aggregate capacity")
end

local function testPriorityRuntimeInjectsStaticSpellColors()
    local runtimeUF = {}
    local compiledConfigs = {}
    local spellColorCalls = 0
    local globalSpellColors = {
        [101] = {1, 0.25, 0.1, 1},
    }
    local runtimeAF = {
        Copy = copy,
        AddToPixelUpdater_Auto = function() end,
        RegisterCallback = function() end,
        Fire = function() end,
    }
    local runtimeA = {}
    function runtimeA.GetNativeSpellColorMap()
        spellColorCalls = spellColorCalls + 1
        return copy(globalSpellColors)
    end

    function runtimeUF.HasNativeAuraContainerBackend()
        return true
    end
    function runtimeUF:RegisterEvent() end
    function runtimeUF:UnregisterEvent() end
    function runtimeUF.CompileNativeAuraSpec(_, _, config)
        compiledConfigs[#compiledConfigs + 1] = copy(config)
        return {
            empty = true,
            migrationReady = false,
            visibility = {},
            diagnostics = {},
            degradations = {},
            metrics = {},
        }
    end
    function runtimeUF.CreateNativeGroupAuraContainerController()
        local frame = {}
        return {
            GetFrame = function() return frame end,
        }
    end

    local runtimeBFI = {
        funcs = {
            isValueNonSecret = function() return true end,
        },
        modules = {
            Auras = runtimeA,
            UnitFrames = runtimeUF,
        },
    }
    local runtimeEnvironment = {
        _G = false,
        AbstractFramework = runtimeAF,
        C_Timer = {
            After = function() end,
        },
        CreateFrame = function()
            error("priority runtime must not allocate fallback frames", 2)
        end,
        GetBuildInfo = function()
            return "12.1.0", "69299", "Aug 13 2026", 120100
        end,
        InCombatLockdown = function() return false end,
        UnitCanAssist = function() return true end,
        UnitCanAttack = function() return false end,
        UnitIsVisible = function() return true end,
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
    }
    runtimeEnvironment._G = runtimeEnvironment
    setmetatable(runtimeEnvironment, {
        __index = function(_, key)
            error("unexpected priority-runtime global: "
                .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/AuraRuntime.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, runtimeEnvironment)
    chunk("BFInfinite", runtimeBFI)

    local root = {
        enabled = true,
        effectiveUnit = "party1",
    }
    local runtime = assert(runtimeUF.CreateNativeGroupAuraIndicator(
        root,
        "PriorityColorRuntime",
        "HELPFUL",
        {},
        {
            includeSpellColors = false,
            includePartition = false,
        }
    ))
    local priorityConfig = {
        enabled = true,
        sortMode = "spell_list_priority",
        mode = "whitelist",
        whitelist = {101},
    }
    runtime:LoadConfig(priorityConfig)
    assertDeepEqual(
        compiledConfigs[#compiledConfigs].spellColors,
        globalSpellColors,
        "exact priority runtime receives global static colors"
    )
    assertEqual(spellColorCalls, 1,
        "priority runtime requests global colors")

    local latentConfig = copy(priorityConfig)
    latentConfig.mode = "blacklist"
    latentConfig.blacklist = {}
    runtime:LoadConfig(latentConfig)
    assertEqual(compiledConfigs[#compiledConfigs].spellColors, nil,
        "latent blacklist priority does not receive colors")
    assertEqual(spellColorCalls, 1,
        "latent priority skips global colors")

    runtime:LoadConfig(priorityConfig)
    globalSpellColors[101] = {0.1, 0.5, 1, 1}
    local compileCount = #compiledConfigs
    assertEqual(runtimeUF.RefreshNativeAuraSpellColors(), false,
        "priority color refresh does not require topology reload")
    assertEqual(#compiledConfigs, compileCount + 1,
        "priority runtime participates in color refresh")
    assertDeepEqual(
        compiledConfigs[#compiledConfigs].spellColors,
        globalSpellColors,
        "priority refresh recompiles with current global colors"
    )
end

testPriorityGroupsAndStandaloneBar()
testMaxDisplayedTunesWithoutConstructionChange()
testPriorityValidationAndLatentPreference()
testHardButtonCapacityAndMetrics()
testCompositeRuntimeExposesCapacityMetrics()
testPriorityRuntimeInjectsStaticSpellColors()

print("unit_frame_buff_display_priority_test.lua: ok")
