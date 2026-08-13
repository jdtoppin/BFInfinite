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

local function makeHarness()
    local harness = {
        events = {},
        indicatorEnables = 0,
        indicatorUpdates = 0,
        guidByUnit = {},
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
        UnitHasVehicleUI = function()
            return false
        end,
        UnitIsPlayer = function()
            return true
        end,
        UnitIsUnit = function(left, right)
            return left == right
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

        function frame:RegisterUnitEvent(event, eventUnit)
            record("unit-event.register", self, event, eventUnit)
        end

        function frame:SetAttribute(key, value)
            self.attributes[key] = value
            local callback = self.scripts.OnAttributeChanged
            if callback then
                callback(self, key, value)
            end
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

        function frame:UnregisterAllEvents()
            record("events.unregister-all", self)
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

    harness.BFI = BFI
    harness.newFrame = newFrame
    return harness
end

local function testVisibleHeaderReassignmentIsDeferred()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_PartyHeaderUnitButton1", "party1", true)

    harness.guidByUnit.party1 = "GUID-SAME-PLAYER"
    harness.guidByUnit.party2 = "GUID-SAME-PLAYER"
    frame:Show()
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

    frame:Show()
    frame:Hide()
    harness:ClearEvents()
    frame:SetAttribute("unit", "raid2")
    assertEqual(frame._unitChangeUpdatePending, true,
        "hidden reassignment marker")

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
    assertEqual(harness:CountEvents("events.unregister-all"), 0,
        "OnShow duplicate event reset")
    local registration = harness:LastUnitRegistration()
    assertTrue(registration, "OnShow unit-event registration")
    assertEqual(registration.args[3], "raid2",
        "OnShow unit-event token")
end

local function testRapidReassignmentsCoalesceOnLatestUnit()
    local harness = makeHarness()
    local frame =
        harness.newFrame("BFI_PartyHeaderUnitButton2", "party1", true)

    frame:Show()
    harness:ClearEvents()
    frame:SetAttribute("unit", "party2")
    frame:SetAttribute("unit", "party3")
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
testDeferredRoutingIsOptIn()
testGroupFramesOptIn()

print("unit_frame_group_header_routing_test.lua: ok")
