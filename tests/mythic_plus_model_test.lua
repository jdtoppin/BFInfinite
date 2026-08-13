local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
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

local chunk, loadError = loadfile("Modules/UIWidgets/MythicPlusModel.lua")
assertEqual(type(chunk), "function", loadError or "module load")
chunk("BFInfinite", BFI)

local M = W.MythicPlusModel
assertEqual(M.FormatClock(0), "0:00", "zero clock")
assertEqual(M.FormatClock(65), "1:05", "minute clock")
assertEqual(M.FormatClock(3661), "1:01:01", "hour clock")
assertEqual(M.FormatClock(-65, true), "-1:05", "negative clock")
assertEqual(M.FormatClock(65, true), "+1:05", "positive clock")
assertEqual(M.FormatClock(nil), "--:--", "missing clock")

local plusTwo, plusThree = M.CalculateBonusThresholds(1800, {})
assertNear(plusTwo, 1440, 0.000001, "standard plus two")
assertNear(plusThree, 1080, 0.000001, "standard plus three")

plusTwo, plusThree = M.CalculateBonusThresholds(1890, {152})
assertNear(plusTwo, 1530, 0.000001, "peril plus two")
assertNear(plusThree, 1170, 0.000001, "peril plus three")

assertNear(M.ModifierFactor(125), 2.25, 0.000001, "modifier factor")
local scaledElapsed, wasNormalized = M.ScaleReferenceElapsed(
    100,
    100,
    200,
    60
)
assertNear(scaledElapsed, 130, 0.000001,
    "only combat time is level-scaled")
assertEqual(wasNormalized, true, "scaled reference label")
scaledElapsed, wasNormalized = M.ScaleReferenceElapsed(100, 100, 200)
assertNear(scaledElapsed, 100, 0.000001,
    "missing combat context keeps raw reference")
assertEqual(wasNormalized, false, "raw fallback label")
assertEqual(M.MakeAffixKey({10, 2, 7}), "2-7-10", "affix key")

local mapHistory = {
    runs = {
        {completed = true, baselineEligible = true, splits = {{elapsed = 10}}},
        {completed = true, baselineEligible = false, splits = {{elapsed = 9}}},
    },
}
assertEqual(M.FindReferenceRun(mapHistory), mapHistory.runs[1],
    "latest eligible reference")

local historyWithEmptyLatest = {
    runs = {
        {
            completed = true,
            baselineEligible = true,
            splits = {{elapsed = 10}},
        },
        {
            completed = true,
            baselineEligible = true,
            splits = {},
        },
    },
}
assertEqual(
    M.FindReferenceRun(historyWithEmptyLatest),
    historyWithEmptyLatest.runs[1],
    "an empty latest run does not hide an older usable split reference"
)

local references = M.BuildReferenceSplits({
    level = 12,
    healthModifierPercent = 100,
    splits = {
        {key = "criteria:1", elapsed = 100, combatElapsed = 60},
    },
}, 200)
assertNear(references["criteria:1"].elapsed, 130, 0.000001,
    "reference split scaling")
assertEqual(references["criteria:1"].normalized, true,
    "reference normalization label")

local criteria = M.ReadScenarioCriteria({numCriteria = 2}, function(index)
    if index == 1 then
        return {
            completed = true,
            criteriaID = 11,
            description = "\226\156\147 Boss",
            quantity = 1,
            totalQuantity = 1,
        }
    end
    return {
        completed = false,
        criteriaID = 12,
        description = "Enemy Forces",
        isWeightedProgress = true,
        quantity = 0,
        quantityString = "42,50%",
        totalQuantity = 100,
    }
end)
assertEqual(criteria[1].description, "Boss", "objective prefix")

local run = {
    combatSeconds = 60,
    combatStartedElapsed = 90,
    referenceSplits = {
        ["criteria:11"] = {
            elapsed = 95,
            rawElapsed = 90,
            referenceLevel = 12,
            normalized = true,
        },
    },
}
local completions = M.UpdateObjectives(run, criteria, 100)
assertEqual(#completions, 1, "new completion")
assertEqual(run.objectives[1].elapsed, 100, "split capture")
assertEqual(run.objectives[1].combatElapsed, 70,
    "split captures cumulative combat time")
assertEqual(run.objectives[1].splitDelta, 5, "split delta")
assertNear(run.objectives[2].percent, 42.5, 0.000001,
    "localized weighted progress")
assertEqual(M.GetForcesObjective(run.objectives), run.objectives[2],
    "forces objective")
assertEqual(#M.GetBossObjectives(run.objectives), 1, "boss objectives")
assertEqual(M.AreObjectivesComplete(run.objectives), false,
    "incomplete objective set")

local deathAdjustedRun = {
    combatSeconds = 40,
    combatStartedElapsed = 50,
    deathTimeLost = 20,
}
M.UpdateObjectives(deathAdjustedRun, criteria, 100)
assertEqual(deathAdjustedRun.objectives[1].combatElapsed, 70,
    "split combat context excludes accumulated death penalties")

local percentOnlyCriteria = {
    {
        completed = false,
        criteriaID = 13,
        description = "Enemy Forces",
        isWeightedProgress = true,
        quantity = 42.5,
        totalQuantity = 200,
    },
}
local percentOnlyRun = {}
M.UpdateObjectives(percentOnlyRun, percentOnlyCriteria, 100)
assertNear(percentOnlyRun.objectives[1].percent, 42.5, 0.000001,
    "quantity fallback is already Blizzard's percentage")

completions = M.UpdateObjectives(run, criteria, 200)
assertEqual(#completions, 0, "completion captured only once")
assertEqual(run.objectives[1].elapsed, 100, "split remains stable")

local partialRun = {
    partialObservation = true,
    combatSeconds = 0,
}
completions = M.UpdateObjectives(partialRun, criteria, 400)
assertEqual(#completions, 0,
    "already-complete objectives do not invent partial-run splits")
assertEqual(partialRun.objectives[1].elapsed, nil,
    "pre-observed completion time remains unknown")
assertEqual(#partialRun.splits, 0,
    "unknown partial-run splits are not reference candidates")

criteria[1].completed = false
M.UpdateObjectives(partialRun, criteria, 420)
criteria[1].completed = true
completions = M.UpdateObjectives(partialRun, criteria, 450)
assertEqual(#completions, 1,
    "later observed completion in a partial run is captured")
assertEqual(partialRun.objectives[1].elapsed, 450,
    "observed partial-run split uses the real world timer")

local reconstructedPartial = {
    partialObservation = true,
    combatSeconds = 0,
}
local reconstructedCriteria = {
    {
        completed = true,
        criteriaID = 14,
        description = "Earlier Boss",
        elapsed = 50,
        quantity = 1,
        totalQuantity = 1,
    },
}
M.UpdateObjectives(reconstructedPartial, reconstructedCriteria, 400)
assertEqual(reconstructedPartial.objectives[1].elapsed, 350,
    "Blizzard-reported completion age reconstructs a partial split")
assertEqual(reconstructedPartial.objectives[1].combatElapsed, nil,
    "reconstructed pre-observation split does not invent combat context")

run.combatStartedElapsed = 10
run.combatSeconds = 5
assertNear(M.FinalizeCombat(run, 25), 15, 0.000001, "combat duration")
assertNear(run.combatSeconds, 20, 0.000001, "accumulated combat")
assertEqual(run.combatStartedElapsed, nil, "combat start cleared")

print("mythic_plus_model_test.lua: ok")
