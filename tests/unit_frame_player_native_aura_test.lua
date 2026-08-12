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

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local function makeHarness()
    local harness = {
        callbacks = {},
        frames = {},
        configMode = {},
        createIndicatorCalls = {},
        setupCalls = {},
        disableCalls = {},
        registerUnitWatchCalls = {},
        unregisterUnitWatchCalls = {},
    }
    local UF = {
        Parent = {
            name = "BFIUnitFrameParent",
        },
        config = {
            general = {
                enabled = true,
            },
            player = {
                general = {
                    enabled = true,
                },
                indicators = {},
            },
        },
    }
    local AF = {}

    function AF.Copy(value)
        return copy(value)
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

    function UF.AddToConfigMode(group, frame)
        harness.configMode[#harness.configMode + 1] = {
            group = group,
            frame = frame,
        }
    end

    function UF.CreatePreviewRect(frame)
        frame.previewCreated = true
    end

    function UF.CreateIndicators(frame, indicators)
        harness.createIndicatorCalls[#harness.createIndicatorCalls + 1] = {
            frame = frame,
            indicators = indicators,
        }
        frame.createdIndicators = indicators
        for _, descriptor in ipairs(indicators) do
            local name = type(descriptor) == "table"
                and descriptor[2]
                or descriptor
            local indicator = {}

            function indicator:Disable()
                self.enabled = false
            end

            function indicator:EnableConfigMode()
                self.configMode = true
                self.enableConfigModeCount =
                    (self.enableConfigModeCount or 0) + 1
            end

            function indicator:DisableConfigMode()
                self.configMode = false
                self.disableConfigModeCount =
                    (self.disableConfigModeCount or 0) + 1
            end

            frame.indicators[name] = indicator
        end
    end

    function UF.SetupUnitFrame(frame, config, indicators, skip)
        harness.setupCalls[#harness.setupCalls + 1] = {
            frame = frame,
            config = config,
            indicators = indicators,
            skip = skip,
        }
        frame.enabled = true
    end

    function UF.DisableIndicators(frame)
        harness.disableCalls[#harness.disableCalls + 1] = frame
        frame.enabled = false
        for _, indicator in pairs(frame.indicators) do
            if UF.configModeEnabled and indicator.DisableConfigMode then
                indicator:DisableConfigMode()
            end
            indicator:Disable()
        end
    end

    local function CreateFrame(frameType, name, parent, template)
        local frame = {
            attributes = {},
            frameType = frameType,
            indicators = {},
            name = name,
            parent = parent,
            template = template,
            visible = false,
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

        function frame:IsVisible()
            return self.visible
        end

        function frame:Hide()
            self.visible = false
            self.hideCount = (self.hideCount or 0) + 1
        end

        function frame:Show()
            self.visible = true
            self.showCount = (self.showCount or 0) + 1
        end

        harness.frames[#harness.frames + 1] = frame
        return frame
    end

    local function RegisterUnitWatch(frame)
        harness.registerUnitWatchCalls[
            #harness.registerUnitWatchCalls + 1
        ] = frame
        frame.unitWatchRegistered = true
    end

    local function UnregisterUnitWatch(frame)
        harness.unregisterUnitWatchCalls[
            #harness.unregisterUnitWatchCalls + 1
        ] = frame
        frame.unitWatchRegistered = false
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
        PLAYER = "Player",
        RegisterUnitWatch = RegisterUnitWatch,
        UnregisterUnitWatch = UnregisterUnitWatch,
        error = error,
        ipairs = ipairs,
        pairs = pairs,
        select = select,
        tostring = tostring,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected Player integration global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError = loadfile("Modules/UnitFrames/Units/Player.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.BFI = BFI
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
            error("unexpected preset compiler global: " .. tostring(key), 2)
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

local function testPlayerActivationAndPreviewIsolation()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    assertTrue(update, "Player update callback was not registered")
    assertEqual(#harness.frames, 0, "module-load frame allocation")

    update(nil, "nameplates", "player")
    update(nil, "unitFrames", "target")
    assertEqual(#harness.frames, 0, "unrelated update frame allocation")

    update(nil, "unitFrames", "player", false)
    assertEqual(#harness.frames, 1, "Player frame creation count")
    assertEqual(#harness.createIndicatorCalls, 1,
        "Player indicator creation count")
    assertEqual(#harness.setupCalls, 1, "Player setup count")
    assertEqual(#harness.registerUnitWatchCalls, 1,
        "Player unit-watch registration")

    local frame = harness.frames[1]
    local live = harness.createIndicatorCalls[1].indicators
    local liveBuffs = findIndicator(live, "buffs")
    local liveDebuffs = findIndicator(live, "debuffs")
    local preview = harness.UF.previewIndicators
    local previewBuffs = findIndicator(preview, "buffs")
    local previewDebuffs = findIndicator(preview, "debuffs")

    assertEqual(frame.frameType, "Button", "Player frame type")
    assertEqual(frame.template, "BFIUnitButtonTemplate",
        "Player frame template")
    assertEqual(frame.parent, harness.UF.Parent, "Player frame parent")
    assertEqual(frame.attributes.unit, "player", "Player secure unit")
    assertEqual(harness.configMode[1].group, "player",
        "Player config-mode group")
    assertEqual(harness.configMode[1].frame, frame,
        "Player config-mode frame")
    assertTrue(frame.previewCreated, "Player preview rectangle")

    assertTrue(liveBuffs, "live Player buffs descriptor")
    assertTrue(liveDebuffs, "live Player debuffs descriptor")
    assertEqual(liveBuffs[1], "nativeAuras", "live buffs builder")
    assertEqual(liveBuffs[3], "HELPFUL", "live buffs filter")
    assertEqual(liveDebuffs[1], "nativeAuras", "live debuffs builder")
    assertEqual(liveDebuffs[3], "HARMFUL", "live debuffs filter")

    assertTrue(preview ~= live, "preset preview list aliases live list")
    assertEqual(#preview, #live - 2, "preset preview indicator count")
    assertEqual(previewBuffs, nil, "preset preview buffs descriptor")
    assertEqual(previewDebuffs, nil, "preset preview debuffs descriptor")
    assertEqual(liveBuffs[1], "nativeAuras",
        "preset filtering mutated live buffs")
    assertEqual(liveDebuffs[1], "nativeAuras",
        "preset filtering mutated live debuffs")

    local common = readFile("Modules/UnitFrames/Common.lua")
    assertTrue(
        common:find("nativeAuras%s*=%s*UF%.CreateNativeAuras") ~= nil,
        "native aura builder is not wired to the compatibility selector"
    )
end

local function testPlayerDisableAndReenableLifecycle()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "player", false)
    local frame = harness.frames[1]

    update(nil, "unitFrames", "player", true)
    assertEqual(#harness.frames, 1, "Player frame recreated on update")
    assertEqual(#harness.setupCalls, 2, "Player repeated setup count")
    assertEqual(harness.setupCalls[2].skip, true,
        "skip-indicator flag was not forwarded")
    assertEqual(#harness.registerUnitWatchCalls, 2,
        "Player repeated unit-watch registration")

    harness.UF.config.player.general.enabled = false
    update(nil, "unitFrames", "player")
    assertEqual(#harness.disableCalls, 1,
        "Player indicator disable count")
    assertEqual(harness.disableCalls[1], frame,
        "disabled Player frame")
    assertEqual(#harness.unregisterUnitWatchCalls, 1,
        "Player unit-watch unregister count")
    assertEqual(frame.unitWatchRegistered, false,
        "Player unit watch after disable")
    assertEqual(frame.hideCount, 1, "Player hide count")

    harness.UF.config.player.general.enabled = true
    update(nil, "unitFrames", "player")
    assertEqual(#harness.frames, 1, "Player frame recreated on re-enable")
    assertEqual(#harness.setupCalls, 3, "Player re-enable setup count")
    assertEqual(#harness.registerUnitWatchCalls, 3,
        "Player re-enable unit-watch registration")
    assertEqual(frame.unitWatchRegistered, true,
        "Player unit watch after re-enable")

    harness.UF.config.general.enabled = false
    update(nil, "unitFrames", "player")
    assertEqual(#harness.disableCalls, 2,
        "global disable indicator count")
    assertEqual(#harness.unregisterUnitWatchCalls, 2,
        "global disable unit-watch count")
end

local function testPlayerConfigModeReenableLifecycle()
    local harness = makeHarness()
    local update = harness.callbacks.BFI_UpdateModule

    update(nil, "unitFrames", "player")
    local frame = harness.frames[1]
    local indicatorCount = 0

    harness.UF.configModeEnabled = true
    frame.inConfigMode = true
    for _, indicator in pairs(frame.indicators) do
        indicator:EnableConfigMode()
        indicatorCount = indicatorCount + 1
    end

    harness.UF.config.player.general.enabled = false
    update(nil, "unitFrames", "player")
    assertEqual(frame.visible, false,
        "disabled Player config-mode preview visibility")
    assertEqual(#harness.unregisterUnitWatchCalls, 1,
        "disabled Player config-mode unit-watch count")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, false,
            "disabled Player indicator preview state")
        assertEqual(indicator.disableConfigModeCount, 1,
            "disabled Player indicator preview count")
    end

    harness.UF.config.player.general.enabled = true
    update(nil, "unitFrames", "player", true)
    assertEqual(harness.setupCalls[2].skip, false,
        "Player config-mode re-enable skipped indicators")
    assertEqual(frame.visible, true,
        "Player config-mode re-enable preview visibility")
    assertEqual(frame.showCount, 1,
        "Player config-mode re-enable preview show count")
    assertEqual(#harness.registerUnitWatchCalls, 1,
        "Player config-mode re-enable unit-watch count")

    local restoredCount = 0
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.configMode, true,
            "re-enabled Player indicator preview state")
        assertEqual(indicator.enableConfigModeCount, 2,
            "re-enabled Player indicator preview count")
        restoredCount = restoredCount + 1
    end
    assertEqual(restoredCount, indicatorCount,
        "re-enabled Player indicator total")

    update(nil, "unitFrames", "player", true)
    assertEqual(harness.setupCalls[3].skip, true,
        "enabled Player config-mode skip flag")
    assertEqual(#harness.registerUnitWatchCalls, 1,
        "enabled Player config-mode unit-watch count")
    for _, indicator in pairs(frame.indicators) do
        assertEqual(indicator.enableConfigModeCount, 2,
            "enabled Player repeated indicator preview entry")
    end
end

local function testShippedPlayerPresetBounds()
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
        local indicators = UF.GetPreset(id).player.indicators
        local buffs, buffError = UF.CompileNativeAuraSpec(
            "player",
            "HELPFUL",
            indicators.buffs
        )
        local debuffs, debuffError = UF.CompileNativeAuraSpec(
            "player",
            "HARMFUL",
            indicators.debuffs
        )

        assertEqual(buffError, nil, id .. " buffs compile error")
        assertEqual(debuffError, nil, id .. " debuffs compile error")
        assertEqual(indicators.buffs.enabled, false,
            id .. " default buffs state")
        assertEqual(indicators.debuffs.enabled, true,
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
            22,
            219,
            39,
            id .. " debuffs"
        )
    end
end
testShippedPlayerPresetBounds()

print("unit_frame_player_native_aura_test.lua: ok")
