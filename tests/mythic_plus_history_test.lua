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

local function assertNear(actual, expected, tolerance, message)
    if math.abs(actual - expected) > tolerance then
        error(("%s: expected %.6f, got %.6f"):format(
            message or "values differ",
            expected,
            actual
        ), 2)
    end
end

local W = {}
local BFI = {
    modules = {
        UIWidgets = W,
    },
}

local chunk, loadError = loadfile("Modules/UIWidgets/MythicPlusHistory.lua")
assertEqual(type(chunk), "function", loadError or "module load")
chunk("BFInfinite", BFI)

local H = W.MythicPlusHistory
assertEqual(type(H), "table", "history helper")
assertEqual(H.SCHEMA_VERSION, 1, "schema version")

local store, character = H.EnsureStore(nil, "Tank-Realm")
assertEqual(store.schemaVersion, 1, "stored schema version")
assertEqual(store.characters["Tank-Realm"], character, "character store")
assertEqual(type(character.seasons), "table", "character seasons")

local sameStore, sameCharacter = H.EnsureStore(store, "Tank-Realm")
assertEqual(sameStore, store, "stable store")
assertEqual(sameCharacter, character, "stable character")

for index = 1, 205 do
    H.AppendPendingRun(character, {
        mapID = index,
        completed = true,
        damageMeterComplete = true,
    })
end
assertEqual(#character.pendingRuns, 200, "pending history cap")
assertEqual(character.pendingRuns[1].mapID, 6,
    "oldest pending run after cap")
assertEqual(character.pendingRuns[200].mapID, 205,
    "newest pending run after cap")
assertEqual(character.pendingRuns[200].historyPending, true,
    "pending run marker")
character.pendingRuns = {}

local fingerprint = H.MakePoolFingerprint({399, 249, 250, 399, "588"})
assertEqual(fingerprint, "v1:249,250,399,588", "sorted pool fingerprint")
assertEqual(H.MakePoolFingerprint({}), "v1:", "empty pool fingerprint")

local seasonOne, seasonOneKey = H.GetOrCreateSeason(
    store,
    "Tank-Realm",
    14,
    "v1:1,2",
    {observedAt = 100, label = "first"}
)
assertEqual(seasonOneKey, "14:v1:1,2", "season key")
assertEqual(seasonOne.metadata.label, "first", "season metadata")

local seasonTwo = H.GetOrCreateSeason(
    store,
    "Tank-Realm",
    15,
    fingerprint,
    {observedAt = 200}
)
assertTrue(seasonOne.archived, "previous season archived")
assertEqual(seasonOne.archivedAt, 200, "previous season archive time")
assertEqual(seasonTwo.archived, nil, "active season is not archived")

local eligibleRun = {
    completed = true,
    damageMeterComplete = true,
    elapsedSeconds = 1499,
    timeLimitSeconds = 1000,
}
local eligible, reason = H.IsBaselineEligible(eligibleRun)
assertEqual(eligible, true, "run below limit is eligible")
assertEqual(reason, nil, "eligible run reason")

eligible, reason = H.IsBaselineEligible({
    completed = true,
    damageMeterComplete = true,
    elapsedSeconds = 1500,
    timeLimitSeconds = 1000,
})
assertEqual(eligible, false, "run at 150 percent is excluded")
assertEqual(reason, "extended_learning_run", "extended run reason")

local ineligibleCases = {
    {{completed = false}, "incomplete_run"},
    {{abandoned = true}, "abandoned_run"},
    {{reset = true}, "reset_run"},
    {{practice = true}, "practice_run"},
    {{partialObservation = true}, "partial_run"},
    {{meterComplete = false}, "incomplete_meter"},
    {{meterReset = true}, "meter_reset"},
    {{rosterCorrupt = true}, "roster_corrupt"},
    {{sessionCorrupt = true}, "session_corrupt"},
}
for _, testCase in ipairs(ineligibleCases) do
    local run = testCase[1]
    if run.completed == nil then
        run.completed = true
    end
    if run.meterComplete == nil and testCase[2] ~= "incomplete_meter" then
        run.damageMeterComplete = true
    end
    run.elapsedSeconds = 100
    run.timeLimitSeconds = 1000
    eligible, reason = H.IsBaselineEligible(run)
    assertEqual(eligible, false, testCase[2] .. " eligibility")
    assertEqual(reason, testCase[2], testCase[2] .. " reason")
end

eligible, reason = H.IsBaselineEligible({
    completed = false,
    abandoned = true,
})
assertEqual(eligible, false, "abandoned incomplete run is excluded")
assertEqual(reason, "abandoned_run",
    "abandonment is preserved as the specific exclusion reason")

eligible, reason = H.IsBaselineEligible({
    completed = false,
    reset = true,
})
assertEqual(eligible, false, "reset incomplete run is excluded")
assertEqual(reason, "reset_run",
    "reset is preserved as the specific exclusion reason")

local integrityCases = {
    {{damageMeterComplete = false, meterReset = true}, "meter_reset"},
    {{damageMeterComplete = false, rosterCorrupt = true}, "roster_corrupt"},
    {{damageMeterComplete = false, sessionCorrupt = true}, "session_corrupt"},
}
for _, testCase in ipairs(integrityCases) do
    local run = testCase[1]
    run.completed = true
    run.elapsedSeconds = 100
    run.timeLimitSeconds = 1000
    eligible, reason = H.IsBaselineEligible(run)
    assertEqual(eligible, false, testCase[2] .. " precedence")
    assertEqual(reason, testCase[2], testCase[2] .. " precedence reason")
end

eligible, reason = H.IsBaselineEligible({
    baselineOverride = true,
    elapsedSeconds = 9999,
    timeLimitSeconds = 1,
})
assertEqual(eligible, true, "manual include")
assertEqual(reason, "manual_include", "manual include reason")

assertNear(H.GetDamageFactorFromPercent(125), 2.25, 0.000001,
    "damage modifier factor")
assertNear(H.NormalizeDamage(2250, 125), 1000, 0.000001,
    "normalized damage")
assertEqual(H.GetDamageFactorFromPercent(nil), nil, "missing modifier")
assertEqual(H.GetDamageFactorFromPercent(-100), nil, "invalid modifier")
assertEqual(H.NormalizeDamage("secret", 125), nil, "invalid raw damage")
assertEqual(H.NormalizeDamage(100, nil), nil,
    "missing modifier does not masquerade as normalized")

local collecting = H.BuildBaseline({1, 2, 3, 4}, "damage")
assertEqual(collecting.available, false, "four-run baseline unavailable")
assertEqual(collecting.sampleCount, 4, "collecting sample count")
assertEqual(collecting.maturity, "collecting", "collecting maturity")

local avoidable = H.BuildBaseline({100, 100, 100, 100, 100}, "avoidable")
assertEqual(avoidable.available, true, "five-run baseline available")
assertEqual(avoidable.maturity, "provisional", "five-run maturity")
assertNear(avoidable.center, 100, 0.000001, "avoidable center")
assertNear(avoidable.spread, 20, 0.000001, "avoidable spread floor")

local sparseAvoidable = H.BuildBaseline(
    {0, 0, 0, 0, 100},
    "avoidable"
)
assertNear(sparseAvoidable.center, 0, 0.000001,
    "sparse avoidable center")
assertNear(sparseAvoidable.spread, 20, 0.000001,
    "sparse avoidable history retains a non-zero spread")
assertEqual(
    H.AssessMetric(
        1,
        {0, 0, 0, 0, 100},
        "avoidable",
        true
    ).band,
    "green",
    "small values are not extreme against a sparse avoidable history"
)

local damage = H.BuildBaseline({100, 100, 100, 100, 100}, "damage")
assertNear(damage.spread, 10, 0.000001, "damage spread floor")

local zeroDamageAssessment = H.AssessMetric(
    1,
    {0, 0, 0, 0, 0},
    "damage",
    true
)
assertEqual(zeroDamageAssessment.score, 3,
    "zero-spread damage score uses a finite extreme")
assertEqual(zeroDamageAssessment.band, "red",
    "zero-spread damage remains an extreme band")

local interrupts = H.BuildBaseline({4, 4, 4, 4, 4}, "interrupt")
assertNear(interrupts.spread, 2, 0.000001, "interrupt spread floor")

local varied = H.BuildBaseline({0, 10, 20, 30, 40}, "damage")
assertNear(varied.center, 20, 0.000001, "weighted median")
assertNear(varied.mad, 10, 0.000001, "weighted MAD")
assertNear(varied.spread, 14.826, 0.000001, "scaled weighted MAD")

local recencyWeighted = H.BuildBaseline({
    0, 0, 0, 0, 0, 0,
    100, 100, 100, 100, 100,
}, "damage")
assertEqual(recencyWeighted.center, 100, "recent samples carry more weight")

local sixtyOne = {9999}
for index = 1, 60 do
    sixtyOne[#sixtyOne + 1] = 1
end
local capped = H.BuildBaseline(sixtyOne, "damage")
assertEqual(capped.sampleCount, 60, "baseline sample cap")
assertEqual(capped.center, 1, "cap keeps newest samples")

local ten = {}
for index = 1, 10 do ten[index] = 10 end
assertEqual(H.BuildBaseline(ten, "damage").maturity, "established",
    "ten-run maturity")
local twenty = {}
for index = 1, 20 do twenty[index] = 10 end
assertEqual(H.BuildBaseline(twenty, "damage").maturity, "mature",
    "twenty-run maturity")

local fixedBaseline = {
    available = true,
    center = 100,
    spread = 10,
}
assertNear(H.Score(120, fixedBaseline, true), 2, 0.000001,
    "adverse-high score")
assertNear(H.Score(120, fixedBaseline, false), -2, 0.000001,
    "adverse-low score")
assertEqual(H.GetBand(120.1 / 10 - 10), "red", "red boundary")
assertEqual(H.GetBand(2), "orange", "orange upper boundary")
assertEqual(H.GetBand(1), "yellow", "yellow upper boundary")
assertEqual(H.GetBand(0.5), "green", "green upper boundary")
assertEqual(H.GetBand(-0.5), "green", "green lower boundary")
assertEqual(H.GetBand(-1.5), "blue", "blue lower boundary")
assertEqual(H.GetBand(-1.5001), "purple", "purple boundary")

local zeroAvoidable = H.BuildBaseline({0, 0, 0, 0, 0}, "avoidable")
assertEqual(zeroAvoidable.zeroOnly, true, "zero-only avoidable baseline")
assertEqual(H.GetBand(H.Score(0, zeroAvoidable, true)), "green",
    "zero remains normal")
assertEqual(H.GetBand(H.Score(1, zeroAvoidable, true)), "red",
    "avoidable damage against zero baseline")
assertEqual(H.Score(1, zeroAvoidable, true), 3,
    "zero-only raw score is finite")
local firstNonZeroAvoidable = H.AssessMetric(
    1,
    {0, 0, 0, 0, 0},
    "avoidable",
    true
)
assertEqual(firstNonZeroAvoidable.band, "yellow",
    "first non-zero avoidable sample is cautious")
assertEqual(firstNonZeroAvoidable.textID, "above_zero_baseline",
    "zero baseline explanation")
local invalidCurrent = H.AssessMetric(
    "invalid",
    {0, 0, 0, 0, 0},
    "avoidable",
    true
)
assertEqual(invalidCurrent.band, "unrated",
    "invalid current value remains unrated")

local priorValues = {10, 10, 10, 10, 10}
local assessment = H.AssessMetric(100, priorValues, "damage", true)
assertEqual(#priorValues, 5, "assessment does not add current run")
assertEqual(assessment.sampleCount, 5, "assessment prior sample count")
assertEqual(assessment.band, "red", "assessment band")
assertEqual(assessment.colorID, "red", "assessment color identifier")
assertEqual(assessment.textID, "much_worse", "assessment text identifier")

local compactSeason = {maps = {}}
local runtimeRun = {
    completed = true,
    baselineEligible = true,
    mapID = 399,
    level = 13,
    elapsed = 1200,
    timeLimit = 1800,
    metrics = {
        group = {
            interrupts = {available = true, raw = 10},
        },
        players = {},
    },
    assessments = {
        group = {
            interrupts = {band = "green"},
        },
        players = {},
    },
    splits = {
        {key = "criteria:1", elapsed = 300},
    },
    pullSnapshots = {{pull = 1}},
    roster = {{guid = "Player-1"}},
    liveMeterSnapshot = {durationSeconds = 10},
    referenceSplits = {["criteria:1"] = {elapsed = 310}},
    objectives = {{key = "criteria:1"}},
    savedSplits = {["criteria:1"] = 300},
    meterStart = {durationSeconds = 0},
    meterEnd = {durationSeconds = 1200},
    timerID = 7,
    localClockStart = 100,
}
local _, compactRun = H.AddRunToHistory(compactSeason, 399, runtimeRun)
assertEqual(compactRun.metrics.group.interrupts.raw, 10,
    "baseline metrics are persisted")
assertEqual(compactRun.assessments.group.interrupts.band, "green",
    "debrief assessments are persisted")
assertEqual(compactRun.splits[1].elapsed, 300,
    "reference splits are persisted")
for _, field in ipairs({
    "pullSnapshots",
    "roster",
    "liveMeterSnapshot",
    "referenceSplits",
    "objectives",
    "savedSplits",
    "meterStart",
    "meterEnd",
    "timerID",
    "localClockStart",
}) do
    assertEqual(compactRun[field], nil,
        field .. " is excluded from compact history")
end
runtimeRun.metrics.group.interrupts.raw = 99
runtimeRun.splits[1].elapsed = 999
assertEqual(compactRun.metrics.group.interrupts.raw, 10,
    "stored metrics do not alias the runtime run")
assertEqual(compactRun.splits[1].elapsed, 300,
    "stored splits do not alias the runtime run")

local historySeason = {maps = {}}
for index = 1, 205 do
    H.AddRunToHistory(historySeason, 399, {
        completed = true,
        damageMeterComplete = true,
        elapsedSeconds = 1000,
        timeLimitSeconds = 1800,
        marker = index,
    })
end

local mapHistory = historySeason.maps[399]
assertEqual(#mapHistory.runs, 200, "summary history cap")
assertEqual(mapHistory.runs[1].historyID, 6, "oldest summary after cap")
assertEqual(mapHistory.runs[200].historyID, 205, "newest summary after cap")
assertEqual(#mapHistory.baselineRunIDs, 60, "baseline projection cap")
assertEqual(mapHistory.baselineRunIDs[1], 146, "oldest baseline projection")
assertEqual(mapHistory.baselineRunIDs[60], 205, "newest baseline projection")

local beforeExtended = #mapHistory.baselineRunIDs
local _, storedExtended = H.AddRunToHistory(historySeason, 399, {
    completed = true,
    damageMeterComplete = true,
    elapsedSeconds = 2700,
    timeLimitSeconds = 1800,
})
assertEqual(storedExtended.baselineEligible, false, "stored eligibility")
assertEqual(storedExtended.baselineReason, "extended_learning_run",
    "stored exclusion reason")
assertEqual(#mapHistory.baselineRunIDs, beforeExtended,
    "extended run is not projected into baseline")

print("mythic_plus_history_test.lua: ok")
