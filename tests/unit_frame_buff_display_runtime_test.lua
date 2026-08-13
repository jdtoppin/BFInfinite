local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copied = {}
    seen[value] = copied
    for key, child in pairs(value) do
        copied[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copied
end

local function newHarness(nativeBackendAvailable, reservationPlan)
    local UF = {}
    local BFI = {
        modules = {
            UnitFrames = UF,
        },
    }
    local harness = {
        created = {},
        events = {},
        legacyCalls = {},
    }

    _G.AbstractFramework = {
        Copy = deepCopy,
        Fire = function(event)
            harness.events[#harness.events + 1] = event
        end,
    }
    _G.CreateFrame = function(_, name, parent)
        local frame = {
            name = name,
            parent = parent,
            shown = true,
        }
        function frame:SetAllPoints(relativeTo)
            self.allPoints = relativeTo
        end
        function frame:Hide()
            self.shown = false
        end
        return frame
    end

    function UF.HasNativeAuraContainerBackend()
        return nativeBackendAvailable ~= false
    end

    if reservationPlan then
        UF.GetActiveBuffDisplayReservationPlan = reservationPlan
    end

    function UF.CreateGroupNativeAuras(...)
        harness.legacyCalls[#harness.legacyCalls + 1] = {...}
        return {legacy = true}
    end

    function UF.CreateNativeGroupAuraIndicator(
        parent,
        name,
        auraFilter,
        seed,
        options
    )
        local runtime = {
            root = parent,
            name = name,
            auraFilter = auraFilter,
            seed = seed,
            options = options,
            state = "READY",
            calls = {},
        }
        local calls = runtime.calls
        local function count(which)
            calls[which] = (calls[which] or 0) + 1
        end

        function runtime:LoadConfig(config)
            self._config = deepCopy(config)
            count("load")
        end
        function runtime:Enable()
            self.active = true
            count("enable")
        end
        function runtime:Disable()
            self.active = nil
            count("disable")
        end
        function runtime:Update(force)
            self.lastForce = force
            count("update")
        end
        function runtime:SetUnit(unit)
            self.unit = unit
            count("setUnit")
        end
        function runtime:RefreshVisibility()
            count("refreshVisibility")
        end
        function runtime:EnableConfigMode()
            self.configMode = true
            count("enableConfigMode")
        end
        function runtime:DisableConfigMode()
            self.configMode = nil
            count("disableConfigMode")
        end
        function runtime:RequiresReloadForConfig(config)
            return config and config.forceChildReload == true
        end
        function runtime:GetNativeAuraState()
            return {
                state = self.state,
                active = self.active == true,
                built = self.built == true,
                pending = self.pending == true,
                configMode = self.configMode == true,
                reloadRequired = self.reloadRequired == true,
            }
        end
        function runtime:Destroy()
            self.destroyed = true
            count("destroy")
        end

        harness.created[#harness.created + 1] = runtime
        return runtime
    end

    local chunk = assert(loadfile(
        "Modules/UnitFrames/BuffDisplayRuntime.lua"
    ))
    chunk("BFInfinite", BFI)
    return harness, UF
end

local function newParent()
    return {
        enabled = true,
        _nativeAuraContainers = {
            buffs = {key = "base"},
            buffDisplays = {
                defensives = {key = "defensives"},
                healing_auras = {key = "healing_auras"},
            },
        },
    }
end

local function newConfig()
    return {
        enabled = false,
        order = {"healing_auras", "defensives"},
        displays = {
            healing_auras = {
                id = "healing_auras",
                name = "Healing Auras",
                enabled = true,
            },
            defensives = {
                id = "defensives",
                name = "Defensives",
                enabled = false,
            },
        },
    }
end

local function boundedReservationPlan(config)
    local reserved, overflow = {}, {}
    local costs = {}
    local total = 0
    for _, id in ipairs(config.order or {}) do
        local display = config.displays[id]
        if display and display.enabled == true then
            local cost = display.reservationCost or 10
            costs[id] = cost
            if #reserved < 4 and total + cost <= 40 then
                reserved[#reserved + 1] = display
                total = total + cost
            else
                overflow[#overflow + 1] = display
            end
        end
    end
    return reserved, overflow, {
        initialReservations = total,
        initialReservationLimit = 40,
        reservationCosts = costs,
    }
end

local function testFallbackPreservesLegacyGroupBuilder()
    local harness, UF = newHarness(false)
    local parent = newParent()
    local result = UF.CreateGroupBuffDisplays(
        parent,
        "FallbackBuffs",
        "HELPFUL",
        "buffs"
    )

    assertEqual(result.legacy, true, "legacy fallback result")
    assertEqual(#harness.legacyCalls, 1, "legacy fallback call count")
    assertEqual(#harness.created, 0, "fallback must not claim seeds")
end

local function testCompositeLifecycleAndAggregateState()
    local harness, UF = newHarness(true)
    local parent = newParent()
    local manager = UF.CreateGroupBuffDisplays(
        parent,
        "CompositeBuffs",
        "HELPFUL",
        "buffs"
    )
    local base = manager._buffDisplayBase
    local healing = manager._buffDisplayRuntimes.healing_auras
    local defensives = manager._buffDisplayRuntimes.defensives

    assertEqual(#harness.created, 3, "one runtime per claimed seed")
    assertEqual(harness.created[1], base, "base seed is claimed first")
    assertEqual(harness.created[2], defensives,
        "child seed names are deterministic")
    assertEqual(harness.created[3], healing,
        "child seed names are deterministic")
    assertEqual(manager.allPoints, base, "composite follows base bounds")
    assertEqual(healing.options.includeSpellColors, false,
        "child color expansion is disabled")
    assertEqual(healing.options.includePartition, false,
        "child relation partition is disabled")

    local config = newConfig()
    manager:LoadConfig(config)
    assertEqual(manager.enabled, true,
        "enabled child keeps composite indicator enabled")
    assertEqual(base.enabled, false, "base enabled gate is independent")
    assertEqual(healing.enabled, true, "child enabled gate")
    assertEqual(defensives.enabled, false, "disabled child gate")
    assertEqual(healing._config.name, "Healing Auras",
        "child metadata remains compiler input")

    manager:Enable()
    assertEqual(base.calls.enable or 0, 0, "disabled base not enabled")
    assertEqual(healing.calls.enable, 1, "enabled child enabled")
    assertEqual(defensives.calls.enable or 0, 0,
        "disabled child not enabled")

    manager:Update(true)
    manager:SetUnit("party2")
    manager:RefreshVisibility()
    assertEqual(healing.calls.update, 1, "update fans out")
    assertEqual(healing.lastForce, true, "force flag preserved")
    assertEqual(healing.unit, "party2", "unit fans out")
    assertEqual(healing.calls.refreshVisibility, 1,
        "visibility refresh fans out")
    assertEqual(base.calls.update or 0, 0,
        "disabled base remains quiescent")

    healing.built = true
    healing.pending = true
    local state = manager:GetNativeAuraState()
    assertEqual(state.active, true, "aggregate active state")
    assertEqual(state.built, true, "aggregate built state")
    assertEqual(state.pending, true, "aggregate pending state")
    assertEqual(state.displays.healing_auras.preallocated, true,
        "claimed child state is marked preallocated")
    assertEqual(state.order[1], "healing_auras",
        "saved display order is retained")

    manager:EnableConfigMode()
    assertEqual(healing.calls.enableConfigMode, 1,
        "configured child enters config mode")
    manager:DisableConfigMode()
    assertEqual(healing.calls.disableConfigMode, 1,
        "child leaves config mode")

    manager:Disable()
    assertEqual(healing.calls.disable >= 1, true,
        "disable fans out")
    manager:Destroy()
    assertEqual(base.calls.destroy, 1, "base destroyed")
    assertEqual(healing.calls.destroy, 1, "child destroyed")
    assertEqual(defensives.calls.destroy, 1,
        "disabled child destroyed")
    assertEqual(manager.shown, false, "manager hidden on destroy")
end

local function testStructuralChangesFailClosed()
    local harness, UF = newHarness(true)
    local parent = newParent()
    local manager = UF.CreateGroupBuffDisplays(
        parent,
        "StructuralBuffs",
        "HELPFUL",
        "buffs"
    )
    local config = newConfig()
    manager:LoadConfig(config)
    manager:Enable()

    local newlyEnabled = deepCopy(config)
    newlyEnabled.order[#newlyEnabled.order + 1] = "externals"
    newlyEnabled.displays.externals = {
        name = "Externals",
        enabled = true,
    }
    assertEqual(
        manager:RequiresReloadForConfig(newlyEnabled),
        true,
        "new enabled child requires reload"
    )

    manager:LoadConfig(newlyEnabled)
    local state = manager:GetNativeAuraState()
    assertEqual(manager.enabled, false,
        "structural edit disables composite")
    assertEqual(state.state, "RELOAD_REQUIRED",
        "structural state")
    assertEqual(state.reloadRequired, true,
        "structural reload flag")
    assertEqual(state.active, false,
        "structural edit quiesces every child")
    assertEqual(state.displays.externals.preallocated, false,
        "missing child is never allocated dynamically")
    assertEqual(harness.events[1],
        "BFI_NativeAuraReloadRequired",
        "structural profile changes request a reload")

    local removed = newConfig()
    removed.displays.healing_auras = nil
    removed.order = {"defensives"}
    assertEqual(manager:RequiresReloadForConfig(removed), true,
        "removing a claimed child requires reload")
end

local function testNonStructuralEditsDelegateReloadDecision()
    local _, UF = newHarness(true)
    local manager = UF.CreateGroupBuffDisplays(
        newParent(),
        "DelegatedBuffs",
        "HELPFUL",
        "buffs"
    )
    local config = newConfig()
    manager:LoadConfig(config)

    local disabledAddition = deepCopy(config)
    disabledAddition.displays.custom_1 = {
        name = "Custom",
        enabled = false,
    }
    disabledAddition.order[#disabledAddition.order + 1] = "custom_1"
    assertEqual(
        manager:RequiresReloadForConfig(disabledAddition),
        false,
        "unallocated disabled child is configuration-only"
    )

    local childTuning = deepCopy(config)
    childTuning.displays.healing_auras.forceChildReload = true
    assertEqual(manager:RequiresReloadForConfig(childTuning), true,
        "child runtime reload result is aggregated")
end

local function testReservationOverflowStaysInertWithoutReloadLoop()
    local _, UF = newHarness(true, boundedReservationPlan)
    local parent = newParent()
    parent._nativeAuraBuffDisplayReservationCosts = {
        healing_auras = 10,
        defensives = 10,
    }
    local manager = UF.CreateGroupBuffDisplays(
        parent,
        "BoundedBuffs",
        "HELPFUL",
        "buffs"
    )
    local config = newConfig()
    config.order[#config.order + 1] = "externals"
    config.displays.externals = {
        id = "externals",
        name = "Externals",
        enabled = true,
        reservationCost = 40,
    }

    assertEqual(manager:RequiresReloadForConfig(config), false,
        "overflow alone cannot be resolved by reload")
    manager:LoadConfig(config)
    manager:Enable()
    local state = manager:GetNativeAuraState()
    assertEqual(state.state, "LIMIT_EXCEEDED",
        "aggregate overflow state")
    assertEqual(state.limitExceeded, true,
        "aggregate overflow flag")
    assertEqual(state.reloadRequired, false,
        "overflow does not request an ineffective reload")
    assertEqual(state.displays.externals.state, "LIMIT_EXCEEDED",
        "overflow display state")
    assertEqual(state.displays.externals.preallocated, false,
        "overflow display remains unallocated")
    assertEqual(
        manager._buffDisplayRuntimes.healing_auras.active,
        true,
        "admitted display remains active"
    )

    local expanded = deepCopy(config)
    expanded.displays.healing_auras.reservationCost = 20
    assertEqual(manager:RequiresReloadForConfig(expanded), true,
        "capacity growth beyond the original shell requires reload")
end

local function testEnabledHelperUsesBaseAndDirectChildren()
    local _, UF = newHarness(true)
    assertEqual(UF.HasEnabledGroupBuffDisplay({enabled = true}), true,
        "base gate")
    assertEqual(UF.HasEnabledGroupBuffDisplay(newConfig()), true,
        "direct child gate")
    assertEqual(UF.HasEnabledGroupBuffDisplay({
        enabled = false,
        displays = {
            deleted = {enabled = true, deleted = true},
        },
    }), false, "deleted children do not activate composite")
end

testFallbackPreservesLegacyGroupBuilder()
testCompositeLifecycleAndAggregateState()
testStructuralChangesFailClosed()
testNonStructuralEditsDelegateReloadDecision()
testReservationOverflowStaysInertWithoutReloadLoop()
testEnabledHelperUsesBaseAndDirectChildren()

print("unit_frame_buff_display_runtime_test: ok")
