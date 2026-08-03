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
    GetCVar = function()
        return "0"
    end,
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
        error("unexpected Party aura contract global: " .. tostring(key), 2)
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

local function assertPartyContract(preset)
    local party = preset.get().party
    local buffs = party.indicators.buffs
    local debuffs = party.indicators.debuffs

    local buffDescriptor, buffError = UF.CompileNativeAuraSpec(
        "party1",
        "HELPFUL",
        buffs
    )
    assertTrue(buffDescriptor, buffError)
    assertEqual(buffDescriptor.migrationReady, true,
        preset.id .. " buff migration")
    assertEqual(buffDescriptor.empty, false, preset.id .. " buff empty")
    assertEqual(#buffDescriptor.completeSpec.groups, 1,
        preset.id .. " buff group count")
    assertEqual(
        buffDescriptor.completeSpec.groups[1].filterString,
        "HELPFUL|PLAYER",
        preset.id .. " buff filter"
    )
    assertEqual(buffDescriptor.completeSpec.groups[1].maxFrameCount, 10,
        preset.id .. " buff group capacity")
    assertEqual(
        buffDescriptor.completeSpec.groups[1].sortMethod,
        SORT_METHOD.Default,
        preset.id .. " buff sort"
    )
    assertEqual(buffDescriptor.completeSpec.holder.width, 129,
        preset.id .. " buff holder width")
    assertEqual(buffDescriptor.completeSpec.holder.height, 12,
        preset.id .. " buff holder height")
    assertEqual(buffDescriptor.visibility.requiresVisible, true,
        preset.id .. " buff visible gate")
    assertEqual(buffDescriptor.visibility.requiresAssist, false,
        preset.id .. " buff assist gate")
    assertEqual(buffDescriptor.metrics.legacyMaxFrameCount, 10,
        preset.id .. " buff legacy capacity")
    assertEqual(buffDescriptor.metrics.nativeVisibleCapacity, 10,
        preset.id .. " buff native capacity")
    assertEqual(buffDescriptor.metrics.initialRestrictedButtonCount, 10,
        preset.id .. " buff initial buttons")
    assertEqual(
        buffDescriptor.metrics.freshContainerRestrictedButtonCountCeiling,
        10,
        preset.id .. " buff button ceiling"
    )

    local debuffDescriptor, debuffError = UF.CompileNativeAuraSpec(
        "party1",
        "HARMFUL",
        debuffs
    )
    assertTrue(debuffDescriptor, debuffError)
    assertEqual(debuffDescriptor.migrationReady, true,
        preset.id .. " debuff migration")
    assertEqual(debuffDescriptor.empty, false,
        preset.id .. " debuff empty")

    -- The current production resolver treats the shipped legacy
    -- castByUnit=true setting as the full harmful set. Keep this replayed
    -- Party contract aligned with the canonical migration used by BFI #137.
    local expectedFilters = {"HARMFUL"}
    assertEqual(#debuffDescriptor.completeSpec.groups, #expectedFilters,
        preset.id .. " debuff group count")
    for index, expectedFilter in ipairs(expectedFilters) do
        local group = debuffDescriptor.completeSpec.groups[index]
        assertEqual(group.filterString, expectedFilter,
            preset.id .. " debuff filter " .. index)
        assertEqual(group.maxFrameCount, 6,
            preset.id .. " debuff capacity " .. index)
        assertEqual(group.sortMethod, SORT_METHOD.Default,
            preset.id .. " debuff sort " .. index)
        assertEqual(group.sortDirection, SORT_DIRECTION.Normal,
            preset.id .. " debuff sort direction " .. index)
    end

    assertEqual(debuffDescriptor.completeSpec.holder.width, 59,
        preset.id .. " debuff holder width")
    assertEqual(debuffDescriptor.completeSpec.holder.height, 39,
        preset.id .. " debuff holder height")
    assertEqual(debuffDescriptor.visibility.requiresVisible, false,
        preset.id .. " debuff visible gate")
    assertEqual(debuffDescriptor.visibility.requiresAssist, false,
        preset.id .. " debuff assist gate")
    assertEqual(debuffDescriptor.metrics.legacyMaxFrameCount, 6,
        preset.id .. " debuff legacy capacity")
    assertEqual(debuffDescriptor.metrics.nativeVisibleCapacity, 6,
        preset.id .. " debuff native capacity")
    assertEqual(debuffDescriptor.metrics.initialRestrictedButtonCount, 10,
        preset.id .. " debuff initial buttons")
    assertEqual(
        debuffDescriptor.metrics.freshContainerRestrictedButtonCountCeiling,
        10,
        preset.id .. " debuff button ceiling"
    )
    assertEqual(
        debuffDescriptor.degradations.auraTypeColorSourceRulesIgnored,
        true,
        preset.id .. " debuff source-color degradation"
    )
    assertTrue(
        hasDiagnostic(
            debuffDescriptor,
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED"
        ),
        preset.id .. " debuff source-color diagnostic"
    )

    return buffs, debuffs
end

local presets = UF.GetPresets()
assertEqual(#presets, 2, "shipped preset count")
local firstBuffs, firstDebuffs = assertPartyContract(presets[1])
local secondBuffs, secondDebuffs = assertPartyContract(presets[2])
assertEqual(firstBuffs.numTotal, secondBuffs.numTotal,
    "shared Party buff contract")
assertEqual(firstDebuffs.numTotal, secondDebuffs.numTotal,
    "shared Party debuff contract")

-- Five fixed Party children prebuild one 10-button buff group, one 10-button
-- debuff group, and one dispel-overlay AuraSlot apiece.
assertEqual(5 * (10 + 10 + 1), 105,
    "Party initial restricted buttons")

print("unit_frame_party_aura_contract_test.lua: ok")
