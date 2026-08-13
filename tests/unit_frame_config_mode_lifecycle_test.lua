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
        events = {},
        inCombat = false,
    }
    local UF = {}
    local AF = {
        player = {
            class = "MAGE",
        },
    }

    local function record(name, ...)
        harness.events[#harness.events + 1] = {
            name = name,
            args = {...},
        }
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    local function dummy()
        return 1
    end

    local function newIndicator(name, enabled)
        local indicator = {
            enabled = enabled,
            name = name,
        }

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

    local function newFrame(name, unit, enabled)
        local frame = {
            attributes = {
                unit = unit,
            },
            effectiveUnit = unit,
            enabled = enabled,
            indicators = {},
            mouseEnabled = true,
            name = name,
            shown = true,
            unit = unit,
        }

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
            if key == "unit" then
                self.unit = value
                self.effectiveUnit = value
            end
            record(
                "frame.attribute",
                self,
                key,
                value,
                self.inConfigMode
            )
        end

        function frame:EnableMouse(enabledMouse)
            self.mouseEnabled = enabledMouse
            record("frame.mouse", self, enabledMouse)
        end

        function frame:Show()
            self.shown = true
            record("frame.show", self)
        end

        function frame:Hide()
            self.shown = false
            record("frame.hide", self)
        end

        return frame
    end

    local function RegisterUnitWatch(frame)
        record(
            "watch.register",
            frame,
            frame.unit,
            frame.inConfigMode,
            frame.enabled,
            frame.shown
        )
        frame.unitWatchRegistered = true
        frame:Show()
    end

    local function UnregisterUnitWatch(frame)
        record("watch.unregister", frame, frame.unit)
        frame.unitWatchRegistered = false
    end

    local function RegisterAttributeDriver(frame, key, value)
        record(
            "driver.register",
            frame,
            key,
            value,
            frame.inConfigMode,
            frame.enabled
        )
        frame.driverRegistered = true
        frame:Show()
    end

    local function UnregisterAttributeDriver(frame)
        record("driver.unregister", frame)
        frame.driverRegistered = false
    end

    local spell = {}
    function spell:ContinueOnSpellLoad()
    end
    function spell:GetSpellName()
        return "Test Spell"
    end
    function spell:GetSpellTexture()
        return 1
    end

    local Spell = {}
    function Spell:CreateFromSpellID()
        return spell
    end

    local function strsplit(delimiter, value)
        local startIndex, endIndex = value:find(delimiter, 1, true)
        if not startIndex then return value end
        return value:sub(1, startIndex - 1), value:sub(endIndex + 1)
    end

    local BFI = {
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        GetRaidTargetIndex = dummy,
        GetTime = dummy,
        InCombatLockdown = function()
            return harness.inCombat
        end,
        RegisterAttributeDriver = RegisterAttributeDriver,
        RegisterUnitWatch = RegisterUnitWatch,
        Spell = Spell,
        UnitCastingInfo = dummy,
        UnitFactionGroup = dummy,
        UnitGUID = dummy,
        UnitGetTotalAbsorbs = dummy,
        UnitGetTotalHealAbsorbs = dummy,
        UnitHasVehicleUI = dummy,
        UnitHealth = dummy,
        UnitHealthMax = dummy,
        UnitIsUnit = dummy,
        UnitPower = dummy,
        UnitPowerMax = dummy,
        UnitStagger = dummy,
        UnregisterAttributeDriver = UnregisterAttributeDriver,
        UnregisterUnitWatch = UnregisterUnitWatch,
        error = error,
        next = next,
        pairs = pairs,
        random = function()
            return 50
        end,
        select = select,
        strsplit = strsplit,
        tinsert = table.insert,
        tostring = tostring,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected ConfigMode global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError = loadfile("Modules/UnitFrames/ConfigMode.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.AF = AF
    harness.BFI = BFI
    harness.UF = UF
    harness.newFrame = newFrame
    harness.newIndicator = newIndicator

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

    function harness:LastEvent(name)
        for index = #self.events, 1, -1 do
            if self.events[index].name == name then
                return self.events[index]
            end
        end
    end

    return harness
end

local function createBossGroup(harness)
    local child = harness.newFrame("Boss1", "boss1", true)
    local enabledIndicator =
        harness.newIndicator("enabled", true)
    local disabledIndicator =
        harness.newIndicator("disabled", false)
    child.indicators = {
        enabled = enabledIndicator,
        disabled = disabledIndicator,
    }
    child.unitWatchRegistered = true

    local container = harness.newFrame("Boss", nil, true)
    container.driverKey = "state-visibility"
    container.driverValue = "[@boss1,exists] show;hide"
    container.driverRegistered = true

    harness.UF.AddToConfigMode("boss", child)
    harness.UF.AddToConfigMode("boss.container", container)
    return child, container, enabledIndicator, disabledIndicator
end

local function testEnabledExitRestoresRealUnitBeforeWatch()
    local harness = makeHarness()
    local child, container, enabledIndicator, disabledIndicator =
        createBossGroup(harness)
    local toggle = harness.callbacks.BFI_ConfigMode

    toggle(nil, "unitFrames", "boss", true)
    assertEqual(child.unit, "player", "config-mode preview unit")
    assertEqual(child.oldUnit, "boss1", "config-mode saved unit")
    assertEqual(child.inConfigMode, true, "child config-mode state")
    assertEqual(container.inConfigMode, true,
        "container config-mode state")
    assertEqual(child.mouseEnabled, false, "config-mode mouse state")
    assertEqual(enabledIndicator.enableConfigModeCount, 1,
        "enabled indicator config-mode entry")
    assertEqual(disabledIndicator.enableConfigModeCount, 1,
        "disabled indicator config-mode entry")

    harness:ClearEvents()
    toggle(nil, "unitFrames", "boss", false)

    assertEqual(enabledIndicator.disableConfigModeCount, 1,
        "enabled indicator config-mode exit")
    assertEqual(disabledIndicator.disableConfigModeCount, 1,
        "disabled indicator config-mode exit")
    assertEqual(child.unit, "boss1", "restored child unit")
    assertEqual(child.effectiveUnit, "boss1",
        "restored effective unit")
    assertEqual(child.oldUnit, nil, "cleared saved unit")
    assertEqual(child.inConfigMode, nil, "cleared child config mode")
    assertEqual(container.inConfigMode, nil,
        "cleared container config mode")
    assertEqual(child.mouseEnabled, true, "restored mouse state")
    assertEqual(child.unitWatchRegistered, true,
        "restored child unit watch")
    assertEqual(container.driverRegistered, true,
        "restored container driver")

    local attribute = harness:LastEvent("frame.attribute")
    assertEqual(attribute.args[3], "boss1",
        "unit restored to real token")
    assertEqual(attribute.args[4], nil,
        "unit restored while still in config mode")

    local watch = harness:LastEvent("watch.register")
    assertEqual(watch.args[2], "boss1",
        "unit watch registered for real token")
    assertEqual(watch.args[3], nil,
        "unit watch registered during config mode")
    assertEqual(watch.args[4], true,
        "enabled frame watch state")
    assertEqual(watch.args[5], false,
        "watch did not own initial visibility")

    local driver = harness:LastEvent("driver.register")
    assertEqual(driver.args[4], nil,
        "driver registered during config mode")
    assertEqual(driver.args[5], true,
        "enabled container driver state")
end

local function testDisabledExitStaysUnregisteredAndHidden()
    local harness = makeHarness()
    local child, container, enabledIndicator, disabledIndicator =
        createBossGroup(harness)
    local toggle = harness.callbacks.BFI_ConfigMode

    toggle(nil, "unitFrames", "boss", true)

    child.enabled = false
    container.enabled = false
    enabledIndicator.enabled = false
    disabledIndicator.enabled = false
    child:Hide()
    container:Hide()

    harness:ClearEvents()
    toggle(nil, "unitFrames", "boss", false)

    assertEqual(enabledIndicator.disableConfigModeCount, 1,
        "disabled enabled-indicator teardown")
    assertEqual(disabledIndicator.disableConfigModeCount, 1,
        "disabled indicator teardown")
    assertEqual(child.unit, "boss1", "disabled restored unit")
    assertEqual(child.inConfigMode, nil,
        "disabled child config-mode state")
    assertEqual(container.inConfigMode, nil,
        "disabled container config-mode state")
    assertEqual(child.shown, false, "disabled child visibility")
    assertEqual(container.shown, false,
        "disabled container visibility")
    assertEqual(child.unitWatchRegistered, false,
        "disabled child unit watch")
    assertEqual(container.driverRegistered, false,
        "disabled container driver")
    assertEqual(harness:CountEvents("watch.register"), 0,
        "disabled child watch registrations")
    assertEqual(harness:CountEvents("driver.register"), 0,
        "disabled container driver registrations")
end

local function testToggleGuards()
    local harness = makeHarness()
    local child = createBossGroup(harness)
    local toggle = harness.callbacks.BFI_ConfigMode

    toggle(nil, "nameplates", "boss", true)
    assertEqual(child.inConfigMode, nil,
        "unrelated module config-mode entry")

    harness.inCombat = true
    toggle(nil, "unitFrames", "boss", true)
    assertEqual(child.inConfigMode, nil, "combat config-mode entry")
end

testEnabledExitRestoresRealUnitBeforeWatch()
testDisabledExitStaysUnregisteredAndHidden()
testToggleGuards()

print("unit_frame_config_mode_lifecycle_test.lua: ok")
