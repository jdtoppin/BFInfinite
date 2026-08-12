---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets

local M = {}
W.MythicPlusModel = M

local abs = math.abs
local floor = math.floor
local max = math.max
local sort = table.sort

local PLUS_TWO_RATIO = 0.80
local PLUS_THREE_RATIO = 0.60
local CHALLENGERS_PERIL_AFFIX_ID = 152

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function stripObjectivePrefix(text)
    if type(text) ~= "string" then
        return ""
    end

    -- Blizzard prefixes completed criteria with U+2713 in some locales.
    text = text:gsub("^\226\156\147%s*", "")
    return text:gsub("^%-%s*", "")
end

local function copyArray(values)
    local result = {}
    if type(values) == "table" then
        for index, value in ipairs(values) do
            result[index] = value
        end
    end
    return result
end

local function getObjectiveKey(info, index)
    local criteriaID = type(info) == "table" and tonumber(info.criteriaID)
    if criteriaID and criteriaID > 0 then
        return "criteria:" .. criteriaID
    end
    return "index:" .. index
end

local function parseWeightedQuantity(info)
    local quantity = tonumber(info.quantity) or 0
    local quantityString = info.quantityString
    if type(quantityString) ~= "string" or quantityString == "" then
        return quantity, false
    end

    local normalized = quantityString:gsub("%%", "")
    if normalized:find(",", 1, true) and not normalized:find(".", 1, true) then
        normalized = normalized:gsub(",", ".")
    end
    local parsed = tonumber(normalized)
    if parsed then
        return parsed, true
    end
    return quantity, false
end

function M.FormatClock(seconds, includeSign)
    if not isFiniteNumber(seconds) then
        return "--:--"
    end

    local sign = ""
    if seconds < 0 then
        sign = "-"
        seconds = abs(seconds)
    elseif includeSign then
        sign = "+"
    end

    seconds = floor(seconds + 0.5)
    local hours = floor(seconds / 3600)
    local minutes = floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    if hours > 0 then
        return ("%s%d:%02d:%02d"):format(sign, hours, minutes, remainder)
    end
    return ("%s%d:%02d"):format(sign, minutes, remainder)
end

function M.CalculateBonusThresholds(timeLimit, affixes)
    timeLimit = tonumber(timeLimit) or 0
    local plusTwo = timeLimit * PLUS_TWO_RATIO
    local plusThree = timeLimit * PLUS_THREE_RATIO

    if timeLimit <= 0 then
        return plusTwo, plusThree
    end

    -- Challenger's Peril adds 90 seconds to the displayed limit without
    -- moving the original +2/+3 portions by the same full amount.
    for _, affixID in ipairs(affixes or {}) do
        if affixID == CHALLENGERS_PERIL_AFFIX_ID then
            local originalLimit = timeLimit - 90
            if originalLimit > 0 then
                plusTwo = originalLimit * PLUS_TWO_RATIO + 90
                plusThree = originalLimit * PLUS_THREE_RATIO + 90
            end
            break
        end
    end

    return plusTwo, plusThree
end

function M.ModifierFactor(modifierPercent)
    if not isFiniteNumber(modifierPercent) then
        return 1
    end

    local factor = 1 + modifierPercent / 100
    if not isFiniteNumber(factor) or factor <= 0 then
        return 1
    end
    return factor
end

function M.ScaleReferenceElapsed(
    referenceElapsed,
    referenceHealthModifier,
    currentHealthModifier,
    referenceCombatElapsed
)
    if not isFiniteNumber(referenceElapsed) or referenceElapsed < 0 then
        return nil
    end

    if not isFiniteNumber(referenceHealthModifier)
        or not isFiniteNumber(currentHealthModifier)
    then
        return referenceElapsed, false, "modifier_unavailable"
    end

    local scale = M.ModifierFactor(currentHealthModifier)
        / M.ModifierFactor(referenceHealthModifier)
    if scale == 1 then
        return referenceElapsed, false
    end
    if not isFiniteNumber(referenceCombatElapsed)
        or referenceCombatElapsed < 0
        or referenceCombatElapsed > referenceElapsed
    then
        return referenceElapsed, false, "combat_context_unavailable"
    end

    local nonCombatElapsed = referenceElapsed - referenceCombatElapsed
    return nonCombatElapsed + referenceCombatElapsed * scale, true
end

function M.MakeAffixKey(affixes)
    local values = copyArray(affixes)
    sort(values)
    for index, value in ipairs(values) do
        values[index] = tostring(value)
    end
    return table.concat(values, "-")
end

function M.FindReferenceRun(mapHistory)
    local runs = type(mapHistory) == "table" and mapHistory.runs
    if type(runs) ~= "table" then
        return nil
    end

    local function hasUsableSplit(run)
        if type(run.splits) ~= "table" then return false end
        for _, split in ipairs(run.splits) do
            if type(split) == "table"
                and isFiniteNumber(split.elapsed)
                and split.elapsed >= 0
            then
                return true
            end
        end
        return false
    end

    local fallback
    for index = #runs, 1, -1 do
        local run = runs[index]
        if type(run) == "table" and run.completed and hasUsableSplit(run) then
            fallback = fallback or run
            if run.baselineEligible then
                return run
            end
        end
    end
    return fallback
end

function M.BuildReferenceSplits(referenceRun, currentHealthModifier)
    local references = {}
    if type(referenceRun) ~= "table" or type(referenceRun.splits) ~= "table" then
        return references
    end

    for index, split in ipairs(referenceRun.splits) do
        if type(split) == "table" and isFiniteNumber(split.elapsed) then
            local key = split.key or getObjectiveKey(split, index)
            local elapsed, normalized, normalizationReason =
                M.ScaleReferenceElapsed(
                    split.elapsed,
                    referenceRun.healthModifierPercent,
                    currentHealthModifier,
                    split.combatElapsed
                )
            references[key] = {
                elapsed = elapsed,
                rawElapsed = split.elapsed,
                combatElapsed = split.combatElapsed,
                referenceLevel = referenceRun.level,
                normalized = normalized,
                normalizationReason = normalizationReason,
            }
        end
    end
    return references
end

function M.ReadScenarioCriteria(stepInfo, getCriteriaInfo)
    local criteria = {}
    local numCriteria = type(stepInfo) == "table"
        and tonumber(stepInfo.numCriteria) or 0
    if type(getCriteriaInfo) ~= "function" then
        return criteria
    end

    for index = 1, numCriteria do
        local info = getCriteriaInfo(index)
        if type(info) == "table" then
            criteria[#criteria + 1] = {
                completed = info.completed == true,
                criteriaID = info.criteriaID,
                description = stripObjectivePrefix(info.description),
                elapsed = info.elapsed,
                isWeightedProgress = info.isWeightedProgress == true,
                quantity = info.quantity,
                quantityString = info.quantityString,
                totalQuantity = info.totalQuantity,
            }
        end
    end
    return criteria
end

function M.UpdateObjectives(run, criteria, elapsed)
    if type(run) ~= "table" then
        return {}
    end
    if type(run.objectives) ~= "table" then
        run.objectives = {}
    end
    if type(run.splits) ~= "table" then
        run.splits = {}
    end
    if type(run.savedSplits) ~= "table" then
        run.savedSplits = {}
    end
    if type(run.savedSplitCombat) ~= "table" then
        run.savedSplitCombat = {}
    end
    if type(run.unknownSplitCombat) ~= "table" then
        run.unknownSplitCombat = {}
    end

    local previousByKey = {}
    for _, objective in ipairs(run.objectives) do
        previousByKey[objective.key] = objective
    end

    local newObjectives = {}
    local newCompletions = {}
    for index, info in ipairs(criteria or {}) do
        local key = getObjectiveKey(info, index)
        local previous = previousByKey[key]
        local objective = {
            key = key,
            criteriaID = info.criteriaID,
            name = stripObjectivePrefix(info.description),
            completed = info.completed == true,
            isWeighted = info.isWeightedProgress == true,
            quantity = tonumber(info.quantity) or 0,
            totalQuantity = tonumber(info.totalQuantity) or 0,
        }

        if objective.isWeighted then
            local rawQuantity, quantityIsAbsolute =
                parseWeightedQuantity(info)
            objective.rawQuantity = rawQuantity
            objective.rawTotalQuantity = objective.totalQuantity
            if quantityIsAbsolute and objective.totalQuantity > 0 then
                objective.percent = rawQuantity / objective.totalQuantity * 100
            else
                -- Blizzard's quantity field is already the 0-100 value used
                -- by its progress bar. quantityString is the absolute forces
                -- count (despite carrying a percent sign) when available.
                objective.percent = rawQuantity
            end
            if objective.completed then
                objective.percent = 100
            end
            objective.percent = max(0, math.min(100, objective.percent))
        elseif objective.totalQuantity == 0 then
            objective.quantity = objective.completed and 1 or 0
            objective.totalQuantity = 1
        end

        local savedElapsed = run.savedSplits[key]
        if objective.completed then
            local reportedElapsed = tonumber(info.elapsed)
            local reconstructedCompletion =
                isFiniteNumber(reportedElapsed)
                and reportedElapsed > 0
                and isFiniteNumber(elapsed)
                and elapsed >= reportedElapsed
            if isFiniteNumber(savedElapsed) then
                objective.elapsed = savedElapsed
            elseif previous and isFiniteNumber(previous.elapsed) then
                objective.elapsed = previous.elapsed
            elseif reconstructedCompletion then
                objective.elapsed = elapsed - reportedElapsed
                objective.reconstructedCompletion = true
                run.savedSplits[key] = objective.elapsed
                if run.partialObservation and not previous then
                    run.unknownSplitCombat[key] = true
                end
                newCompletions[#newCompletions + 1] = objective
            elseif isFiniteNumber(elapsed)
                and (
                    not run.partialObservation
                    or (previous and previous.completed ~= true)
                )
            then
                objective.elapsed = elapsed
                run.savedSplits[key] = elapsed
                newCompletions[#newCompletions + 1] = objective
            end

            local savedCombatElapsed = run.savedSplitCombat[key]
            if isFiniteNumber(savedCombatElapsed) then
                objective.combatElapsed = savedCombatElapsed
            elseif previous and isFiniteNumber(previous.combatElapsed) then
                objective.combatElapsed = previous.combatElapsed
            elseif isFiniteNumber(objective.elapsed)
                and not run.unknownSplitCombat[key]
                and not (
                    run.partialObservation
                    and objective.reconstructedCompletion
                    and not previous
                )
            then
                local combatElapsed = tonumber(run.combatSeconds) or 0
                local objectiveWallElapsed = max(
                    0,
                    objective.elapsed
                        - (tonumber(run.deathTimeLost) or 0)
                )
                if isFiniteNumber(run.combatStartedElapsed)
                    and objectiveWallElapsed >= run.combatStartedElapsed
                then
                    combatElapsed = combatElapsed
                        + objectiveWallElapsed
                        - run.combatStartedElapsed
                end
                objective.combatElapsed = max(0, combatElapsed)
                run.savedSplitCombat[key] = objective.combatElapsed
            end
        end

        local reference = type(run.referenceSplits) == "table"
            and run.referenceSplits[key]
        if reference and isFiniteNumber(reference.elapsed) then
            objective.referenceElapsed = reference.elapsed
            objective.referenceRawElapsed = reference.rawElapsed
            objective.referenceLevel = reference.referenceLevel
            objective.referenceNormalized = reference.normalized
            objective.referenceNormalizationReason =
                reference.normalizationReason
            if objective.elapsed then
                objective.splitDelta = objective.elapsed - reference.elapsed
            end
        end

        newObjectives[#newObjectives + 1] = objective
    end

    run.objectives = newObjectives
    run.splits = {}
    for _, objective in ipairs(newObjectives) do
        if objective.completed and objective.elapsed then
            run.splits[#run.splits + 1] = {
                key = objective.key,
                criteriaID = objective.criteriaID,
                name = objective.name,
                isWeighted = objective.isWeighted,
                elapsed = objective.elapsed,
                combatElapsed = objective.combatElapsed,
            }
        end
    end

    return newCompletions
end

function M.AreObjectivesComplete(objectives)
    local seen = false
    for _, objective in ipairs(objectives or {}) do
        seen = true
        if not objective.completed then
            return false
        end
    end
    return seen
end

function M.GetForcesObjective(objectives)
    for _, objective in ipairs(objectives or {}) do
        if objective.isWeighted then
            return objective
        end
    end
end

function M.GetBossObjectives(objectives)
    local bosses = {}
    for _, objective in ipairs(objectives or {}) do
        if not objective.isWeighted then
            bosses[#bosses + 1] = objective
        end
    end
    return bosses
end

function M.CalculateSplitDelta(objective)
    if type(objective) ~= "table"
        or not isFiniteNumber(objective.elapsed)
        or not isFiniteNumber(objective.referenceElapsed)
    then
        return nil
    end
    return objective.elapsed - objective.referenceElapsed
end

function M.FinalizeCombat(run, elapsed)
    if type(run) ~= "table" or not isFiniteNumber(run.combatStartedElapsed) then
        return 0
    end
    if not isFiniteNumber(elapsed) or elapsed < run.combatStartedElapsed then
        run.combatStartedElapsed = nil
        return 0
    end

    local duration = elapsed - run.combatStartedElapsed
    run.combatSeconds = (tonumber(run.combatSeconds) or 0) + duration
    run.combatStartedElapsed = nil
    return duration
end
