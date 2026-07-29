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
        return self.shown == true
    end

    function holder:IsMouseOver()
        return self.mouseOver == true
    end

    function holder:SetShown(shown)
        record(harness, "holder.shown", self, shown)
        if self.blockSetShown then return end
        self.shown = shown
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
    }
    local AF = {
        isRetail = options.isRetail ~= false,
        versionNum = options.versionNum or 30,
    }
    local UF = {}

    function AF.Copy(value)
        return copy(value)
    end

    function AF.SetSize(frame, width, height)
        frame._width = width
        frame._height = height
        frame:SetSize(width, height)
    end

    function AF.HasCustomAuraContainer()
        return options.hasBackend ~= false
    end

    function AF.CreateCustomAuraContainer(parent)
        local container = newContainer(harness, parent)
        record(harness, "af.create-container", container, parent)
        return container
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
        validateSort(slotOptions.sortMethod, slotOptions.sortDirection)
        local button = newSlotButton(harness, container, key)
        container.slots[key] = {
            filterString = filterString,
            options = slotOptions,
            buttonStyle = buttonStyle,
            button = button,
        }
        record(
            harness,
            "af.add-slot",
            container,
            key,
            filterString,
            slotOptions,
            buttonStyle
        )
        return button
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

local function testCapabilityGate()
    local oldAF = makeHarness({versionNum = 29})
    assertEqual(oldAF.UF.HasNativeAuraContainerBackend(), false, "old AF gate")
    assertEqual(
        oldAF.UF.CreateNativeAuraContainerController({}, "OldAF"),
        nil,
        "old AF controller"
    )
    assertEqual(#oldAF.holders, 0, "old AF holder count")

    local missingMethod = makeHarness({
        missingMethod = "SetCustomAuraSlotSortMethod",
    })
    assertEqual(
        missingMethod.UF.HasNativeAuraContainerBackend(),
        false,
        "missing adapter method gate"
    )
    assertEqual(#missingMethod.holders, 0, "missing-method holder count")
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
        "BFISecondAuraHolder",
        completeSpec("party1", true)
    )
    local firstContainer = harness.containers[1]
    local secondContainer = harness.containers[2]

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
        "holder.shown",
    })
    assertEqual(firstContainer.unit, "target", "combat retarget mutation")
    assertEqual(firstContainer.enabled, true, "combat enabled mutation")
    assertEqual(first:GetFrame().shown, false, "combat stale-display suppression")
    assertEqual(second:GetFrame().shown, false, "combat rebuild display suppression")
    assertEqual(#harness.containers, 2, "combat rebuild mutation")

    harness:SetCombat(false)
    harness:FireRegen()

    assertEqual(countEvents(harness, "uf.register"), 1, "shared regen registrations")
    assertEqual(countEvents(harness, "uf.unregister"), 1, "shared regen unregistrations")
    assertEqual(countEvents(harness, "af.create-container"), 1, "coalesced rebuild count")
    assertEqual(firstContainer.unit, "focus", "deferred retarget")
    assertEqual(firstContainer.enabled, false, "deferred enabled")
    assertEqual(first:GetFrame().shown, false, "deferred holder visibility")
    assertEqual(firstContainer.groups.helpful.filterString, "HELPFUL|PLAYER",
        "deferred tuning")

    local replacement = harness.containers[3]
    assertEqual(replacement.parent, second:GetFrame(), "replacement owner")
    assertEqual(replacement.unit, "party3", "latest rebuild unit")
    assertEqual(replacement.enabled, false, "latest rebuild enabled")
    assertEqual(secondContainer.enabled, false, "old container disabled")
    assertEqual(secondContainer.shown, false, "old container hidden")
    assertEqual(harness.regenCallback, nil, "regen handler after flush")
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

local function testReplacementIsReadyBeforeSwap()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIReplacementAuraHolder",
        completeSpec("target", true)
    )
    local oldContainer = harness.containers[1]

    clearEvents(harness)
    controller:Rebuild(completeSpec("focus", true))

    local replacementContainer = harness.containers[2]
    local _, newUpdateIndex = findEvent(harness, "af.update", function(args)
        return args[1] == replacementContainer
    end)
    local _, oldDisableIndex = findEvent(harness, "af.enabled", function(args)
        return args[1] == oldContainer and args[2] == false
    end)
    local _, oldHideIndex = findEvent(harness, "native.hide", function(args)
        return args[1] == oldContainer
    end)
    local _, newShowIndex = findEvent(harness, "native.show", function(args)
        return args[1] == replacementContainer
    end)

    assertTrue(newUpdateIndex and oldDisableIndex, "replacement lifecycle events missing")
    assertTrue(newUpdateIndex < oldDisableIndex, "old container touched before replacement ready")
    assertTrue(oldHideIndex < newShowIndex, "replacement shown before old container hidden")
end

local function testHoveredTransitionDefers()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIHoveredAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()
    local oldContainer = harness.containers[1]

    clearEvents(harness)
    holder.mouseOver = true
    controller:Rebuild(completeSpec("focus", true))

    assertEqual(#harness.events, 0, "hovered transition mutations")
    assertEqual(#harness.timerCallbacks, 1, "hover retry count")
    assertEqual(#harness.containers, 1, "hovered replacement count")
    assertEqual(oldContainer.enabled, true, "hovered old container enabled")
    assertEqual(oldContainer.shown, true, "hovered old container shown")

    holder.mouseOver = false
    harness:RunNextTimer()

    assertEqual(#harness.timerCallbacks, 0, "completed hover retry count")
    assertEqual(#harness.containers, 2, "completed replacement count")
    assertEqual(harness.containers[2].unit, "focus", "completed replacement unit")
    assertEqual(holder.shown, true, "completed holder visibility")
    assertEqual(harness.events[1].name, "holder.shown", "hover-safe hide order")
    assertEqual(harness.events[1].args[2], false, "hover-safe hide state")
    assertEqual(harness.events[#harness.events].name, "holder.shown",
        "hover-safe restore order")
    assertEqual(harness.events[#harness.events].args[2], true,
        "hover-safe restore state")
end

local function testAbortedHolderWriteDefers()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIAbortedHolderAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()

    clearEvents(harness)
    holder.blockSetShown = true
    controller:Rebuild(completeSpec("focus", true))

    assertEventNames(harness, {
        "holder.shown",
    })
    assertEqual(#harness.timerCallbacks, 1, "aborted-write retry count")
    assertEqual(#harness.containers, 1, "aborted-write replacement count")
    assertEqual(holder.shown, true, "aborted-write holder state")

    holder.blockSetShown = nil
    harness:RunNextTimer()
    assertEqual(#harness.containers, 2, "retried replacement count")
    assertEqual(harness.containers[2].unit, "focus", "retried replacement unit")
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
    controller:Rebuild(completeSpec("focus", true))
    controller:Destroy()

    assertEventNames(harness, {
        "holder.shown",
        "uf.register",
    })
    assertEqual(container.enabled, true, "combat destroy enabled mutation")
    assertEqual(container.shown, true, "combat destroy visibility mutation")
    assertEqual(controller:GetFrame().shown, false, "combat destroy display suppression")

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

testCapabilityGate()
testBuildContract()
testTuningContract()
testHolderConfigQueue()
testSharedCombatQueue()
testRegenDispatchIsolation()
testReplacementIsReadyBeforeSwap()
testHoveredTransitionDefers()
testAbortedHolderWriteDefers()
testMaxFrameCountContract()
testDestroyPrecedence()
testOutOfBandOOCFlushUnregisters()
testRefreshIsDirectDirtyMark()

print("unit_frame_aura_controller_test.lua: ok")
