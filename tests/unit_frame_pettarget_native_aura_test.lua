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
            pettarget = {
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
                "unexpected PetTarget integration global: "
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
        loadfile("Modules/UnitFrames/Units/PetTarget.lua")
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

local function makeEventRuntimeHarness(
    configEnabled,
    hasNativeBackend
)
    if hasNativeBackend == nil then
        hasNativeBackend = true
    end

    local harness = {
        compiles = {},
        controllers = {},
        frameEvents = {},
        legacyConstructions = {},
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
        return hasNativeBackend
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

    function UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
        local indicator = {
            auraFilter = auraFilter,
            builder = "auras",
            hasSubFrame = hasSubFrame,
            name = name,
            root = parent,
        }

        function indicator:Disable()
            self.enabled = false
            self.disableCount = (self.disableCount or 0) + 1
        end

        function indicator:DisableConfigMode()
            self.configMode = false
            self.disableConfigModeCount =
                (self.disableConfigModeCount or 0) + 1
        end

        function indicator:Enable()
            self.enabled = true
            self.enableCount = (self.enableCount or 0) + 1
        end

        function indicator:EnableConfigMode()
            self.configMode = true
            self.enableConfigModeCount =
                (self.enableConfigModeCount or 0) + 1
        end

        function indicator:LoadConfig(config)
            self.config = copy(config)
            self.loadConfigCount =
                (self.loadConfigCount or 0) + 1
        end

        function indicator:Update()
            self.updateCount = (self.updateCount or 0) + 1
        end

        harness.legacyConstructions[
            #harness.legacyConstructions + 1
        ] = indicator
        return indicator
    end

    function UF.GetPublicUnitIdentityValue(value)
        return value, true
    end

    function UF.GetPublicUnitIdentitySnapshot(unit)
        return {
            name = unit,
            class = nil,
            guid = "guid:" .. tostring(unit),
            isPlayer = false,
            inVehicle = false,
        }
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

        function frame:GetObjectType()
            return "Frame"
        end

        function frame:Hide()
            self.shown = false
        end

        function frame:SetAllPoints(relativeTo)
            self.allPoints = relativeTo
        end

        function frame:SetAlpha(alpha)
            self.alpha = alpha
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
        GetBuildInfo = function()
            return "12.1.0", "69273", "Aug 11 2026", 120100
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
            return unit == "pettarget"
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
    assertEqual(rawget(environment, "UnitIsUnit"), nil,
        "UnitButton/runtime UnitIsUnit stub")

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
        effectiveUnit = "pettarget",
        enabled = true,
        hooks = {},
        indicators = {},
        name = "BFI_PetTarget",
        scripts = {},
        shown = true,
        states = {},
        unit = "pettarget",
        _refreshOnUpdate = true,
        _skipDataCache = true,
        _updateOnUnitTargetChanged = "pet",
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
    local buffs = UF.CreateNativeAuras(
        root,
        "BFI_PetTarget_Buffs",
        "HELPFUL"
    )
    local debuffs = UF.CreateNativeAuras(
        root,
        "BFI_PetTarget_Debuffs",
        "HARMFUL"
    )
    root.indicators.buffs = buffs
    root.indicators.debuffs = debuffs
    for _, indicator in ipairs({buffs, debuffs}) do
        indicator.enabled = configEnabled == true
        indicator:LoadConfig({
            enabled = configEnabled == true,
        })
    end

    harness.BFI = BFI
    harness.buffs = buffs
    harness.debuffs = debuffs
    harness.environment = environment
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
        funcs = {},
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
        AuraUtil = {
            AuraFilters = {
                Important = "IMPORTANT",
                Dispellable = "DISPELLABLE",
            },
        },
        GetCVar = function()
            return "0"
        end,
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

local function testPetTargetActivationAndConstructionOrder()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "PetTarget update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.legacyConstructions, 0,
        "module-load legacy aura construction")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "pettarget")
    update(nil, "unitFrames", "pet")
    assertEqual(#harness.frames, 0,
        "unrelated update frame allocation")

    update(nil, "unitFrames", "pettarget", true)
    assertEqual(#harness.frames, 1,
        "PetTarget frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "PetTarget indicator creation count")
    assertEqual(#harness.legacyConstructions, 0,
        "PetTarget legacy aura prebuild count")
    assertEqual(#harness.nativeConstructions, 2,
        "PetTarget native controller prebuild count")
    assertEqual(#harness.setupCalls, 1, "PetTarget setup count")
    assertEqual(harness.setupCalls[1].skip, false,
        "first PetTarget setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "PetTarget initial unit-watch registration")
    assertTrue(
        harness:EventIndex("native.create", 1)
            < harness:EventIndex("setup"),
        "PetTarget first native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("native.create", 2)
            < harness:EventIndex("setup"),
        "PetTarget second native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "PetTarget unit watch registered before setup"
    )

    local frame = harness.frames[1]
    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffs = findIndicator(descriptors, "buffs")
    local debuffs = findIndicator(descriptors, "debuffs")

    assertEqual(frame.name, "BFI_PetTarget",
        "PetTarget frame name")
    assertEqual(frame.frameType, "Button", "PetTarget frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "PetTarget frame template")
    assertEqual(frame.parent, harness.UF.Parent,
        "PetTarget frame parent")
    assertEqual(frame.attributes.unit, "pettarget",
        "PetTarget secure unit")
    assertEqual(frame.unit, "pettarget",
        "PetTarget runtime unit")
    assertEqual(frame._refreshOnUpdate, true,
        "PetTarget periodic refresh flag")
    assertEqual(frame._updateOnPlayerTargetChanged, nil,
        "PetTarget player-target update flag")
    assertEqual(frame._updateOnUnitTargetChanged, "pet",
        "PetTarget unit-target update flag")
    assertEqual(frame._skipDataCache, true,
        "PetTarget data-cache flag")
    assertEqual(frame.unitWatchRegistered, true,
        "PetTarget unit-watch state")
    assertTrue(frame.previewCreated,
        "PetTarget preview rectangle")
    assertEqual(harness.configMode[1].group, "pettarget",
        "PetTarget config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "PetTarget config-mode frame")
    assertEqual(buffs[1], "nativeAuras",
        "PetTarget buffs native builder")
    assertEqual(buffs[3], "HELPFUL", "PetTarget buffs filter")
    assertEqual(debuffs[1], "nativeAuras",
        "PetTarget debuffs native builder")
    assertEqual(debuffs[3], "HARMFUL",
        "PetTarget debuffs filter")
    assertEqual(harness.nativeConstructions[1],
        frame.indicators.buffs,
        "PetTarget buffs native controller")
    assertEqual(frame.indicators.buffs.root, frame,
        "PetTarget buffs native controller parent")
    assertEqual(frame.indicators.buffs.auraFilter, "HELPFUL",
        "PetTarget buffs native controller filter")
    assertEqual(harness.nativeConstructions[2],
        frame.indicators.debuffs,
        "PetTarget debuffs native controller")
    assertEqual(frame.indicators.debuffs.root, frame,
        "PetTarget native controller parent")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "PetTarget native controller filter")
    assertEqual(frame.indicators.buffs.builder, "nativeAuras",
        "PetTarget native buffs construction")
end

local function testPetTargetDisableAndReenableLifecycle()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "pettarget")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget", 1)
    assertEqual(#harness.frames, 1,
        "PetTarget frame recreated on update")
    assertEqual(#harness.setupCalls, 2,
        "PetTarget repeated setup count")
    assertEqual(harness.setupCalls[2].skip, false,
        "truthy PetTarget skip flag was not normalized")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate PetTarget unit-watch registration")

    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget", true)
    assertEqual(#harness.setupCalls, 3,
        "PetTarget boolean-skip setup count")
    assertEqual(harness.setupCalls[3].skip, true,
        "enabled PetTarget boolean-skip flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "PetTarget boolean-skip duplicate unit watch")

    harness.UF.config.pettarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "PetTarget unit-watch unregister count")
    assertEqual(#harness.disableCalls, 1,
        "PetTarget indicator disable count")
    assertEqual(frame.enabled, false, "PetTarget disabled state")
    assertEqual(frame.shown, false,
        "PetTarget disabled visibility")
    assertEqual(frame.unitWatchRegistered, false,
        "PetTarget disabled unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "PetTarget repeated disable unit-watch count")

    harness.UF.config.pettarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget", true)
    assertEqual(#harness.setupCalls, 4,
        "PetTarget re-enable setup count")
    assertEqual(harness.setupCalls[4].skip, false,
        "PetTarget re-enable skipped disabled indicators")
    assertEqual(#harness.nativeConstructions, 2,
        "PetTarget re-enable native construction count")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "PetTarget re-enable unit-watch registration")
    assertEqual(frame.enabled, true,
        "PetTarget re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "PetTarget re-enabled unit watch")
end

local function testPetTargetConfigModeGuardsAreLocal()
    local harness = makeIntegrationHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "pettarget")
    local frame = harness.frames[1]

    harness.UF.configModeEnabled = true
    frame.unitWatchRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "unrelated config mode suppressed PetTarget watch")

    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "PetTarget config mode registered unit watch")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled PetTarget repeated indicator preview entry")

    harness.UF.config.pettarget.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget")
    assertEqual(frame.shown, false,
        "disabled PetTarget config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "disabled PetTarget indicator preview exits"
    )

    harness.UF.config.pettarget.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "pettarget", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "PetTarget config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "PetTarget config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "PetTarget config-mode preview show count")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "PetTarget config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "PetTarget config-mode re-enable unit watch")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled PetTarget indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled PetTarget indicator preview count")
    end
end

local function testPetTargetDefaultDisabledDoesNotBuild()
    local harness = makeEventRuntimeHarness(false)
    local buffState = harness.buffs:GetNativeAuraState()
    local debuffState = harness.debuffs:GetNativeAuraState()

    assertEqual(#harness.controllers, 2,
        "disabled PetTarget controller shell count")
    assertEqual(#harness.compiles, 2,
        "disabled PetTarget descriptor compile count")
    assertEqual(harness.compiles[1].unit, "pettarget",
        "disabled PetTarget buffs compile unit")
    assertEqual(harness.compiles[1].auraFilter, "HELPFUL",
        "disabled PetTarget buffs compile filter")
    assertEqual(harness.compiles[2].unit, "pettarget",
        "disabled PetTarget debuffs compile unit")
    assertEqual(harness.compiles[2].auraFilter, "HARMFUL",
        "disabled PetTarget debuffs compile filter")
    assertEqual(harness.controllers[1].rebuildCount, nil,
        "disabled PetTarget buffs restricted-container rebuild")
    assertEqual(harness.controllers[2].rebuildCount, nil,
        "disabled PetTarget debuffs restricted-container rebuild")
    assertEqual(buffState.built, false,
        "disabled PetTarget buffs native built state")
    assertEqual(debuffState.built, false,
        "disabled PetTarget debuffs native built state")
    assertEqual(buffState.pending, true,
        "disabled PetTarget buffs deferred config state")
    assertEqual(debuffState.pending, true,
        "disabled PetTarget debuffs deferred config state")
end

local function testPetTargetUnitEventsAndTicksRefreshNativeRuntime()
    local harness = makeEventRuntimeHarness(true)
    local root = harness.root
    local buffs = harness.buffs
    local debuffs = harness.debuffs
    local buffController = harness.controllers[1]
    local debuffController = harness.controllers[2]
    local buffUpdate = buffs.Update
    local debuffUpdate = debuffs.Update
    local commonUpdateIndicators = harness.UF.UpdateIndicators

    root.hooks.OnShow(root)
    assertEqual(harness.frameEvents.PLAYER_TARGET_CHANGED, nil,
        "PetTarget PLAYER_TARGET_CHANGED registration")
    assertEqual(harness.frameEvents.UNIT_TARGET, "pet",
        "PetTarget UNIT_TARGET registration")
    assertEqual(#harness.compiles, 2,
        "PetTarget initial runtime compile count")
    assertEqual(harness.compiles[1].unit, "pettarget",
        "PetTarget buffs runtime compile unit")
    assertEqual(harness.compiles[2].unit, "pettarget",
        "PetTarget debuffs runtime compile unit")
    assertEqual(buffController.rebuildCount, 1,
        "PetTarget buffs runtime construction count")
    assertEqual(debuffController.rebuildCount, 1,
        "PetTarget debuffs runtime construction count")

    local initialBuffRefreshCount =
        buffController.refreshCount or 0
    local initialDebuffRefreshCount =
        debuffController.refreshCount or 0
    local initialBuffSetUnitCount =
        buffController.setUnitCount or 0
    local initialDebuffSetUnitCount =
        debuffController.setUnitCount or 0
    root.scripts.OnUpdate(root, 0.25)
    assertEqual(
        buffController.refreshCount,
        initialBuffRefreshCount + 1,
        "PetTarget periodic buffs refresh count"
    )
    assertEqual(
        debuffController.refreshCount,
        initialDebuffRefreshCount + 1,
        "PetTarget periodic debuffs refresh count"
    )
    assertEqual(#harness.compiles, 2,
        "PetTarget tick recompiled stable runtime")
    assertEqual(buffController.rebuildCount, 1,
        "PetTarget tick rebuilt stable buffs runtime")
    assertEqual(debuffController.rebuildCount, 1,
        "PetTarget tick rebuilt stable debuffs runtime")
    assertEqual(
        buffController.setUnitCount or 0,
        initialBuffSetUnitCount,
        "PetTarget tick retargeted stable buffs runtime"
    )
    assertEqual(
        debuffController.setUnitCount or 0,
        initialDebuffSetUnitCount,
        "PetTarget tick retargeted stable debuffs runtime"
    )

    root.scripts.OnEvent(root, "UNIT_TARGET", "pet")
    assertEqual(
        buffController.refreshCount,
        initialBuffRefreshCount + 2,
        "PetTarget UNIT_TARGET buffs refresh count"
    )
    assertEqual(
        debuffController.refreshCount,
        initialDebuffRefreshCount + 2,
        "PetTarget UNIT_TARGET debuffs refresh count"
    )
    assertEqual(#harness.compiles, 2,
        "PetTarget UNIT_TARGET recompiled stable runtime")
    assertEqual(buffController.rebuildCount, 1,
        "PetTarget UNIT_TARGET rebuilt stable buffs runtime")
    assertEqual(debuffController.rebuildCount, 1,
        "PetTarget UNIT_TARGET rebuilt stable debuffs runtime")
    assertEqual(
        buffController.setUnitCount or 0,
        initialBuffSetUnitCount,
        "PetTarget UNIT_TARGET retargeted stable buffs runtime"
    )
    assertEqual(
        debuffController.setUnitCount or 0,
        initialDebuffSetUnitCount,
        "PetTarget UNIT_TARGET retargeted stable debuffs runtime"
    )

    root.scripts.OnEvent(root, "UNIT_TARGET", "target")
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
    assertEqual(#harness.controllers, 2,
        "PetTarget stable routing controller growth")
    assertEqual(buffs.Update, buffUpdate,
        "PetTarget buffs Update method identity")
    assertEqual(debuffs.Update, debuffUpdate,
        "PetTarget debuffs Update method identity")
    assertEqual(harness.UF.UpdateIndicators, commonUpdateIndicators,
        "PetTarget shared UpdateIndicators identity")
end

local function testPetTargetRuntimeLifecycleHasNoGrowth()
    local harness = makeEventRuntimeHarness(true)
    local root = harness.root
    local indicators = {harness.buffs, harness.debuffs}

    root.hooks.OnShow(root)
    for index, indicator in ipairs(indicators) do
        local controller = harness.controllers[index]
        local initialRefreshCount = controller.refreshCount or 0

        indicator:Disable()
        assertEqual(
            indicator:GetNativeAuraState().active,
            false,
            "disabled PetTarget runtime " .. index
        )
        assertEqual(controller.shown, false,
            "disabled PetTarget holder " .. index)

        indicator:Enable()
        assertEqual(
            indicator:GetNativeAuraState().active,
            true,
            "re-enabled PetTarget runtime " .. index
        )
        assertEqual(
            controller.refreshCount,
            initialRefreshCount + 1,
            "re-enabled PetTarget refresh " .. index
        )

        indicator:LoadConfig({
            enabled = true,
            tuningRevision = 1,
        })
        assertEqual(controller.rebuildCount, 1,
            "PetTarget tuning rebuilt runtime " .. index)
        assertEqual(controller.tuningCount, 1,
            "PetTarget tuning apply count " .. index)

        indicator.enabled = false
        indicator:LoadConfig({
            enabled = false,
            tuningRevision = 2,
        })
        indicator:Disable()
        assertEqual(controller.rebuildCount, 1,
            "PetTarget disable rebuilt runtime " .. index)

        indicator.enabled = true
        indicator:LoadConfig({
            enabled = true,
            tuningRevision = 3,
        })
        indicator:Enable()
        assertEqual(controller.rebuildCount, 1,
            "PetTarget re-enable rebuilt runtime " .. index)
    end

    root.inConfigMode = true
    for _, indicator in ipairs(indicators) do
        indicator:EnableConfigMode()
        indicator:EnableConfigMode()
    end
    assertEqual(#harness.legacyConstructions, 2,
        "PetTarget config preview allocation count")
    assertEqual(#harness.controllers, 2,
        "PetTarget config mode controller growth")

    root.inConfigMode = false
    for index, indicator in ipairs(indicators) do
        indicator:DisableConfigMode()
        indicator:Enable()
        assertEqual(harness.controllers[index].rebuildCount, 1,
            "PetTarget config exit rebuilt runtime " .. index)
    end
    assertEqual(#harness.controllers, 2,
        "PetTarget lifecycle controller growth")
    assertEqual(#harness.compiles, 8,
        "PetTarget lifecycle compile count")
end

local function testPetTargetUnavailableBackendUsesInertAuraShells()
    local harness = makeEventRuntimeHarness(true, false)
    local buffs = harness.buffs
    local debuffs = harness.debuffs

    assertEqual(#harness.controllers, 0,
        "unavailable-backend PetTarget native controller count")
    assertEqual(#harness.compiles, 0,
        "unavailable-backend PetTarget native compile count")
    assertEqual(#harness.legacyConstructions, 0,
        "unavailable-backend PetTarget legacy builder count")
    assertEqual(buffs._nativeAuraUnavailable, true,
        "unavailable-backend PetTarget buffs shell")
    assertEqual(buffs:GetObjectType(), "Frame",
        "unavailable-backend PetTarget buffs object type")
    assertEqual(buffs.name, "BFI_PetTarget_Buffs",
        "unavailable-backend PetTarget buffs name")
    assertEqual(buffs.auraFilter, "HELPFUL",
        "unavailable-backend PetTarget buffs filter")
    assertEqual(buffs.hasSubFrame, nil,
        "unavailable-backend PetTarget buffs subframe flag")
    assertEqual(buffs.alpha, 0,
        "unavailable-backend PetTarget buffs alpha")
    assertEqual(buffs.allPoints, harness.root,
        "unavailable-backend PetTarget buffs anchor")
    assertEqual(buffs.shown, false,
        "unavailable-backend PetTarget buffs visibility")
    assertEqual(buffs.enabled, false,
        "unavailable-backend PetTarget buffs enabled state")
    assertEqual(buffs:GetNativeAuraState().state, "UNAVAILABLE",
        "unavailable-backend PetTarget buffs runtime state")
    assertEqual(debuffs._nativeAuraUnavailable, true,
        "unavailable-backend PetTarget debuffs shell")
    assertEqual(debuffs:GetObjectType(), "Frame",
        "unavailable-backend PetTarget debuffs object type")
    assertEqual(debuffs.name, "BFI_PetTarget_Debuffs",
        "unavailable-backend PetTarget debuffs name")
    assertEqual(debuffs.auraFilter, "HARMFUL",
        "unavailable-backend PetTarget debuffs filter")
    assertEqual(debuffs.hasSubFrame, nil,
        "unavailable-backend PetTarget debuffs subframe flag")
    assertEqual(debuffs.alpha, 0,
        "unavailable-backend PetTarget debuffs alpha")
    assertEqual(debuffs.allPoints, harness.root,
        "unavailable-backend PetTarget debuffs anchor")
    assertEqual(debuffs.shown, false,
        "unavailable-backend PetTarget debuffs visibility")
    assertEqual(debuffs.enabled, false,
        "unavailable-backend PetTarget debuffs enabled state")
    assertEqual(debuffs:GetNativeAuraState().state, "UNAVAILABLE",
        "unavailable-backend PetTarget debuffs runtime state")

    harness.root.hooks.OnShow(harness.root)
    assertEqual(buffs.enabled, false,
        "unavailable-backend PetTarget buffs show state")
    assertEqual(debuffs.enabled, false,
        "unavailable-backend PetTarget debuffs show state")
    assertEqual(#harness.controllers, 0,
        "unavailable-backend PetTarget show controller count")
    assertEqual(#harness.compiles, 0,
        "unavailable-backend PetTarget show compile count")
end

local function testShippedPetTargetPresetBounds()
    local UF = makePresetCompiler()

    local function assertAllAuraDescriptor(
        descriptor,
        baseFilter,
        maximum,
        width,
        height,
        message
    )
        assertTrue(descriptor, message .. " descriptor")
        assertEqual(descriptor.migrationReady, true,
            message .. " migration readiness")
        assertEqual(descriptor.metrics.groupCount, 1,
            message .. " group count")
        assertEqual(descriptor.metrics.legacyMaxFrameCount, maximum,
            message .. " legacy capacity")
        assertEqual(descriptor.metrics.nativeVisibleCapacity, maximum,
            message .. " native capacity")
        assertEqual(descriptor.metrics.initialRestrictedButtonCount, 10,
            message .. " initial native buttons")
        assertEqual(
            descriptor.metrics.freshContainerRestrictedButtonCountCeiling,
            math.ceil(maximum / 10) * 10,
            message .. " native button ceiling"
        )
        assertEqual(descriptor.completeSpec.holder.width, width,
            message .. " holder width")
        assertEqual(descriptor.completeSpec.holder.height, height,
            message .. " holder height")
        assertEqual(
            descriptor.completeSpec.groups[1].filterString,
            baseFilter,
            message .. " all-auras filter"
        )
        assertEqual(descriptor.visibility.requiresVisible, false,
            message .. " visibility gate")
        assertEqual(descriptor.visibility.requiresAssist, false,
            message .. " assist gate")
    end

    for _, id in ipairs({"default1", "default2"}) do
        local indicators = UF.GetPreset(id).pettarget.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "pettarget",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "pettarget",
            "HARMFUL",
            indicators.debuffs
        )

        assertEqual(buffError, nil, id .. " buffs compile error")
        assertEqual(debuffError, nil, id .. " debuffs compile error")
        assertEqual(indicators.buffs.enabled, false,
            id .. " default buffs state")
        assertEqual(indicators.debuffs.enabled, false,
            id .. " default debuffs state")
        assertAllAuraDescriptor(
            buffs,
            "HELPFUL",
            22,
            219,
            39,
            id .. " buffs"
        )
        assertAllAuraDescriptor(
            debuffs,
            "HARMFUL",
            3,
            59,
            19,
            id .. " debuffs"
        )
    end
end

testPetTargetActivationAndConstructionOrder()
testPetTargetDisableAndReenableLifecycle()
testPetTargetConfigModeGuardsAreLocal()
testPetTargetDefaultDisabledDoesNotBuild()
testPetTargetUnitEventsAndTicksRefreshNativeRuntime()
testPetTargetRuntimeLifecycleHasNoGrowth()
testPetTargetUnavailableBackendUsesInertAuraShells()
testShippedPetTargetPresetBounds()

print("unit_frame_pettarget_native_aura_test.lua: ok")
