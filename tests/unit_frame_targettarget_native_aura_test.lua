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

local function makeIntegrationHarness(nativeBackendAvailable)
    if nativeBackendAvailable == nil then
        nativeBackendAvailable = true
    end

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
            targettarget = {
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
        local indicator = newIndicator(parent, name, auraFilter, "auras")
        harness.legacyConstructions[
            #harness.legacyConstructions + 1
        ] = indicator
        record("legacy.create", indicator, parent, auraFilter)
        return indicator
    end

    function UF.CreateNativeAuras(parent, name, auraFilter)
        if not nativeBackendAvailable then
            return UF.CreateAuras(parent, name, auraFilter)
        end

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
                "unexpected TargetTarget integration global: "
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
        loadfile("Modules/UnitFrames/Units/TargetTarget.lua")
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

local function makeEventRuntimeHarness()
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
        UnitCanAttack = function()
            return false
        end,
        UnitClass = function()
            return nil
        end,
        UnitExists = function(unit)
            return unit == "targettarget"
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
        UnitIsUnit = function()
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
        setmetatable = setmetatable,
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
        effectiveUnit = "targettarget",
        enabled = true,
        hooks = {},
        indicators = {},
        name = "BFI_TargetTarget",
        scripts = {},
        shown = true,
        states = {},
        unit = "targettarget",
        _skipDataCache = true,
        _updateOnPlayerTargetChanged = true,
        _updateOnUnitTargetChanged = "target",
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
    local buffs = UF.CreateNativeAuraIndicator(
        root,
        "BFI_TargetTarget_Buffs",
        "HELPFUL"
    )
    buffs.enabled = true
    root.indicators.buffs = buffs
    buffs:LoadConfig({
        enabled = true,
    })

    local debuffs = UF.CreateNativeAuraIndicator(
        root,
        "BFI_TargetTarget_Debuffs",
        "HARMFUL"
    )
    debuffs.enabled = true
    root.indicators.debuffs = debuffs
    debuffs:LoadConfig({
        enabled = true,
    })

    harness.BFI = BFI
    harness.environment = environment
    harness.natives = {
        buffs = buffs,
        debuffs = debuffs,
    }
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

local function testTargetTargetActivationAndConstructionOrder()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "TargetTarget update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "targettarget")
    update(nil, "unitFrames", "target")
    assertEqual(#harness.frames, 0,
        "unrelated update frame allocation")

    update(nil, "unitFrames", "targettarget", true)
    assertEqual(#harness.frames, 1,
        "TargetTarget frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "TargetTarget indicator creation count")
    assertEqual(#harness.nativeConstructions, 2,
        "TargetTarget native controller prebuild count")
    assertEqual(#harness.legacyConstructions, 0,
        "TargetTarget native path legacy construction count")
    assertEqual(#harness.setupCalls, 1, "TargetTarget setup count")
    assertEqual(harness.setupCalls[1].skip, false,
        "first TargetTarget setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "TargetTarget initial unit-watch registration")
    assertTrue(
        harness:EventIndex("native.create", 2)
            < harness:EventIndex("setup"),
        "TargetTarget native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "TargetTarget unit watch registered before setup"
    )

    local frame = harness.frames[1]
    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffs = findIndicator(descriptors, "buffs")
    local debuffs = findIndicator(descriptors, "debuffs")

    assertEqual(frame.name, "BFI_TargetTarget",
        "TargetTarget frame name")
    assertEqual(frame.frameType, "Button", "TargetTarget frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "TargetTarget frame template")
    assertEqual(frame.parent, harness.UF.Parent,
        "TargetTarget frame parent")
    assertEqual(frame.attributes.unit, "targettarget",
        "TargetTarget secure unit")
    assertEqual(frame.unit, "targettarget",
        "TargetTarget runtime unit")
    assertEqual(frame._updateOnPlayerTargetChanged, true,
        "TargetTarget player-target update flag")
    assertEqual(frame._updateOnUnitTargetChanged, "target",
        "TargetTarget unit-target update flag")
    assertEqual(frame._skipDataCache, true,
        "TargetTarget data-cache flag")
    assertEqual(frame.unitWatchRegistered, true,
        "TargetTarget unit-watch state")
    assertTrue(frame.previewCreated,
        "TargetTarget preview rectangle")
    assertEqual(harness.configMode[1].group, "targettarget",
        "TargetTarget config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "TargetTarget config-mode frame")
    assertEqual(buffs[1], "nativeAuras",
        "TargetTarget buffs native builder")
    assertEqual(buffs[3], "HELPFUL", "TargetTarget buffs filter")
    assertEqual(debuffs[1], "nativeAuras",
        "TargetTarget debuffs native builder")
    assertEqual(debuffs[3], "HARMFUL",
        "TargetTarget debuffs filter")
    assertEqual(harness.nativeConstructions[1],
        frame.indicators.buffs,
        "TargetTarget native buffs controller")
    assertEqual(harness.nativeConstructions[2],
        frame.indicators.debuffs,
        "TargetTarget native debuffs controller")
    assertEqual(frame.indicators.buffs.root, frame,
        "TargetTarget native buffs controller parent")
    assertEqual(frame.indicators.buffs.auraFilter, "HELPFUL",
        "TargetTarget native buffs controller filter")
    assertEqual(frame.indicators.debuffs.root, frame,
        "TargetTarget native debuffs controller parent")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "TargetTarget native debuffs controller filter")
    assertEqual(frame.indicators.buffs.builder, "nativeAuras",
        "TargetTarget native buffs construction")
    assertEqual(frame.indicators.debuffs.builder, "nativeAuras",
        "TargetTarget native debuffs construction")
end

local function testTargetTargetDisableAndReenableLifecycle()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "targettarget")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget", 1)
    assertEqual(#harness.frames, 1,
        "TargetTarget frame recreated on update")
    assertEqual(#harness.nativeConstructions, 2,
        "TargetTarget repeated-update native construction count")
    assertEqual(#harness.setupCalls, 2,
        "TargetTarget repeated setup count")
    assertEqual(harness.setupCalls[2].skip, false,
        "truthy TargetTarget skip flag was not normalized")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate TargetTarget unit-watch registration")

    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget", true)
    assertEqual(#harness.setupCalls, 3,
        "TargetTarget boolean-skip setup count")
    assertEqual(harness.setupCalls[3].skip, true,
        "enabled TargetTarget boolean-skip flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "TargetTarget boolean-skip duplicate unit watch")

    harness.UF.config.targettarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "TargetTarget unit-watch unregister count")
    assertEqual(#harness.disableCalls, 1,
        "TargetTarget indicator disable count")
    assertEqual(frame.enabled, false, "TargetTarget disabled state")
    assertEqual(frame.shown, false,
        "TargetTarget disabled visibility")
    assertEqual(frame.unitWatchRegistered, false,
        "TargetTarget disabled unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "TargetTarget repeated disable unit-watch count")

    harness.UF.config.targettarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget", true)
    assertEqual(#harness.setupCalls, 4,
        "TargetTarget re-enable setup count")
    assertEqual(harness.setupCalls[4].skip, false,
        "TargetTarget re-enable skipped disabled indicators")
    assertEqual(#harness.nativeConstructions, 2,
        "TargetTarget re-enable native construction count")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "TargetTarget re-enable unit-watch registration")
    assertEqual(frame.enabled, true,
        "TargetTarget re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "TargetTarget re-enabled unit watch")
end

local function testTargetTargetUnavailableNativeBackendFallback()
    local harness = makeIntegrationHarness(false)
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "targettarget")
    local frame = harness.frames[1]

    assertEqual(#harness.nativeConstructions, 0,
        "unavailable backend TargetTarget native construction count")
    assertEqual(#harness.legacyConstructions, 2,
        "unavailable backend TargetTarget legacy construction count")
    assertEqual(frame.indicators.buffs.builder, "auras",
        "unavailable backend TargetTarget buffs fallback")
    assertEqual(frame.indicators.buffs.auraFilter, "HELPFUL",
        "unavailable backend TargetTarget buffs filter")
    assertEqual(frame.indicators.debuffs.builder, "auras",
        "unavailable backend TargetTarget debuffs fallback")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "unavailable backend TargetTarget debuffs filter")

    update(nil, "unitFrames", "targettarget", true)
    harness.UF.config.targettarget.general.enabled = false
    update(nil, "unitFrames", "targettarget")
    harness.UF.config.targettarget.general.enabled = true
    update(nil, "unitFrames", "targettarget", true)
    assertEqual(#harness.frames, 1,
        "unavailable backend TargetTarget fallback frame growth")
    assertEqual(#harness.legacyConstructions, 2,
        "unavailable backend TargetTarget fallback indicator growth")
end

local function testTargetTargetConfigModeGuardsAreLocal()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "targettarget")
    local frame = harness.frames[1]

    harness.UF.configModeEnabled = true
    frame.unitWatchRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "unrelated config mode suppressed TargetTarget watch")

    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "TargetTarget config mode registered unit watch")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled TargetTarget repeated indicator preview entry")

    harness.UF.config.targettarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget")
    assertEqual(frame.shown, false,
        "disabled TargetTarget config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "disabled TargetTarget indicator preview exits"
    )

    harness.UF.config.targettarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "targettarget", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "TargetTarget config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "TargetTarget config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "TargetTarget config-mode preview show count")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "TargetTarget config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "TargetTarget config-mode re-enable unit watch")
    assertEqual(#harness.nativeConstructions, 2,
        "TargetTarget config-mode native construction count")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled TargetTarget indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled TargetTarget indicator preview count")
    end
end

local function testTargetTargetUnitEventsRefreshNativeRuntime()
    local harness = makeEventRuntimeHarness()
    local root = harness.root
    local buffs = harness.natives.buffs
    local debuffs = harness.natives.debuffs
    local buffController = harness.controllers[1]
    local debuffController = harness.controllers[2]
    local buffsUpdate = buffs.Update
    local debuffsUpdate = debuffs.Update
    local commonUpdateIndicators = harness.UF.UpdateIndicators

    root.hooks.OnShow(root)
    assertEqual(harness.frameEvents.PLAYER_TARGET_CHANGED, true,
        "TargetTarget PLAYER_TARGET_CHANGED registration")
    assertEqual(harness.frameEvents.UNIT_TARGET, "target",
        "TargetTarget UNIT_TARGET registration")
    assertEqual(#harness.compiles, 2,
        "TargetTarget initial runtime compile count")
    assertEqual(harness.compiles[1].unit, "targettarget",
        "TargetTarget buffs runtime compile unit")
    assertEqual(harness.compiles[1].auraFilter, "HELPFUL",
        "TargetTarget buffs runtime compile filter")
    assertEqual(harness.compiles[2].unit, "targettarget",
        "TargetTarget debuffs runtime compile unit")
    assertEqual(harness.compiles[2].auraFilter, "HARMFUL",
        "TargetTarget debuffs runtime compile filter")
    assertEqual(buffController.rebuildCount, 1,
        "TargetTarget buffs runtime construction count")
    assertEqual(debuffController.rebuildCount, 1,
        "TargetTarget debuffs runtime construction count")

    local initialBuffRefreshCount = buffController.refreshCount or 0
    local initialDebuffRefreshCount = debuffController.refreshCount or 0
    local initialBuffSetUnitCount = buffController.setUnitCount or 0
    local initialDebuffSetUnitCount = debuffController.setUnitCount or 0
    root.scripts.OnEvent(root, "PLAYER_TARGET_CHANGED")
    assertEqual(
        buffController.refreshCount,
        initialBuffRefreshCount + 1,
        "PLAYER_TARGET_CHANGED buffs refresh count"
    )
    assertEqual(
        debuffController.refreshCount,
        initialDebuffRefreshCount + 1,
        "PLAYER_TARGET_CHANGED debuffs refresh count"
    )
    assertEqual(#harness.compiles, 2,
        "PLAYER_TARGET_CHANGED recompiled stable runtime")
    assertEqual(buffController.rebuildCount, 1,
        "PLAYER_TARGET_CHANGED rebuilt stable buffs runtime")
    assertEqual(debuffController.rebuildCount, 1,
        "PLAYER_TARGET_CHANGED rebuilt stable debuffs runtime")
    assertEqual(
        buffController.setUnitCount or 0,
        initialBuffSetUnitCount,
        "PLAYER_TARGET_CHANGED retargeted stable buffs runtime"
    )
    assertEqual(
        debuffController.setUnitCount or 0,
        initialDebuffSetUnitCount,
        "PLAYER_TARGET_CHANGED retargeted stable debuffs runtime"
    )

    root.scripts.OnEvent(root, "UNIT_TARGET", "target")
    assertEqual(
        buffController.refreshCount,
        initialBuffRefreshCount + 2,
        "UNIT_TARGET buffs refresh count"
    )
    assertEqual(
        debuffController.refreshCount,
        initialDebuffRefreshCount + 2,
        "UNIT_TARGET debuffs refresh count"
    )
    assertEqual(#harness.compiles, 2,
        "UNIT_TARGET recompiled stable runtime")
    assertEqual(buffController.rebuildCount, 1,
        "UNIT_TARGET rebuilt stable buffs runtime")
    assertEqual(debuffController.rebuildCount, 1,
        "UNIT_TARGET rebuilt stable debuffs runtime")
    assertEqual(
        buffController.setUnitCount or 0,
        initialBuffSetUnitCount,
        "UNIT_TARGET retargeted stable buffs runtime"
    )
    assertEqual(
        debuffController.setUnitCount or 0,
        initialDebuffSetUnitCount,
        "UNIT_TARGET retargeted stable debuffs runtime"
    )

    root.scripts.OnEvent(root, "UNIT_TARGET", "focus")
    assertEqual(
        buffController.refreshCount,
        initialBuffRefreshCount + 2,
        "unrelated UNIT_TARGET buffs refresh count"
    )
    assertEqual(
        debuffController.refreshCount,
        initialDebuffRefreshCount + 2,
        "unrelated UNIT_TARGET debuffs refresh count"
    )
    assertEqual(buffs.Update, buffsUpdate,
        "TargetTarget buffs Update method identity")
    assertEqual(debuffs.Update, debuffsUpdate,
        "TargetTarget debuffs Update method identity")
    assertEqual(harness.UF.UpdateIndicators, commonUpdateIndicators,
        "TargetTarget shared UpdateIndicators identity")
end

local function testShippedTargetTargetPresetBounds()
    local UF = makePresetCompiler()

    for _, id in ipairs({"default1", "default2"}) do
        local preset = UF.GetPreset(id)
        local indicators = preset.targettarget.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "targettarget",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "targettarget",
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

        assertEqual(buffs.metrics.groupCount, 5,
            id .. " buffs group count")
        assertEqual(buffs.metrics.legacyMaxFrameCount, 22,
            id .. " buffs legacy capacity")
        assertEqual(buffs.metrics.nativeVisibleCapacity, 110,
            id .. " buffs native capacity")
        assertEqual(buffs.metrics.initialRestrictedButtonCount, 50,
            id .. " buffs initial native buttons")
        assertEqual(
            buffs.metrics.freshContainerRestrictedButtonCountCeiling,
            150,
            id .. " buffs native button ceiling"
        )
        assertEqual(buffs.completeSpec.holder.width, 219,
            id .. " buffs holder width")
        assertEqual(buffs.completeSpec.holder.height, 199,
            id .. " buffs holder height")
        assertEqual(buffs.visibility.requiresVisible, true,
            id .. " buffs visibility gate")
        assertEqual(buffs.visibility.requiresAssist, true,
            id .. " buffs assist gate")

        assertEqual(debuffs.migrationReady, true,
            id .. " debuffs migration readiness")
        assertEqual(debuffs.metrics.groupCount, 3,
            id .. " debuffs group count")
        assertEqual(debuffs.metrics.legacyMaxFrameCount, 3,
            id .. " debuffs legacy capacity")
        assertEqual(debuffs.metrics.nativeVisibleCapacity, 9,
            id .. " debuffs native capacity")
        assertEqual(debuffs.metrics.initialRestrictedButtonCount, 30,
            id .. " debuffs initial native buttons")
        assertEqual(
            debuffs.metrics.freshContainerRestrictedButtonCountCeiling,
            30,
            id .. " debuffs native button ceiling"
        )
        assertEqual(debuffs.completeSpec.holder.width, 59,
            id .. " debuffs holder width")
        assertEqual(debuffs.completeSpec.holder.height, 59,
            id .. " debuffs holder height")
        assertEqual(debuffs.partition, nil,
            id .. " debuffs partition")
        assertEqual(debuffs.completeSpec.groups[1].filterString,
            "HARMFUL|PLAYER", id .. " debuffs player filter")
        assertEqual(debuffs.completeSpec.groups[2].filterString,
            "HARMFUL|RAID_IN_COMBAT|!PLAYER",
            id .. " debuffs raid filter")
        assertEqual(debuffs.completeSpec.groups[3].filterString,
            "HARMFUL|RAID_PLAYER_DISPELLABLE|!PLAYER"
                .. "|!RAID_IN_COMBAT",
            id .. " debuffs dispellable filter")
        assertEqual(debuffs.visibility.requiresVisible, true,
            id .. " debuffs visibility gate")
        assertEqual(debuffs.visibility.requiresAssist, false,
            id .. " debuffs assist gate")
        assertEqual(#debuffs.diagnostics, 3,
            id .. " debuffs diagnostic count")
        assertEqual(
            debuffs.diagnostics[1],
            "NATIVE_DEFAULT_SORT_ADDS_PRIORITY",
            id .. " debuffs default-sort diagnostic"
        )
        assertEqual(
            debuffs.diagnostics[2],
            "NATIVE_HOLDER_USES_MAXIMUM_EXTENT",
            id .. " debuffs holder diagnostic"
        )
        assertEqual(
            debuffs.diagnostics[3],
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED",
            id .. " debuffs source-color diagnostic"
        )
        assertEqual(debuffs.degradations.perGroupLimit, true,
            id .. " debuffs per-group-limit degradation")
        assertEqual(debuffs.degradations.perGroupSort, true,
            id .. " debuffs per-group-sort degradation")
        assertEqual(
            debuffs.degradations.privateAuraSourceUnseparable,
            true,
            id .. " debuffs private-aura-source degradation"
        )
        assertEqual(debuffs.degradations.defaultSortPriority, true,
            id .. " debuffs default-sort degradation")
        assertEqual(debuffs.degradations.fixedHolderExtent, true,
            id .. " debuffs holder-extent degradation")
        assertEqual(
            debuffs.degradations.auraTypeColorSourceRulesIgnored,
            true,
            id .. " debuffs source-color degradation"
        )
        assertEqual(debuffs.degradations.spellIDListsIgnored, false,
            id .. " debuffs spell-list degradation")
        assertEqual(
            debuffs.degradations.tooltipPlacementApproximate,
            false,
            id .. " debuffs tooltip degradation"
        )
        assertEqual(debuffs.degradations.partitionDeferred, false,
            id .. " debuffs partition degradation")
    end
end

testTargetTargetActivationAndConstructionOrder()
testTargetTargetDisableAndReenableLifecycle()
testTargetTargetConfigModeGuardsAreLocal()
testTargetTargetUnavailableNativeBackendFallback()
testTargetTargetUnitEventsRefreshNativeRuntime()
testShippedTargetTargetPresetBounds()

print("unit_frame_targettarget_native_aura_test.lua: ok")
