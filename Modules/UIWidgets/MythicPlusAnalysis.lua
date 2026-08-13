---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets

local H = W.MythicPlusHistory
local A = {}
W.MythicPlusAnalysis = A

local max = math.max

local ASSESSMENT_DEFINITIONS = {
    {
        key = "damageTaken",
        kind = "damage",
        adverseWhenHigh = true,
        valueKey = "normalized",
    },
    {
        key = "avoidableDamageTaken",
        kind = "avoidable",
        adverseWhenHigh = true,
        valueKey = "normalized",
    },
    {
        key = "interrupts",
        kind = "interrupt",
        adverseWhenHigh = false,
        valueKey = "raw",
    },
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function buildDamageMetric(metric, modifierPercent, minutes)
    if type(metric) ~= "table" or metric.available ~= true
        or not isFiniteNumber(metric.value)
    then
        return {
            available = false,
            reason = type(metric) == "table" and metric.reason
                or "metric_unavailable",
        }
    end

    local normalized = H.NormalizeDamage(metric.value, modifierPercent)
    return {
        available = true,
        raw = metric.value,
        normalized = normalized,
        normalizedPerMinute = normalized and normalized / minutes or nil,
        rawPerMinute = metric.value / minutes,
        normalizationAvailable = normalized ~= nil,
        normalizationReason = normalized == nil
            and "modifier_unavailable" or nil,
    }
end

local function buildCountMetric(metric, minutes)
    if type(metric) ~= "table" or metric.available ~= true
        or not isFiniteNumber(metric.value)
    then
        return {
            available = false,
            reason = type(metric) == "table" and metric.reason
                or "metric_unavailable",
        }
    end

    return {
        available = true,
        raw = metric.value,
        perMinute = metric.value / minutes,
    }
end

local function copyTopSpells(spells)
    local result = {}
    if type(spells) ~= "table" then
        return result
    end

    for _, spell in ipairs(spells) do
        if type(spell) == "table" then
            result[#result + 1] = {
                spellID = spell.spellID,
                totalAmount = spell.totalAmount,
                amountPerSecond = spell.amountPerSecond,
                creatureName = spell.creatureName,
                isAvoidable = spell.isAvoidable,
                isDeadly = spell.isDeadly,
            }
        end
    end
    return result
end

local function buildMetricSet(source, modifierPercent, minutes)
    source = type(source) == "table" and source or {}
    return {
        damageTaken = buildDamageMetric(
            source.damageTaken,
            modifierPercent,
            minutes
        ),
        avoidableDamageTaken = buildDamageMetric(
            source.avoidableDamageTaken,
            modifierPercent,
            minutes
        ),
        interrupts = buildCountMetric(source.interrupts, minutes),
        deaths = buildCountMetric(source.deaths, minutes),
        damageDone = buildCountMetric(source.damageDone, minutes),
        dps = buildCountMetric(source.dps, minutes),
    }
end

function A.BuildRunMetrics(snapshot, modifierPercent, combatSeconds)
    if type(snapshot) ~= "table" then
        return nil, "snapshot_unavailable"
    end

    local duration = tonumber(combatSeconds)
    if not isFiniteNumber(duration) or duration <= 0 then
        duration = tonumber(snapshot.durationSeconds)
    end
    if not isFiniteNumber(duration) or duration <= 0 then
        return nil, "duration_unavailable"
    end
    local minutes = max(duration / 60, 1 / 60)

    local result = {
        durationSeconds = duration,
        damageModifierPercent = modifierPercent,
        group = buildMetricSet(snapshot.group, modifierPercent, minutes),
        players = {},
    }

    local sources = type(snapshot.players) == "table"
        and snapshot.players or {}
    for _, source in ipairs(sources) do
        if type(source) == "table"
            and type(source.guid) == "string"
            and source.guid ~= ""
        then
            result.players[#result.players + 1] = {
                order = source.order,
                guid = source.guid,
                name = source.name,
                realmName = source.realmName,
                className = source.className,
                classFilename = source.classFilename,
                role = source.role,
                specIconID = source.specIconID,
                metrics = buildMetricSet(
                    source.metrics,
                    modifierPercent,
                    minutes
                ),
                topAvoidableSpells = copyTopSpells(
                    source.topAvoidableSpells
                ),
                avoidableDrilldownAvailable =
                    source.avoidableDrilldownAvailable == true,
            }
        end
    end

    return result
end

local function sameObserverContext(currentRun, priorRun)
    if currentRun.observerRole ~= priorRun.observerRole then
        return false
    end
    if currentRun.observerSpecID ~= priorRun.observerSpecID then
        return false
    end
    return true
end

local function samePlayerContext(currentPlayer, priorPlayer)
    if currentPlayer.guid ~= priorPlayer.guid then
        return false
    end
    if currentPlayer.role ~= priorPlayer.role then
        return false
    end
    if currentPlayer.specIconID ~= priorPlayer.specIconID then
        return false
    end
    return true
end

local function getMapRuns(season, mapID)
    local mapHistory = type(season) == "table"
        and type(season.maps) == "table" and season.maps[mapID]
    if type(mapHistory) ~= "table"
        or type(mapHistory.runs) ~= "table"
    then
        return {}
    end
    return mapHistory.runs
end

local function findPlayer(players, currentPlayer)
    if type(players) ~= "table" then return end
    for _, priorPlayer in ipairs(players) do
        if type(priorPlayer) == "table"
            and samePlayerContext(currentPlayer, priorPlayer)
        then
            return priorPlayer
        end
    end
end

local function collectGroupValues(season, mapID, currentRun, definition)
    local values = {}
    for _, priorRun in ipairs(getMapRuns(season, mapID)) do
        if type(priorRun) == "table"
            and priorRun.baselineEligible
            and sameObserverContext(currentRun, priorRun)
            and type(priorRun.metrics) == "table"
        then
            local group = priorRun.metrics.group
            local metric = type(group) == "table"
                and group[definition.key]
            local value = metric and metric[definition.valueKey]
            if metric and metric.available and isFiniteNumber(value) then
                values[#values + 1] = value
            end
        end
    end
    return values
end

local function collectPlayerValues(
    season,
    mapID,
    currentPlayer,
    definition
)
    local values = {}
    for _, priorRun in ipairs(getMapRuns(season, mapID)) do
        if type(priorRun) == "table"
            and priorRun.baselineEligible
            and type(priorRun.metrics) == "table"
        then
            local priorPlayer = findPlayer(
                priorRun.metrics.players,
                currentPlayer
            )
            local priorMetrics = priorPlayer
                and priorPlayer.metrics
            local metric = type(priorMetrics) == "table"
                and priorMetrics[definition.key]
            local value = type(metric) == "table"
                and metric[definition.valueKey]
            if type(metric) == "table"
                and metric.available
                and isFiniteNumber(value)
            then
                values[#values + 1] = value
            end
        end
    end
    return values
end

function A.AssessRun(run, season)
    if type(run) ~= "table" or type(run.metrics) ~= "table" then
        return nil
    end

    local groupMetrics = type(run.metrics.group) == "table"
        and run.metrics.group or {}
    local players = type(run.metrics.players) == "table"
        and run.metrics.players or {}
    local assessments = {
        group = {},
        players = {},
    }

    for _, definition in ipairs(ASSESSMENT_DEFINITIONS) do
        local metric = groupMetrics[definition.key]
        local value = type(metric) == "table"
            and metric[definition.valueKey]
        if type(metric) == "table"
            and metric.available
            and isFiniteNumber(value)
        then
            assessments.group[definition.key] = H.AssessMetric(
                value,
                collectGroupValues(
                    season,
                    run.mapID,
                    run,
                    definition
                ),
                definition.kind,
                definition.adverseWhenHigh
            )
        end
    end

    for _, player in ipairs(players) do
        if type(player) == "table"
            and type(player.guid) == "string"
            and player.guid ~= ""
        then
            local playerAssessments = {}
            assessments.players[player.guid] = playerAssessments
            for _, definition in ipairs(ASSESSMENT_DEFINITIONS) do
                local metric = type(player.metrics) == "table"
                    and player.metrics[definition.key]
                local value = type(metric) == "table"
                    and metric[definition.valueKey]
                if type(metric) == "table"
                    and metric.available
                    and isFiniteNumber(value)
                then
                    playerAssessments[definition.key] = H.AssessMetric(
                        value,
                        collectPlayerValues(
                            season,
                            run.mapID,
                            player,
                            definition
                        ),
                        definition.kind,
                        definition.adverseWhenHigh
                    )
                end
            end
        end
    end

    run.assessments = assessments
    return assessments
end
