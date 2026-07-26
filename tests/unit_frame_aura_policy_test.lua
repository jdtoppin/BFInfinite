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

local forbiddenCalls = 0
local function forbidden(name)
    return function()
        forbiddenCalls = forbiddenCalls + 1
        error("forbidden policy dependency: " .. name, 2)
    end
end

local forbiddenTable = setmetatable({}, {
    __index = function(_, key)
        forbiddenCalls = forbiddenCalls + 1
        error("forbidden policy dependency: " .. tostring(key), 2)
    end,
})

local UF = {}
local F = {}
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local AF = {}
local BFI = {
    funcs = F,
    L = L,
    modules = {
        UnitFrames = UF,
    },
}
local moduleEnvironment = {
    _G = false,
    AbstractFramework = AF,
    assert = assert,
    ipairs = ipairs,
    next = next,
    pcall = pcall,
    select = select,
    table = table,
    tonumber = tonumber,
    type = type,
    GetCVar = forbidden("GetCVar"),
    CreateFrame = forbidden("CreateFrame"),
    InCombatLockdown = forbidden("InCombatLockdown"),
    UnitCanAssist = forbidden("UnitCanAssist"),
    UnitCanAttack = forbidden("UnitCanAttack"),
    UnitIsVisible = forbidden("UnitIsVisible"),
    C_UnitAuras = forbiddenTable,
    AuraData = forbiddenTable,
}
moduleEnvironment._G = moduleEnvironment
moduleEnvironment["is" .. "secretvalue"] = forbidden("secret-value API")
setmetatable(moduleEnvironment, {
    __index = function(_, key)
        error("unexpected policy global: " .. tostring(key), 2)
    end,
})

local utilsChunk, utilsLoadError = loadfile("Utils.lua")
assertTrue(utilsChunk, utilsLoadError)
setfenv(utilsChunk, moduleEnvironment)
utilsChunk("BFInfinite", BFI)

local chunk, loadError = loadfile("Modules/UnitFrames/AuraPolicy.lua")
assertTrue(chunk, loadError)
setfenv(chunk, moduleEnvironment)
chunk("BFInfinite", BFI)

assertEqual(type(UF.CompileNativeAuraPolicy), "function", "compiler export")

local function compile(baseFilter, filters)
    local policy, errorCode = UF.CompileNativeAuraPolicy(baseFilter, filters)
    assertTrue(policy, errorCode)
    assertEqual(errorCode, nil, "successful compiler error")
    return policy
end

local function assertGroups(policy, expected, message)
    assertEqual(#policy.groups, #expected, (message or "policy") .. " group count")
    for index, group in ipairs(expected) do
        local actual = policy.groups[index]
        assertEqual(actual.key, group[1], (message or "policy") .. " key " .. index)
        assertEqual(
            actual.filterString,
            group[2],
            (message or "policy") .. " filter " .. index
        )
        assertEqual(actual.candidateFilters, nil,
            (message or "policy") .. " candidates " .. index)
        assertEqual(actual.maxFrameCount, nil,
            (message or "policy") .. " max " .. index)
        assertEqual(actual.layout, nil, (message or "policy") .. " layout " .. index)
        assertEqual(actual.buttonStyle, nil,
            (message or "policy") .. " style " .. index)
    end
end

local function testInvalidInputs()
    local policy, errorCode = UF.CompileNativeAuraPolicy("PLAYER", {})
    assertEqual(policy, nil, "invalid base policy")
    assertEqual(errorCode, "INVALID_BASE_FILTER", "invalid base error")

    policy, errorCode = UF.CompileNativeAuraPolicy("HELPFUL", nil)
    assertEqual(policy, nil, "missing filters policy")
    assertEqual(errorCode, "INVALID_FILTER_SCHEMA", "missing filters error")

    policy, errorCode = UF.CompileNativeAuraPolicy("HARMFUL", {
        castByMe = 1,
    })
    assertEqual(policy, nil, "invalid boolean policy")
    assertEqual(errorCode, "INVALID_FILTER_SCHEMA", "invalid boolean error")
end

local function testEmptyPoliciesStayEmpty()
    local helpful = compile("HELPFUL", {})
    assertGroups(helpful, {}, "empty helpful")
    assertEqual(helpful.empty, true, "empty helpful state")
    assertEqual(helpful.requiresVisible, false, "empty helpful visible gate")
    assertEqual(helpful.requiresAssist, false, "empty helpful assist gate")
    assertEqual(helpful.degradations.perGroupLimit, false, "empty helpful limit")
    assertEqual(helpful.degradations.perGroupSort, false, "empty helpful sort")
    assertEqual(
        helpful.degradations.privateAuraSourceUnseparable,
        false,
        "empty helpful private source"
    )
    assertEqual(
        helpful.degradations.bossAuraUsesCuratedRaidInCombat,
        false,
        "empty helpful boss approximation"
    )

    local harmful = compile("HARMFUL", {
        bigDefensive = true,
        externalDefensive = true,
    })
    assertGroups(harmful, {}, "unsupported harmful source filters")
    assertEqual(harmful.empty, true, "unsupported harmful state")
end

local function testLegacyTruthTable()
    assertGroups(compile("HELPFUL", {
        castByMe = true,
    }), {
        {"player", "HELPFUL|PLAYER"},
    }, "cast by me")

    assertGroups(compile("HARMFUL", {
        isBossAura = true,
    }), {
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT"},
    }, "legacy boss choice uses curated encounter filter")

    assertGroups(compile("HELPFUL", {
        dispellable = true,
    }), {
        {"raidPlayerDispellable", "HELPFUL|RAID_PLAYER_DISPELLABLE"},
    }, "dispellable")

    local defensiveGroups = {
        {"bigDefensive", "HELPFUL|BIG_DEFENSIVE"},
        {"externalDefensive", "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE"},
    }
    assertGroups(compile("HELPFUL", {
        castByOthers = true,
    }), defensiveGroups, "cast by others")
    assertGroups(compile("HELPFUL", {
        castByUnit = true,
    }), defensiveGroups, "cast by unit")

    assertGroups(compile("HELPFUL", {
        castByNPC = true,
    }), {
        {"raidInCombat", "HELPFUL|RAID_IN_COMBAT"},
        {
            "bigDefensive",
            "HELPFUL|BIG_DEFENSIVE|!RAID_IN_COMBAT",
        },
        {
            "externalDefensive",
            "HELPFUL|EXTERNAL_DEFENSIVE|!RAID_IN_COMBAT|!BIG_DEFENSIVE",
        },
    }, "helpful NPC")

    assertGroups(compile("HARMFUL", {
        castByNPC = true,
    }), {
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT"},
    }, "harmful NPC")

    assertGroups(compile("HARMFUL", {
        castByNPC = true,
        isBossAura = true,
    }), {
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT"},
    }, "deduplicated raid filter")
end

local function testCanonicalDisjointOrder()
    local filters = {
        player = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
    }

    local policy = compile("HELPFUL", filters)
    assertGroups(policy, {
        {"player", "HELPFUL|PLAYER"},
        {"raidInCombat", "HELPFUL|RAID_IN_COMBAT|!PLAYER"},
        {
            "raidPlayerDispellable",
            "HELPFUL|RAID_PLAYER_DISPELLABLE|!PLAYER|!RAID_IN_COMBAT",
        },
        {
            "bigDefensive",
            "HELPFUL|BIG_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT"
                .. "|!RAID_PLAYER_DISPELLABLE",
        },
        {
            "externalDefensive",
            "HELPFUL|EXTERNAL_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT"
                .. "|!RAID_PLAYER_DISPELLABLE|!BIG_DEFENSIVE",
        },
    }, "canonical disjoint")
    assertEqual(policy.empty, false, "canonical empty state")
    assertEqual(policy.requiresVisible, true, "canonical visible gate")
    assertEqual(policy.requiresAssist, true, "canonical assist gate")
    assertEqual(policy.degradations.perGroupLimit, true, "canonical limit")
    assertEqual(policy.degradations.perGroupSort, true, "canonical sort")
    assertEqual(
        policy.degradations.privateAuraSourceUnseparable,
        true,
        "canonical private source"
    )
    assertEqual(
        policy.degradations.bossAuraUsesCuratedRaidInCombat,
        false,
        "canonical raid category is not a boss approximation"
    )
end

local function testGateAndDegradationMetadata()
    local player = compile("HARMFUL", {
        player = true,
    })
    assertEqual(player.requiresVisible, true, "player visible gate")
    assertEqual(player.requiresAssist, false, "player assist gate")
    assertEqual(player.degradations.perGroupLimit, false, "single group limit")
    assertEqual(player.degradations.perGroupSort, false, "single group sort")
    assertEqual(
        player.degradations.privateAuraSourceUnseparable,
        true,
        "single group private source"
    )
    assertEqual(
        player.degradations.bossAuraUsesCuratedRaidInCombat,
        false,
        "single player group boss approximation"
    )

    local defensive = compile("HELPFUL", {
        bigDefensive = true,
        externalDefensive = true,
    })
    assertEqual(defensive.requiresVisible, false, "defensive visible gate")
    assertEqual(defensive.requiresAssist, true, "defensive assist gate")
    assertEqual(defensive.degradations.perGroupLimit, true, "defensive limit")
    assertEqual(defensive.degradations.perGroupSort, true, "defensive sort")

    -- Blizzard's 68914 Edit Mode fixture treats RAID_IN_COMBAT as a RAID
    -- substring and therefore selects its raid Bleed sample, not its
    -- non-raid isBossAura Poison sample. This test records BFI's existing
    -- curated contract; exact native boss-candidate coverage lives in AF and
    -- the user-facing semantic decision remains step #6.
    local raid = compile("HARMFUL", {
        isBossAura = true,
    })
    assertEqual(raid.requiresVisible, false, "raid visible gate")
    assertEqual(raid.requiresAssist, false, "raid assist gate")
    assertEqual(
        raid.degradations.privateAuraSourceUnseparable,
        true,
        "real provider includes inseparable private auras"
    )
    assertEqual(
        raid.degradations.bossAuraUsesCuratedRaidInCombat,
        true,
        "legacy boss choice is not an exact boss candidate filter"
    )
    assertEqual(
        raid.groups[1].candidateFilters,
        nil,
        "legacy boss choice emitted an exact native boss predicate"
    )
end

local function testCanonicalCompatibilityMaterialization()
    local legacy = {
        castByMe = true,
        castByOthers = false,
        castByUnit = true,
        castByNPC = true,
        isBossAura = false,
        dispellable = true,
    }
    local resolved = F.ResolveUnitFrameAuraFilters("HELPFUL", legacy)
    assertEqual(resolved.player, true, "legacy player resolution")
    assertEqual(resolved.raidInCombat, true, "legacy raid resolution")
    assertEqual(
        resolved.raidPlayerDispellable,
        true,
        "legacy dispel resolution"
    )
    assertEqual(resolved.bigDefensive, true, "legacy big defensive")
    assertEqual(resolved.externalDefensive, true, "legacy external defensive")

    assertEqual(
        F.SetUnitFrameAuraFilter(
            "HELPFUL",
            legacy,
            "bigDefensive",
            false
        ),
        true,
        "materialize canonical state"
    )
    assertEqual(legacy.player, true, "materialized player")
    assertEqual(legacy.raidInCombat, true, "materialized raid")
    assertEqual(
        legacy.raidPlayerDispellable,
        true,
        "materialized dispel"
    )
    assertEqual(legacy.bigDefensive, false, "materialized big defensive")
    assertEqual(
        legacy.externalDefensive,
        true,
        "materialized external defensive"
    )
    assertEqual(legacy.castByMe, nil, "retired castByMe removed")
    assertEqual(legacy.castByNPC, nil, "retired castByNPC removed")
    assertEqual(legacy.isBossAura, nil, "retired boss alias removed")

    legacy.castByNPC = true
    resolved = F.ResolveUnitFrameAuraFilters("HELPFUL", legacy)
    assertEqual(
        resolved.raidInCombat,
        true,
        "canonical state remains authoritative"
    )
    assertEqual(
        resolved.bigDefensive,
        false,
        "hidden legacy alias cannot re-enable category"
    )

    local matchFilters =
        F.GetSecretSafeAuraMatchFilters("HELPFUL", legacy)
    local expected = {
        "HELPFUL|PLAYER",
        "HELPFUL|RAID_IN_COMBAT",
        "HELPFUL|RAID_PLAYER_DISPELLABLE",
        "HELPFUL|EXTERNAL_DEFENSIVE",
    }
    assertEqual(#matchFilters, #expected, "canonical match filter count")
    for index, filterString in ipairs(expected) do
        assertEqual(
            matchFilters[index],
            filterString,
            "canonical match filter " .. index
        )
    end

    assertEqual(
        F.SetUnitFrameAuraFilter(
            "HARMFUL",
            legacy,
            "bigDefensive",
            true
        ),
        false,
        "harmful defensive category rejected"
    )
end

local function testFreshDeterministicOutput()
    local filters = {
        player = true,
        raidInCombat = true,
        futureField = true,
    }
    local first = compile("HARMFUL", filters)
    local second = compile("HARMFUL", filters)

    assertTrue(first ~= second, "policy tables are shared")
    assertTrue(first.groups ~= second.groups, "group lists are shared")
    assertTrue(first.groups[1] ~= second.groups[1], "group descriptors are shared")
    assertTrue(
        first.degradations ~= second.degradations,
        "degradation tables are shared"
    )
    assertGroups(first, {
        {"player", "HARMFUL|PLAYER"},
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT|!PLAYER"},
    }, "first deterministic")
    assertGroups(second, {
        {"player", "HARMFUL|PLAYER"},
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT|!PLAYER"},
    }, "second deterministic")

    first.groups[1].filterString = "BROKEN"
    first.degradations.perGroupLimit = false
    local third = compile("HARMFUL", filters)
    assertGroups(third, {
        {"player", "HARMFUL|PLAYER"},
        {"raidInCombat", "HARMFUL|RAID_IN_COMBAT|!PLAYER"},
    }, "third deterministic")
    assertEqual(third.degradations.perGroupLimit, true, "fresh degradation")

    assertEqual(filters.player, true, "input player mutation")
    assertEqual(filters.raidInCombat, true, "input raid mutation")
    assertEqual(filters.futureField, true, "input future field mutation")
end

testInvalidInputs()
testEmptyPoliciesStayEmpty()
testLegacyTruthTable()
testCanonicalDisjointOrder()
testGateAndDegradationMetadata()
testCanonicalCompatibilityMaterialization()
testFreshDeterministicOutput()

assertEqual(forbiddenCalls, 0, "forbidden dependency calls")
print("unit_frame_aura_policy_test.lua: ok")
