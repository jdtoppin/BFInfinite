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
    assertEqual(value == true, true, message)
end

local function assertFalse(value, message)
    assertEqual(value == true, false, message)
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end

local function findCall(calls, name, startIndex)
    for index = startIndex or 1, #calls do
        if calls[index].name == name then
            return calls[index], index
        end
    end
end

local function countCalls(calls, name)
    local count = 0
    for _, call in ipairs(calls) do
        if call.name == name then
            count = count + 1
        end
    end
    return count
end

local function NewHarness()
    local state = {
        afTotals = {
            containerCreateAttempts = 0,
            containerAllocations = 0,
            containerCreateCompletions = 0,
            trackedContainers = 0,
            externalContainersObserved = 0,
            groupAddAttempts = 0,
            groupsAdded = 0,
            itemEnchantmentAddAttempts = 0,
            itemEnchantmentsAdded = 0,
            initialFrameReservationsAttempted = 0,
            initialFrameReservationsCompleted = 0,
        },
        calls = {},
        capability = true,
        canSuppress = true,
        combat = false,
        suppressEnableSucceeds = true,
        suppressRestoreSucceeds = true,
        timers = {},
        events = {},
        frames = {},
        playerUnit = "player",
    }

    local function record(name, ...)
        local call = {
            name = name,
            args = {...},
        }
        state.calls[#state.calls + 1] = call
        return call
    end

    local function NewFrame(label)
        local frame = {
            label = label,
            shown = true,
        }
        state.frames[#state.frames + 1] = frame

        function frame:Hide()
            self.shown = false
            record(label .. ".Hide")
        end

        function frame:Show()
            self.shown = true
            record(label .. ".Show")
        end

        function frame:IsMouseOver()
            error("forbidden hover accessor was called", 2)
        end

        function frame:ClearAllPoints()
            record(label .. ".ClearAllPoints")
        end

        function frame:SetPoint(...)
            record(label .. ".SetPoint", ...)
        end

        return frame
    end

    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.PlayerFrame = setmetatable({}, {
        __index = function(_, key)
            if key == "unit" then return state.playerUnit end
        end,
    })
    environment.InCombatLockdown = function()
        return state.combat
    end
    environment.C_Timer = {
        After = function(delay, callback)
            record("Timer.After", delay)
            state.timers[#state.timers + 1] = {
                delay = delay,
                callback = callback,
            }
        end,
    }
    environment.CreateFrame = function(frameType, name, parent)
        assertEqual(frameType, "Frame", "only plain holders use CreateFrame")
        assertEqual(name, nil, "holder is anonymous")
        assertTrue(parent ~= nil, "holder parent")
        record("CreateFrame.Holder")
        return NewFrame("holder" .. tostring(#state.frames + 1))
    end
    environment.Mixin = function(target, mixin)
        for key, value in pairs(mixin) do
            target[key] = value
        end
        return target
    end

    local AF = {
        UIParent = {},
    }
    function AF.Copy(value)
        return deepCopy(value)
    end
    function AF.Fire(...)
        record("AF.Fire", ...)
    end
    function AF.SetSize(frame, width, height)
        frame.width = width
        frame.height = height
        record("AF.SetSize", frame.label, width, height)
    end
    function AF.CreateMover(frame, group, text, save)
        frame.mover = {}
        record("AF.CreateMover", frame.label, group, text, save)
    end
    function AF.UpdateMoverSave(frame, save)
        record("AF.UpdateMoverSave", frame.label, save)
    end
    function AF.LoadPosition(frame, position)
        record("AF.LoadPosition", frame.label, position)
    end
    function AF.CreateCustomAuraContainer(parent)
        state.afTotals.containerCreateAttempts =
            state.afTotals.containerCreateAttempts + 1
        state.afTotals.containerAllocations =
            state.afTotals.containerAllocations + 1
        state.afTotals.containerCreateCompletions =
            state.afTotals.containerCreateCompletions + 1
        state.afTotals.trackedContainers =
            state.afTotals.trackedContainers + 1
        record("AF.CreateCustomAuraContainer", parent.label)
        return NewFrame("container" .. tostring(state.afTotals.containerAllocations))
    end
    function AF.SetCustomAuraContainerEnabled(container, enabled)
        container.enabled = enabled
        record("AF.SetCustomAuraContainerEnabled", enabled)
    end
    function AF.SetCustomAuraContainerFlowLayout(_, layout)
        record("AF.SetCustomAuraContainerFlowLayout", layout)
    end
    function AF.SetCustomAuraContainerProcessingPolicy(_, policy, options)
        record("AF.SetCustomAuraContainerProcessingPolicy", policy, options)
    end
    function AF.SetCustomItemEnchantmentSortMethod(_, method, direction)
        record("AF.SetCustomItemEnchantmentSortMethod", method, direction)
    end
    function AF.SetCustomItemEnchantmentLayout(_, layout)
        record("AF.SetCustomItemEnchantmentLayout", layout)
    end
    function AF.AddCustomItemEnchantment(_, slot, options, buttonStyle)
        state.afTotals.itemEnchantmentAddAttempts =
            state.afTotals.itemEnchantmentAddAttempts + 1
        state.afTotals.initialFrameReservationsAttempted =
            state.afTotals.initialFrameReservationsAttempted + 1
        record("AF.AddCustomItemEnchantment", slot, options, buttonStyle)
        state.afTotals.itemEnchantmentsAdded =
            state.afTotals.itemEnchantmentsAdded + 1
        state.afTotals.initialFrameReservationsCompleted =
            state.afTotals.initialFrameReservationsCompleted + 1
    end
    function AF.AddCustomAuraGroup(_, key, filterString, options, buttonStyle)
        state.afTotals.groupAddAttempts =
            state.afTotals.groupAddAttempts + 1
        state.afTotals.initialFrameReservationsAttempted =
            state.afTotals.initialFrameReservationsAttempted + 10
        record("AF.AddCustomAuraGroup", key, filterString, options, buttonStyle)
        if state.failGroupAdd then
            error("deterministic group construction failure")
        end
        state.afTotals.groupsAdded = state.afTotals.groupsAdded + 1
        state.afTotals.initialFrameReservationsCompleted =
            state.afTotals.initialFrameReservationsCompleted + 10
    end
    function AF.SetCustomAuraContainerUnit(_, unit)
        record("AF.SetCustomAuraContainerUnit", unit)
    end
    function AF.UpdateCustomAuraContainer()
        record("AF.UpdateCustomAuraContainer")
    end
    function AF.SetCustomAuraGroupFilterString(_, key, filterString)
        record("AF.SetCustomAuraGroupFilterString", key, filterString)
    end
    function AF.SetCustomAuraGroupMaxFrameCount(_, key, maximum)
        record("AF.SetCustomAuraGroupMaxFrameCount", key, maximum)
    end
    function AF.SetCustomAuraGroupCandidateFilters(_, key, filters)
        record("AF.SetCustomAuraGroupCandidateFilters", key, filters)
    end
    function AF.SetCustomAuraGroupSortMethod(_, key, method, direction)
        record("AF.SetCustomAuraGroupSortMethod", key, method, direction)
    end
    function AF.SetCustomAuraGroupLayout(_, key, layout)
        record("AF.SetCustomAuraGroupLayout", key, layout)
    end
    function AF.GetCustomAuraContainerConstructionTotals()
        return deepCopy(state.afTotals)
    end
    environment.AbstractFramework = AF

    local BD = {}
    function BD:RegisterEvent(event, callback)
        state.events[event] = state.events[event] or {}
        state.events[event][callback] = true
        record("BD.RegisterEvent", event, callback)
    end
    function BD:UnregisterEvent(event, callback)
        if state.events[event] then
            state.events[event][callback] = nil
        end
        record("BD.UnregisterEvent", event, callback)
    end
    function BD.HasCustomAuraContainerCapability()
        return state.capability
    end
    function BD.CanSuppressNativePublicAuras()
        return state.canSuppress
    end
    function BD.IsNativePublicAuraFrameHovered()
        error("obsolete native hover helper was called", 2)
    end
    function BD.SetNativePublicAurasSuppressed(which, suppressed)
        record("BD.SetNativePublicAurasSuppressed", which, suppressed)
        if suppressed then
            return state.suppressEnableSucceeds
        end
        return state.suppressRestoreSucceeds
    end

    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = L,
        funcs = {
            LoadPosition = function(frame, position)
                record("BFI.LoadPosition", frame.label, position)
            end,
        },
        modules = {
            BuffsDebuffs = BD,
        },
    }

    local chunk = assert(loadfile("Modules/BuffsDebuffs/CustomAuraContainer.lua"))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    function state.runTimers(delay)
        local remaining = {}
        local selected = {}
        for _, timer in ipairs(state.timers) do
            if delay == nil or timer.delay == delay then
                selected[#selected + 1] = timer
            else
                remaining[#remaining + 1] = timer
            end
        end
        state.timers = remaining
        for _, timer in ipairs(selected) do
            timer.callback()
        end
    end

    return {
        AF = AF,
        BD = BD,
        state = state,
    }
end

local function CompileBuffs(config)
    if config.unsupported then
        return nil, "UNSUPPORTED_TEST_CONFIG"
    end

    return {
        enabled = config.enabled == true,
        constructionKey = {
            style = config.style or "base",
        },
        holder = {
            width = config.holderWidth or 100,
            height = config.holderHeight or 40,
        },
        containerPoint = {
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = 0,
            y = 0,
        },
        flowLayout = {
            marker = config.tuning or 1,
        },
        processing = {
            policy = 0,
        },
        groups = {
            {
                key = "buffs",
                filterString = "HELPFUL",
                maxFrameCount = config.maximum or 20,
                candidateFilters = nil,
                sortMethod = 5,
                sortDirection = 0,
                layout = {
                    marker = config.tuning or 1,
                },
                buttonStyle = {
                    width = 26,
                    height = 26,
                },
            },
        },
        itemEnchantments = {
            {
                slot = 0,
                options = {},
                buttonStyle = {width = 26, height = 26},
            },
            {
                slot = 1,
                options = {},
                buttonStyle = {width = 26, height = 26},
            },
        },
        itemEnchantmentSort = {
            method = 0,
            direction = 0,
        },
        itemEnchantmentLayout = {
            placement = 0,
            marker = config.tuning or 1,
        },
        position = {"TOPRIGHT", -4, -4},
        positionSave = config.positionSave,
        moverText = "Buffs",
    }
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
    BD.RegisterCustomAuraContainerPane("debuffs", CompileBuffs)

    state.combat = true
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 21,
    })
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 22,
    })

    assertTrue(BD.GetCustomAuraContainerState("buffs").pending,
        "shared queue keeps buffs pending")
    assertTrue(BD.GetCustomAuraContainerState("debuffs").pending,
        "shared queue keeps debuffs pending")
    assertEqual(
        countCalls(state.calls, "BD.RegisterEvent"),
        4,
        "two controllers share one regen registration"
    )
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        0,
        "combat queue allocates neither controller"
    )

    state.combat = false
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)

    assertFalse(BD.GetCustomAuraContainerState("buffs").pending,
        "shared queue drains buffs")
    assertFalse(BD.GetCustomAuraContainerState("debuffs").pending,
        "shared queue drains debuffs")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        2,
        "shared queue constructs both controllers"
    )
    assertEqual(
        countCalls(state.calls, "BD.UnregisterEvent"),
        1,
        "shared regen callback unregisters after both controllers drain"
    )

    local sawBuffsTuning
    local sawDebuffsTuning
    for _, call in ipairs(state.calls) do
        if call.name == "AF.SetCustomAuraContainerFlowLayout" then
            if call.args[1].marker == 21 then
                sawBuffsTuning = true
            elseif call.args[1].marker == 22 then
                sawDebuffsTuning = true
            end
        end
    end
    assertTrue(sawBuffsTuning == true,
        "shared queue preserves buffs callback state")
    assertTrue(sawDebuffsTuning == true,
        "shared queue preserves debuffs callback state")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state

    assertFalse(BD.IsCustomAuraContainerAvailable("buffs"),
        "unregistered buffs availability")
    assertFalse(BD.IsCustomAuraContainerAvailable("debuffs"),
        "unregistered debuffs availability")
    assertEqual(#state.calls, 0, "availability performs no work")

    BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
    assertTrue(BD.IsCustomAuraContainerAvailable("buffs"),
        "registered buffs availability")
    assertFalse(BD.IsCustomAuraContainerAvailable("debuffs"),
        "debuffs remains unregistered")
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 0,
        "registration does not allocate")
    assertEqual(countCalls(state.calls, "AF.CreateCustomAuraContainer"), 0,
        "registration does not create a native container")

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = false,
    })
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 0,
        "disabled update does not allocate holder")
    assertEqual(countCalls(state.calls, "AF.CreateCustomAuraContainer"), 0,
        "disabled update does not allocate container")
    assertEqual(
        BD.GetCustomAuraContainerConstructionStats().buildAttempts,
        0,
        "disabled build attempts"
    )

    local buildStart = #state.calls + 1
    local profilePosition = {"TOPRIGHT", -4, -4}
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 1,
        positionSave = profilePosition,
    })
    local buildCalls = state.calls
    local _, restoreIndex = findCall(
        buildCalls,
        "BD.SetNativePublicAurasSuppressed",
        buildStart
    )
    local _, createIndex = findCall(
        buildCalls,
        "AF.CreateCustomAuraContainer",
        buildStart
    )
    local loadPositionCall = findCall(
        buildCalls,
        "BFI.LoadPosition",
        buildStart
    )
    local _, addItemIndex = findCall(
        buildCalls,
        "AF.AddCustomItemEnchantment",
        buildStart
    )
    local _, addGroupIndex = findCall(
        buildCalls,
        "AF.AddCustomAuraGroup",
        buildStart
    )
    local _, unitIndex = findCall(
        buildCalls,
        "AF.SetCustomAuraContainerUnit",
        buildStart
    )
    local _, updateIndex = findCall(
        buildCalls,
        "AF.UpdateCustomAuraContainer",
        buildStart
    )
    local enableCall, enableIndex = findCall(
        buildCalls,
        "AF.SetCustomAuraContainerEnabled",
        updateIndex + 1
    )
    local suppressCall, suppressIndex = findCall(
        buildCalls,
        "BD.SetNativePublicAurasSuppressed",
        enableIndex + 1
    )
    local _, showContainerIndex = findCall(
        buildCalls,
        "container1.Show",
        suppressIndex + 1
    )
    local _, showHolderIndex = findCall(
        buildCalls,
        "holder1.Show",
        showContainerIndex + 1
    )

    assertTrue(restoreIndex < createIndex, "restore precedes construction")
    assertTrue(loadPositionCall ~= nil,
        "holder uses BFI position compatibility loader")
    assertEqual(loadPositionCall.args[2][1], "TOPRIGHT",
        "holder compatibility position point")
    assertEqual(loadPositionCall.args[2][2], -4,
        "holder compatibility position X")
    assertEqual(loadPositionCall.args[2][3], -4,
        "holder compatibility position Y")
    assertEqual(countCalls(buildCalls, "AF.LoadPosition"), 0,
        "holder bypasses raw AF position loader")
    assertTrue(createIndex < addItemIndex, "container precedes enchantments")
    assertTrue(addItemIndex < addGroupIndex, "enchantments precede group")
    assertTrue(addGroupIndex < unitIndex, "all add-only sources precede unit")
    assertTrue(unitIndex < updateIndex, "unit precedes update")
    assertEqual(enableCall.args[1], true, "final native enable value")
    assertTrue(updateIndex < enableIndex, "update precedes enable")
    assertEqual(suppressCall.args[2], true, "suppression enable value")
    assertTrue(enableIndex < suppressIndex, "enable precedes suppression")
    assertTrue(suppressIndex < showContainerIndex, "suppression precedes container show")
    assertTrue(showContainerIndex < showHolderIndex, "container shows before holder")
    local moverCall = findCall(buildCalls, "AF.CreateMover", buildStart)
    assertEqual(moverCall.args[4], profilePosition,
        "mover retains profile position table identity")
    assertEqual(
        countCalls(buildCalls, "AF.AddCustomItemEnchantment"),
        2,
        "main/off-hand enchantment count"
    )
    assertEqual(
        countCalls(buildCalls, "AF.AddCustomAuraGroup"),
        1,
        "aura group count"
    )

    local activeState = BD.GetCustomAuraContainerState("buffs")
    assertEqual(activeState.state, "ACTIVE", "active state")
    assertTrue(activeState.active, "active flag")
    assertEqual(activeState.unit, "player", "initial player unit")

    local counters = BD.GetCustomAuraContainerConstructionStats()
    assertEqual(counters.buildAttempts, 1, "build attempts")
    assertEqual(counters.buildCompletions, 1, "build completions")
    assertEqual(counters.expectedGroups, 1, "expected groups")
    assertEqual(counters.expectedItemEnchantments, 2,
        "expected enchantments")
    assertEqual(counters.expectedInitialReservations, 12,
        "expected reservations")
    assertEqual(counters.incompleteBuilds, 0, "incomplete builds")
    assertEqual(counters.strandedNativeShells, 0, "stranded shells")
    assertEqual(counters.strandedInitialReservations, 0,
        "stranded reservations")
    assertEqual(counters.afGroupsAdded, 1, "AF group additions")
    assertEqual(counters.afItemEnchantmentsAdded, 2,
        "AF enchantment additions")

    counters.buildAttempts = 999
    assertEqual(
        BD.GetCustomAuraContainerConstructionStats().buildAttempts,
        1,
        "construction snapshot is immutable"
    )

    local createsBeforeTuning =
        countCalls(state.calls, "AF.CreateCustomAuraContainer")
    local groupsBeforeTuning =
        countCalls(state.calls, "AF.AddCustomAuraGroup")
    local enchantsBeforeTuning =
        countCalls(state.calls, "AF.AddCustomItemEnchantment")
    local tuningStart = #state.calls + 1
    local replacementPosition = {"TOPRIGHT", -8, -8}
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 2,
        maximum = 15,
        positionSave = replacementPosition,
    })
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeTuning,
        "tuning reuses container"
    )
    assertEqual(
        countCalls(state.calls, "AF.AddCustomAuraGroup"),
        groupsBeforeTuning,
        "tuning does not add groups"
    )
    assertEqual(
        countCalls(state.calls, "AF.AddCustomItemEnchantment"),
        enchantsBeforeTuning,
        "tuning does not add enchantments"
    )
    local maxCall = findCall(state.calls, "AF.SetCustomAuraGroupMaxFrameCount")
    assertTrue(maxCall ~= nil, "tuning applies maximum")
    local updateMoverCall = findCall(
        state.calls,
        "AF.UpdateMoverSave",
        tuningStart
    )
    assertEqual(updateMoverCall.args[2], replacementPosition,
        "live tuning refreshes mover profile table identity")

    local disableStart = #state.calls + 1
    BD.DisableCustomAuraContainer("buffs")
    local _, disableRestoreIndex = findCall(
        state.calls,
        "BD.SetNativePublicAurasSuppressed",
        disableStart
    )
    local disableCall, disableNativeIndex = findCall(
        state.calls,
        "AF.SetCustomAuraContainerEnabled",
        disableStart
    )
    assertEqual(disableCall.args[1], false, "disable native value")
    assertTrue(disableRestoreIndex < disableNativeIndex,
        "Blizzard restores before custom hides")
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").state,
        "INACTIVE",
        "disabled state"
    )

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 3,
    })
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeTuning,
        "re-enable reuses container"
    )
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").state,
        "ACTIVE",
        "re-enabled state"
    )

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        style = "changed",
        tuning = 4,
    })
    local reloadState = BD.GetCustomAuraContainerState("buffs")
    assertEqual(reloadState.state, "RELOAD_REQUIRED", "reload state")
    assertTrue(reloadState.reloadRequired, "reload flag")
    assertFalse(reloadState.active, "reload fallback is inactive")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeTuning,
        "construction change does not rebuild"
    )

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        style = "base",
        tuning = 5,
    })
    local revertedState = BD.GetCustomAuraContainerState("buffs")
    assertEqual(revertedState.state, "ACTIVE", "reverted construction state")
    assertFalse(revertedState.reloadRequired, "reverted reload flag")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeTuning,
        "construction revert reuses container"
    )

    state.combat = true
    local flowCallsBeforeCombat =
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout")
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 6,
    })
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 7,
    })
    assertTrue(BD.GetCustomAuraContainerState("buffs").pending,
        "combat update is pending")
    assertEqual(
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout"),
        flowCallsBeforeCombat,
        "combat performs no tuning"
    )
    assertEqual(
        countCalls(state.calls, "BD.RegisterEvent"),
        4,
        "unit events plus one regen registration"
    )

    state.combat = false
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    assertFalse(BD.GetCustomAuraContainerState("buffs").pending,
        "combat queue drained")
    local lastFlowCall
    for _, call in ipairs(state.calls) do
        if call.name == "AF.SetCustomAuraContainerFlowLayout" then
            lastFlowCall = call
        end
    end
    assertEqual(lastFlowCall.args[1].marker, 7,
        "combat queue keeps latest tuning")

    local pointerFlowCount =
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout")
    local pointerTimerCount = countCalls(state.calls, "Timer.After")
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 8,
    })
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 9,
    })
    assertEqual(
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout"),
        pointerFlowCount + 2,
        "pointer-stationary tuning applies immediately"
    )
    assertFalse(BD.GetCustomAuraContainerState("buffs").pending,
        "pointer-stationary tuning does not queue")
    assertEqual(countCalls(state.calls, "Timer.After"), pointerTimerCount,
        "pointer-stationary tuning schedules no retry")
    for _, call in ipairs(state.calls) do
        if call.name == "AF.SetCustomAuraContainerFlowLayout" then
            lastFlowCall = call
        end
    end
    assertEqual(lastFlowCall.args[1].marker, 9,
        "pointer-stationary tuning keeps latest settings")

    state.combat = true
    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").unit,
        "vehicle",
        "combat-live vehicle retarget"
    )
    state.combat = false

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        unsupported = true,
    })
    local unsupported = BD.GetCustomAuraContainerState("buffs")
    assertEqual(unsupported.state, "UNSUPPORTED", "unsupported state")
    assertEqual(unsupported.diagnostic, "UNSUPPORTED_TEST_CONFIG",
        "unsupported diagnostic")
    assertFalse(unsupported.active, "unsupported leaves custom inactive")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
    state.suppressEnableSucceeds = false

    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
    })
    local failed = BD.GetCustomAuraContainerState("buffs")
    assertEqual(failed.state, "SUPPRESSION_FAILED",
        "suppression failure state")
    assertFalse(failed.active, "suppression failure custom hidden")
    assertEqual(state.frames[1].shown, false,
        "suppression failure holder hidden")
    assertEqual(state.frames[2].shown, false,
        "suppression failure container hidden")
    assertEqual(
        BD.GetCustomAuraContainerConstructionStats().buildCompletions,
        1,
        "suppression failure retains completed build"
    )
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
    state.failGroupAdd = true

    local ok = pcall(BD.UpdateCustomAuraContainer, "buffs", {
        enabled = true,
    })
    assertFalse(ok, "partial construction propagates deterministic error")
    local partialStats = BD.GetCustomAuraContainerConstructionStats()
    assertEqual(partialStats.buildAttempts, 1, "partial build attempts")
    assertEqual(partialStats.buildCompletions, 0, "partial build completions")
    assertEqual(partialStats.incompleteBuilds, 1, "partial incomplete build")
    assertEqual(partialStats.strandedNativeShells, 1,
        "partial stranded shell")
    assertEqual(partialStats.strandedInitialReservations, 12,
        "partial stranded reservations")

    state.failGroupAdd = false
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
    })
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").state,
        "FAILED",
        "partial build cannot retry"
    )
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        1,
        "partial build performs one allocation"
    )
end

do
    local controllerFile = assert(io.open(
        "Modules/BuffsDebuffs/CustomAuraContainer.lua",
        "r"
    ))
    local controllerSource = controllerFile:read("*a")
    controllerFile:close()
    local nativeFile = assert(io.open(
        "Modules/BuffsDebuffs/NativeAuraFrames.lua",
        "r"
    ))
    local nativeSource = nativeFile:read("*a")
    nativeFile:close()

    for _, symbol in ipairs({
        ":IsMouseOver(",
        "IsControllerHovered",
        "QueueHoverRetry",
        "HOVER_RETRY_SECONDS",
        "hoverRetryScheduled",
        "IsNativePublicAuraFrameHovered",
    }) do
        assertEqual(controllerSource:find(symbol, 1, true), nil,
            "custom controller forbidden hover source " .. symbol)
        assertEqual(nativeSource:find(symbol, 1, true), nil,
            "native suppression forbidden hover source " .. symbol)
    end
end

print("buffs/debuffs custom aura controller tests passed")
