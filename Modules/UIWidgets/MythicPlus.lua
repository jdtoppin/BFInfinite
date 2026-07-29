---@type BFI
local BFI = select(2, ...)
---@class UIWidgets
local W = BFI.modules.UIWidgets
local L = BFI.L
local F = BFI.funcs
---@type AbstractFramework
local AF = _G.AbstractFramework

local H = W.MythicPlusHistory
local Meter = W.MythicPlusMeter
local Model = W.MythicPlusModel
local Analysis = W.MythicPlusAnalysis

local MP = {}
W.MythicPlus = MP

local C_ChallengeMode = _G.C_ChallengeMode
local C_MythicPlus = _G.C_MythicPlus
local C_Scenario = _G.C_Scenario
local C_ScenarioInfo = _G.C_ScenarioInfo
local C_Timer = _G.C_Timer
local CreateFrame = _G.CreateFrame
local Enum = _G.Enum
local GetBuildInfo = _G.GetBuildInfo
local GetInstanceInfo = _G.GetInstanceInfo
local GetServerTime = _G.GetServerTime
local GetTimePreciseSec = _G.GetTimePreciseSec
local GetWorldElapsedTime = _G.GetWorldElapsedTime
local GetWorldElapsedTimers = _G.GetWorldElapsedTimers
local InCombatLockdown = _G.InCombatLockdown
local UnitFullName = _G.UnitFullName
local UnitGUID = _G.UnitGUID
local hooksecurefunc = _G.hooksecurefunc

local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min
local sort = table.sort

local HISTORY_START_INTERFACE = 120100
local MAX_PULL_SNAPSHOTS = 50
local TIMER_REFRESH_INTERVAL = 0.10
local FINALIZE_QUIET_DELAY = 0.20
local FINALIZE_DEADLINE_SECONDS = 4
local FINALIZE_RETRY_DELAYS = {0.25, 0.50, 0.75, 0.75}
local RUN_START_MATCH_TOLERANCE = 10
local MAX_RESTORE_IDENTITY_RETRIES = 2

local config
local characterHistory
local characterKey
local currentRun
local currentSeason
local currentSeasonKey
local eventFrame
local timerFrame
local previewRun
local updateAccumulator = 0
local deadlineScheduled = {}

local RefreshDisplay
local TryFinalizeRun
local ScheduleFinalization
local archiveInterruptedRun

local bandColors = {
    red = "firebrick",
    orange = "orange",
    yellow = "yellow",
    green = "softlime",
    blue = "skyblue",
    purple = "purple",
    unrated = "gray",
}

local assessmentLabels = {
    much_worse = L["much worse"],
    worse = L["worse"],
    slightly_worse = L["slightly worse"],
    within_norm = L["within norm"],
    better = L["better"],
    much_better = L["much better"],
    collecting = L["collecting"],
    above_zero_baseline = L["above zero baseline"],
}

local baselineReasonLabels = {
    abandoned_run = L["abandoned run"],
    extended_learning_run = L["extended learning run"],
    history_starts_12_1 = L["baselines begin with 12.1"],
    incomplete_meter = L["meter data incomplete"],
    incomplete_run = L["run incomplete"],
    manual_exclude = L["manually excluded"],
    meter_reset = L["damage meter reset during run"],
    missing_timing = L["timing data unavailable"],
    partial_run = L["tracking began after the key started"],
    practice_run = L["practice run"],
    reset_run = L["reset run"],
    roster_corrupt = L["roster data incomplete"],
    session_corrupt = L["meter session changed"],
}

local maturityLabels = {
    collecting = L["collecting"],
    provisional = L["provisional"],
    established = L["established"],
    mature = L["mature"],
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isNonSecret(value)
    return F.isValueNonSecret(value)
end

local function getInterfaceVersion()
    if type(GetBuildInfo) ~= "function" then
        return 0
    end
    local interfaceVersion = select(4, GetBuildInfo())
    if not isNonSecret(interfaceVersion) then
        return 0
    end
    return tonumber(interfaceVersion) or 0
end

local function isHistoryEra()
    return getInterfaceVersion() >= HISTORY_START_INTERFACE
end

local function getTimestamp()
    if type(GetServerTime) == "function" then
        local value = GetServerTime()
        if isNonSecret(value) and type(value) == "number" then
            return value
        end
    end
    return 0
end

local function runAfter(delay, callback)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

local function getCharacterKey()
    local fullName = AF.player and AF.player.fullName
    if isNonSecret(fullName) and type(fullName) == "string"
        and fullName ~= ""
    then
        return fullName
    end

    if type(UnitFullName) == "function" then
        local name, realm = UnitFullName("player")
        if isNonSecret(name) and isNonSecret(realm)
            and type(name) == "string" and name ~= ""
        then
            if type(realm) == "string" and realm ~= "" then
                return name .. "-" .. realm
            end
            return name
        end
    end

    if type(UnitGUID) == "function" then
        local guid = UnitGUID("player")
        if isNonSecret(guid) and type(guid) == "string" and guid ~= "" then
            return guid
        end
    end
    return "unknown"
end

local function ensureHistory()
    characterKey = characterKey or getCharacterKey()
    local store
    store, characterHistory = H.EnsureStore(
        _G.BFIMythicPlusHistory,
        characterKey
    )
    _G.BFIMythicPlusHistory = store

    if type(characterHistory.pendingRuns) ~= "table" then
        characterHistory.pendingRuns = {}
    end
    return store, characterHistory
end

local function getCurrentSeasonID()
    if type(C_MythicPlus) ~= "table"
        or type(C_MythicPlus.GetCurrentSeason) ~= "function"
    then
        return nil
    end
    local seasonID = C_MythicPlus.GetCurrentSeason()
    if not isNonSecret(seasonID) or type(seasonID) ~= "number"
        or seasonID <= 0
    then
        return nil
    end
    return seasonID
end

local function requestMapInfo()
    if type(C_MythicPlus) == "table"
        and type(C_MythicPlus.RequestMapInfo) == "function"
    then
        C_MythicPlus.RequestMapInfo()
    end
end

local function getMapHistory(season, mapID)
    if type(season) ~= "table" or type(season.maps) ~= "table" then
        return nil
    end
    return season.maps[mapID]
end

local function findSeasonForRun(run, fallbackSeason, fallbackKey)
    if type(run) ~= "table" or not characterHistory
        or type(characterHistory.seasons) ~= "table"
    then
        return nil
    end

    local function accepts(season)
        return type(season) == "table"
            and type(season.maps) == "table"
            and season.maps[run.mapID] ~= nil
    end

    if run.seasonKey then
        local exact = characterHistory.seasons[run.seasonKey]
        if accepts(exact)
            and (
                run.seasonID == nil
                or exact.internalSeasonID == run.seasonID
            )
        then
            return exact, run.seasonKey
        end
    end

    if run.seasonID == nil then
        if accepts(fallbackSeason) then
            return fallbackSeason, fallbackKey
        end
        return nil
    end

    if accepts(fallbackSeason)
        and fallbackSeason.internalSeasonID == run.seasonID
    then
        return fallbackSeason, fallbackKey
    end

    local bestSeason, bestKey, bestObservedAt
    for seasonKey, season in pairs(characterHistory.seasons) do
        if accepts(season)
            and season.internalSeasonID == run.seasonID
        then
            local observedAt = type(season.metadata) == "table"
                and tonumber(season.metadata.observedAt) or 0
            if not bestSeason or observedAt > bestObservedAt then
                bestSeason = season
                bestKey = seasonKey
                bestObservedAt = observedAt
            end
        end
    end
    return bestSeason, bestKey
end

local function attachReference(run)
    if type(run) ~= "table" or not currentSeason
        or run.seasonID ~= currentSeason.internalSeasonID
    then
        return
    end

    local reference = Model.FindReferenceRun(
        getMapHistory(currentSeason, run.mapID)
    )
    if not reference then return end

    run.referenceHistoryID = reference.historyID
    run.referenceLevel = reference.level
    run.referenceSplits = Model.BuildReferenceSplits(
        reference,
        run.healthModifierPercent
    )
    Model.UpdateObjectives(run, run.lastCriteria or {}, run.elapsed or 0)
end

local function addRunToSeason(run, season)
    if type(run) ~= "table" or type(season) ~= "table" then
        return false
    end

    if run.metrics then
        Analysis.AssessRun(run, season)
    end
    local eligible, reason = H.IsBaselineEligible(
        run,
        config and config.extendedRunMultiplier or 1.5
    )
    run.baselineEligible = eligible
    run.baselineReason = reason

    local _, storedRun = H.AddRunToHistory(season, run.mapID, run)
    if storedRun then
        run.historyID = storedRun.historyID
        run.historyStored = true
        return true
    end
    return false
end

local function drainPendingRuns(season)
    if not characterHistory or type(characterHistory.pendingRuns) ~= "table"
        or type(season) ~= "table"
    then
        return
    end

    local remaining = {}
    for index = 1, #characterHistory.pendingRuns do
        local run = characterHistory.pendingRuns[index]
        local targetSeason, targetKey = findSeasonForRun(
            run,
            season,
            currentSeasonKey
        )
        if targetSeason then
            run.seasonID = run.seasonID
                or targetSeason.internalSeasonID
            run.seasonKey = run.seasonKey or targetKey
            addRunToSeason(run, targetSeason)
        else
            remaining[#remaining + 1] = run
        end
    end
    characterHistory.pendingRuns = remaining
end

local function discoverSeason()
    if not isHistoryEra() then
        currentSeason = nil
        currentSeasonKey = nil
        return nil
    end
    if type(C_MythicPlus) ~= "table"
        or type(C_MythicPlus.IsMythicPlusActive) ~= "function"
        or not C_MythicPlus.IsMythicPlusActive()
        or type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.GetMapTable) ~= "function"
    then
        return nil
    end

    local seasonID = getCurrentSeasonID()
    if not seasonID then return nil end

    local rawMapIDs = C_ChallengeMode.GetMapTable()
    if not isNonSecret(rawMapIDs) or type(rawMapIDs) ~= "table" then
        return nil
    end

    local mapIDs, seen = {}, {}
    for _, rawMapID in ipairs(rawMapIDs) do
        if isNonSecret(rawMapID) and type(rawMapID) == "number"
            and rawMapID > 0 and not seen[rawMapID]
        then
            seen[rawMapID] = true
            mapIDs[#mapIDs + 1] = rawMapID
        end
    end
    if #mapIDs == 0 then return nil end
    sort(mapIDs)

    ensureHistory()
    local displaySeasonID
    local milestoneSeasonID
    local rewardSeasonID
    if type(C_MythicPlus.GetCurrentSeasonValues) == "function" then
        displaySeasonID, milestoneSeasonID, rewardSeasonID =
            C_MythicPlus.GetCurrentSeasonValues()
    end

    local fingerprint = H.MakePoolFingerprint(mapIDs)
    local season, seasonKey = H.GetOrCreateSeason(
        _G.BFIMythicPlusHistory,
        characterKey,
        seasonID,
        fingerprint,
        {
            displaySeasonID = displaySeasonID,
            milestoneSeasonID = milestoneSeasonID,
            rewardSeasonID = rewardSeasonID,
            interfaceVersion = getInterfaceVersion(),
            observedAt = getTimestamp(),
        }
    )

    for _, mapID in ipairs(mapIDs) do
        local mapHistory = season.maps[mapID]
        if type(mapHistory) ~= "table" then
            mapHistory = {}
            season.maps[mapID] = mapHistory
        end

        if type(C_ChallengeMode.GetMapUIInfo) == "function" then
            local name, id, timeLimit, texture, backgroundTexture,
                instanceMapID = C_ChallengeMode.GetMapUIInfo(mapID)
            if isNonSecret(name) and type(name) == "string" then
                mapHistory.name = name
            end
            if isNonSecret(id) and type(id) == "number" then
                mapHistory.mapChallengeModeID = id
            end
            if isNonSecret(timeLimit) and type(timeLimit) == "number" then
                mapHistory.timeLimit = timeLimit
            end
            if isNonSecret(texture) and type(texture) == "number" then
                mapHistory.texture = texture
            end
            if isNonSecret(backgroundTexture)
                and type(backgroundTexture) == "number"
            then
                mapHistory.backgroundTexture = backgroundTexture
            end
            if isNonSecret(instanceMapID)
                and type(instanceMapID) == "number"
            then
                mapHistory.instanceMapID = instanceMapID
            end
        end
        mapHistory.firstSeen = mapHistory.firstSeen or getTimestamp()
        mapHistory.lastSeen = getTimestamp()
    end

    currentSeason = season
    currentSeasonKey = seasonKey
    drainPendingRuns(season)
    if currentRun and currentRun.active and not currentRun.referenceSplits then
        attachReference(currentRun)
    end
    return season
end

local function storeCompletedRun(run)
    if not isHistoryEra() then
        run.baselineEligible = false
        run.baselineReason = "history_starts_12_1"
        return
    end

    discoverSeason()
    local targetSeason, targetKey = findSeasonForRun(
        run,
        currentSeason,
        currentSeasonKey
    )
    if targetSeason then
        run.seasonID = run.seasonID
            or targetSeason.internalSeasonID
        run.seasonKey = run.seasonKey or targetKey
        addRunToSeason(run, targetSeason)
        return
    end

    ensureHistory()
    H.AppendPendingRun(characterHistory, run)
    requestMapInfo()
end

local function getChallengeTimer()
    if type(GetWorldElapsedTimers) ~= "function"
        or type(GetWorldElapsedTime) ~= "function"
    then
        return nil
    end

    local timerIDs = {GetWorldElapsedTimers()}
    local challengeType = Enum and Enum.WorldElapsedTimerTypes
        and Enum.WorldElapsedTimerTypes.ChallengeMode
    for _, timerID in ipairs(timerIDs) do
        if isNonSecret(timerID) and type(timerID) == "number" then
            local _, elapsed, timerType = GetWorldElapsedTime(timerID)
            if isNonSecret(elapsed) and isNonSecret(timerType)
                and type(elapsed) == "number"
                and timerType == challengeType
            then
                return timerID, elapsed
            end
        end
    end
end
MP.GetChallengeTimer = getChallengeTimer

local function getRunElapsed(run)
    if type(run) ~= "table" then return 0 end

    if run.timerID and type(GetWorldElapsedTime) == "function" then
        local _, elapsed, timerType = GetWorldElapsedTime(run.timerID)
        local challengeType = Enum and Enum.WorldElapsedTimerTypes
            and Enum.WorldElapsedTimerTypes.ChallengeMode
        if isNonSecret(elapsed) and isNonSecret(timerType)
            and type(elapsed) == "number"
            and timerType == challengeType
        then
            return max(0, elapsed)
        end
    end

    local timerID, elapsed = getChallengeTimer()
    if timerID then
        run.timerID = timerID
        return max(0, elapsed)
    end

    if type(GetTimePreciseSec) == "function" and run.localClockStart then
        local now = GetTimePreciseSec()
        if isNonSecret(now) and type(now) == "number" then
            return max(run.elapsed or 0, now - run.localClockStart)
        end
    end
    return max(0, tonumber(run.elapsed) or 0)
end

local function readChallengeDeathData()
    if type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.GetDeathCount) ~= "function"
    then
        return nil, nil
    end

    local deaths, timeLost = C_ChallengeMode.GetDeathCount()
    if not isNonSecret(deaths) or not isFiniteNumber(deaths) then
        deaths = nil
    end
    if not isNonSecret(timeLost) or not isFiniteNumber(timeLost) then
        timeLost = nil
    end
    return deaths, timeLost
end

local function updateRunDeathData(run)
    if type(run) ~= "table" then return nil, nil end
    local deaths, timeLost = readChallengeDeathData()
    if deaths then
        run.deaths = max(0, deaths)
    end
    if timeLost then
        run.deathTimeLost = max(0, timeLost)
    end
    return deaths, timeLost
end

local function establishRunIdentity(run, elapsed)
    if type(run) ~= "table" or not run.identityUnverified then
        return true
    end
    if not isFiniteNumber(elapsed) then return false end

    local _, timeLost = updateRunDeathData(run)
    local serverNow = getTimestamp()
    if not isFiniteNumber(timeLost)
        or not isFiniteNumber(serverNow)
        or serverNow <= 0
    then
        return false
    end

    local startedAt = serverNow - elapsed + max(0, timeLost)
    if not isFiniteNumber(startedAt) or startedAt <= 0 then
        return false
    end

    run.startedAt = startedAt
    run.identityUnverified = nil
    return true
end

local function getScenarioStepInfo()
    if type(C_ScenarioInfo) == "table"
        and type(C_ScenarioInfo.GetScenarioStepInfo) == "function"
    then
        local info = C_ScenarioInfo.GetScenarioStepInfo()
        if isNonSecret(info) and type(info) == "table" then
            return info
        end
    end

    if type(C_Scenario) == "table"
        and type(C_Scenario.GetStepInfo) == "function"
    then
        local title, description, numCriteria, stepFailed, isBonusStep,
            isForCurrentStepOnly, shouldShowBonusObjective, numSpells,
            spells, weightedProgress, rewardQuestID, widgetSetID, stepID =
            C_Scenario.GetStepInfo()
        return {
            title = title,
            description = description,
            numCriteria = numCriteria,
            stepFailed = stepFailed,
            isBonusStep = isBonusStep,
            isForCurrentStepOnly = isForCurrentStepOnly,
            shouldShowBonusObjective = shouldShowBonusObjective,
            numSpells = numSpells,
            spells = spells,
            weightedProgress = weightedProgress,
            rewardQuestID = rewardQuestID,
            widgetSetID = widgetSetID,
            stepID = stepID,
        }
    end
    return {numCriteria = 0}
end

local function updateObjectives(run)
    if type(run) ~= "table" then return end
    updateRunDeathData(run)
    local criteria = Model.ReadScenarioCriteria(
        getScenarioStepInfo(),
        function(index)
            if type(C_ScenarioInfo) == "table"
                and type(C_ScenarioInfo.GetCriteriaInfo) == "function"
            then
                local info = C_ScenarioInfo.GetCriteriaInfo(index)
                if isNonSecret(info) and type(info) == "table" then
                    return info
                end
            end
        end
    )
    run.lastCriteria = criteria
    Model.UpdateObjectives(run, criteria, run.elapsed or 0)
end

local function getOverallSessionType()
    return Meter.GetDefaultSessionType()
end

local function getCurrentSessionType()
    return Enum and Enum.DamageMeterSessionType
        and Enum.DamageMeterSessionType.Current
end

local function makeZeroSnapshot(endSnapshot)
    return {
        schemaVersion = 1,
        sessionType = endSnapshot and endSnapshot.sessionType,
        authoritativeZero = true,
        complete = true,
        coreComplete = true,
        durationSeconds = 0,
        categories = {},
        group = {},
        players = {},
    }
end

local function makeRunDelta(run, endSnapshot)
    if not endSnapshot then
        return nil, "end_snapshot_unavailable"
    end
    local startSnapshot = run.meterStart
    if not startSnapshot and run.meterStartEmpty then
        startSnapshot = makeZeroSnapshot(endSnapshot)
    end
    if not startSnapshot then
        return nil, run.meterStartReason or "start_snapshot_unavailable"
    end
    if startSnapshot.coreComplete ~= true then
        return nil, "start_snapshot_incomplete"
    end
    return Meter.SubtractSnapshots(startSnapshot, endSnapshot)
end

local function compactPullSnapshot(snapshot, pull, elapsed)
    local compact = {
        pull = pull,
        elapsed = elapsed,
        durationSeconds = snapshot.durationSeconds,
        group = snapshot.group,
        players = {},
    }
    for _, player in ipairs(snapshot.players or {}) do
        compact.players[#compact.players + 1] = {
            guid = player.guid,
            interrupts = player.metrics and player.metrics.interrupts,
            avoidableDamageTaken = player.metrics
                and player.metrics.avoidableDamageTaken,
            deaths = player.metrics and player.metrics.deaths,
        }
    end
    return compact
end

local function capturePullSnapshot(run)
    if not run or not run.active or type(InCombatLockdown) ~= "function"
        or InCombatLockdown()
    then
        return
    end

    local currentSnapshot = Meter.CollectRunSnapshot(
        run.roster,
        getCurrentSessionType()
    )
    if currentSnapshot then
        run.pullSnapshots = run.pullSnapshots or {}
        run.pullSnapshots[#run.pullSnapshots + 1] = compactPullSnapshot(
            currentSnapshot,
            run.pullCount or 0,
            run.elapsed or 0
        )
        while #run.pullSnapshots > MAX_PULL_SNAPSHOTS do
            table.remove(run.pullSnapshots, 1)
        end
    end

    local overallSnapshot = Meter.CollectRunSnapshot(
        run.roster,
        getOverallSessionType()
    )
    if overallSnapshot then
        run.liveMeterSnapshot = makeRunDelta(run, overallSnapshot)
    end
    RefreshDisplay()
end

local trackerSuppressed
local trackerHooked
local trackerWasShown
local trackerRestoreAlpha
local trackerRestorePending

local function shouldSuppressTracker()
    return trackerSuppressed == true
        and config and config.hideObjectiveTracker ~= false
end

local function applyTrackerSuppression()
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker or not shouldSuppressTracker() then return end

    if trackerWasShown == nil then
        trackerWasShown = tracker:IsShown()
        trackerRestoreAlpha = tracker:GetAlpha()
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        tracker:SetAlpha(0)
    else
        tracker:SetAlpha(0)
        tracker:Hide()
    end
end

local function installTrackerHook()
    if trackerHooked or not hooksecurefunc then return end
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    trackerHooked = true
    hooksecurefunc(tracker, "Show", function()
        if shouldSuppressTracker() then
            applyTrackerSuppression()
        end
    end)
end

local function suppressTracker()
    trackerSuppressed = true
    installTrackerHook()
    applyTrackerSuppression()
end

local function restoreTrackerNow()
    local tracker = _G.ObjectiveTrackerFrame
    trackerRestorePending = nil
    if tracker and (
        trackerWasShown ~= nil or trackerRestoreAlpha ~= nil
    ) then
        tracker:SetAlpha(trackerRestoreAlpha or 1)
        if trackerWasShown == true then
            tracker:Show()
        elseif trackerWasShown == false then
            tracker:Hide()
        end
    end
    trackerWasShown = nil
    trackerRestoreAlpha = nil
end

local function restoreTracker()
    trackerSuppressed = nil
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        trackerRestorePending = true
        if eventFrame then
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    else
        restoreTrackerNow()
    end
end

local function persistActiveRun()
    ensureHistory()
    characterHistory.activeRun = currentRun and currentRun.active
        and currentRun or nil
end

local function persistPendingFinalization(run)
    ensureHistory()
    characterHistory.pendingFinalization = run
end

local function getActiveMapID()
    if type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.GetActiveChallengeMapID) ~= "function"
    then
        return nil
    end
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not isNonSecret(mapID) or type(mapID) ~= "number" then
        return nil
    end
    return mapID
end

local function isChallengeActive()
    return type(C_ChallengeMode) == "table"
        and type(C_ChallengeMode.IsChallengeModeActive) == "function"
        and C_ChallengeMode.IsChallengeModeActive()
end

local function capturePowerModifiers(level)
    if type(C_ChallengeMode) ~= "table"
        or type(C_ChallengeMode.GetPowerLevelDamageHealthMod) ~= "function"
    then
        return nil, nil
    end
    local damage, health =
        C_ChallengeMode.GetPowerLevelDamageHealthMod(level)
    if not isNonSecret(damage) or type(damage) ~= "number" then
        damage = nil
    end
    if not isNonSecret(health) or type(health) ~= "number" then
        health = nil
    end
    return damage, health
end

local function startRun(mapID, forcePartial)
    mapID = mapID or getActiveMapID()
    if not mapID or not config or not config.enabled then return end
    if currentRun and currentRun.active and currentRun.mapID == mapID then
        return
    end

    local discoveredSeason = discoverSeason()
    local mapName, _, timeLimit, texture
    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        mapName, _, timeLimit, texture =
            C_ChallengeMode.GetMapUIInfo(mapID)
    end
    if not isNonSecret(mapName) or type(mapName) ~= "string" then
        mapName = _G.UNKNOWN or "Unknown"
    end
    if not isNonSecret(timeLimit) or type(timeLimit) ~= "number" then
        timeLimit = 0
    end
    if not isNonSecret(texture) or type(texture) ~= "number" then
        texture = nil
    end

    local level, affixes, charged =
        C_ChallengeMode.GetActiveKeystoneInfo()
    if not isNonSecret(level) or type(level) ~= "number" then
        level = 0
    end
    if not isNonSecret(affixes) or type(affixes) ~= "table" then
        affixes = {}
    else
        local sanitizedAffixes = {}
        for _, affixID in ipairs(affixes) do
            if isNonSecret(affixID) and type(affixID) == "number"
                and affixID > 0
            then
                sanitizedAffixes[#sanitizedAffixes + 1] = affixID
            end
        end
        affixes = sanitizedAffixes
    end
    if not isNonSecret(charged) or type(charged) ~= "boolean" then
        charged = true
    end
    local damageModifier, healthModifier =
        capturePowerModifiers(level)
    local timerID, elapsed = getChallengeTimer()
    elapsed = elapsed or 0
    local deaths, deathTimeLost = readChallengeDeathData()
    local deathDataAvailable = isFiniteNumber(deathTimeLost)
    deathTimeLost = deathDataAvailable and max(0, deathTimeLost) or 0

    local now = type(GetTimePreciseSec) == "function"
        and GetTimePreciseSec() or elapsed
    local observedAt = getTimestamp()
    local startedAt = isFiniteNumber(observedAt) and observedAt > 0
        and max(0, observedAt - elapsed + deathTimeLost) or observedAt
    local identityUnverified = not timerID
        or not deathDataAvailable
        or not isFiniteNumber(startedAt)
        or startedAt <= 0
    currentRun = {
        schemaVersion = 1,
        active = true,
        completed = false,
        mapID = mapID,
        mapName = mapName,
        mapTexture = texture,
        level = level,
        affixes = affixes,
        affixKey = Model.MakeAffixKey(affixes),
        wasCharged = charged,
        timeLimit = timeLimit,
        elapsed = elapsed,
        timerID = timerID,
        localClockStart = now - elapsed,
        startedAt = startedAt,
        seasonID = discoveredSeason
            and discoveredSeason.internalSeasonID,
        seasonKey = discoveredSeason and currentSeasonKey,
        damageModifierPercent = damageModifier,
        healthModifierPercent = healthModifier,
        observerRole = AF.player and AF.player.specRole,
        observerSpecID = AF.player and AF.player.specID,
        pullCount = 0,
        combatSeconds = 0,
        deaths = isFiniteNumber(deaths) and max(0, deaths) or 0,
        deathTimeLost = deathTimeLost,
        objectives = {},
        splits = {},
        savedSplits = {},
        pullSnapshots = {},
        partialObservation = forcePartial or elapsed > 5 or nil,
        identityUnverified = identityUnverified or nil,
    }

    currentRun.roster = Meter.CaptureRoster()
    currentRun.meterStart, currentRun.meterStartReason =
        Meter.CollectRunSnapshot(
            currentRun.roster,
            getOverallSessionType()
        )
    currentRun.meterStartEmpty =
        currentRun.meterStartReason == "session_empty"

    attachReference(currentRun)
    updateObjectives(currentRun)
    persistActiveRun()
    suppressTracker()
    if timerFrame then
        timerFrame:SetScript("OnUpdate", timerFrame._onUpdate)
    end
    RefreshDisplay()
end

local restoreIdentityRetries = 0
local restoreIdentityRetryScheduled

local function restoreRun()
    if not isChallengeActive() then return false end
    local mapID = getActiveMapID()
    if not mapID then return false end

    ensureHistory()
    local saved = characterHistory.activeRun
    if type(saved) ~= "table" then
        restoreIdentityRetries = 0
        startRun(mapID, true)
        return currentRun ~= nil
    end

    if saved.mapID ~= mapID then
        restoreIdentityRetries = 0
        currentRun = saved
        archiveInterruptedRun("abandoned", true)
        startRun(mapID, true)
        return currentRun ~= nil
    end

    local timerID, elapsed = getChallengeTimer()
    local activeDeaths, activeDeathTimeLost = readChallengeDeathData()
    if not timerID or not isFiniteNumber(elapsed)
        or not isFiniteNumber(activeDeathTimeLost)
    then
        currentRun = nil
        if restoreIdentityRetryScheduled then
            return false
        end
        if restoreIdentityRetries < MAX_RESTORE_IDENTITY_RETRIES then
            restoreIdentityRetries = restoreIdentityRetries + 1
            restoreIdentityRetryScheduled = true
            runAfter(1, function()
                restoreIdentityRetryScheduled = nil
                if config and config.enabled and isChallengeActive() then
                    restoreRun()
                end
            end)
            return false
        end
        restoreIdentityRetries = 0
        currentRun = saved
        archiveInterruptedRun("abandoned", true)
        startRun(mapID, true)
        return currentRun ~= nil
    end
    activeDeathTimeLost = max(0, activeDeathTimeLost)

    local serverNow = getTimestamp()
    local savedStartedAt = tonumber(saved.startedAt)
    local estimatedStartedAt = isFiniteNumber(serverNow)
        and serverNow > 0
        and isFiniteNumber(elapsed)
        and serverNow - elapsed + activeDeathTimeLost
        or nil
    local savedElapsed = tonumber(saved.elapsed)
    local elapsedDidNotRollback = not isFiniteNumber(savedElapsed)
        or elapsed + RUN_START_MATCH_TOLERANCE >= savedElapsed
    local canEstablishSavedIdentity = saved.identityUnverified
        and isFiniteNumber(estimatedStartedAt)
        and estimatedStartedAt > 0
        and elapsedDidNotRollback
    local sameRun = canEstablishSavedIdentity
        or (
            not saved.identityUnverified
            and isFiniteNumber(savedStartedAt)
            and savedStartedAt > 0
            and isFiniteNumber(estimatedStartedAt)
            and math.abs(savedStartedAt - estimatedStartedAt)
                <= RUN_START_MATCH_TOLERANCE
        )

    restoreIdentityRetries = 0
    if not sameRun then
        currentRun = saved
        archiveInterruptedRun("abandoned", true)
        startRun(mapID, true)
        return currentRun ~= nil
    end

    currentRun = saved
    currentRun.active = true
    currentRun.completed = false
    currentRun.timerID = timerID
    currentRun.elapsed = max(0, elapsed)
    if canEstablishSavedIdentity then
        currentRun.startedAt = estimatedStartedAt
        currentRun.identityUnverified = nil
    end
    currentRun.deaths = isFiniteNumber(activeDeaths)
        and max(0, activeDeaths) or currentRun.deaths
    currentRun.deathTimeLost = max(0, activeDeathTimeLost)
    local preciseNow = type(GetTimePreciseSec) == "function"
        and GetTimePreciseSec() or currentRun.elapsed
    currentRun.localClockStart = preciseNow - currentRun.elapsed
    currentRun.pullSnapshots = currentRun.pullSnapshots or {}
    currentRun.savedSplits = currentRun.savedSplits or {}
    discoverSeason()
    if not currentRun.referenceSplits then
        attachReference(currentRun)
    end
    updateObjectives(currentRun)
    suppressTracker()
    if timerFrame then
        timerFrame:SetScript("OnUpdate", timerFrame._onUpdate)
    end
    RefreshDisplay()
    return true
end

local function finalizeCombat(run, preserveDeathData)
    if not run then return end
    if not preserveDeathData then
        updateRunDeathData(run)
    end
    local elapsed = run.elapsed or getRunElapsed(run)
    local wallElapsed = max(
        0,
        elapsed - (tonumber(run.deathTimeLost) or 0)
    )
    Model.FinalizeCombat(run, wallElapsed)
end

local function cleanupRawMeterData(run)
    run.meterStart = nil
    run.meterEnd = nil
    run.liveMeterSnapshot = nil
    run.lastCriteria = nil
    run.finalizeCandidate = nil
    run.finalizeLastSnapshot = nil
    run.finalizeLastDelta = nil
    run.finalizeLastReason = nil
    run.finalizeScheduleToken = nil
    run.finalizeAttempts = nil
    run.finalizeDeadlineAt = nil
    run.finalizeDeadlineReached = nil
    run.meterOverallUpdated = nil
    deadlineScheduled[run] = nil
end

local function isUsableFinalDelta(run, delta)
    return type(delta) == "table"
        and delta.valid == true
        and delta.coreComplete == true
        and isFiniteNumber(delta.durationSeconds)
        and delta.durationSeconds > 0
        and delta.resetDetected ~= true
        and delta.corrupt ~= true
        and run.meterReset ~= true
end

local function getUsableFinalCandidate(run)
    local candidate = run and run.finalizeCandidate
    if type(candidate) ~= "table"
        or not isFiniteNumber(candidate.durationSeconds)
        or candidate.durationSeconds <= 0
        or not isUsableFinalDelta(run, candidate.delta)
    then
        if run then
            run.finalizeCandidate = nil
        end
        return nil
    end
    return candidate
end

local function commitFinalization(run, endSnapshot, delta, reason)
    if not run or run.finalized or run.finalizationDiscarded then return end

    run.meterEnd = endSnapshot
    run.meterDeltaReason = reason
    run.meterReset = run.meterReset
        or (delta and delta.resetDetected == true) or nil
    run.sessionCorrupt = run.sessionCorrupt
        or (delta and delta.corrupt == true) or nil
    run.damageMeterComplete = isUsableFinalDelta(run, delta)

    if delta
        and delta.valid == true
        and isFiniteNumber(delta.durationSeconds)
        and delta.durationSeconds > 0
        and not run.meterReset
        and not run.sessionCorrupt
    then
        run.metrics, run.metricsReason = Analysis.BuildRunMetrics(
            delta,
            run.damageModifierPercent,
            run.combatSeconds
        )
    else
        run.metricsReason = reason
    end

    run.finalized = true
    run.finalizePending = nil
    cleanupRawMeterData(run)
    storeCompletedRun(run)
    if characterHistory
        and characterHistory.pendingFinalization == run
    then
        characterHistory.pendingFinalization = nil
    end
    RefreshDisplay()
end

local function rememberFinalCandidate(run, endSnapshot, delta, reason)
    if not isUsableFinalDelta(run, delta) then return false end

    local candidate = getUsableFinalCandidate(run)
    if not candidate
        or delta.durationSeconds >= candidate.durationSeconds
    then
        run.finalizeCandidate = {
            durationSeconds = delta.durationSeconds,
            snapshot = endSnapshot,
            delta = delta,
            reason = reason,
        }
    end
    return true
end

local function commitFinalizationDeadline(run)
    if not run or run.finalized or run.finalizationDiscarded then return end

    run.finalizeDeadlineReached = true
    local candidate = getUsableFinalCandidate(run)
    if candidate then
        commitFinalization(
            run,
            candidate.snapshot,
            candidate.delta,
            candidate.reason
        )
    else
        commitFinalization(
            run,
            run.finalizeLastSnapshot,
            run.finalizeLastDelta,
            run.finalizeLastReason or "meter_finalization_timeout"
        )
    end
end

local function scheduleFinalizationDeadline(run)
    if not run or run.finalized or run.finalizationDiscarded
        or deadlineScheduled[run]
    then
        return
    end

    if not isFiniteNumber(run.finalizeDeadlineAt) then
        run.finalizeDeadlineAt =
            getTimestamp() + FINALIZE_DEADLINE_SECONDS
    end
    deadlineScheduled[run] = true
    local delay = max(0, run.finalizeDeadlineAt - getTimestamp())
    runAfter(delay, function()
        deadlineScheduled[run] = nil
        commitFinalizationDeadline(run)
    end)
end

ScheduleFinalization = function(run, delay)
    if not run or run.finalized or run.finalizationDiscarded then return end

    run.finalizeScheduleToken =
        (tonumber(run.finalizeScheduleToken) or 0) + 1
    local token = run.finalizeScheduleToken
    runAfter(delay or 0, function()
        if run.finalized or run.finalizationDiscarded
            or run.finalizeScheduleToken ~= token
        then
            return
        end
        TryFinalizeRun(run)
    end)
end

TryFinalizeRun = function(run)
    if not run or run.finalized or run.finalizationDiscarded then return end
    if run.finalizeDeadlineReached
        or (
            isFiniteNumber(run.finalizeDeadlineAt)
            and getTimestamp() >= run.finalizeDeadlineAt
        )
    then
        commitFinalizationDeadline(run)
        return
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        run.finalizePending = true
        RefreshDisplay()
        return
    end

    run.finalizePending = true
    run.finalizeAttempts = (tonumber(run.finalizeAttempts) or 0) + 1
    local endSnapshot, endReason = Meter.CollectRunSnapshot(
        run.roster,
        getOverallSessionType()
    )
    local delta, deltaReason = makeRunDelta(run, endSnapshot)
    local reason = deltaReason or endReason
    if delta and isFiniteNumber(delta.durationSeconds)
        and delta.durationSeconds <= 0
    then
        reason = "meter_duration_unavailable"
    end

    run.meterEndReason = endReason
    run.finalizeLastSnapshot = endSnapshot
    run.finalizeLastDelta = delta
    run.finalizeLastReason = reason
    run.meterReset = run.meterReset
        or (delta and delta.resetDetected == true) or nil
    run.sessionCorrupt = run.sessionCorrupt
        or (delta and delta.corrupt == true) or nil

    local currentCandidateIsUsable =
        rememberFinalCandidate(run, endSnapshot, delta, reason)
    if run.meterReset or run.sessionCorrupt then
        run.finalizeCandidate = nil
        commitFinalization(run, endSnapshot, delta,
            run.meterReset and "meter_reset" or "session_corrupt")
        return
    end

    if currentCandidateIsUsable and run.meterOverallUpdated then
        local candidate = getUsableFinalCandidate(run)
        commitFinalization(
            run,
            candidate.snapshot,
            candidate.delta,
            candidate.reason
        )
        return
    end

    if run.finalizeAttempts >= #FINALIZE_RETRY_DELAYS then
        local candidate = getUsableFinalCandidate(run)
        if candidate then
            commitFinalization(
                run,
                candidate.snapshot,
                candidate.delta,
                candidate.reason
            )
        else
            commitFinalization(
                run,
                endSnapshot,
                delta,
                reason or "meter_snapshot_unavailable"
            )
        end
        return
    end

    ScheduleFinalization(
        run,
        FINALIZE_RETRY_DELAYS[run.finalizeAttempts + 1]
    )
end

local function markOverallMeterUpdated()
    local pending = characterHistory
        and characterHistory.pendingFinalization
    if type(pending) == "table"
        and not pending.finalized
        and not pending.finalizationDiscarded
    then
        pending.meterOverallUpdated = true
        ScheduleFinalization(pending, FINALIZE_QUIET_DELAY)
    end
end

local function restorePendingFinalization(showRun)
    ensureHistory()
    local pending = characterHistory.pendingFinalization
    if type(pending) ~= "table" then return false end

    if pending.finalized then
        characterHistory.pendingFinalization = nil
        return false
    end

    pending.active = false
    pending.completed = true
    pending.finalizePending = true
    local restoredDeadline = isFiniteNumber(pending.completedAt)
        and pending.completedAt + FINALIZE_DEADLINE_SECONDS
        or getTimestamp()
    if not isFiniteNumber(pending.finalizeDeadlineAt)
        or pending.finalizeDeadlineAt > restoredDeadline
    then
        pending.finalizeDeadlineAt = restoredDeadline
    end
    if showRun then
        currentRun = pending
    end

    if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
        ScheduleFinalization(pending, FINALIZE_RETRY_DELAYS[1])
    end
    scheduleFinalizationDeadline(pending)
    return true
end

local function readCompletionRoster(completion)
    local guids = {}
    local members = type(completion) == "table" and completion.members
    if not isNonSecret(members) or type(members) ~= "table" then
        return guids
    end

    for _, member in ipairs(members) do
        if isNonSecret(member) and type(member) == "table" then
            local guid = member.memberGUID
            if isNonSecret(guid) and type(guid) == "string"
                and guid ~= ""
            then
                guids[#guids + 1] = guid
            end
        end
    end
    return guids
end

local function rosterMatchesCompletion(roster, completionGUIDs)
    if type(roster) ~= "table" or type(completionGUIDs) ~= "table"
        or #completionGUIDs == 0
    then
        return true
    end

    local expected = {}
    for _, member in ipairs(roster) do
        if type(member) == "table" and type(member.guid) == "string" then
            expected[member.guid] = true
        end
    end
    if #roster ~= #completionGUIDs then return false end
    for _, guid in ipairs(completionGUIDs) do
        if not expected[guid] then return false end
    end
    return true
end

local function completeRun()
    local run = currentRun
    if not run or not run.active then return end

    run.elapsed = getRunElapsed(run)
    if type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
        local completion = C_ChallengeMode.GetChallengeCompletionInfo()
        if isNonSecret(completion) and type(completion) == "table" then
            if isNonSecret(completion.time)
                and type(completion.time) == "number"
                and completion.time > 0
            then
                run.elapsed = completion.time / 1000
            end
            run.onTime = completion.onTime == true
            run.upgradeLevels = completion.keystoneUpgradeLevels
            run.practice = completion.practiceRun == true
            run.scoreEligible = completion.isEligibleForScore == true
            run.completionRosterGUIDs = readCompletionRoster(completion)
            run.rosterCorrupt = not rosterMatchesCompletion(
                run.roster,
                run.completionRosterGUIDs
            ) or nil
        end
    end

    updateObjectives(run)
    finalizeCombat(run)
    run.active = false
    run.completed = true
    run.completedAt = getTimestamp()
    run.finalizeDeadlineAt =
        run.completedAt + FINALIZE_DEADLINE_SECONDS
    run.finalizePending = true
    persistActiveRun()
    persistPendingFinalization(run)
    local showDebrief = config and config.showDebrief ~= false
    if not showDebrief then
        currentRun = nil
        restoreTracker()
    end
    if timerFrame then
        timerFrame:SetScript("OnUpdate", nil)
        if not showDebrief then
            timerFrame:Hide()
        end
    end
    if showDebrief then
        RefreshDisplay()
    end

    if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
        ScheduleFinalization(run, FINALIZE_RETRY_DELAYS[1])
    end
    scheduleFinalizationDeadline(run)
end

archiveInterruptedRun = function(reason, preserveElapsed)
    local run = currentRun
    if not run or not run.active then return end

    if preserveElapsed then
        run.elapsed = isFiniteNumber(run.elapsed)
            and max(0, run.elapsed) or 0
    else
        run.elapsed = getRunElapsed(run)
    end
    -- Reset/zone transitions can clear Blizzard's death counter before this
    -- handler runs, so retain the last death snapshot owned by this run.
    finalizeCombat(run, true)
    run.active = false
    run.completed = false
    run.abandoned = reason == "abandoned"
    run.reset = reason == "reset"
    run.damageMeterComplete = false
    run.baselineEligible = false
    run.baselineReason = reason == "reset" and "reset_run"
        or "abandoned_run"
    cleanupRawMeterData(run)
    if isHistoryEra() then
        storeCompletedRun(run)
    end

    ensureHistory()
    characterHistory.activeRun = nil
    currentRun = nil
    restoreTracker()
    if timerFrame then
        timerFrame:SetScript("OnUpdate", nil)
        timerFrame:Hide()
    end
end

local function dismissCompletedRun()
    if currentRun and currentRun.completed then
        currentRun = nil
    end
    restoreTracker()
    if timerFrame then timerFrame:Hide() end
end

local function onTimerUpdate(_, elapsed)
    if not currentRun or not currentRun.active then return end
    updateAccumulator = updateAccumulator + elapsed
    if updateAccumulator < TIMER_REFRESH_INTERVAL then return end
    updateAccumulator = 0

    currentRun.elapsed = getRunElapsed(currentRun)
    establishRunIdentity(currentRun, currentRun.elapsed)
    if shouldSuppressTracker() then
        applyTrackerSuppression()
    end
    RefreshDisplay()
end

local function onEvent(_, event, ...)
    if event == "CHALLENGE_MODE_MAPS_UPDATE" then
        discoverSeason()
    elseif event == "CHALLENGE_MODE_START" then
        startRun(...)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        completeRun()
    elseif event == "CHALLENGE_MODE_RESET" then
        archiveInterruptedRun("reset")
    elseif event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        RefreshDisplay()
    elseif event == "SCENARIO_CRITERIA_UPDATE"
        or event == "SCENARIO_UPDATE"
    then
        if currentRun and currentRun.active then
            currentRun.elapsed = getRunElapsed(currentRun)
            updateObjectives(currentRun)
            persistActiveRun()
            RefreshDisplay()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if currentRun and currentRun.active
            and not currentRun.combatStartedElapsed
        then
            currentRun.elapsed = getRunElapsed(currentRun)
            updateRunDeathData(currentRun)
            currentRun.pullCount = (currentRun.pullCount or 0) + 1
            currentRun.combatStartedElapsed = max(
                0,
                currentRun.elapsed - (currentRun.deathTimeLost or 0)
            )
            persistActiveRun()
            RefreshDisplay()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if trackerRestorePending then
            restoreTrackerNow()
        end
        local pendingFinalization = characterHistory
            and characterHistory.pendingFinalization
        if type(pendingFinalization) == "table"
            and not pendingFinalization.finalized
        then
            ScheduleFinalization(
                pendingFinalization,
                FINALIZE_RETRY_DELAYS[1]
            )
        end
        if not config or not config.enabled then
            if eventFrame then
                eventFrame:UnregisterAllEvents()
            end
            return
        end
        if currentRun then
            if currentRun.active then
                currentRun.elapsed = getRunElapsed(currentRun)
                finalizeCombat(currentRun)
                persistActiveRun()
                runAfter(0.25, function()
                    if currentRun and currentRun.active then
                        capturePullSnapshot(currentRun)
                    end
                end)
            end
        end
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        local _, sessionID = ...
        if isNonSecret(sessionID) and sessionID == 0 then
            markOverallMeterUpdated()
        end
    elseif event == "DAMAGE_METER_RESET" then
        if currentRun and currentRun.active then
            currentRun.meterReset = true
            persistActiveRun()
        end
        local pending = characterHistory
            and characterHistory.pendingFinalization
        if type(pending) == "table" and not pending.finalized then
            pending.meterReset = true
            pending.finalizeCandidate = nil
            if type(InCombatLockdown) ~= "function"
                or not InCombatLockdown()
            then
                ScheduleFinalization(pending, 0)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        requestMapInfo()
        discoverSeason()
        local activeChallenge = isChallengeActive()
        restorePendingFinalization(
            not activeChallenge and config.showDebrief ~= false
        )
        if activeChallenge then
            restoreRun()
        elseif not currentRun and characterHistory
            and type(characterHistory.activeRun) == "table"
        then
            currentRun = characterHistory.activeRun
            archiveInterruptedRun("abandoned")
        elseif currentRun and currentRun.active then
            archiveInterruptedRun("abandoned")
        elseif currentRun and currentRun.completed then
            local _, instanceType = GetInstanceInfo()
            if instanceType ~= "party" then
                dismissCompletedRun()
            end
        end
        if currentRun and currentRun.completed
            and config.showDebrief ~= false
            and config.hideObjectiveTracker ~= false
        then
            suppressTracker()
        end
        runAfter(2, function()
            if config and config.enabled and isChallengeActive() then
                restoreRun()
            end
        end)
    elseif event == "WORLD_STATE_TIMER_START" then
        local timerID = ...
        if currentRun and currentRun.active
            and isNonSecret(timerID) and type(timerID) == "number"
        then
            local _, elapsed, timerType = GetWorldElapsedTime(timerID)
            local challengeType = Enum and Enum.WorldElapsedTimerTypes
                and Enum.WorldElapsedTimerTypes.ChallengeMode
            if isNonSecret(elapsed) and isNonSecret(timerType)
                and type(elapsed) == "number"
                and timerType == challengeType
            then
                currentRun.timerID = timerID
                currentRun.elapsed = max(0, elapsed)
                establishRunIdentity(currentRun, currentRun.elapsed)
                persistActiveRun()
                RefreshDisplay()
            end
        elseif isChallengeActive() then
            restoreRun()
        end
    elseif event == "WORLD_STATE_TIMER_STOP" then
        local timerID = ...
        local matchesCurrentTimer = false
        if isNonSecret(timerID) then
            matchesCurrentTimer = timerID == nil
                or timerID == (currentRun and currentRun.timerID)
        end
        if currentRun and currentRun.active and matchesCurrentTimer
        then
            currentRun.elapsed = getRunElapsed(currentRun)
            currentRun.timerID = nil
            persistActiveRun()
            RefreshDisplay()
        end
    end
end

local function createText(parent, justify)
    local text = AF.CreateFontString(parent)
    text:SetJustifyH(justify or "LEFT")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    return text
end

local function createHoverRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.accentColor = parent.accentColor or "BFI"
    row.label = createText(row, "LEFT")
    row.value = createText(row, "RIGHT")
    row.compare = createText(row, "RIGHT")
    row:SetScript("OnEnter", function(self)
        if self.tooltip then
            self.tooltip(self)
        end
    end)
    row:SetScript("OnLeave", function()
        AF.HideTooltip()
    end)
    return row
end

local function saveTimerPosition(point, x, y)
    if not config or not point then return end
    if type(config.position) ~= "table" then
        config.position = {}
    end
    config.position[1] = point
    config.position[2] = x
    config.position[3] = y
    AF.Fire("BFI_RefreshOptions", "uiWidgets")
end

local function createTimerFrame()
    timerFrame = AF.CreateBorderedFrame(
        AF.UIParent,
        "BFI_MythicPlusTimer",
        320,
        160,
        "background",
        "border"
    )
    timerFrame:SetFrameStrata("MEDIUM")
    timerFrame:SetClampedToScreen(true)
    timerFrame:Hide()
    timerFrame._onUpdate = onTimerUpdate
    AF.SetDraggable(timerFrame, nil, true, nil, function(self)
        local point, x, y = AF.CalcPoint(self)
        saveTimerPosition(point, x, y)
        AF.LoadPosition(self, config.position)
    end)
    timerFrame:RegisterForDrag()
    timerFrame:EnableMouse(false)

    AF.CreateMover(
        timerFrame,
        "BFI: " .. L["UI Widgets"],
        L["Mythic+ Timer"],
        saveTimerPosition
    )

    timerFrame.title = createText(timerFrame, "LEFT")
    timerFrame.time = createText(timerFrame, "RIGHT")
    timerFrame.affixIcons = {}
    for index = 1, 4 do
        local icon = AF.CreateIcon(timerFrame, nil, 16, "border")
        icon.accentColor = timerFrame.accentColor or "BFI"
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", function(self)
            if self.tooltipLines then
                AF.ShowTooltip(
                    self,
                    "TOPLEFT",
                    0,
                    2,
                    self.tooltipLines
                )
            end
        end)
        icon:SetScript("OnLeave", AF.HideTooltip)
        timerFrame.affixIcons[index] = icon
    end
    timerFrame.thresholds = createText(timerFrame, "RIGHT")
    timerFrame.timerBar = AF.CreateBlizzardStatusBar(
        timerFrame,
        0,
        100,
        304,
        8,
        "BFI",
        "border"
    )
    timerFrame.timerBar:SetScript("OnValueChanged", nil)
    timerFrame.plusThreeTick = AF.CreateTexture(
        timerFrame.timerBar,
        nil,
        "softlime",
        "OVERLAY"
    )
    AF.SetWidth(timerFrame.plusThreeTick, 1)
    timerFrame.plusTwoTick = AF.CreateTexture(
        timerFrame.timerBar,
        nil,
        "skyblue",
        "OVERLAY"
    )
    AF.SetWidth(timerFrame.plusTwoTick, 1)
    timerFrame.info = createText(timerFrame, "LEFT")
    timerFrame.remaining = createText(timerFrame, "RIGHT")
    timerFrame.forcesLabel = createText(timerFrame, "LEFT")
    timerFrame.forcesValue = createText(timerFrame, "RIGHT")
    timerFrame.forcesBar = AF.CreateBlizzardStatusBar(
        timerFrame,
        0,
        100,
        304,
        6,
        "vividblue",
        "border"
    )
    timerFrame.forcesBar:SetScript("OnValueChanged", nil)
    timerFrame.execution = createText(timerFrame, "LEFT")
    timerFrame.objectiveRows = {}

    timerFrame.summaryTitle = createText(timerFrame, "LEFT")
    timerFrame.closeButton = AF.CreateCloseButton(
        timerFrame,
        nil,
        16,
        16,
        10
    )
    timerFrame.closeButton:SetScript("OnClick", dismissCompletedRun)
    timerFrame.closeButton:SetTooltip(L["Dismiss debrief"])
    timerFrame.closeButton:Hide()
    timerFrame.groupRows = {}
    for index = 1, 4 do
        timerFrame.groupRows[index] = createHoverRow(timerFrame)
    end
    timerFrame.playerHeader = createHoverRow(timerFrame)
    timerFrame.playerHeader.extra = createText(
        timerFrame.playerHeader,
        "RIGHT"
    )
    timerFrame.playerRows = {}
    for index = 1, 5 do
        local row = createHoverRow(timerFrame)
        row.extra = createText(row, "RIGHT")
        timerFrame.playerRows[index] = row
    end
    timerFrame.footer = createText(timerFrame, "LEFT")
end

local function getBaseFontSize()
    return max(5, tonumber(config.font and config.font[2]) or 12)
end

local function getEffectiveFontSize(sizeDelta)
    return max(5, getBaseFontSize() + (sizeDelta or 0))
end

local function setFont(text, sizeDelta)
    AF.SetFont(text, config.font, getEffectiveFontSize(sizeDelta))
end

local function getLineHeight(sizeDelta, minimum, padding)
    return max(
        minimum or 1,
        getEffectiveFontSize(sizeDelta) + (padding or 0)
    )
end

local function getTextBlockHeight(text, minimum, padding)
    local height
    if text and type(text.GetStringHeight) == "function" then
        height = text:GetStringHeight()
    end
    if not isFiniteNumber(height) or height <= 0 then
        height = getBaseFontSize()
    end
    return max(minimum or 1, height + (padding or 0))
end

local function setStatusBarColor(bar, color)
    if bar._bfiColor == color then return end
    bar._bfiColor = color
    bar:SetStatusBarColor(AF.GetColorRGB(color, 0.7))
    if bar.tex and type(bar.tex.SetColor) == "function" then
        bar.tex:SetColor(AF.GetColorTable(color, 0.2))
    end
end

local function applyFrameConfig()
    if not timerFrame then return end
    AF.SetWidth(timerFrame, config.width)
    AF.SetWidth(timerFrame.timerBar, config.width - 16)
    AF.SetWidth(timerFrame.forcesBar, config.width - 16)
    AF.UpdateMoverSave(timerFrame, saveTimerPosition)
    AF.LoadPosition(timerFrame, config.position)
    timerFrame.timerBar._bfiColor = nil
    timerFrame.forcesBar._bfiColor = nil

    setFont(timerFrame.title, 2)
    setFont(timerFrame.time, 2)
    setFont(timerFrame.thresholds, -1)
    setFont(timerFrame.info, -1)
    setFont(timerFrame.remaining, -1)
    setFont(timerFrame.forcesLabel, -1)
    setFont(timerFrame.forcesValue, -1)
    setFont(timerFrame.execution, -1)
    setFont(timerFrame.summaryTitle, 1)
    setFont(timerFrame.footer, -2)
    for _, row in ipairs(timerFrame.groupRows) do
        setFont(row.label, -1)
        setFont(row.value, -1)
        setFont(row.compare, -2)
    end
    setFont(timerFrame.playerHeader.label, -2)
    setFont(timerFrame.playerHeader.value, -2)
    setFont(timerFrame.playerHeader.compare, -2)
    setFont(timerFrame.playerHeader.extra, -2)
    for _, row in ipairs(timerFrame.playerRows) do
        setFont(row.label, -1)
        setFont(row.value, -1)
        setFont(row.compare, -2)
        setFont(row.extra, -2)
    end
end

local function hideRowsFrom(rows, first)
    for index = first or 1, #rows do
        rows[index]:Hide()
    end
end

local function hideSummaryDetails()
    for _, row in ipairs(timerFrame.groupRows) do
        row:Hide()
    end
    timerFrame.playerHeader:Hide()
    hideRowsFrom(timerFrame.playerRows, 1)
    timerFrame.footer:Hide()
end

local function hideSummary()
    hideSummaryDetails()
    timerFrame.summaryTitle:Hide()
    timerFrame.closeButton:Hide()
end

local function anchorText(text, point, relative, relativePoint, x, y)
    AF.ClearPoints(text)
    AF.SetPoint(
        text,
        point,
        relative or timerFrame,
        relativePoint or point,
        x,
        y
    )
end

local function getContentWidth()
    return max(1, (tonumber(config.width) or 320) - 16)
end

local function setTruncatedText(
    text,
    value,
    width,
    alignment
)
    AF.SetWidth(text, width)
    local snappedWidth = text:GetWidth()
    if not isFiniteNumber(snappedWidth) or snappedWidth <= 0 then
        snappedWidth = width
    end
    AF.TruncateFontStringByWidth(
        text,
        snappedWidth,
        alignment or "left",
        true,
        value
    )
end

local function layoutThreeColumnRow(
    row,
    labelFraction,
    valueFraction
)
    local contentWidth = getContentWidth()
    local gap = 6
    local labelWidth = floor(contentWidth * labelFraction)
    local valueWidth = floor(contentWidth * valueFraction)
    local compareWidth = max(
        1,
        contentWidth - labelWidth - valueWidth - gap * 2
    )

    anchorText(row.label, "LEFT", row, "LEFT", 0, 0)
    anchorText(
        row.value,
        "LEFT",
        row,
        "LEFT",
        labelWidth + gap,
        0
    )
    anchorText(row.compare, "RIGHT", row, "RIGHT", 0, 0)
    AF.SetWidth(row.label, labelWidth)
    AF.SetWidth(row.value, valueWidth)
    AF.SetWidth(row.compare, compareWidth)
end

local function layoutFourColumnRow(row)
    local contentWidth = getContentWidth()
    local gap = 5
    local labelWidth = floor(contentWidth * 0.30)
    local valueWidth = floor(contentWidth * 0.27)
    local compareWidth = floor(contentWidth * 0.17)
    local extraWidth = max(
        1,
        contentWidth
            - labelWidth
            - valueWidth
            - compareWidth
            - gap * 3
    )

    anchorText(row.label, "LEFT", row, "LEFT", 0, 0)
    anchorText(
        row.value,
        "LEFT",
        row,
        "LEFT",
        labelWidth + gap,
        0
    )
    anchorText(
        row.compare,
        "LEFT",
        row,
        "LEFT",
        labelWidth + valueWidth + gap * 2,
        0
    )
    anchorText(row.extra, "RIGHT", row, "RIGHT", 0, 0)
    AF.SetWidth(row.label, labelWidth)
    AF.SetWidth(row.value, valueWidth)
    AF.SetWidth(row.compare, compareWidth)
    AF.SetWidth(row.extra, extraWidth)
end

local function ensureObjectiveRow(index)
    local row = timerFrame.objectiveRows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, timerFrame)
    row.accentColor = timerFrame.accentColor or "BFI"
    row.name = createText(row, "LEFT")
    row.value = createText(row, "RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local objective = self.objective
        if not AF.Tooltip or not objective then
            return
        end

        AF.ShowTooltip(
            self,
            "LEFT",
            -2,
            0,
            {
                objective.name ~= "" and objective.name
                    or L["Objective split"],
            }
        )
        local tooltip = AF.Tooltip
        if config.showSplits == false
            or not objective.referenceElapsed
        then
            return
        end
        tooltip:AddDoubleLine(
            L["Previous run"],
            ("+%d  %s"):format(
                objective.referenceLevel or 0,
                Model.FormatClock(
                    objective.referenceRawElapsed
                        or objective.referenceElapsed
                )
            ),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
        if objective.referenceNormalized then
            tooltip:AddDoubleLine(
                L["Level-adjusted target"],
                Model.FormatClock(objective.referenceElapsed),
                0.8, 0.8, 0.8,
                0.49, 0.75, 1
            )
            tooltip:AddLine(
                L[
                    "Adjustment scales measured combat time by Blizzard's "
                    .. "enemy-health modifier; travel time is unchanged."
                ],
                0.55, 0.55, 0.55, true
            )
        elseif objective.referenceNormalizationReason
            == "combat_context_unavailable"
        then
            tooltip:AddLine(
                L[
                    "Raw split shown because the reference predates "
                    .. "combat-time tracking."
                ],
                0.55, 0.55, 0.55, true
            )
        end
        tooltip:Show()
    end)
    row:SetScript("OnLeave", AF.HideTooltip)
    setFont(row.name, -1)
    setFont(row.value, -1)
    timerFrame.objectiveRows[index] = row
    return row
end

local function formatNumber(value)
    if not isFiniteNumber(value) then return "—" end
    return AF.FormatNumber(value)
end

local function getAssessmentColor(assessment)
    return bandColors[assessment and assessment.band or "unrated"]
        or "gray"
end

local function formatAssessment(assessment, isCount)
    if type(assessment) ~= "table" then
        return L["unavailable"]
    end
    if not assessment.baseline or not assessment.baseline.available then
        return L["collecting %d/%d"]:format(
            assessment.sampleCount or 0,
            H.MINIMUM_BASELINE_SAMPLES
        )
    end

    local current = assessment.value
    local center = assessment.baselineCenter
    local difference = current - center
    local arrow = difference > 0 and "▲" or difference < 0 and "▼" or "•"
    if isCount then
        local roundedDifference = difference >= 0
            and floor(difference + 0.5)
            or ceil(difference - 0.5)
        return ("%s%+d %s"):format(
            arrow,
            roundedDifference,
            assessmentLabels[assessment.textID] or assessment.textID
        )
    end

    local percent = center ~= 0 and difference / center * 100 or 0
    return ("%s%+.0f%% %s"):format(
        arrow,
        percent,
        assessmentLabels[assessment.textID] or assessment.textID
    )
end

local function addAssessmentTooltip(
    owner,
    title,
    metric,
    assessment,
    isCount
)
    if not AF.Tooltip then return end
    AF.ShowTooltip(owner, "LEFT", -2, 0, {title})
    local tooltip = AF.Tooltip
    if metric and metric.available then
        tooltip:AddDoubleLine(
            L["Current"],
            isCount and tostring(floor(metric.raw + 0.5))
                or formatNumber(metric.raw),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
        if metric.normalized then
            tooltip:AddDoubleLine(
                L["Level-normalized"],
                formatNumber(metric.normalized),
                0.8, 0.8, 0.8,
                1, 1, 1
            )
        end
        if metric.normalizedPerMinute then
            tooltip:AddDoubleLine(
                L["Normalized / combat min"],
                formatNumber(metric.normalizedPerMinute),
                0.8, 0.8, 0.8,
                1, 1, 1
            )
        elseif metric.perMinute then
            tooltip:AddDoubleLine(
                L["Per combat min"],
                ("%.1f"):format(metric.perMinute),
                0.8, 0.8, 0.8,
                1, 1, 1
            )
        end
    else
        tooltip:AddLine(
            L["Data unavailable for this run"],
            0.6,
            0.6,
            0.6
        )
    end
    if assessment and assessment.baseline
        and assessment.baseline.available
    then
        tooltip:AddDoubleLine(
            L["Own baseline"],
            isCount and ("%.1f"):format(assessment.baselineCenter)
                or formatNumber(assessment.baselineCenter),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
        tooltip:AddDoubleLine(
            L["Comparable runs"],
            ("%d • %s"):format(
                assessment.sampleCount,
                maturityLabels[assessment.maturity]
                    or assessment.maturity
            ),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
    end
    tooltip:Show()
end

local function addPlayerTooltip(owner, player, playerAssessments)
    if not AF.Tooltip then return end
    AF.ShowTooltip(
        owner,
        "LEFT",
        -2,
        0,
        {player.name or _G.UNKNOWN or L["Unknown"]}
    )
    local tooltip = AF.Tooltip
    local metrics = player.metrics or {}
    if metrics.damageTaken and metrics.damageTaken.available then
        tooltip:AddDoubleLine(
            L["Damage load"],
            formatNumber(metrics.damageTaken.raw),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
    end
    if metrics.dps and metrics.dps.available then
        tooltip:AddDoubleLine(
            L["DPS context"],
            formatNumber(metrics.dps.raw),
            0.8, 0.8, 0.8,
            1, 1, 1
        )
    end
    local avoidAssessment = playerAssessments
        and playerAssessments.avoidableDamageTaken
    local intAssessment = playerAssessments and playerAssessments.interrupts
    if avoidAssessment then
        tooltip:AddLine(
            L["Avoidable: %s"]:format(
                formatAssessment(avoidAssessment, false)
            ),
            AF.GetColorRGB(getAssessmentColor(avoidAssessment))
        )
    end
    if intAssessment then
        tooltip:AddLine(
            L["Interrupts: %s"]:format(
                formatAssessment(intAssessment, true)
            ),
            AF.GetColorRGB(getAssessmentColor(intAssessment))
        )
    end

    if type(player.topAvoidableSpells) == "table"
        and #player.topAvoidableSpells > 0
    then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Top avoidable abilities"], 1, 0.82, 0)
        for _, spell in ipairs(player.topAvoidableSpells) do
            local spellName
            if _G.C_Spell and _G.C_Spell.GetSpellName then
                spellName = _G.C_Spell.GetSpellName(spell.spellID)
            elseif _G.GetSpellInfo then
                spellName = _G.GetSpellInfo(spell.spellID)
            end
            if not isNonSecret(spellName) or type(spellName) ~= "string" then
                spellName = L["Spell %s"]:format(tostring(spell.spellID))
            end
            tooltip:AddDoubleLine(
                spellName,
                formatNumber(spell.totalAmount),
                0.8, 0.8, 0.8,
                1, 0.5, 0.5
            )
        end
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(
        L["Avoidable classifications can include intentional soaks."],
        0.55, 0.55, 0.55, true
    )
    tooltip:Show()
end

local function updateDeathData(run)
    updateRunDeathData(run)
end

local function renderAffixes(run, y)
    if config.showAffixes == false then
        for _, icon in ipairs(timerFrame.affixIcons) do
            icon.tooltipLines = nil
            icon:Hide()
        end
        return y
    end

    local shown = 0
    for _, affixID in ipairs(run.affixes or {}) do
        local name, description, texture
        if type(C_ChallengeMode.GetAffixInfo) == "function" then
            name, description, texture =
                C_ChallengeMode.GetAffixInfo(affixID)
        end
        if isNonSecret(texture) and type(texture) == "number" then
            shown = shown + 1
            local icon = timerFrame.affixIcons[shown]
            if not icon then break end
            icon:SetIcon(texture)
            if not isNonSecret(name) or type(name) ~= "string"
                or name == ""
            then
                name = L["Affix %d"]:format(affixID)
            end
            icon.tooltipLines = {name}
            if isNonSecret(description) and type(description) == "string"
                and description ~= ""
            then
                icon.tooltipLines[2] = description
            end
            AF.ClearPoints(icon)
            AF.SetPoint(
                icon,
                "TOPLEFT",
                timerFrame,
                "TOPLEFT",
                8 + (shown - 1) * 19,
                y
            )
            icon:Show()
        end
    end
    for index = shown + 1, #timerFrame.affixIcons do
        local icon = timerFrame.affixIcons[index]
        icon.tooltipLines = nil
        icon:Hide()
    end
    return shown > 0
        and y - getLineHeight(-1, 19, 6)
        or y
end

local function renderObjectives(run, y)
    if config.showObjectives == false then
        hideRowsFrom(timerFrame.objectiveRows, 1)
        return y
    end
    local bosses = Model.GetBossObjectives(run.objectives)
    local rowHeight = getLineHeight(-1, 16, 4)
    local shown = 0
    for index, objective in ipairs(bosses) do
        local row = ensureObjectiveRow(index)
        shown = index
        AF.ClearPoints(row)
        AF.SetPoint(row, "TOPLEFT", timerFrame, "TOPLEFT", 8, y)
        AF.SetPoint(row, "RIGHT", timerFrame, "RIGHT", -8, 0)
        AF.SetHeight(row, rowHeight - 1)
        anchorText(row.name, "LEFT", row, "LEFT", 0, 0)
        anchorText(row.value, "RIGHT", row, "RIGHT", 0, 0)
        local contentWidth = getContentWidth()
        local nameWidth = contentWidth * 0.62
        AF.SetWidth(row.value, contentWidth * 0.35)

        setTruncatedText(
            row.name,
            (
                objective.completed
                    and AF.WrapTextInColor("✓", "softlime") .. " "
                    or "○ "
            )
            .. (objective.name ~= "" and objective.name
                or L["Objective %d"]:format(index)),
            nameWidth
        )
        row.objective = objective
        if objective.completed and objective.elapsed then
            local value = Model.FormatClock(objective.elapsed)
            local delta = Model.CalculateSplitDelta(objective)
            if config.showSplits ~= false and delta then
                local color = delta <= 0 and "softlime" or "firebrick"
                local deltaText = (
                    objective.referenceNormalized and "~" or ""
                ) .. Model.FormatClock(delta, true)
                value = value .. "  " .. AF.WrapTextInColor(
                    deltaText,
                    color
                )
            end
            row.value:SetText(value)
        elseif config.showSplits ~= false and objective.referenceElapsed then
            row.value:SetText(
                AF.WrapTextInColor(
                    L["target %s"]:format(
                        Model.FormatClock(objective.referenceElapsed)
                    ),
                    "gray"
                )
            )
        else
            row.value:SetText("")
        end
        row:Show()
        y = y - rowHeight
    end
    hideRowsFrom(timerFrame.objectiveRows, shown + 1)
    return y
end

local function renderExecution(run, y)
    if config.showExecution == false or not run.active then
        timerFrame.execution:Hide()
        return y
    end

    local snapshot = run.liveMeterSnapshot
    local interrupts = snapshot and snapshot.group
        and snapshot.group.interrupts
    local avoidable = snapshot and snapshot.group
        and snapshot.group.avoidableDamageTaken
    local pieces = {}
    if interrupts and interrupts.available then
        pieces[#pieces + 1] = L["INT %d"]:format(
            floor(interrupts.value + 0.5)
        )
    end
    if avoidable and avoidable.available then
        pieces[#pieces + 1] = L["Avoidable %s"]:format(
            formatNumber(avoidable.value)
        )
    end
    if #pieces == 0 then
        pieces[1] = L["Execution updates after combat"]
    end
    timerFrame.execution:SetText(table.concat(pieces, "  •  "))
    timerFrame.execution:SetTextColor(AF.GetColorRGB("gray"))
    anchorText(timerFrame.execution, "TOPLEFT", timerFrame,
        "TOPLEFT", 8, y)
    AF.SetWidth(timerFrame.execution, config.width - 16)
    timerFrame.execution:Show()
    return y - getLineHeight(-1, 17, 5)
end

local function configureSummaryRow(
    row,
    y,
    label,
    metric,
    assessment,
    isCount
)
    AF.ClearPoints(row)
    AF.SetPoint(row, "TOPLEFT", timerFrame, "TOPLEFT", 8, y)
    AF.SetPoint(row, "RIGHT", timerFrame, "RIGHT", -8, 0)
    local rowHeight = getLineHeight(-1, 18, 5)
    AF.SetHeight(row, rowHeight - 1)
    layoutThreeColumnRow(row, 0.30, 0.22)
    setTruncatedText(
        row.label,
        label,
        row.label:GetWidth()
    )
    local valueText =
        metric and metric.available
            and (isCount and tostring(floor(metric.raw + 0.5))
                or formatNumber(metric.raw))
            or "—"
    setTruncatedText(
        row.value,
        valueText,
        row.value:GetWidth(),
        "right"
    )
    local comparisonText = formatAssessment(assessment, isCount)
    if metric and metric.normalized ~= nil and assessment then
        comparisonText = L["~%s"]:format(comparisonText)
    end
    setTruncatedText(
        row.compare,
        comparisonText,
        row.compare:GetWidth(),
        "right"
    )
    row.compare:SetTextColor(AF.GetColorRGB(
        getAssessmentColor(assessment)
    ))
    row.tooltip = function(owner)
        addAssessmentTooltip(
            owner,
            label,
            metric,
            assessment,
            isCount
        )
    end
    row:Show()
    return rowHeight
end

local function renderSummary(run, y)
    if not run.completed or config.showDebrief == false then
        hideSummary()
        return y
    end

    AF.ClearPoints(timerFrame.closeButton)
    AF.SetPoint(
        timerFrame.closeButton,
        "TOPRIGHT",
        timerFrame,
        "TOPRIGHT",
        -4,
        y + 2
    )
    timerFrame.closeButton:Show()
    timerFrame.summaryTitle:SetText(
        run.finalized and L["Run debrief"] or L["Finalizing run data…"]
    )
    timerFrame.summaryTitle:SetTextColor(AF.GetColorRGB("BFI"))
    anchorText(timerFrame.summaryTitle, "TOPLEFT", timerFrame,
        "TOPLEFT", 8, y)
    AF.SetWidth(timerFrame.summaryTitle, max(1, config.width - 38))
    timerFrame.summaryTitle:Show()
    y = y - getLineHeight(1, 21, 8)

    if not run.finalized then
        hideSummaryDetails()
        return y
    end
    local metrics = run.metrics
    if not metrics then
        hideSummaryDetails()
        local reason = baselineReasonLabels[run.baselineReason]
            or L["data unavailable"]
        local unavailableMessage =
            L["Blizzard Damage Meter data unavailable for this run (%s)."]
        timerFrame.footer:SetText(
            unavailableMessage:format(reason)
        )
        timerFrame.footer:SetTextColor(AF.GetColorRGB("gray"))
        anchorText(timerFrame.footer, "TOPLEFT", timerFrame,
            "TOPLEFT", 8, y)
        AF.SetWidth(timerFrame.footer, config.width - 16)
        timerFrame.footer:SetWordWrap(true)
        timerFrame.footer:Show()
        return y - getTextBlockHeight(
            timerFrame.footer,
            30,
            6
        )
    end

    local assessments = run.assessments or {group = {}, players = {}}
    y = y - configureSummaryRow(
        timerFrame.groupRows[1],
        y,
        L["Damage load"],
        metrics.group.damageTaken,
        assessments.group.damageTaken,
        false
    )
    y = y - configureSummaryRow(
        timerFrame.groupRows[2],
        y,
        L["Avoidable"],
        metrics.group.avoidableDamageTaken,
        assessments.group.avoidableDamageTaken,
        false
    )
    y = y - configureSummaryRow(
        timerFrame.groupRows[3],
        y,
        L["Interrupts"],
        metrics.group.interrupts,
        assessments.group.interrupts,
        true
    )
    local deathMetric = metrics.group.deaths
    local deathRowHeight = configureSummaryRow(
        timerFrame.groupRows[4],
        y,
        L["Deaths"],
        deathMetric,
        nil,
        true
    )
    timerFrame.groupRows[4].compare:SetText(
        Model.FormatClock(run.deathTimeLost or 0, true)
    )
    timerFrame.groupRows[4].compare:SetTextColor(
        AF.GetColorRGB(
            (run.deathTimeLost or 0) > 0 and "firebrick" or "gray"
        )
    )
    y = y - deathRowHeight - 4

    if config.showPlayerBreakdown ~= false then
        local headerHeight = getLineHeight(-2, 16, 6)
        local playerRowHeight = getLineHeight(-1, 18, 5)
        local header = timerFrame.playerHeader
        AF.ClearPoints(header)
        AF.SetPoint(header, "TOPLEFT", timerFrame, "TOPLEFT", 8, y)
        AF.SetPoint(header, "RIGHT", timerFrame, "RIGHT", -8, 0)
        AF.SetHeight(header, headerHeight - 1)
        layoutFourColumnRow(header)
        header.label:SetText(L["Player"])
        header.value:SetText(L["Avoidable"])
        header.compare:SetText(L["INT"])
        header.extra:SetText(L["Deaths"])
        header.label:SetTextColor(AF.GetColorRGB("gray"))
        header.value:SetTextColor(AF.GetColorRGB("gray"))
        header.compare:SetTextColor(AF.GetColorRGB("gray"))
        header.extra:SetTextColor(AF.GetColorRGB("gray"))
        header:Show()
        y = y - headerHeight

        local shownPlayers = 0
        for index, player in ipairs(metrics.players or {}) do
            local row = timerFrame.playerRows[index]
            if not row then break end
            shownPlayers = index
            local playerAssessments = assessments.players[player.guid] or {}
            local avoidAssessment =
                playerAssessments.avoidableDamageTaken
            local intAssessment = playerAssessments.interrupts
            local avoidMetric = player.metrics.avoidableDamageTaken
            local intMetric = player.metrics.interrupts
            local deathsMetric = player.metrics.deaths

            AF.ClearPoints(row)
            AF.SetPoint(row, "TOPLEFT", timerFrame, "TOPLEFT", 8, y)
            AF.SetPoint(row, "RIGHT", timerFrame, "RIGHT", -8, 0)
            AF.SetHeight(row, playerRowHeight - 1)
            layoutFourColumnRow(row)
            setTruncatedText(
                row.label,
                player.name or _G.UNKNOWN or L["Unknown"],
                row.label:GetWidth()
            )
            row.label:SetTextColor(AF.GetColorRGB(
                player.classFilename or "white"
            ))
            row.value:SetText(
                avoidMetric and avoidMetric.available
                    and formatNumber(avoidMetric.raw) or "—"
            )
            row.value:SetTextColor(AF.GetColorRGB(
                getAssessmentColor(avoidAssessment)
            ))
            local interruptText = intMetric and intMetric.available
                and tostring(floor(intMetric.raw + 0.5)) or "—"
            local deathText = deathsMetric and deathsMetric.available
                and tostring(floor(deathsMetric.raw + 0.5)) or "—"
            row.compare:SetText(interruptText)
            row.compare:SetTextColor(AF.GetColorRGB(
                getAssessmentColor(intAssessment)
            ))
            row.extra:SetText(deathText)
            row.extra:SetTextColor(AF.GetColorRGB("gray"))
            row.tooltip = function(owner)
                addPlayerTooltip(owner, player, playerAssessments)
            end
            row:Show()
            y = y - playerRowHeight
        end
        hideRowsFrom(timerFrame.playerRows, shownPlayers + 1)
        y = y - 3
    else
        timerFrame.playerHeader:Hide()
        hideRowsFrom(timerFrame.playerRows, 1)
    end

    local eligibility
    if run.baselineEligible then
        eligibility = L["Included in seasonal baseline"]
    else
        eligibility = L["Excluded from baseline: %s"]:format(
            baselineReasonLabels[run.baselineReason]
                or L["unknown"]
        )
    end
    timerFrame.footer:SetText(
        eligibility
        .. L["  •  ~%d pulls  •  %s combat"]:format(
            run.pullCount or 0,
            Model.FormatClock(run.combatSeconds or 0)
        )
    )
    timerFrame.footer:SetTextColor(AF.GetColorRGB(
        run.baselineEligible and "softlime" or "gray"
    ))
    anchorText(timerFrame.footer, "TOPLEFT", timerFrame,
        "TOPLEFT", 8, y)
    AF.SetWidth(timerFrame.footer, config.width - 16)
    timerFrame.footer:SetWordWrap(true)
    timerFrame.footer:Show()
    return y - getTextBlockHeight(timerFrame.footer, 28, 6)
end

local function renderRun(run)
    if not timerFrame or not run then return end

    updateDeathData(run)
    local elapsed = run.elapsed or 0
    local timeLimit = run.timeLimit or 0
    local remaining = timeLimit - elapsed
    local plusTwo, plusThree = Model.CalculateBonusThresholds(
        timeLimit,
        run.affixes
    )

    timerFrame.title:SetTextColor(AF.GetColorRGB("BFI"))
    local contentWidth = getContentWidth()
    local titleWidth = contentWidth * 0.62
    setTruncatedText(
        timerFrame.title,
        ("%s  +%d"):format(
            run.mapName or _G.UNKNOWN or L["Unknown"],
            run.level or 0
        ),
        titleWidth
    )
    anchorText(timerFrame.title, "TOPLEFT", timerFrame,
        "TOPLEFT", 8, -7)
    setTruncatedText(
        timerFrame.time,
        Model.FormatClock(elapsed) .. " / "
            .. Model.FormatClock(timeLimit),
        contentWidth * 0.36,
        "right"
    )
    timerFrame.time:SetTextColor(AF.GetColorRGB(
        remaining >= 0 and "white" or "firebrick"
    ))
    anchorText(timerFrame.time, "TOPRIGHT", timerFrame,
        "TOPRIGHT", -8, -7)

    local y = -7 - getLineHeight(2, 22, 8)
    local detailsY = y
    y = renderAffixes(run, y)

    local showThresholds = config.showThresholds ~= false
    if showThresholds then
        timerFrame.thresholds:SetText(L["+3 %s   +2 %s"]:format(
            Model.FormatClock(plusThree - elapsed, true),
            Model.FormatClock(plusTwo - elapsed, true)
        ))
        timerFrame.thresholds:SetTextColor(AF.GetColorRGB("gray"))
        anchorText(timerFrame.thresholds, "TOPRIGHT", timerFrame,
            "TOPRIGHT", -8, detailsY)
        AF.SetWidth(timerFrame.thresholds, contentWidth)
        timerFrame.thresholds:Show()
        y = min(
            y,
            detailsY - getLineHeight(-1, 19, 6)
        )
    end

    AF.ClearPoints(timerFrame.timerBar)
    AF.SetPoint(
        timerFrame.timerBar,
        "TOPLEFT",
        timerFrame,
        "TOPLEFT",
        8,
        y
    )
    timerFrame.timerBar:SetMinMaxValues(0, max(timeLimit, 1))
    timerFrame.timerBar:SetBarValue(
        min(max(elapsed, 0), max(timeLimit, 1))
    )
    setStatusBarColor(
        timerFrame.timerBar,
        elapsed <= plusThree and "softlime"
            or elapsed <= plusTwo and "skyblue"
            or remaining >= 0 and "BFI"
            or "firebrick"
    )
    if showThresholds then
        AF.ClearPoints(timerFrame.plusThreeTick)
        AF.SetPoint(
            timerFrame.plusThreeTick,
            "TOPLEFT",
            timerFrame.timerBar,
            "TOPLEFT",
            contentWidth * (
                timeLimit > 0 and plusThree / timeLimit or 0
            ),
            0
        )
        AF.SetPoint(
            timerFrame.plusThreeTick,
            "BOTTOMLEFT",
            timerFrame.timerBar,
            "BOTTOMLEFT",
            contentWidth * (
                timeLimit > 0 and plusThree / timeLimit or 0
            ),
            0
        )
        AF.ClearPoints(timerFrame.plusTwoTick)
        AF.SetPoint(
            timerFrame.plusTwoTick,
            "TOPLEFT",
            timerFrame.timerBar,
            "TOPLEFT",
            contentWidth * (
                timeLimit > 0 and plusTwo / timeLimit or 0
            ),
            0
        )
        AF.SetPoint(
            timerFrame.plusTwoTick,
            "BOTTOMLEFT",
            timerFrame.timerBar,
            "BOTTOMLEFT",
            contentWidth * (
                timeLimit > 0 and plusTwo / timeLimit or 0
            ),
            0
        )
        timerFrame.plusThreeTick:Show()
        timerFrame.plusTwoTick:Show()
    else
        timerFrame.thresholds:Hide()
        timerFrame.plusThreeTick:Hide()
        timerFrame.plusTwoTick:Hide()
    end
    y = y - 14

    local infoParts = {}
    if config.showPullCount ~= false then
        infoParts[#infoParts + 1] =
            L["Pulls ~%d"]:format(run.pullCount or 0)
    end
    infoParts[#infoParts + 1] = L["Deaths %d (%s)"]:format(
        run.deaths or 0,
        Model.FormatClock(run.deathTimeLost or 0, true)
    )
    setTruncatedText(
        timerFrame.info,
        table.concat(infoParts, "  •  "),
        contentWidth * 0.62
    )
    timerFrame.info:SetTextColor(AF.GetColorRGB("white"))
    anchorText(timerFrame.info, "TOPLEFT", timerFrame,
        "TOPLEFT", 8, y)
    setTruncatedText(
        timerFrame.remaining,
        remaining >= 0
            and L["Remaining %s"]:format(Model.FormatClock(remaining))
            or L["Over %s"]:format(Model.FormatClock(-remaining)),
        contentWidth * 0.36,
        "right"
    )
    timerFrame.remaining:SetTextColor(AF.GetColorRGB(
        remaining >= 0 and "softlime" or "firebrick"
    ))
    anchorText(timerFrame.remaining, "TOPRIGHT", timerFrame,
        "TOPRIGHT", -8, y)
    timerFrame.remaining:Show()
    y = y - getLineHeight(-1, 18, 6)

    local forces = Model.GetForcesObjective(run.objectives)
    if forces then
        local forcesLabelWidth = contentWidth * 0.68
        setTruncatedText(
            timerFrame.forcesLabel,
            forces.name ~= "" and forces.name or L["Enemy Forces"],
            forcesLabelWidth
        )
        timerFrame.forcesLabel:SetTextColor(AF.GetColorRGB("white"))
        anchorText(timerFrame.forcesLabel, "TOPLEFT", timerFrame,
            "TOPLEFT", 8, y)
        timerFrame.forcesValue:SetText(("%.2f%%"):format(
            forces.percent or 0
        ))
        timerFrame.forcesValue:SetTextColor(AF.GetColorRGB("skyblue"))
        anchorText(timerFrame.forcesValue, "TOPRIGHT", timerFrame,
            "TOPRIGHT", -8, y)
        AF.SetWidth(timerFrame.forcesValue, contentWidth * 0.30)
        timerFrame.forcesLabel:Show()
        timerFrame.forcesValue:Show()
        y = y - getLineHeight(-1, 15, 4)
        AF.ClearPoints(timerFrame.forcesBar)
        AF.SetPoint(
            timerFrame.forcesBar,
            "TOPLEFT",
            timerFrame,
            "TOPLEFT",
            8,
            y
        )
        timerFrame.forcesBar:SetBarValue(forces.percent or 0)
        setStatusBarColor(
            timerFrame.forcesBar,
            (forces.percent or 0) >= 100
                and "softlime" or "vividblue"
        )
        timerFrame.forcesBar:Show()
        y = y - 12
    else
        timerFrame.forcesLabel:Hide()
        timerFrame.forcesValue:Hide()
        timerFrame.forcesBar:Hide()
    end

    y = renderObjectives(run, y)
    y = renderExecution(run, y)
    y = renderSummary(run, y)

    AF.SetHeight(timerFrame, max(80, -y + 8))
    timerFrame:Show()
end

RefreshDisplay = function()
    if not timerFrame or not config or not config.enabled then return end
    local run = currentRun or previewRun
    local previewDraggable = previewRun ~= nil and currentRun == nil
    timerFrame:EnableMouse(previewDraggable)
    if previewDraggable then
        timerFrame:RegisterForDrag("LeftButton")
    else
        timerFrame:RegisterForDrag()
    end
    if run then
        renderRun(run)
    else
        timerFrame:Hide()
    end
end

local function makePreviewRun()
    return {
        active = true,
        completed = false,
        mapName = L["Mythic+ Preview"],
        mapID = 399,
        level = 13,
        affixes = {9, 10, 124},
        timeLimit = 1800,
        elapsed = 887,
        pullCount = 14,
        deaths = 2,
        deathTimeLost = 10,
        objectives = {
            {
                key = "criteria:1",
                name = L["First Boss"],
                completed = true,
                elapsed = 315,
                referenceElapsed = 327,
            },
            {
                key = "criteria:2",
                name = L["Second Boss"],
                completed = false,
                referenceElapsed = 1030,
            },
            {
                key = "criteria:3",
                name = L["Enemy Forces"],
                isWeighted = true,
                percent = 63.42,
            },
        },
        liveMeterSnapshot = {
            group = {
                interrupts = {available = true, value = 27},
                avoidableDamageTaken = {
                    available = true,
                    value = 4200000,
                },
            },
        },
    }
end

function MP.SetPreview(shown)
    previewRun = shown and makePreviewRun() or nil
    RefreshDisplay()
end

function MP.GetCurrentRun()
    return currentRun
end

function MP.GetCurrentSeason()
    return currentSeason, currentSeasonKey
end

function MP.ClearHistory()
    ensureHistory()
    local dismissDebrief = currentRun and currentRun.completed
    local pending = characterHistory.pendingFinalization
    if type(pending) == "table" and not pending.finalized then
        pending.finalizationDiscarded = true
        pending.finalizeScheduleToken =
            (tonumber(pending.finalizeScheduleToken) or 0) + 1
        if currentRun == pending then
            currentRun = nil
        end
    end
    characterHistory.pendingFinalization = nil
    characterHistory.seasons = {}
    characterHistory.pendingRuns = {}
    characterHistory.activeSeasonKey = nil
    currentSeason = nil
    currentSeasonKey = nil
    if currentRun and currentRun.active then
        currentRun.referenceHistoryID = nil
        currentRun.referenceLevel = nil
        currentRun.referenceSplits = nil
    end
    discoverSeason()
    if currentRun and currentRun.active then
        updateObjectives(currentRun)
    elseif dismissDebrief then
        dismissCompletedRun()
    else
        restoreTracker()
    end
    RefreshDisplay()
end

local EVENTS = {
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_START",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_UPDATE",
    "WORLD_STATE_TIMER_START",
    "WORLD_STATE_TIMER_STOP",
}

local function registerEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    for _, event in ipairs(EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    if type(_G.C_DamageMeter) == "table" then
        eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
        eventFrame:RegisterEvent("DAMAGE_METER_RESET")
    end
end

local function unregisterEvents()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

local function updateMythicPlus(_, module, which)
    if module and module ~= "uiWidgets" then return end
    if which and which ~= "mythicPlus" then return end

    config = W.config.mythicPlus
    if not config.enabled then
        if timerFrame then
            timerFrame.enabled = false
        end
        unregisterEvents()
        restoreTracker()
        previewRun = nil
        if timerFrame then
            timerFrame:SetScript("OnUpdate", nil)
            timerFrame:Hide()
        end
        return
    end

    ensureHistory()
    if not timerFrame then createTimerFrame() end
    timerFrame.enabled = true
    applyFrameConfig()
    registerEvents()
    requestMapInfo()
    discoverSeason()
    local activeChallenge = isChallengeActive()
    restorePendingFinalization(
        not activeChallenge and config.showDebrief ~= false
    )
    if currentRun and currentRun.completed
        and config.showDebrief == false
    then
        dismissCompletedRun()
    end
    if not activeChallenge then
        if currentRun and currentRun.active then
            archiveInterruptedRun("abandoned")
        elseif not currentRun
            and type(characterHistory.activeRun) == "table"
        then
            currentRun = characterHistory.activeRun
            archiveInterruptedRun("abandoned")
        end
    end
    if not activeChallenge or not restoreRun() then
        RefreshDisplay()
    end

    if currentRun and currentRun.active then
        if config.hideObjectiveTracker == false then
            restoreTracker()
        else
            suppressTracker()
        end
    elseif currentRun and currentRun.completed
        and (
            config.hideObjectiveTracker == false
            or config.showDebrief == false
        )
    then
        restoreTracker()
    elseif currentRun and currentRun.completed
        and config.showDebrief ~= false
        and config.hideObjectiveTracker ~= false
    then
        suppressTracker()
    end
end
AF.RegisterCallback("BFI_UpdateModule", updateMythicPlus)
