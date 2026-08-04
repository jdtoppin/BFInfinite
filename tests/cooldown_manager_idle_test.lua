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
local activationSettlementSource = extract(
    moduleSource,
    "PresentationMethods.activationSettlementDelays =",
    "methodFrame:Hide()"
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

local PresentationMethods = {}
]] .. activationSettlementSource .. [[

local HighlightState = {}
local CM = {
    config = {
        enabled = true,
        viewers = {essential = {}},
    },
}
local viewerStates = {{key = "essential"}}
local QueuePresentationUpdate
local presentationGeneration = 1
local C_Timer = {}

function C_Timer.After(delay, callback)
    state.scheduled = state.scheduled or {}
    state.scheduled[#state.scheduled + 1] = {
        delay = delay,
        callback = callback,
    }
end

local function MarkPresentationDirty()
    presentationGeneration = presentationGeneration + 1
    QueuePresentationUpdate()
end

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
    if state.poolReady
        and state.lastStaticGeneration ~= presentationGeneration
    then
        state.lastStaticGeneration = presentationGeneration
        state.staticApplications = (state.staticApplications or 0) + 1
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

local function RunScheduled(index)
    local scheduled = state.scheduled and state.scheduled[index]
    if not scheduled then
        error("missing scheduled callback " .. tostring(index), 2)
    end
    scheduled.callback()
end

return {
    controller = presentationController,
    highlight = HighlightState,
    module = CM,
    queue = QueuePresentationUpdate,
    run = Run,
    state = state,
    scheduledCount = function()
        return state.scheduled and #state.scheduled or 0
    end,
    scheduledDelay = function(index)
        return state.scheduled[index].delay
    end,
    runScheduled = RunScheduled,
    getPresentationGeneration = function()
        return presentationGeneration
    end,
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

-- A disabled-to-enabled transition schedules a sparse, bounded ladder of
-- one-shot verification passes. Each pass invalidates static presentation so
-- a native pool populated several seconds after login is still styled, while
-- successful work returns to dormancy between callbacks.
local settlementDelays = {0, 0.2, 1, 3, 6}
assertEqual(controller.controller:UpdateActivationSettlement(false), false,
    "disabled activation invalidates without scheduling")
local firstSettlement = controller.scheduledCount() + 1
assertEqual(controller.controller:UpdateActivationSettlement(true), true,
    "first enable arms settlement")
assertEqual(
    controller.scheduledCount(),
    firstSettlement + #settlementDelays - 1,
    "first enable schedules a finite settlement ladder"
)
for offset, delay in ipairs(settlementDelays) do
    assertEqual(
        controller.scheduledDelay(firstSettlement + offset - 1),
        delay,
        "activation settlement uses sparse delay " .. offset
    )
end
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "scheduled settlement does not install a steady update")

local activationCalls = controller.state.reconcileCalls
local activationGeneration = controller.getPresentationGeneration()
for offset = 0, #settlementDelays - 2 do
    controller.runScheduled(firstSettlement + offset)
    assertEqual(type(controller.controller.scripts.OnUpdate), "function",
        "settlement callback wakes one finite reconciliation pass")
    controller.run()
    assertEqual(controller.controller.scripts.OnUpdate, nil,
        "successful settlement pass immediately returns to dormancy")
    assertEqual(controller.state.staticApplications, nil,
        "empty native pools do not invent static work")
end

controller.state.poolReady = true
controller.runScheduled(firstSettlement + #settlementDelays - 1)
controller.run()
assertEqual(
    controller.state.reconcileCalls,
    activationCalls + #settlementDelays,
    "activation settlement verifies every sparse pass"
)
assertEqual(
    controller.getPresentationGeneration(),
    activationGeneration + #settlementDelays,
    "every settlement callback invalidates static styling"
)
assertEqual(controller.state.staticApplications, 1,
    "late native pool receives static styling on the final pass")
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "activation settlement finishes dormant")

local scheduledAfterFirstEnable = controller.scheduledCount()
assertEqual(controller.controller:UpdateActivationSettlement(true), false,
    "ordinary enabled update does not rearm settlement")
assertEqual(controller.scheduledCount(), scheduledAfterFirstEnable,
    "ordinary enabled update does not rearm settlement")
local forcedSettlement = controller.scheduledCount() + 1
assertEqual(controller.controller:UpdateActivationSettlement(true, true), true,
    "forced world-entry settlement rearms while enabled")
assertEqual(
    controller.scheduledCount(),
    forcedSettlement + #settlementDelays - 1,
    "forced world-entry settlement remains finite"
)
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "forced settlement stays dormant until a callback fires")

-- Timer cancellation is represented by a generation token: callbacks already
-- owned by C_Timer cannot be removed, but callbacks from a disabled generation
-- must become harmless even after a later enable arms a new ladder.
assertEqual(controller.controller:UpdateActivationSettlement(false), false,
    "disable invalidates forced settlement callbacks")
local staleSettlement = controller.scheduledCount() + 1
controller.controller:UpdateActivationSettlement(true)
assertEqual(
    controller.scheduledCount(),
    staleSettlement + #settlementDelays - 1,
    "later re-enable rearms a bounded settlement ladder"
)
controller.controller:UpdateActivationSettlement(false)
local currentSettlement = controller.scheduledCount() + 1
controller.controller:UpdateActivationSettlement(true)
assertEqual(
    controller.scheduledCount(),
    currentSettlement + #settlementDelays - 1,
    "new activation owns a distinct callback generation"
)

local callsBeforeStaleCallbacks = controller.state.reconcileCalls
local generationBeforeStaleCallbacks = controller.getPresentationGeneration()
for offset = 0, #settlementDelays - 1 do
    controller.runScheduled(staleSettlement + offset)
end
assertEqual(controller.state.reconcileCalls, callsBeforeStaleCallbacks,
    "stale callbacks do not reconcile after disable and re-enable")
assertEqual(
    controller.getPresentationGeneration(),
    generationBeforeStaleCallbacks,
    "stale callbacks do not invalidate static presentation"
)
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "stale callbacks cannot wake the presentation controller")

controller.runScheduled(currentSettlement)
assertEqual(type(controller.controller.scripts.OnUpdate), "function",
    "current activation callback still wakes reconciliation")
controller.run()
assertEqual(controller.state.reconcileCalls, callsBeforeStaleCallbacks + 1,
    "current activation callback reconciles once")
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "current activation callback sleeps after success")

controller.controller:UpdateActivationSettlement(false)
local callsBeforeDisabledCallback = controller.state.reconcileCalls
local generationBeforeDisabledCallback = controller.getPresentationGeneration()
controller.runScheduled(currentSettlement + 1)
assertEqual(controller.state.reconcileCalls, callsBeforeDisabledCallback,
    "disable invalidates remaining current callbacks")
assertEqual(
    controller.getPresentationGeneration(),
    generationBeforeDisabledCallback,
    "disabled callback cannot invalidate static presentation"
)
assertEqual(controller.controller.scripts.OnUpdate, nil,
    "disabled settlement remains dormant")

---------------------------------------------------------------------
-- Managed viewer-root integrity guard
---------------------------------------------------------------------

local rootGeometrySource = extract(
    moduleSource,
    "function PresentationMethods.ViewerAnchorMatches",
    "function PresentationMethods.BindViewerGeometry"
)
local rootIntegritySource = extract(
    moduleSource,
    "function PresentationMethods.ProcessManagedRootIntegrity",
    "-- UNIT_AURA is payload-opaque"
)

local rootIntegrity = loadHarness([[
local SECRET = {}
local state = {
    dirtyMarks = 0,
    editMode = false,
    inCombat = false,
    writes = 0,
}
local holder = {}
local managedViewer = {
    scale = 1,
    points = {{"CENTER", holder, "CENTER", 0, 0}},
}
local unmanagedViewer = {
    scale = 1,
    points = {
        {"TOPLEFT", {}, "TOPLEFT", 0, 0},
        {"BOTTOMRIGHT", {}, "BOTTOMRIGHT", 0, 0},
    },
}
local managedViewerState = {
    definition = {managedRoot = true},
    holder = holder,
    viewer = managedViewer,
    viewerGeometryApplied = true,
    nativeViewerPoints = {{"BOTTOM", {}, "BOTTOM", 0, 100}},
}
local viewerStates = {
    managedViewerState,
    {
        definition = {isBar = true},
        holder = {},
        viewer = unmanagedViewer,
        viewerGeometryApplied = true,
    },
}
local CM = {
    config = {
        enabled = true,
        viewers = {},
    },
}
local presentationController = {
    rootIntegrity = {scripts = {}},
}
function presentationController.rootIntegrity:SetScript(script, handler)
    self.scripts[script] = handler
end

local PresentationMethods = {}
local function IsValueNonSecret(value)
    return value ~= SECRET
end
local function IsSafeNumber(value)
    return IsValueNonSecret(value) and type(value) == "number"
end
local function IsSafeString(value)
    return IsValueNonSecret(value) and type(value) == "string"
end
local function NearlyEqual(left, right)
    return math.abs(left - right) < 0.001
end
local function IsBlizzardEditModeActive()
    return state.editMode
end
local function InCombatLockdown()
    return state.inCombat
end
local function CanChangeGeometry()
    return not state.inCombat
end
local function MarkPresentationDirty()
    state.dirtyMarks = state.dirtyMarks + 1
end
local function FrameGetNumPoints(frame)
    return #frame.points
end
local function FrameGetScale(frame)
    return frame.scale
end
local function FrameGetPoint(frame, index)
    return unpack(frame.points[index])
end
local function CapturePoints(frame)
    local points = {}
    for index, point in ipairs(frame.points) do
        points[index] = {unpack(point)}
    end
    return points
end
local function FrameSetScale(frame, scale)
    state.writes = state.writes + 1
    frame.scale = scale
end
local function FrameClearAllPoints(frame)
    state.writes = state.writes + 1
    frame.points = {}
end
local function FrameSetPoint(frame, ...)
    state.writes = state.writes + 1
    frame.points = {{...}}
end
]] .. rootGeometrySource .. rootIntegritySource .. [[

return {
    controller = presentationController,
    managedState = managedViewerState,
    managedViewer = managedViewer,
    module = CM,
    unmanagedViewer = unmanagedViewer,
    run = PresentationMethods.ProcessManagedRootIntegrity,
    state = state,
}
]], "cooldown_manager_root_integrity")

rootIntegrity.controller:UpdateRootIntegrity(true)
assertEqual(
    rootIntegrity.controller.rootIntegrity.scripts.OnUpdate,
    rootIntegrity.run,
    "enabled root integrity guard installs its worker"
)
rootIntegrity.run()
assertEqual(rootIntegrity.state.writes, 0,
    "stable managed root integrity pass performs no writes")
assertEqual(rootIntegrity.state.dirtyMarks, 0,
    "stable managed root integrity pass queues no presentation work")

rootIntegrity.managedViewer.points = {
    {"TOPLEFT", {}, "TOPLEFT", 0, 0},
    {"BOTTOMRIGHT", {}, "BOTTOMRIGHT", 0, 0},
}
rootIntegrity.run()
assertEqual(rootIntegrity.managedViewer.scale, 1,
    "managed root integrity guard changed native root scale")
assertEqual(#rootIntegrity.managedViewer.points, 1,
    "managed root integrity guard repairs a multi-point rewrite")
assertEqual(rootIntegrity.state.writes, 2,
    "managed root repair performs only anchor writes")
assertEqual(rootIntegrity.state.dirtyMarks, 1,
    "managed root repair queues one finite presentation pass")
assertEqual(#rootIntegrity.managedState.nativeViewerPoints, 2,
    "managed root repair did not retain the latest native layout")
assertTrue(rootIntegrity.managedState.nativeViewerPoints[1][2]
    ~= rootIntegrity.managedState.holder,
    "managed root repair captured BFI's holder as the native baseline")
assertEqual(rootIntegritySource:find("ReconcileViewer", 1, true), nil,
    "managed root guard references full reconciliation")
assertEqual(rootIntegritySource:find("ApplyStaticPresentation", 1, true), nil,
    "managed root guard references static presentation")
rootIntegrity.run()
assertEqual(rootIntegrity.state.writes, 2,
    "stable guard pass after repair unexpectedly rewrites root geometry")
assertEqual(rootIntegrity.state.dirtyMarks, 1,
    "stable guard pass after repair unexpectedly queues duplicate work")

local writesBeforeRestriction = rootIntegrity.state.writes
rootIntegrity.managedViewer.points = {
    {"TOPLEFT", {}, "TOPLEFT", 0, 0},
    {"BOTTOMRIGHT", {}, "BOTTOMRIGHT", 0, 0},
}
rootIntegrity.state.editMode = nil
rootIntegrity.run()
assertEqual(rootIntegrity.state.writes, writesBeforeRestriction,
    "unsafe edit-mode visibility did not fail closed")
assertEqual(#rootIntegrity.managedViewer.points, 2,
    "unsafe edit-mode visibility changed managed root geometry")
rootIntegrity.state.editMode = true
rootIntegrity.run()
assertEqual(rootIntegrity.state.writes, writesBeforeRestriction,
    "edit mode blocks managed root repair")
assertEqual(rootIntegrity.state.dirtyMarks, 1,
    "edit mode unexpectedly queues managed root presentation work")
assertEqual(#rootIntegrity.managedViewer.points, 2,
    "edit mode preserves Blizzard-managed root geometry")

rootIntegrity.state.editMode = false
rootIntegrity.state.inCombat = true
rootIntegrity.run()
assertEqual(rootIntegrity.state.writes, writesBeforeRestriction,
    "combat blocks managed root repair")
assertEqual(rootIntegrity.state.dirtyMarks, 1,
    "combat unexpectedly queues managed root presentation work")
assertEqual(#rootIntegrity.managedViewer.points, 2,
    "combat leaves managed root geometry untouched")

rootIntegrity.state.inCombat = false
rootIntegrity.run()
assertEqual(#rootIntegrity.managedViewer.points, 1,
    "managed root repair resumes after restrictions lift")
assertEqual(rootIntegrity.state.dirtyMarks, 2,
    "post-restriction repair did not queue one presentation pass")
assertEqual(rootIntegrity.unmanagedViewer.scale, 1,
    "unmanaged tracked-bar root scale was changed")
assertEqual(#rootIntegrity.unmanagedViewer.points, 2,
    "unmanaged tracked-bar root anchors were changed")

rootIntegrity.controller:UpdateRootIntegrity(false)
assertEqual(rootIntegrity.controller.rootIntegrity.scripts.OnUpdate, nil,
    "module disable removes managed root integrity worker")
rootIntegrity.controller:UpdateRootIntegrity(true)
rootIntegrity.module.config.enabled = false
rootIntegrity.run()
assertEqual(rootIntegrity.controller.rootIntegrity.scripts.OnUpdate, nil,
    "disabled guard removes its own update script")

---------------------------------------------------------------------
-- Assisted highlight restoration hides the inactive region tree
---------------------------------------------------------------------

local restoreSource = extract(
    moduleSource,
    "local function RestoreItemPresentation",
    "local function CanRestoreItemPresentation"
)

local restoredHighlight = loadHarness([[
local state = {
    alphaWrites = 0,
}
local item = {}
local highlight = {
    shown = true,
}
local HighlightState = {
    assisted = {[item] = highlight},
    proc = {},
}
function HighlightState.proc.SetShown(region, shown)
    state.sharedShown = shown
    region.shown = shown
end
function HighlightState.proc.Restore(target)
    state.procRestoreTarget = target
    return true
end
local PresentationMethods = {
    RestoreFontStringPresentation = function() end,
}
local function GetSafeField(owner, key)
    return owner[key]
end
local function GetCountText()
    return nil
end
local function HideItemHotkey(target)
    state.hotkeyTarget = target
end
local function FrameSetAlpha()
    state.alphaWrites = state.alphaWrites + 1
end
]] .. restoreSource .. [[

local itemState = {
    presentationGeneration = 1,
}
state.restored = RestoreItemPresentation(item, {}, itemState)
state.highlightShown = highlight.shown
state.presentationGeneration = itemState.presentationGeneration
return state
]], "cooldown_manager_highlight_restore")

assertEqual(restoredHighlight.restored, true,
    "item presentation restore completes")
assertEqual(restoredHighlight.sharedShown, false,
    "restore routes assisted highlight through shared visibility lifecycle")
assertEqual(restoredHighlight.highlightShown, false,
    "restored assisted highlight tree is hidden")
assertEqual(restoredHighlight.alphaWrites, 0,
    "restore does not leave an alpha-muted highlight tree shown")
assertTrue(restoredHighlight.procRestoreTarget ~= nil,
    "restore retains native proc restoration")
assertTrue(restoredHighlight.hotkeyTarget ~= nil,
    "restore retains hotkey cleanup")
assertEqual(restoredHighlight.presentationGeneration, nil,
    "restore clears presentation generation")

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
    inCombat = false,
    nextSpell = 101,
    baseCalls = 0,
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
    state.baseCalls = state.baseCalls + 1
    return spellID and spellID + 1000 or nil
end
local function UnitAffectingCombat()
    return state.inCombat
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
assertEqual(assisted.highlight.fallbackTicker, nil,
    "assisted fallback is dormant out of combat")
assertEqual(assisted.state.queryCalls, 1, "fallback lifecycle samples immediately")
assertEqual(assisted.state.refreshCalls, 1, "initial recommendation refreshes")
assertEqual(assisted.state.queueCalls, 1, "initial recommendation queues hotkey work")

assisted.state.nextSpell = 202
assisted.event(nil, "SPELL_UPDATE_COOLDOWN")
assertEqual(assisted.highlight.fallbackTicker, nil,
    "out-of-combat recommendation events do not arm a ticker")
assertEqual(assisted.state.refreshCalls, 2,
    "out-of-combat recommendation edge refreshes immediately")
assertEqual(assisted.state.queueCalls, 2,
    "out-of-combat recommendation edge queues presentation once")
local unchangedOOCBaseCalls = assisted.state.baseCalls
assisted.event(nil, "UNIT_POWER_UPDATE")
assertEqual(assisted.state.baseCalls, unchangedOOCBaseCalls,
    "unchanged out-of-combat edge does no base-spell lookup")
assertEqual(assisted.state.refreshCalls, 2,
    "unchanged out-of-combat edge does no highlight work")

assisted.state.inCombat = true
assisted.event(nil, "PLAYER_REGEN_DISABLED")
assertEqual(assisted.state.lastTicker.interval, 0.2, "assisted fallback cadence")
local assistedTicker = assisted.state.lastTicker
local unchangedBaseCalls = assisted.state.baseCalls
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 3,
    "unchanged fallback does no highlight work")
assertEqual(assisted.state.queueCalls, 2,
    "unchanged fallback does no presentation work")
assertEqual(assisted.state.baseCalls, unchangedBaseCalls,
    "unchanged fallback does no base-spell lookup")

assisted.state.nextSpell = 303
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 4,
    "changed fallback refreshes immediately")
assertEqual(assisted.state.queueCalls, 3,
    "changed fallback queues presentation once")

assisted.controller.combatBlocked = true
assisted.state.nextSpell = 404
assistedTicker.callback()
assertEqual(assisted.state.refreshCalls, 5,
    "combat latch does not block runtime highlight refresh")
assertEqual(assisted.state.queueCalls, 3,
    "combat latch still defers broad presentation")
local queueAttempts = assisted.state.queueAttempts
assisted.event(nil, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
assertEqual(assisted.state.refreshCalls, 6,
    "glow event refreshes runtime highlight behind latch")
assertEqual(assisted.state.queueAttempts, queueAttempts,
    "unchanged glow event does not queue broad work")

assisted.controller.combatBlocked = nil
assisted.state.inCombat = false
assisted.event(nil, "PLAYER_REGEN_ENABLED")
assertEqual(assistedTicker.cancelled, true,
    "combat exit cancels assisted fallback")
assertEqual(assisted.highlight.fallbackTicker, nil,
    "combat exit releases assisted fallback")

assisted.state.inCombat = true
assisted.event(nil, "PLAYER_REGEN_DISABLED")
local featureTicker = assisted.state.lastTicker
assisted.module.config.assistedHighlight = false
assisted.updateFallback()
assertEqual(featureTicker.cancelled, true, "feature disable cancels fallback")
assertEqual(assisted.highlight.fallbackTicker, nil, "cancelled fallback is released")
assertEqual(assisted.highlight.spellID, nil, "feature disable clears recommendation")

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
local item2 = {shown = true}
state.items = {item, item2}
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
    item2 = item2,
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
    "buff monitor sleeps after compacting to one visible item")

visibility.item.shown = true
visibility.monitor:Update()
assertEqual(visibility.viewerState.buffVisibilitySnapshots, snapshotBuffers,
    "buff monitor reuses snapshot buffers")
assertEqual(visibility.viewerState.buffVisibilityItems, reusableItems,
    "buff monitor reuses item storage")
assertTrue(visibility.monitor.ticker ~= nil, "active buff re-arms monitor")

visibility.item2.shown = false
visibility.monitor:Update()
assertEqual(visibility.monitor.ticker, nil,
    "a lone visible buff needs no idle visibility monitor")
visibility.item2.shown = true
visibility.monitor:Update()
assertTrue(visibility.monitor.ticker ~= nil,
    "a second visible buff re-arms compaction monitoring")

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
visibility.item2.shown = true
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
    viewer = {shown = false},
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
    state.restoreOrder = state.restoreOrder or {}
    state.restoreOrder[#state.restoreOrder + 1] = "item"
    return state.restoreResult
end
local PresentationMethods = {
    RestoreViewerGeometry = function()
        state.rootRestoreCalls = (state.rootRestoreCalls or 0) + 1
        state.restoreOrder = state.restoreOrder or {}
        state.restoreOrder[#state.restoreOrder + 1] = "root"
        return true
    end,
    GetPixelSnappedScale = function(_, _, scale)
        return scale
    end,
    GetItemLayoutScale = function()
        return 1
    end,
    BindViewerGeometry = function()
        return true, false
    end,
}
local function IsBlizzardEditModeActive()
    return state.editMode
end
local function FrameIsShown(frame)
    return frame.shown
end
local function IsSafeBoolean(value)
    return type(value) == "boolean"
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
assertEqual(reconcile.state.rootRestoreCalls, nil,
    "viewer root is not restored before child restoration succeeds")
reconcile.state.editMode = false
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), false,
    "normal missing restore failure remains incomplete")
reconcile.state.restoreResult = true
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), true,
    "successful missing restore completes reconciliation")
reconcile.viewerState.viewer.shown = true
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), false,
    "shown empty native viewer remains construction-incomplete")
reconcile.viewerState.viewer.shown = false
reconcile.state.editMode = nil
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), false,
    "unsafe edit-mode visibility does not fail reconciliation closed")
reconcile.state.editMode = true
reconcile.state.restoreOrder = {}
assertEqual(reconcile.reconcile(reconcile.viewerState, {}), true,
    "successful edit-mode restoration completes reconciliation")
assertEqual(table.concat(reconcile.state.restoreOrder, ","), "item,root",
    "edit-mode restoration restores child geometry before viewer root geometry")

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
    'RegisterEvent("PLAYER_TARGET_CHANGED")',
    "12.1 target wake")
assertContains(moduleSource,
    "UPDATE_SHAPESHIFT_FORM = true",
    "12.1 active-form watch wake")
assertContains(moduleSource,
    "UPDATE_SHAPESHIFT_FORMS = true",
    "12.1 form-list watch wake")
assertContains(moduleSource,
    "function PresentationMethods.BindViewerGeometry",
    "native viewer root landing geometry")
assertContains(moduleSource,
    "presentationController:UpdateActivationSettlement(",
    "module enable arms bounded native construction settlement")
assertContains(moduleSource,
    "presentationController:UpdateActivationSettlement(true, true)",
    "world entry force-rearms bounded native construction settlement")
assertContains(moduleSource,
    "C_Timer.After(delay, function()",
    "activation settlement uses finite one-shot callbacks")
assertEqual(moduleSource:find("activationPassesRemaining", 1, true), nil,
    "dense frame-driven activation passes removed")
assertContains(moduleSource,
    'FrameSetPoint(item, "CENTER", state.holder, "CENTER"',
    "exact item layout is relative to the persistent BFI holder")
assertEqual(moduleSource:find("targetObserver", 1, true), nil,
    "opaque aura observer transaction removed")
assertEqual(moduleSource:find("CurtainTargetTransition", 1, true), nil,
    "form and target wakes do not hide viewers")
assertContains(moduleSource,
    "PLAYER_REGEN_ENABLED = true",
    "combat-denied regeneration wake")
assertEqual(
    moduleSource:find(
        'presentationController:RegisterEvent("SPELL_UPDATE_COOLDOWN")',
        1,
        true
    ),
    nil,
    "steady cooldown events do not wake full presentation reconciliation"
)
assertContains(moduleSource,
    'HighlightState.controller:RegisterEvent("SPELL_UPDATE_COOLDOWN")',
    "cooldown edges cheaply observe false-mode recommendations")
assertEqual(
    moduleSource:find('RegisterEvent("SPELL_UPDATE_ICON")', 1, true),
    nil,
    "native icon refreshes do not wake full presentation reconciliation"
)
assertEqual(
    moduleSource:find("FrameSetAlpha(highlight, shown and 1 or 0)", 1, true),
    nil,
    "inactive BFI highlight region trees are hidden instead of alpha-muted"
)
assertContains(moduleSource,
    '"CooldownViewerSettings.OnDataChanged"',
    "viewer assignment wake")
assertContains(moduleSource,
    "PresentationMethods.OnCooldownDataChanged",
    "viewer assignment rebuild wake")
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
