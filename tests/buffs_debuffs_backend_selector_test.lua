local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message,
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function assertTrue(value, message)
    assertEqual(value == true, true, message)
end

local function assertLog(actual, expected, message)
    assertEqual(#actual, #expected, message .. " length")
    for index, value in ipairs(expected) do
        assertEqual(actual[index], value, message .. " " .. index)
    end
end

local function assertTransition(BD, actualBackend, desiredBackend, pending,
        message)
    assertEqual(type(BD.GetBuffsDebuffsBackendTransitionState), "function",
        message .. " transition API")
    local state = BD.GetBuffsDebuffsBackendTransitionState("debuffs")
    assertEqual(type(state), "table", message .. " transition state")
    assertEqual(state.actualBackend, actualBackend,
        message .. " actual backend")
    assertEqual(state.desiredBackend, desiredBackend,
        message .. " desired backend")
    assertEqual(state.pending == true, pending == true,
        message .. " pending")
    return state
end

local function assertNoTransition(BD, message)
    assertEqual(BD.GetBuffsDebuffsBackendTransitionState("debuffs"), nil,
        message)
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
    local harmfulSuppressionCalls = {}
    local harmfulCapabilityCalls = 0
    local callLog = {}
    local blizzardStyleDisableCalls = 0
    local blizzardStyleUpdateCalls = {}
    local blizzardStyleActive = options.blizzardStyleActive == true
    local eventCallbacks = {}
    local refreshEvents = {}
    local nextRefreshEvent = 1
    local timerCallbacks = {}
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
    _G.C_Timer = {
        After = function(delay, callback)
            assertEqual(delay, 0, "backend handoff retry delay")
            timerCallbacks[#timerCallbacks + 1] = callback
        end,
    }
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
    AF.Fire = function(event, module, which)
        refreshEvents[#refreshEvents + 1] = {
            event = event,
            module = module,
            which = which or module,
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
                enabled = options.debuffsEnabled == true,
            },
        },
    }
    if options.fullHarmfulMethods ~= false then
        BD.CanSuppressNativeHarmfulAuras = function()
            harmfulCapabilityCalls = harmfulCapabilityCalls + 1
            return options.harmfulSuppressionCapability ~= false
        end
        BD.SetNativeHarmfulAurasSuppressed = function(suppressed, unit)
            harmfulSuppressionCalls[#harmfulSuppressionCalls + 1] = {
                suppressed = suppressed,
                unit = unit,
            }
            callLog[#callLog + 1] = "harmful:"
                .. tostring(suppressed) .. ":" .. tostring(unit)
            return options.harmfulSuppressionResult ~= false
        end
    end
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
        local customState = {
            active = options.customStateActive == true,
            pending = options.customStatePending == true,
            operationPending = options.customOperationPending == true,
            editModeSuspended = options.customEditModeSuspended == true,
        }
        BD.IsCustomAuraContainerAvailable = function(which)
            return customPanes[which] == true
        end
        BD.UpdateCustomAuraContainer = function(which, config)
            if options.requireStyleInactiveBeforeCustom
                and blizzardStyleActive
            then
                error("custom backend activated before #103 released ownership")
            end
            callLog[#callLog + 1] = "customUpdate:" .. which
            customUpdateCalls[#customUpdateCalls + 1] = {
                which = which,
                config = config,
            }
            if not options.customUpdateLeavesInactive then
                customState.active = true
                customState.pending = false
                customState.operationPending = false
            end
            return options.customUpdateResult ~= false
        end
        BD.DisableCustomAuraContainer = function(which, resumeDispatcher)
            callLog[#callLog + 1] = "customDisable:" .. which
            customDisableCalls[#customDisableCalls + 1] = which
            if options.customDisableResult == false then return false end
            if which == "debuffs"
                and options.customDisableRestoresHarmful
                and (
                    customState.active
                    or customState.pending
                    or customState.operationPending
                    or customState.editModeSuspended
                )
            then
                if BD.SetNativeHarmfulAurasSuppressed(
                    false,
                    "player"
                ) ~= true then
                    if options.customDisableQueuesOnRestoreFailure then
                        customState.pending = true
                        customState.operationPending = true
                        customState.resumeDispatcher =
                            resumeDispatcher == true
                    end
                    return false
                end
            end
            if not options.customDisableLeavesState then
                customState.active = false
                customState.pending = false
                customState.operationPending = false
                customState.editModeSuspended = false
            end
            if customState.resumeDispatcher then
                customState.resumeDispatcher = false
                AF.Fire("BFI_UpdateModule", "buffsDebuffs", which)
            end
            return true
        end
        BD.GetCustomAuraContainerState = function(which)
            if customPanes[which] == true then return customState end
        end
        options.customState = customState
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
            if options.styleUpdateResult == false then return false end
            blizzardStyleActive = true
            return true
        end
        BD.DisableBlizzardDebuffStyle = function()
            callLog[#callLog + 1] = "styleDisable"
            blizzardStyleDisableCalls = blizzardStyleDisableCalls + 1
            if options.styleDisableResult == false then return false end
            blizzardStyleActive = false
            return true
        end
        BD.GetBlizzardDebuffStyleState = function()
            return {active = blizzardStyleActive}
        end
    end

    return {
        BD = BD,
        getCreateFrameCalls = function()
            return createFrameCalls
        end,
        customDisableCalls = customDisableCalls,
        customUpdateCalls = customUpdateCalls,
        harmfulSuppressionCalls = harmfulSuppressionCalls,
        getHarmfulCapabilityCalls = function()
            return harmfulCapabilityCalls
        end,
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
        isBlizzardStyleActive = function()
            return blizzardStyleActive
        end,
        refreshEvents = refreshEvents,
        getCustomState = function()
            return options.customState
        end,
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
        continueFiredUpdates = function()
            while nextRefreshEvent <= #refreshEvents do
                local event = refreshEvents[nextRefreshEvent]
                nextRefreshEvent = nextRefreshEvent + 1
                if event.event == "BFI_UpdateModule" then
                    updateCallback(nil, "buffsDebuffs", event.which)
                end
            end
        end,
        getTimerCount = function()
            return #timerCallbacks
        end,
        runTimers = function()
            local callbacks = timerCallbacks
            timerCallbacks = {}
            for _, callback in ipairs(callbacks) do
                callback()
            end
            return #callbacks
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
    }, "style aborts when custom harmful restore fails")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "failed custom restore prevents style activation")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = false,
        harmfulSuppressionResult = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = true,
        customDisableRestoresHarmful = true,
        customDisableQueuesOnRestoreFailure = true,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "opt-out handoff selects Blizzard Debuff style")
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleCapability",
        "customDisable:debuffs",
        "harmful:false:player",
    }, "first handoff stops at failed full harmful restore")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "failed controller restore cannot style Blizzard early")
    local queued = harness.getCustomState()
    assertEqual(queued.active, true,
        "failed handoff keeps the custom harmful row active")
    assertEqual(queued.pending, true,
        "failed handoff queues controller recovery")
    assertEqual(queued.operationPending, true,
        "failed handoff retains disable operation ownership")
    assertTransition(BD, BD.CUSTOM_AURA_CONTAINER_BACKEND,
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND, true,
        "failed custom-to-style restore")

    options.harmfulSuppressionResult = true
    harness.clearCallLog()
    assertEqual(BD.DisableCustomAuraContainer("debuffs"), true,
        "controller retry completes its restore-first disable")
    assertLog(harness.callLog, {
        "customDisable:debuffs",
        "harmful:false:player",
    }, "controller retry restores and hides before continuation")
    local recovered = harness.getCustomState()
    assertEqual(recovered.active, false,
        "controller retry hides the custom harmful row")
    assertEqual(recovered.pending, false,
        "controller retry clears pending recovery")
    assertEqual(recovered.operationPending, false,
        "controller retry clears disable ownership")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "controller completion alone never races style activation")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND, true,
        "controller completion refreshes actual owner before continuation")

    harness.clearCallLog()
    harness.continueFiredUpdates()
    assertLog(harness.callLog, {
        "styleCapability",
        "customDisable:debuffs",
        "native:debuffs:false",
        "styleUpdate",
    }, "dispatcher continuation applies style after controller completion")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "cross-backend handoff applies Blizzard style exactly once")
    assertEqual(#harness.harmfulSuppressionCalls, 2,
        "cross-backend handoff performs only failed and retry restores")
    assertNoTransition(BD,
        "completed custom-to-style handoff clears transition ownership")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        blizzardStyleActive = true,
        styleDisableResult = false,
        requireStyleInactiveBeforeCustom = true,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "opt-in reverse handoff selects desired custom backend")
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleDisable",
    }, "reverse handoff stops when #103 cannot release ownership")
    assertEqual(#harness.customUpdateCalls, 0,
        "failed #103 release prevents premature custom activation")
    assertEqual(harness.isBlizzardStyleActive(), true,
        "failed reverse handoff keeps #103 as actual owner")
    assertTransition(BD, BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        BD.CUSTOM_AURA_CONTAINER_BACKEND, true,
        "failed style-to-custom release")
    assertEqual(harness.getTimerCount(), 1,
        "failed reverse handoff queues one bounded continuation")

    harness.clearCallLog()
    assertEqual(harness.runTimers(), 1,
        "reverse handoff consumes its one automatic continuation")
    assertLog(harness.callLog, {
        "styleDisable",
    }, "bounded reverse continuation stops at persistent owner")
    assertEqual(harness.getTimerCount(), 0,
        "failed automatic continuation does not poll")
    assertEqual(#harness.customUpdateCalls, 0,
        "bounded failure never activates custom early")

    options.styleDisableResult = true
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleDisable",
        "native:debuffs:false",
        "customUpdate:debuffs",
    }, "reverse dispatcher continuation releases style before custom")
    assertEqual(harness.isBlizzardStyleActive(), false,
        "successful reverse continuation clears #103 ownership")
    assertEqual(#harness.customUpdateCalls, 1,
        "reverse handoff activates custom backend exactly once")
    assertEqual(#harness.harmfulSuppressionCalls, 0,
        "dispatcher delegates custom suppression to its controller")
    assertNoTransition(BD,
        "completed style-to-custom handoff clears transition ownership")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = true,
        customDisableRestoresHarmful = true,
        nativeRestoreResult = false,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    harness.update("debuffs")
    assertEqual(harness.getCustomState().active, false,
        "header-restore abort releases the custom owner first")
    assertEqual(harness.isBlizzardStyleActive(), false,
        "header-restore abort never activates #103 early")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "header-restore abort performs zero style writes")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND, true,
        "custom-to-style public restore abort")
    assertEqual(harness.getTimerCount(), 1,
        "public restore abort queues one bounded continuation")

    options.nativeRestoreResult = true
    harness.clearCallLog()
    assertEqual(harness.runTimers(), 1,
        "public restore continuation runs once after repair")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "public restore continuation applies #103 exactly once")
    assertEqual(harness.isBlizzardStyleActive(), true,
        "public restore continuation establishes #103 ownership")
    assertEqual(#harness.customUpdateCalls, 0,
        "custom-to-style repair never rebuilds the old owner")
    assertEqual(harness.getTimerCount(), 0,
        "successful public restore continuation leaves no polling timer")
    assertNoTransition(BD,
        "repaired custom-to-style public restore clears transition")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        blizzardStyleActive = true,
        nativeRestoreResult = false,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    harness.update("debuffs")
    assertEqual(harness.isBlizzardStyleActive(), false,
        "reverse public restore abort releases #103 first")
    assertEqual(#harness.customUpdateCalls, 0,
        "reverse public restore abort never activates custom early")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.CUSTOM_AURA_CONTAINER_BACKEND, true,
        "style-to-custom public restore abort")
    assertEqual(harness.getTimerCount(), 1,
        "reverse public restore abort queues one bounded continuation")

    options.nativeRestoreResult = true
    assertEqual(harness.runTimers(), 1,
        "reverse public restore continuation runs once after repair")
    assertEqual(#harness.customUpdateCalls, 1,
        "reverse public restore continuation activates custom exactly once")
    assertTrue(harness.getCustomState().active,
        "reverse public restore continuation establishes custom ownership")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        "reverse repair never restarts the old style owner")
    assertEqual(harness.getTimerCount(), 0,
        "successful reverse public restore leaves no polling timer")
    assertNoTransition(BD,
        "repaired style-to-custom public restore clears transition")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = true,
        customDisableRestoresHarmful = true,
        styleUpdateResult = false,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    harness.update("debuffs")
    assertEqual(harness.getCustomState().active, false,
        "style-update abort releases custom ownership")
    assertEqual(harness.isBlizzardStyleActive(), false,
        "failed style update leaves Blizzard default presentation")
    assertEqual(#harness.blizzardStyleUpdateCalls, 1,
        "style-update abort makes one failed style attempt")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND, true,
        "style update abort")
    assertEqual(harness.getTimerCount(), 1,
        "style update abort queues one bounded continuation")

    options.styleUpdateResult = true
    assertEqual(harness.runTimers(), 1,
        "style update continuation runs once after repair")
    assertEqual(#harness.blizzardStyleUpdateCalls, 2,
        "style update repair has one failure and one successful write")
    assertEqual(harness.isBlizzardStyleActive(), true,
        "style update repair establishes #103 ownership")
    assertEqual(#harness.customUpdateCalls, 0,
        "style update repair never rebuilds custom")
    assertEqual(harness.getTimerCount(), 0,
        "successful style update continuation leaves no polling timer")
    assertNoTransition(BD,
        "repaired style update clears transition ownership")
end

do
    local options = {
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        blizzardStyleActive = true,
        customUpdateLeavesInactive = true,
    }
    local harness = NewHarness(options)
    local BD = harness.BD

    harness.update("debuffs")
    assertEqual(#harness.customUpdateCalls, 1,
        "cold handoff reaches the custom controller once")
    assertEqual(harness.getCustomState().active, false,
        "accepted cold update can still end without custom ownership")
    assertEqual(harness.getCustomState().pending, false,
        "cold failed controller exposes no internal retry")
    assertEqual(harness.isBlizzardStyleActive(), false,
        "cold failure truthfully leaves Blizzard default active")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.CUSTOM_AURA_CONTAINER_BACKEND, true,
        "cold inactive custom failure")
    assertEqual(harness.getTimerCount(), 1,
        "cold inactive custom failure queues one bounded continuation")

    assertEqual(harness.runTimers(), 1,
        "cold inactive custom failure consumes one retry")
    assertEqual(#harness.customUpdateCalls, 2,
        "cold inactive custom failure retries exactly once")
    assertEqual(harness.getTimerCount(), 0,
        "persistent cold failure does not poll")
    assertTransition(BD, BD.BLIZZARD_DEFAULT_BACKEND,
        BD.CUSTOM_AURA_CONTAINER_BACKEND, true,
        "bounded cold inactive custom failure")
end

for _, staleStateCase in ipairs({
    {name = "active", customStateActive = true},
    {name = "pending", customStatePending = true},
    {name = "operation pending", customOperationPending = true},
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customDisableLeavesState = true,
        customStateActive = staleStateCase.customStateActive,
        customStatePending = staleStateCase.customStatePending,
        customOperationPending = staleStateCase.customOperationPending,
    })
    harness.setBackendOverride(
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {"customDisable:debuffs"},
        staleStateCase.name .. " custom state aborts style transition")
    assertEqual(#harness.blizzardStyleUpdateCalls, 0,
        staleStateCase.name .. " prevents mixed native presentation")
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
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {buffs = true},
    })
    assertEqual(
        harness.BD.GetAuraBackend("debuffs"),
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "opt-in without registered Debuffs controller falls back"
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleCapability",
        "native:debuffs:false",
        "styleUpdate",
    }, "missing Debuffs controller fallback transition")
    assertEqual(#harness.customUpdateCalls, 0,
        "missing Debuffs controller never enters custom update")
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
    assertEqual(BD.HasCustomHarmfulAuraContainerCapability(), true,
        "exact harmful suppression completes Debuffs capability")
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
        debuffsEnabled = true,
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
        debuffsEnabled = false,
        registerCustomBackend = true,
        customPanes = {debuffs = true},
    })
    local BD = harness.BD

    assertEqual(BD.HasCustomHarmfulAuraDescriptorCapability(), true,
        "complete descriptor capability")
    assertEqual(BD.HasCustomHarmfulAuraContainerCapability(), true,
        "complete harmful runtime capability")
    assertEqual(BD.GetAuraBackend("debuffs"), nil,
        "disabled Debuffs cannot select harmful runtime backend")
    harness.update("debuffs")
    assertEqual(#harness.customUpdateCalls, 0,
        "disabled descriptor performs no custom Debuffs update")
    for _, call in ipairs(harness.callLog) do
        assertEqual(call == "native:debuffs:true", false,
            "complete descriptor performs no native suppression")
    end
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
    })
    local BD = harness.BD

    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "Debuffs Enabled selects the complete harmful backend")
    assertEqual(harness.getHarmfulCapabilityCalls(), 1,
        "one backend lookup performs one harmful topology preflight")
    assertEqual(BD.HasAuraBackend("debuffs"), true,
        "opted-in harmful backend is available")
    assertEqual(harness.getHarmfulCapabilityCalls(), 2,
        "availability lookup adds one harmful topology preflight")
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleDisable",
        "native:debuffs:false",
        "customUpdate:debuffs",
    }, "custom activation restores style before controller update")
    assertEqual(#harness.customUpdateCalls, 1,
        "opted-in Debuffs custom update count")
    assertEqual(harness.customUpdateCalls[1].config, BD.config.debuffs,
        "enabled Debuffs forwards its saved configuration")
    assertEqual(harness.getHarmfulCapabilityCalls(), 3,
        "dispatcher lookup adds one harmful topology preflight")
end

for _, staleFlagCase in ipairs({
    {
        name = "stale false flag with enabled Debuffs",
        enabled = true,
        stale = false,
        expected = "custom",
    },
    {
        name = "stale true flag with disabled Debuffs",
        enabled = false,
        stale = true,
        expected = "style",
    },
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = staleFlagCase.enabled,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
    })
    harness.BD.config.debuffs.customHarmfulEnabled = staleFlagCase.stale
    local expected = staleFlagCase.expected == "custom"
        and harness.BD.CUSTOM_AURA_CONTAINER_BACKEND
        or harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND
    assertEqual(harness.BD.GetAuraBackend("debuffs"), expected,
        staleFlagCase.name .. " cannot change backend ownership")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = true,
    })
    local BD = harness.BD
    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "OOC preflight seeds harmful backend")
    harness.setCombat(true)
    harness.BD.CanSuppressNativeHarmfulAuras = function()
        return false
    end
    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "verified active harmful backend remains selected in combat")
    harness.setCombat(false)
    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.CUSTOM_AURA_CONTAINER_BACKEND,
        "active harmful ownership survives transient OOC preflight failure")
end

for _, ownershipCase in ipairs({
    {
        name = "active",
        customStateActive = true,
    },
    {
        name = "pending",
        customStatePending = true,
    },
    {
        name = "operation pending",
        customOperationPending = true,
    },
    {
        name = "Edit Mode suspended",
        customEditModeSuspended = true,
    },
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        harmfulSuppressionCapability = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = ownershipCase.customStateActive,
        customStatePending = ownershipCase.customStatePending,
        customOperationPending = ownershipCase.customOperationPending,
        customEditModeSuspended = ownershipCase.customEditModeSuspended,
    })
    assertEqual(harness.BD.GetAuraBackend("debuffs"),
        harness.BD.CUSTOM_AURA_CONTAINER_BACKEND,
        ownershipCase.name
            .. " ownership survives transient harmful preflight failure")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        harmfulSuppressionCapability = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
    })
    assertEqual(harness.BD.GetAuraBackend("debuffs"),
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "cold inactive preflight failure selects Blizzard style")
end

do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = false,
        harmfulSuppressionCapability = false,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
        customStateActive = true,
        customDisableRestoresHarmful = true,
    })
    local BD = harness.BD
    assertEqual(BD.GetAuraBackend("debuffs"),
        BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        "disabled Debuffs select Blizzard style despite custom ownership")
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleCapability",
        "customDisable:debuffs",
        "harmful:false:player",
        "native:debuffs:false",
        "styleUpdate",
    }, "opt-out restores full harmful owner before style update")
end

for _, suppressionCase in ipairs({
    {
        name = "missing full harmful methods",
        fullHarmfulMethods = false,
    },
    {
        name = "failed full harmful preflight",
        harmfulSuppressionCapability = false,
    },
}) do
    local harness = NewHarness({
        interfaceVersion = 120100,
        afVersion = 42,
        debuffsEnabled = true,
        fullHarmfulMethods = suppressionCase.fullHarmfulMethods,
        harmfulSuppressionCapability =
            suppressionCase.harmfulSuppressionCapability,
        registerCustomBackend = true,
        registerBlizzardDebuffStyle = true,
        customPanes = {debuffs = true},
    })
    assertEqual(
        harness.BD.HasCustomHarmfulAuraContainerCapability(),
        false,
        suppressionCase.name .. " capability"
    )
    assertEqual(
        harness.BD.GetAuraBackend("debuffs"),
        harness.BD.BLIZZARD_DEBUFF_STYLE_BACKEND,
        suppressionCase.name .. " falls back to Blizzard style"
    )
    harness.clearCallLog()
    harness.update("debuffs")
    assertLog(harness.callLog, {
        "styleCapability",
        "customDisable:debuffs",
        "native:debuffs:false",
        "styleUpdate",
    }, suppressionCase.name .. " fallback transition")
    assertEqual(#harness.customUpdateCalls, 0,
        suppressionCase.name .. " performs no custom update")
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
        debuffsEnabled = true,
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
