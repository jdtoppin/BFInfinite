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

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local function makeHarness(build)
    local harness = {
        events = {},
        indicatorEnables = 0,
        indicatorUpdates = 0,
        guidByUnit = {},
        rangeByUnit = {},
        rangeQueries = {},
        vehicleByUnit = {},
    }
    local UF = {}
    local AF = {}
    local F = {}

    local function record(name, ...)
        harness.events[#harness.events + 1] = {
            name = name,
            args = {...},
        }
    end

    function F.isValueNonSecret()
        return true
    end

    function AF.AddToPixelUpdater_Auto()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbackEvent = event
        harness.callback = callback
    end

    function AF.UnitClassBase()
        return "MAGE"
    end

    function UF.OnButtonHide(frame)
        for _, indicator in pairs(frame.indicators) do
            if indicator.enabled then
                indicator:Disable()
            end
        end
        record("indicators.hide", frame)
    end

    function UF.OnButtonShow(frame)
        for _, indicator in pairs(frame.indicators) do
            if indicator.enabled then
                indicator:Enable()
            end
        end
        record("indicators.show", frame, frame.effectiveUnit)
    end

    function UF.UpdateIndicators(frame, force)
        for _, indicator in pairs(frame.indicators) do
            if indicator.enabled then
                indicator:Update(force)
            end
        end
        record(
            "indicators.update",
            frame,
            frame.effectiveUnit,
            force
        )
    end

    local BFI = {
        funcs = F,
        modules = {
            UnitFrames = UF,
        },
        vars = {},
    }

    local environment = {
        _G = false,
        AbstractFramework = AF,
        BFI = BFI,
        GameTooltip = {
            Hide = function()
            end,
        },
        GameTooltip_SetDefaultAnchor = function()
        end,
        C_CurveUtil = {
            EvaluateColorValueFromBoolean = function(
                value,
                valueIfTrue,
                valueIfFalse
            )
                if value then return valueIfTrue end
                return valueIfFalse
            end,
        },
        GetBuildInfo = function()
            return "12.1.0", "68914", "Aug 2026", build or 120100
        end,
        GetTime = function()
            return 1
        end,
        GetUnitName = function(unit)
            return "Name-" .. tostring(unit)
        end,
        Mixin = function(target, mixin)
            for key, value in pairs(mixin) do
                target[key] = value
            end
            return target
        end,
        PingableType_UnitFrameMixin = {},
        UnitExists = function()
            return true
        end,
        UnitGUID = function(unit)
            return harness.guidByUnit[unit]
                or "GUID-" .. tostring(unit)
        end,
        UnitHasVehicleUI = function(unit)
            return harness.vehicleByUnit[unit] or false
        end,
        UnitIsPlayer = function()
            return true
        end,
        UnitIsUnit = function(left, right)
            return left == right
        end,
        UnitInRange = function(unit)
            harness.rangeQueries[#harness.rangeQueries + 1] = unit
            local range = harness.rangeByUnit[unit]
            if range then
                return range.inRange, range.checkedRange
            end
            return true, true
        end,
        error = error,
        next = next,
        pairs = pairs,
        print = print,
        select = select,
        strfind = string.find,
        strmatch = string.match,
        tostring = tostring,
        wipe = function(value)
            for key in pairs(value) do
                value[key] = nil
            end
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error(
                "unexpected UnitButton global: " .. tostring(key),
                2
            )
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/UnitButton.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local function newFrame(name, unit, deferred)
        local frame = {
            attributes = {},
            effectiveUnit = unit,
            name = name,
            oorAlpha = 0.45,
            registeredUnitEvents = {},
            scripts = {},
            shown = false,
            unit = unit,
            _deferUpdateOnUnitChange = deferred,
            _enableUnitButtonMapping = deferred,
        }

        function frame:GetName()
            return self.name
        end

        function frame:HookScript(scriptName, callback)
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

        function frame:IsVisible()
            return self.shown
        end

        function frame:RegisterEvent(event)
            record("event.register", self, event)
        end

        function frame:RegisterForClicks(...)
            self.clicks = {...}
        end

        function frame:RegisterUnitEvent(event, eventUnit, ...)
            record("unit-event.register", self, event, eventUnit)
            local tokens = self.registeredUnitEvents[event]
            if not tokens then
                tokens = {}
                self.registeredUnitEvents[event] = tokens
            end
            tokens[#tokens + 1] = eventUnit
            for _, additionalUnit in ipairs({...}) do
                tokens[#tokens + 1] = additionalUnit
            end
        end

        function frame:UnregisterEvent(event)
            record("event.unregister", self, event)
            self.registeredUnitEvents[event] = nil
        end

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
            local callback = self.scripts.OnAttributeChanged
            if callback then
                callback(self, key, value)
            end
        end

        function frame:SetAlpha(alpha)
            self.alpha = alpha
            record("alpha.set", self, alpha)
        end

        function frame:SetScript(scriptName, callback)
            self.scripts[scriptName] = callback
        end

        function frame:Show()
            if self.shown then return end
            self.shown = true
            local callback = self.scripts.OnShow
            if callback then callback(self) end
        end

        function frame:Hide()
            if not self.shown then return end
            self.shown = false
            local callback = self.scripts.OnHide
            if callback then callback(self) end
        end

        function frame:Tick(elapsed)
            local callback = self.scripts.OnUpdate
            if callback then callback(self, elapsed or 0.25) end
        end

        function frame:FireEvent(event, ...)
            local callback = self.scripts.OnEvent
            if callback then callback(self, event, ...) end
        end

        function frame:UnregisterAllEvents()
            record("events.unregister-all", self)
            self.registeredUnitEvents = {}
        end

        environment.BFIUnitButton_OnLoad(frame)
        local indicator = {
            enabled = true,
            root = frame,
        }

        function indicator:Disable()
            self.boundUnit = nil
            record("indicator.disable", self)
        end

        function indicator:Enable()
            self.boundUnit = self.root.effectiveUnit
            harness.indicatorEnables =
                harness.indicatorEnables + 1
            record("indicator.enable", self, self.boundUnit)
        end

        function indicator:Update(force)
            harness.indicatorUpdates =
                harness.indicatorUpdates + 1
            record(
                "indicator.update",
                self,
                self.root.effectiveUnit,
                force
            )
        end

        frame.bindingIndicator = indicator
        frame.indicators.binding = indicator
        frame.attributes.unit = unit
        return frame
    end

    function harness:ClearEvents()
        self.events = {}
        self.indicatorEnables = 0
        self.indicatorUpdates = 0
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

    function harness:LastUnitRegistration()
        for index = #self.events, 1, -1 do
            local event = self.events[index]
            if event.name == "unit-event.register" then
                return event
            end
        end
    end

    function harness:CountUnitEventRegistrations(eventName, eventUnit)
        local count = 0
        for _, event in ipairs(self.events) do
            if event.name == "unit-event.register"
                and event.args[2] == eventName
                and event.args[3] == eventUnit
            then
                count = count + 1
            end
        end
        return count
    end

    function harness:GetUnitEventTokens(frame, eventName)
        return frame.registeredUnitEvents[eventName] or {}
    end

    function harness:SetRange(unit, inRange, checkedRange)
        self.rangeByUnit[unit] = {
            checkedRange = checkedRange,
            inRange = inRange,
        }
    end

    function harness:SetVehicle(unit, enabled)
        self.vehicleByUnit[unit] = enabled or nil
    end

    function harness:ClearRangeQueries()
        self.rangeQueries = {}
    end

    harness.BFI = BFI
    harness.newFrame = newFrame
    return harness
end

local function assertRangeRegistration(harness, frame, expectedUnit, message)
    local tokens = harness:GetUnitEventTokens(
        frame,
        "UNIT_IN_RANGE_UPDATE"
    )
    assertEqual(#tokens, 1, (message or "range") .. " registration count")
    assertEqual(tokens[1], expectedUnit,
        (message or "range") .. " registration token")
end

local function assertUnitEventTokens(
    harness,
    frame,
    eventName,
    expected,
    message
)
    local tokens = harness:GetUnitEventTokens(frame, eventName)
    assertEqual(#tokens, #expected,
        (message or eventName) .. " token count")
    for index, unit in ipairs(expected) do
        assertEqual(tokens[index], unit,
            (message or eventName) .. " token " .. index)
    end
end

local function testVisibleHeaderReassignmentIsDeferred()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_PartyHeaderUnitButton1", "party1", true)

    harness.guidByUnit.party1 = "GUID-SAME-PLAYER"
    harness.guidByUnit.party2 = "GUID-SAME-PLAYER"
    harness:SetRange("party1", true, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "party1", "initial")
    assertEqual(frame.alpha, 1, "initial in-range alpha")
    frame:Tick()
    frame:Tick()
    assertEqual(harness.BFI.vars.units.party1, frame,
        "initial unit-button mapping")

    harness:ClearEvents()
    frame:SetAttribute("unit", "party2")

    assertEqual(frame.unit, "party2", "reassigned unit")
    assertEqual(frame.effectiveUnit, "party2",
        "reassigned effective unit")
    assertEqual(frame._unitChangeUpdatePending, true,
        "deferred update marker")
    assertEqual(harness.BFI.vars.units.party1, nil,
        "cleared old unit-button mapping")
    assertEqual(frame.__unitGuid, nil,
        "cleared old unit GUID")
    assertEqual(harness.indicatorEnables, 0,
        "attribute handler indicator enables")
    assertEqual(harness.indicatorUpdates, 0,
        "attribute handler indicator updates")
    assertEqual(harness:CountEvents("events.unregister-all"), 0,
        "attribute handler event rebinding")
    assertRangeRegistration(harness, frame, "party1",
        "deferred old-token")

    harness:SetRange("party2", false, true)
    frame:Tick()

    assertEqual(frame._unitChangeUpdatePending, nil,
        "cleared deferred marker")
    assertEqual(harness:CountEvents("events.unregister-all"), 1,
        "deferred event rebinding")
    assertEqual(harness.indicatorEnables, 1,
        "deferred indicator rebind")
    assertEqual(frame.bindingIndicator.boundUnit, "party2",
        "deferred indicator unit")
    assertEqual(harness.indicatorUpdates, 0,
        "deferred update-only path")
    local registration = harness:LastUnitRegistration()
    assertTrue(registration, "deferred unit-event registration")
    assertEqual(registration.args[3], "party2",
        "deferred unit-event token")
    assertRangeRegistration(harness, frame, "party2",
        "deferred latest-token")
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party2"
        ),
        1,
        "deferred latest range registration count"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party1"
        ),
        0,
        "deferred stale range registration"
    )
    assertEqual(frame.alpha, 0.45, "deferred out-of-range alpha")

    frame:Tick()
    assertEqual(
        harness.BFI.vars.units.party2,
        frame,
        "deferred unit-button mapping"
    )
end

local function testHiddenHeaderReassignmentUsesOnShow()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_RaidHeaderUnitButton1", "raid1", true)

    harness:SetRange("raid1", true, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "raid1", "initial hidden")
    frame:Hide()
    harness:ClearEvents()
    frame:SetAttribute("unit", "raid2")
    assertEqual(frame._unitChangeUpdatePending, true,
        "hidden reassignment marker")

    harness:SetRange("raid2", false, true)
    frame:Show()

    assertEqual(frame._unitChangeUpdatePending, nil,
        "OnShow cleared deferred marker")
    assertEqual(frame.effectiveUnit, "raid2",
        "OnShow effective unit")
    assertEqual(harness.indicatorEnables, 1,
        "OnShow indicator enable")
    assertEqual(frame.bindingIndicator.boundUnit, "raid2",
        "OnShow indicator unit")
    assertEqual(harness.indicatorUpdates, 0,
        "OnShow duplicate indicator update")
    assertEqual(harness:CountEvents("events.unregister-all"), 1,
        "OnShow duplicate event reset")
    local registration = harness:LastUnitRegistration()
    assertTrue(registration, "OnShow unit-event registration")
    assertEqual(registration.args[3], "raid2",
        "OnShow unit-event token")
    assertRangeRegistration(harness, frame, "raid2", "OnShow latest-token")
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "raid2"
        ),
        1,
        "OnShow latest range registration count"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "raid1"
        ),
        0,
        "OnShow stale range registration"
    )
    assertEqual(frame.alpha, 0.45, "OnShow out-of-range alpha")
end

local function testRapidReassignmentsCoalesceOnLatestUnit()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_PartyHeaderUnitButton2", "party1", true)

    harness:SetRange("party1", true, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "party1", "initial coalesced")
    harness:ClearEvents()
    frame:SetAttribute("unit", "party2")
    frame:SetAttribute("unit", "party3")
    harness:SetRange("party3", false, true)
    frame:Tick()

    assertEqual(frame.unit, "party3", "coalesced unit")
    assertEqual(frame.effectiveUnit, "party3",
        "coalesced effective unit")
    assertEqual(harness:CountEvents("events.unregister-all"), 1,
        "coalesced event rebind count")
    assertEqual(harness.indicatorEnables, 1,
        "coalesced indicator rebind count")
    assertEqual(frame.bindingIndicator.boundUnit, "party3",
        "coalesced indicator unit")
    assertEqual(harness.indicatorUpdates, 0,
        "coalesced update-only count")
    local registration = harness:LastUnitRegistration()
    assertTrue(registration, "coalesced unit-event registration")
    assertEqual(registration.args[3], "party3",
        "coalesced unit-event token")
    assertRangeRegistration(harness, frame, "party3",
        "coalesced latest-token")
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party3"
        ),
        1,
        "coalesced latest range registration count"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party2"
        ),
        0,
        "coalesced intermediate range registration"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party1"
        ),
        0,
        "coalesced stale range registration"
    )
    assertEqual(frame.alpha, 0.45, "coalesced out-of-range alpha")
end

local function testRangeEventRequeriesInsteadOfReadingPayload()
    local harness = makeHarness()
    local frame = harness.newFrame("BFI_Target", "target", false)

    harness:SetRange("target", false, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "target", "event initial")
    assertEqual(frame.alpha, 0.45, "event initial alpha")

    harness:ClearRangeQueries()
    frame:Tick()
    assertEqual(#harness.rangeQueries, 0,
        "ordinary 0.25-second tick must not poll range")

    harness:ClearRangeQueries()
    harness:SetRange("target", true, false)
    frame:FireEvent("UNIT_IN_RANGE_UPDATE", "target", false)
    assertEqual(frame.alpha, 1,
        "unchecked range must restore full alpha from a re-query")
    assertEqual(#harness.rangeQueries, 1, "event range query count")
    assertEqual(harness.rangeQueries[1], "target", "event range query unit")

    harness:ClearRangeQueries()
    harness:SetRange("target", false, true)
    frame:FireEvent("UNIT_IN_RANGE_UPDATE", "target", true)
    assertEqual(frame.alpha, 0.45,
        "event payload must not override the re-queried out-of-range alpha")
    assertEqual(#harness.rangeQueries, 1,
        "out-of-range event query count")
    assertEqual(harness.rangeQueries[1], "target",
        "out-of-range event query unit")
end

local function testPartyVehicleRebindsRangeToPartyPet()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_PartyHeaderUnitButtonVehicle", "party1", true)

    harness:SetRange("party1", true, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "party1", "party vehicle initial")

    harness:ClearEvents()
    harness:ClearRangeQueries()
    harness:SetVehicle("party1", true)
    harness:SetRange("partypet1", false, true)
    frame:FireEvent("UNIT_ENTERED_VEHICLE", "party1")
    assertEqual(frame._updateRequired, true,
        "party vehicle event schedules an update")
    frame:Tick()

    assertEqual(frame.effectiveUnit, "partypet1",
        "party vehicle effective unit")
    assertRangeRegistration(harness, frame, "partypet1",
        "party vehicle latest range token")
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "partypet1"
        ),
        1,
        "party vehicle latest range registration"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "party1"
        ),
        0,
        "party vehicle stale range registration"
    )
    assertEqual(#harness.rangeQueries, 1, "party vehicle range query count")
    assertEqual(harness.rangeQueries[1], "partypet1",
        "party vehicle range query token")
    assertEqual(frame.alpha, 0.45, "party vehicle out-of-range alpha")
end

local function testPetVehicleEventRebindsRangeToPlayer()
    local harness = makeHarness()
    local frame = harness.newFrame("BFI_Pet", "pet", false)

    harness:SetRange("pet", true, true)
    frame:Show()
    assertRangeRegistration(harness, frame, "pet", "pet vehicle initial")
    assertUnitEventTokens(
        harness,
        frame,
        "UNIT_ENTERED_VEHICLE",
        {"pet", "player"},
        "pet vehicle event registration"
    )

    harness:ClearEvents()
    harness:ClearRangeQueries()
    harness:SetVehicle("player", true)
    harness:SetRange("player", false, true)
    frame:FireEvent("UNIT_ENTERED_VEHICLE", "player")
    assertEqual(frame._updateRequired, true,
        "player vehicle event schedules the pet update")
    frame:Tick()

    assertEqual(frame.effectiveUnit, "player",
        "pet vehicle effective unit")
    assertRangeRegistration(harness, frame, "player",
        "pet vehicle latest range token")
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "player"
        ),
        1,
        "pet vehicle latest range registration"
    )
    assertEqual(
        harness:CountUnitEventRegistrations(
            "UNIT_IN_RANGE_UPDATE",
            "pet"
        ),
        0,
        "pet vehicle stale range registration"
    )
    assertEqual(#harness.rangeQueries, 1, "pet vehicle range query count")
    assertEqual(harness.rangeQueries[1], "player",
        "pet vehicle range query token")
    assertEqual(frame.alpha, 0.45, "pet vehicle out-of-range alpha")
end

local function testPre120007FailsOpen()
    local harness = makeHarness(120006)
    local frame = harness.newFrame("BFI_Target", "target", false)

    harness:SetRange("target", false, true)
    frame:Show()

    assertEqual(
        #harness:GetUnitEventTokens(frame, "UNIT_IN_RANGE_UPDATE"),
        0,
        "pre-120007 range event registration"
    )
    assertEqual(frame.alpha, 1, "pre-120007 range alpha")
end

local function testConfigModeRangeFadeIsDormant()
    local harness = makeHarness()
    local frame = harness.newFrame("BFI_Target", "target", false)

    frame.inConfigMode = true
    harness:SetRange("target", false, true)
    frame:Show()

    assertEqual(
        #harness:GetUnitEventTokens(frame, "UNIT_IN_RANGE_UPDATE"),
        0,
        "config-mode range event registration"
    )
    assertEqual(#harness.rangeQueries, 0, "config-mode range query")
    assertEqual(frame.alpha, 1, "config-mode range alpha")
end

local function testDeferredRoutingIsOptIn()
    local harness = makeHarness()
    local frame = harness.newFrame("BFI_Target", "target", false)

    frame:Show()
    harness:ClearEvents()
    frame:SetAttribute("unit", "focus")
    frame:Tick()

    assertEqual(frame._unitChangeUpdatePending, nil,
        "fixed frame deferred marker")
    assertEqual(harness.indicatorEnables, 0,
        "fixed frame unexpected indicator enable")
    assertEqual(harness.indicatorUpdates, 0,
        "fixed frame unexpected indicator update")
    assertEqual(harness:CountEvents("events.unregister-all"), 0,
        "fixed frame unexpected event rebind")
end

local function testGroupFramesOptIn()
    for _, path in ipairs({
        "Modules/UnitFrames/Units/Party.lua",
        "Modules/UnitFrames/Units/Raid.lua",
    }) do
        local source = readFile(path)
        assertTrue(
            source:find(
                "_deferUpdateOnUnitChange%s*=%s*true"
            ) ~= nil,
            path .. " deferred routing opt-in"
        )
    end
end

testVisibleHeaderReassignmentIsDeferred()
testHiddenHeaderReassignmentUsesOnShow()
testRapidReassignmentsCoalesceOnLatestUnit()
testRangeEventRequeriesInsteadOfReadingPayload()
testPartyVehicleRebindsRangeToPartyPet()
testPetVehicleEventRebindsRangeToPlayer()
testPre120007FailsOpen()
testConfigModeRangeFadeIsDormant()
testDeferredRoutingIsOptIn()
testGroupFramesOptIn()

print("unit_frame_group_header_routing_test.lua: ok")
