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

local function merge(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            merge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local function copyMerged(...)
    local result = {}
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        for key, value in pairs(source) do
            result[key] = copy(value)
        end
    end
    return result
end

local function findIndicator(indicators, name)
    for _, indicator in ipairs(indicators) do
        if type(indicator) == "table" and indicator[2] == name then
            return indicator
        end
    end
end

local function makeIntegrationHarness()
    local harness = {
        callbacks = {},
        configMode = {},
        createIndicatorCalls = {},
        disableCalls = {},
        events = {},
        frames = {},
        legacyConstructions = {},
        nativeConstructions = {},
        setupCalls = {},
    }
    local UF = {
        config = {
            general = {
                enabled = true,
            },
            pet = {
                general = {
                    enabled = true,
                },
                indicators = {},
            },
        },
    }
    local AF = {
        UIParent = {
            name = "UIParent",
        },
    }

    local function record(name, ...)
        harness.events[#harness.events + 1] = {
            name = name,
            args = {...},
        }
    end

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.CreateMover(frame, label, unitLabel)
        harness.mover = {
            frame = frame,
            label = label,
            unitLabel = unitLabel,
        }
    end

    function AF.RegisterCallback(event, callback)
        if event == "BFI_UpdateModule" then
            harness.callbacks[event] = callback
        end
    end

    function AF.UpperFirst(value)
        return value:sub(1, 1):upper() .. value:sub(2)
    end

    function UF.AddToConfigMode(group, frame)
        harness.configMode[#harness.configMode + 1] = {
            group = group,
            frame = frame,
        }
    end

    local function CreatePreviewRect(frame)
        frame.previewCreated = true
    end

    local function SetupUnitFrame(frame, config, indicators, skip)
        harness.setupCalls[#harness.setupCalls + 1] = {
            frame = frame,
            config = config,
            indicators = indicators,
            skip = skip,
        }
        frame.enabled = true
        record("setup", frame, skip)
    end

    local function DisableIndicators(frame)
        harness.disableCalls[#harness.disableCalls + 1] = frame
        frame.enabled = false
        for _, indicator in pairs(frame.indicators) do
            if UF.configModeEnabled
                and indicator.DisableConfigMode
            then
                indicator:DisableConfigMode()
            end
            indicator:Disable()
        end
        record("indicators.disable", frame)
    end

    local function newIndicator(parent, name, auraFilter, builder)
        local indicator = {
            auraFilter = auraFilter,
            builder = builder,
            name = name,
            root = parent,
        }

        function indicator:Disable()
            self.enabled = false
        end

        function indicator:EnableConfigMode()
            self.configMode = true
            self.enableConfigModeCount =
                (self.enableConfigModeCount or 0) + 1
            record("indicator.enable-config", self)
        end

        function indicator:DisableConfigMode()
            self.configMode = false
            self.disableConfigModeCount =
                (self.disableConfigModeCount or 0) + 1
            record("indicator.disable-config", self)
        end

        return indicator
    end

    local function CreateGenericIndicator(parent, name)
        return newIndicator(parent, name, nil, "generic")
    end

    function UF.CreateAuras(parent, name, auraFilter)
        local indicator =
            newIndicator(parent, name, auraFilter, "auras")
        harness.legacyConstructions[
            #harness.legacyConstructions + 1
        ] = indicator
        record("legacy.create", indicator, parent, auraFilter)
        return indicator
    end

    function UF.CreateNativeAuras(parent, name, auraFilter)
        local indicator =
            newIndicator(parent, name, auraFilter, "nativeAuras")
        harness.nativeConstructions[
            #harness.nativeConstructions + 1
        ] = indicator
        record("native.create", indicator, parent, auraFilter)
        return indicator
    end

    for _, builder in ipairs({
        "CreateHealthBar",
        "CreatePowerBar",
        "CreateNameText",
        "CreateHealthText",
        "CreatePowerText",
        "CreatePortrait",
        "CreateCastBar",
        "CreateCombatIcon",
        "CreateLevelText",
        "CreateTargetCounter",
        "CreateRaidIcon",
        "CreateTargetHighlight",
        "CreateMouseoverHighlight",
        "CreateThreatGlow",
    }) do
        UF[builder] = CreateGenericIndicator
    end

    local function CreateFrame(frameType, name, parent, template)
        local frame = {
            attributes = {},
            frameType = frameType,
            indicators = {},
            name = name,
            parent = parent,
            shown = false,
            template = template,
        }

        function frame:GetName()
            return self.name
        end

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
            if key == "unit" then
                self.unit = value
                self.effectiveUnit = value
            end
        end

        function frame:SetAllPoints()
        end

        function frame:SetFrameStrata()
        end

        function frame:IsVisible()
            return self.shown
        end

        function frame:Hide()
            self.shown = false
            self.hideCount = (self.hideCount or 0) + 1
        end

        function frame:Show()
            self.shown = true
            self.showCount = (self.showCount or 0) + 1
            record("frame.show", self)
        end

        if name == "BFIUnitFrameParent" then
            harness.commonParent = frame
        else
            harness.frames[#harness.frames + 1] = frame
        end
        return frame
    end

    local function RegisterUnitWatch(frame)
        frame.unitWatchRegistered = true
        frame.registerUnitWatchCount =
            (frame.registerUnitWatchCount or 0) + 1
        record("watch.register", frame)
    end

    local function UnregisterUnitWatch(frame)
        frame.unitWatchRegistered = false
        frame.unregisterUnitWatchCount =
            (frame.unregisterUnitWatchCount or 0) + 1
        record("watch.unregister", frame)
    end

    local function UnitWatchRegistered(frame)
        record("watch.query", frame)
        return frame.unitWatchRegistered == true
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        CreateFrame = CreateFrame,
        PET = "Pet",
        RegisterAttributeDriver = function()
        end,
        RegisterUnitWatch = RegisterUnitWatch,
        UnitWatchRegistered = UnitWatchRegistered,
        UnregisterUnitWatch = UnregisterUnitWatch,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        tostring = tostring,
        type = type,
        unpack = unpack,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected Pet integration global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local commonChunk, commonLoadError =
        loadfile("Modules/UnitFrames/Common.lua")
    assertTrue(commonChunk, commonLoadError)
    setfenv(commonChunk, environment)
    commonChunk("BFInfinite", BFI)

    local CreateIndicators = UF.CreateIndicators
    function UF.CreateIndicators(frame, indicatorDescriptors)
        harness.createIndicatorCalls[
            #harness.createIndicatorCalls + 1
        ] = {
            frame = frame,
            indicators = indicatorDescriptors,
        }
        return CreateIndicators(frame, indicatorDescriptors)
    end
    UF.CreatePreviewRect = CreatePreviewRect
    UF.SetupUnitFrame = SetupUnitFrame
    UF.DisableIndicators = DisableIndicators

    local chunk, loadError =
        loadfile("Modules/UnitFrames/Units/Pet.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.BFI = BFI
    harness.UF = UF

    function harness:ClearEvents()
        self.events = {}
    end

    function harness:CountEvents(name)
        local count = 0
        for _, event in ipairs(self.events) do
            if event.name == name then
                count = count + 1
            end
        end
        return count
    end

    function harness:EventIndex(name, occurrence)
        occurrence = occurrence or 1
        local count = 0
        for index, event in ipairs(self.events) do
            if event.name == name then
                count = count + 1
                if count == occurrence then
                    return index
                end
            end
        end
    end

    return harness
end

local function makeDisabledRuntimeHarness()
    local harness = {
        compiles = {},
        controllers = {},
    }
    local UF = {}
    local AF = {}
    local BFI = {
        funcs = {
            isValueNonSecret = function()
                return true
            end,
        },
        modules = {
            UnitFrames = UF,
        },
    }

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.Copy(value)
        return copy(value)
    end

    function AF.LoadWidgetPosition()
    end

    function AF.RegisterCallback()
    end

    function AF.SetFrameLevel()
    end

    function UF.HasNativeAuraContainerBackend()
        return true
    end

    function UF.CompileNativeAuraSpec(unit, auraFilter, config)
        harness.compiles[#harness.compiles + 1] = {
            unit = unit,
            auraFilter = auraFilter,
            config = copy(config),
        }
        return {
            completeSpec = {
                enabled = config.enabled,
                groups = {},
                holder = {
                    width = 1,
                    height = 1,
                },
                shown = false,
                slots = {},
                unit = unit,
            },
            constructionKey = {
                groups = {},
                slots = {},
            },
            degradations = {},
            diagnostics = {},
            empty = false,
            migrationReady = true,
            metrics = {},
            placement = {
                anchorTo = "root",
                frameLevel = 1,
                position = {"CENTER", "CENTER", 0, 0},
            },
            tuningSpec = {
                groups = {},
                holder = {
                    width = 1,
                    height = 1,
                },
                slots = {},
            },
            visibility = {
                requiresAssist = false,
                requiresVisible = false,
            },
        }
    end

    function UF.CreateNativeAuraContainerController(parent, name)
        local frame = {
            name = name,
            parent = parent,
            shown = false,
        }

        function frame:GetName()
            return self.name
        end

        function frame:GetObjectType()
            return "Frame"
        end

        function frame:IsShown()
            return self.shown
        end

        local controller = {
            frame = frame,
        }

        function controller:ApplyHolderConfig(callback)
            callback(self.frame)
        end

        function controller:ApplyTuning()
        end

        function controller:Destroy()
        end

        function controller:GetFrame()
            return self.frame
        end

        function controller:Rebuild(spec)
            self.spec = copy(spec)
            self.rebuildCount = (self.rebuildCount or 0) + 1
        end

        function controller:IsPresentationApplied()
            return self.shown == true and self.enabled == true
        end

        function controller:Refresh()
        end

        function controller:SetEnabled()
        end

        function controller:SetShown(shown)
            self.frame.shown = shown
        end

        function controller:SetUnit()
        end

        harness.controllers[#harness.controllers + 1] = controller
        return controller
    end

    function UF.CreateAuras()
        error("disabled Pet runtime unexpectedly used legacy auras", 2)
    end

    function UF.LoadIndicatorPosition()
    end

    function UF:RegisterEvent()
    end

    function UF:UnregisterEvent()
    end

    local environment = {
        _G = false,
        AbstractFramework = AF,
        C_Timer = {
            After = function(_, callback)
                callback()
            end,
        },
        CreateFrame = function()
            error("disabled Pet runtime created an unavailable frame", 2)
        end,
        GetBuildInfo = function()
            return nil, nil, nil, 120100
        end,
        InCombatLockdown = function()
            return false
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
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected disabled Pet runtime global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/AuraRuntime.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local root = {
        effectiveUnit = "pet",
        enabled = true,
        inConfigMode = false,
        unit = "pet",
    }
    local buffs = UF.CreateNativeAuraIndicator(
        root,
        "BFI_Pet_Buffs",
        "HELPFUL"
    )
    local debuffs = UF.CreateNativeAuraIndicator(
        root,
        "BFI_Pet_Debuffs",
        "HARMFUL"
    )

    buffs.enabled = false
    debuffs.enabled = false
    buffs:LoadConfig({
        enabled = false,
    })
    debuffs:LoadConfig({
        enabled = false,
    })

    harness.buffs = buffs
    harness.debuffs = debuffs
    return harness
end

local function makePresetCompiler()
    local UF = {}
    local AF = {}

    function AF.Copy(...)
        return copyMerged(...)
    end

    function AF.GetColorTable(_, alpha)
        return {1, 1, 1, alpha or 1}
    end

    function AF.Merge(target, source)
        return merge(target, source)
    end

    function AF.RegisterCallback()
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        funcs = {},
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        AnchorUtil = {
            FlowLayoutAxis = {
                Horizontal = 101,
                Vertical = 102,
            },
            FlowDirection = {
                Left = 201,
                Right = 202,
                Up = 203,
                Down = 204,
            },
        },
        AuraContainerSortMethod = {
            Default = 301,
        },
        AuraContainerSortDirection = {
            Normal = 401,
        },
        AuraUtil = {
            AuraFilters = {
                Important = "IMPORTANT",
                Dispellable = "DISPELLABLE",
            },
        },
        CustomAuraContainerAuraProcessingPolicy = {
            None = 501,
        },
        GetCVar = function() return nil end,
        assert = assert,
        error = error,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        rawget = rawget,
        select = select,
        string = string,
        table = table,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        wipe = function(value)
            for key in pairs(value) do
                value[key] = nil
            end
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected preset compiler global: "
                    .. tostring(key),
                2
            )
        end,
    })

    for _, path in ipairs({
        "Utils.lua",
        "Modules/UnitFrames/Presets.lua",
        "Modules/UnitFrames/AuraPolicy.lua",
        "Modules/UnitFrames/AuraSpec.lua",
    }) do
        local chunk, loadError = loadfile(path)
        assertTrue(chunk, loadError)
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end

    return UF
end

local function assertMetrics(actual, expected, message)
    for key, value in pairs(expected) do
        assertEqual(actual[key], value, message .. " " .. key)
    end
end

local function assertFilters(descriptor, expected, message)
    assertEqual(#descriptor.completeSpec.groups, #expected,
        message .. " count")
    for index, filterString in ipairs(expected) do
        assertEqual(
            descriptor.completeSpec.groups[index].filterString,
            filterString,
            message .. " group " .. index
        )
    end
end

local function assertDiagnostics(actual, expected, message)
    assertEqual(#actual, #expected, message .. " count")
    for index, value in ipairs(expected) do
        assertEqual(actual[index], value,
            message .. " " .. index)
    end
end

local function assertDegradations(actual, expected, message)
    for key, value in pairs(expected) do
        assertEqual(actual[key], value, message .. " " .. key)
    end
end

local function testPetActivationAndConstructionOrder()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "Pet update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.legacyConstructions, 0,
        "module-load legacy aura construction")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "pet")
    update(nil, "unitFrames", "target")
    assertEqual(#harness.frames, 0,
        "unrelated update frame allocation")

    update(nil, "unitFrames", "pet", true)
    assertEqual(#harness.frames, 1, "Pet frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "Pet indicator creation count")
    assertEqual(#harness.legacyConstructions, 0,
        "Pet legacy aura prebuild count")
    assertEqual(#harness.nativeConstructions, 2,
        "Pet native controller prebuild count")
    assertEqual(#harness.setupCalls, 1, "Pet setup count")
    assertEqual(harness.setupCalls[1].skip, false,
        "first Pet setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Pet initial unit-watch registration")
    assertTrue(
        harness:EventIndex("native.create", 1)
            < harness:EventIndex("setup"),
        "Pet first native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("native.create", 2)
            < harness:EventIndex("setup"),
        "Pet second native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "Pet unit watch registered before setup"
    )

    local frame = harness.frames[1]
    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffs = findIndicator(descriptors, "buffs")
    local debuffs = findIndicator(descriptors, "debuffs")

    assertEqual(frame.name, "BFI_Pet", "Pet frame name")
    assertEqual(frame.frameType, "Button", "Pet frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "Pet frame template")
    assertEqual(frame.parent, harness.UF.Parent, "Pet frame parent")
    assertEqual(frame.attributes.unit, "pet", "Pet secure unit")
    assertEqual(frame.unit, "pet", "Pet runtime unit")
    assertEqual(frame._updateOnUnitPetChanged, "player",
        "Pet owner-event opt-in")
    assertEqual(frame.unitWatchRegistered, true,
        "Pet unit-watch state")
    assertTrue(frame.previewCreated, "Pet preview rectangle")
    assertEqual(harness.configMode[1].group, "pet",
        "Pet config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "Pet config-mode frame")
    assertEqual(buffs[1], "nativeAuras",
        "Pet buffs native builder")
    assertEqual(buffs[3], "HELPFUL", "Pet buffs filter")
    assertEqual(debuffs[1], "nativeAuras",
        "Pet debuffs native builder")
    assertEqual(debuffs[3], "HARMFUL", "Pet debuffs filter")
    assertEqual(frame.indicators.buffs.builder, "nativeAuras",
        "Pet buffs construction")
    assertEqual(frame.indicators.buffs.auraFilter, "HELPFUL",
        "Pet buffs construction filter")
    assertEqual(frame.indicators.debuffs.builder, "nativeAuras",
        "Pet debuffs construction")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "Pet debuffs construction filter")
end

local function testPetDisableAndReenableLifecycle()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "pet")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "pet", 1)
    assertEqual(#harness.setupCalls, 2,
        "Pet numeric skip setup count")
    assertEqual(harness.setupCalls[2].skip, false,
        "Pet numeric skip normalization")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "numeric skip duplicate Pet unit-watch registration")

    harness:ClearEvents()
    update(nil, "unitFrames", "pet", true)
    assertEqual(#harness.frames, 1,
        "Pet frame recreated on update")
    assertEqual(#harness.setupCalls, 3,
        "Pet repeated setup count")
    assertEqual(harness.setupCalls[3].skip, true,
        "enabled Pet skip-indicator flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate Pet unit-watch registration")

    harness.UF.config.pet.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pet")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "Pet unit-watch unregister count")
    assertEqual(#harness.disableCalls, 1,
        "Pet indicator disable count")
    assertEqual(frame.enabled, false, "Pet disabled state")
    assertEqual(frame.shown, false, "Pet disabled visibility")
    assertEqual(frame.unitWatchRegistered, false,
        "Pet disabled unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "pet")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "Pet repeated disable unit-watch count")

    harness.UF.config.pet.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "pet", true)
    assertEqual(#harness.setupCalls, 4,
        "Pet re-enable setup count")
    assertEqual(harness.setupCalls[4].skip, false,
        "Pet re-enable skipped disabled indicators")
    assertEqual(#harness.nativeConstructions, 2,
        "Pet re-enable native construction count")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Pet re-enable unit-watch registration")
    assertEqual(frame.enabled, true, "Pet re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "Pet re-enabled unit watch")
end

local function testPetConfigModeGuardsAreLocal()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "pet")
    local frame = harness.frames[1]

    harness.UF.configModeEnabled = true
    frame.unitWatchRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pet")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "unrelated config mode suppressed Pet watch")

    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "pet", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Pet config mode registered unit watch")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled Pet repeated indicator preview entry")

    harness.UF.config.pet.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pet")
    assertEqual(frame.shown, false,
        "disabled Pet config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "disabled Pet indicator preview exits"
    )

    harness.UF.config.pet.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "pet", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "Pet config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "Pet config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "Pet config-mode preview show count")
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("frame.show"),
        "Pet config-mode preview showed before setup"
    )
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "Pet config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Pet config-mode re-enable unit watch")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled Pet indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled Pet indicator preview count")
    end
end

local function testPetDefaultDisabledDoesNotBuild()
    local harness = makeDisabledRuntimeHarness()
    local buffState = harness.buffs:GetNativeAuraState()
    local debuffState = harness.debuffs:GetNativeAuraState()

    assertEqual(#harness.controllers, 2,
        "disabled Pet controller shell count")
    assertEqual(#harness.compiles, 2,
        "disabled Pet descriptor compile count")
    assertEqual(harness.compiles[1].unit, "pet",
        "disabled Pet buffs compile unit")
    assertEqual(harness.compiles[1].auraFilter, "HELPFUL",
        "disabled Pet buffs compile filter")
    assertEqual(harness.compiles[2].unit, "pet",
        "disabled Pet debuffs compile unit")
    assertEqual(harness.compiles[2].auraFilter, "HARMFUL",
        "disabled Pet debuffs compile filter")
    assertEqual(harness.controllers[1].rebuildCount, nil,
        "disabled Pet buffs restricted-container rebuild")
    assertEqual(harness.controllers[2].rebuildCount, nil,
        "disabled Pet debuffs restricted-container rebuild")
    assertEqual(buffState.built, false,
        "disabled Pet buffs native built state")
    assertEqual(debuffState.built, false,
        "disabled Pet debuffs native built state")
    assertEqual(buffState.pending, true,
        "disabled Pet buffs deferred config state")
    assertEqual(debuffState.pending, true,
        "disabled Pet debuffs deferred config state")
end

local function testShippedPetPresetBounds()
    local UF = makePresetCompiler()
    local helpfulFilters = {"HELPFUL"}
    local harmfulFilters = {"HARMFUL"}
    local diagnostics = {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
    }
    local degradations = {
        perGroupLimit = false,
        perGroupSort = false,
        privateAuraSourceUnseparable = true,
        defaultSortPriority = true,
        fixedHolderExtent = true,
        auraTypeColorSourceRulesIgnored = true,
        spellIDListsIgnored = false,
        tooltipPlacementApproximate = false,
        partitionDeferred = false,
    }

    for _, id in ipairs({"default1", "default2"}) do
        local preset = UF.GetPreset(id)
        local indicators = preset.pet.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "pet",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "pet",
            "HARMFUL",
            indicators.debuffs
        )

        assertTrue(buffs,
            id .. " buffs compile error: " .. tostring(buffError))
        assertTrue(debuffs,
            id .. " debuffs compile error: " .. tostring(debuffError))
        assertEqual(buffError, nil, id .. " buffs compile error")
        assertEqual(debuffError, nil, id .. " debuffs compile error")
        assertEqual(indicators.buffs.enabled, false,
            id .. " default buffs state")
        assertEqual(indicators.debuffs.enabled, false,
            id .. " default debuffs state")

        assertEqual(buffs.migrationReady, true,
            id .. " buffs migration readiness")
        assertEqual(buffs.empty, false,
            id .. " buffs empty state")
        assertEqual(buffs.partition, nil,
            id .. " buffs partition")
        assertEqual(buffs.completeSpec.enabled, false,
            id .. " buffs native enabled state")
        assertEqual(buffs.completeSpec.shown, false,
            id .. " buffs native shown state")
        assertMetrics(buffs.metrics, {
            groupCount = 1,
            legacyMaxFrameCount = 22,
            nativeVisibleCapacity = 22,
            nativeBatchSize = 10,
            initialRestrictedButtonCount = 10,
            freshContainerRestrictedButtonCountCeiling = 30,
        }, id .. " buffs metrics")
        assertEqual(buffs.completeSpec.holder.width, 219,
            id .. " buffs holder width")
        assertEqual(buffs.completeSpec.holder.height, 39,
            id .. " buffs holder height")
        assertFilters(buffs, helpfulFilters, id .. " buffs filters")
        assertEqual(buffs.visibility.requiresVisible, false,
            id .. " buffs visibility gate")
        assertEqual(buffs.visibility.requiresAssist, false,
            id .. " buffs assist gate")
        assertDiagnostics(
            buffs.diagnostics,
            diagnostics,
            id .. " buffs diagnostics"
        )
        assertDegradations(
            buffs.degradations,
            degradations,
            id .. " buffs degradation"
        )

        assertEqual(debuffs.migrationReady, true,
            id .. " debuffs migration readiness")
        assertEqual(debuffs.empty, false,
            id .. " debuffs empty state")
        assertEqual(debuffs.partition, nil,
            id .. " debuffs partition")
        assertEqual(debuffs.completeSpec.enabled, false,
            id .. " debuffs native enabled state")
        assertEqual(debuffs.completeSpec.shown, false,
            id .. " debuffs native shown state")
        assertMetrics(debuffs.metrics, {
            groupCount = 1,
            legacyMaxFrameCount = 3,
            nativeVisibleCapacity = 3,
            nativeBatchSize = 10,
            initialRestrictedButtonCount = 10,
            freshContainerRestrictedButtonCountCeiling = 10,
        }, id .. " debuffs metrics")
        assertEqual(debuffs.completeSpec.holder.width, 59,
            id .. " debuffs holder width")
        assertEqual(debuffs.completeSpec.holder.height, 19,
            id .. " debuffs holder height")
        assertFilters(debuffs, harmfulFilters,
            id .. " debuffs filters")
        assertEqual(debuffs.visibility.requiresVisible, false,
            id .. " debuffs visibility gate")
        assertEqual(debuffs.visibility.requiresAssist, false,
            id .. " debuffs assist gate")
        assertDiagnostics(
            debuffs.diagnostics,
            diagnostics,
            id .. " debuffs diagnostics"
        )
        assertDegradations(
            debuffs.degradations,
            degradations,
            id .. " debuffs degradation"
        )
    end
end

testPetActivationAndConstructionOrder()
testPetDisableAndReenableLifecycle()
testPetConfigModeGuardsAreLocal()
testPetDefaultDisabledDoesNotBuild()
testShippedPetPresetBounds()

print("unit_frame_pet_native_aura_test.lua: ok")
