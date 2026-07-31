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

local function deepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then
        return false
    end

    seen = seen or {}
    if seen[left] then return seen[left] == right end
    seen[left] = right

    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
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

local function lastEvent(harness, name)
    for index = #harness.events, 1, -1 do
        local event = harness.events[index]
        if event.name == name then return event end
    end
end

local function record(harness, name, ...)
    harness.events[#harness.events + 1] = {
        name = name,
        args = {n = select("#", ...), ...},
    }
end

local function validConfig(overrides)
    local config = {
        enabled = true,
        style = "style-a",
        tag = "initial",
        requiresVisible = false,
        requiresAssist = false,
    }
    for key, value in pairs(overrides or {}) do
        config[key] = value
    end
    return config
end

local function newRoot(name, unit)
    return {
        name = name,
        enabled = true,
        unit = unit,
        effectiveUnit = unit,
        indicators = {},
    }
end

local function makeHarness(options)
    options = options or {}

    local harness = {
        backend = options.backend ~= false,
        events = {},
        timers = {},
        controllers = {},
        legacyFrames = {},
        compiles = {},
        registered = {},
        visibleResult = true,
        assistResult = true,
        inCombat = false,
    }
    local UF = {}
    local AF = {}
    local F = {}

    function AF.Copy(value)
        return copy(value)
    end

    function AF.SetFrameLevel(frame, level, relativeTo)
        frame.frameLevel = level
        record(harness, "af.frame-level", frame, level, relativeTo)
    end

    function AF.AddToPixelUpdater_Auto(frame, callback, combatSafeOnly)
        frame.pixelCallback = callback
        frame.pixelCombatSafeOnly = combatSafeOnly
        record(harness, "af.pixel-add", frame, callback, combatSafeOnly)
    end

    function AF.RemoveFromPixelUpdater(frame)
        frame.pixelRemoved = true
        record(harness, "af.pixel-remove", frame)
    end

    function AF.ReSize(frame)
        record(harness, "af.resize", frame)
    end

    function AF.RePoint(frame)
        record(harness, "af.repoint", frame)
    end

    function F.isValueNonSecret(value)
        record(harness, "secret.check", value)
        return type(value) ~= "table" or value.secret ~= true
    end

    function UF.HasNativeAuraContainerBackend()
        record(harness, "uf.backend")
        return harness.backend
    end

    local function newController(parent, name)
        local frame = {
            name = name,
            parent = parent,
            shown = false,
        }
        function frame:GetName()
            return self.name
        end
        function frame:IsShown()
            error("runtime must not observe holder visibility")
        end

        local controller = {
            frame = frame,
            shown = false,
        }
        function controller:GetFrame()
            return self.frame
        end
        function controller:ApplyHolderConfig(callback)
            record(harness, "controller.holder-config", self, callback)
            callback(self.frame)
        end
        function controller:Rebuild(spec)
            self.spec = copy(spec)
            self.built = true
            self.enabled = spec.enabled
            self.shown = spec.shown
            self.frame.shown = spec.shown
            record(harness, "controller.rebuild", self, spec)
        end
        function controller:ApplyTuning(tuning)
            self.tuning = copy(tuning)
            record(harness, "controller.tuning", self, tuning)
        end
        function controller:SetUnit(unit)
            if self.unit == unit then return end
            self.unit = unit
            if self.spec then self.spec.unit = unit end
            record(harness, "controller.unit", self, unit)
        end
        function controller:SetEnabled(enabled)
            if self.enabled == enabled then return end
            self.enabled = enabled
            if self.spec then self.spec.enabled = enabled end
            record(harness, "controller.enabled", self, enabled)
        end
        function controller:SetShown(shown)
            if self.shown == shown then return end
            self.shown = shown
            if self.spec then self.spec.shown = shown end
            record(harness, "controller.shown", self, shown)
        end
        function controller:Refresh()
            self.refreshCount = (self.refreshCount or 0) + 1
            record(harness, "controller.refresh", self)
        end
        function controller:Destroy()
            self.destroyed = true
            record(harness, "controller.destroy", self)
        end

        harness.controllers[#harness.controllers + 1] = controller
        record(harness, "uf.controller", controller, parent, name)
        return controller
    end

    function UF.CreateNativeAuraContainerController(parent, name)
        return newController(parent, name)
    end

    function UF.CompileNativeAuraSpec(unit, auraFilter, config)
        local configCopy = copy(config)
        harness.compiles[#harness.compiles + 1] = {
            unit = unit,
            auraFilter = auraFilter,
            config = configCopy,
        }
        record(harness, "uf.compile", unit, auraFilter, configCopy)

        if config.testState == "error" then
            return nil, "TEST_COMPILE_ERROR"
        end

        local empty = config.testState == "empty"
        local partitioned = config.testState == "partition"
        local descriptor = {
            completeSpec = nil,
            tuningSpec = nil,
            constructionKey = {
                groups = {
                    {
                        key = "group",
                        buttonStyle = {
                            style = config.style,
                        },
                    },
                },
                slots = {},
            },
            placement = {
                position = {"TOPLEFT", "TOPLEFT", config.offset or 0, 0},
                anchorTo = "root",
                frameLevel = config.frameLevel or 4,
            },
            visibility = {
                requiresVisible = config.requiresVisible == true,
                requiresAssist = config.requiresAssist == true,
            },
            partition = partitioned and {
                filter = "notCastByMe",
            } or nil,
            migrationReady = not empty and not partitioned,
            empty = empty,
            diagnostics = {config.tag},
            degradations = {
                test = config.tag,
            },
            metrics = {
                groupCount = empty and 0 or 1,
            },
        }

        if not empty then
            descriptor.completeSpec = {
                unit = unit,
                enabled = config.enabled,
                shown = false,
                holder = {
                    width = config.width or 20,
                    height = config.height or 10,
                },
                groups = {
                    {
                        key = "group",
                        filterString = config.tag,
                        buttonStyle = {
                            style = config.style,
                        },
                    },
                },
                slots = {},
            }
            descriptor.tuningSpec = {
                tag = config.tag,
                holder = copy(descriptor.completeSpec.holder),
                groups = {
                    {
                        key = "group",
                        filterString = config.tag,
                    },
                },
                slots = {},
            }
        end
        return descriptor
    end

    function UF.LoadIndicatorPosition(frame, position, anchorTo)
        frame.position = copy(position)
        frame.anchorTo = anchorTo
        record(harness, "uf.position", frame, position, anchorTo)
    end

    function UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
        local preview = {
            parent = parent,
            name = name,
            auraFilter = auraFilter,
            hasSubFrame = hasSubFrame,
        }
        function preview:LoadConfig(config)
            self.config = copy(config)
            record(harness, "legacy.load", self, config)
        end
        function preview:EnableConfigMode()
            self.configMode = true
            record(harness, "legacy.config-enable", self)
        end
        function preview:DisableConfigMode()
            self.configMode = false
            record(harness, "legacy.config-disable", self)
        end
        function preview:Disable()
            self.disabled = true
            record(harness, "legacy.disable", self)
        end

        harness.legacyFrames[#harness.legacyFrames + 1] = preview
        record(
            harness,
            "uf.legacy",
            preview,
            parent,
            name,
            auraFilter,
            hasSubFrame
        )
        return preview
    end

    function UF:RegisterEvent(event, callback)
        self.registeredByRuntime = true
        harness.registered[event] = harness.registered[event] or {}
        harness.registered[event][callback] = true
        record(harness, "uf.register", event, callback)
    end

    function UF:UnregisterEvent(event, callback)
        assertTrue(
            harness.registered[event]
                and harness.registered[event][callback],
            "unregistering an unknown runtime callback"
        )
        harness.registered[event][callback] = nil
        if next(harness.registered[event]) == nil then
            harness.registered[event] = nil
        end
        record(harness, "uf.unregister", event, callback)
    end

    local BFI = {
        funcs = F,
        modules = {
            UnitFrames = UF,
        },
    }

    local function forbidden(name)
        return function()
            error("forbidden aura-runtime dependency: " .. name, 2)
        end
    end

    local environment = {
        _G = false,
        AbstractFramework = AF,
        C_Timer = {
            After = function(delay, callback)
                harness.timers[#harness.timers + 1] = {
                    delay = delay,
                    callback = callback,
                }
                record(harness, "timer", delay, callback)
            end,
        },
        UnitCanAssist = function(sourceUnit, unit)
            assertEqual(sourceUnit, "player", "assist source unit")
            record(harness, "wow.assist", sourceUnit, unit)
            return harness.assistResult
        end,
        UnitIsVisible = function(unit)
            record(harness, "wow.visible", unit)
            return harness.visibleResult
        end,
        AuraData = setmetatable({}, {
            __index = function()
                error("forbidden aura-runtime dependency: AuraData", 2)
            end,
        }),
        C_UnitAuras = setmetatable({}, {
            __index = function()
                error("forbidden aura-runtime dependency: C_UnitAuras", 2)
            end,
        }),
        CreateFrame = forbidden("CreateFrame"),
        InCombatLockdown = function()
            return harness.inCombat
        end,
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected aura-runtime global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError = loadfile("Modules/UnitFrames/AuraRuntime.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.BFI = BFI
    harness.UF = UF

    function harness:ClearEvents()
        self.events = {}
    end

    function harness:SetCombat(inCombat)
        self.inCombat = inCombat
    end

    function harness:RunTimers(delay)
        local timers = self.timers
        self.timers = {}
        for _, timer in ipairs(timers) do
            if timer.delay == delay then
                timer.callback()
            else
                self.timers[#self.timers + 1] = timer
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

local function createRuntime(harness, root, hasSubFrame)
    local runtime = harness.UF.CreateNativeAuraIndicator(
        root,
        root.name .. "_Auras",
        "HELPFUL",
        hasSubFrame
    )
    assertTrue(runtime, "native runtime was not created")
    runtime.enabled = true
    root.indicators.buffs = runtime
    return runtime, harness.controllers[#harness.controllers]
end

local function testDormancyAndFallback()
    local harness = makeHarness()
    assertEqual(#harness.controllers, 0, "dormant controller count")
    assertEqual(#harness.legacyFrames, 0, "dormant legacy count")
    assertEqual(#harness.compiles, 0, "dormant compile count")
    assertEqual(next(harness.registered), nil, "dormant event registrations")
    assertEqual(countEvents(harness, "af.pixel-add"), 0, "dormant pixel updater")

    local unavailable = makeHarness({backend = false})
    local root = newRoot("Fallback", "target")
    local direct, directError = unavailable.UF.CreateNativeAuraIndicator(
        root,
        "Fallback_Auras",
        "HELPFUL",
        false
    )
    assertEqual(direct, nil, "unavailable direct runtime")
    assertEqual(directError, "NATIVE_AURA_BACKEND_UNAVAILABLE",
        "unavailable direct error")
    assertEqual(#unavailable.controllers, 0, "unavailable controller count")

    local fallback = unavailable.UF.CreateNativeAuras(
        root,
        "Fallback_Auras",
        "HELPFUL",
        false
    )
    assertEqual(fallback, unavailable.legacyFrames[1], "12.0.7 legacy fallback")
    assertEqual(fallback.parent, root, "fallback parent")
    assertEqual(fallback.name, "Fallback_Auras", "fallback name")
    assertEqual(fallback.auraFilter, "HELPFUL", "fallback filter")
    assertEqual(fallback.hasSubFrame, false, "fallback subframe")

    local partitionFallback = harness.UF.CreateNativeAuras(
        root,
        "Partition_Auras",
        "HARMFUL",
        true
    )
    assertEqual(partitionFallback, harness.legacyFrames[1],
        "partition legacy fallback")
    assertEqual(#harness.controllers, 0, "partition controller count")

    local native = harness.UF.CreateNativeAuras(
        root,
        "Native_Auras",
        "HELPFUL",
        false
    )
    assertTrue(native, "native selector result")
    assertEqual(#harness.controllers, 1, "native selector controller count")
    assertEqual(countEvents(harness, "af.pixel-add"), 1,
        "native pixel updater count")

    local disabledHarness = makeHarness()
    local disabledRoot = newRoot("Disabled", "target")
    local disabledRuntime, disabledController = createRuntime(
        disabledHarness,
        disabledRoot
    )
    disabledRuntime:LoadConfig(validConfig({enabled = false}))
    assertEqual(disabledController.built, nil,
        "direct disabled config native allocation")
end

local function testLifecycleAndUnitRefresh()
    local harness = makeHarness()
    local root = newRoot("Lifecycle", "player")
    local runtime, controller = createRuntime(harness, root)
    local config = validConfig()
    local original = copy(config)

    runtime:LoadConfig(config)
    assertTrue(deepEqual(config, original), "LoadConfig mutated its input")
    assertEqual(countEvents(harness, "controller.rebuild"), 1,
        "initial rebuild count")
    assertEqual(controller.enabled, true, "hidden native enabled")
    assertEqual(controller.shown, false, "hidden native holder")

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "READY", "initial runtime state")
    assertEqual(state.built, true, "initial built state")
    assertEqual(state.active, false, "initial active state")
    assertEqual(next(harness.registered), nil, "hidden watcher registration")

    harness:ClearEvents()
    runtime:Enable()
    assertEqual(controller.shown, true, "enabled holder visibility")
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "enable refresh count")
    assertEqual(countEvents(harness, "uf.register"), 0,
        "ungated watcher registrations")

    harness:ClearEvents()
    runtime:Update()
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "stable-token refresh count")

    harness:ClearEvents()
    runtime.pixelCallback(runtime)
    assertEqual(countEvents(harness, "controller.holder-config"), 1,
        "pixel holder-gate count")
    assertEqual(countEvents(harness, "af.resize"), 1,
        "pixel resize count")
    assertEqual(countEvents(harness, "af.repoint"), 1,
        "pixel repoint count")

    root.effectiveUnit = "vehicle"
    harness:ClearEvents()
    runtime:Update()
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "vehicle retarget count")
    assertEqual(lastEvent(harness, "controller.unit").args[2], "vehicle",
        "vehicle retarget unit")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "vehicle retarget rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "vehicle retarget tuning count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "vehicle retarget placement count")
    assertEqual(controller.shown, true, "vehicle retarget visibility")

    harness:ClearEvents()
    runtime:Disable()
    assertEqual(controller.shown, false, "disabled holder visibility")
    assertEqual(controller.enabled, true, "hidden root native prewarm")
    assertEqual(countEvents(harness, "uf.unregister"), 0,
        "ungated watcher unregistrations")
    assertEqual(next(harness.registered), nil, "watcher cleanup")

    root.enabled = false
    runtime:Disable()
    assertEqual(controller.enabled, false, "module-disabled native state")

    root.enabled = true
    runtime:Enable()
    assertEqual(controller.enabled, true, "re-enabled native state")
    assertEqual(controller.shown, true, "re-enabled holder state")
end

local function testDebounceAndConstructionReuse()
    local harness = makeHarness()
    local root = newRoot("Debounce", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        tag = "stale-tuning",
        offset = 1,
    }))
    runtime:LoadConfig(validConfig({
        tag = "latest-tuning",
        offset = 2,
    }))
    runtime:Update()
    assertEqual(controller.shown, false,
        "pending configuration stale-holder suppression")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "pre-debounce tuning count")
    assertEqual(runtime:GetNativeAuraState().pending, true,
        "pending debounce state")

    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "coalesced tuning count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "same-construction rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 1,
        "coalesced placement count")
    assertEqual(controller.tuning.tag, "latest-tuning",
        "latest tuning payload")
    assertEqual(controller.frame.position[3], 2, "latest placement payload")
    assertEqual(runtime:GetNativeAuraState().pending, false,
        "settled debounce state")

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "stale-rebuild",
    }))
    runtime:LoadConfig(validConfig({
        style = "style-c",
        tag = "latest-rebuild",
    }))
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.rebuild"), 1,
        "coalesced construction rebuild count")
    assertEqual(lastEvent(harness, "controller.rebuild").args[2]
        .groups[1].filterString, "latest-rebuild", "latest rebuild payload")
end

local function testControllerLedgerCommitUsesLatestConfig()
    local harness = makeHarness()
    local root = newRoot("LedgerCommit", "player")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        tag = "stale-ledger",
    }))
    runtime:LoadConfig(validConfig({
        tag = "latest-ledger",
    }))
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "controller-ledger tuning count")
    assertEqual(controller.tuning.tag, "latest-ledger",
        "controller-ledger latest tuning")
    assertEqual(controller.shown, true,
        "controller-ledger holder visibility")
    assertEqual(runtime:GetNativeAuraState().pending, false,
        "controller-ledger settled state")
end

local function testRuntimeHasNoHolderVisibilityReads()
    local file = assert(io.open(
        "Modules/UnitFrames/AuraRuntime.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()

    local forbiddenMethods = {
        "IsShown",
        "IsVisible",
        "IsMouseOver",
        "GetAlpha",
    }
    for _, method in ipairs(forbiddenMethods) do
        assertTrue(
            source:find(":" .. method .. "(", 1, true) == nil,
            "runtime reads holder visibility through " .. method
        )
    end
end

local function testSharedCombatCommitQueue()
    local harness = makeHarness()
    local firstRoot = newRoot("CombatFirst", "player")
    local secondRoot = newRoot("CombatSecond", "pet")
    local firstRuntime, firstController = createRuntime(harness, firstRoot)
    local secondRuntime, secondController = createRuntime(
        harness,
        secondRoot
    )

    harness:SetCombat(true)
    harness:ClearEvents()
    firstRuntime:LoadConfig(validConfig({tag = "first"}))
    secondRuntime:LoadConfig(validConfig({tag = "second"}))
    assertEqual(firstController.built, nil, "first combat build state")
    assertEqual(secondController.built, nil, "second combat build state")
    assertEqual(countEvents(harness, "uf.register"), 1,
        "shared combat registration count")

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)
    assertEqual(firstController.built, true, "first regen build state")
    assertEqual(secondController.built, true, "second regen build state")
    assertEqual(firstController.spec.groups[1].filterString, "first",
        "first regen payload")
    assertEqual(secondController.spec.groups[1].filterString, "second",
        "second regen payload")
    assertEqual(countEvents(harness, "uf.unregister"), 1,
        "shared combat unregister count")
end

local function testCombatConfigSupersession()
    local harness = makeHarness()
    local root = newRoot("CombatSupersession", "player")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:SetCombat(true)
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "obsolete-combat-build",
    }))
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "combat replacement count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "combat placement count")
    assertEqual(countEvents(harness, "uf.register"), 1,
        "combat commit registration")

    runtime:LoadConfig(validConfig({
        testState = "empty",
        tag = "final-empty",
    }))
    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)
    harness:RunTimers(0.15)

    assertEqual(runtime:GetNativeAuraState().state, "EMPTY",
        "combat superseded state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "superseded replacement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "superseded tuning count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "superseded placement count")
    assertEqual(controller.enabled, false,
        "superseded native enabled state")
end

local function testUngatedFocusWatcher()
    local harness = makeHarness()
    local root = newRoot("DynamicFocus", "focus")
    local runtime = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    assertEqual(countEvents(harness, "uf.register"), 9,
        "dynamic focus watcher registrations")

    harness:ClearEvents()
    harness:Fire("PLAYER_FOCUS_CHANGED")
    harness:RunTimers(0.05)
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "dynamic focus refresh")
    assertEqual(countEvents(harness, "wow.visible"), 0,
        "ungated focus visibility calls")
    assertEqual(countEvents(harness, "wow.assist"), 0,
        "ungated focus assist calls")

    runtime:Disable()
    assertEqual(countEvents(harness, "uf.unregister"), 9,
        "dynamic focus watcher cleanup")
end

local function testWatcherRoutesUnitSignals()
    local harness = makeHarness()
    local focusRoot = newRoot("RoutedFocus", "focus")
    local targetRoot = newRoot("RoutedTarget", "target")
    local focusRuntime, focusController = createRuntime(
        harness,
        focusRoot
    )
    local targetRuntime, targetController = createRuntime(
        harness,
        targetRoot
    )

    focusRuntime:LoadConfig(validConfig())
    targetRuntime:LoadConfig(validConfig())
    focusRuntime:Enable()
    targetRuntime:Enable()
    local focusRefreshes = focusController.refreshCount
    local targetRefreshes = targetController.refreshCount

    harness:Fire("UNIT_PHASE", "focus")
    harness:RunTimers(0.05)
    assertEqual(focusController.refreshCount, focusRefreshes + 1,
        "unit-routed focus refresh")
    assertEqual(targetController.refreshCount, targetRefreshes,
        "unit-routed target suppression")

    harness:Fire("PLAYER_TARGET_CHANGED")
    harness:RunTimers(0.05)
    assertEqual(focusController.refreshCount, focusRefreshes + 1,
        "target-event focus suppression")
    assertEqual(targetController.refreshCount, targetRefreshes + 1,
        "target-event target refresh")

    harness:Fire("GROUP_ROSTER_UPDATE")
    harness:RunTimers(0.05)
    assertEqual(focusController.refreshCount, focusRefreshes + 2,
        "global focus refresh")
    assertEqual(targetController.refreshCount, targetRefreshes + 2,
        "global target refresh")

    focusRuntime:Disable()
    targetRuntime:Disable()
end

local function testQuiesceAndRecovery()
    local harness = makeHarness()
    local root = newRoot("Recovery", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()

    runtime:LoadConfig(validConfig({
        testState = "empty",
        tag = "empty",
    }))
    harness:RunTimers(0.15)
    assertEqual(runtime:GetNativeAuraState().state, "EMPTY", "empty state")
    assertEqual(controller.enabled, false, "empty native state")
    assertEqual(controller.shown, false, "empty holder state")
    assertEqual(countEvents(harness, "controller.destroy"), 0,
        "empty destroy count")

    runtime:LoadConfig(validConfig({
        testState = "partition",
        tag = "partition",
    }))
    harness:RunTimers(0.15)
    local partitionState = runtime:GetNativeAuraState()
    assertEqual(partitionState.state, "PARTITION_DEFERRED",
        "partition state")
    assertEqual(partitionState.partition.filter, "notCastByMe",
        "partition metadata")
    assertEqual(countEvents(harness, "controller.destroy"), 0,
        "partition destroy count")

    runtime:LoadConfig(validConfig({
        testState = "error",
    }))
    harness:RunTimers(0.15)
    local errorState = runtime:GetNativeAuraState()
    assertEqual(errorState.state, "ERROR", "compile error state")
    assertEqual(errorState.error, "TEST_COMPILE_ERROR", "compile error code")
    assertEqual(countEvents(harness, "controller.destroy"), 0,
        "compile error destroy count")

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        tag = "recovered",
    }))
    harness:RunTimers(0.15)
    assertEqual(runtime:GetNativeAuraState().state, "READY",
        "recovered state")
    assertEqual(controller.enabled, true, "recovered native state")
    assertEqual(controller.shown, true, "recovered holder state")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "recovery tuning count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "recovery rebuild count")
end

local function testSecretSafeWholeHolderGates()
    local harness = makeHarness()
    local root = newRoot("Gates", "focus")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig({
        requiresVisible = true,
        requiresAssist = true,
    }))
    harness.visibleResult = false
    harness.assistResult = true
    runtime:Enable()
    assertEqual(controller.enabled, true, "failed-gate native state")
    assertEqual(controller.shown, false, "definite visibility gate")

    harness.visibleResult = {secret = true}
    harness.assistResult = {secret = true}
    harness:ClearEvents()
    harness:Fire("UNIT_PHASE", "focus")
    harness:Fire("UNIT_FACTION", "focus")
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "pre-coalesce gate refresh")
    harness:RunTimers(0.05)
    assertEqual(controller.shown, true, "secret gate fail-open")
    assertTrue(countEvents(harness, "secret.check") >= 2,
        "secret gate checks")
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "gate event native refresh")

    harness.visibleResult = true
    harness.assistResult = false
    harness:Fire("UNIT_FACTION", "focus")
    harness:RunTimers(0.05)
    assertEqual(controller.shown, false, "definite assist gate")
    assertEqual(controller.enabled, true, "assist gate native state")

    harness.visibleResult = nil
    harness.assistResult = nil
    harness:Fire("GROUP_ROSTER_UPDATE")
    harness:RunTimers(0.05)
    assertEqual(controller.shown, true, "uncertain nil gate fail-open")

    harness:ClearEvents()
    harness:Fire("PLAYER_ENTERING_WORLD", true, false)
    assertEqual(countEvents(harness, "timer"), 3,
        "settled world timer count")
    harness:RunTimers(0.05)
    harness:RunTimers(2)
    harness:RunTimers(6)
    assertEqual(countEvents(harness, "controller.refresh"), 3,
        "world and settled refresh count")

    runtime:LoadConfig(validConfig({
        testState = "empty",
    }))
    assertEqual(next(harness.registered), nil,
        "invalid state watcher cleanup before commit")
    harness:RunTimers(0.15)

    runtime:Disable()
    harness:ClearEvents()
    harness:RunTimers(2)
    harness:RunTimers(6)
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "inactive settled refresh count")
end

local function testConfigModeNeverRetargetsPlayer()
    local harness = makeHarness()
    local root = newRoot("ConfigMode", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()

    root.inConfigMode = true
    runtime:Disable()
    root.oldUnit = "target"
    root.unit = "player"
    root.effectiveUnit = "player"
    runtime:EnableConfigMode()

    assertEqual(controller.enabled, false, "config-mode native state")
    assertEqual(controller.shown, false, "config-mode holder state")
    assertEqual(#harness.legacyFrames, 1, "lazy preview count")
    assertEqual(harness.legacyFrames[1].auraFilter, "HELPFUL",
        "preview aura filter")
    assertEqual(harness.legacyFrames[1].configMode, true,
        "preview config-mode state")

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "preview-edit",
    }))
    runtime:Enable()
    assertEqual(harness.compiles[#harness.compiles].unit, "target",
        "config-mode compile unit")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "config-mode native retarget count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "config-mode native rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "config-mode native tuning count")
    assertEqual(lastEvent(harness, "legacy.load").args[2].tag,
        "preview-edit", "preview config payload")

    runtime:DisableConfigMode()
    assertEqual(harness.legacyFrames[1].disabled, true,
        "preview disabled on exit")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "config-mode exit retarget count")

    root.unit = "target"
    root.effectiveUnit = "target"
    root.oldUnit = nil
    root.inConfigMode = nil
    runtime:Disable()

    assertEqual(countEvents(harness, "controller.unit"), 0,
        "restored same-unit retarget count")
    assertEqual(countEvents(harness, "controller.rebuild"), 1,
        "deferred config-mode rebuild count")
    assertEqual(lastEvent(harness, "controller.rebuild").args[2].unit,
        "target", "deferred rebuild unit")
    assertEqual(controller.enabled, true, "post-preview native prewarm")
    assertEqual(controller.shown, false, "post-preview hidden holder")

    runtime:Enable()
    assertEqual(controller.shown, true, "post-preview enabled holder")
end

local function testDisabledConfigModePreviewCannotEscape()
    local harness = makeHarness()
    local root = newRoot("DisabledPreview", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    root.inConfigMode = true
    runtime:Disable()
    root.oldUnit = "target"
    root.unit = "player"
    root.effectiveUnit = "player"
    runtime:EnableConfigMode()

    runtime.enabled = false
    runtime:LoadConfig(validConfig({
        enabled = false,
        tag = "disabled-preview",
    }))

    -- Keep stale-preview recovery defensive even if another caller skips
    -- the normal symmetric config-mode teardown.
    root.unit = "target"
    root.effectiveUnit = "target"
    root.oldUnit = nil
    root.inConfigMode = nil

    runtime.enabled = true
    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "live-after-preview",
    }))
    runtime:Enable()

    assertEqual(countEvents(harness, "legacy.config-disable"), 1,
        "stale preview config teardown")
    assertEqual(countEvents(harness, "legacy.disable"), 1,
        "stale preview visibility teardown")
    assertEqual(countEvents(harness, "legacy.config-enable"), 0,
        "stale preview reactivation")
    assertEqual(harness.compiles[#harness.compiles].unit, "target",
        "post-preview compile unit")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "post-preview player retarget count")
    assertEqual(runtime:GetNativeAuraState().configMode, false,
        "post-preview config-mode state")
    assertEqual(controller.shown, true, "post-preview live holder")
end

local function testWaitingUnitAndTerminalDestroy()
    local harness = makeHarness()
    local root = newRoot("Waiting", nil)
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    assertEqual(runtime:GetNativeAuraState().state, "WAITING_FOR_UNIT",
        "waiting state")
    assertEqual(controller.built, nil, "waiting build state")

    root.unit = "target"
    root.effectiveUnit = "target"
    runtime:Enable()
    assertEqual(runtime:GetNativeAuraState().state, "READY",
        "resolved waiting state")
    assertEqual(controller.built, true, "resolved build state")
    assertEqual(controller.spec.unit, "target", "resolved build unit")
    assertEqual(controller.shown, true, "resolved build visibility")

    local firstState = runtime:GetNativeAuraState()
    firstState.diagnostics[1] = "mutated"
    assertEqual(runtime:GetNativeAuraState().diagnostics[1], "initial",
        "status snapshot isolation")

    runtime:LoadConfig(validConfig({
        style = "style-b",
    }))
    runtime:Destroy()
    assertEqual(runtime:GetNativeAuraState().state, "DESTROYED",
        "destroyed state")
    assertEqual(controller.destroyed, true, "controller destroy state")
    assertEqual(next(harness.registered), nil, "destroy watcher cleanup")
    assertEqual(controller.frame.pixelRemoved, true, "pixel updater cleanup")

    local rebuilds = countEvents(harness, "controller.rebuild")
    local compiles = #harness.compiles
    runtime:LoadConfig(validConfig())
    runtime:Enable()
    runtime:Update()
    runtime:SetUnit("focus")
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.rebuild"), rebuilds,
        "stale timer rebuild count")
    assertEqual(#harness.compiles, compiles, "post-destroy compile count")
    local destroyedState = runtime:GetNativeAuraState()
    assertEqual(destroyedState.active, false, "destroyed active state")
    assertEqual(destroyedState.configMode, false, "destroyed config-mode state")
    assertEqual(destroyedState.pending, false, "destroyed pending state")
end

local function testPolymorphicGlobalRefreshSource()
    local file = assert(io.open(
        "Modules/UnitFrames/Indicators/Auras.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()

    assertTrue(source:find("buffs:Update%(true%)") ~= nil,
        "buff refresh is not polymorphic")
    assertTrue(source:find("debuffs:Update%(true%)") ~= nil,
        "debuff refresh is not polymorphic")
    assertTrue(source:find("Auras_Update%(buffs%)") == nil,
        "buff refresh still calls the legacy implementation")
    assertTrue(source:find("Auras_Update%(debuffs%)") == nil,
        "debuff refresh still calls the legacy implementation")
end

testDormancyAndFallback()
testLifecycleAndUnitRefresh()
testDebounceAndConstructionReuse()
testControllerLedgerCommitUsesLatestConfig()
testRuntimeHasNoHolderVisibilityReads()
testSharedCombatCommitQueue()
testCombatConfigSupersession()
testUngatedFocusWatcher()
testWatcherRoutesUnitSignals()
testQuiesceAndRecovery()
testSecretSafeWholeHolderGates()
testConfigModeNeverRetargetsPlayer()
testDisabledConfigModePreviewCannotEscape()
testWaitingUnitAndTerminalDestroy()
testPolymorphicGlobalRefreshSource()

print("unit_frame_aura_runtime_test.lua: ok")
