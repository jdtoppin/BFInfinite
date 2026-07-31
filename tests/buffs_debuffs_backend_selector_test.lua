local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
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
    local interfaceVersion = options.interfaceVersion or 120100
    local createFrameCalls = 0
    local customDisableCalls = {}
    local customUpdateCalls = {}
    local updateCallback

    local schema = NewSchema()
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
        return false
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
        versionNum = options.afVersion or 33,
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
    AF.RegisterCallback = function(event, callback)
        if event == "BFI_UpdateModule" then
            updateCallback = callback
        end
    end
    _G.AbstractFramework = AF

    local BD = {
        CanSuppressNativePublicAuras = function()
            return true
        end,
        SetNativePublicAurasSuppressed = function()
            return true
        end,
        RegisterEvent = function()
        end,
        UnregisterEvent = function()
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
            customUpdateCalls[#customUpdateCalls + 1] = {
                which = which,
                config = config,
            }
        end
        BD.DisableCustomAuraContainer = function(which)
            customDisableCalls[#customDisableCalls + 1] = which
        end
    end

    return {
        BD = BD,
        getCreateFrameCalls = function()
            return createFrameCalls
        end,
        customDisableCalls = customDisableCalls,
        customUpdateCalls = customUpdateCalls,
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
        afVersion = 33,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasSecureAuraHeaderBackend(), false, "12.1 legacy capability")
    assertEqual(BD.HasCustomAuraContainerCapability(), true, "12.1 custom capability")
    assertEqual(
        BD.GetAuraBackend("buffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "12.1 buffs backend"
    )
    assertEqual(
        BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "12.1 debuffs backend"
    )
    assertEqual(
        BD.GetAuraBackend(),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "12.1 aggregate backend"
    )
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "12.1 custom selector construction")
    assertEqual(#harness.customUpdateCalls, 2, "12.1 custom update count")
    assertEqual(harness.customUpdateCalls[1].which, "buffs", "12.1 custom buffs update")
    assertEqual(harness.customUpdateCalls[1].config, BD.config.buffs, "12.1 custom buffs config")
    assertEqual(harness.customUpdateCalls[2].which, "debuffs", "12.1 custom debuffs update")
    assertEqual(harness.customUpdateCalls[2].config, BD.config.debuffs, "12.1 custom debuffs config")
    assertEqual(#harness.customDisableCalls, 0, "12.1 custom disable count")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 33,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), true, "unregistered custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "unregistered 12.1 backend")
    assertEqual(BD.HasAuraBackend("buffs"), false, "unregistered 12.1 availability")
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "unregistered 12.1 legacy fallback")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 32,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomAuraContainerCapability(), false, "AF r32 custom capability")
    assertEqual(BD.GetAuraBackend("buffs"), nil, "AF r32 12.1 backend")
    harness.update()
    assertEqual(harness.getCreateFrameCalls(), 0, "AF r32 12.1 legacy fallback")
end

do
    local harness = NewHarness({
        interfaceVersion = 120200,
        afVersion = 33,
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
        afVersion = 33,
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
        afVersion = 33,
        registerCustomBackend = true,
    })
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("privateAuras"), nil, "private pane backend")
    assertEqual(BD.GetAuraBackend("invalid"), nil, "invalid pane backend")
    assertEqual(BD.HasAuraBackend("privateAuras"), false, "private pane availability")
    assertEqual(BD.HasAuraBackend("invalid"), false, "invalid pane availability")
end

print("buffs/debuffs backend selector tests passed")
