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

for _, path in ipairs({
    "Modules/UIWidgets/MythicPlusHistory.lua",
    "Modules/UIWidgets/MythicPlusAnalysis.lua",
}) do
    local chunk, loadError = loadfile(path)
    assertEqual(type(chunk), "function", loadError or path)
    chunk("BFInfinite", BFI)
end

local A = W.MythicPlusAnalysis
local snapshot = {
    durationSeconds = 120,
    group = {
        damageTaken = {available = true, value = 2250},
        avoidableDamageTaken = {available = true, value = 225},
        interrupts = {available = true, value = 10},
        deaths = {available = true, value = 1},
        damageDone = {available = true, value = 10000},
        dps = {available = true, value = 5000},
    },
    players = {
        {
            order = 1,
            guid = "Player-1",
            name = "Tank",
            role = "TANK",
            specIconID = 1,
            metrics = {
                damageTaken = {available = true, value = 2250},
                avoidableDamageTaken = {available = true, value = 225},
                interrupts = {available = true, value = 10},
                deaths = {available = true, value = 1},
                damageDone = {available = true, value = 10000},
                dps = {available = true, value = 5000},
            },
            topAvoidableSpells = {
                {spellID = 10, totalAmount = 100},
            },
        },
    },
}

local metrics = assert(A.BuildRunMetrics(snapshot, 125, 120))
assertNear(metrics.group.damageTaken.normalized, 1000, 0.000001,
    "normalized group damage")
assertNear(metrics.group.damageTaken.normalizedPerMinute, 500, 0.000001,
    "normalized damage rate")
assertNear(metrics.group.interrupts.perMinute, 5, 0.000001,
    "interrupt rate")
assertEqual(metrics.players[1].topAvoidableSpells[1].spellID, 10,
    "avoidable drilldown copied")

local fallbackMetrics = assert(A.BuildRunMetrics(snapshot, 125, 0))
assertEqual(fallbackMetrics.durationSeconds, 120,
    "zero combat duration falls back to snapshot duration")
local nan = 0 / 0
fallbackMetrics = assert(A.BuildRunMetrics(snapshot, 125, nan))
assertEqual(fallbackMetrics.durationSeconds, 120,
    "invalid combat duration falls back to snapshot duration")

local rawOnlyMetrics = assert(A.BuildRunMetrics(snapshot, nil, 120))
assertEqual(rawOnlyMetrics.group.damageTaken.available, true,
    "raw damage remains displayable without a key modifier")
assertEqual(rawOnlyMetrics.group.damageTaken.raw, 2250,
    "raw damage is retained without normalization")
assertEqual(rawOnlyMetrics.group.damageTaken.normalized, nil,
    "missing modifier omits normalized damage")
assertEqual(rawOnlyMetrics.group.damageTaken.normalizationAvailable, false,
    "missing modifier is explicit")

local season = {
    maps = {
        [399] = {
            runs = {},
        },
    },
}
for index = 1, 5 do
    season.maps[399].runs[index] = {
        baselineEligible = true,
        observerRole = "TANK",
        observerSpecID = 73,
        metrics = {
            group = {
                damageTaken = {available = true, normalized = 1000},
                avoidableDamageTaken = {available = true, normalized = 100},
                interrupts = {available = true, raw = 5},
            },
            players = {
                {
                    guid = "Player-1",
                    role = "TANK",
                    specIconID = 1,
                    metrics = {
                        damageTaken = {available = true, normalized = 1000},
                        avoidableDamageTaken = {
                            available = true,
                            normalized = 100,
                        },
                        interrupts = {available = true, raw = 5},
                    },
                },
            },
        },
    }
end

local run = {
    mapID = 399,
    observerRole = "TANK",
    observerSpecID = 73,
    metrics = metrics,
}
local assessments = A.AssessRun(run, season)
assertEqual(assessments.group.damageTaken.sampleCount, 5,
    "group comparable sample count")
assertEqual(assessments.group.damageTaken.band, "green",
    "group damage band")
assertEqual(assessments.group.interrupts.band, "purple",
    "more interrupts are favorable")
assertEqual(
    assessments.players["Player-1"].avoidableDamageTaken.sampleCount,
    5,
    "player comparable sample count"
)

run.observerSpecID = 72
assessments = A.AssessRun(run, season)
assertEqual(assessments.group.damageTaken.sampleCount, 0,
    "observer spec contexts remain separate")

run.observerSpecID = 73
for _, priorRun in ipairs(season.maps[399].runs) do
    priorRun.observerSpecID = nil
end
assessments = A.AssessRun(run, season)
assertEqual(assessments.group.damageTaken.sampleCount, 0,
    "missing observer context is not merged with a known spec")

for _, priorRun in ipairs(season.maps[399].runs) do
    priorRun.observerSpecID = 73
    priorRun.metrics.players[1].specIconID = nil
end
assessments = A.AssessRun(run, season)
assertEqual(
    assessments.players["Player-1"].damageTaken.sampleCount,
    0,
    "missing player spec context is not merged with a known spec"
)

local malformedMetrics = assert(A.BuildRunMetrics({
    durationSeconds = 10,
    group = {},
    players = "invalid",
}, 0))
assertEqual(#malformedMetrics.players, 0,
    "malformed player collections are ignored")

print("mythic_plus_analysis_test.lua: ok")
