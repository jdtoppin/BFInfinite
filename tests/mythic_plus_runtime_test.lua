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

local state = {
    challengeActive = false,
    elapsed = 0,
    inCombat = false,
    bossComplete = false,
    forcesComplete = false,
    queuedTimers = {},
    timerClock = 0,
    meterReads = 0,
    meterFailures = 0,
    deltaDurations = {},
    activeMapID = 399,
    keyLevel = 13,
    deaths = 1,
    deathTimeLost = 5,
    deathDataAvailable = true,
    timerAvailable = true,
    dragPoint = "TOPLEFT",
    dragX = 42,
    dragY = -73,
}

local function newRegion(name)
    local region = {
        name = name,
        shown = true,
        alpha = 1,
        scripts = {},
        events = {},
    }

    function region:SetScript(script, callback)
        self.scripts[script] = callback
    end
    function region:RegisterEvent(event)
        self.events[event] = true
    end
    function region:UnregisterAllEvents()
        self.events = {}
    end
    function region:Show()
        self.showCalls = (self.showCalls or 0) + 1
        self.shown = true
    end
    function region:Hide()
        self.hideCalls = (self.hideCalls or 0) + 1
        self.shown = false
    end
    function region:IsShown()
        return self.shown
    end
    function region:SetAlpha(alpha)
        self.alpha = alpha
    end
    function region:GetAlpha()
        return self.alpha
    end
    function region:SetText(text)
        self.text = text
    end
    function region:SetTextColor(...)
        self.textColor = {...}
    end
    function region:SetTexture(texture)
        self.texture = texture
    end
    function region:SetColorTexture(...)
        self.color = {...}
    end
    function region:SetStatusBarColor(...)
        self.statusBarColor = {...}
    end
    function region:SetMinMaxValues(minimum, maximum)
        self.minimum = minimum
        self.maximum = maximum
    end
    function region:SetValue(value)
        self.value = value
    end
    function region:SetBarValue(value)
        self:SetValue(value)
    end
    function region:SetWidth(width)
        self.width = width
    end
    function region:GetWidth()
        return self.width or 0
    end
    function region:SetHeight(height)
        self.height = height
    end
    function region:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function region:SetPoint(...)
        self.point = {...}
    end
    function region:ClearAllPoints()
        self.point = nil
    end
    function region:SetFrameStrata(strata)
        self.strata = strata
    end
    function region:SetClampedToScreen(value)
        self.clampedToScreen = value
    end
    function region:SetMovable(value)
        self.movable = value
    end
    function region:RegisterForDrag(...)
        self.dragButtons = {...}
    end
    function region:SetMouseClickEnabled(value)
        self.mouseClickEnabled = value
    end
    function region:StartMoving()
        self.moving = true
    end
    function region:StopMovingOrSizing()
        self.moving = false
        self.stopMovingCalls = (self.stopMovingCalls or 0) + 1
    end
    function region:SetUserPlaced(value)
        self.userPlaced = value
    end
    function region:SetJustifyH(justify)
        self.justifyH = justify
    end
    function region:SetJustifyV(justify)
        self.justifyV = justify
    end
    function region:SetWordWrap(wrapped)
        self.wordWrap = wrapped
    end
    function region:GetStringHeight()
        return 12
    end
    function region:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end
    function region:CreateTexture()
        return newRegion()
    end

    return region
end

local callbacks = {}
local fires = {}
local frames = {}
local eventFrame
local timerFrame
local tracker = newRegion("ObjectiveTrackerFrame")
local UIParent = newRegion("UIParent")

local function runNextTimer()
    table.sort(state.queuedTimers, function(left, right)
        return left.due < right.due
    end)
    local timer = table.remove(state.queuedTimers, 1)
    if not timer then return false end
    state.timerClock = math.max(state.timerClock, timer.due)
    timer.callback()
    return true
end

local function runAllTimers()
    local callbacksRun = 0
    while runNextTimer() do
        callbacksRun = callbacksRun + 1
        assertTrue(callbacksRun < 100,
            "timer queue must terminate")
    end
end

local AF = {
    UIParent = UIParent,
    player = {
        fullName = "Tank-Realm",
        specRole = "TANK",
        specID = 73,
    },
}

function AF.RegisterCallback(event, callback)
    callbacks[event] = callback
end
function AF.CreateBorderedFrame(_, name, width, height)
    local frame = newRegion(name)
    frame.width = width
    frame.height = height
    frames[#frames + 1] = frame
    if name == "BFI_MythicPlusTimer" then
        timerFrame = frame
    end
    return frame
end
function AF.CreateBlizzardStatusBar(_, minimum, maximum, width, height)
    local bar = newRegion()
    bar.minimum = minimum
    bar.maximum = maximum
    bar.width = width
    bar.height = height
    return bar
end
function AF.CreateFontString()
    local text = newRegion()
    text.pixelRoundWidth = true
    return text
end
function AF.CreateMover(owner, _, _, save)
    owner.moverSave = save
end
function AF.SetDraggable(frame, target, notUserPlaced, onStart, onStop)
    target = target or frame
    target:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetMouseClickEnabled(true)
    frame:SetScript("OnDragStart", function()
        if onStart then onStart(target) end
        target:StartMoving(true)
        if notUserPlaced then
            target:SetUserPlaced(false)
        end
    end)
    frame:SetScript("OnDragStop", function()
        target:StopMovingOrSizing()
        if onStop then onStop(target) end
    end)
end
function AF.SetFont()
end
function AF.SetWidth(region, width)
    region:SetWidth(region.pixelRoundWidth and math.ceil(width) or width)
end
function AF.SetHeight(region, height)
    region:SetHeight(height)
end
function AF.SetSize(region, width, height)
    region:SetSize(width, height)
end
function AF.ClearPoints(region)
    region:ClearAllPoints()
end
function AF.SetPoint(region, ...)
    region:SetPoint(...)
end
function AF.CreateTexture(parent, _, color)
    local texture = parent:CreateTexture()
    if color then
        texture:SetColorTexture(AF.GetColorRGB(color))
    end
    return texture
end
function AF.CreateIcon(_, texture, size)
    local icon = newRegion()
    icon.icon = newRegion()
    icon:SetSize(size or 16, size or 16)
    function icon:SetIcon(value)
        self.texture = value
        self.icon:SetTexture(value)
    end
    icon:SetIcon(texture)
    return icon
end
function AF.CreateCloseButton()
    local button = newRegion()
    function button:SetTooltip(...)
        self.tooltip = {...}
    end
    return button
end
function AF.ApplyDefaultTexCoord()
end
function AF.HideTooltip()
end
function AF.TruncateFontStringByWidth(text, width, _, _, value)
    text.truncateWidth = width
    if text:GetWidth() > width then
        text:SetText(value:sub(1, 1) .. "...")
    else
        text:SetText(value)
    end
end
function AF.UpdateMoverSave(owner, save)
    owner.moverSave = save
end
function AF.LoadPosition()
end
function AF.CalcPoint()
    return state.dragPoint, state.dragX, state.dragY
end
function AF.Fire(...)
    fires[#fires + 1] = {...}
end
function AF.GetColorRGB()
    return 1, 1, 1, 1
end
function AF.WrapTextInColor(text)
    return text
end
function AF.FormatNumber(value)
    return tostring(math.floor(value + 0.5))
end

local W = {
    config = {
        mythicPlus = {
            enabled = false,
            position = {"TOPRIGHT", -1, -200},
            width = 320,
            font = {"BFI", 12, "none", true},
            hideObjectiveTracker = true,
            showThresholds = true,
            showAffixes = true,
            showObjectives = true,
            showSplits = true,
            showPullCount = true,
            showExecution = true,
            showDebrief = true,
            showPlayerBreakdown = true,
            extendedRunMultiplier = 1.5,
        },
    },
}
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
local BFI = {
    L = L,
    funcs = {
        isValueNonSecret = function()
            return true
        end,
    },
    modules = {
        UIWidgets = W,
    },
}

local roster = {
    {
        order = 1,
        unit = "player",
        guid = "Player-1",
        name = "Tank",
        role = "TANK",
    },
    {
        order = 2,
        unit = "party1",
        guid = "Player-2",
        name = "Mage",
        role = "DAMAGER",
    },
}

local function metric(value)
    return {
        available = true,
        value = value,
        totalAmount = value,
    }
end

local function makeDelta()
    return {
        schemaVersion = 1,
        complete = true,
        coreComplete = true,
        durationSeconds = 600,
        group = {
            damageTaken = metric(1000000),
            avoidableDamageTaken = metric(100000),
            interrupts = metric(20),
            deaths = metric(1),
            damageDone = metric(5000000),
            dps = metric(8000),
        },
        players = {
            {
                order = 1,
                guid = "Player-1",
                name = "Tank",
                role = "TANK",
                specIconID = 132355,
                metrics = {
                    damageTaken = metric(700000),
                    avoidableDamageTaken = metric(40000),
                    interrupts = metric(12),
                    deaths = metric(1),
                    damageDone = metric(2000000),
                    dps = metric(3200),
                },
                topAvoidableSpells = {},
            },
            {
                order = 2,
                guid = "Player-2",
                name = "Mage",
                role = "DAMAGER",
                specIconID = 135846,
                metrics = {
                    damageTaken = metric(300000),
                    avoidableDamageTaken = metric(60000),
                    interrupts = metric(8),
                    deaths = metric(0),
                    damageDone = metric(3000000),
                    dps = metric(4800),
                },
                topAvoidableSpells = {},
            },
        },
    }
end

W.MythicPlusMeter = {
    GetDefaultSessionType = function()
        return 0
    end,
    CaptureRoster = function()
        return roster
    end,
    CollectRunSnapshot = function(_, sessionType)
        state.meterReads = state.meterReads + 1
        if state.meterFailures > 0 then
            state.meterFailures = state.meterFailures - 1
            return nil, "session_unavailable"
        end
        return {
            schemaVersion = 1,
            sessionType = sessionType,
            complete = true,
            coreComplete = true,
            durationSeconds = state.meterReads * 100,
            categories = {},
            group = {},
            players = roster,
        }
    end,
    SubtractSnapshots = function()
        local delta = makeDelta()
        if #state.deltaDurations > 0 then
            delta.durationSeconds =
                table.remove(state.deltaDurations, 1)
        end
        return delta
    end,
}

local challengeMode = {}
function challengeMode.GetMapTable()
    return {399, 400}
end
function challengeMode.GetMapUIInfo(mapID)
    return mapID == 400 and "Second Dungeon" or "Test Dungeon",
        mapID,
        1800,
        mapID == 400 and 12346 or 12345,
        54321,
        2444
end
function challengeMode.GetActiveChallengeMapID()
    return state.challengeActive and state.activeMapID or nil
end
function challengeMode.IsChallengeModeActive()
    return state.challengeActive
end
function challengeMode.GetActiveKeystoneInfo()
    return state.keyLevel, {9, 10, 124}, true
end
function challengeMode.GetPowerLevelDamageHealthMod()
    return 200, 200
end
function challengeMode.GetDeathCount()
    if not state.deathDataAvailable then return nil, nil end
    return state.deaths, state.deathTimeLost
end
function challengeMode.GetAffixInfo(affixID)
    return "Affix " .. affixID, "", 1000 + affixID
end
function challengeMode.GetChallengeCompletionInfo()
    return {
        mapChallengeModeID = state.activeMapID,
        level = state.keyLevel,
        time = 1200000,
        onTime = true,
        keystoneUpgradeLevels = 1,
        practiceRun = false,
        isEligibleForScore = true,
        members = {
            {memberGUID = "Player-1", name = "Tank"},
            {memberGUID = "Player-2", name = "Mage"},
        },
    }
end

local mythicPlus = {}
function mythicPlus.IsMythicPlusActive()
    return true
end
function mythicPlus.GetCurrentSeason()
    return 17
end
function mythicPlus.GetCurrentSeasonValues()
    return 17, 17, 17
end
function mythicPlus.RequestMapInfo()
    state.mapInfoRequested = true
end

local scenarioInfo = {}
function scenarioInfo.GetScenarioStepInfo()
    return {numCriteria = 2}
end
function scenarioInfo.GetCriteriaInfo(index)
    if index == 1 then
        return {
            criteriaID = 1,
            description = "Test Boss",
            completed = state.bossComplete,
            quantity = state.bossComplete and 1 or 0,
            totalQuantity = 1,
            quantityString = state.bossComplete and "1" or "0",
            isWeightedProgress = false,
        }
    end
    return {
        criteriaID = 2,
        description = "Enemy Forces",
        completed = state.forcesComplete,
        quantity = state.forcesComplete and 100 or 50,
        totalQuantity = 100,
        quantityString = state.forcesComplete and "100%" or "50%",
        isWeightedProgress = true,
    }
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    BFIMythicPlusHistory = nil,
    C_ChallengeMode = challengeMode,
    C_DamageMeter = {},
    C_MythicPlus = mythicPlus,
    C_ScenarioInfo = scenarioInfo,
    C_Scenario = nil,
    C_Timer = {
        After = function(delay, callback)
            state.queuedTimers[#state.queuedTimers + 1] = {
                due = state.timerClock + delay,
                callback = callback,
            }
        end,
    },
    CreateFrame = function(frameType, name, parent)
        local frame = newRegion(name)
        frame.frameType = frameType
        frame.parent = parent
        frames[#frames + 1] = frame
        if frameType == "Frame" and name == nil and parent == nil then
            eventFrame = frame
        end
        return frame
    end,
    Enum = {
        WorldElapsedTimerTypes = {
            ChallengeMode = 2,
        },
        DamageMeterSessionType = {
            Overall = 0,
            Current = 1,
        },
    },
    GetBuildInfo = function()
        return "12.1.0", "68914", "", 120100
    end,
    GetInstanceInfo = function()
        return "Test Dungeon", "party"
    end,
    GetServerTime = function()
        return 100000 + math.floor(state.timerClock)
    end,
    GetTimePreciseSec = function()
        return 1000 + state.elapsed
    end,
    GetWorldElapsedTimers = function()
        if not state.timerAvailable then return end
        return 42
    end,
    GetWorldElapsedTime = function(timerID)
        if not state.timerAvailable or timerID ~= 42 then return end
        return "Challenge", state.elapsed, 2
    end,
    InCombatLockdown = function()
        return state.inCombat
    end,
    ObjectiveTrackerFrame = tracker,
    UnitFullName = function()
        return "Tank", "Realm"
    end,
    UnitGUID = function()
        return "Player-1"
    end,
    UNKNOWN = "Unknown",
    hooksecurefunc = function()
    end,
    io = io,
    ipairs = ipairs,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    setmetatable = setmetatable,
    string = string,
    table = table,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
}
environment._G = environment

local function loadModule(path)
    local chunk, loadError = loadfile(path)
    assertEqual(type(chunk), "function", loadError or path)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
end

loadModule("Modules/UIWidgets/MythicPlusHistory.lua")
loadModule("Modules/UIWidgets/MythicPlusModel.lua")
loadModule("Modules/UIWidgets/MythicPlusAnalysis.lua")
loadModule("Modules/UIWidgets/MythicPlus.lua")

local MP = W.MythicPlus
assertTrue(MP, "runtime is exported")
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(timerFrame, nil, "disabled module remains dormant")
assertEqual(state.meterReads, 0, "disabled module does not read meter data")
assertEqual(tracker.shown, true,
    "disabled module does not take ownership of tracker state")

local timerID, elapsed = MP.GetChallengeTimer()
assertEqual(timerID, 42, "challenge timer is discovered")
assertEqual(elapsed, 0, "challenge timer elapsed")

W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertTrue(timerFrame, "enabled module creates its timer frame")
assertTrue(eventFrame.events.CHALLENGE_MODE_START, "runtime events register")
assertTrue(
    eventFrame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED,
    "Overall meter update event registers"
)
assertEqual(type(timerFrame.moverSave), "function",
    "standard AF mover keeps synchronized position saving")
timerFrame.moverSave("TOPRIGHT", -5, -205)
assertEqual(W.config.mythicPlus.position[2], -5,
    "standard AF mover saves its X coordinate")
assertEqual(W.config.mythicPlus.position[3], -205,
    "standard AF mover saves its Y coordinate")

MP.SetPreview(true)
assertEqual(timerFrame.width, 320,
    "preview opens at the readable default width")
assertEqual(timerFrame.title.text, "Mythic+ Preview  +13",
    "preview title remains available in full")
assertEqual(timerFrame.title.truncateWidth, timerFrame.title.width,
    "preview truncation uses the pixel-snapped title width")
assertEqual(timerFrame.info.truncateWidth, timerFrame.info.width,
    "preview truncation uses the pixel-snapped stats width")
assertEqual(timerFrame.mouseEnabled, true,
    "preview enables direct window dragging")
assertEqual(timerFrame.dragButtons[1], "LeftButton",
    "preview uses the standard left drag button")
timerFrame.scripts.OnDragStart(timerFrame)
assertEqual(timerFrame.moving, true, "preview drag begins")
timerFrame.scripts.OnDragStop(timerFrame)
assertEqual(timerFrame.moving, false, "preview drag stops")
assertEqual(W.config.mythicPlus.position[1], "TOPLEFT",
    "preview drag saves its anchor")
assertEqual(W.config.mythicPlus.position[2], 42,
    "preview drag saves its X coordinate")
assertEqual(W.config.mythicPlus.position[3], -73,
    "preview drag saves its Y coordinate")
assertEqual(fires[#fires][1], "BFI_RefreshOptions",
    "preview drag refreshes the visible position options")
MP.SetPreview(false)
assertEqual(timerFrame.mouseEnabled, false,
    "closing the preview disables direct dragging")
assertEqual(timerFrame.dragButtons[1], nil,
    "closing the preview unregisters direct drag input")

state.challengeActive = true
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local run = MP.GetCurrentRun()
assertTrue(run and run.active, "challenge start creates an active run")
assertEqual(run.mapID, 399, "active map captured")
assertEqual(run.partialObservation, nil, "on-time start is complete")
assertEqual(tracker.shown, false, "Blizzard tracker is hidden for the key")
assertEqual(timerFrame.shown, true, "custom timer is visible")
assertEqual(timerFrame.mouseEnabled, false,
    "live timer does not capture drag input")
assertEqual(timerFrame.enabled, true,
    "enabled timer participates in AF mover visibility")
assertEqual(timerFrame.affixIcons[1].texture, 1009,
    "affixes render through AF icon widgets")
assertEqual(timerFrame.affixIcons[1].tooltipLines[1], "Affix 9",
    "affix icon carries an AF tooltip")
assertEqual(timerFrame.affixIcons[1].point[4], 8,
    "first affix follows the standard frame inset")
assertEqual(timerFrame.plusThreeTick.shown, true,
    "threshold option shows the +3 bar marker")
assertEqual(timerFrame.plusTwoTick.shown, true,
    "threshold option shows the +2 bar marker")

local affixHideCalls = timerFrame.affixIcons[1].hideCalls or 0
local objectiveHideCalls =
    timerFrame.objectiveRows[1].hideCalls or 0
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
assertEqual(timerFrame.affixIcons[1].hideCalls or 0, affixHideCalls,
    "clock refresh does not churn a visible affix tooltip owner")
assertEqual(timerFrame.objectiveRows[1].hideCalls or 0,
    objectiveHideCalls,
    "clock refresh does not churn a visible split tooltip owner")

W.config.mythicPlus.width = 260
W.config.mythicPlus.font[2] = 24
W.config.mythicPlus.showThresholds = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(timerFrame.timerBar.width, 244,
    "AF bar width follows the inset content width")
assertEqual(timerFrame.title.width, math.ceil(244 * 0.62),
    "title column uses responsive content width")
assertTrue(timerFrame.objectiveRows[1].height > 15,
    "row height follows the configured AF font size")
assertEqual(timerFrame.thresholds.shown, false,
    "threshold option hides its text")
assertEqual(timerFrame.plusThreeTick.shown, false,
    "threshold option hides the +3 marker")
assertEqual(timerFrame.plusTwoTick.shown, false,
    "threshold option hides the +2 marker")

W.config.mythicPlus.width = 320
W.config.mythicPlus.font[2] = 12
W.config.mythicPlus.showThresholds = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")

state.inCombat = true
state.elapsed = 10
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_DISABLED")
assertEqual(run.pullCount, 1, "combat transition increments pull count")

state.inCombat = false
state.elapsed = 70
state.deaths = 2
state.deathTimeLost = 20
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
runAllTimers()
assertEqual(run.combatSeconds, 45,
    "combat duration excludes newly accumulated death penalties")
assertTrue(run.liveMeterSnapshot, "execution snapshot is available after combat")

state.bossComplete = true
eventFrame.scripts.OnEvent(eventFrame, "SCENARIO_CRITERIA_UPDATE")
assertEqual(run.splits[1].elapsed, 70, "boss completion creates a split")
assertEqual(run.splits[1].combatElapsed, 45,
    "split combat context excludes death penalties")

state.forcesComplete = true
state.elapsed = 1200
state.meterFailures = 1
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assertEqual(run.completed, true, "completion marks the run complete")
assertEqual(run.finalized, nil, "meter finalization is deferred")
assertEqual(
    environment.BFIMythicPlusHistory.characters["Tank-Realm"]
        .pendingFinalization,
    run,
    "completed run persists before deferred finalization"
)
assertEqual(tracker.shown, false,
    "tracker stays hidden while the debrief occupies its position")

runAllTimers()
assertEqual(run.finalized, true, "deferred finalization completes")
assertEqual(state.meterFailures, 0,
    "transient final meter failure is retried")
assertEqual(
    environment.BFIMythicPlusHistory.characters["Tank-Realm"]
        .pendingFinalization,
    nil,
    "pending finalization clears only after storage"
)
assertEqual(timerFrame.closeButton.shown, true,
    "completed debrief exposes the AF dismiss control")
timerFrame.closeButton.scripts.OnClick()
assertEqual(tracker.shown, true,
    "dismissing the debrief restores the Blizzard tracker")
assertEqual(MP.GetCurrentRun(), nil,
    "dismissing the debrief releases the completed display")
local season = MP.GetCurrentSeason()
assertEqual(#season.maps[399].runs, 1, "completed run enters history")
assertEqual(season.maps[399].runs[1].pullSnapshots, nil,
    "history excludes transient pull snapshots")

state.deaths = 0
state.deathTimeLost = 0
state.elapsed = 0
state.bossComplete = false
state.forcesComplete = false
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local staleRun = MP.GetCurrentRun()
state.elapsed = 1200
state.deltaDurations = {0, 600}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
runNextTimer()
assertEqual(staleRun.finalized, nil,
    "zero-duration final snapshot is not committed")
eventFrame.scripts.OnEvent(
    eventFrame,
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    0,
    0
)
runAllTimers()
assertEqual(staleRun.finalized, true,
    "settled Overall update finalizes the retry")
assertEqual(#season.maps[399].runs, 2,
    "meter events and timers still store the run once")

state.elapsed = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local resetPendingRun = MP.GetCurrentRun()
state.elapsed = 1200
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
eventFrame.scripts.OnEvent(eventFrame, "DAMAGE_METER_RESET")
runAllTimers()
assertEqual(resetPendingRun.finalized, true,
    "post-completion meter reset terminates finalization")
assertEqual(resetPendingRun.meterReset, true,
    "post-completion reset is recorded")
assertEqual(resetPendingRun.baselineReason, "meter_reset",
    "reset pending run is excluded with the exact reason")

state.elapsed = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local unavailableRun = MP.GetCurrentRun()
state.elapsed = 1200
state.meterFailures = 10
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
unavailableRun.finalizeCandidate = "malformed persisted value"
for _ = 1, 39 do
    state.timerClock = state.timerClock + 0.1
    eventFrame.scripts.OnEvent(
        eventFrame,
        "DAMAGE_METER_COMBAT_SESSION_UPDATED",
        0,
        0
    )
end
runAllTimers()
assertEqual(unavailableRun.finalized, true,
    "retry deadline finalizes an unavailable meter run")
assertEqual(unavailableRun.baselineReason, "incomplete_meter",
    "deadline run is stored but excluded")
assertEqual(state.meterFailures, 10,
    "hard deadline cannot be postponed by an Overall update storm")
state.meterFailures = 0

state.elapsed = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
state.elapsed = 1200
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
MP.ClearHistory()
runAllTimers()
season = MP.GetCurrentSeason()
assertEqual(
    season.maps[399].runs,
    nil,
    "clearing history cancels pending finalization without repopulating it"
)

local historyStore = environment.BFIMythicPlusHistory
local historyCharacter = historyStore.characters["Tank-Realm"]
local archivedSeason, archivedSeasonKey =
    W.MythicPlusHistory.GetOrCreateSeason(
        historyStore,
        "Tank-Realm",
        16,
        "v1:399",
        {observedAt = 90000}
    )
archivedSeason.maps[399] = {}
historyCharacter.pendingRuns = {
    {
        mapID = 399,
        seasonID = 16,
        seasonKey = archivedSeasonKey,
        completed = true,
        damageMeterComplete = true,
        elapsed = 1000,
        timeLimit = 1800,
    },
    {
        mapID = 399,
        completed = true,
        damageMeterComplete = true,
        elapsed = 1000,
        timeLimit = 1800,
    },
}
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_MAPS_UPDATE")
season = MP.GetCurrentSeason()
assertEqual(#archivedSeason.maps[399].runs, 1,
    "pending rollover run returns to its archived season")
assertEqual(#season.maps[399].runs, 1,
    "pending run with a transient season ID joins the active season")
assertEqual(#historyCharacter.pendingRuns, 0,
    "routable pending runs do not remain stranded")
MP.ClearHistory()
season = MP.GetCurrentSeason()
assertEqual(season.maps[399].runs, nil,
    "season-routing regression setup is cleared")

W.config.mythicPlus.showDebrief = false
state.elapsed = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
assertEqual(tracker.shown, false,
    "active key still suppresses the tracker when debrief is disabled")
state.elapsed = 1200
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
assertEqual(MP.GetCurrentRun(), nil,
    "disabled debrief releases the completed display immediately")
assertEqual(timerFrame.shown, false,
    "disabled debrief hides the timer after completion")
assertEqual(tracker.shown, true,
    "disabled debrief restores the tracker after completion")
runAllTimers()
season = MP.GetCurrentSeason()
assertEqual(#season.maps[399].runs, 1,
    "disabled debrief does not prevent deferred run storage")
W.config.mythicPlus.showDebrief = true

state.elapsed = 0
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
assertTrue(MP.GetCurrentRun().active, "a second run can start")
state.inCombat = true
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(tracker.alpha, 0, "combat-safe restoration is deferred")
assertTrue(eventFrame.events.PLAYER_REGEN_ENABLED,
    "disable keeps the one event needed for restoration")

state.inCombat = false
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
assertEqual(tracker.alpha, 1, "tracker alpha restores after combat")
assertEqual(tracker.shown, true, "tracker visibility restores after combat")
assertEqual(next(eventFrame.events), nil,
    "disabled module unregisters after deferred restoration")

state.challengeActive = false
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(MP.GetCurrentRun(), nil,
    "re-enabling after the key ended does not revive a stale active timer")
assertEqual(timerFrame.shown, false,
    "stale disabled-key state remains hidden after re-enable")
assertEqual(tracker.shown, true,
    "stale disabled-key cleanup leaves the tracker restored")
season = MP.GetCurrentSeason()
local archivedRun =
    season.maps[399].runs[#season.maps[399].runs]
assertEqual(archivedRun.abandoned, true,
    "a key that ended while disabled is retained as an abandoned run")
assertEqual(archivedRun.baselineEligible, false,
    "a disabled-key abandonment cannot enter the baseline")

MP.ClearHistory()
state.bossComplete = false
state.forcesComplete = false
state.activeMapID = 399
state.keyLevel = 13
state.deaths = 0
state.deathTimeLost = 0
state.elapsed = 0
state.timerClock = state.timerClock + 100
state.challengeActive = true
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local resumableRun = MP.GetCurrentRun()
state.deaths = 2
state.deathTimeLost = 20
state.elapsed = 140
state.timerClock = state.timerClock + 120
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(MP.GetCurrentRun(), resumableRun,
    "same active key restores when its start identity matches")

state.elapsed = 620
state.timerClock = state.timerClock + 480
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
state.timerClock = state.timerClock + 180
state.deaths = 0
state.deathTimeLost = 0
state.elapsed = 120
state.keyLevel = 14
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
local sameMapReplacement = MP.GetCurrentRun()
assertTrue(sameMapReplacement ~= resumableRun,
    "a later same-dungeon key cannot reuse the saved run")
assertEqual(resumableRun.abandoned, true,
    "stale same-dungeon run is archived")
assertEqual(resumableRun.historyStored, true,
    "stale same-dungeon run is retained in history")
assertEqual(sameMapReplacement.level, 14,
    "replacement run captures the live key level")
assertEqual(sameMapReplacement.partialObservation, true,
    "replacement run is marked as a partial observation")

state.elapsed = 150
state.timerClock = state.timerClock + 30
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(MP.GetCurrentRun(), sameMapReplacement,
    "a partially observed run retains a stable start identity")

eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_RESET")
state.activeMapID = 399
state.keyLevel = 13
state.deaths = 0
state.deathTimeLost = 0
state.elapsed = 0
state.timerClock = state.timerClock + 100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local differentMapOldRun = MP.GetCurrentRun()
state.elapsed = 300
state.timerClock = state.timerClock + 300
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
state.timerClock = state.timerClock + 135
state.activeMapID = 400
state.keyLevel = 12
state.elapsed = 90
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
local differentMapReplacement = MP.GetCurrentRun()
assertEqual(differentMapOldRun.abandoned, true,
    "stale different-dungeon run is archived")
assertEqual(differentMapOldRun.historyStored, true,
    "stale different-dungeon run is retained in history")
assertEqual(differentMapReplacement.mapID, 400,
    "different live dungeon starts a replacement run")
assertEqual(differentMapReplacement.partialObservation, true,
    "different-dungeon replacement is partial")

eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_RESET")
state.activeMapID = 399
state.keyLevel = 13
state.deaths = 0
state.deathTimeLost = 0
state.elapsed = 0
state.timerClock = state.timerClock + 100
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_START", 399)
local timerUnavailableOldRun = MP.GetCurrentRun()
state.elapsed = 100
state.timerClock = state.timerClock + 100
timerFrame.scripts.OnUpdate(timerFrame, 0.11)
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
state.timerClock = state.timerClock + 100
state.elapsed = 50
state.timerAvailable = false
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(MP.GetCurrentRun(), nil,
    "restore waits briefly for an unavailable world timer")
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(timerUnavailableOldRun.active, true,
    "duplicate refreshes do not bypass the pending identity retry")
runAllTimers()
local unverifiedReplacement = MP.GetCurrentRun()
assertEqual(timerUnavailableOldRun.abandoned, true,
    "unprovable saved run is archived after bounded retries")
assertEqual(unverifiedReplacement.partialObservation, true,
    "timerless replacement remains a partial observation")
assertEqual(unverifiedReplacement.identityUnverified, true,
    "timerless replacement keeps identity explicitly unverified")
state.timerAvailable = true
state.deathDataAvailable = false
eventFrame.scripts.OnEvent(eventFrame, "WORLD_STATE_TIMER_START", 42)
assertEqual(unverifiedReplacement.identityUnverified, true,
    "missing death-time data cannot establish a false timer origin")
local unverifiedStartedAt = unverifiedReplacement.startedAt
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
state.deathDataAvailable = true
state.deaths = 2
state.deathTimeLost = 20
state.timerClock = state.timerClock + 80
state.elapsed = state.elapsed + 80
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
assertEqual(MP.GetCurrentRun(), unverifiedReplacement,
    "reload retains a saved run whose identity was knowingly unverified")
assertEqual(unverifiedReplacement.identityUnverified, nil,
    "safe restore establishes the replacement run identity")
assertNear(
    unverifiedReplacement.startedAt,
    environment.GetServerTime() - state.elapsed + state.deathTimeLost,
    0.001,
    "safe restore corrects the run origin with accumulated death time"
)
assertTrue(
    math.abs(unverifiedReplacement.startedAt - unverifiedStartedAt) > 10,
    ("known placeholder identity is replaced rather than mismatch-archived "
        .. "(old %.3f, new %.3f)"):format(
        unverifiedStartedAt,
        unverifiedReplacement.startedAt
    )
)

unverifiedReplacement.identityUnverified = true
unverifiedReplacement.elapsed = 600
W.config.mythicPlus.enabled = false
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
state.timerClock = state.timerClock + 120
state.elapsed = 30
state.deaths = 0
state.deathTimeLost = 0
W.config.mythicPlus.enabled = true
callbacks.BFI_UpdateModule(nil, "uiWidgets", "mythicPlus")
local rollbackReplacement = MP.GetCurrentRun()
assertTrue(rollbackReplacement ~= unverifiedReplacement,
    "elapsed rollback rejects an unverified stale same-dungeon run")
assertEqual(unverifiedReplacement.abandoned, true,
    "elapsed rollback archives the stale unverified run")
assertEqual(rollbackReplacement.partialObservation, true,
    "elapsed rollback starts a partial replacement observation")

local sourceFile = assert(io.open(
    "Modules/UIWidgets/MythicPlus.lua",
    "r"
))
local sourceText = sourceFile:read("*a")
sourceFile:close()
assertTrue(
    sourceText:find(
        "partialObservation = forcePartial or elapsed > 5 or nil",
        1,
        true
    ),
    "mid-key attachment is explicitly marked partial"
)
assertTrue(
    not sourceText:find("p" .. "call", 1, true),
    "runtime does not probe secrets through protected calls"
)

print("mythic_plus_runtime_test.lua: ok")
