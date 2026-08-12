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

local function newHolder(harness, name, parent, frameTemplate)
    local holder = {
        id = #harness.holders + 1,
        name = name,
        parent = parent,
        frameTemplate = frameTemplate,
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

    function holder:SetSize(width, height)
        self.width = width
        self.height = height
        record(harness, "holder.size", self, width, height)
    end

    function holder:ClearAllPoints()
        self.point = nil
        record(harness, "holder.clear-points", self)
    end

    function holder:SetPoint(point, relativeTo, relativePoint, x, y)
        self.point = {point, relativeTo, relativePoint, x, y}
        record(
            harness,
            "holder.set-point",
            self,
            point,
            relativeTo,
            relativePoint,
            x,
            y
        )
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
        versionNum = options.versionNum or 33,
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
        CreateFrame = function(frameType, name, parent, frameTemplate)
            assertEqual(frameType, "Frame", "holder frame type")
            local holder = newHolder(
                harness,
                name,
                parent,
                frameTemplate
            )
            record(
                harness,
                "wow.create-frame",
                holder,
                frameType,
                name,
                parent,
                frameTemplate
            )
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

local function findHolderByName(harness, name)
    for _, holder in ipairs(harness.holders) do
        if holder.name == name then
            return holder
        end
    end
end

local function partitionCompleteLeaf(
    unit,
    key,
    filterString,
    point,
    relativePoint,
    x,
    y,
    width,
    height
)
    local spec = completeSpec(unit, true)
    spec.holder = {
        width = width,
        height = height,
    }
    spec.containerPoint = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    spec.groups[1].key = key
    spec.groups[1].filterString = filterString
    spec.groups[1].buttonStyle = {
        variant = key,
    }
    spec.slots = {}
    return spec
end

local function partitionCompleteSpec(unit, variant, generation)
    generation = generation or 1
    if generation == 2 then
        return {
            unit = unit,
            enabled = true,
            shown = true,
            variant = variant or "friendly",
            holder = {
                width = 240,
                height = 140,
            },
            friendly = partitionCompleteLeaf(
                unit,
                "friendly",
                "HARMFUL",
                "BOTTOMRIGHT",
                "BOTTOMRIGHT",
                11,
                12,
                220,
                120
            ),
            main = partitionCompleteLeaf(
                unit,
                "main",
                "HARMFUL|PLAYER",
                "TOPRIGHT",
                "TOPRIGHT",
                13,
                14,
                220,
                40
            ),
            complement = partitionCompleteLeaf(
                unit,
                "complement",
                "HARMFUL|!PLAYER",
                "TOPRIGHT",
                "TOPRIGHT",
                15,
                16,
                200,
                80
            ),
            attachment = {
                point = "TOPRIGHT",
                relativePoint = "BOTTOMRIGHT",
                x = 0,
                y = 1,
            },
        }
    end

    return {
        unit = unit,
        enabled = true,
        shown = true,
        variant = variant or "friendly",
        holder = {
            width = 220,
            height = 120,
        },
        friendly = partitionCompleteLeaf(
            unit,
            "friendly",
            "HARMFUL",
            "TOPLEFT",
            "TOPLEFT",
            2,
            -3,
            220,
            120
        ),
        main = partitionCompleteLeaf(
            unit,
            "main",
            "HARMFUL|PLAYER",
            "BOTTOMLEFT",
            "BOTTOMLEFT",
            3,
            4,
            220,
            40
        ),
        complement = partitionCompleteLeaf(
            unit,
            "complement",
            "HARMFUL|!PLAYER",
            "BOTTOMLEFT",
            "BOTTOMLEFT",
            5,
            6,
            200,
            80
        ),
        attachment = {
            point = "BOTTOMLEFT",
            relativePoint = "TOPLEFT",
            x = 0,
            y = -1,
        },
    }
end

local function partitionTuningLeaf(
    key,
    filterString,
    point,
    relativePoint,
    x,
    y,
    width,
    height
)
    local tuning = tuningSpec()
    tuning.holder = {
        width = width,
        height = height,
    }
    tuning.containerPoint = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
    tuning.groups[1].key = key
    tuning.groups[1].filterString = filterString
    tuning.slots = {}
    return tuning
end

local function partitionTuningSpec()
    return {
        holder = {
            width = 230,
            height = 130,
        },
        friendly = partitionTuningLeaf(
            "friendly",
            "HARMFUL|RAID",
            "TOPRIGHT",
            "TOPRIGHT",
            21,
            22,
            230,
            130
        ),
        main = partitionTuningLeaf(
            "main",
            "HARMFUL|PLAYER|RAID",
            "BOTTOMRIGHT",
            "BOTTOMRIGHT",
            23,
            24,
            230,
            50
        ),
        complement = partitionTuningLeaf(
            "complement",
            "HARMFUL|!PLAYER|RAID",
            "TOPRIGHT",
            "TOPRIGHT",
            25,
            26,
            210,
            90
        ),
        attachment = {
            point = "TOPRIGHT",
            relativePoint = "BOTTOMRIGHT",
            x = 1,
            y = 2,
        },
    }
end

local function assertNoNativeMutation(harness, message)
    for _, eventName in ipairs({
        "af.create-container",
        "af.enabled",
        "af.flow",
        "af.processing",
        "af.add-group",
        "af.add-slot",
        "af.unit",
        "af.update",
        "af.group.filter",
        "af.group.max",
        "af.group.candidates",
        "af.group.sort",
        "af.group.layout",
        "af.slot.filter",
        "af.slot.candidates",
        "af.slot.sort",
        "native.hide",
        "native.show",
        "native.clear-points",
        "native.set-point",
        "slot.clear-points",
        "slot.set-point",
    }) do
        assertEqual(
            countEvents(harness, eventName),
            0,
            (message or "unexpected native mutation") .. ": " .. eventName
        )
    end
end

local function testCapabilityGate()
    local oldAF = makeHarness({versionNum = 32})
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

local function testPlayerVehicleCombatRetarget()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIPlayerVehicleAuraHolder",
        completeSpec("player", true)
    )
    local container = harness.containers[1]

    clearEvents(harness)
    harness:SetCombat(true)
    controller:SetUnit("vehicle")

    assertEqual(container.unit, "player",
        "combat Player vehicle native unit")
    assertEqual(controller:GetFrame().shown, false,
        "combat Player vehicle stale-display suppression")
    assertEqual(countEvents(harness, "af.unit"), 0,
        "combat Player vehicle retarget mutation")
    assertEqual(countEvents(harness, "af.create-container"), 0,
        "combat Player vehicle replacement count")
    assertTrue(harness.regenCallback,
        "combat Player vehicle regen registration")

    harness:SetCombat(false)
    harness:FireRegen()

    assertEqual(container.unit, "vehicle",
        "deferred Player vehicle native unit")
    assertEqual(controller:GetFrame().shown, true,
        "deferred Player vehicle holder visibility")
    assertEqual(countEvents(harness, "af.unit"), 1,
        "deferred Player vehicle retarget count")
    assertEqual(countEvents(harness, "af.create-container"), 0,
        "deferred Player vehicle replacement count")
    assertEqual(harness.regenCallback, nil,
        "Player vehicle regen handler after flush")
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

local function testVisibilityUsesWriteLedger()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraContainerController(
        {},
        "BFIOpaqueVisibilityAuraHolder",
        completeSpec("target", true)
    )
    local holder = controller:GetFrame()
    local oldContainer = harness.containers[1]

    clearEvents(harness)
    controller:Rebuild(completeSpec("focus", true))

    assertEqual(#harness.timerCallbacks, 0, "visibility retry count")
    assertEqual(#harness.containers, 2, "replacement count")
    assertEqual(oldContainer.enabled, false, "old container enabled")
    assertEqual(oldContainer.shown, false, "old container shown")
    assertEqual(harness.containers[2].unit, "focus", "replacement unit")
    assertEqual(holder.shown, true, "holder visibility")
    assertEqual(harness.events[1].name, "holder.shown", "holder hide order")
    assertEqual(harness.events[1].args[2], false, "holder hide state")
    assertEqual(harness.events[#harness.events].name, "holder.shown",
        "holder restore order")
    assertEqual(harness.events[#harness.events].args[2], true,
        "holder restore state")
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

local function testPartitionBuildAndRelationSwap()
    local harness = makeHarness()
    local parent = {}
    local controller = harness.UF.CreateNativeAuraPartitionController(
        parent,
        "BFIPartitionAuraHolder"
    )
    assertTrue(controller, "partition controller")
    assertEqual(#harness.holders, 4, "partition holder count")

    local outer = controller:GetFrame()
    local friendlyHolder = findHolderByName(
        harness,
        "BFIPartitionAuraHolder_Friendly"
    )
    local mainHolder = findHolderByName(
        harness,
        "BFIPartitionAuraHolder_HostileMain"
    )
    local complementHolder = findHolderByName(
        harness,
        "BFIPartitionAuraHolder_HostileComplement"
    )
    assertEqual(outer.parent, parent, "partition outer parent")
    assertEqual(
        complementHolder.frameTemplate,
        "DisableUntrustedLayoutScriptsTemplate",
        "partition complement forbidden-layout template"
    )

    controller:Rebuild(partitionCompleteSpec("target", "friendly"))

    assertEqual(#harness.containers, 3, "partition native container count")
    local friendlyNative = controller.friendly:GetNativeFrame()
    local mainNative = controller.main:GetNativeFrame()
    local complementNative = controller.complement:GetNativeFrame()
    assertEqual(friendlyNative, harness.containers[1],
        "friendly native identity")
    assertEqual(mainNative, harness.containers[2],
        "main native identity")
    assertEqual(complementNative, harness.containers[3],
        "complement native identity")

    assertEqual(outer.width, 220, "partition outer width")
    assertEqual(outer.height, 120, "partition outer height")
    assertEqual(outer.shown, true, "partition outer visibility")
    assertEqual(friendlyHolder.shown, true, "friendly initial visibility")
    assertEqual(mainHolder.shown, false, "main initial visibility")
    assertEqual(complementHolder.shown, false,
        "complement initial visibility")

    assertEqual(friendlyHolder.point[1], "TOPLEFT",
        "friendly holder point")
    assertEqual(friendlyHolder.point[2], outer,
        "friendly holder anchor owner")
    assertEqual(friendlyHolder.point[3], "TOPLEFT",
        "friendly holder relative point")
    assertEqual(friendlyHolder.point[4], 0,
        "friendly holder anchor x")
    assertEqual(friendlyHolder.point[5], 0,
        "friendly holder anchor y")
    assertEqual(mainHolder.point[1], "BOTTOMLEFT", "main holder point")
    assertEqual(mainHolder.point[2], outer, "main holder anchor owner")
    assertEqual(mainHolder.point[3], "BOTTOMLEFT",
        "main holder relative point")

    assertEqual(complementHolder.point[1], "BOTTOMLEFT",
        "complement attachment point")
    assertEqual(complementHolder.point[2], mainNative,
        "complement attaches to secret-sized main native frame")
    assertEqual(complementHolder.point[3], "TOPLEFT",
        "complement attachment relative point")
    assertEqual(complementHolder.point[4], 0,
        "complement attachment x")
    assertEqual(complementHolder.point[5], -1,
        "complement attachment clamp correction")
    assertEqual(complementNative.point[1], "BOTTOMLEFT",
        "complement child container point")
    assertEqual(complementNative.point[2], complementHolder,
        "complement child container owner")
    assertEqual(complementNative.point[4], 5,
        "complement child container x")
    assertEqual(complementNative.point[5], 6,
        "complement child container y")

    for _, container in ipairs({
        friendlyNative,
        mainNative,
        complementNative,
    }) do
        assertEqual(container.unit, "target", "partition native unit")
        assertEqual(container.enabled, true, "partition native enabled")
        assertEqual(container.shown, true, "partition native shown")
    end

    clearEvents(harness)
    harness:SetCombat(true)
    controller:SetVariant("hostile")
    harness:SetCombat(false)

    assertEqual(friendlyHolder.shown, false,
        "friendly hostile-swap visibility")
    assertEqual(mainHolder.shown, true, "main hostile-swap visibility")
    assertEqual(complementHolder.shown, true,
        "complement hostile-swap visibility")
    assertEqual(outer.shown, true, "hostile-swap outer visibility")
    assertEqual(#harness.containers, 3,
        "hostile swap container allocation")
    assertEqual(countEvents(harness, "uf.register"), 0,
        "hostile swap combat queue")
    assertNoNativeMutation(harness, "hostile relationship swap")
    assertEqual(harness.events[1].name, "holder.shown",
        "hostile swap atomic hide event")
    assertEqual(harness.events[1].args[1], outer,
        "hostile swap atomic hide holder")
    assertEqual(harness.events[1].args[2], false,
        "hostile swap atomic hide state")
    assertEqual(harness.events[#harness.events].name, "holder.shown",
        "hostile swap atomic restore event")
    assertEqual(harness.events[#harness.events].args[1], outer,
        "hostile swap atomic restore holder")
    assertEqual(harness.events[#harness.events].args[2], true,
        "hostile swap atomic restore state")
end

local function testTargetPartitionDoesNotReadVisibilityState()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraPartitionController(
        {},
        "BFI_Target_Debuffs"
    )
    controller:Rebuild(partitionCompleteSpec("target", "friendly"))

    local outer = controller:GetFrame()
    local friendlyHolder = controller.friendly:GetFrame()
    local mainHolder = controller.main:GetFrame()
    local complementHolder = controller.complement:GetFrame()
    assertEqual(
        complementHolder.name,
        "BFI_Target_Debuffs_HostileComplement",
        "target hostile-complement holder name"
    )

    local function forbidVisibilityRead(frame, method)
        frame[method] = function()
            error("forbidden " .. method .. " visibility read")
        end
    end
    for _, frame in ipairs({
        outer,
        friendlyHolder,
        mainHolder,
        complementHolder,
    }) do
        forbidVisibilityRead(frame, "IsShown")
        forbidVisibilityRead(frame, "IsMouseOver")
    end

    clearEvents(harness)

    controller:SetVariant("hostile")
    controller:SetVariant("friendly")
    controller:SetVariant("hostile")

    assertEqual(#harness.timerCallbacks, 0,
        "partition visibility retry")
    assertEqual(friendlyHolder.shown, false,
        "latest friendly presentation visibility")
    assertEqual(mainHolder.shown, true,
        "latest main presentation visibility")
    assertEqual(complementHolder.shown, true,
        "latest complement presentation visibility")
    assertNoNativeMutation(harness, "secret-safe relationship request")
end

local function testPartitionTuningReanchorsEveryLayer()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraPartitionController(
        {},
        "BFITunedPartitionAuraHolder"
    )
    controller:Rebuild(partitionCompleteSpec("target", "friendly"))

    local outer = controller:GetFrame()
    local friendlyHolder = controller.friendly:GetFrame()
    local mainHolder = controller.main:GetFrame()
    local complementHolder = controller.complement:GetFrame()
    local friendlyNative = controller.friendly:GetNativeFrame()
    local mainNative = controller.main:GetNativeFrame()
    local complementNative = controller.complement:GetNativeFrame()
    clearEvents(harness)

    controller:ApplyTuning(partitionTuningSpec())

    assertEqual(#harness.containers, 3,
        "partition tuning container allocation")
    assertEqual(countEvents(harness, "af.add-group"), 0,
        "partition tuning group allocation")
    assertEqual(outer.width, 230, "partition tuned outer width")
    assertEqual(outer.height, 130, "partition tuned outer height")

    assertEqual(friendlyHolder.point[1], "TOPRIGHT",
        "tuned friendly holder point")
    assertEqual(friendlyHolder.point[2], outer,
        "tuned friendly holder owner")
    assertEqual(mainHolder.point[1], "BOTTOMRIGHT",
        "tuned main holder point")
    assertEqual(mainHolder.point[2], outer, "tuned main holder owner")

    assertEqual(friendlyNative.point[1], "TOPRIGHT",
        "tuned friendly native point")
    assertEqual(friendlyNative.point[2], friendlyHolder,
        "tuned friendly native owner")
    assertEqual(friendlyNative.point[4], 21,
        "tuned friendly native x")
    assertEqual(friendlyNative.point[5], 22,
        "tuned friendly native y")
    assertEqual(mainNative.point[1], "BOTTOMRIGHT",
        "tuned main native point")
    assertEqual(mainNative.point[2], mainHolder,
        "tuned main native owner")
    assertEqual(mainNative.point[4], 23, "tuned main native x")
    assertEqual(mainNative.point[5], 24, "tuned main native y")
    assertEqual(complementNative.point[1], "TOPRIGHT",
        "tuned complement native point")
    assertEqual(complementNative.point[2], complementHolder,
        "tuned complement native owner")
    assertEqual(complementNative.point[4], 25,
        "tuned complement native x")
    assertEqual(complementNative.point[5], 26,
        "tuned complement native y")

    assertEqual(complementHolder.point[1], "TOPRIGHT",
        "tuned complement attachment point")
    assertEqual(complementHolder.point[2], mainNative,
        "tuned complement main owner")
    assertEqual(complementHolder.point[3], "BOTTOMRIGHT",
        "tuned complement relative point")
    assertEqual(complementHolder.point[4], 1,
        "tuned complement attachment x")
    assertEqual(complementHolder.point[5], 2,
        "tuned complement attachment y")
end

local function testPartitionCombatDefersNativeTuning()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraPartitionController(
        {},
        "BFICombatPartitionAuraHolder"
    )
    controller:Rebuild(partitionCompleteSpec("target", "friendly"))

    local outer = controller:GetFrame()
    local complementHolder = controller.complement:GetFrame()
    local oldAttachmentOwner = complementHolder.point[2]
    clearEvents(harness)
    harness:SetCombat(true)

    controller:ApplyTuning(partitionTuningSpec())
    controller:SetVariant("hostile")

    assertEqual(outer.shown, false,
        "combat partition stale-display suppression")
    assertEqual(complementHolder.point[2], oldAttachmentOwner,
        "combat complement reanchor mutation")
    assertEqual(countEvents(harness, "uf.register"), 1,
        "combat partition regen registration")
    assertEqual(countEvents(harness, "af.update"), 0,
        "combat partition native tuning")

    harness:SetCombat(false)
    harness:FireRegen()

    assertEqual(outer.shown, true,
        "deferred partition outer visibility")
    assertEqual(controller.friendly:GetFrame().shown, false,
        "deferred partition friendly visibility")
    assertEqual(controller.main:GetFrame().shown, true,
        "deferred partition main visibility")
    assertEqual(controller.complement:GetFrame().shown, true,
        "deferred partition complement visibility")
    assertEqual(complementHolder.point[2],
        controller.main:GetNativeFrame(),
        "deferred complement main owner")
    assertEqual(complementHolder.point[1], "TOPRIGHT",
        "deferred complement point")
    assertEqual(countEvents(harness, "uf.unregister"), 1,
        "combat partition regen unregistration")
end

local function testPartitionTopologyShrinkKeepsAbsentChildDormant()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraPartitionController(
        {},
        "BFIShrunkPartitionAuraHolder"
    )
    controller:Rebuild(partitionCompleteSpec("target", "hostile"))

    local staleComplement = controller.complement:GetNativeFrame()
    local mainOnly = partitionCompleteSpec("target", "hostile", 2)
    mainOnly.complement = nil
    mainOnly.attachment = nil
    controller:Rebuild(mainOnly)

    assertEqual(controller.main:GetFrame().shown, true,
        "main-only hostile-main visibility")
    assertEqual(controller.complement:GetFrame().shown, false,
        "main-only stale complement visibility")
    assertEqual(staleComplement.enabled, false,
        "main-only stale complement enabled state")

    controller:SetEnabled(false)
    controller:SetEnabled(true)
    assertEqual(staleComplement.enabled, false,
        "main-only stale complement re-enable suppression")

    clearEvents(harness)
    controller:SetUnit("focus")
    assertEqual(countEvents(harness, "af.unit"), 2,
        "main-only retarget count")
    assertEqual(staleComplement.unit, "target",
        "main-only stale complement retarget suppression")

    clearEvents(harness)
    controller:Refresh()
    assertEqual(countEvents(harness, "af.update"), 2,
        "main-only refresh count")

    local staleMain = controller.main:GetNativeFrame()
    local complementOnly = partitionCompleteSpec(
        "focus",
        "hostile",
        1
    )
    complementOnly.main = nil
    complementOnly.attachment = nil
    controller:Rebuild(complementOnly)

    assertEqual(controller.main:GetFrame().shown, false,
        "complement-only stale main visibility")
    assertEqual(controller.complement:GetFrame().shown, true,
        "complement-only hostile-complement visibility")
    assertEqual(staleMain.enabled, false,
        "complement-only stale main enabled state")

    controller:SetEnabled(false)
    controller:SetEnabled(true)
    assertEqual(staleMain.enabled, false,
        "complement-only stale main re-enable suppression")
end

local function testPartitionRebuildRefreshAndDestroy()
    local harness = makeHarness()
    local controller = harness.UF.CreateNativeAuraPartitionController(
        {},
        "BFIRebuiltPartitionAuraHolder"
    )
    controller:Rebuild(partitionCompleteSpec("target", "friendly"))

    local oldFriendly = controller.friendly:GetNativeFrame()
    local oldMain = controller.main:GetNativeFrame()
    local oldComplement = controller.complement:GetNativeFrame()
    local complementHolder = controller.complement:GetFrame()
    clearEvents(harness)

    controller:Rebuild(partitionCompleteSpec("focus", "hostile", 2))

    assertEqual(#harness.containers, 6,
        "partition replacement container count")
    local newFriendly = controller.friendly:GetNativeFrame()
    local newMain = controller.main:GetNativeFrame()
    local newComplement = controller.complement:GetNativeFrame()
    assertTrue(newFriendly ~= oldFriendly,
        "friendly replacement identity")
    assertTrue(newMain ~= oldMain, "main replacement identity")
    assertTrue(newComplement ~= oldComplement,
        "complement replacement identity")
    assertEqual(complementHolder.point[2], newMain,
        "replacement complement reanchors to replacement main")
    assertEqual(complementHolder.point[2] == oldMain, false,
        "replacement complement old-main detachment")
    assertEqual(complementHolder.point[1], "TOPRIGHT",
        "replacement complement point")
    assertEqual(complementHolder.point[3], "BOTTOMRIGHT",
        "replacement complement relative point")
    assertEqual(complementHolder.point[5], 1,
        "replacement complement clamp correction")

    for _, container in ipairs({
        oldFriendly,
        oldMain,
        oldComplement,
    }) do
        assertEqual(container.enabled, false,
            "old partition native disabled")
        assertEqual(container.shown, false,
            "old partition native hidden")
    end
    for _, container in ipairs({
        newFriendly,
        newMain,
        newComplement,
    }) do
        assertEqual(container.unit, "focus",
            "replacement partition unit")
        assertEqual(container.enabled, true,
            "replacement partition enabled")
        assertEqual(container.shown, true,
            "replacement partition shown")
    end
    assertEqual(controller.friendly:GetFrame().shown, false,
        "replacement friendly presentation")
    assertEqual(controller.main:GetFrame().shown, true,
        "replacement main presentation")
    assertEqual(controller.complement:GetFrame().shown, true,
        "replacement complement presentation")

    clearEvents(harness)
    controller:Refresh()
    assertEqual(countEvents(harness, "af.update"), 3,
        "partition refresh native count")
    for _, container in ipairs({
        newFriendly,
        newMain,
        newComplement,
    }) do
        assertTrue(
            findEvent(harness, "af.update", function(args)
                return args[1] == container
            end),
            "partition refresh container"
        )
    end

    clearEvents(harness)
    controller:Destroy()
    assertEqual(controller:GetFrame().shown, false,
        "destroyed partition outer visibility")
    for _, container in ipairs({
        newFriendly,
        newMain,
        newComplement,
    }) do
        assertEqual(container.enabled, false,
            "destroyed partition native disabled")
        assertEqual(container.shown, false,
            "destroyed partition native hidden")
    end
end

testCapabilityGate()
testBuildContract()
testTuningContract()
testHolderConfigQueue()
testSharedCombatQueue()
testPlayerVehicleCombatRetarget()
testRegenDispatchIsolation()
testReplacementIsReadyBeforeSwap()
testVisibilityUsesWriteLedger()
testProductionAvoidsVisibilityInspection()
testMaxFrameCountContract()
testDestroyPrecedence()
testOutOfBandOOCFlushUnregisters()
testRefreshIsDirectDirtyMark()
testPartitionBuildAndRelationSwap()
testTargetPartitionDoesNotReadVisibilityState()
testPartitionTuningReanchorsEveryLayer()
testPartitionCombatDefersNativeTuning()
testPartitionTopologyShrinkKeepsAbsentChildDormant()
testPartitionRebuildRefreshAndDestroy()

print("unit_frame_aura_controller_test.lua: ok")
