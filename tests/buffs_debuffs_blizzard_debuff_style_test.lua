local unpack = unpack

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

local function assertFalse(value, message)
    assertEqual(value == false, true, message)
end

local function assertNil(value, message)
    assertEqual(value, nil, message)
end

local function assertTableEqual(actual, expected, message)
    assertEqual(#actual, #expected, message .. " length")
    for index, value in ipairs(expected) do
        assertEqual(actual[index], value, message .. " " .. index)
    end
end

local function assertBefore(events, first, second, message)
    local firstIndex
    local secondIndex
    for index, value in ipairs(events) do
        if value == first and not firstIndex then firstIndex = index end
        if value == second and not secondIndex then secondIndex = index end
    end
    assertTrue(firstIndex ~= nil, message .. " first event")
    assertTrue(secondIndex ~= nil, message .. " second event")
    assertTrue(firstIndex < secondIndex, message .. " order")
end

local function NewConfig()
    return {
        enabled = true,
        width = 26,
        height = 24,
        stack = {
            enabled = true,
            font = {"Expressway", 11, "outline", true},
            position = {"TOPRIGHT", "TOPRIGHT", 0, 3},
            color = {0.8, 0.7, 0.6, 0.9},
        },
        duration = {
            enabled = false,
        },
    }
end

local function NewHarness(options)
    options = options or {}

    local events = {}
    local secretValues = setmetatable({}, {__mode = "k"})
    local writeCount = 0
    local combatCalls = 0
    local setFontLookups = 0
    local setFontACalls = 0
    local setFontBCalls = 0
    local currentSetFont

    local function Log(value)
        events[#events + 1] = value
    end

    local function MarkSecret(value)
        secretValues[value] = true
        return value
    end

    local function IsValueNonSecret(value)
        return secretValues[value] ~= true
    end

    local function Read(object, method, ...)
        Log("read:" .. object._label .. "." .. method)
        local override = object._overrides and object._overrides[method]
        if override then return override(object, ...) end
        return ...
    end

    local function Write(object, method)
        writeCount = writeCount + 1
        Log("write:" .. object._label .. "." .. method)
        if object._onWrite then object:_onWrite(method) end
    end

    local function NewObject(label, parent)
        local object = {
            _accessible = true,
            _accessCalls = 0,
            _label = label,
            _overrides = {},
            _parent = parent,
        }
        function object:CanBeAccessedInContext()
            self._accessCalls = self._accessCalls + 1
            Log("access:" .. self._label)
            if self._accessError then
                error("unexpected access: " .. self._label, 2)
            end
            if self._accessHook then return self:_accessHook() end
            return self._accessible
        end
        function object:GetParent()
            return Read(self, "GetParent", self._parent)
        end
        return object
    end

    local function NewRegion(label, parent, values)
        values = values or {}
        local region = NewObject(label, parent)
        region.width = values.width or 30
        region.height = values.height or 30
        region.alpha = values.alpha == nil and 1 or values.alpha
        region.texCoord = values.texCoord
            or {0, 0, 0, 1, 1, 0, 1, 1}
        region.font = values.font or {"original.ttf", 13, "OUTLINE"}
        region.points = values.points or {}
        region.textColor = values.textColor or {0.2, 0.3, 0.4, 0.5}
        region.shadowColor = values.shadowColor or {0.1, 0.1, 0.1, 0.8}
        region.shadowOffset = values.shadowOffset or {2, -2}
        region.justifyH = values.justifyH or "CENTER"
        region.justifyV = values.justifyV or "MIDDLE"

        function region:GetWidth()
            return Read(self, "GetWidth", self.width)
        end
        function region:GetHeight()
            return Read(self, "GetHeight", self.height)
        end
        function region:SetSize(width, height)
            Write(self, "SetSize")
            self.width = width
            self.height = height
        end
        function region:GetTexCoord()
            return Read(self, "GetTexCoord", unpack(self.texCoord))
        end
        function region:SetTexCoord(...)
            Write(self, "SetTexCoord")
            local coordinates = {...}
            if #coordinates == 4 then
                local left, right, bottom, top = unpack(coordinates)
                self.texCoord = {
                    left, bottom,
                    left, top,
                    right, bottom,
                    right, top,
                }
            else
                self.texCoord = coordinates
            end
        end
        function region:GetAlpha()
            return Read(self, "GetAlpha", self.alpha)
        end
        function region:SetAlpha(alpha)
            Write(self, "SetAlpha")
            self.alpha = alpha
        end
        function region:GetFont()
            return Read(self, "GetFont", unpack(self.font))
        end
        function region:SetFont(...)
            Write(self, "SetFont")
            self.font = {...}
        end
        function region:GetNumPoints()
            return Read(self, "GetNumPoints", #self.points)
        end
        function region:GetPoint(index)
            return Read(self, "GetPoint", unpack(self.points[index]))
        end
        function region:ClearAllPoints()
            Write(self, "ClearAllPoints")
            self.points = {}
        end
        function region:SetPoint(...)
            Write(self, "SetPoint")
            self.points[#self.points + 1] = {...}
        end
        function region:GetTextColor()
            return Read(self, "GetTextColor", unpack(self.textColor))
        end
        function region:SetTextColor(...)
            Write(self, "SetTextColor")
            self.textColor = {...}
        end
        function region:GetShadowColor()
            return Read(self, "GetShadowColor", unpack(self.shadowColor))
        end
        function region:SetShadowColor(...)
            Write(self, "SetShadowColor")
            self.shadowColor = {...}
        end
        function region:GetShadowOffset()
            return Read(self, "GetShadowOffset", unpack(self.shadowOffset))
        end
        function region:SetShadowOffset(...)
            Write(self, "SetShadowOffset")
            self.shadowOffset = {...}
        end
        function region:GetJustifyH()
            return Read(self, "GetJustifyH", self.justifyH)
        end
        function region:SetJustifyH(value)
            Write(self, "SetJustifyH")
            self.justifyH = value
        end
        function region:GetJustifyV()
            return Read(self, "GetJustifyV", self.justifyV)
        end
        function region:SetJustifyV(value)
            Write(self, "SetJustifyV")
            self.justifyV = value
        end
        return region
    end

    local frame = NewObject("frame")
    local container = NewObject("container", frame)
    frame.AuraContainer = container
    frame.maxAuras = options.maxAuras or 16
    function frame:UpdateAuraButtons()
        error("Blizzard updates are outside the adapter", 2)
    end
    function container:UpdateGridLayout()
        error("Blizzard layout is outside the adapter", 2)
    end

    local entries = {}
    local function NewEntry(index)
        local button = NewObject("b" .. index, container)
        local entry = {
            button = button,
        }
        entry.icon = NewRegion("b" .. index .. ".icon", button)
        entry.border = NewRegion("b" .. index .. ".border", button, {
            width = 40,
            height = 40,
            alpha = 0.9,
        })
        entry.count = NewRegion("b" .. index .. ".count", button, {
            alpha = 0.75,
        })
        entry.count.points = {
            {"BOTTOMRIGHT", entry.icon, "BOTTOMRIGHT", -2, 2},
        }
        entry.duration = NewRegion("b" .. index .. ".duration", button, {
            alpha = 0.6,
        })
        button.Icon = entry.icon
        button.DebuffBorder = entry.border
        button.Count = entry.count
        button.Duration = entry.duration
        return entry
    end

    local auraFrames = {}
    for index = 1, 16 do
        entries[index] = NewEntry(index)
        auraFrames[index] = entries[index].button
    end
    setmetatable(auraFrames, {
        __index = function(_, key)
            if key == 17 then error("auraFrames[17] was observed", 2) end
        end,
    })
    frame.auraFrames = auraFrames
    setmetatable(frame, {
        __index = function(_, key)
            if key == "PrivateAuraAnchors" then
                error("private anchors were observed", 2)
            end
        end,
    })

    local function SetFontA(region, font, size, outline)
        setFontACalls = setFontACalls + 1
        region:SetFont("resolved:" .. font, size, outline)
        region:SetShadowOffset(1, -1)
        region:SetShadowColor(0, 0, 0, 1)
    end
    local function SetFontB(region, font, size, outline)
        setFontBCalls = setFontBCalls + 1
        region:SetFont("replacement:" .. font, size, outline)
        region:SetShadowOffset(9, -9)
        region:SetShadowColor(1, 0, 0, 1)
    end
    currentSetFont = SetFontA
    local AF = setmetatable({}, {
        __index = function(_, key)
            if key ~= "SetFont" then return nil end
            setFontLookups = setFontLookups + 1
            Log("dependency:SetFont:" .. setFontLookups)
            if options.setFontDrift and setFontLookups == 2 then
                currentSetFont = SetFontB
            end
            return currentSetFont
        end,
    })

    local environment = {}
    setmetatable(environment, {
        __index = function(_, key)
            if key == "DeadlyDebuffFrame" then
                error("DeadlyDebuffFrame was observed", 2)
            end
            return _G[key]
        end,
    })
    environment._G = environment
    environment.DebuffFrame = frame
    environment.AbstractFramework = AF
    environment.InCombatLockdown = function()
        combatCalls = combatCalls + 1
        Log("combat:" .. combatCalls)
        if options.mutateSetFontOnFinalCombat and combatCalls == 2 then
            currentSetFont = SetFontB
        end
        if options.finalCombatFlip and combatCalls == 2 then
            return true
        end
        return options.inCombat == true
    end

    local BD = {}
    local BFI = {
        funcs = {
            isValueNonSecret = IsValueNonSecret,
        },
        modules = {
            BuffsDebuffs = BD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/BlizzardDebuffs.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    local harness = {
        BD = BD,
        entries = entries,
        events = events,
        frame = frame,
        container = container,
        secret = MarkSecret,
    }
    function harness:resetTrace()
        for index = #events, 1, -1 do events[index] = nil end
        writeCount = 0
        combatCalls = 0
        setFontLookups = 0
        setFontACalls = 0
        setFontBCalls = 0
        currentSetFont = SetFontA
    end
    function harness:getWriteCount() return writeCount end
    function harness:getSetFontLookups() return setFontLookups end
    function harness:getSetFontACalls() return setFontACalls end
    function harness:getSetFontBCalls() return setFontBCalls end
    function harness:state() return BD.GetBlizzardDebuffStyleState() end
    return harness
end

local function AssertInactiveNoWrites(harness, message)
    assertEqual(harness:getWriteCount(), 0, message .. " writes")
    local state = harness:state()
    assertFalse(state.active, message .. " active")
    assertEqual(state.snapshotsCreated, 0, message .. " snapshots")
    assertEqual(state.styledButtonCount, 0, message .. " styled")
end

local function TestApplyAndRestore()
    local harness = NewHarness()
    harness.entries[1].count.points = {
        {"TOPLEFT", nil, "TOPLEFT", 4, -4},
        {"BOTTOMRIGHT", harness.entries[1].icon, "BOTTOMRIGHT", -2, 2},
    }
    assertTrue(
        harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
        "complete ordinary topology applies"
    )
    assertEqual(harness:getSetFontLookups(), 2, "two dependency reads")
    assertEqual(harness:getSetFontACalls(), 16, "captured font setter")
    assertEqual(harness:getSetFontBCalls(), 0, "replacement setter unused")
    assertBefore(
        harness.events,
        "read:b16.duration.GetAlpha",
        "write:b1.icon.SetSize",
        "all sixteen snapshots precede writes"
    )

    for index = 1, 16 do
        local entry = harness.entries[index]
        assertEqual(entry.icon.width, 26, "styled icon width " .. index)
        assertEqual(entry.icon.height, 24, "styled icon height " .. index)
        assertEqual(entry.border.width, 36, "native border width " .. index)
        assertEqual(entry.border.height, 34, "native border height " .. index)
        assertEqual(entry.border.alpha, 1, "native border visible " .. index)
        assertEqual(entry.count.points[1][2], entry.button,
            "styled count parent " .. index)
        assertEqual(entry.duration.alpha, 0,
            "styled duration alpha " .. index)
    end
    local state = harness:state()
    assertTrue(state.active, "style state active")
    assertEqual(state.snapshotsCreated, 16, "original snapshots retained")
    assertEqual(state.styledButtonCount, 16, "all ordinary buttons styled")

    harness:resetTrace()
    local updated = NewConfig()
    updated.width = 22
    updated.height = 20
    updated.stack.enabled = false
    updated.duration.enabled = true
    assertTrue(
        harness.BD.UpdateBlizzardDebuffStyle(updated),
        "active style updates against the same fixed topology"
    )
    state = harness:state()
    assertEqual(state.snapshotsCreated, 16,
        "active update does not grow original snapshots")
    assertEqual(state.styledButtonCount, 16,
        "active update retains fixed styled count")
    assertEqual(harness.entries[1].icon.width, 22,
        "active update applies latest width")
    assertEqual(harness.entries[1].count.alpha, 0,
        "active update applies stack visibility")
    assertEqual(harness.entries[1].duration.alpha, 1,
        "active update applies duration visibility")

    harness:resetTrace()
    local disabled = NewConfig()
    disabled.enabled = false
    assertTrue(
        harness.BD.UpdateBlizzardDebuffStyle(disabled),
        "disable restores complete original batch"
    )
    assertTrue(harness:getWriteCount() > 0, "restore writes occur")
    for index = 1, 16 do
        local entry = harness.entries[index]
        assertEqual(entry.icon.width, 30, "restored icon width " .. index)
        assertEqual(entry.icon.height, 30, "restored icon height " .. index)
        assertTableEqual(entry.icon.texCoord,
            {0, 0, 0, 1, 1, 0, 1, 1},
            "restored eight-value texcoord " .. index)
        assertEqual(entry.border.width, 40, "restored border width " .. index)
        assertEqual(entry.border.height, 40, "restored border height " .. index)
        assertEqual(entry.border.alpha, 0.9,
            "restored native border alpha " .. index)
        if index ~= 1 then
            assertEqual(entry.count.points[1][2], entry.icon,
                "restored count parent " .. index)
        end
        assertEqual(entry.duration.alpha, 0.6,
            "restored duration alpha " .. index)
        assertTableEqual(entry.count.font,
            {"original.ttf", 13, "OUTLINE"},
            "restored font " .. index)
        assertTableEqual(entry.count.textColor,
            {0.2, 0.3, 0.4, 0.5},
            "restored text colour " .. index)
        assertTableEqual(entry.count.shadowColor,
            {0.1, 0.1, 0.1, 0.8},
            "restored shadow colour " .. index)
        assertTableEqual(entry.count.shadowOffset,
            {2, -2},
            "restored shadow offset " .. index)
        assertEqual(entry.count.alpha, 0.75,
            "restored count alpha " .. index)
        assertEqual(entry.count.justifyH, "CENTER",
            "restored horizontal justification " .. index)
        assertEqual(entry.count.justifyV, "MIDDLE",
            "restored vertical justification " .. index)
    end
    assertEqual(#harness.entries[1].count.points, 2,
        "all original points restored")
    assertEqual(harness.entries[1].count.points[1][2], nil,
        "nil relative is restored")
    assertEqual(harness.entries[1].count.points[2][2],
        harness.entries[1].icon, "own-icon relative is restored")
    state = harness:state()
    assertFalse(state.active, "restored state inactive")
    assertEqual(state.snapshotsCreated, 0, "restored snapshots cleared")
    assertEqual(state.styledButtonCount, 0, "restored styled count")
end

local function TestLateFailureAndTopologyDrift()
    do
        local harness = NewHarness()
        harness.entries[16].duration._overrides.GetAlpha = function()
            return harness:secret({})
        end
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "button sixteen secret getter fails closed"
        )
        AssertInactiveNoWrites(harness, "late secret getter")
    end

    do
        local harness = NewHarness()
        local original = harness.entries[16].duration.GetAlpha
        harness.entries[16].duration.GetAlpha = function(self)
            local alpha = original(self)
            harness.frame.auraFrames[16] = harness.entries[15].button
            return alpha
        end
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "topology drift after snapshot fails closed"
        )
        AssertInactiveNoWrites(harness, "topology drift")
    end

    do
        local harness = NewHarness()
        local original = harness.entries[16].duration.GetAlpha
        harness.entries[16].duration.GetAlpha = function(self)
            local alpha = original(self)
            harness.entries[16].button.Icon = harness.entries[15].icon
            return alpha
        end
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "region drift after snapshot fails closed"
        )
        AssertInactiveNoWrites(harness, "region topology drift")
    end
end

local function TestStructuredGetterSecrecy()
    local cases = {}
    local function Add(label, setup)
        cases[#cases + 1] = {label, setup}
    end
    local function SecretTuple(harness, values, position)
        values[position] = harness:secret({})
        return function() return unpack(values) end
    end

    Add("icon width", function(h)
        h.entries[16].icon._overrides.GetWidth = function()
            return h:secret({})
        end
    end)
    Add("icon height", function(h)
        h.entries[16].icon._overrides.GetHeight = function()
            return h:secret({})
        end
    end)
    for position = 1, 8 do
        local tuplePosition = position
        Add("texcoord " .. position, function(h)
            h.entries[16].icon._overrides.GetTexCoord = SecretTuple(h,
                {0, 0, 0, 1, 1, 0, 1, 1}, tuplePosition)
        end)
    end
    Add("border width", function(h)
        h.entries[16].border._overrides.GetWidth = function()
            return h:secret({})
        end
    end)
    Add("border height", function(h)
        h.entries[16].border._overrides.GetHeight = function()
            return h:secret({})
        end
    end)
    Add("border alpha", function(h)
        h.entries[16].border._overrides.GetAlpha = function()
            return h:secret({})
        end
    end)
    for position = 1, 3 do
        local tuplePosition = position
        Add("font " .. position, function(h)
            h.entries[16].count._overrides.GetFont = SecretTuple(h,
                {"original.ttf", 13, "OUTLINE"}, tuplePosition)
        end)
    end
    Add("point count", function(h)
        h.entries[16].count._overrides.GetNumPoints = function()
            return h:secret({})
        end
    end)
    for position = 1, 5 do
        local tuplePosition = position
        Add("point " .. position, function(h)
            h.entries[16].count._overrides.GetPoint = SecretTuple(h, {
                "BOTTOMRIGHT",
                h.entries[16].icon,
                "BOTTOMRIGHT",
                -2,
                2,
            }, tuplePosition)
        end)
    end
    for position = 1, 4 do
        local tuplePosition = position
        Add("text colour " .. position, function(h)
            h.entries[16].count._overrides.GetTextColor = SecretTuple(h,
                {0.2, 0.3, 0.4, 0.5}, tuplePosition)
        end)
        Add("shadow colour " .. position, function(h)
            h.entries[16].count._overrides.GetShadowColor = SecretTuple(h,
                {0.1, 0.1, 0.1, 0.8}, tuplePosition)
        end)
    end
    for position = 1, 2 do
        local tuplePosition = position
        Add("shadow offset " .. position, function(h)
            h.entries[16].count._overrides.GetShadowOffset = SecretTuple(h,
                {2, -2}, tuplePosition)
        end)
    end
    Add("horizontal justification", function(h)
        h.entries[16].count._overrides.GetJustifyH = function()
            return h:secret({})
        end
    end)
    Add("vertical justification", function(h)
        h.entries[16].count._overrides.GetJustifyV = function()
            return h:secret({})
        end
    end)
    Add("count alpha", function(h)
        h.entries[16].count._overrides.GetAlpha = function()
            return h:secret({})
        end
    end)
    Add("duration alpha", function(h)
        h.entries[16].duration._overrides.GetAlpha = function()
            return h:secret({})
        end
    end)

    for _, case in ipairs(cases) do
        local harness = NewHarness()
        case[2](harness)
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            case[1] .. " secret return fails closed"
        )
        AssertInactiveNoWrites(harness, case[1])
    end
end

local function TestAccessAndParentFailures()
    local cases = {
        {"frame", function(h) return h.frame end},
        {"container", function(h) return h.container end},
    }
    for _, index in ipairs({1, 8, 16}) do
        for _, field in ipairs({
            "button", "icon", "border", "count", "duration",
        }) do
            local entryIndex = index
            local entryField = field
            cases[#cases + 1] = {
                field .. index,
                function(h) return h.entries[entryIndex][entryField] end,
            }
        end
    end
    for _, case in ipairs(cases) do
        local harness = NewHarness()
        case[2](harness)._accessible = false
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            case[1] .. " inaccessible fails closed"
        )
        AssertInactiveNoWrites(harness, case[1])
    end

    for _, accessValue in ipairs({"secret", "nonboolean"}) do
        local harness = NewHarness()
        local target = harness.entries[8].duration
        if accessValue == "secret" then
            target._accessHook = function()
                return harness:secret({})
            end
        else
            target._accessHook = function() return {} end
        end
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            accessValue .. " accessibility result fails closed"
        )
        AssertInactiveNoWrites(harness, accessValue .. " accessibility")
    end

    local parentCases = {
        {"container", function(h) return h.container end},
    }
    for _, index in ipairs({1, 8, 16}) do
        for _, field in ipairs({
            "button", "icon", "border", "count", "duration",
        }) do
            local entryIndex = index
            local entryField = field
            parentCases[#parentCases + 1] = {
                field .. index,
                function(h) return h.entries[entryIndex][entryField] end,
            }
        end
    end
    for _, case in ipairs(parentCases) do
        local harness = NewHarness()
        local poison = {
            _accessCalls = 0,
            CanBeAccessedInContext = function(self)
                self._accessCalls = self._accessCalls + 1
                error("unexpected parent access", 2)
            end,
        }
        case[2](harness)._parent = poison
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            case[1] .. " unexpected parent is rejected by identity"
        )
        assertEqual(poison._accessCalls, 0,
            case[1] .. " unexpected parent receives no access call")
        AssertInactiveNoWrites(harness, case[1] .. " unexpected parent")
    end

    for _, field in ipairs({
        "button", "icon", "border", "count", "duration",
    }) do
        local harness = NewHarness()
        local poison = harness:secret({
            CanBeAccessedInContext = function()
                error("secret parent was accessed", 2)
            end,
        })
        harness.entries[8][field]._parent = poison
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            field .. " secret parent fails before comparison/access"
        )
        AssertInactiveNoWrites(harness, field .. " secret parent")
    end

    do
        local harness = NewHarness()
        local poison = {
            _accessCalls = 0,
            CanBeAccessedInContext = function(self)
                self._accessCalls = self._accessCalls + 1
                error("unexpected point relative access", 2)
            end,
        }
        harness.entries[1].count.points[1][2] = poison
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "external point relative is rejected"
        )
        assertEqual(poison._accessCalls, 0,
            "external relative receives no access call")
        AssertInactiveNoWrites(harness, "external relative")
    end

    do
        local harness = NewHarness()
        local poison = harness:secret({
            CanBeAccessedInContext = function()
                error("secret point relative was accessed", 2)
            end,
        })
        harness.entries[1].count.points[1][2] = poison
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "secret point relative fails before identity/access"
        )
        AssertInactiveNoWrites(harness, "secret relative")
    end

    do
        local harness = NewHarness()
        local icon = harness.entries[1].icon
        local accessCalls = 0
        icon._accessHook = function()
            accessCalls = accessCalls + 1
            return accessCalls < 2
        end
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "matched own icon is freshly access-gated as a point relative"
        )
        AssertInactiveNoWrites(harness, "denied own-icon relative")
    end

    do
        local harness = NewHarness()
        harness.entries[1].count.points[1][2] = nil
        assertTrue(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "nil point relative is accepted"
        )
        assertTrue(harness.BD.DisableBlizzardDebuffStyle(),
            "nil point relative restores")
        assertEqual(harness.entries[1].count.points[1][2], nil,
            "nil point relative survives restore")
    end
end

local function TestFinalGates()
    do
        local harness = NewHarness({finalCombatFlip = true})
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "combat flip at final gate prevents writes"
        )
        assertEqual(harness:getSetFontLookups(), 2,
            "dependency checked before final combat gate")
        AssertInactiveNoWrites(harness, "final combat flip")
    end

    do
        local harness = NewHarness({setFontDrift = true})
        assertFalse(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "font dependency drift prevents writes"
        )
        assertEqual(harness:getSetFontLookups(), 2,
            "drift uses two dependency lookups")
        AssertInactiveNoWrites(harness, "font drift")
    end

    do
        local harness = NewHarness({mutateSetFontOnFinalCombat = true})
        assertTrue(
            harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
            "captured setter survives post-check table mutation"
        )
        assertEqual(harness:getSetFontLookups(), 2,
            "no late dependency lookup after final combat gate")
        assertEqual(harness:getSetFontACalls(), 16,
            "captured setter A used for complete batch")
        assertEqual(harness:getSetFontBCalls(), 0,
            "mutated setter B never used")
    end
end

local function TestActiveFailureIsAtomic()
    local harness = NewHarness()
    assertTrue(
        harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
        "active failure fixture first applies"
    )

    harness:resetTrace()
    harness.entries[8].count._accessible = false
    local changed = NewConfig()
    changed.width = 22
    assertFalse(
        harness.BD.UpdateBlizzardDebuffStyle(changed),
        "active inaccessible region blocks update"
    )
    assertEqual(harness:getWriteCount(), 0,
        "failed active update writes nothing")
    assertTrue(harness:state().active,
        "failed active update retains prior state")

    harness:resetTrace()
    assertFalse(
        harness.BD.DisableBlizzardDebuffStyle(),
        "active inaccessible region blocks restore"
    )
    assertEqual(harness:getWriteCount(), 0,
        "failed active restore writes nothing")
    assertTrue(harness:state().active,
        "failed active restore retains state")

    harness.entries[8].count._accessible = true
    harness:resetTrace()
    assertTrue(
        harness.BD.DisableBlizzardDebuffStyle(),
        "repaired active topology restores exactly"
    )
    assertFalse(harness:state().active, "repaired restore clears state")
end

local function TestStoredActiveGates()
    local storedCases = {
        {
            "stored button",
            function(h) return h.entries[8].button end,
            14,
        },
        {
            "stored region",
            function(h) return h.entries[8].count end,
            4,
        },
        {
            "stored saved relative",
            function(h) return h.entries[8].icon end,
            5,
        },
    }

    for _, operation in ipairs({"update", "disable"}) do
        for _, case in ipairs(storedCases) do
            local harness = NewHarness()
            assertTrue(
                harness.BD.UpdateBlizzardDebuffStyle(NewConfig()),
                operation .. " " .. case[1] .. " fixture applies"
            )

            local target = case[2](harness)
            local accessCalls = 0
            target._accessHook = function()
                accessCalls = accessCalls + 1
                return accessCalls ~= case[3]
            end
            harness:resetTrace()

            local result
            if operation == "update" then
                local changed = NewConfig()
                changed.width = 21
                result = harness.BD.UpdateBlizzardDebuffStyle(changed)
            else
                result = harness.BD.DisableBlizzardDebuffStyle()
            end
            assertFalse(result,
                operation .. " denies " .. case[1])
            assertEqual(harness:getWriteCount(), 0,
                operation .. " " .. case[1] .. " writes nothing")
            assertTrue(harness:state().active,
                operation .. " " .. case[1] .. " retains active state")

            target._accessHook = nil
            harness:resetTrace()
            assertTrue(harness.BD.DisableBlizzardDebuffStyle(),
                operation .. " " .. case[1] .. " repairs and restores")
            assertFalse(harness:state().active,
                operation .. " " .. case[1] .. " clears state")
            assertEqual(harness.entries[8].icon.width, 30,
                operation .. " " .. case[1] .. " exact restore")
        end
    end
end

local function TestSourceBoundary()
    local file = assert(io.open(
        "Modules/BuffsDebuffs/BlizzardDebuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()

    assertNil(source:find("CreateTexture", 1, true),
        "native rounded border is preserved")
    assertNil(source:find("PrivateAuraAnchors", 1, true),
        "no private-anchor access")
    assertNil(source:find("_G.DeadlyDebuffFrame", 1, true),
        "no Deadly frame access")
    assertNil(source:find("auraFrames[17]", 1, true),
        "no seventeenth child access")
    assertNil(source:find("unpack", 1, true),
        "native getter values are not unpacked")
    assertNil(source:find("IsShown", 1, true),
        "no native visibility read")
    assertNil(source:find("AuraData", 1, true),
        "no aura-data read")
    assertNil(source:find(":UpdateAuraButtons", 1, true),
        "no Blizzard aura update call")
    assertNil(source:find(":UpdateGridLayout", 1, true),
        "no Blizzard layout update call")
end

TestApplyAndRestore()
TestLateFailureAndTopologyDrift()
TestStructuredGetterSecrecy()
TestAccessAndParentFailures()
TestFinalGates()
TestActiveFailureIsAtomic()
TestStoredActiveGates()
TestSourceBoundary()

print("buffs/debuffs Blizzard Debuff style tests passed")
