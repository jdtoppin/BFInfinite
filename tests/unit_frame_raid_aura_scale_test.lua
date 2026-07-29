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

local function copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

local function tableCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function record(harness, name, ...)
    harness.events[#harness.events + 1] = {
        name = name,
        combat = harness.inCombat,
        args = {n = select("#", ...), ...},
    }
end

local function countEvents(harness, name, firstArgument)
    local count = 0
    for _, event in ipairs(harness.events) do
        if event.name == name
            and (
                firstArgument == nil
                or event.args[1] == firstArgument
            )
        then
            count = count + 1
        end
    end
    return count
end

local function assertOutOfCombat(harness, operation)
    assertEqual(
        harness.inCombat,
        false,
        operation .. " mutated native structure in combat"
    )
end

local NATIVE_BUTTON_BATCH_SIZE = 10

local function newFrame(harness, name, parent)
    local frame = {
        name = name,
        parent = parent,
        shown = true,
    }

    function frame:GetName()
        return self.name
    end

    function frame:Hide()
        self.shown = false
        record(harness, "holder.hide", self)
    end

    function frame:Show()
        self.shown = true
        record(harness, "holder.show", self)
    end

    function frame:SetShown(shown)
        self.shown = shown
        record(harness, "holder.shown", self, shown)
    end

    function frame:IsShown()
        return self.shown == true
    end

    function frame:IsMouseOver()
        return false
    end

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
        record(harness, "holder.size", self, width, height)
    end

    return frame
end

local function newContainer(harness, parent)
    local container = {
        parent = parent,
        shown = true,
        groups = {},
        slots = {},
    }

    function container:Hide()
        self.shown = false
        record(harness, "container.hide", self)
    end

    function container:Show()
        self.shown = true
        record(harness, "container.show", self)
    end

    function container:ClearAllPoints()
        assertOutOfCombat(harness, "container point clear")
        self.point = nil
        record(harness, "container.clear-point", self)
    end

    function container:SetPoint(...)
        assertOutOfCombat(harness, "container placement")
        self.point = {...}
        record(harness, "container.point", self, ...)
    end

    harness.containers[#harness.containers + 1] = container
    return container
end

local function newHeaderBornContainer(harness, parent)
    local container = newContainer(harness, parent)
    container.seedOrigin = "secure-header"
    record(harness, "header.container", container, parent)
    return container
end

local function totalGroupCount(harness)
    local count = 0
    for _, container in ipairs(harness.containers) do
        count = count + tableCount(container.groups)
    end
    return count
end

local function assertNoNativeConstruction(
    harness,
    expectedContainers,
    expectedGroups,
    expectedRestrictedButtons,
    message
)
    assertEqual(
        #harness.containers,
        expectedContainers,
        message .. " container count"
    )
    assertEqual(
        totalGroupCount(harness),
        expectedGroups,
        message .. " group count"
    )
    assertEqual(
        harness.staticRestrictedButtonCount,
        expectedRestrictedButtons,
        message .. " restricted-button contract"
    )
    assertEqual(
        countEvents(harness, "af.create-container"),
        0,
        message .. " container allocations"
    )
    assertEqual(
        countEvents(harness, "af.add-group"),
        0,
        message .. " group declarations"
    )
end

local function assertCleanNativeUnitEvents(harness, expectedUnit)
    for _, event in ipairs(harness.events) do
        if event.name == "af.unit" then
            local unit = event.args[2]
            assertEqual(type(unit), "string", "native unit argument type")
            if expectedUnit then
                assertEqual(unit, expectedUnit, "native unit argument")
            end
        end
    end
end

local function makeHarness()
    local harness = {
        containers = {},
        events = {},
        inCombat = false,
        nativeUnitValues = {},
        registered = {},
        staticRestrictedButtonCount = 0,
        timers = {},
    }
    local AF = {
        isRetail = true,
        versionNum = 34,
    }
    local UF = {}
    local F = {}

    function AF.Copy(value)
        return copy(value)
    end

    function AF.HasCustomAuraContainer()
        return true
    end

    function AF.GetCustomAuraContainerConstructionStats()
        return {}
    end

    function AF.GetCustomAuraContainerConstructionTotals()
        return {}
    end

    function AF.CreateCustomAuraContainer(parent)
        assertOutOfCombat(harness, "container creation")
        local container = newContainer(harness, parent)
        container.seedOrigin = "eager"
        record(harness, "af.create-container", container, parent)
        return container
    end

    function AF.SetSize(frame, width, height)
        assertOutOfCombat(harness, "holder size")
        frame:SetSize(width, height)
        record(harness, "af.size", frame, width, height)
    end

    function AF.SetFrameLevel(frame, level, relativeTo)
        assertOutOfCombat(harness, "holder/container layer")
        frame.appliedFrameLevel = level
        frame.frameLevelRelativeTo = relativeTo
        record(harness, "af.frame-level", frame, level, relativeTo)
    end

    function AF.SetCustomAuraContainerEnabled(container, enabled)
        assertOutOfCombat(harness, "container enabled state")
        container.enabled = enabled
        record(harness, "af.enabled", container, enabled)
    end

    function AF.SetCustomAuraContainerFlowLayout(container, layout)
        assertOutOfCombat(harness, "container flow tuning")
        container.flowLayout = copy(layout)
        record(harness, "af.flow", container, layout)
    end

    function AF.SetCustomAuraContainerProcessingPolicy(
        container,
        policy,
        options
    )
        assertOutOfCombat(harness, "container processing tuning")
        container.processing = {
            policy = policy,
            options = copy(options),
        }
        record(harness, "af.processing", container, policy, options)
    end

    function AF.SetCustomAuraContainerUnit(container, unit)
        assertEqual(type(unit), "string", "native unit must be a clean token")
        container.unit = unit
        harness.nativeUnitValues[#harness.nativeUnitValues + 1] = unit
        record(harness, "af.unit", container, unit)
    end

    function AF.UpdateCustomAuraContainer(container)
        record(harness, "af.update", container)
    end

    function AF.AddCustomAuraGroup(
        container,
        key,
        filterString,
        options,
        buttonStyle
    )
        assertOutOfCombat(harness, "aura group declaration")
        container.groups[key] = {
            filterString = filterString,
            options = copy(options),
            buttonStyle = copy(buttonStyle),
        }
        -- The mock does not instantiate restricted Blizzard frames. It
        -- accounts for the audited 12.1 ten-button initial batch attached to
        -- each add-only group declaration.
        harness.staticRestrictedButtonCount =
            harness.staticRestrictedButtonCount + NATIVE_BUTTON_BATCH_SIZE
        record(harness, "af.add-group", container, key)
    end

    function AF.SetCustomAuraGroupFilterString(container, key, filterString)
        assertOutOfCombat(harness, "aura group filter tuning")
        container.groups[key].filterString = filterString
        record(harness, "af.group-filter", container, key)
    end

    function AF.SetCustomAuraGroupMaxFrameCount(container, key, maximum)
        assertOutOfCombat(harness, "aura group count tuning")
        container.groups[key].options.maxFrameCount = maximum
        record(harness, "af.group-count", container, key)
    end

    function AF.SetCustomAuraGroupCandidateFilters(container, key, filters)
        assertOutOfCombat(harness, "aura candidate tuning")
        container.groups[key].options.candidateFilters = copy(filters)
        record(harness, "af.group-candidates", container, key)
    end

    function AF.SetCustomAuraGroupSortMethod(
        container,
        key,
        method,
        direction
    )
        assertOutOfCombat(harness, "aura group sort tuning")
        container.groups[key].options.sortMethod = method
        container.groups[key].options.sortDirection = direction
        record(harness, "af.group-sort", container, key)
    end

    function AF.SetCustomAuraGroupLayout(container, key, layout)
        assertOutOfCombat(harness, "aura group layout tuning")
        container.groups[key].options.layout = copy(layout)
        record(harness, "af.group-layout", container, key)
    end

    function AF.AddCustomAuraSlot()
        error("Raid aura scale test did not expect native slots", 2)
    end

    function AF.SetCustomAuraSlotFilterString()
        error("Raid aura scale test did not expect native slots", 2)
    end

    function AF.SetCustomAuraSlotCandidateFilters()
        error("Raid aura scale test did not expect native slots", 2)
    end

    function AF.SetCustomAuraSlotSortMethod()
        error("Raid aura scale test did not expect native slots", 2)
    end

    function AF.AddToPixelUpdater_Auto(frame, callback, combatSafeOnly)
        frame.pixelCallback = callback
        frame.pixelCombatSafeOnly = combatSafeOnly
    end

    function AF.ReSize()
        error("unexpected pixel resize in Raid aura scale test", 2)
    end

    function AF.RePoint()
        error("unexpected pixel reposition in Raid aura scale test", 2)
    end

    function AF.RegisterCallback()
    end

    function F.isValueNonSecret(value)
        return type(value) ~= "table" or value.secret ~= true
    end

    function UF.LoadIndicatorPosition(frame, position, anchorTo)
        assertOutOfCombat(harness, "indicator placement")
        frame.indicatorPosition = copy(position)
        frame.indicatorAnchorTo = anchorTo
        record(harness, "uf.position", frame, position, anchorTo)
    end

    function UF.CreateAuras()
        error("native Raid scale path unexpectedly selected legacy auras", 2)
    end

    function UF:RegisterEvent(event, callback)
        self.registeredByAuraRuntime = true
        harness.registered[event] = harness.registered[event] or {}
        harness.registered[event][callback] = true
        record(harness, "uf.register", event, callback)
    end

    function UF:UnregisterEvent(event, callback)
        local callbacks = harness.registered[event]
        assertTrue(
            callbacks and callbacks[callback],
            "unregistering an unknown aura callback"
        )
        callbacks[callback] = nil
        if next(callbacks) == nil then
            harness.registered[event] = nil
        end
        record(harness, "uf.unregister", event, callback)
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        funcs = F,
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        AnchorUtil = {
            FlowLayoutAxis = {
                Horizontal = "HORIZONTAL",
                Vertical = "VERTICAL",
            },
            FlowDirection = {
                Down = "DOWN",
                Left = "LEFT",
                Right = "RIGHT",
                Up = "UP",
            },
        },
        AuraContainerSortDirection = {
            Normal = "NORMAL",
        },
        AuraContainerSortMethod = {
            Default = "DEFAULT",
        },
        AuraUtil = {
            AuraFilters = {
                Important = "IMPORTANT",
                Dispellable = "DISPELLABLE",
            },
        },
        C_Timer = {
            After = function(delay, callback)
                harness.timers[#harness.timers + 1] = {
                    delay = delay,
                    callback = callback,
                }
            end,
        },
        CustomAuraContainerAuraProcessingPolicy = {
            None = "NONE",
        },
        GetCVar = function() return nil end,
        CreateFrame = function(frameType, name, parent)
            assertOutOfCombat(harness, "aura holder creation")
            assertEqual(frameType, "Frame", "aura holder frame type")
            return newFrame(harness, name, parent)
        end,
        InCombatLockdown = function()
            return harness.inCombat
        end,
        UnitCanAssist = function()
            return true
        end,
        UnitCanAttack = function()
            return false
        end,
        UnitIsVisible = function()
            return true
        end,
        assert = assert,
        error = error,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawget = rawget,
        select = select,
        setmetatable = setmetatable,
        string = string,
        table = table,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected Raid aura scale global: " .. tostring(key), 2)
        end,
    })

    for _, path in ipairs({
        "Utils.lua",
        "Modules/UnitFrames/AuraController.lua",
        "Modules/UnitFrames/AuraPolicy.lua",
        "Modules/UnitFrames/AuraSpec.lua",
        "Modules/UnitFrames/AuraRuntime.lua",
    }) do
        local chunk, loadError = loadfile(path)
        assertTrue(chunk, loadError)
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end

    harness.AF = AF
    harness.UF = UF

    function harness:ClearEvents()
        self.events = {}
    end

    function harness:SetCombat(inCombat)
        self.inCombat = inCombat
    end

    function harness:RunTimers(delay)
        local index = 1
        while index <= #self.timers do
            local timer = self.timers[index]
            if timer.delay == delay then
                table.remove(self.timers, index)
                timer.callback()
            else
                index = index + 1
            end
        end
    end

    function harness:Fire(event, ...)
        local callbacks = self.registered[event]
        assertTrue(callbacks, "event is not registered: " .. event)

        local snapshot = {}
        for callback in pairs(callbacks) do
            snapshot[#snapshot + 1] = callback
        end
        for _, callback in ipairs(snapshot) do
            callback(self.UF, event, ...)
        end
    end

    return harness
end

local function newAuraConfig(auraFilter, revision, constructionRevision)
    constructionRevision = constructionRevision == nil
        and revision
        or constructionRevision
    local harmful = auraFilter == "HARMFUL"
    local width = (harmful and 8 or 10) + constructionRevision
    return {
        enabled = true,
        filters = harmful and {
            player = true,
            raidInCombat = true,
            raidPlayerDispellable = true,
        } or {
            player = true,
        },
        position = {"TOPLEFT", "TOPLEFT", revision * 3, revision},
        anchorTo = "root",
        frameLevel = 4 + revision,
        orientation = "left_to_right",
        width = width,
        height = 10 + constructionRevision,
        spacingX = 1 + revision,
        spacingY = 1 + (revision % 2),
        -- Keep the synthetic profile aligned with both shipped Raid presets.
        -- Four is below the native ten-button initial batch, so tuning these
        -- descriptors cannot request another restricted allocation batch.
        numPerLine = 4,
        numTotal = 4,
        cooldownStyle = constructionRevision == 1
            and "vertical"
            or "clock_with_leading_edge",
        durationText = {
            enabled = true,
            font = {"Mock Font", 10, "OUTLINE", false},
            position = {"CENTER", "CENTER", 0, 0},
            color = {
                normal = {1, 1, 1, 1},
            },
        },
        stackText = {
            enabled = true,
            font = {"Mock Font", 10, "OUTLINE", false},
            position = {"BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0},
            color = {1, 1, 1, 1},
        },
        tooltip = {
            enabled = false,
        },
        auraTypeColor = {
            debuffType = harmful,
        },
        mode = harmful and "blacklist" or "whitelist",
        blacklist = {},
        whitelist = {},
    }
end

local function assertNoStructuralConfiguration(harness, message)
    for _, eventName in ipairs({
        "af.frame-level",
        "af.size",
        "af.flow",
        "af.processing",
        "af.group-filter",
        "af.group-count",
        "af.group-candidates",
        "af.group-sort",
        "af.group-layout",
        "container.clear-point",
        "container.point",
        "uf.position",
    }) do
        assertEqual(
            countEvents(harness, eventName),
            0,
            message .. " " .. eventName
        )
    end
end

-- This is a deterministic construction/lockdown scale test, not an in-client
-- memory or hitch profile. It models Raid's fixed 40 secure-header children,
-- their one header-born debuff shell plus one eagerly created buff shell, and
-- the compiler's audited ten-button initial batch per add-only group. It then
-- proves that runtime edits issue no further construction calls.
local function testRaidAuraScaleLockdown()
    local harness = makeHarness()
    local entries = {}
    local seenSeeds = {}
    local initialRestrictedButtons = 0

    for index = 1, 40 do
        local root = {
            name = "Raid" .. index,
            enabled = true,
            indicators = {},
        }
        local debuffSeed = newHeaderBornContainer(harness, root)
        local buffSeed = harness.UF.CreateNativeGroupAuraContainerSeed(root)
        assertTrue(buffSeed ~= debuffSeed, "per-root seeds are distinct")
        assertTrue(not seenSeeds[buffSeed], "buff seed was reused")
        assertTrue(not seenSeeds[debuffSeed], "debuff seed was reused")
        seenSeeds[buffSeed] = true
        seenSeeds[debuffSeed] = true

        root._nativeAuraContainers = {
            buffs = buffSeed,
            debuffs = debuffSeed,
        }
        local buffs = harness.UF.CreateGroupNativeAuras(
            root,
            root.name .. "_Buffs",
            "HELPFUL",
            "buffs"
        )
        local debuffs = harness.UF.CreateGroupNativeAuras(
            root,
            root.name .. "_Debuffs",
            "HARMFUL",
            "debuffs"
        )
        buffs.enabled = true
        debuffs.enabled = true
        root.indicators.buffs = buffs
        root.indicators.debuffs = debuffs

        buffs:LoadConfig(newAuraConfig("HELPFUL", 0))
        debuffs:LoadConfig(newAuraConfig("HARMFUL", 0))
        buffs:Enable()
        debuffs:Enable()

        for _, runtime in ipairs({buffs, debuffs}) do
            local state = runtime:GetNativeAuraState()
            assertEqual(state.state, "READY", "initial Raid aura state")
            assertEqual(state.unit, "none", "initial group-empty unit")
            assertEqual(state.built, true, "initial Raid aura build")
            initialRestrictedButtons = initialRestrictedButtons
                + state.metrics.initialRestrictedButtonCount
        end

        entries[#entries + 1] = {
            root = root,
            buffs = buffs,
            debuffs = debuffs,
            buffSeed = buffSeed,
            debuffSeed = debuffSeed,
        }
    end

    assertEqual(#entries, 40, "Raid root count")
    assertEqual(tableCount(seenSeeds), 80, "distinct supplied seed count")
    assertEqual(#harness.containers, 80, "initial Raid container count")
    assertEqual(
        countEvents(harness, "header.container"),
        40,
        "header-born debuff container count"
    )
    assertEqual(
        countEvents(harness, "af.create-container"),
        40,
        "eager buff container count"
    )
    assertEqual(totalGroupCount(harness), 160, "initial native group count")
    assertEqual(
        initialRestrictedButtons,
        1600,
        "compiled default restricted-button contract"
    )
    assertEqual(
        harness.staticRestrictedButtonCount,
        1600,
        "declared default restricted-button contract"
    )

    for _, entry in ipairs(entries) do
        assertEqual(entry.buffs._controller._container, entry.buffSeed,
            "buff seed adoption")
        assertEqual(entry.debuffs._controller._container, entry.debuffSeed,
            "debuff seed adoption")
        assertEqual(entry.buffSeed.seedOrigin, "eager",
            "buff eager seed origin")
        assertEqual(entry.debuffSeed.seedOrigin, "secure-header",
            "debuff header seed origin")
        assertEqual(entry.buffs._controller._buildAttempted, true,
            "buff one-shot construction latch")
        assertEqual(entry.debuffs._controller._buildAttempted, true,
            "debuff one-shot construction latch")
        assertEqual(entry.buffSeed.unit, "none", "buff empty unit")
        assertEqual(entry.debuffSeed.unit, "none", "debuff empty unit")
        assertEqual(tableCount(entry.buffSeed.groups), 1,
            "initial buff group count")
        assertEqual(tableCount(entry.debuffSeed.groups), 3,
            "initial debuff group count")
    end

    local fixedContainerCount = #harness.containers
    local fixedGroupCount = totalGroupCount(harness)
    local fixedRestrictedButtons = harness.staticRestrictedButtonCount

    ---------------------------------------------------------------------
    -- Repeated out-of-combat construction edits are reload-only.
    ---------------------------------------------------------------------
    harness:ClearEvents()

    for _, entry in ipairs(entries) do
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 1))
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 2))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 1))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 2))
    end

    for index, entry in ipairs(entries) do
        local unit = "raid" .. index
        entry.root.unit = unit
        entry.root.effectiveUnit = unit
        entry.buffs:Update()
        entry.debuffs:Update()
    end

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "OOC construction edits"
    )
    assertEqual(countEvents(harness, "af.unit"), 0,
        "reload-only OOC retarget count")
    assertEqual(#harness.timers, 0, "reload-only OOC timer count")

    for index, entry in ipairs(entries) do
        local unit = "raid" .. index
        for _, runtime in ipairs({entry.buffs, entry.debuffs}) do
            local state = runtime:GetNativeAuraState()
            assertEqual(state.unit, unit, "reload-only desired Raid unit")
            assertEqual(state.reloadRequired, true,
                "OOC construction reload state")
            assertEqual(state.pending, false,
                "OOC construction pending state")
            assertEqual(runtime._controller._container.unit, "none",
                "reload-only native unit")
            assertEqual(runtime._controller._container.enabled, false,
                "reload-only native enabled state")
            assertEqual(runtime:IsShown(), false,
                "reload-only holder visibility")
        end
    end

    ---------------------------------------------------------------------
    -- Exact construction-key reversion resumes with tuning and retargets.
    ---------------------------------------------------------------------
    harness:ClearEvents()
    for _, entry in ipairs(entries) do
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 3, 0))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 3, 0))
    end
    harness:RunTimers(0.15)

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "OOC exact reversion"
    )
    assertEqual(countEvents(harness, "uf.position"), 80,
        "OOC exact-reversion placement count")
    assertEqual(countEvents(harness, "af.flow"), 80,
        "OOC exact-reversion flow count")
    assertEqual(countEvents(harness, "af.group-layout"), 160,
        "OOC exact-reversion group tuning count")
    assertEqual(countEvents(harness, "af.unit"), 80,
        "OOC exact-reversion retarget count")
    assertCleanNativeUnitEvents(harness)

    local firstReversionHelpful = newAuraConfig("HELPFUL", 3, 0)
    local firstReversionHarmful = newAuraConfig("HARMFUL", 3, 0)
    for index, entry in ipairs(entries) do
        local unit = "raid" .. index
        for _, expected in ipairs({
            {
                runtime = entry.buffs,
                config = firstReversionHelpful,
            },
            {
                runtime = entry.debuffs,
                config = firstReversionHarmful,
            },
        }) do
            local runtime = expected.runtime
            local controller = runtime._controller
            local state = runtime:GetNativeAuraState()
            assertEqual(state.reloadRequired, false,
                "OOC exact-reversion reload state")
            assertEqual(state.pending, false,
                "OOC exact-reversion pending state")
            assertEqual(controller._container.unit, unit,
                "OOC exact-reversion native unit")
            assertEqual(
                controller.frame.indicatorPosition[3],
                expected.config.position[3],
                "OOC exact-reversion holder position"
            )
            assertEqual(controller.frame.appliedFrameLevel,
                expected.config.frameLevel,
                "OOC exact-reversion frame level")
            assertEqual(runtime:IsShown(), true,
                "OOC exact-reversion holder visibility")
        end
    end

    ---------------------------------------------------------------------
    -- Repeated combat construction edits quiesce and stay reload-only.
    ---------------------------------------------------------------------
    harness:ClearEvents()
    harness:SetCombat(true)
    for _, entry in ipairs(entries) do
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 4))
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 5))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 4))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 5))
    end

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "combat construction edits"
    )
    assertNoStructuralConfiguration(harness, "combat construction edits")
    assertEqual(countEvents(harness, "af.enabled"), 0,
        "combat native enabled-state mutation count")
    assertEqual(countEvents(harness, "af.unit"), 0,
        "combat construction retarget count")

    for _, entry in ipairs(entries) do
        for _, runtime in ipairs({entry.buffs, entry.debuffs}) do
            local state = runtime:GetNativeAuraState()
            assertEqual(state.reloadRequired, true,
                "combat construction reload state")
            assertEqual(state.pending, true,
                "combat construction quiesce pending state")
            assertEqual(runtime:IsShown(), false,
                "combat construction holder visibility")
            assertEqual(runtime._controller._container.enabled, true,
                "combat deferred native enabled state")
        end
    end

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "post-regen reload quiesce"
    )
    assertEqual(#harness.containers, 80,
        "post-regen one-shot container count")
    assertEqual(
        harness.registered.PLAYER_REGEN_ENABLED,
        nil,
        "post-regen registration cleanup"
    )
    for _, entry in ipairs(entries) do
        for _, runtime in ipairs({entry.buffs, entry.debuffs}) do
            local state = runtime:GetNativeAuraState()
            assertEqual(state.reloadRequired, true,
                "post-regen reload state")
            assertEqual(state.pending, false,
                "post-regen pending state")
            assertEqual(runtime._controller._container.enabled, false,
                "post-regen native enabled state")
            assertEqual(runtime:IsShown(), false,
                "post-regen holder visibility")
        end
    end

    ---------------------------------------------------------------------
    -- A second exact reversion applies the latest tuning, placement, unit.
    ---------------------------------------------------------------------
    for index, entry in ipairs(entries) do
        local unit = "raid" .. index .. "next"
        entry.root.unit = unit
        entry.root.effectiveUnit = unit
    end
    harness:ClearEvents()
    for _, entry in ipairs(entries) do
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 6, 0))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 6, 0))
    end
    harness:RunTimers(0.15)

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "post-combat exact reversion"
    )
    assertEqual(countEvents(harness, "uf.position"), 80,
        "post-combat exact-reversion placement count")
    assertEqual(countEvents(harness, "af.flow"), 80,
        "post-combat exact-reversion flow count")
    assertEqual(countEvents(harness, "af.group-layout"), 160,
        "post-combat exact-reversion group tuning count")
    assertEqual(countEvents(harness, "af.unit"), 80,
        "post-combat exact-reversion retarget count")
    assertCleanNativeUnitEvents(harness)

    local latestHelpful = newAuraConfig("HELPFUL", 6, 0)
    local latestHarmful = newAuraConfig("HARMFUL", 6, 0)
    local revertedRestrictedButtons = 0
    for index, entry in ipairs(entries) do
        local unit = "raid" .. index .. "next"
        for _, expected in ipairs({
            {
                runtime = entry.buffs,
                config = latestHelpful,
                groupCount = 1,
            },
            {
                runtime = entry.debuffs,
                config = latestHarmful,
                groupCount = 3,
            },
        }) do
            local runtime = expected.runtime
            local controller = runtime._controller
            local container = controller._container
            local state = runtime:GetNativeAuraState()

            assertEqual(
                container,
                expected.runtime == entry.buffs
                    and entry.buffSeed
                    or entry.debuffSeed,
                "exact reversion retains supplied seed"
            )
            assertEqual(container.unit, unit,
                "post-combat exact-reversion native unit")
            assertEqual(tableCount(container.groups), expected.groupCount,
                "post-combat exact-reversion group topology")
            assertEqual(
                controller.frame.indicatorPosition[3],
                expected.config.position[3],
                "post-combat latest holder position"
            )
            assertEqual(
                controller.frame.appliedFrameLevel,
                expected.config.frameLevel,
                "post-combat latest holder frame level"
            )
            for _, group in pairs(container.groups) do
                assertEqual(group.buttonStyle.width, expected.config.width,
                    "exact-key button width")
                assertEqual(
                    group.buttonStyle.cooldownStyle,
                    expected.config.cooldownStyle,
                    "exact-key cooldown style"
                )
                assertEqual(
                    group.options.maxFrameCount,
                    expected.config.numTotal,
                    "post-combat latest group maximum"
                )
                assertEqual(
                    group.options.layout.elementSpacing,
                    expected.config.spacingX,
                    "post-combat latest group spacing"
                )
            end
            revertedRestrictedButtons = revertedRestrictedButtons
                + state.metrics.initialRestrictedButtonCount
            assertEqual(state.unit, unit,
                "post-combat exact-reversion runtime unit")
            assertEqual(state.state, "READY",
                "post-combat exact-reversion runtime state")
            assertEqual(state.pending, false,
                "post-combat exact-reversion pending state")
            assertEqual(state.reloadRequired, false,
                "post-combat exact-reversion reload state")
            assertEqual(runtime:IsShown(), true,
                "post-combat exact-reversion holder visibility")
        end
    end
    assertEqual(
        revertedRestrictedButtons,
        fixedRestrictedButtons,
        "post-combat compiled restricted-button contract"
    )

    ---------------------------------------------------------------------
    -- Secret group units are sanitized to "none"; recovery is retarget-only.
    ---------------------------------------------------------------------
    harness:ClearEvents()
    for _, entry in ipairs(entries) do
        entry.root.effectiveUnit = {
            secret = true,
        }
        entry.buffs:Update()
        entry.debuffs:Update()
    end

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "secret-unit sanitation"
    )
    assertNoStructuralConfiguration(harness, "secret-unit sanitation")
    assertEqual(countEvents(harness, "af.unit"), 80,
        "secret-unit inert retarget count")
    assertEqual(countEvents(harness, "af.update"), 80,
        "secret-unit inert refresh count")
    assertCleanNativeUnitEvents(harness, "none")
    for _, entry in ipairs(entries) do
        for _, runtime in ipairs({entry.buffs, entry.debuffs}) do
            local state = runtime:GetNativeAuraState()
            assertEqual(state.state, "READY",
                "secret group-unit runtime state")
            assertEqual(state.unit, "none",
                "secret group-unit sanitized token")
            assertEqual(state.reloadRequired, false,
                "secret group-unit reload state")
            assertEqual(runtime._controller._container.unit, "none",
                "secret group-unit native token")
        end
    end

    harness:ClearEvents()
    for _, entry in ipairs(entries) do
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 7, 0))
        entry.buffs:LoadConfig(newAuraConfig("HELPFUL", 8, 0))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 7, 0))
        entry.debuffs:LoadConfig(newAuraConfig("HARMFUL", 8, 0))
    end
    harness:RunTimers(0.15)

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "secret-unit latest tuning"
    )
    assertEqual(countEvents(harness, "uf.position"), 80,
        "secret-unit latest placement count")
    assertEqual(countEvents(harness, "af.group-layout"), 160,
        "secret-unit latest group tuning count")
    assertEqual(countEvents(harness, "af.unit"), 0,
        "secret-unit latest tuning retarget count")

    local secretHelpful = newAuraConfig("HELPFUL", 8, 0)
    local secretHarmful = newAuraConfig("HARMFUL", 8, 0)
    for _, entry in ipairs(entries) do
        for _, expected in ipairs({
            {
                runtime = entry.buffs,
                config = secretHelpful,
            },
            {
                runtime = entry.debuffs,
                config = secretHarmful,
            },
        }) do
            local runtime = expected.runtime
            local controller = runtime._controller
            assertEqual(controller.frame.indicatorPosition[3],
                expected.config.position[3],
                "secret-unit latest holder position")
            for _, group in pairs(controller._container.groups) do
                assertEqual(
                    group.options.layout.elementSpacing,
                    expected.config.spacingX,
                    "secret-unit latest group spacing"
                )
            end
            assertEqual(runtime:GetNativeAuraState().pending, false,
                "secret-unit latest tuning pending state")
        end
    end

    harness:ClearEvents()
    for index, entry in ipairs(entries) do
        local unit = "raid" .. index .. "recovered"
        entry.root.unit = unit
        entry.root.effectiveUnit = unit
        entry.buffs:Update()
        entry.debuffs:Update()
    end

    assertNoNativeConstruction(
        harness,
        fixedContainerCount,
        fixedGroupCount,
        fixedRestrictedButtons,
        "clean group-unit recovery"
    )
    assertNoStructuralConfiguration(harness, "clean group-unit recovery")
    assertEqual(countEvents(harness, "af.unit"), 80,
        "clean group-unit recovery retarget count")
    assertEqual(countEvents(harness, "af.update"), 80,
        "clean group-unit recovery refresh count")
    assertCleanNativeUnitEvents(harness)

    for index, entry in ipairs(entries) do
        local unit = "raid" .. index .. "recovered"
        for _, expected in ipairs({
            {
                runtime = entry.buffs,
                config = secretHelpful,
            },
            {
                runtime = entry.debuffs,
                config = secretHarmful,
            },
        }) do
            local runtime = expected.runtime
            local controller = runtime._controller
            local state = runtime:GetNativeAuraState()
            assertEqual(state.unit, unit,
                "clean group-unit recovery runtime token")
            assertEqual(controller._container.unit, unit,
                "clean group-unit recovery native token")
            assertEqual(state.pending, false,
                "clean group-unit recovery pending state")
            assertEqual(state.reloadRequired, false,
                "clean group-unit recovery reload state")
            assertEqual(controller.frame.indicatorPosition[3],
                expected.config.position[3],
                "clean recovery retains latest placement")
            for _, group in pairs(controller._container.groups) do
                assertEqual(
                    group.options.layout.elementSpacing,
                    expected.config.spacingX,
                    "clean recovery retains latest tuning"
                )
            end
        end
    end

    for _, unit in ipairs(harness.nativeUnitValues) do
        assertEqual(type(unit), "string",
            "all native SetUnit values remain clean strings")
    end
end

testRaidAuraScaleLockdown()

print("unit_frame_raid_aura_scale_test.lua: ok")
