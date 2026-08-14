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

local function makeHarness(
    hasNativeBackend,
    cellLoaded,
    creationContext
)
    creationContext = creationContext or "solo"
    local filteredUnitCounts = {
        ["full-raid"] = 40,
        party = 5,
        solo = 1,
    }
    local showAttributeByContext = {
        ["full-raid"] = "showRaid",
        party = "showParty",
        solo = "showSolo",
    }
    assertTrue(
        filteredUnitCounts[creationContext],
        "unsupported Raid creation context: "
            .. tostring(creationContext)
    )

    local harness = {
        addonQueries = {},
        callbacks = {},
        configGroups = {},
        createIndicatorCalls = {},
        disableIndicatorCalls = {},
        driverRegistrations = {},
        dispelCalls = {},
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

        local showAttribute =
            showAttributeByContext[creationContext]
        local filteredUnitCount =
            self.attributes[showAttribute]
                and filteredUnitCounts[creationContext]
                or 0
        local startingIndex =
            self.attributes.startingIndex or 1
        local needButtons =
            filteredUnitCount - (startingIndex - 1)
        local showAttributes = {
            showParty = self.attributes.showParty,
            showPlayer = self.attributes.showPlayer,
            showRaid = self.attributes.showRaid,
            showSolo = self.attributes.showSolo,
        }

        self.childrenCreated = true
        record(
            "header.precreate-show",
            self,
            self.attributes.auraContainerTemplate,
            startingIndex,
            filteredUnitCount,
            needButtons,
            creationContext,
            showAttributes
        )
        assertEqual(
            startingIndex,
            -39,
            "Raid secure-header precreation index"
        )
        assertTrue(
            needButtons >= 0,
            "Raid secure-header button count must be non-negative"
        )
        for index = 1, needButtons do
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

    function AF.GetAnchorPoints_GroupHeader()
        return "TOPLEFT", "BOTTOMLEFT", 0, -4, 5,
            "TOPLEFT", "TOPLEFT"
    end

    function AF.LoadPosition()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function AF.SetGridSize(
        frame,
        width,
        height,
        spacingX,
        spacingY,
        columns,
        unitsPerColumn
    )
        frame.grid = {
            columns = columns,
            height = height,
            spacingX = spacingX,
            spacingY = spacingY,
            unitsPerColumn = unitsPerColumn,
            width = width,
        }
    end

    function AF.SetSize(frame, width, height)
        frame.width = width
        frame.height = height
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
        raid = {
            general = {
                anchor = "TOPLEFT",
                bgColor = {},
                borderColor = {},
                enabled = true,
                groupBy = "GROUP",
                groupFilter = "1,2,3,4,5,6,7,8",
                groupingOrder = "1,2,3,4,5,6,7,8",
                height = 40,
                maxColumns = 8,
                oorAlpha = 0.5,
                orientation = "top_to_bottom_then_right",
                position = {},
                sortDir = "ASC",
                sortMethod = "INDEX",
                spacingX = 4,
                spacingY = 4,
                tooltip = true,
                unitsPerColumn = 5,
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

    function UF.CreateGroupNativeDispelHighlight(
        parent,
        name,
        containerKey
    )
        local call = {
            containerKey = containerKey,
            name = name,
            parent = parent,
        }
        harness.dispelCalls[#harness.dispelCalls + 1] = call
        record("group-native.dispel-builder", parent, name, containerKey)

        if not UF.HasNativeAuraContainerBackend() then
            return newIndicator(name, "unavailable-dispel")
        end

        local containers = parent._nativeAuraContainers
        local seed = containers and containers[containerKey]
        assertTrue(seed, "native group dispel seed is missing")
        call.seed = seed
        local indicator = newIndicator(name, "native-dispel")
        indicator.containerKey = containerKey
        indicator.seed = seed
        return indicator
    end

    function UF.CreateIndicators(frame, descriptors)
        local containers =
            rawget(frame, "_nativeAuraContainers")
        if hasNativeBackend then
            assertTrue(containers,
                "Raid native map must precede indicator construction")
            assertEqual(countKeys(containers), 4,
                "Raid native map size at indicator construction")
            assertTrue(containers.buffs,
                "Raid buff seed before indicator construction")
            assertTrue(containers.debuffs,
                "Raid debuff seed before indicator construction")
            assertTrue(containers.dispels,
                "Raid dispel seed before indicator construction")
            assertTrue(containers.buffDisplays,
                "Raid Buff Display seed map before indicator construction")
        else
            assertEqual(containers, nil,
                "legacy Raid gained native map before construction")
        end

        harness.createIndicatorCalls[
            #harness.createIndicatorCalls + 1
        ] = {
            buffs = containers and containers.buffs,
            debuffs = containers and containers.debuffs,
            dispels = containers and containers.dispels,
            frame = frame,
            indicators = descriptors,
        }
        record("indicators.create", frame)

        for _, descriptor in next, descriptors do
            if type(descriptor) == "table" then
                local builder = descriptor[1]
                local name = descriptor[2]
                if builder == "groupNativeAuras"
                    or builder == "groupBuffDisplays"
                then
                    frame.indicators[name] = UF.CreateGroupNativeAuras(
                        frame,
                        frame:GetName() .. "_"
                            .. AF.UpperFirst(name),
                        descriptor[3],
                        descriptor[4]
                    )
                elseif builder == "groupNativeDispels" then
                    frame.indicators[name] =
                        UF.CreateGroupNativeDispelHighlight(
                            frame,
                            frame:GetName() .. "_"
                                .. AF.UpperFirst(name),
                            descriptor[3]
                        )
                else
                    error("unexpected Raid aura builder: "
                        .. tostring(builder), 2)
                end
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

    function UF.SetupIndicators(frame, descriptors, config)
        frame.enabled = true
        local raidFrame = harness.framesByName.BFI_Raid
        local call = {
            config = config,
            frame = frame,
            indicators = descriptors,
            raidShown = raidFrame and raidFrame.shown,
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
            call.raidShown
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

    local C_AddOns = {}

    function C_AddOns.IsAddOnLoaded(name)
        harness.addonQueries[#harness.addonQueries + 1] = name
        return cellLoaded == true
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
        C_AddOns = C_AddOns,
        CreateFrame = newFrame,
        RAID = "Raid",
        RegisterAttributeDriver = RegisterAttributeDriver,
        UnregisterAttributeDriver = UnregisterAttributeDriver,
        assert = assert,
        next = next,
        select = select,
        strfind = string.find,
        type = type,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected Raid global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/Units/Raid.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    function harness:FireUpdate(skipIndicatorUpdates)
        local callback = assert(
            self.callbacks.BFI_UpdateModule,
            "Raid update callback was not registered"
        )
        callback(
            nil,
            "unitFrames",
            "raid",
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

local function findDispelCall(harness, parent, containerKey)
    for _, call in ipairs(harness.dispelCalls) do
        if call.parent == parent
            and call.containerKey == containerKey
        then
            return call
        end
    end
end

local function findLegacyAuraCall(harness, parent, auraFilter)
    for _, call in ipairs(harness.legacyAuraCalls) do
        if call.parent == parent
            and call.auraFilter == auraFilter
        then
            return call
        end
    end
end

local function testCellLoadedDoesNoRaidWork()
    local harness = makeHarness(true, true)
    harness.events = {}
    harness:FireUpdate()

    assertEqual(#harness.addonQueries, 1,
        "Cell-loaded add-on query count")
    assertEqual(harness.addonQueries[1], "Cell",
        "Cell-loaded add-on query")
    assertEqual(#harness.events, 0,
        "Cell-loaded Raid lifecycle work")
    assertEqual(harness.framesByName.BFI_Raid, nil,
        "Cell-loaded Raid frame")
    assertEqual(harness.framesByName.BFI_RaidHeader, nil,
        "Cell-loaded Raid header")
    assertEqual(countKeys(harness.configGroups), 0,
        "Cell-loaded config registration")
    assertEqual(#harness.nativeSeeds, 0,
        "Cell-loaded native seeds")
    assertEqual(#harness.createIndicatorCalls, 0,
        "Cell-loaded indicator construction")
    assertEqual(#harness.setupIndicatorCalls, 0,
        "Cell-loaded indicator setup")
    assertEqual(#harness.driverRegistrations, 0,
        "Cell-loaded visibility driver")
end

local function testNativeHeaderSeedsAndBuilderArguments()
    local harness
    local header
    for _, creationContext in ipairs({
        "solo",
        "party",
        "full-raid",
    }) do
        harness = makeHarness(
            true,
            false,
            creationContext
        )
        harness:FireUpdate()

        header = harness.framesByName.BFI_RaidHeader
        local contextPrecreateIndex = findEventIndex(
            harness.events,
            "header.precreate-show",
            function(event)
                return event.args[1] == header
            end
        )
        assertTrue(
            contextPrecreateIndex,
            "secure header precreation event in "
                .. creationContext
        )
        local precreation =
            harness.events[contextPrecreateIndex]
        assertEqual(
            precreation.args[4],
            0,
            "empty precreation filter in "
                .. creationContext
        )
        assertEqual(
            precreation.args[5],
            40,
            "12.1 needButtons in " .. creationContext
        )
        assertEqual(
            precreation.args[6],
            creationContext,
            "recorded Raid creation context"
        )
        assertEqual(
            countKeys(precreation.args[7]),
            0,
            "precreation show flags in "
                .. creationContext
        )

        local restoredIndex = findEventIndex(
            harness.events,
            "frame.attribute",
            function(event)
                return event.args[1] == header
                    and event.args[2] == "startingIndex"
                    and event.args[3] == 1
            end
        )
        assertTrue(
            restoredIndex,
            "restored starting-index event in "
                .. creationContext
        )
        assertTrue(
            contextPrecreateIndex < restoredIndex,
            "starting index restored after precreation in "
                .. creationContext
        )
        for _, showAttribute in ipairs({
            "showSolo",
            "showRaid",
            "showParty",
            "showPlayer",
        }) do
            local liveFilterIndex = findEventIndex(
                harness.events,
                "frame.attribute",
                function(event)
                    return event.args[1] == header
                        and event.args[2] == showAttribute
                        and event.args[3] == true
                end
            )
            assertTrue(
                liveFilterIndex,
                showAttribute .. " event in "
                    .. creationContext
            )
            assertTrue(
                restoredIndex < liveFilterIndex,
                "starting index restored before "
                    .. showAttribute .. " in "
                    .. creationContext
            )
        end

        assertEqual(
            #header.children,
            40,
            "Raid child count in " .. creationContext
        )
        assertEqual(
            header.attributes.startingIndex,
            1,
            "restored starting index in "
                .. creationContext
        )
        assertEqual(
            header.attributes.showSolo,
            true,
            "restored solo filter in " .. creationContext
        )
        assertEqual(
            header.attributes.showParty,
            true,
            "restored party filter in " .. creationContext
        )
        assertEqual(
            header.attributes.showRaid,
            true,
            "restored Raid filter in " .. creationContext
        )
        assertEqual(
            header.attributes.showPlayer,
            true,
            "restored player filter in "
                .. creationContext
        )
    end

    assertTrue(header, "Raid header")
    assertEqual(
        header.attributes.auraContainerTemplate,
        "CustomAuraContainerTemplate",
        "Raid native header template"
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
    assertEqual(
        harness.events[precreateIndex].args[3],
        -39,
        "precreation starting index"
    )

    assertEqual(#header.children, 40, "Raid child count")
    assertEqual(#harness.nativeSeeds, 80,
        "eager helpful and dispel seed count")
    assertEqual(#harness.createIndicatorCalls, 40,
        "Raid indicator construction count")
    assertEqual(#harness.groupAuraCalls, 80,
        "group aura builder call count")
    assertEqual(#harness.nativeAuraCalls, 80,
        "native aura selection count")
    assertEqual(#harness.dispelCalls, 40,
        "native dispel builder call count")
    assertEqual(#harness.legacyAuraCalls, 0,
        "native Raid legacy selection count")

    local descriptors =
        harness.createIndicatorCalls[1].indicators
    local buffsTuple = findAuraTuple(descriptors, "buffs")
    local debuffsTuple = findAuraTuple(descriptors, "debuffs")
    local dispelsTuple = findAuraTuple(descriptors, "dispels")
    assertTrue(buffsTuple, "Raid buffs tuple")
    assertEqual(#buffsTuple, 4, "Raid buffs tuple size")
    assertEqual(buffsTuple[1], "groupBuffDisplays",
        "Raid buffs builder")
    assertEqual(buffsTuple[2], "buffs", "Raid buffs name")
    assertEqual(buffsTuple[3], "HELPFUL",
        "Raid buffs filter")
    assertEqual(buffsTuple[4], "buffs",
        "Raid buffs seed key")
    assertTrue(debuffsTuple, "Raid debuffs tuple")
    assertEqual(#debuffsTuple, 4,
        "Raid debuffs tuple size")
    assertEqual(debuffsTuple[1], "groupNativeAuras",
        "Raid debuffs builder")
    assertEqual(debuffsTuple[2], "debuffs",
        "Raid debuffs name")
    assertEqual(debuffsTuple[3], "HARMFUL",
        "Raid debuffs filter")
    assertEqual(debuffsTuple[4], "debuffs",
        "Raid debuffs seed key")
    assertTrue(dispelsTuple, "Raid dispels tuple")
    assertEqual(#dispelsTuple, 3,
        "Raid dispels tuple size")
    assertEqual(dispelsTuple[1], "groupNativeDispels",
        "Raid dispels builder")
    assertEqual(dispelsTuple[2], "dispels",
        "Raid dispels name")
    assertEqual(dispelsTuple[3], "dispels",
        "Raid dispels seed key")

    local claimedSeeds = {}
    for index, button in ipairs(header.children) do
        local containers =
            rawget(button, "_nativeAuraContainers")
        assertTrue(containers,
            "Raid child native container map " .. index)
        assertEqual(countKeys(containers), 4,
            "Raid child explicit seed count " .. index)
        assertEqual(countKeys(containers.buffDisplays), 0,
            "Raid child disabled Buff Display seed count " .. index)
        assertEqual(containers.debuffs, button.AuraContainer,
            "Raid header-born harmful seed " .. index)
        assertEqual(containers.debuffs.origin, "header",
            "Raid harmful seed origin " .. index)
        assertEqual(containers.buffs.origin, "eager",
            "Raid helpful seed origin " .. index)
        assertEqual(containers.buffs.child, button,
            "Raid helpful seed parent " .. index)
        assertEqual(containers.dispels.origin, "eager",
            "Raid dispel seed origin " .. index)
        assertEqual(containers.dispels.child, button,
            "Raid dispel seed parent " .. index)
        assertTrue(
            containers.buffs ~= containers.debuffs,
            "Raid aura seeds must be distinct " .. index
        )
        assertTrue(
            containers.dispels ~= containers.buffs
                and containers.dispels ~= containers.debuffs,
            "Raid dispel seed must be independent " .. index
        )
        assertTrue(not claimedSeeds[containers.buffs],
            "duplicate Raid helpful seed " .. index)
        assertTrue(not claimedSeeds[containers.debuffs],
            "duplicate Raid harmful seed " .. index)
        assertTrue(not claimedSeeds[containers.dispels],
            "duplicate Raid dispel seed " .. index)
        claimedSeeds[containers.buffs] = true
        claimedSeeds[containers.debuffs] = true
        claimedSeeds[containers.dispels] = true

        local construction =
            harness.createIndicatorCalls[index]
        assertEqual(construction.frame, button,
            "Raid indicator construction frame " .. index)
        assertEqual(construction.buffs, containers.buffs,
            "Raid helpful seed before construction " .. index)
        assertEqual(construction.debuffs, containers.debuffs,
            "Raid harmful seed before construction " .. index)
        assertEqual(construction.dispels, containers.dispels,
            "Raid dispel seed before construction " .. index)

        local buffsCall =
            findGroupAuraCall(harness, button, "buffs")
        local debuffsCall =
            findGroupAuraCall(harness, button, "debuffs")
        local dispelsCall =
            findDispelCall(harness, button, "dispels")
        assertTrue(buffsCall,
            "Raid helpful builder call " .. index)
        assertEqual(
            buffsCall.name,
            button:GetName() .. "_Buffs",
            "Raid helpful builder name " .. index
        )
        assertEqual(buffsCall.auraFilter, "HELPFUL",
            "Raid helpful builder filter " .. index)
        assertEqual(buffsCall.seed, containers.buffs,
            "Raid helpful forwarded seed " .. index)
        assertTrue(debuffsCall,
            "Raid harmful builder call " .. index)
        assertEqual(
            debuffsCall.name,
            button:GetName() .. "_Debuffs",
            "Raid harmful builder name " .. index
        )
        assertEqual(debuffsCall.auraFilter, "HARMFUL",
            "Raid harmful builder filter " .. index)
        assertEqual(debuffsCall.seed, containers.debuffs,
            "Raid harmful forwarded seed " .. index)
        assertTrue(dispelsCall,
            "Raid dispel builder call " .. index)
        assertEqual(
            dispelsCall.name,
            button:GetName() .. "_Dispels",
            "Raid dispel builder name " .. index
        )
        assertEqual(dispelsCall.seed, containers.dispels,
            "Raid dispel forwarded seed " .. index)

        assertEqual(button._updateOnGroupUpdate, true,
            "Raid group-update flag " .. index)
        assertEqual(button._deferUpdateOnUnitChange, true,
            "Raid deferred unit-change flag " .. index)
        assertEqual(button._enableUnitButtonMapping, true,
            "Raid unit mapping flag " .. index)
    end
    assertEqual(countKeys(claimedSeeds), 120,
        "distinct Raid native seed count")
    -- The compiled shipped contract is covered by the contract/scale tests;
    -- integration owns the fixed child and one-slot multiplicity.
    assertEqual(#header.children * (10 + 30 + 1),
        1640, "Raid initial native button reservations")
end

local function testUnavailableBackendIsExactLegacyPath()
    local harness = makeHarness(false, false)
    harness:FireUpdate()

    local header = harness.framesByName.BFI_RaidHeader
    assertEqual(
        header.attributes.auraContainerTemplate,
        nil,
        "12.0.7 Raid header attribute"
    )
    assertEqual(#header.children, 40,
        "12.0.7 Raid child count")
    assertEqual(#harness.nativeSeeds, 0,
        "12.0.7 Raid native seed count")
    assertEqual(#harness.nativeAuraCalls, 0,
        "12.0.7 Raid native selection count")
    assertEqual(#harness.groupAuraCalls, 80,
        "12.0.7 group builder dispatch count")
    assertEqual(#harness.legacyAuraCalls, 80,
        "12.0.7 legacy builder selection count")
    assertEqual(#harness.dispelCalls, 40,
        "unavailable dispel builder dispatch count")

    for index, button in ipairs(header.children) do
        assertEqual(
            rawget(button, "_nativeAuraContainers"),
            nil,
            "12.0.7 native container map " .. index
        )
        assertEqual(button.AuraContainer, nil,
            "12.0.7 header-born container " .. index)
        assertEqual(
            harness.createIndicatorCalls[index].buffs,
            nil,
            "12.0.7 construction buff seed " .. index
        )
        assertEqual(
            harness.createIndicatorCalls[index].debuffs,
            nil,
            "12.0.7 construction debuff seed " .. index
        )
        assertEqual(
            harness.createIndicatorCalls[index].dispels,
            nil,
            "12.0.7 construction dispel seed " .. index
        )

        local helpful =
            findLegacyAuraCall(harness, button, "HELPFUL")
        local harmful =
            findLegacyAuraCall(harness, button, "HARMFUL")
        assertTrue(helpful,
            "12.0.7 helpful legacy builder " .. index)
        assertTrue(harmful,
            "12.0.7 harmful legacy builder " .. index)
        assertEqual(
            helpful.name,
            button:GetName() .. "_Buffs",
            "12.0.7 helpful legacy name " .. index
        )
        assertEqual(
            harmful.name,
            button:GetName() .. "_Debuffs",
            "12.0.7 harmful legacy name " .. index
        )
        assertEqual(helpful.hasSubFrame, nil,
            "12.0.7 helpful legacy arguments " .. index)
        assertEqual(harmful.hasSubFrame, nil,
            "12.0.7 harmful legacy arguments " .. index)
    end
end

local function testSkipGuardAndConfigRegistrationSurviveDisable()
    local harness = makeHarness(true, false)

    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 40,
        "initial true skip must not skip setup")
    assertEqual(#harness.configGroups.raid, 40,
        "registered Raid config children")
    assertEqual(#harness.configGroups["raid.container"], 1,
        "registered Raid container")
    assertEqual(#harness.configGroups["raid.header"], 1,
        "registered Raid header")

    harness:FireUpdate("truthy")
    assertEqual(#harness.setupIndicatorCalls, 80,
        "non-boolean skip must not skip setup")

    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 80,
        "enabled exact true skip")

    harness:FireUpdate(false)
    assertEqual(#harness.setupIndicatorCalls, 120,
        "explicit false skip")

    local raid = harness.framesByName.BFI_Raid
    harness.UF.config.raid.general.enabled = false
    harness:FireUpdate(true)
    assertEqual(#harness.removeConfigModeCalls, 0,
        "Raid disable config-group removal")
    assertEqual(#harness.configGroups.raid, 40,
        "Raid config group after disable")
    assertEqual(#harness.configGroups["raid.container"], 1,
        "Raid container group after disable")
    assertEqual(#harness.configGroups["raid.header"], 1,
        "Raid header group after disable")
    assertEqual(raid.enabled, false,
        "disabled Raid mover state")
    assertEqual(raid.shown, false,
        "disabled Raid visibility")
    assertEqual(raid.driverRegistered, false,
        "disabled Raid visibility driver")
    assertEqual(#harness.disableIndicatorCalls, 40,
        "disabled Raid indicator count")

    harness.UF.config.raid.general.enabled = true
    harness:FireUpdate(true)
    assertEqual(#harness.setupIndicatorCalls, 160,
        "re-enable true skip must restore setup")
    assertEqual(raid.enabled, true,
        "re-enabled Raid mover state")
    assertEqual(raid.shown, true,
        "re-enabled Raid visibility")
    assertEqual(raid.driverRegistered, true,
        "re-enabled Raid visibility driver")
    assertEqual(#harness.configGroups.raid, 40,
        "Raid config group after re-enable")
end

local function testConfigModeReenableRestoresPreviewState()
    local harness = makeHarness(true, false)
    harness:FireUpdate()

    local raid = harness.framesByName.BFI_Raid
    local header = raid.header
    raid.inConfigMode = true
    header.inConfigMode = true
    harness.UF.configModeEnabled = true

    harness.UF.config.raid.general.enabled = false
    harness:FireUpdate()
    assertEqual(raid.shown, false,
        "config-mode disabled Raid visibility")

    harness:ClearLifecycleEvents()
    harness.UF.config.raid.general.enabled = true
    harness:FireUpdate(true)

    assertEqual(raid.shown, true,
        "config-mode re-enabled Raid parent visibility")
    assertEqual(header.shown, true,
        "config-mode re-enabled Raid header visibility")
    assertEqual(#harness.setupIndicatorCalls, 40,
        "config-mode re-enable indicator setup")
    assertEqual(#harness.driverRegistrations, 0,
        "config-mode re-enable driver registration")

    local raidShowIndex = findEventIndex(
        harness.events,
        "frame.show",
        function(event)
            return event.args[1] == raid
        end
    )
    local setupIndex = findEventIndex(
        harness.events,
        "indicators.setup"
    )
    assertTrue(raidShowIndex,
        "config-mode re-enable Raid show")
    assertTrue(setupIndex,
        "config-mode re-enable indicator setup event")
    assertTrue(
        raidShowIndex < setupIndex,
        "Raid parent must be shown before preview setup"
    )

    for callIndex, call in ipairs(harness.setupIndicatorCalls) do
        assertEqual(call.raidShown, true,
            "Raid shown during setup " .. callIndex)
    end

    for index, button in ipairs(header.children) do
        assertTrue(button.previewRect,
            "Raid preview rectangle retained " .. index)
        for name, indicator in pairs(button.indicators) do
            assertEqual(
                indicator.enableConfigModeCount,
                1,
                "Raid preview indicator restored "
                    .. index .. ":" .. name
            )
            assertEqual(indicator.inConfigMode, true,
                "Raid preview indicator state "
                    .. index .. ":" .. name)
        end
    end
end

local function testRaidOwnsDriverDecision()
    local harness = makeHarness(true, false)
    harness.UF.configModeEnabled = true
    harness:FireUpdate()

    local raid = harness.framesByName.BFI_Raid
    assertEqual(#harness.driverRegistrations, 1,
        "global config mode must not suppress Raid driver")
    assertEqual(
        harness.driverRegistrations[1].frame,
        raid,
        "Raid driver owner"
    )
    assertEqual(
        harness.driverRegistrations[1].key,
        "state-visibility",
        "Raid driver key"
    )
    assertEqual(
        harness.driverRegistrations[1].value,
        "[@raid1,exists] show; hide",
        "Raid driver value"
    )

    raid.inConfigMode = true
    harness.UF.configModeEnabled = false
    harness:ClearLifecycleEvents()
    harness:FireUpdate()
    assertEqual(#harness.driverRegistrations, 0,
        "Raid config mode must suppress its driver")
    assertEqual(raid.shown, true,
        "Raid config mode explicit visibility")
end

testCellLoadedDoesNoRaidWork()
testNativeHeaderSeedsAndBuilderArguments()
testUnavailableBackendIsExactLegacyPath()
testSkipGuardAndConfigRegistrationSurviveDisable()
testConfigModeReenableRestoresPreviewState()
testRaidOwnsDriverDecision()

print("unit_frame_raid_native_aura_test.lua: ok")
