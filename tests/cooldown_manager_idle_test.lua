local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message, 2)
    end
end

local function assertContains(source, text, message)
    if not source:find(text, 1, true) then
        error(message .. ": missing " .. text, 2)
    end
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    assertEqual(type(file), "userdata", openError or ("open " .. path))
    local contents = file:read("*a")
    file:close()
    return contents
end

local function extract(source, firstMarker, lastMarker)
    local first = source:find(firstMarker, 1, true)
    assertEqual(type(first), "number", "source start marker")
    local last = source:find(lastMarker, first, true)
    assertEqual(type(last), "number", "source end marker")
    return source:sub(first, last - 1)
end

local function loadHarness(source, name)
    local chunk, loadError = loadstring(source, "@" .. name)
    assertEqual(type(chunk), "function", loadError or (name .. " load"))
    return chunk()
end

local moduleSource = readFile("Modules/CooldownManager/CooldownManager.lua")

---------------------------------------------------------------------
-- Coalesced presentation controller, combat latch, and disabled gate
---------------------------------------------------------------------

local controllerSource = extract(
    moduleSource,
    "function presentationController:ReleaseCombatBlock",
    "local function UpdateCooldownManager"
)

local controller = loadHarness([[
local state = {
    assistedCalls = 0,
    buffUpdates = 0,
    initializeCalls = 0,
    reconcileCalls = 0,
    restoreCalls = 0,
}
local presentationController = {
    scripts = {},
    buffVisibility = {},
}
function presentationController:SetScript(script, callback)
    self.scripts[script] = callback
end
function presentationController.buffVisibility:Update()
    state.buffUpdates = state.buffUpdates + 1
end

local HighlightState = {}
local CM = {
    config = {
        enabled = true,
        viewers = {essential = {}},
    },
}
local viewerStates = {{key = "essential"}}
local QueuePresentationUpdate

local function InitializeViewers()
    state.initializeCalls = state.initializeCalls + 1
end

local function RefreshAssistedHighlightState()
    state.assistedCalls = state.assistedCalls + 1
end

local function NextResult(key)
    local remaining = state[key] or 0
    if remaining > 0 then
        state[key] = remaining - 1
        return false
    end
    return true
end

local function ReconcileViewer()
    state.reconcileCalls = state.reconcileCalls + 1
    if state.redirtyDuringReconcile then
        state.redirtyDuringReconcile = nil
        QueuePresentationUpdate()
    end
    return NextResult("reconcileFailures")
end

local function RestoreViewer()
    state.restoreCalls = state.restoreCalls + 1
    return NextResult("restoreFailures")
end

local function InCombatLockdown()
    return state.inCombat or false
end

local function IsValueNonSecret()
    return true
end
]] .. controllerSource .. [[

local function Run(elapsed)
    local update = presentationController.scripts.OnUpdate
    if update then
        update(presentationController, elapsed or 0)
    end
end

return {
    controller = presentationController,
    highlight = HighlightState,
    module = CM,
    queue = QueuePresentationUpdate,
    run = Run,
    state = state,
}
]], "cooldown_manager_idle_controller")

assertEqual(controller.controller.scripts.OnUpdate, nil, "idle starts dormant")
controller.queue()
assertEqual(type(controller.controller.scripts.OnUpdate), "function", "dirty wake")
controller.run()
assertEqual(controller.state.initializeCalls, 1, "one initialization per pass")
assertEqual(controller.state.reconcileCalls, 1, "dirty reconcile")
assertEqual(controller.controller.scripts.OnUpdate, nil, "successful pass sleeps")

controller.queue()
controller.queue()
controller.run()
assertEqual(controller.state.reconcileCalls, 2, "duplicate dirt coalesced")

controller.state.redirtyDuringReconcile = true
controller.queue()
controller.run()
assertEqual(type(controller.controller.scripts.OnUpdate), "function",
    "work dirtied during a pass stays awake")
controller.run()
assertEqual(controller.state.reconcileCalls, 4, "re-dirtied work reconciled")
assertEqual(controller.controller.scripts.OnUpdate, nil, "re-dirtied work sleeps")

controller.state.reconcileFailures = 2
controller.queue()
controller.run()
controller.run(0.15)
assertEqual(type(controller.controller.scripts.OnUpdate), "function",
    "incomplete out-of-combat work retries")
controller.run(0.15)
assertEqual(controller.controller.scripts.OnUpdate, nil, "successful retry sleeps")

controller.state.reconcileFailures = 100
controller.queue()
for _ = 1, 7 do
    controller.run(0.15)
end
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "persistent out-of-combat failure has a finite retry window")
local callsAfterRetryWindow = controller.state.reconcileCalls
controller.run(1)
assertEqual(controller.state.reconcileCalls, callsAfterRetryWindow,
    "timed-out controller remains dormant until another lifecycle edge")

controller.state.inCombat = true
controller.state.reconcileFailures = 100
controller.queue()
controller.run()
assertEqual(controller.controller.combatBlocked, true, "combat failure latches")
assertEqual(controller.controller.dirty, true, "combat dirt remains pending")
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "combat-denied work sleeps without polling")
local combatCalls = controller.state.reconcileCalls
controller.queue()
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "ordinary dirt cannot bypass combat latch")
controller.run(1)
assertEqual(controller.state.reconcileCalls, combatCalls,
    "latched controller remains dormant")
assertEqual(controller.controller:ReleaseCombatBlock(), false,
    "unsafe release keeps latch")

controller.state.inCombat = false
controller.state.reconcileFailures = 0
assertEqual(controller.controller:ReleaseCombatBlock(), true,
    "safe restriction edge releases latch")
assertEqual(type(controller.controller.scripts.OnUpdate), "function",
    "released pending work wakes")
controller.run()
assertEqual(controller.state.reconcileCalls, combatCalls + 1,
    "released work reconciles once")
assertEqual(controller.controller.combatBlocked, nil, "successful release clears latch")

controller.module.config.enabled = false
controller.queue()
controller.run()
assertEqual(controller.state.restoreCalls, 1, "disabled module restores viewer")
assertEqual(controller.state.assistedCalls, 1,
    "disabled pass clears assisted runtime state")
assertEqual(controller.controller.disabledRestored, true,
    "successful disabled cleanup closes gate")
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "completed disable restore sleeps")
controller.queue()
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "native dirt is ignored after disabled cleanup")
assertEqual(controller.state.restoreCalls, 1,
    "disabled gate prevents duplicate restoration")

controller.module.config.enabled = true
controller.queue()
assertEqual(controller.controller.disabledRestored, nil,
    "re-enable bypasses disabled gate")
controller.run()
assertEqual(controller.state.reconcileCalls, combatCalls + 2,
    "re-enabled module reconciles")

---------------------------------------------------------------------
-- Assisted fallback: scoped 5 Hz lifecycle and change-only work
---------------------------------------------------------------------

local assistedSource = extract(
    moduleSource,
    "local function SetAssistedHighlightSpell",
    "HighlightState.controller:RegisterEvent"
)

local assisted = loadHarness([[
local state = {
    cvarEnabled = true,
    nextSpell = 101,
    queryCalls = 0,
    queueAttempts = 0,
    queueCalls = 0,
    refreshCalls = 0,
    tickerCreations = 0,
}
local presentationController = {}
local HighlightState = {baseSpellIDs = {}}
local CM = {
    config = {
        enabled = true,
        assistedHighlight = true,
    },
}
local hotkeyGeneration = 0

local C_AssistedCombat = {}
function C_AssistedCombat.GetNextCastSpell(includeQueued)
    if includeQueued ~= false then
        error("fallback must use GetNextCastSpell(false)")
    end
    state.queryCalls = state.queryCalls + 1
    return state.nextSpell
end
local C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function() end,
}
local C_Timer = {}
function C_Timer.NewTicker(interval, callback)
    state.tickerCreations = state.tickerCreations + 1
    local ticker = {
        callback = callback,
        interval = interval,
    }
    function ticker:Cancel()
        self.cancelled = true
        state.cancelCalls = (state.cancelCalls or 0) + 1
    end
    state.lastTicker = ticker
    return ticker
end

local function GetCVarBool()
    return state.cvarEnabled
end
local function GetCVar()
    return "0.2"
end
local function IsValueNonSecret()
    return true
end
local function IsSafeBoolean(value)
    return type(value) == "boolean"
end
local function ClampNumber(value, fallback, lower, upper)
    value = type(value) == "number" and value or fallback
    return math.max(lower, math.min(value, upper))
end
local function GetNonSecretSpellID(spellID)
    return type(spellID) == "number" and spellID or nil
end
local function GetBaseSpellID(spellID)
    return spellID and spellID + 1000 or nil
end
local function RefreshAssistedHighlights()
    state.refreshCalls = state.refreshCalls + 1
end
local function QueuePresentationUpdate()
    state.queueAttempts = state.queueAttempts + 1
    if not presentationController.combatBlocked then
        state.queueCalls = state.queueCalls + 1
    end
end
local function wipe(tableValue)
    for key in next, tableValue do
        tableValue[key] = nil
    end
end
]] .. assistedSource .. [[

return {
    controller = presentationController,
    event = OnAssistedHighlightEvent,
    highlight = HighlightState,
    module = CM,
    state = state,
    updateFallback = HighlightState.UpdateAssistedHighlightFallback,
}
]], "cooldown_manager_assisted_fallback")

assisted.updateFallback()
assertEqual(assisted.state.lastTicker.interval, 0.2, "assisted fallback cadence")
assertEqual(assisted.state.queryCalls, 1, "fallback lifecycle samples immediately")
assertEqual(assisted.state.refreshCalls, 1, "initial recommendation refreshes")
assertEqual(assisted.state.queueCalls, 1, "initial recommendation queues hotkey work")

local assistedTicker = assisted.state.lastTicker
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 1,
    "unchanged fallback does no highlight work")
assertEqual(assisted.state.queueCalls, 1,
    "unchanged fallback does no presentation work")

assisted.state.nextSpell = 202
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 2,
    "changed fallback refreshes immediately")
assertEqual(assisted.state.queueCalls, 2,
    "changed fallback queues presentation once")

assisted.controller.combatBlocked = true
assisted.state.nextSpell = 303
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 3,
    "combat latch does not block runtime highlight refresh")
assertEqual(assisted.state.queueCalls, 2,
    "combat latch still defers broad presentation")
local queueAttempts = assisted.state.queueAttempts
assisted.event(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
assertEqual(assisted.state.refreshCalls, 4,
    "glow event refreshes runtime highlight behind latch")
assertEqual(assisted.state.queueAttempts, queueAttempts,
    "unchanged glow event does not queue broad work")

assisted.controller.combatBlocked = nil
assisted.module.config.assistedHighlight = false
assisted.updateFallback()
assertEqual(assistedTicker.cancelled, true, "feature disable cancels fallback")
assertEqual(assisted.highlight.fallbackTicker, nil, "cancelled fallback is released")
assertEqual(assisted.highlight.spellID, nil, "feature disable clears recommendation")
assertEqual(assisted.state.refreshCalls, 5,
    "feature disable clears highlight immediately")

assisted.module.config.assistedHighlight = true
assisted.updateFallback()
local moduleTicker = assisted.state.lastTicker
assisted.module.config.enabled = false
assisted.updateFallback()
assertEqual(moduleTicker.cancelled, true, "module disable cancels fallback")
assertEqual(assisted.highlight.spellID, nil, "module disable clears recommendation")
local disabledQueries = assisted.state.queryCalls
local disabledRefreshes = assisted.state.refreshCalls
assisted.controller.disabledRestored = true
assisted.highlight.RefreshAssistedHighlightRecommendation()
assertEqual(assisted.state.queryCalls, disabledQueries,
    "disabled gate ignores native recommendation callbacks")
assertEqual(assisted.state.refreshCalls, disabledRefreshes,
    "disabled gate ignores runtime refresh callbacks")

---------------------------------------------------------------------
-- Active-only native buff visibility monitor
---------------------------------------------------------------------

local visibilitySource = extract(
    moduleSource,
    "presentationController.buffVisibility.weakKeys",
    "function presentationController:ReleaseCombatBlock"
)

local visibility = loadHarness([[
local state = {
    queueCalls = 0,
    tickerCreations = 0,
}
local presentationController = {buffVisibility = {}}
local item = {shown = true}
state.items = {item}
local viewer = {hideWhenInactive = true}
local viewerState = {
    definition = {isBuff = true},
    key = "buffIcon",
    viewer = viewer,
}
local viewerStates = {viewerState}
local CM = {
    config = {
        enabled = true,
        viewers = {
            buffIcon = {visibility = "always"},
        },
    },
}

local function wipe(tableValue)
    for key in next, tableValue do
        tableValue[key] = nil
    end
end
local function IsSafeBoolean(value)
    return type(value) == "boolean"
end
local function FrameIsShown(frame)
    return frame.shown
end
local function GetActiveItems(_, reusableItems)
    if state.poolInvalid then return nil end
    wipe(reusableItems)
    for index, activeItem in ipairs(state.items) do
        reusableItems[index] = activeItem
    end
    return reusableItems
end
local function QueuePresentationUpdate()
    state.queueCalls = state.queueCalls + 1
end
local C_Timer = {}
function C_Timer.NewTicker(interval, callback)
    state.tickerCreations = state.tickerCreations + 1
    local ticker = {
        callback = callback,
        interval = interval,
    }
    function ticker:Cancel()
        self.cancelled = true
        state.cancelCalls = (state.cancelCalls or 0) + 1
    end
    state.lastTicker = ticker
    return ticker
end
]] .. visibilitySource .. [[

return {
    item = item,
    module = CM,
    monitor = presentationController.buffVisibility,
    state = state,
    viewer = viewer,
    viewerState = viewerState,
}
]], "cooldown_manager_buff_visibility")

visibility.monitor:Update()
assertEqual(visibility.monitor.ticker.interval, 0.25, "buff monitor cadence")
assertEqual(visibility.state.queueCalls, 0, "initial sample is a baseline")
assertEqual(getmetatable(visibility.viewerState.buffVisibilitySnapshots[1]).__mode,
    "k", "buff snapshot uses weak keys")
local snapshotBuffers = visibility.viewerState.buffVisibilitySnapshots
local reusableItems = visibility.viewerState.buffVisibilityItems
local visibilityTicker = visibility.monitor.ticker
visibilityTicker.callback()
assertEqual(visibility.state.queueCalls, 0, "unchanged buff sample does no work")

visibility.item.shown = false
visibilityTicker.callback()
assertEqual(visibility.state.queueCalls, 1,
    "eventless native visibility edge queues reconciliation")
assertEqual(visibility.monitor.ticker, nil,
    "buff monitor sleeps when no dynamic buff remains active")

visibility.item.shown = true
visibility.monitor:Update()
assertEqual(visibility.viewerState.buffVisibilitySnapshots, snapshotBuffers,
    "buff monitor reuses snapshot buffers")
assertEqual(visibility.viewerState.buffVisibilityItems, reusableItems,
    "buff monitor reuses item storage")
assertTrue(visibility.monitor.ticker ~= nil, "active buff re-arms monitor")

visibility.viewer.hideWhenInactive = false
visibility.monitor:Update()
assertEqual(visibility.monitor.ticker, nil,
    "viewer without hideWhenInactive is not monitored")

visibility.viewer.hideWhenInactive = true
visibility.module.config.viewers.buffIcon.visibility = "hidden"
visibility.monitor:Update()
assertEqual(visibility.monitor.ticker, nil,
    "hidden viewer is not monitored")

visibility.module.config.viewers.buffIcon.visibility = "always"
visibility.item.shown = "secret"
visibility.monitor:Update()
assertTrue(visibility.monitor.ticker ~= nil,
    "unsafe initial sample gets a bounded retry")
for _ = 1, 20 do
    local ticker = visibility.monitor.ticker
    if not ticker then break end
    ticker.callback()
end
assertEqual(visibility.monitor.ticker, nil,
    "persistently unsafe sampling does not become permanent idle work")

visibility.item.shown = true
visibility.monitor:Update()
assertTrue(visibility.monitor.ticker ~= nil,
    "later safe lifecycle update can re-arm buff monitor")
visibility.module.config.enabled = false
visibility.monitor:Update()
assertEqual(visibility.monitor.ticker, nil, "module disable stops buff monitor")

---------------------------------------------------------------------
-- Missing item restoration participates in reconciliation completion
---------------------------------------------------------------------

local reconcileSource = extract(
    moduleSource,
    "local function RestoreMissingItems",
    "local function RestoreViewer"
)

local reconcile = loadHarness([[
local state = {
    editMode = false,
    restoreResult = false,
}
local viewerState = {
    definition = {previewCount = 1},
}
local missingItem = {}
local itemStates = {
    [missingItem] = {
        applied = true,
        owner = viewerState,
    },
}
local CM = {config = {skin = false}}

local function BindHolderPosition()
    return true
end
local function GetOrderedItems()
    return {}, {}
end
local function RestoreItem()
    state.restoreCalls = (state.restoreCalls or 0) + 1
    return state.restoreResult
end
local function IsBlizzardEditModeActive()
    return state.editMode
end
local function BuildLayout()
    return {height = 1, scale = 1}
end
local function UpdateHolderPreview() end
]] .. reconcileSource .. [[

return {
    reconcile = ReconcileViewer,
    state = state,
    viewerState = viewerState,
}
]], "cooldown_manager_restore_completion")

reconcile.state.editMode = true
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), false,
    "edit-mode missing restore failure remains incomplete")
reconcile.state.editMode = false
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), false,
    "normal missing restore failure remains incomplete")
reconcile.state.restoreResult = true
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), true,
    "successful missing restore completes reconciliation")

---------------------------------------------------------------------
-- Structural wake coverage and absence of broad permanent polling
---------------------------------------------------------------------

assertEqual(
    moduleSource:find('HighlightState.controller:SetScript("OnUpdate"', 1, true),
    nil,
    "assisted controller has no permanent OnUpdate"
)
assertEqual(moduleSource:find("local function PollPresentation", 1, true), nil,
    "broad presentation poll removed")
assertContains(moduleSource,
    'RegisterUnitEvent("UNIT_AURA", "player", "target")',
    "aura visibility wake")
assertContains(moduleSource,
    'RegisterUnitEvent("UNIT_TARGET", "player")',
    "12.0.7 target wake")
assertContains(moduleSource,
    'RegisterEvent("PLAYER_TARGET_CHANGED")',
    "12.1 target wake")
assertContains(moduleSource,
    "PLAYER_REGEN_ENABLED = true",
    "combat-denied regeneration wake")
assertContains(moduleSource,
    'RegisterEvent("SPELL_UPDATE_COOLDOWN")',
    "cooldown visibility wake")
assertContains(moduleSource,
    '"CooldownViewerSettings.OnDataChanged"',
    "viewer assignment wake")
assertContains(moduleSource,
    '"AssistedCombatManager.OnAssistedHighlightSpellChange"',
    "assisted recommendation wake")
assertContains(moduleSource,
    '"AssistedCombatManager.OnSetUseAssistedHighlight"',
    "assisted CVar wake")
assertContains(moduleSource,
    '"AssistedCombatManager.OnSetActionSpell"',
    "assisted action wake")
assertContains(moduleSource,
    '"assistedCombatIconUpdateRate",\n    HighlightState.UpdateAssistedHighlightFallback',
    "assisted fallback cadence CVar lifecycle")

print("cooldown_manager_idle_test.lua: ok")
