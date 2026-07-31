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

local function copy(value)
    if type(value) ~= "table" then return value end

    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local MOCK_SORT_METHOD = {
    Default = 0,
    BigDefensive = 1,
    UnitFrameDebuff = 2,
    ImportantOnly = 3,
    Expiration = 4,
}
local MOCK_SORT_DIRECTION = {
    Normal = 0,
    Reverse = 1,
}
local MOCK_PROCESSING_POLICY = {
    None = 0,
    ProcessAura = 1,
}
local MOCK_FLOW_AXIS = {
    Horizontal = 0,
    Vertical = 1,
}

local function isEnumValue(enum, value)
    for _, candidate in pairs(enum) do
        if candidate == value then return true end
    end
    return false
end

local function validateSort(sortMethod, sortDirection)
    assertTrue(isEnumValue(MOCK_SORT_METHOD, sortMethod), "invalid mock sort method")
    assertTrue(isEnumValue(MOCK_SORT_DIRECTION, sortDirection),
        "invalid mock sort direction")
end

local function validateFlowLayout(layout)
    assertTrue(type(layout) == "table", "invalid mock flow layout")
    if layout.axis ~= nil then
        assertTrue(isEnumValue(MOCK_FLOW_AXIS, layout.axis), "invalid mock flow axis")
    end
end

local function validateProcessing(policy, options)
    assertTrue(isEnumValue(MOCK_PROCESSING_POLICY, policy),
        "invalid mock processing policy")
    if policy == MOCK_PROCESSING_POLICY.None then
        assertEqual(options, nil, "None processing options")
    else
        assertTrue(options == nil or type(options) == "table",
            "ProcessAura processing options")
    end
end

local function record(harness, name, ...)
    local args = {n = select("#", ...), ...}
    harness.events[#harness.events + 1] = {
        name = name,
        args = args,
    }
end

local function clearEvents(harness)
    harness.events = {}
end

local function countEvents(harness, name)
    local count = 0
    for _, event in ipairs(harness.events) do
        if event.name == name then
            count = count + 1
        end
    end
    return count
end

local function findEvent(harness, name, predicate)
    for index, event in ipairs(harness.events) do
        if event.name == name and (not predicate or predicate(event.args)) then
            return event, index
        end
    end
end

local function assertEventNames(harness, expected)
    assertEqual(#harness.events, #expected, "event count")
    for index, name in ipairs(expected) do
        assertEqual(harness.events[index].name, name, "event " .. index)
    end
end

local function newHolder(harness, name, parent)
    local holder = {
        id = #harness.holders + 1,
        name = name,
        parent = parent,
    }

    function holder:Hide()
        self.shown = false
        record(harness, "holder.hide", self)
    end

    function holder:IsShown()
        error("holder visibility must remain opaque")
    end

    function holder:IsMouseOver()
        error("holder hover state must remain opaque")
    end

    function holder:SetShown(shown)
        record(harness, "holder.shown", self, shown)
        self.shown = shown
    end

    function holder:SetAlpha(alpha)
        self.alpha = alpha
        if harness.recordAlpha then
            record(harness, "holder.alpha", self, alpha)
        end
    end

    function holder:SetSize(width, height)
        self.width = width
        self.height = height
        record(harness, "holder.size", self, width, height)
    end

    harness.holders[#harness.holders + 1] = holder
    return holder
end

local function newContainer(harness, parent)
    local container = {
        id = #harness.containers + 1,
        parent = parent,
        groups = {},
        slots = {},
    }

    function container:Hide()
        self.shown = false
        record(harness, "native.hide", self)
    end

    function container:Show()
        self.shown = true
        record(harness, "native.show", self)
    end

    function container:SetAlpha(alpha)
        self.alpha = alpha
        if harness.recordAlpha then
            record(harness, "native.alpha", self, alpha)
        end
    end

    function container:ClearAllPoints()
        self.point = nil
        record(harness, "native.clear-points", self)
    end

    function container:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = {point, relativeTo, relativePoint, x, y}
        record(
            harness,
            "native.set-point",
            self,
            point,
            relativeTo,
            relativePoint,
            x,
            y
        )
    end

    harness.containers[#harness.containers + 1] = container
    return container
end

local function newSlotButton(harness, container, key)
    local button = {
        container = container,
        key = key,
    }

    function button:ClearAllPoints()
        self.point = nil
        record(harness, "slot.clear-points", self)
    end

    function button:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = {point, relativeTo, relativePoint, x, y}
        record(
            harness,
            "slot.set-point",
            self,
            point,
            relativeTo,
            relativePoint,
            x,
            y
        )
    end

    harness.slotButtons[#harness.slotButtons + 1] = button
    return button
end

local function makeHarness(options)
    options = options or {}

    local harness = {
        events = {},
        holders = {},
        containers = {},
        slotButtons = {},
        timerCallbacks = {},
        inCombat = false,
        afConstructionStatsReads = 0,
        afConstructionTotalsReads = 0,
    }
    local AF = {
        isRetail = options.isRetail ~= false,
        versionNum = options.versionNum or 34,
    }
    local UF = {}
    local afConstructionTotals = {
        containerCreateAttempts = 0,
        containerAllocations = 0,
        containerCreateCompletions = 0,
        trackedContainers = 0,
        externalContainersObserved = 0,
        groupAddAttempts = 0,
        groupsAdded = 0,
        slotAddAttempts = 0,
        slotsAdded = 0,
        itemEnchantmentAddAttempts = 0,
        itemEnchantmentsAdded = 0,
        initialFrameReservationsAttempted = 0,
        initialFrameReservationsCompleted = 0,
    }

    function AF.Copy(value)
        return copy(value)
    end

    function AF.SetSize(frame, width, height)
        frame._width = width
        frame._height = height
        frame:SetSize(width, height)
    end

    function AF.SetFrameLevel(frame, level, relativeTo)
        assertEqual(harness.inCombat, false,
            "external container layer mutated in combat")
        frame.frameLevel = (relativeTo.frameLevel or 0) + level
        frame.frameStrata = relativeTo.frameStrata
        record(harness, "af.frame-level", frame, level, relativeTo)
    end

    function AF.HasCustomAuraContainer()
        return options.hasBackend ~= false
    end

    function AF.CreateCustomAuraContainer(parent)
        afConstructionTotals.containerCreateAttempts =
            afConstructionTotals.containerCreateAttempts + 1
        local container = newContainer(harness, parent)
        container.afConstructionStats = {
            groupsAdded = 0,
            slotsAdded = 0,
            initialFrameReservationsCompleted = 0,
        }
        afConstructionTotals.containerAllocations =
            afConstructionTotals.containerAllocations + 1
        afConstructionTotals.containerCreateCompletions =
            afConstructionTotals.containerCreateCompletions + 1
        afConstructionTotals.trackedContainers =
            afConstructionTotals.trackedContainers + 1
        if options.failCreatedContainerSetUnit then
            container.failSetUnit = true
        end
        record(harness, "af.create-container", container, parent)
        return container
    end

    function AF.GetCustomAuraContainerConstructionTotals()
        harness.afConstructionTotalsReads =
            harness.afConstructionTotalsReads + 1
        return copy(afConstructionTotals)
    end

    function AF.GetCustomAuraContainerConstructionStats(container)
        harness.afConstructionStatsReads =
            harness.afConstructionStatsReads + 1
        return copy(container.afConstructionStats)
    end

    function AF.SetCustomAuraContainerEnabled(container, enabled)
        container.enabled = enabled
        record(harness, "af.enabled", container, enabled)
    end

    function AF.SetCustomAuraContainerFlowLayout(container, layout)
        validateFlowLayout(layout)
        container.flowLayout = layout
        record(harness, "af.flow", container, layout)
    end

    function AF.SetCustomAuraContainerProcessingPolicy(container, policy, policyOptions)
        validateProcessing(policy, policyOptions)
        container.processing = {
            policy = policy,
            options = policyOptions,
        }
        record(harness, "af.processing", container, policy, policyOptions)
    end

    function AF.SetCustomAuraContainerUnit(container, unit)
        if container.failSetUnit then
            error("injected non-secret SetUnit failure")
        end
        container.unit = unit
        record(harness, "af.unit", container, unit)
    end

    function AF.UpdateCustomAuraContainer(container)
        record(harness, "af.update", container)
    end

    function AF.AddCustomAuraGroup(container, key, filterString, groupOptions, buttonStyle)
        afConstructionTotals.groupAddAttempts =
            afConstructionTotals.groupAddAttempts + 1
        afConstructionTotals.initialFrameReservationsAttempted =
            afConstructionTotals.initialFrameReservationsAttempted + 10
        assertTrue(
            groupOptions.maxFrameCount == math.huge
                or (
                    type(groupOptions.maxFrameCount) == "number"
                    and groupOptions.maxFrameCount >= 0
                    and groupOptions.maxFrameCount == math.floor(groupOptions.maxFrameCount)
                ),
            "invalid mock group maxFrameCount"
        )
        validateSort(groupOptions.sortMethod, groupOptions.sortDirection)
        container.groups[key] = {
            filterString = filterString,
            options = groupOptions,
            buttonStyle = buttonStyle,
        }
        container.afConstructionStats.groupsAdded =
            container.afConstructionStats.groupsAdded + 1
        container.afConstructionStats.initialFrameReservationsCompleted =
            container.afConstructionStats.initialFrameReservationsCompleted + 10
        afConstructionTotals.groupsAdded =
            afConstructionTotals.groupsAdded + 1
        afConstructionTotals.initialFrameReservationsCompleted =
            afConstructionTotals.initialFrameReservationsCompleted + 10
        record(
            harness,
            "af.add-group",
            container,
            key,
            filterString,
            groupOptions,
            buttonStyle
        )
    end

    function AF.SetCustomAuraGroupFilterString(container, key, filterString)
        container.groups[key].filterString = filterString
        record(harness, "af.group.filter", container, key, filterString)
    end

    function AF.SetCustomAuraGroupMaxFrameCount(container, key, maxFrameCount)
        assertTrue(
            maxFrameCount == math.huge
                or (
                    type(maxFrameCount) == "number"
                    and maxFrameCount >= 0
                    and maxFrameCount == math.floor(maxFrameCount)
                ),
            "invalid mock group maxFrameCount"
        )
        container.groups[key].options.maxFrameCount = maxFrameCount
        record(harness, "af.group.max", container, key, maxFrameCount)
    end

    function AF.SetCustomAuraGroupCandidateFilters(container, key, candidateFilters)
        container.groups[key].options.candidateFilters = candidateFilters
        record(harness, "af.group.candidates", container, key, candidateFilters)
    end

    function AF.SetCustomAuraGroupSortMethod(container, key, sortMethod, sortDirection)
        validateSort(sortMethod, sortDirection)
        local group = container.groups[key]
        group.options.sortMethod = sortMethod
        group.options.sortDirection = sortDirection
        record(
            harness,
            "af.group.sort",
            container,
            key,
            sortMethod,
            sortDirection
        )
    end

    function AF.SetCustomAuraGroupLayout(container, key, layout)
        container.groups[key].options.layout = layout
        record(harness, "af.group.layout", container, key, layout)
    end

    function AF.AddCustomAuraSlot(container, key, filterString, slotOptions, buttonStyle)
        afConstructionTotals.slotAddAttempts =
            afConstructionTotals.slotAddAttempts + 1
        afConstructionTotals.initialFrameReservationsAttempted =
            afConstructionTotals.initialFrameReservationsAttempted + 1
        validateSort(slotOptions.sortMethod, slotOptions.sortDirection)
        assertTrue(type(slotOptions.anchor) == "table", "missing mock slot anchor")
        if options.failSlotAdd then
            error("injected non-secret AddSlot failure")
        end
        local button = newSlotButton(harness, container, key)
        container.slots[key] = {
            filterString = filterString,
            options = slotOptions,
            buttonStyle = buttonStyle,
            button = button,
        }
        container.afConstructionStats.slotsAdded =
            container.afConstructionStats.slotsAdded + 1
        container.afConstructionStats.initialFrameReservationsCompleted =
            container.afConstructionStats.initialFrameReservationsCompleted + 1
        afConstructionTotals.slotsAdded =
            afConstructionTotals.slotsAdded + 1
        afConstructionTotals.initialFrameReservationsCompleted =
            afConstructionTotals.initialFrameReservationsCompleted + 1
        record(
            harness,
            "af.add-slot",
            container,
            key,
            filterString,
            slotOptions,
            buttonStyle
        )
        button:ClearAllPoints()
        button:SetPoint(
            slotOptions.anchor.point,
            slotOptions.anchor.relativeTo,
            slotOptions.anchor.relativePoint,
            slotOptions.anchor.x,
            slotOptions.anchor.y
        )
    end

    function AF.SetCustomAuraSlotFilterString(container, key, filterString)
        container.slots[key].filterString = filterString
        record(harness, "af.slot.filter", container, key, filterString)
    end

    function AF.SetCustomAuraSlotCandidateFilters(container, key, candidateFilters)
        container.slots[key].options.candidateFilters = candidateFilters
        record(harness, "af.slot.candidates", container, key, candidateFilters)
    end

    function AF.SetCustomAuraSlotSortMethod(container, key, sortMethod, sortDirection)
        validateSort(sortMethod, sortDirection)
        local slot = container.slots[key]
        slot.options.sortMethod = sortMethod
        slot.options.sortDirection = sortDirection
        record(
            harness,
            "af.slot.sort",
            container,
            key,
            sortMethod,
            sortDirection
        )
    end

    if options.missingMethod then
        AF[options.missingMethod] = nil
    end

    function UF:RegisterEvent(event, callback)
        assertEqual(event, "PLAYER_REGEN_ENABLED", "registered event")
        assertEqual(harness.regenCallback, nil, "regen handler already registered")
        harness.regenCallback = callback
        record(harness, "uf.register", event, callback)
    end

    function UF:UnregisterEvent(event, callback)
        assertEqual(event, "PLAYER_REGEN_ENABLED", "unregistered event")
        assertEqual(callback, harness.regenCallback, "unregistered regen handler")
        record(harness, "uf.unregister", event, callback)
        harness.regenCallback = nil
    end

    local BFI = {
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        AuraContainerSortDirection = MOCK_SORT_DIRECTION,
        AuraContainerSortMethod = MOCK_SORT_METHOD,
        C_Timer = {
            After = function(delay, callback)
                assertTrue(delay == 0 or delay == 0.25, "unexpected mock timer delay")
                harness.timerCallbacks[#harness.timerCallbacks + 1] = {
                    delay = delay,
                    callback = callback,
                }
            end,
        },
        CustomAuraContainerAuraProcessingPolicy = MOCK_PROCESSING_POLICY,
        CreateFrame = function(frameType, name, parent)
            assertEqual(frameType, "Frame", "holder frame type")
            local holder = newHolder(harness, name, parent)
            record(harness, "wow.create-frame", holder, frameType, name, parent)
            return holder
        end,
        InCombatLockdown = function()
            return harness.inCombat
        end,
        assert = assert,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        pcall = pcall,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        type = type,
    }
    environment._G = environment

    local chunk, loadError = loadfile("Modules/UnitFrames/AuraController.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.UF = UF
    function harness:SetCombat(inCombat)
        self.inCombat = inCombat
    end
    function harness:FireRegen(deferTimers)
        local callback = self.regenCallback
        assertTrue(callback, "regen handler is not registered")
        callback()
        if not deferTimers then
            self:RunTimers(0)
        end
    end
    function harness:RunNextTimer()
        local timer = table.remove(self.timerCallbacks, 1)
        assertTrue(timer, "timer callback is not queued")
        timer.callback()
        return timer.delay
    end
    function harness:RunTimers(delay)
        local index = 1
        while index <= #self.timerCallbacks do
            local timer = self.timerCallbacks[index]
            if timer.delay == delay then
                table.remove(self.timerCallbacks, index)
                timer.callback()
            else
                index = index + 1
            end
        end
    end
    return harness
end

local function completeSpec(unit, enabled)
    return {
        unit = unit,
        enabled = enabled,
        shown = true,
        holder = {
            width = 120,
            height = 32,
        },
        containerPoint = {
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = 2,
            y = -3,
        },
        flowLayout = {
            axis = MOCK_FLOW_AXIS.Horizontal,
            maximumLineSize = 120,
        },
        processing = {
            policy = MOCK_PROCESSING_POLICY.ProcessAura,
            options = {
                ignoreBuffs = false,
            },
        },
        groups = {
            {
                key = "helpful",
                filterString = "HELPFUL",
                maxFrameCount = 4,
                candidateFilters = {
                    isFromPlayerOrPlayerPet = true,
                },
                sortMethod = MOCK_SORT_METHOD.BigDefensive,
                sortDirection = MOCK_SORT_DIRECTION.Reverse,
                layout = {
                    elementWidth = 20,
                    elementHeight = 20,
                },
                buttonStyle = {
                    size = 20,
                },
            },
        },
        slots = {
            {
                key = "priority",
                filterString = "HARMFUL",
                candidateFilters = {
                    isBossAura = true,
                },
                sortMethod = MOCK_SORT_METHOD.UnitFrameDebuff,
                sortDirection = MOCK_SORT_DIRECTION.Normal,
                point = {
                    point = "CENTER",
                    relativePoint = "CENTER",
                    x = 5,
                    y = 6,
                },
                buttonStyle = {
                    size = 18,
                },
            },
        },
    }
end

local function tuningSpec()
    return {
        holder = {
            width = 140,
            height = 36,
        },
        containerPoint = {
            point = "BOTTOMLEFT",
            relativePoint = "BOTTOMLEFT",
            x = 7,
            y = 8,
        },
        flowLayout = {
            axis = MOCK_FLOW_AXIS.Vertical,
            maximumLineSize = 80,
        },
        processing = {
            policy = MOCK_PROCESSING_POLICY.None,
        },
        groups = {
            {
                key = "helpful",
                filterString = "HELPFUL|PLAYER",
                maxFrameCount = 6,
                candidateFilters = {
                    canApplyAura = true,
                },
                sortMethod = MOCK_SORT_METHOD.ImportantOnly,
                sortDirection = MOCK_SORT_DIRECTION.Normal,
                layout = {
                    elementWidth = 24,
                    elementHeight = 24,
                },
            },
        },
        slots = {
            {
                key = "priority",
                filterString = "HARMFUL|RAID",
                candidateFilters = {
                    isBossOrRoleAura = true,
                },
                sortMethod = MOCK_SORT_METHOD.Expiration,
                sortDirection = MOCK_SORT_DIRECTION.Reverse,
            },
        },
    }
end

local function assertConstructionStats(harness, expected, label)
    local stats = harness.UF.GetNativeAuraConstructionStats()
    for field, expectedValue in pairs(expected) do
        assertEqual(stats[field], expectedValue, label .. " " .. field)
    end
    for field, value in pairs(stats) do
        assertEqual(type(value), "number", label .. " scalar " .. field)
    end
    return stats
end

local function testConstructionStatsContract()
    local harness = makeHarness()
    harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIConstructionStatsAuraHolder",
        completeSpec("target", true)
    )

    assertEqual(harness.afConstructionTotalsReads, 0,
        "AF totals read during construction")
    assertEqual(harness.afConstructionStatsReads, 0,
        "AF per-container stats read during construction")
    local stats = assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 0,
        destroyCompletions = 0,
        liveControllers = 1,
        seedsAllocated = 0,
        seedsClaimed = 0,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        frameworkBuilds = 1,
        adoptedBuilds = 0,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        retiredNativeShells = 0,
        retiredInitialReservations = 0,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
        afContainerCreateAttempts = 1,
        afContainerAllocations = 1,
        afContainerCreateCompletions = 1,
        afTrackedContainers = 1,
        afExternalContainersObserved = 0,
        afGroupAddAttempts = 1,
        afGroupsAdded = 1,
        afSlotAddAttempts = 1,
        afSlotsAdded = 1,
        afItemEnchantmentAddAttempts = 0,
        afItemEnchantmentsAdded = 0,
        afInitialFrameReservationsAttempted = 11,
        afInitialFrameReservationsCompleted = 11,
    }, "construction snapshot")
    assertEqual(harness.afConstructionTotalsReads, 1,
        "explicit AF totals read")
    assertEqual(harness.afConstructionStatsReads, 0,
        "unexpected AF per-container stats read")

    stats.controllersCreated = 99
    stats.afContainerAllocations = 99
    assertConstructionStats(harness, {
        controllersCreated = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        afContainerAllocations = 1,
    }, "fresh non-resetting snapshot")
    assertEqual(harness.afConstructionTotalsReads, 2,
        "second explicit AF totals read")
end

local function testCapabilityGate()
    local oldAF = makeHarness({versionNum = 33})
    assertEqual(
        oldAF.UF.HasNativeAuraContainerBackend(),
        false,
        "AF r33 block-color gate"
    )
    assertEqual(
        oldAF.UF.CreateNativeAuraContainerController({}, "OldAF"),
        nil,
        "AF r33 controller"
    )
    assertEqual(#oldAF.holders, 0, "AF r33 holder count")

    local missingMethod = makeHarness({
        missingMethod = "SetCustomAuraSlotSortMethod",
    })
    assertEqual(
        missingMethod.UF.HasNativeAuraContainerBackend(),
        false,
        "missing adapter method gate"
    )
    assertEqual(#missingMethod.holders, 0, "missing-method holder count")

    local missingConstructionMethod = makeHarness({
        missingMethod = "GetCustomAuraContainerConstructionStats",
    })
    assertEqual(
        missingConstructionMethod.UF.HasNativeAuraContainerBackend(),
        false,
        "missing construction method gate"
    )
    assertEqual(#missingConstructionMethod.holders, 0,
        "missing-construction-method holder count")
end

local function testGlobalFrameworkRequirement()
    local requiredVersion
    local stopAfterVersionCheck = {}
    local eventHandler = {}

    function eventHandler:UnregisterEvent() end

    local AF = {
        CreateSimpleEventHandler = function()
            return eventHandler
        end,
        GetAddOnVersion = function()
            return "test", 1
        end,
        GetColorTable = function()
            return {}
        end,
        RegisterCallback = function() end,
        RequireVersion = function(version)
            requiredVersion = version
            error(stopAfterVersionCheck)
        end,
        SetAddonAccentColor = function() end,
    }
    local BFI = {
        funcs = {},
        name = "BFInfinite",
        vars = {},
    }
    local environment = setmetatable({
        AbstractFramework = AF,
        C_SpecializationInfo = {
            GetNumSpecializationsForClassID = function() return 0 end,
        },
    }, {__index = _G})
    environment._G = environment

    local chunk, loadError = loadfile("Core.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
    assertEqual(BFI.requiredAFVersion, 34, "published global AF minimum")

    local ok, versionError = pcall(eventHandler.ADDON_LOADED, eventHandler, BFI.name)
    assertEqual(ok, false, "global AF version check stops harness")
    assertEqual(versionError, stopAfterVersionCheck, "global AF version check sentinel")
    assertEqual(requiredVersion, 34, "global AF minimum")
end

local function testBuildContract()
    local harness = makeHarness()
    local parent = {}
    local spec = completeSpec("target", true)
    local controller = harness.UF.CreateNativeAuraContainerController(
        parent,
        "BFITestAuraHolder",
        spec
    )

    assertEventNames(harness, {
        "wow.create-frame",
        "holder.hide",
        "holder.size",
        "af.create-container",
        "native.hide",
        "af.enabled",
        "native.clear-points",
        "native.set-point",
        "af.flow",
        "af.processing",
        "af.add-group",
        "af.add-slot",
        "slot.clear-points",
        "slot.set-point",
        "af.unit",
        "af.update",
        "af.enabled",
        "native.show",
        "holder.shown",
    })

    local holder = controller:GetFrame()
    local container = harness.containers[1]
    local group = container.groups.helpful
    local slot = container.slots.priority
    assertEqual(holder.parent, parent, "holder parent")
    assertEqual(holder.width, 120, "holder width")
    assertEqual(holder.height, 32, "holder height")
    assertEqual(holder.shown, true, "holder visibility")
    assertEqual(container.parent, holder, "native parent")
    assertEqual(container.unit, "target", "native unit")
    assertEqual(container.enabled, true, "native enabled")
    assertEqual(container.shown, true, "native visibility")
    assertEqual(container.point[2], holder, "native point owner")
    assertEqual(group.filterString, "HELPFUL", "group filter")
    assertEqual(group.options.maxFrameCount, 4, "group max")
    assertEqual(group.options.candidateFilters.isFromPlayerOrPlayerPet, true,
        "group candidate filter")
    assertEqual(group.buttonStyle.size, 20, "group button style")
    assertEqual(slot.filterString, "HARMFUL", "slot filter")
    assertEqual(slot.options.candidateFilters.isBossAura, true, "slot candidate filter")
    assertEqual(slot.buttonStyle.size, 18, "slot button style")
    assertEqual(slot.options.anchor.point, "CENTER", "slot initializer anchor point")
    assertEqual(slot.options.anchor.relativeTo, holder,
        "slot initializer anchor owner")
    assertEqual(slot.options.anchor.relativePoint, "CENTER",
        "slot initializer relative point")
    assertEqual(slot.options.anchor.x, 5, "slot initializer anchor x")
    assertEqual(slot.options.anchor.y, 6, "slot initializer anchor y")
    assertEqual(slot.button.point[2], holder, "slot point owner")

    assertTrue(group.options ~= spec.groups[1], "group options were not normalized")
    assertTrue(
        group.options.candidateFilters ~= spec.groups[1].candidateFilters,
        "group candidate filters were not copied"
    )
    assertTrue(
        slot.buttonStyle ~= spec.slots[1].buttonStyle,
        "slot style was not copied"
    )
end

local function testTuningContract()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFITuningAuraHolder",
        completeSpec("target", true)
    )
    local container = harness.containers[1]
    local holder = controller:GetFrame()
    local constructionBefore = harness.UF.GetNativeAuraConstructionStats()

    clearEvents(harness)
    controller:ApplyTuning(tuningSpec())

    assertEventNames(harness, {
        "holder.shown",
        "holder.size",
        "native.clear-points",
        "native.set-point",
        "af.flow",
        "af.processing",
        "af.group.filter",
        "af.group.max",
        "af.group.candidates",
        "af.group.sort",
        "af.group.layout",
        "af.slot.filter",
        "af.slot.candidates",
        "af.slot.sort",
        "af.update",
        "holder.shown",
    })
    assertEqual(#harness.containers, 1, "tuning container count")
    assertEqual(countEvents(harness, "af.add-group"), 0, "tuning group additions")
    assertEqual(countEvents(harness, "af.add-slot"), 0, "tuning slot additions")
    assertEqual(holder.width, 140, "tuned holder width")
    assertEqual(holder.height, 36, "tuned holder height")
    assertEqual(container.groups.helpful.filterString, "HELPFUL|PLAYER",
        "tuned group filter")
    assertEqual(container.groups.helpful.options.maxFrameCount, 6, "tuned group max")
    assertEqual(container.slots.priority.filterString, "HARMFUL|RAID",
        "tuned slot filter")
    controller:Refresh()
    local constructionAfter = assertConstructionStats(harness, {
        controllersCreated = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
        afContainerAllocations = 1,
        afGroupsAdded = 1,
        afSlotsAdded = 1,
        afInitialFrameReservationsCompleted = 11,
    }, "tuning construction stability")
    for field, beforeValue in pairs(constructionBefore) do
        assertEqual(constructionAfter[field], beforeValue,
            "tuning/refresh construction delta " .. field)
    end
end

local function testHolderConfigQueue()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIHolderConfigAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()

    clearEvents(harness)
    controller:ApplyHolderConfig(function(configuredHolder)
        assertEqual(configuredHolder, holder, "configured holder")
        record(harness, "holder.config", configuredHolder, "initial")
    end)
    assertEventNames(harness, {
        "holder.shown",
        "holder.config",
        "holder.shown",
    })
    assertEqual(holder.shown, true, "holder config restored visibility")

    clearEvents(harness)
    harness:SetCombat(true)
    controller:ApplyHolderConfig(function(configuredHolder)
        record(harness, "holder.config", configuredHolder, "stale")
    end)
    controller:ApplyHolderConfig(function(configuredHolder)
        record(harness, "holder.config", configuredHolder, "latest")
    end)
    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
    })
    assertEqual(countEvents(harness, "holder.config"), 0,
        "combat holder configuration")

    harness:SetCombat(false)
    harness:FireRegen()
    assertEqual(countEvents(harness, "holder.config"), 1,
        "coalesced holder configuration")
    local configEvent = findEvent(harness, "holder.config")
    assertEqual(configEvent.args[2], "latest", "latest holder configuration")
    assertEqual(holder.shown, true, "deferred holder config visibility")

    local unbuilt = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIUnbuiltHolderConfigAuraHolder"
    )
    local unbuiltHolder = unbuilt:GetFrame()
    clearEvents(harness)
    unbuilt:ApplyHolderConfig(function(configuredHolder)
        record(harness, "holder.config", configuredHolder, "unbuilt")
    end)
    assertEventNames(harness, {
        "holder.config",
    })
    assertEqual(unbuiltHolder.shown, false, "unbuilt holder visibility")
end

local function testSharedCombatQueue()
    local harness = makeHarness()
    local first = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIFirstAuraHolder",
        completeSpec("target", true)
    )
    local second = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFISecondAuraHolder"
    )
    local firstContainer = harness.containers[1]

    clearEvents(harness)
    harness:SetCombat(true)
    first:ApplyTuning(tuningSpec())
    first:SetUnit("focus")
    first:SetEnabled(false)
    first:SetShown(false)
    second:Rebuild(completeSpec("party2", true))
    second:Rebuild(completeSpec("party3", false))

    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
    })
    assertEqual(firstContainer.unit, "target", "combat retarget mutation")
    assertEqual(firstContainer.enabled, true, "combat enabled mutation")
    assertEqual(first:GetFrame().shown, false, "combat stale-display suppression")
    assertEqual(second:GetFrame().shown, false,
        "combat initial-build display suppression")
    assertEqual(#harness.containers, 1, "combat initial-build mutation")
    assertConstructionStats(harness, {
        controllersCreated = 2,
        liveControllers = 2,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        frameworkBuilds = 1,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        afContainerAllocations = 1,
    }, "combat deferred construction")

    harness:SetCombat(false)
    harness:FireRegen()

    assertEqual(countEvents(harness, "uf.register"), 1, "shared regen registrations")
    assertEqual(countEvents(harness, "uf.unregister"), 1, "shared regen unregistrations")
    assertEqual(countEvents(harness, "af.create-container"), 1,
        "coalesced initial-build count")
    assertEqual(firstContainer.unit, "focus", "deferred retarget")
    assertEqual(firstContainer.enabled, false, "deferred enabled")
    assertEqual(first:GetFrame().shown, false, "deferred holder visibility")
    assertEqual(firstContainer.groups.helpful.filterString, "HELPFUL|PLAYER",
        "deferred tuning")

    local initialContainer = harness.containers[2]
    assertEqual(initialContainer.parent, second:GetFrame(), "initial-build owner")
    assertEqual(initialContainer.unit, "party3", "latest initial-build unit")
    assertEqual(initialContainer.enabled, false, "latest initial-build enabled")
    assertEqual(harness.regenCallback, nil, "regen handler after flush")
    assertConstructionStats(harness, {
        controllersCreated = 2,
        liveControllers = 2,
        buildAttempts = 2,
        buildCompletions = 2,
        incompleteBuilds = 0,
        frameworkBuilds = 2,
        expectedGroups = 2,
        expectedSlots = 2,
        expectedInitialReservations = 22,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
        afContainerAllocations = 2,
        afGroupsAdded = 2,
        afSlotsAdded = 2,
        afInitialFrameReservationsCompleted = 22,
    }, "regen completed construction")
end

local function testRegenDispatchIsolation()
    local harness = makeHarness()
    local first = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIFailingAuraHolder",
        completeSpec("target", true)
    )
    local second = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFISurvivingAuraHolder",
        completeSpec("party1", true)
    )
    local firstContainer = harness.containers[1]
    local secondContainer = harness.containers[2]

    clearEvents(harness)
    harness:SetCombat(true)
    first:SetUnit("focus")
    second:SetUnit("party2")
    firstContainer.failSetUnit = true
    harness:SetCombat(false)
    harness:FireRegen(true)

    assertEqual(#harness.timerCallbacks, 2, "isolated regen dispatch count")
    local failureCount = 0
    while #harness.timerCallbacks > 0 do
        -- Test-only pcall observes an injected, deterministic configuration
        -- failure; production native work is deliberately not wrapped.
        local succeeded = pcall(harness.RunNextTimer, harness)
        if not succeeded then
            failureCount = failureCount + 1
        end
    end

    assertEqual(failureCount, 1, "isolated regen failure count")
    assertEqual(firstContainer.unit, "target", "failed controller unit")
    assertEqual(first:GetFrame().shown, false, "failed controller fail-closed state")
    assertEqual(secondContainer.unit, "party2", "surviving controller unit")
    assertEqual(second:GetFrame().shown, true, "surviving controller visibility")
    assertTrue(harness.regenCallback, "failing controller regen retention")
end

local function testRebuildRejectsAfterInitialBuild()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFISingleBuildAuraHolder",
        completeSpec("target", true)
    )
    local container = harness.containers[1]
    local group = container.groups.helpful
    local slot = container.slots.priority
    local button = slot.button

    clearEvents(harness)
    local accepted, message = pcall(
        controller.Rebuild,
        controller,
        completeSpec("focus", false)
    )

    assertEqual(accepted, false, "second rebuild acceptance")
    assertTrue(
        tostring(message):find("initial build already attempted", 1, true) ~= nil,
        "second rebuild assertion"
    )
    assertEqual(#harness.events, 0, "second rebuild native mutations")
    assertEqual(#harness.containers, 1, "second rebuild container allocation")
    assertEqual(#harness.slotButtons, 1, "second rebuild button allocation")
    assertEqual(controller._container, container, "second rebuild controller container")
    assertEqual(container.groups.helpful, group, "second rebuild group")
    assertEqual(container.slots.priority, slot, "second rebuild slot")
    assertEqual(container.slots.priority.button, button, "second rebuild button")
    assertEqual(container.unit, "target", "second rebuild unit mutation")
    assertEqual(container.enabled, true, "second rebuild enabled mutation")
    assertEqual(group.filterString, "HELPFUL", "second rebuild group mutation")
    assertEqual(slot.filterString, "HARMFUL", "second rebuild slot mutation")

    controller:ApplyTuning(tuningSpec())

    assertEqual(#harness.containers, 1, "post-rejection tuning container count")
    assertEqual(#harness.slotButtons, 1, "post-rejection tuning button count")
    assertEqual(countEvents(harness, "af.create-container"), 0,
        "post-rejection tuning container allocation")
    assertEqual(countEvents(harness, "af.add-group"), 0,
        "post-rejection tuning group addition")
    assertEqual(countEvents(harness, "af.add-slot"), 0,
        "post-rejection tuning slot addition")
    assertEqual(group.filterString, "HELPFUL|PLAYER",
        "post-rejection group tuning")
    assertEqual(slot.filterString, "HARMFUL|RAID",
        "post-rejection slot tuning")
end

local function assertMidBuildFailureIsOneShot(
    harness,
    controller,
    expectedContainer,
    expectedCreateCount,
    label
)
    clearEvents(harness)
    local built, buildMessage = pcall(
        controller.Rebuild,
        controller,
        completeSpec("party1", true)
    )

    assertEqual(built, false, label .. " injected build acceptance")
    assertTrue(
        tostring(buildMessage):find("injected non-secret SetUnit failure", 1, true)
            ~= nil,
        label .. " injected build failure"
    )
    expectedContainer = expectedContainer or harness.containers[1]
    assertEqual(controller._buildAttempted, true, label .. " build-attempt latch")
    assertEqual(controller._seedContainer, nil, label .. " consumed seed")
    assertEqual(controller._container, expectedContainer, label .. " claimed container")
    assertEqual(#harness.containers, 1, label .. " initial container count")
    assertEqual(#harness.slotButtons, 1, label .. " initial button count")
    assertEqual(countEvents(harness, "af.create-container"), expectedCreateCount,
        label .. " initial container allocations")
    assertEqual(countEvents(harness, "af.add-group"), 1,
        label .. " initial group allocations")
    assertEqual(countEvents(harness, "af.add-slot"), 1,
        label .. " initial slot allocations")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 0,
        destroyCompletions = 0,
        liveControllers = 1,
        seedsAllocated = 0,
        seedsClaimed = expectedCreateCount == 0 and 1 or 0,
        buildAttempts = 1,
        buildCompletions = 0,
        incompleteBuilds = 1,
        frameworkBuilds = 0,
        adoptedBuilds = 0,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        retiredNativeShells = 0,
        retiredInitialReservations = 0,
        strandedNativeShells = 1,
        strandedInitialReservations = 11,
        afContainerAllocations = 1,
        afGroupsAdded = 1,
        afSlotsAdded = 1,
        afInitialFrameReservationsCompleted = 11,
    }, label .. " incomplete construction")

    local group = expectedContainer.groups.helpful
    local slot = expectedContainer.slots.priority
    local button = slot.button
    expectedContainer.failSetUnit = nil
    clearEvents(harness)

    local rebuilt, rebuildMessage = pcall(
        controller.Rebuild,
        controller,
        completeSpec("party2", false)
    )
    assertEqual(rebuilt, false, label .. " public retry acceptance")
    assertTrue(
        tostring(rebuildMessage):find("initial build already attempted", 1, true)
            ~= nil,
        label .. " public retry assertion"
    )

    local internalRetry, internalMessage = pcall(
        controller._Build,
        controller
    )
    assertEqual(internalRetry, false, label .. " internal retry acceptance")
    assertTrue(
        tostring(internalMessage):find("initial build already attempted", 1, true)
            ~= nil,
        label .. " internal retry assertion"
    )
    assertEqual(#harness.events, 0, label .. " retry native mutations")
    assertEqual(#harness.containers, 1, label .. " retry container count")
    assertEqual(#harness.slotButtons, 1, label .. " retry button count")
    assertEqual(expectedContainer.groups.helpful, group, label .. " retry group")
    assertEqual(expectedContainer.slots.priority, slot, label .. " retry slot")
    assertEqual(expectedContainer.slots.priority.button, button,
        label .. " retry button")

    controller:Destroy()
    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 1,
        destroyCompletions = 1,
        liveControllers = 0,
        buildAttempts = 1,
        buildCompletions = 0,
        incompleteBuilds = 1,
        frameworkBuilds = 0,
        adoptedBuilds = 0,
        retiredNativeShells = 1,
        retiredInitialReservations = 11,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, label .. " retired incomplete construction")
end

local function testMidBuildFailureIsOneShot()
    local createdHarness = makeHarness({
        failCreatedContainerSetUnit = true,
    })
    local createdController = createdHarness.UF.CreateNativeAuraContainerController(
        {},
        "BFIFailingCreatedAuraHolder"
    )
    assertMidBuildFailureIsOneShot(
        createdHarness,
        createdController,
        createdHarness.containers[1],
        1,
        "created"
    )

    local seededHarness = makeHarness()
    local root = {}
    local seed = seededHarness.AF.CreateCustomAuraContainer(root)
    seed.failSetUnit = true
    local seededController =
        seededHarness.UF.CreateNativeGroupAuraContainerController(
            root,
            "BFIFailingSeededAuraHolder",
            seed
        )
    assertMidBuildFailureIsOneShot(
        seededHarness,
        seededController,
        seed,
        0,
        "seeded"
    )
end

local function testPartialAddFailureDiagnostics()
    local harness = makeHarness({
        failSlotAdd = true,
    })
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIPartialAddFailureAuraHolder"
    )

    -- Test-only pcall observes an injected non-secret adapter failure.
    -- Production construction remains unwrapped and fail-closed.
    local succeeded, message = pcall(
        controller.Rebuild,
        controller,
        completeSpec("target", true)
    )
    assertEqual(succeeded, false, "partial AddSlot failure acceptance")
    assertTrue(
        tostring(message):find("injected non-secret AddSlot failure", 1, true)
            ~= nil,
        "partial AddSlot failure"
    )
    assertEqual(#harness.slotButtons, 0, "partial AddSlot button allocation")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        liveControllers = 1,
        buildAttempts = 1,
        buildCompletions = 0,
        incompleteBuilds = 1,
        frameworkBuilds = 0,
        adoptedBuilds = 0,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        retiredNativeShells = 0,
        retiredInitialReservations = 0,
        strandedNativeShells = 1,
        strandedInitialReservations = 10,
        afGroupAddAttempts = 1,
        afGroupsAdded = 1,
        afSlotAddAttempts = 1,
        afSlotsAdded = 0,
        afInitialFrameReservationsAttempted = 11,
        afInitialFrameReservationsCompleted = 10,
    }, "partial AddSlot construction gap")
    assertEqual(harness.afConstructionStatsReads, 0,
        "partial failure per-container stats read")

    controller:Destroy()
    assertConstructionStats(harness, {
        destroyRequests = 1,
        destroyCompletions = 1,
        liveControllers = 0,
        incompleteBuilds = 1,
        retiredNativeShells = 1,
        retiredInitialReservations = 10,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
        afInitialFrameReservationsAttempted = 11,
        afInitialFrameReservationsCompleted = 10,
    }, "retired partial AddSlot construction")
end

local function testVisibilityUsesWriteLedger()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIOpaqueVisibilityAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()
    local container = harness.containers[1]

    harness.recordAlpha = true
    clearEvents(harness)
    controller:ApplyTuning(tuningSpec())

    assertEqual(#harness.timerCallbacks, 0, "visibility retry count")
    assertEqual(#harness.containers, 1, "tuning container count")
    assertEqual(container.groups.helpful.filterString, "HELPFUL|PLAYER",
        "write-only tuning")
    assertEqual(holder.shown, true, "holder visibility")
    assertEqual(holder.alpha, 1, "holder curtain restoration")
    assertEqual(controller:IsPresentationApplied(), true,
        "applied presentation state")
    assertEqual(harness.events[1].name, "holder.alpha",
        "holder curtain precedes hide")
    assertEqual(harness.events[1].args[2], 0, "holder curtain alpha")
    assertEqual(harness.events[2].name, "holder.shown", "holder hide order")
    assertEqual(harness.events[2].args[2], false, "holder hide state")
    assertEqual(harness.events[#harness.events].name, "holder.alpha",
        "holder uncurtains after restore")
    assertEqual(harness.events[#harness.events].args[2], 1,
        "holder restored alpha")
end

local function testHideReversalUsesWriteLedger()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIWriteLedgerReversalAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()

    clearEvents(harness)
    controller:SetShown(false)

    assertEqual(holder.alpha, 0, "hidden holder remains curtained")
    assertEqual(holder.shown, false, "hidden holder state")
    assertEqual(controller:IsPresentationApplied(), false,
        "hidden presentation state")
    assertEqual(#harness.timerCallbacks, 0, "hidden holder retry count")

    controller:SetShown(true)
    assertEqual(holder.alpha, 1, "restored holder alpha")
    assertEqual(holder.shown, true, "restored holder visibility")
    assertEqual(controller:IsPresentationApplied(), true,
        "restored presentation state")
    assertEqual(#harness.timerCallbacks, 0, "restored holder retry count")
end

local function testDestroyCompletesWithoutVisibilityRead()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIWriteLedgerDestroyAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()

    clearEvents(harness)
    controller:Destroy()

    assertEqual(holder.alpha, 0, "destroyed holder remains curtained")
    assertEqual(holder.shown, false, "destroyed holder visibility")
    assertEqual(controller:IsPresentationApplied(), false,
        "destroyed presentation state")
    assertEqual(#harness.timerCallbacks, 0, "destroy retry count")
end

local function testProductionAvoidsVisibilityInspection()
    local file = assert(io.open("Modules/UnitFrames/AuraController.lua", "r"))
    local source = file:read("*a")
    file:close()

    for _, method in ipairs({"IsShown", "IsVisible", "IsMouseOver", "GetAlpha"}) do
        assertEqual(
            source:find(":" .. method .. "%(", 1),
            nil,
            "forbidden visibility inspection " .. method
        )
    end
end

local function testMaxFrameCountContract()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIMaxAuraHolder"
    )
    local spec = completeSpec("target", true)
    spec.groups[1].maxFrameCount = 1.5

    -- Test-only pcall observes a deterministic configuration assertion; it
    -- does not probe API availability, protected state, or secret values.
    local accepted, message = pcall(controller.Rebuild, controller, spec)
    assertEqual(accepted, false, "fractional maxFrameCount acceptance")
    assertTrue(
        tostring(message):find("non%-negative integer or infinity") ~= nil,
        "fractional maxFrameCount assertion"
    )
    assertEqual(#harness.containers, 0, "fractional maxFrameCount native mutation")
end

local function testDestroyPrecedence()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIDestroyAuraHolder",
        completeSpec("target", true)
    )
    local container = harness.containers[1]

    clearEvents(harness)
    harness:SetCombat(true)
    controller:ApplyTuning(tuningSpec())
    controller:Destroy()

    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
    })
    assertEqual(container.enabled, true, "combat destroy enabled mutation")
    assertEqual(container.shown, true, "combat destroy visibility mutation")
    assertEqual(controller:GetFrame().shown, false, "combat destroy display suppression")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 1,
        destroyCompletions = 0,
        liveControllers = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        retiredNativeShells = 0,
        retiredInitialReservations = 0,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, "combat destroy request")

    harness:SetCombat(false)
    harness:FireRegen()
    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
        "af.enabled",
        "native.hide",
        "uf.unregister",
    })
    assertEqual(#harness.containers, 1, "destroy rebuilt a container")
    assertEqual(container.enabled, false, "destroy container enabled")
    assertEqual(container.shown, false, "destroy container visibility")
    assertEqual(controller:GetFrame().shown, false, "destroy holder visibility")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 1,
        destroyCompletions = 1,
        liveControllers = 0,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        retiredNativeShells = 1,
        retiredInitialReservations = 11,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, "completed destroy")
end

local function testOutOfBandOOCFlushUnregisters()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIOOCAuraHolder",
        completeSpec("target", true)
    )

    clearEvents(harness)
    harness:SetCombat(true)
    controller:SetUnit("focus")
    harness:SetCombat(false)
    controller:SetUnit("mouseover")

    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
        "af.unit",
        "af.update",
        "holder.shown",
        "uf.unregister",
    })
    assertEqual(harness.containers[1].unit, "mouseover", "out-of-band retarget")
    assertEqual(controller:GetFrame().shown, true, "out-of-band holder visibility")
    assertEqual(harness.regenCallback, nil, "out-of-band regen handler")
end

local function testRefreshIsDirectDirtyMark()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIRefreshAuraHolder",
        completeSpec("target", true)
    )
    local container = harness.containers[1]

    clearEvents(harness)
    harness:SetCombat(true)
    controller:Refresh()

    assertEventNames(harness, {
        "af.update",
    })
    assertEqual(harness.events[1].args[1], container, "refresh container")
    assertEqual(harness.regenCallback, nil, "refresh regen handler")
end

local function testGroupHeaderCapabilityAndSeed()
    local unavailable = makeHarness({
        hasBackend = false,
    })
    local unavailableHeader = {
        attributes = {},
    }
    function unavailableHeader:SetAttribute(key, value)
        self.attributes[key] = value
    end

    assertEqual(
        unavailable.UF.PrepareNativeGroupAuraHeader(unavailableHeader),
        false,
        "unavailable group header capability"
    )
    assertEqual(
        unavailableHeader.attributes.auraContainerTemplate,
        nil,
        "12.0.7 group header attribute"
    )
    assertEqual(
        unavailable.UF.CreateNativeGroupAuraContainerSeed({}),
        nil,
        "12.0.7 extra group seed"
    )
    assertEqual(#unavailable.containers, 0, "12.0.7 native allocation")
    assertConstructionStats(unavailable, {
        controllersCreated = 0,
        seedsAllocated = 0,
        seedsClaimed = 0,
        buildAttempts = 0,
        buildCompletions = 0,
        retiredNativeShells = 0,
        strandedNativeShells = 0,
        afContainerAllocations = 0,
    }, "unavailable seed construction")

    local harness = makeHarness()
    local header = {
        attributes = {},
    }
    function header:SetAttribute(key, value)
        self.attributes[key] = value
        record(harness, "header.attribute", self, key, value)
    end

    assertEqual(
        harness.UF.PrepareNativeGroupAuraHeader(header),
        true,
        "12.1 group header capability"
    )
    assertEqual(
        header.attributes.auraContainerTemplate,
        "CustomAuraContainerTemplate",
        "12.1 group header template"
    )

    local parent = {}
    local seed = harness.UF.CreateNativeGroupAuraContainerSeed(parent)
    assertEqual(seed, harness.containers[1], "created group seed")
    assertEqual(seed.parent, parent, "group seed parent")
    assertEqual(seed.shown, false, "group seed initial visibility")
    assertEqual(seed.enabled, false, "group seed initial enabled state")
    assertConstructionStats(harness, {
        controllersCreated = 0,
        liveControllers = 0,
        seedsAllocated = 1,
        seedsClaimed = 0,
        buildAttempts = 0,
        buildCompletions = 0,
        retiredNativeShells = 0,
        strandedNativeShells = 0,
        afContainerAllocations = 1,
        afGroupsAdded = 0,
        afSlotsAdded = 0,
    }, "allocated seed construction")
end

local function testGroupSeedAdoptionAndOneShotClaim()
    local harness = makeHarness()
    local root = {}
    local seed = harness.AF.CreateCustomAuraContainer(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFIGroupAuraHolder",
        seed,
        completeSpec("party1", true)
    )

    assertEqual(#harness.containers, 1, "seeded build allocation count")
    assertEqual(controller._container, seed, "adopted group seed")
    assertEqual(controller._seedContainer, nil, "consumed group seed")
    assertEqual(controller._containerIsExternal, true,
        "external group container")
    assertEqual(seed.parent, root, "adopted seed parent")
    assertEqual(seed.point[2], controller:GetFrame(),
        "seed position relative to holder")
    assertEqual(seed.unit, "party1", "seeded build unit")
    assertEqual(seed.enabled, true, "seeded build enabled")
    assertEqual(seed.shown, true, "seeded build visibility")
    assertEqual(seed.alpha, 1, "seeded build curtain restoration")
    assertEqual(controller:GetFrame().shown, true,
        "seeded holder visibility")
    assertEqual(countEvents(harness, "af.frame-level"), 1,
        "seeded build layer synchronization")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        liveControllers = 1,
        seedsAllocated = 0,
        seedsClaimed = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        frameworkBuilds = 0,
        adoptedBuilds = 1,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        retiredNativeShells = 0,
        strandedNativeShells = 0,
        afContainerAllocations = 1,
        afInitialFrameReservationsCompleted = 11,
    }, "adopted seed construction")

    clearEvents(harness)
    controller:ApplyHolderConfig(function(holder)
        holder.frameLevel = 27
        holder.frameStrata = "HIGH"
    end)
    assertEqual(seed.frameLevel, 28, "seeded updated frame level")
    assertEqual(seed.frameStrata, "HIGH", "seeded updated frame strata")
    assertEqual(countEvents(harness, "af.frame-level"), 1,
        "seeded holder update layer synchronization")

    local accepted, message = pcall(
        harness.UF.CreateNativeGroupAuraContainerController,
        {},
        "BFIDuplicateGroupAuraHolder",
        seed
    )
    assertEqual(accepted, false, "duplicate seed claim acceptance")
    assertTrue(
        tostring(message):find("already claimed", 1, true) ~= nil,
        "duplicate seed claim assertion"
    )
    assertEqual(#harness.holders, 1, "duplicate claim holder allocation")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        seedsClaimed = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        adoptedBuilds = 1,
    }, "duplicate seed claim stability")
end

local function testGroupSeedBuildQueuesInCombat()
    local harness = makeHarness()
    local root = {}
    local seed = harness.AF.CreateCustomAuraContainer(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFICombatBootstrapAuraHolder",
        seed
    )
    assertEqual(seed.alpha, 0, "claimed seed is immediately curtained")

    clearEvents(harness)
    harness:SetCombat(true)
    controller:ApplyHolderConfig(function(holder)
        holder.bootstrapConfigured = true
        holder.frameLevel = 11
    end)
    assertTrue(harness.regenCallback, "bootstrap holder regen registration")

    controller:Rebuild(completeSpec("party3", true))
    assertEqual(controller._container, nil, "combat bootstrap container")
    assertEqual(next(seed.groups), nil, "combat bootstrap group declaration")
    assertEqual(next(seed.slots), nil, "combat bootstrap slot declaration")
    assertEqual(seed.alpha, 0, "combat bootstrap seed stays curtained")
    assertEqual(controller:GetFrame().bootstrapConfigured, nil,
        "combat bootstrap holder configuration")
    assertEqual(countEvents(harness, "af.frame-level"), 0,
        "combat bootstrap external frame level")
    assertTrue(harness.regenCallback, "combat bootstrap regen registration")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        seedsClaimed = 1,
        buildAttempts = 0,
        buildCompletions = 0,
        expectedGroups = 0,
        expectedSlots = 0,
        expectedInitialReservations = 0,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, "combat queued seed construction")

    harness:SetCombat(false)
    harness:FireRegen()
    assertEqual(#harness.containers, 1, "bootstrap allocation count")
    assertEqual(countEvents(harness, "af.create-container"), 0,
        "bootstrap ordinary container allocation")
    assertEqual(seed.unit, "party3", "bootstrap unit")
    assertEqual(seed.enabled, true, "bootstrap enabled")
    assertEqual(seed.shown, true, "bootstrap visibility")
    assertEqual(seed.alpha, 1, "bootstrap curtain restoration")
    assertEqual(controller:GetFrame().shown, true,
        "bootstrap holder visibility")
    assertEqual(controller:GetFrame().bootstrapConfigured, true,
        "bootstrap holder configuration")
    assertTrue(seed.groups.helpful, "bootstrap group declaration")
    assertTrue(seed.slots.priority, "bootstrap slot declaration")
    assertEqual(seed.frameLevel, 12, "bootstrap external frame level")
    assertEqual(harness.regenCallback, nil,
        "bootstrap stale regen registration")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        seedsClaimed = 1,
        buildAttempts = 1,
        buildCompletions = 1,
        incompleteBuilds = 0,
        frameworkBuilds = 0,
        adoptedBuilds = 1,
        expectedGroups = 1,
        expectedSlots = 1,
        expectedInitialReservations = 11,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, "regen adopted seed construction")
end

local function testUnusedSeedDestroyAccounting()
    local harness = makeHarness()
    local root = {}
    local seed = harness.UF.CreateNativeGroupAuraContainerSeed(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFIUnusedSeedAuraHolder",
        seed
    )
    assertEqual(seed.alpha, 0, "unused claimed seed is curtained")

    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 0,
        destroyCompletions = 0,
        liveControllers = 1,
        seedsAllocated = 1,
        seedsClaimed = 1,
        buildAttempts = 0,
        buildCompletions = 0,
        incompleteBuilds = 0,
        retiredNativeShells = 0,
        retiredInitialReservations = 0,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
    }, "claimed unused seed")

    controller:Destroy()
    assertEqual(seed.enabled, false, "unused seed retired enabled state")
    assertEqual(seed.shown, false, "unused seed retired visibility")
    assertEqual(seed.alpha, 0, "unused seed remains curtained")
    assertConstructionStats(harness, {
        controllersCreated = 1,
        destroyRequests = 1,
        destroyCompletions = 1,
        liveControllers = 0,
        seedsAllocated = 1,
        seedsClaimed = 1,
        buildAttempts = 0,
        buildCompletions = 0,
        incompleteBuilds = 0,
        retiredNativeShells = 1,
        retiredInitialReservations = 0,
        strandedNativeShells = 0,
        strandedInitialReservations = 0,
        afContainerAllocations = 1,
        afInitialFrameReservationsCompleted = 0,
    }, "retired unused seed")
end

local function testGroupCombatLiveRetarget()
    local harness = makeHarness()
    local root = {}
    local seed = harness.AF.CreateCustomAuraContainer(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFILiveGroupAuraHolder",
        seed,
        completeSpec("party1", true)
    )

    clearEvents(harness)
    harness:SetCombat(true)
    controller:SetUnit("party4")

    assertEventNames(harness, {
        "native.hide",
        "holder.shown",
        "af.unit",
        "af.update",
        "holder.shown",
        "native.show",
    })
    assertEqual(seed.unit, "party4", "combat-live group unit")
    assertEqual(seed.shown, true, "combat-live group visibility")
    assertEqual(controller:GetFrame().shown, true,
        "combat-live holder visibility")
    assertEqual(harness.regenCallback, nil,
        "combat-live retarget regen registration")
end

local function testGroupRetargetPrecedesStructuralTuning()
    local harness = makeHarness()
    local root = {}
    local seed = harness.AF.CreateCustomAuraContainer(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFIStructuralGroupAuraHolder",
        seed,
        completeSpec("party1", true)
    )

    harness.recordAlpha = true
    clearEvents(harness)
    harness:SetCombat(true)
    controller:ApplyTuning(tuningSpec())
    controller:SetUnit("party2")

    assertEqual(seed.unit, "party2", "pending tuning live unit")
    assertEqual(seed.shown, false, "pending tuning seed visibility")
    assertEqual(controller:GetFrame().shown, false,
        "pending tuning holder visibility")
    assertEqual(seed.alpha, 0, "pending tuning seed curtain")
    assertEqual(controller:GetFrame().alpha, 0,
        "pending tuning holder curtain")
    local _, holderCurtainIndex = findEvent(harness, "holder.alpha")
    local _, seedCurtainIndex = findEvent(harness, "native.alpha")
    local _, seedHideIndex = findEvent(harness, "native.hide")
    local _, retargetIndex = findEvent(harness, "af.unit")
    assertTrue(holderCurtainIndex < seedHideIndex,
        "holder curtain precedes protected seed hide")
    assertTrue(seedCurtainIndex < seedHideIndex,
        "seed curtain precedes protected seed hide")
    assertTrue(seedHideIndex < retargetIndex,
        "seed hide precedes combat-live retarget")
    assertTrue(harness.regenCallback, "pending tuning regen registration")
    assertEqual(countEvents(harness, "af.create-container"), 0,
        "combat structural allocation")
    assertEqual(countEvents(harness, "af.unit"), 1,
        "combat structural live retarget count")

    harness:SetCombat(false)
    harness:FireRegen()
    assertEqual(#harness.containers, 1, "regen tuning container count")
    assertEqual(seed.unit, "party2", "regen tuned unit")
    assertEqual(seed.enabled, true, "regen tuned enabled")
    assertEqual(seed.shown, true, "regen tuned visibility")
    assertEqual(seed.alpha, 1, "regen tuned seed curtain restoration")
    assertEqual(controller:GetFrame().alpha, 1,
        "regen tuned holder curtain restoration")
    assertEqual(seed.groups.helpful.filterString, "HELPFUL|PLAYER",
        "regen group tuning")
    assertEqual(controller:GetFrame().shown, true,
        "regen tuned holder visibility")
end

local function testGroupVisibilityDoesNotProbeFrameState()
    local harness = makeHarness()
    local root = {}
    local seed = harness.AF.CreateCustomAuraContainer(root)
    local controller = harness.UF.CreateNativeGroupAuraContainerController(
        root,
        "BFIHoveredGroupAuraHolder",
        seed,
        completeSpec("party1", true)
    )

    clearEvents(harness)
    controller:GetFrame().IsShown = function()
        error("forbidden IsShown visibility read")
    end
    controller:GetFrame().IsMouseOver = function()
        error("forbidden IsMouseOver visibility read")
    end
    controller:SetShown(false)

    assertEqual(seed.shown, false, "group seed visibility")
    assertEqual(controller:GetFrame().shown, false,
        "group holder visibility")
    assertEqual(controller:GetFrame().alpha, 0,
        "hidden group holder remains curtained")
    assertEqual(seed.alpha, 0,
        "hidden external container remains curtained")
    assertEqual(controller:IsPresentationApplied(), false,
        "hidden external presentation state")
    assertEqual(countEvents(harness, "native.hide"), 1,
        "native visibility mutation")
    assertEqual(#harness.timerCallbacks, 0,
        "group visibility retry")
end

testConstructionStatsContract()
testGlobalFrameworkRequirement()
testCapabilityGate()
testBuildContract()
testTuningContract()
testHolderConfigQueue()
testSharedCombatQueue()
testRegenDispatchIsolation()
testRebuildRejectsAfterInitialBuild()
testMidBuildFailureIsOneShot()
testPartialAddFailureDiagnostics()
testVisibilityUsesWriteLedger()
testHideReversalUsesWriteLedger()
testDestroyCompletesWithoutVisibilityRead()
testProductionAvoidsVisibilityInspection()
testMaxFrameCountContract()
testDestroyPrecedence()
testOutOfBandOOCFlushUnregisters()
testRefreshIsDirectDirtyMark()
testGroupHeaderCapabilityAndSeed()
testGroupSeedAdoptionAndOneShotClaim()
testGroupSeedBuildQueuesInCombat()
testUnusedSeedDestroyAccounting()
testGroupCombatLiveRetarget()
testGroupRetargetPrecedesStructuralTuning()
testGroupVisibilityDoesNotProbeFrameState()

print("unit_frame_aura_controller_test.lua: ok")
