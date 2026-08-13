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

local function countEventCallbackCalls(calls, name, event, callback)
    local count = 0
    for _, call in ipairs(calls) do
        if call.name == name
            and call.args[1] == event
            and call.args[2] == callback
        then
            count = count + 1
        end
    end
    return count
end

local function countCalls(calls, name, startIndex)
    local count = 0
    for index = startIndex or 1, #calls do
        if calls[index].name == name then
            count = count + 1
        end
    end
    return count
end

local function countPlain(source, needle)
    local count = 0
    local offset = 1
    while true do
        local position = source:find(needle, offset, true)
        if not position then return count end
        count = count + 1
        offset = position + #needle
    end
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
        harmfulCanSuppress = true,
        harmfulSuppressSucceeds = true,
        harmfulRestoreSucceeds = true,
        harmfulReassertSucceeds = true,
        suppressEnableSucceeds = true,
        suppressRestoreSucceeds = true,
        timers = {},
        events = {},
        registryCallbacks = {},
        frames = {},
        playerUnit = "player",
        secretValues = {},
        secretUnits = {},
        secretUnitBoundaryCalls = 0,
        secretUnitTypeCalls = 0,
        secretUnitEqualityCalls = 0,
        mutationReadCounts = {},
    }

    local nativeType = type

    local function IsSecretUnit(value)
        for _, secret in ipairs(state.secretUnits) do
            if rawequal(value, secret) then
                return true
            end
        end
        return false
    end

    local function IsSecretValue(value)
        for _, secret in ipairs(state.secretValues) do
            if rawequal(value, secret) then
                return true
            end
        end
        return IsSecretUnit(value)
    end

    function state.newSecretValue(label)
        local secret = setmetatable({label = label}, {
            __index = function()
                error("secret value was observed", 2)
            end,
            __eq = function()
                error("secret value reached equality", 2)
            end,
        })
        state.secretValues[#state.secretValues + 1] = secret
        return secret
    end

    function state.newSecretUnit()
        local secret = setmetatable({}, {
            __eq = function()
                state.secretUnitEqualityCalls =
                    state.secretUnitEqualityCalls + 1
                error("secret unit reached equality", 2)
            end,
        })
        state.secretUnits[#state.secretUnits + 1] = secret
        return secret
    end

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

        function frame:CanBeAccessedInContext()
            record(label .. ".CanBeAccessedInContext")
            state.holderAccessCalls = (state.holderAccessCalls or 0) + 1
            if state.onHolderAccess then
                state.onHolderAccess(frame, state.holderAccessCalls)
            end
            return state.holderAccessResult == nil
                or state.holderAccessResult
        end

        function frame:SetRolesets(rolesets)
            if state.onHolderSetRolesets then
                state.onHolderSetRolesets(frame, rolesets)
            end
            self.rolesets = rolesets
            record(label .. ".SetRolesets", rolesets)
        end

        function frame:ClearAllPoints()
            record(label .. ".ClearAllPoints")
        end

        function frame:SetPoint(...)
            record(label .. ".SetPoint", ...)
        end

        return frame
    end

    local environmentStorage = {}
    local environment = setmetatable({}, {
        __index = function(_, key)
            local value = environmentStorage[key]
            if value ~= nil then return value end
            return _G[key]
        end,
        __newindex = function(_, key, value)
            environmentStorage[key] = value
        end,
    })
    environment._G = environment
    environment.rawget = function(target, key)
        if rawequal(target, environment) then
            local value = environmentStorage[key]
            local mutation = state.globalReadMutations
                and state.globalReadMutations[key]
            if mutation then
                state.mutationReadCounts[key] =
                    (state.mutationReadCounts[key] or 0) + 1
                mutation(
                    environmentStorage,
                    state.mutationReadCounts[key],
                    value
                )
                value = environmentStorage[key]
            end
            return value
        end
        return rawget(target, key)
    end
    environment.type = function(value)
        if IsSecretValue(value) then
            state.secretUnitTypeCalls = state.secretUnitTypeCalls + 1
            error("secret unit reached type", 2)
        end
        return nativeType(value)
    end
    environment.PlayerFrame = setmetatable({}, {
        __index = function(_, key)
            if key == "unit" then return state.playerUnit end
        end,
    })
    environment.InCombatLockdown = function()
        state.combatCalls = (state.combatCalls or 0) + 1
        if state.onCombatCheck then
            state.onCombatCheck(state.combatCalls)
        end
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


    local function NewAccessibleGlobal(label)
        local object = {label = label}
        function object:CanBeAccessedInContext()
            record(label .. ".CanBeAccessedInContext")
            state.globalAccessCalls = state.globalAccessCalls or {}
            state.globalAccessCalls[label] =
                (state.globalAccessCalls[label] or 0) + 1
            if state.onGlobalAccess then
                state.onGlobalAccess(
                    label,
                    object,
                    state.globalAccessCalls[label]
                )
            end
            local result = state.globalAccessResults
                and state.globalAccessResults[label]
            if result ~= nil then return result end
            return true
        end
        return object
    end

    environment.UIParent = NewAccessibleGlobal("UIParent")
    environment.BuffFrame = NewAccessibleGlobal("BuffFrame")
    environment.EditModeManagerFrame =
        NewAccessibleGlobal("EditModeManagerFrame")
    environment.DeadlyDebuffFrame = setmetatable({}, {
        __index = function()
            error("private DeadlyDebuffFrame was observed", 2)
        end,
    })
    environment.PrivateAuraFrame = setmetatable({}, {
        __index = function()
            error("private aura frame alias was observed", 2)
        end,
    })
    environment.auraFrames = setmetatable({}, {
        __index = function()
            error("auraFrames alias was observed", 2)
        end,
    })
    environment.EventRegistry = {}
    function environment.EventRegistry:RegisterCallback(event, callback, owner)
        state.registryCallbacks[event] =
            state.registryCallbacks[event] or {}
        state.registryCallbacks[event][
            #state.registryCallbacks[event] + 1
        ] = {
            callback = callback,
            owner = owner,
        }
        record("EventRegistry.RegisterCallback", event, callback, owner)
    end

    local AF = {
        UIParent = environment.UIParent,
    }
    function AF.Copy(value)
        local copy = deepCopy(value)
        if type(copy) == "table" and copy.nativeFollower ~= nil then
            state.lastDescriptorCopy = copy
        end
        return copy
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
            if state.onSuppressEnable then state.onSuppressEnable() end
            return state.suppressEnableSucceeds
        end
        if state.onSuppressRestore then state.onSuppressRestore() end
        return state.suppressRestoreSucceeds
    end
    function BD.CanSuppressNativeHarmfulAuras()
        record("BD.CanSuppressNativeHarmfulAuras")
        return state.harmfulCanSuppress
    end
    function BD.SetNativeHarmfulAurasSuppressed(suppressed, unit)
        record(
            "BD.SetNativeHarmfulAurasSuppressed",
            suppressed,
            unit
        )
        if suppressed then
            if state.onHarmfulSuppress then state.onHarmfulSuppress() end
            return state.harmfulSuppressSucceeds
        end
        if state.onHarmfulRestore then state.onHarmfulRestore(unit) end
        return state.harmfulRestoreSucceeds
    end
    function BD.ReassertNativeHarmfulAuraSuppression()
        record("BD.ReassertNativeHarmfulAuraSuppression")
        if state.onHarmfulReassert then state.onHarmfulReassert() end
        return state.harmfulReassertSucceeds
    end
    function BD.UpdateBlizzardDebuffStyle()
        error("#127 must not call the #103 style adapter", 2)
    end
    function BD.DisableBlizzardDebuffStyle()
        error("#127 must not call the #103 style adapter", 2)
    end

    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = L,
        funcs = {
            isValueNonSecret = function(value)
                state.secretUnitBoundaryCalls =
                    state.secretUnitBoundaryCalls + 1
                return not IsSecretValue(value)
            end,
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

    function state.newDebuffFrame(options)
        options = options or {}
        local frame = {
            scale = options.scale == nil and 2 or options.scale,
            systemInfo = options.systemInfo or {
                anchorInfo = {
                    point = "TOPRIGHT",
                    relativeTo = "UIParent",
                    relativePoint = "TOPRIGHT",
                    offsetX = -31,
                    offsetY = -42,
                },
                anchorInfo2 = {
                    point = "BOTTOMRIGHT",
                    relativeTo = "BuffFrame",
                    relativePoint = "BOTTOMRIGHT",
                    offsetX = -7,
                    offsetY = 9,
                },
            },
        }

        function frame:CanBeAccessedInContext()
            record("DebuffFrame.CanBeAccessedInContext")
            state.nativeAccessCalls = (state.nativeAccessCalls or 0) + 1
            if state.onNativeAccess then
                state.onNativeAccess(frame, state.nativeAccessCalls)
            end
            if state.nativeAccessResult ~= nil then
                return state.nativeAccessResult
            end
            local globalResult = state.globalAccessResults
                and state.globalAccessResults.DebuffFrame
            if globalResult ~= nil then return globalResult end
            return true
        end
        function frame:GetScale()
            record("DebuffFrame.GetScale")
            state.nativeScaleCalls = (state.nativeScaleCalls or 0) + 1
            if state.onNativeScale then
                state.onNativeScale(frame, state.nativeScaleCalls)
            end
            return frame.scale
        end
        function frame:ClearAllPointsBase()
            record("DebuffFrame.ClearAllPointsBase")
        end
        function frame:SetPointBase(...)
            record("DebuffFrame.SetPointBase", ...)
        end
        function frame:ClearAllPoints()
            error("follower must use Blizzard's captured base clearer", 2)
        end
        function frame:SetPoint()
            error("follower must use Blizzard's captured base setter", 2)
        end
        function frame:GetPoint()
            error("follower must not read DebuffFrame geometry", 2)
        end
        function frame:GetSize()
            error("follower must not read DebuffFrame size", 2)
        end
        function frame:IsShown()
            error("follower must not read DebuffFrame visibility", 2)
        end
        return frame
    end

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

    function state.fireEvent(event, ...)
        local callbacks = {}
        for callback in pairs(state.events[event] or {}) do
            callbacks[#callbacks + 1] = callback
        end
        for _, callback in ipairs(callbacks) do
            callback(event, ...)
        end
    end

    function state.fireRegistry(event, ...)
        for _, registration in ipairs(
            state.registryCallbacks[event] or {}
        ) do
            if registration.owner ~= nil then
                registration.callback(registration.owner, ...)
            else
                registration.callback(...)
            end
        end
    end

    return {
        AF = AF,
        BD = BD,
        environment = environment,
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

local function CompileFollowingBuffs(config)
    local descriptor, diagnostic = CompileBuffs(config)
    if not descriptor then return nil, diagnostic end
    descriptor.holderRolesets = "buffs"
    descriptor.nativeFollower = {
        globalName = "DebuffFrame",
        point = "TOPRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = -5,
    }
    descriptor.containerPoint = {
        point = "BOTTOMRIGHT",
        relativePoint = "BOTTOMRIGHT",
        x = 0,
        y = 0,
    }
    return descriptor
end

local function CompileHarmful(config)
    if config.unsupported then
        return nil, "UNSUPPORTED_TEST_CONFIG"
    end

    local descriptor = CompileBuffs(config)
    descriptor.holderRolesets = "buffs"
    descriptor.holderAnchor = {
        globalName = "DebuffFrame",
        point = "TOPRIGHT",
        relativePoint = "TOPRIGHT",
        x = 0,
        y = 0,
    }
    descriptor.nativeSuppression = "harmful"
    descriptor.position = nil
    descriptor.positionSave = nil
    descriptor.moverText = nil
    descriptor.itemEnchantments = {}
    descriptor.itemEnchantmentSort = nil
    descriptor.itemEnchantmentLayout = nil
    descriptor.groups[1].key = "harmful"
    descriptor.groups[1].filterString = "HARMFUL"
    descriptor.groups[1].maxFrameCount = config.maximum or 25
    return descriptor
end

for _, callbackOrder in ipairs({
    {
        name = "unit refresh before lifecycle invalidation",
        unitFirst = true,
    },
    {
        name = "lifecycle invalidation before unit refresh",
        unitFirst = false,
    },
}) do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    local unitRefresh = BD.RefreshCustomAuraContainerUnits
    local lifecycleInvalidation
    local callbackCount = 0
    for callback in pairs(state.events.PLAYER_ENTERING_WORLD or {}) do
        callbackCount = callbackCount + 1
        if callback ~= unitRefresh then
            lifecycleInvalidation = callback
        end
    end
    assertEqual(callbackCount, 2,
        callbackOrder.name .. " has exactly two event callbacks")
    assertTrue(type(lifecycleInvalidation) == "function",
        callbackOrder.name .. " finds lifecycle invalidation callback")

    state.playerUnit = "vehicle"
    local eventStart = #state.calls + 1
    if callbackOrder.unitFirst then
        unitRefresh("PLAYER_ENTERING_WORLD")
        lifecycleInvalidation("PLAYER_ENTERING_WORLD")
    else
        lifecycleInvalidation("PLAYER_ENTERING_WORLD")
        unitRefresh("PLAYER_ENTERING_WORLD")
    end

    local retargeted = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(retargeted.unit, "vehicle",
        callbackOrder.name .. " retargets custom row immediately")
    assertTrue(retargeted.active,
        callbackOrder.name .. " keeps custom row active")
    assertEqual(countCalls(
        state.calls,
        "AF.SetCustomAuraContainerUnit",
        eventStart
    ), 1, callbackOrder.name .. " performs one immediate custom SetUnit")
    assertEqual(countCalls(
        state.calls,
        "AF.UpdateCustomAuraContainer",
        eventStart
    ), 1, callbackOrder.name .. " performs one immediate custom update")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        eventStart
    ), 0, callbackOrder.name .. " defers the native reassert")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        eventStart
    ), 0, callbackOrder.name .. " starts no duplicate setter transaction")

    state.runTimers(0)
    state.runTimers(0)
    local recovered = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(recovered.unit, "vehicle",
        callbackOrder.name .. " retains vehicle after recovery")
    assertFalse(recovered.harmfulReassertPending,
        callbackOrder.name .. " consumes the coalesced reassert intent")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        eventStart
    ), 1, callbackOrder.name .. " performs exactly one deferred reassert")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        eventStart
    ), 0, callbackOrder.name .. " never duplicates native suppression")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 1,
    })

    state.harmfulSuppressSucceeds = false
    state.harmfulRestoreSucceeds = false
    local failureStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 2,
    })
    local retained = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(retained.active,
        "active revalidation failure keeps custom harmful visible")
    assertTrue(retained.operationPending,
        "active revalidation failure queues harmful retry ownership")
    assertFalse(retained.nativeFollowerActive,
        "active harmful retry never claims native follower ownership")
    assertTrue(state.frames[1].shown and state.frames[2].shown,
        "active revalidation failure leaves the replacement visible")
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        failureStart
    ), nil, "active harmful failure performs no follower writes")

    state.harmfulSuppressSucceeds = true
    state.harmfulRestoreSucceeds = true
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(repaired.active,
        "later harmful revalidation repair remains visible")
    assertFalse(repaired.operationPending,
        "later harmful revalidation repair clears retry ownership")
    assertEqual(repaired.state, "ACTIVE",
        "later harmful revalidation repair restores active state")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local initialSecret = state.newSecretUnit()
    state.playerUnit = initialSecret

    BD.RegisterCustomAuraContainerPane("buffs", CompileBuffs)
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
    })
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").unit,
        "player",
        "secret initial unit falls back before native construction"
    )

    state.combat = true
    local invalidUnits = {
        {label = "empty", value = ""},
        {label = "arbitrary", value = "party1"},
        {label = "table", value = {}},
        {label = "false", value = false},
        {label = "number", value = 1},
        {label = "nil"},
    }
    for _, invalid in ipairs(invalidUnits) do
        state.playerUnit = "vehicle"
        BD.RefreshCustomAuraContainerUnits()
        assertEqual(
            BD.GetCustomAuraContainerState("buffs").unit,
            "vehicle",
            invalid.label .. " setup accepts vehicle"
        )

        state.playerUnit = invalid.value
        BD.RefreshCustomAuraContainerUnits()
        local controllerState = BD.GetCustomAuraContainerState("buffs")
        assertEqual(controllerState.unit, "player",
            invalid.label .. " unit falls back to player")
        assertFalse(controllerState.pending,
            invalid.label .. " combat retarget needs no regen queue")
    end

    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    local refreshSecret = state.newSecretUnit()
    state.playerUnit = refreshSecret
    BD.RefreshCustomAuraContainerUnits()
    assertEqual(
        BD.GetCustomAuraContainerState("buffs").unit,
        "player",
        "secret combat unit falls back immediately"
    )
    assertFalse(
        BD.GetCustomAuraContainerState("buffs").pending,
        "secret combat fallback needs no regen queue"
    )
    assertEqual(state.secretUnitTypeCalls, 0,
        "secret unit is gated before type")
    assertEqual(state.secretUnitEqualityCalls, 0,
        "secret unit is gated before equality")
    assertTrue(state.secretUnitBoundaryCalls > 0,
        "unit values pass through the canonical boundary")

    for _, call in ipairs(state.calls) do
        for _, argument in ipairs(call.args) do
            assertFalse(
                rawequal(argument, initialSecret)
                    or rawequal(argument, refreshSecret),
                "raw secret unit never escapes to AF or event calls"
            )
        end
    end
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
        countEventCallbackCalls(
            state.calls,
            "BD.RegisterEvent",
            "PLAYER_REGEN_ENABLED",
            BD.FlushCustomAuraContainerUpdates
        ),
        1,
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
    local createsBeforeCombat =
        countCalls(state.calls, "AF.CreateCustomAuraContainer")
    local unitWritesBeforeCombat =
        countCalls(state.calls, "AF.SetCustomAuraContainerUnit")
    local updatesBeforeCombat =
        countCalls(state.calls, "AF.UpdateCustomAuraContainer")
    local timersBeforeCombat = countCalls(state.calls, "Timer.After")
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
        countEventCallbackCalls(
            state.calls,
            "BD.RegisterEvent",
            "PLAYER_REGEN_ENABLED",
            BD.FlushCustomAuraContainerUpdates
        ),
        1,
        "combat queue has one controller regen registration"
    )

    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    local retargetedPendingState =
        BD.GetCustomAuraContainerState("buffs")
    assertEqual(retargetedPendingState.unit, "vehicle",
        "queued tuning does not defer combat-live retarget")
    assertTrue(retargetedPendingState.pending,
        "combat-live retarget preserves queued tuning")
    assertEqual(
        countCalls(state.calls, "AF.SetCustomAuraContainerUnit"),
        unitWritesBeforeCombat + 1,
        "queued tuning retarget writes unit immediately"
    )
    assertEqual(
        countCalls(state.calls, "AF.UpdateCustomAuraContainer"),
        updatesBeforeCombat + 1,
        "queued tuning retarget refreshes native container immediately"
    )
    assertEqual(
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout"),
        flowCallsBeforeCombat,
        "combat-live retarget does not apply queued tuning"
    )
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeCombat,
        "combat-live retarget does not rebuild"
    )
    assertEqual(countCalls(state.calls, "Timer.After"), timersBeforeCombat,
        "combat-live retarget does not add a retry timer")

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
    assertEqual(
        countCalls(state.calls, "AF.SetCustomAuraContainerFlowLayout"),
        flowCallsBeforeCombat + 1,
        "regen applies exactly one queued tuning pass"
    )
    assertEqual(lastFlowCall.args[1].marker, 7,
        "combat queue keeps latest tuning")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        createsBeforeCombat,
        "regen tuning reuses the existing container"
    )
    assertEqual(countCalls(state.calls, "Timer.After"), timersBeforeCombat + 1,
        "regen schedules one deferred tuning callback")

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
    local environment = harness.environment
    local debuffFrame = state.newDebuffFrame()
    environment.DebuffFrame = debuffFrame
    environment.EditModeManagerFrame.editModeActive = nil

    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    local buildStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local active = BD.GetCustomAuraContainerState("buffs")
    assertTrue(active.active, "fresh-login nil Edit Mode state activates")
    assertTrue(active.nativeFollowerActive,
        "fresh-login nil Edit Mode state attaches the follower")
    assertEqual(state.frames[1].rolesets, "buffs",
        "holder receives the shared buffs roleset")
    local _, rolesetIndex = findCall(
        state.calls,
        "holder1.SetRolesets",
        buildStart
    )
    local _, moverIndex = findCall(
        state.calls,
        "AF.CreateMover",
        buildStart
    )
    assertTrue(rolesetIndex < moverIndex,
        "roleset is assigned before mover publication")
    local attachCall = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        buildStart
    )
    assertEqual(attachCall.args[1], "TOPRIGHT", "follower point")
    assertEqual(attachCall.args[2], state.frames[1],
        "follower uses the BFI holder identity")
    assertEqual(attachCall.args[3], "BOTTOMRIGHT",
        "follower relative point")
    assertEqual(attachCall.args[4], 0, "follower native-unit X")
    assertEqual(attachCall.args[5], -5, "follower native-unit Y")

    local disableStart = #state.calls + 1
    BD.DisableCustomAuraContainer("buffs")
    local disabled = BD.GetCustomAuraContainerState("buffs")
    assertFalse(disabled.active, "disable hides custom Buffs")
    assertFalse(disabled.nativeFollowerActive,
        "disable releases Blizzard Debuffs")
    local restoreFirst, restoreFirstIndex = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        disableStart
    )
    assertEqual(restoreFirst.args[1], "TOPRIGHT", "first restore point")
    assertEqual(restoreFirst.args[2], environment.UIParent,
        "UIParent alias resolves to the exact object")
    assertEqual(restoreFirst.args[3], "TOPRIGHT",
        "first restore relative point")
    assertEqual(restoreFirst.args[4], -15.5,
        "first restore X converts physical offset by scale")
    assertEqual(restoreFirst.args[5], -21,
        "first restore Y converts physical offset by scale")
    local restoreSecond = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        restoreFirstIndex + 1
    )
    assertTrue(restoreSecond ~= nil,
        "optional second native anchor is restored atomically")
    assertEqual(restoreSecond.args[2], environment.BuffFrame,
        "BuffFrame alias resolves to the exact object")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    local frame = state.newDebuffFrame()
    environment.DebuffFrame = frame
    environment.EditModeManagerFrame.editModeActive = false

    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local active = BD.GetCustomAuraContainerState("buffs")
    assertTrue(active.active,
        "explicit false Edit Mode state activates")
    assertTrue(active.nativeFollowerActive,
        "explicit false Edit Mode state attaches the follower")
end

do
    for _, point in ipairs({
        "BOTTOM",
        "BOTTOMLEFT",
        "BOTTOMRIGHT",
        "CENTER",
        "LEFT",
        "RIGHT",
        "TOP",
        "TOPLEFT",
        "TOPRIGHT",
    }) do
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        local frame = state.newDebuffFrame()
        frame.systemInfo.anchorInfo.point = point
        frame.systemInfo.anchorInfo.relativePoint = point
        frame.systemInfo.anchorInfo2 = nil
        environment.DebuffFrame = frame

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        BD.UpdateCustomAuraContainer("buffs", {enabled = true})
        local disableStart = #state.calls + 1
        BD.DisableCustomAuraContainer("buffs")
        local restore = findCall(
            state.calls,
            "DebuffFrame.SetPointBase",
            disableStart
        )
        assertEqual(restore.args[1], point,
            point .. " is accepted as a native restore point")
        assertEqual(restore.args[3], point,
            point .. " is accepted as a native relative point")
    end
end

do
    local function RunRolesetFailure(label, configure)
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        configure(state)

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        local buildStart = #state.calls + 1
        local ok = pcall(BD.UpdateCustomAuraContainer, "buffs", {
            enabled = true,
        })
        assertTrue(ok, label .. " fails closed without Lua error")
        assertEqual(findCall(
            state.calls,
            "holder1.SetRolesets",
            buildStart
        ), nil, label .. " performs zero SetRolesets calls")
        assertEqual(findCall(
            state.calls,
            "AF.CreateMover",
            buildStart
        ), nil, label .. " publishes no mover")
        assertEqual(findCall(
            state.calls,
            "AF.CreateCustomAuraContainer",
            buildStart
        ), nil, label .. " allocates no container")
        local result = BD.GetCustomAuraContainerState("buffs")
        assertFalse(result.buildAttempted,
            label .. " publishes no completed holder construction")
    end

    for _, case in ipairs({
        {
            label = "false holder access",
            configure = function(state)
                state.holderAccessResult = false
            end,
        },
        {
            label = "nonboolean holder access",
            configure = function(state)
                state.holderAccessResult = {}
            end,
        },
        {
            label = "secret holder access",
            configure = function(state)
                state.holderAccessResult =
                    state.newSecretValue("roleset holder access")
            end,
        },
        {
            label = "missing SetRolesets",
            configure = function(state)
                state.onHolderAccess = function(holder, count)
                    if count == 1 then holder.SetRolesets = nil end
                end
            end,
        },
        {
            label = "secret SetRolesets",
            configure = function(state)
                state.onHolderAccess = function(holder, count)
                    if count == 1 then
                        holder.SetRolesets =
                            state.newSecretValue("SetRolesets")
                    end
                end
            end,
        },
        {
            label = "drifted SetRolesets",
            configure = function(state)
                state.onHolderAccess = function(holder, count)
                    if count == 2 then
                        holder.SetRolesets = function()
                            error("drifted SetRolesets executed", 2)
                        end
                    end
                end
            end,
        },
        {
            label = "roleset final combat flip",
            configure = function(state)
                state.onCombatCheck = function(count)
                    if count == 2 then state.combat = true end
                end
            end,
        },
    }) do
        RunRolesetFailure(case.label, case.configure)
    end
end

do
    local function RunRolesetRetry(label, configure, recover)
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        environment.DebuffFrame = state.newDebuffFrame()
        configure(state)

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        BD.UpdateCustomAuraContainer("buffs", {enabled = true})
        assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
            label .. " allocates one retained pending holder")
        assertEqual(countCalls(state.calls, "holder1.SetRolesets"), 0,
            label .. " performs no failed roleset write")
        assertEqual(countCalls(state.calls, "AF.CreateMover"), 0,
            label .. " publishes no mover while roleset is pending")
        assertEqual(countCalls(
            state.calls,
            "AF.CreateCustomAuraContainer"
        ), 0, label .. " allocates no native container while pending")

        recover(state, state.frames[1])
        BD.UpdateCustomAuraContainer("buffs", {enabled = true})
        assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
            label .. " reuses the retained pending holder")
        assertEqual(countCalls(state.calls, "holder1.SetRolesets"), 1,
            label .. " applies rolesets once after recovery")
        assertEqual(countCalls(state.calls, "AF.CreateMover"), 1,
            label .. " publishes one mover after roleset success")
        assertEqual(countCalls(
            state.calls,
            "AF.CreateCustomAuraContainer"
        ), 1, label .. " allocates one container after roleset success")
        local result = BD.GetCustomAuraContainerState("buffs")
        assertTrue(result.buildCompleted,
            label .. " completes construction after recovery")
        assertTrue(result.active,
            label .. " activates the recovered single holder")
    end

    RunRolesetRetry(
        "holder access retry",
        function(state)
            state.holderAccessResult = false
        end,
        function(state)
            state.holderAccessResult = nil
        end
    )

    RunRolesetRetry(
        "holder method retry",
        function(state)
            state.onHolderAccess = function(holder, count)
                if count == 1 then
                    state.savedSetRolesets = holder.SetRolesets
                    holder.SetRolesets = nil
                end
            end
        end,
        function(state, holder)
            holder.SetRolesets = state.savedSetRolesets
            state.onHolderAccess = nil
        end
    )

    RunRolesetRetry(
        "holder final combat retry",
        function(state)
            state.onCombatCheck = function(count)
                if count == 2 then state.combat = true end
            end
        end,
        function(state)
            state.combat = false
            state.onCombatCheck = nil
        end
    )

    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)

    state.holderAccessResult = false
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
        "repeated roleset failures allocate the pending holder once")

    state.holderAccessResult = nil
    state.onHolderAccess = function(holder, count)
        if count == 2 then
            state.savedSetRolesets = holder.SetRolesets
            holder.SetRolesets = nil
        end
    end
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
        "method failure reuses the same pending holder")

    state.frames[1].SetRolesets = state.savedSetRolesets
    state.onHolderAccess = nil
    state.onCombatCheck = function(count)
        if count == 4 then state.combat = true end
    end
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
        "final-combat failure reuses the same pending holder")
    assertEqual(countCalls(state.calls, "holder1.SetRolesets"), 0,
        "all repeated failures perform zero roleset writes")
    assertEqual(countCalls(state.calls, "AF.CreateMover"), 0,
        "all repeated failures publish zero movers")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), 0, "all repeated failures allocate zero native containers")

    state.combat = false
    state.onCombatCheck = nil
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
        "recovery still uses the one retained pending holder")
    assertEqual(countCalls(state.calls, "holder1.SetRolesets"), 1,
        "recovery applies rolesets once")
    local moverCall = findCall(state.calls, "AF.CreateMover")
    local containerCall = findCall(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )
    assertEqual(moverCall.args[1], "holder1",
        "mover publishes the retained holder")
    assertEqual(containerCall.args[1], "holder1",
        "native container uses the retained holder")
    assertTrue(BD.GetCustomAuraContainerState("buffs").active,
        "repeated-failure holder activates after recovery")
end

do
    local function RunFollowerFailure(label, configure)
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        local debuffFrame = state.newDebuffFrame()
        environment.DebuffFrame = debuffFrame
        configure(state, environment, debuffFrame)

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        local writeStart = #state.calls + 1
        local ok = pcall(BD.UpdateCustomAuraContainer, "buffs", {
            enabled = true,
        })
        assertTrue(ok, label .. " fails closed without Lua error")
        local result = BD.GetCustomAuraContainerState("buffs")
        assertFalse(result.nativeFollowerActive,
            label .. " never claims native follower ownership")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), nil, label .. " performs zero native anchor writes")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.SetPointBase",
            writeStart
        ), nil, label .. " performs zero native point writes")
    end

    for _, case in ipairs({
        {
            label = "unknown restore alias",
            configure = function(_, _, frame)
                frame.systemInfo.anchorInfo.relativeTo = "WorldFrame"
            end,
        },
        {
            label = "secret restore alias",
            configure = function(state, environment, frame)
                environment.UIParent = state.newSecretValue("UIParent")
                frame.systemInfo.anchorInfo.relativeTo = "UIParent"
            end,
        },
        {
            label = "invalid restore point token",
            configure = function(_, _, frame)
                frame.systemInfo.anchorInfo.point = "ALL"
            end,
        },
        {
            label = "invalid restore relative point token",
            configure = function(_, _, frame)
                frame.systemInfo.anchorInfo.relativePoint = "ALL"
            end,
        },
        {
            label = "zero scale",
            configure = function(_, _, frame) frame.scale = 0 end,
        },
        {
            label = "NaN scale",
            configure = function(_, _, frame) frame.scale = 0 / 0 end,
        },
        {
            label = "infinite scale",
            configure = function(_, _, frame) frame.scale = math.huge end,
        },
        {
            label = "division overflow",
            configure = function(_, _, frame)
                frame.scale = 1e-320
                frame.systemInfo.anchorInfo.offsetX = 1e308
            end,
        },
        {
            label = "malformed optional second point",
            configure = function(_, _, frame)
                frame.systemInfo.anchorInfo2.relativeTo = "WorldFrame"
            end,
        },
        {
            label = "active Edit Mode",
            configure = function(_, environment)
                environment.EditModeManagerFrame.editModeActive = true
            end,
        },
        {
            label = "hostile Edit Mode state",
            configure = function(_, environment)
                environment.EditModeManagerFrame.editModeActive = {}
            end,
        },
        {
            label = "secret Edit Mode state",
            configure = function(state, environment)
                environment.EditModeManagerFrame.editModeActive =
                    state.newSecretValue("editModeActive")
            end,
        },
        {
            label = "false relative access result",
            configure = function(state)
                state.globalAccessResults = {UIParent = false}
            end,
        },
        {
            label = "nonboolean relative access result",
            configure = function(state)
                state.globalAccessResults = {UIParent = {}}
            end,
        },
        {
            label = "secret relative access result",
            configure = function(state)
                state.globalAccessResults = {
                    UIParent = state.newSecretValue("UIParent access"),
                }
            end,
        },
        {
            label = "false holder access result",
            configure = function(state)
                state.holderAccessResult = false
            end,
        },
        {
            label = "nonboolean holder access result",
            configure = function(state)
                state.holderAccessResult = {}
            end,
        },
        {
            label = "secret holder access result",
            configure = function(state)
                state.holderAccessResult =
                    state.newSecretValue("holder access")
            end,
        },
        {
            label = "false Edit Mode access result",
            configure = function(state)
                state.globalAccessResults = {
                    EditModeManagerFrame = false,
                }
            end,
        },
        {
            label = "nonboolean Edit Mode access result",
            configure = function(state)
                state.globalAccessResults = {
                    EditModeManagerFrame = {},
                }
            end,
        },
        {
            label = "secret Edit Mode access result",
            configure = function(state)
                state.globalAccessResults = {
                    EditModeManagerFrame = state.newSecretValue(
                        "Edit Mode access"
                    ),
                }
            end,
        },
    }) do
        RunFollowerFailure(case.label, case.configure)
    end
end

do
    local function RunLateSecretApply(label, install)
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        local frame = state.newDebuffFrame()
        environment.DebuffFrame = frame

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        local writeStart = #state.calls + 1
        install(state, environment, frame)
        local ok = pcall(BD.UpdateCustomAuraContainer, "buffs", {
            enabled = true,
        })
        assertTrue(ok, label .. " fails closed without Lua error")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), nil, label .. " performs zero native clears")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.SetPointBase",
            writeStart
        ), nil, label .. " performs zero native point writes")
        assertFalse(BD.GetCustomAuraContainerState("buffs").nativeFollowerActive,
            label .. " publishes no follower ownership")
    end

    local targetFields = {
        "CanBeAccessedInContext",
        "GetScale",
        "ClearAllPointsBase",
        "SetPointBase",
        "systemInfo",
    }
    for _, field in ipairs(targetFields) do
        RunLateSecretApply("late-secret target " .. field,
            function(state, _, frame)
                state.onHolderAccess = function(_, count)
                    if count == 2 then
                        frame[field] = state.newSecretValue(field)
                    end
                end
            end)
    end

    local anchorFields = {
        "point",
        "relativeTo",
        "relativePoint",
        "offsetX",
        "offsetY",
    }
    for _, field in ipairs(anchorFields) do
        RunLateSecretApply("late-secret anchor " .. field,
            function(state, _, frame)
                state.onHolderAccess = function(_, count)
                    if count == 2 then
                        frame.systemInfo.anchorInfo[field] =
                            state.newSecretValue(field)
                    end
                end
            end)
    end

    for _, field in ipairs(anchorFields) do
        RunLateSecretApply("late-secret second anchor " .. field,
            function(state, _, frame)
                state.onHolderAccess = function(_, count)
                    if count == 2 then
                        frame.systemInfo.anchorInfo2[field] =
                            state.newSecretValue("anchorInfo2 " .. field)
                    end
                end
            end)
    end

    RunLateSecretApply("late-secret anchorInfo2",
        function(state, _, frame)
            state.onHolderAccess = function(_, count)
                if count == 2 then
                    frame.systemInfo.anchorInfo2 =
                        state.newSecretValue("anchorInfo2")
                end
            end
        end)

    RunLateSecretApply("late-secret DebuffFrame global",
        function(state)
            state.globalReadMutations = {
                DebuffFrame = function(storage, count)
                    if count == 3 then
                        storage.DebuffFrame =
                            state.newSecretValue("DebuffFrame")
                    end
                end,
            }
        end)

    RunLateSecretApply("late-secret relative global",
        function(state)
            state.globalReadMutations = {
                UIParent = function(storage, count)
                    if count == 3 then
                        storage.UIParent =
                            state.newSecretValue("UIParent global")
                    end
                end,
            }
        end)

    RunLateSecretApply("late-secret relative access method",
        function(state, environment)
            state.onHolderAccess = function(_, count)
                if count == 2 then
                    environment.UIParent.CanBeAccessedInContext =
                        state.newSecretValue("UIParent access method")
                end
            end
        end)

    RunLateSecretApply("late-secret holder access method",
        function(state)
            state.onHolderAccess = function(holder, count)
                if count == 2 then
                    holder.CanBeAccessedInContext =
                        state.newSecretValue("holder access method")
                end
            end
        end)

    RunLateSecretApply("late-secret Edit Mode manager global",
        function(state)
            state.globalReadMutations = {
                EditModeManagerFrame = function(storage, count)
                    if count == 3 then
                        storage.EditModeManagerFrame = state.newSecretValue(
                            "EditModeManagerFrame"
                        )
                    end
                end,
            }
        end)

    RunLateSecretApply("late-secret Edit Mode access method",
        function(state, environment)
            state.onHolderAccess = function(_, count)
                if count == 2 then
                    environment.EditModeManagerFrame
                        .CanBeAccessedInContext = state.newSecretValue(
                            "Edit Mode access method"
                        )
                end
            end
        end)

    RunLateSecretApply("late-secret Edit Mode state",
        function(state, environment)
            state.onHolderAccess = function(_, count)
                if count == 2 then
                    environment.EditModeManagerFrame.editModeActive =
                        state.newSecretValue("editModeActive")
                end
            end
        end)

    for _, field in ipairs({
        "globalName",
        "point",
        "relativePoint",
        "x",
        "y",
    }) do
        RunLateSecretApply("late-secret follower " .. field,
            function(state)
                state.onHolderAccess = function(_, count)
                    if count == 2 then
                        state.lastDescriptorCopy.nativeFollower[field] =
                            state.newSecretValue("follower " .. field)
                    end
                end
            end)
    end
end

do
    local function RunLateSecretRestore(label, mutate)
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        local frame = state.newDebuffFrame()
        environment.DebuffFrame = frame

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        BD.UpdateCustomAuraContainer("buffs", {enabled = true})
        state.globalAccessCalls = {}
        local secret = state.newSecretValue(label)
        local repair
        local allocations = countCalls(
            state.calls,
            "AF.CreateCustomAuraContainer"
        )
        state.onGlobalAccess = function(globalName, _, count)
            if globalName == "BuffFrame" and count == 3 then
                repair = mutate(state, environment, frame, secret)
            end
        end

        local writeStart = #state.calls + 1
        local ok = pcall(BD.DisableCustomAuraContainer, "buffs")
        assertTrue(ok, label .. " restore fails closed without Lua error")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), nil, label .. " restore performs zero native clears")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.SetPointBase",
            writeStart
        ), nil, label .. " restore performs zero native point writes")
        local retained = BD.GetCustomAuraContainerState("buffs")
        assertTrue(retained.active,
            label .. " restore retains the active presentation")
        assertTrue(retained.nativeFollowerActive,
            label .. " restore retains follower ownership")
        assertTrue(retained.operationPending,
            label .. " restore keeps disable queued")

        state.onGlobalAccess = nil
        assertTrue(type(repair) == "function",
            label .. " reached the terminal restore fence")
        repair()
        state.fireEvent("PLAYER_REGEN_ENABLED")
        state.runTimers(0)
        local repaired = BD.GetCustomAuraContainerState("buffs")
        assertFalse(repaired.active,
            label .. " repairs to an inactive custom presentation")
        assertFalse(repaired.nativeFollowerActive,
            label .. " repairs exact native follower ownership")
        assertFalse(repaired.operationPending,
            label .. " drains the queued disable after repair")
        assertEqual(countCalls(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), 1, label .. " repairs with one exact native clear")
        assertEqual(countCalls(
            state.calls,
            "DebuffFrame.SetPointBase",
            writeStart
        ), 2, label .. " repairs the exact saved two-point anchor")
        assertEqual(countCalls(
            state.calls,
            "AF.CreateCustomAuraContainer"
        ), allocations, label .. " repair allocates no replacement container")
    end

    for _, field in ipairs({
        "CanBeAccessedInContext",
        "GetScale",
        "ClearAllPointsBase",
        "SetPointBase",
        "systemInfo",
    }) do
        RunLateSecretRestore("late-secret restore target " .. field,
            function(_, _, frame, secret)
                local original = frame[field]
                frame[field] = secret
                return function() frame[field] = original end
            end)
    end

    RunLateSecretRestore("late-secret restore DebuffFrame global",
        function(_, environment, _, secret)
            local original = environment.DebuffFrame
            environment.DebuffFrame = secret
            return function() environment.DebuffFrame = original end
        end)
    RunLateSecretRestore("late-secret restore anchorInfo2",
        function(_, _, frame, secret)
            local original = frame.systemInfo.anchorInfo2
            frame.systemInfo.anchorInfo2 = secret
            return function()
                frame.systemInfo.anchorInfo2 = original
            end
        end)

    for _, anchorName in ipairs({"anchorInfo", "anchorInfo2"}) do
        for _, field in ipairs({
            "point",
            "relativeTo",
            "relativePoint",
            "offsetX",
            "offsetY",
        }) do
            RunLateSecretRestore(
                "late-secret restore " .. anchorName .. " " .. field,
                function(_, _, frame, secret)
                    local original = frame.systemInfo[anchorName][field]
                    frame.systemInfo[anchorName][field] = secret
                    return function()
                        frame.systemInfo[anchorName][field] = original
                    end
                end
            )
        end
    end

    RunLateSecretRestore("late-secret restore relative global",
        function(_, environment, _, secret)
            local original = environment.UIParent
            environment.UIParent = secret
            return function() environment.UIParent = original end
        end)
    RunLateSecretRestore("late-secret restore relative access method",
        function(_, environment, _, secret)
            local original = environment.UIParent.CanBeAccessedInContext
            environment.UIParent.CanBeAccessedInContext = secret
            return function()
                environment.UIParent.CanBeAccessedInContext = original
            end
        end)
end

do
    local driftCases = {
        {
            label = "target identity drift",
            configure = function(state, environment)
                state.onNativeScale = function(_, count)
                    if count == 1 then
                        environment.DebuffFrame = state.newDebuffFrame()
                    end
                end
            end,
        },
        {
            label = "systemInfo identity drift",
            configure = function(state, _, frame)
                state.onNativeScale = function(_, count)
                    if count == 1 then
                        frame.systemInfo = deepCopy(frame.systemInfo)
                    end
                end
            end,
        },
        {
            label = "anchor identity drift",
            configure = function(state, _, frame)
                state.onGlobalAccess = function(label, _, count)
                    if label == "UIParent" and count == 1 then
                        frame.systemInfo.anchorInfo =
                            deepCopy(frame.systemInfo.anchorInfo)
                    end
                end
            end,
        },
        {
            label = "captured writer drift",
            configure = function(state, _, frame)
                state.onNativeScale = function(_, count)
                    if count == 1 then
                        frame.SetPointBase = function()
                            error("drifted writer must never execute", 2)
                        end
                    end
                end
            end,
        },
        {
            label = "relative global drift",
            configure = function(state, environment)
                state.onGlobalAccess = function(label, _, count)
                    if label == "UIParent" and count == 1 then
                        environment.UIParent = {
                            CanBeAccessedInContext = function() return true end,
                        }
                    end
                end
            end,
        },
        {
            label = "holder access-method drift",
            configure = function(state)
                state.onHolderAccess = function(holder, count)
                    if count == 1 then
                        holder.CanBeAccessedInContext = function()
                            return true
                        end
                    end
                end
            end,
        },
        {
            label = "Edit Mode manager drift",
            configure = function(state, environment)
                state.onGlobalAccess = function(label, _, count)
                    if label == "EditModeManagerFrame" and count == 1 then
                        environment.EditModeManagerFrame = {
                            editModeActive = false,
                            CanBeAccessedInContext = function() return true end,
                        }
                    end
                end
            end,
        },
        {
            label = "follower payload drift",
            configure = function(state)
                state.onHolderAccess = function(_, count)
                    if count == 1 then
                        state.lastDescriptorCopy.nativeFollower.y = -6
                    end
                end
            end,
        },
    }

    for _, case in ipairs(driftCases) do
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        local frame = state.newDebuffFrame()
        environment.DebuffFrame = frame

        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        state.globalAccessCalls = {}
        case.configure(state, environment, frame)
        local writeStart = #state.calls + 1
        local ok = pcall(BD.UpdateCustomAuraContainer, "buffs", {
            enabled = true,
        })
        assertTrue(ok, case.label .. " fails closed without Lua error")
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), nil, case.label .. " performs zero native anchor writes")
        local result = BD.GetCustomAuraContainerState("buffs")
        assertFalse(result.nativeFollowerActive,
            case.label .. " never publishes follower ownership")
    end
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    state.onCombatCheck = function(count)
        if count == 3 then state.combat = true end
    end

    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    local writeStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        writeStart
    ), nil, "final combat flip performs zero native anchor writes")
    assertFalse(BD.GetCustomAuraContainerState("buffs").nativeFollowerActive,
        "final combat flip never publishes follower ownership")
end

do
    local accessCases = {
        {label = "false target access", value = false},
        {label = "nonboolean target access", value = {}},
        {label = "string target access", value = "yes"},
    }
    for _, case in ipairs(accessCases) do
        local harness = NewHarness()
        local BD = harness.BD
        local state = harness.state
        local environment = harness.environment
        environment.DebuffFrame = state.newDebuffFrame()
        state.nativeAccessResult = case.value
        BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
        local writeStart = #state.calls + 1
        BD.UpdateCustomAuraContainer("buffs", {enabled = true})
        assertEqual(findCall(
            state.calls,
            "DebuffFrame.ClearAllPointsBase",
            writeStart
        ), nil, case.label .. " performs zero writes")
    end

    local secretHarness = NewHarness()
    local secretBD = secretHarness.BD
    local secretState = secretHarness.state
    secretHarness.environment.DebuffFrame = secretState.newDebuffFrame()
    secretState.nativeAccessResult =
        secretState.newSecretValue("native access result")
    secretBD.RegisterCustomAuraContainerPane(
        "buffs",
        CompileFollowingBuffs
    )
    local writeStart = #secretState.calls + 1
    secretBD.UpdateCustomAuraContainer("buffs", {enabled = true})
    assertEqual(findCall(
        secretState.calls,
        "DebuffFrame.ClearAllPointsBase",
        writeStart
    ), nil, "secret target access result performs zero writes")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    local frame = state.newDebuffFrame()
    environment.DebuffFrame = frame
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.globalAccessResults = {UIParent = false}
    local deniedStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        style = "changed",
    })
    local denied = BD.GetCustomAuraContainerState("buffs")
    assertTrue(denied.active,
        "failed update restore retains the active custom presentation")
    assertTrue(denied.nativeFollowerActive,
        "failed update restore retains the last safe follower anchor")
    assertTrue(denied.operationPending,
        "failed update restore keeps the requested update queued")
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        deniedStart
    ), nil, "denied stored restore performs zero native writes")
    assertTrue(state.frames[1].shown and state.frames[2].shown,
        "denied update never creates a zero-display transition")

    state.globalAccessResults = nil
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("buffs")
    assertEqual(repaired.state, "RELOAD_REQUIRED",
        "repaired update completes its queued reload fallback")
    assertFalse(repaired.active,
        "repaired update restores Blizzard before hiding custom Buffs")
    assertFalse(repaired.nativeFollowerActive,
        "repaired update restores native Debuff ownership")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        allocations,
        "repaired update allocates no duplicate native container"
    )
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    local originalUIParent = environment.UIParent
    environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})

    environment.UIParent = {
        CanBeAccessedInContext = function() return true end,
    }
    local deniedStart = #state.calls + 1
    BD.DisableCustomAuraContainer("buffs")
    local denied = BD.GetCustomAuraContainerState("buffs")
    assertTrue(denied.active,
        "failed disable restore retains the active custom presentation")
    assertTrue(denied.nativeFollowerActive,
        "failed disable restore retains the last safe follower anchor")
    assertTrue(denied.operationPending,
        "failed disable restore keeps disable queued")
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        deniedStart
    ), nil, "changed restore global performs zero native writes")

    environment.UIParent = originalUIParent
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("buffs")
    assertEqual(repaired.state, "INACTIVE",
        "repaired disable completes")
    assertFalse(repaired.active,
        "repaired disable hides custom Buffs after native restore")
    assertFalse(repaired.nativeFollowerActive,
        "repaired disable releases native Debuff ownership")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    local frame = state.newDebuffFrame()
    environment.DebuffFrame = frame
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})

    local enterStart = #state.calls + 1
    state.fireRegistry("EditMode.Enter")
    local entered = BD.GetCustomAuraContainerState("buffs")
    assertTrue(entered.active,
        "Edit Mode entry retains custom Buff presentation ownership")
    assertFalse(entered.nativeFollowerActive,
        "Edit Mode entry restores native Debuff anchoring")
    assertTrue(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        enterStart
    ) ~= nil, "Edit Mode entry restores the native root")
    assertTrue(state.frames[1].shown and state.frames[2].shown,
        "Edit Mode entry keeps the custom presentation visible")

    frame.systemInfo.anchorInfo.offsetX = -60
    frame.systemInfo.anchorInfo.offsetY = -80
    local exitStart = #state.calls + 1
    state.fireRegistry("EditMode.Exit")
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        exitStart
    ), nil, "Edit Mode exit does not reattach synchronously")
    assertTrue(findCall(state.calls, "Timer.After", exitStart) ~= nil,
        "Edit Mode exit queues one next-tick reattach")
    state.runTimers(0)
    local exited = BD.GetCustomAuraContainerState("buffs")
    assertTrue(exited.active and exited.nativeFollowerActive,
        "next-tick Edit Mode exit restores shared follower ownership")
    local reattach = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        exitStart
    )
    assertEqual(reattach.args[2], state.frames[1],
        "Edit Mode exit reattaches Debuffs to the same holder")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true, tuning = 1})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.combat = true
    BD.UpdateCustomAuraContainer("buffs", {enabled = true, tuning = 2})
    BD.UpdateCustomAuraContainer("buffs", {enabled = true, tuning = 3})
    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    local queued = BD.GetCustomAuraContainerState("buffs")
    assertEqual(queued.unit, "vehicle",
        "follower controller retargets player to vehicle immediately")
    assertTrue(queued.operationPending,
        "combat-live retarget preserves the latest tuning operation")

    local eventStart = #state.calls + 1
    local timersBefore = countCalls(state.calls, "Timer.After")
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.fireEvent("PLAYER_ENTERING_WORLD")
    state.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    state.fireEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "player")
    assertEqual(
        countCalls(state.calls, "Timer.After"),
        timersBefore + 1,
        "combat lifecycle bursts coalesce to one follower timer"
    )
    state.runTimers(0)
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        eventStart
    ), nil, "combat lifecycle timer performs zero protected writes")

    state.combat = false
    state.fireEvent("PLAYER_REGEN_ENABLED")
    state.runTimers(0)
    local recovered = BD.GetCustomAuraContainerState("buffs")
    assertFalse(recovered.operationPending,
        "regen drains the latest tuning operation")
    assertEqual(recovered.unit, "vehicle",
        "regen preserves the immediate vehicle retarget")
    assertTrue(recovered.nativeFollowerActive,
        "regen reapplies the shared follower")
    local lastFlow
    for _, call in ipairs(state.calls) do
        if call.name == "AF.SetCustomAuraContainerFlowLayout" then
            lastFlow = call
        end
    end
    assertEqual(lastFlow.args[1].marker, 3,
        "regen applies only the latest queued tuning payload")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        allocations,
        "combat lifecycle recovery allocates no duplicate container"
    )
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.globalAccessResults = {UIParent = false}
    local refreshStart = #state.calls + 1
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.runTimers(0)
    local failed = BD.GetCustomAuraContainerState("buffs")
    assertEqual(failed.state, "ACTIVE_REFRESH_FAILED",
        "active refresh failure has a distinct state")
    assertEqual(failed.diagnostic, "NATIVE_FOLLOWER_REFRESH_FAILED",
        "active refresh failure has a truthful distinct diagnostic")
    assertTrue(failed.active and failed.nativeFollowerActive,
        "active refresh failure retains the last safe presentation")
    assertTrue(state.frames[1].shown and state.frames[2].shown,
        "active refresh failure keeps holder and container visible")
    assertEqual(findCall(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        refreshStart
    ), nil, "failed active refresh performs zero native writes")

    state.globalAccessResults = nil
    state.fireEvent("PLAYER_ENTERING_WORLD")
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("buffs")
    assertEqual(repaired.state, "ACTIVE",
        "later lifecycle recovery repairs the active follower")
    assertEqual(repaired.diagnostic, nil,
        "successful refresh clears the distinct diagnostic")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        allocations,
        "active refresh recovery allocates no duplicate container"
    )
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    local frame = state.newDebuffFrame()
    environment.DebuffFrame = frame
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})

    state.globalAccessResults = {UIParent = false}
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.runTimers(0)
    local failed = BD.GetCustomAuraContainerState("buffs")
    assertTrue(failed.pending,
        "failed lifecycle attachment marks shared follower pending")
    assertFalse(failed.operationPending,
        "failed lifecycle attachment is not a config operation")
    assertEqual(failed.diagnostic, "NATIVE_FOLLOWER_REFRESH_FAILED",
        "failed lifecycle attachment publishes truthful diagnostic")

    frame.systemInfo.anchorInfo.point = "LEFT"
    frame.systemInfo.anchorInfo.relativePoint = "RIGHT"
    frame.systemInfo.anchorInfo.offsetX = 24
    frame.systemInfo.anchorInfo.offsetY = -18
    frame.systemInfo.anchorInfo2.point = "TOP"
    frame.systemInfo.anchorInfo2.relativePoint = "CENTER"
    frame.systemInfo.anchorInfo2.offsetX = -14
    frame.systemInfo.anchorInfo2.offsetY = 22
    state.globalAccessResults = nil
    local recoveryStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("buffs", {
        enabled = true,
        tuning = 4,
    })
    assertEqual(countCalls(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        recoveryStart
    ), 1, "direct config recovery performs one real follower clear")
    assertEqual(countCalls(
        state.calls,
        "DebuffFrame.SetPointBase",
        recoveryStart
    ), 1, "direct config recovery performs one real follower attach")
    local reattach = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        recoveryStart
    )
    assertEqual(reattach.args[1], "TOPRIGHT",
        "direct config recovery reapplies the follower point")
    assertEqual(reattach.args[2], state.frames[1],
        "direct config recovery reattaches to the existing holder")
    assertEqual(reattach.args[3], "BOTTOMRIGHT",
        "direct config recovery reapplies follower relative point")
    assertEqual(reattach.args[4], 0,
        "direct config recovery reapplies follower X")
    assertEqual(reattach.args[5], -5,
        "direct config recovery reapplies follower Y")
    local repaired = BD.GetCustomAuraContainerState("buffs")
    assertEqual(repaired.state, "ACTIVE",
        "direct config update repairs failed lifecycle attachment")
    assertFalse(repaired.pending,
        "successful direct update clears global follower pending")
    assertFalse(repaired.operationPending,
        "successful direct update leaves no config operation pending")
    assertEqual(repaired.diagnostic, nil,
        "successful direct update clears refresh diagnostic")
    assertTrue(repaired.nativeFollowerActive,
        "successful direct update retains follower ownership")

    local disableStart = #state.calls + 1
    BD.DisableCustomAuraContainer("buffs")
    assertEqual(countCalls(
        state.calls,
        "DebuffFrame.ClearAllPointsBase",
        disableStart
    ), 1, "disable clears the repaired follower once")
    assertEqual(countCalls(
        state.calls,
        "DebuffFrame.SetPointBase",
        disableStart
    ), 2, "disable restores the updated two-point system anchor")
    local firstRestore, firstRestoreIndex = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        disableStart
    )
    assertEqual(firstRestore.args[1], "LEFT",
        "disable restores updated first point")
    assertEqual(firstRestore.args[2], environment.UIParent,
        "disable restores updated first relative object")
    assertEqual(firstRestore.args[3], "RIGHT",
        "disable restores updated first relative point")
    assertEqual(firstRestore.args[4], 12,
        "disable restores updated first scaled X")
    assertEqual(firstRestore.args[5], -9,
        "disable restores updated first scaled Y")
    local secondRestore = findCall(
        state.calls,
        "DebuffFrame.SetPointBase",
        firstRestoreIndex + 1
    )
    assertEqual(secondRestore.args[1], "TOP",
        "disable restores updated second point")
    assertEqual(secondRestore.args[2], environment.BuffFrame,
        "disable restores updated second relative object")
    assertEqual(secondRestore.args[3], "CENTER",
        "disable restores updated second relative point")
    assertEqual(secondRestore.args[4], -7,
        "disable restores updated second scaled X")
    assertEqual(secondRestore.args[5], 11,
        "disable restores updated second scaled Y")
    local disabled = BD.GetCustomAuraContainerState("buffs")
    assertFalse(disabled.active,
        "disable completes after restoring the updated system anchor")
    assertFalse(disabled.nativeFollowerActive,
        "disable releases follower ownership after updated restore")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    state.suppressEnableSucceeds = false
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local rolledBack = BD.GetCustomAuraContainerState("buffs")
    assertEqual(rolledBack.state, "SUPPRESSION_FAILED",
        "successful rollback reports suppression failure")
    assertFalse(rolledBack.active,
        "successful rollback hides custom Buffs after native restore")
    assertFalse(rolledBack.nativeFollowerActive,
        "successful rollback restores native Debuff anchoring")
    assertFalse(state.frames[1].shown or state.frames[2].shown,
        "successful rollback leaves no duplicate custom presentation")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        1,
        "successful rollback retains one completed container"
    )
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    state.suppressEnableSucceeds = false
    state.onSuppressEnable = function()
        state.suppressRestoreSucceeds = false
    end
    BD.RegisterCustomAuraContainerPane("buffs", CompileFollowingBuffs)
    BD.UpdateCustomAuraContainer("buffs", {enabled = true})
    local retained = BD.GetCustomAuraContainerState("buffs")
    assertTrue(retained.active,
        "failed native rollback retains a visible custom presentation")
    assertTrue(state.frames[1].shown and state.frames[2].shown,
        "failed native rollback never leaves zero Buff presentation")
    assertEqual(
        countCalls(state.calls, "AF.CreateCustomAuraContainer"),
        1,
        "failed rollback allocates no duplicate container"
    )
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
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    environment.EditModeManagerFrame.editModeActive = false

    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    assertTrue(BD.IsCustomAuraContainerAvailable("debuffs"),
        "full harmful controller availability")

    local buildStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local active = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(active.active, "full harmful controller activates")
    assertTrue(active.buildCompleted,
        "full harmful construction completes before activation")
    assertEqual(active.state, "ACTIVE", "full harmful active state")
    assertEqual(active.unit, "player", "full harmful initial unit")
    assertFalse(active.operationPending,
        "full harmful activation leaves no queued operation")
    assertEqual(state.frames[1].rolesets, "buffs",
        "full harmful holder receives the shared roleset")

    local restoreCall, restoreIndex = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        buildStart
    )
    assertEqual(restoreCall.args[1], false,
        "build starts by restoring complete harmful presentation")
    assertEqual(restoreCall.args[2], "player",
        "build restore uses sanitized player unit")
    local _, createIndex = findCall(
        state.calls,
        "AF.CreateCustomAuraContainer",
        buildStart
    )
    local groupCall, groupIndex = findCall(
        state.calls,
        "AF.AddCustomAuraGroup",
        buildStart
    )
    local _, updateIndex = findCall(
        state.calls,
        "AF.UpdateCustomAuraContainer",
        buildStart
    )
    local suppressCall, suppressIndex = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        restoreIndex + 1
    )
    local _, showIndex = findCall(
        state.calls,
        "container1.Show",
        buildStart
    )
    assertTrue(restoreIndex < createIndex,
        "native restore precedes harmful container allocation")
    assertTrue(createIndex < groupIndex,
        "harmful container exists before its native group")
    assertEqual(groupCall.args[1], "harmful", "harmful group key")
    assertEqual(groupCall.args[2], "HARMFUL", "harmful native filter")
    assertEqual(groupCall.args[3].maxFrameCount, 25,
        "harmful combined finite cap")
    assertTrue(groupIndex < updateIndex,
        "native group is complete before first native update")
    assertEqual(suppressCall.args[1], true,
        "activation uses full harmful suppression")
    assertEqual(suppressCall.args[2], nil,
        "suppression does not pass an observed private unit")
    assertTrue(updateIndex < suppressIndex,
        "replacement is updated before Blizzard suppression")
    assertTrue(suppressIndex < showIndex,
        "Blizzard suppression completes before custom row show")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativePublicAurasSuppressed",
        buildStart
    ), 0, "harmful activation never uses public-only suppression")

    local holderPoint = findCall(state.calls, "holder1.SetPoint", buildStart)
    assertEqual(holderPoint.args[1], "TOPRIGHT",
        "harmful holder point")
    assertEqual(holderPoint.args[2], environment.DebuffFrame,
        "harmful holder follows exact DebuffFrame root")
    assertEqual(holderPoint.args[3], "TOPRIGHT",
        "harmful holder relative point")
    assertEqual(holderPoint.args[4], 0, "harmful holder X offset")
    assertEqual(holderPoint.args[5], 0, "harmful holder Y offset")

    local disableStart = #state.calls + 1
    assertTrue(BD.DisableCustomAuraContainer("debuffs"),
        "full harmful disable completes")
    local disabled = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(disabled.active, "full harmful disable is inactive")
    assertFalse(disabled.operationPending,
        "full harmful disable leaves no pending operation")
    local disableRestore, disableRestoreIndex = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        disableStart
    )
    local _, disableContainerIndex = findCall(
        state.calls,
        "AF.SetCustomAuraContainerEnabled",
        disableStart
    )
    local _, disableHolderIndex = findCall(
        state.calls,
        "holder1.Hide",
        disableStart
    )
    assertEqual(disableRestore.args[1], false,
        "disable restores full native harmful owner")
    assertEqual(disableRestore.args[2], "player",
        "disable restores the current sanitized unit")
    assertTrue(disableRestoreIndex < disableContainerIndex,
        "native restore precedes custom container disable")
    assertTrue(disableRestoreIndex < disableHolderIndex,
        "native restore precedes custom holder hide")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.harmfulRestoreSucceeds = false
    local disableStart = #state.calls + 1
    assertFalse(BD.DisableCustomAuraContainer("debuffs"),
        "failed native restore rejects custom disable")
    local retained = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(retained.active,
        "failed restore retains the custom harmful presentation")
    assertTrue(retained.operationPending,
        "failed restore keeps disable queued")
    assertEqual(findCall(
        state.calls,
        "AF.SetCustomAuraContainerEnabled",
        disableStart
    ), nil, "failed restore performs no custom disable write")
    assertEqual(findCall(
        state.calls,
        "container1.Hide",
        disableStart
    ), nil, "failed restore performs no custom container hide")
    assertEqual(findCall(
        state.calls,
        "holder1.Hide",
        disableStart
    ), nil, "failed restore performs no custom holder hide")

    state.harmfulRestoreSucceeds = true
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(repaired.active,
        "restore retry hides custom only after native recovery")
    assertFalse(repaired.operationPending,
        "restore retry clears pending disable")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), allocations, "restore retry allocates no duplicate container")
end

for _, suppressionFailure in ipairs({
    {
        name = "suppression failure with successful restore",
        restoreSucceeds = true,
        customVisible = false,
    },
    {
        name = "suppression failure with failed recovery",
        restoreSucceeds = false,
        customVisible = false,
    },
}) do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    state.harmfulSuppressSucceeds = false
    local restoreCalls = 0
    state.onHarmfulRestore = function()
        restoreCalls = restoreCalls + 1
        if restoreCalls >= 2 then
            state.harmfulRestoreSucceeds =
                suppressionFailure.restoreSucceeds
        end
    end
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    local result = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(result.active, suppressionFailure.customVisible,
        suppressionFailure.name .. " visibility")
    assertEqual(state.frames[1].shown, suppressionFailure.customVisible,
        suppressionFailure.name .. " holder visibility")
    assertEqual(state.frames[2].shown, suppressionFailure.customVisible,
        suppressionFailure.name .. " container visibility")
    assertFalse(result.operationPending,
        suppressionFailure.name .. " has no retry ownership")
    assertFalse(result.nativeFollowerActive,
        suppressionFailure.name .. " has no follower ownership")
    assertEqual(result.state, "SUPPRESSION_FAILED",
        suppressionFailure.name .. " publishes fallback state")
    assertEqual(result.diagnostic, "NATIVE_SUPPRESSION_FAILED",
        suppressionFailure.name .. " publishes fallback diagnostic")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), 1, suppressionFailure.name .. " builds one native shell")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed"
    ), 3, suppressionFailure.name
        .. " performs pre-build restore, suppression, and recovery")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    environment.EditModeManagerFrame.editModeActive = false
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 1,
    })
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    local enterStart = #state.calls + 1
    state.fireRegistry("EditMode.Enter")
    local suspended = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(suspended.active,
        "Edit Mode entry restores and hides custom harmful row")
    assertTrue(suspended.editModeSuspended,
        "Edit Mode entry records explicit suspension")
    local enterRestore, enterRestoreIndex = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        enterStart
    )
    local _, enterHideIndex = findCall(
        state.calls,
        "container1.Hide",
        enterStart
    )
    assertEqual(enterRestore.args[1], false,
        "Edit Mode entry restores full Blizzard harmful row")
    assertTrue(enterRestoreIndex < enterHideIndex,
        "Edit Mode native restore precedes custom hide")

    local updateStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 2,
    })
    BD.UpdateCustomAuraContainer("debuffs", {
        enabled = true,
        tuning = 3,
    })
    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    local retargetedSuspension =
        BD.GetCustomAuraContainerState("debuffs")
    assertEqual(retargetedSuspension.unit, "vehicle",
        "Edit Mode suspension retargets the hidden row immediately")
    assertFalse(retargetedSuspension.active,
        "Edit Mode retarget keeps the custom harmful row hidden")
    assertTrue(retargetedSuspension.editModeSuspended,
        "Edit Mode retarget preserves suspension ownership")
    assertTrue(BD.GetCustomAuraContainerState("debuffs").operationPending,
        "Edit Mode retarget preserves the latest pending tuning update")
    local retargetCall = findCall(
        state.calls,
        "AF.SetCustomAuraContainerUnit",
        updateStart
    )
    assertEqual(retargetCall.args[1], "vehicle",
        "hidden combined row receives the immediate vehicle unit")
    assertEqual(findCall(
        state.calls,
        "AF.SetCustomAuraContainerFlowLayout",
        updateStart
    ), nil, "Edit Mode performs no harmful tuning writes")
    assertEqual(findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        updateStart
    ), nil, "Edit Mode performs no harmful suppression writes")
    assertEqual(findCall(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        updateStart
    ), nil, "Edit Mode retarget performs no harmful reassert writes")

    local exitStart = #state.calls + 1
    state.fireRegistry("EditMode.Exit")
    assertEqual(findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        exitStart
    ), nil, "Edit Mode exit defers harmful activation to next tick")
    state.runTimers(0)
    local resumed = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(resumed.active,
        "Edit Mode exit reactivates the custom harmful row")
    assertFalse(resumed.editModeSuspended,
        "successful Edit Mode exit clears suspension")
    assertFalse(resumed.operationPending,
        "Edit Mode exit drains latest harmful update")
    assertEqual(resumed.unit, "vehicle",
        "Edit Mode exit preserves the immediate vehicle retarget")
    local finalFlow
    for index = exitStart, #state.calls do
        if state.calls[index].name
            == "AF.SetCustomAuraContainerFlowLayout"
        then
            finalFlow = state.calls[index]
        end
    end
    assertEqual(finalFlow.args[1].marker, 3,
        "Edit Mode exit applies latest-only harmful tuning")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        exitStart
    ), 1, "Edit Mode exit performs one suppression transaction")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        exitStart
    ), 0, "fresh Edit Mode suppression is not redundantly reasserted")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), allocations, "Edit Mode cycle allocates no duplicate container")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.combat = true
    state.playerUnit = "vehicle"
    local retargetStart = #state.calls + 1
    BD.RefreshCustomAuraContainerUnits()
    local retargeted = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(retargeted.unit, "vehicle",
        "harmful row retargets to vehicle immediately")
    assertTrue(retargeted.active,
        "vehicle retarget keeps custom presentation visible")
    assertTrue(retargeted.operationPending,
        "vehicle retarget queues OOC harmful reassert")
    local unitCall = findCall(
        state.calls,
        "AF.SetCustomAuraContainerUnit",
        retargetStart
    )
    assertEqual(unitCall.args[1], "vehicle",
        "native combined row receives sanitized vehicle unit")
    assertEqual(findCall(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        retargetStart
    ), nil, "combat retarget performs no private reassert call")

    state.combat = false
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local recovered = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(recovered.active,
        "regen reassert keeps custom harmful row active")
    assertFalse(recovered.operationPending,
        "regen clears harmful reassert queue")
    assertFalse(recovered.harmfulReassertPending,
        "regen clears harmful reassert marker")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        retargetStart
    ), 1, "regen performs one private suppression reassert")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), allocations, "vehicle reassert allocates no duplicate container")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    state.harmfulReassertSucceeds = false
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local allocations = countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    )

    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    local failed = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(failed.active,
        "failed private reassert retains custom presentation")
    assertTrue(failed.operationPending,
        "failed private reassert remains queued")
    assertTrue(failed.harmfulReassertPending,
        "failed private reassert exposes truthful state")
    assertEqual(failed.diagnostic, "NATIVE_HARMFUL_REASSERT_FAILED",
        "failed private reassert diagnostic")

    state.harmfulReassertSucceeds = true
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local repaired = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(repaired.active,
        "private reassert retry keeps the custom presentation")
    assertFalse(repaired.operationPending,
        "private reassert retry clears the queue")
    assertEqual(repaired.state, "ACTIVE",
        "private reassert retry restores active state")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), allocations, "private reassert retry allocates no duplicate shell")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    state.combat = true
    state.playerUnit = "vehicle"
    BD.RefreshCustomAuraContainerUnits()
    state.combat = false
    state.harmfulReassertSucceeds = false
    BD.FlushCustomAuraContainerUpdates()
    state.runTimers(0)
    local failed = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(failed.active,
        "disable-after-reassert setup retains custom row")
    assertTrue(failed.operationPending,
        "disable-after-reassert setup exposes pending retry")
    assertTrue(failed.harmfulReassertPending,
        "disable-after-reassert setup records reassert failure")

    state.harmfulRestoreSucceeds = true
    local disableStart = #state.calls + 1
    assertTrue(BD.DisableCustomAuraContainer("debuffs"),
        "disable bypasses failed reassert and restores native")
    local disabled = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(disabled.active,
        "disable-after-reassert hides custom row")
    assertFalse(disabled.operationPending,
        "disable-after-reassert clears queued retry")
    assertFalse(disabled.harmfulReassertPending,
        "disable-after-reassert clears reassert marker")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        disableStart
    ), 0, "disable does not repeat failed reassert")
    local restoreCall, restoreIndex = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        disableStart
    )
    local _, hideIndex = findCall(
        state.calls,
        "container1.Hide",
        disableStart
    )
    assertEqual(restoreCall.args[1], false,
        "disable-after-reassert uses full native restore")
    assertEqual(restoreCall.args[2], "vehicle",
        "disable-after-reassert restores current vehicle unit")
    assertTrue(restoreIndex < hideIndex,
        "disable-after-reassert restores before hiding custom")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    state.nativeAccessResult = false
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    local firstStart = #state.calls + 1
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local denied = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(denied.active,
        "denied harmful holder anchor never activates")
    assertFalse(denied.buildAttempted,
        "denied harmful holder anchor performs no native build")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer",
        firstStart
    ), 0, "denied harmful holder anchor allocates no container")
    local firstRestore = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        firstStart
    )
    assertEqual(firstRestore.args[1], false,
        "holder preflight keeps Blizzard restored")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        firstStart
    ), 1, "denied holder performs no suppression write")

    state.nativeAccessResult = nil
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local recovered = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(recovered.active,
        "harmful holder access recovery activates")
    assertEqual(countCalls(state.calls, "CreateFrame.Holder"), 1,
        "harmful holder retry reuses pending holder")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer"
    ), 1, "harmful holder retry allocates one native container")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    environment.EventRegistry = nil
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    local startIndex = #state.calls + 1
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})
    local unavailable = BD.GetCustomAuraContainerState("debuffs")
    assertFalse(unavailable.active,
        "missing Edit Mode lifecycle never activates harmful replacement")
    assertFalse(unavailable.buildAttempted,
        "missing Edit Mode lifecycle performs no harmful build")
    assertEqual(countCalls(
        state.calls,
        "AF.CreateCustomAuraContainer",
        startIndex
    ), 0, "missing lifecycle allocates no harmful container")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        startIndex
    ), 1, "missing lifecycle performs only fail-native restoration")
    local restoreOnly = findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        startIndex
    )
    assertEqual(restoreOnly.args[1], false,
        "missing lifecycle never suppresses Blizzard harmful presentation")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    local environment = harness.environment
    environment.DebuffFrame = state.newDebuffFrame()
    environment.EditModeManagerFrame.editModeActive = false
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    state.harmfulRestoreSucceeds = false
    state.fireRegistry("EditMode.Enter")
    local failedSuspend = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(failedSuspend.active,
        "failed Edit Mode suspension keeps custom harmful visible")
    assertFalse(failedSuspend.editModeSuspended,
        "failed Edit Mode suspension never claims suspended ownership")
    assertEqual(failedSuspend.diagnostic, "EDIT_MODE_SUSPEND_FAILED",
        "failed Edit Mode suspension publishes its own diagnostic")

    state.playerUnit = "vehicle"
    local retargetStart = #state.calls + 1
    BD.RefreshCustomAuraContainerUnits()
    local retargeted = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(retargeted.unit, "vehicle",
        "restore-failed active row retargets in Edit Mode immediately")
    assertTrue(retargeted.active,
        "restore-failed Edit Mode retarget remains visible")
    assertTrue(retargeted.harmfulReassertPending,
        "restore-failed Edit Mode retarget records one reassert intent")
    assertEqual(findCall(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        retargetStart
    ), nil, "restore-failed Edit Mode retarget performs no suppression")
    assertEqual(findCall(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        retargetStart
    ), nil, "restore-failed Edit Mode retarget performs no reassert")

    state.harmfulRestoreSucceeds = true
    local exitStart = #state.calls + 1
    state.fireRegistry("EditMode.Exit")
    state.runTimers(0)
    local recovered = BD.GetCustomAuraContainerState("debuffs")
    assertTrue(recovered.active,
        "failed-suspend exit keeps the replacement active")
    assertFalse(recovered.harmfulReassertPending,
        "failed-suspend exit consumes reassert intent")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        exitStart
    ), 1, "failed-suspend exit performs exactly one reassert")
    assertEqual(countCalls(
        state.calls,
        "BD.SetNativeHarmfulAurasSuppressed",
        exitStart
    ), 0, "failed-suspend exit does not start a fresh suppression")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    local startIndex = #state.calls + 1
    state.fireEvent("PLAYER_REGEN_ENABLED")
    state.runTimers(0)
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        startIndex
    ), 0, "unrelated regen creates no harmful reassert intent")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    state.combat = true
    local startIndex = #state.calls + 1
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    state.fireEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "player")
    state.runTimers(0)
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        startIndex
    ), 0, "combat lifecycle burst performs no immediate reassert")

    state.combat = false
    state.fireEvent("PLAYER_REGEN_ENABLED")
    state.runTimers(0)
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        startIndex
    ), 1, "combat layout/spec burst coalesces to one reassert")
end

do
    local harness = NewHarness()
    local BD = harness.BD
    local state = harness.state
    harness.environment.DebuffFrame = state.newDebuffFrame()
    BD.RegisterCustomAuraContainerPane("debuffs", CompileHarmful)
    BD.UpdateCustomAuraContainer("debuffs", {enabled = true})

    state.combat = true
    state.playerUnit = "vehicle"
    local startIndex = #state.calls + 1
    BD.RefreshCustomAuraContainerUnits()
    state.fireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    state.fireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    state.fireEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "player")
    state.runTimers(0)
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        startIndex
    ), 0, "combat retarget/callback burst performs no early reassert")

    state.combat = false
    state.fireEvent("PLAYER_REGEN_ENABLED")
    state.runTimers(0)
    local recovered = BD.GetCustomAuraContainerState("debuffs")
    assertEqual(recovered.unit, "vehicle",
        "combined burst preserves immediate vehicle retarget")
    assertFalse(recovered.harmfulReassertPending,
        "combined burst consumes its sole reassert intent")
    assertEqual(countCalls(
        state.calls,
        "BD.ReassertNativeHarmfulAuraSuppression",
        startIndex
    ), 1, "combat retarget plus both callbacks reasserts exactly once")
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

    local resolverStart = assert(controllerSource:find(
        "local function ResolvePlayerUnit()",
        1,
        true
    ))
    local resolverEnd = assert(controllerSource:find(
        "\nend\n\nlocal function HasPendingControllers",
        resolverStart,
        true
    ))
    local resolverSource = controllerSource:sub(resolverStart, resolverEnd)
    local unitRead = assert(resolverSource:find(
        "unit = playerFrame.unit",
        1,
        true
    ))
    local boundaryGate = assert(resolverSource:find(
        "if IsValueNonSecret(unit)",
        1,
        true
    ))
    local typeCheck = assert(resolverSource:find(
        "and type(unit) == \"string\"",
        1,
        true
    ))
    local whitelist = assert(resolverSource:find(
        "and (unit == \"player\" or unit == \"vehicle\")",
        1,
        true
    ))
    assertTrue(unitRead < boundaryGate,
        "player unit is read once before the boundary")
    assertTrue(boundaryGate < typeCheck,
        "secret gate precedes unit type observation")
    assertTrue(typeCheck < whitelist,
        "unit type check precedes whitelist equality")
    assertEqual(countPlain(resolverSource, "playerFrame.unit"), 1,
        "resolver reads PlayerFrame.unit exactly once")
    assertEqual(resolverSource:find("type(playerFrame.unit)", 1, true), nil,
        "resolver never observes raw PlayerFrame.unit type")
    local cachedGate = assert(controllerSource:find(
        "local IsValueNonSecret = BFI.funcs.isValueNonSecret",
        1,
        true
    ))
    assertTrue(cachedGate < resolverStart,
        "resolver uses the cached canonical secret gate")

    for _, order in ipairs({
        {
            startText = "local function HasExactSystemAnchorIdentity(",
            endText = "\nlocal function HasExactNativeFollowerIdentity(",
            gateText = "if not IsOrdinaryValue(relativeObject) then",
            observeText = "local relativeType = type(relativeObject)",
            label = "relative global",
        },
        {
            startText = "local function HasExactNativeFollowerIdentity(",
            endText = "\nlocal function RevalidateNativeFollowerSnapshot(",
            gateText = "if not IsOrdinaryValue(target) then",
            observeText = "local targetType = type(target)",
            label = "DebuffFrame global",
        },
        {
            startText = "local function HasExactApplyTransactionIdentity(",
            endText = "\nlocal function RestoreNativeFollower(",
            gateText = "if not IsOrdinaryValue(manager) then",
            observeText = "local managerType = type(manager)",
            label = "Edit Mode manager",
        },
    }) do
        local sectionStart = assert(controllerSource:find(
            order.startText,
            1,
            true
        ))
        local sectionEnd = assert(controllerSource:find(
            order.endText,
            sectionStart,
            true
        ))
        local section = controllerSource:sub(sectionStart, sectionEnd)
        local gate = assert(section:find(order.gateText, 1, true))
        local observation = assert(section:find(order.observeText, 1, true))
        assertTrue(gate < observation,
            order.label .. " secret gate precedes type observation")
    end

    local applyPendingStart = assert(controllerSource:find(
        "function ControllerMixin:_ApplyPending()",
        1,
        true
    ))
    local applyPendingEnd = assert(controllerSource:find(
        "\nfunction ControllerMixin:Update(config)",
        applyPendingStart,
        true
    ))
    local applyPendingSource =
        controllerSource:sub(applyPendingStart, applyPendingEnd)
    local retarget = assert(applyPendingSource:find(
        "self:_ApplyRetarget()",
        1,
        true
    ))
    local editModeDeferral = assert(applyPendingSource:find(
        "nativeFollowerEditModeActive",
        1,
        true
    ))
    local noOperation = assert(applyPendingSource:find(
        "if not self.pendingOperation then",
        1,
        true
    ))
    local combatGate = assert(applyPendingSource:find(
        "if InCombatLockdown() then",
        1,
        true
    ))
    assertTrue(retarget < editModeDeferral,
        "live retarget precedes Edit Mode holder deferral")
    assertTrue(retarget < noOperation,
        "live retarget precedes pending-operation cleanup")
    assertTrue(noOperation < combatGate,
        "live retarget precedes protected tuning deferral")

    local systemIdentityStart = assert(controllerSource:find(
        "local function HasExactSystemAnchorIdentity(",
        1,
        true
    ))
    local systemIdentityEnd = assert(controllerSource:find(
        "\nend\n\nlocal function HasExactNativeFollowerIdentity",
        systemIdentityStart,
        true
    ))
    local systemIdentitySource = controllerSource:sub(
        systemIdentityStart,
        systemIdentityEnd
    )
    local relativeGate = assert(systemIdentitySource:find(
        "IsOrdinaryValue(relativeObject)",
        1,
        true
    ))
    local relativeType = assert(systemIdentitySource:find(
        "type(relativeObject)",
        1,
        true
    ))
    assertTrue(relativeGate < relativeType,
        "relative-object terminal secret gate precedes type")

    local nativeIdentityStart = assert(controllerSource:find(
        "local function HasExactNativeFollowerIdentity(",
        1,
        true
    ))
    local nativeIdentityEnd = assert(controllerSource:find(
        "\nend\n\nlocal function RevalidateNativeFollowerSnapshot",
        nativeIdentityStart,
        true
    ))
    local nativeIdentitySource = controllerSource:sub(
        nativeIdentityStart,
        nativeIdentityEnd
    )
    local targetGate = assert(nativeIdentitySource:find(
        "IsOrdinaryValue(target)",
        1,
        true
    ))
    local targetType = assert(nativeIdentitySource:find(
        "type(target)",
        1,
        true
    ))
    assertTrue(targetGate < targetType,
        "native-target terminal secret gate precedes type")

    local applyIdentityStart = assert(controllerSource:find(
        "local function HasExactApplyTransactionIdentity(",
        1,
        true
    ))
    local applyIdentityEnd = assert(controllerSource:find(
        "\nend\n\nlocal function RestoreNativeFollower",
        applyIdentityStart,
        true
    ))
    local applyIdentitySource = controllerSource:sub(
        applyIdentityStart,
        applyIdentityEnd
    )
    local managerGate = assert(applyIdentitySource:find(
        "IsOrdinaryValue(manager)",
        1,
        true
    ))
    local managerType = assert(applyIdentitySource:find(
        "type(manager)",
        1,
        true
    ))
    assertTrue(managerGate < managerType,
        "Edit Mode manager terminal secret gate precedes type")

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
