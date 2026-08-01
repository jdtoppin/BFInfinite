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

local function spellColorConstructionKey(spellColors)
    local colorKeys = {}
    local seen = {}
    for _, color in pairs(spellColors or {}) do
        local key = table.concat({
            tostring(color[1]),
            tostring(color[2]),
            tostring(color[3]),
            tostring(color[4]),
        }, "|")
        if not seen[key] then
            seen[key] = true
            colorKeys[#colorKeys + 1] = key
        end
    end
    table.sort(colorKeys)
    return colorKeys
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

local function countRegisteredCallbacks(harness)
    local count = 0
    for _, callbacks in pairs(harness.registered) do
        for _ in pairs(callbacks) do
            count = count + 1
        end
    end
    return count
end

local function assertProviderObserverOnly(harness, message)
    assertTrue(
        harness.registered.AURA_DATA_PROVIDER_SWITCH ~= nil,
        (message or "provider observer") .. " is not registered"
    )
    assertEqual(
        countRegisteredCallbacks(harness),
        1,
        (message or "provider observer") .. " callback count"
    )
end

local function assertNoProviderDrivenControllerWork(
    harness,
    message,
    allowCompile
)
    local prefix = message or "provider switch"
    local eventNames = {
        "controller.rebuild",
        "controller.tuning",
        "controller.unit",
        "controller.enabled",
        "controller.refresh",
        "controller.holder-config",
    }
    if not allowCompile then
        eventNames[#eventNames + 1] = "uf.compile"
    end
    for _, eventName in ipairs(eventNames) do
        assertEqual(
            countEvents(harness, eventName),
            0,
            prefix .. " " .. eventName
        )
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
        spellIDFilterRequiresPublicAssist = false,
        spellIDFilterRequiresPublicNonAssist = false,
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
        interfaceVersion = options.interfaceVersion or 120100,
        events = {},
        timers = {},
        controllers = {},
        legacyFrames = {},
        unavailableFrames = {},
        unavailableFrameBudget = options.unavailableFrameBudget or 0,
        compiles = {},
        registered = {},
        afCallbacks = {},
        spellColors = copy(options.spellColors or {}),
        visibleResult = true,
        assistResult = true,
        attackResult = false,
        inCombat = false,
    }
    local UF = {}
    local AF = {
        isRetail = options.isRetail ~= false,
    }
    local F = {}

    function AF.Copy(value)
        assertTrue(type(value) == "table",
            "mock AF.Copy requires a table")
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

    function AF.RegisterCallback(event, callback)
        harness.afCallbacks[event] =
            harness.afCallbacks[event] or {}
        harness.afCallbacks[event][callback] = true
    end

    function AF.Fire(event, ...)
        record(harness, "af.fire", event, ...)
        local callbacks = harness.afCallbacks[event]
        if not callbacks then return end

        local snapshot = {}
        for callback in pairs(callbacks) do
            snapshot[#snapshot + 1] = callback
        end
        for _, callback in ipairs(snapshot) do
            callback(event, ...)
        end
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

    local function newController(parent, name, seedContainer)
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
            seedContainer = seedContainer,
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
            self.presentationApplied =
                spec.enabled and spec.shown or false
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
            if not enabled then
                self.presentationApplied = false
            end
            record(harness, "controller.enabled", self, enabled)
        end
        function controller:SetShown(shown)
            if self.shown == shown then return end
            self.shown = shown
            self.frame.shown = shown
            self.presentationApplied = shown and self.enabled or false
            if self.spec then self.spec.shown = shown end
            record(harness, "controller.shown", self, shown)
        end
        function controller:IsPresentationApplied()
            return self.presentationApplied == true
                and self.enabled == true
                and self.shown == true
        end
        function controller:SetVariant(variant)
            if self.variant == variant then return end
            self.variant = variant
            if self.deferVariantApplication then
                self.presentationApplied = false
            end
            if self.spec then self.spec.variant = variant end
            record(harness, "controller.variant", self, variant)
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
        record(
            harness,
            "uf.controller",
            controller,
            parent,
            name,
            seedContainer
        )
        return controller
    end

    function UF.CreateNativeAuraContainerController(parent, name)
        return newController(parent, name)
    end

    function UF.CreateNativeGroupAuraContainerController(
        parent,
        name,
        seedContainer
    )
        return newController(parent, name, seedContainer)
    end

    function UF.CreateNativeAuraPartitionController(parent, name)
        local controller = newController(parent, name)
        controller.partitionController = true
        record(harness, "uf.partition-controller", controller, parent, name)
        return controller
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
                            spellColorFamilies =
                                spellColorConstructionKey(
                                    config.spellColors
                                ),
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
                spellIDFilterRequiresPublicAssist =
                    config.spellIDFilterRequiresPublicAssist == true,
                spellIDFilterRequiresPublicNonAssist =
                    config.spellIDFilterRequiresPublicNonAssist == true,
            },
            partition = nil,
            migrationReady = not empty,
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
                spellColors = copy(config.spellColors),
                holder = copy(descriptor.completeSpec.holder),
                groups = {
                    {
                        key = "group",
                        filterString = config.tag,
                    },
                },
                slots = {},
            }

            if partitioned then
                local main = {
                    completeSpec = copy(descriptor.completeSpec),
                    tuningSpec = copy(descriptor.tuningSpec),
                    constructionKey = copy(descriptor.constructionKey),
                }
                main.completeSpec.groups[1].filterString =
                    config.tag .. "|PLAYER"
                main.tuningSpec.groups[1].filterString =
                    config.tag .. "|PLAYER"

                local complementStyle =
                    config.complementStyle or "complement-a"
                local complement = {
                    completeSpec = copy(descriptor.completeSpec),
                    tuningSpec = copy(descriptor.tuningSpec),
                    constructionKey = copy(descriptor.constructionKey),
                }
                complement.completeSpec.holder = {
                    width = config.complementWidth or 16,
                    height = config.complementHeight or 8,
                }
                complement.tuningSpec.holder =
                    copy(complement.completeSpec.holder)
                complement.completeSpec.groups[1].filterString =
                    config.tag .. "|!PLAYER"
                complement.tuningSpec.groups[1].filterString =
                    config.tag .. "|!PLAYER"
                complement.completeSpec.groups[1].buttonStyle.style =
                    complementStyle
                complement.constructionKey.groups[1]
                    .buttonStyle.style = complementStyle

                local includeComplement =
                    config.partitionMainOnly ~= true
                descriptor.partition = {
                    filter = "notCastByMe",
                    selector = {
                        kind = "unitCanAttack",
                        actorUnit = "player",
                        secretFallback = "friendly",
                    },
                    holder = {
                        width = config.width or 20,
                        height = config.compositeHeight or 18,
                    },
                    hostile = {
                        main = main,
                        complement = includeComplement
                            and complement
                            or nil,
                        attachment = includeComplement and {
                            point = "BOTTOMLEFT",
                            relativePoint = "TOPLEFT",
                            x = 0,
                            y = -1,
                        } or nil,
                    },
                }
            end
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

    local A = {}
    function A.GetNativeSpellColorMap()
        return copy(harness.spellColors)
    end

    local BFI = {
        funcs = F,
        modules = {
            Auras = A,
            UnitFrames = UF,
        },
    }

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
        GetBuildInfo = function()
            return "test", "test", "test", harness.interfaceVersion
        end,
        UnitCanAssist = function(sourceUnit, unit)
            assertEqual(sourceUnit, "player", "assist source unit")
            record(harness, "wow.assist", sourceUnit, unit)
            return harness.assistResult
        end,
        UnitCanAttack = function(sourceUnit, unit)
            assertEqual(sourceUnit, "player", "attack source unit")
            record(harness, "wow.attack", sourceUnit, unit)
            return harness.attackResult
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
        CreateFrame = function(objectType, name, parent)
            assertTrue(
                #harness.unavailableFrames
                    < harness.unavailableFrameBudget,
                "unexpected unavailable aura frame allocation"
            )
            assertEqual(objectType, "Frame", "unavailable frame type")
            local frame = {
                name = name,
                objectType = objectType,
                parent = parent,
                shown = true,
            }
            function frame:GetName()
                return self.name
            end
            function frame:GetObjectType()
                return self.objectType
            end
            function frame:SetAllPoints(relativeTo)
                self.allPoints = relativeTo
                record(harness, "unavailable.all-points", self, relativeTo)
            end
            function frame:Hide()
                self.shown = false
                record(harness, "unavailable.hide", self)
            end
            harness.unavailableFrames[#harness.unavailableFrames + 1] = frame
            record(harness, "unavailable.create", frame, parent, name)
            return frame
        end,
        InCombatLockdown = function()
            return harness.inCombat
        end,
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        setmetatable = setmetatable,
        tostring = tostring,
        tonumber = tonumber,
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

local function createGroupRuntime(harness, root)
    local seedContainer = {}
    root._nativeAuraContainers = {
        buffs = seedContainer,
    }
    local runtime = harness.UF.CreateGroupNativeAuras(
        root,
        root.name .. "_Auras",
        "HELPFUL",
        "buffs"
    )
    assertTrue(runtime, "native group runtime was not created")
    runtime.enabled = true
    root.indicators.buffs = runtime
    return runtime, harness.controllers[#harness.controllers], seedContainer
end

local function createPartitionRuntime(harness, root)
    local runtime = harness.UF.CreateNativePartitionedAuraIndicator(
        root,
        root.name .. "_Auras",
        "HARMFUL",
        true
    )
    assertTrue(runtime, "partition runtime was not created")
    runtime.enabled = true
    root.indicators.debuffs = runtime
    return runtime, harness.controllers[#harness.controllers]
end

local function testDormancyAndFallback()
    local harness = makeHarness({unavailableFrameBudget = 1})
    assertEqual(#harness.controllers, 0, "dormant controller count")
    assertEqual(#harness.legacyFrames, 0, "dormant legacy count")
    assertEqual(#harness.compiles, 0, "dormant compile count")
    assertProviderObserverOnly(harness, "dormant provider observer")
    assertEqual(countEvents(harness, "af.pixel-add"), 0, "dormant pixel updater")

    local unavailable = makeHarness({
        backend = false,
        unavailableFrameBudget = 1,
    })
    assertEqual(next(unavailable.registered), nil,
        "12.1 unavailable provider observer")
    local unavailableStats = unavailable.UF.GetNativeAuraRuntimeStats()
    assertEqual(unavailableStats.nativeBackendAvailable, false,
        "12.1 unavailable provider backend state")
    assertEqual(unavailableStats.providerSwitchEvents, 0,
        "12.1 unavailable provider switch count")
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
    assertEqual(fallback._nativeAuraUnavailable, true,
        "12.1 unavailable indicator marker")
    assertEqual(fallback.root, root, "12.1 unavailable root")
    assertEqual(fallback:GetObjectType(), "Frame",
        "12.1 unavailable anchor object type")
    assertEqual(fallback.allPoints, root,
        "12.1 unavailable anchor shell")
    assertEqual(fallback.shown, false,
        "12.1 unavailable shell visibility")
    assertEqual(fallback:GetName(), "Fallback_Auras",
        "12.1 unavailable name")
    assertEqual(fallback.auraFilter, "HELPFUL",
        "12.1 unavailable filter")
    assertEqual(#unavailable.legacyFrames, 0,
        "12.1 unavailable legacy count")
    assertEqual(#unavailable.unavailableFrames, 1,
        "12.1 unavailable frame count")
    fallback.enabled = true
    fallback:LoadConfig(validConfig())
    assertEqual(fallback.enabled, false,
        "12.1 unavailable config state")
    fallback:Enable()
    assertEqual(fallback.enabled, false,
        "12.1 unavailable enable state")
    local unavailableState = fallback:GetNativeAuraState()
    assertEqual(unavailableState.state, "UNAVAILABLE",
        "12.1 unavailable runtime state")
    assertEqual(unavailableState.active, false,
        "12.1 unavailable active state")
    assertEqual(unavailableState.built, false,
        "12.1 unavailable built state")
    assertEqual(unavailableState.nativeBackendAvailable, false,
        "12.1 unavailable backend state")

    local nativePartitionDirect, nativePartitionError =
        unavailable.UF.CreateNativePartitionedAuraIndicator(
            root,
            "Fallback_PartitionAuras",
            "HARMFUL",
            true
        )
    assertEqual(nativePartitionDirect, nil,
        "unavailable direct partition runtime")
    assertEqual(nativePartitionError,
        "NATIVE_AURA_BACKEND_UNAVAILABLE",
        "unavailable direct partition error")
    local nativePartitionFallback =
        unavailable.UF.CreateNativePartitionedAuras(
            root,
            "Fallback_PartitionAuras",
            "HARMFUL",
            true
        )
    assertEqual(nativePartitionFallback._nativeAuraUnavailable, true,
        "12.1 native partition unavailable marker")
    assertEqual(nativePartitionFallback:GetObjectType(), "Frame",
        "12.1 native partition anchor object type")
    assertEqual(#unavailable.legacyFrames, 0,
        "12.1 native partition legacy count")

    local partitionFallback = harness.UF.CreateNativeAuras(
        root,
        "Partition_Auras",
        "HARMFUL",
        true
    )
    assertEqual(partitionFallback._nativeAuraUnavailable, true,
        "12.1 partition unavailable marker")
    assertEqual(#harness.legacyFrames, 0,
        "12.1 partition legacy count")
    assertEqual(#harness.unavailableFrames, 1,
        "12.1 partition unavailable frame count")
    assertEqual(#harness.controllers, 0, "partition controller count")

    local legacy = makeHarness({
        backend = false,
        interfaceVersion = 120007,
    })
    local legacyFallback = legacy.UF.CreateNativeAuras(
        root,
        "Legacy_Auras",
        "HELPFUL",
        false
    )
    assertEqual(legacyFallback, legacy.legacyFrames[1],
        "12.0.7 legacy fallback")
    assertEqual(legacyFallback.parent, root, "12.0.7 fallback parent")
    assertEqual(legacyFallback.name, "Legacy_Auras", "12.0.7 fallback name")
    assertEqual(legacyFallback.auraFilter, "HELPFUL",
        "12.0.7 fallback filter")
    assertEqual(legacyFallback.hasSubFrame, false,
        "12.0.7 fallback subframe")
    local legacyPartitionFallback = legacy.UF.CreateNativePartitionedAuras(
        root,
        "Legacy_PartitionAuras",
        "HARMFUL",
        true
    )
    assertEqual(legacyPartitionFallback, legacy.legacyFrames[2],
        "12.0.7 partition legacy fallback")
    assertEqual(legacyPartitionFallback.hasSubFrame, true,
        "12.0.7 partition fallback subframe")

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

local function testOptInRelationPartitionRuntime()
    local harness = makeHarness()
    local root = newRoot("RelationPartition", "party1")
    local runtime, controller = createPartitionRuntime(harness, root)

    runtime:LoadConfig(validConfig({
        testState = "partition",
        tag = "partition-a",
        spellIDFilterRequiresPublicAssist = true,
    }))
    runtime:Enable()

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "READY", "opt-in partition state")
    assertEqual(state.partitionVariant, "friendly",
        "friendly initial partition variant")
    assertTrue(controller.partitionController,
        "partition controller selection")
    assertEqual(controller.variant, "friendly",
        "friendly controller variant")
    assertTrue(type(controller.spec.friendly) == "table",
        "friendly prebuilt spec")
    assertTrue(type(controller.spec.main) == "table",
        "hostile-main prebuilt spec")
    assertTrue(type(controller.spec.complement) == "table",
        "hostile-complement prebuilt spec")
    assertEqual(controller.spec.holder.height, 18,
        "composite holder height")
    assertTrue(harness.registered.UNIT_FACTION ~= nil,
        "partition relationship watcher")

    harness:ClearEvents()
    harness.attackResult = true
    controller.deferVariantApplication = true
    harness:SetCombat(true)
    harness:Fire("UNIT_FACTION", "party1")
    harness:RunTimers(0.05)
    assertEqual(controller.variant, "hostile",
        "hostile combat relation variant")
    assertEqual(runtime:GetNativeAuraState().partitionVariant, "hostile",
        "hostile state variant")
    assertEqual(countEvents(harness, "controller.variant"), 1,
        "hostile visibility switch count")
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "deferred hostile refresh count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "hostile relation rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "hostile relation tuning count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "hostile relation placement count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "hostile relation retarget count")

    controller.deferVariantApplication = nil
    controller.presentationApplied = true
    harness:ClearEvents()
    runtime:Update()
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "applied hostile refresh count")

    harness:ClearEvents()
    harness.assistResult = {secret = true}
    harness:Fire("UNIT_FACTION", "party1")
    harness:RunTimers(0.05)
    assertEqual(controller.shown, false,
        "secret spell-gated partition visibility")
    assertEqual(controller.variant, "hostile",
        "hidden partition does not drive a replacement variant")
    assertEqual(runtime:GetNativeAuraState().partitionVariant, nil,
        "hidden partition state suppresses variant")
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "secret spell-gated partition refresh count")

    harness:ClearEvents()
    harness.assistResult = true
    harness:Fire("UNIT_FACTION", "party1")
    harness:RunTimers(0.05)
    assertEqual(controller.shown, true,
        "public spell-gated partition recovery")
    assertEqual(controller.variant, "hostile",
        "recovered partition relation")
    assertEqual(countEvents(harness, "controller.refresh"), 1,
        "recovered partition refresh count")

    harness:ClearEvents()
    harness.attackResult = {secret = true}
    harness:Fire("UNIT_FACTION", "player")
    harness:RunTimers(0.05)
    assertEqual(controller.variant, "friendly",
        "secret relationship friendly fallback")
    assertTrue(countEvents(harness, "secret.check") > 0,
        "secret relationship guard")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "secret relationship rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "secret relationship tuning count")

    harness:SetCombat(false)
    harness.attackResult = false
    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        testState = "partition",
        tag = "partition-tuned",
    }))
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "partition tuning reuse count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "partition tuning rebuild count")
    assertEqual(controller.tuning.friendly.tag, "partition-tuned",
        "friendly partition tuning payload")
    assertEqual(
        controller.tuning.main.groups[1].filterString,
        "partition-tuned|PLAYER",
        "hostile-main tuning payload"
    )
    assertEqual(
        controller.tuning.complement.groups[1].filterString,
        "partition-tuned|!PLAYER",
        "hostile-complement tuning payload"
    )

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        testState = "partition",
        tag = "partition-tuned",
        complementStyle = "complement-b",
    }))
    harness:RunTimers(0.15)
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "complement construction live rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "complement construction tuning count")
    assertEqual(
        runtime:GetNativeAuraState().reloadRequired,
        true,
        "complement construction reload boundary"
    )

    local unpartitionedHarness = makeHarness()
    local unpartitionedRoot = newRoot("OptionalPartition", "target")
    local unpartitionedRuntime, unpartitionedController =
        createPartitionRuntime(unpartitionedHarness, unpartitionedRoot)
    unpartitionedRuntime:LoadConfig(validConfig())
    unpartitionedRuntime:Enable()
    assertEqual(unpartitionedRuntime:GetNativeAuraState().state, "READY",
        "partition-capable unpartitioned state")
    assertTrue(type(unpartitionedController.spec.friendly) == "table",
        "unpartitioned friendly spec")
    assertEqual(unpartitionedController.spec.main, nil,
        "unpartitioned hostile-main spec")
    assertEqual(unpartitionedController.spec.complement, nil,
        "unpartitioned hostile-complement spec")

    unpartitionedHarness:ClearEvents()
    unpartitionedRuntime:LoadConfig(validConfig({
        testState = "partition",
    }))
    unpartitionedHarness:RunTimers(0.15)
    assertEqual(
        countEvents(unpartitionedHarness, "controller.rebuild"),
        0,
        "unpartitioned-to-partitioned live rebuild count"
    )
    assertEqual(
        countEvents(unpartitionedHarness, "controller.tuning"),
        0,
        "unpartitioned-to-partitioned tuning count"
    )
    assertEqual(
        unpartitionedRuntime:GetNativeAuraState().reloadRequired,
        true,
        "unpartitioned-to-partitioned reload boundary"
    )

    unpartitionedHarness:ClearEvents()
    unpartitionedRuntime:LoadConfig(validConfig())
    unpartitionedHarness:RunTimers(0.15)
    assertEqual(
        countEvents(unpartitionedHarness, "controller.rebuild"),
        0,
        "partitioned-to-unpartitioned live rebuild count"
    )
    assertEqual(
        countEvents(unpartitionedHarness, "controller.tuning"),
        1,
        "restored unpartitioned tuning count"
    )
    assertEqual(
        unpartitionedRuntime:GetNativeAuraState().reloadRequired,
        false,
        "restored unpartitioned topology clears reload"
    )

    local mainOnlyHarness = makeHarness()
    local mainOnlyRoot = newRoot("MainOnlyPartition", "target")
    local mainOnlyRuntime, mainOnlyController =
        createPartitionRuntime(mainOnlyHarness, mainOnlyRoot)
    mainOnlyRuntime:LoadConfig(validConfig({
        testState = "partition",
        partitionMainOnly = true,
    }))
    mainOnlyRuntime:Enable()
    assertEqual(mainOnlyRuntime:GetNativeAuraState().state, "READY",
        "main-only partition state")
    assertTrue(type(mainOnlyController.spec.main) == "table",
        "main-only hostile-main spec")
    assertEqual(mainOnlyController.spec.complement, nil,
        "main-only hostile-complement spec")
    assertEqual(mainOnlyController.spec.attachment, nil,
        "main-only partition attachment")

    mainOnlyRuntime:SetUnit(nil)
    assertEqual(mainOnlyRuntime:GetNativeAuraState().state,
        "WAITING_FOR_UNIT",
        "partition waiting-unit state")
    assertEqual(
        mainOnlyRuntime:GetNativeAuraState().partitionVariant,
        nil,
        "partition waiting-unit variant"
    )
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
    assertEqual(state.providerMode, "live", "initial provider mode")
    assertEqual(state.providerBuildDeferred, false,
        "initial provider deferral")
    assertProviderObserverOnly(harness, "hidden provider observer")

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
    assertProviderObserverOnly(harness, "ungated watcher cleanup")

    root.enabled = false
    runtime:Disable()
    assertEqual(controller.enabled, false, "module-disabled native state")

    root.enabled = true
    runtime:Enable()
    assertEqual(controller.enabled, true, "re-enabled native state")
    assertEqual(controller.shown, true, "re-enabled holder state")
end

local function testPendingPresentationSuppressesStableRefresh()
    local harness = makeHarness()
    local root = newRoot("PendingPresentation", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()

    harness:ClearEvents()
    controller.presentationApplied = false
    runtime:Update()
    assertEqual(
        countEvents(harness, "controller.refresh"),
        0,
        "pending presentation suppresses refresh"
    )

    controller.presentationApplied = true
    runtime:Update()
    assertEqual(
        countEvents(harness, "controller.refresh"),
        1,
        "applied presentation permits refresh"
    )
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
    local reloadState = runtime:GetNativeAuraState()
    assertEqual(reloadState.reloadRequired, true,
        "construction change reload state")
    assertEqual(reloadState.pending, false,
        "construction change pending state")
    assertEqual(reloadState.diagnostics[1], "latest-rebuild",
        "latest reload-required descriptor")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "post-build construction rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "post-build construction placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "post-build construction tuning count")
    assertEqual(controller.enabled, false,
        "reload-required native state")
    assertEqual(controller.shown, false,
        "reload-required holder state")
end

local function testPostBuildConstructionRequiresReload()
    local harness = makeHarness()
    local root = newRoot("ReloadRequired", "target")
    local runtime, controller = createRuntime(harness, root)

    local candidate = validConfig({
        style = "style-b",
        tag = "preflight",
    })
    local originalCandidate = copy(candidate)
    assertEqual(runtime:RequiresReloadForConfig(candidate), false,
        "unbuilt preflight reload state")
    assertTrue(deepEqual(candidate, originalCandidate),
        "unbuilt preflight mutated config")

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:ClearEvents()

    assertEqual(runtime:RequiresReloadForConfig(validConfig()), false,
        "same-construction preflight")
    assertEqual(runtime:RequiresReloadForConfig(candidate), true,
        "changed-construction preflight")
    assertEqual(runtime:RequiresReloadForConfig(validConfig({
        testState = "empty",
    })), false, "empty preflight reload state")
    assertEqual(runtime:RequiresReloadForConfig(validConfig({
        testState = "partition",
        style = "style-b",
    })), false, "deferred preflight reload state")
    assertEqual(runtime:GetNativeAuraState().reloadRequired, false,
        "preflight runtime mutation")
    assertEqual(runtime:GetNativeAuraState().diagnostics[1], "initial",
        "preflight descriptor mutation")
    assertTrue(deepEqual(candidate, originalCandidate),
        "built preflight mutated config")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "preflight rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "preflight placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "preflight tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "preflight retarget count")

    runtime.enabled = false
    root.enabled = false
    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        enabled = false,
        style = "style-b",
        tag = "disabled-profile-change",
    }))

    local state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, true,
        "disabled profile reload state")
    assertEqual(state.pending, false,
        "disabled profile pending state")
    assertEqual(controller.enabled, false,
        "disabled profile native state")
    assertEqual(controller.shown, false,
        "disabled profile holder state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "disabled profile rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "disabled profile placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "disabled profile tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "disabled profile retarget count")

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        enabled = false,
        style = "style-c",
        tag = "latest-disabled-profile-change",
    }))
    root.effectiveUnit = "focus"
    runtime:Update()
    runtime:Enable()

    state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, true,
        "repeated construction reload state")
    assertEqual(state.unit, "focus",
        "reload-required desired unit")
    assertEqual(state.diagnostics[1], "latest-disabled-profile-change",
        "repeated construction latest descriptor")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "repeated construction rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "repeated construction placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "repeated construction tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "repeated construction retarget count")

    runtime.enabled = true
    root.enabled = true
    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        tag = "exact-reversion",
        offset = 3,
    }))
    harness:RunTimers(0.15)

    state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, false,
        "exact reversion reload state")
    assertEqual(state.pending, false,
        "exact reversion pending state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "exact reversion rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 1,
        "exact reversion placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "exact reversion tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "exact reversion retarget count")
    assertEqual(controller.unit, "focus",
        "exact reversion retarget unit")
    assertEqual(controller.enabled, true,
        "exact reversion native state")
    assertEqual(controller.shown, true,
        "exact reversion holder state")
end

local function testCombatConstructionReloadLatestWins()
    local harness = makeHarness()
    local root = newRoot("CombatReload", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:SetCombat(true)
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "obsolete-combat-topology",
    }))
    local state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, true,
        "combat construction reload state")
    assertEqual(state.pending, true,
        "combat reload quiesce pending state")
    assertEqual(controller.shown, false,
        "combat reload immediate holder state")
    assertEqual(controller.enabled, true,
        "combat reload deferred native state")
    assertEqual(countEvents(harness, "controller.enabled"), 0,
        "combat reload native mutation count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "combat reload rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "combat reload placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "combat reload tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "combat reload retarget count")

    runtime:LoadConfig(validConfig({
        tag = "latest-same-topology",
    }))
    state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, false,
        "combat exact reversion reload state")
    assertEqual(state.pending, true,
        "combat exact reversion pending state")
    assertTrue(harness.registered.PLAYER_REGEN_ENABLED,
        "combat exact reversion regen registration")

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)
    harness:RunTimers(0.15)
    state = runtime:GetNativeAuraState()
    assertEqual(state.pending, false,
        "combat exact reversion settled state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "combat exact reversion rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "combat exact reversion tuning count")
    assertEqual(controller.enabled, true,
        "combat exact reversion native state")
    assertEqual(controller.shown, true,
        "combat exact reversion holder state")

    harness:SetCombat(true)
    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "stale-combat-reload",
    }))
    runtime:LoadConfig(validConfig({
        style = "style-c",
        tag = "latest-combat-reload",
    }))
    root.effectiveUnit = "focus"
    runtime:Update()

    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "latest combat reload rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "latest combat reload placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "latest combat reload tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "latest combat reload retarget count")
    assertEqual(countEvents(harness, "controller.enabled"), 0,
        "latest combat reload enabled count")

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)
    state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, true,
        "latest combat reload state")
    assertEqual(state.pending, false,
        "latest combat reload settled state")
    assertEqual(state.unit, "focus",
        "latest combat reload desired unit")
    assertEqual(state.diagnostics[1], "latest-combat-reload",
        "latest combat reload descriptor")
    assertEqual(controller.enabled, false,
        "latest combat reload native state")
    assertEqual(controller.shown, false,
        "latest combat reload holder state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "settled combat reload rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "settled combat reload placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "settled combat reload tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "settled combat reload retarget count")
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
    assertEqual(runtime:GetNativeAuraState().reloadRequired, false,
        "combat superseded reload state")
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
    harness:ClearEvents()
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

local function testWatcherRoutesRelationshipSignals()
    local harness = makeHarness()
    local focusRoot = newRoot("VehicleFocus", "focus")
    local targetRoot = newRoot("VehicleTarget", "target")
    focusRoot.effectiveUnit = "focuspet"
    targetRoot.effectiveUnit = "targetpet"
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

    harness:Fire("PLAYER_TARGET_CHANGED")
    harness:RunTimers(0.05)
    assertEqual(
        focusController.refreshCount,
        focusRefreshes,
        "derived target-event focus suppression"
    )
    assertEqual(
        targetController.refreshCount,
        targetRefreshes + 1,
        "derived target-event target refresh"
    )

    harness:Fire("PLAYER_FOCUS_CHANGED")
    harness:RunTimers(0.05)
    assertEqual(
        focusController.refreshCount,
        focusRefreshes + 1,
        "derived focus-event focus refresh"
    )
    assertEqual(
        targetController.refreshCount,
        targetRefreshes + 1,
        "derived focus-event target suppression"
    )

    harness:Fire("UNIT_FACTION", "targetpet")
    harness:RunTimers(0.05)
    assertEqual(
        focusController.refreshCount,
        focusRefreshes + 1,
        "effective-faction focus suppression"
    )
    assertEqual(
        targetController.refreshCount,
        targetRefreshes + 2,
        "effective-faction target refresh"
    )

    harness:Fire("UNIT_FACTION", "target")
    harness:RunTimers(0.05)
    assertEqual(
        focusController.refreshCount,
        focusRefreshes + 1,
        "root-faction focus suppression"
    )
    assertEqual(
        targetController.refreshCount,
        targetRefreshes + 3,
        "root-faction target refresh"
    )

    harness:Fire("UNIT_FACTION", "player")
    harness:RunTimers(0.05)
    assertEqual(
        focusController.refreshCount,
        focusRefreshes + 2,
        "player-faction focus relationship refresh"
    )
    assertEqual(
        targetController.refreshCount,
        targetRefreshes + 4,
        "player-faction target relationship refresh"
    )

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
    local emptyState = runtime:GetNativeAuraState()
    assertEqual(emptyState.state, "EMPTY", "empty state")
    assertEqual(emptyState.reloadRequired, false,
        "empty reload state")
    assertEqual(emptyState.pending, false,
        "empty pending state")
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
    assertEqual(partitionState.reloadRequired, false,
        "partition reload state")
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
    assertEqual(errorState.reloadRequired, false,
        "compile error reload state")
    assertEqual(errorState.pending, false,
        "compile error pending state")
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
    assertProviderObserverOnly(
        harness,
        "invalid state watcher cleanup before commit"
    )
    harness:RunTimers(0.15)

    runtime:Disable()
    harness:ClearEvents()
    harness:RunTimers(2)
    harness:RunTimers(6)
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "inactive settled refresh count")
end

local function testSpellIDReactionGatesAndProviderBypass()
    do
        local harness = makeHarness()
        local root = newRoot("HelpfulSpellIDGate", "party1")
        local runtime, controller = createRuntime(harness, root)

        harness:ClearEvents()
        harness.assistResult = true
        runtime:LoadConfig(validConfig({
            spellIDFilterRequiresPublicAssist = true,
        }))
        runtime:Enable()

        local visibility = runtime:GetNativeAuraState().visibility
        assertEqual(
            visibility.spellIDFilterRequiresPublicAssist,
            true,
            "helpful spell-ID assist requirement"
        )
        assertEqual(
            visibility.spellIDFilterRequiresPublicNonAssist,
            false,
            "helpful spell-ID non-assist requirement"
        )
        assertEqual(controller.shown, true,
            "helpful public assist gate")
        assertEqual(countEvents(harness, "uf.register"), 9,
            "helpful spell-ID watcher registrations")

        harness.assistResult = false
        harness:Fire("UNIT_FACTION", "party1")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "helpful public non-assist rejection")

        harness.assistResult = {secret = true}
        harness:ClearEvents()
        harness:Fire("UNIT_FACTION", "party1")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "helpful secret reaction fail-closed")
        assertTrue(countEvents(harness, "secret.check") >= 1,
            "helpful secret reaction check")

        harness.assistResult = nil
        harness:Fire("UNIT_FACTION", "party1")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "helpful indeterminate reaction fail-closed")

        harness.assistResult = true
        harness:Fire("UNIT_FACTION", "party1")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, true,
            "helpful public assist recovery")

        harness.assistResult = {secret = true}
        harness:Fire("UNIT_FACTION", "party1")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "helpful provider setup gate")

        harness:ClearEvents()
        harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)
        assertEqual(controller.shown, true,
            "test provider reaction-gate bypass")
        assertEqual(countEvents(harness, "wow.assist"), 0,
            "test provider reaction-gate call count")
        assertEqual(countEvents(harness, "uf.unregister"), 9,
            "test provider spell-ID watcher cleanup")
        assertProviderObserverOnly(
            harness,
            "test provider spell-ID watcher state"
        )
    end

    do
        local harness = makeHarness()
        local root = newRoot("HarmfulSpellIDGate", "party2")
        local runtime = harness.UF.CreateNativeAuraIndicator(
            root,
            "HarmfulSpellIDGate_Auras",
            "HARMFUL",
            false
        )
        assertTrue(runtime, "harmful native runtime was not created")
        runtime.enabled = true
        root.indicators.debuffs = runtime

        harness:ClearEvents()
        harness.assistResult = false
        runtime:LoadConfig(validConfig({
            spellIDFilterRequiresPublicNonAssist = true,
        }))
        runtime:Enable()

        local visibility = runtime:GetNativeAuraState().visibility
        assertEqual(
            visibility.spellIDFilterRequiresPublicAssist,
            false,
            "harmful spell-ID assist requirement"
        )
        assertEqual(
            visibility.spellIDFilterRequiresPublicNonAssist,
            true,
            "harmful spell-ID non-assist requirement"
        )
        local controller = harness.controllers[#harness.controllers]
        assertEqual(controller.shown, true,
            "harmful public non-assist gate")
        assertEqual(countEvents(harness, "uf.register"), 9,
            "harmful spell-ID watcher registrations")

        harness.assistResult = true
        harness:Fire("UNIT_FACTION", "party2")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "harmful public assist rejection")

        harness.assistResult = {secret = true}
        harness:ClearEvents()
        harness:Fire("UNIT_FACTION", "party2")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "harmful secret reaction fail-closed")
        assertTrue(countEvents(harness, "secret.check") >= 1,
            "harmful secret reaction check")

        harness.assistResult = nil
        harness:Fire("UNIT_FACTION", "party2")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, false,
            "harmful indeterminate reaction fail-closed")

        harness.assistResult = false
        harness:Fire("UNIT_FACTION", "party2")
        harness:RunTimers(0.05)
        assertEqual(controller.shown, true,
            "harmful public non-assist recovery")

        harness:ClearEvents()
        runtime:Disable()
        assertEqual(countEvents(harness, "uf.unregister"), 9,
            "harmful spell-ID watcher cleanup")
        assertProviderObserverOnly(
            harness,
            "harmful spell-ID watcher state"
        )
    end
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
    assertEqual(runtime:GetNativeAuraState().reloadRequired, true,
        "config-mode construction reload state")
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
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "deferred config-mode rebuild count")
    assertEqual(runtime:GetNativeAuraState().reloadRequired, true,
        "config-mode exit reload state")
    assertEqual(controller.enabled, false, "post-preview native state")
    assertEqual(controller.shown, false, "post-preview hidden holder")

    runtime:Enable()
    assertEqual(controller.shown, false,
        "reload-required post-preview holder")

    harness:ClearEvents()
    runtime:LoadConfig(validConfig({
        tag = "preview-reverted",
    }))
    harness:RunTimers(0.15)
    assertEqual(runtime:GetNativeAuraState().reloadRequired, false,
        "config-mode exact reversion state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "config-mode exact reversion rebuild count")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "config-mode exact reversion tuning count")
    assertEqual(controller.enabled, true,
        "config-mode exact reversion native state")
    assertEqual(controller.shown, true,
        "config-mode exact reversion holder")
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
    assertEqual(runtime:GetNativeAuraState().reloadRequired, true,
        "pre-destroy reload state")
    runtime:Destroy()
    assertEqual(runtime:GetNativeAuraState().state, "DESTROYED",
        "destroyed state")
    assertEqual(controller.destroyed, true, "controller destroy state")
    assertProviderObserverOnly(harness, "destroy watcher cleanup")
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
    assertEqual(destroyedState.reloadRequired, false,
        "destroyed reload state")
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

local function testGlobalSpellColorRefresh()
    local harness = makeHarness({
        spellColors = {
            [101] = {0.1, 0.8, 0.2, 1},
        },
    })
    local firstRoot = newRoot("FirstColors", "target")
    local secondRoot = newRoot("SecondColors", "focus")
    local firstRuntime = createRuntime(harness, firstRoot)
    local secondRuntime = createRuntime(harness, secondRoot)

    firstRuntime:LoadConfig(validConfig())
    secondRuntime:LoadConfig(validConfig())
    assertEqual(#harness.compiles, 2, "initial color compile count")
    assertTrue(
        harness.compiles[1].config.spellColors[101] ~= nil,
        "global colors were not injected into first compile"
    )
    assertTrue(
        harness.compiles[2].config.spellColors[101] ~= nil,
        "global colors were not injected into hidden runtime compile"
    )

    harness.spellColors[202] = {0.1, 0.8, 0.2, 1}
    harness:ClearEvents()
    harness.AF.Fire("BFI_UpdateConfig", "auras", "colors")
    assertEqual(#harness.compiles, 4,
        "same-family edit did not refresh every runtime")
    assertEqual(
        countEvents(harness, "af.fire"),
        1,
        "same-family edit requested a reload"
    )
    assertEqual(firstRuntime:GetNativeAuraState().reloadRequired, false,
        "same-family first runtime reload state")
    assertEqual(secondRuntime:GetNativeAuraState().reloadRequired, false,
        "same-family hidden runtime reload state")
    harness:RunTimers(0.15)

    harness.spellColors[303] = {0.9, 0.2, 0.4, 1}
    harness:ClearEvents()
    harness.AF.Fire("BFI_UpdateConfig", "auras", "colors")
    assertEqual(#harness.compiles, 6,
        "new-family edit did not refresh every runtime")
    assertEqual(
        countEvents(harness, "af.fire"),
        2,
        "new-family edit did not emit one coalesced reload event"
    )
    local reloadEvent = lastEvent(harness, "af.fire")
    assertEqual(
        reloadEvent.args[1],
        "BFI_NativeAuraReloadRequired",
        "new-family reload event"
    )
    assertEqual(firstRuntime:GetNativeAuraState().reloadRequired, true,
        "new-family first runtime reload state")
    assertEqual(secondRuntime:GetNativeAuraState().reloadRequired, true,
        "new-family hidden runtime reload state")

    local compileCount = #harness.compiles
    harness.AF.Fire("BFI_UpdateConfig", "colors", "casts")
    assertEqual(#harness.compiles, compileCount,
        "unrelated common colors refreshed aura runtimes")
end

local function testLegacyPathDoesNotReadAuraIdentityForColors()
    local file = assert(io.open(
        "Modules/UnitFrames/Indicators/Auras.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()

    assertTrue(
        source:find("GetAuraColor", 1, true) == nil,
        "legacy aura still requests a per-spell color"
    )
    assertTrue(
        source:find("auraData.spellId", 1, true) == nil,
        "legacy aura still indexes a live aura spell ID for color"
    )
    assertTrue(
        source:find("AF.GetColorRGB%(\"BFI\"%)") == nil,
        "legacy preview pretends to know a per-spell color"
    )
end

local function testGroupRuntimeSelectionAndFallback()
    local unavailable = makeHarness({
        backend = false,
        unavailableFrameBudget = 1,
    })
    local fallbackRoot = setmetatable({
        name = "GroupFallback",
        unit = "party1",
        indicators = {},
        enabled = true,
        shown = true,
    }, {
        __index = function(_, key)
            if key == "_nativeAuraContainers" then
                error("12.0.7 accessed native group containers", 2)
            end
        end,
    })
    function fallbackRoot:GetName()
        return self.name
    end
    function fallbackRoot:IsVisible()
        return self.shown == true
    end

    local fallback = unavailable.UF.CreateGroupNativeAuras(
        fallbackRoot,
        "GroupFallback_Buffs",
        "HELPFUL",
        "buffs"
    )
    assertEqual(fallback._nativeAuraUnavailable, true,
        "group 12.1 unavailable marker")
    assertEqual(#unavailable.controllers, 0,
        "group 12.1 native controller count")
    assertEqual(#unavailable.legacyFrames, 0,
        "group 12.1 legacy count")
    assertEqual(#unavailable.unavailableFrames, 1,
        "group 12.1 unavailable frame count")
    assertEqual(fallback.root, fallbackRoot,
        "group unavailable root")
    assertEqual(fallback:GetName(), "GroupFallback_Buffs",
        "group unavailable name")
    assertEqual(fallback.auraFilter, "HELPFUL",
        "group unavailable filter")

    local legacy = makeHarness({
        backend = false,
        interfaceVersion = 120007,
    })
    local legacyFallback = legacy.UF.CreateGroupNativeAuras(
        fallbackRoot,
        "GroupLegacy_Buffs",
        "HELPFUL",
        "buffs"
    )
    assertEqual(legacyFallback, legacy.legacyFrames[1],
        "group 12.0.7 legacy fallback")
    assertEqual(legacyFallback.parent, fallbackRoot,
        "group 12.0.7 fallback parent")
    assertEqual(legacyFallback.name, "GroupLegacy_Buffs",
        "group 12.0.7 fallback name")
    assertEqual(legacyFallback.auraFilter, "HELPFUL",
        "group 12.0.7 fallback filter")
    assertEqual(legacyFallback.hasSubFrame, nil,
        "group 12.0.7 fallback subframe")

    local harness = makeHarness()
    local root = newRoot("GroupNative", "party1")
    local seed = {}
    root._nativeAuraContainers = {
        buffs = seed,
    }
    local runtime = harness.UF.CreateGroupNativeAuras(
        root,
        "GroupNative_Buffs",
        "HELPFUL",
        "buffs"
    )
    assertTrue(runtime, "group native runtime")
    assertEqual(#harness.controllers, 1, "group native controller count")
    assertEqual(harness.controllers[1].seedContainer, seed,
        "group runtime seed forwarding")
    assertEqual(runtime.root, root, "group runtime root")
    assertEqual(runtime.auraFilter, "HELPFUL", "group runtime filter")
    assertEqual(runtime._hasSubFrame, false, "group runtime subframe")

    local missingRoot = newRoot("MissingGroupSeed", "party1")
    local accepted, message = pcall(
        harness.UF.CreateGroupNativeAuras,
        missingRoot,
        "MissingGroupSeed_Buffs",
        "HELPFUL",
        "buffs"
    )
    assertEqual(accepted, false, "missing group seed acceptance")
    assertTrue(
        tostring(message):find("seed is missing", 1, true) ~= nil,
        "missing group seed assertion"
    )
end

local function testGroupSeedsPrebuildBeforeCombat()
    local harness = makeHarness()
    local root = newRoot("GroupBootstrap", nil)
    local runtime, controller = createGroupRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    assertEqual(runtime:GetNativeAuraState().state, "READY",
        "group prebuild ready state")
    assertEqual(runtime:GetNativeAuraState().unit, "none",
        "group prebuild inert unit")
    assertEqual(controller.built, true, "group prebuild initial build")
    assertEqual(controller.spec.unit, "none",
        "group prebuild controller unit")
    assertEqual(controller.shown, false,
        "group prebuild inactive visibility")

    harness:SetCombat(true)
    harness:ClearEvents()
    root.unit = "party5"
    root.effectiveUnit = "party5"
    runtime:Enable()

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "READY", "group bootstrap ready state")
    assertEqual(state.unit, "party5", "group bootstrap unit")
    assertEqual(state.built, true, "group bootstrap built state")
    assertEqual(controller.built, true, "group bootstrap controller build")
    assertEqual(controller.spec.unit, "party5",
        "group assignment controller unit")
    assertEqual(controller.shown, true, "group bootstrap visibility")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "group assignment combat rebuild count")
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "group assignment combat retarget count")
    assertProviderObserverOnly(
        harness,
        "group bootstrap regen registration"
    )
end

local function testGroupUnitRetargetsBeforePendingCombatConfig()
    local harness = makeHarness()
    local root = newRoot("GroupPendingConfig", "party1")
    local runtime, controller = createGroupRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:SetCombat(true)
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        tag = "pending-combat-config",
    }))
    root.unit = "party4"
    root.effectiveUnit = "party4"
    runtime:Update()

    assertEqual(controller.unit, "party4",
        "pending config live group unit")
    assertEqual(controller.shown, false,
        "pending config group visibility")
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "pending config live retarget count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "pending config combat tuning count")
    assertTrue(harness.registered.PLAYER_REGEN_ENABLED,
        "pending config regen registration")
    assertEqual(runtime:GetNativeAuraState().pending, true,
        "pending config runtime state")

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "pending config duplicate regen retarget")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "pending config regen tuning count")
    assertEqual(controller.shown, true,
        "pending config regen visibility")
end

local function testSecretUnitTokenFailsClosed()
    local harness = makeHarness()
    local root = newRoot("SecretUnit", "party1")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:ClearEvents()

    root.effectiveUnit = {
        secret = true,
    }
    runtime:Update()

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "WAITING_FOR_UNIT", "secret unit state")
    assertEqual(state.unit, nil, "secret unit storage")
    assertEqual(controller.shown, false, "secret unit holder visibility")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "secret unit native retarget")
    assertTrue(countEvents(harness, "secret.check") > 0,
        "secret unit predicate")

    root.effectiveUnit = "party4"
    harness:ClearEvents()
    runtime:Update()
    state = runtime:GetNativeAuraState()
    assertEqual(state.state, "READY", "clean unit recovery state")
    assertEqual(state.unit, "party4", "clean unit recovery token")
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "clean unit recovery retarget")
    assertEqual(controller.shown, true, "clean unit recovery visibility")

    harness:ClearEvents()
    runtime:SetUnit({
        secret = true,
    })
    state = runtime:GetNativeAuraState()
    assertEqual(state.state, "WAITING_FOR_UNIT",
        "direct secret unit state")
    assertEqual(state.unit, nil, "direct secret unit storage")
    assertEqual(controller.shown, false,
        "direct secret unit holder visibility")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "direct secret native retarget")
end

local function testSecretUnitDefersExactTopologyRecovery()
    local harness = makeHarness()
    local root = newRoot("SecretConfigRecovery", "target")
    local runtime, controller = createRuntime(harness, root)

    runtime:LoadConfig(validConfig())
    runtime:Enable()
    harness:ClearEvents()

    runtime:LoadConfig(validConfig({
        style = "style-b",
        tag = "reload-before-secret",
    }))
    assertEqual(runtime:GetNativeAuraState().reloadRequired, true,
        "pre-secret structural reload state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "pre-secret structural rebuild count")

    root.effectiveUnit = {
        secret = true,
    }
    runtime:Update()
    local waitingState = runtime:GetNativeAuraState()
    assertEqual(waitingState.state, "WAITING_FOR_UNIT",
        "structural secret waiting state")
    assertEqual(waitingState.reloadRequired, true,
        "structural secret reload state")

    runtime:LoadConfig(validConfig({
        tag = "latest-secret-tuning",
        offset = 7,
        width = 24,
    }))
    waitingState = runtime:GetNativeAuraState()
    assertEqual(waitingState.state, "WAITING_FOR_UNIT",
        "exact reversion waiting state")
    assertEqual(waitingState.reloadRequired, false,
        "exact reversion clears reload state")
    assertEqual(waitingState.pending, true,
        "exact reversion deferred config state")

    harness:RunTimers(0.15)
    waitingState = runtime:GetNativeAuraState()
    assertEqual(waitingState.pending, true,
        "waiting config remains deferred")
    assertEqual(#harness.timers, 0,
        "waiting config dormant timer count")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "waiting config rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 0,
        "waiting config placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "waiting config tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 0,
        "waiting config retarget count")

    root.effectiveUnit = "focus"
    harness:ClearEvents()
    runtime:Update()

    local recoveredState = runtime:GetNativeAuraState()
    assertEqual(recoveredState.state, "READY",
        "clean config recovery state")
    assertEqual(recoveredState.pending, false,
        "clean config recovery pending state")
    assertEqual(recoveredState.reloadRequired, false,
        "clean config recovery reload state")
    assertEqual(countEvents(harness, "controller.rebuild"), 0,
        "clean config recovery rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 1,
        "clean config recovery placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 1,
        "clean config recovery tuning count")
    assertEqual(countEvents(harness, "controller.unit"), 1,
        "clean config recovery retarget count")
    assertEqual(controller.tuning.tag, "latest-secret-tuning",
        "clean config recovery latest tuning")
    assertEqual(controller.frame.position[3], 7,
        "clean config recovery latest placement")
    assertEqual(controller.unit, "focus",
        "clean config recovery retarget unit")
    assertEqual(controller.enabled, true,
        "clean config recovery native state")
    assertEqual(controller.shown, true,
        "clean config recovery holder state")
    assertEqual(#harness.timers, 0,
        "clean config recovery timer count")
end

local function testNativeProviderVisibilityAndRuntimeCounters()
    local harness = makeHarness()
    local root = newRoot("ProviderVisibility", "player")
    local runtime, controller = createRuntime(harness, root)

    harness.assistResult = false
    runtime:LoadConfig(validConfig({
        requiresVisible = true,
        requiresAssist = true,
    }))
    runtime:Enable()
    assertEqual(controller.shown, false,
        "live provider assist-gated holder")

    local initialStats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(initialStats.nativeBackendAvailable, true,
        "provider backend availability")
    assertEqual(initialStats.runtimesCreated, 1,
        "provider runtime creation count")
    assertEqual(initialStats.runtimesDestroyed, 0,
        "provider runtime destruction count")
    assertEqual(initialStats.liveRuntimes, 1,
        "provider live runtime count")
    assertEqual(initialStats.providerSwitchEvents, 0,
        "initial provider switch count")
    assertEqual(initialStats.testProviderActive, false,
        "initial provider state")

    harness:SetCombat(true)
    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)

    local state = runtime:GetNativeAuraState()
    assertEqual(state.providerMode, "test", "test provider mode")
    assertEqual(state.providerBuildDeferred, false,
        "built test-provider deferral")
    assertEqual(state.pending, false, "built test-provider pending state")
    assertEqual(controller.shown, true,
        "test provider visibility-gate bypass")
    assertEqual(countEvents(harness, "controller.shown"), 1,
        "test provider holder resync count")
    assertEqual(countEvents(harness, "wow.visible"), 0,
        "test provider visible-gate call count")
    assertEqual(countEvents(harness, "wow.assist"), 0,
        "test provider assist-gate call count")
    assertEqual(countEvents(harness, "uf.unregister"), 9,
        "test provider gate-watcher cleanup")
    assertProviderObserverOnly(
        harness,
        "test provider gate-watcher state"
    )
    assertNoProviderDrivenControllerWork(
        harness,
        "test provider entry"
    )
    assertEqual(harness.registered.PLAYER_REGEN_ENABLED, nil,
        "test provider combat queue")
    assertEqual(#harness.controllers, 1,
        "test provider controller growth")

    harness:ClearEvents()
    runtime:Update()
    assertEqual(countEvents(harness, "controller.refresh"), 0,
        "test provider stable-unit refresh count")
    assertEqual(countEvents(harness, "wow.visible"), 0,
        "test provider stable-unit visible-gate count")
    assertEqual(countEvents(harness, "wow.assist"), 0,
        "test provider stable-unit assist-gate count")

    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)

    state = runtime:GetNativeAuraState()
    assertEqual(state.providerMode, "live", "restored provider mode")
    assertEqual(state.pending, false, "restored provider pending state")
    assertEqual(controller.shown, false,
        "restored live assist gate")
    assertEqual(countEvents(harness, "controller.shown"), 1,
        "restored provider holder resync count")
    assertEqual(countEvents(harness, "wow.visible"), 1,
        "restored visible-gate call count")
    assertEqual(countEvents(harness, "wow.assist"), 1,
        "restored assist-gate call count")
    assertEqual(countEvents(harness, "uf.register"), 9,
        "restored provider gate-watcher registration")
    assertNoProviderDrivenControllerWork(
        harness,
        "live provider restoration"
    )
    assertEqual(harness.registered.PLAYER_REGEN_ENABLED, nil,
        "live provider combat queue")
    assertEqual(#harness.controllers, 1,
        "live provider controller growth")
    assertEqual(#harness.timers, 0,
        "live provider timer count")

    local stats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(stats.providerSwitchEvents, 2,
        "provider switch event count")
    assertEqual(stats.testProviderActivations, 1,
        "test provider activation count")
    assertEqual(stats.liveProviderRestorations, 1,
        "live provider restoration count")
    assertEqual(stats.lateBuildDeferrals, 0,
        "built provider late-build count")
    assertEqual(stats.lateBuildResumptions, 0,
        "built provider resume count")
    assertEqual(stats.testProviderActive, false,
        "restored provider stats state")

    stats.runtimesCreated = 99
    assertEqual(
        harness.UF.GetNativeAuraRuntimeStats().runtimesCreated,
        1,
        "provider stats snapshot isolation"
    )

    harness:SetCombat(false)
    runtime:Destroy()
    stats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(stats.runtimesDestroyed, 1,
        "provider runtime destroyed count")
    assertEqual(stats.liveRuntimes, 0,
        "provider runtime release count")
    assertProviderObserverOnly(harness, "post-destroy provider observer")
end

local function testNativeProviderTerminalConfigCancelsLateBuild()
    local cases = {
        {
            testState = "empty",
            expectedState = "EMPTY",
        },
        {
            testState = "partition",
            expectedState = "PARTITION_DEFERRED",
        },
        {
            testState = "error",
            expectedState = "ERROR",
        },
    }

    for _, case in ipairs(cases) do
        local harness = makeHarness()
        harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)

        local root = newRoot(
            "ProviderTerminal_" .. case.testState,
            "target"
        )
        local runtime, controller = createRuntime(harness, root)
        runtime:LoadConfig(validConfig())
        assertEqual(
            runtime:GetNativeAuraState().providerBuildDeferred,
            true,
            case.testState .. " initial provider deferral"
        )

        runtime:LoadConfig(validConfig({
            testState = case.testState,
            tag = case.testState,
        }))
        local state = runtime:GetNativeAuraState()
        assertEqual(
            state.state,
            case.expectedState,
            case.testState .. " terminal state"
        )
        assertEqual(
            state.providerBuildDeferred,
            false,
            case.testState .. " terminal provider deferral"
        )
        assertEqual(
            controller.built,
            nil,
            case.testState .. " terminal controller build"
        )

        local timerCount = #harness.timers
        harness:ClearEvents()
        harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)

        state = runtime:GetNativeAuraState()
        assertEqual(
            state.providerMode,
            "live",
            case.testState .. " restored provider mode"
        )
        assertEqual(
            state.providerBuildDeferred,
            false,
            case.testState .. " restored provider deferral"
        )
        assertEqual(
            state.built,
            false,
            case.testState .. " restored build state"
        )
        assertEqual(
            #harness.timers,
            timerCount,
            case.testState .. " restored timer count"
        )
        assertNoProviderDrivenControllerWork(
            harness,
            case.testState .. " provider restoration"
        )

        local stats = harness.UF.GetNativeAuraRuntimeStats()
        assertEqual(
            stats.lateBuildDeferrals,
            1,
            case.testState .. " late-build count"
        )
        assertEqual(
            stats.lateBuildResumptions,
            0,
            case.testState .. " resume count"
        )

        harness:RunTimers(0.15)
        assertEqual(
            runtime:GetNativeAuraState().pending,
            false,
            case.testState .. " settled pending state"
        )
        assertEqual(
            controller.built,
            nil,
            case.testState .. " settled controller build"
        )
    end
end

local function testNativeProviderSecretUnitCancelsLateBuild()
    local harness = makeHarness()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)

    local root = newRoot("ProviderSecretUnit", "target")
    local runtime, controller = createRuntime(harness, root)
    runtime:LoadConfig(validConfig())
    assertEqual(
        runtime:GetNativeAuraState().providerBuildDeferred,
        true,
        "secret-unit setup provider deferral"
    )

    root.effectiveUnit = {
        secret = true,
    }
    runtime:LoadConfig(validConfig({
        tag = "secret-unit",
    }))

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "WAITING_FOR_UNIT",
        "secret-unit provider waiting state")
    assertEqual(state.providerBuildDeferred, false,
        "secret-unit provider deferral cancellation")
    assertEqual(state.built, false,
        "secret-unit provider build state")
    assertEqual(controller.built, nil,
        "secret-unit controller build")

    harness:RunTimers(0.15)
    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)

    state = runtime:GetNativeAuraState()
    assertEqual(state.providerMode, "live",
        "secret-unit restored provider mode")
    assertEqual(state.state, "WAITING_FOR_UNIT",
        "secret-unit restored waiting state")
    assertEqual(state.providerBuildDeferred, false,
        "secret-unit restored provider deferral")
    assertEqual(state.built, false,
        "secret-unit restored build state")
    assertEqual(controller.built, nil,
        "secret-unit restored controller build")
    assertNoProviderDrivenControllerWork(
        harness,
        "secret-unit provider restoration"
    )

    local stats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(stats.lateBuildDeferrals, 1,
        "secret-unit late-build deferral count")
    assertEqual(stats.lateBuildResumptions, 0,
        "secret-unit false-resumption count")
end

local function testNativeProviderLateBuildDefersThroughCombat()
    local harness = makeHarness()

    -- The observer is registered before any BFI runtime or native container,
    -- so entering Edit Mode first still protects the initial build.
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)

    local root = newRoot("ProviderLateBuild", "target")
    local runtime, controller = createRuntime(harness, root)
    harness:ClearEvents()
    runtime:LoadConfig(validConfig())
    runtime:Enable()
    runtime:Update()

    local state = runtime:GetNativeAuraState()
    assertEqual(state.state, "READY", "deferred provider ready state")
    assertEqual(state.providerMode, "test",
        "deferred provider test state")
    assertEqual(state.providerBuildDeferred, true,
        "deferred provider build state")
    assertEqual(state.built, false, "deferred provider built state")
    assertEqual(state.pending, true, "deferred provider pending state")
    assertEqual(controller.built, nil,
        "deferred provider controller build")
    assertNoProviderDrivenControllerWork(
        harness,
        "test provider deferred build",
        true
    )
    assertEqual(countEvents(harness, "uf.compile"), 1,
        "test provider deferred compile count")

    local stats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(stats.runtimesCreated, 1,
        "deferred provider runtime count")
    assertEqual(stats.providerSwitchEvents, 1,
        "deferred provider switch count")
    assertEqual(stats.testProviderActivations, 1,
        "deferred provider activation count")
    assertEqual(stats.lateBuildDeferrals, 1,
        "deferred provider build count")
    assertEqual(stats.lateBuildResumptions, 0,
        "pre-restoration build resume count")

    harness:SetCombat(true)
    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)

    state = runtime:GetNativeAuraState()
    assertEqual(state.providerMode, "live",
        "combat restoration provider mode")
    assertEqual(state.providerBuildDeferred, false,
        "combat restoration provider deferral")
    assertEqual(state.built, false,
        "combat restoration built state")
    assertEqual(state.pending, true,
        "combat restoration pending state")
    assertEqual(controller.built, nil,
        "combat restoration controller build")
    assertNoProviderDrivenControllerWork(
        harness,
        "combat provider restoration"
    )
    assertTrue(harness.registered.PLAYER_REGEN_ENABLED,
        "combat provider restoration queue")

    stats = harness.UF.GetNativeAuraRuntimeStats()
    assertEqual(stats.providerSwitchEvents, 2,
        "combat restoration switch count")
    assertEqual(stats.liveProviderRestorations, 1,
        "combat restoration event count")
    assertEqual(stats.lateBuildResumptions, 1,
        "combat restoration resume count")
    assertEqual(stats.testProviderActive, false,
        "combat restoration provider stats state")

    harness:SetCombat(false)
    harness:Fire("PLAYER_REGEN_ENABLED")
    harness:RunTimers(0)

    state = runtime:GetNativeAuraState()
    assertEqual(state.built, true, "regen provider built state")
    assertEqual(state.pending, false, "regen provider pending state")
    assertEqual(controller.built, true,
        "regen provider controller build")
    assertEqual(countEvents(harness, "controller.rebuild"), 1,
        "regen provider rebuild count")
    assertEqual(countEvents(harness, "controller.holder-config"), 1,
        "regen provider placement count")
    assertEqual(countEvents(harness, "controller.tuning"), 0,
        "regen provider tuning count")
end

local function testNativeProviderRespectsConfigModePreview()
    local harness = makeHarness()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)

    local root = newRoot("ProviderConfigMode", "focus")
    local runtime, controller = createRuntime(harness, root)
    runtime:LoadConfig(validConfig())

    root.inConfigMode = true
    runtime:EnableConfigMode()
    assertEqual(controller.built, nil,
        "config-mode provider native build")
    assertEqual(#harness.legacyFrames, 1,
        "config-mode provider preview count")
    assertEqual(harness.legacyFrames[1].configMode, true,
        "config-mode provider preview state")

    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)

    local state = runtime:GetNativeAuraState()
    assertEqual(state.providerMode, "live",
        "config-mode restored provider mode")
    assertEqual(state.providerBuildDeferred, false,
        "config-mode restored provider deferral")
    assertEqual(state.configMode, true,
        "provider switch config-mode state")
    assertEqual(state.built, false,
        "provider switch config-mode build")
    assertEqual(state.pending, true,
        "provider switch config-mode pending state")
    assertEqual(controller.built, nil,
        "provider switch config-mode controller build")
    assertEqual(harness.legacyFrames[1].configMode, true,
        "provider switch preview continuity")
    assertEqual(countEvents(harness, "legacy.load"), 0,
        "provider switch preview reload count")
    assertEqual(countEvents(harness, "legacy.config-enable"), 0,
        "provider switch preview enable count")
    assertEqual(countEvents(harness, "legacy.config-disable"), 0,
        "provider switch preview disable count")
    assertEqual(countEvents(harness, "legacy.disable"), 0,
        "provider switch preview hide count")
    assertNoProviderDrivenControllerWork(
        harness,
        "config-mode provider restoration"
    )

    root.inConfigMode = nil
    runtime:DisableConfigMode()
    runtime:Enable()
    state = runtime:GetNativeAuraState()
    assertEqual(state.built, true,
        "post-config provider built state")
    assertEqual(state.pending, false,
        "post-config provider pending state")
    assertEqual(controller.built, true,
        "post-config provider controller build")
    assertEqual(harness.legacyFrames[1].configMode, false,
        "post-config provider preview state")

    runtime:Disable()
    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)
    state = runtime:GetNativeAuraState()
    assertEqual(state.active, false,
        "disabled test-provider active state")
    assertEqual(controller.shown, false,
        "disabled test-provider holder state")
    assertNoProviderDrivenControllerWork(
        harness,
        "disabled test-provider entry"
    )

    harness:Fire("AURA_DATA_PROVIDER_SWITCH", true)
    runtime:Enable()
    runtime:LoadConfig(validConfig({
        style = "reload-style",
    }))
    assertEqual(runtime:GetNativeAuraState().reloadRequired, true,
        "provider reload-required setup")

    harness:ClearEvents()
    harness:Fire("AURA_DATA_PROVIDER_SWITCH", false)
    state = runtime:GetNativeAuraState()
    assertEqual(state.reloadRequired, true,
        "test-provider reload-required state")
    assertEqual(controller.shown, false,
        "test-provider reload-required holder state")
    assertNoProviderDrivenControllerWork(
        harness,
        "reload-required test-provider entry"
    )
end

testDormancyAndFallback()
testOptInRelationPartitionRuntime()
testLifecycleAndUnitRefresh()
testPendingPresentationSuppressesStableRefresh()
testDebounceAndConstructionReuse()
testPostBuildConstructionRequiresReload()
testCombatConstructionReloadLatestWins()
testControllerLedgerCommitUsesLatestConfig()
testRuntimeHasNoHolderVisibilityReads()
testSharedCombatCommitQueue()
testCombatConfigSupersession()
testUngatedFocusWatcher()
testWatcherRoutesUnitSignals()
testWatcherRoutesRelationshipSignals()
testQuiesceAndRecovery()
testSecretSafeWholeHolderGates()
testSpellIDReactionGatesAndProviderBypass()
testConfigModeNeverRetargetsPlayer()
testDisabledConfigModePreviewCannotEscape()
testWaitingUnitAndTerminalDestroy()
testPolymorphicGlobalRefreshSource()
testGlobalSpellColorRefresh()
testLegacyPathDoesNotReadAuraIdentityForColors()
testGroupRuntimeSelectionAndFallback()
testGroupSeedsPrebuildBeforeCombat()
testGroupUnitRetargetsBeforePendingCombatConfig()
testSecretUnitTokenFailsClosed()
testSecretUnitDefersExactTopologyRecovery()
testNativeProviderVisibilityAndRuntimeCounters()
testNativeProviderTerminalConfigCancelsLateBuild()
testNativeProviderSecretUnitCancelsLateBuild()
testNativeProviderLateBuildDefersThroughCombat()
testNativeProviderRespectsConfigModePreview()

print("unit_frame_aura_runtime_test.lua: ok")
