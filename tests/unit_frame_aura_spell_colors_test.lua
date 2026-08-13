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

local function countKeys(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function merge(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            merge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local updateConfigCallback
local AF = {}
local A = {}
local BFI = {
    modules = {
        Auras = A,
    },
}

function AF.Copy(value)
    return copy(value)
end

function AF.Merge(target, source)
    return merge(target, source)
end

function AF.RegisterCallback(event, callback, priority)
    assertEqual(event, "BFI_UpdateConfig", "defaults callback event")
    assertEqual(priority, "high", "defaults callback priority")
    assertEqual(updateConfigCallback, nil, "duplicate defaults callback")
    updateConfigCallback = callback
end

local environment = {
    _G = false,
    AbstractFramework = AF,
    assert = assert,
    error = error,
    math = math,
    next = next,
    pairs = pairs,
    select = select,
    tostring = tostring,
    type = type,
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
            "unexpected spell-color dependency: " .. tostring(key),
            2
        )
    end,
})

local function loadModule(path)
    local chunk, loadError = loadfile(path)
    assertTrue(chunk, loadError)
    setfenv(chunk, environment)
    chunk("BFInfinite", BFI)
end

loadModule("Modules/Auras/Auras.lua")
loadModule("Modules/Auras/Defaults.lua")
assertEqual(type(updateConfigCallback), "function", "defaults callback")

local firstColor = {0.1, 0.2, 0.3, 0.4}
local secondColor = {0.9, 0.8, 0.7, 0.6}
A.config = {
    colors = {
        [774] = firstColor,
        [194384] = secondColor,
    },
}

local firstMap = A.GetNativeSpellColorMap()
assertEqual(countKeys(firstMap), 2, "exact map size")
assertEqual(firstMap[774][1], 0.1, "first exact spell color")
assertEqual(firstMap[194384][4], 0.6, "second exact spell color")
assertEqual(firstMap[155777], nil, "spell family was inferred")
assertTrue(firstMap ~= A.config.colors, "map aliases saved config")
assertTrue(firstMap[774] ~= firstColor, "first color aliases saved config")
assertTrue(
    firstMap[194384] ~= secondColor,
    "second color aliases saved config"
)

firstMap[774][1] = 1
assertEqual(firstColor[1], 0.1, "result mutation reached saved color")
secondColor[4] = 0.25
assertEqual(firstMap[194384][4], 0.6, "saved mutation reached result")

local secondMap = A.GetNativeSpellColorMap()
assertTrue(secondMap ~= firstMap, "map reused across reads")
assertTrue(secondMap[774] ~= firstMap[774], "color reused across reads")

A.config.colors = {
    [100] = {0.1, 0.2, 0.3, 1},
    [0] = {0.1, 0.2, 0.3, 1},
    [-1] = {0.1, 0.2, 0.3, 1},
    [1.5] = {0.1, 0.2, 0.3, 1},
    ["101"] = {0.1, 0.2, 0.3, 1},
    [102] = "red",
    [103] = {0.1, 0.2, 0.3},
    [104] = {0 / 0, 0.2, 0.3, 1},
    [105] = {0.1, math.huge, 0.3, 1},
    [106] = {0.1, 0.2, 0.3, -math.huge},
}
local filteredMap = A.GetNativeSpellColorMap()
assertEqual(countKeys(filteredMap), 1, "invalid entry filtering")
assertEqual(filteredMap[100][4], 1, "valid filtered entry")

A.config = nil
assertEqual(countKeys(A.GetNativeSpellColorMap()), 0, "missing config map")
A.config = {}
assertEqual(countKeys(A.GetNativeSpellColorMap()), 0, "missing colors map")
A.config.colors = "invalid"
assertEqual(countKeys(A.GetNativeSpellColorMap()), 0, "invalid colors map")

environment.BFIConfig = {}
updateConfigCallback(nil, nil)
assertEqual(type(environment.BFIConfig.auras), "table", "auras hydration")
assertEqual(
    type(environment.BFIConfig.auras.colors),
    "table",
    "colors hydration"
)
assertEqual(
    environment.BFIConfig.auras.priorities[980],
    1,
    "priority defaults retained"
)
assertEqual(A.config, environment.BFIConfig.auras, "hydrated config binding")

local savedBlacklist = {
    [700] = true,
}
local savedPriorities = {
    [701] = 9,
}
environment.BFIConfig = {
    auras = {
        blacklist = savedBlacklist,
        priorities = savedPriorities,
    },
}
updateConfigCallback(nil, nil)
assertEqual(
    environment.BFIConfig.auras.blacklist,
    savedBlacklist,
    "blacklist table replaced during colors hydration"
)
assertEqual(
    environment.BFIConfig.auras.priorities,
    savedPriorities,
    "priority table replaced during colors hydration"
)
assertEqual(
    type(environment.BFIConfig.auras.colors),
    "table",
    "missing colors table not hydrated"
)

local colors = environment.BFIConfig.auras.colors
colors[702] = {0.4, 0.3, 0.2, 0.1}
A.ResetToDefaults()
assertEqual(countKeys(colors), 0, "default reset did not clear colors")
assertEqual(
    environment.BFIConfig.auras.blacklist,
    savedBlacklist,
    "default reset replaced blacklist table"
)
assertEqual(savedBlacklist[700], true, "default reset changed blacklist")
assertEqual(
    environment.BFIConfig.auras.priorities,
    savedPriorities,
    "default reset replaced priority table"
)
assertEqual(savedPriorities[701], 9, "default reset changed priorities")

local firstDefaults = A.GetDefaults("colors")
local secondDefaults = A.GetDefaults("colors")
assertTrue(firstDefaults ~= secondDefaults, "color defaults table reused")
firstDefaults[703] = {1, 1, 1, 1}
assertEqual(secondDefaults[703], nil, "color defaults mutation leaked")

print("unit_frame_aura_spell_colors_test.lua: ok")
