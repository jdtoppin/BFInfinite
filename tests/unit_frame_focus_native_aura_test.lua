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

local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then return true end
    end
    return false
end

local function makeHarness()
    local harness = {
        callbacks = {},
        configMode = {},
        createIndicatorCalls = {},
        disableCalls = {},
        events = {},
        frames = {},
        nativeConstructions = {},
        setupCalls = {},
    }
    local UF = {
        config = {
            general = {
                enabled = true,
            },
            focus = {
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
        assertEqual(event, "BFI_UpdateModule", "registered callback event")
        harness.callbacks[event] = callback
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
            if UF.configModeEnabled and indicator.DisableConfigMode then
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
        return newIndicator(parent, name, auraFilter, "auras")
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
        "CreateRangeText",
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
            error("unexpected Focus integration global: " .. tostring(key), 2)
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

    local chunk, loadError = loadfile("Modules/UnitFrames/Units/Focus.lua")
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
            error("unexpected preset compiler global: " .. tostring(key), 2)
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

local function testFocusActivationAndConstructionOrder()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "Focus update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "focus")
    update(nil, "unitFrames", "target")
    assertEqual(#harness.frames, 0, "unrelated update frame allocation")

    update(nil, "unitFrames", "focus", true)
    assertEqual(#harness.frames, 1, "Focus frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "Focus indicator creation count")
    assertEqual(#harness.nativeConstructions, 1,
        "Focus native controller prebuild count")
    assertEqual(#harness.setupCalls, 1, "Focus setup count")
    assertEqual(harness.setupCalls[1].skip, false,
        "first Focus setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Focus initial unit-watch registration")
    assertTrue(
        harness:EventIndex("native.create")
            < harness:EventIndex("setup"),
        "Focus native controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "Focus unit watch registered before setup"
    )

    local frame = harness.frames[1]
    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffs = findIndicator(descriptors, "buffs")
    local debuffs = findIndicator(descriptors, "debuffs")

    assertEqual(frame.name, "BFI_Focus", "Focus frame name")
    assertEqual(frame.frameType, "Button", "Focus frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "Focus frame template")
    assertEqual(frame.parent, harness.UF.Parent, "Focus frame parent")
    assertEqual(frame.attributes.unit, "focus", "Focus secure unit")
    assertEqual(frame.unit, "focus", "Focus runtime unit")
    assertEqual(frame._skipDataCache, true, "Focus data-cache flag")
    assertEqual(frame.unitWatchRegistered, true,
        "Focus unit-watch state")
    assertTrue(frame.previewCreated, "Focus preview rectangle")
    assertEqual(harness.configMode[1].group, "focus",
        "Focus config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "Focus config-mode frame")
    assertEqual(buffs[1], "auras", "Focus buffs legacy builder")
    assertEqual(buffs[3], "HELPFUL", "Focus buffs filter")
    assertEqual(debuffs[1], "nativeAuras",
        "Focus debuffs native builder")
    assertEqual(debuffs[3], "HARMFUL", "Focus debuffs filter")
    assertEqual(harness.nativeConstructions[1],
        frame.indicators.debuffs, "Focus native controller")
    assertEqual(frame.indicators.debuffs.root, frame,
        "Focus native controller parent")
    assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
        "Focus native controller filter")
    assertEqual(frame.indicators.buffs.builder, "auras",
        "Focus legacy buffs construction")
end

local function testFocusDisableAndReenableLifecycle()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "focus")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "focus", true)
    assertEqual(#harness.frames, 1, "Focus frame recreated on update")
    assertEqual(#harness.setupCalls, 2, "Focus repeated setup count")
    assertEqual(harness.setupCalls[2].skip, true,
        "enabled Focus skip-indicator flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate Focus unit-watch registration")

    harness.UF.config.focus.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focus")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "Focus unit-watch unregister count")
    assertEqual(#harness.disableCalls, 1,
        "Focus indicator disable count")
    assertEqual(frame.enabled, false, "Focus disabled state")
    assertEqual(frame.shown, false, "Focus disabled visibility")
    assertEqual(frame.unitWatchRegistered, false,
        "Focus disabled unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "focus")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "Focus repeated disable unit-watch count")

    harness.UF.config.focus.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "focus", true)
    assertEqual(#harness.setupCalls, 3, "Focus re-enable setup count")
    assertEqual(harness.setupCalls[3].skip, false,
        "Focus re-enable skipped disabled indicators")
    assertEqual(#harness.nativeConstructions, 1,
        "Focus re-enable native construction count")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Focus re-enable unit-watch registration")
    assertEqual(frame.enabled, true, "Focus re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "Focus re-enabled unit watch")
end

local function testFocusConfigModeGuardsAreLocal()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "focus")
    local frame = harness.frames[1]

    harness.UF.configModeEnabled = true
    frame.unitWatchRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focus")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "unrelated config mode suppressed Focus watch")

    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "focus", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Focus config mode registered unit watch")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled Focus repeated indicator preview entry")

    harness.UF.config.focus.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "focus")
    assertEqual(frame.shown, false,
        "disabled Focus config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "disabled Focus indicator preview exits"
    )

    harness.UF.config.focus.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "focus", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "Focus config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "Focus config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "Focus config-mode preview show count")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "Focus config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Focus config-mode re-enable unit watch")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled Focus indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled Focus indicator preview count")
    end
end

local function testShippedFocusPresetBounds()
    local UF = makePresetCompiler()

    for _, id in ipairs({"default1", "default2"}) do
        local preset = UF.GetPreset(id)
        local indicators = preset.focus.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "focus",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "focus",
            "HARMFUL",
            indicators.debuffs
        )

        assertTrue(buffs, id .. " buffs compile error: " .. tostring(buffError))
        assertTrue(debuffs,
            id .. " debuffs compile error: " .. tostring(debuffError))
        assertEqual(buffError, nil, id .. " buffs compile error")
        assertEqual(debuffError, nil, id .. " debuffs compile error")
        assertEqual(indicators.buffs.enabled, true,
            id .. " default buffs state")
        assertEqual(indicators.debuffs.enabled, true,
            id .. " default debuffs state")

        assertEqual(buffs.metrics.groupCount, 5,
            id .. " buffs group count")
        assertEqual(buffs.metrics.nativeVisibleCapacity, 15,
            id .. " buffs native capacity")
        assertEqual(buffs.metrics.initialRestrictedButtonCount, 50,
            id .. " buffs initial native buttons")
        assertEqual(
            buffs.metrics.freshContainerRestrictedButtonCountCeiling,
            50,
            id .. " buffs native button ceiling"
        )
        assertEqual(buffs.completeSpec.holder.width, 59,
            id .. " buffs holder width")
        assertEqual(buffs.completeSpec.holder.height, 99,
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
        assertTrue(contains(
            debuffs.diagnostics,
            "AURA_TYPE_COLOR_SOURCE_RULES_IGNORED"
        ), id .. " debuffs source-color diagnostic")
    end
end

testFocusActivationAndConstructionOrder()
testFocusDisableAndReenableLifecycle()
testFocusConfigModeGuardsAreLocal()
testShippedFocusPresetBounds()

print("unit_frame_focus_native_aura_test.lua: ok")
