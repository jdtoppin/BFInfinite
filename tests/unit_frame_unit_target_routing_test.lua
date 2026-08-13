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

local function makeHarness()
    local harness = {
        callbacks = {},
        unitExists = {
            targettarget = true,
        },
        updates = {},
    }
    local UF = {}
    local AF = {}
    local BFI = {
        funcs = {},
        modules = {
            UnitFrames = UF,
        },
        vars = {},
    }

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function AF.UnitClassBase()
        return "MAGE"
    end

    function UF.OnButtonHide()
        harness.onButtonHideCount =
            (harness.onButtonHideCount or 0) + 1
    end

    function UF.OnButtonShow()
        harness.onButtonShowCount =
            (harness.onButtonShowCount or 0) + 1
    end

    function UF.UpdateIndicators(frame, force)
        harness.updates[#harness.updates + 1] = {
            frame = frame,
            force = force,
        }
    end

    function UF.GetPublicUnitIdentityValue(value)
        return value, true
    end

    function UF.GetPublicUnitIdentitySnapshot(unit)
        return {
            name = unit,
            class = "MAGE",
            guid = harness.unitExists[unit]
                and "guid-" .. unit
                or nil,
            isPlayer = false,
            inVehicle = false,
        }
    end

    local environment = {
        _G = false,
        AbstractFramework = AF,
        GetTime = function()
            return 0
        end,
        GetUnitName = function(unit)
            return unit
        end,
        Mixin = function(target, mixin)
            for key, value in pairs(mixin) do
                target[key] = value
            end
            return target
        end,
        PingableType_UnitFrameMixin = {},
        UnitExists = function(unit)
            return harness.unitExists[unit] == true
        end,
        UnitGUID = function(unit)
            if harness.unitExists[unit] then
                return "guid-" .. unit
            end
        end,
        UnitHasVehicleUI = function()
            return false
        end,
        UnitIsPlayer = function()
            return false
        end,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        select = select,
        tostring = tostring,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            if key == "UnitIsUnit" then
                error(
                    "UnitButton UNIT_TARGET routing must not reference UnitIsUnit",
                    2
                )
            end
            error("unexpected UnitButton global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/UnitButton.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local function newFrame()
        local frame = {
            attributes = {},
            eventRegistrations = {},
            hooks = {},
            scripts = {},
            shown = true,
            unitEventRegistrations = {},
        }

        function frame:GetName()
            return "BFI_TargetTarget"
        end

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
        end

        function frame:RegisterForClicks(...)
            self.clickRegistration = {...}
        end

        function frame:SetScript(script, callback)
            self.scripts[script] = callback
        end

        function frame:HookScript(script, callback)
            self.hooks[script] = callback
        end

        function frame:RegisterEvent(event)
            self.eventRegistrations[event] = true
        end

        function frame:RegisterUnitEvent(event, unit)
            self.unitEventRegistrations[event] =
                self.unitEventRegistrations[event] or {}
            self.unitEventRegistrations[event][unit] = true
        end

        function frame:UnregisterAllEvents()
            self.eventRegistrations = {}
            self.unitEventRegistrations = {}
        end

        function frame:IsVisible()
            return self.shown
        end

        function frame:FireHook(script)
            local callback = self.hooks[script]
            assertTrue(callback, "missing " .. script .. " hook")
            callback(self)
        end

        function frame:DeliverEvent(event, unit, arg)
            local callback = self.scripts.OnEvent
            assertTrue(callback, "missing OnEvent script")
            callback(self, event, unit, arg)
        end

        function frame:FireRegisteredEvent(event, unit, arg)
            if unit ~= nil then
                local units = self.unitEventRegistrations[event]
                if not (units and units[unit]) then
                    return false
                end
            elseif not self.eventRegistrations[event] then
                return false
            end

            self:DeliverEvent(event, unit, arg)
            return true
        end

        environment.BFIUnitButton_OnLoad(frame)
        frame.unit = "targettarget"
        frame.effectiveUnit = "targettarget"
        frame._updateOnPlayerTargetChanged = true
        frame._updateOnUnitTargetChanged = "target"
        return frame
    end

    harness.BFI = BFI
    harness.environment = environment
    harness.newFrame = newFrame

    function harness:ClearUpdates()
        self.updates = {}
    end

    return harness
end

local function testOnShowRegistersDerivedUnitRoutes()
    local harness = makeHarness()
    local frame = harness.newFrame()

    frame:FireHook("OnShow")

    assertTrue(
        frame.eventRegistrations.PLAYER_TARGET_CHANGED,
        "targettarget should register PLAYER_TARGET_CHANGED"
    )
    assertTrue(
        frame.unitEventRegistrations.UNIT_TARGET
            and frame.unitEventRegistrations.UNIT_TARGET.target,
        "targettarget should register UNIT_TARGET for target"
    )
    assertEqual(
        harness.onButtonShowCount,
        1,
        "OnShow should notify the shared unit-frame runtime"
    )
    assertEqual(
        #harness.updates,
        0,
        "OnShow should not perform an eager indicator update"
    )
end

local function testBothSignalsForceVisibleExistingDerivedUnit()
    local harness = makeHarness()
    local frame = harness.newFrame()
    frame:FireHook("OnShow")

    assertTrue(
        frame:FireRegisteredEvent("PLAYER_TARGET_CHANGED"),
        "PLAYER_TARGET_CHANGED should be delivered"
    )
    assertEqual(#harness.updates, 1, "player target update count")
    assertEqual(
        harness.updates[1].frame,
        frame,
        "player target update frame"
    )
    assertEqual(
        harness.updates[1].force,
        true,
        "player target update should be forced"
    )

    harness:ClearUpdates()
    assertTrue(
        frame:FireRegisteredEvent("UNIT_TARGET", "target"),
        "target UNIT_TARGET should be delivered"
    )
    assertEqual(#harness.updates, 1, "unit target update count")
    assertEqual(
        harness.updates[1].frame,
        frame,
        "unit target update frame"
    )
    assertEqual(
        harness.updates[1].force,
        true,
        "unit target update should be forced"
    )
end

local function testWrongUnitTargetRouteIsNotDelivered()
    local harness = makeHarness()
    local frame = harness.newFrame()
    frame:FireHook("OnShow")

    assertEqual(
        frame:FireRegisteredEvent("UNIT_TARGET", "focus"),
        false,
        "unit-event registration should reject another unit"
    )
    assertEqual(
        #harness.updates,
        0,
        "another unit's target change must not update targettarget"
    )
end

local function testNonexistentDerivedUnitDoesNotUpdate()
    local harness = makeHarness()
    local frame = harness.newFrame()
    frame:FireHook("OnShow")
    harness.unitExists.targettarget = false

    frame:FireRegisteredEvent("PLAYER_TARGET_CHANGED")
    frame:FireRegisteredEvent("UNIT_TARGET", "target")

    assertEqual(
        #harness.updates,
        0,
        "a nonexistent targettarget must not update"
    )
end

local function testHiddenOrConfigModeFrameDoesNotUpdate()
    local harness = makeHarness()
    local frame = harness.newFrame()
    frame:FireHook("OnShow")

    frame.shown = false
    frame:DeliverEvent("PLAYER_TARGET_CHANGED")
    frame:DeliverEvent("UNIT_TARGET", "target")
    assertEqual(
        #harness.updates,
        0,
        "a hidden targettarget must not update"
    )

    frame.shown = true
    frame.inConfigMode = true
    frame:DeliverEvent("PLAYER_TARGET_CHANGED")
    frame:DeliverEvent("UNIT_TARGET", "target")
    assertEqual(
        #harness.updates,
        0,
        "a config-mode targettarget must not update"
    )
end

testOnShowRegistersDerivedUnitRoutes()
testBothSignalsForceVisibleExistingDerivedUnit()
testWrongUnitTargetRouteIsNotDelivered()
testNonexistentDerivedUnitDoesNotUpdate()
testHiddenOrConfigModeFrameDoesNotUpdate()

print("unit-frame UNIT_TARGET routing tests passed")
