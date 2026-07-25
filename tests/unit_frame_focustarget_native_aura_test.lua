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
            focustarget = {
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
        "CreateLevelText",
        "CreateTargetCounter",
        "CreateRaidIcon",
        "CreateRoleIcon",
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
                "unexpected FocusTarget integration global: "
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
        loadfile("Modules/UnitFrames/Units/FocusTarget.lua")
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

local function makeEventRuntimeHarness(configEnabled)
    local harness = {
        compiles = {},
        controllers = {},
        frameEvents = {},
    }
    local UF = {}
    local AF = {
        UIParent = {
            name = "UIParent",
        },
    }
    local F = {}
    local BFI = {
        funcs = F,
        modules = {
            UnitFrames = UF,
        },
        vars = {},
    }

    function F.isValueNonSecret()
        return true
    end

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.Copy(value)
        return copy(value)
    end

    function AF.RegisterCallback()
    end

    function AF.LoadWidgetPosition(frame, position, anchorTo)
        frame.position = copy(position)
        frame.anchorTo = anchorTo
    end

    function AF.SetFrameLevel(frame, level, relativeTo)
        frame.frameLevel = level
        frame.frameLevelRelativeTo = relativeTo
    end

    function AF.UnitClassBase()
        return "WARRIOR"
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
                enabled = true,
                groups = {},
                holder = {
                    width = 59,
                    height = 59,
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
                position = {"TOPRIGHT", "BOTTOMRIGHT", 0, -1},
            },
            tuningSpec = {
                groups = {},
                holder = {
                    width = 59,
                    height = 59,
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
        function controller:ApplyTuning(tuning)
            self.tuning = copy(tuning)
            self.tuningCount = (self.tuningCount or 0) + 1
        end
        function controller:Destroy()
            self.destroyed = true
        end
        function controller:GetFrame()
            return self.frame
        end
        function controller:Rebuild(spec)
            self.spec = copy(spec)
            self.enabled = spec.enabled
            self.shown = spec.shown
            self.frame.shown = spec.shown
            self.rebuildCount = (self.rebuildCount or 0) + 1
        end
        function controller:Refresh()
            self.refreshCount = (self.refreshCount or 0) + 1
        end
        function controller:SetEnabled(enabled)
            self.enabled = enabled
        end
        function controller:SetShown(shown)
            self.shown = shown
            self.frame.shown = shown
        end
        function controller:SetUnit(unit)
            self.unit = unit
            self.setUnitCount = (self.setUnitCount or 0) + 1
        end

        harness.controllers[#harness.controllers + 1] = controller
        return controller
    end

    function UF.CreateAuras()
        error("event/runtime harness unexpectedly used legacy auras", 2)
    end

    function UF.LoadIndicatorPosition(frame, position, anchorTo)
        frame.position = copy(position)
        frame.anchorTo = anchorTo
    end

    function UF:RegisterEvent()
    end

    function UF:UnregisterEvent()
    end

    local function CreateFrame(frameType, name, parent, template)
        local frame = {
            attributes = {},
            frameType = frameType,
            name = name,
            parent = parent,
            scripts = {},
            hooks = {},
            shown = true,
            template = template,
        }

        function frame:GetName()
            return self.name
        end

        function frame:SetAllPoints()
        end

        function frame:SetFrameStrata()
        end

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
        end

        return frame
    end

    local environment = {
        _G = false,
        AbstractFramework = AF,
        BFIUnitButton_OnLoad = false,
        C_Timer = {
            After = function(_, callback)
                callback()
            end,
        },
        CreateFrame = CreateFrame,
        GameTooltip = {},
        GameTooltip_SetDefaultAnchor = function()
        end,
        GetTime = function()
            return 0
        end,
        GetUnitName = function(unit)
            return unit
        end,
        InCombatLockdown = function()
            return false
        end,
        Mixin = function()
        end,
        PingableType_UnitFrameMixin = {},
        RegisterAttributeDriver = function()
        end,
        UnitCanAssist = function()
            return true
        end,
        UnitClass = function()
            return nil
        end,
        UnitExists = function(unit)
            return unit == "focustarget"
        end,
        UnitGUID = function(unit)
            return "guid:" .. tostring(unit)
        end,
        UnitHasVehicleUI = function()
            return false
        end,
        UnitIsPlayer = function()
            return false
        end,
        UnitIsVisible = function()
            return true
        end,
        error = error,
        ipairs = ipairs,
        math = math,
        next = next,
        pairs = pairs,
        pcall = pcall,
        print = function()
        end,
        select = select,
        strfind = string.find,
        string = string,
        strmatch = string.match,
        table = table,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack,
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
                "unexpected UnitButton/runtime global: "
                    .. tostring(key),
                2
            )
        end,
    })

    for _, path in ipairs({
        "Modules/UnitFrames/UnitButton.lua",
        "Modules/UnitFrames/AuraRuntime.lua",
        "Modules/UnitFrames/Common.lua",
    }) do
        local chunk, loadError = loadfile(path)
        assertTrue(chunk, loadError)
        setfenv(chunk, environment)
        chunk("BFInfinite", BFI)
    end

    local root = {
        attributes = {},
        effectiveUnit = "focustarget",
        enabled = true,
        hooks = {},
        indicators = {},
        name = "BFI_FocusTarget",
        scripts = {},
        shown = true,
        states = {},
        unit = "focustarget",
        _refreshOnUpdate = true,
        _skipDataCache = true,
        _updateOnUnitTargetChanged = "focus",
    }

    function root:GetName()
        return self.name
    end

    function root:GetParent()
        return nil
    end

    function root:HookScript(name, callback)
        self.hooks[name] = callback
    end

    function root:IsVisible()
        return self.shown
    end

    function root:RegisterEvent(event)
        harness.frameEvents[event] = true
    end

    function root:RegisterForClicks()
    end

    function root:RegisterUnitEvent(event, unit)
        harness.frameEvents[event] = unit
    end

    function root:SetAttribute(key, value)
        self.attributes[key] = value
    end

    function root:SetScript(name, callback)
        self.scripts[name] = callback
    end

    function root:UnregisterAllEvents()
        harness.frameEvents = {}
    end

    environment.BFIUnitButton_OnLoad(root)
    local native = UF.CreateNativeAuraIndicator(
        root,
        "BFI_FocusTarget_Debuffs",
        "HARMFUL"
    )
    native.enabled = configEnabled == true
    root.indicators.debuffs = native
    native:LoadConfig({
        enabled = configEnabled == true,
    })

    harness.BFI = BFI
    harness.environment = environment
    harness.native = native
    harness.root = root
    harness.UF = UF

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
        CustomAuraContainerAuraProcessingPolicy = {
            None = 501,
        },
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

local function testFocusTargetActivationAndConstructionOrder()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "FocusTarget update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.legacyConstructions, 0,
        "module-load legacy aura construction")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "focustarget")
    update(nil, "unitFrames", "focus")
    assertEqual(#harness.frames, 0,
        "unrelated update frame allocation")

    update(nil, "unitFrames", "focustarget", true)
    assertEqual(#harness.frames, 1,
        "FocusTarget frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "FocusTarget indicator creation count")
    assertEqual(#harness.legacyConstructions, 1,
        "FocusTarget legacy aura prebuild count")
    assertEqual(#harness.nativeConstructions, 1,
        "FocusTarget native controller prebuild count")
    assertEqual(#harness.setupCalls, 1, "FocusTarget setup count")
    assertEqual(harness.setupCalls[1].skip, false,
        "first FocusTarget setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "FocusTarget initial unit-watch registration")
    assertTrue(
        harness:EventIndex("native.create")
            < harness:EventIndex("setup"),
        "FocusTarget native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("legacy.create")
            < harness:EventIndex("setup"),
        "FocusTarget legacy auras were not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "FocusTarget unit watch registered before setup"
    )

    local frame = harness.frames[1]
    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffs = findIndicator(descriptors, "buffs")
    local debuffs = findIndicator(descriptors, "debuffs")

    assertEqual(frame.name, "BFI_FocusTarget",
        "FocusTarget frame name")
    assertEqual(frame.frameType, "Button", "FocusTarget frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "FocusTarget frame template")
    assertEqual(frame.parent, harness.UF.Parent,
        "FocusTarget frame parent")
    assertEqual(frame.attributes.unit, "focustarget",
        "FocusTarget secure unit")
    assertEqual(frame.unit, "focustarget",
        "FocusTarget runtime unit")
    assertEqual(frame._refreshOnUpdate, true,
        "FocusTarget periodic refresh flag")
    assertEqual(frame._updateOnPlayerTargetChanged, nil,
        "FocusTarget player-target update flag")
    assertEqual(frame._updateOnUnitTargetChanged, "focus",
        "FocusTarget unit-target update flag")
    assertEqual(frame._skipDataCache, true,
        "FocusTarget data-cache flag")
    assertEqual(frame.unitWatchRegistered, true,
        "FocusTarget unit-watch state")
    assertTrue(frame.previewCreated,
        "FocusTarget preview rectangle")
    assertEqual(harness.configMode[1].group, "focustarget",
        "FocusTarget config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "FocusTarget config-mode frame")
    assertEqual(buffs[1], "auras",
        "FocusTarget buffs legacy builder")
    assertEqual(buffs[3], "HELPFUL", "FocusTarget buffs filter")
    assertEqual(debuffs[1], "nativeAuras",
        "FocusTarget debuffs native builder")
    assertEqual(debuffs[3], "HARMFUL",
        "FocusTarget debuffs filter")
    assertEqual(harness.nativeConstructions[1],
        frame.indicators.debuffs,
        "FocusTarget native controller")
    assertEqual(frame.indicators.debuffs.root, frame,
        "FocusTarget native controller parent")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "FocusTarget native controller filter")
    assertEqual(frame.indicators.buffs.builder, "auras",
        "FocusTarget legacy buffs construction")
end

local function testFocusTargetDisableAndReenableLifecycle()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "focustarget")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget", 1)
    assertEqual(#harness.frames, 1,
        "FocusTarget frame recreated on update")
    assertEqual(#harness.setupCalls, 2,
        "FocusTarget repeated setup count")
    assertEqual(harness.setupCalls[2].skip, false,
        "truthy FocusTarget skip flag was not normalized")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate FocusTarget unit-watch registration")

    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget", true)
    assertEqual(#harness.setupCalls, 3,
        "FocusTarget boolean-skip setup count")
    assertEqual(harness.setupCalls[3].skip, true,
        "enabled FocusTarget boolean-skip flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "FocusTarget boolean-skip duplicate unit watch")

    harness.UF.config.focustarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "FocusTarget unit-watch unregister count")
    assertEqual(#harness.disableCalls, 1,
        "FocusTarget indicator disable count")
    assertEqual(frame.enabled, false, "FocusTarget disabled state")
    assertEqual(frame.shown, false,
        "FocusTarget disabled visibility")
    assertEqual(frame.unitWatchRegistered, false,
        "FocusTarget disabled unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "FocusTarget repeated disable unit-watch count")

    harness.UF.config.focustarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget", true)
    assertEqual(#harness.setupCalls, 4,
        "FocusTarget re-enable setup count")
    assertEqual(harness.setupCalls[4].skip, false,
        "FocusTarget re-enable skipped disabled indicators")
    assertEqual(#harness.nativeConstructions, 1,
        "FocusTarget re-enable native construction count")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "FocusTarget re-enable unit-watch registration")
    assertEqual(frame.enabled, true,
        "FocusTarget re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "FocusTarget re-enabled unit watch")
end

local function testFocusTargetConfigModeGuardsAreLocal()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "focustarget")
    local frame = harness.frames[1]

    harness.UF.configModeEnabled = true
    frame.unitWatchRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "unrelated config mode suppressed FocusTarget watch")

    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "FocusTarget config mode registered unit watch")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled FocusTarget repeated indicator preview entry")

    harness.UF.config.focustarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget")
    assertEqual(frame.shown, false,
        "disabled FocusTarget config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "disabled FocusTarget indicator preview exits"
    )

    harness.UF.config.focustarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "focustarget", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "FocusTarget config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "FocusTarget config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "FocusTarget config-mode preview show count")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "FocusTarget config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "FocusTarget config-mode re-enable unit watch")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled FocusTarget indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled FocusTarget indicator preview count")
    end
end

local function testFocusTargetDefaultDisabledDoesNotBuild()
    local harness = makeEventRuntimeHarness(false)
    local state = harness.native:GetNativeAuraState()

    assertEqual(#harness.controllers, 1,
        "disabled FocusTarget controller shell count")
    assertEqual(#harness.compiles, 1,
        "disabled FocusTarget descriptor compile count")
    assertEqual(harness.compiles[1].unit, "focustarget",
        "disabled FocusTarget compile unit")
    assertEqual(harness.controllers[1].rebuildCount, nil,
        "disabled FocusTarget restricted-container rebuild")
    assertEqual(state.built, false,
        "disabled FocusTarget native built state")
    assertEqual(state.pending, true,
        "disabled FocusTarget deferred config state")
end

local function testFocusTargetUnitEventsAndTicksRefreshNativeRuntime()
    local harness = makeEventRuntimeHarness(true)
    local root = harness.root
    local native = harness.native
    local controller = harness.controllers[1]
    local nativeUpdate = native.Update
    local commonUpdateIndicators = harness.UF.UpdateIndicators

    root.hooks.OnShow(root)
    assertEqual(harness.frameEvents.PLAYER_TARGET_CHANGED, nil,
        "FocusTarget PLAYER_TARGET_CHANGED registration")
    assertEqual(harness.frameEvents.UNIT_TARGET, "focus",
        "FocusTarget UNIT_TARGET registration")
    assertEqual(#harness.compiles, 1,
        "FocusTarget initial runtime compile count")
    assertEqual(harness.compiles[1].unit, "focustarget",
        "FocusTarget runtime compile unit")
    assertEqual(controller.rebuildCount, 1,
        "FocusTarget runtime construction count")

    local initialRefreshCount = controller.refreshCount or 0
    local initialSetUnitCount = controller.setUnitCount or 0
    root.scripts.OnUpdate(root, 0.25)
    assertEqual(controller.refreshCount, initialRefreshCount + 1,
        "FocusTarget periodic native refresh count")
    assertEqual(#harness.compiles, 1,
        "FocusTarget tick recompiled stable runtime")
    assertEqual(controller.rebuildCount, 1,
        "FocusTarget tick rebuilt stable runtime")
    assertEqual(controller.setUnitCount or 0, initialSetUnitCount,
        "FocusTarget tick retargeted stable runtime")

    root.scripts.OnEvent(root, "UNIT_TARGET", "focus")
    assertEqual(controller.refreshCount, initialRefreshCount + 2,
        "FocusTarget UNIT_TARGET native refresh count")
    assertEqual(#harness.compiles, 1,
        "FocusTarget UNIT_TARGET recompiled stable runtime")
    assertEqual(controller.rebuildCount, 1,
        "FocusTarget UNIT_TARGET rebuilt stable runtime")
    assertEqual(controller.setUnitCount or 0, initialSetUnitCount,
        "FocusTarget UNIT_TARGET retargeted stable runtime")

    root.scripts.OnEvent(root, "UNIT_TARGET", "target")
    assertEqual(controller.refreshCount, initialRefreshCount + 2,
        "unrelated UNIT_TARGET native refresh count")
    assertEqual(native.Update, nativeUpdate,
        "FocusTarget native Update method identity")
    assertEqual(harness.UF.UpdateIndicators, commonUpdateIndicators,
        "FocusTarget shared UpdateIndicators identity")
end

local function testShippedFocusTargetPresetBounds()
    local UF = makePresetCompiler()
    local helpfulFilters = {
        "HELPFUL|PLAYER",
        "HELPFUL|RAID_IN_COMBAT|!PLAYER",
        "HELPFUL|RAID_PLAYER_DISPELLABLE|!PLAYER"
            .. "|!RAID_IN_COMBAT",
        "HELPFUL|BIG_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT"
            .. "|!RAID_PLAYER_DISPELLABLE",
        "HELPFUL|EXTERNAL_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT"
            .. "|!RAID_PLAYER_DISPELLABLE|!BIG_DEFENSIVE",
    }
    local harmfulFilters = {
        "HARMFUL|PLAYER",
        "HARMFUL|RAID_IN_COMBAT|!PLAYER",
        "HARMFUL|RAID_PLAYER_DISPELLABLE|!PLAYER"
            .. "|!RAID_IN_COMBAT",
    }
    local diagnostics = {
        "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
        "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
        "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
    }
    local degradations = {
        perGroupLimit = true,
        perGroupSort = true,
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
        local indicators = preset.focustarget.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "focustarget",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "focustarget",
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
        assertEqual(buffs.partition, nil,
            id .. " buffs partition")
        assertMetrics(buffs.metrics, {
            groupCount = 5,
            legacyMaxFrameCount = 22,
            nativeVisibleCapacity = 110,
            nativeBatchSize = 10,
            initialRestrictedButtonCount = 50,
            freshContainerRestrictedButtonCountCeiling = 150,
        }, id .. " buffs metrics")
        assertEqual(buffs.completeSpec.holder.width, 219,
            id .. " buffs holder width")
        assertEqual(buffs.completeSpec.holder.height, 199,
            id .. " buffs holder height")
        assertFilters(buffs, helpfulFilters, id .. " buffs filters")
        assertEqual(buffs.visibility.requiresVisible, true,
            id .. " buffs visibility gate")
        assertEqual(buffs.visibility.requiresAssist, true,
            id .. " buffs assist gate")
        assertEqual(#buffs.diagnostics, #diagnostics,
            id .. " buffs diagnostic count")
        for index, value in ipairs(diagnostics) do
            assertEqual(buffs.diagnostics[index], value,
                id .. " buffs diagnostic " .. index)
        end
        for key, value in pairs(degradations) do
            assertEqual(buffs.degradations[key], value,
                id .. " buffs degradation " .. key)
        end

        assertEqual(debuffs.migrationReady, true,
            id .. " debuffs migration readiness")
        assertEqual(debuffs.partition, nil,
            id .. " debuffs partition")
        assertMetrics(debuffs.metrics, {
            groupCount = 3,
            legacyMaxFrameCount = 3,
            nativeVisibleCapacity = 9,
            nativeBatchSize = 10,
            initialRestrictedButtonCount = 30,
            freshContainerRestrictedButtonCountCeiling = 30,
        }, id .. " debuffs metrics")
        assertEqual(debuffs.completeSpec.holder.width, 59,
            id .. " debuffs holder width")
        assertEqual(debuffs.completeSpec.holder.height, 59,
            id .. " debuffs holder height")
        assertFilters(debuffs, harmfulFilters,
            id .. " debuffs filters")
        assertEqual(debuffs.visibility.requiresVisible, true,
            id .. " debuffs visibility gate")
        assertEqual(debuffs.visibility.requiresAssist, false,
            id .. " debuffs assist gate")
        assertEqual(#debuffs.diagnostics, #diagnostics,
            id .. " debuffs diagnostic count")
        for index, value in ipairs(diagnostics) do
            assertEqual(debuffs.diagnostics[index], value,
                id .. " debuffs diagnostic " .. index)
        end
        for key, value in pairs(degradations) do
            assertEqual(debuffs.degradations[key], value,
                id .. " debuffs degradation " .. key)
        end
    end
end

testFocusTargetActivationAndConstructionOrder()
testFocusTargetDisableAndReenableLifecycle()
testFocusTargetConfigModeGuardsAreLocal()
testFocusTargetDefaultDisabledDoesNotBuild()
testFocusTargetUnitEventsAndTicksRefreshNativeRuntime()
testShippedFocusTargetPresetBounds()

print("unit_frame_focustarget_native_aura_test.lua: ok")
