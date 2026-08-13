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
    local secretGuidMetatable = {
        __eq = function()
            error("Pet owner routing must not compare opaque GUIDs", 2)
        end,
    }
    local harness = {
        callbacks = {},
        playerInVehicle = false,
        unitExists = {
            pet = true,
            player = true,
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

    function BFI.funcs.isValueNonSecret(value)
        harness.nonSecretChecks =
            (harness.nonSecretChecks or 0) + 1
        assertEqual(
            getmetatable(value),
            secretGuidMetatable,
            "opaque GUID value"
        )
        return false
    end

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function AF.UnitClassBase()
        return "HUNTER"
    end

    function AF.WrapTextInColor(value)
        return value
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
            effectiveUnit = frame.effectiveUnit,
            force = force,
            frame = frame,
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
        UnitGUID = function()
            return setmetatable({}, secretGuidMetatable)
        end,
        UnitHasVehicleUI = function(unit)
            return unit == "player" and harness.playerInVehicle
        end,
        UnitIsPlayer = function()
            harness.unitIsPlayerCalls =
                (harness.unitIsPlayerCalls or 0) + 1
            return false
        end,
        UnitIsUnit = function()
            error("Pet owner routing must not call UnitIsUnit", 2)
        end,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        print = function()
        end,
        select = select,
        strfind = string.find,
        strmatch = string.match,
        tostring = tostring,
        wipe = function(target)
            for key in pairs(target) do
                target[key] = nil
            end
        end,
    }
    environment._G = environment

    local chunk, loadError =
        loadfile("Modules/UnitFrames/UnitButton.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local function newFrame(optIn)
        local frame = {
            attributes = {},
            eventRegistrations = {},
            hooks = {},
            registrationCalls = {},
            scripts = {},
            shown = true,
            tooltip = {
                enabled = false,
            },
            unitEventRegistrations = {},
        }

        function frame:GetName()
            return "BFI_Pet"
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

        function frame:RegisterUnitEvent(event, ...)
            local units = {...}
            self.registrationCalls[#self.registrationCalls + 1] = {
                event = event,
                units = units,
            }
            self.unitEventRegistrations[event] = {}
            for _, unit in ipairs(units) do
                self.unitEventRegistrations[event][unit] = true
            end
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
            if self.eventRegistrations[event] then
                self:DeliverEvent(event, unit, arg)
                return true
            end

            local units = self.unitEventRegistrations[event]
            if not (unit and units and units[unit]) then
                return false
            end

            self:DeliverEvent(event, unit, arg)
            return true
        end

        function frame:Tick(elapsed)
            local callback = self.scripts.OnUpdate
            assertTrue(callback, "missing OnUpdate script")
            callback(self, elapsed)
        end

        environment.BFIUnitButton_OnLoad(frame)
        frame.unit = "pet"
        frame.effectiveUnit = "pet"
        if optIn then
            frame._updateOnUnitPetChanged = "player"
        end
        return frame
    end

    function harness:ClearUpdates()
        self.updates = {}
    end

    harness.BFI = BFI
    harness.environment = environment
    harness.newFrame = newFrame
    return harness
end

local function findRegistration(frame, event)
    local found
    for _, registration in ipairs(frame.registrationCalls) do
        if registration.event == event then
            assertEqual(found, nil, event .. " duplicate registration")
            found = registration
        end
    end
    return found
end

local function assertRegistration(frame, event, ...)
    local registration = findRegistration(frame, event)
    assertTrue(registration, "missing " .. event .. " registration")
    assertEqual(
        #registration.units,
        select("#", ...),
        event .. " unit count"
    )
    for index = 1, select("#", ...) do
        assertEqual(
            registration.units[index],
            select(index, ...),
            event .. " unit " .. index
        )
    end
end

local function testPetOwnerEventRegistrationsAreOptIn()
    local harness = makeHarness()
    local pet = harness.newFrame(true)

    pet:FireHook("OnShow")

    assertRegistration(pet, "UNIT_CONNECTION", "pet")
    assertRegistration(
        pet,
        "UNIT_ENTERED_VEHICLE",
        "pet",
        "player"
    )
    assertRegistration(
        pet,
        "UNIT_EXITED_VEHICLE",
        "pet",
        "player"
    )
    assertRegistration(pet, "UNIT_PET", "player")
    assertEqual(
        harness.onButtonShowCount,
        1,
        "Pet OnShow runtime notification"
    )
    assertEqual(#harness.updates, 0, "Pet OnShow eager update count")

    local control = harness.newFrame(false)
    control:FireHook("OnShow")

    assertRegistration(control, "UNIT_CONNECTION", "pet")
    assertRegistration(control, "UNIT_ENTERED_VEHICLE", "pet")
    assertRegistration(control, "UNIT_EXITED_VEHICLE", "pet")
    assertEqual(
        findRegistration(control, "UNIT_PET"),
        nil,
        "control UNIT_PET registration"
    )
end

local function testStablePetReplacementForcesOneOpaqueRefresh()
    local harness = makeHarness()
    local pet = harness.newFrame(true)
    pet:FireHook("OnShow")

    assertTrue(
        pet:FireRegisteredEvent("UNIT_PET", "player"),
        "owner UNIT_PET delivery"
    )
    assertEqual(#harness.updates, 0, "eager owner UNIT_PET updates")

    pet:Tick(0.25)

    assertEqual(#harness.updates, 1, "owner UNIT_PET update count")
    assertEqual(harness.updates[1].frame, pet, "owner UNIT_PET frame")
    assertEqual(harness.updates[1].force, true, "owner UNIT_PET force")
    assertEqual(
        harness.updates[1].effectiveUnit,
        "pet",
        "stable replacement effective unit"
    )
    local unitIsPlayerCalls = harness.unitIsPlayerCalls
    pet:Tick(0.25)
    assertEqual(harness.nonSecretChecks, 1, "opaque GUID checks")
    assertEqual(
        harness.unitIsPlayerCalls,
        unitIsPlayerCalls,
        "secret GUID path reached UnitIsPlayer"
    )
    assertEqual(#harness.updates, 1, "owner UNIT_PET repeated update")
    assertEqual(
        pet:FireRegisteredEvent("UNIT_PET", "party1"),
        false,
        "unrelated UNIT_PET delivery"
    )
    pet:Tick(0.25)
    assertEqual(#harness.updates, 1, "unrelated UNIT_PET update")
end

local function testOwnerVehicleEventsRetargetOnce()
    local harness = makeHarness()
    local pet = harness.newFrame(true)
    pet:FireHook("OnShow")

    harness.playerInVehicle = true
    assertTrue(
        pet:FireRegisteredEvent("UNIT_ENTERED_VEHICLE", "player"),
        "owner vehicle-entry delivery"
    )
    pet:Tick(0.25)
    assertEqual(#harness.updates, 1, "owner vehicle-entry updates")
    assertEqual(
        harness.updates[1].effectiveUnit,
        "player",
        "vehicle-entry effective unit"
    )

    harness:ClearUpdates()
    pet:FireRegisteredEvent("UNIT_PET", "player")
    pet:Tick(0.25)
    assertEqual(
        #harness.updates,
        1,
        "owner/effective overlap update count"
    )
    assertEqual(
        harness.updates[1].effectiveUnit,
        "player",
        "owner/effective overlap unit"
    )

    harness:ClearUpdates()
    harness.playerInVehicle = false
    pet:FireRegisteredEvent("UNIT_EXITED_VEHICLE", "player")
    pet:Tick(0.25)
    assertEqual(#harness.updates, 1, "owner vehicle-exit updates")
    assertEqual(
        harness.updates[1].effectiveUnit,
        "pet",
        "vehicle-exit effective unit"
    )

    harness:ClearUpdates()
    pet:FireRegisteredEvent("UNIT_ENTERED_VEHICLE", "pet")
    pet:Tick(0.25)
    assertEqual(#harness.updates, 1, "primary Pet vehicle updates")
end

local function testOwnerEventsDoNotBroadenOrdinaryUnitMatching()
    local harness = makeHarness()
    local pet = harness.newFrame(true)
    pet:FireHook("OnShow")

    pet:FireRegisteredEvent("UNIT_FLAGS", "player")
    pet:FireRegisteredEvent("UNIT_NAME_UPDATE", "player")
    pet:Tick(0.25)
    assertEqual(
        #harness.updates,
        0,
        "ordinary owner events while displaying Pet"
    )

    harness.playerInVehicle = true
    pet:FireRegisteredEvent("UNIT_ENTERED_VEHICLE", "player")
    pet:Tick(0.25)
    harness:ClearUpdates()

    pet:FireRegisteredEvent("UNIT_FLAGS", "player")
    pet:Tick(0.25)
    assertEqual(
        #harness.updates,
        1,
        "effective player UNIT_FLAGS update"
    )
end

local function testHiddenAndConfigModeFramesDoNotUpdate()
    local harness = makeHarness()
    local pet = harness.newFrame(true)
    pet:FireHook("OnShow")

    pet.shown = false
    pet:DeliverEvent("UNIT_PET", "player")
    pet:Tick(0.25)
    assertEqual(#harness.updates, 0, "hidden Pet owner update")

    pet.shown = true
    pet.inConfigMode = true
    pet:DeliverEvent("UNIT_PET", "player")
    pet:Tick(0.25)
    assertEqual(#harness.updates, 0, "config-mode Pet owner update")
end

local function testHideAndReshowUseExistingButtonLifecycle()
    local harness = makeHarness()
    local pet = harness.newFrame(true)
    pet:FireHook("OnShow")

    pet:FireHook("OnHide")
    assertEqual(
        harness.onButtonHideCount,
        1,
        "Pet OnHide runtime notification"
    )
    assertEqual(
        pet:FireRegisteredEvent("UNIT_PET", "player"),
        false,
        "hidden Pet UNIT_PET delivery"
    )

    pet:FireHook("OnShow")
    assertEqual(
        harness.onButtonShowCount,
        2,
        "Pet reshow runtime notification"
    )
    assertEqual(#harness.updates, 0, "Pet reshow eager updates")
end

testPetOwnerEventRegistrationsAreOptIn()
testStablePetReplacementForcesOneOpaqueRefresh()
testOwnerVehicleEventsRetargetOnce()
testOwnerEventsDoNotBroadenOrdinaryUnitMatching()
testHiddenAndConfigModeFramesDoNotUpdate()
testHideAndReshowUseExistingButtonLifecycle()

print("unit-frame Pet owner routing tests passed")
