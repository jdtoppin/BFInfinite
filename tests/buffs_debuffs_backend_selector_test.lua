local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertLog(actual, expected, message)
    assertEqual(#actual, #expected, message .. " length")
    for index, value in ipairs(expected) do
        assertEqual(actual[index], value, message .. " " .. index)
    end
end

local REQUIRED_CUSTOM_AF_METHODS = {
    "AddCustomAuraGroup",
    "AddCustomItemEnchantment",
    "CreateCustomAuraContainer",
    "GetCustomAuraContainerConstructionStats",
    "GetCustomAuraContainerConstructionTotals",
    "HasCustomAuraContainer",
    "ResetCustomItemEnchantmentLayout",
    "SetCustomAuraContainerEnabled",
    "SetCustomAuraContainerFlowLayout",
    "SetCustomAuraContainerProcessingPolicy",
    "SetCustomAuraContainerUnit",
    "SetCustomAuraGroupCandidateFilters",
    "SetCustomAuraGroupFilterString",
    "SetCustomAuraGroupLayout",
    "SetCustomAuraGroupMaxFrameCount",
    "SetCustomAuraGroupSortMethod",
    "SetCustomItemEnchantmentLayout",
    "SetCustomItemEnchantmentSortMethod",
    "UpdateCustomAuraContainer",
}

local function NewSchema()
    return {
        AnchorUtil = {
            FlowLayoutAxis = {
                Horizontal = 0,
                Vertical = 1,
            },
            FlowDirection = {
                Left = 0,
                Right = 1,
                Up = 2,
                Down = 3,
            },
        },
        AuraContainerSortMethod = {
            Default = 0,
            ExpirationOnly = 5,
            NameOnly = 7,
            AuraInstanceIDOnly = 8,
        },
        AuraContainerSortDirection = {
            Normal = 0,
            Reverse = 1,
        },
        AuraContainerItemEnchantmentSlot = {
            MainHand = 0,
            OffHand = 1,
            Ranged = 2,
        },
        AuraContainerItemEnchantmentSortMethod = {
            Slot = 0,
            Duration = 1,
        },
        CustomAuraContainerAuraProcessingPolicy = {
            None = 0,
        },
        CustomAuraContainerItemEnchantmentPlacement = {
            BeforeAuraGroups = 0,
            AfterAuraGroups = 1,
        },
    }
end

local function NewHarness(options)
    options = options or {}
    local interfaceVersion = options.interfaceVersion
    if interfaceVersion == nil and not options.missingInterfaceVersion then
        interfaceVersion = 120100
    end
    local createFrameCalls = 0
    local customDisableCalls = {}
    local customUpdateCalls = {}
    local callLog = {}
    local blizzardStyleDisableCalls = 0
    local blizzardStyleUpdateCalls = {}
    local eventCallbacks = {}
    local refreshEvents = {}
    local inCombat = options.inCombat == true
    local updateCallback

    local schema = NewSchema()
    for name in pairs(schema) do
        _G[name] = nil
    end
    if options.missingSchema then
        schema[options.missingSchema] = nil
    end
    for name, value in pairs(schema) do
        _G[name] = value
    end

    _G.C_UnitAuras = {
        GetUnitAuraInstanceIDs = function()
            return {}
        end,
    }
    _G.GetBuildInfo = function()
        -- Retail returns localizedVersion and buildInfo after the interface
        -- number. Keep those trailing values so the harness catches accidental
        -- multi-return forwarding into APIs such as tonumber.
        return "test", "test", "test", interfaceVersion, "test-localized", "test-build-info"
    end
    _G.GetWeaponEnchantInfo = function()
        return false
    end
    _G.GetInventorySlotInfo = function()
        return 1
    end
    _G.InCombatLockdown = function()
        return inCombat
    end
    _G.CreateFrame = function()
        createFrameCalls = createFrameCalls + 1
        error("CreateFrame must not be reached by selector tests")
    end
    _G.RegisterAttributeDriver = function()
    end
    if options.legacyGlobals == false then
        _G.SecureAuraHeader_Update = nil
        _G.SecureAuraHeader_UpdateEventRegistrations = nil
    else
        _G.SecureAuraHeader_Update = function()
        end
        _G.SecureAuraHeader_UpdateEventRegistrations = function()
        end
    end
    _G.Enum = {
        UnitAuraSortRule = {
            Unsorted = 0,
        },
        UnitAuraSortDirection = {
            Normal = 0,
        },
    }

    local AF = {
        isRetail = options.isRetail ~= false,
        versionNum = options.afVersion or 42,
        UIParent = {},
    }
    if options.customMethods ~= false then
        for _, methodName in ipairs(REQUIRED_CUSTOM_AF_METHODS) do
            AF[methodName] = function()
            end
        end
        AF.HasCustomAuraContainer = function()
            return options.hasCustomAuraContainer ~= false
        end
    end
    if options.missingCustomMethod then
        AF[options.missingCustomMethod] = nil
    end
    if options.nativeDispelColorMethodValue ~= nil then
        AF.HasNativeDispelColorTexture =
            options.nativeDispelColorMethodValue
    elseif options.nativeDispelColorMethod ~= false then
        AF.HasNativeDispelColorTexture = function()
            return options.nativeDispelColor ~= false
        end
    end
    AF.RegisterCallback = function(event, callback)
        if event == "BFI_UpdateModule" then
            updateCallback = callback
        end
    end
    AF.Fire = function(event, which)
        refreshEvents[#refreshEvents + 1] = {
            event = event,
            which = which,
        }
    end
    _G.AbstractFramework = AF

    local BD = {
        CanSuppressNativePublicAuras = function()
            return true
        end,
        SetNativePublicAurasSuppressed = function(which, suppressed)
            callLog[#callLog + 1] = "native:" .. which .. ":"
                .. tostring(suppressed)
            return options.nativeRestoreResult ~= false
        end,
        RegisterEvent = function(_, event, callback)
            eventCallbacks[event] = callback
        end,
        UnregisterEvent = function(_, event, callback)
            if eventCallbacks[event] == callback then
                eventCallbacks[event] = nil
            end
        end,
        config = {
            buffs = {
                enabled = true,
            },
            debuffs = {
                enabled = true,
            },
        },
    }
    local BFI = {
        L = {},
        modules = {
            BuffsDebuffs = BD,
        },
    }

    local chunk = assert(loadfile("Modules/BuffsDebuffs/BuffsDebuffs.lua"))
    chunk("BFInfinite", BFI)

    if options.registerCustomBackend then
        local customPanes = options.customPanes or {
            buffs = true,
            debuffs = true,
        }
        BD.IsCustomAuraContainerAvailable = function(which)
            return customPanes[which] == true
        end
        BD.UpdateCustomAuraContainer = function(which, config)
            callLog[#callLog + 1] = "customUpdate:" .. which
            customUpdateCalls[#customUpdateCalls + 1] = {
                which = which,
                config = config,
            }
        end
        BD.DisableCustomAuraContainer = function(which)
            callLog[#callLog + 1] = "customDisable:" .. which
            customDisableCalls[#customDisableCalls + 1] = which
            return options.customDisableResult ~= false
        end
    end

    if options.registerBlizzardDebuffStyle then
        BD.HasBlizzardDebuffStyleCapability = function()
            callLog[#callLog + 1] = "styleCapability"
            if options.styleCapabilityFailsInCombat and inCombat then
                return false
            end
            return options.styleCapability ~= false
        end
        BD.UpdateBlizzardDebuffStyle = function(config)
            callLog[#callLog + 1] = "styleUpdate"
            blizzardStyleUpdateCalls[#blizzardStyleUpdateCalls + 1] =
                config
            return options.styleUpdateResult ~= false
        end
        BD.DisableBlizzardDebuffStyle = function()
            callLog[#callLog + 1] = "styleDisable"
            blizzardStyleDisableCalls = blizzardStyleDisableCalls + 1
            return options.styleDisableResult ~= false
        end
    end

    return {
        BD = BD,
        getCreateFrameCalls = function()
            return createFrameCalls
        end,
        customDisableCalls = customDisableCalls,
        customUpdateCalls = customUpdateCalls,
        blizzardStyleUpdateCalls = blizzardStyleUpdateCalls,
        callLog = callLog,
        clearCallLog = function()
            for index = #callLog, 1, -1 do
                callLog[index] = nil
            end
        end,
        getBlizzardStyleDisableCalls = function()
            return blizzardStyleDisableCalls
        end,
        refreshEvents = refreshEvents,
        setCombat = function(value)
            inCombat = value == true
        end,
        setBackendOverride = function(backend)
            BD.GetAuraBackend = function(which)
                if which == "debuffs" then return backend end
            end
        end,
        fireRegen = function()
            local callback = eventCallbacks.PLAYER_REGEN_ENABLED
            assert(callback, "PLAYER_REGEN_ENABLED callback not registered")
            callback()
        end,
        hasRegenCallback = function()
            return eventCallbacks.PLAYER_REGEN_ENABLED ~= nil
        end,
        update = function(which)
            updateCallback(nil, "buffsDebuffs", which)
        end,
    }
end

do
    local harness = NewHarness({
        interfaceVersion = 120007,
        afVersion = 21,
        customMethods = false,
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), true, "12.0.7 legacy capability")
    assertEqual(
        BD.GetAuraBackend("buffs"),
        BD.SECURE_AURA_HEADER_BACKEND,
        "12.0.7 buffs backend"
    )
    assertEqual(
        BD.GetAuraBackend("debuffs"),
        BD.SECURE_AURA_HEADER_BACKEND,
        "12.0.7 debuffs backend"
    )
    harness.update("invalid")
    assertEqual(harness.getCreateFrameCalls(), 0, "invalid update pane")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerBlizzardDebuffStyle = true,
        styleCapabilityFailsInCombat = true,
    })
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "out-of-combat capability seeds static style policy")
    harness.clearCallLog()
    harness.setCombat(true)
    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "combat uses only last verified static style policy")
    harness.update("debuffs")
    assertEqual(BD.IsBuffsDebuffsUpdatePending("debuffs"), true,
        "combat style request remains visible as pending")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "combat does not call the style adapter")
    harness.setCombat(false)
    harness.fireRegen()
    assertEqual(BD.IsBuffsDebuffsUpdatePending("debuffs"), false,
        "regen clears Debuffs pending state")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "regen applies the verified style")
end

for _, backendCase in ipairs({
    {name = "custom", backend = "customAuraContainer"},
    {name = "secure", backend = "secureAuraHeader"},
    {name = "nil", backend = nil},
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        styleDisableResult = false,
    })
    harness.setBackendOverride(backendCase.backend)
    harness.BD.config.debuffs.enabled = false
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {"styleDisable"},
        backendCase.name .. " aborts on failed style restore")
    assertEqual(#harness.customUpdateCalls, 0,
        backendCase.name .. " performs no downstream custom update")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customDisableResult = false,
    })
    harness.setBackendOverride(
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "customDisable:debuffs",
        "native:debuffs:false",
        "styleUpdate",
    }, "style ignores optional custom-disable false")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerBlizzardDebuffStyle = true,
        nativeRestoreResult = false,
    })
    harness.setBackendOverride(
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {"native:debuffs:false"},
        "style aborts when native restore fails")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "native restore failure prevents style update")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerBlizzardDebuffStyle = true,
        styleUpdateResult = false,
    })
    harness.setBackendOverride(
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "native:debuffs:false",
        "styleUpdate",
    }, "style false result ends transition")
end

do
    local harness = NewHarness({
        missingInterfaceVersion = true,
        afVersion = 36,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), false,
        "missing interface legacy capability")
    assertEqual(BD.HasCustomAuraContainerCapability(), false,
        "missing interface custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil,
        "missing interface backend")
    assertEqual(harness.getCreateFrameCalls(), 0,
        "missing interface CreateFrame")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {buffs = true, debuffs = true},
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), false, "12.1 legacy capability")
    assertEqual(BD.HasCustomAuraContainerCapability(), true, "12.1 custom capability")
    assertEqual(BD.HasCustomHarmfulAuraDescriptorCapability(), true,
        "AF r42 native dispel-colour descriptor capability")
    assertEqual(
        BD.GetAuraBackend("buffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "12.1 buffs backend"
    )
    assertEqual(
        BD.GetAuraBackend("debuffs"),
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "12.1 debuffs backend"
    )
    assertEqual(
        BD.GetAuraBackend(),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "12.1 aggregate backend"
    )
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "12.1 custom selector construction")
    assertEqual(#harness.customUpdateCalls, 1, "12.1 custom update count")
    assertEqual(harness.customUpdateCalls[1].which, "buffs", "12.1 custom buffs update")
    assertEqual(harness.customUpdateCalls[1].config, BD.config.buffs, "12.1 custom buffs config")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "12.1 Debuffs style update count")
    assertEqual(harness.blizzardStyleUpdateCalls[1], BD.config.debuffs,
        "12.1 Debuffs style config")
    assertEqual(#harness.customDisableCalls, 1,
        "style transition deactivates optional Debuffs custom controller")
    assertEqual(harness.customDisableCalls[1], "debuffs",
        "style transition custom pane")
    assertEqual(harness.callLog[#harness.callLog - 2],
        "customDisable:debuffs", "style transition first step")
    assertEqual(harness.callLog[#harness.callLog - 1],
        "native:debuffs:false", "style transition second step")
    assertEqual(harness.callLog[#harness.callLog],
        "styleUpdate", "style transition final step")
end

for _, capabilityCase in ipairs({
    {
        name = "AF r41",
        afVersion = 41,
    },
    {
        name = "string AF r42",
        afVersion = "42",
    },
    {
        name = "NaN AF version",
        afVersion = 0 / 0,
    },
    {
        name = "infinite AF version",
        afVersion = math.huge,
    },
    {
        name = "missing native dispel-colour method",
        afVersion = 42,
        nativeDispelColorMethod = false,
    },
    {
        name = "non-callable native dispel-colour method",
        afVersion = 42,
        nativeDispelColorMethodValue = true,
    },
    {
        name = "false native dispel-colour capability",
        afVersion = 42,
        nativeDispelColor = false,
    },
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = capabilityCase.afVersion,
        nativeDispelColorMethod = capabilityCase.nativeDispelColorMethod,
        nativeDispelColorMethodValue =
            capabilityCase.nativeDispelColorMethodValue,
        nativeDispelColor = capabilityCase.nativeDispelColor,
        registerCustomBackend = true,
        customPanes = {debuffs = true},
    })
    assertEqual(
        harness.BD.HasCustomHarmfulAuraDescriptorCapability(),
        false,
        capabilityCase.name .. " stays unavailable"
    )
    assertEqual(harness.BD.GetAuraBackend("debuffs"), nil,
        capabilityCase.name .. " never selects custom Debuffs")
    harness.update("debuffs")
    assertEqual(#harness.customUpdateCalls, 0,
        capabilityCase.name .. " performs no custom Debuffs update")
    assertEqual(
        harness.callLog[#harness.callLog] == "native:debuffs:true",
        false,
        capabilityCase.name .. " performs no native suppression"
    )
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        customPanes = {debuffs = true},
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomHarmfulAuraDescriptorCapability(), true,
        "complete dormant descriptor capability")
    assertEqual(BD.GetAuraBackend("debuffs"), nil,
        "complete descriptor cannot select a harmful runtime backend")
    harness.update("debuffs")
    assertEqual(#harness.customUpdateCalls, 0,
        "complete descriptor performs no custom Debuffs update")
    for _, call in ipairs(harness.callLog) do
        assertEqual(call == "native:debuffs:true", false,
            "complete descriptor performs no native suppression")
    end
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {buffs = true},
        inCombat = true,
        styleCapabilityFailsInCombat = true,
    })
    local BD = harness.BD

    harness.update("buffs")
    assertEqual(
        BD.IsBuffsDebuffsUpdatePending("buffs"),
        true,
        "combat queue marks Buffs pending"
    )
    assertEqual(
        BD.IsBuffsDebuffsUpdatePending("debuffs"),
        false,
        "single-pane combat queue excludes Debuffs"
    )
    assertEqual(#harness.refreshEvents, 1, "first queue refresh")
    assertEqual(
        harness.refreshEvents[1].event,
        "BFI_RefreshOptions",
        "queue refresh event"
    )
    assertEqual(
        harness.refreshEvents[1].which,
        "buffsDebuffs",
        "queue refresh module"
    )
    assertEqual(harness.hasRegenCallback(), true, "regen callback registered")

    harness.update("buffs")
    assertEqual(#harness.refreshEvents, 1, "same queue state deduplicated")

    harness.update("debuffs")
    assertEqual(
        BD.IsBuffsDebuffsUpdatePending("buffs"),
        true,
        "mixed queue coalesces Buffs"
    )
    assertEqual(
        BD.IsBuffsDebuffsUpdatePending("debuffs"),
        true,
        "mixed queue coalesces Debuffs"
    )
    assertEqual(
        BD.IsBuffsDebuffsUpdatePending(),
        true,
        "mixed queue exposes aggregate pending"
    )
    assertEqual(#harness.refreshEvents, 2, "wildcard queue refresh")

    harness.update("debuffs")
    assertEqual(#harness.refreshEvents, 2, "wildcard state deduplicated")

    harness.setCombat(false)
    harness.fireRegen()
    assertEqual(BD.IsBuffsDebuffsUpdatePending(), false, "regen clears queue")
    assertEqual(harness.hasRegenCallback(), false, "regen callback released")
    assertEqual(#harness.refreshEvents, 3, "queue clear refresh")
    assertEqual(#harness.customUpdateCalls, 1,
        "wildcard retry updates custom Buffs")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "wildcard retry updates Debuffs style")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
        isRetail = false,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), false, "non-Retail legacy capability")
    assertEqual(BD.HasCustomAuraContainerCapability(), false,
        "non-Retail custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "non-Retail backend")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), true, "unregistered custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "unregistered 12.1 backend")
    assertEqual(BD.HasAuraBackend("buffs"), false, "unregistered 12.1 availability")
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "unregistered 12.1 legacy fallback")
end


for _, missingSchema in ipairs({
    "AnchorUtil",
    "AuraContainerSortMethod",
    "AuraContainerSortDirection",
    "AuraContainerItemEnchantmentSlot",
    "AuraContainerItemEnchantmentSortMethod",
    "CustomAuraContainerAuraProcessingPolicy",
    "CustomAuraContainerItemEnchantmentPlacement",
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
        missingSchema = missingSchema,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), false,
        "missing schema: " .. missingSchema)
    assertEqual(BD.GetAuraBackend("buffs"), nil,
        "missing schema backend: " .. missingSchema)
    assertEqual(harness.getCreateFrameCalls(), 0,
        "missing schema CreateFrame: " .. missingSchema)
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
        hasCustomAuraContainer = false,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), false,
        "false custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil,
        "false custom backend")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 35,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), false, "AF r35 custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "AF r35 12.1 backend")
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "AF r35 12.1 legacy fallback")
end

do
    local harness = NewHarness({
        interfaceVersion = 120200,
        afVersion = 36,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), false, "12.2 legacy capability")
    assertEqual(BD.HasCustomAuraContainerCapability(), false, "unverified 12.2 custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "unverified 12.2 backend")
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "unverified 12.2 legacy fallback")
end

for _, missingMethod in ipairs(REQUIRED_CUSTOM_AF_METHODS) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
        missingCustomMethod = missingMethod,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(
        BD.HasCustomAuraContainerCapability(),
        false,
        "incomplete custom capability: " .. missingMethod
    )
    assertEqual(
        BD.GetAuraBackend("buffs"),
        nil,
        "incomplete 12.1 backend: " .. missingMethod
    )
    assertEqual(
        BD.HasAuraBackend("buffs"),
        false,
        "incomplete 12.1 availability: " .. missingMethod
    )
    harness.update()
    assertEqual(
        harness.getCreateFrameCalls(),
        0,
        "incomplete 12.1 legacy fallback: " .. missingMethod
    )
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 36,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("privateAuras"), nil, "private pane backend")
    assertEqual(BD.GetAuraBackend("invalid"), nil, "invalid pane backend")
    assertEqual(BD.HasAuraBackend("privateAuras"), false, "private pane availability")
    assertEqual(BD.HasAuraBackend("invalid"), false, "invalid pane availability")
end

print("buffs/debuffs backend selector tests passed")
