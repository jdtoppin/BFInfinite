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

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local function makeHarness(nativeBackendAvailable)
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
            boss = {
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

    function AF.CreateMover(frame, label, unitLabel)
        harness.mover = {
            frame = frame,
            label = label,
            unitLabel = unitLabel,
        }
    end

    function AF.AddToPixelUpdater_Auto(frame, callback, combatSafeOnly)
        harness.pixelUpdater = {
            frame = frame,
            callback = callback,
            combatSafeOnly = combatSafeOnly,
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

    local function SetupUnitGroup(group, config, indicators, skip)
        harness.setupCalls[#harness.setupCalls + 1] = {
            group = group,
            config = config,
            indicators = indicators,
            skip = skip,
        }
        for _, frame in ipairs(group) do
            frame.enabled = true
        end
        record("setup", group, skip)
    end

    local function DisableIndicators(frame)
        harness.disableCalls[#harness.disableCalls + 1] = frame
        frame.enabled = false
        for _, indicator in pairs(frame.indicators) do
            if harness.UF.configModeEnabled
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
        "CreateRaidIcon",
        "CreateTargetHighlight",
        "CreateMouseoverHighlight",
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

        function frame:Hide()
            self.shown = false
            self.hideCount = (self.hideCount or 0) + 1
        end

        function frame:Show()
            self.shown = true
            self.showCount = (self.showCount or 0) + 1
            record("frame.show", self)
        end

        function frame:IsVisible()
            return self.shown
        end

        function frame:SetAllPoints()
        end

        function frame:SetFrameStrata()
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

    local function RegisterAttributeDriver(frame, key, value)
        frame.driverRegistered = true
        frame.registerDriverCount = (frame.registerDriverCount or 0) + 1
        record("driver.register", frame, key, value)
    end

    local function UnregisterAttributeDriver(frame)
        frame.driverRegistered = false
        frame.unregisterDriverCount =
            (frame.unregisterDriverCount or 0) + 1
        record("driver.unregister", frame)
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
        BOSS = "Boss",
        CreateFrame = CreateFrame,
        RegisterAttributeDriver = RegisterAttributeDriver,
        RegisterUnitWatch = RegisterUnitWatch,
        UnitWatchRegistered = UnitWatchRegistered,
        UnregisterAttributeDriver = UnregisterAttributeDriver,
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
            error("unexpected Boss integration global: " .. tostring(key), 2)
        end,
    })

    local commonChunk, commonLoadError =
        loadfile("Modules/UnitFrames/Common.lua")
    assertTrue(commonChunk, commonLoadError)
    setfenv(commonChunk, environment)
    commonChunk("BFInfinite", BFI)

    -- Exercise Common.lua's real descriptor-to-builder dispatch while keeping
    -- layout and indicator configuration isolated for this Boss lifecycle
    -- harness.
    local CreateIndicators = UF.CreateIndicators
    function UF.CreateIndicators(frame, indicatorDescriptors)
        harness.createIndicatorCalls[
            #harness.createIndicatorCalls + 1
        ] = {
            frame = frame,
            indicators = indicatorDescriptors,
        }
        frame.createdIndicators = indicatorDescriptors
        return CreateIndicators(frame, indicatorDescriptors)
    end
    UF.CreatePreviewRect = CreatePreviewRect
    UF.SetupUnitGroup = SetupUnitGroup
    UF.DisableIndicators = DisableIndicators

    local chunk, loadError = loadfile("Modules/UnitFrames/Units/Boss.lua")
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

local function testBossActivationAndConstructionOrder()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "Boss update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")
    assertEqual(#harness.nativeConstructions, 0,
        "module-load native aura construction")

    update(nil, "nameplates", "boss")
    update(nil, "unitFrames", "raid")
    assertEqual(#harness.frames, 0, "unrelated update frame allocation")

    update(nil, "unitFrames", "boss", false)
    assertEqual(#harness.frames, 9, "Boss frame creation count")
    assertEqual(#harness.createIndicatorCalls, 8,
        "Boss indicator creation count")
    assertEqual(#harness.nativeConstructions, 16,
        "Boss native controller prebuild count")
    assertEqual(#harness.legacyConstructions, 0,
        "Boss native path legacy construction count")
    assertEqual(#harness.setupCalls, 1, "Boss setup count")
    assertEqual(harness:CountEvents("watch.register"), 8,
        "Boss initial unit-watch registrations")
    assertEqual(harness:CountEvents("driver.register"), 1,
        "Boss initial driver registration")
    assertTrue(
        harness:EventIndex("native.create", 16)
            < harness:EventIndex("setup"),
        "Boss native controllers were not prebuilt before setup"
    )
    assertTrue(
        harness:EventIndex("setup")
            < harness:EventIndex("watch.register"),
        "Boss unit watch registered before setup"
    )
    assertTrue(
        harness:EventIndex("watch.register", 8)
            < harness:EventIndex("driver.register"),
        "Boss driver registered before child watches"
    )

    local boss = harness.frames[1]
    assertEqual(boss.frameType, "Frame", "Boss container type")
    assertEqual(boss.template, "SecureFrameTemplate",
        "Boss container template")
    assertEqual(boss.parent, harness.AF.UIParent, "Boss container parent")
    assertEqual(boss.driverKey, "state-visibility", "Boss driver key")
    assertEqual(boss.driverValue, "[@boss1,exists] show;hide",
        "Boss driver value")
    assertEqual(boss.enabled, true, "Boss container enabled state")
    assertEqual(harness.configMode[1].group, "boss.container",
        "Boss container config-mode group")
    assertEqual(harness.pixelUpdater.frame, boss,
        "Boss pixel-updater frame")
    assertEqual(harness.pixelUpdater.combatSafeOnly, true,
        "Boss pixel-updater combat policy")

    for index = 1, 8 do
        local frame = boss[index]
        local descriptors =
            harness.createIndicatorCalls[index].indicators
        local buffs = findIndicator(descriptors, "buffs")
        local debuffs = findIndicator(descriptors, "debuffs")

        assertEqual(frame, harness.frames[index + 1],
            "Boss child order " .. index)
        assertEqual(frame.name, "BFI_Boss" .. index,
            "Boss child name " .. index)
        assertEqual(frame.attributes.unit, "boss" .. index,
            "Boss child unit " .. index)
        assertEqual(frame.template, "BFIUnitButtonTemplate",
            "Boss child template " .. index)
        assertEqual(frame.parent, boss, "Boss child parent " .. index)
        assertEqual(frame.unitWatchRegistered, true,
            "Boss child unit watch " .. index)
        assertEqual(
            harness.nativeConstructions[(index * 2) - 1],
            frame.indicators.buffs,
            "Boss child native buffs controller " .. index
        )
        assertEqual(
            harness.nativeConstructions[index * 2],
            frame.indicators.debuffs,
            "Boss child native debuffs controller " .. index
        )
        assertEqual(frame.indicators.buffs.root, frame,
            "Boss native buffs controller parent " .. index)
        assertEqual(frame.indicators.buffs.auraFilter, "HELPFUL",
            "Boss native buffs controller filter " .. index)
        assertEqual(frame.indicators.debuffs.root, frame,
            "Boss native debuffs controller parent " .. index)
        assertEqual(frame.indicators.debuffs.auraFilter, "HARMFUL",
            "Boss native debuffs controller filter " .. index)
        assertEqual(frame.indicators.buffs.builder, "nativeAuras",
            "Boss native buffs construction " .. index)
        assertEqual(frame.indicators.debuffs.builder, "nativeAuras",
            "Boss native debuffs construction " .. index)
        assertTrue(frame.previewCreated,
            "Boss child preview rectangle " .. index)
        assertEqual(harness.configMode[index + 1].group, "boss",
            "Boss child config-mode group " .. index)
        assertEqual(harness.configMode[index + 1].frame, frame,
            "Boss child config-mode frame " .. index)
        assertEqual(buffs[1], "nativeAuras",
            "Boss buffs native builder " .. index)
        assertEqual(buffs[3], "HELPFUL",
            "Boss buffs filter " .. index)
        assertEqual(debuffs[1], "nativeAuras",
            "Boss debuffs native builder " .. index)
        assertEqual(debuffs[3], "HARMFUL",
            "Boss debuffs filter " .. index)
    end

    local common = readFile("Modules/UnitFrames/Common.lua")
    assertTrue(
        common:find("nativeAuras%s*=%s*UF%.CreateNativeAuras") ~= nil,
        "native aura builder is not wired to the compatibility selector"
    )
end

local function testBossDisableAndReenableLifecycle()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "boss", false)
    local boss = harness.frames[1]

    harness:ClearEvents()
    update(nil, "unitFrames", "boss", true)
    assertEqual(#harness.frames, 9, "Boss frame recreated on update")
    assertEqual(#harness.nativeConstructions, 16,
        "Boss repeated-update native construction count")
    assertEqual(#harness.setupCalls, 2, "Boss repeated setup count")
    assertEqual(harness.setupCalls[2].skip, true,
        "enabled Boss skip-indicator flag")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "duplicate Boss unit-watch registrations")

    harness.UF.config.boss.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "boss")
    assertEqual(harness:CountEvents("driver.unregister"), 1,
        "Boss driver unregister count")
    assertEqual(harness:CountEvents("watch.unregister"), 8,
        "Boss unit-watch unregister count")
    assertEqual(#harness.disableCalls, 8,
        "Boss indicator disable count")
    assertEqual(boss.enabled, false, "Boss disabled state")
    assertEqual(boss.hideCount, 1, "Boss hide count")
    for index = 1, 8 do
        assertEqual(boss[index].unitWatchRegistered, false,
            "disabled Boss child watch " .. index)
        assertEqual(boss[index].enabled, false,
            "disabled Boss child state " .. index)
    end

    harness:ClearEvents()
    update(nil, "unitFrames", "boss")
    assertEqual(harness:CountEvents("watch.unregister"), 0,
        "disabled Boss repeated unit-watch unregister count")

    harness.UF.config.boss.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "boss", true)
    assertEqual(#harness.frames, 9, "Boss frame recreated on re-enable")
    assertEqual(#harness.nativeConstructions, 16,
        "Boss re-enable native construction count")
    assertEqual(#harness.setupCalls, 3, "Boss re-enable setup count")
    assertEqual(harness.setupCalls[3].skip, false,
        "Boss re-enable skipped disabled indicators")
    assertEqual(harness:CountEvents("watch.register"), 8,
        "Boss re-enable unit-watch registrations")
    assertEqual(harness:CountEvents("driver.register"), 1,
        "Boss re-enable driver registration")
    assertEqual(boss.enabled, true, "Boss re-enabled state")
    for index = 1, 8 do
        assertEqual(boss[index].unitWatchRegistered, true,
            "re-enabled Boss child watch " .. index)
        assertEqual(boss[index].enabled, true,
            "re-enabled Boss child state " .. index)
    end
end

local function testBossLegacyAuraFallback()
    local harness = makeHarness(false)
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "boss")
    local boss = harness.frames[1]

    assertEqual(#harness.nativeConstructions, 0,
        "12.0.7 Boss native construction count")
    assertEqual(#harness.legacyConstructions, 16,
        "12.0.7 Boss legacy construction count")
    for index = 1, 8 do
        assertEqual(boss[index].indicators.buffs.builder, "auras",
            "12.0.7 Boss buffs fallback " .. index)
        assertEqual(boss[index].indicators.buffs.auraFilter, "HELPFUL",
            "12.0.7 Boss buffs filter " .. index)
        assertEqual(boss[index].indicators.debuffs.builder, "auras",
            "12.0.7 Boss debuffs fallback " .. index)
        assertEqual(boss[index].indicators.debuffs.auraFilter, "HARMFUL",
            "12.0.7 Boss debuffs filter " .. index)
    end

    update(nil, "unitFrames", "boss", true)
    harness.UF.config.boss.general.enabled = false
    update(nil, "unitFrames", "boss")
    harness.UF.config.boss.general.enabled = true
    update(nil, "unitFrames", "boss", true)
    assertEqual(#harness.frames, 9,
        "12.0.7 Boss fallback frame growth")
    assertEqual(#harness.legacyConstructions, 16,
        "12.0.7 Boss fallback indicator growth")
end

local function testBossConfigModeGuardsAreLocal()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "boss")
    local boss = harness.frames[1]

    -- Config mode can be globally enabled for another frame type. Boss must
    -- continue to own its normal unit watches and visibility driver.
    harness.UF.configModeEnabled = true
    for index = 1, 8 do
        boss[index].unitWatchRegistered = false
    end
    boss.driverRegistered = false
    harness:ClearEvents()
    update(nil, "unitFrames", "boss")
    assertEqual(harness:CountEvents("watch.register"), 8,
        "unrelated config mode suppressed Boss watches")
    assertEqual(harness:CountEvents("driver.register"), 1,
        "unrelated config mode suppressed Boss driver")

    -- Boss config mode itself owns visibility and temporarily rewrites units.
    boss.inConfigMode = true
    boss.driverRegistered = false
    local configModeIndicatorCount = 0
    for index = 1, 8 do
        boss[index].inConfigMode = true
        boss[index].unitWatchRegistered = false
        for _, indicator in pairs(boss[index].indicators) do
            indicator:EnableConfigMode()
            configModeIndicatorCount = configModeIndicatorCount + 1
        end
    end
    harness:ClearEvents()
    update(nil, "unitFrames", "boss")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Boss config mode registered unit watches")
    assertEqual(harness:CountEvents("driver.register"), 0,
        "Boss config mode registered visibility driver")
    assertEqual(harness:CountEvents("indicator.enable-config"), 0,
        "enabled Boss repeated indicator preview entry")

    -- Disabling hides the container. Re-enabling while Boss config mode owns
    -- visibility must restore the preview without secure registrations.
    harness.UF.config.boss.general.enabled = false
    harness:ClearEvents()
    update(nil, "unitFrames", "boss")
    assertEqual(boss.shown, false,
        "disabled Boss config-mode preview visibility")
    assertEqual(
        harness:CountEvents("indicator.disable-config"),
        configModeIndicatorCount,
        "disabled Boss indicator preview exits"
    )
    for index = 1, 8 do
        for _, indicator in pairs(boss[index].indicators) do
            assertEqual(indicator.configMode, false,
                "disabled Boss indicator preview state")
        end
    end

    harness.UF.config.boss.general.enabled = true
    harness:ClearEvents()
    update(nil, "unitFrames", "boss", true)
    assertEqual(harness.setupCalls[#harness.setupCalls].skip, false,
        "Boss config-mode re-enable skipped disabled indicators")
    assertEqual(boss.shown, true,
        "Boss config-mode re-enable preview visibility")
    assertEqual(harness:CountEvents("frame.show"), 1,
        "Boss config-mode preview show count")
    assertEqual(
        harness:CountEvents("indicator.enable-config"),
        configModeIndicatorCount,
        "Boss config-mode re-enable indicator previews"
    )
    assertEqual(harness:CountEvents("watch.register"), 0,
        "Boss config-mode re-enable unit watches")
    assertEqual(harness:CountEvents("driver.register"), 0,
        "Boss config-mode re-enable visibility driver")
    assertEqual(#harness.nativeConstructions, 16,
        "Boss config-mode native construction count")
    for index = 1, 8 do
        for _, indicator in pairs(boss[index].indicators) do
            assertEqual(indicator.configMode, true,
                "re-enabled Boss indicator preview state")
            assertEqual(indicator.enableConfigModeCount, 2,
                "re-enabled Boss indicator preview count")
        end
    end
end

local function testShippedBossPresetBounds()
    local UF = makePresetCompiler()

    for _, id in ipairs({"default1", "default2"}) do
        local preset = UF.GetPreset(id)
        local indicators = preset.boss.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "boss1",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "boss1",
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

        assertEqual(buffs.metrics.groupCount, 4,
            id .. " buffs group count")
        assertEqual(buffs.migrationReady, true,
            id .. " buffs migration readiness")
        assertEqual(buffs.metrics.legacyMaxFrameCount, 3,
            id .. " buffs legacy capacity")
        assertEqual(buffs.metrics.nativeVisibleCapacity, 12,
            id .. " buffs native capacity")
        assertEqual(buffs.metrics.initialRestrictedButtonCount, 40,
            id .. " buffs initial native buttons")
        assertEqual(
            buffs.metrics.freshContainerRestrictedButtonCountCeiling,
            40,
            id .. " buffs native button ceiling"
        )
        assertEqual(buffs.completeSpec.holder.width, 59,
            id .. " buffs holder width")
        assertEqual(buffs.completeSpec.holder.height, 79,
            id .. " buffs holder height")
        assertEqual(buffs.completeSpec.groups[1].filterString,
            "HELPFUL|PLAYER", id .. " buffs player filter")
        assertEqual(buffs.completeSpec.groups[2].filterString,
            "HELPFUL|RAID_IN_COMBAT|!PLAYER",
            id .. " buffs raid filter")
        assertEqual(buffs.completeSpec.groups[3].filterString,
            "HELPFUL|BIG_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT",
            id .. " buffs big-defensive filter")
        assertEqual(buffs.completeSpec.groups[4].filterString,
            "HELPFUL|EXTERNAL_DEFENSIVE|!PLAYER|!RAID_IN_COMBAT"
                .. "|!BIG_DEFENSIVE",
            id .. " buffs external-defensive filter")
        assertEqual(buffs.visibility.requiresVisible, true,
            id .. " buffs visibility gate")
        assertEqual(buffs.visibility.requiresAssist, true,
            id .. " buffs assist gate")

        assertEqual(debuffs.migrationReady, true,
            id .. " debuffs migration readiness")
        assertEqual(debuffs.metrics.groupCount, 1,
            id .. " debuffs group count")
        assertEqual(debuffs.metrics.legacyMaxFrameCount, 3,
            id .. " debuffs legacy capacity")
        assertEqual(debuffs.metrics.nativeVisibleCapacity, 3,
            id .. " debuffs native capacity")
        assertEqual(
            debuffs.metrics.nativeVisibleCapacity * 8,
            24,
            id .. " eight-token visible capacity"
        )
        assertEqual(debuffs.metrics.initialRestrictedButtonCount, 10,
            id .. " debuffs initial native buttons")
        assertEqual(
            debuffs.metrics.freshContainerRestrictedButtonCountCeiling,
            10,
            id .. " debuffs native button ceiling"
        )
        assertEqual(
            debuffs.metrics.initialRestrictedButtonCount * 8,
            80,
            id .. " eight-token initial native buttons"
        )
        assertEqual(
            debuffs.metrics
                .freshContainerRestrictedButtonCountCeiling * 8,
            80,
            id .. " eight-token native button ceiling"
        )
        assertEqual(debuffs.completeSpec.holder.width, 59,
            id .. " debuffs holder width")
        assertEqual(debuffs.completeSpec.holder.height, 19,
            id .. " debuffs holder height")
        assertEqual(debuffs.partition, nil,
            id .. " debuffs partition")
        assertEqual(debuffs.completeSpec.groups[1].filterString,
            "HARMFUL|PLAYER", id .. " debuffs filter")
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

testBossActivationAndConstructionOrder()
testBossDisableAndReenableLifecycle()
testBossConfigModeGuardsAreLocal()
testBossLegacyAuraFallback()
testShippedBossPresetBounds()

print("unit_frame_boss_native_aura_test.lua: ok")
