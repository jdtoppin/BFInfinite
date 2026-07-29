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

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function makeHarness(hasNativeBackend)
    local harness = {
        callbacks = {},
        configGroups = {},
        createIndicatorCalls = {},
        disableIndicatorCalls = {},
        driverRegistrations = {},
        events = {},
        framesByName = {},
        groupAuraCalls = {},
        legacyAuraCalls = {},
        nativeAuraCalls = {},
        nativeSeeds = {},
        previewCalls = {},
        removeConfigModeCalls = {},
        setupIndicatorCalls = {},
    }
    local UF = {
        configModeEnabled = false,
    }
    local AF = {}

    local function record(name, ...)
        harness.events[#harness.events + 1] = {
            name = name,
            args = {...},
        }
    end

    local frameMethods = {}

    function frameMethods:GetName()
        return self.name
    end

    function frameMethods:GetAttribute(key)
        return self.attributes[key]
    end

    function frameMethods:SetAttribute(key, value)
        self.attributes[key] = value
        record("frame.attribute", self, key, value)
        local callback = self.scripts.OnAttributeChanged
        if callback then
            callback(self, key, value)
        end
    end

    function frameMethods:HookScript(scriptName, callback)
        local previous = self.scripts[scriptName]
        if previous then
            self.scripts[scriptName] = function(...)
                previous(...)
                callback(...)
            end
        else
            self.scripts[scriptName] = callback
        end
    end

    function frameMethods:Show()
        self.shown = true
        record("frame.show", self)

        if self.template ~= "SecureGroupHeaderTemplate"
            or self.childrenCreated
        then
            return
        end

        self.childrenCreated = true
        record(
            "header.precreate-show",
            self,
            self.attributes.auraContainerTemplate
        )
        for index = 1, 5 do
            local child = setmetatable({
                attributes = {},
                indicators = {},
                name = self.name .. "UnitButton" .. index,
                parent = self,
                scripts = {},
                shown = true,
            }, {
                __index = frameMethods,
            })
            self[index] = child
            self.children[index] = child
            harness.framesByName[child.name] = child

            if self.attributes.auraContainerTemplate then
                child.AuraContainer = {
                    child = child,
                    index = index,
                    origin = "header",
                    template =
                        self.attributes.auraContainerTemplate,
                }
            end
            record("header.child-created", self, child)
        end
    end

    function frameMethods:Hide()
        self.shown = false
        record("frame.hide", self)
    end

    function frameMethods:ClearAllPoints()
        record("frame.clear-points", self)
    end

    function frameMethods:SetPoint(...)
        self.point = {...}
        record("frame.point", self, ...)
    end

    function frameMethods:SetSize(width, height)
        self.width = width
        self.height = height
        record("frame.size", self, width, height)
    end

    local function newFrame(_, name, parent, template)
        local frame = setmetatable({
            attributes = {},
            children = {},
            indicators = {},
            name = name,
            parent = parent,
            scripts = {},
            shown = false,
            template = template,
        }, {
            __index = frameMethods,
        })
        harness.framesByName[name] = frame
        record("frame.create", frame, template)
        return frame
    end

    local function newIndicator(name, kind)
        local indicator = {
            kind = kind,
            name = name,
        }

        function indicator:EnableConfigMode()
            self.inConfigMode = true
            self.enableConfigModeCount =
                (self.enableConfigModeCount or 0) + 1
            record("indicator.enable-config", self)
        end

        function indicator:DisableConfigMode()
            self.inConfigMode = false
            self.disableConfigModeCount =
                (self.disableConfigModeCount or 0) + 1
            record("indicator.disable-config", self)
        end

        function indicator:Disable()
            self.enabled = false
            record("indicator.disable", self)
        end

        return indicator
    end

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.ApplyDefaultBackdropWithColors()
    end

    function AF.ConvertPixelsForRegion(value)
        return value
    end

    function AF.CreateMover()
    end

    function AF.GetAnchorPoints_Simple(_, spacing)
        return "TOPLEFT", "BOTTOMLEFT", 0, -(spacing or 0)
    end

    function AF.LoadPosition()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function AF.SetHeight(frame, height)
        frame.height = height
    end

    function AF.SetListHeight(frame, count, height, spacing)
        frame.height = count * height + (count - 1) * spacing
    end

    function AF.SetListWidth(frame, count, width, spacing)
        frame.width = count * width + (count - 1) * spacing
    end

    function AF.SetSize(frame, width, height)
        frame.width = width
        frame.height = height
    end

    function AF.SetWidth(frame, width)
        frame.width = width
    end

    function AF.UpdateMoverSave()
    end

    function AF.UpperFirst(value)
        return value:sub(1, 1):upper() .. value:sub(2)
    end

    UF.Parent = newFrame("Frame", "BFIUnitFrameParent")
    UF.config = {
        general = {
            enabled = true,
        },
        party = {
            general = {
                anchor = "TOPLEFT",
                bgColor = {},
                borderColor = {},
                enabled = true,
                groupBy = "GROUP",
                groupingOrder = "1,2,3,4",
                height = 40,
                oorAlpha = 0.5,
                orientation = "top_to_bottom",
                position = {},
                showPlayer = true,
                sortDir = "ASC",
                sortMethod = "INDEX",
                spacing = 4,
                tooltip = true,
                width = 100,
            },
            indicators = {},
        },
    }

    function UF.AddToConfigMode(group, frame)
        local frames = harness.configGroups[group]
        if not frames then
            frames = {}
            harness.configGroups[group] = frames
        end
        frames[#frames + 1] = frame
        record("config.add", group, frame)
    end

    function UF.RemoveFromConfigMode(group)
        harness.removeConfigModeCalls[
            #harness.removeConfigModeCalls + 1
        ] = group
        harness.configGroups[group] = nil
        record("config.remove", group)
    end

    function UF.HasNativeAuraContainerBackend()
        return hasNativeBackend
    end

    function UF.PrepareNativeGroupAuraHeader(header)
        record("native.header-prepare", header)
        if not UF.HasNativeAuraContainerBackend() then
            return false
        end

        header:SetAttribute(
            "auraContainerTemplate",
            "CustomAuraContainerTemplate"
        )
        return true
    end

    function UF.CreateNativeGroupAuraContainerSeed(parent)
        assertTrue(hasNativeBackend,
            "unavailable backend allocated a native seed")
        local seed = {
            child = parent,
            index = #harness.nativeSeeds + 1,
            origin = "eager",
        }
        harness.nativeSeeds[#harness.nativeSeeds + 1] = seed
        record("native.seed", parent, seed)
        return seed
    end

    function UF.CreateAuras(parent, name, auraFilter, hasSubFrame)
        local call = {
            auraFilter = auraFilter,
            hasSubFrame = hasSubFrame,
            name = name,
            parent = parent,
        }
        harness.legacyAuraCalls[
            #harness.legacyAuraCalls + 1
        ] = call
        record(
            "legacy.builder",
            parent,
            name,
            auraFilter,
            hasSubFrame
        )
        local indicator = newIndicator(name, "legacy")
        indicator.auraFilter = auraFilter
        return indicator
    end

    function UF.CreateGroupNativeAuras(
        parent,
        name,
        auraFilter,
        containerKey
    )
        local call = {
            auraFilter = auraFilter,
            containerKey = containerKey,
            name = name,
            parent = parent,
        }
        harness.groupAuraCalls[
            #harness.groupAuraCalls + 1
        ] = call
        record(
            "group-native.builder",
            parent,
            name,
            auraFilter,
            containerKey
        )

        if not UF.HasNativeAuraContainerBackend() then
            return UF.CreateAuras(parent, name, auraFilter)
        end

        local containers = parent._nativeAuraContainers
        local seed = containers and containers[containerKey]
        assertTrue(seed, "native group aura seed is missing")
        call.seed = seed
        harness.nativeAuraCalls[
            #harness.nativeAuraCalls + 1
        ] = call
        local indicator = newIndicator(name, "native")
        indicator.auraFilter = auraFilter
        indicator.containerKey = containerKey
        indicator.seed = seed
        return indicator
    end

    function UF.CreateIndicators(frame, indicators)
        harness.createIndicatorCalls[
            #harness.createIndicatorCalls + 1
        ] = {
            frame = frame,
            indicators = indicators,
        }
        record("indicators.create", frame)

        for _, descriptor in next, indicators do
            if type(descriptor) == "table" then
                local builder = descriptor[1]
                local name = descriptor[2]
                assertEqual(builder, "groupNativeAuras",
                    "unexpected Party aura builder")
                frame.indicators[name] =
                    UF.CreateGroupNativeAuras(
                        frame,
                        frame:GetName() .. "_" .. AF.UpperFirst(name),
                        descriptor[3],
                        descriptor[4]
                    )
            else
                frame.indicators[descriptor] =
                    newIndicator(descriptor, "ordinary")
            end
        end
    end

    function UF.CreatePreviewRect(frame)
        frame.previewRect = {
            parent = frame,
        }
        harness.previewCalls[#harness.previewCalls + 1] = frame
        record("preview.create", frame)
    end

    function UF.DisableIndicators(frame)
        harness.disableIndicatorCalls[
            #harness.disableIndicatorCalls + 1
        ] = frame
        frame.enabled = false
        for _, indicator in next, frame.indicators do
            if UF.configModeEnabled
                and indicator.DisableConfigMode
            then
                indicator:DisableConfigMode()
            end
            indicator:Disable()
        end
        record("indicators.disable", frame)
    end

    function UF.SetupIndicators(frame, indicators, config)
        frame.enabled = true
        local call = {
            config = config,
            frame = frame,
            indicators = indicators,
            partyShown =
                harness.framesByName.BFI_Party.shown,
        }
        harness.setupIndicatorCalls[
            #harness.setupIndicatorCalls + 1
        ] = call
        for _, indicator in next, frame.indicators do
            indicator.enabled = true
        end
        record(
            "indicators.setup",
            frame,
            call.partyShown
        )
    end

    local function RegisterAttributeDriver(frame, key, value)
        local call = {
            frame = frame,
            key = key,
            value = value,
        }
        harness.driverRegistrations[
            #harness.driverRegistrations + 1
        ] = call
        frame.driverRegistered = true
        record("driver.register", frame, key, value)
        frame:Show()
    end

    local function UnregisterAttributeDriver(frame)
        frame.driverRegistered = false
        record("driver.unregister", frame)
    end

    local BFI = {
        L = setmetatable({}, {
            __index = function(_, key)
                return key
            end,
        }),
        funcs = {
            LoadPosition = AF.LoadPosition,
        },
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        CreateFrame = newFrame,
        PARTY = "Party",
        RegisterAttributeDriver = RegisterAttributeDriver,
        UnregisterAttributeDriver = UnregisterAttributeDriver,
        assert = assert,
        error = error,
        next = next,
        pairs = pairs,
        select = select,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected Party global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/Units/Party.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    function harness:FireUpdate(skipIndicatorUpdates)
        local callback = assert(
            self.callbacks.BFI_UpdateModule,
            "Party update callback was not registered"
        )
        callback(
            nil,
            "unitFrames",
            "party",
            skipIndicatorUpdates
        )
    end

    function harness:ClearLifecycleEvents()
        self.driverRegistrations = {}
        self.events = {}
        self.setupIndicatorCalls = {}
    end

    harness.AF = AF
    harness.BFI = BFI
    harness.UF = UF
    return harness
end

local function findAuraTuple(indicators, indicatorName)
    for _, descriptor in next, indicators do
        if type(descriptor) == "table"
            and descriptor[2] == indicatorName
        then
            return descriptor
        end
    end
end

local function findEventIndex(events, name, predicate)
    for index, event in ipairs(events) do
        if event.name == name
            and (not predicate or predicate(event))
        then
            return index
        end
    end
end

local function findGroupAuraCall(harness, parent, containerKey)
    for _, call in ipairs(harness.groupAuraCalls) do
        if call.parent == parent
            and call.containerKey == containerKey
        then
            return call
        end
    end
end

local function testNativeHeaderSeedsAndBuilderArguments()
    local harness = makeHarness(true)
    harness:FireUpdate()

    local header = harness.framesByName.BFI_PartyHeader
    assertTrue(header, "Party header")
    assertEqual(
        header.attributes.auraContainerTemplate,
        "CustomAuraContainerTemplate",
        "Party native header template"
    )

    local attributeIndex = findEventIndex(
        harness.events,
        "frame.attribute",
        function(event)
            return event.args[1] == header
                and event.args[2] == "auraContainerTemplate"
        end
    )
    local precreateIndex = findEventIndex(
        harness.events,
        "header.precreate-show",
        function(event)
            return event.args[1] == header
        end
    )
    assertTrue(attributeIndex, "native header attribute event")
    assertTrue(precreateIndex, "secure header precreation event")
    assertTrue(
        attributeIndex < precreateIndex,
        "native header attribute must precede child precreation"
    )
    assertEqual(
        harness.events[precreateIndex].args[2],
        "CustomAuraContainerTemplate",
        "precreation native template"
    )

    assertEqual(#header.children, 5, "Party child count")
    assertEqual(#harness.nativeSeeds, 5,
        "eager helpful seed count")
    assertEqual(#harness.groupAuraCalls, 10,
        "group aura builder call count")
    assertEqual(#harness.nativeAuraCalls, 10,
        "native aura selection count")
    assertEqual(#harness.legacyAuraCalls, 0,
        "native Party legacy selection count")

    local indicators =
        harness.createIndicatorCalls[1].indicators
    local buffsTuple = findAuraTuple(indicators, "buffs")
    local debuffsTuple = findAuraTuple(indicators, "debuffs")
    assertTrue(buffsTuple, "Party buffs tuple")
    assertEqual(#buffsTuple, 4, "Party buffs tuple size")
    assertEqual(buffsTuple[1], "groupNativeAuras",
        "Party buffs builder")
    assertEqual(buffsTuple[2], "buffs", "Party buffs name")
    assertEqual(buffsTuple[3], "HELPFUL",
        "Party buffs filter")
    assertEqual(buffsTuple[4], "buffs",
        "Party buffs seed key")
    assertTrue(debuffsTuple, "Party debuffs tuple")
    assertEqual(#debuffsTuple, 4,
        "Party debuffs tuple size")
    assertEqual(debuffsTuple[1], "groupNativeAuras",
        "Party debuffs builder")
    assertEqual(debuffsTuple[2], "debuffs",
        "Party debuffs name")
    assertEqual(debuffsTuple[3], "HARMFUL",
        "Party debuffs filter")
    assertEqual(debuffsTuple[4], "debuffs",
        "Party debuffs seed key")

    local claimedSeeds = {}
    for index, button in ipairs(header.children) do
        local containers =
            rawget(button, "_nativeAuraContainers")
        assertTrue(containers,
            "Party child native container map " .. index)
        assertEqual(countKeys(containers), 2,
            "Party child explicit seed count " .. index)
        assertEqual(containers.debuffs, button.AuraContainer,
            "Party header-born harmful seed " .. index)
        assertEqual(containers.debuffs.origin, "header",
            "Party harmful seed origin " .. index)
        assertEqual(containers.buffs.origin, "eager",
            "Party helpful seed origin " .. index)
        assertEqual(containers.buffs.child, button,
            "Party helpful seed parent " .. index)
        assertTrue(
            containers.buffs ~= containers.debuffs,
            "Party aura seeds must be distinct " .. index
        )
        assertTrue(not claimedSeeds[containers.buffs],
            "duplicate Party helpful seed " .. index)
        assertTrue(not claimedSeeds[containers.debuffs],
            "duplicate Party harmful seed " .. index)
        claimedSeeds[containers.buffs] = true
        claimedSeeds[containers.debuffs] = true

        local buffsCall =
            findGroupAuraCall(harness, button, "buffs")
        local debuffsCall =
            findGroupAuraCall(harness, button, "debuffs")
        assertTrue(buffsCall,
            "Party helpful builder call " .. index)
        assertEqual(buffsCall.auraFilter, "HELPFUL",
            "Party helpful builder filter " .. index)
        assertEqual(buffsCall.seed, containers.buffs,
            "Party helpful forwarded seed " .. index)
        assertTrue(debuffsCall,
            "Party harmful builder call " .. index)
        assertEqual(debuffsCall.auraFilter, "HARMFUL",
            "Party harmful builder filter " .. index)
        assertEqual(debuffsCall.seed, containers.debuffs,
            "Party harmful forwarded seed " .. index)

        assertEqual(button._updateOnGroupUpdate, true,
            "Party group-update flag " .. index)
        assertEqual(button._deferUpdateOnUnitChange, true,
            "Party deferred unit-change flag " .. index)
        assertEqual(button._enableUnitButtonMapping, true,
            "Party unit mapping flag " .. index)
    end
    assertEqual(countKeys(claimedSeeds), 10,
        "distinct Party native seed count")
end

local function testUnavailableBackendIsExactLegacyPath()
    local harness = makeHarness(false)
    harness:FireUpdate()

    local header = harness.framesByName.BFI_PartyHeader
    assertEqual(
        header.attributes.auraContainerTemplate,
        nil,
        "12.0.7 Party header attribute"
    )
    assertEqual(#harness.nativeSeeds, 0,
        "12.0.7 Party native seed count")
    assertEqual(#harness.nativeAuraCalls, 0,
        "12.0.7 Party native selection count")
    assertEqual(#harness.groupAuraCalls, 10,
        "12.0.7 group builder dispatch count")
    assertEqual(#harness.legacyAuraCalls, 10,
        "12.0.7 legacy builder selection count")

    for index, button in ipairs(header.children) do
        assertEqual(
            rawget(button, "_nativeAuraContainers"),
            nil,
            "12.0.7 native container map " .. index
        )
        assertEqual(button.AuraContainer, nil,
            "12.0.7 header-born container " .. index)

        local helpful
        local harmful
        for _, call in ipairs(harness.legacyAuraCalls) do
            if call.parent == button
                and call.auraFilter == "HELPFUL"
            then
                helpful = call
            elseif call.parent == button
                and call.auraFilter == "HARMFUL"
            then
                harmful = call
            end
        end
        assertTrue(helpful,
            "12.0.7 helpful legacy builder " .. index)
        assertTrue(harmful,
            "12.0.7 harmful legacy builder " .. index)
        assertEqual(helpful.hasSubFrame, nil,
            "12.0.7 helpful legacy arguments " .. index)
        assertEqual(harmful.hasSubFrame, nil,
            "12.0.7 harmful legacy arguments " .. index)
    end
end

local function testSkipGuardAndConfigRegistrationSurviveDisable()
    local harness = makeHarness(true)

    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 5,
        "initial true skip must not skip setup")
    assertEqual(#harness.configGroups.party, 5,
        "registered Party config children")

    harness:FireUpdate("truthy")
    assertEqual(#harness.setupIndicatorCalls, 10,
        "non-boolean skip must not skip setup")

    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 10,
        "enabled exact true skip")

    harness:FireUpdate(false)
    assertEqual(#harness.setupIndicatorCalls, 15,
        "explicit false skip")

    local party = harness.framesByName.BFI_Party
    harness.UF.config.party.general.enabled = false
    harness:FireUpdate(true)
    assertEqual(#harness.removeConfigModeCalls, 0,
        "Party disable config-group removal")
    assertEqual(#harness.configGroups.party, 5,
        "Party config group after disable")
    assertEqual(party.enabled, false,
        "disabled Party mover state")
    assertEqual(party.shown, false,
        "disabled Party visibility")
    assertEqual(#harness.disableIndicatorCalls, 5,
        "disabled Party indicator count")

    harness.UF.config.party.general.enabled = true
    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 20,
        "re-enable true skip must restore setup")
    assertEqual(party.enabled, true,
        "re-enabled Party mover state")
end

local function testConfigModeReenableRestoresPreviewState()
    local harness = makeHarness(true)
    harness:FireUpdate()

    local party = harness.framesByName.BFI_Party
    local header = party.header
    party.inConfigMode = true
    header.inConfigMode = true
    harness.UF.configModeEnabled = true

    harness.UF.config.party.general.enabled = false
    harness:FireUpdate()
    assertEqual(party.shown, false,
        "config-mode disabled Party visibility")

    harness:ClearLifecycleEvents()
    harness.UF.config.party.general.enabled = true
    harness:FireUpdate(true)

    assertEqual(party.shown, true,
        "config-mode re-enabled Party parent visibility")
    assertEqual(header.shown, true,
        "config-mode re-enabled Party header visibility")
    assertEqual(#harness.setupIndicatorCalls, 5,
        "config-mode re-enable indicator setup")
    assertEqual(#harness.driverRegistrations, 0,
        "config-mode re-enable driver registration")

    local partyShowIndex = findEventIndex(
        harness.events,
        "frame.show",
        function(event)
            return event.args[1] == party
        end
    )
    local setupIndex = findEventIndex(
        harness.events,
        "indicators.setup"
    )
    assertTrue(partyShowIndex,
        "config-mode re-enable Party show")
    assertTrue(setupIndex,
        "config-mode re-enable indicator setup event")
    assertTrue(
        partyShowIndex < setupIndex,
        "Party parent must be shown before preview setup"
    )

    for index, button in ipairs(header.children) do
        assertTrue(button.previewRect,
            "Party preview rectangle retained " .. index)
        for name, indicator in pairs(button.indicators) do
            assertEqual(
                indicator.enableConfigModeCount,
                1,
                "Party preview indicator restored "
                    .. index .. ":" .. name
            )
            assertEqual(indicator.inConfigMode, true,
                "Party preview indicator state "
                    .. index .. ":" .. name)
        end
    end
end

local function testPartyOwnsDriverDecision()
    local harness = makeHarness(true)
    harness.UF.configModeEnabled = true
    harness:FireUpdate()

    local party = harness.framesByName.BFI_Party
    assertEqual(#harness.driverRegistrations, 1,
        "global config mode must not suppress Party driver")
    assertEqual(
        harness.driverRegistrations[1].frame,
        party,
        "Party driver owner"
    )

    party.inConfigMode = true
    harness.UF.configModeEnabled = false
    harness:ClearLifecycleEvents()
    harness:FireUpdate()
    assertEqual(#harness.driverRegistrations, 0,
        "Party config mode must suppress its driver")
    assertEqual(party.shown, true,
        "Party config mode explicit visibility")
end

testNativeHeaderSeedsAndBuilderArguments()
testUnavailableBackendIsExactLegacyPath()
testSkipGuardAndConfigRegistrationSurviveDisable()
testConfigModeReenableRestoresPreviewState()
testPartyOwnsDriverDecision()

print("unit_frame_party_native_aura_test.lua: ok")
