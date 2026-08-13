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

local function findIndicator(indicators, name)
    for _, indicator in ipairs(indicators) do
        if type(indicator) == "table" and indicator[2] == name then
            return indicator
        end
    end
end

local function makeHarness()
    local harness = {
        callbacks = {},
        configAdds = {},
        configRemoves = {},
        events = {},
        frames = {},
        legacyConstructions = {},
        nativeConstructions = {},
        partitionConstructions = {},
        setupCalls = {},
    }
    local UF = {
        config = {
            general = {
                enabled = true,
            },
            target = {
                general = {
                    enabled = true,
                },
                indicators = {},
            },
        },
    }
    local AF = {
        UIParent = {},
    }

    local function record(name, ...)
        harness.events[#harness.events + 1] = {
            name = name,
            args = {...},
        }
    end

    function AF.CreateMover()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function AF.UpperFirst(value)
        return value:sub(1, 1):upper() .. value:sub(2)
    end

    function UF.AddToConfigMode(group, frame)
        harness.configAdds[#harness.configAdds + 1] = {
            group = group,
            frame = frame,
        }
    end

    function UF.RemoveFromConfigMode(group, frame)
        harness.configRemoves[#harness.configRemoves + 1] = {
            group = group,
            frame = frame,
        }
        record("config.remove", group, frame)
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
        record("legacy.create", indicator)
        return indicator
    end

    function UF.CreateNativeAuras(parent, name, auraFilter)
        local indicator = newIndicator(
            parent,
            name,
            auraFilter,
            "nativeAuras"
        )
        harness.nativeConstructions[
            #harness.nativeConstructions + 1
        ] = indicator
        record("native.create", indicator)
        return indicator
    end

    function UF.CreateNativePartitionedAuras(
        parent,
        name,
        auraFilter,
        hasSubFrame
    )
        local indicator = newIndicator(
            parent,
            name,
            auraFilter,
            "nativePartitionedAuras"
        )
        indicator.hasSubFrame = hasSubFrame
        harness.partitionConstructions[
            #harness.partitionConstructions + 1
        ] = indicator
        record("partition.create", indicator)
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
        "CreateLeaderIcon",
        "CreateLeaderText",
        "CreateLevelText",
        "CreateTargetCounter",
        "CreateRangeText",
        "CreateStatusTimer",
        "CreateStatusIcon",
        "CreateRaidIcon",
        "CreateRoleIcon",
        "CreateFactionIcon",
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
        end

        function frame:Show()
            self.shown = true
            record("frame.show", self)
        end

        if name ~= "BFIUnitFrameParent" then
            harness.frames[#harness.frames + 1] = frame
        end
        return frame
    end

    local function RegisterUnitWatch(frame)
        frame.unitWatchRegistered = true
        record("watch.register", frame)
    end

    local function UnregisterUnitWatch(frame)
        frame.unitWatchRegistered = false
        record("watch.unregister", frame)
    end

    local function UnitWatchRegistered(frame)
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
        TARGET = "Target",
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
                "unexpected Target integration global: "
                    .. tostring(key),
                2
            )
        end,
    })

    local commonChunk, commonError =
        loadfile("Modules/UnitFrames/Common.lua")
    assertTrue(commonChunk, commonError)
    setfenv(commonChunk, environment)
    commonChunk("BFInfinite", BFI)

    local CreateIndicators = UF.CreateIndicators
    function UF.CreateIndicators(frame, indicators)
        harness.indicatorDescriptors = indicators
        return CreateIndicators(frame, indicators)
    end

    function UF.CreatePreviewRect(frame)
        frame.previewCreated = true
    end

    function UF.SetupUnitFrame(frame, config, indicators, skip)
        harness.setupCalls[#harness.setupCalls + 1] = {
            config = config,
            frame = frame,
            indicators = indicators,
            skip = skip,
        }
        frame.enabled = true
        record("setup", frame, skip)
    end

    local DisableIndicators = UF.DisableIndicators
    function UF.DisableIndicators(frame)
        harness.disableCount = (harness.disableCount or 0) + 1
        DisableIndicators(frame)
    end

    local targetChunk, targetError =
        loadfile("Modules/UnitFrames/Units/Target.lua")
    assertTrue(targetChunk, targetError)
    setfenv(targetChunk, environment)
    targetChunk("BFInfinite", BFI)

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

    function harness:EventIndex(name)
        for index, event in ipairs(self.events) do
            if event.name == name then
                return index
            end
        end
    end

    return harness
end

local function testConstructionAndIdentity()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "Target update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    update(nil, "unitFrames", "target", true)

    local frame = harness.frames[1]
    local buffs =
        findIndicator(harness.indicatorDescriptors, "buffs")
    local debuffs =
        findIndicator(harness.indicatorDescriptors, "debuffs")

    assertEqual(#harness.frames, 1, "Target frame creation count")
    assertEqual(buffs[1], "nativeAuras", "Target buffs builder")
    assertEqual(buffs[3], "HELPFUL", "Target buffs filter")
    assertEqual(debuffs[1], "nativePartitionedAuras",
        "Target debuffs builder")
    assertEqual(debuffs[3], "HARMFUL", "Target debuffs filter")
    assertEqual(debuffs[4], true, "Target debuffs sub-frame flag")
    assertEqual(#harness.legacyConstructions, 0,
        "Target legacy construction count")
    assertEqual(#harness.nativeConstructions, 1,
        "Target native construction count")
    assertEqual(#harness.partitionConstructions, 1,
        "Target partition construction count")
    assertEqual(
        harness.partitionConstructions[1],
        frame.indicators.debuffs,
        "Target partition controller"
    )
    assertEqual(
        harness.nativeConstructions[1],
        frame.indicators.buffs,
        "Target native Buffs controller"
    )
    assertEqual(frame.indicators.buffs.builder, "nativeAuras",
        "Target native Buffs construction")
    assertEqual(
        harness.nativeConstructions[1].auraFilter,
        "HELPFUL",
        "Target native Buffs construction filter"
    )
    assertEqual(
        harness.partitionConstructions[1].auraFilter,
        "HARMFUL",
        "Target partition construction filter"
    )
    assertEqual(
        harness.partitionConstructions[1].hasSubFrame,
        true,
        "Target partition construction sub-frame flag"
    )
    assertTrue(
        harness:EventIndex("native.create")
            < harness:EventIndex("setup"),
        "Target native Buffs controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("partition.create")
            < harness:EventIndex("setup"),
        "Target partition controller was not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "Target unit watch registered before setup"
    )
    assertEqual(harness.setupCalls[1].skip, false,
        "first Target setup skipped indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Target initial unit-watch registration")
    assertEqual(frame.attributes.unit, "target",
        "Target secure unit")
    assertEqual(frame.unit, "target", "Target runtime unit")
    assertEqual(frame._updateOnPlayerTargetChanged, true,
        "Target target-change opt-in")
    assertEqual(frame._skipDataCache, true,
        "Target data-cache flag")
    assertEqual(frame.unitWatchRegistered, true,
        "Target unit-watch state")
    assertEqual(harness.configAdds[1].group, "target",
        "Target config-mode group")
end

local function testWatchAndSkipLifecycle()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "target")
    local frame = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "target", 1)
    assertEqual(harness.setupCalls[2].skip, false,
        "Target numeric skip normalization")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Target numeric update duplicated unit watch")

    harness:ClearEvents()
    update(nil, "unitFrames", "target", true)
    assertEqual(harness.setupCalls[3].skip, true,
        "Target repeated skip flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Target repeated unit-watch registration")

    harness.UF.config.target.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "target")
    assertEqual(harness:CountEvents("watch.unregister"), 1,
        "Target disable unit-watch unregister")
    assertEqual(frame.enabled, false, "Target disabled state")
    assertEqual(frame.shown, false, "Target disabled visibility")

    harness:ClearEvents()
    update(nil, "unitFrames", "target")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "Target repeated disable unit-watch unregister")

    harness.UF.config.target.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "target", true)
    assertEqual(harness.setupCalls[4].skip, false,
        "Target re-enable skipped disabled indicators")
    assertEqual(harness:CountEvents("watch.register"), 1,
        "Target re-enable unit-watch registration")
    assertEqual(#harness.partitionConstructions, 1,
        "Target re-enable rebuilt partition controller")
    assertEqual(#harness.nativeConstructions, 1,
        "Target re-enable rebuilt native Buffs controller")
    assertEqual(frame.enabled, true, "Target re-enabled state")
    assertEqual(frame.unitWatchRegistered, true,
        "Target re-enabled unit watch")
    assertEqual(#harness.configRemoves, 0,
        "Target disable removed config-mode registration")
end

local function testConfigModeReenable()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "target")
    local frame = harness.frames[1]
    frame.inConfigMode = true
    frame.unitWatchRegistered = false
    harness.UF.configModeEnabled = true

    local indicatorCount = 0
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "target", true)
    assertEqual(harness:CountEvents("watch.register"), 0,
        "enabled Target config mode registered unit watch")

    harness.UF.config.target.general.enabled = false
    update(nil, "unitFrames", "target")
    assertEqual(frame.inConfigMode, true,
        "Target disable exited config mode")
    assertEqual(frame.shown, false,
        "Target disabled config-mode visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        indicatorCount,
        "Target disable indicator preview exits"
    )
    assertEqual(#harness.configRemoves, 0,
        "Target disable removed Target from config mode")

    harness.UF.config.target.general.enabled = true
    update(nil, "unitFrames", "target", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "Target config-mode re-enable skipped indicators")
    assertEqual(frame.shown, true,
        "Target config-mode re-enable visibility")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        indicatorCount,
        "Target config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Target config-mode lifecycle registered unit watch")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "Target re-enabled indicator preview state")
    end
    assertEqual(#harness.nativeConstructions, 1,
        "Target config-mode lifecycle rebuilt native Buffs controller")
    assertEqual(#harness.partitionConstructions, 1,
        "Target config-mode lifecycle rebuilt partition controller")
end

testConstructionAndIdentity()
testWatchAndSkipLifecycle()
testConfigModeReenable()

print("unit_frame_target_native_aura_test.lua: ok")
