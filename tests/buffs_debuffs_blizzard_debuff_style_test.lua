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

local function NewRegion(options)
    options = options or {}
    local region = {
        width = options.width or 1,
        height = options.height or 1,
        texCoord = options.texCoord or {0, 1, 0, 1},
        alpha = options.alpha or 1,
        font = options.font or {"original.ttf", 13, "OUTLINE"},
        points = options.points or {},
        textColor = options.textColor or {0.2, 0.3, 0.4, 0.5},
        shadowColor = options.shadowColor or {0.1, 0.1, 0.1, 0.8},
        shadowOffset = options.shadowOffset or {2, -2},
        justifyH = options.justifyH or "CENTER",
        justifyV = options.justifyV or "MIDDLE",
    }

    function region:GetWidth()
        return self.width
    end
    function region:GetHeight()
        return self.height
    end
    function region:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function region:GetTexCoord()
        return unpack(self.texCoord)
    end
    function region:SetTexCoord(...)
        self.texCoord = {...}
    end
    function region:GetAlpha()
        return self.alpha
    end
    function region:SetAlpha(alpha)
        self.alpha = alpha
    end
    function region:GetFont()
        return unpack(self.font)
    end
    function region:SetFont(...)
        self.font = {...}
    end
    function region:GetNumPoints()
        return #self.points
    end
    function region:GetPoint(index)
        return unpack(self.points[index])
    end
    function region:ClearAllPoints()
        self.points = {}
    end
    function region:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end
    function region:GetTextColor()
        return unpack(self.textColor)
    end
    function region:SetTextColor(...)
        self.textColor = {...}
    end
    function region:GetShadowColor()
        return unpack(self.shadowColor)
    end
    function region:SetShadowColor(...)
        self.shadowColor = {...}
    end
    function region:GetShadowOffset()
        return unpack(self.shadowOffset)
    end
    function region:SetShadowOffset(...)
        self.shadowOffset = {...}
    end
    function region:GetJustifyH()
        return self.justifyH
    end
    function region:SetJustifyH(value)
        self.justifyH = value
    end
    function region:GetJustifyV()
        return self.justifyV
    end
    function region:SetJustifyV(value)
        self.justifyV = value
    end

    return region
end

local function NewHarness(options)
    options = options or {}
    local inCombat = options.inCombat == true
    local forbiddenUpdateCalls = 0
    local privateParentCalls = 0
    local fontCalls = 0

    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.InCombatLockdown = function()
        return inCombat
    end

    local container = {}
    local frame = {
        maxAuras = options.maxAuras or 16,
        auraFrames = {},
    }
    function container:GetParent()
        return frame
    end
    function container:UpdateGridLayout()
        forbiddenUpdateCalls = forbiddenUpdateCalls + 1
        error("BFInfinite must not drive Blizzard layout", 2)
    end
    frame.AuraContainer = container
    function frame:UpdateAuraButtons()
        forbiddenUpdateCalls = forbiddenUpdateCalls + 1
        error("BFInfinite must not drive Blizzard aura updates", 2)
    end

    local privateAnchor = {}
    function privateAnchor:GetParent()
        privateParentCalls = privateParentCalls + 1
        error("BFInfinite must not access private-aura anchors", 2)
    end
    frame.PrivateAuraAnchors = {privateAnchor}

    local buttons = {}
    for index = 1, frame.maxAuras do
        local button = {}
        function button:GetParent()
            return container
        end
        button.Icon = NewRegion({
            width = 30,
            height = 30,
            texCoord = {0, 1, 0, 1},
        })
        button.DebuffBorder = NewRegion({
            width = 40,
            height = 40,
        })
        button.Count = NewRegion({
            alpha = 0.75,
            points = {
                {"BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", -2, 2},
            },
        })
        button.Duration = NewRegion({
            alpha = 0.6,
        })
        buttons[index] = button
        frame.auraFrames[index] = button
    end
    frame.auraFrames[#frame.auraFrames + 1] = privateAnchor

    environment.DebuffFrame = frame
    environment.DeadlyDebuffFrame = {
        untouched = true,
    }

    local AF = {}
    function AF.SetFont(region, font, size, outline, shadow)
        fontCalls = fontCalls + 1
        region:SetFont("resolved:" .. font, size, outline)
        if shadow then
            region:SetShadowOffset(1, -1)
            region:SetShadowColor(0, 0, 0, 1)
        else
            region:SetShadowOffset(0, 0)
            region:SetShadowColor(0, 0, 0, 0)
        end
    end
    environment.AbstractFramework = AF

    local BD = {}
    local BFI = {
        modules = {
            BuffsDebuffs = BD,
        },
    }
    local chunk = assert(loadfile(
        "Modules/BuffsDebuffs/BlizzardDebuffs.lua"
    ))
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    return {
        BD = BD,
        buttons = buttons,
        privateAnchor = privateAnchor,
        deadlyFrame = environment.DeadlyDebuffFrame,
        setCombat = function(value)
            inCombat = value == true
        end,
        getForbiddenUpdateCalls = function()
            return forbiddenUpdateCalls
        end,
        getPrivateParentCalls = function()
            return privateParentCalls
        end,
        getFontCalls = function()
            return fontCalls
        end,
    }
end

local config = {
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

do
    local harness = NewHarness()
    local BD = harness.BD

    assertTrue(
        BD.HasBlizzardDebuffStyleCapability(),
        "pinned Blizzard DebuffFrame shape is supported"
    )
    assertEqual(
        harness.getPrivateParentCalls(),
        0,
        "private anchors are never accessed"
    )
    assertTrue(
        BD.UpdateBlizzardDebuffStyle(config),
        "ordinary Debuffs style applies"
    )
    assertEqual(
        harness.getForbiddenUpdateCalls(),
        0,
        "Blizzard update methods are never called"
    )
    assertEqual(
        harness.getFontCalls(),
        16,
        "only fixed ordinary count regions are styled"
    )
    assertTrue(
        harness.deadlyFrame.untouched,
        "DeadlyDebuffFrame remains untouched"
    )

    for _, button in ipairs(harness.buttons) do
        assertEqual(button.Icon.width, 26, "icon width")
        assertEqual(button.Icon.height, 24, "icon height")
        assertTableEqual(
            button.Icon.texCoord,
            {0.08, 0.92, 0.08, 0.92},
            "icon crop"
        )
        assertEqual(button.DebuffBorder.width, 36, "border width")
        assertEqual(button.DebuffBorder.height, 34, "border height")
        assertTableEqual(
            button.Count.font,
            {"resolved:Expressway", 11, "outline"},
            "count font"
        )
        assertTableEqual(
            button.Count.textColor,
            config.stack.color,
            "count colour"
        )
        assertEqual(button.Count.alpha, 1, "count enabled")
        assertEqual(button.Count.justifyH, "RIGHT", "count horizontal")
        assertEqual(button.Count.justifyV, "TOP", "count vertical")
        assertEqual(
            button.Count.points[1][2],
            button,
            "count anchors to ordinary button"
        )
        assertEqual(
            button.Duration.alpha,
            0,
            "native duration visibility"
        )
    end

    local state = BD.GetBlizzardDebuffStyleState()
    assertTrue(state.active, "style state active")
    assertEqual(state.styledButtonCount, 16, "styled button count")
    assertEqual(state.snapshotsCreated, 16, "snapshot count")

    config.width = 100
    config.height = 5
    config.stack.enabled = false
    config.duration.enabled = true
    assertTrue(
        BD.UpdateBlizzardDebuffStyle(config),
        "style updates without new construction"
    )
    state = BD.GetBlizzardDebuffStyleState()
    assertEqual(state.snapshotsCreated, 16, "snapshots are not duplicated")
    for _, button in ipairs(harness.buttons) do
        assertEqual(button.Icon.width, 30, "icon width clamps to cell")
        assertEqual(button.Icon.height, 10, "icon height clamps to cell")
        assertEqual(button.Count.alpha, 0, "count disabled")
        assertEqual(button.Duration.alpha, 1, "duration enabled")
    end

    config.enabled = false
    assertTrue(
        BD.UpdateBlizzardDebuffStyle(config),
        "disabling restores Blizzard presentation"
    )
    state = BD.GetBlizzardDebuffStyleState()
    assertFalse(state.active, "style state inactive")
    assertEqual(state.styledButtonCount, 0, "restored button count")
    for _, button in ipairs(harness.buttons) do
        assertEqual(button.Icon.width, 30, "restored icon width")
        assertEqual(button.Icon.height, 30, "restored icon height")
        assertTableEqual(
            button.Icon.texCoord,
            {0, 1, 0, 1},
            "restored icon crop"
        )
        assertEqual(
            button.DebuffBorder.width,
            40,
            "restored border width"
        )
        assertEqual(button.Count.alpha, 0.75, "restored count alpha")
        assertEqual(
            button.Duration.alpha,
            0.6,
            "restored duration alpha"
        )
        assertEqual(
            button.Count.font[1],
            "original.ttf",
            "restored count font"
        )
        assertEqual(
            button.Count.points[1][2],
            button.Icon,
            "restored count anchor"
        )
    end

    harness.setCombat(true)
    config.enabled = true
    assertFalse(
        BD.UpdateBlizzardDebuffStyle(config),
        "combat mutation is deferred by the caller"
    )
    assertFalse(
        BD.GetBlizzardDebuffStyleState().active,
        "combat attempt leaves style inactive"
    )
end

do
    local harness = NewHarness({
        maxAuras = 15,
    })
    assertFalse(
        harness.BD.HasBlizzardDebuffStyleCapability(),
        "changed ordinary-button pool size fails closed"
    )
    assertEqual(
        harness.getPrivateParentCalls(),
        0,
        "unsupported topology still does not access private anchors"
    )
end

do
    local file = assert(io.open(
        "Modules/BuffsDebuffs/BlizzardDebuffs.lua",
        "r"
    ))
    local source = file:read("*a")
    file:close()

    assertNil(source:find("hooksecurefunc", 1, true),
        "no Blizzard function hooks")
    assertNil(source:find(":SetScript", 1, true),
        "no scripts installed on aura buttons")
    assertNil(source:find(":HookScript", 1, true),
        "no scripts hooked on aura buttons")
    assertNil(source:find(":IsShown", 1, true),
        "no visibility side channel")
    assertNil(source:find(".buttonInfo", 1, true),
        "no aura-data table reads")
    assertNil(source:find("PrivateAuraAnchors", 1, true),
        "no private-aura anchor table access")
    assertNil(source:find(":UpdateAuraButtons", 1, true),
        "no Blizzard aura updates driven")
    assertNil(source:find(":UpdateGridLayout", 1, true),
        "no Blizzard layout updates driven")
end

print("buffs/debuffs Blizzard Debuff style tests passed")
