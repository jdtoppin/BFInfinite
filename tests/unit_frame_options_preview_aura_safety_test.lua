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

local function findIndicator(indicators, name)
    for _, indicator in ipairs(indicators) do
        if type(indicator) == "table" and indicator[2] == name then
            return indicator
        end
    end
end

local function makeHarness()
    local harness = {
        callbacks = {},
    }
    local UF = {
        Parent = {},
        config = {
            general = {enabled = true},
            player = {general = {enabled = true}},
        },
    }
    local AF = {}

    function AF.Copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do
            result[key] = child
        end
        return result
    end

    function AF.CreateMover()
    end

    function AF.RegisterCallback(event, callback)
        harness.callbacks[event] = callback
    end

    function UF.AddToConfigMode()
    end

    function UF.CreateIndicators(frame, indicators)
        harness.liveIndicators = indicators
        frame.indicators = {}
    end

    function UF.CreatePreviewRect()
    end

    function UF.DisableIndicators()
    end

    function UF.SetupUnitFrame()
    end

    local function CreateFrame(frameType, name, parent, template)
        local frame = {
            frameType = frameType,
            name = name,
            parent = parent,
            template = template,
        }

        function frame:Hide()
            self.hidden = true
        end

        function frame:SetAttribute(key, value)
            self[key] = value
        end

        return frame
    end

    local L = setmetatable({}, {
        __index = function(_, key)
            return key
        end,
    })
    local BFI = {
        L = L,
        modules = {
            UnitFrames = UF,
        },
    }
    local environment = {
        _G = false,
        AbstractFramework = AF,
        CreateFrame = CreateFrame,
        ipairs = ipairs,
        pairs = pairs,
        PLAYER = "Player",
        RegisterUnitWatch = function()
        end,
        select = select,
        setmetatable = setmetatable,
        table = table,
        tostring = tostring,
        type = type,
        UnregisterUnitWatch = function()
        end,
    }
    environment._G = environment
    setmetatable(environment, {
        __index = function(_, key)
            error("unexpected Player global: " .. tostring(key), 2)
        end,
    })

    local chunk, loadError =
        loadfile("Modules/UnitFrames/Units/Player.lua")
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)

    harness.UF = UF
    return harness
end

local function testPresetCardsNeverConstructAuraIndicators()
    local harness = makeHarness()
    local preview = harness.UF.previewIndicators

    assertEqual(findIndicator(preview, "buffs"), nil,
        "preset preview buffs descriptor")
    assertEqual(findIndicator(preview, "debuffs"), nil,
        "preset preview debuffs descriptor")

    local update = harness.callbacks.BFI_UpdateModule
    assertTrue(update, "Player update callback was not registered")
    update(nil, "unitFrames", "player", false)

    local live = harness.liveIndicators
    assertTrue(findIndicator(live, "buffs"),
        "live Player buffs descriptor")
    assertTrue(findIndicator(live, "debuffs"),
        "live Player debuffs descriptor")
    assertEqual(#preview, #live - 2,
        "preset preview indicator count")
end

testPresetCardsNeverConstructAuraIndicators()

print("unit frame options preview aura safety tests passed")
