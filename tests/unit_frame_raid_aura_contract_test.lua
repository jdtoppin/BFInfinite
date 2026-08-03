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
            error(("%s: unexpected key %s"):format(
                message,
                tostring(key)
            ), 2)
        end
    end
end

local function deepMerge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            deepMerge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function copyMany(...)
    local result = {}
    for index = 1, select("#", ...) do
        deepMerge(result, select(index, ...))
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

local RAID_BUFF_WHITELIST = {
    8936,
    774,
    155777,
    33763,
    188550,
    48438,
    102351,
    102352,
    391891,
    145205,
    383193,
    439530,
    429224,
    363502,
    370889,
    364343,
    355941,
    376788,
    366155,
    367364,
    373862,
    378001,
    373267,
    395296,
    395152,
    360827,
    410089,
    406732,
    406789,
    445740,
    409895,
    119611,
    124682,
    325209,
    406139,
    450805,
    423439,
    53563,
    223306,
    148039,
    156910,
    200025,
    287280,
    156322,
    431381,
    388013,
    388007,
    388010,
    388011,
    200654,
    139,
    41635,
    17,
    194384,
    77489,
    372847,
    443526,
    974,
    383648,
    61295,
    382024,
    375986,
    444490,
}

local RAID_DEBUFF_BLACKLIST = {
    8326,
    160029,
    255234,
    225080,
    57723,
    57724,
    80354,
    264689,
    390435,
    206151,
    195776,
    352562,
    356419,
    387847,
    213213,
}

local UF = {}
local AF = {}
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local BFI = {
    L = L,
    funcs = {},
    modules = {
        UnitFrames = UF,
    },
}

function AF.Copy(...)
    return copyMany(...)
end

function AF.GetColorTable(_, alpha)
    return {1, 1, 1, alpha == nil and 1 or alpha}
end

function AF.Merge(target, source)
    return deepMerge(target, source)
end

function AF.RegisterCallback()
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    AnchorUtil = {
        FlowLayoutAxis = FLOW_AXIS,
        FlowDirection = FLOW_DIRECTION,
    },
    AuraContainerSortDirection = SORT_DIRECTION,
    AuraContainerSortMethod = SORT_METHOD,
    AuraUtil = {
        AuraFilters = {
            Important = "IMPORTANT",
            Dispellable = "DISPELLABLE",
        },
    },
    CustomAuraContainerAuraProcessingPolicy = PROCESSING_POLICY,
    GetCVar = function() return nil end,
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
        error("unexpected Raid aura contract global: " .. tostring(key), 2)
    end,
})

for _, path in ipairs({
    "Utils.lua",
    "Modules/UnitFrames/AuraPolicy.lua",
    "Modules/UnitFrames/AuraSpec.lua",
    "Modules/UnitFrames/Presets.lua",
}) do
    local chunk, loadError = loadfile(path)
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
end

local function hasDiagnostic(descriptor, code)
    for _, diagnostic in ipairs(descriptor.diagnostics) do
        if diagnostic == code then return true end
    end
    return false
end

local function spellIDMap(list)
    local map = {}
    for _, spellID in ipairs(list) do
        map[spellID] = true
    end
    return map
end

local function assertIndependentCandidateFilters(
    groups,
    filterKey,
    expectedSpellIDs,
    message
)
    local projected = {}
    for index, group in ipairs(groups) do
        assertDeepEqual(group.candidateFilters, {
            [filterKey] = expectedSpellIDs,
        }, message .. " candidate filters " .. index)

        for previousIndex, previous in ipairs(projected) do
            assertTrue(
                group.candidateFilters ~= previous.candidateFilters,
                ("%s candidate table %d aliases %d"):format(
                    message,
                    index,
                    previousIndex
                )
            )
            assertTrue(
                group.candidateFilters[filterKey]
                    ~= previous.candidateFilters[filterKey],
                ("%s spell-ID map %d aliases %d"):format(
                    message,
                    index,
                    previousIndex
                )
            )
        end
        projected[index] = group
    end
end

local function assertGroup(group, expectedKey, expectedFilter, message)
    assertEqual(group.key, expectedKey, message .. " key")
    assertEqual(group.filterString, expectedFilter, message .. " filter")
    assertEqual(group.maxFrameCount, 4, message .. " capacity")
    assertEqual(group.sortMethod, SORT_METHOD.Default, message .. " sort")
    assertEqual(
        group.sortDirection,
        SORT_DIRECTION.Normal,
        message .. " sort direction"
    )
end

local function assertCommonDescriptor(
    descriptor,
    presetID,
    auraName,
    expectedVisible,
    expectedAssist
)
    local message = presetID .. " Raid " .. auraName
    assertEqual(descriptor.migrationReady, true, message .. " migration")
    assertEqual(descriptor.empty, false, message .. " empty")
    assertEqual(descriptor.visibility.requiresVisible, expectedVisible,
        message .. " visible gate")
    assertEqual(descriptor.visibility.requiresAssist, expectedAssist,
        message .. " assist gate")
    assertEqual(descriptor.metrics.legacyMaxFrameCount, 4,
        message .. " legacy capacity")
    assertEqual(descriptor.metrics.nativeBatchSize, 10,
        message .. " native batch size")
    assertEqual(#descriptor.completeSpec.slots, 0,
        message .. " complete slots")
    assertEqual(#descriptor.tuningSpec.slots, 0,
        message .. " tuning slots")
    assertEqual(#descriptor.constructionKey.slots, 0,
        message .. " construction slots")
    assertEqual(descriptor.degradations.spellIDListsIgnored, false,
        message .. " spell IDs are compiled")
    assertEqual(
        descriptor.degradations.spellIDFiltersRestrictedByUnitReaction,
        true,
        message .. " spell-ID reaction restriction"
    )
    assertTrue(
        hasDiagnostic(
            descriptor,
            "SPELL_ID_FILTERS_RESTRICTED_BY_UNIT_REACTION"
        ),
        message .. " spell-ID reaction diagnostic"
    )
    assertEqual(
        descriptor.degradations.privateAuraSourceUnseparable,
        true,
        message .. " private-source degradation"
    )
end

local function assertRaidContract(preset)
    local raid = preset.get().raid
    local buffs = raid.indicators.buffs
    local debuffs = raid.indicators.debuffs

    assertEqual(buffs.mode, "whitelist",
        preset.id .. " Raid buff list mode")
    assertEqual(#buffs.whitelist, 63,
        preset.id .. " Raid buff whitelist count")
    assertDeepEqual(
        buffs.whitelist,
        RAID_BUFF_WHITELIST,
        preset.id .. " Raid exact buff whitelist"
    )
    assertEqual(#buffs.blacklist, 0,
        preset.id .. " Raid buff blacklist count")
    assertEqual(debuffs.mode, "blacklist",
        preset.id .. " Raid debuff list mode")
    assertEqual(#debuffs.blacklist, 15,
        preset.id .. " Raid debuff blacklist count")
    assertDeepEqual(
        debuffs.blacklist,
        RAID_DEBUFF_BLACKLIST,
        preset.id .. " Raid exact debuff blacklist"
    )
    assertEqual(#debuffs.whitelist, 0,
        preset.id .. " Raid debuff whitelist count")

    local buffDescriptor, buffError = UF.CompileNativeAuraSpec(
        "raid1",
        "HELPFUL",
        buffs
    )
    assertTrue(buffDescriptor, buffError)
    assertCommonDescriptor(
        buffDescriptor,
        preset.id,
        "buff",
        true,
        true
    )
    assertEqual(#buffDescriptor.completeSpec.groups, 1,
        preset.id .. " Raid buff group count")
    assertEqual(#buffDescriptor.tuningSpec.groups, 1,
        preset.id .. " Raid buff tuning group count")
    assertGroup(
        buffDescriptor.completeSpec.groups[1],
        "player",
        "HELPFUL|PLAYER",
        preset.id .. " Raid buff group"
    )
    assertIndependentCandidateFilters(
        {
            buffDescriptor.completeSpec.groups[1],
            buffDescriptor.tuningSpec.groups[1],
        },
        "includeSpellIDs",
        spellIDMap(RAID_BUFF_WHITELIST),
        preset.id .. " Raid buff whitelist"
    )
    assertEqual(buffDescriptor.completeSpec.holder.width, 48,
        preset.id .. " Raid buff holder width")
    assertEqual(buffDescriptor.completeSpec.holder.height, 12,
        preset.id .. " Raid buff holder height")
    assertEqual(buffDescriptor.metrics.nativeVisibleCapacity, 4,
        preset.id .. " Raid buff native capacity")
    assertEqual(buffDescriptor.metrics.initialRestrictedButtonCount, 10,
        preset.id .. " Raid buff initial buttons")
    assertEqual(
        buffDescriptor.metrics.freshContainerRestrictedButtonCountCeiling,
        10,
        preset.id .. " Raid buff button ceiling"
    )
    assertEqual(buffDescriptor.degradations.perGroupLimit, false,
        preset.id .. " Raid buff per-group limit")
    assertEqual(buffDescriptor.degradations.perGroupSort, false,
        preset.id .. " Raid buff per-group sort")
    assertEqual(
        buffDescriptor.degradations.auraTypeColorSourceRulesIgnored,
        false,
        preset.id .. " Raid buff source-color degradation"
    )

    local debuffDescriptor, debuffError = UF.CompileNativeAuraSpec(
        "raid1",
        "HARMFUL",
        debuffs
    )
    assertTrue(debuffDescriptor, debuffError)
    assertCommonDescriptor(
        debuffDescriptor,
        preset.id,
        "debuff",
        false,
        false
    )
    local expectedDebuffGroups = {
        {"all", "HARMFUL"},
    }
    assertEqual(
        #debuffDescriptor.completeSpec.groups,
        #expectedDebuffGroups,
        preset.id .. " Raid debuff group count"
    )
    assertEqual(
        #debuffDescriptor.tuningSpec.groups,
        #expectedDebuffGroups,
        preset.id .. " Raid debuff tuning group count"
    )
    for index, expected in ipairs(expectedDebuffGroups) do
        assertGroup(
            debuffDescriptor.completeSpec.groups[index],
            expected[1],
            expected[2],
            preset.id .. " Raid debuff group " .. index
        )
    end
    assertIndependentCandidateFilters(
        {
            debuffDescriptor.completeSpec.groups[1],
            debuffDescriptor.tuningSpec.groups[1],
        },
        "excludeSpellIDs",
        spellIDMap(RAID_DEBUFF_BLACKLIST),
        preset.id .. " Raid debuff blacklist"
    )
    -- Raid units are assistable. Blizzard can match harmful spell identities
    -- there only when an aura is NeverSecret, so the complete exclusion map is
    -- retained while this reaction restriction remains explicit.
    assertEqual(
        debuffDescriptor.degradations
            .spellIDFiltersRestrictedByUnitReaction,
        true,
        preset.id .. " Raid friendly harmful NeverSecret restriction"
    )
    assertTrue(
        hasDiagnostic(
            debuffDescriptor,
            "SPELL_ID_FILTERS_RESTRICTED_BY_UNIT_REACTION"
        ),
        preset.id .. " Raid friendly harmful restriction diagnostic"
    )
    assertEqual(debuffDescriptor.completeSpec.holder.width, 48,
        preset.id .. " Raid debuff holder width")
    assertEqual(debuffDescriptor.completeSpec.holder.height, 12,
        preset.id .. " Raid debuff holder height")
    assertEqual(debuffDescriptor.metrics.nativeVisibleCapacity, 4,
        preset.id .. " Raid debuff native capacity")
    assertEqual(debuffDescriptor.metrics.initialRestrictedButtonCount, 10,
        preset.id .. " Raid debuff initial buttons")
    assertEqual(
        debuffDescriptor.metrics.freshContainerRestrictedButtonCountCeiling,
        10,
        preset.id .. " Raid debuff button ceiling"
    )
    assertEqual(debuffDescriptor.degradations.perGroupLimit, false,
        preset.id .. " Raid debuff per-group limit")
    assertEqual(debuffDescriptor.degradations.perGroupSort, false,
        preset.id .. " Raid debuff per-group sort")
    assertEqual(
        debuffDescriptor.degradations.auraTypeColorSourceRulesIgnored,
        true,
        preset.id .. " Raid debuff source-color degradation"
    )
    assertTrue(
        hasDiagnostic(
            debuffDescriptor,
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED"
        ),
        preset.id .. " Raid debuff source-color diagnostic"
    )

    return raid, {buffDescriptor, debuffDescriptor}
end

local presets = UF.GetPresets()
assertEqual(#presets, 2, "shipped preset count")
local firstRaid, firstDescriptors = assertRaidContract(presets[1])
local secondRaid = assertRaidContract(presets[2])
assertDeepEqual(firstRaid, secondRaid, "shared shipped Raid config")

local totals = {
    containers = 0,
    groups = 0,
    slots = 0,
    legacyCapacity = 0,
    nativeVisibleCapacity = 0,
    initialRestrictedButtons = 0,
    freshContainerCeiling = 0,
}
for _ = 1, 40 do
    for _, descriptor in ipairs(firstDescriptors) do
        totals.containers = totals.containers + 1
        totals.groups = totals.groups + descriptor.metrics.groupCount
        totals.slots = totals.slots + #descriptor.completeSpec.slots
        totals.legacyCapacity = totals.legacyCapacity
            + descriptor.metrics.legacyMaxFrameCount
        totals.nativeVisibleCapacity = totals.nativeVisibleCapacity
            + descriptor.metrics.nativeVisibleCapacity
        totals.initialRestrictedButtons = totals.initialRestrictedButtons
            + descriptor.metrics.initialRestrictedButtonCount
        totals.freshContainerCeiling = totals.freshContainerCeiling
            + descriptor.metrics.freshContainerRestrictedButtonCountCeiling
    end
end

assertEqual(totals.containers, 80, "Raid native containers")
assertEqual(totals.groups, 80, "Raid native groups")
assertEqual(totals.slots, 0, "Raid native slots")
assertEqual(totals.legacyCapacity, 320, "Raid legacy visible capacity")
assertEqual(totals.nativeVisibleCapacity, 320,
    "Raid native visible capacity")
assertEqual(totals.initialRestrictedButtons, 800,
    "Raid initial restricted buttons")
assertEqual(totals.freshContainerCeiling, 800,
    "Raid fresh-container restricted-button ceiling")

print("unit_frame_raid_aura_contract_test.lua: ok")
