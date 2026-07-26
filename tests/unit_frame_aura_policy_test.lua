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
    assertEqual(
        helpful.degradations.legacySourceFilterUsesSuperset,
        false,
        "empty helpful source migration"
    )

    local harmful = compile("HARMFUL", {
        bigDefensive = true,
        externalDefensive = true,
    })
    assertGroups(harmful, {}, "unsupported harmful source filters")
    assertEqual(harmful.empty, true, "unsupported harmful state")
end

local function testLegacyTruthTable()
    local player = compile("HELPFUL", {
        castByMe = true,
    })
    assertGroups(player, {
        {"player", "HELPFUL|PLAYER"},
    }, "cast by me")
    assertEqual(player.requiresVisible, true, "player visibility gate")

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

    local others = compile("HELPFUL", {
        castByOthers = true,
    })
    assertGroups(others, {
        {"notPlayer", "HELPFUL|!PLAYER"},
    }, "cast by others")
    assertEqual(
        others.degradations.legacySourceFilterUsesSuperset,
        true,
        "cast by others widens to not-player"
    )

    local npc = compile("HARMFUL", {
        castByNPC = true,
    })
    assertGroups(npc, {
        {"notPlayer", "HARMFUL|!PLAYER"},
    }, "cast by NPC")
    assertEqual(
        npc.degradations.legacySourceFilterUsesSuperset,
        true,
        "cast by NPC widens to not-player"
    )

    local exactNotPlayer = compile("HARMFUL", {
        castByOthers = true,
        castByNPC = true,
    })
    assertGroups(exactNotPlayer, {
        {"notPlayer", "HARMFUL|!PLAYER"},
    }, "other-player and NPC union")
    assertEqual(
        exactNotPlayer.degradations.legacySourceFilterUsesSuperset,
        false,
        "complete not-player source union"
    )

    local unit = compile("HELPFUL", {
        castByUnit = true,
    })
    assertGroups(unit, {
        {"all", "HELPFUL"},
    }, "cast by unit")
    assertEqual(
        unit.degradations.legacySourceFilterUsesSuperset,
        true,
        "cast by unit widens to all"
    )
    assertEqual(unit.requiresVisible, false, "all visibility gate")
    assertEqual(unit.requiresAssist, false, "all assist gate")

    local partialAll = compile("HARMFUL", {
        castByMe = true,
        castByOthers = true,
    })
    assertGroups(partialAll, {
        {"all", "HARMFUL"},
    }, "player plus widened not-player")
    assertEqual(
        partialAll.degradations.legacySourceFilterUsesSuperset,
        true,
        "partial source union widens to all"
    )

    local exactAll = compile("HELPFUL", {
        castByMe = true,
        castByOthers = true,
        castByUnit = true,
        castByNPC = true,
        isBossAura = true,
        dispellable = true,
    })
    assertGroups(exactAll, {
        {"all", "HELPFUL"},
    }, "complete legacy source union")
    assertEqual(
        exactAll.degradations.legacySourceFilterUsesSuperset,
        false,
        "complete legacy source union is exact"
    )
    assertEqual(
        exactAll.degradations.bossAuraUsesCuratedRaidInCombat,
        false,
        "all makes the boss approximation redundant"
    )
end

local function testLegacySourceResolutionExhaustive()
    local function enabled(mask, bitIndex)
        return math.floor(mask / (2 ^ bitIndex)) % 2 == 1
    end

    for mask = 0, 127 do
        local legacy = {
            castByMe = enabled(mask, 0),
            castByOthers = enabled(mask, 1),
            castByUnit = enabled(mask, 2),
            castByNPC = enabled(mask, 3),
            isBossAura = enabled(mask, 4),
            dispellable = enabled(mask, 5),
            canBeDispelled = enabled(mask, 6),
        }
        local exactNotPlayer =
            legacy.castByOthers and legacy.castByNPC
        local expectedNotPlayer =
            legacy.castByOthers or legacy.castByNPC
        local exactAll = legacy.castByMe and exactNotPlayer
        local expectedAll =
            legacy.castByUnit
            or (legacy.castByMe and expectedNotPlayer)

        for _, baseFilter in ipairs({"HELPFUL", "HARMFUL"}) do
            local resolved, migration =
                F.ResolveUnitFrameAuraFilters(baseFilter, legacy)
            local label = baseFilter .. " legacy mask " .. mask
            assertEqual(resolved.all, expectedAll, label .. " all")
            assertEqual(
                resolved.player,
                not expectedAll and legacy.castByMe,
                label .. " player"
            )
            assertEqual(
                resolved.notPlayer,
                not expectedAll and expectedNotPlayer,
                label .. " not-player"
            )
            assertEqual(
                resolved.raidInCombat,
                not expectedAll and legacy.isBossAura,
                label .. " raid"
            )
            assertEqual(
                resolved.raidPlayerDispellable,
                not expectedAll
                    and (
                        legacy.dispellable
                        or legacy.canBeDispelled
                    ),
                label .. " dispel"
            )
            assertEqual(
                resolved.bigDefensive,
                false,
                label .. " big defensive"
            )
            assertEqual(
                resolved.externalDefensive,
                false,
                label .. " external defensive"
            )
            assertEqual(
                migration.legacySourceFilterUsesSuperset,
                (expectedNotPlayer and not exactNotPlayer)
                    or (expectedAll and not exactAll),
                label .. " source widening"
            )
        end
    end
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
    assertEqual(policy.requiresVisible, false, "canonical visible gate")
    assertEqual(policy.requiresAssist, false, "canonical assist gate")
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

local function testNotPlayerDisjointOrderAndAllCollapse()
    local policy = compile("HELPFUL", {
        notPlayer = true,
        raidInCombat = true,
        raidPlayerDispellable = true,
        bigDefensive = true,
        externalDefensive = true,
    })
    assertGroups(policy, {
        {"notPlayer", "HELPFUL|!PLAYER"},
        {"raidInCombat", "HELPFUL|RAID_IN_COMBAT|PLAYER"},
        {
            "raidPlayerDispellable",
            "HELPFUL|RAID_PLAYER_DISPELLABLE|PLAYER"
                .. "|!RAID_IN_COMBAT",
        },
        {
            "bigDefensive",
            "HELPFUL|BIG_DEFENSIVE|PLAYER|!RAID_IN_COMBAT"
                .. "|!RAID_PLAYER_DISPELLABLE",
        },
        {
            "externalDefensive",
            "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER|!RAID_IN_COMBAT"
                .. "|!RAID_PLAYER_DISPELLABLE|!BIG_DEFENSIVE",
        },
    }, "not-player disjoint")
    for _, group in ipairs(policy.groups) do
        assertEqual(
            group.filterString:find("!!", 1, true),
            nil,
            "native filter contains double negation"
        )
    end
    assertEqual(
        policy.requiresVisible,
        false,
        "mixed not-player union visibility gate"
    )
    assertEqual(
        policy.requiresAssist,
        false,
        "mixed not-player union assist gate"
    )

    local all = compile("HARMFUL", {
        all = false,
        player = true,
        notPlayer = true,
        raidInCombat = true,
    })
    assertGroups(all, {
        {"all", "HARMFUL"},
    }, "player complement collapse")
    assertEqual(all.requiresVisible, false, "collapsed all visibility gate")
    assertEqual(all.requiresAssist, false, "collapsed all assist gate")
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

    local mixed = compile("HELPFUL", {
        player = true,
        bigDefensive = true,
    })
    assertEqual(
        mixed.requiresVisible,
        false,
        "mixed union whole-holder visibility gate"
    )
    assertEqual(
        mixed.requiresAssist,
        false,
        "mixed union whole-holder assist gate"
    )

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
        castByOthers = true,
        castByUnit = true,
        castByNPC = true,
        isBossAura = true,
        dispellable = true,
    }
    local resolved, migration =
        F.ResolveUnitFrameAuraFilters("HELPFUL", legacy)
    assertEqual(resolved.all, true, "legacy all resolution")
    assertEqual(resolved.player, false, "collapsed legacy player")
    assertEqual(resolved.notPlayer, false, "collapsed legacy not-player")
    assertEqual(resolved.raidInCombat, false, "collapsed legacy raid")
    assertEqual(
        migration.legacySourceFilterUsesSuperset,
        false,
        "complete source union migration"
    )

    assertEqual(
        F.SetUnitFrameAuraFilter(
            "HELPFUL",
            legacy,
            "raidInCombat",
            true
        ),
        true,
        "materialize canonical state"
    )
    assertEqual(legacy.all, false, "materialized all")
    assertEqual(legacy.player, false, "materialized player")
    assertEqual(legacy.notPlayer, false, "materialized not-player")
    assertEqual(legacy.raidInCombat, true, "materialized raid")
    assertEqual(
        legacy.raidPlayerDispellable,
        false,
        "materialized dispel"
    )
    assertEqual(legacy.bigDefensive, false, "materialized big defensive")
    assertEqual(
        legacy.externalDefensive,
        false,
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
        resolved.notPlayer,
        false,
        "hidden legacy alias cannot re-enable not-player"
    )

    local matchFilters =
        F.GetSecretSafeUnitFrameAuraMatchFilters(
            "HELPFUL",
            legacy
        )
    local expected = {
        "HELPFUL|RAID_IN_COMBAT",
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

    local notPlayer = {
        notPlayer = true,
    }
    matchFilters =
        F.GetSecretSafeUnitFrameAuraMatchFilters(
            "HARMFUL",
            notPlayer
        )
    assertEqual(#matchFilters, 1, "not-player match rule count")
    assertEqual(
        matchFilters[1].filterString,
        "HARMFUL|PLAYER",
        "not-player C-side filter"
    )
    assertEqual(
        matchFilters[1].matchWhenFilteredOut,
        true,
        "not-player complement direction"
    )

    matchFilters =
        F.GetSecretSafeUnitFrameAuraMatchFilters(
            "HELPFUL",
            {all = true}
        )
    assertEqual(#matchFilters, 1, "all match rule count")
    assertEqual(matchFilters[1], "HELPFUL", "all base match rule")
end

local function testNameplateProjectionRemainsScoped()
    local filters = F.GetSecretSafeAuraMatchFilters("HELPFUL", {
        castByOthers = true,
    })
    assertEqual(#filters, 2, "legacy nameplate source filter count")
    assertEqual(filters[1], "HELPFUL|BIG_DEFENSIVE",
        "legacy nameplate big defensive")
    assertEqual(filters[2], "HELPFUL|EXTERNAL_DEFENSIVE",
        "legacy nameplate external defensive")

    filters = F.GetSecretSafeAuraMatchFilters("HARMFUL", {
        castByNPC = true,
    })
    assertEqual(#filters, 1, "legacy nameplate NPC filter count")
    assertEqual(filters[1], "HARMFUL|RAID_IN_COMBAT",
        "legacy nameplate NPC projection")
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
testLegacySourceResolutionExhaustive()
testCanonicalDisjointOrder()
testNotPlayerDisjointOrderAndAllCollapse()
testGateAndDegradationMetadata()
testCanonicalCompatibilityMaterialization()
testNameplateProjectionRemainsScoped()
testFreshDeterministicOutput()

assertEqual(forbiddenCalls, 0, "forbidden dependency calls")
print("unit_frame_aura_policy_test.lua: ok")
