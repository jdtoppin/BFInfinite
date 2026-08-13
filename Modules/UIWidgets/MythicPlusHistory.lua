---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets

local H = {}
W.MythicPlusHistory = H

H.SCHEMA_VERSION = 1
H.MINIMUM_BASELINE_SAMPLES = 5
H.MAXIMUM_BASELINE_SAMPLES = 60
H.MAXIMUM_RUN_HISTORY = 200

local HALF_LIFE_RUNS = 10
local MAD_SCALE = 1.4826
local EXTREME_SCORE = 3

local bandText = {
    red = "much_worse",
    orange = "worse",
    yellow = "slightly_worse",
    green = "within_norm",
    blue = "better",
    purple = "much_better",
    unrated = "collecting",
}

local RUN_HISTORY_FIELDS = {
    "schemaVersion",
    "mapID",
    "mapName",
    "mapTexture",
    "level",
    "affixes",
    "affixKey",
    "wasCharged",
    "timeLimit",
    "timeLimitSeconds",
    "elapsed",
    "elapsedSeconds",
    "startedAt",
    "completedAt",
    "seasonID",
    "seasonKey",
    "damageModifierPercent",
    "healthModifierPercent",
    "observerRole",
    "observerSpecID",
    "completed",
    "abandoned",
    "reset",
    "onTime",
    "upgradeLevels",
    "practice",
    "scoreEligible",
    "partialObservation",
    "pullCount",
    "combatSeconds",
    "deaths",
    "deathTimeLost",
    "damageMeterComplete",
    "meterComplete",
    "damageMeterReset",
    "meterReset",
    "rosterCorrupt",
    "sessionCorrupt",
    "baselineOverride",
    "baselineEligible",
    "baselineReason",
    "metricsReason",
    "meterDeltaReason",
    "metrics",
    "assessments",
    "splits",
}

local function copyHistoryValue(value, ancestors)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean"
        or valueType == "number" or valueType == "string"
    then
        return value
    elseif valueType ~= "table" then
        return nil
    end

    ancestors = ancestors or {}
    if ancestors[value] then
        return nil
    end
    ancestors[value] = true

    local result = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType == "boolean" or keyType == "number"
            or keyType == "string"
        then
            result[key] = copyHistoryValue(child, ancestors)
        end
    end
    ancestors[value] = nil
    return result
end

local function makeStoredRun(run)
    local stored = {}
    for _, field in ipairs(RUN_HISTORY_FIELDS) do
        stored[field] = copyHistoryValue(run[field])
    end
    return stored
end

function H.CopyRunForStorage(run)
    if type(run) ~= "table" then return nil end
    return makeStoredRun(run)
end

function H.AppendPendingRun(character, run)
    if type(character) ~= "table" or type(run) ~= "table" then
        return nil
    end
    if type(character.pendingRuns) ~= "table" then
        character.pendingRuns = {}
    end

    local storedRun = H.CopyRunForStorage(run)
    storedRun.historyPending = true
    character.pendingRuns[#character.pendingRuns + 1] = storedRun
    while #character.pendingRuns > H.MAXIMUM_RUN_HISTORY do
        table.remove(character.pendingRuns, 1)
    end
    return storedRun
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function getMaturity(sampleCount)
    if sampleCount < H.MINIMUM_BASELINE_SAMPLES then
        return "collecting"
    elseif sampleCount < 10 then
        return "provisional"
    elseif sampleCount < 20 then
        return "established"
    end
    return "mature"
end

local function makeSeasonKey(internalSeasonID, poolFingerprint)
    return tostring(internalSeasonID) .. ":" .. tostring(poolFingerprint)
end

function H.EnsureStore(store, characterKey)
    if type(store) ~= "table" then
        store = {}
    end

    store.schemaVersion = H.SCHEMA_VERSION
    if type(store.characters) ~= "table" then
        store.characters = {}
    end

    characterKey = tostring(characterKey or "unknown")
    local character = store.characters[characterKey]
    if type(character) ~= "table" then
        character = {}
        store.characters[characterKey] = character
    end
    if type(character.seasons) ~= "table" then
        character.seasons = {}
    end

    return store, character
end

function H.MakePoolFingerprint(mapIDs)
    local copy, seen = {}, {}
    if type(mapIDs) == "table" then
        for _, value in ipairs(mapIDs) do
            local mapID = tonumber(value)
            if mapID and mapID == math.floor(mapID) and not seen[mapID] then
                seen[mapID] = true
                copy[#copy + 1] = mapID
            end
        end
    end

    table.sort(copy)
    for index, mapID in ipairs(copy) do
        copy[index] = tostring(mapID)
    end
    return "v1:" .. table.concat(copy, ",")
end

function H.GetOrCreateSeason(
    store,
    characterKey,
    internalSeasonID,
    poolFingerprint,
    metadata
)
    local normalizedStore, character = H.EnsureStore(store, characterKey)
    local seasonKey = makeSeasonKey(internalSeasonID, poolFingerprint)
    local season = character.seasons[seasonKey]

    if type(season) ~= "table" then
        season = {
            internalSeasonID = internalSeasonID,
            poolFingerprint = poolFingerprint,
            maps = {},
            metadata = {},
        }
        character.seasons[seasonKey] = season
    end
    if type(season.maps) ~= "table" then
        season.maps = {}
    end
    if type(season.metadata) ~= "table" then
        season.metadata = {}
    end

    if type(metadata) == "table" then
        for key, value in pairs(metadata) do
            season.metadata[key] = value
        end
    end

    local previousKey = character.activeSeasonKey
    if previousKey and previousKey ~= seasonKey then
        local previousSeason = character.seasons[previousKey]
        if type(previousSeason) == "table" then
            previousSeason.archived = true
            if metadata and metadata.observedAt then
                previousSeason.archivedAt = metadata.observedAt
            end
        end
    end

    season.archived = nil
    season.archivedAt = nil
    character.activeSeasonKey = seasonKey

    return season, seasonKey, normalizedStore
end

function H.IsBaselineEligible(run, limitMultiplier)
    if type(run) ~= "table" then
        return false, "invalid_run"
    end

    if run.baselineOverride ~= nil then
        if run.baselineOverride then
            return true, "manual_include"
        end
        return false, "manual_exclude"
    end

    if run.abandoned then
        return false, "abandoned_run"
    elseif run.reset then
        return false, "reset_run"
    elseif run.completed ~= true then
        return false, "incomplete_run"
    elseif run.practice then
        return false, "practice_run"
    elseif run.partialObservation then
        return false, "partial_run"
    end

    local meterComplete = run.damageMeterComplete
    if meterComplete == nil then
        meterComplete = run.meterComplete
    end
    if run.damageMeterReset or run.meterReset then
        return false, "meter_reset"
    elseif run.rosterCorrupt then
        return false, "roster_corrupt"
    elseif run.sessionCorrupt then
        return false, "session_corrupt"
    elseif meterComplete ~= true then
        return false, "incomplete_meter"
    end

    local elapsed = run.elapsedSeconds or run.elapsed
    local timeLimit = run.timeLimitSeconds or run.timeLimit
    if not isFiniteNumber(elapsed) or not isFiniteNumber(timeLimit)
        or elapsed < 0 or timeLimit <= 0
    then
        return false, "missing_timing"
    end

    if not isFiniteNumber(limitMultiplier) or limitMultiplier <= 0 then
        limitMultiplier = 1.5
    end
    if elapsed >= timeLimit * limitMultiplier then
        return false, "extended_learning_run"
    end

    return true
end

function H.GetDamageFactorFromPercent(apiPercent)
    if not isFiniteNumber(apiPercent) then
        return nil
    end

    local factor = 1 + apiPercent / 100
    if not isFiniteNumber(factor) or factor <= 0 then
        return nil
    end
    return factor
end

function H.NormalizeDamage(raw, modifierPercent)
    if not isFiniteNumber(raw) then
        return nil
    end
    local factor = H.GetDamageFactorFromPercent(modifierPercent)
    if not factor then return nil end
    return raw / factor
end

local function buildWeightedSamples(values)
    local samples = {}
    if type(values) ~= "table" then
        return samples
    end

    local firstIndex = math.max(1, #values - H.MAXIMUM_BASELINE_SAMPLES + 1)
    local newestIndex = #values
    for index = firstIndex, newestIndex do
        local candidate = values[index]
        local value, age
        if type(candidate) == "table" then
            value = candidate.value
            age = candidate.age
        else
            value = candidate
        end

        if isFiniteNumber(value) then
            if not isFiniteNumber(age) or age < 0 then
                age = newestIndex - index
            end
            samples[#samples + 1] = {
                value = value,
                weight = 2 ^ (-age / HALF_LIFE_RUNS),
            }
        end
    end
    return samples
end

local function weightedMedian(samples, valueKey)
    local sorted, totalWeight = {}, 0
    for _, sample in ipairs(samples) do
        local value = sample[valueKey]
        if isFiniteNumber(value) and isFiniteNumber(sample.weight)
            and sample.weight > 0
        then
            sorted[#sorted + 1] = sample
            totalWeight = totalWeight + sample.weight
        end
    end
    if #sorted == 0 or totalWeight <= 0 then
        return nil
    end

    table.sort(sorted, function(left, right)
        return left[valueKey] < right[valueKey]
    end)

    local midpoint = totalWeight / 2
    local cumulative = 0
    for index, sample in ipairs(sorted) do
        cumulative = cumulative + sample.weight
        if cumulative >= midpoint then
            if cumulative == midpoint and sorted[index + 1] then
                return (sample[valueKey] + sorted[index + 1][valueKey]) / 2
            end
            return sample[valueKey]
        end
    end

    return sorted[#sorted][valueKey]
end

function H.BuildBaseline(values, metricKind)
    local samples = buildWeightedSamples(values)
    local sampleCount = #samples
    local baseline = {
        available = sampleCount >= H.MINIMUM_BASELINE_SAMPLES,
        sampleCount = sampleCount,
        maturity = getMaturity(sampleCount),
        metricKind = metricKind,
    }
    if not baseline.available then
        return baseline
    end

    local center = weightedMedian(samples, "value")
    for _, sample in ipairs(samples) do
        sample.deviation = math.abs(sample.value - center)
    end

    local mad = weightedMedian(samples, "deviation") or 0
    local spread = MAD_SCALE * mad
    local magnitude = math.abs(center)
    if metricKind == "avoidable" then
        local nonZeroSamples = {}
        for _, sample in ipairs(samples) do
            if sample.value ~= 0 then
                nonZeroSamples[#nonZeroSamples + 1] = sample
            end
        end
        local nonZeroCenter =
            weightedMedian(nonZeroSamples, "value") or 0
        spread = math.max(
            spread,
            magnitude * 0.20,
            math.abs(nonZeroCenter) * 0.20
        )
    elseif metricKind == "damage" then
        spread = math.max(spread, magnitude * 0.10)
    elseif metricKind == "interrupt" then
        spread = math.max(
            spread,
            1,
            math.sqrt(math.max(center, 0)),
            magnitude * 0.15
        )
    end

    baseline.center = center
    baseline.mad = mad
    baseline.spread = spread
    local allZero = true
    for _, sample in ipairs(samples) do
        if sample.value ~= 0 then
            allZero = false
            break
        end
    end
    baseline.zeroOnly = metricKind == "avoidable" and allZero

    return baseline
end

function H.Score(current, baseline, adverseWhenHigh)
    if not isFiniteNumber(current) or type(baseline) ~= "table"
        or not baseline.available or not isFiniteNumber(baseline.center)
    then
        return nil
    end

    if adverseWhenHigh == nil then
        adverseWhenHigh = true
    end

    if baseline.zeroOnly then
        if current == 0 then
            return 0
        elseif adverseWhenHigh then
            return current > 0 and EXTREME_SCORE or -EXTREME_SCORE
        end
        return current > 0 and -EXTREME_SCORE or EXTREME_SCORE
    end

    local difference = current - baseline.center
    if not adverseWhenHigh then
        difference = -difference
    end

    if not isFiniteNumber(baseline.spread) or baseline.spread <= 0 then
        if difference == 0 then
            return 0
        end
        return difference > 0 and EXTREME_SCORE or -EXTREME_SCORE
    end
    return difference / baseline.spread
end

function H.GetBand(score)
    if not isFiniteNumber(score) then
        if score == math.huge then
            return "red"
        elseif score == -math.huge then
            return "purple"
        end
        return "unrated"
    elseif score > 2 then
        return "red"
    elseif score > 1 then
        return "orange"
    elseif score > 0.5 then
        return "yellow"
    elseif score >= -0.5 then
        return "green"
    elseif score >= -1.5 then
        return "blue"
    end
    return "purple"
end

function H.AssessMetric(current, priorValues, metricKind, adverseWhenHigh)
    if adverseWhenHigh == nil then
        adverseWhenHigh = metricKind ~= "interrupt"
    end
    local baseline = H.BuildBaseline(priorValues, metricKind)
    local score = H.Score(current, baseline, adverseWhenHigh)
    local band = H.GetBand(score)
    local textID = bandText[band]

    -- A first non-zero avoidable sample after an all-zero baseline is useful
    -- but has no defensible spread yet. Flag it gently until non-zero history
    -- exists instead of presenting an artificial extreme.
    if baseline.zeroOnly and isFiniteNumber(current)
        and current > 0 and adverseWhenHigh
    then
        score = 0.75
        band = "yellow"
        textID = "above_zero_baseline"
    end

    return {
        value = current,
        adverseWhenHigh = adverseWhenHigh,
        baseline = baseline,
        baselineCenter = baseline.center,
        baselineSpread = baseline.spread,
        sampleCount = baseline.sampleCount,
        maturity = baseline.maturity,
        score = score,
        band = band,
        colorID = band,
        textID = textID,
    }
end

local function removeBaselineID(baselineRunIDs, historyID)
    for index = #baselineRunIDs, 1, -1 do
        if baselineRunIDs[index] == historyID then
            table.remove(baselineRunIDs, index)
        end
    end
end

function H.AddRunToHistory(season, mapID, run)
    if type(season) ~= "table" or type(run) ~= "table" then
        return nil
    end
    if type(season.maps) ~= "table" then
        season.maps = {}
    end

    mapID = mapID or "unknown"
    local mapHistory = season.maps[mapID]
    if type(mapHistory) ~= "table" then
        mapHistory = {}
        season.maps[mapID] = mapHistory
    end
    if type(mapHistory.runs) ~= "table" then
        mapHistory.runs = {}
    end
    if type(mapHistory.baselineRunIDs) ~= "table" then
        mapHistory.baselineRunIDs = {}
    end

    mapHistory.nextRunID = (mapHistory.nextRunID or 0) + 1
    local storedRun = H.CopyRunForStorage(run)
    storedRun.historyID = mapHistory.nextRunID

    local eligible, reason
    if run.baselineEligible == nil then
        eligible, reason = H.IsBaselineEligible(run)
    else
        eligible = run.baselineEligible == true
        reason = run.baselineReason
    end
    storedRun.baselineEligible = eligible
    storedRun.baselineReason = reason

    mapHistory.runs[#mapHistory.runs + 1] = storedRun
    if eligible then
        local ids = mapHistory.baselineRunIDs
        ids[#ids + 1] = storedRun.historyID
        while #ids > H.MAXIMUM_BASELINE_SAMPLES do
            table.remove(ids, 1)
        end
    end

    while #mapHistory.runs > H.MAXIMUM_RUN_HISTORY do
        local removed = table.remove(mapHistory.runs, 1)
        removeBaselineID(mapHistory.baselineRunIDs, removed.historyID)
    end

    return mapHistory, storedRun
end
