local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function makeHarness()
    local NP = {}
    local AF = {}
    local harness = {}

    local function newNameText()
        local text = {}

        function text:ClearUnit()
            self.unit = nil
        end

        function text:Hide()
            self.shown = false
        end

        function text:SetLength(length)
            self.length = length
        end

        function text:SetUnit(unit)
            self.unit = unit
        end

        function text:Show()
            self.shown = true
        end

        function text:UpdateName()
        end

        return text
    end

    function AF.CreateSecretNameText()
        return newNameText()
    end

    function AF.SetFont()
    end

    function AF.noop()
    end

    function NP.GetIndicator()
        return nil
    end

    function NP.LoadIndicatorPosition()
    end

    local threatIndicator = {}

    function threatIndicator:Refresh()
    end

    function threatIndicator:SetNameOverlay(overlay)
        self.nameOverlay = overlay
    end

    local parent = {
        indicators = {
            healthBar = {
                threatIndicator = threatIndicator,
            },
        },
        unit = "nameplate1",
    }
    local BFI = {
        modules = {
            Nameplates = NP,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        error = error,
        math = math,
        select = select,
        tostring = tostring,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected NameText global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError = loadfile(
        "Modules/Nameplates/Indicators/NameText.lua"
    )
    assertEqual(type(chunk), "function", loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.text = NP.CreateNameText(parent, "TestNameText")
    return harness
end

local function makeConfig(color)
    return {
        anchorTo = "root",
        color = color,
        font = {"BFI", 13, "outline", false},
        length = 0,
        parent = "root",
        placement = "outside",
        position = {"CENTER", "CENTER", 0, -10},
    }
end

local function testFriendlyPlayerClassColorIsPreserved()
    local harness = makeHarness()

    harness.text:LoadConfig(makeConfig({
        type = "class_color",
        rgb = {1, 1, 1},
    }))

    assertEqual(
        harness.text.color.type,
        "class_color",
        "friendly-player name color descriptor"
    )
end

local function testCustomColorIsPreserved()
    local harness = makeHarness()
    local customColor = {0.1, 0.2, 0.3}

    harness.text:LoadConfig(makeConfig({
        type = "custom_color",
        rgb = customColor,
    }))

    assertEqual(harness.text.color.type, "custom_color", "custom type")
    assertEqual(harness.text.color.rgb, customColor, "custom color table")
end

local function testOtherColorTypesUseSelectionColor()
    local harness = makeHarness()

    harness.text:LoadConfig(makeConfig({type = "selection_color"}))
    assertEqual(
        harness.text.color.type,
        "selection_color",
        "selection color descriptor"
    )

    harness.text:LoadConfig(makeConfig({type = "future_color_type"}))
    assertEqual(
        harness.text.color.type,
        "selection_color",
        "unknown color descriptor fallback"
    )
end

testFriendlyPlayerClassColorIsPreserved()
testCustomColorIsPreserved()
testOtherColorTypesUseSelectionColor()

print("nameplate_name_class_color_test.lua: ok")
